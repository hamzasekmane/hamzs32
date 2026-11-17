@echo off
REM =====================================================================
REM QuantumMarketEngine (QME) - MetaEditor Automated Build Script
REM =====================================================================
SETLOCAL ENABLEDELAYEDEXPANSION

SET "ME_PATH="
IF EXIST "C:\Program Files\MetaTrader 5\metaeditor64.exe" (
    SET "ME_PATH=C:\Program Files\MetaTrader 5\metaeditor64.exe"
) ELSE IF EXIST "C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe" (
    SET "ME_PATH=C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe"
) ELSE IF EXIST "%LOCALAPPDATA%\Programs\MetaTrader 5\metaeditor64.exe" (
    SET "ME_PATH=%LOCALAPPDATA%\Programs\MetaTrader 5\metaeditor64.exe"
)

IF "%ME_PATH%"=="" (
    echo [ERROR] metaeditor64.exe was not found in standard paths.
    echo Please compile manually in MetaEditor (press F4 in MT5, then F7).
    pause
    exit /b 1
)

echo [INFO] Found MetaEditor at: "%ME_PATH%"
SET "BASE_DIR=%~dp0MQL5"

echo [BUILD] Compiling QME_Main.mq5...
"%ME_PATH%" /compile:"%BASE_DIR%\Experts\QME\QME_Main.mq5" /log:"%~dp0build_ea.log"

echo [BUILD] Compiling QME_RunTests.mq5...
"%ME_PATH%" /compile:"%BASE_DIR%\Scripts\QME\QME_RunTests.mq5" /log:"%~dp0build_tests.log"

echo [BUILD COMPLETE] Review build_ea.log and build_tests.log for details.
IF EXIST "%~dp0build_ea.log" type "%~dp0build_ea.log"
pause
