unit tyControls.ThemeLint;
{ E23 (DX) — lint / strict mode: a NON-raising diagnostics pass for tooling.

  TyLintCss parses a .tycss source via the SAME TTyCssParser the engine uses, then
  walks the parsed sheet (its :root vars + @mode blocks + rules) collecting human-
  readable warnings WITHOUT ever raising. A clean theme yields an EMPTY array; the
  output is intended for an editor/CLI "problems" list, not for failing a load (the
  engine's own load path stays fail-fast — see StyleModel.ValidateRules).

  Four categories are reported, in a stable order (all UNKNOWN PROPERTY first, then
  UNDEFINED VARIABLE, then MISSING ASSET, then LOW CONTRAST), each scanned in source
  order so the output is deterministic:

    (1) unknown property '<prop>'        — a declaration whose Prop TyApplyDeclaration
                                           does not recognise (it returns False).
    (2) undefined variable --<name>      — a var(--name) / bare --name reference in any
                                           value (rule decls, :root, @mode, all import-
                                           flattened) whose name is neither defined in the
                                           sheet (RootVars + every @mode block's vars) nor a
                                           known dynamic token (system-accent / system-mode /
                                           transparent / none / ty-mode).
    (3) missing asset '<path>'           — a url(<path>) whose resolved file does not exist
                                           (only when ABaseDir<>''; an empty base dir means
                                           "assets not checkable" -> skipped, no false alarm).
    (4) low contrast on '<selector>'     — a rule that sets BOTH a SOLID background and a
                                           color whose perceived-luminance delta is below a
                                           small threshold (best-effort; both sides resolved
                                           against the sheet vars, guarded so an unresolvable
                                           value simply skips this check for that rule).

  Robustness: every evaluation is individually guarded. An undefined variable inside an
  otherwise-valid expression is reported by (2), not allowed to mask (1)/(3)/(4); a value
  that cannot be evaluated for the contrast check (e.g. a gradient, an image, a function
  the linter does not model) just opts that rule out of (4). @import targets are flattened
  (relative to ABaseDir) so a multi-file theme lints as a whole; an unreadable/cyclic import
  is itself reported rather than raised. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.StrConsts;

type
  TTyLintResult = array of string;

{ Lint ASource (a .tycss document). ABaseDir, when non-empty, is the theme root used to
  resolve url() assets and relative @import targets (pass the directory that CONTAINS the
  theme file, with or without a trailing path delimiter). Returns the warnings (possibly
  empty). NEVER raises. }
function TyLintCss(const ASource: string; const ABaseDir: string = ''): TTyLintResult;

implementation

uses
  tyControls.Types, tyControls.Css.Parser, tyControls.Css.Values,
  tyControls.StyleModel;

const
  // Below this perceived-luminance delta a bg/fg pair is flagged as low contrast. Chosen
  // small (0.10) so it only catches near-invisible text, never the legitimate themes (the
  // repo themes pair e.g. #1F2937 ink on #FFFFFF surface -> delta ~0.85).
  cLowContrastThreshold = 0.10;

{ ── helpers ─────────────────────────────────────────────────────────────────── }

procedure Emit(var AResult: TTyLintResult; const AMsg: string);
begin
  SetLength(AResult, Length(AResult) + 1);
  AResult[High(AResult)] := AMsg;
end;

{ Is Ch a character that may appear inside a CSS custom-property name (after the '--')? }
function IsVarNameChar(Ch: Char): Boolean;
begin
  Result := (Ch in ['a'..'z', 'A'..'Z', '0'..'9', '-', '_']);
end;

{ A token is a known dynamic value (not a user var) and so never "undefined". Covers the
  OS sentinels (system-accent/system-mode), the §3.4 empty-value keywords (transparent/none)
  and the mode token (ty-mode is supplied by the active @mode / OS, may be unset in :root). }
function IsKnownDynamicVar(const AName: string): Boolean;
var n: string;
begin
  n := LowerCase(AName);
  Result := (n = 'system-accent') or (n = 'system-mode') or (n = 'transparent')
         or (n = 'none') or (n = 'ty-mode');
end;

{ Add 'name' (no leading --, lower-cased) to ADefined if not already present. }
procedure AddDefined(ADefined: TStrings; const AName: string);
var n: string;
begin
  n := LowerCase(Trim(AName));
  if (n <> '') and (ADefined.IndexOf(n) < 0) then
    ADefined.Add(n);
end;

{ Scan ARaw for every '--name' reference (both 'var(--name)' and a bare '--name' leaf, the
  two forms the engine resolves) and append each as 'undefined variable --name' to AResult
  when its name is not in ADefined and not a known dynamic token. ASeen de-dupes within ONE
  value so 'a var(--x) b var(--x)' reports --x once; cross-value de-dupe is intentionally
  NOT done (the same undefined var in two rules is two problems to fix). }
procedure ScanValueForUndefinedVars(const ARaw: string; ADefined: TStrings;
  var AResult: TTyLintResult);
var
  i, j, n: Integer;
  name, key: string;
  seen: TStringList;
begin
  n := Length(ARaw);
  seen := TStringList.Create;
  try
    i := 1;
    while i < n do
    begin
      // a custom-property reference always starts with two dashes '--'
      if (ARaw[i] = '-') and (ARaw[i + 1] = '-') then
      begin
        j := i + 2;
        while (j <= n) and IsVarNameChar(ARaw[j]) do Inc(j);
        name := Copy(ARaw, i + 2, j - (i + 2));
        if name <> '' then
        begin
          key := LowerCase(name);
          if (seen.IndexOf(key) < 0) then
          begin
            seen.Add(key);
            if (ADefined.IndexOf(key) < 0) and not IsKnownDynamicVar(name) then
              Emit(AResult, Format(rsLintUndefinedVar, [name]));
          end;
        end;
        i := j;
      end
      else
        Inc(i);
    end;
  finally
    seen.Free;
  end;
end;

{ Find each 'url(<path>)' in ARaw and, when ABaseDir<>'', report any whose resolved file is
  missing. Quotes are stripped; the path is resolved as-is first, then relative to ABaseDir
  (mirroring ResolveAssetPath's fallback). Empty ABaseDir => assets not checkable => skip. }
procedure ScanValueForMissingAssets(const ARaw: string; const ABaseDir: string;
  var AResult: TTyLintResult);
var
  lo, path, resolved: string;
  p, q: Integer;
begin
  if ABaseDir = '' then Exit;
  lo := LowerCase(ARaw);
  p := Pos('url(', lo);
  while p > 0 do
  begin
    q := p + 4;
    while (q <= Length(ARaw)) and (ARaw[q] <> ')') do Inc(q);
    path := Trim(Copy(ARaw, p + 4, q - (p + 4)));
    // strip optional surrounding quotes
    if (Length(path) >= 2) and ((path[1] = '''') or (path[1] = '"')) then
      path := Copy(path, 2, Length(path) - 2);
    // the lexer can inject spaces around '.' in unquoted paths (panel. png); collapse them
    path := StringReplace(path, ' ', '', [rfReplaceAll]);
    if path <> '' then
    begin
      resolved := path;
      if not FileExists(resolved) and FileExists(ABaseDir + path) then
        resolved := ABaseDir + path;
      if not FileExists(resolved) then
        Emit(AResult, Format(rsLintMissingAsset, [path]));
    end;
    // advance past this url( and look for the next
    p := Pos('url(', Copy(lo, q + 1, Length(lo)));
    if p > 0 then p := p + q;  // re-base the offset onto the full string
  end;
end;

{ Selector text for a low-contrast message, e.g. 'TyButton', 'TyButton.primary',
  'TyButton:hover', 'TyButton.primary:hover'. Mirrors the engine's selector shape. }
function SelectorText(const ASel: TTyCssSelector): string;
const
  cStateName: array[TTyState] of string =
    ('', 'hover', 'active', 'focus', 'disabled', 'selected');
begin
  Result := ASel.TypeName;
  if ASel.Variant <> '' then
    Result := Result + '.' + ASel.Variant;
  if ASel.HasState then
    Result := Result + ':' + cStateName[ASel.State];
end;

{ For a single rule, if it sets BOTH a solid background and a text color, resolve both
  against ADefined-derived vars (AVars) and flag a low-contrast pair. Guarded throughout:
  any value that does not resolve to a SOLID colour (gradient/image/undefined var/unknown
  function) silently opts the rule out — best-effort, never a false alarm or a raise. The
  per-selector message uses the rule's FIRST selector. }
procedure ScanRuleForLowContrast(ARule: TTyCssRule; AVars: TStrings;
  var AResult: TTyLintResult);
var
  di: Integer;
  prop, raw, lc: string;
  hasBg, hasFg: Boolean;
  bg, fg: TTyColor;
  sel: string;
begin
  hasBg := False; hasFg := False;
  bg := tyTransparent; fg := tyTransparent;
  for di := 0 to High(ARule.Declarations) do
  begin
    prop := LowerCase(Trim(ARule.Declarations[di].Prop));
    raw := Trim(ARule.Declarations[di].RawValue);
    lc := LowerCase(raw);
    if (prop = 'background') or (prop = 'background-color') then
    begin
      // only a SOLID fill participates: skip none / linear-gradient / url() image
      if (lc = 'none') or (Copy(lc, 1, 16) = 'linear-gradient(')
         or (Pos('url(', lc) > 0) then
        hasBg := False
      else
        try
          bg := TyEvalColor(raw, AVars);
          // a fully/near transparent background gives no real contrast signal -> skip
          hasBg := TyAlphaOf(bg) >= 250;
        except
          hasBg := False;
        end;
    end
    else if prop = 'color' then
      try
        fg := TyEvalColor(raw, AVars);
        hasFg := TyAlphaOf(fg) >= 250;
      except
        hasFg := False;
      end;
  end;
  if hasBg and hasFg and (Abs(TyLuminance(bg) - TyLuminance(fg)) < cLowContrastThreshold) then
  begin
    if Length(ARule.Selectors) > 0 then
      sel := SelectorText(ARule.Selectors[0])
    else
      sel := '?';
    Emit(AResult, Format(rsLintLowContrast, [sel]));
  end;
end;

{ Collect a sheet's :root + every @mode block's var NAMES into ADefined. }
procedure CollectSheetVars(ASheet: TTyCssStylesheet; ADefined: TStrings);
var vi, mi: Integer; mb: TTyCssModeBlock;
begin
  for vi := 0 to ASheet.RootVars.Count - 1 do
    AddDefined(ADefined, ASheet.RootVars.Names[vi]);
  for mi := 0 to ASheet.ModeBlocks.Count - 1 do
  begin
    mb := TTyCssModeBlock(ASheet.ModeBlocks[mi]);
    for vi := 0 to mb.Vars.Count - 1 do
      AddDefined(ADefined, mb.Vars.Names[vi]);
  end;
end;

{ ── @import flattening (non-raising) ────────────────────────────────────────── }

{ Recursively load + parse + collect every sheet reachable from ASheet's @import list into
  ASheets (each entry owned by the caller), and accumulate vars into ADefined and the path
  fallback into a base-dir stack. NON-raising: a missing/cyclic/too-deep import is reported
  to AResult and that branch is abandoned (the rest still lints). ADone canonicalises files
  so a diamond import loads once; AActive guards cycles. }
procedure CollectImports(ASheet: TTyCssStylesheet; const ABaseDir: string;
  ASheets: TFPList; ABaseDirs: TStringList; ADefined: TStrings;
  AActive, ADone: TStrings; ADepth: Integer; var AResult: TTyLintResult);
const
  cMaxDepth = 32;
var
  ii: Integer;
  rawPath, resolved, canon, childDir: string;
  sl: TStringList;
  parser: TTyCssParser;
  child: TTyCssStylesheet;
begin
  if ADepth > cMaxDepth then
  begin
    Emit(AResult, Format(rsLintImportTooDeep, [cMaxDepth]));
    Exit;
  end;
  for ii := 0 to High(ASheet.Imports) do
  begin
    rawPath := Trim(ASheet.Imports[ii]);
    if rawPath = '' then
    begin
      Emit(AResult, rsLintEmptyImportPath);
      Continue;
    end;
    resolved := rawPath;
    if (ABaseDir <> '') and not FileExists(resolved) and FileExists(ABaseDir + rawPath) then
      resolved := ABaseDir + rawPath;
    if not FileExists(resolved) then
    begin
      Emit(AResult, Format(rsLintMissingImport, [rawPath]));
      Continue;
    end;
    canon := LowerCase(ExpandFileName(resolved));
    if AActive.IndexOf(canon) >= 0 then
    begin
      Emit(AResult, Format(rsLintImportCycle, [rawPath]));
      Continue;
    end;
    if ADone.IndexOf(canon) >= 0 then
      Continue;  // diamond: already collected

    sl := TStringList.Create;
    try
      try
        sl.LoadFromFile(resolved);
      except
        Emit(AResult, Format(rsLintUnreadableImport, [rawPath]));
        Continue;
      end;
      child := nil;
      try
        parser := TTyCssParser.Create(sl.Text);
        try
          try
            child := parser.Parse;
          except
            on E: Exception do
            begin
              Emit(AResult, Format(rsLintImportParseError, [rawPath, E.Message]));
              child := nil;
            end;
          end;
        finally
          parser.Free;
        end;
        if child <> nil then
        begin
          AActive.Add(canon);
          ADone.Add(canon);
          try
            childDir := ExtractFilePath(ExpandFileName(resolved));
            // recurse FIRST (lower layer), then register this child's own vars + sheet
            CollectImports(child, childDir, ASheets, ABaseDirs, ADefined,
                           AActive, ADone, ADepth + 1, AResult);
            CollectSheetVars(child, ADefined);
            ASheets.Add(child);
            ABaseDirs.Add(childDir);
            child := nil;  // ownership transferred to ASheets
          finally
            AActive.Delete(AActive.IndexOf(canon));
          end;
        end;
      finally
        child.Free;  // only frees if a parse/collect failure left it un-transferred
      end;
    finally
      sl.Free;
    end;
  end;
end;

{ Build a resolve-time var set (name=value) from EVERY collected sheet's :root + @mode vars,
  for the contrast check's TyEvalColor. Later sheets (the main one, appended last) override
  earlier (imported) ones, matching the engine's importer-wins merge. Known dynamic tokens
  are seeded to concrete-ish values so an expression using them still resolves for contrast:
  ty-mode defaults 'light'; transparent/none map to a sentinel the evaluator understands. }
procedure BuildEvalVars(ASheets: TFPList; AEvalVars: TStrings);
var si, vi, mi: Integer; sheet: TTyCssStylesheet; mb: TTyCssModeBlock;
begin
  for si := 0 to ASheets.Count - 1 do
  begin
    sheet := TTyCssStylesheet(ASheets[si]);
    for vi := 0 to sheet.RootVars.Count - 1 do
      AEvalVars.Values[sheet.RootVars.Names[vi]] := sheet.RootVars.ValueFromIndex[vi];
    // overlay every mode's vars (any mode that defines a token makes it resolvable; for the
    // best-effort contrast pass we do not model which mode is active)
    for mi := 0 to sheet.ModeBlocks.Count - 1 do
    begin
      mb := TTyCssModeBlock(sheet.ModeBlocks[mi]);
      for vi := 0 to mb.Vars.Count - 1 do
        AEvalVars.Values[mb.Vars.Names[vi]] := mb.Vars.ValueFromIndex[vi];
    end;
  end;
  // dynamic tokens: give --ty-mode a default so elevate()/on() resolve; map the OS accent
  // sentinel to a mid colour so an accent-seeded theme still evaluates for the contrast pass.
  if AEvalVars.IndexOfName('ty-mode') < 0 then
    AEvalVars.Values['ty-mode'] := 'light';
end;

{ Walk a sheet's decls: report unknown properties + undefined vars + missing assets, and
  (when AScanContrast) low-contrast rules. ADefined drives var-defined-ness; AEvalVars the
  contrast resolve. Properties are scanned via a throwaway TyApplyDeclaration whose False
  return == unknown prop; the call is guarded so an undefined-var inside the value (reported
  separately) never masks the unknown-prop signal. }
procedure ScanSheet(ASheet: TTyCssStylesheet; ADefined, AEvalVars: TStrings;
  const ABaseDir: string; AScanContrast: Boolean; var AResult: TTyLintResult);
var
  ri, di, vi, mi: Integer;
  rule: TTyCssRule;
  mb: TTyCssModeBlock;
  prop, raw: string;
  dummy: TTyStyleSet;
  known: Boolean;
begin
  // (a) :root values — undefined vars + assets only (no property semantics in :root)
  for vi := 0 to ASheet.RootVars.Count - 1 do
  begin
    raw := ASheet.RootVars.ValueFromIndex[vi];
    ScanValueForUndefinedVars(raw, ADefined, AResult);
    ScanValueForMissingAssets(raw, ABaseDir, AResult);
  end;
  // (b) @mode block values — same
  for mi := 0 to ASheet.ModeBlocks.Count - 1 do
  begin
    mb := TTyCssModeBlock(ASheet.ModeBlocks[mi]);
    for vi := 0 to mb.Vars.Count - 1 do
    begin
      raw := mb.Vars.ValueFromIndex[vi];
      ScanValueForUndefinedVars(raw, ADefined, AResult);
      ScanValueForMissingAssets(raw, ABaseDir, AResult);
    end;
  end;
  // (c) rule declarations
  for ri := 0 to ASheet.Rules.Count - 1 do
  begin
    rule := TTyCssRule(ASheet.Rules[ri]);
    for di := 0 to High(rule.Declarations) do
    begin
      prop := Trim(rule.Declarations[di].Prop);
      raw := Trim(rule.Declarations[di].RawValue);
      // unknown property: TyApplyDeclaration returns False for an unrecognised name. Guard
      // the call: a bad VALUE (undefined var) raises inside, but that is reported by the
      // var scan below — here we only care whether the PROP name is known. A raise means the
      // prop WAS recognised (it tried to evaluate), so treat an exception as "known".
      known := True;
      try
        known := TyApplyDeclaration(dummy, prop, raw, AEvalVars);
      except
        known := True;
      end;
      if not known then
        Emit(AResult, Format(rsLintUnknownProperty, [prop]));
    end;
    // undefined vars + missing assets across this rule's values (after the prop pass so all
    // 'unknown property' lines precede 'undefined variable' lines in the output)
    for di := 0 to High(rule.Declarations) do
    begin
      raw := Trim(rule.Declarations[di].RawValue);
      ScanValueForUndefinedVars(raw, ADefined, AResult);
      ScanValueForMissingAssets(raw, ABaseDir, AResult);
    end;
  end;
  // (d) low contrast — best-effort, last
  if AScanContrast then
    for ri := 0 to ASheet.Rules.Count - 1 do
      ScanRuleForLowContrast(TTyCssRule(ASheet.Rules[ri]), AEvalVars, AResult);
end;

{ ── public entry ────────────────────────────────────────────────────────────── }

function TyLintCss(const ASource: string; const ABaseDir: string): TTyLintResult;
var
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  imported: TFPList;        // owns every imported TTyCssStylesheet
  importedDirs: TStringList;
  defined, evalVars, active, doneSet: TStringList;
  baseDir: string;
  i: Integer;
  allSheets: TFPList;
begin
  Result := nil;   // empty dynamic array (no warnings); Emit grows it as needed
  baseDir := ABaseDir;
  if (baseDir <> '') then
    baseDir := IncludeTrailingPathDelimiter(baseDir);

  // 1) parse the entry document; a parse error is itself the (only) warning, non-raising.
  sheet := nil;
  parser := TTyCssParser.Create(ASource);
  try
    try
      sheet := parser.Parse;
    except
      on E: Exception do
      begin
        Emit(Result, Format(rsLintParseError, [E.Message]));
        sheet := nil;
      end;
    end;
  finally
    parser.Free;
  end;
  if sheet = nil then
    Exit;   // unparseable entry document -> only the parse-error warning (already emitted)

  imported := TFPList.Create;
  importedDirs := TStringList.Create;
  defined := TStringList.Create;
  evalVars := TStringList.Create;
  active := TStringList.Create;
  doneSet := TStringList.Create;
  allSheets := TFPList.Create;
  try
    // 2) flatten @import targets into 'imported' (lower layers first) + accumulate var names
    CollectImports(sheet, baseDir, imported, importedDirs, defined,
                   active, doneSet, 0, Result);
    // the entry sheet's own vars are the TOP layer of defined-ness
    CollectSheetVars(sheet, defined);

    // 3) one ordered sheet list: imports (in load order) then the entry sheet last
    for i := 0 to imported.Count - 1 do
      allSheets.Add(imported[i]);
    allSheets.Add(sheet);
    BuildEvalVars(allSheets, evalVars);

    // 4) scan each sheet with its OWN base dir (so per-file relative url() resolves right).
    //    Contrast runs only on the entry sheet to keep the report focused on the theme proper.
    for i := 0 to imported.Count - 1 do
      ScanSheet(TTyCssStylesheet(imported[i]), defined, evalVars,
                importedDirs[i], False, Result);
    ScanSheet(sheet, defined, evalVars, baseDir, True, Result);
  finally
    for i := 0 to imported.Count - 1 do
      TTyCssStylesheet(imported[i]).Free;
    imported.Free;
    importedDirs.Free;
    defined.Free;
    evalVars.Free;
    active.Free;
    doneSet.Free;
    allSheets.Free;
    sheet.Free;
  end;
end;

end.
