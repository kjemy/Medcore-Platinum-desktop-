@echo off
setlocal
cd /d "%~dp0"
echo ================================================================
echo MEDCORE PLATINUM DESKTOP - SYSTEM LAUNCHER
echo ================================================================

if not defined MEDCORE_DB_USER set MEDCORE_DB_USER=root
if not defined MEDCORE_DB_PASSWORD set MEDCORE_DB_PASSWORD=MedCoreLocalDb#2026
if not defined MEDCORE_DB_HOST set MEDCORE_DB_HOST=127.0.0.1
if not defined MEDCORE_DB_PORT set MEDCORE_DB_PORT=3307
if not defined MEDCORE_DB_NAME set MEDCORE_DB_NAME=medcore_local

echo Checking Local MedCore Service...
curl -s -m 2 http://127.0.0.1:8443/api/v1/health >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Local MedCore Service is already running on port 8443.
) else (
    echo Starting Local MedCore Service daemon...
    start "MedCore Local Service" /B "service\medcore_local_service.exe"
    timeout /t 2 /nobreak >nul
)

echo Launching MedCore Desktop Client...
start "" "medcore_desktop.exe"
