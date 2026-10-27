$ErrorActionPreference = "Stop"
$runtimeDir = "C:\Users\hp\Desktop\project 4\runtime"
$mariaBin = Join-Path $runtimeDir "mariadb\bin"
$dataDir = Join-Path $runtimeDir "mariadb_data"

$installDbExe = Join-Path $mariaBin "mariadb-install-db.exe"
$mariadbdExe = Join-Path $mariaBin "mariadbd.exe"
$mariadbClientExe = Join-Path $mariaBin "mariadb.exe"

if (-not (Test-Path (Join-Path $dataDir "my.ini"))) {
    if (Test-Path $dataDir) {
        Remove-Item -Recurse -Force $dataDir
    }
    Write-Output "Initializing MariaDB 11.4 data directory at $dataDir on port 3307..."
    & $installDbExe --datadir="$dataDir" --port=3307 --default-user
}

# Ensure strict InnoDB and UTF8MB4 settings in my.ini
$myIniPath = Join-Path $dataDir "my.ini"
$iniContent = Get-Content $myIniPath -Raw
if ($iniContent -notmatch "bind-address") {
    $extraIni = @"

bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
innodb_strict_mode=ON
max_connections=150
"@
    Add-Content -Path $myIniPath -Value $extraIni -Encoding UTF8
}

# Check if mariadbd is already listening on 3307
$listening = Get-NetTCPConnection -LocalPort 3307 -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
    Write-Output "Starting mariadbd.exe daemon on 127.0.0.1:3307..."
    Start-Process -FilePath $mariadbdExe -ArgumentList "--defaults-file=`"$myIniPath`"" -WindowStyle Hidden
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        $listening = Get-NetTCPConnection -LocalPort 3307 -State Listen -ErrorAction SilentlyContinue
        if ($listening) { break }
    }
}

& $mariadbClientExe -h 127.0.0.1 -P 3307 -u root -e "SELECT VERSION() AS mariadb_version, @@port AS port, @@character_set_server AS charset;"
& $mariadbClientExe -h 127.0.0.1 -P 3307 -u root -e "CREATE DATABASE IF NOT EXISTS medcore_local CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE DATABASE IF NOT EXISTS medcore_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
Write-Output "LOCAL MARIADB 11.4 ON 127.0.0.1:3307 IS ONLINE AND READY."
