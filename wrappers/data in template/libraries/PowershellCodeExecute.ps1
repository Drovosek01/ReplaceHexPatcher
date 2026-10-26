
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
            if ($hideExternalOutput) {
                Invoke-Expression $cleanedContent *> $null
            }
            else {
                Invoke-Expression $cleanedContent
            }

            Remove-Item -Path $tempFile -Force -ErrorAction Stop 2>$null
        }
        else {
            [string]$nullFile = [System.IO.Path]::GetTempFileName()
            [System.Collections.Hashtable]$processArgs = @{
                ArgumentList = "-ExecutionPolicy Bypass -NoProfile -File `"$tempFile`""
                Verb         = "RunAs"
                PassThru     = $true
                Wait         = $true
            }

            if ($hideExternalOutput) {
                $processArgs.RedirectStandardOutput = $nullFile
            }
            
            $processId = Start-Process @processArgs
        
            Remove-Item -Path $nullFile -Force -ErrorAction SilentlyContinue 2>$null
            Remove-Item -Path $tempFile -Force -ErrorAction Stop 2>$null

            if ($processId.ExitCode -gt 0) {
                throw "Something happened wrong when execute Powershell code from template. Exit code is $($processId.ExitCode)"
            }
        }
    }
    catch {
        Write-Error "We have problems with executing Powershell script from template. Exit code is $($processId.ExitCode)"
        throw "$($_.Exception.Message)"
    }
}
