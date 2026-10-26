# =====
# GLOBAL VARIABLES
# =====

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}

# Text - flags in parse sections
[string]$notModifyFlag = 'NOT MODIFY IT'
    
# IPs
[string]$localhostIPv4 = '127.0.0.1'
[string]$localhostIPv6 = '::1'
[string]$zeroIPv4 = '0.0.0.0'



[string]$hostsAddContent = @'

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
    [string]$urlFlag = 'SEE_HERE_FIRST'

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
    }
    elseif ($templateContentLines[0].Trim().ToUpper().StartsWith($urlFlag)) {
        # if there is a flag phrase at the beginning of the text "SEE_HERE_FIRST" and there is a link behind it...
        # and the link is indeed there and it is available for download, then add to hosts
        # the content downloaded from the link, not the rest of the lines in the add section

        [string]$urlText = $templateContentLines[0].Trim() -replace "^$urlFlag\s*", ""

        if ($urlText -like "http*") {
            $tempStatusCode = ''
            try {
                $tempStatusCode = (Invoke-WebRequest -UseBasicParsing -Uri $urlText -ErrorAction Stop).StatusCode
            }
            catch {
                CombineLinesForHosts ($content -replace "^SEE_HERE_FIRST.*[\r\n]+", "")
                return ''
            }
            
            if ($tempStatusCode -eq 200) {
                $urlContent = (Invoke-WebRequest -Uri $urlText -UseBasicParsing).Content
                
                CombineLinesForHosts $(RemoveEmptyLines $urlContent)
            }
            else {
                CombineLinesForHosts ($content -replace "^SEE_HERE_FIRST.*[\r\n]+", "")
                return ''
            }
        }
    }
    else {
        foreach ($line in $content -split "\n") {
            # Trim line is important because end line include \n
            $line = $line.Trim()

            if ($line.StartsWith($urlFlag)) {
                continue
            }
            elseif ($line.StartsWith('#') -or $line.StartsWith($zeroIPv4) -or $line.StartsWith($localhostIPv4) -or $line.StartsWith($localhostIPv6)) {
                $contentForAddToHosts += $line + "`r`n"
            }
            else {
                # block URL for IPv4
                $contentForAddToHosts += $zeroIPv4 + ' ' + $line + "`r`n"
                # block URL for IPv6
                $contentForAddToHosts += $localhostIPv6 + ' ' + $line + "`r`n"
            }
        }
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
    }
    elseif ($content -is [array]) {
        return ($content[$content.Length - 1].Trim() -eq "")
    }
    else {
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

    [int]$lineCountOriginal = (Get-Content $hostsFilePath).Count

    [string]$contentForAddToHosts = CombineLinesForHosts $cleanedContent
    [string]$hostsFileContent = [System.IO.File]::ReadAllText($hostsFilePath)

    if (Test-Path $hostsFilePath 2>$null) {
        # If required lines exist in hosts file - no need touch hosts file
        if ($hostsFileContent.TrimEnd().Contains($contentForAddToHosts)) {
            return
        }

        # If hosts file exist check if last line hosts file empty
        # and add indents from the last line hosts file to new content
        if (isLastLineEmptyOrSpaces ($hostsFileContent)) {
            $contentForAddToHosts = "`r`n" + $contentForAddToHosts
        }
        else {
            $contentForAddToHosts = "`r`n`r`n" + $contentForAddToHosts
        }

        # If file have attribute "read only" remove this attribute for made possible patch file
        if ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly) {
            $needRemoveReadOnlyAttr = $true
        }
        else {
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
        }
        else {
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
    }
    else {
        $command = @"
@'
$contentForAddToHosts 
'@ | Out-File -FilePath $hostsFilePath -Encoding utf8 -Force
Clear-DnsClientCache
"@
        Start-Process $PSHost -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"$command`""
    }

    Start-Sleep -Seconds 2  

    [int]$lineCountCurrent = (Get-Content $hostsFilePath).Count
    Write-Host "The hosts file contained lines: ${lineCountOriginal}"
    Write-Host "Lines added: $($lineCountCurrent - $lineCountOriginal)"
    Write-Host "Now the hosts file contained lines: ${lineCountCurrent}"
}




# =====
# MAIN
# =====


$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    if ($hostsAddContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines for add to hosts..."
        AddToHosts $hostsAddContent
        Write-Host "Adding lines to hosts complete"
    }
}
catch {
    Write-Error "$($_.Exception.Message)"
    exit 1
}


$watch.Stop() # stop timer
Write-Host "Script execution time is" $watch.Elapsed # time of execution code

# Pause before exit like in CMD
Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
