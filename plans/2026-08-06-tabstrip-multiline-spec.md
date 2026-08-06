# `TTyCustomTabStrip` — `MultiLine` 规格（未实现，可直接照做）

**状态：未做。** 同一轮里 `TabPosition` 与页签图标已经落地并合并；`MultiLine` 一族
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

---

## 2. 要加的属性

| 属性 | 类型 | 默认 | LCL 出处 | 说明 |
|---|---|---|---|---|
| `MultiLine` | `Boolean` | `False` | `TCustomTabControl.MultiLine` | `True` 时行程折行填满整条带，**不再出现溢出箭头** |
| `RaggedRight` | `Boolean` | `False` | 同上 | `False`（LCL 默认）时把每一行的页签**拉伸**到铺满整行；`True` 时保持自然宽度、行尾留白 |
| `ScrollOpposite` | `Boolean` | `False` | 同上 | 见 §4，只在 `MultiLine = True` 时有意义 |
| `RowCount` | `Integer` | — | `TCustomTabControl.RowCount` | **只读**。`MultiLine = False` 时恒为 1（有页签时）或 0（无页签时） |

> **`default` 指令的注意事项**：三个 `Boolean` 都必须写 `default False`。
> 它们是新属性，没有任何既存 `.lfm` 带过它们，所以 `False` 既是 LCL 的默认也是
> "现状不变"的那一侧——这两点同时成立，才可以放心写 `default`。

`RowCount` **只读**这一点要照抄 LCL：行数是布局的**结果**，不是输入。
给它一个 setter 会立刻产生"我设了 3 行但只排得下 2 行"这种无法回答的状态。

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

1. **`(X > 0)` 这个条件不能省。** 一个比整条带还宽的页签必须**独占一行**，
   否则它会在行首就触发折行、`X` 归零、再次触发——死循环。
2. **`RowThick` 就是现在的 `TabH`**（顶/底条带）或 `TabH`（左/右条带的行高）。
   多行**对左/右条带同样成立**：那是"多列"，行程横着折。语义上是一回事，代码上是同一段。
3. **`FBandThickness` 变成 `FRowCount * RowThick`**，`InsetForBand` / `BandBoxPx` /
   `BandRect` 全部**不用改**——它们已经拿 `BandThicknessPx` 说话。
   这是把行数折进厚度而不是折进别处的**唯一理由**，也是这套设计最省的一步。
4. **`MultiLine = True` 时必须强制 `FShowScrollAffordance := False`、`FHeaderScroll := 0`、
   `FArrowBandPx := 0`。** 折行与滚动是互斥的：内容已经全部可见，再留一条箭头带
   等于凭空吃掉两端各 16px 并把行首页签推到箭头下面。LCL 也是这样（`MultiLine`
   打开时原生标签控件不给 `TCS_SCROLLOPPOSITE` 以外的滚动）。
5. **`RaggedRight = False` 的拉伸**要在**第三趟**做，而不是在折行时边折边拉：
   一行放几个只有折完才知道。第三趟按行重新分配：
   `extra := MainVisible - 行内总宽; 每个页签分 extra div n，前 extra mod n 个各多 1px`。
   **余数必须逐个发下去而不是丢掉**，否则最后一个页签与行尾之间会差几个像素，
   在有边框的皮肤下看得见。
6. `TabCaptionWidth` 每次调用 new 一个 `TBitmap`；折行让 `RebuildLayout` 的成本不变
   （还是每页签一次），但**第三趟不要重新测量**，只改 `Left/Right`。

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

---

## 5. 四个消费者各自要改什么（以及为什么大部分不用改）

| 消费者 | 改动 |
|---|---|
| **绘制** `RenderTo` | 不用改。`HeaderRectShifted` 已经把次轴坐标带出来了 |
| **命中** `IndexOfTabAt` / `MouseDown` / `MouseMove` | **要改**：现在扫的是 `HitMainSpan`（只比主轴），多行下必须比**两轴**。改成 `HitRect`。注意这在 `RowCount = 1` 时与 `HitMainSpan` **不等价**——单行时页签的次轴范围就是整条带，两者同解；但溢出滚动下页签会伸出控件外，所以**只在 `MultiLine` 打开时**换成两轴比较，或者干脆让 `HitMainSpan` 在多行时加上次轴条件 |
| **拖拽中点** `TyDropIndexAtPoint` | **要改**：一维的"第一个中点在指针之后"要变成**字典序**比较 `(行, 主轴中点)`。落点仍然是唯一一处比较，仍然用 `ToReadingMain` + 一个新的 `ToReadingCross`。`RowCount = 1` 时字典序退化成现在的规则，逐字节相同 |
| **滚动偏移** `HeaderShiftPx` | 不用改，因为多行下滚动被强制关掉（§3.4），`FHeaderScroll` 恒 0 |

**`ToReadingCross` 是这件事唯一要新增的变换成员**，而且它必须和 `ToReadingMain`
写在一起、用同一套逆序步骤，否则两个逆函数会各自漂移——那正是 §3.11 收口的那个毛病。

---

## 6. 测试要钉的点（每一条都先看它红）

1. `MultiLine = False`（默认）时 `RowCount = 1`、几何逐字节不变——**这条先写**。
2. 折行点：把控件宽度调到"第 3 个页签差 1px 放不下"，断言第 3 个在第 2 行、第 2 个仍在第 1 行。
   **探针对准边界，不要对准行中央。**
3. 一个宽过整条带的页签独占一行，且**不死循环**（超时即失败）。
4. `RaggedRight = False` 时每一行的最后一个页签**右边缘正好等于**条带边缘（余数逐个发）；
   `True` 时不等于。
5. `MultiLine` 打开后**溢出箭头消失**、`TyMaxHeaderScroll = 0`。
6. `AdjustClientRect` / `DisplayRect` 扣掉的是 **`RowCount × 行厚**，不是一行。
7. **绘制与命中在多行下仍然同源**：对每个页签，取它画出来的矩形，
   在四个角内 1px 处命中，必须命中它自己（现有 `PaintAndHitTestAgreeAtEveryPosition` 的多行版）。
8. **拖拽中点跟着绘制走**：跨**行**拖拽（从第 2 行拖到第 1 行）必须落在正确的槽位——
   这是多行下新增的那个静默失效面，一维的中点规则在这里会给出"最近的那个"而不是正确的那个。
9. `ScrollOpposite` 的行置换表：`RowDisplayOrder` 的纯函数单测，
   2/3/4 行 × 每个选中行 × 两个布尔值，**全枚举**。
10. 四个 `TabPosition` × `MultiLine` 的交叉：左/右条带的"多行"是多**列**，
    厚度同样是 `RowCount × 行厚`。

## 7. 变异测试建议

- 折行条件去掉 `(X > 0)` → 第 3 条必须超时/红。
- `RaggedRight` 的余数丢掉（`extra div n` 不发余数）→ 第 4 条必须红。
- `FBandThickness` 仍取一行厚 → 第 6、7 条必须红。
- 拖拽中点保持一维（不比较行）→ **第 8 条必须红**；这是本特性最该被钉住的一个。
- `MultiLine` 下不清 `FShowScrollAffordance` → 第 5 条必须红。
