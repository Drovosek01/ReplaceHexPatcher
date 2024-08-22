param (
    [string]$templateContent,
    [System.Collections.Hashtable]$vars
)


# =====
# REQUIREMENTS
# =====

# Function "DoWeHaveAdministratorPrivileges" wrote in external script where this script importing.
# If need use this script not like library but like full separated script - write the function in this file or import it  


# =====
# GLOBAL VARIABLES
# =====

# IPs
[string]$localhostIP = '127.0.0.1'
[string]$zeroIP = '0.0.0.0'



# =====
# FUNCTIONS
# =====


<#
.SYNOPSIS
Handle content from template section and remove it from hosts file
#>
function RemoveFromHosts {
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    [string]$hostsFilePath = [System.Environment]::SystemDirectory + "\drivers\etc\hosts"

    if (-not (Test-Path $hostsFilePath)) {
        # if hosts file not exist - we have no target for remove lines
        return
    }

    [string]$cleanedContent = $content.Clone().Trim()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    [bool]$needRemoveReadOnlyAttr = $false

    $fileAttributes = Get-Item -Path $hostsFilePath | Select-Object -ExpandProperty Attributes

    [string[]]$linesForRemoveFromHosts = $cleanedContent -split "`n"
    [string]$hostsFileContent = [System.IO.File]::ReadAllText($hostsFilePath)
    
    if ($hostsFileContent.Trim().Length -eq 0) {
        # if hosts file empty - we no have target for remove lines
        return
    }
    
    if (-not ($hostsFileContent.EndsWith("`r`n"))) {
        # add to hosts last empty line if not exist
        $hostsFileContent = "$hostsFileContent`r`n"
    }
    
    [string[]]$hostsLines = [System.IO.File]::ReadAllLines($hostsFilePath)
    [string]$resultContent = ''
    [string[]]$resultLines = $hostsLines.Clone()

    foreach ($line in $linesForRemoveFromHosts) {
        # Trim line is important because end line include \n
        $line = $line.Trim()

        $resultLines = $resultLines | Where-Object {
            [string]$tempHostLine = $_.Trim()
            [string]$tempMatchLine = $line.Clone()

            if (($line.StartsWith('#') -or ($line.StartsWith($localhostIP)) -or ($line.StartsWith($zeroIP)))) {
                $tempMatchLine = $tempMatchLine -replace "\s+", '\s+'
                $tempHostLine -notmatch $tempMatchLine 
            } else {
                $tempMatchLine = $tempMatchLine.Replace('*','.*')
                $tempHostLine -notmatch "[^\.]\b$tempMatchLine\b"
            }
        }
    }

    $resultContent = ($resultLines -join "`r`n").Trim()

    if (DoWeHaveAdministratorPrivileges) {
        if ($needRemoveReadOnlyAttr) {
            Set-ItemProperty -Path $hostsFilePath -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
        }
        # Set-Content -Value $resultContent -Path $hostsFilePath
        $resultContent | Out-File -FilePath $hostsFilePath -Encoding utf8 -Force
        # Return readonly attribute if it was
        if ($needRemoveReadOnlyAttr) {
            Set-ItemProperty -Path $hostsFilePath -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
            $needRemoveReadOnlyAttr = $false
        }

        Clear-DnsClientCache
    } else {
        # IMPORTANT !!!
        # Do not formate this command and not re-write it
        # it need for add multiline string to Start-Process command
        $command = @"
@'
$resultContent 
'@
| Out-File -FilePath $hostsFilePath -Encoding utf8 -Force
"@
        if ($needRemoveReadOnlyAttr) {
            # If hosts file have attribute "read only" we need remove this attribute before adding lines
            # and restore "default state" (add this attribute to hosts file) after lines to hosts was added
            $command = "Set-ItemProperty -Path '$hostsFilePath' -Name Attributes -Value ('$fileAttributes' -bxor [System.IO.FileAttributes]::ReadOnly)" `
            + "`n" `
            + $command `
            + "`n" `
            + "Set-ItemProperty -Path '$hostsFilePath' -Name Attributes -Value ('$fileAttributes' -bor [System.IO.FileAttributes]::ReadOnly)" `
            + "Clear-DnsClientCache"
        }
        Start-Process $PSHost -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"$command`""
    }
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $vars) {
        $variables = $vars
        RemoveFromHosts -content $templateContent
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}