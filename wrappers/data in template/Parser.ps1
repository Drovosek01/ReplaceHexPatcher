param (
    [Parameter(Mandatory)]
    [string]$templatePath,
    [string]$patcherPath
)


# =====
# GLOBAL VARIABLES
# =====

$comments = @(';;')

# Here will stored parsed template variables
[System.Collections.Hashtable]$variables = @{}

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$templateDir = ''

# Other flags for code
[string]$fileIsTempFlag = 'fileIsTemp'


# Names loaded .ps1 files
[string]$getPatcherScriptName = 'GetPatcher'
[string]$detectFilesAndPatternsAndPatchScriptName = 'DetectFilesAndPatternsAndPatch'
[string]$removeFromHostsScriptName = 'RemoveFromHosts'
[string]$addToHostsScriptName = 'AddToHosts'
[string]$deleteFilesOrFoldersScriptName = 'DeleteFilesOrFolders'
[string]$createAllFilesFromTextOrBase64ScriptName = 'CreateAllFilesFromTextOrBase64'
[string]$blockOrRemoveFilesFromFirewallScriptName = 'BlockOrRemoveFilesFromFirewall'
[string]$registryFileApplyScriptName = 'RegistryFileApply'
[string]$powershellCodeExecuteScriptName = 'PowershellCodeExecute'
[string]$cmdCodeExecuteScriptName = 'CmdCodeExecute'


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
Remove comments from text template
and replace template variables with text
and return cleaned template content
#>
function CleanTemplate {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$filePath
    )

    [string[]]$content = [System.IO.File]::ReadAllLines($filePath, [System.Text.Encoding]::UTF8)

    # Remove lines with current template-comments tag
    foreach ($comment in $comments) {
        $content = $content | select-string -pattern $comment -notmatch
    }

    # Replace $USER to current username
    $content = $content -ireplace '\$USER', $env:USERNAME

    return ($content -join "`n")
}


<#
.SYNOPSIS
Detect type end lines from given text
#>
function GetTypeEndLines {
    param (
        [Parameter(Mandatory)]
        [string]$content
    )
    
    if ($content.IndexOf("`r`n") -gt 0) {
        return "`r`n"
    } else {
        return "`n"
    }
}


<#
.DESCRIPTION
Remove empty lines from given string
and convert end lines if need
and trim all lines if need
#>
function RemoveEmptyLines {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$content,
        [string]$endLinesForResult,
        [switch]$noTrimLines = $false
    )

    # if content have no text or have 1 symbol - no data for handle
    # then return given content
    if ($content.Length -le 1) {
        return $content
    }

    [string]$endLinesCurrent = ''
    [string[]]$contentLines = $content -split "`r`n|`n"
    [string]$endLinesResult = ''
    
    $endLinesCurrent = GetTypeEndLines -content $content
    
    # set type of end lines for result text
    if ($endLinesForResult -eq 'CRLF') {
        $endLinesResult = "`r`n"
    } elseif ($endLinesForResult -eq 'LF') {
        $endLinesResult = "`n"
    } else {
        $endLinesResult = $endLinesCurrent
    }

    $contentLines = $contentLines | Where-Object { -not [String]::IsNullOrWhiteSpace($_) }

    if (-Not $noTrimLines) {
        $contentLines = $contentLines | ForEach-Object { $_.Trim() }
    }

    return ($contentLines -join $endLinesResult)
}


<#
.SYNOPSIS
Function for extract text between start and end named section edges

.DESCRIPTION
Get templateContent and sectionName and return text
between [start-sectionName] and [end-sectionName]
#>
function ExtractContent {
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string]$content,
        [Parameter(Mandatory)]
        [string]$sectionName,
        [switch]$several = $false,
        [switch]$saveEmptyLines = $false
    )

    [string]$cleanedTemplateContent = $content.Clone()
    [string]$startSectionName = "[start-$sectionName]"
    [string]$endSectionName = "[end-$sectionName]"

    if (-not $saveEmptyLines) {
        $cleanedTemplateContent = RemoveEmptyLines $cleanedTemplateContent
    }

    [System.Collections.ArrayList]$contentSection = New-Object System.Collections.ArrayList

    # start position content between content tags (+1 mean not include in content \n after start tag)
    [int]$startContentIndex = $cleanedTemplateContent.IndexOf($startSectionName)+$startSectionName.Length
    if ($cleanedTemplateContent[$startContentIndex] -eq "`n") {
        $startContentIndex +=1
    }
    if (($cleanedTemplateContent[$startContentIndex] -eq "`r") -and ($cleanedTemplateContent[$startContentIndex + 1] -eq "`n")) {
        $startContentIndex +=2
    }

    # end position content between content tags
    [int]$endContentIndex = $cleanedTemplateContent.IndexOf($endSectionName)

    if (($startContentIndex -eq -1) -or ($endContentIndex -eq -1)) {
        return $contentSection
    }
    if ($startContentIndex -gt $endContentIndex) {
        Write-Error "Wrong template. Error on parse section $sectionName"
        exit 1
    }

    if ($several) {
        do {
            [void]$contentSection.Add($cleanedTemplateContent.Substring($startContentIndex, $endContentIndex-$startContentIndex))
            
            if ($startContentIndex -gt $endContentIndex) {
                Write-Error "Wrong template. Error on parse section $sectionName"
                exit 1
            }

            [int]$fullEndSectionIndex = $endContentIndex + $endSectionName.Length

            $cleanedTemplateContent = $cleanedTemplateContent.Substring($fullEndSectionIndex, $cleanedTemplateContent.Length-$fullEndSectionIndex-1)

            # start position content between content tags (+1 mean not include in content \n after start tag)
            [int]$startContentIndex = $cleanedTemplateContent.IndexOf($startSectionName)+$startSectionName.Length + 1
            # end position content between content tags
            [int]$endContentIndex = $cleanedTemplateContent.IndexOf($endSectionName)
        } until (
            ($startContentIndex -eq -1) -or ($endContentIndex -eq -1)
        )
    } else {
        [void]$contentSection.Add($cleanedTemplateContent.Substring($startContentIndex, $endContentIndex-$startContentIndex))
    }

    # If array will contain 1 element and it will returned to variable with type [string]
    # this variable will contain this 1 element, not all array
    return $contentSection.ToArray()
}


<#
.SYNOPSIS
Extract variables and values from give content and return hashtable with it
#>
function GetVariables {
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    $variables = @{}

    foreach ($line in $content -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()
        if (-not ($line.Contains('='))) {
            continue
        } else {
            $tempSplitLine = $line.Split("=")
            [void]$variables.Add($tempSplitLine[0].Trim(),$tempSplitLine[1].Trim())
        }
    }

    return $variables
}


<#
.DESCRIPTION
The path to the template is passed as an argument to this script.
This can be the path to a file on your computer or the URL to the template text.
This function checks for the presence of a file on the computer if it is the path to the file,
    or creates a temporary file and downloads a template from the specified URL into it
#>
function GetTemplateFile {
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string]$templateWay
    )

    if (Test-Path $templateWay 2>$null) {
        if ($templateWay.Contains($env:Temp)) {
            return (Get-ChildItem $templateWay).FullName, $fileIsTempFlag
        }
        return (Get-ChildItem $templateWay).FullName, ''
    } elseif ((Invoke-WebRequest -UseBasicParsing -Uri $templateWay).StatusCode -eq 200) {
        [string]$tempFile = [System.IO.Path]::GetTempFileName()
        Get-Process | Where-Object {$_.CPU -ge 1} | Out-File $tempFile
        (New-Object System.Net.WebClient).DownloadFile($templateWay,$tempFile)
        $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf("."))+".txt")
        Rename-Item $tempFile $renamedTempFile
        return (Get-ChildItem $renamedTempFile).FullName, $fileIsTempFlag
    }
    
    Write-Error "No valid template path or URL was provided"
    exit 1
}



# =====
# MAIN
# =====


$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    [string]$fullTemplatePath, [string]$templateFileTempFlag = GetTemplateFile $templatePath
    [string]$cleanedTemplate = CleanTemplate $fullTemplatePath
    $templateDir = [System.IO.Path]::GetDirectoryName($fullTemplatePath)

    Set-Location $scriptDir


    # Get content from template file

    [string]$variablesContent = ExtractContent $cleanedTemplate "variables"
    
    [string]$patcherPathOrUrlContent = ExtractContent $cleanedTemplate "patcher_path_or_url"
    # If path or URL for patcher will passed like script argument
    # need check this argument first before check patchers lines from template  
    if ((Test-Path variable:patcherPath) -and ($patcherPath.Length -gt 1)) {
        $patcherPathOrUrlContent = $patcherPath + "`n" + $patcherPathOrUrlContent
    }

    [string]$targetsAndPatternsContent = ExtractContent $cleanedTemplate "targets_and_patterns"
    [string]$hostsRemoveContent = ExtractContent $cleanedTemplate "hosts_remove"
    [string]$hostsAddContent = ExtractContent $cleanedTemplate "hosts_add"
    [string]$deleteNeedContent = ExtractContent $cleanedTemplate "files_or_folders_delete"
    [string[]]$createFilesFromTextContent = ExtractContent $cleanedTemplate "file_create_from_text" -saveEmptyLines -several
    [string[]]$createFilesFromBase64Content = ExtractContent $cleanedTemplate "file_create_from_base64" -saveEmptyLines -several
    [string]$firewallBlockContent = ExtractContent $cleanedTemplate "firewall_block"
    [string]$firewallRemoveBlockContent = ExtractContent $cleanedTemplate "firewall_remove_block"
    [string]$registryModifyContent = ExtractContent $cleanedTemplate "registry_file"
    [string]$powershellCodeContent = ExtractContent $cleanedTemplate "powershell_code"
    [string]$cmdCodeContent = ExtractContent $cleanedTemplate "cmd_code"


    # Simple detection for needed admins rights:
    # If we have data for Windows Registry or for Firewall
    # - we 100% need Administrator privileges for apply instructions for it

    if ((($hostsRemoveContent.Length -gt 0) -or ($hostsAddContent.Length -gt 0) -or ($firewallBlockContent.Length -gt 0) -or ($firewallRemoveBlockContent.Length -gt 0) -or ($registryModifyContent.Length -gt 0)) -and (-not (DoWeHaveAdministratorPrivileges))) {
        $argumentsBound = ($PSBoundParameters.GetEnumerator() | ForEach-Object {
            $valuePath = $_.Value
            if ($_.Key -eq 'templatePath') {
                $valuePath = $fullTemplatePath
            }
            if ($valuePath.StartsWith('.')) {
                $valuePath = $valuePath | Resolve-Path
            }
            "-$($_.Key) `"$($valuePath)`""
        }) -join " "

        Start-Process -Verb RunAs $PSHost ("-ExecutionPolicy Bypass -File `"$PSCommandPath`" $argumentsBound")
        break
    }
    
    # Start use parsed data from template file

    if ($variablesContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing template variables..."
        $variables = GetVariables $variablesContent
        Write-Host "Parsing template variables complete"
    }

    if ($patcherPathOrUrlContent.Length -gt 0) {
        Write-Host
        Write-Host "Start patcher path..."
        . (Resolve-Path ".\$getPatcherScriptName.ps1")
        [string]$patcherFile, [string]$patcherFileTempFlag = GetPatcherFile $patcherPathOrUrlContent
        Write-Host "Patcher received"
    }

    if ($targetsAndPatternsContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing patch targets and apply patches..."
        . (Resolve-Path ".\$detectFilesAndPatternsAndPatchScriptName.ps1")
        DetectFilesAndPatternsAndPatch -patcherFile $patcherFile -content $targetsAndPatternsContent
        Write-Host "Parsing patch targets and apply patches complete"    
    }

    if ($hostsRemoveContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines for remove from hosts..."
        . (Resolve-Path ".\$removeFromHostsScriptName.ps1")
        RemoveFromHosts $hostsRemoveContent
        Write-Host "Removing lines from hosts complete"
    }

    if ($hostsAddContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines for add to hosts..."
        . (Resolve-Path ".\$addToHostsScriptName.ps1")
        AddToHosts $hostsAddContent
        Write-Host "Adding lines to hosts complete"
    }

    if ($deleteNeedContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines with paths for files and folders delete..."
        . (Resolve-Path ".\$deleteFilesOrFoldersScriptName.ps1")
        DeleteFilesOrFolders $deleteNeedContent
        Write-Host "Deleting files and folders complete"
    }

    if (($createFilesFromTextContent.Count -gt 0) -and ($createFilesFromTextContent[0].Length -gt 0)) {
        Write-Host
        Write-Host "Start parsing lines for create files..."
        . (Resolve-Path ".\$createAllFilesFromTextOrBase64ScriptName.ps1")
        CreateAllFilesFromText $createFilesFromTextContent
        Write-Host "Creating text files complete"
    }

    if (($createFilesFromBase64Content.Count -gt 0) -and ($createFilesFromBase64Content[0].Length -gt 0)) {
        Write-Host
        Write-Host "Start parsing data for create files from base64..."
        . (Resolve-Path ".\$createAllFilesFromTextOrBase64ScriptName.ps1")
        CreateAllFilesFromBase64 $createFilesFromBase64Content
        Write-Host "Creating files from base64 complete"
    }

    if ($firewallRemoveBlockContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines paths for remove from firewall..."
        . (Resolve-Path ".\$blockOrRemoveFilesFromFirewallScriptName.ps1")
        RemoveBlockFilesFromFirewall $firewallRemoveBlockContent
        Write-Host "Remove rules from firewall complete"
    }

    if ($firewallBlockContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines paths for block in firewall..."
        . (Resolve-Path ".\$blockOrRemoveFilesFromFirewallScriptName.ps1")
        BlockFilesWithFirewall $firewallBlockContent
        Write-Host "Adding rules in firewall complete"
    }

    if ($registryModifyContent.Length -gt 0) {
        Write-Host
        Write-Host "Start parsing lines for modify registry..."
        . (Resolve-Path ".\$registryFileApplyScriptName.ps1")
        RegistryFileApply $registryModifyContent
        Write-Host "Modifying registry complete"
    }

    if ($powershellCodeContent.Length -gt 0) {
        Write-Host
        Write-Host "Start execute external Powershell code..."
        Write-Host
        . (Resolve-Path ".\$powershellCodeExecuteScriptName.ps1")
        PowershellCodeExecute $powershellCodeContent -hideExternalOutput
        Write-Host "Executing external Powershell code complete"
    }

    if ($cmdCodeContent.Length -gt 0) {
        Write-Host
        Write-Host "Start execute external CMD code..."
        Write-Host
        . (Resolve-Path ".\$cmdCodeExecuteScriptName.ps1")
        CmdCodeExecute $cmdCodeContent
        Write-Host "Executing external CMD code complete"
    }

    

    # Delete patcher or template files if it downloaded to temp file

    if ($patcherFileTempFlag -eq $fileIsTempFlag) {
        Remove-Item $patcherFile
    }

    if ($templateFileTempFlag -eq $fileIsTempFlag) {
        Remove-Item $fullTemplatePath
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$watch.Stop() # stop timer
Write-Host "Script execution time is" $watch.Elapsed # time of execution code

# Pause before exit like in CMD
Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
