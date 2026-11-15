"""Merge copies of InkWords v3 libraries into a NEW folder; never edit inputs.
Usage: python tools/merge_libraries.py old-copy new-library --output merged-library
Conflicting book IDs or file contents abort before creating the output.
"""
from pathlib import Path
import argparse,shutil,re
p=argparse.ArgumentParser();p.add_argument('folders',nargs='+');p.add_argument('--output',required=True);a=p.parse_args()
dest=Path(a.output)
if dest.exists():p.error('Output must be a new folder. Inputs will not be modified.')
books={};files={}
for folder in map(Path,a.folders):
    lines=(folder/'library_v2.txt').read_text(encoding='utf-8-sig').splitlines()
    if not lines or lines[0]!='INKWORDS_LIBRARY_3':p.error('Only format 3 libraries can be merged; older libraries need a separate conversion.')
    for line in lines[1:]:
        cells=line.split('\t')
        if len(cells)!=7 or not re.fullmatch('[A-Za-z0-9]+',cells[0]) or not all(x.isdigit() for x in cells[3:]):p.error('Invalid catalogue row')
        key=cells[0]
        if key in books and books[key]!=line:p.error('Conflicting book ID: '+key)
        books[key]=line
    for f in folder.iterdir():
        if f.name=='library_v2.txt':continue
        if f.is_symlink() or not f.is_file():p.error('Expected only plain files: '+f.name)
        if f.name in files and f.read_bytes()!=files[f.name].read_bytes():p.error('Conflicting file: '+f.name)
        files[f.name]=f
for line in books.values():
    key,_,_,_,count,per,shards=line.split('\t');count=int(count);per=int(per)
    if not 1<=per<=600 or count<1 or int(shards)!=(count+per-1)//per:p.error('Invalid card count')
    for i in range((count+249)//250):
        if f'{key}_e{i:03d}.txt' not in files:p.error('Missing data chunk for '+key)
dest.mkdir(parents=True)
for name,f in files.items():shutil.copy2(f,dest/name)
(dest/'library_v2.txt').write_text('INKWORDS_LIBRARY_3\n'+'\n'.join(books.values())+'\n',encoding='utf-8')
print('Merged',len(books),'books into',dest,'; input copies unchanged. Copy to the reader only after this success message.')
