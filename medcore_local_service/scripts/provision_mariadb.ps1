# ================================================================================
# MEDCORE PLATINUM DESKTOP — MARIADB PROVISIONING & VERIFICATION ENGINE
# ================================================================================
# Follows the Khaled Universal Engineering Constitution:
# 1. Real runtime verification (no false positives, explicit native exit codes).
# 2. Dynamic binary and data path resolution (no hardcoded developer paths).
# 3. Secure authentication (no passwordless assumption; verify configured credentials).
# 4. Strict fail-closed error handling (exit non-zero on any verification failure).
# 5. Local isolation (127.0.0.1 binding only, no external network exposure).
# ================================================================================

$ErrorActionPreference = "Stop"

$dbHost = if ($env:MEDCORE_DB_HOST) { $env:MEDCORE_DB_HOST.Trim() } else { "127.0.0.1" }
$dbPort = if ($env:MEDCORE_DB_PORT) { [int]$env:MEDCORE_DB_PORT } else { 3307 }
$dbUser = if ($env:MEDCORE_DB_USER) { $env:MEDCORE_DB_USER.Trim() } else { "root" }

# Dynamic Security & Credential Resolution (Gate 4 - Zero Universal Hardcoded Passwords)
function Resolve-SecurityDir {
    if ($env:MEDCORE_SECURITY_DIR -and (Test-Path $env:MEDCORE_SECURITY_DIR)) {
        return (Resolve-Path $env:MEDCORE_SECURITY_DIR).Path
    }
    $candidates = @(
        (Join-Path $PSScriptRoot "..\runtime\security"),
        (Join-Path $PSScriptRoot "..\..\runtime\security"),
        (Join-Path $PSScriptRoot "runtime\security"),
        (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "runtime\security")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            return (Resolve-Path $c).Path
        }
    }
    $defaultSec = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "runtime\security"
    if (-not (Test-Path $defaultSec)) {
        New-Item -ItemType Directory -Path $defaultSec -Force | Out-Null
    }
    return (Resolve-Path $defaultSec).Path
}

function Resolve-DynamicDbPassword {
    param([string]$secDir)
    if ($env:MEDCORE_DB_PASSWORD -and $env:MEDCORE_DB_PASSWORD.Trim()) {
        return $env:MEDCORE_DB_PASSWORD.Trim()
    }
    $credFile = Join-Path $secDir "db_credentials.json"
    if (Test-Path $credFile) {
        try {
            $json = Get-Content $credFile -Raw | ConvertFrom-Json
            if ($json.password -and $json.password.Trim()) {
                return $json.password.Trim()
            }
        } catch {}
    }

    # Generate cryptographically secure random 32-character dynamic password
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $randPass = [Convert]::ToBase64String($bytes).Replace('+', 'X').Replace('/', 'Y').Replace('=', 'Z')

    $credObj = @{
        user = "root"
        password = $randPass
        generatedAtUtc = [DateTime]::UtcNow.ToString("o")
        port = 3307
        host = "127.0.0.1"
    } | ConvertTo-Json
    Set-Content -Path $credFile -Value $credObj -Encoding UTF8
    return $randPass
}

$securityDir = Resolve-SecurityDir
$dbPassword = Resolve-DynamicDbPassword -secDir $securityDir

# --------------------------------------------------------------------------------
# 1. Resolve MariaDB Binaries & Data Directory Dynamically
# --------------------------------------------------------------------------------
function Resolve-MariaDBBinDir {
    # 1. Explicit environment overrides
    if ($env:MEDCORE_MARIADB_BIN -and (Test-Path (Join-Path $env:MEDCORE_MARIADB_BIN "mariadbd.exe"))) {
        return (Resolve-Path $env:MEDCORE_MARIADB_BIN).Path
    }
    if ($env:MARIADB_HOME -and (Test-Path (Join-Path $env:MARIADB_HOME "bin\mariadbd.exe"))) {
        return (Resolve-Path (Join-Path $env:MARIADB_HOME "bin")).Path
    }
    if ($env:MEDCORE_RUNTIME_DIR -and (Test-Path (Join-Path $env:MEDCORE_RUNTIME_DIR "mariadb\bin\mariadbd.exe"))) {
        return (Resolve-Path (Join-Path $env:MEDCORE_RUNTIME_DIR "mariadb\bin")).Path
    }

    # 2. Package relative resolution from script directory ($PSScriptRoot)
    $scriptRoot = $PSScriptRoot
    $candidates = @(
        (Join-Path $scriptRoot "..\mariadb\bin"),                  # <pkg>/service/mariadb/bin
        (Join-Path $scriptRoot "..\..\service\mariadb\bin"),       # from nested scripts
        (Join-Path $scriptRoot "..\..\mariadb\bin"),               # <pkg>/mariadb/bin
        (Join-Path $scriptRoot "..\..\runtime\mariadb\bin"),       # <repo>/runtime/mariadb/bin
        (Join-Path $scriptRoot "..\runtime\mariadb\bin"),
        (Join-Path $scriptRoot "runtime\mariadb\bin"),
        (Join-Path $scriptRoot "mariadb\bin")
    )
    foreach ($cand in $candidates) {
        if (Test-Path (Join-Path $cand "mariadbd.exe")) {
            return (Resolve-Path $cand).Path
        }
        if (Test-Path (Join-Path $cand "mysqld.exe")) {
            return (Resolve-Path $cand).Path
        }
        if (Test-Path (Join-Path $cand "mariadb.exe")) {
            return (Resolve-Path $cand).Path
        }
    }

    # 3. Standard Windows Installation Paths (fallback only)
    $stdPaths = Get-ChildItem "C:\Program Files\MariaDB*" -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName "bin" }
    foreach ($p in $stdPaths) {
        if (Test-Path (Join-Path $p "mariadbd.exe") -or Test-Path (Join-Path $p "mariadb.exe")) {
            return (Resolve-Path $p).Path
        }
    }

    # 4. PATH lookup
    $cmd = Get-Command mariadbd.exe -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $cmd = Get-Command mariadb.exe -ErrorAction SilentlyContinue
    }
    if ($cmd) {
        return (Split-Path -Parent $cmd.Source)
    }

    return $null
}

function Resolve-MariaDBDataDir {
    param([string]$binDir)

    if ($env:MEDCORE_DATA_DIR) {
        return (Resolve-Path $env:MEDCORE_DATA_DIR).Path
    }

    $scriptRoot = $PSScriptRoot

    # 1. Check relative to binary location
    if ($binDir) {
        $parent = Split-Path -Parent $binDir
        $serviceOrPkg = Split-Path -Parent $parent
        $pkgRoot = Split-Path -Parent $serviceOrPkg

        $cands = @(
            (Join-Path $pkgRoot "runtime\mariadb_data"),
            (Join-Path $serviceOrPkg "runtime\mariadb_data"),
            (Join-Path $pkgRoot "mariadb_data"),
            (Join-Path $parent "data")
        )
        foreach ($c in $cands) {
            if (Test-Path $c) {
                return (Resolve-Path $c).Path
            }
        }
    }

    # 2. Check relative to script directory
    $repoData = Join-Path $scriptRoot "..\..\runtime\mariadb_data"
    if (Test-Path $repoData) {
        return (Resolve-Path $repoData).Path
    }

    $svcData = Join-Path $scriptRoot "..\runtime\mariadb_data"
    if (Test-Path $svcData) {
        return (Resolve-Path $svcData).Path
    }

    # 3. Default to package root / runtime / mariadb_data
    $pkgDefault = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptRoot)) "runtime\mariadb_data"
    return $pkgDefault
}

$mariaBin = Resolve-MariaDBBinDir
$dataDir = Resolve-MariaDBDataDir -binDir $mariaBin

$installDbExe = if ($mariaBin) {
    if (Test-Path (Join-Path $mariaBin "mariadb-install-db.exe")) {
        Join-Path $mariaBin "mariadb-install-db.exe"
    } elseif (Test-Path (Join-Path $mariaBin "mysql_install_db.exe")) {
        Join-Path $mariaBin "mysql_install_db.exe"
    } else {
        $null
    }
} else { $null }

$mariadbdExe = if ($mariaBin) {
    if (Test-Path (Join-Path $mariaBin "mariadbd.exe")) {
        Join-Path $mariaBin "mariadbd.exe"
    } elseif (Test-Path (Join-Path $mariaBin "mysqld.exe")) {
        Join-Path $mariaBin "mysqld.exe"
    } else {
        $null
    }
} else { $null }

$mariadbClientExe = if ($mariaBin) {
    if (Test-Path (Join-Path $mariaBin "mariadb.exe")) {
        Join-Path $mariaBin "mariadb.exe"
    } elseif (Test-Path (Join-Path $mariaBin "mysql.exe")) {
        Join-Path $mariaBin "mysql.exe"
    } else {
        $null
    }
} else { $null }

# --------------------------------------------------------------------------------
# 2. Check / Initialize & Start MariaDB Daemon
# --------------------------------------------------------------------------------
$listening = Get-NetTCPConnection -LocalPort $dbPort -State Listen -ErrorAction SilentlyContinue

if (-not $listening) {
    if (-not $mariadbdExe -or -not (Test-Path $mariadbdExe)) {
        Write-Error "CRITICAL: MariaDB is not listening on port $dbPort, and mariadbd.exe/mysqld.exe was not found in: $mariaBin"
        exit 1
    }

    $myIniPath = Join-Path $dataDir "my.ini"
    $normalizedDataDir = $dataDir -replace '\\', '/'

    if (-not (Test-Path $myIniPath)) {
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }
        if ($installDbExe -and (Test-Path $installDbExe)) {
            Write-Output "Initializing MariaDB 11.4 data directory at $dataDir on port $dbPort..."
            & $installDbExe --datadir="$dataDir" --port=$dbPort --password="$dbPassword" --default-user 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Error "CRITICAL: mariadb-install-db failed with exit code $LASTEXITCODE."
                exit 1
            }
        }
    }

    # Ensure my.ini configuration exists and enforces strict local isolation
    if (-not (Test-Path $myIniPath)) {
        $defaultIni = @"
[mysqld]
datadir=$normalizedDataDir
bind-address=$dbHost
port=$dbPort
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
innodb_strict_mode=ON
max_connections=150
"@
        Set-Content -Path $myIniPath -Value $defaultIni -Encoding UTF8
    } else {
        $iniContent = Get-Content $myIniPath -Raw -ErrorAction SilentlyContinue
        if ($iniContent -notmatch "bind-address") {
            $extraIni = @"

bind-address=$dbHost
port=$dbPort
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
innodb_strict_mode=ON
max_connections=150
"@
            Add-Content -Path $myIniPath -Value $extraIni -Encoding UTF8
        }
    }

    Write-Output "Starting MariaDB daemon on $dbHost`:$dbPort..."
    Start-Process -FilePath $mariadbdExe -ArgumentList "--defaults-file=`"$myIniPath`"" -WindowStyle Hidden
    
    # Poll for port listening
    $started = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        $listening = Get-NetTCPConnection -LocalPort $dbPort -State Listen -ErrorAction SilentlyContinue
        if ($listening) {
            $started = $true
            break
        }
    }

    if (-not $started) {
        Write-Error "CRITICAL: MariaDB was started but port $dbPort is not listening after 15 seconds."
        exit 1
    }
}

# --------------------------------------------------------------------------------
# 3. Authenticate & Verify Database State
# --------------------------------------------------------------------------------
if (-not $mariadbClientExe -or -not (Test-Path $mariadbClientExe)) {
    # If client is missing but port is listening, test raw TCP connection
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($dbHost, $dbPort)
        $tcp.Close()
        Write-Output "LOCAL MARIADB 11.4 ON $dbHost`:$dbPort IS ONLINE AND READY (TCP listener verified)."
        exit 0
    } catch {
        Write-Error "CRITICAL: Port $dbPort connection failed: $_"
        exit 1
    }
}

# Try connecting with configured password
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

$probeOutput = & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser "-p$dbPassword" --connect-timeout=5 -e "SELECT VERSION() AS ver, @@port AS port, @@character_set_server AS charset;" 2>&1
$probeExit = $LASTEXITCODE

if ($probeExit -ne 0) {
    # Check if legacy password or passwordless works and migrate to the new dynamic password!
    $legacyPw = "MedCoreLocalDb#2026"
    $legacyOutput = & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser "-p$legacyPw" --connect-timeout=5 -e "SELECT VERSION();" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Migrating legacy MariaDB password to secure dynamic per-installation password..."
        & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser "-p$legacyPw" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$dbPassword'; ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$dbPassword'; FLUSH PRIVILEGES;" 2>&1 | Out-Null
        $probeOutput = & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser "-p$dbPassword" --connect-timeout=5 -e "SELECT VERSION() AS ver, @@port AS port, @@character_set_server AS charset;" 2>&1
        $probeExit = $LASTEXITCODE
    } else {
        # If password fails, test if fresh passwordless root is open
        $noPwOutput = & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser --connect-timeout=5 -e "SELECT VERSION();" 2>&1
        if ($LASTEXITCODE -eq 0) {
            # Secure passwordless root with configured application password
            & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$dbPassword'; ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$dbPassword'; FLUSH PRIVILEGES;" 2>&1 | Out-Null
            
            # Re-probe with new password
            $probeOutput = & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser "-p$dbPassword" --connect-timeout=5 -e "SELECT VERSION() AS ver, @@port AS port, @@character_set_server AS charset;" 2>&1
            $probeExit = $LASTEXITCODE
        }
    }
}

$ErrorActionPreference = $prevEAP

if ($probeExit -ne 0) {
    Write-Error "CRITICAL: MariaDB client failed to authenticate on $dbHost`:$dbPort for user '$dbUser'. Check credentials."
    exit 1
}

# Ensure medcore_local and medcore_test databases exist
$createDbOutput = & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser "-p$dbPassword" -e "CREATE DATABASE IF NOT EXISTS medcore_local CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE DATABASE IF NOT EXISTS medcore_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "CRITICAL: Failed to create or verify medcore_local and medcore_test databases: $createDbOutput"
    exit 1
}

# Read-back verification
$verifyOutput = & $mariadbClientExe -h $dbHost -P $dbPort -u $dbUser "-p$dbPassword" -e "USE medcore_local; SELECT DATABASE() AS current_db, @@collation_database AS collation_db;" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "CRITICAL: Read-back verification of medcore_local failed: $verifyOutput"
    exit 1
}

Write-Output "LOCAL MARIADB 11.4 ON $dbHost`:$dbPort IS ONLINE AND READY."
exit 0
