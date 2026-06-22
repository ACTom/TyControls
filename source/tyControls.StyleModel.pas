unit tyControls.StyleModel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types,
  tyControls.Types, tyControls.Css.Parser, tyControls.Css.Values,
  tyControls.DefaultTheme, tyControls.ThemeBundle, tyControls.SystemTheme;

type
  { P4 (A5 / D8). Resolver hooks for the dynamic OS tokens. RebuildMergedVars
    post-processes the merged var set: any var whose VALUE is exactly 'system-accent'
    is replaced by TySystemAccentHook (a '#RRGGBB' string) and any whose value is
    exactly 'system-mode' by TySystemModeHook ('light'/'dark'/''). The hooks default
    to the real OS probes (tyControls.SystemTheme) but are swappable so tests can
    inject a deterministic accent/mode without touching the registry. }
  TTySystemAccentHook = function: string;
  TTySystemModeHook = function: string;

var
  { Default = live OS detection. A test may point these at a stub for determinism. }
  TySystemAccentHook: TTySystemAccentHook;
  TySystemModeHook: TTySystemModeHook;

type
  { One parsed rule: selector match + its RAW declarations (Prop, RawValue), kept
    unevaluated so ResolveStyle evaluates them against the merged var set (D2). }
  TTyStyleRuleEntry = class
    TypeName: string;
    Variant: string;
    HasState: Boolean;
    State: TTyState;
    Decls: array of TTyCssDeclaration;
  end;

  TTyStyleModel = class
  private
    FRules: TFPList;          // user layer — owns TTyStyleRuleEntry
    FVars: TStringList;       // user :root vars, name=value (no leading --)
    FBaseRules: TFPList;      // built-in default layer — owns TTyStyleRuleEntry
    FBaseVars: TStringList;   // built-in :root vars
    FMergedVars: TStringList; // FBaseVars (+) FVars (+) active @mode vars; rebuilt on load/clear/SetMode
    FThemeBaseDir: string;    // dir of the loaded theme file; restored into GThemeBaseDir at resolve so url() assets resolve (merge-then-resolve evaluates url() at resolve time, not load time)
    FVersion: Cardinal;       // bumped on every load/clear; the §3.8 switch/cache anchor
    FPropertyCascade: Boolean; // A7: False=all-or-nothing (default, golden); True=base->user per-prop merge
    FMode: string;            // P3 (D7): active @mode name ('' = no mode override)
    FModeVars: TStringList;   // loaded @mode blocks: Names[i]=lower(mode), Objects[i]=owned TStringList of that mode's vars
    procedure ClearList(ARules: TFPList);
    procedure ClearModeVars;
    function ModeVarsFor(const AMode: string): TStringList;
    procedure RebuildMergedVars;
    procedure ValidateRules(ARules: TFPList; AVars: TStrings);
    procedure LoadInto(ARules: TFPList; AVars: TStrings; const ASource: string;
      AReplace: Boolean = True);
    procedure ExpandSheet(ASheet: TTyCssStylesheet; ATmpRules: TFPList;
      ATmpVars, ATmpModes: TStrings; const ABaseDir: string; AActive, ADone: TStrings; ADepth: Integer);
    procedure AddSheetInto(ASheet: TTyCssStylesheet; ATmpRules: TFPList; ATmpVars, ATmpModes: TStrings);
    procedure AddEntryTo(ARules: TFPList; const ATypeName, AVariant: string;
      AHasState: Boolean; AState: TTyState; const ADecls: array of TTyCssDeclaration);
    procedure ApplyAllMatching(ARules: TFPList; const ATypeName, AVariant: string;
      AHasState: Boolean; AState: TTyState; var AResult: TTyStyleSet);
    procedure ApplyEntry(var AResult: TTyStyleSet; AEntry: TTyStyleRuleEntry);
    procedure ResolveLayer(ARules: TFPList; const ATypeKey, AStyleClass: string;
      AStates: TTyStateSet; var AResult: TTyStyleSet);
    function UserHasTypeKey(const ATypeKey: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadFromCss(const ASource: string);          // raises ETyCssError (replaces user layer)
    procedure LoadFromCssAdditive(const ASource: string);  // appends rules + merges vars (A6)
    procedure LoadFromFile(const AFileName: string);
    { C (Phase 2): load a theme from a bundle SOURCE (directory or zip), the §3.8 REPLACE
      path. RootCss is the entry stylesheet; url()/@import resolve relative to the bundle
      root. For a DIRECTORY source (AssetBaseDir<>'') resolution reuses the existing
      file-based path (GThemeBaseDir), so a dir bundle is byte-identical to
      LoadFromFile(<dir>/theme.tycss). For a ZIP source (AssetBaseDir='') the CSS text is
      loaded directly; zipped IMAGE assets are a documented follow-up (not yet resolved). }
    procedure LoadFromSource(ASource: ITyThemeSource);
    function ResolveStyle(const ATypeKey, AStyleClass: string; AStates: TTyStateSet): TTyStyleSet;
    { Distinct non-empty variant names defined for ATypeKey across the base + user layers
      (ignores :state). Powers the design-time StyleClass dropdown so it lists exactly the
      classes the active theme defines for THIS control type. Exact-case dedupe. }
    procedure GetVariantsForType(const ATypeKey: string; AList: TStrings);
    { A9 per-instance StyleOverride (§3.1 layer 2). Parse a bare declaration block (no
      selector) and evaluate each declaration against the LIVE merged var set, so a
      'var(--accent)' in an override binds to the active theme (and re-binds after a
      switch, since the override cache is keyed by ThemeVersion on the control side).
      Returns a TTyStyleSet whose Present flags cover only the properties the override
      mentions; TyMergeStyleSet then overlays those on top of the resolved theme style.
      Bad-value tolerant: a parse failure yields EmptyStyleSet; a single bad declaration
      (e.g. var(--undefined)) is skipped (try/except) so an override never crashes paint. }
    function ResolveOverride(const ASource: string): TTyStyleSet;
    function MaxGlassBlur: Integer;   // largest glass-blur any active rule requests (0 = none)
    { P3 (D7) single-file dual-mode. Select which loaded '@mode NAME' (its inner :root)
      block's vars overlay the user :root in the merged var set. SetMode re-runs the merge
      and bumps ThemeVersion so the §3.8 cache key changes and controls re-resolve. An
      unknown/empty mode applies NO mode vars (graceful): the theme resolves as if it had
      only its shared body + plain :root. }
    procedure SetMode(const AMode: string);
    { P4 (D8). Re-run RebuildMergedVars (re-resolving the 'system-accent'/'system-mode'
      sentinels to the CURRENT OS state via the hooks) and bump ThemeVersion, WITHOUT a
      mode switch — for a live OS ACCENT change where the light/dark scheme is unchanged.
      Inert for themes that use no sentinel (the merge is identical), but always bumps the
      version + lets the caller repaint. }
    procedure RefreshSystemTokens;
    property Mode: string read FMode write SetMode;
    property ThemeVersion: Cardinal read FVersion;  // bumps on every load/clear
    { A7 property cascade. False (default) = today's all-or-nothing: a user rule for a
      typeKey suppresses the ENTIRE built-in layer for that typeKey (golden baseline).
      True = ResolveStyle ALWAYS applies the base layer then the user layer, so a thin
      theme that sets only one property inherits the base's other properties (省略=继承,
      D4). Default stays False so the golden is byte-identical until a theme opts in. }
    property PropertyCascade: Boolean read FPropertyCascade write FPropertyCascade;
  end;

procedure TyMergeStyleSet(var ABase: TTyStyleSet; const AOver: TTyStyleSet);

// Apply one CSS declaration (prop name + raw value) to a style set, resolving
// values against Vars, and set the matching Present flag. Returns False for
// unknown property names (caller may ignore).
function TyApplyDeclaration(var AStyle: TTyStyleSet; const AProp, ARawValue: string;
  Vars: TStrings): Boolean;

implementation

{ P4 (A5 / D8). Swap any var whose VALUE is exactly the sentinel 'system-accent' /
  'system-mode' for the live OS state (a '#RRGGBB' hex / 'light'|'dark'|''). Used by
  both RebuildMergedVars (the resolve-time var set) and LoadInto's validation set, so
  a theme seeded with 'system-accent' validates AND resolves to a concrete colour. }
procedure ApplySystemTokens(AVars: TStrings);
var i: Integer; val: string;
begin
  if AVars = nil then Exit;
  for i := 0 to AVars.Count - 1 do
  begin
    val := LowerCase(Trim(AVars.ValueFromIndex[i]));
    if (val = 'system-accent') and Assigned(TySystemAccentHook) then
      AVars.ValueFromIndex[i] := TySystemAccentHook()
    else if (val = 'system-mode') and Assigned(TySystemModeHook) then
      AVars.ValueFromIndex[i] := TySystemModeHook();
  end;
end;

procedure TyMergeStyleSet(var ABase: TTyStyleSet; const AOver: TTyStyleSet);
begin
  if tpBackground   in AOver.Present then ABase.Background   := AOver.Background;
  if tpTextColor    in AOver.Present then ABase.TextColor    := AOver.TextColor;
  if tpBorderColor  in AOver.Present then ABase.BorderColor  := AOver.BorderColor;
  if tpBorderWidth  in AOver.Present then ABase.BorderWidth  := AOver.BorderWidth;
  if tpBorderStyle  in AOver.Present then ABase.BorderStyle  := AOver.BorderStyle;
  if tpBorderRadius in AOver.Present then
  begin
    ABase.BorderRadius := AOver.BorderRadius;
    ABase.Radius       := AOver.Radius;
  end;
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
  if tpOutline in AOver.Present then
  begin
    ABase.OutlineColor  := AOver.OutlineColor;
    ABase.OutlineWidth  := AOver.OutlineWidth;
    ABase.OutlineOffset := AOver.OutlineOffset;
  end;
  // Glass rides Background but merges NARROWLY: a ':hover { glass-tint: ... }' rule
  // with no background: must not blank the base Background (only tpBackground does that).
  if tpGlass in AOver.Present then
  begin
    ABase.Background.GlassBlur := AOver.Background.GlassBlur;
    ABase.Background.GlassTint := AOver.Background.GlassTint;
  end;
  if tpBgUnderTitle in AOver.Present then
    ABase.BackgroundUnderTitlebar := AOver.BackgroundUnderTitlebar;
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
      3:
        begin
          v[1] := TyEvalLength(parts[0], Vars); // top
          v[0] := TyEvalLength(parts[1], Vars); // left
          v[2] := v[0];                          // right
          v[3] := TyEvalLength(parts[2], Vars); // bottom
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

const
  cMaxImportDepth = 32;  // hard backstop against runaway @import recursion

var
  GThemeBaseDir: string = '';  // set by LoadFromFile so url() resolves vs the theme dir

{ Resolve a url() asset path. Strips spaces (the lexer can insert them around dots),
  and when the model was loaded from a FILE, falls back to a path relative to the
  theme file's directory if the raw path doesn't exist as-is. }
function ResolveAssetPath(const APath: string): string;
var p: string;
begin
  p := StringReplace(APath, ' ', '', [rfReplaceAll]);
  Result := p;
  if (p <> '') and (GThemeBaseDir <> '') and not FileExists(p)
     and FileExists(GThemeBaseDir + p) then
    Result := GThemeBaseDir + p;
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
  Result.ImagePath := ResolveAssetPath(urlInner);
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

// Parse 'url(path)' into a plain image fill (no slice). Mode defaults to cover and
// is overridden by background-size; blur by background-blur.
function ParsePlainImage(const ARaw: string): TTyFill;
var
  lo, urlInner: string;
  pu, qu: Integer;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkImage;
  Result.ImageMode := timCover;
  lo := ARaw;
  pu := Pos('url(', LowerCase(lo));
  if pu = 0 then raise Exception.CreateFmt('background-image needs url(): %s', [ARaw]);
  qu := pu + 4;
  while (qu <= Length(lo)) and (lo[qu] <> ')') do Inc(qu);
  urlInner := Trim(Copy(lo, pu + 4, qu - (pu + 4)));
  if (Length(urlInner) >= 2) and ((urlInner[1] = '''') or (urlInner[1] = '"')) then
    urlInner := Copy(urlInner, 2, Length(urlInner) - 2);
  Result.ImagePath := ResolveAssetPath(urlInner);
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

// Parse the 'border' shorthand: 'border: <width> [style] <color>'. Tokens are
// split on TOP-LEVEL whitespace but paren-aware, so function/var() values such
// as 'var(--a)' or 'rgb(0, 0, 0)' survive as a single token despite inner
// spaces and commas. Each token is classified by shape: 'solid'/'none' -> style;
// a leading digit -> width; anything else -> color. A border shorthand always
// implies a style, so an omitted style defaults to solid (and is marked present).
procedure ApplyBorderShorthand(var AStyle: TTyStyleSet; const ARaw: string; Vars: TStrings);
var
  toks: TStringList;
  i, depth, start: Integer;
  ch: Char;
  tok, lc: string;
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
      lc := LowerCase(tok);
      if (lc = 'solid') or (lc = 'none') then
      begin
        if lc = 'none' then AStyle.BorderStyle := tbsNone else AStyle.BorderStyle := tbsSolid;
        Include(AStyle.Present, tpBorderStyle);
      end
      else if (tok <> '') and (tok[1] in ['0'..'9']) then
      begin
        AStyle.BorderWidth := TyEvalLength(tok, Vars);
        Include(AStyle.Present, tpBorderWidth);
      end
      else
      begin
        AStyle.BorderColor := TyEvalColor(tok, Vars);
        Include(AStyle.Present, tpBorderColor);
      end;
    end;
    // shorthand implies a style even if omitted -> default solid present
    if not (tpBorderStyle in AStyle.Present) then
    begin
      AStyle.BorderStyle := tbsSolid;
      Include(AStyle.Present, tpBorderStyle);
    end;
  finally
    toks.Free;
  end;
end;

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
    parts.StrictDelimiter := True;
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

function TyApplyDeclaration(var AStyle: TTyStyleSet; const AProp, ARawValue: string;
  Vars: TStrings): Boolean;
var
  prop, raw: string;
  fill: TTyFill;
begin
  Result := True;
  prop := LowerCase(Trim(AProp));
  raw := Trim(ARawValue);
  if (prop = 'background') or (prop = 'background-color') then
  begin
    if LowerCase(raw) = 'none' then
    begin
      // explicit empty background (D4): no fill drawn
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
  else if prop = 'background-image' then
  begin
    if Pos('slice(', LowerCase(raw)) > 0 then
      AStyle.Background := ParseNineSlice(raw)    // url(...) slice(t r b l) -> 9-slice
    else
      AStyle.Background := ParsePlainImage(raw);  // url(...) -> plain image (cover)
    Include(AStyle.Present, tpBackground);
  end
  else if prop = 'background-size' then
  begin
    if LowerCase(raw) = 'stretch' then AStyle.Background.ImageMode := timStretch
    else if LowerCase(raw) = 'center' then AStyle.Background.ImageMode := timCenter
    else AStyle.Background.ImageMode := timCover;
  end
  else if prop = 'background-blur' then
    AStyle.Background.Blur := StrToIntDef(
      Trim(StringReplace(LowerCase(raw), 'px', '', [rfReplaceAll])), 0)
  else if prop = 'glass-blur' then
  begin
    AStyle.Background.GlassBlur := TyEvalLength(raw, Vars);
    Include(AStyle.Present, tpGlass);
  end
  else if prop = 'glass-tint' then
  begin
    AStyle.Background.GlassTint := TyEvalColor(raw, Vars);
    Include(AStyle.Present, tpGlass);
  end
  else if prop = 'background-under-titlebar' then
  begin
    AStyle.BackgroundUnderTitlebar := (LowerCase(raw) = 'true');
    Include(AStyle.Present, tpBgUnderTitle);
  end
  else if prop = 'window-shadow' then
  begin
    // TyForm only: toggle the OS-native window drop shadow (on/off; the OS owns the look)
    AStyle.WindowShadow := (LowerCase(raw) = 'true');
    Include(AStyle.Present, tpWindowShadow);
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
  else if prop = 'border' then
  begin
    // shorthand: border: <width> [style] <color>
    ApplyBorderShorthand(AStyle, raw, Vars);
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
    ApplyBorderRadius(AStyle, raw, Vars);
  end
  else if prop = 'border-style' then
  begin
    if LowerCase(raw) = 'none' then
      AStyle.BorderStyle := tbsNone
    else
      AStyle.BorderStyle := tbsSolid;
    Include(AStyle.Present, tpBorderStyle);
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
  else if prop = 'outline' then
  begin
    ApplyOutline(AStyle, raw, Vars);
  end
  else if prop = 'outline-offset' then
  begin
    AStyle.OutlineOffset := TyEvalLength(raw, Vars);
    // offset is meaningful only alongside 'outline'; it does not itself set tpOutline
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
  FMergedVars := TStringList.Create;
  FModeVars := TStringList.Create;
  { Seed the built-in default skin once. It is never cleared by user theme
    loads — it only applies (per-typeKey) when the user layer is silent. }
  LoadInto(FBaseRules, FBaseVars, TyBuiltinThemeCss);
end;

destructor TTyStyleModel.Destroy;
begin
  ClearList(FRules);
  ClearList(FBaseRules);
  ClearModeVars;
  FRules.Free;
  FBaseRules.Free;
  FVars.Free;
  FBaseVars.Free;
  FMergedVars.Free;
  FModeVars.Free;
  inherited Destroy;
end;

procedure TTyStyleModel.ClearModeVars;
{ Free every owned per-mode TStringList, then clear the index list. }
var i: Integer;
begin
  for i := 0 to FModeVars.Count - 1 do
    FModeVars.Objects[i].Free;
  FModeVars.Clear;
end;

function TTyStyleModel.ModeVarsFor(const AMode: string): TStringList;
{ The loaded vars for AMode (case-insensitive), or nil if there is no such @mode block. }
var idx: Integer;
begin
  Result := nil;
  if AMode = '' then Exit;
  idx := FModeVars.IndexOf(LowerCase(Trim(AMode)));
  if idx >= 0 then
    Result := TStringList(FModeVars.Objects[idx]);
end;

procedure TTyStyleModel.Clear;
{ Clears only the USER layer (rules + :root vars + @mode blocks); the built-in base
  layer is permanent. The active FMode name is kept (a re-load may bring it back), but
  with no mode blocks it simply contributes nothing. }
begin
  ClearList(FRules);
  FVars.Clear;
  ClearModeVars;
  FThemeBaseDir := '';   // no user theme -> no asset base dir
  RebuildMergedVars;
  Inc(FVersion);
end;

procedure TTyStyleModel.ClearList(ARules: TFPList);
var i: Integer;
begin
  for i := 0 to ARules.Count - 1 do
    TObject(ARules[i]).Free;
  ARules.Clear;
end;

procedure TTyStyleModel.SetMode(const AMode: string);
{ P3 (D7). Switch the active @mode and re-merge so the new mode's :root overrides win.
  Bumps ThemeVersion (the §3.8 switch/cache anchor) so override caches and any
  version-keyed consumers re-resolve. No-ops on an unchanged mode. }
begin
  if FMode = AMode then Exit;
  FMode := AMode;
  RebuildMergedVars;
  Inc(FVersion);
end;

procedure TTyStyleModel.RefreshSystemTokens;
{ P4 (D8). Re-merge (re-resolving system-* sentinels via the hooks) + bump version,
  with no mode change — the live-accent-change path. See the interface comment. }
begin
  RebuildMergedVars;
  Inc(FVersion);
end;

procedure TTyStyleModel.RebuildMergedVars;
{ Merge the token layers ONCE per load/mode-switch: base derives first, the user :root
  overrides same-named vars, then the ACTIVE @mode block's vars overlay on top (so a
  dual-mode theme's per-mode :root wins, P3/D7). ResolveStyle evaluates every rule
  against this set, so overriding a SEED re-derives the whole family (var-on-var resolves
  through TyEvalColor at resolve time). An unset/unknown FMode contributes nothing. }
var i: Integer; mv: TStringList;
begin
  FMergedVars.Clear;
  FMergedVars.Assign(FBaseVars);
  for i := 0 to FVars.Count - 1 do
    FMergedVars.Values[FVars.Names[i]] := FVars.ValueFromIndex[i];
  mv := ModeVarsFor(FMode);
  if mv <> nil then
    for i := 0 to mv.Count - 1 do
      FMergedVars.Values[mv.Names[i]] := mv.ValueFromIndex[i];
  { P4 (A5 / D8) dynamic OS tokens. AFTER the merge, swap any 'system-accent' /
    'system-mode' sentinel VALUE for the live OS state, so '--accent: system-accent;'
    resolves to the OS accent and ResolveStyle sees a concrete hex/mode. }
  ApplySystemTokens(FMergedVars);
end;

procedure TTyStyleModel.ValidateRules(ARules: TFPList; AVars: TStrings);
{ Load-time fail-fast: try-evaluate every declaration against AVars once, BEFORE the
  load commits, so a bad value (undefined var / malformed expression) raises with the
  PREVIOUS theme intact — preserving the old eager-bake's "broken load throws + keeps
  the old theme" contract now that real evaluation is deferred to resolve time. }
var i, di: Integer; e: TTyStyleRuleEntry; dummy: TTyStyleSet;
begin
  for i := 0 to ARules.Count - 1 do
  begin
    e := TTyStyleRuleEntry(ARules[i]);
    dummy := EmptyStyleSet;
    for di := 0 to High(e.Decls) do
      TyApplyDeclaration(dummy, e.Decls[di].Prop, e.Decls[di].RawValue, AVars);
  end;
end;

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

procedure TTyStyleModel.ApplyAllMatching(ARules: TFPList; const ATypeName, AVariant: string;
  AHasState: Boolean; AState: TTyState; var AResult: TTyStyleSet);
{ Apply EVERY matching entry's decls in list (FORWARD) order, so a later-appended
  entry (additive load / @import / a duplicate rule) overwrites only the properties it
  sets — per-property merge within a layer. Single-load themes have one entry per slot,
  so this degenerates to apply-one (golden unchanged); TestDuplicateRuleLastWins still
  passes (both entries apply forward, the later overwrites the field). }
var
  i: Integer;
  e: TTyStyleRuleEntry;
begin
  for i := 0 to ARules.Count - 1 do
  begin
    e := TTyStyleRuleEntry(ARules[i]);
    if SameText(e.TypeName, ATypeName) and SameText(e.Variant, AVariant)
       and (e.HasState = AHasState) and ((not AHasState) or (e.State = AState)) then
      ApplyEntry(AResult, e);
  end;
end;

procedure TTyStyleModel.ApplyEntry(var AResult: TTyStyleSet; AEntry: TTyStyleRuleEntry);
{ Apply a matched rule's raw declarations IN ORDER onto AResult, evaluating each
  against the merged vars. In-order application reproduces the eager bake exactly
  (overwrite-by-field; shorthands expand the same), so the pixel baseline holds. }
var di: Integer;
begin
  for di := 0 to High(AEntry.Decls) do
    TyApplyDeclaration(AResult, AEntry.Decls[di].Prop, AEntry.Decls[di].RawValue, FMergedVars);
end;

function TTyStyleModel.UserHasTypeKey(const ATypeKey: string): Boolean;
{ True if the user layer has ANY rule for this typeKey (base, variant or state).
  A single match suppresses the ENTIRE built-in layer for the typeKey — including
  base-state defaults the user didn't override. This is intentional (the theme
  owns the control's look once it touches it; no built-in property bleeds in).
  Repo themes always ship a base rule per typeKey, so a variant-only/state-only
  block — which would leave the plain base state empty — does not occur. }
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

procedure TTyStyleModel.AddSheetInto(ASheet: TTyCssStylesheet; ATmpRules: TFPList;
  ATmpVars, ATmpModes: TStrings);
{ Append ONE parsed sheet's own vars (over, new wins) + rules (after, so later wins via
  apply-all-forward) + @mode blocks into the accumulating tmp lists. Imports are NOT
  handled here — the recursive ExpandSheet has already spliced them in BEFORE calling
  this. @mode blocks accumulate into ATmpModes (Names[i]=lower(mode), Objects[i]=owned
  TStringList); a later sheet's same-mode vars override earlier ones (importer wins). }
var
  ri, si, vi, mi, idx: Integer;
  rule: TTyCssRule;
  sel: TTyCssSelector;
  mb: TTyCssModeBlock;
  dest: TStringList;
begin
  for vi := 0 to ASheet.RootVars.Count - 1 do
    ATmpVars.Values[ASheet.RootVars.Names[vi]] := ASheet.RootVars.ValueFromIndex[vi];
  for ri := 0 to ASheet.Rules.Count - 1 do
  begin
    rule := TTyCssRule(ASheet.Rules[ri]);
    for si := 0 to High(rule.Selectors) do
    begin
      sel := rule.Selectors[si];
      // store the RAW declarations; evaluation is deferred to ResolveStyle (D2)
      AddEntryTo(ATmpRules, sel.TypeName, sel.Variant, sel.HasState, sel.State,
                 rule.Declarations);
    end;
  end;
  // @mode blocks: merge into the per-mode accumulator (copy out before the sheet frees).
  for mi := 0 to ASheet.ModeBlocks.Count - 1 do
  begin
    mb := TTyCssModeBlock(ASheet.ModeBlocks[mi]);
    idx := ATmpModes.IndexOf(LowerCase(Trim(mb.Mode)));
    if idx < 0 then
    begin
      dest := TStringList.Create;
      ATmpModes.AddObject(LowerCase(Trim(mb.Mode)), dest);
    end
    else
      dest := TStringList(ATmpModes.Objects[idx]);
    for vi := 0 to mb.Vars.Count - 1 do
      dest.Values[mb.Vars.Names[vi]] := mb.Vars.ValueFromIndex[vi];
  end;
end;

procedure TTyStyleModel.ExpandSheet(ASheet: TTyCssStylesheet; ATmpRules: TFPList;
  ATmpVars, ATmpModes: TStrings; const ABaseDir: string; AActive, ADone: TStrings; ADepth: Integer);
{ Recursively flatten ASheet into (ATmpRules, ATmpVars): each @import target is loaded,
  parsed and expanded FIRST (so its rules/vars are the LOWER layer), then THIS sheet's own
  vars/rules are appended on top (so the importer overrides — same-name var override + a
  later-appended rule wins via ApplyAllMatching forward order). base-dir is a STACK
  (ABaseDir is this sheet's own dir; each child uses its OWN dir) for nested relative
  resolution. Cycle guard: AActive = ancestor stack (re-entry on it = cycle -> raise);
  ADone = permanently-seen set (idempotent diamond: a shared base loads ONCE). A hard
  depth cap is the backstop. All file I/O lives here; the parser stays pure. }
var
  ii: Integer;
  rawPath, resolved, canon, childDir: string;
  childSheet: TTyCssStylesheet;
  parser: TTyCssParser;
  sl: TStringList;
begin
  if ADepth > cMaxImportDepth then
    raise ETyCssError.CreateFmt('@import nesting too deep (> %d)', [cMaxImportDepth]);
  for ii := 0 to High(ASheet.Imports) do
  begin
    rawPath := Trim(ASheet.Imports[ii]);
    if rawPath = '' then
      raise ETyCssError.Create('@import has an empty path');
    // Resolve relative to THIS sheet's directory (the bundle/theme root). An absolute or
    // already-existing path is used as-is; otherwise fall back to ABaseDir + path.
    resolved := rawPath;
    if (ABaseDir <> '') and not FileExists(resolved)
       and FileExists(ABaseDir + rawPath) then
      resolved := ABaseDir + rawPath;
    if not FileExists(resolved) then
      raise ETyCssError.CreateFmt('@import target not found: "%s"', [rawPath]);
    canon := LowerCase(ExpandFileName(resolved));   // win32: case-insensitive canonical key
    if AActive.IndexOf(canon) >= 0 then
      raise ETyCssError.CreateFmt('@import cycle detected: "%s"', [rawPath]);
    if ADone.IndexOf(canon) >= 0 then
      Continue;   // diamond: this file was already spliced in once — skip (idempotent)

    sl := TStringList.Create;
    try
      sl.LoadFromFile(resolved);
      parser := TTyCssParser.Create(sl.Text);
      try
        childSheet := parser.Parse;
        try
          AActive.Add(canon);
          ADone.Add(canon);
          try
            childDir := ExtractFilePath(ExpandFileName(resolved));
            ExpandSheet(childSheet, ATmpRules, ATmpVars, ATmpModes, childDir,
                        AActive, ADone, ADepth + 1);
          finally
            AActive.Delete(AActive.IndexOf(canon));   // pop active stack (keep ADone)
          end;
        finally
          childSheet.Free;
        end;
      finally
        parser.Free;
      end;
    finally
      sl.Free;
    end;
  end;
  // THEN this sheet's own content, on top of everything it imported.
  AddSheetInto(ASheet, ATmpRules, ATmpVars, ATmpModes);
end;

procedure TTyStyleModel.LoadInto(ARules: TFPList; AVars: TStrings; const ASource: string;
  AReplace: Boolean);

  // Free every owned per-mode TStringList in a tmp mode accumulator, then the list.
  procedure FreeModeAccum(AModes: TStringList);
  var k: Integer;
  begin
    if AModes = nil then Exit;
    for k := 0 to AModes.Count - 1 do
      AModes.Objects[k].Free;
    AModes.Free;
  end;

var
  parser: TTyCssParser; sheet: TTyCssStylesheet;
  tmpRules: TFPList; tmpVars, tmpMerged, active, done, tmpModes: TStringList;
  ri, mi, vi, idx: Integer;
  mv, dest: TStringList;
begin
  tmpRules := TFPList.Create;
  tmpVars := TStringList.Create;
  tmpMerged := TStringList.Create;
  active := TStringList.Create;
  done := TStringList.Create;
  tmpModes := TStringList.Create;   // Names[i]=lower(mode), Objects[i]=owned TStringList
  try
    parser := TTyCssParser.Create(ASource);
    try
      sheet := parser.Parse;
      try
        // Recursively expand @import targets first (lower layer), then this sheet on top.
        // The top-level base dir is the active theme-file dir (GThemeBaseDir, set by
        // LoadFromFile; empty for LoadFromCss -> relative @import that doesn't exist errors).
        ExpandSheet(sheet, tmpRules, tmpVars, tmpModes, GThemeBaseDir, active, done, 0);
      finally
        sheet.Free;
      end;
    finally
      parser.Free;
    end;
    // Fail-fast on bad VALUES before committing (against base (+) this layer), so a
    // broken theme raises with the previous theme still active. A dual-mode theme's
    // SHARED body may reference vars defined ONLY inside @mode blocks (e.g. a per-mode
    // transparent-fill); union EVERY loaded mode's vars into the validation set so such
    // mode-conditional vars resolve here (a var defined in at least one mode is valid).
    tmpMerged.Assign(FBaseVars);
    if not AReplace then   // additive: the new rules also see the EXISTING user vars
      for ri := 0 to AVars.Count - 1 do
        tmpMerged.Values[AVars.Names[ri]] := AVars.ValueFromIndex[ri];
    for ri := 0 to tmpVars.Count - 1 do
      tmpMerged.Values[tmpVars.Names[ri]] := tmpVars.ValueFromIndex[ri];
    for mi := 0 to tmpModes.Count - 1 do
    begin
      mv := TStringList(tmpModes.Objects[mi]);
      for vi := 0 to mv.Count - 1 do
        tmpMerged.Values[mv.Names[vi]] := mv.ValueFromIndex[vi];
    end;
    // P4: resolve 'system-accent'/'system-mode' sentinels so a theme seeded with them
    // validates against a concrete OS colour/mode (not the unparseable literal token).
    ApplySystemTokens(tmpMerged);
    ValidateRules(tmpRules, tmpMerged);
    // Commit. Replace clears first; additive appends rules + merges vars (new wins) so
    // the appended entries sort LAST (importer/override wins via ApplyAllMatching order).
    if AReplace then
    begin
      ClearList(ARules);
      AVars.Clear;
      ClearModeVars;
      // §3.8 REPLACE adopts the new theme's asset base dir (set by LoadFromFile/
      // LoadFromSource via the GThemeBaseDir global; '' for a pure-string load).
      // Additive loads keep the current theme's dir (compose onto the active theme).
      FThemeBaseDir := GThemeBaseDir;
    end;
    for ri := 0 to tmpRules.Count - 1 do ARules.Add(tmpRules[ri]);
    tmpRules.Clear;   // ownership transferred to ARules; clear list only (do NOT free entries)
    if AReplace then
      AVars.Assign(tmpVars)
    else
      for ri := 0 to tmpVars.Count - 1 do
        AVars.Values[tmpVars.Names[ri]] := tmpVars.ValueFromIndex[ri];
    // Commit @mode blocks into model storage (replace cleared FModeVars above; additive
    // merges per-mode, new wins). The tmp per-mode lists are COPIED, not transferred.
    for mi := 0 to tmpModes.Count - 1 do
    begin
      mv := TStringList(tmpModes.Objects[mi]);
      idx := FModeVars.IndexOf(tmpModes[mi]);
      if idx < 0 then
      begin
        dest := TStringList.Create;
        FModeVars.AddObject(tmpModes[mi], dest);
      end
      else
        dest := TStringList(FModeVars.Objects[idx]);
      for vi := 0 to mv.Count - 1 do
        dest.Values[mv.Names[vi]] := mv.ValueFromIndex[vi];
    end;
  except
    ClearList(tmpRules);  // free entries built before the failure
    tmpRules.Free; tmpVars.Free; tmpMerged.Free; active.Free; done.Free;
    FreeModeAccum(tmpModes);
    raise;
  end;
  tmpRules.Free; tmpVars.Free; tmpMerged.Free; active.Free; done.Free;
  FreeModeAccum(tmpModes);
  RebuildMergedVars;   // base (+) user (+) active @mode, for resolve-time evaluation
  Inc(FVersion);       // §3.8: every load bumps the version (cache/switch anchor)
end;

procedure TTyStyleModel.LoadFromCss(const ASource: string);
begin
  LoadInto(FRules, FVars, ASource, True);
end;

procedure TTyStyleModel.LoadFromCssAdditive(const ASource: string);
begin
  LoadInto(FRules, FVars, ASource, False);
end;

function TTyStyleModel.MaxGlassBlur: Integer;

  function ScanLayer(ARules: TFPList; ASkipUserKeys: Boolean): Integer;
  var
    i, di, gb: Integer;
    e: TTyStyleRuleEntry;
  begin
    Result := 0;
    for i := 0 to ARules.Count - 1 do
    begin
      e := TTyStyleRuleEntry(ARules[i]);
      // Honour the user-suppresses-base rule: skip base entries for typeKeys the
      // user theme defines (their base glass tokens are suppressed by ResolveStyle).
      if ASkipUserKeys and UserHasTypeKey(e.TypeName) then Continue;
      // Entries now hold raw decls; evaluate any glass-blur against the merged vars.
      for di := 0 to High(e.Decls) do
        if LowerCase(Trim(e.Decls[di].Prop)) = 'glass-blur' then
        begin
          gb := TyEvalLength(e.Decls[di].RawValue, FMergedVars);
          if gb > Result then Result := gb;
        end;
    end;
  end;

var
  u, b: Integer;
begin
  u := ScanLayer(FRules, False);
  // A7: with property cascade ON, base entries are NOT suppressed by a user typeKey
  // (ResolveStyle always applies the base layer), so base glass-blur must count too.
  b := ScanLayer(FBaseRules, not FPropertyCascade);
  if u > b then Result := u else Result := b;
end;

procedure TTyStyleModel.LoadFromFile(const AFileName: string);
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AFileName);
    // Resolve url() assets relative to the theme file's folder while parsing.
    GThemeBaseDir := ExtractFilePath(ExpandFileName(AFileName));
    try
      LoadFromCss(sl.Text);
    finally
      GThemeBaseDir := '';
    end;
  finally
    sl.Free;
  end;
end;

procedure TTyStyleModel.LoadFromSource(ASource: ITyThemeSource);
var
  baseDir: string;
begin
  if ASource = nil then
    raise ETyCssError.Create('LoadFromSource: nil theme source');
  // A directory bundle carries an on-disk root; reuse the existing file-based url()/
  // @import resolution (GThemeBaseDir) so it is byte-identical to LoadFromFile of the
  // entry sheet (the golden guard). A zip bundle has no dir -> empty base (relative
  // file url()/@import won't resolve; that is the documented zipped-image follow-up).
  baseDir := ASource.AssetBaseDir;
  if baseDir <> '' then
    GThemeBaseDir := ExtractFilePath(ExpandFileName(IncludeTrailingPathDelimiter(baseDir)));
  try
    LoadFromCss(ASource.RootCss);
  finally
    GThemeBaseDir := '';
  end;
end;

procedure TTyStyleModel.ResolveLayer(ARules: TFPList; const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet; var AResult: TTyStyleSet);
const
  // fixed state application order: selected (resting layer) first, then the
  // transient feedback states, then disabled last (highest precedence). selected
  // goes first so hover/active can override its conflicting props per-property
  // while selected-only props (e.g. a border-color) survive.
  cStateOrder: array[0..4] of TTyState = (tysSelected, tysHover, tysFocused, tysActive, tysDisabled);
var
  variants: TStringList;
  vi, si: Integer;
  v: string;
  st: TTyState;
begin
  variants := TStringList.Create;
  try
    variants.Delimiter := ' ';
    variants.StrictDelimiter := False; // collapse multiple spaces
    variants.DelimitedText := Trim(AStyleClass);
    // 1) type base rule (no variant, no state)
    ApplyAllMatching(ARules, ATypeKey, '', False, tysNormal, AResult);
    // 2) each variant token, in textual order, base-state rule (TypeName.variant)
    for vi := 0 to variants.Count - 1 do
    begin
      v := Trim(variants[vi]);
      if v = '' then Continue;
      ApplyAllMatching(ARules, ATypeKey, v, False, tysNormal, AResult);
    end;
    // 3) state layers present in AStates, in fixed order;
    //    for each state apply TypeName:state then each TypeName.variant:state
    for si := 0 to High(cStateOrder) do
    begin
      st := cStateOrder[si];
      if not (st in AStates) then Continue;
      ApplyAllMatching(ARules, ATypeKey, '', True, st, AResult);
      for vi := 0 to variants.Count - 1 do
      begin
        v := Trim(variants[vi]);
        if v = '' then Continue;
        ApplyAllMatching(ARules, ATypeKey, v, True, st, AResult);
      end;
    end;
  finally
    variants.Free;
  end;
end;

function TTyStyleModel.ResolveStyle(const ATypeKey, AStyleClass: string;
  AStates: TTyStateSet): TTyStyleSet;
var savedBaseDir: string;
begin
  Result := EmptyStyleSet;
  { merge-then-resolve evaluates raw decls HERE, so a background-image url() is resolved
    now — long after LoadFromFile cleared the GThemeBaseDir global. Restore the loaded
    theme's dir for the duration of the resolve so ResolveAssetPath finds the asset. }
  savedBaseDir := GThemeBaseDir;
  GThemeBaseDir := FThemeBaseDir;
  try
    { A7. With PropertyCascade OFF (default) the built-in default layer applies only
      when the user theme defines NO rule for this typeKey — all-or-nothing: a fully-
      themed control gets no base bleed; the golden baseline. With PropertyCascade ON
      the base layer ALWAYS applies first, then the user layer overwrites per-property
      (omitted user props inherit the base; 省略=继承, D4). Both layers' raw declarations
      evaluate against the MERGED vars, so overriding a seed reaches base rules (D2). }
    if FPropertyCascade or not UserHasTypeKey(ATypeKey) then
      ResolveLayer(FBaseRules, ATypeKey, AStyleClass, AStates, Result);
    ResolveLayer(FRules, ATypeKey, AStyleClass, AStates, Result);
  finally
    GThemeBaseDir := savedBaseDir;
  end;
end;

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
  ScanLayer(FBaseRules);   // built-in defaults (always present)
  ScanLayer(FRules);       // user theme layer
end;

function TTyStyleModel.ResolveOverride(const ASource: string): TTyStyleSet;
{ §3.1 layer 2. Parse the bare override block, then apply each declaration against the
  MERGED var set (so var(--...) resolves through the active theme — the §3.8 token rule).
  Each declaration is guarded individually so one bad value (undefined var, malformed
  expression) is skipped, not fatal: an override must never crash painting (unlike a
  theme LOAD, which fails fast). A parse failure leaves the result empty (no overlay). }
var
  decls: TTyCssDeclarationArray;
  i: Integer;
  savedBaseDir: string;
begin
  Result := EmptyStyleSet;
  if not TyParseOverride(ASource, decls) then
    Exit;   // malformed fragment -> empty override (no Present flags -> overlays nothing)
  savedBaseDir := GThemeBaseDir;   // an override may set a background-image; resolve its url() vs the theme dir too
  GThemeBaseDir := FThemeBaseDir;
  try
    for i := 0 to High(decls) do
    begin
      try
        TyApplyDeclaration(Result, decls[i].Prop, decls[i].RawValue, FMergedVars);
      except
        on E: Exception do
          ; // skip a bad declaration; keep the other (good) override props
      end;
    end;
  finally
    GThemeBaseDir := savedBaseDir;
  end;
end;

{ ── default dynamic-token hooks (live OS detection) ──────────────────────────── }

function DefaultSystemAccentHook: string;
{ The detected OS accent as a '#RRGGBB' literal (alpha implied FF, which TyParseColor
  applies). Detection never raises; on failure TyDetectSystemAccent leaves a sensible
  fallback in c, so this always returns a parseable hex. }
var c: TTyColor;
begin
  TyDetectSystemAccent(c);   // True/False both leave a usable colour in c
  Result := Format('#%.2x%.2x%.2x', [TyRedOf(c), TyGreenOf(c), TyBlueOf(c)]);
end;

function DefaultSystemModeHook: string;
{ The detected OS scheme as 'light'/'dark', or '' when unknown (no override). }
begin
  Result := TySchemeToMode(TyDetectSystemScheme);
end;

initialization
  TySystemAccentHook := @DefaultSystemAccentHook;
  TySystemModeHook := @DefaultSystemModeHook;

end.
