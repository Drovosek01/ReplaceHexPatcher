param (
    [string]$templateContent,
    [System.Collections.Hashtable]$vars
)


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
Create temp .cmd file with code from template
and execute it with admin rights if need
Then remove temp file
#>
function CmdCodeExecute {
    param (
        [Parameter(Mandatory)]
        [string]$content,
        [switch]$hideExternalOutput = $false,
        [switch]$needRunAS = $false,
        [switch]$needNewWindow = $false
    )

    # hideExternalOutput for cmd process work only in Powershell window
    # if launched in different window WITH admin privileges - it not work

    [string]$cleanedContent = $content.Clone().Trim()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    try {
        [string]$tempFile = [System.IO.Path]::GetTempFileName()
        Rename-Item -Path $tempFile -NewName "$tempFile.cmd"
        $tempFile = "$tempFile.cmd"

        # write cmd code from template to temp .cmd file
        # need encoding UTF-8 without BOM
        [System.IO.File]::WriteAllLines($tempFile, $cleanedContent, [System.Text.UTF8Encoding]($False))
        [string]$nullFile = [System.IO.Path]::GetTempFileName()

        [System.Collections.Hashtable]$processArgs = @{
            FilePath = "cmd.exe"
            ArgumentList = "-ExecutionPolicy Bypass /c `"$tempFile`""
            NoNewWindow = $true
            Wait = $true
        }

        if ($needNewWindow) {
            $processArgs.Remove('NoNewWindow')
        }
        if ($hideExternalOutput) {
            $processArgs.RedirectStandardOutput = $nullFile
        }
        
        if ((DoWeHaveAdministratorPrivileges) -or (-not $needRunAS)) {
            Start-Process @processArgs
            
            Remove-Item -Path $nullFile -Force -ErrorAction Stop
        } else {
            $processArgs.PassThru = $true
            $processArgs.Verb = 'RunAs'
            # NoNewWindow parameter incompatible with "-Verb RunAs" - need remove it from args
            $processArgs.Remove('NoNewWindow')

            $processId = Start-Process @processArgs
        
            if ($processId.ExitCode -gt 0) {
                throw "Something happened wrong when execute CMD code in file $tempFile"
            }
        }
        
        Remove-Item -Path $tempFile -Force -ErrorAction Stop
    }
    catch {
        Write-Error "Error while execute CMD-code from template - " $_.Exception.Message
    }
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $vars) {
        $variables = $vars
        CmdCodeExecute -content $templateContent
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}