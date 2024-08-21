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

set "temp_filename_uniq="

set "parser_name=Parser.ps1"
set "parser_url_if_need=https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data in template/Parser.ps1"
rem WRITE FULL PATH or URL HERE !!!!!! vvv
set "parser_path="

set "template_name=template.txt"
set "template_url_if_need=https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/wrappers/data in template/template.txt"
rem WRITE FULL PATH or URL HERE !!!!!! vvv
set "template_path="

set "patcher_path=https://github.com/Drovosek01/ReplaceHexPatcher/raw/main/core/ReplaceHexBytesAll.ps1"

set "current_dir=%~dp0"




rem =====
rem MAIN
rem =====

echo =====
echo Start main procedure
echo =====
echo.

setlocal enableextensions enabledelayedexpansion

call :check_or_get_parser
call :check_or_get_template
call :parse_template


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


:get_temp_filename_uniq <extension>
    rem Get a unique full file name in the temporary folder
    set "temp_filename_uniq=%temp%\replacehex-%random%%1"
    echo "temp_filename_uniq %temp_filename_uniq%"
    if exist %temp_filename_uniq% goto :get_temp_filename_uniq
    exit /b


:check_or_get_parser
    rem If the powershell script file is in the folder with the current script, use it
    rem otherwise download the script and use the downloaded one
    if defined parser_path (
        exit /b
    ) else if exist "%current_dir%%parser_name%" (
        call :set_filename "%current_dir%%parser_name%"
        set "parser_path=!file!"
        exit /b
    ) else (
        call :get_temp_filename_uniq .ps1
        set "parser_path=!temp_filename_uniq!"
        powershell -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('%parser_url_if_need%','!parser_path!')"
    )
    exit /b


:check_or_get_template
    rem If the template.txt file is in the folder with the current script, use it
    rem otherwise download the script and use the downloaded one
    if defined template_path (
        exit /b
    ) else if exist "%current_dir%%template_name%" (
        call :set_filename "%current_dir%%template_name%"
        set "template_path=!file!"
        exit /b
    ) else (
        call :get_temp_filename_uniq .txt
        set "template_path=!temp_filename_uniq!"
        powershell -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('%template_url_if_need%','!template_path!')"
    )
    exit /b


:parse_template
    rem Apply parser script and transfer template to it
    if defined patcher_path (
        powershell -noexit -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%parser_path%" "-templatePath" "!template_path!" "-patcherPath" "%patcher_path%"
    ) else (
        powershell -noexit -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%parser_path%" "-templatePath" "!template_path!"
    )
    exit /b