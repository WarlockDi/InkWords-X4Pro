from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools/gamekit'))
import harness
from harness import Game
original=harness.lua54.LuaRuntime
harness.lua54.LuaRuntime=lambda **kw:original(max_memory=1024*1024,**kw)
STUB=r'''
fake_epoch=1794646800
ctx.clock.now=function()return {epoch_sec=fake_epoch,hour=9,minute=0,second=0}end
ctx.storage.list=function()local out={}for k in pairs(store)do out[#out+1]=k end return out end
ctx.storage.remove=function(self,n)store[n]=nil;return true end
timers={};writes=0
ctx.after=function(self,ms,fn)timers[#timers+1]=fn;return #timers end
ctx.budget={extend=function()end}
local gc=collectgarbage
ctx.gc={collect=function()gc('collect')end,count=function()return gc('count')*1024 end}
ctx.files={exists=function(self,n)return pyexists(n)end,read=function(self,n,o,l)return pyread(n,o,l)end,
 write=function(self,n,s)writes=writes+1;return pywrite(n,s)end}
ctx.package={open_text=function(self,n)
 local f=io.open(DATA..n,'rb');if not f then return nil end
 return {read_line=function()return f:read('l')end,close=function()f:close()end}
end}
function step_timer()local fn=table.remove(timers,1);if not fn then return false end;fn();return true end
collectgarbage=nil
'''
def new_game(files=None,fail=None):
    files={} if files is None else files
    def setup(h):
        g=h.L.globals();g.pyexists=lambda n:n in files
        g.pyread=lambda n,o,l:files[n].encode('utf-8')[int(o):int(o)+int(l)].decode('utf-8') if n in files else None
        def write(n,s):
            if n==fail:return False
            files[n]=s;return True
        g.pywrite=write
    app=ROOT/'apps/inkwords'
    g=Game(str(app),stubs='DATA=[['+(app/'data').as_posix()+'/]]\n'+STUB,before_load=setup)
    g.files=files
    return g
def pump(g,allow_error=False):
    for _ in range(30000):
        if not g.g.step_timer():break
    else:raise AssertionError('Loader did not finish')
    g.draw()
    if not allow_error:assert not g.api.error(),g.api.error()
    assert not g.api.loading()
    assert g.commands()<1024
