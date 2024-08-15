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
rem [] and write URLs for add to hosts inside function below !



rem =====
rem MAIN
rem =====

echo =====
echo Start main procedure
echo =====
echo.

setlocal enableextensions enabledelayedexpansion

rem rem Adding lines to hosts
rem first argument - modifying mode
rem    mode - FORCE (add group lines text to end hosts file)
rem       and NOTOVERWRITE (check every URL in hosts file and if URL existing and even commented it will not added)
rem second argument - just name of comment before lines with urls
rem    for example text "Adobe servers for license check" will added like # Adobe servers for license check
call :block_hosts "NOTOVERWRITE" "WRITE HERE NAME OF GROUP FILES ADDED TO HOSTS"

echo.
echo =====
echo Main procedure complete
echo =====

pause
goto :eof






rem =====
rem FUNCTIONS
rem =====

:block_hosts <mode> <name_group_lines>
    rem Add lines contains this "function" to hosts file
    rem mode - FORCE (add group lines text to end hosts file)
    rem   and NOTOVERWRITE (check every URL in hosts file and if URL existing and even commented it will not added)
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
rem IMPORTANT - NO TEXT WITH SPACES in URLs list
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
