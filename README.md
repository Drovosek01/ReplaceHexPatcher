# Replace Hex native for Windows

Language: [Русский](README_RU.md) | English

- [Replace Hex native for Windows](#replace-hex-native-for-windows)
  - [What kind of repository is this](#what-kind-of-repository-is-this)
  - [Alternatives](#alternatives)
  - [Functions](#functions)
  - [Usage examples](#usage-examples)
    - [The main patcher script](#the-main-patcher-script)
    - [Wrapper script with data processing from template.txt](#wrapper-script-with-data-processing-from-templatetxt)
  - [What gives nativity](#what-gives-nativity)
  - [Where to start](#where-to-start)
  - [Documentation](#documentation)
  - [ToDo](#todo)
  - [Changelog](#changelog)
  - [Additional info](#additional-info)
  - [System requirements](#system-requirements)
    - [Configuring the Powershell](#configuring-the-powershell)
    - [Supported OS](#supported-os)


## What kind of repository is this

The code in this repository is the result of an attempt to find a Windows native way to find and replace bytes.

Native means it does not use third-party programs (only the tools included with the system, in this case Windows 10).

On UNIX systems, the search and replacement of bytes in hex format can be carried out using the utilities `perl` and `sed` (and probably some other tools) that are preinstalled in most GNU Linux distributions and in macOS too.

4 "code interpreters" are builtin in Windows - CMD, Visual Basic Script, Powershell, JavaScript.
CMD is too limited in capabilities. In Visual Basic Script, I have not found a way to write effective code to find and replace a byte pattern in a file of any size. But Powershell is, very roughly speaking, a C# code execution environment, and with C# you can do a lot of things, and therefore using Powershell code it is quite possible to search and replace bytes in hex format.

## Alternatives

I have not found any other ready-to-use Powershell or Visual Basic Script scripts to find byte replacements.
In this case, the alternative option is not a native method.:

- sed can be downloaded from (and is included in):
    - [sed-windows](https://github.com/mbuilov/sed-windows)
    - [sed for Windows](https://gnuwin32.sourceforge.net/packages/sed.htm) (GNU for Win32) + [Sourceforge files](https://sourceforge.net/projects/gnuwin32/files/sed/)
    - [Git for Windows](https://git-scm.com/download/win) or [site 2](https://gitforwindows.org/) and to use `perl` or `sed` which are available in Git Bash
    - [Cygwin](https://cygwin.com/)
    - [msysgit](https://github.com/msysgit/msysgit/) or [msys2](https://www.msys2.org/)
    - [GNU utilities for Win32](https://unxutils.sourceforge.net/)
    - [sed by Eric Pement](https://www.pement.org/sed/)
- [HexAndReplace](https://github.com/jjxtra/HexAndReplace)
- [BinaryFilePatcher](https://github.com/Invertex/BinaryFilePatcher)
- [BBE for Windows](https://anilech.blogspot.com/2016/09/binary-block-editor-bbe-for-windows.html)
- [HexPatcher](https://github.com/Haapavuo/HexPatcher/)

## Functions

Main:
- Search and replace all found hex-byte sequences
- Only searching (counting occurrences) of hex byte sequences
- Output of an array of found positions for each search pattern in decimal or hexadecimal formats
- The possibility of using wildcard characters "??" in patterns
- Creating backups of files if hex patterns are found
- Non-strict format of hex values (omnivorous data)
- Independent length of replacement patterns
- Requests administrator rights only if necessary

Together with the wrappers:
- Byte substitution in multiple files or checking that they have already been patched
- Deleting files and folders
- Adding lines to the `hosts` file
- Deleting specific text and addresses from the `hosts` file
- File blocking in Windows Firewall
- Removing all rules for specific files from Windows Firewall
- Working with a template file with prepared patterns
- Using variables in the template
  - Create new text files based on text
  - Creation of new files based on base64
  - Using strings to modify the registry
  - Executing Powershell code from a template
  - Executing CMD code from a template

For more information, see [documentation](./docs/docs_EN.md)

## Usage examples

### The main patcher script

```powershell
.\ReplaceHexBytesAll.ps1 -filePath "<path to file>" -patterns "<hex search pattern>/<hex replacement pattern>",
```
- `hex pattern` has no strict format.
  - There can be any number of spaces and `\x` characters between the values in the pattern - all of them will be deleted (their presence will not cause errors)
  - Wildcard characters `??` can be used in search and replace patterns
- the separator between the search and replace patterns can be one of the characters `/`,`\`,`|`
- in the `-patterns` parameter, you can pass both an array of patterns in the form of comma-separated strings, and 1 line in which the sets of patterns are separated by a comma
- you can pass the `-makeBackup` parameter and then the original file will be saved with the added extension `.bak`

Here is an example:

1. Start Powershell
2. Use `cd <path>` to go to the folder with the file `ReplaceHexBytesAll.ps1`
3. In the Powershell window, run:
```powershell
.\ReplaceHexBytesAll.ps1 -filePath "D:\TEMP\file.exe" -patterns "48 83EC2 8BA2F 000000 488A/202 0EB1 1111 11111 111111","C42518488D4D68\90909011111175","45A8488D55A8|75EB88909090","\xAA\x7F\xBB\x08\xE3\x4D|\xBB\x90\xB1\xE8\x99\x4D" -makeBackup -showMoreInfo -showFoundOffsetsInHex
```

### Wrapper script with data processing from template.txt

The `wrappers` folder contains the `data in template` folder and the files `Start.cmd`, `Parser.ps1`, `template.txt`

An approximate algorithm:
1. Fill in the form `template.txt` or any other txt file, depending on what you need to do.
2. Run `Start.cmd` and select the written txt file
3. Or use Powershell to directly run `Parser.ps1` and pass it the path or template link as an argument.:
```powershell
.\Parser.ps1 -templatePath "D:\path to\template.txt "
```


## What gives nativity

When implementing the idea, the emphasis was also on making the tool completely, absolutely native to the system in which it is executed (that is, for Windows in this case). So that you don't have to download and install any dependencies, libraries, runtime, etc. So that everything is done solely by the system itself, that is, by what it has "out of the box".

There are no binary files in the project in any form and they are not needed for the utility to work. Only the text code.

Due to this, you can not download anything, but simply execute such a command in the Powershell window to apply hex patterns.:
```powershell
irm "https://github.com/Drovosek01/ReplaceHexPatcher/raw/refs/heads/main/core/v2/ReplaceHexBytesAll.ps1" -OutFile $env:TEMP\t.ps1; & $env:TEMP\t.ps1 -filePath "C:\Program Files\Adobe\Adobe Photoshop 2025\DaVinci Remote Monitor.exe" -patterns "B9000000/11111111", "0F 31 89 C2 44 29 C0 41 89 D0 44 39 C8 41 89 C1/11", "EF C4 66 41 0F 6F 22 66/778899" -showMoreInfo -makeBackup -showFoundOffsetsInHex; ri $env:TEMP\t.ps1
```
or
```powershell
irm "https://github.com/Drovosek01/ReplaceHexPatcher/raw/refs/heads/main/wrappers/data%20in%20template/Parser.ps1" -OutFile $env:TEMP\t.ps1; & $env:TEMP\t.ps1 '[start-flags]
MAKE_BACKUPS
VERBOSE
[end-flags]


[start-patch_bin]
C:\Users\USERNAME_FIELD\Desktop\hextests\DaVinci Remote Monitor.exe
7B 58 5D D9 80 DF 5F D8 52 69 63 68 81 DF 5F D8
112233

FF FF EF BF
AA 11 BB 22


C:\Users\USERNAME_FIELD\Desktop\hextests\CorelCAD.21.2.1.3523 Win 64bit.rar
00 00 3F 73
CC CC CC CC
2B 77 4D CE E9 B1 6D 92 89 BD 3B C3 3F A4 98 CC
2B 77 4D CE E9 B1 6D 92 89 BD 3B C3 3F A4 98 33
[end-patch_bin]'; ri $env:TEMP\t.ps1
```

## Where to start

1. Start by manually performing the actions.
  - This tool automates what is usually done manually - searching and replacing bytes in the hex editor, changing the hosts file, adding or removing rules in the firewall, etc. If you can't do it manually, then not using automated tools is probably a bad idea.
2. Read the [documentation](./docs/docs_EN.md)
3. Practice using only the main script [ReplaceHexBytesAll.ps1](./core/ReplaceHexBytesAll.ps1) on some binary file
4. Decide what you need to do/automate - just byte replacement or something else
5. Correct/rewrite [template](./wrappers/data%20in%20template/template.txt) for your tasks and test the execution of your template


## Documentation

In a separate [file](./docs/docs_EN.md)


## ToDo

In a separate [file](./docs/todo_EN.md)


## Changelog

In a separate [file](./docs/changelog_EN.md)


## Additional info

In a separate [file](./docs/additional_info_EN.md)


## System requirements

### Configuring the Powershell

Configuring the Powershell Script Launch Policy (ExecutionPolicy) - [learn.microsoft.com v1](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1), [learn.microsoft.com v2](https://learn.microsoft.com/previous-versions/windows/powershell-scripting/hh847748(v=wps.640)), [StackOverflow (RU)](https://ru.stackoverflow.com/questions/935212/powershell-%d0%b2%d1%8b%d0%bf%d0%be%d0%bb%d0%bd%d0%b5%d0%bd%d0%b8%d0%b5-%d1%81%d1%86%d0%b5%d0%bd%d0%b0%d1%80%d0%b8%d0%b5%d0%b2-%d0%be%d1%82%d0%ba%d0%bb%d1%8e%d1%87%d0%b5%d0%bd%d0%be-%d0%b2-%d1%8d%d1%82%d0%be%d0%b9-%d1%81%d0%b8%d1%81%d1%82%d0%b5%d0%bc%d0%b5)

Run Powershell as an administrator and run the command

For one-time use of the script
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

For frequent use of the script
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser
```

### Supported OS

All the code was written and tested on Windows 10 x64 22H2.
It is expected that in Windows 11 it will also work out of the box.

I have not checked the compatibility of the code and the Powershell functions used with previous versions. You will probably need Powershell 5.1, which comes bundled with Windows 10, to perform them.

If you are running on Windows 7, 8, 8.1, then you will probably need to install [Microsoft.NET Framework 4.8](https://support.microsoft.com/topic/microsoft-net-framework-4-8-offline-installer-for-windows-9d23f658-3b97-68ab-d013-aa3c3e7495e0) and [Powershell 5.1](https://www.microsoft.com/download/details.aspx/?id=54616) to make the code from this repository work for you.
