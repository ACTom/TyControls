# 终端控件 2 期 · 2a 解析器与 UTF-8 解码（Task 2–5）

> 本文件是 [`2026-09-28-terminal-phase-2.md`](2026-09-28-terminal-phase-2.md) 的附录，执行方式、核实记录、开工前问题、接口清单、夹具格式、地雷都在主文件。先读主文件。

**这一批做完能看到什么**：上游 VT500 转移表 4257 项和 Pascal 在 `initialization` 里生成的表逐项相同；UTF-8 解码每次调用的输出码位相同（含跨块半截、非法字节、BOM）；几百条输入的回调轨迹——打印区间、执行、CSI 标识与参数（含子参数）、ESC、OSC / DCS / APC 的起止与载荷、错误动作、注册处理器的调用链——和上游逐项相同；11MB 载荷、1000 个参数、20 位数字、64KB 中间字节之后状态有界、后续序列照常。

---

### Task 2: `parser-cases.js` → 三份解析器夹具

**Files:**
- Create: `tools/terminal-oracle/cases/parser.js`（只有输入）
- Create: `tools/terminal-oracle/parser-cases.js`
- Create (generated): `tests/fixtures/terminal-parser-table.json`、`terminal-parser-utf8.json`、`terminal-parser-trace.json`（可能分片）

- [ ] **Step 1: 写 `cases/parser.js`**（Write 工具）

导出 `{ utf8, traces, cutSources, longCases, fuzz }`。

**`utf8`**：每项 `{ id, chunks: [[byte...] ...] }`。至少：

| id | 分块（十六进制字节，`|` 分块） | 守的是（`TextDecoder.ts`） |
|---|---|---|
| `ascii-unrolled` | `61 62 63 64 65 66 67 68 69` | 四字节展开的快路径（`:229-240`）与尾巴 |
| `ascii-short` | `61 62 63` | 不足四字节 |
| `two-three-four` | `C3 A9 E4 B8 AD F0 9F 98 80` | 三种长度 |
| `overlong-2` | `C0 80 C1 BF 61` | 2 字节 `cp < 0x80` → 回退一字节（`:262-266`） |
| `overlong-3` | `E0 80 80 61` | `cp < 0x800` 不回退（`:293-296`） |
| `overlong-4` | `F0 80 80 80 61` | `cp < 0x10000` 不回退（`:335-338`） |
| `surrogates` | `ED A0 80 ED BF BF 61` | 代理区丢弃 |
| `bom-whole` | `EF BB BF 61` | BOM 丢弃 |
| `bom-split` | `EF | BB BF 61` | BOM 经跨块路径丢弃（`:195`） |
| `beyond-max` | `F4 90 80 80 F5 80 80 80 F8 61 FF 61` | `> 0x10FFFF` 吃四字节；`F8`–`FF` 非法字节单独跳过（`:340-342`） |
| `bad-cont-2` | `C3 41` | 续字节错 → 回退（`:256-260`） |
| `bad-cont-3a` / `bad-cont-3b` | `E4 41` / `E4 B8 41` | 三字节两个位置 |
| `bad-cont-4a/b/c` | `F0 41` / `F0 9F 41` / `F0 9F 98 41` | 四字节三个位置 |
| `lone-cont` | `80 BF 61` | 孤立续字节 |
| `split-3` | `E4 | B8 | AD` | 跨块续接（`:155-209`） |
| `split-4` | `F0 | 9F | 98 | 80` | 逐字节 |
| `split-empty` | `E4 | (空) | B8 AD` | 空块不动半截（`:142-144`） |
| `split-bad-cont` | `E4 B8 | 41` | 跨块时续字节错：丢弃半截、`41` 重读（`:173-177`） |
| `split-overlong-2` | `C1 | BF 61` | 跨块 2 字节 `cp < 0x80`：`startPos--`（`:188-190`） |
| `split-surrogate` | `ED | A0 80 61` | 跨块代理丢弃 |
| `split-then-ascii-run` | `E4 B8 | AD 61 62 63 64 65` | 续接后进快路径 |

**`traces`**：每项 `{ id, register: [...], feed: [...] }`，输入里用 `s: "..."`（JS 字符串，按码位转换）或 `cp: [..]` 写。`register` 词表（`parser-cases.js` 照它装处理器，Pascal 照它装同样的）：

| 项 | 装什么 | 事件 |
|---|---|---|
| `{ csi: {prefix?, intermediates?, final}, ret }` | `registerCsiHandler` | `["h", k, "csi", paramsJson]`，返回 `ret` |
| `{ esc: {...}, ret }` | `registerEscHandler` | `["h", k, "esc"]` |
| `{ exec: code }` | `setExecuteHandler(String.fromCharCode(code))` | `["h", k, "exec"]` |
| `{ osc: ident, kind: "string", ret }` | `registerOscHandler(ident, new OscHandler(data => ...))` | `["h", k, "osc", digestable(data)]` |
| `{ osc: ident, kind: "raw", ret }` | 手写 `IOscHandler` | `["h", k, "osc-start"]`、`["h", k, "osc-put", digestable(cps)]`、`["h", k, "osc-end", success]` |
| `{ dcs: {...}, kind: "string", ret }` | `registerDcsHandler(id, new DcsHandler((data, params) => ...))` | `["h", k, "dcs", digestable(data), paramsJson]` |
| `{ dcs: {...}, kind: "raw", ret }` | 手写 `IDcsHandler` | `dcs-hook`（paramsJson）/ `dcs-put` / `dcs-unhook` |
| `{ apc: {...}, kind: "string" | "raw", ret }` | 同上 | `apc` / `apc-start` / `apc-put` / `apc-end` |

`feed` 词表：`{ s }`、`{ cp }`、`{ repeat: { s | cp, times } }`（同一块连续 parse `times` 次）、`{ reset: 1 }`（`parser.reset()`）、`{ unregister: k }`（调第 k 个注册返回的 `dispose()`）。每一项是一次 `parse` 调用（`repeat` 是 `times` 次）。

轨迹记录规则（两侧一致）：
- 打印处理器总是装一个记录器：`["print", digestable(data.subarray(start, end))]`，**并把 `parser.precedingJoinState` 设成本段最后一个码位**（任意非零值，用来观察后续动作有没有把它清零）。
- 六个回退处理器和错误处理器都装记录器（主文件「夹具格式」的事件形状）；错误处理器返回原状态、`abort` 恒 false。
- OSC 回退的编号大于 2147483647 时记字符串 `"big"`：上游是浮点数（309 位以后是 `Infinity`，`JSON.stringify` 成 `null`），Pascal 是饱和的 `Int64`，两边的具体数值没有可比性，可比的只是「它大到不可能命中任何处理器」。
- 用例结束记 `finalState = parser.currentState`、`finalJoinState = parser.precedingJoinState`。

至少这些手写用例（id → 输入要点 → 守的是）：

| 组 | id 与要点 | 守的是（`EscapeSequenceParser.ts` 行号） |
|---|---|---|
| 打印 | `print-ascii`；`print-nonascii`（含 U+00A0、U+00FF、😀）；`print-del`（地面 `0x7F` → 错误事件）；`print-long-run`（300 个字符，走摘要） | PRINT 内循环 `:754-771`、`NON_ASCII_PRINTABLE`、ERROR `:779-791` |
| 执行 | `exec-c0-all`（`0x00`–`0x1F` 逐个，含 `0x18`/`0x1A` CAN/SUB、不含 `0x1B`）；`exec-c1-all`（`0x80`–`0x9F` 作为码位）；`exec-in-csi`（`ESC[1` `\n` `2m`）；`exec-in-esc-intermediate`（`ESC (` `\n` `0`）；`exec-in-osc`（OSC 里的 C0 被忽略）；`exec-registered`（`{exec: 7}` 后喂 BEL） | EXE 快路径 `:688-692`、anywhere 规则 `:120-131`、OSC 里 C0 `:136` |
| CSI | `csi-basic`（`ESC[1;2H`）；`csi-zdm`（`ESC[m` → `[0]`）；`csi-empty-params`（`ESC[;;m`）；`csi-subparams`（`ESC[1;2:3:4;5::6m`）；`csi-leading-colon`（`ESC[:1m`）；`csi-prefix-each`（`<` `=` `>` `?` 各一次）；`csi-prefix-late`（`ESC[1?m` → CSI_IGNORE、不派发）；`csi-intermediates`（`ESC[1 !p`、`ESC[ $p`）；`csi-many-intermediates`（`ESC[?1 !!!!p`：`_collect` 左移截断后的标识进回退）；`csi-param-overflow`（`ESC[99999999999999999999m`）；`csi-33-params`（33 个参数，第 33 个及其数字丢弃）；`csi-subparam-overflow`（`1:` 后 33 个子参数）；`csi-subparam-after-reject`（33 个参数后再带 `:5`）；`csi-nonascii-abort`（参数里夹 U+00E9 → ERROR 回地面、剩下的字符打印）；`csi-7f-inside`（各 CSI 状态里的 `0x7F` 被忽略） | Params `:158-247`、CSI 各转移 `:173-188`、`_collect` `:828-831` |
| CSI 快路径 | `csi-fast-chunk-end`（三次 parse：`ESC[`、`1`、`m`）；`csi-fast-two`（`ESC[`+`1m` 两块）；`csi-fast-exact`（块恰好是 `ESC[1m`）；`csi-fast-after-print`（`ab` + `ESC[m` + `c`：看 `finalJoinState` 清零）；`csi-fast-in-sospm`（`ESC X` 里的 `ESC[1m`） | 快路径 `:695-746`（`i + 2 < length`、`precedingJoinState = 0`、`currentState < OSC_STRING`） |
| ESC | `esc-basic`（`ESC 7`、`ESC c`、`ESC =`）；`esc-intermediate`（`ESC ( 0`、`ESC # 8`、`ESC % G`）；`esc-st-swallowed`（`ESC \` 不进回退）；`esc-7f`（`ESC 0x7F 7`）；`esc-final-ranges`（`ESC` + `0x30`–`0x7E` 每个，扣掉引出 DCS / SOS / CSI / OSC / PM / APC 的 `P X [ ] ^ _`，另一个用例单独喂这六个） | `:190-196`、`:334-335` |
| OSC | `osc-bel`、`osc-st`（`ESC \`）、`osc-c1-st`（`0x9C`）、`osc-can`、`osc-sub`（`end(false)`）；`osc-no-payload`（`OSC 2 BEL`：ID 态收尾时补 START）；`osc-no-id`（`OSC ;x BEL`）；`osc-bad-id`（`OSC 2a;x BEL` → ABORT）；`osc-id-huge`（`OSC 4294967300;1;? BEL`，另注册 `{osc: 4, kind: "raw"}`：不能命中）；`osc-c0-inside`（`0x1C`–`0x1F` 被忽略、`0x07` 结束）；`osc-nonascii`；`osc-split`（载荷分三次 parse）；`osc-chain`（同一编号注册三个 string 处理器，返回 `false,true,false` 的排列：看 `end(success)` 的调用顺序与收尾时的 `end(false)`） | OscParser `:99-188`、OSC 转移 `:147-151`、`:224` |
| DCS | `dcs-basic`（`ESC P 1 $ q m ESC \`）；`dcs-params`（`ESC P 1;2:3 q ...`）；`dcs-ignore`（`ESC P 1 ? q` → DCS_IGNORE，不 hook）；`dcs-can`；`dcs-c0-put`（passthrough 里 C0 当数据）；`dcs-7f`；`dcs-string-handler`（`{dcs: {intermediates: "$", final: "q"}, kind: "string"}`）；`dcs-chain` | DcsParser `:66-130`、DCS 转移 `:198-221`、DCS_PUT 内循环 `:858-868` |
| APC | `apc-basic`（`ESC _ G a=1 ESC \`）；`apc-intermediate`（`ESC _ ! G ...`）；`apc-allowed-bytes`（载荷里夹 `0x08`–`0x0D` 与其他 C0）；`apc-can`；`apc-string-handler` | ApcParser、APC 转移 `:158-172`、APC_PUT `:907-918` |
| SOS / PM | `sos-pm`（`ESC X ... ESC \`、`0x98`、`0x9E`、里面的 `0x9C` 结束） | `:127`、`:153-157` |
| 复位与注销 | `reset-mid-osc`（半截 OSC，`reset`，再喂字符）；`reset-mid-dcs`；`reset-mid-csi`；`unregister-csi`（注册、喂、注销、再喂 → 进回退）；`unregister-twice`（同一句柄注销两次：第二次空操作）；`csi-chain`（同一标识三个处理器，返回值排列） | `reset` `:495-510`、`dispose` `:396-403` |

**`cutSources`**：从上表挑 15 条（覆盖每种序列类型和 UTF-8 无关的码位），生成器对每条的每个切点各生成一个两块的用例（id 加 `@cut<k>`）。

**`longCases`**（`source: "long"`）：`long-params`（`ESC[` + 1000 个 `1;` + `31m`）；`long-digits`（`ESC[` + 20 位数字 + `;` + 20 位 + `H`）；`long-intermediates`（`ESC[` + 65536 个 `!` + `p`，用 `repeat`）；`long-osc-exact` / `long-osc-over` / `long-osc-astral`（注册 `{osc: 2, kind: "string"}`，载荷 10,000,000 个 `a` / 10,000,001 个 / 5,000,001 个 😀，用 `repeat` 按 65536 码位一块喂）；`long-dcs-over`（`{dcs: $q, kind: "string"}`，10,000,001）；`long-apc-over`；`long-sos`（11MB 的 SOS）；`long-print`（1,048,576 个 `x`）；`long-osc-id`（`OSC` + 5000 位数字 + `;x BEL`）。每条末尾都接一段正常输入 `ESC[1m` + `ok` + `OSC 2;t BEL`，轨迹里要看到它们照常派发。

**`fuzz`**：`{ seeds: [1..100], length: [256, 2048] }`（生成器用）。

- [ ] **Step 2: 写 `parser-cases.js`**（Write 工具）

要求：

1. 头部注释照 1 期 `gen-unicode-tables.js` 的写法：生成什么、上游是谁、怎么跑（`node tools/terminal-oracle/parser-cases.js`）、三份夹具的格式（引用主计划「夹具格式」）。
2. 经 `lib-term.js` 加载；解析器从 `require(path.join(L.XTERM, L.OUT_DIR, 'common/parser/EscapeSequenceParser.js'))` 取 `EscapeSequenceParser` 和 `VT500_TRANSITION_TABLE`，`OscHandler` / `DcsHandler` / `ApcHandler` 从各自的模块取，`Utf8ToUtf32` 从 `common/input/TextDecoder.js` 取（这些模块都在 `PORTED` 里，地雷 2）。
3. **表**：`runsOf` 的思路压 `VT500_TRANSITION_TABLE.table`（长度 4257，断言），写 `terminal-parser-table.json`。
4. **UTF-8**：每个用例新建一个 `Utf8ToUtf32`，每块调一次 `decode(Uint8Array, target)`（`target` 长度 = 块长 + 4），记 `out[k] = Array.from(target.subarray(0, n))`。另加 50 个随机用例（`prng(1000 + i)`：长度 16–256 字节，字节有 60% 取 `0x80`–`0xFF`、20% 取 `0xC2`–`0xF4`、20% 取 ASCII；切 1–6 刀）。
5. **轨迹**：每个用例新建一个 `EscapeSequenceParser`，照 Step 1 的规则装记录器和注册处理器，照 `feed` 调 `parse(Uint32Array, length)`；切点用例、长用例、随机用例同样。随机用例：`prng(seed)` 生成 256–2048 个码位，权重 ESC 15%、`[` 10%、`]` 3%、`P` 2%、`_` 2%、`;` 8%、`:` 3%、数字 20%（连续数字最多 6 位）、`0x40`–`0x7E` 终止字节 15%、C0 8%、C1 3%、`0x7F` 1%、`0x3C`–`0x3F` 3%、非 ASCII 4%、`0x20`–`0x2F` 3%；按 `prng` 切 1–8 块。
6. 写 `terminal-parser-trace.json`（`writeFixture` 自动分片）；打印各类用例数和文件字节数。
7. 末尾 `process.exit(0)`。

- [ ] **Step 3: 生成并核对**

```bash
cd /d/Projects/ty-3.1 && node tools/terminal-oracle/parser-cases.js && ls -l tests/fixtures/terminal-parser-*.json && node tools/terminal-oracle/parser-cases.js > /dev/null && git status --short
```

Expected：表 4257 项；三份（或加分片）夹具都 ≤ 2MB；第二次运行后 `git status --short` 只有新文件（两次输出相同）；`long-osc-exact` 的轨迹里有 `["h", 0, "osc", {"n":10000000, ...}]`，`long-osc-over` 没有（上限按 UTF-16 单元、`>` 判定，核实记录 2）；`osc-id-huge` 的轨迹里没有 `["h", 0, "osc-start"]`（核实记录 3）。不符就停下查。

- [ ] **Step 4: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tools/terminal-oracle/cases/parser.js tools/terminal-oracle/parser-cases.js tests/fixtures/terminal-parser-*.json && git commit -m "test(terminal): parser traces, UTF-8 decoding and the VT500 table from xterm.js

parser-cases.js runs xterm.js's own EscapeSequenceParser and Utf8ToUtf32:
the transition table as runs, decoder output per call across split and
malformed input, and the full callback trace (print ranges, executes, CSI
params with sub-params, ESC, OSC/DCS/APC start/put/end, errors, handler
chains) for hand cases, every cut of fifteen of them, oversized input and
seeded random input.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `tyControls.Terminal.Parser`（一）——参数、UTF-8 解码、字符串工具

**Files:**
- Create: `source/tyControls.Terminal.Parser.pas`
- Modify: `tycontrols.lpk`（`<Files>` 末尾、`tyControls.Unicode.Width.pas` 那一项之后）

- [ ] **Step 1: 单元头与 interface**

单元头照 spec §14 和 1 期 `tyControls.Unicode.Width.pas` 的写法：移植自 xterm.js 6.0.0（commit 前 12 位）；源文件 `src/common/parser/{EscapeSequenceParser,Params,OscParser,DcsParser,ApcParser,Constants,Types}.ts`、`src/common/input/TextDecoder.ts`（`Utf8ToUtf32`、`utf32ToString`）、`src/common/StringBuilder.ts`（`LimitedStringBuilder`）；版权行照抄 `xterm:LICENSE:1-3`；「MIT，全文见 THIRD-PARTY-NOTICES.md」。再用一段话写清三处不直观的地方：载荷上限按 UTF-16 单元数（核实记录 2）、OSC 编号饱和（核实记录 3）、异步处理器没有移植（spec §2.2）。

interface 段就是主计划「接口清单」的 Parser 部分；`{$mode objfpc}{$H+}`、`{$modeswitch advancedrecords}`。

- [ ] **Step 2: `TTyTerminalParams`**（逐行对 `Params.ts`）

字段照上游：`FParams: array of Integer`（长度 `MaxLength`）、`FLength`、`FSubParams`（长度 `MaxSubParamsLength`）、`FSubParamsLength`、`FSubParamsIdx: array of Word`（高 8 位起点、低 8 位终点）、`FRejectDigits`、`FRejectSubDigits`、`FDigitIsSub`。
- `Create`：`AMaxSubParamsLength > 256` 抛 `EArgumentException`（`:79-81`）。
- `AddParam`：`FDigitIsSub := False`；满了设 `FRejectDigits` 返回；`< -1` 抛 `EArgumentException`；`FSubParamsIdx[FLength] := (FSubParamsLength shl 8) or FSubParamsLength`；值钳到 `$7FFFFFFF`。
- `AddSubParam`：`FDigitIsSub := True`；`FLength = 0` 返回；`FRejectDigits or (FSubParamsLength >= FMaxSubParamsLength)` → `FRejectSubDigits := True` 返回；钳值；`Inc(FSubParamsIdx[FLength - 1])`。
- `AddDigit`：照 `:235-247`；`cur * 10 + value` 在 `Int64` 里算再和 `$7FFFFFFF` 取小（地雷 3）；`~cur` 即 `cur <> -1`。
- `ResetZdm` / `Reset` / `Clone` / `HasSubParams` / `SubParamCount` / `SubParam` / `ToJson`（格式和 `JSON.stringify(toArray())` 逐字相同：`[1,2,[3,4],5,[-1,6]]`，无空格）。
- `Params[i]` 读 `FParams[i]`，不查界（上游同样「别读超过 length - 1」）。

- [ ] **Step 3: `TTyUtf8Decoder`**（逐行对 `TextDecoder.ts:121-346`）

`FInterim: array[0..2] of Byte`。`Decode(const ABytes; ACount; var AOut)` 按上游结构写：先处理半截（`:155-209`，含 `discardInterim`、`startPos--` 两个分支、type 2/3/4 的末尾检查），再主循环（四字节 ASCII 展开可以照抄也可以写成简单循环——行为一样，**但注释写明是哪一种**），每种长度的 `i--` / 不回退分支照原样。返回写入的码位数。`AOut` 的长度由调用者保证 ≥ `ACount`（上游同样不查界），单元内用断言式检查 `Assert(Length(AOut) >= ACount)` 只在调试编译生效。

- [ ] **Step 4: 字符串工具**

- `TyTerminalCodepointsToUtf8(AData, AStart, AEnd)`：码位 → UTF-8。码位来自解码器，没有代理区、没有越界，但 CSI / OSC 的注册 API 允许宿主直接 `Parse` 任意 `Cardinal`：`> $10FFFF` 或代理区的码位按 U+FFFD 编码（上游 `utf32ToString` 会编出孤立代理或乱码，这类输入上游不产生，没有基准；写在注释里）。
- `TyTerminalUtf16Length(AData, AStart, AEnd)`：`> $FFFF` 记 2，其余记 1。
- 内部 `TTyLimitedStringBuilder`（`StringBuilder.ts:35-67`）：`Append(AData, AStart, AEnd): Boolean` 以 UTF-16 单元计长，超过上限就清空并返回 True；`Text` 取 UTF-8；`Reset`；`Length`（UTF-16 单元）。内部用一个按需翻倍的 UTF-8 缓冲，避免反复 `+` 拼接。

- [ ] **Step 5: 加进 `.lpk`**

`tycontrols.lpk` 的 `<Files>` 里 `source/tyControls.Unicode.Width.pas` 那个 `<Item>` 之后加（编辑工具）：

```xml
      <Item>
        <Filename Value="source/tyControls.Terminal.Parser.pas"/>
        <UnitName Value="tyControls.Terminal.Parser"/>
      </Item>
```

- [ ] **Step 6: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Parser.pas tycontrols.lpk && git commit -m "feat(terminal): parser params and the UTF-8 decoder, ported from xterm.js

Params keeps xterm.js's limits (32 params, 32 sub-params, values clamped
to 2^31-1, digits after a rejected param dropped) with the arithmetic in
Int64 so a twenty-digit parameter clamps instead of wrapping. The decoder
drops malformed bytes and the BOM exactly as Utf8ToUtf32 does, carrying a
split sequence across calls.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

（Task 3 与 Task 4 写同一个文件，分两次提交；Task 3 提交时单元可以不完整——整期末才编译。）

---

### Task 4: `tyControls.Terminal.Parser`（二）——子解析器与 `TTyTerminalParser`

**Files:**
- Modify: `source/tyControls.Terminal.Parser.pas`

- [ ] **Step 1: 转移表**

单元级 `var GTransitions: array[0..4256] of Word;`，在 `initialization` 里照 `EscapeSequenceParser.ts:97-230` 的代码**一句一句**生成（spec §17.2 第 6 条：照代码生成、不写常量表），`setDefault`、`add`、`addMany`、`r(start, end)`（半开区间）写成局部过程。公开纯查询 `function TyTermTransition(AIndex: Integer): Word;`（Task 5 对表用）。

- [ ] **Step 2: OSC / DCS / APC 子解析器**（逐行对 `OscParser.ts:14-189`、`DcsParser.ts:15-131`、`ApcParser.ts:22-148`）

- 每个子解析器：处理器表（键 → 处理器对象列表，按注册顺序）、`FActive`（当前列表的引用或下标）、`FId` / `FIdent`、`FState`（OSC 才有：START / ID / PAYLOAD / ABORT）、回退。
- OSC 编号：`FId: Int64`，`-1` 表示未开始；`FId := FId * 10 + digit` 前若 `FId > (High(Int64) - 9) div 10` 就不再增长（饱和，地雷 3）。查表时 `FId > High(Integer)` 视为没有处理器（进回退，回退收 `Int64`）。
- `end` / `unhook` 的循环：从最后注册的往前调，遇到返回 True 停止，**剩下的**继续调 `Finish(False)` / `Unhook(False)` 收尾（`OscParser.ts:156-181` 去掉 Promise 分支后的样子）。`reset` 在 OSC 是「PAYLOAD 态才收尾」，DCS / APC 是「有活动处理器就收尾」（三处条件不同，照原样）。
- 字符串处理器三个类（`OscHandler` / `DcsHandler` / `ApcHandler`）：用 Task 3 的 `TTyLimitedStringBuilder`；`hitLimit` 后 `Put` 直接返回；`Finish(ASuccess)`：超限返回 False、成功调回调、最后清空。`DcsHandler.hook` 的参数克隆条件照 `:155`（`(params.length > 1) or (params.params[0] <> 0)`，否则用共享的空参数 `[0]`）。
- 所有权：注册的处理器对象由子解析器持有，注销（句柄）或解析器析构时 `Free`（开工前问题二第 7 条）。

- [ ] **Step 3: `TTyTerminalParser`**（逐行对 `EscapeSequenceParser.ts:263-933`，去掉 `_parseStack` 与 Promise 分支）

- 构造：`FCurrentState := tpsGround`、`FParams := TTyTerminalParams.Create`、`FParams.AddParam(0)`、`FCollect := 0`、`FPrecedingJoinState := 0`、七个回退为空、执行处理器快表（`0..$17`）与完整表（`0..$FF`，键是字节）；最后注册 `ESC \` 吞掉的处理器（`:334-335`）——它也占一个句柄号，外部看不到。
- `_identifier` → 私有 `IdentOf(const AId; AFinalLo, AFinalHi): Cardinal`，校验失败抛 `EArgumentException`，消息照上游英文原句。
- CSI / ESC 处理器表：键 → 方法指针列表；`Register*` 返回句柄（全局递增的整数），句柄表记「哪一类、哪个键、列表里的哪一项」；`Unregister` 从列表里删掉那一项（上游 `splice`），找不到是空操作。`ClearCsiHandler` / `ClearEscHandler` 删整个键。
- `Parse(AData, ALength)`：主循环照 `:684-932`，顺序是 EXE 快路径 → CSI 快路径 → 查表 → `case` 动作；PRINT / PARAM / OSC_PUT / DCS_PUT / APC_PUT 的内循环条件逐字照抄（地雷：条件里 `>=` / `>` / `<` 的每一个都在变异表里）；ERROR 动作调错误处理器（`abort` 为 True 就 `Exit`）；三个 `*_END` / `DCS_UNHOOK` 在 `code = $1B` 时把下一状态并上 ESCAPE。
- `Reset`：照 `:495-510` 去掉 `_parseStack` 部分。
- `IdentToString`：照 `:375-382`。
- `OscPayloadLength`：当前 OSC 活动处理器里第一个字符串处理器的 `Length`（没有就 0）。纯查询，给有界断言用。

- [ ] **Step 4: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add source/tyControls.Terminal.Parser.pas && git commit -m "feat(terminal): the escape sequence parser, ported from xterm.js

The VT500 state machine with xterm.js's transition table built from the
same code at start-up, its two fast paths and inner loops, handler chains
keyed by prefix, intermediates and final byte, and the OSC, DCS and APC
sub-parsers. Payloads stop at ten million UTF-16 units as upstream counts
them, and an OSC number saturates instead of wrapping onto a real one.
Handlers are synchronous: the async continuation is not ported.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `tests/test.terminal.parser.pas`

**Files:**
- Create: `tests/test.terminal.oracle.pas`（不注册测试；本任务只写它的公共部分，Task 9、18 扩展）
- Create: `tests/test.terminal.parser.pas`
- Modify: `tests/tytests.lpr`（uses 里 `test.unicode.width,` 之后加 `test.terminal.oracle, test.terminal.parser,`）

**`tests/test.terminal.oracle.pas` 的公共部分**（主计划「比较器判据」）：`TTyTermMisses`（`Add(ACaseId, APath, AWant, AGot)`、`AddCompared(n)`、`Count`、`Compared`、`Text`，只存前 30 条）；`TyTermFixturePath`、`TyTermLoadFixtures(AKind)`（读 `terminal-<kind>.json` 与 `terminal-<kind>-<n>.json`，分片的 `parts` 一致、`part` 连号，否则记一条 miss）；`TyTermCheckUpstream(AFixture, AMisses)`（commit 以 `c58ea36` 开头、`version = '6.0.0'`）；`TyTermDigest(const ACps: array of Cardinal): Cardinal`、`TyTermDigestUtf8(const S: string): Cardinal`（主计划「夹具格式」的长串摘要，局部 `{$Q-}{$R-}`）；`TyTermJsonDigestable(ANode, out AIsDigest, out AN, out AH, out APlain)`（读「原样或 `{n, h}`」两种形状）。数值一律按 `Int64` 读（`AsInt64`）。

`tests/test.terminal.parser.pas` 的单元头注释照 `tests/test.unicode.width.pas`：夹具从哪来、守什么、比较是精确的。

#### `TTyTerminalParserOracleTests`（夹具）

每个测试都**数比较次数并断言**（主计划「比较器判据」）。

| 测试 | 比什么 | 计数必须等于 |
|---|---|---|
| `TestFixturesComeFromThePinnedUpstream` | 三份（含分片）夹具的 `upstream.commit` 相同、以 `c58ea36` 开头、`version = '6.0.0'` | — |
| `TestTransitionTableMatchesUpstream` | 区间表逐项对 `TyTermTransition(i)` | 4257 |
| `TestUtf8DecodeChunkByChunk` | 每个用例一个新解码器，逐块 `Decode`，比返回数与每个码位 | 所有 `out` 的码位数 + 块数 |
| `TestHandTraces` | 手写用例：照 `register` 装处理器（Pascal 版的记录器和 node 版同规则），照 `feed` 喂，逐事件比轨迹（事件类型、标识、`paramsJson` 字符串、载荷或摘要、成功标志），再比 `finalState`（按上游数值）、`finalJoinState` | 所有用例的事件数 + 用例数 × 2 |
| `TestEveryCutTraces` | 切点用例，同上 | 同上 |
| `TestLongInputsStayBounded` | 长用例，同上；另外：`long-osc-*` 喂的过程中每次 `Parse` 之后 `OscPayloadLength <= TyTermParserPayloadLimit`；整条喂完后 `GetFPCHeapStatus.CurrHeapUsed` 比用例开始前多不超过 2MB（数据释放了） | 同上，外加每个长 OSC 用例的每一块 |
| `TestFuzzTraces` | 随机用例，同上 | 同上 |

失败信息：`case <id> event #<n>: want ["csi",27971,"[1,2]"] got ["csi",27971,"[1]"]`，再附前后各两个事件。

#### `TTyTerminalParserTests`（纯函数，照表）

**1. `TestParamsBuild`**（每行新建一个 `TTyTerminalParams`，照「操作」调，比 `ToJson` 和 `Length`）

| 操作 | `ToJson` |
|---|---|
| `AddParam(0)` | `[0]` |
| `AddParam(1); AddSubParam(2); AddSubParam(3); AddParam(4)` | `[1,[2,3],4]` |
| `AddSubParam(5)`（没有参数） | `[]` |
| `ResetZdm; AddDigit(1); AddDigit(2)` | `[12]` |
| `ResetZdm; AddSubParam(-1); AddDigit(7)` | `[0,[7]]` |
| `ResetZdm` 后 `AddDigit(9)` 22 次 | `[2147483647]` |
| `AddParam(1)` 33 次 | 32 个 `1`（`Length = 32`） |
| `AddParam(1)` 32 次，再 `AddDigit(5)` | 32 项，最后一项 `15`（第 32 次还没满，数字照常累加） |
| `AddParam(1)` 33 次，再 `AddDigit(5)` | 32 项，最后一项 `1`（第 33 次置 `FRejectDigits`，`:160-162`） |
| `AddParam(1)`，再 `AddSubParam(1)` 33 次 | `[1,[1,…]]`，子参数 32 个 |
| `AddParam(2147483647); AddParam(-1)` | `[2147483647,-1]` |

**2. `TestParamsRejectsBadInput`**：`Create(32, 257)` 抛 `EArgumentException`；`AddParam(-2)`、`AddSubParam(-2)` 抛。

**3. `TestIdentifierRules`**（`RegisterCsiHandler` / `RegisterEscHandler` / `RegisterApcHandler`，期望「句柄 > 0」或「抛 `EArgumentException`」）

| 调用 | 期望 |
|---|---|
| CSI `('', '', 'm')` | 成功 |
| CSI `('??', '', 'm')` | 抛（前缀多于一字节） |
| CSI `('!', '', 'm')` | 抛（前缀不在 `0x3C`–`0x3F`） |
| CSI `('', '!!!', 'p')` | 抛（中间字节多于两个） |
| CSI `('', '0', 'p')` | 抛（中间字节不在 `0x20`–`0x2F`） |
| CSI `('', '', '0')` | 抛（CSI 终止字节下限 `0x40`） |
| ESC `('', '', '0')` | 成功（ESC 下限 `0x30`） |
| CSI `('', '', #$7F)` | 抛 |
| APC `('?', '', 'G')` | 成功（APC 忽略前缀，`:468`） |

**4. `TestIdentToString`**：`IdentToString($3F2470)`（`?` `$` `p`）= `'?$p'`；`IdentToString(Ord('m'))` = `'m'`；`IdentToString(0)` = `''`。

**5. `TestUnregister`**：未知句柄 `Unregister(9999)` 不抛；同一句柄注销两次不抛；注销 OSC 字符串处理器后，处理器对象已释放（测试里用一个子类，析构时把外部计数器加一）。

**6. `TestHandlersFreedWithTheParser`**：注册 OSC / DCS / APC 各两个（测试子类），`Free` 解析器后计数器 = 6。

**7. `TestCodepointsToUtf8`**

| 码位 | UTF-8 字节 | `TyTerminalUtf16Length` |
|---|---|---|
| `[$41]` | `41` | 1 |
| `[$E9, $4E2D]` | `C3 A9 E4 B8 AD` | 2 |
| `[$1F600]` | `F0 9F 98 80` | 2 |
| `[$D800]` | `EF BF BD`（U+FFFD） | 1 |
| `[$110000]` | `EF BF BD` | 2（照 `> $FFFF` 记 2，注释写明这类输入上游不产生） |

**8. `TestDecoderLeavesNothingBehindAfterClear`**：喂 `E4`，`Clear`，再喂 `B8 AD 61` → 输出 `[$61]`（`B8`、`AD` 作为孤立续字节被跳过）。

- [ ] **Step 1: 写 `test.terminal.oracle.pas` 的公共部分与测试单元**，后者 `initialization` 里 `RegisterTest(TTyTerminalParserOracleTests); RegisterTest(TTyTerminalParserTests);`
- [ ] **Step 2: 登记到 `tests/tytests.lpr`**（编辑工具）
- [ ] **Step 3: 提交**（不编译）

```bash
cd /d/Projects/ty-3.1 && git add tests/test.terminal.oracle.pas tests/test.terminal.parser.pas tests/tytests.lpr && git commit -m "test(terminal): the parser held to xterm.js event by event

The transition table entry by entry, the UTF-8 decoder call by call, and
the full callback trace for hand, cut, oversized and random input, each
with its comparison count asserted so an empty fixture cannot pass; plus
tables for params, identifier rules and handler ownership.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**变异表（期末做，Task 23 Step 5；改 `source/tyControls.Terminal.Parser.pas`）：**

| # | 变异 | 必须红 |
|---|---|---|
| P1 | `AddParam`：`FLength >= FMaxLength` → `>` | `csi-33-params`、`TestParamsBuild` |
| P2 | `AddDigit`：去掉和 `$7FFFFFFF` 取小 | `csi-param-overflow`、`long-digits` |
| P3 | `AddSubParam`：去掉 `FRejectDigits or` | `csi-subparam-after-reject` |
| P4 | 转移表：删掉 `add($7F, CSI_ENTRY, IGNORE, CSI_ENTRY)` | `TestTransitionTableMatchesUpstream`、`csi-7f-inside` |
| P5 | EXE 快路径：`ACode < $18` → `< $20` | `esc-basic` 等几乎全部（ESC 被当控制字符执行） |
| P6 | CSI 快路径：删掉 `FPrecedingJoinState := 0` | `csi-fast-after-print`（`finalJoinState`） |
| P7 | CSI 快路径：前缀判断 `>= $3C` → `> $3C` | `csi-prefix-each`（`<` 前缀的序列被丢弃） |
| P8 | PRINT 内循环：`>= NON_ASCII_PRINTABLE` → `>` | `print-nonascii`（U+00A0 切断打印区间） |
| P9 | OSC_PUT 内循环：去掉 `(code < $20) or` | `osc-c0-inside`、`osc-bel` |
| P10 | OscParser.put：删掉非数字编号转 ABORT 的判断 | `osc-bad-id` |
| P11 | OSC 编号改成 `Integer` 普通累加（去掉饱和） | `osc-id-huge`（回绕成 4 命中处理器）、`long-osc-id` |
| P12 | 字符串处理器上限：`>` → `>=` | `long-osc-exact` |
| P13 | 上限计数改成按码位（不按 UTF-16） | `long-osc-astral` |
| P14 | OSC_END：`success` 条件去掉 `$1A` | `osc-sub` |
| P15 | OSC_END：删掉 `code = $1B` 时并入 ESCAPE | `osc-st`（`\` 被打印） |
| P16 | DcsHandler.hook：克隆条件取反 | `dcs-params` |
| P17 | APC_PUT 内循环：去掉 `$08..$0D` 的允许区间 | `apc-allowed-bytes` |
| P18 | 解码器三字节：去掉 `= $FEFF` 判断 | `bom-whole` |
| P19 | 解码器半截路径：删掉续字节错时的 `startPos--` | `split-bad-cont` |
| P20 | 解码器四字节：删掉 `> $10FFFF` 判断 | `beyond-max` |
| P21 | ESC_DISPATCH：删掉回退调用 | `esc-basic`、`esc-final-ranges` |
| P22 | 处理器链：循环方向改成从第一个注册的开始 | `csi-chain`、`osc-chain` |
| P23 | `Unregister` 改成空操作 | `unregister-csi`、`TestUnregister` |
| P24 | `Reset`：删掉 `FOscParser.Reset` | `reset-mid-osc` |
| P25 | ERROR 动作：不调错误处理器 | `print-del` |
| P26 | OscParser.end：删掉「ID 态收尾时补 START」 | `osc-no-payload` |
| P27 | DcsParser.reset：条件改成和 OSC 一样（只在某状态收尾） | `reset-mid-dcs` |

**等价、不做的**：EXE 快路径的 `currentState <= CSI_IGNORE` 改成 `<`（CSI_IGNORE 下表里同样是「执行、留在原态」，走表和走快路径结果相同）；四字节 ASCII 展开改成单字节循环（Step 3 允许两种写法，结果相同）。
