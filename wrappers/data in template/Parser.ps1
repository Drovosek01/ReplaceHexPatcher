param (
    [Parameter(Mandatory)]
    [string]$templatePath
)


# =====
# GLOBAL VARIABLES
# =====

# Same splitter like in core script
$patternSplitters = @('/','\','|')

$comments = @(';', '::')

# Text - flags in parse sections
[string]$notModifyFlag = 'NOT MODIFY IT'
[string]$moveToBinFlag = 'MOVE TO BIN'



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
    $content = $content -ireplace '\$USER', "$env:USERNAME"

    return ($content -join "`n")
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

    # detect type end lines from given text
    if ($content.IndexOf("`r`n") -gt 0) {
        $endLinesCurrent = "`r`n"
    } else {
        $endLinesCurrent = "`n"
    }
    
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

    return ($contentLines -join "$endLinesResult")
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
        [string]$templateContent,
        [Parameter(Mandatory)]
        [string]$sectionName,
        [switch]$several = $false,
        [switch]$saveEmptyLines = $false
    )

    [string]$cleanedTemplateContent = $templateContent.Clone()
    [string]$startSectionName = "[start-$sectionName]"
    [string]$endSectionName = "[end-$sectionName]"

    if (-not $saveEmptyLines) {
        $cleanedTemplateContent = RemoveEmptyLines $cleanedTemplateContent
    }

    [System.Collections.ArrayList]$contentSection = New-Object System.Collections.ArrayList

    # start position content between content tags (+1 mean not include in content \n after start tag)
    [int]$startContentIndex = $cleanedTemplateContent.IndexOf("$startSectionName")+"$startSectionName".Length + 1
    # end position content between content tags
    [int]$endContentIndex = $cleanedTemplateContent.IndexOf("$endSectionName")

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
            [int]$startContentIndex = $cleanedTemplateContent.IndexOf("$startSectionName")+"$startSectionName".Length + 1
            # end position content between content tags
            [int]$endContentIndex = $cleanedTemplateContent.IndexOf("$endSectionName")
        } until (
            ($startContentIndex -eq -1) -or ($endContentIndex -eq -1)
        )
    } else {
        [void]$contentSection.Add($cleanedTemplateContent.Substring($startContentIndex, $endContentIndex-$startContentIndex))
    }

    return $contentSection.ToArray()
}


<#
.SYNOPSIS
Function for check if for re-write transferred file need admins privileges

.DESCRIPTION
First, we check the presence of the "read-only" attribute and try to remove this attribute.
If it is cleaned without errors, then admin rights are not needed (or they have already been issued to this script).
If there is no "read-only" attribute, then we check the possibility to change the file.
#>
function Test-ReadOnlyAndWriteAccess {
    [OutputType([bool[]])]
    param (
        [Parameter(Mandatory)]
        [string]$targetPath,
        [Parameter(Mandatory)]
        [bool]$targetIsFile
    )
    
    $fileAttributes = Get-Item -Path "$targetPath" | Select-Object -ExpandProperty Attributes
    [bool]$isReadOnly = $false
    [bool]$needRunAs = $false

    if ($targetIsFile -and ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly)) {
        # if it file check "readonly" attribute
        # folders in Windows have no "readonly" attribute and if target is folder - skip this check
        try {
            Set-ItemProperty -Path "$targetPath" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
            $isReadOnly = $true
            Set-ItemProperty -Path "$targetPath" -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
            $needRunAs = $false
        }
        catch {
            $isReadOnly = $true
            $needRunAs = $true
        }
    } else {
        $isReadOnly = $false

        if ($targetIsFile) {
            # if it file
            # we check permissions for write and open - it mean we can modify file
            try {
                $stream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
                $stream.Close()
                $needRunAs = $false
            } catch {
                $needRunAs = $true
            }
        } else {
            # if it folder
            # we check permissions for delete folder
            try {
                # Here we need to check if we need administrator rights to manipulate the folder
                # The only manipulation of the folder from the text in the template is to delete the folder
                # I have not found a normal way to check if administrator rights are needed to delete a folder
                # I found only an alternative way - to create a file in a folder and delete it.
                #   If this happens without errors, then we do not need administrator rights to create and delete a file inside the folder.
                #   Which means most likely to delete the folder too
                # 
                # But this is a bad way because creating and deleting a file is probably a more time-consuming procedure than checking the rights or attributes of a folder.
                # Also, it does not check the actual right to delete the folder. Folders probably have many different rights and "access levels"
                #   and if we have the ability/right to create + delete a file inside a folder,
                #   then it's not a fact that we have the right to delete a folder (this is just my hypothesis)
                # 
                # TODO: Find a normal way to check if you need administrator rights to delete a folder
                $tempFile = [System.IO.Path]::Combine($targetPath, [System.IO.Path]::GetRandomFileName())
                [void](New-Item -Path $tempFile -ItemType File -Force -ErrorAction Stop)
                Remove-Item -Path $tempFile -Force -ErrorAction Stop

                $needRunAs = $false
            }
            catch {
                $needRunAs = $true
            }
        }
    }

    return $isReadOnly, $needRunAs
}


<#
.DESCRIPTION
Function get path to ps1 file, patch target-file and patterns array etc
and run receive ps1 file and pass given arguments to ran script
#>
function RunPSFile {
    param (
        [Parameter(Mandatory)]
        [string]$psFile,
        [Parameter(Mandatory)]
        [string]$targetFile,
        [Parameter(Mandatory)]
        [string]$patterns
    )

    $patterns = $patterns -replace ',"$',""

    # The only .ps1 file that needs to be run from template is the patcher (main/core file)
    # Previously there was additional code here to run the process as administrator or as usual, depending on different conditions
    # But the logic of restarting on behalf of the administrator has been added to the script patcher.
    # It looks like it makes no sense to repeat the logic of checking startup as an administrator (but this is not accurate),
    #   but if necessary, run others.ps1 files, then you will need to return the logic of the conditions to run as administrator

    $PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}
    $process = Start-Process $PSHost -ArgumentList "-File `"$psFile`" -filePath `"$targetFile`" -patterns", "$patterns" -PassThru -Wait

    if ($process.ExitCode -gt 0) {
        throw "Something happened wrong when patching file $targetFile"
    }
}


<#
.DESCRIPTION
Function gets a text with lines loop all lines
if detect valid path then all next lines concat like patterns until detect other path or end text
then form path to target file and search/replace patterns and send it to function with run patcher script
#>
function DetectFilesAndPatternsAndPatch {
    param (
        [Parameter(Mandatory)]
        [string]$patcherFile,
        [Parameter(Mandatory)]
        [string]$templateContent,
        [Parameter(Mandatory)]
        [System.Collections.Hashtable]$variables
    )

    [string]$cleanedContent = $templateContent.Clone()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    [string]$filePathArg = ''
    [string]$patternsArg = '"'

    [bool]$isSearchPattern = $true

    foreach ($line in $cleanedContent -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()
        if (Test-Path "$line" 2>$null) {
            if ($patternsArg.Length -gt 1) {
                RunPSFile "$patcherFile" "$filePathArg" $patternsArg
                $filePathArg = "$line"
                $patternsArg = '"'
            } else {
                $filePathArg = "$line"
            }
        } else {
            # if it ready search+replace pattern - add it to all patterns string
            # and continue lines loop
            if ($patternSplitters.ForEach("$line".Contains($_))) {
                $patternsArg += "$line`",`""
                continue
            }

            # else it not ready pattern and need
            # concat search then replace patterns on each iteration
            if ($isSearchPattern) {
                $patternsArg += "$line/"
                $isSearchPattern = $false
            } else {
                $patternsArg += "$line`",`""
                $isSearchPattern = $true
            }
        }
    }

    if ($patternsArg.Length -gt 1) {
        if ($filePathArg) {
            RunPSFile "$patcherFile" "$filePathArg" $patternsArg
        } else {
            Write-Error "No valid targets or patterns was found"
            exit 1
        }
    }
}


<#
.SYNOPSIS
Move item (file or folder) to bin
#>
function Move-ToRecycleBin {
    param (
        [Parameter(Mandatory)]
        [string]$targetPath
    )
    
    if (-Not (Test-Path $targetPath)) {
        Write-Error "Not found file for move to bin - $targetPath"
        return
    }
    
    [bool]$isFolder = (Get-Item "$line").PSIsContainer
    $shell = New-Object -ComObject Shell.Application

    $parentFolder = $shell.Namespace((Get-Item $targetPath).DirectoryName)
    if ($isFolder) {
        $parentFolder = $shell.Namespace((Get-Item $targetPath).Parent.FullName)
    }

    $item = $parentFolder.ParseName((Get-Item $targetPath).Name)

    $item.InvokeVerb("delete")
}


<#
.SYNOPSIS
Analyze given text and create new text file with content from text
#>
function CreateFilesFromText {
    param (
        [Parameter(Mandatory)]
        [string]$sectionContent
    )

    [string]$cleanedContent = $sectionContent.Clone().TrimStart()
    [string]$targetPath = ''
    [string]$endLines = ''
    [string]$targetContent = ''
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }
    
    [string[]]$cleanedContentLines = $cleanedContent -split "\n"
    $targetPath = $cleanedContentLines[0].Trim()

    if (Test-Path $targetPath) {
        DeleteFilesOrFolders $targetPath
    }
    
    if ($cleanedContentLines.Count -gt 1) {
        if ($cleanedContentLines[1].Trim() -eq 'CRLF') {
            $endLines = "`r`n"
        } elseif ($cleanedContentLines[1].Trim() -eq 'LF') {
            $endLines = "`n"
        }
    }

    if ("$endLines" -eq '') {
        $endLines = [System.Environment]::NewLine
        $targetContent = ($cleanedContentLines[1..($cleanedContentLines.Length-1)]) -join "$endLines"
    } else {
        $targetContent = ($cleanedContentLines[2..($cleanedContentLines.Length-1)]) -join "$endLines"
    }

    try {
        [void](New-Item -Path "$targetPath" -ItemType File -Force)
        Set-Content -Value $targetContent -Path "$targetPath" -NoNewline -ErrorAction Stop
    }
    catch {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"New-Item -Path `"$targetPath`" -ItemType File -Force;Set-Content -Value `"$contentForAddToHosts`" -Path `"$hostsFilePath`" -NoNewline`""
    }
}


<#
.SYNOPSIS
Get array with text and iterate it and function CreateFilesFromText
#>
function CreateAllFilesFromText {
    param (
        [Parameter(Mandatory)]
        [string[]]$sectionContents
    )
    
    foreach ($content in $sectionContents) {
        CreateFilesFromText $content
    }
}


<#
.SYNOPSIS
Delete items (files and folder) from given lines of string
#>
function DeleteFilesOrFolders {
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    [string]$cleanedContent = $content.Clone().Trim()
    
    [System.Collections.ArrayList]$itemsDeleteWithAdminsPrivileges = New-Object System.Collections.ArrayList
    [System.Collections.ArrayList]$itemsDeleteWithAdminsPrivilegesAndDisableReadOnly = New-Object System.Collections.ArrayList
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }
    
    [string[]]$cleanedContentLines = $cleanedContent -split "\n"
    
    [bool]$needMoveToBin = $false

    if ($cleanedContentLines[0].Trim() -eq "$moveToBinFlag") {
        $needMoveToBin = $true
    }
    
    foreach ($line in $cleanedContentLines) {
        # Trim line is important because end line include \n
        $line = $line.Trim()

        if (-not (Test-Path "$line")) {
            continue
        }

        [bool]$isFile = -not ((Get-Item "$line").PSIsContainer)
        $isReadOnly, $needRunAS = Test-ReadOnlyAndWriteAccess -targetPath "$line" -targetIsFile $isFile
        $fileAttributes = Get-Item -Path "$line" | Select-Object -ExpandProperty Attributes

        if ($isFile) {
            if ((-not $isReadOnly) -and (-not $needRunAS)) {
                if ($needMoveToBin) {
                    Move-ToRecycleBin -targetPath "$line"
                } else {
                    Remove-Item -Path "$line" -Recurse
                }
            }
            if ($isReadOnly -and (-not $needRunAS)) {
                if ($needMoveToBin) {
                    # files with "readonly" attribute can be moved in Bin without problems without remove this attribute
                    Move-ToRecycleBin -targetPath "$line"
                } else {
                    Set-ItemProperty -Path "$line" -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
                    Remove-Item -Path "$line" -Recurse
                }
            }
            if ($needRunAS -and (-not $isReadOnly)) {
                [void]$itemsDeleteWithAdminsPrivileges.Add("$line")
            }
            if ($needRunAS -and $isReadOnly) {
                [void]$itemsDeleteWithAdminsPrivilegesAndDisableReadOnly.Add("$line")
            }
        } else {
            # If it is a folder, it is very difficult to determine in advance whether administrator rights are needed to delete it,
            #   because files and folders with different rights may be attached to it and deleting a folder
            #   with such files will require administrator rights.
            # So the surest way to determine if you need administrator rights to delete a folder is to try deleting the folder
            try {
                Remove-Item -Path "$line" -Recurse -Force -ErrorAction Stop
            }
            catch {
                [void]$itemsDeleteWithAdminsPrivileges.Add("$line")
            }
        }
        
    }

    # For all items requiring administrator rights to delete
    # combine deleting all items in 1 command and run command with admins privileges
    [string]$deleteCommand = ''

    if ($needMoveToBin) {
        [string[]]$allItemsForMoveToBinLikeAdmin = $itemsDeleteWithAdminsPrivileges + $itemsDeleteWithAdminsPrivilegesAndDisableReadOnly
        [string]$allItemsForMoveToBinInString = "`'" + ($allItemsForMoveToBinLikeAdmin -join "','") + "`'"
        # IMPORTANT !!!
        # Do not formate this command and not re-write it
        # it need for add multiline string to Start-Process command
        $deleteCommand = @"
`$shell = New-Object -ComObject Shell.Application
foreach (`$itemForDelete in @($allItemsForMoveToBinInString)) {
    [bool]`$isFolder = (Get-Item `"`$itemForDelete`").PSIsContainer
    `$parentFolder = `$shell.Namespace((Get-Item `"`$itemForDelete`").DirectoryName)
    if (`$isFolder) {
        `$parentFolder = `$shell.Namespace((Get-Item `"`$itemForDelete`").Parent.FullName)
    }
    `$item = `$parentFolder.ParseName((Get-Item `$itemForDelete).Name)
    `$item.InvokeVerb('delete')
}
"@
    } else {
        if ($itemsDeleteWithAdminsPrivileges.Count -gt 0) {
            foreach ($item in $itemsDeleteWithAdminsPrivileges) {
                $deleteCommand += "Remove-Item -Path '$item' -Recurse -Force`n"
            }
        }
    
        if ($itemsDeleteWithAdminsPrivilegesAndDisableReadOnly.Count -gt 0) {
            foreach ($item in $itemsDeleteWithAdminsPrivilegesAndDisableReadOnly) {
                $fileAttributes = Get-Item -Path "$item" | Select-Object -ExpandProperty Attributes
                # IMPORTANT !!!
                # Do not formate this command and not re-write it
                # it need for add multiline string to Start-Process command
                $deleteCommand += @"
Set-ItemProperty -Path '$item' -Name Attributes -Value ('$fileAttributes' -bxor [System.IO.FileAttributes]::ReadOnly)
Remove-Item -Path '$item' -Recurse -Force
"@
            }
        }
    }

    if ($deleteCommand.Length -gt 0) {
        $PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}
        $processId = Start-Process $PSHost -Verb RunAs -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"$deleteCommand`"" -PassThru -Wait
        
        if ($processId.ExitCode -gt 0) {
            throw "Something happened wrong when process remove files or folders with admins privileges"
        }
    }
}


<#
.SYNOPSIS
Return True if last line empty or contain spaces/tabs only
#>
function isLastLineEmptyOrSpaces {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        $content
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
.DESCRIPTION
Handle content from template, if in just URL so add zeroIP before URL,
and make other checks
then formate these lines to string and return formatted string
#>
function CombineLinesForHosts {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$templateContent
    )
    
    [string]$localhostIP = '127.0.0.1'
    [string]$zeroIP = '0.0.0.0'
    
    [string]$contentForAddToHosts = ''

    [string[]]$templateContentLines = $templateContent -split "\n"

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
        foreach ($line in $templateContent -split "\n") {
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
Handle content from template section and add it to hosts file
#>
function AddToHosts {
    param (
        [Parameter(Mandatory)]
        [string]$templateContent
    )

    $needRemoveReadOnly = $false

    [string]$hostsFilePath = [System.Environment]::SystemDirectory + "\drivers\etc\hosts"
    $fileAttributes = Get-Item -Path $hostsFilePath | Select-Object -ExpandProperty Attributes

    [string]$contentForAddToHosts = CombineLinesForHosts $templateContent

    if (Test-Path "$hostsFilePath" 2>$null) {
        # If hosts file exist check if last line hosts file empty
        # and add indents from the last line hosts file to new content
        if (isLastLineEmptyOrSpaces ([System.IO.File]::ReadAllText($hostsFilePath))) {
            $contentForAddToHosts = "`r`n" + $contentForAddToHosts
        } else {
            $contentForAddToHosts = "`r`n`r`n" + $contentForAddToHosts
        }

        # If file have attribute "read only" remove this attribute for made possible patch file
        if ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly) {
            $needRemoveReadOnly = $true
        } else {
            $needRemoveReadOnly = $false
        }

        if (DoWeHaveAdministratorPrivileges) {
            if ($needRemoveReadOnly) {
                Set-ItemProperty -Path $hostsFilePath -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
            }
            Add-Content -Value $contentForAddToHosts -Path $hostsFilePath
            # Return readonly attribute if it was
            if ($needRemoveReadOnly) {
                Set-ItemProperty -Path $hostsFilePath -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
                $needRemoveReadOnly = $false
            }
        } else {
            # IMPORTANT !!!
            # Do not formate this command and not re-write it
            # it need for add multiline string to Start-Process command
            $command = @"
Add-Content -Path $hostsFilePath -Value @'
$contentForAddToHosts 
'@
"@
            if ($needRemoveReadOnly) {
                # If hosts file have attribute "read only" we need remove this attribute before adding lines
                # and restore "default state" (add this attribute to hosts file) after lines to hosts was added
                $command = "Set-ItemProperty -Path '$hostsFilePath' -Name Attributes -Value ('$fileAttributes' -bxor [System.IO.FileAttributes]::ReadOnly)" `
                + "`n" `
                + $command `
                + "`n" `
                + "Set-ItemProperty -Path '$hostsFilePath' -Name Attributes -Value ('$fileAttributes' -bor [System.IO.FileAttributes]::ReadOnly)"
            }
            Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"$command`""
        }
    } else {
        Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"Set-Content -Value `"$contentForAddToHosts`" -Path `"$hostsFilePath`"`""
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
        [string]$templateContent
    )

    $variables = @{}

    foreach ($line in $templateContent -split "\n") {
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
Function get a text with lines and detect valid path to .ps1 file or url
and if first valid line is url - download script from url to temp file
and return path to script file
or throw error if no one valid path or url was detected
#>
function GetPatcherFile {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$templateContent
    )

    foreach ($line in $templateContent -split "\n") {
        # Trim line is important because end line include \n
        $line = $line.Trim()
        if ($line -like "http*") {
            if ((Invoke-WebRequest -UseBasicParsing -Uri $line).StatusCode -eq 200) {
                [string]$tempFile = [System.IO.Path]::GetTempFileName()
                Get-Process | Where-Object {$_.CPU -ge 1} | Out-File $tempFile
                (New-Object System.Net.WebClient).DownloadFile($line,$tempFile)
                $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf("."))+".ps1")
                Rename-Item $tempFile $renamedTempFile
                return $renamedTempFile
            }
        } else {
            if ((Test-Path "$line" -PathType Leaf 2>$null) -and ("$line".EndsWith(".ps1"))) {
                return "$line"
            }
        }
    }
    
    Write-Error "No valid URL for patcher or paths for file-patcher in template"
    exit 1
}

<#
.DESCRIPTION
The path to the template is passed as an argument to this script.
This can be the path to a file on your computer or the URL to the template text.
This function checks for the presence of a file on the computer if it is the path to the file,
    or creates a temporary file and downloads a template from the specified URL into it
#>
function GetTemplateFile {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$templateWay
    )

    if (Test-Path $templateWay 2>$null) {
        return (Get-ChildItem $templateWay).FullName
    } elseif ((Invoke-WebRequest -UseBasicParsing -Uri $templateWay).StatusCode -eq 200) {
        [string]$tempFile = [System.IO.Path]::GetTempFileName()
        Get-Process | Where-Object {$_.CPU -ge 1} | Out-File $tempFile
        (New-Object System.Net.WebClient).DownloadFile($templateWay,$tempFile)
        $renamedTempFile = ($tempFile.Substring(0, $tempFile.LastIndexOf("."))+".txt")
        Rename-Item $tempFile $renamedTempFile
        return (Get-ChildItem $renamedTempFile).FullName
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
    [string]$fullTemplatePath = GetTemplateFile $templatePath
    [string]$cleanedTemplate = CleanTemplate $fullTemplatePath

    # [string]$patcherPathOrUrlContent = ExtractContent $cleanedTemplate "patcher_path_or_url"
    # [string]$variablesContent = ExtractContent $cleanedTemplate "variables"
    # [string]$targetsAndPatternsContent = ExtractContent $cleanedTemplate "targets_and_patterns"
    # [string]$hostsContent = ExtractContent $cleanedTemplate "hosts_add"
    # [string[]]$deleteNeedContent = (ExtractContent $cleanedTemplate "files_or_folders_delete")
    [string[]]$createFilesFromTextContent = ExtractContent $cleanedTemplate "file_create_from_text" -saveEmptyLines -several

    # [string]$patcherFile = GetPatcherFile $patcherPathOrUrlContent
    # [System.Collections.Hashtable]$variables = GetVariables $variablesContent
    # DetectFilesAndPatternsAndPatch $patcherFile $targetsAndPatternsContent $variables
    # AddToHosts $hostsContent
    # DeleteFilesOrFolders $deleteNeedContent[0]
    CreateAllFilesFromText $createFilesFromTextContent


} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$watch.Stop() # stop timer
Write-Host "Script execution time is" $watch.Elapsed # time of execution code