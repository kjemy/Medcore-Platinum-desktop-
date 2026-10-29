@echo off
setlocal
cd /d "%~dp0"
if "%~1"=="" (
    "service\medcore_commission.exe" status
) else (
    "service\medcore_commission.exe" %*
)
pause
