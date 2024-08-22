Language: [Русский](README_RU.md) | English

## What kind of repository is this

The code in this repository is the result of an attempt to find a Windows native way to find and replace bytes.

Native means it does not use third-party programs (only the tools included with the system, in this case Windows 10).

On UNIX systems, the search and replacement of bytes in hex format can be carried out using the utilities `perl` and `sed` (and probably some other tools) that are preinstalled in most GNU Linux distributions and in macOS too.

3 "programming tools" are preinstalled in Windows - CMD, Visual Basic Script, Powershell.
CMD is too limited in capabilities. In Visual Basic Script, I have not found a way to write effective code to find and replace a byte pattern in a file of any size. But Powershell is, very roughly speaking, a C# code execution environment, and with C# you can do a lot of things, and therefore using Powershell code it is quite possible to search and replace bytes in hex format.

## Alternatives

I have not found any other ready-to-use Powershell or Visual Basic Script scripts to find byte replacements.
In this case, the alternative option is not a native method.:

- sed can be downloaded from (and is included in):
    - [sed-windows](https://github.com/mbuilov/sed-windows)
    - [sed for Windows](https://gnuwin32.sourceforge.net/packages/sed.htm) (GNU for Win32) + [Sourceforge files](https://sourceforge.net/projects/gnuwin32/files/sed/)
    - [Git for Windows](https://git-scm.com/download/win) or [сайт 2](https://gitforwindows.org/) and to use `perl` и `sed` which are available in Git Bash
    - [Cygwin](https://cygwin.com/)
    - [msysgit](https://github.com/msysgit/msysgit/) or [msys2](https://www.msys2.org/)
    - [GNU utilities for Win32](https://unxutils.sourceforge.net/)
    - [sed by Eric Pement](https://www.pement.org/sed/)
- [HexAndReplace](https://github.com/jjxtra/HexAndReplace)
- [BinaryFilePatcher](https://github.com/Invertex/BinaryFilePatcher)
- [BBE for Windows](https://anilech.blogspot.com/2016/09/binary-block-editor-bbe-for-windows.html)

## Functions

Main:
- Search and replace all found byte sequences
- Creating backups of files if hex patterns are found
- Several possible formats of transmitted hex values
- Requests administrator rights only if necessary

Together with the wrappers:
- Byte substitution in multiple files
- Deleting files and folders
- Adding lines to the `hosts` file
- Deleting specific text and addresses from the `hosts` file
- File blocking in Windows Firewall
- Removing all rules for specific files from Windows Firewall
- Working with a template file with prepared patterns
- Using variables in the template
  - Create new text files based on text
  - Creation of new base64-based text files
  - Creation of new binary files based on base64
  - Using strings to modify the registry
  - Executing Powershell code from a template
  - Executing CMD code from a template

For more information, see [documentation](./docs/docs_EN.md)

## Usage examples

### The main patcher script

```
.\ReplaceHexBytesAll.ps1 -filePath "<path to file>" -patterns "<hex search pattern>/<hex replacement pattern>",
```
- `hex pattern` has no strict format.
  - There can be any number of spaces and `\x` characters between the values in the pattern - all of them will be deleted (their presence will not cause errors)
- the separator between the search and replace patterns can be one of the characters `/`,`\`,`|`
- in the `-patterns` parameter, you can pass both an array of patterns in the form of comma-separated strings, and 1 line in which the sets of patterns are separated by a comma
- you can pass the `-makeBackup` parameter and then the original file will be saved with the added extension `.bak`

Here is an example:

1. Start Powershell
2. Use `cd <path>` to go to the folder with the file `ReplaceHexBytesAll.ps1`
3. In the Powershell window, run:
```
.\ReplaceHexBytesAll.ps1 -filePath "D:\TEMP\file.exe" -patterns "48 83EC2 8BA2F 000000 488A/202 0EB1 1111 11111 111111","C42518488D4D68\90909011111175","45A8488D55A8|75EB88909090","\xAA\x7F\xBB\x08\xE3\x4D|\xBB\x90\xB1\xE8\x99\x4D" -makeBackup
```

### Wrapper script with all the data inside

The `wrappers` folder contains the `data inside` folder and the `Start.cmd` file in it
Fill in all the data inside the `Start.cmd` file and you can double-click it.
Inside the file there is a memo of what needs to be done/filled in inside the file, also it is written in more detail in [documentation](./docs/docs_EN.md)

### Wrapper script with data processing from template.txt

The `wrappers` folder contains the `data inside` folder and the files `Start.cmd`, `Parser.ps1`, `template.txt`

Necessary:
1. Fill in the form `template.txt` depending on what you need to do
2. If all 3 files are in 1 folder, just run `Start.cmd`
3. If all files are located separately, in `Start.cmd` fill in the paths to them or URL links to download them and run with a double click
4. Either run `Parser.ps1` directly through Powershell and pass it the path or a link to the template as an argument:
``
\.Parser.ps1 -templatePath"D:\path к\template.txt "
``
you can also use the second argument to pass the path to the patch script `-patcherPath "C:\path to\ReplaceHexBytesAll.ps1"` and it will take precedence over those specified in the template


## Documentation

In a separate [file](./docs/docs_EN.md)

## ToDo

- [ ] Make support for limiting substitutions of found patterns (if you need to replace not all found sequences)
- [ ] Make byte deletion support
- [ ] Do question mark support `??` in templates as in [AutoIt](https://www.autoitscript.com/autoit3/docs/functions/StringRegExp.htm)
- [ ] Make regular expression support in hex templates like in `sed` or `perl`
  - Maybe [this one](https://stackoverflow.com/a/55314611) an example will help
- [ ] Make a search function starting from a certain offset in the file or starting from a certain part of the file in %
- [ ] To read patterns from a file
- [ ] Make a check for the necessary permissions immediately after the first pattern found, and not after going through all the patterns in the main script
- [ ] Add support [globbing](https://stackoverflow.com/questions/30229465/what-is-file-globbing) in the lines with the paths to the files/folders to be found in the template file
- [ ] Add support for working with relative paths
   - This means the file paths in the template
- [ ] In the section for deleting files and folders, add support for deleting only all attached data or attached files according to some pattern (for example `\*exe`), although this is probably globbing
- [ ] It may be worth adding logic for running `.ps1` files as an administrator in the parser script
   - This means files created from the code in the template
- [ ] Find a normal way to check if you need administrator rights to delete a folder
  - The current method checks this by creating and deleting an empty file in the required folder (this is wrong from the point of view of logic and performance, but in most situations it works as it should)
- [ ] Stylize progress bars
  - When searching for Firewall rules with the specified paths to the exe, a progress bar appears showing the progress of the process. It appears at the top of the terminal simply with the name of the `Get-NetFirewallRule` method
- [ ] Add some way to set the execution order for sections in the template
  - There may be situations when custom Powershell code or CMD code from the template needs to be executed first, for example, to do something with services (delete or restart or something else)
- [ ] Add the ability to set attributes for created files
  - For example, if the created file needs to be made invisible or system-wide

## System requirements

All the code was written and tested on Windows 10 x64 22H2.

I have not checked the compatibility of the code and the Powershell functions used with previous versions. You will probably need Powershell 5.1, which comes bundled with Windows 10, to perform them.

If you are running on Windows 7, 8, 8.1, then you will probably need to install [Microsoft.NET Framework 4.8](https://support.microsoft.com/topic/microsoft-net-framework-4-8-offline-installer-for-windows-9d23f658-3b97-68ab-d013-aa3c3e7495e0) and [Powershell 5.1](https://www.microsoft.com/download/details.aspx/?id=54616) to make the code from this repository work for you.
