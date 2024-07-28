# Function to convert hex string to byte array
function Convert-HexStringToByteArray {
    param (
        [string]$hexString
    )
    $hexString = $hexString -replace ' ', ''
    if ($hexString.Length % 2 -ne 0) {
        throw "Invalid hex string length."
    }
    [byte[]]$byteArray = @()
    for ($i = 0; $i -lt $hexString.Length; $i += 2) {
        $byteArray += [Convert]::ToByte($hexString.Substring($i, 2), 16)
    }
    return $byteArray
}

# Function to search and replace hex patterns in a binary file
function SearchAndReplace-HexPatternInBinaryFile {
    param (
        [string]$filePath,
        [string]$searchPattern,
        [string]$replacePattern
    )

    $searchBytes = Convert-HexStringToByteArray -hexString $searchPattern
    $replaceBytes = Convert-HexStringToByteArray -hexString $replacePattern

    if ($searchBytes.Length -ne $replaceBytes.Length) {
        throw "Search and replace patterns must be of the same length."
    }

    [byte[]]$fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    [int]$searchLength = $searchBytes.Length
    [int]$index = 0

    while ($index -lt $fileBytes.Length) {
        $foundIndex = [Array]::IndexOf($fileBytes, $searchBytes[0], $index)

        if ($foundIndex -eq -1) {
            break
        }

        $match = $true
        for ($i = 1; $i -lt $searchLength; $i++) {
            if ($fileBytes[$foundIndex + $i] -ne $searchBytes[$i]) {
                $match = $false
                break
            }
        }

        if ($match) {
            [Array]::Copy($replaceBytes, 0, $fileBytes, $foundIndex, $searchLength)
            $index = $foundIndex + $searchLength
        } else {
            $index = $foundIndex + 1
        }
    }

    [System.IO.File]::WriteAllBytes($filePath, $fileBytes)
}

# Main script
param (
    [string]$filePath,
    [string]$searchPattern,
    [string]$replacePattern
)

if (-not (Test-Path $filePath)) {
    Write-Error "File not found: $filePath"
    exit 1
}

try {
    SearchAndReplace-HexPatternInBinaryFile -filePath $filePath -searchPattern $searchPattern -replacePattern $replacePattern
    Write-Output "Hex pattern replaced successfully in $filePath"
} catch {
    Write-Error $_.Exception.Message
    exit 1
}