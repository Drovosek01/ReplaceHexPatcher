param (
    [Parameter(Mandatory)]
    [string]$template
)


# =====
# GLOBAL VARIABLES
# =====

[string[]]$comments = @(';;', '#')
[bool]$needUsePatchSectionsOnly = $false

# Here will stored parsed template variables
[System.Collections.Hashtable]$variables = @{}
[System.Collections.Generic.HashSet[string]]$flagsAll = New-Object System.Collections.Generic.HashSet[string]

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) { 'PowerShell' } Else { 'PwSh' }
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$templateDir = ''
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


# Other flags for code
[string]$fileIsTempFlag = 'fileIsTemp'


# Template flags
[string]$MAKE_BACKUPS_flag_text='MAKE_BACKUPS'
[string]$REMOVE_SIGN_PATCHED_PE_flag_text='REMOVE_SIGN_PATCHED_PE'
[string]$CAN_USE_REGEXP_IN_PATCH_TEXT_flag_text='CAN_USE_REGEXP_IN_PATCH_TEXT'
[string]$PATCH_TEXT_IS_CASEINSENSITIVE_flag_text='PATCH_TEXT_IS_CASEINSENSITIVE'
[string]$WILDCARD_IS_1_Q_SYMBOL_flag_text='WILDCARD_IS_1_Q_SYMBOL'
[string]$VERBOSE_flag_text='VERBOSE'
[string]$CHECK_OCCURRENCES_ONLY_flag_text='CHECK_OCCURRENCES_ONLY'
[string]$CHECK_ALREADY_PATCHED_ONLY_flag_text='CHECK_ALREADY_PATCHED_ONLY'
[string]$EXIT_IF_NO_ADMINS_RIGHTS_flag_text='EXIT_IF_NO_ADMINS_RIGHTS'
[string]$ASK_ADMINS_RIGHTS_flag_text='ASK_ADMINS_RIGHTS'
[string]$SHOW_EXECUTION_TIME_flag_text='SHOW_EXECUTION_TIME'
[string]$SHOW_SPACES_IN_LOGGED_PATTERNS_flag_text='SHOW_SPACES_IN_LOGGED_PATTERNS'
[string]$REMOVE_SPACES_IN_LOGGED_PATTERNS_flag_text='REMOVE_SPACES_IN_LOGGED_PATTERNS'
[string]$PATCH_ONLY_ALL_BIN_PATTERNS_EXIST_flag_text='PATCH_ONLY_ALL_BIN_PATTERNS_EXIST'
[string]$PATCH_ONLY_ALL_BIN_PATTERNS_EXIST_1_TIME_flag_text='PATCH_ONLY_ALL_BIN_PATTERNS_EXIST_1_TIME'
[string]$EXIT_IF_ANY_PATCH_BIN_FILE_NOT_EXIST_flag_text='EXIT_IF_ANY_PATCH_BIN_FILE_NOT_EXIST'
[string]$EXIT_IF_ANY_PATCH_TEXT_FILE_NOT_EXIST_flag_text='EXIT_IF_ANY_PATCH_TEXT_FILE_NOT_EXIST'


# Names loaded .ps1 files
[string]$coreScriptName = 'ReplaceHexBytesAll'
[string]$detectFilesAndPatternsAndPatchBinaryScriptName = 'DetectFilesAndPatternsAndPatchBinary'
[string]$detectFilesAndPatternsAndPatchTextScriptName = 'DetectFilesAndPatternsAndPatchText'
[string]$removeFromHostsScriptName = 'RemoveFromHosts'
[string]$addToHostsScriptName = 'AddToHosts'
[string]$deleteFilesOrFoldersScriptName = 'DeleteFilesOrFolders'
[string]$createAllFilesFromTextOrBase64ScriptName = 'CreateAllFilesFromTextOrBase64'
[string]$blockOrRemoveFilesFromFirewallScriptName = 'BlockOrRemoveFilesFromFirewall'
[string]$registryFileApplyScriptName = 'RegistryFileApply'
[string]$powershellCodeExecuteScriptName = 'PowershellCodeExecute'
[string]$cmdCodeExecuteScriptName = 'CmdCodeExecute'

# Backup direct links for loaded .ps1 files if they not placed in folder
[string]$coreScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/refs/heads/main/core/v2/ReplaceHexBytesAll.ps1'
[string]$detectFilesAndPatternsAndPatchBinaryScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/DetectFilesAndPatternsAndPatchBinary.ps1'
[string]$detectFilesAndPatternsAndPatchTextScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/DetectFilesAndPatternsAndPatchText.ps1'
[string]$removeFromHostsScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/RemoveFromHosts.ps1'
[string]$addToHostsScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/AddToHosts.ps1'
[string]$deleteFilesOrFoldersScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/DeleteFilesOrFolders.ps1'
[string]$createAllFilesFromTextOrBase64ScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/CreateAllFilesFromTextOrBase64.ps1'
[string]$blockOrRemoveFilesFromFirewallScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/BlockOrRemoveFilesFromFirewall.ps1'
[string]$registryFileApplyScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/RegistryFileApply.ps1'
[string]$powershellCodeExecuteScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/PowershellCodeExecute.ps1'
[string]$cmdCodeExecuteScriptURL = 'https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data%20in%20template/libraries/CmdCodeExecute.ps1'

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
    }
    else {
        return $true
    }
}

<#
.DESCRIPTION
Check whether we (the current script process) need administrator rights to change a file or folder

.INPUTS
Path to file or folder

.OUTPUTS
True if need admin rights for modify file/folder otherwise - false
#>
function Test-FileAdminRequired {
    [OutputType([bool])]
    param([string]$targetPath)
    
    if (-not (Test-Path $targetPath)) {
        return $false
    }
    
    try {
        $acl = Get-Acl -Path $targetPath
        $accessRules = $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
        
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
        
        $hasWriteAccess = $false
        
        foreach ($rule in $accessRules) {
            # Checking whether the rule applies to the current user or his groups
            if ($principal.IsInRole($rule.IdentityReference) -or 
                $rule.IdentityReference.Value -eq $currentUser.Name -or
                $rule.IdentityReference.Value -eq "BUILTIN\Users" -or
                $rule.IdentityReference.Value -eq "NT AUTHORITY\Authenticated Users") {
                
                if (($rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Write) -eq [System.Security.AccessControl.FileSystemRights]::Write -and
                    $rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
                    $hasWriteAccess = $true
                    break
                }
            }
        }
        
        return (-not $hasWriteAccess)
    }
    catch {
        Write-ProblemMsg "Error during check wights for: $($_.Exception.Message)"
        return $false
    }
}


<#
.DESCRIPTION
Replace template variables with text
and return cleaned template content
#>
function ReplaceGlobalVariables {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$filePath
    )

    [string[]]$content = [System.IO.File]::ReadAllLines($filePath, [System.Text.Encoding]::UTF8)

    # Replace $USER to current username
    $content = $content -ireplace '\$USER', $env:USERNAME
    # Replace USERNAME_FIELD to current username
    $content = $content -ireplace 'USERNAME_FIELD', $env:USERNAME
    # Replace USERPROFILE_FIELD to current username
    $content = $content -ireplace 'USERPROFILE_FIELD', $env:USERPROFILE
    # Replace USERHOME_FIELD to current username
    $content = $content -ireplace 'USERHOME_FIELD', $env:USERPROFILE

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
    }
    else {
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
    }
    elseif ($endLinesForResult -eq 'LF') {
        $endLinesResult = "`n"
    }
    else {
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
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$content,
        [Parameter(Mandatory)]
        [string]$sectionName,
        [string]$commentExclusionItem,
        [switch]$saveEmptyLines = $false
    )

    [string]$cleanedTemplateContent = ""
    [string]$startSectionName = "[start-$sectionName]"
    [string]$endSectionName = "[end-$sectionName]"

    [string[]]$cleanedComments = $comments -ne $commentExclusionItem
    $pattern = ($cleanedComments | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $cleanedTemplateContent = ($content.Clone() -split "`r?`n" | Where-Object { $_ -notmatch $pattern }) -join "`n"

    # Remove lines with current template-comments tag
    foreach ($comment in $cleanedComments) {
        $cleanedTemplateContent = $cleanedTemplateContent | select-string -pattern $comment -notmatch
    }
    
    if (-not $saveEmptyLines) {
        $cleanedTemplateContent = RemoveEmptyLines $cleanedTemplateContent
    }

    # start position content between content tags (+1 mean not include in content \n after start tag)
    [int]$startSectionIndex = $cleanedTemplateContent.IndexOf($startSectionName)
    [int]$startContentIndex = $startSectionIndex + $startSectionName.Length
    if ($cleanedTemplateContent[$startContentIndex] -eq "`n") {
        $startContentIndex += 1
    }
    if (($cleanedTemplateContent[$startContentIndex] -eq "`r") -and ($cleanedTemplateContent[$startContentIndex + 1] -eq "`n")) {
        $startContentIndex += 2
    }
    
    # end position content between content tags
    [int]$endContentIndex = $cleanedTemplateContent.IndexOf($endSectionName)
    
    if (($startSectionIndex -eq -1) -or ($startSectionIndex -eq -1)) {
        return ''
    }
    if ($startContentIndex -gt $endContentIndex) {
        Write-Error "Wrong template. Error on parse section $sectionName"
        exit 1
    }

    return $cleanedTemplateContent.Substring($startContentIndex, $endContentIndex - $startContentIndex)
}


<#
.DESCRIPTION
Return True if current script have Admins privileges
otherwise return false
#>
function Stop-ExecIfNotAdminsRights {
    [bool]$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-ProblemMsg "Need administrator privileges for handle given template!"
        Write-ProblemMsg "Restart Powershell with admins rights and execute script again"
        exit 1
    }
}


<#
.DESCRIPTION
Analyze content-text with flags and
add all flags to global hash set
#>
function HandleFlagsContent {
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    foreach ($line in $content -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()
        [void]($flagsAll.Add($line))
    }
}


<#
.DESCRIPTION
Analyze hash-set with flags and apply global flags
#>
function HandlePatcherFlags {
    param (
        [System.Collections.Generic.HashSet[string]]$flags
    )

    if ($flags.Count -eq 0) {
        return
    }

    if ($flags.Contains($EXIT_IF_NO_ADMINS_RIGHTS_flag_text)) {
        Stop-ExecIfNotAdminsRights
    }

    if ($flags.Contains($ASK_ADMINS_RIGHTS_flag_text) -and (-not (DoWeHaveAdministratorPrivileges))) {
        Start-Process -Verb RunAs $PSHost ("-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argumentsBound")
        break
    }
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
        }
        else {
            $tempSplitLine = $line.Split("=")
            [void]$variables.Add($tempSplitLine[0].Trim(), $tempSplitLine[1].Trim())
        }
    }

    $cleanedVariables = $variables.Clone()

    # Variable values can also contain variables
    # loop all variable values and replace variables keys to values if it contain it
    foreach ($key in $variables.Keys) {
        $variables.Keys | foreach {
            if ($_ -eq $key) {
                return
            }
            
            $cleanedVariables[$_] = $cleanedVariables[$_].Replace($key, $cleanedVariables[$key])
        }
    }

    return $cleanedVariables
}


<#
.DESCRIPTION
Function try decode given text from base64 to default text
Return decoded text if decoded without problems
Otherwise return $null
#>
function ConvertFrom-Base64 {
    param (
        [Parameter(Mandatory)]
        [string]$base64String
    )

    try {
        [byte[]]$decodedData = [System.Convert]::FromBase64String($base64String)
        return [System.Text.Encoding]::UTF8.GetString($decodedData)
    }
    catch {
        return $null
    }
}


<#
.DESCRIPTION
Function try decode given text from base64 to default text
If text decoded without problems - it save decoded text to temp file and return path to file
Otherwise return $null
#>
function TryDecodeIfBase64 {
    param (
        [Parameter(Mandatory)]
        [string]$base64String
    )
    
    try {
        [byte[]]$decodedData = [System.Convert]::FromBase64String($base64String)
        [string]$decodedText = [System.Text.Encoding]::UTF8.GetString($decodedData)

        [string]$tempFile = [System.IO.Path]::GetTempFileName()
        Get-Process | Where-Object { $_.CPU -ge 1 } | Out-File $tempFile
        $decodedText | Out-File -FilePath $tempFile -Encoding utf8 -Force
        $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf(".")) + ".txt")
        Rename-Item $tempFile $renamedTempFile

        return (Get-ChildItem $renamedTempFile).FullName
    }
    catch {
        return $null
    }
}

<#
.DESCRIPTION
The path to the template is passed as an argument to this script.
This can be the path to a file on your computer or the URL to the template text.
This function checks for the presence of a file on the computer if it is the path to the file,
    or creates a temporary file and downloads a template from the specified URL into it
#>
function Get-TemplateFile {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$templateWay,
        [Parameter(Mandatory)]
        # [System.Collections.Generic.List[string]]
        [ref]$tempFilesList
    )

    $decodedTemplate = ''

    if ((Test-Path $templateWay 2>$null) -or (Test-Path -LiteralPath $templateWay 2>$null)) {
        # case when template is path to file
        [string]$filePathFull_Unescaped = [System.IO.Path]::GetFullPath(($templateWay -ireplace "``", ""))
        [string]$filePathFull = [System.Management.Automation.WildcardPattern]::Escape($filePathFull_Unescaped)

        $content = [System.IO.File]::ReadAllText($templateWay)

        if ($filePathFull.Contains($env:Temp)) {
            [void]($tempFilesList.Value.Add($filePathFull))
        }

        if (($decodedTemplatePath = TryDecodeIfBase64 $content) -and $decodedTemplatePath) {
            [void]($tempFilesList.Value.Add($decodedTemplatePath))
            return (Get-ChildItem $decodedTemplatePath).FullName
        }
        
        return (Get-ChildItem $filePathFull).FullName
    }
    elseif ($templateWay.StartsWith("http") -and ((Invoke-WebRequest -UseBasicParsing -Uri $templateWay).StatusCode -eq 200)) {
        # case when template is URL
        [string]$tempFile = [System.IO.Path]::GetTempFileName()
        Get-Process | Where-Object { $_.CPU -ge 1 } | Out-File $tempFile
        (New-Object System.Net.WebClient).DownloadFile($templateWay, $tempFile)
        $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf(".")) + ".txt")
        Rename-Item $tempFile $renamedTempFile
        [void]($tempFilesList.Value.Add($renamedTempFile))

        $content = [System.IO.File]::ReadAllText($renamedTempFile)

        if (($decodedTemplatePath = TryDecodeIfBase64 $content) -and $decodedTemplatePath) {
            [void]($tempFilesList.Value.Add($decodedTemplatePath))
            return (Get-ChildItem $decodedTemplatePath).FullName
        }
        
        return (Get-ChildItem $renamedTempFile).FullName
    }
    else {
        # case when template is string
        [string]$tempFile = [System.IO.Path]::GetTempFileName()
        Get-Process | Where-Object { $_.CPU -ge 1 } | Out-File $tempFile
        $templateWay | Out-File -FilePath $tempFile -Encoding utf8 -Force
        $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf(".")) + ".txt")
        Rename-Item $tempFile $renamedTempFile
        [void]($tempFilesList.Value.Add($renamedTempFile))

        $content = [System.IO.File]::ReadAllText($renamedTempFile)

        if (($decodedTemplatePath = TryDecodeIfBase64 $content) -and $decodedTemplatePath) {
            [void]($tempFilesList.Value.Add($decodedTemplatePath))
            return (Get-ChildItem $decodedTemplatePath).FullName
        }

        return (Get-ChildItem $renamedTempFile).FullName
    }
    
    Write-Error "No valid template"
    exit 1
}


<#
.SYNOPSIS
Download Powershell script in temp file and rename it to given name
#>
function DownloadPSScript {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$link,
        [Parameter(Mandatory)]
        [string]$fileNameFull
    )
    
    [string]$filePathFull = "${env:Temp}\$fileNameFull.ps1"

    try {
        if (Test-Path $filePathFull) {
            Remove-Item -Path $filePathFull -Force -ErrorAction Stop
            # TODO: Maybe need check if file is using and kill process for kill process using this file
        }
    
        (New-Object System.Net.WebClient).DownloadFile($link, $filePathFull)
    }
    catch {
        Write-Error "Something wrong when download external Powershell-script. Error message is: $_.Exception.Message"
        exit 1
    }

    return $filePathFull
}


<#
.DESCRIPTION
Check all given arguments like paths to files
and if any file not exist - write message about it and return false
otherwise return true

.INPUTS
Array of strings-paths or each string-path in separate argument

.OUTPUTS
True if all files exist
#>
function Test-AllFilePaths {
    if ($args[0] -is [array]) {
        $args = $args[0]
    }
    
    foreach ($path in $args) {
        if (-not (Test-Path $path -PathType Leaf)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                # throw [System.IO.FileNotFoundException]::new("File not found: $path")
                Write-Host "File not found: $path"
                return $false
            }
        }
    }

    return $true
}


<#
.SYNOPSIS
They will check whether the string looks like the path to a folder or file in Windows (fle system path)

.DESCRIPTION
If we have lines of text (hex patterns and paths) that contain paths to existing and non-existing files, how do we check that the string being processed is the path to the file, but the file is not on disk?
We can assume that...

Here are examples of file paths in Windows:
C:\Windows\System32\notepad.exe
..\Pictures\photo.jpg
\\MyServer\SharedData\file.doc
\\?\D:\...\file.txt

Based on these examples, the function implements the calculation of the assumption that the string passed to the function is the path to a file or folder in Windows.

Paths with environment variables are not supported and will not be considered a path:
%USERPROFILE%\Desktop
You need to replace the environment variables with their values in the passed strings before passing them to this function.
#>
function DoesItLooksLikeFSPath {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$text
    )

    if ($text -eq $null -or $text -eq "") {
        return $false
    }
    
    if ($text.Contains(":\") -or $text.Contains("\\") -or $text.StartsWith("..\") -or $text.StartsWith(".\")) {
        return $true
    }

    return $false
}


<#
.SYNOPSIS
Write-Host given text with yellow prefix "[WARN]: "
#>
function Write-WarnMsg {
    param (
        [Parameter(Mandatory)]
        [string]$text
    )

    if (-not $flagsAll.Contains($VERBOSE_flag_text)) {
        return
    }
    
    # TODO: change yellow to orange
    Write-Host "[WARN]: " -ForegroundColor Yellow -NoNewline
    Write-Host $text
}


<#
.SYNOPSIS
Write-Host given text without changes just with filter VERBOSE flag
#>
function Write-Msg {
    param (
        [string]$text = ''
    )

    if (-not $flagsAll.Contains($VERBOSE_flag_text)) {
        return
    }
    
    Write-Host $text
}


<#
.SYNOPSIS
Write-Host given text with green prefix "[INFO]: "
#>
function Write-InfoMsg {
    param (
        [Parameter(Mandatory)]
        [string]$text,
        [switch]$isHeader
    )

    if (-not $flagsAll.Contains($VERBOSE_flag_text)) {
        return
    }
    
    if ($isHeader) {
        Write-Host
    }
    Write-Host "[INFO]: " -ForegroundColor Green -NoNewline
    Write-Host $text
}


<#
.SYNOPSIS
Write-Host given text with red prefix "[PROBLEM]: "
#>
function Write-ProblemMsg {
    param (
        [Parameter(Mandatory)]
        [string]$text
    )

    if (-not $flagsAll.Contains($VERBOSE_flag_text)) {
        return
    }
    
    Write-Host "[PROBLEM]: " -ForegroundColor Red -NoNewline
    Write-Host $text
}



# =====
# MAIN
# =====


$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    [System.Collections.Generic.List[string]]$tempFilesForRemove = New-Object System.Collections.Generic.List[string]
    [string]$fullTemplatePath = Get-TemplateFile -templateWay $template -tempFilesList ([ref]$tempFilesForRemove)
    [string]$cleanedTemplate = ReplaceGlobalVariables $fullTemplatePath
    $templateDir = [System.IO.Path]::GetDirectoryName($fullTemplatePath)

    Set-Location $scriptDir


    # Get content from template file

    [string]$variablesContent = ExtractContent $cleanedTemplate "variables"
    [string]$patchBinContent = ExtractContent $cleanedTemplate "patch_bin"
    [string]$patchTextContent = ExtractContent $cleanedTemplate "patch_text"
    [string]$flagsContent = ExtractContent $cleanedTemplate "flags"
    [string]$hostsRemoveContent = ExtractContent $cleanedTemplate "hosts_remove" -commentExclusionItem "#"
    [string]$hostsAddContent = ExtractContent $cleanedTemplate "hosts_add" -commentExclusionItem "#"
    [string]$deleteNeedContent = ExtractContent $cleanedTemplate "files_or_folders_delete"
    [string]$createFilesFromTextContent = ExtractContent $cleanedTemplate "file_create_from_text" -saveEmptyLines
    [string]$createFilesFromBase64Content = ExtractContent $cleanedTemplate "file_create_from_base64" -saveEmptyLines
    [string]$firewallBlockContent = ExtractContent $cleanedTemplate "firewall_block"
    [string]$firewallRemoveBlockContent = ExtractContent $cleanedTemplate "firewall_remove_block"
    [string]$registryModifyContent = ExtractContent $cleanedTemplate "registry_file" -saveEmptyLines
    [string]$prePowershellCodeContent = ExtractContent $cleanedTemplate "pre_powershell_code" -saveEmptyLines
    [string]$preCmdCodeContent = ExtractContent $cleanedTemplate "pre_cmd_code" -saveEmptyLines
    [string]$postPowershellCodeContent = ExtractContent $cleanedTemplate "post_powershell_code" -saveEmptyLines
    [string]$postCmdCodeContent = ExtractContent $cleanedTemplate "post_cmd_code" -saveEmptyLines


    # Simple detection for needed admins rights:
    # If we have data for Windows Registry or for Firewall
    # - we 100% need Administrator privileges for apply instructions for it

    if ((($hostsRemoveContent.Length -gt 0) -or ($hostsAddContent.Length -gt 0) -or ($firewallBlockContent.Length -gt 0) -or ($firewallRemoveBlockContent.Length -gt 0) -or ($registryModifyContent.Length -gt 0)) -and (-not (DoWeHaveAdministratorPrivileges))) {
        Start-Process -Verb RunAs $PSHost ("-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argumentsBound")
        break
    }

    if ($flagsContent.Length -gt 0) {
        Write-InfoMsg "Start checking template flags..." -isHeader

        HandleFlagsContent $flagsContent
        HandlePatcherFlags -flags $flagsAll

        if ($flagsAll.Contains($CHECK_OCCURRENCES_ONLY_flag_text) -or $flagsAll.Contains($CHECK_ALREADY_PATCHED_ONLY_flag_text)) {
            $needUsePatchSectionsOnly = $true
        }
        Write-InfoMsg "End checking template flags"
    }
    
    # Start use parsed data from template file

    if ($variablesContent.Length -gt 0) {
        Write-InfoMsg "Start parsing template variables..." -isHeader
        $variables = GetVariables $variablesContent
        Write-InfoMsg "Parsing template variables complete"
    }
    
    Write-InfoMsg "Start getting patcher core..." -isHeader
    
    # Import external Powershell-code
    $coreScriptNameFull = "$coreScriptName.ps1"
    [string]$patcherFilePath = ''
    if (Test-Path ".\$coreScriptNameFull") {
        $patcherFilePath = (Resolve-Path ".\$coreScriptNameFull")
    }
    elseif (Test-Path "..\..\core\v2\$coreScriptNameFull") {
        $patcherFilePath = (Resolve-Path "..\..\core\v2\$coreScriptNameFull")
    }
    elseif (Test-Path ".\libraries\$coreScriptNameFull") {
        $patcherFilePath = (Resolve-Path ".\libraries\$coreScriptNameFull")
    }
    else {
        $patcherFilePath = (DownloadPSScript -link $coreScriptURL -fileName $coreScriptNameFull)
        [void]($tempFilesForRemove.Add($patcherFilePath))
    }
    
    Write-InfoMsg "Patcher code received"

    if (($prePowershellCodeContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start execute external pre-patch Powershell code..." -isHeader

        # Import external Powershell-code
        $powershellCodeExecuteScriptNameFull = "$powershellCodeExecuteScriptName.ps1"
        if (Test-Path ".\$powershellCodeExecuteScriptNameFull") {
            . (Resolve-Path ".\$powershellCodeExecuteScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$powershellCodeExecuteScriptNameFull") {
            . (Resolve-Path ".\libraries\$powershellCodeExecuteScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $powershellCodeExecuteScriptURL -fileName $powershellCodeExecuteScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        PowershellCodeExecute $prePowershellCodeContent
        Write-InfoMsg "Executing external pre-patch Powershell code complete"
    }

    if (($preCmdCodeContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start execute external pre-patch CMD code..." -isHeader

        # Import external Powershell-code
        $cmdCodeExecuteScriptNameFull = "$cmdCodeExecuteScriptName.ps1"
        if (Test-Path ".\$cmdCodeExecuteScriptNameFull") {
            . (Resolve-Path ".\$cmdCodeExecuteScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$cmdCodeExecuteScriptNameFull") {
            . (Resolve-Path ".\libraries\$cmdCodeExecuteScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $cmdCodeExecuteScriptURL -fileName $cmdCodeExecuteScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        CmdCodeExecute $preCmdCodeContent
        Write-InfoMsg "Executing external pre-patch CMD code complete"
    }
    
    if ($patchBinContent.Length -gt 0) {
        Write-InfoMsg "Start parsing binary patch targets and apply patches..." -isHeader
        
        # Import external Powershell-code
        $detectFilesAndPatternsAndPatchBinaryScriptNameFull = "$detectFilesAndPatternsAndPatchBinaryScriptName.ps1"
        if (Test-Path ".\$detectFilesAndPatternsAndPatchBinaryScriptNameFull") {
            . (Resolve-Path ".\$detectFilesAndPatternsAndPatchBinaryScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$detectFilesAndPatternsAndPatchBinaryScriptNameFull") {
            . (Resolve-Path ".\libraries\$detectFilesAndPatternsAndPatchBinaryScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $detectFilesAndPatternsAndPatchBinaryScriptURL -fileName $detectFilesAndPatternsAndPatchBinaryScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        DetectFilesAndPatternsAndPatchBinary -patcherFilePath $patcherFilePath -content $patchBinContent -flags $flagsAll

        Write-InfoMsg "Parsing patch targets and apply binary patches complete"    
    }
    
    if ($patchTextContent.Length -gt 0) {
        Write-InfoMsg "Start parsing text patch targets and apply patches..." -isHeader
        
        # Import external Powershell-code
        $detectFilesAndPatternsAndPatchTextScriptNameFull = "$detectFilesAndPatternsAndPatchTextScriptName.ps1"
        if (Test-Path ".\$detectFilesAndPatternsAndPatchTextScriptNameFull") {
            . (Resolve-Path ".\$detectFilesAndPatternsAndPatchTextScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$detectFilesAndPatternsAndPatchTextScriptNameFull") {
            . (Resolve-Path ".\libraries\$detectFilesAndPatternsAndPatchTextScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $detectFilesAndPatternsAndPatchTextScriptURL -fileName $detectFilesAndPatternsAndPatchTextScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }
        
        DetectFilesAndPatternsAndPatchText -content $patchTextContent -flags $flagsAll

        Write-InfoMsg "Parsing patch targets and apply text patches complete"    
    }
    
    if (($hostsRemoveContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start parsing lines for remove from hosts..." -isHeader

        # Import external Powershell-code
        $removeFromHostsScriptNameFull = "$removeFromHostsScriptName.ps1"
        if (Test-Path ".\$removeFromHostsScriptNameFull") {
            . (Resolve-Path ".\$removeFromHostsScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$removeFromHostsScriptNameFull") {
            . (Resolve-Path ".\libraries\$removeFromHostsScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $removeFromHostsScriptURL -fileName $removeFromHostsScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        RemoveFromHosts $hostsRemoveContent
        
        Write-InfoMsg "Removing lines from hosts complete"
    }

    if (($hostsAddContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start parsing lines for add to hosts..." -isHeader

        # Import external Powershell-code
        $addToHostsScriptNameFull = "$addToHostsScriptName.ps1"
        if (Test-Path ".\$addToHostsScriptNameFull") {
            . (Resolve-Path ".\$addToHostsScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$addToHostsScriptNameFull") {
            . (Resolve-Path ".\libraries\$addToHostsScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $addToHostsScriptURL -fileName $addToHostsScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        AddToHosts $hostsAddContent
        
        Write-InfoMsg "Adding lines to hosts complete"
    }

    if (($deleteNeedContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start parsing lines with paths for files and folders delete..." -isHeader

        # Import external Powershell-code
        $deleteFilesOrFoldersScriptNameFull = "$deleteFilesOrFoldersScriptName.ps1"
        if (Test-Path ".\$deleteFilesOrFoldersScriptNameFull") {
            . (Resolve-Path ".\$deleteFilesOrFoldersScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$deleteFilesOrFoldersScriptNameFull") {
            . (Resolve-Path ".\libraries\$deleteFilesOrFoldersScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $deleteFilesOrFoldersScriptURL -fileName $deleteFilesOrFoldersScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        DeleteFilesOrFolders $deleteNeedContent
        
        Write-InfoMsg "Deleting files and folders complete"
    }
    
    if (($createFilesFromTextContent.Count -gt 0) -and ($createFilesFromTextContent[0].Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start parsing lines for create files..." -isHeader
        
        if (-not (Get-Command -Name DeleteFilesOrFolders -ErrorAction SilentlyContinue)) {
            # Import external Powershell-code
            $deleteFilesOrFoldersScriptNameFull = "$deleteFilesOrFoldersScriptName.ps1"
            if (Test-Path ".\$deleteFilesOrFoldersScriptNameFull") {
                . (Resolve-Path ".\$deleteFilesOrFoldersScriptNameFull")
            }
            elseif (Test-Path ".\libraries\$deleteFilesOrFoldersScriptNameFull") {
                . (Resolve-Path ".\libraries\$deleteFilesOrFoldersScriptNameFull")
            }
            else {
                $tempPSFile = (DownloadPSScript -link $deleteFilesOrFoldersScriptURL -fileName $deleteFilesOrFoldersScriptNameFull)
                [void]($tempFilesForRemove.Add($tempPSFile))
                . $tempPSFile
            }
        }

        if (Get-Command -Name CreateAllFilesFromText -ErrorAction SilentlyContinue) {
            CreateAllFilesFromText $createFilesFromTextContent
        }
        else {
            # Import external Powershell-code
            $createAllFilesFromTextOrBase64ScriptNameFull = "$createAllFilesFromTextOrBase64ScriptName.ps1"
            if (Test-Path ".\$createAllFilesFromTextOrBase64ScriptNameFull") {
                . (Resolve-Path ".\$createAllFilesFromTextOrBase64ScriptNameFull")
            }
            elseif (Test-Path ".\libraries\$createAllFilesFromTextOrBase64ScriptNameFull") {
                . (Resolve-Path ".\libraries\$createAllFilesFromTextOrBase64ScriptNameFull")
            }
            else {
                $tempPSFile = (DownloadPSScript -link $createAllFilesFromTextOrBase64ScriptURL -fileName $createAllFilesFromTextOrBase64ScriptNameFull)
                [void]($tempFilesForRemove.Add($tempPSFile))
                . $tempPSFile
            }

            CreateAllFilesFromText $createFilesFromTextContent
        }

        Write-InfoMsg "Creating text files complete"
    }

    if (($createFilesFromBase64Content.Count -gt 0) -and ($createFilesFromBase64Content[0].Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start parsing data for create files from base64..." -isHeader

        if (-not (Get-Command -Name DeleteFilesOrFolders -ErrorAction SilentlyContinue)) {
            # Import external Powershell-code
            $deleteFilesOrFoldersScriptNameFull = "$deleteFilesOrFoldersScriptName.ps1"
            if (Test-Path ".\$deleteFilesOrFoldersScriptNameFull") {
                . (Resolve-Path ".\$deleteFilesOrFoldersScriptNameFull")
            }
            elseif (Test-Path ".\libraries\$deleteFilesOrFoldersScriptNameFull") {
                . (Resolve-Path ".\libraries\$deleteFilesOrFoldersScriptNameFull")
            }
            else {
                $tempPSFile = (DownloadPSScript -link $deleteFilesOrFoldersScriptURL -fileName $deleteFilesOrFoldersScriptNameFull)
                [void]($tempFilesForRemove.Add($tempPSFile))
                . $tempPSFile
            }
        }

        if (Get-Command -Name CreateAllFilesFromBase64 -ErrorAction SilentlyContinue) {
            CreateAllFilesFromBase64 $createFilesFromBase64Content
        }
        else {
            # Import external Powershell-code
            $createAllFilesFromTextOrBase64ScriptNameFull = "$createAllFilesFromTextOrBase64ScriptName.ps1"
            if (Test-Path ".\$createAllFilesFromTextOrBase64ScriptNameFull") {
                . (Resolve-Path ".\$createAllFilesFromTextOrBase64ScriptNameFull")
            }
            elseif (Test-Path ".\libraries\$createAllFilesFromTextOrBase64ScriptNameFull") {
                . (Resolve-Path ".\libraries\$createAllFilesFromTextOrBase64ScriptNameFull")
            }
            else {
                $tempPSFile = (DownloadPSScript -link $createAllFilesFromTextOrBase64ScriptURL -fileName $createAllFilesFromTextOrBase64ScriptNameFull)
                [void]($tempFilesForRemove.Add($tempPSFile))
                . $tempPSFile
            }

            CreateAllFilesFromBase64 $createFilesFromBase64Content
        }

        Write-InfoMsg "Creating files from base64 complete"
    }

    if (($firewallRemoveBlockContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start parsing lines paths for remove from firewall..." -isHeader

        if (Get-Command -Name RemoveBlockFilesFromFirewall -ErrorAction SilentlyContinue) {
            RemoveBlockFilesFromFirewall $firewallRemoveBlockContent
        }
        else {
            # Import external Powershell-code
            $blockOrRemoveFilesFromFirewallScriptNameFull = "$blockOrRemoveFilesFromFirewallScriptName.ps1"
            if (Test-Path ".\$blockOrRemoveFilesFromFirewallScriptNameFull") {
                . (Resolve-Path ".\$blockOrRemoveFilesFromFirewallScriptNameFull")
            }
            elseif (Test-Path ".\libraries\$blockOrRemoveFilesFromFirewallScriptNameFull") {
                . (Resolve-Path ".\libraries\$blockOrRemoveFilesFromFirewallScriptNameFull")
            }
            else {
                $tempPSFile = (DownloadPSScript -link $blockOrRemoveFilesFromFirewallScriptURL -fileName $blockOrRemoveFilesFromFirewallScriptNameFull)
                [void]($tempFilesForRemove.Add($tempPSFile))
                . $tempPSFile
            }

            RemoveBlockFilesFromFirewall $firewallRemoveBlockContent
        }

        Write-InfoMsg "Remove rules from firewall complete"
    }

    if (($firewallBlockContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start parsing lines paths for block in firewall..." -isHeader

        if (Get-Command -Name BlockFilesWithFirewall -ErrorAction SilentlyContinue) {
            BlockFilesWithFirewall $firewallBlockContent
        }
        else {
            # Import external Powershell-code
            $blockOrRemoveFilesFromFirewallScriptNameFull = "$blockOrRemoveFilesFromFirewallScriptName.ps1"
            if (Test-Path ".\$blockOrRemoveFilesFromFirewallScriptNameFull") {
                . (Resolve-Path ".\$blockOrRemoveFilesFromFirewallScriptNameFull")
            }
            elseif (Test-Path ".\libraries\$blockOrRemoveFilesFromFirewallScriptNameFull") {
                . (Resolve-Path ".\libraries\$blockOrRemoveFilesFromFirewallScriptNameFull")
            }
            else {
                $tempPSFile = (DownloadPSScript -link $blockOrRemoveFilesFromFirewallScriptURL -fileName $blockOrRemoveFilesFromFirewallScriptNameFull)
                [void]($tempFilesForRemove.Add($tempPSFile))
                . $tempPSFile
            }

            BlockFilesWithFirewall $firewallBlockContent
        }

        Write-InfoMsg "Adding rules in firewall complete"
    }

    if (($registryModifyContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start parsing lines for modify registry..." -isHeader

        # Import external Powershell-code
        $registryFileApplyScriptNameFull = "$registryFileApplyScriptName.ps1"
        if (Test-Path ".\$registryFileApplyScriptNameFull") {
            . (Resolve-Path ".\$registryFileApplyScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$registryFileApplyScriptNameFull") {
            . (Resolve-Path ".\libraries\$registryFileApplyScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $registryFileApplyScriptURL -fileName $registryFileApplyScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        RegistryFileApply $registryModifyContent
        Write-InfoMsg "Modifying registry complete"
    }

    if (($postPowershellCodeContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start execute external post-patch Powershell code..." -isHeader

        # Import external Powershell-code
        $powershellCodeExecuteScriptNameFull = "$powershellCodeExecuteScriptName.ps1"
        if (Test-Path ".\$powershellCodeExecuteScriptNameFull") {
            . (Resolve-Path ".\$powershellCodeExecuteScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$powershellCodeExecuteScriptNameFull") {
            . (Resolve-Path ".\libraries\$powershellCodeExecuteScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $powershellCodeExecuteScriptURL -fileName $powershellCodeExecuteScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        PowershellCodeExecute $postPowershellCodeContent
        Write-InfoMsg "Executing external post-patch Powershell code complete"
    }

    if (($postCmdCodeContent.Length -gt 0) -and (-not $needUsePatchSectionsOnly)) {
        Write-InfoMsg "Start execute external post-patch CMD code..." -isHeader

        # Import external Powershell-code
        $cmdCodeExecuteScriptNameFull = "$cmdCodeExecuteScriptName.ps1"
        if (Test-Path ".\$cmdCodeExecuteScriptNameFull") {
            . (Resolve-Path ".\$cmdCodeExecuteScriptNameFull")
        }
        elseif (Test-Path ".\libraries\$cmdCodeExecuteScriptNameFull") {
            . (Resolve-Path ".\libraries\$cmdCodeExecuteScriptNameFull")
        }
        else {
            $tempPSFile = (DownloadPSScript -link $cmdCodeExecuteScriptURL -fileName $cmdCodeExecuteScriptNameFull)
            [void]($tempFilesForRemove.Add($tempPSFile))
            . $tempPSFile
        }

        CmdCodeExecute $postCmdCodeContent
        Write-InfoMsg "Executing external post-patch CMD code complete"
    }

    # Delete patcher or template files if it downloaded to temp file

    if ($patcherFileTempFlag -eq $fileIsTempFlag) {
        Remove-Item $patcherFile
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    # Delete all temp Powershell-script files
    $tempFilesForRemove | foreach { Remove-Item -Path $_ -Force 2>$null }
}

if ($flagsAll.Contains($SHOW_EXECUTION_TIME_flag_text)) {
    $watch.Stop() # stop timer
    Write-Host "Script execution time is $($watch.Elapsed)" # time of execution code
}

# Pause before exit like in CMD
Write-Host -NoNewLine 'Press any key to continue...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
