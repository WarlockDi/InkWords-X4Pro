# 如何获取和导入词库 / Getting vocabulary decks

维护者：**WarlockDi** · e99866@outlook.com

墨词并不限制只能学20个词。公开安装文件内置20条演示词卡；你可以添加更多词库。**软件安装只需一个 `.xtapp`，添加第三方词库属于可选的数据导入步骤，目前仍需在电脑上转换、复制。** 已有完整词库的用户不用重新获取。

## 1. 到哪里找

| 来源 | 适合寻找的内容 | 使用前注意 |
| --- | --- | --- |
| [lilinji/English 中文目录](https://github.com/lilinji/English/blob/main/README_zh.md) | 按目录查找考试、分级、商务及专业英语词表；这是个人版108本词书的来源 | 先查看原仓库说明和具体词书来源。各文件内容不同，不是统一的可直接安装包。 |
| [词光 Word Atlas](https://github.com/designfuchen/word-atlas) | 中英文词汇与例句 | 内容许可见其 [CONTENT_LICENSE.md](https://github.com/designfuchen/word-atlas/blob/main/CONTENT_LICENSE.md)。词典JSON不能直接复制进墨词，需按下面字段转换。 |
| [KyleBing/english-vocabulary](https://github.com/KyleBing/english-vocabulary) | 四六级、考研等 TXT / JSON 词表 | 检查仓库说明、具体文件格式与许可；不是墨词格式。 |
| 你自己整理或得到授权的词表 | 个性化单词、专业术语、已有表格 | 最方便的入口是 UTF-8 CSV；可加入自己的例句和翻译。 |

这些是原作者的入口，不是墨词镜像下载。请遵守具体来源的使用条件；写明出处并不自动获得再分发权，也不要把整套词库或教材再次上传到本项目。

### 从 GitHub 下载原始文件

打开上面的原仓库，按其目录找到需要的文件。文件页若提供 **Download raw file / 下载原始文件**，使用该入口；也可以在仓库首页 **Code → Download ZIP** 下载整个仓库，再找出词表。不要把 GitHub 网页另存为 HTML 当成词库，也不要仅把 `.xlsx` / `.json` 改后缀为 `.csv`。

同一词书有多个版本时，按原仓库标注选择所需版本。不同年份或书名不一定代表相同词条顺序；**学过的书不要随意换版本覆盖**，否则进度与词条可能错位。

## 2. 整理成墨词接受的 CSV

先从本项目首页 **Code → Download ZIP** 获取源码并解压，找到 `tools/import_csv.py`。电脑需要 Python 3.10 或以上；这个转换器只用标准库，不需要安装额外依赖。

转换器目前接受 **UTF-8 CSV**，不会直接读取 XLSX、XLS、JSON、APKG 或 PDF。Excel词表可先用 Excel、WPS 或 LibreOffice 打开，复制需要的列到新表并另存为“CSV UTF-8”。通常把“单词”映射为 `word`、“释义”映射为 `meaning`；其余列可以不带。

| 列名，必须照写 | 内容 | 必填 |
| --- | --- | --- |
| `word` | 英文单词或词组 | 是 |
| `meaning` | 中文释义 | 是 |
| `sentence` | 包含目标词的英文例句 | 否 |
| `translation` | 对应例句的中文译文 | 否 |

可以下载并修改 [CSV模板](../examples/import-template.csv)。例如：

```csv
word,meaning,sentence,translation
apple,n. 苹果,I put an apple in my bag.,我把一个苹果放进包里。
```

JSON/TXT的字段与分隔方式因来源而异，需要先整理成上述列，**本项目没有承诺一键转换所有第三方格式**。例句缺失可留空；这种词卡仍可用于其他练习，例句填空会跳过它。例句有明显错误时请先修正。

## 3. 转换

在解压的墨词源码目录打开终端，把词表命名为 `my-words.csv` 放在该目录，然后运行：

```sh
python tools/import_csv.py my-words.csv --name "我的雅思词库" --output my-library
```

Windows如果 `python` 无法识别，可尝试 `py`。书名自行填写，不代表脚本会自动下载雅思词库。输出目录 `my-library` 必须是尚不存在的新目录。

成功后里面会有 `library_v2.txt` 和若干 `iw…_e000.txt` 文件。这才是墨词的可用词库格式。不要单独复制原始CSV到阅读器，当前程序不会自动识别它。

## 4. 添加到阅读器，保留原来的词库

1. 退出墨词，连接阅读器进入USB传输模式。
2. 将阅读器现有的 **`AppFiles/inkwords` 整个文件夹复制到电脑**，在源码目录旁命名为 `reader-library-copy`，同时保留一份未动过的备份。
3. 在电脑运行合并工具，它只生成新目录，不修改输入：

```sh
python tools/merge_libraries.py reader-library-copy my-library --output merged-library
```

4. 看到成功提示后，把 `merged-library` **里面的文件**复制到阅读器 `AppFiles/inkwords`。会更新目录文件，使新旧词书同时显示；不要把 `merged-library` 文件夹套在里面。
5. 安全弹出设备，重新打开墨词，在“通用与分级”中查找新书名。

如果设备上尚没有目录，先打开墨词一次，程序会自动准备示例词库，再按上述方法添加。**不要直接用新生成的 `library_v2.txt` 覆盖原目录**：那会让其他书在界面上消失，尽管原数据文件可能还在。

合并工具拒绝同一书籍ID的不同内容、缺失数据分片、旧格式目录以及已有输出目录。遇到冲突时先停止，不要删掉原来的词库。用不同书名导入新版词表会产生新的书籍ID，进度独立计算；同一书名下重新排序、删词或覆盖内容会破坏旧进度对应关系。

这里只备份和合并外部词库文件，**不等于备份应用私有学习进度**。已有书的ID、词条顺序和原文件内容在合并中保持不变。首次只导入几十个词检查一遍，再处理大词库。

## English quick guide

The app is not limited to 20 words. The built-in demo is separate from optional user-supplied vocabulary. Installing the app is one file; adding external decks currently requires conversion and copying on a computer.

Use the upstream links above to locate permitted vocabulary files. XLS/XLSX, JSON, TXT and Anki packages are **not** directly readable by this converter. Normalize your data to UTF-8 CSV with `word`, `meaning`, and optional `sentence`, `translation` columns. See the [template](../examples/import-template.csv).

Run `python tools/import_csv.py my-words.csv --name "My vocabulary" --output my-library` from this repository. Copy the reader's entire `AppFiles/inkwords` folder to your computer as `reader-library-copy`, keep a backup, then run `python tools/merge_libraries.py reader-library-copy my-library --output merged-library`. Only after success, copy the files inside `merged-library` back to `AppFiles/inkwords` and safely eject.

The merge tool accepts format-3 catalogues only and refuses conflicting IDs/files. It preserves existing book IDs and data. Never replace an established catalogue with a single-book export or reorder a studied book in place. External-library backups do not necessarily include private learning progress. This workflow does not grant rights to redistribute the source dictionaries.
