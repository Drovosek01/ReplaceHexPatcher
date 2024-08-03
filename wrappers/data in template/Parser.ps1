param (
    [Parameter(Mandatory)]
    [string]$templatePath
)


# =====
# GLOBAL VARIABLES
# =====

# Same splitter like in core script
$patternSplitters = @('/','\','|')

$comments = @(';', '::')



# =====
# FUNCTIONS
# =====


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
.DESCRIPTION
Remove comments from text template
and replace template variables with text
and remove empty lines
and return cleaned template content
#>
function CleanTemplate {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$filePath
    )
    $content = [System.IO.File]::ReadAllLines($filePath, [System.Text.Encoding]::UTF8)

    # Remove lines with comments
    foreach ($comment in $comments) {
        $content = $content | select-string -pattern $comment -notmatch
    }

    # Remove empty lines + convert each line to string with trim
    $content = $content | Where-Object { -not [String]::IsNullOrWhiteSpace($_) } | ForEach-Object { ($_.Line).Trim() }
    # Replace $USER to current username
    $content = $content -ireplace '\$USER', "$env:USERNAME"

    return ($content -join "`n")
}


<#
.SYNOPSIS
Function for extract text between start and end named section edges

.DESCRIPTION
Get templateContent and sectionName and return text
between [start-sectionName] and [end-sectionName]
#>
function ExtractContent {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$templateContent,
        [Parameter(Mandatory)]
        [string]$sectionName
    )

    $start = $templateContent.IndexOf("[start-$sectionName]")+"[start-$sectionName]".Length
    $end = $templateContent.IndexOf("[end-$sectionName]")

    $contentSection = $templateContent.Substring($start, $end-$start).Trim()

    return $contentSection
}


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
Function get path to ps1 file, patch target-file and patterns array etc
and run receive ps1 file and pass given arguments to ran script
#>
function RunPSFile {
    param (
        [Parameter(Mandatory)]
        [string]$psFile,
        [Parameter(Mandatory)]
        [string]$targetFile,
        [Parameter(Mandatory)]
        [string]$patterns
    )

    $patterns = $patterns -replace ',"$',""

    # The only .ps1 file that needs to be run from template is the patcher (main/core file)
    # Previously there was additional code here to run the process as administrator or as usual, depending on different conditions
    # But the logic of restarting on behalf of the administrator has been added to the script patcher.
    # It looks like it makes no sense to repeat the logic of checking startup as an administrator (but this is not accurate),
    #   but if necessary, run others.ps1 files, then you will need to return the logic of the conditions to run as administrator

    $PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}
    $process = Start-Process $PSHost -ArgumentList "-File `"$psFile`" -filePath `"$targetFile`" -patterns", "$patterns" -PassThru -Wait

    if ($process.ExitCode -gt 0) {
        throw "Something happened wrong when patching file $targetFile"
    }
}


<#
.DESCRIPTION
Function gets a text with lines loop all lines
if detect valid path then all next lines concat like patterns until detect other path or end text
then form path to target file and search/replace patterns and send it to function with run patcher script
#>
function DetectFilesAndPatternsAndPatch {
    param (
        [Parameter(Mandatory)]
        [string]$patcherFile,
        [Parameter(Mandatory)]
        [string]$templateContent,
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$variables
    )

    [string]$cleanedContent = $templateContent.Clone()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    [string]$filePathArg = ''
    [string]$patternsArg = '"'

    [bool]$isSearchPattern = $true

    foreach ($line in $cleanedContent -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()
        if (Test-Path "$line" 2>$null) {
            if ($patternsArg.Length -gt 1) {
                RunPSFile "$patcherFile" "$filePathArg" $patternsArg
                $filePathArg = "$line"
                $patternsArg = '"'
            } else {
                $filePathArg = "$line"
            }
        } else {
            # if it ready search+replace pattern - add it to all patterns string
            # and continue lines loop
            if ($patternSplitters.ForEach("$line".Contains($_))) {
                $patternsArg += "$line`",`""
                continue
            }

            # else it not ready pattern and need
            # concat search then replace patterns on each iteration
            if ($isSearchPattern) {
                $patternsArg += "$line/"
                $isSearchPattern = $false
            } else {
                $patternsArg += "$line`",`""
                $isSearchPattern = $true
            }
        }
    }

    if ($patternsArg.Length -gt 1) {
        if ($filePathArg) {
            RunPSFile "$patcherFile" "$filePathArg" $patternsArg
        } else {
            Write-Error "No valid targets or patterns was found"
            exit 1
        }
    }
}

<#
.SYNOPSIS
Return True if last line empty or contain spaces/tabs only
#>
function isLastLineEmptyOrSpaces {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        $content
    )
    
    if ($content -is [string]) {
        return (($content -split "`r`n|`n")[-1].Trim() -eq "")
    } elseif ($content -is [array]) {
        return ($content[$content.Length - 1].Trim() -eq "")
    } else {
        Write-Error "Given variable is not string or array for detect last line"
        exit 1
    }
}


<#
.DESCRIPTION
Handle content from template, if in just URL so add zeroIP before URL,
and make other checks
then formate these lines to string and return formatted string
#>
function CombineLinesForHosts {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$templateContent
    )
    
    [string]$localhostIP = '127.0.0.1'
    [string]$zeroIP = '0.0.0.0'
    [string]$notModifyFlag = 'NOT MODIFY IT'
    
    [string]$contentForAddToHosts = ''

    [string[]]$templateContentLines = $templateContent -split "\n"

    if ($templateContentLines[0].Trim().ToUpper() -eq $notModifyFlag) {
        foreach ($line in $templateContentLines) {
            # Trim line is important because end line include \n
            $line = $line.Trim()
            if ($line -eq $notModifyFlag) {
                continue
            }

            $contentForAddToHosts += $line + "`r`n"
        }
    } else {
        foreach ($line in $templateContent -split "\n") {
            # Trim line is important because end line include \n
            $line = $line.Trim()
            if ($line.StartsWith('#') -OR $line.StartsWith($localhostIP)) {
                $contentForAddToHosts += $line + "`r`n"
            } else {
                $contentForAddToHosts += $zeroIP + ' ' + $line + "`r`n"
            }
        }
        $contentForAddToHosts = $contentForAddToHosts.Replace($localhostIP, $zeroIP)
    }

    return $contentForAddToHosts.Trim()
}


<#
.SYNOPSIS
Handle content from template section and add it to hosts file
#>
function AddToHosts {
    param (
        [Parameter(Mandatory)]
        [string]$templateContent
    )

    $needRemoveReadOnly = $false

    [string]$hostsFilePath = [System.Environment]::SystemDirectory + "\drivers\etc\hosts"
    $fileAttributes = Get-Item -Path $hostsFilePath | Select-Object -ExpandProperty Attributes

    [string]$contentForAddToHosts = CombineLinesForHosts $templateContent

    if (Test-Path "$hostsFilePath" 2>$null) {
        # If hosts file exist check if last line hosts file empty
        # and add indents from the last line hosts file to new content
        if (isLastLineEmptyOrSpaces ([System.IO.File]::ReadAllText($hostsFilePath))) {
            $contentForAddToHosts = "`r`n" + $contentForAddToHosts
        } else {
            $contentForAddToHosts = "`r`n`r`n" + $contentForAddToHosts
        }

        # If file have attribute "read only" remove this attribute for made possible patch file
        if ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly) {
            $needRemoveReadOnly = $true
        } else {
            $needRemoveReadOnly = $false
        }

        if (DoWeHaveAdministratorPrivileges) {
            write-host Yes we have rights
            if ($needRemoveReadOnly) {
                Set-ItemProperty -Path $hostsFilePath -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
            }
            Add-Content -Value $contentForAddToHosts -Path $hostsFilePath
            # Return readonly attribute if it was
            if ($needRemoveReadOnly) {
                Set-ItemProperty -Path $hostsFilePath -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
                $needRemoveReadOnly = $false
            }
        } else {
            # IMPORTANT !!!
            # Do not formate this command and not re-write it
            # it need for add multiline string to Start-Process command
            $command = @"
Add-Content -Path $hostsFilePath -Value @'
$contentForAddToHosts 
'@
"@
            if ($needRemoveReadOnly) {
                # If hosts file have attribute "read only" we need remove this attribute before adding lines
                # and restore "default state" (add this attribute to hosts file) after lines to hosts was added
                $command = "Set-ItemProperty -Path '$hostsFilePath' -Name Attributes -Value ('$fileAttributes' -bxor [System.IO.FileAttributes]::ReadOnly)" `
                + "`n" `
                + $command `
                + "`n" `
                + "Set-ItemProperty -Path '$hostsFilePath' -Name Attributes -Value ('$fileAttributes' -bor [System.IO.FileAttributes]::ReadOnly)"
            }
            Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"$command`""
        }
    } else {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"Set-Content -Value `"$contentForAddToHosts`" -Path `"$hostsFilePath`"`""
    }

}


<#
.SYNOPSIS
Extract variables and values from give content and return hashtable with it
#>
function GetVariables {
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter(Mandatory)]
        [string]$templateContent
    )

    $variables = @{}

    foreach ($line in $templateContent -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()
        if (-not ($line.Contains('='))) {
            continue
        } else {
            $tempSplitLine = $line.Split("=")
            $variables.Add($tempSplitLine[0].Trim(),$tempSplitLine[1].Trim())
        }
    }

    return $variables
}


<#
.DESCRIPTION
Function get a text with lines and detect valid path to .ps1 file or url
and if first valid line is url - download script from url to temp file
and return path to script file
or throw error if no one valid path or url was detected
#>
function GetPatcherFile {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$templateContent
    )

    foreach ($line in $templateContent -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()
        if ($line -like "http*") {
            if ((Invoke-WebRequest -UseBasicParsing -Uri $line).StatusCode -eq 200) {
                [string]$tempFile = [System.IO.Path]::GetTempFileName()
                Get-Process | Where-Object {$_.CPU -ge 1} | Out-File $tempFile
                (New-Object System.Net.WebClient).DownloadFile($line,$tempFile)
                $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf("."))+".ps1")
                Rename-Item $tempFile $renamedTempFile
                return $renamedTempFile
            }
        } else {
            if ((Test-Path "$line" -PathType Leaf 2>$null) -and ("$line".EndsWith(".ps1"))) {
                return "$line"
            }
        }
    }
    
    Write-Error "No valid URL for patcher or paths for file-patcher in template"
    exit 1
}

<#
.DESCRIPTION
The path to the template is passed as an argument to this script.
This can be the path to a file on your computer or the URL to the template text.
This function checks for the presence of a file on the computer if it is the path to the file,
    or creates a temporary file and downloads a template from the specified URL into it
#>
function GetTemplateFile {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$templateWay
    )

    if (Test-Path $templateWay 2>$null) {
        return (Get-ChildItem $templateWay).FullName
    } elseif ((Invoke-WebRequest -UseBasicParsing -Uri $templateWay).StatusCode -eq 200) {
        [string]$tempFile = [System.IO.Path]::GetTempFileName()
        Get-Process | Where-Object {$_.CPU -ge 1} | Out-File $tempFile
        (New-Object System.Net.WebClient).DownloadFile($templateWay,$tempFile)
        $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf("."))+".txt")
        Rename-Item $tempFile $renamedTempFile
        return (Get-ChildItem $renamedTempFile).FullName
    }
    
    Write-Error "No valid template path or URL was provided"
    exit 1
}



# =====
# MAIN
# =====


$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    [string]$fullTemplatePath = GetTemplateFile $templatePath
    [string]$cleanedTemplate = CleanTemplate $fullTemplatePath

    # [string]$patcherPathOrUrlContent = ExtractContent $cleanedTemplate "patcher_path_or_url"
    # [string]$variablesContent = ExtractContent $cleanedTemplate "variables"
    # [string]$targetsAndPatternsContent = ExtractContent $cleanedTemplate "targets_and_patterns"
    [string]$hostsContent = ExtractContent $cleanedTemplate "hosts_add"

    # [string]$patcherFile = GetPatcherFile $patcherPathOrUrlContent
    # [System.Collections.Hashtable]$variables = GetVariables $variablesContent
    # DetectFilesAndPatternsAndPatch $patcherFile $targetsAndPatternsContent $variables
    AddToHosts $hostsContent
    

} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$watch.Stop() # stop timer
Write-Host "Script execution time is" $watch.Elapsed # time of execution code