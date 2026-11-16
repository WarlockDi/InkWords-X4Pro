# 1.6.3 验证记录 / Validation record

维护者反馈：1.6.3本轮实机检查无问题。设备为阅星瞳X4 Pro；首次打开错词页面仍可能等待数秒。没有测量真实延迟、耗电或进行长期硬件耐久认证。
The maintainer reports the requested 1.6.3 checks passed on their X4 Pro. Initial mistake-list loading can still take seconds; no hardware latency, energy or endurance certification is claimed.

## 本地开发检查 / Local development checks

- 1000次固定种子的答题、导航、重启混合操作 / 1,000 seeded mixed answer/navigation/restart operations.
- 6000条来源记录的索引、重启和两个错词入口切换，模拟Lua内存上限1MiB / 6,000 source records, restart and scope switching under a simulated 1 MiB Lua heap.
- 96个连续配对保存故障场景、42个大记录边界场景、29个原保存事务故障场景 / 96 pair-journal faults, 42 oversized-boundary cases, 29 legacy persistence fault cases.
- 84个派生缓存写入故障场景 / 84 derived-cache write faults; canonical progress preserved.
- 104组校验输入对照；新校验中间值不超过131040 / 104 digest vectors, bounded arithmetic with intermediates no larger than 131040.
- 进度实际计数、取消重开、自动完成、缺少毫秒时钟时的回退，以及中间刷新800ms限频 / Real counts, cancellation/retry, completion, missing-clock fallback and throttled intermediate redraws.
- 25090字节进度文件的答题前相关读取由3次减至2次，保留写后校验 / A 25,090-byte progress fixture reduced relevant feedback-path reads from 3 to 2, retaining read-back validation.

详细压力测试使用开发用测试词库，不将私人词库和学习记录上传仓库。仓库内提供下方可复现的公开示例测试；以上数字不是这些简短测试单独覆盖的全部范围。
Large stress tests used development fixtures which are not distributed as private vocabulary/progress. The smaller public checks below are reproducible; they do not by themselves cover every stress scenario listed above.

## 公开可运行检查 / Reproducible public checks

```sh
python -m pip install -r requirements-dev.txt
python build.py
python tests/smoke.py
python tests/test_import.py
python tests/test_digest.py
python tests/test_progress.py
python tools/lualint55.py apps/inkwords/src/main.lua
```

包构建校验容器内的代码与数据，发布流程校验分发文件SHA256。模拟截图不能衡量墨水屏刷新与残影。
Build checks verify code/data container round-trips; publishing verifies distribution SHA256 hashes. Runtime screenshots do not measure e-paper refresh or ghosting.
