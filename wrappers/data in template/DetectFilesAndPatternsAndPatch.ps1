param (
    [string]$templateContent,
    [System.Collections.Hashtable]$vars,
    [string]$patcherFilePath
)


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
        [string]$content
    )

    [string]$cleanedContent = $content.Clone().Trim()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    [string]$filePathArg = ''
    [string]$patternsArg = '"'
    [bool]$makeBackupArg = $false

    [bool]$isSearchPattern = $true

    foreach ($line in $cleanedContent -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()

        if (Test-Path $line 2>$null) {
            if ($patternsArg.Length -gt 1) {
                RunPSFile $patcherFile $filePathArg $patternsArg $makeBackupArg
                # Reset variables-arguments before run patcher again
                $filePathArg = $line
                $patternsArg = '"'
                $makeBackupArg = $false
            } else {
                $filePathArg = $line
            }
        } elseif ($line -eq $makeBackupFlag) {
            $makeBackupArg = $true
        } else {
            # if it ready search+replace pattern - add it to all patterns string
            # and continue lines loop
            # if ($patternSplitters.ForEach($line.Contains($_))) {
            if (DoesStringContainsOneItemArray $line $patternSplitters) {
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
            RunPSFile $patcherFile $filePathArg $patternsArg $makeBackupArg
        } else {
            Write-Error "No valid targets or patterns was found. Or target files not exist"
            exit 1
        }
    }
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $vars -and $patcherFilePath) {
        $variables = $vars
        DetectFilesAndPatternsAndPatch -content $templateContent -patcherFile $patcherFilePath
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}