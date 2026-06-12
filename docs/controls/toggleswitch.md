# TTyToggleSwitch — API 参考

## 1. 概述

`TTyToggleSwitch` 是 TyControls 库中的主题化开关控件，继承自 `TTyCustomControl`。外观为一个胶囊形（pill）轨道加一个可滑动的圆形旋钮，左侧为 OFF、右侧为 ON。点击或按下空格键触发切换；`Checked` 属性反映当前状态，`OnChange` 在值变化时触发。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ToggleSwitch` |
| typeKey | `TyToggleSwitch` |
| 基类 | `TTyCustomControl`（继承自 `TCustomControl`） |
| 默认尺寸 | 44 × 24（逻辑像素） |

```pascal
uses tyControls.ToggleSwitch;
```

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Checked` | `Boolean` | `False` | 当前开关状态。写入时若值变化则触发重绘并调用 `OnChange`（已定义 `default False`，可参与 DFM 差量存储）。 |
| `OnChange` | `TNotifyEvent` | `nil` | `Checked` 值发生变化时触发（无论是点击、按键还是直接赋值）。 |
| `Align` | `TAlign` | — | 父容器内的停靠方式。 |
| `Anchors` | `TAnchors` | — | 锚点布局。 |
| `StyleClass` | `string` | `''` | CSS 变体类名。 |
| `Controller` | `TTyStyleController` | `nil`（全局默认） | 关联的样式控制器。 |
| `OnClick` | `TNotifyEvent` | `nil` | 点击时触发（在 `Toggle` 完成后由 `inherited Click` 触发）。 |

### 继承的通用成员

TTyToggleSwitch 继承自 `TTyCustomControl`（`tyControls.Base`）的通用状态机制。**构造时自动设置 `TabStop := True`**，支持 Tab 键导航。

---

## 4. 方法与事件

### public 方法

#### `procedure Toggle`

将 `Checked` 切换为相反值（等价于 `SetChecked(not FChecked)`）。`Click` 和空格键内部均调用此方法。

### 交互

| 操作 | 行为 |
|------|------|
| 鼠标左键点击 | 调用 `Toggle`，然后触发 `OnClick` |
| 空格键（`VK_SPACE`） | 调用 `Toggle`，消费按键（`Key := 0`） |

---

## 5. 状态与主题

### 状态

`TTyToggleSwitch` 的 `CurrentStates` 已重写：**`Checked = True` 时额外添加 `tysActive` 状态**，即 ON 状态通过 `:active` 伪类在主题中表达。

| 状态 | 触发条件 |
|------|----------|
| `:hover` | 鼠标悬停 |
| `:focus` | 获得键盘焦点 |
| `:active` | 鼠标左键按下，**或** `Checked = True`（ON 状态） |
| `:disabled` | `Enabled = False` |

> **主题写法要点：** 若要区分"按下中"和"已选中 ON"，目前两者共用 `:active`，无法在 CSS 层面区分。通常 ON 状态与按下状态使用相同的强调色视觉即可。

### 渲染细节

- **轨道：** 使用 `TyToggleSwitch` 样式规则绘制背景与边框；若主题未声明 `border-radius`，引擎自动使用控件高度的一半（胶囊形）。
- **旋钮：** 圆形，颜色固定来自当前样式的 `TextColor`（即 CSS `color` 属性）。旋钮在 OFF 时位于轨道左侧，ON 时位于右侧；边距为 3 逻辑像素（DPI 缩放）。

### light.tycss 示例规则

```css
TyToggleSwitch {
  background: var(--border);          /* OFF 时轨道颜色 */
  color: var(--surface);              /* 旋钮颜色（白色） */
  border-radius: 12px;                /* 可省略，默认取高度/2 */
}
TyToggleSwitch:active {
  background: var(--accent);          /* ON 时轨道变蓝（含"按下中"） */
}
TyToggleSwitch:hover {
  background: darken(--border, 10%);  /* 悬停时轨道略深 */
}
TyToggleSwitch:disabled { opacity: 0.5; }
```

---

## 6. 代码示例

```pascal
uses
  tyControls.Controller, tyControls.ToggleSwitch;

// 加载主题
TyDefaultController.LoadTheme('themes/light.tycss');

// 创建开关
var SW: TTyToggleSwitch;
SW := TTyToggleSwitch.Create(Self);
SW.Parent := Self;
SW.SetBounds(24, 24, 44, 24);
SW.Checked := False;
SW.OnChange := @OnSwitchChanged;

procedure TMainForm.OnSwitchChanged(Sender: TObject);
begin
  if (Sender as TTyToggleSwitch).Checked then
    ShowMessage('已开启')
  else
    ShowMessage('已关闭');
end;

// 代码直接切换
SW.Toggle;         // 等价于 SW.Checked := not SW.Checked
SW.Checked := True; // 直接设为 ON
```

完整可运行示例参见 `examples/toggleswitch/umain.pas`。

---

## 7. 注意事项

1. **ON 状态映射 `:active`：** `CurrentStates` 重写会在 `Checked = True` 时加入 `tysActive`，因此主题中 `TyToggleSwitch:active { }` 规则同时覆盖"鼠标按下"和"已选中 ON"两种情形。需要在主题中区分时，建议通过 `StyleClass` 变体实现（如 `.on`），但需在代码中手动同步 `StyleClass`。
2. **旋钮颜色来自 `color`：** 旋钮的填充色固定读取 `TextColor`（CSS `color`），不受 `background` 影响。常见配置为 `color: #FFFFFF`（白色旋钮）以在彩色轨道上提供对比。
3. **OnChange 在直接赋值时也触发：** 无论通过 `Toggle()`、点击、按键还是直接 `Checked := Value`，只要值变化，`OnChange` 就会被调用。
4. **DFM 序列化：** `Checked` 声明了 `default False`，值为 `False` 时不写入 `.lfm`；值为 `True` 时写入。
5. **默认尺寸偏小：** 默认宽 44、高 24 是最小可用尺寸；在高分屏或需要触控操作的场景下，建议放大到 56 × 28 或更大。
