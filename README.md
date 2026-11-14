# 墨词 InkWords · X4 Pro

**离线背单词小工具 / An offline vocabulary trainer for XTEINK X4 Pro**

[中文介绍](#中文介绍) · [English](#english) · [下载安装 / Downloads](https://github.com/WarlockDi/InkWords-X4Pro/releases/latest)

## 中文介绍

墨词是一款面向阅星瞳 X4 Pro 墨水屏阅读器的离线背单词小工具。支持自由选择词库，通过中英双向选择题、填空、配对和间隔复习学习单词。

**当前版本：0.2.1。** 已由用户在 **X4 Pro、XTOS Licorice 26111201** 上确认可用；其他设备和固件尚未验证。

### 功能

- **六种入口**：随机组合、英选中、中选英、填空、配对、单词卡；学习中可随时切换。
- **自定义随机组合**：勾选参与随机的题型，至少保留一种。
- **即时保存**：答题当下保存结果。配对中的每个词分别记分，错配只影响当前选择的英文词。
- **间隔复习与错词本**：根据 FSRS 安排复习，错词支持查看释义、单词练习、本页练习和手动移出。
- **词库管理**：名称搜索、收藏筛选、最近词库置顶、已学数量和百分比。
- **今日总结**：查看新学、复习、正确和错误次数。
- **适配小屏**：黑白界面；配对完成后保留单词与翻译，详情支持逐词切换和分页。

### 安装与升级

1. 从 [Releases](https://github.com/WarlockDi/InkWords-X4Pro/releases/latest) 下载 `InkWords_0.2.1.xtapp`。
2. 复制到设备 SD 卡，在设备文件列表中打开安装。
3. 在工具箱中打开“墨词”。

**旧版直接覆盖安装，无需先装 0.1.5 或 0.2.0；请勿卸载。** 应用 ID 始终为 `inkwords`，覆盖升级保留学习记录和词库。原 Anki 使用不同 ID，其记录不会自动迁移到墨词。

### 词库

内置 B2–C1 英语词库 **1438 条**、词光完整词库 **7298 条**、雅思词汇真经 **3632 条**，并支持自建词卡。原 B2–C1 词库保留英英解释。

可选下载 `InkWords_23_Dictionaries.zip`：共 **23 类、116953 条记录**，包括雅思、托福、GRE、GMAT、SAT、四六级、考研、商务英语及中小学词库。按压缩包中的说明，将 `AppFiles/inkwords` 复制到 SD 卡对应目录。

各词库存在重复与重合，记录数不是去重单词数，也不代表覆盖全部考试用词。

### 操作入口

| 入口 | 操作 |
| --- | --- |
| 词库页 → 查找 | 搜索词库、只看收藏、清除筛选、今日总结 |
| 长按词库 | 收藏或取消收藏、选择练习 |
| 继续学习 | 沿用最近词库与上次模式 |
| 学习菜单 | 切换模式、错词本、自定义随机组合、今日总结 |
| 配对后的单词 | 点击查看释义与例句 |

已学百分比表示练习过的词条比例，不等于掌握率。今日统计和错词收集从本版使用时开始，不倒推旧版历史。错词按词库分别保存，答对后仍保留，可在掌握后手动移出。填空为**点选词块**，没有适用例句时回退为词义选择；配对候选不足时可少于四组。

## 运行测试截图 / Runtime test screenshots

以下图片来自 **0.2.1 的 Lua 程序在离线测试环境中实际运行产生的绘图指令**，再由测试渲染器输出为图片。**不是 AI 生成图，也不是设备实拍**；字体及刷新表现与真机可能不同。测试过程和文件校验记录见 [截图说明](docs/SCREENSHOTS.md)。

These images are rendered from drawing commands emitted by the **actual v0.2.1 Lua application running in the offline test harness**. They are **not AI-generated artwork or photographs of the device**. Font rendering and refresh behavior may differ on hardware. See [capture details](docs/SCREENSHOTS.md).

| 词库 / Decks | 英选中 / English → Chinese |
| --- | --- |
| <img src="docs/screenshots/decks.png" width="300" alt="词库测试截图 / Deck list test capture"> | <img src="docs/screenshots/quiz.png" width="300" alt="选择题测试截图 / Quiz test capture"> |

| 配对 / Matching | 学习菜单 / Study menu |
| --- | --- |
| <img src="docs/screenshots/match.png" width="300" alt="配对测试截图 / Matching test capture"> | <img src="docs/screenshots/menu.png" width="300" alt="菜单测试截图 / Menu test capture"> |

| 错词本 / Wrong-word list | 今日总结 / Daily summary |
| --- | --- |
| <img src="docs/screenshots/wrong-words.png" width="300" alt="错词本测试截图 / Wrong-word list test capture"> | <img src="docs/screenshots/summary.png" width="300" alt="今日总结测试截图 / Daily summary test capture"> |

| 词库查找 / Deck search | 随机设置 / Mixed-practice settings |
| --- | --- |
| <img src="docs/screenshots/search.png" width="300" alt="查找测试截图 / Search test capture"> | <img src="docs/screenshots/random.png" width="300" alt="随机设置测试截图 / Mixed-practice settings test capture"> |

## English

InkWords is an offline vocabulary trainer for the **XTEINK X4 Pro** e-paper reader. Choose a deck and study through bilingual quizzes, word-choice cloze exercises, matching and spaced repetition.

**Version 0.2.1 has been confirmed working by the user on X4 Pro with XTOS Licorice 26111201.** Other devices and firmware versions have not been verified. The interface is primarily in Chinese.

### Features

- Mixed practice, English-to-Chinese quizzes, Chinese-to-English quizzes, cloze, matching and flashcards. Switch modes from the study menu.
- Choose which question types participate in mixed practice; keep at least one enabled.
- Answers are saved immediately. Each matched word receives its own review result; a wrong match affects only the selected English word.
- FSRS spaced repetition and a per-deck wrong-word list with definitions, individual practice, page practice and manual removal.
- Deck search, favorites, a pinned recent deck, studied counts and progress percentages.
- A daily summary of new words, review responses, correct responses and errors.
- A monochrome interface with paged definitions and examples. Matched words remain visible.

### Install or update

1. Download `InkWords_0.2.1.xtapp` from [Releases](https://github.com/WarlockDi/InkWords-X4Pro/releases/latest).
2. Copy it to your SD card and open it from the reader's file list to install.
3. Open **墨词** from the toolbox.

**Install over your existing version; do not uninstall first.** Intermediate versions are unnecessary. The app ID remains `inkwords`, preserving existing InkWords decks and progress. Progress from the separate Anki app is not automatically imported.

### Vocabulary and usage notes

The app includes a 1,438-entry B2–C1 English deck, a 7,298-entry Word Atlas deck, a 3,632-entry IELTS deck and support for personal cards. The original B2–C1 deck retains English definitions.

The optional `InkWords_23_Dictionaries.zip` contains 23 decks and 116,953 records, including IELTS, TOEFL, GRE, GMAT, SAT, CET-4/6, postgraduate entrance, business English and school vocabulary. Follow its instructions to copy `AppFiles/inkwords` to the matching SD-card location. Decks overlap; record counts are not unique-word totals or guarantees of full exam coverage.

Use **查找** for search and favorites filtering; long-press a deck to favorite it. **继续学习** resumes the recent deck and mode. The study menu contains mode switching, the wrong-word list, mixed-practice settings and the daily summary.

Progress measures entries practiced, not mastery. Daily statistics and wrong-word collection start with this version; older response history is not reconstructed. Wrong words remain listed until manually removed. Cloze exercises use selectable word options, with a definition-choice fallback when no suitable example exists. Matching can use fewer than four pairs when candidates are limited.

## 构建与测试 / Build and test

Python 3.10+:

```sh
python -m pip install -r requirements.txt
python build.py
```

输出 / Output: `dist/InkWords_0.2.1.xtapp`

```sh
python -m pip install -r requirements-dev.txt
python tests/test_v020.py
python tests/test_random_mode.py
python tests/test_switch_mode.py
python tools/lualint55.py apps/inkwords/index.lua
```

应用逻辑 / Application logic: `apps/inkwords/src/main.lua`.

Tests cover immediate saving, independent matching results, wrong-word practice, undo, random subsets, date rollover, search, favorites and persistence. Offline tests do not fully emulate device storage latency or firmware execution limits. Version 0.2.1 caches favorites to eliminate repeated storage reads during home-screen sorting.

## 来源与许可 / Credits and licenses

基于 / Based on [touch-licorice-apps v0.24.0 — Anki](https://github.com/omer-faruq-xteink/touch-licorice-apps/tree/v0.24.0/apps/anki). Original MIT notices are preserved in `LICENSE` and `tools/vendor/`.

词库使用各自的来源和许可，不统一改为 MIT。Vocabulary datasets retain their respective source terms and licenses; the application code license does not relicense the datasets. See [THIRD_PARTY.md](THIRD_PARTY.md).

MemDeck 仅作为交互参考，未复制其编译程序。本项目不是阅星瞳、Anki 或 MemDeck 的官方产品。MemDeck inspired interaction ideas; its compiled program was not copied. This is not an official XTEINK, Anki or MemDeck product.

