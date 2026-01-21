# Additional information

Language: [Русский](additional_info_RU.md) | English

- [Additional information](#additional-information)
  - [Small personal conclusions](#small-personal-conclusions)
    - [About CMD](#about-cmd)
    - [Adaptive restart with admin rights (UAC) is a very big hemorrhoid](#adaptive-restart-with-admin-rights-uac-is-a-very-big-hemorrhoid)
    - [About Powershell](#about-powershell)
  - [Usefulness](#usefulness)
    - [Repositories with examples of competent scripts](#repositories-with-examples-of-competent-scripts)
    - [Implementations of hex pattern search in C#](#implementations-of-hex-pattern-search-in-c)


There will be information/notes here that are not directly related to this repository/utility/tool, but are related to the stages of development.


## Small personal conclusions

This is my first experience writing scripts in CMD (batch) and Powershell. Keep this in mind when reading my conclusions.

### About CMD

**CMD is a pain!**

And that's why:
- there are no normal functions
  - the `call` constructions must be placed at the end of the file, otherwise, when executing the code, these blocks will also be read and executed, they are not fenced in any way, they just have a "link" to them 
- there are no normal cycles
  - to make cycles, you need to make conditions in which there is a `goto` on the label outside/in front of the condition
- re-wrapping something in quotes - adds these quotes to the wrapped value and because of this, problems often arise and it has to be kept in mind
- there is no normal way to store any multiline text
  - if there are no quotes and some special characters in the multiline text, then such text can be stored in multiline form, but if there are quotes and special characters, then you have to add `echo` before each line

The main advantage that makes it worth considering writing something in CMD is that it can be launched with a 2nd click in any Windows. (Of course there is also VBS, but it is somehow less common)

### Adaptive restart with admin rights (UAC) is a very big hemorrhoid

If you make the utility "worse", then you need to request administrator rights only when you definitely can't do without them.

It is also worth remembering about the "read-only" attribute, because if the file has standard rights, then this attribute can be removed without problems without requesting administrator rights, although a test for an attempt to write will show that admin rights are needed to change the file.

Juggling these 2 items "administrator rights" and the "read-only" attribute is a rather confusing task and it adds quite a lot of additional logic to the script and reduces the readability of the code.

This is especially a problem when you need to run code from a regular Powershell script that contains multiline text.
It is much easier and more convenient to request administrator rights at the very beginning of the script execution and abort execution in their absence, but it is not a fact that these rights are really necessary to make changes.

True-the way is to request permissions if necessary.

Later, the logic of requesting administrator rights in the patcher script was changed and checking for the need to restart with a request for administrator rights is done from the very beginning, because the file may not have read permissions and in order to banally read the file and search for bytes (without replacing bytes, that is, without changing the file), you may need Administrator rights. This initial check made it possible to reduce the number of "crutches", in principle, the amount of code in the patch.

### About Powershell

Powershell has shown itself to be a good side and is a good alternative to the Unix Shell.

Naturally, comparing CMD and Powershell is stupid, these are completely different "levels", it's like comparing heaven and earth.

But it was not without drawbacks. And here they are:
- `.ps1` scripts cannot be run with a double click, unlike Unix Shell scripts on Unix systems and unlike `.cmd` or `.bat` or `.vbs` files in Windows. You will have to write a wrapper script `.cmd` to run `.ps1` if you need to run by double click.
- The typing is fictitious - the interpreter does not check the correspondence of the variable to the specified type anywhere. It looks like typing is used only in the IDE for auto add-ons.
- When working in a Powershell window/terminal, relative paths are considered relative to the path that was originally when you started Powershell, and if you navigate to another folder using the command `cd C:\path\to\file` and then you will execute some script or commands in the Powershell window using relative file paths, then they will not regarding the current directory
  - When simply launching Powershell from the search bar at the bottom left (next to the Start button), the initial path is the path to the user's folder, that is, what is in the environment variable `%USERPROFILE%`
  - When running Powershell from the search bar at the bottom left (next to the Start button) as an Administrator, the initial path is the path to the folder `C:\Windows\system32`
  - When testing wrappers like "data in template", I repeatedly ran the file [Parser.ps1](../wrappers/data%20in%20template/Parser.ps1), passing it test txt files that I created in the same folder. Sometimes I started Powershell as an administrator, went to the "data in template" folder with the command `cd "....../data in template"`, and then, as usual, executed the command `.\Parser.ps1 '.\template test.txt'`
  - But I was getting an error with the text `\ReplaceHexPatcher\wrappers\data in template\Parser.ps1 : Exception when calling "ReadAllText" with "1" arguments: "File 'C:\Windows\system32\template test.txt' not found."`
  - Although when executing the same commands in Powershell running NOT as an Administrator, everything is fine performed normally
  - What the hell, when using Powershell as an Administrator, he considers the reference point not the folder in which he is located, but the folder `C:\Windows\system32` in relative paths inside quotation marks?!
- There are no good IDEs (I haven't found any).
  - Windows Powershell ISE looks old-fashioned and clumsy, and personally I am not comfortable writing large code in it and there are not many convenient functions compared to Visual Studio Code.
  - Visual Studio Code at first seemed like a perfect alternative to "ISE" for writing Powershell code, but for some reason in VSC the auto-add-on works strangely (or does not work at all) at some points - when I start typing the words `break` or `continue`, the auto-completion does not prompt the continuation of these words, so there are others similar situations.
  - Maybe everything is perfect in the IDE from JetBrains when writing code in Powershell, but I haven't checked it.
- Returning the value to "nowhere" in the script itself - returns the value to the output stream.
  - This is a bit strange behavior, and if you don't know about it or forget to take this nuance into account, you can spend a lot of time on debag. Namely, when executing the `New-Item` and `.Add()` functions of the `ArrayList` - these functions return a value. If [do not assign](https://stackoverflow.com/a/46586504) that value - it will get into the output stream, that is, it will be mixed with what will be passed to the `Write-Host'.
- There is a strange situation in which the performance of the script drops by 3 times (it runs 3 times longer)
  - I tried to refactor one function and took the initialization of a variable with an array of bytes outside the function where this variable is used. [Code before](https://gist.github.com/Drovosek01/9d47068365ea0bce26526ee61b23be7c?permalink_comment_id=5141498#gistcomment-5141498) and [code after](https://gist.github.com/Drovosek01/9d47068365ea0bce26526ee61b23be7c?permalink_comment_id=5141499#gistcomment-5141499). And just when moving the byte array outside the variable, the script began to work 3 times slower. It's very strange.
- There is no "native" way (I did not find one) to move the file to the Trash.
  - To move a file to the Trash, you will need to use components from Visual Basic Script or JScript.
- There is no way (I have not found) to check if administrator rights are needed to delete a folder [without trying to delete it](https://qna.habr.com/q/1364540)
- The `catch {}` block after `try {}` does not catch all errors
  - For example, if there is an error when executing `New-Item` or `Remove-Item`, then without the `-ErrorAction Stop` argument, the `catch {}` block will not catch the error
- Processing (for example, searching) bytes directly by Powershell is noticeably slower than in compiled versions of the algorithms, if additional checks need to be performed after each byte found. The more constructions there are `if {...}` is executed after finding the desired byte, the slower the script runs. This is very noticeable when searching for small patterns, for example, searching for `00000090` and replacing it with `11223344` - try to do this using [strategy v4](../core/search%20strategies/SearchReplaceBytes_v4.ps1) (which does not support wildcards) and using [strategy v4.1](../core/search%20strategies/SearchReplaceBytes_v4.1.ps1) (which has wildcards support `??` and, accordingly, additional comparison conditions) and you will notice a difference in the speed of work.
  - Therefore, it is better to write the business logic of byte search and replacement in C# and automatically compile this C# code in a Powershell script and import it into a script and process it using a compiled component, rather than using Powershell forces. This will significantly improve the speed of the utility.
  - Perhaps the situation is better in Powershell Core, but in Powershell 5.1, which comes out of the box in Windows 10, the speed of the script is very different from the same when compiled in C#.
- Probably due to non-strict typing (or lack thereof), errors do not occur where they should be, for example, when trying to get an array element by an index that points outside the array. If you don't notice this (and don't write additional index verification conditions), then you get used to it, and then when porting code to languages with normal typing (for example, C#), errors occur and you can search for an error in the code for a long time. Although the direct porting from Powershell to C# was done correctly.
- In Powershell, if a function returns an array with 1 element (for example, the number -1), then Powershell automatically "unpacks" this array and returns this single element from the array, rather than an array with 1 element.
  - In Powershell 5.1 and older versions, when saving text to a `utf8` encoded file, the text was saved in `UTF-8 with BOM`
encoding - For example, this happened when executing the following code `Set-Content-Value $targetContent -Path $TargetPath -NoNewline -ErrorAction Stop -Encoding UTF8`
  - It seems that specific things are written in the code - save the file in UTF-8 encoding, why the hell does Powershell save it in UTF-8 with BOM?! And after all, there are no other utf8 variants in the `Set-Content` function/cmdlet, and it turns out that using it, the text cannot be saved to regular UTF-8 and third-party functions must be used from .Net, for example, `[System.IO.File]::WriteAllText($TargetPath, $targetContent, [System.Text.UTF8Encoding]::new($false))`
is at least critical for .lic files for RLM if .The lic files will be encoded in UTF-8 with BOM, then the data from the license file will not be read.
  - As far as I know, this was fixed starting with Powershell 6, and even if it was, why wasn't it done normally from the very beginning in Powershell, which comes out of the box in Windows 10?
- Examples from the Internet and seemingly logical code may not work. For example, such code examples:
  - `irm https://github.com/Drovosek01/ReplaceHexPatcher/raw/refs/heads/main/core/v2/ReplaceHexBytesAll.ps1 | iex`
  - `& ([scriptblock]::Create((Invoke-RestMethod -Uri "https://github.com/Drovosek01/ReplaceHexPatcher/raw/refs/heads/main/core/v2/ReplaceHexBytesAll.ps1")))`
  - `$url="https://github.com/Drovosek01/ReplaceHexPatcher/raw/refs/heads/main/core/v2/ReplaceHexBytesAll.ps1"; $f=[System.IO.Path]::GetTempFileName()+".ps1"; (irm $url)>$f; & $f`
  - As a result, as it turned out, Powershell for some reason automatically converted the encoding to `UTF-16 LE` and saved the file with this encoding (and the size of the saved file increased by 2 times), although the encoding in the original file was `UTF-8 with BOM`
- Escaping in Powershell is done "not according to the canon", that is, for escaping, you do not need to use the backslash `\`, but the apostrophe "`"
- The Powershell window when selecting files via the Tab key extension - sometimes writes the file names as they are in the Explorer, and sometimes escapes special characters
  - For example, it can escape square brackets with apostrophes `D:\TEMP\My Best App [Win] for test.7z` (it was not possible to insert apostrophes in the example here because they are not escaped in Markdown)
  - And almost all cmdlets that work with the file system, registry, etc. (for example, `Test-Path`, `Resolve-Path`, `Get-Item` and many others) have additional arguments to use the previously obtained path in the "as is" cmdlet (the `-LiteralPath` argument) or you can use the resulting path as a regular expression (when you just pass a string without arguments) , and then square brackets will be treated as a regular expression command and the path will not be found
  - But C# functions (for example, opening a stream file using `[System.IO.File]::Open()`) do not support escaping from Powershell, and escaping must be removed when passing the path to these functions
  - And also, when comparing strings with the `-eq` operator, square brackets and other special characters are considered as part of the string, and not as part of the regular
  - **Therefore, in order to cover all use cases of paths** passed to the script as arguments, it is necessary to remove all escaping from the resulting path and in all cmdlets to which such a path is passed, do not forget to add the `-LiteralPath` argument. Or, on the contrary, save and use the escaped path, and in conditions and C# functions, pre-process the string with the path, removing the escaping from it.
  - This is a noticeable hemorrhoid and adds an additional "juggling layer"
- Assigning attributes to a file may not work if it is done on pure Powershell, while on .NET - it works
  - When executing the code `Set-ItemProperty -Path "$backupAbsoluteName" -Name Attributes -Value ($fileAttributesForBackup -bxor [System.IO.FileAttributes]::ReadOnly)` I was getting an error `Set-ItemProperty : The attribute cannot be set because attributes are not supported. Only the following attributes can be set: Archive, Hidden, Normal, ReadOnly, or System.`, but the file had attributes at that time `Archive, NoScrubData`
  - When I started using the implementation on instead of that code .NET - `[System.IO.File]::SetAttributes($backupAbsoluteName, ($fileAttributesForBackup -bxor [System.IO.FileAttributes]::ReadOnly))`, then the error stopped appearing
- You can't move a group of selected files to the Powershell window so that the paths to all these files are written
in the window
  - I'm used to macOS, if I select several objects (files, folders) in the Finder and move the selected one to the Terminal window, then the paths to all the objects that will be selected will be written in it.
  - In Windows, when moving a group of objects (files and folders) from the Explorer to the Powershell window, we only get the path to the object that the cursor was hovering over when trying to drag the selected group.
  - It turns out that if I want to calculate the CRC32 hash sum for 10 files from one folder using the script [CRC32.ps1](../utilities/CRC32.ps1) from the folder with utilities, then each file of the 10 necessary files should be moved to the Powershell window individually as a script argument. It's incredibly inconvenient!
- You can't delete a folder if you run Powershell from it.
  - If you open a folder in the Explorer and write powershell in the path bar and press Enter to open a Powershell window with the specified path to the current folder, and then in the Powershell window go to any other folder at higher levels, let's say to the root of the C drive, and then try to delete the folder that was opened initially, the File Explorer will give an error stating that this folder is in use.
  - It turns out that when we launch Powershell from the Explorer window while in a folder, Powershell somehow locks this folder wherever we "go" inside the Powershell window. Even if you delete everything from the original folder, you will not be able to delete the folder itself until the Powershell process is completed.


## Usefulness

### Repositories with examples of competent scripts

Powershell Scripts
- https://github.com/KurtDeGreeff/PlayPowershell

CMD/Bat scripts
- https://github.com/npocmaka/batch.scripts
- https://github.com/corpnewt/ProperTree/blob/master/ProperTree.bat

### Implementations of hex pattern search in C#

As separate functions
- https://www.cyberforum.ru/csharp-net/thread1946246.html
- https://stackoverflow.com/questions/4859023/find-an-array-byte-inside-another-array
- https://stackoverflow.com/questions/16252518/boyer-moore-horspool-algorithm-for-all-matches-find-byte-array-inside-byte-arra
- https://forum.cheatengine.org/viewtopic.php?p=5726618
  - https://stackoverflow.com/questions/44314769/using-boyer-moore-algorithms-in-64-bit-processes
- https://stackoverflow.com/questions/28329974/byte-pattern-finding-needle-in-haystack-wildcard-mask
- https://stackoverflow.com/a/50625581/8744985

As part of utilities
- https://github.com/jjxtra/HexAndReplace/
- https://github.com/Haapavuo/HexPatcher/
