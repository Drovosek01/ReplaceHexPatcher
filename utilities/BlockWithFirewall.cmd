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
rem  ! ! ! IMPORTANT ! ! !
rem =====

rem [] change text "WRITE HERE NAME OF GROUP FILES ADDED TO HOSTS" in call :block_hosts
rem []    AND var count_lines_to_hosts inside block_hosts



rem =====
rem MAIN
rem =====

echo =====
echo Start main procedure
echo =====
echo.

rem IMPORTANT - change counter for count paths
set /a count_target_files=4

rem "%ProgramFiles%\path to folder"

rem If need block only 1 exe-file - write full path to file
rem If need block all exe-files in 1 folder - write full path to folder and add *.exe to end of path
rem If need block all exe-files in 1 folder with all subfolders - write full path to main folder and add *.exe to end of path
rem     and change var USE_SUBFOLDERS in function below to value TRUE
set "target_path_1=d:\TEMP\te st\*.exe"
set "target_path_2=d:\TEMP\test\test.exe"
set "target_path_3=d:\TEMP\test\sub folder\*.exe"
set "target_path_4=d:\TEMP\test\other folder\test.exe"

setlocal enableextensions enabledelayedexpansion

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


:block_targets_with_firewall
    rem Function for block all files-targets with Windows Firewall
    set /a counter=1
    :loop_block_targets_with_firewall
        if %counter% leq %count_target_files% (
            set /a counter+=1
            set "IS_DIR=FALSE"
            set "USE_SUBFOLDERS=FALSE"
            call :set_filename "!target_path_%counter%!"

            rem check if line end is symbol \
            echo !target_path_%counter%! | findstr /e "\" >nul 2>&1
            if %errorlevel% == 0 (
                set "IS_DIR=TRUE"
            )
            rem check if line ends with text *.exe
            echo !target_path_%counter%! | findstr /e "*.exe" >nul 2>&1
            if %errorlevel% == 0 (
                set "IS_DIR=TRUE"
            ) else (
                set "IS_DIR=FALSE"
            )

            call :block_with_firewall "!target_path_%counter%!" !IS_DIR! !USE_SUBFOLDERS!
            goto :loop_block_targets_with_firewall
        )
    exit /b


:block_with_firewall <path_to_file_or_folder> <is_folder_or_file> <search_in_subfolders>
    rem Function for block transferred file or files in transferred folder
    rem     using Windows Firewall
    rem === Arguments:
    rem path_to_file_or_folder - string with path to file or folder.
    rem     It file or folder will detected below in function
    rem is_folder_or_file - flag for mark if given path for file or folder
    rem     Detection 'echo %~a1 | find "d" >nul 2>&1' will not work because path with end '*.exe' it use like files
    rem     but path with end '*.exe' we need mark like folder for use it in loop
    rem search_in_subfolders - block files with selected extension also in all subfolders transferred folder TRUE or FALSE
    if %1 == "" (
        echo Not transferred files or folder for block in firewall!
        exit /b 1 
    )
    if not exist %1 (
        echo Transferred files %1% or folder for block in firewall not exist!
        exit /b 1
    )

    set "IS_DIR=%2"

    if %IS_DIR% == FALSE (
        rem It mean given path to file - so block in firewall only given file path
        call :set_filename %1
        rem remove existing firewall rules for file
        powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$existRulesForExes = Get-NetFirewallApplicationFilter | Where-Object { $_.Program -in '!file!' } | Get-NetFirewallRule; if ($existRulesForExes.Length -gt 0) { $existRulesForExes | Remove-NetFirewallRule }"
        echo A blocking rule is being added for !file!
        netsh advfirewall firewall add rule name="Blocked !file!" dir=in action=block program="!file!" enable=yes profile=any >nul 2>&1
        netsh advfirewall firewall add rule name="Blocked !file!" dir=out action=block program="!file!" enable=yes profile=any >nul 2>&1
    ) else (
        rem It mean given path to folder and we can block all .exe in this folder
        rem     or also recursive block .exe in subfolders
        if %3 == FALSE (
            rem Block in firewall all files with extension only in given folder
            for %%G in (%1) do (
                rem remove existing firewall rules for file
                powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$existRulesForExes = Get-NetFirewallApplicationFilter | Where-Object { $_.Program -in '%%G' } | Get-NetFirewallRule; if ($existRulesForExes.Length -gt 0) { $existRulesForExes | Remove-NetFirewallRule }"
                echo A blocking rule is being added for %%G
                netsh advfirewall firewall add rule name="Blocked %%G" dir=in action=block program="%%G" enable=yes profile=any >nul 2>&1
                netsh advfirewall firewall add rule name="Blocked %%G" dir=out action=block program="%%G" enable=yes profile=any >nul 2>&1
            )
        ) else (
            rem Block in firewall all files with extension in given folder and all subfolders recursive
            for /f "delims=" %%G in ('dir /b /s %1') do (
                rem remove existing firewall rules for file
                powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$existRulesForExes = Get-NetFirewallApplicationFilter | Where-Object { $_.Program -in '%%G' } | Get-NetFirewallRule; if ($existRulesForExes.Length -gt 0) { $existRulesForExes | Remove-NetFirewallRule }"
                echo A blocking rule is being added for %%G
                netsh advfirewall firewall add rule name="Blocked %%G" dir=in action=block program="%%G" enable=yes profile=any >nul 2>&1
                netsh advfirewall firewall add rule name="Blocked %%G" dir=out action=block program="%%G" enable=yes profile=any >nul 2>&1
            )
        )
    )