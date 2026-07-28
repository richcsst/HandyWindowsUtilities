:: -----------------------------------------------------
:: Option 8: Self-Update Script from GitHub
:: -----------------------------------------------------
:UPDATE_SCRIPT
cls
echo %BRIGHT_CYAN%[!] Checking GitHub repository for updates...%RESET%
echo %BRIGHT_BLACK%Repository: https://github.com/richcsst/HandyWindowsUtilities%RESET%
echo.

set "TEMP_FILE=%TEMP%\updater_new.cmd"

:: Download raw script cleanly using PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$url = [Uri]::EscapeUriString('https://raw.githubusercontent.com/richcsst/HandyWindowsUtilities/main/Software and Driver Updater.cmd'); [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile($url, '%TEMP_FILE%')" >nul 2>&1

if not exist "%TEMP_FILE%" (
    echo %BRIGHT_RED%[!] Error: Failed to download update from GitHub.%RESET%
    echo %BRIGHT_RED%Check your internet connection or repository branch name.%RESET%
    echo.
    pause
    goto MENU
)

:: Extract REMOTE_VERSION from the downloaded temporary script
set "REMOTE_VERSION="
for /f "tokens=2 delims==" %%V in ('findstr /I /C:"set \"VERSION=" "%TEMP_FILE%"') do set "REMOTE_VERSION=%%~V"

if "%REMOTE_VERSION%"=="" (
    echo %BRIGHT_RED%[!] Error: Unable to verify version from downloaded file.%RESET%
    del /f /q "%TEMP_FILE%" >nul 2>&1
    echo.
    pause
    goto MENU
)

if "%REMOTE_VERSION%"=="%VERSION%" (
    echo %BRIGHT_GREEN%[✓] You are already running the latest version (v%VERSION%).%RESET%
    del /f /q "%TEMP_FILE%" >nul 2>&1
    echo.
    pause
    goto MENU
)

echo %BRIGHT_YELLOW%[!] New version found: v%REMOTE_VERSION% (Current: v%VERSION%)%RESET%
echo %BRIGHT_CYAN%[!] Replacing script with updated version...%RESET%

:: Hand off replacement and relaunch to a detached subshell
start "" cmd /c "timeout /t 1 >nul & move /y "%TEMP_FILE%" "%~f0" >nul & start "" cmd /c ""%~f0"""
exit /b
