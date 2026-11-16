# 1.6.8 验证记录 / Validation

### 验证与边界

电脑检查包括：1 MiB 模拟Lua堆下七种题型；250次连续查词与导航；160次混合查询；6000组编辑距离和500组前缀对照；100次讲解/释义切换；96种配对保存故障恢复；重置取消、书签和跨页返回检查。更早的本轮检查包含1000次固定种子混合答题/导航/重启。
这些不是实机毫秒耗时或耗电测试。用户已确认词典可用；1.6.8整包长期实机验证未完成，不宣称无延迟或零崩溃。


Desktop-only checks, no hardware latency/energy certification. Public reproducible commands: `python tests/smoke.py`, `python tests/test_import.py`, `python tests/test_digest.py`, `python tests/test_progress.py`. Additional local stress tests used development fixtures not distributed with private data.
