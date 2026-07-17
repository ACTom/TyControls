# TTyBadge

## 1. 概述

TTyBadge 是**独立的数字 / 圆点角标**控件,继承自 `TTyGraphicControl`(无窗口句柄,绘制在宿主画布上)。它把 TTyButton 内置角标(`ShowBadge` / `BadgeValue` / `BadgePosition`)的那颗胶囊**独立成控件**,于是**任意控件**都能挂角标:把 `Target` 指向某个控件,角标就吸附到它的 `Position` 角上(内缩量与内置角标一致),并随其移动 / 缩放跟随;`Target = nil` 时就是一个普通的独立标记。`Value` 计数(> 99 显示 `99+`,与内置角标同一规则),`ShowZero` 决定 0 是否显示,`Dot` 则换成一颗纯圆点。

两套角标**共存**:TTyButton 的内置角标原样保留、未做任何改动;本控件复用它的角点枚举,并逐 token 复刻其几何,因此挂在按钮上的 TTyBadge 与按钮自画的角标**落在同一批像素上**(`TestMatchesButtonBadgeGeometry` 用像素包围盒逐边比对守护)。

**为什么是无窗口控件?** 角标天生是装饰:不取焦、不收键盘、不需要自己的画布。更关键的是,无窗口控件绘制在**父控件的画布**上——这是让它出现在一个**自带句柄的控件(TTyButton 等)之上**的唯一办法(同级的兄弟控件会被那个句柄裁掉,见 [FormSurface](../../CHANGELOG.md) 一节的同类结论)。因此 `Target` 是窗口化控件时,角标直接**认它当 Parent**,画在它的画布上,胶囊圆角外的空隙自然透出宿主自己的绘制(渐变、hover 渐变动画、图片主题的照片);换成窗口化控件则需要自己的不透明底色补丁,并且盖不住宿主的实时动画。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Badge` |
| `GetStyleTypeKey` 返回值 | `'TyBadge'`(**与 TTyButton 内置角标同一个 key**:一条主题规则同时驱动两者,不会走样)|
| 新增 token | `--badge-dot-size`(圆点直径,logical px;未设置时回退到 `TyBadgeDotSize` = 8)|

角点枚举 `TTyBadgePosition`(`bpTopLeft` / `bpTopRight` / `bpBottomLeft` / `bpBottomRight`)**别名自** `tyControls.Button` 的同名类型——不是复制:两者必须对"角"含义完全一致,别名不会漂移,也不会像同包内第二个同名枚举那样造成歧义。枚举**值**仍在 `tyControls.Button`,代码里写 `bpTopRight` 需一并 uses 该单元。

```pascal
uses tyControls.Badge, tyControls.Button;   // 后者提供 bpTopRight 等枚举值
```

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Target` | `TControl` | `nil` | 挂载目标。赋值会把角标**移动到该控件上**:窗口化目标 → 角标认它当 `Parent`,落在其 client 矩形的角上(与内置角标同一位置);无窗口目标(不能当 Parent)→ 角标成为它的**兄弟**,吸附到其 `BoundsRect` 的角。`nil` = 独立使用,由用户自行摆放。目标被释放时自动解绑。 |
| `Value` | `Integer` | `0` | 计数。> 99 显示 `99+`(TTyButton 规则);负数不夹紧(内置角标也不夹)。`0` 时默认隐藏。 |
| `ShowZero` | `Boolean` | `False` | 计数为 0 时是否仍然显示。 |
| `Dot` | `Boolean` | `False` | 画一颗纯圆点(直径取 `--badge-dot-size`)而非数字:表示"有东西"但不给数。是否显示仍由 `Value` / `ShowZero` 决定。 |
| `Position` | `TTyBadgePosition` | `bpBottomRight` | 位于目标的哪个角(内缩量与内置角标一致)。默认值**与 `TTyButton.BadgePosition` 相同**。独立使用时该属性无效(没有宿主的角可吸附)。 |

继承:`Anchors`(仅独立使用时有意义——挂载后位置由 `Target` / `Position` 决定)/ `StyleClass` / `StyleOverride` / `Controller` / `Enabled` / `Font` / `Hint` / `About` 等基类属性。

**没有 `Align` / `AutoSize`:** 角标**永远是自己量出来的自然尺寸**(主题字号 + padding,或圆点直径),尺寸由内容与主题决定,不由布局决定。

---

## 4. 事件

本控件不新增事件;暴露 `TTyGraphicControl` 基线事件集(`OnClick` / `OnMouseEnter` / …)。见 [../events.md](../events.md)。

> **注意:** 挂载后(`Target <> nil`)角标对鼠标**完全透明**(`CM_HITTEST` 回 0),点击会穿透到目标控件上——角标画在按钮上却吃掉按钮的点击是不可接受的。因此**挂载状态下 `OnClick` 不会触发**;独立使用时它是普通控件,`OnClick` 正常。

---

## 5. 状态与主题

样式全部来自 `TyBadge` 规则(内置主题已有,与 TTyButton 内置角标共用):

```css
TyBadge {
  background: var(--accent);           /* 胶囊 / 圆点填充 */
  color: var(--on-accent);             /* 数字颜色 */
  border-radius: var(--radius-round);  /* 默认胶囊;更小的圆角会被尊重 */
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-bold);
  padding: 0px 4px;                    /* 横向呼吸;高度靠字高 */
}

:root { --badge-dot-size: 8px; }       /* 圆点直径(可选,未设置则用内置 8) */
```

**渲染:** 高度 = 参考字形 `'0'` 的高 + 2×纵向 padding(下限 8 logical px,量崩了也保持可见),宽度 = 实际文本宽 + 2×横向 padding,且**不窄于自身高度**(单个数字落成近似圆形)。圆角默认取半高(胶囊),主题设了更小的 `border-radius` 则按 `TyClampRadius` 夹紧后尊重之。圆点即 1:1 宽高的同一形状 = 正圆。数字用 `ASmallCrisp` 绘制(Linux/macOS 上超采样,Windows 行为不变),文本裁剪矩形额外放宽 1px 防止 Qt6 下小号粗体被削边——以上每一条都与 `TTyButton.DrawBadge` 逐行对齐。

**主题切换会改变尺寸,不只是重画:** 角标的几何**完全**由主题推导(字号 / padding / `--badge-dot-size`),因此控件重写了 `Invalidate`——Controller 换主题时发给每个控件的那记 `Invalidate`,在这里会触发重新测量并 `SetBounds`。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Badge, tyControls.Button;

TyDefaultController.LoadTheme('themes/light.tycss');

var Bdg: TTyBadge;

// 挂到按钮右上角:未读 5 条
Bdg := TTyBadge.Create(Self);        // Owner = 窗体;不必设 Parent,Target 会安排
Bdg.Target := Button1;               // 自动成为 Button1 的子控件并吸附到角上
Bdg.Position := bpTopRight;
Bdg.Value := 5;                      // > 99 自动显示 99+

// 变成"有新消息"的小红点(不给数),0 时自动消失
Bdg.Dot := True;

// 计数归零 -> 角标自动隐藏(除非 ShowZero := True)
Bdg.Value := 0;

// 独立使用:当作普通标记自行摆放
var Tag: TTyBadge;
Tag := TTyBadge.Create(Self);
Tag.Parent := Self;
Tag.Left := 20;  Tag.Top := 20;      // 尺寸不用管,永远是自然尺寸
Tag.Value := 12;
```

---

## 7. 注意事项

- **与 TTyButton 内置角标共存:** 按钮自己的 `ShowBadge` / `BadgeValue` / `BadgePosition` 原样保留。按钮上要角标,两条路都行:内置的更省事;TTyBadge 则可以在运行期换目标、和其他控件共用一套代码。**两者别同时开**,否则同一个角上叠两颗。
- **容器类目标要当心:** 挂到窗口化目标时角标会成为它的**子控件**。若目标是会自动排布子控件的容器(ToolBar / GridPanel / RelativePanel 之类),它可能把角标当成内容参与布局。角标是给**叶子控件**(按钮 / 编辑框 / 图片 / 标签 / 页签)用的;要给容器加角标,请挂到容器里的某个具体控件上。
- **挂载后不吃鼠标:** 见 §4——挂载状态 `CM_HITTEST` 回 0,点击穿透到目标;独立使用时正常可点。
- **目标被释放:** 角标自动把 `Target` 置 nil 并撤掉跟随钩子,自身存活(LCL 不会随父控件释放子控件,只会解除 Parent),不会 AV、不会留悬垂方法指针。
- **跨 Parent 的目标:** 角标必须与目标处在同一坐标空间才可能贴上去,所以赋 `Target` 会**改变角标的 Parent**(设计期即可见)。无窗口目标若此刻还没有 Parent(代码创建顺序问题),吸附会推迟到目标获得 Parent / 下一次 bounds 变化,`.lfm` 流式加载则统一在 `Loaded` 里完成。
- **不吸附 = 不移动:** `Target = nil` 时 `Position` 无效,`Left` / `Top` 完全由用户(或 `Anchors`)决定。
- **纯逻辑可测:** 文本规则 `TyBadgeText`、显示规则 `TyBadgeVisible`、尺寸 `TyBadgeSize`、角点 `TyBadgeCornerPos` 均为纯函数并已单元测试;`TestMatchesButtonBadgeGeometry` 进一步用像素包围盒守护"与内置角标长得一样"。
- **主题驱动:** 颜色 / 圆角 / 字号 / padding / 圆点直径全部取自 `TyBadge` 与 `--badge-dot-size`,控件代码里不硬编码。唯二的例外是**角内缩 2px** 与**高度下限 8px** 两个常量(`TyBadgeInset` / `TyBadgeMinSize`):它们是 `TTyButton.DrawBadge` 里的字面量,**故意不 token 化**——只在这边 token 化会让挂载的 TTyBadge 与按钮内置角标错位。将来要 token 化,必须两处同时改。
