param (
    [Parameter(Mandatory)]
    [string]$filePath,
    # One pattern is string with search/replace hex
    # like "AABB/1122" or "\xAA\xBB/\x11\x22" or "A A BB CC|1 12 233" or "?? AA BB CC??FF/112233445566" or "AABB??CC????11/??C3??????????"
    [Parameter(Mandatory)]
    [string[]]$patterns
)

if (-not (Test-Path $filePath)) {
    Write-Error "File not found: $filePath"
    exit 1
}

if ($patterns.Count -eq 0) {
    Write-Error "No patterns given"
    exit 1
}


# =====
# GLOBAL VARIABLES
# =====

[string]$filePathFull = [System.IO.Path]::GetFullPath($filePath)


# =====
# FUNCTIONS
# =====


<#
.SYNOPSIS
Function for convert given hex string to bytes array
#>
function Convert-HexStringToByteArray {
    [OutputType([byte[]])]
    param (
        [string]$hexString
    )

    if ($hexString.Length % 2 -ne 0) {
        throw "Invalid hex string length of $hexString"
    }

    [System.Collections.Generic.List[byte]]$byteArray = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $hexString.Length; $i += 2) {
        try {
            [void]($byteArray.Add([Convert]::ToByte($hexString.Substring($i, 2), 16)))
        }
        catch {
            Write-Error "Looks like we have not hex symbols in $hexString"
            exit 1
        }
    }

    return [byte[]]$byteArray.ToArray()
}


<#
.DESCRIPTION
Function get string that contain hex symbols and wildcards (??) symbols
and return 2 arrays:
Second array is "true" array of bytes (wildcards symbols replaced with '0')
First array is indexes where wildcards will placed in array bytes
#>
function Convert-HexStringToByteArrayWithWildcards {
    [OutputType([array])]
    param (
        [string]$hexString
    )

    if (-not $hexString.Contains('?')) {
        [byte[]]$byteArray = Convert-HexStringToByteArray $hexString

        return @(), $byteArray
    }

    [System.Collections.Generic.List[int]]$wildcardsIndexes = New-Object System.Collections.Generic.List[int]

    [string]$tempHexString = $hexString.Clone()
    [int]$wildcardPosition = $tempHexString.IndexOf('??')

    while ($wildcardPosition -ne -1) {
        if (($wildcardPosition % 2) -eq 0) {
            $wildcardsIndexes.Add($wildcardPosition / 2)
            # replace wildcards symbols to any hex symbol for skip search found index
            $tempHexString = $tempHexString.Remove($wildcardPosition, 2).Insert($wildcardPosition, '00')
            $wildcardPosition = $tempHexString.IndexOf('??')
        } else {
            Write-Error "Looks like $hexString is wrong hex pattern because wildcard (??) is not in an even position"
            exit 1
        }
    }

    [byte[]]$byteArray = Convert-HexStringToByteArray $tempHexString

    return $wildcardsIndexes.ToArray(), $byteArray
}


<#
.DESCRIPTION
A set of patterns can be passed not as an array, but as 1 line
   this usually happens if this script is called on behalf of the administrator from another Powershell script
In this case, this string becomes the first and only element of the pattern array
We need to divide the string into an array of patterns (extract all patterns from 1 string)
#>
function ExtractPatterns {
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string]$patternsString
    )

    return $patternsString.Replace('"',"").Replace("'","").Split(',')
}


<#
.SYNOPSIS
Function for clean hex string and separate search and replace patterns

.DESCRIPTION
The pattern array contains strings. Each string is a set of bytes to search
    and replace in a non-strict format.
Non-strict means that the presence or absence of spaces between byte values
    is allowed, as well as the presence or absence of "\x" characters denoting 16-bit data.
The value separator for search and replace can be one of the characters: \, /, |

Then all this is divided into 2 arrays - an array with search patterns
    and an array with replacement patterns and return both arrays
#>
function Separate-Patterns {
    [OutputType([array])]
    param (
        [Parameter(Mandatory)]
        [string[]]$patternsArray
    )
    
    [System.Collections.Generic.List[byte[]]]$searchBytes = New-Object System.Collections.Generic.List[byte[]]
    [System.Collections.Generic.List[int[]]]$searchWildcardsIndexes = New-Object System.Collections.Generic.List[int[]]
    [System.Collections.Generic.List[byte[]]]$replaceBytes = New-Object System.Collections.Generic.List[byte[]]
    [System.Collections.Generic.List[int[]]]$replaceWildcardsIndexes = New-Object System.Collections.Generic.List[int[]]

    # Separate pattern-string on search and replace strings
    foreach ($pattern in $patternsArray) {
        # Clean and split string with search and replace hex patterns
        [string[]]$temp = $pattern.Clone().Replace(" ","").Replace("\x","").Replace("\","/").Replace("|","/").ToUpper().Split("/")

        if (-not ($temp.Count -eq 2)) {
            throw "Wrong pattern $pattern and $temp"
        }
        
        if ($temp[0].Replace('??', '').Trim().Length -eq 0) {
            throw "Looks like search pattern $pattern[0] contain only wildcards. Specify the bytes that need to be searched for."
        }
        
        if ($temp[1].Replace('??', '').Trim().Length -eq 0) {
            throw "Looks like replace pattern $pattern[1] contain only wildcards. Specify the bytes that need to be searched for."
        }

        [int[]]$searchWildcards, [byte[]]$searchHexPattern = (Convert-HexStringToByteArrayWithWildcards -hexString $temp[0])
        [int[]]$replaceWildcards, [byte[]]$replaceHexPattern = (Convert-HexStringToByteArrayWithWildcards -hexString $temp[1])

        [void]($searchBytes.Add($searchHexPattern))
        if ($searchWildcards.Count -gt 0) {
            [void]($searchWildcardsIndexes.Add($searchWildcards))
        }

        [void]($replaceBytes.Add($replaceHexPattern))
        if ($replaceWildcards.Count -gt 0) {
            [void]($replaceWildcardsIndexes.Add($replaceWildcards))
        }
    }

    return $searchBytes, $searchWildcardsIndexes, $replaceBytes, $replaceWildcardsIndexes
}


<#
.SYNOPSIS
Return index first bytes not matched with index wildcard
#>
function Get-IndexFirstTrueByte {
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[byte]]$hexBytes,
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[int]]$wildcardsIndexes
    )

    if ($wildcardsIndexes.Count -eq 0) {
        return 0
    }

    for ($i = 0; $i -lt $hexBytes.Count; $i++) {
        if ($wildcardsIndexes.Contains($i)) {
            continue
        } else {
            return $i
        }
    }
}


<#
.SYNOPSIS
Function to search and replace hex patterns in a binary file

.DESCRIPTION
Loop in given patterns array and search each search-pattern and replace
    all found replace-patterns in given file
    and return indexes found patterns from given patterns array 
#>
function SearchAndReplace-HexPatternInBinaryFile {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory)]
        [string]$targetPath,
        [Parameter(Mandatory)]
        [string[]]$patternsArray
    )

    [System.Collections.Generic.List[byte[]]]$searchBytes,
    [System.Collections.Generic.List[int[]]]$searchWildcardsIndexes,
    [System.Collections.Generic.List[byte[]]]$replaceBytes,
    [System.Collections.Generic.List[int[]]]$replaceWildcardsIndexes= Separate-Patterns $patternsArray

    $stream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)

    [System.Collections.Generic.List[int]]$foundPatternsIndexes = New-Object System.Collections.Generic.List[int]

    [int]$bufferSize = [System.UInt16]::MaxValue
    $stream.Position = 0
    
    for ($p = 0; $p -lt $patternsArray.Count; $p++) {
        [int]$position = 0
        [int]$bytesRead = 0
        [byte[]]$buffer = New-Object byte[] ($bufferSize + $searchBytes[$p].Length - 1)
        [void]($stream.Seek(0, [System.IO.SeekOrigin]::Begin))
        [int]$searchLength = $searchBytes[$p].Length

        # check if we have wildcards
        if ($searchWildcardsIndexes.GetType().FullName.Contains('System.Collections.Generic.List') -and ($searchWildcardsIndexes.Count -gt 0)) {
            [int]$indexFirstTrueByte = Get-IndexFirstTrueByte -hexBytes $searchBytes[$p] -wildcardsIndexes $searchWildcardsIndexes[$p]
        } else {
            [int]$indexFirstTrueByte = 0
        }

        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [int]$index = 0
            
            while ($index -le ($bytesRead - $searchLength)) {
                [int]$foundIndex = [Array]::IndexOf($buffer, $searchBytes[$p][$indexFirstTrueByte], $index)
                
                if ($foundIndex -eq -1) {
                    break
                }
                
                # start position for paste "replace bytes" if "search bytes" will match
                [int]$fixedFoundIndex = $foundIndex - $indexFirstTrueByte
                
                # If fixedFoundIndex goes beyond the initial file boundary
                # so the found index is not suitable for us - increase loop index and go to next loop iteration
                if (($position -eq 0) -and (($index - [math]::Abs($indexFirstTrueByte)) -lt 0)) {
                    $index++
                    continue
                }
                
                $match = $true
                for ($x = 1; $x -lt $searchLength; $x++) {
                    if ($searchWildcardsIndexes[$p] -and ($searchWildcardsIndexes[$p].Contains($x))) {
                        continue
                    }
                    if ($buffer[$fixedFoundIndex + $x] -ne $searchBytes[$p][$x]) {
                        $match = $false
                        break
                    }
                }
                
                if ($match) {
                    [void]($stream.Seek($position + $fixedFoundIndex, [System.IO.SeekOrigin]::Begin))
                    [System.Collections.Generic.List[byte]]$fixedReplaceBytes = [System.Collections.Generic.List[byte]]::New($replaceBytes[$p])

                    if (($replaceWildcardsIndexes.GetType().FullName.Contains('System.Collections.Generic.List')) -and ($replaceWildcardsIndexes.Count -gt 0)) {
                        for ($rwi = 0; $rwi -lt $replaceWildcardsIndexes[$p].Count; $rwi++) {
                            $tempBytesIndex = $fixedFoundIndex + $replaceWildcardsIndexes[$p][$rwi]
                            $fixedReplaceBytes[$replaceWildcardsIndexes[$p][$rwi]] = $buffer[$tempBytesIndex]
                        }
                    }

                    $stream.Write($fixedReplaceBytes.ToArray(), 0, $replaceBytes[$p].Length)
                    $index = $foundIndex + $searchLength
                    [void]($foundPatternsIndexes.Add($p))
                } else {
                    $index = $foundIndex + 1
                }
            }

            $position += $bytesRead - $searchLength + 1
            if ($position -gt ($stream.Length - $searchLength)) {
                break
            }
            [void]($stream.Seek($position, [System.IO.SeekOrigin]::Begin))
        }
    }

    $stream.Close()


    if ($foundPatternsIndexes.Count -eq 0) {
        # It need for prevent error when pass empty array to function
        [void]($foundPatternsIndexes.Add(-1))
    }

    return [int[]]$foundPatternsIndexes.ToArray()
}


<#
.SYNOPSIS
Show info about found+replaced or not found patterns
#>
function HandleReplacedPatternsIndexes {
    param (
        [Parameter(Mandatory)]
        [string[]]$patternsArray,
        [Parameter(Mandatory)]
        [int[]]$replacedPatternsIndexes
    )
    
    # Each pattern can be found many times
    # in this case pattern index will be added in array indexes many times
    # but we need only unique indexes
    [int[]]$replacedPatternsIndexesCleaned = ($replacedPatternsIndexes | Select-Object -Unique)

    [string]$notFoundPatterns = ''

    if ($replacedPatternsIndexesCleaned.Count -eq 0 -OR ($replacedPatternsIndexesCleaned.Count -eq 1 -AND $replacedPatternsIndexesCleaned[0] -eq -1)) {
        Write-Host "No patterns was found in $filePathFull"
    }
    elseif ($replacedPatternsIndexesCleaned.Count -eq $patternsArray.Count) {
        Write-Host "All hex patterns found and replaced successfully in $filePathFull"
    }
    else {
        [int[]]$notReplacedPatternsIndexes = (0..($patternsArray.Count-1)).Where({$_ -notin $replacedPatternsIndexesCleaned})
        if ($notReplacedPatternsIndexes.Count -gt 0) {
            for ($i = 0; $i -lt $notReplacedPatternsIndexes.Count; $i++) {
                $notFoundPatterns += ' ' + $patternsArray[$notReplacedPatternsIndexes[$i]]
            }
            Write-Host "Hex patterns" $notFoundPatterns.Trim() "- not found, but other given patterns found and replaced successfully in $filePathFull" 
        }
    }
}



# =====
# MAIN
# =====

$watch = [System.Diagnostics.Stopwatch]::StartNew()
$watch.Start() # launch timer

try {
    Write-Host Start searching patterns...

    [string[]]$patternsExtracted = @()
    if ($patterns.Count -eq 1) {
        # Maybe all patterns written in 1 string if first array item and we need handle it
        $patternsExtracted = ExtractPatterns $patterns[0]
    } else {
        $patternsExtracted = $patterns
    }

    $replacedPatternsIndexes = SearchAndReplace-HexPatternInBinaryFile -targetPath $filePathFull -patterns $patternsExtracted

    HandleReplacedPatternsIndexes $patternsExtracted $replacedPatternsIndexes
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$watch.Stop()
Write-Host "Script execution time is" $watch.Elapsed # time of execution code

# Pause before exit like in CMD
Write-Host -NoNewLine "Press any key to continue...`r`n";
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');