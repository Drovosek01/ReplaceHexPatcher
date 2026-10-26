
# paths/files/targets for patches
[System.Collections.Generic.List[string]]$paths = New-Object System.Collections.Generic.List[string]
# list flags mean file from list $paths exist on disk
[System.Collections.Generic.List[bool]]$paths_exist_mask = New-Object System.Collections.Generic.List[bool]
# arrays search patterns for each path/file
[System.Collections.Generic.List[string[]]]$searchPatterns = New-Object System.Collections.Generic.List[string[]]
# arrays replace patterns for each path/file
[System.Collections.Generic.List[string[]]]$replacePatterns = New-Object System.Collections.Generic.List[string[]]
# arrays of number found matches for each search pattern for each path/file
[System.Collections.Generic.List[int[]]]$foundMatches_allPaths = New-Object System.Collections.Generic.List[int[]]



function ClearStorageArrays {
    $paths.Clear()
    $searchPatterns.Clear()
    $replacePatterns.Clear()
    $foundMatches_allPaths.Clear()
}


<#
.DESCRIPTION
The function checks if there are characters in the pattern (search string) that in regexp can indicate line breaks or pattern search on multiple lines.

This is necessary to optimize the search.

If regexp does not have search characters on multiple lines, then the text file can be iterated line by line, rather than loading the entire contents of the file into memory.
#>
function Test-MultilineRegex {
    [OutputType([bool])]
    param (
        [string]$searchText
    )

    [string[]]$symbolsFlags = @("\n", "\r", ".")
    
    for ($i = 0; $i -lt $symbolsFlags.Count; $i++) {
        if ($searchText.Contains($symbolsFlags[$i])) {
            return $true
        }
    }

    return $false
}


<#
.SYNOPSIS
Find texts in given file with some options

.NOTES
The search is done in a smart way.
If it is a regexp that searches in multiple lines, then the text file will be read in full.
Otherwise, the file will be read line by line.

.OUTPUTS
Number of matches found for each text
#>
function Find-TextsInFile {
    [OutputType([int[]])]
    param (
        [string]$FilePath,
        [string[]]$SearchTexts,
        [bool]$isRegex = $false,
        [bool]$CaseSensitive = $true
    )
    
    [System.Collections.Generic.List[int]]$matchCounts = New-Object System.Collections.Generic.List[int]

    if ($isRegex) {
        $options = [System.Text.RegularExpressions.RegexOptions]::None
        if (-not $CaseSensitive) {
            $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        }
        
        for ($i = 0; $i -lt $SearchTexts.Count; $i++) {
            $regex = [System.Text.RegularExpressions.Regex]::new($SearchTexts[$i], $options)
            [int]$matchCount = 0
            [bool]$isRegexCanMultiline = Test-MultilineRegex $SearchTexts[$i]

            if ($isRegexCanMultiline) {
                $content = [System.IO.File]::ReadAllText($FilePath)
                $matchCounts.Add(($regex.Matches($content)).Count)
            }
            else {
                Get-Content -Path $FilePath | ForEach-Object {
                    $lineMatches = $regex.Matches($_)
                    $matchCount += $lineMatches.Count
                }

                $matchCounts.Add($matchCount)
            }
        }
    }
    else {
        [int]$matchCount = 0
        
        if ($CaseSensitive) {
            for ($i = 0; $i -lt $SearchTexts.Count; $i++) {
                Get-Content -Path $FilePath -Encoding UTF8 | ForEach-Object {
                    $line = $_
                    $index = 0
                    while (($index = $line.IndexOf($SearchTexts[$i], $index)) -ne -1) {
                        $matchCount++
                        $index += $SearchTexts[$i].Length
                    }
                }
                $matchCounts.Add($matchCount)
                $matchCount = 0
            }
        }
        else {
            for ($i = 0; $i -lt $SearchTexts.Count; $i++) {
                $escapedText = [Regex]::Escape($SearchTexts[$i])
                $pattern = if ($CaseSensitive) { $escapedText } else { "(?i)$escapedText" }

                $matchesPattern = Select-String -Path $FilePath -Pattern $pattern -AllMatches
                $totalMatches = 0
                foreach ($match in $matchesPattern.Matches) {
                    $totalMatches += $match.Count
                }
                $matchCounts.Add($totalMatches)
            }
        }
    }

    return $matchCounts.ToArray()
}


<#
.DESCRIPTION
Function search array strings and replace each search string with replace string
for given text

.OUTPUTS
Text with replaced strings
#>
function ReplaceTexts {
    [OutputType([string])]
    param (
        [string]$content,
        [string[]]$SearchTexts,
        [string[]]$ReplaceTexts,
        [bool]$isRegex = $false,
        [bool]$CaseSensitive = $true
    )

    if ($isRegex) {
        $options = [System.Text.RegularExpressions.RegexOptions]::None
        if (-not $CaseSensitive) {
            $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        }

        for ($i = 0; $i -lt $SearchTexts.Count; $i++) {
            $regex = [System.Text.RegularExpressions.Regex]::new($SearchTexts[$i], $options)

            $content = $content -replace $regex, $ReplaceTexts[$i]
        }
    }
    else {
        if ($CaseSensitive) {
            for ($i = 0; $i -lt $SearchTexts.Count; $i++) {
                $content = $content.Replace($SearchTexts[$i], $ReplaceTexts[$i])
            }
        }
        else {
            for ($i = 0; $i -lt $SearchTexts.Count; $i++) {
                $escapedText = [Regex]::Escape($SearchTexts[$i])

                $pattern = if ($CaseSensitive) { $escapedText } else { "(?i)$escapedText" }
                
                $content = $content -replace $pattern, $ReplaceTexts[$i]
            }
        }
    }
    
    return $content
}


function Test-AllZero {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [int[]]$array
    )

    for ($i = 0; $i -lt $array.Count; $i++) {
        if ($array[$i] -ne 0) { return $false }
    }

    return $true
}


<#
.DESCRIPTION
Function search array strings and replace each search string with replace string
for given file path

.OUTPUTS
Amount of found string for each search string
#>
function ReplaceTextsInFile {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string[]]$SearchTexts,
        [Parameter(Mandatory)]
        [string[]]$ReplaceTexts,
        [bool]$isRegex = $false,
        [bool]$CaseSensitive = $true
    )

    try {
        $content = [System.IO.File]::ReadAllText($FilePath)
    }
    catch {
        throw "Unknown problem when read file: $FilePath`nMaybe need admins permissions for read it"
    }
    
    [int[]]$occurrences = Find-TextsInFile -FilePath $FilePath -SearchTexts $SearchTexts -isRegex $isRegex -CaseSensitive $CaseSensitive

    # if no text was found - no need modify file
    if (Test-AllZero $occurrences) {
        return $occurrences
    }
    
    [string]$newContent = ReplaceTexts -content $content -SearchTexts $SearchTexts -ReplaceTexts $ReplaceTexts -isRegex $isRegex -CaseSensitive $CaseSensitive
    
    try {
        $newContent | Set-Content -Path $FilePath -NoNewline
    }
    catch {
        throw "Unknown problem when modify file: $FilePath`nMaybe it have option ReadOnly or need admins permissions for modify it"
    }

    return $occurrences
}


<#
.DESCRIPTION
Function analyze given text and extract from the text paths
and pairs search + replace text-patterns for each path
and add paths, search patterns and replace patterns in separated lists
#>
function ExtractPathsAndPatterns {
    param (
        [Parameter(Mandatory)]
        [string]$content
    )

    [string]$cleanedContent = $content.Clone().Trim()
    
    # replace variables with variables values in all current content
    foreach ($key in $variables.Keys) {
        $cleanedContent = $cleanedContent.Replace($key, $variables[$key])
    }

    [System.Collections.Generic.List[string]]$searchPatternsLocal = New-Object System.Collections.Generic.List[string]
    [System.Collections.Generic.List[string]]$replacePatternsLocal = New-Object System.Collections.Generic.List[string]
    [bool]$searchPatternFound = $false

    foreach ($line in $cleanedContent -split "\n") {
        # Trim line is important because end line include \n
        $line = [Environment]::ExpandEnvironmentVariables($line.Trim())

        if ((Test-Path $line 2>$null) -or (Test-Path -LiteralPath $line 2>$null)) {
            $paths.Add($line)
            $paths_exist_mask.Add($true)
            
            if ($searchPatternsLocal.Count -gt 0) {
                $searchPatterns.Add($searchPatternsLocal.ToArray())
                $searchPatternsLocal.Clear()
                $replacePatterns.Add($replacePatternsLocal.ToArray())
                $replacePatternsLocal.Clear()
            }
        }
        elseif (DoesItLooksLikeFSPath $line) {
            $paths.Add($line)
            $paths_exist_mask.Add($true)
            
            if ($searchPatternsLocal.Count -gt 0) {
                $searchPatterns.Add($searchPatternsLocal.ToArray())
                $searchPatternsLocal.Clear()
                $replacePatterns.Add($replacePatternsLocal.ToArray())
                $replacePatternsLocal.Clear()
            }
        }
        else {
            if ($searchPatternFound) {
                $replacePatternsLocal.Add($line)
                $searchPatternFound = $false
            }
            else {
                $searchPatternsLocal.Add($line)
                $searchPatternFound = $true
            }
        }
    }

    if ($searchPatternsLocal.Count -gt 0) {
        $searchPatterns.Add($searchPatternsLocal.ToArray())
        $searchPatternsLocal.Clear()
        $replacePatterns.Add($replacePatternsLocal.ToArray())
        $replacePatternsLocal.Clear()
    }
}


<#
.SYNOPSIS
Find texts in given files with some options

.OUTPUTS
Number of matches found for each file
#>
function Find-TextsInFiles {
    [OutputType([int[][]])]
    param (
        [string[]]$FilePaths,
        [string[]]$SearchTexts,
        [bool]$isRegex = $false,
        [bool]$CaseSensitive = $true
    )
    
    [System.Collections.Generic.List[int[]]]$matchCounts = New-Object System.Collections.Generic.List[int[]]

    for ($i = 0; $i -lt $FilePaths.Count; $i++) {
        [int[]]$matchCount = Find-TextsInFile -FilePath $FilePaths[$i] -SearchText $SearchTexts[$i] -isRegex $isRegex -CaseSensitive $CaseSensitive
        $matchCounts.Add($matchCount)
    }

    return $matchCounts.ToArray()
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
        [string]$targetPath
    )
    
    $fileAttributes = Get-Item -Path $targetPath -Force | Select-Object -ExpandProperty Attributes
    [bool]$isReadOnly = $false
    [bool]$needRunAs = $false

    if ($fileAttributes -band [System.IO.FileAttributes]::ReadOnly) {
        try {
            Set-ItemProperty -Path $targetPath -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
            $isReadOnly = $true
            Set-ItemProperty -Path $targetPath -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
            $needRunAs = $false
        }
        catch {
            $isReadOnly = $true
            $needRunAs = $true
        }
    }
    else {
        $isReadOnly = $false
        
        try {
            $stream = [System.IO.File]::Open(($targetPath -ireplace "``", ""), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write)
            $stream.Close()
            $needRunAs = $false
        }
        catch {
            $needRunAs = $true
        }
    }

    return $isReadOnly, $needRunAs
}


function ApplyTextPatternsInTextFile {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory)]
        [string]$targetPath,
        [Parameter(Mandatory)]
        [string[]]$SearchTexts,
        [Parameter(Mandatory)]
        [string[]]$ReplaceTexts,
        [Parameter(Mandatory)]
        [bool]$needMakeBackup,
        [bool]$isSearchOnly = $false,
        [bool]$isRegex = $false,
        [bool]$CaseSensitive = $true
    )

    [string]$backupAbsoluteName = "$targetPath.bak"
    [string]$backupTempAbsoluteName = $(New-TemporaryFile).FullName

    $isReadOnly, $needRunAS = Test-ReadOnlyAndWriteAccess $targetPath

    $fileAttributes = Get-Item -Path $targetPath -Force | Select-Object -ExpandProperty Attributes
    $fileAcl = Get-Acl $targetPath

    if ($needRunAS -and !(DoWeHaveAdministratorPrivileges)) {
        # add permissions for current user for FullControl file
        $command = @"
`$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
`$acl = Get-Acl '$targetPath'
`$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    `$currentUser,
    'FullControl',
    'Allow'
)
`$acl.AddAccessRule(`$accessRule)
Set-Acl -Path '$targetPath' -AclObject `$acl
"@

        $processId = Start-Process $PSHost -Verb RunAs -PassThru -Wait -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -Command `"$command`""

        if ($processId.ExitCode -gt 0) {
            throw "Something happened wrong when try add permissions for current user for FullControl file - $targetPath"
        }
        break
    }

    try {
        if ($isReadOnly) {
            Set-ItemProperty -Path $targetPath -Name Attributes -Value ($fileAttributes -bxor [System.IO.FileAttributes]::ReadOnly)
        }
    
        if ($needMakeBackup) {
            # Make temp backup file
            Copy-Item -Path $targetPath -Destination $backupTempAbsoluteName -Force
        }

        if ($isSearchOnly) {
            [int[]]$matchesNumber = Find-TextsInFile -FilePath $targetPath -SearchTexts $SearchTexts -isRegex $isRegex -CaseSensitive $CaseSensitive
        }
        else {
            [int[]]$matchesNumber = ReplaceTextsInFile -FilePath $targetPath -SearchTexts $SearchTexts -ReplaceTexts $ReplaceTexts -isRegex $isRegex -CaseSensitive $CaseSensitive
        }
    }
    catch {
        Remove-Item -Path $backupTempAbsoluteName -Force 2>$null
        Remove-Item -Path $backupAbsoluteName -Force 2>$null

        throw "$($_.Exception.Message)"
    }
    finally {
        if ($needRunAS -and !(DoWeHaveAdministratorPrivileges)) {
            # restore file permissions
            $fileAcl | Set-Acl $targetPath
        }

        # restore attribute "Read Only" if it was
        if ($isReadOnly) {
            Set-ItemProperty -Path $targetPath -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
        }
    }


    # if target file patched we need rename temp backuped file to "true" backuped file
    # and restore attributes and permissions

    if ($needMakeBackup) {
        if (Test-Path $backupTempAbsoluteName) {
            try {
                Move-Item -Path $backupTempAbsoluteName -Destination $backupAbsoluteName -Force -ErrorAction Stop
            }
            catch {
        # add permissions for current user for FullControl file
        $command = @"
Move-Item -Path '$backupTempAbsoluteName' -Destination '$backupAbsoluteName' -Force
"@

                $processId = Start-Process $PSHost -Verb RunAs -PassThru -Wait -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -Command `"$command`""

                if ($processId.ExitCode -gt 0) {
                    throw "Something happened wrong when try set backup file: $backupAbsoluteName"
                }
            }
        }

        # restore attribute "Read Only" if it was on original file
        if ($isReadOnly) {
            Set-ItemProperty -Path $backupAbsoluteName -Name Attributes -Value ($fileAttributes -bor [System.IO.FileAttributes]::ReadOnly)
        }

        if ($needRunAS -and !(DoWeHaveAdministratorPrivileges)) {
            # restore file permissions
            $fileAcl | Set-Acl $backupAbsoluteName
        }
    }

    return $matchesNumber
}



function DetectFilesAndPatternsAndPatchText {
    param (
        [Parameter(Mandatory)]
        [string]$content,
        [System.Collections.Generic.HashSet[string]]$flags
    )

    [bool]$checkOccurrencesOnly = $false
    [bool]$needMakeBackup = $false
    [bool]$isRegex = $false
    [bool]$isCaseSensitive = $true

    if ($flags.Contains($MAKE_BACKUPS_flag_text)) {
        $needMakeBackup = $true
    }

    if ($flags.Contains($CAN_USE_REGEXP_IN_PATCH_TEXT_flag_text)) {
        $isRegex = $true
    }

    if ($flags.Contains($PATCH_TEXT_IS_CASEINSENSITIVE_flag_text)) {
        $isCaseSensitive = $false
    }

    if ($flags.Contains($CHECK_OCCURRENCES_ONLY_flag_text)) {
        $checkOccurrencesOnly = $true
    }

    ExtractPathsAndPatterns -content $content

    if ($paths.Count -eq 0) {
        Write-ProblemMsg "None of the file paths specified for the text patches were found"
        return
    }

    if ($flags.Contains($EXIT_IF_ANY_PATCH_TEXT_FILE_NOT_EXIST_flag_text)) {
        if ($paths_exist_mask.ToArray() -contains $false) {
            Write-ProblemMsg "Not all files from section patch_text exists!"
            Write-ProblemMsg "With current template need that all target files exist"
            Write-ProblemMsg "Check for files and run the template again"
            exit 1
        }
    }

    if ($flags.Contains($CHECK_ALREADY_PATCHED_ONLY_flag_text)) {
        $checkOccurrencesOnly = $true
        $searchPatterns = $replacePatterns
    }

    for ($i = 0; $i -lt $paths.Count; $i++) {
        # if the file is not exist on the disk, then we do not apply patterns to it
        if (-not $paths_exist_mask[$i]) {
            $foundMatches_allPaths.Add(@(0))
            continue
        }
        [int[]]$matchesNumber = ApplyTextPatternsInTextFile -targetPath $paths[$i] -SearchTexts $searchPatterns[$i] -ReplaceTexts $replacePatterns[$i] -needMakeBackup $([bool]!$checkOccurrencesOnly -and $needMakeBackup) -isRegex $isRegex -CaseSensitive $isCaseSensitive -isSearchOnly $checkOccurrencesOnly
        
        $foundMatches_allPaths.Add($matchesNumber)
    }

    if ($foundMatches_allPaths.ToArray().Count -ne 0) {
        Show-TextPatchInfo -searchPatternsLocal $searchPatterns.ToArray() -foundMatches $foundMatches_allPaths.ToArray() -isSearchOnly $checkOccurrencesOnly
    }
    else {
        Write-ProblemMsg "No files were found on the disk:"
        
        for ($i = 0; $i -lt $paths.Count; $i++) {
            if (-not $paths_exist_mask[$i]) {
                Write-Msg ($paths[$i])
            }
        }
    }

    ClearStorageArrays
}


<#
.SYNOPSIS
Function check if all array items is 0
#>
function Test-AllZero_allPaths {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [int[][]]$array
    )

    for ($i = 0; $i -lt $array.Count; $i++) {
        for ($x = 0; $x -lt $array[$i].Count; $x++) {
            if ($array[$i][$x] -ne 0) { return $false }
        }
    }

    return $true
}


<#
.SYNOPSIS
Function check if all array items is non-0
#>
function Test-AllNonZero_allPaths {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [int[][]]$arrayFoundOccurrences
    )

    for ($i = 0; $i -lt $arrayFoundOccurrences.Count; $i++) {
        for ($x = 0; $x -lt $arrayFoundOccurrences[$i].Count; $x++) {
            if ($arrayFoundOccurrences[$i][$x] -eq 0) { return $false }
        }
    }

    return $true
}


<#
.DESCRIPTION
Function calculate sum of occurrences all patterns positions
#>
function Get-OccurrencesSum {
    [OutputType([int[][]])]
    param(
        [Parameter(Mandatory)]
        [int[][]]$occurrences
    )
    
    [int]$sum = 0

    foreach ($row in $occurrences) {
        foreach ($element in $row) {
            if ($element -gt 0) {
                $sum += $element
            }
        }
    }

    return $sum
}

function Show-TextPatchInfo {
    param (
        [Parameter(Mandatory)]
        [string[][]]$searchPatternsLocal,
        [Parameter(Mandatory)]
        [int[][]]$foundMatches,
        [bool]$isSearchOnly = $false
    )

    if (-not $flagsAll.Contains($VERBOSE_flag_text)) {
        return
    }
    
    [bool]$isAllPathsExist = ($paths_exist_mask.ToArray() -notcontains $false)
    [bool]$isAllPathsNotExist = ($paths_exist_mask.ToArray() -notcontains $true)

    [bool]$isAllPatternsNotFound = Test-AllZero_allPaths $foundMatches
    [bool]$isAllPatternsFound = Test-AllNonZero_allPaths $foundMatches
        
    [int]$occurrencesSum = Get-OccurrencesSum $foundMatches
    
    if ($isAllPathsNotExist) {
        Write-ProblemMsg "No files were found!"
        Write-Msg
        Write-Msg "Here is a list of the files we are looking for:"
        
        for ($i = 0; $i -lt $paths.Count; $i++) {
            if (-not $paths_exist_mask[$i]) {
                Write-Msg ($paths[$i])
            }
        }
        Write-Msg
        return
    } elseif (-not $isAllPathsExist) {
        Write-Msg
        Write-WarnMsg "These files not exist on disk (not found):"
        
        for ($i = 0; $i -lt $paths.Count; $i++) {
            if (-not $paths_exist_mask[$i]) {
                Write-Msg ($paths[$i])
            }
        }
        Write-Msg
    }

    if ($isAllPatternsNotFound) {
        Write-ProblemMsg "No text-patterns was found!"
        Write-Msg
        Write-Msg "In files:"
        
        for ($i = 0; $i -lt $paths.Count; $i++) {
            # if the file is not exist on the disk, then we do not applied patterns to it
            if (-not $paths_exist_mask[$i]) {
                continue
            }
            Write-Msg $paths[$i]
        }
    }
    else {
        if ($isAllPatternsFound -and $isAllPathsExist) {
            if ($isSearchOnly) {
                Write-Msg "All text-patterns found!"
            }
            else {
                Write-Msg "All text-patterns found and replaced!"
            }
        }
        else {
            if ($isSearchOnly) {
                Write-WarnMsg "Not all text-patterns was found!"
            }
            else {
                Write-WarnMsg "Not all text-patterns was found! Only the found patterns were replaced."
            }
        }
        Write-Msg

        for ($i = 0; $i -lt $paths.Count; $i++) {
            # if the file is not exist on the disk, then we do not applied patterns to it
            if (-not $paths_exist_mask[$i]) {
                continue
            }
            Write-Msg $paths[$i]

            for ($x = 0; $x -lt $searchPatternsLocal[$i].Count; $x++) {
                Write-Msg "$($searchPatternsLocal[$i][$x].Trim()) | $($foundMatches[$i][$x])"
            }

            Write-Msg
        }
    }
    
    Write-Msg "The total number of occurrences of all patterns: $occurrencesSum"
}