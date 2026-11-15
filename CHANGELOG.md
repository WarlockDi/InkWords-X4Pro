# Version history / 版本说明

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
