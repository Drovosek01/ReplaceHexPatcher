param (
    [string]$templateContent,
    [System.Collections.Hashtable]$vars
)


# =====
# REQUIREMENTS
# =====

# Function "GetTypeEndLines" wrote in external script where this script importing.
# If need use this script not like library but like full separated script - write the function in this file or import it


# =====
# FUNCTIONS
# =====


<#
.DESCRIPTION
Handle content from template like .reg file
and apply this .reg file to Windows Registry
#>
function RegistryFileApply {
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    [string]$cleanedContent = $content.Clone().Trim()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    [string]$regFileStart = 'Windows Registry Editor Version 5.00'
    
    [string]$tempFile = [System.IO.Path]::GetTempFileName()
    Rename-Item -Path $tempFile -NewName "$tempFile.reg"
    $tempFile = "$tempFile.reg"

    [string]$endLinesContent = GetTypeEndLines -content $content

    try {
        if ($endLinesContent -eq "`n") {
            $cleanedContent = ($cleanedContent -replace "`n","`r`n")
        }

        if (-not ($cleanedContent.StartsWith($regFileStart))) {
            $cleanedContent = $regFileStart + "`r`n" + $cleanedContent
        }

        # Important that registry file be with CRLF ends of lines and with UTF-16 LE BOM (it Unicode) encoding
        $cleanedContent | Out-File -FilePath $tempFile -Encoding unicode -Force

        reg.exe import $tempFile 2>$null
        Remove-Item -Path $tempFile -Force -ErrorAction Stop
    }
    catch {
        Write-Error "Error when trying modify Registry"
    }
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $vars) {
        $variables = $vars
        RegistryFileApply $templateContent
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}