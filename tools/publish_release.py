"""Publish a new version without replacing an older tag or its assets."""
from pathlib import Path
import hashlib, json, os, sys, urllib.request, urllib.error, urllib.parse, zipfile
root=Path(__file__).resolve().parents[1]
meta=json.loads((root/'docs/releases/release.json').read_text(encoding='utf-8'))
version=meta['version'];tag='v'+version
manifest=json.loads((root/'apps/inkwords/manifest.json').read_text(encoding='utf-8'))
assert manifest['version']==version
assert hashlib.sha256((root/'apps/inkwords/index.lua').read_bytes()).hexdigest()==meta['code_sha256']
files={}
for line in (root/'downloads/SHA256SUMS.txt').read_text().splitlines():
    digest,name=line.split('  ',1)
    assert name in [f'InkWords_{version}.xtapp',f'InkWords_{version}_Public.zip']
    data=(root/'downloads'/name).read_bytes();assert hashlib.sha256(data).hexdigest()==digest,name
    files[name]=data
assert len(files)==2
assert hashlib.sha256(files[f'InkWords_{version}.xtapp']).hexdigest()==meta['app_sha256']
with zipfile.ZipFile(root/'downloads'/f'InkWords_{version}_Public.zip') as z:
    assert z.testzip() is None and z.read(f'InkWords_{version}.xtapp')==files[f'InkWords_{version}.xtapp']
files['SHA256SUMS.txt']=(root/'downloads/SHA256SUMS.txt').read_bytes()
notes=(root/'docs/releases'/f'{version}.md').read_text(encoding='utf-8')
assert '## 中文' in notes and '## English' in notes and 'screenshots/summary-progress.png' in notes
if '--verify-only' in sys.argv:
    print('PASS publication inputs: tested app, source digest, archive, bilingual notes and screenshots');sys.exit(0)
repo=os.environ['GITHUB_REPOSITORY'];assert repo=='WarlockDi/InkWords-X4Pro'
commit=os.environ['GITHUB_SHA'];token=os.environ['GH_TOKEN']
def api(path,method='GET',data=None,raw=None):
    url=path if path.startswith('https://') else 'https://api.github.com/repos/'+repo+path
    assert url.startswith(('https://api.github.com/repos/'+repo+'/', 'https://uploads.github.com/repos/'+repo+'/'))
    body=raw if raw is not None else (json.dumps(data).encode() if data is not None else None)
    req=urllib.request.Request(url,data=body,method=method,headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','Content-Type':'application/octet-stream' if raw is not None else 'application/json','X-GitHub-Api-Version':'2022-11-28'})
    with urllib.request.urlopen(req,timeout=90) as response:return json.load(response)
releases=api('/releases?per_page=100');matches=[r for r in releases if r['tag_name']==tag];assert len(matches)<=1
if matches:
    release=matches[0]
else:
    release=api('/releases','POST',{'tag_name':tag,'target_commitish':commit,'name':'墨词 InkWords '+version+' · 错词复习与加载进度 / Review & loading progress','body':notes,'draft':True,'prerelease':False})
for name,payload in files.items():
    existing=next((a for a in release['assets'] if a['name']==name),None)
    expected='sha256:'+hashlib.sha256(payload).hexdigest()
    if existing:
        assert existing['size']==len(payload) and existing.get('digest')==expected,(name,'existing asset mismatch; refusing overwrite')
    else:
        assert release['draft'],'Refusing to add missing assets to an already-published release'
        asset=api(release['upload_url'].split('{')[0]+'?name='+urllib.parse.quote(name),'POST',raw=payload)
        assert asset['size']==len(payload) and asset.get('digest')==expected,name
release=api('/releases/'+str(release['id']),'PATCH',{'body':notes,'draft':False,'prerelease':False,'make_latest':'true'})
assert release['tag_name']==tag and not release['draft']
print('Published:',release['html_url'])
