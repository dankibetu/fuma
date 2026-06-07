@echo off
setlocal EnableExtensions

title FUMA 7470 Excel Add-In Installer

:: ------------------------------------------------------
:: Request Administrator Rights
:: ------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
color 0E
echo.
echo ====================================================
echo      FUMA 7470 EXCEL ADD-IN INSTALLER
echo ====================================================
echo.
echo Administrator privileges are required.
echo Requesting elevation...
echo.

```
powershell -Command "Start-Process '%~f0' -Verb RunAs"
exit /b
```

)

:: ------------------------------------------------------
:: Banner
:: ------------------------------------------------------
color 1F
cls
echo.
echo ====================================================
echo      FUMA 7470 EXCEL ADD-IN INSTALLER
echo ====================================================
echo.

:: ------------------------------------------------------
:: Locate Excel
:: ------------------------------------------------------
for /f "tokens=2,*" %%A in (
'reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe" /ve ^| find "REG_SZ"'
) do set "EXCEL_EXE=%%B"

if not defined EXCEL_EXE (
color 0C
echo [ERROR] Unable to locate Microsoft Excel.
echo.
pause
exit /b 1
)

for %%F in ("%EXCEL_EXE%") do set "EXCEL_DIR=%%~dpF"

:: Remove trailing slash
if "%EXCEL_DIR:~-1%"=="" set "EXCEL_DIR=%EXCEL_DIR:~0,-1%"

:: ------------------------------------------------------
:: Define Paths
:: ------------------------------------------------------
set "SOURCE_FILE=%~dp0Fuma7470v3.xlam"
set "TARGET_DIR=%EXCEL_DIR%\Library"
set "TARGET_FILE=%TARGET_DIR%\Fuma7470v3.xlam"

color 0B
echo [INFO] Excel Executable:
echo        %EXCEL_EXE%
echo.
echo [INFO] Excel Directory:
echo        %EXCEL_DIR%
echo.
echo [INFO] Source File:
echo        %SOURCE_FILE%
echo.
echo [INFO] Target File:
echo        %TARGET_FILE%
echo.

:: ------------------------------------------------------
:: Validate Source File
:: ------------------------------------------------------
if not exist "%SOURCE_FILE%" (
color 0C
echo [ERROR] Add-in file not found.
echo.
echo Expected:
echo %SOURCE_FILE%
echo.
pause
exit /b 1
)

:: ------------------------------------------------------
:: Validate Target Directory
:: ------------------------------------------------------
if not exist "%TARGET_DIR%" (
color 0C
echo [ERROR] Excel Library directory does not exist.
echo.
echo Expected:
echo %TARGET_DIR%
echo.
pause
exit /b 1
)

:: ------------------------------------------------------
:: Copy Add-In
:: ------------------------------------------------------
color 0E
echo [ACTION] Installing add-in...
echo.

copy /Y "%SOURCE_FILE%" "%TARGET_FILE%" >nul

if errorlevel 1 (
color 0C
echo [ERROR] Installation failed.
echo.
pause
exit /b 1
)

:: ------------------------------------------------------
:: Success
:: ------------------------------------------------------
color 0A
echo [SUCCESS] Installation completed successfully.
echo.
echo The add-in has been copied to:
echo %TARGET_FILE%
echo.
echo You may now start Microsoft Excel.
echo.

pause
exit /b 0
