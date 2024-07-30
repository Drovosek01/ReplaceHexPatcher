param (
    [Parameter(Mandatory)]
    [string]$templatePath
)


# =====
# GLOBAL VARIABLES
# =====

# Same splitter like in core script
$patternSplitters = @('/','\','|')



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
    $comments = @(';', '::', '#')
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
#>
function Test-WriteAccess {
    param (
        [string]$Path
    )
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
        $stream.Close()
        return $true
    } catch {
        return $false
    }
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
        # [string[]]$patterns
        [string]$patterns
    )

    $patterns = $patterns -replace ',"$',""

    $fileAttributes = Get-Item -Path $targetFile | Select-Object -ExpandProperty Attributes

    # If file have attribute "read only" remove this attribute for made possible patch file
    if ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly) {
        Set-ItemProperty -Path $targetFile -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
        $readOnlyRemoved = $true
    } else {
        $readOnlyRemoved = $false
    }

    # Check write access only after remove readonly attribute!
    $needRunAS = if (Test-WriteAccess -Path $targetFile) {$false} else {$true}

    if ($needRunAS -and !(DoWeHaveAdministratorPrivileges)) {
        $process = Start-Process powershell -Verb RunAs -ArgumentList "-File `"$psFile`" -filePath `"$targetFile`" -patterns", "$patterns" -PassThru -Wait
    } else {
        $process = Start-Process powershell -ArgumentList "-File `"$psFile`" -filePath `"$targetFile`" -patterns", "$patterns" -PassThru -Wait
    }

    if ($process.ExitCode -gt 0) {
        throw "Something happened wrong when patching file $targetFile"
    }

    # Return readonly attribute if it was
    if ($readOnlyRemoved) {
        Set-ItemProperty -Path $targetFile -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
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

    if (Test-Path $templateWay) {
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

    [string]$patcherPathOrUrlContent = ExtractContent $cleanedTemplate "patcher_path_or_url"
    [string]$variablesContent = ExtractContent $cleanedTemplate "variables"
    [string]$targetsAndPatternsContent = ExtractContent $cleanedTemplate "targets_and_patterns"

    [string]$patcherFile = GetPatcherFile $patcherPathOrUrlContent
    [System.Collections.Hashtable]$variables = GetVariables $variablesContent
    DetectFilesAndPatternsAndPatch $patcherFile $targetsAndPatternsContent $variables
    
    

} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$watch.Stop() # stop timer
Write-Host "Script execution time is" $watch.Elapsed # time of execution code