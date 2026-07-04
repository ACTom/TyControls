# 更新日志

本文件记录 **ty-controls** 的所有重要变更。项目采用 3 段式语义化版本号(`主版本.次版本.修订号`)。
所有控件均由 BGRABitmap 全自绘、由轻量 `.tycss` 文本主题统一着色 —— 在 Windows、Linux、macOS 上
像素级一致。

> English: [CHANGELOG.en.md](CHANGELOG.en.md).

## [2.2.0] — 2026-07-04

一个大型功能版本。主角是**对话框子系统**:为 **TTyForm** 补齐了完整的窗口镶边(caption 按钮),
新增 **11 个全自绘对话框组件**、配套的全局函数、IDE 集成与独立示例;同时新增**三个小控件**
(三态 CheckBox、可编辑 ComboBox、TTyTabSet),并修复了大量在真机(尤其 Win10 DWM 玻璃)上才暴露的问题。

### 新增 — 对话框

- **TTyForm 窗口镶边** —— caption 按钮由 **`BorderIcons` + `Resizable`** 驱动:`BorderIcons:=[]`
  可去掉全部按钮;`BorderStyle` 锁定为 `bsNone`(强制 setter);把标题栏关联到别的窗口会抛异常
  (跨窗口守卫)。`ShowMinimize` / `ShowMaximize` 旧开关移除,`BorderIcons` 成为唯一来源。
- **11 个全自绘对话框组件** —— 与 LCL 对齐,既有组件也有全局函数:
  - **TTyMessage** —— 消息框(`TyShowMessage` / `TyMessageDlg`),按钮标题 / 结果 / 顺序与类型图标齐全。
  - **TTyInputDialog / TTyPasswordDialog / TTyTextDialog** —— 单行输入、掩码密码、可缩放多行文本
    (`TyInputQuery` / `TyInputBox` / `TyPasswordQuery` / `TyTextQuery`)。
  - **TTySelectValueDialog** —— 列表取值选择器。
  - **TTySelectPathDialog** —— 惰性目录树的文件夹选择器,带**新建文件夹**、文件夹图标、更宽松且随
    悬停高亮的行。
  - **TTyColorDialog** —— 单模型多视图同步的取色器(HSV 方块 + 色相条 + RGB / CMYK / Alpha / Hex)。
  - **TTyFontDialog** —— 字族 / 字号 / 样式 / 颜色 / 预览的字体选择器。
  - **TTyFindDialog / TTyReplaceDialog** —— 无模态查找 / 替换(LCL `TFindOptions` 对齐,
    `OnFind` / `OnReplace`)。
  - **TTyProgressDialog** —— 应用驱动的无模态进度对话框,带 Cancel。
  - 所有 11 个组件都补齐了 **`OnShow` / `OnClose` / `OnCanClose`** 事件(LCL 对齐)。
- **IDE 集成** —— 新增 **TyControls Dialogs** 组件面板分组、11 个对话框的调色板图标、File > New 的
  **TyControls Dialog** 新建项;在设计器中**双击**任一对话框组件即可预览。
- **示例** —— 新增独立的 **dialogs 示例**展示全部 11 个对话框;主 demo 也加入了三列对话框网格。

### 新增 — 三个小控件

- **三态 CheckBox** —— `State` / `AllowGrayed`,带灰显(不确定态)glyph。
- **可编辑 ComboBox** —— `csDropDown` 自由输入 + 前缀自动补全弹层,并转发 `MaxLength` / `CharCase`。
- **TTyTabSet** —— 基于 TabStrip 引擎的纯标签条控件(带调色板图标与组件注册)。

### 新增 — 示例整体翻新

- 所有单控件示例统一迁移到 **TTyForm + TTyTitleBar** 镶边骨架,不再是裸 LCL 窗口;每个示例都更
  充分地演示了对应控件的关键特性(如 checkbox 演示三态、combobox 演示可编辑 + 自动补全)。
- 新增 7 个专属示例:tabset、calendar、datetimepicker、splitter、statusbar、toolbar、menu;
  `tabcontrol` 示例改写为 TTyPageControl + TTyTabSheet。

### 修复

- **Win10 DWM 玻璃穿透** —— 每个 TTyForm 都带整块客户区玻璃扩展,任何 alpha-0 像素都会透出玻璃
  (失焦时发白)。多处修复:TTyPageControl / TTyTabSheet / TTyGroupBox 标题带 / 标签条右侧空白 /
  对话框内容区改为**填充不透明主题背景**(新增 `TyPageControl` / `TyTabSheet` 主题规则并同步到全部
  内置主题);Vista–10 阴影扩展改用 sheet-of-glass 边距 `{-1,-1,-1,-1}`,消除随激活变白 / 变灰的
  1px 窗口边线;拦截 `WM_NCACTIVATE` 避免非激活态非客户区边框绘制;`TyResolveParentBg` 会向上
  穿过透明容器找到不透明背景,补齐圆角控件的角落缝隙。
- **禁用控件玻璃化** —— `:disabled` 的整体 opacity 之前用 `ApplyGlobalOpacity` 乘到每个像素的 alpha 上,
  使不透明背景变半透明、透出 DWM 玻璃(失焦时全白)。改为 `TTyPainter.OpacityBase`:先铺一层不透明
  底色再叠加淡化内容,观感一致但保持 alpha-255。
- **可缩放 TTyForm 侧边条纹** —— `WM_NCCALCSIZE` 不再内缩客户区,避免把 `WS_THICKFRAME` 原生边框
  (DWM 强调色 / 白)暴露成左右竖条。
- **可编辑 ComboBox** —— 自动补全弹层弹出时不再抢走内嵌编辑器焦点(第二个字符不再丢失);
  弹层就地 `Resize` 刷新过滤列表,不再闪烁;点击弹层行读取实际显示的列表(修正取错列表 / 提交错文本)。
- **标签条溢出箭头**遮住首 / 尾标签 —— 引入 `HeaderShiftPx`,把标签统一渲染在左右箭头之间的带内
  (影响 TTyTabSet 与 TTyPageControl)。
- **TTyDateTimePicker** —— 通过全局默认控制器着色(`Controller` 为 nil,即常规用法)时,打开日期下拉
  不再因 `FCalendar.Controller.Model` 空引用而崩溃;改用 nil-safe 的 `ActiveController`。
- **TTyProgressDialog 闪烁** —— 放弃原生 TPanel 宿主方案,改为把可视刷新节流到 ~20fps(始终保留最新
  进度 / 文本,完成时强制刷出 100%),并关闭进度条动画、固定状态标签宽度。
- **TTyForm 双击最大化崩溃** —— `ToggleMaximize` 为 `Screen.MonitorFromWindow` 可能返回 nil 加了
  守卫(回退到主显示器工作区)。
- **国际化** —— 运行时加载 `tycontrols` 包词条目录(消息框按钮显示"确定"而非 "OK");catalog 部署为
  无点号文件名以绕开 LCL `ChangeFileExt` 的截断;dialogs 示例补齐 exe 名词条目录并把代码中的英文
  硬编码串改为 resourcestring;跟随系统语言自动检测。
- **示例真机修复** —— 若干示例的启动崩溃(状态标签在 `OnChange` 之前尚未创建)、GroupBox 标题带遮挡、
  splitter 停靠一侧不可拖动、以及把不存在的 `StyleClass` 变体当功能演示等问题。

## [2.1.1] — 2026-06-30

一个修复版本,集中处理 green 图片主题的真机观感,以及 IDE 设计期的若干小问题。

### 修复

- **green 主题** —— 所有容器(toolbar、titlebar、statusbar、panel、groupbox、tab、分隔符、滚动条)
  改为 **100% 透明**,照片背景干净透出,不再有磨砂或纯色填充。
- **TTyForm 玻璃/照片背景** —— 应用主题时即时重建:用 Custom… 选图片主题后背景图**立刻出现**
  (不再需要先最小化/最大化触发);工具栏、状态栏也会采样照片透出。
- **最小化** —— 主窗口最小化到任务栏(而不是缩到屏幕角落的小方块);最小化弹出子窗口不再连累整个应用。
- **TTyToolBar 分隔符** —— 实心主题下与工具栏背景无缝(去掉怪异的填充色块),图片主题下透出照片。
- **IDE 设计器**
  - 切换 **TTyPageControl** 页面后旧页控件不再残留(先置 `csNoDesignVisible` 再改 `Visible`,使可见性即时重算)。
  - **TTyTreeView / TTyListBox / TTyMemo** 的内部子控件(滚动条、TTyTreeView 的内联编辑器)不再在设计器中露出。

## [2.1.0] — 2026-06-30

一个大型功能版本。主角是 **TTyTreeView**(一个 VirtualTreeView 级别的虚拟树),同时新增另外五个控件、
为 **TTyForm** 加入原生窗口缩放与窗口特效,并为整个库加上键盘助记符。

### 新增 — 新控件

- **TTyTreeView** —— 虚拟、数据按需加载的树,可承载百万级节点:
  - 三阶段惰性初始化;增量高度/位置缓存 + 快速命中测试。
  - 多列 + 可拖拽表头 —— 列**调宽**、**重排**、**自动列宽 / 弹性列**。
  - **排序** —— `OnCompareNodes`、点击表头切换升降序(带方向箭头)、惰性感知的归并排序。
  - **复选框** + 三态 + 自动三态传播,以及**单选(radio)**节点。
  - **多选**(Ctrl / Shift / Ctrl+A)与**整行选择**。
  - **逐节点可变行高**(`OnMeasureItem`)。
  - **增量输入查找**(type-to-find)。
  - **逐单元格自绘**(`OnDrawNode` / `OnAfterCellPaint`)。
  - **内联单元格编辑**(F2 / 双击;Enter 提交、Esc 取消;`OnEditing` / `OnNewText`)。
  - **树内节点拖放** —— 重排或改变父子关系,带 accent 落点标记与循环重父化守卫。
- **TTySplitter** —— 拖动以调整相邻控件大小。
- **TTyStatusBar** —— 分栏状态栏。
- **TTyToolBar** —— 带分隔符的工具栏。
- **TTyDateTimePicker** —— 分段式日期/时间编辑 + 下拉日历 + 时间微调。
- **TTyCalendar** —— 支持 日 → 月 → 年 逐级钻取的日历。

### 新增 — TTyForm

- 原生窗口**缩放**(Windows 自绘边框:`WS_THICKFRAME` + `WM_NCCALCSIZE` / `WM_NCHITTEST`),
  新增 **`Resizable`** 属性;最大化铺满显示器工作区;标题栏拖动 + 顶边缩放。
- 系统**圆角 + 原生投影**(Windows 11 DWM / macOS),默认开启,可通过 CSS 关闭。

### 新增 — 交互、主题、国际化

- **助记符(Mnemonics)** —— `&` 加速键,Alt 下划线显示 + Alt+字母激活,覆盖菜单、按钮、复选框、
  单选钮、分组框、标签、标签页。
- **TTyNativeStyler** —— 让原生 / 第三方 LCL 控件与当前主题协调一致。
- **TTyComboBox** —— 共享的主题化下拉浮层。
- **国际化** —— `resourcestring` + 英文与简体中文 `.po` 词条(主题诊断、设计期字符串、演示程序),
  演示程序支持运行时切换语言。

### 修复

- **TreeView** —— 节点图标不显示(ImageList 绘制被 BGRA 合成覆盖,改为合成之后再画;真正的根因是
  在加列之前就设了 `MainColumn`);HiDPI 垂直轴(滚动 / 命中测试 / 滚动到可见);超大范围的内嵌
  滚动条(最小滑块尺寸、64 位位置映射、构造期创建);展开箭头尺寸;水平滚动;销毁时托管节点数据
  泄漏;删除 / 清空时多选计数完整性。
- **TTyForm** —— 最大化底边钻到任务栏下方;双击最大化"原地变大";顶边缩放;顶部边框过宽。
- **主题** —— 双模式主题以无模式方式加载时崩溃;`TTyNativeStyler` 在深色主题下的文字颜色。
- **TTyEdit** —— 光标高度改为跟随字体行高(原先绑定盒子高度,在树的内联编辑器等紧凑宿主里只有半高)。
- **TTyMemo** —— 文本测量性能(逐行宽度缓存)。

### 平台

- **macOS** —— 编译 + 运行修复(系统主题检测用 process 单元、`CGFloat`、多显示器启动定位)。
- 自绘编辑控件的**输入法(IME)**支持(Qt6 / GTK2)。

### 说明

- 原生窗口缩放本版本**仅 Windows**;GTK / Qt / Cocoa 回退到手动缩放边距(原生交接计划中)。

## [2.0.0] — 2026-06-20

2.x 初始基线:基于 `.tycss` v2 主题引擎(先合并后解析、分层 token、双 `@mode`、跟随系统亮/暗 + 强调色、
热重载 + lint)的全自绘控件集,12 套内置主题,逐控件 `About` 元数据,以及发布工具链。
