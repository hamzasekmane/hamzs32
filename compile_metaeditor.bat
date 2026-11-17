@echo off
REM =====================================================================
REM QuantumMarketEngine (QME) - MetaEditor Indicator and Test Build
REM =====================================================================
SETLOCAL

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
    echo Run this script on Windows with MetaTrader 5 installed.
    exit /b 1
)

SET "BASE_DIR=%~dp0MQL5"
echo [BUILD] Compiling QME indicator...
"%ME_PATH%" /compile:"%BASE_DIR%\Indicators\QME\QME_Indicator.mq5" /log:"%~dp0build_indicator.log"
IF ERRORLEVEL 1 exit /b 1
powershell -NoProfile -Command "$log=Get-Content -Raw -Encoding Unicode '%~dp0build_indicator.log'; if($log -notmatch 'Result: 0 errors, 0 warnings') { exit 1 }"
IF ERRORLEVEL 1 (
    echo [FAIL] Indicator compile log does not report zero errors and zero warnings.
    exit /b 1
)

echo [BUILD] Compiling QME feature test script...
"%ME_PATH%" /compile:"%BASE_DIR%\Scripts\QME\QME_RunTests.mq5" /log:"%~dp0build_tests.log"
IF ERRORLEVEL 1 exit /b 1
powershell -NoProfile -Command "$log=Get-Content -Raw -Encoding Unicode '%~dp0build_tests.log'; if($log -notmatch 'Result: 0 errors, 0 warnings') { exit 1 }"
IF ERRORLEVEL 1 (
    echo [FAIL] Test compile log does not report zero errors and zero warnings.
    exit /b 1
)

echo [BUILD COMPLETE] Indicator and native tests compiled with zero errors and warnings.
ENDLOCAL
