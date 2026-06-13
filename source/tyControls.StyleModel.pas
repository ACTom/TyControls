unit tyControls.StyleModel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types,
  tyControls.Types, tyControls.Css.Parser, tyControls.Css.Values,
  tyControls.DefaultTheme;

type
  TTyStyleModel = class
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
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadFromCss(const ASource: string);   // raises ETyCssError
    procedure LoadFromFile(const AFileName: string);
    function ResolveStyle(const ATypeKey, AStyleClass: string; AStates: TTyStateSet): TTyStyleSet;
  end;

procedure TyMergeStyleSet(var ABase: TTyStyleSet; const AOver: TTyStyleSet);

// Apply one CSS declaration (prop name + raw value) to a style set, resolving
// values against Vars, and set the matching Present flag. Returns False for
// unknown property names (caller may ignore).
function TyApplyDeclaration(var AStyle: TTyStyleSet; const AProp, ARawValue: string;
  Vars: TStrings): Boolean;

implementation

type
  TTyStyleRuleEntry = class
    TypeName: string;
    Variant: string;
    HasState: Boolean;
    State: TTyState;
    Style: TTyStyleSet;
  end;

procedure TyMergeStyleSet(var ABase: TTyStyleSet; const AOver: TTyStyleSet);
begin
  if tpBackground   in AOver.Present then ABase.Background   := AOver.Background;
  if tpTextColor    in AOver.Present then ABase.TextColor    := AOver.TextColor;
  if tpBorderColor  in AOver.Present then ABase.BorderColor  := AOver.BorderColor;
  if tpBorderWidth  in AOver.Present then ABase.BorderWidth  := AOver.BorderWidth;
  if tpBorderRadius in AOver.Present then ABase.BorderRadius := AOver.BorderRadius;
  if tpPadding      in AOver.Present then ABase.Padding      := AOver.Padding;
  if tpFontName     in AOver.Present then ABase.FontName     := AOver.FontName;
  if tpFontSize     in AOver.Present then ABase.FontSize     := AOver.FontSize;
  if tpFontWeight   in AOver.Present then ABase.FontWeight   := AOver.FontWeight;
  if tpOpacity      in AOver.Present then ABase.Opacity      := AOver.Opacity;
  if tpShadow       in AOver.Present then
  begin
    ABase.ShadowColor  := AOver.ShadowColor;
    ABase.ShadowBlur   := AOver.ShadowBlur;
    ABase.ShadowOffset := AOver.ShadowOffset;
  end;
  ABase.Present := ABase.Present + AOver.Present;
end;

// Parse 'a b c d' (space-separated logical px) into a TRect (Left Top Right Bottom);
// 1 value = all sides, 2 = vert/horiz, 4 = explicit.
function ParsePadding(const ARaw: string; Vars: TStrings): TRect;
var
  parts: TStringList;
  v: array[0..3] of Integer;
  i: Integer;
begin
  parts := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := True;
    parts.DelimitedText := Trim(ARaw);
    // drop empties produced by multiple spaces
    for i := parts.Count - 1 downto 0 do
      if Trim(parts[i]) = '' then parts.Delete(i);
    for i := 0 to 3 do v[i] := 0;
    case parts.Count of
      1:
        begin
          v[0] := TyEvalLength(parts[0], Vars);
          v[1] := v[0]; v[2] := v[0]; v[3] := v[0];
        end;
      2:
        begin
          v[1] := TyEvalLength(parts[0], Vars); // top
          v[3] := v[1];                          // bottom
          v[0] := TyEvalLength(parts[1], Vars); // left
          v[2] := v[0];                          // right
        end;
      4:
        begin
          v[1] := TyEvalLength(parts[0], Vars); // top
          v[2] := TyEvalLength(parts[1], Vars); // right
          v[3] := TyEvalLength(parts[2], Vars); // bottom
          v[0] := TyEvalLength(parts[3], Vars); // left
        end;
    else
      raise Exception.CreateFmt('Invalid padding: %s', [ARaw]);
    end;
    Result := Rect(v[0], v[1], v[2], v[3]);
  finally
    parts.Free;
  end;
end;

// Parse 'linear-gradient(<angle>deg, <colorA>, <colorB>)' into a gradient fill.
function ParseLinearGradient(const ARaw: string; Vars: TStrings): TTyFill;
var
  inner, angleTok: string;
  p, q: Integer;
  parts: TStringList;
  fmt: TFormatSettings;
begin
  Result.Kind := tfkLinearGradient;
  Result.Color := tyTransparent;
  Result.ImagePath := '';
  Result.SliceInsets := Rect(0, 0, 0, 0);
  Result.GradAngleDeg := 0;
  p := Pos('(', ARaw);
  q := Length(ARaw);
  while (q > p) and (ARaw[q] <> ')') do Dec(q);
  inner := Copy(ARaw, p + 1, q - p - 1);
  parts := TStringList.Create;
  try
    // angle, colorA, colorB; nested-paren-aware so function color args with
    // inner commas (e.g. 'lighten(--accent, 16%)') are not mis-split.
    SplitArgs(inner, parts);
    if parts.Count <> 3 then
      raise Exception.CreateFmt('Invalid linear-gradient: %s', [ARaw]);
    angleTok := LowerCase(Trim(parts[0]));
    if (Length(angleTok) >= 3) and (Copy(angleTok, Length(angleTok) - 2, 3) = 'deg') then
      angleTok := Trim(Copy(angleTok, 1, Length(angleTok) - 3));
    fmt := DefaultFormatSettings;
    fmt.DecimalSeparator := '.';
    Result.GradAngleDeg := StrToFloat(angleTok, fmt);
    Result.GradFrom := TyEvalColor(Trim(parts[1]), Vars);
    Result.GradTo := TyEvalColor(Trim(parts[2]), Vars);
  finally
    parts.Free;
  end;
end;

// Parse 'url(path) slice(t r b l)' into a nine-slice fill.
function ParseNineSlice(const ARaw: string): TTyFill;
var
  lo, urlInner, sliceInner: string;
  pu, qu, ps, qs: Integer;
  nums: TStringList;
  t, r, b, l: Integer;
begin
  Result.Kind := tfkNineSlice;
  Result.Color := tyTransparent;
  Result.GradAngleDeg := 0;
  lo := ARaw;
  pu := Pos('url(', LowerCase(lo));
  if pu = 0 then raise Exception.CreateFmt('background-image needs url(): %s', [ARaw]);
  qu := pu + 4;
  while (qu <= Length(lo)) and (lo[qu] <> ')') do Inc(qu);
  urlInner := Trim(Copy(lo, pu + 4, qu - (pu + 4)));
  // strip optional quotes
  if (Length(urlInner) >= 2) and ((urlInner[1] = '''') or (urlInner[1] = '"')) then
    urlInner := Copy(urlInner, 2, Length(urlInner) - 2);
  // The CSS lexer may insert spaces around '.' in unquoted URL paths (e.g.
  // 'panel. png' for 'panel.png'); remove them so the path round-trips correctly.
  // v1 limitation: url() asset paths must not contain spaces, because spaces
  // are stripped unconditionally here to reconstruct dotted filenames (e.g. foo.png).
  Result.ImagePath := StringReplace(urlInner, ' ', '', [rfReplaceAll]);
  ps := Pos('slice(', LowerCase(lo));
  if ps = 0 then raise Exception.CreateFmt('background-image needs slice(): %s', [ARaw]);
  qs := ps + 6;
  while (qs <= Length(lo)) and (lo[qs] <> ')') do Inc(qs);
  sliceInner := Trim(Copy(lo, ps + 6, qs - (ps + 6)));
  nums := TStringList.Create;
  try
    nums.Delimiter := ' ';
    nums.StrictDelimiter := False; // collapse runs of spaces
    nums.DelimitedText := sliceInner;
    if nums.Count <> 4 then
      raise Exception.CreateFmt('slice() needs 4 values: %s', [ARaw]);
    t := StrToInt(Trim(nums[0]));
    r := StrToInt(Trim(nums[1]));
    b := StrToInt(Trim(nums[2]));
    l := StrToInt(Trim(nums[3]));
    Result.SliceInsets := Rect(l, t, r, b); // TRect = Left,Top,Right,Bottom
  finally
    nums.Free;
  end;
end;

// Parse 'shadow: <offX> <offY> <blur> <color>' (logical px + color expr).
procedure ApplyShadow(var AStyle: TTyStyleSet; const ARaw: string; Vars: TStrings);
var
  parts: TStringList;
  i: Integer;
begin
  parts := TStringList.Create;
  try
    parts.Delimiter := ' ';
    parts.StrictDelimiter := False;
    parts.DelimitedText := Trim(ARaw);
    for i := parts.Count - 1 downto 0 do
      if Trim(parts[i]) = '' then parts.Delete(i);
    if parts.Count <> 4 then
      raise Exception.CreateFmt('Invalid shadow: %s', [ARaw]);
    AStyle.ShadowOffset.X := TyEvalLength(parts[0], Vars);
    AStyle.ShadowOffset.Y := TyEvalLength(parts[1], Vars);
    AStyle.ShadowBlur := TyEvalLength(parts[2], Vars);
    AStyle.ShadowColor := TyEvalColor(parts[3], Vars);
  finally
    parts.Free;
  end;
end;

function TyApplyDeclaration(var AStyle: TTyStyleSet; const AProp, ARawValue: string;
  Vars: TStrings): Boolean;
var
  prop, raw: string;
  fill: TTyFill;
begin
  Result := True;
  prop := LowerCase(Trim(AProp));
  raw := Trim(ARawValue);
  if prop = 'background' then
  begin
    if LowerCase(Copy(raw, 1, 16)) = 'linear-gradient(' then
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
  else if prop = 'background-image' then
  begin
    AStyle.Background := ParseNineSlice(raw);
    Include(AStyle.Present, tpBackground);
  end
  else if prop = 'shadow' then
  begin
    // shadow: <offsetX> <offsetY> <blur> <color>  (logical px)
    ApplyShadow(AStyle, raw, Vars);
    Include(AStyle.Present, tpShadow);
  end
  else if prop = 'color' then
  begin
    AStyle.TextColor := TyEvalColor(raw, Vars);
    Include(AStyle.Present, tpTextColor);
  end
  else if prop = 'border-color' then
  begin
    AStyle.BorderColor := TyEvalColor(raw, Vars);
    Include(AStyle.Present, tpBorderColor);
  end
  else if prop = 'border-width' then
  begin
    AStyle.BorderWidth := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpBorderWidth);
  end
  else if prop = 'border-radius' then
  begin
    AStyle.BorderRadius := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpBorderRadius);
  end
  else if prop = 'padding' then
  begin
    AStyle.Padding := ParsePadding(raw, Vars);
    Include(AStyle.Present, tpPadding);
  end
  else if prop = 'font-family' then
  begin
    AStyle.FontName := raw;
    Include(AStyle.Present, tpFontName);
  end
  else if prop = 'font-size' then
  begin
    AStyle.FontSize := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpFontSize);
  end
  else if prop = 'font-weight' then
  begin
    if LowerCase(raw) = 'bold' then
      AStyle.FontWeight := 700
    else if LowerCase(raw) = 'normal' then
      AStyle.FontWeight := 400
    else
      AStyle.FontWeight := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpFontWeight);
  end
  else if prop = 'opacity' then
  begin
    AStyle.Opacity := TyEvalFloat(raw, Vars);
    Include(AStyle.Present, tpOpacity);
  end
  else
    Result := False;
end;

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

procedure TTyStyleModel.LoadFromCss(const ASource: string);
begin
  LoadInto(FRules, FVars, ASource);
end;

procedure TTyStyleModel.LoadFromFile(const AFileName: string);
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AFileName);
    LoadFromCss(sl.Text);
  finally
    sl.Free;
  end;
end;

function TTyStyleModel.ResolveLayer(ARules: TFPList; const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
const
  // fixed state application order: hover, focused, active, disabled
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
    variants.StrictDelimiter := False; // collapse multiple spaces
    variants.DelimitedText := Trim(AStyleClass);
    // 1) type base rule (no variant, no state)
    if FindStyleIn(ARules, ATypeKey, '', False, tysNormal, found) then
      TyMergeStyleSet(Result, found);
    // 2) each variant token, in textual order, base-state rule (TypeName.variant)
    for vi := 0 to variants.Count - 1 do
    begin
      v := Trim(variants[vi]);
      if v = '' then Continue;
      if FindStyleIn(ARules, ATypeKey, v, False, tysNormal, found) then
        TyMergeStyleSet(Result, found);
    end;
    // 3) state layers present in AStates, in fixed order;
    //    for each state apply TypeName:state then each TypeName.variant:state
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

end.
