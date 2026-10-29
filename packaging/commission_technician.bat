@echo off
setlocal
cd /d "%~dp0"
pushd "%~dp0service"
if "%~1"=="" (
    "medcore_commission.exe" status
) else (
    "medcore_commission.exe" %*
)
popd
pause
