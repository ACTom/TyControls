# TTyBalloonHint

带指针的主题化气泡标注：**标题 + 正文 + 可选图标**，从目标控件引出一个指针，全部由
`TTyPainter` 按 `TyHint` 样式绘制。与 [TTyHint](hint.md)（替换被动 tooltip）不同，气泡由
`ShowFor` / `ShowAt` 显式弹出，`HideInterval` 毫秒后自动隐藏。

## 属性

| 属性 | 说明 |
|------|------|
| `Title` | 标题（粗体行）。 |
| `Description` | 正文（支持换行）。 |
| `Icon` | `biNone` / `biInfo` / `biWarning` / `biError`——左侧图标圆点（颜色取自主题 accent / danger 令牌）。 |
| `HideInterval` | 自动隐藏延时（毫秒，`0` = 一直显示到 `HideHint`）。默认 `4000`。 |
| `Controller` | 可选样式控制器，缺省用 `TyDefaultController`。气泡的尺寸和外观都按它的主题来。 |

## 方法

| 方法 | 说明 |
|------|------|
| `ShowFor(AControl)` | 指向某控件弹出（用其屏幕矩形）。 |
| `ShowAt(ATargetScreen)` | 指向任意屏幕矩形弹出。 |
| `HideHint` | 立即隐藏（自动隐藏计时器也调用它）。 |

## 用法

```pascal
uses tyControls.BalloonHint;

FBalloon := TTyBalloonHint.Create(Self);
FBalloon.Title := '已保存';
FBalloon.Description := '文档已写入磁盘。';
FBalloon.Icon := biInfo;
FBalloon.ShowFor(SaveButton);
```

## 说明

- 窗口用组合区域整形（圆角主体 ∪ 指针三角）；Wayland 无 XShape 时退化为纯圆角主体。
- 优先在目标下方弹出，下方空间不足且上方够时翻转到上方（纯几何 `TyBalloonPlacement`，可 headless 单测）。
- 主体和指针是同一条轮廓：带边框的主题下，指针两条斜边带边框，底边没有线。
- 指针底边只落在两个圆角之间的直线段上：离主体两端各留半个底宽，再加圆角半径和边框宽度。气泡被挤到屏幕边上时，指针会往里让，不会压进圆角；主体窄到放不下这段余量时，只留半个底宽。
- 实际渲染需真机验证。
- 参见 [[TTyHint]]。
