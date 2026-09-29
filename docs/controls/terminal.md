# TTyTerminalView — API 参考

## 1. 概述

`TTyTerminalView` 是终端控件：解析程序的输出（VT / xterm 转义序列）、维护屏幕和滚回、画出来，并把按键、粘贴、程序询问的应答编码成字节交给宿主。解析、缓冲和按键编码都照 xterm.js 6.0.0 移植，逐位对着 xterm.js 测过。

控件**不碰进程**：它不开 shell，也不管 PTY。宿主把程序的输出喂进来、把控件要发的字节写回 PTY，就是一个完整的终端。最小接法三行：

```pascal
Term.Write(BytesFromPty);                 // 程序的输出
Term.OnData := @TermData;                 // TermData 里把 AData 写回 PTY
Term.OnGridResize := @TermGridResize;     // TermGridResize 里改 PTY 的行列数
```

真的接 PTY 的示例在 4 期；现有的 `examples/terminal` 回放 asciicast 录制，不需要进程。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Terminal`（控件）；`tyControls.Terminal.Core`（`Core` 属性的类）、`tyControls.Terminal.Keyboard`（按键编码）、`tyControls.Terminal.Render`（渲染部件） |
| typeKey | `TyTerminal`；另有 `TyTerminalCursor`、`TyTerminalSelection`、`TyTerminalAnsi0` … `TyTerminalAnsi15`、`TyTerminalLink`、`TyTerminalPreedit` |
| 基类 | `TTyCustomControl` |
| 默认尺寸 | 480 × 300（逻辑像素） |

```pascal
uses tyControls.Terminal;
```

事件和写入回调的类型（`TTyTerminalDataEvent`、`TTyTerminalWriteDone` 等）在 `tyControls.Terminal` 里有同名别名，只 uses 这一个单元就够。

---

## 3. 属性、方法、事件

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Scrollback` | `Integer` | `1000` | 滚回行数，转给 Core。`0` 没有滚回（滚动条禁用）。上限 100000。 |
| `CursorStyle` | `TTyTerminalCursorStyle` | `tcsBlock` | 光标形状：块、下划线、竖线。程序用 DECSCUSR（`CSI n SP q`）要的形状优先。 |
| `CursorInactiveStyle` | `TTyTerminalCursorInactiveStyle` | `tcisOutline` | 失焦时的光标：空心框、实心块、竖线、下划线、不画。 |
| `CursorBlink` | `Boolean` | `False` | 光标闪烁（600 ms；放着不动 5 分钟后停在显示）。程序用 DECSCUSR 要的闪烁优先。 |
| `AmbiguousWide` | `Boolean` | `False` | 东亚歧义宽度字符算两格。只对 `UnicodeVersion` 为 `15` / `15-graphemes` 起作用。 |
| `UnicodeVersion` | `TTyUnicodeVersion` | `tuv11` | 字符宽度表：`tuv6`、`tuv11`、`tuv15`、`tuv15Graphemes`。见 §9。 |
| `MacOptionIsMeta` | `Boolean` | `False` | macOS 上 Option 当 Meta（发 `ESC` 前缀），否则 Option 打第三层字符。 |
| `AlternateScroll` | `Boolean` | `True` | 没有滚回（备用屏）且程序没要鼠标事件时，滚轮发上下方向键。 |
| `DrawBoldTextInBrightColors` | `Boolean` | `True` | 粗体的调色板颜色 0–7 画成 8–15。 |
| `ReadOnly` | `Boolean` | `False` | 不往外发字节（按键、粘贴、输入法都不发）；本地翻页照常。转给 Core。 |
| `ConvertEol` | `Boolean` | `False` | LF 当 CR LF。转给 Core。 |
| `TabStopWidth` | `Integer` | `8` | 默认制表位间隔。转给 Core。 |
| `ScrollOnUserInput` | `Boolean` | `True` | 键入、粘贴时滚到底。转给 Core。 |
| `ScrollBarAutoHide` | `TTyScrollBarAutoHide` | `sbahDefault` | 内嵌滚动条闲下来后淡出，转给条；见 [scrollbar.md](scrollbar.md) §7。 |
| `LineHeightPercent` | `Integer` | `100` | 行高倍数（100–300）。框线和块字符照样连成线。 |
| `LetterSpacing` | `Integer` | `0` | 字间距，逻辑像素（−10–50）。 |
| `TabStop` | `Boolean` | `True` | |
| `Font` / `ParentFont` | | | `ParentFont = False` 时 `Font.Name`、`Font.Size` 压过主题（见 §7）。 |

另有 `TTyCustomControl` 的通用成员（`Align`、`Anchors`、`BorderSpacing`、`Constraints`、`Enabled`、`TabOrder`、`PopupMenu`、`Hint`、`StyleClass`、`StyleOverride`、`Controller`，以及 `OnEnter` / `OnExit` / `OnKeyDown` / `OnKeyUp` / `OnUTF8KeyPress` / `OnClick` / `OnMouse*`）。

### public 属性

| 属性 | 说明 |
|------|------|
| `Core: TTyTerminalCore` | 终端本体：缓冲、模式、解析器。只读取它，或挂下面 §9 说的那几个事件。 |
| `Cols`、`Rows` | 当前网格 |
| `Title` | 程序用 OSC 0 / 2 设的标题 |

### 方法

| 方法 | 说明 |
|------|------|
| `Write(AData)`、`Write(ABuf, ACount)` | 程序的输出，只入队；控件在消息循环里分片解析。可带回调 `AOnDone`：回调到的时候，这一块和它前面的都处理完了。 |
| `WriteSync(AData)` | 先把队列里的处理完，再当场解析 `AData`。 |
| `Paste(AText)` | 按粘贴编码（换行变 CR；程序开了括号粘贴就加括号、把 ESC 换成 ␛）发出去。 |
| `Input(AText)` | 当作键入发出去。 |
| `PasteFromClipboard` | 读剪贴板再 `Paste`。 |
| `CopyToClipboard` | 复制选区。选区在 4 期，现在什么都不做。 |
| `Clear` | 清滚回。 |
| `Reset` | 终端复位（xterm.js headless 的 reset：保留标题等）。 |
| `ScrollLines(ADelta)`、`ScrollPages(APages)`、`ScrollToTop`、`ScrollToBottom` | 在滚回里移动视口。 |
| `CellAt(X, Y): TPoint` | 客户区像素 → 0 起的格子（钳在网格内）。 |
| `CellRect(ACol, ARow): TRect` | 视口里一格的矩形。 |
| `SizeForGrid(ACols, ARows): TSize` | 要这么多行列，客户区得多大（内边距、滚动条都算进去）。宿主想固定 80 × 24 就用它设尺寸。 |

### 事件

| 事件 | 说明 |
|------|------|
| `OnData(Sender, AData)` | 控件要发给程序的字节：按键、粘贴、输入法提交、对程序询问的应答。写回 PTY。 |
| `OnGridResize(Sender, ACols, ARows)` | 网格变了（客户区、字体、DPI、程序的 DECCOLM）。加载完成后的第一次排版即使没变也发一次。改 PTY 的尺寸。 |
| `OnTitleChange(Sender, AText)` | 程序设了标题。 |
| `OnBell(Sender)` | BEL。 |
| `OnOsc(Sender, AIdent, AData)` | 没有处理器接的 OSC（例如 OSC 7 当前目录）。 |
| `OnShortcutQuery(Sender, Key, Shift, var APassToApplication)` | 控件要吞一个键之前先问宿主；置 `True` 就不吞，交给窗体。见 §5。 |

---

## 4. 数据流与线程

- `Write` 只入队，控件经 `Application.QueueAsyncCall` 按片（每片约 12 ms）解析，窗口不会被一大段输出卡住。回调按写入的顺序到。
- 所有方法都只能在主线程调用；别的线程调会抛 `EInvalidOperation`。后台读 PTY 的线程要 `TThread.Queue` / `Synchronize` 回主线程再 `Write`。
- 积压超过 50 MB（宿主没做流控）时 `Write` 抛 `ETyTerminalWriteOverflow`。流控靠 `Write` 的回调：回调到了再写下一块（示例的回放器就是这样，一次只让一块在队列里）。
- `Core.DiscardPending` 丢掉还没解析的块，**不调**它们的回调——宿主自己要丢的（换一份录制、重开会话），流控计数跟着重来。
- 解析一次里程序滚了几千行，控件只在解析完后失效、同步滚动条一次；程序改了颜色（OSC 4 / 10 / 11 / 104 …）整窗重画。距上一帧不到 16 ms 时控件接着解析，不急着画。
- 事件是同步发的，发生在解析中间。在事件里调 `Core.Resize`、`Reset`、`WriteSync` 不会被拒绝，但会等这一块处理完再执行；别以为调用返回时已经生效——以 `OnGridResize` 为准。

---

## 5. 键盘

终端要把几乎所有键交给程序：方向键、功能键、Tab、Enter、Esc、Ctrl+字母、Alt+字母都会被**吞掉**并编码发出（编码照 xterm.js）。能打出字符的键（字母、数字、符号、空格）不在按下时发，而是等字符事件——这样任何键盘布局、死键、AltGr 都对。

**放行给窗体**：控件吞键之前会问 `OnShortcutQuery`。

```pascal
procedure TForm1.TermShortcutQuery(Sender: TObject; Key: Word; Shift: TShiftState;
  var APassToApplication: Boolean);
begin
  // Ctrl+Tab 留给窗体切换页签
  APassToApplication := (Key = VK_TAB) and (ssCtrl in Shift);
end;
```

**本地动作**（同样先问 `OnShortcutQuery`）：

| 动作 | Windows / Linux | macOS |
|------|-----------------|-------|
| 复制 | Ctrl+Shift+C、Ctrl+Insert | Cmd+C |
| 粘贴 | Ctrl+Shift+V、Shift+Insert | Cmd+V |
| 翻页（滚回） | Shift+PgUp / Shift+PgDn（一次 行数 − 1） | 同左 |
| 到顶 / 到底 | Shift+Home / Shift+End | 同左 |

- Shift+Home / Shift+End 是本地的「到顶 / 到底」，所以不发给程序——PSReadLine、nano 里用它们选到行首 / 行尾的，在这个终端里做不到（xterm.js 不劫持这两个键，这是有意的不同）。
- Ctrl+C 永远发给程序（`03`），不是复制。
- Alt+字母发 `ESC` + 字母。macOS 上 Option 默认打第三层字符（`MacOptionIsMeta = False`）；设成 `True` 才发 `ESC` 前缀。
- Windows 上 AltGr（等于 Ctrl+Alt）打的是布局上的字符，不发 `ESC`。
- 应用小键盘模式（DECKPAM）不影响小键盘：数字和运算符一律发字符，和 xterm.js 一样。
- 输入法：提交的文字当作键入发出；候选窗跟着光标格。macOS 上组字串画在光标处，取消组字什么都不发。
- 焦点跟的是系统焦点：切到别的程序也算失焦——光标变成失焦样式、停止闪烁，程序开了 1004 就收到 `CSI O`。
- Kitty 键盘协议、win32-input-mode 控件不编码，所以程序问的时候也不报支持（宿主改了 `Core.VtExtensions` 也会被关掉）。

---

## 6. 滚回与滚动条

- 右侧是内嵌的 `TTyScrollBar`，跟着滚回走；拖动它就在滚回里移动。备用屏（vim、less、htop）没有滚回，条禁用。
- **条的宽度总是留着**：列数不随主屏 / 备用屏变化，进出 vim 不会让程序多收一次改尺寸。代价是全屏程序右边有一条空白（自动隐藏的主题下条淡掉，只剩空白）。
- 竖向滚轮三种去向（照 xterm.js）：程序要了鼠标滚轮事件就上报给程序；否则有滚回就滚 3 行；再否则（备用屏）且 `AlternateScroll` 开着，就发上 / 下方向键——less、man 里滚轮就能翻。
- Shift+滚轮照 xterm.js：不上报、不发方向键；Windows / Linux 上它是横滚（终端没有横向可滚，事件交给父控件），macOS 上照常滚滚回。

---

## 7. 状态与主题

| typeKey | 用到的属性 |
|---------|-----------|
| `TyTerminal` | `background`（底色，调色板 257）、`color`（前景，256）、`font-size`、`padding`、边框（默认无边框） |
| `TyTerminal:disabled` | `opacity`：禁用时整块（字、底色、内边距、外框）按它朝父控件底色淡下去；程序问颜色（OSC 10 / 11）仍答原色 |
| `TyTerminalCursor` | `background`（光标色，258）、`color`（块光标下的字） |
| `TyTerminalSelection`、`:focus` | `background`（选区，4 期用） |
| `TyTerminalAnsi0` … `TyTerminalAnsi15` | `color`：16 色 |
| `TyTerminalLink` | `color`（链接，4 期用） |
| `TyTerminalPreedit` | `background`、`color`、`border-color`（组字串的底、字、下划线） |

token（`light.tycss` 基础层，所有皮肤继承）：

| token | 默认 |
|-------|------|
| `--terminal-bg` / `--terminal-fg` | `var(--surface)` / `var(--on-surface)` |
| `--terminal-cursor` / `--terminal-cursor-ink` | `var(--on-surface)` / `var(--terminal-bg)` |
| `--terminal-selection-bg` / `--terminal-selection-bg-inactive` | 半透明强调色 / 半透明前景 |
| `--terminal-link` | `var(--accent)` |
| `--terminal-ansi-0` … `--terminal-ansi-15` | 见下 |
| `--terminal-font-family` / `--terminal-font-family-wide` | `monospace` / `monospace-wide` |
| `--terminal-pad` | `4px`（现代密度 `8px`） |
| `--terminal-cursor-width` / `--terminal-underline-width` | `1px` |

**16 色**：每个只写一处，`on(var(--terminal-bg), 浅底值, 深底值)`。深底是 xterm.js 的 Tango 原值；浅底那套用 xterm.js 自己的对比度算法把同一色相压暗，直到对白底 4.5:1（黑、白和它们的亮色 0 / 7 / 8 / 15 不动）。皮肤想要自己的配色，改这 16 个 token 就行。

颜色表按**这个实例**的样式取（`StyleClass`、`StyleOverride`），不跟悬停、聚焦走。一个实例单独换了深底（`StyleOverride := 'background: #101010; color: #e0e0e0'`，或者一个写了深底的类），16 色跟着换成深底那套——控件拿它的底色把 token 再求一次；类里另写了某一色就用那一色。光标色、光标下的字色默认就是前景、底色，也跟着实例走。

自己的皮肤里若改写了 `TyTerminal` 规则，基础层的 `TyTerminal:disabled` 就不再继承，要连它一起写，否则禁用时不变淡。

**字体**：`--terminal-font-family` 由控件原样读（不经 `var()` 求值），`monospace` 换成平台等宽字体（Windows `Consolas`、macOS `Menlo`、Linux `Monospace`）。宽字符（CJK）默认交给系统的字体替换；`--terminal-font-family-wide` 写一个字体名就专门用它画宽字符，`monospace-wide` 在 macOS / Linux 换成 `PingFang SC` / `Noto Sans CJK SC`，Windows 上是空（Consolas 经系统字体链接本来就把中文画在两格里）。

字体的来源顺序：**`StyleOverride` 里的 `font-family` / `font-size` > `ParentFont = False` 时的 `Font` > `TyTerminal` 规则 > token**。`Font.Name = 'default'` 当没设。

```css
/* 自己的皮肤里给终端换一套深色 */
:root {
  --terminal-bg: #1e1e1e;
  --terminal-fg: #d4d4d4;
  --terminal-font-family: "Cascadia Mono";
}
```

---

## 8. 代码示例

**回放一份录制**（`examples/terminal` 的简化版）：一次只让一块在队列里，回调到了再写下一块——大录制「一次喂完」也不会撑爆队列。

```pascal
procedure TForm1.WriteNextChunk;
begin
  if FInFlight or (FNext >= Cast.Count) then Exit;
  FInFlight := True;
  Term.Write(Cast[FNext].Data, @ChunkDone, FNext);   // 只入队；控件在消息循环里解析、画
  Inc(FNext);
end;

procedure TForm1.ChunkDone(Sender: TObject; ATag: PtrInt);
begin
  FInFlight := False;
  WriteNextChunk;
end;
```

**宿主接 PTY 的骨架**（伪接口；4 期示例有真实现）：

```pascal
procedure TForm1.PtyOutput(const ABytes: RawByteString);   // 已切回主线程
begin
  Term.Write(ABytes);
end;

procedure TForm1.TermData(Sender: TObject; const AData: RawByteString);
begin
  Pty.WriteBytes(AData);
end;

procedure TForm1.TermGridResize(Sender: TObject; ACols, ARows: Integer);
begin
  Pty.Resize(ACols, ARows);
end;
```

---

## 9. 注意事项

- **Unicode 版本**：默认 `11`。要字形簇（表情修饰符、ZWJ 序列按一个字算）选 `15-graphemes`。**`15` 不连接组合符**：`e` + U+0301 在 `15` 下占 2 格（组合符自占一格），在 `6` / `11` / `15-graphemes` 下占 1 格。
- **`AmbiguousWide` 只对 `15` / `15-graphemes` 起作用**；打开后，U+0301 这类在表里本身是歧义宽度的组合符也算宽：`é`（e + U+0301）在 `15` 下占 **3** 格，在 `15-graphemes` 下占 **2** 格（照 xterm.js）。
- **控件接管了 Core 的这些事件，宿主不要改写**：`OnData`、`OnRefreshRows`、`OnTitleChange`、`OnBell`、`OnCursorMove`、`OnScroll`、`OnBufferActivate`、`OnModesChange`、`OnOsc`、`OnQueryBaseColor`、`OnProcessRequest`、`OnWindowOptionsReport`、`OnResize`、`OnScrollbackCleared`。宿主可以自己挂 `Core.OnIconNameChange`、`Core.OnLineFeed`、`Core.OnRequestScrollToBottom`（只是通知，Core 自己会滚到底），或用 `Core.Parser.Register*Handler` 加自己的序列处理器。
- 换主题时只有颜色表真变了（换明暗、换配色）才告诉程序（开了 2031 就报明暗），同时丢掉程序用 OSC 设过的颜色；只改了内边距、字体的主题变化不算。
- 第一次画一屏新字形时，每一帧只花约 10 ms 画新字形，剩下的下一帧补上（Windows 上一个字形约 2 ms）；之后都从缓存里取。
- REP（`CSI b`）重复次数极大时按周期快进，被跳过那段滚动的 `Core.OnScroll` 不发。
- 窗口尺寸应答（`CSI 14 t` / `16 t`）和 SGR 像素鼠标报的是**设备像素**（xterm.js 报 CSS 像素）。
- **表情**：Windows 上彩色表情画成单色轮廓（GDI 文字管线不画彩色字形），宽度照字符宽度表算。Powerline 私用区字形（U+E0A0、U+E0B0 等）要字体里有才画得出来。
- 颜色 token 的透明度会被丢掉：终端的底色、前景、16 色都按不透明画。

---

## 10. 本期限制 / 后续

- 鼠标按键上报、本地选择与复制、右键菜单、Linux PRIMARY、OSC 52、链接：4 期。
- 拖窗口时长行不重新折行（程序会按新宽度重画）：5 期。
- 最低对比度（`MinimumContrastRatio`）、盲文 / Powerline 自绘：5 期。
