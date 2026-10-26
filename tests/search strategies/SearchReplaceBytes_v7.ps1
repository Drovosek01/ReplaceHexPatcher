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
# CSharp Part
# =====

$hexHandler = @"
using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;

namespace HexHandler
{
    /// <summary>
    /// Find/replace binary data in a seekable stream
    /// </summary>
    public sealed class BytesHandler : IDisposable
    {
        private readonly Stream stream;
        private readonly int bufferSize;

        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="stream">Stream</param>
        /// <param name="bufferSize">Buffer size</param>
        public BytesHandler(Stream stream, int bufferSize = ushort.MaxValue)
        {
            if (bufferSize < 2)
                throw new ArgumentOutOfRangeException("bufferSize less than 2 bytes");

            this.stream = stream;
            this.bufferSize = bufferSize;
        }

        private static byte[] ConvertHexStringToByteArray(string hexString)
        {
            string hexStringCleaned = hexString.Replace(" ", string.Empty)
                                                .Replace("\\x", string.Empty)
                                                .Replace("0x", string.Empty)
                                                .Replace(",", string.Empty)
                                                .Normalize()
                                                .Trim();

            if (hexStringCleaned.Length % 2 != 0)
            {
                throw new ArgumentException(string.Format(CultureInfo.InvariantCulture, 
                    "The binary key cannot have an odd number of digits: {0}", hexStringCleaned));
            }

            byte[] data = new byte[hexStringCleaned.Length / 2];
            for (int index = 0; index < data.Length; index++)
            {
                string byteValue = hexStringCleaned.Substring(index * 2, 2);
                data[index] = byte.Parse(byteValue, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            }

            return data;
        }

        /// <summary>
        /// Find and replace all occurrences binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="replacePattern">Replace</param>
        /// <returns>All indexes of replaced data</returns>
        public long[] Replace(byte[] searchPattern, byte[] replacePattern, int amount)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (replacePattern == null)
                throw new ArgumentNullException("replacePattern argument not given");
            if (amount > stream.Length)
                throw new ArgumentException("amount replace occurrences should be less than count bytes in stream");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long[] foundPositions = Find(searchPattern, amount);

            if (foundPositions.Length > 1 && foundPositions[0] != -1)
            {
                for (int i = 0; i < foundPositions.Length; i++)
                {
                    stream.Seek(foundPositions[i], SeekOrigin.Begin);
                    stream.Write(replacePattern, 0, replacePattern.Length);
                }
            }

            stream.Seek(0, SeekOrigin.Begin);
            return foundPositions;
        }

        /// <summary>
        /// Find and replace all occurrences binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="replacePattern">Replace</param>
        /// <returns>All indexes of replaced data</returns>
        public long[] ReplaceAll(byte[] searchPattern, byte[] replacePattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (replacePattern == null)
                throw new ArgumentNullException("replacePattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long[] foundPositions = FindAll(searchPattern);

            if (foundPositions.Length > 1 && foundPositions[0] != -1)
            {
                for (int i = 0; i < foundPositions.Length; i++)
                {
                    stream.Seek(foundPositions[i], SeekOrigin.Begin);
                    stream.Write(replacePattern, 0, replacePattern.Length);
                }
            }

            stream.Seek(0, SeekOrigin.Begin);
            return foundPositions;
        }

        /// <summary>
        /// Find and replace once binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="replacePattern">Replace</param>
        /// <returns>First index of replaced data, or -1 if find is not found</returns>
        public long ReplaceOnce(byte[] searchPattern, byte[] replacePattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (replacePattern == null)
                throw new ArgumentNullException("replacePattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long foundPosition = Find(searchPattern);

            if (foundPosition != -1)
            {
                stream.Seek(foundPosition, SeekOrigin.Begin);
                stream.Write(replacePattern, 0, replacePattern.Length);
            }

            stream.Seek(0, SeekOrigin.Begin);
            return foundPosition;
        }

        /// <summary>
        /// Find byte array in a stream start from given decimal position
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="position">Initial position in stream</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        public long FindFromPosition(byte[] searchPattern, long position = 0)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (position < 0)
                throw new ArgumentNullException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentNullException("position must be within the stream");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long foundPosition = -1;
            byte[] buffer = new byte[bufferSize + searchPattern.Length - 1];
            int bytesRead;
            stream.Position = position;

            while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                int index = 0;

                while (index <= (bytesRead - searchPattern.Length))
                {
                    int foundIndex = Array.IndexOf(buffer, searchPattern[0], index);

                    if (foundIndex == -1 || foundIndex + searchPattern.Length > buffer.Length)
                        break;
                    
                    bool match = true;
                    for (int j = 1; j < searchPattern.Length; j++)
                    {
                        if (buffer[foundIndex + j] != searchPattern[j])
                        {
                            match = false;
                            break;
                        }
                    }

                    if (match)
                    {
                        foundPosition = position + foundIndex;
                        return foundPosition;
                    }
                    else
                    {
                        index = foundIndex + 1;
                    }
                }

                position += bytesRead - searchPattern.Length + 1;
                if (position > stream.Length - searchPattern.Length)
                {
                    break;
                }
                stream.Seek(position, SeekOrigin.Begin);
            }

            return foundPosition;
        }

        /// <summary>
        /// Find byte array in a stream start from given decimal position
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="position">Initial position in stream</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        public long FindFromPosition(string searchPattern, long position = 0)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (position < 0)
                throw new ArgumentNullException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentNullException("position must be within the stream");

            byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
            return FindFromPosition(searchPatternBytes, position);
        }

        /// <summary>
        /// Find byte array from start a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        public long Find(string searchPattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");

            byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
            return FindFromPosition(searchPatternBytes, 0);
        }

        /// <summary>
        /// Find byte array from start a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        public long Find(byte[] searchPattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long result = FindFromPosition(searchPattern, 0);
            return result;
        }

        /// <summary>
        /// Find byte array from start a stream for a set number of times
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>Indexes of found set occurrences or array with -1 or array with less amount indexes if occurrences less than given amount number</returns>
        public long[] Find(string searchPattern, int amount)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (amount > stream.Length)
                throw new ArgumentException("amount replace occurrences should be less than count bytes in stream");
                
            byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);

            List<long> foundPositions = new List<long>();

            return Find(searchPatternBytes, amount);
        }

        /// <summary>
        /// Find byte array from start a stream for a set number of times
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>Indexes of found set occurrences or array with -1 or array with less amount indexes if occurrences less than given amount number</returns>
        public long[] Find(byte[] searchPattern, int amount)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (amount > stream.Length)
                throw new ArgumentException("amount replace occurrences should be less than count bytes in stream");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            List<long> foundPositions = new List<long>();
            long firstFoundPosition = Find(searchPattern);
            foundPositions.Add(firstFoundPosition);

            if (firstFoundPosition > 0 || amount > 1)
            {
                for (int i = 1; i < amount; i++)
                {
                    long nextFoundPosition = FindFromPosition(searchPattern, foundPositions[foundPositions.Count - 1] + 1);

                    if (nextFoundPosition > 0)
                    {
                        foundPositions.Add(nextFoundPosition);
                    }
                    else
                    {
                        break;
                    }
                }
            }

            return foundPositions.ToArray();
        }

        /// <summary>
        /// Find all occurrences of byte array from start a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>Indexes of found all occurrences or array with -1</returns>
        public long[] FindAll(byte[] searchPattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            List<long> foundPositionsList = new List<long>();
            long foundPosition = Find(searchPattern);
            foundPositionsList.Add(foundPosition);

            if (foundPosition > 0)
            {
                while (foundPosition < stream.Length - searchPattern.Length)
                {
                    foundPosition = FindFromPosition(searchPattern, foundPositionsList[foundPositionsList.Count - 1] + 1);

                    if (foundPosition > 0)
                    {
                        foundPositionsList.Add(foundPosition);
                    }
                    else
                    {
                        break;
                    }
                }
            }

            return foundPositionsList.ToArray();
        }

        /// <summary>
        /// Dispose the stream
        /// </summary>
        public void Dispose()
        {
            stream.Dispose();
        }
    }
}


"@

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
    [OutputType([byte[]])]
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

        if (-not ($temp.Count -eq 2) -or $temp[1].Length -eq 0) {
            throw "Search pattern $pattern not have replace pattern"
        }

        [byte[]]$searchHexPattern = (Convert-HexStringToByteArray -hexString $temp[0])
        [byte[]]$replaceHexPattern = (Convert-HexStringToByteArray -hexString $temp[1])

        [void]($searchBytes.Add($searchHexPattern))
        [void]($replaceBytes.Add($replaceHexPattern))
    }

    # Method .ToArray() wrap array in array and we need extract first element for get target converted list
    return $searchBytes.ToArray()[0], $replaceBytes.ToArray()[0]
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

    # if any method from C# code exist - C# already imported in the script and not need compile and import it again
    if (-not ("HexHandler.BytesReplacer" -as [Type])) {
        Add-Type -TypeDefinition $hexHandler -Language CSharp
    }

    $stream = [System.IO.File]::Open($filePathFull, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
    [byte[]]$searchBytes, [byte[]]$replaceBytes = Separate-Patterns $patternsExtracted

    $BytesHandler = [HexHandler.BytesHandler]::new($stream)
    # $positions = $BytesHandler.FindAll($searchBytes)
    $positions = $BytesHandler.ReplaceAll($searchBytes, $replaceBytes)

    if (($positions.Length -gt 0) -and ($positions[0] -gt 0)) {
        # Write-Host "Found occurrences at positions:" ($positions -join ', ')
        Write-Host "Found occurrences at positions:" ($positions.Length)
    } else {
        Write-Host "Given pattern not found in file"
    }

    $stream.Close()
} catch {
    if ($stream.CanWrite) {
        $stream.Close()
    }
    Write-Error "$($_.Exception.Message)"
    exit 1
}

$watch.Stop()
Write-Host "Script execution time is" $watch.Elapsed # time of execution code

# Pause before exit like in CMD
Write-Host -NoNewLine "Press any key to continue...`r`n";
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');