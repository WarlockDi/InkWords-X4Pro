# Version history / 版本说明

## 1.5.4 — 2026-11-15

自上一公开版 1.4.6 的累计更新 / Cumulative update since public 1.4.6.

- 优化显示答案、双向配对和下一题响应：仅预备当前题与下一题，复用字形和排版，后台准备可取消；不增加后台服务。
- 答题先保存并校验恢复日志，再显示结果；分段合并进度，异常退出后恢复，避免重复计分。保存失败时停止继续计分并提示。
- 拼写词组保留清晰间距，长词组按词换行；上下划线及用户填写保持固定。答对仅显示“拼写正确”，答错显示“拼写错误”和正确拼写，主动显示答案不误判为拼写错误。
- 累计总结分段加载、支持取消和短期缓存，避免短暂返回答题页。恢复开屏短句，做题标题只显示实际题型。
- 保留原布局、现有词库与进度；安装方式、示例词库范围和作者/上游许可证不变。

- Faster answer feedback, bidirectional matching and Next through bounded current/next preparation and reusable glyph/layout caches. Preparation is cancellable; no background service added.
- A verified recovery journal precedes feedback; incremental progress merging supports restart recovery without duplicate grading. Save failures stop further grading and show an error.
- Clear phrase spacing and word-aware wrapping; stable spelling slots and submitted letters. Correct answers show only success; incorrect answers show the reference spelling. Revealing an answer is distinguished from a spelling error.
- Cumulative summaries load incrementally with cancellation and a short-lived cache, avoiding a flash back to the exercise. Restored splash sentence and simplified exercise headings.
- Existing layout, libraries and progress are preserved. Public data scope, installation, authorship and upstream licensing are unchanged.

验证与限制 / Validation and limitations: [docs/TESTING.md](docs/TESTING.md). Maintainer: **WarlockDi**, e99866@outlook.com.

## 1.4.6 — Public distribution

- Maintainer and InkWords modification author: **WarlockDi**, e99866@outlook.com.
- Single-file installation: built-in original demo cards initialize on first launch; existing libraries remain untouched.
- Replace Windows-derived glyph resources with OFL-1.1 InkWords UI Font derived from Noto Sans CJK SC Bold; notices included.
- Publish source, build tools, public smoke tests, real runtime previews and clear upstream acknowledgements.
- Do not redistribute the personal 108-book collection, scraped examples or user progress.
- Preserve 1.4.5 exercise behavior and progress format. New public build is simulated/tested, not yet revalidated on hardware.

## 1.4.5 — Personal build

- Correct-spelling label and reference word share a line when they fit; exceptionally long words continue without truncation.
- Easy spelling hides two letters, except two-letter words retain one visible letter.

## 1.4.4

- Keep submitted letters above; show reference spelling below with adaptive size.

## 1.4.3

- Fix underline widths/positions across answer states; release old exercise memory before switching modes.

## 1.4.2

- Rename letter fill to 拼写单词; handle loader scheduling failure, cancel stale tasks on return, defer spelling eligibility reads.

Earlier development added interactive practice, categories, local summaries, reset/restore, on-demand vocabulary loading and conservative memory evidence rules on top of the upstream MIT mini-app. This history documents changes, not independent certification of every old build.
