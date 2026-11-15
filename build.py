"""Build the public InkWords app; never includes personal vocabulary or progress."""
from pathlib import Path
import hashlib,json,subprocess,sys,zipfile
import xtpack
from PIL import Image
root=Path(__file__).resolve().parent;app=root/'apps/inkwords';out=root/'dist';out.mkdir(exist_ok=True)
subprocess.run([sys.executable,str(root/'tools/build_spelling_font.py')],check=True)
subprocess.run([sys.executable,str(app/'bundle.py')],check=True)
m=xtpack.validate_manifest(json.loads((app/'manifest.json').read_text(encoding='utf-8')),str(app))
code=[(name,(app/name).read_bytes()) for name in ['index.lua','lockscreen.lua']]
data=[(p.name,p.read_bytes()) for p in sorted((app/'data').glob('uf*.txt'))]
assert len(data)==92,'Missing packaged font blocks'
data += [('spelling_font.txt',(app/'data/spelling_font.txt').read_bytes())]
data += [('font_notice.txt',(root/'licenses/FONT-COPYRIGHT.txt').read_bytes()),('font_license.txt',(root/'licenses/OFL-NotoSansCJK.txt').read_bytes()),('code_license.txt',(root/'LICENSE').read_bytes())]
data += [(name,(app/'data'/name).read_bytes()) for name in ['demo_cards.txt','demo_examples.txt','demo_library.txt']]
icon=xtpack.build_xic_1bpp(Image.open(app/'icon.png'));icons=xtpack.build_xtab([('app_icon_s',icon),('app_icon_l',icon)])
pkg,dek=xtpack.build_container(m,xtpack.device_pubkey(),code,data,icons)
_,obj=xtpack.xtapp.read_licorice_container(pkg);assert xtpack.xtapp.read_licorice_code(pkg,dek)==code
off,length=xtpack.xtapp.licorice_sections(pkg)['data'];encrypted=pkg[off:off+length]
assert xtpack.xtapp.licorice_section_hmac(dek,encrypted).hex()==obj['hmac_data']
assert xtpack.read_xtdt(xtpack.xtapp.licorice_ctr(dek,bytes.fromhex(obj['iv_data']),encrypted))==data
program=out/f'InkWords_{m["version"]}.xtapp';program.write_bytes(pkg)
archive=out/f'InkWords_{m["version"]}_Public.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    z.write(program,program.name)
    for name in ['INSTALL.md','THIRD_PARTY.md','LICENSE','AUTHORSHIP.md']:z.write(root/name,name)
    for p in (root/'licenses').iterdir():z.write(p,'licenses/'+p.name)
with zipfile.ZipFile(archive) as z:assert z.testzip() is None and z.read(program.name)==pkg
(out/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in [program,archive]),encoding='ascii')
print('PASS: code and data decrypted and checked;',len(pkg),'program bytes')
