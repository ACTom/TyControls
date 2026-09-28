# 终端控件 3 期 · 3a 键盘（Task 1–3）

> 本文件是 [`2026-09-29-terminal-phase-3.md`](2026-09-29-terminal-phase-3.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件。

**这一批做完能看到什么**：`tyControls.Terminal.Keyboard` 的四个函数与上游逐位相同——`evaluateKeyboardEvent` 在「VK × 16 种修饰键 × 应用光标 × 三种平台设置」的全组合上、第三层 Shift、粘贴编码；美式布局表两边一致。段末编译一次，只跑 3a 的 suite。

键盘的基准和 1、2 期同一套：`lib-dump.js` 加载上游 `out/`，脚本只有输入、期望值由上游算。

---

### Task 1: 键盘与粘贴的基准脚本

**Files:**
- Modify: `tools/terminal-oracle/lib-dump.js`（`PORTED`、`GENERATED`）
- Create: `tools/terminal-oracle/cases/keyboard.js`、`tools/terminal-oracle/keyboard-cases.js`
- Modify: `tools/terminal-oracle/regen-all.js`（`SCRIPTS` 追加 `keyboard-cases.js`）
- Generate: `tests/fixtures/terminal-keyboard.json`（超 1.8MB 自动分片）、`tests/fixtures/terminal-paste.json`

- [ ] **Step 1: `lib-dump.js`**（编辑工具）

`PORTED` 追加 `common/input/Keyboard`、`browser/Clipboard`（Task 1），`browser/Types`（Task 4 的色表也用，这里一起加）；`GENERATED` 追加 `tests/fixtures/terminal-keyboard(-\d+)?.json`、`tests/fixtures/terminal-paste.json`（照已有条目的写法，正则或字符串）。试一次 `require(L.XTERM + '/' + L.OUT_DIR + '/browser/CoreBrowserTerminal.js')`：能加载就把 `browser/CoreBrowserTerminal` 也加进 `PORTED`、第三层 Shift 用上游算（开工前问题二第 19 条）；加载抛错就不加，脚本注释写一句原因（错误消息的第一行）。

- [ ] **Step 2: 美式布局表——唯一真源**（`keyboard-cases.js` 顶部的常量 `US_LAYOUT`，Pascal 的表由 Task 3 逐项对它比）

每行 `[vk, key, shiftedKey, code]`，`key` / `shiftedKey` 是浏览器 `KeyboardEvent.key` 的值（不按 Ctrl / Alt 变——浏览器在 Ctrl 下给的 `key` 仍是字母本身）：

| VK | key / shiftedKey | code |
|---|---|---|
| 8、9、13、27 | `Backspace`、`Tab`、`Enter`、`Escape`（两列相同） | 同 key |
| 16、17、18、20 | `Shift`、`Control`、`Alt`、`CapsLock` | `ShiftLeft`、`ControlLeft`、`AltLeft`、`CapsLock` |
| 32 | `' '` / `' '` | `Space` |
| 33–40 | `PageUp`、`PageDown`、`End`、`Home`、`ArrowLeft`、`ArrowUp`、`ArrowRight`、`ArrowDown` | 同 key |
| 45、46 | `Insert`、`Delete` | 同 key |
| 48–57 | `0`–`9` / 上游 `KEYCODE_KEY_MAPPINGS` 第二列（`Keyboard.ts:11-36`：`)!@#$%^&*(`） | `Digit0`–`Digit9` |
| 65–90 | `a`–`z` / `A`–`Z` | `KeyA`–`KeyZ` |
| 91、93 | `Meta`、`ContextMenu` | `MetaLeft`、`ContextMenu` |
| 96–105 | `0`–`9`（两列相同，NumLock 开） | `Numpad0`–`Numpad9` |
| 106、107、109、110、111 | `*`、`+`、`-`、`.`、`/` | `NumpadMultiply`、`NumpadAdd`、`NumpadSubtract`、`NumpadDecimal`、`NumpadDivide` |
| 112–123 | `F1`–`F12` | 同 key |
| 144 | `NumLock` | 同 key |
| 186–192、219–222 | `KEYCODE_KEY_MAPPINGS` 两列 | `Semicolon`、`Equal`、`Comma`、`Minus`、`Period`、`Slash`、`Backquote`、`BracketLeft`、`Backslash`、`BracketRight`、`Quote` |
| 229 | `Process` | `''` |

表外的 VK：`key = 'Unidentified'`、`code = ''`（两边同样处理）。脚本断言每个 VK 只出现一次、数字与符号两列与上游 `KEYCODE_KEY_MAPPINGS` 相同（从上游源码 `Keyboard.ts` 文本里正则取出比，防手抄错）。

- [ ] **Step 3: 手写输入 `cases/keyboard.js`**（Write 工具；只有输入，没有期望值）

1. **全组合**（脚本生成，不手写）：表里每个 VK × 16 种修饰键（shift / alt / ctrl / meta 的位组合）× `applicationCursorMode` ∈ {false, true} × 平台 ∈ {win：`isMac=false`；mac：`isMac=true, macOptionIsMeta=false`；macMeta：`isMac=true, macOptionIsMeta=true`}。`key` 取 shift 位决定的那一列。约 95 × 16 × 2 × 3 ≈ 9100 例。
2. **手写事件**（显式 `{keyCode, key, code, shift, alt, ctrl, meta}`，LCL 造不出来、但函数有分支的）：keyCode 0 + `UIKeyInputUpArrow` / `…LeftArrow` / `…RightArrow` / `…DownArrow`（两种应用光标）；keyCode 13 + `key: 'c'` + ctrl；`key: 'Dead'` + `code: 'KeyN'` / `'KeyE'` + alt（± shift）；keyCode 191 + `key: '/'` + ctrl（`#5457` 那条）；`key: 'é'`、`key: '€'`、`key: '😀'`（keyCode 都取 69；`length` 按 UTF-16，前两个是 1、😀 是 2）无修饰；Option 在 macOS 上产生的字符（`key: 'å'`，keyCode 65，alt）三种平台。
3. **第三层 Shift**：上面全组合里去掉 meta 位（上游三项都要求 `!metaKey` 或不看）的事件 × `isMac` / `isWindows` 四种（win：`isWindows`；mac；linux：两者都 false）× `macOptionIsMeta` × `keypress` ∈ {false, true}；外加 `AltGraph = true` 的若干（Windows 下 `getModifierState('AltGraph')` 那一项）。
4. **粘贴**：`''`、`'a'`、`'a\nb'`、`'a\r\nb'`、`'a\rb'`（单独的 CR 不动）、`'a\n\nb'`、`'\x1b[201~evil'`、`'中文\n😀'`、`'\x1b\x1b'`、只有换行的 `'\n'`；每个 × 括号粘贴 ∈ {false, true}。

- [ ] **Step 4: `keyboard-cases.js`**（Write 工具）

- `const K = require(L.XTERM + '/' + L.OUT_DIR + '/common/input/Keyboard.js')`，调 `K.evaluateKeyboardEvent(ev, appCursor, isMac, macOptionIsMeta)`；`ev` 是普通对象 `{keyCode, key, code, shiftKey, altKey, ctrlKey, metaKey, type: 'keydown'}`。
- 结果记 `[type, cancel ? 1 : 0, key === undefined ? null : b64(utf8(key))]`（`type` 是数：0–3）。
- 第三层 Shift：Step 1 能加载上游就 `CoreBrowserTerminal.prototype._isThirdLevelShift.call({ options: { macOptionIsMeta } }, { isMac, isWindows }, evWithType)`，`evWithType` 带 `type: keypress ? 'keypress' : 'keydown'` 和 `getModifierState: m => m === 'AltGraph' && altGraph`；不能加载就不生成这一类（Task 3 改用手写表）。
- 粘贴：`Clipboard.bracketTextForPaste(Clipboard.prepareTextForTerminal(text), bracketed)`，与上游 `paste()` 的调用顺序相同（`src/browser/Clipboard.ts:45-54`，执行时核对行号）。
- **格式**（外壳照 2 期「夹具格式」：`upstream`、`generator`、`kind`、`part` / `parts`）：
  - `terminal-keyboard.json`：`{ layout: US_LAYOUT, combos: [[vk, mods, app, platform, type, cancel, keyB64|null] ...], hand: [{ id, ev: {...}, app, isMac, optMeta, type, cancel, key }], third: [[vk, mods, altGraph, isMac, isWindows, optMeta, keypress, result] ...] | null }`。`mods` = `shift | alt<<1 | ctrl<<2 | meta<<3`（同上游 `modifiers` 的位序）；`platform` 0 = win、1 = mac、2 = macMeta。
  - `terminal-paste.json`：`{ cases: [[textB64, bracketed, outB64] ...] }`。
- 打印各类条数；可复现（不读时间、对象键固定顺序、`JSON.stringify` 不缩进）。

- [ ] **Step 5: 跑脚本、确认可复现**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/keyboard-cases.js && git status --short tests/fixtures && node tools/terminal-oracle/keyboard-cases.js && git status --short tests/fixtures
```

Expected：第一次多出两个（或分片的几个）夹具；第二次跑完 `git status` 与第一次相同（先 `git add` 再跑一次，`git diff --quiet` 为真）。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/ tests/fixtures/terminal-keyboard*.json tests/fixtures/terminal-paste.json && git commit -m "test(terminal): keyboard and paste expectations from xterm.js

Every key the US layout has, under all sixteen modifier combinations,
with and without application cursor keys, on Windows-like and macOS
settings, goes through xterm.js's evaluateKeyboardEvent; so do the
events LCL cannot produce but the function has branches for. The layout
table lives in the script and is written into the fixture, so the Pascal
side is held to the same table. Paste text goes through the two
clipboard helpers, with and without bracketed paste.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异表（期末做，JS 侧）：**

| # | 变异 | 必须红 |
|---|---|---|
| K1 | `US_LAYOUT` 里 50 的 shiftedKey `@` 改成 `"`（英式布局） | 脚本自己的断言（和上游 `KEYCODE_KEY_MAPPINGS` 比）；去掉那条断言后，Task 3 的 `TestLayoutMatchesTheFixture` |
| K2 | 全组合漏掉 meta 位（`mods` 只到 7） | `TestEvaluateMatchesUpstream` 的应比次数断言（夹具条数变了，Pascal 侧算出的应比次数按「表 × 16 × 2 × 3」，对不上） |

---

### Task 2: `tyControls.Terminal.Keyboard`

**Files:**
- Create: `source/tyControls.Terminal.Keyboard.pas`
- Modify: `tycontrols.lpk`（`<Files>` 里 `tyControls.Terminal.Core.pas` 之后，写法照已有条目）

- [ ] **Step 1: 单元头**（照 Core 单元头的格式）

移植自 xterm.js 6.0.0（commit `c58ea3637f39`）：`src/common/input/Keyboard.ts`（`evaluateKeyboardEvent`、`KEYCODE_KEY_MAPPINGS`）、`src/browser/Clipboard.ts`（`prepareTextForTerminal`、`bracketTextForPaste`）、`src/browser/CoreBrowserTerminal.ts:937-948`（`_isThirdLevelShift`）；版权行：`Keyboard.ts` 头部的「Copyright (c) 2014 The xterm.js authors」「Copyright (c) 2012-2013, Christopher Jeffrey」、`Clipboard.ts` 的「Copyright (c) 2016 The xterm.js authors」，外加仓库 `LICENSE:1-3` 三行；「MIT，全文见 THIRD-PARTY-NOTICES.md」。再写一段「和上游不同的形状」：`Key` / `Code` 是 UTF-8、`key.length` 按 UTF-16 单元算；`AltGraph` 字段代替 `getModifierState('AltGraph')`；美式布局表由测试对夹具比。

- [ ] **Step 2: `TyTerminalEvaluateKey`**——逐分支照 `Keyboard.ts:38-380`，**不重排、不合并分支**（审查时逐行对）。要点：
  - `modifiers := Ord(Shift) or Ord(Alt) shl 1 or Ord(Ctrl) shl 2 or Ord(Meta) shl 3`；序列里的 `modifiers + 1` 用 `IntToStr`。
  - 三个方向键和上方向键的 `if (ev.metaKey) break;` 在 `modifiers` 判断**之前**（Meta+方向键什么都不发）。
  - PgUp / PgDn：Shift 优先（本地翻页），其次 **只看 Ctrl** 才带修饰码（`'[5;' + (modifiers + 1) + '~'`，Alt+PgUp 发普通的 `ESC[5~`）。
  - Insert：Shift 或 Ctrl 按着就什么都不发（留给宿主的复制粘贴）。
  - 默认分支四个 `else if` 的顺序：Ctrl 单独 → (非 Mac 或 OptionIsMeta) 且 Alt 且非 Meta → Mac 且只有 Meta（Cmd+A 全选）→ 无修饰且 `keyCode >= 48` 且 `key` 恰一个 UTF-16 单元 → Ctrl+Shift 的三个 `code`。
  - `String.fromCharCode(n)` 一律按码位编 UTF-8（这里都 < 128）；`toUpperCase` 只作用于 ASCII 字母。
  - `C0` 常量取 Core 单元已有的（`data/EscapeSequences.ts` 的移植）或本单元私有常量——**不**为此引 Core 单元（Keyboard 保持只依赖 `SysUtils` / `Classes` / `LCLType`）。

- [ ] **Step 3: `TyTerminalKeyEventFromLCL`**：按 Task 1 的表（Pascal 常量数组，按 VK 排序，二分或直接 256 项查表）填 `Key` / `Code`；`ssShift` / `ssCtrl` / `ssAlt` / `ssMeta` / `ssAltGr` → 五个布尔。表外 VK：`'Unidentified'` / `''`。

- [ ] **Step 4: `TyTerminalIsThirdLevelShift`**：`third := (AIsMac and not AMacOptionIsMeta and Alt and not Ctrl and not Meta) or (AIsWindows and Alt and Ctrl and not Meta) or (AIsWindows and AltGraph)`；`AKeyPress` 为真直接返回 `third`，否则 `third and ((KeyCode = 0) or (KeyCode > 47))`。

- [ ] **Step 5: `TyTerminalPrepareTextForPaste`**：先把 `\r\n` 和单独的 `\n` 换成 `\r`（正则 `/\r?\n/g` 的语义：单独的 `\r` 不动），括号粘贴时再把每个 ESC（`#27`）换成 U+241B 的 UTF-8（`E2 90 9B`）并包上 `ESC[200~` / `ESC[201~`。输入按 UTF-8 原样过，不校验。

- [ ] **Step 6: 加进 `.lpk`，提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Keyboard.pas tycontrols.lpk && git commit -m "feat(terminal): keys, paste and focus into bytes, ported from xterm.js

evaluateKeyboardEvent is ported branch by branch, with the US layout
table LCL needs to fill in the browser's key and code; the third-level
shift test keeps all three of xterm.js's conditions, AltGr included;
paste text gets its line endings turned into CR and, under bracketed
paste, its escapes made harmless before the brackets go on.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 键盘测试

**Files:**
- Create: `tests/test.terminal.keyboard.pas`
- Modify: `tests/tytests.lpr`（uses 里 `test.terminal.core` 之后加 `test.terminal.keyboard`）

夹具读法照 `tests/test.terminal.oracle.pas`（`TyTermLoadFixtures`、`TTyTermMisses`，分片连号检查），比较器只计数、记前 30 条，循环外断言一次（2 期地雷 11）。

**`TTyTerminalKeyboardOracleTests`**（判据）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestLayoutMatchesTheFixture` | 夹具 `layout` 每行：`TyTerminalKeyEventFromLCL(vk, [])` 的 `Key` / `Code` 等于第 2 / 4 列，`[ssShift]` 的 `Key` 等于第 3 列；另查 5 个表外 VK（0、1、150、200、255）得 `'Unidentified'` / `''`。比较次数 = 行数 × 3 + 5 | K3：Pascal 表里 219 / 221 的 key 对调 |
| `TestEvaluateMatchesUpstream` | 夹具 `combos` 每条：由 `(vk, mods)` 造 `TShiftState` → `TyTerminalKeyEventFromLCL` → `TyTerminalEvaluateKey(ev, app, platform>0, platform=2)`，`Kind` 的序号、`Cancel`、`Key` 字节全等。失败打印 `vk=<n>(<key>) mods=<shift alt ctrl meta> app=<0/1> <win/mac/macMeta>: want <kind cancel hex> got <…>`。比较次数 = `combos` 条数，且等于「表行数 × 16 × 2 × 3」 | K4–K12（下表） |
| `TestHandEventsMatchUpstream` | `hand` 每条直接用夹具给的事件（不经布局表） | K13 |
| `TestThirdLevelShiftMatchesUpstream` | `third` 非空时逐条比；为空时本测试改走手写表（Task 1 Step 1 的结论），并在测试名旁注释「上游在 node 里加载不了：<原因>」 | K14、K15 |
| `TestPasteMatchesUpstream` | `terminal-paste.json` 逐条字节全等 | K16、K17 |

手写表（`third` 为空时用，也在 `TTyTerminalKeyboardTests` 里留一份做可读的回归）：

| 事件 | isMac | isWindows | optMeta | keypress | 期望 |
|---|---|---|---|---|---|
| Ctrl+Alt+Q（81） | F | T | F | F | True |
| Ctrl+Alt+Left（37） | F | T | F | F | False（keyCode ≤ 47） |
| Ctrl+Alt+Left | F | T | F | T | True |
| Ctrl+Alt+Q | F | F | F | F | False（Linux：上游只认 Windows 的 Ctrl+Alt） |
| AltGraph+Q | F | T | F | F | True |
| AltGraph+Q | F | F | F | F | False |
| Alt+Q | T | F | F | F | True |
| Alt+Q | T | F | T | F | False |
| Alt+Ctrl+Q | T | F | F | F | False |
| Meta+Ctrl+Alt+Q | F | T | F | F | False |

**`TTyTerminalKeyboardTests`**（可读的输入 / 期望表，独立于夹具；每行也是一个变异靶子）：

| 按键（LCL） | app | 平台 | 期望 |
|---|---|---|---|
| VK_UP | F | win | `ESC [ A` |
| VK_UP | T | win | `ESC O A` |
| Shift+VK_UP | T | win | `ESC [ 1 ; 2 A`（有修饰就不看应用光标） |
| Ctrl+VK_LEFT | F | win | `ESC [ 1 ; 5 D` |
| Meta+VK_LEFT | F | mac | 空 |
| VK_HOME / VK_END | T | win | `ESC O H` / `ESC O F` |
| VK_F1 / Shift+VK_F1 | F | win | `ESC O P` / `ESC [ 1 ; 2 P` |
| VK_F5 / Ctrl+VK_F5 | F | win | `ESC [ 1 5 ~` / `ESC [ 1 5 ; 5 ~` |
| VK_F11 | F | win | `ESC [ 2 3 ~` |
| VK_BACK / Ctrl / Alt | F | win | `7F` / `08` / `ESC 7F` |
| VK_TAB / Shift+VK_TAB | F | win | `09`（Cancel）/ `ESC [ Z` |
| VK_RETURN / Alt+VK_RETURN | F | win | `0D` / `ESC 0D` |
| VK_ESCAPE / Alt+VK_ESCAPE | F | win | `1B` / `1B 1B` |
| VK_INSERT / Shift+VK_INSERT / Ctrl+VK_INSERT | F | win | `ESC [ 2 ~` / 空 / 空 |
| VK_DELETE / Shift+VK_DELETE | F | win | `ESC [ 3 ~` / `ESC [ 3 ; 2 ~` |
| Shift+VK_PRIOR / Ctrl+VK_PRIOR / Alt+VK_PRIOR | F | win | 种类 PageUp / `ESC [ 5 ; 5 ~` / `ESC [ 5 ~` |
| Ctrl+A / Ctrl+Z | F | win | `01` / `1A` |
| Ctrl+Space / Ctrl+3 / Ctrl+7 / Ctrl+8 | F | win | `00` / `1B` / `1F` / `7F` |
| Ctrl+[ / Ctrl+\ / Ctrl+] / Ctrl+/ | F | win | `1B` / `1C` / `1D` / `1F` |
| Ctrl+Shift+2 / Ctrl+Shift+6 / Ctrl+Shift+- | F | win | `00` / `1E` / `1F` |
| Ctrl+Shift+C / Ctrl+Shift+V | F | win | 空（留给复制粘贴快捷键） |
| Alt+A / Alt+Shift+A / Ctrl+Alt+A | F | win | `ESC a` / `ESC A` / `ESC 01` |
| Alt+2 / Alt+Shift+2 | F | win | `ESC 2` / `ESC @` |
| Alt+Space / Ctrl+Alt+Space | F | win | `ESC 20` / `ESC 00` |
| Alt+A | F | mac | 空（第三层，留给字符） |
| Alt+A | F | macMeta | `ESC a` |
| Meta+A | F | mac | 种类 SelectAll |
| A / Shift+A（无修饰） | F | win | `a` / `A`（KeyDown 里控件不发，见 Task 11；这里只验函数） |
| VK_NUMPAD5 / VK_MULTIPLY | F | win | `5` / `*`（不看小键盘模式，开工前问题一第 1 条） |
| VK_PROCESSKEY（229） | F | win | 空 |
| 粘贴 `'a\r\nb\nc'`，非括号 | — | — | `a 0D b 0D c` |
| 粘贴 `'x\x1b[201~y'`，括号 | — | — | `ESC [ 2 0 0 ~ x E2 90 9B [ 2 0 1 ~ y ESC [ 2 0 1 ~` |

**变异表（期末做）：**

| # | 变异 | 必须红 |
|---|---|---|
| K3 | Pascal 布局表 219 / 221 的 key 对调 | `TestLayoutMatchesTheFixture`；`TestEvaluateMatchesUpstream`（Alt+[） |
| K4 | `modifiers + 1` 写成 `modifiers` | 两个测试都红（Shift+Up） |
| K5 | 方向键的 `metaKey` 早退挪到 `modifiers` 判断之后 | `TestEvaluateMatchesUpstream`（mac Meta+Left） |
| K6 | PgUp 的 Ctrl 判断改成 `modifiers <> 0` | Alt+PgUp 行 |
| K7 | Backspace 的 Ctrl 分支对调（`^H` / `DEL`） | Ctrl+Backspace 行 |
| K8 | Alt 分支去掉 `(not AIsMac or AMacOptionIsMeta)` | mac Alt+A 行 |
| K9 | Alt 分支字母忘了 Shift 转大写 | Alt+Shift+A 行 |
| K10 | 默认分支的「单字符」判断按 UTF-8 字节数 | `TestHandEventsMatchUpstream`（`key: 'é'` 两字节却是一个 UTF-16 单元） |
| K11 | Ctrl+数字 `51–55` 的区间写成 `51–56` | Ctrl+8 行（应走 `DEL` 分支） |
| K12 | Insert 分支去掉 Ctrl 条件 | Ctrl+Insert 行 |
| K13 | `keyCode = 0` 的四个 `UIKeyInput*` 删掉 | `TestHandEventsMatchUpstream` |
| K14 | 第三层 Shift 去掉 AltGraph 那一项 | `TestThirdLevelShift*`（AltGraph+Q） |
| K15 | keydown 时去掉 `KeyCode > 47` | Ctrl+Alt+Left 行 |
| K16 | 粘贴只换 `\n`、不先吃 `\r\n` | `TestPasteMatchesUpstream`（`a\r\nb` → `a\r\rb`） |
| K17 | 括号粘贴不替换 ESC | `TestPasteMatchesUpstream` |

- [ ] **Step 1: 写测试单元、加进 `tytests.lpr`**
- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.keyboard.pas tests/tytests.lpr && git commit -m "test(terminal): keyboard encodings held to xterm.js

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: 段 3a 编译并跑本段 suite**（主文件「跑测试的固定套路」3a 行）。只修本段的红；以上游为准。修复提交 `fix(terminal): ...`。
