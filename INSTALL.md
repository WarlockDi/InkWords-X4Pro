# 安装 / Installation

维护者 / Maintainer: **WarlockDi** · e99866@outlook.com  
官方来源 / Official source: https://github.com/WarlockDi/InkWords-X4Pro

## 已经安装墨词

1. 下载 `InkWords_1.5.4.xtapp`，退出墨词。
2. 连接阅读器并进入 USB 文件传输模式。
3. **只复制 `InkWords_1.5.4.xtapp` 到阅读器。**
4. 安全弹出，退出 USB 模式，在阅读器文件列表打开 `.xtapp` 覆盖安装。
5. 在“设置 → 关于墨词”确认版本 **1.5.4 公开版**、作者 **WarlockDi**。

无需先安装中间版本。不要卸载或重置进度。应用 ID 保持 `inkwords`，现有108本词库不变。私有学习记录不随本公开安装包分发。较旧版本可能无法识别新进度字段，不建议降级。

## 首次安装

同样只安装一个 `.xtapp` 文件。首次打开“墨词”时，程序会自动创建内置示例词库，无需复制 AppFiles。进入“通用与分级 → 墨词示例词库”体验。

初始化仅在没有现有词库目录时执行；先写词条，校验后最后写目录。写入失败时可检查存储卡后重开，已有词库不会被自动替换。

示例库只有20条自行编写的词卡，不代表完整考试词库，也不是学习数量上限。添加其他词书请看 **[词库获取、转换和导入教程](docs/VOCABULARY.md)**，其中包括保留原词库的合并方法。额外词库导入目前仍需电脑操作。

## English

**Existing users:** download `InkWords_1.5.4.xtapp`, copy it to the reader, safely eject, and open it to install over the existing app. Do not uninstall or reset progress. Verify version 1.5.4 and WarlockDi in Settings → About.

**First installation:** install the same single `.xtapp`. The 20-card demonstration library is initialized automatically on first launch, only when no existing catalogue is present. No separate AppFiles copy is required. Other dictionaries must be supplied by the user with appropriate rights.

See [Getting vocabulary decks](docs/VOCABULARY.md) for source links, CSV conversion and safe catalogue merging; additional decks currently require a computer.

## 注意 / Notes

- 本版本为 X4 Pro / XTOS Licorice 开发，其他固件与设备未验证。
- 公开版更换为 OFL 开放字体，少数字形可能与1.4.5不同；功能及进度格式保持兼容。
- 升级前可按设备支持的方式备份资料。复制 AppFiles 只备份词库，不一定包含应用私有进度。
- 请先测试打开拼写、连续作答、返回词库和重启后的进度。遇到问题请提供版本、词库名、题型、操作步骤和照片，不要公开自己的完整学习记录。
- Check `SHA256SUMS.txt` against the files from the official repository. Checksums detect file changes; they are not digital signatures or a guarantee of safety.
