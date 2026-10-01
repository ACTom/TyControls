# 主题编辑器 3 期：AI 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：整期**连续写完**——每个任务只写代码 + 测试并单独提交，任务之间**不编译、不跑测试**（例外只有 Task 0：基线编译与全量，产出记进草稿）；Task 1–14 写完后在 Task 15 **一次编译**、跑本期 suite 和全量、在 WSL 里跑 libcurl 那条路、集中修红、按 spec 逐条核代码、集中变异、期末审查、写回 spec、签收；Task 16 把本期的真机项追加进三期共用的验收文档。中途不汇报、不问要不要提交。**三期做完用户一次性真机验收**。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：问用户、编 `tycontrols.lpk` / `tycontrols_dt.lpk`、截图、启动 GUI 冒烟、拿用户的真密钥或本机模型跑真实生成。实现 agent 不编任何 `.lpk`。**`tools/themebuilder/themebuilder.lpi` 与 WSL 里的控制台程序 `tools/themebuilder-curl-wsl` 实现 agent 可以编**（Task 15，编法见「跑测试的固定套路」）。
>
> **起点**：本计划在 **2 期签收之后**执行（2 期计划 `docs/superpowers/plans/2026-10-01-themebuilder-phase-2.md` 末尾的签收已填）。本期用到 2 期留下的 `ApplyEdits`、`TbEdit` / `TTbTextEdit`、`TbSeedNames`、`ShowSidePage`；Task 0 逐个核对它们的实际签名，与本计划写的不同就以代码为准、在本计划里就地改名并记进签收。
>
> **共享文件**：本期**不改任何库文件**——`source/` 与 `designtime/` 一个字节都不动。本期需要的库能力全是现成的公开 API（核实记录 6、7、9）。执行中发现非改库不可，停下交主控，主控先问用户。

**Goal:** 在 1、2 期的编辑器上接通 spec §7 的 AI：侧栏第三页「AI」——选一个配置好的服务（OpenAI 兼容 / Anthropic / 本地 Ollama），用一句话描述想要的主题，流式看到模型的回答，随时可停；回答里的 tycss 代码块经解析器、`TyLintCssEx` 与预览试解析把关，有错自动回喂最多 2 次；最后在左右并排的对比窗口里看改了什么，可以先在预览里试看，「接受」一步替换编辑器全文（Ctrl+Z 一次撤回），「放弃」什么都不变；网络、密钥、限流、超时、格式不对、找不到 libcurl 都用一句话说清。

**Architecture:** 引擎在 `tools/themebuilder/ai/`，界面在 `tools/themebuilder/` 顶层。最底下是一个阻塞式 HTTP 传输（`tbhttp` 定接口；Windows 用自己声明的 WinHTTP，Linux / macOS 用 `dynlibs` 运行时加载的 libcurl 函数表，找不到就报告原因、只关 AI），一次请求在工作线程里跑、字节随到随交；上面是与 LCL 无关的 SSE 拆分器（`tbsse`）、两种接口格式的请求构造与事件解读（`tbaiformat`）、一次流式调用与错误归类（`tbaiclient`），以及配置与密钥（`tbaisettings`：Windows DPAPI、其他平台 0600 文件）——这五个单元与测试用的本机 HTTP 服务（`tests/tbfakehttp.pas`）一起也在 WSL 里用 `fpc` 编成控制台程序，跑 libcurl 那条路。再上面是精简参考（`tbreference`：运行时从库的数组与内置默认主题拼出来，不是构建时生成的文件）、一次生成的状态机（`tbaisession`：拼提示、多轮记住描述、取代码块、校验、回喂），全在主线程。界面：AI 页 frame（`tbaiframe`）、设置对话框（`tbaisettingsform`）、对比窗口（`tbcompareform`，两个只读 SynEdit 并排，行对齐、改动行着色）、按行对比算法（`tbdiff`）；预览 frame 加「试看」（暂换文本、结束还原），主窗体用 2 期的 `ApplyEdits` 把接受的结果包成一步撤销。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4 LCL、SynEdit、BGRABitmap、FPC `fpjson` / `jsonparser`、`dynlibs`、`sockets`（测试服务）、`base64`、`IniFiles`；Windows 的 `winhttp.dll` 与 `crypt32.dll`；Linux / macOS 的系统 libcurl；fpcunit（`tests/tytests.lpi`）；WSL Ubuntu 里的 `fpc` 3.2.2；Python 3（`scripts/example-rsj2po.py`）。

**设计依据:** `docs/superpowers/specs/2026-10-01-theme-builder-design.md`（下称 spec）§9 第 3 条，细节在 §7 全节、§8 的 AI 一行、§10 的风险，以及各处「实现期修正（1 期）」「实现期修正（2 期）」。1 期计划 `docs/superpowers/plans/2026-10-01-themebuilder-phase-1.md`（下称 1 期计划）与 2 期计划（下称 2 期计划）的格式、约定、硬规则本期照用。

**不在本期**：AI 的「工具调用式」小改动（spec §3）；把 HTTP / 大模型客户端做进库（spec §3）；预置模型列表的在线刷新；重试与退避（429 / 5xx 只说清原因，由用户再点一次）；CHANGELOG（发版时写）；合 `main`。

---

## 总目录

| 部分 | 任务 | 这一批做完能看到什么（执行时不单独验收） |
|---|---|---|
| 基线 | Task 0 | 起点、全量条数、核对 2 期接口、主控定开工前问题 |
| 传输 | Task 1–2 | 接口与地址拆分、WinHTTP、本机测试服务；libcurl 函数表与 WSL 控制台程序 |
| 协议 | Task 3–5 | SSE 拆分（事件跨块）；两种接口格式的请求与事件；一次流式调用、错误归类成一句话、密钥不外露 |
| 配置 | Task 6 | 多个配置、五种预置、DPAPI / 0600 的密钥存储 |
| 参考 | Task 7 | 运行时拼出的精简参考、与源同步的守卫、约 5–8 千 token |
| 对比 | Task 8 | 按行对比、行对齐、「整篇替换」压成只换中间那段 |
| 一次生成 | Task 9 | 提示词、多轮、取代码块、校验（解析 + lint + 试解析）、回喂 ≤ 2 次、停止 |
| 界面 | Task 10–12 | 预览试看与对比窗口；设置对话框与测试连接；AI 页与主窗体接线 |
| 双语与文档 | Task 13–14 | 中英 `.po`；工具的使用文档与 README |
| 收尾 | Task 15 | 一次编译、全量、WSL、按 spec 逐条核、集中变异、主控编包冒烟、审查、写回 spec、签收 |
| 验收文档 | Task 16 | 往三期共用的验收文档追加 3 期各项与决定 |

---

## 核实记录（写计划时读源码，2026-10-01，`feat/theme-builder` @ `f87c46c6`，2 期正在实现）

**1. WinHTTP（spec §2 第 8 条、§7.1 代理）**

1. FPC 有绑定：`C:/lazarus/fpc/3.2.2/source/packages/winunits-base/src/winhttp.pp`（797 行，H2Pas 机器转换，`External_library='winhttp.dll'`，静态导入），已编好在 `fpc/3.2.2/units/x86_64-win64/winunits-base/winhttp.ppu`。**不用它，自己声明**，理由：
   - `:735` 把 `WinHttpSetTimeouts` 写成了 **`WinHttpSetTimes`**——`winhttp.dll` 没有这个导出，调用它要么链接失败、要么进程起不来；
   - 错误常量被转换器改坏了名字：`:436` `ERROR_WINHTTPOF_HANDLES`（原名 `ERROR_WINHTTP_OUT_OF_HANDLES`）、`:437` `ERROR_WINHTTP_TIME`（原名 `ERROR_WINHTTP_TIMEOUT`，12002）；
   - 需要的只有十个函数、十几个常量（`:413-416` 的四种访问方式、`:61` `WINHTTP_FLAG_SECURE = $00800000`、`:299` `WINHTTP_QUERY_STATUS_CODE = 19`、`:359` `WINHTTP_QUERY_FLAG_NUMBER = $20000000`、`:425`/`:429` 的 `WINHTTP_ADDREQ_FLAG_ADD` / `_REPLACE`、`:435-` 的错误码）。声明照 `:727-750` 的签名，`WinHttpSetTimeouts(hInternet: HINTERNET; nResolveTimeout, nConnectTimeout, nSendTimeout, nReceiveTimeout: Integer): BOOL; stdcall; external 'winhttp.dll'`。
2. `WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4`（`:416`）要 Windows 8.1 起；更早的系统 `WinHttpOpen` 返回 nil、`GetLastError = ERROR_INVALID_PARAMETER`（87），这时退回 `WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0`（`netsh winhttp` 的设置）。本机（Win10 19044）`netsh winhttp show proxy` 是「直接访问」。
3. 本机地址不走代理：地址是 `localhost` / `127.x.x.x` / `::1` 时用 `WINHTTP_ACCESS_TYPE_NO_PROXY = 1` 另开会话（自动代理的 PAC 不一定排除本机；测试服务也在本机）。
4. 同步用法（全部在工作线程）：`WinHttpOpen` → `WinHttpSetTimeouts`（解析、连接用连接超时；发送、接收用「空闲超时」，接收超时对每次 `WinHttpReceiveResponse` / `WinHttpQueryDataAvailable` / `WinHttpReadData` 生效——Task 1 的 H6 验证这个说法）→ `WinHttpConnect` → `WinHttpOpenRequest('POST', path, …, 安全时 WINHTTP_FLAG_SECURE)` → `WinHttpAddRequestHeaders`（UTF-16、`CRLF` 连起来、长度 `DWORD(-1)`）→ `WinHttpSendRequest(正文指针, 长度, 长度)` → `WinHttpReceiveResponse` → `WinHttpQueryHeaders(STATUS_CODE or FLAG_NUMBER)` → 循环 `WinHttpQueryDataAvailable`（阻塞到有数据；0 = 读完）+ `WinHttpReadData`。分块编码 WinHTTP 自己拆。**取消**：别的线程在锁里置标志并 `WinHttpCloseHandle(请求句柄)`，阻塞中的调用随即失败（`ERROR_WINHTTP_OPERATION_CANCELLED` 12017 或 `ERROR_INVALID_HANDLE` 6），工作线程看到标志就报「已取消」；句柄只关一次（锁 + 已关标志）。
5. 错误码（Windows SDK `winhttp.h`）：12002 超时、12005 地址不对、12006 协议不认、12007 主机名解析不了、12017 已取消、12029 连不上、12030 连接中断、12152 应答不对、12175 安全连接失败（12157、12169 等 `ERROR_WINHTTP_SECURE_*` 也归这类）。

**2. libcurl（Linux / macOS）**

6. FPC 的绑定 `packages/libcurl/src/libcurl.pp`（1583 行）是**静态链接**：`:45` `External_library='libcurl'`，`:1518-1559` 全是 `external External_library name '…'`——编出来的程序在链接时就要 `-lcurl`、运行时没有 libcurl 就起不来，违背 spec「找不到只关 AI」。所以自己用 `dynlibs`（`rtl/inc/dynlibs.pas`：`LoadLibrary`、`GetProcedureAddress`、`NilHandle`）建最小函数表：`curl_global_init`、`curl_easy_init`、`curl_easy_setopt`、`curl_easy_perform`、`curl_easy_getinfo`、`curl_easy_cleanup`、`curl_easy_strerror`、`curl_slist_append`、`curl_slist_free_all`。**不 `uses libcurl`**（只为常量引它也会把 `-lcurl` 带进链接），常量自己写（数值抄自 `libcurl.pp`）：`CURLOPT_URL = 10002`（`:460`）、`CURLOPT_WRITEDATA = 10001`（`:458`）、`CURLOPT_WRITEFUNCTION = 20011`（`:479`）、`CURLOPT_POSTFIELDS = 10015`（`:496`）、`CURLOPT_POST = 47`（`:569`）、`CURLOPT_POSTFIELDSIZE = 60`（`:596`）、`CURLOPT_HTTPHEADER = 10023`（`:524`）、`CURLOPT_USERAGENT = 10018`（`:503`）、`CURLOPT_LOW_SPEED_LIMIT = 19` / `_TIME = 20`（`:510-512`）、`CURLOPT_NOPROGRESS = 43`（`:565`）、`CURLOPT_XFERINFODATA = 10057`（即 `PROGRESSDATA`，`:589`）、`CURLOPT_XFERINFOFUNCTION = 20219`（`:1002`）、`CURLOPT_CONNECTTIMEOUT = 78`（`:638`）、`CURLOPT_NOSIGNAL = 99`（`:694`）、`CURLOPT_ERRORBUFFER = 10010`（`:476`）、`CURLOPT_PROXY = 10004`（`:464`）、`CURLINFO_RESPONSE_CODE = $200002`（`:1193`）、`CURL_GLOBAL_DEFAULT = 3`（`:1423-1424`）；错误码 1 协议不认、3 地址不对、5 代理解析不了、6 主机解析不了、7 连不上、18 没收完、23 写回调中止、28 超时、35 安全连接、42 进度回调中止、52 什么都没收到、55 发送、56 接收、60 证书。
7. `curl_easy_setopt` / `curl_easy_getinfo` 是 **C 变参函数**（绑定 `:1554`、`:1558` 用 `args: array of const` 表达）。函数表里用 `cdecl` 过程类型 + 末参 `array of const`：`TCurlSetopt = function(h: Pointer; opt: LongInt; args: array of const): LongInt; cdecl;`——FPC 把 cdecl 的 `array of const` 按 C 变参传，过程类型这样写有先例（`packages/objcrtl/src/objcrtl10.pas:114` `IMP1 = function (param1: id; param2: SEL; param3: array of const): id; cdecl;`）。**长整型实参一律写成 `Int64(...)`**（Linux / macOS 64 位上 C 的 `long` 是 64 位，`Integer` 进变参槽只有 32 位，高位是垃圾），指针写 `Pointer(...)`。Apple arm64 的变参走栈，靠的是 FPC 对 cdecl `array of const` 的处理——本机测不到，列为风险（开工前问题二第 4 条），验收在真 Mac 上看。
8. 回调：写回调 `function(p: PChar; size, nmemb: PtrUInt; ud: Pointer): PtrUInt; cdecl`，返回不等于 `size*nmemb` 即中止（`CURLE_WRITE_ERROR`）；进度回调 `function(ud: Pointer; dltotal, dlnow, ultotal, ulnow: Int64): LongInt; cdecl`（`:210` 的 `curl_XFERINFO_callback`），返回非 0 中止（`CURLE_ABORTED_BY_CALLBACK`）——libcurl 空闲时也约每秒调一次，所以取消最迟约 1 秒生效。状态码：第一次写回调里 `curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, [Pointer(@code)])`（`code: Int64`）。空闲超时：`LOW_SPEED_LIMIT = 1`、`LOW_SPEED_TIME = 空闲秒数`。`NOSIGNAL = 1`（多线程）。正文较大时较老的 libcurl 会发 `Expect: 100-continue`——请求头加一行 `Expect:`（空值）关掉它；测试服务也认 100-continue。
9. 代理：libcurl 默认读 `http_proxy` / `https_proxy` / `no_proxy` 环境变量（spec §7.1），不用设；本机地址时设 `CURLOPT_PROXY = ''`（空串 = 不用代理）。
10. 库名候选（spec §10）：先看环境变量 `THEMEBUILDER_LIBCURL`（给发行版名字特别的情况，也是验收「找不到 libcurl」那一项的办法），再按序试 Linux `libcurl.so.4`、`libcurl-gnutls.so.4`、`libcurl-nss.so.4`、`libcurl.so`；macOS `/usr/lib/libcurl.4.dylib`、`libcurl.4.dylib`、`libcurl.dylib`。函数表缺任何一个函数也当没找到（原因里说缺哪个）。`curl_global_init` 只在主线程、第一次加载时调一次。
11. WSL：`wsl.exe -l` 有 `Ubuntu`（另有 `Ubuntu-26.04`）；`Ubuntu` 里 `fpc -iV` = 3.2.2，`/usr/lib/x86_64-linux-gnu/` 有 `libcurl.so.4`（→ `4.8.0`）与 `libcurl-gnutls.so.4`，`/usr/lib/fpc/3.2.2/units/x86_64-linux/` 有 `fcl-json`、`fcl-net`、`fcl-web`，有 `python3`、`curl`。先例：终端 7 期的 `tools/terminal-zmodem-wsl/zmwsl.lpr`（不依赖 LCL 的单元在 WSL 里 `fpc -Mobjfpc -Sh -FUlib -Fu… x.lpr && ./x`，打印 `PASS` / `FAIL` 与「N passed, M failed」，退出码 M；目录里 `.gitignore` 忽略可执行文件与 `lib/`）。

**3. DPAPI 与 0600 文件（spec §7.1）**

12. FPC 有：`packages/winunits-jedi/src/jwawincrypt.pas:14836`（`CryptProtectData`）、`:14841`（`CryptUnprotectData`）、`:19848-19849`（`external crypt32`）、`:1203-1253`（`DATA_BLOB`）、`:14808` `CRYPTPROTECT_UI_FORBIDDEN = 1`。它拖着整套 JWA 类型单元；只要两个函数和一个记录，**自己声明**（`crypt32.dll`，`stdcall`），释放输出用 `Windows.LocalFree`。熵（`pOptionalEntropy`）用固定的 `'TyControls.ThemeBuilder.AI'`，标志 `CRYPTPROTECT_UI_FORBIDDEN`，当前用户范围（不加 `LOCAL_MACHINE`）。
13. Unix：`BaseUnix.fpOpen(name, O_WRONLY or O_CREAT or O_TRUNC, &600)` 建文件（新建时就是 0600，不留「先 0644 再 chmod」的窗口），写完 `fpFChmod(fd, &600)` 兜底（文件原来就在、权限更宽时）；读的时候发现组 / 其他人可读就 `fpChmod(name, &600)` 改回来。先写到同目录临时文件再 `fpRename`（照 1 期保存的原子写法）。

**4. JSON 与 SSE（spec §7.3、§8）**

14. 构造：`fpjson` 的 `TJSONObject` / `TJSONArray`，`AsJSON` 出文本。`TJSONStringType = UTF8String`（`fcl-json/src/fpjson.pp:50`）；`StringToJSONString` 只转义 `"`、`\`、`#0..#31`（`/` 只在 strict 时），非 ASCII 原样输出 UTF-8——中文描述与中文注释原样进请求体（Task 4 的 A3 守着）。仓库的用法：`source/tyControls.ThemeBundle.pas:126-160`（`GetJSON` + `TJSONObject`）、`source/tyControls.Terminal.ColorScheme.pas:519-540`（`TJSONParser.Create(…, [joUTF8, …])`）。
15. 解析：`TJSONParser.Create(s, [joUTF8])`。FPC 3.2.2 的 `jsonscanner.pp:342-372` 把连续两个 `\u` 当一对拼起来、`\u0000` 会丢（仓库记忆「fpjson 吞掉 \u0000」）：两个 BMP 字符相邻拼起来结果仍对，代理对也对，只有 NUL 丢。模型的回答里不会有 NUL；服务端用 `ensure_ascii` 风格把中文写成 `\u4e2d\u6587` 的（DeepSeek 等 Python 后端常见）由 Task 4 的 A6 守着，红了再加预解码。**不复用** `TyTermJsonDecodeEscapes`（`Terminal.ColorScheme.pas:161-166`）：那个单元 `uses Graphics`，WSL 里的无 LCL 程序编不进去。
16. SSE 自己写（WHATWG 的事件流规则）：行以 CRLF / LF / CR 结束（块末尾单独一个 CR 要等下一个字节才知道是不是 CRLF）；流开头的 BOM 去掉；`:` 开头是注释；`field: value`，冒号后一个空格去掉；`data` 多行用 LF 连起来；`event` 设事件名（默认 `message`）；`id`、`retry`、不认的字段忽略；没有冒号的行是「字段名 = 整行、值为空」；空行派发（数据为空不派发）；流结束时没等到空行的半个事件丢掉。
17. 两种格式的流（**样本按官方文档手写**：本机没有 Ollama——`curl localhost:11434` 不通；能访问 `api.openai.com`、`api.anthropic.com`（不带密钥分别 401、405），但没有密钥，录不了真流）：
    - **OpenAI 兼容**（`POST {base}/chat/completions`；`Authorization: Bearer <key>`，没有密钥不发这一行）：`data: {"id":…,"object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}`，随后每块 `choices[0].delta.content`；结束块 `finish_reason` 为 `stop` / `length`（`length` = 到了最大输出被截断）/ `content_filter`；最后 `data: [DONE]`。DeepSeek 推理模型另有 `delta.reasoning_content`（当「在思考」）、`: keep-alive` 注释行；流中出错少数代理会发 `data: {"error":{"message":…}}`。非 2xx 的应答体：`{"error":{"message":…,"type":…,"code":…}}`（OpenAI、DeepSeek、Ollama 的 `/v1` 都是这个形状；Ollama 原生接口是 `{"error":"…"}` 字符串，也认）。OpenAI 的 401 消息原文会带**半遮的密钥**（`Incorrect API key provided: sk-proj-****…abcd.`）——必须洗掉（Task 5 的 `TbScrubSecret`）。
    - **Anthropic**（`POST {base}/messages`；`x-api-key`、`anthropic-version: 2023-06-01`、`content-type: application/json`；正文 `model`、`max_tokens`（**必填**）、`system`、`messages`、`stream: true`）：`event: message_start` → `content_block_start`（`content_block.type` 为 `text` 或 `thinking`）→ `content_block_delta`（`delta.type` 为 `text_delta`（取 `delta.text`）、`thinking_delta`、`signature_delta`）→ `content_block_stop` → `message_delta`（`delta.stop_reason`：`end_turn` / `max_tokens`（截断）/ `refusal`（拒绝）/ `stop_sequence`）→ `message_stop`；中间夹 `event: ping`；流中出错 `event: error` + `{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}`。非 2xx 应答体同样 `{"type":"error","error":{"type":…,"message":…}}`，状态 400 / 401 / 403 / 404 / 429 / 500 / 529。来源：Anthropic API 文档的 Messages 流式一节与错误一节（写计划时由 `claude-api` 技能的 `curl/examples.md`、`shared/error-codes.md` 核对）。**当前模型默认带自适应思考**，流里先来 `thinking` 块（默认不显示内容，`thinking` 文字为空）、然后才是正文——界面要显示「模型在思考…」，否则看起来像卡住。
    - 两种都要兼容「服务没按流式回答」：2xx 但应答体是一整段 JSON（OpenAI 形状 `choices[0].message.content`、Anthropic 形状 `content[*].text`）——有的代理会这样。当作一次性收到全文。
18. Ollama：OpenAI 兼容地址是 `http://localhost:11434/v1`，不要密钥。它默认的上下文很短（2048–4096 token，按版本），超出部分**静默截掉开头**——系统提示与参考首当其冲。不在请求里改得了（OpenAI 兼容接口不收 `num_ctx`），只能在启动 Ollama 前设 `OLLAMA_CONTEXT_LENGTH`。设置对话框与文档里说一句（本机没有 Ollama，这条按其文档写，验收时用真模型看）。

**5. 测试里的本机 HTTP 服务**

19. `fcl-web` 的 `fphttpserver` 能起服务，但应答走 `TFPHTTPConnectionResponse.SendContent` 一次写完，要「分块、慢发、中途断开、一直不回」得绕到底层 socket；`fcl-net` 的 `ssockets.TInetServer`（`ssockets.pp:189-202`）可以，但拿实际端口与停服都要自己再包。**自己写一个最小服务**（`tests/tbfakehttp.pas`，约 250 行）：`sockets` 单元（Windows 版在 `initialization` 里 `WSAStartup`，`packages/rtl-extra/src/win/sockets.pp:278-282`；函数 `fpSocket` / `fpBind` / `fpListen` / `fpAccept` / `fpRecv` / `fpSend` / `fpGetSockName` / `fpShutdown` / `CloseSocket`，`packages/rtl-extra/src/inc/socketsh.inc:157-172`），绑 **`127.0.0.1` 端口 0**、`fpGetSockName` 取实际端口，一个后台线程逐个接连接、按脚本应答（发一段字节 / 睡 N 毫秒 / 关连接 / 一直挂着直到停服）。停服：置标志、放开「挂着」的等待、自己连一次自己把阻塞的 `accept` 叫醒。**只绑回环地址**：绑 `0.0.0.0` 会让 Windows 防火墙在用户桌面弹询问框（仓库记忆「探针程序会在用户桌面弹模态框」）。这个单元只用 `Classes`、`SysUtils`、`SyncObjs`、`sockets`，WSL 里同样编得过。

**6. 精简参考的来源（spec §7.2）**

20. 可以直接从代码读的：`TyCatalogTypeKeys`（253 个，`source/tyControls.Css.Catalog.pas:279`）、`TyCatalogTokens`（256 个，`:21`）、`TyKnownStyleProps`（23 个，`source/tyControls.StyleModel.pas:226-231`）、`TyStyleValueHints(prop, dest)`（`:237`、`:913-933`，封闭关键字集）、`TyKnownColorFns`（9 个，`source/tyControls.Css.Values.pas:35-36`）、`TyKnownPseudoStates`（6 个，`checked` 是 `selected` 的别名，`source/tyControls.Css.Parser.pas:101-102`）。种子与推导变量：内置默认主题 = `TyBuiltinThemeCss('default')`（即 `themes/auto.tycss`，`source/tyControls.BuiltinThemes.pas:18`），用 `TTyCssParser` 解析后 `ModeBlocks`（`Css.Parser.pas:45`，每块 `Mode` + `Vars`：`name=value`、不带 `--`、保持出现顺序）里亮、暗两块的 `:root`（源文件 `:507-560` 亮、`:562-` 暗：SEED 六个、MAP 由种子 `darken` / `lighten` 出来的、ALIAS 语义别名、COMPONENT 标量）；变体：同一份解析结果里规则选择器的 `TypeName` + `Variant`（如 `TyButton.primary` / `.danger` / `.ghost`）。种子名用 2 期的 `TbSeedNames`（`tools/themebuilder/tbseeds.pas:30`）。
21. 不能从代码读、要手写的：语法与限制（`docs/tycss-reference.md` §2.3–2.4 `:115-138`、§4.1–4.2 `:206-239`、§8.1「整键替换」`:721-752`、§9 限制汇总 `:1224-1288`——中文、约 2 万 token，不能直接发）、每个属性取值的写法（`padding` 一到四个长度、`font-size` 按 pt……）、每个颜色函数的签名、一个完整的小例子。
22. **生成方式改为运行时拼**（开工前问题二第 5 条）：spec 写「构建时由脚本生成、编进工具，守卫测试保证生成物与源一致」。可读的那一半本来就编在库里（数组与函数），工具运行时直接拼，**不可能**与源不一致；要脚本生成就得用 PowerShell 去解析 Pascal 源码（`TyStyleValueHints` 是代码不是数据）——比 `scripts/gen-tycss-catalog.ps1` 解析 tycss 脆得多。手写的那一半由守卫测试钉住：每个属性都有说明、没有多余的；每个颜色函数都有签名且签名里的例子求值不抛；每条「不支持」都配一段必须解析失败的片段、每条「支持」配一段必须通过的；例子解析干净、lint 无错、两种模式试解析都过。token 粗估 = 字节数 ÷ 4（参考全是 ASCII 英文，约 4 字节一个 token），守卫在 4 千–8.5 千之间。
23. 写计划时粗算：typeKey 清单约 4 KB、变量名约 5.5 KB、亮色推导变量约 2.8 KB、属性与取值约 2 KB、函数约 0.6 KB、规则与限制约 4 KB、例子约 1.5 KB，合计约 20 KB ≈ 5 千 token，在 spec 的 6–8 千以内偏下；Task 15 打印实数。

**7. 与 1、2 期的衔接**

24. 侧栏：`tbmain.lfm` 的 `SideBar: TTyToolWindowBar` 现在是「种子、问题」两页（2 期 Task 9），窗口顺序 = `.lfm` 里的子控件顺序；「AI」页加在 `ProblemsWin` **之后**（spec「种子 / 问题 / AI」），图标 Lucide `sparkles`（`assets/lucide/codepoints.json` 有）。frame 运行时建、放进宿主面板，照 1 期预览、2 期种子面板（`tbmain.pas:204-207`）。菜单开侧栏页用 2 期的 `ShowSidePage`。
25. 一步撤销：2 期 `ApplyEdits(AText, AEdits)`（陈旧保护：`Editor.Lines.Text <> AText` 就不改；`BeginUndoBlock` / `EndUndoBlock` 里从后往前 `SetTextBetweenPoints`；之后 `UpdateTitle` + `RefreshNow`），改动类型 `TTbTextEdit` / `TbEdit(起, 止, 文本)`（`tools/themebuilder/tbcssscan.pas:84-87`）。接受 = 一个改动：两份文本去掉共同的首尾**整行**之后的中间那段（Task 8 的 `TbWholeTextEdit`）——仍是「整篇替换」的语义、一步撤销，但编辑器里没变的行（行标记、书签、光标所在）不受打扰；共同尾部总含末尾的换行，所以改动的终点永远在文本之内（`TbOffsetToPoint(文本, 长度+1)` 落在不存在的行上的那种情况不会出现）。
26. 试看：预览的 `LoadDocument`（`tbpreview.pas:834-853`）成功时把文本记成「上一版能用的」（`FGoodText` / `FGoodDir`），文本变了就清 `FModeError`；`RestoreGood`（`:855-862`）。试看要**暂存再还原**这三样，所以在 frame 里加 `BeginTrial` / `EndTrial`，不直接借 `LoadDocument`。试看中主窗体的 `RefreshNow`（`tbmain.pas:510-523`）不能把编辑器文本载回预览——对比窗口是模态的，但 `RefreshTimer` 在模态循环里照样触发。
27. 校验复用：`TbCollectProblems(文本, 目录, 未保存, 底层变量)`（`tbproblems.pas:32`，已过滤底层定义过的「未定义变量」）、`TbHasParseError`、`TbProbeDocument(模型, 文本, 现代密度, out 错误)`（`tbpreview.pas:285`）、`TTbTextThemeSource`（`tbthemesource.pas`）、`TbBaseVarNames`（主窗体已有一份 `FBaseVars`，`tbmain.pas:191-192`）。
28. 编辑器配色：`TbEditorColors` / `TbApplyEditorColors`（`tbeditorlook.pas:26-34`，问题行 `TyMix(底色, 色, 18)`，`:133-135`）——对比窗口的两个 SynEdit 用同一套，另加「增 / 删 / 空位」三种行底色。
29. 1 期测试里要跟着改的：F11（`tests/test.themebuilder.main.pas:314-347`）从磁盘问清单用的是 `FindAllFiles(dir, '*.pas', False)`（`:339`，不递归）、比的是文件名——`ai/` 下的单元要递归找、按相对路径（`ai/tbhttp.pas`）比；I3（`:670-`）找 resourcestring 同样不递归（`:680`），要改成递归；I1 的 `.lfm` 清单 2 期改成了 `FindAllFiles(ToolDir, '*.lfm', False)`——本期的 `.lfm` 都放顶层，不用动。

**8. 对比窗口用什么控件**

30. 库里没有能逐行着色、等宽、上千行还流畅的只读文本控件：`TTyMemo` 没有行底色、没有 `TextHint`（`source/tyControls.Memo.pas` 只有 `Append` `:739`、`ReadOnly` `:888`、`WordWrap` `:884`），按行测宽有缓存但仍是逐字形测量（仓库记忆「Memo text perf」）。对比窗口用**两个只读 `TSynEdit`**（行底色走 `OnSpecialLineMarkup`，和 1 期问题行同一做法；两边滚动互相跟随走 `OnStatusChange` 的 `scTopLine`；CSS 高亮与编辑器同一套颜色）。这把 spec §6「SynEdit 是唯一的非 Ty 控件」的例外从编辑器扩到对比窗口——**需主控确认**（开工前问题一第 9 条）。AI 页的流式输出仍用 `TTyMemo`（纯文字、不需要着色；每 150 ms 合并一次追加，Task 15 量一次 600 行的追加耗时）。
31. 按行对比自己写：先去掉共同的首尾行，中间段做 LCS 动态规划（`light.tycss` 1409 行是仓库里最长的主题，去掉首尾后最坏 1409 × 1409 ≈ 200 万格，`Integer` 表约 8 MB）；格数超过 400 万就不再求 LCS，整段当「删 + 增」（不会错，只是不细）。删除段紧跟增加段时两两配成「改」行，多出来的仍是删 / 增。两边行对齐：一边缺的行用空位补，空位不算行号（SynEdit 的行号栏关掉，左右各在状态行里说「第 N 处改动」）。

**9. 示例硬规则（spec §6）**

32. 新窗体都是 `TTyForm` + `.lfm` + `TitleBar = Bar`，跟着工具的皮肤（`TyDefaultController`）；对比窗口、设置对话框都是模态，按钮 `ModalResult` 在 `.lfm` 里写整数；聚焦用 `CanSetFocus`；颜色全走令牌（`tbeditorlook` 的表）；除 SynEdit 外只用 Ty 控件；非可视的 `TTimer`、`TTyPopupMenu` 照先例可以用。用户可见文字全部 resourcestring 或 `.lfm`，进中英 `.po`；**给模型看的文字**（系统提示、参考、回喂）是英文常量、不翻译、不进 resourcestring。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，Task 15 写回 spec 原处。第一类由主控在 Task 0 决定问不问用户；用户没回复前按建议做（三期一起验收时仍可改，Task 16 把它们写进验收文档的「等你定的决定」）。

> **状态**：未单独询问用户，按建议执行（用户 2026-10-01 以 /goal 指示按计划、开发、验证、修复顺序完成 spec 全部内容），一起验收时可改。主控的决定：第一类十一条全部按建议，另有两处修正——① 第 1 条 Anthropic 预置的模型改用 `claude-sonnet-5`，最大输出要大于 0（主控举例 8192，执行时定为 32000，理由见下面「实现期修正（开工核对）」第 3 条）；② 第二类第 4 条（macOS 也运行时加载 libcurl）的后备方案改为「macOS 若不行，改为调用 `/usr/bin/curl` 进程」（本期不实现）。第 9 条（对比窗口用两个只读 SynEdit）主控同意。

### 实现期修正（开工核对）

Task 0 对照 2 期实际留下的代码（`df1fd13b`，含 2 期期末修复）逐个核对本计划用到的接口，与计划写的不同之处如下，正文已就地改过：

1. `ApplyEdits(const AText: string; const AEdits: TTbTextEdits; const AMergeKey: string = ''): Boolean`——多了合并键（圆角微调框用）。接受 AI 的版本不传合并键：传空串会把「上一步可合并」清掉，正是要的（接受是单独一步）。陈旧保护、`BeginUndoBlock` / `EndUndoBlock`、末尾 `RefreshNow` 与计划写的一样；另外 `PutEdits` 已处理「改动终点在文末换行之后」与「零行编辑器多出一个空行」两种边角，`TbWholeTextEdit` 的终点不会超出文本，碰不到前者。
2. `Ask(AMsg, AButtons, AType = mtConfirmation)` 是三参的；框和对话框问话用的类型 `TTbAskEvent`（`tbseedsframe`）是两参的，主窗体给它们的是 `AskFor`。Task 12 的 `BuildAiSettingsForm` 写成 `Result.OnAsk := @AskFor`（计划原写 `@Ask`，类型不配）。
3. **Anthropic 预置的最大输出**定为 32000（`TbAnthropicDefaultMaxOutput`，请求体里 `MaxOutput <= 0` 时也用它；设置对话框切到 Anthropic 且原值 0 时自动填它）：整份重写一份内置主题要的输出就不少——`themes/auto.tycss` 32 KB，按 4 字节一个 token 约 8 千，而当前模型默认先思考、思考也算在 `max_tokens` 里；8192 会把整份重写截断。32000 在 Sonnet 级模型的上限之内。计划里原写 64000 的地方（Task 4 请求体、Task 6 预置表、Task 11 自动填、G1、G4、A3）都改为这个常量。
4. `TbSeedNames` 是常量数组（`array[0..TbSeedCount - 1] of string`，`tbseeds.pas:38`），不是函数；用法照常量。
5. `ShowSidePage(AWin: TTyToolWindow)` 是主窗体的私有方法，`MnuAiClick` 在窗体里调它，不受影响。侧栏页的建法与 2 期种子页相同（frame 运行时建、放进 `.lfm` 里的宿主面板）。种子页「看得见时才算」的缓存（`SeedsWin.OnShow` → `CatchUp`）与 AI 页无关：AI 页在前台时种子页只收文本、不算。
6. 主窗体测试 F1（`TestTheWindowIsBuilt`）现在断言侧栏 2 页，Task 12 改为 3 页（M1 另断言第三页）。F11（`TestTheProjectListsItsUnits`）与 I3（`TestTheTranslationsCoverTheCode`）现在都 `FindAllFiles(…, False)`，照计划改递归。
7. 验收文档现在最后一项是第 52 项、最后一个决定是 E26：Task 16 的 3 期项编 53–72、决定编 E27–E37。
8. **libcurl 的变参只有一个调用点**（主控决定）：`curl_easy_setopt` 与 `curl_easy_getinfo` 各经一个函数（`CurlSetOpt` / `CurlGetInfo`）调用，所有选项都从这里过；实参一律按指针宽度传（`Pointer(PtrInt(x))`）——C 的 `long` 在 Linux / macOS 上（LP64，以及 32 位的 ILP32）与指针一样宽，比计划原写的 `Int64(x)` 在 32 位系统上也对。注释写明 Apple arm64 变参走栈、靠 FPC 对 cdecl `array of const` 的处理、本机测不到、后备方案是调用 `/usr/bin/curl` 进程（第二类第 4 条，本期不实现）。
9. 基线（`df1fd13b`）的条数与红名单记在签收里。

### 一、产品方向 / 用户可见（问用户）

1. **五种预置填什么。** **建议**：

   | 预置 | 格式 | 地址 | 模型 | 最大输出 | 空闲超时 |
   |---|---|---|---|---|---|
   | OpenAI | OpenAI 兼容 | `https://api.openai.com/v1` | `gpt-5` | 0（不发） | 120 s |
   | DeepSeek | OpenAI 兼容 | `https://api.deepseek.com/v1` | `deepseek-chat` | 8192 | 120 s |
   | Anthropic | Anthropic | `https://api.anthropic.com/v1` | ~~`claude-opus-5`~~ `claude-sonnet-5`（主控） | ~~64000~~ 32000（开工核对第 3 条） | 300 s |
   | 本地（Ollama） | OpenAI 兼容 | `http://localhost:11434/v1` | `qwen2.5-coder:7b` | 0 | 300 s |
   | 自定义 | OpenAI 兼容 | （空） | （空） | 0 | 120 s |

   模型名是写计划时的取值，会过时，用户随时可改（填错了「测试连接」会报「地址或模型不对（404）」）。「最大输出 0 = 不发」：OpenAI 的新模型拒收 `max_tokens`（要 `max_completion_tokens`），不发最稳；DeepSeek 的 `deepseek-chat` 上限 8192，发 64000 会被拒；Anthropic 必填。另一做法：OpenAI 兼容格式也给一个默认值（如 16000）——对 OpenAI 官方的新模型会 400。
2. **「超时」是什么意思。** **建议**：「多久收不到任何数据就算超时」（空闲超时，设置里可改，默认见上表），连接另有固定 15 秒；生成一份主题要一两分钟是正常的，总时长不设上限（随时可点「停止」）。另一做法：总时长上限——思考型模型上很容易误伤。
3. **对比窗口的形态。** **建议**：生成结束（或回喂两次后仍有问题）自动弹出**模态**对比窗口：左边现在的文本、右边模型的版本，改动行着色、两边滚动跟随；底下列剩下的问题；「在预览里试看」是个复选框（勾上预览换成模型的版本，去掉或关窗口就还原）；「接受」「放弃」。关掉后 AI 页留一个「查看对比…」可以再打开。另一做法：非模态、可以边看边改编辑器——那样「接受」时更容易盖掉刚做的改动，也更难保证试看结束能还原。
4. **生成之后编辑器又改过，再接受。** **建议**问一句：「生成之后编辑器里又改过。接受会把这些改动一起替换掉。接受吗？」，是 → 替换当前全文（一步撤销仍能回到替换前），否 → 不动。另一做法：拒绝接受，要求重新生成。
5. **校验多一道「试解析」。** spec §7.3 写的是「解析 + `TyLintCssEx`」。预览载入时还会做试解析（1 期 E9），解析与 lint 都过、但某个模式下画不出来的文档（只在亮色里定义、暗色规则里用到的变量；底层规则接不住的种子值）会被预览拒收。**建议**把「每个模式各试解析一次」也算失败、一起回喂，否则用户接受之后预览保持上一版、还得自己去找原因。另一做法：照 spec 只做解析 + lint。
6. **多轮记到什么时候。** **建议**：同一份文档里记住每次的描述，并标明它的结果有没有被接受（「再暗一点」能接上，模型也知道上一次被放弃了）；新建、打开另一份文档时清空；AI 页有「新对话」按钮手动清。只发最新的文档全文，不发旧的回答（spec §7.2）。另一做法：跨文档也记住。
7. **「附上当前问题」**（spec §7.2 的「可选：当前问题列表」）。**建议** AI 页一个复选框，文档有错误时自动勾上、没错误时自动去掉（用户手动改过之后在这份文档里就不再自动改）。
8. **发给模型的文字用什么语言。** **建议**系统提示、精简参考、回喂都用英文（各家模型对英文的规则遵从最好；参考是从代码拼的，本来就是英文；同样内容中文 token 更多）；用户的描述原样发送，模型的说明文字跟着用户的语言走（系统提示里写一句「用用户的语言写代码块之前那一句话」）。另一做法：全中文。
9. **【需主控确认】SynEdit 例外扩到对比窗口**（核实记录 30）。**建议**同意：对比窗口显示的就是编辑器里的那种代码文本（等宽、CSS 高亮、上千行、逐行着色、两边滚动跟随），库里没有能做这些的 Ty 控件，与编辑器用同一控件、同一套令牌取色。另一做法：用两个 `TTyListBox` 自绘行（要自己画高亮、自己处理横向滚动），或只给统一视图（一列，删 / 增行交替）——与 spec「左右并排」不符。
10. **AI 页放什么。** **建议**（侧栏宽 280）：顶上「服务」下拉 + 齿轮（设置）；描述框（4 行，上面一行说明「描述想要的主题或改动，例如：暖色调，圆角大一点」）；「附上当前问题」；「生成」（主按钮）/「停止」/「新对话」；一行状态（一句话，出错时就是那句原因）；「本次对话：N 条要求」；流式输出占满剩下的高度；底部一行小字「发送到：<主机名>」与「查看对比…」。
11. **找不到 libcurl 时**（Linux / macOS）。**建议** AI 页整页可见、「生成」与「测试连接」灰掉，状态行说「找不到 libcurl（试过 libcurl.so.4、libcurl-gnutls.so.4、…）。装上 libcurl（如 libcurl4 包）就能用 AI」；其余功能照常。环境变量 `THEMEBUILDER_LIBCURL` 可以指定库文件（写进文档）。

### 二、实现层面（主控定）

1. **新单元（`tb` 前缀）与目录**：`ai/` 下 `tbhttp`（接口、地址拆分、工厂）、`tbhttpwin`（WinHTTP，`{$IFDEF MSWINDOWS}`）、`tbhttpcurl`（libcurl，`{$IFDEF UNIX}`）、`tbsse`、`tbaiformat`、`tbaiclient`、`tbaisettings`、`tbreference`、`tbaisession`；顶层 `tbdiff`、`tbcompareform`、`tbaisettingsform`、`tbaiframe`（界面放顶层，`.lfm` 检查脚本与 I1 的 `.lfm` 清单都只看顶层，不用改）。工具工程 `OtherUnitFiles` 加 `ai`；测试工程加 `../tools/themebuilder/ai`。spec §4 的 `ai/uhttp.pas` / `uaiclient.pas` / `uaisettings.pas` / `uaisession.pas` / `ureference.inc` 与 `udiff.pas` 写回为这些名字。
2. **WinHTTP、DPAPI 自己声明，libcurl 自己建运行时函数表**（核实记录 1、6、12）。
3. **线程**：只有 HTTP 在工作线程；字节经 SSE 拆分、格式解读后的「文字片段」在工作线程里攒进带锁的缓冲，`TThread.Queue(nil, @方法)` 交给主线程（FPC 3.2.2 有 `Queue` 与 `RemoveQueuedEvents`，`rtl/objpas/classes/classesh.inc:1801-1805`）；取代码块、解析、lint、试解析、界面全在主线程（样式模型与解析器有进程级状态：`GThemeBaseDir`、全局回退字号、测量缓存）。对象析构前 `Cancel` + `WaitFor` + `RemoveQueuedEvents`。
4. **macOS 也走运行时加载**（spec 原文）。风险：Apple arm64 的 C 变参走栈，`curl_easy_setopt` 能不能对靠 FPC 对 cdecl `array of const` 的处理（核实记录 7）；本机与 WSL 都测不到，验收在真 Mac 上做一次真实生成。不行的退路（不在本期做）：~~Darwin 改用静态 `external 'curl'`（macOS 自带 libcurl，静态链接不会「起不来」）~~ 改为调用 `/usr/bin/curl` 进程（主控决定，开工核对）。
5. **精简参考运行时拼**（核实记录 22），写回 spec §7.2；守卫测试见 Task 7。
6. **测试缝**：AI 配置文件跟着 1 期的 `SettingsFileForTest` 走（同目录下的 `themebuilder-ai.ini` / `themebuilder-ai.keys`，`TbAiFilesFor`）；一次生成的后端可替换（`TTbAiSession.Backend`，测试用按脚本回答的假后端，spec §8「按脚本回答的假模型」）；对比窗口、设置对话框只 `Create` + `Prepare`、从不 `ShowModal`，测试直接调按钮的处理方法；等异步结果用 `CheckSynchronize` 循环（上限 10 秒，超时的失败消息说等的是什么）。
7. **密钥不外露**（spec §7.1）：只在请求头里出现；错误句子与 `Detail` 都过 `TbScrubSecret`（整串、前 6 个字符、后 4 个字符、含 `***` 的词都换成 `***`）；Windows 的配置文件里只有 DPAPI 密文的 base64；Unix 的密钥文件 0600；工具没有日志。测试断言密钥不在任何对外的字符串、不在 ini 字节里。
8. **2 期接口以代码为准**（`ApplyEdits`、`TbEdit`、`TbSeedNames`、`ShowSidePage`），Task 0 核对。

---

## 需要改共享文件的地方

**库：无。** `source/`、`designtime/`、两个 `.lpk`、库的 `languages/`、`themes/` 本期都不碰。

**非库的共用文件：** `tests/tytests.lpi`（搜索路径加 `../tools/themebuilder/ai`，Task 1）、`tests/tytests.lpr`（uses 随各任务加）、`tests/test.themebuilder.main.pas`（F11、I3 改递归，Task 12；新增 M1–M12）、`tools/themebuilder/themebuilder.lpi`（`ai` 路径与 `<Units>`，随各任务）、`tools/themebuilder/tbmain.pas` / `.lfm`（Task 12）、`tools/themebuilder/tbpreview.pas`（试看，Task 10）、`tools/themebuilder/tbeditorlook.pas`（三种对比行底色，Task 10）、`README.md` / `README.en.md`（Task 14）、`.gitignore`（不需要：WSL 工具目录自带 `.gitignore`）。

---

## 接口清单（全计划用这一套名字）

```pascal
{ ai/tbhttp.pas -- no LCL }
type
  TTbHttpErrorKind = (hekNone, hekCancelled, hekNoTransport, hekBadUrl, hekNameNotResolved,
    hekCannotConnect, hekTls, hekTimeout, hekBroken, hekOther);
  TTbHttpRequest = record
    Url: string;
    Headers: TStringArray;        { 'Name: value', one per item }
    Body: RawByteString;          { UTF-8 }
    ConnectTimeoutMs: Integer;    { 0 = TbDefaultConnectTimeoutMs }
    IdleTimeoutMs: Integer;       { no byte for this long = hekTimeout; 0 = 120000 }
  end;
  TTbHttpResult = record
    Status: Integer;              { 0 when no response came }
    Error: TTbHttpErrorKind;      { hekNone also for a 4xx / 5xx: that is Status's business }
    Detail: string;               { the system's words (error code, message); never headers or body }
  end;
  { both on the worker thread, in this order: the status once, after the headers; then the
    body as it comes. Returning False from AOnData stops the transfer (hekCancelled). }
  TTbHttpStatusEvent = procedure(AStatus: Integer) of object;
  TTbHttpDataEvent = function(const AData: RawByteString): Boolean of object;
  TTbHttpTransport = class
  public
    function Execute(const ARequest: TTbHttpRequest; AOnStatus: TTbHttpStatusEvent;
      AOnData: TTbHttpDataEvent): TTbHttpResult; virtual; abstract;   { blocking; once per instance }
    procedure Cancel; virtual; abstract;   { any thread, any time; Execute returns hekCancelled soon }
  end;
  TTbUrlParts = record
    Secure: Boolean;
    Host: string;                 { no brackets for IPv6 }
    Port: Word;
    Path: string;                 { with the query; '/' at least }
  end;
const
  TbDefaultConnectTimeoutMs = 15000;
  TbUserAgent = 'TyControls-ThemeBuilder/3.1';
function TbSplitUrl(const AUrl: string; out AParts: TTbUrlParts): Boolean;
function TbIsLoopbackHost(const AHost: string): Boolean;   { localhost, 127.*, ::1 }
{ nil + AReason when this platform cannot do HTTP (no libcurl) }
function TbCreateTransport(out AReason: string): TTbHttpTransport;
function TbTransportAvailable(out AReason: string): Boolean;

{ ai/tbhttpwin.pas -- Windows only }
type
  TTbWinHttpTransport = class(TTbHttpTransport) ... end;
function TbWinHttpErrorKind(ACode: DWORD): TTbHttpErrorKind;

{ ai/tbhttpcurl.pas -- Unix only }
type
  TTbCurlTransport = class(TTbHttpTransport) ... end;
function TbCurlCandidates: TStringArray;            { $THEMEBUILDER_LIBCURL first }
function TbCurlLoad(out AReason: string): Boolean;  { once; main thread; curl_global_init }
function TbCurlLoadedName: string;
function TbCurlErrorKind(ACode: LongInt): TTbHttpErrorKind;

{ ai/tbsse.pas -- no LCL }
type
  TTbSseEvent = record
    Name: string;                 { 'message' when the event has no event: line }
    Data: string;                 { data: lines joined with #10 }
  end;
  TTbSseEventProc = procedure(const AEvent: TTbSseEvent) of object;
  TTbSseParser = class
  public
    constructor Create(AOnEvent: TTbSseEventProc);
    procedure Feed(const AChunk: RawByteString);
    procedure Finish;             { a last event without its blank line is dropped }
    property EventCount: Integer read FEventCount;
    property DroppedPartial: Boolean read FDroppedPartial;
  end;

{ ai/tbaiformat.pas -- no LCL }
type
  TTbAiFormat = (tafOpenAI, tafAnthropic);
  TTbAiProfile = record
    Id, Name: string;
    Format: TTbAiFormat;
    BaseUrl, Model: string;
    MaxOutput: Integer;           { 0 = not sent (OpenAI-compatible); Anthropic needs > 0 }
    TimeoutSec: Integer;          { idle timeout }
  end;
  TTbChatRole = (tcrUser, tcrAssistant);
  TTbChatMessage = record
    Role: TTbChatRole;
    Text: string;
  end;
  TTbChatMessages = array of TTbChatMessage;
  TTbStreamPiece = (tspNone, tspText, tspThinking, tspDone, tspTruncated, tspRefused, tspError);
  TTbStreamDelta = record
    Kind: TTbStreamPiece;
    Text: string;                 { tspText: the text; tspError: the service's message }
  end;
function TbEndpointUrl(const AProfile: TTbAiProfile): string;
function TbRequestHeaders(const AProfile: TTbAiProfile; const AKey: string): TStringArray;
function TbRequestBody(const AProfile: TTbAiProfile; const ASystem: string;
  const AMessages: TTbChatMessages): RawByteString;
function TbParseStreamEvent(AFormat: TTbAiFormat; const AEvent: TTbSseEvent): TTbStreamDelta;
function TbParseWholeReply(AFormat: TTbAiFormat; const ABody: string; out AText: string): Boolean;
function TbErrorBodyMessage(const ABody: string): string;   { '' when none }

{ ai/tbaiclient.pas -- no LCL }
type
  TTbAiErrorKind = (aekNone, aekCancelled, aekNoTransport, aekBadUrl, aekNameNotResolved,
    aekCannotConnect, aekTls, aekTimeout, aekBroken, aekAuth, aekNotFound, aekRateLimit,
    aekBadRequest, aekServer, aekBadFormat, aekTruncated, aekRefused, aekOther);
  TTbAiResult = record
    Kind: TTbAiErrorKind;
    Status: Integer;
    Text: string;                 { all the answer text that arrived (also when it failed) }
    Detail: string;               { the service's or the system's words, scrubbed }
  end;
  { on the WORKER thread }
  TTbAiDeltaEvent = procedure(Sender: TObject; APiece: TTbStreamPiece; const AText: string) of object;
  TTbAiClient = class
  public
    constructor Create(const AProfile: TTbAiProfile; const AKey: string);
    destructor Destroy; override;
    function Run(const ASystem: string; const AMessages: TTbChatMessages;
      AOnDelta: TTbAiDeltaEvent): TTbAiResult;     { blocking }
    procedure Cancel;                              { any thread }
  end;
function TbAiErrorSentence(const AResult: TTbAiResult; const AProfile: TTbAiProfile): string;
function TbScrubSecret(const AText, AKey: string): string;
function TbHostOf(const AUrl: string): string;    { for the sentences and "Sent to" }

{ ai/tbaisettings.pas -- no LCL }
type
  TTbAiPreset = (tapOpenAI, tapDeepSeek, tapAnthropic, tapOllama, tapCustom);
  TTbAiSettings = class
  public
    constructor Create(const AIniFile, AKeyFile: string);
    destructor Destroy; override;
    procedure Load;                               { a missing file = no profiles }
    function Save: Boolean;                       { best effort; False when it could not write }
    function Count: Integer;
    function Profile(AIndex: Integer): TTbAiProfile;
    function IndexOfId(const AId: string): Integer;
    procedure Put(const AProfile: TTbAiProfile);  { add, or replace the one with that Id }
    procedure Delete(const AId: string);          { and its key }
    function GetKey(const AId: string): string;   { '' when none or unreadable }
    procedure SetKey(const AId, AKey: string);    { '' removes; written by Save }
    function Current(out AProfile: TTbAiProfile): Boolean;
    property CurrentId: string read FCurrentId write FCurrentId;
    property IniFile: string read FIniFile;
    property KeyFile: string read FKeyFile;
  end;
function TbPresetProfile(APreset: TTbAiPreset): TTbAiProfile;   { a fresh Id each call }
function TbPresetCaption(APreset: TTbAiPreset): string;
function TbNewProfileId: string;
procedure TbAiFilesFor(const ASettingsIni: string; out AIniFile, AKeyFile: string);
{$IFDEF MSWINDOWS}
function TbProtectKey(const AKey: string): string;               { DPAPI, base64 }
function TbUnprotectKey(const AStored: string; out AKey: string): Boolean;
{$ENDIF}
function TbWritePrivateFile(const AFileName: string; const AData: RawByteString): Boolean;

{ ai/tbreference.pas }
type
  TTbRefClaim = record
    Claim: string;                { the sentence in the reference }
    Snippet: string;              { tycss that shows it }
    MustParse: Boolean;           { True: parses and lints without errors; False: fails }
  end;
  TTbRefClaims = array of TTbRefClaim;
function TbReferenceText: string;               { built once, then cached }
function TbReferenceApproxTokens: Integer;      { Length(TbReferenceText) div 4 }
function TbReferenceExample: string;            { the complete small theme in it }
function TbPropertyNote(const AProp: string): string;    { '' when none }
function TbColorFnSignature(const AFn: string): string;  { '' when none }
function TbReferenceClaims: TTbRefClaims;       { FOR THE TESTS }
function TbNotedProperties: TStringArray;       { FOR THE TESTS }
function TbSignedColorFns: TStringArray;        { FOR THE TESTS }

{ ai/tbaisession.pas }
type
  TTbAiIssue = record
    Line, Col: Integer;           { in the candidate; 0 = no position }
    IsError: Boolean;
    Text: string;
  end;
  TTbAiIssues = array of TTbAiIssue;
  TTbAiStage = (tasIdle, tasSending, tasThinking, tasReceiving, tasChecking, tasRetrying,
    tasDone, tasFailed, tasStopped);
  TTbAiOutcome = record
    HasCandidate: Boolean;
    BaseText, Candidate, Raw: string;   { Raw: the last answer as it came }
    Issues: TTbAiIssues;          { what is left: errors and hints }
    Requests: Integer;            { 1..1 + TbAiMaxFeedback }
    Sentence: string;             { the one sentence for the status line }
  end;
  TTbAiDoneEvent = procedure(Sender: TObject; const AResult: TTbAiResult) of object;
  { one request at a time; OnDelta / OnDone on the MAIN thread }
  TTbChatBackend = class
  public
    procedure Start(const ASystem: string; const AMessages: TTbChatMessages); virtual; abstract;
    procedure Cancel; virtual; abstract;
    property OnDelta: TTbAiDeltaEvent read FOnDelta write FOnDelta;
    property OnDone: TTbAiDoneEvent read FOnDone write FOnDone;
  end;
  TTbClientBackend = class(TTbChatBackend)      { TTbAiClient on a thread }
  public
    constructor Create(const AProfile: TTbAiProfile; const AKey: string);
    destructor Destroy; override;
  end;
  TTbAiDocument = record
    Text, BaseDir: string;
    Untitled: Boolean;
    Problems: TTbProblems;
  end;
const
  TbAiMaxFeedback = 2;
function TbSystemPrompt: string;                 { the rules + TbReferenceText }
function TbExtractCodeBlock(const AReply: string; out ABlock: string;
  out ATruncated: Boolean): Boolean;
function TbCheckCandidate(const AText, ABaseDir: string; AUntitled: Boolean;
  ABaseVars: TStrings): TTbAiIssues;
function TbIssueErrorCount(const AIssues: TTbAiIssues): Integer;
function TbAiIssueCaption(const AIssue: TTbAiIssue): string;   { '12:5  text' / '—  text' }
function TbFeedbackMessage(const AIssues: TTbAiIssues): string;
type
  TTbAiSession = class
  public
    constructor Create;
    destructor Destroy; override;
    function Generate(const ADescription: string; const ADoc: TTbAiDocument;
      AWithProblems: Boolean): Boolean;           { False: busy, no backend or empty description }
    procedure Stop;
    procedure ResetConversation;
    procedure MarkLast(AAccepted: Boolean);
    function UserMessage(const ADescription: string; const ADoc: TTbAiDocument;
      AWithProblems: Boolean): string;            { FOR THE TESTS too }
    property Backend: TTbChatBackend read FBackend write SetBackend;   { owned }
    property BaseVars: TStrings read FBaseVars write FBaseVars;        { not owned }
    property History: TStrings read FHistory;     { descriptions; Objects: 0 open, 1 accepted, 2 not used }
    property Stage: TTbAiStage read FStage;
    property Outcome: TTbAiOutcome read FOutcome;
    property Streamed: string read FStreamed;     { the current answer so far }
    property LastMessages: TTbChatMessages read FLastMessages;   { FOR THE TESTS }
    property OnStage: TNotifyEvent read FOnStage write FOnStage;
    property OnStreamed: TNotifyEvent read FOnStreamed write FOnStreamed;
    property OnFinished: TNotifyEvent read FOnFinished write FOnFinished;
  end;

{ tbdiff.pas }
type
  TTbDiffKind = (tdkSame, tdkRemoved, tdkAdded, tdkChanged);
  TTbDiffRow = record
    Kind: TTbDiffKind;
    Left, Right: Integer;         { 0-based line index; -1 = a filler on that side }
  end;
  TTbDiffRows = array of TTbDiffRow;
const
  TbDiffMaxCells = 4000000;
procedure TbSplitLines(const AText: string; ALines: TStrings);   { any break; a final break adds no line }
function TbDiffLines(AOld, ANew: TStrings): TTbDiffRows;
function TbDiffChangeCount(const ARows: TTbDiffRows): Integer;    { runs of non-same rows }
function TbNormalizeEol(const AText: string): string;             { every break -> LineEnding, one at the end }
function TbWholeTextEdit(const AOld, ANew: string): TTbTextEdit;  { the differing whole lines in the middle }

{ tbcompareform.pas }
type
  TTbTrialEvent = procedure(Sender: TObject; AOn: Boolean; out AError: string) of object;
  TTbCompareForm = class(TTyForm)
  public
    procedure Prepare(const ABase, ACandidate: string; const AIssues: TTbAiIssues;
      const ALook: TTbEditorColors);
    function RowKindAt(ARight: Boolean; AEditorLine: Integer): TTbDiffKind;   { FOR THE TESTS }
    property Rows: TTbDiffRows read FRows;
    property Accepted: Boolean read FAccepted;
    property OnTrial: TTbTrialEvent read FOnTrial write FOnTrial;
  end;

{ tbaisettingsform.pas }
type
  TTbAiSettingsForm = class(TTyForm)
  public
    procedure Prepare(ASettings: TTbAiSettings);     { works on a copy }
    procedure AddPreset(APreset: TTbAiPreset);
    procedure SelectProfile(AIndex: Integer);
    function StartTest: Boolean;                     { False: nothing to test }
    procedure Commit;                                { the copy back into the settings, and Save }
    property Testing: Boolean read GetTesting;
    property TestText: string read GetTestText;      { FOR THE TESTS }
    property OnAsk: TTbAskEvent read FOnAsk write FOnAsk;   { 2 期 tbseedsframe 的类型 }
  end;

{ tbaiframe.pas }
type
  TTbAiDocEvent = function: TTbAiDocument of object;
  TTbAiFrame = class(TFrame)
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Setup(ASettings: TTbAiSettings; ABaseVars: TStrings);
    procedure RefreshProfiles;
    procedure DocumentChanged(AHasErrors: Boolean);  { new / open: forget; and the problems box }
    procedure ProblemsChanged(AHasErrors: Boolean);  { the problems box, unless the user set it }
    procedure GenerateClick(Sender: TObject);        { published handler; public FOR THE TESTS }
    procedure StopClick(Sender: TObject);
    property Session: TTbAiSession read FSession;
    property Available: Boolean read FAvailable;
    property OnGetDocument: TTbAiDocEvent read FOnGetDocument write FOnGetDocument;
    property OnCandidate: TNotifyEvent read FOnCandidate write FOnCandidate;
    property OnSettings: TNotifyEvent read FOnSettings write FOnSettings;
  end;

{ tbpreview.pas（加） }
    function BeginTrial(const AText, ABaseDir: string; out AError: string): Boolean;
    procedure EndTrial;
    property InTrial: Boolean read FInTrial;

{ tbeditorlook.pas（加字段） }
    AddedLine, RemovedLine, FillerLine: TColor;

{ tbmain.pas（加） }
    function BuildCompareForm: TTbCompareForm;     { from Ai.Session.Outcome; prepared, not shown }
    function AcceptCandidate(const ABase, ACandidate: string): Boolean;
    function BuildAiSettingsForm: TTbAiSettingsForm;
    property Ai: TTbAiFrame read FAi;
    property AiSettings: TTbAiSettings read FAiSettings;
```

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `tools/themebuilder/ai/tbhttp.pas`、`ai/tbhttpwin.pas`、`tests/tbfakehttp.pas`、`tests/test.themebuilder.http.pas`（`TTbHttpTests`） | **新建**（Task 1） |
| `tools/themebuilder/ai/tbhttpcurl.pas`、`tools/themebuilder-curl-wsl/tbcurlwsl.lpr`、`tools/themebuilder-curl-wsl/.gitignore` | **新建**（Task 2；`.lpr` 在 Task 5、6 再加用例） |
| `tools/themebuilder/ai/tbsse.pas`、`tests/test.themebuilder.sse.pas`（`TTbSseTests`，Task 4 再加 `TTbAiFormatTests`） | **新建**（Task 3） |
| `tools/themebuilder/ai/tbaiformat.pas`、`tests/fixtures/themebuilder/ai/*.sse`、`*.json` | **新建**（Task 4） |
| `tools/themebuilder/ai/tbaiclient.pas`、`tests/test.themebuilder.aiclient.pas`（`TTbAiClientTests`，Task 6 再加 `TTbAiSettingsTests`） | **新建**（Task 5） |
| `tools/themebuilder/ai/tbaisettings.pas` | **新建**（Task 6） |
| `tools/themebuilder/ai/tbreference.pas`、`tests/test.themebuilder.reference.pas`（`TTbReferenceTests`） | **新建**（Task 7） |
| `tools/themebuilder/tbdiff.pas`、`tests/test.themebuilder.diff.pas`（`TTbDiffTests`） | **新建**（Task 8） |
| `tools/themebuilder/ai/tbaisession.pas`、`tests/tbaitesthelp.pas`、`tests/test.themebuilder.aisession.pas`（`TTbAiSessionTests`） | **新建**（Task 9） |
| `tools/themebuilder/tbcompareform.pas`、`.lfm`、`tests/test.themebuilder.compare.pas`（`TTbCompareTests`，Task 11 再加 `TTbAiSettingsFormTests`） | **新建**（Task 10） |
| `tools/themebuilder/tbpreview.pas`、`tbeditorlook.pas` | 改（Task 10） |
| `tools/themebuilder/tbaisettingsform.pas`、`.lfm` | **新建**（Task 11） |
| `tools/themebuilder/tbaiframe.pas`、`.lfm` | **新建**（Task 12） |
| `tools/themebuilder/tbmain.pas`、`tbmain.lfm`、`tests/test.themebuilder.main.pas` | 改（Task 12） |
| `tools/themebuilder/themebuilder.lpi` | `ai` 路径（Task 1）；`<Units>` 随 Task 1–12 加 |
| `tests/tytests.lpi` | 搜索路径加 `../tools/themebuilder/ai`（Task 1） |
| `tools/themebuilder/languages/themebuilder.zh_CN.po`、`themebuilder.zh_CN.json` | 改（Task 13；代码条目 Task 15 跑脚本补） |
| `docs/themebuilder.md`、`docs/themebuilder.en.md`、`README.md`、`README.en.md` | **新建** / 改（Task 14） |
| `tests/tytests.lpr` | uses 随各任务加 |
| `docs/superpowers/specs/2026-10-01-theme-builder-design.md` | 只在 Task 15 写回 |
| `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md` | 改（Task 16） |

**不碰**：`source/`、`designtime/`、两个 `.lpk`、库的 `languages/`、`themes/`、`scripts/`、`CHANGELOG*`。

---

## 实现期的地雷（每个任务开工前看一眼）

1 期计划地雷 1–19、2 期计划地雷 20–27 全部照旧（不 amend / rebase / reset / stash；不用 `sed -i`；只按 PID 结束进程；FPC `{ }` 注释会嵌套；`.lfm` 规矩；自绘 UI 里不用裸 LCL 控件；视觉值走主题令牌；`CanSetFocus`；默认控制器的监听要摘；测试不弹任何窗；新单元进清单；用户可见文字全部 resourcestring 或 `.lfm`；SynEdit 的列是字节列；单跑绿全量红先 `lazbuild -B`；手编带 `-FU`；文本改动只替换值 / 整行；偏移是字节；回调挡住；导出不留半个包……）。本期另加：

28. **密钥只进请求头**：任何对外的字符串（错误句子、`Detail`、异常消息、状态行、测试的失败消息）都不含密钥；Windows 的 ini 里只有 DPAPI 密文；断言用「`Pos(密钥, s) = 0`」，别用会把整串打印出来的 `AssertEquals(期望, 含密钥的串)`。
29. **只有 HTTP 在工作线程**：工作线程里不碰 LCL、不碰样式模型、不碰解析器与 lint；界面与校验只在主线程（经 `TThread.Queue`）。工作线程对象 `FreeOnTerminate := False`，析构顺序：`Cancel` → `WaitFor` → `TThread.RemoveQueuedEvents(Self 的方法)` → 释放。漏了的症状是关窗口后晚到的 `Queue` 打到已释放的对象上（随机 AV）。
30. **测试服务只绑 `127.0.0.1`**：绑 `0.0.0.0` 会在用户桌面弹防火墙询问框。
31. **libcurl 的变参**：`long` 实参写 `Int64(x)`、指针写 `Pointer(x)`，**绝不**传 `Integer` / `LongInt` / `Boolean`；字符串选项传 `PChar`，指向的字符串在 `curl_easy_perform` 返回前不能释放（`CURLOPT_POSTFIELDS` 不复制正文）。
32. **取消只关一次句柄**：WinHTTP 的请求句柄由「锁 + 已关标志」保护，`Cancel` 与工作线程的收尾谁先到谁关。
33. **等异步结果的测试**用 `CheckSynchronize(10)` 循环 + 10 秒上限，不用 `Sleep` 干等；超时的失败消息说等的是什么、当时的阶段。所有 HTTP 用例总用时控制在 30 秒内（睡眠都是 100–300 ms 量级，超时用例的空闲超时设 1 秒）。
34. **试看期间不载入编辑器文本**：`RefreshNow` 先看 `FPreview.InTrial`；对比窗口关闭（任何路径：接受、放弃、标题栏关闭、Esc）都 `EndTrial`。
35. **给模型的文字是英文常量**、放 `implementation` 的 `const`，不进 resourcestring（I3 只认 resourcestring 段；`.po` 也不该有它们）；用户看得见的全进 resourcestring。
36. **WSL 里编的单元不许引 LCL**：`tbhttp`、`tbhttpwin`、`tbhttpcurl`、`tbsse`、`tbaiformat`、`tbaiclient`、`tbaisettings`、`tests/tbfakehttp` 的 uses 只能是 RTL / FCL（`Classes`、`SysUtils`、`SyncObjs`、`StrUtils`、`DateUtils`、`IniFiles`、`base64`、`fpjson`、`jsonparser`、`dynlibs`、`sockets`、`ctypes`、`Windows`、`BaseUnix`）。Task 7 的 R9 守着（读源码查 uses）。
37. **请求体与 JSON 一律 UTF-8**：`TJSONStringType` 是 `UTF8String`，工具里的 `string` 已是 UTF-8（LazUTF8），赋值不转码；WinHTTP 的 URL、头用 `UTF8Decode` 转 `UnicodeString` 再取 `PWideChar`，正文按字节原样发。

---

## 跑测试的固定套路（只在 Task 0 与 Task 15 跑）

exe 用唯一名 `tytests-tb3.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/tb3-build.txt 2>&1 || { tail -30 /tmp/tb3-build.txt; false; } && cd tests && cp tytests.exe tytests-tb3.exe && for s in $SUITES; do ./tytests-tb3.exe --suite=$s --format=plain > /tmp/tb3-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/tb3-$s.txt | tr '\n' ' '; echo; done
```

`SUITES` = `TTbHttpTests TTbSseTests TTbAiFormatTests TTbAiClientTests TTbAiSettingsTests TTbReferenceTests TTbDiffTests TTbAiSessionTests TTbCompareTests TTbAiSettingsFormTests TTbMainFormTests TTbPreviewTests TTbProblemsTests TTbCssScanTests TTbSeedEditTests TTbSeedsFrameTests TTbExportTests TTbSnippetsTests TCssCatalogTest TI18NTest TReleaseManifestTest`

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了，重跑。

全量（输出必须重定向到文件）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-tb3.exe --all --format=plain > /tmp/tb3-all.txt 2>&1; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/tb3-all.txt
```

**编工具**（实现 agent 可以做，只在 Task 15）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tools/themebuilder/themebuilder.lpi > /tmp/tb3-tool.txt 2>&1; tail -3 /tmp/tb3-tool.txt; grep -ci "components.synedit.*Compiling\|Compiling.*synedit" /tmp/tb3-tool.txt
```

Expected：0 错；最后一个数是 0（没有去重编 Lazarus 目录里的 SynEdit）。

**WSL 里跑 libcurl 那条路**（实现 agent 可以做，只在 Task 15）：

```bash
wsl.exe -d Ubuntu --cd /mnt/d/Projects/ty-3.1/tools/themebuilder-curl-wsl -- sh -c 'mkdir -p lib && fpc -Mobjfpc -Sh -FUlib -Fu../themebuilder/ai -Fu../../tests tbcurlwsl.lpr > lib/build.txt 2>&1 || { tail -20 lib/build.txt; exit 99; }; ./tbcurlwsl; echo "exit=$?"; THEMEBUILDER_LIBCURL=libcurl-gnutls.so.4 ./tbcurlwsl; echo "exit=$?"; THEMEBUILDER_LIBCURL=/nonexistent/libcurl.so ./tbcurlwsl --expect-missing; echo "exit=$?"'
```

Expected：三次都是 `exit=0`；前两次最后一行 `tbcurlwsl: N passed, 0 failed`（N 见 Task 2 / 5 / 6 的用例数），并各打印一行实际加载的库名（`libcurl.so.4` / `libcurl-gnutls.so.4`）；第三次只跑「找不到」那一条。`git status` 里 `tools/themebuilder-curl-wsl/` 下没有新文件（`.gitignore` 忽略可执行文件与 `lib/`）。

---

## 关于判据和变异

同 1 期计划同名一节：纯函数给**输入 / 期望表**，窗体、frame、线程路径写**判据**；每条写明「**在哪个变异下必须红**」，期末集中做（改一行 → `git diff --stat` 确认改到 → `lazbuild -B` → 跑相关 suite（WSL 那几条在 WSL 里重编重跑）→ 必须红 → 改回 → 重编重跑 → 绿）；接线类变异每类至少一条（事件没挂、`Queue` 没发、试看没还原、撤销块没包、回喂没接）；断言里那个量要真的变过（「流式」之前先证明服务端确实分了几次发、中间睡过；「密钥洗掉了」之前先证明原始消息里确实有密钥片段；「试看还原了」之前先证明试看时预览确实变了）；标「—」的不做变异，理由写在表里。**本计划里的判据编号（H、W、E、A、C、K、R、D、S、V、G、M）只在本计划内有效**，与 1、2 期的同字母编号无关。

---

### Task 0: 起点、基线、核对 2 期接口、开工前问题

**Files:** 无（只读、只跑）；本计划（就地改名，若 2 期接口与本计划不同）

- [ ] **Step 1: 【主控执行】开工前问题一的十一条**：主控决定问不问用户（第 9 条至少主控自己定）；问了就把答复写进「开工前要定的问题」开头的「状态」引用块；没问或没回复就写「按建议执行」。答复与建议不同的：第 1 条改了 → Task 6 的预置表照改；第 2 条选「总时长」→ Task 1 / 2 的超时改为 `WinHttpSetTimeouts` 的接收超时 = 总时长、libcurl 用 `CURLOPT_TIMEOUT`；第 3 条选「非模态」→ Task 10 的对比窗口改为 `Show`、Task 12 的接受走第 4 条的询问；第 4 条选「拒绝」→ Task 12 的 `AcceptCandidate` 直接返回 False 并在状态行说明；第 5 条选「只解析 + lint」→ Task 9 的 `TbCheckCandidate` 去掉试解析那一段；第 6 条选「跨文档」→ Task 12 的 `DocumentChanged` 不清对话；第 8 条选「全中文」→ Task 7 / 9 的英文常量改成中文（token 估算的守卫上限随之放宽，Task 7 R6 里写明）；第 9 条不同意 → 对比窗口改用两个 `TTyListBox` 自绘（Task 10 改写，另加一周工作量的估计交主控）。

- [ ] **Step 2: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1 && git log --oneline feat/theme-builder..main | wc -l && grep -n "^## 签收" -A4 docs/superpowers/plans/2026-10-01-themebuilder-phase-2.md | head -6
```

Expected：工作区干净，分支 `feat/theme-builder`；`main` 没有新提交（有的话停下交主控）；2 期计划末尾的签收已填（还是「（Task 11 填写：…）」= 2 期没收尾，停下交主控）。

- [ ] **Step 3: 核对 2 期留下的接口**

```bash
cd /d/Projects/ty-3.1 && grep -n "function ApplyEdits\|procedure ShowSidePage\|SeedsWin\|ProblemsWin" tools/themebuilder/tbmain.pas tools/themebuilder/tbmain.lfm | head; grep -n "function TbEdit\|TTbTextEdit = \|function TbApplyEdits\|function TbOffsetToPoint" tools/themebuilder/tbcssscan.pas; grep -n "TbSeedNames" tools/themebuilder/tbseeds.pas | head -2; grep -n "FindAllFiles" tests/test.themebuilder.main.pas; grep -nE "^\| [0-9]+ \|" docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md | tail -1; grep -nE "^\| E[0-9]+ \|" docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md | tail -1
```

Expected：`ApplyEdits(const AText: string; const AEdits: TTbTextEdits): Boolean`、`ShowSidePage(AWin: TTyToolWindow)`（或 2 期实际的名字）、`TbEdit(AStart, AStop: Integer; const AText: string): TTbTextEdit`、`TbOffsetToPoint`、`TbSeedNames` 都在。名字或参数不同 → 在本计划里全局改成实际的（用 Edit，`replace_all`），记进草稿，Task 15 签收写一句。记下验收文档**最后一项的编号 N** 与**最后一个决定的编号 Ek**：Task 16 的 3 期项从 N+1 编起、决定从 E(k+1) 编起。

- [ ] **Step 4: 基线编译与全量**（本任务的例外，实现 agent 做）：「跑测试的固定套路」的编译 + 全量。条数与红名单记进草稿，Task 15 签收时写进本计划末尾。**除 1、2 期签收里记的已知项外有别的红就停。**

---

### Task 1: 传输层接口、WinHTTP、本机测试服务

**Files:**
- Create: `tools/themebuilder/ai/tbhttp.pas`、`tools/themebuilder/ai/tbhttpwin.pas`
- Create: `tests/tbfakehttp.pas`、`tests/test.themebuilder.http.pas`（suite `TTbHttpTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`（`OtherUnitFiles` 改为 `.;ai;../../source;../../designtime`；`<Units>` 加 `ai/tbhttp.pas`、`ai/tbhttpwin.pas`，`<Filename Value="ai/tbhttp.pas"/>` + `<UnitName Value="tbhttp"/>`）、`tests/tytests.lpi`（`OtherUnitFiles` 末尾加 `;../tools/themebuilder/ai`）、`tests/tytests.lpr`

- [ ] **Step 1: `tbhttp.pas`**（接口清单那一段；单元头注释写：为什么自己做传输（spec §2 第 8 条）、阻塞 + 工作线程、两种实现在哪、这个单元与 LCL 无关（WSL 里也编）。uses：`Classes, SysUtils, StrUtils`，implementation 里 `{$IFDEF MSWINDOWS} tbhttpwin {$ELSE} tbhttpcurl {$ENDIF}`）：
  - `TbSplitUrl`：只认 `http://` 与 `https://`（不分大小写）；`[v6]:port` 形式去掉方括号；没有端口时 80 / 443；端口不是 1..65535 的数字 → False；路径为空给 `'/'`；`#` 之后丢掉；主机为空 → False。
  - `TbIsLoopbackHost`：`SameText(h, 'localhost')`、`h = '::1'`、或以 `127.` 开头且其余是数字与点。
  - `TbCreateTransport`：Windows → `TTbWinHttpTransport.Create`，`AReason := ''`；Unix → `TbCurlLoad(AReason)` 成功则 `TTbCurlTransport.Create`，否则 nil。`TbTransportAvailable` 同理不建对象。
- [ ] **Step 2: `tbhttpwin.pas`**（`{$IFDEF MSWINDOWS}` 包住整个 interface 与 implementation 的内容，Unix 上是空单元）。自己声明（核实记录 1）：

```pascal
type
  HINTERNET = Pointer;
const
  cWinHttp = 'winhttp.dll';
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
  WINHTTP_ACCESS_TYPE_NO_PROXY = 1;
  WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY = 4;   { Windows 8.1 and later }
  WINHTTP_FLAG_SECURE = $00800000;
  WINHTTP_QUERY_STATUS_CODE = 19;
  WINHTTP_QUERY_FLAG_NUMBER = $20000000;
  WINHTTP_ADDREQ_FLAG_ADD = $20000000;
  WINHTTP_ADDREQ_FLAG_REPLACE = $80000000;
  ERROR_WINHTTP_TIMEOUT = 12002;
  ERROR_WINHTTP_INVALID_URL = 12005;
  ERROR_WINHTTP_UNRECOGNIZED_SCHEME = 12006;
  ERROR_WINHTTP_NAME_NOT_RESOLVED = 12007;
  ERROR_WINHTTP_OPERATION_CANCELLED = 12017;
  ERROR_WINHTTP_CANNOT_CONNECT = 12029;
  ERROR_WINHTTP_CONNECTION_ERROR = 12030;
  ERROR_WINHTTP_INVALID_SERVER_RESPONSE = 12152;
  ERROR_WINHTTP_SECURE_FAILURE = 12175;

function WinHttpOpen(pszAgent: PWideChar; dwAccessType: DWORD; pszProxy, pszProxyBypass: PWideChar;
  dwFlags: DWORD): HINTERNET; stdcall; external cWinHttp;
function WinHttpSetTimeouts(h: HINTERNET; nResolve, nConnect, nSend, nReceive: Integer): BOOL;
  stdcall; external cWinHttp;
function WinHttpConnect(h: HINTERNET; pswzServerName: PWideChar; nServerPort: Word;
  dwReserved: DWORD): HINTERNET; stdcall; external cWinHttp;
function WinHttpOpenRequest(h: HINTERNET; pwszVerb, pwszObjectName, pwszVersion,
  pwszReferrer: PWideChar; ppwszAcceptTypes: Pointer; dwFlags: DWORD): HINTERNET;
  stdcall; external cWinHttp;
function WinHttpAddRequestHeaders(h: HINTERNET; lpszHeaders: PWideChar; dwHeadersLength,
  dwModifiers: DWORD): BOOL; stdcall; external cWinHttp;
function WinHttpSendRequest(h: HINTERNET; lpszHeaders: PWideChar; dwHeadersLength: DWORD;
  lpOptional: Pointer; dwOptionalLength, dwTotalLength: DWORD; dwContext: PtrUInt): BOOL;
  stdcall; external cWinHttp;
function WinHttpReceiveResponse(h: HINTERNET; lpReserved: Pointer): BOOL; stdcall; external cWinHttp;
function WinHttpQueryHeaders(h: HINTERNET; dwInfoLevel: DWORD; pwszName: PWideChar;
  lpBuffer: Pointer; lpdwBufferLength, lpdwIndex: PDWORD): BOOL; stdcall; external cWinHttp;
function WinHttpQueryDataAvailable(h: HINTERNET; lpdwNumberOfBytesAvailable: PDWORD): BOOL;
  stdcall; external cWinHttp;
function WinHttpReadData(h: HINTERNET; lpBuffer: Pointer; dwNumberOfBytesToRead: DWORD;
  lpdwNumberOfBytesRead: PDWORD): BOOL; stdcall; external cWinHttp;
function WinHttpCloseHandle(h: HINTERNET): BOOL; stdcall; external cWinHttp;
```

  `Execute` 的骨架（字段 `FLock: TCriticalSection`、`FRequest: HINTERNET`、`FCancelled`、`FRequestClosed: Boolean`、`FStatus: DWORD`）：

```pascal
function TTbWinHttpTransport.Execute(const ARequest: TTbHttpRequest;
  AOnStatus: TTbHttpStatusEvent; AOnData: TTbHttpDataEvent): TTbHttpResult;
var
  url: TTbUrlParts;
  session, conn: HINTERNET;
  access, flags, status, size, avail, got: DWORD;
  buf: RawByteString;
  headers: UnicodeString;

  function Fail(AKind: TTbHttpErrorKind): TTbHttpResult;
  var
    code: DWORD;
  begin
    code := GetLastError;
    Result.Status := FStatus;        { 0 until the headers came; kept after (a broken stream) }
    if IsCancelled then
      Result.Error := hekCancelled
    else if AKind <> hekOther then
      Result.Error := AKind
    else
      Result.Error := TbWinHttpErrorKind(code);
    Result.Detail := Format('WinHTTP %d', [code]);
  end;

begin
  Result := Default(TTbHttpResult);
  FStatus := 0;
  if not TbSplitUrl(ARequest.Url, url) then
    Exit(Fail(hekBadUrl));
  if TbIsLoopbackHost(url.Host) then
    access := WINHTTP_ACCESS_TYPE_NO_PROXY
  else
    access := WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY;
  session := WinHttpOpen(PWideChar(UnicodeString(TbUserAgent)), access, nil, nil, 0);
  if (session = nil) and (access = WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY) then
    { before Windows 8.1: the proxy netsh winhttp configured }
    session := WinHttpOpen(PWideChar(UnicodeString(TbUserAgent)),
      WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
  if session = nil then
    Exit(Fail(hekOther));
  conn := nil;
  try
    WinHttpSetTimeouts(session, ConnectMs(ARequest), ConnectMs(ARequest),
      IdleMs(ARequest), IdleMs(ARequest));
    conn := WinHttpConnect(session, PWideChar(UTF8Decode(url.Host)), url.Port, 0);
    if conn = nil then
      Exit(Fail(hekOther));
    if url.Secure then flags := WINHTTP_FLAG_SECURE else flags := 0;
    if not OpenRequest(conn, UTF8Decode(url.Path), flags) then   { sets FRequest under FLock }
      Exit(Fail(hekOther));
    headers := UTF8Decode(JoinHeaders(ARequest.Headers));        { 'A: b'#13#10'C: d' }
    if (headers <> '') and not WinHttpAddRequestHeaders(FRequest, PWideChar(headers),
       DWORD(-1), WINHTTP_ADDREQ_FLAG_ADD or WINHTTP_ADDREQ_FLAG_REPLACE) then
      Exit(Fail(hekOther));
    if not WinHttpSendRequest(FRequest, nil, 0, PAnsiChar(ARequest.Body),
       Length(ARequest.Body), Length(ARequest.Body), 0) then
      Exit(Fail(hekOther));
    if not WinHttpReceiveResponse(FRequest, nil) then
      Exit(Fail(hekOther));
    size := SizeOf(status);
    if not WinHttpQueryHeaders(FRequest, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER,
       nil, @status, @size, nil) then
      Exit(Fail(hekOther));
    FStatus := status;
    if Assigned(AOnStatus) then AOnStatus(status);
    repeat
      if IsCancelled then Exit(Fail(hekCancelled));
      if not WinHttpQueryDataAvailable(FRequest, @avail) then
        Exit(Fail(hekOther));
      if avail = 0 then Break;                        { the whole body has come }
      SetLength(buf, avail);
      if not WinHttpReadData(FRequest, PAnsiChar(buf), avail, @got) then
        Exit(Fail(hekOther));
      SetLength(buf, got);
      if (got > 0) and Assigned(AOnData) and not AOnData(buf) then
      begin
        Cancel;
        Exit(Fail(hekCancelled));
      end;
    until False;
  finally
    CloseRequest;                                     { once, under FLock }
    if conn <> nil then WinHttpCloseHandle(conn);
    WinHttpCloseHandle(session);
  end;
  Result.Status := FStatus;
  Result.Error := hekNone;
end;
```

  （`FStatus: DWORD` 是字段：`Fail` 是嵌套函数，读不到外层的局部 `Result`。）`Cancel`：`FLock.Enter; FCancelled := True; if (FRequest <> nil) and not FRequestClosed then begin WinHttpCloseHandle(FRequest); FRequestClosed := True; end; FLock.Leave;`。`CloseRequest` 同样在锁里、只关一次。`TbWinHttpErrorKind`：12002 → `hekTimeout`；12005、12006 → `hekBadUrl`；12007 → `hekNameNotResolved`；12017 → `hekCancelled`；12029 → `hekCannotConnect`；12030、12152 → `hekBroken`；12157、12169、12175、12037–12045 → `hekTls`；其余 `hekOther`。**读到 `avail = 0` 之前连接断了**（分块编码没有收尾的 0 块）：WinHTTP 报 12030 → `hekBroken`（H5 验证）。

- [ ] **Step 3: `tests/tbfakehttp.pas`**（单元头注释：为什么不用 `fphttpserver`（核实记录 19）；只绑 127.0.0.1（地雷 30）；不依赖 LCL，WSL 里同样用）：

```pascal
type
  TTbFakeStepKind = (fskSend, fskSleep, fskClose, fskHold);
  TTbFakeStep = record
    Kind: TTbFakeStepKind;
    Data: RawByteString;
    Ms: Integer;
  end;
  TTbFakeRequest = record
    Method, Path: string;
    Headers: TStringArray;        { 'name: value' as received; name lower case }
    Body: RawByteString;
  end;
  TTbFakeHttpServer = class
  public
    constructor Create;                       { binds 127.0.0.1:0, starts listening }
    destructor Destroy; override;             { stops: wakes a Hold, wakes accept, joins }
    { the steps for the next connections, in order; the last script repeats }
    procedure Script(const ASteps: array of TTbFakeStep);
    procedure Queue(const ASteps: array of TTbFakeStep);   { one more connection's script }
    function Url(const APath: string): string;             { 'http://127.0.0.1:<port>' + APath }
    function RequestCount: Integer;
    function LastRequest: TTbFakeRequest;
    function HeaderValue(const AName: string): string;     { of the last request; '' none }
    property Port: Word read FPort;
  end;
function FakeSend(const AData: RawByteString): TTbFakeStep;
function FakeSleep(AMs: Integer): TTbFakeStep;
function FakeClose: TTbFakeStep;
function FakeHold: TTbFakeStep;
{ 'HTTP/1.1 <code> <reason>'#13#10 + headers + blank line; AChunked adds Transfer-Encoding,
  otherwise Content-Length of ABody (and ABody is appended) }
function FakeHead(ACode: Integer; const AContentType: string; AChunked: Boolean;
  const ABody: RawByteString = ''): RawByteString;
function FakeChunk(const AData: RawByteString): RawByteString;   { hex length CRLF data CRLF }
function FakeLastChunk: RawByteString;                            { '0'#13#10#13#10 }
{ a port nothing listens on: bound, read, closed }
function FakeDeadPort: Word;
```

  服务线程：`fpAccept` → 读到 `#13#10#13#10` 为止（上限 64 KB）→ 头里有 `expect: 100-continue` 先回 `'HTTP/1.1 100 Continue'#13#10#13#10` → 按 `content-length` 读正文 → 记下请求（锁里）→ 依次执行这次连接的步骤（`fskSleep` 与 `fskHold` 用一个 `TEvent.WaitFor`，停服时 `SetEvent` 放开；`fskClose` 立刻关）→ 步骤走完关连接 → 回到 accept。停服：`FStopping := True; FWake.SetEvent;` 然后连一次自己的端口叫醒 `accept`，`WaitFor` 线程，`CloseSocket` 监听口。

- [ ] **Step 4: 判据测试**（`TTbHttpTests`；每条用 `TbCreateTransport` 建真传输、打到 `TTbFakeHttpServer`；工作线程跑 `Execute` 的用例用一个测试内的小 `TThread` 子类，主线程等它，地雷 33）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| H1 | 普通应答：脚本 `FakeHead(200, 'application/json', False, '{"ok":1}')`；请求 `POST`、头 `Content-Type: application/json`、`Authorization: Bearer t-123`、正文 `'{"q":"中文"}'`（UTF-8）→ `Status = 200`、`Error = hekNone`、收到的字节 = `'{"ok":1}'`；服务端看到的方法 `POST`、路径 = 请求的路径、两个头都在、正文字节逐字相等；`OnStatus` 恰好调了一次、在第一次 `OnData` 之前 | 头不发（`WinHttpAddRequestHeaders` 那行删掉） |
| H2 | 真的是流式：脚本 `FakeHead(200,'text/event-stream',True)`、`FakeChunk('a')`、`FakeSleep(300)`、`FakeChunk('b')`、`FakeSleep(300)`、`FakeChunk('c')`、`FakeLastChunk`→ `OnData` 至少 3 次、拼起来 `'abc'`；**第一次 `OnData` 的时刻比 `Execute` 返回早 ≥ 450 ms**（先证明脚本里确实睡了 600 ms：`Execute` 总用时 ≥ 550 ms） | 读满整个应答再一次交出（循环里把数据攒起来、最后才调 `OnData`） |
| H3 | 401：`FakeHead(401,'application/json',False,'{"error":{"message":"bad key"}}')` → `Status = 401`、`Error = hekNone`、正文完整交出 | 4xx 当成 `hekOther` |
| H4 | 429 同上 → `Status = 429` | — |
| H5 | 中途断开：分块头 + `FakeChunk('a')` + `FakeClose`（没有收尾 0 块）→ `Error = hekBroken`，已收到 `'a'`，`Status = 200` | `Fail` 把状态清成 0（`Status = 0`） |
| H6 | 空闲超时：头 + 一块 + `FakeHold`，`IdleTimeoutMs = 1000` → `Error = hekTimeout`，`Execute` 用时 0.9–4 秒 | `WinHttpSetTimeouts` 的接收超时传连接超时（15 s：用例超时失败） |
| H7 | 连不上：`'http://127.0.0.1:' + FakeDeadPort` → `hekCannotConnect`，用时 < 3 秒 | `TbWinHttpErrorKind` 12029 映射成 `hekOther` |
| H8 | 取消：头 + 一块 + `FakeHold`、空闲超时 30 s；另一线程 300 ms 后 `Cancel` → `Error = hekCancelled`，`Cancel` 之后 1 秒内返回；之后服务端停得下来（析构不挂） | `Cancel` 只置标志不关句柄（要等到空闲超时，用例超时失败） |
| H9 | `OnData` 返回 False → `hekCancelled`，之后不再有 `OnData` | 忽略返回值 |
| H10 | `localhost`：同 H1 但地址写 `http://localhost:<port>/x`（服务只听 IPv4）→ 成功；用时 < 3 秒 | —（守「Ollama 只听 127.0.0.1 时 `localhost` 也能连」，不是变异目标） |
| H11 | `TbSplitUrl` 表：`https://api.openai.com/v1` → (True, `api.openai.com`, 443, `/v1`)；`http://localhost:11434/v1/chat/completions?x=1#f` → (False, `localhost`, 11434, `/v1/chat/completions?x=1`)；`http://[::1]:8080` → (`::1`, 8080, `/`)；`HTTP://A` → (False, `A`, 80, `/`)；`ftp://x`、`http://`、`http://h:0`、`http://h:70000`、`http://h:12a` → False | 默认端口写反（443 / 80） |
| H12 | `TbIsLoopbackHost`：`localhost`、`LOCALHOST`、`127.0.0.1`、`127.1.2.3`、`::1` → True；`localhost.example.com`、`127.0.0.1.nip.io`、`10.0.0.1`、`` → False | 只看 `127` 前缀不看其余 |
| H13 | 正文较大（200 KB 的 `x`）完整到达服务端 | — |

- [ ] **Step 5: 注册与提交**：`tests/tytests.lpr` 的 uses 加 `test.themebuilder.http`。

```bash
cd /d/Projects/ty-3.1 && git add tools/themebuilder/ai/tbhttp.pas tools/themebuilder/ai/tbhttpwin.pas tools/themebuilder/themebuilder.lpi tests/tbfakehttp.pas tests/test.themebuilder.http.pas tests/tytests.lpi tests/tytests.lpr && git commit -m "feat(themebuilder): an HTTP transport over WinHTTP, and a local server for the tests

The AI client needs streaming HTTPS with the system proxy and a way
to stop. WinHTTP is declared here: FPC's binding names
WinHttpSetTimeouts WinHttpSetTimes, which winhttp.dll does not export.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: libcurl 函数表与 WSL 控制台程序

**Files:**
- Create: `tools/themebuilder/ai/tbhttpcurl.pas`
- Create: `tools/themebuilder-curl-wsl/tbcurlwsl.lpr`、`tools/themebuilder-curl-wsl/.gitignore`
- Modify: `tools/themebuilder/themebuilder.lpi`（`<Units>` 加 `ai/tbhttpcurl.pas`）

- [ ] **Step 1: `tbhttpcurl.pas`**（`{$IFDEF UNIX}` 包住内容；uses `Classes, SysUtils, SyncObjs, dynlibs, ctypes, tbhttp`；**不** `uses libcurl`，核实记录 6）：

```pascal
type
  TCurlGlobalInit = function(flags: LongInt): LongInt; cdecl;
  TCurlEasyInit = function: Pointer; cdecl;
  TCurlEasySetopt = function(h: Pointer; opt: LongInt; args: array of const): LongInt; cdecl;
  TCurlEasyGetinfo = function(h: Pointer; info: LongInt; args: array of const): LongInt; cdecl;
  TCurlEasyPerform = function(h: Pointer): LongInt; cdecl;
  TCurlEasyCleanup = procedure(h: Pointer); cdecl;
  TCurlEasyStrerror = function(code: LongInt): PChar; cdecl;
  TCurlSlistAppend = function(list: Pointer; s: PChar): Pointer; cdecl;
  TCurlSlistFreeAll = procedure(list: Pointer); cdecl;
const
  CURLOPT_WRITEDATA = 10001;  CURLOPT_URL = 10002;  CURLOPT_PROXY = 10004;
  CURLOPT_ERRORBUFFER = 10010;  CURLOPT_WRITEFUNCTION = 20011;  CURLOPT_POSTFIELDS = 10015;
  CURLOPT_USERAGENT = 10018;  CURLOPT_LOW_SPEED_LIMIT = 19;  CURLOPT_LOW_SPEED_TIME = 20;
  CURLOPT_HTTPHEADER = 10023;  CURLOPT_NOPROGRESS = 43;  CURLOPT_POST = 47;
  CURLOPT_XFERINFODATA = 10057;  CURLOPT_POSTFIELDSIZE = 60;  CURLOPT_CONNECTTIMEOUT = 78;
  CURLOPT_NOSIGNAL = 99;  CURLOPT_XFERINFOFUNCTION = 20219;
  CURLINFO_RESPONSE_CODE = $200002;
  CURL_GLOBAL_DEFAULT = 3;
```

  - `TbCurlCandidates`：`GetEnvironmentVariable('THEMEBUILDER_LIBCURL')` 非空就放第一个；然后 `{$IFDEF DARWIN}` `/usr/lib/libcurl.4.dylib`、`libcurl.4.dylib`、`libcurl.dylib` `{$ELSE}` `libcurl.so.4`、`libcurl-gnutls.so.4`、`libcurl-nss.so.4`、`libcurl.so` `{$ENDIF}`。
  - `TbCurlLoad`：已试过就返回上次的结论（成功 / 失败与原因都缓存）；按候选 `LoadLibrary`，拿到句柄后 `GetProcedureAddress` 九个函数，缺一个就 `UnloadLibrary`、记「`<库>` 里没有 `<函数>`」、试下一个；全部失败 → `AReason := Format(rsTbAiNoCurl, [逗号连起来的候选])`（`rsTbAiNoCurl` 放在 `tbhttp` 的 resourcestring 里：`'libcurl was not found (tried %s). Install libcurl (for example the libcurl4 package) to use AI.'`）；成功 → `curl_global_init(CURL_GLOBAL_DEFAULT)`，`TbCurlLoadedName` 记库名。
  - `Execute`：`h := curl_easy_init`；`slist` 依次 `curl_slist_append` 每个请求头，再加 `'Expect:'`；`setopt` 全部用 `[Pointer(...)]` 或 `[Int64(...)]`（地雷 31）：URL、`POST = 1`、`POSTFIELDS = PChar(正文)`、`POSTFIELDSIZE = Length(正文)`、`HTTPHEADER = slist`、`USERAGENT`、`WRITEFUNCTION = @CurlWrite`、`WRITEDATA = Self`、`NOPROGRESS = 0`、`XFERINFOFUNCTION = @CurlProgress`、`XFERINFODATA = Self`、`CONNECTTIMEOUT = 连接秒数`、`LOW_SPEED_LIMIT = 1`、`LOW_SPEED_TIME = 空闲秒数`（向上取整，至少 1）、`NOSIGNAL = 1`、`ERRORBUFFER = @FErrBuf[0]`（`array[0..255] of Char`）；本机地址再加 `PROXY = PChar('')`；`code := curl_easy_perform(h)`；`Result.Status` 取第一次写回调里记下的状态（一个字节都没收到时 perform 之后再 `getinfo` 一次）；`code <> 0` → `Error := TbCurlErrorKind(code)`（取消标志置位时一律 `hekCancelled`），`Detail := Format('libcurl %d: %s', [code, 错误缓冲或 curl_easy_strerror])`；`finally` 里 `curl_slist_free_all`、`curl_easy_cleanup`。
  - `CurlWrite(p, size, nmemb, ud)`：`self := TTbCurlTransport(ud)`；第一次调用时取状态码、调 `OnStatus`；`SetString(s, p, size*nmemb)`；`OnData(s)` 返回 False 或已取消 → 置取消标志、返回 0（libcurl 报 23，归 `hekCancelled`）；否则返回 `size*nmemb`。
  - `CurlProgress(ud, …)`：已取消返回 1，否则 0。
  - `Cancel`：只置标志（线程安全的 `Boolean`，读写都在锁里或用 `InterLockedExchange`）。
  - `TbCurlErrorKind`：1、3 → `hekBadUrl`；5、6 → `hekNameNotResolved`；7 → `hekCannotConnect`；28 → `hekTimeout`；35、51、53、54、58、59、60、64、66、77、80、82、83、90、91 → `hekTls`；18、52、55、56 → `hekBroken`；23、42 → `hekCancelled`；其余 `hekOther`。
- [ ] **Step 2: `tools/themebuilder-curl-wsl/tbcurlwsl.lpr`**（照 `tools/terminal-zmodem-wsl/zmwsl.lpr` 的写法；程序头注释写：它是什么（Linux 上 libcurl 那条路的测试，tytests 在 Windows 上只走 WinHTTP）、怎么编怎么跑（「跑测试的固定套路」里那一行）、`--expect-missing` 的意思；uses `cthreads, Classes, SysUtils, tbhttp, tbhttpcurl, tbfakehttp`）：
  - 一个 `Check(AName: string; AOk: Boolean; const AWhy: string)`，打印 `PASS <名字>` / `FAIL <名字>: <原因>`；最后 `tbcurlwsl: N passed, M failed`，`Halt(M)`。
  - 开头打印 `library: ` + `TbCurlLoadedName`（加载失败打印原因）。
  - `--expect-missing`：只做一件事——`TbTransportAvailable(reason)` 必须为 False、`reason` 里含 `/nonexistent/libcurl.so`；打印一条结果后退出。
  - 本任务写进去的用例：W1–W9 = Task 1 的 H1、H2、H3、H5、H6、H7、H8、H9、H10 在 libcurl 上的同一判据（用时上限同 H 表；H8 的「`Cancel` 之后 1 秒内返回」在这里放宽到 2.5 秒，因为进度回调约每秒一次，核实记录 8）；W10 = 本机地址绕过代理：代理环境变量会影响同一进程里的全部用例，所以单开一个子进程——程序带 `--proxy-check` 参数时只跑 H1 那一条（打到本机测试服务）；父进程用 `fpSystem('http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 ./tbcurlwsl --proxy-check')`（`Unix` 单元）调它，退出码 0 = 绕过了代理（端口 9 上没有代理，走了代理必然连不上）；变异「本机地址不设 `CURLOPT_PROXY = ''`」若仍绿（libcurl 自己对本机地址不用代理），签收记「等价」；W11 = 加载名打印出来、且是候选之一。Task 5、6 往里再加 C、K 两组。
- [ ] **Step 3: `.gitignore`**（两行：`tbcurlwsl`、`lib/`）。
- [ ] **Step 4: 提交**：

```bash
cd /d/Projects/ty-3.1 && git add tools/themebuilder/ai/tbhttpcurl.pas tools/themebuilder/themebuilder.lpi tools/themebuilder-curl-wsl && git commit -m "feat(themebuilder): the HTTP transport over libcurl, loaded at run time

FPC's libcurl unit links the library at build time, so a Linux
without libcurl would not start the tool at all. A small function
table loaded with dynlibs keeps the editor working and only turns AI
off. A console program runs the transport's checks in WSL.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: SSE 拆分

**Files:**
- Create: `tools/themebuilder/ai/tbsse.pas`、`tests/test.themebuilder.sse.pas`（suite `TTbSseTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 单元**（接口清单那一段；单元头注释列核实记录 16 的规则）。状态：`FLine: RawByteString`（当前未完的行）、`FPendingCR: Boolean`（上一块以 CR 结尾）、`FData: RawByteString`、`FHasData: Boolean`、`FName: string`、`FStarted: Boolean`（BOM 只在最开头去）。核心：

```pascal
procedure TTbSseParser.Feed(const AChunk: RawByteString);
var
  i, start: Integer;
  c: Char;
  s: RawByteString;
begin
  s := AChunk;
  if not FStarted and (s <> '') then
  begin
    FStarted := True;
    if Copy(s, 1, 3) = #$EF#$BB#$BF then Delete(s, 1, 3);
  end;
  i := 1;
  if FPendingCR and (s <> '') then
  begin
    FPendingCR := False;
    if s[1] = #10 then i := 2;         { the LF of a CRLF split across chunks }
  end;
  start := i;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c = #13) or (c = #10) then
    begin
      FLine := FLine + Copy(s, start, i - start);
      HandleLine(FLine);
      FLine := '';
      if c = #13 then
      begin
        if i = Length(s) then
          FPendingCR := True
        else if s[i + 1] = #10 then
          Inc(i);
      end;
      start := i + 1;
    end;
    Inc(i);
  end;
  FLine := FLine + Copy(s, start, MaxInt);
end;
```

  `HandleLine(L)`：`L = ''` → 派发（`FHasData` 时：去掉数据末尾一个 #10，名字空给 `'message'`，调回调，`Inc(FEventCount)`；然后清数据与名字）；`L[1] = ':'` → 注释，忽略；否则按第一个 `:` 拆字段与值（没有冒号 → 整行是字段、值为空），值开头一个空格去掉；`data` → `FData := FData + 值 + #10; FHasData := True`；`event` → `FName := 值`；其余忽略。`Finish`：`FLine <> ''` 先当一行处理（最后一行没有换行）；然后若 `FHasData` → `FDroppedPartial := True`，丢弃。
- [ ] **Step 2: 判据测试**（`TTbSseTests`）。每个输入**用三种喂法**：整段一次；逐字节；按每个可能的两段切点切成两块（所有切点都试）——三种的事件序列必须完全相同（名字、数据逐字节相等），这一条对表里每一行都断言：

| # | 输入（`\n` = #10，`\r` = #13） | 期望事件（名字 / 数据） | 在哪个变异下必须红 |
|---|---|---|---|
| E1 | `data: a\n\ndata: b\n\n` | (message, `a`)、(message, `b`) | — |
| E2 | `event: x\ndata: 1\ndata: 2\n\n` | (x, `1\n2`) | 多行数据不加 #10 |
| E3 | 同 E2 全用 `\r\n` | 同 E2 | 跨块的 CRLF（CR 在块末）被算成两个行尾（逐字节喂法下多出一个空行 → 多派发 / 少数据） |
| E4 | 同 E2 全用 `\r` | 同 E2 | 只认 LF |
| E5 | `: keep-alive\n\ndata: x\n\n` | (message, `x`) | 注释当数据 |
| E6 | `data:x\ndata:  y\n\n` | (message, `x\n y`)（只去一个空格） | 去掉全部前导空格 |
| E7 | `data\n\n` | (message, ``)——有 `data` 字段就派发，哪怕值为空 | —（WHATWG 行为） |
| E8 | `event: e\n\n` | 无（没有数据不派发）；下一个事件名字回到 `message` | 事件名不清 |
| E9 | BOM + `data: a\n\n` | (message, `a`)；而 `data: a\n\n` + BOM + `data: b\n\n` 里第二个 BOM 不去（字段名变成 BOM+`data`，忽略）→ 只有一个事件 | 每块都去 BOM |
| E10 | `id: 7\nretry: 10\ndata: z\n\n` | (message, `z`) | — |
| E11 | `data: half`（没有空行）然后 `Finish` | 无事件、`DroppedPartial = True` | `Finish` 派发半个事件 |
| E12 | `data: 中文\n\n`（UTF-8），逐字节喂 | (message, `中文`) 字节相同 | — |
| E13 | 真实样本：`tests/fixtures/themebuilder/ai/openai-ok.sse` 与 `anthropic-ok.sse`（Task 4 建）各三种喂法 | 事件数与 Task 4 表里写的相同 | — |

- [ ] **Step 3: 注册与提交**：uses 加 `test.themebuilder.sse`。`feat(themebuilder): a server-sent events reader that does not care where the chunks split` + Co-Authored-By。

---

### Task 4: 两种接口格式

**Files:**
- Create: `tools/themebuilder/ai/tbaiformat.pas`
- Create: `tests/fixtures/themebuilder/ai/openai-ok.sse`、`openai-length.sse`、`openai-error-midstream.sse`、`deepseek-reasoning.sse`、`anthropic-ok.sse`、`anthropic-max-tokens.sse`、`anthropic-refusal.sse`、`anthropic-error.sse`、`openai-401.json`、`anthropic-401.json`、`ollama-404.json`、`openai-whole.json`、`anthropic-whole.json`
- Modify: `tests/test.themebuilder.sse.pas`（suite `TTbAiFormatTests`）、`tools/themebuilder/themebuilder.lpi`

- [ ] **Step 1: 单元**（uses `Classes, SysUtils, fpjson, jsonparser, tbsse`；单元头注释：两种格式各是什么样（核实记录 17 的摘要），来源）：
  - `TbEndpointUrl`：`b := TrimRight(BaseUrl)` 去掉末尾 `/`；OpenAI 格式：`b` 已以 `/chat/completions` 结尾就原样，否则 `b + '/chat/completions'`；Anthropic：已以 `/messages` 结尾就原样，否则 `b + '/messages'`。
  - `TbRequestHeaders`：都有 `Content-Type: application/json`、`Accept: text/event-stream`；OpenAI：`AKey <> ''` 时 `Authorization: Bearer <key>`；Anthropic：`x-api-key: <key>`（空也发——Anthropic 没有无密钥的用法，让服务说 401）、`anthropic-version: 2023-06-01`。
  - `TbRequestBody`（`TJSONObject`，`AsJSON`）：OpenAI：`model`、`stream: true`、`messages` = `[{"role":"system","content":ASystem}]` + 每条（`user` / `assistant`）、`MaxOutput > 0` 时 `max_tokens`；Anthropic：`model`、`max_tokens`（`MaxOutput`，≤ 0 时用 ~~64000~~ `TbAnthropicDefaultMaxOutput` = 32000，开工核对第 3 条）、`system`、`messages`、`stream: true`。**不发** `temperature`（当前的推理 / 思考模型拒收）。
  - `TbParseStreamEvent`：`Data` 解析失败 → `tspError`、文字 `'not JSON: ' + Copy(Data, 1, 80)`。OpenAI：`Data = '[DONE]'` → `tspDone`；有 `error` 对象 → `tspError`（`error.message`）；`choices[0].delta.content` 是非空字符串 → `tspText`；`delta.reasoning_content` 非空 → `tspThinking`；`finish_reason = 'length'` → `tspTruncated`；`= 'content_filter'` → `tspRefused`；其余（`stop`、空的开头块）→ `tspNone`。Anthropic（看 `Name`，名字是 `message` 时看 JSON 的 `type`）：`content_block_delta` + `delta.type = 'text_delta'` → `tspText`（`delta.text`）；`thinking_delta` / `signature_delta` 或 `content_block_start` 且 `content_block.type = 'thinking'` → `tspThinking`；`message_delta` 的 `delta.stop_reason = 'max_tokens'` → `tspTruncated`、`= 'refusal'` → `tspRefused`；`message_stop` → `tspDone`；`error` → `tspError`（`error.message`，没有就 `error.type`）；`ping`、`message_start`、`content_block_stop`、其余 → `tspNone`。
  - `TbParseWholeReply`：OpenAI `choices[0].message.content`；Anthropic `content` 数组里 `type = 'text'` 的 `text` 连起来；都没有 → False。
  - `TbErrorBodyMessage`：JSON 里 `error` 是对象 → `error.message`（没有就 `error.type`）；`error` 是字符串 → 它；顶层有 `message` → 它；解析不了 → `Trim(Copy(去掉控制字符的原文, 1, 200))`。
- [ ] **Step 2: fixture**（每个 `.sse` 第一行是 SSE 注释写来源，如 `: hand-written after https://platform.openai.com/docs/api-reference/chat-streaming (2026-10-01)`——解析器忽略注释，样本自己带出处；`.json` 不能带注释，来源写在测试单元的注释里）：
  - `openai-ok.sse`：开头块（`role: assistant`、`content: ""`）、四块内容 `'Here is the theme.\n'`、`` '```tycss\n' ``、`':root { --accent: #2563EB; }\n'`、`` '```' ``、结束块（`finish_reason: stop`、`delta: {}`）、`data: [DONE]`，每个事件后空行；其中一块内容用 `\u4e2d\u6587` 写两个汉字（`'中文'`）、一块含 emoji 的代理对 `\ud83c\udfa8`（🎨）。
  - `openai-length.sse`：两块内容后 `finish_reason: length`、`[DONE]`。
  - `openai-error-midstream.sse`：一块内容后 `data: {"error":{"message":"The server had an error while processing your request.","type":"server_error"}}`，没有 `[DONE]`。
  - `deepseek-reasoning.sse`：`: keep-alive` 注释、两块 `reasoning_content`、两块 `content`、`stop`、`[DONE]`。
  - `anthropic-ok.sse`：`message_start`、`content_block_start`（index 0，`thinking`）、`content_block_delta`（`thinking_delta`，`thinking: ""`）、`content_block_delta`（`signature_delta`）、`content_block_stop`、`ping`、`content_block_start`（index 1，`text`）、三个 `text_delta`（拼起来是一个完整的 ` ```tycss ` 代码块）、`content_block_stop`、`message_delta`（`stop_reason: end_turn`、`usage`）、`message_stop`。
  - `anthropic-max-tokens.sse`：一个 `text_delta` 后 `message_delta` 的 `stop_reason: max_tokens`、`message_stop`。
  - `anthropic-refusal.sse`：`message_delta` 的 `stop_reason: refusal`。
  - `anthropic-error.sse`：一个 `text_delta` 后 `event: error`、`data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}`。
  - `openai-401.json`：`{"error":{"message":"Incorrect API key provided: sk-proj-****************************ab12. You can find your API key at https://platform.openai.com/account/api-keys.","type":"invalid_request_error","param":null,"code":"invalid_api_key"}}`；`anthropic-401.json`：`{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}`；`ollama-404.json`：`{"error":{"message":"model \"qwen9\" not found, try pulling it first","type":"api_error","param":null,"code":null}}`；`openai-whole.json` / `anthropic-whole.json`：非流式的完整应答各一份（含一个代码块）。
- [ ] **Step 3: 判据测试**（`TTbAiFormatTests`；样本经 `TTbSseParser` 拆成事件再逐个 `TbParseStreamEvent`，文字片段拼起来比）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| A1 | `TbEndpointUrl`：(`https://api.openai.com/v1`, OpenAI) → `…/v1/chat/completions`；(`…/v1/`, OpenAI) 同；(`http://h/v1/chat/completions`, OpenAI) 原样；(`https://api.anthropic.com/v1`, Anthropic) → `…/v1/messages`；(`…/v1/messages`, Anthropic) 原样 | 不去末尾 `/`（得到 `//chat`） |
| A2 | 请求头：OpenAI 有密钥 → 含 `Authorization: Bearer k`；无密钥 → 没有任何 `Authorization`；Anthropic → `x-api-key: k`、`anthropic-version: 2023-06-01`；两者都有 `Content-Type: application/json` | 空密钥也发 `Authorization: Bearer ` |
| A3 | 请求体（解析回 JSON 再查字段）：OpenAI、`MaxOutput = 0` → 没有 `max_tokens`；`= 8192` → 有；`messages[0]` 是 `system`、其后 `user` / `assistant` 顺序与输入相同；`stream = true`；没有 `temperature`；Anthropic → `system` 在顶层、`messages` 里没有 `system`、`max_tokens = 32000`（`MaxOutput = 0` 时；开工核对第 3 条）；**中文与 `"`、`\`、换行、制表符**的描述往返解析后逐字相同，原始请求体里中文是 UTF-8 原样（不是 `\u`） | OpenAI 在 `MaxOutput = 0` 时也发 `max_tokens` |
| A4 | `openai-ok.sse` → 文字 = 期望的完整回答（含 `中文` 与 🎨 的 UTF-8）、最后一个有意义的片段是 `tspDone`；`tspText` 片段数 = 4 | — |
| A5 | `deepseek-reasoning.sse` → 有 `tspThinking`、文字只含 `content` 的部分 | `reasoning_content` 当正文 |
| A6 | `\u` 写的汉字与代理对（A4 的那两块）解码正确——这一条单列，红了就是 fpjson 的 `\u` 问题（核实记录 15），修法：解析前自己把 `\uXXXX` 解成 UTF-8（`\u0022`、`\u005C`、`< \u0020` 保留转义） | — |
| A7 | `openai-length.sse` → 出现 `tspTruncated`；`openai-error-midstream.sse` → `tspError` 且文字含 `server had an error` | `length` 当正常结束 |
| A8 | `anthropic-ok.sse` → 文字 = 三个 `text_delta` 连起来；思考块产生 `tspThinking`；`ping` 是 `tspNone`；最后 `tspDone` | `thinking_delta` 当正文（文字前多出空串之外的东西——样本里 `signature_delta` 带一段签名串，当正文就混进去了） |
| A9 | `anthropic-max-tokens.sse` → `tspTruncated`；`anthropic-refusal.sse` → `tspRefused`；`anthropic-error.sse` → `tspError`、文字 `Overloaded` | `stop_reason` 不看 |
| A10 | `TbErrorBodyMessage`：三个错误体分别得到 `Incorrect API key provided: …`、`invalid x-api-key`、`model "qwen9" not found, try pulling it first`；`'{"error":"boom"}'` → `boom`；`'<html>502 Bad Gateway</html>'` → 以 `<html>502` 开头、≤ 200 字节 | 只认 `error` 对象（字符串形式得到 ''） |
| A11 | `TbParseWholeReply`：两个 `*-whole.json` 各得到代码块所在的全文；`'{"x":1}'` → False | — |
| A12 | 不是 JSON 的 `data`（`data: hello`）→ `tspError`，不抛 | 解析异常往外抛 |

- [ ] **Step 4: 提交**：`feat(themebuilder): requests and streamed replies for OpenAI-compatible services and Anthropic` + Co-Authored-By（正文一句：样本按官方文档手写，来源在样本第一行）。

---

### Task 5: 一次流式调用、错误说成一句话、密钥不外露

**Files:**
- Create: `tools/themebuilder/ai/tbaiclient.pas`、`tests/test.themebuilder.aiclient.pas`（suite `TTbAiClientTests`）
- Modify: `tools/themebuilder-curl-wsl/tbcurlwsl.lpr`（加 C 组）、`tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 单元**（uses `Classes, SysUtils, SyncObjs, StrUtils, tbhttp, tbsse, tbaiformat`）：
  - `Run`：`FTransport := TbCreateTransport(reason)`（nil → `aekNoTransport`、`Detail := reason`）；请求 = 地址 `TbEndpointUrl`、头 `TbRequestHeaders`、正文 `TbRequestBody`、连接超时 15 s、空闲超时 `TimeoutSec * 1000`（0 时 120 s）；`OnStatus` 记状态；`OnData`：2xx → 喂 SSE 拆分器，同时把原始字节攒进 `FRaw`（只留前 256 KB，给「不是流式」的兜底用）；非 2xx → 只攒进 `FRaw`（上限 64 KB）。SSE 事件回调里 `TbParseStreamEvent`：`tspText` → `FText := FText + 文字`、`AOnDelta(Self, tspText, 文字)`；`tspThinking` → `AOnDelta(Self, tspThinking, '')`（只在这一轮第一次与每隔 1 秒报一次，免得刷屏）；`tspDone` → 记 `FDone`；`tspTruncated` / `tspRefused` → 记下；`tspError` → 记 `FStreamError`。`Execute` 返回后 `Finish` 拆分器，然后按下面的顺序定结果（第一条成立的）：
    1. 传输错误 `hekCancelled` → `aekCancelled`；其余传输错误 → 一一对应（`hekBadUrl` → `aekBadUrl`……`hekBroken` → `aekBroken`、`hekOther` → `aekOther`），`Detail` = 传输的 `Detail`。
    2. 状态 401 / 403 → `aekAuth`；404 → `aekNotFound`；429 → `aekRateLimit`；400 / 413 / 422 / 其余 4xx → `aekBadRequest`；5xx（含 529）→ `aekServer`；`Detail = TbErrorBodyMessage(FRaw)`。
    3. `FStreamError <> ''` → `aekServer`、`Detail = FStreamError`。
    4. `FRefused` → `aekRefused`；`FTruncated` → `aekTruncated`。
    5. 一个 SSE 事件都没有：`TbParseWholeReply(FRaw)` 成功 → 当作完整回答（`FText := 它`、补发一次 `tspText`、`aekNone`）；否则 `aekBadFormat`，`Detail` = 原文开头 80 字节（去掉控制字符）。
    6. 有事件但既没有 `tspDone` 也没有 OpenAI 的结束块（`finish_reason` 非空）→ `aekBroken`（服务说完了才算完）。
    7. 否则 `aekNone`。
    最后 `Result.Text := FText`、`Result.Detail := TbScrubSecret(Detail, FKey)`。
  - `Cancel`：锁里置标志，`FTransport <> nil` 时 `FTransport.Cancel`。
  - `TbScrubSecret(AText, AKey)`：`AKey` 长度 ≥ 8 时：整串换 `***`；`Copy(AKey, 1, 6)` 与 `Copy(AKey, Length(AKey) - 3, 4)` 出现的地方所在的「词」（以空白、引号、逗号、句号结尾为界；`sk-proj-…ab12.` 这种以句号收尾的去掉句号再看）整个换成 `***`；另外任何含 `***` 或连续 4 个以上 `*` 的词换成 `***`。`AKey` 为空或更短：只做最后那条。
  - `TbAiErrorSentence`（resourcestring 见下；`%s` 的主机名用 `TbHostOf(BaseUrl)`；`Detail` 非空时句末加 `' ' + Format(rsTbAiServiceSays, [Detail])`）：

```pascal
resourcestring
  rsTbAiCancelled = 'Stopped.';
  rsTbAiNoTransport = 'AI is not available: %s';
  rsTbAiBadUrl = 'The service address is not a web address: %s';
  rsTbAiNameNotResolved = 'Cannot find the host %s. Check the address and the network.';
  rsTbAiCannotConnect = 'Cannot connect to %s. Is the service running, or does it need a proxy?';
  rsTbAiTls = 'The secure connection to %s failed.';
  rsTbAiTimeout = 'No reply from %s for %d seconds.';
  rsTbAiBroken = 'The connection to %s broke off before the reply was complete.';
  rsTbAiAuth = 'The key was refused (%d). Check the key in the AI settings.';
  rsTbAiNotFound = 'Wrong address or model name (404).';
  rsTbAiRateLimit = 'Too many requests (429). Wait a little and try again.';
  rsTbAiBadRequest = 'The service refused the request (%d).';
  rsTbAiServer = 'The service had a problem (%d). Try again later.';
  rsTbAiStreamError = 'The service stopped with an error.';
  rsTbAiBadFormat = 'The reply is not in the expected format.';
  rsTbAiTruncated = 'The reply reached the maximum output length and was cut off. Raise it in the AI settings.';
  rsTbAiRefused = 'The model declined the request.';
  rsTbAiOther = 'The request failed.';
  rsTbAiServiceSays = '(%s)';
```

  （`aekServer` 且状态为 0 → 用 `rsTbAiStreamError`；`aekBadFormat` 的细节进括号。）
  - `TbHostOf`：`TbSplitUrl` 的主机，失败给原串。
- [ ] **Step 2: 判据测试**（`TTbAiClientTests`；全部打到 `TTbFakeHttpServer`、走真实传输；`Run` 在测试里的小线程上跑，主线程等；回调里记下片段与线程 ID）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| C1 | OpenAI 流：服务端以分块编码发 `openai-ok.sse`，**切成 7 块、块界落在一个事件中间与一个 `\r\n` 中间**，块间睡 50 ms → `Kind = aekNone`、`Text` = A4 的全文；`tspText` 回调 ≥ 4 次、都在工作线程上（线程 ID ≠ 主线程）；服务端收到的路径是 `/v1/chat/completions`、正文里 `stream: true` | 拆分器不跨块保留半行（块界在事件中间的那一块丢字） |
| C2 | Anthropic 流（`anthropic-ok.sse`，同样切块）→ 文字正确；收到过 `tspThinking`；请求头有 `x-api-key`、`anthropic-version` | — |
| C3 | 401：OpenAI 形状的错误体（`openai-401.json`），密钥 `'sk-proj-abcdefghijklmnopqrstuvwxyzab12'` → `aekAuth`、`Status = 401`；**先证明**原始错误体里含 `ab12`（密钥后四位）；`Detail` 与 `TbAiErrorSentence(...)` 都**不含** `ab12`、不含 `sk-proj-a`、不含密钥整串，含 `***` 与 `Incorrect API key` | `Run` 末尾不调 `TbScrubSecret` |
| C4 | 429（Anthropic 形状 `rate_limit_error`）→ `aekRateLimit`；句子以 `rsTbAiRateLimit` 开头、括号里是服务的消息 | 429 落到 `aekBadRequest` |
| C5 | 404（`ollama-404.json`）→ `aekNotFound`，句子含 `model "qwen9" not found` | — |
| C6 | 500 → `aekServer`；529 → `aekServer` | — |
| C7 | 断流：分块发 `openai-ok.sse` 的前一半，然后 `FakeClose` → `aekBroken`，`Text` 是已收到的那一半 | 传输的 `hekBroken` 被当成正常结束（得到 `aekNone`） |
| C8 | 服务说完了才算完：`openai-ok.sse` 去掉结束块与 `[DONE]`、但正常收尾（0 块）→ `aekBroken` | 判定第 6 条删掉 |
| C9 | 空闲超时：头 + 一个事件 + `FakeHold`，配置 `TimeoutSec = 1` → `aekTimeout`，句子含 `1` | — |
| C10 | 流中出错（`anthropic-error.sse`）→ `aekServer`、`Status = 200`、句子是 `rsTbAiStreamError` + `(Overloaded)` | — |
| C11 | 截断（`openai-length.sse` / `anthropic-max-tokens.sse`）→ `aekTruncated`，`Text` 保留已收到的 | — |
| C12 | 拒绝（`anthropic-refusal.sse`）→ `aekRefused` | — |
| C13 | 不是流式：200 + `application/json` + `openai-whole.json` → `aekNone`、`Text` = 其中的全文、补发过一次 `tspText` | 兜底删掉（得到 `aekBadFormat`） |
| C14 | 格式不对：200 + `text/html` + `'<html>hello</html>'` → `aekBadFormat`，句子括号里有 `<html>hello` | — |
| C15 | 取消：头 + 一个事件 + `FakeHold`，300 ms 后另一线程 `Cancel` → `aekCancelled`，1 秒内返回，`Text` 是那一个事件的文字 | `Cancel` 不转给传输 |
| C16 | 本机无密钥：配置地址 `http://127.0.0.1:<port>/v1`、密钥 '' → 服务端收到的头里没有 `authorization` | — |
| C17 | `TbScrubSecret` 表：(`'key sk-abcdef1234567890 bad'`, `'sk-abcdef1234567890'`) → `'key *** bad'`；(`'Incorrect API key provided: sk-proj-****ab12.'`, `'sk-proj-xyzxyzxyzab12'`) → 不含 `ab12`；(`'token ****wxyz'`, `''`) → `'token ***'`；(`'no secret here'`, `'k'`) → 原样 | 只换整串（第二行的半遮串留下） |

- [ ] **Step 3: WSL 程序加 C 组**：`tbcurlwsl.lpr` 加 C1、C3、C7、C9、C13、C15 在 libcurl 上的同一判据（编号写成 `C1@curl`……）。
- [ ] **Step 4: 注册与提交**：uses 加 `test.themebuilder.aiclient`。`feat(themebuilder): one streamed AI call, its failures told in one sentence, the key never in them` + Co-Authored-By。

---

### Task 6: 配置与密钥

**Files:**
- Create: `tools/themebuilder/ai/tbaisettings.pas`
- Modify: `tests/test.themebuilder.aiclient.pas`（suite `TTbAiSettingsTests`）、`tools/themebuilder-curl-wsl/tbcurlwsl.lpr`（加 K 组）、`tools/themebuilder/themebuilder.lpi`

- [ ] **Step 1: 单元**（uses `Classes, SysUtils, IniFiles, base64, tbaiformat` + `{$IFDEF MSWINDOWS} Windows {$ELSE} BaseUnix {$ENDIF}`）：
  - ini 格式（`AIniFile`，`TMemIniFile`，UTF-8）：`[General] Current=<id>`、`Order=<id>,<id>,…`；每个配置一节 `[Profile.<id>]`：`Name`、`Format`（`openai` / `anthropic`）、`BaseUrl`、`Model`、`MaxOutput`、`TimeoutSec`；Windows 另有 `[Keys] <id>=<base64 的 DPAPI 密文>`。Unix 的密钥在 `AKeyFile`：每行 `<id>=<key>`（密钥里有换行或 `=` 之外的控制字符就拒收——`SetKey` 抛 `EArgumentException`）。
  - `Load`：文件不存在 = 空；`Order` 里列的按序读，节缺失的跳过；`Current` 不在里面就取第一个。Unix：读密钥文件前 `fpStat`，`st_mode and &077 <> 0` 就 `fpChmod(&600)`。
  - `Save`：ini 先写同目录临时文件再替换（照 1 期 `tbdocument` 的原子写法，可以直接调它导出的那个函数——若 1 期没有导出，就在本单元写一份同样的：Windows `MoveFileExW(REPLACE_EXISTING or WRITE_THROUGH)`，Unix `fpRename`）；Unix 密钥文件用 `TbWritePrivateFile`；任何一步失败返回 False、不抛（照 1 期「设置写不进去不拦关窗口」）。`ForceDirectories` 目录。
  - `TbWritePrivateFile`：Unix：临时名 `AFileName + '.tmp'`，`fd := fpOpen(tmp, O_WRONLY or O_CREAT or O_TRUNC, &600)`、`fpWrite`、`fpFChmod(fd, &600)`、`fpClose`、`fpRename(tmp, AFileName)`；Windows：普通写（Windows 上它只用于测试与非密钥数据）。
  - DPAPI（Windows，自己声明，核实记录 12）：

```pascal
type
  TDataBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PDataBlob = ^TDataBlob;
const
  CRYPTPROTECT_UI_FORBIDDEN = 1;
  cEntropy: RawByteString = 'TyControls.ThemeBuilder.AI';
function CryptProtectData(pDataIn: PDataBlob; szDataDescr: PWideChar; pOptionalEntropy: PDataBlob;
  pvReserved, pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PDataBlob): BOOL;
  stdcall; external 'crypt32.dll';
function CryptUnprotectData(pDataIn: PDataBlob; ppszDataDescr: PPWideChar; pOptionalEntropy: PDataBlob;
  pvReserved, pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PDataBlob): BOOL;
  stdcall; external 'crypt32.dll';
```

  `TbProtectKey`：输入 = 密钥的 UTF-8 字节，输出密文 `EncodeStringBase64`，`LocalFree(out.pbData)`；失败抛 `Exception`（消息不含密钥）。`TbUnprotectKey`：`DecodeStringBase64` → `CryptUnprotectData` → 成功取出、`LocalFree`；任何失败返回 False。
  - `TbPresetProfile`（开工前问题一第 1 条的表；`Name` = `TbPresetCaption`；`Id` = `TbNewProfileId`）。`TbPresetCaption`：`'OpenAI'`、`'DeepSeek'`、`'Anthropic'`（品牌名不译、不进 resourcestring）、`rsTbAiPresetLocal = 'Local (Ollama)'`、`rsTbAiPresetCustom = 'Custom'`。`TbNewProfileId`：`CreateGUID` 去掉括号与横线、小写、取前 12 位。
  - `TbAiFilesFor(ASettingsIni)`：`dir := ExtractFilePath(ASettingsIni)`；`AIniFile := dir + 'themebuilder-ai.ini'`；`AKeyFile := {$IFDEF MSWINDOWS}''{$ELSE}dir + 'themebuilder-ai.keys'{$ENDIF}`。
- [ ] **Step 2: 判据测试**（`TTbAiSettingsTests`；文件都在测试自己的临时目录）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| K1 | 往返：两个配置（一个 Anthropic、一个 Ollama 预置），改名、设 `MaxOutput`、设当前、`Save`；另建一个 `Load` → 顺序、全部字段、当前都相同 | `Save` 不写 `Order`（顺序丢） |
| K2 | 密钥：`SetKey(id, 'sk-test-ABCDEFGH12345678')`、`Save`；另建 `Load` → `GetKey` 相同；**ini 文件的字节里不含**密钥整串、不含 `ABCDEFGH`、不含它的 base64（`EncodeStringBase64(密钥)`）（Windows） | 存成明文 / 存成 base64 明文 |
| K3 | 篡改：把 ini 里那条密文改一个字符 → `GetKey = ''`，不抛 | `TbUnprotectKey` 的异常往外抛 |
| K4 | `Delete(id)` 同时删掉它的密钥（再 `Save` + `Load`，`[Keys]` 里没有那个 id） | `Delete` 不删密钥 |
| K5 | 文件不存在 → `Count = 0`、`Current` 为 False；写不进去的目录（指向一个**已存在的文件**下面的子目录）→ `Save = False`、不抛 | `Save` 不包异常 |
| K6 | 预置：五个预置的格式、地址、`MaxOutput` 与开工前问题一第 1 条的表相同；Anthropic 的 `MaxOutput > 0`；两次 `TbPresetProfile(tapOpenAI)` 的 `Id` 不同 | — |
| K7 | `TbAiFilesFor('C:\x\themebuilder.ini')` → `C:\x\themebuilder-ai.ini`；Windows 上密钥文件为 '' | — |
| K8 | （Windows）`TbProtectKey` 两次同一密钥 → 密文不同（DPAPI 带随机盐），都能解回 | — |

- [ ] **Step 3: WSL 程序加 K 组**：K1、K2（Unix 版：密钥文件存在、`fpStat` 的 `st_mode and &777 = &600`、ini 里没有密钥）、K9 = 先手写一个 0644 的密钥文件再 `Load` → 之后权限是 0600、密钥读得出来、K10 = `TbWritePrivateFile` 新建的文件是 0600（`umask 022` 下）。
- [ ] **Step 4: 提交**：`feat(themebuilder): AI services as profiles; keys encrypted for the user on Windows, 0600 elsewhere` + Co-Authored-By。

---

### Task 7: 精简参考

**Files:**
- Create: `tools/themebuilder/ai/tbreference.pas`、`tests/test.themebuilder.reference.pas`（suite `TTbReferenceTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 单元**（uses `Classes, SysUtils, StrUtils, tyControls.Css.Catalog, tyControls.Css.Parser, tyControls.Css.Values, tyControls.StyleModel, tyControls.BuiltinThemes, tbseeds`；单元头注释：参考给模型看、为什么运行时拼（核实记录 22）、哪些来自代码哪些手写、守卫在哪）。`TbReferenceText` 依次拼九节（标题一律 `## `，英文）：
  1. **Answer format** —— 一句：「The rules for answering are in the system prompt above this reference.」（规则本身在 `tbaisession` 的系统提示里，这里不重复。）
  2. **How a file is built**（手写常量 `cSyntax`）：

```text
## How a .tycss file is built
- A file is a sequence of :root blocks, rules and @mode blocks, in any order. @import lines must come first.
- :root { --name: value; } defines variables. Use them as var(--name) or as a bare --name.
- @mode light { :root { ... } } and @mode dark { :root { ... } } hold the variables of each mode. Only :root may appear inside @mode.
- A rule is: selector-list { property: value; ... }.
- Selector: TypeKey, optionally .variant, optionally :state. Examples: TyButton, TyButton.primary, TyButton:hover, TyButton.primary:hover. A comma list applies the same declarations to each selector.
- States: <TbKnownStates>. One state per selector; :checked means :selected.
- Every declaration ends with a semicolon, the last one in a block too.
- Comments are /* ... */ only.
- Names (types, variants, states, properties, functions) are not case-sensitive.
- Colours: #rgb, #rrggbb, #rrggbbaa, transparent, or a colour function.
- Lengths are plain numbers or numbers with px. font-size is in points.
- The file sits on top of the built-in base theme: anything the file does not define comes from the base.
- A rule for a TypeKey replaces ALL of the base theme's rules for that TypeKey (every state and variant), not just the properties you write. Restate everything the control needs, or leave the TypeKey alone and change variables instead.
Not supported (the parser rejects them or the engine ignores them):
- descendant or child selectors (TyPanel TyButton, TyPanel > TyButton), *, .variant without a type, :state without a type, two variants (TyButton.a.b), chained states (:hover:focus)
- @media, !important, // comments, escapes in strings
- margin, width, height, gap, per-corner radius (border-top-left-radius), percentage radius
- border-style dashed / dotted / groove / ridge
- quotes around font-family names
- alpha() takes 0..1, not a percentage; linear-gradient angles: 0deg = left to right, 90deg = top to bottom; two colour stops only
```

     `<TbKnownStates>` 运行时由 `TyKnownPseudoStates` 填（`hover, active, focus, disabled, selected, checked`）。
  3. **Seeds**：`TbSeedNames` 每个一行 `--accent: light #3B82F6, dark #60A5FA`——值从内置默认主题解析结果的亮、暗两个 `@mode` 块里取（`TTyCssParser.Create(TyBuiltinThemeCss('default')).Parse`，`ModeBlocks` 里 `Mode = 'light'` / `'dark'` 的 `Vars.Values[名字不带 --]`），一句说明「Change these first: most colours derive from them.」
  4. **Derived variables (light mode of the base theme)**：亮色块里种子以外的每个变量一行 `--名字: 原值`（按出现顺序）；一句说明「Defined in both modes the same way; dark mode uses its own seeds. Override any of them in your file to change what derives from it.」
  5. **Other variables**：`TyCatalogTokens` 里没在第 3、4 节出现过的名字，逗号连起来（只给名字），一句「Defined by the base theme; use them with var(), override them if needed.」
  6. **Properties**：`TyKnownStyleProps` 每个一行：`- 名字: TbPropertyNote(名字)`，有 `TyStyleValueHints` 的再加 ` Values: a, b, c.`（`(` 结尾的提示如 `linear-gradient(` 写成 `linear-gradient(...)`）。`TbPropertyNote` 是手写表（每个一句，内容取自 `docs/tycss-reference.md` §5）：`background`「colour, transparent, none, or linear-gradient(angle, colour, colour)」、`background-image`「url(file) slice(t r b l): a nine-patch image, path relative to the theme file」、`padding`「1 to 4 lengths (top right bottom left)」、`border-radius`「1, 2 or 4 lengths」、`font-size`「points」、`font-weight`「normal, bold, or a number (600 and above is bold)」、`shadow`「x y blur colour; the colour must be one token (#rrggbbaa or a variable)」、`outline`「width colour; outline-offset only works together with outline」、`opacity`「0..1」……23 个全写。
  7. **Colour functions**：`TyKnownColorFns` 每个一行 `TbColorFnSignature`：`var(--name)`、`lighten(colour, 0..100)`、`darken(colour, 0..100)`、`alpha(colour, 0..1)`、`mix(colour1, colour2, 0..100)`、`rgb(r, g, b)`、`rgba(r, g, b, a)`、`elevate(colour, level)`、`on(colour)`（`elevate` / `on` 的意思照 `docs/tycss-reference.md` §6 与 `Css.Values.pas` 的实现写一句）。
  8. **TypeKeys**：`TyCatalogTypeKeys` 逗号连起来；在默认主题规则里出现过变体的，名字后面跟括号列出变体（`TyButton(.primary .danger .ghost)`）。
  9. **A complete small theme**（手写常量 `cExample`，约 50 行）：两个 `@mode` 块（六个种子 + 两三个推导变量的覆盖）+ 一条完整重写 `TyButton, TySpeedButton` 的规则组（基础、`:hover`、`:active`、`:focus`、`:disabled`、`.primary`、`.primary:hover`——写全每个状态要的属性，示范第 2 节最后一条）+ 一条 `TyEdit` 的 `:focus`。注释里说明「this restyles buttons completely; everything else comes from the seeds」。
  - `TbReferenceClaims`：第 2 节每一条配一段片段：「支持」的（`MustParse = True`）：`':root { --a: #fff; } TyButton { background: var(--a); }'`、`'TyButton { background: --accent; }'`（裸变量）、`'TyEdit:focus, TyComboBox:focus { border-color: #123456; }'`、`'TyButton:checked { color: #000; }'`、`'@mode dark { :root { --a: #000; } }'`、`'TyButton { padding: 2px 4px 6px 8px; }'`、`'TyButton { border-radius: 2px 4px; }'`；「不支持」的（`MustParse = False` = 解析失败**或** lint 报错误）：`'TyPanel TyButton { color: #000; }'`、`'TyPanel > TyButton { }'`、`'* { }'`、`'.primary { }'`、`':hover { }'`、`'TyButton.a.b { }'`、`'TyButton:hover:focus { }'`、`'@media x { }'`、`'TyButton { color: #000 !important; }'`、`'// c'#10'TyButton { }'`、`'TyButton { margin: 1px; }'`、`'TyButton { width: 10px; }'`、`'TyButton { border-top-left-radius: 2px; }'`、`'TyButton { color: #000 }'`（块里最后一条漏分号：解析器在每条声明后 `Expect(ctkSemicolon)`，`source/tyControls.Css.Parser.pas:335`，是解析错误）。R5 红了先看是参考说错了还是片段写错了：引擎的行为为准，改参考那句话或片段，签收写一句。
- [ ] **Step 2: 判据测试**（`TTbReferenceTests`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| R1 | 属性说明与源同步：`TbNotedProperties` 与 `TyKnownStyleProps` 作为集合相等（两个方向）；参考文本里每个属性名都出现 | 删掉一条说明；或在说明表里多一个 `margin` |
| R2 | 颜色函数同步：`TbSignedColorFns` 与 `TyKnownColorFns` 集合相等；每个签名里把占位换成例子（`colour` → `#336699`、`0..100` → `10`、`0..1` → `0.5`、`level` → `1`、`--name` → `--surface`（在一个定义了 `--surface: #FFFFFF` 的变量表里））后 `TyEvalColor` 不抛 | 签名表少 `on` |
| R3 | typeKey 全在：`TyCatalogTypeKeys` 每一个都在参考文本里（按「前后不是字母数字」的整词找）；`TyButton(.primary .danger .ghost)` 这一段在 | 只列前 100 个 |
| R4 | 种子值与默认主题一致：参考里 `--accent: light #3B82F6, dark #60A5FA`——但不写死：期望值也从 `TyBuiltinThemeCss('default')` 解析得到，比参考里那一行（守的是「拼对了」，不是「值是多少」）；六个种子都有 | 亮暗取反 |
| R5 | 片段守卫：`TbReferenceClaims` 每一条，`MustParse` 为 True 的 → `TTyCssParser.Parse` 不抛且 `TyLintCssEx` 没有 `tlsError`；为 False 的 → 解析抛 `ETyCssError` 或 `TyLintCssEx` 有 `tlsError`；失败消息打印那句话与片段 | —（守卫本身：引擎将来改了行为这里会红，提醒改参考） |
| R6 | 长度：`TbReferenceApproxTokens` 在 4000–8500 之间；打印实数（Task 15 记进签收） | 第 5 节把变量名写成「名字: 值」（变长，超上限） |
| R7 | 例子能用：`TbReferenceExample` 解析不抛；`TbCollectProblems(例子, '', True, 底层变量)` 没有错误；装进一个新 `TTyStyleModel`（`LoadFromSource(TTbTextThemeSource)`）后 `light`、`dark` 两个模式各 `TbProbeDocument` 都过 | 例子的暗色块漏一个种子并在规则里用一个只在亮色定义的变量（试解析红） |
| R8 | 全是 ASCII：参考文本每个字节 < 128（中文会让 token 估算失真） | 说明里混进一个全角标点 |
| R9 | WSL 单元不引 LCL（地雷 36）：读 `ai/tbhttp.pas`、`tbhttpwin.pas`、`tbhttpcurl.pas`、`tbsse.pas`、`tbaiformat.pas`、`tbaiclient.pas`、`tbaisettings.pas` 与 `tests/tbfakehttp.pas` 的文本，`uses` 段（interface 与 implementation 两处，到分号为止）里的每个单元名都在允许表里 | 在 `tbaiclient` 的 uses 里加 `Forms`（WSL 编不过——也算红） |
| R10 | 缓存：两次 `TbReferenceText` 返回同一串（`Pointer(s1) = Pointer(s2)`） | — |

- [ ] **Step 3: 注册与提交**：uses 加 `test.themebuilder.reference`。`feat(themebuilder): a short tycss reference for the model, put together from the engine's own lists` + Co-Authored-By（正文：不是构建时生成的文件；手写的部分有片段守着）。

---

### Task 8: 按行对比

**Files:**
- Create: `tools/themebuilder/tbdiff.pas`、`tests/test.themebuilder.diff.pas`（suite `TTbDiffTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 单元**（uses `Classes, SysUtils, tbcssscan`）：
  - `TbSplitLines`：按 CRLF / LF / CR 断行；文末的换行不产生空行；空串 → 0 行。
  - `TbDiffLines`：`p` = 共同前缀行数、`s` = 共同后缀行数（不与前缀重叠）；中间段 `n × m`：`n * m <= TbDiffMaxCells` → LCS 表（`array of array of Integer`，`(n+1) × (m+1)`，从后往前填）再从前往后走出删 / 增 / 同序列；否则整段删 + 整段增。然后**配对**：连续的删（k 行）紧跟连续的增（j 行）→ 前 `min(k, j)` 对配成 `tdkChanged`（`Left`、`Right` 都有），多出来的留作删（`Right = -1`）或增（`Left = -1`）。
  - `TbDiffChangeCount`：连续的非 `tdkSame` 行算一处。
  - `TbNormalizeEol`：各种换行换成 `LineEnding`；不以换行结尾就补一个；空串仍是空串。
  - `TbWholeTextEdit(AOld, ANew)`：两者都先 `TbNormalizeEol`；找共同前缀**行**（按 `LineEnding` 切）与共同后缀行（不重叠）；`Start` = 前缀行的字节总长 + 1；`Stop` = `Length(AOld) - 后缀字节总长 + 1`；`Text` = `ANew` 的中间那段。完全相同 → `Start = Stop`、`Text = ''`。**调用方保证 `AOld` 就是编辑器的 `Lines.Text`**（已是 `LineEnding` 且以它结尾），`AOld` 不变，所以偏移在原文上成立。
- [ ] **Step 2: 判据测试**（`TTbDiffTests`）：

| # | 输入（左 → 右，`|` 分行） | 期望 | 在哪个变异下必须红 |
|---|---|---|---|
| D1 | `a|b|c` → `a|b|c` | 3 行 `tdkSame`；`ChangeCount = 0` | — |
| D2 | `a|b|c` → `a|x|c` | `same, changed(1,1), same` | 不配对（得到 removed + added 两行） |
| D3 | `a|b|c` → `a|c` | `same, removed(1,-1), same` | — |
| D4 | `a|c` → `a|b|c` | `same, added(-1,1), same` | — |
| D5 | `a|b|c|d` → `a|x|y|z|d` | `same, changed, changed, added, same` | 配对时多出来的方向搞反 |
| D6 | `x|a|b` → `a|b|y`（首删尾增） | `removed, same, same, added`；`ChangeCount = 2` | 前后缀重叠时多算 |
| D7 | 两边都以 CRLF 写 vs LF 写同样的行 | 全 `same` | 不按任意换行切 |
| D8 | 1409 行（`themes/light.tycss`）→ 改其中第 700 行、删第 900 行 → 恰好两处改动；用时 < 200 ms（打印） | 不先去首尾（全量 LCS，用时超限——若机器快到不超，签收写「等价」） |
| D9 | 超格数：`TbDiffMaxCells` 临时当作 4（测试里传一个更小的上限：把上限做成函数参数的默认值 `AMaxCells: Integer = TbDiffMaxCells`）→ `a|b|c` → `x|b|y` 得到整段删 + 增配成 changed / changed / changed，不抛 | — |
| D10 | `TbWholeTextEdit('a'#13#10'b'#13#10'c'#13#10, 'a'#10'X'#10'c'#10)`（编辑器文本在 Windows 上是 CRLF）→ `Start` 指向 `b`、`Stop` 指向 `c` 那一行开头、`Text = 'X' + LineEnding`；`TbApplyEdits(旧, [它]) = TbNormalizeEol(新)` | 后缀不去（`Stop` 落在文末之后） |
| D11 | 相同文本 → `Start = Stop`、`Text = ''`；整篇都不同 → `Start = 1`、`Stop` = 最后那个换行之前（共同的结尾换行留在后缀里）——**`Stop <= Length(旧)`** | 允许 `Stop = Length + 1`（2 期 `TbOffsetToPoint` 会落到不存在的行） |
| D12 | `TbSplitLines('a'#13'b'#10'c')` → 3 行；`'a'#10` → 1 行；`''` → 0 行 | 文末换行多出空行 |

- [ ] **Step 3: 注册与提交**：uses 加 `test.themebuilder.diff`。`feat(themebuilder): a line diff for the AI comparison, and a whole-text edit that touches only the changed lines` + Co-Authored-By。

---

### Task 9: 一次生成——提示、多轮、取代码块、校验、回喂

**Files:**
- Create: `tools/themebuilder/ai/tbaisession.pas`、`tests/tbaitesthelp.pas`、`tests/test.themebuilder.aisession.pas`（suite `TTbAiSessionTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: 给模型的文字**（`implementation` 里的 `const`，英文，地雷 35）：

```pascal
const
  cRules =
    'You edit themes for TyControls, a control library for Lazarus and Free Pascal. ' +
    'A theme is a .tycss file, a small CSS dialect described in the reference below. ' +
    'The user''s file sits on top of the library''s built-in base theme, so a file that ' +
    'only sets the six seed variables is already a complete theme.'#10#10 +
    'How to answer:'#10 +
    '1. Output the whole new file in exactly one fenced code block that starts with ```tycss. ' +
    'You may write one short sentence before it, in the user''s language. Write nothing after it.'#10 +
    '2. Keep the file''s structure. If it has @mode light and @mode dark blocks, keep both and ' +
    'change both consistently. If it has none, do not add them unless asked.'#10 +
    '3. Use only the properties, functions, states and TypeKeys listed in the reference.'#10 +
    '4. Prefer changing the seed variables and the derived variables over writing rules.'#10 +
    '5. A rule for a TypeKey replaces all of the base theme''s rules for that TypeKey. If you ' +
    'write one, restate everything that control needs, in every state.'#10 +
    '6. Keep text readable: enough contrast against its background, in both modes.'#10 +
    '7. Keep everything the user did not ask to change, comments included.'#10#10;
  cEarlier = 'Earlier requests in this conversation, oldest first:';
  cAccepted = ' (accepted: the current file includes it)';
  cNotUsed = ' (not used)';
  cProblems = 'Problems the editor reports in the current file:';
  cCurrent = 'Current file:';
  cRequest = 'Request: ';
  cFeedbackHead = 'The theme engine found problems in your file:';
  cFeedbackTail = 'Fix them and output the whole corrected file again in one ```tycss block. ' +
    'Change nothing else.';
```

  `TbSystemPrompt` = `cRules + TbReferenceText`。
- [ ] **Step 2: 纯函数**：
  - `TbExtractCodeBlock(AReply, out ABlock, out ATruncated)`：按行扫，围栏行 = 去掉前导空白后以 ```` ``` ```` 开头；开围栏后面的语言标签（去空白、小写）；收集所有闭合的块（`(标签, 内容)`）。选法：第一个标签是 `tycss` 的；没有就第一个 `css`；没有就恰好一个无标签块时用它；还没有就最长的那个。有开围栏却没闭合（文本在块里结束）→ `ATruncated := True`、`Result := False`。没有块 → False。内容的行尾统一成 `#10`，去掉首尾空行。
  - `TbCheckCandidate(AText, ABaseDir, AUntitled, ABaseVars)`：
    1. `p := TbCollectProblems(AText, ABaseDir, AUntitled, ABaseVars)`：`tlsError` → 错误、`tlsWarning` → 提示，都带 `Line` / `Col` 与 `Text`。
    2. 没有解析错误时：建一个 `TTyStyleModel`，`LoadFromSource(TTbTextThemeSource.Create(AText, ABaseDir))`（抛 → 一条错误，`Line = 0`，文字是异常消息），然后对 `ModeNames`（为空就只试当前模式 `''`）每个 `SetMode(m)` + `TbProbeDocument(model, AText, False, err)`，失败 → 一条错误 `Format(rsTbAiModeProbe, [m, err])`（`rsTbAiModeProbe = 'In %s mode: %s'`）。模型用完释放。（开工前问题一第 5 条。）
  - `TbFeedbackMessage(AIssues)`：`cFeedbackHead`，每个**错误**一行 `- line L, col C: 文字`（`Line = 0` 时 `- 文字`），`cFeedbackTail`。提示不进回喂。
- [ ] **Step 3: `TTbClientBackend`**：`Start` 建一个 `TTbAiWorker = class(TThread)`（`FreeOnTerminate := False`），线程里 `FClient.Run(...)`；`Run` 的 `OnDelta`（工作线程）把片段追加进带锁的 `FPending` 与「看到了思考」标志，若距上次投递 ≥ 100 ms 或这是第一个片段就 `TThread.Queue(nil, @FlushOnMain)`；`Run` 返回后存结果、`TThread.Queue(nil, @DoneOnMain)`。`FlushOnMain`（主线程）取出 `FPending`、调 `OnDelta`；`DoneOnMain` 先 `FlushOnMain` 再调 `OnDone`。`Cancel` → `FClient.Cancel`。析构：`Cancel`、`WaitFor`、`TThread.RemoveQueuedEvents(@FlushOnMain)` 与 `(@DoneOnMain)`、释放（地雷 29）。
- [ ] **Step 4: `TTbAiSession`**（字段：`FBackend`、`FHistory: TStringList`（`OwnsObjects = False`，Objects 存 `TObject(PtrInt(0/1/2))`）、`FDoc: TTbAiDocument`、`FMessages`、`FRound`、`FStreamed`、`FOutcome`、`FStage`、`FBusy`、`FStopping`）：
  - `UserMessage`：若 `FHistory.Count > 0`：`cEarlier` 换行，每条 `N. 描述` + `cAccepted` / `cNotUsed` / 无后缀（0 = 还在等结论，理论上不会有）；空行。`AWithProblems` 且 `ADoc.Problems` 有条目：`cProblems`，每条 `- line L, col C: 文字`（只列错误与警告的文字，无位置的 `- 文字`）；空行。`cCurrent`、`'```tycss'`、文档全文（行尾统一成 `#10`）、`'```'`；空行。`cRequest + 描述`。
  - `Generate`：`FBusy` 或 `FBackend = nil` 或 `Trim(描述) = ''` → False。否则：上一条描述的结论还是 0 → 记成 2（没用）；`FDoc := ADoc`；`FHistory` 先**不**加这次的（`UserMessage` 里的 Earlier 只列以前的）；`FMessages := [user(UserMessage(...))]`；`FHistory.AddObject(描述, 0)`；`FRound := 1`；`FOutcome := Default; FOutcome.BaseText := ADoc.Text`；`SetStage(tasSending)`；`FBusy := True`；`FBackend.Start(TbSystemPrompt, FMessages)`；True。（后端可能在 `Start` 里同步回调 `OnDone`——测试的假后端就这样；所以 `Start` 之前状态要全部设好，地雷见下。）
  - `BackendDelta(Sender, APiece, AText)`：`tspThinking` → 阶段 `tasThinking`；`tspText` → `FStreamed := FStreamed + AText`、阶段 `tasReceiving`、`OnStreamed`。
  - `BackendDone(Sender, AResult)`：
    1. `FOutcome.Raw := AResult.Text`；`FOutcome.Requests := FRound`。
    2. `AResult.Kind = aekCancelled` 或 `FStopping` → 阶段 `tasStopped`、`Sentence := rsTbAiCancelled`、结束。
    3. 其余 `Kind <> aekNone`（含 `aekTruncated`）→ `tasFailed`、`Sentence := TbAiErrorSentence(AResult, 当前配置)`、结束（回答里若已有完整代码块也不用——被截断的回答不可信）。
    4. `TbExtractCodeBlock`：失败 → `tasFailed`、`Sentence := rsTbAiNoBlock`（`'The reply has no tycss code block; its text is shown below.'`），截断时 `rsTbAiTruncated`；结束。
    5. 阶段 `tasChecking`；`issues := TbCheckCandidate(块, FDoc.BaseDir, FDoc.Untitled, FBaseVars)`；`FOutcome.Candidate := 块; FOutcome.Issues := issues; FOutcome.HasCandidate := True`。
    6. 有错误且 `FRound <= TbAiMaxFeedback` → `FMessages += [assistant(AResult.Text), user(TbFeedbackMessage(issues))]`；`Inc(FRound)`；`FStreamed := ''`；阶段 `tasRetrying`（状态行 `Format(rsTbAiRetrying, [错误数, FRound - 1, TbAiMaxFeedback])` = `'Found %d problems; asking the model to fix them (%d of %d)...'`）；`FBackend.Start(TbSystemPrompt, FMessages)`；**返回**（不结束）。
    7. 否则 → `tasDone`；`Sentence`：块与 `FDoc.Text` 规范化后相同 → `rsTbAiNoChange`（`'The model returned the file unchanged.'`），`HasCandidate := False`；有错误 → `Format(rsTbAiDoneIssues, [n])`（`'Done, with %d problems left.'`）；否则 `rsTbAiDoneClean`（`'Done.'`）。
    结束 = `FBusy := False; FStopping := False; OnFinished`。
  - `Stop`：`FBusy` 时 `FStopping := True; FBackend.Cancel`。
  - `ResetConversation`：忙时先 `Stop`；`FHistory.Clear`；`FOutcome := Default`。`MarkLast(AAccepted)`：最后一条记成 1 / 2。
  - `SetBackend`：忙时先 `Stop`；释放旧的；挂 `OnDelta` / `OnDone`。
  - 阶段文字（frame 显示用，放本单元 resourcestring）：`rsTbAiSending = 'Sending to %s...'`、`rsTbAiThinking = 'The model is thinking...'`、`rsTbAiReceiving = 'Receiving: %d lines so far.'`、`rsTbAiChecking = 'Checking the result...'`。
- [ ] **Step 5: 判据测试**（`TTbAiSessionTests`；假后端放在测试辅助单元 `tests/tbaitesthelp.pas`（Task 12 的主窗体测试也用）：`TScriptedBackend = class(TTbChatBackend)`：构造时给一串回答（每个 = 若干片段 + 一个 `TTbAiResult`）；`Start` 记下 `ASystem` 与 `AMessages` 的副本，**同步**依次调 `OnDelta`、`OnDone`；另有「挂起」模式：`Start` 只记下，测试再手动 `Release` 或等 `Cancel`。底层变量用 `TbBaseVarNames`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| S1 | 一次就好：回答 = 一句话 + 合法的 `tycss` 块（改亮色 `--accent`）→ `Requests = 1`、`Stage = tasDone`、`HasCandidate`、`Candidate` = 块、没有错误、`Sentence = rsTbAiDoneClean`；`OnStreamed` 至少一次 | — |
| S2 | 回喂一次：第 1 个回答块里 `TyButton { frobnicate: 1px; }`、第 2 个改好 → `Requests = 2`；第 2 次请求的消息是 `[user, assistant(第 1 个回答原文), user(回喂)]`，回喂里有 `- line 1, col 12:` 与 `frobnicate`（第 1 个回答的块就是 `TyButton { frobnicate: 1px; }` 一行，属性名从第 12 个字节起）、以 `cFeedbackTail` 结尾；最终没有错误 | 回喂不带上一次的回答（第 2 次只有两条消息） |
| S3 | 两次之后交给用户：三个回答都有同一个错误 → `Requests = 3`（不是 4）、`tasDone`、`HasCandidate`、`Issues` 有那个错误、`Sentence` 是 `rsTbAiDoneIssues` | `FRound <= TbAiMaxFeedback` 写成 `<`（只回喂一次）；或写成 `<= TbAiMaxFeedback + 1`（4 次） |
| S4 | 没有代码块 → `tasFailed`、`Requests = 1`、`Sentence = rsTbAiNoBlock`、`Raw` = 原文 | 没块也回喂 |
| S5 | 只有提示不回喂：回答里 `:root { --c: #112233; } TyButton { background: #111111; color: #131313; }`（低对比度）→ `Requests = 1`、`Issues` 里有一条 `IsError = False` | 提示也算错误 |
| S6 | 底层变量不算错：`TyButton { background: var(--surface-hover); }` → 没有错误 | `TbCheckCandidate` 不传底层变量 |
| S7 | 试解析算错（开工前问题一第 5 条）：回答是两个 `@mode` 块、亮色定义 `--only-light: #123456`、规则 `TyButton:disabled { color: var(--only-light); }` → 有一条 `Line = 0` 的错误、文字以 `In dark mode:` 开头；`Requests = 2` | `TbCheckCandidate` 去掉试解析那段 |
| S8 | 多轮——不重发旧回答：第一次描述 `make it blue`、回答块里带标记注释 `/* MARK-ONE */`，**不接受**（`MarkLast(False)`）；第二次描述 `darker` → 第二次请求的全部消息里**没有** `MARK-ONE`；用户消息里有 `1. make it blue (not used)` 与 `Request: darker` 与当前文档全文 | `UserMessage` 把上一次的候选附上 |
| S9 | 多轮——接受的写明：同 S8 但第一次 `MarkLast(True)` 且文档换成含 `MARK-ONE` 的那份 → 第二次用户消息含 `(accepted: …)`；`MARK-ONE` 只出现一次（在当前文档里） | 结论标反 |
| S10 | 新对话：`ResetConversation` 后再生成 → 用户消息里没有 `Earlier requests` | — |
| S11 | 附上问题：`AWithProblems = True` 且文档问题列表有一条 (3,5) → 用户消息含 `line 3, col 5`；`False` → 不含 `Problems the editor reports` | 不看 `AWithProblems` |
| S12 | 停止：挂起模式的后端，`Generate` 后 `Stop` → 后端收到 `Cancel`；后端以 `aekCancelled` 结束 → `tasStopped`、`Sentence = rsTbAiCancelled`、之后能再 `Generate` | `Stop` 不转给后端 |
| S13 | 忙时拒绝：挂起中再 `Generate` → False，后端 `Start` 只调过一次 | — |
| S14 | 失败的说法：后端以 `aekAuth`（401）结束 → `tasFailed`、`Sentence` 以 `rsTbAiAuth` 的格式开头 | — |
| S15 | 没改：回答块与当前文档相同（只差行尾 CRLF / LF）→ `HasCandidate = False`、`Sentence = rsTbAiNoChange` | 比较前不统一行尾 |
| S16 | `TbExtractCodeBlock` 表：`` 'x'#10'```tycss'#10'a'#10'```' `` → `a`；`` '```css'#10'b'#10'```' `` → `b`；两个块 `` ```css `` 与 `` ```tycss `` → 取 tycss 那个；一个无标签块 → 它；两个无标签块 → 长的；`` '```tycss'#10'a' ``（没闭合）→ False、`ATruncated`；CRLF 写的同样；没有块 → False | 选第一个块而不看标签 |
| S17 | 真后端接线（一条集成）：`TTbClientBackend` + `TTbFakeHttpServer`（OpenAI 形状，回答含合法块，分块发）→ `CheckSynchronize` 循环等 `OnFinished`（10 秒上限）→ `tasDone`、`Requests = 1`；`OnStreamed` 在主线程（线程 ID）；释放 session 之后再 `CheckSynchronize(50)` 不 AV | `TTbClientBackend` 的 `OnDelta` 直接在工作线程里调（线程 ID 不对） |
| S18 | 系统提示：`TbSystemPrompt` 以 `cRules` 开头、含 `TbReferenceText`、含 ```` ```tycss ```` | — |

- [ ] **Step 6: 注册与提交**：uses 加 `test.themebuilder.aisession`。`feat(themebuilder): one AI generation -- the prompt, the conversation, the code block, the checks and two rounds of feedback` + Co-Authored-By。

---

### Task 10: 预览试看、对比窗口

**Files:**
- Modify: `tools/themebuilder/tbpreview.pas`（试看）、`tools/themebuilder/tbeditorlook.pas`（三种行底色）
- Create: `tools/themebuilder/tbcompareform.pas`、`tbcompareform.lfm`、`tests/test.themebuilder.compare.pas`（suite `TTbCompareTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`（`<Units>` 加 `tbcompareform.pas`，带 `<ComponentName Value="TbCompareForm"/>`、`<HasResources Value="True"/>`、`<ResourceBaseClass Value="Form"/>`）、`tests/tytests.lpr`

- [ ] **Step 1: 预览试看**（`tbpreview.pas`；字段 `FInTrial: Boolean`、`FTrialGoodText`、`FTrialGoodDir`、`FTrialModeError: string`；单元头注释补一段「试看」）：

```pascal
function TTbPreviewFrame.BeginTrial(const AText, ABaseDir: string; out AError: string): Boolean;
begin
  if not FInTrial then
  begin
    { what the editor's document left here; EndTrial puts exactly this back }
    FTrialGoodText := FGoodText;
    FTrialGoodDir := FGoodDir;
    FTrialModeError := FModeError;
    FInTrial := True;
  end;
  Result := LoadDocument(AText, ABaseDir, AError);
  if not Result then
    EndTrial;                       { refused: the preview shows the editor's version again }
end;

procedure TTbPreviewFrame.EndTrial;
var
  err: string;
begin
  if not FInTrial then Exit;
  FInTrial := False;
  LoadDocument(FTrialGoodText, FTrialGoodDir, err);
  FModeError := FTrialModeError;   { LoadDocument cleared it: the text changed twice }
  UpdateModeNote;
end;
```

- [ ] **Step 2: 编辑器配色加三种行底色**（`tbeditorlook.pas`）：`TTbEditorColors` 加 `AddedLine, RemovedLine, FillerLine: TColor`；`TbEditorColors` 里 `AddedLine := TyColorToLCL(TyMix(bg, success, 18))`（`--success`，取不到用文字色）、`RemovedLine := TyMix(bg, danger, 18)`（与 `ErrorLine` 同源，但单独一个字段）、`FillerLine := Gutter`（`--surface-chrome`）。单元头注释的表补三行。
- [ ] **Step 3: `.lfm`**（`object TbCompareForm: TTbCompareForm`，`TitleBar = Bar`，宽 1100 高 640，`Position = poOwnerFormCenter`，`OnCreate` / `OnDestroy` / `OnClose` / `OnKeyDown`（Esc = 放弃），`KeyPreview = True`）：
  - `Surface: TTyFormSurface`（`alClient`）
    - `Bar: TTyTitleBar`（`alTop`，`Caption = 'Compare the AI''s version'`）
    - `Summary: TTyLabel`（`alTop`，内距照主窗体状态栏的令牌；文字代码里设）
    - `Buttons: TTyPanel`（`alBottom`，高 44）：`TrialCheck: TTyCheckBox`（左，`Caption = 'Try it in the preview'`，`OnChange = TrialCheckChange`）、`BtnDiscard: TTyButton`（右，`Caption = 'Discard'`，`ModalResult = 2`）、`BtnAccept: TTyButton`（右，`Caption = 'Accept'`，`StyleClass = 'primary'`，`OnClick = BtnAcceptClick`，`ModalResult = 1`）——按钮按内容 AutoSize、一个锚在另一个左边（1 期「换肤会撑破写死的宽度」）
    - `IssuesList: TTyListBox`（`alBottom`，高 96，没有问题时 `Visible = False`）
    - `Headers: TTyPanel`（`alTop`）：`LeftTitle: TTyLabel`（`'Now'`）、`RightTitle: TTyLabel`（`'AI''s version'`）——各占一半宽（`OnResize` 里设）
    - `LeftEdit: TSynEdit`（`alLeft`，`ReadOnly = True`，`Gutter.Visible = False`，`OnSpecialLineMarkup = EditSpecialLineMarkup`，`OnStatusChange = EditStatusChange`）、`Splitter: TTySplitter`（`alLeft`）、`RightEdit: TSynEdit`（`alClient`，同上）
- [ ] **Step 4: `tbcompareform.pas`**：
  - `FormCreate`：两个 SynEdit 各配一个 `TTyCssEditKit`（`Create(Self)`，`AutoComplete := False`、`FormatOnLineLeave := False`，再 `Attach(编辑框, True)`——高亮与编辑器同一套，只读框不要补全）；保留光标（便于选中复制）。
  - `Prepare(ABase, ACandidate, AIssues, ALook)`：`TbSplitLines` 两边、`FRows := TbDiffLines`；按行填两边：每行 `Same` / `Changed` 两边都填对应原文；`Removed` 左填原文、右填空行（空位）；`Added` 右填、左空位；记两张表「编辑器行号 → 行种类」（`FLeftKinds`、`FRightKinds`：`Same` / `Changed` / `Removed`（左）/ `Added`（右）/ 空位用 `tdkSame` 之外的一个内部标记，`RowKindAt` 对空位返回对面那一边的种类）；`TbApplyEditorColors` 到两边；`Summary.Caption := Format(rsTbCompareSummary, [TbDiffChangeCount(FRows), 剩余错误数])`（`'%d changes. Problems left: %d.'`）；`IssuesList` 填 `TbAiIssueCaption`（`'12:5  text'` / `'—  text'`，照 `TbProblemCaption`）；`BtnAccept.Enabled := True`（有问题也能接受——spec「由用户决定」）。
  - `EditSpecialLineMarkup(Sender, Line, var Special, Markup)`：按那一边的表：左 `Removed` / `Changed` → `RemovedLine`；右 `Added` / `Changed` → `AddedLine`；空位 → `FillerLine`；其余不特殊。
  - `EditStatusChange(Sender, Changes)`：`scTopLine in Changes` 且不在同步中 → 另一边 `TopLine := (Sender as TSynEdit).TopLine`（`FSyncing` 防回弹）。
  - `TrialCheckChange`：`FOnTrial(Self, TrialCheck.Checked, err)`；`err <> ''` → 复选框退回不勾（挡住回调）、`Summary` 后面接 `Format(rsTbCompareTrialFailed, [err])`（`'The preview cannot show it: %s'`）。
  - `BtnAcceptClick`：`FAccepted := True`（`ModalResult` 由 `.lfm` 关窗）。
  - `FormClose`：试看开着 → `FOnTrial(Self, False, err)`（地雷 34）。`FormDestroy`：同样兜一次（测试不显示窗体、直接 `Free`）。
- [ ] **Step 5: 判据测试**（`TTbCompareTests`；`TTbCompareForm.Create(nil)`，不显示；配色用 `TbEditorColors(TyDefaultController)`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| V1 | 两边对齐：`Prepare('a|b|c', 'a|x|c|d')` → 两边行数相同（= 行数 4）；左第 2 行 `b`、右第 2 行 `x`；右第 4 行 `d`、左第 4 行为空（空位）；`RowKindAt(False, 2) = tdkChanged`、`RowKindAt(True, 4) = tdkAdded` | 空位不填（两边行数不同） |
| V2 | 着色：`EditSpecialLineMarkup(RightEdit, 4, …)` → `Special` 且背景 = `AddedLine`；左第 2 行 → `RemovedLine`；第 1 行 → 不特殊；**先证明** `AddedLine <> RemovedLine <> 底色` | 右边改动行用 `RemovedLine` |
| V3 | 滚动跟随：左边 `TopLine := 3`，调 `EditStatusChange(LeftEdit, [scTopLine])` → 右边 `TopLine = 3`（若无句柄的 SynEdit 设不了 `TopLine`——行数少于一屏——就用 200 行的文本） | 不同步 |
| V4 | 试看接线：`OnTrial` 挂一个记录器；`TrialCheck.Checked := True` → 记录 (True)；`Free` 窗体 → 再记录 (False) | `FormDestroy` 不收试看 |
| V5 | 试看被拒：记录器返回 `err = 'x'` → 复选框回到不勾、`Summary` 含 `x`、记录器只被调一次（回退时不再触发） | 回退时不挡回调（调两次） |
| V6 | 剩余问题：`Prepare` 带一条错误 → `IssuesList.Visible`、`Summary` 含 `1`；不带 → 不可见 | — |
| V7 | 预览试看（`TTbPreviewFrame` 单独建）：先 `LoadDocument(标记文档 A：按钮背景 $123456)`；**先证明**此时预览按钮背景是 `$123456`；`BeginTrial(文档 B：$654321)` → 背景 `$654321`、`InTrial`；`EndTrial` → 回到 `$123456`、`InTrial = False` | `EndTrial` 不重新载入（背景停在 `$654321`） |
| V8 | 试看不丢「切模式被拒」：A 在暗色下被拒（`SetDark(True)` 失败，`ModeError <> ''`）；`BeginTrial(B)` / `EndTrial` 之后 `ModeError` 与之前相同 | `EndTrial` 不还原 `FModeError` |
| V9 | 试看被拒：`BeginTrial(坏文本)` → False、`InTrial = False`、背景仍是 A 的 | 被拒时不 `EndTrial`（`InTrial` 留 True） |

- [ ] **Step 6: 注册与提交**：uses 加 `test.themebuilder.compare`。`feat(themebuilder): the side-by-side comparison of the AI's version, and trying it in the preview` + Co-Authored-By。

---

### Task 11: AI 设置对话框

**Files:**
- Create: `tools/themebuilder/tbaisettingsform.pas`、`tbaisettingsform.lfm`
- Modify: `tests/test.themebuilder.compare.pas`（suite `TTbAiSettingsFormTests`）、`tools/themebuilder/themebuilder.lpi`

- [ ] **Step 1: `.lfm`**（`object TbAiSettingsForm: TTbAiSettingsForm`，`TitleBar = Bar`，宽 760 高 520，`Position = poOwnerFormCenter`）：
  - `Surface` / `Bar`（`Caption = 'AI settings'`）
  - 左栏 `LeftPane: TTyPanel`（`alLeft`，宽 220）：`ProfileList: TTyListBox`（`alClient`，`OnClick = ProfileListClick`）、底部一行 `BtnAdd: TTyDropDownButton`（`Caption = 'Add'`，`DropDownMenu = PresetMenu`）与 `BtnRemove: TTyButton`（`Caption = 'Remove'`）
  - 右栏 `Fields: TTyPanel`（`alClient`），自上而下（每项一个 `TTyLabel` + 控件，`AutoSize` 的标签、控件锚定在标签右边）：`EdtName`（`'Name'`）、`CmbFormat: TTyComboBox`（`'Format'`，条目代码里填）、`EdtUrl`（`'Address'`）、`EdtModel`（`'Model'`）、`EdtKey`（`'Key'`，`PasswordChar = '•'`，`TextHint = 'Not needed for a local model'`）、`SpnMaxOutput: TTySpinEdit`（`'Maximum output (tokens, 0 = not sent)'`，0..1000000）、`SpnTimeout: TTySpinEdit`（`'Timeout (seconds without data)'`，5..3600）、`LblHint: TTyLabel`（`WordWrap`，Ollama / 本机地址时显示 `rsTbAiOllamaHint`）；`BtnTest: TTyButton`（`'Test connection'`）+ `LblTest: TTyLabel`（`WordWrap`）；底部 `LblPrivacy: TTyLabel`（`WordWrap`，文字代码里设，见下）
  - 底栏：`BtnOk`（`'OK'`，`StyleClass = 'primary'`，`ModalResult = 1`，`OnClick = BtnOkClick`）、`BtnCancel`（`'Cancel'`，`ModalResult = 2`）
  - 非可视：`PresetMenu: TTyPopupMenu`（五项：`'OpenAI'`、`'DeepSeek'`、`'Anthropic'`、`'Local (Ollama)'`、`'Custom'`，`Tag` 0..4，`OnClick = PresetClick`）、`TestTimer: TTimer`（100 ms，`Enabled = False`，`OnTimer = TestTimerTimer`）
- [ ] **Step 2: `tbaisettingsform.pas`**：
  - `Prepare(ASettings)`：把配置**复制**进 `FWork: array of TTbAiProfile` 与 `FKeys: TStringList`（id → 密钥）；填 `ProfileList`；选中当前那个；`CmbFormat.Items` = `rsTbAiFormatOpenAI`（`'OpenAI-compatible'`）/ `rsTbAiFormatAnthropic`（`'Anthropic'`）；`LblPrivacy.Caption := rsTbAiPrivacy + ' ' + {$IFDEF MSWINDOWS}rsTbAiKeyStoreWin{$ELSE}rsTbAiKeyStoreUnix{$ENDIF}`：`rsTbAiPrivacy = 'The theme text and your descriptions are sent to the service set here. A local model (an address on localhost) keeps them on this computer.'`、`rsTbAiKeyStoreWin = 'Keys are stored encrypted for your Windows user.'`、`rsTbAiKeyStoreUnix = 'Keys are stored in a file only you can read.'`。
  - 字段改动随时写回 `FWork[当前]`（各控件 `OnChange`，`FUpdating` 挡住代码里的同步，2 期地雷 22）；`EdtUrl` 改了刷新 `LblHint`（`TbIsLoopbackHost(主机)` 时显示 `rsTbAiOllamaHint`：`'Ollama keeps only a short context by default and cuts the start of a long request without saying so. Set OLLAMA_CONTEXT_LENGTH=32768 (or more) before starting Ollama.'`）；`CmbFormat` 改成 Anthropic 且 `MaxOutput = 0` → 自动填 ~~64000~~ 32000（开工核对第 3 条）。
  - `AddPreset` / `PresetClick`：`TbPresetProfile` 追加、选中、`EdtKey` 聚焦（`CanSetFocus`）。`BtnRemove`：问一次（借主窗体的 `Ask`，经 `OnAsk: TTbAskEvent`，2 期的类型）再删。
  - `StartTest`：当前配置 + `FKeys` 里的密钥建一个 `TTbClientBackend`，`OnDelta` / `OnDone` 挂上；系统提示 `'Reply with the single word OK.'`、消息 `[user('ping')]`；`LblTest.Caption := rsTbAiTesting`（`'Testing...'`）；第一个 `tspText` 或 `tspThinking` 到达就算连上了：`Cancel` 后端、`LblTest := Format(rsTbAiTestOk, [Model])`（`'Connected: %s is answering.'`）；`OnDone` 先到（没有片段）：`aekNone` → 同样成功，否则 `LblTest := TbAiErrorSentence(...)`。`Testing` = 后端还在跑。窗体关闭 / 析构时有测试在跑就 `Cancel` + 释放（地雷 29）。
  - `Commit`：Anthropic 且 `MaxOutput <= 0` 的配置拒绝提交（`LblTest := rsTbAiNeedMaxOutput`，`'Anthropic needs a maximum output length above 0.'`，`ModalResult := mrNone`）；否则把 `FWork` 全部 `Put` 回设置、删掉列表里没有了的、写密钥、`CurrentId` = 选中的、`Save`。`BtnOkClick` = `Commit`。
- [ ] **Step 3: 判据测试**（`TTbAiSettingsFormTests`；设置文件在临时目录；窗体不显示）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| G1 | 预置：`AddPreset(tapAnthropic)` → 列表多一项、选中它、`CmbFormat.ItemIndex = 1`、`EdtUrl.Text = 'https://api.anthropic.com/v1'`、`SpnMaxOutput.Value = 32000`（开工核对第 3 条） | — |
| G2 | 改字段 + 密钥 + `Commit` → 另建 `TTbAiSettings` `Load` 读回相同；`Cancel`（不 `Commit`）的改动不落盘（先证明改过） | 字段改动直接写进真设置（不 `Commit` 也落盘） |
| G3 | 本机提示：地址改成 `http://localhost:11434/v1` → `LblHint.Visible`；改成 `https://api.openai.com/v1` → 不可见 | — |
| G4 | Anthropic 的最大输出：格式切到 Anthropic 且原值 0 → 自动 32000；手动改回 0 再 `Commit` → 设置没变、`LblTest` 是 `rsTbAiNeedMaxOutput` | 不拦 |
| G5 | 测试连接成功：配置指向 `TTbFakeHttpServer`（OpenAI 形状的流，第一块之后 `FakeHold`）→ `StartTest`，`CheckSynchronize` 等到 `Testing = False`（≤ 5 秒）→ `TestText` 以 `Connected` 开头；服务端收到的正文里 `"content":"ping"`；**测试结束服务端的连接被取消了**（服务端的 Hold 被客户端断开：服务端记到的连接已关闭——`TTbFakeHttpServer` 加一个 `ClosedByPeer` 计数） | 连上之后不 `Cancel`（要等到空闲超时，用例超时失败） |
| G6 | 测试连接失败：401 → `TestText` 以 `rsTbAiAuth` 的格式开头；不含密钥 | — |
| G7 | 隐私说明：`LblPrivacy.Caption` 含 `rsTbAiPrivacy` 与本平台那一句 | 不显示 |
| G8 | 析构时有测试在跑：`StartTest`（服务端 Hold、不回第一块）后立刻 `Free` → 不挂、之后 `CheckSynchronize(50)` 不 AV | 析构不取消、不等线程 |

- [ ] **Step 4: 提交**：`feat(themebuilder): the AI settings -- profiles from presets, the key, a connection test and what gets sent where` + Co-Authored-By。

---

### Task 12: AI 页与主窗体接线

**Files:**
- Create: `tools/themebuilder/tbaiframe.pas`、`tbaiframe.lfm`
- Modify: `tools/themebuilder/tbmain.pas`、`tbmain.lfm`、`tools/themebuilder/themebuilder.lpi`、`tests/test.themebuilder.main.pas`

- [ ] **Step 1: `tbaiframe.lfm`**（`object AiFrame: TTbAiFrame`；开工前问题一第 10 条的布局，自上而下 `alTop`，输出框 `alClient`）：`TopRow: TTyPanel`（`ProfileCombo: TTyComboBox`（`alClient`，`OnChange = ProfileComboChange`）+ `BtnSettings: TTySpeedButton`（`alRight`，`Images = AiIcons`，`ImageName = 'settings'`，`Hint = 'AI settings'`，`ShowHint = True`））；非可视 `AiIcons: TTyLucideImageList`（`settings`）；`LblDescribe: TTyLabel`（`WordWrap`，`'Describe the theme or the change, for example: warm colours, rounder corners.'`）；`EdtPrompt: TTyMemo`（高 72，`WordWrap`）；`ChkProblems: TTyCheckBox`（`'Include the problem list'`）；`ButtonRow: TTyPanel`（`BtnGenerate: TTyButton`（`'Generate'`，`StyleClass = 'primary'`）、`BtnStop: TTyButton`（`'Stop'`，`Enabled = False`）、`BtnNewChat: TTyButton`（`'New conversation'`，`StyleClass = 'ghost'`），按内容 AutoSize、依次左锚）；`LblStatus: TTyLabel`（`WordWrap`）；`LblConversation: TTyLabel`；`BottomRow: TTyPanel`（`alBottom`：`LblSentTo: TTyLabel`（`WordWrap`）、`BtnShowCompare: TTyButton`（`'Show the comparison...'`，`Enabled = False`））；`OutputMemo: TTyMemo`（`alClient`，`ReadOnly = True`，`WordWrap = True`）；非可视 `FlushTimer: TTimer`（150 ms，`Enabled = False`）。
- [ ] **Step 2: `tbaiframe.pas`**：
  - `Setup(ASettings, ABaseVars)`：`FSettings := ASettings`；`FSession.BaseVars := ABaseVars`；`FAvailable := TbTransportAvailable(FUnavailable)`；`RefreshProfiles`；`UpdateButtons`。
  - `RefreshProfiles`：`ProfileCombo.Items` = 每个配置的 `Name`（`FUpdating` 挡住），选中当前；没有配置 → `LblStatus := rsTbAiNoProfile`（`'Add a service in the AI settings first.'`）；有 → 按当前配置建 `TTbClientBackend`（`FSession.Backend := …`，密钥 `FSettings.GetKey`）；`LblSentTo := Format(rsTbAiSentTo, [TbHostOf(BaseUrl)])`（`'Sent to: %s'`）。
  - `ProfileComboChange`：`FSettings.CurrentId := …; FSettings.Save; RefreshProfiles`。
  - `GenerateClick`：不可用（`FAvailable = False`）→ 状态行 `Format(rsTbAiNoTransport, [FUnavailable])`，返回；`Trim(EdtPrompt.Text) = ''` → `rsTbAiDescribe`（`'Describe the theme or the change first.'`），返回；`doc := FOnGetDocument()`；`OutputMemo.Clear`；`FSession.Generate(EdtPrompt.Text, doc, ChkProblems.Checked)`；成功则 `UpdateButtons`。
  - `StopClick` → `FSession.Stop`。`BtnNewChatClick` → `FSession.ResetConversation`、更新 `LblConversation`。`BtnSettingsClick` → `FOnSettings(Self)`。`BtnShowCompareClick` → `FOnCandidate(Self)`。
  - Session 事件：`OnStage` → 状态行按阶段（`tasSending`：`Format(rsTbAiSending, [主机])`；`tasThinking`：`rsTbAiThinking`；`tasReceiving`：`Format(rsTbAiReceiving, [行数])`；`tasChecking`：`rsTbAiChecking`；`tasRetrying` 与结束各阶段：`FSession.Outcome.Sentence` 或 session 给的那句）；`OnStreamed` → 只置脏标志并启动 `FlushTimer`；`FlushTimerTimer` → 把 `FSession.Streamed` 里新增的部分 `OutputMemo.Append`（记已显示的长度；回喂开始新一轮时 `Streamed` 清空——显示一行分隔 `'— ' + rsTbAiRound + ' —'`（`'Round %d'`）再接着显示），并把光标移到末尾；`OnFinished` → 刷一次输出、`UpdateButtons`、`LblConversation := Format(rsTbAiConversation, [History.Count])`（`'This conversation: %d requests.'`）；`Outcome.HasCandidate` → `BtnShowCompare.Enabled := True` 并 `FOnCandidate(Self)`（自动弹对比，开工前问题一第 3 条）；失败而回答没有代码块 → 输出框里已经是原文（spec「原文给用户看」）。
  - `DocumentChanged(AHasErrors)`：`FSession.ResetConversation`；`BtnShowCompare.Enabled := False`；`FProblemsTouched := False`；`ChkProblems.Checked := AHasErrors`（挡住回调）。`ChkProblemsChange`（用户点的）→ `FProblemsTouched := True`。另有 `ProblemsChanged(AHasErrors)`：`not FProblemsTouched` 时 `ChkProblems.Checked := AHasErrors`（开工前问题一第 7 条）。
  - `UpdateButtons`：`BtnGenerate.Enabled := FAvailable and 有配置 and not 忙`；`BtnStop.Enabled := 忙`。
  - 析构：`FSession.Free`（它会停后端、等线程）。
- [ ] **Step 3: `tbmain.lfm`**：`SideBar` 里 `ProblemsWin` **之后**加 `AiWin: TTyToolWindow`（`Caption = 'AI'`、`ImageName = 'sparkles'`、`StripHint = 'AI'`），里面 `AiHost: TTyPanel`（`alClient`）；`Icons.Names` 加 `sparkles`。菜单 `MnuView` 里 `MnuProblems` 之后加 `MnuAi '&AI'`；`MnuViewSep2` 之后（覆盖检查那一组）加 `MnuAiSettings 'AI se&ttings...'`。
- [ ] **Step 4: `tbmain.pas`**：
  - `FormCreate`（种子面板之后、`NewMinimal` 之前）：

```pascal
  TbAiFilesFor(FSettings.FileName, aiIni, aiKeys);
  FAiSettings := TTbAiSettings.Create(aiIni, aiKeys);
  FAiSettings.Load;
  FAi := TTbAiFrame.Create(Self);
  FAi.Parent := AiHost;
  FAi.Align := alClient;
  FAi.OnGetDocument := @AiDocument;
  FAi.OnCandidate := @AiCandidate;
  FAi.OnSettings := @AiSettingsClick;
  FAi.Setup(FAiSettings, FBaseVars);
```

  - `FormDestroy` 开头：`if FAi <> nil then begin FAi.Session.Stop; FAi.OnGetDocument := nil; FAi.OnCandidate := nil; FAi.OnSettings := nil; end;`；`FPreview.EndTrial`；末尾 `FreeAndNil(FAiSettings)`（frame 是窗体的子组件，先于它被释放之前不再回调）。
  - `NewMinimal` / `NewFromBuiltin` / `OpenFile`（成功后）：`FAi.DocumentChanged(TbErrorCount(FProblems) > 0)`（在 `LoadEditor` 的 `RefreshNow` 之后）；`ShowProblems` 末尾：`FAi.ProblemsChanged(TbErrorCount(FProblems) > 0)`。**外部修改后的重新载入不清对话**（同一份文档）。
  - `AiDocument: TTbAiDocument`：`Text := Editor.Lines.Text; BaseDir := FDoc.BaseDir; Untitled := FDoc.Untitled; Problems := FProblems`。
  - `RefreshNow`：`if not FParseFailed then` 改成 `if not FParseFailed and not FPreview.InTrial then`（地雷 34；试看期间问题列表照常刷新，预览不动）。
  - `BuildCompareForm`：`o := FAi.Session.Outcome; Result := TTbCompareForm.Create(Self); Result.OnTrial := @CompareTrial; Result.Prepare(o.BaseText, o.Candidate, o.Issues, FLook);`。字段 `FTrialText := o.Candidate`。
  - `AiCandidate(Sender)`：`f := BuildCompareForm; try if (f.ShowModal = mrOk) and f.Accepted then AcceptCandidate(FAi.Session.Outcome.BaseText, FAi.Session.Outcome.Candidate) else FAi.Session.MarkLast(False); finally f.Free; end;`（关窗时 `FormClose` 已收试看；`Free` 再兜一次）。
  - `CompareTrial(Sender, AOn, out AError)`：`AError := ''`；`AOn` → `FPreview.BeginTrial(FTrialText, FDoc.BaseDir, AError)`；否则 `FPreview.EndTrial`；之后 `BuildProblems`（把预览的状态反映到列表——试看不改 lint）。
  - `AcceptCandidate(ABase, ACandidate): Boolean`：

```pascal
function TTbMainForm.AcceptCandidate(const ABase, ACandidate: string): Boolean;
var
  current: string;
begin
  Result := False;
  current := Editor.Lines.Text;
  { the editor changed after the request went out: say so, and replace what is there now }
  if TbNormalizeEol(current) <> TbNormalizeEol(ABase) then
    if Ask(rsTbAiEditedSince, [mbYes, mbNo], mtConfirmation) <> mrYes then
      Exit;
  Result := ApplyEdits(current, [TbWholeTextEdit(current, TbNormalizeEol(ACandidate))]);
  if Result then
  begin
    FAi.Session.MarkLast(True);
    SetStatus(rsTbAiAccepted);
  end;
end;
```

  （`rsTbAiEditedSince = 'The editor changed after this was generated. Accepting replaces those changes too. Accept?'`、`rsTbAiAccepted = 'Accepted the AI''s version. Ctrl+Z undoes it.'`；`Ask` 的第三个参数是 1 期期末加的消息类型，以实际签名为准。`TbWholeTextEdit` 返回的改动 `Start = Stop` 且 `Text = ''`（完全相同）时 `ApplyEdits` 什么都不做——session 那边已经把这种情况说成「没改」、不会走到这里。）
  - `BuildAiSettingsForm`：`Result := TTbAiSettingsForm.Create(Self); Result.OnAsk := @AskFor; Result.Prepare(FAiSettings);`（开工核对第 2 条：`Ask` 是三参的）。`AiSettingsClick` / `MnuAiSettingsClick`：`f := BuildAiSettingsForm; try if f.ShowModal = mrOk then FAi.RefreshProfiles; finally f.Free; end;`。`MnuAiClick` → `ShowSidePage(AiWin)`。
- [ ] **Step 5: 1 期测试跟着改**（`tests/test.themebuilder.main.pas`）：F1 的侧栏页数改为 3、`Windows[2] = AiWin`；F11 的 `cUnits` 加本期的单元（`ai/` 下的写相对路径），从磁盘问清单改为 `FindAllFiles(dir, '*.pas', True)`，每个文件按「相对 `tools/themebuilder/` 的路径、分隔符换成 `/`」在 `.lpi` 里找 `<Filename Value="…"/>`；F11 另查 `OtherUnitFiles` 含 `ai`；I3 的 `FindAllFiles(ToolDir, '*.pas', False)` 改为 `True`。
- [ ] **Step 6: 判据测试**（接着写 `TTbMainFormTests`；`SetUp` / `TearDown` 照 1 期，AI 配置文件随 `SettingsFileForTest` 落在临时目录；需要后端的用例在测试里把 `Ai.Session.Backend` 换成 `tests/tbaitesthelp.pas` 的 `TScriptedBackend`（Task 9）；需要配置的用例先 `AiSettings.Put(TbPresetProfile(tapCustom))` 并 `Ai.RefreshProfiles`，再换后端——`RefreshProfiles` 会按配置建真后端，换的顺序反了就被覆盖）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| M1 | 建好：`SideBar.WindowCount = 3`、`Windows[2] = AiWin`；`Ai.Parent = AiHost`；没有配置时 `Ai.BtnGenerate.Enabled = False`、状态行 = `rsTbAiNoProfile`；`AiSettings.IniFile` 在临时目录里 | `FormCreate` 不建 frame |
| M2 | 生成 → 对比 → 接受 → 一次撤销：放一个配置、换上假后端（回答 = 极简模板把亮色 `--accent` 改成 `#ABCDEF`）；`OnCandidate` 换成测试的处理（不 `ShowModal`：`f := BuildCompareForm; f.BtnAcceptClick(nil); AcceptCandidate(...)`）；`Ai.EdtPrompt.Text := 'blue'; Ai.GenerateClick(nil)` → 编辑器文本里亮色 `--accent: #ABCDEF;`；预览主按钮背景 = `$ABCDEF`；`Editor.Undo` **一次** → 文本 = 极简模板（行尾统一后比） | `AcceptCandidate` 用 `Editor.Lines.Text :=`（撤销一次回不去） |
| M3 | 接受只换改了的行：生成之前把光标放在第 3 行第 2 列（`Editor.LogicalCaretXY := Point(2, 3)`），候选只改亮色 `--accent` 那一行（在第 3 行之后）→ 接受后光标仍是 (2, 3)；**先证明**整篇替换会挪光标：同样的文本直接 `ApplyEdits(text, [TbEdit(1, Length(text) + 1 - Length(LineEnding), 候选去掉末尾换行)])` 之后光标不在 (2, 3) | `TbWholeTextEdit` 换成整篇（`Start = 1`） |
| M4 | 生成之后编辑器改过：生成完、接受之前往编辑器加一行；`PromptAnswerForTest := mrNo` → `AcceptCandidate = False`、文本不变、`LastAsk = rsTbAiEditedSince`；`mrYes` → 换成候选、`Undo` 一次回到「加了一行」的样子 | 不比较 `ABase` |
| M5 | 试看与刷新：`CompareTrial(nil, True, err)`（候选 = 背景 `$654321`）→ 预览背景 `$654321`；编辑器打一个字、`RefreshNow` → 预览**仍是** `$654321`；`CompareTrial(nil, False, err)` → 回到编辑器文本的样子 | `RefreshNow` 不看 `InTrial` |
| M6 | 新文档清对话：生成一次（`History.Count = 1`）→ `NewMinimal` → `History.Count = 0`；外部修改重载（1 期 F12 的做法）→ 不清 | `DocumentChanged` 没接 |
| M7 | 附上问题自动勾选：打开一份有解析错误的文件 → `Ai.ChkProblems.Checked`；改好、`RefreshNow` → 不勾；用户手动勾上后再改坏改好 → 保持用户的选择 | `ProblemsChanged` 没接 |
| M8 | 放弃：对比窗口不接受（直接 `Free`）→ 文本不变、`History.Objects[0] = 2`（没用） | 放弃时不 `MarkLast(False)` |
| M9 | 设置窗体接线：`BuildAiSettingsForm` → `AddPreset(tapOllama)`、`Commit` → `Ai.ProfileCombo.Items.Count = 1`（经 `RefreshProfiles`）、`Ai.LblSentTo` 含 `localhost` | 关设置后不 `RefreshProfiles` |
| M10 | 停止接线：挂起模式的假后端，`GenerateClick` 后 `Ai.BtnStop.Enabled`；`Ai.StopClick(nil)` → 后端收到 `Cancel`；后端以 `aekCancelled` 结束 → 状态行 `rsTbAiCancelled`、`BtnGenerate.Enabled` | — |
| M11 | 销毁时在生成：挂起模式开始生成后 `Free` 主窗体 → 不 AV、后端收到 `Cancel`；之后 `CheckSynchronize(50)` 不 AV | `FormDestroy` 不停 session |
| M12 | 流式显示：假后端分 30 个片段送 600 行 → `FlushTimerTimer` 手动调几次之后 `OutputMemo.Lines.Count >= 600`；`OutputMemo.Append` 的总耗时打印（Task 15 记进签收；> 500 ms 写进签收的遗留） | `OnStreamed` 没接（输出框空） |

- [ ] **Step 7: 提交**：`feat(themebuilder): the AI page in the side bar -- generate, stop, compare, try and accept in one undo step` + Co-Authored-By。

---

### Task 13: 中英 `.po`

**Files:**
- Modify: `tools/themebuilder/languages/themebuilder.zh_CN.po`、`themebuilder.zh_CN.json`

- [ ] **Step 1: `.lfm` 条目**：照 1 期 Task 11 Step 2 的写法，加三个新 `.lfm`（根类名 `ttbcompareform`、`ttbaisettingsform`、`ttbaiframe`）与 `tbmain.lfm` 新增组件（`ttbmainform.aiwin.caption` / `.striphint`、`mnuai`、`mnuaisettings`）的每个 `Caption`、`Hint`、`TextHint`、`StripHint`、`Text`。**译文**（照原生语感，仓库记忆「文档要原生语感」）：Compare the AI's version 对比 AI 的版本、Now 现在、AI's version AI 的版本、Try it in the preview 在预览里试看、Accept 接受、Discard 放弃、AI settings AI 设置、Add 添加、Remove 删除、Name 名称、Format 格式、Address 地址、Model 模型、Key 密钥、Not needed for a local model 本地模型不需要、Maximum output (tokens, 0 = not sent) 最大输出（token，0 = 不发送）、Timeout (seconds without data) 超时（多少秒收不到数据）、Test connection 测试连接、OK 确定、Cancel 取消、Local (Ollama) 本地（Ollama）、Custom 自定义、Describe the theme or the change, for example: warm colours, rounder corners. 描述想要的主题或改动，例如：暖色调，圆角大一点。、Include the problem list 附上问题列表、Generate 生成、Stop 停止、New conversation 新对话、Show the comparison... 查看对比…、AI 不译（`msgstr` 也写 `AI`，不能空）；`OpenAI`、`DeepSeek`、`Anthropic` 同样原样。
- [ ] **Step 2: 代码条目的译文**（`.json`，键 `<小写单元名>.<小写 rs 名>`；`ai/` 下的单元同样只用单元名）：Task 2、5、6、9、10、11、12 的全部 resourcestring。例：`tbhttp.rstbainocurl`: `"找不到 libcurl（试过 %s）。装上 libcurl（例如 libcurl4 包）就能用 AI。"`、`tbaiclient.rstbaicancelled`: `"已停止。"`、`tbaiclient.rstbaicannotconnect`: `"连不上 %s。服务开着吗？或者需要代理？"`、`tbaiclient.rstbaitimeout`: `"%s 已经 %d 秒没有回应。"`、`tbaiclient.rstbaiauth`: `"密钥被拒绝（%d）。请检查 AI 设置里的密钥。"`、`tbaiclient.rstbairatelimit`: `"请求太多（429）。等一会儿再试。"`、`tbaiclient.rstbaitruncated`: `"回答到了最大输出长度被截断了。请在 AI 设置里调大。"`、`tbaiclient.rstbaiservicesays`: `"（%s）"`、`tbaisession.rstbainoblock`: `"回答里没有 tycss 代码块，原文在下面。"`、`tbaisession.rstbairetrying`: `"发现 %d 个问题，正在请模型改（第 %d 次，最多 %d 次）……"`、`tbaisession.rstbaithinking`: `"模型在思考……"`、`tbaisession.rstbaimodeprobe`: `"%s模式下：%s"`、`tbaisettings.rstbaipresetlocal`: `"本地（Ollama）"`、`tbaisettingsform.rstbaiprivacy`: `"主题文本和你的描述会发给这里设置的服务。本地模型（localhost 上的地址）不会离开这台电脑。"`、`tbaisettingsform.rstbaiollamahint`: `"Ollama 默认的上下文很短，请求太长时会悄悄截掉开头。启动 Ollama 前先设 OLLAMA_CONTEXT_LENGTH=32768（或更大）。"`、`tbmain.rstbaieditedsince`: `"生成之后编辑器里又改过。接受会把这些改动一起替换掉。接受吗？"`、`tbmain.rstbaiaccepted`: `"已接受 AI 的版本。Ctrl+Z 可以撤回。"`……占位符个数与顺序与英文一致（`%s模式下` 的 `%s` 填的是 1 期已有的「亮色 / 暗色」译文，前面不加空格）。代码条目由 Task 15 编译后跑脚本并进 `.po`。
- [ ] **Step 3: 提交**：`i18n(themebuilder): Chinese for the AI page, its settings and the comparison` + Co-Authored-By。

---

### Task 14: 工具的使用文档与 README

**Files:**
- Create: `docs/themebuilder.md`（中文）、`docs/themebuilder.en.md`（英文）
- Modify: `README.md`、`README.en.md`

1 期计划「不在本期」写明工具的使用文档与 README 在 3 期末一起写。照 `docs/themes.md` / `themes.en.md` 的体例与语气（仓库记忆「文档要原生语感」：不要翻译腔、不要 AI 味；中文是原文，英文另写、不逐句对译）。

- [ ] **Step 1: `docs/themebuilder.md`** 各节：这是什么（两三句，spec §1）；怎么编、在哪（`lazbuild -B tools/themebuilder/themebuilder.lpi`，三平台的 widgetset 参数；不用先装包）；界面一览（侧栏三页、编辑区、预览）；写主题（种子面板、问题列表、Ctrl+点击、覆盖检查——各一两段，指向 `docs/tycss-reference.md`）；保存与导出（换行符原样、主题包两种格式与 zip 的限制、代码片段）；**AI**：配一个服务（五种预置、密钥存哪、隐私：主题文本会发给配置的服务、本机模型不出本机）、本地模型（Ollama 的地址、`OLLAMA_CONTEXT_LENGTH`）、一次生成怎么走（流式、停止、自动检查与最多两次回喂、对比、试看、接受可撤销）、多轮怎么记、出错时那句话分别是什么意思、Linux / macOS 要 libcurl（`THEMEBUILDER_LIBCURL`）、代理（Windows 跟系统设置；Linux / macOS 读 `https_proxy` 等环境变量）；配置文件在哪（三平台路径）；已知限制（SynEdit 的滚动条与边框是系统的；AI 每次整份重写）。
- [ ] **Step 2: `docs/themebuilder.en.md`**：同样的节，英文写法。
- [ ] **Step 3: README**：`README.md` 与 `README.en.md` 里讲主题的那一节（`grep -n "tycss\|主题\|theme" README*.md` 找位置）加一两句与链接：「`tools/themebuilder` 是一个主题编辑器：边写边看预览，可以接大模型起草」。不加截图（验收后再说）。
- [ ] **Step 4: 自查与提交**：文档里每条操作路径与菜单名与 `.lfm` / `.po` 一致（中文文档用中文菜单名）；链接都能打开（相对路径）。

```bash
cd /d/Projects/ty-3.1 && git add docs/themebuilder.md docs/themebuilder.en.md README.md README.en.md && git commit -m "docs(themebuilder): how to use the theme builder, AI included; README points to it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: 收尾——编译、全量、WSL、按 spec 逐条核、集中变异、主控编包冒烟、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-10-01-theme-builder-design.md`（写回）、`tools/themebuilder/languages/themebuilder.zh_CN.po`（脚本补代码条目）
- 修复时按需改 Task 1–14 的文件

- [ ] **Step 1: 一次编译 + 本期 suite + 全量**：「跑测试的固定套路」。Expected：列出的 suite 全 0 / 0；全量 errors / failures 与 Task 0 的基线相同、总数 = 基线 + 本期新增。红了集中修，一个问题一个 `fix(themebuilder): ...` 提交；以 spec 与本计划的判据为准，不改判据迁就代码（判据本身错了的，改判据并在签收里写原因）。HTTP 类用例偶发超时的，先查是不是机器上同时在跑别的全量（1 期签收记过一次），单跑三次判定。
- [ ] **Step 2: WSL**：「跑测试的固定套路」里 WSL 那一行。三次 `exit=0`。用例数与加载的库名记进签收。编不过先看是不是哪个 `ai/` 单元引了 LCL（R9 应该已经红了）。
- [ ] **Step 3: 编工具、补 `.po`**：编工具命令（0 错、没有重编 SynEdit）；然后

```bash
cd /d/Projects/ty-3.1 && python scripts/example-rsj2po.py tools/themebuilder themebuilder tools/themebuilder/languages/themebuilder.zh_CN.json && python scripts/check-example-po.py . && python scripts/check-lfm-props.py && git status --short tools/themebuilder
```

Expected：`added=` 等于本期新增的 resourcestring 个数、没有 `FATAL`；两个检查通过；`git status` 只有 `.po` 变了。重编 tytests 再跑 `TTbMainFormTests`（I1–I3 这时才看得到新条目）。
- [ ] **Step 4: 量几个数**：精简参考的字节数与 token 估计（R6 打印的）；D8 的对比耗时；M12 的追加耗时；`TbSystemPrompt` + 极简模板 + 一句描述的请求体字节数，以及 `themes/auto.tycss` 当文档时的字节数（写进签收，并换算成 token 粗估，说明本地 8B 模型需要多大的上下文——spec §10 的下限）。
- [ ] **Step 5: 按 spec 逐条核代码，不看测试**：§7.1 每一句（多个配置、六个字段、五种预置、测试连接、隐私说明、DPAPI / 0600、不进日志与错误消息、两种代理）；§7.2 每一句（不发整份文档、参考的五样内容、来源是代码、守卫、四条规则、每次请求的三样（+ 问题）、多轮）；§7.3 五步；§7.4 每种错误各对应哪个 `aek*` 与哪句话、libcurl 缺失；§8 的 AI 一行（两种样本、分块与跨块、本机服务的五种情形、假模型、参考守卫）；§2 第 3、4、8 条；§10 的 libcurl 库名与「参考太长 / 太短」。逐条记「在哪一行实现 / 为什么不需要 / 与规格不符（写回）」。重点查接线（仓库记忆「建好没接线」）：frame 的三个事件、session 的三个事件、`TTbClientBackend` 的两个 `Queue`、对比窗口的 `OnTrial`、`RefreshNow` 的 `InTrial`、`DocumentChanged` / `ProblemsChanged` 的两处调用、两个新菜单项的 `OnClick`、设置窗体关闭后的 `RefreshProfiles`。
- [ ] **Step 6: 【主控执行】编包、冒烟、看一眼**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tools/themebuilder/themebuilder.lpi > /tmp/tb3-tool.txt 2>&1; tail -3 /tmp/tb3-tool.txt; git status --short
```

Expected：编过；`source/`、`designtime/` 下没有任何改动。然后：
1. `powershell -File scripts/smoke-launch-examples.ps1 -Dirs tools\themebuilder`：起得来、只有主窗体与应用窗口、没有 `#32770`。
2. 打开工具看一眼（不录）：侧栏第三页 AI → 设置里加一个 DeepSeek 预置（不填密钥）→ 测试连接看 401 那句话 → 关设置 → AI 页状态行。
3. **真实生成**（需要用户给一个密钥，或本机装了 Ollama——主控先问用户，用户不给就整项留给验收）：「暖色调，圆角大一点」→ 看流式、对比窗口、试看、接受、Ctrl+Z。密钥用完从设置里删掉。
4. 截图放 `docs/superpowers/plans/2026-10-01-themebuilder-acceptance-shots/`：`p3-ai-settings-win32.png`（设置对话框）；第 3 步做了真实生成的，再截 `p3-ai-page-win32.png`（AI 页带输出）与 `p3-compare-win32.png`（对比窗口），没做就这两张留给验收。Task 16 引用。
- [ ] **Step 7: 集中变异**（每条三拍，必须红；WSL 那几条在 WSL 里重编重跑）：H1、H2、H3、H5、H6、H7、H8、H9、H11、H12、W10、E2、E3、E4、E5、E6、E8、E9、E11、A1、A2、A3、A5、A7、A8、A9、A10、A12、C1、C3、C4、C7、C8、C13、C15、C17、K1、K2、K3、K4、K5、R1、R2、R3、R4、R6、R7、R8、R9、D2、D5、D6、D7、D8、D11、D12、S2、S3（两个方向）、S4、S5、S6、S7、S8、S9、S11、S12、S15、S16、S17、V1、V2、V3、V4、V5、V7、V8、V9、G2、G4、G5、G7、G8、M1、M2、M3、M4、M5、M6、M7、M8、M9、M11、M12。结果逐条记进签收（红 / 补强 / 等价 + 理由）；没红的先查改没改对地方、再查是不是「这条路走不到」，确实没红就当场补测试。
- [ ] **Step 8: 期末审查（主控派两个审查 agent）**：规格核对（Step 5 的记录对着 spec 再过一遍）+ 代码质量（`git diff <Task 0 的 HEAD>..HEAD`），重点：
  - 密钥：除请求头外不出现在任何字符串里；Windows ini 只有密文；Unix 文件 0600、新建时就是（地雷 28）。
  - 线程：工作线程里只有 HTTP 与拆分；所有 `Queue` 都有对应的 `RemoveQueuedEvents`；析构顺序（地雷 29）；WinHTTP 句柄只关一次（地雷 32）；libcurl 的变参类型（地雷 31）。
  - 流：事件跨块、CR 跨块、`[DONE]` / `message_stop` 才算完、截断与拒绝不当成功。
  - 生成：回喂恰好 ≤ 2 次、提示不回喂、试解析算错、多轮不发旧回答、新文档清对话。
  - 界面：试看任何关闭路径都还原、试看期间刷新不载入、接受一步撤销、编辑过先问；`.lfm` 规矩；SynEdit 之外没有裸 LCL 控件。
  - 审出来的问题修完回到 Step 1。
- [ ] **Step 9: 写回 spec 原处，标「实现期修正（3 期）」**，原文删除线保留。至少：状态行（3 期签收、三期都完成、待真机验收）；§2 第 3 条（预置与「最大输出 0 = 不发」）；§4 的单元名（`ai/tbhttp` / `tbhttpwin` / `tbhttpcurl` / `tbsse` / `tbaiformat` / `tbaiclient` / `tbaisettings` / `tbreference` / `tbaisession`，顶层 `tbdiff` / `tbcompareform` / `tbaisettingsform` / `tbaiframe`；`ureference.inc` 不存在了）；§6「SynEdit 是唯一的非 Ty 控件」（对比窗口也用，开工前问题一第 9 条的答复）；§7.1 超时的含义、密钥文件位置；§7.2 参考改为运行时拼、守卫是什么、实测的 token 数、提示用英文、多轮记到哪；§7.3 第 3 步多了试解析、对比窗口的形态、编辑过再接受先问；§7.4 每种错误的那句话（列表）；§8 AI 一行（样本手写、来源；WSL 跑 libcurl）；§10 libcurl 的库名候选与环境变量、macOS 变参的风险、Ollama 的上下文；开工前问题一的答复；「与规格不符之处」每一条。
- [ ] **Step 10: 签收记录写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、本期各 suite 条数与用时、WSL 的结果、Step 4 的数、变异结果、spec 写回的节号、计划外发现、遗留。

```bash
cd /d/Projects/ty-3.1 && git add docs/ tools/themebuilder/languages && git commit -m "docs(themebuilder): phase 3 sign-off; corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: 把 3 期的真机项追加进验收文档

**Files:**
- Modify: `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md`

照文档现有的形式与语气：

- [ ] **Step 1: 开头**：「现在只有 1 期的项……」之类说「还没做完」的句子改成「三期都做完了」。
- [ ] **Step 2: 「这是什么，做了什么」**：「3 期」那一行的「（待做）」换成一段：AI 页（配一个服务：OpenAI 兼容、Anthropic、本地 Ollama；用一句话描述，流式看到回答，可以停）；结果自动检查、有错最多请模型改两次；对比窗口左右并排、可以先在预览里试看，接受后 Ctrl+Z 一次就能撤回；出错用一句话说清；Linux / macOS 用系统的 libcurl，没有也不影响别的功能；库一处没改。3 期签收的头提交与全量条数。
- [ ] **Step 3: 「准备」**：加三条——AI 要一个服务的密钥（或本机的 Ollama：装好、`ollama pull` 一个模型、**先设 `OLLAMA_CONTEXT_LENGTH=32768` 再启动**）；Linux / macOS 确认有 libcurl（`ldconfig -p | grep libcurl`；macOS 自带）；AI 配置在设置文件旁边的 `themebuilder-ai.ini`（Linux / macOS 另有 `themebuilder-ai.keys`），想从头来就删掉。
- [ ] **Step 4: 「验收表」**：本计划末尾「3 期的真机验收项」C1–C20 接着 Task 0 记下的最后编号 N 往下编成 N+1…N+20，「期（原编号）」列写「3 期（C1）」……。
- [ ] **Step 5: 「按平台的项号」**：各平台一行里补上对应的项（照下表的「平台」列）。
- [ ] **Step 6: 「等你定的决定」**：加一小节「3 期开工前的问题」，从 Task 0 记下的 E(k+1) 编起，十一条（对应开工前问题一的 11 条）：是什么、选项、现在的做法（按 Task 0 的实际答复）、看哪一项、改哪里。「与规格不符、你可能想改的」补上本计划「与规格不符之处」里用户看得见的几条（多一道试解析、参考运行时拼、对比窗口用 SynEdit、OpenAI 默认不发最大输出、超时是空闲超时、提示用英文）。
- [ ] **Step 7: 「截图」**：列出 Task 15 Step 6 的截图及对应项号。
- [ ] **Step 8: 自查与提交**：项号连续；每一项都有「怎么操作」与「期望」；决定清单每条都有「看哪一项」。

```bash
cd /d/Projects/ty-3.1 && git add docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md docs/superpowers/plans/2026-10-01-themebuilder-acceptance-shots && git commit -m "docs(themebuilder): phase 3's checks and decisions on the acceptance sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 3 期做完能看到什么

- `tytests` 里本期十个 suite 全绿，1、2 期的 suite 照旧全绿：WinHTTP 打到本机服务的各种情形（流式真的是边收边交、断流、超时、取消、连不上、`localhost`）；SSE 在任意切块下事件不变；两种格式的样本解读正确；错误归类与那一句话、密钥洗掉；DPAPI 往返与篡改；参考与库的列表同步、片段守卫、例子能用；对比的行对齐与「只换改了的行」；回喂恰好两次、多轮不发旧回答；试看还原；接受一步撤销。
- WSL 里的控制台程序在 `libcurl.so.4` 与 `libcurl-gnutls.so.4` 上各跑一遍全过，找不到库时说得清。
- 工具里：侧栏第三页 AI；设置里五种预置；生成、停止、对比、试看、接受、Ctrl+Z。
- 库一个字节没动。

---

## 3 期的真机验收项（Task 16 写进验收文档，接在 2 期之后编号）

| # | 项 | 平台 | 怎么验 | 算过 |
|---|---|---|---|---|
| C1 | AI 页的样子 | Win32、GTK2、Cocoa | 第一次打开 AI 页（没有配置）；加一个配置后再看；换几个皮肤、中英文各看一次 | 没有配置时说「先在 AI 设置里添加一个服务」、生成按钮灰；配好后底部写「发送到：<主机>」；按钮不挤、文字不被截 |
| C2 | 设置与预置 | Win32、GTK2 | 依次添加五种预置，看各字段；改名、填密钥、确定；重启工具再打开 | 字段与预置表一致；本机地址时出现 Ollama 的上下文提示；重启后都在；隐私说明在 |
| C3 | 密钥怎么存 | Win32、GTK2、Cocoa | 填一个密钥后，Windows 打开 `themebuilder-ai.ini`；Linux / macOS `ls -l` 看 `themebuilder-ai.keys` 并打开 ini | Windows 的 ini 里看不到密钥原文；Linux / macOS 的密钥文件是 `-rw-------`，ini 里没有密钥 |
| C4 | 测试连接 | Win32 | 正确密钥测一次；改错一位再测；地址改成不存在的主机再测；拔网线（或关 Wi-Fi）再测 | 分别是「已连上」、「密钥被拒绝（401）」、「找不到主机」、「连不上 / 找不到主机」；没有一句里出现密钥 |
| C5 | OpenAI 兼容服务生成一次 | Win32 | 用 DeepSeek 或 OpenAI：极简模板，描述「暖色调，圆角大一点」 | 输出框里字一段段出来；结束自动弹对比；改动行左红右绿、两边滚动跟随；试看时预览换样、取消试看恢复；接受后编辑器变、Ctrl+Z 一次回去 |
| C6 | Anthropic 生成一次 | Win32 | 同上用 Anthropic | 先显示「模型在思考……」再出字；其余同上 |
| C7 | 本地模型 | Win32 或 Linux | 装 Ollama、`ollama pull` 一个 7–8B 的模型、设 `OLLAMA_CONTEXT_LENGTH=32768` 启动；配本地预置（不填密钥）生成一次；再不设上下文长度重启 Ollama 试一次 | 第一次能出结果（质量记下）；第二次的现象记下（多半是不照规则回答——说明文档里那句提示有用） |
| C8 | 多轮 | 任一 | 生成一次并接受；再说「再暗一点」；再生成一次但放弃，接着说「还是刚才那样，只把按钮改成圆的」；然后新建文档再生成 | 第二次接着第一次改；第三次模型知道上一次没用；新建后不记得之前的 |
| C9 | 停止 | 任一 | 生成到一半点「停止」 | 马上停、状态行「已停止」、输出保留、能再生成 |
| C10 | 回喂 | 任一 | 描述里故意要求「给按钮加 margin: 4px」 | 状态行出现「发现 N 个问题，正在请模型改（第 1 次，最多 2 次）」；最后对比窗口里没有 `margin`，或者底下列出剩下的问题 |
| C11 | 编辑过再接受 | 任一 | 生成期间在编辑器里改一行；生成完点接受 | 先问一句；选「否」不变；选「是」替换，Ctrl+Z 回到改过一行的样子 |
| C12 | 出错的说法 | Win32 | 超时设 5 秒用一个思考型模型；模型名写错；（有条件的话）连续快速生成触发 429 | 分别是「…秒没有回应」「地址或模型不对（404）」「请求太多（429）」；编辑器不受影响 |
| C13 | 代理 | Win32、GTK2 | Windows：系统设置里配一个代理（如公司代理或本机 Fiddler）再生成；Linux：`https_proxy=… ./themebuilder` 启动再生成；本地模型照常 | 走代理能用；本地模型不走代理 |
| C14 | Linux 的 libcurl | GTK2、Qt6 | 正常启动生成一次；再 `THEMEBUILDER_LIBCURL=/nonexistent ./themebuilder` 启动 | 第一次正常；第二次 AI 页说找不到 libcurl、试过哪些，生成按钮灰，编辑、预览、保存照常 |
| C15 | macOS | Cocoa（Apple 芯片） | 生成一次 | 正常出结果（这一项验 libcurl 的变参在 arm64 上是对的——开工前问题二第 4 条；不过就记下现象） |
| C16 | 中文 | Win32、GTK2 | 用中文描述，要求「在文件开头加一段中文注释说明配色」 | 中文注释原样进对比窗口与编辑器，保存后是 UTF-8 |
| C17 | 对比窗口的样子 | Win32、GTK2、Cocoa | 换几个编辑器外观（含暗色）看对比窗口；HiDPI 150% 看一次 | 两边配色跟编辑器一致、增删行底色看得清；不糊、不挤 |
| C18 | 关窗口时在生成 | Win32 | 生成中直接关工具 | 不卡、不报错 |
| C19 | 中英 | Win32、GTK2 | 中英文系统各看一遍 AI 页、设置、对比窗口 | 跟随系统语言；中文下没有英文漏网（OpenAI 等品牌名与 AI 本来不译） |
| C20 | 文档 | — | 读 `docs/themebuilder.md` 与 `.en.md` | 照着能把工具编出来、把 AI 配起来；读着不别扭 |

---

## 与规格不符之处（核实中发现，Task 15 写回）

1. spec §4 的 `ai/uhttp.pas` / `uaiclient.pas` / `uaisettings.pas` / `uaisession.pas` / `ureference.inc` 与 `udiff.pas` 改为 `tb` 前缀并拆开：`ai/tbhttp`、`tbhttpwin`、`tbhttpcurl`、`tbsse`、`tbaiformat`、`tbaiclient`、`tbaisettings`、`tbreference`、`tbaisession`；顶层 `tbdiff`、`tbcompareform`、`tbaisettingsform`、`tbaiframe`。
2. spec §7.2「构建时由脚本生成精简参考」：改为运行时从库的数组与内置默认主题拼出来，手写部分由片段守卫（核实记录 22）。没有 `.inc` 文件。
3. spec §7.3 第 3 步：校验多一道「每个模式试解析」，失败也回喂（开工前问题一第 5 条）。
4. spec §6「SynEdit 是唯一的非 Ty 控件」：对比窗口也用两个只读 SynEdit（开工前问题一第 9 条，需主控确认）。
5. spec §7.1「超时」：是空闲超时（多久收不到数据），连接另有 15 秒（第 2 条）。「最大输出长度」0 = 不发送（OpenAI 兼容格式），Anthropic 必须大于 0（第 1 条）。
6. spec 未提：发给模型的文字用英文（第 8 条）；生成之后编辑器改过再接受会先问（第 4 条）；「服务没按流式回答」也接受；Linux / macOS 可用 `THEMEBUILDER_LIBCURL` 指定库（第 11 条）；本地地址不走代理；接受时只替换改了的那几行（仍是一步撤销）。
7. spec §2 第 8 条的 WinHTTP / libcurl：FPC 自带的两个绑定都不用（WinHTTP 绑定有错名、libcurl 绑定是静态链接），自己声明（核实记录 1、6）。

---

## 签收

（Task 15 填写：起点与提交、期末审查的处理、集中变异、测试结果、WSL 结果、量到的数、主控已做、与规格不符之处的写回、计划外发现、遗留。）
