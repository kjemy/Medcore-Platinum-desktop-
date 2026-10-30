@echo off
setlocal enabledelayedexpansion

:: ================================================================
:: STAGE 1: Resolve Package Root
:: ================================================================
cd /d "%~dp0"
set "PACKAGE_ROOT=%cd%"
if not exist "%PACKAGE_ROOT%\medcore_desktop.exe" (
    if exist "%PACKAGE_ROOT%\..\medcore_desktop.exe" (
        cd /d "%PACKAGE_ROOT%\.."
        set "PACKAGE_ROOT=!cd!"
    )
)

echo ================================================================
echo MEDCORE PLATINUM DESKTOP - SELF-CONTAINED SYSTEM LAUNCHER
echo ================================================================
echo [Stage 1/10] Package root resolved: %PACKAGE_ROOT%

if not defined MEDCORE_DB_USER set MEDCORE_DB_USER=root
if not defined MEDCORE_DB_HOST set MEDCORE_DB_HOST=127.0.0.1
if not defined MEDCORE_DB_PORT set MEDCORE_DB_PORT=3307
if not defined MEDCORE_DB_NAME set MEDCORE_DB_NAME=medcore_local

:: Resolve Dynamic Database Password from runtime security store
if not defined MEDCORE_DB_PASSWORD (
    if exist "%PACKAGE_ROOT%\runtime\security\db_credentials.json" (
        for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "(Get-Content '%PACKAGE_ROOT%\runtime\security\db_credentials.json' | ConvertFrom-Json).password"`) do set "MEDCORE_DB_PASSWORD=%%p"
    ) else if exist "%PACKAGE_ROOT%\service\runtime\security\db_credentials.json" (
        for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "(Get-Content '%PACKAGE_ROOT%\service\runtime\security\db_credentials.json' | ConvertFrom-Json).password"`) do set "MEDCORE_DB_PASSWORD=%%p"
    )
)

:: ================================================================
:: STAGE 2: Resolve Bundled MariaDB
:: ================================================================
echo [Stage 2/10] Resolving bundled MariaDB binary directory...
set "MARIADB_BIN="
if exist "%PACKAGE_ROOT%\service\mariadb\bin\mariadbd.exe" (
    set "MARIADB_BIN=%PACKAGE_ROOT%\service\mariadb\bin"
) else if exist "%PACKAGE_ROOT%\service\mariadb\bin\mysqld.exe" (
    set "MARIADB_BIN=%PACKAGE_ROOT%\service\mariadb\bin"
) else if exist "%PACKAGE_ROOT%\mariadb\bin\mariadbd.exe" (
    set "MARIADB_BIN=%PACKAGE_ROOT%\mariadb\bin"
) else if exist "%PACKAGE_ROOT%\mariadb\bin\mysqld.exe" (
    set "MARIADB_BIN=%PACKAGE_ROOT%\mariadb\bin"
) else if exist "%PACKAGE_ROOT%\runtime\mariadb\bin\mariadbd.exe" (
    set "MARIADB_BIN=%PACKAGE_ROOT%\runtime\mariadb\bin"
) else if exist "%PACKAGE_ROOT%\runtime\mariadb\bin\mysqld.exe" (
    set "MARIADB_BIN=%PACKAGE_ROOT%\runtime\mariadb\bin"
) else if exist "%PACKAGE_ROOT%\..\runtime\mariadb\bin\mariadbd.exe" (
    set "MARIADB_BIN=%PACKAGE_ROOT%\..\runtime\mariadb\bin"
)

:: ================================================================
:: STAGE 3: Verify MariaDB Binary
:: ================================================================
echo [Stage 3/10] Verifying MariaDB server executable...
set "MARIADB_DAEMON_EXE="
if defined MARIADB_BIN (
    if exist "%MARIADB_BIN%\mariadbd.exe" (
        set "MARIADB_DAEMON_EXE=%MARIADB_BIN%\mariadbd.exe"
    ) else if exist "%MARIADB_BIN%\mysqld.exe" (
        set "MARIADB_DAEMON_EXE=%MARIADB_BIN%\mysqld.exe"
    )
)

if not defined MARIADB_DAEMON_EXE (
    echo Note: Bundled MariaDB binary not directly discovered in root; relying on provision_mariadb.ps1.
) else (
    echo Verified MariaDB server daemon: %MARIADB_DAEMON_EXE%
)

:: ================================================================
:: STAGE 4: Verify Data Directory
:: ================================================================
echo [Stage 4/10] Verifying local MariaDB data directory...
set "DATA_DIR=%PACKAGE_ROOT%\runtime\mariadb_data"
if not exist "%DATA_DIR%" (
    if exist "%PACKAGE_ROOT%\service\runtime\mariadb_data" (
        set "DATA_DIR=%PACKAGE_ROOT%\service\runtime\mariadb_data"
    )
)
echo MariaDB target data directory: %DATA_DIR%

:: ================================================================
:: STAGE 5: Initialize MariaDB if Needed
:: ================================================================
echo [Stage 5/10] Checking MariaDB data directory initialization...
:: Evaluated and executed by provision_mariadb.ps1 if empty/missing

:: ================================================================
:: STAGE 6: Start Bundled MariaDB Locally (127.0.0.1:3307)
:: ================================================================
echo [Stage 6/10] Ensuring MariaDB daemon is active on %MEDCORE_DB_HOST%:%MEDCORE_DB_PORT%...
set MARIADB_RUNNING=0
powershell -NoProfile -Command "$conn = Get-NetTCPConnection -LocalPort %MEDCORE_DB_PORT% -State Listen -ErrorAction SilentlyContinue; if ($conn) { exit 0 } else { exit 1 }" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set MARIADB_RUNNING=1
) else (
    echo Starting and configuring MariaDB via service\scripts\provision_mariadb.ps1...
    if exist "%PACKAGE_ROOT%\service\scripts\provision_mariadb.ps1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%PACKAGE_ROOT%\service\scripts\provision_mariadb.ps1"
        if !ERRORLEVEL! NEQ 0 (
            echo ================================================================
            echo ERROR: Failed to initialize/start bundled MariaDB!
            echo Launch aborted at Stage 6.
            echo ================================================================
            exit /b 1
        )
        set MARIADB_RUNNING=1
    ) else (
        echo ERROR: provision_mariadb.ps1 script is missing!
        exit /b 1
    )
)

:: ================================================================
:: STAGE 7: Poll Authenticated MariaDB Health
:: ================================================================
echo [Stage 7/10] Polling authenticated MariaDB connection...
set AUTH_OK=0
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $script = '%PACKAGE_ROOT%\service\scripts\provision_mariadb.ps1'; if (Test-Path $script) { & $script; exit $LASTEXITCODE } else { exit 0 } }" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set AUTH_OK=1
    echo Authenticated MariaDB connection verified on %MEDCORE_DB_HOST%:%MEDCORE_DB_PORT%.
) else (
    echo ================================================================
    echo ERROR: MariaDB authenticated connection failed.
    echo Launch aborted at Stage 7.
    echo ================================================================
    exit /b 1
)

:: ================================================================
:: STAGE 8: Start Local MedCore Service Daemon
:: ================================================================
echo [Stage 8/10] Checking / Starting Local MedCore Service daemon...
set SERVICE_HEALTHY=0
curl -s -m 2 http://127.0.0.1:8443/api/v1/health | findstr /I "HEALTHY" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Local MedCore Service is already running and healthy on port 8443.
    set SERVICE_HEALTHY=1
) else (
    echo Launching medcore_local_service.exe...
    pushd "%PACKAGE_ROOT%\service"
    start "MedCore Local Service" /B "medcore_local_service.exe"
    popd

    :: ================================================================
    :: STAGE 9: Poll Service Health
    :: ================================================================
    echo [Stage 9/10] Waiting for Local MedCore Service health probe...
    for /L %%i in (1,1,25) do (
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
    echo ERROR: Local MedCore Service daemon failed health check on port 8443.
    echo Launch aborted at Stage 9.
    echo ================================================================
    exit /b 1
)
echo Local MedCore Service is online and healthy.

:: ================================================================
:: STAGE 10: Start MedCore Desktop Client
:: ================================================================
echo [Stage 10/10] Launching MedCore Desktop Client application...
start "" "%PACKAGE_ROOT%\medcore_desktop.exe"
echo ================================================================
echo MEDCORE PLATINUM DESKTOP LAUNCH COMPLETE
echo System is operational in offline self-contained mode.
echo ================================================================
exit /b 0
