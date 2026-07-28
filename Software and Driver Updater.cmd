@echo off

REM Quick Windows 11 Update Utility to update software and drivers without third-party utilities
REM Written by Richard Kelsch - https://github.com/richcsst/HandyWindowsUtilities
REM Distributed under the GNU GPL v 3.0 License

:: -----------------------------------------------------
:: Check for Administrative Privileges
:: -----------------------------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

set "VERSION=1.00"

:: -----------------------------------------------------
:: ANSI Escape Initialization & 16-Color Palette Setup
:: -----------------------------------------------------
for /f "tokens=1,2 delims=#" %%a in ('"prompt #$H#$E# & echo on & for %%b in (1) do rem"') do set "ESC=%%b"

:: Reset
set "RESET=%ESC%[0m"

:: 8 Standard Colors
set "BLACK=%ESC%[30m"
set "RED=%ESC%[31m"
set "GREEN=%ESC%[32m"
set "YELLOW=%ESC%[33m"
set "BLUE=%ESC%[34m"
set "MAGENTA=%ESC%[35m"
set "CYAN=%ESC%[36m"
set "WHITE=%ESC%[37m"

:: 8 Bright / High-Intensity Colors
set "BRIGHT_BLACK=%ESC%[1;30m"    :: Dark Gray / Charcoal
set "BRIGHT_RED=%ESC%[1;31m"
set "BRIGHT_GREEN=%ESC%[1;32m"
set "BRIGHT_YELLOW=%ESC%[1;33m"
set "BRIGHT_BLUE=%ESC%[1;34m"
set "BRIGHT_MAGENTA=%ESC%[1;35m"
set "BRIGHT_CYAN=%ESC%[1;36m"
set "BRIGHT_WHITE=%ESC%[1;37m"

title Windows 11 Software ^& Driver Updater

:: Clear screen once on initial launch
cls

:: -----------------------------------------------------
:: Main Menu Display Loop
:: -----------------------------------------------------
:MENU
echo.
echo %BRIGHT_BLUE%=========================================================%RESET%
echo %BRIGHT_GREEN%            WINDOWS 11 UPDATE UTILITY                   %RESET%
echo %BRIGHT_YELLOW%                    Version %VERSION%%RESET%
echo %BRIGHT_BLUE%=========================================================%RESET%
echo.
echo  %BRIGHT_YELLOW%[Software Management]%RESET%
echo    %BRIGHT_WHITE%1.%RESET% Show software in need of updating
echo    %BRIGHT_WHITE%2.%RESET% Update specific software %BRIGHT_BLACK%(prompt for name)%RESET%
echo    %BRIGHT_WHITE%3.%RESET% Update all software
echo.
echo  %BRIGHT_YELLOW%[Driver Management]%RESET%
echo    %BRIGHT_WHITE%4.%RESET% Show drivers in need of updating
echo    %BRIGHT_WHITE%5.%RESET% Update a specific driver %BRIGHT_BLACK%(prompt for name)%RESET%
echo    %BRIGHT_WHITE%6.%RESET% Update all drivers
echo.
echo  %BRIGHT_YELLOW%[System]%RESET%
echo    %BRIGHT_WHITE%7.%RESET% Exit
echo.
echo %BRIGHT_BLUE%=========================================================%RESET%
set /p choice="%BRIGHT_CYAN%Select an option (1-7): %RESET%"

:: Route user selection
if "%choice%"=="1" goto SHOW_SW
if "%choice%"=="2" goto UPD_SPEC_SW
if "%choice%"=="3" goto UPD_ALL_SW
if "%choice%"=="4" goto SHOW_DRV
if "%choice%"=="5" goto UPD_SPEC_DRV
if "%choice%"=="6" goto UPD_ALL_DRV
if "%choice%"=="7" goto EXIT

echo.
echo %BRIGHT_RED%Invalid option selected. Please try again.%RESET%
timeout /t 2 >nul
goto MENU


:: -----------------------------------------------------
:: Option 1: List outdated software packages via Winget
:: -----------------------------------------------------
:SHOW_SW
echo.
echo %BRIGHT_CYAN%[!] Querying available software updates via Winget...%RESET%
echo.
winget upgrade
echo.
pause
echo.
goto MENU


:: -----------------------------------------------------
:: Option 2: Upgrade a specific software package by name/ID
:: -----------------------------------------------------
:UPD_SPEC_SW
echo.
set /p swName="%BRIGHT_CYAN%Enter the exact or partial name/ID of the software to update: %RESET%"
if "%swName%"=="" goto MENU
echo.
echo %BRIGHT_CYAN%[!] Updating %swName%...%RESET%
winget upgrade --id "%swName%" --exact || winget upgrade "%swName%"
echo.
pause
echo.
goto MENU


:: -----------------------------------------------------
:: Option 3: Bulk upgrade all software via Winget
:: -----------------------------------------------------
:UPD_ALL_SW
echo.
echo %BRIGHT_CYAN%[!] Updating ALL software packages via Winget...%RESET%
echo.
winget upgrade --all --include-unknown
echo.
pause
echo.
goto MENU


:: -----------------------------------------------------
:: Option 4: Query Windows Update Agent COM API for drivers
:: -----------------------------------------------------
:SHOW_DRV
echo.
echo %BRIGHT_CYAN%[!] Scanning Windows Update for driver updates...%RESET%
echo %CYAN%(This may take 15-30 seconds to query Microsoft servers...)%RESET%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=New-Object -ComObject 'Microsoft.Update.Session'; $res=$s.CreateUpdateSearcher().Search('IsInstalled=0'); $drv=$res.Updates | Where-Object { $_.Type -eq 2 -or ($_.Categories | Where-Object { $_.Name -like '*Driver*' }) }; if ($drv) { $drv | Select-Object Title, DriverModel | Format-Table -AutoSize } else { Write-Host 'No pending driver updates found.' -ForegroundColor Green }"
echo.
pause
echo.
goto MENU


:: -----------------------------------------------------
:: Option 5: Search and install a specific driver
:: -----------------------------------------------------
:UPD_SPEC_DRV
echo.
set /p drvName="%BRIGHT_CYAN%Enter the name or keyword of the driver to update: %RESET%"
if "%drvName%"=="" goto MENU
echo.
echo %BRIGHT_CYAN%[!] Searching and installing matching driver update via Windows Update...%RESET%
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d='%drvName%'; $s=New-Object -ComObject 'Microsoft.Update.Session'; $res=$s.CreateUpdateSearcher().Search('IsInstalled=0'); $target=$res.Updates | Where-Object { $_.Title -like '*' + $d + '*' }; if ($target) { Write-Host 'Driver found. Downloading...' -ForegroundColor Yellow; $u=New-Object -ComObject 'Microsoft.Update.UpdateColl'; $u.Add($target[0])|Out-Null; $dl=$s.CreateUpdateDownloader(); $dl.Updates=$u; $dl.Download(); Write-Host 'Installing...' -ForegroundColor Yellow; $i=$s.CreateUpdateInstaller(); $i.Updates=$u; $i.Install(); Write-Host 'Done!' -ForegroundColor Green } else { Write-Host 'No matching driver updates found.' -ForegroundColor Red }"
echo.
pause
echo.
goto MENU


:: -----------------------------------------------------
:: Option 6: Bulk download & install all pending drivers
:: -----------------------------------------------------
:UPD_ALL_DRV
echo.
echo %BRIGHT_CYAN%[!] Scanning and installing ALL available driver updates via Windows Update...%RESET%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=New-Object -ComObject 'Microsoft.Update.Session'; $res=$s.CreateUpdateSearcher().Search('IsInstalled=0'); $drv=$res.Updates | Where-Object { $_.Type -eq 2 -or ($_.Categories | Where-Object { $_.Name -like '*Driver*' }) }; if (-not $drv) { Write-Host 'No driver updates available.' -ForegroundColor Green } else { Write-Host 'Found driver updates. Downloading...' -ForegroundColor Yellow; $u=New-Object -ComObject 'Microsoft.Update.UpdateColl'; foreach($item in $drv){$u.Add($item)|Out-Null}; $dl=$s.CreateUpdateDownloader(); $dl.Updates=$u; $dl.Download(); Write-Host 'Installing...' -ForegroundColor Yellow; $i=$s.CreateUpdateInstaller(); $i.Updates=$u; $i.Install(); Write-Host 'Driver updates installed successfully!' -ForegroundColor Green }"
echo.
pause
echo.
goto MENU


:: -----------------------------------------------------
:: Option 7: Exit Script
:: -----------------------------------------------------
:EXIT
echo.
echo %BRIGHT_YELLOW%Goodbye!%RESET%
timeout /t 1 >nul
exit /b