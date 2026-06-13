# TTyMemo — API 参考

## 1. 概述

`TTyMemo` 是 TyControls 库中的主题化多行文本编辑控件，继承自 `TTyCustomControl`。控件以一个逻辑行一条 `TStrings` 行的方式维护文本模型，支持回车换行、退格/删除（含跨行合并）、方向键与 Home/End 导航；当逻辑行数超过可见行数时，右侧自动出现内嵌的 `TTyScrollBar` 垂直滚动条，并支持鼠标滚轮滚动。文本模型发生任何变化（插入/拆分/删除/合并）时触发 `OnChange`；纯光标移动不触发。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Memo` |
| typeKey | `TyMemo` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 200 × 120（逻辑像素） |

```pascal
uses tyControls.Memo;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Lines` | `TStrings` | 空 | 文本模型，一条 `TStrings` 行对应一条逻辑行。读取返回内部列表；写入通过 `SetLines` 进行 `Assign`，随后夹紧光标与滚动窗口并刷新滚动条。 |
| `OnChange` | `TNotifyEvent` | `nil` | 文本模型变化（插入/拆分/退格/删除/合并）后触发；纯光标移动不触发。 |
| `Enabled` | `Boolean` | `True` | 为 `False` 时键盘与滚轮输入一律被忽略（v1.5 策略：禁用时不消费按键、`DoMouseWheel` 返回 `False`）。 |
| `Font` | `TFont` | — | 字体；其 `PixelsPerInch` 参与行高/列宽度量。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器；内嵌滚动条会继承同一 Controller。 |
| `OnClick` | `TNotifyEvent` | `nil` | 鼠标点击时触发。 |

### 继承的通用成员

TTyMemo 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制。`TabStop` 在构造时置为 `True`。

---

## 4. 文本模型与光标

- 文本以逻辑行存储：`Lines[i]` 是第 i 条逻辑行的 UTF-8 字符串。空模型在视觉上仍为一条可承载光标的行（`LineCountLogical >= 1`）。
- 二维光标 `(CaretLine, CaretCol)`：`CaretLine` 在 `0 .. LineCountLogical-1`，`CaretCol` 是该行内的**码点**索引（`0 .. UTF8Length(line)`）。
- 垂直移动（↑/↓）会记忆“期望列”（desired column），跨越短行后仍尽量回到原列；行内编辑/水平移动会刷新期望列。
- 度量统一使用 `TyConfigureTextFont` 在 BGRA 位图上完成，使列宽（光标定位）与绘制结果一致（与 `TTyEdit` 的光标漂移修复同源）。

---

## 5. 键盘与交互

| 操作 | 行为 |
|------|------|
| 可打印字符 | 在 `CaretCol` 处插入码点，光标后移；触发 `OnChange` |
| `Enter`（回车） | 在光标处拆分当前行为两行，光标落到新（下）行行首；触发 `OnChange` |
| `Backspace`（退格） | 行内删除前一码点；位于行首且非首行时把当前行并入上一行末尾，光标落在接合点；位于 (0,0) 为空操作（消费按键但不触发 `OnChange`） |
| `Delete` | 行内删除后一码点；位于行尾且有后续行时把下一行上提合并；位于文档末尾为空操作（消费按键但不触发 `OnChange`） |
| `←` / `→` | 行内左右移动；越过行首/行尾时跳到上一行末尾 / 下一行行首 |
| `↑` / `↓` | 上下移动，按记忆的期望列定位（夹紧到目标行长度） |
| `Home` / `End` | 行首 / 行尾；配合 `Ctrl`（或 macOS `Cmd`/Meta）跳到文档开头 / 末尾 |
| 鼠标滚轮 | 上滚 `TopLine -= 3`、下滚 `TopLine += 3`（先调用 `inherited`，即用户的 `OnMouseWheel`，若已消费则不再滚动） |

> **注意：** 当 `Enabled = False` 时所有键盘/滚轮输入都不生效，且 `KeyDown` 不消费按键（导航可下传）。

---

## 6. 垂直滚动

- 可见行数 `VisibleRows = Height div LineHeight(Font.PixelsPerInch)`（下限 1）。
- 当 `LineCountLogical > VisibleRows` 时，惰性创建内嵌 `TTyScrollBar`（`Create(Self)`、`Parent := Self`、`Align := alRight`、`Kind := sbVertical`），其 `Min=0`、`Max=LineCountLogical-VisibleRows`、`PageSize=VisibleRows`、`Position=TopLine`；否则隐藏滚动条。
- 滚动条宽度为 `MulDiv(12, Font.PixelsPerInch, 96)`；可见时渲染会从内容区右缘减去该宽度。
- `TopLine -> 滚动条.Position` 与 `滚动条.OnChange -> SetTopLine` 之间用 `FSyncingScroll` 防重入护栏，避免来回抖动。
- 编辑或导航后 `EnsureCaretLineVisible` 会把光标行滚回 `[TopLine, TopLine+VisibleRows)` 可见窗口内，并夹紧到 `MaxTopLine`。
- 内嵌滚动条由控件自身（`Create(Self)`）拥有，随 `TComponent` 析构自动释放。

---

## 7. 状态与主题：typeKey `TyMemo`

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停在控件上 |
| `:focus` | 获得键盘焦点 |
| `:disabled` | `Enabled = False` |

每条可见逻辑行用 Memo 自身解析出的样式绘制（无逐行条目解析），文本以固定行高 top 对齐绘制；光标为 1px 竖条（与 `TTyEdit` 一致），仅在获得焦点且光标行可见时绘制。

### light.tycss 示例规则

```css
TyMemo {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 4px;
  font-size: 10px;
}
TyMemo:hover    { border-color: darken(--border, 10%); }
TyMemo:focus    { border-color: var(--accent); }
TyMemo:disabled { opacity: 0.5; }
```

> 该样式块同时存在于 `themes/light.tycss`、`themes/dark.tycss`、`themes/showcase.tycss`，并与内置兜底皮肤 `TyBuiltinThemeCss` 中的 `TyMemo` 块逐字一致——因此未加载任何主题、或在设计器中拖放时控件也有合理外观。

---

## 8. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.Memo;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建多行编辑器
var M: TTyMemo;
M := TTyMemo.Create(Self);
M.Parent := Self;
M.SetBounds(16, 16, 388, 240);
M.Lines.Text := '第一行' + LineEnding + '第二行' + LineEnding + '第三行';
M.OnChange := @OnMemoChange;

procedure TMainForm.OnMemoChange(Sender: TObject);
begin
  Label1.Caption := Format('行数：%d', [(Sender as TTyMemo).Lines.Count]);
end;
```

完整可运行示例参见 `examples/memo/umain.pas`。

---

## 9. 注意事项

1. **UTF-8 码点为单位：** `CaretCol`、行内编辑、列宽度量均以码点（而非字节）为单位，多字节字符（中文/emoji）行为正确。
2. **行高/列宽与绘制一致：** 度量经由 `TyConfigureTextFont` 在 BGRA 位图上完成，禁止用 LCL `TBitmap.Canvas` 的负字体高度去量，否则会引入光标漂移。
3. **像素测试请固定 PPI=96：** macOS 下 `Font.PixelsPerInch` 默认 72；几何/像素断言需显式钉为 96 才能与设计基准对齐。
4. **直接改 `Lines` 后窗口自动校正：** 通过 `SetLines`（即 `Lines :=` / `Lines.Assign`）写入会夹紧光标与 `TopLine` 并刷新滚动条；渲染时也会再调用一次 `UpdateScrollBar` 兜底外部直接 mutate 的情况。
5. **`OnChange` 仅模型变化触发：** 纯光标移动（方向键/Home/End、(0,0) 退格、文档末尾删除）不触发 `OnChange`。

---

## 10. v1 限制 / 缺口（Gaps）

`TTyMemo` 的 v1 版本聚焦于一个**可靠的多行编辑核心**（逐码点编辑、跨行合并、二维导航、垂直滚动）。为了把范围收敛到可在 v1.9 内可靠交付并通过完整测试套件的功能集，以下条目被**有意推迟**（deferred），当前版本**尚未**实现。下游开发者在选型/集成时应知悉这些缺口：

| 缺口 | 说明 / 当前行为 |
|------|------|
| **无文本选区（no selection）** | 控件只有单个插入光标，没有选区锚点。`Shift+方向键`、`Shift+Home/End`、鼠标拖拽**不会**产生高亮选区；不存在“选中文本”的概念，因此也无“替换选区”“删除选区”等操作。 |
| **无区间剪贴板（no clipboard of ranges）** | 不支持 `Ctrl/Cmd+C/X/V` 对**文本区间**的复制 / 剪切 / 粘贴。`KeyDown` 中没有任何剪贴板分支（`Ctrl`/`Cmd` 仅用于把 `Home`/`End` 改为跳到文档首尾）。需要导入大段文本请直接赋值 `Lines.Text`。 |
| **无自动换行（no word-wrap）** | 渲染时 `WordBreak = False`：一条逻辑行始终绘制为一行，不会按控件宽度回绕到下一行。逻辑行与可见行严格一一对应。 |
| **无水平滚动 / 长行被裁剪（no horizontal scroll, long lines clipped）** | 没有水平滚动条，也没有水平自动滚动。超出内容区宽度的长行在右缘被画布**直接裁剪**；当光标移动到可见区右侧之外时也不会水平滚动跟随（光标可能被画到内容区外而不可见）。仅垂直方向有滚动条/滚轮。 |
| **无撤销 / 重做（no undo/redo）** | 没有编辑历史栈，`Ctrl/Cmd+Z` / `Ctrl/Cmd+Y` 无效。每次编辑都是不可撤销的就地修改。 |
| **无按词导航（no word-nav）** | `Ctrl/Cmd+Left/Right` **不会**按单词边界跳转（与 `TTyEdit` 的同名缺口一致）；`Ctrl`/`Cmd` 仅作用于 `Home`/`End`（跳到文档首/末）。普通 `←`/`→` 始终按单个码点移动。 |
| **无光标闪烁（no caret blink）** | 光标是一根**静态** 1px 竖条，仅在控件获得焦点且光标行可见时绘制；没有 `TTimer` 驱动的闪烁动画，光标不会周期性隐现。 |

> 以上均为可在后续 Tier-2 增强层补齐的项；v1.9 不实现它们是经过权衡的范围决策，而非缺陷。`TTyEdit` 的“无按词导航”缺口亦记录于 [docs/KNOWN_GAPS.md](../KNOWN_GAPS.md)。
