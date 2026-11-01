import os
import subprocess
import json

proj = r'C:\Users\hp\Desktop\project 4'

env = os.environ.copy()
env['MEDCORE_TEST_DB_PASSWORD'] = 'KW1tDkidQdzXr5fjoKXlEXgAr42S8MDg'
env['MEDCORE_TEST_DB_PORT'] = '3307'

tests = [
    ('batch18_commercial_rights_and_offline_licensing_test.dart', '05_LICENSING'),
    ('batch19_independent_certification_gates_03_to_07_test.dart', '05_LICENSING'),
    ('clock_rollback_guard_acceptance_test.dart', '06_CLOCK')
]

results = {}
all_pass = True

for t, dest in tests:
    print(f'Running {t}...')
    p = subprocess.run(f'dart test test/{t}', cwd=os.path.join(proj, 'medcore_local_service'), env=env, shell=True, capture_output=True, text=True, encoding='utf-8', errors='replace')
    passed = (p.returncode == 0)
    if not passed:
        all_pass = False
    results[t] = {
        'exit_code': p.returncode,
        'pass': passed,
        'stdout': p.stdout[-1000:] if len(p.stdout) > 1000 else p.stdout
    }
    print(f'-> {t}: {"PASS" if passed else "FAIL"}')

# Save in 05_LICENSING
out_05 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '05_LICENSING', 'gate05_results.json')
with open(out_05, 'w', encoding='utf-8') as f:
    json.dump({'suite': 'batch18 & batch19', 'results': results, 'status': 'PASS' if all_pass else 'FAIL'}, f, indent=2)

# Save in 06_CLOCK
out_06 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '06_CLOCK', 'gate06_results.json')
with open(out_06, 'w', encoding='utf-8') as f:
    json.dump({'suite': 'clock_rollback_guard_acceptance_test.dart', 'results': results.get('clock_rollback_guard_acceptance_test.dart'), 'status': 'PASS' if results.get('clock_rollback_guard_acceptance_test.dart', {}).get('pass') else 'FAIL'}, f, indent=2)

# Save in 07_HARDWARE
out_07 = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '07_HARDWARE', 'gate07_results.json')
with open(out_07, 'w', encoding='utf-8') as f:
    json.dump({'suite': 'batch18 & batch19 hardware binding tests', 'results': results.get('batch19_independent_certification_gates_03_to_07_test.dart'), 'status': 'PASS' if results.get('batch19_independent_certification_gates_03_to_07_test.dart', {}).get('pass') else 'FAIL'}, f, indent=2)

print('GATES 05, 06, 07 COMPLETE. Overall status:', 'PASS' if all_pass else 'FAIL')
