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
        private const string wildcard = "??";
        private const string wildcardInRegExp = "[\\x00-\\xFF]";

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
            try
            {
                for (int index = 0; index < data.Length; index++)
                {
                    string byteValue = hexStringCleaned.Substring(index * 2, 2);
                    data[index] = byte.Parse(byteValue, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                }
            }
            catch (FormatException)
            {
                throw new FormatException("Hex string " + hexString + " or it cleaned version " + hexStringCleaned + " contain not HEX symbols and cannot be converted to bytes array");
            }

            return data;
        }

        /// <summary>
        /// Convert string with any type of hex symbols or wildcards to byte array and wildcards mask array
        /// </summary>
        /// <param name="hexString">hexString with wildcards</param>
        /// <param name="wildcardExample">example of wildcard symbol what will match like 1 byte</param>
        /// <returns>Tuple with byte array and array of wildcards mask. true in mask array mean that symbol on same index in byte array is wildcard.</returns>
        private static Tuple<byte[], bool[]> ConvertHexStringWithWildcardsToByteArrayAndMask(string hexString, string wildcardExample = wildcard)
        {
            string hexStringCleaned = hexString.Replace(" ", string.Empty)
                                                .Replace(wildcardInRegExp, wildcardExample)
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
            bool[] mask = new bool[data.Length];

            try
            {
                for (int index = 0; index < data.Length; index++)
                {
                    string byteValue = hexStringCleaned.Substring(index * 2, 2);
                    if (byteValue == wildcardExample)
                    {
                        data[index] = byte.Parse("00", NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                        mask[index] = true;
                    }
                    else
                    {
                        data[index] = byte.Parse(byteValue, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                        mask[index] = false;
                    }
                }
            }
            catch (FormatException)
            {
                throw new FormatException("Hex string " + hexString + " or it cleaned version " + hexStringCleaned + " contain not HEX symbols and cannot be converted to bytes array");
            }

            return Tuple.Create(data, mask);
        }

        private bool testHexStringContainWildcards(string hexString, string wildcardExample = wildcard)
        {
            string hexStringCleaned = hexString.Replace(" ", string.Empty)
                                                .Replace(wildcardInRegExp, wildcardExample);

            return hexStringCleaned.IndexOf(wildcardExample) != -1 || hexStringCleaned.IndexOf(wildcardInRegExp) != -1;
        }

        /// <summary>
        /// Find and insert (with overwrite) the specified number of times occurrences binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="insertPattern">Insert with overwrite</param>
        /// <returns>All indexes of overwritten data</returns>
        public long[] OverwriteBytesAtPatternPositions(byte[] searchPattern, byte[] insertPattern, int amount)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (insertPattern == null)
                throw new ArgumentNullException("insertPattern argument not given");
            if (amount > stream.Length)
                throw new ArgumentOutOfRangeException("amount overwrite occurrences should be less than count bytes in stream");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long[] foundPositions = Find(searchPattern, amount);

            if (foundPositions.Length > 1 && foundPositions[0] != -1)
            {
                for (int i = 0; i < foundPositions.Length; i++)
                {
                    stream.Seek(foundPositions[i], SeekOrigin.Begin);
                    stream.Write(insertPattern, 0, insertPattern.Length);
                }
            }

            return foundPositions;
        }

        /// <summary>
        /// Find and insert (with overwrite) the specified number of times occurrences binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="insertPattern">Insert with overwrite</param>
        /// <returns>All indexes of overwritten data</returns>
        public long[] OverwriteBytesAtPatternPositions(string searchPattern, string insertPattern, int amount)
        {
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");
            if (string.IsNullOrEmpty(insertPattern))
                throw new ArgumentNullException("insertPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            bool isSearchPatternContainWildcards = testHexStringContainWildcards(searchPattern);
            long[] offsets;

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                offsets = Find_WithWildcardsMask(searchPatternBytes, wildcardsMask, amount);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                offsets = Find(searchPatternBytes, amount);
            }

            if (offsets.Length > 0 && offsets[0] != -1)
            {
                for (int i = 0; i < offsets.Length; i++)
                {
                    PasteBytesSequenceAtOffset(insertPattern, offsets[i]);
                }
            }

            return offsets;
        }

        /// <summary>
        /// Find and insert (with overwrite) all occurrences binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="insertPattern">Insert with overwrite</param>
        /// <returns>All indexes of overwritten data</returns>
        public long[] OverwriteBytesAtAllPatternPositions(byte[] searchPattern, byte[] insertPattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (insertPattern == null)
                throw new ArgumentNullException("insertPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long[] foundPositions = FindAll(searchPattern);

            if (foundPositions.Length > 1 && foundPositions[0] != -1)
            {
                for (int i = 0; i < foundPositions.Length; i++)
                {
                    stream.Seek(foundPositions[i], SeekOrigin.Begin);
                    stream.Write(insertPattern, 0, insertPattern.Length);
                }
            }

            return foundPositions;
        }

        /// <summary>
        /// Find and insert (with overwrite) all occurrences binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="insertPattern">Insert with overwrite</param>
        /// <returns>All indexes of overwritten data</returns>
        public long[] OverwriteBytesAtAllPatternPositions(string searchPattern, string insertPattern)
        {
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");
            if (string.IsNullOrEmpty(insertPattern))
                throw new ArgumentNullException("insertPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            bool isSearchPatternContainWildcards = testHexStringContainWildcards(searchPattern);
            long[] offsets;

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                offsets = FindAll_WithWildcardsMask(searchPatternBytes, wildcardsMask);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                offsets = FindAll(searchPatternBytes);
            }

            if (offsets.Length > 0 && offsets[0] != -1)
            {
                for (int i = 0; i < offsets.Length; i++)
                {
                    PasteBytesSequenceAtOffset(insertPattern, offsets[i]);
                }
            }

            return offsets;
        }

        /// <summary>
        /// Find and insert (with overwrite) first occurrence binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="insertPattern">Insert with overwrite</param>
        /// <returns>First index of overwritten data, or -1 if find is not found</returns>
        public long OverwriteBytesAtFirstPatternPosition(byte[] searchPattern, byte[] insertPattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (insertPattern == null)
                throw new ArgumentNullException("insertPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long foundPosition = FindFirst(searchPattern);

            if (foundPosition != -1)
            {
                stream.Seek(foundPosition, SeekOrigin.Begin);
                stream.Write(insertPattern, 0, insertPattern.Length);
            }

            return foundPosition;
        }

        /// <summary>
        /// Find and insert (with overwrite) first occurrence binary data in a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="insertPattern">Insert with overwrite</param>
        /// <returns>First index of overwritten data, or -1 if find is not found</returns>
        public long OverwriteBytesAtFirstPatternPosition(string searchPattern, string insertPattern)
        {
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");
            if (string.IsNullOrEmpty(insertPattern))
                throw new ArgumentNullException("insertPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            bool isSearchPatternContainWildcards = testHexStringContainWildcards(searchPattern);
            long offset;

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                offset = FindFromPosition_WithWildcardsMask(searchPatternBytes, wildcardsMask, 0);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                offset = FindFromPosition(searchPatternBytes, 0);
            }

            if (offset != -1)
            {
                PasteBytesSequenceAtOffset(insertPattern, offset);
            }

            return offset;
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
                throw new ArgumentOutOfRangeException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentOutOfRangeException("position must be within the stream body");
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
        /// Find byte array with mask array in a stream start from given decimal position
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="wildcardsMask">Mask if symbol is wildcards</param>
        /// <param name="position">Initial position in stream</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        private long FindFromPosition_WithWildcardsMask(byte[] searchPattern, bool[] wildcardsMask, long position = 0)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (wildcardsMask == null)
                throw new ArgumentNullException("wildcardsMask argument not given");
            if (searchPattern.Length != wildcardsMask.Length)
                throw new ArgumentException("wildcardsMask and search pattern must be same length");
            if (position < 0)
                throw new ArgumentOutOfRangeException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentOutOfRangeException("position must be within the stream body");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            bool isMaskFilledWildcards = Array.TrueForAll(wildcardsMask, x => x);
            if (isMaskFilledWildcards)
            {
                return position;
            }

            bool isMaskHasNoWildcards = Array.TrueForAll(wildcardsMask, x => !x);
            if (isMaskHasNoWildcards)
            {
                return FindFromPosition(searchPattern, position);
            }

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
                        if (!wildcardsMask[j] && buffer[foundIndex + j] != searchPattern[j])
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
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");
            if (position < 0)
                throw new ArgumentOutOfRangeException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentOutOfRangeException("position must be within the stream body");

            bool isSearchPatternContainWildcards = testHexStringContainWildcards(searchPattern);

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                return FindFromPosition_WithWildcardsMask(searchPatternBytes, wildcardsMask, position);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                return FindFromPosition(searchPatternBytes, position);
            }
        }

        /// <summary>
        /// Find first occurrence byte array from start a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        public long FindFirst(string searchPattern)
        {
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");

            bool isSearchPatternContainWildcards = testHexStringContainWildcards(searchPattern);

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                return FindFromPosition_WithWildcardsMask(searchPatternBytes, wildcardsMask, 0);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                return FindFromPosition(searchPatternBytes, 0);
            }
        }

        /// <summary>
        /// Find byte array from start a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        public long FindFirst(byte[] searchPattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            return FindFromPosition(searchPattern, 0);
        }

        /// <summary>
        /// Find byte array from start a stream for a set number of times
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="amount">number of times find</param>
        /// <returns>Indexes of found set occurrences or array with -1 or array with less amount indexes if occurrences less than given amount number</returns>
        public long[] Find(string searchPattern, int amount)
        {
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");
            if (amount > stream.Length)
                throw new ArgumentOutOfRangeException("amount search occurrences should be less than count bytes in stream");

            bool isSearchPatternContainWildcards = testHexStringContainWildcards(searchPattern);

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                return Find_WithWildcardsMask(searchPatternBytes, wildcardsMask, amount);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                return Find(searchPatternBytes, amount);
            }
        }

        /// <summary>
        /// Find byte array with wildcards mask from start a stream for a set number of times
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="wildcardsMask">Mask if symbol is wildcards</param>
        /// <param name="amount">number of times find</param>
        /// <returns>Indexes of found all occurrences or array with -1</returns>
        private long[] Find_WithWildcardsMask(byte[] searchPattern, bool[] wildcardsMask, int amount)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (wildcardsMask == null)
                throw new ArgumentNullException("wildcardsMask argument not given");
            if (searchPattern.Length != wildcardsMask.Length)
                throw new ArgumentException("wildcardsMask and search pattern must be same length");
            if (amount > stream.Length)
                throw new ArgumentOutOfRangeException("amount replace occurrences should be less than count bytes in stream");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            bool isMaskHasNoWildcards = Array.TrueForAll(wildcardsMask, x => !x);
            if (isMaskHasNoWildcards)
            {
                return Find(searchPattern, amount);
            }

            List<long> foundPositions = new List<long>();

            bool isMaskFilledWildcards = Array.TrueForAll(wildcardsMask, x => x);
            if (isMaskFilledWildcards)
            {
                long tempPosition = 0;
                long counter = 0;
                foundPositions.Add(tempPosition);

                while (tempPosition < stream.Length || counter < amount)
                {
                    tempPosition += searchPattern.Length;
                    if (tempPosition < stream.Length)
                    {
                        foundPositions.Add(tempPosition);
                        counter++;
                    }
                    else
                    {
                        return foundPositions.ToArray();
                    }
                }

                return foundPositions.ToArray();
            }

            long firstFoundPosition = FindFromPosition_WithWildcardsMask(searchPattern, wildcardsMask, 0);
            foundPositions.Add(firstFoundPosition);

            if (firstFoundPosition > 0 || amount > 1)
            {
                for (int i = 1; i < amount; i++)
                {
                    long nextFoundPosition = FindFromPosition_WithWildcardsMask(searchPattern, wildcardsMask, foundPositions[foundPositions.Count - 1] + 1);

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
        /// Find byte array from start a stream for a set number of times
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="amount">number of times find</param>
        /// <returns>Indexes of found set occurrences or array with -1 or array with less amount indexes if occurrences less than given amount number</returns>
        public long[] Find(byte[] searchPattern, int amount)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (amount > stream.Length)
                throw new ArgumentOutOfRangeException("amount replace occurrences should be less than count bytes in stream");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            List<long> foundPositions = new List<long>();
            long firstFoundPosition = FindFirst(searchPattern);
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
            long foundPosition = FindFirst(searchPattern);
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
        /// Find all occurrences of byte array from start a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>Indexes of found all occurrences or array with -1</returns>
        public long[] FindAll(string searchPattern)
        {
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");

            bool isSearchPatternContainWildcards = testHexStringContainWildcards(searchPattern);

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                return FindAll_WithWildcardsMask(searchPatternBytes, wildcardsMask);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);

                List<long> foundPositionsList = new List<long>();
                long firstFoundPosition = FindFirst(searchPatternBytes);
                foundPositionsList.Add(firstFoundPosition);

                if (firstFoundPosition > 0)
                {
                    long nextFoundPosition = firstFoundPosition;

                    while (nextFoundPosition < stream.Length - searchPatternBytes.Length)
                    {
                        nextFoundPosition = FindFromPosition(searchPatternBytes, foundPositionsList[foundPositionsList.Count - 1] + 1);

                        if (nextFoundPosition > 0)
                        {
                            foundPositionsList.Add(nextFoundPosition);
                        }
                        else
                        {
                            break;
                        }
                    }
                }

                return foundPositionsList.ToArray();
            }
        }

        /// <summary>
        /// Find all occurrences of byte array from start a stream
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>Indexes of found all occurrences or array with -1</returns>
        private long[] FindAll_WithWildcardsMask(byte[] searchPattern, bool[] wildcardsMask)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (wildcardsMask == null)
                throw new ArgumentNullException("wildcardsMask argument not given");
            if (searchPattern.Length != wildcardsMask.Length)
                throw new ArgumentException("wildcardsMask and search pattern must be same length");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            bool isMaskHasNoWildcards = Array.TrueForAll(wildcardsMask, x => !x);
            if (isMaskHasNoWildcards)
            {
                return FindAll(searchPattern);
            }

            List<long> foundPositions = new List<long>();

            bool isMaskFilledWildcards = Array.TrueForAll(wildcardsMask, x => x);
            if (isMaskFilledWildcards)
            {
                long tempPosition = 0;
                foundPositions.Add(tempPosition);

                while (tempPosition < stream.Length)
                {
                    tempPosition += searchPattern.Length;
                    if (tempPosition < stream.Length)
                    {
                        foundPositions.Add(tempPosition);
                    }
                    else
                    {
                        return foundPositions.ToArray();
                    }
                }

                return foundPositions.ToArray();
            }

            long firstFoundPosition = FindFromPosition_WithWildcardsMask(searchPattern, wildcardsMask, 0);
            foundPositions.Add(firstFoundPosition);

            if (firstFoundPosition > 0)
            {
                long nextFoundPosition = firstFoundPosition;
                
                while (nextFoundPosition < stream.Length - searchPattern.Length)
                {
                    nextFoundPosition = FindFromPosition_WithWildcardsMask(searchPattern, wildcardsMask, foundPositions[foundPositions.Count - 1] + 1);

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
        /// Paste bytes sequence start from given offset (replace bytes sequence start from offset)
        /// </summary>
        /// <param name="sequence">Bytes sequence</param>
        /// <param name="offset">Position in decimal</param>
        public void PasteBytesSequenceAtOffset(byte[] sequence, long offset)
        {
            if (sequence == null)
                throw new ArgumentNullException("sequence argument not given");
            if (offset < 0)
                throw new ArgumentOutOfRangeException("offset should more than zero");
            if (offset > stream.Length)
                throw new ArgumentOutOfRangeException("offset must be within the stream");
            if (offset + sequence.Length > stream.Length)
                throw new ArgumentOutOfRangeException("sequence must not extend beyond the file");

            stream.Seek(offset, SeekOrigin.Begin);
            stream.Write(sequence, 0, sequence.Length);
        }

        /// <summary>
        /// Paste bytes sequence start from given offset (replace bytes sequence start from offset) with wildcards
        /// </summary>
        /// <param name="sequence">Bytes sequence</param>
        /// <param name="wildcardsMask">wildcardsMask</param>
        /// <param name="offset">Position in decimal</param>
        private void PasteBytesSequenceAtOffset_WithWildcardsMask(byte[] sequence, bool[] wildcardsMask, long offset)
        {
            if (sequence == null)
                throw new ArgumentNullException("sequence argument not given");
            if (wildcardsMask == null)
                throw new ArgumentNullException("wildcardsMask argument not given");
            if (sequence.Length != wildcardsMask.Length)
                throw new ArgumentException("wildcardsMask and sequence bytes must be same length");
            if (offset < 0)
                throw new ArgumentOutOfRangeException("offset should more than zero");
            if (offset > stream.Length)
                throw new ArgumentOutOfRangeException("offset must be within the stream");
            if (offset + sequence.Length > stream.Length)
                throw new ArgumentOutOfRangeException("sequence must not extend beyond the file");

            stream.Seek(offset, SeekOrigin.Begin);

            for (int i = 0; i < sequence.Length; i++)
            {
                if (wildcardsMask[i])
                {
                    stream.Position += 1;
                    continue;
                }

                stream.WriteByte(sequence[i]);
            }
        }

        /// <summary>
        /// Paste bytes sequence start from given offset (replace bytes sequence start from offset)
        /// </summary>
        /// <param name="sequence">Bytes sequence</param>
        /// <param name="offset">Position in decimal</param>
        public void PasteBytesSequenceAtOffset(string sequence, long offset)
        {
            if (string.IsNullOrEmpty(sequence))
                throw new ArgumentNullException("sequence argument not given");
            if (offset < 0)
                throw new ArgumentOutOfRangeException("offset should more than zero");
            if (offset > stream.Length)
                throw new ArgumentOutOfRangeException("offset must be within the stream");

            bool isSequenceHaveWildcards = testHexStringContainWildcards(sequence);;

            if (isSequenceHaveWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(sequence);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;

                PasteBytesSequenceAtOffset_WithWildcardsMask(searchPatternBytes, wildcardsMask, offset);
            }
            else
            {
                byte[] sequenceArr = ConvertHexStringToByteArray(sequence);
                PasteBytesSequenceAtOffset(sequenceArr, offset);
            }
        }

        /// <summary>
        /// Dispose the stream
        /// </summary>
        public void Dispose()
        {
            stream.Dispose();
        }




        // 
        // 
        // LEGACY FUNCTIONS
        // 
        // I left these functions in a separate block of code because they seem to me to be faster due to the fact that when they work, an array with all the positions of the bytes found is not created, but simply 1 pass through the bytes of the stream is performed.
        // I haven't done any speed tests or comparisons, but it seems to me that these functions will be faster compared to functions based first on searching for positions, and then switching to each position found.
        // 
        // 





        /// <summary>
        /// Find byte array in a stream start from given decimal position
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="position">Initial position in stream</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        public long FindFromPosition_legacy(byte[] searchPattern, long position = 0)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (position < 0)
                throw new ArgumentNullException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentNullException("position must be within the stream body");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long foundPosition = -1;
            byte[] buffer = new byte[bufferSize + searchPattern.Length - 1];
            int bytesRead;
            stream.Position = position;

            while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                for (int i = 0; i <= bytesRead - searchPattern.Length; i++)
                {
                    bool match = true;
                    for (int j = 0; j < searchPattern.Length; j++)
                    {
                        if (buffer[i + j] != searchPattern[j])
                        {
                            match = false;
                            break;
                        }
                    }

                    if (match)
                    {
                        foundPosition = position + i;
                        return foundPosition;
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
        /// Find and replace all occurrences binary data in a stream
        /// </summary>
        /// <param name="find">Find</param>
        /// <param name="replace">Replace</param>
        /// <returns>All indexes of replaced data</returns>
        public long[] Replace_legacy(byte[] find, byte[] replace, int amount)
        {
            if (amount < 1)
                throw new ArgumentNullException("amount argument must be more than 0");
            if (find == null)
                throw new ArgumentNullException("find argument not given");
            if (replace == null)
                throw new ArgumentNullException("replace argument not given");
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
                        }
                        else
                        {
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

            return foundPositions.ToArray();
        }

        /// <summary>
        /// Find and replace all occurrences binary data in a stream
        /// </summary>
        /// <param name="find">Find</param>
        /// <param name="replace">Replace</param>
        /// <returns>All indexes of replaced data</returns>
        public long[] ReplaceAll_legacy(byte[] find, byte[] replace)
        {
            if (find == null)
                throw new ArgumentNullException("find argument not given");
            if (replace == null)
                throw new ArgumentNullException("replace argument not given");
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

            return foundPositions.ToArray();
        }

        /// <summary>
        /// Find and replace once binary data in a stream
        /// </summary>
        /// <param name="find">Find</param>
        /// <param name="replace">Replace</param>
        /// <returns>First index of replaced data, or -1 if find is not found</returns>
        public long ReplaceOnce_legacy(byte[] find, byte[] replace)
        {
            if (find == null)
                throw new ArgumentNullException("find argument not given");
            if (replace == null)
                throw new ArgumentNullException("replace argument not given");
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

            return foundPosition;
        }
    }
}

"@

# =====
# FUNCTIONS
# =====



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
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string[]]$patternsArray
    )
    
    [System.Collections.Generic.List[string]]$searchPatterns = New-Object System.Collections.Generic.List[string]
    [System.Collections.Generic.List[string]]$replacePatterns = New-Object System.Collections.Generic.List[string]

    # Separate pattern-string on search and replace strings
    foreach ($pattern in $patternsArray) {
        # Clean and split string with search and replace hex patterns
        [string[]]$temp = $pattern.Clone().Replace(" ","").Replace("\","/").Replace("|","/").ToUpper().Split("/")

        if (-not ($temp.Count -eq 2) -or $temp[1].Length -eq 0) {
            throw "Search pattern $pattern not have replace pattern"
        }

        [void]($searchPatterns.Add($temp[0]))
        [void]($replacePatterns.Add($temp[1]))
    }

    return $searchPatterns.ToArray(), $replacePatterns.ToArray()
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
    [string[]]$searchPatterns, [string[]]$replacePatterns = Separate-Patterns $patternsExtracted
    [System.Collections.Generic.List[long[]]]$positions = New-Object System.Collections.Generic.List[long[]]

    $BytesHandler = [HexHandler.BytesHandler]::new($stream)

    for ($i = 0; $i -lt $searchPatterns.Count; $i++) {
        [long[]]$positionsTemp = @($BytesHandler.OverwriteBytesAtAllPatternPositions($searchPatterns[$i], $replacePatterns[$i]))
        $positions.Add($positionsTemp)
    }

    Write-Host "Results:"
    
    for ($i = 0; $i -lt $positions.Count; $i++) {
        if (($positions[$i].Count -eq 1) -and ($positions[$i] -eq -1)) {
            Write-Host "Pattern: $($searchPatterns[$i]) | Replaced number of times: 0"
        } else {
            Write-Host "Pattern: $($searchPatterns[$i]) | Replaced number of times: $($positions[$i].Count)"
        }
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