@echo off

rem =====
rem Check and run script as Administrator
rem =====

reg query "HKU\S-1-5-19\Environment" >nul 2>&1
if %errorlevel% NEQ 0 (
    powershell.exe -ExecutionPolicy Bypass -noprofile "Start-Process '%~f0' -Verb RunAs"
    exit
)



rem =====
rem Init variables
rem =====

set "patcher_name=ReplaceHexBytesAll.ps1"
set "patcher_url_if_need=https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/core/ReplaceHexBytesAll.ps1"
set "temp_filename_uniq="
set "patcher_path="

rem =====
rem files + patterns

set /a count_target_files=1

rem f1 mean "file/target 1"

set "target_path_1=d:\TEMP\test\test.exe"
rem "%ProgramFiles%\CLO Standalone OnlineAuth"

set "original_f1_1=FFE1488B4B70E851AA0000488BCBE8A9"
set "patched_f1_1=9090488B4B70E851AA0000488BCBE8A9"

set "original_f1_2=0F8434020000488D5530488B8E800000"
set "patched_f1_2=E93502000090488D5530488B8E800000"

set "original_f1_3=32DB488D4C2438FF15A46EA70390488D"
set "patched_f1_3=B301488D4C2438FF15A46EA70390488D"

set "original_f1_4=E8A62600000FB6D8488D4C2440FF1578"
set "patched_f1_4=EB032600000FB6D8488D4C2440FF1578"

set /a count_patches_f1=4

rem endline is CRLF or LF
rem create mode is FORCE (overwrite) or NOTOVERWRITE
set "file_text_path_1=D:\TEMP\test\test2\all.lic"
set "endline_text_file_1=LF"
set "create_mode_text_file_1=FORCE"

set /a count_text_files=1



rem =====
rem  ! ! ! IMPORTANT ! ! !
rem =====


rem Check list before run script:
rem 
rem [] Check variables patcher_name and patcher_url_if_need and modify if need
rem 
rem [] if need patch multiple files add variables target_path_2, target_path_3 etc
rem []    AND chage var count_target_files
rem 
rem [] if need patch multiple files add variables original_f2_1, patched_f2_1... original_f3_1, patched_f3_1 etc
rem []    AND add vriables count_patches_f2, count_patches_f3 etc
rem 
rem [] if no need create text files - comment call :create_all_text_files in MAIN section
rem [] if need make 1 text file - modify function :create_text_file_2 and :create_all_text_files and var file_text_path_1
rem [] if need make multiple text files add functions create_text_file_2, create_text_file_3 etc in FUNCTIONS sections
rem []    AND add vriables endline_text_file_2, create_mode_text_file_2 etc
rem []    AND change var count_text_files
rem 
rem [] change text "WRITE HERE NAME OF GROUP FILES ADDED TO HOSTS" in call :block_hosts
rem []    AND var count_lines_to_hosts inside block_hosts
rem [] if no need modify hosts file - comment call :block_hosts in MAIN section
rem 
rem [] if no need block patched files with firewall - comment call :block_targets_with_firewall in MAIN section




rem =====
rem MAIN
rem =====

echo =====
echo Start main procedure
echo =====
echo.

setlocal enableextensions enabledelayedexpansion

rem rem Patching files-targets
call :prepare_all_targets
call :check_or_get_patcher
call :patch_all_files

rem rem Making text files
call :create_all_text_files

rem rem Adding lines to hosts
call :block_hosts "NOTOVERWRITE" "WRITE HERE NAME OF GROUP FILES ADDED TO HOSTS"

rem rem Block files in Windows Firewall
call :block_targets_with_firewall

echo.
echo =====
echo Main procedure complete
echo =====

pause
goto :eof




rem =====
rem FUNCTIONS
rem =====

:patch_all_files
    rem Applying patch patterns for all files-targets
    set /a counter=1
    :loop_applying_patches
        if %counter% leq %count_target_files% (
            set /a counter+=1
            call :apply_patch %patcher_path% %counter% !count_patches_f%counter%!
            goto :loop_applying_patches
        )
    exit /b


:apply_patch <path_patcher> <file_number> <count_patches>
    rem To form patches as command arguments for the powershell script
    rem and apply the patch to the transferred file
    if not exist %1 (
        echo Patcher not found!
        exit /b 1
    )
    if %2 leq 0 (
        echo Target file not found!
        exit /b 1
    )
    if %3 leq 0 (
        echo Not transferred patches for target!
        exit /b 1
    )
    set "path_patcher=%1"
    set /a count_patches=%3
    set /a file_number=%2
    set /a counter=1
    set "patterns_str="
    :loop_concat_patterns
        rem Combine all the patterns into one line for use as an argument in powershell
        if %counter% leq !count_patches_f%file_number%! (
            set /a counter+=1
            set "patterns_str=%patterns_str%\"!original_f%file_number%_%counter%!/!patched_f%file_number%_%counter%!\","
            goto :loop_concat_patterns
        )
        rem remove last symbol (comma)
        set "patterns_str=%patterns_str:~0,-1%"
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& %path_patcher% -filePath  \"!target_path_%file_number%!\" -patterns %patterns_str%"
    exit /b


:check_or_get_patcher
    rem If the powershell script file is in the folder with the current script, use it
    rem otherwise download the script and use the downloaded one
    if exist ".\%patcher_name%" (
        call :set_filename ".\%patcher_name%"
        set "patcher_path=!file!"
        exit /b
    ) else if exist "..\..\core\%patcher_name%" (
        rem patcher path in repository
        call :set_filename "..\..\core\%patcher_name%"
        set "patcher_path=!file!"
        exit /b
    ) else (
        call :get_temp_filename_uniq
        set "patcher_path=!temp_filename_uniq!"
        powershell -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('%patcher_url_if_need%','!patcher_path!')"
    )
    exit /b


:get_temp_filename_uniq
    rem Get a unique full file name in the temporary folder
    set "temp_filename_uniq=%temp%\patcher-%random%.ps1"
    if exist %temp_filename_uniq% goto :get_temp_filename_uniq
    exit /b


:set_filename <full_path_file>
    rem Getting the file name from EXISTING file
    rem which transfered as function argument
    if %1 == "" (
        echo Not transferred var for extract filename!
        exit /b 1
    )
    set "file=%~f1"
    set "filepath=%~dp1"
    set "filename=%~nx1"
    set "fileextension=%~x1"
    exit /b


:prepare_all_targets
    rem We check all the target files and prepare them for the patch
    set /a counter=1
    :loop_prepare_targets
        if %counter% leq %count_target_files% (
            set /a counter+=1
            call :prepare_file "!target_path_%counter%!"
            goto :loop_prepare_targets
        )
     exit /b


:prepare_file <full_path_file>
    rem Check for the file in the specified path
    rem and kill the process of executing this file
    if not exist %1 (
        echo Not transferred path for target for prepare
        exit /b 1
    )
    if not exist %1 cd /d %1
    if not exist %1 cd /d "%~dp0"
    if not exist %1 (
        echo Error, %1 not found!  
        pause
        exit /b 1
    )
    call :set_filename %1
    @taskkill /im "%filename%" >nul 2>&1
    exit /b


rem =====
rem Text files functions
rem =====

:create_all_text_files
    rem Creating all files from vars and data inside script
    set /a counter=1
    :loop_creating_text_files
        if %counter% leq %count_text_files% (
            set /a counter+=1
            call :create_text_file_%counter% "!file_text_path_%counter%!" "!endline_text_file_%counter%!" "!create_mode_text_file_%counter%!"
            goto :loop_creating_text_files
        )
    exit /b


:create_text_file_1 <path_file> <end_line> <create_mode>
    rem Create text file with transfered arguments
    rem and with content file stored in this "funcion"
    if %1 == "" (
        echo Not transferred path for text file
        exit /b 1
    )
    if %2 == "" (
        echo Not transferred end_line for text file
        exit /b 1
    )
    if %3 == "" (
        echo Not transferred create_mode for text file
        exit /b 1
    )

    if %3 == "NOTOVERWRITE" (
        if exist %1 (
            echo Text file exist and create mode NOTOVERWRITE
            echo so we need touch exist file
            exit /b
        )
    ) else (
        del %1 >nul 2>&1
        mkdir %1
        rmdir %1
        echo. > %1
rem I think this best way for write text in file
rem if text contain quotations
(
echo LICENSE productgroup product 2099.99 permanent uncounted hostid=ANY
echo   issued=1-oct-2023 _ck=bc1e94b45e sig="60P0450BS5WA0G7VJPP96BBAAKB36J
echo   B97TSF8MG22GD0ABHFK09Q0WPNFF1543YXM0RSYN6JD4"
echo LICENSE productgroup product 2099.99 permanent uncounted hostid=ANY
echo   issued=1-oct-2023 _ck=c51e947507 sig="60P0451JSHX4N85D89MA8R0D8UFTNE
echo   NCAHCS5K822HNR6ACG1VVK6T6UXVQ9C894YY2MFGTBEC"
echo LICENSE productgroup product 2099.99 permanent uncounted hostid=ANY
echo   issued=1-oct-2023 _ck=321e9478d7 sig="60PG4580G7JA027QRQ9HEV39P7553R
echo   GBS7FK6R5M08A0QJ59X2V3VEER4TA348065RQ967481KFG"
) > %1
    )
    rem change end of lines it created text file
    rem About conver CRLF and LF on Powershell - https://stackoverflow.com/a/48919146
    if %2 == "CRLF" (
        powershell -ExecutionPolicy Bypass -NoProfile -command "((Get-Content '%1') -join \"`r`n\") + \"`r`n\" | Set-Content -NoNewline '%1'"
    ) else (
        powershell -ExecutionPolicy Bypass -NoProfile -command "((Get-Content '%1') -join \"`n\") + \"`n\" | Set-Content -NoNewline '%1'"
    )
    exit /b


rem =====
rem Block connections functions
rem =====

:block_hosts <mode> <name_group_lines>
    rem Add lines contains this "function" to hosts file
    rem mode - FORCE (add group lines text to end hosts file) and NOTOVERWRITE (check every URL in hosts file and if URL existing and even commented it will not added)
    rem name_group_lines - comment with text before added lines
    if "%OS%"=="Windows_NT" (
        set hosts_file=%windir%\system32\drivers\etc\hosts
    ) else (
        set hosts_file=%windir%\hosts
    )
    if %1 == "" (
        echo Not transferred mode for adding lines to hosts file!
        exit /b 1
    )
    if %2 == "" (
        echo Not transferred name_group_lines!
        exit /b 1
    )
    attrib -h -r -s %hosts_file%
    rem IMPORTANT CHANGE THIS VARIABLE with change count lines in loop below
    set /a count_lines_to_hosts=4
echo. >>%hosts_file%
echo # %2 >>%hosts_file%
for %%A IN (

site.com
anothersite.com
etc.another.site.net
on.more.time

) do (
    set /a count_lines_to_hosts-=1
    set "one_line=%%A"
    if %1 == "FORCE" (
        echo 0.0.0.0 %%A >> %hosts_file%
    ) else (
        set "found_string_in_hosts="
        rem check if URL exist in hosts file 
        for /f "delims=" %%B in ('powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& Select-String -Path %hosts_file% -Pattern %%A"') do set "found_string_in_hosts=%%B"
        if "!found_string_in_hosts!" == "" (
           echo 0.0.0.0 %%A >> %hosts_file%
        )
        if !count_lines_to_hosts! EQU 0 (
            rem if all line exist in host just remove line with comment contain name_group_lines because we added in before start loop
            powershell -ExecutionPolicy Bypass -c "&{$a = gc '%hosts_file%' -enc OEM;$a[0..($a.count-3)] |out-file '%hosts_file%' -enc OEM}"
        )
    )
)
    attrib +r %hosts_file%
    ipconfig /flushdns >nul 2>&1
    exit /b


:block_targets_with_firewall
    rem Function for block all files-targets with Windows Firewall
    set /a counter=1
    :loop_block_targets_with_firewall
        if %counter% leq %count_target_files% (
            set /a counter+=1
            call :set_filename "!target_path_%counter%!"
            call :block_with_firewall "!target_path_%counter%!" "!fileextension!" "FALSE"
            goto :loop_block_targets_with_firewall
        )
    exit /b


:block_with_firewall <path_to_file_or_folder> <files_extensions_for_block> <search_in_subfolders>
    rem Function for block transferred file or files in transferred folder
    rem     using Windows Firewall
    rem === Arguments:
    rem path_to_file_or_folder - string with path to file or folder.
    rem     It file or folder will detected below in function
    rem files_extensions_for_block - use only if transferred path to folder. Usually EXE or DLL
    rem search_in_subfolders - block files with selected extension also in all subfolders transferred folder TRUE or FALSE
    if %1 == "" (
        echo Not transferred files or folder for block in firewall!
        exit /b 1 
    )
    if not exist %1 (
        echo Transferred files or folder for block in firewall not exist!
        exit /b 1
    )

    set "IS_DIR="
    echo %~a1 | find "d" >nul 2>&1
    if %errorlevel% NEQ 0 (
        rem Block in firewall only given file path
        call :set_filename %1
        set "IS_DIR=FALSE"
        rem remove existing firewall rules for file
        powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$existRulesForExes = Get-NetFirewallApplicationFilter | Where-Object { $_.Program -in '!file!'' } | Get-NetFirewallRule; if ($existRulesForExes.Length -gt 0) { $existRulesForExes | Remove-NetFirewallRule }"
        netsh advfirewall firewall add rule name="Blocked !file!" dir=in action=block program="!file!" enable=yes profile=any >nul 2>&1
        netsh advfirewall firewall add rule name="Blocked !file!" dir=out action=block program="!file!" enable=yes profile=any >nul 2>&1
    ) else (
        set "IS_DIR=TRUE"
        if %3 == "FALSE" (
            rem Block in firewall all files with extension only in given folder
            for %%G in (%1*%2) do (
                rem remove existing firewall rules for file
                powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$existRulesForExes = Get-NetFirewallApplicationFilter | Where-Object { $_.Program -in '%%G'' } | Get-NetFirewallRule; if ($existRulesForExes.Length -gt 0) { $existRulesForExes | Remove-NetFirewallRule }"
                netsh advfirewall firewall add rule name="Blocked %%G" dir=in action=block program="%%G" enable=yes profile=any >nul 2>&1
                netsh advfirewall firewall add rule name="Blocked %%G" dir=out action=block program="%%G" enable=yes profile=any >nul 2>&1
            )
        ) else (
            rem Block in firewall all files with extension in given folder and all subfolders recursive
            for /r %%G in (%1*%2) do (
                rem remove existing firewall rules for file
                powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$existRulesForExes = Get-NetFirewallApplicationFilter | Where-Object { $_.Program -in '%%G'' } | Get-NetFirewallRule; if ($existRulesForExes.Length -gt 0) { $existRulesForExes | Remove-NetFirewallRule }"
                netsh advfirewall firewall add rule name="Blocked %%G" dir=in action=block program="%%G" enable=yes profile=any >nul 2>&1
                netsh advfirewall firewall add rule name="Blocked %%G" dir=out action=block program="%%G" enable=yes profile=any >nul 2>&1
            )
        )
    )