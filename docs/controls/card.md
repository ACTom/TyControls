# TTyCard — API 参考

## 1. 概述

`TTyCard` 是**卡片容器**,继承自 `TTyCustomControl`(窗口化,拥有自己的句柄)。一张卡片是**一整块主题化表面**,由发丝分隔线切分成三条横带:

- **标题条(header)** —— 顶部,绘制 `Title`;由 `ShowHeader` 控制。
- **主体(body)** —— 中间,**承载用户的子控件**(`csAcceptsControls`,IDE 设计器可直接往里拖控件)。
- **操作条(actions)** —— 底部,由 `ShowActions` 控制。

对标 Ant Design Card,但做成**原生容器**而非 Web 组件。定位上填补的缺口:`TTyGroupBox` 是「带边框标题的分组」(标题打断边框线),`TTyPanel` 是裸容器——**都不是卡片**。卡片是一块整体表面,标题条与操作条只是画在它上面的带,不是独立子控件。

典型用途:仪表板磁贴、设置分区、列表项详情、带操作区的信息块。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Card` |
| 基类 | `TTyCustomControl`(→ `TCustomControl`)。**容器必须窗口化**:子控件只能挂在 `TWinControl` 上,图形控件没有句柄可挂 |
| `GetStyleTypeKey` 返回值 | `'TyCard'`(表面:背景 / 边框 / 圆角 / 阴影 / padding) |
| 标题条 typeKey | `'TyCardHeader'`(`background` = 可选带底色,`border-*` = 分隔线,`color`/`font-*` = 标题文字) |
| 操作条 typeKey | `'TyCardActions'`(`background` = 可选带底色,`border-*` = 分隔线) |
| 默认尺寸 | 240 × 160(逻辑像素) |

```pascal
uses tyControls.Card;
```

三个 typeKey 都参与卡片的状态集:`TyCard:hover { … }` 即可实现 AntD 的 `hoverable`(基类已跟踪 hover,无需属性);`:disabled { opacity: … }` 同时作用于三条带。

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Title` | `string` | `''` | 标题条文字。**按字面绘制**(不解析 `&` 助记符——卡片只是给表面命名,不激活任何东西),放不下时省略号截断。 |
| `TitleAlignment` | `TAlignment` | `taLeftJustify` | 标题在标题条内的水平对齐。 |
| `ShowHeader` | `Boolean` | `True` | 是否绘制标题条**并**从子控件区中扣除它。**标志是权威,不是 `Title` 文字**:`Title` 为空时标题条依然占位,所以清空标题不会让主体跳动。 |
| `ShowActions` | `Boolean` | `False` | 是否绘制底部操作条**并**从子控件区中扣除它。 |
| `Align` / `Anchors` / `StyleClass` / `Controller` | — | — | 继承自基类的通用容器成员。 |

### public 方法

| 方法 | 返回 | 说明 |
|------|------|------|
| `HeaderRect` | `TRect` | 已绘制的标题条矩形(**客户区坐标**);`ShowHeader = False` 时为空矩形。 |
| `ActionsRect` | `TRect` | 已绘制的操作条矩形(客户区坐标);`ShowActions = False` 时为空矩形。 |
| `ContentRect` | `TRect` | **子控件区**(客户区坐标):主体带再按主题 `padding` 内缩。见 §7 的坑。 |

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `TyCardHeaderHeight` | `36` | 标题条逻辑高度**兜底值**(主题未定义 `--card-header-height` 时用)。 |
| `TyCardActionsHeight` | `44` | 操作条逻辑高度兜底值(足够居中放一个默认 30px 高的 `TTyButton`)。 |

---

## 4. 纯几何函数(可独立单元测试)

```pascal
{ 卡片的三条横带(设备像素),与传入的客户区**同一坐标空间**。 }
TTyCardLayout = record
  Header: TRect;    // 标题条(隐藏 / 无空间时为空)
  Body: TRect;      // 承载子控件的中间带(永不为负)
  Actions: TRect;   // 操作条(隐藏 / 无空间时为空)
end;

function TyCardLayout(const AClient: TRect; AHeaderH, AActionsH: Integer): TTyCardLayout;
```

无控件状态、无句柄,测试直接调用。契约:

- **三带精确铺满客户区**:`Header.Bottom = Body.Top` 且 `Body.Bottom = Actions.Top`——不留未绘制的缝,也不互相重叠。
- 传 `0` 表示「该带隐藏」,带塌陷为空矩形。
- **空间不足时标题条优先**(标题比操作条重要):标题条先钳制到客户区高度,操作条只拿剩下的,主体吸收余量、可塌陷为 0,但**永不反转**。
- 客户区退化(高度为 0)或**上下反转**(`Bottom < Top`)时不崩溃、不产生负高度带。

---

## 5. 状态与主题

**渲染顺序:** `DrawFrame` 先以 `TyCard` 画**整张卡片**的表面(背景 + 边框 + 圆角 + 阴影),标题条与操作条再作为带画在它上面。

**带的绘制:** 每条带按其 typeKey 解析样式——

- `background` **有设置才**填充(AntD 风格的标题条本就是透明的,只有 `classic` / `win98` 这类皮肤才需要带底色)。带的填充会**按卡片边框宽度内缩**(卡片边框是画在矩形内侧的,不内缩会盖住边框),且**外侧圆角跟随卡片**(标题条圆上面两角、操作条圆下面两角,朝主体的一边保持直角)——否则方形填充会溢出到卡片的圆角弧里。
- **分隔线**取该带的 `border-color` / `border-width`(`border-width: 0` 或未设 `border-color` 即无分隔线),以直角填充带绘制:它只是一条边,直角才能在任何圆角下都保持锐利。
- **标题文字**取 `TyCardHeader` 的 `color` / `font-*`;水平留白取 `TyCardHeader` 自己的 `padding`,**未设时回落到卡片的 `padding`**——所以默认状态下标题与主体内容左对齐。

**带高:** 取自主题 metric `--card-header-height` / `--card-actions-height`(未定义时用上面的兜底常量),随 DPI 缩放。**刻意不做成 published 属性**:卡片的比例本身就是皮肤的一部分(同 `TTyGroupBox` 的 `--groupbox-caption-height`);单张卡片要破例用 `StyleOverride`。

所有可见值均主题驱动,控件代码中无任何硬编码颜色 / 尺寸 / 圆角。

---

## 6. 代码示例

```pascal
uses tyControls.Controller, tyControls.Card, tyControls.Button, tyControls.Memo;

TyDefaultController.LoadTheme('themes/light.tycss');

var Card: TTyCard; Btn: TTyButton; Memo: TTyMemo;
Card := TTyCard.Create(Self);
Card.Parent := Self;
Card.SetBounds(20, 20, 260, 180);
Card.Title := '本月用量';
Card.ShowActions := True;

// 对齐的子控件自动落在主体带里(AdjustClientRect 已把标题条 / 操作条扣掉)
Memo := TTyMemo.Create(Self);
Memo.Parent := Card;
Memo.Align := alClient;      // 落在标题条与操作条之间

// 手工摆放的子控件(alNone)必须自己对着 ContentRect 定位 —— 见 §7
Btn := TTyButton.Create(Self);
Btn.Parent := Card;
Btn.SetBounds(Card.ContentRect.Left, Card.ContentRect.Top, 88, 30);
```

---

## 7. 注意事项

- **⚠ 手工摆放的子控件不会自动避开标题条。** LCL 的 `GetClientRect` 返回的是**原始** `(0,0,W,H)` 矩形,`AdjustClientRect` **只作用于对齐的子控件**(`alClient` / `alTop` / …)与锚定。`Align = alNone` + `SetBounds` 的子控件坐标是**原始客户区坐标**,`Top = 0` 会**压在标题条底下**。请对着 public 的 `ContentRect` 定位——它就是 `AdjustClientRect` 自己的输出(实现上直接委托给它),所以两条路径**在构造上不可能漂移**。
- **卡片 vs 分组框 vs 面板:** 需要「一块有标题的表面」用本控件;需要「一圈边框把相关控件框起来、标题打断边框线」用 [TTyGroupBox](groupbox.md);只要一个裸容器用 [TTyPanel](panel.md)。
- **`padding.Top` 的语义与 GroupBox 不同:** `TTyGroupBox` 刻意不在标题带下再加 `padding.Top`(会双倍留白);卡片的 `padding.Top` **作用在标题条分隔线之下**——分隔线是分隔物,不是内容的留白。
- **操作条是绘制的装饰带,不是第二个容器:** 子控件区(`AdjustClientRect`)**只有主体带**。要往操作条里放按钮,请手工摆放并对着 `ActionsRect` 定位。
- **`hoverable` / `bordered` 无需属性:** 前者写 `TyCard:hover { … }` 规则,后者写 `border-width: 0`(或用 `StyleClass`)。
- **`ShowHeader` / `ShowActions` 变化会 `Realign`:** 主体带的尺寸随之变化,已对齐的子控件会重新布局。
</content>
