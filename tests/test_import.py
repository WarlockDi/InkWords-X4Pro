from pathlib import Path
import csv,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='inkwords-import-') as temp:
    base=Path(temp);source=base/'words.csv'
    with source.open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.writer(f);w.writerow(['word','meaning','sentence','translation']);w.writerow(['hello','你好\n问候语','I say hello.','我打个招呼。'])
    def run(script,*args,ok=True):
        r=subprocess.run([sys.executable,str(ROOT/'tools'/script),*map(str,args)],capture_output=True,text=True)
        assert (r.returncode==0)==ok,(r.stdout,r.stderr)
    new=base/'new';merged=base/'merged';existing=ROOT/'examples/AppFiles/inkwords'
    before={p.name:p.read_bytes() for p in existing.iterdir()}
    run('import_csv.py',source,'--name','Test book','--output',new)
    assert '你好\\n问候语' in next(new.glob('*_e000.txt')).read_text(encoding='utf-8')
    run('import_csv.py',source,'--name','Test book','--output',new,ok=False)
    run('merge_libraries.py',existing,new,'--output',merged)
    assert len((merged/'library_v2.txt').read_text(encoding='utf-8').splitlines())==3
    assert all((merged/n).read_bytes()==v for n,v in before.items() if n!='library_v2.txt')
    assert before=={p.name:p.read_bytes() for p in existing.iterdir()}
    block=next(new.glob('*_e000.txt'));block.write_text(block.read_text(encoding='utf-8')+'2\tx\ty\n',encoding='utf-8')
    rejected=base/'rejected';run('merge_libraries.py',merged,new,'--output',rejected,ok=False)
    assert not rejected.exists()
print('PASS: CSV multiline/BOM, no overwrite, additive merge, original files unchanged, conflicting contents rejected before output')
