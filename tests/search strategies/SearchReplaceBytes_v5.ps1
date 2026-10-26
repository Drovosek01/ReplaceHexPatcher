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
using System.Collections.Generic;

namespace HexHandler
{
    /// <summary>
    /// Find/replace binary data in a seekable stream
    /// </summary>
    public sealed class BytesReplacer : IDisposable
    {
        private readonly Stream stream;
        private readonly int bufferSize;

        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="stream">Stream</param>
        /// <param name="bufferSize">Buffer size</param>
        public BytesReplacer(Stream stream, int bufferSize = ushort.MaxValue)
        {
            if (bufferSize < 2)
                throw new ArgumentOutOfRangeException("bufferSize less than 2 bytes");

            this.stream = stream;
            this.bufferSize = bufferSize;
        }

        /// <summary>
        /// Find and replace all occurrences binary data in a stream
        /// </summary>
        /// <param name="find">Find</param>
        /// <param name="replace">Replace</param>
        /// <returns>All indexes of replaced data</returns>
        /// <exception cref="ArgumentException">Find and replace are not the same length</exception>
        public long[] Replace(byte[] find, byte[] replace, int amount)
        {
            if (amount < 1)
                throw new ArgumentNullException("amount argument must be more than 0");
            if (find == null)
                throw new ArgumentNullException("find argument not given");
            if (replace == null)
                throw new ArgumentNullException("replace argument not given");
            if (find.Length != replace.Length)
                throw new ArgumentException("Find and replace hex must be same length");
            if (find.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", find.Length, bufferSize));

            long position = 0;
            List<long> foundPositions = new List<long>();
            byte[] buffer = new byte[bufferSize + find.Length - 1];
            int bytesRead;
            stream.Position = 0;

            while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                for (int i = 0; i <= bytesRead - find.Length; i++)
                {
                    bool match = true;
                    for (int j = 0; j < find.Length; j++)
                    {
                        if (buffer[i + j] != find[j])
                        {
                            match = false;
                            break;
                        }
                    }

                    if (match)
                    {
                        stream.Seek(position + i, SeekOrigin.Begin);
                        stream.Write(replace, 0, replace.Length);

                        if (foundPositions.Count < amount)
                        {
                            foundPositions.Add(position + i);
                        } else {
                            Dispose();
                            return foundPositions.ToArray();
                        }
                    }
                }

                position += bytesRead - find.Length + 1;
                if (position > stream.Length - find.Length)
                {
                    break;
                }
                stream.Seek(position, SeekOrigin.Begin);
            }

            Dispose();
            return foundPositions.ToArray();
        }

        /// <summary>
        /// Find and replace all occurrences binary data in a stream
        /// </summary>
        /// <param name="find">Find</param>
        /// <param name="replace">Replace</param>
        /// <returns>All indexes of replaced data</returns>
        /// <exception cref="ArgumentException">Find and replace are not the same length</exception>
        public long[] ReplaceAll(byte[] find, byte[] replace)
        {
            if (find == null)
                throw new ArgumentNullException("find argument not given");
            if (replace == null)
                throw new ArgumentNullException("replace argument not given");
            if (find.Length != replace.Length)
                throw new ArgumentException("Find and replace hex must be same length");
            if (find.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", find.Length, bufferSize));

            long position = 0;
            List<long> foundPositions = new List<long>();
            byte[] buffer = new byte[bufferSize + find.Length - 1];
            int bytesRead;
            stream.Position = 0;

            while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                for (int i = 0; i <= bytesRead - find.Length; i++)
                {
                    bool match = true;
                    for (int j = 0; j < find.Length; j++)
                    {
                        if (buffer[i + j] != find[j])
                        {
                            match = false;
                            break;
                        }
                    }

                    if (match)
                    {
                        stream.Seek(position + i, SeekOrigin.Begin);
                        stream.Write(replace, 0, replace.Length);
                        foundPositions.Add(position + i);
                    }
                }

                position += bytesRead - find.Length + 1;
                if (position > stream.Length - find.Length)
                {
                    break;
                }
                stream.Seek(position, SeekOrigin.Begin);
            }

            Dispose();
            return foundPositions.ToArray();
        }

        /// <summary>
        /// Find and replace once binary data in a stream
        /// </summary>
        /// <param name="find">Find</param>
        /// <param name="replace">Replace</param>
        /// <returns>First index of replaced data, or -1 if find is not found</returns>
        /// <exception cref="ArgumentException">Find and replace are not the same length</exception>
        public long ReplaceOnce(byte[] find, byte[] replace)
        {
            if (find == null)
                throw new ArgumentNullException("find argument not given");
            if (replace == null)
                throw new ArgumentNullException("replace argument not given");
            if (find.Length != replace.Length)
                throw new ArgumentException("Find and replace hex must be same length");
            if (find.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", find.Length, bufferSize));

            long position = 0;
            long foundPosition = -1;
            byte[] buffer = new byte[bufferSize + find.Length - 1];
            int bytesRead;
            stream.Position = 0;

            while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                for (int i = 0; i <= bytesRead - find.Length; i++)
                {
                    bool match = true;
                    for (int j = 0; j < find.Length; j++)
                    {
                        if (buffer[i + j] != find[j])
                        {
                            match = false;
                            break;
                        }
                    }

                    if (match)
                    {
                        stream.Seek(position + i, SeekOrigin.Begin);
                        stream.Write(replace, 0, replace.Length);
                        if (foundPosition == -1)
                        {
                            foundPosition = position + i;
                            Dispose();
                            return foundPosition;
                        }
                    }
                }

                position += bytesRead - find.Length + 1;
                if (position > stream.Length - find.Length)
                {
                    break;
                }
                stream.Seek(position, SeekOrigin.Begin);
            }

            Dispose();
            return foundPosition;
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

    $BytesReplacer = [HexHandler.BytesReplacer]::new($stream)
    $positions = $BytesReplacer.ReplaceAll($searchBytes, $replaceBytes)

    if (($positions.Length -gt 0) -and ($positions[0] -gt 0)) {
        Write-Host "Found occurrences at positions:" ($positions -join ', ')
    } else {
        Write-Host "Given pattern not found in file"
    }
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