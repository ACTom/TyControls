# TTyPainter 矢量 API —— 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `TTyPainter` 加一套完整的矢量绘制 API，使 `TTyAdvanceChart` 的 series 渲染器不必绕过它去抓 `Bitmap.Canvas2D`。

**Architecture:** 直接扩展 `source/tyControls.Painter.pas` 里的 `TTyPainter`（不新开单元，理由见 §1）。所有方法委托给 `FBmp.Canvas2D`，但对外只暴露本仓库的类型（`TTyColor` / `TTyFill` / 逻辑像素），并接管 DPI 缩放与主题取色。

**Tech Stack:** Free Pascal 3.2.2 / BGRABitmap 的 `TBGRACanvas2D`。测试沿用 `tests/test.painter.pas` 已有的 headless 模式（`TBitmap` + `BeginPaint` + `Bitmap.GetPixel`）。

**基线：** 6390 个测试，0 错 0 败（`feat/advancechart` @ c1e36cc）。

> **计划体例说明：** 本计划与实现在同一会话内连续执行，故实现体不在计划里重复抄一遍（那会是纯复制）。计划锁定的是**设计决策、API 契约、测试规格与已核实的外部事实**——也就是需要判断的部分；实现体见代码及其单元头注释。

---

## 1. 已核实的事实与由此定下的决策

| # | 事实（已核对源码） | 决策 |
|---|---|---|
| 1 | `Grid.pas` **15724 行**、`TreeView.pas` 8159 行 | 加约 700 行到 `Painter.pas`（2327 → ~3000）**完全在本仓库常规内**。不新开单元 |
| 2 | `TTyPainter.Bitmap` 是 public，`Canvas2D` **按位图缓存**（`bgradefaultbitmap.pas:3865`），状态跨调用保留 | `SaveState`/`RestoreState` 直接映射 `ctx.save`/`restore`（`bgracanvas2d.pas` 里它 Duplicate 整个 `TBGRACanvasState2D`，含 matrix 与 clipMask）。**但绝不能假设进入时状态干净**——每个绘制入口必须显式设置它用到的每一项 |
| 3 | `TTyPainter.Scale` 是 `MulDiv(ALogical, FPPI, 96)`，**取整** | 线宽/虚线/半径新增 `ScaleF: Double`，**不取整**。150% 下 1px 轴线必须是 1.5 而不是 2 |
| 4 | `IBGRACanvasGradient2D` 派生自 `IBGRACanvasTextureProvider2D`（`bgracanvas2d.pas:41`） | `ctx.fillStyle(grad)` 直接可编译，渐变是一等填充 |
| 5 | `TFillMode = Graphics.TFillMode`（`fmAlternate`/`fmWinding`） | `TTyFillRule = (tfrNonZero, tfrEvenOdd)` 映射到 `fmWinding`/`fmAlternate` |
| 6 | `TPenEndCap`(`pecRound`/`pecSquare`/`pecFlat`)、`TPenJoinStyle`(`pjsRound`/`pjsBevel`/`pjsMiter`) 来自 LCL | 用 `lineCapLCL`/`lineJoinLCL` 而不是字符串版，避免拼写错误静默失效 |
| 7 | `addPath(ASvgPath: string)` 收全套 `M L H V C S Q T A Z` 含椭圆弧（`bgrapath.pas:2301,2400`） | `path://` 不需要自写解析器 |
| 8 | `TextOutAngle(x, y: single; orientationTenthDegCCW: Integer; ...)`，**十分之一度、逆时针**，Menu.pas:1351 已在用 | 旋转文字走它而不是 `ctx.fillText`，以复用 `TyConfigureTextFont` 那一整套字体级联与回退 |
| 9 | `GradientEndpoints` 是 private，`TyColorToBGRA` 是单元级函数 | 都在类内可直接调用，`TTyFill` 的角度渐变不用重写 |
| 10 | `TTyPainter.Opacity` 是**整帧**变暗，在 `EndPaint` 里 `ApplyGlobalOpacity` | 逐元素 alpha 用 `ctx.globalAlpha`，与 `Opacity` **正交**，两者可叠加 |

**坐标单位约定**（沿用既有 painter 的做法，并写进单元注释）：
- **路径坐标 = 设备 px、Double**。几何层（`AdvChart.Coord`）已经把值换算成设备像素了，再让画家缩放一次就是错的。
- **线宽 / 虚线段长 / 圆角半径 = 逻辑 px、Double**，由 `ScaleF` 换算。它们来自主题令牌，令牌是逻辑单位。

---

## 2. API 契约

```pascal
type
  TTyFillRule = (tfrNonZero, tfrEvenOdd);
  TTyLineCap  = (tlcButt, tlcRound, tlcSquare);
  TTyLineJoin = (tljMiter, tljRound, tljBevel);
  TTyVecPoint = record X, Y: Double; end;
  TTyDashPattern = array of Double;      // 逻辑 px，on/off 交替；空 = 实线
```

`TTyPainter` 新增（分五组）：

**① 路径构建**（坐标设备 px）
`BeginPath` · `ClosePath` · `MoveTo` · `LineTo` · `CurveTo`(三次) · `QuadTo`(二次) ·
`ArcTo(cx,cy,r,startRad,endRad,anticlockwise)` · `PolylineTo(const array of TTyVecPoint)` ·
`RectPath` · `RoundRectPath(...,ARadiusLogical)` · `EllipsePath` · `CirclePath` ·
`SvgPath(APathData)` · `SvgPathIn(APathData, ARect, AKeepAspect)`

**② 绘制当前路径**
`FillPath(AColor, ARule)` · `FillPathWith(const AFill: TTyFill; const ABounds: TRect; ARule)` ·
`StrokePath(AColor, AWidthLogical)` · `FillAndStrokePath(...)` · `PathContains(AX, AY): Boolean`

**③ 描边状态**
`SetLineDash(const APatternLogical: array of Double)` · `SetLineCap` · `SetLineJoin(AJoin, AMiterLimit)`

**④ 状态栈 / 变换 / 裁剪 / 逐元素 alpha**
`SaveState` · `RestoreState` · `Translate` · `RotateBy(AAngleRad)` · `ScaleBy(ASX, ASY)` ·
`ResetTransform` · `ClipPath(ARule)` · `ClipRect(const ARect: TRect)` · `SetElementAlpha(0..1)`

**⑤ 旋转文字**
`DrawTextRotated(AText, AFontName, AFontSizeLogical, AWeight, AColor, AX, AY, AAngleRad, AHAlign, AVAlign)`

**新增辅助**：`ScaleF(ALogical: Double): Double`（public——series 渲染器也要它）。

---

## 3. 契约里那些「必须是这个而不是那个」的点

这些是测试真正要钉住的东西，不是 API 形状。

1. **`ClipRect` 必须走路径 + clip，不能直接改一个矩形裁剪域。** 否则在有旋转的 CTM 下裁剪框不跟着转，画出来的东西会被一个**没有转**的矩形切掉。
2. **`RestoreState` 必须同时还原变换、裁剪、描边状态和 alpha。** 少还原任何一项，都会在下一个 series 上表现成「上一个 series 的样式漏过来了」。
3. **`tfrEvenOdd` 与 `tfrNonZero` 在自交路径上必须给出不同结果。** 环形（外圈顺时针 + 内圈顺时针）用 even-odd 才有洞——饼图的甜甜圈、sunburst 的每一环都靠它。
4. **`PathContains` 必须尊重当前变换。** 命中检测与绘制走同一条路径是 TTySegmented 那条规矩；变换只作用于绘制而不作用于命中，就是让两者漂移。
5. **虚线长度是逻辑 px。** 一条 `[4,4]` 的虚线在 150% 下必须是 6 设备 px 的段，否则高 DPI 上虚线会碎成点。
6. **`SetElementAlpha` 与 `Opacity` 正交。**
7. **零宽/负宽描边必须什么都不画**，而不是画一条 BGRA 默认宽度的线。
8. **`DrawTextRotated` 逆时针为正，0 弧度必须与 `DrawText` 同位置，2π 必须与 0 同位置。**

---

## 4. 任务

| # | 内容 | 测试类 |
|---|---|---|
| 1 | `ScaleF` + 类型 + 路径构建 + `FillPath`/`StrokePath` 骨架 | `TPainterVectorTest` |
| 2 | 填充规则（even-odd 的洞）、`FillPathWith`（TTyFill 渐变）、`PathContains` | 同上 |
| 3 | 描边状态：宽度（含零宽）、虚线（逻辑 px）、cap、join | 同上 |
| 4 | 状态栈、变换、裁剪、逐元素 alpha | 同上 |
| 5 | `SvgPath` / `SvgPathIn`（`path://` 符号） | 同上 |
| 6 | `DrawTextRotated` | 同上 |
| 7 | 全量回归 + 变异测试（≥8 个，先跑 canary 验脚本） | — |

测试文件：`tests/test.painter.vector.pas`，挂进 `tests/tytests.lpr`。
**不改 `tests/test.painter.pas`**——既有 28 个测试必须原样全绿，这是「没碰坏老路径」的判据。

---

## 5. 完成判据

1. `test.painter.pas` 的 28 个测试**零改动**且全绿；
2. 新测试全绿，全量套件 ≥ 6390 + 新增数，0 错 0 败；
3. §3 那 8 条每条至少有一个测试钉住；
4. 变异测试：针对 §3 的每一条各造一个变异，**全部被杀**；变异脚本先用 canary 自验；
5. `grep -n "Canvas2D" source/tyControls.AdvChart.*.pas` 为空——矢量 API 落地后，图表层不再需要直接碰 Canvas2D（本 spike 阶段图表层还没有渲染器，此条留待 Tier 1 复查）。
