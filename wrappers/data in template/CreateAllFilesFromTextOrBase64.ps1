param (
    [string]$templateContent,
    [System.Collections.Hashtable]$vars
)


# =====
# GLOBAL VARIABLES
# =====

# Names loaded .ps1 files
[string]$deleteFilesOrFoldersScriptName = 'DeleteFilesOrFolders'


# =====
# FUNCTIONS
# =====


<#
.SYNOPSIS
Get array with text and iterate it and function CreateFilesFromData
#>
function CreateAllFilesFromText {
    param (
        [Parameter(Mandatory)]
        [string[]]$sectionContents
    )
    
    foreach ($content in $sectionContents) {
        CreateFilesFromData -sectionContent $content
    }
}


<#
.SYNOPSIS
Get array with text and iterate it and function CreateFilesFromData
#>
function CreateAllFilesFromBase64 {
    param (
        [Parameter(Mandatory)]
        [string[]]$sectionContents
    )
    
    foreach ($content in $sectionContents) {
        CreateFilesFromData -sectionContent $content -isBase64Content
    }
}


<#
.SYNOPSIS
Convert given text to base64 string or bytes array and return it
#>
function ConvertBase64ToData {
    param (
        [Parameter(Mandatory)]
        [string]$content,
        [switch]$isBinary = $false
    )

    if ($content.Length -eq 0) {
        return $content
    } else {
        [byte[]]$decodedBytes = [System.Convert]::FromBase64String($content.Trim())
        
        if ($isBinary) {
            return $decodedBytes
        } else {
            [string]$decodedString = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
    
            return $decodedString
        }
    }
}


<#
.SYNOPSIS
Analyze given text and create new text file with content from text
#>
function CreateFilesFromData {
    param (
        [Parameter(Mandatory)]
        [string]$sectionContent,
        [switch]$isBase64Content = $false
    )

    # Trim only start because end file can have empty lines if new file need empty lines
    [string]$cleanedContent = $sectionContent.Clone().TrimStart()
    [string]$targetPath = ''
    [string]$endLinesNeed = ''
    [string]$targetContent = ''
    [bool]$isBinaryBase64 = $false
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }
    
    [string[]]$cleanedContentLines = $cleanedContent -split "\n"
    $targetPath = $cleanedContentLines[0].Trim()

    # if target file exist - delete it
    if (Test-Path $targetPath) {
        . (Resolve-Path ".\$deleteFilesOrFoldersScriptName.ps1")
        DeleteFilesOrFolders $targetPath
    }

    # check second line in content and detect if it flag for end lines type
    if ($cleanedContentLines.Count -gt 1) {
        if ($cleanedContentLines[1].Trim() -eq 'CRLF') {
            $endLinesNeed = "`r`n"
        } elseif ($cleanedContentLines[1].Trim() -eq 'LF') {
            $endLinesNeed = "`n"
        } elseif ($cleanedContentLines[1].Trim() -eq $binaryDataFlag) {
            $endLinesNeed = 'no need modify'
            $isBinaryBase64 = $true
        }
    }

    # if endLinesNeed settled - mean second line in content is tag for endLinesNeed and tag is not part future file content
    # else endLinesNeed var is empty - mean second line in content is start for future file content
    if ($endLinesNeed -eq '') {
        [string[]]$tempContentLines = $cleanedContentLines[1..($cleanedContentLines.Length-1)]
        
        if ($isBase64Content) {
            [byte[]]$targetContent = ConvertBase64ToData ($tempContentLines -join '') -isBinary
        } else {
            $endLinesNeed = [System.Environment]::NewLine
            $targetContent = ($tempContentLines) -join $endLinesNeed
        }
    } else {
        [string[]]$tempContentLines = $cleanedContentLines[2..($cleanedContentLines.Length-1)]
        
        if ($isBase64Content) {            
            if ($isBinaryBase64) {
                [byte[]]$targetContent = ConvertBase64ToData ($tempContentLines -join '') -isBinary
            } else {
                $targetContent = ConvertBase64ToData ($tempContentLines -join '')
                if ($endLinesNeed -eq "`n") {
                    $targetContent = ($targetContent -replace "`r`n", "`n") -replace "`r", "`n"
                }
                if ($endLinesNeed -eq "`r`n") {
                    $targetContent = $targetContent -replace "`n", "`r`n"
                }
            }
        } else {
            $targetContent = ($tempContentLines) -join $endLinesNeed
        }
    }

    # create file with content inside and all folder for file path
    try {
        if ($isBinaryBase64) {
            [void](New-Item -Path $targetPath -ItemType File -Force -ErrorAction Stop)
            [System.IO.File]::WriteAllBytes($targetPath, $targetContent)
        } else {
            [void](New-Item -Path $targetPath -ItemType File -Force -ErrorAction Stop)
            Set-Content -Value $targetContent -Path $targetPath -NoNewline -ErrorAction Stop
        }
    }
    catch {
        # create same files with same content but with admin privileges
        if ($isBinaryBase64) {
            # we can't execute WriteAllBytes in Start-Process because we can't set bytes to command string
            # so WriteAllBytes to temp file then move temp file with admin privileges
            $tempFile = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllBytes($tempFile, $targetContent)
            $processId = Start-Process $PSHost -Verb RunAs -PassThru -Wait -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"Copy-Item -Path '$tempFile' -Destination '$targetPath' -Force;Remove-Item '$tempFile'`""
        }
        else {
            $processId = Start-Process $PSHost -Verb RunAs -PassThru -Wait -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"New-Item -Path `"$targetPath`" -ItemType File -Force;Set-Content -Value `"$targetContent`" -Path `"$targetPath`" -NoNewline`""
        }
    
        if ($processId.ExitCode -gt 0) {
            throw "Something happened wrong when create files with data with administrator privileges"
        }
    }
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $vars) {
        $variables = $vars
        CreateAllFilesFromText -sectionContents $templateContent
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}