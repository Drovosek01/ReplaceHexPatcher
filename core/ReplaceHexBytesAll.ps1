# Example usage in Windows Powershell:
# .\ReplaceHexBytesAll.ps1 -filePath "D:\TEMP\file.exe" -patterns "4883EC28BA2F000000488D0DB0B7380A/11111111111111111111111111111111","C4252A0A48894518488D5518488D4D68/11111111111111111111111111111111","45A8488D55A8488D4D68E8618C1E05BA/1111111111111111111111111111111"

# Main script
param (
    [Parameter(Mandatory)]
    [string]$filePathArg,
    [switch]$makeBackup = $false,
    # One pattern is string with search/replace hex like "AABB/1122" or "AABB,1122" or "\xAA\xBB/\x11\x22" or "A A BB CC|1 12 233"
    [Parameter(Mandatory)]
    [string[]]$patternsArg,
    [string[]]$lastArgs
)

if (-not (Test-Path $filePathArg)) {
    Write-Error "File not found: $filePathArg"
    exit 1
}

if ($patternsArg.Count -eq 0) {
    Write-Error "No patterns given"
    exit 1
}


# =====
# GLOBAL VARIABLES
# =====

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}
[string]$PSBoundParametersStringGlobal = ($PSBoundParameters.GetEnumerator() | ForEach-Object { "-$($_.Key) `"$($_.Value)`"" }) -join " "
[string]$fileNameOfTarget = [System.IO.Path]::GetFileName("$filePathArg")
[string]$tempFolderBaseName = "ReplaceHexBytesAllTmp"
[string]$varNameTempFolder = "ReplaceHexBytesAll"
[string]$varNameFoundIndexes = "ReplaceHexBytesAllFoundIndexes"



# =====
# FUNCTIONS
# =====


<#
.SYNOPSIS
Function for check if for re-write transferred file need admins privileges

.DESCRIPTION
First, we check the presence of the "read-only" attribute and try to remove this attribute.
If it is cleaned without errors, then admin rights are not needed (or they have already been issued to this script).
If there is no "read-only" attribute, then we check the possibility to change the file.
#>
function Test-ReadOnlyAndWriteAccess {
    [OutputType([bool[]])]
    param (
        [string]$filePath
    )
    
    $fileAttributes = Get-Item -Path "$filePath" | Select-Object -ExpandProperty Attributes
    [bool]$isReadOnly = $false
    [bool]$needRunAs = $false

    if ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly) {
        try {
            Set-ItemProperty -Path "$filePath" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
            $isReadOnly = $true
            Set-ItemProperty -Path "$filePath" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
            $needRunAs = $false
        }
        catch {
            $isReadOnly = $true
            $needRunAs = $true
        }
    } else {
        $isReadOnly = $false

        try {
            $stream = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
            $stream.Close()
            $needRunAs = $false
        } catch {
            $needRunAs = $true
        }
    }

    return $isReadOnly, $needRunAs
}


<#
.DESCRIPTION
Function detect if current script run as administrator
and return bool info about it
#>
function DoWeHaveAdministratorPrivileges {
    [OutputType([bool])]
    param ()

    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        return $false
    } else {
        return $true
    }
}


<#
.SYNOPSIS
Function to convert hex string given byte array
#>
function Convert-HexStringToByteArray {
    [OutputType([byte[]])]
    param (
        [string]$hexString
    )

    if ($hexString.Length % 2 -ne 0) {
        throw "Invalid hex string length."
    }

    $byteArray = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $hexString.Length; $i += 2) {
        [void]$byteArray.Add([Convert]::ToByte($hexString.Substring($i, 2), 16))
    }

    return [byte[]]$byteArray
}


<#
.DESCRIPTION
A set of patterns can be passed not as an array, but as 1 line
   this usually happens if this script is called on behalf of the administrator from another Powershell script
In this case, this string becomes the first and only element of the pattern array
We need to divide the string into an array of patterns (extract all patterns from 1 string)
#>
function ExtractPatterns {
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string]$patternsString
    )

    return $patternsString.Replace('"',"").Replace("'","").Split(',')
}


<#
.SYNOPSIS
Function for clean hex string and separate search and replace patterns

.DESCRIPTION
The pattern array contains strings. Each string is a set of bytes to search
    and replace in a non-strict format.
Non-strict means that the presence or absence of spaces between byte values
    is allowed, as well as the presence or absence of "\x" characters denoting 16-bit data.
The value separator for search and replace can be one of the characters: \, /, |

Then all this is divided into 2 arrays - an array with search patterns
    and an array with replacement patterns and return both arrays
#>
function Separate-Patterns {
    [OutputType([System.Collections.ArrayList[]])]
    param (
        [Parameter(Mandatory)]
        [string[]]$patterns
    )
    
    [System.Collections.ArrayList]$searchBytes = New-Object System.Collections.ArrayList
    [System.Collections.ArrayList]$replaceBytes = New-Object System.Collections.ArrayList

    # Separate pattern-string on search and replace strings
    foreach ($pattern in $patterns) {
        # Clean and split string with search and replace hex patterns
        [string[]]$temp = $pattern.Clone().Replace(" ","").Replace("\x","").Replace("\","/").Replace("|","/").ToUpper().Split("/")

        if (-not ($temp.Count -eq 2)) {
            throw "Wrong pattern $pattern and $temp"
        }

        [byte[]]$searchHexPattern = (Convert-HexStringToByteArray -hexString $temp[0])
        [byte[]]$replaceHexPattern = (Convert-HexStringToByteArray -hexString $temp[1])

        [void]$searchBytes.Add($searchHexPattern)
        [void]$replaceBytes.Add($replaceHexPattern)
    }

    return $searchBytes, $replaceBytes
}


<#
.SYNOPSIS
Function to search and replace hex patterns in a binary file

.DESCRIPTION
Loop in given patterns array and search each search-pattern and replace
    all found replace-patterns in given file and re-write file after replace
    patterns if any patterns was found and return indexes found patterns
#>
function SearchAndReplace-HexPatternInBinaryFile {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory)]
        [string]$filePath,
        [string[]]$patterns
    )

    [System.Collections.ArrayList]$searchBytes, [System.Collections.ArrayList]$replaceBytes = Separate-Patterns $patterns

    [byte[]]$fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    [int[]]$foundPatternsIndexes = @()

    # TODO:
    # Re-write for check if need admins rights after first match hex pattern,
    #    not after all patterns will found

    for ($i = 0; $i -lt $patterns.Count; $i++) {
        [int]$searchLength = $searchBytes[$i].Length
        [int]$index = 0
    
        while ($index -lt $fileBytes.Length) {
            $foundIndex = [Array]::IndexOf($fileBytes, $searchBytes[$i][0], $index)
    
            if ($foundIndex -eq -1) {
                break
            }
    
            $match = $true
            for ($x = 1; $x -lt $searchLength; $x++) {
                if ($fileBytes[$foundIndex + $x] -ne $searchBytes[$i][$x]) {
                    $match = $false
                    break
                }
            }
    
            if ($match) {
                [Array]::Copy($replaceBytes[$i], 0, $fileBytes, $foundIndex, $searchLength)
                $index = $foundIndex + $searchLength
                $foundPatternsIndexes += $i
            } else {
                $index = $foundIndex + 1
            }
        }
    }

    # TODO:
    # Need to refactor this part of the code - put it in a separate function.
    # It will be more logical and improve readability.
    # But when the byte array leaves the limits of this function, the speed of the script deteriorates by 3 times.
    # I do not yet know why this is so and how to fix it.

    # Not re-write file if hex-patterns not found in file
    if ($foundPatternsIndexes.Count -gt 0) {
        $isReadOnly, $needRunAS = Test-ReadOnlyAndWriteAccess -filePath $filePath
        $tempFolderForPatchedFilePath = ''

        if ($needRunAS -and !(DoWeHaveAdministratorPrivileges)) {
            # create temp file with replaced bytes
            $folderIndex = 0
            while ($tempFolderForPatchedFilePath.Length -eq 0) {
                $tempPath = "${env:Temp}\$tempFolderBaseName${folderIndex}"

                if (Test-Path "$tempPath") {
                    $folderIndex++
                } else {
                    [void](New-Item -Path "$tempPath" -ItemType Directory)
                    $tempFolderForPatchedFilePath = "$tempPath"
                }
            }

            [System.IO.File]::WriteAllBytes("${tempFolderForPatchedFilePath}\${fileNameOfTarget}", $fileBytes)
    
            # Each pattern can be found many times
            # in this case pattern index will be added in array indexes many times
            # but we need only unique indexes
            $foundPatternsIndexes = ($foundPatternsIndexes | Select-Object -Unique)

            # relaunch current script in separate process with Admins privileges
            [string]$lastArgsForProcess = "$varNameTempFolder=`"$tempFolderForPatchedFilePath`",$varNameFoundIndexes=`"$($foundPatternsIndexes -join ' ')`""
            Start-Process -Verb RunAs $PSHost ("-ExecutionPolicy Bypass -File `"$PSCommandPath`" $PSBoundParametersStringGlobal -lastArgs $lastArgsForProcess")
            break
        } else {
            $fileAcl = Get-Acl "$filePath"
            $fileAttributes = Get-Item -Path "$filePath" | Select-Object -ExpandProperty Attributes
            [string]$backupFullName = "$filePath.bak"

            KillExeTasks $filePath

            if ($isReadOnly) {
                Set-ItemProperty -Path "$filePath" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
            }

            if ($makeBackup) {
                if (Test-Path $backupFullName) {
                    Set-ItemProperty -Path "$backupFullName" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
                }

                Copy-Item -Path "$filePath" -Destination "$backupFullName"
        
                if ($isReadOnly) {
                    Set-ItemProperty -Path "$backupFullName" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
                }
                $fileAcl | Set-Acl "$backupFullName"
            }
            
            [System.IO.File]::WriteAllBytes("$filePath", $fileBytes)
            
            $fileAcl | Set-Acl "$filePath"
        }
        
        if ($isReadOnly) {
            Set-ItemProperty -Path "$filePath" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
        }
    }

    if ($foundPatternsIndexes.Count -eq 0) {
        # It need for prevent error when pass empty array to function
        $foundPatternsIndexes = @(-1)
    }

    return $foundPatternsIndexes
}

<#
.DESCRIPTION
This function will be called only if the script is restarted on behalf of the administrator.
When restarting as an administrator, the patched file is saved to a temporary folder so as not to search for all the templates again.
This function replaces the original file with a previously saved patched file from a temporary folder
#>
function Replace-TempPatchedFileIfExist {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$filePath,
        [Parameter(Mandatory)]
        [string]$tempFolderForPatchedFilePath
    )

    $isReadOnly, $needRunAS = Test-ReadOnlyAndWriteAccess -filePath $filePath
    $fileAttributes = Get-Item -Path "$filePath" | Select-Object -ExpandProperty Attributes
    $fileAcl = Get-Acl "$filePath"
    [string]$backupFullName = "$filePath.bak"

    KillExeTasks $filePath
    
    if ($isReadOnly) {
        Set-ItemProperty -Path "$filePath" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
    }
    
    if ($makeBackup) {
        if (Test-Path $backupFullName) {
            Set-ItemProperty -Path "$backupFullName" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
        }

        Copy-Item -Path "$filePath" -Destination "$backupFullName"
        
        if ($isReadOnly) {
            Set-ItemProperty -Path "$backupFullName" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
        }
        $fileAcl | Set-Acl "$backupFullName"
    }

    # check exist temp folder for backuped patched file and just move backuped file
    # or re-write existing file
    [string]$patchedTempFile = "$tempFolderForPatchedFilePath\$fileNameOfTarget"
    if (Test-Path "$patchedTempFile") {
        Remove-Item -Path $filePath

        KillExeTasks $patchedTempFile
        Move-Item -Path $patchedTempFile -Destination $filePath
        $fileAcl | Set-Acl "$filePath"
        Remove-Item "$tempFolderForPatchedFilePath"
    
        if ($isReadOnly) {
            Set-ItemProperty -Path "$filePath" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
        }

        return $true
    } else {
        if ($isReadOnly) {
            Set-ItemProperty -Path "$filePath" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
        }

        return $false
    }
}

<#
.SYNOPSIS
Kill the process that occupies the target file
#>
function KillExeTasks {
    param (
        [Parameter(Mandatory)]
        [string]$targetPath
    )

    if (($targetPath.Length -eq 0) -or (-not (Test-Path $targetPath))) {
        return
    }
    
    $targetName = [System.IO.Path]::GetFileNameWithoutExtension($targetPath)

    $process = Get-Process -Name $targetName -ErrorAction SilentlyContinue

    if ($process) {
        try {
            Stop-Process -Name $targetName -Force
        }
        catch {
            if (-not (DoWeHaveAdministratorPrivileges)) {
                $processId = Start-Process $PSHost -Verb RunAs -PassThru -Wait -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"Stop-Process -Name '$targetName' -Force`""

                if ($processId.ExitCode -gt 0) {
                    throw "Something happened wrong when try kill process with target file"
                }
            }
    
        }
    }
}

<#
.SYNOPSIS
Show info about found+replaced or not found patterns
#>
function HandleReplacedPatternsIndexes {
    param (
        [Parameter(Mandatory)]
        [string[]]$patterns,
        [Parameter(Mandatory)]
        [int[]]$replacedPatternsIndexes
    )
    
    [string]$notFoundPatterns = ''

    if ($replacedPatternsIndexes.Count -eq 0 -OR ($replacedPatternsIndexes.Count -eq 1 -AND $replacedPatternsIndexes[0] -eq -1)) {
        Write-Host "No patterns was found in $filePathArg"
    }
    elseif ($replacedPatternsIndexes.Count -eq $patterns.Count) {
        Write-Host "All hex patterns found and replaced successfully in $filePathArg"
    }
    else {
        [int[]]$notReplacedPatternsIndexes = (0..$patterns.Count).Where({$_ -notin $replacedPatternsIndexes})
        for ($i = 0; $i -lt $notReplacedPatternsIndexes.Count; $i++) {
            $notFoundPatterns += ' ' + $patterns[$notReplacedPatternsIndexes[$i]]
        }
        Write-Host "Hex patterns" $notFoundPatterns.Trim() "- not found, but other given patterns found and replaced successfully in $filePathArg" 
    }
}



# =====
# MAIN
# =====

$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    Write-Host Start searching patterns...

    [string[]]$patterns = @()
    if ($patternsArg.Count -eq 1) {
        # Maybe all patterns written in 1 string if first array item and we need handle it
        $patterns = ExtractPatterns $patternsArg[0]
    } else {
        $patterns = $patternsArg
    }

    # The last unnamed argument can be the path to an already patched file stored in a temporary folder.
    # This is done so as not to patch the file again (if it has already been patched) when restarting the script on behalf of the administrator.
    # Therefore, if the last argument is the path to the file, then this is already a patched file and we just need to replace the original file with it.
    if ($lastArgs -and ($lastArgs.Count -gt 0)) {
        [string]$tempFolderPath = ''
        [int[]]$replacedPatternsIndexes = @()
        [string[]]$lastArgsSeparated = $lastArgs[0].Split(',')

        foreach ($arg in $lastArgsSeparated) {
            $varName = $arg.Split('=')[0]
            if ($varName.Trim() -eq $varNameTempFolder) {
                $tempFolderPath = $arg.Split('=')[1]
            }
            if ($varName.Trim() -eq $varNameFoundIndexes) {
                $replacedPatternsIndexes = ($arg.Split('=')[1]).Split(' ') | foreach { [int]$_ }
            }
        }

        [bool]$isTempPatchedFileReplaced = Replace-TempPatchedFileIfExist "$filePathArg" "$tempFolderPath"

        if (!$isTempPatchedFileReplaced) {
            Write-Error "Temp patched file not found but should be"
            exit 1
        }
    } else {
        if ((Test-Path variable:filePathArg) -and ($filePathArg.Length -gt 0) -and (Test-Path variable:patterns) -and ($filePathArg.Length -gt 0)) {
            $replacedPatternsIndexes = SearchAndReplace-HexPatternInBinaryFile -filePath $filePathArg -patterns $patterns
        } else {
            throw "Not given path for file for patch or patterns"
        }
    }

    HandleReplacedPatternsIndexes $patterns $replacedPatternsIndexes
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$watch.Stop()
Write-Host "Script execution time is" $watch.Elapsed # time of execution code

# Pause before exit like in CMD
Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');