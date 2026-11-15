"""Build InkWords UI Font (OFL-1.1) from a locally supplied Noto Sans CJK SC Bold OTF."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import argparse,json
p=argparse.ArgumentParser();p.add_argument('--font',required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[1]
codes=[int(x) for x in (root/'assets/font-charset.txt').read_text().splitlines()]
fonts={False:ImageFont.truetype(args.font,40),True:ImageFont.truetype(args.font,34)}
blocks={}
for code in codes:
    ch=chr(code);font=fonts[code>127];width=round(font.getlength(ch));assert width<=64
    im=Image.new('L',(68,60));ImageDraw.Draw(im).text((0,44),ch,font=font,fill=255,anchor='ls');pix=im.load()
    rects=[];active={}
    for y in range(61):
        spans=[];x=0
        if y<60:
            while x<68:
                if pix[x,y]<128:x+=1;continue
                a=x
                while x<68 and pix[x,y]>=128:x+=1
                spans.append((a,x-a))
        current=set(spans)
        for key in list(active):
            if key not in current:
                yy=active.pop(key);rects.append((key[0],yy,key[1],y-yy))
        for key in current:
            if key not in active:active[key]=y
    value=''.join(chr(v+33) for v in [width]+[v for r in rects for v in r])
    blocks.setdefault(code//256,[]).append(str(code)+'\t'+value)
out=root/'apps/inkwords/data';out.mkdir(parents=True,exist_ok=True)
for key,lines in blocks.items():(out/f'uf{key:04x}.txt').write_text('\n'.join(lines)+'\n',encoding='ascii')
print(json.dumps({'glyphs':len(codes),'blocks':len(blocks),'bytes':sum(p.stat().st_size for p in out.glob('uf*.txt'))}))
