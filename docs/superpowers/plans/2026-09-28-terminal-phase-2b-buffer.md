# 终端控件 2 期 · 2b 缓冲（Task 6–9）

> 本文件是 [`2026-09-28-terminal-phase-2.md`](2026-09-28-terminal-phase-2.md) 的附录，执行方式、核实记录、开工前问题、接口清单、夹具格式、地雷都在主文件。先读主文件。

**这一批做完能看到什么**：不经解析器，直接对缓冲层下操作——行的插删替换（宽字符两半、受保护格）、组合码位、改宽、整行复制与克隆、转文本；环形行表的推入 / 回收 / 拼接 / 裁头 / 平移与三种事件；缓冲的滚动（三条路径）、改行数、主备切换、制表位（含越界旧键）、标记跟随与作废、折行区间；OSC 8 链接表——每一步的返回值和之后的完整状态都和上游逐步相同。比较器（`tests/test.terminal.oracle.pas`）就位，2c 直接复用。

---

### Task 6: `buffer-cases.js` → `terminal-buffer-ops.json`

**Files:**
- Create: `tools/terminal-oracle/cases/buffer.js`（只有输入）
- Create: `tools/terminal-oracle/buffer-cases.js`
- Create (generated): `tests/fixtures/terminal-buffer-ops.json`（可能分片）

- [ ] **Step 1: 操作词表**（写进 `buffer-cases.js` 头部注释，两侧照它实现）

每个用例 `{ id, target, init, ops }`；生成器逐个执行 `ops`，每步之后记快照 `after[k] = { ret, state }`。`attr` 写成 `{ fg, bg, ext?: [rawExt, urlId] }`，`cell` 写成 `{ content, fg, bg, ext?: [rawExt, urlId], comb?: [cp...] }`（`comb` 存在时 `content` 必须带组合位）。

**`target: "line"`**——`init: { lines: { <name>: { cols, fill?: cell } } }`，节点侧 `new BufferLine(cols, fill ? CellData : undefined)`。

| 操作 | 上游调用 | `ret` |
|---|---|---|
| `["setCellFromCodepoint", n, col, cp, width, attr]` | `setCellFromCodepoint` | — |
| `["addCodepointToCell", n, col, cp, width]` | `addCodepointToCell` | — |
| `["setCell", n, col, cell]` | `setCell` | — |
| `["insertCells", n, pos, count, cell]` / `["deleteCells", …]` | 同名 | — |
| `["replaceCells", n, start, end, cell, respectProtect]` | 同名 | — |
| `["resize", n, cols, cell]` | 同名 | 返回的布尔 |
| `["fill", n, cell, respectProtect]` | 同名 | — |
| `["copyFrom", dst, src, blank]` / `["clone", dst, src, blank]`（`clone` 把新行放进名字 `dst`） | 同名 | — |
| `["copyCellsFrom", dst, src, srcCol, destCol, len, reverse]` | 同名 | — |
| `["setWrapped", n, bool]` | `isWrapped =` | — |
| `["translate", n, trimRight, start|null, end|null]` | `translateToString` | 字符串（`digestable`） |
| `["trimmed", n]` / `["noBgTrimmed", n]` | `getTrimmedLength` / `getNoBgTrimmedLength` | 数 |
| `["probe", n, col]` | `getWidth` / `hasWidth` / `hasContent` / `getCodePoint` / `isCombined` / `getString` / `isProtected` | `[w, hasW, hasC, cp, comb, str, prot]`（布尔化） |
| `["load", n, col]` | `loadCell` | `cell`（含 `ext`、`comb`） |

`state` = 每条命名行导出成主文件 `<buf>.lines` 的行格式（不省略默认行），外加 `name`。

**`target: "list"`**——`init: { max }`，节点侧 `new CircularList(max)`，元素是整数标签。Pascal 侧用 `TTyTerminalLineList`，元素是「第 0 格码位 = 标签」的行，比较时读回标签；空槽（`length` 变长时的 `undefined`）在两侧都记 `null`。

| 操作 | `ret` |
|---|---|
| `["push", tag]`、`["set", i, tag]`、`["splice", start, del, [tags]]`、`["trimStart", n]`、`["setMax", n]`、`["setLength", n]` | — |
| `["recycle"]`、`["pop"]`、`["get", i]` | 标签或 `"throws"`（`recycle` 在不满时抛） |
| `["shift", start, count, offset]` | `"throws"` 或 — |

`state` = `{ length, maxLength, isFull, items: [标签...] (0..length-1), events: [["insert", i, n] | ["delete", i, n] | ["trim", n] ...] }`，`events` 是这一步发出的事件、按顺序。

**`target: "buffers"`**——`init: { cols, rows, options }`（`options` 只用 `scrollback`、`tabStopWidth`、`windowsPty`），节点侧建一个 headless 终端，只动 `term._core._bufferService`（**不经解析器**）。

| 操作 | 上游调用 | `ret` |
|---|---|---|
| `["scroll", attr, isWrapped]` | `bufferService.scroll` | — |
| `["scrollLines", disp]` | `bufferService.scrollLines` | — |
| `["resize", cols, rows]` | `bufferService.resize`（**不是** `term.resize`：不 flush、不钳最小值） | — |
| `["reset"]` | `bufferService.reset` | — |
| `["activateAlt", attr|null]` / `["activateNormal"]` | `buffers.activateAltBuffer` / `activateNormalBuffer` | — |
| `["setXY", x, y]`、`["setMargins", top, bottom]`、`["setYdisp", n]` | 直接写活动缓冲字段（准备状态用） | — |
| `["text", absRow, col, "ascii"]` | 逐字符 `setCellFromCodepoint(col+i, cp, 1, DEFAULT_ATTR_DATA)` | — |
| `["setWrapped", absRow, bool]` | `lines.get(absRow).isWrapped =` | — |
| `["setupTabStops", i|null]`、`["tabSet", col]`、`["tabClear", col]`、`["tabClearAll"]` | 同名 / `tabs[col] = true` / `delete` / `tabs = {}` | — |
| `["nextStop", x|null]` / `["prevStop", x|null]` | 同名 | 数 |
| `["addMarker", absRow]` | `buffer.addMarker` | 标记序号（本用例内从 0 数） |
| `["disposeMarker", k]`、`["clearMarkers", absRow]`、`["clearAllMarkers"]` | 同名 | — |
| `["wrappedRange", absRow]` | `getWrappedRangeForLine` | `[first, last]` |
| `["setOption", name, value]` | `term.options[name] = value`（`scrollback` 触发 `BufferSet.resize`，`tabStopWidth` 触发 `setupTabStops()`） | — |
| `["fillViewport", attr|null]`、`["clear"]` | `fillViewportRows` / `buffer.clear` | — |
| `["registerLink", id|null, uri]` | `term._core._oscLinkService.registerLink` | 链接号 |
| `["addLineToLink", linkId, absRow]` | 同名 | — |
| `["getLinkData", linkId]` | 同名 | `[id|null, uri]` 或 `null` |

`state` = `{ active, isUserScrolling, buffers: { normal: <buf>, alt: <buf> }, markers: [[line, isDisposed] × 本用例建过的每个标记], links: [...] }`，`<buf>` / `links` 的格式同主文件（`lib-term.js` 的导出函数复用）。

- [ ] **Step 2: 写 `cases/buffer.js`**（Write 工具）

至少这些用例（`cols` 用 6–12、`rows` 用 3–6、`scrollback` 用 0–8，控制体积）：

| 组 | id 与要点 | 守的是（上游行号） |
|---|---|---|
| 行 | `line-insert-wide-left`（在宽字符第二半插入：左半被清）；`line-insert-wide-end`（插入把宽字符推到最后一格：被清）；`line-insert-big`（`count` = 2^31-1，走 `else` 分支）；`line-delete-wide`（删到宽字符中间：`pos-1` 与 `pos` 两处修补）；`line-delete-big`；`line-replace-wide-edges`（`start` 在第二半、`end` 在第一半）；`line-replace-protect`（受保护格不动、宽字符边界的两个受保护判断）；`line-replace-end-beyond`（`end` 远大于长度） | `BufferLine.ts:295-381` |
| 行 | `line-combine-empty`（空格上加码位：宽 1 路径）；`line-combine-twice`（已组合再加）；`line-combine-width`（带宽度参数改宽）；`line-resize-shrink-combined`（截掉的组合与扩展被删、再变宽不复活）；`line-resize-grow`；`line-resize-same`（返回值） | `:268-293`、`:390-431` |
| 行 | `line-fill-protect`；`line-copyfrom-lengths`（长度不同 / 相同两条路径）；`line-clone-blank`；`line-copycells-reverse`（重叠区间正反两种方向）；`line-translate`（宽字符、组合、空格与从没写过、`trimRight`、起止列、起止落在宽字符中间）；`line-trimmed`（末格是宽字符的第一半）；`line-nobg-trimmed`（只有背景色的格） | `:450-597` |
| 行 | `line-ext-urlid`（扩展属性带链接号：`ext` 取值强制 DASHED）；`line-ext-variant`（变体偏移 1–7，含负数路径）；`line-ext-sgr59`（下划线色写 `-1`：得 `0x3FFFFFF`，核实记录 7） | `AttributeData.ts:140-213` |
| 表 | `list-push-trim`（推满后再推：trim 事件、`startIndex` 前进）；`list-recycle`（不满时抛、满时回收的是最老那一项）；`list-pop`；`list-splice-delete`；`list-splice-insert-overflow`（插入超出上限：先 insert 事件再 trim 事件）；`list-splice-both`；`list-trimstart-over`（裁的比长度多）；`list-shift-up-expand`（正向平移超出长度、再超出上限：逐个 trim 事件）；`list-shift-down`；`list-shift-errors`（`start` 越界、`start + offset < 0` 两种抛）；`list-setmax-shrink` / `list-setmax-grow`（重排到 0 起）；`list-setlength-grow`（空槽） | `CircularList.ts:70-251` |
| 缓冲 | `scroll-push`（`scrollTop = 0`、底行是最后一行、不满：push、`ybase` / `ydisp` 前进）；`scroll-recycle`（满：recycle、`ybase` 不动）；`scroll-splice`（底边距不是最后一行：splice 路径）；`scroll-region-shift`（`scrollTop > 0`：平移、不进滚回）；`scroll-user-scrolling`（`scrollLines(-2)` 后滚动：`ydisp` 不跟；满时 `ydisp - 1`）；`scroll-cached-blank`（连续两次同属性滚动复用缓存行、属性变了重建；`isWrapped` 写在缓存行上） | `BufferService.ts:68-126` |
| 缓冲 | `lines-scroll`（`scrollLines` 正负、到顶、到底、`isUserScrolling` 的两个切换点）；`rows-grow-scrollup`（`ybase > 0`、光标在底：上移 `ybase`、`y` 加回）；`rows-grow-blank`（下面有空行：push 空行）；`rows-shrink-pop`（光标上方：pop 空行）；`rows-shrink-cursor`（光标在底：`ybase++`）；`rows-grow-windowspty`（`windowsPty` 有值：只 push）；`cols-change-windowspty`（`{conpty, 19044}`：变宽补格、变窄不截短，核实记录 13）；`maxlength-trim`（`setOption scrollback` 变小：裁头、`ybase` / `ydisp` / `savedY` 调整、标记跟着减）；`resize-cursor-clamp`（`x` / `y` / `savedX` 钳位、`scrollTop` 归零） | `Buffer.ts:160-286`、`BufferService.ts:49-56` |
| 缓冲 | `alt-activate`（带填充属性：备用屏按属性填满、光标拷过去）；`alt-activate-twice`（已是备用屏：空操作）；`alt-back`（切回：光标拷回、备用屏标记清掉、备用屏清空）；`alt-no-scrollback`（备用屏上滚动不进滚回；`hasScrollback` 两块各自的值）；`reset-buffers` | `BufferSet.ts:40-128` |
| 缓冲 | `tabs-default`（宽 8、12 列）；`tabs-width-option`（`tabStopWidth` 改 4：整表重建）；`tabs-after-resize`（`windowsPty` 下 12 → 7 → 20 列：`setupTabStops(i)` 从 `prevStop` 续、旧键留着）；`tabs-beyond-cols`（`tabSet` 在 `col = cols`）；`tabs-next-prev-edges`（`x` 为 -1、0、cols-1、cols、cols+3） | `Buffer.ts:575-608`、`BufferSet.ts:134-137` |
| 缓冲 | `markers-trim`（裁头时减行号、减到负数作废）；`markers-insert-delete`（`splice` 插入 / 删除事件的移动与作废）；`markers-clear-line`；`markers-clear-all`；`markers-dispose-twice`；`wrapped-range`（上下都有折行、顶行、末行） | `Buffer.ts:557-569`、`:614-671`、`Marker.ts` |
| 链接 | `link-no-id`（每次注册都是新号）；`link-with-id-reuse`（同 id + uri 复用、给当前行加标记）；`link-add-line-dup`（同一行不重复加）；`link-trimmed-out`（链接所在行被挤出滚回：标记作废、链接条目删掉、`getLinkData` 返回 `null`）；`link-alt-switch`（备用屏上注册、切回主屏：备用屏标记全作废） | `OscLinkService.ts:31-102` |

- [ ] **Step 3: 写 `buffer-cases.js`**（Write 工具）

要求：头部注释（生成什么、上游、怎么跑、Step 1 的词表全文）；经 `lib-term.js` 加载；`BufferLine` / `CellData` / `CircularList` / `AttributeData` 从 `out/common/...` 取；`CircularList` 的三个事件在每步之前清空记录；`buffers` 目标用 `lib-term.js` 的导出函数出 `<buf>`，**不省略默认行**的开关打开（缓冲层用例小，逐行比更容易定位）；遇到上游抛异常的操作记 `ret: "throws"` 并继续（`list-shift-errors`、`list-recycle`）；写 `terminal-buffer-ops.json`，打印用例数与字节数。

- [ ] **Step 4: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/buffer-cases.js && ls -l tests/fixtures/terminal-buffer-ops*.json && node tools/terminal-oracle/buffer-cases.js > /dev/null && git status --short
```

Expected：≤ 2MB；两次输出相同；`list-recycle` 第一步 `ret` 是 `"throws"`；`line-ext-sgr59` 的扩展字低 26 位是 `0x3FFFFFF`；`cols-change-windowspty` 变窄后行的 `len` 仍是旧列数。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/cases/buffer.js tools/terminal-oracle/buffer-cases.js tests/fixtures/terminal-buffer-ops*.json && git commit -m "test(terminal): buffer operations stepped against xterm.js directly

buffer-cases.js drives xterm.js's own BufferLine, CircularList and
BufferService without the parser and records every return value and the
full state after each step: wide-character edges, protected cells,
combining, resizing lines, list trims and shifts with their events, the
three scroll paths, row resizes, alternate screen, tab stops, markers and
OSC 8 links.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `tyControls.Terminal.Buffer`（一）——常量、属性、单元格、行

**Files:**
- Create: `source/tyControls.Terminal.Buffer.pas`
- Modify: `tycontrols.lpk`（`tyControls.Terminal.Parser.pas` 那一项之后，写法同 Task 3 Step 5）

- [ ] **Step 1: 单元头与 interface**

单元头：移植自 xterm.js 6.0.0；源文件 `src/common/buffer/{Constants,AttributeData,CellData,BufferLine,Buffer,BufferSet,Marker}.ts`、`src/common/CircularList.ts`、`src/common/services/{BufferService,OscLinkService}.ts`；版权行、MIT 同 Task 3。一段话写清：扩展属性按值存（地雷 6）、行的引用计数（开工前问题二第 5 条）、折行开关 2 期恒 false（开工前问题二第 24 条）、`BufferService` 为什么在这个单元（开工前问题二第 6 条）。interface 照主计划「接口清单」Buffer 部分。

- [ ] **Step 2: 常量与两个记录**（逐行对 `Constants.ts`、`AttributeData.ts`）

- `TTyTerminalExtAttrs`：`RawExt`（上游 `_ext`）、`UrlId`；`Ext`（getter：`UrlId <> 0` 时把第 26–28 位换成 `UnderlineStyle shl 26`）、`UnderlineStyle`（`UrlId <> 0` 时恒 DASHED = 5）、`SetUnderlineStyle`、`UnderlineColor`（`RawExt and $3FFFFFF`）、`SetUnderlineColor(AValue: Integer)`（`Cardinal(AValue) and $3FFFFFF`，所以 `-1` 得 `$3FFFFFF`）、`UnderlineVariantOffset`（`SarLongint(Integer(RawExt and $E0000000), 29)`，负数时 `xor $FFFFFFF8`，地雷 3）、`SetUnderlineVariantOffset`、`IsEmpty`（`UnderlineStyle = 0` 且 `UrlId = 0`；上游的 `payload` 不移植——只有图片 addon 用，写在注释里）。
- `TTyTerminalAttrData`：`Fg` / `Bg` / `Extended`；上游 `AttributeData` 的判定和取色函数照搬（`IsInverse` … `GetUnderlineVariantOffset`，名字去掉上游的 `is` / `get` 前缀规则在注释里写一次），`UpdateExtended`；单元级常量 `TyTermDefaultAttr`（全 0，`DEFAULT_ATTR_DATA`）。
- `TTyTerminalCellData`：`Content` / `Fg` / `Bg` / `Ext` / `Combined`（UTF-8）；`Width`（`Content shr 22`）、`IsCombined`、`Chars`；构造函数式的 `TyTermCellFromCodepoint(ACode, AWidth, const AAttr)`、`TyTermNullCell(const AAttr)`、`TyTermWhitespaceCell(const AAttr)`。

- [ ] **Step 3: `TTyTerminalLine`**（逐行对 `BufferLine.ts:69-618`）

- 数据：`FData: array of Cardinal`（`cols * 3`）、`FLength`、`FCombined` / `FExtended`：各是按列号升序的小数组（spec §17.2 第 7 条），元素 `(Col, Value)`；查找二分，插入保持有序。**只在格子带对应标志时读**，和上游一样允许留陈旧项（`setCell` 只写不删，`fill` / `copyFrom(blank)` / `_copySparseMapsFrom` 清空）。
- 引用计数：`FRefCount`（新建为 1）；`AddRef`、`Release`（到 0 时 `Free`）；类变量 `GLiveCount` 在构造 / 析构加减，`LiveCount` 读它。非原子（Core 只在主线程用，spec §3.5）。
- 方法照接口清单，每个都在注释里写上游行号。要逐字照抄的细节：`InsertCells` / `DeleteCells` 开头 `APos := APos mod FLength`；`n < length - pos` 在 `Int64` 里比较（地雷 3）；宽字符的四处修补条件；`ReplaceCells` 的两套分支（`respectProtect`）；`Resize` 的返回值（上游按字节算的「是否值得回收内存」——Pascal 没有共享 `ArrayBuffer`，返回值按「新长度 × 3 × 4 × 2 < 当前容量字节」同一公式算，容量用 `System.Length(FData)`；注释写明这只影响 `CleanupMemory` 的调度，而 `CleanupMemory` / `_batchedMemoryCleanup` 不移植——纯内存优化，没有可观察行为）；`TranslateToString` 的「空格格补一个空格、宽字符不补」「至少前进 1」「`trimRight` 先截到 `GetTrimmedLength`」。
- `TranslateToString` 的缓存（`_cache` / `_cacheValid`）不移植，注释写明「只是性能」；`outColumns` 参数 4 期选区再加。
- `Clone` 返回的新行引用计数 1、归调用者。

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Buffer.pas tycontrols.lpk && git commit -m "feat(terminal): cells and lines, ported from xterm.js

Three 32-bit words per cell in xterm.js's bit layout, combined text and
extended attributes in small column-sorted side tables read only when the
cell's flag says so, and every line operation with its wide-character
repairs. Lines are reference counted, so a line xterm.js keeps holding
across a list change stays alive here too.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `tyControls.Terminal.Buffer`（二）——环形行表、标记、缓冲、主备缓冲、`BufferService`、链接表

**Files:**
- Modify: `source/tyControls.Terminal.Buffer.pas`

- [ ] **Step 1: `TTyTerminalLineList`**（逐行对 `CircularList.ts:45-262`）

- `FArray: array of TTyTerminalLine`（长度 `MaxLength`）、`FStartIndex`、`FLength`；`CyclicIndex(i) = (FStartIndex + i) mod FMaxLength`。
- **槽位持有引用**：写槽位的唯一入口是私有 `Store(ASlot, ALine)`——`ALine.AddRef`（非 nil）、旧值 `Release`（非 nil）、再赋值。`Push` / `SetItem` / `Splice` 的插入都经它；`Splice` 的删除与平移、`ShiftElements` 的复制也经它（复制 = 同一行两个槽位各持一份，和上游的别名一致）；`Pop` 返回被弹出的行但**不** `Release`——槽位里的引用保留到被覆盖为止（上游 `pop` 同样只改长度、不清槽）；`Length` 变长时新槽写 nil（经 `Store`）。
- `MaxLength` setter 重建数组：落在新长度以外的槽位 `Release`。`Recycle` 不改引用计数（同一个槽位换了意义）。
- `FStartIndex` 每次加完取模（地雷 3）。
- 事件 `OnInsert` / `OnDelete` / `OnTrim` 单播（订阅者只有 `TTyTerminalBuffer`，它再分发给标记）。顺序照上游：`Splice` 先 delete 事件、再 insert、再 trim。
- `ShiftElements` 的两个异常用 `EArgumentOutOfRangeException`，消息照上游英文原句。
- 析构：所有槽位 `Release`。

- [ ] **Step 2: `TTyTerminalMarker`**（`Marker.ts`）：类变量 `GNextId`（从 1）；`Dispose` 幂等、先置 `IsDisposed`、`Line := -1`、再按添加顺序调释放监听者、然后清空监听者；监听者列表是方法指针的动态数组。

- [ ] **Step 3: `TTyTerminalBuffer`**（逐行对 `Buffer.ts:29-672`，`_reflow*` 除外）

- 字段照上游；`Tabs`：`array of Boolean`，按需加长、从不缩短（越界旧键要留着，Task 6 `tabs-after-resize`），`TabStops` 导出所有为真的下标（升序）；`delete tabs[x]` = 置 False。
- `SavedCharset` / `SavedCharsets`：存 `TTyTermCharsetId`（Core 的表下标），`SavedCharsets` 照上游是「切片拷贝」——动态数组整体复制，`undefined` 空洞记 0。
- `GetNullCell` / `GetWhitespaceCell` 返回记录（值），`attr` 省略时用全 0 属性和空扩展。
- `HasScrollback`：`FHasScrollback and (Lines.MaxLength > FRows)`（spec §6.3）。
- `Resize`：照 `:160-286` 逐行；`_isReflowEnabled` 换成 `IsReflowEnabled`，2 期恒 `False`，函数体里写「5 期：`windowsPty.buildNumber` 有值时 `hasScrollback and conpty and >= 21376`，否则 `hasScrollback`（`Buffer.ts:310-316`）」的注释；于是 `:258-268` 整段不执行（与上游 `windowsPty = {conpty, <21376}` 的路径一致）。`windowsPty.backend !== undefined || buildNumber !== undefined` 映射成 `(WindowsPty.Backend <> twpNone) or (WindowsPty.BuildNumber <> 0)`（接口清单：`BuildNumber = 0` 表示没给）。`_memoryCleanupQueue` 不移植（Task 7 Step 3 同理）。
- 标记：`AddMarker` 建标记、加进 `FMarkers`、给它挂释放监听（从 `FMarkers` 删，`_isClearing` 时不删）；列表事件到来时 `TTyTerminalBuffer` 遍历 `FMarkers` 的**快照**逐个处理（上游每个标记各订阅三个事件、按订阅顺序执行，等价于按 `FMarkers` 顺序）：trim 减行号、减到负数作废；insert 行号 ≥ 位置就加；delete 在区间内作废、在位置之后减。
- `Clear`：照 `:144-153`，新建行表（旧表释放，其中的行 `Release`）。
- `GetBlankLine` 返回新行（引用计数 1，归调用者；调用者 `Push` / `Splice` 后要 `Release` 自己那一份——或者直接把「交出所有权」的变体写成私有 `PushOwned`，二选一，**全单元统一**，注释写明）。

- [ ] **Step 4: `TTyTerminalBufferSet`**（`BufferSet.ts`）：`Reset` 建两块新缓冲（旧的释放）、`FillViewportRows`、激活主屏、发 `OnBufferActivate`、`SetupTabStops`；两个 `Activate*` 照 `:82-117`；`Resize` 两块都改再 `SetupTabStops(newCols)`。

- [ ] **Step 5: `TTyTerminalBufferService`**（`BufferService.ts`）：构造钳 `2 × 1`（`:41-42`）；`Scroll` 照 `:68-126`，`_cachedBlankLine` 由服务持有一份引用（换缓存行时 `Release` 旧的）；`Push(newLine.clone(true))` / `Recycle().CopyFrom(newLine, True)` / `Splice(bottomRow + 1, 0, clone)` / `ShiftElements(topRow + 1, h - 1, -1)` + `SetItem(bottomRow, clone)` 四条路径照抄；`ScrollLines` 照 `:135-157`；`Resize` 发 `OnResize(cols, rows, colsChanged, rowsChanged)`；`OnScroll(ydisp)` 在 `Scroll`、`ScrollLines`（有变化且不压制时）、`OnBufferActivate` 时发（`:44-46`）。另加两个方法供 Core 在选项变化时调：`ScrollbackChanged`（= `buffers.resize(cols, rows)`，`BufferSet.ts:36`）、`TabStopWidthChanged`（= `buffers.setupTabStops()`，`:37`）。

- [ ] **Step 6: `TTyTerminalOscLinks`**（`OscLinkService.ts`）：条目 `(LinkId, HasId, Id, Uri, Key, Markers[])`；`_entriesWithId` 用键 `id + ';;' + uri` 的有序字符串表（`TStringList`，`Sorted`、`CaseSensitive`）；标记释放监听里做 `_removeMarkerFromLink`；`_nextId` 从 1 起、复位不清（核实记录 8）；`LinkIds` 升序、`LinkLines` 按条目里标记的顺序。

- [ ] **Step 7: 钉住清单写进单元注释**（地雷 7）：本单元内「跨一次列表修改还拿着行」的地方——`BufferService.Scroll` 的 `newLine`（缓存行，服务持有）；`Buffer.Resize` 里循环中的 `Lines.Get(i).Resize`（不跨修改，无需）；OscLinks 不持有行。Core 里的钉住点（`print` 的 `bufferRow` / `oldRow`、headless `clear()` 的光标行）在 Task 16 / 15 处理，这里列出来提醒。

- [ ] **Step 8: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Buffer.pas && git commit -m "feat(terminal): line ring, buffers, markers and OSC 8 links from xterm.js

The circular line list with its insert, delete and trim events, the
normal and alternate buffers with tab stops, saved cursor and markers
that follow their line, the buffer service's three scroll paths and row
resizing, and the OSC 8 link table. Reflow stays off until phase 5; the
buffer then behaves as xterm.js does for an old ConPTY.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 比较器与缓冲测试

**Files:**
- Modify: `tests/test.terminal.oracle.pas`（Task 5 建的，加行 / 缓冲比较）
- Create: `tests/test.terminal.buffer.pas`
- Modify: `tests/tytests.lpr`（uses 里 `test.terminal.parser,` 之后加 `test.terminal.buffer,`）

- [ ] **Step 1: 扩展 `tests/test.terminal.oracle.pas`**

照主计划「比较器判据」，在 Task 5 建的公共部分之上加不依赖 Core 的比较（Task 18 再加 `TTyTermHarness` 与 `TyTermCompareState`）：

- `TyTermCellFromJson`、`TyTermAttrFromJson`（Task 6 词表里的 `cell` / `attr`）。
- `TyTermCompareLine(ALine: TTyTerminalLine; AJson: TJSONObject; ACols: Integer; const APath: string; AMisses)`：展开游程、逐格比三字、组合码位、扩展四元组（`Ext`、`UrlId`、`UnderlineColor`、`UnderlineVariantOffset`）、`IsWrapped`、`Length`；失败路径格式照主计划。
- `TyTermCompareDefaultLine`（没导出的行必须是默认行）。
- `TyTermCompareBuffer(ABuf: TTyTerminalBuffer; AJson; ACols; const APath; AMisses)`：主计划 `<buf>` 的每个字段；`lines` 缺省行按默认行比。
- 数值比较一律在 `Int64` 里比（`fg` 带第 31 位，JSON 里是 > 2^31 的正数，`fpjson` 用 `AsInt64` 读）。

- [ ] **Step 2: `tests/test.terminal.buffer.pas`**

#### `TTyTerminalBufferOracleTests`

| 测试 | 比什么 | 计数 |
|---|---|---|
| `TestFixturesComeFromThePinnedUpstream` | 同 2a | — |
| `TestLineOps` | `target = "line"` 的用例：Pascal 侧建同名行，逐步执行、逐步比 `ret` 与所有命名行 | 每步 1（`ret`）+ 每步所有行的格数 |
| `TestListOps` | `target = "list"`：逐步比 `ret`、`length`、`maxLength`、`isFull`、`items`、`events` | 每步 4 + 项数 + 事件数 |
| `TestBufferOps` | `target = "buffers"`：一个 `TTyTerminalBufferService`（选项照 `init`）+ 一个 `TTyTerminalOscLinks`，逐步执行、逐步比 `ret`、`active`、`isUserScrolling`、两块 `<buf>`、标记表、链接表 | 每步两块缓冲的总格数 + 字段数 |

失败信息：`case <id> step #<k> <op 的 JSON>: <路径>: want … got …`。

#### `TTyTerminalBufferTests`（纯函数，照表）

**1. `TestExtAttrsAccessors`**

| 设置 | `Ext` | `UnderlineStyle` | `UnderlineColor` | `UnderlineVariantOffset` | `IsEmpty` |
|---|---|---|---|---|---|
| 全 0 | `0` | 0 | `0` | 0 | True |
| `SetUnderlineStyle(3)` | `$0C000000` | 3 | `0` | 0 | False |
| `SetUnderlineStyle(3); UrlId := 5` | `$14000000` | 5 | `0` | 0 | False |
| `SetUnderlineColor(-1)` | `$03FFFFFF` | 0 | `$03FFFFFF` | 0 | True |
| `SetUnderlineVariantOffset(3)` | `$60000000` | 0 | `0` | 3 | True |
| `SetUnderlineVariantOffset(7)` | `$E0000000` | 0 | `0` | 7（负数路径：`-1 xor $FFFFFFF8`） | True |

**2. `TestLinesAreFreedWhenTheirOwnersGo`**（开工前问题二第 5 条的守卫）：
- 建 `TTyTerminalBufferService`（10 × 3、`scrollback = 5`），`LiveCount` = 主屏 3 行（备用屏还没填）；连续 `Scroll` 100 次后 `LiveCount` = `Normal.Lines.Length`（8）+ 缓存行 1；`ActivateAltBuffer` 后再加 3；`ActivateNormalBuffer` 后回到 9（备用屏 `Clear` 释放了行）；`Free` 服务后 `LiveCount` = 用例开始前的值。
- 行表：`Push` 同一行两次（经 `AddRef`）、`ShiftElements` 造成别名、`Splice` 删除、`MaxLength` 缩小：每一步后 `LiveCount` 等于「表里不同的行数 + 测试自己持有的数」。

**3. `TestTabStopsKeepStaleKeys`**：`windowsPty = {conpty, 19044}`、12 列，`Resize(7, 3)`、`Resize(20, 3)` 后 `TabStops` = `[0, 8, 16]`；`SetTab(12, True)`、`Resize(10, 3)` 后 `TabStops` 仍含 12 和 16（旧键不删）。（这一条上游行为已由 Task 6 `tabs-after-resize` 比过，这里是给 Pascal 数据结构的直接表。）

- [ ] **Step 3: 登记到 `tests/tytests.lpr`**（编辑工具）
- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.oracle.pas tests/test.terminal.buffer.pas tests/tytests.lpr && git commit -m "test(terminal): buffer operations held to xterm.js step by step

A shared comparator for terminal fixtures (run-length cells, combined
code points, extended attributes, default lines, split fixtures, failure
paths naming case, buffer, row, column and field) and the buffer suite:
every line, list and buffer operation compared after each step, extended
attribute accessors, and a live-line count proving lines are freed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异表（期末做；改 `source/tyControls.Terminal.Buffer.pas`）：**

| # | 变异 | 必须红 |
|---|---|---|
| B1 | `InsertCells`：删掉「`pos` 在宽字符第二半时清左半」 | `line-insert-wide-left` |
| B2 | `InsertCells`：删掉末格宽字符修补 | `line-insert-wide-end` |
| B3 | `DeleteCells`：删掉 `pos` 处 `width = 0` 且无内容的修补 | `line-delete-wide` |
| B4 | `ReplaceCells`（保护分支）：`not IsProtected(end)` → `not IsProtected(end - 1)` | `line-replace-protect` |
| B5 | `ReplaceCells`：`end` 用 `Integer` 截断（去掉 `Int64`） | `line-replace-end-beyond`（及 2c 的 ECH 大参数） |
| B6 | `AddCodepointToCell`：空格路径宽度写 2 | `line-combine-empty` |
| B7 | `Resize` 缩短：不删越界的组合项 | `line-resize-shrink-combined`（再变宽时组合复活） |
| B8 | `TranslateToString`：「至少前进 1」去掉 | `line-translate`（宽 0 格死循环——**不做**，改做下一条） |
| B8' | `TranslateToString`：空格格补的空格去掉 | `line-translate` |
| B9 | `GetTrimmedLength`：返回 `i + 1` 而不是 `i + width` | `line-trimmed` |
| B10 | `TTyTerminalExtAttrs.Ext`：`UrlId` 时不强制 DASHED | `line-ext-urlid`、`TestExtAttrsAccessors` |
| B11 | `UnderlineVariantOffset`：`SarLongint` 换成 `shr` | `line-ext-variant`、`TestExtAttrsAccessors` |
| B12 | 行表 `Push`：满时不发 trim 事件 | `list-push-trim`、`markers-trim` |
| B13 | 行表 `Splice`：insert 与 trim 事件顺序对调 | `list-splice-insert-overflow` |
| B14 | 行表 `ShiftElements`：扩展超上限时一次 trim n 而不是逐个 trim 1 | `list-shift-up-expand` |
| B15 | 行表 `MaxLength` setter：不把起点归 0 | `list-setmax-shrink` |
| B16 | `BufferService.Scroll`：满时仍 `ybase++` | `scroll-recycle` |
| B17 | `Scroll`：`isUserScrolling` 且满时不减 `ydisp` | `scroll-user-scrolling` |
| B18 | `Scroll`：缓存行比较漏掉 `bg` | `scroll-cached-blank` |
| B19 | `Buffer.Resize` 增行：`lines.length <= ybase + y + addToY + 1` → `<` | `rows-grow-scrollup` / `rows-grow-blank` |
| B20 | `Buffer.Resize`：`windowsPty` 判断取反 | `rows-grow-windowspty` |
| B21 | `Buffer.Resize`：不调 `savedY` | `maxlength-trim` |
| B22 | `ActivateNormalBuffer`：不 `ClearAllMarkers` | `link-alt-switch`、`alt-back` |
| B23 | `SetupTabStops(i)`：`not tabs[i]` 时不 `prevStop` | `tabs-after-resize` |
| B24 | `NextStop`：返回前不钳到 `cols - 1` | `tabs-next-prev-edges` |
| B25 | 标记 delete 事件：「在位置之后减」的 `>` 改 `>=` | `markers-insert-delete` |
| B26 | OscLinks：`AddLineToLink` 不查重 | `link-add-line-dup` |
| B27 | 行表槽位写入不经 `Store`（直接赋值） | `TestLinesAreFreedWhenTheirOwnersGo` |

**等价、不做的**：`TranslateToString` 去掉缓存（Task 7 Step 3 本来就没移植）；`Resize` 的返回值公式改动（只影响不移植的内存回收调度，没有可观察行为）。
