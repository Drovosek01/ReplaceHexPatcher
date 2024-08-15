# =====
# GLOBAL VARIABLES
# =====

[string]$firewallBlockContent = @'

C:\Users\$USER\AppData\Local\Temp\Test Folder\*.exe
C:\Users\$USER\AppData\Local\Temp\Test Folder with subfolders\*

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
Get string array with paths to exe-files
and check if exist rule for this path
and delete rule if exist
#>
function RemoveFilesFromFirewall {
    param (
        [Parameter(Mandatory)]
        [string[]]$exePaths
    )
    
    if ($exePaths.Count -eq 0) {
        return
    } else {
        try {
            [Microsoft.Management.Infrastructure.CimInstance[]]$existRulesForExes = Get-NetFirewallApplicationFilter | Where-Object { $_.Program -in $exePaths } | Get-NetFirewallRule
            if ($existRulesForExes.Length -gt 0) {
                $existRulesForExes | Remove-NetFirewallRule
            }
        }
        catch {
            Write-Error "Error when search and removing rules from Firewall"
        }
    }
}


<#
.DESCRIPTION
Get array with string of paths to exe-files or folders with files
And extract paths to exe-files from given folders
If folder path end with '*' it mean get paths for all exe files include all subfolders (recursive)
If folder path end with '*.exe' it mean get paths for all exe files only from this folder (without subfolders)

Return array strings with paths only for exe-files
#>
function GetPathsForExe {
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    [string]$cleanedContent = $content.Clone().Trim()

    [System.Collections.ArrayList]$resultLines = New-Object System.Collections.ArrayList
    [string]$exeFilesPattern = '*.exe'

    foreach ($line in $cleanedContent -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()

        if (-not (Test-Path $line)) {
            continue
        }

        if ($line.EndsWith("\$exeFilesPattern")) {
            [string]$folderPath = $line.Replace("\$exeFilesPattern", '')
            [string[]]$filesFromFolder = Get-ChildItem $folderPath -Filter $exeFilesPattern | ForEach-Object { $_.FullName }
            $filesFromFolder | ForEach-Object { [void]($resultLines.Add($_)) }
        } elseif ($line.EndsWith('\*')) {
            [string]$folderPath = $line.Replace('\*', '')
            [string[]]$filesFromFolder = Get-ChildItem $folderPath -Filter $exeFilesPattern -Recurse | ForEach-Object { $_.FullName }
            $filesFromFolder | ForEach-Object { [void]($resultLines.Add($_)) }
        } else {
            [void]($resultLines.Add($line))
        }
    }

    # if no paths we return -1 because Powershell cannot return empty array.
    # Then need handle -1 where we execute this function
    $result = if ($resultLines.Count -eq 0) { -1 } else { $resultLines.ToArray() }

    return $result
}


<#
.DESCRIPTION
Get array with string of paths to exe-files or folders with files
And add rules to Windows Firewall for block all connections for give exe-files
without duplication firewall rules
without check if exe-files exist
#>
function BlockFilesWithFirewall {
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    if (($content.Trim()).Count -eq 0) {
        return
    }
    
    if (-Not (DoWeHaveAdministratorPrivileges)) {
        throw "For modify Firewall rules need Administrator privileges, but this script not have it.`nRelaunch script with admins privileges"
        exit 1
    }

    [string]$cleanedContent = $content.Clone().Trim()

    $temp = GetPathsForExe $cleanedContent
    if ($temp -eq -1) {
        # no paths for files - no targets for block in firewall
        return
    } else {
        [string[]]$exePaths = $temp
    }

    # deduplication rules - remove existing rules for same exes before block exe
    RemoveFilesFromFirewall -exePaths $exePaths

    foreach ($line in $exePaths) {
        # Trim line is important because end line include \n
        $line = $line.Trim()

        [string]$ruleName = "Blocked $line"

        # Block all (Inbound and Outbound) network traffic for .exe
        [void](New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Program $line -Action Block -Profile Any)
        [void](New-NetFirewallRule -DisplayName $ruleName -Direction Outbound -Program $line -Action Block -Profile Any)
    }
}




# =====
# MAIN
# =====


$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    $firewallBlockContent = $firewallBlockContent -ireplace '\$USER', $env:USERNAME

    if ($firewallBlockContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines paths for block in firewall..."
        BlockFilesWithFirewall $firewallBlockContent
        Write-Host "Adding rules in firewall complete"
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
