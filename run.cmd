@echo off
title Setting up Fuma

setlocal enabledelayedexpansion

Echo Checking Python and Pip Installation

python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python is not installed. Please install Python and ensure it's added to your PATH.
    pause
    exit /b
) else (
    @REM Get the full version string (e.g., Python 3.13.0)
    for /f "tokens=2 delims= " %%v in ('python --version') do set PYTHON_VERSION=%%v
    @REM Extract the major version (first number) from the version string
    for /f "tokens=1 delims=." %%v in ("!PYTHON_VERSION!") do set PYTHON_MAJOR_VERSION=%%v
    @REM Echo the full Python version
    echo Python version: !PYTHON_VERSION!
    @REM Check if Python version is 3 or higher
    if !PYTHON_MAJOR_VERSION! LSS 3 (
        echo Python version is less than 3. Please install Python 3 or higher.
        pause
        exit /b
    )
)

@REM Check for pip installation
pip --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Pip is not installed or not found in PATH.
    echo Please install pip to proceed. You can do this by running the following command in Python:
    echo python -m ensurepip --upgrade
    pause
    exit /b
) else (
    for /f "tokens=2,* delims= " %%v in ('pip --version') do set PIP_VERSION=%%v
    echo Pip version: !PIP_VERSION!
)

@REM Set environment variable names and initial values
set "fuma_env=FUMA_DIRECTORY"
set "jdev_env=JDEV_USER_HOME"
set "fuma_dir=%cd%"
set "env_db_user=APPS"

@REM Check and set up FUMA environment if not already defined
echo -------------------------------------------------------------------------
echo setting environment Variables

setx %fuma_env% "%fuma_dir%" >nul 2>&1
setx FUMA "%FUMA_DIRECTORY%\Fuma.py -f" >nul 2>&1
setx FUMA_SECURE "%%FUMA_DIRECTORY%%\secure\credentials.py" >nul 2>&1

if defined %fuma_env% (
    echo %fuma_env%: %fuma_dir%
) else (
    echo %fuma_env%: Undefined
)

if defined %jdev_env% (
    echo %jdev_env%: %JDEV_USER_HOME%
) else (
    echo %jdev_env%: Undefined
)

if defined JAVA_HOME (
    echo JAVA_HOME: %JAVA_HOME%
) else (
    echo JAVA_HOME: Undefined
)
echo -------------------------------------------------------------------------
echo installing dependencies

@REM color 0A

for /f "tokens=1" %%p in ('type "%fuma_dir%\_others\requirements.txt"') do (
    pip show %%p >nul 2>&1
    if %errorlevel% equ 0 (
        @REM color 0A
        echo + [PASS] %%p
    ) else (
        @REM color 0C
        echo - [FAIL] %%p.
        @REM color 07
    )
)

@REM color 
echo.
echo Fuma is now installed in your system
pause
exit /b
