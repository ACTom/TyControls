# TyControls 控件完善程序 · API 事件/属性 与 LCL 原生对齐 设计文档

- **日期:** 2026-06-16
- **前置:** `main`(Phase 0 + 批①②③④⑤⑥ + empty-FontName 修复 已合入,732 测试,0 失败,15 无头 env 错误)。
- **定位:** 程序最初定的"API 补全(横切基线 + 高频专属)"那一层的**事件 + 属性 与原生对齐**正式批次。用户选定 **事件 + 属性 全部一次做**。
- **来源:** 一次 18-agent 审计 workflow(`api-events-parity-audit`)的结论。
- **执行约定:** 沿用项目惯例 —— PPI=96;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests.exe -a --format=plain`;现有测试保持全绿、不改既有测试语义。基线:0 failures + 15 无头 win32(error 1407)env 错误(非回归)。`examples/demo/*` 是用户测试台,每个任务只 stage 自己的文件。

---

## 1. 核心发现(审计)

这**绝大部分是"只缺 published"** 的差距:两个基类(`source/tyControls.Base.pas` 的 `TTyGraphicControl` published 块 ~38-45、`TTyCustomControl` ~74-83)**重新发布了零个**继承事件,所以全部 16 个控件只暴露 `Enabled/Font/Hint/ShowHint/StyleClass/Controller`(+ 窗口类 `TabOrder/TabStop`)+ 少数专属。关键:**每一个 override 的 `MouseDown/KeyDown/…` 都已调用 `inherited`**(Base.pas 211-431 + 各控件审计确认),LCL 的派发字段/方法完好 —— 事件名一旦 published 就立即触发。**无需任何 `inherited` 补调**。

两个真·行为 BUG(非 publish 缺口):
- **`TTyEdit.OnChange` 打字时永不触发** —— `DoChange`(Edit.pas ~225-228)只在 `RestoreState`(undo/redo,~274)调用;`InjectKey`(~921-953)/`InjectBackspace`(~955+)/`InjectDelete`/`DeleteSelection`/`Paste`/`Cut`/`SetText` 都不调。
- **`TTyCheckBox` 完全没有 `OnChange`** —— `SetChecked` 只 `Invalidate`。

## 2. 核心原则

事件以"基类基线发布 + 控件专属"两层完成;属性补到接近原生但**跳过与主题冲突的**(见 §5)。一切向后兼容(新增 published/事件/属性是叠加;发布事件不改运行逻辑——逻辑早已 `inherited`)。**有意行为变化**:Edit 打字现在触发 OnChange、CheckBox/ProgressBar 新增 OnChange、Track/ScrollBar 滚轮现在步进(见 §6)。

## 3. 范围 · 事件

### 3.1 基线发布(`source/tyControls.Base.pas` 两个 published 块)
- **Tier A · 通用**(加到 **两个** published 块:`TTyGraphicControl` 38-45 与 `TTyCustomControl` 74-83;均 `TControl` 声明,base override 已 inherited):
  `OnClick`、`OnDblClick`、`OnMouseDown`、`OnMouseUp`、`OnMouseMove`、`OnMouseEnter`、`OnMouseLeave`、`OnMouseWheel`、`OnMouseWheelUp`、`OnMouseWheelDown`、`OnContextPopup`、`OnResize`、`OnChangeBounds`,以及属性 `PopupMenu`、`Constraints`、`BorderSpacing`、`Cursor`、`ParentShowHint`、`Action`。
- **Tier B · 可聚焦**(只加到 `TTyCustomControl` 74-83;`TWinControl` 声明;graphic 非窗口,**不能**进 graphic 块):
  `OnKeyDown`、`OnKeyUp`、`OnKeyPress`、`OnUTF8KeyPress`、`OnEnter`、`OnExit`、`OnEditingDone`。
- 注:`Visible` 可能 TControl 已默认 published —— 显式发布无害但**先确认不重复声明**(编译报重复就去掉)。`Align`/`Anchors` 各控件已 published,**不**上移基类。

### 3.2 控件专属事件
- **ComboBox**:`OnSelect`(用户从列表选定,区别于 OnChange)、`OnDropDown`(从 `DropDown` 触发)、`OnCloseUp`(从 `CloseUp` 触发);确认 `OnClick` 经基线获得。
- **ScrollBar**:`OnScroll`(`Sender; ScrollCode: TScrollCode; var ScrollPos: Integer`)—— 比 OnChange 更细,观察 sbLineUp/PageDown/ThumbTrack 等并可中途改值。
- **TabControl**:`OnChanging`(`var AllowChange: Boolean` 切页前否决,TPageControl 平价)、`OnReorder`(拖动重排已实现却无通知——切页/重排后触发)。`OnTabClose` 已有。
- **Memo**:`OnSelectionChange`(选区变化而非文本变化)。
- **ProgressBar**:`OnChange`(`SetPosition`/`SetMin`/`SetMax` 触发;与 Edit/SpinEdit 约定一致)。
- **FormChrome**:`OnCloseQuery`(`var CanClose: Boolean` 否决)、`OnClose`、`OnMinimize`、`OnMaximize`、`OnRestore`(目前 `DoClose` 无条件 `FForm.Close`,零生命周期事件)。
- 把**公有但未 published** 的 `AnimationsEnabled` 发布到 `TTyButton`/`TTyProgressBar`/`TTyScrollBar`(+ 确认 Toggle/Track/Tab 已 published)。

### 3.3 事件 BUG 修复(行为变化,单独提交便于二分)
- **Edit OnChange-on-typing**:在 `InjectKey`/`InjectBackspace`/`InjectDelete`/`DeleteSelection`/`InjectStringAt`(Paste)/`Cut`/`SetText` 各文本变更点调用 `DoChange`(注意防重入:避开 `FSuspendUndo`/批量内部重复触发;最终对外只在净变化时一次)。补测"打字触发 OnChange、撤销/重做触发、SetText 触发"。
- **Track/ScrollBar 滚轮步进**:override `DoMouseWheel`,在 thumb/控件上滚轮按 `SmallChange`/`LineSize`(ScrollBar)或 `LineSize`(TrackBar)步进 `Position`(返回 True 表示已处理)。当前滚轮无反应。

### 3.4 TTyTitleBar 例外(必须)
`TTyFormChrome` 内部 `FTitleBar.OnMouseDown/OnMouseMove/OnMouseUp/OnDblClick :=` 自己的处理做窗口拖动/双击最大化。基线发布会把这 4 个槽暴露在 `TTyTitleBar` 上,用户一赋值就**覆盖** chrome 接线。处理:`TTyTitleBar` **不**继承这 4 个的 published(它若直接派生基类,需在其 published 块显式不列、或把 chrome 内部接线改为**方法 override**而非事件槽——优先后者:把 `FTitleBar` 的拖动/双击逻辑从"赋值 OnMouseX"改为 TTyTitleBar 内部方法 override,腾出事件槽给用户)。实现时读 Form.pas 确认 TTyTitleBar 的基类与现有接线,选最干净的隔离方式。

## 4. 范围 · 属性(补到接近原生,跳过主题冲突项)

- **Edit**:`SelStart`/`SelLength`/`SelText`(接现有选区模型 `FSelAnchor`/`FCaret`/选区 API)、`Alignment`(taLeftJustify/Center/Right 绘制+光标对齐)、`CharCase`(ecNormal/UpperCase/LowerCase,输入转换)、`NumbersOnly`(只允许数字输入)。
- **Memo**:`SelStart`/`SelLength`/`SelText`/`CaretPos`(扁平偏移,接行/列模型)、`Text`(整体字符串访问器,现仅 `Lines: TStrings`)、`WantTabs`(Tab 进文本 vs 导航)、`WantReturns`(Enter 换行 vs 默认按钮)、`ScrollBars`(ssNone/ssVertical/ssHorizontal/ssBoth/ssAutoVertical… 控制内嵌滚动条显隐——接现有 FScrollBar)。
- **SpinEdit**:`ReadOnly`(锁编辑缓冲,保留 +/- 步进?——与原生一致:ReadOnly 锁文本编辑但仍可只读;按 LCL 语义实现)、`Alignment`、`MaxLength`。
- **ComboBox**:`DropDownCount`(下拉可见行数)、`Sorted`(排序 + 维持选中项)、`MaxLength`、`CharCase`。
- **Button**:`Default`(窗体回车默认按钮)、`Cancel`(Esc 取消按钮)、`ModalResult`(点击设窗体 ModalResult)、`Action`(经基线已发布 Action 属性;确认 ActionLink 生效)。
- **ToggleSwitch**:`Caption`(文本标签,TToggleBox 平价;绘制在开关旁)。
- **Label**:`Alignment`、`Layout`、`WordWrap`、`AutoSize`(随文本调整大小)、`Transparent`(默认透明已是?确认)、`FocusControl`(点 label 聚焦目标控件 + 助记符)。
- **ListBox**:`Sorted`(排序+维持 ItemIndex/选择)、`Columns`(多列,较大——若过深则标记拆后续)。

**深度提示(实事求是)**:`Memo.ScrollBars/WantTabs/WantReturns`、`Label.AutoSize/WordWrap`、`ComboBox.Sorted`、`ListBox.Columns`、`Button.Default/Cancel` 的窗体键路由 是真·小功能。尽力在本批做完;若某项 TDD 中证明是独立大件(尤其 `ListBox.Columns`、`Memo.ScrollBars` 全枚举),就地标记、拆到紧随后续,不硬塞坏质量。

## 5. 不做 / 跳过(主题冲突或不适用)

- `Color`、`Brush`、`ParentColor`、`ParentBackground`、`ParentFont`(主题字体解析冲突;`Font` 本身仍 published,只是不暴露 ParentFont 传播)、`Bevel*`、`BorderStyle`/原生 `BorderWidth`(主题边框经 StrokeBorder,原生会双画)、`DoubleBuffered`(Base.Create 强制 True 防闪,发布会让人关掉重现闪烁)。
- `OnPaint`(本批不加;一旦加,`TTyPanel/ProgressBar/TitleBar/CaptionButton` 的 `Paint` override 需补 `inherited Paint` 或显式 `OnPaint(Self)`——留后续)。
- CheckBox 三态(`State`/cbGrayed)——本批跳过(独立功能)。

## 6. 验收

- 现有 732 测试保持全绿。新增测试:
  - **基线事件**:为代表控件(如 Edit 窗口类 + Label graphic 类)断言"设了 `OnMouseDown`/`OnKeyDown`(Edit)/`OnClick` 处理器后,经 `MouseDown`/`KeyDown`/`Click` 注入会触发它"(无头经方法注入,access/直接调)。Tier B 不出现在 graphic 类(编译即证:若 graphic 块误加 OnKeyDown 会编译失败)。
  - **控件专属事件**:CheckBox `OnChange`(`Checked:=` 触发)、ComboBox `OnSelect/DropDown/CloseUp`、ScrollBar `OnScroll`、TabControl `OnChanging`(返回 AllowChange=False 阻止切页)/`OnReorder`、Memo `OnSelectionChange`、ProgressBar `OnChange`、FormChrome `OnCloseQuery`(CanClose=False 阻止关闭)/`OnClose/Minimize/Maximize/Restore`。
  - **事件 bug**:Edit 打字/退格/删除/粘贴/剪切/SetText 各触发一次 `OnChange`;撤销/重做仍触发。Track/ScrollBar 滚轮改 Position 且触发其 Change/Scroll。
  - **属性**:每个新属性的 getter/setter 语义测试(Edit `SelStart/SelLength/SelText` 读写与选区一致;`Alignment` 渲染像素;`CharCase` 输入转换;SpinEdit `ReadOnly` 拦截编辑;ComboBox `DropDownCount`;Button `Default/Cancel`(回车/Esc 触发 Click,经无头键盘注入);Toggle `Caption` 渲染;Label `Alignment/WordWrap/AutoSize`;ListBox/ComboBox `Sorted` 顺序)。
- 无头事件/键盘经方法注入(`MouseDown`/`KeyDown`/`UTF8KeyPress`/`Click`/access 子类);PPI=96。
- `bash scripts/build-matrix.sh` 全绿;heaptrc 0;终审通过;`docs/controls/*.md` 同步新事件/属性,新增 `docs/events.md`(或在各控件 md 补"事件"节)说明基线事件集 + 哪些主题冲突项被刻意跳过(原因)。

## 7. 兼容性 / 有意的可见行为变化

加 published/事件/属性是叠加,默认不变(除下列)。**有意行为变化**(用户可在 demo 验证):
1. Edit 打字现在触发 `OnChange`(此前只 undo/redo 触发——是 bug 修复)。
2. CheckBox / ProgressBar 新增 `OnChange`(此前无)。
3. TrackBar / ScrollBar 鼠标滚轮现在步进 `Position`(此前无反应)。
4. 全部控件现在暴露标准事件(`OnMouseDown` 等)——纯增强。
5. 禁用态下输入类事件不触发(多数 override `if not Enabled then Exit` 在 inherited 前;原生可接受);ScrollBar/TrackBar 滚轮、Memo ReadOnly 的 UTF8KeyPress 同此语义——记入文档。
6. `TTyTitleBar` 的窗口拖动/双击改为内部方法实现,其 `OnMouseDown/Move/Up/DblClick` 事件槽腾给用户。
