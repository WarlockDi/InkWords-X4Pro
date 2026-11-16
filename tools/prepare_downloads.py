from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[1]
m=json.loads((root/'docs/releases/archive-parts.json').read_text())
blocks=[]
for part in m['parts']:
 data=(root/part['path']).read_bytes();assert hashlib.sha256(data).hexdigest()==part['sha256'];blocks.append(data)
data=b''.join(blocks);assert hashlib.sha256(data).hexdigest()==m['sha256']
(root/'downloads'/m['name']).write_bytes(data)
print('PASS assembled release archive checksum')
