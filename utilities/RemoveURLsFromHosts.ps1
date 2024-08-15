# =====
# GLOBAL VARIABLES
# =====

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}

[string]$localhostIP = '127.0.0.1'
[string]$zeroIP = '0.0.0.0'




[string]$hostsRemoveContent = @'

# Just some title
anysute.com
sdjfhksdf.com
ij.sddddwr.ru
bdj.sdfsdf.ss

'@




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


$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    if ($hostsRemoveContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines for remove from hosts..."
        RemoveFromHosts $hostsRemoveContent
        Write-Host "Removing lines from hosts complete"
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}


$watch.Stop() # stop timer
Write-Host "Script execution time is" $watch.Elapsed # time of execution code

# Pause before exit like in CMD
Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
