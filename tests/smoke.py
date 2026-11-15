from support import *

g=new_game();pump(g)
assert g.g.writes==3 and len(g.api.decks())==2
installed=dict(g.files)
g=new_game(installed);pump(g);assert g.g.writes==0 and g.files==installed
for target in ['iwdemo1_e000.txt','iwdemo1_examples.txt','library_v2.txt']:
    files={};bad=new_game(files,fail=target);pump(bad,allow_error=True)
    assert bad.api.boot_error() and 'library_v2.txt' not in files
    recovered=new_game(files);pump(recovered);assert len(recovered.api.decks())==2
# An existing but unreadable/empty catalogue must not be silently replaced.
bad=new_game({'library_v2.txt':''});pump(bad,allow_error=True)
assert bad.api.boot_error() and bad.g.writes==0
for mode in ['quiz','reverse','cloze','letters','match','flash','random']:
    g=new_game(dict(installed));pump(g);g.api.mode(mode);g.api.open('iwdemo1');pump(g)
    assert g.api.screen()=='study'
    if mode=='letters':
        q=g.api.exercise();s=q.spelling;assert len(s.slots)==2
        for j in range(1,len(s.slots)+1):
            char=s.word[int(s.slots[j])-1].lower()
            i=next(i for i,c in s.choices.items() if c==char);r=s.layout.buttons[i]
            g.tap(r.x+r.w/2,r.y+r.h/2);pump(g)
        assert q.correct and q.answered and s.layout.text==s.submitted
    g.key('back');pump(g);assert g.api.screen()=='decks'
    g.api.mode('letters');g.api.open('iwdemo1');pump(g);assert g.api.exercise().spelling
print('PASS: single-file first install; no overwrite; interrupted/failed-write retry; corrupt-catalogue protection; seven modes; answer and reopen; 1 MiB simulated heap ceiling')
