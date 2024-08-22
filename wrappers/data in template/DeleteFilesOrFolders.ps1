param (
    [string]$templateContent,
    [System.Collections.Hashtable]$vars
)


# =====
# GLOBAL VARIABLES
# =====

$PSHost = If ($PSVersionTable.PSVersion.Major -le 5) {'PowerShell'} Else {'PwSh'}

# Text - flags in parse sections
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
    
    [bool]$isFolder = (Get-Item $line).PSIsContainer
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

    if ($cleanedContentLines[0].Trim() -eq $moveToBinFlag) {
        $needMoveToBin = $true
    }
    
    foreach ($line in $cleanedContentLines) {
        # Trim line is important because end line include \n
        $line = $line.Trim()

        if (-not (Test-Path $line)) {
            continue
        }

        [bool]$isFile = -not ((Get-Item $line).PSIsContainer)
        $isReadOnly, $needRunAS = Test-ReadOnlyAndWriteAccess -targetPath $line -targetIsFile $isFile
        $fileAttributes = Get-Item -Path $line | Select-Object -ExpandProperty Attributes

        if ($isFile) {
            if (DoWeHaveAdministratorPrivileges -or (-not $needRunAS)) {
                if (-not $isReadOnly) {
                    if ($needMoveToBin) {
                        Move-ToRecycleBin -targetPath $line
                    } else {
                        Remove-Item -Path $line -Recurse
                    }
                }
                if ($isReadOnly) {
                    if ($needMoveToBin) {
                        # files with "readonly" attribute can be moved in Bin without problems without remove this attribute
                        Move-ToRecycleBin -targetPath $line
                    } else {
                        Set-ItemProperty -Path $line -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
                        Remove-Item -Path $line -Recurse
                    }
                }
            } else {
                if ($needRunAS -and (-not $isReadOnly)) {
                    [void]$itemsDeleteWithAdminsPrivileges.Add($line)
                }
                if ($needRunAS -and $isReadOnly) {
                    [void]$itemsDeleteWithAdminsPrivilegesAndDisableReadOnly.Add($line)
                }
            }
        } else {
            # If it is a folder, it is very difficult to determine in advance whether administrator rights are needed to delete it,
            #   because files and folders with different rights may be attached to it and deleting a folder
            #   with such files will require administrator rights.
            # So the surest way to determine if you need administrator rights to delete a folder is to try deleting the folder
            try {
                Remove-Item -Path $line -Recurse -Force -ErrorAction Stop
            }
            catch {
                [void]$itemsDeleteWithAdminsPrivileges.Add($line)
            }
        }
    }

    # Check if we have items that require admins rights for delete it
    [string[]]$allItemsForDeleteLikeAdmin = $itemsDeleteWithAdminsPrivileges + $itemsDeleteWithAdminsPrivilegesAndDisableReadOnly
    if ($allItemsForDeleteLikeAdmin.Count -eq 0) {
        return
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
                $fileAttributes = Get-Item -Path $item | Select-Object -ExpandProperty Attributes
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
        $processId = Start-Process $PSHost -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"$deleteCommand`"" -PassThru -Wait
        
        if ($processId.ExitCode -gt 0) {
            throw "Something happened wrong when process remove files or folders with admins privileges"
        }
    }
}


# =====
# MAIN
# =====

try {
    if ($templateContent -and $vars) {
        $variables = $vars
        DeleteFilesOrFolders -content $templateContent
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}