# TyControls v1.1 设计文档(Phase 2)

- **日期:** 2026-06-13
- **状态:** 已确认
- **前置:** v1 已交付(见 `2026-06-11-tycontrols-design.md`):三层架构、CSS-lite 引擎、TTyPainter、10 控件、窗体子系统、三主题、双包、148 测试。

---

## 1. 目标

三个方向纳入同一阶段:

1. **Tier-2 控件 + ComboBox 真下拉** —— 补上 v1 头号已知限制,扩充控件面。
2. **v1 打磨** —— Edit 全套编辑体验、ScrollBar/CheckBox 样式管线补洞、LICENSE。
3. **窗体 native 增强(仅本机可验证项)** —— macOS 阴影、跨屏 DPI、红绿灯风格。

**明确不做(本阶段):** TTyTabControl(留下阶段);Windows Aero Snap / DWM 阴影(本机无交叉编译器,无法编译验证,不盲写——KNOWN_GAPS 继续明示);状态过渡动画;位图皮肤导入器。

## 2. A 部分 —— Tier-2 控件 + ComboBox 真下拉

### 2.1 实现顺序与依赖

`TTyListBox` **先做**,ComboBox 下拉弹层复用它。其余控件相互独立。

### 2.2 控件清单

| 控件 | 基类 | typeKey | 行为要点 |
|---|---|---|---|
| `TTyListBox` | TTyCustomControl | `TyListBox` | `Items: TStringList`(拥有/释放)、`ItemIndex`、`ItemHeight`(逻辑 px,按 PPI 缩放)、`OnChange`;鼠标点击选中、滚轮滚动;内容超高时显示内嵌 `TTyScrollBar`(子控件,靠右停靠);键盘上下键移动选中 |
| ComboBox 下拉 | (改造现有) | `TyComboBox` | `DroppedDown` 属性;Click 弹出无边框浮动窗(`TForm`,`bsNone`,`PopupParent`=宿主窗体)内嵌 `TTyListBox`;选中项→更新 Text/ItemIndex/OnChange 并关闭;失焦(Deactivate)/Esc 关闭;删除"点击循环"行为及其文档/示例说明 |
| `TTyProgressBar` | TTyGraphicControl | `TyProgressBar` | `Min/Max/Position` 纯展示;轨道画 DrawFrame,填充段按比例绘制 |
| `TTyToggleSwitch` | TTyCustomControl | `TyToggleSwitch` | `Checked`、`OnChange`;点击/空格切换;胶囊轨道 + 圆形旋钮,Checked 时旋钮滑到右侧 |
| `TTyTrackBar` | TTyCustomControl | `TyTrackBar` | `Min/Max/Position`、`OnChange`;水平;拖动/点击轨道定位;键盘左右步进 |
| `TTyGroupBox` | TTyCustomControl | `TyGroupBox` | 容器;`Caption` 嵌在上边框;子控件区按标题高度下移 |

### 2.3 子部件 typeKey(延续 TyCaptionButton 先例,不引入后代选择器)

| typeKey | 用于 | 状态语义 |
|---|---|---|
| `TyListItem` | ListBox/下拉列表的行 | `:hover`=悬停行;`:active`=选中行 |
| `TyProgressFill` | 进度条填充段 | 仅 base |
| `TyTrackThumb` | TrackBar 滑块 | `:hover`/`:active`(拖动中) |

ToggleSwitch 不引入子 typeKey:ON 状态映射 `:active`(`TyToggleSwitch:active { background: var(--accent); }`),旋钮用 `TextColor` 绘制。

### 2.4 配套交付(每控件)

- FPCUnit 测试(状态/选择/几何逻辑 headless 可测;paint 走 RenderTo 冒烟)
- 三套主题(light/dark/showcase)补全部新 typeKey 规则
- `examples/<name>/` 独立示例工程(纯代码模板)
- `docs/controls/<name>.md` 中文 API 文档
- `tycontrols.lpk` Files 列表、`tyControls.Design.pas` 注册、demo gallery 加入新控件
- 主题加载测试(INTEGRATION.10 模式)断言新 typeKey 可解析

## 3. B 部分 —— v1 打磨

### 3.1 Edit 全套编辑(本阶段最大单项)

- **模型:** `FCaret`(以 UTF-8 codepoint 计的光标索引,0..UTF8Length(Text))、`FSelAnchor`(选区锚点;=FCaret 时无选区)。所有文本操作 codepoint 安全(用 LazUTF8 的 UTF8Copy/UTF8Length/UTF8CharStart)。
- **键盘:** 左/右(±Shift 扩选)、Home/End(±Shift)、Backspace/Delete(有选区删选区,无选区删光标侧一个 codepoint)、可打印字符替换选区/在光标处插入、Ctrl+A 全选、Ctrl+C/X/V(同时认 ssMeta,macOS Cmd)。剪贴板用 LCL `Clipbrd`。
- **鼠标:** 点击按字形度量定位光标(painter/canvas TextWidth 累加 codepoint 宽);拖动扩选;双击全选(简化:双击=全选)。
- **绘制:** 选区背景 = `:focus` 态解析出的 `BorderColor` 半透(或主题新属性?**不加属性**——用 `TyEdit:focus` 的 border-color 加 alpha 绘制选区底,文档说明);光标竖线画在 FCaret 的像素 x 处,跟随文本。
- **公开 API:** `SelStart/SelLength/SelText`(LCL TEdit 习惯)、`CaretPos: Integer`(codepoint)、`SelectAll`、`CopyToClipboard/CutToClipboard/PasteFromClipboard`。
- **测试:** 插删/移动/选区/剪贴板(剪贴板测试在 headless 下若不稳则注入抽象——以实际可行为准,优先真 Clipbrd)。

### 3.2 其余打磨

- **ScrollBar thumb 颜色:** thumb 改用解析样式的 `TextColor` 填充(主题已有的 `TyScrollBar { color: … }`、`:hover { color: … }` 生效);三主题核查/补 thumb 颜色;更新 tycss-reference 中"color 在 ScrollBar 上无效"的说明。
- **CheckBox/Radio 接入 DrawFrame:** RenderTo 先 DrawFrame(全矩形)再画 glyph+caption → opacity/shadow/background 生效;三主题为其保持透明背景(视觉不变);KNOWN_GAPS 相应更新。
- **LICENSE:** 仓库根放 `COPYING.modifiedLGPL.txt`(Lazarus/LCL 同款修改版 LGPL 文本),README 加"许可"小节。

## 4. C 部分 —— native 增强(macOS 可验证项)

- **macOS 原生阴影:** `TTyFormChrome.InstallChrome` 在 `BorderStyle:=bsNone` 后,`{$IFDEF LCLCOCOA}` 取 `NSWindow` 句柄设 `hasShadow:=True`(必要时配合 `invalidateShadow`);本机运行验证。非 cocoa 平台无操作。
- **跨屏 DPI:** FormChrome 记录安装时 PPI;监听宿主窗体位置变化(挂 OnChangeBounds 链或 WM 通知,具体以可行实现为准),检测 `Monitor.PixelsPerInch` 变化后重算 TitleHeight/按钮尺寸并 Invalidate。重算函数做成纯函数单元测试;单显示器环境下行为验证有限,如实记录。
- **红绿灯风格:** `TTyCaptionButton` 新增 `ShowGlyphOnHoverOnly: Boolean`(默认 False;True 时仅 hover/active 才画 glyph);`docs/` 给出红绿灯主题配方(圆形 border-radius + 红黄绿 background 的 `.close/.min/.max` 变体 + 该属性),showcase 主题可选用。
- **Windows 项不做**,KNOWN_GAPS 保持记载并注明原因(无交叉编译验证环境)。

## 5. 验收标准

- 全部新控件 + 改造在三套主题下渲染正常;`148+` 测试全绿(新增测试覆盖每个新行为)。
- 主题加载测试覆盖全部新 typeKey;三套主题均含新规则。
- ComboBox 在 demo 中真实弹出下拉并可选择。
- Edit:中文/emoji 输入下光标、选区、剪贴板全部正确。
- macOS 无边框窗有原生投影(肉眼验证 + 代码评审)。
- `scripts/build-matrix.sh` 全绿(双包 + 全部示例 + 测试);全套件 heaptrc 0 泄漏。
- 文档同步:新控件 docs/controls/*.md、tycss-reference 新 typeKey 表、README 示例表、KNOWN_GAPS 修订。

## 6. 决策记录

| 维度 | 决策 |
|---|---|
| TabControl | 留下阶段 |
| Edit 范围 | 全套:光标+选区+剪贴板 |
| LICENSE | 修改版 LGPL(Lazarus 惯例) |
| 列表项样式 | 子部件独立 typeKey(TyListItem 等),不加后代选择器 |
| ToggleSwitch ON | 映射 `:active` 状态 |
| Windows native | 不盲写,留待有 Windows 验证环境 |
| 选区底色 | 复用 `:focus` 的 border-color 加 alpha,不新增 CSS 属性 |
