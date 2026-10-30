$ErrorActionPreference = "Stop"
$env:MEDCORE_TEST_DB_PASSWORD = "KW1tDkidQdzXr5fjoKXlEXgAr42S8MDg"
$env:MEDCORE_TEST_DB_PORT = "3307"

Set-Location "C:\Users\hp\Desktop\project 4\medcore_local_service"

$tests = @(
    "test/batch1_gate1_and_gate2_acceptance_test.dart",
    "test/batch2_feature_completion_acceptance_test.dart",
    "test/batch3_concurrency_and_integration_test.dart",
    "test/batch4_full_system_integration_and_redteam_test.dart",
    "test/batch5_product_layer_foundation_test.dart",
    "test/batch6_master_product_completion_test.dart",
    "test/batch7_employee_management_test.dart",
    "test/batch8_external_payables_and_lan_pki_test.dart",
    "test/batch9_database_lifecycle_and_recovery_test.dart",
    "test/batch10_initial_admin_and_activation_truth_test.dart",
    "test/batch11_final_commissioning_gate_simulation_test.dart",
    "test/batch12_micro_pbkdf2_and_credential_isolation_test.dart",
    "test/batch13_dynamic_template_and_resource_engine_test.dart",
    "test/batch14_technician_bootstrap_and_first_admin_test.dart",
    "test/batch15_fresh_install_master_closure_test.dart",
    "test/batch16_technician_credential_lifecycle_and_recovery_test.dart",
    "test/batch17_bundled_mariadb_self_contained_offline_test.dart",
    "test/batch18_commercial_rights_and_offline_licensing_test.dart",
    "test/batch19_independent_certification_gates_03_to_07_test.dart",
    "test/batch20_independent_certification_gates_08_to_13_test.dart",
    "test/batch21_commercial_bypass_redteam_35_vectors_test.dart",
    "test/clock_rollback_guard_acceptance_test.dart",
    "test/settlement_domain_redteam_test.dart"
)

$results = @()
$allPass = $true

foreach ($t in $tests) {
    Write-Host "`n=================================================="
    Write-Host "RUNNING: $t"
    Write-Host "=================================================="
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath "dart" -ArgumentList "test", $t -Wait -NoNewWindow -PassThru
    $sw.Stop()
    $status = if ($p.ExitCode -eq 0) { "PASS" } else { "FAIL" }
    if ($p.ExitCode -ne 0) { $allPass = $false }
    $results += [PSCustomObject]@{
        Suite = $t
        Status = $status
        ExitCode = $p.ExitCode
        DurationSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    }
    Write-Host "RESULT: $t -> $status ($($sw.Elapsed.TotalSeconds)s)"
    Start-Sleep -Seconds 1
}

Write-Host "`n=================================================="
Write-Host "FINAL TEST RUNNER SUMMARY (Gate 20)"
Write-Host "=================================================="
$results | Format-Table -AutoSize

if (-not $allPass) {
    Write-Error "ONE OR MORE TEST SUITES FAILED!"
    exit 1
} else {
    Write-Host "ALL 23 TEST SUITES PASSED DETERMINISTICALLY!"
    exit 0
}
