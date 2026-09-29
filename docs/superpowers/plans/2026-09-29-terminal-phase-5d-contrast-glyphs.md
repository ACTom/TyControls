# 终端控件 5 期 · 5d 最低对比度与自绘字形（Task 10–12）

> 本文件是 [`2026-09-29-terminal-phase-5.md`](2026-09-29-terminal-phase-5.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 16–21、29，开工前问题一第 3、4 条、问题二第 11、12、16 条，地雷 6–9、14、17、18。

**这一批做完能看到什么**：对比度的纯函数（亮度、对比度、`ensureContrastRatio`、增减亮度、选项钳制、排除的码位）与上游逐位相同；控件有 `MinimumContrastRatio`，打开后前景按上游规则调整——暗淡减半、选区对选区底色、框线块元素与 Powerline 不动、块光标下的字与链接下划线不动，默认 1 时像素和现在逐字节相同；示例有下拉。（用户同意时）Powerline 与盲文自绘。段末编译一次，只跑 5d 的 suite。

---

### Task 10: 对比度的基准与纯函数

**Files:**
- Create: `tools/terminal-oracle/contrast-cases.js`
- Modify: `tools/terminal-oracle/lib-dump.js`（`PORTED`、`GENERATED`）、`regen-all.js`（`SCRIPTS`）
- Generate: `source/tyControls.Terminal.Luminance.inc`、`tests/fixtures/terminal-contrast.json`
- Modify: `source/tyControls.Terminal.Render.pas`、`tests/test.terminal.render.pas`

- [ ] **Step 1: `lib-dump.js`**：`PORTED` 加 `browser/renderer/shared/RendererUtils`、`common/services/OptionsService`（`common/Color` 已在）；`GENERATED` 加两个生成物。
- [ ] **Step 2: `contrast-cases.js`**（Write 工具落文件；头注释写做什么、怎么跑、为什么亮度用表——开工前问题二第 12 条）：
  1. **亮度表**：`c = 0..255`，照 `Color.ts:240-248` 的**同一个表达式**在 node 里算线性化值（`rs <= 0.03928 ? rs / 12.92 : Math.pow((rs + 0.055) / 1.055, 2.4)`，`rs = c / 255`）。**自证**：种子化随机 100000 个颜色，断言 `t[r] * 0.2126 + t[g] * 0.7152 + t[b] * 0.0722` 与上游 `rgb.relativeLuminance2(r, g, b)` 用 `Object.is` 逐个相等，不等就中止。写 `source/tyControls.Terminal.Luminance.inc`：`TyTermLinearChannelBits: array[0..255] of QWord`，每项是那个 double 的 IEEE 位模式（`$` 十六进制，16 位）；头部写上游版本、commit、提交日期、「由 contrast-cases.js 生成，勿手改」；不许有花括号（地雷 6，脚本检查）。
  2. **夹具 `terminal-contrast.json`**（颜色一律 `$RRGGBB` 整数，double 一律位模式的十六进制串）：
     - `luminance`：Tango 16 色、`light.tycss` 浅底 12 色（从 `light-palette.js` 的输出取，不重算）、24 级灰、种子化随机 2000 色 → `relativeLuminance` 的位模式。
     - `ensure`：底色 × 前景 × 比值：底 / 前从「Tango 16 + 浅底 12 + 灰阶 24 + 黑白」两两组合，另加种子化随机 3000 对；比值取 `1, 1.5, 2.25, 3, 3.5, 4.5, 7, 10.5, 21`；导出 `rgba.ensureContrastRatio(bg << 8 | 0xff, fg << 8 | 0xff, r)` 的结果（`null` = 上游 `undefined`）。
     - `reduce` / `increase`：随机 500 对 × 比值 4.5、7，分别调两个函数。
     - `clamp`：`new OptionsService({})` 之后逐个设 `options.minimumContrastRatio = v` 再读回（走上游自己的钳制，`OptionsService.ts:188-190`）；`v` 取 `−5, 0, 0.5, 1, 1.04, 1.05, 1.15, 1.25, 1.35, 4.45, 4.449999, 4.5, 7.35, 20.96, 21, 21.04, 22, 1e9`。
     - `excluded`：码位 `0x2400–0x2700`、`0xE000–0xE100` 全部，导出 `treatGlyphAsBackgroundColor(cp)` 为真的区间。
- [ ] **Step 3: `regen-all.js`** 的 `SCRIPTS` 在 `view-cases.js` 之后加 `contrast-cases.js`；跑它，`git status` 只多这两个生成物。抽查：`ensure` 里白底、Tango 3 号、4.5 → `$8e7400`（核实记录 16）。
- [ ] **Step 4: 纯函数**（`Render.pas`，接口清单；函数上方注释标 `Color.ts` 行号；单元头的「ported from」加 `src/common/Color.ts:230-384`、`src/browser/renderer/shared/RendererUtils.ts:15-65`、`src/browser/ColorContrastCache.ts`）：
  - `TyTermRelativeLuminance`：`{$I tyControls.Terminal.Luminance.inc}` 的表（位模式经 `PDouble(@bits)^` 取值），`t[r] * KR + t[g] * KG + t[b] * KB` 按这个顺序，`KR` / `KG` / `KB` 是 `Double` 类型的常量（地雷 8）。
  - `TyTermContrastRatio`、`TyTermReduceLuminance`、`TyTermIncreaseLuminance`、`TyTermEnsureContrastRatio`：逐行照 `Color.ts:296-362`。`Math.ceil(x * 0.1)` 写成 `Ceil(x * KTenth)`，`KTenth: Double = 0.1`；循环条件、`resultARatio > resultBRatio ? A : B` 的方向照抄。
  - `TyTermClampContrastRatio`：`NaN` / 无穷按 1（§15）；否则 `Max(1, Min(21, Floor(v * 10 + 0.5) / 10))`——全部 `Double`，别用整数字面量的 `Max`（[[fpc-max-integer-literal-single]]），写 `Math.Max(1.0, …)`。
  - `TyTermExcludedFromContrast`：`(cp >= $E0A4) and (cp <= $E0D6)` 或 `(cp >= $2500) and (cp <= $259F)`。
  - `TTyTermContrastCache`：`TDictionary<UInt64, Cardinal>`，键 `(bg shl 24) or fg`（两个 24 位拼成 48 位，不对称），值的第 24 位标「调过」；`Find` / `Put` / `Clear` / `Count`。
- [ ] **Step 5: 测试**（判据；`TTyTerminalRenderTests` 里加，夹具读法照 `terminal-view-palette.json`）

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestLuminanceMatchesUpstream` | `luminance` 每一项：`TyTermRelativeLuminance` 的位模式与夹具相等（比 `QWord`，不比浮点） | T2：`KR` 写成未标类型的常量（Single 精度）；T1：改用 FPC `Power` 现算——**可能存活**（本机 `Power` 恰好在这 256 个值上与 V8 相同时），存活就记「本机等价」，表照样用（开工前问题二第 12 条） |
| `TestEnsureContrastRatioMatchesUpstream` | `ensure` 每一项：返回值（False ↔ `null`）与结果颜色相等；比较次数 = 夹具项数 | T3：`Ceil(x * 0.1)` 的 0.1 用 Single；T4：前景暗时只试 `reduce`、不试 `increase`；T8：`resultARatio > resultBRatio` 写成 `>=` |
| `TestReduceAndIncreaseMatchUpstream` | `reduce` / `increase` 每一项相等 | T9：`increase` 的每步写成 `x + Ceil((255 − x) × 0.1)` 但不钳 255 |
| `TestTheRatioIsClampedAsUpstream` | `clamp` 每一项：`TyTermClampContrastRatio(v)` = 夹具值（位模式相等） | T5：用 `Round`（银行家舍入，1.25 → 1.2） |
| `TestTheExcludedGlyphs` | `excluded` 的区间与 `TyTermExcludedFromContrast` 在两段码位上逐个一致 | T6：上界写成 `$E0D4` |
| `TestTheContrastCache` | 手写：`Put($111111, $222222, $333333, True)` 后 `Find($222222, $111111, …)` 答 False（键不对称）；`Put(…, False)` 后 `Find` 答 True 且 `AAdjusted = False`；`Clear` 后 `Count = 0` | T7：键写成 `bg xor fg` |

- [ ] **Step 6: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle source/tyControls.Terminal.Luminance.inc source/tyControls.Terminal.Render.pas tests/fixtures/terminal-contrast.json tests/test.terminal.render.pas && git commit -m "feat(terminal): xterm.js's minimum contrast functions, bit for bit

Relative luminance, contrast ratio, ensureContrastRatio with its reduce
and increase steps, the option's clamp and the glyphs that are drawn as
background, ported from Color.ts, RendererUtils and the options service.
The sRGB linearization comes from a table of V8's own results, generated
and checked against upstream, so a boundary comparison cannot tip by an
ulp; the fixture holds thousands of colour pairs at nine ratios.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异（JS 侧，期末做）**：J3：生成亮度表时把 2.4 写成 2.39——自证那一步必须中止（证明自证真的在比）。

---

### Task 11: 控件接上 `MinimumContrastRatio`

**Files:**
- Modify: `source/tyControls.Terminal.Render.pas`（`FgRaw`、行绘制器）、`source/tyControls.Terminal.pas`（属性、缓存、帧级参数）
- Modify: `examples/terminal/umain.pas`、`examples/terminal/umain.lfm`、`examples/terminal/languages/terminal_example.zh_CN.json`
- Modify: `tests/test.terminal.view.pas`、`tests/test.terminal.view.paint.pas`、`tests/test.terminal.view.theme.pas`、`tests/test.terminal.perf.pas`

规则见开工前问题二第 11 条，坑见地雷 7、14、17。

- [ ] **Step 1: `TyTermResolveCellColors`** 多填 `FgRaw`（暗淡之前的前景）；另加 `UnderlineIsDefault: Boolean`（下划线色没显式给）。`Fg`、`Underline` 照旧——比值为 1 的调用方完全不变。
- [ ] **Step 2: 行绘制器**：`PaintRow` 在「选区替换底色」之后、画字形之前，每格算一次最终的字色 `Ink`（存进 `TCellInfo`），字形、删除线、上划线、默认下划线都用它：
  1. `MinContrast <= 1`、或格子隐藏、或（非组合格且 `TyTermExcludedFromContrast(GetCodePoint(c))`）→ `Ink` = 现在的算法（选中且 `SelHasInk` 用 `SelInk`，否则 `C.Fg`），下划线不动。
  2. 否则：`base` = 选中且 `SelHasInk` ? `SelInk` : `C.FgRaw`；`ratio` = `MinContrast`，暗淡再除 2；缓存 = 暗淡用 `HalfContrastCache`，否则 `ContrastCache`；`TyTermEnsureContrastRatio(C.Bg, base, ratio, adj)`（先查缓存）；调过就 `base := adj`；暗淡再按 Step 1 同一个公式和 `C.Bg` 混；`Ink := base`；`UnderlineIsDefault` 时 `C.Underline := Ink`。
  3. 块光标下的字（`CursorInk`）、悬停链接的下划线色、显式下划线色不调（核实记录 18、20）。
  宽字符后半照旧抄前半的 `TCellInfo`。
- [ ] **Step 3: 控件属性**：`MinimumContrastRatio: Double`（开工前问题二第 16 条），`stored` 函数 `FMinContrast <> 1`，默认值 1 写在构造里。setter：`TyTermClampContrastRatio`；变了就清两份缓存、作废全部行键（Task 7 的帧级参数加它）、`Invalidate`。两份缓存由控件持有（构造建、析构放），交给行绘制器；色表签名变了（`EnsurePalette` / `PremixFrameColors` 里 `FColorSig` 变）两份一起清（上游换主题清缓存，`ThemeService.ts:136`）。
- [ ] **Step 4: 示例**：`Tools4` 那一排在 OSC 52 下拉后面加 `LblContrast`（`Caption = 'Minimum contrast:'`）和 `CmbContrast`（`Items = 1 / 3 / 4.5 / 7`，`ItemIndex = 0`，`AutoSize`），写进 `.lfm`（[[demo-edits-lfm-not-code]]）；`OnChange` 设 `Term.MinimumContrastRatio`（解析用 `StrToFloat` 带 `'.'` 的 `TFormatSettings`，不跟系统区域）。译文照 4 期：英文标题与中文「最低对比度：」进 `examples/terminal/languages/terminal_example.zh_CN.json`，`.po` 由主控在 Task 14 生成（地雷 18）。
- [ ] **Step 5: 测试**（判据；像素用下划线那几行验颜色，地雷 14）

**`TTyTerminalViewTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestMinimumContrastRatioProperty` | 新建：值 1、`IsStoredProp` 为假（RTTI 读 `stored`）；设 4.5 后为真；按 `terminal-contrast.json` 的 `clamp` 表逐个设、读回 = 夹具值；published 默认值守卫（3 期的 RTTI 测试）只管序数属性，这一条补浮点 | N10：`stored` 函数写反；N11：setter 不钳 |

**`TTyTerminalViewPaintTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestContrastAdjustsTheForeground` | 写 `ESC[4;38;2;170;170;170;48;2;187;187;187mAb`：比值 1 时下划线那几行的像素 = `$AAAAAA`；4.5 时 = `TyTermEnsureContrastRatio($BBBBBB, $AAAAAA, 4.5)` 的结果（该函数已由 Task 10 对上游证明） | N1：行绘制器不调前景（属性没接到绘制） |
| `TestDimHalvesTheRatio` | 同上加 `SGR 2`：下划线色 = 「`ensure(bg, fg, 2.25)` 的结果再按暗淡公式和底色混」 | N2：暗淡不减半；N3：先混暗淡再算对比度 |
| `TestExcludedGlyphsKeepTheirColour` | 4.5 下，前景 `$AAAAAA`、底 `$BBBBBB` 的 `█`（U+2588）格整格像素 = `$AAAAAA`；`─`（U+2500）的线像素同样；Task 12 做了的话加 U+E0B0 | N4：不排除 |
| `TestSelectionIsTheGroundForContrast` | 选中一个带下划线的格：下划线色 = `ensure(选区底色, fg, 4.5)`；实例 `StyleOverride` 给 `TyTerminalSelection` 写了 `color` 时 = `ensure(选区底色, 选区前景, 4.5)` | N5：选中时仍对格子自己的底色算 |
| `TestInverseUsesThePaintedColours` | 实例 `StyleOverride` 把 `TyTerminal` 的 `color` / `background` 设成 `#777777` / `#888888`；写反显、默认色、带下划线的字：下划线色 = `ensure($777777, $888888, 4.5)`（底 = 主题前景，前 = 主题底色） | N6：照 DOM 拿主题前景当前景（结果不同） |
| `TestCursorInkAndLinksKeepTheirColour` | 4.5 下块光标下那个字的像素 = `CursorInk`；按 Ctrl 悬停的链接下划线 = 链接色 | N7：光标下的字也调 |
| `TestTheCachesClearWithThePalette` | 4.5 下画一帧（缓存 `Count > 0`）；换主题使 257 号色变了：下一帧之前两份缓存 `Count = 0`，画完后下划线色 = 用新底色算的结果；把比值改成 7：缓存又清空 | N8：色表变了不清缓存（下划线色是旧底色的答案） |

比值为 1 时像素不变：由 3、4 期全部像素测试（它们都在默认 1 下跑）原样变绿证明，不另写。

**`TTyTerminalViewThemeTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestContrastLiftsTheSixteenColours` | 17 个主题 × 明暗，用本控件的色表：1–6、9–14 号色对 257 号底色，`ensure(底, 色, 4.5)` 之后的对比度 ≥ 4.5（上游对纯黑 / 纯白能到 21:1，任何底色都够得着 4.5）；把 xp / macos / breeze 浅色 3 号色前后的对比度打印出来（写进 spec §11） | —（守的是「兜底真的兜得住」；变异在上面几条） |

**`TTyTerminalPerfTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestContrastCostsLittle` | 满屏混合颜色、热缓存（先画两帧），`ForgetPaintedRows` + `RenderTo` 的中位（20 次）：4.5 ≤ 1 的 1.3 倍（同一次运行里比） | N12：不查缓存、每格现算 |

- [ ] **Step 6: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Render.pas source/tyControls.Terminal.pas examples/terminal/umain.pas examples/terminal/umain.lfm examples/terminal/languages/terminal_example.zh_CN.json tests/test.terminal.view.pas tests/test.terminal.view.paint.pas tests/test.terminal.view.theme.pas tests/test.terminal.perf.pas && git commit -m "feat(terminal): MinimumContrastRatio

Off at 1, as in xterm.js. Above it, a cell's text colour is pushed
lighter or darker until it stands off its background by that ratio --
half of it for faint text, measured against the selection where the cell
is selected, and never for box drawing, block elements or powerline
symbols, the cursor's text or a link's underline. Results are cached per
colour pair and dropped with the palette. The example offers 1, 3, 4.5
and 7.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12（有条件）: 自绘字形扩到 Powerline 与盲文

**只在开工前问题一第 4 条的答复是「做」时执行**；答复是别的范围，按答复调整 Step 1 的区段；答复「都不做」就跳过本任务，签收记录写一句，5d 段末从 Task 11 之后编译。

**Files:**
- Modify: `tools/terminal-oracle/gen-terminal-glyphs.js`；重新生成 `source/tyControls.Terminal.CustomGlyphs.inc`
- Modify: `source/tyControls.Terminal.Render.pas`
- Modify: `tests/test.terminal.render.pas`、`tests/test.terminal.view.paint.pas`

- [ ] **Step 1: 生成器**：区段从一个 `FIRST..LAST` 改成一张区段表：`[0x2500, 0x259F]`、`[0xE0A0, 0xE0D4]`、`[0x2800, 0x28FF]`。部件种类加：`VECTOR_SHAPE`（`d` 路径 + `FILL` / `STROKE` + `leftPadding` / `rightPadding`）、`BRAILLE`（数据是 0–255 的位图）；路径命令加 `Q`、`T`、`Z`（Powerline 用到的全部：`M L C Q T Z`，核实记录 29；脚本遇到别的命令或别的部件属性——`scaleType`、`clipPath` 等——就中止并打印码位）。索引表改成「区段号 + 区段内偏移」两级（`.inc` 里一个区段表 + 每段一个索引数组），`TyTermIsCustomGlyph` 查区段表。头注释补新种类的数据格式。重跑，`git diff` 里 U+2500–259F 那部分数据不变（只是换了索引的组织）。
- [ ] **Step 2: 光栅化**（`Render.pas`，照 `CustomGlyphRasterizer.ts`，函数上方标行号）：
  - `VECTOR_SHAPE`（`:620-667`）：先裁到格子；线宽 = `devicePixelRatio × fontSize / 12`（我们的 `devicePixelRatio` = PPI / 96，`fontSize` = 字号的 CSS 像素，同 3 期 `PATH_FUNCTION` 的换算）；`translateArgs` 的左右内边距；`Q` = `quadraticCurveTo`，`T` = 以上一个控制点的镜像作控制点（`svgToCanvasInstructionMap` 里的状态机，照抄 `lastControlX` / `lastCommand` 的规则），`Z` = `closePath`；`FILL` 用填充、`STROKE` 用描边。用 3 期已有的 BGRACanvas2D 路径（`DrawPathPart` 那一套）。
  - `BRAILLE`（`:152-194`）：点位表照抄；`xEighth = 格宽 / 8`、`paddingY = 格高 × 0.1`、`yEighth = 格高 × 0.8 / 8`、半径 `min(xEighth, yEighth)`；每个置位的点画一个整圆填充。
  - 进字形缓存的方式同 3 期的自绘字形（白色画在比格子大一圈的透明小位图上、裁到格子、成遮罩；缓存键 = 码位、格数、格宽、格高、PPI）。
- [ ] **Step 3: 测试**（判据；上游画法要 Canvas，node 里没有，没有像素基准——所以判据是形状上的不变量，注明「没有上游像素基准」）

**`TTyTerminalRenderTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestTheGlyphTableCoversTheNewRanges` | `TyTermIsCustomGlyph` 对 U+E0A0、U+E0B0、U+E0D4、U+2800、U+28FF 为真，对 U+E0D5、U+27FF、U+2900 为假 | Y1：区段表漏了盲文 |
| `TestBrailleDotsFollowTheBits` | 格子 8 × 16、96 PPI：U+2800 无墨；U+28FF 有 8 个互不相连的墨团；对 0–255 每个码位，墨团数 = 位图里 1 的个数，每个墨团的中心落在上游公式算出的点位 ±1 像素 | Y2：点位表的第 7、8 点写反（位 6 / 7 的墨团位置错） |
| `TestPowerlineTrianglesFillHalfTheCell` | U+E0B0（右三角实心）、U+E0B2（左三角实心）在 10 × 20 的格子里：墨的覆盖率之和在格子面积的 45%–55%；两者左右镜像（逐列覆盖率之和互为倒序，±2%） | Y3：`FILL` 画成 `STROKE` |
| `TestPowerlineShapesStayInTheCell` | E0A0–E0D4 每个：遮罩的墨都在格子里（裁剪生效），且有墨（除了上游注释里未用的码位） | Y4：不裁到格子 |

**`TTyTerminalViewPaintTests`**：

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestPowerlineJoinsItsNeighbours` | 写 `ESC[44m text ESC[34;49m`：箭头那一格最左一列的像素 = 蓝色（和左边那格的底色严丝合缝）、最右一列在箭头尖以外 = 终端底色 | Y5：箭头走字体（Consolas 无墨，整格是底色） |

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/gen-terminal-glyphs.js source/tyControls.Terminal.CustomGlyphs.inc source/tyControls.Terminal.Render.pas tests/test.terminal.render.pas tests/test.terminal.view.paint.pas && git commit -m "feat(terminal): powerline symbols and braille are drawn, not taken from the font

The glyph table dumped from xterm.js's WebGL addon now also covers the
powerline range U+E0A0-E0D4 and the braille patterns U+2800-28FF: vector
shapes with quadratic curves and closed paths, filled or stroked and
clipped to the cell, and braille dots placed as upstream places them. A
prompt's arrows now meet the next cell's colour on fonts without them.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 段 5d 编译并跑本段 suite**（主文件「跑测试的固定套路」5d 行；没有 Task 12 就在 Task 11 之后做这一步）。只修本段的红。
