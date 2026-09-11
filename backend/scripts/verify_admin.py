"""Live admin acceptance. Only generated fixture IDs are changed/deleted.
--ui keeps a temporary private fixture and admin for browser inspection until Enter.
The real administrator's credentials are never read or changed.
"""
import argparse
import base64
from datetime import datetime
import hashlib
import http.cookiejar
import json
import os
from pathlib import Path
import secrets
import subprocess
import urllib.error
import urllib.request
import uuid

cfg = dict(line.split('=',1) for line in (Path(__file__).resolve().parents[1]/'.env.local').read_text().splitlines()
           if line and not line.startswith('#') and '=' in line)
BASE='https://chenxi-edu.com'
def sql(query):
    result=subprocess.run(['/usr/local/opt/mysql-client/bin/mysql','--connect-timeout=10','-N','-B','-h',cfg['DB_HOST'],'-u',cfg['DB_USER'],cfg['DB_NAME']],
            input=query,text=True,capture_output=True,env=dict(os.environ,MYSQL_PWD=cfg['DB_PASSWORD']))
    if result.returncode: raise RuntimeError('Database check failed; details suppressed')
    return result.stdout.strip()
def quote(value): return "'"+value.replace('\\','\\\\').replace("'","''")+"'"
jar=http.cookiejar.CookieJar()
client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
def call(path,method='GET',payload=None,expected=200,authenticated=True,mutation=True,origin=BASE):
    headers={'Content-Type':'application/json'}
    if path.startswith('/api/admin/'): headers['Origin']=origin
    if mutation and method!='GET': headers['X-Lumen-Admin']='1'
    req=urllib.request.Request(BASE+path,data=None if payload is None else json.dumps(payload).encode(),headers=headers,method=method)
    try: response=(client.open(req,timeout=20) if authenticated else urllib.request.urlopen(req,timeout=20))
    except urllib.error.HTTPError as error: response=error
    with response:
        data=response.read();status=response.code;response_headers=response.headers
    assert status==expected,f'{method} {path}: expected {expected}, received {status}'
    if path.startswith('/api/admin/'): assert response_headers.get('Cache-Control')=='no-store'
    print(f'PASS {method} {path.split("?")[0]} [{status}]',flush=True)
    return json.loads(data) if 'application/json' in response_headers.get('Content-Type','') else data.decode()

args=argparse.ArgumentParser();args.add_argument('--ui',action='store_true');args=args.parse_args()
uid=str(uuid.uuid4());pid=str(uuid.uuid4());aid=str(uuid.uuid4());cid=str(uuid.uuid4());ui_post=str(uuid.uuid4())
email='admin-qa-'+secrets.token_hex(10)+'@example.invalid';password=secrets.token_urlsafe(32)
salt=base64.urlsafe_b64encode(secrets.token_bytes(16)).decode().rstrip('=')
password_hash=base64.urlsafe_b64encode(hashlib.pbkdf2_hmac('sha256',password.encode(),base64.urlsafe_b64decode(salt+'=='),120000,32)).decode().rstrip('=')
fixture_ids=[pid,aid,ui_post]
try:
    assert call('/api/health')['status']=='ok'
    for path in ['/admin/','/admin/admin.js','/admin/admin.css']: call(path,authenticated=False)
    for path in ['/api/admin/me','/api/admin/stats','/api/admin/posts','/api/admin/comments','/api/admin/posts/'+pid]: call(path,expected=401,authenticated=False)
    for path in ['/api/admin/posts/'+pid,'/api/admin/comments/'+cid]: call(path,'DELETE',expected=401,authenticated=False)
    sql('INSERT INTO users(id,email,nickname,password_salt,password_hash,email_verified_at) VALUES('+','.join(map(quote,[uid,email,'后台验收'+uid[:8],salt,password_hash]))+',CURRENT_TIMESTAMP(3));')
    login={'email':email,'password':password}
    call('/api/admin/login','POST',login,expected=403,mutation=False)
    call('/api/admin/login','POST',login,expected=403,origin='https://untrusted.example')
    call('/api/admin/login','POST',login,expected=403)
    assert sql('SELECT COUNT(*) FROM user_sessions WHERE user_id='+quote(uid))=='0'
    sql('INSERT INTO admin_members(user_id) VALUES('+quote(uid)+');')
    call('/api/admin/login','POST',dict(login,password='wrong-test-password'),expected=401)
    call('/api/admin/login','POST',login)
    cookie=next(c for c in jar if c.name=='lumen_admin')
    assert cookie.secure and cookie.path=='/api/admin' and cookie.has_nonstandard_attr('HttpOnly')
    assert 'token' not in call('/api/admin/me')
    remaining=int(sql('SELECT TIMESTAMPDIFF(SECOND,CURRENT_TIMESTAMP(3),expires_at) FROM user_sessions WHERE user_id='+quote(uid)+' LIMIT 1'))
    assert 28700<=remaining<=28800
    for item,kind,original in [(pid,'ORIGINAL',None),(aid,'ASSIGNMENT',pid),(ui_post,'ORIGINAL',None)]:
        title='后台验收 · '+('复刻作业' if kind=='ASSIGNMENT' else '光影测试')
        sql('INSERT INTO posts(id,author_id,kind,original_post_id,title,description,shooting_notes,editing_notes,reused_notes,adjusted_notes,assignment_notes,visibility) VALUES('
            +','.join([quote(item),quote(uid),quote(kind),quote(original) if original else 'NULL',quote(title),quote('仅供后台验收，完成后自动清理。'),quote('自然光拍摄'),quote(''),quote(''),quote(''),quote('练习说明'),quote('PUBLIC' if item==pid else 'PRIVATE')])+');')
    sql('INSERT INTO comments(id,post_id,author_id,content) VALUES('+','.join(map(quote,[cid,pid,uid,'验收评论 <img src=x onerror=alert(1)>']))+');UPDATE posts SET comment_count=1 WHERE id='+quote(pid)+';')
    assert call('/api/admin/posts?kind=ORIGINAL&q='+ui_post)['total']==1
    assert call('/api/admin/posts?kind=ASSIGNMENT&q='+aid)['total']==1
    assert call('/api/admin/posts?kind=ORIGINAL&limit=1')['limit']==1
    call('/api/admin/posts?kind=INVALID',expected=400)
    detail=call('/api/admin/posts/'+pid);assert detail['content']['id']==pid
    expected_epoch=float(sql('SELECT UNIX_TIMESTAMP(created_at) FROM posts WHERE id='+quote(pid)))
    assert abs(datetime.fromisoformat(detail['createdAt'].replace('Z','+00:00')).timestamp()-expected_epoch)<1
    listed=call('/api/admin/posts?kind=ORIGINAL&q='+pid)['items'][0]
    assert listed['createdAt']==detail['createdAt'], 'List/detail dates must share the real database instant'
    assert call('/api/admin/comments?postId='+pid)['items'][0]['id']==cid
    call('/api/admin/stats')
    assert len(call('/api/posts/'+pid+'/comments')['items'])==1
    call('/api/admin/comments/'+cid,'DELETE',expected=403,mutation=False)
    call('/api/admin/comments/'+cid,'DELETE',expected=403,origin='https://untrusted.example')
    call('/api/admin/comments/'+cid,'DELETE',expected=204)
    call('/api/admin/comments/'+cid,'DELETE',expected=204)
    assert len(call('/api/posts/'+pid+'/comments')['items'])==0
    assert sql('SELECT comment_count FROM posts WHERE id='+quote(pid))=='0'
    assert call('/api/admin/comments?status=DELETED&postId='+pid)['total']==1
    call('/api/posts/'+pid)
    call('/api/admin/posts/'+pid,'DELETE',expected=204)
    call('/api/admin/posts/'+pid,'DELETE',expected=204)
    call('/api/posts/'+pid,expected=404)
    assert call('/api/admin/posts/'+pid)['deletedAt'] is not None
    assert call('/api/admin/posts?kind=ORIGINAL&status=DELETED&q='+pid)['total']==1
    assert call('/api/admin/posts?kind=ASSIGNMENT&q='+aid)['total']==1
    assert sql('SELECT COUNT(*) FROM admin_audit_logs WHERE actor_id='+quote(uid))=='2'
    call('/api/admin/posts/'+str(uuid.uuid4()),'DELETE',expected=404)
    if args.ui:
        # These are freshly generated, disposable fixture credentials, not user credentials.
        print('TEMPORARY BROWSER FIXTURE: '+json.dumps({'email':email,'password':password,'postId':ui_post}),flush=True)
        input('Browser verification ready. Press Enter to revoke and clean up.\n')
    call('/api/admin/logout','POST',expected=204)
    call('/api/admin/me',expected=401)
    print('PASS administrator authorization, CSRF, pagination, details, idempotent soft deletion, public invisibility, comment count, audit, logout',flush=True)
finally:
    # Exact generated IDs, children first. No existing user/content is targeted.
    sql('DELETE FROM admin_audit_logs WHERE actor_id='+quote(uid)+';DELETE FROM comments WHERE author_id='+quote(uid)+';'
        +'DELETE FROM posts WHERE id='+quote(aid)+' AND author_id='+quote(uid)+';'
        +'DELETE FROM posts WHERE id IN ('+','.join(map(quote,[pid,ui_post]))+') AND author_id='+quote(uid)+';'
        +'DELETE FROM users WHERE id='+quote(uid)+' AND email='+quote(email)+';')
    print('PASS temporary account, role, sessions, content and audit fixtures removed',flush=True)
