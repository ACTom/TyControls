# TTyNativeStyler — API 参考

## 1. 概述

`TTyNativeStyler` 是 TyControls 库中的一个**非可视组件**（继承自 `TComponent`），用于把**原生 / 第三方 LCL 控件**（`TEdit`、`TButton`、`TTreeView` 及任意暴露 published `Color`/`Font` 的控件）与当前主题协调一致。把它拖到窗体上、令其 `Controller` 指向主题控制器；每当主题变化时，它会递归遍历 `Root` 子树下的每一个**非 Ty 控件**，借用最接近的 Ty 令牌（`TEdit`→`TyEdit`、`TMemo`→`TyMemo`……未匹配则退回 `TyPanel`）为其设置字体颜色与背景。它是 **RTTI 泛化**的（第三方控件同样受益），并对 OS 自绘类走一份小型 deny-list（保留字体、跳过背景）。典型用途：在自绘 UI 中夹带少量必须使用的原生控件时，让它们的颜色随主题（尤其是深色主题）走。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.NativeStyler` |
| 基类 | `TComponent`（非可视组件，无 typeKey / 无自身选择器） |
| 借用的 Ty typeKey | `TyEdit` / `TyMemo` / `TyComboBox` / `TyListBox` / `TyRadioButton` / `TyCheckBox` / `TyButton` / `TyGroupBox` / `TyLabel` / `TyPanel`（未匹配退回 `TyPanel`） |

`TTyNativeStyler` 本身**不参与主题绘制**，因此在 `.tycss` 中**没有对应的选择器前缀**。它是把已有的 Ty 控件令牌（如 `TyEdit`、`TyPanel`）**转借**给原生控件——见 [tycss-reference.md](../tycss-reference.md) 中对应 typeKey 的规则。

```pascal
uses tyControls.NativeStyler;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Controller` | `TTyStyleController` | `nil` | 提供主题令牌的样式控制器。写入时自动挂接其变更监听（`AddChangeListener`）——主题变化即自动重新样式化。设为 `nil` 或未设时不执行任何样式化。|
| `Root` | `TWinControl` | `nil` | 递归样式化的子树根。为 `nil` 时退回 `Owner`（若 `Owner` 是 `TWinControl`，通常即宿主窗体），见 `EffectiveRoot`。|
| `Enabled` | `Boolean` | `True` | 为 `False` 时 `Apply` 直接返回，不做任何样式化。|
| `ApplyFontName` | `Boolean` | `False` | 为 `True` 且主题令牌含 `font-name` 时，把控件字体族改为主题字体族；默认 `False`（只改字体**颜色**，不动字体族）。|
| `ApplyFontSize` | `Boolean` | `False` | 为 `True` 且主题令牌含 `font-size`（`> 0`）时，把控件字号改为主题字号；默认 `False`。|

> `Enabled` / `ApplyFontName` / `ApplyFontSize` 均声明了 `default`，值等于默认值时不写入 `.lfm`/`.dfm`。`Controller` 与 `Root` 为对象引用，无 `default`，未设时按空值处理。

### 继承的通用成员

`TTyNativeStyler` 直接继承自 `TComponent`，**不**具备 `StyleClass`（它自身不被主题绘制）。可用的仅是 `TComponent` 的标准成员（`Name`、`Tag`、`Owner` 等）。`Controller` 属性即上表所列，是本组件与主题系统的唯一挂钩。

---

## 4. 事件

| 事件 | 类型 | 触发时机 |
|------|------|----------|
| `OnStyleControl` | `TTyStyleControlEvent` | 在对**每一个**候选控件应用样式**之前**触发；签名 `(Sender: TObject; AControl: TControl; var AHandled: Boolean)`。把 `AHandled := True` 可**跳过**该控件（opt-out），或在自行施加自定义样式后设 `True` 以**覆盖**默认逻辑。|

`TTyStyleControlEvent` 定义：

```pascal
TTyStyleControlEvent = procedure(Sender: TObject; AControl: TControl;
  var AHandled: Boolean) of object;
```

> `TTyNativeStyler` 是非可视 `TComponent`，**不**暴露 [../events.md](../events.md) 中面向控件的基线事件集（Tier A / Tier B 鼠标·键盘·焦点事件）——它没有可见表面、不接收输入。`OnStyleControl` 是它唯一的事件，用于逐控件的 opt-out / 覆盖。

---

## 5. 状态与主题

`TTyNativeStyler` 没有伪类状态（无 `:hover` / `:focus` / `:active` / `:disabled`）——它不是被绘制的控件，而是一台**令牌转借引擎**。它的行为是把原生控件映射到最接近的 Ty typeKey，再用该 typeKey 的**基础态**（`ResolveStyle(key, '', [])`，无伪类）令牌为其设置字体色与背景。

### typeKey 映射规则（`NativeTypeKey`）

按以下顺序（先特化后泛化）判定控件类别，取第一条匹配：

| 原生类（`is` 判断） | 借用的 typeKey |
|----------------------|----------------|
| `TCustomMemo` | `TyMemo` |
| `TCustomComboBox` | `TyComboBox` |
| `TCustomListBox` | `TyListBox` |
| `TCustomEdit` | `TyEdit` |
| `TRadioButton` | `TyRadioButton` |
| `TCustomCheckBox` | `TyCheckBox` |
| `TCustomButton` | `TyButton`（仅字体；背景被 deny）|
| `TCustomGroupBox` | `TyGroupBox` |
| `TCustomLabel` / `TCustomStaticText` | `TyLabel` |
| `TCustomPanel` | `TyPanel` |
| **其它一切未匹配** | `TyPanel`（每个主题都存在的中性表面）|

### 借用令牌摘要（light.tycss）

未匹配控件退回 `TyPanel`，其令牌为：

```css
TyPanel {
  background: var(--surface);           /* #FFFFFF */
  color: var(--on-surface);             /* #1F2937 */
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 8px;
}
TyLabel {
  background: alpha(#FFFFFF, 0);        /* 透明 */
  color: var(--on-surface);             /* 兜底字体色来源 */
}
```

### 应用细节

- **字体颜色（低风险，总是应用）：** 若控件有 published `Font`，取映射令牌的 `text-color` 设为字体色。若映射令牌**没有**显式文字色（例如退回 `TyPanel` 只设了背景），则**兜底**用 `TyLabel` 的 `text-color`（`--on-surface`），保证原生文字在深色主题下依然可读，而不是保留设计期黑色。
- **字体族 / 字号（opt-in）：** 仅当 `ApplyFontName` / `ApplyFontSize` 为 `True` 且令牌含对应值时才改写；两者默认 `False`。改字体后把控件的 `ParentFont` 置 `False`（若存在）以免被父控件覆盖回去。
- **背景（高风险，条件应用）：** 仅当控件有 published `Color`、令牌背景为**纯色**（`tfkSolid`）、且该类**不在 deny-list** 时，才设置 `Color`（并把 `ParentColor` 置 `False`）。OS 自绘类（见下）跳过背景。
- **`TTreeView` 特例：** 对 `TCustomTreeView` 移除 `Options` 中的 `tvoThemedDraw`——否则 LCL 用 OS 主题色绘制节点文字、无视 `Font.Color`，深色主题下文字仍为 OS 黑。移除后 +/- 按钮变经典外观，但节点文字由 `Font.Color` 驱动（主题正确）。
- **deny-list（背景禁写）：** `initialization` 中注册 `TCustomButton`（`TButton`/`TBitBtn` 等）、`TSpeedButton`、`TCustomCheckBox`（含 `TRadioButton`）——这些类由 OS 绘制背景，设背景无效或难看，故只应用字体、跳过背景。可用类方法 `RegisterDeny(AClass)` 追加（影响全部 styler 实例），`IsDenied(AControl)` 查询。
- **自我主题控件被跳过：** 遍历中遇到 `TTyGraphicControl` / `TTyCustomControl` 子类（即 Ty 自绘控件）直接跳过——它们自己会主题化。

---

## 6. 代码示例

### 设计期用法（demo 的做法）

demo 在窗体上拖了一个 `TyNativeStyler1`，仅设了 `Controller`（`Root` 留空 → 退回 `Owner` 窗体）：

```
object TyNativeStyler1: TTyNativeStyler
  Controller = TyController
end
```

主题一切换，窗体下所有原生控件即随之重新着色，无需代码。

### 运行期用法

```pascal
uses
  tyControls.Controller, tyControls.NativeStyler;

var
  Styler: TTyNativeStyler;
begin
  Styler := TTyNativeStyler.Create(Self);
  Styler.Controller := TyDefaultController;   // 挂接主题；自动首刷
  Styler.Root := Self;                        // 样式化本窗体子树（可省略，退回 Owner）
  // Styler.ApplyFontName := True;             // 可选：连字体族也随主题
  // Styler.ApplyFontSize := True;
  Styler.OnStyleControl := @HandleStyleControl;
end;

// 逐控件 opt-out / 覆盖
procedure TForm1.HandleStyleControl(Sender: TObject; AControl: TControl;
  var AHandled: Boolean);
begin
  if AControl is TMyBrandLabel then
    AHandled := True;   // 跳过此控件，保留其自定义外观
end;
```

### 为运行期新建的控件手动着色

```pascal
// Apply 不会自动追踪运行期后来新建的控件；对新控件单独调用即可
var Edt: TEdit;
Edt := TEdit.Create(Self);
Edt.Parent := Self;
Styler.StyleControl(Edt);   // 按规则解析令牌、设字体/背景

// 或整棵子树重刷（幂等）
Styler.Apply;
```

---

## 7. 注意事项

- **绝不在设计期运行：** `Apply` 首行即检查 `csDesigning`——设计期直接返回，避免把主题颜色**烘焙进 `.lfm`**。所以 IDE 设计器里看不到样式效果，属正常；效果只在运行期出现。
- **`Root` 退回 `Owner`：** 未设 `Root` 时以 `Owner`（若为 `TWinControl`）作为遍历根，通常即宿主窗体。若 `Owner` 不是 `TWinControl` 且未设 `Root`，则 `EffectiveRoot` 为 `nil`，`Apply` 静默无操作。
- **自动重刷绑定主题变更：** 设 `Controller` 时挂接其 `ChangeListener`，主题变化自动触发 `Apply`；组件销毁时在 `Destroy` 中 `RemoveChangeListener` 解绑。`Loaded` 与 `SetController`（非 `csLoading`）也各触发一次 `Apply`。
- **不追踪运行期新建控件：** `Apply` 是一次性快照式遍历，**不**监听控件树增删。运行期后来创建的控件需自行调用 `StyleControl(c)` 或再次 `Apply`。
- **RTTI 泛化、第三方友好：** 判定基于 `is TCustom*` 与 published `Color`/`Font` 的存在性（`IsPublishedProp`），因此任何暴露 `Color`/`Font` 的第三方控件都会被着色；无 `Color` 的只改字体，无 `Font` 的两者都不改。
- **背景只吃纯色令牌：** 仅 `tfkSolid` 背景才写入 `Color`；渐变 / 图片 / 玻璃等非纯色背景**不**转借给原生控件（原生 `Color` 只能是纯色）。
- **deny-list 是类级共享：** `RegisterDeny` 为**类方法**，追加的 deny 类影响进程内**所有** `TTyNativeStyler` 实例；内置已 deny `TCustomButton`、`TSpeedButton`、`TCustomCheckBox`。
- **Ty 控件自动豁免：** 遍历跳过所有 `TTyGraphicControl` / `TTyCustomControl` 子类；不必担心 styler 会去干扰同窗体上的原生 Ty 控件。
- **`OnStyleControl` 在应用前触发：** 事件在解析/设置样式**之前**回调，`AHandled := True` 既可用于纯跳过，也可用于"我自己上完色了、别再动"。
