# TTyTag

## 1. 概述

`TTyTag` 是 TyControls 库中的主题化「标签 / 胶囊」控件，继承自 `TTyGraphicControl`（图形控件，无窗口句柄，不能作为父容器）。它把一段文字放在一枚圆角填充胶囊里，可选带一个关闭（`x`）字形。典型用途：筛选条件（filter chip）、状态标记（「草稿」「已发布」）、多选框里已选项的可移除标签、列表行里的分类标记。

颜色变体**不是**枚举，而是普通的 `StyleClass`——`Tag.StyleClass := 'danger'` 对应 `.tycss` 里的 `TyTag.danger { ... }`。控件本身不认识任何变体名，主题想定义多少种就定义多少种，加变体**不需要改代码**（见第 6 节的调色板边界）。

`Closable := True` 时胶囊右侧出现 `x`：点它触发 `OnClose`，未被否决则默认**隐藏**该标签；点胶囊其余部分是普通的 `OnClick`。两个手势互不串味——点 `x` **不会**触发 `OnClick`（详见第 7 节）。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Tag` |
| `GetStyleTypeKey` 返回值 | `'TyTag'`（胶囊本体：`background` / `border-*` / `color` / `font-*` / `padding` / `opacity` / `shadow`） |
| 关闭字形 typeKey | `'TyTagClose'`（`x` 的悬停底片取其 `background`，`x` 的笔色取其 `color`） |
| 基类 | `TTyGraphicControl`（继承自 `TGraphicControl`） |
| 默认尺寸 | 72 × 22（逻辑像素，构造时设置） |

```pascal
uses tyControls.Tag;
```

**为什么是图形控件（无句柄）？** 标签是成群出现的装饰件，不取焦点、不吃按键（`x` 是纯鼠标可视对象）；直接画在父控件画布上，胶囊圆角**之外**的四角缺口天然显出父表面（图片主题下则是照片），省掉窗口化控件必须做的补角处理，也省掉每个标签一个 HWND。

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Caption` | `string` | `''` | 标签文字，用解析后的 `TyTag` 样式绘制（**不**读取 LCL `Font.*`）。在胶囊内**居中**，放不下时省略号截断（`Ta…`）。**不解析助记符**：标签不激活任何东西，`&` 就是字面字符。 |
| `Closable` | `Boolean` | `False` | 显示并启用关闭（`x`）字形。关掉时会一并清掉残留的悬停 / 按下状态。 |
| `OnClose` | `TTyTagCloseEvent` | `nil` | 见第 4 节。 |
| `AutoSize` | `Boolean` | `False` | 开启后胶囊贴合文字（文字 + 左右 `padding`，`Closable` 时再加 gap + `x` 槽位）。 |

### 继承的通用成员

`TTyTag` 继承自 `TTyGraphicControl`（`tyControls.Base`）：

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `StyleClass` | `string` | `''` | **颜色变体入口**：对应 `.tycss` 里 `TyTag.<classname>`。 |
| `StyleOverride` | `string` | `''` | 单实例内联 CSS 声明块（可引用 `var(--...)` 令牌）。 |
| `Controller` | `TTyStyleController` | `nil`（用全局 `TyDefaultController`） | 指定样式控制器。 |

另暴露 `Enabled` / `Font` / `Align` / `Anchors` / `OnClick` 及 `TTyGraphicControl` 基线事件集，见 [../events.md](../events.md)。

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnClose` | 在标签**响应 `x` 点击**之前触发。`procedure(Sender: TObject; var AllowClose: Boolean) of object`。默认 `AllowClose = True` → 控件执行默认动作 **`Visible := False`**（隐藏）；置 `AllowClose := False` 则否决默认动作，由宿主自己决定（`Free` 它、从列表里摘掉、做退场动画等）。 |
| `OnClick` | 点击胶囊**除 `x` 以外**的区域。点 `x` 的手势**不会**触发它。 |

> **为什么默认动作是「隐藏」而不是「什么都不做」：** 未挂 `OnClose` 时 `x` 仍然是活的可视对象（点了就消失），符合用户对标签的直觉；真正拥有标签生命周期的宿主用 `AllowClose := False` 接管。

---

## 5. 关键成员

### 纯几何函数（单元级，可无句柄直接调用）

```pascal
type
  TTyTagLayout = record
    CaptionRect: TRect;   // 文字绘制矩形（空 => 不画文字）
    CloseRect: TRect;     // 关闭字形槽位（空 => 无 x）
  end;

function TyTagLayout(AClientWidth, AClientHeight: Integer; AClosable: Boolean;
  APadLeft, APadRight, AGap, ACloseSize: Integer): TTyTagLayout;

function TyTagPreferredWidth(ATextWidth: Integer; AClosable: Boolean;
  APadLeft, APadRight, AGap, ACloseSize: Integer): Integer;
```

全部整数入参、无控件状态、无句柄依赖，测试直接调用（`tests/test.tag.pas`）。要点：

- 内容带 = 胶囊按 `padding` 左右内缩；`x` 槽位贴内容带**右**边缘，在**整个高度**上垂直居中（标签的上下 `padding` 通常是 0，而槽位比文字高）。
- 文字带止于 `x` 槽位前 `AGap` 处。
- **`x` 优先**：胶囊窄到放不下两者时，`x` 保留（它是标签唯一的可视对象），文字带塌缩为空。
- 槽位比胶囊高 → 压进高度内，不越界；`padding` 吃掉整个胶囊 / 宽高 ≤ 0 → 两个矩形都为空，绝不出现反向矩形。
- `TyTagPreferredWidth` 是 `TyTagLayout` 的**逆**：把它的结果当 `AClientWidth` 回喂，`CaptionRect` 正好 `ATextWidth` 宽（已有往返测试守护）。

### 公开成员

```pascal
procedure Close;               // 走 OnClose，未否决则隐藏；可对 disabled 标签调用（只有鼠标路径受 Enabled 门控）
function TyTagCloseRect: TRect; // x 槽位（设备像素，(0,0)-local）；非 Closable 时为空。绘制与命中检测同源
```

---

## 6. 状态与主题

### 支持的伪类状态

- **胶囊**（`TyTag`）：`:hover` / `:active` / `:disabled` 由基类状态机计算。
- **`x`**（`TyTagClose`）：状态取的是**字形自己的**——指针精确落在 `x` 上才是 `:hover`，所以 `x` 独立于胶囊亮起（与 TabStrip 的关闭按钮同一套路）。解析时带上**标签的 `StyleClass`**，因此 `TyTagClose.danger` 可以给危险标签的 `x` 单独换色。

### 主题令牌摘要

```css
TyTag {
  background: var(--overlay-hover);     /* 中性标签：一层淡淡的 on-surface 覆盖 */
  color: var(--on-surface);
  border-radius: var(--radius-round);   /* 过大的半径会被自动夹到半高 => 正圆端胶囊 */
  font-size: var(--font-size-base);
  padding: 0px 8px;                     /* 决定内容带；上下通常 0 */
}
/* 颜色变体 = StyleClass。下面两个直接落在现有的 5 seed 调色板上： */
TyTag.accent { background: var(--accent); color: var(--on-accent); }
TyTag.danger { background: var(--danger); color: var(--on-danger); }

TyTagClose       { color: var(--muted); }
TyTagClose:hover { background: var(--overlay-hover); color: var(--on-surface);
                   border-radius: var(--radius); }
```

> **变体调色板的边界：** 主题的 seed 只有 `--accent` / `--surface` / `--on-surface` / `--border` / `--danger`（+ `--radius`）。因此 `TyTag.accent` / `TyTag.danger` 是**现成的**；`success` / `warning` / `info` 这类语义变体需要先给调色板**新增 seed 颜色**（及其 `on(...)` 配对），那是主题层面的决定，不是本控件能自行发明的。控件对变体名一无所知——主题定义几个就有几个。

`TyTagClose` **未定义时优雅降级**：无 `background` → 不画底片；无 `color` → `x` 用胶囊自己的 `color`。**不会**回退到任何硬编码颜色。

### 可调尺寸令牌（v3/C 约定）

| 令牌 | 内置默认（逻辑像素） | 作用 |
|------|------|------|
| `--tag-close-size` | `14`（= `TyTagCloseSize`，与 `TyTabCloseSize` 一致，两处 `x` 观感统一） | `x` 方形槽位边长 |
| `--tag-gap` | `4`（= `TyTagGap`） | 文字与 `x` 槽位之间的间隙 |

`x` 字形本身还支持图标字体覆盖（`--glyph-close`，v3/C5）。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Tag;

TyDefaultController.LoadTheme('themes/light.tycss');

var T: TTyTag;

// 状态标记：只读，用变体上色
T := TTyTag.Create(Self);
T.Parent := Surface;
T.Caption := '已发布';
T.StyleClass := 'accent';       // 对应 TyTag.accent { ... }
T.AutoSize := True;
T.Left := 16; T.Top := 16;

// 可移除的筛选条件：点 x 移除，点本体切换筛选
T := TTyTag.Create(Self);
T.Parent := Surface;
T.Caption := 'region: 华东';
T.Closable := True;
T.AutoSize := True;
T.OnClose := @HandleTagClose;   // procedure(Sender: TObject; var AllowClose: Boolean)
T.OnClick := @HandleTagClick;
T.Left := 16; T.Top := 48;
```

宿主接管生命周期（不要默认的「隐藏」）：

```pascal
procedure TForm1.HandleTagClose(Sender: TObject; var AllowClose: Boolean);
begin
  AllowClose := False;                       // 否决默认的 Visible := False
  FFilters.Remove((Sender as TTyTag).Caption);
  (Sender as TTyTag).Free;                   // 自己销毁并重排
  RelayoutTags;
end;
```

---

## 8. 注意事项

- **两个手势互不串味：** 点 `x` **只**触发 `OnClose`，绝不触发 `OnClick`（否则一个筛选 chip 会「既切换又删除」）。实现依赖 LCL 的既定次序——`TControl.WMLButtonUp` **先 `Click` 后 `MouseUp`**：`Click` 看到「本次按下起始于 `x`」就吞掉；`MouseUp`（知道抬起位置）才决定是否真的关闭。
- **按下 `x` 拖开再抬起 = 取消：** 和任何按钮一致——不关闭，也不产生 `OnClick`（这次按下从来就不属于胶囊）。
- **图形控件，非容器：** 无窗口句柄，子控件不能以它为 `Parent`。
- **文字用主题样式，不读 LCL Font：** 遵循「主题锁定」约定，改字号 / 字色请改主题令牌或用 `StyleClass` / `StyleOverride`。
- **变体是 `StyleClass`，不是枚举：** 新增一种颜色只改 `.tycss`，控件代码不动。
- **胶囊形状是主题的事：** `FillBackground` 会把过大的 `border-radius`（如 `var(--radius-round)`）夹到「较短边的一半」，所以主题写 `--radius-round` 就得到正圆端胶囊，控件代码里没有任何形状常量。
- **`AutoSize` 需要已实现句柄的父窗体：** LCL 的 `AutoSizeDelayed` 在父窗体未实现句柄时会抑制所有重新贴合（headless 场景下 `AutoSize` 不生效）——这是 LCL 行为，不是本控件的。测试因此直接验 `CalculatePreferredSize`。
