# TTyTerminalView — API 参考

## 1. 概述

`TTyTerminalView` 是终端控件：解析程序的输出（VT / xterm 转义序列）、维护屏幕和滚回、画出来，并把按键、粘贴、程序询问的应答编码成字节交给宿主。解析、缓冲和按键编码都照 xterm.js 6.0.0 移植，逐位对着 xterm.js 测过。

控件**不碰进程**：它不开 shell，也不管 PTY。宿主把程序的输出喂进来、把控件要发的字节写回 PTY，就是一个完整的终端。最小接法三行：

```pascal
Term.Write(BytesFromPty);                 // 程序的输出
Term.OnData := @TermData;                 // TermData 里把 AData 写回 PTY
Term.OnGridResize := @TermGridResize;     // TermGridResize 里改 PTY 的行列数
```

`examples/terminal` 有两种模式：回放 asciicast 录制（不需要进程），以及「Shell」——真起一个 shell，Windows 上经 ConPTY，Linux / macOS 上经 PTY。接 PTY 的做法见 §11。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Terminal`（控件）；`tyControls.Terminal.Core`（`Core` 属性的类）、`tyControls.Terminal.Keyboard`（按键编码）、`tyControls.Terminal.Render`（渲染部件）、`tyControls.Terminal.Selection`（选区）、`tyControls.Terminal.Links`（链接）、`tyControls.Terminal.ColorScheme`（配色方案，读写 Windows Terminal 配色） |
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
| `CursorStyle` | `TTyTerminalCursorStyle` | `tcsBlock` | 光标形状：块、下划线、竖线。这是默认值：程序可以用 DECSCUSR（`CSI Ps SP q`，`Ps` 为 0–6）临时要别的形状（比如 vim 的插入模式要竖线），`CSI 0 SP q` 回到这里设的，RIS（`ESC c`）也回到这里。 |
| `CursorInactiveStyle` | `TTyTerminalCursorInactiveStyle` | `tcisOutline` | 失焦时的光标：空心框、实心块、竖线、下划线、不画。 |
| `CursorBlink` | `Boolean` | `False` | 光标闪烁（600 ms；放着不动 5 分钟后停在显示）。同样是默认值：DECSCUSR 的奇数 / 偶数 `Ps` 临时要闪 / 不闪，`CSI 0 SP q` 和 RIS 回到这里设的。 |
| `AmbiguousWide` | `Boolean` | `False` | 东亚歧义宽度字符算两格。只对 `UnicodeVersion` 为 `15` / `15-graphemes` 起作用。 |
| `UnicodeVersion` | `TTyUnicodeVersion` | `tuv11` | 字符宽度表：`tuv6`、`tuv11`、`tuv15`、`tuv15Graphemes`。见 §12。 |
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
| `MinimumContrastRatio` | `Double` | `1` | 最低对比度（同 xterm.js 的 `minimumContrastRatio`）。`1` 不调；大于 1 时把字色往亮或往暗推，直到和画出来的底色达到这个比值。写入时钳到 1–21、保留一位小数。只调前景；暗淡的字按一半算。框线、块元素、Powerline 符号、块光标下的字、链接下划线、自带颜色的下划线不调。见 §10。 |
| `ColorSource` | `TTyTerminalColorSource` | `tsrcTheme` | 颜色从哪来：`tsrcTheme` 跟随主题，`tsrcScheme` 用下面的配色方案。见 §10。 |
| `ColorScheme` | `TTyTerminalColorScheme` | 空方案 | 自定义配色方案；开了 `ColorSchemePaired` 时是浅色那套。在对象查看器里展开改，只有改过的项写进 `.lfm`。赋值是复制（`Assign`）；赋 `nil` 抛 `EConvertError`，和 `Font := nil` 一样——要清空用 `ColorScheme.Clear`。 |
| `ColorSchemePaired` | `Boolean` | `False` | 明暗各一套：主题的底色是浅的用 `ColorScheme`，深的用 `DarkColorScheme`，换明暗时自动换。 |
| `DarkColorScheme` | `TTyTerminalColorScheme` | 空方案 | 配对时深色主题用的那套。 |
| `SelectionOverrideKey` | `TTyTerminalSelectionOverrideKey` | `tsoDefault` | 程序接管鼠标时，按住哪个键照样本地选择：`tsoDefault`（macOS 上是 Option，别处 Shift）、`tsoShift`、`tsoAlt`、`tsoNone`。见 §7。 |
| `WordSeparators` | `string` | 空格和 `` ()[]{}',"` `` | 双击选词时算分隔符的字符（同 xterm.js）。 |
| `CopyOnSelect` | `Boolean` | `False` | 选完（松开、双击、三击、全选）就写剪贴板。 |
| `DetectUrls` | `Boolean` | `True` | 认出输出里的网址当链接。OSC 8 链接不受它管。见 §8。 |
| `AllowNonHttpLinks` | `Boolean` | `False` | OSC 8 里不是 http / https 的 URI（`file://`、`ssh://`）也算链接。见 §8。 |
| `Osc52` | `TTyTerminalOsc52Policy` | `to52Off` | 程序能不能经 OSC 52 碰剪贴板：`to52Off`、`to52Write`、`to52ReadWrite`。见 §9。 |
| `PopupMenu` | `TPopupMenu` | `nil` | 设了就代替内置的右键菜单。 |
| `TabStop` | `Boolean` | `True` | |
| `Font` / `ParentFont` | | | `ParentFont = False` 时 `Font.Name`、`Font.Size` 压过主题（见 §10）。 |

**配色方案对象** `TTyTerminalColorScheme`（`ColorScheme`、`DarkColorScheme` 的类型）的 published 属性，每项的默认值都是 `clNone`（未设置）：

| 属性 | Windows Terminal 的键 | 未设置时 |
|------|------|------|
| `Name` | `name` | 只用来显示和写出 |
| `Foreground` / `Background` | `foreground` / `background` | 主题的前景 / 底色 |
| `CursorColor` | `cursorColor` | 生效的前景 |
| `CursorText` | —（WT 没有） | 生效的底色 |
| `SelectionBackground` | `selectionBackground` | 主题的聚焦选区色 |
| `SelectionInactiveBackground` | —（WT 没有） | 设了 `SelectionBackground` 就用它，否则主题的失焦选区色 |
| `Black` `Red` `Green` `Yellow` `Blue` `Purple` `Cyan` `White`、`BrightBlack` … `BrightWhite` | 同名小驼峰（`purple` / `brightPurple`，读时也认 `magenta` / `brightMagenta`） | 主题的那一色 |

`clDefault` 也当未设置；`clWindow` 这类系统色用的时候换成当前平台的 RGB。方案里存的是系统色本身，用户改了系统配色以后再设一次同样的值什么都不会发生（值没变）；这时调 `Term.ColorScheme.Changed`（配对时还有 `Term.DarkColorScheme.Changed`），终端就按新的系统色重画。方案对象的方法：

| 方法 | 说明 |
|------|------|
| `LoadFromText(AText, AName)`、`LoadFromFile(AFileName, AName)` | 读一套 Windows Terminal 配色（格式见 §10）。失败抛 `ETyTerminalColorSchemeError`（`Key` 是出错的键），方案不变。 |
| `TryLoadFromText`、`TryLoadFromFile` | 同上，不抛：返回 `False` 和消息。 |
| `SaveToText`、`SaveToFile` | 写成一个 Windows Terminal 方案对象。没有名字或 16 色不全时报错。 |
| `ListSchemeNames(AText)`（类方法） | 文本里有哪几套（按出现的顺序）。 |
| `Assign`、`Clear`、`IsEmpty`、`Equals`、`Colors[ASlot]` | 复制、清空、是不是全没设、比较、按槽取色。 |
| `BeginUpdate` / `EndUpdate` | 一次改多个颜色，终端只重算一次。 |
| `Changed` | 内容没变也算改了一次：终端重新取色、重画。给系统色用（见下）。 |

另有 `TTyCustomControl` 的通用成员（`Align`、`Anchors`、`BorderSpacing`、`Constraints`、`Enabled`、`TabOrder`、`Hint`、`StyleClass`、`StyleOverride`、`Controller`，以及 `OnEnter` / `OnExit` / `OnKeyDown` / `OnKeyUp` / `OnUTF8KeyPress` / `OnClick` / `OnMouse*`）。

### public 属性

| 属性 | 说明 |
|------|------|
| `Core: TTyTerminalCore` | 终端本体：缓冲、模式、解析器。只读取它，或挂下面 §12 说的那几个事件。 |
| `Core.ReflowCursorLine` | 改列数重新折行时，光标所在的那段也折。默认 `False`（同 xterm.js：程序收到改尺寸会自己重画那一行）。 |
| `Cols`、`Rows` | 当前网格 |
| `Title` | 程序用 OSC 0 / 2 设的标题 |
| `SelectionText` | 选中的文字（规则见 §7）；没有选区是空串 |
| `HasSelection` | 有没有选区 |

### 方法

| 方法 | 说明 |
|------|------|
| `Write(AData)`、`Write(ABuf, ACount)` | 程序的输出，只入队；控件在消息循环里分片解析。可带回调 `AOnDone`：回调到的时候，这一块和它前面的都处理完了。 |
| `WriteSync(AData)` | 先把队列里的处理完，再当场解析 `AData`。 |
| `Paste(AText)` | 按粘贴编码（换行变 CR；程序开了括号粘贴就加括号、把 ESC 换成 ␛）发出去。 |
| `Input(AText)` | 当作键入发出去。 |
| `PasteFromClipboard` | 读剪贴板再 `Paste`。 |
| `CopyToClipboard` | 有选区才写剪贴板（`SelectionText`）。 |
| `SelectAll`、`ClearSelection` | 全选（滚回加屏幕）、清掉选区。 |
| `Select(ACol, AAbsRow, ALength)` | 从缓冲行 `AAbsRow`（0 = 滚回最早一行）的 `ACol` 列起选 `ALength` 格，可以跨行。 |
| `SelectLines(AFirst, ALast)` | 选中缓冲行 `AFirst`..`ALast` 整行（越界钳住）。 |
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
| `OnSelectionChange(Sender)` | 选区变了（包括被清掉）。 |
| `OnLinkActivate(Sender, AUri, AFromOsc8)` | 用户 Ctrl+单击（macOS Cmd+单击）了一条链接。控件什么都不打开，打不打开由宿主定。见 §8。 |
| `OnOsc52(Sender, AWrite, ASelection, var AText, var AAllow)` | 程序要写或读剪贴板，宿主可以改文字、可以拒绝。见 §9。 |

---

## 4. 数据流与线程

- `Write` 只入队，控件经 `Application.QueueAsyncCall` 按片解析，窗口不会被一大段输出卡住。输出一直排着时，解析加绘制一轮约 50 ms：一片的时间是 50 ms 减去上一帧画了多久，至少 3 ms；到点先把这一帧画上（等不到消息循环：排片的消息一直在，Windows 不会给 `WM_PAINT`），再排下一片。所以大段输出时画面约 20 帧每秒，两次绘制隔 50–85 ms。Windows 上有按键、鼠标按键在排队时，下一片等它们处理完。回调按写入的顺序到。
- 一次很大的 `Write`（几十 MB 一块）也不会一口气解析完：块内按 32 KB 分段，段与段之间看时间，到点就让出。回调要等整块处理完才到；`Core.PendingBytes` 按段往下减。还有输出排着的时候，一帧画新字形的预算从 10 ms 降到 4 ms（这时的行很快就滚走了）。
- 宿主做流控，推荐高低水位：已写入、回调还没到的字节超过高水位就停止读 PTY，回调把它降到低水位以下再接着读（示例的 `uptysession.pas`）。
- 所有方法都只能在主线程调用；别的线程调会抛 `EInvalidOperation`。后台读 PTY 的线程把读到的东西放进加锁的队列，回到主线程再 `Write`——示例的 `uptysession` 就是这么做的：队列从空变成非空时唤醒主线程一次（`Application.QueueAsyncCall`），不是每读一块唤醒一次。
- 积压超过 50 MB（宿主没做流控）时 `Write` 抛 `ETyTerminalWriteOverflow`。流控靠 `Write` 的回调：回调到了再写下一块（示例的回放器就是这样，一次只让一块在队列里）。
- `Core.DiscardPending` 丢掉还没解析的块（连同解析了一半的那块），**不调**它们的回调——宿主自己要丢的（换一份录制、重开会话），流控计数跟着重来。释放控件时，队列里没处理的块也不再回调。
- 解析一次里程序滚了几千行，控件只在解析完后失效、同步滚动条一次；程序改了颜色（OSC 4 / 10 / 11 / 104 …）整窗重画。输出排着时，一轮（约 50 ms）没到控件接着解析，不急着画。
- 事件是同步发的，发生在解析中间。在事件里调 `Core.Resize`、`Reset`、`WriteSync` 不会被拒绝，但会等这一块处理完再执行（大块切了段也一样：等最后一段、回调之后，不在段与段之间）；别以为调用返回时已经生效——以 `OnGridResize` 为准。

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
| 全选 | —（Ctrl+A 发给程序；用右键菜单） | Cmd+A |

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
- 横向滚轮（触控板、带横滚的鼠标）：程序要了鼠标事件就报左 / 右（SGR 里是 66 / 67）；没要就交给父控件。

**改宽度重新折行**（照 xterm.js）：列数变了，主缓冲按新宽度重新折行——长行折回、改宽了再接回去，宽字符不劈开，颜色、链接、标记跟着字走。

- 什么时候折：主缓冲、有滚回，并且没设 `Core.WindowsPty`，或者设了且是 21376 及以后的 ConPTY。21376 之前的 ConPTY 自己会按新宽度重画，所以不折（窗口改窄后留下的长行照旧），走 xterm.js 的老办法。备用屏（vim、less、htop）不折。
- 光标所在的那段折行默认不动：提示符后正在打的长命令，拖宽后仍是两行，等 shell 自己重画。要一起折，设 `Core.ReflowCursorLine := True`。
- 这一次会重新折行，就清掉选区（字挪了，选区还框着原来的格子会复制出别的字）；不折的时候（老 ConPTY、备用屏）照 xterm.js 保留。
- 滚动条的范围和拇指跟着新的行数走；指针下悬停的链接先取消，指针再动时在新位置重新找。
- **拖窗口时合并**：控件有窗口时，客户区一变，新网格等到消息循环里才生效，只按最后的尺寸改一次（1 万行滚回的重新折行一次要几十毫秒）；`OnGridResize` 也在那时发。问几何的入口（`Cols`、`Rows`、`CellAt`、`CellRect`、`SizeForGrid`）和 `WriteSync` 会先让它生效。`Write`、`Input`、`Paste` 不会——拖动时程序每收到一次改尺寸就会输出，它们一应用就成了每一步都折一次。所以排着的时候 `Core` 还是旧网格（`Core.Cols` 是旧的），这时写进来的输出按旧网格解析，生效时一起折。还没有窗口（隐藏的控件）时照旧当场改；控件释放时不再应用。

---

## 7. 鼠标与选区

**谁拿鼠标**：程序没要鼠标事件时，鼠标归控件——拖动选择、双击选词、右键菜单。程序（vim `:set mouse=a`、htop、tmux、mc）打开了鼠标上报，按键、拖动、移动、滚轮就按程序要的协议报给它，拖出控件外也照报（坐标钳在网格边上）。这时按住**覆盖键**（默认 Shift，macOS 上是 Option；见 `SelectionOverrideKey`）再按，就还是本地选择。

| 按下时 | 这次按下走哪 |
|--------|--------------|
| 按着 Ctrl（macOS Cmd），指针下是链接 | 链接（§8），程序接管了鼠标也一样 |
| 程序要了鼠标，没按覆盖键 | 报给程序；拖动、抬起都报 |
| 左键 | 本地选择 |
| 右键 | 弹菜单（程序要了鼠标时，右键报给程序、不弹；按住覆盖键就弹） |
| 中键 | Linux（X11）上粘贴 PRIMARY；Windows、macOS 上什么都不做 |

路在按下那一刻就定了：拖到一半松开覆盖键，这次拖动还是本地选择。

**怎么选**（同 xterm.js）：

- 单击拖动选字符；点在一格的右半边，从下一格算起。
- 双击选词，词按 `WordSeparators` 断，折行处上下接着选；指针下是链接（OSC 8 或认出的网址）就选整条链接。三击选整行（折了几行都算一行）。双击、三击后接着拖，按词、按行扩展。
- Shift+单击把选区扩到这里（程序接管鼠标时 Shift 是覆盖键，就不扩展了）。
- Alt+拖动选矩形（列选择）；macOS 上 Alt 是覆盖键，就不做列选择。
- 拖出网格上下边会自动滚，离得越远滚得越快。
- 键盘全选：macOS 上 Cmd+A。别的平台 Ctrl+A 照发给程序（`01`），要全选用右键菜单或 `SelectAll`。

**选区跟着文字走**：新的输出把行挤出滚回的顶上时，选区跟着上移；它指的那几行被挤没了，选区就没了。这些时候选区会被清掉：键入或粘贴、行数变了、列数变了且这次重新折行（§6）、切到另一个屏幕（进出 vim、RIS）、程序打开鼠标上报、清滚回。

**复制**：`SelectionText` 去掉每行行尾的空白，折行接成一行，行之间用平台的换行（Windows 上 CRLF，Linux / macOS 上 LF），NBSP 换成空格。复制的快捷键见 §5；`CopyOnSelect` 打开后选完就写剪贴板。Linux（X11）上选完同时占住 PRIMARY，文字等别的程序来要时才取（大选区松手时不拼文字），中键粘贴它（Wayland 下看合成器支不支持）。

**抬起丢了**：按下之后捕获被别处拿走（切换窗口、弹出模态框），或者抬起落在别的窗口上，控件等到那个键确实松开了（或下一次按同一个键时）就照松开收尾：选区照常结束，程序会收到补发的抬起。

**右键菜单**：复制、粘贴、全选、清屏四项；没有选区时复制是灰的，剪贴板里没有文字或 `ReadOnly` 时粘贴是灰的（只问有没有文字，不把剪贴板读出来）。菜单键在光标格下面弹出。Shift+F10 是有编码的键，照常先发给程序；之后还弹不弹菜单看 widgetset，待真机确认。宿主设了 `PopupMenu` 就弹宿主的；macOS 上右键先选中指针下的词，宿主的菜单也一样。

**指针形状**：平常是 I 形；程序接管鼠标时是箭头；按着 Alt 要列选择时是十字；链接上是手形。宿主自己设了 `Cursor` 的，平常就用宿主的。

---

## 8. 链接

链接有两种来源：程序用 OSC 8 标出来的超链接（`ls --hyperlink`、gcc 的诊断等），和控件从文字里认出来的网址（`DetectUrls`，认法同 xterm.js 的 web-links 插件：`http://` / `https://` 开头，结尾的标点、括号不算，主机是非 ASCII 的不算）。

- **按住 Ctrl（macOS Cmd）**时指针下的链接画下划线、指针变手形；不按就是普通文字。
- **Ctrl+单击**（按下、抬起都在同一条链接上）发 `OnLinkActivate`，`AUri` 是原样的 URI 或网址。程序接管了鼠标也是链接优先。
- **控件什么都不打开。**宿主决定：弹个确认框再交给浏览器（示例就是这样，而且只开 http / https），或者干脆不理。
- OSC 8 的 URI 不是 http / https（`file://`、`ssh://`、`mailto:`）默认**不算链接**：不画下划线、点了没反应（xterm.js 的默认也是这样）。设 `AllowNonHttpLinks := True` 才算，这时宿主要自己判断能不能打开。
- 双击链接会选中整条，不用按 Ctrl。
- xterm.js 的链接悬停不用按键、单击就打开；这里要 Ctrl / Cmd，是有意的不同：终端里的单击要留给选择和程序。

---

## 9. 剪贴板与 OSC 52

程序可以用 OSC 52 写剪贴板、读剪贴板（tmux 的 `set-clipboard`、vim 的 osc52 插件）。读剪贴板等于让程序（也可能是 ssh 那头的程序）看到你复制过的东西，所以默认关着。

| `Osc52` | 写 | 读 |
|---------|----|----|
| `to52Off`（默认） | 丢掉 | 丢掉，不应答 |
| `to52Write` | 先问 `OnOsc52`（`AAllow` 默认 `True`），再写剪贴板 | 丢掉，不应答 |
| `to52ReadWrite` | 同上 | 问 `OnOsc52`，`AAllow` 默认 `False`：宿主明确同意才应答；没挂事件就是不同意 |

- 事件在解析中间同步发，宿主可以在里面弹模态框问用户，应答的顺序不会乱；但**不能在事件里释放控件**（也不能做会释放它的事，比如关掉它所在的窗体）。事件或剪贴板（别的程序占着时会抛）抛出的异常由控件吞掉，这一条 OSC 52 作罢，后面的输出照常解析。
- `AText` 写的时候是解出来的文字（坏的 base64 解成空串，同 xterm.js），读的时候是剪贴板现在的内容；宿主都可以改。
- `ASelection` 是程序给的剪贴板名（`c`、`p` …）原样，控件不按它选剪贴板。
- 应答不算键入：不清选区，不滚到底。

---

## 10. 状态与主题

| typeKey | 用到的属性 |
|---------|-----------|
| `TyTerminal` | `background`（底色，调色板 257）、`color`（前景，256）、`font-size`、`padding`、边框（默认无边框） |
| `TyTerminal:disabled` | `opacity`：禁用时整块（字、底色、内边距、外框）按它朝父控件底色淡下去；程序问颜色（OSC 10 / 11）仍答原色 |
| `TyTerminalCursor` | `background`（光标色，258）、`color`（块光标下的字） |
| `TyTerminalSelection`、`:focus` | `background`：选区颜色，失焦 / 聚焦两种，可以半透明——先在主题底色上混成不透明，再**替换**选中格的底色（反显格、亮底色格上的选区一样看得见，同 xterm.js）；宽字符按它的第一列算，整字选中或整字不选；`color`：选中的字换成这个色，**写了才用**，不写就保持原色 |
| `TyTerminalAnsi0` … `TyTerminalAnsi15` | `color`：16 色 |
| `TyTerminalLink` | `color`：悬停链接的下划线 |
| `TyTerminalPreedit` | `background`、`color`、`border-color`（组字串的底、字、下划线） |

token（`light.tycss` 基础层，所有皮肤继承）：

| token | 默认 |
|-------|------|
| `--terminal-bg` / `--terminal-fg` | `var(--surface)` / `var(--on-surface)` |
| `--terminal-cursor` / `--terminal-cursor-ink` | `var(--on-surface)` / `var(--terminal-bg)` |
| `--terminal-selection-bg` / `--terminal-selection-bg-inactive` | 半透明强调色（0.35）/ 半透明前景（0.3，同 xterm.js 默认选区的透明度） |
| `--terminal-link` | `var(--accent)` |
| `--terminal-ansi-0` … `--terminal-ansi-15` | 见下 |
| `--terminal-font-family` / `--terminal-font-family-wide` | `monospace` / `monospace-wide` |
| `--terminal-pad` | `4px`（现代密度 `8px`） |
| `--terminal-cursor-width` / `--terminal-underline-width` | `1px` |

**16 色**：每个只写一处，`on(var(--terminal-bg), 浅底值, 深底值)`。深底是 xterm.js 的 Tango 原值；浅底那套用 xterm.js 自己的对比度算法把同一色相压暗，直到对白底 4.5:1（黑、白和它们的亮色 0 / 7 / 8 / 15 不动）。皮肤想要自己的配色，改这 16 个 token 就行。

**最低对比度**：浅底那套 16 色是按纯白底调的。皮肤的浅底不是纯白时（xp、macos、breeze 的底色偏灰），3 号黄这类颜色对底色只有 3.7–4.0:1。设 `MinimumContrastRatio := 4.5` 兜底：字色按 xterm.js 的算法再压一压，每个内置主题的彩色（1–6、9–14 号）都能到 4.5:1。比的是**画出来的**两个颜色：选中的格对选区色比，主题给了选区字色就调那个字色；反显的默认色是主题底色画在主题前景上（同 xterm.js 的 WebGL 渲染器）。暗淡的字按一半的比值调，调过的颜色直接画、不再变淡（同 xterm.js）；不用调的照常变淡。没有字也没有线的空格子不调。换主题、改比值时缓存一起清；缓存最多记 16384 对颜色，满了从头记。

颜色表按**这个实例**的样式取（`StyleClass`、`StyleOverride`），不跟悬停、聚焦走。一个实例单独换了深底（`StyleOverride := 'background: #101010; color: #e0e0e0'`，或者一个写了深底的类），16 色跟着换成深底那套——控件拿它的底色把 token 再求一次；类里另写了某一色就用那一色。光标色、光标下的字色默认就是前景、底色，也跟着实例走。

自己的皮肤里若改写了 `TyTerminal` 规则，基础层的 `TyTerminal:disabled` 就不再继承，要连它一起写，否则禁用时不变淡。

禁用时选区色（已经混成不透明）、链接色和别的颜色一样朝父控件底色淡下去。

**独立配色方案**：`ColorSource := tsrcScheme` 后，这个终端不再跟主题的配色，改用 `ColorScheme`。

- 优先级：**程序用 OSC 设的颜色 > 方案里设了的 > 主题**。方案里没设的项照样跟主题，一套全空的方案画出来和跟随主题一样。
- 选区按 xterm.js 的做法：方案的选区色降到 0.3 的透明度，再在底色上混成不透明。
- `ColorSchemePaired := True` 时，主题是浅的用 `ColorScheme`、深的用 `DarkColorScheme`。深浅看这个实例跟随主题时的底色，规则和 tycss 的 `on()` 一样（Rec.601 亮度大于 0.5 算浅），所以单模式的深色皮肤、自己调深的 `--terminal-bg` 也算深。
- 换方案、改方案里正在用的颜色，和换主题一样：程序用 OSC 设过的颜色被丢掉，开了 2031 就报一次明暗。宿主在一个事件里连着改几项，程序只收到一条。改没用到的那一套不重画。
- 禁用时变淡、`MinimumContrastRatio` 照旧对画出来的颜色起作用，程序问颜色（OSC 10 / 11、996）答的是方案的颜色。
- 链接下划线、外框、滚动条仍然跟主题；输入法组字串的底色和字色用方案的底色、前景，下划线跟主题。
- 浅底上 16 色看不清时，可以换一套方案（Windows Terminal 自带的 Tango Light、Solarized Light、One Half Light），或者打开最低对比度。
- 方案只设了底色（或前景、底色），16 色没设时，16 色跟的是**主题**，不看方案的底：浅色主题下就是给浅底配的那套。所以在浅色主题下给方案设一个深底，暗的几色（0 黑、4 蓝这类）落在深底上会看不清；反过来也一样。底色和 16 色要一起设，或者打开最低对比度。
- Windows Terminal 自带的「Tango Dark」和深色主题下的默认 16 色只差 0 号（WT 是 `#000000`，xterm.js 是 `#2e3436`），前景和底色本来就不同，所以两者看起来不一样。

**读写 Windows Terminal 配色**：`LoadFromText` / `LoadFromFile` 认两种文本：

- 单个方案对象（Windows Terminal 配色文档里的形状，也是 `iTerm2-Color-Schemes` 仓库 `windowsterminal/` 目录里每个文件的形状）：`name` 可以没有。
- Windows Terminal 的 `settings.json`：按 `AName` 在 `schemes` 里取，名字区分大小写，同名的取第一个 16 色齐全的；`AName` 为空时 `schemes` 里得恰好一套完整的。别的方案里写坏的颜色不影响这一套。

注释（`//`、`/* */`）、尾逗号、UTF-8 BOM 都认；UTF-16 的文件要先存成 UTF-8。大于 16 MB 的文件不读，方括号、花括号嵌套超过 64 层的当坏 JSON（不这样的话，一个很深的文件会撑爆解析器的栈、整个程序崩掉）。16 色必须齐（`purple` 缺了看 `magenta`）；颜色只收 `#rgb`、`#rrggbb`；`foreground`、`background`、`cursorColor`、`selectionBackground` 缺了按 Windows Terminal 的缺省补（白、黑、白、白），读进来的颜色和它在 Windows Terminal 里一样。不认识的键不管；重复的键报错。

出错时抛 `ETyTerminalColorSchemeError`，消息说哪个键、什么值；`Try*` 版本不抛。读失败时方案原样不动。

`SaveToText` 写出的样子和 Windows Terminal 自己写的一样（键的顺序、`#RRGGBB` 大写），可以直接放进它的 `schemes`。`CursorText`、`SelectionInactiveBackground` 在 Windows Terminal 里没有，不写。

方案从哪来：Windows Terminal 自带的在它的 `defaults.json` 里（`examples/terminal/colorschemes/windows-terminal.json` 是其中七套的原样一份）；`mbadolato/iTerm2-Color-Schemes` 的 `windowsterminal/` 目录里有几百套，每个文件都能直接「导入」，但那个仓库的 MIT 只管整个集合，单套方案的版权归各自的作者，要随程序发布就得一套一套查许可。

**设计器**：右键终端有「导入 Windows Terminal 配色…」「导出配色…」；导入时一个文件里有多套会先问要哪一套，配对开着时再问写进浅色还是深色那套。

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

## 11. 代码示例

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

**接一个 PTY**：真实现在 `examples/terminal/ushell.pas`（会话、读写线程在 `uptysession.pas`，平台部分在 `uptywin.pas` / `uptyunix.pas`，都在示例里，不在库里）。要做的就三件事：

```pascal
// 1. 按键、粘贴、应答 -> PTY（示例在写线程里写，大段粘贴不卡窗口）
procedure TShell.TermData(Sender: TObject; const AData: RawByteString);
begin
  Session.Write(AData);
end;

// 2. PTY 的输出 -> 终端，带回调：回调说「解析完了多少」，读线程据此决定读不读
procedure TShell.Pump;                                  // 已在主线程
begin
  if Session.Pump(Bytes, Exited, Code) and (Bytes <> '') then
    Term.Write(Bytes, @WriteDone, Length(Bytes));
end;

procedure TShell.WriteDone(Sender: TObject; ATag: PtrInt);
begin
  Session.Delivered(ATag);                              // 积压降到低水位以下，读线程接着读
end;

// 3. 网格尺寸 -> PTY
procedure TShell.TermGridResize(Sender: TObject; ACols, ARows: Integer);
begin
  Session.Resize(ACols, ARows);
end;
```

**用一套独立的配色**：

```pascal
// 从 Windows Terminal 的配色文件读一套（单个方案对象）
Term.ColorScheme.LoadFromFile('Dracula.json');
Term.ColorSource := tsrcScheme;

// 明暗各一套，从 settings.json 里按名取；主题换明暗时终端自己换
Term.ColorScheme.LoadFromFile(SettingsFile, 'One Half Light');
Term.DarkColorScheme.LoadFromFile(SettingsFile, 'One Half Dark');
Term.ColorSchemePaired := True;
Term.ColorSource := tsrcScheme;

// 读用户选的文件：不抛，把原因告诉用户
if not Term.ColorScheme.TryLoadFromFile(OpenDialog1.FileName, '', Err) then
  ShowMessage(Err);

// 代码里配色：一次改完只重算一次
Term.ColorScheme.BeginUpdate;
try
  Term.ColorScheme.Background := RGBToColor($1E, $1E, $1E);
  Term.ColorScheme.Foreground := RGBToColor($D4, $D4, $D4);
finally
  Term.ColorScheme.EndUpdate;
end;
```

Windows 上在第一个字节到来之前告诉 Core 它在 ConPTY 后面、是哪个版本（`Core.WindowsPty := ...`，构建号用 `RtlGetVersion` 取）：21376 之前的 ConPTY 会自己重画折行，Core 照 xterm.js 的老办法处理。

---

## 12. 注意事项

- **Unicode 版本**：默认 `11`。要字形簇（表情修饰符、ZWJ 序列按一个字算）选 `15-graphemes`。**`15` 不连接组合符**：`e` + U+0301 在 `15` 下占 2 格（组合符自占一格），在 `6` / `11` / `15-graphemes` 下占 1 格。
- **`AmbiguousWide` 只对 `15` / `15-graphemes` 起作用**；打开后，U+0301 这类在表里本身是歧义宽度的组合符也算宽：`é`（e + U+0301）在 `15` 下占 **3** 格，在 `15-graphemes` 下占 **2** 格（照 xterm.js）。
- **控件接管了 Core 的这些事件，宿主不要改写**：`OnData`、`OnRefreshRows`、`OnTitleChange`、`OnBell`、`OnCursorMove`、`OnScroll`、`OnBufferActivate`、`OnModesChange`、`OnOsc`、`OnQueryBaseColor`、`OnProcessRequest`、`OnWindowOptionsReport`、`OnResize`、`OnScrollbackCleared`、`OnUserInput`。宿主可以自己挂 `Core.OnIconNameChange`、`Core.OnLineFeed`、`Core.OnRequestScrollToBottom`（只是通知，Core 自己会滚到底），或用 `Core.Parser.Register*Handler` 加自己的序列处理器。
- 换主题、换方案时只有颜色表真变了（换明暗、换配色、换方案）才告诉程序（开了 2031 就报明暗），同时丢掉程序用 OSC 设过的颜色；只改了内边距、字体的主题变化不算。
- 第一次画一屏新字形时，每一帧只花约 10 ms 画新字形，剩下的下一帧补上（Windows 上一个字形约 1.1 ms）；之后都从缓存里取。整屏往上滚一行时只画新露出的那一行，其余的行原样挪上去。
- 块内切片不改变重入的规矩：解析中间调的 `Core.Resize`、`WriteSync` 等整块处理完才执行（§4）。
- REP（`CSI b`）重复次数极大时按周期快进，被跳过那段滚动的 `Core.OnScroll` 不发。
- 窗口尺寸应答（`CSI 14 t` / `16 t`）和 SGR 像素鼠标报的是**设备像素**（xterm.js 报 CSS 像素）。
- **表情**：Windows 上彩色表情画成单色轮廓（GDI 文字管线不画彩色字形），宽度照字符宽度表算。
- **自己画的字形**：框线和块元素（U+2500–259F）、Powerline 符号（U+E0A0–E0D4 里 xterm.js 定义的 38 个：分支、锁、箭头、半圆、斜切等）、盲文（U+2800–28FF）由控件照 xterm.js 自己画，不看字体——相邻格严丝合缝，Consolas 这类没有 Powerline 字形的字体也画得出提示符的箭头。这一段里 xterm.js 没定义的码位照旧交给字体。
- 颜色 token 的透明度会被丢掉：终端的底色、前景、16 色都按不透明画；选区色的透明度只用来在主题底色上预混（见 §10）。
- **OSC 52 读剪贴板是隐私问题**：程序（包括 ssh 过去的远端）能读到你复制过的密码。`to52ReadWrite` 只在宿主会问用户时才开。
- **自己写 Unix PTY 时**：`fork` 之后子进程里只能做系统调用（`sigprocmask`、`sigaction`、`close`、`setsid`、`open`、`ioctl`、`dup2`、`execve`）。LCL 程序是多线程的，子进程里分配内存可能永远等一把别的线程拿着的锁；参数、环境变量、要关的描述符上限都在 `fork` 之前备好。子进程还要清空信号屏蔽字、把被忽略的信号恢复默认（忽略会跨 `execve` 传下去）、关掉宿主没设 close-on-exec 的描述符。
- **关 PTY 别在主线程上等**：ConPTY 的 `ClosePseudoConsole` 在 Windows 11 24H2 之前会等输出读完、程序退出（程序在关闭处理里可以耗 5 秒）；Unix 子进程可能不理 SIGHUP。示例把这些放在收尾线程里，超时按句柄 / SIGKILL 结束程序，程序退出时有上限地等一次（`examples/terminal/uptysession.pas`）。
- Linux 上 PRIMARY 在 X11 下照常；Wayland 下要看合成器支不支持 primary selection。
- 程序接管鼠标时按着覆盖键拖出的是本地选区，程序收不到这次拖动；滚轮照常带着修饰键报给程序。

---

## 13. 本期限制 / 后续

- 自绘字形还没覆盖：Legacy Computing（U+1FB00–）、进度条（U+EE00–EE0B）、git 分支图（U+F5D0–F60D），现在由字体画。
- win32-input-mode（键盘按扫描码编码）、Alt+单击移动光标、kitty 键盘协议：以后。
- 配色方案：只读写 Windows Terminal 的格式（iTerm2 的 `.itermcolors`、xterm.js 的主题 JSON 等以后再说，接口留了 `AFormat`）；16–255 色不进方案；系统色（`clWindow` 这类）在系统改了配色后不会自己刷新，要调一次方案的 `Changed`（§3）；方案名里的 `\u0000` 会丢（FPC 的 JSON 解析器吞掉它）。
- 以后单独立项：屏幕阅读器、连字、图片协议（sixel、iTerm、kitty 图形）、搜索、序列化、进度条 OSC 9;4、网页字体、彩色表情、文字闪烁（SGR 5）。
