@echo off

REM Quick Windows 11 Update Utility to update software and drivers without third-party utilities
REM Written by Richard Kelsch - https://github.com/richcsst/HandyWindowsUtilities
REM Distributed under the GNU GPL v 3.0 License

:: -----------------------------------------------------
:: Check for Administrative Privileges
:: Re-launches via PowerShell with RunAs if non-elevated
:: -----------------------------------------------------
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

title Windows 11 Software ^& Driver Updater - Written by Richard Kelsch

:: -----------------------------------------------------
:: Main Menu Display Loop
:: -----------------------------------------------------
:MENU
cls
echo ===================================================
echo           WINDOWS 11 UPDATE UTILITY
echo ===================================================
echo.
echo  1. Show software in need of updating
echo  2. Show drivers in need of updating
echo  3. Update specific software (prompt for name)
echo  4. Update a specific driver (prompt for name)
echo  5. Update all software
echo  6. Update all drivers
echo  7. Exit
echo.
echo ===================================================
set /p choice="Select an option (1-7): "

:: Route user selection to appropriate label
if "%choice%"=="1" goto SHOW_SW
if "%choice%"=="2" goto SHOW_DRV
if "%choice%"=="3" goto UPD_SPEC_SW
if "%choice%"=="4" goto UPD_SPEC_DRV
if "%choice%"=="5" goto UPD_ALL_SW
if "%choice%"=="6" goto UPD_ALL_DRV
if "%choice%"=="7" goto EXIT

:: Fallback for invalid input
echo.
echo Invalid option selected. Please try again.
timeout /t 2 >nul
goto MENU


:: -----------------------------------------------------
:: Option 1: List outdated software packages via Winget
:: -----------------------------------------------------
:SHOW_SW
cls
echo [!] Querying available software updates via Winget...
echo.
winget upgrade
echo.
pause
goto MENU


:: --------------------------------------------------------
:: Option 2: Query Windows Update Agent COM API for drivers
:: --------------------------------------------------------
:SHOW_DRV
cls
echo [!] Scanning Windows Update for driver updates...
echo (This may take 15-30 seconds to query Microsoft servers...)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=New-Object -ComObject 'Microsoft.Update.Session'; $res=$s.CreateUpdateSearcher().Search('IsInstalled=0'); $drv=$res.Updates | Where-Object { $_.Type -eq 2 -or ($_.Categories | Where-Object { $_.Name -like '*Driver*' }) }; if ($drv) { $drv | Select-Object Title, DriverModel | Format-Table -AutoSize } else { Write-Host 'No pending driver updates found.' -ForegroundColor Green }"
echo.
pause
goto MENU


:: --------------------------------------------------------
:: Option 3: Upgrade a specific software package by name/ID
:: --------------------------------------------------------
:UPD_SPEC_SW
cls
echo.
set /p swName="Enter the exact or partial name/ID of the software to update: "
if "%swName%"=="" goto MENU
echo.
echo [!] Updating %swName%...
winget upgrade --id "%swName%" --exact || winget upgrade "%swName%"
echo.
pause
goto MENU


:: -----------------------------------------------------
:: Option 4: Search and install a specific driver
:: -----------------------------------------------------
:UPD_SPEC_DRV
cls
echo.
set /p drvName="Enter the name or keyword of the driver to update: "
if "%drvName%"=="" goto MENU
echo.
echo [!] Searching and installing matching driver update via Windows Update...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d='%drvName%'; $s=New-Object -ComObject 'Microsoft.Update.Session'; $res=$s.CreateUpdateSearcher().Search('IsInstalled=0'); $target=$res.Updates | Where-Object { $_.Title -like '*' + $d + '*' }; if ($target) { Write-Host 'Driver found. Downloading...' -ForegroundColor Yellow; $u=New-Object -ComObject 'Microsoft.Update.UpdateColl'; $u.Add($target[0])|Out-Null; $dl=$s.CreateUpdateDownloader(); $dl.Updates=$u; $dl.Download(); Write-Host 'Installing...' -ForegroundColor Yellow; $i=$s.CreateUpdateInstaller(); $i.Updates=$u; $i.Install(); Write-Host 'Done!' -ForegroundColor Green } else { Write-Host 'No matching driver updates found.' -ForegroundColor Red }"
echo.
pause
goto MENU


:: -----------------------------------------------------
:: Option 5: Bulk upgrade all software via Winget
:: -----------------------------------------------------
:UPD_ALL_SW
cls
echo [!] Updating ALL software packages via Winget...
echo.
winget upgrade --all --include-unknown
echo.
pause
goto MENU


:: -----------------------------------------------------
:: Option 6: Bulk download & install all pending drivers
:: -----------------------------------------------------
:UPD_ALL_DRV
cls
echo [!] Scanning and installing ALL available driver updates via Windows Update...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=New-Object -ComObject 'Microsoft.Update.Session'; $res=$s.CreateUpdateSearcher().Search('IsInstalled=0'); $drv=$res.Updates | Where-Object { $_.Type -eq 2 -or ($_.Categories | Where-Object { $_.Name -like '*Driver*' }) }; if (-not $drv) { Write-Host 'No driver updates available.' -ForegroundColor Green } else { Write-Host 'Found driver updates. Downloading...' -ForegroundColor Yellow; $u=New-Object -ComObject 'Microsoft.Update.UpdateColl'; foreach($item in $drv){$u.Add($item)|Out-Null}; $dl=$s.CreateUpdateDownloader(); $dl.Updates=$u; $dl.Download(); Write-Host 'Installing...' -ForegroundColor Yellow; $i=$s.CreateUpdateInstaller(); $i.Updates=$u; $i.Install(); Write-Host 'Driver updates installed successfully!' -ForegroundColor Green }"
echo.
pause
goto MENU


:: -----------------------------------------------------
:: Option 7: Exit Script
:: -----------------------------------------------------
:EXIT
cls
echo Goodbye!
timeout /t 1 >nul
exit /b
