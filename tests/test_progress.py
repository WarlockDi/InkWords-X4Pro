from support import *

g=new_game();pump(g)
d=next(d for d in g.api.decks().values() if d.key=='iwdemo1')
g.g.store['iwdemo1_wrong.txt']='0:0 3\n0:1 2\n0:2 2'
for all in [False,True]:
    g.api.study.open(all,d)
    assert g.api.loading() and '正在准备' in g.texts()
    g.tap_label('返回');pump(g)
    assert not g.api.loading() and not g.api.error()
    g.api.study.open(all,d);pump(g)
    assert '开始复习' in g.texts()
    g.tap_label('返回')
g.tap_label('总结');g.tap_label('累计总结')
assert g.api.loading() and '统计词库' in g.texts()
g.tap_label('返回');pump(g);assert '今日总结' in g.texts()
g.tap_label('累计总结');pump(g)
assert any(s.startswith('已学 ') for s in g.texts())
assert not g.api.loading() and not g.api.error() and len(g.g.timers)==0
print('PASS public mistake/summary progress, cancel/retry/completion, no timer leak')
