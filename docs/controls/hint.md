# TTyHint

主题化的气泡提示（tooltip），用当前 `.tycss` 主题的 `TyHint` 样式绘制圆角表面 + 文本，
**替换原生 LCL tooltip、全应用生效**。

`TTyHint` 是非可视组件：只要在窗体上放一个（或运行期 `TTyHint.Create`），它就把内部的
`TTyHintWindow` 安装为 LCL 全局 `HintWindowClass`，此后每个控件的 `Hint` 都用主题化窗口显示。
多个实例引用计数，最后一个释放时恢复原来的类。

## 属性

| 属性 | 说明 |
|------|------|
| `Active` | 为 `True`（默认）时安装主题化提示窗口；设计期不安装。 |
| `Controller` | 仅文档用途——提示窗口由 LCL 实例化，始终用活动的默认控制器（`TyDefaultController`）解析样式。 |

## 用法

```pascal
uses tyControls.Hint;

// 放一个即可（设计期拖放，或运行期创建）：
FHint := TTyHint.Create(Self);

// 控件照常设置 Hint / ShowHint：
Button1.Hint := '保存当前文档';
Button1.ShowHint := True;
```

## 主题

`TyHint` 令牌（`background` / `color` / `border` / `border-radius` / `padding` / `font-size`）决定气泡外观，
存在于全部内置主题。

## 说明

- 提示窗口按主题圆角（`SetWindowRgn`）；Wayland 无 XShape 时退化为方角（表面色填角，视觉干净）。
- 只有纯尺寸几何 `TyHintContentRect` 可 headless 单测；实际渲染需真机验证。
- 参见 [[TTyBalloonHint]]（显式调用的带指针气泡标注）。
