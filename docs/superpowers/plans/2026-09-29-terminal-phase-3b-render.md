# 终端控件 3 期 · 3b 渲染与控件骨架（Task 4–10）

> 本文件是 [`2026-09-29-terminal-phase-3.md`](2026-09-29-terminal-phase-3.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是 Task 0 的「实验记录」——本批的字形遮罩做法照那里的 E2 结论（下文按首选（c）写；选了（b）的话，Task 5 Step 5 和 Task 10 的 V43 反过来）。

**这一批做完能看到什么**：`TTyTerminalView` 能把 Core 画出来——16 / 256 / RGB 色、粗体亮色、暗淡、反显、隐藏、五种下划线与下划线色、删除线、上划线、宽字符两格、制表符与块元素连成线、光标三种形状与五种失焦样式、闪烁与 5 分钟停闪、同步输出攒行与 1 秒超时、DPI 与字号变化重建；只重画脏行、字形缓存命中；Core 的事件、调度、焦点、主题取色、窗口尺寸应答都接上。段末编译一次，只跑 3a + 3b 的 suite。

---

### Task 4: 自绘字形的数据与 256 色表的基准

**Files:**
- Modify: `tools/terminal-oracle/lib-dump.js`（`PORTED` 加 `addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts` → `addons/addon-webgl/${OUT_DIR}/customGlyphs/CustomGlyphDefinitions.js`；`GENERATED` 加下面两个生成物）
- Create: `tools/terminal-oracle/gen-terminal-glyphs.js`、`tools/terminal-oracle/view-cases.js`
- Modify: `tools/terminal-oracle/regen-all.js`（`SCRIPTS` 追加这两个）
- Generate: `source/tyControls.Terminal.CustomGlyphs.inc`、`tests/fixtures/terminal-view-palette.json`

- [ ] **Step 1: `gen-terminal-glyphs.js`**（Write 工具）

从上游 `customGlyphDefinitions`（**以字符为键**，核实记录 15）取 U+2500–259F 共 160 个码位，写 `source/tyControls.Terminal.CustomGlyphs.inc`：

- 头部（`//` 注释，**不用花括号**，脚本断言全文没有 `{` `}`）：出自 xterm.js 6.0.0 的 `addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts`、commit、上游提交日期（照 `Unicode.Width.Data.inc` 的写法，不写墙钟时间、不写本机路径）；版权「Copyright (c) 2021 The xterm.js authors」（该文件头）与 addon 的 `LICENSE:1`「Copyright (c) 2018, The xterm.js authors」；MIT，全文见 THIRD-PARTY-NOTICES.md；「由 gen-terminal-glyphs.js 生成，别手改」。
- 三种部件（实跑确认这一段只有这三种、属性只有 `type` / `data` / `strokeWidth`，脚本遇到别的类型或属性就报错退出）：
  - `SOLID_OCTANT_BLOCK_VECTOR`（0）：矩形列表，单位是 1/8 格（`x, y, w, h`）。
  - `BLOCK_PATTERN`（1）：0/1 矩阵（行 × 列）。
  - `PATH_FUNCTION`（2）：路径串按空格切成指令，每条 = 命令字母（只允许 `M` `L` `C`）+ 逗号分隔的数。`data` 是函数时，上游在光栅化时以 `xp = 0.15`、`yp = 0.15 / 格高 × 格宽` 调它（`CustomGlyphRasterizer.ts:548-554`，执行时核对行号）；脚本以 `yp = 0` 和 `yp = 1` 各调一次，每个数写成 `a + b·yp` 的两个系数，再以 `yp = 0.37` 验证线性与指令结构不变（不满足就报错退出）。串形的 `b = 0`。`strokeWidth`（1 或 3）照抄。
- 输出成 Pascal 常量数组（码位 → 部件区间 → 数据区间，布局由实现者定，注释写清），数用 JS `String(n)` 的最短往返写法。
- 脚本最后打印三类部件的个数（预期：块 29、图案 3、路径 178，其中带 `yp` 的 33 个码位）。

- [ ] **Step 2: `view-cases.js`**：加载 `out/browser/Types.js` 的 `DEFAULT_ANSI_COLORS`，写 `tests/fixtures/terminal-view-palette.json`：`{ ansi: [256 个 0xRRGGBB] }`（`rgba >>> 8`）。外壳照 2 期「夹具格式」。

- [ ] **Step 3: 跑两个脚本，确认可复现**（同 Task 1 Step 5 的做法：跑两遍、第二遍 `git diff --quiet`）

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/ source/tyControls.Terminal.CustomGlyphs.inc tests/fixtures/terminal-view-palette.json && git commit -m "feat(terminal): box-drawing and block glyph data dumped from xterm.js

The WebGL addon draws U+2500-259F itself so neighbouring cells join up;
its definitions are dumped into an include, the path functions (double
lines and arcs) written as a constant plus a multiple of the cell's
aspect term they are evaluated with. The 256-colour table is dumped as a
fixture for the renderer's formula.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异表（期末做，JS 侧）：**

| # | 变异 | 必须红 |
|---|---|---|
| R0 | 函数路径只在 `yp = 0` 求一次（`b` 恒 0） | 脚本自己的线性验证（`yp = 0.37` 对不上）；去掉验证后，Task 6 的 `TestDoubleLinesKeepTheirGap`（非方格下两条线的间距不随格子比例变） |

---

### Task 5: `tyControls.Terminal.Render`

**Files:**
- Create: `source/tyControls.Terminal.Render.pas`
- Modify: `tycontrols.lpk`（`tyControls.Terminal.Keyboard.pas` 之后）

依赖：`SysUtils`、`Classes`、`Math`、`Types`、`Graphics`（`TFontStyle`）、`BGRABitmap`、`BGRABitmapTypes`、`BGRAGrayscaleMask`、`BGRACanvas2D`、`tyControls.Painter`（`TyConfigureTextFont`、`TyFontHeightPx`）、`tyControls.Unicode.Width`、`tyControls.Terminal.Buffer`。**不引**控件单元、`Forms`、`Controls`。

- [ ] **Step 1: 单元头**：自己写的渲染部件；颜色解析照 `src/browser/renderer/dom/DomRendererRowFactory.ts:342-460`（「Copyright (c) 2018, 2023 The xterm.js authors」）、256 色表照 `src/browser/Types.ts:205-227`、自绘字形照 `addons/addon-webgl/src/customGlyphs/CustomGlyphRasterizer.ts`（「Copyright (c) 2021 The xterm.js authors」，数据在 `CustomGlyphs.inc`）；MIT，全文见 THIRD-PARTY-NOTICES.md。另写「和上游不同的形状」：字形是不带颜色的遮罩（E2）；装饰线按整段画、相位按绝对 x（上游的 `underlineVariantOffset` 是为了逐格图集拼接，我们不需要）。

- [ ] **Step 2: 度量 `TyTermMeasureCell`**（spec §10.2；`TTyTermFontSpec` 另加 `UnderlineWidthLogical`、`CursorWidthLogical` 两个字段，来自 token）

1. 一张 1×1 的 `TBGRABitmap`，`TyConfigureTextFont(bmp, MainName, SizeLogical, 400, PPI)`。
2. `CharW := Ceil(bmp.TextSize(32 个 'W').cx / 32)`；`CellW := Max(1, CharW + MulDiv(LetterSpacingLogical, PPI, 96))`。
3. `m := bmp.FontPixelMetric`；`CharH := m.Lineheight`（`m.Defined` 为假时退到 `TextSize('Ag').cy`，注释引用 Task 0 的 E1 数字）；`CellH := Max(CharH, Ceil(CharH * LineHeightPercent / 100))`。
4. `TextTop := (CellH - CharH) div 2`；`Baseline := TextTop + m.Baseline`。
5. `LineW := Max(1, MulDiv(UnderlineWidthLogical, PPI, 96))`；`UnderlineY := Min(CellH - LineW, Baseline + LineW)`；`StrikeY := TextTop + (m.xLine + m.Baseline) div 2 - LineW div 2`；`OverlineY := TextTop`。
6. 结果由调用者按「规格记录」缓存；本函数不缓存。

- [ ] **Step 3: 颜色**

- `TyTermDefaultPaletteColor`：0–15 Tango（`Types.ts:183-203`）；16–231 立方 `v = [$00,$5f,$87,$af,$d7,$ff]`，`r = v[(i-16) div 36 mod 6]`、`g = v[(i-16) div 6 mod 6]`、`b = v[(i-16) mod 6]`；232–255 灰 `8 + 10 × (i-232)`。
- `TyTermRgbToPixel`：`$RRGGBB` → `TBGRAPixel`（地雷 11：只此一处）。
- `TyTermResolveCellColors`（核实记录 13 逐条）：
  1. 取 `fg` / `bg` 的颜色模式与值；**反显**时连同模式一起互换。
  2. 底色：P16 / P256 → `AResolve(值)`；RGB → 值；默认 → 反显时 `AResolve(256)`（前景色），否则 `AResolve(257)`。
  3. 前景：P16 / P256 → 粗体且值 < 8 且 `ADrawBoldBright` 时值 + 8，再 `AResolve`；RGB → 值；默认 → 反显时 `AResolve(257)`，否则 `AResolve(256)`。
  4. 暗淡：`Fg := Mix(Fg, Bg)`，每通道 `(f + b + 1) div 2`；`Dim := True`。
  5. 隐藏：`Invisible := True`（字形不画，装饰线照画——上游把字换成空格，下划线仍在）。
  6'. 闪烁（SGR 5）不影响颜色，照常画（spec §10.6；上游默认 `blinkIntervalDuration: 0`）。
  6. 下划线色：`AExt` 的下划线色是默认 → 等于最终 `Fg`；调色板色 → 粗体且 < 8 且 `ADrawBoldBright` 时 + 8（`DomRendererRowFactory.ts:313-320`），`AResolve`；RGB → 值。

- [ ] **Step 4: 字形缓存 `TTyTermGlyphCache`**：键 = `Text` + `Bold` + `Italic` + `Cells` + `Font`（**没有颜色**）；哈希表 + 双向链表做 LRU（`contnrs` 的 `TFPHashObjectList` 或 `Generics.Collections`，看库里现有用法挑一个）；`Find` 命中移到表头、`Hits` 加一，没中 `Misses` 加一；`Add` 超容量淘汰表尾并释放；`Clear` 全释放。`TTyTermGlyph` 带类变量 `GLiveCount`（构造加、析构减，FOR THE TESTS）。

- [ ] **Step 5: 光栅器 `TTyTermGlyphRasterizer.Rasterize`**（按 E2 结论；下面是（c））

1. 临时位图宽 `Cells × CellW + 2·pad`、高 `CellH + 2·pad`，`pad = CellH`（给斜体、超宽字形留余量），填白。
2. 字体：`Cells = 2` 且 `Spec.WideName <> ''` 用宽字体，否则主字体；`TyConfigureTextFont(tmp, name, SizeLogical, IfThen(Bold, 700, 400), PPI)`；斜体再 `tmp.FontStyle := tmp.FontStyle + [fsItalic]`（不改 `Painter.pas`）。
3. 前进宽度 `adv := tmp.TextSize(Text).cx`；`adv > Cells × CellW + 1` 时横向压缩：先画在宽 `adv + 2·pad` 的临时图上，再把墨迹区 `Resample` 到 `Cells × CellW` 宽（上游 `rescaleOverlappingGlyphs` 的思路）。
4. 黑字画在 `(pad, pad + TextTop)`；覆盖率 = `255 − (R + G + B) div 3`。
5. 纵向裁到格子行内（`[pad, pad + CellH)`）——相邻行重画时会盖掉越界的墨，留着反而时有时无；横向按墨迹包围盒裁（可越过本格，画在同一行其他格的底色之上）。
6. 存成 `TGrayscaleMask` + `OffsetX := 包围盒左 − pad`、`OffsetY := 包围盒顶 − pad`。全无墨返回一个空遮罩的字形（缓存它，别每次重画）。
7. 调用者不对空格、空格子、隐藏的格子、自绘字形调光栅器。

- [ ] **Step 6: 自绘字形 `TyTermDrawCustomGlyph`**（照 `CustomGlyphRasterizer.ts`，执行时逐函数对行号）

- 块矩形（`drawBlockVectorChar` `:129-168`）：`fillRect(x + bx·W/8, y + by·H/8, bw·W/8, bh·H/8)`，W / H 是**格子**尺寸（含字间距与行高）；用 `ABmp.Canvas2D`（`TBGRACanvas2D`）的 `fillRect`，小数边照 Canvas 2D 抗锯齿。
- 图案（`drawPatternChar` `:462-530`）：照上游用图案平铺填满格子（上游建一张图案画布再 `createPattern`；Pascal 可以直接按像素 `(x mod 列数, y mod 行数)` 取 0/1，结果相同就行——判据见 Task 6）。
- 路径（`drawPathFunctionCharacter` `:531-589`、`translateArgs` `:734-768`）：先按 `yp = 0.15 / H × W` 把 `a + b·yp` 算成数；坐标 `×W` / `×H` 后「非 0 就 `Round(v + 0.5) − 0.5` 再钳到 `[0, W]`」（上游 `Math.round` 是 .5 向正无穷，用 `Floor(v + 0.5 + 0.5) − 0.5`，地雷 11），加格子偏移；裁剪到格子矩形；`M` / `L` / `C` 对应 `moveTo` / `lineTo` / `bezierCurveTo`；`strokeWidth` 有值时 `lineWidth = PPI / 96 × strokeWidth` 描边，否则填充。
- 颜色就是前景色；本期不缓存自绘字形（每次直接画，5 期性能再说）。

- [ ] **Step 7: 行绘制器 `TTyTermRowPainter.PaintRow`**（spec §10.1 的顺序）

1. **底色**：逐格 `TyTermResolveCellColors`，相邻同底色的格合成一段 `FillRect`；宽字符的第二格（宽度 0）跟前一格同色。
2. **字形**：逐格，有内容（`HasContent`）、宽度 > 0、不隐藏的：`TyTermIsCustomGlyph(码位)`（且不是组合格）→ 自绘；否则查缓存（键：`GetChars` 的 UTF-8、粗体、斜体、宽度、主 / 宽字体）→ 没中就光栅化并 `Add` → `ABmp.FillMask(x + OffsetX, y + OffsetY, Mask, 前景, dmDrawWithTransparency)`。
3. **装饰线**：按「同样式同颜色」合段，从左到右一段一段画：单线 = `LineW` 高的实条于 `UnderlineY`；双线 = 两条，间隔 `LineW`（第二条在 `UnderlineY − 2·LineW`，不出格子）；波浪 = 周期 `4·LineW`、振幅 `LineW` 的折线（相位按绝对 x，跨格连续）；点线 = `LineW` 方点、间隔 `LineW`；虚线 = `3·LineW` 实、`2·LineW` 空。删除线于 `StrikeY`、上划线于 `OverlineY`，都是单线。线宽都用 `LineW`（spec §10.6「按 DPI 缩放，至少 1 设备像素」）。
4. **光栅化出来的遮罩着色**用 `FillMask`；如果 Task 0 的 E2 热缓存超时，这里换成自己的逐行混合循环（E2 判据表第二行）。
5. **光标**（`ACursorCol >= 0`）：块实心 = 光标格（宽字符两格）填 `CursorColor`，再用 `CursorInk` 重画该格字形（自绘字形也用 `CursorInk`）；块轮廓 = `LineW` 宽的框；下划线 = 格子底部 `CursorWidthPx` 高的条；竖线 = 格子左侧 `CursorWidthPx` 宽的条；`tcpNone` 什么都不画（形状枚举用 `tcp*` 前缀，别和控件的 `TTyTerminalCursorStyle` 的 `tcs*` 撞名）。
6. 画完一行 `Inc(FRowsPainted)`（FOR THE TESTS）。

- [ ] **Step 8: 加进 `.lpk`，提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Render.pas tycontrols.lpk && git commit -m "feat(terminal): cell metrics, colours, glyph masks and the row painter

A glyph is rasterized once through the library's own text path into a
coverage mask with no colour in it, and tinted wherever it lands; the
cache is keyed by text, weight, slant, width and font, and drops the
least recently used past 4096. Colours follow xterm.js's DOM renderer:
inverse swaps modes as well as values, bold brightens palette colours
below 8, dim mixes halfway to the background. Box drawing and block
elements are drawn from xterm.js's definitions so they meet at cell
edges.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 渲染部件测试

**Files:**
- Create: `tests/test.terminal.render.pas`（suite `TTyTerminalRenderTests`）
- Modify: `tests/tytests.lpr`

像素测试用手造的度量记录（例如 `CellW = 9, CellH = 18`，另一组 `CellW = 10, CellH = 23` 非整比例），不经字体，结果不随本机字体变；位图预填哨兵品红，断言「是 / 不是某色」。

**纯函数表：**

`TyTermDefaultPaletteColor(i)` 对 `terminal-view-palette.json` 的 256 项逐项相等（比较次数 256）。

`TyTermResolveCellColors`：解析器答 `$100000 + 下标`（一眼看出取的是哪一号），下划线扩展属性默认。

| fg | bg | 属性 | 粗体亮色 | 期望 Fg | 期望 Bg | 其他 |
|---|---|---|---|---|---|---|
| 默认 | 默认 | — | 开 | 256 | 257 | |
| P16 1 | 默认 | — | 开 | 1 | 257 | |
| P16 1 | 默认 | 粗体 | 开 | 9 | 257 | |
| P16 1 | 默认 | 粗体 | 关 | 1 | 257 | |
| P256 5 | 默认 | 粗体 | 开 | 13 | 257 | P256 也加 8 |
| P256 9 | 默认 | 粗体 | 开 | 9 | 257 | ≥ 8 不变 |
| RGB `$123456` | RGB `$654321` | 粗体 | 开 | `$123456` | `$654321` | |
| 默认 | 默认 | 反显 | 开 | 257 | 256 | |
| P16 1 | P16 4 | 反显 | 开 | 4 | 1 | |
| P16 1 | P16 2 | 反显 + 粗体 | 开 | 10 | 1 | 反显后再加亮 |
| RGB `$FF0000` | RGB `$000000` | 暗淡 | 开 | `$800000` | `$000000` | `Dim` |
| P16 3 | 默认 | 隐藏 | 开 | 3 | 257 | `Invisible` |
| P16 3 | 默认 | 下划线，下划线色 P16 3，粗体 | 开 | 11 | 257 | 下划线色 11 |
| P16 3 | 默认 | 下划线，下划线色 RGB `$0000FF` | 开 | 3 | 257 | 下划线色 `$0000FF` |

**判据：**

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestPaletteMatchesUpstream` | 上面 256 项 | R1：立方的第二级 `$5f` 写成 `$60` |
| `TestCellColors` | 上表逐行 | R2：反显只换值不换模式（第 8 行）；R3：粗体亮色只对 P16（第 5 行）；R4：暗淡换成「底色 50%」 |
| `TestGlyphCacheEvictsTheLeastRecentlyUsed` | 容量 3：加 A、B、C，找 A，加 D → B 不在、A / C / D 在；`Count = 3`；`TTyTermGlyph.GLiveCount` 等于 3；`Clear` 后 0 | R5：淘汰表头；R6：`Find` 不移到表头 |
| `TestGlyphCacheCountsHitsAndMisses` | 找一次不在的、加上、再找两次 → `Misses = 1`、`Hits = 2` | — |
| `TestFullBlockFillsTheCell` | █ 画在格子 (1, 1)：该格每个像素都等于前景；格子外一个像素都没动（仍是哨兵） | R7：块矩形用 `CharW` 不用 `CellW`（造一组 `CharW < CellW` 的度量） |
| `TestHalfBlocks` | ▀：上半 `H/2` 行全是前景、下半全是哨兵（`H` 取偶数）；▌同理按列 | — |
| `TestShadesCoverTheirShare` | ░ / ▒ / ▓ 在 18 × 9 格里前景像素占比分别在 [20%, 30%]、[45%, 55%]、[70%, 80%]；另对 ░ 的左上 2 × 2 像素逐个比上游图案矩阵（`[[1,0],[0,0]]` 从格子左上角起铺，执行时对 `drawPatternChar` 核对起点） | R8：图案当整块填满；R8b：图案起点错一格（░ 左上像素变成底色）。行列对调是等价变异、不做：三个图案 `[[1,0],[0,0]]`、`[[1,0],[0,1]]`、`[[1,1],[1,0]]` 都对称 |
| `TestLinesJoinAcrossCells` | 4 个 ─ 横排：存在一行 y，使 `[0, 4W)` 每一列在该行都有墨；3 个 │ 竖排：存在一列 x，使 `[0, 3H)` 每一行都有墨；两组度量、96 与 144 PPI 各一遍 | R9：`translateArgs` 的钳制上界用 `W − 1`；R10：路径坐标没加格子偏移 |
| `TestHeavyLinesAreThicker` | ━ 的墨行数 ≥ ─ 的墨行数 × 2 | R11：`strokeWidth` 忽略 |
| `TestDoubleLinesKeepTheirGap` | ═ 在中间一列上恰好两段墨、段间有空；非方格度量下两段间距 = 由 `yp` 算出的值（±1 像素） | R0（Task 4） |
| `TestArcsReachTheirEdges` | ╭：右边中点、底边中点有墨，左上角 3×3 没墨 | — |
| `TestCellMetricsScaleWithThePPI` | `TyTermMeasureCell(Consolas, 9, 96)` 与 `(…, 144)`：`CellW` 比值在 [1.4, 1.6]；`LetterSpacingLogical = 2` 时 144 PPI 下 `CellW` 多 3；`LineHeightPercent = 150` 时 `CellH = Ceil(1.5 × CharH)`、`TextTop = (CellH − CharH) div 2`；`LineW` 在 96 / 192 PPI 下为 1 / 2 | R12：字间距没按 PPI 缩放；R13：行高倍数加在 `TextTop` 两次 |
| `TestRasterizedGlyphs` | `W` 的遮罩非空、墨迹在格内；`中`（宽 2）墨迹宽 > `CellW`；把 `W` 当宽 1、字间距 −3 光栅化 → 墨迹宽 ≤ `CellW`（被压缩）；空字形（`U+200B` 之类无墨的）返回空遮罩且被缓存（第二次 `Hits` 加一） | R14：不压缩 |

- [ ] **Step 1: 写测试单元、加进 `tytests.lpr`**
- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.render.pas tests/tytests.lpr && git commit -m "test(terminal): colours, the glyph cache and drawn box glyphs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 控件骨架——属性、Core 接线、调度、网格、字体、主题取色、设计期

**Files:**
- Create: `source/tyControls.Terminal.pas`
- Modify: `tycontrols.lpk`（`tyControls.Terminal.Render.pas` 之后）

- [ ] **Step 1: 单元头**：自己写的控件；同步输出照 `src/browser/services/RenderService.ts:155-200`、`:337-380`，焦点与键盘分流照 `src/browser/CoreBrowserTerminal.ts:860-1017`，滚轮照 `src/browser/services/MouseService.ts:250-292`（引用处标行号，逻辑参照，不是逐行移植）；列出 WHAT TO KNOW：接管了 Core 的哪些事件（主文件接口清单）、不在 `Paint` 里改网格、可出字符的键不清零、列数不随滚动条变。

- [ ] **Step 2: 类型与 published 属性**（主文件接口清单）

- 公开、published 接口里用到的 Core 类型（`TTyTerminalDataEvent`、`TTyTerminalTextEvent`、`TTyTerminalOscEvent`、`TTyTerminalWriteDone`、`TTyTerminalCore`）和 `TTyUnicodeVersion`、`TTyScrollBarAutoHide` 在本单元 interface 段各起一个同名别名（`TTyTerminalDataEvent = tyControls.Terminal.Core.TTyTerminalDataEvent;`），宿主只 `uses tyControls.Terminal` 就够。
- 转给 Core 的 setter：`Scrollback`、`ConvertEol`、`TabStopWidth`、`ScrollOnUserInput`、`ReadOnly`、`AmbiguousWide`、`UnicodeVersion`、`CursorStyle`（映射到 `tco*`）、`CursorBlink`；getter 读 Core（不另存一份，免得两份真相、也免得 `Loaded` 里互相覆盖，地雷 14）。`AmbiguousWide` / `UnicodeVersion` 变了还要清字形缓存、整屏重画。
- 控件自己存的：`CursorInactiveStyle`、`MacOptionIsMeta`、`AlternateScroll`、`DrawBoldTextInBrightColors`（变了整屏重画）、`ScrollBarAutoHide`（推给已建的条，照 `Memo.pas:1322-1330`）、`LineHeightPercent`（钳到 100–300；上游 `lineHeight < 1` 抛异常，我们钳）、`LetterSpacing`（钳到 −10–50），后两者变了走「度量变了」。
- 构造：`inherited Create`（基类已 `TyBornAtDesignPPI`）；`ControlStyle := ControlStyle + [csOpaque, csDoubleClicks, csTripleClicks]`；`TabStop := True`；初始尺寸照库里同类控件（`SetInitialBounds(0, 0, 480, 300)`，按 96 PPI）；`FCore := TTyTerminalCore.Create(80, 24)`；接 Core 事件（Step 3）；`FCore.ReportFocus(False)`（2 期交接：`Focused` 初值 True，新控件没焦点）；平台标志 `FIsMac := TyTerminalIsMac`、`FIsWindows := TyTerminalIsWindows`（受保护，测试可改）。**不建**滚动条、计时器、表面位图。

- [ ] **Step 3: Core 事件接线**（每一行都要有测试，Task 9）

| Core 事件 | 控件做什么 |
|---|---|
| `OnData` | 转发 `OnData`（`ReadOnly` 已由 Core 挡掉） |
| `OnRefreshRows(F, L)` | 同步输出开着 → 攒起来（Task 8 Step 4）；否则把攒着的并进来、映射成视口行、标脏、`InvalidateRows`；记一次「活动」（闪烁用） |
| `OnTitleChange` | 存 `Title`、转发 |
| `OnBell` | 转发 |
| `OnOsc` | 转发 |
| `OnCursorMove` | 旧光标行、新光标行标脏；闪烁复位成「显示」；输入法光标矩形更新（Task 13） |
| `OnScroll(AYDisp)` | 全部行标脏、`Invalidate` 网格区；同步滚动条（Task 12） |
| `OnBufferActivate` | 全部行标脏；滚动条启用状态（Task 12） |
| `OnModesChange` | 光标行标脏（DECSCUSR、DECTCEM）；重算有效闪烁、开停计时器 |
| `OnQueryBaseColor(i)` | 从色表答（Step 6）；`i` 越界答 0 |
| `OnRequestScrollToBottom` | `FCore.ScrollToBottom` |
| `OnProcessRequest` | `ScheduleSlice`（Step 4） |
| `OnWindowOptionsReport` | 14t → `FCore.Input(ESC '[4;' 行数×格高 ';' 列数×格宽 't', False)`；16t → `ESC '[6;' 格高 ';' 格宽 't'`（设备像素，核实记录 11） |
| `OnResize(C, R)` | 存 `FCols` / `FRows`、重分配表面、全部行标脏、发 `OnGridResize(C, R)`、同步滚动条 |
| `OnScrollbackCleared` | 同步滚动条（选区 4 期） |

- [ ] **Step 4: 调度**：`ScheduleSlice`（虚方法）默认 `if not (csDesigning in ComponentState) then Application.QueueAsyncCall(@AsyncSlice, 0)`；`AsyncSlice`：`if FCore.ProcessPending then ScheduleSlice`。设计期不排片（预览走 `WriteSync`）。

- [ ] **Step 5: 网格与字体**

- `ResolveFontSpec`（开工前问题二第 6 条的顺序）：`ovr := ActiveController.Model.ResolveOverride(StyleOverride)`（`StyleOverride = ''` 时跳过；按 `(Model, ThemeVersion, StyleOverride)` 缓存）；`st := CurrentStyle`（`TyTerminal`，含覆盖）。
  - 字体族：`tpFontName in ovr.Present` → `ovr.FontName`；否则 `not ParentFont` 且 `Font.Name` 不是 `'default'`（也不是空）→ `Font.Name`；否则主题规则写了 `font-family`（`tpFontName in st.Present`）→ `st.FontName`；否则 `RawVar('--terminal-font-family')`；空就 `'monospace'`。最后 `monospace` → Windows `Consolas`、Linux / BSD `Monospace`、macOS `Menlo`（按平台 `{$IFDEF}`，不按 widgetset，[[widgetset-not-platform-gating]]）。
  - 宽字体：`RawVar('--terminal-font-family-wide')`；`monospace-wide` → Task 0 定下的平台默认（可能是空串）。
  - 字号：`tpFontSize in ovr.Present` → `ovr.FontSize`；否则 `not ParentFont` 且 `Font.Size <> 0` → `Font.Size`；否则 `st.FontSize`（基础层 `var(--terminal-font-size)`）；再没有 → `TyEffectiveFontSizeLogical(0)`。
  - PPI = `Font.PixelsPerInch`（全库约定）；`LetterSpacing`、`LineHeightPercent`、两个线宽 token（`ActiveController.Metric('--terminal-underline-width', 1)`、`'--terminal-cursor-width'`）一起进规格记录。
- `EnsureMetrics`：规格记录和上次不同 → `TyTermMeasureCell`、清字形缓存、全部行标脏、表面外框标脏；网格要变就 `RequestRelayout`（在 `RenderTo` 里只记下、`QueueAsyncCall` 一次；不在绘制中就直接 `UpdateGrid`）。
- `UpdateGrid`（`Resize`、度量变了、内边距变了、`RequestRelayout` 回调里调）：`pad := CurrentStyle.Padding` 按 PPI 缩放；`barW := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), PPI, 96)`（**恒扣**，地雷 6；设计期也扣，设计器和运行时同一网格）；`cols := Max(2, (ClientWidth − pad.L − pad.R − barW) div CellW)`、`rows := Max(1, (ClientHeight − pad.T − pad.B) div CellH)`；和 Core 不同 → `FCore.Resize(cols, rows)`（`OnResize` 会回来做其余的事，地雷 7）；**第一次**（不在 `csLoading`、有父控件）即使相同也发一次 `OnGridResize`（spec §9.2「加载完成后的第一次也发」）。
- `CellRect(c, r)` = `(pad.L + c·CellW, pad.T + r·CellH, +CellW, +CellH)`；`CellAt(X, Y)` = 减内边距后整除、钳到 `[0, Cols−1] × [0, Rows−1]`（上游先钳再除，`MouseCoordsService.ts:38-44`）；`SizeForGrid(c, r)` = `(pad.L + pad.R + barW + c·CellW, pad.T + pad.B + r·CellH)`。

- [ ] **Step 6: 主题取色**

- 色表 259 项，键 `(ActiveController.Model 指针, Model.ThemeVersion)`——**只比版本号不够**：换 `Controller` 后两个模型的版本号可能恰好相同。0–15 = `ResolveStyle('TyTerminalAnsi<n>', '', []).TextColor`；16–255 = `TyTermDefaultPaletteColor`；256 = `TyTerminal` 的 `TextColor`；257 = `TyTerminal` 的 `Background.Color`；258 = `TyTerminalCursor` 的 `Background.Color`；另存光标墨色 = `TyTerminalCursor` 的 `TextColor`。颜色一律取 RGB、丢掉 alpha（`--terminal-bg` 不该是半透明，文档写明）；某个键没解析出颜色时退到 Tango / 黑白，不抛。
- `Invalidate` 覆盖（开工前问题二第 13 条）：`inherited` 之前比色表键；变了 → `ThemeChanged`：重建色表、`FCore.NotifyColorSchemeChanged`（清 OSC 覆盖色、2031 开着就报明暗）、表面外框标脏、全部行标脏、`EnsureMetrics` 的键失效。`RenderTo` 开头再比一次（无头测试不走 `Invalidate`）。`NotifyColorSchemeChanged` 会同步发 `OnData`——这在 `Invalidate` 里是安全的（不改尺寸、不重入绘制）。
- 设 `Controller` 属性后同样走 `ThemeChanged`（键里有模型指针，自然会走到）。

- [ ] **Step 7: 设计期预览**（开工前问题二第 21 条）：`csDesigning` 时，每次 `OnResize` 之后 `FCore.WriteSync(#27'c' + TyTerminalDesignPreview)`；常量 `TyTerminalDesignPreview` 是 CRLF 分行的字节串：第 1 行 `ESC[30m`…`ESC[37m` 八色各写色名、第 2 行 `ESC[90m`…`ESC[97m`、第 3 行八个底色块、第 4 行粗体 / 暗淡 / 斜体 / 五种下划线 / 删除线 / 反显各一词、第 5 行「中文 한국어」与 `┌─┬─┐`，最后 `ESC[0m`。不进流式化，不建计时器和滚动条（地雷 8）。

- [ ] **Step 8: 公开方法**：`Write` 两个重载、`WriteSync` 转 Core；`Reset` → `FCore.Reset` + 全部行标脏 + `Invalidate`；`Clear` → `FCore.ClearScrollback`；四个 `Scroll*` 转 Core（`ScrollPages` 同名转发）；`Paste` / `Input` / `PasteFromClipboard` 在 Task 11。

- [ ] **Step 9: 析构**（地雷 8）：`Application.RemoveAsyncCalls(Self)` → 释放两个计时器 → 输入法卸载（Task 13）→ Core 的事件全置 nil → 释放 Core、字形缓存、光栅器、表面 → `inherited`。

- [ ] **Step 10: 加进 `.lpk`，提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas tycontrols.lpk && git commit -m "feat(terminal): TTyTerminalView holds a core and wires it up

Properties are forwarded to the core instead of kept twice; every core
event lands somewhere (dirty rows, the title, the scroll bar, the grid
size, colour queries answered from the theme, window reports in device
pixels); processing slices go through the message queue. The grid is
sized from the client area less padding and a scroll bar's width that
is always reserved, so columns never change when the bar comes and goes.
The font comes from StyleOverride, then an explicit Font, then the
theme's tokens, with monospace mapped to the platform's fixed-pitch
face. A new control reports itself unfocused to the core at once.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 控件绘制——表面位图、脏行、光标与闪烁、同步输出、DPI

**Files:**
- Modify: `source/tyControls.Terminal.pas`

- [ ] **Step 1: 表面位图与 `RenderTo`**（开工前问题二第 14 条）

1. `EnsureThemeCurrent`（Task 7 Step 6）、`EnsureMetrics(APPI)`。
2. 表面尺寸 ≠ `ARect` 尺寸 → 重建（不透明 `TBGRABitmap`），外框标脏、全部行标脏。
3. 外框脏 → `TTyPainter.Create` + `BeginPaintOn(ACanvas, ARect, FSurface)`（`Painter.pas:1306`）→ `DrawFrame(P, R, CurrentStyle)`、内边距与网格外的余量填 `TyTerminal` 底色 → `EndPaint`（[[painter-bgra-overwrites-canvas-gdi]]：EndPaint 之后不再有 GDI 绘制）；全部行标脏。
4. 脏的视口行 `r`：`abs := Buffer.YDisp + r`；`line := Buffer.GetLine(abs)`（nil 时画空行）；光标列 = 满足「`ShowCursor`、`Buffer.YDisp = Buffer.YBase`（视口在底部）、`abs = YBase + Y`、闪烁相位为显示」时的 `Buffer.X`，否则 −1；光标形状（Step 2）；`FRowPainter.PaintRow(FSurface, pad.L, pad.T + r·CellH, line, Cols, 列, 形状)`；清掉该行的脏标记。输入法组字串在这之后叠在光标行上（Task 13）。
5. `FSurface.DrawPart(ACanvas.ClipRect 与 ARect 的交, ACanvas, …, True)`（不透明，`bgra:` 执行时核对 `DrawPart` 的签名与行号）；裁剪区为空就整张画。
6. `Paint` = `RenderTo(Canvas, ClientRect, Font.PixelsPerInch)`。
7. **绝不**在这里调 `FCore.Resize`、发宿主事件（地雷 5）；度量变了要改网格就 `RequestRelayout`。

- [ ] **Step 2: 光标形状**：有效样式 = `Modes.CursorRequest`（非 `tcrDefault` 时）否则 `CursorStyle`；聚焦 → 块实心 / 下划线 / 竖线；失焦 → `CursorInactiveStyle`：轮廓（块轮廓）、块（实心）、竖线、下划线、无。光标色 / 墨色 = 色表 258 / 光标墨色；竖线与下划线粗细 = `CursorWidthPx`（token `--terminal-cursor-width` 按 PPI 缩放，至少 1）。

- [ ] **Step 3: 脏行与失效**

- 脏标记：长度 `Rows` 的布尔数组（或位图）+ 「全部脏」标志；`OnResize` 时重分配。
- 映射（开工前问题二第 15 条）：Core 行 `y` → 视口行 `y + YBase − YDisp`，落在 `[0, Rows)` 外就不标。
- `InvalidateRows(AFirst, ALast)`（受保护、虚，FOR THE TESTS 可观察，**子类覆盖必须调 inherited**）：有句柄时 `LCLIntf.InvalidateRect(Handle, 行矩形并集, False)`；没句柄只留脏标记。

- [ ] **Step 4: 同步输出**（核实记录 12、2 期交接）

- `OnRefreshRows` 时 `FCore.Modes.SynchronizedOutput` 为真：把区间并进 `FSyncFirst` / `FSyncLast`（第一次就置「在攒」）；`FSyncTimer` 没在跑就启动（懒建 `TTimer`，1000ms，一次性）。**模式打开本身不启动计时器**（`OnModesChange` 不碰它）。
- 模式关着时来的 `OnRefreshRows`：有攒着的就并进来、停计时器、清「在攒」，再照常标脏失效。
- 计时器到点：停、`FCore.EndSynchronizedOutput`（它清模式、`RefreshAll` → 回到上一条正常重画）。
- 析构前停掉（地雷 8）。

- [ ] **Step 5: 闪烁**（spec §9.10）

- 有效闪烁 = `Modes.BlinkRequest`（`tbrOn` / `tbrOff`）否则 `CursorBlink`。
- 计时器（懒建，600ms）只在「有效闪烁 且 `Focused` 且有句柄 且非设计期」时开；`DoEnter` / `DoExit` / `OnModesChange` / 属性 setter 里重算。
- `BlinkTick(ANowMs)`（计时器回调传 `Clock` 的当前值：`FCore.Clock` 非 nil 用它，否则 `TyTermDefaultClock`）：`ANowMs − FLastActivityMs ≥ 300000` → 相位置「显示」、停计时器、光标行标脏；否则翻转相位、光标行标脏。
- 「活动」：`OnRefreshRows`（有输出）、按键发出字节（Task 11）、`OnCursorMove` → `FLastActivityMs := 现在`、相位置显示、计时器停了就按条件重开。

- [ ] **Step 6: DPI**：`EnsureMetrics` 的规格记录含 PPI，`AutoAdjustLayout` / `ScaleFontsPPI` 之后下一次 `RenderTo` / `UpdateGrid` 自然重建；`Resize` 里调 `UpdateGrid`（它内部 `EnsureMetrics(Font.PixelsPerInch)`）。

- [ ] **Step 7: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.pas && git commit -m "feat(terminal): paint only the rows that changed, into a kept surface

The control keeps one opaque bitmap the size of its client area; the
frame is painted into it when the theme or size changes, rows when the
core reports them dirty (mapped through the viewport, so output below a
scrolled-up view is not painted over the wrong line), and Paint copies
only the clip. Synchronized output holds rows back and lets them go when
the program ends it or a second after the first held row. The cursor
takes the program's DECSCUSR shape over the property, the inactive style
when unfocused, blinks at 600 ms and rests visible after five idle
minutes.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 控件的事件、调度、焦点、主题测试

**Files:**
- Create: `tests/test.terminal.view.pas`（suite `TTyTerminalViewTests`；探针类 `TTyTerminalViewProbe` 放在这里，Task 10、14 复用——单元 interface 段导出它和夹具辅助 `NewViewOnForm`）
- Modify: `tests/tytests.lpr`

探针：`TTyTerminalViewProbe = class(TTyTerminalView)` 公开 `RenderTo`、`BlinkTick`、`KeyDown`、`UTF8KeyPress`、`DoMouseWheel`、`DoEnter`、`DoExit`、平台标志、`RowsPainted`、`GlyphCache`、`Metrics`；覆盖 `ScheduleSlice`（计数，按开关决定是否调 inherited）、`InvalidateRows`（记录区间后 inherited）、`ReadClipboardText` / `WriteClipboardText`（桩）。夹具：`TForm.CreateNew(nil)` 当父控件、自建 `TTyStyleController`（`ThemeName := 'default'`、`Mode := 'light'`）、`TyFallbackFontName` 钉死并在 `TearDown` 恢复（地雷 9、10）。

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestPublishedDefaultsMatchTheConstructor` | RTTI 遍历全部 published 序数 / 枚举 / 布尔 / 整数属性（`Default <> $80000000`）：新建实例的值 = 声明的 `Default`；至少查到 17 个（防 RTTI 读空） | V1：构造里 `LineHeightPercent := 110` |
| `TestSettersReachTheCore` | 设 `Scrollback := 50`、`ConvertEol`、`TabStopWidth := 4`、`ScrollOnUserInput := False`、`ReadOnly`、`AmbiguousWide`、`UnicodeVersion := tuv15`、`CursorStyle := tcsBar`、`CursorBlink` → Core 对应属性相等 | V2：`UnicodeVersion` setter 不转发 |
| `TestStreamedValuesSurviveLoading` | 非默认值写进流（`TWriter` / `TReader`，照库里已有的流式化测试写法）再读回新实例：Core 的值是流里的 | V3：`Loaded` 把 Core 按默认值重设 |
| `TestCoreRepliesComeOutOfOnData` | `WriteSync(ESC '[c')` → `OnData` = `ESC '[?1;2c'`（xterm.js 的 DA1 应答，执行时对 2 期夹具核对） | V4：`OnData` 没接 |
| `TestTitleBellAndOsc` | `OSC 2;hi BEL` → `OnTitleChange('hi')`、`Title = 'hi'`；`BEL` → `OnBell` 一次；`OSC 7;file://x BEL` → `OnOsc(7, 'file://x')` | V5：`OnOsc` 没接；V5b：`Title` 读 Core 之外的空字段 |
| `TestANewControlIsUnfocusedToTheCore` | 新控件 `WriteSync(ESC '[?1004h')` → `OnData` = `ESC '[O'`；`DoEnter` → `ESC '[I'`；`DoExit` → `ESC '[O'` | V6：构造里没 `ReportFocus(False)`；V7：`DoEnter` 没报 |
| `TestColourQueriesAnswerFromTheTheme` | `OSC 11;? BEL` 的应答颜色 = 控制器解析出的 `TyTerminal` 底色；`OSC 10` = 前景；`OSC 12` = 光标；`OSC 4;1;?` = `TyTerminalAnsi1`（按 `TyTermToRgbString` 的格式比） | V8：256 / 257 对调 |
| `TestAThemeChangeDropsOverridesAndReports` | `OSC 4;1;#123456` → `Core.ResolveColor(1) = $123456`；打开 2031；`Controller.Mode := 'dark'` → 覆盖没了（等于暗色主题的 Ansi1）且 `OnData` 收到一次明暗报告（上游格式 `CSI ? 997 ; <1 暗 / 2 浅> n`，执行时对 `CoreBrowserTerminal.ts:261-` 与 2 期夹具核对） | V9：`Invalidate` 覆盖不比键；V9b：比了键但不调 `NotifyColorSchemeChanged` |
| `TestSwappingControllersRebuildsThePalette` | 两个新建控制器，A light、B dark；先断言 `A.Model.ThemeVersion = B.Model.ThemeVersion`（前提，失败就说明夹具要改）；控件从 A 换到 B → `ResolveColor(257)` = B 的底色 | V10：色表键只有版本号 |
| `TestWindowReportsInDevicePixels` | `Core.WindowOptions := [twoGetWinSizePixels, twoGetCellSizePixels]`；`CSI 14 t` → `ESC[4;<Rows×CellH>;<Cols×CellW>t`；`CSI 16 t` → `ESC[6;<CellH>;<CellW>t` | V11：宽高对调 |
| `TestTheGridFollowsTheClientArea` | `SetBounds` 使客户区 = `pad×2 + barW + 10·CellW + 3` × `pad×2 + 5·CellH + 2` → `Cols = 10`、`Rows = 5`、`Core.Cols / Rows` 相同、`OnGridResize(10, 5)` 恰一次 | V12：没扣条宽 |
| `TestTheFirstLayoutIsAnnounced` | 客户区恰好 80 × 24 格 → `OnGridResize(80, 24)` 恰一次；再原样 `SetBounds` 不再发 | V13：只在变了时发 |
| `TestDecColmResizesTheGrid` | `WindowOptions := [twoSetWinLines]`；`CSI ? 3 h` → `OnGridResize(132, Rows)` | V14：`OnResize` 没接 |
| `TestSizeForGridRoundTrips` | `SizeForGrid(c, r)` 设成客户区 → `(Cols, Rows) = (c, r)`；宽少 1 像素 → `c − 1` | V15：`SizeForGrid` 漏了内边距 |
| `TestCellAtAndCellRect` | `CellRect(3, 2)` 的四个值；`CellAt(那个矩形的中心) = (3, 2)`；`CellAt(-5, 10000)` 钳到 `(0, Rows − 1)` | V16：`CellAt` 不钳 |
| `TestAWriteAsksForOneSlice` | 缝：`Write('a')` → `ScheduleSlice` 调 1 次；再 `Write('b')`（前一片没处理）→ 仍 1 次；探针手动 `ProcessPending` 返回 False 后再 `Write` → 2 次 | V17：`OnProcessRequest` 没接 |
| `TestSlicesRunThroughTheMessageQueue` | 真路径（惰性初始化 `Forms.Application`，照 `test.focus.tabstop.pas:595`）：注入 `Core.Clock` 每次调用 +20ms（每片只处理一块）；写三块、各带回调；循环 `Forms.Application.ProcessMessages` 至多 100 次直到三个回调都到 → 回调按序、缓冲第 0 行是三块拼起来的文本 | V18：`AsyncSlice` 在 `ProcessPending` 返回 True 时不再排 |
| `TestAFreedControlLeavesNoSliceBehind` | `Write` 后立刻 `Free`，再 `ProcessMessages` → 不抛、不访问违例 | V19：析构没 `RemoveAsyncCalls` |
| `TestSyncOutputHoldsRowsBack` | `CSI ? 2026 h` 后写一行 → `InvalidateRows` 没被调、同步计时器已开；`CSI ? 2026 l` → 失效区覆盖那一行、计时器停 | V20：攒行不看模式 |
| `TestSyncOutputTimesOut` | 2026 开、写一行、手动触发同步计时器 → `Modes.SynchronizedOutput = False`、那一行失效 | V21：计时器回调什么都不做 |
| `TestTheSyncTimerStartsAtTheFirstHeldRow` | 只发 `CSI ? 2026 h`（没有输出）→ 计时器没开；再写一个字 → 开了 | V22：模式一打开就开计时器 |
| `TestResizingFromACoreEventIsSafe` | 宿主在 `OnTitleChange` 里改控件宽度；`WriteSync(OSC 2;x BEL + 文本)` 不抛，之后 `Cols` 跟新宽度一致 | —（Core 的延后已有测试，这条守控件没有在事件里假设尺寸已生效） |
| `TestDesignTimePreview` | 探针置 `csDesigning`（`SetDesigning(True)`）后排版 → 缓冲第 0 行文本以 `black` 开头（预览第一词）；没有滚动条子控件；两个计时器都没建；`ScheduleSlice` 没被调 | V23：预览没写；V23b：设计期照样建滚动条（Task 12 之后才能做，挪到 Task 14 验） |

- [ ] **Step 1: 写测试单元、加进 `tytests.lpr`**
- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.view.pas tests/tytests.lpr && git commit -m "test(terminal): the control's wiring, scheduling, focus and colours

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 控件像素测试

**Files:**
- Create: `tests/test.terminal.view.paint.pas`（suite `TTyTerminalViewPaintTests`，用 Task 9 的探针与夹具）
- Modify: `tests/tytests.lpr`

夹具补充：网格定在 20 × 5（用 `SizeForGrid`）；画法 `bmp := TBGRABitmap.Create(W, H, 品红)`、`probe.RenderTo(bmp.Canvas, Rect(0,0,W,H), PPI)`；颜色都从夹具的控制器现解析（不写死十六进制）；字形相关只数墨（像素 ≠ 该格底色）；颜色断言用 █（Task 6 已证它整格纯色）。**写断言前先打一次包围盒**（地雷 9）。

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestAnEmptyTerminalIsAllBackground` | 客户区每个像素都等于 `TyTerminal` 底色（默认无边框；有边框的主题另作一例：边框像素 = 边框色，其余 = 底色），一个哨兵都不剩 | V24：内边距 / 网格外余量没填 |
| `TestSixteenColoursComeFromTheTheme` | `ESC[3<n>m█`（n = 0–7）、`ESC[9<n>m█` 各占一格：每格整格 = `TyTerminalAnsi<n>` / `<n+8>` | V25：8–15 映射回 0–7 |
| `Test256AndTrueColour` | `ESC[38;5;196m█` = `$FF0000`；`ESC[38;2;1;2;3m█` = `$010203`；`ESC[48;5;21m ` 整格 = `$0000FF` | V26：空格不铺底色 |
| `TestBoldBrightens` | `ESC[1;31m█` = Ansi9；`DrawBoldTextInBrightColors := False` 后重画 = Ansi1 | V27：属性没接到行绘制器 |
| `TestInverseDimAndHidden` | `ESC[7m ` = 前景色整格；`ESC[2;38;2;255;0;0;48;2;0;0;0m█` = `(128,0,0)`；`ESC[8m█` = 底色 | V28：隐藏照画 |
| `TestAWideCharacterTakesTwoCells` | `中X`：格 0、格 1 都有墨，`X` 的墨全在格 2 | V29：宽字符只推进一格 |
| `TestUnderlineStyles` | 空格 + `ESC[4:<s>m`：墨只在基线以下的行；s = 2 时中间一列上两段墨；s = 3 时各列最高墨行不全相同；s = 4 / 5 时下划线带里有空列，且 5 的空段比 4 长；`ESC[4;58;2;0;0;255m ` 的墨是蓝色 | V30：样式一律当单线；V31：下划线色不用 |
| `TestStrikeAndOverline` | `ESC[9m ` 的墨在格子中部（`TextTop + CharH/4` 到 `TextTop + 3·CharH/4`）；`ESC[53m ` 的墨在格子顶部三分之一 | V32：删除线画在下划线位置 |
| `TestBoxDrawingJoinsEvenWithExtraLineHeight` | `LineHeightPercent := 150`；三行各一个 │：有一列在整整三格高度里每行都有墨 | V33：不走自绘（字体的 │ 撑不满多出来的行高） |
| `TestCursorShapes` | 光标在 `W` 上（写 `W` 再 `CSI D`），聚焦（探针置焦点标志，或走 `DoEnter`）：块 → 该格多数像素 = 光标色、且有光标墨色的像素；`CSI 4 SP q` → 只有底部 `CursorWidthPx` 行是光标色；`CSI 6 SP q` → 只有左侧 `CursorWidthPx` 列是光标色 | V34：DECSCUSR 被忽略 |
| `TestInactiveCursorStyles` | 失焦：轮廓 → 边上 `LineW` 圈 = 光标色、中心 = 字形或底色；`tcisNone` → 该格没有光标色 | V35：失焦照画实心 |
| `TestHiddenAndScrolledAwayCursors` | `CSI ? 25 l` → 没有光标色；写 30 行后 `ScrollLines(-2)` → 没有光标色 | V36：视口不在底部照画 |
| `TestCursorOnAWideCharacter` | 光标在 `中` 上，块 → 两格都是光标色为主 | — |
| `TestBlinkHidesThenRests` | `CursorBlink := True`、聚焦；`BlinkTick(t0 + 600)` → 光标行被标脏、再画没有光标色；`BlinkTick(t0 + 1200)` → 有；从最后一次活动算起 `+300000` → 有、计时器停；再 `WriteSync('x')` → 计时器又开 | V37：没有 5 分钟停闪；V38：`CSI 1 SP q`（程序要闪）在 `CursorBlink = False` 时不闪 |
| `TestOnlyDirtyRowsArePainted` | 画一次；`WriteSync(CSI 4;1H + 'x')` → 下一次画 `RowsPainted` 只加 1，`InvalidateRows` 收到 `(3, 3)` | V39：刷新时整屏标脏 |
| `TestDirtyRowsFollowTheViewport` | 5 行终端写 30 行（光标停在屏幕第 4 行、不换行），画一次；`ScrollLines(-2)`，再画一次；此后 (a) 在屏幕第 4 行写一个字（不换行、不滚动）→ 映射到视口第 `4 + 2 = 6` 行，落在视口外，`RowsPainted` 不变、`InvalidateRows` 没被调；(b) `CSI 2;1H` 写一个字（屏幕第 1 行）→ 视口第 3 行，`RowsPainted` 加 1、`InvalidateRows` 收到 `(3, 3)` | V40：映射忽略 `YDisp`（(a) 会画第 4 行、(b) 会画第 1 行） |
| `TestGlyphsAreCachedWithoutTheirColour` | 写 `aaaa` → `Misses = 1`、`Hits ≥ 3`；再写 `ESC[31ma` → `Count` 不变；`ESC[1ma` → `Count` + 1 | V41：颜色进了键（E2 选（b）时本条反过来：`Count` + 1） |
| `TestAFontChangeClearsTheCache` | `ParentFont := False; Font.Size := 12` → 下一次画之后 `Metrics.CellH` 变大、缓存里只有新画的字 | V42：规格记录不含字号 |
| `TestTheCellScalesWithThePPI` | `RenderTo` 在 144 PPI 下 `Metrics.CellW` 是 96 下的 1.4–1.6 倍；192 PPI 下单下划线带 2 行厚 | V43：规格记录不含 PPI |
| `TestPaddingComesFromTheTheme` | `StyleOverride := 'padding: 10px'` → `CellRect(0, 0).TopLeft = (10, 10)`（96 PPI）；网格随之少算 | V44：内边距写死 |
| `TestTheFontOrder` | `Metrics` 之外再露出 `FontSpec`：默认 `MainName = 'Consolas'`（Windows 上 `monospace` 的映射）；`StyleOverride := 'font-family: Courier New'` → `Courier New`；清掉覆盖，`ParentFont := False; Font.Name := 'Lucida Console'` → 它；两者都设 → 覆盖赢；`Font.Name := 'default'` → 退回 token | V45：Font 压过 StyleOverride；V46：`'default'` 当字体名传下去 |
| `TestBlinkingTextIsDrawnSteady` | `ESC[5m█` 整格 = 前景；`BlinkTick` 前后各画一次，该格像素相同 | — |
| `TestWarmRedrawTime`（只打印） | 200 × 60、全屏各种 ASCII、先画一次热身，再整屏标脏重画 5 次取中位数，`WriteLn` 用时（Task 20 Step 3 用；不断言） | — |

- [ ] **Step 1: 写测试单元、加进 `tytests.lpr`**
- [ ] **Step 2: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.view.paint.pas tests/tytests.lpr && git commit -m "test(terminal): pixels for colours, attributes, glyphs, cursor and dirty rows

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: 段 3b 编译并跑本段 suite**（主文件「跑测试的固定套路」3b 行）。只修本段的红。像素断言红了先打包围盒看图，再判是控件错还是断言错（[[headless-render-needs-sentinel-ground]]）。
