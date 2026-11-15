# 验证记录 / Verification

Public build **1.4.6**, maintained by **WarlockDi**. Tests use the actual bundled Lua code and the Noto-derived glyph blocks shipped in this repository.

| Check | Result |
| --- | --- |
| First installation with no AppFiles | Creates 20-card library automatically; verifies each write; catalogue written last |
| Existing valid or damaged catalogue | Valid catalogue is preserved; unreadable/empty existing catalogue is not replaced |
| Simulated failure on each first-run file write | Failure reported, retry succeeds, no premature catalogue commit |
| Seven modes with public demo cards | Open, answer spelling, return and reopen passed |
| 108 personal books, spelling | Passed locally; these books are not distributed |
| Adaptive spelling | 1,280 cases; minimum-two easy blanks with short-word exception, repeated letters and candidate availability |
| Font layout | 26 Latin candidates centered, missing-resource fallback, redraw cache checked |
| Loader recovery | Simulated callback rejection and 36 interrupted opens/reopens |
| Random interaction | 3,000 operations, six seeds, 296 runtime reconstructions |
| Continuous practice | 6,000 questions across three large local books |
| Screenshots | Actual Lua drawing commands; spelling, matching and About inspected |
| Install container | Decrypted code/data compared with inputs; asset integrity verified |

The stress harness uses an artificial **1 MiB Lua heap ceiling** and simulated file/timer APIs. This is not a measurement of actual device RAM, I/O speed, battery life or firmware limits. The 6,000-question run peaked close to that artificial ceiling (1,048,552 bytes) and collected to approximately 483–536 kB; passing it is not proof of unlimited stability. Firmware differences can still reveal issues.

This public build has **not yet been revalidated on physical hardware**. Earlier personal versions were tested by the owner, but that does not certify this font and installer update. No promise of “zero crashes” or support for other readers is made.

Reproducible public smoke tests: `python tests/smoke.py`. Full private-library stress fixtures are deliberately not uploaded. Public screenshots render native text using a desktop font substitute; embedded glyphs come from this public build, but hardware font metrics and e-ink refresh can differ.

反馈请注明版本、设备/固件、词库名、题型、操作步骤。先在 GitHub Issues 提交可复现问题，或联系 e99866@outlook.com；避免上传私人学习记录。公开邮箱可能收到垃圾邮件。
