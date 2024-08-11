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
set "parser_url_if_need=https://gist.aga.com/Drovosek01/9d47068365ea0bce26526ee61b23be7c/raw/581aa5312b0f99745ca55c2646d31990a93e2ee3/ReplaceHexBytesAll.ps1"
set "parser_path= WRITE FULL PATH HERE !!!!!!"

set "template_name=template.txt"
set "template_url_if_need=https://gist.aga.com/Drovosek01/9d47068365ea0bce26526ee61b23be7c/raw/581aa5312b0f99745ca55c2646d31990a93e2ee3/ReplaceHexBytesAll.ps1"
set "template_path=WRITE FULL PATH HERE !!!!!!"




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


:get_temp_filename_uniq
    rem Get a unique full file name in the temporary folder
    set "temp_filename_uniq=%temp%\patcher-%random%.ps1"
    if exist %temp_filename_uniq% goto :get_temp_filename_uniq
    exit /b


:check_or_get_parser
    rem If the powershell script file is in the folder with the current script, use it
    rem otherwise download the script and use the downloaded one
    if defined parser_path (
        exit /b
    ) else if exist ".\%parser_name%" (
        call :set_filename ".\%parser_name%"
        set "parser_path=!file!"
        exit /b
    ) else if exist "..\..\core\%parser_name%" (
        rem patcher path in repository
        call :set_filename "..\..\core\%parser_name%"
        set "parser_path=!file!"
        exit /b
    ) else (
        call :get_temp_filename_uniq
        set "parser_path=!temp_filename_uniq!"
        powershell -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('%parser_url_if_need%','!parser_path!')"
    )
    exit /b


:check_or_get_template
    rem If the template.txt file is in the folder with the current script, use it
    rem otherwise download the script and use the downloaded one
    if defined template_path (
        exit /b
    ) else if exist ".\%template_name%" (
        call :set_filename ".\%template_name%"
        set "template_path=!file!"
        exit /b
    ) else if exist "..\..\core\%template_name%" (
        rem patcher path in repository
        call :set_filename "..\..\core\%template_name%"
        set "template_path=!file!"
        exit /b
    ) else (
        call :get_temp_filename_uniq
        set "template_path=!temp_filename_uniq!"
        powershell -ExecutionPolicy Bypass -Command "(New-Object System.Net.WebClient).DownloadFile('%template_url_if_need%','!template_path!')"
    )
    exit /b


:parse_template
    rem Apply parser script and transfer template to it
    powershell -noexit -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%parser_path%" "-templatePath" "!template_path!"
    exit /b