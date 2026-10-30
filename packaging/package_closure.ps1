$ErrorActionPreference = 'Stop'
$builtCommit = '95a2ca8b163ee4c97577bc5f0ede92ef7511d642'
$shortSha = '95a2ca8'
$artifactBase = "medcore-platinum-windows-main-commercial-closure-$shortSha"
$stagingDir = "package_staging/$artifactBase"

Write-Host "Creating staging directory $stagingDir..."
if (Test-Path $stagingDir) { Remove-Item -Path $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

# 1. Desktop Client Binaries & Assets
$clientSource = "medcore_desktop/build/windows/x64/runner/Release"
Copy-Item -Path "$clientSource/*" -Destination $stagingDir -Recurse -Force

# 2. Local Backend Service & Tools
$serviceStaging = "$stagingDir/service"
New-Item -ItemType Directory -Path "$serviceStaging/sql/migrations" -Force | Out-Null
New-Item -ItemType Directory -Path "$serviceStaging/scripts" -Force | Out-Null
New-Item -ItemType Directory -Path "$serviceStaging/runtime/security" -Force | Out-Null

Copy-Item -Path "medcore_local_service/build/bin/medcore_local_service.exe" -Destination "$serviceStaging/" -Force
Copy-Item -Path "medcore_local_service/build/bin/medcore_commission.exe" -Destination "$serviceStaging/" -Force
Copy-Item -Path "medcore_local_service/sql/migrations/*" -Destination "$serviceStaging/sql/migrations/" -Force
Copy-Item -Path "medcore_local_service/scripts/*" -Destination "$serviceStaging/scripts/" -Force

# 3. Bundled MariaDB 11.4 Distribution
$mariadbStaging = "$serviceStaging/mariadb"
New-Item -ItemType Directory -Path "$mariadbStaging/licenses" -Force | Out-Null
$mariadbSource = "runtime/mariadb"
Write-Host "Copying MariaDB components from $mariadbSource to $mariadbStaging..."
Copy-Item -Path "$mariadbSource/bin" -Destination "$mariadbStaging/bin" -Recurse -Force
Copy-Item -Path "$mariadbSource/lib" -Destination "$mariadbStaging/lib" -Recurse -Force
Copy-Item -Path "$mariadbSource/share" -Destination "$mariadbStaging/share" -Recurse -Force

# Licenses (GPLv2 compliance)
if (Test-Path "$mariadbSource/COPYING") {
    Copy-Item -Path "$mariadbSource/COPYING" -Destination "$mariadbStaging/licenses/COPYING" -Force
    Copy-Item -Path "$mariadbSource/COPYING" -Destination "$mariadbStaging/COPYING" -Force
}

# 4. Packaging Helpers, Documentation & Runtime Directories
New-Item -ItemType Directory -Path "$stagingDir/packaging" -Force | Out-Null
New-Item -ItemType Directory -Path "$stagingDir/runtime/mariadb_data" -Force | Out-Null
New-Item -ItemType Directory -Path "$stagingDir/runtime/security" -Force | Out-Null

Copy-Item -Path "packaging/start_medcore_system.bat" -Destination "$stagingDir/" -Force
Copy-Item -Path "packaging/commission_technician.bat" -Destination "$stagingDir/" -Force
Copy-Item -Path "packaging/start_medcore_system.bat" -Destination "$stagingDir/packaging/" -Force
Copy-Item -Path "packaging/commission_technician.bat" -Destination "$stagingDir/packaging/" -Force
Copy-Item -Path "packaging/README_INSTALL.txt" -Destination "$stagingDir/" -Force

# Calculate Hashes
$desktopExeHash = (Get-FileHash -Path "$stagingDir/medcore_desktop.exe" -Algorithm SHA256).Hash
$serviceExeHash = (Get-FileHash -Path "$serviceStaging/medcore_local_service.exe" -Algorithm SHA256).Hash
$commissionExeHash = (Get-FileHash -Path "$serviceStaging/medcore_commission.exe" -Algorithm SHA256).Hash
$mariadbdHash = (Get-FileHash -Path "$mariadbStaging/bin/mariadbd.exe" -Algorithm SHA256).Hash
$mariadbClientHash = (Get-FileHash -Path "$mariadbStaging/bin/mariadb.exe" -Algorithm SHA256).Hash

$pkgManifest = [ordered]@{
    "project" = "MedCore Platinum Desktop"
    "release" = "v1.0.0-rc.3-commercial-closure"
    "build_type" = "EVALUATION"
    "package_classification" = "B) Desktop + Local Service + Bundled MariaDB 11.4 Self-Contained Offline Hospital Distribution Package"
    "commercial_rights_closure" = $true
    "offline_licensing" = "RSA-2048 Signed .mclic with PKCS#1 v1.5"
    "hardware_binding" = "SHA-256 Windows Host Machine Fingerprint"
    "anti_rollback_clock_guard" = "Monotonic Security Anchor + Keyed HMAC Seal"
    "dynamic_db_credentials" = "32-character CSPRNG Generated root password"
    "static_passwords_eliminated" = @("LEGACY_STATIC_DEFAULT_PURGED")
    "bundled_mariadb" = $true
    "mariadb_version" = "11.4.4-MariaDB"
    "desktop_binary_sha256" = $desktopExeHash
    "service_binary_sha256" = $serviceExeHash
    "commission_binary_sha256" = $commissionExeHash
    "mariadb_daemon_sha256" = $mariadbdHash
    "mariadb_client_sha256" = $mariadbClientHash
    "offline_capable" = $true
    "application_commit" = $builtCommit
    "build_timestamp" = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}
$pkgManifest | ConvertTo-Json -Depth 5 | Out-File -FilePath "$stagingDir/release_manifest.json" -Encoding utf8

Write-Host "Compressing archive $artifactBase.zip..."
$zipName = "$artifactBase.zip"
if (Test-Path $zipName) { Remove-Item $zipName -Force }
Compress-Archive -Path "$stagingDir/*" -DestinationPath $zipName -Force

$zipItem = Get-Item $zipName
$zipHash = (Get-FileHash -Path $zipName -Algorithm SHA256).Hash
$mb = [math]::Round($zipItem.Length / 1MB, 2)

Write-Host "============================================================"
Write-Host "PACKAGE CLOSURE COMPLETE"
Write-Host "Archive Name   : $zipName"
Write-Host "Archive Size   : $($zipItem.Length) bytes ($mb MB)"
Write-Host "Archive SHA256 : $zipHash"
Write-Host "============================================================"
