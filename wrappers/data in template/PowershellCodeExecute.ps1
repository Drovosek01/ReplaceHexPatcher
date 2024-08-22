param (
    [string]$templateContent,
    [System.Collections.Hashtable]$vars
)


# =====
# GLOBAL VARIABLES
# =====

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}


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
Create temp .ps1 file with code from template
and execute it with admin rights if need
Then remove temp file
#>
function PowershellCodeExecute {
    param (
        [Parameter(Mandatory)]
        [string]$content,
        [switch]$hideExternalOutput = $false,
        [switch]$needRunAS = $false
    )

    [string]$cleanedContent = $content.Clone().Trim()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }
    
    try {
        [string]$tempFile = [System.IO.Path]::GetTempFileName()
        Rename-Item -Path $tempFile -NewName "$tempFile.ps1"
        $tempFile = "$tempFile.ps1"

        # write code from template to temp .ps1 file
        $cleanedContent | Out-File -FilePath $tempFile -Encoding utf8 -Force
    
        # execute file .ps1 with admin rights if exist else request admins rights
        if ((DoWeHaveAdministratorPrivileges) -or (-not $needRunAS)) {
            [string]$nullFile = [System.IO.Path]::GetTempFileName()
            
            [System.Collections.Hashtable]$processArgs = @{
                FilePath = $PSHost.Clone()
                ArgumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$tempFile`""
                NoNewWindow = $true
                Wait = $true
            }

            if ($hideExternalOutput) {
                $processArgs.RedirectStandardOutput = $nullFile
            }

            Start-Process @processArgs
        
            Remove-Item -Path $nullFile -Force -ErrorAction Stop
        } else {
            $processId = Start-Process -FilePath $PSHost `
                -Verb RunAs `
                -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$tempFile`"" `
                -PassThru `
                -Wait
        
            if ($processId.ExitCode -gt 0) {
                throw "Something happened wrong when execute Powershell code in file $tempFile"
            }
        }
    
        Remove-Item -Path $tempFile -Force -ErrorAction Stop
    }
    catch {
        Write-Error "Error while execute Powershell-code from template - " $_.Exception.Message
    }
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $vars) {
        $variables = $vars
        PowershellCodeExecute -content $templateContent -hideExternalOutput
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}