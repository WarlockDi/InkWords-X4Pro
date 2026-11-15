-- InkWords modifications Copyright (c) 2026 WarlockDi
-- Official: https://github.com/WarlockDi/InkWords-X4Pro
-- Derived from Omer Faruk Inel's touch-licorice-apps (MIT). See LICENSE.
-- Anki flashcards for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- Decks: the built-in English deck (this package's data section: en_info.txt, en_c000.txt ...),
-- "My cards", and every deck converted on a computer with apkg2cards.py and copied into the
-- app's user folder (ctx.files, API 2.9) or XTApps/anki/files/ (<prefix>_info.txt, <prefix>_c000.txt ...); a plain "front<TAB>back" .tsv
-- list copied there is a deck too. A card file line is "id<TAB>front<TAB>back" ("\n" for a line
-- break); every card file of a deck holds `per` cards, so a card is known by its place:
-- shard s, line l.
--
-- Read indexed 25-card blocks to bound memory usage on the device. A study
-- session reads the card file of the card it shows, and the progress of the cards of one card
-- file lives in a small file of its own (<key>_p000.txt: "line due interval ease reps lapses"),
-- so a rating rewrites a few kilobytes. <key>_st.txt keeps the next new card, today's new-card
-- count and the earliest due time of every progress file, so only the files with cards due are
-- read. Own cards: <key>_own.txt and <key>_pown.txt (by id); deleted cards: <key>_del.txt.
--
-- Scheduling is FSRS 4.5 (see "scheduling"): Again / Hard / Good / Easy, steps of minutes for
-- new and forgotten cards (they come back in the same session), then intervals from each card's
-- stability and difficulty. Progress saved by the SM-2 scheduler before v0.11 is read as FSRS.
--
-- Lock screen: long-press a deck, Lock screen. lockscreen.lua then shows its next cards from
-- lock_cards.txt, which this app rewrites when the deck list shows and when it is left.

local base_width=kit.width
local width_cache,width_entries={},0
kit.width=function(font,text)
  if not font then return base_width(font,text) end
  local c=width_cache[font]
  if c and c[text] then return c[text] end
  local value=base_width(font,text)
  if width_entries>=128 then width_cache={};width_entries=0;c=nil end
  if not c then c={};width_cache[font]=c end
  c[text]=value;width_entries=width_entries+1
  return value
end
local W, H = kit.W, kit.H
local BTN_Y, BTN_H = 704, 72
local TOP = 100
local LEARN_S = 20 * 60                -- due again within this: shown again in this session
local MAX_REVIEWS = 300                -- reviews taken into one session
local MAX_TSV = 300000                 -- a plain .tsv list is read whole
local MAX_IVL = 1000                   -- the longest interval, in days
local NEW_CHOICES = { 5, 10, 15, 20, 30, 50, 0 }
local ROW_H, ROWS = 84, 7

local settings = { new_per_day = 15 }
local decks = {}                       -- { key, name, source = 'package' | 'storage' | 'tsv' | 'own', file, cards, per, shards }
local screen = 'decks'                 -- decks | study | done
local deck, st = nil, nil              -- the open deck and its state
local own, own_prog = {}, {}           -- own cards { id, f, b } and their progress by id
local dels = {}                        -- "s:l" -> true
local queue = {}                       -- { s, l, new } (s = 'own', l = id for own cards)
local shown, scroll, max_scroll = false, 0, 0
local last = nil                       -- the last rating, for Undo
local page = 0
local suppress_up = false
local long_done = false
local msg, ERR = nil, nil
local storage_error=nil
local boot_task=nil
local boot_step=nil
local start_loading=nil
kit.flow={guard=0}
local boot_stage='正在准备'
local boot_error=nil
local boot_reads=0
local boot_quiet=false
local boot_initial=true
local management_busy=false
local management_confirm,show_settings
local request_visible_summaries=nil
local boot_serial=0
local function extend_budget()
  pcall(function() if ctx.budget then ctx.budget:extend() end end)
end
local function boot_checkpoint()
  if boot_task and coroutine.running()==boot_task then
    boot_reads=boot_reads+1
    coroutine.yield()
  end
end
local function release_memory()
  if kit.evict_prompt then kit.evict_prompt() end
  if ctx.gc and type(ctx.gc.collect)=='function' then pcall(function() ctx.gc:collect() end)
  elseif type(collectgarbage)=='function' then pcall(collectgarbage,'collect') end
end
local session = { done = 0 }

------------------------------------------------------------------ files

-- Two checked journal slots commit namespace and backup metadata together.
-- Old progress is retained in place; reset never copies a whole progress database into RAM.
local P={}
do
  local fields={'active','overrides','kind','backup_active','backup_overrides','book','backup_book_ns',
    'settings','order','modes','backup_settings','backup_order','backup_modes','time'}
  local prefs={['settings.txt']='settings',['new_word_order.txt']='order',['random_modes.txt']='modes'}
  local function digest(s)
    local a,b=1,0
    for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end
    return string.format('%08x',(b<<16)|a)
  end
  local function ns_ok(s) return s=='' or (type(s)=='string' and s:match('^r%d+_$')~=nil) end
  local function parse_map(s)
    local map={}
    for key,value in (s or ''):gmatch('([%w]+)=([^\n]*)\n') do
      if not ns_ok(value) then error('学习记录索引损坏。') end
      map[key]=value
    end
    return map
  end
  local function map_text(map)
    local rows={};for k,v in pairs(map) do rows[#rows+1]=k..'='..v..'\n' end
    table.sort(rows);return table.concat(rows)
  end
  local function encode(v)
    local rows={'INKWORDS_PROFILE_1\n',tostring(v.seq)..'\n'}
    for _,key in ipairs(fields) do
      local value=v[key]
      rows[#rows+1]=value==nil and '-1\n' or tostring(#value)..'\n'..value
    end
    local body=table.concat(rows);return body..'\n#'..digest(body)
  end
  local function decode(raw)
    if type(raw)~='string' or #raw>16000 then return nil end
    local body,hash=raw:match('^(.*)\n#(%x%x%x%x%x%x%x%x)$')
    if not body or digest(body)~=hash then return nil end
    local seq,pos=body:match('^INKWORDS_PROFILE_1\n(%d+)\n()')
    if not seq then return nil end
    local v={seq=tonumber(seq)}
    for _,key in ipairs(fields) do
      local ending=body:find('\n',pos,true);if not ending then return nil end
      local size=tonumber(body:sub(pos,ending-1));pos=ending+1
      if not size or size%1~=0 or size< -1 or size>16000 then return nil end
      if size>=0 then v[key]=body:sub(pos,pos+size-1);pos=pos+size end
    end
    if pos~=#body+1 or not ns_ok(v.active) or not ns_ok(v.backup_active or '') or not ns_ok(v.backup_book_ns or '') then return nil end
    if not ({['']=true,progress=true,settings=true,deck=true})[v.kind or ''] then return nil end
    return v
  end
  function P.load()
    if P.state then return P.state end
    local a=ctx.storage:read('profile_a.txt');local b=ctx.storage:read('profile_b.txt')
    local x,y=decode(a),decode(b)
    if not x and not y and (a or b) then error('学习记录管理文件损坏，请保留存储卡文件。') end
    P.state=(x and (not y or x.seq>y.seq)) and x or y or {seq=0,active='',overrides='',kind=''}
    P.map=parse_map(P.state.overrides);return P.state
  end
  function P.copy()
    local out={};for k,v in pairs(P.load()) do out[k]=v end;return out
  end
  function P.commit(v)
    v.seq=P.load().seq+1
    if P.state.seq==0 then
      local baseline=encode(P.state)
      ctx.storage:write('profile_b.txt',baseline)
      if ctx.storage:read('profile_b.txt')~=baseline then error('备份准备失败，原学习记录已保留。') end
    end
    local raw=encode(v);local name=v.seq%2==1 and 'profile_a.txt' or 'profile_b.txt'
    local result,why=ctx.storage:write(name,raw)
    if result==false or (result==nil and why~=nil) then error('设置保存失败，原学习记录已保留。') end
    if ctx.storage:read(name)~=raw then error('设置保存校验失败，原学习记录已保留。') end
    P.state=v;P.map=parse_map(v.overrides);return true
  end
  function P.book_of(name)
    local key,tail=name:match('^([%w]+)_(.-)%.txt$')
    if key and (tail=='st' or tail=='wrong' or tail=='pown' or tail:match('^p%d+$')) then return key end
  end
  function P.path(name)
    local v=P.load();local key=P.book_of(name)
    if key then return (P.map[key] or v.active)..name end
    if name=='daily.txt' or name=='recent_decks.txt' then return v.active..name end
    return name
  end
  function P.read(name)
    local key=prefs[name];local v=P.load()
    if key and v[key]~=nil then return v[key] end
    return ctx.storage:read(P.path(name))
  end
  function P.write(name,value)
    local key=prefs[name];local v=P.load()
    if key and v[key]~=nil then local copy=P.copy();copy[key]=value;return P.commit(copy) end
    return ctx.storage:write(P.path(name),value)
  end
  function P.remove(name) return ctx.storage:remove(P.path(name)) end
  function P.new_namespace()
    local number=P.load().seq+1
    local names=ctx.storage:list()
    if type(names)~='table' then error('无法检查学习记录，已取消重置。') end
    for _,name in ipairs(names) do
      boot_checkpoint()
      local used=type(name)=='string' and tonumber(name:match('^r(%d+)_'))
      if used and used>=number then number=used+1 end
    end
    return 'r'..number..'_'
  end
  function P.reset(kind,book,time)
    local v=P.copy();v.kind=kind;v.time=tostring(time)
    v.backup_active=nil;v.backup_overrides=nil;v.backup_book_ns=nil;v.book=nil
    v.backup_settings=nil;v.backup_order=nil;v.backup_modes=nil
    if kind=='progress' then
      v.backup_active=v.active;v.backup_overrides=v.overrides
      v.active=P.new_namespace();v.overrides=''
    elseif kind=='deck' then
      v.book=book;v.backup_book_ns=P.map[book] or v.active
      local overrides=parse_map(v.overrides);overrides[book]=P.new_namespace();v.overrides=map_text(overrides)
    elseif kind=='settings' then
      v.backup_settings=P.read('settings.txt') or ''
      v.backup_order=P.read('new_word_order.txt') or 'random'
      v.backup_modes=P.read('random_modes.txt') or 'quiz,reverse,cloze,match'
      v.settings='new_per_day=15\nlock_deck=\nrecent=\nrecent_mode=random'
      v.order='random';v.modes='quiz,reverse,cloze,match'
    else error('未知的重置类型。') end
    P.commit(v)
  end
  function P.restore()
    local v=P.copy()
    if v.kind=='progress' then v.active=v.backup_active;v.overrides=v.backup_overrides
    elseif v.kind=='deck' then local map=parse_map(v.overrides);map[v.book]=v.backup_book_ns;v.overrides=map_text(map)
    elseif v.kind=='settings' then v.settings=v.backup_settings;v.order=v.backup_order;v.modes=v.backup_modes
    else error('暂无可恢复的备份。') end
    v.kind='';v.backup_active=nil;v.backup_overrides=nil;v.backup_book_ns=nil
    v.backup_settings=nil;v.backup_order=nil;v.backup_modes=nil;v.book=nil;v.time=nil
    P.commit(v)
  end
  -- Remove only unreferenced reset namespaces. The two journal slots themselves are never removed.
  function P.cleanup()
    local v=P.load();local keep={[v.active]=true}
    for _,ns in pairs(P.map) do keep[ns]=true end
    if v.kind=='progress' then keep[v.backup_active]=true;for _,ns in pairs(parse_map(v.backup_overrides)) do keep[ns]=true end end
    if v.kind=='deck' then keep[v.backup_book_ns]=true end
    -- Also retain every namespace referenced by the fallback journal slot.
    for _,file in ipairs({'profile_a.txt','profile_b.txt'}) do
      local previous=decode(ctx.storage:read(file))
      if previous then
        keep[previous.active]=true
        for _,ns in pairs(parse_map(previous.overrides)) do keep[ns]=true end
        if previous.backup_active then keep[previous.backup_active]=true end
        if previous.backup_book_ns then keep[previous.backup_book_ns]=true end
        for _,ns in pairs(parse_map(previous.backup_overrides)) do keep[ns]=true end
      end
    end
    local ok,names=pcall(function()return ctx.storage:list()end)
    if ok and type(names)=='table' then
      for _,name in ipairs(names) do
        boot_checkpoint()
        if type(name)=='string' then
          local ns=name:match('^(r%d+_)')
          if ns and not keep[ns] then pcall(function()ctx.storage:remove(name)end) end
        end
      end
    end
  end
end

local small_cache={}
local small_keys={['recent_decks.txt']=true,['new_word_order.txt']=true,['random_modes.txt']=true}
local function sread(name)
  if small_keys[name] and small_cache[name]~=nil then return small_cache[name] or nil end
  boot_checkpoint()
  local ok, s = pcall(function() return P.read(name) end)
  local value=(ok and type(s)=='string') and s or nil
  if small_keys[name] then small_cache[name]=value or false end
  return value
end
local function swrite(name, s)
  boot_checkpoint()
  local measured,used=pcall(function()return ctx.gc:count()end)
  if measured and type(used)=='number' and used>=600000 then release_memory() end
  local ok,result,why=pcall(function() return P.write(name,s) end)
  if not ok or result==false or (result==nil and why~=nil) then storage_error='保存失败';error('保存失败，请检查存储空间并重新打开工具。') end
  if small_keys[name] then small_cache[name]=s end
end
local function sremove(name) pcall(function() P.remove(name) end) end
-- a file from the app's user folder (ctx.files, API 2.9: AppFiles/<app_id>, where the user
-- copies decks), read 64 KB at a time; a host that hands back the whole file is fine too
local function files_read(name)
  boot_checkpoint()
  local F = ctx.files
  if not F then return nil end
  local ok, t = pcall(function()
    if not F:exists(name) then return nil end
    local parts, off = {}, 0
    for _i = 1, 64 do
      local piece = F:read(name, off, 65536)
      if type(piece) ~= 'string' or piece == '' then break end
      if off+#piece>120000 then return nil end
      parts[#parts + 1] = piece
      off = off + #piece
      if #piece ~= 65536 then break end
    end
    return table.concat(parts)
  end)
  return (ok and type(t) == 'string' and t ~= '') and t or nil
end
-- names in the user folder and in the private files (decks copied the older way)
-- where copied decks go, for the help text
local function deck_folder()
  local F = ctx.files
  return (F and type(F.path) == 'string' and F.path ~= '') and F.path or 'XTApps/inkwords/files/'
end

-- a data-section file as one string (the package reader goes line by line)
local function kv(s) return kit.kv(s) end
local function unesc(s)
  return (s:gsub('\\(.)', function(ch) if ch == 'n' then return '\n' elseif ch == 't' then return '\t' end return ch end))
end
local function lines(text)
  if text:sub(-1) ~= '\n' then text = text .. '\n' end
  return text:gmatch('([^\n]*)\n')
end

------------------------------------------------------------------ time

local function now_sec()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and tonumber(t.epoch_sec) then return math.floor(tonumber(t.epoch_sec)) end
  local okm, ms = pcall(function() return ctx.clock:millis() end)
  return (okm and tonumber(ms)) and math.floor(tonumber(ms) / 1000) or 0
end

-- today's number in local time: the offset from the wall clock, rounded to a quarter hour
local function today()
  local ok, t = pcall(function() return ctx.clock:now() end)
  local e = now_sec()
  if ok and type(t) == 'table' and tonumber(t.hour) then
    local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
    local off = (wall - e % 86400) % 86400
    if off > 14 * 3600 then off = off - 86400 end
    off = math.floor(off / 900 + 0.5) * 900
    return (e + off) // 86400
  end
  return e // 86400
end

------------------------------------------------------------------ decks

local function load_settings()
  local t = kv(sread('settings.txt'))
  settings.recent = t.recent
  if P.load().seq>0 then settings.recent=(sread('recent_decks.txt') or ''):match('^([^\n]+)') end
  settings.recent_mode = ({random=true,quiz=true,reverse=true,cloze=true,match=true,flash=true})[t.recent_mode or ''] and t.recent_mode or 'random'
  local daily=tonumber(t.new_per_day) or 15
  settings.new_per_day=daily==0 and 0 or math.max(1,math.min(50,math.floor(daily)))
  settings.lock_deck = (t.lock_deck and t.lock_deck ~= '') and t.lock_deck or nil
end
function kit.flow.daily_label()
  return settings.new_per_day==0 and '无限制' or tostring(settings.new_per_day)
end
function kit.flow.allowance(used)
  return settings.new_per_day==0 and 50 or math.max(0,settings.new_per_day-used)
end
local function save_settings()
  swrite('settings.txt', 'new_per_day=' .. settings.new_per_day .. '\nlock_deck=' .. (settings.lock_deck or '') .. '\nrecent=' .. (settings.recent or '') .. '\nrecent_mode=' .. (settings.recent_mode or 'random'))
end

local function discover()
  decks={}
  local text=files_read('library_v2.txt')
  if not text then
    -- Install the bundled demo only when no catalogue exists. Commit it last,
    -- so interrupted first-run setup can retry without touching established books.
    local ok,present=pcall(function()return ctx.files:exists('library_v2.txt')end)
    if not ok or present then error('无法读取现有词库目录，请检查存储卡。') end
    for _,item in ipairs({{'demo_cards.txt','iwdemo1_e000.txt'},{'demo_examples.txt','iwdemo1_examples.txt'},{'demo_library.txt','library_v2.txt'}}) do
      boot_checkpoint()
      local reader=ctx.package:open_text(item[1]);if not reader then error('内置示例词库缺失。') end
      local chunks={};local size=0
      local loaded,why=pcall(function()
        while true do local line=reader:read_line();if not line then break end
          size=size+#line+1;if size>24000 then error('内置词库过大。') end
          chunks[#chunks+1]=line..'\n'
        end
      end)
      pcall(function()reader:close()end);if not loaded then error(why) end
      local value=table.concat(chunks)
      local wrote,result,why=pcall(function()return ctx.files:write(item[2],value)end)
      if not wrote or result==false or (result==nil and why~=nil) then error('无法准备词库，请检查存储卡可写及剩余空间。') end
      if files_read(item[2])~=value then error('词库写入校验失败，请检查存储卡后重开。') end
    end
    text=files_read('library_v2.txt')
  end
  text=text:gsub('\r','')
  local format=text:match('^([^\n]+)')
  if format~='INKWORDS_LIBRARY_2' and format~='INKWORDS_LIBRARY_3' then error('词库目录版本不正确，请重新复制更新包中的 AppFiles。') end
  local seen={}
  for line in text:gmatch('[^\n]+') do
    local key,name,cat,rank,cards,per,shards=line:match('^([%w]+)\t([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)$')
    if key then
      cards,per,shards=tonumber(cards),tonumber(per),tonumber(shards)
      if seen[key] or cards<1 or per<1 or per>600 or shards~=math.ceil(cards/per) then error('词库目录数据异常：'..key) end
      seen[key]=true
      decks[#decks+1]={key=key,name=name,category=cat,rank=tonumber(rank),source='indexed',cards=cards,per=per,shards=shards,physical=format=='INKWORDS_LIBRARY_3' and 250 or 750,suffix=format=='INKWORDS_LIBRARY_3' and 'e' or 'v'}
    elseif line~=format then error('词库目录内容不完整，请重新复制。') end
  end
  if #decks==0 then error('词库目录为空，请重新复制。') end
  decks[#decks+1]={key='my',name='我的词卡',source='own',cards=0,per=1,shards=0}
end

-- the cards of shard s: { { id, f, b } ... } (one shard cached)
-- Keep encoded lines, decode only the cards needed on screen. Stable line IDs preserve progress.
local cache = { key = nil, rows = nil }
local file_cache={name=nil,text=nil}
local function shard(d, s)
  local ck = d.key .. ':' .. s
  if cache.key == ck then return cache.rows end
  cache.key, cache.rows = nil, nil
  if type(collectgarbage)=='function' then pcall(collectgarbage,'collect') end
  if d.source=='indexed' then
    local block_index,block_rows=-1,nil
    local n=math.max(0,math.min(d.per,d.cards-s*d.per))
    local rows=setmetatable({}, {
      __len=function() return n end,
      __index=function(_,i)
        if type(i)~='number' or i<1 or i>n or i%1~=0 then return nil end
        local global=s*d.per+i-1;local block=global//25
        if block_index~=block then
          block_rows=nil;block_index=-1
          local physical=global//d.physical
          local filename=string.format('%s_%s%03d.txt',d.key,d.suffix,physical)
          if file_cache.name~=filename then
            file_cache.name=nil;file_cache.text=nil;release_memory()
            local data=files_read(filename)
            if type(data)~='string' or #data>120000 or data:sub(-1)~='\n' then error('词库内容缺失或不完整，请重新复制 AppFiles。') end
            file_cache.text=data;file_cache.name=filename
          end
          local text=file_cache.text
          if type(text)~='string' or #text>120000 or text:sub(-1)~='\n' then error('词库内容缺失或不完整，请重新复制 AppFiles。') end
          local content={};local row=0;local first=(block*25)%d.physical
          for line in text:gmatch('([^\n]*)\n') do
            if row>=first then content[#content+1]=line end
            row=row+1;if #content==25 then break end
          end
          block_rows=content;block_index=block
        end
        local line=block_rows[global%25+1]
        if not line then error('词条索引超出范围，请重新复制词库。') end
        local id,f,b=line:match('^([^\t]+)\t([^\t]+)\t(.*)$')
        if not id or tonumber(id)~=global+1 then error('词条与索引不匹配，请重新复制词库。') end
        return {id=id,f=unesc(f),b=unesc(b),_line=i-1,_shard=s}
      end
    })
    cache.key,cache.rows=ck,rows;return rows
  end
  error('词库类型不支持，请更新词库目录。')
end

local function slots(d)
  if d.source == 'tsv' then return #shard(d, 0) end
  if d.source == 'own' then return 0 end
  return d.shards * d.per
end

------------------------------------------------------------------ progress

local function pname(d, s) return s == 'own' and (d.key .. '_pown.txt') or string.format('%s_p%03d.txt', d.key, s) end

-- a progress line: "key due S D reps lapses last state"; the 6-field lines of the SM-2 scheduler
-- before v0.11 ("key due interval ease reps lapses") are read as FSRS records
local generations={}
local function generation(d)
  if generations[d.key]==nil then generations[d.key]=tonumber(kv(sread(d.key..'_st.txt')).generation) or 0 end
  return generations[d.key]
end
local function progress_text(d,sh)
  local raw=sread(pname(d,sh)) or ''
  local stored=tonumber(raw:match('^#generation=(%d+)')) or 0
  return stored==generation(d) and raw or ''
end
local function progress_header(d) return '#generation='..generation(d)..'\n' end
local function load_prog(d, s)
  local t = {}
  for line in lines(progress_text(d,s)) do
    local k, due, a, b, reps, lapses, last, state, evidence, spelling = line:match('^(%S+) (%-?%d+) ([%d%.]+) ([%d%.]+) (%d+) (%d+) ?(%-?%d*) ?([lr]?) ?(%d*) ?(%d*)$')
    if k then
      if s ~= 'own' then k = tonumber(k) end
      due, a, b = tonumber(due), tonumber(a), tonumber(b)
      if state ~= '' then
        t[k] = { due = due, s = a, d = b, reps = tonumber(reps), lapses = tonumber(lapses), last = tonumber(last) or due, state = state, evidence=tonumber(evidence) or 0, spelling=tonumber(spelling) or 0 }
      else
        -- SM-2: the interval is the stability, an ease of 1.3 .. 3.5 a difficulty of 10 .. 1
        local ivl, ease = a, b
        t[k] = { due = due, s = math.max(ivl, 1), d = math.max(1, math.min(10, 10 - (ease - 1.3) * 4)),
                 reps = tonumber(reps), lapses = tonumber(lapses),
                 last = due - math.floor(ivl * 86400), state = ivl >= 1 and 'r' or 'l' }
      end
    end
  end
  return t
end

local function fmt(x) return (string.format('%.2f', x):gsub('%.?0+$', '')) end

local function save_prog(d, s, t)
  local out, min = {}, nil
  for k, r in pairs(t) do
    out[#out + 1] = k .. ' ' .. r.due .. ' ' .. fmt(r.s) .. ' ' .. fmt(r.d) .. ' ' .. r.reps .. ' ' .. r.lapses .. ' ' .. r.last .. ' ' .. r.state .. ' ' .. (r.evidence or 0) .. ' ' .. (r.spelling or 0)
    if not min or r.due < min then min = r.due end
  end
  if #out == 0 then sremove(pname(d, s)) else swrite(pname(d, s), progress_header(d)..table.concat(out, '\n') .. '\n') end
  st.mins[s] = min
end

-- Single-card updates avoid allocating hundreds of scheduler records for every answer.
local function read_record(d,s,key)
  local wanted=tostring(key)..' '
  for line in lines(progress_text(d,s)) do
    if line:sub(1,#wanted)==wanted then
      local _,due,a,b,reps,lapses,last_time,state,evidence,spelling=line:match('^(%S+) (%-?%d+) ([%d%.]+) ([%d%.]+) (%d+) (%d+) ?(%-?%d*) ?([lr]?) ?(%d*) ?(%d*)$')
      if not due then return nil end
      due,a,b=tonumber(due),tonumber(a),tonumber(b)
      if state~='' then return {due=due,s=a,d=b,reps=tonumber(reps),lapses=tonumber(lapses),last=tonumber(last_time) or due,state=state,evidence=tonumber(evidence) or 0,spelling=tonumber(spelling) or 0} end
      return {due=due,s=math.max(a,1),d=math.max(1,math.min(10,10-(b-1.3)*4)),reps=tonumber(reps),lapses=tonumber(lapses),last=due-math.floor(a*86400),state=a>=1 and 'r' or 'l'}
    end
  end
end
local function progress_keys(d,s)
  local keys={}
  for line in lines(progress_text(d,s)) do
    local key=line:match('^(%S+) ')
    if key then key=s=='own' and key or tonumber(key);if key then keys[key]=true end end
  end
  return keys
end
local function save_record(d,s,key,rec)
  local out,present={},{};local min=nil
  for line in lines(progress_text(d,s)) do
    local k,due=line:match('^(%S+) (%-?%d+) ')
    if k and k~=tostring(key) then
      out[#out+1]=line;local index=s=='own' and k or tonumber(k)
      if index then present[index]=true end
      due=tonumber(due);min=min and math.min(min,due) or due
    end
  end
  if rec then
    out[#out+1]=key..' '..rec.due..' '..fmt(rec.s)..' '..fmt(rec.d)..' '..rec.reps..' '..rec.lapses..' '..rec.last..' '..rec.state..' '..(rec.evidence or 0)..' '..(rec.spelling or 0)
    present[key]=true;min=min and math.min(min,rec.due) or rec.due
  end
  swrite(pname(d,s),progress_header(d)..table.concat(out,'\n')..'\n')
  st.mins[s]=min
  if s=='own' then own_prog[key]=rec end
  return present
end

local function load_state(d)
  local t = kv(sread(d.key .. '_st.txt'))
  local s = { next = math.max(0,math.floor(tonumber(t.next) or 0)), day = tonumber(t.day) or 0, new = math.max(0,math.floor(tonumber(t.new) or 0)), mins = {} }
  for k, m in (t.mins or ''):gmatch('([%w]+):(%-?%d+)') do s.mins[k == 'own' and 'own' or tonumber(k)] = tonumber(m) end
  local td = today()
  if s.day ~= td then s.day, s.new = td, 0 end
  return s
end

local function save_state(d)
  d.summary_day=nil
  local m = {}
  for k, v in pairs(st.mins) do m[#m + 1] = k .. ':' .. v end
  table.sort(m)
  swrite(d.key .. '_st.txt', 'generation='..generation(d)..'\nnext=' .. st.next .. '\nday=' .. st.day .. '\nnew=' .. st.new .. '\nmins=' .. table.concat(m, ','))
end

local function load_own(d)
  own = {}
  for line in lines(sread(d.key .. '_own.txt') or '') do
    local id, f, b = line:match('^([^\t]+)\t([^\t]*)\t?(.*)$')
    if id then own[#own + 1] = { id = id, f = unesc(f), b = unesc(b) } end
  end
  own_prog = load_prog(d, 'own')
end

local function esc(s) return (s:gsub('\\', '\\\\'):gsub('\t', ' '):gsub('\r', ''):gsub('\n', '\\n')) end
local function save_own(d)
  local out = {}
  for _k, c in ipairs(own) do out[#out + 1] = c.id .. '\t' .. esc(c.f) .. '\t' .. esc(c.b) end
  if #out == 0 then sremove(d.key .. '_own.txt') else swrite(d.key .. '_own.txt', table.concat(out, '\n') .. '\n') end
end

local function load_dels(d)
  dels = {}
  for line in lines(sread(d.key .. '_del.txt') or '') do if line ~= '' then dels[line] = true end end
end
local function save_dels(d)
  local out = {}
  for k in pairs(dels) do out[#out + 1] = k end
  table.sort(out)
  if #out == 0 then sremove(d.key .. '_del.txt') else swrite(d.key .. '_del.txt', table.concat(out, '\n') .. '\n') end
end

------------------------------------------------------------------ scheduling

-- FSRS 4.5 (the open spaced-repetition scheduler Anki uses), with its default parameters. A card
-- has a stability S (days until recall drops to 90 %) and a difficulty D (1..10). Recall after
-- t days: R = (1 + 19/81 * t / S) ^ -0.5, so at 90 % retention the next interval is S days. New
-- and forgotten cards first go through steps of minutes in the same session (as in Anki).
local FW = { 0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474, 0.1367, 1.0461,
             2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755 }
local function w(i) return FW[i + 1] end
local DECAY, FACTOR, RETENTION = -0.5, 19 / 81, 0.9

local function clamp_d(x) return math.max(1, math.min(10, x)) end
local function init_d(g) return clamp_d(w(4) - w(5) * (g - 3)) end
local function next_d(d, g) return clamp_d(w(7) * w(4) + (1 - w(7)) * (d - w(6) * (g - 3))) end
local function recall(days, s) return (1 + FACTOR * days / s) ^ DECAY end
-- days until recall drops to RETENTION; at most MAX_IVL so that now + days * 86400 stays a
-- 32-bit number, which the reader's Lua may use
local function interval(s)
  local i = s / FACTOR * (RETENTION ^ (1 / DECAY) - 1)
  return math.max(1, math.min(MAX_IVL, math.floor(i + 0.5)))
end
local function recall_s(d, s, r, g)
  local hard = g == 2 and w(15) or 1
  local easy = g == 4 and w(16) or 1
  return s * (1 + math.exp(w(8)) * (11 - d) * s ^ (-w(9)) * (math.exp(w(10) * (1 - r)) - 1) * hard * easy)
end
local function forget_s(d, s, r)
  return math.min(s, w(11) * d ^ (-w(12)) * ((s + 1) ^ w(13) - 1) * math.exp(w(14) * (1 - r)))
end

-- a card's record after rating g (1 Again, 2 Hard, 3 Good, 4 Easy) at time now:
-- { due, s, d, reps, lapses, last (time of this review), state 'l' (learning steps) or 'r' }
local function schedule(rec, g, now)
  local s, d, state = rec.s, rec.d, rec.state
  local reps, lapses = (rec.reps or 0) + 1, rec.lapses or 0
  local due
  if not s then                                 -- a new card
    s, d = w(g - 1), init_d(g)
    if g == 4 then state, due = 'r', now + interval(s) * 86400
    else state, due = 'l', now + ({ 60, 6 * 60, 10 * 60 })[g] end
  elseif state == 'l' then                      -- in the steps: stability stays, then graduates
    d = next_d(d, g)
    if g == 1 then due = now + (lapses > 0 and 10 * 60 or 60)
    elseif g == 2 then due = now + 6 * 60
    else
      if g == 4 then s = s * w(16) end
      state, due = 'r', now + interval(s) * 86400
    end
  else                                          -- a review
    local r = recall(math.max(0, now - (rec.last or now)) / 86400, s)
    if g == 1 then
      lapses = lapses + 1
      s, d, state, due = forget_s(d, s, r), next_d(d, 1), 'l', now + 10 * 60
    else
      s, d = recall_s(d, s, r, g), next_d(d, g)
      due = now + interval(s) * 86400
    end
  end
  return { due = due, s = s, d = d, reps = reps, lapses = lapses, last = now, state = state }
end

-- Memory evidence is deliberately separate from total attempts and the scheduler estimate.
kit.memory={base=schedule}
function kit.memory.copy(rec)
  local out={};for k,v in pairs(rec) do out[k]=v end;return out
end
schedule=function(rec,g,now,kind)
  kind=kind or 'self'
  local previous=rec.s~=nil
  local ev=rec.evidence or 0;local spelling=rec.spelling or 0
  local last=rec.last or now
  local effective=math.max(now,last)
  local delayed=previous and now>=(rec.due or now) and now-last>=20*3600
  local out
  if g==1 then
    out=kit.memory.base(rec,g,effective);ev=0;spelling=0
  elseif previous and (now<(rec.due or now) or now<last or now-last<600 or (rec.state=='r' and not delayed) or kind=='elimination') then
    -- Early practice and elimination do not grow stability or graduate a learning card.
    out=kit.memory.copy(rec);out.reps=(rec.reps or 0)+1;out.last=effective
    out.due=math.max(rec.due or 0,effective+600)
  else
    out=kit.memory.base(rec,previous and g or math.min(g,3),effective)
    if previous and rec.state=='l' and g>=3 then out.due=math.min(out.due,effective+86400);out.s=math.min(out.s,1) end
    if previous and rec.state=='r' then
      local growth=(kind=='spelling' or kind=='self') and 2 or 1.5
      if g==2 then growth=1 end
      local days=math.max(1,math.floor((rec.s or 1)*growth+.5))
      out.due=math.min(out.due,effective+days*86400)
      out.s=math.min(out.s,days)
    end
    if delayed and g>=3 and kind~='elimination' then
      ev=math.min(31,ev+1)
      if kind=='spelling' then spelling=math.min(31,spelling+1) end
    end
  end
  if g==2 then ev=math.max(0,ev-1);spelling=math.max(0,spelling-1) end
  out.evidence=ev;out.spelling=spelling
  return out
end
function kit.memory.level(rec)
  if not rec or rec.state~='r' or (rec.evidence or 0)<1 then return 'easy' end
  if (rec.evidence or 0)>=3 and (rec.spelling or 0)>=1 and math.random(5)==1 then return 'hard' end
  return 'normal'
end

function kit.memory.expose(e)
  if not e then return end
  local rec=e.s=='own' and own_prog[e.l] or read_record(deck,e.s,e.l)
  if not rec then return end
  local now=now_sec()
  if now-(rec.last or now)<600 then return end
  local updated=kit.memory.copy(rec);updated.last=now
  save_record(deck,e.s,e.l,updated);save_state(deck)
end

local function span(sec)
  if sec < 3600 then return math.max(1, sec // 60) .. 'm' end
  local d = sec / 86400
  if d < 1 then return (sec // 3600) .. 'h' end
  if d < 31 then return math.floor(d + 0.5) .. 'd' end
  if d < 365 then return math.floor(d / 30 + 0.5) .. 'mo' end
  return fmt(math.floor(d / 36.5 + 0.5) / 10) .. 'y'
end

------------------------------------------------------------------ the queue

local function card_of(e)
  if e.s == 'own' then
    for _k, c in ipairs(own) do if c.id == e.l then return c end end
    return nil
  end
  local rows = shard(deck, e.s)
  local c = rows[e.l + 1]
  if c and c.f ~= '' then return c end
  return nil
end

local function rec_of(e)
  if e.s == 'own' then return own_prog[e.l] end
  return read_record(deck,e.s,e.l)
end

-- cards due now (reviews and learning), then new cards up to today's limit
-- Sample across shuffled shards without loading their card text or shuffling the full deck.
local memory_checks=0
local function collect_if_needed()
  memory_checks=memory_checks+1
  local ok,bytes=pcall(function() return ctx.gc:count() end)
  if (ok and type(bytes)=='number' and bytes>=650000) or (not ok and memory_checks%4==0) then release_memory() end
end
local function new_word_order() return sread('new_word_order.txt')=='sequence' and 'sequence' or 'random' end
local function random_new_cards(want)
  local total=deck.source=='tsv' and #shard(deck,0) or deck.cards
  local shard_count=math.ceil(total/deck.per)
  local indexes={};for i=0,shard_count-1 do indexes[#indexes+1]=i end
  for i=#indexes,2,-1 do local j=math.random(i);indexes[i],indexes[j]=indexes[j],indexes[i] end
  local selected,result={},{}
  local quota=math.max(1,math.ceil(want/math.max(1,shard_count)))
  for pass=1,2 do
    for _,shard_index in ipairs(indexes) do
      local keys=st.mins[shard_index] and progress_keys(deck,shard_index) or {}
      local candidates={};for l=0,math.min(deck.per,total-shard_index*deck.per)-1 do candidates[#candidates+1]=l end
      for i=#candidates,2,-1 do local j=math.random(i);candidates[i],candidates[j]=candidates[j],candidates[i] end
      local picked=0
      for candidate_index,line_index in ipairs(candidates) do
        if candidate_index%8==1 then boot_checkpoint();collect_if_needed() end
        local id=shard_index..':'..line_index
        if not keys[line_index] and not dels[id] and not selected[id] then
          local valid=true
          if deck.source=='tsv' then valid=shard(deck,shard_index)[line_index+1].f~='' end
          if valid and (not kit.flow.eligible or kit.flow.eligible({s=shard_index,l=line_index})) then
            result[#result+1]={s=shard_index,l=line_index,new=true};selected[id]=true;picked=picked+1
            if #result>=want then break end
            if pass==1 and picked>=quota then break end
          end
        end
      end
      if #result>=want then break end
    end
    if #result>=want then break end
  end
  for i=#result,2,-1 do local j=math.random(i);result[i],result[j]=result[j],result[i] end
  return result
end

local function build_queue()
  queue = {}
  local now = now_sec()
  local due = {}
  local function offer(e)
    if dels[e.s..':'..e.l] or (kit.flow.eligible and not kit.flow.eligible(e)) then return end
    local n=#due
    if n<MAX_REVIEWS then
      n=n+1;due[n]=e
      while n>1 do
        local parent=n//2;if due[parent].due>=e.due then break end
        due[n]=due[parent];n=parent;due[n]=e
      end
    elseif e.due<due[1].due then
      due[1]=e;local i=1
      while i*2<=n do
        local child=i*2
        if child<n and due[child+1].due>due[child].due then child=child+1 end
        if due[child].due<=e.due then break end
        due[i]=due[child];i=child;due[i]=e
      end
    end
  end
  for s, m in pairs(st.mins) do
    if m <= now then
      local t = s == 'own' and own_prog or load_prog(deck, s)
      for k, r in pairs(t) do if r.due <= now then offer({ s = s, l = k, due = r.due }) end end
    end
  end
  table.sort(due, function(a, b) return a.due < b.due end)
  for k = 1, math.min(#due, MAX_REVIEWS) do queue[#queue + 1] = due[k] end
  -- own cards not studied yet first, then the deck's next cards
  local want = kit.flow.allowance(st.new)
  local own_candidates={};for _,c in ipairs(own) do own_candidates[#own_candidates+1]=c end
  if new_word_order()=='random' then
    for i=#own_candidates,2,-1 do local j=math.random(i);own_candidates[i],own_candidates[j]=own_candidates[j],own_candidates[i] end
  end
  for _k, c in ipairs(own_candidates) do
    if want<=0 then break end
    if not own_prog[c.id] and not dels['own:'..c.id] and (not kit.flow.eligible or kit.flow.eligible({s='own',l=c.id})) then queue[#queue + 1] = { s = 'own', l = c.id, new = true }; want = want - 1 end
  end
  if deck.source~='own' and want>0 and new_word_order()=='random' then
    for _,e in ipairs(random_new_cards(want)) do queue[#queue+1]=e end
    return
  end
  if deck.source ~= 'own' then
    local checked_shard, checked_prog=nil,nil
    local k, total = st.next, slots(deck)
    while want > 0 and k < total do
      if k%25==0 then boot_checkpoint() end
      local s, l = k // deck.per, k % deck.per
      if not dels[s .. ':' .. l] then
        local rows = shard(deck, s)
        if #rows == 0 or l >= #rows then break end
        if checked_shard~=s then checked_shard=s;checked_prog=progress_keys(deck,s) end
        if not checked_prog[l] and (not kit.flow.eligible or kit.flow.eligible({s=s,l=l})) and rows[l + 1].f ~= '' then queue[#queue + 1] = { s = s, l = l, new = true, k = k }; want = want - 1 end
      end
      k = k + 1
    end
  end
end

kit.flow.refill=function()
  local active=deck
  start_loading('准备练习',function()
    if screen~='study' or deck~=active then return end
    build_queue();shown=false;scroll=0
    if screen~='study' or deck~=active then return end
    if #queue==0 then screen='done' end
  end,true)
end
local function counts()
  local n, r = 0, 0
  for _k, e in ipairs(queue) do if e.new then n = n + 1 else r = r + 1 end end
  return n, r
end

------------------------------------------------------------------ opening a deck

local function open_deck_sync(d)
  kit.flow.guard=0
  local recent={d.key}
  for key in (sread('recent_decks.txt') or ''):gmatch('[^\n]+') do
    if key~=d.key and #recent<5 then recent[#recent+1]=key end
  end
  swrite('recent_decks.txt',table.concat(recent,'\n'))
  kit.close()
  settings.recent=d.key; save_settings()
  deck = d
  st = load_state(d)
  load_own(d); load_dels(d)
  build_queue()
  screen, shown, scroll, last, session.done, msg = 'study', false, 0, nil, 0, nil
  if #queue == 0 then screen = 'done' end
  save_state(d)
end
local function open_deck(d)
  screen='decks'
  start_loading('准备练习',function() open_deck_sync(d) end)
end

-- due and new counts for the deck list, without opening the deck
local function summary(d)
  local day=today()
  if d.summary_day==day and d.summary_limit==settings.new_per_day and now_sec()<(d.summary_refresh_at or math.huge) then return d.due,(settings.new_per_day==0 and (d.summary_left or 0) or math.min(kit.flow.allowance(d.summary_new or 0),d.summary_left or 0)) end
  local s = load_state(d)
  local now, due, studied = now_sec(), 0, 0
  local refresh_at=math.huge
  for k, _ in pairs(s.mins) do
    for line in lines(progress_text(d,k)) do
      local _,at,_,_,reps,_,last_at=line:match('^(%S+) (%-?%d+) ([%d%.]+) ([%d%.]+) (%d+) (%d+) ?(%-?%d*)')
      if at then
        if tonumber(reps)>0 then studied=studied+1 end
        d.last_studied=math.max(d.last_studied or 0,tonumber(last_at) or 0)
        if tonumber(at)<=now then due=due+1 else refresh_at=math.min(refresh_at,tonumber(at)) end
      end
    end
  end
  d.summary_refresh_at=refresh_at
  d.studied=studied;d.summary_day=day;d.summary_limit=settings.new_per_day
  local left = d.source == 'own' and 0 or math.max(0, d.cards - s.next)
  d.summary_left=left;d.summary_new=s.new
  return due, (settings.new_per_day==0 and left or math.min(kit.flow.allowance(s.new),left))
end

-- the deck list's numbers, worked out when the list is shown, not on every redraw
local function refresh_summaries()
  -- At startup only the last book needs a progress summary. Other books are lazy.
  for _,d in ipairs(decks) do
    if d.key==settings.recent or d.summary_day then d.due,d.new=summary(d) end
  end
end

------------------------------------------------------------------ lock screen

-- lock_cards.txt for lockscreen.lua: the lock deck's name, then up to LOCK_CARDS cards as
-- "front<TAB>back" (then the pictures of a card with pictures): those due within a day, then the
-- next new ones. Written when the deck list
-- shows and when the app is left, so the lock screen follows the studying.
local LOCK_CARDS = 30
local function write_lock_cards()
  local d
  for _k, x in ipairs(decks) do if x.key == settings.lock_deck then d = x end end
  if not d then return end
  local s, now, out = load_state(d), now_sec(), {}
  local mine = {}
  for line in lines(sread(d.key .. '_own.txt') or '') do
    local id, f, b = line:match('^([^\t]+)\t([^\t]*)\t?(.*)$')
    if id then mine[id] = { f = f, b = b } end
  end
  local deleted = {}
  for line in lines(sread(d.key .. '_del.txt') or '') do deleted[line] = true end
  local function add(f, b, fs, bs)
    if f and f ~= '' and #out < LOCK_CARDS then
      local pic = (fs or '') ~= '' or (bs or '') ~= ''
      out[#out + 1] = f .. '\t' .. b .. (pic and ('\t' .. fs .. '\t' .. bs) or '')
    end
  end
  local function base(sh, l)
    local c = shard(d, sh)[l + 1]
    if c then add(esc(c.f), esc(c.b), c.fs, c.bs) end
  end
  local due = {}
  for k, m in pairs(s.mins) do
    if m <= now + 86400 then
      for l, r in pairs(load_prog(d, k)) do if r.due <= now + 86400 then due[#due + 1] = { s = k, l = l, due = r.due } end end
    end
  end
  table.sort(due, function(a, b) return a.due < b.due end)
  for _k, e in ipairs(due) do
    if e.s == 'own' then local c = mine[e.l]; if c then add(c.f, c.b) end else base(e.s, e.l) end
  end
  local k, total = s.next, slots(d)
  while #out < LOCK_CARDS and k < total and d.source ~= 'own' do
    local sh, l = k // d.per, k % d.per
    if not deleted[sh .. ':' .. l] then
      if l >= #shard(d, sh) then break end
      base(sh, l)
    end
    k = k + 1
  end
  for _id, c in pairs(mine) do add(c.f, c.b) end
  swrite('lock_cards.txt', d.name .. '\n' .. table.concat(out, '\n') .. '\n')
end

-- this deck on the lock screen, or (when it is already) off again
local function toggle_lock(d)
  local L = ctx.lockscreen
  if settings.lock_deck == d.key then
    settings.lock_deck = nil
    save_settings()
    sremove('lock_cards.txt')
    local okd, isdef = pcall(function() return L:is_default() end)
    if L and okd and isdef == true then pcall(function() L:clear_default() end) end
    msg = '锁屏词卡已关闭。'
    return
  end
  settings.lock_deck = d.key
  save_settings()
  write_lock_cards()
  if not L then msg = '当前固件不支持锁屏词卡。'; return end
  -- the firmware asks "Set as lock screen" itself (Settings > Display > Off wallpaper: Default)
  local okd, isdef = pcall(function() return L:is_default() end)
  if not (okd and isdef == true) then pcall(function() L:set_default() end) end
  msg = 'Lock screen: cards from ' .. d.name .. '.'
end

local function show_decks(skip_summary)
  -- Leaving a page invalidates its continuations, even for quiet refills.
  boot_task=nil;boot_serial=boot_serial+1;boot_error=nil;ERR=nil
  exercise=nil;queue={}
  screen,deck='decks',nil
  if not skip_summary and request_visible_summaries then request_visible_summaries() end
end

------------------------------------------------------------------ actions

-- Persistent per-answer statistics and wrong-word lists. Entries use existing shard IDs.
local function entry_id(e) return tostring(e.s)..':'..tostring(e.l) end
local function wrong_rows(d)
  local out={}
  for a,b,n in (sread(d.key..'_wrong.txt') or ''):gmatch('([^%s:]+):([^%s]+) (%d+)') do
    out[#out+1]={s=a=='own' and a or tonumber(a),l=a=='own' and b or tonumber(b),errors=tonumber(n)}
  end
  return out
end
local function write_wrong(d,rows)
  local out={};for _,e in ipairs(rows) do out[#out+1]=entry_id(e)..' '..e.errors end
  swrite(d.key..'_wrong.txt',table.concat(out,'\n'))
end
local function daily_stats()
  local t=kv(sread('daily.txt'))
  if tonumber(t.day)~=today() then return {day=today(),fresh=0,review=0,wrong=0} end
  return {day=today(),fresh=tonumber(t.fresh) or 0,review=tonumber(t.review) or 0,wrong=tonumber(t.wrong) or 0}
end
local function history_fields(e,r,before,kind)
  local t=kv(sread('daily.txt'));local day=today()
  local days=tonumber(t.days) or 0;local streak=tonumber(t.streak) or 0
  local lastday=tonumber(t.lastday)
  if lastday~=day then days=days+1;streak=lastday==day-1 and streak+1 or 1 end
  local attempts=tonumber(t.first_attempts) or 0;local correct=tonumber(t.first_correct) or 0
  local errors=t.errors or ''
  if tonumber(t.day)~=day then attempts=0;correct=0;errors='' end
  -- Use local midnight derived from the clock, including non-integer-hour time zones.
  local ok,clock=pcall(function()return ctx.clock:now()end)
  local midnight=now_sec()-(ok and clock and ((tonumber(clock.hour) or 0)*3600+(tonumber(clock.minute) or 0)*60+(tonumber(clock.second) or 0)) or now_sec()%86400)
  if kind~='self' and kind~='elimination' and (not before or (before.last or 0)<midnight) then
    attempts=attempts+1;if r~=1 then correct=correct+1 end
  end
  if r==1 then
    local id=deck.key..':'..entry_id(e);local items={}
    for old in errors:gmatch('[^,]+') do if old~=id then items[#items+1]=old end end
    items[#items+1]=id;while #items>60 do table.remove(items,1)end
    errors=table.concat(items,',')
  end
  return '\nsince='..(t.since or day)..'\ndays='..days..'\nstreak='..streak..'\nlastday='..day
    ..'\nreview_total='..((tonumber(t.review_total) or 0)+(before and 1 or 0))
    ..'\nfirst_attempts='..attempts..'\nfirst_correct='..correct..'\nerrors='..errors
end
local function record_result(e,r,before,kind)
  local extra=history_fields(e,r,before,kind)
  local t=daily_stats();local k=before and 'review' or 'fresh';t[k]=t[k]+1
  if r==1 then
    t.wrong=t.wrong+1
    local rows=wrong_rows(deck);local found=false
    for _,w in ipairs(rows) do if entry_id(w)==entry_id(e) then w.errors=w.errors+1;found=true;break end end
    if not found then rows[#rows+1]={s=e.s,l=e.l,errors=1} end
    write_wrong(deck,rows)
  end
  swrite('daily.txt','day='..t.day..'\nfresh='..t.fresh..'\nreview='..t.review..'\nwrong='..t.wrong..extra)
end
local function commit_entry(e,grade,kind)
  collect_if_needed()
  if st.day~=today() then st.day=today();st.new=0 end
  if type(collectgarbage)=='function' then pcall(collectgarbage,'collect') end
  local before=e.s=='own' and own_prog[e.l] or read_record(deck,e.s,e.l)
  last={e=e,before=before,next=st.next,new=st.new,queue={table.unpack(queue)},interactive=true,
    daily=sread('daily.txt') or '',wrong=sread(deck.key..'_wrong.txt') or ''}
  local rec=schedule(before or {},grade,now_sec(),kind)
  local present=save_record(deck,e.s,e.l,rec)
  if not before then st.new=st.new+1 end
  if deck.source~='own' then
    local total=slots(deck)
    while st.next<total and st.next//deck.per==e.s do
      local sh,ln=st.next//deck.per,st.next%deck.per
      if not present[ln] and not dels[sh..':'..ln] then break end
      st.next=st.next+1
    end
  end
  save_state(deck);record_result(e,grade,before,kind);session.done=session.done+1
  return rec
end

local function rate(r)
  collect_if_needed()
  if st.day~=today() then st.day=today();st.new=0 end
  local e = queue[1]
  if not e then return end
  local now = now_sec()
  local before = rec_of(e)
  local rec = schedule(before or {}, r, now,'self')
  last = { e = e, before = before, next = st.next, new = st.new, queue = { table.unpack(queue) }, daily=sread('daily.txt') or '',wrong=sread(deck.key..'_wrong.txt') or '' }
  record_result(e,r,before,'self')
  if e.s == 'own' then
    own_prog[e.l] = rec
    save_prog(deck, 'own', own_prog)
  else
    save_record(deck,e.s,e.l,rec)
  end
  if e.new then
    st.new = st.new + 1
    if e.k then st.next = math.max(st.next, e.k + 1) end
  end
  save_state(deck)
  table.remove(queue, 1)
  if rec.due <= now then table.insert(queue, math.min(#queue + 1, 4), { s = e.s, l = e.l }) end
  session.done = session.done + 1
  shown, scroll, msg = false, 0, nil
  kit.moved()
  if #queue == 0 then kit.flow.refill() end
end

local function undo()
  if not last then msg = '暂无可撤销记录。'; return end
  local e = last.e
  if e.s == 'own' then
    own_prog[e.l] = last.before
    save_prog(deck, 'own', own_prog)
  else
    save_record(deck,e.s,e.l,last.before)
  end
  if last.daily then swrite('daily.txt',last.daily);swrite(deck.key..'_wrong.txt',last.wrong) end
  st.next, st.new, queue = last.next, last.new, last.queue
  save_state(deck)
  session.done = math.max(0, session.done - 1)
  if last.interactive then build_queue() end
  last, shown, scroll, screen, msg = nil, false, 0, 'study', nil
end

local function delete_current()
  local e = queue[1]
  if not e then return end
  if e.s == 'own' then
    for k, c in ipairs(own) do if c.id == e.l then table.remove(own, k); break end end
    save_own(deck)
    own_prog[e.l] = nil
    save_prog(deck, 'own', own_prog)
  else
    dels[e.s .. ':' .. e.l] = true
    save_dels(deck)
    save_record(deck,e.s,e.l,nil)
    if e.new and e.k then st.next = math.max(st.next, e.k + 1) end
  end
  save_state(deck)
  for k = #queue, 1, -1 do
    if queue[k].s == e.s and queue[k].l == e.l then table.remove(queue, k) end
  end
  last, shown, scroll, msg = nil, false, 0, 'Card deleted.'
  if #queue == 0 then kit.flow.refill() end
end

local function add_card(d)
  local function ask(title, value, fn)
    ctx.input:text({ title = title, text = value or '', max_bytes = 256 }, function(c, s) pcall(fn, s) ; kit.refresh() end)
  end
  ask('New card: front', '', function(front)
    if not front or front == '' then return end
    ask('New card: back', '', function(back)
      if not back or back == '' then return end
      if deck ~= d then deck = d; st = load_state(d); load_own(d); load_dels(d) end
      local id = 'o' .. now_sec() .. math.random(10, 99)
      own[#own + 1] = { id = id, f = front, b = back }
      save_own(d)
      if screen == 'study' or screen == 'done' then
        queue[#queue + 1] = { s = 'own', l = id, new = true }
        if screen == 'done' then screen = 'study'; shown = false end
      end
      msg = '词卡已添加。'
      if screen == 'decks' then refresh_summaries() end
    end)
  end)
end

------------------------------------------------------------------ drawing

-- pictures: the reader draws text left to right only and refuses right-to-left text (Arabic,
-- Hebrew ...), so the converter on the tools site draws it. A drawn line of a side is "\1k,h,w,a"
-- (the side's k-th picture, its height and width; a = r / l: right or left aligned), and the
-- card's line carries two more fields, the front's and the back's pictures: 1-bit PNGs in base64,
-- comma separated. One picture per line, drawn whole (the reader refuses g:image's src on a
-- decoded picture). The host keeps 8 decoded pictures at most: only those of the shown card's
-- visible lines are kept, and when the 8 are taken the ones not on screen are let go.
local pics = { card = nil, img = {} }    -- img['f' .. k] / img['b' .. k] = picture or false
local function pics_release(keep)
  for key, im in pairs(pics.img) do
    if not (keep and keep[key]) then
      if im then pcall(function() im:release() end) end
      pics.img[key] = nil
    end
  end
end
-- the card on screen: the pictures of the one before are let go
local function pics_for(c)
  if pics.card ~= c then pics_release(nil); pics.card = c end
end
local function nth(list, k)
  local i = 0
  for b64 in (list or ''):gmatch('[^,]+') do
    i = i + 1
    if i == k then return b64 end
  end
end
local function decode(b64)
  local ok, im, err = pcall(function()
    local bytes = ctx.base64:decode(b64)
    if not bytes then return nil, 'invalid_argument' end
    return ctx.image:decode(bytes, { max_w = 480, max_h = 1024 })
  end)
  if ok then return im, err end
  return nil, 'error'
end
-- the k-th picture of a side of card c; frame: the pictures drawn in this frame
local function picture(c, side, k, frame)
  pics_for(c)
  local key = side .. k
  local v = pics.img[key]
  if v == nil then
    v = false
    local b64 = nth(side == 'f' and c.fs or c.bs, k)
    if b64 and ctx.image and ctx.base64 then
      local im, err = decode(b64)
      if not im and err == 'limit_exceeded' then pics_release(frame); im = decode(b64) end
      v = im or false
    end
    pics.img[key] = v
  end
  frame[key] = true
  return v or nil
end
local function pic_mark(l)
  local k, h, w, a = l:match('^\1(%d+),(%d+),(%d+),([lr])$')
  if k then return { k = tonumber(k), h = tonumber(h), w = tonumber(w), a = a } end
end

-- the card as rows of text: { text, font name, centred } (with pic and side for a drawn line)
-- and a divider (false) before the back
local wrapped_text
local function card_rows(c, with_back)
  local rows, maxw = {}, W - 40
  local first = true
  for para in (c.f .. '\n'):gmatch('([^\n]*)\n') do
    local fname = first and 'large' or 'medium'
    local m = pic_mark(para)
    if m then rows[#rows + 1] = { '', fname, true, pic = m, side = 'f' }
    else
      for _k, l in ipairs(wrapped_text(para, maxw, fname)) do rows[#rows + 1] = { l, fname, true } end
    end
    first = false
  end
  if with_back then
    rows[#rows + 1] = false
    for para in (c.b .. '\n'):gmatch('([^\n]*)\n') do
      local m = pic_mark(para)
      if m then rows[#rows + 1] = { '', 'medium', false, pic = m, side = 'b' }
      else
        for _k, l in ipairs(wrapped_text(para, maxw, 'medium')) do rows[#rows + 1] = { l, 'medium' } end
      end
    end
  end
  return rows
end

local function row_h(r)
  if not r then return 22 end
  return r.pic and r.pic.h or (kit.line_h(r[2]) + 4)
end

-- Original interactive exercises for the Licorice host. No MemDeck code used.
local exercise, mode = nil, 'quiz'
local choose_mode
local random_mix, previous_mode = false, nil
local function random_modes()
  local raw=sread('random_modes.txt');local out={}
  for _,m in ipairs({'quiz','reverse','cloze','match','letters'}) do
    if not raw or raw:find(m,1,true) then out[#out+1]=m end
  end
  if #out==0 then out={'quiz','reverse','cloze','match','letters'} end
  return out
end
-- Saved feedback remains on screen until Next; exclude it from pending counts.
local pending_counts=counts
counts=function()
  local n,r=pending_counts()
  if exercise then
    for _,e in ipairs(queue) do
      if exercise.saved and exercise.saved[entry_id(e)] then
        if e.new then n=n-1 else r=r-1 end
      end
    end
  end
  return math.max(0,n),math.max(0,r)
end
local mode_names = {random='随机组合', quiz='英选中', reverse='中选英', cloze='例句填空', letters='拼写单词', match='配对', flash='单词卡'}
local function word(c) return (c.f:match('^[^\n]+') or c.f):gsub('^%s+',''):gsub('%s+$','') end
local function meaning(c)
  local m = c.b:match('释义：([^\n]+)')
  if m then return m end
  for line in c.b:gmatch('[^\n]+') do
    if line:find('[\228-\233]') and not line:find('英音',1,true) then
      return (line:gsub('^.- | ',''):gsub(' | Chapter.*',''))
    end
  end
  return c.b:match('^[^\n]+') or c.b
end
local function shuffle(t)
  for i=#t,2,-1 do local j=math.random(i); t[i],t[j]=t[j],t[i] end
  return t
end
local function pool_for(c)
  local result, seenw, seenm = {c}, {[word(c):lower()]=true}, {[meaning(c)]=true}
  if mode=='match' then
    local pending={};for i=2,#queue do pending[#pending+1]=i end;shuffle(pending)
    for _,i in ipairs(pending) do
      local e=queue[i];local r=card_of(e)
      if r then
        local w,m=word(r),meaning(r)
        if not dels[tostring(queue[1].s)..':'..tostring(queue[1].s=='own' and r.id or i-1)] and w~='' and m~='' and not seenw[w:lower()] and not seenm[m] and not dels[entry_id(e)] then
          r._shard=e.s;r._line=e.l
          result[#result+1]=r;seenw[w:lower()]=true;seenm[m]=true
          if #result==4 then return result end
        end
      end
    end
  end
  local rows = queue[1].s == 'own' and own or shard(deck,queue[1].s)
  local progress=mode=='match' and (queue[1].s=='own' and own_prog or progress_keys(deck,queue[1].s)) or nil
  local pending_ids={}
  if mode=='match' then for _,e in ipairs(queue) do pending_ids[entry_id(e)]=true end end
  local indexes={}
  if mode=='match' and queue[1].s~='own' then
    local seen={}
    for i in pairs(progress) do if i>=0 and i<#rows then indexes[#indexes+1]=i+1;seen[i]=true end end
    for _,e in ipairs(queue) do
      if e.s==queue[1].s and not seen[e.l] then indexes[#indexes+1]=e.l+1;seen[e.l]=true end
    end
  else for i=1,#rows do indexes[i]=i end end
  shuffle(indexes)
  for _,i in ipairs(indexes) do
    local r=rows[i]; local w,m=word(r),meaning(r)
    local e={s=queue[1].s,l=queue[1].s=='own' and r.id or i-1}
    local allowed=mode~='match' or progress[e.l]~=nil or pending_ids[entry_id(e)]
    if allowed and not dels[entry_id(e)] and w~='' and m~='' and not seenw[w:lower()] and not seenm[m] then
      result[#result+1]=r; seenw[w:lower()]=true; seenm[m]=true
      if #result==4 then break end
    end
  end
  return result
end
local function sentence_translation(c,sentence)
  local previous=false
  for line in c.b:gmatch('[^\n]+') do
    if previous then
      local translated=line:match('^译文：(.+)') or line:match('^翻译：(.+)')
      if translated then return translated end
      if previous=='plain' and line:find('[\228-\233]') and not line:find('：',1,true) then return line end
    end
    previous=line==sentence and 'plain' or (line=='例句：'..sentence and 'tagged' or false)
  end
  return nil
end
local function cloze_for(c)
  local w=word(c); local sentence=c.b:match('例句：([^\n]+)')
  if sentence then
    local low,start=sentence:lower(),1
    while true do
      local a,b=low:find(w:lower(),start,true); if not a then break end
      if not low:sub(a-1,a-1):match('[a-z]') and not low:sub(b+1,b+1):match('[a-z]') then
        return sentence:sub(1,a-1)..' ______ '..sentence:sub(b+1), '例句填空：点选正确单词',sentence,sentence_translation(c,sentence)
      end
      start=b+1
    end
  end
  return nil, '暂无适用例句'
end
kit.flow.index={key=nil,bits=nil,failed=false}
function kit.flow.cloze_only()
  if not random_mix then return mode=='cloze' end
  local enabled=random_modes();return #enabled==1 and enabled[1]=='cloze'
end
kit.flow.eligible=function(e)
  local enabled=random_mix and random_modes() or nil
  if (not random_mix and mode=='letters') or (enabled and #enabled==1 and enabled[1]=='letters') then
    if e.s=='own' then local c=card_of(e);return c and kit.letters.accept(c) or false end
    local skip=kit.flow.spelling_skip
    if not skip or skip.key~=deck.key then return true end
    local index=e.s*deck.per+e.l
    return ((skip.bits:byte(index//8+1) or 0) & (1 << (index%8)))==0
  end
  if not kit.flow.cloze_only() then return true end
  if e.s~='own' then
    if kit.flow.index.key~=deck.key then
      kit.flow.index={key=deck.key,bits=nil,failed=false}
      local raw=files_read(deck.key..'_examples.txt')
      if raw then
        local count,bits=raw:gsub('\r',''):match('^INKWORDS_EXAMPLES_1\n(%d+)\n([0-9a-f]+)\n$')
        if tonumber(count)==deck.cards and #bits==math.ceil(deck.cards/4) then kit.flow.index.bits=bits end
      end
    end
    if kit.flow.index.bits and not kit.flow.index.failed then
      local index=e.s*deck.per+e.l
      if index>=deck.cards then return false end
      local value=tonumber(kit.flow.index.bits:sub(index//4+1,index//4+1),16)
      return value and (value & (1 << (index%4)))~=0 or false
    end
  end
  local card=card_of(e);return card and cloze_for(card)~=nil or false
end
local function prepare_exercise()
  if exercise or mode=='flash' or boot_task then return end
  if type(collectgarbage)=='function' then pcall(collectgarbage,'collect') end
  local c=queue[1] and card_of(queue[1]); if not c then return end
  if random_mix then
    local enabled=random_modes()
    local choices={}; for _,m in ipairs(enabled) do
      if (m~='cloze' or cloze_for(c)) and (m~='letters' or kit.letters.accept(c)) and (m~=previous_mode or #enabled==1) then choices[#choices+1]=m end
    end
    if #choices==0 then for _,m in ipairs(enabled)do if (m~='cloze' or cloze_for(c)) and (m~='letters' or kit.letters.accept(c)) then choices[#choices+1]=m end end end
    if #choices==0 then choices={'cloze'} end
    mode=choices[math.random(#choices)]; previous_mode=mode
  end
  if (mode=='cloze' and not cloze_for(c)) or (mode=='letters' and not kit.letters.accept(c)) then
    local active=deck
    if mode=='letters' and queue[1].s~='own' then
      local e=queue[1];local index=e.s*deck.per+e.l
      local skip=kit.flow.spelling_skip
      if not skip or skip.key~=deck.key then
        skip={key=deck.key,bits=string.rep(string.char(0),math.ceil(deck.cards/8))}
        kit.flow.spelling_skip=skip
      end
      local pos=index//8+1;local value=(skip.bits:byte(pos) or 0) | (1 << (index%8))
      skip.bits=skip.bits:sub(1,pos-1)..string.char(value)..skip.bits:sub(pos+1)
    end
    -- A stale optional index must fall back to checking text, never loop on one bad entry.
    if kit.flow.index.key==deck.key then kit.flow.index.failed=true end
    start_loading('准备练习',function()
      if screen~='study' or deck~=active or (mode~='cloze' and mode~='letters') then return end
      build_queue()
      if screen~='study' or deck~=active or (mode~='cloze' and mode~='letters') then return end
      if #queue==0 then screen='done' end
    end,true)
    return
  end
  local pool=mode=='letters' and {c} or pool_for(c)
  exercise={card=c, options={}, correct=false, answered=false, failed=false, pairs={}, selected=nil, matched={}, attempts=0}
  local q=exercise
  q.saved={};q.entries={};q.pair_failed={}
  local e=queue[1]
  for _,r in ipairs(pool) do
    local sh=r._shard or e.s
    q.entries[r]={s=sh,l=sh=='own' and r.id or r._line}
  end
  q.entries[c]={s=e.s,l=e.l}
  for i,r in ipairs(pool) do q.options[i]={label=mode=='quiz' and meaning(r) or word(r), right=i==1, card=r} end
  shuffle(q.options)
  q.prompt=mode=='reverse' and meaning(c) or word(c)
  q.hint=mode=='reverse' and '看中文，选择英文' or '看英文，选择中文释义'
  if mode=='cloze' then q.prompt,q.hint,q.sentence,q.translation=cloze_for(c) end

  if mode=='letters' then kit.letters.prepare(q) end
  if mode=='match' then
    q.left=shuffle(pool); q.right={}; for i,r in ipairs(q.left) do q.right[i]={card=r,index=i} end
    shuffle(q.right); q.hint='点击对应的英文和中文'
  end
end
wrapped_text=function(s,width,font)
  local result={};local f=kit.font(font or 'medium')
  for raw in (s..'\n'):gmatch('(.-)\n') do
    local offsets={}
    for pos in utf8.codes(raw) do offsets[#offsets+1]=pos end
    offsets[#offsets+1]=#raw+1
    local start=1;local count=#offsets-1
    if count==0 then result[#result+1]='' end
    while start<=count do
      local lo,hi,best=start,math.min(count,start+80),start
      while lo<=hi do
        local mid=(lo+hi)//2
        if kit.width(f,raw:sub(offsets[start],offsets[mid+1]-1))<=width then best=mid;lo=mid+1 else hi=mid-1 end
      end
      if best<count then
        for k=best,math.max(start,best-12),-1 do
          if raw:sub(offsets[k],offsets[k])==' ' then best=k;break end
        end
      end
      result[#result+1]=raw:sub(offsets[start],offsets[best+1]-1)
      start=best+1
    end
  end
  return result
end
local function text_block(gg,s,x,y,width,limit,font)
  local ls=wrapped_text(s,width,font);local f=kit.font(font or 'medium')
  for i=1,math.min(#ls,limit) do
    local line=ls[i]; if i==limit and #ls>limit then
      while #line>0 and kit.width(f,line..'…')>width do line=kit.drop_last(line) end
      line=line..'…'
    end
    gg:text(x,y+(i-1)*28,line,{font=kit.font(font or 'medium')})
  end
end
-- Keep all text inside the existing touch regions; no additional asset cache.
local function text_in_box(gg,text,x,y,w,h,font,center,limit,strong)
  font=font or 'medium'
  local ls=wrapped_text(text,w,font)
  local step=math.max(28,kit.line_h(font)+5)
  local count=math.min(#ls,limit or math.floor(h/step))
  local yy=y+math.max(0,(h-(count-1)*step-kit.line_h(font))//2)
  for i=1,count do
    local line=ls[i]
    if i==count and #ls>count then
      while #line>0 and kit.width(kit.font(font),line..'…')>w do line=kit.drop_last(line) end
      line=line..'…'
    end
    local xx=center and x+(w-kit.width(kit.font(font),line))//2 or x
    gg:text(xx,yy+(i-1)*step,line,{font=kit.font(font)})
    if strong then gg:text(xx+1,yy+(i-1)*step,line,{font=kit.font(font)}) end
  end
end
local word_font_ready=false
local function word_font(text,width)
  if not word_font_ready then
    word_font_ready=true
    local ok,f=pcall(function()return ctx.fonts:size(44)end)
    if ok and f then
      local valid,h=pcall(function()return f.line_height end)
      if valid and type(h)=='number' and h>=32 and h<=52 then
        local original=kit.font
        kit.font=function(name)if name=='word' then return f end;return original(name)end
      end
    end
  end
  if kit.font('word') and kit.width(kit.font('word'),text)<=width then return 'word' end
  return kit.width(kit.font('large'),text)<=width and 'large' or 'medium'
end
do
  local cache=nil
  kit.evict_prompt=function()cache=nil end
  local function prepare(text,w,h)
    if cache and cache.text==text and cache.w==w and cache.h==h then return not cache.unavailable and cache or nil end
    cache=nil;collect_if_needed()
    local function failed()cache={text=text,w=w,h=h,unavailable=true};return nil end
    local codes,needed,groups={},{},{};local cjk=false
    for _,code in utf8.codes(text) do
      if #codes>=90 then return failed() end
      codes[#codes+1]=code;if code>=0x3400 and code<=0x9fff then cjk=true end
      if code~=10 then needed[code]=true;groups[code//256]=true end
    end
    local glyphs={};local commands=0
    for block in pairs(groups) do
      local ok,reader=pcall(function()return ctx.package:open_text(string.format('uf%04x.txt',block))end)
      if not ok or not reader then return failed() end
      local success=pcall(function()
        while true do
          local line=reader:read_line();if not line then break end;line=line:gsub('\r$','')
          local key,value=line:match('^(%d+)\t(.*)$');key=tonumber(key)
          if needed[key] and (#value-1)%4==0 then glyphs[key]=value end
        end
      end)
      pcall(function()reader:close()end)
      if not success then return failed() end
    end
    for _,code in ipairs(codes) do
      if code~=10 then
        local glyph=glyphs[code];if not glyph then return failed() end
        commands=commands+(#glyph-1)//4
      end
    end
    if commands>820 then return failed() end
    for _,scale in ipairs({1,0.85,0.75}) do
      local rows,widths={{}},{0};local row=1
      for _,code in ipairs(codes) do
        local advance=code==10 and 0 or math.floor((glyphs[code]:byte(1)-32)*scale)
        if code==10 or widths[row]+advance>w then
          local moved={};local cut=nil
          if code~=10 then
            for j=#rows[row],math.max(1,#rows[row]//2),-1 do
              local c=rows[row][j]
              if c==32 or c==59 or c==0xff1b or c==0xff0c or c==44 then cut=j;break end
            end
          end
          if cut then
            for j=cut+1,#rows[row] do moved[#moved+1]=rows[row][j] end
            for j=#rows[row],cut+1,-1 do
              widths[row]=widths[row]-math.floor((glyphs[rows[row][j]]:byte(1)-32)*scale);rows[row][j]=nil
            end
          end
          row=row+1;rows[row]=moved;widths[row]=0
          for _,c in ipairs(moved)do widths[row]=widths[row]+math.floor((glyphs[c]:byte(1)-32)*scale)end
        end
        if code~=10 then rows[row][#rows[row]+1]=code;widths[row]=widths[row]+advance end
      end
      if #rows==2 and widths[2]<widths[1]*0.5 then
        local all={};for _,r in ipairs(rows)do for _,c in ipairs(r)do all[#all+1]=c end end
        local total=widths[1]+widths[2];local left,best,diff=0,nil,math.huge
        for j,c in ipairs(all)do
          left=left+math.floor((glyphs[c]:byte(1)-32)*scale)
          if j<#all and (c==32 or c==59 or c==0xff1b or c==0xff0c or c==44) and left<=w and total-left<=w and math.abs(total-2*left)<diff then
            best=j;diff=math.abs(total-2*left)
          end
        end
        if best then
          rows={{},{}};widths={0,0}
          for j,c in ipairs(all)do local r=j<=best and 1 or 2;rows[r][#rows[r]+1]=c;widths[r]=widths[r]+math.floor((glyphs[c]:byte(1)-32)*scale)end
        end
      end
      if #rows*52*scale<=h then
        local inkmin,inkmax=math.huge,0
        for i,r in ipairs(rows)do for _,code in ipairs(r)do
          local glyph=glyphs[code]
          for p=2,#glyph,4 do
            local gy= glyph:byte(p+1)-33;local gh=glyph:byte(p+3)-33
            inkmin=math.min(inkmin,math.floor((i-1)*52*scale)+math.floor(gy*scale))
            inkmax=math.max(inkmax,math.floor((i-1)*52*scale)+math.floor((gy+gh)*scale))
          end
        end end
        if inkmin==math.huge then inkmin=0 end
        cache={text=text,w=w,h=h,glyphs=glyphs,rows=rows,widths=widths,zoom=scale,inkmin=inkmin,inkmax=inkmax}
        return cache
      end
    end
    return failed()
  end
  kit.prompt_text=function(gg,text,x,y,w,h)
    local c=prepare(text,w,h);if not c then return false end
    local scale=c.zoom;local top=y+math.floor((h-(c.inkmax-c.inkmin))/2)-c.inkmin
    for i,row in ipairs(c.rows) do
      local xx=x+math.floor((w-c.widths[i])/2);local yy=top+math.floor((i-1)*52*scale)
      for _,code in ipairs(row) do
        local glyph=c.glyphs[code]
        for p=2,#glyph,4 do
          local gx,gy,gw,gh=glyph:byte(p,p+3);gx=gx-33;gy=gy-33;gw=gw-33;gh=gh-33
          local left=math.floor(gx*scale);local top=math.floor(gy*scale)
          gg:rect(xx+left,yy+top,math.max(1,math.floor((gx+gw)*scale)-left),math.max(1,math.floor((gy+gh)*scale)-top),{fill=true})
        end
        xx=xx+math.floor((glyph:byte(1)-32)*scale)
      end
    end
    return true
  end
end


local function pair_text(gg,text,x,y,w,h)
  local font=#wrapped_text(text,w,'medium')<=2 and 'medium' or 'small'
  text_in_box(gg,text,x,y,w,h,font,#wrapped_text(text,w,font)==1,font=='medium' and 2 or 3)
end
local function draw_prompt(gg,q)
  if q.sentence then
    if not q.display_prompt then
      local words,blank={},1
      for part in q.prompt:gmatch('%S+') do words[#words+1]=part;if part:find('______',1,true) then blank=#words end end
      local first,last=1,#words;local text=q.prompt
      while #wrapped_text(text,408,'small')>4 and first<last do
        if blank-first>last-blank then first=first+1 else last=last-1 end
        text=(first>1 and '… ' or '')..table.concat(words,' ',first,last)..(last<#words and ' …' or '')
      end
      q.display_prompt=text
    end
    if not q.sentence_font then
      q.sentence_font='small'
      for _,size in ipairs({'large','medium'})do
        if #wrapped_text(q.display_prompt,408,size)<=3 then q.sentence_font=size;break end
      end
    end
    local count=#wrapped_text(q.display_prompt,408,q.sentence_font)
    text_in_box(gg,q.display_prompt,36,140,408,122,q.sentence_font,count<=2,q.sentence_font=='small' and 4 or 3)
    return
  end
  if kit.prompt_text(gg,q.prompt,28,140,424,122) then return end
  local font=mode=='quiz' and word_font(q.prompt,408) or 'medium'
  if mode=='quiz' and kit.width(kit.font(font),q.prompt)>408 then font='medium' end
  if #wrapped_text(q.prompt,408,font)>3 then font='small' end
  local centered=mode=='quiz' or (mode=='reverse' and kit.width(kit.font(font),q.prompt)<=408)
  text_in_box(gg,q.prompt,36,144,408,112,font,centered,font=='small' and 4 or 3,mode=='quiz')
end
do
  local original_show=kit.show
  kit.show=function(m)
    local rows={}
    for _,row in ipairs(m.rows or {}) do
      if not (#row==2 and row[1][1]=='上一页' and row[2][1]=='下一页 1/1') then rows[#rows+1]=row end
    end
    m.rows=rows;original_show(m)
  end
  local function dialog_layout(m)
    local lines={}
    if m.title then for _,line in ipairs(wrapped_text(m.title,400,'medium')) do lines[#lines+1]={text=line,font='medium',height=34} end end
    if #lines>0 then lines[#lines].height=lines[#lines].height+10 end
    for _,text in ipairs(m.lines or {}) do
      for _,line in ipairs(wrapped_text(text,400,'small')) do lines[#lines+1]={text=line,font='small',height=25} end
    end
    local th=0;for _,line in ipairs(lines) do th=th+line.height end
    local h=40+th+#m.rows*64;local y=math.max(100,(800-h)//2)
    local buttons={};local by=y+22+th
    for _,row in ipairs(m.rows) do
      local bw=(400-(#row-1)*12)//#row
      for k,b in ipairs(row) do buttons[#buttons+1]={x=40+(k-1)*(bw+12),y=by,w=bw,h=54,b=b} end
      by=by+64
    end
    return lines,buttons,y,h
  end
  kit.draw_modal=function(gg)
    local m=kit.modal();local lines,buttons,y,h=dialog_layout(m)
    gg:rect(20,y,440,h,{fill=true,color=0});gg:rect(20,y,440,h,{line_width=1})
    local yy=y+20
    for _,line in ipairs(lines) do gg:text(40,yy,line.text,{font=kit.font(line.font)});yy=yy+line.height end
    for _,b in ipairs(buttons) do kit.button(gg,b.x,b.y,b.w,b.h,b.b[3]==false and '('..b.b[1]..')' or b.b[1],{line_width=1}) end
  end
  kit.tap_modal=function(x,y)
    local m=kit.modal();if not m then return false end
    local _,buttons,top,h=dialog_layout(m)
    for _,b in ipairs(buttons) do
      if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then if b.b[3]~=false then b.b[2]()end;return true end
    end
    if (y<top or y>top+h) and m.cancel then m.cancel()end
    return true
  end
end

local function save_answer(q,c,failed)
  local e=q.entries[c];if not e or q.saved[entry_id(e)] then return end
  local kind='recognition'
  if mode=='letters' then
    local n=select(2,word(c):gsub('[a-zA-Z]',''))
    kind=#q.spelling.slots/math.max(1,n)>=.3 and 'spelling' or 'guided'
  elseif mode=='match' then
    local remaining=0;for i=1,#q.left do if not q.matched[i] then remaining=remaining+1 end end
    if remaining<=1 then kind='elimination' end
  end
  e.rec=commit_entry(e,failed and 1 or 3,kind);q.saved[entry_id(e)]=e
end
-- Bounded, local-only spelling exercise; uses the existing portrait canvas and fonts.
kit.letters={}
function kit.letters.accept(c)
  local w=word(c)
  return #w>=2 and #w<=80 and not w:find("[^a-zA-Z '%-]") and select(2,w:gsub('[a-zA-Z]',''))>=2
end
kit.letters.recent={}
function kit.letters.prepare(q)
  local w=word(q.card);local all={}
  for i=1,#w do if w:sub(i,i):match('[a-zA-Z]') then all[#all+1]=i end end
  local e=q.entries[q.card];local rec=e and (e.s=='own' and own_prog[e.l] or read_record(deck,e.s,e.l))
  local level=kit.memory.level(rec)
  local positions={};for j,pos in ipairs(all) do if level=='hard' or j>1 then positions[#positions+1]=pos end end
  local cap=math.min(5,#all-1,#positions)
  local lo,hi
  if level=='easy' then lo=math.min(2,cap);hi=lo
  elseif level=='normal' then lo=math.max(1,math.floor(#all*.3));hi=math.max(lo,math.floor(#all*.4+.5))
  else lo=math.max(1,math.floor(#all*.5));hi=math.max(lo,math.floor(#all*.6+.5)) end
  lo=math.min(lo,cap);hi=math.min(hi,cap)
  local blanks=math.random(lo,hi)
  local previous
  for _,r in ipairs(kit.letters.recent) do if r.word==w:lower() then previous=r.mask;break end end
  local slots,mask
  for attempt=1,8 do
    shuffle(positions);slots={};for i=1,blanks do slots[i]=positions[i] end;table.sort(slots);mask=table.concat(slots,',')
    if mask~=previous then break end
  end
  if mask==previous and #positions>blanks then
    local used={};for _,pos in ipairs(slots) do used[pos]=true end
    for _,pos in ipairs(positions) do if not used[pos] then slots[#slots]=pos;break end end
    table.sort(slots);mask=table.concat(slots,',')
  end
  for i=#kit.letters.recent,1,-1 do if kit.letters.recent[i].word==w:lower() then table.remove(kit.letters.recent,i) end end
  kit.letters.recent[#kit.letters.recent+1]={word=w:lower(),mask=mask}
  if #kit.letters.recent>16 then table.remove(kit.letters.recent,1) end
  local s={word=w,slots=slots,filled={},choices={},active=1,level=level};local seen={}
  for _,pos in ipairs(slots) do local c=w:sub(pos,pos):lower();if not seen[c] then s.choices[#s.choices+1]=c;seen[c]=true end end
  local total=level=='easy' and math.random(4,5) or (level=='normal' and math.random(6,8) or 8)
  total=math.min(total,math.max(1,math.floor((W-32+12)/88))*2)
  local near,other={},{};local close={}
  for _,group in ipairs({'bdpq','iljt','mnuvw','ceos','fg','rt','az','aeiou'}) do
    for c in pairs(seen) do if group:find(c,1,true) then for x in group:gmatch('.') do close[x]=true end end end
  end
  for i=97,122 do local c=string.char(i);if not seen[c] then if close[c] then near[#near+1]=c else other[#other+1]=c end end end
  shuffle(near);shuffle(other)
  local missing=total-#s.choices;local near_count=math.min(#near,math.max(1,missing//2))
  for i=1,near_count do s.choices[#s.choices+1]=near[i] end
  for i=near_count+1,#near do other[#other+1]=near[i] end;shuffle(other)
  for i=1,total-#s.choices do s.choices[#s.choices+1]=other[i] end
  shuffle(s.choices);kit.letters.load_glyphs(s);q.spelling=s
end
-- Reuse the packaged Latin font. Cache at most eight glyphs for this question.
function kit.letters.load_glyphs(s)
  s.glyphs={};local needed,groups={},{};for _,c in ipairs(s.choices) do local code=utf8.codepoint(c);needed[code]=true;groups[code//256]=true end
  for block in pairs(groups) do
  local ok,reader=pcall(function()return ctx.package:open_text(string.format('uf%04x.txt',block))end)
  if not ok or not reader then return end
  pcall(function()
    while true do
      local line=reader:read_line();if not line then break end
      line=line:gsub('\r$','');local code,raw=line:match('^(%d+)\t(.*)$');code=tonumber(code)
      if needed[code] and #raw>1 and (#raw-1)%4==0 then
        local left,top,right,bottom=math.huge,math.huge,0,0
        for p=2,#raw,4 do
          local x,y,w,h=raw:byte(p,p+3);x=x-33;y=y-33;w=w-33;h=h-33
          left=math.min(left,math.floor(x*.75));top=math.min(top,math.floor(y*.75))
          right=math.max(right,math.floor((x+w)*.75));bottom=math.max(bottom,math.floor((y+h)*.75))
        end
        s.glyphs[utf8.char(code)]={raw=raw,x=left,y=top,w=right-left,h=bottom-top}
      end
    end
  end)
  pcall(function()reader:close()end)
  end
end
function kit.letters.draw_glyph(gg,s,c,r)
  local glyph=s.glyphs[c]
  if not glyph then
    local f=kit.font('large');gg:text(r.x+(r.w-kit.width(f,c))//2,r.y+(r.h-kit.line_h('large'))//2,c,{font=f});return
  end
  local ox=r.x+(r.w-glyph.w)//2-glyph.x;local oy=r.y+(r.h-glyph.h)//2-glyph.y
  for p=2,#glyph.raw,4 do
    local x,y,w,h=glyph.raw:byte(p,p+3);x=x-33;y=y-33;w=w-33;h=h-33
    local xx,yy=math.floor(x*.75),math.floor(y*.75)
    gg:rect(ox+xx,oy+yy,math.max(1,math.floor((x+w)*.75)-xx),math.max(1,math.floor((y+h)*.75)-yy),{fill=true})
  end
end
function kit.letters.layout(q)
  local s=q.spelling;local display={};local slots={}
  for j,p in ipairs(s.slots) do slots[p]=j end
  for i=1,#s.word do display[i]=slots[i] and (s.filled[slots[i]] or '  ') or s.word:sub(i,i) end
  local text=table.concat(display)
  if s.layout and s.layout.text==text then return s.layout end
  collect_if_needed()
  local l=s.layout
  if not l then
    local width=W-40;local height=170;local font=word_font(s.word,width)
    for _,name in ipairs({font,'large','medium','small'}) do
      local ranges={};local first,total=1,0;local f=kit.font(name)
      for i=1,#s.word do
        local w=slots[i] and math.max(kit.width(f,'W'),kit.width(f,'  ')) or kit.width(f,s.word:sub(i,i))
        if total+w>width and i>first then ranges[#ranges+1]={first,i-1};first=i;total=0 end
        total=total+w
      end
      ranges[#ranges+1]={first,#s.word}
      local step=kit.line_h(name)+math.max(14,math.ceil(kit.line_h(name)*.4))
      if #ranges*step<=height then l={font=name,ranges=ranges,step=step,cw=kit.width(f,'W'),buttons={}};break end
    end
    -- The accepted 80-character limit fits at the existing small font on this device.
    if not l then error('拼写单词字体尺寸不适配') end
    local cols=math.max(1,math.floor((W-32+12)/88));local bw=(W-32-(cols-1)*12)//cols
    for i=1,#s.choices do
      local row=(i-1)//cols;local n=math.min(cols,#s.choices-row*cols)
      l.buttons[i]={x=(W-(n*bw+(n-1)*12))//2+((i-1)%cols)*(bw+12),y=440+(2-math.ceil(#s.choices/cols))*38+row*76,w=bw,h=64}
    end
  end
  l.cells={};l.lines={};l.text=text
  local f=kit.font(l.font)
  for row,range in ipairs(l.ranges) do
    local widths,total={},0
    for i=range[1],range[2] do
      widths[i]=slots[i] and math.max(kit.width(f,'W'),kit.width(f,'  ')) or kit.width(f,s.word:sub(i,i))
      total=total+widths[i]
    end
    local x=(W-total)//2
    local y=136+(170-#l.ranges*l.step)//2+(row-1)*l.step
    for i=range[1],range[2] do
      l.cells[i]={x=x,y=y,w=widths[i]}
      if display[i]~='  ' then
        l.lines[#l.lines+1]={x=x+(widths[i]-kit.width(f,display[i]))//2,y=y,text=display[i]}
      end
      x=x+widths[i]
    end
  end
  s.layout=l;return l
end
function kit.letters.draw(gg,q)
  local s=q.spelling;local l=kit.letters.layout(q);local used={}
  -- Fixed cells keep the word and every underline still throughout the answer.
  for _,line in ipairs(l.lines) do gg:text(line.x,line.y,line.text,{font=kit.font(l.font)}) end
  for j,p in ipairs(s.slots) do
    local r=l.cells[p];local y=r.y+kit.line_h(l.font)+math.ceil(kit.line_h(l.font)*.35)
    if s.filled[j] then used[s.filled[j]]=true end
    gg:rect(r.x,y,math.max(2,r.w-1),2,{fill=true})
  end
  text_in_box(gg,meaning(q.card),24,312,W-48,104,'medium',true,3)
  for i,c in ipairs(s.choices) do
    local r=l.buttons[i]
    gg:rect(r.x,r.y,r.w,r.h,{line_width=used[c] and 3 or 1})
    kit.letters.draw_glyph(gg,s,c,r)
  end
  if q.answered then
    local label=q.correct and '回答正确：' or '正确拼写：'
    local small=kit.font('small');local label_width=kit.width(small,label)
    -- Keep label and reference on the same baseline; reduce only as needed.
    for _,name in ipairs({'large','medium','small'}) do
      local f=kit.font(name);local total=label_width+kit.width(f,s.word);local h=kit.line_h(name)
      if total<=W-40 then
        local x=(W-total)//2;local y=646-h//2
        gg:text(x,y+h-kit.line_h('small'),label,{font=small})
        gg:text(x+label_width,y,s.word,{font=f})
        break
      elseif name=='small' then
        -- Exceptionally long words continue naturally after the inline label.
        local lines=wrapped_text(label..s.word,W-40,'small');local step=h+2
        local y=646-((#lines-1)*step+h)//2
        for i,line in ipairs(lines) do gg:text((W-kit.width(small,line))//2,y+(i-1)*step,line,{font=small}) end
        break
      end
    end
  else kit.button(gg,12,614,W-24,56,'撤销') end
end
function kit.letters.tap(q,x,y)
  local s=q.spelling;local l=kit.letters.layout(q)
  if y>=704 then
    q.answered=true;q.failed=true;q.correct=false;save_answer(q,q.card,true);return
  end
  if x>=12 and x<W-12 and y>=614 and y<670 then
    local j=s.active
    if not s.filled[j] then j=j-1 end
    if j>=1 then s.filled[j]=nil;s.active=j end
    return
  end
  for j,pos in ipairs(s.slots) do
    local r=l.cells[pos]
    if x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+l.step then s.active=j;return end
  end
  for i,r in ipairs(l.buttons) do
    if x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h then
      s.filled[s.active]=s.choices[i]
      for j=1,#s.slots do if not s.filled[j] then s.active=j;return end end
      local result={};for p=1,#s.word do result[p]=s.word:sub(p,p) end
      for j,p in ipairs(s.slots) do result[p]=s.filled[j] end
      s.submitted=table.concat(result);q.correct=s.submitted:lower()==s.word:lower()
      q.failed=not q.correct;q.answered=true;save_answer(q,q.card,q.failed);return
    end
  end
end

function kit.letters.draw_menu(gg)
  if not kit.letters.menu_face then
    kit.letters.menu_face={choices={'菜','单'}};kit.letters.load_glyphs(kit.letters.menu_face)
  end
  gg:rect(W-112,16,100,56,{line_width=1})
  kit.letters.draw_glyph(gg,kit.letters.menu_face,'菜',{x=W-90,y=16,w=28,h=56})
  kit.letters.draw_glyph(gg,kit.letters.menu_face,'单',{x=W-62,y=16,w=28,h=56})
end

local function choose_answer(i)
  local q=exercise; if not q or q.unavailable or q.answered or not q.options[i] then return end
  save_answer(q,q.card,not q.options[i].right)
  q.selected=i; q.answered=true; q.correct=q.options[i].right; q.failed=not q.correct
end
local function finish_exercise(force)
  if not exercise or (not exercise.answered and not force) then return end
  for key,e in pairs(exercise.saved) do
    for i=#queue,1,-1 do if entry_id(queue[i])==key then table.remove(queue,i) end end
    local rec=e.rec
    if rec and rec.due<=now_sec() then queue[#queue+1]={s=e.s,l=e.l} end
  end
  exercise=nil;shown=false;scroll=0
  if #queue==0 then kit.flow.refill() end
end
local function draw_exercise(gg)
  prepare_exercise(); local q=exercise
  if not q then
    if boot_task then gg:text(20,160,'正在准备…',{font=kit.font('medium')}) end
    return
  end
  local label=mode=='cloze' and '例句填空' or mode=='match' and '中英配对' or mode_names[mode]
  gg:text(20,108,(random_mix and '随机组合 · ' or '')..label,{font=kit.font('small')})
  if mode=='letters' then kit.letters.draw(gg,q)
  elseif mode=='match' then
    for i,c in ipairs(q.left) do
      local y=156+(i-1)*112
      gg:rect(12,y,218,100,{line_width=q.selected==i and 3 or 1})
      pair_text(gg,(q.matched[i] and '✓ ' or '')..word(c),24,y+8,194,84)
    end
    for i,r in ipairs(q.right) do
      local y=156+(i-1)*112
      gg:rect(246,y,222,100,{line_width=q.selected_right==i and 3 or 1})
      pair_text(gg,(q.matched[r.index] and '✓ ' or '')..meaning(r.card),258,y+8,198,84)
    end
    if q.notice then text_block(gg,q.notice,16,620,448,2,'small') end
  else
    draw_prompt(gg,q)
    if #q.options<2 then
      text_block(gg,'词条不足，请切换单词卡。',18,300,444,2)
      kit.button(gg,12,704,456,72,'切换单词卡'); return
    end
    for i,o in ipairs(q.options) do
      local y=278+(i-1)*88
      local prefix=string.char(64+i)..'. '
      if q.answered and o.right then prefix='✓ '..prefix end
      gg:rect(12,y,456,80,{line_width=q.selected==i and 3 or 1})
      text_in_box(gg,prefix..o.label,26,y+8,428,64,'medium',false,2)
    end
    if q.answered then
      text_in_box(gg,q.correct and '回答正确！' or '答错了，稍后复习',20,636,440,46,'small',true,1)
    end
  end
  if q.answered then
    kit.button(gg,12,704,218,72,mode=='cloze' and '句子讲解' or '释义与例句')
    kit.button(gg,246,704,222,72,'下一题')
  elseif mode~='match' then kit.button(gg,12,704,456,72,'显示答案') end
end
local detail_layout=nil
local show_details,show_sentence
show_sentence=function(q,page)
  kit.memory.expose(q.entries[q.card])
  page=page or 1
  local content=q.sentence and ('完整句子：\n'..q.sentence..'\n中文译文：\n'..(q.translation or '词库未提供句子译文'))
    or ''
  content=content..'\n答案：'..word(q.card)..'\n'..meaning(q.card)
  local all=wrapped_text(content,400,'small');local pages=math.max(1,math.ceil(#all/9));page=math.min(page,pages)
  local visible={};for i=(page-1)*9+1,math.min(page*9,#all) do visible[#visible+1]=all[i] end
  kit.show({title='句子讲解',lines=visible,rows={
    {{'上一页',function() show_sentence(q,(page-2)%pages+1) end},{'下一页 '..page..'/'..pages,function() show_sentence(q,page%pages+1) end}},
    {{'查看各选项',function() show_details(q,q.selected or 1,1) end},{'返回题目',kit.close}}},cancel=kit.close})
end
show_details=function(q,index,page)
  local cards={}
  if mode=='match' then cards=q.left else for _,o in ipairs(q.options) do cards[#cards+1]=o.card end end
  index=index or 1;page=page or 1
  local c=cards[index];if not c then return end
  kit.memory.expose(q.entries[c])
  local label=''
  if mode~='match' and mode~='letters' then
    label='选项 '..string.char(64+index)..(q.options[index].right and ' · 正确答案' or '')..(q.selected==index and ' · 你的选择' or '')..'\n'
  end
  if not detail_layout or detail_layout.card~=c or detail_layout.label~=label then
    detail_layout={card=c,label=label,lines=wrapped_text(label..c.b,400,'small')}
  end
  local all=detail_layout.lines;local pages=math.max(1,math.ceil(#all/8))
  page=math.min(page,pages);local visible={}
  for i=(page-1)*8+1,math.min(page*8,#all) do visible[#visible+1]=all[i] end
  local rows={}
  if #cards>1 then rows[#rows+1]={
    {'上一词',function() show_details(q,(index-2)%#cards+1,1) end},
    {'下一词',function() show_details(q,index%#cards+1,1) end}} end
  if mode=='cloze' then rows[#rows+1]={{'句子讲解',function() show_sentence(q,1) end}} end
  rows[#rows+1]={
    {'页 '..page..'/'..pages,function() show_details(q,index,page%pages+1) end},
    {mode=='match' and '返回配对' or '返回',kit.close}}
  local title=word(c);local suffix=#cards>1 and ('  '..index..'/'..#cards) or ''
  while #title>0 and kit.width(kit.font('medium'),title..suffix)>390 do title=kit.drop_last(title) end
  kit.show({title=title..suffix,
    lines=visible,rows=rows,cancel=kit.close})
end
local function tap_exercise(x,y)
  if y>=704 and (not exercise or not exercise.answered) and (kit.now_ms() or kit.flow.guard)<kit.flow.guard then return end
  if not kit.modal() then detail_layout=nil end
  prepare_exercise(); local q=exercise; if not q then return end
  if mode~='match' and mode~='letters' and #q.options<2 then if y>=704 then mode='flash'; exercise=nil end; return end
  if q.answered then
    if y>=704 then
      if x>=240 then finish_exercise();kit.flow.guard=(kit.now_ms() or 0)+450
      elseif mode=='cloze' then show_sentence(q,1)
      else show_details(q,mode=='match' and 1 or (q.selected or 1),1) end
    elseif mode=='match' and y>=156 then
      local i=(y-156)//112+1
      if i<=#q.left and (y-156)%112<100 then
        if x<230 then show_details(q,i,1)
        elseif x>=246 then show_details(q,q.right[i].index,1) end
      end
    elseif mode~='match' and mode~='letters' and y>=278 and y<630 then
      local i=(y-278)//88+1
      if (y-278)%88<80 and q.options[i] then show_details(q,i,1) end
    end
    return
  end
  if mode=='letters' then kit.letters.tap(q,x,y)
  elseif mode=='match' then
    local i=(y-156)//112+1
    if y<156 or i>#q.left or (y-156)%112>=100 then return end
    if x<230 and q.matched[i] then show_details(q,i,1)
    elseif x>=246 and q.matched[q.right[i].index] then show_details(q,q.right[i].index,1)
    else
      q.notice=nil
      if x<230 then
        if q.selected==i then q.selected=nil else q.selected=i end
      elseif x>=246 then
        if q.selected_right==i then q.selected_right=nil else q.selected_right=i end
      else return end
      if q.selected and q.selected_right then
        local left,right=q.selected,q.selected_right
        q.attempts=q.attempts+1
        if q.right[right].index==left then
          save_answer(q,q.left[left],q.pair_failed[left])
          q.matched[left]=true;q.notice='配对正确'
          local n=0;for _ in pairs(q.matched) do n=n+1 end
          if n==#q.left then q.answered=true;q.correct=not q.failed;q.notice='本组完成' end
        else
          q.failed=true;q.pair_failed[left]=true
          save_answer(q,q.left[left],true)
          q.notice='配对不正确，请重试'
        end
        q.selected=nil;q.selected_right=nil
      end
    end
  elseif y>=704 then save_answer(q,q.card,true);q.answered=true; q.failed=true; q.correct=false
  elseif y>=278 and y<630 then
    local i=(y-278)//88+1; if (y-278)%88<80 then choose_answer(i) end
  end
end
choose_mode=function(d,switching)
  local rows={}
  for _,m in ipairs({'random','quiz','reverse','cloze','letters','match','flash'}) do
    local chosen=m
    rows[#rows+1]={{mode_names[chosen],function()
      kit.close()
      if switching and exercise then finish_exercise(true) end
      random_mix=chosen=='random'; previous_mode=nil
      settings.recent_mode=chosen
      mode=random_mix and 'quiz' or chosen; exercise=nil
      kit.flow.guard=0
      if switching then
        start_loading('准备练习',function()build_queue();exercise=nil;shown=false;scroll=0;screen=#queue>0 and 'study' or 'done';save_settings()end)
      else open_deck(d) end
    end}}
  end
  kit.show({title='练习模式',lines=wrapped_text(d.name,400,'small'),rows=rows,cancel=kit.close})
end


local function draw_study(gg)
  local e = queue[1]
  local c = e and card_of(e)
  if not c then
    -- a card that went missing (its file changed): skip it
    table.remove(queue, 1)
    if #queue == 0 then kit.flow.refill() end
    return
  end
  if not shown then
    gg:text(20,108,'单词卡',{font=kit.font('small')})
    if not kit.prompt_text(gg,c.f,28,180,424,360) then text_in_box(gg,c.f,32,180,416,360,word_font(c.f,416),#wrapped_text(c.f,416,'large')<=3,8,true) end
    kit.button(gg,12,BTN_Y,W-24,BTN_H,'显示答案',{font='large'})
    return
  end
  pics_for(c)
  local frame = {}
  local rows = card_rows(c, shown)
  local area = BTN_Y - 16 - TOP
  local total = 0
  for _k, r in ipairs(rows) do total = total + row_h(r) end
  max_scroll = 0
  -- skip whole rows from the top while scrolled
  local first, skipped, npics = 1, 0, 0
  for _k, r in ipairs(rows) do if r and r.pic then npics = npics + 1 end end
  while first <= #rows and skipped < scroll and (total - skipped > area or npics > 8) do
    local r = rows[first]
    if r and r.pic then npics = npics - 1 end
    skipped = skipped + row_h(r); first = first + 1
  end
  -- the rows that fit, with at most 8 pictures (the host's limit; the rest come with a swipe), and
  -- the pictures of the rows before let go first, so the new ones can be decoded
  local vis, n = {}, 0
  local y = TOP + 8
  for k = first, #rows do
    local r = rows[k]
    if y + row_h(r) > TOP + area or (r and r.pic and n == 8) then max_scroll = scroll + 1; break end
    if r and r.pic then n = n + 1; frame[r.side .. r.pic.k] = true end
    vis[#vis + 1] = { r, y }
    y = y + row_h(r)
  end
  pics_release(frame)
  for _k, v in ipairs(vis) do
    local r, y = v[1], v[2]
    if r and r.pic then
      local p = r.pic
      local im = picture(c, r.side, p.k, frame)
      local x = r[3] and (W - p.w) // 2 or (p.a == 'r' and W - 20 - p.w or 20)
      if im then gg:image(im, x, y)
      else gg:text(20, y, '(a picture this reader cannot show)', { font = kit.font('small') }) end
    elseif r then
      local f = kit.font(r[2])
      local x = r[3] and (W - kit.width(f, r[1])) // 2 or 20
      gg:text(x, y, r[1], { font = f })
    else
      gg:line(20, y + 10, W - 20, y + 10)
    end
  end
  if max_scroll > scroll then gg:text(W - 160, BTN_Y - 30, '上滑查看更多', { font = kit.font('small') }) end
  if scroll > 0 then gg:text(W - 160, TOP + 2, '下滑查看上文', { font = kit.font('small') }) end
  if not shown then
    kit.button(gg, 12, BTN_Y, W - 24, BTN_H, '显示答案', { font = 'large' })
  else
    local now = now_sec()
    local rec = rec_of(e) or {}
    local bw = math.floor((W - 24 - 3 * 8) / 4)
    for k, label in ipairs({ '重学', '困难', '记得', '熟悉' }) do
      local x = 12 + (k - 1) * (bw + 8)
      gg:rect(x, BTN_Y, bw, BTN_H, { line_width = 2 })
      local f, s = kit.font('medium'), kit.font('small')
      gg:text(x + (bw - kit.width(f, label)) // 2, BTN_Y + 10, label, { font = f })
      local t = span(schedule(rec, k, now,'self').due - now)
      gg:text(x + (bw - kit.width(s, t)) // 2, BTN_Y + 40, t, { font = s })
    end
  end
end

local function fit_label(s,width,font)
  local f=kit.font(font)
  if kit.width(f,s)<=width then return s end
  while #s>0 and kit.width(f,s..'…')>width do s=kit.drop_last(s) end
  return s..'…'
end
local library_query, favorites_only='',false
local favorite_cache=nil
local function is_favorite(d)
  if not favorite_cache then
    favorite_cache={}
    for key in (sread('favorites.txt') or ''):gmatch('[^\n]+') do favorite_cache[key]=true end
  end
  return favorite_cache[d.key]==true
end
local function toggle_favorite(d)
  local out={};local on=is_favorite(d)
  favorite_cache[d.key]=not on or nil
  for key in pairs(favorite_cache) do out[#out+1]=key end
  table.sort(out)
  swrite('favorites.txt',table.concat(out,'\n'));page=0
end
local function flat_library_view()
  local result,positions={},{}
  for i,d in ipairs(decks) do
    positions[d.key]=i
    if (not favorites_only or is_favorite(d)) and (library_query=='' or d.name:lower():find(library_query:lower(),1,true)) then
      result[#result+1]=d
    end
  end
  table.sort(result,function(a,b)
    if a.key==settings.recent then return b.key~=settings.recent end
    if b.key==settings.recent then return false end
    if is_favorite(a)~=is_favorite(b) then return is_favorite(a) end
    return positions[a.key]<positions[b.key]
  end)
  return result
end
local library_folder=nil
local folder_pages={}
local function navigate_folder(destination)
  folder_pages[library_folder or "home"]=page
  library_folder=destination
  page=folder_pages[destination or "home"] or 0
end
local category_names={'中考','高考','大学英语','四级','六级','专四','专八','考研','研究生','考博','雅思','托福','国际英语','英语专业教材','新概念英语','通用分级','GRE / GMAT / SAT / ACT','剑桥英语与等级考试','专业英语','我的与导入'}
local function category(d)
  for _,name in ipairs(category_names) do if d.category==name then return name end end
  local n=d.name:lower()
  if n:find('雅思',1,true) or n:find('ielts',1,true) then return '雅思' end
  if n:find('专四',1,true) or n:find('专八',1,true) then return '专四专八' end
  if n:find('四级',1,true) or n:find('六级',1,true) then return '四六级' end
  if n:find('考研',1,true) then return '考研' end
  if n:find('托福',1,true) or n:find('toefl',1,true) then return '托福' end
  if n:find('gre',1,true) or n:find('gmat',1,true) or n:find('sat',1,true) then return 'GRE / GMAT / SAT' end
  if n:find('小学',1,true) or n:find('初中',1,true) or n:find('高中',1,true) then return '中小学' end
  if n:find('商务',1,true) then return '商务英语' end
  if d.key=='en' or d.key=='wa7298' or n:find('cefr',1,true) then return '通用与分级' end
  return '我的与导入'
end
local function library_view()
  if library_query~='' or favorites_only then return flat_library_view() end
  local result={}
  local function folder(id,name,description)
    result[#result+1]={folder=id,key='folder:'..id,name=name,cards=0,description=description}
  end
  if library_folder then
    folder('home','回到分类','当前：'..library_folder)
    if library_folder=='最近练习' then
      local used={};local keys=sread('recent_decks.txt') or settings.recent or ''
      for key in keys:gmatch('[^\n]+') do
        for _,d in ipairs(decks) do if d.key==key and not used[key] and #result<6 then result[#result+1]=d;used[key]=true end end
      end
    else
      for _,d in ipairs(decks) do if category(d)==library_folder then result[#result+1]=d end end
      table.sort(result,function(a,b)
        if a.folder then return not b.folder end
        if b.folder then return false end
        local ar,br=a.rank or 100,b.rank or 100
        if ar~=br then return ar<br end
        if a.cards~=b.cards then return a.cards<b.cards end
        return a.key<b.key
      end)
    end
  else
    for _,d in ipairs(decks) do if d.key==settings.recent then result[#result+1]=d;break end end
    folder('最近练习','最近练习','最近学习的 5 个单词本')
    local counts={};for _,d in ipairs(decks) do local c=category(d);counts[c]=(counts[c] or 0)+1 end
    for _,name in ipairs(category_names) do if counts[name] then folder(name,name,counts[name]..' 个单词本') end end
  end
  return result
end

request_visible_summaries=function()
  if screen~='decks' or kit.modal() or (boot_task and not boot_quiet) then return end
  local view=library_view();local pending={}
  for i=page*ROWS+1,math.min(#view,(page+1)*ROWS) do
    local d=view[i]
    if d and not d.folder and (d.summary_day~=today() or now_sec()>=(d.summary_refresh_at or math.huge)) then pending[#pending+1]=d end
  end
  if #pending==0 then return end
  start_loading('更新当前页进度',function()
    for _,d in ipairs(pending) do
      d.due,d.new=summary(d)
      if d.source=='own' then
        d.cards=0;for line in lines(sread('my_own.txt') or '') do if line~='' then d.cards=d.cards+1 end end
      end
    end
  end,true)
end
local show_today
local random_settings
random_settings=function()
  local modes=random_modes();local on={};for _,m in ipairs(modes) do on[m]=true end
  local rows={}
  for _,m in ipairs({'quiz','reverse','cloze','match','letters'}) do
    local chosen=m
    rows[#rows+1]={{(on[m] and '✓ ' or '□ ')..mode_names[m],function()
      if on[chosen] and #modes==1 then return end
      on[chosen]=not on[chosen];local out={}
      for _,v in ipairs({'quiz','reverse','cloze','match','letters'}) do if on[v] then out[#out+1]=v end end
      swrite('random_modes.txt',table.concat(out,','));random_settings()
    end}}
  end
  rows[#rows+1]={{'完成',kit.close}}
  kit.show({title='自定义随机组合',lines=wrapped_text('至少选择一种题型。',400,'small'),rows=rows,cancel=kit.close})
end
local wrong_book
wrong_book=function(p)
  p=p or 1
  local entries={}
  for _,e in ipairs(wrong_rows(deck)) do
    if not dels[entry_id(e)] then entries[#entries+1]=e end
  end
  local pages=math.max(1,math.ceil(#entries/5));p=math.min(p,pages)
  local rows={}
  for i=(p-1)*5+1,math.min(p*5,#entries) do
    local e=entries[i];local c=card_of(e) or {f='词条不可用',b='原词条已不存在，可移出错词本。'}
    rows[#rows+1]={{fit_label(word(c),300,'medium')..' · 错'..e.errors,function()
      local ls=wrapped_text(c.b,400,'small');local detail_page=1
      local detail
      detail=function()
        kit.memory.expose(e)
        local visible={};for j=(detail_page-1)*8+1,math.min(detail_page*8,#ls) do visible[#visible+1]=ls[j] end
        kit.show({title=fit_label(word(c),390,'medium'),lines=visible,rows={
          {{'练习这个词',function()
            kit.close();exercise=nil;queue={{s=e.s,l=e.l}};screen='study';shown=false;scroll=0
          end},{'移出错词本',function()
            local remaining={};for _,w in ipairs(wrong_rows(deck)) do if entry_id(w)~=entry_id(e) then remaining[#remaining+1]=w end end
            write_wrong(deck,remaining);wrong_book(p)
          end}},
          {{'页 '..detail_page..'/'..math.max(1,math.ceil(#ls/8)),function() detail_page=detail_page%math.max(1,math.ceil(#ls/8))+1;detail() end},
           {'返回错词本',function() wrong_book(p) end}}},cancel=function() wrong_book(p) end})
      end
      detail()
    end}}
  end
  rows[#rows+1]={{'练习本页',function()
    if #entries==0 then return end
    kit.close();exercise=nil;queue={}
    for i=(p-1)*5+1,math.min(p*5,#entries) do queue[#queue+1]={s=entries[i].s,l=entries[i].l} end
    screen='study';shown=false;scroll=0
  end},{'页 '..p..'/'..pages,function() wrong_book(p%pages+1) end}}
  rows[#rows+1]={{'关闭',kit.close}}
  kit.show({title='错词本 · '..#entries..' 词',lines=#entries==0 and {'暂无错词。'} or {},rows=rows,cancel=kit.close})
end
local function confirm_reset_progress()
  management_confirm('deck',deck)
end

do
  local cumulative,books_page,today_errors
  local function summary_help()
    kit.show({title='统计说明',lines={
      '已学按词库内练习过的词条统计。',
      '不同词库可能包含同一个单词。',
      '天数与复习次数自1.0.2开始累计。',
      '首次答对率仅统计今日首次作答，',
      '不含单词卡自评。错题保留最近60词。',
      '已学不等于掌握；重置会影响统计。'},rows={{{'返回',function()show_today()end}}},cancel=kit.close})
  end
  local function review_group(d,entries)
    kit.close()
    start_loading('准备错词练习',function()
      open_deck_sync(d)
      local valid={}
      for _,e in ipairs(entries) do
        boot_checkpoint()
        if #valid<300 and not dels[entry_id(e)] and card_of(e) then valid[#valid+1]=e end
      end
      queue=valid;mode='quiz';random_mix=false;exercise=nil;shown=false;scroll=0
      screen=#queue>0 and 'study' or 'done'
    end)
  end
  today_errors=function(p)
    local t=kv(sread('daily.txt'));local groups,order={},{}
    if tonumber(t.day)==today() then
      for key,sh,line in (t.errors or ''):gmatch('([%w]+):([%w]+):([^,]+)') do
        if not groups[key] then groups[key]={};order[#order+1]=key end
        groups[key][#groups[key]+1]={s=sh=='own' and sh or tonumber(sh),l=sh=='own' and line or tonumber(line)}
      end
    end
    p=p or 1;local pages=math.max(1,math.ceil(#order/5));p=math.min(p,pages);local rows={}
    for i=(p-1)*5+1,math.min(p*5,#order) do
      local key=order[i]
      for _,d in ipairs(decks) do if d.key==key then
        local entries=groups[key]
        rows[#rows+1]={{fit_label(d.name,300,'medium')..' · '..#entries,function()review_group(d,entries)end}}
        break
      end end
    end
    rows[#rows+1]={{'上一页',function()today_errors((p-2)%pages+1)end},{'下一页 '..p..'/'..pages,function()today_errors(p%pages+1)end}}
    rows[#rows+1]={{'返回总结',function()show_today()end}}
    kit.show({title='今日错词',lines={#order==0 and '今天暂无错词。' or '按词库复习'},rows=rows,cancel=kit.close})
  end
  books_page=function(items,p)
    p=p or 1;local pages=math.max(1,math.ceil(#items/4));p=math.min(p,pages);local rows={}
    for i=(p-1)*4+1,math.min(p*4,#items) do
      local d=items[i]
      local n=d.studied or 0;local percent=d.cards>0 and math.min(100,n/d.cards*100) or 0
      rows[#rows+1]={{fit_label(d.name,290,'medium')..'  '..string.format('%.2f',percent)..'%',function()
        kit.show({title=fit_label(d.name,390,'medium'),lines={
          '已学 '..n..' / '..d.cards..' 词条',
          '进度 '..string.format('%.2f',percent)..'% · 待复习 '..(d.due or 0)},rows={
          {{'继续学习',function()kit.close();open_deck(d)end}},
          {{'复习错词',function()review_group(d,wrong_rows(d))end}},
          {{'返回进度',function()books_page(items,p)end}}},cancel=kit.close})
      end}}

    end
    rows[#rows+1]={{'上一页',function()books_page(items,(p-2)%pages+1)end},{'下一页 '..p..'/'..pages,function()books_page(items,p%pages+1)end}}
    rows[#rows+1]={{'返回累计',function()cumulative()end}}
    kit.show({title='各词库进度',lines=#items==0 and {'尚未开始学习。'} or {},rows=rows,cancel=kit.close})
  end
  cumulative=function()
    kit.close()
    start_loading('统计学习进度',function()
      local studied,due,wrong=0,0,0;local items={}
      for _,d in ipairs(decks) do
        boot_checkpoint();local count=summary(d);d.due=count
        studied=studied+(d.studied or 0);due=due+count
        wrong=wrong+#wrong_rows(d)
        if (d.studied or 0)>0 then items[#items+1]=d end
      end
      local t=kv(sread('daily.txt'));local lastday=tonumber(t.lastday);local streak=tonumber(t.streak) or 0
      if not lastday or lastday<today()-1 then streak=0 end
      kit.show({title='累计学习',lines={
        '已学 '..studied..' 词条 · '..#items..' 本词库',
        '待复习 '..due..' · 错词 '..wrong,
        '学习 '..(tonumber(t.days) or 0)..' 天 · 连续 '..streak..' 天',
        '累计复习 '..(tonumber(t.review_total) or 0)..' 次'},rows={
        {{'各词库进度',function()books_page(items)end}},
        {{'今日错词',function()today_errors()end},{'统计说明',summary_help}},
        {{'今日',function()show_today()end},{'关闭',kit.close}}},cancel=kit.close})
    end)
  end
  show_today=function()
    local t=daily_stats();local raw=kv(sread('daily.txt'));local attempts=tonumber(raw.day)==today() and (tonumber(raw.first_attempts) or 0) or 0
    local correct=tonumber(raw.first_correct) or 0
    local rate=attempts>0 and string.format('%.0f%%',correct/attempts*100) or '暂无记录'
    kit.show({title='今日学习',lines={'新学 '..t.fresh..' 词条','复习 '..t.review..' 次 · 答错 '..t.wrong..' 次','首次答对率 '..rate},rows={
      {{'复习今日错词',function()today_errors()end}},
      {{'累计总结',function()cumulative()end},{'统计说明',summary_help}},
      {{'关闭',kit.close}}},cancel=kit.close})
  end
end

local toggle_new_order
toggle_new_order=function()
  local current=new_word_order()
  local function select(value)
    swrite('new_word_order.txt',value)
    toggle_new_order()
  end
  kit.show({title='新词顺序',lines={'当前：'..(current=='random' and '随机' or '顺序'),'下次进入词库生效。'},rows={
    {{'随机'..(current=='random' and '（已选）' or ''),function() select('random') end}},
    {{'顺序'..(current=='sequence' and '（已选）' or ''),function() select('sequence') end}},
    {{'完成',kit.close}}},cancel=kit.close})
end
do
  local manage_menu,show_daily,run_management
  local function reload_management(target)
    small_cache={};generations={};favorite_cache=nil
    cache.key=nil;cache.rows=nil;file_cache.name=nil;file_cache.text=nil
    exercise=nil;last=nil;queue={};own={};own_prog={};dels={}
    library_query='';favorites_only=false;library_folder=nil;folder_pages={};page=0
    load_settings();screen='decks';deck=nil;session.done=0
    st=target and load_state(target) or nil
    for _,d in ipairs(decks) do d.summary_day=nil;d.studied=nil;d.due=nil;d.new=nil;d.last_studied=nil end
    release_memory()
  end
  run_management=function(kind,target)
    kit.close();management_busy=true;screen='decks'
    start_loading('管理学习记录',function()
      local ok,err=pcall(function()
        if kind=='restore' then P.restore() else P.reset(kind,target and target.key,now_sec()) end
        reload_management(target)
        P.cleanup()
      end)
      management_busy=false
      if not ok then error(err) end
      local title=kind=='restore' and '备份已恢复' or kind=='settings' and '已恢复默认设置' or '进度已重置'
      local rows={}
      if kind=='deck' then rows[#rows+1]={{'开始学习',function()open_deck(target)end}} end
      rows[#rows+1]={{'回到词库',function()kit.close();show_decks()end}}
      kit.show({title=title,lines={kind=='restore' and '已恢复重置前的记录。' or '可在设置中恢复备份。'},rows=rows,cancel=function()kit.close();show_decks()end})
    end)
  end
  management_confirm=function(kind,target)
    local titles={progress='重置全部学习进度？',settings='恢复默认设置？',deck='确定重置进度吗？',restore='恢复上次备份？'}
    local descriptions={
      progress={'清空所有词库进度、错词本、','学习统计和最近练习。','保留词库、个人词卡、收藏和设置。'},
      settings={'恢复每日新词15、随机新词顺序、','全部组合题型及默认练习偏好。','保留全部学习进度、词卡和收藏。'},
      deck={target and fit_label(target.name,390,'small') or '', '只重置这本词库的进度和错词本。','保留词卡、收藏、统计和其他词库。'},
      restore={'将覆盖上次重置范围内的新记录。','其他内容保持不变。','恢复成功后，该备份入口将清空。'}
    }
    local lines_=descriptions[kind]
    if kind~='restore' then lines_[#lines_+1]='保留最近一次重置前的备份。' end
    kit.show({title=titles[kind],lines=lines_,rows={{{'取消',kit.close},{kind=='restore' and '确定恢复' or '确定重置',function()run_management(kind,target)end}}},cancel=kit.close})
  end
  manage_menu=function()
    local kind=P.load().kind
    local names={progress='全部学习进度',settings='偏好设置',deck='单本词库进度'}
    kit.show({title='备份与重置',lines={names[kind] and ('上次备份：'..names[kind]) or '暂无重置备份。','备份保存在本机；卸载应用会丢失。'},rows={
      {{'重置全部学习进度',function()management_confirm('progress')end}},
      {{'恢复默认设置',function()management_confirm('settings')end}},
      {{'恢复上次备份',function()management_confirm('restore')end,kind~=''}},
      {{'返回设置',function()show_settings()end}}
    },cancel=function()show_settings()end})
  end
  show_daily=function()
    local rows={}
    for i=1,#NEW_CHOICES,2 do
      local row={}
      for j=i,math.min(i+1,#NEW_CHOICES) do
        local n=NEW_CHOICES[j]
        row[#row+1]={(n==0 and '无限制' or tostring(n))..(n==settings.new_per_day and '（已选）' or ''),function()settings.new_per_day=n;save_settings();show_daily()end}
      end
      rows[#rows+1]=row
    end
    rows[#rows+1]={{'返回设置',function()show_settings()end}}
    kit.show({title='每日新词数量',lines={'每本词库的每日上限'},rows=rows,cancel=function()show_settings()end})
  end
  show_settings=function()
    kit.show({title='设置',rows={
      {{'每日新词：'..kit.flow.daily_label(),show_daily}},
      {{'新词顺序：'..(new_word_order()=='random' and '随机' or '顺序'),toggle_new_order}},
      {{'自定义随机组合',random_settings}},
      {{'备份与重置',manage_menu}},
      {{'关于墨词',function()
        kit.show({title='墨词 InkWords',lines={'版本：1.4.6 公开版','作者：WarlockDi','e99866@outlook.com','已安装词库：'..(#decks-1)..' 本','适用设备：阅星瞳 X4 Pro','中英文练习 · 本地保存进度'},rows={{{'返回设置',function()show_settings()end}}},cancel=function()show_settings()end})
      end}},
      {{'关闭',kit.close}}
    },cancel=kit.close})
  end
end

local function library_tools()
  kit.show({title='更多',rows={
    {{'学习总结',show_today}},
    {{'搜索词库',function()
      kit.close();ctx.input:text({title='搜索词库名称',text=library_query,max_bytes=100},function(_,s)
        if s then library_query=s;page=0 end;request_visible_summaries();kit.refresh()
      end)
    end},{favorites_only and '显示全部' or '只看收藏',function() favorites_only=not favorites_only;page=0;kit.close() end}},
    {{'清除搜索',function() library_query='';favorites_only=false;page=0;kit.close() end}},
{{'关闭',kit.close}}
  },cancel=kit.close})
end

local function draw_decks(gg)
  local decks=library_view()
  if #decks==0 then gg:text(24,140,'未找到词库，可在“更多”中清除筛选。',{font=kit.font('small')}) end
  local first=page*ROWS+1
  for k=first,math.min(#decks,first+ROWS-1) do
    local d=decks[k];local y=TOP+(k-first)*ROW_H
    gg:line(24,y+ROW_H-4,W-24,y+ROW_H-4)
    local name=(d.key==settings.recent and '继续学习 · ' or '')..(is_favorite(d) and '★ ' or '')..d.name
    gg:text(26,y+14,fit_label(name,W-48,'medium'),{font=kit.font('medium')})
    local n=math.min(d.cards,d.studied or 0)
    local percent=d.cards>0 and n/d.cards*100 or 0
    local info='已学 '..n..'/'..d.cards..' ('..string.format('%.2f',percent)..'%)  待复习 '..(d.due or 0)
    if d.studied==nil and not d.folder then info=d.cards..' 词条 · 正在读取学习进度' end
    if d.folder then info=d.description or '点开查看词库' end
    gg:text(26,y+46,fit_label(info,W-48,'small'),{font=kit.font('small')})
  end
end
local help_pages={
  {'学习与进度','首页可继续上次学习。','最近练习保留最近五本词书。','菜单可切换题型、查看学习总结。','已学百分比不代表已经掌握。','显示答案后，该词会安排重学。'},
  {'题型与例句','配对后保留单词与翻译。','点已配对的词可查看详情。','答题后可查看各选项的释义。','填空自动跳过暂无适用例句的词。','句子讲解包含完整例句和译文。'},
  {'设置与保存','设置可调整每日新词与学习顺序。','学习进度自动保存。','重置需要确认，并保留最近一次备份。','覆盖安装时不要卸载旧程序。','包含新版词库时，需同时更新AppFiles。'}
}

local show_help
show_help=function(p)
  local source=help_pages[p];local ls={}
  for i=2,#source do for _,line in ipairs(wrapped_text(source[i],400,'small')) do ls[#ls+1]=line end end
  kit.show({title='帮助 '..p..'/3 · '..source[1],lines=ls,
    rows={{{'上一页',function() show_help((p-2)%3+1) end},{'下一页',function() show_help(p%3+1) end}},{{'关闭',kit.close}}},cancel=kit.close})
end

local DECK_BUTTONS = {
  { function() return '设置' end,show_settings },
  { function() return '更多' end, library_tools },
  { function() return '帮助' end, function()
      show_help(1)
    end },
  { function() return '页 ' .. (page + 1) .. '/' .. math.max(1, math.ceil(#library_view() / ROWS)) end, function()
      page = (page + 1) % math.max(1, math.ceil(#library_view() / ROWS))
    end },
}

local function menu()
  kit.show({ title = fit_label(deck.name,390,'medium'), lines = { '已完成 '..session.done .. ' 词条' },
             rows = { { { '切换练习模式', function() choose_mode(deck,true) end } },
                      {{'设置',show_settings}},
                      {{'错词本',function() wrong_book(1) end},{'学习总结',show_today}},
                      {{'重置进度',confirm_reset_progress}}, { { '撤销', function() kit.close(); undo(); exercise=nil end, last ~= nil },
                        { '添加词卡', function() kit.close(); add_card(deck) end } },
                      { { '删除词卡', function()
                            kit.show({ title = '删除当前词卡？', lines = { '删除后，本词库将不再显示这张词卡。' },
                                       rows = { { { '删除', function() kit.close(); delete_current(); exercise=nil end }, { '取消', kit.close } } },
                                       cancel = kit.close })
                          end, screen == 'study' },
                        { '回到词库', function() kit.close(); show_decks(); exercise=nil end } } },
             cancel = kit.close })
end

local function deck_buttons_rect(k)
  local bw = math.floor((W - 24 - 3 * 8) / 4)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

function on_draw(c, gg)
  if not gg then return end
  extend_budget()
  if (boot_task and boot_initial) or boot_error then
    gg:clear(0)
    if boot_error then
      gg:text(24,80,'暂时无法打开',{font=kit.font('large')})
      text_block(gg,boot_error,24,150,W-48,14,'small')
      gg:text(24,650,'请保留这条提示，再退出重试。',{font=kit.font('small')})
    else
      gg:rect(192,224,96,96,{line_width=3})
      gg:line(240,242,240,300)
      gg:line(208,248,232,254);gg:line(248,254,272,248)
      gg:line(208,269,232,275);gg:line(248,275,272,269)
      local title='墨词';local subtitle='InkWords'
      gg:text((W-kit.width(kit.font('large'),title))//2,352,title,{font=kit.font('large')})
      gg:text((W-kit.width(kit.font('small'),subtitle))//2,410,subtitle,{font=kit.font('small')})
      local message='正在准备上次学习'
      gg:text((W-kit.width(kit.font('small'),message))//2,560,message,{font=kit.font('small')})
    end
    return
  end
  local ok, e = pcall(function()
    gg:clear(0)
    if screen == 'decks' then
      gg:text(12, 12, '墨词 InkWords', { font = kit.font('large') })
      gg:text(12, 52, ((boot_task and not boot_quiet) and (management_busy and '正在保存备份与设置…' or '正在打开词书…') or ('每日新词：' .. kit.flow.daily_label())), { font = kit.font('small') })
    else
      -- the deck name, shortened to end before the Menu button
      local f, name = kit.font('medium'), deck.name
      if kit.width(f, name) > W - 136 then
        while #name > 1 and kit.width(f, name .. '~') > W - 136 do name = kit.drop_last(name) end
        name = name .. '~'
      end
      gg:text(16, 18, name, { font = f })
      local n, r = counts()
      gg:text(12, 52, '新词 ' .. n .. '  复习 ' .. r .. '  完成 ' .. session.done, { font = kit.font('small') })
      kit.letters.draw_menu(gg)
    end
    gg:line(0, 90, W, 90)
    if kit.modal() then kit.draw_modal(gg); return end
    if screen == 'decks' then
      draw_decks(gg)
      for k, b in ipairs(DECK_BUTTONS) do
        local x, y, bw, bh = deck_buttons_rect(k)
        kit.button(gg, x, y, bw, bh, b[1](), { font = 'small' })
      end
    elseif screen == 'study' then
      if mode=='flash' then draw_study(gg) else draw_exercise(gg) end
    else
      gg:text(24, TOP + 40, '本轮练习结束', { font = kit.font('large') })
      local stats=daily_stats()
      local lines_ = { session.done .. ' 个词条已完成。',
                       '今日新学 '..stats.fresh..'，复习 '..stats.review..'，答错 '..stats.wrong..'。' }
      local y = TOP + 90
      for _k, s in ipairs(lines_) do
        for _j, l in ipairs(wrapped_text(s, W - 48, 'small')) do gg:text(24, y, l, { font = kit.font('small') }); y = y + 26 end
        y = y + 6
      end
      local next_due
      for _,t in pairs(st.mins) do if t>now_sec() and (not next_due or t<next_due) then next_due=t end end
      if next_due then gg:text(24,y+20,'下次复习约 '..span(next_due-now_sec())..' 后',{font=kit.font('small')}) end
      kit.button(gg,12,BTN_Y,218,BTN_H,'回到词库')
      kit.button(gg,246,BTN_Y,222,BTN_H,'检查复习')
    end
    if msg then gg:text(12, BTN_Y - 30, kit.short(msg, 46), { font = kit.font('small') }) end
    if ERR then gg:text(12, H - 24, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then ERR=tostring(e);pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

local function in_rect(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

local function deck_at(x, y)
  if y < TOP or y >= TOP + ROWS * ROW_H then return nil end
  return library_view()[page * ROWS + (y - TOP) // ROW_H + 1]
end

local function deck_menu(d)
  local on_lock = settings.lock_deck == d.key
  kit.show({ title = fit_label(d.name,390,'medium'),
             lines = { on_lock and '已开启锁屏词卡。' or '锁屏词卡每30分钟更换一个单词。' },
             rows = { {{is_favorite(d) and '取消收藏' or '收藏词库',function() toggle_favorite(d);kit.close() end}}, { { '选择练习', function() kit.close(); choose_mode(d) end },
                        { '添加词卡', function() kit.close(); add_card(d) end } },
                      { { on_lock and '关闭锁屏词卡' or '开启锁屏词卡', function() kit.close(); toggle_lock(d) end },
                        { '关闭', kit.close } } },
             cancel = kit.close })
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  if screen == 'decks' then
    for k, b in ipairs(DECK_BUTTONS) do
      if in_rect(x, y, deck_buttons_rect(k)) then b[2](); return end
    end
    local d = deck_at(x, y)
    if d then
      if d.folder then navigate_folder(d.folder~='home' and d.folder or nil);return end
      if d.key==settings.recent then
        random_mix=settings.recent_mode=='random';previous_mode=nil
        mode=random_mix and 'quiz' or settings.recent_mode;exercise=nil;open_deck(d)
      elseif d.source == 'own' and not sread('my_own.txt') then deck_menu(d) else choose_mode(d) end
    end
    return
  end
  if in_rect(x, y, W - 112, 16, 100, 56) then menu(); return end
  if screen == 'done' then
    if y >= BTN_Y then if x>=246 then exercise=nil;open_deck(deck) else show_decks() end end
    return
  end
  if mode~='flash' then tap_exercise(x,y); return end
  if not shown then
    if y >= TOP then shown, scroll = true, 0 end
    return
  end
  if y >= BTN_Y then
    local bw = math.floor((W - 24 - 3 * 8) / 4)
    local k = (x - 12) // (bw + 8) + 1
    if k >= 1 and k <= 4 then rate(k) end
  end
end

function on_input(c, ev)
  if management_busy then return true end
  extend_budget()
  if (boot_task and not boot_quiet) or boot_error then
    if type(ev)=='table' and ev.type=='key' and ev.key=='back' then
      if not boot_initial then kit.close();show_decks(true);kit.refresh();return true end
      return false
    end
    return true
  end
  if storage_error then
    kit.show({title='保存未完成',lines={'请检查设备存储空间。','为避免重复记分，请退出后重新打开。'},rows={{{'关闭提示',kit.close}}},cancel=kit.close})
    kit.refresh();return false
  end
  if type(ev)=='table' and ev.type=='pointer' and ev.phase=='down' then long_done=false;return true end
  ERR = nil
  local handled = true
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'key' and ev.key == 'back' then
      -- Back acts on its release: closes a box, leaves a study session for the deck list, and on
      -- the deck list is left to the host (which offers to exit)
      if ev.phase ~= 'up' and ev.phase ~= nil then return end
      if kit.modal() then
        if kit.modal().cancel then kit.modal().cancel() end
      elseif screen ~= 'decks' then show_decks()
      elseif library_folder then navigate_folder(nil)
      elseif library_query~='' or favorites_only then library_query='';favorites_only=false;page=0
      else handled = false end
      return
    end
    if ev.type == 'pointer' then
      local x, y = ev.x or 0, ev.y or 0
      if ev.phase == 'down' then long_done = false end
      if (ev.gesture == 'long' or ev.phase == 'hold') and not kit.modal() then
        if not long_done and screen == 'decks' then
          local d = deck_at(x, y)
          if d and not d.folder then deck_menu(d) end
        end
        long_done = true
        suppress_up = ev.phase ~= 'up'
        if ev.phase == 'up' then long_done = false end
        return
      end
      if ev.phase ~= 'up' then return end
      long_done = false
      if suppress_up then suppress_up = false; return end
      if ev.gesture == 'swipe_up' and screen == 'study' and mode=='flash' and not kit.modal() then
        if max_scroll > scroll then scroll = scroll + 200 end
        return
      elseif ev.gesture == 'swipe_down' and screen == 'study' and mode=='flash' and not kit.modal() then
        scroll = 0
        return
      end
      tap(x, y)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        return
      elseif screen == 'study' then
        if mode~='flash' then
          if exercise and exercise.answered and (ev.key=='right' or ev.key=='down') then finish_exercise() end
          return
        end
        if ev.key == 'down' or ev.key == 'right' then
          if not shown then shown = true elseif max_scroll > scroll then scroll = scroll + 200 end
        elseif ev.key == 'up' or ev.key == 'left' then scroll = 0 end
      elseif screen == 'decks' and (ev.key == 'down' or ev.key == 'right') then
        page = (page + 1) % math.max(1, math.ceil(#library_view() / ROWS))
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  if ok and screen=="decks" then request_visible_summaries() end
  kit.refresh()
  return handled
end

boot_step=function()
  if not boot_task then return end
  extend_budget()
  local begin=kit.now_ms() or 0
  local finished=false
  -- Batch cheap checkpoints, but yield after 12 ms or 24 checkpoints.
  for _=1,24 do
    local ok,err=coroutine.resume(boot_task)
    if not ok then boot_task=nil;boot_error=tostring(err);ERR=boot_error;kit.refresh();return end
    if coroutine.status(boot_task)=='dead' then boot_task=nil;finished=true;break end
    if (kit.now_ms() or begin)-begin>=12 then break end
  end
  if finished then boot_initial=false;boot_stage='加载完成';kit.refresh();return end
  local serial=boot_serial
  local scheduled,result,why=pcall(function() return ctx:after(16,function() if serial==boot_serial then boot_step() end end) end)
  if not scheduled or result==false or (result==nil and why~=nil) then
    boot_task=nil;boot_serial=boot_serial+1
    boot_error='准备未完成，请返回后重试。';ERR=boot_error;kit.refresh()
  end
end
start_loading=function(label,fn,quiet)
  if label=='准备练习' then exercise=nil;release_memory() end
  boot_serial=boot_serial+1
  boot_error=nil;boot_stage=label;boot_reads=0;boot_quiet=quiet or false
  if type(ctx.after)=='function' then
    boot_task=coroutine.create(fn)
    -- Normal book opens finish within this first slice and never show a loading page.
    if not quiet and label~='正在准备' then boot_step()
    else
      local serial=boot_serial
      local ok,result,why=pcall(function() return ctx:after(16,function() if serial==boot_serial then boot_step() end end) end)
      if not ok or result==false or (result==nil and why~=nil) then
        boot_task=nil;boot_serial=boot_serial+1
        boot_error='准备未完成，请返回后重试。';ERR=boot_error;kit.refresh()
      end
    end
    if not quiet then kit.refresh() end
  else
    local ok,err=pcall(fn)
    if not ok then boot_error=tostring(err);ERR=boot_error end
  end
end

function on_load(c)
  storage_error=nil;boot_error=nil;ERR=nil;boot_reads=0;boot_initial=true
  extend_budget()
  math.randomseed(kit.now_ms() or 1)
  local function initialize()
    boot_stage='读取设置';P.load();load_settings()
    boot_stage='扫描词库';discover()
    boot_stage='读取学习进度';refresh_summaries()
  end
  start_loading('正在准备',initialize)
end
function on_leave()
  local loading=boot_task~=nil or boot_error~=nil
  boot_task=nil;boot_serial=boot_serial+1
  if not loading then pcall(write_lock_cards) end
end

if rawget(_G, '__TEST') then
  __TEST.api = { profile=function()return P.load()end, loading_visible=function() return boot_task~=nil and not boot_quiet end, loading=function() return boot_task~=nil end, boot_error=function() return boot_error end, error=function() return ERR end,
    exercise=function() return exercise end, current_mode=function() return mode end, mode=function(m) random_mix=m=='random'; previous_mode=nil; mode=random_mix and 'quiz' or m; exercise=nil end, choose=choose_answer, finish=finish_exercise,
    screen = function() return screen end, decks = function() return decks end, deck = function() return deck end,
    queue = function() return queue end, state = function() return st end, shown = function() return shown end,
    memory=kit.memory, schedule = schedule, span = span, prog = function(key, s) for _i, d in ipairs(decks) do if d.key == key then return load_prog(d, s) end end end, open = function(k) for _i, d in ipairs(decks) do if d.key == k then open_deck(d) end end end,
    card = function() return queue[1] and card_of(queue[1]) end, today = today, own = function() return own end,
  }
end
