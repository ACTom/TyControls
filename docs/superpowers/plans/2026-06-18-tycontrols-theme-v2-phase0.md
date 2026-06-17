# TyControls 主题系统 v2 · 阶段0「引擎地基」实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:executing-plans (本会话内执行) 落地本计划，逐任务推进。步骤用 `- [ ]` 勾选跟踪。

**Goal:** 把 `StyleModel` 从「加载即烘焙」改为「先合并令牌层、解析时统一求值一次」（D2），并加 `luminance/elevate/on` + `--ty-mode` + `transparent/none`——现有主题像素零变化。

**Architecture:** 规则条目改持原始声明 `array of TTyCssDeclaration`；加载期建 `FMergedVars := FBaseVars ⊕ FVars` 并做一次校验性求值（fail-fast）；`ResolveStyle` 按既有级联顺序把命中条目的声明逐条 `TyApplyDeclaration(… , FMergedVars)`。求值机 `TyEvalColor/Length/Float` 已是 `Vars` 参数化，复用不改。

**Tech Stack:** FPC 3.2.2 / Lazarus；`source/tyControls.{StyleModel,Css.Values}.pas`；fpcunit（`tests/`）；PPI=96。

**权威来源:** `docs/superpowers/specs/2026-06-17-tycontrols-theme-v2-phase0-design.md`。

**执行约定:** 每任务结束 `lazbuild tests/tytests.lpi` → `./tests/tytests.exe --all --format=plain`，现有全绿（已知 11 环境错误不变）+ 新测试过；只 stage 自己的文件；提交信息以 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` 结尾。

---

## File Structure

- `source/tyControls.Css.Values.pas` — 新增 `TyLuminance/TyElevate/TyOn`；`TyEvalColor` 加 `transparent/elevate/on` 分发；加 `uses Math`。
- `source/tyControls.StyleModel.pas` — 条目改持声明；`LoadInto/ResolveLayer/ResolveStyle/MaxGlassBlur` 重构；新增 `FMergedVars/RebuildMergedVars/ValidateRules/ApplyEntry/FindEntryIn`；`TyApplyDeclaration` 加 `background:none`。
- `tests/test.Css.Values.pas` — 加 `transparent`、`luminance/elevate/on` 单测。
- `tests/test.StyleModel.pas` — 加 `background:none`、头号 seed-override 解锁测试、merge-then-resolve 等价抽样测试。
- 不动控件代码、不动既有测试语义、不动 `themes/*.tycss`、不动并行线未提交的 `demo.lpi`。

任务顺序：**Task 1/2 是对现模型的纯叠加**（先落、低风险、各自可发）；**Task 3 是核心重构**（Task 1/2 的新语法随之改为 resolve 期求值，行为不变）。

---

## Task 1：`transparent` / `none` 关键字

**Files:**
- Modify: `source/tyControls.Css.Values.pas`（`TyEvalColor`）
- Modify: `source/tyControls.StyleModel.pas`（`TyApplyDeclaration` 的 `background` 分支）
- Test: `tests/test.Css.Values.pas`、`tests/test.StyleModel.pas`

- [ ] **Step 1: 写失败测试（transparent 颜色关键字）** — 在 `test.Css.Values.pas` 加：

```pascal
procedure TTyCssValuesTest.TestTransparentKeyword;
var v: TStringList;
begin
  v := TStringList.Create;
  try
    AssertEquals('transparent -> $00000000', TTyColor($00000000), TyEvalColor('transparent', v));
    AssertEquals('TRANSPARENT 大小写无关', TTyColor($00000000), TyEvalColor('  TRANSPARENT ', v));
  finally
    v.Free;
  end;
end;
```
（记得在 `published` 区登记 `TestTransparentKeyword`。）

- [ ] **Step 2: 运行 → 失败**：`Cannot evaluate color: transparent`。

- [ ] **Step 3: 实现 transparent** — `TyEvalColor` 在空检查后、hex 前插：

```pascal
  E := Trim(Expr);
  if E = '' then
    raise Exception.Create('Empty color expression');
  if LowerCase(E) = 'transparent' then
    Exit(tyTransparent);   // $00000000，alpha 0
  // direct hex
  if E[1] = '#' then
    Exit(TyParseColor(E));
```

- [ ] **Step 4: 运行 → 过。**

- [ ] **Step 5: 写失败测试（background:none）** — 在 `test.StyleModel.pas` 加：

```pascal
procedure TTyStyleModelTest.TestBackgroundNoneKeyword;
var model: TTyStyleModel; st: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss('TyPanel { background: none; }');
    st := model.ResolveStyle('TyPanel', '', []);
    AssertTrue('tpBackground 置位', tpBackground in st.Present);
    AssertTrue('Kind = tfkNone', st.Background.Kind = tfkNone);
  finally
    model.Free;
  end;
end;
```

- [ ] **Step 6: 运行 → 失败**（`none` 当前会进 `ParsePlainImage`/`TyEvalColor` 报错或误判）。

- [ ] **Step 7: 实现 background:none** — `TyApplyDeclaration` 的 background 分支改为：

```pascal
  if (prop = 'background') or (prop = 'background-color') then
  begin
    if LowerCase(raw) = 'none' then
    begin
      fill := Default(TTyFill);
      fill.Kind := tfkNone;
      AStyle.Background := fill;
    end
    else if LowerCase(Copy(raw, 1, 16)) = 'linear-gradient(' then
      AStyle.Background := ParseLinearGradient(raw, Vars)
    else
    begin
      fill := Default(TTyFill);
      fill.Kind := tfkSolid;
      fill.Color := TyEvalColor(raw, Vars);
      AStyle.Background := fill;
    end;
    Include(AStyle.Present, tpBackground);
  end
```

- [ ] **Step 8: 运行全套 → 新测过、现有全绿。**

- [ ] **Step 9: 提交** — `feat(tycontrols): theme v2 P0 — transparent/none keywords`，stage 两源文件 + 两测试文件。

---

## Task 2：`luminance` / `elevate` / `on` + `--ty-mode`

**Files:**
- Modify: `source/tyControls.Css.Values.pas`
- Test: `tests/test.Css.Values.pas`

- [ ] **Step 1: 写失败测试** — 在 `test.Css.Values.pas` 加：

```pascal
procedure TTyCssValuesTest.TestLuminance;
begin
  AssertEquals('white ~1', 1.0, TyLuminance(TyRGB(255,255,255)), 0.01);
  AssertEquals('black 0',  0.0, TyLuminance(TyRGB(0,0,0)),       0.001);
  AssertTrue('mid in (0,1)', (TyLuminance(TyRGB(128,128,128)) > 0.1)
                         and (TyLuminance(TyRGB(128,128,128)) < 0.5));
end;

procedure TTyCssValuesTest.TestElevateDirection;
var lt, dk: TTyColor;
begin
  lt := TyRGB(240,240,240);  dk := TyRGB(20,24,32);
  // light 模式 -> darken；dark 模式 -> lighten
  AssertEquals('light=darken', TyDarken(lt,8), TyElevate(lt,8,'light'));
  AssertEquals('dark=lighten',  TyLighten(dk,8), TyElevate(dk,8,'dark'));
  // 缺省按 luminance：亮色 darken、暗色 lighten
  AssertEquals('default light->darken', TyDarken(lt,8), TyElevate(lt,8,''));
  AssertEquals('default dark->lighten', TyLighten(dk,8), TyElevate(dk,8,''));
end;

procedure TTyCssValuesTest.TestOnInk;
begin
  AssertEquals('on(white)=black', TyRGB(0,0,0),   TyOn(TyRGB(255,255,255)));
  AssertEquals('on(black)=white', TyRGB(255,255,255), TyOn(TyRGB(0,0,0)));
  // on-accent bug 回归：蓝 accent 上墨可读（白）
  AssertEquals('on(#3B82F6)=white', TyRGB(255,255,255), TyOn(TyParseColor('#3B82F6')));
  // 自定义墨：bg 偏暗取 inkOnDark
  AssertEquals('custom on dark bg', TyParseColor('#EEEEEE'),
    TyOn(TyRGB(20,20,20), TyParseColor('#111111'), TyParseColor('#EEEEEE')));
end;

procedure TTyCssValuesTest.TestElevateOnViaEvalColor;
var v: TStringList;
begin
  v := TStringList.Create;
  try
    v.Values['surface'] := '#F0F0F0';
    v.Values['ty-mode'] := 'light';
    AssertEquals('elevate via eval', TyDarken(TyParseColor('#F0F0F0'),6),
      TyEvalColor('elevate(var(--surface), 6%)', v));
    AssertEquals('on via eval', TyRGB(0,0,0), TyEvalColor('on(var(--surface))', v));
  finally
    v.Free;
  end;
end;
```
（在 `published` 登记四个方法。）

- [ ] **Step 2: 运行 → 失败**（函数/分发不存在）。

- [ ] **Step 3: 实现函数** — `uses` 加 `Math`；接口区加：

```pascal
function TyLuminance(c: TTyColor): Single;
function TyElevate(c: TTyColor; Pct: Single; const Mode: string): TTyColor;
function TyOn(bg: TTyColor): TTyColor; overload;
function TyOn(bg, inkOnLight, inkOnDark: TTyColor): TTyColor; overload;
```

实现区：

```pascal
function TyLuminance(c: TTyColor): Single;
  function Lin(ch: Byte): Single;
  var s: Single;
  begin
    s := ch / 255.0;
    if s <= 0.03928 then Result := s / 12.92
    else Result := Power((s + 0.055) / 1.055, 2.4);
  end;
begin
  // WCAG 相对亮度（线性化加权），0..1
  Result := 0.2126 * Lin(TyRedOf(c)) + 0.7152 * Lin(TyGreenOf(c)) + 0.0722 * Lin(TyBlueOf(c));
end;

function TyElevate(c: TTyColor; Pct: Single; const Mode: string): TTyColor;
var m: string; goDark: Boolean;
begin
  m := LowerCase(Trim(Mode));
  if m = 'light' then goDark := True          // 亮模式 → 抬升=变暗
  else if m = 'dark' then goDark := False      // 暗模式 → 抬升=变亮
  else goDark := TyLuminance(c) >= 0.5;         // 缺省：粗略按色自身亮度（主题应设 --ty-mode）
  if goDark then Result := TyDarken(c, Pct) else Result := TyLighten(c, Pct);
end;

function TyOn(bg: TTyColor): TTyColor;
begin
  // 最大对比：WCAG 黑白文字边界在相对亮度 0.179
  if TyLuminance(bg) > 0.179 then Result := TyRGB(0, 0, 0) else Result := TyRGB(255, 255, 255);
end;

function TyOn(bg, inkOnLight, inkOnDark: TTyColor): TTyColor;
begin
  if TyLuminance(bg) > 0.179 then Result := inkOnLight else Result := inkOnDark;
end;
```

- [ ] **Step 4: 接 `TyEvalColor` 分发 + `--ty-mode` 读取** — 加一个 mode helper（实现区上方）：

```pascal
function ModeOf(Vars: TStrings): string;
begin
  if (Vars <> nil) and (Vars.IndexOfName('ty-mode') >= 0) then
    Result := LowerCase(Trim(Vars.Values['ty-mode']))
  else
    Result := '';
end;
```

在 `TyEvalColor` 的 function-call 分发里（`mix`/`rgb` 之后、`raise Unknown` 之前）插：

```pascal
      if (fn = 'elevate') and (args.Count = 2) then
        Exit(TyElevate(TyEvalColor(args[0], Vars), ParsePctOrNum(args[1]), ModeOf(Vars)));
      if (fn = 'on') and (args.Count = 1) then
        Exit(TyOn(TyEvalColor(args[0], Vars)));
      if (fn = 'on') and (args.Count = 3) then
        Exit(TyOn(TyEvalColor(args[0], Vars), TyEvalColor(args[1], Vars), TyEvalColor(args[2], Vars)));
```

- [ ] **Step 5: 运行全套 → 新测过、现有全绿。**

- [ ] **Step 6: 提交** — `feat(tycontrols): theme v2 P0 — luminance/elevate/on + --ty-mode`。

---

## Task 3：merge-then-resolve 求值模型重构（核心）

**Files:**
- Modify: `source/tyControls.StyleModel.pas`（条目结构、`LoadInto`、`ResolveLayer`、`ResolveStyle`、`MaxGlassBlur`、`Create`/`Destroy`/`Clear`、`AddEntryTo`、`FindStyleIn`→`FindEntryIn`；新增 `FMergedVars`、`RebuildMergedVars`、`ValidateRules`、`ApplyEntry`）
- Test: `tests/test.StyleModel.pas`

**TDD 驱动 = 头号 seed-override 解锁测试**（旧模型给内置 accent，重构后给覆盖色）；**回归门 = 全部既有像素/主题测试保持全绿**。

- [ ] **Step 1: 写失败测试（解锁 + 等价抽样）** — `test.StyleModel.pas` 加：

```pascal
procedure TTyStyleModelTest.TestSeedOverrideReachesBaseRule;
var model: TTyStyleModel; st: TTyStyleSet;
begin
  // 只覆盖 --accent、不写任何 TyButton 规则；base TyButton.primary = var(--accent)
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(':root { --accent: #FF0000; }');
    st := model.ResolveStyle('TyButton', 'primary', []);
    AssertTrue('background present', tpBackground in st.Present);
    AssertEquals('base primary 吃到 merged seed = 红',
      TTyColor($FFFF0000), st.Background.Color);   // 旧模型会是内置 $FF3B82F6
  finally
    model.Free;
  end;
end;

procedure TTyStyleModelTest.TestFullThemeBaselineUnchanged;
var model: TTyStyleModel; prim, edit: TTyStyleSet;
begin
  // 载完整内置主题等价：抽样几个值与「烘焙基线」一致（无 seed 覆盖时不变）
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(TyBuiltinThemeCss);   // 完整主题：每个 typeKey 都 user-defined
    prim := model.ResolveStyle('TyButton', 'primary', []);
    AssertEquals('primary=内置 accent', TTyColor($FF3B82F6), prim.Background.Color);
    edit := model.ResolveStyle('TyEdit', '', [tysFocused]);
    AssertTrue('focus 有 outline', tpOutline in edit.Present);
  finally
    model.Free;
  end;
end;
```
（登记两方法。`TyBuiltinThemeCss` 已是 `tyControls.DefaultTheme` 的导出常量；确认 `test.StyleModel.pas` 的 uses 含 `tyControls.DefaultTheme`，缺则补。）

- [ ] **Step 2: 运行 → `TestSeedOverrideReachesBaseRule` 失败**（得 `$FF3B82F6` 而非红），`TestFullThemeBaselineUnchanged` 过（旧模型本就如此）。这确认测试有效。

- [ ] **Step 3: 条目改持声明** — `TTyStyleRuleEntry` 改：

```pascal
  TTyStyleRuleEntry = class
    TypeName: string;
    Variant: string;
    HasState: Boolean;
    State: TTyState;
    Decls: array of TTyCssDeclaration;   // 原始 (Prop, RawValue)，解析期求值
  end;
```
确认 `uses` 含 `tyControls.Css.Parser`（`TTyCssDeclaration` 来源）——`StyleModel` 已用 `TTyCssParser`，应已在。

- [ ] **Step 4: `AddEntryTo` 改传声明数组：**

```pascal
procedure TTyStyleModel.AddEntryTo(ARules: TFPList; const ATypeName, AVariant: string;
  AHasState: Boolean; AState: TTyState; const ADecls: array of TTyCssDeclaration);
var e: TTyStyleRuleEntry; i: Integer;
begin
  e := TTyStyleRuleEntry.Create;
  e.TypeName := ATypeName;
  e.Variant := AVariant;
  e.HasState := AHasState;
  e.State := AState;
  SetLength(e.Decls, Length(ADecls));
  for i := 0 to High(ADecls) do e.Decls[i] := ADecls[i];
  ARules.Add(e);
end;
```
（同步改接口区/私有声明的形参。）

- [ ] **Step 5: 新增字段与辅助** — 私有区加 `FMergedVars: TStringList;`，并加：

```pascal
procedure TTyStyleModel.RebuildMergedVars;
var i: Integer;
begin
  FMergedVars.Clear;
  FMergedVars.Assign(FBaseVars);                       // 第0层 SEED/派生
  for i := 0 to FVars.Count - 1 do                     // 用户层覆盖同名
    FMergedVars.Values[FVars.Names[i]] := FVars.ValueFromIndex[i];
end;

procedure TTyStyleModel.ValidateRules(ARules: TFPList);
{ 加载期一次性校验：对 merged vars 试求值每条声明，坏值（未定义 var/坏表达式）
  立即抛出 —— 保住「载入坏主题即抛」的 fail-fast 语义。 }
var i, di: Integer; e: TTyStyleRuleEntry; dummy: TTyStyleSet;
begin
  for i := 0 to ARules.Count - 1 do
  begin
    e := TTyStyleRuleEntry(ARules[i]);
    dummy := EmptyStyleSet;
    for di := 0 to High(e.Decls) do
      TyApplyDeclaration(dummy, e.Decls[di].Prop, e.Decls[di].RawValue, FMergedVars);
  end;
end;

procedure TTyStyleModel.ApplyEntry(var AResult: TTyStyleSet; AEntry: TTyStyleRuleEntry);
var di: Integer;
begin
  for di := 0 to High(AEntry.Decls) do
    TyApplyDeclaration(AResult, AEntry.Decls[di].Prop, AEntry.Decls[di].RawValue, FMergedVars);
end;

function TTyStyleModel.FindEntryIn(ARules: TFPList; const ATypeName, AVariant: string;
  AHasState: Boolean; AState: TTyState): TTyStyleRuleEntry;
var i: Integer; e: TTyStyleRuleEntry;
begin
  Result := nil;
  for i := ARules.Count - 1 downto 0 do   // 倒序 = 后定义胜（与旧 FindStyleIn 一致）
  begin
    e := TTyStyleRuleEntry(ARules[i]);
    if SameText(e.TypeName, ATypeName) and SameText(e.Variant, AVariant)
       and (e.HasState = AHasState) and ((not AHasState) or (e.State = AState)) then
      Exit(e);
  end;
end;
```
（接口/私有区登记四者；删除旧 `FindStyleIn`，或留作未用——建议改名替换。）

- [ ] **Step 6: `LoadInto` 停止烘焙、存原始声明、建 merged、校验：**

```pascal
procedure TTyStyleModel.LoadInto(ARules: TFPList; AVars: TStrings; const ASource: string);
var
  parser: TTyCssParser; sheet: TTyCssStylesheet;
  tmpRules: TFPList; tmpVars: TStringList;
  ri, si: Integer; rule: TTyCssRule; sel: TTyCssSelector;
begin
  tmpRules := TFPList.Create;
  tmpVars := TStringList.Create;
  try
    parser := TTyCssParser.Create(ASource);
    try
      sheet := parser.Parse;
      try
        tmpVars.Assign(sheet.RootVars);
        for ri := 0 to sheet.Rules.Count - 1 do
        begin
          rule := TTyCssRule(sheet.Rules[ri]);
          for si := 0 to High(rule.Selectors) do
          begin
            sel := rule.Selectors[si];
            AddEntryTo(tmpRules, sel.TypeName, sel.Variant, sel.HasState, sel.State,
                       rule.Declarations);   // 原始声明，不烘焙
          end;
        end;
      finally
        sheet.Free;
      end;
    finally
      parser.Free;
    end;
    ClearList(ARules);
    AVars.Clear;
    for ri := 0 to tmpRules.Count - 1 do ARules.Add(tmpRules[ri]);
    tmpRules.Clear;
    AVars.Assign(tmpVars);
  except
    ClearList(tmpRules);
    tmpRules.Free; tmpVars.Free;
    raise;
  end;
  tmpRules.Free; tmpVars.Free;
  RebuildMergedVars;            // base ⊕ user（user 刚写入 AVars=FVars，或 base 写入 FBaseVars）
  ValidateRules(ARules);        // 对刚载入层做 fail-fast 校验
end;
```
注：`LoadInto` 既用于 base（`Create`）也用于 user（`LoadFromCss`）。base 载入时 `FVars` 空 → merged=base；user 载入时 merged=base⊕user。

- [ ] **Step 7: `ResolveLayer`/`ResolveStyle` 改按声明求值** — 替换二者：

```pascal
procedure TTyStyleModel.ResolveLayer(ARules: TFPList; const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet; var AResult: TTyStyleSet);
const
  cStateOrder: array[0..3] of TTyState = (tysHover, tysFocused, tysActive, tysDisabled);
var
  variants: TStringList; e: TTyStyleRuleEntry; vi, si: Integer; v: string; st: TTyState;
begin
  variants := TStringList.Create;
  try
    variants.Delimiter := ' ';
    variants.StrictDelimiter := False;
    variants.DelimitedText := Trim(AStyleClass);
    e := FindEntryIn(ARules, ATypeKey, '', False, tysNormal);
    if e <> nil then ApplyEntry(AResult, e);
    for vi := 0 to variants.Count - 1 do
    begin
      v := Trim(variants[vi]); if v = '' then Continue;
      e := FindEntryIn(ARules, ATypeKey, v, False, tysNormal);
      if e <> nil then ApplyEntry(AResult, e);
    end;
    for si := 0 to High(cStateOrder) do
    begin
      st := cStateOrder[si];
      if not (st in AStates) then Continue;
      e := FindEntryIn(ARules, ATypeKey, '', True, st);
      if e <> nil then ApplyEntry(AResult, e);
      for vi := 0 to variants.Count - 1 do
      begin
        v := Trim(variants[vi]); if v = '' then Continue;
        e := FindEntryIn(ARules, ATypeKey, v, True, st);
        if e <> nil then ApplyEntry(AResult, e);
      end;
    end;
  finally
    variants.Free;
  end;
end;

function TTyStyleModel.ResolveStyle(const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
begin
  Result := EmptyStyleSet;
  if not UserHasTypeKey(ATypeKey) then
    ResolveLayer(FBaseRules, ATypeKey, AStyleClass, AStates, Result);
  ResolveLayer(FRules, ATypeKey, AStyleClass, AStates, Result);
end;
```
（接口/私有区把 `ResolveLayer` 签名改为 `var AResult` 过程。）

- [ ] **Step 8: `MaxGlassBlur` 适配原始声明：**

```pascal
function TTyStyleModel.MaxGlassBlur: Integer;
  function ScanLayer(ARules: TFPList; ASkipUserKeys: Boolean): Integer;
  var i, di, gb: Integer; e: TTyStyleRuleEntry;
  begin
    Result := 0;
    for i := 0 to ARules.Count - 1 do
    begin
      e := TTyStyleRuleEntry(ARules[i]);
      if ASkipUserKeys and UserHasTypeKey(e.TypeName) then Continue;
      for di := 0 to High(e.Decls) do
        if LowerCase(Trim(e.Decls[di].Prop)) = 'glass-blur' then
        begin
          gb := TyEvalLength(e.Decls[di].RawValue, FMergedVars);
          if gb > Result then Result := gb;
        end;
    end;
  end;
var u, b: Integer;
begin
  u := ScanLayer(FRules, False);
  b := ScanLayer(FBaseRules, True);
  if u > b then Result := u else Result := b;
end;
```

- [ ] **Step 9: `Create`/`Destroy`/`Clear` 维护 `FMergedVars`：**

```pascal
constructor TTyStyleModel.Create;
begin
  inherited Create;
  FRules := TFPList.Create;
  FVars := TStringList.Create;
  FBaseRules := TFPList.Create;
  FBaseVars := TStringList.Create;
  FMergedVars := TStringList.Create;
  LoadInto(FBaseRules, FBaseVars, TyBuiltinThemeCss);   // 内部建 merged + 校验 base
end;

destructor TTyStyleModel.Destroy;
begin
  ClearList(FRules);
  ClearList(FBaseRules);
  FRules.Free;
  FBaseRules.Free;
  FVars.Free;
  FBaseVars.Free;
  FMergedVars.Free;
  inherited Destroy;
end;

procedure TTyStyleModel.Clear;
begin
  ClearList(FRules);
  FVars.Clear;
  RebuildMergedVars;   // 回到 base-only
end;
```

- [ ] **Step 10: 编译修补** — 删 `TyApplyDeclaration` 在 `LoadInto` 的旧调用残留；确认 `EmptyStyleSet`、`TTyCssDeclaration`、`Math`(若 StyleModel 需要) 可见；`lazbuild tyControls.lpk` 过。

- [ ] **Step 11: 运行全套** — `TestSeedOverrideReachesBaseRule` 现在过（红）；`TestFullThemeBaselineUnchanged` 过；**所有既有 pixel/主题/控件测试保持全绿**（这是 merge-then-resolve 等价性的证据）。
  - 若某既有测试因「partial CSS + 覆盖 seed + 断言未覆盖 typeKey 的 base 色」而合理改变（spec §7.3 子风险）：**停下，上报用户**，按新能力更新该测试，不静默改语义。

- [ ] **Step 12: 提交** — `refactor(tycontrols): theme v2 P0 — merge-then-resolve evaluation`，stage `StyleModel.pas` + `test.StyleModel.pas`。

---

## 收尾验证

- [ ] `lazbuild` 三目标（lpk / tytests / demo）全过；`tytests.exe` 现有全绿 + 新测过；demo 显示正常（Green 玻璃不回归，`MaxGlassBlur` 仍 16）。
- [ ] 回填记忆 `theme-system-v2-program.md`：Phase 0 done，记录"no cache / on() auto+override / 等价证明 + 像素基线门"等决策与提交。
- [ ] 向用户汇报，确认是否进 Phase 1（令牌分层 + 内置主题接 elevate/on）。
