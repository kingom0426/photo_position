"""Public API acceptance using a disposable account; cleans only its own fixtures."""
from pathlib import Path
import os, subprocess, json, uuid, secrets, base64, hashlib, urllib.request, urllib.error
cfg=dict(line.split('=',1) for line in (Path(__file__).resolve().parents[1]/'.env.local').read_text().splitlines() if line and not line.startswith('#') and '=' in line)
def sql(query):
 r=subprocess.run(['/usr/local/opt/mysql-client/bin/mysql','--connect-timeout=10','-N','-B','-h',cfg['DB_HOST'],'-u',cfg['DB_USER'],cfg['DB_NAME']],input=query,text=True,capture_output=True,env=dict(os.environ,MYSQL_PWD=cfg['DB_PASSWORD']))
 if r.returncode: raise RuntimeError('Database check failed; details suppressed')
 return r.stdout.strip()
def quote(v): return "'"+v.replace("'","''")+"'"
uid=str(uuid.uuid4());email='location-qa-'+secrets.token_hex(8)+'@example.invalid';password=secrets.token_urlsafe(24)
salt_bytes=secrets.token_bytes(16)
salt=base64.urlsafe_b64encode(salt_bytes).decode().rstrip('=')
pw=base64.urlsafe_b64encode(hashlib.pbkdf2_hmac('sha256',password.encode(),salt_bytes,120000,32)).decode().rstrip('=')
token=None
BASE='https://chenxi-edu.com'
def call(path,method='GET',payload=None,status=200,auth=False):
 headers={'Content-Type':'application/json'}
 if auth: headers['Authorization']='Bearer '+token
 req=urllib.request.Request(BASE+path,headers=headers,method=method,data=None if payload is None else json.dumps(payload).encode())
 try: response=urllib.request.urlopen(req,timeout=30)
 except urllib.error.HTTPError as error: response=error
 with response: data=response.read();code=response.code
 assert code==status, f'{method} {path}: {code}, expected {status}'
 return json.loads(data) if data else None

def payload(privacy=None,lat=None,lon=None):
 return {'kind':'ORIGINAL','title':'地点隐私验收'+uid,'location':{'name':'qa-secret-'+uid,'city':'上海','district':'秘密小区','detailedAddress':'门牌501','advice':'秘密入口','privacy':privacy,'latitude':lat,'longitude':lon}}
def hidden(loc):
 assert loc['privacy']=='PRIVATE' and loc['latitude'] is None and loc['longitude'] is None
 assert all(not loc[k] for k in ['name','city','district','detailedAddress','advice'])
try:
 assert call('/api/health')['status']=='ok'
 assert sql("SELECT COUNT(*) FROM flyway_schema_history WHERE version='17' AND success=1")=='1'
 sql('INSERT INTO users(id,email,nickname,password_salt,password_hash,email_verified_at) VALUES('+','.join(map(quote,[uid,email,'地点验收'+uid[:8],salt,pw]))+',CURRENT_TIMESTAMP(3));')
 token=call('/api/auth/login','POST',{'email':email,'password':password})['token']
 missing=call('/api/posts','POST',{'kind':'ORIGINAL','title':'无地点验收'+uid},201,True);hidden(missing['location'])
 private=call('/api/posts','POST',payload('PRIVATE',31.234567,121.456789),201,True);hidden(private['location'])
 for privacy in ['EXACT','APPROXIMATE']:
  call('/api/posts','POST',payload(privacy),400,True)
  call('/api/posts','POST',payload(privacy,31.2,None),400,True)
 call('/api/posts','POST',payload('EXACT',91,121),400,True)
 exact=call('/api/posts','POST',payload('EXACT',31.234567,121.456789),201,True)
 assert exact['location']['latitude']==31.234567 and exact['location']['detailedAddress']=='门牌501'
 approx=call('/api/posts','POST',payload('APPROXIMATE',31.234567,121.456789),201,True)
 assert approx['location']['latitude']==31.23 and approx['location']['longitude']==121.46
 assert approx['location']['name']=='模糊区域' and not approx['location']['detailedAddress'] and not approx['location']['advice']
 for post in [missing,private,exact,approx]:
  assert call('/api/posts/'+post['id'])['location']==post['location']
 listed=call('/api/posts?authorId='+uid)['items'];assert len(listed)==4
 for post in listed:
  if post['id'] in [missing['id'],private['id']]: hidden(post['location'])
 near=call('/api/posts?feed=nearby&latitude=31.234567&longitude=121.456789&radiusKm=5&authorId='+uid)['items']
 assert {p['id'] for p in near}=={exact['id'],approx['id']}
 search=call('/api/discovery/search?q=qa-secret-'+uid)
 assert len(search['locations'])==1 and search['locations'][0]['latitude']==31.234567
 # Text edit preserves each previously selected privacy and public precision.
 for post in [private,approx,exact]:
  body={'title':'编辑验收'+uid,'location':post['location']}
  updated=call('/api/posts/'+post['id'],'PUT',body,auth=True)
  assert updated['location']==post['location']
 hidden(call('/api/posts/'+exact['id'],'PUT',payload('PRIVATE',31.234567,121.456789),auth=True)['location'])
 assert call('/api/discovery/search?q=qa-secret-'+uid)['locations']==[]
 assignment_body={'kind':'ASSIGNMENT','originalId':approx['id'],'title':'无地点作业验收'+uid}
 assignment=call('/api/posts','POST',assignment_body,201,True);hidden(assignment['location'])
 assert sql('SELECT COUNT(*) FROM post_locations l JOIN posts p ON p.id=l.post_id WHERE p.author_id='+quote(uid)+" AND l.privacy_level='PRIVATE' AND (l.latitude IS NOT NULL OR l.longitude IS NOT NULL OR l.place_name<>'' OR l.detailed_address<>'')")=='0'
 print('PASS: migration 17, health, missing/private/exact/approximate create, validation, edits, assignment isolation, detail, list, nearby, search and stored privacy')
finally:
 sql('DELETE FROM remake_plans WHERE user_id='+quote(uid)+';DELETE FROM posts WHERE author_id='+quote(uid)+" AND kind='ASSIGNMENT';DELETE FROM posts WHERE author_id="+quote(uid)+';DELETE FROM users WHERE id='+quote(uid)+' AND email='+quote(email)+';')
 print('PASS: disposable account and posts removed')
