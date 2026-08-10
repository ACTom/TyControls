# `TTyCustomTabStrip` — `MultiLine` 规格

> **状态：已实现（2026-08-07），除 `ScrollOpposite` 外全部落地。**
> 下文保留了原规格的正文，**做掉的部分加了删除线**，并在每一节末尾用 `> 实测：` 记下
> 与规格不符之处。规格是写在「还没做过」的时候的，有四处推断经不起实现，逐条列在 §8。
> `ScrollOpposite` **明确不做**，理由见 §4 的实测段与 §8.5。
>
> 测试：`tests/test.tabstrip.multiline.pas`（21 条），变异 14 个全部被杀（§7；
> 其中 2 个是第一轮活下来、补强守卫后才杀掉的，见 §7.1）。

**原状态：未做。** 同一轮里 `TabPosition` 与页签图标已经落地并合并；`MultiLine` 一族
（`MultiLine` / `RaggedRight` / `ScrollOpposite` / `RowCount`）被**明确划出**，
因为它需要的东西比另外两个多一层，而半做的它比不做更糟——多行与溢出滚动是**互斥**的两条路，
一个只做了一半的实现会同时留下滚动箭头和折行，两边都不对。

本文写到"照着做就能做"的粒度，包括每个判断的理由、边界情形、以及测试要钉哪些点。

---

## 1. 现在的地基（做这件事之前必须先读懂的部分）

`source/tyControls.TabStrip.pas`：

- **内容空间**是一条**一维行程**：`RebuildLayout` 沿"主轴"从 0 开始逐个累加，
  `x` 携带**主轴**、`y` 携带**次轴**（一个页签占满条带厚度）。
- **`ToScreenRect` 是唯一的坐标变换**，三步：沿主轴平移 `HeaderShiftPx` →
  按 `TabPosition` 把行程嵌进控件方框 → 右到左时反射**屏幕横轴**。
  `tpTop` 下三步全是恒等，所以默认形态逐字节不变。
- **`ToReadingMain` 是它的精确逆**（反射、嵌入两步倒着跑），
  绘制 / 命中 / 拖拽中点 / 滚动偏移四个消费者都只经这一对函数换算。

**做 `MultiLine` 时唯一不能碰的东西就是这一点：四个消费者必须继续出自同一处。**

好消息是：多行**天然落在现有的内容空间里**——次轴坐标现在恒为 `0..Cross`，
多行只是让它变成 `Row*RowThick .. (Row+1)*RowThick`。
`ToScreenRect` **一行都不用改**。

> **实测：这一节全部成立。** `ToScreenRect` 一个字符都没改，四个消费者仍然同源。
> 但"次轴只是从 `0..Cross` 变成 `Row*RowThick..`"这句话在 `RebuildLayout` **内部**
> 还牵着两组次轴坐标，规格没提：**关闭 × 与图标的槽位**。它们原来写的是
> `(TabH - CloseSize) div 2` 和 `Cross - Margin - CloseSize`，那是"从条带边算"，
> 单行时恰好等于"从本行边算"。不改的话每个关闭 × 都会堆在第 0 行上，
> 页签本体却在第 1 行。见 §5 的实测段。

---

## 2. 要加的属性

| 属性 | 类型 | 默认 | LCL 出处 | 说明 |
|---|---|---|---|---|
| ~~`MultiLine`~~ ✅ | `Boolean` | `False` | `TCustomTabControl.MultiLine` | `True` 时行程折行填满整条带，**不再出现溢出箭头** |
| ~~`RaggedRight`~~ ✅ | `Boolean` | `False` | 同上 | `False`（LCL 默认）时把每一行的页签**拉伸**到铺满整行；`True` 时保持自然宽度、行尾留白 |
| `ScrollOpposite` ❌ **不做** | `Boolean` | `False` | 同上 | 见 §4，只在 `MultiLine = True` 时有意义 |
| ~~`RowCount`~~ ✅ | `Integer` | — | `TCustomTabControl.RowCount` | **只读**。`MultiLine = False` 时恒为 1（有页签时）或 0（无页签时） |

> **`default` 指令的注意事项**：三个 `Boolean` 都必须写 `default False`。
> 它们是新属性，没有任何既存 `.lfm` 带过它们，所以 `False` 既是 LCL 的默认也是
> "现状不变"的那一侧——这两点同时成立，才可以放心写 `default`。

`RowCount` **只读**这一点要照抄 LCL：行数是布局的**结果**，不是输入。
给它一个 setter 会立刻产生"我设了 3 行但只排得下 2 行"这种无法回答的状态。

> **实测：**
> - `MultiLine` / `RaggedRight` 在基类是 `public`、在 `TTyPageControl` 与 `TTyTabSet` 上
>   才 `published`——照 `TabPosition` 的先例（`TTyRibbon` 的 chrome 只有一行高，见 §8.3）。
> - `RowCount` **只能 public，不能 published**，规格没写这一条而它是硬规则：
>   只读属性没有 setter，`TWriter.WriteProperty` 会跳过它、对象检查器报"无法读取"
>   （WAVE_RULES §4）。LCL 的 `RowCount` 也是 public。
> - 另外加了一个 protected 虚函数 `HeaderMultiLine`，与既有的 `HeaderTabPosition` 同形：
>   布局只读它，子类可以在**一个地方**整体拒绝折行。`TTyRibbon` 需要它，见 §8.3。

---

## 3. 布局（改动集中在 `RebuildLayout` 的第二趟）

现在的第二趟是：

```
X := 0;
for I := ... do begin FHeaderRects[I] := Rect(X, 0, X + MainExt, Cross); Inc(X, MainExt); end;
```

多行版：

```
Row := 0; X := 0;
for I := ... do
begin
  if FMultiLine and (X > 0) and (X + MainExt > MainVisible) then
  begin Inc(Row); X := 0; end;            // 折行：放不下就换行，且不在行首折
  FHeaderRects[I] := Rect(X, Row * RowThick, X + MainExt, (Row + 1) * RowThick);
  Inc(X, MainExt);
end;
FRowCount := Row + 1;
FBandThickness := FRowCount * RowThick;   // 次轴厚度 = 行数 × 一行的厚度
```

要点，按重要性排：

1. ~~**`(X > 0)` 这个条件不能省。** 一个比整条带还宽的页签必须**独占一行**，
   否则它会在行首就触发折行、`X` 归零、再次触发——死循环。~~
   > **实测：条件确实不能省，但理由是错的——不会死循环。** 折行写在一个
   > `for I := 0 to GetTabCount - 1` 里，循环次数是固定的，重复触发折行只会
   > 让 `Row` 多加一次。真正的后果是：**一个过宽的页签会在行首被推到下一行，
   > 上面留下一整行空的**。首个页签就过宽时最明显（第 0 行全空）。
   > 变异 M1 打掉这个条件后，红的是 `AnOverWideTabKeepsItsOwnRowAndLeavesNoneEmpty`
   > 里的"`RowCount = 2`"与"tab 0 在第 0 行"两条，**不是超时**。
   > 因此测试点 §6.3 也照这个改写了（断言行数与行号，不用超时）。
2. **`RowThick` 就是现在的 `TabH`**（顶/底条带）或 `TabH`（左/右条带的行高）。
   多行**对左/右条带同样成立**：那是"多列"，行程横着折。语义上是一回事，代码上是同一段。
   > **实测：成立，但 `RowThick` 的取值规格说反了。** 次轴方向上一行的厚度：
   > 顶/底条带是 `TabH`，左/右条带是**最宽的标题盒**（`TabH` 是左/右条带的**主轴**
   > 长度，不是厚度）。代码里就是原来那个 `Cross`，改名成 `RowThick`，
   > 两种形态用同一个变量，`FBandThickness := FRowCount * RowThick` 一句覆盖两者。
   > 都来自既有令牌（`--control-height` / `--tab-padding` + 字体），没有新令牌。
   > comctl32 的 `TCS_MULTILINE` + `TCS_VERTICAL` 也是多列，这一点我们与 LCL 一致。
3. **`FBandThickness` 变成 `FRowCount * RowThick`**，`InsetForBand` / `BandBoxPx` /
   `BandRect` 全部**不用改**——它们已经拿 `BandThicknessPx` 说话。
   这是把行数折进厚度而不是折进别处的**唯一理由**，也是这套设计最省的一步。
   > **实测：三个消费者确实一行没改，但 `BandThicknessPx` 本身必须改**，规格漏了它。
   > 它原来对横向条带**短路**（`if not BandIsVertical then Exit(TabHPx(...))`），
   > 折行后横向条带的厚度也是 `RowCount` 行，短路会答一行。现在的条件是
   > `if not (BandIsVertical or HeaderMultiLine) then Exit(TabHPx(...))`。
   > **另有一个空条带的例外**：`GetTabCount = 0` 时 `FRowCount = 0`，
   > 照字面写 `FBandThickness := FRowCount * RowThick` 会得到 0——
   > 而**空条带一直是画一行底的**。所以无页签时厚度取 `RowThick`、行数取 0。
   > 变异 M9 专钉这一条。
4. **`MultiLine = True` 时必须强制 `FShowScrollAffordance := False`、`FHeaderScroll := 0`、
   `FArrowBandPx := 0`。** 折行与滚动是互斥的：内容已经全部可见，再留一条箭头带
   等于凭空吃掉两端各 16px 并把行首页签推到箭头下面。LCL 也是这样（`MultiLine`
   打开时原生标签控件不给 `TCS_SCROLLOPPOSITE` 以外的滚动）。
   > **实测：成立。** 只需要在 `FShowScrollAffordance` 的赋值里加 `(not Multi) and`，
   > 另外三个量顺着既有的 else 分支与末尾的 clamp 自动归零，不用单独写。
   > `SetMultiLine` 里额外 `FHeaderScroll := 0`（打开折行时把已生效的偏移**丢弃**
   > 而不是留着）。
5. **`RaggedRight = False` 的拉伸**要在**第三趟**做，而不是在折行时边折边拉：
   一行放几个只有折完才知道。第三趟按行重新分配：
   `extra := MainVisible - 行内总宽; 每个页签分 extra div n，前 extra mod n 个各多 1px`。
   **余数必须逐个发下去而不是丢掉**，否则最后一个页签与行尾之间会差几个像素，
   在有边框的皮肤下看得见。
   > **实测：成立，两处补充。**
   > (a) 拉伸的目标不是 `MainVisible` 而是 `MainVisible - HeaderLeftInset`
   >     （折行的判据也一样）：行程是**带着 `HeaderShiftPx` 偏移画出去的**，
   >     按整条带宽拉伸会让每一行都超出控件正好一个 inset。
   >     变异 M12 用一个 `HeaderLeftInset = 40` 的测试子类钉住。
   > (b) `extra < 0` 时（过宽的独占行）**不能收缩**，直接跳过。
   > 实现分成 2a 折行 / 2b 拉伸 / 2c 放置三趟，2c 才写 rect，
   > 所以关闭 × 与图标自动落在拉伸后的位置上。
6. `TabCaptionWidth` 每次调用 new 一个 `TBitmap`；折行让 `RebuildLayout` 的成本不变
   （还是每页签一次），但**第三趟不要重新测量**，只改 `Left/Right`。
   > **实测：成立**（2b 只改数字，2c 只放置，都不再测量）。
   > 但另有一笔规格没算的开销，见 §8.4。

---

## 4. `ScrollOpposite`——语义先说清楚，这是最容易做错的一个

Delphi 的定义：`MultiLine = True` 时，用户点了**非贴近页面体那一行**的页签，
行会重排，让**被选中的那一行**贴到页面体旁边。`ScrollOpposite` 决定重排怎么做：

- `False`（默认）：**被选中的行移到贴近页面体的一侧**，它原先所在位置以上的行往外挪。
- `True`：**未被选中的行整体移到相反的一侧**。

两者的可见差别只有在 3 行以上时才明显。**实现建议：把它做成一个纯函数的行置换**

```
function RowDisplayOrder(ARowCount, ASelectedRow: Integer; AOpposite: Boolean): TIntegerArray;
```

返回"第 k 个显示位置上放的是第几行"，`RebuildLayout` 第二趟拿它把 `Row` 映射成
`DisplayRow` 再乘 `RowThick`。这样做的三个理由：

1. 它是**纯的**，可以脱离控件单测，把 `ScrollOpposite` 的语义钉死在一张表上——
   而这正是最需要被钉死的部分（两个布尔值 × 行数 × 选中行，四维，读代码读不出来）。
2. 置换只作用在**次轴坐标**上，`ToScreenRect` 依旧不用改，四个消费者依旧同源。
3. **选中行变化会改变布局**，所以 `SetTabIndex` 必须触发一次重排。
   这是 `ScrollOpposite` 真正的成本：它把"选中"从一个纯粹的**渲染状态**
   变成了**布局输入**。现在 `SetTabIndex` 只 `Invalidate` + `ScrollTabIntoView`；
   多行下它还要 `Realign`（`FBandThickness` 不变，但页签位置变了）。
   **这一条是 `MultiLine` 与现有代码耦合最深的一处，也是把它划出本轮的主要原因。**

> **实测：三条理由里第 3 条的**机制**判断不成立，但**结论**成立，而且真正的
> 理由比规格说的更硬。逐条：
>
> **(a) "`SetTabIndex` 必须触发重排"——技术上是免费的。** `RebuildLayout`
> 名字里带 cached，实际上**每次调用都全量重算**（`FHeaderRects` 只是一次调用内的
> 缓存）。所以选中变化会被下一次任何调用自动带进来，`SetTabIndex` 现有的
> `Invalidate` 已经够了；`FBandThickness` 不变，`Realign` 也不需要。
> 规格担心的那笔耦合成本，在这套设计里并不存在。
>
> **(b) 但有一笔规格没看见的成本，而且它落在本控件历来最容易坏的那条缝上：
> 拖拽重排。** comctl32 没有拖拽重排，本控件有。拖拽时**选中钉在位置上**
> （`TTyPageControl.DoReorderTabs` / `TTyTabSet.DoReorderTabs` 都这么写、都有注释），
> 于是一次跨行的拖拽会改变"哪一行被选中"→ 行立刻重排 → **指针底下的页签换了位置**，
> 而 `MouseMove` 正拿着这个位置继续解析落点。这是一个手势进行中的自我扰动，
> headless 很难测出来，正是 §1 那条"四个消费者必须同源"要防的东西的下一层。
>
> **(c) 语义本身欠定义。** "被选中的行移到贴近页面体的一侧，其余往外挪"在
> 3 行以上时到底是**整体轮转**还是**后缀轮转**，Delphi 文档说不清楚，
> comctl32 的实现细节也不是本库该去逆的东西。规格建议"用一张全枚举表钉死"，
> 但**钉死一张自己编的表并不等于钉死 LCL 的语义**——它只会把一个猜测变成合约。
>
> **(d) 决定：行重排与 `ScrollOpposite` 一起不做。** 两者是一件事——
> 没有行重排，`ScrollOpposite` 就是一个 published 却什么都不做的属性，
> 而那正是本轮要清除的缺陷类（`tests/test.parity.pas` 的
> `LyingPropertiesStayUnpublished`）。不做行重排的代价写进了文档：
> `tpTop` 下只有最后一行的页签会与页面体的框融成一体，活动页签在别的行里靠填色区分。
> 现代的多行标签栏（VS Code、浏览器）也都不做这个重排——点一下标签整片跳动
> 是那个年代的产物。
> **`SelectionIsStillARenderStateNotALayoutInput` 这条测试把这个决定钉住了**：
> 它断言换选中不会移动任何一个页签，并断言 `ScrollOpposite` 这个属性不存在。
> 将来要做行重排，第一件事就是**故意**改写这条测试。

---

## 5. 四个消费者各自要改什么（以及为什么大部分不用改）

| 消费者 | 改动 |
|---|---|
| **绘制** `RenderTo` | 不用改。`HeaderRectShifted` 已经把次轴坐标带出来了 |
| **命中** `IndexOfTabAt` / `MouseDown` / `MouseMove` | **要改**：现在扫的是 `HitMainSpan`（只比主轴），多行下必须比**两轴**。改成 `HitRect`。注意这在 `RowCount = 1` 时与 `HitMainSpan` **不等价**；~~所以**只在 `MultiLine` 打开时**换成两轴比较~~ |
| **拖拽中点** `TyDropIndexAtPoint` | **要改**：一维的"第一个中点在指针之后"要变成**字典序**比较 `(行, 主轴中点)`。落点仍然是唯一一处比较，仍然用 `ToReadingMain` + 一个新的 `ToReadingCross`。`RowCount = 1` 时字典序退化成现在的规则，逐字节相同 |
| **滚动偏移** `HeaderShiftPx` | 不用改，因为多行下滚动被强制关掉（§3.4），`FHeaderScroll` 恒 0 |

**`ToReadingCross` 是这件事唯一要新增的变换成员**，而且它必须和 `ToReadingMain`
写在一起、用同一套逆序步骤，否则两个逆函数会各自漂移——那正是 §3.11 收口的那个毛病。

> **实测：四行都对方向，三处细节不同。**
>
> **(a) 绘制确实一行没改，但 `RebuildLayout` 里给绘制准备的两组次轴坐标要改**——
> 关闭 × 与图标的槽位（见 §1 实测段）。变异 M7 钉这一条。
>
> **(b) 命中改成两轴，但规格说的"`RowCount = 1` 时两者不等价、所以要加条件"是**
> **错的：单行时两者恒等价**，因为扫描前的 `HitBandMinor` 已经把次轴限死在条带内，
> 而单行页签的次轴范围**就是**整条带。规格担心的溢出情形只影响**主轴**
> （行程会伸出控件外），命中恰恰不能在主轴上加条带限制——那是 `HitBandMinor`
> 只比次轴的原因，与这里无关。所以实现是**无条件两轴**，`HitMainSpan` 整个删掉，
> 全库只剩 `HitRect` 一条命中规则。既有的 26 条 axis 测试与 31 条 strip 测试
> 全绿，就是这个等价性的证据。
>
> **(c) `ToReadingCross` 与 `ToReadingMain` 不对称，而且那个不对称是承重的。**
> `ToReadingMain` 可以给 `BandBoxPx` 传厚度 0（它读的是条带**沿着走**的那根轴，
> 厚度不影响），`ToReadingCross` **必须传真厚度**（它读的正是厚度摆放的那根轴：
> `tpBottom` 的 `AH - AThickness`、`tpRight` 的 `AW - AThickness`）。
> 传 0 在 `tpTop` 下答对、在另外三种形态下差整个控件。变异 M10 钉这一条。
>
> **(d) 落点解析要把指针的次轴坐标钳进条带**，规格没提。不钳的话，一次拖出条带的
> 手势会答"第一行之上/最后一行之下"——那是**另一个槽位**而不是邻近的槽位。
> 变异 M11 钉这一条，`ADragOffTheBandClampsIntoTheNearestRow` 是它的测试。
>
> **(e) 而"`RowCount = 1` 时字典序会自动退化"是错的**（规格与我自己第一版实现都这么
> 以为）。`TabHeight = 0` 让每一行的次轴厚度变成 0，`RC < HR.Bottom` 对零高的行
> 永不成立，扫描穿过所有页签返回默认值——`TyDropIndexAt` 是纯公开 API，
> 不在 `HitBandMinor` 那道门后面，所以"没人够得着"不是答案。
> 现在按 `FRowCount > 1` 显式分支，单行那一支**照抄**原规则。
> 变异 M14 钉这一条，`AHiddenBandStillResolvesADropByMidpoints` 是它的测试。

---

## 6. 测试要钉的点（每一条都先看它红）

1. ~~`MultiLine = False`（默认）时 `RowCount = 1`、几何逐字节不变~~ ✅
   `DefaultsAreOffAndRowCountIsOne`（四种 `TabPosition`）。
2. ~~折行点：把控件宽度调到"第 3 个页签差 1px 放不下"，断言第 3 个在第 2 行、第 2 个仍在第 1 行。
   **探针对准边界，不要对准行中央。**~~ ✅
   `ATabFoldsAtTheExactPixelItStopsFitting`——**两侧都探**：差 1px 时折、正好够时不折。
3. ~~一个宽过整条带的页签独占一行，且**不死循环**（超时即失败）。~~ ✅
   `AnOverWideTabKeepsItsOwnRowAndLeavesNoneEmpty`——**改成断言行数与行号**，
   因为不会死循环（§3.1 实测）。
4. ~~`RaggedRight = False` 时每一行的最后一个页签**右边缘正好等于**条带边缘（余数逐个发）；
   `True` 时不等于。~~ ✅
   `RaggedRightOffFillsTheRowToTheLastPixel` / `RaggedRightOnLeavesTheRowShort`——
   fixture 把余数刻意做成 1，所以"丢余数"正好差 1px。
5. ~~`MultiLine` 打开后**溢出箭头消失**、`TyMaxHeaderScroll = 0`。~~ ✅
   `FoldingTurnsTheOverflowAffordanceOff`（另加：已生效的偏移必须被丢弃）。
6. ~~`AdjustClientRect` / `DisplayRect` 扣掉的是 **`RowCount × 行厚**，不是一行。~~ ✅
   `TheBodyGivesUpEveryRowNotJustTheFirst`（顶 + 底）。
7. ~~**绘制与命中在多行下仍然同源**：对每个页签，取它画出来的矩形，
   在四个角内 1px 处命中，必须命中它自己。~~ ✅
   `PaintHitAndDragAgreeOnEveryFoldedBand` / `...WhenMirrored`——**8 种形态**，
   每种先断言"画出来的红色包围盒 = `TabRect`"，再拿**那个包围盒**去探命中与落点。
8. ~~**拖拽中点跟着绘制走**：跨**行**拖拽必须落在正确的槽位。~~ ✅
   `ADragAcrossARowBoundaryLandsInTheRightSlot`——两个探针在一维规则下都**差整整一个槽**。
9. ~~`ScrollOpposite` 的行置换表~~ ❌ **删除**，见 §4 实测。
   换成 `SelectionIsStillARenderStateNotALayoutInput`：钉住"不做行重排"这个决定。
10. ~~四个 `TabPosition` × `MultiLine` 的交叉~~ ✅
    `PaintHitAndDragAgree*`（8 形态）+ `ASideBandFoldsIntoColumns`。

**规格之外另加的 6 条**（都对应实测里发现的坑）：

11. `AnEmptyStripStillHasItsBand`——空条带不能因为 `RowCount = 0` 而失去底（§3.3 实测）。
12. `TheCloseGlyphTravelsDownToItsOwnRow`——关闭 × 的次轴坐标从**本行**算（§1 实测）。
13. `PressAndHoverReachTheSecondRow`——`MouseDown` / `MouseMove` 各有一套自己的扫描，
    `IndexOfTabAt` 绿不代表它们绿；hover 一半用 `TyTabHoverClose`（`MouseMove` 自己写的值）断言。
14. `ADragOffTheBandClampsIntoTheNearestRow`——指针离开条带时钳到最近的行（§5(d) 实测）。
15. `TheOneAxisDropEntryPointStillIgnoresTheOtherAxis`——`TyDropIndexAt(X)` 的 `y = 0`
    在 `tpBottom` 上不能把答案带偏（§5(d) 实测）。
16. `AReservedHeadIsRoomTheRowsDoNotGet`——折行/拉伸的基准要扣掉 `HeaderLeftInset`（§3.5 实测）。
17. `AHiddenBandStillResolvesADropByMidpoints`——`TabHeight = 0` 时行厚为 0，落点解析
    不能再比较行，否则对整条带的每一点都返回默认值（见 §7 末尾）。
18. `TheStripExtentIsTheLongestRowNotTheLast`——`TyHeaderStripWidth` 取**最长行**；
    fixture 特意开 `RaggedRight` 让各行不等长（见 §7.1）。

---

## 7. 变异测试

规格建议的 5 个 + 实现过程中发现的 9 个，共 14 个（驱动脚本
`scratchpad/a649_mutate.sh`）。每一个都是「改一处 → `lazbuild -B` 编包 →
增量编测试工程 → 跑 4 个 tab 相关套件 → **无条件还原**」。

> **M3 排在第一个当作构建链路的对照**：它先用「包与测试工程双 `-B`」完整跑过一次，
> 11 红；快循环若在链接旧库，它会变绿，整轮就作废。实测两次都是 11 红。

- ~~折行条件去掉 `(X > 0)` → 第 3 条必须超时/红。~~ → **M1**，红，但是断言红不是超时。
- ~~`RaggedRight` 的余数丢掉 → 第 4 条必须红。~~ → **M2**，红。
- ~~`FBandThickness` 仍取一行厚 → 第 6、7 条必须红。~~ → **M3**，红（11 条）。
- ~~拖拽中点保持一维（不比较行）→ **第 8 条必须红**。~~ → **M4**，红。
- ~~`MultiLine` 下不清 `FShowScrollAffordance` → 第 5 条必须红。~~ → **M5**，红。
- 新增：**M6** 命中退回只比主轴 / **M7** 关闭 × 从条带算 / **M8** 折行早一像素（`>` → `>=`）/
  **M9** 空条带失去底 / **M10** `ToReadingCross` 传厚度 0 / **M11** 落点不钳次轴 /
  **M12** 折行基准不扣 `HeaderLeftInset` / **M13** `TyHeaderStripWidth` 取最后一行而非最长行 /
  **M14** 落点解析对单行也走折行规则（`Folded := True`）。

### 7.1 第一轮活下来的两个变异体（都是**弱守卫**，不是"代码本来就对"）

第一轮 14 个里 **M5 与 M13 活了下来**，而 M5 正是规格明确点名"必须红"的那一个。
两者的**根因是同一个**：本单元所有折行 fixture 都是**默认拉伸**的，
而拉伸会把每一行都钉成正好一个条带宽——

- **M5**（折行时不清 `FShowScrollAffordance`）：拉伸之后 `StripLen` 恒等于 `MainVisible`，
  溢出判据 `StripLen > MainVisible` 靠算术就答 False，`not Multi` 那一项根本轮不到被读。
  这一项**唯一真正起作用**的形态是"某一行里有一个比条带还宽的页签"，
  于是把断言加到 `AnOverWideTabKeepsItsOwnRowAndLeavesNoneEmpty` 上
  （那个 fixture 天然满足 `TyHeaderStripWidth > Width`）。补后：红，`TyMaxHeaderScroll` 变成 72。
- **M13**（`TyHeaderStripWidth` 取最后一行而非最长行）：拉伸之后最后一行与最长行**是同一个数**。
  新增 `TheStripExtentIsTheLongestRowNotTheLast`，**特意开 `RaggedRight`** 让各行不等长。
  补后：红，216 vs 162。

补完两条断言后重跑这两个变异体，**14/14 全部被杀**。
教训写在两条测试的注释里：一个把所有行拉成等长的 fixture，
测不出任何一条"哪一行最长/有没有超出"的规则。

**M14 对应的是写完之后复读自己的代码找出来的一个真缺陷**：落点解析原来无条件比较行，
而 `TabHeight = 0`（"完全不要条带"，是一个已发布并有测试的能力）会让每一行的次轴厚度
变成 **0**，半开区间 `RC < HR.Bottom` 对一个零高的行永远不成立——扫描会穿过所有页签、
对条带上的任意一点都返回默认值。折行之前这条规则根本不碰次轴，所以是本轮引入的回归。
修法是让"有没有行结构"（`FRowCount > 1`）显式分支，单行那一支**照抄原规则**而不是
论证它会退化——WAVE_RULES 反复说的就是"论证等价"这一步最容易假绿。

---

## 8. 规格里经不起实现的五处 + 一个决定

1. **§3.1「死循环」** —— 折行在 `for` 循环里，去掉 `(X > 0)` 只会多出一整行空行。
   条件要保留，理由要换。
2. **§3.3「`InsetForBand` / `BandBoxPx` / `BandRect` 全部不用改」** —— 对，
   但 `BandThicknessPx` 自己必须改（它对横向条带短路），而且空条带要特判。
3. **§5「命中只在 `MultiLine` 打开时换成两轴」** —— 不必加条件，单行时两轴与单轴等价
   （`HitBandMinor` 已经限死次轴）。无条件两轴，`HitMainSpan` 删除。
4. **§5「`ToReadingCross` 与 `ToReadingMain` 用同一套逆序步骤」** —— 步骤同，
   但**传给 `BandBoxPx` 的厚度参数必须不同**，而那正是最容易照抄错的一行。
5. **§5「`RowCount = 1` 时字典序退化成现在的规则，逐字节相同」** —— 不成立。
   `TabHeight = 0` 让行厚为 0，半开的次轴比较对零高行永不成立，扫描会全部落空。
   必须按 `FRowCount > 1` 显式分支、单行那一支照抄旧规则。
6. **§4 `ScrollOpposite`** —— 规格给的"划出本轮"的理由（`SetTabIndex` 要重排）
   在这套设计里不成立（`RebuildLayout` 本来就每次全量）；但**结论仍然是不做**，
   真正的理由是拖拽重排会与行重排互相扰动、以及语义欠定义。见 §4 实测 (b)(c)(d)。

## 9. 留给下一个人的

- **`TTyRibbon` 需要一行覆盖**（本轮 `source/tyControls.Ribbon.pas` 不在编辑范围内）：
  ```pascal
  function TTyRibbon.HeaderMultiLine: Boolean; begin Result := False; end;
  ```
  （声明加在 protected 段 `HeaderLeftInset` 旁边。）
  证据：`Ribbon.pas` 的 File 页签（`h := MulDiv(TabHeight, ppi, 96)`）、
  折叠 V 形（`TyRibbonCollapseRect(ClientWidth, MulDiv(TabHeight, ...))`）、
  minimized 飞出的原点（`stripH := MulDiv(TabHeight, ...)`）
  与两处 `MouseDown` 门（`if (Y >= 0) and (Y < h) and (X >= HeaderLeftInset)`）
  全部按**一行**算。折行后条带两行高，这些 chrome 仍然一行高、只应答第一行。
  `MultiLine` 在功能区上没有 published（同 `TabPosition`），所以只有从代码里
  显式赋值才会踩到——与 `TabPosition` 在功能区上**已经存在**的同一个缺口等价。
- **`RebuildLayout` 的调用次数**：折行让横向条带也走上"每次 `BandThicknessPx`
  都全量重算布局"的路（原来只有左/右条带这样）。`RenderTo` 每个页签经
  `HeaderRectShifted` → `ToScreenRect` → `BandBoxPx(..., BandThicknessPx)`
  各触发一次，而 `TabCaptionWidth` 每次都 new 一个 `TBitmap`：n 个页签一帧 n² 次测量。
  左/右条带早就是这样、没有报过性能问题，所以本轮不动它；
  真要修就是给 `RebuildLayout` 加一个按 (PPI, 尺寸, 页签内容, 主题版本) 失效的缓存，
  那需要一套自己的失效规则，不该塞进这次改动。
