# 终端控件 1 期：Unicode 宽度表与字形簇 + node 端上游基准 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（用户要求，优先于子技能的默认做法）**：整期连续实现，**每个任务只写代码 + 测试并单独提交**，**任务之间不编译、不跑 Pascal 测试**（node 生成脚本例外：生成物要进提交，脚本必须当场跑）。整期写完后（Task 7）一次编译、跑全量、集中修；全绿后集中做一轮变异；最后整体规格核对 + 代码质量审查。中途不汇报、不问要不要提交。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：`D:/Projects/xterm.js` 里的 `npm ci`（三棵树共用的一份 checkout，等同机器级资源，[[parallel-agent-worktree-hazards]]）、从 unicode.org 取许可原文（要联网）、编 `tycontrols.lpk`。实现 agent 不编任何 `.lpk`。

**Goal:** 新增纯函数单元 `tyControls.Unicode.Width`（四个 Unicode 版本的字符宽度、字形簇连接状态、串宽），数据表由 node 跑 xterm.js 6.0.0 上游 dump 生成；同时立起 `tools/terminal-oracle/` 基准环境，让 1、2 期的期望值都来自真跑上游。

**Architecture:** node 在本地 xterm.js checkout 的构建产物上加载四个 provider（`6` 核心自带、`11` addon、`15` / `15-graphemes` addon），把 0..0x10FFFF 压成区间表写进 `source/tyControls.Unicode.Width.Data.inc`；另一个脚本直接问上游 `wcwidth` / `charProperties` / `getStringCellWidth`，写成三份夹具 JSON。Pascal 单元查表（区间二分；6 / 11 的 BMP 在 `initialization` 展开成 64K 字节表），逻辑逐行移植上游 provider。测试按区间对全码位比较，夹具和 `.inc` 由两条独立路径从上游取数。

**Tech Stack:** FPC 3.2.2 / Lazarus（`fpcunit`、`fpjson`）；node v22.22.2（只用内置模块）；xterm.js 6.0.0 本地 checkout（`tsgo` 构建出的 `out/`）。

**设计依据：** `docs/superpowers/specs/2026-09-28-terminal-view-design.md`（下称 spec）。本计划覆盖 §18 第 1 期、§4 全节、§13.1 / §13.2 / §13.5（与 Unicode 相关的部分）、§14（xterm.js 与 Unicode 许可）、§17.2 第 5、8、10 条。

**不在本期**：解析器 / 缓冲 / 核心（2 期）；§13.3 那套缓冲夹具格式（2 期；本期三份夹具格式见 Task 4）；`escape_sequence_files` 的「测试夹具」许可小节（2 期，§17.2 第 9 条）；CHANGELOG（发版时写，[[changelog-user-facing]]）；README（没有新控件）；控件文档（3 期）。

---

## 核实记录（写计划时读源码 + 实跑上游源码得到，2026-09-28）

执行者不用重做，但 Task 0 会在真构建上复核其中几条。「实跑」= 把上游 `.ts` 拷到临时目录、改 import 路径、`node --experimental-strip-types` 直接跑（没装 `node_modules`，没动 checkout）。

1. **构建命令**（`xterm:package.json:39-41`、`AGENTS.md`「Build System」）：`npm run build` = `tsgo -b ./tsconfig.all.json`，产物是逐文件 CommonJS：核心在 `out/`（`src/tsconfig-base.json` 的 `rootDir: "."` + 各子项目 `outDir: ../../out`，所以是 `out/common/...`、`out/headless/...`），addon 在 `addons/<名>/out/`（addon 的 `src/tsconfig.json`：`rootDir: "."`、`outDir: "../out"`）。addon 源码用路径别名 `common/*`（同文件 `paths`），编出来原样是 `require("common/...")`，所以要 `NODE_PATH=<XTERM>/out`，上游 benchmark 同样这么设（`package.json:67`）。
2. **上游自己的单元测试已经不走 `out/` 了**：`bin/test_unit.js:11-14` 用的是 `npm run esbuild` 出的 `out-esbuild/`（`bin/esbuild.mjs` 的 `outConfig`，同样逐文件 CJS、同样要 `NODE_PATH`）。spec §13.1 写的 `out/` 仍然可用（benchmark 路径），本计划照 spec 用 `out/`；`out/` 加载不了时的备选是 `npm run esbuild` + `out-esbuild/`（Task 0 Step 3）。
3. **`npm ci` 会装 `node-pty`（原生模块）**：`package.json` 的 devDependencies 有 `node-pty ^1.2.0-beta.9`，装的时候可能要编原生代码。我们用不到它；装失败就改用 `npm ci --ignore-scripts`（`esbuild`、`@typescript/native-preview` 的平台二进制走 optionalDependencies，不靠安装脚本）。根 `package.json` 没有 `postinstall` / `prepare`。
4. **15-graphemes addon 能在 headless 里加载**：`UnicodeGraphemesAddon.activate` 只用 `terminal.unicode`（`addons/addon-unicode-graphemes/src/UnicodeGraphemesAddon.ts:20-28`），headless 的 `unicode` getter 要 `allowProposedApi: true`（`src/headless/public/Terminal.ts:60-63`、`:81-84`），`loadAddon` 在 `:174-177`。`ambiguousCharsAreWide` 是 provider 实例上的公开字段，addon 把两个 provider 都注册进 `UnicodeService._providers`，node 端从 `term._core.unicodeService._providers['15' | '15-graphemes']` 拿到实例直接设。
5. **（与 spec 不符，重要）node 下 15 表解码是坏的。** `third-party/UnicodeProperties.ts` 的 `_dec` 在有 `Buffer` 时用 `Buffer.from(s, 'base64')`；解出来 3023 字节，node 从 8KB 共享池里切给它，`byteOffset` = 648（实跑）。`unicode-trie.ts` 的构造函数用 `new DataView(data.buffer)` 读头，**忽略了 byteOffset**，读到池里的垃圾：`highStart` 读成 `0x5c`（应为 `0x110000`），`uncompressedLength` 读成 1869639017（应为 51056，于是分配约 1.8GB）。后果：**补充平面（≥ U+10000）的 `getInfo` 全部是 0**（表情不宽、区旗不连），BMP 碰巧对；读到的垃圾取决于池里之前放了什么，**结果不可复现**。浏览器里走 `atob` 分支、拿到的是新数组，所以是对的——上游 addon 的测试只在 playwright（浏览器）里跑（`addons/addon-unicode-graphemes/test/`），没抓到。
   **修法**：加载 addon **之前** `Buffer.poolSize = 0`（node 的 `Buffer.from(string)` 在 `length >= Buffer.poolSize >>> 1` 时不走池，每次读这个值），`byteOffset` 就是 0。实跑确认：修后 `getInfo` 共 2269 段（修前 1807 段），U+1F600 → `0x3b`（宽），U+1F1E6 → `0x13`（区旗、强制 1 列），区旗对 🇨🇳 连接后宽 2。生成脚本另外独立解码一遍 trie 逐码位对照（Task 1），以防这一条以后以别的形式回来。
6. **全码位区间数**（修后、实跑）：`wcwidth` —— `6` 309 段、`11` 888 段、`15` 927 段（ambiguous 宽时 1231）；15 原始 `getInfo` 2269 段，取值 20 种、最大 `0x3b`（放得进 `Byte`）。`charProperties` 按 9 个前驱各扫一遍全码位，6 个变体合计约 6.5 万段——夹具约 1.2MB，node 扫一遍约 3.5 秒。
7. **打包值的范围**：`createPropertyValue` 先 `state & 0xffffff` 再 `<< 3`，最大 `0x7FFFFFF`（27 位），恒为正；「不连接」时 15-graphemes 的 state 是负数（`afterCode - 16`，`UnicodeProperties.ts` 的 `shouldJoin`），掩码后是 `0xFFFFF0..0xFFFFFB`。Pascal 必须照样掩 24 位。
8. **`15`（不带 graphemes）永不连接**：`UnicodeGraphemeProvider.charProperties` 里 `w` 小于 2 时一律改成 1（`:36-40`），`handleGraphemes = false` 时 `charInfo = w === 0 ? 1 : 0` 恒为 0（`:46`），所以组合符在 `15` 下**自占一格、宽 1**，而同一个码位的 `wcwidth` 是 0。实跑：`15` 下 `"e\u0301"` 串宽 2，`6` / `11` / `15-graphemes` 下是 1。
9. **U+0301 在 15 表里是 ambiguous**：`15` + ambiguous 宽时 `"e\u0301"` 串宽 3；`15-graphemes` + ambiguous 宽时 2（连接后宽取 2，减去前一个的 1）。照上游结果做（spec §13.5 第 2 条）。
10. **15 下控制字符 `wcwidth` = 1、U+200D = 1**（trie 里 Control 归 `GRAPHEME_BREAK_Other`，宽度类 normal）；`6` / `11` 下都是 0。打印路径不会把 C0 送进来，但查表函数照上游答。
11. **越界码位**：上游 `6` / `11` 对 > 0x10FFFF 答 1，`15` 的 trie 对 > 0x10FFFF 答 `errorValue`（= 0）。
12. **`getStringCellWidth` 的 UCS-2 回退有顺序怪癖**：高代理后面跟的不是低代理时，**先**把后一个单元按 `wcwidth` 加上，**再**让高代理本身走 `charProperties`，然后循环跳过已经吃掉的后一个单元（`UnicodeService.ts:83-91`）。实跑：单元序列 `[D83D, D83D, DE00]` 串宽 3（后面那一对被拆开了）。
13. **Unicode 数据的出处链**：15 表是 addon 从外部项目 unicode-properties（`addons/addon-unicode-graphemes/README.md:7`）生成的；`third-party/*.ts` 三个文件没有任何许可头。我们只移植 `UnicodeProperties.ts` 的规则部分（`shouldJoin` / `_shouldJoin`，约 60 行）、不移植解压器，数据是跑上游 dump 出来的。
14. **仓库现状**：`source/` 下没有 `tyControls.Unicode*`；`tests/fixtures/` 只有 `sample-theme/`（AdvChart 的夹具在 `ty-advchart` 树，没进这棵树）；`tools/` 下没有 `*-oracle`；`.gitignore` 忽略任意层级的 `lib/` 目录（所以脚本目录里别建 `lib/`）；`core.autocrlf = true`。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，收尾时（Task 7）写回 spec。

### 一、产品方向（问用户）

1. **`15`（不带 graphemes）照搬「组合符不连接、自占一格」吗？**（核实记录 8）
   这是上游的实际行为，很可能是上游的疏漏：选 `15` 时分解形式的 `é`、带变体选择符的字符都会多占一格。spec 的原则是「照上游的结果做」（§13.5 第 2 条），默认版本又是 `tuv11`，所以只有宿主主动选 `15` 才会碰到。
   **建议**：照搬，逐位对上上游；3 期写控件文档时注明「要字形簇就选 `15-graphemes`，`15` 不连接组合符」。改成连接就没有上游基准了。
2. **`15` / `15-graphemes` 下 ambiguous 宽时的怪结果照搬吗？**（核实记录 9）U+0301 这类组合符本身是 ambiguous，打开 `AmbiguousWide` 后 `15` 下 `é` 占 3 格、`15-graphemes` 下占 2 格。
   **建议**：照搬，理由同上；3 期控件文档注明。
3. **要不要给上游报「node 下 15 表解码错」？**（核实记录 5）这是明确的 bug（`DataView` 忽略 `byteOffset`），修法一行。报 issue 是以你的账号公开发帖，我们不代发。
   **建议**：你有空就报一个，附上本计划核实记录 5 的两个数；不影响我们（Task 1 已经绕开）。

### 二、实现层面（主控定）

4. **基准取浏览器里的行为**：node 下 15 表的结果依赖 Buffer 池里的垃圾，既不对也不可复现；浏览器（`atob` 分支）才是 xterm.js 用户看到的。生成脚本加载 addon 前设 `Buffer.poolSize = 0`，再独立解码一遍 trie 逐码位对照，不一致就中止（Task 1）。
5. **node 依赖只装在 `D:/Projects/xterm.js`**：`tools/terminal-oracle/` 不是 npm package（不建 `package.json`、不建 `node_modules`），脚本只用 node 内置模块 + 上游 `out/`。这就是 spec §13.1 的做法，核实可行（核实记录 1、4）。
6. **`NODE_PATH` 在 `lib-dump.js` 里设**（`process.env.NODE_PATH = ...; require('module').Module._initPaths()`），命令行不带环境变量前缀——spec §13.1 的 `NODE_PATH=... node ...` 是 POSIX 写法，PowerShell 下不认。上游路径仍可用 `XTERM_ROOT` 覆盖（spec §13.1）。
7. **生成物头部不写墙钟时间**：spec §4.2 说头部写「生成时间」，§13.5 第 7 条又要求「不读时间、重跑 `git diff` 为空」，两条冲突。**做法**：头部写上游提交的日期（`git log -1 --format=%cs`），它随上游固定。上游的本地路径只写在脚本头部注释和默认值里，不写进生成物（换一台机器路径不同，生成物不该变）。
8. **数据形态**：三张区间表，每张是「起点 `Cardinal` 数组 + 值 `Byte` 数组」两个平行常量数组；`6` / `11` 存 `wcwidth`，`15` 存原始 `getInfo`（`15` 的 `wcwidth` / `charProperties` 由 Pascal 逻辑从原始值算，和上游同一条路）。`6` / `11` 的 BMP 在 `initialization` 展开成两张 64K 字节表（spec §17.2 第 5 条），BMP 外走二分。
9. **全码位比较按区间，不写 111 万条**：夹具里存上游答案的区间表，Pascal 侧逐区间、逐码位调函数比。三份夹具：`terminal-unicode-width.json`（6 个变体的 `wcwidth` + 越界探针）、`terminal-unicode-join.json`（6 个变体 × 9 个前驱的 `charProperties` 全码位）、`terminal-unicode-cases.json`（手写序列、代表码位的两两 / 三连组合、串宽）。每份 ≤ 2MB（spec §17.2 第 8 条），生成脚本超限就报错。
10. **`TyUnicodeStringCellWidth` 收 UTF-8，孤立代理用 WTF-8 表示**：标准 UTF-8 装不下孤立代理，spec §4.4 又要求「含孤立代理的 UCS-2 回退」。做法：自带解码器把 UTF-8 转成 UTF-16 单元，**三字节序列编码的 U+D800..U+DFFF 解成那个孤立单元**（WTF-8），然后逐行照搬上游的 UTF-16 循环。其余非法字节：每个出错的首字节产出一个 U+FFFD、只吃这一个字节（上游没有这种输入，没有基准；判据只要求「和同样多的 U+FFFD 一样宽」）。
11. **越界码位（> 0x10FFFF）照上游答**：`.inc` 里给三个版本各一个越界常量，由脚本从上游问出来（核实记录 11）；Pascal 先判越界再查表。
12. **`_shouldJoin` 的许可**：规则所在的 `third-party/UnicodeProperties.ts` 位于 addon 目录，addon 的 `LICENSE`（MIT，2023 The xterm.js authors）覆盖该目录；上游来源 unicode-properties 项目本身的许可没核。**做法**：单元头按 addon 的 MIT 署名，另注明「字形簇规则取自 unicode-properties，经 xterm.js addon 引入」。主控开工前看一眼 `github.com/PerBothner/unicode-properties` 的许可；若不兼容 MIT，Task 3 的 `JoinRule` 改为照 UAX #29 GB6–GB13 自写（行为由夹具锁死，测试不用改）。
13. **比较次数要断言**：每个全码位测试数一下实际比了多少个码位，必须等于「0x110000 × 区间表张数」——夹具读空、循环提前退出都会「零次比较、全绿」（[[assertion-never-varies-the-thing]]）。
14. **锚点测试独立于夹具**：`.inc` 和夹具都出自同一个上游进程，如果将来有人把核实记录 5 的修法弄丢，两边会**一起**错、测试一起绿。所以另有一张锚点表（本计划 Task 5，值是写计划时用正确解码实跑上游得到的），不读夹具。
15. **`tycontrols.lpk` 改了清单，签收前主控编一次包**（Task 7 Step 5）。本期除此之外没有编包、编示例。

---

## 接口清单（全计划用这一套名字）

**公开的（`source/tyControls.Unicode.Width.pas`，spec §4.4 原样）：**

```pascal
type
  TTyUnicodeVersion = (tuv6, tuv11, tuv15, tuv15Graphemes);
  TTyUnicodeCharProps = type Cardinal;   { state shl 3 or width shl 1 or Ord(shouldJoin) }

function TyUnicodeWcWidth(ACodepoint: Cardinal; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;                                   { 0..2 }
function TyUnicodeCharProperties(ACodepoint: Cardinal; APreceding: TTyUnicodeCharProps;
  AVersion: TTyUnicodeVersion; AAmbiguousWide: Boolean): TTyUnicodeCharProps;
function TyUnicodePropsWidth(AProps: TTyUnicodeCharProps): Integer;       { extractWidth }
function TyUnicodePropsShouldJoin(AProps: TTyUnicodeCharProps): Boolean;  { extractShouldJoin }
function TyUnicodePropsKind(AProps: TTyUnicodeCharProps): Cardinal;       { extractCharKind }
function TyUnicodeStringCellWidth(const AUtf8: string; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;
function TyUnicodeVersionName(AVersion: TTyUnicodeVersion): string;      { '6' '11' '15' '15-graphemes' }
```

`6` / `11` 下 `AAmbiguousWide` 不起作用（spec §4.3、§17.1 第 2 条）。

**单元内部的（implementation 段）：** `RunIndex`、`MakeProps`、`LegacyWcWidth`、`LegacyCharProps`、`Info15`、`WcWidth15`、`JoinRule`、`ShouldJoin15`、`CharProps15`、`Wtf8ToUnits`、`ExpandBmp`、`GBmp6` / `GBmp11`。

**生成的常量（`source/tyControls.Unicode.Width.Data.inc`，只在 implementation 段 `{$I}`）：**

```pascal
const
  TyUniV6Start: array[0..N6-1] of Cardinal = (...);   TyUniV6Width: array[0..N6-1] of Byte = (...);
  TyUniV11Start: array[0..N11-1] of Cardinal = (...); TyUniV11Width: array[0..N11-1] of Byte = (...);
  TyUniV15Start: array[0..N15-1] of Cardinal = (...); TyUniV15Info: array[0..N15-1] of Byte = (...);
  TyUniV6OutOfRange = 1; TyUniV11OutOfRange = 1; TyUniV15OutOfRangeInfo = 0;   { 由脚本问出，不手写 }
```

**node 端（`tools/terminal-oracle/lib-dump.js` 导出）：** `XTERM`、`PIN`、`upstreamInfo()`、`loadUpstream()`、`makeTerminal(up)`、`VARIANTS`、`useVariant(term, variant)`、`runsOf(fn)`、`checkTrieDecode(up)`、`writeGenerated(relPath, text)`、`writeFixture(name, obj)`、`GENERATED`。

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `tools/terminal-oracle/lib-dump.js` | **新建**（Task 1）。上游加载、钉版本、`NODE_PATH`、Buffer 池修法与 trie 对照、变体切换、区间编码、写文件与体积上限、生成物登记 |
| `tools/terminal-oracle/gen-unicode-tables.js` | **新建**（Task 2）。写 `.inc` |
| `tools/terminal-oracle/cases/unicode.js` | **新建**（Task 4）。手写序列与串（只有输入） |
| `tools/terminal-oracle/unicode-cases.js` | **新建**（Task 4）。写三份夹具 |
| `tools/terminal-oracle/regen-all.js` | **新建**（Task 4）。重跑全部生成脚本并检查只动了登记过的生成物 |
| `tools/terminal-oracle/unicode-license.txt` | **新建**（Task 0，主控）。从 unicode.org 取的 Unicode License v3 原文 |
| `source/tyControls.Unicode.Width.Data.inc` | **生成**（Task 2）。进 git，**不**列进 `.lpk`（先例 `Icons.Lucide.License.inc`） |
| `source/tyControls.Unicode.Width.pas` | **新建**（Task 3） |
| `tycontrols.lpk` | `<Files>` 末尾加 `source/tyControls.Unicode.Width.pas`（Task 3） |
| `tests/fixtures/terminal-unicode-width.json`、`…-join.json`、`…-cases.json` | **生成**（Task 4） |
| `tests/test.unicode.width.pas` | **新建**（Task 5）。`TTyUnicodeWidthOracleTests`、`TTyUnicodeWidthTests` |
| `tests/tytests.lpr` | uses 加 `test.unicode.width`（Task 5） |
| `THIRD-PARTY-NOTICES.md` | 加 xterm.js 一节与 Unicode 数据许可（Task 6） |
| `tests/test.release.pas` | 加一条：发的单元带 xterm.js / Unicode 数据时，通知文件里有对应的节（Task 6） |
| `docs/superpowers/specs/2026-09-28-terminal-view-design.md` | 只在 Task 7 写回 |

**不碰**：`source/` 下其他任何单元、`designtime/`、`themes/`、`examples/`、`languages/`、`README*`、`CHANGELOG*`、`D:/Projects/xterm.js` 下的任何受版本控制的文件（只在里面装依赖、构建）。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **Buffer 池**（核实记录 5）：任何 `require` 到 `addons/addon-unicode-graphemes/out/...` 的脚本，都必须经 `lib-dump.js` 的 `loadUpstream()` 加载——它在第一行设 `Buffer.poolSize = 0`。**不要**在脚本里自己 `require` 上游模块。
2. **打包值掩 24 位**（核实记录 7）：`MakeProps` 里 state 先转 `Cardinal` 再 `and $FFFFFF`；负的 state（`afterCode - 16`）是正常输入。
3. **`15` 的 `w` 永远 ≥ 1**、`charInfo = w === 0 ? 1 : 0` 恒为 0（核实记录 8）：照原样移植这句，**别**「顺手修掉」，也别当死代码删（删了行为不变，但移植就不再逐行对应，审查时说不清）。
4. **ASCII 快路径的条件是 `(APreceding shr 3) = 0`**，不是 `APreceding = 0`：前驱是 Prepend 时 `a` 要走慢路径才能连上（GB9a）。
5. **`RunIndex` 的变异会死循环**：`mid := (lo + hi + 1) shr 1` 去掉 `+ 1` 后 `lo := mid` 不再前进，测试卡死而不是变红。期末变异只做变异表里列的那几条；卡住时按进程号结束 `tytests-term.exe`，**禁用 `taskkill -im`**（[[parallel-agent-worktree-hazards]]）。
6. **FPC 的 `{ }` 注释会嵌套**（[[fpc-brace-comments-nest]]）：`.inc` 头部注释由脚本写，脚本要断言头部文本里没有 `{`、`}`；单元里的注释也别写 JSON 例子。
7. **含反斜杠的 JS 一律用 Write 工具落文件**，别用 Bash heredoc（[[bash-heredoc-eats-backslashes]]：`\u{...}`、`\n` 会被吃掉）。
8. **新文件写出来是 LF**，检出后是 CRLF（`core.autocrlf = true`）。改 `.pas` 用编辑工具，别用 Git Bash 的 `sed -i`（[[git-bash-sed-strips-crlf]]）；期末变异先 `git diff --stat` 确认改到了（[[crlf-mutation-phantom-survivor]]）。
9. **新单元要进 `.lpk`**（[[new-unit-missing-from-lpk]]），`.inc` 不进；新测试单元要进 `tests/tytests.lpr` 的 uses（`TReleaseManifestTest.EveryTestUnitThatRegistersTestsIsLinked` 守着）。
10. **`fpjson` 读大整数**：夹具里的数都 ≤ 0x7FFFFFFF，用 `AsInteger` 读；越界探针故意不放 ≥ 2^31 的数。
11. **fpcunit 断言别放进 111 万次的循环**：每个码位调一次 `AssertEquals` 会拼消息字符串，慢到不可用。照 AdvChart 的 `Miss` 模式（`D:/Projects/ty-advchart/tests/test.advchart.bargeometry.pas:151-156`）：循环里只计数、记前 30 条，循环外断言一次。
12. **生成要可复现**（spec §13.5 第 7 条）：脚本不读时间、不用随机数、对象键按固定顺序写；`JSON.stringify` 不带缩进（数字数组缩进后体积翻几倍）。

---

## 跑测试的固定套路（只在 Task 7 用）

改了 `source/` 之后**必须** `lazbuild -B`（[[example-stale-lib-on-source-change]]、[[canary-then-rebuild]]）。exe 用唯一名 `tytests-term.exe`。

编译 + 跑一组 suite：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/term-build.txt 2>&1 || { tail -30 /tmp/term-build.txt; false; } && cd tests && cp tytests.exe tytests-term.exe && for s in TTyUnicodeWidthOracleTests TTyUnicodeWidthTests TReleaseManifestTest; do ./tytests-term.exe --suite=$s --format=plain > /tmp/term-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures)" /tmp/term-$s.txt | tr '\n' ' '; echo; done
```

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了（或 suite 名写错），重跑，别读成通过。

全量（输出必须重定向到文件，[[known-rare-suite-flake]]）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-term.exe --all --format=plain > /tmp/term-all.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/term-all.txt
```

## 关于判据和变异

- 纯函数给**输入 / 期望表**，测试照表写；夹具比较写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写。
- 每个任务的「变异」小节列的是**期末集中做**的变异（Task 7 Step 4），不是任务当场做。变异三拍：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编重跑 → 绿。没红的：先查是不是改错了地方；确实没红，当场补强测试，签收记录里写一句。
- 标「等价」的变异不做，理由写在表里（审查时核）。

---

### Task 0: 基线与上游构建

**Files:**
- Create: `tools/terminal-oracle/unicode-license.txt`（Step 5，主控）

- [ ] **Step 1: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1
```

Expected：工作区干净，分支 `feat/terminal`，HEAD 是本计划的提交或其后。

- [ ] **Step 2: 【主控执行】装依赖并构建上游**

```bash
cd /d/Projects/xterm.js && git status --short && git rev-parse HEAD && node --version && npm --version
npm ci > /tmp/xterm-ci.txt 2>&1; echo "exit $?"; tail -15 /tmp/xterm-ci.txt
```

- 若失败在 `node-pty`（原生编译），改跑 `npm ci --ignore-scripts > /tmp/xterm-ci.txt 2>&1`（核实记录 3）。
- Expected：`git status --short` 为空（装之前、装之后都是：`node_modules/`、`out/` 在上游 `.gitignore` 里）；HEAD 以 `c58ea36` 开头；node `v22.22.2`。

```bash
cd /d/Projects/xterm.js && npm run build > /tmp/xterm-build.txt 2>&1; echo "exit $?"; tail -15 /tmp/xterm-build.txt
ls out/headless/public/Terminal.js out/common/services/UnicodeService.js addons/addon-unicode11/out/Unicode11Addon.js addons/addon-unicode-graphemes/out/UnicodeGraphemesAddon.js addons/addon-unicode-graphemes/out/UnicodeGraphemeProvider.js addons/addon-unicode-graphemes/out/third-party/UnicodeProperties.js addons/addon-unicode-graphemes/out/third-party/unicode-trie.js
git status --short
```

Expected：`exit 0`；七个文件都在；`git status --short` 仍为空。

- [ ] **Step 3: 【主控执行】冒烟：headless + 两个 addon + Buffer 池**

```bash
cd /d/Projects/xterm.js && NODE_PATH=./out node -e "
Buffer.poolSize = 0;
const {Terminal} = require('./out/headless/public/Terminal.js');
const {Unicode11Addon} = require('./addons/addon-unicode11/out/Unicode11Addon.js');
const {UnicodeGraphemesAddon} = require('./addons/addon-unicode-graphemes/out/UnicodeGraphemesAddon.js');
const t = new Terminal({allowProposedApi: true});
t.loadAddon(new Unicode11Addon()); t.loadAddon(new UnicodeGraphemesAddon());
const s = t._core.unicodeService;
console.log(t.unicode.versions.join(','), t.unicode.activeVersion);
s.activeVersion = '15-graphemes';
console.log(s.getStringCellWidth('\u{1F1E8}\u{1F1F3}'), s.wcwidth(0x1F600), s.getStringCellWidth('\u{1F468}\u200D\u{1F469}'));
t.dispose(); process.exit(0);"
```

Expected：第一行 `6,11,15,15-graphemes 15-graphemes`；第二行 `2 2 2`。

再跑一遍**去掉** `Buffer.poolSize = 0;` 那一行，记下第二行（核实记录 5 预期是 `2 1 …`：第一个数恰好还是 2——两个区旗各算 1 格、不连接；看第二个数）。第二个数不是 1 也照记：只说明这次池里的垃圾碰巧不同，修法照样保留。

`out/` 加载失败（`Cannot find module` 之类）时：`npm run esbuild`，把上面的 `./out` 换成 `./out-esbuild`、`/out/` 换成 `/out-esbuild/` 再试；成功的话 Task 1 的 `OUT_DIR` 默认值改成 `out-esbuild`，并在 Task 7 写回 spec §13.1。

- [ ] **Step 4: 编译并跑全量，记下基线条数**（实现 agent 做）

用「跑测试的固定套路」的全量命令（先 `lazbuild -B tests/tytests.lpi`、拷成 `tytests-term.exe`）。条数记进草稿，Task 7 签收时写进本计划末尾。**有红就停**。

- [ ] **Step 5: 【主控执行】取 Unicode 许可原文**

从 `https://www.unicode.org/license.txt` 取全文，原样存成 `tools/terminal-oracle/unicode-license.txt`（LF，文件末尾一个换行）。核对第一行是 `UNICODE LICENSE V3`；不是的话停下来，看 unicode.org 的 `https://www.unicode.org/copyright.html` 现在指向哪一份，把结论写进草稿。

- [ ] **Step 6: 【主控执行】看一眼 unicode-properties 的许可**（开工前问题 12）

`https://github.com/PerBothner/unicode-properties` 的 LICENSE。结论（许可名、是否兼容 MIT）写进草稿；不兼容时通知 Task 3 的执行者按 UAX #29 自写 `JoinRule`。

- [ ] **Step 7: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/unicode-license.txt && git commit -m "chore(terminal): the Unicode License v3 text, fetched from unicode.org

Source for the notice the width tables need: the '15' table derives from
the Unicode Character Database.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: `tools/terminal-oracle/lib-dump.js`——上游加载与共用代码

**Files:**
- Create: `tools/terminal-oracle/lib-dump.js`

- [ ] **Step 1: 写 `lib-dump.js`**

用 Write 工具（地雷 7）。完整内容：

```js
// Shared plumbing for the terminal oracle scripts: every script in this directory
// loads xterm.js through here and writes through here.
//
// Upstream: xterm.js 6.0.0, a LOCAL checkout built once (spec 13.1):
//   cd D:/Projects/xterm.js && npm ci && npm run build
// (npm ci --ignore-scripts if node-pty fails to build; we never load it.)
// XTERM_ROOT overrides the checkout path; XTERM_OUT the output folder ('out' by
// default; 'out-esbuild' if the tsgo output ever stops loading in node).
//
// Pinned: package.json version 6.0.0 and HEAD c58ea36... A different checkout, or a
// dirty one, is refused -- the port and the oracle must be the same code.
//
// THE BUFFER POOL. addon-unicode-graphemes decodes its trie with
// Buffer.from(base64) and then reads the header through new DataView(data.buffer),
// ignoring byteOffset. Node carves small Buffers out of a shared 8 KB pool, so the
// header is read from whatever else sits in the pool: every code point above the
// BMP comes back 0 and ~1.8 GB is allocated, differently from run to run. A browser
// takes the atob branch and gets it right. Buffer.poolSize = 0 before the addon is
// required makes node hand out an unpooled buffer (byteOffset 0), and
// checkTrieDecode() proves it by decoding the same bytes independently.
'use strict';
Buffer.poolSize = 0; // before ANY upstream module is required -- see above

const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const Module = require('module');

const XTERM = (process.env.XTERM_ROOT || 'D:/Projects/xterm.js').replace(/\\/g, '/');
const OUT_DIR = process.env.XTERM_OUT || 'out';
const PIN = { version: '6.0.0', commitPrefix: 'c58ea36' };
const ROOT = path.resolve(__dirname, '..', '..');
const MAX_FIXTURE_BYTES = 2 * 1024 * 1024; // spec 17.2 #8

// Every file a generator writes, repo-relative. regen-all.js fails when anything
// else changes.
const GENERATED = [
  'source/tyControls.Unicode.Width.Data.inc',
  'tests/fixtures/terminal-unicode-width.json',
  'tests/fixtures/terminal-unicode-join.json',
  'tests/fixtures/terminal-unicode-cases.json',
];

function git(args) {
  return cp.execFileSync('git', ['-C', XTERM, ...args], { encoding: 'utf8' }).trim();
}

function upstreamInfo() {
  const pkg = JSON.parse(fs.readFileSync(path.join(XTERM, 'package.json'), 'utf8'));
  const commit = git(['rev-parse', 'HEAD']);
  if (pkg.version !== PIN.version) throw new Error(`xterm.js at ${XTERM} is ${pkg.version}, pinned ${PIN.version}`);
  if (!commit.startsWith(PIN.commitPrefix)) throw new Error(`xterm.js HEAD ${commit}, pinned ${PIN.commitPrefix}`);
  const dirty = git(['status', '--porcelain', '--untracked-files=no']);
  if (dirty) throw new Error(`xterm.js checkout has local changes:\n${dirty}`);
  return { name: 'xterm.js', version: pkg.version, commit, commitDate: git(['log', '-1', '--format=%cs']) };
}

function need(rel) {
  const f = path.join(XTERM, rel);
  if (!fs.existsSync(f)) throw new Error(`missing ${f} -- run npm ci && npm run build in ${XTERM}`);
  return require(f);
}

function loadUpstream() {
  const info = upstreamInfo();
  process.env.NODE_PATH = path.join(XTERM, OUT_DIR);
  Module._initPaths(); // the addons require('common/...') through NODE_PATH
  require.resolve('common/services/UnicodeService'); // throws if the alias does not resolve
  const g = `addons/addon-unicode-graphemes/${OUT_DIR}`;
  return {
    info,
    Terminal: need(`${OUT_DIR}/headless/public/Terminal.js`).Terminal,
    Unicode11Addon: need(`addons/addon-unicode11/${OUT_DIR}/Unicode11Addon.js`).Unicode11Addon,
    UnicodeGraphemesAddon: need(`${g}/UnicodeGraphemesAddon.js`).UnicodeGraphemesAddon,
    UC: need(`${g}/third-party/UnicodeProperties.js`),
    UnicodeTrie: need(`${g}/third-party/unicode-trie.js`).default,
    propsSourceFile: path.join(XTERM, g, 'third-party', 'UnicodeProperties.js'),
  };
}

// A headless terminal with all four providers registered.
function makeTerminal(up) {
  const term = new up.Terminal({ allowProposedApi: true, cols: 80, rows: 24 });
  term.loadAddon(new up.Unicode11Addon());
  term.loadAddon(new up.UnicodeGraphemesAddon());
  const svc = term._core.unicodeService;
  const want = ['6', '11', '15', '15-graphemes'];
  if (svc.versions.join(',') !== want.join(',')) throw new Error('providers: ' + svc.versions.join(','));
  return term;
}

// The six variants every table and fixture is written for. 6 and 11 have no
// ambiguous data (spec 4.3), so they appear once.
const VARIANTS = [
  { id: '6', version: '6', ambiguousWide: false },
  { id: '11', version: '11', ambiguousWide: false },
  { id: '15', version: '15', ambiguousWide: false },
  { id: '15+amb', version: '15', ambiguousWide: true },
  { id: '15-graphemes', version: '15-graphemes', ambiguousWide: false },
  { id: '15-graphemes+amb', version: '15-graphemes', ambiguousWide: true },
];

// Make VARIANT active; returns the UnicodeService.
function useVariant(term, variant) {
  const svc = term._core.unicodeService;
  svc.activeVersion = variant.version;
  for (const v of ['15', '15-graphemes']) svc._providers[v].ambiguousCharsAreWide = variant.ambiguousWide;
  return svc;
}

// fn over 0..0x10FFFF as a flat run list [start0, value0, start1, value1, ...].
function runsOf(fn) {
  const out = [];
  let prev;
  for (let c = 0; c <= 0x10FFFF; c++) {
    const v = fn(c);
    if (!Number.isInteger(v) || v < 0 || v > 0x7FFFFFFF) throw new Error(`value ${v} at U+${c.toString(16)}`);
    if (c === 0 || v !== prev) { out.push(c, v); prev = v; }
  }
  return out;
}

// Decode the trie a second time from a fresh, unpooled copy of the same bytes and
// compare every code point with what the addon's own getInfo answers.
function checkTrieDecode(up) {
  const src = fs.readFileSync(up.propsSourceFile, 'utf8');
  const m = src.match(/trieRaw\s*=\s*"([A-Za-z0-9+/=]+)"/);
  if (!m) throw new Error('trieRaw not found in ' + up.propsSourceFile);
  const bytes = new Uint8Array(Buffer.from(m[1], 'base64')); // a copy: own ArrayBuffer, offset 0
  const trie = new up.UnicodeTrie(bytes);
  for (let c = 0; c <= 0x10FFFF; c++) {
    if (trie.get(c) !== up.UC.getInfo(c)) {
      throw new Error(`the addon's trie disagrees with a clean decode at U+${c.toString(16)} -- the Buffer pool fix is not in effect`);
    }
  }
  if (up.UC.getInfo(0x1F600) >> 4 !== 3) throw new Error('U+1F600 is not wide in the 15 table');
}

function writeGenerated(rel, text) {
  if (!GENERATED.includes(rel)) throw new Error(rel + ' is not listed in GENERATED');
  fs.writeFileSync(path.join(ROOT, rel), text);
  console.log('wrote', rel, text.length, 'bytes');
}

function writeFixture(name, obj) {
  const text = JSON.stringify(obj) + '\n';
  if (text.length > MAX_FIXTURE_BYTES) throw new Error(`${name}: ${text.length} bytes, cap ${MAX_FIXTURE_BYTES}`);
  writeGenerated(`tests/fixtures/${name}`, text);
}

module.exports = {
  XTERM, PIN, ROOT, GENERATED, VARIANTS,
  upstreamInfo, loadUpstream, makeTerminal, useVariant, runsOf, checkTrieDecode,
  writeGenerated, writeFixture,
};
```

- [ ] **Step 2: 冒烟**（需要 Task 0 Step 2 已经做完）

```bash
cd /d/Projects/ty-3.1 && node -e "const L=require('./tools/terminal-oracle/lib-dump.js'); const up=L.loadUpstream(); L.checkTrieDecode(up); const t=L.makeTerminal(up); console.log(up.info, L.useVariant(t, L.VARIANTS[4]).getStringCellWidth('\u{1F1E8}\u{1F1F3}')); t.dispose(); process.exit(0)"
```

Expected：打印 `{ name: 'xterm.js', version: '6.0.0', commit: 'c58ea36…'(40 位), commitDate: '…' } 2`，没有异常。

**判据 / 变异（期末做，JS 侧）：**

| # | 变异 | 必须 |
|---|---|---|
| J1 | 删掉第一行 `Buffer.poolSize = 0;` | Step 2 的命令抛「the Buffer pool fix is not in effect」或「U+1F600 is not wide」 |
| J2 | `PIN.commitPrefix` 改成 `'0000000'` | 抛 `pinned` |

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/lib-dump.js && git commit -m "feat(terminal): oracle plumbing that loads the pinned xterm.js build

Loads the local 6.0.0 checkout through NODE_PATH set in-process, refuses a
different or dirty checkout, and turns node's Buffer pool off before the
graphemes addon decodes its trie: pooled, the addon reads its header from
the wrong offset and every code point above the BMP comes back 0. A clean
second decode is compared code point by code point to prove the fix holds.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `gen-unicode-tables.js` → `tyControls.Unicode.Width.Data.inc`

**Files:**
- Create: `tools/terminal-oracle/gen-unicode-tables.js`
- Create (generated): `source/tyControls.Unicode.Width.Data.inc`

- [ ] **Step 1: 写脚本**（Write 工具）

```js
// Writes source/tyControls.Unicode.Width.Data.inc: the three width tables of
// tyControls.Unicode.Width, dumped from xterm.js itself (spec 4.2).
//
//   '6'  UnicodeV6.wcwidth    src/common/input/UnicodeV6.ts           (core)
//   '11' UnicodeV11.wcwidth   addons/addon-unicode11/src/UnicodeV11.ts
//   '15' UC.getInfo raw value addons/addon-unicode-graphemes/src/third-party/UnicodeProperties.ts
//
// For 6 and 11 the width IS the table; for 15 the raw trie value is stored and the
// Pascal unit derives wcwidth / charProperties from it the way the provider does,
// so those two stay a port and not a dump.
//
// Upstream path, pin and the Buffer-pool fix: lib-dump.js. The generated header
// names the upstream version, commit and commit DATE -- never the wall clock and
// never the local path, so a rerun on any machine is byte-identical (spec 13.5 #7).
//
//   node tools/terminal-oracle/gen-unicode-tables.js
'use strict';
const fs = require('fs');
const path = require('path');
const L = require('./lib-dump.js');

const up = L.loadUpstream();
L.checkTrieDecode(up);
const term = L.makeTerminal(up);
const providers = term._core.unicodeService._providers;

const v6 = L.runsOf(c => providers['6'].wcwidth(c));
const v11 = L.runsOf(c => providers['11'].wcwidth(c));
const v15 = L.runsOf(c => up.UC.getInfo(c));
for (const [n, r] of [['6', v6], ['11', v11], ['15', v15]]) {
  for (let i = 1; i < r.length; i += 2) if (r[i] > 255) throw new Error(`${n}: value ${r[i]} does not fit a Byte`);
}

// Beyond U+10FFFF: one answer per table, the same for every probe (checked).
const PROBES = [0x110000, 0x1FFFFF, 0x7FFFFFFF];
function oneAnswer(name, f) {
  const a = PROBES.map(f);
  if (a.some(x => x !== a[0])) throw new Error(`${name}: out-of-range answers differ: ${a}`);
  return a[0];
}
const oor6 = oneAnswer('6', c => providers['6'].wcwidth(c));
const oor11 = oneAnswer('11', c => providers['11'].wcwidth(c));
const oor15 = oneAnswer('15', c => up.UC.getInfo(c));

function firstLine(rel) {
  return fs.readFileSync(path.join(L.XTERM, rel), 'utf8').split(/\r?\n/)[0].trim();
}
const copyright = [
  firstLine('LICENSE'),
  fs.readFileSync(path.join(L.XTERM, 'LICENSE'), 'utf8').split(/\r?\n/)[1].trim(),
  fs.readFileSync(path.join(L.XTERM, 'LICENSE'), 'utf8').split(/\r?\n/)[2].trim(),
  firstLine('addons/addon-unicode11/LICENSE'),
  firstLine('addons/addon-unicode-graphemes/LICENSE'),
];

const i = up.info;
const header = [
  `GENERATED by tools/terminal-oracle/gen-unicode-tables.js -- do NOT edit by hand;`,
  `change the script and rerun it. Upstream: ${i.name} ${i.version}, commit ${i.commit}`,
  `(${i.commitDate}). Each table is a run list: Start[k] is the first code point of`,
  `run k, the value holds up to Start[k+1]-1 (the last run to U+10FFFF).`,
  ``,
  `  '6'  wcwidth of src/common/input/UnicodeV6.ts`,
  `  '11' wcwidth of addons/addon-unicode11/src/UnicodeV11.ts`,
  `  '15' raw getInfo of addons/addon-unicode-graphemes/src/third-party/UnicodeProperties.ts,`,
  `       decoded with node's Buffer pool off (see lib-dump.js)`,
  ``,
  `Derived from xterm.js, MIT:`,
  ...copyright.map(s => '  ' + s),
  `The '15' table derives from the Unicode Character Database, Unicode License v3.`,
  `Full texts: THIRD-PARTY-NOTICES.md.`,
];
for (const line of header) if (/[{}]/.test(line)) throw new Error('a brace in the header would open a nested comment: ' + line);

function arr(name, type, values) {
  const hexW = type === 'Cardinal' ? 6 : 2;
  const items = values.map(v => '$' + v.toString(16).toUpperCase().padStart(hexW, '0'));
  const lines = [];
  for (let k = 0; k < items.length; k += 12) lines.push('    ' + items.slice(k, k + 12).join(', '));
  return `  ${name}: array[0..${values.length - 1}] of ${type} = (\n${lines.join(',\n')});\n`;
}
const starts = r => r.filter((_, k) => k % 2 === 0);
const values = r => r.filter((_, k) => k % 2 === 1);

let out = '{ ' + header.join('\n  ') + ' }\n\nconst\n';
out += arr('TyUniV6Start', 'Cardinal', starts(v6)) + arr('TyUniV6Width', 'Byte', values(v6));
out += arr('TyUniV11Start', 'Cardinal', starts(v11)) + arr('TyUniV11Width', 'Byte', values(v11));
out += arr('TyUniV15Start', 'Cardinal', starts(v15)) + arr('TyUniV15Info', 'Byte', values(v15));
out += `  TyUniV6OutOfRange = ${oor6};\n  TyUniV11OutOfRange = ${oor11};\n  TyUniV15OutOfRangeInfo = ${oor15};\n`;

L.writeGenerated('source/tyControls.Unicode.Width.Data.inc', out);
console.log('runs: 6', v6.length / 2, '11', v11.length / 2, '15', v15.length / 2);
term.dispose();
process.exit(0);
```

- [ ] **Step 2: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/gen-unicode-tables.js && head -30 source/tyControls.Unicode.Width.Data.inc && node tools/terminal-oracle/gen-unicode-tables.js > /dev/null && git status --short
```

Expected：`runs: 6 309 11 888 15 2269`（核实记录 6）；头部没有本机路径、没有当天日期；三个越界常量是 `1 / 1 / 0`（核实记录 11）；第二次运行后 `git status --short` 只有这一个 `??` 新文件（两次输出相同）。区间数和核实记录不一致时**停下来**查（最可能是 Buffer 池修法没生效）。

**判据 / 变异（期末做）：** 见 Task 5 的 U1、U17；J1 也会让本脚本中止。

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/gen-unicode-tables.js source/tyControls.Unicode.Width.Data.inc && git commit -m "feat(terminal): width tables dumped from xterm.js 6.0.0

Run lists for the '6' and '11' wcwidth and the raw '15' trie value over
every code point, written as an include for tyControls.Unicode.Width. The
header carries the upstream commit and its date, not the wall clock, so a
rerun is byte-identical.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `tyControls.Unicode.Width` 单元

**Files:**
- Create: `source/tyControls.Unicode.Width.pas`
- Modify: `tycontrols.lpk`（`<Files>` 末尾，`source/tyControls.AdvanceChart.pas` 那一项之后）

- [ ] **Step 1: 写单元**

单元头（照 spec §14）：移植自 xterm.js 6.0.0（commit `c58ea3637f39` 全 40 位由 `.inc` 头部给出，单元头写前 12 位）；源文件 `src/common/input/UnicodeV6.ts`、`addons/addon-unicode11/src/UnicodeV11.ts`、`addons/addon-unicode-graphemes/src/UnicodeGraphemeProvider.ts`、`…/third-party/UnicodeProperties.ts`（规则部分，出处 unicode-properties，开工前问题 12）、`src/common/services/UnicodeService.ts`；版权行照抄 `xterm:LICENSE:1-3` 和两个 addon 的 `LICENSE:1`；「MIT，全文见 THIRD-PARTY-NOTICES.md」。再用一段话写清三个不直观的地方：核实记录 8（`15` 不连接）、10（15 下控制字符宽 1）、开工前问题 10（WTF-8）。

interface 段就是「接口清单」那一块，`uses` 只有 `SysUtils`（spec §2.1）。implementation 段：

```pascal
implementation

{$I tyControls.Unicode.Width.Data.inc}

const
  { UnicodeProperties.ts: GRAPHEME_BREAK_* and CHARWIDTH_* }
  GB_MASK = $F;
  GB_Other = 0; GB_Prepend = 1; GB_Extend = 2; GB_RegionalIndicator = 3;
  GB_SpacingMark = 4; GB_HangulL = 5; GB_HangulV = 6; GB_HangulT = 7;
  GB_HangulLV = 8; GB_HangulLVT = 9; GB_ZWJ = 10; GB_ExtPic = 11;
  GB_SawRegionalPair = 32;   { only ever returned by ShouldJoin15 }
  CW_MASK = $30; CW_SHIFT = 4;
  CW_Wide = 3;
  MaxCodepoint = $10FFFF;

var
  GBmp6, GBmp11: array[0..$FFFF] of Byte;   { filled in initialization (spec 17.2 #5) }

{ Index of the run holding ACp: the last k with AStarts[k] <= ACp. AStarts[0] is 0. }
function RunIndex(const AStarts: array of Cardinal; ACp: Cardinal): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(AStarts);
  while lo < hi do
  begin
    mid := (lo + hi + 1) shr 1;
    if AStarts[mid] <= ACp then
      lo := mid
    else
      hi := mid - 1;
  end;
  Result := lo;
end;

{ UnicodeService.createPropertyValue: state masked to 24 bits -- it is negative for
  "no join" under 15-graphemes. }
function MakeProps(AState, AWidth: Integer; AShouldJoin: Boolean): TTyUnicodeCharProps;
begin
  Result := TTyUnicodeCharProps(((Cardinal(AState) and $FFFFFF) shl 3)
    or ((Cardinal(AWidth) and 3) shl 1) or Cardinal(Ord(AShouldJoin)));
end;

function TyUnicodePropsWidth(AProps: TTyUnicodeCharProps): Integer;
begin
  Result := (AProps shr 1) and 3;
end;

function TyUnicodePropsShouldJoin(AProps: TTyUnicodeCharProps): Boolean;
begin
  Result := (AProps and 1) <> 0;
end;

function TyUnicodePropsKind(AProps: TTyUnicodeCharProps): Cardinal;
begin
  Result := AProps shr 3;
end;

{ ---- 6 and 11: UnicodeV6.ts / UnicodeV11.ts ---- }

function LegacyWcWidth(ACp: Cardinal; AVersion: TTyUnicodeVersion): Integer;
begin
  if ACp > MaxCodepoint then
  begin
    if AVersion = tuv6 then Exit(TyUniV6OutOfRange) else Exit(TyUniV11OutOfRange);
  end;
  if ACp <= $FFFF then
  begin
    if AVersion = tuv6 then Exit(GBmp6[ACp]) else Exit(GBmp11[ACp]);
  end;
  if AVersion = tuv6 then
    Result := TyUniV6Width[RunIndex(TyUniV6Start, ACp)]
  else
    Result := TyUniV11Width[RunIndex(TyUniV11Start, ACp)];
end;

function LegacyCharProps(ACp: Cardinal; APreceding: TTyUnicodeCharProps;
  AVersion: TTyUnicodeVersion): TTyUnicodeCharProps;
var
  width, oldWidth: Integer;
  shouldJoin: Boolean;
begin
  width := LegacyWcWidth(ACp, AVersion);
  shouldJoin := (width = 0) and (APreceding <> 0);
  if shouldJoin then
  begin
    oldWidth := TyUnicodePropsWidth(APreceding);
    if oldWidth = 0 then
      shouldJoin := False
    else if oldWidth > width then
      width := oldWidth;
  end;
  Result := MakeProps(0, width, shouldJoin);
end;

{ ---- 15 and 15-graphemes: UnicodeGraphemeProvider.ts + UnicodeProperties.ts ---- }

function Info15(ACp: Cardinal): Cardinal;
begin
  if ACp > MaxCodepoint then Exit(TyUniV15OutOfRangeInfo);
  Result := TyUniV15Info[RunIndex(TyUniV15Start, ACp)];
end;

function WcWidth15(ACp: Cardinal; AAmbiguousWide: Boolean): Integer;
var
  info, w, kind: Cardinal;
begin
  info := Info15(ACp);
  w := (info and CW_MASK) shr CW_SHIFT;
  kind := info and GB_MASK;
  if (kind = GB_Extend) or (kind = GB_Prepend) then Exit(0);
  if (w >= 2) and ((w = CW_Wide) or AAmbiguousWide) then Exit(2);
  Result := 1;
end;

{ UnicodeProperties.ts _shouldJoin: GB6-GB13, simplified upstream (no GB9c; GB11
  looks only at the code point before). }
function JoinRule(ABefore, AAfter: Cardinal): Boolean;
begin
  if (ABefore >= GB_HangulL) and (ABefore <= GB_HangulLVT) then
  begin
    if (ABefore = GB_HangulL) and ((AAfter = GB_HangulL) or (AAfter = GB_HangulV)
      or (AAfter = GB_HangulLV) or (AAfter = GB_HangulLVT)) then Exit(True);      { GB6 }
    if ((ABefore = GB_HangulLV) or (ABefore = GB_HangulV))
      and ((AAfter = GB_HangulV) or (AAfter = GB_HangulT)) then Exit(True);        { GB7 }
    if ((ABefore = GB_HangulLVT) or (ABefore = GB_HangulT))
      and (AAfter = GB_HangulT) then Exit(True);                                    { GB8 }
  end;
  if (AAfter = GB_Extend) or (AAfter = GB_ZWJ) or (ABefore = GB_Prepend)
    or (AAfter = GB_SpacingMark) then Exit(True);                                   { GB9, GB9a, GB9b }
  if (ABefore = GB_ZWJ) and (AAfter = GB_ExtPic) then Exit(True);                   { GB11 }
  if (AAfter = GB_RegionalIndicator) and (ABefore = GB_RegionalIndicator) then
    Exit(True);                                                                     { GB12, GB13 }
  Result := False;
end;

{ UnicodeProperties.ts shouldJoin: > 0 joins, <= 0 breaks. }
function ShouldJoin15(ABeforeState, AAfterInfo: Cardinal): Integer;
var
  b, a: Cardinal;
begin
  b := ABeforeState and GB_MASK;
  a := AAfterInfo and GB_MASK;
  if JoinRule(b, a) then
  begin
    if a = GB_RegionalIndicator then
      Result := GB_SawRegionalPair
    else
      Result := Integer(a) + 16;
  end
  else
    Result := Integer(a) - 16;
end;

function CharProps15(ACp: Cardinal; APreceding: TTyUnicodeCharProps;
  AGraphemes, AAmbiguousWide: Boolean): TTyUnicodeCharProps;
var
  info, w, oldWidth: Integer;
  wi: Cardinal;
  shouldJoin: Boolean;
begin
  { the ASCII fast path, valid only while the preceding kind is Other (:25-30) }
  if (ACp >= 32) and (ACp < 127) and ((APreceding shr 3) = 0) then
    Exit(MakeProps(GB_Other, 1, False));
  info := Integer(Info15(ACp));
  wi := (Cardinal(info) and CW_MASK) shr CW_SHIFT;
  if wi >= 2 then
  begin
    { emoji presentation selector U+FE0F counts as wide (:37) }
    if (wi = CW_Wide) or AAmbiguousWide or (ACp = $FE0F) then w := 2 else w := 1;
  end
  else
    w := 1;
  shouldJoin := False;
  if APreceding <> 0 then
  begin
    oldWidth := TyUnicodePropsWidth(APreceding);
    if AGraphemes then
      info := ShouldJoin15(TyUnicodePropsKind(APreceding), Cardinal(info))
    else if w = 0 then   { never true: w is 1 or 2 here. Upstream's line, kept as is (:46). }
      info := 1
    else
      info := 0;
    shouldJoin := info > 0;
    if shouldJoin then
    begin
      if oldWidth > w then
        w := oldWidth
      else if info = GB_SawRegionalPair then
        w := 2;
    end;
  end;
  Result := MakeProps(info, w, shouldJoin);
end;

{ ---- public ---- }

function TyUnicodeWcWidth(ACodepoint: Cardinal; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;
begin
  case AVersion of
    tuv6, tuv11: Result := LegacyWcWidth(ACodepoint, AVersion);
  else
    Result := WcWidth15(ACodepoint, AAmbiguousWide);
  end;
end;

function TyUnicodeCharProperties(ACodepoint: Cardinal; APreceding: TTyUnicodeCharProps;
  AVersion: TTyUnicodeVersion; AAmbiguousWide: Boolean): TTyUnicodeCharProps;
begin
  case AVersion of
    tuv6, tuv11: Result := LegacyCharProps(ACodepoint, APreceding, AVersion);
    tuv15: Result := CharProps15(ACodepoint, APreceding, False, AAmbiguousWide);
  else
    Result := CharProps15(ACodepoint, APreceding, True, AAmbiguousWide);
  end;
end;

{ UTF-8 -> UTF-16 code units. WTF-8: a three-byte sequence for U+D800..U+DFFF gives
  that lone surrogate, so upstream's UCS-2 fallback is reachable from UTF-8. Any other
  malformed byte gives one U+FFFD and consumes that byte only. }
function Wtf8ToUnits(const S: string): UnicodeString;
var
  i, j, k, n, need: Integer;
  b: Byte;
  cp, lo, hi: Cardinal;
begin
  n := Length(S);
  SetLength(Result, n);   { never more units than bytes }
  i := 1;
  k := 0;
  while i <= n do
  begin
    b := Ord(S[i]);
    lo := $80;
    hi := $BF;
    cp := 0;
    case b of
      $00..$7F: begin need := 0; cp := b; end;
      $C2..$DF: begin need := 1; cp := b and $1F; end;
      $E0:      begin need := 2; cp := b and $0F; lo := $A0; end;
      $E1..$EF: begin need := 2; cp := b and $0F; end;
      $F0:      begin need := 3; cp := b and $07; lo := $90; end;
      $F1..$F3: begin need := 3; cp := b and $07; end;
      $F4:      begin need := 3; cp := b and $07; hi := $8F; end;
    else
      need := -1;
    end;
    if (need > 0) and (i + need > n) then need := -1;
    if need > 0 then
      for j := 1 to need do
      begin
        b := Ord(S[i + j]);
        if ((j = 1) and ((b < lo) or (b > hi))) or ((j > 1) and ((b < $80) or (b > $BF))) then
        begin
          need := -1;
          Break;
        end;
        cp := (cp shl 6) or (b and $3F);
      end;
    if need < 0 then
    begin
      Inc(k);
      Result[k] := WideChar($FFFD);
      Inc(i);
      Continue;
    end;
    if cp >= $10000 then
    begin
      Dec(cp, $10000);
      Inc(k); Result[k] := WideChar($D800 + (cp shr 10));
      Inc(k); Result[k] := WideChar($DC00 + (cp and $3FF));
    end
    else
    begin
      Inc(k);
      Result[k] := WideChar(cp);
    end;
    Inc(i, need + 1);
  end;
  SetLength(Result, k);
end;

{ UnicodeService.getStringCellWidth (:67-101), line for line over UTF-16 units. }
function TyUnicodeStringCellWidth(const AUtf8: string; AVersion: TTyUnicodeVersion;
  AAmbiguousWide: Boolean): Integer;
var
  u: UnicodeString;
  i, n, chWidth: Integer;
  code, second: Cardinal;
  preceding, current: TTyUnicodeCharProps;
begin
  u := Wtf8ToUnits(AUtf8);
  n := Length(u);
  Result := 0;
  preceding := 0;
  i := 1;
  while i <= n do
  begin
    code := Ord(u[i]);
    if (code >= $D800) and (code <= $DBFF) then
    begin
      Inc(i);
      if i > n then
        Exit(Result + TyUnicodeWcWidth(code, AVersion, AAmbiguousWide));
      second := Ord(u[i]);
      if (second >= $DC00) and (second <= $DFFF) then
        code := (code - $D800) * $400 + second - $DC00 + $10000
      else
        Inc(Result, TyUnicodeWcWidth(second, AVersion, AAmbiguousWide));
    end;
    current := TyUnicodeCharProperties(code, preceding, AVersion, AAmbiguousWide);
    chWidth := TyUnicodePropsWidth(current);
    if TyUnicodePropsShouldJoin(current) then
      Dec(chWidth, TyUnicodePropsWidth(preceding));
    Inc(Result, chWidth);
    preceding := current;
    Inc(i);
  end;
end;

function TyUnicodeVersionName(AVersion: TTyUnicodeVersion): string;
begin
  case AVersion of
    tuv6: Result := '6';
    tuv11: Result := '11';
    tuv15: Result := '15';
  else
    Result := '15-graphemes';
  end;
end;

procedure ExpandBmp(const AStarts: array of Cardinal; const AWidths: array of Byte;
  var ATable: array of Byte);
var
  r: Integer;
  c, stop: Cardinal;
begin
  for r := 0 to High(AStarts) do
  begin
    if AStarts[r] > $FFFF then Break;
    if r < High(AStarts) then stop := AStarts[r + 1] else stop := MaxCodepoint + 1;
    if stop > $10000 then stop := $10000;
    for c := AStarts[r] to stop - 1 do
      ATable[c] := AWidths[r];
  end;
end;

initialization
  ExpandBmp(TyUniV6Start, TyUniV6Width, GBmp6);
  ExpandBmp(TyUniV11Start, TyUniV11Width, GBmp11);
end.
```

执行者要自己核的三处（照上游源码逐行对，别凭这里的代码）：`CharProps15` 对 `UnicodeGraphemeProvider.ts:24-56`；`LegacyCharProps` 对 `UnicodeV6.ts:132-145`；`TyUnicodeStringCellWidth` 对 `UnicodeService.ts:67-101`。对不上以上游为准，并在提交信息里写一句。

- [ ] **Step 2: 加进 `.lpk`**

在 `tycontrols.lpk` 的 `<Files>` 里 `source/tyControls.AdvanceChart.pas` 那个 `<Item>` 之后加（用编辑工具，地雷 8）：

```xml
      <Item>
        <Filename Value="source/tyControls.Unicode.Width.pas"/>
        <UnitName Value="tyControls.Unicode.Width"/>
      </Item>
```

`.inc` 不加（spec §2.1）。

**判据 / 变异**：本单元的判据就是 Task 5 的两个测试类，变异表（U1–U20）也在 Task 5，期末做。

- [ ] **Step 3: 提交**（不编译，编译错误留给 Task 7 集中修）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Unicode.Width.pas tycontrols.lpk && git commit -m "feat(terminal): tyControls.Unicode.Width, character widths ported from xterm.js

wcwidth, the grapheme join state and string cell width for the four
upstream versions (6, 11, 15, 15-graphemes), with ambiguous width for the
15 tables. Pure functions over the dumped run tables; 6 and 11 expand their
BMP part into byte tables once, as upstream does. UTF-8 input carries lone
surrogates as WTF-8 so upstream's UCS-2 fallback stays reachable.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `unicode-cases.js` → 三份夹具；`regen-all.js`

**Files:**
- Create: `tools/terminal-oracle/cases/unicode.js`
- Create: `tools/terminal-oracle/unicode-cases.js`
- Create: `tools/terminal-oracle/regen-all.js`
- Create (generated): `tests/fixtures/terminal-unicode-width.json`、`terminal-unicode-join.json`、`terminal-unicode-cases.json`

- [ ] **Step 1: 写 `cases/unicode.js`**（只有输入，spec §13.2；Write 工具）

导出 `{ sequences, strings, extraReps }`。`sequences` 每项 `{ id, codepoints }`，`strings` 每项 `{ id, units }`（UTF-16 单元数组——JSON 装不下孤立代理，所以不用字符串）。至少包含下表（id 用表里的名字）：

| id | 码位 / 单元 | 守的是 |
|---|---|---|
| `combining-a-acute` | 61 301 | 组合符接窄字符 |
| `combining-two-marks` | 65 301 302 | 连续两个组合符 |
| `combining-after-wide` | 4E00 301 | 宽字符后的组合符保持宽 2（`oldWidth > width`） |
| `combining-at-start` | 301 | 没有前驱 |
| `hangul-l-v-t` | 1100 1161 11A8 | GB6、GB7 |
| `hangul-lv-t` | AC00 11A8 | GB7 |
| `hangul-lvt-t` | AC01 11A8 | GB8 |
| `hangul-l-l` | 1100 1100 | GB6 |
| `hangul-t-v-breaks` | 11A8 1161 | 不连 |
| `ri-pair` | 1F1E8 1F1F3 | 区旗对强制宽 2 |
| `ri-three` | 1F1E8 1F1F3 1F1FA | 第三个另起 |
| `ri-four` | 1F1E8 1F1F3 1F1FA 1F1F8 | 两对 |
| `zwj-family` | 1F468 200D 1F469 200D 1F467 | GB9 + GB11 |
| `zwj-then-letter` | 1F468 200D 41 | ZWJ 后不是 ExtPic |
| `vs16-smile` | 263A FE0F | VS16 强制宽 |
| `vs15-smile` | 263A FE0E | VS15 |
| `vs16-heart` | 2764 FE0F | |
| `keycap-one` | 31 FE0F 20E3 | ASCII 起头的表情序列 |
| `prepend-arabic-digit` | 600 661 | GB9a |
| `prepend-then-ascii` | 600 61 | ASCII 快路径的前驱条件（地雷 4） |
| `spacing-mark` | 915 93F | GB9b |
| `emoji-modifier` | 1F44D 1F3FD | 肤色修饰 |
| `ambiguous-letters` | 3B1 2026 FFFD E000 | ambiguous 宽的四个例子 |
| `controls` | 0 7 1B 7F 9F | 控制字符（核实记录 10） |
| `surrogate-codepoints` | D800 DBFF DC00 DFFF | 作为码位直接送进 `charProperties` |
| `soft-hyphen` | AD 61 | |
| `plane-16` | 10FFFD 10FFFF | 最后一个区间 |

`strings`（单元数组；`gscw` 是上游 `getStringCellWidth`）：`empty` []、`ascii` 61 62 63、`cjk` 4E2D 6587、`e-acute` 65 301、`family` D83D DC68 200D D83D DC69 200D D83D DC67、`flags-odd` D83C DDE8 D83C DDF3 D83C DDFA、`smile-vs16` 263A FE0F、`smile-vs15` 263A FE0E、`ellipsis` 2026、`lone-high-at-end` 61 D83D、`high-then-letter` D83D 61、`high-high-low` D83D D83D DE00、`lone-low` DE00 61、`low-then-high` DE00 D83D、`two-fffd` FFFD FFFD、`hangul` 1100 1161 11A8、`prepend-ascii` 600 61。

`extraReps`：`[0x41, 0x200D, 0xFE0E, 0xFE0F, 0x1F1E6, 0x4E00, 0x1F600, 0x301]`。

- [ ] **Step 2: 写 `unicode-cases.js`**（Write 工具）

要求（照写即可，代码结构执行者定）：

1. 头部注释照 Task 2 的写法：生成什么、上游是谁、怎么跑（`node tools/terminal-oracle/unicode-cases.js`）、三份夹具的格式（就是下面第 4–6 条）。
2. `const L = require('./lib-dump.js'); const up = L.loadUpstream(); L.checkTrieDecode(up); const term = L.makeTerminal(up);`——**只**经 `lib-dump.js` 加载（地雷 1）。
3. 每个变体都用 `svc = L.useVariant(term, v)`，然后只调 `svc.wcwidth`、`svc.charProperties`、`svc.getStringCellWidth`——spec §4.5 要求问的是 `_core.unicodeService`，不是 provider。
4. **`terminal-unicode-width.json`**：
   ```
   { "upstream": up.info, "generator": "tools/terminal-oracle/unicode-cases.js",
     "variants": L.VARIANTS 原样（id / version / ambiguousWide），
     "wcwidth": { "<variant id>": runsOf(c => svc.wcwidth(c)), ... 6 个 },
     "outOfRange": { "codepoints": [1114112, 2097151, 2147483647],
                     "wcwidth": { "<id>": [3 个] }, "props0": { "<id>": [charProperties(c, 0) × 3] } } }
   ```
5. **`terminal-unicode-join.json`**：
   ```
   { "upstream", "generator", "variants",
     "preceding": [0, 2, 4, 8, P(200D), P(1F1E6), P(600), P(1100), P(1F600)],
     "props": { "<id>": [ runsOf(c => svc.charProperties(c, preceding[0])), ... 9 个 ] } }
   ```
   `P(x)` = 在 `15-graphemes`（ambiguous 窄）下 `charProperties(x, 0)`，在切变体之前先算好，所有变体共用同一组数（任意打包值都是合法输入）。实跑值是 `0x52, 0x9a, 0xa, 0x1ac, 0x1dc`（核实记录用的 `p8.mts`）；生成时断言相等，不等就中止（说明上游表或加载方式变了）。`8` 是「state 1、宽 0、不连」，专门打到 `LegacyCharProps` 的 `oldWidth = 0` 分支。
6. **`terminal-unicode-cases.json`**：
   ```
   { "upstream", "generator", "variants",
     "sequences": [ { "id", "source": "hand", "codepoints": [...],
                      "props": { "<id>": [逐步 charProperties，前驱从 0 起、每步取上一步结果] } } ],
     "reps": [代表码位],
     "pairs": { "<id>": [ reps 两两 (i, j) 按字典序，每对记 2 个逐步 props，平铺 ] },
     "triples": { "15-graphemes": [...], "15-graphemes+amb": [...] },   // (i, j, k) 字典序，每组 3 个，平铺
     "strings": [ { "id", "source": "hand", "units": [...], "width": { "<id>": gscw } } ] }
   ```
   `reps` = 对 0..0x10FFFF 取 `up.UC.getInfo`，每个不同的值取**最小**的那个码位（20 个），再并上 `extraReps`，去重、升序。三连只给 `15-graphemes` 的两个变体（字形簇状态只在那里有意义，也控制体积）。
7. 输出前数一下：三份夹具字节数、`reps` 个数、`pairs` / `triples` 条数，打印出来；`writeFixture` 超 2MB 会自己报错。
8. 末尾 `term.dispose(); process.exit(0);`。

- [ ] **Step 3: 写 `regen-all.js`**（Write 工具）

```js
// Reruns every oracle generator and checks the working tree afterwards: only the
// files lib-dump.js lists in GENERATED may have changed, and with --expect-clean
// not even those (spec 4.2: a rerun against the same upstream must leave
// `git diff` empty).
//
//   node tools/terminal-oracle/regen-all.js [--expect-clean]
'use strict';
const cp = require('child_process');
const path = require('path');
const L = require('./lib-dump.js');

const SCRIPTS = ['gen-unicode-tables.js', 'unicode-cases.js'];
for (const s of SCRIPTS) {
  console.log('==', s);
  cp.execFileSync(process.execPath, [path.join(__dirname, s)], { stdio: 'inherit' });
}
const changed = cp.execFileSync('git', ['-C', L.ROOT, 'status', '--porcelain'], { encoding: 'utf8' })
  .split(/\r?\n/).filter(Boolean).map(l => l.slice(3).replace(/\\/g, '/'));
const stray = changed.filter(f => !L.GENERATED.includes(f));
if (stray.length) { console.error('changed but not a generated file:\n  ' + stray.join('\n  ')); process.exit(1); }
if (process.argv.includes('--expect-clean') && changed.length) {
  console.error('the rerun changed:\n  ' + changed.join('\n  ')); process.exit(1);
}
console.log(changed.length ? 'changed (generated only): ' + changed.join(', ') : 'clean');
```

- [ ] **Step 4: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/unicode-cases.js && ls -l tests/fixtures/terminal-unicode-*.json
```

Expected：三份夹具都 ≤ 2MB（预估：width 约 60KB、join 约 1.2MB、cases 约 1MB）；打印的 `reps` 个数不超过 28（20 个取值代表 + 8 个 `extraReps`，去重后）。

- [ ] **Step 5: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/cases/unicode.js tools/terminal-oracle/unicode-cases.js tools/terminal-oracle/regen-all.js tests/fixtures/terminal-unicode-width.json tests/fixtures/terminal-unicode-join.json tests/fixtures/terminal-unicode-cases.json && git commit -m "test(terminal): upstream answers for every code point, join state and string width

unicode-cases.js asks xterm.js's own UnicodeService, per variant: wcwidth
over all code points as runs; charProperties over all code points after
nine preceding states; hand-written sequences (combining marks, Hangul
L/V/T, flag pairs, ZWJ emoji, VS15/VS16, Prepend); every pair of
representative code points, and every triple under 15-graphemes; and
getStringCellWidth including lone surrogates. regen-all.js reruns the
generators and fails if anything but a listed output changed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: 重跑确认可复现**（提交之后跑，否则本任务的新脚本会被当成「不是生成物的改动」）

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/regen-all.js --expect-clean
```

Expected：`clean`（`.inc` 和三份夹具重新生成后与已提交的字节相同）。不 clean 就是生成不可复现（地雷 12），修脚本、重新生成、再提交一次（`fix(terminal): ...`），直到 clean。

---

### Task 5: `tests/test.unicode.width.pas`

**Files:**
- Create: `tests/test.unicode.width.pas`
- Modify: `tests/tytests.lpr`（uses 里 `test.advancechart,` 之后加 `test.unicode.width,`）

单元头注释照 `D:/Projects/ty-advchart/tests/test.advchart.bargeometry.pas:1-17` 的写法：夹具从哪来、守的规则是什么、比较是精确的。读夹具用 `ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'terminal-unicode-<x>.json'` + `fpjson`（spec §13.2）；`.inc` 的路径用 `test.designregistry` 的 `RepoRoot`。版本 / ambiguous 从变体 id 解析：`TyUnicodeVersionName` 反查 `version` 字段，`ambiguousWide` 直接读。失败收集照地雷 11（`Miss` 计数、记前 30 条，每条写变体 id、码位十六进制、前驱、期望、实际）。

#### `TTyUnicodeWidthOracleTests`（夹具）

每个测试都要**数比较次数并断言**（开工前问题 13）。判据：

| 测试 | 比什么 | 计数必须等于 |
|---|---|---|
| `TestFixturesComeFromThePinnedUpstream` | 三份夹具的 `upstream.commit` 相同、以 `c58ea36` 开头、`version = '6.0.0'`；`.inc` 文件文本里含这个 40 位 commit | — |
| `TestWcWidthOfEveryCodepoint` | `width.json` 每个变体的区间表逐码位对 `TyUnicodeWcWidth`；**`6` / `11` 两个变体各用 `AAmbiguousWide = False` 和 `True` 各比一遍，期望相同**（spec §4.3） | `$110000 × 8`；另断言每张区间表首起点 0、起点严格递增、末起点 ≤ `$10FFFF` |
| `TestWcWidthBeyondTheLastCodepoint` | `outOfRange.wcwidth` 对 `TyUnicodeWcWidth`，`outOfRange.props0` 对 `TyUnicodeCharProperties(cp, 0, …)` | `3 × 6 × 2` |
| `TestCharPropertiesAfterEveryPreceding` | `join.json`：每个变体 × 9 个前驱，区间表逐码位对 `TyUnicodeCharProperties(cp, preceding, …)`，比打包值（整数相等） | `$110000 × 54` |
| `TestHandSequences` | `cases.json` 的 `sequences`：前驱从 0 起逐步调、每步比打包值 | 所有序列长度之和 × 6 |
| `TestRepresentativePairsAndTriples` | `pairs`（每个变体）、`triples`（两个 15-graphemes 变体），同上逐步比 | `n² × 2 × 6 + n³ × 3 × 2`（`n` = `reps` 个数） |
| `TestStringCellWidth` | `strings`：单元数组编成 WTF-8（有效代理对 → 4 字节；孤立代理 → 3 字节 `ED xx xx`；其余照 UTF-8），调 `TyUnicodeStringCellWidth` | `strings` 条数 × 6 |

用时：`TestCharPropertiesAfterEveryPreceding` 结尾用 `GetTickCount64` 量整条用时，**只打印**（`WriteLn`），不断言。整个 suite 预计几秒（约 6700 万次调用）。Task 7 跑的时候记下用时；超过 30 秒先看是不是循环里做了多余的事（字符串拼接、每次重新解析 JSON 节点），**不要**靠删扫描省时间。

#### `TTyUnicodeWidthTests`（纯函数，照表）

**1. `TestPropsFieldsUnpack`**

| `AProps` | `TyUnicodePropsWidth` | `TyUnicodePropsShouldJoin` | `TyUnicodePropsKind` |
|---|---|---|---|
| `0` | 0 | False | 0 |
| `$3` | 1 | True | 0 |
| `$95` | 2 | True | `$12` |
| `$7FFFF9A` | 1 | False | `$FFFFF3` |
| `$7FFFFFF` | 3 | True | `$FFFFFF` |

**2. `TestVersionNames`**：`tuv6` → `'6'`，`tuv11` → `'11'`，`tuv15` → `'15'`，`tuv15Graphemes` → `'15-graphemes'`；再断言 `Ord(High(TTyUnicodeVersion)) = 3`（加了版本要想起来补夹具）。

**3. `TestAnchorsIndependentOfTheFixtures`**（开工前问题 14；值来自写计划时用正确解码实跑上游，核实记录 5）

`TyUnicodeWcWidth`：

| 码位 | 6 | 11 | 15 | 15 amb | 15-g | 15-g amb |
|---|---|---|---|---|---|---|
| `$7` | 0 | 0 | 1 | 1 | 1 | 1 |
| `$301` | 0 | 0 | 0 | 0 | 0 | 0 |
| `$200D` | 0 | 0 | 1 | 1 | 1 | 1 |
| `$FE0F` | 0 | 0 | 0 | 0 | 0 | 0 |
| `$2026` | 1 | 1 | 1 | 2 | 1 | 2 |
| `$1F600` | 1 | 2 | 2 | 2 | 2 | 2 |
| `$20000` | 2 | 2 | 2 | 2 | 2 | 2 |
| `$1F1E6` | 1 | 1 | 1 | 1 | 1 | 1 |
| `$E000` | 1 | 1 | 1 | 2 | 1 | 2 |
| `$110000` | 1 | 1 | 1 | 1 | 1 | 1 |

`TyUnicodeStringCellWidth`（UTF-8 写法；孤立代理按 WTF-8）：

| 串（码位） | 6 | 11 | 15 | 15 amb | 15-g | 15-g amb |
|---|---|---|---|---|---|---|
| `e` U+0301 | 1 | 1 | 2 | 3 | 1 | 2 |
| 👨 ZWJ 👩 ZWJ 👧（1F468 200D 1F469 200D 1F467） | 3 | 6 | 8 | 8 | 2 | 2 |
| 🇨🇳🇺（1F1E8 1F1F3 1F1FA） | 3 | 3 | 3 | 3 | 3 | 3 |
| U+263A U+FE0F | 1 | 1 | 3 | 3 | 2 | 2 |
| U+263A U+FE0E | 1 | 1 | 2 | 3 | 1 | 2 |
| U+1100 U+1161 U+11A8 | 2 | 2 | 4 | 4 | 2 | 2 |
| U+0600 `a` | 1 | 1 | 2 | 2 | 1 | 1 |
| `a` + 孤立高代理 D83D（`#$ED#$A0#$BD`） | 2 | 2 | 2 | 2 | 2 | 2 |
| D83D + D83D DE00（`#$ED#$A0#$BD` + 😀 的四字节） | 3 | 3 | 3 | 3 | 3 | 3 |

`TyUnicodeCharProperties` 逐步打包值（前驱从 0 起）：

| 版本 | 码位序列 | 打包值序列 |
|---|---|---|
| 15-graphemes（amb 窄） | 1F1E8 1F1F3 1F1FA | `$9A` `$105` `$7FFFF9A` |
| 15-graphemes | 1F468 200D 1F469 | `$1DC` `$D5` `$DD` |
| 15-graphemes | 263A FE0F | `$5A` `$95` |
| 15-graphemes | 600 61 | `$A` `$83` |
| 15 | 61 301 | `$2` `$2` |
| 11 | 1F468 200D 1F469 | `$4` `$5` `$4` |
| 6 | 4E00 301 | `$4` `$5` |

**4. `TestMalformedUtf8`**（上游没有这类输入，判据是相对的；每条对 6 个变体都成立）

| 输入字节 | 期望 |
|---|---|
| `''` | 0 |
| `#$FF` | = `TyUnicodeStringCellWidth(UTF8(U+FFFD))` |
| `#$E4#$B8`（截断的「中」） | = 两个 U+FFFD 的串宽 |
| `#$C0#$80`（超长编码） | = 两个 U+FFFD 的串宽 |
| `#$80` `a`（孤立续字节） | = U+FFFD `a` 的串宽 |
| `#$F4#$90#$80#$80`（> U+10FFFF） | = 四个 U+FFFD 的串宽 |
| `#$ED#$B8#$80` `a`（WTF-8 孤立低代理 DE00） | = `TestStringCellWidth` 里 `lone-low` 那条的期望（从夹具读，不写死） |

- [ ] **Step 1: 写测试单元**，`initialization` 里 `RegisterTest(TTyUnicodeWidthOracleTests); RegisterTest(TTyUnicodeWidthTests);`
- [ ] **Step 2: 登记到 `tests/tytests.lpr`**（编辑工具）
- [ ] **Step 3: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.unicode.width.pas tests/tytests.lpr && git commit -m "test(terminal): unicode widths held to xterm.js code point by code point

Every code point under every variant, the join state after nine preceding
states, hand sequences, representative pairs and triples, and string width,
compared exactly against the oracle fixtures, with the comparison count
asserted so an empty fixture cannot pass. Anchor values measured apart from
the fixtures guard against the tables and the fixtures going wrong together.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异表（期末做，Task 7 Step 4）：**

| # | 变异（在 `source/tyControls.Unicode.Width.pas`） | 必须红的测试 |
|---|---|---|
| U1 | `RunIndex`：`AStarts[mid] <= ACp` → `<` | `TestWcWidthOfEveryCodepoint` |
| U2 | `LegacyWcWidth`：tuv6 的 BMP 查 `GBmp11` | `TestWcWidthOfEveryCodepoint` |
| U3 | `LegacyCharProps`：`oldWidth > width` → `oldWidth < width` | `TestHandSequences`、锚点 |
| U4 | `LegacyCharProps`：删掉 `if oldWidth = 0 then shouldJoin := False else` | `TestCharPropertiesAfterEveryPreceding`（前驱 8） |
| U5 | `CharProps15`：`oldWidth > w` → `oldWidth >= w` | `ri-pair`、锚点 🇨🇳 |
| U6 | `CharProps15`：删掉 `else if info = GB_SawRegionalPair then w := 2` | 同上 |
| U7 | `CharProps15`：快路径去掉 `and ((APreceding shr 3) = 0)` | `prepend-then-ascii`、锚点 600 61 |
| U8 | `CharProps15`：去掉 `or (ACp = $FE0F)` | `vs16-*`、锚点 |
| U9 | `CharProps15`：去掉 `or AAmbiguousWide` | `15+amb` 的全码位扫描 |
| U10 | `WcWidth15`：去掉 `or (kind = GB_Prepend)` | `TestWcWidthOfEveryCodepoint` |
| U11 | `CharProps15`：非 graphemes 分支 `info := 0` → `info := 1` | `15` 变体的扫描、锚点 `15 61 301` |
| U12 | `MakeProps`：去掉 `and $FFFFFF` | 15-graphemes 的前驱扫描、锚点 `$7FFFF9A` |
| U13 | `JoinRule`：删掉 GB9b（`or (AAfter = GB_SpacingMark)`） | `spacing-mark`、前驱 2 的扫描 |
| U14 | `JoinRule`：删掉 GB11 那一行 | `zwj-family`、前驱 `P(200D)` 的扫描 |
| U15 | `JoinRule`：GB7 去掉 `(ABefore = GB_HangulV)` | `hangul-l-v-t` |
| U16 | `TyUnicodeStringCellWidth`：删掉 `Dec(chWidth, …)` 那一句 | `TestStringCellWidth`、锚点 |
| U17 | `TyUnicodeStringCellWidth`：删掉 `Inc(Result, TyUnicodeWcWidth(second, …))` | `high-then-letter` |
| U18 | `Wtf8ToUnits`：`$E1..$EF` 分支对 `$ED` 把 `hi` 设成 `$9F`（标准 UTF-8 拒收代理） | `TestStringCellWidth`、`TestMalformedUtf8` 末条 |
| U19 | `TyUnicodeVersionName`：`'15'` 与 `'15-graphemes'` 对调 | `TestVersionNames`、所有夹具测试（变体解析错位） |
| U20 | `.inc`：`TyUniV6Width` 里任改一个值（不重跑脚本） | `TestWcWidthOfEveryCodepoint`——证明夹具不是从 `.inc` 抄的 |

**等价、不做的**（审查时核理由）：`LegacyCharProps` 的 `>` → `>=`（进入分支时 `width` 恒为 0、`oldWidth` ≥ 1，两者同真）；`Info15` 的越界判断删掉（最后一段的值恰好也是 `errorValue` 0，核实记录 11）；`CharProps15` 的 `else if w = 0` 改判（`w` 恒 ≥ 1，只有 U11 那种改常量才分得开）；`RunIndex` 去掉 `+ 1`（死循环，地雷 5）。

---

### Task 6: 许可与署名

**Files:**
- Modify: `THIRD-PARTY-NOTICES.md`
- Modify: `tests/test.release.pas`

- [ ] **Step 1: `THIRD-PARTY-NOTICES.md` 加一节**（放在 Lucide 那节之后，格式照它，spec §14）

内容要点（英文，照 Lucide 节的语气，[[doc-writing-native-tone]]）：

- 标题 `## xterm.js — source/tyControls.Unicode.Width.pas, source/tyControls.Unicode.Width.Data.inc`（2 期起往后补单元名）。
- `Upstream: <https://github.com/xtermjs/xterm.js> · pinned at 6.0.0, commit c58ea3637f39.`
- 一段话：这两个文件是移植 / 生成自 xterm.js 的；**只有用了 `tyControls.Unicode.Width`（以及以后的 `tyControls.Terminal*`）的程序才要带这一节**；数据表以常量编进单元，智能链接会把不用它的程序里的整张表去掉。
- MIT 全文：版权行照抄 `xterm:LICENSE:1-3`，再加 `addons/addon-unicode11/LICENSE:1`、`addons/addon-unicode-graphemes/LICENSE:1` 两行（同一份 MIT 条款，一段正文即可），条款原文从 `xterm:LICENSE` 复制，不凭记忆打。
- 一句：字形簇规则经 xterm.js 的 addon 取自 unicode-properties 项目（按 Task 0 Step 6 的结论写它的许可；兼容 MIT 就写一句出处，不兼容就写「规则按 UAX #29 自写」——那种情况下 Task 3 已经改写）。
- 子标题 `### Unicode data`：`'15'` 表源自 Unicode Character Database；Unicode License v3 全文，**从 `tools/terminal-oracle/unicode-license.txt` 原样复制**进代码块。

- [ ] **Step 2: `tests/test.release.pas` 加一条守卫**

`TReleaseManifestTest` 新增 published 方法 `TheThirdPartyNoticeCoversTheUnicodeWidthPort`，照 `TheThirdPartyNoticeShipsWithTheFontItLicenses` 的写法（它说明了「这是有意写死的字面量」，新方法同样写一段注释说明为什么）。判据：

| 断言 | 变异（期末做） |
|---|---|
| `IsShipped(FPs1, 'source/tyControls.Unicode.Width.pas')` 且 `.inc` 也 shipped（两个脚本都查） | — |
| `THIRD-PARTY-NOTICES.md` 文本含 `## xterm.js` | R1：删掉这一节标题 → 红 |
| 同一文件含 `UNICODE LICENSE V3` | R2：删掉 Unicode 许可代码块 → 红 |
| 同一文件含 `c58ea36` | — |

- [ ] **Step 3: 提交**

```bash
cd /d/Projects/ty-3.1 && git add THIRD-PARTY-NOTICES.md tests/test.release.pas && git commit -m "docs(terminal): xterm.js and Unicode data notices for the width tables

The width unit is ported from xterm.js (MIT) and its '15' table derives
from the Unicode Character Database (Unicode License v3); both texts now
travel in THIRD-PARTY-NOTICES.md, and the release manifest test fails if
the section goes missing while the unit ships.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 收尾——编译、全量、集中修、按 spec 逐条核、集中变异、审查、写回 spec、签收

**Files:**
- Modify: `docs/superpowers/plans/2026-09-28-terminal-phase-1.md`（签收记录）
- Modify: `docs/superpowers/specs/2026-09-28-terminal-view-design.md`（写回）
- 修复时按需改 Task 1–6 的文件

- [ ] **Step 1: 一次编译 + 本期 suite + 全量**

「跑测试的固定套路」两条命令。Expected：`TTyUnicodeWidthOracleTests`、`TTyUnicodeWidthTests`、`TReleaseManifestTest` 都 0 / 0；全量 errors / failures 为 0，总数 = Task 0 基线 + 本期新增条数。记下 `TestCharPropertiesAfterEveryPreceding` 打印的用时。

编译错、红了就集中修：每修一处，先确认是移植错还是夹具错——**以上游为准**，对照上游源码行号；修完回到本步从头跑。全量红而单跑绿，按 [[suite-order-widgetset-init]]、[[canary-then-rebuild]] 排查。修复提交信息写 `fix(terminal): ...`，每个问题一个提交。

- [ ] **Step 2: 重跑生成，确认可复现**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/regen-all.js --expect-clean
```

Expected：`clean`。

- [ ] **Step 3: 按 spec 逐条核代码，不看测试**（[[green-tests-are-not-spec-conformance]]）

逐条记「在哪一行实现 / 为什么不需要」：

- §2.1：单元名、只依赖 `SysUtils`、进运行时包、`.inc` 不进清单；纯函数、无全局可变状态（`GBmp6` / `GBmp11` 只在 `initialization` 写）。
- §4.2：脚本路径与名字、四个 provider 都经上游加载、全码位、区间表、头部写上游版本 / commit（日期代替生成时间，开工前问题 7）、重跑 `git diff` 为空。
- §4.3：15 / 15-graphemes 的 ambiguous 照 provider 字段；6 / 11 下不起作用。
- §4.4：七个函数签名与 spec 一字不差；`TTyUnicodeVersion` 名字与上游版本字符串一一对应。
- §4.5：全码位 × 版本 × ambiguous；序列用例六类都在；串宽含孤立代理；三条点名的变异在变异表里（U1、U3/U5、U6）。
- §13.1：钉版本、读 commit 写进每个夹具、`allowProposedApi`、读 `_core` 内部。
- §13.2：目录与命名（`tools/terminal-oracle/*.js`、`cases/*.js`、`lib-dump.js`、`tests/fixtures/terminal-*.json`、`tests/test.unicode.width.pas`）。
- §13.5：精确比较；照结果不照意图（核实记录 8、9 的行为保留了）；夹具标 `source`；上游崩的输入（本期没有）；生成可复现。
- §14：单元头、`.inc` 头、`THIRD-PARTY-NOTICES.md` 两节。
- §17.2：第 5、8、10 条。

- [ ] **Step 4: 集中变异**（每条三拍，必须红）

Task 5 变异表 U1–U20、Task 6 的 R1–R2、Task 1 的 J1–J2（JS 侧：改完跑 Task 1 Step 2 的命令，必须抛；改回）。卡死的按进程号结束（地雷 5）。结果逐条记进签收记录；没红的当场补强。

- [ ] **Step 5: 【主控执行】编一次运行时包**（`.lpk` 清单改了）

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/term-pkg.txt 2>&1; tail -3 /tmp/term-pkg.txt; git status --short
```

Expected：编过；`git status` 没有变化（`languages/` 不动——本期没有 resourcestring）。报错路径里出现别的树 = 注册权被抢，重编一次（[[parallel-agent-worktree-hazards]]）。

- [ ] **Step 6: 整体代码质量审查**

对 `git diff <Task 0 的 HEAD>..HEAD` 做一次：移植函数与上游逐行对照（Task 3 Step 1 点名的三处 + `JoinRule` / `ShouldJoin15` / `WcWidth15`），注释行号引用对得上；`lib-dump.js` 之外没有脚本直接 `require` 上游；`GENERATED` 与实际写出的文件一致；夹具读空时每个测试都会红（计数断言）；`.inc` 头部没有本机路径和日期以外的可变内容；等价变异的理由站得住。审出来的问题修完回到 Step 1。

- [ ] **Step 7: 写回 spec 原处，标「实现期修正（1 期）」**

至少：

- §13.1：node 下 15 表解码的 bug 与 `Buffer.poolSize = 0` 修法、`checkTrieDecode`（核实记录 5）；`NODE_PATH` 改在脚本里设（开工前问题 6）；上游单元测试用的是 `out-esbuild/`、我们用 `out/`（核实记录 2，Task 0 Step 3 若改了就写实际用的）；`npm ci` 与 `node-pty`（核实记录 3）。
- §4.1 / §4.3：`15` 不连接组合符、U+0301 是 ambiguous、15 下控制字符与 U+200D 宽 1（核实记录 8–10），以及用户对开工前问题 1、2 的结论。
- §4.2：头部写上游提交日期而不是生成时间（开工前问题 7）；实际区间数。
- §4.4：`TyUnicodeStringCellWidth` 的 WTF-8 与非法字节规则；越界码位（开工前问题 10、11）。
- §13.2：三份夹具的名字与格式、`regen-all.js`、`cases/unicode.js`、`unicode-license.txt`。
- §14：unicode-properties 的出处与许可结论（开工前问题 12）。
- §17.2 第 5、8、10 条标「已完成（1 期）」。

- [ ] **Step 8: 签收记录写进本计划末尾，提交**

写：全量条数（基线 → 签收）、提交区间、Oracle suite 用时、变异结果（每条红 / 补强 / 等价）、spec 写回的节号、遗留、给 2 期的交接（`lib-dump.js` 已有什么可复用、`GENERATED` 要登记新夹具、2 期夹具格式按 spec §13.3）。本期没有真机项，不出验收表。

```bash
cd /d/Projects/ty-3.1 && git add docs/ && git commit -m "docs(terminal): phase 1 sign-off and corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 1 期做完能看到什么

- `tytests` 里 `TTyUnicodeWidthOracleTests` / `TTyUnicodeWidthTests` 全绿：四个版本（加 ambiguous 共六个变体）每个码位的宽度、九种前驱下每个码位的连接状态、手写序列、代表码位的两两 / 三连组合、串宽，都和 xterm.js 6.0.0 逐位相同。
- `node tools/terminal-oracle/regen-all.js --expect-clean` 打印 `clean`：重跑两个生成脚本，仓库一个字节不变。
- `THIRD-PARTY-NOTICES.md` 有 xterm.js 与 Unicode 数据两节。
- 没有界面，没有真机项。
