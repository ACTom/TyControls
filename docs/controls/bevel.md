# TTyBevel

## 1. 概述

TTyBevel 是 TyControls 的**装饰性线条 / 边框控件**(TBevel 的主题化重制),继承自 `TTyGraphicControl`(叶子图形控件,无焦点 / 子控件)。它用一条**高光线**(基色朝白色混合)配一条**阴影线**(朝黑色混合)营造 3D 凹陷 / 凸起观感;`Style` 决定这两条线的位置互换。基色来自本控件自己的 typeKey `TyBevel` 的 border / surface / text token,因此 bevel 会跟随当前主题——**不硬编码任何颜色**。

典型用途:表单分区分隔线、分组框边、纯装饰性的凹槽 / 凸脊边框,以及不可见的占位间隔(spacer)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Bevel` |
| `GetStyleTypeKey` 返回值 | `'TyBevel'`(**自有 typeKey**)|

bevel 曾经返回 `'TyPanel'`,但它压根不画面板——没有填充、没有边框、没有标题,只有高光 / 阴影两条导轨——那意味着想调一条分隔线的颜色就得把全应用的面板边框一起改。现在它有自己的键:`TyBevel` 已作为附加选择器加进主题里 `TyPanel` 的规则块,取值与从前逐字节相同,**这一步只是开出钩子,不改任何像素**。

高光 / 阴影的基色按优先级从解析后的 `TyBevel` 样式取:`border-color` → 纯色 `background` → `color`(文字色)→ 中灰兜底(有真实主题时不会走到)。

### 子部件 typeKey

**没有。** 高光线与阴影线不是各自可寻址的子部件:它们的颜色由上面那个基色在代码里混合而成(两个比例 `0.55` / `0.45` 是 Pascal 具名常量 `cBevelHighAmount` / `cBevelLowAmount`;**哪个比例走哪个方向**由所在表面的明暗决定,见《深色表面上的导轨》)。子部件键的扩展(`TyBevelHighlight` / `TyBevelShadow`)已被**刻意推迟**,这两个键当前**并不存在**,写进 `.tycss` 不会解析到任何东西。因此像"把两条导轨设成同一个颜色以得到一条扁平细线"这样的需求,今天还表达不出来。

```pascal
uses tyControls.Bevel;
```

---

## 3. 属性表

### 自有 published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Shape` | `TTyBevelShape` | `tbsBox` | 绘制形状(见下表)。 |
| `Style` | `TTyBevelStyle` | `tbsLowered` | `tbsLowered`(凹陷:阴影在上 / 左)/ `tbsRaised`(凸起:高光在上 / 左)。 |

**`TTyBevelShape` 取值:**

| 值 | 含义 |
|------|------|
| `tbsBox` | 完整矩形轮廓(四条边)。 |
| `tbsFrame` | 3D 凹槽 / 凸脊矩形(外圈 + 内圈,两圈颜色互换)。 |
| `tbsTopLine` / `tbsBottomLine` / `tbsLeftLine` / `tbsRightLine` | 单条边线。 |
| `tbsSpacer` | 不绘制任何内容(不可见占位间隔)。 |

### 继承的通用成员

| 属性 | 类型 | 说明 |
|------|------|------|
| `StyleClass` | `string` | `.tycss` 类名(作用于 `TyBevel` 解析)。 |
| `StyleOverride` | `string` | 每实例 CSS 覆盖块(可用 `var(--...)`),例如把边线基色改为强调色。 |
| `Controller` | `TTyStyleController` | 指定样式控制器(nil 时用全局默认)。 |
| `Align` / `Anchors` | — | 布局。 |

**枚举:** `TTyBevelShape = (tbsBox, tbsFrame, tbsTopLine, tbsBottomLine, tbsLeftLine, tbsRightLine, tbsSpacer)`;`TTyBevelStyle = (tbsLowered, tbsRaised)`。

---

## 4. 事件

TTyBevel 暴露 `TTyGraphicControl` 的**基线事件集**(Tier A 鼠标 / 通用事件)。作为纯装饰控件,自身不新增任何命令事件。完整清单见 [../events.md](../events.md)。

---

## 5. 状态与主题

### 支持的伪类状态

| 伪类 | 触发条件 |
|------|----------|
| `:disabled` | `Enabled = False`(`TyBevel` 若定义 `opacity` 则整体变淡)。 |

（无 hover / focus / active——纯展示控件。）

### 颜色推导

bevel 不使用 `DrawFrame` 的背景 / 边框绘制,而是自行在 `TyPainter.Bitmap` 上画 1 逻辑像素(经 `Scale` 做 HiDPI 缩放)的轴对齐线:

- **高光线** = 基色朝白色混合;**阴影线** = 基色朝黑色混合;
- **两个比例(0.55 / 0.45)按所在表面的明暗决定各自的方向**——见下面《深色表面上的导轨》;
- `tbsRaised` 时高光在上 / 左边、阴影在下 / 右边;`tbsLowered` 时互换。
- `tbsFrame` 画外圈 + 内缩 1px 的内圈,两圈颜色互换,得到凹槽 / 凸脊错觉。

因基色取自 `TyBevel` 主题规则,更换主题即更换 bevel 颜色。要**只**改 bevel 而不动别的容器,在主题里写 `TyBevel { border-color: ...; }` 即可;单个实例调色用 `StyleOverride`(例如 `'border-color: var(--accent);'`)。

### 深色表面上的导轨(3.0 修复)

两个混合比例原先是**无条件**照着"高光朝白 55% / 阴影朝黑 45%"套的,而这组数值是在**浅色**表面上调出来的:浅色主题的 `--border`(`#D1D5DB`)离白只剩 ~42 级亮度、离黑还有 ~213 级,于是**大比例落在短行程上**(+23)、小比例落在长行程上(−96)——这个搭配才让两条线读起来像一道棱,而不是两条杠。

深色主题把两段行程整个调了个个儿(`--border` `#3F3F46`:朝白 ~192、朝黑 ~63)。方向不变地套同一组比例,等于把**大比例压在长行程上**,两重放大叠加,高光落到亮度 ~169——而它所在的窗口只有亮度 30。那就是深色下"发光的白边"。这从来不是调出来的效果,只是浅色的数值在没读模式的情况下被照搬。

现在 `TyBevelRails` 先看**所在表面**(Rec.601 亮度,以 128 为界,与 `tests/test.modecoherence.pas` 同一套判定):深色表面上把两个比例**对调**,恢复"大比例配短行程"的原意。高光仍比基色亮、阴影仍比基色暗,`tbsRaised` / `tbsLowered` 的含义分毫未变。

真机实测(读控件所在 DC 的像素,`tbsRaised` 的上边导轨):

| 主题 / 模式 | 修复前高光 | 修复后高光 | 表面 |
|---|---|---|---|
| default / dark | `#A9A9AC`(亮度 169) | `#959599`(亮度 **149**) | `#1E1E1E`(30) |
| aero / dark | `#A8B0BB`(亮度 175) | `#949FAC`(亮度 **157**) | `#1E1E1E`(30) |
| default / light | `#EAECEF`(亮度 236) | `#EAECEF`(**逐字节不变**) | `#FFFFFF`(255) |
| aero / light | `#DBE4EE`(亮度 226) | `#DBE4EE`(**逐字节不变**) | `#FFFFFF`(255) |

浅色一路**不动一个像素**是硬约束:判定只在"表面是深色"时才改走另一条分支,`TestLightSurfaceRailsAreUnchanged` 直接拿 `TyBevelLighten(base, 0.55)` / `TyBevelDarken(base, 0.45)` 这两个旧调用当期望值钉住。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Bevel;

TyDefaultController.LoadTheme('themes/light.tycss');

// 一条凹陷的水平分隔线
var Sep: TTyBevel;
Sep := TTyBevel.Create(Self);
Sep.Parent := Self;
Sep.SetBounds(16, 60, 260, 2);
Sep.Shape := tbsTopLine;
Sep.Style := tbsLowered;

// 一个凹槽装饰框
var Frame: TTyBevel;
Frame := TTyBevel.Create(Self);
Frame.Parent := Self;
Frame.SetBounds(16, 80, 260, 120);
Frame.Shape := tbsFrame;
Frame.Style := tbsLowered;

// 用强调色的凸起边框
var Ridge: TTyBevel;
Ridge := TTyBevel.Create(Self);
Ridge.Parent := Self;
Ridge.SetBounds(16, 210, 260, 40);
Ridge.Shape := tbsBox;
Ridge.Style := tbsRaised;
Ridge.StyleOverride := 'border-color: var(--accent);';
```

---

## 7. 注意事项

- **无自身填充:** bevel 只画边线,内部保持透明——它是叠在其他控件 / 背景之上的装饰,不会覆盖底下的内容。
- **spacer 完全不可见:** `Shape = tbsSpacer` 时 `RenderTo` 直接返回,一个像素都不画;用作纯布局间隔。
- **纯几何可测:** `TyBevelEdges(Shape)` 返回该形状占用的边集合(`TTyBevelEdges`),`TyBevelLighten` / `TyBevelDarken` 为纯颜色混合函数,`TyBevelLuma`(Rec.601 亮度)与 `TyBevelRails(基色, 表面)`(挑导轨)同样是纯函数——全部已 headless 单元测试。
- **HiDPI:** 线宽为 1 逻辑像素,绘制时经 `Painter.Scale` 缩放;高 DPI 下线条按比例加粗。
- **主题驱动:** 高光 / 阴影颜色全部由 `TyBevel` 主题规则推导,控件不硬编码任何**颜色令牌**(库的硬性规则)。两个混合比例仍是代码里的具名常量、主题改不了——它们等子部件键那一批;把它们做成 token **不能**挂在 `TyBevel` 这个键上,因为 `tests/test.themes.pas` 的 `ALIAS_PAIRS` 把 `TyBevel` 钉成 `TyPanel` 的克隆(20 套主题 × 5 个状态逐字节相等),给它加自有属性会让这条守卫在每一套主题上变红。真要做,得走 `:root` 级的标量 token 或另立子部件键。
- **第三方主题需补选择器:** 主题层按 typeKey 全有全无地回落。只覆盖了 `TyPanel` 而没写 `TyBevel` 的旧主题,bevel 会掉回内置 light 取值(在图片主题上会读成一块不透明灰)。库内 15 套皮肤与示例主题都已补齐。
