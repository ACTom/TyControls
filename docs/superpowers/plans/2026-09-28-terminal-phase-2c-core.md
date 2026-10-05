# 终端控件 2 期 · 2c 核心（Task 10–18）

> 本文件是 [`2026-09-28-terminal-phase-2.md`](2026-09-28-terminal-phase-2.md) 的附录，执行方式、核实记录、开工前问题、接口清单、夹具格式、比较器判据、地雷都在主文件。先读主文件。

**这一批做完能看到什么**：几百个用例——手写 vttest 风格、上游 79 个序列文件、整块与逐字节 / 随机切块、坏序列与超长输入、种子化随机字节、颜色 / 明暗 / 焦点应答、鼠标编码、真实程序录制——喂进 `TTyTerminalCore` 后，两块缓冲的每一格三字、组合与扩展、光标、边距、制表位、保存的光标、模式、字符集、标题、应答字节、响铃 / 换行 / 光标移动 / 重画区间 / 滚动事件、OSC 8 链接表都和 xterm.js 6.0.0 逐位相同；同一个 Core 复位后重跑，结果和 node 复位后重跑相同。

---

### Task 10: `gen-terminal-charsets.js` → `source/tyControls.Terminal.Charsets.inc`

**Files:**
- Create: `tools/terminal-oracle/gen-terminal-charsets.js`
- Create (generated): `source/tyControls.Terminal.Charsets.inc`

- [ ] **Step 1: 写脚本**（Write 工具）

要求：

1. 头部注释照 1 期 `gen-unicode-tables.js`：生成什么、为什么 dump 而不手抄（开工前问题二第 21 条）、怎么跑、生成物头部不写时间和本机路径。
2. 经 `lib-dump.js` 加载 `out/common/data/Charsets.js` 的 `CHARSETS`、`DEFAULT_CHARSET`。
3. 按 `for (const key in CHARSETS)` 的顺序（就是 `InputHandler` 注册 ESC 处理器的顺序，`InputHandler.ts:354-362`）列出键；按**对象同一性**给每张表编号（别名共享一个编号，`undefined` 的 `B` 编号 0），编号按第一次出现的顺序从 1 起。
4. 断言：每个键是单个字符；每张表的键都是单个字符、落在 `0x20`–`0x7E`；每个值的 `charCodeAt(0)` 在 BMP 内（`print` 只取第一个单元，`InputHandler.ts:552-557`）。不满足就中止并打印——说明 `print` 的移植要改。
5. 写 `.inc`（`L.writeGenerated`），头部格式同 `Unicode.Width.Data.inc`（上游版本、完整 commit、提交日期、MIT 出处；断言头部没有花括号）：

   ```
   const
     TyTermCharsetCount = <表数>;
     TyTermCharsetKeys: array[0..K-1] of Char = ('0', 'A', 'B', ...);          { for...in order }
     TyTermCharsetOfKey: array[0..K-1] of Byte = (1, 2, 0, ...);               { 0 = none (B) }
     TyTermCharsetMap: array[1..TyTermCharsetCount, $20..$7E] of Word = (...);  { 0 = unmapped }
   ```

6. `lib-dump.js` 的 `GENERATED` 已在 Task 1 登记这个路径。

- [ ] **Step 2: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/gen-terminal-charsets.js && head -30 source/tyControls.Terminal.Charsets.inc && node tools/terminal-oracle/gen-terminal-charsets.js > /dev/null && git status --short
```

Expected：键 16 个（`0 A B 4 C 5 R Q K Y E 6 Z H 7 =`，以实际 `for...in` 顺序为准）、表 12 张（三对别名）；`'0'` 表里 `'q'` 映射到 `$2500`（`─`）；两次输出相同。

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/gen-terminal-charsets.js source/tyControls.Terminal.Charsets.inc && git commit -m "feat(terminal): character set tables dumped from xterm.js

The DEC special graphics and national replacement sets, written as an
include in xterm.js's registration order with aliases sharing one table,
so the port's designations and the tables cannot drift apart.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: `core-cases.js` → 手写、长输入、合成应答、鼠标编码四类夹具

**Files:**
- Create: `tools/terminal-oracle/cases/core-hand.js`（只有输入）
- Create: `tools/terminal-oracle/core-cases.js`
- Create (generated): `tests/fixtures/terminal-core-hand*.json`、`terminal-core-long*.json`、`terminal-core-synth*.json`、`terminal-core-mouse*.json`

- [ ] **Step 1: 写 `cases/core-hand.js`**（Write 工具）

导出 `{ hand, long, synth, palette, mouse }`。用例写法：`{ id, cols?, rows?, options?, steps }`，步骤里的 `write` 可以写 `s: "..."`（JS 字符串，生成器按 UTF-8 编码）；缺省 `cols 20, rows 6`。**每条用例写一行注释说它守的是上游哪一行**（审查时核）。至少这些（行号都是 `InputHandler.ts`，另注的除外）：

**打印与字符集**

| id | 要点 | 守的是 |
|---|---|---|
| `print-ascii`、`print-wrap-pending`（打满一行后 `x = cols`）、`print-wrap-next`（再打一个：折行、下一行 `isWrapped`）、`print-nowrap`（`?7l` 后打超：覆盖最后一格） | `print` `:517-661` 的主干 | |
| `print-wide-edge`（宽字符落在最后一格：留空格、折行）、`print-wide-nowrap`（`?7l` 下宽字符在最后一格：跳过，`:611-617`）、`print-over-wide-half`（在宽字符第二半上打：左半清掉，`:537-539`）、`print-wide-right-reset`（打完后右边是孤立第二半：清掉，`:652-655`） | 宽字符 | |
| `combine-at-line-start`（`x = 0` 时的组合符）、`combine-after-wide`、`combine-across-wrap`（`15-graphemes` 下 VS16 把最后一格的字符撑宽 → 整个字符搬到下一行，`:596-601`）、`combine-width-grow`（组合后宽度 1 → 2，`:627-629`）、`soft-hyphen`（U+00AD 被跳过，`:546-548`） | 组合 | |
| `insert-mode`（`CSI 4 h` 后打字：右移；宽字符挤到最后一格被清，`:632-642`）、`insert-mode-reset`（`CSI 4 l`） | IRM | |
| `charset-dec-graphics`（`ESC ( 0` + `lqkxjm` + `ESC ( B`）、`charset-each-<key>`（16 个键各一条：设为 G0 后打印 `0x20`–`0x7E` 全部）、`charset-so-si`（`ESC ) 0` + `SO` + `q` + `SI` + `q`）、`charset-ls2-ls3`（`ESC * 0` + `ESC n`、`ESC + A` + `ESC o`、`ESC |`、`ESC }`、`ESC ~`）、`charset-slash`（`ESC / A`：无效果）、`charset-default`（`ESC % G`、`ESC % @`）、`charset-decset2`（`CSI ? 2 h` 把四个 G 都设回默认）、`charset-saved`（`ESC ) 0` `SO` `ESC 7` `SI` `ESC ( A` `ESC 8` 后打印） | 字符集 `:3323-3360`、`:1939-1945`、`:2994-3029` | |
| `unicode-<v>`（6 个变体各一条：`é`、`e`+U+0301、`中`、😀、🇨🇳、👨‍👩‍👧、U+2026、`☺`+VS16，在 `cols = 8` 下打到折行） | 打印路径和 1 期宽度表的衔接 | |

**控制字符**

| id | 要点 |
|---|---|
| `bel-count`（三个 BEL） | `:727-730` |
| `bs-basic`、`bs-at-0`、`bs-pending-wrap`（`x = cols` 时 BS：先钳到 `cols - 1`） | `:793-806` |
| `bs-reverse-wrap`（`?45h`，行首 BS 回到上一折行末尾；上一行末尾是「宽字符提前折行留下的空格」时再退一格，`:822-843`）、`bs-reverse-not-wrapped`（上一行不是折行：不动）、`bs-reverse-at-top-margin` | 反向折行 |
| `ht-default`、`ht-at-end`（`x >= cols`：不动，`:850-853`）、`ht-after-tbc` | `:850-860` |
| `lf-basic`、`lf-clears-wrapped`（LF 到一个已折行的行：清 `isWrapped`，`:757-764`）、`lf-pending-wrap`（`x = cols` 时 LF：`x--`）、`vt-ff`（`0x0B`、`0x0C` 同 LF）、`lf-converteol`（`convertEol: true`）、`lnm`（`CSI 20 h` 打开、`CSI 20 l` 关闭；终值 `options.convertEol`） | `:742-771`、`:1804-1816` |
| `cr`、`c1-ind-nel-hts`（UTF-8 的 `C2 84`、`C2 85`、`C2 88`） | `:777-780`、`:3287-3395` |

**光标**

| id | 要点 |
|---|---|
| `cuu-cud-cuf-cub`（缺省、0、2、超界）、`cuu-stop-at-margin`（在边距内 / 外两种）、`cnl-cpl`、`cha-hpa`、`cup`（0、1、2 个参数、超界）、`hvp`、`vpa-vpr-hpr` | `:930-1097` |
| `cursor-huge-params`（每个移动序列都带 20 位参数：钳到边缘，地雷 3） | `_moveCursor` / `_setCursor` 的整数宽度 |
| `origin-mode`（`CSI 3;5 r` + `?6h` + `CUP`：相对上边距、钳在区域内；`?6l` 回原点） | `:889-921`、`:1972-1975` |
| `decsc-decrc`（`ESC 7` / `ESC 8`、`CSI s` / `CSI u`，含属性、原点模式、折行模式）、`decrc-without-save`（没存过就恢复：`savedY` 相对 `ybase`、下限 0） | `:2994-3029` |

**擦除、插删、滚动**

| id | 要点 |
|---|---|
| `ed-0/1/2/3`、`ed-2-scroll-on-erase`（`scrollOnEraseInDisplay: true`：把非空行推进滚回，`:1260-1272`）、`ed-3-scrollback`（滚回清掉、`ybase` / `ydisp` 归位）、`ed-pending-wrap`（`x = cols` 时 ED 0：`_restrictCursor(cols)`）、`ed-1-wraps`（ED 1 删到行尾时清下一行 `isWrapped`，`:1247-1253`） | `:1229-1305` |
| `el-0/1/2`、`el-clears-wrapped`（EL 0 在 `x = 0`、EL 2：清 `isWrapped`）、`decsca-decsel-decsed`（`CSI 1 " q` 保护后 `CSI ? K` / `CSI ? J` 跳过受保护格；`CSI 2 " q` / `CSI 0 " q` 取消） | `:1324-1340`、`:1158-1163` |
| `ech`（缺省、3、20 位参数：擦到行尾，核实记录 4）、`bce`（背景色下擦除：只带背景，`_eraseAttrData` `:3441-3445`） | `:1614-1626` |
| `ich-dch`（宽字符边界）、`il-dl`（区域内 / 区域外无效）、`il-dl-1000`（参数 1000：钳制等价，开工前问题二第 12 条）、`su-sd`、`su-sd-1000`、`sd-default-attr`（SD 插入的空行用默认属性而不是擦除属性，`:1489`）、`sl-sr`（`CSI 2 SP @`、`CSI 2 SP A`；光标在区域外无效）、`decic-decdc`（`CSI 2 ' }`、`CSI 2 ' ~`） | `:1350-1604` |
| `cht-cbt`（缺省、3、1000）、`cht-at-end` | `:1125-1150` |
| `rep-ascii`、`rep-wide`、`rep-grapheme`（`15-graphemes` 下 👨‍👩‍👧 再 REP 2）、`rep-after-control`（`\r` 之后 REP：无效）、`rep-zero`（`CSI 0 b` = 1）、`rep-wrap`、`rep-cap`（`a` + `CSI 1048576 b`，40 × 6、`scrollback 20`：恰好等于上限，开工前问题二第 11 条） | `:1654-1678` |
| `decaln`（`ESC # 8`，带颜色属性、清 `isWrapped`、光标归位） | `:3470-3494` |
| `ri-top-margin`（`ESC M` 在上边距：区域下移）、`ri-mid`、`ind-bottom`（`ESC D`）、`nel` | `:3366-3419` |

**滚动区域与滚回**

| id | 要点 |
|---|---|
| `decstbm-valid/invalid`（`bottom > rows`、`bottom = 0`、`top >= bottom` 忽略；设置后光标归位） | `:2890-2905` |
| `lf-in-region`（`scrollTop > 0`：区域内平移、不进滚回）、`lf-region-top-0`（进滚回）、`scrollback-full`（`scrollback 3` 下滚 20 行：`ybase` 停在 3）、`user-scrolled-output`（`scrollLines -2` 后输出：视口不动）、`user-scrolled-full`（滚回满时视口上移一行） | `BufferService.scroll` |
| `scroll-steps`（`scrollLines` / `scrollToTop` / `scrollToBottom` 步骤）、`input-scrolls-to-bottom`（视口在上方时 `input user: true`：回底；`user: false` 不回；`scrollOnUserInput: false` 不回）、`input-disabled`（`disableStdin`：`input` 不发数据）、`clear-step`（有滚回时 `clear`：光标行成为第 0 行） | `CoreService.ts:74-95`、headless `Terminal.ts:101-112` |

**制表位**

| id | 要点 |
|---|---|
| `tbc-0-3`、`hts`、`hts-pending-wrap`（`x = cols` 时 HTS：键等于 cols，导出里有它）、`tabs-width-4`（`setOption tabStopWidth 4`） | `:1109-1119`、`:3389-3392` |

**模式与查询**

| id | 要点 |
|---|---|
| `decset-each`（`?1 ?6 ?7 ?12 ?25 ?45 ?66 ?1004 ?2004 ?2026 ?2031 ?9001` 逐个开、看 `modes`，再逐个关） | `:1932-2071`、`:2198-2317` |
| `decset-12-quirk`（`allowSetCursorBlink: true` 时 `?12h` 改 `options.cursorBlink`） | `:1963-1967` |
| `decset-2031-disabled`（`vtExtensions.colorSchemeQuery: false`：不置位）、`decset-9001-enabled`（`win32InputMode: true` 才置位） | |
| `decset-3-no-winlines`（没开 `setWinLines`：无效）、`decset-3-winlines`（`windowOptions: [setWinLines]`、`windowsPty {conpty, 19044}`：列变 132 并触发复位；开工前问题二第 24 条） | `:1945-1955` |
| `alt-47/1047/1049`（进出备用屏：光标拷贝、1049 存取光标、切回时备用屏清空、`isCursorInitialized`、重画整屏的 `renders` 项）、`alt-1048`、`alt-ed3`（备用屏上 ED 3：不动 `isUserScrolling`） | `:2019-2031`、`:2268-2283` |
| `mouse-modes`（`?9 ?1000 ?1002 ?1003` 互斥、`?1006 ?1016` 编码、`?1005 ?1015` 无效、`?1000l` 关协议） | `:1976-2009` |
| `decrqm-ansi`（`CSI 2/4/12/20/99 $ p`，含 IRM、LNM 开关前后）、`decrqm-private`（`CSI ? <m> $ p` 对 1 3 6 7 8 9 12 25 45 47 66 67 1000 1002 1003 1004 1005 1006 1015 1016 1047 1048 1049 2004 2026 9001 9999，开关前后各问一次） | `:2336-2396` |
| `kitty-off`（`CSI = 1 u`、`CSI ? u`、`CSI > 1 u`、`CSI < u`：扩展关，全无效、无应答）、`kitty-on`（`vtExtensions.kittyKeyboard: true`：三种设置模式、推入超 16 挤掉最老、弹出、空栈归 0、`?u` 应答、1049 进出时主备标志互换） | `:3552-3651`、`:2020-2025` |

**SGR**

| id | 要点 |
|---|---|
| `sgr-flags`（1–9、21–29、53、55 逐个开关）、`sgr-16`（30–37、40–47、90–97、100–107、39、49）、`sgr-zero-fast`（`CSI m`、`CSI 0 m`、`CSI 0;0 m`）、`sgr-bold-faint-kitty`（221、222；扩展关时无效） | `:2600-2725` |
| `sgr-256-semicolon`（`38;5;n`、`48;5;n`、`58;5;n`）、`sgr-256-colon`（`38:5:n`）、`sgr-rgb-semicolon`（`38;2;r;g;b`）、`sgr-rgb-colon`（`38:2::r:g:b`、`38:2:r:g:b`——色空间槽的两种写法）、`sgr-color-truncated`（`38;5`、`38;2;1;2`、`38:2`）、`sgr-color-then-more`（`38;5;1;1`：后面的 1 是粗体） | `_extractColor` `:2416-2475` |
| `sgr-underline-styles`（`4:0`–`4:5`、`4:9`、`4:`、`21`、`24`、`58`、`59`，核实记录 7）、`sgr-underline-with-link`（OSC 8 下的下划线样式强制 DASHED） | `:2485-2513` |
| `sgr-33-params`（34 个参数：第 33 个起丢弃） | Params 上限 |

**应答**

| id | 要点 |
|---|---|
| `da1`（`CSI c`、`CSI 0 c`、`CSI 1 c` 无应答）、`da2`（`CSI > c`）、`xtversion`（`CSI > q`，归一化）、`dsr`（`CSI 5 n`、`CSI 6 n`、`CSI ? 6 n`、`CSI ? 15/25/26/53 n` 无应答） | `:1706-1777`、`:2743-2795` |
| `decrqss`（`DCS $ q " q`、`" p`、`r`、`m`、` q`、`x` 无效；在 `cursorStyle: "bar", cursorBlink: true` 与缺省两种选项下各一条）、`decrqss-protected`（`CSI 1 " q` 之后问 `" q`）、`decrqss-params-ignored`（`DCS 1 $ q m ST`） | `:3519-3537` |
| `xtwinops-off`（缺省：`CSI 18 t`、`22 t`、`23 t` 都无效）、`xtwinops-18`（`windowOptions: [getWinSizeChars]`）、`xtwinops-title-stack`（`[pushTitle, popTitle]`：推 12 次、上限 10、弹出恢复标题与图标名；`22;1`、`22;2` 分开推） | `:2936-2983` |
| `replies-disabled`（`disableStdin: true`：DA1 / DSR / DECRQM 都不发） | `CoreService.ts:76-78` |

**OSC**

| id | 要点 |
|---|---|
| `osc-titles`（0 / 1 / 2，BEL 与 ST 两种结尾，空标题）、`osc-unknown`（7、133、1337：无效果；我们的 `OnOsc` 另在 Task 18 纯测） | `:286-325`、`:3042-3055` |
| `osc8-basic`（`OSC 8;;uri` … `OSC 8;;`）、`osc8-id`（`id=x:foo=bar`、`id=` 空值）、`osc8-reopen`（不关直接开新的）、`osc8-malformed`（没有分号）、`osc8-id-no-uri`（`8;id=x;`：处理器返回 false，无效果）、`osc8-trim`（id 两边空格）、`osc8-wrap`（链接跨折行：`addLineToLink`）、`osc8-reuse`（同 id + uri 两次：同一个链接号）、`osc8-scrolled-out`（`scrollback 2` 下链接行被挤出：条目消失） | `:3109-3150`、`OscLinkService.ts` |

**复位**

| id | 要点 |
|---|---|
| `decstr`（设一堆状态后 `CSI ! p`：光标显示、边距、属性、IRM、字符集、保存的光标、原点模式复位；标题、制表位、滚回不动） | `:2816-2835` |
| `ris`（同样一堆状态后 `ESC c`：全部复位，**但光标隐藏保留、标题保留**，核实记录 8）、`ris-then-text`（`ESC c` 后同一块里的文字照常打印）、`reset-step`（`reset` 步骤：和 RIS 的差别是解析器状态不复位——`reset` 前留一个半截 CSI，复位后续上） | `:3427-3438`、headless `Terminal.ts:122-132` |

**Windows 模式与改尺寸**

| id | 要点 |
|---|---|
| `winpty-heuristic-lf`（`{conpty, 19044}`：打满一行不折行地 `CR LF`，下一行被标成折行；行尾是空格则不标）、`winpty-heuristic-cup`（`CSI H` 触发同一判断，然后照常定位）、`winpty-new-build`（`{conpty, 21376}`：不启用）、`winpty-winpty`（`{winpty, 19044}`：不启用）、`winpty-option-change`（`setOption windowsPty` 运行中打开 / 关闭） | `WindowsMode.ts`、`CoreTerminal.ts:279-306` |
| `resize-rows`（增减行，光标在上 / 中 / 底，有 / 无滚回）、`resize-min`（`resize [1, 0]` → 2 × 1）、`resize-same`（同尺寸：无操作，headless `:90-96`）、`resize-in-alt`、`resize-cols-winpty`（`{conpty, 19044}` 下改列）、`resize-saved-cursor`（`savedX` 钳位） | `CoreTerminal.ts:187-200`、`Buffer.resize` |
| `scrollback-option`（运行中 `setOption scrollback 2`：裁头、`ybase` 调整、标记 / 链接跟着） | `BufferSet.ts:36` |

**重画区间**

| id | 要点 |
|---|---|
| `renders-multi`（一块里写三行）、`renders-scroll`（滚动时的区间，含 `onScroll` 并入的边距）、`renders-full`（`?1049h`：整屏）、`renders-scrolled-away`（视口在上方很远时输出：`viewportStart >= rows`，不发） | `:474-484`、`CoreTerminal.ts:153-156` |

**`long`**（`source: "long"`，`terminal-core-long.json`；每条末尾接 `ESC[H ESC[2J ok`，证明之后照常）：`long-sgr-1000`、`long-param-digits`（CUP / ECH / ICH / DCH / `38;5;<20 位>`）、`long-intermediates`（`CSI` + 65536 个 `!` + `p`，`writeRepeat`）、`long-osc-title-over`（`OSC 2;` + 10,000,001 个 `a` + BEL：标题不变）、`long-osc-title-exact`（10,000,000：标题设上，存摘要）、`long-dcs-over`（DECRQSS 载荷超限：无应答）、`long-apc-over`、`long-sos`、`long-print`（80 × 25、`scrollback 100`，1,048,576 个 `x` 不换行）、`long-rep-cap`（同 `rep-cap`，放这里因为慢）。

**`synth`**（`source: "synthesized"`，`terminal-core-synth.json`；色表缺省用夹具外壳的 `palette`（主计划「夹具格式」），要浅色表或同亮度表的用例在自己的 `synth.palette` 里给）：

| id | 要点 |
|---|---|
| `osc4-query`（`4;1;?`、`4;1;?;2;?`、`4;256;?` 无效、`4;x;?` 无效）、`osc4-set-query`（各种色彩写法后查询）、`osc4-bad-spec` | `:3066-3090`、`XParseColor.ts` |
| `osc10-11-12`（查询、设置、`10;?;?` 一次问前景和背景、第三项以后被忽略）、`osc104`（全部 / 列表 / 无效项）、`osc110-111-112` | `:3159-3276` |
| `color-formats`（`rgb:f/0/8`、`rgb:ff/00/80`、`rgb:fff/000/888`、`rgb:ffff/0000/8888`、`#f08`、`#ff0088`、`#fff000888`、`#ffff00008888`、大写、`rgb:1/22/333` 混合无效、`#12345` 无效、命名色无效） | `XParseColor.ts:23-56` |
| `scheme-query`（`CSI ? 996 n` 在深 / 浅 / 前景背景同亮度三种色表下）、`scheme-notify`（`?2031h` 后每次设色 / 复位色都报一次；`OSC 4;1;#f00;2;#0f0` 报两次）、`scheme-theme`（`theme` 步骤：覆盖色丢失、报一次）、`scheme-disabled`（`colorSchemeQuery: false`：996 无应答、2031 不置位） | `CoreBrowserTerminal.ts:261-268`、`:524-531` |
| `focus-1004`（`focused: true` 时 `?1004h` 立即 `CSI I`；`false` 时 `CSI O`；`focus` 步骤切换；`?1004l` 后切换不发） | `CoreBrowserTerminal.ts:187`、`:305-331`、`:1124-1130` |
| `ris-keeps-colors`（设色、`ESC c`、查询：仍是设过的色，核实记录 9） | `CoreBrowserTerminal.ts:1099-1119` |

**`mouse`**（`terminal-core-mouse.json`）：5 个协议 × 3 个编码 × 事件表。事件表由生成器组合：按键 `LEFT MIDDLE RIGHT NONE WHEEL` × 动作 `UP DOWN LEFT RIGHT MOVE`（只取上游会产生的组合：滚轮只配 `UP DOWN LEFT RIGHT`，其余只配 `UP DOWN MOVE`）× 修饰键 `{无, shift, alt, ctrl, 三个全按}` × 坐标 `{(0,0), (94,10), (222,5), (223,5), (300,40)}`（像素 `x = col * 9 + 4`、`y = row * 17 + 8`）。

- [ ] **Step 2: 写 `core-cases.js`**（Write 工具）

要求：

1. 头部注释（生成什么、上游、怎么跑、四份夹具的格式引用主计划「夹具格式」、为什么有 `synth`）。
2. 经 `lib-term.js`：每个用例 `normalizeOptions` → `runCase`（得 `expect` 与 `afterReset`）；**只有一个 `write` 步骤**的 `hand` 用例自动加 `variants: [{cuts: "each"}, {cuts: <prng(种子 = 用例序号) 切 3 刀>}]` 并 `checkVariants`（主计划 Task 1 第 10 条）。
3. 四份夹具都用 `T.writeCoreFixture` 写（外壳带 `palette`）；应答器每个用例都挂（主计划「夹具格式」），`synth` 类用例只在要换色表或失焦时带 `synth`。
4. `mouse`：新建一个终端，对每个协议 / 编码组合直接设 `term._core.mouseStateService.activeProtocol / activeEncoding`，对每个事件 `const e = {...event}; const ok = svc.restrictMouseEvent(e); const s = ok ? svc.encodeMouseEvent(e) : null;` 记 `restrict: ok, eventAfter: e, encoded: s === null ? null : b64(latin1(s))`——编码结果是「每个 UTF-16 单元一个字节」的串（`CSI M` 的三个码值可以 > 127，spec §3.3），按 latin1 转字节。
5. 写四份夹具，打印各自的用例数与字节数。

- [ ] **Step 3: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/core-cases.js && ls -l tests/fixtures/terminal-core-*.json && node tools/terminal-oracle/core-cases.js > /dev/null && git status --short
```

Expected：每个文件（含分片）≤ 2MB；两次输出相同；`checkVariants` 没有报错（上游对切块不敏感）；抽查三条：`ech` 的第一行文本 `"ab"`（核实记录 4）；`ris` 的 `modes.showCursor` 为 `false`（核实记录 8）；`scheme-notify` 的 `data` 解出来含两个 `ESC[?997;`。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/cases/core-hand.js tools/terminal-oracle/core-cases.js tests/fixtures/terminal-core-hand*.json tests/fixtures/terminal-core-long*.json tests/fixtures/terminal-core-synth*.json tests/fixtures/terminal-core-mouse*.json && git commit -m "test(terminal): whole-terminal cases from xterm.js headless

vttest-style hand cases over printing, charsets, controls, cursor,
erase, insert/delete, margins, tabs, modes and their reports, SGR,
replies, OSC 8 and resets, each also fed byte by byte and in random
pieces; oversized input that must leave the terminal usable; colour,
colour-scheme and focus replies from a responder copied from the browser
layer; and mouse restriction and encoding for every protocol.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: `escape-files.js` → `terminal-core-escape*.json`

**Files:**
- Create: `tools/terminal-oracle/escape-files.js`
- Create (generated): `tests/fixtures/terminal-core-escape*.json`

- [ ] **Step 1: 写脚本**（Write 工具）

要求：

1. 头部注释：输入来自 xterm.js 仓库 `test/fixtures/escape_sequence_files/`（MIT）；按 Task 0 Step 3 的结论写出处与许可；为什么不照上游跳过（核实记录 11，开工前问题二第 13 条）——把上游跳过的 5 个文件名和原因抄进注释；为什么从 git 对象读（核实记录 10）；为什么 `convertEol: true`（文件本来经终端的 ONLCR 显示）。
2. 文件列表：`git -C XTERM ls-tree --name-only HEAD test/fixtures/escape_sequence_files/`，取 `.in` 与 `.in_`，减去 `EXCLUDED`（Task 0 Step 3 决定；缺省空数组），按名字排序。
3. 每个文件一个用例：`{ id: <文件名>, source: "escape-file", cols: 80, rows: 25, options: { convertEol: true }, steps: [{ write: b64(gitBlob(...)) }], variants: [{ cuts: "each" }, { cuts: <prng(文件序号 + 5000) 切 4 刀> }] }`，`runCase` + `checkVariants`。
4. 用 `T.writeCoreFixture` 写 `terminal-core-escape.json`（自动分片），打印用例数、总字节数。

- [ ] **Step 2: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/escape-files.js && ls -l tests/fixtures/terminal-core-escape*.json && node tools/terminal-oracle/escape-files.js > /dev/null && git status --short
```

Expected：用例数 = 79 − `EXCLUDED` 个数；分片都 ≤ 2MB；两次相同；`t0003-line_wrap.in` 的用例里 `write` 解码后没有 `\r\n`（从 git 对象读的是 LF）。

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/escape-files.js tests/fixtures/terminal-core-escape*.json && git commit -m "test(terminal): xterm.js's escape sequence files as oracle cases

All the .in files (and the three parked .in_ ones) from xterm.js's own
test fixtures, read from git objects so autocrlf cannot touch them, fed
whole, byte by byte and in random pieces at 80x25. The five files
upstream skips are compared too: they are skipped there for differing
from real xterm, which does not apply to a port checked against
xterm.js.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: `fuzz.js` → `terminal-core-fuzz*.json`

**Files:**
- Create: `tools/terminal-oracle/fuzz.js`
- Create (generated): `tests/fixtures/terminal-core-fuzz*.json`

- [ ] **Step 1: 写脚本**（Write 工具）

要求：

1. 300 个用例，种子 1–300，`cols 40, rows 12, scrollback 50`，Unicode 版本按种子轮换（`6 / 11 / 15 / 15-graphemes`）。
2. 每个用例 `prng(seed)` 生成 512–4096 字节：权重 ESC 12%、`[` 10%、`]` 2%、`P` 1%、`_` 1%、`;` 8%、`:` 2%、数字 18%（**连续数字最多 4 位**：避免 IL / DL / REP 之类的循环拖慢上游，核实记录 5、6）、CSI 终止字节 `@`–`~` 14%、C0 7%、UTF-8 片段（合法多字节、截断、非法字节）8%、`?` `>` `=` `<` 3%、ASCII 可打印 12%、`0x7F`–`0x9F` 单字节 2%。
3. 终端用 `T.makeCaseTerminal` + `T.attachRecorders` + `T.attachSynth`（缺省色表、focused true）建；执行用 `term._core.writeSync(bytes)` 包在 `try/catch` 里（上游崩的输入没有答案，spec §13.5 第 6 条）：抛了就丢弃该种子、在输出和脚本末尾的 `SKIPPED` 表里记一行（种子 + 异常消息）；正常的用例 `dumpState` 得 `expect`。`afterReset` 同 `runCase` 的做法（同实例 `reset()` 后再 `writeSync`）。
4. 每 5 个用例里给 1 个加 `variants: [{ cuts: <prng 切 6 刀> }]`，用 `writeSync` 逐块喂验证相同。
5. 用 `T.writeCoreFixture` 写 `terminal-core-fuzz.json`（自动分片），打印用例数、跳过数、字节数。

- [ ] **Step 2: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/fuzz.js && ls -l tests/fixtures/terminal-core-fuzz*.json && node tools/terminal-oracle/fuzz.js > /dev/null && git status --short
```

Expected：跑完不超过 2 分钟；分片 ≤ 2MB；两次相同；跳过数打印出来（预期 0，有的话照记）。

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/fuzz.js tests/fixtures/terminal-core-fuzz*.json && git commit -m "test(terminal): seeded random bytes through xterm.js as oracle cases

Three hundred seeded byte streams biased towards escape syntax, broken
UTF-8 and control codes, run through xterm.js headless with the final
state as the expectation; digit runs are capped so no case asks upstream
for billions of loop iterations, and any seed upstream throws on is
dropped and listed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 真实程序录制（看开工前问题一第 2 条）

用户选了「不录」：跳过整个任务（`regen-all.js` 会 skip `recordings.js`），Task 18 不写 `TestRecordings`，签收记录写一句。

**Files:**
- Create: `tools/terminal-oracle/wsl-record.sh`、`tools/terminal-oracle/wsl-record-pipe.py`
- Create: `tools/terminal-oracle/recordings/*.cast`（主控录）
- Create: `tools/terminal-oracle/recordings.js`
- Create (generated): `tests/fixtures/terminal-core-recording*.json`

- [ ] **Step 1: 写两个录制脚本**（Write 工具；实现 agent 写，主控跑）

`wsl-record-pipe.py`：从 stdin 读原始字节，写 asciicast v2——第一行头部 `{"version": 2, "width": W, "height": H, "env": {"TERM": "xterm-256color"}}`（**不写** `timestamp`，spec §13.5 第 7 条的精神：录制物本身可以带时间，但不带录制时刻），之后每读到一块写一行 `[秒数, "o", "<文本>"]`；秒数是相对开始的单调时间，保留 6 位小数；文本用增量 UTF-8 解码器（`codecs.getincrementaldecoder('utf-8')(errors='replace')`，块边界上的半截字符留到下一块）。asciicast 的数据是 UTF-8 文本，装不下非法字节：真遇到了就替换成 U+FFFD，结束时向 stderr 报替换个数，非零的录制作废重录（录制环境 `LANG=C.UTF-8`，正常不会出现）。只用 Python 标准库。

`wsl-record.sh <名字> <宽> <高> <命令文件>`：`env -i HOME=/tmp/tyrec PATH=/usr/bin:/bin TERM=xterm-256color LANG=C.UTF-8 PS1='$ '` 下起 `tmux new-session -d -s tyrec -x W -y H bash --norc --noprofile`；`tmux pipe-pane -o -t tyrec 'python3 …/wsl-record-pipe.py W H > recordings/<名字>.cast'`；按命令文件逐行 `tmux send-keys`（行首 `#sleep N` 表示等待 N 秒）；最后 `tmux kill-session`。录制目录和脚本用 WSL 路径 `/mnt/d/Projects/ty-3.1/tools/terminal-oracle/`。命令文件放 `recordings/<名字>.keys`（也进仓库，可重录）。

- [ ] **Step 2: 【主控执行】录制**

每段 ≤ 256KB（spec §17.2 第 8 条），超了就缩短操作。至少：

| 名字 | 尺寸 | 操作要点 |
|---|---|---|
| `vim-edit` | 80 × 24 | `vim -u NONE -N`，`:syntax on` 不可用时用 `vim -u DEFAULTS`；打开一个生成的 50 行文件、翻页、插入几行、`:q!` |
| `less-scroll` | 80 × 24 | `less` 一个 200 行文件，翻页、搜索、`q` |
| `htop-few-frames` | 100 × 30 | `htop -d 5`，等 2 秒，`q` |
| `git-log-color` | 100 × 30 | 在 `/tmp/tyrec` 建一个 30 次提交的仓库（提交人 `Test <test@example.com>`、固定日期 `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE`），`git log --color --graph --oneline -n 40 | cat` |
| `ls-color` | 80 × 24 | 生成几类文件后 `ls --color=always -la` |
| `python-repl` | 80 × 24 | `python3 -q`，几行表达式、一个异常、`exit()` |
| `tmux-split` | 100 × 30 | 嵌套 tmux：分左右两格，各跑 `seq 1 50`、`printf` 彩色 |
| `cat-cjk-emoji` | 80 × 24 | `cat` 一个含中文、全角标点、表情（含 ZWJ 序列、区旗）、组合符的文件 |

录完检查：`grep -c "$(whoami)\|$(hostname)" recordings/*.cast` 必须全为 0（不带用户名、主机名）。

- [ ] **Step 3: 写 `recordings.js`**（Write 工具）

读 `recordings/*.cast`（名字排序）：头部取宽高；每个 `"o"` 事件的文本按 UTF-8 编码成一个 `write` 步骤（事件边界就是切块边界）；`options: { scrollback: 200 }`；Unicode 版本 `11`；`runCase`（`afterReset` 照常）；用 `T.writeCoreFixture` 写 `terminal-core-recording.json`（自动分片），打印用例数与字节数。

- [ ] **Step 4: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && ls -l tools/terminal-oracle/recordings/ && node tools/terminal-oracle/recordings.js && ls -l tests/fixtures/terminal-core-recording*.json && node tools/terminal-oracle/recordings.js > /dev/null && git status --short
```

Expected：每个 `.cast` ≤ 256KB；夹具分片 ≤ 2MB；两次相同。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/wsl-record.sh tools/terminal-oracle/wsl-record-pipe.py tools/terminal-oracle/recordings tools/terminal-oracle/recordings.js tests/fixtures/terminal-core-recording*.json && git commit -m "test(terminal): real program recordings replayed through xterm.js

vim, less, htop, git log, ls, a Python REPL, nested tmux and a CJK and
emoji file, recorded in WSL through tmux with a scrubbed environment and
kept as asciicast v2 with the keystroke scripts that made them, then fed
event by event to xterm.js headless for the expected state.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: `tyControls.Terminal.Core`（一）——类型、选项、状态服务、颜色、鼠标协议、公开接口

**Files:**
- Create: `source/tyControls.Terminal.Core.pas`
- Modify: `tycontrols.lpk`（`tyControls.Terminal.Buffer.pas` 之后）

- [ ] **Step 1: 单元头与 interface**

单元头：移植自 xterm.js 6.0.0；源文件 `src/common/InputHandler.ts`、`CoreTerminal.ts`（非 UI 部分）、`src/headless/Terminal.ts`（`reset` / `clear` / `resize`）、`src/common/services/{Core,Charset,MouseState}Service.ts`、`src/common/input/{WriteBuffer,XParseColor}.ts`、`src/common/WindowsMode.ts`、`src/common/data/{Charsets,EscapeSequences}.ts`，以及浏览器层的应答段 `src/browser/CoreBrowserTerminal.ts:204-268`、`:305-331`、`:1124-1130`、`src/browser/services/ThemeService.ts` 的覆盖 / 恢复语义；版权行同 Task 3，另抄 `CoreTerminal.ts:6-12` 的 jslinux 来历一句。一段话写清：headless 的 `reset` 不是全复位（地雷 13）；REP 上限是有意偏离（开工前问题二第 11 条）；等价钳制（第 12 条）；颜色覆盖表的语义（第 18 条）；鼠标只有协议状态与两个纯函数（第 16 条）。

interface 照主计划「接口清单」Core 部分。

- [ ] **Step 2: 内部状态**（implementation 段的私有类或 `TTyTerminalCore` 的私有字段，结构执行者定）

- **CoreService**（`CoreService.ts`）：`Modes.InsertMode`；`DecPrivateModes` 的 12 个字段（`cursorBlink` / `cursorStyle` 是三态：未设 / 值）；`IsCursorHidden`、`IsCursorInitialized`；kitty 状态（`flags`、`mainFlags`、`altFlags`、两个栈）；`Reset` 照 `:68-72`（**不**动 `IsCursorHidden`）；`TriggerDataEvent(AData: RawByteString; AWasUserInput)` 照 `:74-95`：`ReadOnly` 直接返回；用户输入且 `ScrollOnUserInput` 且 `ybase <> ydisp` → 发 `OnRequestScrollToBottom` 并滚到底（`CoreTerminal.ts:150`）；用户输入 → 写入队列的 `DidUserInput := True`（`:151`，2d 用）；发 `OnData`。
- **CharsetService**（`CharsetService.ts`）：`Charset: TTyTermCharsetId`、`GLevel`、`Charsets: array of TTyTermCharsetId`（按需加长，空洞 0）；`Reset` / `SetGLevel` / `SetGCharset` 照抄。字符集表读 Task 10 的 `.inc`（`{$I tyControls.Terminal.Charsets.inc}` 放 implementation 段）；`CharsetForKey(AKey: Char): TTyTermCharsetId`。
- **MouseStateService**（`MouseStateService.ts`）：协议、编码两个枚举；`RestrictMouseEvent` 照 `:13-83` 的五个 `restrict`（X10 清掉修饰位）；`EncodeMouseEvent` 照 `:92-151`：`eventCode`（动作映射见地雷 12）；DEFAULT 编码三个值任一 > 255 返回 `''`，否则 `#27'[M'` + 三个**单字节**（`Chr(v)`，spec §3.3）；SGR / SGR_PIXELS 的 `M` / `m`。`Reset`：NONE / DEFAULT。协议变化时发 `OnModesChange`。
- **颜色**：覆盖表 `array[0..258] of record Set: Boolean; Rgb: Cardinal end`；`ResolveColor(i)` = 覆盖优先、否则 `OnQueryBaseColor`（没挂事件时答 0）；`HasColorOverride`；XParseColor 的移植 `ParseXColor(const S: string; out R, G, B: Byte): Boolean`（`XParseColor.ts:23-56`，舍入按地雷 3）；`ToRgbString(Rgb)`（`:58-80` 的 16 位写法）；颜色事件处理（REPORT / SET / RESTORE，主计划 Task 1 第 6 条的语义）、明暗报告（`relativeLuminance` 逐字移植，`Power` 的末位误差只影响前景背景亮度几乎相等时的比较，夹具里的等亮度用例两边都得 2）；`NotifyColorSchemeChanged` = 清空覆盖表 + 「若 2031 开着就报明暗」。
- **焦点**：`FFocused`（缺省 True——和 node 合成器的缺省一致）；`ReportFocus(AFocused)`：记下，若 `sendFocus` 开着就发 `ESC[I` / `ESC[O`；DECSET 1004 打开时照 `CoreBrowserTerminal.ts:1124-1130` 立即按 `FFocused` 报一次。
- **DirtyRowTracker**（`InputHandler.ts:3655-3695`）照抄。
- **选项**：`TTyTerminalOptions` 实例；属性 setter：`Scrollback` → `BufferService.ScrollbackChanged`；`TabStopWidth` → `TabStopWidthChanged`；`WindowsPty` → 启用 / 停用 Windows 启发（Task 17）；`UnicodeVersion` / `AmbiguousWide` 存着给 `print` 用。

- [ ] **Step 3: 构造、复位、尺寸与滚动的公开方法**

- `Create(ACols, ARows)`：选项缺省（主计划「夹具格式」的缺省表；`UnicodeVersion = tuv11`）、`TTyTerminalBufferService.Create(opts, max(ACols, 2), max(ARows, 1))`、`TTyTerminalOscLinks`、`TTyTerminalParser`、注册全部处理器（Task 16、17 写处理器本体，本步写注册表——照 `InputHandler.ts:180-378` 的顺序逐行注册，顺序决定同键处理器的调用顺序）、UTF-8 解码器、解析缓冲（`array of Cardinal`，按需长到 131072）。
- `Resize`：照 `CoreTerminal.ts:187-200` + headless `:90-96`：同尺寸直接返回；钳 `2 × 1`；**先把写入队列同步处理完**（2d 的 `FlushSync`）；再 `BufferService.Resize`。
- `Reset`：照 headless `:122-132` → `CoreTerminal.ts:270-276`：`_setup()`（重新评估 Windows 启发）→ 输入处理的 `reset`（属性归默认）→ `BufferService.Reset` → 字符集 `Reset` → CoreService `Reset` → 鼠标 `Reset`。**不**复位解析器、标题、链接号计数、`IsCursorHidden`（地雷 13）。
- `ClearScrollback`：照 headless `Terminal.clear()`（`:101-112`）：`ClearAllMarkers`；**钉住**光标行（`AddRef`）后 `Lines.SetItem(0, 它)`、`Lines.Length := 1`、`Release`；`ydisp = ybase = y = 0`；补 `rows - 1` 行默认空行；发 `OnScroll(ydisp)`。
- `ScrollLines` / `ScrollPages`（`pageCount * (rows - 1)`）/ `ScrollToTop` / `ScrollToBottom` 照 `CoreTerminal.ts:218-239`。
- `Input`：`TriggerDataEvent(AData, AWasUserInput)`。
- `Modes`：从各服务拼 `TTyTerminalModes`（`ShowCursor = not IsCursorHidden`；`CursorRequest` / `BlinkRequest` 从三态字段来）。
- `OnModesChange`：CoreService / 鼠标 / 字符集以外的模式字段在一次 CSI / ESC 处理里有变化，处理结束时发一次（实现：处理器入口记快照、出口比较）。

- [ ] **Step 4: 加进 `.lpk`**（写法同 Task 3 Step 5，`tyControls.Terminal.Core.pas`）

- [ ] **Step 5: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Core.pas tycontrols.lpk && git commit -m "feat(terminal): TTyTerminalCore state, options and replies from xterm.js

The core's services: DEC private modes and kitty keyboard state, the G0-G3
charsets over the dumped tables, mouse protocol restriction and encoding,
the colour override table with xterm.js's query, set, restore and
colour-scheme semantics, focus reports, dirty-row tracking, and the
public reset, resize, clear and scroll methods, with reset kept as
partial as xterm.js headless keeps it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: 输入处理（一）——解析入口、打印、控制字符、光标、擦除、插删、滚动

**Files:**
- Modify: `source/tyControls.Terminal.Core.pas`

每个处理器照上游逐行移植，函数头注释写上游名字和起始行号；参数取值统一写 `P(i)` = `Params[i]`（`0` 当缺省的地方照上游写 `IfThen(p = 0, 1, p)` 的等价式，别改成 `Max(p, 1)`——负数不会出现，但逐字对照时更容易核）。

- [ ] **Step 1: `Parse`**（`InputHandler.ts:430-485`，去掉 `wasPaused` / Promise 分支）：记 `cursorStartX/Y`；解析缓冲按需加长；`DirtyRowTracker.ClearRange`；输入超过 131072 字节就按 131072 切片（切的是**字节**，核实记录 14），每片解码再 `Parser.Parse`；结束后光标动了发 `OnCursorMove`；按 `:476-484` 算视口区间，`viewportStart < rows` 才发 `OnRefreshRows`。

- [ ] **Step 2: `Print`**（`:517-661`，逐行）

- 钉住（地雷 7）：`bufferRow` 取到后 `AddRef`，换行时先 `Release` 旧的再取新的并 `AddRef`；`oldRow` 同理（它要跨 `Scroll` 使用）；函数出口统一 `Release`（`try … finally`）。
- `charProperties` 用 `TyUnicodeCharProperties(code, precedingJoinState, UnicodeVersion, AmbiguousWide)`；`extractWidth` / `extractShouldJoin` 用 1 期的 `TyUnicodePropsWidth` / `TyUnicodePropsShouldJoin`。
- 链接：`urlId <> 0` 时 `Links.AddLineToLink(urlId, ybase + y)`。
- 字符集替换：`code < 127` 且当前字符集非 0 时查 `TyTermCharsetMap`，非 0 就替换。
- `screenReaderMode` 分支不移植（无障碍，spec §15 不做）。
- 其余（折行、组合、插入模式、宽字符占位、两处宽字符修补、`precedingJoinState` 写回）照抄。

- [ ] **Step 3: 控制字符与光标**：`bell`、`lineFeed`、`carriageReturn`、`backspace`（两支）、`tab`、`shiftOut` / `shiftIn`、`_restrictCursor`、`_setCursor`、`_moveCursor`（`Int64`，地雷 3）、`cursorUp` … `hVPosition`、`tabClear`、`cursorForwardTab` / `cursorBackwardTab`（次数钳到 `cols`，开工前问题二第 12 条）、`index`、`reverseIndex`、`nextLine`、`tabSet`。

- [ ] **Step 4: 擦除与插删**：`_eraseInBufferLine`、`_resetBufferLine`、`eraseInDisplay`（四支 + `scrollOnEraseInDisplay` 分支 + ED 3 的 `isUserScrolling` 只对主屏）、`eraseInLine`、`selectProtected`、`insertLines` / `deleteLines`（次数钳到 `scrollBottom - y + 1`）、`insertChars` / `deleteChars`、`scrollUp` / `scrollDown`（钳到区域高度；SD 用默认属性）、`scrollLeft` / `scrollRight` / `insertColumns` / `deleteColumns`、`eraseChars`（`x + n` 用 `Int64`）、`repeatPrecedingCharacter`（次数钳到 1,048,576；按块调 `Print`，每块 ≤ 65536 个码位，不预先分配整段；文本取 `bufferRow.GetChars(x)` 解成码位）、`screenAlignmentPattern`、`_eraseAttrData`。

- [ ] **Step 5: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Core.pas && git commit -m "feat(terminal): printing, controls, cursor, erase and scroll handlers

xterm.js's InputHandler for the parse entry, printing with wrap, wide
characters, grapheme joining, insert mode and charsets, the C0/C1
controls, cursor movement with origin mode, the erase family with
selective erase, line and character insert/delete, scroll up/down/left/
right and REP. Loop counts are clamped only where the extra passes are
no-ops, coordinates are summed in Int64, and REP stops at 2^20 repeats.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 17: 输入处理（二）——模式、SGR、应答、存取光标、字符集、OSC、复位、Windows 启发

**Files:**
- Modify: `source/tyControls.Terminal.Core.pas`

- [ ] **Step 1: 模式**：`setMode` / `resetMode`（4、20；20 改的是选项 `ConvertEol`）、`setModePrivate` / `resetModePrivate`（`:1932-2071`、`:2198-2317` 逐 `case`，含 3 的 `setWinLines` + `Resize(132 / 80)` + 复位、12 的 quirk、66 / 1004 / 2026 / 2031 / 9001 的条件、47 / 1047 / 1049 的 kitty 标志互换与备用屏切换、`isCursorInitialized`、整屏重画——`OnRefreshRows(0, rows - 1)`，headless 把 `undefined` 映射成全屏）、`requestMode`（`:2336-2396` 逐行）。

- [ ] **Step 2: SGR**：`_updateAttrColor`、`_extractColor`（逐字：`accu` 六槽、`cSpace`、子参数循环的两个退出条件、分号模式的提前退出、`-1` 归 0）、`_processUnderline`（先 clone——Pascal 按值即可，地雷 6；`!~style || style > 5` → 1）、`_processSGR0`、`charAttributes`（单个 0 的快路径；逐个 `if` 分支照顺序；221 / 222 看扩展）。

- [ ] **Step 3: 应答**：`sendDeviceAttributesPrimary` / `Secondary`（`termName` 固定 `'xterm'`，`_is` 的其他分支照样移植但走不到，注释写明）、`sendXtVersion`（`#27'P>|TyControls(' + TyTermLibraryVersion + ')'#27'\'`，spec §17.2 第 11 条。`TyVersion` 在 `source/tyControls.Types.pas:111`，但那个单元 uses `Graphics`（LCL），Core 不能引用它（地雷 15）；所以 Core 里复制一个常量 `TyTermLibraryVersion = '3.1.0'`，注释写明「发版改 `TyVersion` 时同步改这里」，Task 18 的 `TestXtVersionConstant` 守着两者相等）、`deviceStatus` / `deviceStatusPrivate`（996 → 明暗报告）、`requestStatusString`（DECRQSS，` q` 读选项 `CursorStyle` / `CursorBlink`）、`windowOptions`（`paramToWindowOption` 照 `:52-80`；14 / 16 发 `OnWindowOptionsReport`；18 应答；22 / 23 标题栈上限 10）、`setCursorStyle`。

- [ ] **Step 4: 存取光标、字符集、ESC 其余**：`saveCursor` / `restoreCursor`（`savedCharsets` 整体复制）、`keypadApplicationMode` / `keypadNumericMode`、`selectDefaultCharset`、`selectCharset`（`GLEVEL` 映射 `( ) * + - .`；`/` 无效；未知键 → 默认）、`setgLevel`、`softReset`（`:2816-2835`：`isCursorHidden := False`、边距、属性、CoreService 与字符集复位、保存的光标、原点模式）、`fullReset`（`Parser.Reset` + `Reset`）、`reset`（属性归默认）。

- [ ] **Step 5: OSC**：`setTitle`（发 `OnTitleChange`）/ `setIconName`（发 `OnIconNameChange`，见主计划接口清单末尾的说明）、`setOrReportIndexedColor`（`data.split(';')` 成对取、颜色号用饱和解析、0–255 才有效）、`setHyperlink` / `_createHyperlink` / `_finishHyperlink`（`id` 参数按 `:` 切、找 `id=` 前缀）、`_setOrReportSpecialColor`、`restoreIndexedColor`（空数据 = 全部）、`restoreFg/Bg/CursorColor`。未注册编号的 OSC：解析器的 OSC 回退收集载荷（用 `TTyLimitedStringBuilder`，同样的上限），`END` 且成功时若编号 ≤ `High(Integer)` 发 `OnOsc(ident, data, handled)`（开工前问题二第 23 条）。

- [ ] **Step 6: kitty 键盘**（`:3552-3651`）：四个处理器照抄，扩展关时直接返回 True。

- [ ] **Step 7: Windows 启发**（`CoreTerminal.ts:279-306`、`WindowsMode.ts`）：`windowsPty` 满足 `conpty` 且 `BuildNumber < 21376`（且两项都给了）时启用：`OnLineFeed` 之后调 `UpdateWindowsModeWrappedState`，并注册一个 `CSI H` 处理器（先调启发、返回 False 让原处理器继续）；停用时注销。`lastChar[CHAR_DATA_CODE_INDEX]` 用 `GetCodePoint(cols - 1)`（组合格的「最后一个 UTF-16 单元」永远不是 0 或 32，结论与用码位相同，注释写明）。

- [ ] **Step 8: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Core.pas && git commit -m "feat(terminal): modes, SGR, replies, OSC and resets from xterm.js

SM/RM and DECSET/DECRST with their reports, SGR including colon
sub-parameters, underline styles and colours, DA1/DA2, DSR, DECRQSS and
window reports, XTVERSION reporting TyControls, cursor save and restore
with charsets, OSC titles, colours and hyperlinks, soft and full reset,
the kitty keyboard state and the old-ConPTY wrap heuristics.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 18: `tests/test.terminal.core.pas`（基准、纯函数、守卫）

**Files:**
- Modify: `tests/test.terminal.oracle.pas`（加 `TTyTermHarness`、`TyTermCompareState`、`TyTermRunCase`）
- Create: `tests/test.terminal.core.pas`
- Modify: `tests/tytests.lpr`（uses 里 `test.terminal.buffer,` 之后加 `test.terminal.core,`）

- [ ] **Step 1: 扩展 `test.terminal.oracle.pas`**（主计划「比较器判据」的后三行）

- `TTyTermHarness.Create(ACase: TJSONObject)`：建 `TTyTerminalCore`（`cols` / `rows`），照 `options` 设属性（名字映射一张表写在单元里）；挂记录器；挂 `OnQueryBaseColor`（答用例 `synth.palette` 或文件级 `palette` 的第 `AIndex` 项）并 `ReportFocus(focused)`（缺省 true）；`Run(ASteps; AVariant)`：`write` / `writeRepeat` → `WriteSync`（切块变体：按 `cuts` 分块逐次 `WriteSync`；`"each"` = 每字节一次）；其余步骤映射到 Core 方法（`setOption` 用同一张名字表；`theme` → 用新色表替换 `OnQueryBaseColor` 的答案并调 `NotifyColorSchemeChanged`；`focus` → `ReportFocus`）。
- `TyTermCompareState(ACore; AHarness; AExpect; ACaseId; AMisses)`：主计划 `<state>` 的每个字段；`data` 先把 `TyControls(<TyVersion>)` 换成占位再比（归一化，spec §13.5 第 3 条，这是 Pascal 侧唯一的 `Normalize`）。
- `TyTermRunCase(ACase; AMisses)`：新建 → 跑 → 比 `expect`；同一 Core `Reset` → 记录器清零 → 再跑 → 比 `afterReset`（`"same"` 就比 `expect`）；再对每个 `variants` 项新建 → 跑 → 比 `expect`。返回本用例的比较次数。

- [ ] **Step 2: `TTyTerminalCoreOracleTests`**

| 测试 | 比什么 | 计数 |
|---|---|---|
| `TestFixturesComeFromThePinnedUpstream` | 所有 `terminal-core-*` 夹具的上游信息 | — |
| `TestHandCases` | `terminal-core-hand` 全部用例（含变体、复位重跑） | 各用例 `TyTermRunCase` 返回值之和，且 > 0 |
| `TestLongInputsStayBounded` | `terminal-core-long`；另外每条用例跑完后 `Core.Parser.OscPayloadLength = 0`、`GetFPCHeapStatus.CurrHeapUsed` 比用例开始前多不超过「两块缓冲的行数 × 列数 × 64 字节 + 1MB」 | 同上 |
| `TestSynthesizedReplies` | `terminal-core-synth` | 同上 |
| `TestMouseEncoding` | `terminal-core-mouse`：设协议 / 编码（经 `WriteSync` 发对应 DECSET，而不是直接改字段——走真路径，[[built-not-wired-is-the-default-failure]]），`RestrictMouseEvent` 比返回值与改后的修饰位，`EncodeMouseEvent` 比字节 | 用例数 × 5 |
| `TestEscapeFiles` | `terminal-core-escape` | 同 `TestHandCases` |
| `TestFuzz` | `terminal-core-fuzz` | 同上 |
| `TestRecordings` | `terminal-core-recording`（问题一第 2 条选了不录就不写这个测试） | 同上 |

每个测试结尾 `WriteLn` 用时（只打印，Task 23 Step 3 记）。

- [ ] **Step 3: `TTyTerminalCoreTests`**（纯函数与 Pascal 侧独有行为，照表）

**1. `TestParseXColor`**

| 输入 | 结果 |
|---|---|
| `rgb:f/0/8` | `(255, 0, 136)` |
| `rgb:ff/00/80` | `(255, 0, 128)` |
| `rgb:fff/000/888` | `(255, 0, 136)` |
| `rgb:ffff/0000/8888` | `(255, 0, 136)` |
| `RGB:FF/00/80` | `(255, 0, 128)` |
| `#f08` | `(240, 0, 128)` |
| `#ff0088` | `(255, 0, 136)` |
| `#fff000888` | `(255, 0, 136)` |
| `#ffff00008888` | `(255, 0, 136)` |
| `rgb:1/22/333` | 失败 |
| `#12345` | 失败 |
| `red` | 失败 |
| `''` | 失败 |

（这一列写计划时已用 node 跑上游 `parseColor` 核过，逐项相同。）

**2. `TestToRgbString`**（同样已对上游 `toRgbString` 核过）：`$FF0088` → `rgb:ffff/0000/8888`；`$000000` → `rgb:0000/0000/0000`；`$0A0B0C` → `rgb:0a0a/0b0b/0c0c`。

**3. `TestUnhandledOscGoesToTheHost`**：挂 `OnOsc`，`WriteSync(#27']7;file:///tmp'#7)` → 收到 `(7, 'file:///tmp')`；`OSC 133;A ST` → `(133, 'A')`；`OSC 2;t BEL`（核心处理）→ 不收到；`OSC 4294967300;x BEL` → 不收到；宿主经 `Core.Parser.RegisterOscHandler(1337, …)` 注册后 `OSC 1337;x` → 宿主处理器收到、`OnOsc` 不收到。

**4. `TestModesChangeFiresOncePerSequence`**：`CSI ?1;25;2004h` → `OnModesChange` 恰好 1 次；`CSI ?1h`（已开）→ 0 次；`CSI 1m`（SGR）→ 0 次；`CSI ?1000h` → 1 次（鼠标协议）。

**5. `TestIconNameEvent`**：`OSC 1;icon BEL` → `OnIconNameChange('icon')`、`OnTitleChange` 不发；`OSC 0;both BEL` → 两个都发。

**6. `TestRepBeyondTheCapEqualsTheCap`**：两个 20 × 4、`Scrollback = 10` 的 Core，分别写 `a` + `CSI 1048577 b` 与 `a` + `CSI 1048576 b`；两者的 `X`、`Y`、`YBase`、`YDisp`、行数相同，每一行逐格三字相同（直接用 `TTyTerminalLine` 的访问函数循环比，比较次数断言 = 行数 × 20）。再比 `a` + `CSI 2147483647 b`：同样相同，且在 5 秒内返回（证明分块打印、没有按原始次数循环）。

**7. `TestWindowReportsAskTheHost`**：`WindowOptions := [twoGetWinSizePixels, twoGetCellSizePixels]`，`CSI 14 t` → `OnWindowOptionsReport(twrWinSizePixels)`；`CSI 14;2 t` → 不发；`CSI 16 t` → `twrCellSizePixels`；选项关掉后都不发。

**8. `TestThemeChangeDropsOverrides`**：`OSC 4;1;#123456 BEL` 后 `HasColorOverride(1)`；`NotifyColorSchemeChanged` 后 False，`ResolveColor(1)` 回到 `OnQueryBaseColor` 的答案。

**9. `TestReadOnlySendsNothing`**：`ReadOnly := True` 后 DA1、DSR、DECRQM、焦点报告、`Input`：`OnData` 一次都不发。

**10. `TestCoreUnitsDoNotUseTheLcl`**：读三个单元的源文件，取所有 `uses` 子句里的单元名，不得出现 `Forms Controls Graphics LCLType LCLIntf LResources Dialogs ExtCtrls StdCtrls Menus InterfaceBase LMessages`（spec §3.1）。

**11. `TestNoLineOutlivesTheCore`**：记 `TTyTerminalLine.LiveCount`，建 Core、写一段录制（或 `t0504-vim.in` 的夹具输入）、`Resize` 几次、`ClearScrollback`、进出备用屏，`Free`，`LiveCount` 回到原值。

**12. `TestXtVersionConstant`**：`TyTermLibraryVersion = TyVersion`（测试单元可以 uses `tyControls.Types`）；再 `WriteSync(#27'[>q')`，`OnData` 收到的正好是 `#27'P>|TyControls(' + TyVersion + ')'#27'\'`。

- [ ] **Step 4: 登记到 `tests/tytests.lpr`**，`initialization` 里 `RegisterTest(TTyTerminalCoreOracleTests); RegisterTest(TTyTerminalCoreTests);`（`TTyTerminalWriteQueueTests` 在 Task 20 加进同一个单元）。

- [ ] **Step 5: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.oracle.pas tests/test.terminal.core.pas tests/tytests.lpr && git commit -m "test(terminal): the core held to xterm.js on every fixture class

Hand, oversized, synthesized-reply, mouse, escape-file, random and
recorded cases each run on a fresh core, again after Reset on the same
core, and again fed in pieces, compared field by field with the count
asserted; plus colour parsing, the host OSC hook, mode-change and icon
events, the REP cap, window reports, theme changes, read-only, the no-LCL
rule for the three units and a live-line count after free.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异表（期末做；改 `source/tyControls.Terminal.Core.pas`，除注明的以外）：**

| # | 变异 | 必须红 |
|---|---|---|
| C1 | `Print`：折行时不设下一行 `isWrapped` | `print-wrap-next`、`t0003-line_wrap.in` |
| C2 | `Print`：`oldWidth > 0` 时不搬旧字符 | `combine-across-wrap` |
| C3 | `Print`：`?7l` 下宽字符不跳过 | `print-wide-nowrap` |
| C4 | `Print`：删掉结尾「右边孤立第二半」修补 | `print-wide-right-reset` |
| C5 | `Print`：不跳过 U+00AD | `soft-hyphen` |
| C6 | `shiftOut`：`SetGLevel(1)` → `SetGLevel(2)` | `charset-so-si` |
| C7 | `lineFeed`：不清 `isWrapped` | `lf-clears-wrapped` |
| C8 | `backspace`：反向折行时不做「空格再退一格」 | `bs-reverse-wrap` |
| C9 | `_moveCursor`：`Int64` 改回 `Integer` | `cursor-huge-params`、`long-param-digits` |
| C10 | `eraseInDisplay` 1：不清下一行 `isWrapped` | `ed-1-wraps` |
| C11 | `eraseInDisplay` 3：备用屏上也清 `isUserScrolling` | `alt-ed3` |
| C12 | `scrollDown`：插入行用擦除属性 | `sd-default-attr` |
| C13 | `insertLines`：钳制上限少 1 | `il-dl-1000` |
| C14 | `repeatPrecedingCharacter`：前一个是控制字符时不返回 | `rep-after-control` |
| C15 | `_extractColor`：冒号模式不留色空间槽（`cSpace` 恒 0） | `sgr-rgb-colon` |
| C16 | `_extractColor`：分号模式提前退出条件删掉 | `sgr-color-then-more` |
| C17 | `_processUnderline`：`style > 5` 不归 1 | `sgr-underline-styles` |
| C18 | SGR 59：写 0 而不是 `-1` | `sgr-underline-styles`（核实记录 7） |
| C19 | SGR 221：不看扩展开关 | `sgr-bold-faint-kitty` |
| C20 | `requestMode`：1048 答 RESET | `decrqm-private` |
| C21 | `setModePrivate` 2031：不看扩展开关 | `decset-2031-disabled` |
| C22 | 1049 切回：不 `restoreCursor` | `alt-47/1047/1049` |
| C23 | `softReset`：不复位保存的光标 | `decstr` |
| C24 | `fullReset`：同时把 `IsCursorHidden` 清掉（「修」成全复位） | `ris`（地雷 13） |
| C25 | `Reset`（headless）：复位解析器 | `reset-step`、各用例的 `afterReset` |
| C26 | `setHyperlink`：`id` 不 trim | `osc8-trim` |
| C27 | OscLinks 复用：键不含 uri | `osc8-reuse` |
| C28 | 颜色 SET 后不报明暗 | `scheme-notify` |
| C29 | `NotifyColorSchemeChanged`：不清覆盖表 | `scheme-theme`、`TestThemeChangeDropsOverrides` |
| C30 | DECSET 1004：不立即报焦点 | `focus-1004` |
| C31 | `EncodeMouseEvent` DEFAULT：上限 `> 255` → `>= 255` | `terminal-core-mouse` 的 `(222, 5)` 用例 |
| C32 | `eventCode`：非 SGR 的抬起不并 `NONE` | `terminal-core-mouse` |
| C33 | X10 `restrict`：不清修饰位 | `terminal-core-mouse` |
| C34 | `Parse`：光标没动也发 `OnCursorMove` | 所有 `cursorMoves` 计数（如 `osc-titles`） |
| C35 | `OnRefreshRows`：不做 `viewportStart < rows` 判断 | `renders-scrolled-away` |
| C36 | `TriggerDataEvent`：不看 `ReadOnly` | `replies-disabled`、`TestReadOnlySendsNothing` |
| C37 | Windows 启发：`< 21376` → `<=` | `winpty-new-build`（构建号 21376 那条） |
| C38 | `ClearScrollback`：不钉住光标行直接 `SetItem` | `TestNoLineOutlivesTheCore` 或访问已释放行崩溃（两者之一即算红） |
| C39 | `requestStatusString` ` q`：读 DECSCUSR 状态而不是选项 | `decrqss` |
| C40 | 未处理 OSC：成功条件去掉（失败的也交给宿主） | `TestUnhandledOscGoesToTheHost`（补一条 `OSC 7;x CAN`） |

**等价、不做的**：`DirtyRowTracker.markRangeDirty` 里交换 `y1`/`y2` 的写法（用 `Min` / `Max` 重写结果相同）；`_is` 里 `rxvt-unicode` / `linux` / `screen` 分支（`termName` 固定 `xterm`，走不到）；`Print` 的字符集替换条件 `< 127` 改 `<= 127`（字符集表的键只在 `0x20`–`0x7E`，Task 10 断言过）；`Parse` 按 131072 个码位而不是字节切（解码器跨块续接、`precedingJoinState` 跨调用保留，切点位置不影响任何导出字段——核实记录 14 只是纠正 spec 的措辞）。
