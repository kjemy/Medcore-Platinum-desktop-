@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ================================================================
echo MEDCORE PLATINUM DESKTOP - SYSTEM LAUNCHER
echo ================================================================

if not defined MEDCORE_DB_USER set MEDCORE_DB_USER=root
if not defined MEDCORE_DB_PASSWORD set MEDCORE_DB_PASSWORD=MedCoreLocalDb#2026
if not defined MEDCORE_DB_HOST set MEDCORE_DB_HOST=127.0.0.1
if not defined MEDCORE_DB_PORT set MEDCORE_DB_PORT=3307
if not defined MEDCORE_DB_NAME set MEDCORE_DB_NAME=medcore_local

:: ------------------------------------------------------------------
:: 1. Verify MariaDB Connectivity on port %MEDCORE_DB_PORT%
:: ------------------------------------------------------------------
echo [1/3] Verifying MariaDB connectivity on %MEDCORE_DB_HOST%:%MEDCORE_DB_PORT%...

set MARIADB_OK=0
powershell -NoProfile -Command "$conn = Get-NetTCPConnection -LocalPort %MEDCORE_DB_PORT% -State Listen -ErrorAction SilentlyContinue; if ($conn) { exit 0 } else { exit 1 }" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set MARIADB_OK=1
) else (
    echo MariaDB is not listening on port %MEDCORE_DB_PORT%.
    if exist "service\scripts\provision_mariadb.ps1" (
        echo Running service\scripts\provision_mariadb.ps1 to initialize/start MariaDB...
        powershell -NoProfile -ExecutionPolicy Bypass -File "service\scripts\provision_mariadb.ps1"
        if !ERRORLEVEL! EQU 0 (
            set MARIADB_OK=1
        )
    )
)

if "!MARIADB_OK!"=="0" (
    echo ================================================================
    echo ERROR: MariaDB is NOT listening on %MEDCORE_DB_HOST%:%MEDCORE_DB_PORT%.
    echo The Local MedCore Service requires MariaDB 11.4 to store hospital data.
    echo Please start MariaDB or execute service\scripts\provision_mariadb.ps1.
    echo System launch aborted.
    echo ================================================================
    exit /b 1
)
echo MariaDB is listening on port %MEDCORE_DB_PORT%.

:: ------------------------------------------------------------------
:: 2. Check / Start Local MedCore Service & Verify Health
:: ------------------------------------------------------------------
echo [2/3] Checking Local MedCore Service daemon...

set SERVICE_HEALTHY=0
curl -s -m 2 http://127.0.0.1:8443/api/v1/health | findstr /I "HEALTHY" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Local MedCore Service is already running and healthy on port 8443.
    set SERVICE_HEALTHY=1
) else (
    echo Starting Local MedCore Service daemon...
    pushd "%~dp0service"
    start "MedCore Local Service" /B "medcore_local_service.exe"
    popd

    echo Waiting for Local MedCore Service health probe...
    for /L %%i in (1,1,20) do (
        if !SERVICE_HEALTHY! EQU 0 (
            timeout /t 1 /nobreak >nul 2>&1
            curl -s -m 2 http://127.0.0.1:8443/api/v1/health | findstr /I "HEALTHY" >nul 2>&1
            if !ERRORLEVEL! EQU 0 (
                set SERVICE_HEALTHY=1
            )
        )
    )
)

if "!SERVICE_HEALTHY!"=="0" (
    echo ================================================================
    echo ERROR: Local MedCore Service daemon failed to become healthy.
    echo Cannot launch MedCore Desktop without a healthy backend service.
    echo Please verify MariaDB status, port 8443, or service log output.
    echo System launch aborted.
    echo ================================================================
    exit /b 1
)
echo Local MedCore Service is online and healthy.

:: ------------------------------------------------------------------
:: 3. Launch MedCore Desktop Client
:: ------------------------------------------------------------------
echo [3/3] Launching MedCore Desktop Client...
start "" "medcore_desktop.exe"
echo MedCore Platinum Desktop successfully launched.
exit /b 0
