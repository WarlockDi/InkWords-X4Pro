# 墨词 1.6.8 安装与升级 / Install and update

作者：WarlockDi · e99866@outlook.com

## 安装

如果已安装 1.6.6 或 1.6.7 且词典正常可用，只需将 InkWords_1.6.8.xtapp 复制到阅读器，安全弹出后打开文件覆盖安装。无需再复制词典，无需卸载或重置进度。

首次安装或缺少词典数据时，将 InkWords_1.6.8.xtapp 与 AppFiles 一起复制到阅读器根目录。AppFiles 合并覆盖，保留现有文件，不要删除整个文件夹。安全弹出后打开 xtapp 安装。

设置→关于墨词应显示 1.6.8。可直接更新，无需安装中间版本。

## 本次更新

- 词典顶部词语和放大镜统一作为查询入口，删除底部“重新查询”。
- 设备返回键和页面返回逐级返回，恢复原候选或词条页码。
- 提交查询不主动刷新中间页；重复查询保留原页，不重复读取；取消或空输入保留页面。
- 返回历史词条不改变最近查询顺序；拦截重复及过期输入回调。
- 总结子页按来源返回；单页总结列表隐藏翻页，多页首尾不循环。
- 重选当前错词筛选保留页码；重选当前题型保留当前题、队列和作答状态。
- 词库搜索取消返回“更多”；相同搜索不重置页码或重复请求汇总。
- 句子讲解单页隐藏翻页，多页到首尾停止。

保留既有词库、学习进度、单词本书签、字母拼写、双向配对及间隔复习功能。原有答题布局和进度保存逻辑保持不变。

## 安装后重点检查

1. 点击词典顶部词语改查；从候选进入词条后按设备返回键。
2. 输入后是否仍闪回查询页；取消输入是否保留原词条。
3. 答题中打开题型选择，再选当前题型，已填字母或配对状态是否保留。
4. 总结各子页返回、单页句子讲解以及长内容翻页。
5. 做几题后正常退出重开，确认进度和单词本页码。

电脑 Lua 运行、限内存、导航和保存故障检查不能替代实机刷新延迟及耗电测试。

## 词典数据

附带 625 个 dict1_*.txt 文件，与 1.6.6 完全一致。支持英汉/汉英精确和词首查询，以及部分常用英文词的一次字母编辑建议，不是整句翻译工具。词典来源和许可见 AppFiles/inkwords/dict1_notice.txt、dict1_ecdict_license.txt 与 THIRD_PARTY.md。字形来源见 licenses。

## English

If the dictionary already works in version 1.6.6 or 1.6.7, install only InkWords_1.6.8.xtapp over the existing app. No data recopy, uninstall or progress reset is needed. For a first install, copy both the xtapp and AppFiles to the reader root, merging without deleting existing files, safely eject, then install the xtapp.

This update unifies dictionary input at the query heading, removes the redundant requery action, fixes back navigation and pagination, avoids unnecessary intermediate query refreshes, preserves current exercises when selecting the same mode, and preserves search/filter state. Dictionary data is unchanged. Desktop verification does not measure real device latency or energy use. 
