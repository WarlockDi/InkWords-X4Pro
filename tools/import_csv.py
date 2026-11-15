"""Convert your authorized UTF-8 CSV to a NEW InkWords library folder.
Columns: word,meaning,sentence,translation (last two optional).
Never overwrites an existing library. Keep IDs/order stable after studying.
"""
from pathlib import Path
import argparse,csv,hashlib
p=argparse.ArgumentParser();p.add_argument('csv');p.add_argument('--name',required=True);p.add_argument('--output',required=True);a=p.parse_args()
dest=Path(a.output)
if dest.exists():p.error('Choose a new output directory; existing libraries will not be overwritten.')
with Path(a.csv).open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
assert rows and all(r.get('word') and r.get('meaning') for r in rows),'word and meaning are required'
assert not any(c in a.name for c in '\t\r\n'),'Invalid name'
key='iw'+hashlib.sha256(a.name.encode()).hexdigest()[:10]
def esc(s):return s.replace('\\','\\\\').replace('\r','').replace('\t',' ').replace('\n','\\n')
lines=[]
for i,r in enumerate(rows,1):
    back='释义：'+r['meaning']
    if r.get('sentence'):back+='\n例句：'+r['sentence']
    if r.get('translation'):back+='\n译文：'+r['translation']
    line=f'{i}\t{esc(r["word"])}\t{esc(back)}\n';assert len(line.encode())<=2000,'Shorten very long entries'
    lines.append(line)
blocks=[''.join(lines[i:i+250]) for i in range(0,len(lines),250)]
assert all(len(s.encode())<120000 for s in blocks),'Shorten entries: maximum block size exceeded'
dest.mkdir(parents=True)
for i,block in enumerate(blocks):(dest/f'{key}_e{i:03d}.txt').write_text(block,encoding='utf-8')
(dest/'library_v2.txt').write_text(f'INKWORDS_LIBRARY_3\n{key}\t{a.name}\t通用与分级\t1\t{len(rows)}\t600\t{(len(rows)+599)//600}\n',encoding='utf-8')
print('Created',len(rows),'cards in',dest,'; do not overwrite an established catalogue without merging it first.')
