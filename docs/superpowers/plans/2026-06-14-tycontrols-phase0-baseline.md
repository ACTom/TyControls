# TyControls Phase 0 横切基线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让圆角与焦点环成为**主题可定制**的 CSS 能力(per-corner `border-radius` + `outline` 焦点环),用它把默认主题统一成"A·全局统一圆角"(修标题栏/Tab 直角);并补齐横切交互基线(键盘激活 + 统一 published 属性)。

**Architecture:** 沿用三层解耦。新增能力**纯叠加、向后兼容**:`TTyStyleSet` 增 `Radius: TTyCorners` 与 `Outline*` 字段;DSL `border-radius` 支持 1 值(旧)与 4 值(新),新增 `outline`/`outline-offset`;`TTyPainter` 的圆角原语增 per-corner 重载(BGRABitmap `rr*Square` 方化指定角);`DrawFrame` 用每角半径画背景/边框,并在 `:focus` 解析出 `outline` 时画内侧焦点环。控件代码零硬编码视觉值。

**Tech Stack:** Free Pascal / Lazarus LCL / BGRABitmap;FPCUnit;PPI=96 像素探针。

**约定:** 几何/像素测试钉 `PPI=96`。运行测试:`lazbuild tests/tytests.lpi` 后 `./tests/tytests -a --format=plain`。所有新增测试加在**已注册**的测试单元里(无需改 `tests/tytests.lpr`)。提交信息用 `feat(tycontrols): …` / `test(tycontrols): …`。

---

## File Structure

- `source/tyControls.Types.pas` — 新类型 `TTyCorners` + 助手 `TyCorners`/`TyUniformCorners`/`TyEffectiveCorners`;`TTyStyleSet` 增 `Radius`、`OutlineColor/OutlineWidth/OutlineOffset`;`TTyProp` 增 `tpOutline`。
- `source/tyControls.StyleModel.pas` — `TyMergeStyleSet` 合并新字段;`TyApplyDeclaration` 解析 `border-radius`(1/4 值)、`outline`、`outline-offset`。
- `source/tyControls.Painter.pas` — `FillBackground`/`StrokeBorder` 增 `TTyCorners` 重载(per-corner)。
- `source/tyControls.Base.pas` — 两处 `DrawFrame` 改用每角半径 + 画焦点环;两个基类 published 段补基线属性。
- `source/tyControls.TabControl.pas` — Tab 表头填充改用 `TyEffectiveCorners(TabStyle)`(主题驱动顶部圆角)。
- `source/tyControls.Button.pas` / `tyControls.CheckBox.pas`(含 TTyRadioButton)/ `tyControls.ToggleSwitch.pas` — 键盘激活。
- `themes/light.tycss` + `dark.tycss` + `showcase.tycss` + `source/tyControls.DefaultTheme.pas` — A 圆角 + `--focus-ring` + `:focus { outline }`。
- `docs/tycss-reference.md` — 新增属性文档。
- Tests(均为已注册单元,新增 `procedure Test*`):`test.Types.pas`、`test.StyleModel.pas`、`test.painter.pas`、`test.base.drawframe.pas`、`test.base.pas`、`test.button.pas`、`test.checkbox.pas`、`test.toggleswitch.pas`、`test.defaulttheme.pas`。

---

## 工作流 A — 视觉地基

### Task 1: Types — TTyCorners + Outline 字段

**Files:**
- Modify: `source/tyControls.Types.pas`
- Test: `tests/test.Types.pas`

- [ ] **Step 1: 写失败测试** (加到 `tests/test.Types.pas` 的 published 段 + 实现段;参照该文件既有 `procedure Test*` 风格)

```pascal
procedure TestUniformCornersAllEqual;
var c: TTyCorners;
begin
  c := TyUniformCorners(6);
  AssertEquals('tl', 6, c.TL);
  AssertEquals('tr', 6, c.TR);
  AssertEquals('br', 6, c.BR);
  AssertEquals('bl', 6, c.BL);
end;

procedure TestEffectiveCornersFromRadiusField;
var s: TTyStyleSet;
begin
  s := EmptyStyleSet;
  s.Radius := TyCorners(6, 6, 0, 0);
  AssertEquals('tl', 6, TyEffectiveCorners(s).TL);
  AssertEquals('bl', 0, TyEffectiveCorners(s).BL);
end;

procedure TestEffectiveCornersFallsBackToUniformBorderRadius;
{ Styles built in CODE (e.g. ToggleSwitch track) set only BorderRadius and leave
  Radius all-zero. TyEffectiveCorners must then derive uniform corners from it. }
var s: TTyStyleSet;
begin
  s := EmptyStyleSet;
  s.BorderRadius := 12;          // Radius stays (0,0,0,0)
  AssertEquals('uniform from BorderRadius', 12, TyEffectiveCorners(s).TR);
end;
```

Register these three names in the `TTypesTest` (or equivalently named) test case's `published` section.

- [ ] **Step 2: 运行确认失败/不编译**

Run: `lazbuild tests/tytests.lpi`
Expected: 编译失败(`TTyCorners`/`TyCorners`/`TyUniformCorners`/`TyEffectiveCorners`/`TTyStyleSet.Radius` 未声明)。

- [ ] **Step 3: 实现** (`source/tyControls.Types.pas`)

(a) 在 `TTyBorderStyle` 声明之后加:

```pascal
  TTyCorners = record
    TL, TR, BR, BL: Integer;   // per-corner radii, logical px
  end;
```

(b) `TTyProp` 末尾加 `tpOutline`:

```pascal
  TTyProp = (tpBackground, tpTextColor, tpBorderColor, tpBorderWidth, tpBorderRadius,
             tpPadding, tpFontName, tpFontSize, tpFontWeight, tpOpacity, tpShadow,
             tpBorderStyle, tpOutline);
```

(c) `TTyStyleSet` 在 `BorderRadius: Integer;` 之后加 `Radius` 字段,并在末尾加 outline 字段:

```pascal
    BorderRadius: Integer;
    Radius: TTyCorners;          // per-corner; falls back to BorderRadius when all 0
    ...
    ShadowOffset: TPoint;
    OutlineColor: TTyColor;
    OutlineWidth: Integer;
    OutlineOffset: Integer;
```

(d) interface 段 `EmptyStyleSet` 声明附近加三个助手声明:

```pascal
function TyCorners(ATL, ATR, ABR, ABL: Integer): TTyCorners;
function TyUniformCorners(R: Integer): TTyCorners;
function TyEffectiveCorners(const AStyle: TTyStyleSet): TTyCorners;
```

(e) implementation 段实现(放在 `EmptyStyleSet` 之前):

```pascal
function TyCorners(ATL, ATR, ABR, ABL: Integer): TTyCorners;
begin
  Result.TL := ATL; Result.TR := ATR; Result.BR := ABR; Result.BL := ABL;
end;

function TyUniformCorners(R: Integer): TTyCorners;
begin
  Result.TL := R; Result.TR := R; Result.BR := R; Result.BL := R;
end;

function TyEffectiveCorners(const AStyle: TTyStyleSet): TTyCorners;
begin
  // Per-corner Radius wins; if it was never set (all zero) but a uniform
  // BorderRadius was (e.g. a code-built style), derive uniform corners from it.
  if (AStyle.Radius.TL = 0) and (AStyle.Radius.TR = 0) and
     (AStyle.Radius.BR = 0) and (AStyle.Radius.BL = 0) and (AStyle.BorderRadius > 0) then
    Result := TyUniformCorners(AStyle.BorderRadius)
  else
    Result := AStyle.Radius;
end;
```

`EmptyStyleSet` 无需改动:`Default(TTyStyleSet)` 已把 `Radius` 四角与 `Outline*` 清零。

- [ ] **Step 4: 运行测试通过**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests --suite=TTypesTest -a --format=plain`
Expected: PASS(含三个新用例)。若 `--suite` 名不符,跑全量 `./tests/tytests -a --format=plain` 并确认三用例绿。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.Types.pas tests/test.Types.pas
git commit -m "feat(tycontrols): TTyCorners + per-corner Radius and Outline fields on TTyStyleSet"
```

---

### Task 2: StyleModel 合并新字段

**Files:**
- Modify: `source/tyControls.StyleModel.pas:53-73` (`TyMergeStyleSet`)
- Test: `tests/test.StyleModel.pas`

- [ ] **Step 1: 写失败测试** (加到 `tests/test.StyleModel.pas`)

```pascal
procedure TestMergeRadiusCornersOverrides;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  over := EmptyStyleSet;
  over.Radius := TyCorners(6, 6, 0, 0);
  over.BorderRadius := 6;
  Include(over.Present, tpBorderRadius);
  TyMergeStyleSet(base, over);
  AssertTrue('radius present after merge', tpBorderRadius in base.Present);
  AssertEquals('tl merged', 6, base.Radius.TL);
  AssertEquals('bl merged', 0, base.Radius.BL);
end;

procedure TestMergeOutlineOverrides;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  over := EmptyStyleSet;
  over.OutlineColor := TyRGB($FF, $00, $00);
  over.OutlineWidth := 2;
  over.OutlineOffset := 1;
  Include(over.Present, tpOutline);
  TyMergeStyleSet(base, over);
  AssertTrue('outline present', tpOutline in base.Present);
  AssertEquals('outline width', 2, base.OutlineWidth);
  AssertEquals('outline offset', 1, base.OutlineOffset);
  AssertEquals('outline color r', $FF, TyRedOf(base.OutlineColor));
end;
```

Register both in the test case's `published` section.

- [ ] **Step 2: 运行确认失败**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 两用例 FAIL(`base.Radius.TL`=0、`tpOutline` 未合并)。

- [ ] **Step 3: 实现** —— 在 `TyMergeStyleSet` 里把现有这一行:

```pascal
  if tpBorderRadius in AOver.Present then ABase.BorderRadius := AOver.BorderRadius;
```

替换为(同时合并 Radius):

```pascal
  if tpBorderRadius in AOver.Present then
  begin
    ABase.BorderRadius := AOver.BorderRadius;
    ABase.Radius       := AOver.Radius;
  end;
```

并在 `tpShadow` 合并块之后、`ABase.Present := ...` 之前加:

```pascal
  if tpOutline in AOver.Present then
  begin
    ABase.OutlineColor  := AOver.OutlineColor;
    ABase.OutlineWidth  := AOver.OutlineWidth;
    ABase.OutlineOffset := AOver.OutlineOffset;
  end;
```

- [ ] **Step 4: 运行测试通过**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 两用例 PASS;全量回归绿。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.StyleModel.pas tests/test.StyleModel.pas
git commit -m "feat(tycontrols): merge per-corner Radius and Outline in TyMergeStyleSet"
```

---

### Task 3: DSL 解析 border-radius(1/4 值)+ outline + outline-offset

**Files:**
- Modify: `source/tyControls.StyleModel.pas` (新 `ApplyBorderRadius`/`ApplyOutline`;`TyApplyDeclaration` 分派)
- Test: `tests/test.StyleModel.pas`

- [ ] **Step 1: 写失败测试** (加到 `tests/test.StyleModel.pas`)

```pascal
procedure TestBorderRadiusSingleValueUniform;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { border-radius: 6px; }');
    s := m.ResolveStyle('T', '', []);
    AssertTrue('present', tpBorderRadius in s.Present);
    AssertEquals('uniform border-radius', 6, s.BorderRadius);
    AssertEquals('corner tl', 6, s.Radius.TL);
    AssertEquals('corner bl', 6, s.Radius.BL);
  finally m.Free; end;
end;

procedure TestBorderRadiusFourValuesTopOnly;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { border-radius: 6px 6px 0 0; }');
    s := m.ResolveStyle('T', '', []);
    AssertEquals('tl', 6, s.Radius.TL);
    AssertEquals('tr', 6, s.Radius.TR);
    AssertEquals('br', 0, s.Radius.BR);
    AssertEquals('bl', 0, s.Radius.BL);
  finally m.Free; end;
end;

procedure TestBorderRadiusFourValuesWithVar;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root{--r:8px;} T { border-radius: var(--r) var(--r) 0 0; }');
    s := m.ResolveStyle('T', '', []);
    AssertEquals('tl from var', 8, s.Radius.TL);
    AssertEquals('br', 0, s.Radius.BR);
  finally m.Free; end;
end;

procedure TestOutlineParsed;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T:focus { outline: 2px #FF0000; }');
    s := m.ResolveStyle('T', '', [tysFocused]);
    AssertTrue('outline present on focus', tpOutline in s.Present);
    AssertEquals('outline width', 2, s.OutlineWidth);
    AssertEquals('outline color r', $FF, TyRedOf(s.OutlineColor));
  finally m.Free; end;
end;

procedure TestOutlineAbsentWhenNotFocused;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T:focus { outline: 2px #FF0000; }');
    s := m.ResolveStyle('T', '', []);   // no focus state
    AssertFalse('outline absent without focus', tpOutline in s.Present);
  finally m.Free; end;
end;

procedure TestOutlineOffsetParsed;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T:focus { outline: 2px #FF0000; outline-offset: 3px; }');
    s := m.ResolveStyle('T', '', [tysFocused]);
    AssertEquals('outline offset', 3, s.OutlineOffset);
  finally m.Free; end;
end;
```

Register all six in the `published` section.

- [ ] **Step 2: 运行确认失败**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 新用例 FAIL(4 值被旧 `TyEvalLength` 当单值/异常;`outline` 是未知属性被忽略)。

- [ ] **Step 3: 实现** (`source/tyControls.StyleModel.pas`)

(a) 在 `ApplyBorderShorthand` 之后加两个解析过程:

```pascal
// Parse 'border-radius': 1 value (all corners) or 4 values (TL TR BR BL).
procedure ApplyBorderRadius(var AStyle: TTyStyleSet; const ARaw: string; Vars: TStrings);
var
  parts: TStringList;
  i, mx: Integer;
  v: array[0..3] of Integer;
begin
  parts := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := False;       // collapse runs of spaces
    parts.DelimitedText := Trim(ARaw);
    for i := parts.Count - 1 downto 0 do
      if Trim(parts[i]) = '' then parts.Delete(i);
    case parts.Count of
      1:
        begin
          v[0] := TyEvalLength(parts[0], Vars);
          AStyle.Radius := TyCorners(v[0], v[0], v[0], v[0]);
          AStyle.BorderRadius := v[0];
        end;
      4:
        begin
          v[0] := TyEvalLength(parts[0], Vars); // TL
          v[1] := TyEvalLength(parts[1], Vars); // TR
          v[2] := TyEvalLength(parts[2], Vars); // BR
          v[3] := TyEvalLength(parts[3], Vars); // BL
          AStyle.Radius := TyCorners(v[0], v[1], v[2], v[3]);
          // uniform fallback for legacy consumers (e.g. DropShadow): the max corner
          mx := v[0];
          for i := 1 to 3 do if v[i] > mx then mx := v[i];
          AStyle.BorderRadius := mx;
        end;
    else
      raise Exception.CreateFmt('border-radius needs 1 or 4 values: %s', [ARaw]);
    end;
    Include(AStyle.Present, tpBorderRadius);
  finally
    parts.Free;
  end;
end;

// Parse 'outline: <width> <color>'. Paren-aware top-level whitespace split (so a
// var()/rgb() color survives). Leading-digit token = width; the rest = color.
procedure ApplyOutline(var AStyle: TTyStyleSet; const ARaw: string; Vars: TStrings);
var
  toks: TStringList;
  i, depth, start: Integer;
  ch: Char;
  tok: string;
begin
  toks := TStringList.Create;
  try
    depth := 0; start := 1;
    for i := 1 to Length(ARaw) do
    begin
      ch := ARaw[i];
      if ch = '(' then Inc(depth)
      else if ch = ')' then Dec(depth)
      else if (ch in [' ', #9]) and (depth = 0) then
      begin
        tok := Trim(Copy(ARaw, start, i - start));
        if tok <> '' then toks.Add(tok);
        start := i + 1;
      end;
    end;
    tok := Trim(Copy(ARaw, start, Length(ARaw) - start + 1));
    if tok <> '' then toks.Add(tok);
    for i := 0 to toks.Count - 1 do
    begin
      tok := toks[i];
      if (tok <> '') and (tok[1] in ['0'..'9']) then
        AStyle.OutlineWidth := TyEvalLength(tok, Vars)
      else
        AStyle.OutlineColor := TyEvalColor(tok, Vars);
    end;
    Include(AStyle.Present, tpOutline);
  finally
    toks.Free;
  end;
end;
```

(b) `TyApplyDeclaration` 里把现有 `border-radius` 分支:

```pascal
  else if prop = 'border-radius' then
  begin
    AStyle.BorderRadius := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpBorderRadius);
  end
```

替换为:

```pascal
  else if prop = 'border-radius' then
  begin
    ApplyBorderRadius(AStyle, raw, Vars);
  end
```

并在 `opacity` 分支之前加两个新分支:

```pascal
  else if prop = 'outline' then
  begin
    ApplyOutline(AStyle, raw, Vars);
  end
  else if prop = 'outline-offset' then
  begin
    AStyle.OutlineOffset := TyEvalLength(raw, Vars);
    // offset is meaningful only alongside 'outline'; it does not itself set tpOutline
  end
```

- [ ] **Step 4: 运行测试通过**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 六个新用例 PASS;现有 StyleModel 用例(含 1 值 `border-radius`)保持绿。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.StyleModel.pas tests/test.StyleModel.pas
git commit -m "feat(tycontrols): parse 4-value border-radius + outline/outline-offset (theme-customizable)"
```

---

### Task 4: Painter per-corner 重载

**Files:**
- Modify: `source/tyControls.Painter.pas` (`FillBackground`/`StrokeBorder` 增 `TTyCorners` 重载)
- Test: `tests/test.painter.pas`

- [ ] **Step 1: 写失败测试** (加到 `tests/test.painter.pas`,参照其 GetPixel 探针风格)

```pascal
procedure TestPerCornerTopRoundBottomSquare;
{ border-radius 6 6 0 0: top corners rounded away (white backdrop shows),
  bottom corners square (green fill reaches the corner). Discriminate on red:
  white R=255 (rounded corner), green fill R=$20 (square corner). }
var
  P: TTyPainter; bmp: TBitmap; reread: TBGRABitmap;
  fill: TTyFill; r: TRect; pxTL, pxBL: TBGRAPixel;
begin
  bmp := TBitmap.Create; P := TTyPainter.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(40, 40);
    bmp.Canvas.Brush.Color := clWhite;       // white backdrop
    bmp.Canvas.FillRect(0, 0, 40, 40);
    r := Rect(0, 0, 40, 40);
    fill := Default(TTyFill);
    fill.Kind := tfkSolid;
    fill.Color := TyRGB($20, $C0, $40);       // green, red channel = $20
    P.BeginPaint(bmp.Canvas, r, 96);
    P.FillBackground(r, fill, TyCorners(6, 6, 0, 0));
    P.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      pxTL := reread.GetPixel(0, 0);          // top-left: rounded -> white
      pxBL := reread.GetPixel(0, 39);         // bottom-left: square -> green
      AssertTrue('top-left rounded (white shows): red > 200', pxTL.red > 200);
      AssertTrue('bottom-left square (green fill): red < 128', pxBL.red < 128);
    finally reread.Free; end;
  finally P.Free; bmp.Free; end;
end;
```

Register `TestPerCornerTopRoundBottomSquare` in the painter test case's `published` section.

- [ ] **Step 2: 运行确认失败/不编译**

Run: `lazbuild tests/tytests.lpi`
Expected: 编译失败(`FillBackground(...,TTyCorners)` 重载不存在)。

- [ ] **Step 3: 实现** (`source/tyControls.Painter.pas`)

(a) interface 的 `TTyPainter` 里,给现有两个方法加 `overload`,并各加一个 `TTyCorners` 版本声明:

```pascal
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer); overload;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; const ACorners: TTyCorners); overload;
    procedure StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor); overload;
    procedure StrokeBorder(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor); overload;
```

(b) implementation:把现有 `TTyPainter.FillBackground(...; ARadiusLogical: Integer)` 的**整段函数体**替换为委托:

```pascal
procedure TTyPainter.FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer);
begin
  FillBackground(ARect, AFill, TyUniformCorners(ARadiusLogical));
end;
```

并新增 per-corner 版本(把原实现迁过来,改用每角方化 options):

```pascal
procedure TTyPainter.FillBackground(const ARect: TRect; const AFill: TTyFill; const ACorners: TTyCorners);
var
  r: Integer;
  opts: TRoundRectangleOptions;
  px: TBGRAPixel;
  p1f, p2f: TPointF;
  grad: TBGRAGradientScanner;
begin
  if FBmp = nil then Exit;
  r := ACorners.TL;
  if ACorners.TR > r then r := ACorners.TR;
  if ACorners.BR > r then r := ACorners.BR;
  if ACorners.BL > r then r := ACorners.BL;
  r := Scale(r);
  opts := [];
  if ACorners.TL <= 0 then Include(opts, rrTopLeftSquare);
  if ACorners.TR <= 0 then Include(opts, rrTopRightSquare);
  if ACorners.BR <= 0 then Include(opts, rrBottomRightSquare);
  if ACorners.BL <= 0 then Include(opts, rrBottomLeftSquare);
  case AFill.Kind of
    tfkSolid:
      begin
        px := TyColorToBGRA(AFill.Color);
        if r <= 0 then
          FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, px, dmDrawWithTransparency)
        else
          FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, px, opts);
      end;
    tfkNone: ;
    tfkLinearGradient:
      begin
        GradientEndpoints(ARect, AFill.GradAngleDeg, p1f, p2f);
        grad := TBGRAGradientScanner.Create(TyColorToBGRA(AFill.GradFrom), TyColorToBGRA(AFill.GradTo), gtLinear, p1f, p2f);
        try
          if r <= 0 then
            FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, grad, dmDrawWithTransparency, daNearestNeighbor)
          else
            FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, grad, opts);
        finally
          grad.Free;
        end;
      end;
    tfkNineSlice: NineSlice(ARect, AFill.ImagePath, AFill.SliceInsets);
  end;
end;
```

(c) 同样把现有 `TTyPainter.StrokeBorder(...; ARadiusLogical, AWidthLogical)` 的函数体替换为委托,并加 per-corner 版本:

```pascal
procedure TTyPainter.StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor);
begin
  StrokeBorder(ARect, TyUniformCorners(ARadiusLogical), AWidthLogical, AColor);
end;

procedure TTyPainter.StrokeBorder(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor);
var
  w, r: Integer;
  opts: TRoundRectangleOptions;
  half: Single;
  px: TBGRAPixel;
  l, t, rr, b: Single;
begin
  if FBmp = nil then Exit;
  w := Scale(AWidthLogical);
  if w <= 0 then Exit;
  r := ACorners.TL;
  if ACorners.TR > r then r := ACorners.TR;
  if ACorners.BR > r then r := ACorners.BR;
  if ACorners.BL > r then r := ACorners.BL;
  r := Scale(r);
  opts := [];
  if ACorners.TL <= 0 then Include(opts, rrTopLeftSquare);
  if ACorners.TR <= 0 then Include(opts, rrTopRightSquare);
  if ACorners.BR <= 0 then Include(opts, rrBottomRightSquare);
  if ACorners.BL <= 0 then Include(opts, rrBottomLeftSquare);
  px := TyColorToBGRA(AColor);
  half := w / 2;
  l := ARect.Left + half;
  t := ARect.Top + half;
  rr := ARect.Right - 1 - half;
  b := ARect.Bottom - 1 - half;
  if r <= 0 then
    FBmp.RectangleAntialias(l, t, rr, b, px, w)
  else
    FBmp.RoundRectAntialias(l, t, rr, b, r, r, px, w, opts);
end;
```

> 注意:`TRoundRectangleOptions` / `rr*Square` 来自 `BGRABitmapTypes`(已在 `uses`)。委托后,旧 1 值调用走 `TyUniformCorners` → 与原渲染逐像素一致(已有 `test.painter` 用例守护)。

- [ ] **Step 4: 运行测试通过**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 新 per-corner 用例 PASS;**现有 `test.painter` 全部保持绿**(若梯度 AA 出现差异,把梯度分支的 `opts` 改为 `opts + [rrDefault]` 再跑)。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.Painter.pas tests/test.painter.pas
git commit -m "feat(tycontrols): per-corner FillBackground/StrokeBorder overloads (rr*Square)"
```

---

### Task 5: DrawFrame 用每角半径 + 画焦点环

**Files:**
- Modify: `source/tyControls.Base.pas:171-182` 和 `:314-325`(两处 `DrawFrame`)
- Test: `tests/test.base.drawframe.pas`

- [ ] **Step 1: 写失败测试** (加到 `tests/test.base.drawframe.pas`;`TDrawFrameProbe` 是 `TTyCustomControl` 子类,已暴露 `RunDrawFrame`)

```pascal
procedure TestPerCornerBackgroundViaDrawFrame;
{ A style with Radius 6 6 0 0 must render top-left rounded (white) and
  bottom-left square (green) through DrawFrame. }
var
  probe: TDrawFrameProbe; painter: TTyPainter; bmp: TBitmap;
  style: TTyStyleSet; r: TRect; pxTL, pxBL: TBGRAPixel; reread: TBGRABitmap;
begin
  bmp := TBitmap.Create; probe := TDrawFrameProbe.Create(nil); painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40);
    r := Rect(0, 0, 40, 40);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(r);
    style := EmptyStyleSet;
    style.Background.Kind := tfkSolid;
    style.Background.Color := TyRGB($20, $C0, $40);
    Include(style.Present, tpBackground);
    style.Radius := TyCorners(6, 6, 0, 0);
    Include(style.Present, tpBorderRadius);
    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      pxTL := reread.GetPixel(0, 0);
      pxBL := reread.GetPixel(0, 39);
      AssertTrue('DrawFrame top-left rounded (white): red>200', pxTL.red > 200);
      AssertTrue('DrawFrame bottom-left square (green): red<128', pxBL.red < 128);
    finally reread.Free; end;
  finally painter.Free; probe.Free; bmp.Free; end;
end;

procedure TestFocusRingDrawnWhenOutlinePresent;
{ outline present -> a red ring is drawn near the inset edge; absent -> not.
  Probe (1,20) on the left edge. Ring red (FF0000) -> green<128; white -> green>128. }
var
  probe: TDrawFrameProbe; painter: TTyPainter; bmp: TBitmap;
  style: TTyStyleSet; r: TRect; px: TBGRAPixel; reread: TBGRABitmap;
begin
  // ring present
  bmp := TBitmap.Create; probe := TDrawFrameProbe.Create(nil); painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40); r := Rect(0, 0, 40, 40);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(r);
    style := EmptyStyleSet;
    style.OutlineColor := TyRGB($FF, $00, $00);
    style.OutlineWidth := 2;
    style.OutlineOffset := 0;
    Include(style.Present, tpOutline);
    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(1, 20);
      AssertTrue('focus ring drawn: green<128 (red ring)', px.green < 128);
    finally reread.Free; end;
  finally painter.Free; probe.Free; bmp.Free; end;

  // ring absent
  bmp := TBitmap.Create; probe := TDrawFrameProbe.Create(nil); painter := TTyPainter.Create;
  try
    bmp.SetSize(40, 40); r := Rect(0, 0, 40, 40);
    bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(r);
    style := EmptyStyleSet;   // no tpOutline
    painter.BeginPaint(bmp.Canvas, r, 96);
    probe.RunDrawFrame(painter, r, style);
    painter.EndPaint;
    reread := TBGRABitmap.Create(bmp);
    try
      px := reread.GetPixel(1, 20);
      AssertTrue('no ring: green>128 (white)', px.green > 128);
    finally reread.Free; end;
  finally painter.Free; probe.Free; bmp.Free; end;
end;
```

Register both in `TDrawFrameTest`'s `published` section.

- [ ] **Step 2: 运行确认失败**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 两用例 FAIL(DrawFrame 仍用 `BorderRadius` 单值;未画焦点环)。

- [ ] **Step 3: 实现** —— `source/tyControls.Base.pas` 的**两处** `DrawFrame`(`TTyGraphicControl` 与 `TTyCustomControl`)函数体**整体**替换为(两处一致):

```pascal
procedure T<...>Control.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
var
  corners, ringCorners: TTyCorners;
  off: Integer;
  ringRect: TRect;
begin
  if tpOpacity in AStyle.Present then
    APainter.Opacity := AStyle.Opacity;
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  corners := TyEffectiveCorners(AStyle);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, corners);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0)
     and not ((tpBorderStyle in AStyle.Present) and (AStyle.BorderStyle = tbsNone)) then
    APainter.StrokeBorder(ARect, corners, AStyle.BorderWidth, AStyle.BorderColor);
  // Focus ring: only present when a ':focus { outline: ... }' rule resolved.
  if (tpOutline in AStyle.Present) and (AStyle.OutlineWidth > 0) then
  begin
    off := APainter.Scale(AStyle.OutlineOffset);
    ringRect := Rect(ARect.Left + off, ARect.Top + off, ARect.Right - off, ARect.Bottom - off);
    ringCorners.TL := corners.TL - AStyle.OutlineOffset; if ringCorners.TL < 0 then ringCorners.TL := 0;
    ringCorners.TR := corners.TR - AStyle.OutlineOffset; if ringCorners.TR < 0 then ringCorners.TR := 0;
    ringCorners.BR := corners.BR - AStyle.OutlineOffset; if ringCorners.BR < 0 then ringCorners.BR := 0;
    ringCorners.BL := corners.BL - AStyle.OutlineOffset; if ringCorners.BL < 0 then ringCorners.BL := 0;
    APainter.StrokeBorder(ringRect, ringCorners, AStyle.OutlineWidth, AStyle.OutlineColor);
  end;
end;
```

> 保留两处分别属于 `TTyGraphicControl` / `TTyCustomControl`,只是函数名前缀不同,函数体相同。`TyEffectiveCorners` 来自 `tyControls.Types`(已在 `uses`)。

- [ ] **Step 4: 运行测试通过 + 关键回归**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 两新用例 + 既有 `TestSolidBackgroundCenterPixel`/`TestOpacityDimsControl`/`TestBorderStyleNoneSuppressesBorder` 全绿;CheckBox/Radio/Panel 等控件像素测试保持绿(1 值半径经 `TyEffectiveCorners` 与旧路径一致)。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.Base.pas tests/test.base.drawframe.pas
git commit -m "feat(tycontrols): DrawFrame renders per-corner radius + focus-ring outline"
```

---

### Task 6: TabControl 表头主题驱动顶部圆角

**Files:**
- Modify: `source/tyControls.TabControl.pas:1047`
- Test: `tests/test.tabcontrol.pas`

- [ ] **Step 1: 写失败测试** (加到 `tests/test.tabcontrol.pas`。若该文件已有渲染访问子类则复用;否则用此处的访问子类。该测试加载一个把 `TyTab` 设为顶部圆角的主题,渲染整控件,验证某个 Tab 表头的左下角是 Tab 背景填充(方角),左上角被圆掉。)

```pascal
type
  TTabRenderAccess = class(TTyTabControl)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

procedure TTabRenderAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TTabControlTest.TestTabHeaderTopCornerRoundedFromTheme;
var
  ctl: TTyStyleController; tabs: TTabRenderAccess;
  bmp: TBitmap; reread: TBGRABitmap; pxTopCorner: TBGRAPixel;
begin
  ctl := TTyStyleController.Create(nil);
  bmp := TBitmap.Create;
  try
    // Tab fill = pure blue so it is unmistakable; top corners rounded, bottom square.
    ctl.Model.LoadFromCss(
      'TyTabControl { background:#FFFFFF; border-color:#000000; border-width:1px; }' +
      'TyTab { background:#0000FF; color:#000000; padding:4px; border-radius:8px 8px 0 0; }');
    tabs := TTabRenderAccess.Create(nil);
    try
      tabs.Controller := ctl;
      tabs.Font.PixelsPerInch := 96;
      tabs.AddTab('AAAA');
      tabs.AddTab('BBBB');
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(200, 120);
      bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0, 0, 200, 120);
      tabs.DoRenderTo(bmp.Canvas, Rect(0, 0, 200, 120), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        // The very top-left pixel of the first tab header must NOT be the solid
        // blue fill (it has been rounded away). Probe (0,0): blue B=255 would mean
        // square; rounded -> backdrop/white, B<200.
        pxTopCorner := reread.GetPixel(0, 0);
        AssertTrue('tab top-left rounded away (not solid blue)', pxTopCorner.blue < 200);
      finally reread.Free; end;
    finally tabs.Free; end;
  finally bmp.Free; ctl.Free; end;
end;
```

Register `TestTabHeaderTopCornerRoundedFromTheme` and add `TStyleController`/`Graphics`/`BGRABitmap` to the unit's `uses` if missing.

> 注:Tab 表头在 `RenderTo` 中布局于控件左上区域,首个表头左上角对齐 (0,0)。若该项目里首表头不在 (0,0)(存在表头内边距),把探针点改为 `tabs` 第一个 `FHeaderRects[0]` 的左上角——用已暴露的几何助手取坐标;否则保持 (0,0)。

- [ ] **Step 2: 运行确认失败**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: FAIL(表头当前用硬编码 `0` 半径 → 方角 → (0,0) 是纯蓝)。

- [ ] **Step 3: 实现** —— `source/tyControls.TabControl.pas` 第 1047 行附近,把:

```pascal
        P.FillBackground(HdrRect, TabStyle.Background, 0);
```

改为(用该 Tab 解析样式的每角半径,主题驱动):

```pascal
        P.FillBackground(HdrRect, TabStyle.Background, TyEffectiveCorners(TabStyle));
```

确认单元 `uses` 含 `tyControls.Types`(`TyEffectiveCorners` 所在;通常已在)。

- [ ] **Step 4: 运行测试通过**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 新用例 PASS;`test.tabcontrol*` 既有用例保持绿(默认无 4 值半径时 `TyEffectiveCorners` 退化为 0/uniform,与原 `0` 一致)。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.TabControl.pas tests/test.tabcontrol.pas
git commit -m "feat(tycontrols): tab header corners are theme-driven (TyEffectiveCorners)"
```

---

### Task 7: 默认主题落 A(圆角统一 + 焦点环)

**Files:**
- Modify: `themes/light.tycss`、`themes/dark.tycss`、`themes/showcase.tycss`、`source/tyControls.DefaultTheme.pas`
- Test: `tests/test.defaulttheme.pas`

- [ ] **Step 1: 写失败测试** (加到 `tests/test.defaulttheme.pas`)

```pascal
procedure TestBuiltinTitleBarTopRoundedTab;
var m: TTyStyleModel; sTitle, sTab: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    sTitle := m.ResolveStyle('TyTitleBar', '', []);
    AssertTrue('titlebar tl rounded', sTitle.Radius.TL > 0);
    AssertEquals('titlebar bl square', 0, sTitle.Radius.BL);
    sTab := m.ResolveStyle('TyTab', '', []);
    AssertTrue('tab tr rounded', sTab.Radius.TR > 0);
    AssertEquals('tab br square', 0, sTab.Radius.BR);
  finally m.Free; end;
end;

procedure TestBuiltinFocusRingOnButton;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    s := m.ResolveStyle('TyButton', '', [tysFocused]);
    AssertTrue('button focus outline present', tpOutline in s.Present);
    AssertTrue('focus outline width > 0', s.OutlineWidth > 0);
  finally m.Free; end;
end;
```

Register both. (`TestBuiltinMatchesLightTheme` 已存在,会强制 builtin==light。)

- [ ] **Step 2: 运行确认失败**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 两新用例 FAIL(标题栏/Tab 还没有顶部圆角;Button 还没 outline)。`TestBuiltinMatchesLightTheme` 此刻仍 PASS(两边都还旧)。

- [ ] **Step 3: 实现 —— `themes/light.tycss` 编辑:**

(3a) `:root` 块在 `--radius: 6px;` 之后加一行:

```css
  --focus-ring: var(--accent);
```

(3b) `TyButton:focus` 行改为(加 outline,保留描边变化):

```css
TyButton:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
```

(3c) 给以下 typeKey 的 `:focus` 行同样追加 `outline: 2px var(--focus-ring);`:`TyEdit:focus`、`TyComboBox:focus`、`TyListBox:focus`、`TySpinEdit:focus`、`TyMemo:focus`。例如:

```css
TyEdit:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
```

(3d) 为缺 `:focus` 规则的可聚焦控件**新增** `:focus` 规则行(放在各自的状态规则附近):

```css
TyCheckBox:focus    { outline: 2px var(--focus-ring); }
TyRadioButton:focus { outline: 2px var(--focus-ring); }
TyToggleSwitch:focus { outline: 2px var(--focus-ring); }
TyTrackBar:focus    { outline: 2px var(--focus-ring); }
TyTabControl:focus  { outline: 2px var(--focus-ring); }
```

(3e) `TyTitleBar` 块加一行顶部圆角:

```css
  border-radius: var(--radius) var(--radius) 0 0;
```

(3f) `TyTab` 块加一行顶部圆角(在 `padding: 4px;` 之后):

```css
  border-radius: var(--radius) var(--radius) 0 0;
```

> 不动 `TyCaptionButton: 0px`(标题栏内的系统按钮保持方角命中区,是有意例外);不动 ToggleSwitch `12px`、TrackThumb `8px`、CheckBox `3px`、Radio `8px`、ScrollBar `4px`、TrackBar `3px`(几何性圆角)。

- [ ] **Step 4: 实现 —— 同步 `source/tyControls.DefaultTheme.pas`:** 对 `TyBuiltinThemeCss` 字符串做与 3a–3f **逐字一致**的修改(每条加成 `'...' + LineEnding +` 形式)。例如 3a:

```pascal
    '  --radius:     6px;' + LineEnding +
    '  --focus-ring: var(--accent);' + LineEnding +
```

3e(TyTitleBar 块内,`'  font-weight: 700;'` 行之前或 `border-width` 之后)加:

```pascal
    '  border-radius: var(--radius) var(--radius) 0 0;' + LineEnding +
```

其余 3b/3c/3d/3f 同理。**务必保证** `NormalizeCss(light.tycss) == NormalizeCss(TyBuiltinThemeCss)`(由 `TestBuiltinMatchesLightTheme` 守护:它 TrimRight 每行后整体 Trim 比较,故只需"同样的行、同样的顺序、同样的非尾随空白内容")。

- [ ] **Step 5: 实现 —— `themes/dark.tycss` 与 `themes/showcase.tycss`:** 做与 3a–3f **结构相同**的编辑——
  - `:root` 加 `--focus-ring: var(--accent);`(若该主题强调色变量名不同,用其对应强调色变量);
  - 同样给上述可聚焦 typeKey 的 `:focus` 追加/新增 `outline: 2px var(--focus-ring);`;
  - `TyTitleBar`、`TyTab` 各加 `border-radius: var(--radius) var(--radius) 0 0;`。
  这两个文件**不**被 builtin-sync 测试约束,但要保持各自既有色值不变,只做上述叠加。

- [ ] **Step 6: 运行测试通过**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: `TestBuiltinTitleBarTopRoundedTab`、`TestBuiltinFocusRingOnButton`、`TestBuiltinMatchesLightTheme` 全绿;`test.themes`(三主题加载/解析)保持绿。

- [ ] **Step 7: Commit**

```bash
git add themes/light.tycss themes/dark.tycss themes/showcase.tycss source/tyControls.DefaultTheme.pas tests/test.defaulttheme.pas
git commit -m "feat(tycontrols): default themes adopt unified radius (titlebar/tab top-rounded) + focus ring"
```

---

## 工作流 B — 行为基线

### Task 8: 键盘激活 —— Button(Space/Enter)

**Files:**
- Modify: `source/tyControls.Button.pas`
- Test: `tests/test.button.pas`

- [ ] **Step 1: 写失败测试** (加到 `tests/test.button.pas`。给已有 `TTyButtonAccess` 加 `DoKeyDown`,新增两个用例)

给 `TTyButtonAccess` 增公开包装:

```pascal
  TTyButtonAccess = class(TTyButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
  end;
...
procedure TTyButtonAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;
```

新用例(`uses` 加 `LCLType`):

```pascal
procedure TestSpaceKeyFiresClick;
var F: TCustomForm; B: TTyButtonAccess; K: Word;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButtonAccess.Create(F); B.Parent := F; B.OnClick := @HandleClick;
    K := VK_SPACE; B.DoKeyDown(K, []);
    AssertEquals('space fired click', 1, FClicked);
    AssertEquals('space consumed', 0, K);
    K := VK_RETURN; B.DoKeyDown(K, []);
    AssertEquals('enter fired click', 2, FClicked);
  finally F.Free; end;
end;

procedure TestDisabledSwallowsKeyNoClick;
var F: TCustomForm; B: TTyButtonAccess; K: Word;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButtonAccess.Create(F); B.Parent := F; B.OnClick := @HandleClick;
    B.Enabled := False;
    K := VK_SPACE; B.DoKeyDown(K, []);
    AssertEquals('disabled: no click', 0, FClicked);
  finally F.Free; end;
end;
```

Register both names.

- [ ] **Step 2: 运行确认失败**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 编译失败(`DoKeyDown` 调用的 `KeyDown` 未被 Button 覆写……可编译,因 `KeyDown` 继承自 TWinControl)→ 实为运行 FAIL(`FClicked` 仍 0)。

- [ ] **Step 3: 实现** (`source/tyControls.Button.pas`)

protected 段声明:

```pascal
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
```

实现(放在 `Click` 之后):

```pascal
procedure TTyButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if (Key = VK_SPACE) or (Key = VK_RETURN) then
  begin
    Click;            // Click already guards Enabled and fires OnClick
    Key := 0;
  end;
end;
```

`Button.pas` 已 `uses LCLType`(`VK_*` 可用)。

- [ ] **Step 4: 运行测试通过**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 两用例 PASS;`TestOnClickFires` 等保持绿。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.Button.pas tests/test.button.pas
git commit -m "feat(tycontrols): TTyButton keyboard activation (Space/Enter -> Click)"
```

---

### Task 9: 键盘激活 —— CheckBox(Space)+ RadioButton(Space)

**Files:**
- Modify: `source/tyControls.CheckBox.pas`(`TTyCheckBox` 与 `TTyRadioButton`)
- Test: `tests/test.checkbox.pas`、`tests/test.radiobutton.pas`

- [ ] **Step 1: 写失败测试** (test.checkbox.pas:访问子类 + 用例;`uses` 加 `LCLType`、`Forms`、`Controls`)

```pascal
type
  TTyCheckBoxAccess = class(TTyCheckBox)
  public
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
  end;
...
procedure TTyCheckBoxAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TCheckBoxTest.TestSpaceTogglesChecked;
var F: TCustomForm; C: TTyCheckBoxAccess; K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F); C.Parent := F;
    AssertFalse('starts unchecked', C.Checked);
    K := VK_SPACE; C.DoKeyDown(K, []);
    AssertTrue('space checked it', C.Checked);
    AssertEquals('space consumed', 0, K);
  finally F.Free; end;
end;

procedure TCheckBoxTest.TestDisabledSpaceNoToggle;
var F: TCustomForm; C: TTyCheckBoxAccess; K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F); C.Parent := F; C.Enabled := False;
    K := VK_SPACE; C.DoKeyDown(K, []);
    AssertFalse('disabled: not toggled', C.Checked);
  finally F.Free; end;
end;
```

(test.radiobutton.pas:对应 `TTyRadioButtonAccess` + `TestSpaceSelectsRadio`,断言 `Checked` 由 False→True。)

Register the new names.

- [ ] **Step 2: 运行确认失败** —— `./tests/tytests`:新用例 FAIL(Space 无效)。

- [ ] **Step 3: 实现** (`source/tyControls.CheckBox.pas`)

`TTyCheckBox` protected 加 `procedure KeyDown(var Key: Word; Shift: TShiftState); override;`,实现:

```pascal
procedure TTyCheckBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if Key = VK_SPACE then
  begin
    Click;            // toggles Checked + fires OnClick (guards Enabled)
    Key := 0;
  end;
end;
```

`TTyRadioButton` 同样加 `KeyDown` override:

```pascal
procedure TTyRadioButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if Key = VK_SPACE then
  begin
    Click;            // selects (Checked:=True, unchecks siblings) + OnClick
    Key := 0;
  end;
end;
```

确认 `CheckBox.pas` 已 `uses LCLType`(`VK_SPACE`)——是。

- [ ] **Step 4: 运行测试通过** —— 全量绿。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.CheckBox.pas tests/test.checkbox.pas tests/test.radiobutton.pas
git commit -m "feat(tycontrols): keyboard activation for TTyCheckBox and TTyRadioButton (Space)"
```

---

### Task 10: 键盘激活 —— ToggleSwitch 补 Enter

**Files:**
- Modify: `source/tyControls.ToggleSwitch.pas:174-183`
- Test: `tests/test.toggleswitch.pas`

- [ ] **Step 1: 写失败测试** (test.toggleswitch.pas:若无访问子类则加一个暴露 `KeyDown`,新增)

```pascal
procedure TToggleTest.TestEnterTogglesChecked;
var F: TCustomForm; T: TTyToggleSwitchAccess; K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    T := TTyToggleSwitchAccess.Create(F); T.Parent := F;
    AssertFalse('off', T.Checked);
    K := VK_RETURN; T.DoKeyDown(K, []);
    AssertTrue('enter toggled on', T.Checked);
    AssertEquals('enter consumed', 0, K);
  finally F.Free; end;
end;
```

(若文件无 `TTyToggleSwitchAccess`,加 `type TTyToggleSwitchAccess = class(TTyToggleSwitch) public procedure DoKeyDown(var Key: Word; Shift: TShiftState); begin KeyDown(Key, Shift); end; end;`。`uses` 加 `LCLType`/`Forms`/`Controls`。)

- [ ] **Step 2: 运行确认失败** —— `VK_RETURN` 当前不切换 → FAIL。

- [ ] **Step 3: 实现** —— `tyControls.ToggleSwitch.pas` 把:

```pascal
  if Key = VK_SPACE then
  begin
    Toggle;
    Key := 0;
  end;
```

改为:

```pascal
  if (Key = VK_SPACE) or (Key = VK_RETURN) then
  begin
    Toggle;
    Key := 0;
  end;
```

- [ ] **Step 4: 运行测试通过** —— 全量绿(既有 Space 用例不受影响)。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.ToggleSwitch.pas tests/test.toggleswitch.pas
git commit -m "feat(tycontrols): TTyToggleSwitch Enter also toggles (parity with Space)"
```

---

### Task 11: 统一 published 基线属性

**Files:**
- Modify: `source/tyControls.Base.pas`(两个基类 published 段)
- Test: `tests/test.base.pas`

- [ ] **Step 1: 写失败测试** (test.base.pas;`uses` 加 `TypInfo`,以及若干控件单元 `tyControls.Panel`、`tyControls.GroupBox`、`tyControls.ComboBox`)

```pascal
procedure TBaseTest.TestBaselinePropertiesPublished;
{ Baseline props must be PUBLISHED (streamable + Object Inspector) on controls
  that previously omitted them. Uses RTTI: GetPropInfo returns nil for a
  non-published property. }
var P: TTyPanel; G: TTyGroupBox; C: TTyComboBox;
begin
  P := TTyPanel.Create(nil);
  G := TTyGroupBox.Create(nil);
  C := TTyComboBox.Create(nil);
  try
    AssertTrue('Panel.Font published',    GetPropInfo(P, 'Font') <> nil);
    AssertTrue('Panel.Hint published',    GetPropInfo(P, 'Hint') <> nil);
    AssertTrue('Panel.ShowHint published',GetPropInfo(P, 'ShowHint') <> nil);
    AssertTrue('GroupBox.Font published', GetPropInfo(G, 'Font') <> nil);
    AssertTrue('ComboBox.Font published', GetPropInfo(C, 'Font') <> nil);
    AssertTrue('Panel.TabOrder published (TWinControl)', GetPropInfo(P, 'TabOrder') <> nil);
  finally P.Free; G.Free; C.Free; end;
end;
```

Register `TestBaselinePropertiesPublished`.

- [ ] **Step 2: 运行确认失败** —— `Panel.Font`/`Hint` 等未 published → `GetPropInfo` 返回 nil → FAIL。

- [ ] **Step 3: 实现** (`source/tyControls.Base.pas`)

`TTyGraphicControl` 的 `published` 段(当前只有 `StyleClass`、`Controller`)补:

```pascal
  published
    property Enabled;
    property Font;
    property Hint;
    property ShowHint;
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
```

`TTyCustomControl` 的 `published` 段补(它是 `TCustomControl`/`TWinControl`,有 TabOrder/TabStop):

```pascal
  published
    property Enabled;
    property Font;
    property Hint;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property StyleClass: string read FStyleClass write SetStyleClass;
    property Controller: TTyStyleController read FController write SetController;
```

> 派生控件里已存在的 `property Enabled; property Font;` 重复声明无害(Pascal 允许 published 重声明),本任务不动它们;原本**遗漏** Font/Enabled 的控件(Panel/GroupBox/ComboBox 等)现经基类继承获得。`Hint`/`ShowHint`/`TabOrder` 自 `TControl`/`TWinControl`,只是提升为 published。

- [ ] **Step 4: 运行测试通过 + 全量回归**

Run: `lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain`
Expected: 新用例 PASS;全套件绿。再跑 `bash scripts/build-matrix.sh` 确认两个包 + 全部示例 + 测试器都能构建(published 提升可能让某些 `.lfm` 现在可序列化新属性——示例 `.lfm` 不含这些则无影响)。

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.Base.pas tests/test.base.pas
git commit -m "feat(tycontrols): publish baseline Enabled/Font/Hint/ShowHint/TabOrder on base controls"
```

---

### Task 12: 文档 + 收口

**Files:**
- Modify: `docs/tycss-reference.md`
- Test: 全量回归 + 构建矩阵

- [ ] **Step 1: 文档** —— 在 `docs/tycss-reference.md` 的属性/函数表补:
  - `border-radius`:支持 1 值(四角)与 4 值 `tl tr br bl`(标准 CSS 顺序);示例 `border-radius: 6px 6px 0 0;`(顶部圆角)。
  - `outline`:`outline: <width> <color>` 焦点环;`outline-offset: <len>`;通常写在 `:focus` 里;示例 `TyButton:focus { outline: 2px var(--focus-ring); }`。说明它画在控件内侧(自绘控件无外侧空间)。
  - `--focus-ring` 语义令牌(默认 `var(--accent)`),买家覆盖即可改焦点环色;`outline: 0` 关闭焦点环;`border-radius: 0` 改回直角。
  - 注明仍不支持:per-corner 长写 `border-top-left-radius` 等、百分比/椭圆角(`/` 语法)。

- [ ] **Step 2: 全量回归 + 构建矩阵 + heaptrc**

Run:
```bash
lazbuild tests/tytests.lpi && ./tests/tytests -a --format=plain
bash scripts/build-matrix.sh
```
Expected: 测试全绿;矩阵 `== matrix OK ==`。若环境启用了 heaptrc,确认 0 泄漏(新增字段为值类型,无新分配)。

- [ ] **Step 3: Commit**

```bash
git add docs/tycss-reference.md
git commit -m "docs(tycontrols): document 4-value border-radius, outline/outline-offset, --focus-ring"
```

---

## 完成后

- 全套件 + 构建矩阵 + heaptrc 0;终审(reviewer 跑 per-corner + 焦点环像素探针;确认非 titlebar/tab 控件渲染零变化;确认三主题切换正常)。
- 本地快进合并 `main` + 删 `phase0-baseline` 分支(项目惯例)。
- 更新记忆:Phase 0 完成;下一程为"逐批控件高频专属属性"(批① 文本类起)。
- 同步收尾文档漂移(可并入或留作小提交):README/getting-started/memo.md 关于 Memo 能力的过期描述、KNOWN_GAPS 标题、tycss-reference 的 alpha()/重复选择器对账——这些是审计点名的独立小修,不阻塞 Phase 0。

---

## Self-Review(规划者自查,已执行)

- **Spec 覆盖**:§3 工作流 A(A1 per-corner→Task 3/4/5、A2 outline→Task 3/5、A3 主题→Task 7、TabControl 驱动→Task 6;Types/merge 地基→Task 1/2);工作流 B(B1 键盘→Task 8/9/10、B2 published→Task 11);§6 验收(各 Task 测试 + Task 12 矩阵/文档)。无遗漏。
- **类型/签名一致**:`TyCorners`/`TyUniformCorners`/`TyEffectiveCorners`、`TTyStyleSet.Radius`、`OutlineColor/Width/Offset`、`tpOutline`、`FillBackground/StrokeBorder(...,TTyCorners)` 重载在 Task 1/2/3/4 定义,Task 5/6/7 一致引用。
- **无占位符**:每个代码步给出完整 Pascal/CSS;主题 dark/showcase 以"与 3a–3f 同构的具体编辑"指明,builtin 同步由既有 `TestBuiltinMatchesLightTheme` 强约束。
- **向后兼容**:1 值 `border-radius`→`TyUniformCorners`;`TyEffectiveCorners` 兜底代码构建的样式(ToggleSwitch 胶囊);published 重声明无害。现有像素测试在 Task 4/5 步骤里显式要求保持绿。
