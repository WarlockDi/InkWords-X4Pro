"""Pre-scale the 26 candidate letters and menu glyphs; preserve every black pixel."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1];data=root/'apps/inkwords/data'
chars='abcdefghijklmnopqrstuvwxyz菜单';rows=[];before=after=0
for c in chars:
 code=ord(c);block=data/f'uf{code//256:04x}.txt'
 raw=next(v for k,v in (line.split('\t',1) for line in block.read_text(encoding='ascii').splitlines()) if int(k)==code)
 pixels=set();left=top=1000;right=bottom=0
 for i in range(1,len(raw),4):
  x,y,w,h=[ord(v)-33 for v in raw[i:i+4]];xx=x*3//4;yy=y*3//4;ww=max(1,(x+w)*3//4-xx);hh=max(1,(y+h)*3//4-yy)
  left=min(left,xx);top=min(top,yy);right=max(right,(x+w)*3//4);bottom=max(bottom,(y+h)*3//4)
  pixels.update((a,b) for a in range(xx,xx+ww) for b in range(yy,yy+hh))
 active={};rects=[]
 for y in range(max(b for a,b in pixels)+2):
  xs=sorted(a for a,b in pixels if b==y);spans=[]
  for x in xs:
   if spans and spans[-1][0]+spans[-1][1]==x:spans[-1]=(spans[-1][0],spans[-1][1]+1)
   else:spans.append((x,1))
  # Finish vertical runs before beginning new ones.
  for span in list(active):
   if span not in spans:
    start=active.pop(span);rects.append((span[0],start,span[1],y-start))
  for span in spans:
   if span not in active:active[span]=y
 rebuilt={(a,b) for x,y,w,h in rects for a in range(x,x+w) for b in range(y,y+h)}
 assert rebuilt==pixels,c
 value=chr((ord(raw[0])-32)*3//4+32)+''.join(chr(v+33) for r in rects for v in r)
 rows.append(str(code)+'\t'+','.join(map(str,[left,top,right-left,bottom-top]))+'\t'+value);before+=(len(raw)-1)//4;after+=len(rects)
path=data/'spelling_font.txt';path.write_text('\n'.join(rows)+'\n',encoding='ascii')
print(json.dumps({'glyphs':len(rows),'rectangles_before':before,'rectangles_after':after,'bytes':path.stat().st_size,'pixel_identical':True}))
