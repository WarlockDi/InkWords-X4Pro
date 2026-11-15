# 1.5.4 验证记录 / Validation

维护者 / Maintainer: WarlockDi · e99866@outlook.com

## 检查结果 / Results

All checks below passed in the desktop Lua harness against the 1.5.4 source. Private vocabulary fixtures and learning data are not distributed.

| 检查 / Check | 覆盖 / Coverage |
| --- | --- |
| 公开包 / Public smoke | 首次安装、保留已有词库、初始化中断恢复、损坏目录保护、七种模式、作答与重新打开 / first install, preservation, interrupted initialization, corrupt catalogue protection, seven modes, answer and reopen |
| 随机操作 / Random operations | 3,000 operations across 6 seeds |
| 连续作答 / Continuous practice | 6,000 questions; simulated 1 MiB Lua heap ceiling; observed peak 1,048,317 bytes |
| 保存故障 / Persistence faults | 29 cases: write failure, interruption, partial writes, false success and recovery; no duplicate grading |
| 下一题 / Prepared Next | Six modes: zero synchronous writes, deck reads, font-line reads or full GC on the tested prepared transition path |
| 快速操作 / Rapid input | 20 rapid answers with background work withheld; previous durable transaction is merged before replacement |
| 配对 / Matching | 432 groups across 108 private test books; both selection directions |
| 自动难度 / Adaptive spelling | 1,280 cases; repeated letters, short/long words and phrases |
| 总结 / Summaries | 100 open/close/cancel cycles; cache invalidation after answers, timeout, date change and reset |
| 布局 / Layout | 35 general UI frames and 12 spelling/phrase frames pixel-identical to 1.5.3 |
| 打包 / Packaging | Code and all packaged resources decrypted and verified; public download matches the delivered, tested app |

## 可复现公开检查 / Public checks

```sh
python -m pip install -r requirements-dev.txt
python tests/smoke.py
python tests/test_import.py
python tools/lualint55.py apps/inkwords/src/main.lua
python build.py
```

## 预览和实机限制 / Preview and hardware limits

README images are actual 1.5.4 Lua drawing output using public demo cards, not generated artwork or hardware photographs. Native font rendering and e-ink refresh may differ.

维护者实机反馈响应有所改善，但电脑环境无法测量设备真实的点击延迟、存储卡写入速度、刷新残影、耗电或长时间运行表现。预备未完成、内存紧张及存储慢时仍可能等待。1 MiB 是测试设定的 Lua 内存上限，并非设备总内存参数；测试峰值接近此上限，不表示有很大余量。

The maintainer reports improved responsiveness on their device. Desktop tests do not measure real tap latency, SD-card I/O, e-ink ghosting, power consumption or long-term hardware reliability. An unfinished prefetch, memory pressure or slow storage can still cause a wait. The 1 MiB limit is an artificial Lua test budget, not total device RAM; peak usage is close to that ceiling.

升级后建议检查连续快速下一题、双向配对、拼写最后一个字母、退出重开后的进度，以及累计总结打开与取消。发现问题请提供版本、题型和操作步骤，勿公开个人学习记录。

After upgrading, check rapid Next taps, both matching directions, the final spelling letter, persisted progress after reopening, and summary opening/cancellation. Report version, mode and steps without publishing private learning records.
