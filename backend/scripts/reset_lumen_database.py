"""Explicitly authorized Lumen reset. Back up first; preserve schema and Flyway history.

Run only while lumen.service is stopped. The clear phase requires the saved backup's
checksum and exact pre-reset row counts. DELETE runs atomically, never TRUNCATE/DROP.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[2]
BACKUP = PROJECT / 'work/data-reset-backups/20260903-lumen-reset'
TABLES = ['notifications', 'remake_plans', 'favorites', 'post_likes', 'follows',
          'content_reports', 'post_tags', 'post_locations', 'capture_metadata', 'comments',
          'posts', 'email_auth_challenges', 'user_consent_acceptances', 'user_sessions',
          'users', 'sms_verification_codes', 'sms_send_attempts', 'auth_rate_limits']
CONFIG = dict(line.split('=', 1) for line in (PROJECT / 'backend/.env.local').read_text().splitlines()
              if line and not line.startswith('#') and '=' in line)
assert CONFIG['DB_NAME'] == 'photo_position_db', 'Unexpected database: abort'
ENV = dict(os.environ, MYSQL_PWD=CONFIG['DB_PASSWORD'])
CONNECTION = ['--connect-timeout=10', '--ssl-mode=PREFERRED', '-h', CONFIG['DB_HOST'],
              '-P', CONFIG.get('DB_PORT', '3306'), '-u', CONFIG['DB_USER']]
MYSQL = '/usr/local/opt/mysql-client/bin/mysql'
DUMP = '/usr/local/opt/mysql-client/bin/mysqldump'


def query(sql):
    result = subprocess.run([MYSQL, *CONNECTION, '-N', '-B', CONFIG['DB_NAME']],
                            input=sql, capture_output=True, text=True, env=ENV)
    if result.returncode:
        raise RuntimeError('Database command failed; details suppressed to avoid exposing private backup contents')
    return result.stdout.strip()


def assert_service_stopped():
    state = subprocess.run(['ssh', '-i', '/Users/duxin/.ssh/lumen_ecs_ed25519', '-o', 'BatchMode=yes',
                            'root@39.96.25.138', 'systemctl is-active lumen.service'], capture_output=True, text=True)
    if state.stdout.strip() != 'inactive':
        raise RuntimeError('Refuse reset while lumen.service is not confirmed inactive')


def snapshot():
    tables = query('SHOW TABLES;').splitlines()
    assert set(tables) == set(TABLES + ['flyway_schema_history']), 'Unexpected tables: stop for scope review'
    assert not query("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND ENGINE<>'InnoDB';"), 'Transactional engine required'
    counts = {table: int(query(f'SELECT COUNT(*) FROM `{table}`;')) for table in TABLES}
    history = query('SELECT installed_rank,version,description,checksum,success FROM flyway_schema_history ORDER BY installed_rank;')
    return {'counts': counts, 'flyway_sha256': hashlib.sha256(history.encode()).hexdigest()}


mode = sys.argv[1]
os.umask(0o077)
assert_service_stopped()
if mode == 'backup':
    BACKUP.mkdir(parents=True, exist_ok=True)
    BACKUP.chmod(0o700)
    dump = BACKUP / 'database.sql'
    assert not dump.exists(), 'Refuse to overwrite existing backup'
    before = snapshot()
    result = subprocess.run([DUMP, *CONNECTION[1:], '--single-transaction', '--set-gtid-purged=OFF',
                             '--no-tablespaces', '--column-statistics=0', '--hex-blob',
                             '--result-file=' + str(dump), CONFIG['DB_NAME']],
                            capture_output=True, text=True, env=ENV)
    assert result.returncode == 0, 'Database backup failed: no data was cleared'
    dump.chmod(0o600)
    data = dump.read_bytes()
    for table in TABLES + ['flyway_schema_history']:
        assert f'CREATE TABLE `{table}`'.encode() in data, 'Incomplete schema backup'
    assert b'Dump completed' in data, 'Incomplete dump'
    assert snapshot() == before, 'Data changed during backup: abort'
    before['dump_sha256'] = hashlib.sha256(data).hexdigest()
    (BACKUP / 'database-manifest.json').write_text(json.dumps(before, indent=2))
    print('Database backup validated. Bytes:', len(data))
    print(json.dumps(before['counts'], ensure_ascii=False))
elif mode == 'clear':
    assert len(sys.argv) == 3 and sys.argv[2] == 'CONFIRM_ALL_LUMEN_BUSINESS_DATA', 'Explicit confirmation required'
    before = json.loads((BACKUP / 'database-manifest.json').read_text())
    assert hashlib.sha256((BACKUP / 'database.sql').read_bytes()).hexdigest() == before['dump_sha256'], 'Backup checksum mismatch'
    current = snapshot()
    assert current['counts'] == before['counts'] and current['flyway_sha256'] == before['flyway_sha256'], 'Data changed since backup: abort'
    statements = ['START TRANSACTION;']
    for table in TABLES:
        if table == 'comments': statements.append('UPDATE comments SET parent_id=NULL WHERE parent_id IS NOT NULL;')
        if table == 'posts': statements.append('UPDATE posts SET original_post_id=NULL WHERE original_post_id IS NOT NULL;')
        statements.append(f'DELETE FROM `{table}`;')
    statements.append('COMMIT;')
    query('\n'.join(statements))
    after = snapshot()
    assert all(count == 0 for count in after['counts'].values()), 'Some business data remains'
    assert after['flyway_sha256'] == before['flyway_sha256'], 'Migration history changed unexpectedly'
    (BACKUP / 'database-after-reset.json').write_text(json.dumps(after, indent=2))
    print('All 18 business tables are empty; schema and Flyway migration history preserved.')
else:
    raise SystemExit('Use backup or clear')
