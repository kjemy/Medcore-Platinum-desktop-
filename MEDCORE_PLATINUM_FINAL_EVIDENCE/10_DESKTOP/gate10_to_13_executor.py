import os
import subprocess
import json

proj = r'C:\Users\hp\Desktop\project 4'

env = os.environ.copy()
env['MEDCORE_TEST_DB_PASSWORD'] = 'KW1tDkidQdzXr5fjoKXlEXgAr42S8MDg'
env['MEDCORE_TEST_DB_PORT'] = '3307'

results = {
    'desktop_tests': {},
    'clinical_business_tests': {},
    'persistence_verification': {},
    'launcher_verification': {}
}

# 1. Desktop Application Tests (Gate 10)
print('=== EXECUTING GATE 10 (DESKTOP APPLICATION TESTS) ===')
p_flutter = subprocess.run('flutter test', cwd=os.path.join(proj, 'medcore_desktop'), shell=True, capture_output=True, text=True, encoding='utf-8', errors='replace')
desktop_pass = (p_flutter.returncode == 0)
results['desktop_tests'] = {
    'exit_code': p_flutter.returncode,
    'pass': desktop_pass,
    'stdout': p_flutter.stdout[-1500:] if len(p_flutter.stdout) > 1500 else p_flutter.stdout
}
print(f'-> Desktop Flutter Tests: {"PASS" if desktop_pass else "FAIL"}')

# 2. Clinical / Business / Product Layer Tests (Gate 13)
print('\n=== EXECUTING GATE 13 (CLINICAL & BUSINESS TESTS) ===')
clinical_suites = [
    'test/batch5_product_layer_foundation_test.dart',
    'test/batch6_master_product_completion_test.dart',
    'test/batch7_employee_management_test.dart',
    'test/batch8_external_payables_and_lan_pki_test.dart',
    'test/batch13_dynamic_template_and_resource_engine_test.dart',
    'test/settlement_domain_redteam_test.dart'
]
clinical_pass = True
for t in clinical_suites:
    suite = os.path.basename(t)
    print(f'Running {suite}...')
    p = subprocess.run(f'dart test {t}', cwd=os.path.join(proj, 'medcore_local_service'), env=env, shell=True, capture_output=True, text=True, encoding='utf-8', errors='replace')
    passed = (p.returncode == 0)
    if not passed:
        clinical_pass = False
    results['clinical_business_tests'][suite] = {'exit_code': p.returncode, 'pass': passed, 'stdout': p.stdout[-1000:] if len(p.stdout) > 1000 else p.stdout}
    print(f'-> {suite}: {"PASS" if passed else "FAIL"}')

# 3. Persistence & Fresh Install Closure (Gate 11)
print('\n=== EXECUTING GATE 11 (PERSISTENCE & FRESH INSTALL CLOSURE) ===')
p_fresh = subprocess.run('dart test test/batch15_fresh_install_master_closure_test.dart', cwd=os.path.join(proj, 'medcore_local_service'), env=env, shell=True, capture_output=True, text=True, encoding='utf-8', errors='replace')
fresh_pass = (p_fresh.returncode == 0)
results['persistence_verification']['batch15'] = {
    'exit_code': p_fresh.returncode,
    'pass': fresh_pass,
    'stdout': p_fresh.stdout[-1500:] if len(p_fresh.stdout) > 1500 else p_fresh.stdout
}
print(f'-> Persistence Batch 15: {"PASS" if fresh_pass else "FAIL"}')

# Direct physical database write and independent read-back verification
client_bin = os.path.join(proj, 'runtime', 'mariadb', 'bin', 'mariadb.exe')
test_record_sql = "INSERT INTO medcore_local.mc_tenants (hospital_code, name, status) VALUES ('HOSP_PERSIST_VERIFY', 'Persistence Test Center', 'active') ON DUPLICATE KEY UPDATE status='active';"
p_write = subprocess.run([client_bin, '-h', '127.0.0.1', '-P', '3307', '-u', 'root', '-pKW1tDkidQdzXr5fjoKXlEXgAr42S8MDg', '-e', test_record_sql], capture_output=True, text=True)

p_read = subprocess.run([client_bin, '-h', '127.0.0.1', '-P', '3307', '-u', 'root', '-pKW1tDkidQdzXr5fjoKXlEXgAr42S8MDg', '-e', "SELECT hospital_code, name, status FROM medcore_local.mc_tenants WHERE hospital_code='HOSP_PERSIST_VERIFY';"], capture_output=True, text=True)
readback_verified = 'Persistence Test Center' in p_read.stdout
results['persistence_verification']['direct_sql_readback'] = {
    'write_exit': p_write.returncode,
    'read_exit': p_read.returncode,
    'read_output': p_read.stdout.strip(),
    'verified': readback_verified
}
print(f'-> Direct Physical DB Read-Back: {"PASS" if readback_verified else "FAIL"}')

# 4. Launcher Verification (Gate 12)
launcher_bat = os.path.join(proj, 'packaging', 'start_medcore_system.bat')
stages_found = []
if os.path.exists(launcher_bat):
    with open(launcher_bat, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        for i in range(1, 11):
            if f'Stage {i}/10' in content or f'STAGE {i}' in content:
                stages_found.append(i)
launcher_pass = (len(stages_found) >= 10)
results['launcher_verification'] = {
    'file': launcher_bat,
    'stages_found': stages_found,
    'pass': launcher_pass
}
print(f'-> Launcher 10 Stages Verification: {"PASS" if launcher_pass else "FAIL"}')

# Save evidence files
out_10 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '10_DESKTOP', 'gate10_results.json')
with open(out_10, 'w', encoding='utf-8') as f:
    json.dump({'status': 'PASS' if desktop_pass else 'FAIL', 'data': results['desktop_tests']}, f, indent=2)

out_11 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '11_PERSISTENCE', 'gate11_results.json')
with open(out_11, 'w', encoding='utf-8') as f:
    json.dump({'status': 'PASS' if (fresh_pass and readback_verified) else 'FAIL', 'data': results['persistence_verification']}, f, indent=2)

out_12 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '12_LAUNCHER', 'gate12_results.json')
with open(out_12, 'w', encoding='utf-8') as f:
    json.dump({'status': 'PASS' if launcher_pass else 'FAIL', 'data': results['launcher_verification']}, f, indent=2)

out_13 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '13_E2E', 'gate13_results.json')
with open(out_13, 'w', encoding='utf-8') as f:
    json.dump({'status': 'PASS' if clinical_pass else 'FAIL', 'data': results['clinical_business_tests']}, f, indent=2)

print('\nGATES 10, 11, 12, 13 COMPLETE.')
print('GATE 10:', 'PASS' if desktop_pass else 'FAIL')
print('GATE 11:', 'PASS' if (fresh_pass and readback_verified) else 'FAIL')
print('GATE 12:', 'PASS' if launcher_pass else 'FAIL')
print('GATE 13:', 'PASS' if clinical_pass else 'FAIL')
