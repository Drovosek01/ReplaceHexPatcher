@echo off

rem =====
rem Check and run script as Administrator
rem =====

reg query "HKU\S-1-5-19\Environment" >nul 2>&1
if %errorlevel% NEQ 0 (
    powershell.exe -noprofile "Start-Process '%~f0' -Verb RunAs"
    exit
)



rem =====
rem Init variables
rem =====

set "temp_filename_uniq="

set "parser_name=Parser.ps1"
set "parser_url_if_need=https://gist.github.com/Drovosek01/9d47068365ea0bce26526ee61b23be7c/raw/581aa5312b0f99745ca55c2646d31990a93e2ee3/ReplaceHexBytesAll.ps1"
set "parser_path="

set "template_name=template.txt"
set "template_url_if_need=https://gist.github.com/Drovosek01/9d47068365ea0bce26526ee61b23be7c/raw/581aa5312b0f99745ca55c2646d31990a93e2ee3/ReplaceHexBytesAll.ps1"
set "template_path="




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


:check_or_get_parser
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
        powershell -Command "(New-Object System.Net.WebClient).DownloadFile('%parser_url_if_need%','!parser_path!')"
    )
    exit /b


:check_or_get_template
    rem If the template.txt file is in the folder with the current script, use it
    rem otherwise download the script and use the downloaded one
    if exist ".\%template_name%" (
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
        powershell -Command "(New-Object System.Net.WebClient).DownloadFile('%template_url_if_need%','!template_path!')"
    )
    exit /b


:parse_template
    rem Apply parser script and transfer template to it
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& %parser_path% -templatePath \"!template_path!\""
    exit /b