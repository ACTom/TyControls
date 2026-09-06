# 两阶段轴构建 —— 实施计划（Tier 0 第 12 项）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 「估文字 → 收缩矩形 → 定尺寸」这一趟，做成 v6 的 `outerBounds` 形状而不是已弃用的 `containLabel`。它是标签适配的底座，坐标系拿到的绘图矩形是从这里出来的。

**基线：** 6419 个测试，0 错 0 败（`feat/advancechart` @ 6632532）。

---

## 1. 先查后做：第 15 项不用做

Tier 0 第 15 项写的是「文字度量缓存 + 折行/截断/省略号接到 `TyWrapTextCJK`」。**已经全在了**：

| 要的东西 | 现状 |
|---|---|
| 度量缓存 | `TyMeasureTextBlock` / `TyMeasureRenderedTextWidth` 双缓存，带完整的**失效性论证**（`Painter.pas` 里那段 12 条依赖枚举），主题变更时丢弃，且有守卫测试 |
| 上限 | **有**：`TY_TEXT_MEASURE_CACHE_MAX = 4096`，满了整表清空 |
| 折行接 CJK | `TyMeasureTextBlock` 收 `AWrapWidthPx`，走 `TyWrapTextCJK` |
| 省略号 | `TyEllipsisPrefix` |
| 无句柄 | 两个函数都自建临时位图，纯单元可直接调 |

原本担心「整表清空会抖动」——不会：图表一帧的工作集约 50-100 个串，4096 是它的 40 倍，清空成本摊薄在 4096 次未命中上。**第 15 项标记为无需工作。**

## 2. 必须吸收的一个既有事实

`Painter.pas` 的注释写明：`TyMeasureTextBlock`（LCL canvas）与 `TyMeasureRenderedTextWidth`（BGRA 渲染器）**是两个光栅器，会差一个像素**——同一台机器上 "Open" 都是 32，"New" 一个 26 一个 27。而且原话：

> 任何**尺寸下限会喂给裁剪**的控件，必须取两者较大值。

轴标签正是这种情况：我们按度量结果预留空间，文字最终由 BGRA 画。所以度量器取 `Max(canvasW, rendererW)`。

## 3. 设计决策

### 3.1 度量走接口注入，不让布局层依赖 Painter

Tier 0 spec §3 原本写 `AdvChart.Layout` 依赖 `Painter`（量文字）。**改掉**，理由两条：

1. 那会让 Layout 拉进 `Controls`/`Graphics`/`LCLType`，把已经建立的「前几个单元纯」的性质破掉；
2. 更重要的是**可测性**。用真字体测轴布局是脆的——字体因机器和 widgetset 而异（仓库记忆 `headless-tests-never-run-lcl-align`）。注入一个**确定性的假度量器**，算法本身就能被精确断言；真度量器另外单独验。

```pascal
  { 一行文字的未旋转 ink 尺寸，设备 px。 }
  ITyTextMeasurer = interface
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
  end;
```

放 `AdvChart.Types`（纯）。Painter 支撑的实现放 `tyControls.AdvChart.Measure.pas`（**唯一**允许碰 Painter 的桥接单元）。

### 3.2 不用 LCL 的对齐枚举

`TAlignment` / `TTextLayout` 来自 `Classes`/`Graphics`。纯单元里自定义 `TTyTextAnchorH` / `TTyTextAnchorV`，桥接单元负责转换。

### 3.3 两阶段**不迭代**，这是有意的

估算阶段算出的厚度 = 垂直于轴方向上标签的最大延伸。收缩后轴变短，可能需要**更多**抽稀——但抽稀改变的是标签**数量**，不是单个标签的尺寸，所以厚度不变。唯一的偏差是「最宽的那个标签恰好被抽掉了」，ECharts 也不管这个。单趟，不迭代，注释里写明。

### 3.4 抽稀用**均匀 k**，不用贪心

`axisLabel.interval: 'auto'` 的语义是均匀间隔。贪心「不重叠就留」会得到疏密不均的刻度，在分类轴上很难看。算法：求最小的 k ≥ 1，使得每隔 k 个显示时相邻两个不重叠。

旋转标签沿轴方向的延伸：
- 横轴：`|w·cos θ| + |h·sin θ|`
- 纵轴：`|w·sin θ| + |h·cos θ|`

### 3.5 `outerBounds` 形状，不是 `containLabel`

- `obmNone` —— 给的框**就是**绘图区，标签允许溢出到框外（v5 默认，`containLabel:false`）。
- `obmAuto` —— 给的框是**外边界**，收缩绘图区让标签落在框内（v6 默认，≈ `containLabel:true`）。

`TTyOuterBoundsContain`：`obcAxisLabel`（只算标签）/ `obcAll`（标签 + 轴名）。

**不做（记在这里）**：`nameMoveOverlap`（轴名与末端标签冲突时的挪让）。它是 v6 新增的独立特性，不是两阶段本身的一部分。

---

## 4. 测试规格

新文件 `tests/test.advchart.axis.pas`，用**假度量器**（每字符固定宽、固定高），因此断言可以是精确数值。

| 要钉住的 | 测试 |
|---|---|
| obmNone 不收缩 | 绘图区 == 容器 |
| obmAuto 按标签宽收缩左侧 | 左边距 == 最宽标签 + tick + margin |
| 厚度取**最大**标签不是最后一个 | 把最宽的放中间 |
| 轴名只在 obcAll 计入 | 同一 spec 两种 contain，厚度差 == 名字尺寸 + gap |
| 旋转 45° 的横轴标签变高 | 厚度大于未旋转 |
| 旋转 90° 的横轴标签厚度 == 标签**宽** | 精确值 |
| 抽稀是均匀 k | 显示的下标是 0,k,2k… |
| 不重叠时 k==1 | 全显示 |
| 挤到极限时至少留 1 个 | 不会一个都不显示 |
| 标签锚点落在刻度上 | 底轴第 i 个标签的 X == plot.Left + pos*width |
| 底轴锚点在绘图区**下方** | Y > plot.Bottom |
| 左轴标签右对齐、垂直居中 | 锚点枚举 |
| 两阶段单趟 | 收缩后不再改厚度（回归守卫） |
| 真度量器取两条路径的较大值 | 桥接单元单独测 |

## 5. 完成判据

1. 全量 ≥ 6419 + 新增，0 错 0 败；
2. `AdvChart.Layout` 仍然只 uses `SysUtils`/`Math`/`AdvChart.*`——纯度不破；
3. 变异测试：§4 每一行至少一个变异被杀；变异脚本先跑 canary。
