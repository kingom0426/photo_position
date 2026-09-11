"""Explicit live smoke test. Creates only a disposable .invalid QA account, then removes it.

Uses synthetic challenges for public-API positive paths; does not read anyone's inbox.
Separately requests one real message to the configured sending mailbox and checks SMTP status.
Never prints passwords, codes, tokens, email addresses, or credentials.
"""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]


def config(path):
    return dict(line.split('=', 1) for line in path.read_text().splitlines()
                if line and not line.startswith('#') and '=' in line)


cfg = config(ROOT / '.env.local')
mail = config(ROOT / '.env.mail.local')
BASE = mail.get('PUBLIC_BASE_URL', 'https://chenxi-edu.com').rstrip('/')
MYSQL = '/usr/local/opt/mysql-client/bin/mysql'


def sql(query):
    env = dict(os.environ, MYSQL_PWD=cfg['DB_PASSWORD'])
    result = subprocess.run([MYSQL, '--connect-timeout=10', '--ssl-mode=PREFERRED', '-N', '-B',
        '-h', cfg['DB_HOST'], '-P', cfg.get('DB_PORT', '3306'), '-u', cfg['DB_USER'], cfg['DB_NAME']],
        input=query, text=True, capture_output=True, env=env)
    if result.returncode:
        raise RuntimeError('Database verification command failed (details suppressed to protect credentials)')
    return result.stdout.strip()


def quoted(value):
    return "'" + value.replace('\\', '\\\\').replace("'", "''") + "'"


def api(path, method='GET', payload=None, token=None, expect=200):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(BASE + path, data=None if payload is None else json.dumps(payload).encode(),
                                     headers=headers, method=method)
    try:
        response = urllib.request.urlopen(request, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        data = response.read()
        status = response.code
        response_headers = response.headers
    if status != expect:
        # Only fixed route and status are surfaced; responses may include authentication tokens.
        raise AssertionError(f'{method} {path}: expected {expect}, got {status}')
    if path.startswith('/api/auth/'):
        assert response_headers.get('Cache-Control') == 'no-store'
    print(f'PASS {method} {path} [{status}]', flush=True)
    if 'application/json' in response_headers.get('Content-Type', ''):
        return json.loads(data) if data else {}
    return data.decode()


qa_email = 'lumen-qa-' + secrets.token_hex(8) + '@example.invalid'
challenge_id = str(uuid.uuid4())
qa_user_id = None
initial_count = int(sql('SELECT COUNT(*) FROM users;'))
try:
    assert api('/api/health')['status'] == 'ok'
    consent = api('/api/auth/consent')
    assert consent['version'] == '3.0'
    html = api('/api/auth/reset-password')
    assert 'reset-form' in html
    script = api('/api/auth/reset-password.js')
    assert 'location.hash' in script and 'history.replaceState' in script
    api('/api/auth/email-code', 'POST', {'email': 'not-an-email'}, expect=400)
    generic = api('/api/auth/forgot-password', 'POST', {'email': qa_email})['message']

    code = f'{secrets.randbelow(1000000):06d}'
    digest = hmac.new(mail['MAIL_PASSWORD'].encode(), f'{challenge_id}:{code}'.encode(), hashlib.sha256).hexdigest()
    sql('INSERT INTO email_auth_challenges (id,email,purpose,secret_hash,delivery_status,expires_at) VALUES ('
        + ','.join(map(quoted, [challenge_id, qa_email, 'REGISTER', digest, 'PENDING']))
        + ',CURRENT_TIMESTAMP(3)+INTERVAL 10 MINUTE);')
    # Exercise the real MySQL schema: SMTP completion must not auto-update expiry.
    before_expiry = sql('SELECT expires_at FROM email_auth_challenges WHERE id=' + quoted(challenge_id) + ';')
    sql("UPDATE email_auth_challenges SET delivery_status='SENT' WHERE id=" + quoted(challenge_id) + ';')
    assert sql('SELECT expires_at FROM email_auth_challenges WHERE id=' + quoted(challenge_id) + ';') == before_expiry
    assert int(sql('SELECT TIMESTAMPDIFF(SECOND,created_at,expires_at) FROM email_auth_challenges WHERE id='
                   + quoted(challenge_id) + ';')) == 600
    print('PASS real MySQL preserves 600-second code expiry after delivery update', flush=True)
    password = secrets.token_urlsafe(24)
    registration = {'email': qa_email, 'password': password, 'nickname': '邮件验收' + secrets.token_hex(5),
                    'consentAccepted': True, 'consentVersion': consent['version'], 'verificationCode': code}
    wrong = dict(registration, verificationCode='111111' if code != '111111' else '222222')
    api('/api/auth/register', 'POST', wrong, expect=400)
    account = api('/api/auth/register', 'POST', registration, expect=201)
    qa_user_id = account['user']['id']
    assert account['user']['email'] == qa_email
    duplicate = api('/api/auth/register', 'POST', registration, expect=409)
    assert '该邮箱已注册' in duplicate['error']
    duplicate_code = api('/api/auth/email-code', 'POST', {'email': qa_email}, expect=409)
    assert '该邮箱已注册' in duplicate_code['error']
    login = api('/api/auth/login', 'POST', {'email': qa_email.upper(), 'password': password})
    api('/api/auth/me', token=login['token'])
    api('/api/auth/login', 'POST', {'email': qa_email, 'password': 'wrong-password-for-test'}, expect=401)

    token = secrets.token_urlsafe(32)
    reset_id = str(uuid.uuid4())
    sql('INSERT INTO email_auth_challenges (id,email,purpose,user_id,secret_hash,delivery_status,expires_at) VALUES ('
        + ','.join(map(quoted, [reset_id, qa_email, 'RESET', qa_user_id, hashlib.sha256(token.encode()).hexdigest(), 'SENT']))
        + ',CURRENT_TIMESTAMP(3)+INTERVAL 30 MINUTE);')
    new_password = secrets.token_urlsafe(24)
    api('/api/auth/reset-password', 'POST', {'token': 'invalid', 'password': new_password}, expect=400)
    api('/api/auth/reset-password', 'POST', {'token': token, 'password': new_password})
    api('/api/auth/reset-password', 'POST', {'token': token, 'password': new_password}, expect=400)
    api('/api/auth/me', token=account['token'], expect=401)
    api('/api/auth/me', token=login['token'], expect=401)
    api('/api/auth/login', 'POST', {'email': qa_email, 'password': password}, expect=401)
    logged_in = api('/api/auth/login', 'POST', {'email': qa_email, 'password': new_password})
    final_password = secrets.token_urlsafe(24)
    api('/api/auth/me/password', 'PUT', {'oldPassword': 'wrong-password-for-test', 'newPassword': final_password},
        token=logged_in['token'], expect=400)
    api('/api/auth/me/password', 'PUT', {'oldPassword': new_password, 'newPassword': final_password}, token=logged_in['token'])
    api('/api/auth/me', token=logged_in['token'], expect=401)
    final = api('/api/auth/login', 'POST', {'email': qa_email, 'password': final_password})
    api('/api/auth/logout', 'POST', token=final['token'], expect=204)

    # Delivery-only test to the user's configured mailbox; no mailbox read access is used.
    destination = mail['MAIL_USERNAME'].strip().lower()
    exists = int(sql('SELECT COUNT(*) FROM users WHERE email=' + quoted(destination) + ';')) > 0
    route = '/api/auth/forgot-password' if exists else '/api/auth/email-code'
    result = api(route, 'POST', {'email': destination})
    assert result['message'] == generic if exists else '10 分钟' in result['message']
    for attempt in range(20):
        state = sql('SELECT delivery_status FROM email_auth_challenges WHERE email=' + quoted(destination)
                    + ' ORDER BY created_at DESC LIMIT 1;')
        if state in ('SENT', 'FAILED'):
            break
        time.sleep(1)
    assert state == 'SENT', 'SMTP delivery not confirmed; no credentials or message body displayed'
    ttl = sql('SELECT TIMESTAMPDIFF(SECOND,created_at,expires_at),expires_at>CURRENT_TIMESTAMP(3) '
              + 'FROM email_auth_challenges WHERE email=' + quoted(destination) + ' ORDER BY created_at DESC LIMIT 1;').split('\t')
    assert ttl == [str(1800 if exists else 600), '1'], 'Actually generated mail must retain full validity after SMTP submission'
    print('PASS real email challenge retains full lifetime and remains valid after SMTP', flush=True)
    print('PASS ECS SMTP accepted message to configured mailbox (inbox delivery requires user confirmation)', flush=True)
    api(route, 'POST', {'email': destination}, expect=429)
finally:
    # Exact generated email/ID only. No pre-existing account can match this random reserved-domain identity.
    if qa_user_id:
        sql('DELETE FROM users WHERE id=' + quoted(qa_user_id) + ' AND email=' + quoted(qa_email) + ';')
    sql('DELETE FROM email_auth_challenges WHERE email=' + quoted(qa_email) + ';')
    remaining = int(sql('SELECT COUNT(*) FROM users WHERE email=' + quoted(qa_email) + ';'))
    assert remaining == 0, 'QA account cleanup incomplete'
    print('PASS temporary QA account and challenges removed; pre-existing accounts untouched', flush=True)
    print('User count before/after: ' + str(initial_count) + '/' + sql('SELECT COUNT(*) FROM users;'), flush=True)
