# Example usage in Windows Powershell:
# .\ReplaceHexBytesAll.ps1 -filePath "D:\TEMP\file.exe" -patterns "4883EC28BA2F????00??8D0DB0B7380A/11111111111111111111111111111111","C4 25 2A 0A 48 89 45 18 48 8D 55 18 48 8D 4D ?? /     1111 111111    111111 1111111111111111","\x45\xA8\x48\x8D\x55\xA8\x48\x8D\x4D\x68\xE8\x61\x8C\x1E\x05\xBA/\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11" -makeBackup

# Main script
param (
    [Parameter(Mandatory)]
    [string]$filePath,
    [switch]$makeBackup = $false,
    # One pattern is string with search/replace hex like "AABB/1122" or "\xAA\xBB/\x11\x22" or "A A BB CC|1 12 233"
    [Parameter(Mandatory)]
    [string[]]$patterns,
    [string[]]$lastArgs
)

if (-not (Test-Path $filePath)) {
    Write-Error "File not found: $filePath"
    exit 1
}

if ($patterns.Count -eq 0) {
    Write-Error "No patterns given"
    exit 1
}


# =====
# GLOBAL VARIABLES
# =====

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}
[string]$PSBoundParametersStringGlobal = ($PSBoundParameters.GetEnumerator() | ForEach-Object {
    if ($_.Value -is [array]) {
        # If value is array - it array with patterns and we need concat it to 1 string
        $tempValue = $_.Value -join ','
        return "-$($_.Key) `"$tempValue`""
    }

    if (Test-Path $_.Value) {
        $tempValue = [System.IO.Path]::GetFullPath($_.Value)
        return "-$($_.Key) `"$tempValue`""
    }

    return "-$($_.Key) `"$($_.Value)`""
}) -join " "

[string]$filePathFull = [System.IO.Path]::GetFullPath($filePath)


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
        [string]$targetPath
    )
    
    $fileAttributes = Get-Item -Path "$targetPath" -Force | Select-Object -ExpandProperty Attributes
    [bool]$isReadOnly = $false
    [bool]$needRunAs = $false

    if ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly) {
        try {
            Set-ItemProperty -Path "$targetPath" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
            $isReadOnly = $true
            Set-ItemProperty -Path "$targetPath" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
            $needRunAs = $false
        }
        catch {
            $isReadOnly = $true
            $needRunAs = $true
        }
    } else {
        $isReadOnly = $false

        try {
            $stream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
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
Function for convert given hex string to bytes array
#>
function Convert-HexStringToByteArray {
    [OutputType([byte[]])]
    param (
        [string]$hexString
    )

    if ($hexString.Length % 2 -ne 0) {
        throw "Invalid hex string length of $hexString"
    }

    [System.Collections.Generic.List[byte]]$byteArray = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $hexString.Length; $i += 2) {
        try {
            [void]($byteArray.Add([Convert]::ToByte($hexString.Substring($i, 2), 16)))
        }
        catch {
            Write-Error "Looks like we have not hex symbols in $hexString"
            exit 1
        }
    }

    return [byte[]]$byteArray.ToArray()
}


<#
.DESCRIPTION
Function get string that contain hex symbols and wildcards (??) symbols
and return 2 arrays:
Second array is "true" array of bytes (wildcards symbols replaced with '0')
First array is indexes where wildcards will placed in array bytes
#>
function Convert-HexStringToByteArrayWithWildcards {
    [OutputType([array])]
    param (
        [string]$hexString
    )

    if (-not $hexString.Contains('?')) {
        [byte[]]$byteArray = Convert-HexStringToByteArray $hexString

        return @(), $byteArray
    }

    [System.Collections.Generic.List[int]]$wildcardsIndexes = New-Object System.Collections.Generic.List[int]

    [string]$tempHexString = $hexString.Clone()
    [int]$wildcardPosition = $tempHexString.IndexOf('??')

    while ($wildcardPosition -ne -1) {
        if (($wildcardPosition % 2) -eq 0) {
            $wildcardsIndexes.Add($wildcardPosition / 2)
            # replace wildcards symbols to any hex symbol for skip search found index
            $tempHexString = $tempHexString.Remove($wildcardPosition, 2).Insert($wildcardPosition, '00')
            $wildcardPosition = $tempHexString.IndexOf('??')
        } else {
            Write-Error "Looks like $hexString is wrong hex pattern because wildcard (??) is not in an even position"
            exit 1
        }
    }

    [byte[]]$byteArray = Convert-HexStringToByteArray $tempHexString

    return $wildcardsIndexes.ToArray(), $byteArray
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
    [OutputType([array])]
    param (
        [Parameter(Mandatory)]
        [string[]]$patternsArray
    )
    
    [System.Collections.Generic.List[byte[]]]$searchBytes = New-Object System.Collections.Generic.List[byte[]]
    [System.Collections.Generic.List[int[]]]$wildcardsIndexes = New-Object System.Collections.Generic.List[int[]]
    [System.Collections.Generic.List[byte[]]]$replaceBytes = New-Object System.Collections.Generic.List[byte[]]

    # Separate pattern-string on search and replace strings
    foreach ($pattern in $patternsArray) {
        # Clean and split string with search and replace hex patterns
        [string[]]$temp = $pattern.Clone().Replace(" ","").Replace("\x","").Replace("\","/").Replace("|","/").ToUpper().Split("/")

        if (-not ($temp.Count -eq 2)) {
            throw "Wrong pattern $pattern and $temp"
        }
        
        if ($temp[0].Replace('??', '').Trim().Length -eq 0) {
            throw "Looks like search pattern $pattern[0] contain only wildcards. Specify the bytes that need to be searched for."
        }
        
        if ($temp[1].Replace('??', '').Trim().Length -eq 0) {
            throw "Looks like replace pattern $pattern[1] contain only wildcards. Specify the bytes that need to be searched for."
        }

        [int[]]$wildcards, [byte[]]$searchHexPattern = (Convert-HexStringToByteArrayWithWildcards -hexString $temp[0])
        [byte[]]$replaceHexPattern = (Convert-HexStringToByteArray -hexString $temp[1])

        [void]($searchBytes.Add($searchHexPattern))
        [void]($wildcardsIndexes.Add($wildcards))
        [void]($replaceBytes.Add($replaceHexPattern))
    }

    return $searchBytes, $wildcardsIndexes, $replaceBytes
}


<#
.DESCRIPTION
Getting the path to the file
and return absolute path for temp file in same folder
#>
function Get-UniqTempFileName {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$targetPath
    )
    
    [string]$tempFilePath = "$targetPath.temp"
    while (-not (Test-Path $tempFilePath)) {
        if (-not (Test-Path $tempFilePath)) {
            break
        }

        $tempFilePath += (Get-Random -Maximum 10)
    }
    
    return $tempFilePath
}


<#
.DESCRIPTION
Check attribute and permission for target file and handle search + replace patterns
#>
function Apply-HexPatternInBinaryFile {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory)]
        [string]$targetPath,
        [Parameter(Mandatory)]
        [string[]]$patternsArray,
        [Parameter(Mandatory)]
        [bool]$needMakeBackup
    )

    [string]$backupAbsoluteName = "$targetPath.bak"
    [string]$backupTempAbsoluteName = Get-UniqTempFileName -targetPath $targetPath
    [System.Collections.Generic.List[int]]$foundPatternsIndexes = New-Object System.Collections.Generic.List[int]

    $isReadOnly, $needRunAS = Test-ReadOnlyAndWriteAccess $targetPath

    KillExeTasks $targetPath

    if ($needRunAS -and !(DoWeHaveAdministratorPrivileges)) {
        # relaunch current script in separate process with Admins privileges
        Start-Process -Verb RunAs $PSHost ("-ExecutionPolicy Bypass -File `"$PSCommandPath`" $PSBoundParametersStringGlobal")
        break
    }

    $fileAcl = Get-Acl "$targetPath"
    $fileAttributes = Get-Item -Path "$targetPath" -Force | Select-Object -ExpandProperty Attributes


    if ($isReadOnly) {
        Set-ItemProperty -Path "$targetPath" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
    }

    if ($needMakeBackup) {
        # Make temp backup file
        Copy-Item -Path "$targetPath" -Destination "$backupTempAbsoluteName" -Force
    }


    $foundPatternsIndexes = SearchAndReplace-HexPatternInBinaryFile -targetPath $targetPath -patternsArray $patternsArray


    # restore file permissions
    $fileAcl | Set-Acl "$targetPath"

    # restore attribute "Read Only" if it was
    if ($isReadOnly) {
        Set-ItemProperty -Path "$targetPath" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
    }

    if ((($foundPatternsIndexes -is [array]) -and ($foundPatternsIndexes.Count -eq 0)) -or ($foundPatternsIndexes -is [int])) {
        # It need for prevent error when pass empty array to function
        [void]($foundPatternsIndexes.Add(-1))

        # If no patterns found - backuped file was just duplicate original file
        # no need backup file because original file was not modified
        if ($needMakeBackup) {
            Remove-Item -Path $backupTempAbsoluteName -Force
        }
    } else {
        # if target file patched we need rename temp backuped file to "true" backuped file
        # and restore attributes and permissions

        if ($needMakeBackup) {
            if (Test-Path $backupAbsoluteName) {
                try {
                    $fileAttributesForBackup = Get-Item -Path "$backupAbsoluteName" -Force | Select-Object -ExpandProperty Attributes
                    
                    # remove "Read Only" attribute from exist backuped file
                    Set-ItemProperty -Path "$backupAbsoluteName" -Name Attributes -Value ($fileAttributesForBackup -bxor [System.IO.FileAttributes]::ReadOnly)
                    Remove-Item -Path "$backupAbsoluteName" -Force
                }
                catch {
                    # IMPORTANT !!!
                    # Do not formate this command and not re-write it
                    # it need for add multiline string to Start-Process command
                    $command = @"
$fileAttributesForBackup = Get-Item -Path '$backupAbsoluteName' -Force | Select-Object -ExpandProperty Attributes
Set-ItemProperty -Path '$backupAbsoluteName' -Name Attributes -Value ('$fileAttributesForBackup' -bxor [System.IO.FileAttributes]::ReadOnly)
Remove-Item -Path '$backupAbsoluteName' -Force
"@

                    # Start-Process $PSHost -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"$command`""
                    $processId = Start-Process $PSHost -Verb RunAs -PassThru -Wait -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -Command `"$command`""

                    if ($processId.ExitCode -gt 0) {
                        throw "Something happened wrong when try remove previously backuped file"
                    }
                }
            }

            # with copying it wil be replaced
            Rename-Item -Path "$backupTempAbsoluteName" -NewName "$backupAbsoluteName" -Force

            # restore attribute "Read Only" if it was on original file
            if ($isReadOnly) {
                Set-ItemProperty -Path "$backupAbsoluteName" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
            }

            # restore file permissions
            $fileAcl | Set-Acl "$backupAbsoluteName"
        }
    }

    return [int[]]$foundPatternsIndexes.ToArray()
}


<#
.SYNOPSIS
Return index first bytes not matched with index wildcard
#>
function Get-IndexFirstTrueByte {
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[byte]]$hexBytes,
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[int]]$wildcardsIndexes
    )

    if ($wildcardsIndexes.Count -eq 0) {
        return 0
    }

    for ($i = 0; $i -lt $hexBytes.Count; $i++) {
        if ($wildcardsIndexes.Contains($i)) {
            continue
        } else {
            return $i
        }
    }
}


<#
.SYNOPSIS
Function to search and replace hex patterns in a binary file

.DESCRIPTION
Loop in given patterns array and search each search-pattern and replace
    all found replace-patterns in given file
    and return indexes found patterns from given patterns array 
#>
function SearchAndReplace-HexPatternInBinaryFile {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory)]
        [string]$targetPath,
        [Parameter(Mandatory)]
        [string[]]$patternsArray
    )

    [System.Collections.Generic.List[byte[]]]$searchBytes, [System.Collections.Generic.List[int[]]]$wildcardsIndexes, [System.Collections.Generic.List[byte[]]]$replaceBytes = Separate-Patterns $patternsArray

    try {
        $stream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
    }
    catch {
        # If error when read file it looks like we have not rights
        # and we need request admin privileges - re-launch script with admin privileges
        Start-Process -Verb RunAs $PSHost ("-ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`" $PSBoundParametersStringGlobal")
        break
    }
    [System.Collections.Generic.List[int]]$foundPatternsIndexes = New-Object System.Collections.Generic.List[int]

    [int]$bufferSize = [System.UInt16]::MaxValue
    $stream.Position = 0
    
    for ($p = 0; $p -lt $patternsArray.Count; $p++) {
        [int]$position = 0
        [int]$bytesRead = 0
        [byte[]]$buffer = New-Object byte[] ($bufferSize + $searchBytes[$p].Length - 1)
        [void]($stream.Seek(0, [System.IO.SeekOrigin]::Begin))
        [int]$searchLength = $searchBytes[$p].Length

        # check if we have wildcards
        if ($wildcardsIndexes.GetType().FullName.Contains('System.Collections.Generic.List') -and ($wildcardsIndexes.Count -gt 0)) {
            [int]$indexFirstTrueByte = Get-IndexFirstTrueByte -hexBytes $searchBytes[$p] -wildcardsIndexes $wildcardsIndexes[$p]
        } else {
            [int]$indexFirstTrueByte = 0
        }

        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [int]$index = 0
            
            while ($index -le ($bytesRead - $searchLength)) {
                [int]$foundIndex = [Array]::IndexOf($buffer, $searchBytes[$p][$indexFirstTrueByte], $index)

                if ($foundIndex -eq -1) {
                    break
                }
                
                # start position for paste "replace bytes" if "search bytes" will match
                [int]$fixedFoundIndex = $foundIndex - $indexFirstTrueByte
                
                # If fixedFoundIndex goes beyond the initial file boundary
                # so the found index is not suitable for us - increase loop index and go to next loop iteration
                if (($position -eq 0) -and (($index - [math]::Abs($fixedFoundIndex)) -lt 0)) {
                    $index++
                    continue
                }
        
                $match = $true
                for ($x = 1; $x -lt $searchLength; $x++) {
                    if ($wildcardsIndexes[$p].Contains($x)) {
                        continue
                    }
                    if ($buffer[$fixedFoundIndex + $x] -ne $searchBytes[$p][$x]) {
                        $match = $false
                        break
                    }
                }
                
                if ($match) {
                    [void]($stream.Seek($position + $fixedFoundIndex, [System.IO.SeekOrigin]::Begin))
                    $stream.Write($replaceBytes[$p], 0, $replaceBytes[$p].Length)
                    $index = $foundIndex + $searchLength
                    [void]($foundPatternsIndexes.Add($p))
                } else {
                    $index = $foundIndex + 1
                }
            }

            $position += $bytesRead - $searchLength + 1
            if ($position -gt ($stream.Length - $searchLength)) {
                break
            }
            [void]($stream.Seek($position, [System.IO.SeekOrigin]::Begin))
        }
    }    

    $stream.Close()

    if ($foundPatternsIndexes.Count -eq 0) {
        # It need for prevent error when pass empty array to function
        [void]($foundPatternsIndexes.Add(-1))
    }

    return [int[]]$foundPatternsIndexes.ToArray()
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

    # TODO:
    # Also need good way for kill process blocked access to file if file not launched

    if (($targetPath.Length -eq 0) -or (-not (Test-Path $targetPath))) {
        return
    }
    
    $targetName = [System.IO.Path]::GetFileNameWithoutExtension($targetPath)

    $process = Get-Process | ForEach-Object {
        if ($_.Path -eq $targetPath) {
            return $_.Path -eq $targetPath
        }
    }

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
        [string[]]$patternsArray,
        [Parameter(Mandatory)]
        [int[]]$replacedPatternsIndexes
    )
    
    # Each pattern can be found many times
    # in this case pattern index will be added in array indexes many times
    # but we need only unique indexes
    [int[]]$replacedPatternsIndexesCleaned = ($replacedPatternsIndexes | Select-Object -Unique)

    [string]$notFoundPatterns = ''

    if ($replacedPatternsIndexesCleaned.Count -eq 0 -OR ($replacedPatternsIndexesCleaned.Count -eq 1 -AND $replacedPatternsIndexesCleaned[0] -eq -1)) {
        Write-Host "No patterns was found in $filePathFull"
    }
    elseif ($replacedPatternsIndexesCleaned.Count -eq $patternsArray.Count) {
        Write-Host "All hex patterns found and replaced successfully in $filePathFull"
    }
    else {
        [int[]]$notReplacedPatternsIndexes = (0..($patternsArray.Count-1)).Where({$_ -notin $replacedPatternsIndexesCleaned})
        if ($notReplacedPatternsIndexes.Count -gt 0) {
            for ($i = 0; $i -lt $notReplacedPatternsIndexes.Count; $i++) {
                $notFoundPatterns += ' ' + $patternsArray[$notReplacedPatternsIndexes[$i]]
            }
            Write-Host "Hex patterns" $notFoundPatterns.Trim() "- not found, but other given patterns found and replaced successfully in $filePathFull" 
        }
    }
}



# =====
# MAIN
# =====

$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    Write-Host Start searching patterns...

    [string[]]$patternsExtracted = @()
    if ($patterns.Count -eq 1) {
        # Maybe all patterns written in 1 string if first array item and we need handle it
        $patternsExtracted = ExtractPatterns $patterns[0]
    } else {
        $patternsExtracted = $patterns
    }

    $replacedPatternsIndexes = Apply-HexPatternInBinaryFile -targetPath $filePathFull -patterns $patternsExtracted -needMakeBackup $makeBackup

    HandleReplacedPatternsIndexes $patternsExtracted $replacedPatternsIndexes
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$watch.Stop()
Write-Host "Script execution time is" $watch.Elapsed # time of execution code

# Pause before exit like in CMD
Write-Host -NoNewLine "Press any key to continue...`r`n";
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');