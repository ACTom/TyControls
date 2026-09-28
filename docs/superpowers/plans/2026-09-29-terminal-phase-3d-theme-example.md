# 终端控件 3 期 · 3d 主题、注册、示例、文档（Task 15–19）

> 本文件是 [`2026-09-29-terminal-phase-3.md`](2026-09-29-terminal-phase-3.md) 的附录，执行方式、核实记录、开工前问题、接口清单、地雷都在主文件。先读主文件，尤其是核实记录 3–6（`font-family` 不求值、`:focus`、`on()` 看 Rec.601、换主题只有 `ThemeVersion`）和开工前问题一第 3 条（7 / 15 的取舍）。

**这一批做完能看到什么**：§11 的全部键和 token 写进基础层，三个生成器重跑，17 个主题 × 明暗 16 色都解析得出、深底是 Tango、浅底那套对白底 ≥ 4.5:1；组件面板里有 `TTyTerminalView` 和它的图标，注册驱动的守卫全过；回放示例 `examples/terminal`；控件文档、README、notices。段末编译一次，跑 3a–3d 的 suite。

---

### Task 15: 主题——键、token、浅底 16 色、生成器、守卫

**Files:**
- Create: `tools/terminal-oracle/light-palette.js`
- Modify: `themes/light.tycss`、`source/tyControls.DensityPack.pas`
- Regenerate: `source/tyControls.DefaultTheme.pas`、`source/tyControls.Css.Catalog.pas`
- Modify: `tests/test.themes.pas`、`tests/golden/*.golden.txt`、`tests/test.defaulttheme.pas`
- Create: `tests/test.terminal.view.theme.pas`（suite `TTyTerminalViewThemeTests`）；Modify: `tests/tytests.lpr`

- [ ] **Step 1: 先验生成器忠实度**（动 `light.tycss` 之前，[[gen-defaulttheme-eats-handwritten-code]]）

```bash
cd /d/Projects/ty-3.1 && git checkout HEAD -- themes/light.tycss && powershell -File scripts/gen-defaulttheme.ps1 && git diff --quiet -- source/tyControls.DefaultTheme.pas && echo FAITHFUL
```

Expected：`FAITHFUL`。不是就停下交主控。

- [ ] **Step 2: `light-palette.js`**（Write 工具；开工前问题二第 20 条）

加载上游 `out/common/Color.js` 与 `out/browser/Types.js`（经 `lib-dump.js`）；对 i = 1–6、9–14：`rgba.ensureContrastRatio(0xFFFFFFFF, DEFAULT_ANSI_COLORS[i].rgba, 4.5)`，`undefined` 就原色；0 / 7 / 8 / 15 照 Tango（开工前问题一第 3 条若改成「调」，7 按 3:1 算、15 保持）。打印 `i  Tango  →  浅底值  对白底对比度`；`--check` 时读 `themes/light.tycss`，逐个核 `--terminal-ansi-<i>` 的 `on()` 第二个参数等于算出的值、第三个参数等于 Tango，不等就退出码 1。

写计划时实跑的结果（供核对，执行时以脚本输出为准）：

| i | Tango | 浅底值 | 对白底 |
|---|---|---|---|
| 0 | `#2e3436` | 不变 | 12.65 |
| 1 | `#cc0000` | 不变 | 5.89 |
| 2 | `#4e9a06` | `#3f7c04` | 5.13 |
| 3 | `#c4a000` | `#8e7400` | 4.52 |
| 4 | `#3465a4` | 不变 | 5.93 |
| 5 | `#75507b` | 不变 | 6.58 |
| 6 | `#06989a` | `#047a7c` | 5.15 |
| 7 | `#d3d7cf` | 不变（问题一第 3 条） | 1.4 |
| 8 | `#555753` | 不变 | 7.31 |
| 9 | `#ef2929` | `#d72424` | 5.04 |
| 10 | `#8ae234` | `#50831c` | 4.56 |
| 11 | `#fce94f` | `#756d24` | 5.29 |
| 12 | `#729fcf` | `#517396` | 4.95 |
| 13 | `#ad7fa8` | `#8b6687` | 4.83 |
| 14 | `#34e2e2` | `#1c8383` | 4.54 |
| 15 | `#eeeeec` | 不变（问题一第 3 条） | 1.2 |

（上游算法按 0.9 倍逐步压暗，所以亮色有时比同名的暗色还深，例如 11 比 3 深——截图里一并给用户看。）

- [ ] **Step 3: 写 `light.tycss`**（编辑工具）

1. `:root` 颜色区（放在 `--chart-*` 之类同层 token 附近，带一段注释说明为什么 16 色用三参数 `on()`、深底是 Tango、浅底由 `light-palette.js` 算）：

   ```
   --terminal-bg: var(--surface);
   --terminal-fg: var(--on-surface);
   --terminal-cursor: var(--on-surface);
   --terminal-cursor-ink: var(--terminal-bg);
   --terminal-selection-bg: alpha(var(--accent), 0.35);
   --terminal-selection-bg-inactive: alpha(var(--on-surface), 0.18);
   --terminal-link: var(--accent);
   --terminal-ansi-0: on(var(--terminal-bg), #2e3436, #2e3436);
   --terminal-ansi-1: on(var(--terminal-bg), #cc0000, #cc0000);
   --terminal-ansi-2: on(var(--terminal-bg), #3f7c04, #4e9a06);
   …（16 行，第二个参数是 Step 2 的浅底值、第三个是 Tango）
   --terminal-font-family: monospace;
   --terminal-font-family-wide: monospace-wide;
   --terminal-font-size: var(--font-size-base);
   ```

   `font-family` 两个 token 只给控件用 `RawVar` 读（核实记录 3），不在任何规则里 `var()` 引用。
2. 长度区（`:118` 起的密度段）：`--terminal-pad: 4px;`、`--terminal-cursor-width: 1px;`、`--terminal-underline-width: 1px;`。
3. 规则（放在 `TyMemo` 那组之后）：

   ```
   TyTerminal {
     background: var(--terminal-bg);
     color: var(--terminal-fg);
     font-size: var(--terminal-font-size);
     padding: var(--terminal-pad);
   }
   TyTerminal:disabled { opacity: var(--disabled-opacity); }
   TyTerminalCursor { background: var(--terminal-cursor); color: var(--terminal-cursor-ink); }
   TyTerminalSelection { background: var(--terminal-selection-bg-inactive); }
   TyTerminalSelection:focus { background: var(--terminal-selection-bg); }
   TyTerminalAnsi0 { color: var(--terminal-ansi-0); }
   …（16 行）
   TyTerminalLink { color: var(--terminal-link); }
   TyTerminalPreedit { background: var(--terminal-bg); color: var(--terminal-fg); border-color: var(--accent); }
   ```

   `TyTerminal` 默认无边框（spec §11），所以没有 `:focus` 规则；伪类是 `:focus`（核实记录 4）。选区前景（`TyTerminalSelection` 的 `color`）不写——spec §11「写了才用」。
4. 底色只引用皮肤已定义的 surface token（[[skin-must-define-derived-tokens]]），不写 `darken(--surface, …)`。

- [ ] **Step 4: `DensityPack.pas`**：`TyDensityModernCss` 按字母序插入 `'  --terminal-pad: 8px;' + LineEnding`（另两个长度现代与经典相同，不写；现代取值待真机，进验收表第 3 项一起看）。

- [ ] **Step 5: 重跑生成器**

```bash
cd /d/Projects/ty-3.1 && powershell -File scripts/gen-defaulttheme.ps1 && powershell -File scripts/gen-tycss-catalog.ps1 && node tools/terminal-oracle/light-palette.js --check && git status --short
```

Expected：`DefaultTheme.pas`、`Css.Catalog.pas` 改了；`--check` 通过。不跑 `gen-builtinthemes.ps1`（没动 `auto` / `system` / `builtin/*`，皮肤经基础层继承，[[theme-base-layer-fallback]]）。

- [ ] **Step 6: GGRID / GMETRICS / golden / 内置主题覆盖**

- `tests/test.themes.pas`：GGRID（`:591`，`array[0..222]`）上界 + 21，在 `'TyMemo|'` 附近加 `'TyTerminal|'`、`'TyTerminalCursor|'`、`'TyTerminalSelection|'`、`'TyTerminalAnsi0|'` … `'TyTerminalAnsi15|'`、`'TyTerminalLink|'`、`'TyTerminalPreedit|'`；GMETRICS（`:681`，`array[0..124]`）上界 + 3，按字母序加 `'--terminal-cursor-width'`、`'--terminal-pad'`、`'--terminal-underline-width'`。
- 重铺 golden：跑 `TTestThemeGolden` 得到 `.actual`，**逐个 diff 确认是纯增量**（只多出这 21 个键 × 5 种状态的行和 3 个 metric 行），再覆盖（`test.themes.pas:1191-1222` 的机制）。
- `tests/test.defaulttheme.pas` 的 `TestBuiltinCoversAllTypeKeys` 加 `AssertBg('TyTerminal', [])`、`AssertBg('TyTerminalCursor', [])`、`AssertBg('TyTerminalSelection', [])`、`AssertBg('TyTerminalPreedit', [])`（有底色的四个）。

- [ ] **Step 7: `TTyTerminalViewThemeTests`**（照 `test.themes.pas:242-282` 的循环：`TyRegisterBuiltinThemes`、一个 `TTyStyleController`、`TyBuiltinThemeNames × Mode ∈ {light, dark}`）

| 测试 | 判据 | 在哪个变异下必须红 |
|---|---|---|
| `TestEveryThemeResolvesTheTerminalKeys` | 34 种组合 × 21 个键：`TyTerminal` 有底色与前景、`TyTerminalAnsi<n>` 的 `tpColor in Present`、`TyTerminalCursor` / `TyTerminalSelection` / `TyTerminalPreedit` 有底色、`TyTerminalLink` 有前景；比较次数 = 34 × 21 | T1：删掉 `TyTerminalAnsi5` 规则（重跑生成器） |
| `TestDarkGroundsGetTango` | `--terminal-bg` 解析出的颜色 Rec.601 亮度 ≤ 0.5 的组合：Ansi<n> = Tango[n]；至少有 1 个这样的组合（防空转） | T2：`on()` 两个参数对调 |
| `TestLightGroundsGetTheTunedSet` | 亮度 > 0.5 的组合：Ansi<n> = 浅底值（测试里写死 Step 2 的 16 个值，注释「由 light-palette.js 算出，--check 守着 light.tycss」）；且 i ∈ 1–6、9–14 对白底的 WCAG 对比度（`TyTermRelativeLuminance`）≥ 4.5；另外对「该组合的实际底色」算一遍对比度、`WriteLn` 成表（只记录不断言，给截图验收对照，spec §11） | T3：浅底 3 号改回 `#c4a000` |
| `TestTheTerminalLengthsHaveDensityValues` | 经典：`--terminal-pad` = 4、`--terminal-cursor-width` = 1、`--terminal-underline-width` = 1；现代：`--terminal-pad` = 8 | T4：`DensityPack` 没加 |
| `TestSelectionFollowsFocus` | `ResolveStyle('TyTerminalSelection', '', [tysFocused])` 的底色 ≠ 无状态的底色 | T5：规则写成 `:focused`（解析器不认，聚焦态落回无状态） |
| `TestTheFontTokensAreReadRaw` | `Model.RawVar('--terminal-font-family') = 'monospace'`、`'--terminal-font-family-wide'` = `'monospace-wide'`；`ResolveStyle('TyTerminal')` 的 `tpFontName` 不在 `Present`（没有规则写 `font-family`） | T6：规则里写了 `font-family: var(--terminal-font-family)`（字体名会变成那串字） |

- [ ] **Step 8: 提交**

```bash
cd /d/Projects/ty-3.1 && git add themes/light.tycss source/tyControls.DefaultTheme.pas source/tyControls.Css.Catalog.pas source/tyControls.DensityPack.pas tools/terminal-oracle/light-palette.js tests/ && git commit -m "feat(terminal): theme keys, tokens and a light-ground 16-colour set

The terminal's colours are tokens in the base layer, so every built-in
skin and both modes inherit them. Each of the sixteen is written once as
on(background, light-ground value, dark-ground value): dark grounds get
xterm.js's Tango colours, light grounds get the same hues darkened with
xterm.js's own contrast routine until they reach 4.5:1 on white (black,
white and their bright forms left alone). The font family is a token the
control reads raw, with monospace standing for the platform's
fixed-pitch face.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: 面板注册与图标，注册驱动的守卫

**Files:**
- Modify: `designtime/tyControls.Design.pas`（`'TyControls Edits'` 组，`:143-146`，`TTyMemo` 之后；uses 加 `tyControls.Terminal`）
- Modify: `tools/genicons/genicons.lpr`（`GTerminal` 绘制过程 + `Glyphs` 表一项、上界 + 1，`:946`）、`scripts/gen-icons.ps1`（`$classes`，`:9-56`）
- Generate【主控执行】: `designtime/icons/TTyTerminalView.png`、`_150.png`、`_200.png`、`designtime/tycontrols_icons.lrs`
- Modify: `tests/test.version.pas`（`Reg()` 块与 uses）、`tests/test.focus.tabstop.pas`（TabStop 表）

- [ ] **Step 1: 注册**：`RegisterComponents('TyControls Edits', [..., TTyMemo, TTyTerminalView, TTySpinEdit, ...])`。

- [ ] **Step 2: 图标**：`GTerminal(b: TBGRABitmap)` 照 `GMemo`（`genicons.lpr:248`）的 24 格网格：圆角窗框 + 顶部一条标题栏 + 左上 `>_` 提示符（`>` 两笔折线、`_` 一横）+ 两行短横当输出。颜色用 genicons 已有的调色常量，不另起。

- [ ] **Step 3: 【主控执行】生成图标**：`powershell -File scripts/gen-icons.ps1`（它会校验图标集与每个 `RegisterComponents` 组对得上），`git status` 只多出三张 PNG 和 `.lrs` 的改动。

- [ ] **Step 4: 守卫表**

- `test.version.pas` 的 `Reg()` 块加 `TTyTerminalView`（uses 加 `tyControls.Terminal`），否则 `TestEveryRegisteredNameResolves` 红（核实记录 17）。
- `test.focus.tabstop.pas` 的 TabStop 表（`:215-240`）在「value pickers and data controls, each of which handles its own keys」那一行加 `TTyTerminalView`，旁注「终端自己吞 Tab，焦点只经鼠标或宿主放行的键离开，spec §9.4」。
- `test.dpi.measurefont.pas`、`test.paletteicons.pas`、`test.designregistry.pas` 不用改，按注册表自动取；它们红了说明控件本身的 DPI 或注册有问题，修控件。

- [ ] **Step 5: 提交**（不编译；PNG / `.lrs` 等主控生成后由主控 `git add` 进同一个或紧接着的提交）

```bash
cd /d/Projects/ty-3.1 && git add designtime/tyControls.Design.pas tools/genicons/genicons.lpr scripts/gen-icons.ps1 tests/test.version.pas tests/test.focus.tabstop.pas && git commit -m "feat(terminal): TTyTerminalView on the Edits palette page, next to the memo

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

主控生成图标后：

```bash
cd /d/Projects/ty-3.1 && git add designtime/icons/TTyTerminalView*.png designtime/tycontrols_icons.lrs && git commit -m "chore(terminal): palette icon for TTyTerminalView

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异表（期末做）：**

| # | 变异 | 必须红 |
|---|---|---|
| T7 | `Reg()` 块删掉 `TTyTerminalView` | `TestEveryRegisteredNameResolves` |
| T8 | 构造里 `TabStop := False` | `TestPublishedDefaultAgreesWithTheConstructedValue`、`TestControlsThatActOnInputAreTabStops` |

---

### Task 17: 回放示例 `examples/terminal`

**Files:**
- Create: `examples/terminal/terminal_example.lpi`、`terminal_example.lpr`、`terminal_example.ico`（拷 `examples/memo/memo_example.ico`）、`umain.pas`、`umain.lfm`、`uasciicast.pas`
- Create: `examples/terminal/recordings/*.cast`（2 期的 8 份原样拷贝 + 新写的 `palette.cast`）
- Create: `examples/terminal/languages/terminal_example.zh_CN.po`、`examples/terminal/languages/tycontrols.zh_CN.po`（拷 `examples/memo/languages/tycontrols.zh_CN.po`）
- Modify: `tests/test.release.pas`（录制一致的守卫，开工前问题二第 11 条）

照示例规矩（地雷 18）：`.lpi` 照 `examples/memo/memo_example.lpi`（含 i18n 段 `:18-21`）；`.lpr` 照 `memo_example.lpr:25-40`（`SetDefaultLang`、`TranslateUnitResourceStringsEx`）；窗体 `TMainForm = class(TTyForm)`、真 `TTyTitleBar`（`.lfm` 里 `TitleBar = Bar`，[[lfm-titlebar-must-be-associated]]）；换肤 / 明暗照 `examples/memo/umain.pas:98-130`（`TyRegisterBuiltinThemes`、主题下拉、暗色开关、`ApplyChromeTheme`）；所有能写进 `.lfm` 的设置都写进 `.lfm`；只用库里的控件（按钮 `AutoSize`）。

- [ ] **Step 1: `uasciicast.pas`**（示例私有，不进包）

- `TAsciicastEvent = record Time: Double; Data: RawByteString; end`；`TAsciicast = class`：`LoadFromFile(AFile)`、`Width`、`Height`、`Count`、`Events[i]`。
- 第一行 JSON 头：`version` 必须是 2（否则抛带文件名的 `Exception`，示例里弹库的消息框）、`width`、`height`；之后每行 `[时间, 类型, 数据]`，只收 `"o"`，`"i"` / 其他忽略；空行跳过。`fpjson` 解析，数据串取 UTF-8。
- 已知限制写进单元注释：`fpjson` 会吞 `\u0000`（[[fpjson-drops-u0000]]），这类事件的 NUL 会丢；8 份录制里没有（Step 3 的守卫顺带查）。

- [ ] **Step 2: `umain.lfm` / `umain.pas`**

布局（从上到下）：标题栏；工具条（`TTyPanel` 顶对齐，里面一排库控件）：录制下拉（列出 `recordings/*.cast`）、打开…（`TTyOpenDialog`）、播放 / 暂停（切换按钮）、单步、速度下拉（0.5×、1×、2×、4×、一次喂完）、按录制尺寸、主题下拉、暗色开关；第二排：只读开关（默认开）、本地回显开关（默认关）、Unicode 版本下拉（6 / 11 / 15 / 15-graphemes，默认 11）、Ambiguous 宽开关、字号微调；主体：终端 `alClient`；右侧键码面板（`TTyMemo` 只读 + `TTySplitter`）；底部状态栏：事件进度（`i / n`、当前时间）、网格尺寸、标题。

行为：
- 选录制 / 打开 → `Term.Reset`、`Term.Clear`、载入、停在开头；状态栏显示录制的宽高。
- 播放：`TTimer`（15ms）；已播时长 = 真实流逝 × 速度（`TyTermDefaultClock`）；把 `Time × 1000 ≤ 已播` 的事件都 `Term.Write`；「一次喂完」直接把剩余全写；播完自动停。暂停停计时器；单步写下一个事件（暂停状态下）。
- 按录制尺寸：`sz := Term.SizeForGrid(cast.Width, cast.Height)`，窗体按差值放大 / 缩小（传算好的新尺寸，地雷 17）。
- `Term.OnData`：键码面板追加一行 `十六进制  可读形式`（`1B 5B 41  ESC [ A`）；本地回显开着就 `Term.Write(AData)`。
- `Term.OnTitleChange` → 状态栏；`Term.OnGridResize` → 状态栏。
- 只读开关 ↔ `Term.ReadOnly`（开着时键码面板提示「关掉只读才能看按键字节」）。
- 窗体 `OnCreate` 里把焦点给终端。
- 示例自己的字符串全用 `resourcestring`（[[example-content-two-purposes]]：示例教用法——宿主怎么接 `Write` / `OnData` / `OnGridResize`，注释写清 4 期会在这里接 PTY）。

- [ ] **Step 3: 录制**：把 `tools/terminal-oracle/recordings/*.cast` 8 份原样拷进 `examples/terminal/recordings/`（二进制拷贝，别经编辑器转行尾）；新写 `palette.cast`（Write 工具，LF）：头 `{"version": 2, "width": 80, "height": 24}`，一个事件打出 0–15 前景各一格 `████`（`ESC[38;5;<n>m`）+ 编号、0–15 底色各一格、粗体 / 暗淡 / 斜体 / 五种下划线 / 删除线 / 反显各一词、一段 `┌──┬──┐` 框线和 `▀▄█░▒▓`。
  `test.release.pas` 加 `TheExampleRecordingsMatchTheOracle`：8 个同名文件在两处字节相同；示例目录里的 `.cast` 都能被当 asciicast v2 头解析（第一行含 `"version": 2`）；任何一份不含 `\u0000`。变异 T9：示例里的 `vim-edit.cast` 改一个字节 → 红。

- [ ] **Step 4: 译文**：`terminal_example.zh_CN.po` 照 `examples/memo/languages/memo_example.zh_CN.po` 的格式手写两段——`.lfm` 的标题 / 文字 / 提示（`#: tmainform.<控件>.caption`）和 `resourcestring`（`#: umain.<标识>`）；中文用原生语感（[[doc-writing-native-tone]]）；同一份译文另存成 json（Task 20 主控跑 `example-rsj2po.py` 用，放草稿，不进 git）。英文标题按中文宽度留足、或 `AutoSize`（[[example-english-caption-fit]]，`test.englishfit` / `test.skinfit` 会扫）。

- [ ] **Step 5: 检查**（实现 agent 可做的部分）：`python scripts/check-lfm-props.py examples/terminal/umain.lfm`；`python scripts/check-example-po.py examples/terminal`（参数照脚本头说明）。**不编示例**（Task 20 Step 5 主控编、生成 `.po`、冒烟、截图）。

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add examples/terminal tests/test.release.pas && git commit -m "feat(examples): terminal replay -- asciicast playback with skins and a key panel

Plays the recordings at their own pace, faster, all at once or one event
at a time, resizes the window to the recording's grid, and switches skin
and light/dark while playing. With read-only off, every key's bytes show
in a side panel, and local echo writes them back into the terminal. The
eight recordings are the oracle's own, and a release test keeps the two
copies identical.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 18: 控件文档与 README

**Files:**
- Create: `docs/controls/terminal.md`
- Modify: `docs/controls/README.md`（`TTyMemo` 那行之后，`:73`）、`README.md`、`README.en.md`

中文原生语感、不写小作文（[[doc-writing-native-tone]]）；结构照 `docs/controls/memo.md`：

1. **概述**：终端做什么、不做什么（不碰进程；宿主管 PTY——4 期示例演示）；最小接法三行（`Write` 喂字节、`OnData` 写回 PTY、`OnGridResize` 改 PTY 尺寸）。
2. **单元与 typeKey**：`tyControls.Terminal`；另有 `tyControls.Terminal.Core`（`Core` 属性）、`.Keyboard`、`.Render`；typeKey 列表。
3. **属性表**：published（本期全部，类型、默认、说明，哪些转给 Core）、public（`Core`、`Cols`、`Rows`、`Title`）、方法、继承的通用成员；事件表。
4. **数据流与线程**：`Write` 只入队、按片在消息循环里处理、回调表示「前面的都处理完了」；只许主线程调用（否则 `EInvalidOperation`）；积压 50MB 抛 `ETyTerminalWriteOverflow`；事件同步发、在解析中间，事件里调 `Resize` / `Reset` / `WriteSync` 会延后到这一块处理完。
5. **键盘**：终端吞哪些键、`OnShortcutQuery` 放行（示例代码：放行 Ctrl+Tab）、复制粘贴快捷键表（三个平台）、Ctrl+C 永远发给程序、本地翻页、Alt 前缀与 macOS `MacOptionIsMeta`、AltGr 出字符；应用小键盘模式不影响小键盘（照 xterm.js，开工前问题一第 1 条的结论）。
6. **滚回与滚动条**：`Scrollback`、条宽总是留着（列数不随主屏 / 备用屏变）、滚轮三种去向、`AlternateScroll`。
7. **状态与主题**：各 typeKey 与 token 表；16 色 `on()` 的写法与深底 / 浅底两套的来历；字体 token `monospace` / `monospace-wide` 与各平台映射；「StyleOverride > 显式 Font > 主题」；light.tycss 示例规则。
8. **代码示例**：回放（读一份 `.cast` 按时间 `Write`）；宿主接 PTY 的骨架（伪 PTY 接口，注明 4 期示例有真实现）；放行快捷键。
9. **注意事项**：
   - **Unicode 版本**：默认 11；要字形簇（emoji 修饰、ZWJ 序列）选 `15-graphemes`；**`15` 不连接组合符**：`e` + U+0301 在 `15` 下占 2 格（组合符自占一格），`6` / `11` / `15-graphemes` 下占 1 格（1 期遗留）。
   - **`AmbiguousWide` 只对 `15` / `15-graphemes` 起作用**；打开后 U+0301 这类在表里本身是 ambiguous 的组合符也算宽：`é`（e + U+0301）在 `15` 下占 **3** 格、在 `15-graphemes` 下占 **2** 格（1 期遗留，照上游）。
   - 控件接管的 Core 事件清单，宿主别改写；可以自己挂的是 `OnIconNameChange`、`OnLineFeed`，或 `Core.Parser.Register*Handler`。
   - REP（`CSI b`）重复次数极大时按周期快进，被跳过那段的 `Core.OnScroll` 不发（2 期遗留）。
   - 窗口尺寸应答（14t / 16t）与 SGR 像素鼠标报设备像素（xterm.js 报 CSS 像素）。
   - 表情：按 Task 0 E1 的结论写（例如「Windows 上彩色表情画成单色轮廓」）。
   - 颜色 token 丢 alpha。
10. **本期限制 / 后续**：鼠标上报与本地选择、右键菜单、Linux PRIMARY、OSC 52、链接（4 期）；拖窗口时长行不重新折行（5 期）；最低对比度（5 期）。

README（两份同步改，[[pre-merge-checklist]]）：「168 个控件 / 168 controls」三处 → 169；`TyControls Edits(14)` → 15；`TTyMemo` 行之后加一行（中：「`TTyTerminalView` | 终端：画程序输出、把按键编码交给宿主，照 xterm.js」；英文对应）；示例表加 `terminal` 一行（中：「终端回放：asciicast 录制、换肤、键码面板」）。`docs/controls/README.md` 加 `| [TTyTerminalView](terminal.md) | 终端：解析 + 缓冲 + 渲染，照 xterm.js；PTY 归宿主 |`。

- [ ] **Step 1: 写文档、改索引与 README**
- [ ] **Step 2: 提交**

```bash
cd /d/Projects/ty-3.1 && git add docs/controls/terminal.md docs/controls/README.md README.md README.en.md && git commit -m "docs(terminal): control reference and README entries

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异表（期末做）：**

| # | 变异 | 必须红 |
|---|---|---|
| T10 | `docs/controls/README.md` 删掉终端那一行 | `TheControlDocsIndexLinksEveryPageAndOnlyRealOnes` |

---

### Task 19: 许可与署名，段 3d 编译

**Files:**
- Modify: `THIRD-PARTY-NOTICES.md`（`:73` 的 `## xterm.js` 标题行）、`tests/test.release.pas`（`TheThirdPartyNoticeCoversTheTerminalPort`，`:570-599`）

- [ ] **Step 1: notices**：标题行追加 `` `source/tyControls.Terminal.Keyboard.pas` ``、`` `source/tyControls.Terminal.Render.pas` ``、`` `source/tyControls.Terminal.CustomGlyphs.inc` ``；正文「用了哪些单元要带」那一句覆盖新单元；版权行核对：`Keyboard.ts` 的 2014 年行与 `CustomGlyphRasterizer.ts` / `CustomGlyphDefinitions.ts` 的 2021 年行都是「The xterm.js authors」，已被仓库 `LICENSE` 的「2014-2026, The xterm.js authors」覆盖；addon-webgl 的 `LICENSE:1`「Copyright (c) 2018, The xterm.js authors」同理——结论写成一句「版权人同上」，不新增行（执行时逐文件核头部，出现新的版权人就加一行）。控件单元 `tyControls.Terminal.pas` 是自己写的（逻辑参照、没有移植代码），不进标题；它的单元头已写参照来源。
- [ ] **Step 2: 守卫**：`Units` 数组（`array[0..6]`）加三项（上界 → 9），注释补一句「3 期：键盘移植、渲染部件（颜色解析与自绘字形照 xterm.js）、从 addon-webgl dump 的字形表」。变异 T11：标题行删掉 `Render` → 红。
- [ ] **Step 3: 核对四个新文件的单元头**（Task 2、4、5、7 写的）：移植的写「移植自 xterm.js 6.0.0（commit 前 12 位）+ 源文件路径 + 版权行 + MIT，全文见 THIRD-PARTY-NOTICES.md」；参照的写「逻辑参照 xterm.js 的 …（行号）」。缺的补上。
- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add THIRD-PARTY-NOTICES.md tests/test.release.pas && git commit -m "docs(terminal): notices cover the keyboard port, the renderer and the glyph table

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: 段 3d 编译并跑本段 suite**（主文件「跑测试的固定套路」3d 行；图标还没由主控生成时，`TPaletteIconTest` 的红是预期的——记下，Task 20 主控生成后再跑）。只修本段的红。
