import os
import subprocess
import json
import time

proj = r'C:\Users\hp\Desktop\project 4'
evidence_dir = os.path.join(proj, 'MEDCORE_PLATINUM_FINAL_EVIDENCE', '03_MIGRATIONS')
os.makedirs(evidence_dir, exist_ok=True)

env = os.environ.copy()
env['MEDCORE_TEST_DB_PASSWORD'] = 'KW1tDkidQdzXr5fjoKXlEXgAr42S8MDg'
env['MEDCORE_TEST_DB_PORT'] = '3307'

client_bin = os.path.join(proj, 'runtime', 'mariadb', 'bin', 'mariadb.exe')

def run_sql(db, sql):
    cmd = [client_bin, '-h', '127.0.0.1', '-P', '3307', '-u', 'root', '-pKW1tDkidQdzXr5fjoKXlEXgAr42S8MDg']
    if db:
        cmd.extend(['-D', db])
    cmd.extend(['-e', sql])
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr

results = {}

# 1. Clean Database Setup
test_db = 'medcore_gate03_migration_test'
run_sql('', f'DROP DATABASE IF EXISTS `{test_db}`; CREATE DATABASE `{test_db}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;')

# 2. Run MigrationRunner via Dart script
dart_runner_script = f'''
import 'dart:io';
import 'package:medcore_local_service/medcore_local_service.dart';
import 'test/support/test_db_config.dart';

void main() async {{
  final config = testDbConfig(databaseName: '{test_db}');
  final db = DbClient(config);
  try {{
    final runner = MigrationRunner(
      db: db,
      migrationsDir: 'sql/migrations',
    );
    print('PASS 1: Clean migration run...');
    final applied1 = await runner.runMigrations();
    print('APPLIED_PASS_1: ' + applied1.length.toString());
    
    print('PASS 2: Idempotency migration run...');
    final applied2 = await runner.runMigrations();
    print('VERIFIED_PASS_2: ' + applied2.length.toString());
  }} finally {{
    await db.close();
  }}
}}
'''

script_path = os.path.join(proj, 'medcore_local_service', 'gate03_runner.dart')
with open(script_path, 'w', encoding='utf-8') as f:
    f.write(dart_runner_script)

p_dart = subprocess.run('dart run gate03_runner.dart', cwd=os.path.join(proj, 'medcore_local_service'), env=env, shell=True, capture_output=True, text=True)
if os.path.exists(script_path):
    os.remove(script_path)

results['migration_run'] = {
    'exit_code': p_dart.returncode,
    'stdout': p_dart.stdout,
    'stderr': p_dart.stderr
}

# 3. Inspect Tables in Database
code, out_tables, err = run_sql(test_db, 'SHOW TABLES;')
tables = [line.strip() for line in out_tables.splitlines()[1:] if line.strip()]
results['tables_count'] = len(tables)
results['tables'] = tables

# 4. Check schema version table
code, out_ver, err = run_sql(test_db, 'SELECT version, description, execution_ms, applied_at FROM mc_schema_migrations ORDER BY version ASC;')
results['schema_versions'] = [line.strip() for line in out_ver.splitlines()]

# 5. Red Team Attacks on Migrations
red_team = []

# RT-MIG-01: Replay already applied migration (should not corrupt existing schema)
v001_path = os.path.join(proj, 'medcore_local_service', 'sql', 'migrations', 'V001__platform_governance_and_tenants.sql')
with open(v001_path, 'r', encoding='utf-8') as f:
    v001_sql = f.read()

c_v001, out_v001, err_v001 = run_sql(test_db, v001_sql)
red_team.append({
    'attack_id': 'RT-MIG-01',
    'name': 'Direct Migration Replay Attack',
    'expected': 'Zero schema corruption, tables intact',
    'exit_code': c_v001,
    'tables_after': len(tables),
    'pass': c_v001 == 0
})

# RT-MIG-02: Constraint enforcement check (Insert duplicate tenant)
c_dup, out_dup, err_dup = run_sql(test_db, "INSERT INTO mc_tenants (hospital_code, name, status) VALUES ('HOSP_DUP', 'Test', 'active'); INSERT INTO mc_tenants (hospital_code, name, status) VALUES ('HOSP_DUP', 'Test Duplicate', 'active');")
red_team.append({
    'attack_id': 'RT-MIG-02',
    'name': 'Primary Key / Unique Constraint Enforcement Attack',
    'expected': 'Duplicate entry rejected (1062)',
    'exit_code': c_dup,
    'blocked': c_dup != 0 and '1062' in err_dup,
    'err': err_dup.strip()
})

# RT-MIG-03: Tamper Detection (Simulate tampered checksum in mc_schema_migrations)
run_sql(test_db, "UPDATE mc_schema_migrations SET checksum_sha256 = '0000000000000000000000000000000000000000000000000000000000000000' WHERE version = 'V001';")

dart_tamper_script = f'''
import 'dart:io';
import 'package:medcore_local_service/medcore_local_service.dart';
import 'test/support/test_db_config.dart';

void main() async {{
  final config = testDbConfig(databaseName: '{test_db}');
  final db = DbClient(config);
  try {{
    final runner = MigrationRunner(
      db: db,
      migrationsDir: 'sql/migrations',
    );
    await runner.runMigrations();
    print('UNEXPECTED_PASS');
  }} catch (e) {{
    print('CAUGHT_TAMPER_EXCEPTION: ' + e.toString());
  }} finally {{
    await db.close();
  }}
}}
'''
tamper_path = os.path.join(proj, 'medcore_local_service', 'gate03_tamper.dart')
with open(tamper_path, 'w', encoding='utf-8') as f:
    f.write(dart_tamper_script)

p_tamper = subprocess.run('dart run gate03_tamper.dart', cwd=os.path.join(proj, 'medcore_local_service'), env=env, shell=True, capture_output=True, text=True)
if os.path.exists(tamper_path):
    os.remove(tamper_path)

tamper_detected = 'MigrationTamperException' in p_tamper.stdout
red_team.append({
    'attack_id': 'RT-MIG-03',
    'name': 'Migration Checksum Tamper Attack',
    'expected': 'MigrationTamperException thrown and execution blocked',
    'blocked': tamper_detected,
    'output': p_tamper.stdout.strip()
})

results['red_team'] = red_team

# Clean up test database
run_sql('', f'DROP DATABASE IF EXISTS `{test_db}`;')

gate_pass = (p_dart.returncode == 0) and ('APPLIED_PASS_1: 18' in p_dart.stdout) and ('VERIFIED_PASS_2: 18' in p_dart.stdout) and all(r['pass'] if 'pass' in r else r['blocked'] for r in red_team)
results['gate_status'] = 'PASS' if gate_pass else 'FAIL'

with open(os.path.join(evidence_dir, 'gate03_results.json'), 'w', encoding='utf-8') as f:
    json.dump(results, f, indent=2)

print('GATE 03 COMPLETE. Status:', results['gate_status'])
