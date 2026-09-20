# 让控件的 `Font` 成为单实例覆盖通道 —— 需求（已拍板，待设计）

> 状态：**需求已由用户拍板，尚未做设计**（没有 spec、没有计划）· 目标分支：`feat/3.1`
> 来源：3.0 修复会话 2026-09-20 转交；用户在那边拍的板，含他补充的「两级开关」

现状是 `Font` 挂在三十多个控件上、却几乎不生效——一个会撒谎的 published 属性。
本需求把它变成**单个控件的覆盖通道**：`.lfm` 里写了哪个字段，哪个字段就生效。

设计阶段从这份需求出发，先走 brainstorming，再写 spec，再拆计划。

---

## 现状（转交方已核实的事实）

- 库的约定是「主题锁定」：字体族 / 字号 / 字重 / 颜色都来自主题。`Font` 对象保留下来，是因为 `Font.PixelsPerInch` 是全库的 DPI 来源（464 处）。
- 已经有一条显式通道 `TyResolveFontSize`（`source/tyControls.Base.pas:1807`）：
  主题 typeKey 的 font-size > 显式 `Font.Size`（`ParentFont=False`）> `--font-size-base` > 继承 / 9。`tests/test.fontcascade.pas` 钉着它。
- **问题**：内置主题给每个 typeKey 都写了 font-size，第一级永远命中，显式 Font 事实上够不着。
- `Font.Name` 只有 9 处直接读：Chart / Dial / GearDial / Gauge / Meter / LevelMeter / CircularProgress / Dialogs / Dialogs.About。
- `Font.Style` / `Font.Color` 没有任何控件读。

## 用户拍板的规则

1. **一级开关 `ParentFont`**：True（默认，对象查看器没碰过）→ 完全主题驱动，行为逐字节不变（含 `TestSkinFontSizeMatchesDefault` 那类守卫）。
2. **二级开关：逐字段与 `TFont` 出厂值比较**，等于出厂值的字段不应用。出厂值就是 LCL 的未设哨兵：
   `Name = 'default'`、`Height = 0`（Size 0）、`Style = []`、`Color = clDefault`（LCL 未定义 `UseCLDefault` 时是 `clWindowText`，两者都当未设；`lcl/include/font.inc:624`、`graphics.pp:117 DefFontData`）。
   这恰好是 `.lfm` 的存储粒度（TFont 只存非出厂字段），所以规则一句话讲得清：**lfm 里 Font 下写了哪个字段，哪个字段就生效**。
   参照物**用出厂值，不用父控件当前字体**——后者会在父字体后来改动时让子控件悄悄变回主题，不稳定。
3. **映射**：
   - `Name` → font-family
   - `Size` → font-size（逻辑 pt，走现有 MulDiv PPI 路径）
   - `fsBold in Style` → font-weight 700（**只映射「有 bold」**，不映射「没 bold」：分不清「用户去掉了」和「从来没有」）
   - 斜体：主题引擎没有 font-style，**不映射**，写进文档
   - `Color` → color，**对所有状态生效**（hover / active / disabled 的墨色一并盖掉），与 StyleOverride 的 `color` 同一语义
4. **优先级**：控件自己的 `StyleOverride` > 显式 Font 字段 > 主题 typeKey > `--font-size-base`。
   StyleOverride 压过 Font 可实现：控件已持有解析后的 override（`FOvrCache`，`Base.pas:~1790`），看它的 `Present` 里有没有 `tpFontSize` / `tpFontName` / `tpFontWeight` / `tpColor`。
5. **收口**：全库绘制站点统一走一个 helper（建议 `TyResolveTextStyle` 返回 name / size / weight / color 的 record，或四个并列函数）；
   把那 9 处直接读 `Font.Name` 的删掉；`TTyEdit.EffectiveFontSize` / `TTyMemo.EffectiveFontSize` / `TTyLabel.ResolveFontSize` 这些副本并进去（`test.fontcascade` 的注释说了它们的来历）。
6. **DPI 前提已满足**：`TTyGraphicControl` / `TTyCustomControl.ScaleFontsPPI` 的守卫让未设的 `Height` 跨屏保持 0（`docs/superpowers/plans/2026-08-08-permonitor-dpi.md` §5），二级开关靠这个才成立。
   `TTyForm` 自身没这个守卫（§5d），但窗体不是绘制控件，与本特性无关。
7. **测试**：
   - `TestSharedHelperPriority` 第 1 条改成「显式优先」
   - 新增：`ParentFont=True` 时非出厂字段也被忽略；`ParentFont=False` 时只应用非出厂字段（`Name='default'` **绝不能**被当字体名传给 BGRA、`Color=clDefault` 不映射）；StyleOverride 压过 Font；粗体映射 700、去粗不映射
   - 变异判据至少三条：去掉二级开关 → `Name='default'` 被当字体名（渲染字体名断言红）；去掉一级开关 → 继承了大字体的控件字号红（复用 `TestControlRecoversBaseFontUnderSkin` 的夹具）；优先级翻回去 → 显式 14 被主题 9 压掉红
8. **文档**：`tycss-reference.md` 的主题锁定段、十几个控件 md 里「不读 LCL Font」的句子，改成「`ParentFont=False` 时按字段生效」；`popover.md` 那种非可视组件没有 Font 的说明不变。
9. **changelog 要写的行为变化**：以前在对象查看器里改过 Font、又不指望它生效的窗体，升级后就生效了。

## 用户已否决（不做）

- **隐藏 `Font`**：三十多个控件 published，去掉是 `.lfm` 破坏性变更。
- **自动把 Font 同步成 StyleOverride 字符串**：双真相源。

## 排期

排在 IDE 工作台（侧栏 / 底栏）之后。工作台的 spec 是 `2026-09-17-toolwindow-workbench-design.md`，
计划分 A–D 四期，A 期计划 `docs/superpowers/plans/2026-09-20-toolwindow-phase-a.md` 正在执行。
