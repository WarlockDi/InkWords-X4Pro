from pathlib import Path
import sys,re,random,zlib

from lupa.lua54 import LuaRuntime
src=(Path(__file__).resolve().parents[1]/'apps/inkwords/src/main.lua').read_text(encoding='utf-8')
fn=src.split('function kit.study.digest(s)',1)[1].split('\nend',1)[0]
assert '2166136261' not in fn and '16777619' not in fn and '<<' not in fn and '~' not in fn
L=LuaRuntime(encoding=None)
L.execute(b'function bounded(n) assert(n>=0 and n<=131040 and n==math.floor(n));return n end')
# Check every intermediate arithmetic result against the safe integer envelope.
fn=fn.replace('a+s:byte(i)','bounded(a+s:byte(i))').replace('b+a','bounded(b+a)')
f=L.eval(('function(s)'+fn+'\nend').encode())
rng=random.Random(163)
samples=[b'',bytes(range(256)),b'\xff'*131041,'雅思真词汇 医学英语'.encode()]
samples += [rng.randbytes(rng.randrange(1,32768)) for _ in range(100)]
for raw in samples:
 expected=(f'{zlib.adler32(raw):08x}:{len(raw)}').encode();assert f(raw)==expected
print('PASS',len(samples),'digest vectors; every intermediate <=131040; reference checksum agrees')
