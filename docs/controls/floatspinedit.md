# TTyFloatSpinEdit — API 参考

## 1. 概述

`TTyFloatSpinEdit` 是**带步进按钮的小数微调框**——LCL `TFloatSpinEdit`（`spin.pp:89`）的对标控件，继承自 [`TTyNumericEdit`](numericedit.md)。它把库里原本分开的两半合到一起：`TTyNumericEdit` 有 `Value: Double` 和 `Decimals` 但没有按钮，[`TTySpinEdit`](spinedit.md) 有按钮但值是 `Integer`。要一个"单价 / 百分比 / 缩放系数"字段以前必须二选一。

因为底座是 `TTyEdit`，它自带**完整文本引擎**：选区、剪贴板、撤销 / 重做、词级导航、IME —— 这些 `TTySpinEdit` 的轻量行缓冲全都没有。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.FloatSpinEdit` |
| `GetStyleTypeKey` | `'TyEdit'`（**继承**，不覆盖）|
| 基类 | `TTyNumericEdit` → `TTyEdit` → `TTyCustomControl` |
| 默认尺寸 | 140 × 28（逻辑像素，继承自 `TTyEdit`）|

复用 `TyEdit` 主题规则，**无新增 `.tycss`**。

```pascal
uses tyControls.FloatSpinEdit;
```

---

## 3. 为什么它不是 `TTySpinEdit` 的后代

**LCL 的家族方向和我们相反。** LCL 里整数版是小数版的**后代**（`TCustomSpinEdit = class(TCustomFloatSpinEdit)`，`spin.pp:146`），所以"从 `TTySpinEdit` 派生出小数版"这条路在 LCL 那边根本不存在。

**反过来倒挂我们自己的层次也走不通。** `TTySpinEdit` 有三个已发布的 `public virtual` 缝 —— `GetLimitedValue` / `ValueToStr` / `StrToValue`（对标 `spin.pp:74-76`）—— 它们的签名是 `Integer`，而且外部已经有派生类覆写了它们。把它们改成 `Double` 会当场打断这些调用方。

另外两个被否掉的形状，以及否掉的理由：

| 形状 | 为什么不行 |
|------|-----------|
| 在继承来的 `Value: Integer` 上**遮蔽**一个 `Value: Double` | 步进引擎还是整数那套：`1.5` 会被**静默截断**成 1，没有任何提示。`test.floatspinedit` 的 `ValueKeepsItsFraction` 与 `AFractionalIncrementIsNotTruncated` 就是钉这个的。 |
| 给 `TTySpinEdit` 加一个 `DecimalPlaces` **模式** | 需要第二个值属性（`Value: Integer` + 一个 `FloatValue`），于是任何时刻总有一个在说谎。 |

所以：**继承 `TTyNumericEdit`（拿到 Double + 小数位 + 文本引擎），只补一对步进按钮**，按钮走 `TTyEdit` 早就公开的尾部部件三件套 `RightReserve` / `PaintTrailing` / `TrailingZone` —— 和 [`TTyComboEdit`](comboedit.md)、[`TTyURLEdit`](urledit.md) 挂按钮用的是同一组钩子。

---

## 4. 属性表

### 本控件新增（published）

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Increment` | `Double` | `1` | 每步步进量（LCL `spin.pp:80`，同默认值、同 `stored` 规则——等于 1 时**不写进 `.lfm`**）。**刻意不像 `TTySpinEdit.Increment` 那样下限钳到 1**：小于 1 的步长正是小数微调框的意义所在。 |
| `EditorEnabled` | `Boolean` | `True` | 只锁**键盘**，箭头 / 滚轮 / 按钮照常步进（LCL `spin.pp:79`）。详见第 7 节。 |
| `UseThousands` | `Boolean` | **`False`**（重声明，父类是 `True`）| LCL 的小数微调框**不做千分位分组**——它的 `ValueToStr` 就是一句 `FloatToStrF(..., ffFixed, 20, DecimalPlaces)`（`include/spinedit.inc:237`）。父类 `TTyNumericEdit` 默认分组，因为它是通用金额 / 数量框。 |

### 继承自 [`TTyNumericEdit`](numericedit.md)

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Decimals` | `Integer` | `2` | 小数位数。**这是 LCL `DecimalPlaces` 在本库里的名字**——本库另外三个数值框（`TTyNumericEdit` / `TTyCurrencyEdit` / `TTyTrackEdit`）都叫 `Decimals`，一个库里同一件事不应该有两个拼法。从 Lazarus 移植的代码写 `DecimalPlaces` 会得到一个**编译错误**（响亮的失败），而不是一个静默无效的属性。 |
| `MinValue` / `MaxValue` | `Double` | `0` / `0` | 仅当 `MaxValue > MinValue` 时才夹紧；`MaxValue <= MinValue` 表示**不限制**（LCL `include/spinedit.inc:228` 同一条规则）。 |
| `Value` | `Double` | `0` | **public，不是 published**——和父类一致。原因见第 8 节第 3 条。 |

### 继承自 [`TTyEdit`](edit.md)

`Text`（published，`.lfm` 里承载数值的就是它）、`ReadOnly`、`MaxLength`、`Alignment`（构造时为 `taRightJustify`）、`TextHint`、`AutoSelect`、`HideSelection`、`CharCase`、`OnChange`，以及 public 的 `Modified` / `CaretPos` / `SelStart` / `SelLength` / `SelText` / `Undo` / `Redo` / `CopyToClipboard` / `CutToClipboard` / `PasteFromClipboard`。

### 本控件新增（public）

| 成员 | 签名 | 说明 |
|------|------|------|
| `StepValue` | `procedure(ADelta: Double); virtual` | 按"用户在改"的语义移动值：`ReadOnly` 时直接返回，成功后把 `Modified` 置 `True`。**每一个按钮、方向键、滚轮刻度都走它**，派生类改一处就改了全部。 |
| `UpButtonRect` | `function(APPI: Integer): TRect` | 上按钮的可点区域（客户区像素）。控件太窄放不下按钮列时返回空矩形。 |
| `DownButtonRect` | `function(APPI: Integer): TRect` | 下按钮的可点区域。 |

### 单元级函数

```pascal
function TyFloatSpinGlyphBox(const AHalf: TRect): TRect;
```

按钮半区里**最大的居中正方形**，也就是箭头字形真正画进去的框。存在的理由见第 6 节。

---

## 5. 键盘与交互

| 操作 | 行为 |
|------|------|
| 数字 / `-` / 小数点 | 插入（继承 `TTyNumericEdit` 的输入过滤；小数点仅当 `Decimals > 0`）|
| `↑` / `↓` | `Value ± Increment`。**先跑 `inherited`（也就是应用的 `OnKeyDown`）**，处理程序把 `Key` 置 0 表示自己消费掉了，这时**不**步进 |
| 点击上 / 下按钮 | `Value ± Increment`，并把焦点交给字段 |
| 鼠标滚轮 | `Value ± Increment`；应用的 `OnMouseWheel` 先跑，它消费了就不再步进 |
| 聚焦 | 去掉千分位（若开启），显示原始数字（继承） |
| 失焦 | 夹紧 + 重新格式化（继承） |
| 选区 / 剪贴板 / 撤销 / 词级导航 / IME | 全部继承自 `TTyEdit` |

---

## 6. 按钮几何与主题

- **按钮列宽 = `--field-button-width` 令牌**（缺省 18px），**实时读取**——和 `TTyComboBox` 的下拉按钮、`TTyComboEdit` 的箭头区、`TTySpinEdit` 的上下键读的是**同一个**令牌，所以换密度包 / 换皮肤时四者一起变。
- **上下半区**由 `TySpinUpButtonRect` / `TySpinDownButtonRect` 切分——直接复用 `TTySpinEdit` 的几何函数，两个微调控件不会对"上按钮到哪里为止"给出两个答案。
- **箭头**是 `tgArrowUp` / `tgArrowDown`，走 `TyDrawGlyph`，因此可被主题的 `--glyph-arrow-up` / `--glyph-arrow-down` 覆盖（图标字体或图片）；颜色取解析样式的 `TextColor`。

### 和 `TTySpinEdit` 的一处**刻意**差异：按钮区被内距挤进来了

`TTySpinEdit` 自己拥有整个客户区，按钮**贴齐右缘、占满上下**。`TTyFloatSpinEdit` 的按钮挂在 `TTyEdit` 的尾部区里，而这块区域是**被四边内距（`padding`）内缩过**的——所以按钮不贴边，上下也各留出一条内距。

**这是设计，不是回归。** 尾部区的位置由 `TTyEdit` 定义，`TTyComboEdit` 的下拉箭头、`TTyURLEdit` 的打开按钮都在同一位置；让这一个控件跳出去会让三个尾部按钮在同一个表单上高低不一。

它带来的后果是一个必须处理的细节：96 DPI 下按钮半区约 18×10，而 `TTyPainter.DrawGlyph` **默认每边再内缩 4 逻辑像素**，箭头会被压成 1 像素高的一道糊痕（本库踩过的"字形槽位地板"）。所以字形先经 `TyFloatSpinGlyphBox` 取**最大居中正方形**（18×10 → 10×10），再用 `pad = 1` 绘制；这条换算跟着 DPI 与密度自动缩放。

---

## 7. `ReadOnly` 与 `EditorEnabled`：两把不同的锁

和 LCL 一样（`spin.pp:79` 就挨着 `ReadOnly`），二者**正交**：

| | 键入 / 退格 / 删除 / 剪贴板 / 撤销 | 按钮 · 方向键 · 滚轮 | 程序 `Value :=` / `Text :=` |
|---|---|---|---|
| `ReadOnly = True` | 拦 | **拦** | 通 |
| `EditorEnabled = False` | 拦 | **通** | 通 |

`EditorEnabled := False` 的用途是**把值钉在合法刻度上**（0.5 的倍数、一刻钟）而**不**把控件变成死的——`ReadOnly` 做不到这件事。

被拦的键是：任意字符、`Backspace`、`Delete`（含 `Ctrl` 的整词形式），以及 `Ctrl`/`Cmd` + `X` / `V` / `Z` / `Y`。

两条要知道的边界：

1. 这些键是在 `TTyEdit` 看到它们**之前**吞掉的，所以 `OnKeyDown` 也收不到 —— 这一点与 LCL 不同（LCL 在部件层用 `EM_SETREADONLY` 挡住"效果"，通知照发）。
2. 宿主**在代码里**调 `PasteFromClipboard` 时，字段锁着也不会插入任何东西（`FilterInsert` 拒绝了），但**会丢掉当前选区**——因为 `TTyEdit` 先删选区再问过滤器。键盘那条路（`Ctrl+V`）是整条被吞的，没有这个问题。

---

## 8. 注意事项

1. **步长比 `Decimals` 还细 → 按钮看起来是死的。** 值每写一次都要经过"格式化成显示文本 → 再解析回来"，所以 `Decimals = 2` 时 `Increment = 0.001` 会被四舍五入回原地。LCL 在有句柄之后也是这个行为（它的部件层 `GetValue` 同样重新解析编辑框文字）。解法是提高 `Decimals`，不是去动步长。
2. **同一条重新量化也是好事：** `Increment = 0.1` 连点十次上箭头得到的是**正好** `1.00`，不是 `0.9999999999999999` —— 二进制累积误差每一步都被显示文本抹平了。`test.floatspinedit.SteppingDoesNotAccumulateBinaryDrift` 钉住这一条。
3. **`Value` 是 public 不是 published。** 与 `TTyNumericEdit` 一致：这个控件的存储就是 `Text`，而 `Text` 已经 published。两个都 published 的话，一个把 `Text` 设成 `'abc'` 的窗体会写出 `Text='abc'` + `Value=0`，加载时后写的 `Value` 覆盖前者，`.lfm` 不再能原样往返。设计期填数值请写 `Text`，运行期读写用 `Value`。
4. **`Increment` 没有下限保护。** 给 0 会让按钮不动、给负数会让上下颠倒 —— LCL 也不拦（小数没有一个说得通的下限），这是调用方的选择。整数兄弟 `TTySpinEdit` 把 `Increment` 钳到 ≥ 1，两者必须不同。
5. **`ValueEmpty` 没有。** LCL 的 `TFloatSpinEdit` 也**没有** published 它（只在 `TCustomFloatSpinEdit` 的 public 段）。在一个 `TTyEdit` 底座上，"空"就是 `Text = ''`，占位提示用继承来的 `TextHint`。
6. **没有 `OnValueChange`。** `TTySpinEdit` 的那一对（`OnChange` = 文字变了 / `OnValueChange` = 提交后的值动了）是为它的"缓冲 + 提交"模型准备的；这里值**就是**文字，`OnChange` 一个就够，与 `TTyNumericEdit` / `TTyCurrencyEdit` 一致。
7. **点按钮会取走焦点**，这一点和另外两个尾部按钮控件不同（`TTyComboEdit` 弹 popup、`TTyURLEdit` 打开浏览器，都把用户交出去了）。微调按钮之后用户还在字段里，方向键要能接着按。
8. **只读时滚轮报告"未处理"**（`DoMouseWheel` 返回 `False`），这样外层滚动容器还能滚 —— 否则鼠标停在一个用不上滚轮的字段上，整页就滚不动了。

---

## 9. 代码示例

```pascal
uses tyControls.Controller, tyControls.FloatSpinEdit;

TyDefaultController.LoadTheme('themes/light.tycss');

var Scale: TTyFloatSpinEdit;
Scale := TTyFloatSpinEdit.Create(Self);
Scale.Parent := Self;
Scale.SetBounds(24, 24, 140, 28);
Scale.Decimals  := 2;       // 显示两位小数（LCL 里叫 DecimalPlaces）
Scale.MinValue  := 0.25;
Scale.MaxValue  := 4;       // Max > Min 才启用夹紧
Scale.Increment := 0.25;    // 每步四分之一
Scale.Value     := 1;

// 只许用箭头在 0.25 的倍数上选，不许手打
Scale.EditorEnabled := False;

Scale.OnChange := @ScaleChanged;

procedure TMainForm.ScaleChanged(Sender: TObject);
begin
  Preview.Zoom := (Sender as TTyFloatSpinEdit).Value;
end;
```

---

## 10. 相关控件

| 需要 | 用 |
|------|-----|
| 整数 + 按钮 | [`TTySpinEdit`](spinedit.md) |
| 小数、不要按钮 | [`TTyNumericEdit`](numericedit.md) |
| 小数 + 货币符号 | [`TTyCurrencyEdit`](currencyedit.md) |
| 小数 + 内嵌滑块 | [`TTyTrackEdit`](trackedit.md) |
| 一对独立的上下按钮，绑到别的控件 | [`TTyUpDown`](updown.md)（`Associate`）|
