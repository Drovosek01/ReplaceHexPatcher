param (
    [string]$templateContent,
    [string]$variables
)


<#
.DESCRIPTION
Function get a text with lines and detect valid path to .ps1 file or url
and if first valid line is url - download script from url to temp file
and return path to script file
or throw error if no one valid path or url was detected
#>
function GetPatcherFile {
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    [string]$cleanedContent = $content.Clone().Trim()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    foreach ($line in $cleanedContent -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()

        if ($line -like "http*") {
            $tempStatusCode = ''
            try {
                $tempStatusCode = (Invoke-WebRequest -UseBasicParsing -Uri $line -ErrorAction Stop).StatusCode
            }
            catch {
                continue
            }

            if ($tempStatusCode -eq 200) {
                # If file on URL exist - download it to temp file
                [string]$tempFile = [System.IO.Path]::GetTempFileName()
                Get-Process | Where-Object {$_.CPU -ge 1} | Out-File $tempFile
                (New-Object System.Net.WebClient).DownloadFile($line,$tempFile)
                $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf("."))+".ps1")
                Rename-Item $tempFile $renamedTempFile
                return $renamedTempFile, $fileIsTempFlag
            }
        } else {
            if ((Test-Path $line -PathType Leaf 2>$null) -and ($line.EndsWith(".ps1"))) {
                return $line, ''
            }
        }
    }
    
    Write-Error "No valid URL for patcher or paths for file-patcher in template"
    exit 1
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $variables) {
        GetPatcherFile -content $templateContent
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}