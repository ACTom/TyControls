# TTyChart

## 概述

`TTyChart` 是折线 / 柱 / 饼图控件(`TTyGraphicControl`,BGRA `Canvas2D` 抗锯齿)。设计期可编辑系列、
自动 Y 轴量程 + 漂亮刻度 + 网格、图例、标题。**零新增主题 token**(`GetStyleTypeKey='TyPanel'`;
坐标轴/文字/网格走主题 surface/text/border;系列色用内置雅致调色板,可按系列覆盖)。

## 用法

```pascal
uses tyControls.Chart;

Chart := TTyChart.Create(Self);
Chart.Parent := Panel1;
Chart.Align := alClient;
Chart.ChartType := ctBar;
Chart.Title := '季度销量';
Chart.Categories.Text := 'Q1'#10'Q2'#10'Q3'#10'Q4';
with Chart.Series.Add do begin Name := '华东'; Values := '12, 19, 15, 22'; end;
with Chart.Series.Add do begin Name := '华南'; Values := '9, 14, 18, 16'; end;
```

## 属性

| 成员 | 说明 |
|---|---|
| `ChartType: (ctLine, ctBar, ctPie)` | 图表类型(v1 一图一类型)。默认 `ctLine`。 |
| `Series: TTyChartSeries` | 系列集合(设计期可编辑)。每项 `Name` / `Color`(`clDefault`=按调色板循环)/ `Values`(逗号分隔数值)。 |
| `Categories: TStrings` | X 轴分类(折线/柱)。 |
| `Title: string` | 标题。 |
| `ShowLegend` / `ShowGrid` / `ShowValues` | 图例 / 网格 / 数值标注。默认 True/True/False。 |

**类型语义**:折线/柱 = 多系列(每系列一条线 / 一组柱),Categories 作 X 轴;饼 = 第一个系列的各值为扇区。

## 关键设计

- **自动量程**:Y 轴用 Heckbert nice-numbers 把数据范围扩到漂亮边界(step ∈ {1,2,5}×10^k),含 0 基线;
  纯函数 `TyChartNiceRange` 无头测。
- **纯几何可无头测**:`TyChartNiceRange`(量程)、`TyChartValueToY`(值→像素)、`TyChartBarXRange`(柱分区,
  不重叠、在界内)、`TyChartPieSweeps`(返回 `TTyChartPieSlice(StartDeg,SweepDeg)` 记录数组,sweep 和=360、
  全零/负值安全)。绘制靠真机 + 无头渲染到位图不崩。
- 空数据 / 系列短于 Categories / max==min 都安全(不崩、不除零)。

**v1 不含**:tooltip / 交互 / 缩放 / 混合类型 / 次坐标轴。

## 关联

见 `docs/superpowers/plans/2026-07-12-phase9-finish.md`。装饰性矢量图元见 [TTyShape](shape.md)。
