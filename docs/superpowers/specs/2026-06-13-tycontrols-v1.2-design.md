# TyControls v1.2 设计文档

- **日期:** 2026-06-13
- **状态:** 自主推进(用户授权"按你想法来")
- **前置:** v1+v1.1 已在 main(15 控件、263 测试)。本阶段取自 v1.1 终审遗留 + 路线图最高价值项。

## 1. 范围

### A. 一致性清理(v1.1 终审 minor)
1. **RenderTo 原点契约统一**:painter 位图以 (0,0) 为原点(BeginPaint 建 W×H 位图,EndPaint 按 FRect.Left/Top 贴回)。v1 控件归一化为 `Rect(0,0,W,H)`,但 ListBox/TrackBar/ProgressBar/ComboBox 用了 ARect 绝对坐标,ToggleSwitch 内部分裂(框架 ARect、旋钮 (0,0))。统一全部新控件为 (0,0)-local(与 Button/Edit/Panel 一致),消除非零原点调用的潜在错位。
2. **ListBox 内嵌滚动条**:宽度从创建时 PPI 冻结改为渲染期一致(在 UpdateScrollBar 里按当前 Font.PixelsPerInch 重算宽度);Controller 属性切换时传播到内嵌滚动条;ComboBox 弹层列表的 Controller 在每次 DropDown 时同步(而非仅首次)。
3. **ProgressBar 填充内缩边框宽度**:填充矩形 inset 掉已绘制的边框(Scale(S.BorderWidth)),不再压住边框线。
4. **Painter 卫生**:删除 DrawGlyph 死变量 `pts`;`style` 误报 hint 用 `Default(TTextStyle)` 消除。

### B. Edit 横向滚动
- 私有 `FScrollX`(设备 px,>=0)。每次光标移动/文本变化后 `EnsureCaretVisible`:光标像素 x 落在可视窗口外时调整 FScrollX(右越界:caret - 可视宽 + 余量;左越界:caret - 余量;clamp 0)。
- 渲染:文本/选区带/光标统一左移 FScrollX;`CaretIndexAtX` 把点击 x 加上 FScrollX 再映射。
- 文本删短/失焦不强制回 0,但 clamp 到最大可滚动量。
- 测试:长文本 END 后光标像素位置在可视区内;HOME 后 FScrollX=0;点击映射在滚动状态下仍 round-trip。
- KNOWN_GAPS 移除"无横向滚动"项(词级跳转仍保留为已知项)。

### C. TTyTabControl
- 单元 `tyControls.TabControl`;typeKey `TyTabControl`(整体框架),子部件 typeKey **`TyTab`**(页签头;`:hover` 悬停、`:active` 选中,延续 TyCaptionButton/TyListItem 先例)。
- API(钉死):
```pascal
TTyTabControl = class(TTyCustomControl)
  function AddTab(const ACaption: string): TTyPanel;  // 创建并返回该页的内容面板(Owner/Parent=Self,Align=alClient 于客户区)
  property Tabs: TStrings (read-only 视图,由 AddTab 维护;或暴露 TabCount/TabCaptions[i])
  property TabIndex: Integer;            // 切换显示对应页;-1 无;setter 夹取+OnChange(仅真变化)
  property TabHeight: Integer;           // 逻辑 px,默认 28
  property Pages[AIndex: Integer]: TTyPanel; // 只读
  property OnChange: TNotifyEvent;
end;
```
- 行为:页签头水平排布在顶部(宽度=文本测量+2×padding,最小 Scale(48));点击页签选中;键盘 ←/→ 切换;`AdjustClientRect` 顶部下移 TabHeight(页面板自动落在客户区);仅活动页 Visible。
- 渲染:DrawFrame 画整体(客户区背景/边框);每个页签头按 TyTab 解析样式画带+文本(选中 `:active`、悬停 `:hover`);页签溢出控件宽度时简单截断(v1.2 不做滚动页签,记 KNOWN_GAPS)。
- 几何纯函数 `TyTabHeaderRect(index)` 公开可测。

### D. 集成(沿用 v1.1 模式)
三主题补 `TyTabControl`/`TyTab` 规则 + 主题加载测试;lpk + Design 注册 + demo;`examples/tabcontrol` 示例;`docs/controls/tabcontrol.md`;tycss-reference typeKey 表、README(16 控件)、getting-started 示例表、KNOWN_GAPS 同步(加:页签不滚动;删:Edit 无横向滚动)。

## 2. 不做
词级跳转(Ctrl+方向);Windows native;动画;页签关闭按钮/拖拽排序/滚动(记 KNOWN_GAPS)。

## 3. 验收
263+ 测试全绿;矩阵全绿(含新示例);全套件 heaptrc 0 泄漏;终审通过;文档同步。
