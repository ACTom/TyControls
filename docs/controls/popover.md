# TTyPopover

## 1. 概述

`TTyPopover` 是**能承载真实控件的主题化浮层**,继承自 `TComponent`——它是**非可视组件**(`TTyBalloonHint` / `TTyNotification` 的路子),不是控件。

它填的是**功能缺口,不是观感缺口**:`TTyHint` 与 `TTyBalloonHint` 只能显示**文本**,库里此前**完全没有**办法在某个控件旁边弹出一小块带按钮的面板——「确定要删除吗?[是] [否]」这类 flyout、挂在工具条按钮上的小型颜色 / 格式编辑器、筛选框。Popconfirm 就是这个模式,并且建立在本组件之上。

用法是:往窗体上丢一个 `TTyPopover`,把 `Content` 指向你在设计器里填好的容器,把 `Target` 指向它所属的控件,然后调 `Show`。它**不能**做成就地控件——因为它必须浮在**所有东西之上**(包括窗口化子控件,后者会裁掉一切画在窗体自身画布上的内容),所以和 `TTyPopupSurface` / `TTyBalloonHint` 完全一样,它**自己拥有一个窗口**:一个无边框、`fsStayOnTop` 的裸窗体,用 `TTyPainter` 画出主体 + 箭头。

**为什么 `Content` 是「应用自己已经拥有的控件」,而不是由本组件创建的容器?** 整件事的意义就是让应用把**真实控件**放进去,而开发者唯一能搭出这些控件的地方是设计器、在窗体上。所以弹窗在 `Show` 时把一个既有容器**收养(adopt)**进自己的窗口,在 `Hide` 时把它**原样交还**给原来的父控件——用的是 `TTyPopupSurface` 那套久经考验的 `AdoptContent` / `ReleaseContent`,Ribbon 早就靠它把活的控件树搬进 flyout。

凡是**规则**的部分——弹窗落在哪、往哪边翻、框里装什么——都是接受纯整数的自由函数,所以整套几何**无窗口、无屏幕**即可验证。只有「把窗口真正立起来」需要真机;**观感必须在真机上核对**(尤其 `RenderTo` 里注明的箭头 / 边框装饰问题,见 §8)。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Popover` |
| 基类 | `TComponent`(**非可视组件**;设计期面板页 `TyControls Images`,与 `TTyHint` / `TTyBalloonHint` 同页) |
| 主体 typeKey | `'TyPopover'`(类函数 `TTyPopover.StyleTypeKey`)——`background` / `border-*` / `color` / `font-*` / `padding` / `opacity` |
| 标题 typeKey | `'TyPopoverTitle'`(类函数 `TTyPopover.TitleStyleTypeKey`)——`background`(可选头带) / `color` / `font-*` |
| 默认尺寸 | **无**。非可视组件没有尺寸;弹窗窗口的大小是**测出来的**(`Content` 的设计期尺寸 + 主题 `padding` + 标题行 + 箭头条),见 `MeasureFrameAtPPI` |
| 新增 metric 令牌 | `--popover-arrow-size` / `--popover-offset` / `--popover-title-gap`(见 §6) |

```pascal
uses tyControls.Popover;
```

**为什么 typeKey 是「类函数」而不是 `GetStyleTypeKey`?** 本组件**不是** `ITyStyleable`:控制器的 styleable 注册表装的是 `TControl`,而非可视组件不是控件。所以两个 typeKey 做成朴素的类函数,供测试与主题文档使用。

---

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Target` | `TControl` | `nil` | 弹窗所属、并指向的控件。`Show` 用它;`ShowFor` / `ShowAt` 可以**单次**越过它而**不打扰**它。设了 `FreeNotification`——`Target` 被销毁时置 `nil`。 |
| `Content` | `TWinControl` | `nil` | 弹窗展示的**容器**。在设计器里填好它(典型是一个塞了按钮的 `TTyPanel`,在窗体上留 `Visible=False`),然后把本属性指过来:`Show` 时它被**重新挂进**弹窗窗口、摆在框的 content rect 上,`Hide` 时**原样**回到自己的窗体。**弹窗按它的设计期尺寸测量**,所以要调大小请调容器,不是调 popover。 |
| `Placement` | `TTyPopoverPlacement` | `ppBottom` | 弹窗**偏好**落在 `Target` 的哪一侧、以及沿该侧如何对齐。**只是偏好**:那一侧放不下就翻到对面(见 §5)。 |
| `Title` | `string` | `''` | 内容上方可选的标题行,用解析后的 `TyPopoverTitle` 样式绘制。空 = 无标题,内容占满主体。**单行 + 省略号截断**;**不解析助记符**——标题不激活任何东西,`&` 就是字面字符。 |
| `ShowArrow` | `Boolean` | `True` | 画出指向 `Target` 的箭头。关掉 = 一张普通浮动卡片,**照样**按同一套规则定位与翻转,只是没有箭头条(**也不占那条厚度**)。 |
| `CloseOnClickOutside` | `Boolean` | `True` | 点击别处(即弹窗窗口失活)时关闭。默认开——flyout 本该如此。**关掉它**用于「内容必须被回答」的弹窗:此时它只能靠 `Hide` 或 Escape 消失。 |
| `CloseOnEscape` | `Boolean` | `True` | 按 Escape 关闭。**刻意与 `CloseOnClickOutside` 分开**:这样「必须回答」的弹窗仍然保留每个用户都期待的键盘退路,而不会有误触退路。 |
| `StyleClass` | `string` | `''` | 变体入口:主题里的 `TyPopover.danger` 规则。**两个 typeKey 都用它解析**,所以 `TyPopoverTitle.danger` 能单独给危险弹窗的标题上色。 |
| `Controller` | `TTyStyleController` | `nil`(用全局 `TyDefaultController`) | 指定样式控制器。被销毁时置 `nil` 并**回落到全局默认**,而不是悬垂。 |

> **属性变更不会移动已经弹出的窗口。** `Placement` 改了只记下来(「活着的弹窗不跳:布局是在它弹起来时读的——在用户指针底下挪走它,正是用户够不到那个按钮的原因」)。`Title` / `ShowArrow` / `StyleClass` / `Controller` 改了只 `Invalidate` **重绘**:`Title` 的 `''` ↔ 有文字其实是**尺寸变化**(整条标题带),要重新测量、重新定位、重新给内容定界——新尺寸落在**下一次 `Show`**,那才是 popover 决定几何的时机。

### public 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `Showing` | `Boolean`(只读) | 弹窗当前是否立着。 |

---

## 4. 事件

| 事件 | 触发时机 |
|------|----------|
| `OnShow` | `TNotifyEvent`。在弹窗**已经上屏之后**触发(且在内容**已被收养进去之后**,所以处理函数里可以给内部某个控件设焦点)。 |
| `OnHide` | `TNotifyEvent`。**每次消失触发一次**,不论起因:点击别处、Escape、还是 `Hide`。**组件被销毁时不触发**——组件消失不等于用户关掉了弹窗(且此时处理函数所在的窗体可能已经拆了一半)。 |

---

## 5. 关键成员

### 纯规则 / 几何(单元级自由函数,无组件、无窗口、无主题即可调用)

```pascal
type
  TTyPopoverSide  = (psvTop, psvBottom, psvLeft, psvRight);   // 主体在锚点的哪一侧
  TTyPopoverAlign = (palStart, palCenter, palEnd);            // 沿共享边如何对齐
  TTyPopoverPlacement = (
    ppTop, ppTopLeft, ppTopRight,
    ppBottom, ppBottomLeft, ppBottomRight,
    ppLeft, ppLeftTop, ppLeftBottom,
    ppRight, ppRightTop, ppRightBottom);

  TTyPopoverGeometry = record
    Frame: TRect;        // 整个弹窗窗口:主体 + 锚点侧的箭头条
    Side: TTyPopoverSide;// 实际落在的侧(翻转之后)。别假定它就是你请求的那个
    Flipped: Boolean;    // 请求的那侧放不下、对面放得下 => True
    TipX, TipY: Integer; // 箭头顶点,在 Frame 的近边上,瞄准锚点中心
  end;

  TTyPopoverLayout = record   // 框的内部,设备像素,相对 Frame 左上角
    BodyRect: TRect;     // 圆角主体(= 框减去箭头条)。空 => 根本没有弹窗可画
    ArrowRect: TRect;    // 三角形的包围盒(空 => 无箭头)
    ArrowTip: TPoint;    // 三角形顶点,在框的近边上
    TitleRect: TRect;    // 标题行带(空 => 无标题,或放不下)
    ContentRect: TRect;  // 被承载控件的位置(空 => 放不下)
  end;

function TyPopoverSide(APlacement: TTyPopoverPlacement): TTyPopoverSide;
function TyPopoverAlign(APlacement: TTyPopoverPlacement): TTyPopoverAlign;
function TyPopoverPlacementOf(ASide: TTyPopoverSide; AAlign: TTyPopoverAlign): TTyPopoverPlacement;
function TyPopoverOppositeSide(ASide: TTyPopoverSide): TTyPopoverSide;
function TyPopoverSideIsVertical(ASide: TTyPopoverSide): Boolean;

function TyPopoverPlace(const AAnchor: TRect; AFrameW, AFrameH: Integer;
  const AWorkArea: TRect; APlacement: TTyPopoverPlacement;
  AOffset, AArrowSize: Integer): TTyPopoverGeometry;
function TyPopoverTipLocal(const AGeometry: TTyPopoverGeometry): Integer;
function TyPopoverLayout(AFrameW, AFrameH: Integer; ASide: TTyPopoverSide; ATipLocal: Integer;
  AShowArrow, AHasTitle: Boolean;
  APadL, APadT, APadR, APadB, ATitleH, ATitleGap, AArrowSize: Integer): TTyPopoverLayout;
function TyPopoverFrameSize(AContentW, AContentH: Integer; ASide: TTyPopoverSide;
  AShowArrow, AHasTitle: Boolean;
  APadL, APadT, APadR, APadB, ATitleH, ATitleGap, AArrowSize: Integer): TSize;
function TyPopoverArrowPoints(const ALayout: TTyPopoverLayout; ASide: TTyPopoverSide;
  out ATip, ABase1, ABase2: TPoint): Boolean;
```

全部纯整数 / 枚举入参,无控件状态、无句柄、无屏幕,测试直接调用(`tests/test.popover.pas`)。

**`TTyPopoverPlacement` 为什么是一个扁平的十二值枚举,而不是「侧 + 对齐」两个属性?** 因为这是设计器里用户**唯一**要设的那一件事,一个十二项的下拉框比两个能组合出同样十二种的下拉框读起来好。`TyPopoverSide` / `TyPopoverAlign` 再把它拆回去给规则用。

#### `TyPopoverPlace` 的契约

- **主轴(侧):** 框在锚点与工作区边缘之间**放得下**,就用请求的那侧;放不下、而**对面放得下**时,弹窗**翻转**——这就是这条轴上的**全部**溢出策略,也是 popover 永不遮住它所属之物的原因。**两侧都放不下时保留请求的那侧**:已经没有正确答案了,那就让调用者自己的请求赢,而不是给出第二个错误答案。
- 主轴上**刻意不做钳制**:一个沿主轴滑走的弹窗就不再读作「属于那个锚点」了,而且它的箭头会指向虚空。翻转帮不上忙时,框保持贴着锚点、任其溢出工作区。
- **交叉轴(对齐):** 先按请求对齐,再**钳进工作区**——这条轴上滑动恰恰是对的,因为弹窗无论如何都还在锚点旁边。**先钳右边、再钳左边**:比工作区还宽的框会贴**左**(阅读侧)边缘,不是右边——这是 `TTyBalloonHint` 的钳制顺序,理由相同。
- **翻转只改侧,不改对齐:** 放不下的 `ppBottomLeft` 变成 `ppTopLeft`,**绝不是** `ppTop`;对齐是用户的意思,必须活过翻转(`TyPopoverPlacementOf` 就是为此存在的)。
- **顶点**瞄准锚点中心,然后钳进框内(离框角至少一个 `AArrowSize`),这样被迫滑动过的弹窗仍有一个**形状良好**的箭头——只是不再指着正中间。

#### `TyPopoverLayout` 的契约

- 框按**一个顺序**切开:**箭头条 → 主体 → padding → 标题 → 内容**。
- 箭头条从**朝向锚点的那条边**上切:`psvBottom`(弹窗在锚点下方)→ 条在**顶**;`psvTop` → 条在**底**;`psvRight` → 条在**左**;`psvLeft` → 条在**右**。
- **内容是唯一有弹性的部分**,且它宁可**塌缩为空**也不显示一条细缝——装不下内容的框是一个**测错了的 popover**,不是一种值得维护的布局。
- **所有矩形都可能为空,空永远表示「这里什么都没有」,绝不表示「它挪走了」。** 退化的框(零 / 负尺寸、padding 吃光主体、条比框还厚)让每个矩形都为空,**绝不反转**。
  - padding 吃光主体:**主体本身仍在、仍然绘制**,只是标题与内容都为空。
  - 条吃光整个框:**连主体都没有**——这里根本没有弹窗。
- **标题间隙只花在标题与内容「都在」的时候**(`TyPopoverFrameSize` 与之镜像:内容高为 0 的有标题弹窗**不带**一个通向虚空的间隙)。标题放不下整行时,标题拿走仅剩的空间、内容塌缩。

#### `TyPopoverFrameSize` 的契约

它是 `TyPopoverLayout` 的**逆**:把结果当 `AFrameW`/`AFrameH` 回喂(其余参数相同),`ContentRect` 正好是 `AContentW × AContentH`(已有往返测试守护;这正是**阻止 popover 每次 `Show` 都把自己的内容改小一点**的东西)。结果最小钳到 `1 × 1`。

**宽度不是标题的函数**:标题单行且省略号截断(和本库每一处文字一样),所以长标题显示 `Confirm dele…`,而不是把弹窗从它的内容底下撑出去。

#### `TyPopoverArrowPoints`

三角形的三个点(顶点 + 两个底角),从 layout 的 `ArrowRect` + `ArrowTip` 推出;无箭头时返回 `False` 且不动 out 参数。**底边是箭头条的内侧边**——也就是与主体相接的那条——所以两条斜边从那里跑向框外边缘上的顶点。**从绘制里拆出来,就是为了让「窗口填的那个三角形」成为测试能读的规则。**

### 公开成员

```pascal
class function StyleTypeKey: string;         // 'TyPopover'
class function TitleStyleTypeKey: string;    // 'TyPopoverTitle'

procedure Show;                        // 在 Target 旁弹出。无 Target 时、以及设计期,均惰性无操作
procedure ShowFor(AControl: TControl); // 在任意控件旁弹出。不改 Target
procedure ShowAt(const AAnchorScreen: TRect);  // 在任意屏幕矩形旁弹出:上面两者汇入的接缝,
                                       // 供锚定「非控件之物」(网格单元、一个字形)的宿主使用
procedure Hide;                        // 收起:把内容还回它自己的窗体、隐藏窗口、触发 OnHide。
                                       // 幂等 —— OnHide 每次消失只触发一次,对已收起的 popover
                                       // 调 Hide 什么都不触发

function TitleHeightAt(APPI: Integer): Integer;      // 标题解析字体下的一行高(设备像素)
function MeasureFrameAtPPI(APPI: Integer): TSize;    // 框的自然尺寸(设备像素)
function GeometryIn(const AAnchorScreen, AWorkArea: TRect; APPI: Integer): TTyPopoverGeometry;
function LayoutIn(AFrameW, AFrameH: Integer; ASide: TTyPopoverSide;
  ATipLocal, APPI: Integer): TTyPopoverLayout;
```

- `TitleHeightAt` 用**稳定参照字形 `'Ag'`** 测量,所以**空标题也测得出整整一行**;它必须用 `TTyPainter` 而非 `TBitmap` 画布——标题是用 BGRA 文字度量绘制的,只有同一个测量者才能复现那些字形真正渲染出的高度。结果最小为 1。
- `MeasureFrameAtPPI`:`Content` 的**设计期尺寸原样取用**(它是真实窗体上的真实控件,已经在那个窗体的像素里;**这里不做任何再缩放**——弹窗包住设计器搭出来的东西,不去揣测它)。`Content = nil` 只量出外壳——**没有内容的 popover 是合法的**(虽然没意义),绝不崩溃、也绝不猜一个尺寸。
- `GeometryIn` 的**工作区是参数**(不是 `Screen.WorkAreaRect`),所以定位规则无屏幕可测;`ShowAt` 传真实的那个。

---

## 6. 状态与主题

### 支持的伪类状态

**没有。** 两个 typeKey 都以**空状态集**解析(`ResolveStyle(..., FStyleClass, [])`)——popover 是个非可视组件,没有状态机、不跟踪指针。主题里给 `TyPopover` 写 `:hover` / `:disabled` 是**不会生效**的;变体请走 `StyleClass`。

### 主题令牌摘要

`themes/light.tycss` 中的实际规则(base 层,每个主题都继承,并可各自重写):

```css
/* Popover: a floating surface that HOSTS controls (that is the gap it fills — Hint/BalloonHint
   can only carry text). The arrow is cut from this same surface, so it needs no key. */
TyPopover {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 8px;
  font-size: var(--font-size-base);
}
TyPopoverTitle { color: var(--on-surface); font-size: var(--font-size-base);
                 font-weight: var(--font-weight-bold); }
```

**箭头没有自己的 typeKey**:它就是主体表面被带出自己边缘之外的那一块,取的是主体的 `background`(纯色)与 `border-color` / `border-width`。

### 尺寸令牌(v3/C 约定)

| 令牌 | 内置兜底(逻辑像素) | 作用 |
|------|------|------|
| `--popover-arrow-size` | `8`(= `TyPopoverArrowSize`) | 箭头的**半底宽**,**同时**是箭头条的厚度(`TTyBalloonHint` 的指针也是一个数管两件事;两者必须一致,否则三角形就不再是 45° 直角楔形) |
| `--popover-offset` | `4`(= `TyPopoverOffset`) | 锚点边缘与弹窗**框**近边之间的间隙 |
| `--popover-title-gap` | `6`(= `TyPopoverTitleGap`) | 标题行与内容之间的间隙 |

每个都在调用点缩放到设备像素(`MulDiv(..., APPI, 96)`,与 `TTyPainter.Scale` 同一套换算,所以**这里测出的框就是绘制切开的框**)。负值一律钳为 0。

> 常量而非内联字面量,是因为**多个调用点(布局、测量、测试)必须拼写一致**:任何一处拼错都会静默回落到兜底值,几何就会与测量漂移。**目前随库发布的主题都没有声明这三个令牌**,因此它们实际都取兜底常量;它们的存在是为了让皮肤能各自重调。

### 优雅降级

代码怎么写的就怎么说:

- **主题的 `TyPopover`(或该变体)未声明 `background`** → **完全不画弹窗**,而不是画一个硬编码的。降级,绝不崩溃,绝不发明颜色。
- **主体是渐变 / 图片 / 九宫格(非 `tfkSolid`)** → **没有箭头**:那里没有唯一一个颜色可以带出去,而发明一个正是本库不做的事。**箭头条依然预留**(所以什么都不会挪位),这样的主题只是读作一张浮动卡片。要在渐变弹窗上要箭头,请关掉 `ShowArrow`,或给一个纯色的 `TyPopover`。
- **`TyPopoverTitle` 未定义某个值** → **逐属性**回落到**主体的**:只给了 `font-weight` 的主题照样拿到主体的字族与字号;`color` 未定义 → 标题用弹窗自己的墨色;`background` 未定义 → **不画头带**(主题填了它就白得一条头带)。**绝不回退到任何硬编码字体 / 颜色。**
- **`opacity` 令牌**:设了才应用。
- **边框可见时**(`TyBorderVisible`),箭头**只描两条斜边**——底边属于主体,由主体自己的边框画。
- **Wayland**:没有 XShape,窗口形状被静默忽略 → 弹窗保持**方角与方形箭头条**(`TTyBalloonHint` 的规则原样照搬)。
- **不画阴影**:窗口被裁成主体的轮廓,阴影会和轮廓外的一切一起被裁掉。顶层窗口的高度感是**操作系统的事**。

---

## 7. 代码示例

```pascal
uses tyControls.Controller, tyControls.Popover;

// 窗体上(设计器里)已有:
//   PanelConfirm: TTyPanel  —— Visible=False,里面摆好「确定 / 取消」两个 TTyButton
//   BtnDelete:    TTyButton
//   Pop:          TTyPopover

procedure TForm1.FormCreate(Sender: TObject);
begin
  Pop.Target := BtnDelete;          // 它属于谁、指向谁
  Pop.Content := PanelConfirm;      // 弹窗展示的容器 —— 弹窗按它的设计期尺寸测量
  Pop.Title := '确定要删除吗?';
  Pop.Placement := ppTopRight;      // 偏好:在按钮上方、右对齐(放不下就翻到下方,仍右对齐)
  Pop.CloseOnClickOutside := False; // 「必须回答」:点别处不关
  Pop.CloseOnEscape := True;        // 但键盘退路留着
  Pop.OnShow := @PopShown;
end;

procedure TForm1.BtnDeleteClick(Sender: TObject);
begin
  Pop.Show;                         // 无 Target 时惰性;设计期惰性
end;

procedure TForm1.PopShown(Sender: TObject);
begin
  BtnConfirmYes.SetFocus;           // 内容此时已经在弹窗窗口里了
end;

procedure TForm1.BtnConfirmYesClick(Sender: TObject);
begin
  Pop.Hide;                         // 内容原样回到本窗体;OnHide 触发一次
  DoDelete;
end;
```

锚定「非控件之物」(网格单元、一个字形):

```pascal
// ShowFor / ShowAt 单次越过 Target,且不打扰它
Pop.ShowAt(Grid.ClientToScreen(CellRect));
```

---

## 8. 注意事项

- **非可视组件,不是控件:** 它没有尺寸、没有 `Parent`、不参与对齐。弹窗的大小来自 `Content` 的**设计期尺寸**——**要改大小,改容器,不是改 popover**。
- **`Content` 是借来的,不是拥有的:** `Show` 收养它(记下原 `Parent` / `Align` / `BoundsRect` / `Visible`,置 `Align := alNone`、挂进弹窗窗口、置 `Visible := True`),`Hide` **逐项原样交还**。两次 `Show` 之间,设计器搭的那个窗体和原来一模一样。
- **`Content` 在弹窗立着时被改写 → 先 `Hide`:** 从活着的弹窗底下换掉内容会把旧的那个**遗弃在我们的窗口里**;setter 因此先送它回家,并让调用者自己用新内容重新 `Show`。
- **`Content` 被销毁 → 弹窗自己下来:** `Notification` 丢掉收养关系(**不做交还**——已经没有东西可还了),把 `Content` 置 `nil`,然后 `Hide`。内容刚死掉的 popover 已经没有什么可展示的了。
- **`Placement` 只是偏好:** 别假定 `Geometry.Side` 就是你请求的那一侧。真正落在哪一侧看 `Side`,是否翻转过看 `Flipped`。
- **主轴会溢出:** 两侧都放不下时,框保持贴着锚点并**溢出工作区**(见 §5 的理由)。这是刻意的,不是 bug。
- **销毁不触发 `OnHide`:** 组件消失不等于用户关掉了弹窗,而且处理函数所在的窗体可能已经拆了一半。内容照样会被送回家——它属于那个窗体,不属于我们。
- **`Hide` 幂等:** 每次消失只触发一次 `OnHide`;对已收起的 popover 调 `Hide` 什么都不触发(但**仍会**把可能残留的收养关系交还——万一某次 `Show` 没走完)。
- **设计期惰性:** `ShowAt` 在 `csDesigning` 下直接返回——popover 是**运行期手势,不是设计器预览**;IDE 绝不该落得把窗体的容器重新挂进一个野生弹窗窗口里。
- **`ShowFor` 的锚点矩形** = `AControl.ClientToScreen(Point(0, 0))` 作为左上角,加上控件的 `Width` × `Height`。
- **窗口的 `Color` 必须设:** `TTyPopupSurface` 的教训——裸无边框窗体从不设 `Color`,于是保留操作系统默认的 `clBtnFace`,在**暗色系统上近乎黑**。主体没盖住的每一个像素都会擦除成它(圆角外的四角、箭头旁边的条,以及 Wayland 上——形状区域被静默忽略——的整个轮廓),**应用挂进来的每个透明 / ghost 子控件也一样**,而那正是本组件存在的全部意义。所以 `EnsureWindow` 先用主体自己的表面色(纯色背景时)刷窗口。
- **已知装饰问题(与 `TTyBalloonHint` 共有):** 有边框的主题上,主体自己的边框线**仍会横穿箭头底边**。**观感请在真机上核对。**
- **主题锁定:** 非可视组件没有自己的 `Font`,所以**主题是唯一来源**——`ResolveFontSize` 传 `ParentFont=True` / size 0,让 `TyResolveFontSize` 一路落到 `--font-size-base`。改字号 / 字色请改主题令牌,或用 `StyleClass`。
- **没有 `StyleOverride`:** 那是 `TTyGraphicControl` / `TTyCustomControl` 的成员,本组件继承自 `TComponent`,只有 `StyleClass` 这一个变体入口。
- **`ContentRect` 不被绘制:** 那里住着一个真实控件,它自己画自己。
