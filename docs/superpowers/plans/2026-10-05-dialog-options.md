# 对话框选项对齐 LCL + 字体选择只列等宽 实现计划（4.0）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能默认做法）**：Task 1–11 连续写完，每个任务改代码 + 写测试并单独提交，任务之间**不编译**；Task 12 一次编译、跑相关 suite 与全量、集中修红、G9/G10、集中变异、签收。中途不汇报。
>
> **谁来做**：标 **【主控执行】** 的实现 agent 不做：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编 `examples/`、GUI 冒烟、改 CHANGELOG。实现 agent 只编 `tests/tytests.lpi`。
>
> **不许碰**：`Painter.pas`、`StyleModel.pas`、`TextMenu.pas`、`Base.pas`。不用比 Lazarus 3.0 新的 LCL API。

**Goal:** GitHub #27（`TTyFontComboBox` / `TTyFontListBox` 的 `FixedPitchOnly`，终端示例加字体框）与 #28（字体、颜色、打开/保存、选文件夹、查找/替换对话框的选项对齐 LCL：每个 LCL 选项归入「实现 / 收下不起作用 / 不适用」）。

**Architecture:** 等宽 / 可缩放判断集中在新单元 `tyControls.FontFamilies` 的一个过程里，只经 LCL `EnumFontFamiliesEx` 读系统标志；字体框、字体列表、字体对话框都调它。各对话框照已有模式拆出无模态的测试缝：组件的 `BuildForm`（建窗体、配置选项，不 `ShowModal`）、文件/文件夹的纯校验函数、文件对话框的 `ApplyResult`。文件对话框的 `Options` 改用 LCL 的 `TOpenOptions`，旧 `.lfm` 里的 `fdo*` 名字靠 FPC 的枚举别名（`TypInfo.AddEnumElementAliases`）照常读入。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4（最低 3.0）、fpcunit（`tests/tytests.lpi`）、Python（`scripts/gen-mimic.py`）。

**工作树 / 分支：** `D:/Projects/ty-dialogs`，`feat/dialog-options`，起点 `main` @ `140496e6`。

**不在本计划：** CHANGELOG（发版时写）；LCL 对话框的其它事件（`OnFolderChange`、`OnSelectionChange`、`OnTypeChange`）和 `TOpenDialog.OptionsEx`、`TCommonDialog.Title/HelpContext`（不是 #28 说的「选项」，见末尾「后续」）；示例自带的 `tycontrols.zh_CN.po` 副本（本来就落后于库，主控统一处理）。

---

## 一、核实记录

| # | 核实了什么 | 结论 | 出处 |
|---|---|---|---|
| V1 | 8 个 Ty 自己的对话框已拆，11 个 `TCommonDialog` 系不拆 | 本计划的 7 个对话框都在不拆之列：新属性直接加在 `TTyFontDialog` 等类上并发布；`TTyCustomFileDialog` 是已有的公共父类（不是 Custom/最终拆分），新属性加在它的 published 段末尾 | `docs/subclassing.md` §5；`tests/test.customclasses.pas:74-88` CNotSplit |
| V2 | 字体框、字体列表已拆 | `FixedPitchOnly` 放 `TTyCustomFontComboBox` / `TTyCustomFontListBox`（public），最终类 published 段**末尾**加 `property FixedPitchOnly;`；要重新生成 G9 mimic、跑 G10 fresh streams | `CONTRIBUTING.md` 硬规矩 |
| V3 | win32 `EnumFontFamiliesEx` | 直通 `EnumFontFamiliesExW`，`lfPitchAndFamily` 原样传入（Windows 文档要求 0，实际忽略）；回调里 `elfLogFont.lfPitchAndFamily` 是字体真实的间距位，`FontType` 带 `RASTER_FONTTYPE`；LCL 自己的 `FontIsMonoSpace` 就靠回调里的 `FIXED_PITCH` 位 | `win32/win32winapi.inc:1380`、`win32/win32lclintf.inc:103-145` |
| V4 | gtk2 / gtk3 | `charset=DEFAULT, face='', pitch=0` 走默认分支，回调里 `lfPitchAndFamily`、`FontType` 都没填（`FontType=0`）；`pitch=FIXED_PITCH` 走过滤分支，只回调 `pango_font_family_is_monospace` 为真的族，回调里 `lfPitchAndFamily` = 传入值，`FontType=TRUETYPE_FONTTYPE` | `gtk2/gtk2winapi.inc:3392-3600`、`gtk3/gtk3winapi.inc:1120-1260` |
| V5 | qt6 | 同 gtk：`FIXED_PITCH` 过滤用 `QFontDatabase_isFixedPitch`，回调 pitch = 传入值；默认分支 `FontType=0` | `qt6/qtwinapi.inc:1715-1915` |
| V6 | cocoa | 不按 pitch 过滤，逐族逐成员回调，`lfPitchAndFamily` = 成员有 `NSFontMonoSpaceTrait` 时 `FIXED_PITCH` 否则 `VARIABLE_PITCH`；`FontType` 恒为 `TRUETYPE_FONTTYPE` | `cocoa/cocoawinapi.inc:736-825` |
| V7 | 由 V3–V6 得出的统一写法 | **请求 `lfPitchAndFamily := FIXED_PITCH`，回调里收 `(lfPitchAndFamily and 3) = FIXED_PITCH` 的族名**：Windows 靠回调里的真实位，gtk/qt 靠过滤 + 回填，cocoa 靠逐成员的位。一套代码，四个平台都只读系统标志、不量宽度 | — |
| V8 | 「可缩放」能从哪读 | 只有 Windows 报 `RASTER_FONTTYPE`；gtk/qt 默认分支报 0、cocoa 报 TrueType，都不是点阵。所以「可缩放 = 回调 `FontType` 不含 `RASTER_FONTTYPE`」：Windows 上滤掉点阵字体，别的平台全部算可缩放（LCL 本来就不报点阵）。`fdTrueTypeOnly` 不能这么做：gtk/qt 默认分支报 0，会把列表滤空 → 归「不起作用」 | V3–V6 |
| V9 | `Screen.Fonts` 怎么来的 | `EnumFontFamiliesEx(DEFAULT_CHARSET,'',0)` 去重后排序。过滤结果按 `Screen.Fonts` 的顺序和写法取子集，名字与不过滤时一致 | `lcl/include/screen.inc:614-631` |
| V10 | 旧 `.lfm` 里的 `Options = [fdoXxx]` 怎么读 | `TBinaryObjectReader.ReadSet` 对每个名字调 `GetEnumValue`，找不到就抛 `EReadError`；FPC 3.2.2 的 `GetEnumValue` 找不到时会查 `AddEnumElementAliases` 注册的别名。所以在单元 `initialization` 里给 `TypeInfo(TOpenOption)` 注册 `fdoOverwritePrompt`→`ofOverwritePrompt` 等 4 个别名，旧窗体照常读入；IDE 存盘时 `GetEnumName` 写真名，旧窗体存一次就迁移到新名字 | `fpc/3.2.2/source/rtl/objpas/classes/reader.inc:286-311`、`rtl/objpas/typinfo.pp:882,1019,3418` |
| V11 | 文件对话框 `fdoPathMustExist` 现状 | 枚举里有、文档说支持，`AcceptSelection` 从没检查它——**3.0 也有的 bug** | `Dialogs.FileDialog.pas` `AcceptSelection` |
| V12 | LCL `TOpenDialog` 在 widgetset 之外做的事 | `DoExecute`：先去掉 `ofExtensionDifferent`；没有 `ofNoResolveLinks` 就 `GetPhysicalFilename(…, pfeOriginal)`；没有 `ofNoChangeDir` 就把 `InitialDir` 改成结果所在目录；`CheckFile` 依次查 `ofPathMustExist`、`ofFileMustExist`、`ofNoReadOnlyReturn`；单文件且扩展名与 `DefaultExt` 不同则置 `ofExtensionDifferent`。都与平台无关 | `lcl/include/filedialog.inc:545-660` |
| V13 | Windows 上 `GetPhysicalFilename` | 原样返回，所以 `ofNoResolveLinks` 只在 Unix 上有可见效果，本机测不出（见 Task 12 未覆盖项） | `lazutils/winlazfileutils.inc:69` |
| V14 | LCL 查找对话框怎么用 12 个选项 | `SetFormValues`：`frHide*` → `Visible := False`，`frDisable*` → `Enabled := False`，`frShowHelp` → 帮助按钮可见，`frEntireScope` / `frPromptOnReplace` 只是两个复选框的勾选状态（`GetFormValues` 读回），**真正按范围搜、替换前确认是程序的事**；`TReplaceDialog.Create` 默认加 `frHidePromptOnReplace`；`frButtonsAtBottom` 改按钮在底部还是右侧 | `lcl/include/finddialog.inc:540-582`、`replacedialog.inc:592-654` |
| V15 | LCL 颜色对话框 `CustomColors` | `TStrings`，条目 `ColorA=FFFFFF` … 值是 `IntToHex(TColor, 6)`；只有 win32 widgetset 读写（16 个自定义色格，写回时按 `ColorA..ColorP`），gtk/qt/cocoa 忽略 | `lcl/include/lclcolordialog.inc:14-75`、`win32/win32wsdialogs.pp:401-453` |
| V16 | `TTyDialog.LayoutButtonBar` 遇到隐藏按钮 | 不跳过，照样占一个位置 → 查找对话框的「帮助」按钮要能隐藏，基类得只排可见按钮（`AutoSizeToContent` 的最小宽度同理） | `Dialogs.pas` `LayoutButtonBar` / `AutoSizeToContent` |
| V17 | 窗体能不能无头建 | 字体、查找、选文件夹、文件对话框窗体都已在测试里无头建过（`test.dialogfit.pas:228`），文件对话框单元头注释「不能无头建」已过时；但 `TyMessageDlg` 是模态的，校验逻辑必须拆成纯函数测 | — |
| V18 | `TTySpinEdit.ValueEmpty`、`TTyCheckBox.State=cbGrayed` | 都有；空白 / 灰态被用户输入、点击清掉（不开 `AllowGrayed` 时点灰态变勾选、回不到灰态） | `SpinEdit.pas:207,614-634`、`CheckBox.pas:329-341` |
| V19 | `TTyColorGrid` | 构造时自带 16 色 VGA，只有 `AddColor`，没有清空和按格改色 → 加 `ClearColors`、`ColorAt`、`SetColorAt` | `ColorGrid.pas` |

## 二、决定

- **D1 `.lfm` 兼容（硬约束）**：所有新属性的默认值让旧窗体的外观和行为不变；`MinFontSize` / `MaxFontSize` 写 `default 0`（LCL 没写 default，会让每个窗体都存一行 0）。
- **D2 文件对话框 `Options` 改用 LCL 的 `TOpenOptions`，不扩充 `TTyFileDialogOptions`。** 理由：#28 要求「能用 LCL 类型的就用」，LCL 代码 `Dlg.Options := [ofOverwritePrompt]` 要能直接编译；扩充自家枚举做不到，而在本单元重新声明 `of*` 名字会和 `Dialogs` 的同名标识符互相遮蔽。兼容措施：① `initialization` 注册 4 个别名（V10），旧 `.lfm` 照读；② `TTyFileDialogOption = TOpenOption` / `TTyFileDialogOptions = TOpenOptions` 与 `fdoOverwritePrompt = ofOverwritePrompt` 等 4 个常量保留并标 `deprecated`，旧代码照编（带警告）；③ published 默认值保持 `[]`（不跟 LCL 的 `[ofEnableSizing, ofViewDetail]`：改默认值会让存过 `Options` 的旧窗体丢掉这两位，见 D4）；④ 测试：把含 `Options = [fdoOverwritePrompt, fdoAllowMultiSelect]` 的旧窗体文本读入，得 `[ofOverwritePrompt, ofAllowMultiSelect]`。
- **D3 「否定式」选项照 LCL 实现**：`ofNoChangeDir`、`ofNoResolveLinks`、`frHideEntireScope`、`frHidePromptOnReplace` 照 LCL 语义——不带这一位时做 LCL 默认做的事。这会带来三处 3.0 窗体可见的变化，写进文档并在汇报里列给主控：查找/替换对话框多一个「整个范围」复选框（加 `frHideEntireScope` 恢复旧样）；3.0 存过 `Options` 的替换对话框多一个「替换前提示」复选框（代码新建的照 LCL 默认隐藏）；`Execute` 成功后 `InitialDir` 跟着结果目录走、Unix 上 `FileName` 解析符号链接。
  - **（期末修复补记）** 第二处的范围比上面写的大：3.0 的 `TTyReplaceDialog` 构造初值 `[frDown, frReplace, frReplaceAll]` 与声明的 `default [frDown]` 不同，所以**设计器里放过的替换对话框全都**把 `Options` 写进了窗体，读入时整体盖掉 4.0 构造函数加的 `frHidePromptOnReplace`；第一处则是所有查找 / 替换对话框（3.0 没有 `frHideEntireScope` 可存）。保持 LCL 语义、不改代码；`dialogs.md` §10 写成明确的升级须知，给出 `.lfm` 与代码两种恢复写法；`examples/demo/mainform.lfm` 的替换对话框补 `frHidePromptOnReplace`（demo 不处理它；其它示例的查找 / 替换对话框都是代码建的，没有 `.lfm` 要改）。
  - **（期末修复补记）** 第三处「Unix 上 `FileName` 解析符号链接」同样落在选文件夹组件上：`TTySelectPathDialog.Execute` 没有 `ofNoResolveLinks` 时把 `Directory` 过 `GetPhysicalFilename`（`Options` 默认 `[]`，所以 Linux / macOS 上所有 3.0 窗体里的选文件夹对话框都会把链接换成实际路径；全局函数 `TySelectDirectory` 不解析）。写进 `dialogs.md` §8.5 的「从 3.0 升级」，恢复旧行为加 `ofNoResolveLinks`。
- **D4 「默认开着」的选项不实现成开关**：LCL 默认带 `ofEnableSizing`、`ofViewDetail`、`cdFullOpen`；Ty 的对话框本来就总能缩放、总从详细视图开始、总是展开的取色器。要让「去掉这一位」生效就得改默认值或改现有窗体行为，所以归「收下不起作用」，文档写明「总是如此」。
- **D5 等宽 / 可缩放只读系统标志**（V7、V8），不量字形宽度、不缓存：只在选项打开时枚举一次，开销与 `Screen.Fonts` 首次填充同级；字体框只在构造、`Loaded`、`RefreshFonts`、改 `FixedPitchOnly` 时枚举，字体对话框每次 `Execute` 枚举一次（用户可能刚装了字体）。
  - **（期末修复补记）** 「刚装的字体会出现」不成立：结果按 `Screen.Fonts` 取交集，而 LCL 只在首次访问时填充 `Screen.Fonts`、之后从不重读（`screen.inc` `GetFonts`），运行中新装的字体要重启程序才出现。单元头注释、`BuildForm` 注释与 `RefreshFonts` 的文档已改成实话。
- **D6 查找对话框的复选框按可见的重新排列**，隐藏的不留空位；窗体高度跟着变。
- **D7 `CustomColors` 为空时不显示自定义色一行**（默认空，旧窗体外观不变）；有条目时显示 16 格（`ColorA..ColorP`，缺的格子画白色，和 Windows 自定义色格的初值一致），「添加到自定义颜色」按钮把当前颜色放进下一格；确定后只写回原来就有的和新加的格子，其余条目原样保留。
- **D8 测试缝**：组件加 public `BuildForm`（建并配置窗体，不显示，调用方释放；`TTyFindDialog` 已有同名方法，形状照它）；文件对话框加 public `ApplyResult(AOK, AFileName, AFiles)`（`Execute` 在 `ShowModal` 之后调它，测试直接调）；校验做成纯函数 `TyFileDialogCheck`、`TySelectPathCheck`。

## 三、LCL 选项对照表

### 3.1 `TTyFontDialog.Options: TFontDialogOptions`（默认 `[fdEffects]`，同 LCL）

| 选项 | 归类 | 做法 / 理由 |
|---|---|---|
| fdEffects | 实现 | 有：显示下划线、删除线、颜色按钮；没有：三者隐藏，`WriteTo` 不改字体原来的下划线、删除线、颜色 |
| fdFixedPitchOnly | 实现 | 家族列表用 `TyGetFontFamilies(…, True, …)`（#27 同一判断） |
| fdScalableOnly | 实现 | `TyGetFontFamilies(…, …, True)`：滤掉系统报为点阵的字体（只有 Windows 报，V8） |
| fdLimitSize | 实现 | 字号框范围取 `MinFontSize` / `MaxFontSize`（>0 才生效）；确定时字号一定在范围内（原字号越界时写回钳过的值，原字号 ≤0「默认」保持） |
| fdNoFaceSel | 实现 | 家族列表不预选；不动选择就不改 `Font.Name` |
| fdNoSizeSel | 实现 | 字号框空白（`ValueEmpty`）；不动就不改 `Font.Size` |
| fdNoStyleSel | 实现 | 粗体、斜体复选框灰态；不点就保留原样式位 |
| fdApplyButton | 实现 | 按钮栏加「应用」：把当前选择写进 `Font`，触发 `OnApplyClicked`，对话框不关 |
| fdAnsiOnly | 不起作用 | Windows `ChooseFont` 的字符集过滤，跨平台无对应 |
| fdTrueTypeOnly | 不起作用 | 「TrueType」是 Windows 的字体技术区分；gtk/qt 默认枚举报 `FontType=0`，照做会把列表滤空（V8） |
| fdNoOEMFonts | 不起作用 | Windows OEM 字符集遗留 |
| fdNoSimulations | 不起作用 | GDI 合成粗斜体遗留 |
| fdNoVectorFonts | 不起作用 | Windows 矢量（笔画）字体遗留 |
| fdWysiwyg | 不起作用 | 屏幕 / 打印机共有字体，Windows 遗留 |
| fdShowHelp | 不起作用 | LCL `TFontDialog` 没有帮助事件，帮助按钮无事可做 |
| fdForceFontExist | 不适用 | 只能从列表里选家族，没有手输字体名的框，选中的一定存在 |

另加属性：`MinFontSize`、`MaxFontSize`（`default 0`）、`PreviewText`（空 = 原来的示例文字）、`OnApplyClicked`；public `ApplyClicked`（virtual，同 LCL）。

### 3.2 `TTyColorDialog.Options: TColorDialogOptions`（默认 `[cdFullOpen]`，同 LCL）

| 选项 | 归类 | 做法 / 理由 |
|---|---|---|
| cdPreventFullOpen | 实现 | 不许自定义颜色：色相条、HSV 方块、Hex/RGB/CMYK/Alpha 输入框和「添加到自定义颜色」禁用，只能点色块 |
| cdFullOpen | 不起作用 | Ty 的取色器没有收起状态，总是展开（D4） |
| cdSolidColor | 不起作用 | 256 色模式下的抖动色遗留 |
| cdAnyColor | 不起作用 | 同上 |
| cdShowHelp | 不起作用 | LCL `TColorDialog` 没有帮助事件 |

另加属性 `CustomColors: TStrings`（D7）。

### 3.3 `TTyOpenDialog` / `TTySaveDialog`（及 4 个预览变体）`.Options: TOpenOptions`（默认 `[]`）

| 选项 | 归类 | 做法 / 理由 |
|---|---|---|
| ofOverwritePrompt | 实现（已有） | 保存时文件已存在 → 确认 |
| ofAllowMultiSelect | 实现（已有） | 打开时可多选 |
| ofFileMustExist | 实现（已有，扩到多选的每个文件、保存也查，照 LCL `CheckAllFiles`） | 文件不存在 → 报错不关 |
| ofPathMustExist | 实现（**3.0 收下没做**，V11） | 结果所在目录不存在 → 报错不关 |
| ofCreatePrompt | 实现 | 文件不存在 → 问「要创建吗」，否 → 不关 |
| ofNoReadOnlyReturn | 实现 | 文件存在而不可写，或不存在而目录不可写 → 报错不关 |
| ofExtensionDifferent | 实现 | 输出位：确定后单个文件、`DefaultExt` 非空且扩展名不同时置上，否则清掉 |
| ofNoChangeDir | 实现（D3） | 没有它：确定后 `InitialDir` 改成结果所在目录 |
| ofNoResolveLinks | 实现（D3） | 没有它：确定后 `FileName` / `Files` 过 `GetPhysicalFilename`（只 Unix 有效果，V13） |
| ofForceShowHidden | 实现 | 列表和目录树显示隐藏项 |
| ofShowHelp | 实现 | 按钮栏加「帮助」，点了触发新事件 `OnHelpClicked`（LCL `TFileDialog` 有） |
| ofEnableSizing | 不起作用 | 总能缩放（D4） |
| ofViewDetail | 不起作用 | 总从详细视图开始（D4） |
| ofReadOnly | 不起作用 | Windows 老式对话框的「只读」复选框 |
| ofHideReadOnly | 不起作用 | 同上 |
| ofNoValidate | 不起作用 | 不校验文件名里的非法字符，Ty 本来就不校验 |
| ofShareAware | 不起作用 | Windows 共享冲突 |
| ofNoTestFileCreate | 不起作用 | Windows 试建文件，Ty 从不试建 |
| ofNoNetworkButton | 不起作用 | Windows 网络按钮 |
| ofNoLongNames | 不起作用 | 8.3 文件名 |
| ofOldStyleDialog | 不起作用 | Win9x 样式 |
| ofNoDereferenceLinks | 不起作用 | Windows `.lnk`，Ty 从不解析 `.lnk` |
| ofDontAddToRecent | 不起作用 | Windows「最近」列表，Ty 不加 |
| ofAutoPreview | 不起作用 | 有没有预览窗格由对话框种类决定（Picture / Preview 变体） |
| ofEnableIncludeNotify | 不适用 | LCL 自己也没用（只为 Delphi 兼容声明） |

### 3.4 `TTySelectPathDialog.Options: TOpenOptions`（新属性，默认 `[]`）

LCL 的 `TSelectDirectoryDialog` 继承 `TOpenDialog`，同一个选项类型。

| 选项 | 归类 | 做法 / 理由 |
|---|---|---|
| ofPathMustExist | 实现 | 路径框里输入的文件夹的上一级不存在 → 报错不关 |
| ofFileMustExist | 实现 | 输入的文件夹不存在 → 报错不关（LCL 选目录时把它当「目录必须存在」） |
| ofCreatePrompt | 实现 | 输入的文件夹不存在 → 问「要创建吗」，是 → 建好并返回它 |
| ofNoReadOnlyReturn | 实现 | 选中的文件夹不可写 → 报错不关 |
| ofNoResolveLinks | 实现（D3） | 没有它：确定后 `Directory` 过 `GetPhysicalFilename` |
| ofShowHelp | 实现 | 「帮助」按钮 + `OnHelpClicked` |
| ofForceShowHidden | 不起作用 | 树里本来就列出隐藏文件夹（`TySubdirectories` 带 `fotHidden`），改成默认不列会改变旧窗体 |
| ofEnableSizing | 不起作用 | 总能缩放 |
| ofViewDetail、ofReadOnly、ofHideReadOnly、ofNoValidate、ofShareAware、ofNoTestFileCreate、ofNoNetworkButton、ofNoLongNames、ofOldStyleDialog、ofNoDereferenceLinks、ofDontAddToRecent | 不起作用 | 同 3.3 |
| ofNoChangeDir | 不适用 | 这个对话框没有 `InitialDir`，`Directory` 本来就是进出两用 |
| ofOverwritePrompt | 不适用 | 选文件夹不覆盖任何东西 |
| ofAllowMultiSelect | 不适用 | 目录树单选 |
| ofExtensionDifferent | 不适用 | 文件夹没有扩展名 |
| ofAutoPreview | 不适用 | 没有预览窗格 |
| ofEnableIncludeNotify | 不适用 | LCL 自己也没用 |

（「不起作用」一行合并了 11 个，计数按 13 个：ofForceShowHidden、ofEnableSizing + 这 11 个。）

不实现「没有选项时输入不存在的路径」的语义变化：没有 `ofPathMustExist` / `ofFileMustExist` / `ofCreatePrompt` 时照 3.0 返回树上选中的节点。

### 3.5 `TTyFindDialog` / `TTyReplaceDialog.Options: TFindOptions`（默认 `[frDown]` 不变）

| 选项 | 归类 | 做法 |
|---|---|---|
| frDown、frFindNext、frMatchCase、frWholeWord、frReplace、frReplaceAll | 实现（已有） | — |
| frHideMatchCase / frHideWholeWord / frHideUpDown | 实现 | 对应复选框隐藏，其余往上挪（D6） |
| frDisableMatchCase / frDisableWholeWord / frDisableUpDown | 实现 | 对应复选框禁用 |
| frEntireScope | 实现 | 新复选框「整个范围」的勾选状态，读回 `Options`（V14：按范围搜是程序的事） |
| frHideEntireScope | 实现 | 隐藏「整个范围」（D3：不带它就显示） |
| frPromptOnReplace | 实现 | 替换对话框新复选框「替换前提示」的勾选状态，读回 `Options` |
| frHidePromptOnReplace | 实现 | 隐藏「替换前提示」；`TTyReplaceDialog.Create` 照 LCL 默认带上它 |
| frShowHelp | 实现 | 「帮助」按钮 + 新事件 `OnHelpClicked` |
| frButtonsAtBottom | 不起作用 | Ty 的按钮总在底部按钮栏 |

另：`Options` 的写入改走 setter，窗体开着时当场同步（LCL `TFindDialog.SetOptions` 也是）。

### 3.6 合计

| 对话框 | 实现 | 不起作用 | 不适用 | 合计 |
|---|---|---|---|---|
| 字体 | 8 | 7 | 1 | 16 |
| 颜色 | 1 | 4 | 0 | 5 |
| 打开 / 保存 | 11 | 13 | 1 | 25 |
| 选文件夹 | 6 | 13 | 6 | 25 |
| 查找 / 替换 | 17（其中新 11） | 1 | 0 | 18 |
| **合计** | **43** | **38** | **8** | **89** |

## 四、文件

| 文件 | 改什么 |
|---|---|
| Create `source/tyControls.FontFamilies.pas` | `TyGetFontFamilies` |
| `tycontrols.lpk` | 加上新单元 |
| `source/tyControls.FontComboBox.pas`、`FontListBox.pas` | `FixedPitchOnly` |
| `source/tyControls.Dialogs.pas` | 按钮栏只排可见按钮 |
| `source/tyControls.Dialogs.Find.pas` | 11 个新选项、`OnHelpClicked`、`SetOptions` |
| `source/tyControls.Dialogs.Font.pas` | `Options` 等 5 个属性、`Configure`、`BuildForm` |
| `source/tyControls.ColorGrid.pas` | `ClearColors`、`ColorAt`、`SetColorAt` |
| `source/tyControls.Dialogs.Color.pas` | `Options`、`CustomColors`、`BuildForm` |
| `source/tyControls.Dialogs.FileDialog.pas` | `TOpenOptions`、别名、`TyFileDialogCheck`、`BuildForm`、`ApplyResult`、`OnHelpClicked` |
| `source/tyControls.Dialogs.SelectPath.pas` | `Options`、`TySelectPathCheck`、`BuildForm`、`OnHelpClicked` |
| `source/tyControls.Dialogs.ImageCollectionEditor.pas` | `fdoAllowMultiSelect` → `ofAllowMultiSelect` |
| `source/tyControls.StrConsts.pas` + `languages/tyControls.StrConsts.pot` + `languages/tycontrols.strconsts.zh_CN.po` | 新文字 |
| `examples/terminal/umain.lfm` / `umain.pas` / `languages/terminal_example.zh_CN.po` | 字体框 |
| `examples/filedialog/umain.lfm`、`examples/terminal/umain.lfm` | `fdo*` → `of*` |
| tests：`test.fontfamilies.pas`（新）、`test.fontcombobox.pas`、`test.fontlistbox.pas`、`test.dialogs.pas`、`test.dialogs.find.pas`、`test.dialogs.font.pas`、`test.colorgrid.pas`、`test.dialogs.color.pas`、`test.dialogs.filedialog.pas`、`test.dialogs.selectpath.pas`、`tytests.lpr`、`test.customclasses.mimic.pas`（生成） | — |
| docs：`controls/fontcombobox.md`、`fontlistbox.md`、`terminal.md`、`dialogs.md`、`filedialog.md` | 只有中文版 |

新用户可见文字（`resourcestring`，zh_CN）：

| 标识符 | 英文 | 中文 |
|---|---|---|
| rsDlgFontApply | Apply | 应用 |
| rsDlgCustomColors | Custom colors | 自定义颜色 |
| rsDlgAddCustomColor | Add to custom colors | 添加到自定义颜色 |
| rsDlgEntireScope | Entire scope | 整个范围 |
| rsDlgPromptOnReplace | Prompt on replace | 替换前提示 |
| rsFdPathMustExist | The folder "%s" does not exist. | 文件夹"%s"不存在。 |
| rsFdNotWritable | "%s" is not writable. | "%s"不可写。 |
| rsFdCreatePrompt | "%s" does not exist.<LF>Do you want to create it? | "%s"不存在。<LF>要创建吗？ |

「帮助」复用 `rsMsgBtnHelp`。

---

## 五、任务

判据一律写「在哪个变异下必须红」；测试代码在执行时写，照所在测试文件的风格。

### Task 0：计划提交

- [ ] 提交本计划：`docs(plan): dialog options on par with LCL and fixed-pitch font pickers`（正文 `Refs #27`、`Refs #28`）。

### Task 1：`tyControls.FontFamilies`

**Files:** Create `source/tyControls.FontFamilies.pas`；Modify `tycontrols.lpk`（在 `tyControls.FontComboBox` 条目前加一项）；Create `tests/test.fontfamilies.pas`；Modify `tests/tytests.lpr`。

```pascal
{ Fills ADest with the installed families, in Screen.Fonts order and spelling, keeping only those
  the SYSTEM reports as fixed-pitch (AFixedPitchOnly) and/or not a bitmap font (AScalableOnly).
  Neither flag -> ADest is Screen.Fonts. Read through LCL's EnumFontFamiliesEx; nothing is
  measured. }
procedure TyGetFontFamilies(ADest: TStrings; AFixedPitchOnly: Boolean;
  AScalableOnly: Boolean = False);
```

实现：两个 `extdecl` 回调往一个 `TStringList`（`Sorted`、`dupIgnore`）里收名字——等宽回调收 `(lfPitchAndFamily and 3) = FIXED_PITCH`，可缩放回调收 `(FontType and RASTER_FONTTYPE) = 0`；等宽请求 `lfPitchAndFamily := FIXED_PITCH`，可缩放请求 0（V7、V8）；`GetDC(0)` / `ReleaseDC`；最后按 `Screen.Fonts` 逐项过滤进 `ADest`（`BeginUpdate`/`EndUpdate`）。

- [ ] 测试 `TFontFamiliesTest`（只在本机有对应字体时断言，否则 `Ignore`）：
  - 不带选项 = `Screen.Fonts`（条数、逐项相等）。
  - 等宽：`Courier New`、`Consolas` 在，`Arial`、`Segoe UI` 不在；结果是 `Screen.Fonts` 的有序子集。**变异 M1-1** 回调不看 pitch 全收 → 红；**M1-2** 忽略 `AFixedPitchOnly` 直接 Assign → 红。
  - 可缩放：`Arial` 在，Windows 上 `Fixedsys`/`Terminal`/`MS Sans Serif` 中本机存在的点阵字体不在。**M1-3** 可缩放回调全收 → 红。
  - 两个都开：交集（`Courier New` 在、`Fixedsys` 不在）。**M1-4** 两个集合取并 → 红。
- [ ] 提交 `feat(fonts): list families by the system's fixed-pitch and bitmap flags`（`Refs #27`）。

### Task 2：字体框、字体列表的 `FixedPitchOnly`

**Files:** `FontComboBox.pas`、`FontListBox.pas`、`test.fontcombobox.pas`、`test.fontlistbox.pas`。

- 两个 Custom 类：字段 `FFixedPitchOnly`，public `property FixedPitchOnly: Boolean read … write SetFixedPitchOnly default False;`；`RefreshFonts` 与 `Loaded` 改用 `TyGetFontFamilies(Items, FFixedPitchOnly)`（`Loaded` 里列表框按名字恢复选中，照旧）；setter：值变了且不在 `csLoading` → 记住当前家族名，刷新，名字还在就选回去，否则照 `RefreshFonts` 选第 0 项。最终类 published 段末尾（`Anchors` 之后）加 `property FixedPitchOnly;`。
- [ ] 测试（两个控件各一套）：
  - 设 `FixedPitchOnly := True` 后 `Items` = `TyGetFontFamilies(…, True)`；设回 False = `Screen.Fonts`。**M2-1** setter 不刷新 → 红。
  - 选中 `Courier New` 再打开 → 仍选 `Courier New`；选中 `Arial` 再打开 → 选第 0 项。**M2-2** 不按名字恢复 → 红。
  - 窗体文本 `FixedPitchOnly = True` 读入 → `Items` 只有等宽、选中按名字恢复。**M2-3** `Loaded` 仍 `Assign(Screen.Fonts)` → 红。
  - 默认值写窗体：新建控件写出的文本里没有 `FixedPitchOnly`；设 True 后有。**M2-4** 去掉 `default False` → 红。
- [ ] 提交 `feat(fontcombobox): FixedPitchOnly lists only fixed-pitch families`（同时含列表框，`Refs #27`）。

### Task 3：终端示例 + 字体框文档

**Files:** `examples/terminal/umain.lfm`、`umain.pas`、`languages/terminal_example.zh_CN.po`；`docs/controls/fontcombobox.md`、`fontlistbox.md`、`terminal.md`。

- `Tools2` 一行已满（到 952/980）。做法：`LblFontSize` 的标题改成 `Font:`（宽 40），后面 `CmbFont: TTyFontComboBox`（Left 746, Width 140, `FixedPitchOnly = True`, `ReadOnly = True`, `OnChange = FontNameChange`），`SpnFontSize` 挪到 892；`BtnPaste` 挪到 `Tools4` 末尾（Left 860，那一行到 840 为止）。
- `umain.pas`：字段 `CmbFont: TTyFontComboBox`、uses `tyControls.FontComboBox`；`FontNameChange`：`Term.ParentFont := False; Term.Font.Name := CmbFont.SelectedFont;`；`FormCreate` 里若终端当前字体在列表中则选中它（`CmbFont.SelectedFont := Term.Font.Name`，在挂 `OnChange` 之前 / 或用 lfm 不写 OnChange、代码里挂——照文件里已有写法）。
- `.po`：`tmainform.lblfontsize.caption` 的 msgid 改 `Font:`、msgstr `字体：`（示例 .po 不需要别的条目：字体框没有标题）。
- 文档：`fontcombobox.md`、`fontlistbox.md` 属性表加 `FixedPitchOnly`（说明只读系统标志、Windows/GTK/Qt/Cocoa 各自来源、只在打开时枚举）；`terminal.md` 字体那段补「示例里的字体框开了 `FixedPitchOnly`」。
- [ ] 提交 `feat(examples): the terminal example picks a fixed-pitch font`（`Fixes #27`）。【主控执行】编示例、冒烟。

### Task 4：按钮栏只排可见按钮

**Files:** `source/tyControls.Dialogs.pas`、`tests/test.dialogs.pas`。

- `LayoutButtonBar`：只把 `Visible` 的按钮交给 `TyDialogButtonBar`，隐藏的不动；`ButtonHeight` 只看可见按钮；`AutoSizeToContent` 的最小宽度只累加可见按钮。
- [ ] 测试：三个按钮，隐藏中间那个后，可见两个之间的间距 = `Px(cDlgBarSpacing)`、右边那个右缘不变。**M4-1** 恢复成全部参与排布 → 红。
- [ ] 提交 `fix(dialogs): the button bar leaves no gap for a hidden button`（`Refs #28`）。

### Task 5：查找 / 替换

**Files:** `Dialogs.Find.pas`、`StrConsts.pas` + `.pot` + `zh_CN.po`、`test.dialogs.find.pas`。

- 窗体：`Build` 多建 `FEntireScope`（两种模式）、`FPromptOnReplace`（只替换模式）、`FHelpBtn`（`AddButton(rsMsgBtnHelp, mrNone)`，点了调 `FDlg.DoHelpClicked`）；记下复选框起始 y 与内容宽度；`SyncFrom` 设勾选（含 `frEntireScope`、`frPromptOnReplace`）、可见（`frHide*`）、可用（`frDisable*`）、帮助按钮可见（`frShowHelp`），然后 `LayoutChecks`：可见复选框从起始 y 依次排，`AutoSizeToContent` 按最后一个的底边定高，`LayoutButtonBar`。`WriteBack` 读回 `frEntireScope`、`frPromptOnReplace`。测试缝 `EntireScopeCheck`、`PromptOnReplaceCheck`、`HelpButton`。
- 组件：`Options` 写入走 `SetOptions`（窗体在就 `SyncFrom`）；published 末尾（`OnCanClose` 后）加 `OnHelpClicked: TNotifyEvent`；`TTyReplaceDialog.Create` 加 `frHidePromptOnReplace`。
- [ ] 测试：
  - 每个 `frHide*`（MatchCase / WholeWord / UpDown / EntireScope / PromptOnReplace）→ 对应复选框 `Visible=False`，下一个可见复选框的 Top 等于被藏那个原来的 Top。**M5-1** 去掉任一 hide 映射 → 红；**M5-2** `LayoutChecks` 不跳过隐藏的 → 红。
  - 每个 `frDisable*` → `Enabled=False`，另两个仍可用。**M5-3** 映射错位（MatchCase↔WholeWord）→ 红。
  - `frEntireScope` 进出：Sync 勾上；取消勾选后 `DoFindNext` → `Options` 无 `frEntireScope`。**M5-4** `WriteBack` 不读回 → 红。替换模式 `frPromptOnReplace` 同理（**M5-5**）。
  - 查找模式没有「替换前提示」复选框（nil）。
  - 替换对话框新建即含 `frHidePromptOnReplace`，窗体上该复选框不可见。**M5-6** 构造函数不加 → 红。
  - `frShowHelp`：帮助按钮可见，`Click` → `OnHelpClicked` 触发、Sender 是组件；没有 → 不可见。**M5-7** 点帮助不转发 → 红。
  - 窗体建好后改 `Options := Options + [frHideWholeWord]` → 复选框当场隐藏。**M5-8** published 写回 `FOptions` 直写 → 红。
- [ ] 提交 `feat(find): honour LCL's hide, disable, scope, prompt and help options`（`Refs #28`）。

### Task 6：字体对话框

**Files:** `Dialogs.Font.pas`、`StrConsts`/.pot/.po、`test.dialogs.font.pas`。

- 窗体：`procedure Configure(AOptions: TFontDialogOptions; AMinSize, AMaxSize: Integer; const APreviewText: string);`（`SeedFrom` 之后调）——`fdLimitSize` 时设字号框范围并重记 `FSeedDisplay`；`fdNoSizeSel` → `ValueEmpty`；`fdNoFaceSel` → 列表 `ItemIndex := -1`；`fdNoStyleSel` → 粗体、斜体 `State := cbGrayed`；无 `fdEffects` → 下划线、删除线、颜色按钮隐藏；`fdApplyButton` → `AddButton(rsDlgFontApply, mrNone)`，点了 `DoApply`（触发 `OnApply`）；记 `PreviewText`。`WriteTo` 按上述「不动就保持」写回，`fdLimitSize` 钳范围。预览：字号空白时用种子显示值，灰态用种子样式，示例文字 `SampleText`（`PreviewText` 非空用它，否则 `rsDlgFontSample`）。公开 `property OnApply`、`function SampleText: string`。
- 组件：published 末尾加 `Options: TFontDialogOptions default [fdEffects]`、`MinFontSize`/`MaxFontSize: Integer default 0`、`PreviewText: string`、`OnApplyClicked`；public `function BuildForm: TTyFontForm;`（家族 = 有 `fdFixedPitchOnly`/`fdScalableOnly` 时 `TyGetFontFamilies`，否则 `Screen.Fonts`；种子；`Configure`；`OnApply` 接到组件：`d.WriteTo(FFont); ApplyClicked`）、`procedure ApplyClicked; virtual;`；`Execute` 改用 `BuildForm`。
- [ ] 测试：
  - `fdFixedPitchOnly` → `FamilyCount` 等于 `TyGetFontFamilies(…, True)` 的条数（本机无 Courier New 则 Ignore）。**M6-1** `BuildForm` 不看选项 → 红。
  - `fdLimitSize` + Min 8 Max 12 + 种子 20 → 字号框显示 12，确定写回 12；种子 10 不动 → 10；不带 `fdLimitSize` 时 Min/Max 不生效（种子 20 → 20）。**M6-2** 不看 `fdLimitSize` → 红；**M6-3** 越界种子原样写回 → 红。
  - `fdNoSizeSel`：字号框空白，不动 → `Size` 不变；用户改值后写回新值。**M6-4** 不设 `ValueEmpty` → 红（断言空白）。
  - `fdNoFaceSel`：列表无选中，`WriteTo` 后 `Name` 不变。**M6-5**。
  - `fdNoStyleSel`：种子 `[fsBold]`，粗体斜体灰态，`WriteTo` 后仍 `[fsBold]`；点一下粗体（变勾选）→ 含 `fsBold`、点两下 → 不含。**M6-6** 灰态当未勾选写回 → 红。
  - 无 `fdEffects`：三个控件隐藏；种子 `[fsUnderline]`、红色，`WriteTo` 后不变。**M6-7** 隐藏但仍写回 → 红（先在窗体上把隐藏的下划线复选框取消勾选再 `WriteTo`）。
  - `fdApplyButton`：按钮栏有「应用」，`Click` 后 `Font` 已是当前选择、`OnApplyClicked` 触发、窗体 `ModalResult = mrNone`。**M6-8** 应用前不 `WriteTo` → 红。没有该选项 → 没有这个按钮。
  - `PreviewText` → `SampleText`；空 → `rsDlgFontSample`。**M6-9**。
  - 默认值：新组件 `Options = [fdEffects]`，写窗体不出现 5 个新属性（**M6-10** 去掉 `default 0` → 红）；默认 `BuildForm` 与改动前一致（下划线等可见、无应用按钮）。
- [ ] 提交 `feat(fontdialog): Options, size limits, preview text and an apply button`（`Refs #28`）。

### Task 7：颜色网格 API + 颜色对话框

**Files:** `ColorGrid.pas`、`test.colorgrid.pas`、`Dialogs.Color.pas`、`StrConsts`/.pot/.po、`test.dialogs.color.pas`。

- 网格：`procedure ClearColors;`（清空、取消选中、重绘）、`function ColorAt(AIndex: Integer): TColor;`、`procedure SetColorAt(AIndex: Integer; AColor: TColor);`（越界忽略，重绘）。
- 解析（纯函数，单元 interface）：`function TyParseCustomColor(const AName, AValue: string; out ASlot: Integer; out AColor: TColor): Boolean;`——`Color` + 一个字母 `A..P` → 槽 0..15，值是十六进制 TColor（照 LCL `ExtractColorIndexAndColor`，但只认 16 槽）。
- 窗体：`ApplyOptions(AOptions: TColorDialogOptions)`（`cdPreventFullOpen` → 禁用方块、色相条、Hex、R/G/B/C/M/Y/K/A、添加按钮）；`SetCustomColors(AList: TStrings)`：有至少一条合法条目才在常用色下面插一段「自定义颜色」标签 + 16 格网格（缺的槽白色）+ 「添加到自定义颜色」按钮，预览标签与预览框往下挪，`AutoSizeToContent` 重算；`GetCustomColors(AList)`：只写回原有和新加的槽（`Values['ColorX'] := IntToHex(c, 6)`）；`AddCustomColor`：当前颜色放进下一槽（从「最后一个已定义槽的下一格」开始，满 16 绕回 0），网格选中它；点自定义色格走和常用色一样的 `ApplyColor`。测试缝 `CustomSwatches`（无则 nil）、`AddCustomColor`。预览标签要留引用（现在是匿名 `MkLabel`）。
- 组件：published 末尾加 `Options: TColorDialogOptions default [cdFullOpen]`、`CustomColors: TStrings`（setter `Assign`）；public `BuildForm`；`Execute` 确定后写 `FColor` 并 `GetCustomColors(FCustomColors)`。
- [ ] 测试：
  - 网格三个新方法（含越界）。**M7-1** `ClearColors` 不清选中 → 红（清空后 `Selected = clNone`）。
  - `TyParseCustomColor`：`ColorA`/`FF0000` → 0/$FF0000；`ColorP` → 15；`ColorQ`、`ColorAA`、`Foo`、坏十六进制 → False。**M7-2** 放宽到 Q..T → 红。
  - 空 `CustomColors` → 没有自定义网格，窗体尺寸与改动前一样（与不调 `SetCustomColors` 的窗体比 `ClientHeight`）。**M7-3** 空列表也建段 → 红。
  - `ColorA=0000FF`、`ColorC=00FF00` → 网格 16 格，0 号是 `$0000FF`、1 号白、2 号 `$00FF00`；预览框整体下移。
  - 点自定义色格（`SetColorAt` 后模拟选中，走 `OnChange`）→ `CurrentColor` 变。
  - `AddCustomColor` 两次 → 槽 3、4 写入当前颜色；`GetCustomColors` 写回 A、C、D、E，B 不出现；列表里原有的 `ColorQ=…` 原样保留。**M7-4** 写回全部 16 槽 → 红。
  - `cdPreventFullOpen` → 方块、Hex、R、A、添加按钮 `Enabled=False`，常用色网格可用。**M7-5** 漏禁用 Hex → 红。
  - 默认：`Options = [cdFullOpen]`，写窗体不出现 `Options`、`CustomColors`。**M7-6**。
- [ ] 提交 `feat(colordialog): Options and CustomColors`（`Refs #28`）。

### Task 8：打开 / 保存对话框

**Files:** `Dialogs.FileDialog.pas`、`Dialogs.ImageCollectionEditor.pas`、`examples/filedialog/umain.lfm`、`examples/terminal/umain.lfm`、`StrConsts`/.pot/.po、`test.dialogs.filedialog.pas`。

- 类型：`TTyFileDialogOption = TOpenOption deprecated; TTyFileDialogOptions = TOpenOptions deprecated;`；常量 `fdoOverwritePrompt = ofOverwritePrompt deprecated;` 等 4 个；`initialization` 里 4 次 `AddEnumElementAliases(TypeInfo(TOpenOption), ['fdoXxx'], Ord(ofXxx))`（`try … except on EArgumentException do ; end`，防重复注册）；`finalization` 里 `RemoveEnumElementAliases`。窗体与组件的 `Options` 改 `TOpenOptions`。
- 纯校验：`TTyFileDialogCheck = (fdcOK, fdcPathMissing, fdcFileMissing, fdcNotWritable, fdcAskCreate, fdcAskOverwrite)`；`function TyFileDialogCheck(ASaveMode: Boolean; const AFileName: string; AOptions: TOpenOptions): TTyFileDialogCheck;` 顺序：`ofPathMustExist` → `ofFileMustExist` → `ofNoReadOnlyReturn`（存在查 `FileIsWritable`，否则查目录 `DirectoryIsWritable`）→ 不存在且 `ofCreatePrompt` → 保存、存在且 `ofOverwritePrompt`。`AcceptSelection` 对结果（打开多选时对每个文件）调它：错误类 `TyMessageDlg(…, mtError, [mbOK])` 后否决；询问类 `mtConfirmation, [mbYes, mbNo]`，否 → 否决。
- 窗体：`SetOptions` 另设 `FList.ShowHidden` / `FTree.ShowHidden := ofForceShowHidden in AValue`；`property OnHelpClicked: TNotifyEvent`（帮助按钮转发）。
- 组件：published 末尾（`OnPreview` 后）加 `OnHelpClicked`；public `function BuildForm: TTyFileDialogForm;`（就是现在 `Execute` 里 `ShowModal` 之前那段，另：`ofShowHelp` → 加帮助按钮）；public `procedure ApplyResult(AOK: Boolean; const AFileName: string; AFiles: TStrings);`：先去 `ofExtensionDifferent`；OK 时写 `FFileName`/`FFiles`，没有 `ofNoResolveLinks` → `GetPhysicalFilename(…, pfeOriginal)`；没有 `ofNoChangeDir` → `InitialDir := ExtractFilePath(FFileName)`（空则看 `Files[0]`）；`Files.Count <= 1`、`DefaultExt <> ''` 且 `CompareFileNames('.' + DefaultExt 去掉前导点, ExtractFileExt(FFileName)) <> 0` → 置 `ofExtensionDifferent`。`Execute` = `BuildForm` → `ShowModal` → `ApplyResult`。
- 文件头注释「表单不能无头建」改成现状。`ImageCollectionEditor` 改 `ofAllowMultiSelect`。两个示例 `.lfm` 的 `fdo*` 换成 `of*`。
- [ ] 测试：
  - 旧窗体文本 `object D: TTyOpenDialog Options = [fdoOverwritePrompt, fdoAllowMultiSelect] end` 读入 → `[ofOverwritePrompt, ofAllowMultiSelect]`；四个旧名各一遍。**M8-1** 去掉别名注册 → 读入抛异常（红）；**M8-2** 别名错位（PathMustExist↔FileMustExist）→ 红。
  - 新窗体写出用 `of*` 名字；默认 `[]` 不写。**M8-3** 默认改成 LCL 的 → 红。
  - `TyFileDialogCheck`（临时目录、真实文件、`FileSetAttr` 只读文件）：每个选项单独一行，外加顺序（同时 `PathMustExist`+`FileMustExist` 时目录缺失报 `fdcPathMissing`；`FileMustExist`+`CreatePrompt` 时报 `fdcFileMissing`）。**M8-4** 删掉 `ofPathMustExist` 分支 → 红（这正是 3.0 的 bug）；**M8-5** 交换前两步 → 红；**M8-6** 只读检查不看属性 → 红；**M8-7** 打开模式也问覆盖 → 红。
  - `ApplyResult`：`DefaultExt='txt'`、结果 `a.md` → 含 `ofExtensionDifferent`；`a.txt` → 不含；两个文件 → 不含；`DefaultExt=''` → 不含；先前就带着这一位、这次相同 → 被清掉。**M8-8** 不先清 → 红。`InitialDir` 没 `ofNoChangeDir` → 结果目录，有 → 不变；取消 → 都不变。**M8-9** 忽略 `ofNoChangeDir` → 红。
  - `BuildForm`：`ofForceShowHidden` → 列表 `ShowHidden`；`ofAllowMultiSelect` → `MultiSelect`；`ofShowHelp` → 有帮助按钮且点击触发 `OnHelpClicked`（Sender 是组件），没有 → 无此按钮。**M8-10** 不接 `ShowHidden` → 红。
  - `ofNoResolveLinks`：本机 `GetPhysicalFilename` 原样返回，测不出（Task 12 记入未覆盖）。
- [ ] 提交 `feat(filedialog): Options take LCL's TOpenOptions; old fdo names still load`（`Refs #28`）。

### Task 9：选文件夹

**Files:** `Dialogs.SelectPath.pas`、`StrConsts`/.pot/.po、`test.dialogs.selectpath.pas`。

- 纯校验：`TTySelectPathCheck = (spcOK, spcParentMissing, spcMissing, spcNotWritable, spcAskCreate)`；`function TySelectPathCheck(const APath: string; AOptions: TOpenOptions): TTySelectPathCheck;` 不存在时：`ofPathMustExist` 且上一级不存在 → `spcParentMissing`；`ofFileMustExist` → `spcMissing`；`ofCreatePrompt` → `spcAskCreate`；否则 `spcOK`（照 3.0 回落到树节点）；存在时 `ofNoReadOnlyReturn` 且 `not DirectoryIsWritable` → `spcNotWritable`。
- 窗体：`property Options: TOpenOptions`、`property OnHelpClicked`；`CloseQuery` 覆写：`inherited`，`ModalResult = mrOK` 时取路径框文字（空则树节点），按校验结果报错（`rsFdPathMustExist` 用上一级 / 本身）或询问创建（是 → `ForceDirectories`，失败报 `rsDlgCreateFolderErr`）。
- 组件：published 末尾加 `Options: TOpenOptions default []`、`OnHelpClicked`；public `BuildForm`；`Execute` 确定后没有 `ofNoResolveLinks` → `GetPhysicalFilename`。帮助按钮仅 `ofShowHelp`。
- [ ] 测试：校验函数每种结果各一行 + 无选项时不存在的路径返回 `spcOK`（**M9-1** 默认也报缺失 → 红：3.0 行为被改）；**M9-2** `ofPathMustExist` 查本身而不是上一级 → 红；`BuildForm` 的 `Options` 传进窗体、帮助按钮（同 Task 8）；默认值不写窗体（**M9-3**）。
- [ ] 提交 `feat(selectpath): Options with LCL's TOpenOptions`（`Refs #28`）。

### Task 10：文档

**Files:** `docs/controls/dialogs.md`（§8.5、§9.1、§9.2、§10）、`docs/controls/filedialog.md`。

- 每个对话框一张「实现 / 不起作用 / 不适用」表（同第三节，说明写成用户看的话）；新属性、事件、`BuildForm`；`filedialog.md`：`Options` 类型换成 `TOpenOptions`、旧名字照读、旧代码带 deprecated 警告照编、示例代码改 `of*`；D3 的三处可见变化写成「从 3.0 升级」小节（在 `dialogs.md` §10 与 `filedialog.md` 各写对应的那条）。
- [ ] 提交 `docs(dialogs): option tables for the font, color, file, folder and find dialogs`（`Refs #28`）。

### Task 11：收尾前自查（不编译）

- [ ] 按第三节逐项对代码：每个「实现」项能指到代码行和测试；每个「不起作用」项代码里确实没用到；新 `resourcestring` 三处都有。

### Task 12：一次编译、测试、变异、签收

- [ ] `rm -f source/*.ppu source/*.o`；`lazbuild -B tests/tytests.lpi`。
- [ ] 复制 `tests/tytests.exe` → `tests/tytests-dlg28.exe`，相关 suite 逐个跑，再全量（`--all --format=plain`，输出重定向到 scratchpad，判据是有 `Number of run tests` 行）。
- [ ] G9：`python scripts/gen-mimic.py`，`git diff tests/test.customclasses.mimic.pas` 只多 `TTyFontComboBox`、`TTyFontListBox` 的 `property FixedPitchOnly;`。G10：`TY_WRITE_FRESH_STREAMS=1` 跑 `TTyCustomClassesGuardTest.TestFreshFormFileTextUnchanged`，`fresh-streams.txt` 应无变化（默认 False 不写）。
- [ ] 集中修红，重编，重跑。
- [ ] 集中变异：按上面的 M 编号逐个改源（Python 按字节替换、断言命中 1 次、写回原字节还原，不用 git），每个变异后重编、跑对应 suite，记录红/绿；全部还原后重编、再跑全量一次。
- [ ] 末尾签收：全量条数、红名单（含偶发单跑确认）、变异结果表、未覆盖项。
- [ ] 提交 `test(dialogs): sign off the dialog options plan`（`Fixes #28`）。

---

## 后续（不在本计划）

- LCL `TOpenDialog` 的 `OptionsEx`、`OnFolderChange`、`OnSelectionChange`、`OnTypeChange`，`TCommonDialog.Title`、`HelpContext`：LCL 窗体若存了它们，换成 Ty 对话框读入会报未知属性。
- 示例自带的 `tycontrols.zh_CN.po` 副本同步。

## 签收（2026-10-05）

**提交**（起点 `140496e6`）：`dd92f87f` 计划 → `bf9c849a` FontFamilies → `67c1f723` FixedPitchOnly → `a5957091` 终端示例（Fixes #27）→ `f5b60a4a` 按钮栏 → `5cb993a8` 文字 → `26e29b1a` 查找 → `99a7fa95` 字体对话框 → `9540a665` 颜色网格 → `937b66f1` 颜色对话框 → `64981c85` 文件对话框 → `e5b20298` 选文件夹 → `7e21dd6b` 文档 → `5e1cc7af` G9 mimic → `a6cc92be` 网格测试加强 → 本签收（Fixes #28）。

**编译**：`lazbuild -B tests/tytests.lpi` 一次过（只修了一处漏写的 `type`），本批单元无新警告。

**全量**（`tests/tytests-dlg28.exe --all`，变异后 `-B` 重编再跑）：**8836 条，0 错 0 败**，忽略 1 条（`TSelectPathOptionsTest.TestNoReadOnlyReturn`：Windows 上给文件夹设只读属性不影响写入，造不出「不可写的文件夹」）。第一次全量唯一的红是 G9（mimic 尚未重新生成），重新生成后绿。

**G9 / G10**：`gen-mimic.py` 的 diff 只多 `TGenFontComboBox`、`TGenFontListBox` 各一行 `property FixedPitchOnly;`；`TY_WRITE_FRESH_STREAMS=1` 重写 `fresh-streams.txt` 内容无变化（只有行尾，未提交内容差异）。

**变异**（52 个，按字节替换、写回原字节还原、每个变异重编）：51 个第一次就红；**M7-1**（`ClearColors` 不清选中）第一次存活——测试选的是 VGA 后面的格子，清空后新加的第 0 格碰不到那个旧下标；改成选第 0 格（`a6cc92be`）后复跑变红。另加了计划外的 M2-*L（列表框同款）、M8-11（帮助按钮不看 `ofShowHelp`）、M9-4（`BuildForm` 不传 `Options`），全红。

**未覆盖**：
- `ofNoResolveLinks`：Windows 上 `GetPhysicalFilename` 原样返回，本机测不出，只能读码确认（文件、选文件夹两处）。
- `TySelectPathCheck` 的 `spcNotWritable`：同上，Windows 造不出不可写的文件夹，测试被忽略。
- 弹出的消息框（`TyMessageDlg`）是模态的，文件 / 选文件夹对话框里「判断结果 → 报哪句话」的映射只读码，判断本身由纯函数测住。
- 非 Windows widgetset 上的等宽 / 点阵判断只按 LCL 源码核实（V3–V6），没有真机。

**与计划的出入**：
- 新文字集中在一个提交（`5cb993a8`），没有分散到各任务。
- 枚举别名没有在 `finalization` 里 `RemoveEnumElementAliases`：它会删掉 `TOpenOption` 上**所有**别名（包括别人注册的），而包从不卸载。
- 文档（Task 10）挪到编译之后写，好让文档里的名字以编译通过的为准；颜色测试里一个写错的期望条数（应为 5）随文档提交一起改了。

## 集成与期末修复（2026-10-05，`feat/4.0-batch`）

三个分支（#9 标题栏、#14 typeKey 链、#27/#28 对话框选项）合进 `feat/4.0-batch`（`d509261d`）后整批审查，下面是按审查意见做的修复，每项一个提交（正文按 issue 写 `Refs`）：

| 提交 | 处理 |
|---|---|
| `0d0a2758` | 字体对话框 `fdLimitSize` + 原字号 0：显示的 9 被范围夹过时写回夹过的值，未被夹才保留 0（#28） |
| `2e5f883e` | 字体框 / 字体列表切换 `FixedPitchOnly`：原地重填、按名字找回选中，不再选第一行；没选中的仍不选；选中的字体族不变不发 `OnChange`、变了只发一次（#27） |
| `072528cb` | `TyGetFontFamilies` 所有列表（过滤与不过滤）都不列 `@` 竖排字体；字体对话框的不过滤列表也走它；写进升级说明（#27） |
| `4e7ce551` | `dialogs.md` §10 写成「从 3.0 升级须知」：所有 3.0 窗体里的查找 / 替换对话框都多出复选框，给 `.lfm` 与代码两种恢复写法；demo 的替换对话框补 `frHidePromptOnReplace`（#28） |
| `396e5c67` | 示例里的库翻译副本补这批界面上看得见的字符串：50 份都补窗口菜单 4 项（每个示例都有标题栏），demo / dialogs / ribbon 补「整个范围」「替换前提示」，filedialog 补文件对话框 3 条新消息（#9、#28） |
| `1e37ab32` | 选文件夹组件在 Linux / macOS 上把 `Directory` 的符号链接换成实际路径，写进 §8.5「从 3.0 升级」（#28） |
| `0f81e711` | 选文件夹路径框里的相对路径按树上选中的文件夹展开（不再按进程当前目录）；没选中时带三个存在性选项之一就报错；报错 / 询问走虚方法，OK 路径可无头测（#28） |
| `c2b3ceca` | 标题栏：Win32 顶边缩放热区清掉图标按下标记；图标跟随窗体 / 程序图标变化重画（`TTyForm` 经 `CM_ICONCHANGED` 转告 `HostIconChanged`），缩放好的图标按「图源 + 边长 + 版本号」缓存；菜单开着时单击图标只关菜单；焦点在 bar 上宿主放的窗口化控件里时菜单键不弹窗口菜单；文档写明右键不再冒泡到窗体的 `PopupMenu`（#9） |
| `7a80d1f4` | 新增 `TyTryRegisterTypeKeyParent`；`tycss-reference` §4.5 中英补「按属性组交错」「链根以下同一阶段先内置层后用户层」「`initialization` 里抛异常会让程序起不来」；补四角圆角还原测试（#14） |
| `f6dcc412` | 文件对话框「询问创建 / 询问覆盖」走虚方法 `ConfirmChoice`，补测试（#28） |
| `22fcad6a` | `FontFamilies` 单元头、`BuildForm`、`RefreshFonts` 文档改成实话：LCL 只填一次 `Screen.Fonts`，运行中新装的字体要重启程序（#27、#28） |
| `8ec8d708` | `rsTyWindowMenu*` 挪出 `rsTyToolWindow*` 那组；`.pot` 末尾补回生成器写的空行（提交的那份在 `e796fc02` 里丢了它，每次编包都把工作树弄脏）（#9） |
| `68b8bf33` | `tycontrols.strconsts.en.po` 删掉追加的 4 条与英文相同的翻译（文件头写明故意最小化）（#9） |
| `539736ce` | `dialogs.md` §10 中英混排改成全中文（#28） |

**编译**：`lazbuild -B tests/tytests.lpi` 通过，本批改过的单元没有新警告（StyleModel、Form 里的三条是原有的）；设计期 7 个单元用 fpc 对着测试构建的运行时单元、IDEIntf / SynEdit / LazControls 的已编单元单独编过，0 错误（4 条警告在 AdvChart 编辑器里，原有），输出只进 scratchpad。

**全量**（`tests/tytests-batchfix.exe --all`，即合并后的整批）：**8931 条，0 错 0 败**，没有计时类偶发红。合并前三份签收分别是 8836 / 8799 / 8793（各自分支）；本轮新增 22 条。`main` 上那 4 个 3.0 移植提交（`34d58e8a` 按钮栏不给隐藏按钮留空、`1f69a555` 隐藏按钮不定按钮栏高度、`bf26ce09` 文件对话框 `ofPathMustExist` / `ofFileMustExist`、`92076c03` 查找对话框的隐藏 / 禁用 / 帮助）带来的测试在 4.0 路径下全部跑到且全绿：`TestAHiddenButtonLeavesNoGap`、`TestAHiddenButtonDoesNotSetTheBarHeight`、`TFileDialogValidationTest` 的 5 条、`TFindOptionsTest` 的 7 条。`TTyCustomClassesGuardTest` 连跑 3 次，11/11 全绿。

**G9 / G10**：`gen-mimic.py` 重生成无 diff（没有新 published 属性）；`TY_WRITE_FRESH_STREAMS=1` 重写 `fresh-streams.txt` 内容无变化（只有写出时的 LF，已转回 CRLF）。`check-lfm-props` 通过，`check-example-po` 101 个文件 0 问题。

**变异**（按字节替换、断言命中 1 次、写回原字节并核对、每个变异后重编再跑相关 suite）：

| 变异 | 改了什么 | 结果 |
|---|---|---|
| M28f | 原字号 ≤0 一律保留 0（审查时存活的那个） | 红 |
| M28f2 | 原字号 ≤0 一律不保留 | 红 |
| M27c / M27cL | 切换 `FixedPitchOnly` 退回选第一行（字体框 / 列表） | 红（4 / 1） |
| M27d / M27dL | 不管变没变都发 `OnChange` | 红（2 / 2） |
| M27e / M27eL | 变了也不发 | 红（1 / 1） |
| M27f | `TyGetFontFamilies` 不滤 `@` | 红（字体族 2、字体框 3、列表 4、对话框 1） |
| M27g | 字体对话框不过滤时退回 `Screen.Fonts` | 红 |
| M28g | 相对路径不展开 | 红 |
| M28h | 没选中时相对路径不拒绝 | 红（2） |
| M9c | `IconChanged` 不 `Invalidate`（审查时存活的那个） | 红 |
| M9d | `IconChanged` 不升版本号（缓存不失效） | 红 |
| M9e | `TTyForm` 不改接 `Icon.OnChange` | 红 |
| M9f | `CMIconChanged` 不转告标题栏 | 红 |
| M9g | 图标单击不看菜单开着 / 刚关 | 红 |
| M9h | 菜单键不看焦点在宿主子控件上 | 红 |
| M9i | 顶边热区不清图标按下标记 | 红 |
| M9j | 默认菜单关闭不记时 | 红 |
| M14b | `RestoreProps` 不还原四角 `Radius`（审查时存活的那个） | 红 |
| M14c | `TyTryRegisterTypeKeyParent` 出错仍返回 True | 红 |
| M14d | `outline-offset` 不算进 outline 组 | 红 |
| M28a | 选中集里的输入名再查一次（审查时存活的那个） | 红 |
| M28i / M28j | 询问创建 / 覆盖不问直接放行 | 红（2 / 1） |

**选择与理由**：
- `@` 竖排字体：普通列表也过滤。LCL `TFontDialog` 在 Windows 上就是 `ChooseFont`，它不列这些；GTK / Qt / Cocoa 本来不报；它们在横排控件里字是躺着的。3.0 列出它们，写进 `fontcombobox.md` / `fontlistbox.md` / `dialogs.md` 的升级说明。
- 选文件夹相对路径：展开而不拒绝。路径框平时显示选中文件夹的完整路径，在上面输一个名字的意思就是「在这里面」，Windows 选文件夹对话框也这样；没选中时无从展开，才拒绝。输入过程中只跟随完整路径，免得选中的文件夹在手底下变动。
- `outline-offset`：不拆成单独属性位，只写文档。组的划分和 StyleOverride 合并是同一套；拆开要给样式集加新的 `Present` 标志，所有读它的地方都得认，而只有父子键在不同阶段分写同一个焦点环的两半时才碰得到。

**未覆盖 / 要人看的**：
- 图标单击「只关菜单」在真机上依赖弹出菜单自己的失活关闭（点击主窗口 → 延迟关闭），测试只模拟了「菜单开着」「刚关」两种顺序。
- 标题栏放在非 `TTyForm` 的窗体上时，窗体 / 程序图标的变化要宿主自己调 `HostIconChanged`（文档已写）。
- `ofNoResolveLinks`、选文件夹的不可写文件夹：同前，Windows 上测不出。

**主控待做**：编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编示例冒烟（toolwindows 的图标与窗口菜单、demo 的替换对话框）；合 `main` 时注意 `main` 在本分支起点之后又有 `672c16c9`、`12ca184f`（3.0 的 `@` 字体修复，`TyFontPickerFamilies` 与「只有过滤单元读 `Screen.Fonts`」的源码守卫）、`0fb45bbc`（文件对话框 OnCanClose 只问通过校验的名字），与本批在 `FontComboBox` / `FontListBox` / `Dialogs.Font` / `Dialogs.FileDialog` / `.pot` 及对应测试上会冲突——4.0 一侧以 `TyGetFontFamilies` 为准（`TyFontPickerFamilies` 可改成调它），守卫要放行 `tyControls.FontFamilies`；合完再跑一次全量。
