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

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}

# Text - flags in parse sections
[string]$notModifyFlag = 'NOT MODIFY IT'

# IPs
[string]$localhostIP = '127.0.0.1'
[string]$zeroIP = '0.0.0.0'



# =====
# FUNCTIONS
# =====


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
        [string]$content
    )
    
    [string]$contentForAddToHosts = ''

    [string[]]$templateContentLines = $content -split "\n"

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
        foreach ($line in $content -split "\n") {
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
Return True if last line empty or contain spaces/tabs only
#>
function isLastLineEmptyOrSpaces {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$content
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
.SYNOPSIS
Handle content from template section and add it to hosts file
#>
function AddToHosts {
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    [string]$cleanedContent = $content.Clone().Trim()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    [bool]$needRemoveReadOnlyAttr = $false

    [string]$hostsFilePath = [System.Environment]::SystemDirectory + "\drivers\etc\hosts"
    $fileAttributes = Get-Item -Path $hostsFilePath | Select-Object -ExpandProperty Attributes

    [string]$contentForAddToHosts = CombineLinesForHosts $cleanedContent
    [string]$hostsFileContent = [System.IO.File]::ReadAllText($hostsFilePath)

    if (Test-Path $hostsFilePath 2>$null) {
        # If required lines exist in hosts file - no need touch hosts file
        if ($hostsFileContent.TrimEnd().EndsWith($contentForAddToHosts)) {
            return
        }

        # If hosts file exist check if last line hosts file empty
        # and add indents from the last line hosts file to new content
        if (isLastLineEmptyOrSpaces ($hostsFileContent)) {
            $contentForAddToHosts = "`r`n" + $contentForAddToHosts
        } else {
            $contentForAddToHosts = "`r`n`r`n" + $contentForAddToHosts
        }

        # If file have attribute "read only" remove this attribute for made possible patch file
        if ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly) {
            $needRemoveReadOnlyAttr = $true
        } else {
            $needRemoveReadOnlyAttr = $false
        }

        if (DoWeHaveAdministratorPrivileges) {
            if ($needRemoveReadOnlyAttr) {
                Set-ItemProperty -Path $hostsFilePath -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
            }
            Add-Content -Value $contentForAddToHosts -Path $hostsFilePath -Force
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
Add-Content -Path $hostsFilePath -Force -Value @'
$contentForAddToHosts 
'@
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
    } else {
        $command = @"
@'
$contentForAddToHosts 
'@
| Out-File -FilePath $hostsFilePath -Encoding utf8 -Force
Clear-DnsClientCache
"@
        Start-Process $PSHost -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"$command`""
    }
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $vars) {
        $variables = $vars
        AddToHosts -content $templateContent
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}