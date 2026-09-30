# 终端控件 TTyTerminalView 验收

这是终端控件六期做完后的**一次性真机验收**入口：一张表列出 3–6 期所有要在真机上看的项，后面是还等你拍板的决定、截图在哪、发现问题怎么报。每项看完在「结果」列写 过 / 不过 / 现象。

## 这是什么，做了什么

`TTyTerminalView` 是库里的终端控件：宿主把程序的输出字节喂进来（`Write`），控件解析、存进屏幕缓冲、画出来；键盘、鼠标、粘贴编成字节，经 `OnData` 交还宿主。会话、PTY、shell 归宿主。解析、缓冲、核心、键盘编码照 xterm.js 6.0.0 移植，逐位对上游；渲染自己写。

- **1 期**：Unicode 宽度表（6 / 11 / 15 / 15-graphemes 四个版本）和 node 跑上游生成期望值的基准环境。
- **2 期**：解析器、缓冲、核心——几百个用例的缓冲、光标、模式、应答字节与上游逐位相同；写入队列、重入、超长和坏序列有界。
- **3 期**：可见控件——绘制、字形缓存、自绘框线、键盘、滚回与滚动条、主题（17 个皮肤明暗两种 16 色）、输入法、回放示例。
- **4 期**：真 shell（Windows ConPTY、Linux / macOS forkpty）、鼠标上报、选区与剪贴板、右键菜单、链接、OSC 52、示例的流量控制。
- **5 期**：改宽度时重新折行；一次很大的 `Write` 也分片、灌入时窗口照样重画；整屏上滚只画新露出的行；库的 Windows 文字渲染器留一张常驻位图（全库首帧文字快约一倍，像素不变）；`MinimumContrastRatio`；Powerline 与盲文自绘。
- **6 期**：终端可以不跟主题、换成独立的配色方案（前景、背景、光标、选区、16 色），可在设计器里改、能配成明暗两套随主题换；方案从 Windows Terminal 的 JSON 读进来、也能写出去；示例带 WT 自带的七套和三对明暗，外加「导入…」。

分支 `feat/terminal`，头提交 `afeb61f4`（6 期代码与测试，含期末审查的修复；之后只有文档）。全量测试 8413 条，只有 1 条红：`TPainterTest.TestTextIsInkedAsWindowsInksIt`——本机 ClearType 环境下的测试（main 带来的，和终端无关，改动前后实测值相同：Segoe UI 96 PPI 浅色 1075 / 0.24 对 Windows 1203 / 0.37）。

## 准备

- **示例**：`lazbuild -B examples/terminal/terminal_example.lpi`，程序在 `examples/terminal/lib/<目标平台>/` 下（Windows 是 `examples/terminal/lib/x86_64-win64/terminal_example.exe`，主控已在 2026-09-30 编好）。Linux 用 `--ws=gtk2` 或 `--ws=qt6` 编，macOS 用 `--ws=cocoa`。
- **设计期**（第 18、94、95 项）：先装 `tycontrols_dt.lpk` 重建 IDE。6 期起右键终端有「导入 Windows Terminal 配色…」「导出配色…」。
- **两种模式**：示例第一行工具栏最左边的下拉切 Replay（回放）和 Shell。回放读 `examples/terminal/recordings/` 里的录制（vim、htop、less、tmux、彩色 ls、中英表情、两段 ConPTY 录制）；Shell 起真的 shell（Windows 默认 `%COMSPEC%`，另列 powershell，有的话列 pwsh、wsl；Linux / macOS 是 `$SHELL -l`）。「Minimum contrast」（最低对比度）下拉在第四行工具栏；Shell 模式的命令框和「Log PTY output」在第三行；6 期的「Colours」（配色）下拉和「Import...」（导入…）在第五行，同一行右边是光标设置（「Cursor:」形状、「Blink」闪烁、「Unfocused:」失焦时的样子，第 101 项）。
- **要 WSL 或别的平台的项**：表后的平台索引列了每台机器要做的项。WSL 里 `tools/terminal-ptytest` 的 12 例 4 期已跑过，不用再跑。
- **基准工具**（第 72、75、89 项）：`lazbuild -B tools/terminal-bench/terminalbench.lpi`。
- **顺序建议**：先 Win32 本机（Windows 10 19044），再 Windows 11，再 Linux GTK2 / Qt6，最后 macOS。

## 验收表

「期（原编号）」是这一项最早出现的那一期和它在那期计划里的编号；「5 期审查补」是 5 期两轮审查建议加的。第 92 项起是 6 期。3、4 期的项在后来某期被改写过的，「怎么操作」末尾带一句「5 期：…」或「6 期：…」。

| # | 期（原编号） | 验什么 | 平台 | 怎么操作 | 期望 | 结果 |
|---|---|---|---|---|---|---|
| 1 | 3 期（1） | E1 字体回退 | GTK2、Linux Qt6、Cocoa（Win32 已在 Task 0 跑过） | 各平台编 `tools/terminal-fontprobe`，跑 `--e1` | CJK 有字形、宽 1.5–2.5 格、不被截；按结果确认 / 改 `monospace-wide` 的平台默认值 |  |
| 2 | 3 期（2） | E2 画质与耗时 | 同上 | 跑 `--e2` | （c）对参照差 ≤ 2、热缓存全屏 ≤ 16 ms |  |
| 3 | 3 期（3） | 16 色与皮肤 | Win32 | 看 34 张 16 色样例截图 + 34 张 `ls-color` 截图<br>6 期：看不清的可以在示例里换一套方案对照（第 92 项）。 | 每种皮肤明暗下 1–6、9–14 都看得清；7 / 15 的取舍（开工前问题一第 3 条） |  |
| 4 | 3 期（4） | 回放与真终端一致 | 任一 | 示例播放 vim / htop / less / tmux / git log / 彩色 ls / 中英表情 | 与 WSL 里真终端同一录制的画面一致（框线连续、宽字符两格、颜色对） |  |
| 5 | 3 期（5） | Linux / macOS 小字清晰度、macOS CJK 下半截 | Qt6、GTK2、Cocoa | 示例 9pt 下看中文与粗体 | 不虚、CJK 不缺下半截 |  |
| 6 | 3 期（6） | 键盘：Alt+字母 与窗体菜单 | Win32 | 示例关只读，按 Alt+F、F10 | 终端收到 `ESC f`；F10 发 `ESC[21~`、不激活菜单 |  |
| 7 | 3 期（7） | 键盘：AltGr 布局 | Win32（德语、法语布局） | AltGr+Q、AltGr+E、AltGr+7 | 出 `@`、`€`、`{`，不发 ESC 前缀 |  |
| 8 | 3 期（8） | 键盘：macOS Option | Cocoa | `MacOptionIsMeta` 两种设置下 Option+字母 | False 出第三层字符；True 发 `ESC` + 字母 |  |
| 9 | 3 期（9） | 键盘：死键 | Win32、GTK2、Cocoa | 国际布局下 `´` + `e` | 出 `é` 一个字符 |  |
| 10 | 3 期（10） | 键盘：Ctrl+Space、Ctrl+/、Ctrl+Shift+2 / 6 / - | 各平台 | 键码面板 | `00`、`1F`、`00` / `1E` / `1F` |  |
| 11 | 3 期（11） | Tab 与焦点 | GTK2、Qt6、Cocoa | 终端获焦后按 Tab、Shift+Tab | 发 `09` / `ESC[Z`，焦点不离开终端；`OnShortcutQuery` 放行 Tab 后焦点才走 |  |
| 12 | 3 期（12） | 复制粘贴快捷键 | 各平台 | Ctrl+Shift+V、Shift+Insert、Cmd+V；Ctrl+C | 前三个粘贴；Ctrl+C 发 `03` |  |
| 13 | 3 期（13） | 输入法 | Win32、Qt6、GTK2、Cocoa；GTK3 | 中文输入法打字<br>5 期：macOS 组字串跟着光标列走，见第 90 项。 | 提交的字经 `OnData` 发出；候选窗在光标格（GTK3 已知不跟随）；Cocoa 组字串画在光标处、取消时不发 |  |
| 14 | 3 期（14） | 滚轮 | 各平台 | 主屏滚回、备用屏（less）、htop（要鼠标） | 主屏滚 3 行 / 格；less 里翻行（方向键）；htop 里滚轮上报 |  |
| 15 | 3 期（15） | 滚动条自动隐藏 | 各平台 | `ScrollBarAutoHide` 三个值；进出 vim | 列数不变；备用屏条禁用 / 淡掉 |  |
| 16 | 3 期（16） | DPI | Win32 125% / 150%、每显示器切换 | 拖窗口跨屏 | 格子数、字形重建，不糊不错位 |  |
| 17 | 3 期（17） | 光标闪烁 | 各平台 | `CursorBlink = True`，放着不动 5 分钟 | 600ms 闪烁；5 分钟后停在显示 |  |
| 18 | 3 期（18） | 设计期 | Lazarus IDE（Win32） | 面板图标、放一个到窗体、换主题<br>6 期：见第 94、95 项。 | 图标对；预览 16 色随主题变；没有滚动条和计时器 |  |
| 19 | 3 期（19） | OSC 改色后整屏更新 | 各平台 | 在真 shell（4 期）或录制里 `printf '\e]11;#203040\a'`、再 `printf '\e]111\a'`<br>6 期：自定义方案下再做一次，`\e]111\a` 回到方案的底色（第 96 项）。 | 整个终端连内边距一起变色、变回，没有残留的旧底色条 |  |
| 20 | 3 期（20） | 候选窗位置在切焦点之后 | Win32 | 在示例旁放的 Memo / Edit 里打中文，再点回终端打中文 | 候选窗在终端的光标格，不留在 Memo / Edit 的位置 |  |
| 21 | 3 期（21） | AltGr | Linux GTK2、Qt6（德语、法语布局） | 同第 7 项 | 出布局上的字符，不发 ESC 前缀 |  |
| 22 | 3 期（22） | 切应用时的焦点报告 | 各平台 | 程序打开 1004（`printf '\e[?1004h'`）后 Alt+Tab 切走再切回 | 键码面板依次出 `1B 5B 4F`、`1B 5B 49`；光标变空心框、停闪，回来恢复 |  |
| 23 | 3 期（23） | 同步输出（2026） | 各平台 | neovim、tmux 里快速滚动 / 重绘；再用一个只开 2026 不关的脚本 | 画面不撕裂；只开不关的 1 秒后恢复刷新 |  |
| 24 | 3 期（24） | 表面位图不整块黑 | GTK2、Qt6、Cocoa | 示例正常播放、拖动改尺寸、局部重画（光标闪烁） | 没有整块黑（pf24bit 的坑，[[opaque-device-cache-pf24bit]]）；非 Win32 的贴图走 `DrawPart`，顺带看局部重画的耗时 |  |
| 25 | 3 期（25） | 滚轮手感 | 各平台（触控板、高精度滚轮） | 主屏滚回、less 里、Shift+滚轮 | 触控板不过灵、不丢格；Shift+滚轮在 Win / Linux 上不动、在 macOS 上滚滚回 |  |
| 26 | 3 期（26） | 浅底 3 号色取舍 | —（看截图） | `…-shots/ansi-3-{xp,macos,breeze}-light-15x.png`、`palette-*-light.png`、`ansi-7-15-default-light-2x.png`<br>6 期：默认仍跟随主题；看不清的宿主可以换方案（决定 D1）。 | 用户在（a）以最暗浅底重算、（b）终端底色改用更白 token、（c）维持 三者中定；7 / 15 调不调 |  |
| 27 | 3 期（27） | Shift+Home / End | Win32 PSReadLine、nano | 按 Shift+Home / Shift+End | 现在是本地到顶 / 到底；用户定去留（spec §15） |  |
| 28 | 3 期（28） | 禁用态外观 | 各平台 | 示例里临时把终端 `Enabled := False` | 整块按 `:disabled` 的 opacity 变淡，字、底色、内边距、外框一致 |  |
| 29 | 3 期（29） | 高 DPI 下「按录制尺寸」 | Win32 125% / 150% | 点「按录制尺寸」 | 网格正好是录制的行列数（状态栏显示），不多不少 |  |
| 30 | 3 期（30） | 满屏框线的流畅度 | 各平台 | 播放 `tmux-split.cast`；真 mc / tmux（4 期） | 不卡；框线连续 |  |
| 31 | 3 期（31） | macOS 输入法 | Cocoa | 拼音输入、取消、死键（´ + e） | 组字串画在光标处，提交发一次、取消不发；死键的 é 只发一次 |  |
| 32 | 4 期（32） | ConPTY 基本 | Win32（本机 19044；有条件再在 Windows 11 上） | 示例 Shell 模式起 cmd、pwsh；`dir`、彩色输出、Tab 补全、方向键历史、Ctrl+C 中断 `ping -t`；拖窗口改大小后 `mode con` | 都正常；`mode con` 的列数、行数等于状态栏的网格尺寸 |  |
| 33 | 4 期（33） | ConPTY 启动时发了什么 | Win32 | 打开「记录 PTY 输出」再起 cmd，看侧栏前 4 KB | 记下有没有 `?9001h`、`?1004h`、`?25l` 等，写回 spec §12.4 / §16；控件对 `?9001h` 不认（DECRQM 报不认识），键盘照常 |  |
| 34 | 4 期（34） | ConPTY 鼠标 | Win32 | cmd 里跑 `wsl.exe` 进 vim `:set mouse=a`、htop；有 Far Manager 的话跑一次 | 能点能拖能滚就记「通」；不通就记构建号与现象（控件侧协议本期已按标准做，见「Win32InputMode 与 ConPTY 鼠标：结论」） |  |
| 35 | 4 期（35） | 老 ConPTY 的折行启发 | Win32 19044 | 输出一行 300 字符的长行，窗口改窄再改宽；三击这行、复制<br>5 期：老 ConPTY 仍不重新折行、启发照旧（第 68 项同一件事）。 | 显示与 ConPTY 重绘一致；三击选中整段折行、复制成一行 |  |
| 36 | 4 期（36） | forkpty 路径 Linux | GTK2、Qt6 | 示例起 `$SHELL -l`；vim、htop 里拖窗口；`exit 3` | 起得来；vim / htop 跟着改尺寸重画；终端里打出「进程已退出（3）」，能重启 |  |
| 37 | 4 期（37） | forkpty 路径 macOS | Cocoa | 同上，zsh | 同上 |  |
| 38 | 4 期（38） | 鼠标上报 | 各平台 | vim `:set mouse=a` 点、拖选、滚；htop 点列头；tmux `set -g mouse on` 拖分隔线、点窗格；mc | 都按程序的意思动；拖出窗口外仍在报（捕获） |  |
| 39 | 4 期（39） | 覆盖键本地选择 | 各平台 | vim 鼠标模式下按住 Shift（macOS Option）拖选，再 Ctrl+Shift+C / Cmd+C | 选中的是本地选区、vim 没收到拖动；剪贴板里是那段文字 |  |
| 40 | 4 期（40） | 右键 | Win32、GTK2、Qt6、Cocoa | 程序没接管：右键出四项菜单（没选区时复制灰）；vim 鼠标模式：右键发给 vim、不弹菜单；Shift（macOS Option）+右键弹菜单；菜单键 / Shift+F10 | 都如此；GTK 上菜单不会在右键上报之后又弹出来（地雷 9） |  |
| 41 | 4 期（41） | 选词、选行、列选 | 各平台 | 双击单词、路径、网址；三击折行的长行；Alt+拖动 | 词按 `WordSeparators` 断、网址整条；三击整段折行；列选是矩形。Linux 上 Alt+拖动若被窗口管理器拿走，记下来 |  |
| 42 | 4 期（42） | 拖选自动滚 | 各平台 | 滚回里拖选到窗口上边外、下边外，远近不同 | 越远越快；松手停 |  |
| 43 | 4 期（43） | 选区随输出 | 各平台 | 选中滚回里的一段，同时 `ping`（Win：`ping -t`）持续输出 | 选区跟着文字往上走；文字被挤出滚回后选区消失；打字时选区清掉 |  |
| 44 | 4 期（44） | 复制规则 | Win32、Linux | 选中含折行长行和行尾空白的几行，复制到记事本 / gedit | Windows 上是 CRLF、Linux 上是 LF；折行接成一行；行尾空白去掉 |  |
| 45 | 4 期（45） | CopyOnSelect | 各平台 | 示例里勾上，拖选 | 松手即进剪贴板 |  |
| 46 | 4 期（46） | Linux PRIMARY | GTK2、Qt6（X11；再在 Wayland 会话里看一次） | 在终端里选中，到别的程序中键；在别的程序里选中，到终端中键 | X11 下两个方向都通；Wayland 下记现象 |  |
| 47 | 4 期（47） | 链接 | 各平台 | `echo https://example.com`；`printf '\e]8;;https://example.com\e\\link\e]8;;\e\\\n'`；`ls --hyperlink=auto`（file://）；vim 鼠标模式里 Ctrl+单击网址<br>5 期：悬停中拖窗口改尺寸，下划线和手形都取消（第 88 项）。 | Ctrl+悬停出下划线、手形；Ctrl+单击弹示例的确认、再用浏览器开；不按 Ctrl 悬停没有下划线；`file://` 默认不是链接（开工前问题一第 2 条）；vim 里 Ctrl+单击也开 |  |
| 48 | 4 期（48） | OSC 52 | 各平台 | 示例三种策略下 `printf '\e]52;c;aGVsbG8=\a'`，再 `printf '\e]52;c;?\a'`；tmux `set -g set-clipboard on` 里复制 | Off：剪贴板不变、读无应答；写：剪贴板变 `hello`；读写：读时示例弹确认，同意后键码面板里有应答 |  |
| 49 | 4 期（49） | 横向滚轮 | 各平台（触控板、带横滚的鼠标） | vim 鼠标模式里横滚；bash 里横滚 | vim 收到 66 / 67（键码面板可见）；bash 里什么都不发、窗口不乱滚 |  |
| 50 | 4 期（50） | 括号粘贴真机 | 各平台 | bash 5 / zsh 里粘贴多行；vim 插入模式粘贴缩进代码 | 多行不当场执行；vim 不层层缩进 |  |
| 51 | 4 期（51） | 输入法进真 shell | Win32、Qt6、GTK2、Cocoa | cmd / bash 里 `echo 中文` | 候选窗在光标格；回车后 shell 回显中文 |  |
| 52 | 4 期（52） | 高 DPI 下的鼠标 | Win32 150% | 选区起点（半格规则）、拖动阈值、上报格子 | 点在格子右半从下一格开始选；上报的格子和指针对得上 |  |
| 53 | 4 期（53） | macOS 全选与右键选词 | Cocoa | Cmd+A、Cmd+C；在选区外右键 | 全选并可复制；右键先选中词再弹菜单 |  |
| 54 | 4 期（54） | 流量控制 | 各平台 | `cat` 一个 50 MB 文本（Win：`type`）<br>5 期：一次很大的 `Write` 也按 32 KB 一段切片；灌入期间窗口照样重画（第 72、89 项），输入不卡（第 81 项）。 | 界面不冻、内存不涨过百 MB；没有「写入溢出」；中途 Ctrl+C 能停 |  |
| 55 | 4 期（55） | 关闭与重启不挂 | 各平台 | `ping -t` / `sleep 1000` 运行中点「重启」、再直接关窗 | 立即重启 / 关闭；任务管理器 / `ps` 里没有残留的 shell 或 conhost |  |
| 56 | 4 期（56） | 关闭 / 重启的冻结时长（第 55 项的可量标准） | Win32、GTK2、Qt6、Cocoa | 第 55 项的三种程序（`ping -t`、一个在 `CTRL_CLOSE_EVENT` 里不走的程序、`trap '' HUP; sleep 1000`）各点一次「重启」、各关一次窗；看界面停多久 | 点下去到界面能动 ≤ 200 ms（关闭在收尾线程上，自动测试量的是 `Close` < 200 ms）；关窗时窗口可以晚到约 9 秒才消失（程序退出时有上限的总等待），但窗口不「未响应」 |  |
| 57 | 4 期（57） | Win11 24H2 无残留 | Windows 11 24H2 | 同第 55 项；再跑 `cmd /k` 后关窗 | 24H2 上 `ClosePseudoConsole` 不再等，程序可能还在：3 秒内按句柄结束，任务管理器按 PID 查不到；这是本机杀不掉的 Y16 变异交给真机的那一半 |  |
| 58 | 4 期（58） | 退出与关闭同时发生 | 各平台 | `cmd /c exit 3`（`sh -c 'exit 3'`）反复点「重启」，快过它退出 | 不崩、不挂、没有残留；偶尔看到上一个程序的退出行是正常的，不会出现在新程序的输出中间 |  |
| 59 | 4 期（59） | macOS 的 `poll()` 与 PTY | Cocoa | 示例起 zsh，`ls`、`cat` 大文件、改尺寸 | 输出照常；若 `poll()` 对主端答 `POLLNVAL`，后端自动换 `select`（WSL 里强制走过这条路径） |  |
| 60 | 4 期（60） | 失去捕获 | Win32、GTK2、Qt6、Cocoa | 在终端里按住左键拖选，拖动中 Alt+Tab 切走再松键再切回；vim 鼠标模式里拖动中弹出一个模态框（宿主可用 `OnBell` 弹） | 切回后选区已经结束、不再跟着指针；vim 收到了抬起（不再以为键还按着）；`GetKeyState` 对鼠标键的答案在各 widgetset 上对 |  |
| 61 | 4 期（61） | Shift+F10 | Win32、GTK2、Qt6、Cocoa | bash / vim 里按 Shift+F10 | 程序收到 F10 带 Shift 的编码；之后弹不弹控件菜单记下来（看 widgetset），写回 §9.6.4 |  |
| 62 | 4 期（62） | 子进程的信号与描述符 | GTK2、Qt6、Cocoa | 示例起 `bash --norc`，`grep -E 'Sig(Blk|Ign)' /proc/self/status`（macOS 用 `trap -p`、`ulimit`）；`yes \| head -1`；`ls /proc/$$/fd` | 屏蔽字和忽略集都是 0（LCL 程序忽略了 SIGPIPE 也不传下去）；`yes` 静悄悄结束；没有宿主的描述符 |  |
| 63 | 4 期（63） | 失焦选区看得见 | 各平台，17 个皮肤明暗 | 选中一段后点别处；深色主题、反显文字上（`ls --color` 的目录、vim 的状态行）也选一次<br>5 期：office 深色的聚焦选区 4 期没截图，真机看（决定 D3）。 | 失焦的选区在每个皮肤下都看得出（截图 `selection-*.png`）；反显、亮底色格上的选区和空白处同色 |  |
| 64 | 4 期（64） | X10 横向滚轮 | 各平台（触控板） | 程序开 `?9h`（`printf '\e[?9h'`）后横滚；再开 `?1000h` 横滚 | X10 下不上报、横滚交给外层（窗口里有可横滚的父控件时它动）；1000 下报 66 / 67 |  |
| 65 | 4 期（65） | ConPTY 录制在新版本上的差异 | Windows 11 | 用 `tools/terminal-conpty-record` 按 `recordings/*.cmdline` 重录 cmd / PowerShell，和 19044 的录制比 | 记下 ConPTY 画屏的差别（标题、清屏、行尾补空格）；控件回放两份都和上游一致 |  |
| 66 | 5 期（66） | 回放模式折行 | Win32、GTK2、Qt6、Cocoa | 示例回放 `ls-color.cast`、`cat-cjk-emoji.cast`，拖窗口宽度窄、宽来回几次 | 长行按新宽度折回，缩回来复原；宽字符不劈开；颜色、链接跟着字走（截图 `reflow-*.png`） |  |
| 67 | 5 期（67） | 真 shell 里的折行 | GTK2、Qt6（bash、zsh）；Cocoa（zsh）；Windows 11（≥ 21376，pwsh） | 输出几行长行后拖窗口；再在提示符后打一条超长命令、拖宽 | 输出的长行折回；提示符那一段按程序的重画走（shell 收到改尺寸后自己重画，可能留一行旧提示符——上游同样，记现象） |  |
| 68 | 5 期（68） | 老 ConPTY 不折行 | Win32 19044 | Shell 模式（cmd）输出长行、拖窄再拖宽 | 不重新折行（启发照旧，同第 35 项）；截图 `reflow-oldconpty-*.png` 的样子 |  |
| 69 | 5 期（69） | 折行与选区、链接、滚动条 | 各平台 | 选中滚回里一段后拖宽度；按住 Ctrl 悬停一条折了行的网址后拖宽度；拖宽度前后看滚动条 | 选区按开工前问题一第 2 条的结论（清掉或保留）；悬停下划线消失、再移动指针在新位置出现；滚动条的范围和拇指跟着新行数 |  |
| 70 | 5 期（70） | 大滚回拖窗口（改尺寸合并） | Win32、GTK2、Qt6、Cocoa | `Scrollback` 分别设 1000（默认）和 10000（示例里临时改），`seq 1 200000 \| paste -sd' '` 之类的长行填满后，按住窗口边框慢慢拖宽、拖窄，拖几秒再松手 | 拖动不卡、不「未响应」；记下是只在停下 / 松手时折一次，还是每动一下就折一次（Win32 的模态拖动循环会派发排着的异步调用，合并可能不起作用）；卡的话记下哪个平台、哪个滚回行数，决定改成定时器节流或等 `WM_EXITSIZEMOVE`（决定 N3） |  |
| 71 | 5 期（71） | 吞吐与帧率 | Win32、GTK2、Qt6、Cocoa | `cat` 50 MB 文本（Win：`type`）、`yes`（Win：`cmd /c "for /l %i in (0,0,1) do @echo y"`）、htop 全屏刷新；看任务管理器 / `top` | 界面不冻、能拖窗口；内存不涨过百 MB；CPU、帧率记下来写回 spec §16（四个 widgetset 各一组） |  |
| 72 | 5 期（72） | 一次很大的 Write | Win32（再抽一个 Linux widgetset） | `terminalbench --window --flood 20`（一个窗口、一次 `Write` 20 MB） | 灌入期间窗口能拖、能重画，不「未响应」 |  |
| 73 | 5 期（73） | 滚动只画新行不留残影 | Win32、GTK2、Qt6、Cocoa | less / vim 里快速翻页；tmux 分屏里一边滚；输出含 ░▒▓ 的文本并滚动；光标闪烁时滚；有选区时滚 | 画面和整屏重画一样：没有错位、没有残影、阴影图案不「跳」 |  |
| 74 | 5 期（74） | 冷启动首屏 | Win32 | 新开示例，回放 `cat-cjk-emoji.cast` 一次喂完 | 首屏几乎立刻画全；字形和库里别的控件的文字观感一致（和 3 期截图对照） |  |
| 75 | 5 期（75） | 非 Win32 的冷启动耗时 | GTK2、Qt6、Cocoa | 各平台编 `tools/terminal-bench`，跑 `--raster` | 每个字形的耗时记下来写回 spec §10.3；比 Win32 基线慢很多的平台，记成以后优化的依据 |  |
| 76 | 5 期（76） | 最低对比度 | Win32；17 个皮肤明暗抽看 | 示例「最低对比度」切 1 / 4.5；看 `palette.cast`、`ls --color`、暗淡文字（`printf '\e[2mdim\e[0m'`）、选区里的字；再加一个暗淡又要调整的字：`printf '\e[2;38;2;170;170;170;48;2;187;187;187mX\e[0m'`<br>6 期：方案下同样生效（第 97 项）。 | 4.5 下 xp / macos / breeze 浅色的 3 号色清楚了；暗淡的字仍比正常的淡；决定清单第 1 条就此定（截图 `contrast-*.png`）；那个 X 在 4.5 下看得清、又比同色的正常字淡（调过的颜色不再变淡，照上游） |  |
| 77 | 5 期（77） | 对比度不动框线与块 | 各平台 | 4.5 下跑 mc、tmux 分屏、`printf '\u2588\u2593'` | 边框、块元素的颜色与 1 时相同 |  |
| 78 | 5 期（78） | Powerline 与盲文自绘（Task 12 做了才有） | 各平台 | oh-my-posh / starship 的 powerline 主题；btop | 箭头、圆角和相邻格的底色严丝合缝；盲文点阵清楚（截图 `glyphs-*.png`） |  |
| 79 | 5 期（79） | 高 DPI 下的折行与滚动 | Win32 150%、每显示器 DPI 切换 | 第 66、73 项在 150% 下各做一次，再把窗口拖到另一块 DPI 不同的屏 | 没有错位；切屏后格子数、字形重建，折行照新列数 |  |
| 80 | 5 期审查补 | 满滚回后拖窄不丢最后几行 | Win32、GTK2、Qt6、Cocoa | `Scrollback` 设 5（示例里临时改），输出 20 行长行把滚回填满，再把窗口拖到很窄 | 最后一行仍是提示符、光标在它上面；不会变成顶上被挤掉的那行内容（上游的这个 bug 我们没照搬，spec §15） |  |
| 81 | 5 期审查补 | 灌入时输入不卡 | Win32（再抽一个 Linux widgetset） | `cat` 50 MB 文本（Win：`type`）的同时打字、按 Ctrl+C、拖动窗口、点滚动条 | 按键、鼠标立即有反应；Ctrl+C 能停；Win32 上有按键排队时下一片会让一下（spec §3.1），吞吐略降、不停顿 |  |
| 82 | 5 期审查补 | Linux x86_64 上的对比度夹具 | Linux x86_64（GTK2 或 Qt6） | 在 Linux 上编 `tests/tytests.lpi`，跑 `--suite=TTyTerminalRenderTests` | 全绿：对比度夹具在 Extended 精度下仍逐位相同（本机 Win64 只证明 Double 下相同；i386 只支持 SSE2 编译） |  |
| 83 | 5 期审查补 | 各 widgetset 编整个包 | GTK2、Qt6、Cocoa | 各平台 `lazbuild -B tycontrols.lpk`、`tycontrols_dt.lpk`，再编示例 | 都编过（5 期只在 Win32 编过） |  |
| 84 | 5 期审查补 | Painter 常驻位图：高 DPI 与每显示器 DPI | Win32 125% / 150% / 200%、每显示器 DPI 切换 | 示例里的 Memo、Grid、按钮、菜单、终端；把窗口拖到另一块 DPI 不同的屏 | 文字位置、粗细和以前一样；切屏后字号跟着变，不糊、不截 |  |
| 85 | 5 期审查补 | Painter 常驻位图：ClearType 关掉 / 灰度 | Win32（同一台机器） | 系统设置里关掉 ClearType（或改灰度），同一次会话跑 `tools/painter-regress/ab.sh cf92b36d^` | 全部画面 0 像素差；本机默认 ClearType 下的结果见 `tests/fixtures/painter-regress/ab-2026-09-30.md` |  |
| 86 | 5 期审查补 | 长时间运行的 GDI 对象和内存 | Win32 | 示例开着终端跑 `ping -t` 一小时，中途换几次主题、拖几次窗口；任务管理器加「GDI 对象」「内存」两列 | GDI 对象数稳定（常驻位图只占 1 个 DC、1 张位图、1 个字体）；内存不持续上涨 |  |
| 87 | 5 期审查补 | Memo 画过超长行后的内存 | Win32 | 在一个 Memo 里粘贴一行 5 万字符不换行的文字，滚动几次，再删掉 | 任务管理器里内存涨一下就回来；常驻位图不超过约 12 MB（超长的一段走一次性位图、画完就放） |  |
| 88 | 5 期审查补 | 悬停链接时拖窗口 | 各平台 | 按住 Ctrl（macOS Cmd）悬停一条网址，另一只手拖窗口边框改尺寸 | 下划线消失，指针从手形变回 I 形 |  |
| 89 | 5 期审查补 | 一次很大的 Write 期间窗口能重画 | GTK2、Qt6、Cocoa（Win32 已有自动测试 `TestAFloodStillPaints`） | `terminalbench --window --flood 20` | 灌入期间画面在动、窗口能拖、不「未响应」 |  |
| 90 | 5 期审查补 | macOS 组字串跟着光标 | Cocoa | 组字过程中让光标闪烁、用方向键左右移动光标 | 组字串一直画在光标所在的格子，不留在旧位置 |  |
| 91 | 5 期审查补 | office 深色的聚焦选区 | Win32 | 切到 office 深色，选中一段文字，终端保持聚焦 | 选区看不看得出来（聚焦选区对底色只有 1.27:1，靠色相区分），结论交决定 D3 |  |
| 92 | 6 期（92） | 示例里切方案 | Win32；GTK2、Qt6、Cocoa 各抽一次 | 「Colours」（配色）下拉切七套、再切回「跟随主题」；回放 `palette.cast`、`ls-color.cast` | 整窗（连内边距）换成那一套，换皮肤时不跟着变；切回后和以前一样（和 `scheme-*.png` 对照） |  |
| 93 | 6 期（93） | 明暗配对 | 各平台 | 选「Tango (light / dark)」，拨标题栏的暗色开关几次；再换一个深色皮肤；Shell 模式里先 `printf '\e[?2031h'`，再拨暗色开关几次，看键码面板 | 浅色主题是 Tango Light、深色是 Tango Dark，拨一次换一次；单模式的深色皮肤也换到深色那套（截图 `scheme-pair-tango-*.png`）；开着 2031 时每拨一次键码面板恰好出一条 `ESC [ ? 997 ; 1 n` / `2 n`，不多不少 |  |
| 94 | 6 期（94） | 设计器里改方案 | Lazarus IDE（Win32） | 放一个终端，`ColorSource` 改成 `tsrcScheme`，展开 `ColorScheme` 改几个颜色；存盘、关掉窗体再打开 | 设计期预览跟着变；`.lfm` 里只有改过的几项；重开后颜色还在 |  |
| 95 | 6 期（95） | 设计器右键导入导出 | Lazarus IDE（Win32） | 右键终端「导入 Windows Terminal 配色…」选本机 WT 的 `settings.json`（`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_*\LocalState\settings.json`）挑一套；导入后按 Ctrl+Z；开着 `ColorSchemePaired` 再导入一次（会问写进浅色还是深色）；再「导出配色…」，把导出的文件放进 WT 的 `schemes` 里；最后把方案的 `Name` 清空（或清掉一个颜色）再导出 | 导入后预览是那一套、窗体标成已修改；`ColorSource` 还是跟随主题时会问要不要改；Ctrl+Z 撤不撤得掉这次导入，记现象；对话框标题没有省略号（中文界面也是）；导出的方案在 WT 里能选、颜色一样；没名字或缺色的方案一选导出就报错，不弹保存对话框、不留空文件 |  |
| 96 | 6 期（96） | 方案下程序改色 | 各平台 | 自定义方案下 Shell 里 `printf '\e]11;#203040\a'`、`printf '\e]4;1;#00ff00\a'`，再 `printf '\e]111\a'`、`printf '\e]104\a'`；开 2031 后切方案（`printf '\e[?2031h'`，看键码面板） | 程序的颜色盖过方案；复位后回到方案的颜色（不是主题的）；切方案时程序设的颜色被清掉、键码面板出一条 `ESC [ ? 997 ; 1 n` / `2 n`，和新方案的底色深浅一致（截图 `scheme-osc11-solarized-dark.png`） |  |
| 97 | 6 期（97） | 方案下的最低对比度与禁用 | Win32 | Solarized Light 下「最低对比度」切 1 / 4.5；临时把终端 `Enabled := False` | 4.5 下浅色方案里的淡色字变清楚、框线块元素不变；禁用时整块变淡（和 `scheme-contrast-*.png` 对照） |  |
| 98 | 6 期（98） | 系统色 | Win32、GTK2、Qt6、Cocoa | 设计器里把方案的背景设成 `clWindow`、前景设成 `clWindowText`，运行；运行中改系统配色（Windows：高对比度主题或「窗口」颜色；Linux：换 GTK / Qt 主题），再让程序调一次 `Term.ColorScheme.Changed`（示例里没有按钮，临时加一行，比如接在暗色开关上） | 颜色是那个平台窗口底色 / 字色；记下各 widgetset 的实际值，写回 spec §11.1.3；改了系统配色后终端先不变，调 `Changed` 后换成新的窗口色 |  |
| 99 | 6 期（99） | 导入真实的 WT 文件 | Win32 | 示例「导入…」本机 WT 的 `settings.json`（带注释、尾逗号，可能有 BOM）；再导入 `iTerm2-Color-Schemes` 的 `windowsterminal/` 里任意几个文件；同一个文件再导入一次；再导入一个故意写坏的（删一个颜色）；再导入两个方案名是中文的文件，一个名字写成 `\u` 转义（`"name": "\u6d4b\u8bd5"`），一个直接写 UTF-8 的中文 | 能读的都出现在下拉里、颜色和 WT 里一样；同名的方案（比如 WT 自带的 Campbell 和示例里的 Campbell）在下拉里只出现一次，再导入同一个文件也不多；坏文件在状态栏报出缺哪个颜色，终端不变，之后选一套能读的，状态栏里的错误消失；两个中文名在下拉里都显示成正确的中文 |  |
| 100 | 6 期审查补 | 只设底色的方案配浅主题 | Win32 | 设计器（或临时代码）里一个终端 `ColorSource := tsrcScheme`，方案只设 `Background`（深色，比如 `#1E1E1E`），16 色都不设；浅色主题下回放 `palette.cast`、`ls-color.cast`；再拨到深色主题看一次 | 16 色跟的是主题：浅色主题下是给浅底配的那套，落在深底上几色（0 黑、4 蓝等）看不清——这是定下的逐槽规则，不是 bug；看完定：维持并在文档提醒（现在的做法，控件文档 §10 已写），还是改成按方案的底重求 16 色（结论交决定 D1 或文档） |  |
| 101 | 6 期审查补 | 示例里的光标设置 | Win32（WSL 或 Git Bash 的 vim）、GTK2、Qt6、Cocoa | 第五行「Cursor:」切方块 / 下划线 / 竖线，勾「Blink」，「Unfocused:」切几种再点别处；Shell 模式跑 vim：进插入模式（`i`）、退出（Esc），再 `printf '\e[0 q'`；再换一种默认样式后跑一次 vim | 三种形状、闪烁、失焦样子都跟着设置变；vim 插入模式把光标改成竖线，Esc 退出后恢复（vim 自己发 DECSCUSR）；`CSI 0 SP q` 回到示例里选的样式，不是固定的方块 |  |

## 按平台的项号

在一台机器上一次做完：

| 平台 | 项号 |
|---|---|
| Win32 本机（Windows 10 19044） | 3、4、6、7、9、10、12、13、14、15、16、17、18、19、20、22、23、25、27、28、29、30、32、33、34、35、38、39、40、41、42、43、44、45、47、48、49、50、51、52、54、55、56、58、60、61、63、64、66、68、69、70、71、72、73、74、76、77、78、79、80、81、84、85、86、87、88、91、92、93、94、95、96、97、98、99、100、101 |
| Windows 11 | 32、57、65、67 |
| Linux GTK2 | 1、4、5、9、10、11、12、13、14、15、17、19、21、22、23、24、25、28、30、36、38、39、40、41、42、43、44、45、46、47、48、49、50、51、54、55、56、58、60、61、62、63、64、66、67、69、70、71、72、73、75、77、78、80、81、82、83、88、89、92、93、96、98、101 |
| Linux Qt6 | 1、4、5、10、11、12、13、14、15、17、19、21、22、23、24、25、28、30、36、38、39、40、41、42、43、44、45、46、47、48、49、50、51、54、55、56、58、60、61、62、63、64、66、67、69、70、71、72、73、75、77、78、80、81、82、83、88、89、92、93、96、98、101 |
| macOS Cocoa | 1、4、5、8、9、10、11、12、13、14、15、17、19、22、23、24、25、28、30、31、37、38、39、40、41、42、43、45、47、48、49、50、51、53、54、55、56、58、59、60、61、62、63、64、66、67、69、70、71、73、75、77、78、80、83、88、89、90、92、93、96、98、101 |
| 只看截图 / 任一平台 | 4、26（6 期截图对照第 92、93、96、97 项） |

## 等你定的决定

每条：是什么、选项、现在的做法（默认）、看哪里、定了之后改哪里。「已定，可改」的是期末审查后主控按建议先定下来的，你可以推翻。

### 5 期期末新定的（已定，可改）

**N1 上游折行的一个 bug：修掉了**
- 是什么：xterm.js 的 `_reflowSmaller`（`Buffer.ts:504-510`）在滚回满了以后变窄，会把新行写到负下标，环形表取模后落在最后几行——提示符那一行变成顶上被挤掉的那行。
- 选项：（a）修掉，记成偏离（现在的做法）；（b）照上游逐位复刻。
- 看哪里：第 80 项；测试 `TestNarrowingAFullScrollbackKeepsThePrompt`。
- 另：要不要给上游报这个 bug，由你决定（我们不代报）。1 期发现的「node 下 15 表解码错」同理（spec §13.1）。
- 改哪里：`Buffer.Reflow.inc` 那一句判断；`tools/terminal-oracle/lib-dump.js` 的运行时补丁；spec §1.1 第 20 条、§6.2、§15。

**N2 两条没达标的性能目标：按实测改写了**
- 一行一行滚：原目标「每帧耗时 ≤ 基线的 1/4（1.74 ms）」没达到（离屏 4.78 ms、走窗口绘制 6.9 ms，基线 6.94 ms）。改写为「每帧画的行数 ≤ 3（实测 2.00），耗时不劣于基线」。要到 1/4 得在屏幕上直接滚（环形表面、`ScrollWindowEx`），列为以后。
- 50 MB 灌入：原目标「两次绘制的最长间隔 ≤ 50 ms」没达到。审查时还发现原来量的 69 ms 是假的：Windows 上排片的消息一直在，`WM_PAINT` 轮不到，窗口前 3.4 秒一次也没画。修好以后：解析加绘制一轮约 50 ms，间隔中位 52.6 ms、最长 79–110 ms，吞吐约 5 MB/s（不画的时候是 10–12 MB/s）。改写为「≤ 约 90 ms，且不劣于基线」：中位过，最长偶尔有尖峰超过 90 ms。
- 冷启动光栅化：原目标「每个字形 ≤ 基线的 1/3」只对 B 路线成立，你选的是 A。改写为「走 A：每个 ≤ 基线的 1/2」：ASCII 0.50、CJK 0.59（这台机器此时负载起伏大，Task 9 时是 0.47 / 0.53）。要再快就在 A 之上再做 B。
- 选项：接受改写；或者要求继续优化（上面列的以后的做法）。
- 看哪里：第 71、72、73、74、89 项；数字在 5 期计划末尾的签收和 spec §10.1、§10.3、§16。
- 改哪里：`Terminal.pas` 的 `FloodCycleMs`（一轮多长：长了吞吐高、画面稀）；spec §18。

**N3 改尺寸合并：保留**
- 是什么：拖窗口时新网格等消息循环里才生效，只按最后的尺寸折一次（1 万行滚回折一次 30–50 ms）。Win32 的模态拖动循环会派发排着的异步调用，真拖动时可能每动一下就折一次。
- 选项：保留（现在的做法）；去掉；改成定时器节流或等 `WM_EXITSIZEMOVE`。
- 看哪里：第 70 项（重点看 Win32）。
- 改哪里：`Terminal.pas` 的 `UpdateGrid` / `AsyncApplyGrid`；spec §6.2；`docs/controls/terminal.md` §6。

### 浅底配色

**D1 浅底 3 号色（暗黄）在几个皮肤的浅底上对比度不够**
- 选项：（a）以最暗的浅底重算浅色表；（b）终端底色改用更白的 token；（c）维持，靠 `MinimumContrastRatio` 兜底。
- 现在：（c）。对白底 4.52:1；落到皮肤实际浅底上 xp 3.70、macos 3.82、breeze 3.96（office 4.04、win10 4.07 …）。比值 1 时低于 4.5 的不止 3 号：xp 8 个（3、14、10 号最差）、macos 8 个、breeze 7 个；比值 4.5 时全部 ≥ 4.5。注意 `MinimumContrastRatio` 默认是 1，也就是默认不兜底。
- 看哪里：3 期截图 `ansi-3-{xp,macos,breeze}-light-15x.png`、`palette-*-light.png`；5 期截图 `contrast-{1,45}-{xp,macos,breeze}-light.png`；第 3、26、76 项。
- **6 期后的表述**：默认跟随主题；看不清可换方案。主题的浅底 16 色仍是默认，仍待你在（a）/（b）/（c）中定；嫌看不清的宿主可以把单个终端换成一套方案（示例里的 Tango Light、Solarized Light、One Half Light），或打开最低对比度。6 期截图 `scheme-tango-light.png`、`scheme-solarized-light.png`、`scheme-onehalf-light.png`、`scheme-contrast-{1,45}-solarized-light.png` 可对照。只设了底色的方案在浅色主题下 16 色仍是浅底那套，看第 100 项，结论也在这里定。
- 改哪里：（a）`tools/terminal-oracle/light-palette.js` 的目标底色、`themes/light.tycss` 的 16 色，重跑 `light-palette.js --check`、`scripts/gen-defaulttheme.ps1`、`gen-builtinthemes.ps1`；（b）`themes/light.tycss` 的 `--terminal-bg`；都要改 spec §11、§17.1 第 4 条。

**D2 浅底 7 / 15 号色调不调**
- 选项：不调（现在）；7 调到对白底 ≥ 3:1、15 保持最浅。
- 现在：不调，对白底约 1.4:1 和 1.2:1。
- **6 期后的表述**：7 / 15 调不调仍待定；默认跟随主题，看不清的宿主可以换一套方案。
- 看哪里：`ansi-7-15-default-light-2x.png`（对照 `…-dark-2x.png`）；第 3、26 项。
- 改哪里：`light-palette.js` 的排除集、`themes/light.tycss`、`tests/test.themes.pas` 的对比度守卫、spec §11、§17.1。

**D3 聚焦选区在 office 深色上对比度只有 1.27**
- 选项：不动（现在；靠色相区分，守卫只防以后改坏）；全局调 `--terminal-selection-bg` 的透明度；只在 office 皮肤里覆盖。
- 看哪里：第 63、91 项。**没有截图**（4 期只截了 default、xp、macos），要真机看。
- 改哪里：`themes/light.tycss` 或 office 皮肤；重跑 `gen-defaulttheme`、重铺 golden；spec §11。

**D4 `--terminal-pad` 的现代密度取值**
- 现在：经典 4px、现代 8px（`source/tyControls.DensityPack.pas`）。
- 看哪里：第 3 项时切到现代密度看一眼。
- 改哪里：`DensityPack.pas`。

### 键盘

**D5 Shift+Home / Shift+End**
- 选项：保留本地的「滚回到顶 / 到底」（现在）；照上游发给程序（PSReadLine、nano 里就能选到行首 / 行尾）。
- 看哪里：第 27 项。
- 改哪里：`Terminal.pas` 的 `KeyDown`、测试 `TestLocalPaging`、spec §9.4、§15、控件文档。

**D6 应用小键盘模式（DECKPAM）影不影响小键盘**
- 选项：照上游，不影响（现在）；照 xterm 发 `ESC O p` 等（没有基准的偏离）。
- 改哪里：`Keyboard.pas`；spec §1.1 第 9 条、§15。

**D7 滚动条的宽度一直留着**
- 选项：一直留着，列数不随主屏 / 备用屏变（现在）；备用屏里拿掉，进出 vim 时程序会多收一次改尺寸。
- 看哪里：第 15 项。
- 改哪里：`Terminal.pas` 的 `UpdateGrid`；spec §9.7。

### 链接、鼠标、菜单（4 期开工前的六条，现在都按建议做的）

| # | 是什么 | 现在 | 另一个做法 | 看哪里 | 改哪里 |
|---|---|---|---|---|---|
| D8 | 右键菜单 | 终端自建四项：复制、粘贴、全选、清屏 | 复用编辑框的六项菜单（要改共享的 `TextMenu.pas`） | 第 40 项 | `Terminal.View.Menu.inc`；spec §9.6.4 |
| D9 | `file://` 等非 http(s) 的 OSC 8 算不算链接 | 不算（`AllowNonHttpLinks` 默认 False） | 全认，交宿主 | 第 47 项 | `Terminal.pas`；spec §9.8 |
| D10 | macOS 右键先选中指针下的词 | 照上游这么做 | 不选词，或做成属性 | 第 53 项 | `View.Menu.inc` |
| D11 | Windows 上默认起什么 shell | `%COMSPEC%`，另列 powershell，找得到才列 pwsh、wsl | 默认 pwsh | 第 32 项 | 示例 `umain.pas`；spec §12.1 |
| D12 | Windows / macOS 上中键 | 什么都不做 | 像 PuTTY 那样粘贴 | 第 46 项（只验 Linux） | `View.Mouse.inc`；spec §15 |
| D13 | 双击链接 | 选整条，不要求按 Ctrl（照上游） | 按普通取词 | 第 41、47 项 | `View.Selection.inc`；spec §9.5.5 |

### 选区与折行

**D14 改列数、重新折行之后清不清选区**
- 选项：真的折行了就清（现在，偏离上游）；照上游不清——字挪了，选区会框着别的字。
- 看哪里：第 69 项。
- 改哪里：`Terminal.pas` 的 `CoreResize`；选照上游的话补一条「选区随折行的 trim 上移」的测试；spec §9.5.5、§15。

**D18 光标所在那段折行，拖宽时不复原**
- 选项：照上游不动（现在；`Core.ReflowCursorLine` 默认 False，宿主可开）；默认也折；把它做成控件的 published 属性。
- 看哪里：第 67 项。
- 改哪里：`Core.pas`；spec §6.2、§7.6。

### 渲染

**D15 框线两段笔画重叠处，有 0.01–0.03% 的像素差 1 级**
- 选项：保持（现在：整个字形合成一次再混色）；回到 3 期初版的逐段混色。肉眼基本看不出。
- 看哪里：没有专门截图，可以看 3 期截图里 `htop-few-frames-*`、`vim-edit-*` 的框线。
- 改哪里：`Render.pas` 的自绘字形；spec §10.4、§10.5。

**D16 自绘字形的范围**
- 现在：框线与块元素（2500–259F）、Powerline（E0A0–E0D4 里上游定义的 38 个）、盲文（2800–28FF）。
- 另一个做法：再加 Legacy Computing、进度条、git 分支图；或者去掉 Powerline / 盲文。
- 看哪里：5 期截图 `glyphs-{powerline,braille}-*.png`；第 78 项。
- 改哪里：`gen-terminal-glyphs.js`、`CustomGlyphs.inc`；spec §10.5。

**D17 `MinimumContrastRatio` 的默认值和来源**
- 现在：默认 1（不调），只是控件属性，没有主题 token；示例下拉 1 / 3 / 4.5 / 7。
- 另一个做法：浅色皮肤默认兜底——改默认值，或者加 token `--terminal-min-contrast`，或换一套方案（6 期）。和 D1 一起定。
- 看哪里：`contrast-*` 截图；第 76、77 项。
- 改哪里：`Terminal.pas`；主题；spec §9.1、§10.9。

**D19 macOS / Linux 的 CJK 宽字体默认值**
- 现在：Windows 空串（交给系统字体链接），macOS `PingFang SC`，Linux `Noto Sans CJK SC`——后两个按证据定的，没真机验过。
- 看哪里：第 1、5 项。
- 改哪里：`Terminal.pas` 的字体解析；spec §10.3。

### 6 期开工前的问题（都按建议做的，可改）

| # | 是什么 | 选项 | 现在 | 看哪里 | 改哪里 |
|---|---|---|---|---|---|
| D20 | 「明暗各一套」在属性上的样子 | A：`ColorSource`（跟随主题 / 自定义方案）两个值，另加开关 `ColorSchemePaired` 和第二个方案 `DarkColorScheme`；B：`ColorSource` 三个值、不要开关；C：不要开关，`DarkColorScheme` 里有颜色就算配对 | A | 第 93、94 项 | `Terminal.pas` 的四个属性；spec §11.1.3、§11.1.5 |
| D21 | 设计器里要不要右键「导入 / 导出 Windows Terminal 配色…」 | 做；不做（只能在对象查看器里一格一格填 22 个颜色） | 做 | 第 95 项 | `designtime/tyControls.Design.CompEditors.pas` 的 `TTyTerminalViewComponentEditor`；spec §11.1.9 |
| D22 | 示例带哪几套 | WT 自带的七套（Campbell、One Half 明 / 暗、Solarized 明 / 暗、Tango 明 / 暗）加三对明暗；WT 自带的 16 套全带；只带自己配的两三套 | 七套加三对（WT 的 MIT，Solarized、One Half 的 MIT，Tango 公有领域，notices 里一节） | 第 92、93 项；截图 `scheme-*.png` | `examples/terminal/colorschemes/windows-terminal.json`、`THIRD-PARTY-NOTICES.md`、发版守卫 `TheExampleColourSchemesAreCoveredByTheNotice` 里的七个名字 |
| D23 | 自定义方案下链接下划线和组字串的颜色（方案里没有这两项） | 链接下划线跟主题、组字串底色 / 字色用方案的底色 / 前景（下划线跟主题）；或链接下划线也用方案的前景 | 前者 | 第 96 项顺带看；组字串只在 macOS 画（第 90 项） | `Terminal.pas` 的 `PaintPreedit`；spec §11.1.4 |

### spec §15 里你可能想改的偏离（默认都不改）

- 链接悬停、激活要按 Ctrl（macOS Cmd）；上游悬停就下划线、单击就开。
- 输入法组字时不滚到底（上游 `scrollOnUserInput` 时会先滚到底）。
- macOS 默认的选区覆盖键是 Option（上游 macOS 默认没有覆盖键）。
- 1016 鼠标像素和 14t / 16t 尺寸应答报设备像素（上游报 CSS 像素）。
- 其余：横向滚轮上报；`AlternateScroll` 可关；XTVERSION 报库名；程序接管鼠标时 Ctrl+单击仍开链接；比格子宽的字形横向压进格子；Kitty 键盘协议与 win32-input-mode 一律屏蔽；Shift+滚轮在 Windows / Linux 上交还父控件；清滚回也清选区；同一个鼠标协议重复 DECSET 不清选区。
- 6 期新增：读 WT 配色时有六处和 WT 不同——十六进制位严格检查（WT 把 `#12345g` 读成 `05`）、重复键报错（WT 以后一个为准）、按名取时只校验选中的那一套（WT 整个文件读不进）、`purple` 与 `magenta` 都写了又缺一个主名时报缺键（WT 会留一色未初始化）、单个方案对象可以没有名字、写出时丢掉 `CursorText` 和 `SelectionInactiveBackground`；另外方案没设光标 / 光标下的字色时取生效的前景 / 底色（xterm.js 缺省是白 / 黑）。
- 5 期新增：大块输出块内切片、灌入时到点当场画一帧；改列数折行时清选区（D14）；对比度的取色（反显默认色照 WebGL、选区字色照 DOM）；`MinimumContrastRatio` 是 NaN 时按 1；`{conpty, 0}` 表达不了；Buffer 层三处抛异常；上游负下标 bug 不照搬（N1）；行内存回收当场做；对比度缓存有上限。

### 「记现象」的项，结论写回哪里

| 项 | 记什么 | 写回 spec |
|---|---|---|
| 33 | ConPTY 启动时发了哪些模式 | §12.4、§16 |
| 34 | ConPTY 鼠标通不通、构建号 | §12.4、§16 |
| 41 | Linux 上 Alt+拖动是否被窗口管理器拿走 | §9.5.5、§16 |
| 46 | Wayland 下的 PRIMARY | §9.6.2、§16 |
| 61 | Shift+F10 之后弹不弹菜单 | §9.6.4 |
| 65 | Windows 11 上 ConPTY 录制的差异 | §12.4、§13.4 |
| 67 | 真 shell 折行后留一行旧提示符 | §6.2、§15 |
| 70 | 拖动时合并有没有效、卡不卡 | §6.2（N3） |
| 1、2、75 | 各平台的字体与光栅化耗时 | §10.3 |
| 71 | 四个 widgetset 的 CPU 和帧率 | §16 |
| 95 | 设计器里 Ctrl+Z 撤不撤得掉一次导入 | §11.1.9 |
| 98 | 各 widgetset 下系统色（`clWindow`、`clWindowText`）解出来的实际值；改系统配色后调 `Changed` 的效果 | §11.1.3 |
| 100 | 只设底色的方案配浅主题时 16 色看不看得清 | §11.1.4（或决定 D1） |

## 截图

- [`2026-09-29-terminal-phase-3-shots/`](2026-09-29-terminal-phase-3-shots/index.md)：3 期，79 张。17 个皮肤明暗两种的 16 色样例和彩色 `ls`、几段录制（vim、htop、tmux、mc…）、3 号色与 7 / 15 号色的放大样例。
- [`2026-09-29-terminal-phase-4-shots/`](2026-09-29-terminal-phase-4-shots/index.md)：4 期，16 张。选区（聚焦 / 失焦、反显格上）、列选区、链接悬停。
- [`2026-09-29-terminal-phase-5-shots/`](2026-09-29-terminal-phase-5-shots/index.md)：5 期，22 张。折行前后（80 → 47 → 80 列，明暗两种）、老 ConPTY 不折的对照、最低对比度 1 与 4.5（xp、macos、breeze 浅色，default 深色）、不调的字形、Powerline 与盲文。
- [`2026-09-30-terminal-phase-6-shots/`](2026-09-30-terminal-phase-6-shots/index.md)：6 期，18 张。七套方案下的 `palette.cast`、Tango 明暗配对、跟随主题的对照（和从没设过方案的控件逐像素相同，也和 3 期的 `palette-default-*.png` 相同）、方案下程序的 OSC 11、Solarized Light 下最低对比度 1 与 4.5、只设了三色的方案、Campbell 的选区（另设了失焦选区色时失焦用它，`scheme-selection-inactive-campbell.png`）。
- 重新生成：`lazbuild -B tools/terminal-shots/terminalshots.lpi`，然后 `terminalshots`（3 期）、`terminalshots --phase4`、`terminalshots --phase5`、`terminalshots --phase6`。
- 库的文字路径前后对照（`Painter.pas` 常驻位图）：[`tests/fixtures/painter-regress/ab-2026-09-30.md`](../../../tests/fixtures/painter-regress/ab-2026-09-30.md)——366 个画面 0 像素差，耗时前后表，全量结果。

## 发现问题怎么报

- 在表里「结果」列写「不过」加一句现象；能截图就截图，放 `docs/superpowers/plans/2026-09-29-terminal-acceptance-shots/`，文件名带项号（如 `70-win32-drag.png`）。
- 说清楚：平台和 widgetset、Windows 构建号 / 发行版、缩放比例、皮肤与明暗、用的是回放还是 Shell（哪个 shell、跑的什么命令）、能不能复现。
- 卡顿、慢的，附上任务管理器（或 `top`）里的 CPU、内存、GDI 对象数；能跑 `terminalbench` 的附上它的输出。
- 画面不对的，顺手打开示例的「Log PTY output」看程序发了什么（右边面板，前 4 KB 十六进制）。

## 验收之后

- 结论写回 spec：各项的「记现象」按上表写回对应的节，决定清单定下来的改 spec §17 并在原处标注。
- 不过的项一个问题开一个 `fix(terminal): ...`，修完重跑全量。
- 合 `main` 之前按合并前清单查 i18n（示例的 `.po`）和 README。
- CHANGELOG 发版时写，只写用户能感觉到的变化。
