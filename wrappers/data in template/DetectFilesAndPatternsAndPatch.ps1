param (
    [string]$templateContent,
    [System.Collections.Hashtable]$vars,
    [string]$patcherFilePath
)


# =====
# GLOBAL VARIABLES
# =====

# Same splitter like in core script
$patternSplitters = @('/','\','|')

# Text - flags in parse sections
[string]$makeBackupFlag = 'MAKE BACKUP'


# =====
# FUNCTIONS
# =====


<#
.DESCRIPTION
Check if string contain any element from array and return $true if contain
#>
function DoesStringContainsOneItemArray {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$text,
        [Parameter(Mandatory)]
        [array]$items
    )
    
    $containsElement = $false

    foreach ($element in $items) {
        if ($text -match [regex]::Escape($element)) {
            $containsElement = $true
            break
        }
    }

    return $containsElement
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
        [string]$patterns,
        [Parameter(Mandatory)]
        [bool]$makeBackup
    )

    [string]$patternsCleaned = $patterns -replace ",`"$",""

    # The only .ps1 file that needs to be run from template is the patcher (main/core file)
    # Previously there was additional code here to run the process as administrator or as usual, depending on different conditions
    # But the logic of restarting on behalf of the administrator has been added to the script patcher.
    # It looks like it makes no sense to repeat the logic of checking startup as an administrator (but this is not accurate),
    #   but if necessary, run others.ps1 files, then you will need to return the logic of the conditions to run as administrator

    if ($makeBackup) {
        $process = Start-Process $PSHost -PassThru -Wait -NoNewWindow -ArgumentList "-ExecutionPolicy Bypass -File `"$psFile`" -filePath `"$targetFile`" -patterns", "$patternsCleaned", "-makeBackup"
    } else {
        $process = Start-Process $PSHost -PassThru -Wait -NoNewWindow -ArgumentList "-ExecutionPolicy Bypass -File `"$psFile`" -filePath `"$targetFile`" -patterns", "$patternsCleaned"
    }

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