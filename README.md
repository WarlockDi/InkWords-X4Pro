# 墨词 InkWords · X4 Pro

**由 WarlockDi 维护的离线中英文背单词工具。An offline bilingual vocabulary trainer maintained by WarlockDi.**

官方仓库 / Official repository: https://github.com/WarlockDi/InkWords-X4Pro  
联系 / Contact: **e99866@outlook.com**  
当前公开版 / Public version: **1.4.6**

[下载并安装 / Download app](https://github.com/WarlockDi/InkWords-X4Pro/raw/refs/heads/main/downloads/InkWords_1.4.6.xtapp) · [安装说明 / Installation](INSTALL.md) · [获取和导入词库 / Get decks](docs/VOCABULARY.md) · [来源与致谢 / Credits](THIRD_PARTY.md) · [贡献说明 / Contributors](CONTRIBUTORS.md) · [作者与转载 / Authorship](AUTHORSHIP.md)

## 中文

墨词针对阅星瞳 **X4 Pro、XTOS Licorice 26111201、480×800 竖屏**设计。它从个人使用需求出发，沿用设备现有交互方式，离线运行，不需要账号、网络、系统软键盘或后台服务。不是普通手机应用，也不是阅星瞳、Anki 或 MemDeck 的官方产品。

### 功能

- 英选中、中选英、例句填空、拼写单词、双向配对、单词卡，以及可自选题型的随机组合。
- 拼写自动难度：简单题两个空位；两个字母的词只挖一个空，始终保留可见字母。普通与挑战题最多五个空位、八个候选，重复字母可以重复点击。
- 填写前后下划线长度和位置固定。答错时上方保留实际填写，下方显示正确拼写；长词按空间适配。
- 配对既可以先点英文，也可以先点中文；配对后仍可查看单词和释义。
- 基于上游 FSRS 4.5 的复习调度，增加保守的记忆证据规则；同轮重试、提前练习、配对末项排除不直接视为长期记住。
- 词库分类、最近练习、继续学习、搜索、收藏、学习总结、错词记录、每日新词数量及无限制选项。
- 本地保存进度，支持单词本/全部进度重置、恢复默认设置，以及最近一次重置备份恢复。重置需确认。

“已学”百分比表示练习过的比例，不等于掌握率。记忆判定是软件估计，不是学习效果保证。例句填空跳过没有适用例句的词。

### 安装与词库

下载并安装上方 `.xtapp` 即可；首次打开自动准备内置示例词库，不需要另行复制 AppFiles。已有完整词库和学习进度直接沿用，程序不会用示例库覆盖它们。详见 [INSTALL.md](INSTALL.md)。

公开包提供20条自行编写的中英示例词卡，用于体验所有题型，**不是只能学习20个词**。更多词库来源、下载、CSV转换和保留原词库的导入步骤，见 **[如何获取和导入词库](docs/VOCABULARY.md)**。个人版本使用过的108本词书及抓取例句不在此公开包中，原因见 [THIRD_PARTY.md](THIRD_PARTY.md)。这不影响你本机已有的词库。

### 运行预览

下图来自 **1.4.6 实际 Lua 程序在电脑测试环境中的绘图**，不是生成图片，也不是实机照片。使用公开包的开放许可字形资源；设备原生字体、刷新速度和残影可能不同。

| 拼写 / Spelling | 双向配对 / Matching |
| --- | --- |
| <img src="docs/screenshots/spelling.png" width="280" alt="Spelling runtime preview"> | <img src="docs/screenshots/matching.png" width="280" alt="Matching runtime preview"> |

### 验证范围

见 [测试记录](docs/TESTING.md)。本次公开版尚未在实机上重新验收，不承诺无故障或兼容所有固件。程序只加载当前需要的数据，不把整套词库读进内存。

## English

InkWords is a Chinese-interface, offline English vocabulary trainer for **XTEINK X4 Pro with XTOS Licorice 26111201**, using the existing 480×800 portrait UI. No account, network, background service or system keyboard is required.

Features include bilingual multiple-choice quizzes, sentence cloze, adaptive letter spelling, bidirectional matching, flashcards, configurable mixed practice, local spaced repetition, deck categories, recent decks, summaries, wrong-word records and confirmed reset/restore operations. Easy spelling hides two letters except in two-letter words; at least one letter remains visible. Submitted letters and fixed underlines remain visible after answering, with the reference spelling below.

The review scheduler is adapted from the upstream FSRS 4.5 implementation with conservative evidence rules. It estimates familiarity; progress is not a mastery guarantee. Sentence cloze skips cards without a suitable example.

The single `.xtapp` contains the app and **20 newly written demonstration cards**, initialized automatically on first launch, not the private 108-book collection or scraped dictionaries. Existing users install the same `.xtapp`; existing vocabulary and progress are preserved. No manual AppFiles copy is needed for first-time demo use. See [installation](INSTALL.md), [credits and data boundaries](THIRD_PARTY.md), and [test limitations](docs/TESTING.md). This public build has not yet been revalidated on hardware; other devices/firmware are unverified.

## 构建 / Build

Python 3.10+:

```sh
python -m pip install -r requirements.txt
python build.py
```

Output: `dist/InkWords_1.4.6.xtapp` and `dist/InkWords_1.4.6_Public.zip`. The included generated font blocks are sufficient to build. To regenerate them, supply the Noto Sans CJK SC Bold OTF specified in `licenses/FONT-COPYRIGHT.txt` to `python tools/build_fonts.py --font PATH`.

```sh
python -m pip install -r requirements-dev.txt
python tests/smoke.py
python tools/lualint55.py apps/inkwords/src/main.lua
```

## 感谢 / Acknowledgements

**WarlockDi** 负责需求、交互决策、维护和实机反馈；**OpenAI Codex** 协助开发、排查问题、模拟测试、文档和发布准备。详见 [贡献与 AI 辅助说明 / Contributors and AI assistance](CONTRIBUTORS.md)。

- **Omer Faruk Inel / omer-faruq-xteink** — [touch-licorice-apps v0.24.0](https://github.com/omer-faruq-xteink/touch-licorice-apps/tree/v0.24.0): Anki mini-app foundation, gamekit, Lua host documentation and packaging tools. MIT notices retained.
- **KFloyd.com / kycube** — [x4pro-emu](https://github.com/kycube/x4pro-emu): upstream Licorice container/packer implementation. MIT notice retained.
- **doconline2026-cell** — [MemDeck](https://github.com/doconline2026-cell/memdeck): interaction ideas for multiple-choice, cloze and matching practice. No MemDeck binary is included.
- **Anki and the open-spaced-repetition community** — [Anki](https://github.com/ankitects/anki), [FSRS](https://github.com/open-spaced-repetition/fsrs4anki): spaced-repetition concepts. InkWords is not Anki and does not synchronize with AnkiWeb.
- **Adobe / Google / Noto contributors** — [Noto CJK](https://github.com/notofonts/noto-cjk): open-licensed source for the bundled InkWords UI Font, under OFL-1.1.
- **lilinji, designfuchen, kajweb, KyleBing and LynnShaw** — vocabulary resources used or evaluated during personal development; scope and redistribution exclusions are documented in [THIRD_PARTY.md](THIRD_PARTY.md).

InkWords-specific modifications: **Copyright © 2026 WarlockDi**. Application code is MIT-licensed; third-party licenses remain applicable. Please retain the author and upstream notices when copying or distributing the code. See [AUTHORSHIP.md](AUTHORSHIP.md).

