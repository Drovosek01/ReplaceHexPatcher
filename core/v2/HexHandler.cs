using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;

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
                                                .Replace("h", string.Empty)
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
                                                .Replace("h", string.Empty)
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

        private bool TestHexStringContainWildcards(string hexString, string wildcardExample = wildcard)
        {
            string hexStringCleaned = hexString.Replace(" ", string.Empty)
                                                .Replace(wildcardInRegExp, wildcardExample);

            return hexStringCleaned.IndexOf(wildcardExample) != -1 || hexStringCleaned.IndexOf(wildcardInRegExp) != -1;
        }

        private byte[] CreateArrayFilledIdenticalBytes(int size, byte element)
        {
            byte[] result = new byte[size];

            for (int i = 0; i < size; i++)
            {
                result[i] = element;
            }

            return result;
        }

        /// <summary>
        /// Check if file start from 2 symbols - MZ (or 4D 5A in hex)
        /// It part of check if file is PE-file
        /// </summary>
        /// <returns>True if file start with MZ symbols or false if not</returns>
        private bool IsFileStartWithMZSymbols()
        {
            byte[] mzSignature = new byte[] { 0x4D, 0x5A };
            return StartsWith(mzSignature);
        }

        /// <summary>
        /// Check if file at offset/position 0x3C have pointer to PE-header
        /// and on this position we have hex 50 45 00 00 (PE\0\0)
        /// </summary>
        /// <returns>True if file have pointer to PE-header and PE-header</returns>
        private bool IsFileHavePointerToPEHeader()
        {
            // got to offset 0x3C
            stream.Seek(60, SeekOrigin.Begin);
            byte[] buffer = new byte[4];
            if (stream.Read(buffer, 0, buffer.Length) != buffer.Length)
            {
                return false;
            }

            int position = BitConverter.ToInt32(buffer, 0);
            byte[] PE00_buffer = new byte[4];
            stream.Seek(position, SeekOrigin.Begin);
            if (stream.Read(PE00_buffer, 0, PE00_buffer.Length) != PE00_buffer.Length)
            {
                return false;
            }
            byte[] PE00_true = new byte[] { 0x50, 0x45, 0x00, 0x00 };

            return PE00_buffer.SequenceEqual(PE00_true);
        }
        
        /// <summary>
        /// Detect if file is PE-file like .exe or .dll or sys...
        /// </summary>
        /// <returns>True if file is PE-file</returns>
        public bool IsFilePEFile()
        {
            return IsFileStartWithMZSymbols() && IsFileHavePointerToPEHeader();
        }

        /// <summary>
        /// Test if stream has same bytes array as given in given position
        /// </summary>
        /// <param name="sequence">Bytes sequence</param>
        /// <param name="position">Stream position</param>
        /// <returns>True if stream in given position has same bytes sequence</returns>
        private bool DoesStreamHaveSequenceInPosition(byte[] sequence, long position)
        {
            if (sequence.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", sequence.Length, bufferSize));
            if (position < 0)
                throw new ArgumentOutOfRangeException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentOutOfRangeException("position must be within the stream body");

            byte[] buffer = new byte[sequence.Length];
            stream.Position = position;
            stream.Read(buffer, 0, buffer.Length);

            for (int i = 0; i < sequence.Length; i++)
            {
                if (buffer[i] != sequence[i])
                {
                    return false;
                }
            }

            return true;
        }

        /// <summary>
        /// Test if stream has same bytes array (with wildcardsMask) as given in given position
        /// </summary>
        /// <param name="sequence">Bytes sequence</param>
        /// <param name="wildcardsMask">wildcardsMask</param>
        /// <param name="position">Stream position</param>
        /// <returns>True if stream in given position has same bytes sequence (with wildcardsMask)</returns>
        private bool DoesStreamHaveSequenceInPosition_WithWildcardsMask(byte[] sequence, bool[] wildcardsMask, long position)
        {
            if (sequence.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", sequence.Length, bufferSize));
            if (position < 0)
                throw new ArgumentOutOfRangeException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentOutOfRangeException("position must be within the stream body");

            byte[] buffer = new byte[sequence.Length];
            stream.Position = position;
            stream.Read(buffer, 0, buffer.Length);

            for (int i = 0; i < sequence.Length; i++)
            {
                if (!wildcardsMask[i] && buffer[i] != sequence[i])
                {
                    return false;
                }
            }

            return true;
        }

        /// <summary>
        /// Extract array without duplicates at edges given array
        /// </summary>
        /// <example>
        /// For example for array:
        /// 00 00 00 00 79 00 AE 88 F1 C5 00 90 C3 90 90 90
        /// will extracted array
        /// 00 79 00 AE 88 F1 C5 00 90 C3 90
        /// and
        /// skipFromStart = 3
        /// skipFromEnd = 2
        /// </example>
        /// <param name="searchPattern">Bytes array mean search pattern</param>
        /// <returns>Return array without duplicates at edges and number of skipped elements from start source array and number of skipped elements from end source array</returns>
        private Tuple<byte[], Tuple<int, int>> extractArrayWithoutDuplicatesAtEdges(byte[] searchPattern)
        {
            int skipFromStart = 0;
            int skipFromEnd = 0;

            // in case when all array elements are identical
            if (searchPattern.Distinct().Count() == 1)
            {
                return Tuple.Create(new byte[] {searchPattern[0]}, Tuple.Create(0, searchPattern.Length - 2));
            }

            // loop from start array
            for (int i = 1; i < searchPattern.Length; i++)
            {
                if (searchPattern[i] != searchPattern[i - 1])
                {
                    break;
                }

                skipFromStart++;
            }

            // loop from end array
            for (int i = searchPattern.Length - 2; i > 0; i--)
            {
                if (searchPattern[i] != searchPattern[i + 1])
                {
                    break;
                }

                skipFromEnd++;
            }

            int newLength = searchPattern.Length - skipFromStart - skipFromEnd;
            byte[] result = new byte[newLength];
            Array.Copy(searchPattern, skipFromStart, result, 0, newLength);

            return Tuple.Create(result, Tuple.Create(skipFromStart, skipFromEnd));
        }

        /// <summary>
        /// Extract array without duplicates wildcards at edges given array
        /// </summary>
        /// <example>
        /// For example for pattern:
        /// ?? ?? ?? ?? 79 00 AE ?? F1 ?? 00 90 C3 ?? ?? ??
        /// we will have bytes array
        /// 00 00 00 00 79 00 AE 00 F1 00 00 90 C3 00 00 00
        /// and wildcardsMask (in this example "11" - true, "00" - false)
        /// 11 11 11 11 00 00 00 11 00 11 00 00 00 11 11 11
        /// will extracted array
        /// 79 00 AE 00 F1 00 00 90 C3
        /// and wildcardsMask
        /// 00 00 00 11 00 11 00 00 00
        /// and
        /// skipFromStart = 4
        /// skipFromEnd = 3
        /// </example>
        /// <param name="searchPattern">Bytes array mean search pattern</param>
        /// <param name="wildcardsMask">Bool array mean position wildcards in bytes array</param>
        /// <returns>Return array without duplicates at edges and number of skipped elements from start source array and number of skipped elements from end source array</returns>
        private Tuple<Tuple<byte[], bool[]>, Tuple<int, int>> extractArrayWithoutDuplicatesAtEdges_WithWildcardsMask(byte[] searchPattern, bool[] wildcardsMask)
        {
            int skipFromStart = 0;
            int skipFromEnd = 0;

            // loop from start array
            for (int i = 0; i < wildcardsMask.Length; i++)
            {
                if (!wildcardsMask[i])
                {
                    break;
                }

                skipFromStart++;
            }

            // loop from end array
            for (int i = wildcardsMask.Length - 1; i > 0; i--)
            {
                if (!wildcardsMask[i])
                {
                    break;
                }

                skipFromEnd++;
            }

            int newLength = wildcardsMask.Length - skipFromStart - skipFromEnd;
            byte[] resultBytes = new byte[newLength];
            bool[] resultWildCards = new bool[newLength];
            Array.Copy(searchPattern, skipFromStart, resultBytes, 0, newLength);
            Array.Copy(wildcardsMask, skipFromStart, resultWildCards, 0, newLength);

            return Tuple.Create(Tuple.Create(resultBytes, resultWildCards), Tuple.Create(skipFromStart, skipFromEnd));
        }

        /// <summary>
        /// Test if stream starts from given bytes array
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>True if stream start from given byte array</returns>
        public bool StartsWith(byte[] searchPattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));
            
            return DoesStreamHaveSequenceInPosition(searchPattern, 0);
        }

        /// <summary>
        /// Test if stream starts from given hexString
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>True if stream start from given hexString</returns>
        public bool StartsWith(string searchPattern)
        {
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");
            
            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;

                return DoesStreamHaveSequenceInPosition_WithWildcardsMask(searchPatternBytes, wildcardsMask, 0);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);

                return StartsWith(searchPatternBytes);
            }
        }

        /// <summary>
        /// Test if stream ends with given bytes array
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>True if stream ends with given byte array</returns>
        public bool EndsWith(byte[] searchPattern)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (searchPattern.Length > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));
            
            return DoesStreamHaveSequenceInPosition(searchPattern, stream.Length - searchPattern.Length);
        }

        /// <summary>
        /// Test if stream ends with given hexString
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <returns>True if stream ends with given hexString</returns>
        public bool EndsWith(string searchPattern)
        {
            if (string.IsNullOrEmpty(searchPattern))
                throw new ArgumentNullException("searchPattern argument not given");
            
            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;

                return DoesStreamHaveSequenceInPosition_WithWildcardsMask(searchPatternBytes, wildcardsMask, stream.Length - searchPatternBytes.Length);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);

                return EndsWith(searchPatternBytes);
            }
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

            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);
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

            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);
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

            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);
            long offset;

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                
                Tuple<Tuple<byte[], bool[]>, Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges_WithWildcardsMask(searchPatternBytes, wildcardsMask);
                byte[] genuineArray = extractedData.Item1.Item1;
                bool[] genuineMask = extractedData.Item1.Item2;
                int skippedFromStart = extractedData.Item2.Item1;
                int skippedFromEnd = extractedData.Item2.Item2;

                offset = FindFromPosition_WithWildcardsMask(genuineArray, genuineMask, 0, skippedFromStart, skippedFromEnd);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                offset = FindFirst(searchPatternBytes);
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
        /// <param name="skippedFromStart">Number of skipped/removed identical bytes from start/begin of search pattern</param>
        /// <param name="skippedFromEnd">Number of skipped/removed identical bytes from end of search pattern</param>
        /// <param name="stepBackFromEnd">Number of bytes to be indented before the end of the file</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        public long FindFromPosition(byte[] searchPattern, long position = 0, int skippedFromStart = 0, int skippedFromEnd = 0, long stepBackFromEnd = 0)
        {
            if (searchPattern == null)
                throw new ArgumentNullException("searchPattern argument not given");
            if (position < 0)
                throw new ArgumentOutOfRangeException("position should more than zero");
            if (position > stream.Length)
                throw new ArgumentOutOfRangeException("position must be within the stream body");
            if (searchPattern.Length + skippedFromStart + skippedFromEnd > bufferSize)
                throw new ArgumentException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            long foundPosition = -1;
            byte[] buffer = new byte[bufferSize + searchPattern.Length - 1];
            int bytesRead;
            stream.Position = position;

            bool isPatternHaveDuplicatesAtEdges = skippedFromStart > 0 || skippedFromEnd > 0;

            while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                int index = 0;

                while (index <= (bytesRead - searchPattern.Length))
                {
                    int foundIndex = Array.IndexOf(buffer, searchPattern[0], index);

                    if (foundIndex == -1 || foundIndex + searchPattern.Length > buffer.Length)
                        break;

                    bool match = true;

                    // Check the remaining bytes, starting from the END of the pattern
                    // (going from searchPattern.Length - 1 down to 1, since index 0 has already been checked)
                    for (int j = searchPattern.Length - 1; j >= 1; j--)
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

                        if (isPatternHaveDuplicatesAtEdges)
                        {
                            if (skippedFromStart > foundPosition || foundPosition - skippedFromStart < position)
                            {
                                match = false;
                                index = foundIndex + 1;
                                continue;
                            }

                            if (skippedFromEnd > stream.Length - foundPosition - stepBackFromEnd)
                            {
                                return -1;
                            }

                            if (skippedFromStart > 0)
                            {
                                byte[] skippedBytes = CreateArrayFilledIdenticalBytes(skippedFromStart, searchPattern[0]);

                                if (!DoesStreamHaveSequenceInPosition(skippedBytes, foundPosition - skippedFromStart))
                                {
                                    match = false;
                                    index = foundIndex + 1;
                                    continue;
                                }
                            }

                            if (skippedFromEnd > 0)
                            {
                                byte[] skippedBytes = CreateArrayFilledIdenticalBytes(skippedFromEnd, searchPattern[searchPattern.Length - 1]);

                                if (!DoesStreamHaveSequenceInPosition(skippedBytes, foundPosition + searchPattern.Length))
                                {
                                    match = false;
                                    index = foundIndex + searchPattern.Length + 1;
                                    continue;
                                }
                            }

                            return foundPosition - skippedFromStart;
                        }
                        else
                        {
                            return foundPosition;
                        }
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

            return -1;
        }

        /// <summary>
        /// Find byte array with mask array in a stream start from given decimal position
        /// </summary>
        /// <param name="searchPattern">Find</param>
        /// <param name="wildcardsMask">Mask if symbol is wildcards</param>
        /// <param name="position">Initial position in stream</param>
        /// <param name="skippedFromStart">Number of skipped/removed wildcard bytes from start/begin of wildcardsMask</param>
        /// <param name="skippedFromEnd">Number of skipped/removed wildcard bytes from end of wildcardsMask</param>
        /// <returns>First index of byte array data, or -1 if find is not found</returns>
        private long FindFromPosition_WithWildcardsMask(byte[] searchPattern, bool[] wildcardsMask, long position = 0, int skippedFromStart = 0, int skippedFromEnd = 0)
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
            if (searchPattern.Length + skippedFromStart + skippedFromEnd > bufferSize)
                throw new ArgumentOutOfRangeException(string.Format("Find size {0} is too large for buffer size {1}", searchPattern.Length, bufferSize));

            bool isMaskFilledWildcards = Array.TrueForAll(wildcardsMask, x => x);
            if (isMaskFilledWildcards)
            {
                return position;
            }

            bool isMaskHasNoWildcards = Array.TrueForAll(wildcardsMask, x => !x);
            if (isMaskHasNoWildcards)
            {
                Tuple<byte[], Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges(searchPattern);
                byte[] genuineArray = extractedData.Item1;
                int skippedFromStartGenuine = extractedData.Item2.Item1;
                int skippedFromEndGenuine = extractedData.Item2.Item2;

                return FindFromPosition(genuineArray, position + skippedFromStart, skippedFromStartGenuine, skippedFromEndGenuine, skippedFromEnd) - skippedFromStart;
            }

            long foundPosition = -1;
            byte[] buffer = new byte[bufferSize + searchPattern.Length - 1];
            int bytesRead;
            stream.Position = position;

            bool isPatternHaveDuplicatesAtEdges = skippedFromStart > 0 || skippedFromEnd > 0;

            while ((bytesRead = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                int index = 0;

                while (index <= (bytesRead - searchPattern.Length))
                {
                    int foundIndex = Array.IndexOf(buffer, searchPattern[0], index);

                    if (foundIndex == -1 || foundIndex + searchPattern.Length > buffer.Length)
                        break;

                    bool match = true;
                    
                    // Check the remaining bytes, starting from the END of the pattern
                    // (going from searchPattern.Length - 1 down to 1, since index 0 has already been checked)
                    for (int j = searchPattern.Length - 1; j >= 1; j--)
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

                        if (isPatternHaveDuplicatesAtEdges)
                        {
                            if (skippedFromStart > foundPosition || foundPosition - skippedFromStart < position)
                            {
                                match = false;
                                index = foundIndex + 1;
                                continue;
                            }

                            if (skippedFromEnd > stream.Length - foundPosition)
                            {
                                return -1;
                            }

                            return foundPosition - skippedFromStart;
                        }
                        else
                        {
                            return foundPosition;
                        }
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

            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                
                Tuple<Tuple<byte[], bool[]>, Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges_WithWildcardsMask(searchPatternBytes, wildcardsMask);
                byte[] genuineArray = extractedData.Item1.Item1;
                bool[] genuineMask = extractedData.Item1.Item2;
                int skippedFromStart = extractedData.Item2.Item1;
                int skippedFromEnd = extractedData.Item2.Item2;

                return FindFromPosition_WithWildcardsMask(genuineArray, genuineMask, position, skippedFromStart, skippedFromEnd);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                Tuple<byte[], Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges(searchPatternBytes);
                byte[] genuineArray = extractedData.Item1;
                int skippedFromStart = extractedData.Item2.Item1;
                int skippedFromEnd = extractedData.Item2.Item2;

                return FindFromPosition(genuineArray, position, skippedFromStart, skippedFromEnd);
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

            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);

            if (isSearchPatternContainWildcards)
            {
                Tuple<byte[], bool[]> dataPair = ConvertHexStringWithWildcardsToByteArrayAndMask(searchPattern);
                byte[] searchPatternBytes = dataPair.Item1;
                bool[] wildcardsMask = dataPair.Item2;
                
                Tuple<Tuple<byte[], bool[]>, Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges_WithWildcardsMask(searchPatternBytes, wildcardsMask);
                byte[] genuineArray = extractedData.Item1.Item1;
                bool[] genuineMask = extractedData.Item1.Item2;
                int skippedFromStart = extractedData.Item2.Item1;
                int skippedFromEnd = extractedData.Item2.Item2;

                return FindFromPosition_WithWildcardsMask(genuineArray, genuineMask, 0, skippedFromStart, skippedFromEnd);
            }
            else
            {
                byte[] searchPatternBytes = ConvertHexStringToByteArray(searchPattern);
                Tuple<byte[], Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges(searchPatternBytes);
                byte[] genuineArray = extractedData.Item1;
                int skippedFromStart = extractedData.Item2.Item1;
                int skippedFromEnd = extractedData.Item2.Item2;

                return FindFromPosition(genuineArray, 0, skippedFromStart, skippedFromEnd);
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

            Tuple<byte[], Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges(searchPattern);
            byte[] genuineArray = extractedData.Item1;
            int skippedFromStart = extractedData.Item2.Item1;
            int skippedFromEnd = extractedData.Item2.Item2;

            return FindFromPosition(genuineArray, 0, skippedFromStart, skippedFromEnd);
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

            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);

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
                
            Tuple<Tuple<byte[], bool[]>, Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges_WithWildcardsMask(searchPattern, wildcardsMask);
            byte[] genuineArray = extractedData.Item1.Item1;
            bool[] genuineMask = extractedData.Item1.Item2;
            int skippedFromStart = extractedData.Item2.Item1;
            int skippedFromEnd = extractedData.Item2.Item2;

            long firstFoundPosition = FindFromPosition_WithWildcardsMask(genuineArray, genuineMask, 0, skippedFromStart, skippedFromEnd);
            foundPositions.Add(firstFoundPosition);

            if (firstFoundPosition > 0 || amount > 1)
            {
                for (int i = 1; i < amount; i++)
                {
                    long nextFoundPosition = FindFromPosition_WithWildcardsMask(genuineArray, genuineMask, foundPositions[foundPositions.Count - 1] + searchPattern.Length, skippedFromStart, skippedFromEnd);

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

            Tuple<byte[], Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges(searchPattern);
            byte[] genuineArray = extractedData.Item1;
            int skippedFromStart = extractedData.Item2.Item1;
            int skippedFromEnd = extractedData.Item2.Item2;

            List<long> foundPositions = new List<long>();
            long firstFoundPosition = FindFirst(searchPattern);
            foundPositions.Add(firstFoundPosition);

            if (firstFoundPosition > 0 || amount > 1)
            {
                for (int i = 1; i < amount; i++)
                {
                    long nextFoundPosition = FindFromPosition(genuineArray, foundPositions[foundPositions.Count - 1] + searchPattern.Length, skippedFromStart, skippedFromEnd);

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

            Tuple<byte[], Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges(searchPattern);
            byte[] genuineArray = extractedData.Item1;
            int skippedFromStart = extractedData.Item2.Item1;
            int skippedFromEnd = extractedData.Item2.Item2;

            List<long> foundPositionsList = new List<long>();
            long foundPosition = FindFirst(searchPattern);
            foundPositionsList.Add(foundPosition);

            if (foundPosition > 0)
            {
                while (foundPosition < stream.Length - searchPattern.Length)
                {
                    foundPosition = FindFromPosition(genuineArray, foundPositionsList[foundPositionsList.Count - 1] + searchPattern.Length, skippedFromStart, skippedFromEnd);

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

            bool isSearchPatternContainWildcards = TestHexStringContainWildcards(searchPattern);

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
                Tuple<byte[], Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges(searchPatternBytes);
                byte[] genuineArray = extractedData.Item1;
                int skippedFromStart = extractedData.Item2.Item1;
                int skippedFromEnd = extractedData.Item2.Item2;

                List<long> foundPositionsList = new List<long>();
                long firstFoundPosition = FindFirst(searchPatternBytes);
                foundPositionsList.Add(firstFoundPosition);

                if (firstFoundPosition > 0)
                {
                    long nextFoundPosition = firstFoundPosition;

                    while (nextFoundPosition < stream.Length - searchPatternBytes.Length)
                    {
                        nextFoundPosition = FindFromPosition(genuineArray, foundPositionsList[foundPositionsList.Count - 1] + searchPatternBytes.Length, skippedFromStart, skippedFromEnd);

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
                
            Tuple<Tuple<byte[], bool[]>, Tuple<int, int>> extractedData = extractArrayWithoutDuplicatesAtEdges_WithWildcardsMask(searchPattern, wildcardsMask);
            byte[] genuineArray = extractedData.Item1.Item1;
            bool[] genuineMask = extractedData.Item1.Item2;
            int skippedFromStart = extractedData.Item2.Item1;
            int skippedFromEnd = extractedData.Item2.Item2;

            long firstFoundPosition = FindFromPosition_WithWildcardsMask(genuineArray, genuineMask, 0, skippedFromStart, skippedFromEnd);
            foundPositions.Add(firstFoundPosition);

            if (firstFoundPosition > 0)
            {
                long nextFoundPosition = firstFoundPosition;
                
                while (nextFoundPosition < stream.Length - searchPattern.Length)
                {
                    nextFoundPosition = FindFromPosition_WithWildcardsMask(genuineArray, genuineMask, foundPositions[foundPositions.Count - 1] + searchPattern.Length, skippedFromStart, skippedFromEnd);

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

            bool isSequenceHaveWildcards = TestHexStringContainWildcards(sequence);;

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
                // Limit the loop so that i + (pattern length - 1) does not go beyond the number of bytes read
                int limit = bytesRead - searchPattern.Length;

                for (int i = 0; i <= limit; i++)
                {
                    // Checking the first byte (quick check)
                    if (buffer[i] == searchPattern[0])
                    {
                        bool match = true;

                        // Check the remaining bytes, starting from the END of the pattern
                        // (going from searchPattern.Length - 1 down to 1, since index 0 has already been checked)
                        for (int j = searchPattern.Length - 1; j >= 1; j--)
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
                }

                // Calculate the offset for the next read
                // Shift so that the last block checked fits into the next buffer (overlap)

                long nextPosition = position + bytesRead - searchPattern.Length + 1;
        
                if (nextPosition >= stream.Length || nextPosition <= position)
                    break;

                position = nextPosition;
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
