# 终端控件 4 期 · 4a 基准与纯逻辑（Task 1–4）

> 本文件是 [`2026-09-29-terminal-phase-4.md`](2026-09-29-terminal-phase-4.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 1–12、19–23，开工前问题二第 1–6 条，地雷 4–7。

**这一批做完能看到什么**：四份夹具由上游代码本身生成（选区服务、网址提供者、OSC 8 提供者、Linkifier 的去重叠与命中、剪贴板 addon、鼠标服务的事件映射、`getCoords`、拖动滚速）；两个新的纯逻辑单元逐项对上；Core 有 `OnUserInput`，Buffer 有 `TrimmedLines`。段末编译一次，只跑 4a 的 suite。

---

### Task 1: 基准脚本与四份夹具

**Files:**
- Create: `tools/terminal-oracle/selection-cases.js`、`tools/terminal-oracle/cases/selection.js`
- Create: `tools/terminal-oracle/url-cases.js`、`tools/terminal-oracle/cases/links.js`
- Create: `tools/terminal-oracle/clipboard-cases.js`、`tools/terminal-oracle/mouse-cases.js`
- Modify: `tools/terminal-oracle/lib-dump.js`、`tools/terminal-oracle/regen-all.js`
- Generate: `tests/fixtures/terminal-selection.json`、`terminal-links.json`、`terminal-osc52.json`、`terminal-mouse-events.json`

含正则、`\x1b`、`\u` 的 JS 一律用 Write 工具落文件（地雷 2）。脚本只用 node 内置模块，只经 `lib-dump.js` 加载上游。

- [ ] **Step 1: `lib-dump.js`**

1. `PORTED` 追加（源 → 产物）：`src/browser/services/SelectionService.ts`、`src/browser/selection/SelectionModel.ts`、`src/browser/input/Mouse.ts`、`src/browser/services/MouseService.ts`、`src/browser/OscLinkProvider.ts`、`src/browser/Linkifier.ts`、`src/browser/renderer/dom/DomRendererRowFactory.ts`（都在 `${OUT_DIR}/browser/...`）；`addons/addon-web-links/src/WebLinkProvider.ts`、`addons/addon-web-links/src/WebLinksAddon.ts`（产物 `addons/addon-web-links/${OUT_DIR}/*.js`）；`addons/addon-clipboard/src/ClipboardAddon.ts`（`addons/addon-clipboard/${OUT_DIR}/ClipboardAddon.js`）。
2. 新函数 `loadBrowserParts()`（在 `loadUpstream()` 之后调），返回 `{ SelectionService, DomRendererRowFactory, Linkifier, OscLinkProvider, MouseService, getCoords, LinkComputer, strictUrlRegex, ClipboardAddon }`。`strictUrlRegex` 这样取（它不导出）：`new WebLinksAddon().activate({ registerLinkProvider: p => { captured = p; return { dispose() {} }; } })`，取 `captured._regex`，并断言它的 `source` 与 `WebLinksAddon.ts:21` 那一行字面相同（读源文件比，防止产物过期或被改）。
3. 新函数 `fakeBrowser(term, opts)`：造选区服务要的几个假对象——`screenElement`（`ownerDocument` 的 `addEventListener` / `removeEventListener` 空实现，`getBoundingClientRect` 答 `{left: 0, top: 0}`）、`window`（`requestAnimationFrame` 答 0 不回调、`setInterval` 答 1、`clearInterval` 空、`getComputedStyle` 的 `getPropertyValue` 答 `'0'`）、`renderService.dimensions.css.canvas.height = rows × CELL_H`（`CELL_H = 10`）、`mouseCoordsService.getCoords` 答「当前步骤给的点」（1 起，见 Step 2）、`linkifier.currentLink` 按步骤给。
4. `GENERATED` 追加四份夹具。
5. 头注释补一段：这四类的上游是浏览器层代码，靠假对象 + 原型调用在 node 里跑，假对象只提供坐标与尺寸，不含逻辑。

- [ ] **Step 2: `selection-cases.js` + `cases/selection.js`**

每个用例：`{ id, cols, rows, scrollback, wordSeparator?, steps }`。脚本建 headless 终端（`L.makeTerminal` 同款选项 + 用例的尺寸与滚回），用 `term._core._bufferService` / `coreService` / `optionsService` / `mouseStateService` 与 `fakeBrowser` 构造 `SelectionService`，订阅 `onSelectionChange` 计数。步骤（输入只有这些字段，Pascal 侧逐字段照做）：

| 步骤 | 上游调用 | 说明 |
|---|---|---|
| `{ write: <base64> }` | `term.write(bytes)`，等回调 | trim 由上游的 `onTrim` 订阅处理 |
| `{ resize: [c, r] }` | `term.resize(c, r)` | 行数变了上游清选区 |
| `{ scroll: n }` | `term.scrollLines(n)` | 视口移动 |
| `{ press: { at: [x, vr], detail, button, shift, alt, enabled } }` | 先按 `enabled` 调 `enable()` / `disable()`（只在变化时，`disable` 会清选区——这正是上游行为），再 `handleMouseDown(ev)` | `at` 是选区点：`x` 0..cols（边界）、`vr` 视口行（0 起）；假 `getCoords` 答 `[x + 1, vr + 1]`；`ev = { button, detail, shiftKey, altKey, timeStamp: 0, preventDefault(){}, stopPropagation(){} }` |
| `{ move: { at: [x, vr], py } }` | `_handleMouseMove(ev)` | `py` 是相对网格顶的整数设备像素（可为负）；`ev.clientY = py + 0.5`（像素中心），`stopImmediatePropagation(){}` |
| `{ dragScroll: true }` | `_dragScroll()` | 上游会发 `onRequestScrollLines`：脚本订阅它、照 `CoreBrowserTerminal.ts:599` 调 `term.scrollLines(amount)` |
| `{ release: true }` | `_handleMouseUp({ timeStamp: 1000, altKey: false })` | 永远不带 Alt（Alt+单击移动光标不做，§15） |
| `{ rightClick: { at } }` | `rightClickSelect(ev)` | macOS 行为（开工前问题一第 3 条） |
| `{ link: [sx, sy, ex, ey] }` | 设 `linkifier.currentLink = { link: { range } }`（1 起闭区间）；`{ link: null }` 清掉 | 下一次双击用 |
| `{ selectAll }`、`{ selectLines: [a, b] }`、`{ setSelection: [c, r, len] }`、`{ clear }` | 同名方法 | |
| `{ userInput: true }` | `term._core.coreService.triggerDataEvent('x', true)` | 上游 `onUserInput` 清选区 |

每步之后导出（全部字段逐步比）：`start` / `end`（`finalSelectionStart` / `End`，`null` = undefined）、`raw`（`_model.selectionStart`、`selectionEnd`、`selectionStartLength`、`isSelectAllActive`）、`mode`（`_activeSelectionMode` 0–3）、`has`、`text`（`selectionText`，UTF-8 的 base64，行分隔是 `\n`）、`changes`（本步 `onSelectionChange` 的次数）、`dragAmount`（`_dragScrollAmount`）、`ydisp`、`ybase`、`trimmed`（本步上游 `onTrim` 的累计量，给 Pascal 侧核对 `TrimmedLines` 的差值）、`spans`（视口每一行：用 `DomRendererRowFactory.prototype._isCellInSelection.call({ _selectionStart: start, _selectionEnd: end, _columnSelectMode: mode === 3 }, x, 绝对行)` 扫 `x = 0..cols−1`，断言命中的列连续，导出 `[from, to)` 或 `null`）。

`cases/selection.js` 至少这些组（每组几个用例，**每个判据单独一个用例**，spec §13.5 第 8 条）：
1. 单击拖动：同一行正向、反向；跨行；终点落在宽字符后半（`x++`）；起点落在宽字符后半；点在右边界 `x = cols`（早退）；在滚回里（先 `scroll: -5`）。
2. 双击取词：ASCII 词；路径 `a/b.c`（不是分隔符）；每个默认分隔符两侧各一例；纯空白段（允许）；从没写过的格子（空串是分隔符，核实记录 5）；中文连续字；`a😀b`；`cafe\u0301 x`；跨折行的词（向上接、向下接、上下都接）；自定义 `wordSeparator = ' :'`；词长超过列数被截。
3. 双击后拖（词模式）：正向跨词、反向跨词、跨折行。
4. 三击：普通行；三行折行段从中间一行点；三击后向上、向下拖（行模式）。
5. Shift+单击：`enabled` 时扩展；`enabled = false` 时（覆盖键）是新选区；没有起点时 Shift+单击无事。
6. Alt 列选：行长不一的矩形；x 反向；零宽列（文本 `''`）；列选里有折行（不接）。
7. 拖出边界：`py` 在网格上方 1、25、60 像素，下方 1、25、60 像素；随后 `dragScroll` 三次（有滚回内容）；列模式下 x 不被推到 0 / cols。
8. `selectAll`、`selectLines` 越界钳制、`setSelection` 长度跨行（恰好是列数的倍数、不是倍数两种）。
9. trim：滚回 5 行时选中滚回里的一段，再写 3 行、再写 10 行（终点也被挤掉 → 清空）；只有起点被挤掉（→ `[0, 0]`）。
10. 清空时机：有选区时 `userInput`；`resize` 只改列（不清）、改行（清）；`CSI ? 1049 h`（换缓冲，清）；`press` 带 `enabled: false` 且不带 Shift（`disable()` 清，且不新建选区）。
11. 选区文本：NBSP（`\u00a0` 写进去，复制出空格）；行尾空白去掉；折行接起来；首末行半截；中间有宽字符；最后一行正好到列尾。
12. 右键：已有选区时 `press` 右键（选区保留、`changes` 0）；`rightClick` 在选区外（选词，不含纯空白）、在选区内（不变）、在纯空白上（不选）。
13. 链接：`link` 设了范围后双击（选整条，跨折行的链接一例）。
14. 事件计数：无选区时单击（0）、有选区时单击（1）、松开时变了（1）没变（0）、`clear` 在没有选区时（仍 1）。

- [ ] **Step 3: `url-cases.js` + `cases/links.js`**

四部分，都写进 `terminal-links.json`：
1. **`prefix`**：`{ text, ok, base, protocol }`——`new URL(text)` 成功与否、`protocol`；`base` 用 `WebLinkProvider.ts:46-51` 那三行同一个公式从 `url` 算（脚本里照抄并注明出处行号：它是公式，真正的基准是 node 的 WHATWG `URL`）；另给 `isUrl`（同文件 `:52` 的前缀比较）。**过滤**：`url.hostname` 含 `xn--` 或输入主机含非 ASCII 的用例不进夹具（开工前问题二第 5 条的偏离），脚本打印被过滤的输入。输入（`cases/links.js` 的 `PREFIX`）：
   - 端口：`:80`、`:080`、`:0080`、`:443`（http）、`https://a.com:443`、`:8080`、`:08080`、`:65535`、`:65536`、`:0`、`:`（空）、`:8a`；
   - 用户信息：`u@`、`:p@`、`u:p@`、`u:p:q@`、`a@b@c.com`、`u;x@`、`u=x@`、`u[x@`、`%41@`；
   - 主机：大写、`ex%41mple.com`、`exa_mple.com`、`a..b.com`、`a.com.`、`127.0.0.1`、`127.1`、`0x7f.0.0.1`、`1.2.3.4.`、`256.1.1.1`、`1.2.3.08`、`[::1]`、`[0:0::1]`、`[::FFFF:1.2.3.4]`、`[1:2:3:4:5:6:7:8]`、`[1::2::3]`、`[::1]:8080`、`[::1`；
   - 协议：`HTTP://A.COM`、`https://`、`http:///x`、`http:\\a.com`、`ftp://a.com`、`file:///c:/x`、`ssh://h`、`mailto:a@b`、` http://a.com `（首尾空格）、`ht\ttp://a.com`（中间 Tab）、`javascript:alert(1)`。
2. **`urls`**：每个输入串单独写在一个 300 列终端的第 1 行（`\r\n` 分行），对该行跑 `LinkComputer.computeLink(1, strictUrlRegex, term, noop)`，导出 `[{ text, range }]`。输入：上游测试的全部形态（`addons/addon-web-links/test/WebLinksAddon.test.ts:33-188`：`testHostName` 七种写法 × 抽 12 个国家顶级域 + `.com` + `.com.<cc>` 三个；大写与默认端口五行；全角前后、韩文路径、用户名密码 + 组合字符、百分号参数）；另加我们的：U+3000 截断、NBSP 截断、结尾 `. , ! ? :` 各一、`(http://a.com)`、`<http://a.com>`、`"…"`、`'…'`、`http://a.com*`（结尾是 `*`）、`xhttp://a.com`、`Http://a.com`（不匹配）、`http://a.com/~u`、`http://a.com/p(1)`、`http://a.com/a,b`、一行三个网址、主机非 ASCII（`http://例子.测试`、`http://münchen.de`，两个都应当不算链接——这是 `isUrl` 真实给出的答案，不是偏离，保留在这一部分）。
3. **`lines`**：多行场景，`{ cols, rows, write, queries: [y…] }`；每个 `y` 导出 `web`（`computeLink`）、`osc`（`OscLinkProvider.provideLinks`，`linkHandler = null`）、`oscAll`（`term.options.linkHandler = { allowNonHttpProtocols: true, activate() {} }` 后再算）、`kept`（两路按 OSC 在前传给 `Linkifier.prototype._removeIntersectingLinks.call({ _bufferService: { cols } }, y, replies)` 之后剩下的）、`hits`（对 `y` 所在行和链接跨到的行，每个 `x = 1..cols` 用 `_linkAtPosition` 找「按提供者顺序第一个命中的」链接，导出下标或 -1）。场景：长网址折三行；网址在折行处遇到行尾空格子 + 下一行首是宽字符（`_mapStrIdx` 的 +1 补正）；向上扩展碰到含空格的段停下；2048 限制（折 12 行的长串）；OSC 8 相邻两条不同链接；同 id 同 URI；链接在行尾（`getTrimmedLength` 边界）；OSC 8 跨折行；`file://`、`ssh://`、`mailto:`、坏 URI `http://`、大写 `HTTP://X`；OSC 8 文本本身又像网址（去重叠：网址被去掉）；OSC 8 包住半个网址（部分重叠）。
4. OSC 8 的写法：`\x1b]8;id=<id>;<uri>\x1b\\文本\x1b]8;;\x1b\\`。

- [ ] **Step 4: `clipboard-cases.js`**

假终端 `{ parser: { registerOscHandler: (id, h) => { handler = h; return { dispose() {} }; } }, input: (s, user) => replies.push([s, user]) }`，假剪贴板 `{ readText: pc => '读到的 text\n', writeText: (pc, t) => writes.push([pc, t]) }`；`new ClipboardAddon(undefined, provider).activate(fake)`；每个用例调 `handler(data)`。导出 `{ data, writes: [[pc, <base64 of UTF-8 text>]], replies: [[<base64 of reply UTF-8>, user]] }`（文本一律 base64，夹具里可能有 NUL，[[fpjson-drops-u0000]]）。输入：`c;aGVsbG8=`、`c;?`、`p;?`、`;aGk=`、`c`、空串、`c;aGVsbG8=;x`、` c;aGVs bG8= `（空白）、`c;aGVsbG8`（缺 `=`）、`c;aGV$`、`c;aGVsb`（模 4 余 1）、`c;77u/QQ==`（BOM + A）、`c;/w==`（0xFF）、`c;8J+Y`（截断的 4 字节）、`c;7aCA`（代理区码位 ED A0 80）、`c;AA==`（NUL）、`c;5Lit5paH`（中文）、`c;` + 1 MB 的 base64（只比长度与哈希，导出 `sha1`）。脚本启动时断言 `typeof Uint8Array.fromBase64 === 'undefined'`（走 `atob` 路径，核实记录 23；将来 node 有了它要重新评估）。

- [ ] **Step 5: `mouse-cases.js`**

三部分，写进 `terminal-mouse-events.json`：
1. **`send`**：`MouseService.prototype._sendEvent.call(ctx, { target: {} }, ev)`，`ctx` 的假对象见 Task 1 探针（`getMouseReportCoords` 答固定格子、`areMouseEventsActive = true`、`mouseEventsRequireAlt = false`、`_triggerMouseEvent` 记下参数、`_consumeWheelEvent` 答 1）。事件：`mousedown` / `mouseup` × `button` 0–4；`mousemove` × `buttons` 0–7；每种再配 Ctrl / Alt / Shift 的 8 种组合（只对 `button 0` 按下和 `buttons 1` 移动全配，其余配「全不按」与「三个全按」两种）。导出 `{ type, button, buttons, ctrl, alt, shift, out: { button, action, ctrl, alt, shift } | null }`。
2. **`coords`**：`getCoords(win, { clientX: px + 0.5, clientY: py + 0.5 }, el, cols, rows, true, cw, ch, isSel)`；`cols = 10`、`rows = 5`，格子 `7 × 14` 与 `9 × 19` 两种；`px` 取 `-3..cols·cw+3` 全部、`py` 取 `-3..rows·ch+3` 全部；`isSel` 真假两种。导出 `[px, py, x, y]`（1 起，照上游）。
3. **`dragAmount`**：`SelectionService.prototype._getMouseEventScrollAmount.call(ctx, { clientX: 0, clientY: py + 0.5 })`，画布高 140 与 190；`py` 取 `-120..H+120` 全部。导出 `[H, py, amount]`。

- [ ] **Step 6: `regen-all.js`** 的 `SCRIPTS` 追加四个脚本；跑一遍：

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/selection-cases.js && node tools/terminal-oracle/url-cases.js && node tools/terminal-oracle/clipboard-cases.js && node tools/terminal-oracle/mouse-cases.js && ls -l tests/fixtures/terminal-selection.json tests/fixtures/terminal-links.json tests/fixtures/terminal-osc52.json tests/fixtures/terminal-mouse-events.json
```

Expected：四份夹具生成、每份 < 1.8 MB（超了 `writeFixture` 自动分片）；每个脚本打印用例数；`url-cases.js` 打印被过滤的输入（只应有 `xn--` / 非 ASCII 主机那几条前缀用例）。**抽查**：`aaa http://example.com aaa`（20 列）的 `start (5, 1)`、`end (2, 2)`；`selection` 第 2 组 `a😀b` 的双击选区长度。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle tests/fixtures/terminal-selection*.json tests/fixtures/terminal-links*.json tests/fixtures/terminal-osc52*.json tests/fixtures/terminal-mouse-events*.json && git commit -m "test(terminal): oracle for selection, links, OSC 52 and mouse events

The browser layer's selection service, web-links and OSC 8 providers,
link overlap and hit test, clipboard addon, mouse event mapping,
coordinate rounding and drag-scroll speed all run in node on a headless
terminal with a few fake DOM objects that only supply sizes and points.
Their answers are the fixtures the Pascal ports are held to.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异（JS 侧，期末做）**：J1：`fakeBrowser` 的 `CELL_H` 改成 11（`dragAmount` 夹具变 → Pascal 侧红）——验证夹具真的依赖假尺寸；J2：`strictUrlRegex` 的源码比较去掉（手改产物里的正则一个字符后脚本应当拒绝，改回）。

---

### Task 2: `tyControls.Terminal.Selection`

**Files:**
- Create: `source/tyControls.Terminal.Selection.pas`
- Modify: `tycontrols.lpk`（`<Files>` 末尾加）

单元头：移植自 xterm.js 6.0.0（commit、`src/browser/selection/SelectionModel.ts`、`src/browser/services/SelectionService.ts` 的非 DOM 部分、`src/browser/input/Mouse.ts:40-49` 的取整规则、`addons/addon-clipboard/src/ClipboardAddon.ts` 的参数与编解码规则），版权行照 `LICENSE:1-3`，addon-clipboard 另列 `Copyright (c) 2023`；「MIT，全文见 THIRD-PARTY-NOTICES.md」。依赖 `SysUtils`、`Classes`、`Types`、`tyControls.Unicode.Width`、`tyControls.Terminal.Buffer`。接口见主文件接口清单；`TTyTermLinkRange` 和 `PTyTermLinkRange = ^TTyTermLinkRange` 在这个单元声明（`Links` 单元引用它）。

- [ ] **Step 1: 模型**（`SelectionModel.ts:12-145` 逐方法）：`Clear`、`FinalStart`、`FinalEnd`（三种补正，核实记录 2）、`AreReversed`、`HandleTrim`。注意 `FinalEnd` 里 `startPlusLength % cols` 与 `Math.floor` 都是非负整数运算，照写 `mod` / `div`。

- [ ] **Step 2: 取词与取行**（`:793-1057`）：
  - 行串用 `UnicodeString`：`UTF8Decode(Buffer.TranslateBufferLineToString(row, False))`；格子文本长度用 `TyTermJsLength(line.GetChars(col))`（地雷 4）。
  - `ConvertViewportColToCharacterIndex`、`GetWordAt(point, allowWs, followAbove, followBelow)`、`SelectWordAt`、`SelectToWordAt`、`IsCharWordSeparator`（宽度 0 → False；`GetChars = ''` → True；否则 `Pos(chars, WordSeparators) > 0`）、`SelectLineAt`（`GetWrappedRangeForLine` + `getRangeLength`）。
  - `line.charAt(i) === ' '` 在下标越界时是 `'' === ' '` 为假——Pascal 取字符前先判下标。JS `trim()` 的空白用 `TyTermIsJsWhitespace`。

- [ ] **Step 3: 交互**：`Press`（单击 / 双击 / 三击 / 扩展，`:483-499`、`:531-601`；双击传了 `ALink` 就照 `:346-352` 选整条，`getRangeLength` 在 `BufferRange.ts:8-13`）、`DragTo`（`:619-686`，入参已是选区点与滚速）、`DragScrollAmount` / `AfterDragScroll`（`:692-716` 拆成两半：控件在两半之间滚视口）、`Release`（`_fireEventIfSelectionChanged`）、`RightClickSelect`（`:820-827`，`_isClickInSelection` = `_areCoordsInSelection` `:333-338`）、`SelectAll`、`SelectLines`、`SetSelection`、`Clear`、`HandleTrim`、`HasSelection`、`Text`（`:203-262`，列模式与普通模式、NBSP、分隔符参数）、`RowSpan`（`DomRendererRowFactory.ts:534-552` 的判定写成「这一行的 `[from, to)`」）。`OnChange` 在上游发 `onSelectionChange` 的每一处发（核实记录 9），`OnRedraw` 在上游调 `refresh()` 的每一处发。`Dragging` 在 `Press` 成功后为真、`Release` / `Clear` 后为假（上游挂 / 摘 mousemove 监听的时机：`_addMouseDownListeners` `:498`、`_removeMouseDownListeners` `:269`、`:725`、`:813`）。

- [ ] **Step 4: 几何与 OSC 52**：`TyTermSelectionPointAt`（开工前问题二第 6 条）、`TyTermDragScrollAmount`（`offset = AOffsetY + 0.5`；在 `[0, AHeight]` 内答 0；超出部分钳到 ±`AThreshold` 再除以 `AThreshold`；`Sign + Floor(offset × 14 + 0.5)`；`AThreshold` 是参数，不写死 50）、`TyTermOsc52Split`（按 `;` 切，不足两段 False，只取前两段）、`TyTermOsc52Decode`（WHATWG forgiving-base64：去掉 `#9 #10 #12 #13 #32`；长度模 4 为 0 时去掉末尾一个或两个 `=`；模 4 余 1 或含 `A-Za-z0-9+/` 以外的字符 → 失败答 `''`；再按 WHATWG UTF-8 解码：去开头 BOM、坏序列按最大子串换 U+FFFD、代理区码位与超长编码都算坏；结果转成控件用的 UTF-8 `string`）、`TyTermOsc52Reply`（标准 base64 带 `=`，`#27']52;' + Pc + ';' + b64 + #7`）。

- [ ] **Step 5: 进包**：`tycontrols.lpk` 的 `<Files>` 末尾加 `source/tyControls.Terminal.Selection.pas`（照 3 期几个终端单元的写法）。

- [ ] **Step 6: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Selection.pas tycontrols.lpk && git commit -m "feat(terminal): the selection, ported from xterm.js without its DOM

Word, line and column selection, dragging, the drag-scroll steps, how a
selection follows lines trimmed off the top, and the selected text --
the same code paths as xterm.js's SelectionService and SelectionModel,
in UTF-16 indices as upstream counts them. Also the pixel-to-boundary
rounding a selection uses and the OSC 52 argument and base64 rules.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `tyControls.Terminal.Links`

**Files:**
- Create: `source/tyControls.Terminal.Links.pas`
- Modify: `tycontrols.lpk`

单元头：移植自 `addons/addon-web-links/src/WebLinkProvider.ts`、`WebLinksAddon.ts:21`（正则的语义）、`src/browser/OscLinkProvider.ts`、`src/browser/Linkifier.ts:153-173`、`:370-375`；addon-web-links 另列 `Copyright (c) 2017`（`addons/addon-web-links/LICENSE:1`）。依赖同上，另加 `tyControls.Terminal.Selection`（`TTyTermLinkRange`）。

- [ ] **Step 1: URL 前缀解析 `TyTermParseUrlPrefix`**（开工前问题二第 5 条）。按 WHATWG URL 的顺序写，每一段注释标规范里的状态名（scheme start、special authority slashes、authority、host、port）：
  1. 去掉首尾 `<= U+0020` 的字符，删掉所有 Tab、LF、CR。
  2. 协议：ASCII 字母起头，随后 `[A-Za-z0-9+.-]*`，再 `:`；小写；不是 `http` / `https` → 仍可能成功（OSC 8 要知道协议），但本函数只对特殊协议走下面的权威解析；非特殊协议一律答「成功、`AIsHttp = False`」（`mailto:`、`ssh:` 在 WHATWG 里能解析；`OscLinkProvider` 只关心协议）。
  3. 特殊协议：跳过 `:` 后所有的 `/` 和 `\`；权威部分到第一个 `/ \ ? #` 为止。
  4. 最后一个 `@` 之前是用户信息：第一个 `:` 分用户名 / 密码；每个码位按「用户信息百分号编码集」编码（C0、空格、`" # < > ? ` { } / : ; = @ [ \ ] ^ |`、> U+007E）。
  5. 主机：空 → 失败。`[` 开头：到 `]` 为 IPv6，按 WHATWG IPv6 解析（压缩 `::`、嵌入 IPv4、各段 ≤ 4 位十六进制），失败 → 失败；成功 → 规范化（最长 ≥ 2 段的零压缩、小写、去前导零）。否则：百分号解码；含非 ASCII → **本函数答失败给 `isUrl`、答成功给 OSC 8**（用一个输出标志 `ANonAscii` 区分，两处调用各自判）；含禁止域名字符（C0、空格、`# % / : < > ? @ [ \ ] ^ |`、DEL）→ 失败；小写；最后一个标签（忽略一个末尾空标签）全是数字、或 `0x` / `0X` 加十六进制 → 按 WHATWG IPv4 解析（最多 4 段，十进制 / `0` 前缀八进制 / `0x` 十六进制，末段可占剩余字节，越界失败）并序列化成点分十进制。
  6. 端口：`:` 后到权威部分结束全是 ASCII 数字才行（否则失败）；空 = 没有端口；> 65535 失败；等于默认端口（http 80、https 443）去掉；否则用十进制（无前导零）。
  7. `ABase` = 协议 + `://` + [用户名 [`:` 密码] `@`（只在用户名非空时，密码非空才带；上游：密码与用户名都非空 → `u:p@`；只有用户名 → `u@`；否则不带）] + 主机 + [`:` 端口]。
  - `TyTermIsUrl(S)` = 解析成功、主机没有非 ASCII、`UnicodeLowerCase(S)` 以 `UnicodeLowerCase(ABase)` 开头（上游 `toLocaleLowerCase`；主机与用户信息里的非 ASCII 早已判否，剩下的前缀是 ASCII，小写规则无歧义）。

- [ ] **Step 2: 扫描器 `TyTermNextUrlMatch`**（开工前问题二第 4 条）：集合写成两个 `UnicodeString` 常量 + `TyTermIsJsWhitespace`：`X` = `"'!*(){}|\^<>` 与反引号，`Y` = `"':,.!?{}|\^~[]` 与反引号、`()<>`（逐字对 `WebLinksAddon.ts:21`，常量上方 `//` 注释抄正则原文，地雷 3）。从 `AFrom` 起对每个下标 `i`：`S[i..]` 以 `http://`、`https://`、`HTTP://`、`HTTPS://` 之一开头（区分大小写，`Http` 不行）→ 设 `p` 为 `//` 之后；`e` = 从 `p` 起连续不在 `X` 且非空白的最远处；结尾候选从 `e` 往回：`e < 长度` 且 `S[e]` 不在 `Y` 且非空白（紧跟的那个字符，`X` 里只有 `*` 能满足）则结尾在 `e`；否则在 `[p, e)` 里找最后一个不在 `Y` 且非空白的下标。有结尾 → 匹配 `[i, 结尾 + 1)`；没有 → 下一个 `i`。注意 `https` 先试 `https://`，不行再试 `http`（`https:/x` 不匹配，JS 回溯到 `http` 后面跟 `s` 也不是 `:`，同样不匹配）。
- [ ] **Step 3: `TyTermComputeUrlLinks`**：照 `WebLinkProvider.ts:59-199` 逐行：`_getWindowedLineStrings`（`translateToString(true)` 转 UTF-16、2048 按 UTF-16 长度、`indexOf(' ')`、首字符 `[0] !== ' '`——空串的 `[0]` 是 `undefined`、不等于 `' '`）、循环 exec（下一次从匹配末尾开始）、`isUrl`、`_mapStrIdx`（`chars.length || 1`，行尾补正）、范围 1 起。
- [ ] **Step 4: `TyTermComputeOsc8Links`**（`OscLinkProvider.ts:22-104`、`:108-196`）：逐格读扩展属性的 `UrlId`（`ExtendedEntry`）；段的结束条件与行尾那一格的 `endX` 补正照抄；URI 取 `ALinks.GetLinkData`；`AAllowNonHttp = False` 时 `TyTermParseUrlPrefix` 失败或非 http(s) 就丢（非 ASCII 主机按成功）。
- [ ] **Step 5: 去重叠、命中、查找**：`TyTermRemoveIntersectingLinks`（逐列占位，注意上游在内层循环里 `splice(i--, 1)` 后 `break`，外层 `i` 继续——照写）、`TyTermLinkAtPosition`、`TyTermFindLinkAt`（`AAbsRow` / `ACol` 0 起转成 1 起；OSC 8 在前、`ADetectUrls` 才算网址；去重叠后按提供者顺序第一个命中的）。
- [ ] **Step 6: 进包、提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Links.pas tycontrols.lpk && git commit -m "feat(terminal): links -- OSC 8 runs and recognised web addresses

Web addresses are found the way xterm.js's web-links addon finds them:
its regular expression, re-created as a scanner over UTF-16 so that
JavaScript's Unicode whitespace ends an address, wrapped lines joined
and mapped back to cells, and only matches that parse as a URL whose
text starts with its own scheme, user and host. OSC 8 runs follow
OscLinkProvider, non-http(s) ones dropped unless allowed; a web address
overlapping an OSC 8 link gives way, as in the Linkifier.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Core / Buffer 的两处补充与 4a 的测试

**Files:**
- Modify: `source/tyControls.Terminal.Buffer.pas`（`TrimmedLines`）、`source/tyControls.Terminal.Core.pas`、`source/tyControls.Terminal.Core.Services.inc`（`OnUserInput`）
- Create: `tests/test.terminal.selection.pas`（suite `TTyTerminalSelectionOracleTests`、`TTyTerminalSelectionTests`）、`tests/test.terminal.links.pas`（suite `TTyTerminalLinksOracleTests`、`TTyTerminalLinksTests`）
- Modify: `tests/test.terminal.core.pas`、`tests/test.terminal.buffer.pas`（各加一两条）、`tests/tytests.lpr`

- [ ] **Step 1: `TrimmedLines`**：`TTyTerminalBuffer` 加 `FTrimmedLines: Int64`，`LinesTrim` 开头（在 `FMarkers.Count = 0` 早退**之前**）`Inc(FTrimmedLines, AAmount)`；公开只读属性，注释「纯查询；选区按差值调整（4 期）」。
- [ ] **Step 2: `OnUserInput`**：`TTyTerminalCore` 加 `FOnUserInput` 与属性；`TriggerDataEvent` 在滚到底那段之后、`FDidUserInput := True` 之前发（上游 `CoreService.ts:86-89` 在 `onData` 之前；`DisableStdin` 早退不变）。接口注释写「控件接管」。
- [ ] **Step 3: 测试单元**（判据如下；夹具读法照 3 期 `test.terminal.keyboard.pas`）

**`TTyTerminalSelectionOracleTests`**（夹具 `terminal-selection.json`）：每个用例新建 Core（尺寸、滚回），`TTyTermSelection.Create(Core.BufferService)`，`WordSeparators` 取用例的或默认；步骤照表执行——`write` 用 `WriteSync`；每步之后先按 `Buffer.TrimmedLines` 的差值调 `HandleTrim`（并断言差值 = 夹具的 `trimmed`），换缓冲（`Core.OnBufferActivate`）时 `Clear`；`press` 的路由照上游非 macOS 规则在测试里写死：右键且 `HasSelection` → 什么都不做；非左键 → 什么都不做；`enabled` 变了且变成 False → `Clear`；`enabled = False` 且没 Shift → 什么都不做；否则 `Press(点, detail, enabled and shift, alt, 当前链接)`；`move` = `DragTo(点, TyTermDragScrollAmount(py, rows × 10, 50))`（夹具的画布高是 `rows × CELL_H`，`CELL_H = 10`；函数内部加 0.5 取像素中心）；`dragScroll` = `n := DragScrollAmount; if n <> 0 then Core.ScrollLines(n); AfterDragScroll`；`userInput` = `Core.Input('x', True)`，测试把 `Core.OnUserInput` 接到 `Clear`（只在 `HasSelection` 时，上游 `:139-143`）。每步比夹具的全部字段（`text` 用分隔符 `#10`）。

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestEveryStepMatches` | 全部用例、全部步骤、全部字段逐一相等；失败打印用例 id、步骤号、字段、两边的值；比较次数 = 夹具步骤数 × 字段数 | S1：`FinalEnd` 反向时不按列数折行；S2：`IsCharWordSeparator` 对空串答 False；S3：取词用 UTF-8 字节下标；S4：`HandleTrim` 起点小于 0 时清空而不是 `[0, 0]`；S5：`Text` 不接折行；S6：`DragTo` 不做宽字符 `x++`；S7：`Clear` 在没选区时不发 `OnChange`；S8：`RowSpan` 列模式不按起终 x 大小分两种 |
| `TestAfterResetToo` | 每个用例跑完后 `Core.Reset` 再跑一遍前三步，结果与夹具前三步相同（复用路径，spec §13.5 第 5 条的精神：选区对象不重建） | S9：`Clear` 不清 `IsSelectAllActive` |

**`TTyTerminalSelectionTests`**（夹具 `terminal-mouse-events.json` 的 `coords` / `dragAmount` 两部分 + 手写表）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestSelectionPointsMatchGetCoords` | `coords` 里 `isSel = true` 的每一行：`TyTermSelectionPointAt(px, py, cw, ch, cols, rows)` = `(x − 1, y − 1)` | S10：列用 `⌊px / cw⌋`（不加半格） |
| `TestReportCellsMatchGetCoords` | `isSel = false` 的每一行：3 期的格子规则（`⌊px / cw⌋`、`⌊py / ch⌋`，钳在网格）= `(x − 1, y − 1)`——守住 3 期 `CellAt` 与上游一致（测试里按同一公式算，不调控件） | — |
| `TestDragAmountMatchesUpstream` | `dragAmount` 每一行：`TyTermDragScrollAmount(py, H, 50) = amount` | S11：`Round` 代替 `Floor(x + 0.5)`（`-0.5` 处不同）；S12：阈值写死不看参数（另一条手写：阈值 75 时 `py = H + 75` 答 15） |
| `TestPixelTables` | 手写（与夹具互证，失败时一眼看得懂）：`TyTermSelectionPointAt(px, 0, 7, 14, 10, 5).X`：`px` = −4 / −1 / 0 / 3 / 4 / 10 / 11 / 69 / 100 → 0 / 0 / 0 / 0 / 1 / 1 / 2 / 10 / 10；`.Y`（`px = 0`，`py` = −1 / 0 / 13 / 14 / 69 / 70）→ 0 / 0 / 0 / 1 / 4 / 4。`TyTermDragScrollAmount(py, 140, 50)`：`py` = −100 / −26 / −1 / 0 / 70 / 139 / 140 / 141 / 165 / 300 → −15 / −8 / −1 / 0 / 0 / 0 / 1 / 1 / 8 / 15（这一列由 Task 1 探针对上游实跑得到） | S13：公式写成 `⌊(2·px + 1 + w) / (2w)⌋`（像素中心算两次，`px = 3` 得 1）。（`div` 代替 `Floor` 在钳制后结果相同，等价，不做） |
| `TestOsc52Oracle` | `terminal-osc52.json`：`TyTermOsc52Split` 不足两段时没有写入也没有应答；`Pd = '?'` 时应答 = `TyTermOsc52Reply(Pc, '读到的 text'#10)`；否则写入的文本 = `TyTermOsc52Decode(Pd)`（逐字节比 base64 解出的 UTF-8） | O1：不去 BOM；O2：模 4 余 1 时照样解；O3：坏序列按字节换而不是按最大子串 |
| `TestOsc52Table` | 手写：`TyTermOsc52Reply('c', '')` = `ESC ]52;c; BEL`；`'c', 'hi'` → `aGk=`；`'p', '中'` → `5Lit` | — |

**`TTyTerminalLinksOracleTests`**（`terminal-links.json`）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestUrlPrefixes` | `prefix` 每一条：成功与否、`ABase`、`AIsHttp`（`protocol` 是 `http:` / `https:`）、`TyTermIsUrl` 与夹具 `isUrl` 相同 | L1：默认端口不去掉；L2：IPv4 不规范化（`127.1` 成功且前缀相等）；L3：用户信息不编码 `;`；L4：只有密码时也带用户信息 |
| `TestUrlsInALine` | `urls` 每一条：写进 300 列 Core 的第一行，`TyTermComputeUrlLinks(Buffer, 1)` 的 `text` 与 `range` 逐条相同、条数相同 | L5：`\s` 只认 ASCII 空白（U+3000 用例红）；L6：结尾不回退（`http://a.com.` 带点）；L7：`X` 里漏掉 `*` 以外的某个（逐字符对表时红）；L8：大小写不敏感地认协议（`Http://` 被认出） |
| `TestLinesAndProviders` | `lines` 每个查询：`web`、`osc`（`AAllowNonHttp = False`）、`oscAll`（True）、`kept`（`TyTermRemoveIntersectingLinks` 之后）、`hits`（每一列 `TyTermFindLinkAt` 的结果对应的下标）全部相同 | L9：`_mapStrIdx` 不做行尾宽字符补正；L10：OSC 8 不按行尾补 `endX`；L11：去重叠按半开区间；L12：`TyTermFindLinkAt` 网址优先于 OSC 8 |

**`TTyTerminalLinksTests`**（手写，钉住偏离）：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestNonAsciiHostIsNotAWebLink` | `TyTermIsUrl('http://例子.测试/')` = False；`TyTermParseUrlPrefix` 同一串成功且 `AIsHttp`（OSC 8 会认它，§15） | L13：非 ASCII 主机在 OSC 8 路径上也判失败 |
| `TestXnLabelsAreNotChecked` | `TyTermIsUrl('http://xn--zz.com')` = True（上游因 punycode 无效判否，我们不校验，§15） | — |

- [ ] **Step 4: Core / Buffer 各加的测试**

| 测试（所在 suite） | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestTrimmedLinesCountsEveryTrim`（`TTyTerminalBufferTests`） | 5 行、滚回 3：写 20 行后 `Normal.TrimmedLines = 12`；没有标记时也计（先确认缓冲里 0 个标记）；`CSI 3 J` 清滚回后再加 3 | C1：计数放在「没有标记就早退」之后 |
| `TestUserInputIsAnnouncedBeforeData`（`TTyTerminalCoreTests`） | 挂 `OnUserInput` 与 `OnData` 记顺序：`Input('a', True)` → `[user, data]`；`Input('a', False)` → `[data]`；`ReadOnly := True` 后 `Input('a', True)` → 什么都没有；SGR 鼠标上报（`TriggerMouseEvent`，1006 开着）→ `[user, data]`；默认编码鼠标上报 → `[data]` | C2：`OnUserInput` 在 `ReadOnly` 时也发；C3：`TriggerMouseEvent` 的 SGR 路径不算用户输入 |

- [ ] **Step 5: `tytests.lpr` 的 uses 加两个测试单元；提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Buffer.pas source/tyControls.Terminal.Core.pas source/tyControls.Terminal.Core.Services.inc tests/test.terminal.selection.pas tests/test.terminal.links.pas tests/test.terminal.core.pas tests/test.terminal.buffer.pas tests/tytests.lpr && git commit -m "feat(terminal): user input is announced, trimmed lines are counted

The core raises OnUserInput where xterm.js's core service fires
onUserInput -- before the data, never when read-only -- and each buffer
counts the lines ever trimmed off its top, so a selection kept in
buffer rows can catch up with output. Tests hold the selection and link
ports to the fixtures step by step.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: 段 4a 编译并跑本段 suite**（主文件「跑测试的固定套路」4a 行）。只修本段的红：夹具和移植对不上时**以上游为准**，先查 UTF-16 下标（地雷 4）、空串分隔符（地雷 5）、`Math.round`（地雷 6）。
