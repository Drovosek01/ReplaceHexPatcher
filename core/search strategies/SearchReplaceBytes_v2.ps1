param (
    [Parameter(Mandatory)]
    [string]$filePath,
    # One pattern is string with search/replace hex like "AABB/1122" or "\xAA\xBB/\x11\x22" or "A A BB CC|1 12 233"
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
Function to convert hex string given byte array
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
            $byteArray.Add([Convert]::ToByte($hexString.Substring($i, 2), 16))
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
    [OutputType([System.Collections.Generic.List[byte[]]])]
    param (
        [Parameter(Mandatory)]
        [string[]]$patternsArray
    )
    
    [System.Collections.Generic.List[byte[]]]$searchBytes = New-Object System.Collections.Generic.List[byte[]]
    [System.Collections.Generic.List[byte[]]]$replaceBytes = New-Object System.Collections.Generic.List[byte[]]

    # Separate pattern-string on search and replace strings
    foreach ($pattern in $patternsArray) {
        # Clean and split string with search and replace hex patterns
        [string[]]$temp = $pattern.Clone().Replace(" ","").Replace("\x","").Replace("\","/").Replace("|","/").ToUpper().Split("/")

        if (-not ($temp.Count -eq 2)) {
            throw "Wrong pattern $pattern and $temp"
        }

        [byte[]]$searchHexPattern = (Convert-HexStringToByteArray -hexString $temp[0])
        [byte[]]$replaceHexPattern = (Convert-HexStringToByteArray -hexString $temp[1])

        [void]($searchBytes.Add($searchHexPattern))
        [void]($replaceBytes.Add($replaceHexPattern))
    }

    return $searchBytes, $replaceBytes
}


<#
.SYNOPSIS
Function to search and replace hex patterns in a binary file

.DESCRIPTION
Loop in given patterns array and search each search-pattern and replace
    all found replace-patterns in given file and re-write file after replace
    patterns if any patterns was found and return indexes found patterns
#>
function SearchAndReplace-HexPatternInBinaryFile {
    [OutputType([int[]])]
    param (
        [Parameter(Mandatory)]
        [string]$targetPath,
        [string[]]$patternsArray
    )
    
    [System.Collections.Generic.List[byte[]]]$searchBytes, [System.Collections.Generic.List[byte[]]]$replaceBytes = Separate-Patterns $patternsArray

    [System.Collections.Generic.List[int]]$foundPatternsIndexes = New-Object System.Collections.Generic.List[int]

    $stream = [System.IO.File]::Open($targetPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
    [int]$bufferSize = [System.UInt16]::MaxValue
    [int]$position = 0;
    [int]$foundPosition = -1;
    [byte[]]$buffer = New-Object byte[] ($bufferSize + $searchBytes[0].Length - 1)
    [int]$bytesRead = 0
    $stream.Position = 0

    # !!!
    # This algorithm ported from https://github.com/jjxtra/HexAndReplace/blob/d6dc05b6eef242149bcbb876a1f923f4311fd08b/BinaryReplacer.cs
    # !!!

    for ($p = 0; $p -lt $patternsArray.Count; $p++) {
        [void]($stream.Seek(0, [System.IO.SeekOrigin]::Begin))
        
        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            for ($i = 0; $i -le $bytesRead - $searchBytes[$p].Length; $i++) {
                for ($j = 0; $j -lt $searchBytes[$p].Length; $j++) {
                    if ($buffer[$i + $j] -ne $searchBytes[$p][$j]) {
                        break
                    } elseif ($j -eq $searchBytes[$p].Length - 1) {
                        [void]($stream.Seek($position + $i, [System.IO.SeekOrigin]::Begin))
                        $stream.Write($replaceBytes[$p], 0, $replaceBytes[$p].Length)

                        if ($foundPosition -eq -1) {
                            [void]($foundPatternsIndexes.Add($p))
                        }

                        break
                    }
                }
            }

            $position += $bytesRead - $searchBytes[$p].Length + 1

            if ($position -gt ($stream.Length - $searchBytes[$p].Length)) {
                break
            }
            
            [void]($stream.Seek($position, [System.IO.SeekOrigin]::Begin))
        }
    }
    
    $stream.Close()

    if ($foundPatternsIndexes.Count -eq 0) {
        # It need for prevent error when pass empty array to function
        $foundPatternsIndexes.Add(-1)
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