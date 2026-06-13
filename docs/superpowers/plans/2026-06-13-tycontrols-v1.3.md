# TyControls v1.3 — 内置默认皮肤 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 引擎内置一套默认皮肤,使控件在未加载任何主题时(无 Controller / 设计器中)也能正常显示;已加载主题按 typeKey 在其之上覆盖,完整主题渲染零变化。

**Architecture:** `TTyStyleModel` 内置一个始终存在的"基础层"(`FBaseRules`,Create 时由内嵌的 `TyBuiltinThemeCss` 解析填充)。`ResolveStyle` 改为两层:仅当用户层对该 typeKey **无任何规则**时才叠加基础层,然后把用户层合并在上。这样完整主题(定义了所有 typeKey)会让基础层对每个控件整体失效 ⇒ 无属性渗漏、渲染与现状一致;部分主题/无主题则回退到默认皮肤。

**Tech Stack:** Free Pascal / Lazarus / LCL / BGRABitmap;CSS-lite 引擎;FPCUnit 测试(`tests/tytests.lpi` + `tytests.lpr`)。

**关键约束(记忆):**
- 几何/像素测试必须 `Font.PixelsPerInch := 96`(macOS 默认 72)。
- 测试构建走 `lazbuild tests/tytests.lpi`(不能编 bare .lpr);新测试单元要加进 `tytests.lpr` 的 uses。
- 链接 LCL/BGRA 的程序首个 unit 必须是 `Interfaces`(tytests.lpr 已满足)。
- 子代理派发以 "DIRECT task. Do NOT invoke any brainstorming/planning skill, do NOT create plan files." 开头。

---

## File Structure

- **Create** `source/tyControls.DefaultTheme.pas` — 单一职责:返回内嵌的浅色默认 `.tycss` 文本。无其它逻辑,不依赖 StyleModel(避免循环 uses)。
- **Modify** `source/tyControls.StyleModel.pas` — 新增内置基础层 + 两层 `ResolveStyle`;重构 find/add/resolve 为按列表参数化。`uses` 增加 `tyControls.DefaultTheme`。
- **Create** `tests/test.defaulttheme.pas` — v1.3 全部新测试(内置内容同步/覆盖、基础层兜底、按 typeKey 抑制、端到端可见性)。
- **Modify** `tests/tytests.lpr` — uses 增加 `test.defaulttheme`。
- **Modify** `tycontrols.lpk` — Files 列表加入新单元(Count 23→24)。
- **Modify** `docs/getting-started.md`, `docs/KNOWN_GAPS.md`, `docs/tycss-reference.md`, `README.md` — 文档同步。

---

## Task 1: 内置默认皮肤单元 + 内容测试

**Files:**
- Create: `source/tyControls.DefaultTheme.pas`
- Create: `tests/test.defaulttheme.pas`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 创建 `source/tyControls.DefaultTheme.pas`**

单元只暴露 `function TyBuiltinThemeCss: string;`。函数体返回 **`themes/light.tycss` 当前文件内容的逐字内嵌副本**(浅色主题,蓝色强调,覆盖全部 16 控件 + 子部件 + TyTitleBar/TyCaptionButton)。

实现方式:把 `themes/light.tycss` 的每一行写成 Pascal 字符串拼接,每行后接 `+ LineEnding +`(light.tycss 不含单引号,无需转义)。骨架如下,**正文必须与 `themes/light.tycss` 一字不差**(由 Step 3/4 的同步测试强制保证):

```pascal
unit tyControls.DefaultTheme;
{$mode objfpc}{$H+}
interface

{ Built-in default skin. Compiled into the binary (no disk dependency) so that
  controls render with a sensible look even when no theme is loaded — e.g. a
  control with no Controller bound, or any control dropped onto a form in the
  Lazarus designer. This text MUST stay byte-identical to themes/light.tycss
  (enforced by test.defaulttheme's sync test). When light.tycss changes, update
  this string to match. }
function TyBuiltinThemeCss: string;

implementation

function TyBuiltinThemeCss: string;
begin
  Result :=
    '/* TyControls — Light theme */' + LineEnding +
    ':root {' + LineEnding +
    '  --accent:     #3B82F6;' + LineEnding +
    // ... 继续逐行内嵌 themes/light.tycss 的完整内容,直到最后一行 ...
    'TyTab:active { background: var(--surface); color: var(--accent); }' + LineEnding;
end;

end.
```

> 实现者:读取 `themes/light.tycss`,把全部 205 行逐行转成上面的拼接形式。最后一行也加 `+ LineEnding`。务必包含 `:root`、所有控件块、注释行。

- [ ] **Step 2: 写失败测试 — 文件创建 `tests/test.defaulttheme.pas`(同步 + 覆盖)**

```pascal
unit test.defaulttheme;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.DefaultTheme;
type
  TBuiltinThemeTest = class(TTestCase)
  private
    function NormalizeCss(const S: string): string;
  published
    procedure TestBuiltinMatchesLightTheme;
    procedure TestBuiltinCoversAllTypeKeys;
  end;
implementation

function TBuiltinThemeTest.NormalizeCss(const S: string): string;
{ Robust to line-ending and trailing-whitespace differences. }
var sl: TStringList; i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Text := S;
    for i := 0 to sl.Count - 1 do
      sl[i] := TrimRight(sl[i]);
    Result := Trim(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TBuiltinThemeTest.TestBuiltinMatchesLightTheme;
{ The embedded built-in skin must stay identical to themes/light.tycss. }
var
  path: string;
  fileText: TStringList;
begin
  path := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes'
    + PathDelim + 'light.tycss';
  AssertTrue('light.tycss must exist for sync check', FileExists(path));
  fileText := TStringList.Create;
  try
    fileText.LoadFromFile(path);
    AssertEquals('built-in skin must equal themes/light.tycss',
      NormalizeCss(fileText.Text), NormalizeCss(TyBuiltinThemeCss));
  finally
    fileText.Free;
  end;
end;

procedure TBuiltinThemeTest.TestBuiltinCoversAllTypeKeys;
{ Parsing the built-in CSS into a model's user layer must resolve every styled
  typeKey with its key property present. }
var
  m: TTyStyleModel;
  procedure AssertBg(const Key: string; AStates: TTyStateSet);
  begin
    AssertTrue(Key + ' must set Background',
      tpBackground in m.ResolveStyle(Key, '', AStates).Present);
  end;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss);
    AssertBg('TyButton', []);
    AssertBg('TyEdit', []);
    AssertBg('TyCheckBox', []);
    AssertBg('TyRadioButton', []);
    AssertBg('TyPanel', []);
    AssertBg('TyComboBox', []);
    AssertBg('TyScrollBar', []);
    AssertBg('TyTitleBar', []);
    AssertBg('TyListBox', []);
    AssertBg('TyListItem', [tysActive]);
    AssertBg('TyProgressBar', []);
    AssertBg('TyProgressFill', []);
    AssertBg('TyToggleSwitch', [tysActive]);
    AssertBg('TyTrackBar', []);
    AssertBg('TyTrackThumb', []);
    AssertBg('TyTabControl', []);
    AssertBg('TyTab', [tysActive]);
    AssertTrue('TyGroupBox must set BorderColor',
      tpBorderColor in m.ResolveStyle('TyGroupBox', '', []).Present);
    AssertTrue('TyLabel must set TextColor',
      tpTextColor in m.ResolveStyle('TyLabel', '', []).Present);
  finally
    m.Free;
  end;
end;

initialization
  RegisterTest(TBuiltinThemeTest);
end.
```

- [ ] **Step 3: 注册测试单元到 `tests/tytests.lpr`**

在 uses 末尾 `test.tabcontrol;` 之前加入 `test.defaulttheme,`(注意逗号/分号)。改为:

```pascal
  test.groupbox,
  test.tabcontrol,
  test.defaulttheme;
```

- [ ] **Step 4: 构建并运行测试**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi && ./tests/tytests --suite=TBuiltinThemeTest --format=plain`
Expected: 2/2 通过(`TestBuiltinMatchesLightTheme`、`TestBuiltinCoversAllTypeKeys`)。若同步测试失败,说明内嵌副本与 light.tycss 有差异 ⇒ 修正 `TyBuiltinThemeCss` 正文直到逐行一致。

- [ ] **Step 5: 全量回归**

Run: `./tests/tytests -a --format=plain 2>&1 | tail -5`
Expected: 全部通过(289 旧 + 2 新 = 291)。

- [ ] **Step 6: Commit**

```bash
git add source/tyControls.DefaultTheme.pas tests/test.defaulttheme.pas tests/tytests.lpr
git commit -m "feat(tycontrols): add built-in default skin (TyBuiltinThemeCss) mirroring light theme"
```

---

## Task 2: StyleModel 内置基础层 + 两层 ResolveStyle

**Files:**
- Modify: `source/tyControls.StyleModel.pas`
- Modify: `tests/test.defaulttheme.pas`

- [ ] **Step 1: 写失败测试 — 追加到 `tests/test.defaulttheme.pas`**

在 `TBuiltinThemeTest` 的 `published` 区追加三个方法声明:

```pascal
    procedure TestEmptyModelFallsBackToBuiltin;
    procedure TestUserTypeKeySuppressesBuiltinNoBleed;
    procedure TestUnstyledTypeKeyStillGetsBuiltin;
```

在 implementation 区追加:

```pascal
procedure TBuiltinThemeTest.TestEmptyModelFallsBackToBuiltin;
{ A fresh model with NO theme loaded must resolve the built-in default skin
  (the core fix: controls are visible with zero configuration). }
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    s := m.ResolveStyle('TyButton', '', []);
    AssertTrue('empty model: TyButton Background present (built-in)',
      tpBackground in s.Present);
    AssertTrue('empty model: TyButton TextColor present (built-in)',
      tpTextColor in s.Present);
    AssertTrue('empty model: solid background', s.Background.Kind = tfkSolid);
    // built-in surface = #FFFFFF (white)
    AssertEquals('built-in surface red', $FF, TyRedOf(s.Background.Color));
    AssertEquals('built-in surface green', $FF, TyGreenOf(s.Background.Color));
    AssertEquals('built-in surface blue', $FF, TyBlueOf(s.Background.Color));
  finally
    m.Free;
  end;
end;

procedure TBuiltinThemeTest.TestUserTypeKeySuppressesBuiltinNoBleed;
{ When the user theme defines ANY rule for a typeKey, the built-in layer for
  that typeKey is suppressed entirely — no property bleeds through. }
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    // user theme sets ONLY background for TyButton (no border/padding/etc.)
    m.LoadFromCss('TyButton { background: #FF0000; }');
    s := m.ResolveStyle('TyButton', '', []);
    AssertTrue('user background present', tpBackground in s.Present);
    AssertEquals('user red wins', $FF, TyRedOf(s.Background.Color));
    AssertEquals('user red wins (green 0)', $00, TyGreenOf(s.Background.Color));
    // built-in TyButton sets border-width/padding/font — these must NOT leak in
    AssertFalse('no built-in border-width bleed', tpBorderWidth in s.Present);
    AssertFalse('no built-in padding bleed', tpPadding in s.Present);
    AssertFalse('no built-in font-size bleed', tpFontSize in s.Present);
  finally
    m.Free;
  end;
end;

procedure TBuiltinThemeTest.TestUnstyledTypeKeyStillGetsBuiltin;
{ A partial theme that styles only TyButton must still leave OTHER controls
  with the built-in default look (robustness for partial themes). }
var
  m: TTyStyleModel;
  s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { background: #FF0000; }');
    s := m.ResolveStyle('TyLabel', '', []);
    AssertTrue('unstyled TyLabel still gets built-in TextColor',
      tpTextColor in s.Present);
    s := m.ResolveStyle('TyPanel', '', []);
    AssertTrue('unstyled TyPanel still gets built-in Background',
      tpBackground in s.Present);
  finally
    m.Free;
  end;
end;
```

- [ ] **Step 2: 运行,确认新测试失败(基础层未实现)**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi && ./tests/tytests --suite=TBuiltinThemeTest --format=plain`
Expected: `TestEmptyModelFallsBackToBuiltin` 等 FAIL(空 model 当前返回 EmptyStyleSet,Background 不 present)。

- [ ] **Step 3: 实现基础层 — 改 `source/tyControls.StyleModel.pas`**

3a. `uses` 子句末尾加入 `tyControls.DefaultTheme`:
```pascal
uses
  Classes, SysUtils, Types,
  tyControls.Types, tyControls.Css.Parser, tyControls.Css.Values,
  tyControls.DefaultTheme;
```

3b. 替换类声明的 `private` 区(整段)为:
```pascal
  private
    FRules: TFPList;          // user layer — owns TTyStyleRuleEntry
    FVars: TStringList;       // user :root vars, name=value (no leading --)
    FBaseRules: TFPList;      // built-in default layer — owns TTyStyleRuleEntry
    FBaseVars: TStringList;   // built-in :root vars
    procedure ClearList(ARules: TFPList);
    procedure LoadInto(ARules: TFPList; AVars: TStrings; const ASource: string);
    procedure AddEntryTo(ARules: TFPList; const ATypeName, AVariant: string;
      AHasState: Boolean; AState: TTyState; const AStyle: TTyStyleSet);
    function FindStyleIn(ARules: TFPList; const ATypeName, AVariant: string;
      AHasState: Boolean; AState: TTyState; out AStyle: TTyStyleSet): Boolean;
    function ResolveLayer(ARules: TFPList; const ATypeKey, AStyleClass: string;
      AStates: TTyStateSet): TTyStyleSet;
    function UserHasTypeKey(const ATypeKey: string): Boolean;
```

3c. 替换 `Create`、`Destroy`、`Clear`:
```pascal
constructor TTyStyleModel.Create;
begin
  inherited Create;
  FRules := TFPList.Create;
  FVars := TStringList.Create;
  FBaseRules := TFPList.Create;
  FBaseVars := TStringList.Create;
  { Seed the built-in default skin once. It is never cleared by user theme
    loads — it only applies (per-typeKey) when the user layer is silent. }
  LoadInto(FBaseRules, FBaseVars, TyBuiltinThemeCss);
end;

destructor TTyStyleModel.Destroy;
begin
  ClearList(FRules);
  ClearList(FBaseRules);
  FRules.Free;
  FBaseRules.Free;
  FVars.Free;
  FBaseVars.Free;
  inherited Destroy;
end;

procedure TTyStyleModel.Clear;
{ Clears only the USER layer; the built-in base layer is permanent. }
begin
  ClearList(FRules);
  FVars.Clear;
end;
```

3d. 删除旧的 `AddEntry` 和 `FindStyle` 方法实现,替换为 `ClearList`/`AddEntryTo`/`FindStyleIn`/`UserHasTypeKey`/`LoadInto`:
```pascal
procedure TTyStyleModel.ClearList(ARules: TFPList);
var i: Integer;
begin
  for i := 0 to ARules.Count - 1 do
    TObject(ARules[i]).Free;
  ARules.Clear;
end;

procedure TTyStyleModel.AddEntryTo(ARules: TFPList; const ATypeName, AVariant: string;
  AHasState: Boolean; AState: TTyState; const AStyle: TTyStyleSet);
var e: TTyStyleRuleEntry;
begin
  e := TTyStyleRuleEntry.Create;
  e.TypeName := ATypeName;
  e.Variant := AVariant;
  e.HasState := AHasState;
  e.State := AState;
  e.Style := AStyle;
  ARules.Add(e);
end;

function TTyStyleModel.FindStyleIn(ARules: TFPList; const ATypeName, AVariant: string;
  AHasState: Boolean; AState: TTyState; out AStyle: TTyStyleSet): Boolean;
var
  i: Integer;
  e: TTyStyleRuleEntry;
begin
  Result := False;
  AStyle := EmptyStyleSet;
  for i := 0 to ARules.Count - 1 do
  begin
    e := TTyStyleRuleEntry(ARules[i]);
    if SameText(e.TypeName, ATypeName) and SameText(e.Variant, AVariant)
       and (e.HasState = AHasState) and ((not AHasState) or (e.State = AState)) then
    begin
      AStyle := e.Style;
      Result := True;
      Exit;
    end;
  end;
end;

function TTyStyleModel.UserHasTypeKey(const ATypeKey: string): Boolean;
var
  i: Integer;
  e: TTyStyleRuleEntry;
begin
  Result := False;
  for i := 0 to FRules.Count - 1 do
  begin
    e := TTyStyleRuleEntry(FRules[i]);
    if SameText(e.TypeName, ATypeKey) then
      Exit(True);
  end;
end;

procedure TTyStyleModel.LoadInto(ARules: TFPList; AVars: TStrings; const ASource: string);
var
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  ri, si, di: Integer;
  rule: TTyCssRule;
  sel: TTyCssSelector;
  decl: TTyCssDeclaration;
  st: TTyStyleSet;
begin
  ClearList(ARules);
  AVars.Clear;
  parser := TTyCssParser.Create(ASource);
  try
    sheet := parser.Parse;
    try
      AVars.Assign(sheet.RootVars);
      for ri := 0 to sheet.Rules.Count - 1 do
      begin
        rule := TTyCssRule(sheet.Rules[ri]);
        st := EmptyStyleSet;
        for di := 0 to High(rule.Declarations) do
        begin
          decl := rule.Declarations[di];
          TyApplyDeclaration(st, decl.Prop, decl.RawValue, AVars);
        end;
        for si := 0 to High(rule.Selectors) do
        begin
          sel := rule.Selectors[si];
          AddEntryTo(ARules, sel.TypeName, sel.Variant, sel.HasState, sel.State, st);
        end;
      end;
    finally
      sheet.Free;
    end;
  finally
    parser.Free;
  end;
end;
```

3e. 替换 `LoadFromCss`(`LoadFromFile` 保持不变,它调用 LoadFromCss):
```pascal
procedure TTyStyleModel.LoadFromCss(const ASource: string);
begin
  LoadInto(FRules, FVars, ASource);
end;
```

3f. 把旧 `ResolveStyle` 的整段**主体**抽成 `ResolveLayer`(改名 + 用 `FindStyleIn(ARules, ...)`),再写新的 `ResolveStyle`:
```pascal
function TTyStyleModel.ResolveLayer(ARules: TFPList; const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
const
  cStateOrder: array[0..3] of TTyState = (tysHover, tysFocused, tysActive, tysDisabled);
var
  variants: TStringList;
  found: TTyStyleSet;
  vi, si: Integer;
  v: string;
  st: TTyState;
begin
  Result := EmptyStyleSet;
  variants := TStringList.Create;
  try
    variants.Delimiter := ' ';
    variants.StrictDelimiter := False;
    variants.DelimitedText := Trim(AStyleClass);
    if FindStyleIn(ARules, ATypeKey, '', False, tysNormal, found) then
      TyMergeStyleSet(Result, found);
    for vi := 0 to variants.Count - 1 do
    begin
      v := Trim(variants[vi]);
      if v = '' then Continue;
      if FindStyleIn(ARules, ATypeKey, v, False, tysNormal, found) then
        TyMergeStyleSet(Result, found);
    end;
    for si := 0 to High(cStateOrder) do
    begin
      st := cStateOrder[si];
      if not (st in AStates) then Continue;
      if FindStyleIn(ARules, ATypeKey, '', True, st, found) then
        TyMergeStyleSet(Result, found);
      for vi := 0 to variants.Count - 1 do
      begin
        v := Trim(variants[vi]);
        if v = '' then Continue;
        if FindStyleIn(ARules, ATypeKey, v, True, st, found) then
          TyMergeStyleSet(Result, found);
      end;
    end;
  finally
    variants.Free;
  end;
end;

function TTyStyleModel.ResolveStyle(const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
var
  userLayer: TTyStyleSet;
begin
  Result := EmptyStyleSet;
  { Built-in default layer applies only when the user theme defines NO rule for
    this typeKey — so a fully-themed control is untouched (no property bleed),
    while an unstyled/partially-themed control still gets a sensible default. }
  if not UserHasTypeKey(ATypeKey) then
    Result := ResolveLayer(FBaseRules, ATypeKey, AStyleClass, AStates);
  userLayer := ResolveLayer(FRules, ATypeKey, AStyleClass, AStates);
  TyMergeStyleSet(Result, userLayer);
end;
```

- [ ] **Step 4: 运行新测试,确认通过**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi && ./tests/tytests --suite=TBuiltinThemeTest --format=plain`
Expected: 5/5 通过。

- [ ] **Step 5: 全量回归(关键:现有 289 必须零改动通过)**

Run: `./tests/tytests -a --format=plain 2>&1 | tail -5`
Expected: 全部通过(289 + 5 新 = 294)。若任何旧测试失败,**不要修改旧测试**——回到 Step 3 排查(基础层应在用户层定义该 typeKey 时被完全抑制)。

- [ ] **Step 6: Commit**

```bash
git add source/tyControls.StyleModel.pas tests/test.defaulttheme.pas
git commit -m "feat(tycontrols): layer built-in skin under loaded theme (per-typeKey fallback)"
```

---

## Task 3: 端到端可见性测试(核心缺陷回归)

**Files:**
- Modify: `tests/test.defaulttheme.pas`

- [ ] **Step 1: 写测试 — 追加 control 渲染可见性用例**

在 `test.defaulttheme.pas` 的 uses 增加:`Controls, Graphics, BGRABitmap, BGRABitmapTypes, tyControls.Controller, tyControls.Base, tyControls.Button`。

在文件中(implementation 之上)加入 access 子类:
```pascal
type
  TTyButtonRenderAccess = class(TTyButton)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;
```
implementation 区:
```pascal
procedure TTyButtonRenderAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;
```

在 `published` 区加 `procedure TestControlVisibleWithoutTheme;`,实现:
```pascal
procedure TBuiltinThemeTest.TestControlVisibleWithoutTheme;
{ End-to-end fix for the reported bug: a control whose controller has NO theme
  loaded must still render its background (built-in skin), not blank. Mirrors
  what the Lazarus designer does (Paint -> RenderTo, no LoadTheme ever run). }
var
  Ctl: TTyStyleController;
  Btn: TTyButtonRenderAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil); // deliberately NO LoadTheme
  Bmp := TBitmap.Create;
  try
    Btn := TTyButtonRenderAccess.Create(nil);
    try
      Btn.Controller := Ctl;
      Btn.Caption := '';                 // no glyph at center
      Btn.Font.PixelsPerInch := 96;      // pin PPI (macOS defaults to 72)
      Bmp.PixelFormat := pf32bit;
      Bmp.SetSize(100, 40);
      { Distinct magenta backdrop so an unpainted control stays detectable. }
      Bmp.Canvas.Brush.Color := TColor($FF00FF); // BGR: magenta
      Bmp.Canvas.FillRect(0, 0, 100, 40);
      Btn.DoRenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);

      Reread := TBGRABitmap.Create(Bmp);
      try
        Px := Reread.GetPixel(50, 20);   // center: built-in surface = white
        AssertTrue('center painted white-ish (built-in bg drawn), not backdrop: R',
          Px.red > 240);
        AssertTrue('center painted white-ish (built-in bg drawn): G', Px.green > 240);
        AssertTrue('center painted white-ish (built-in bg drawn): B', Px.blue > 240);
      finally
        Reread.Free;
      end;
    finally
      Btn.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;
```

- [ ] **Step 2: 构建并运行**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi && ./tests/tytests --suite=TBuiltinThemeTest --format=plain`
Expected: 6/6 通过。

- [ ] **Step 3: 全量回归**

Run: `./tests/tytests -a --format=plain 2>&1 | tail -5`
Expected: 全部通过(289 + 6 = 295)。

- [ ] **Step 4: Commit**

```bash
git add tests/test.defaulttheme.pas
git commit -m "test(tycontrols): control renders built-in skin with no theme loaded (designer/no-controller regression)"
```

---

## Task 4: 集成(包注册 + 构建矩阵)

**Files:**
- Modify: `tycontrols.lpk`

- [ ] **Step 1: 把新单元加入 `tycontrols.lpk`**

把 `<Files Count="23">` 改为 `<Files Count="24">`;在 `Item5`(`tyControls.Css.Values`)之后插入新条目,并把原 `Item6`..`Item23` 顺延为 `Item7`..`Item24`。最稳妥做法:在所有现有 Item 之后追加,并把它编号为 `Item24`:
```xml
      <Item24><Filename Value="source/tyControls.DefaultTheme.pas"/><UnitName Value="tyControls.DefaultTheme"/></Item24>
```
(顺序不影响编译;只需 Count=24 且编号唯一连续。追加为 Item24 最简单,无需重排。)

- [ ] **Step 2: 编译运行期包**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tycontrols.lpk 2>&1 | tail -5`
Expected: 编译成功(无错误)。

- [ ] **Step 3: 编译设计期包(确认不破坏)**

Run: `lazbuild tycontrols_dt.lpk 2>&1 | tail -5`
Expected: 成功。

- [ ] **Step 4: 构建矩阵(包 + 全部示例 + 测试器)**

Run: `bash scripts/build-matrix.sh 2>&1 | tail -20`
Expected: 全绿(2 包 + 17 示例 + tytests)。若脚本不存在或参数不同,改为逐个 `lazbuild` 每个 `examples/*/*.lpi` + `tests/tytests.lpi`。

- [ ] **Step 5: Commit**

```bash
git add tycontrols.lpk
git commit -m "build(tycontrols): register tyControls.DefaultTheme in runtime package"
```

---

## Task 5: 文档同步

**Files:**
- Modify: `docs/getting-started.md`
- Modify: `docs/KNOWN_GAPS.md`
- Modify: `docs/tycss-reference.md`
- Modify: `README.md`

- [ ] **Step 1: `docs/getting-started.md` — 新增"内置默认皮肤"小节**

在"## 4. 主题"的"### 内置主题"之前(或紧随其后)插入:
```markdown
### 内置默认皮肤(零配置)

TyControls 内置了一套**默认皮肤**(浅色,与 `themes/light.tycss` 一致),已编译进库中。
因此即使你**没有加载任何主题**,控件也会以合理的默认外观显示:

- 未显式设置 `Controller`、且从未调用 `LoadTheme` 的控件 —— 显示内置默认皮肤;
- 在 Lazarus **窗体设计器**中拖放的控件 —— 同样以内置默认皮肤呈现(无需运行程序)。

加载主题会在内置皮肤**之上按 typeKey 覆盖**:

- 加载**完整主题**(`light`/`dark`/`showcase` 定义了所有控件)—— 完全替换内置外观;
- 加载**部分主题**(例如只重定义 `TyButton` 或只改 `:root` 变量后重写若干控件)——
  你写了规则的控件用你的样式,**未提及的控件仍保留内置默认皮肤**,不会变成空白。

> 抑制粒度是"按 typeKey":只要主题为某个 typeKey 写了任意一条规则,该 typeKey 的内置
> 默认就被整体让位给主题(避免内置属性意外渗漏)。
```

- [ ] **Step 2: `docs/getting-started.md` — 修订"## 7. 已知限制"第 4 条**

把现有第 4 条(设计期渲染近似)替换为:
```markdown
4. **设计期渲染** — 拖放到窗体上的 TyControls 控件在 Lazarus 设计器中会以**内置默认皮肤**
   呈现(零配置可见)。注意:完整的自绘**窗框**(`TTyFormChrome`)仍只在运行期呈现,
   设计器显示的是原生(未换肤)窗口框架——这是此类皮肤库的通常行为。
```

- [ ] **Step 3: `docs/KNOWN_GAPS.md` — 同步设计期描述**

打开文件,找到关于"设计期/design-time"渲染的条目(若有),改为与上面一致的措辞(拖放控件以内置默认皮肤呈现;仅窗框为运行期)。若没有该条目则跳过。Run `grep -n "设计\|design" docs/KNOWN_GAPS.md` 定位。

- [ ] **Step 4: `docs/tycss-reference.md` — 补内置默认 + 覆盖语义**

在文档顶部概述或主题加载相关章节,加一段:
```markdown
## 内置默认皮肤与覆盖语义

库内置一套默认皮肤(等同 `themes/light.tycss`),作为始终存在的基础层。`ResolveStyle`
的实际行为是:**当且仅当**已加载主题对某 typeKey 没有任何规则时,该 typeKey 回退到内置
默认;一旦主题为该 typeKey 写了规则,内置层对它整体失效,完全由主题决定(包括"留空"
的属性也不会从内置层渗漏)。因此完整主题与未引入本特性前渲染一致,而部分主题不会导致
未覆盖控件不可见。
```

- [ ] **Step 5: `README.md` — 卖点补一句**

在特性列表/卖点处加入一条(中英按 README 现有语言):
```markdown
- **零配置默认皮肤** — 未加载主题或在设计器中拖放即有合理外观;主题在其之上按 typeKey 覆盖。
```
用 `grep -n` 找到特性列表位置后插入。

- [ ] **Step 6: Commit**

```bash
git add docs/getting-started.md docs/KNOWN_GAPS.md docs/tycss-reference.md README.md
git commit -m "docs(tycontrols): document built-in default skin and per-typeKey override semantics"
```

---

## 完成后

- 运行最终全套件 + 构建矩阵 + heaptrc 0 泄漏核查。
- 终审(reviewer 跑探针,不止读代码)。
- 通过后用 superpowers:finishing-a-development-branch 完成(本仓约定:本地快进合并 main + 删分支)。
- 更新项目记忆 `tycontrols-project.md`(内置默认皮肤已加;设计期可见性已修)。
