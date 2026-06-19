# Button Ghost 变体 + 选中态 + 角标 + 动态 StyleClass 编辑器 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 `TTyButton` 增加 VS Code 风格的透明(ghost)变体 + 常驻选中态、数字角标(badge),并把设计期 StyleClass 下拉改为按控件类型从主题动态读取。

**Architecture:** CSS 引擎新增一个 `:selected` 伪状态(`tysSelected`);选中态由 `TTyButton.Down` 驱动并注入 `CurrentStates`。ghost 是纯主题层变体(`TyButton.ghost`,透明底用 `alpha(...,0)` 以复用现有 alpha 淡入动画)。角标沿用既有"独立 typeKey 子元素"模式(`TyBadge`),由按钮在 `RenderTo` 末尾按角内嵌绘制;显示策略经 `OnBadgeDisplay` 事件可改写。设计期下拉读控件的 controller model 动态枚举该 typeKey 的 variant。所有可见值均主题令牌驱动,无硬编码。

**Tech Stack:** Free Pascal / Lazarus LCL,BGRABitmap 绘制,fpcunit 测试,`.tycss` 主题 + 生成的 `DefaultTheme.pas`。

**Spec:** `docs/superpowers/specs/2026-06-19-tycontrols-button-ghost-badge-design.md`

---

## Phase 0：分支与前置(菜单 session 合并后再开始)

- [ ] **Step 0.1:** 确认菜单 session 已合并入 `main`(或目标集成分支)。`git fetch && git status` 工作树干净。
- [ ] **Step 0.2:** 从最新集成分支建专用分支:`git switch main && git pull && git switch -c feat/button-ghost-badge`(如需隔离可用 superpowers:using-git-worktrees 建 worktree)。
- [ ] **Step 0.3:** 基线全绿:`lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`。Expected:`Number of errors: 0` 且 `Number of failures: 0`。Windows 下二进制为 `tests/tytests.exe`;Git Bash 里 `./tests/tytests` 可直接运行。

> 全程的统一测试命令:`lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`。下文凡"运行测试套件"均指此命令(本仓库无单 suite 过滤约定,跑全量并在输出里核对相关断言)。

---

## Phase A：引擎 — 新增 `:selected` 状态

### Task 1：`tysSelected` 枚举值 + parser 伪类映射

**Files:**
- Modify: `source/tyControls.Types.pas`(`TTyState` 枚举)
- Modify: `source/tyControls.Css.Parser.pas`(`PseudoToState`)
- Test: `tests/test.Css.Parser.pas`(新增一个 published 方法)

- [ ] **Step 1.1: 写失败测试** — 在 `tests/test.Css.Parser.pas` 的 `TTestCase` 类(文件内已有的解析测试类)`published` 段加方法声明 `procedure TestSelectedPseudoState;`,并在 implementation 段加:

```pascal
procedure TTestCssParser.TestSelectedPseudoState;
var
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  rule: TTyCssRule;
begin
  // ':selected' 与别名 ':checked' 都应解析为 tysSelected
  parser := TTyCssParser.Create('TyButton.ghost:selected { background:#FF0000; }');
  try
    sheet := parser.Parse;
    try
      AssertEquals('one rule', 1, sheet.Rules.Count);
      rule := TTyCssRule(sheet.Rules[0]);
      AssertTrue('has state', rule.Selectors[0].HasState);
      AssertTrue('state is tysSelected', rule.Selectors[0].State = tysSelected);
    finally sheet.Free; end;
  finally parser.Free; end;

  parser := TTyCssParser.Create('TyButton:checked { background:#00FF00; }');
  try
    sheet := parser.Parse;
    try
      rule := TTyCssRule(sheet.Rules[0]);
      AssertTrue('checked alias -> tysSelected', rule.Selectors[0].State = tysSelected);
    finally sheet.Free; end;
  finally parser.Free; end;
end;
```

> 测试类是 `TTestCssParser`(`tests/test.Css.Parser.pas`,`uses` 已含 `tyControls.Types`、`tyControls.Css.Parser`)。把声明加进它的 `published` 段。

- [ ] **Step 1.2: 运行,确认编译失败(红)** — 运行测试套件。Expected:**编译失败**,`tytests.lpr` 报 `tysSelected` 标识符未定义。这确认测试指向尚不存在的枚举值。

- [ ] **Step 1.3: 加枚举值** — `source/tyControls.Types.pas`,把:

```pascal
  TTyState = (tysNormal, tysHover, tysActive, tysFocused, tysDisabled);
```

改为(**末尾追加**,保持现有序号不变):

```pascal
  TTyState = (tysNormal, tysHover, tysActive, tysFocused, tysDisabled, tysSelected);
```

- [ ] **Step 1.4: 加伪类映射** — `source/tyControls.Css.Parser.pas` 的 `PseudoToState`,在 `else if n = 'disabled' then ...` 之后、`else begin Error(...) end` 之前插入:

```pascal
  else if (n = 'selected') or (n = 'checked') then
    Result := tysSelected
```

- [ ] **Step 1.5: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestSelectedPseudoState` 通过;`Number of failures: 0`。

- [ ] **Step 1.6: 提交**

```bash
git add source/tyControls.Types.pas source/tyControls.Css.Parser.pas tests/test.Css.Parser.pas
git commit -m "feat(tycontrols): add :selected/:checked pseudo-state (tysSelected)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2：级联顺序 — `cStateOrder` 纳入 `tysSelected`(最先应用)

**Files:**
- Modify: `source/tyControls.StyleModel.pas`(`ResolveLayer` 的 `cStateOrder`)
- Test: `tests/test.StyleModel.pas`(新增 published 方法)

- [ ] **Step 2.1: 写失败测试** — 在 `tests/test.StyleModel.pas` 的 `TTestStyleResolve`(已注册)`published` 段加 `procedure TestSelectedStateCascade;`,implementation 段加:

```pascal
procedure TTestStyleResolve.TestSelectedStateCascade;
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  // selected 作为常驻底层,hover 应能逐属性覆盖其 background,但保留 selected 独有的 border-color
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(
      'TyButton.ghost { background:#000000; }' + LineEnding +
      'TyButton.ghost:selected { background:#111111; border-color:#FF0000; }' + LineEnding +
      'TyButton.ghost:hover { background:#222222; }');
    // 仅 selected
    s := m.ResolveStyle('TyButton', 'ghost', [tysSelected]);
    AssertEquals('selected bg', $11, TyRedOf(s.Background.Color));
    AssertEquals('selected border R', $FF, TyRedOf(s.BorderColor));
    // selected + hover:hover 覆盖 background,selected 的 border-color 保留
    s := m.ResolveStyle('TyButton', 'ghost', [tysSelected, tysHover]);
    AssertEquals('hover overrides bg', $22, TyRedOf(s.Background.Color));
    AssertEquals('selected border survives', $FF, TyRedOf(s.BorderColor));
  finally m.Free; end;
end;
```

- [ ] **Step 2.2: 运行,确认失败(红)** — 运行测试套件。Expected:`selected + hover` 子断言失败——当前 `cStateOrder` 不含 `tysSelected`,故 `:selected` 规则根本未被应用(border-color 缺失)。

- [ ] **Step 2.3: 扩展 cStateOrder** — `source/tyControls.StyleModel.pas` 的 `ResolveLayer`,把:

```pascal
  cStateOrder: array[0..3] of TTyState = (tysHover, tysFocused, tysActive, tysDisabled);
```

改为(selected 放最前——常驻底层,hover/active 后应用可覆盖):

```pascal
  cStateOrder: array[0..4] of TTyState = (tysSelected, tysHover, tysFocused, tysActive, tysDisabled);
```

- [ ] **Step 2.4: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestSelectedStateCascade` 通过;无回归失败。

- [ ] **Step 2.5: 提交**

```bash
git add source/tyControls.StyleModel.pas tests/test.StyleModel.pas
git commit -m "feat(tycontrols): apply :selected state first in the cascade order

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase B：主题令牌(light + 内置)

### Task 3：light.tycss 增加 `TyButton.ghost` + `TyBadge`,重生成 DefaultTheme

**Files:**
- Modify: `themes/light.tycss`
- Regenerate: `source/tyControls.DefaultTheme.pas`(由脚本生成,勿手改)
- Test: `tests/test.defaulttheme.pas`(新增 published 方法)

- [ ] **Step 3.1: 写失败测试** — 在 `tests/test.defaulttheme.pas` 的 `TBuiltinThemeTest` `published` 段加 `procedure TestGhostAndBadge;`,implementation 段加:

```pascal
procedure TBuiltinThemeTest.TestGhostAndBadge;
var m: TTyStyleModel; g, gh, b: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    // ghost 基态:透明纯色底(alpha=0),但仍是 solid
    g := m.ResolveStyle('TyButton', 'ghost', []);
    AssertTrue('ghost has background', tpBackground in g.Present);
    AssertTrue('ghost base is solid', g.Background.Kind = tfkSolid);
    AssertTrue('ghost base transparent (alpha 0)', TyAlphaOf(g.Background.Color) = 0);
    // ghost hover:不透明底 + 边框
    gh := m.ResolveStyle('TyButton', 'ghost', [tysHover]);
    AssertTrue('ghost hover background present', tpBackground in gh.Present);
    AssertTrue('ghost hover bg opaque-ish', TyAlphaOf(gh.Background.Color) > 200);
    // ghost selected:有边框色
    gh := m.ResolveStyle('TyButton', 'ghost', [tysSelected]);
    AssertTrue('ghost selected sets border-color', tpBorderColor in gh.Present);
    // TyBadge:有背景与文字色
    b := m.ResolveStyle('TyBadge', '', []);
    AssertTrue('badge has background', tpBackground in b.Present);
    AssertTrue('badge has text color', tpTextColor in b.Present);
  finally m.Free; end;
end;
```

- [ ] **Step 3.2: 运行,确认失败(红)** — 运行测试套件。Expected:`TestGhostAndBadge` 失败(ghost/TyBadge 规则尚不存在),且 `TestBuiltinMatchesLightTheme` 仍通过。

- [ ] **Step 3.3: 在 light.tycss 增加 ghost 变体** — 打开 `themes/light.tycss`,在 `TyButton.danger:active { ... }` 行之后(按钮规则块末尾)追加:

```css
TyButton.ghost {
  background: alpha(var(--surface-hover), 0);
  color: var(--on-surface);
  border-color: alpha(var(--border), 0);
  border-width: var(--input-border-width);
  border-radius: var(--radius);
  padding: 6px;
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-normal);
}
TyButton.ghost:hover    { background: var(--surface-hover); border-color: var(--input-border-hover); }
TyButton.ghost:active   { background: var(--surface-active); }
TyButton.ghost:selected { background: var(--surface-active); border-color: var(--accent); }
TyButton.ghost:focus    { outline: 2px var(--focus-ring); }
TyButton.ghost:disabled { opacity: var(--disabled-opacity); }
```

- [ ] **Step 3.4: 在 light.tycss 增加 TyBadge** — 在 `TyToggleKnob { ... }` 行附近(其它子元素 typeKey 旁,文件末尾区)追加:

```css
TyBadge {
  background: var(--accent);
  color: var(--on-accent);
  border-radius: var(--radius-round);
  font-size: var(--font-size-base);
  font-weight: var(--font-weight-bold);
  padding: 0px 4px;
}
```

- [ ] **Step 3.5: 重生成内置主题** — 仓库根目录运行:`powershell -File gen-defaulttheme.ps1`。Expected:输出 `Regenerated DefaultTheme.pas from light.tycss (N content lines)`;`source/tyControls.DefaultTheme.pas` 已更新。**不要手改该文件。**

- [ ] **Step 3.6: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestGhostAndBadge` 通过;`TestBuiltinMatchesLightTheme` 仍通过(已重生成,字节同步);无回归。

- [ ] **Step 3.7: 提交**

```bash
git add themes/light.tycss source/tyControls.DefaultTheme.pas tests/test.defaulttheme.pas
git commit -m "feat(tycontrols): add TyButton.ghost variant + TyBadge tokens to light/default theme

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase C：按钮选中态(Down)

### Task 4：`TTyButton.Down` 属性 + `CurrentStates` override

**Files:**
- Modify: `source/tyControls.Button.pas`
- Test: `tests/test.button.pas`(扩展 `TTyButtonAccess` + 新增 published 方法)

- [ ] **Step 4.1: 暴露 protected `CurrentStates` 给测试** — `tests/test.button.pas` 的 `TTyButtonAccess` 类加方法。声明段加:

```pascal
    function States: TTyStateSet;
```

implementation 段加:

```pascal
function TTyButtonAccess.States: TTyStateSet;
begin
  Result := CurrentStates;
end;
```

并确保单元 `uses` 含 `tyControls.Types`(`TTyStateSet`/`tysSelected`);如缺则加入。

- [ ] **Step 4.2: 写失败测试** — `TButtonTest` `published` 段加 `procedure TestDownDrivesSelectedState;`,implementation 段加:

```pascal
procedure TButtonTest.TestDownDrivesSelectedState;
var B: TTyButtonAccess;
begin
  B := TTyButtonAccess.Create(nil);
  try
    AssertFalse('Down default False', B.Down);
    AssertFalse('not selected initially', tysSelected in B.States);
    B.Down := True;
    AssertTrue('Down adds tysSelected', tysSelected in B.States);
    AssertFalse('selected excludes normal', tysNormal in B.States);
    // disabled 优先:Down 不叠加
    B.Enabled := False;
    AssertFalse('disabled drops selected', tysSelected in B.States);
    AssertTrue('disabled present', tysDisabled in B.States);
    AssertTrue('Down is published', IsPublishedProp(B, 'Down'));
  finally B.Free; end;
end;
```

- [ ] **Step 4.3: 运行,确认编译失败(红)** — 运行测试套件。Expected:编译失败,`Down` 未定义。

- [ ] **Step 4.4: 加 Down 字段/属性/setter + CurrentStates override** — `source/tyControls.Button.pas`:

private 段加:

```pascal
    FDown: Boolean;
    procedure SetDown(AValue: Boolean);
```

protected 段加:

```pascal
    function CurrentStates: TTyStateSet; override;
```

published 段加(放在 `Default`/`Cancel` 附近):

```pascal
    // VS Code 风格常驻选中态:为 True 时 CurrentStates 注入 tysSelected,触发
    // 主题里的 ':selected' 规则(如 TyButton.ghost:selected)。互斥分组由应用层在
    // OnClick 里自行切换各按钮的 Down(本期不内建 GroupIndex)。
    property Down: Boolean read FDown write SetDown default False;
```

implementation 段加:

```pascal
procedure TTyButton.SetDown(AValue: Boolean);
begin
  if FDown = AValue then Exit;
  FDown := AValue;
  Invalidate;
end;

function TTyButton.CurrentStates: TTyStateSet;
begin
  Result := inherited CurrentStates;   // hover/active/focused/disabled, 或 normal
  // Enabled=False 时 inherited 已只返回 [tysDisabled];disabled 优先,不叠加 selected。
  if FDown and Enabled then
  begin
    Include(Result, tysSelected);
    Exclude(Result, tysNormal);
  end;
end;
```

- [ ] **Step 4.5: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestDownDrivesSelectedState` 通过;无回归(现有按钮像素/动画测试不受影响——未设 Down 时行为不变)。

- [ ] **Step 4.6: 提交**

```bash
git add source/tyControls.Button.pas tests/test.button.pas
git commit -m "feat(tycontrols): add TTyButton.Down toggle driving the :selected state

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase D：动画取色修正(选中态下的 hover 淡入)

### Task 5：hover 淡入按"当前态 ± hover"取色

**Files:**
- Modify: `source/tyControls.Button.pas`(`RenderTo` 的混色段)
- Test: `tests/test.button.pas`(新增 published 方法)

> 背景:现有 `RenderTo` 固定解析 `[tysNormal]`/`[tysHover]` 混色,对选中的 ghost 按钮会从错误底色起步。改为以 `CurrentStates`(去/加 hover)两端取色。对非选中按钮结果不变(`CurrentStates - [tysHover]` 即 `[tysNormal]`),既有像素测试不破。

- [ ] **Step 5.1: 写测试(行为不变回归 + 选中态取色)** — `TButtonTest` `published` 段加 `procedure TestHoverBlendUsesRestingState;`,implementation 段加:

```pascal
procedure TButtonTest.TestHoverBlendUsesRestingState;
var
  B: TTyButtonAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  // 选中的 ghost 按钮、无 hover、动画静止(headless 句柄未分配=瞬时吸附):
  // 底色应为 ghost:selected 的 surface-active(可见、非透明),而不是 normal 的透明。
  Bmp := TBitmap.Create;
  B := TTyButtonAccess.Create(nil);
  try
    B.StyleClass := 'ghost';
    B.Down := True;
    B.Caption := '';
    B.Font.PixelsPerInch := 96;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(80, 28);
    Bmp.Canvas.Brush.Color := TColor($FF00FF);   // 品红背景:未绘制可检出
    Bmp.Canvas.FillRect(0, 0, 80, 28);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 80, 28), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(40, 14);
      // surface-active = darken(#FFFFFF,10%) ≈ #E6E6E6:非品红、非透明
      AssertTrue('selected ghost painted (not magenta backdrop): R<>255 or G<>0',
        not ((Px.red = 255) and (Px.green = 0) and (Px.blue = 255)));
      AssertTrue('selected ghost bg is light surface-active', Px.green > 180);
    finally Reread.Free; end;
  finally B.Free; Bmp.Free; end;
end;
```

> 需要 `tests/test.button.pas` 的 `uses` 含 `BGRABitmap, BGRABitmapTypes`;如缺则加入。

- [ ] **Step 5.2: 运行,确认失败(红)** — 运行测试套件。Expected:`TestHoverBlendUsesRestingState` 失败——当前混色逻辑不感知 selected,选中 ghost 在 headless 下按 `FHover=False` 走非混色路径解析 `CurrentStyle`(含 selected)其实可能已对;**若该断言此时已通过**,说明仅动画中间帧受影响——改为下方更强的中间帧断言:在 `B.RenderTo` 前调用 `B.ArmBgAnim` 等已有动画 seam 制造 `0<Eased<1`(参考 `tests/test.animation.button.pas` 的驱动方式),断言中间帧底色介于 selected 底与 hover 底之间。实施者据实选用其一,确保红→绿。

- [ ] **Step 5.3: 改混色取色** — `source/tyControls.Button.pas` 的 `RenderTo`,把现有:

```pascal
    if (Eased > 0) and (Eased < 1) and (S.Background.Kind = tfkSolid) then
    begin
      NormalS := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]);
      HoverS  := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysHover]);
      if (NormalS.Background.Kind = tfkSolid) and (HoverS.Background.Kind = tfkSolid) then
        S.Background.Color := TyLerpColor(NormalS.Background.Color, HoverS.Background.Color, Eased);
    end;
```

替换为(以 `CurrentStates` 去/加 hover 取两端静止/悬停样式):

```pascal
    if (Eased > 0) and (Eased < 1) and (S.Background.Kind = tfkSolid) then
    begin
      // 静止态 = 当前态去掉 hover(选中按钮即 selected 底,普通按钮即 normal 底);
      // 悬停态 = 当前态加上 hover。让 alpha 也参与插值(ghost 的透明底 -> 不透明底淡入)。
      NormalS := ActiveController.Model.ResolveStyle(
        GetStyleTypeKey, StyleClass, CurrentStates - [tysHover]);
      HoverS  := ActiveController.Model.ResolveStyle(
        GetStyleTypeKey, StyleClass, CurrentStates + [tysHover]);
      if (NormalS.Background.Kind = tfkSolid) and (HoverS.Background.Kind = tfkSolid) then
        S.Background.Color := TyLerpColor(NormalS.Background.Color, HoverS.Background.Color, Eased);
    end;
```

- [ ] **Step 5.4: 运行,确认通过(绿)** — 运行测试套件。Expected:新测试通过;`tests/test.animation.button.pas` 与既有按钮像素测试全绿(普通按钮取色路径等价不变)。

- [ ] **Step 5.5: 提交**

```bash
git add source/tyControls.Button.pas tests/test.button.pas
git commit -m "fix(tycontrols): hover fade blends the resting state (correct for selected ghost)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase E：角标(badge)

### Task 6：画笔文本测量 `MeasureText` + 反缩放 `Unscale`

**Files:**
- Modify: `source/tyControls.Painter.pas`
- Test: `tests/test.painter.pas`(新增 published 方法)

- [ ] **Step 6.1: 写失败测试** — `tests/test.painter.pas` 的 `TPainterTest` `published` 段加 `procedure TestMeasureTextAndUnscale;`,implementation 段加:

```pascal
procedure TPainterTest.TestMeasureTextAndUnscale;
var P: TTyPainter; bmp: TBitmap; sz: TSize;
begin
  bmp := TBitmap.Create; P := TTyPainter.Create;
  try
    bmp.SetSize(60, 30);
    P.BeginPaint(bmp.Canvas, Rect(0,0,60,30), 96);
    sz := P.MeasureText('99+', '', 9, 400);
    AssertTrue('measured width > 0', sz.cx > 0);
    AssertTrue('measured height > 0', sz.cy > 0);
    // Unscale 是 Scale 的逆:96 PPI 下恒等
    AssertEquals('unscale identity at 96ppi', 12, P.Unscale(P.Scale(12)));
    P.EndPaint;
  finally P.Free; bmp.Free; end;
end;
```

> 需 `tests/test.painter.pas` 的 `uses` 含 `Types`(`TSize`);如缺则加入。

- [ ] **Step 6.2: 运行,确认编译失败(红)** — 运行测试套件。Expected:编译失败,`MeasureText`/`Unscale` 未定义。

- [ ] **Step 6.3: 实现** — `source/tyControls.Painter.pas`:

interface 的 `TTyPainter` public 段(`Scale` 附近)加声明:

```pascal
    function Unscale(ADevice: Integer): Integer;
    function MeasureText(const AText, AFontName: string; AFontSizeLogical, AWeight: Integer): TSize;
```

implementation 段(`Scale` 之后)加:

```pascal
function TTyPainter.Unscale(ADevice: Integer): Integer;
begin
  // 逆缩放:device px -> logical px。FillBackground 的圆角是逻辑值且内部再 Scale,
  // 故由 device 几何反推逻辑半径时用它。
  Result := MulDiv(ADevice, 96, FPPI);
end;

function TTyPainter.MeasureText(const AText, AFontName: string; AFontSizeLogical, AWeight: Integer): TSize;
begin
  Result := Size(0, 0);
  if FBmp = nil then Exit;
  // 与 DrawText 同一字体配置,保证测量=绘制。
  TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
  Result := FBmp.TextSize(AText);
end;
```

- [ ] **Step 6.4: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestMeasureTextAndUnscale` 通过。

- [ ] **Step 6.5: 提交**

```bash
git add source/tyControls.Painter.pas tests/test.painter.pas
git commit -m "feat(tycontrols): TTyPainter.MeasureText + Unscale helpers (for badge layout)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7：角标类型/属性 + 显示决策 `ResolveBadgeDisplay`

**Files:**
- Modify: `source/tyControls.Button.pas`
- Test: `tests/test.button.pas`(扩展 `TTyButtonAccess` + 新增 published 方法)

- [ ] **Step 7.1: 暴露决策方法给测试** — `tests/test.button.pas` 的 `TTyButtonAccess` 声明段加:

```pascal
    function CallResolveBadge(out AText: string): Boolean;
```

implementation 段加:

```pascal
function TTyButtonAccess.CallResolveBadge(out AText: string): Boolean;
begin
  Result := ResolveBadgeDisplay(AText);
end;
```

- [ ] **Step 7.2: 写失败测试** — `TButtonTest` private 段加一个事件处理器,published 段加 `procedure TestBadgeDisplayRules;`。private 段:

```pascal
    procedure HideUnderThree(Sender: TObject; AValue: Integer; var AText: string; var AVisible: Boolean);
```

implementation:

```pascal
procedure TButtonTest.HideUnderThree(Sender: TObject; AValue: Integer;
  var AText: string; var AVisible: Boolean);
begin
  if AValue < 3 then AVisible := False;   // 用户策略:<3 不显示
end;

procedure TButtonTest.TestBadgeDisplayRules;
var B: TTyButtonAccess; txt: string;
begin
  B := TTyButtonAccess.Create(nil);
  try
    // 默认值
    AssertFalse('ShowBadge default False', B.ShowBadge);
    AssertTrue('BadgePosition default bottom-right', B.BadgePosition = bpBottomRight);
    AssertTrue('Down/badge props published', IsPublishedProp(B, 'ShowBadge')
      and IsPublishedProp(B, 'BadgeValue') and IsPublishedProp(B, 'BadgePosition'));
    // 关:不显示
    B.ShowBadge := False; B.BadgeValue := 5;
    AssertFalse('off -> not visible', B.CallResolveBadge(txt));
    // 开 + 值0:默认显示 "0"
    B.ShowBadge := True; B.BadgeValue := 0;
    AssertTrue('on, value 0 -> visible by default', B.CallResolveBadge(txt));
    AssertEquals('value 0 text', '0', txt);
    // >99 -> 99+
    B.BadgeValue := 150;
    AssertTrue(B.CallResolveBadge(txt));
    AssertEquals('cap at 99+', '99+', txt);
    // 事件隐藏 <3
    B.OnBadgeDisplay := @HideUnderThree;
    B.BadgeValue := 2;
    AssertFalse('event hides <3', B.CallResolveBadge(txt));
    B.BadgeValue := 7;
    AssertTrue('event shows >=3', B.CallResolveBadge(txt));
    AssertEquals('7 text', '7', txt);
  finally B.Free; end;
end;
```

- [ ] **Step 7.3: 运行,确认编译失败(红)** — 运行测试套件。Expected:编译失败,`ShowBadge`/`BadgeValue`/`BadgePosition`/`bpBottomRight`/`ResolveBadgeDisplay` 未定义。

- [ ] **Step 7.4: 实现类型、属性、决策** — `source/tyControls.Button.pas`:

`interface` 的 `type` 段、`TTyButton` 声明**之前**加:

```pascal
  TTyBadgePosition = (bpTopLeft, bpTopRight, bpBottomLeft, bpBottomRight);
  TTyBadgeDisplayEvent = procedure(Sender: TObject; AValue: Integer;
    var AText: string; var AVisible: Boolean) of object;
```

`TTyButton` private 段加:

```pascal
    FShowBadge: Boolean;
    FBadgeValue: Integer;
    FBadgePosition: TTyBadgePosition;
    FOnBadgeDisplay: TTyBadgeDisplayEvent;
    procedure SetShowBadge(AValue: Boolean);
    procedure SetBadgeValue(AValue: Integer);
    procedure SetBadgePosition(AValue: TTyBadgePosition);
```

protected 段加:

```pascal
    // 决定是否/以何文本绘制角标:ShowBadge 关 -> False;否则按 >99->'99+' 算默认文本与
    // 可见(含 0),再经 OnBadgeDisplay 让用户改写;最终 visible 且文本非空才 True。
    function ResolveBadgeDisplay(out AText: string): Boolean;
    procedure DrawBadge(P: TTyPainter; const AFullRect: TRect);
```

published 段加:

```pascal
    // 角标(badge):仅数字,>99 显示 '99+'。ShowBadge 为总开关;默认显示含 0,可经
    // OnBadgeDisplay 改写文本或置 AVisible:=False 自定义隐藏策略。样式由 TyBadge typeKey 主题化。
    property ShowBadge: Boolean read FShowBadge write SetShowBadge default False;
    property BadgeValue: Integer read FBadgeValue write SetBadgeValue default 0;
    property BadgePosition: TTyBadgePosition read FBadgePosition write SetBadgePosition default bpBottomRight;
    property OnBadgeDisplay: TTyBadgeDisplayEvent read FOnBadgeDisplay write FOnBadgeDisplay;
```

构造函数 `TTyButton.Create` 末尾加(显式设默认角位):

```pascal
  FBadgePosition := bpBottomRight;
```

implementation 段加 setter 与决策:

```pascal
procedure TTyButton.SetShowBadge(AValue: Boolean);
begin
  if FShowBadge = AValue then Exit;
  FShowBadge := AValue;
  Invalidate;
end;

procedure TTyButton.SetBadgeValue(AValue: Integer);
begin
  if FBadgeValue = AValue then Exit;
  FBadgeValue := AValue;
  if FShowBadge then Invalidate;
end;

procedure TTyButton.SetBadgePosition(AValue: TTyBadgePosition);
begin
  if FBadgePosition = AValue then Exit;
  FBadgePosition := AValue;
  if FShowBadge then Invalidate;
end;

function TTyButton.ResolveBadgeDisplay(out AText: string): Boolean;
var vis: Boolean;
begin
  Result := False;
  AText := '';
  if not FShowBadge then Exit;
  if FBadgeValue > 99 then AText := '99+' else AText := IntToStr(FBadgeValue);
  vis := True;
  if Assigned(FOnBadgeDisplay) then FOnBadgeDisplay(Self, FBadgeValue, AText, vis);
  Result := vis and (AText <> '');
end;
```

> `IntToStr` 已由 `SysUtils` 提供(单元已 uses)。`DrawBadge` 在 Task 8 实现;本任务先放一个最小占位实现以便编译通过:

```pascal
procedure TTyButton.DrawBadge(P: TTyPainter; const AFullRect: TRect);
begin
  // 真正绘制在 Task 8 实现。
end;
```

- [ ] **Step 7.5: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestBadgeDisplayRules` 通过。

- [ ] **Step 7.6: 提交**

```bash
git add source/tyControls.Button.pas tests/test.button.pas
git commit -m "feat(tycontrols): badge properties + display decision (ShowBadge/BadgeValue/BadgePosition/OnBadgeDisplay)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8：角标绘制(按角内嵌 + TyBadge 主题色)

**Files:**
- Modify: `source/tyControls.Button.pas`(`DrawBadge` 实体 + `RenderTo` 调用)
- Test: `tests/test.button.pas`(新增像素测试)

- [ ] **Step 8.1: 写失败测试** — `TButtonTest` `published` 段加 `procedure TestBadgeRendersAtCorner;`,implementation:

```pascal
procedure TButtonTest.TestBadgeRendersAtCorner;
var
  B: TTyButtonAccess; Bmp: TBitmap; Reread: TBGRABitmap; Px: TBGRAPixel;
begin
  // 内置 TyBadge 背景 = var(--accent) = #3B82F6(R=$3B,G=$82,B=$F6)。
  // 右下角内嵌:badge 占据约 x∈[w-2-bw, w-2]、y∈[h-2-bh, h-2]。取靠右下的点验证为蓝。
  Bmp := TBitmap.Create;
  B := TTyButtonAccess.Create(nil);
  try
    B.Caption := '';
    B.Font.PixelsPerInch := 96;
    B.ShowBadge := True;
    B.BadgeValue := 2;
    B.BadgePosition := bpBottomRight;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 40);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(92, 31);   // 右下角徽标体内
      AssertTrue('badge is accent blue: B>200', Px.blue > 200);
      AssertTrue('badge is accent blue: R<128', Px.red < 128);
    finally Reread.Free; end;

    // 关掉角标:同点应是按钮 surface(白),非蓝。
    B.ShowBadge := False;
    Bmp.Canvas.Brush.Color := clBlack; Bmp.Canvas.FillRect(0,0,100,40);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(92, 31);
      AssertFalse('no badge -> not accent blue', (Px.blue > 200) and (Px.red < 128));
    finally Reread.Free; end;
  finally B.Free; Bmp.Free; end;
end;
```

- [ ] **Step 8.2: 运行,确认失败(红)** — 运行测试套件。Expected:`TestBadgeRendersAtCorner` 失败(`DrawBadge` 仍是占位,且 `RenderTo` 未调用它)。

- [ ] **Step 8.3: 实现 DrawBadge + 在 RenderTo 调用** — `source/tyControls.Button.pas`:

把 Task 7 的占位 `DrawBadge` 替换为:

```pascal
procedure TTyButton.DrawBadge(P: TTyPainter; const AFullRect: TRect);
var
  S: TTyStyleSet;
  txt: string;
  fs, fw, padX, padY, tw, bh, bw, inset, x, y, half, themedR, rLogical: Integer;
  szH, szW: TSize;
  badgeRect: TRect;
begin
  if not ResolveBadgeDisplay(txt) then Exit;
  S := ActiveController.Model.ResolveStyle('TyBadge', '', []);
  if not (tpBackground in S.Present) then Exit;   // 无主题键则不画
  fs := ResolveFontSize(S);
  fw := S.FontWeight;
  // 高度用参考字 '0'(与内容无关、稳定);宽度用实际文本。
  szH := P.MeasureText('0', S.FontName, fs, fw);
  szW := P.MeasureText(txt, S.FontName, fs, fw);
  padX := P.Scale(S.Padding.Left);
  padY := P.Scale(S.Padding.Top);
  bh := szH.cy + 2 * padY;
  if bh < P.Scale(8) then bh := P.Scale(8);    // 退化保护:测量异常时仍可见
  tw := szW.cx;
  bw := tw + 2 * padX;
  if bw < bh then bw := bh;                     // 单字符 -> 近正圆
  inset := P.Scale(2);
  x := AFullRect.Left + inset;
  y := AFullRect.Top + inset;
  case FBadgePosition of
    bpTopLeft:     begin x := AFullRect.Left  + inset;       y := AFullRect.Top    + inset;       end;
    bpTopRight:    begin x := AFullRect.Right - inset - bw;  y := AFullRect.Top    + inset;       end;
    bpBottomLeft:  begin x := AFullRect.Left  + inset;       y := AFullRect.Bottom - inset - bh;  end;
    bpBottomRight: begin x := AFullRect.Right - inset - bw;  y := AFullRect.Bottom - inset - bh;  end;
  end;
  badgeRect := Rect(x, y, x + bw, y + bh);
  // 圆角:默认胶囊(半高);若主题给了更小半径则尊重之。FillBackground 收逻辑半径,故反缩放。
  half := P.Unscale(bh div 2);
  themedR := TyEffectiveCorners(S).TL;
  if themedR <= 0 then rLogical := half
  else rLogical := TyClampRadius(themedR, half);
  P.FillBackground(badgeRect, S.Background, TyUniformCorners(rLogical));
  P.DrawText(badgeRect, txt, S.FontName, fs, fw, S.TextColor, taCenter, tlCenter, False);
end;
```

在 `RenderTo` 内,定位"画完 frame、内缩 padding 之前"那段。把:

```pascal
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, ContentRect, S);
    // Inset content by all four padding sides
    ContentRect := Rect(
```

改为(捕获全客户区供角标定位):

```pascal
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, ContentRect, S);
    BadgeArea := ContentRect;   // 角标定位用全客户区(padding 内缩前)
    // Inset content by all four padding sides
    ContentRect := Rect(
```

并在 `RenderTo` 的 `P.DrawText(ContentRect, Caption, ...)` 之后、`P.EndPaint;` 之前插入:

```pascal
    DrawBadge(P, BadgeArea);
```

在 `RenderTo` 的 `var` 段加局部变量 `BadgeArea: TRect;`(与现有 `ContentRect` 并列)。

> 用到的 `TyEffectiveCorners`、`TyClampRadius`、`TyUniformCorners` 均在 `tyControls.Types`(单元已 uses);`tpBackground` 同。

- [ ] **Step 8.4: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestBadgeRendersAtCorner` 通过;现有按钮像素测试不破(未开 ShowBadge 时 `DrawBadge` 立即 Exit)。

- [ ] **Step 8.5: 提交**

```bash
git add source/tyControls.Button.pas tests/test.button.pas
git commit -m "feat(tycontrols): render numeric badge (corner-inset, TyBadge-themed)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase F：其余主题

### Task 9：把 `TyButton.ghost` + `TyBadge` 同步到其余 5 个主题

**Files:**
- Modify: `themes/dark.tycss`、`themes/green.tycss`、`themes/showcase.tycss`、`themes/system.tycss`、`themes/auto.tycss`
- Test: `tests/test.themes.pas`(若存在主题加载测试则扩展;否则新增 published 方法)

- [ ] **Step 9.1: 写测试** — 在 `tests/test.themes.pas` 的 `TTestThemes`(已注册)加 `procedure TestAllThemesHaveGhostAndBadge;`,逐个加载每主题文件,断言 `TyButton.ghost`(基态背景透明 alpha=0)与 `TyBadge`(有 background)存在:

```pascal
procedure TTestThemes.TestAllThemesHaveGhostAndBadge;
const Names: array[0..5] of string =
  ('light','dark','green','showcase','system','auto');
var
  i: Integer; m: TTyStyleModel; g, b: TTyStyleSet; path: string;
begin
  for i := 0 to High(Names) do
  begin
    path := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes'
      + PathDelim + Names[i] + '.tycss';
    AssertTrue(Names[i] + ' exists', FileExists(path));
    m := TTyStyleModel.Create;
    try
      m.LoadFromFile(path);
      g := m.ResolveStyle('TyButton', 'ghost', []);
      AssertTrue(Names[i] + ': ghost base transparent',
        (tpBackground in g.Present) and (TyAlphaOf(g.Background.Color) = 0));
      b := m.ResolveStyle('TyBadge', '', []);
      AssertTrue(Names[i] + ': TyBadge background', tpBackground in b.Present);
    finally m.Free; end;
  end;
end;
```

> `TTestThemes` 的 `uses` 应已含 `tyControls.StyleModel`、`tyControls.Types`;如缺补之。

- [ ] **Step 9.2: 运行,确认失败(红)** — 运行测试套件。Expected:`light` 通过(Task 3 已加),其余 5 个失败。

- [ ] **Step 9.3: 给每个主题追加 ghost + TyBadge** — 对 `dark/green/showcase/system/auto` 各文件,在其 `TyButton.danger:...` 块之后追加 ghost 块、并在文件子元素区追加 `TyBadge`,**用该主题已有的 token 习惯**:

  - `themes/dark.tycss`、`themes/system.tycss`、`themes/auto.tycss`(与 light 同 token 命名):直接复用 Task 3 的 ghost/`TyBadge` 文本。
  - `themes/green.tycss`(用 `darken(--surface,n%)`、字面 `0.5`、`#FFFFFF`):

```css
TyButton.ghost {
  background: alpha(var(--surface), 0);
  color: var(--on-surface);
  border-color: alpha(var(--border), 0);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 6px;
}
TyButton.ghost:hover    { background: darken(--surface, 4%); border-color: darken(--border, 10%); }
TyButton.ghost:active   { background: darken(--surface, 10%); }
TyButton.ghost:selected { background: darken(--surface, 10%); border-color: var(--accent); }
TyButton.ghost:focus    { outline: 2px var(--focus-ring); }
TyButton.ghost:disabled { opacity: 0.5; }

TyBadge { background: var(--accent); color: #FFFFFF; border-radius: var(--radius-round);
          font-weight: 700; padding: 0px 4px; }
```

  - `themes/showcase.tycss`(hover 用渐变):ghost 块仍用纯色 surface(透明底 alpha 淡入需要纯色;渐变不参与混色,会退化为瞬时——可接受)。`TyBadge` 用该主题的 accent/`--on-accent` 令牌。

> 实施者逐文件核对其 `:root` 实际定义了哪些令牌(如 `--surface-hover`/`--on-accent`/`--radius-round` 是否存在),缺失则改用该主题等价令牌或字面值,确保加载不因未定义 var 而 fail-fast。

- [ ] **Step 9.4: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestAllThemesHaveGhostAndBadge` 全过。

- [ ] **Step 9.5: 提交**

```bash
git add themes/dark.tycss themes/green.tycss themes/showcase.tycss themes/system.tycss themes/auto.tycss tests/test.themes.pas
git commit -m "feat(tycontrols): add ghost variant + TyBadge to all bundled themes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase G：设计期 StyleClass 编辑器(动态)

### Task 10：`TTyStyleModel.GetVariantsForType`

**Files:**
- Modify: `source/tyControls.StyleModel.pas`
- Test: `tests/test.StyleModel.pas`(新增 published 方法)

- [ ] **Step 10.1: 写失败测试** — `tests/test.StyleModel.pas` 的 `TTestStyleResolve` 加 `procedure TestGetVariantsForType;`:

```pascal
procedure TTestStyleResolve.TestGetVariantsForType;
var m: TTyStyleModel; list: TStringList;
begin
  m := TTyStyleModel.Create;   // 仅内置层
  list := TStringList.Create;
  try
    m.GetVariantsForType('TyButton', list);
    AssertTrue('builtin has primary', list.IndexOf('primary') >= 0);
    AssertTrue('builtin has danger', list.IndexOf('danger') >= 0);
    AssertTrue('builtin has ghost',  list.IndexOf('ghost')  >= 0);
    // 该 typeKey 的 variant 不会串到别的控件
    list.Clear;
    m.GetVariantsForType('TyEdit', list);
    AssertEquals('TyEdit has no variants', 0, list.Count);
    // 加载自定义主题后,新 class 出现且去重
    list.Clear;
    m.LoadFromCss('TyButton.cta { background:#FF0000; } TyButton.cta:hover { background:#EE0000; }');
    m.GetVariantsForType('TyButton', list);
    AssertTrue('custom class appears', list.IndexOf('cta') >= 0);
    AssertEquals('cta deduped (one entry)', 1,
      Length(list.Text) - Length(StringReplace(list.Text, 'cta'+LineEnding, '', [rfReplaceAll])) > 0); // 见下注
  finally list.Free; m.Free; end;
end;
```

> 末尾去重断言写法繁琐,实施时简化为:遍历 `list` 统计等于 `'cta'` 的项数 == 1。例如:

```pascal
    var k, n: Integer; n := 0;
    for k := 0 to list.Count - 1 do if list[k] = 'cta' then Inc(n);
    AssertEquals('cta deduped', 1, n);
```

(用此替换上面那条 `AssertEquals('cta deduped ...')`。)

- [ ] **Step 10.2: 运行,确认编译失败(红)** — 运行测试套件。Expected:编译失败,`GetVariantsForType` 未定义。

- [ ] **Step 10.3: 实现** — `source/tyControls.StyleModel.pas`:

`TTyStyleModel` public 段加声明:

```pascal
    { 收集 ATypeKey 在 base 层 + user 层定义过的去重 variant(.class,忽略 :state)。
      供设计期 StyleClass 下拉按控件类型 + 当前主题动态列出可用 class。 }
    procedure GetVariantsForType(const ATypeKey: string; AList: TStrings);
```

implementation 段加:

```pascal
procedure TTyStyleModel.GetVariantsForType(const ATypeKey: string; AList: TStrings);

  procedure ScanLayer(ARules: TFPList);
  var i: Integer; e: TTyStyleRuleEntry;
  begin
    for i := 0 to ARules.Count - 1 do
    begin
      e := TTyStyleRuleEntry(ARules[i]);
      if SameText(e.TypeName, ATypeKey) and (e.Variant <> '')
         and (AList.IndexOf(e.Variant) < 0) then
        AList.Add(e.Variant);
    end;
  end;

begin
  if AList = nil then Exit;
  ScanLayer(FBaseRules);
  ScanLayer(FRules);
end;
```

- [ ] **Step 10.4: 运行,确认通过(绿)** — 运行测试套件。Expected:`TestGetVariantsForType` 通过。

- [ ] **Step 10.5: 提交**

```bash
git add source/tyControls.StyleModel.pas tests/test.StyleModel.pas
git commit -m "feat(tycontrols): TTyStyleModel.GetVariantsForType for dynamic StyleClass listing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11：动态 `GetValues`(按 typeKey + controller model)

**Files:**
- Modify: `designtime/tyControls.Design.pas`
- Verify: 构建设计期包 + 手动 IDE 验证(无 headless 单测)

- [ ] **Step 11.1: 改写 GetValues** — `designtime/tyControls.Design.pas`,把:

```pascal
procedure TTyStyleClassPropertyEditor.GetValues(Proc: TGetStrProc);
begin
  Proc('primary');
  Proc('danger');
  Proc('close');
  Proc('min');
  Proc('max');
end;
```

替换为:

```pascal
procedure TTyStyleClassPropertyEditor.GetValues(Proc: TGetStrProc);
var
  comp: TPersistent;
  sty: ITyStyleable;
  ctrl: TTyStyleController;
  model: TTyStyleModel;
  list: TStringList;
  i: Integer;
begin
  comp := GetComponent(0);
  if not Supports(comp, ITyStyleable, sty) then Exit;
  // 取该控件实际使用的 model:其 Controller(若设)否则全局默认。两个基类都暴露
  // published Controller,但无公共祖先,故分别判断。
  ctrl := nil;
  if comp is TTyGraphicControl then ctrl := TTyGraphicControl(comp).Controller
  else if comp is TTyCustomControl then ctrl := TTyCustomControl(comp).Controller;
  if ctrl <> nil then model := ctrl.Model else model := TyDefaultController.Model;
  list := TStringList.Create;
  try
    list.Sorted := True;          // 稳定显示顺序
    list.Duplicates := dupIgnore;
    model.GetVariantsForType(sty.GetStyleTypeKey, list);
    for i := 0 to list.Count - 1 do Proc(list[i]);
  finally
    list.Free;
  end;
end;
```

> `designtime/tyControls.Design.pas` 的 `uses` 已含 `tyControls.Base`(`ITyStyleable`/两基类)、`tyControls.Controller`(`TTyStyleController`/`TyDefaultController`)、`tyControls.StyleModel`(`TTyStyleModel`)。`Supports` 来自 `SysUtils`(已 uses)。如编译报缺,补 `uses`。

- [ ] **Step 11.2: 构建运行期 + 设计期包** — 运行:`lazbuild tyControls.lpk && lazbuild tycontrols_dt.lpk`。Expected:两个包均 `Compile Project ... Success`,无错误。

- [ ] **Step 11.3: 回归测试套件** — 运行测试套件(确认 GetVariantsForType 等核心逻辑未被破坏)。Expected:0 失败。

- [ ] **Step 11.4: 手动 IDE 验证(记录,不阻塞)** — 在已安装设计期包的 Lazarus 里:拖一个 `TTyButton`,Object Inspector 的 StyleClass 下拉应只列 `primary/danger/ghost`(不再有 `min/max/close`);拖一个 `TTyEdit`,下拉应为空;窗体放一个 `TTyStyleController` 设 `ThemeFile` 指向含自定义 `TyButton.<x>` 的主题,该自定义 class 应出现。把结果记入提交说明或 PR。

- [ ] **Step 11.5: 提交**

```bash
git add designtime/tyControls.Design.pas
git commit -m "fix(tycontrols): StyleClass design-time dropdown reads theme variants per control type

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase H：文档与示例

### Task 12：更新 `docs/controls/button.md`

**Files:**
- Modify: `docs/controls/button.md`

- [ ] **Step 12.1: 追加属性/状态/角标文档** — 在 `docs/controls/button.md` 相应处补充(自有 published 属性表加 `Down`/`ShowBadge`/`BadgeValue`/`BadgePosition`;事件表加 `OnBadgeDisplay`;状态表加 `:selected`;新增"Ghost 变体"与"角标"两节)。建议加入如下内容块:

```markdown
### Ghost(透明)变体 与 选中态

`StyleClass := 'ghost'` 使按钮平时透明(无可见底色/边框),仅 hover/active/选中时显示。
选中是常驻状态:`Button.Down := True;` 触发主题中的 `:selected` 规则(如
`TyButton.ghost:selected`)。互斥分组(同组仅一个选中)由应用在 `OnClick` 中切换各按钮
的 `Down` 实现(本控件不内建 GroupIndex)。

| 属性 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `Down` | `Boolean` | `False` | 常驻选中态;为 True 时 `CurrentStates` 注入 `tysSelected`(disabled 时不生效) |

伪状态新增 `:selected`(别名 `:checked`):见 [tycss-reference](../tycss-reference.md)。

### 角标(badge)

按钮右下角(可改)叠加一个数字角标。仅数字,`>99` 显示 `99+`。

| 属性 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `ShowBadge` | `Boolean` | `False` | 角标总开关 |
| `BadgeValue` | `Integer` | `0` | 数值 |
| `BadgePosition` | `TTyBadgePosition` | `bpBottomRight` | 角标所在角(`bpTopLeft/bpTopRight/bpBottomLeft/bpBottomRight`) |

| 事件 | 签名 | 说明 |
|------|------|------|
| `OnBadgeDisplay` | `procedure(Sender; AValue: Integer; var AText: string; var AVisible: Boolean)` | 显示前回调:默认显示含 0,可改写文本或置 `AVisible:=False` 自定义隐藏(如 `<3` 不显示) |

样式由 `TyBadge` typeKey 主题化(默认 `var(--accent)` 蓝底):

​```css
TyBadge { background: var(--accent); color: var(--on-accent);
          border-radius: var(--radius-round); font-weight: var(--font-weight-bold);
          font-size: var(--font-size-base); padding: 0px 4px; }
​```

​```pascal
Btn.StyleClass := 'ghost';
Btn.Down := True;          // 选中态
Btn.ShowBadge := True;
Btn.BadgeValue := 2;       // 角标显示 "2"
// 仅在 >=3 时显示:
//   Btn.OnBadgeDisplay := @MyHandler;  // var AVisible := AValue >= 3;
​```
```

> 上面代码围栏里的反引号是中文全角占位以避免嵌套冲突;落盘时改回正常的三反引号代码块。

- [ ] **Step 12.2: 校对** — 通读 `button.md` 确认表格/锚点正确、与实现属性名一致(`Down`/`ShowBadge`/`BadgeValue`/`BadgePosition`/`OnBadgeDisplay`/`bpBottomRight`)。

- [ ] **Step 12.3: 提交**

```bash
git add docs/controls/button.md
git commit -m "docs(tycontrols): document button ghost variant, selected state, badge

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13：示例 `examples/button/umain.pas`

**Files:**
- Modify: `examples/button/umain.pas`

- [ ] **Step 13.1: 阅读现状** — 打开 `examples/button/umain.pas`,找到窗体创建控件的位置(`FormCreate`/构造)与其使用的 `Controller`/布局坐标约定。

- [ ] **Step 13.2: 加 ghost+选中+角标演示** — 在现有按钮创建之后,追加(把 `AddBtn` 改成该文件实际的父容器/坐标方式;若文件直接 `Btn := TTyButton.Create(Self); Btn.Parent := ...` 则照搬该模式):

```pascal
var
  GhostBtn, BadgeBtn: TTyButton;
begin
  // ... 现有按钮 ...

  // Ghost(透明)+ 选中态
  GhostBtn := TTyButton.Create(Self);
  GhostBtn.Parent := Self;          // 改为该示例实际父容器
  GhostBtn.SetBounds(24, 220, 160, 32);
  GhostBtn.Caption := 'Ghost / 选中';
  GhostBtn.StyleClass := 'ghost';
  GhostBtn.Down := True;            // 常驻选中
  GhostBtn.OnClick := @ToggleGhostDown;   // 见下:点击切换选中

  // 角标
  BadgeBtn := TTyButton.Create(Self);
  BadgeBtn.Parent := Self;
  BadgeBtn.SetBounds(200, 220, 160, 32);
  BadgeBtn.Caption := '消息';
  BadgeBtn.ShowBadge := True;
  BadgeBtn.BadgeValue := 128;       // 显示 "99+"
  BadgeBtn.BadgePosition := bpBottomRight;
end;
```

并在窗体类加一个点击处理器(演示选中切换):

```pascal
procedure TForm1.ToggleGhostDown(Sender: TObject);
begin
  (Sender as TTyButton).Down := not (Sender as TTyButton).Down;
end;
```

> 把 `TForm1` 换成该示例实际窗体类名;`ToggleGhostDown` 需在窗体类 `published`/`private` 段声明。

- [ ] **Step 13.3: 构建示例** — 运行:`lazbuild examples/button/button_example.lpi`。Expected:`Success`,无错误。

- [ ] **Step 13.4: 提交**

```bash
git add examples/button/umain.pas
git commit -m "docs(tycontrols): demo ghost+selected button and badge in button example

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase I：收尾

### Task 14：全量回归 + 包构建

- [ ] **Step 14.1: 全量测试** — 运行:`lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`。Expected:`Number of errors: 0`、`Number of failures: 0`。
- [ ] **Step 14.2: 包构建** — 运行:`lazbuild tyControls.lpk && lazbuild tycontrols_dt.lpk`。Expected:两包均成功。
- [ ] **Step 14.3: 示例冒烟** — 运行:`lazbuild examples/button/button_example.lpi`。Expected:成功。
- [ ] **Step 14.4:(可选)开 PR** — `gh pr create`,标题 `feat(tycontrols): button ghost variant + selected state + numeric badge + dynamic StyleClass editor`,正文链接 spec/plan 并附 Task 11.4 的手动 IDE 验证结果。

---

## 自检对照(spec 覆盖)

- A1 `:selected` 引擎 → Task 1、2 ✓
- A2 `Down` + CurrentStates → Task 4 ✓
- A3 动画取色修正 → Task 5 ✓
- A4 ghost 变体(light+全主题) → Task 3、9 ✓
- B1 角标属性/事件 → Task 7 ✓
- B2 显示规则(含 0 默认显示、事件隐藏、99+) → Task 7 ✓
- B3 `TyBadge` 主题键 → Task 3、9 ✓
- B4 渲染(MeasureText/Unscale/按角内嵌/胶囊半径) → Task 6、8 ✓
- C 动态 StyleClass 编辑器 → Task 10、11 ✓
- 文档/示例 → Task 12、13 ✓
- 同步/回归(DefaultTheme、golden) → Task 3、14 ✓

## 风险备忘

- `cStateOrder` 改 5 元素:仅 `ResolveLayer` 使用,`High()` 自适应。
- 新增 `tysSelected`:若 `tests/test.Types.pas` 对枚举有断言(数量/名称),Task 1 后随全量跑核对,必要时同步该测试。
- 设计期 `GetValues` 无 headless 单测:靠 Task 11.4 真实 IDE 验证(系统级)。
- 各主题 `:root` 令牌集合不同:Task 9 逐文件核对 var 是否定义,避免 fail-fast 加载失败。
- headless 字体测量:角标像素测试只采样**背景胶囊**色(不依赖字形),对空 FontName 回退稳健。
