import os
import subprocess
import json

proj = r'C:\Users\hp\Desktop\project 4'

env = os.environ.copy()
env['MEDCORE_TEST_DB_PASSWORD'] = 'KW1tDkidQdzXr5fjoKXlEXgAr42S8MDg'
env['MEDCORE_TEST_DB_PORT'] = '3307'

tests_gate08 = [
    'test/batch20_independent_certification_gates_08_to_13_test.dart',
    'test/batch21_commercial_bypass_redteam_35_vectors_test.dart'
]

tests_gate09 = [
    'test/batch1_gate1_and_gate2_acceptance_test.dart',
    'test/batch2_feature_completion_acceptance_test.dart',
    'test/batch3_concurrency_and_integration_test.dart',
    'test/batch4_full_system_integration_and_redteam_test.dart'
]

results = {'gate08': {}, 'gate09': {}}
g8_pass = True
g9_pass = True

print('=== EXECUTING GATE 08 (COMMERCIAL ENTITLEMENT & RED TEAM) ===')
for t in tests_gate08:
    suite = os.path.basename(t)
    print(f'Running {suite}...')
    p = subprocess.run(f'dart test {t}', cwd=os.path.join(proj, 'medcore_local_service'), env=env, shell=True, capture_output=True, text=True, encoding='utf-8', errors='replace')
    passed = (p.returncode == 0)
    if not passed:
        g8_pass = False
    results['gate08'][suite] = {'exit_code': p.returncode, 'pass': passed, 'stdout': p.stdout[-1000:] if len(p.stdout) > 1000 else p.stdout}
    print(f'-> {suite}: {"PASS" if passed else "FAIL"}')

print('\n=== EXECUTING GATE 09 (LOCAL SERVICE SECURITY & CONCURRENCY) ===')
for t in tests_gate09:
    suite = os.path.basename(t)
    print(f'Running {suite}...')
    p = subprocess.run(f'dart test {t}', cwd=os.path.join(proj, 'medcore_local_service'), env=env, shell=True, capture_output=True, text=True, encoding='utf-8', errors='replace')
    passed = (p.returncode == 0)
    if not passed:
        g9_pass = False
    results['gate09'][suite] = {'exit_code': p.returncode, 'pass': passed, 'stdout': p.stdout[-1000:] if len(p.stdout) > 1000 else p.stdout}
    print(f'-> {suite}: {"PASS" if passed else "FAIL"}')

# Save Gate 08
out_08 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '08_ENTITLEMENT', 'gate08_results.json')
with open(out_08, 'w', encoding='utf-8') as f:
    json.dump({'status': 'PASS' if g8_pass else 'FAIL', 'results': results['gate08']}, f, indent=2)

# Save Gate 09
out_09 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '09_LOCAL_SERVICE', 'gate09_results.json')
with open(out_09, 'w', encoding='utf-8') as f:
    json.dump({'status': 'PASS' if g9_pass else 'FAIL', 'results': results['gate09']}, f, indent=2)

print('GATE 08 STATUS:', 'PASS' if g8_pass else 'FAIL')
print('GATE 09 STATUS:', 'PASS' if g9_pass else 'FAIL')
