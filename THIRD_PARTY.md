# 来源与致谢 / Sources and credits

Maintainer: **WarlockDi** · e99866@outlook.com

## 本公开包包含 / Included in this public package

| Component | Source / author | License and use |
| --- | --- | --- |
| App foundation, UI framework, packer wrapper | [omer-faruq-xteink/touch-licorice-apps v0.24.0](https://github.com/omer-faruq-xteink/touch-licorice-apps/tree/v0.24.0), Omer Faruk Inel | MIT; substantially modified Anki mini-app, gamekit and packaging code. Original notice in `licenses/LICENSE-touch-licorice-apps.txt`. |
| Licorice packer core | [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu), KFloyd.com | MIT; `tools/vendor/xtapp.py`, notice in `tools/vendor/LICENSE-x4pro-emu`. |
| InkWords UI Font | [notofonts/noto-cjk](https://github.com/notofonts/noto-cjk), Adobe / Noto contributors | OFL-1.1; generated rectangle glyphs derived from Noto Sans CJK SC Bold. Modified font resource name: InkWords UI Font. Full license, copyright and source hash in `licenses/`. No Windows font files or Windows-derived character blocks included. |
| Demo cards | Newly written for this project with AI assistance | MIT, Copyright 2026 WarlockDi. Twenty basic terms, definitions and example sentences, not copied from the private vocabulary collection. |

The generated glyph resources remain under OFL, not MIT. The package includes their notice and license. Python build/test dependencies (Pillow, cryptography, Lupa) are installed separately and retain their own licenses; their distributions are not bundled into the reader app.

## 交互与算法参考 / Ideas and scheduling

- [doconline2026-cell/memdeck](https://github.com/doconline2026-cell/memdeck): 多题型学习和墨水屏交互参考；本包不包含其插件、编译程序或素材。Interaction reference for quizzes/cloze/matching; its binaries and assets are not distributed here.
- [Anki](https://github.com/ankitects/anki) and [FSRS](https://github.com/open-spaced-repetition/fsrs4anki): spaced-repetition concepts. The implementation was inherited through the MIT upstream mini-app and adapted with additional evidence rules. It is not an unmodified reference FSRS implementation, Anki client, or AnkiWeb sync client.

## 个人开发阶段用过的资料 / Historical data references, NOT bundled

| Resource | Scope |
| --- | --- |
| [lilinji/English](https://github.com/lilinji/English) | Personal 108-book selection, exam/professional categories and source spreadsheets. Attribution does not establish permission to redistribute underlying books. Omitted from public downloads. |
| [kajweb/dict](https://github.com/kajweb/dict), commit `3992bcb94c800a2fd38a9fd6ff95b2353e755363` | Supplemental bilingual examples in private builds. Upstream describes app-scraped content; omitted from public downloads. |
| [designfuchen/word-atlas](https://github.com/designfuchen/word-atlas) | Earlier Word Atlas vocabulary/examples. Upstream content is described under CC BY 4.0; source includes AI-generated material. Not bundled in this public release. |
| [KyleBing/english-vocabulary](https://github.com/KyleBing/english-vocabulary) | Earlier vocabulary collection; upstream repository carries BSD-3-Clause. Not bundled in this release. |
| [LynnShaw/vocabulary_for_ielts](https://github.com/LynnShaw/vocabulary_for_ielts) | Earlier IELTS list, superseded in personal builds. Not bundled in this release. |
| [rspeer/wordfreq](https://github.com/rspeer/wordfreq), [Princeton WordNet](https://wordnet.princeton.edu/) | Original upstream Anki built-in deck. The original deck is not included here, so this release does not relabel those datasets as MIT. |

感谢以上作者和维护者。公开可访问的数据不自动取得再发布许可；代码的 MIT 许可也不覆盖第三方词书。已有用户的私有词库仍可在本地使用，本项目不会上传其学习记录。No affiliation, endorsement, or blanket redistribution permission is implied.
