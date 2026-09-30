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
  is itself reported rather than raised.

  TyLintCssEx (theme builder): the same checks in the same order, each issue with WHERE it
  is (line / byte column in the entry document), how bad (error / warning) and what kind.
  The parser keeps no positions and its data structures are left alone: once it has
  ACCEPTED the text, the entry document is walked a second time with the same lexer, the
  way the parser walks it, recording where each rule, declaration, variable and @import
  starts (BuildPositions). Those line up one to one with the parsed sheet. A problem inside
  an @import-ed file is placed on the entry document's @import that brought it in. One kind
  exists only in the Ex form: tlkBadValue, a value the engine rejects (border-radius with
  three numbers, say, or a variable that leads back to itself -- ScanVarCycles, on the
  variable's definition) -- TyLintCss leaves it out, so its output is unchanged word for
  word. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tyControls.StrConsts;

type
  TTyLintResult = array of string;

  TTyLintSeverity = (tlsError, tlsWarning);
  TTyLintKind = (tlkParseError, tlkUnknownProperty, tlkUndefinedVar, tlkMissingAsset,
    tlkLowContrast, tlkImportTooDeep, tlkEmptyImportPath, tlkMissingImport,
    tlkImportCycle, tlkUnreadableImport, tlkImportParseError,
    tlkBadValue);   { TyLintCssEx only: a value the engine rejects (not reported by TyLintCss) }

  TTyLintIssue = record
    Line, Col: Integer;          { in ASource, 1-based, byte column; 0 = no position }
    Severity: TTyLintSeverity;
    Kind: TTyLintKind;
    { the property, the variable (no leading --), the asset or import path, the selector;
      '' for a parse error or a too-deep import }
    Subject: string;
    Message: string;             { exactly the text TyLintCss gives for this issue }
  end;
  TTyLintIssues = array of TTyLintIssue;

{ Lint ASource (a .tycss document). ABaseDir, when non-empty, is the theme root used to
  resolve url() assets and relative @import targets (pass the directory that CONTAINS the
  theme file, with or without a trailing path delimiter). Returns the warnings (possibly
  empty): the messages of TyLintCssEx without tlkBadValue. NEVER raises. }
function TyLintCss(const ASource: string; const ABaseDir: string = ''): TTyLintResult;
{ The same checks in the same order, each with where it is, how bad and what kind; an issue
  inside an @import-ed file is placed on the entry document's @import that brought it in.
  NEVER raises. }
function TyLintCssEx(const ASource: string; const ABaseDir: string = ''): TTyLintIssues;

implementation

uses
  tyControls.Types, tyControls.Css.Tokens, tyControls.Css.Lexer, tyControls.Css.Parser,
  tyControls.Css.Values, tyControls.StyleModel;

const
  // Below this perceived-luminance delta a bg/fg pair is flagged as low contrast. Chosen
  // small (0.10) so it only catches near-invisible text, never the legitimate themes (the
  // repo themes pair e.g. #1F2937 ink on #FFFFFF surface -> delta ~0.85).
  cLowContrastThreshold = 0.10;

  cKindSeverity: array[TTyLintKind] of TTyLintSeverity = (
    tlsError,     // tlkParseError
    tlsError,     // tlkUnknownProperty
    tlsError,     // tlkUndefinedVar
    tlsWarning,   // tlkMissingAsset
    tlsWarning,   // tlkLowContrast
    tlsError,     // tlkImportTooDeep
    tlsError,     // tlkEmptyImportPath
    tlsError,     // tlkMissingImport
    tlsError,     // tlkImportCycle
    tlsError,     // tlkUnreadableImport
    tlsError,     // tlkImportParseError
    tlsError);    // tlkBadValue

{ ── positions ───────────────────────────────────────────────────────────────── }

type
  TLintPos = record
    Line, Col: Integer;
  end;

  { Where each piece of the entry document starts, recorded by walking the lexer the way
    the parser walks it -- only ever after the parser accepted the text, so the grammar is
    known to hold. Order matches the parsed sheet: Rules[i] <-> Rules[i], a rule's
    Declarations[j] <-> Decls[i][j], ModeBlocks[m] <-> Modes[m], Imports[k] <-> Imports[k].
    A variable maps to its LAST definition: :root and @mode keep the last value of a name
    in the first name's slot (Css.Parser.pas ParseRootInto). }
  TLintPositions = class
  public
    Rules: array of TLintPos;               { the rule's first selector token }
    Decls: array of array of TLintPos;      { the property name token }
    RootVars: TStringList;                  { lower name (no --) -> Objects = index into VarPos }
    Modes: array of TStringList;            { the same, one list per @mode block }
    VarPos: array of TLintPos;
    Imports: array of TLintPos;             { the '@' of each @import }
    constructor Create;
    destructor Destroy; override;
    function RootVar(const AName: string): TLintPos;           { (0,0) when unknown }
    function ModeVar(AMode: Integer; const AName: string): TLintPos;
    function Rule(ARule: Integer): TLintPos;
    function Decl(ARule, ADecl: Integer): TLintPos;
    function ImportAt(AIndex: Integer): TLintPos;
  end;

function NoPos: TLintPos;
begin
  Result.Line := 0;
  Result.Col := 0;
end;

function PosOf(const ATok: TTyCssToken): TLintPos;
begin
  Result.Line := ATok.Line;
  Result.Col := ATok.Col;
end;

constructor TLintPositions.Create;
begin
  inherited Create;
  RootVars := TStringList.Create;
end;

destructor TLintPositions.Destroy;
var
  i: Integer;
begin
  RootVars.Free;
  for i := 0 to High(Modes) do
    Modes[i].Free;
  inherited Destroy;
end;

function LookupVar(AList: TStringList; const AName: string;
  const AVarPos: array of TLintPos): TLintPos;
var
  i, k: Integer;
begin
  Result := NoPos;
  if AList = nil then Exit;
  i := AList.IndexOf(LowerCase(Trim(AName)));
  if i < 0 then Exit;
  k := PtrInt(AList.Objects[i]);
  if (k >= 0) and (k <= High(AVarPos)) then
    Result := AVarPos[k];
end;

function TLintPositions.RootVar(const AName: string): TLintPos;
begin
  Result := LookupVar(RootVars, AName, VarPos);
end;

function TLintPositions.ModeVar(AMode: Integer; const AName: string): TLintPos;
begin
  if (AMode < 0) or (AMode > High(Modes)) then
    Exit(NoPos);
  Result := LookupVar(Modes[AMode], AName, VarPos);
end;

function TLintPositions.Rule(ARule: Integer): TLintPos;
begin
  if (ARule < 0) or (ARule > High(Rules)) then
    Exit(NoPos);
  Result := Rules[ARule];
end;

function TLintPositions.Decl(ARule, ADecl: Integer): TLintPos;
begin
  if (ARule < 0) or (ARule > High(Decls)) or (ADecl < 0) or (ADecl > High(Decls[ARule])) then
    Exit(NoPos);
  Result := Decls[ARule][ADecl];
end;

function TLintPositions.ImportAt(AIndex: Integer): TLintPos;
begin
  if (AIndex < 0) or (AIndex > High(Imports)) then
    Exit(NoPos);
  Result := Imports[AIndex];
end;

{ Walk the lexer over a document the parser has accepted and record where things start.
  Never raises: on anything unexpected it returns what it has recorded so far (the rest of
  the positions are simply 0). }
function BuildPositions(const ASource: string): TLintPositions;
var
  lex: TTyCssLexer;
  tok: TTyCssToken;
  ri: Integer;
  modeList: TStringList;

  procedure SkipTo(AKind: TTyCssTokenKind);
  begin
    repeat
      tok := lex.Next;
    until (tok.Kind = AKind) or (tok.Kind = ctkEOF);
  end;

  // the opening brace is next; each '--name:' up to the closing brace
  procedure ReadVarBlock(AList: TStringList);
  var
    name: string;
    i: Integer;
  begin
    tok := lex.Next;                    // '{'
    while True do
    begin
      tok := lex.Next;
      if (tok.Kind = ctkRBrace) or (tok.Kind = ctkEOF) then
        Break;
      name := LowerCase(Copy(tok.Text, 3, MaxInt));
      i := AList.IndexOf(name);
      if i >= 0 then
        Result.VarPos[PtrInt(AList.Objects[i])] := PosOf(tok)   // the last definition wins
      else
      begin
        SetLength(Result.VarPos, Length(Result.VarPos) + 1);
        Result.VarPos[High(Result.VarPos)] := PosOf(tok);
        AList.AddObject(name, TObject(PtrInt(High(Result.VarPos))));
      end;
      SkipTo(ctkSemicolon);   // the parser's ReadRawValue stops at ';' whatever the depth
    end;
  end;

  // the opening brace is consumed; each property name up to the closing brace
  procedure ReadDeclBlock(ARule: Integer);
  begin
    while True do
    begin
      tok := lex.Next;
      if (tok.Kind = ctkRBrace) or (tok.Kind = ctkEOF) then
        Break;
      SetLength(Result.Decls[ARule], Length(Result.Decls[ARule]) + 1);
      Result.Decls[ARule][High(Result.Decls[ARule])] := PosOf(tok);
      SkipTo(ctkSemicolon);
    end;
  end;

begin
  Result := TLintPositions.Create;
  lex := TTyCssLexer.Create(ASource);
  try
    try
      tok := lex.Next;
      while tok.Kind <> ctkEOF do
      begin
        case tok.Kind of
          ctkAtKeyword:
            if LowerCase(tok.Text) = 'import' then
            begin
              SetLength(Result.Imports, Length(Result.Imports) + 1);
              Result.Imports[High(Result.Imports)] := PosOf(tok);
              SkipTo(ctkSemicolon);
            end
            else if LowerCase(tok.Text) = 'mode' then
            begin
              modeList := TStringList.Create;
              SetLength(Result.Modes, Length(Result.Modes) + 1);
              Result.Modes[High(Result.Modes)] := modeList;
              tok := lex.Next;               // the mode name
              tok := lex.Next;               // '{'
              while True do
              begin
                tok := lex.Next;
                if (tok.Kind = ctkRBrace) or (tok.Kind = ctkEOF) then
                  Break;
                if tok.Kind = ctkColon then
                begin
                  tok := lex.Next;           // 'root'
                  ReadVarBlock(modeList);
                end;
              end;
            end;
          ctkColon:
            begin
              tok := lex.Next;               // 'root'
              ReadVarBlock(Result.RootVars);
            end;
          ctkIdent:
            begin
              SetLength(Result.Rules, Length(Result.Rules) + 1);
              Result.Rules[High(Result.Rules)] := PosOf(tok);
              SetLength(Result.Decls, Length(Result.Rules));
              ri := High(Result.Rules);
              SkipTo(ctkLBrace);             // the rest of the selector list
              ReadDeclBlock(ri);
            end;
        end;
        if tok.Kind = ctkEOF then
          Break;
        tok := lex.Next;
      end;
    except
      // keep what was recorded; lint never raises
    end;
  finally
    lex.Free;
  end;
end;

{ ── helpers ─────────────────────────────────────────────────────────────────── }

procedure EmitIssue(var AIssues: TTyLintIssues; const APos: TLintPos; AKind: TTyLintKind;
  const ASubject, AMsg: string);
var
  n: Integer;
begin
  n := Length(AIssues);
  SetLength(AIssues, n + 1);
  AIssues[n].Line := APos.Line;
  AIssues[n].Col := APos.Col;
  AIssues[n].Severity := cKindSeverity[AKind];
  AIssues[n].Kind := AKind;
  AIssues[n].Subject := ASubject;
  AIssues[n].Message := AMsg;
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

{ Every '--name' reference in ARaw (both 'var(--name)' and a bare '--name' leaf, the two
  forms the engine resolves), once each, in order, original case -- ALL of them, defined or
  not (AAll) or only the undefined ones (AOut, when non-nil), meaning neither in ADefined nor
  a known dynamic token. The within-one-value de-dupe makes 'a var(--x) b var(--x)' report
  --x once; cross-value de-dupe is intentionally NOT done (the same undefined var in two
  rules is two problems to fix). }
procedure CollectVarRefs(const ARaw: string; ADefined: TStrings; AOut, AAll: TStrings);
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
            if AAll <> nil then
              AAll.Add(name);
            if (AOut <> nil) and (ADefined.IndexOf(key) < 0) and not IsKnownDynamicVar(name) then
              AOut.Add(name);
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

procedure CollectUndefinedVars(const ARaw: string; ADefined, AOut: TStrings);
begin
  CollectVarRefs(ARaw, ADefined, AOut, nil);
end;

{ Would evaluating ARaw hit a variable the linter cannot supply? True when ARaw -- or the
  value of any variable it uses, followed through the sheet's own variables -- refers to a
  variable the sheet does not define (reported as undefined elsewhere, or defined only by
  the base theme the document will sit on) or to a dynamic token the lint has no value for.
  Such a value failing to evaluate says nothing about the value itself, so it is not a bad
  value. }
function DependsOnUnknownVar(const ARaw: string; ADefined, AEvalVars: TStrings): Boolean;
var
  visited: TStringList;

  function Walk(const ARawValue: string; ADepth: Integer): Boolean;
  var
    refs: TStringList;
    i: Integer;
    key: string;
  begin
    Result := False;
    if ADepth > 32 then
      Exit(True);
    refs := TStringList.Create;
    try
      CollectVarRefs(ARawValue, ADefined, nil, refs);
      for i := 0 to refs.Count - 1 do
      begin
        key := LowerCase(refs[i]);
        if AEvalVars.IndexOfName(key) < 0 then
        begin
          { not a sheet variable: undefined, or a dynamic token the lint has no value for }
          if (ADefined.IndexOf(key) < 0) or IsKnownDynamicVar(key) then
            Exit(True);
          Continue;
        end;
        if visited.IndexOf(key) >= 0 then
          Continue;
        visited.Add(key);
        { a variable the OS fills in (its value is the bare sentinel, swapped at merge) }
        if IsKnownDynamicVar(Trim(AEvalVars.Values[key])) then
          Exit(True);
        if Walk(AEvalVars.Values[key], ADepth + 1) then
          Exit(True);
      end;
    finally
      refs.Free;
    end;
  end;

begin
  visited := TStringList.Create;
  try
    Result := Walk(ARaw, 0);
  finally
    visited.Free;
  end;
end;

{ Append each undefined reference in ARaw as 'undefined variable --name' at APos. }
procedure ScanValueForUndefinedVars(const ARaw: string; ADefined: TStrings;
  const APos: TLintPos; var AIssues: TTyLintIssues);
var
  names: TStringList;
  i: Integer;
begin
  names := TStringList.Create;
  try
    CollectUndefinedVars(ARaw, ADefined, names);
    for i := 0 to names.Count - 1 do
      EmitIssue(AIssues, APos, tlkUndefinedVar, names[i],
        Format(rsLintUndefinedVar, [names[i]]));
  finally
    names.Free;
  end;
end;

{ Find each 'url(<path>)' in ARaw and, when ABaseDir<>'', report any whose resolved file is
  missing. Quotes are stripped; the path is resolved as-is first, then relative to ABaseDir
  (mirroring ResolveAssetPath's fallback). Empty ABaseDir => assets not checkable => skip. }
procedure ScanValueForMissingAssets(const ARaw: string; const ABaseDir: string;
  const APos: TLintPos; var AIssues: TTyLintIssues);
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
        EmitIssue(AIssues, APos, tlkMissingAsset, path, Format(rsLintMissingAsset, [path]));
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
  const APos: TLintPos; var AIssues: TTyLintIssues);
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
    EmitIssue(AIssues, APos, tlkLowContrast, sel, Format(rsLintLowContrast, [sel]));
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

type
  TLintPosArray = array of TLintPos;

{ Recursively load + parse + collect every sheet reachable from ASheet's @import list into
  ASheets (each entry owned by the caller), and accumulate vars into ADefined and the path
  fallback into a base-dir stack. NON-raising: a missing/cyclic/too-deep import is reported
  to AIssues and that branch is abandoned (the rest still lints). ADone canonicalises files
  so a diamond import loads once; AActive guards cycles.
  Positions: at depth 0 each @import is placed where it stands in the entry document
  (APos.ImportAt(ii)); everything under it -- its own problems and those of the files it pulls
  in -- lands on that same top-level @import (ATop, passed down unchanged). ATops receives
  that position for each sheet added to ASheets, in the same order. }
procedure CollectImports(ASheet: TTyCssStylesheet; const ABaseDir: string;
  ASheets: TFPList; ABaseDirs: TStringList; ADefined: TStrings;
  AActive, ADone: TStrings; ADepth: Integer; APos: TLintPositions; const ATop: TLintPos;
  var ATops: TLintPosArray; var AIssues: TTyLintIssues);
const
  cMaxDepth = 32;
var
  ii: Integer;
  rawPath, resolved, canon, childDir: string;
  sl: TStringList;
  parser: TTyCssParser;
  child: TTyCssStylesheet;
  here: TLintPos;
begin
  if ADepth > cMaxDepth then
  begin
    EmitIssue(AIssues, ATop, tlkImportTooDeep, '', Format(rsLintImportTooDeep, [cMaxDepth]));
    Exit;
  end;
  for ii := 0 to High(ASheet.Imports) do
  begin
    if (ADepth = 0) and (APos <> nil) then
      here := APos.ImportAt(ii)
    else
      here := ATop;
    rawPath := Trim(ASheet.Imports[ii]);
    if rawPath = '' then
    begin
      EmitIssue(AIssues, here, tlkEmptyImportPath, '', rsLintEmptyImportPath);
      Continue;
    end;
    resolved := rawPath;
    if (ABaseDir <> '') and not FileExists(resolved) and FileExists(ABaseDir + rawPath) then
      resolved := ABaseDir + rawPath;
    if not FileExists(resolved) then
    begin
      EmitIssue(AIssues, here, tlkMissingImport, rawPath, Format(rsLintMissingImport, [rawPath]));
      Continue;
    end;
    canon := LowerCase(ExpandFileName(resolved));
    if AActive.IndexOf(canon) >= 0 then
    begin
      EmitIssue(AIssues, here, tlkImportCycle, rawPath, Format(rsLintImportCycle, [rawPath]));
      Continue;
    end;
    if ADone.IndexOf(canon) >= 0 then
      Continue;  // diamond: already collected

    sl := TStringList.Create;
    try
      try
        sl.LoadFromFile(resolved);
      except
        EmitIssue(AIssues, here, tlkUnreadableImport, rawPath,
          Format(rsLintUnreadableImport, [rawPath]));
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
              EmitIssue(AIssues, here, tlkImportParseError, rawPath,
                Format(rsLintImportParseError, [rawPath, E.Message]));
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
                           AActive, ADone, ADepth + 1, APos, here, ATops, AIssues);
            CollectSheetVars(child, ADefined);
            ASheets.Add(child);
            ABaseDirs.Add(childDir);
            SetLength(ATops, Length(ATops) + 1);
            ATops[High(ATops)] := here;
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

{ Each variable of the entry document that, in some mode, leads back to itself through
  variables (--a: var(--a); --a: var(--b) with --b: var(--a)) -- the engine refuses such a
  theme wherever the variable is evaluated (TyCssVarCycleMsg), and before that guard it
  recursed until the stack ran out. Every mode is checked on its own var set, merged the
  way the engine merges it (every sheet's :root, the importer's last, then that mode's
  blocks over them); a document without @mode is checked on its :root alone. A variable is
  reported only when it is ON a cycle (a strongly connected component of more than one, or
  one that refers to itself), not when it merely uses one, and only where the entry
  document defines it -- as tlkBadValue on that definition, once. A cycle through the base
  theme's variables is not seen here (the lint does not know the base); the load reports it. }
procedure ScanVarCycles(ASheets: TFPList; AEntry: TTyCssStylesheet; APos: TLintPositions;
  var AIssues: TTyLintIssues);
var
  modes, names, reported, refs: TStringList;
  vals: array of string;
  srcEntry: array of Boolean;
  srcBlock: array of Integer;           { -1 = the entry's :root, else its @mode block }
  adj: array of array of Integer;
  num, low: array of Integer;
  onStack, cyclic: array of Boolean;
  stack: array of Integer;
  sp, counter: Integer;

  procedure Put(const AName, AValue: string; AIsEntry: Boolean; ABlock: Integer);
  var
    n: string;
    i, k: Integer;
  begin
    n := LowerCase(Trim(AName));
    if n = '' then Exit;
    i := names.IndexOf(n);
    if i < 0 then
    begin
      k := Length(vals);
      SetLength(vals, k + 1);
      SetLength(srcEntry, k + 1);
      SetLength(srcBlock, k + 1);
      names.AddObject(n, TObject(PtrInt(k)));
    end
    else
      k := PtrInt(names.Objects[i]);
    vals[k] := AValue;
    srcEntry[k] := AIsEntry;
    srcBlock[k] := ABlock;
  end;

  procedure Strong(V: Integer);
  var
    i, w: Integer;
    size: Integer;
    selfRef: Boolean;
  begin
    num[V] := counter;
    low[V] := counter;
    Inc(counter);
    stack[sp] := V;
    Inc(sp);
    onStack[V] := True;
    selfRef := False;
    for i := 0 to High(adj[V]) do
    begin
      w := adj[V][i];
      if w = V then
        selfRef := True;
      if num[w] < 0 then
      begin
        Strong(w);
        if low[w] < low[V] then low[V] := low[w];
      end
      else if onStack[w] and (num[w] < low[V]) then
        low[V] := num[w];
    end;
    if low[V] = num[V] then
    begin
      { pop the component; mark it when it is a real cycle }
      size := 0;
      i := sp - 1;
      while stack[i] <> V do
      begin
        Inc(size);
        Dec(i);
      end;
      Inc(size);
      while True do
      begin
        Dec(sp);
        w := stack[sp];
        onStack[w] := False;
        cyclic[w] := (size > 1) or selfRef;
        if w = V then Break;
      end;
    end;
  end;

var
  si, mi, vi, i, j, k, n: Integer;
  sheet: TTyCssStylesheet;
  mb: TTyCssModeBlock;
  isEntry: Boolean;
  mode, key: string;
  P: TLintPos;
begin
  modes := TStringList.Create;
  names := TStringList.Create;
  reported := TStringList.Create;
  refs := TStringList.Create;
  try
    modes.Sorted := True;
    modes.Duplicates := dupIgnore;
    for si := 0 to ASheets.Count - 1 do
    begin
      sheet := TTyCssStylesheet(ASheets[si]);
      for mi := 0 to sheet.ModeBlocks.Count - 1 do
        modes.Add(LowerCase(Trim(TTyCssModeBlock(sheet.ModeBlocks[mi]).Mode)));
    end;
    if modes.Count = 0 then
      modes.Add('');                    { no @mode anywhere: the :root alone }
    names.Sorted := True;
    for i := 0 to modes.Count - 1 do
    begin
      mode := modes[i];
      names.Clear;
      vals := nil;
      srcEntry := nil;
      srcBlock := nil;
      for si := 0 to ASheets.Count - 1 do
      begin
        sheet := TTyCssStylesheet(ASheets[si]);
        isEntry := sheet = AEntry;
        for vi := 0 to sheet.RootVars.Count - 1 do
          Put(sheet.RootVars.Names[vi], sheet.RootVars.ValueFromIndex[vi], isEntry, -1);
      end;
      if mode <> '' then
        for si := 0 to ASheets.Count - 1 do
        begin
          sheet := TTyCssStylesheet(ASheets[si]);
          isEntry := sheet = AEntry;
          for mi := 0 to sheet.ModeBlocks.Count - 1 do
          begin
            mb := TTyCssModeBlock(sheet.ModeBlocks[mi]);
            if not SameText(Trim(mb.Mode), mode) then Continue;
            for vi := 0 to mb.Vars.Count - 1 do
              Put(mb.Vars.Names[vi], mb.Vars.ValueFromIndex[vi], isEntry, mi);
          end;
        end;
      n := Length(vals);
      SetLength(adj, n);
      for k := 0 to n - 1 do
      begin
        adj[k] := nil;
        refs.Clear;
        CollectVarRefs(vals[k], nil, nil, refs);
        for j := 0 to refs.Count - 1 do
        begin
          si := names.IndexOf(LowerCase(refs[j]));
          if si >= 0 then
          begin
            SetLength(adj[k], Length(adj[k]) + 1);
            adj[k][High(adj[k])] := PtrInt(names.Objects[si]);
          end;
        end;
      end;
      SetLength(num, n);
      SetLength(low, n);
      SetLength(onStack, n);
      SetLength(cyclic, n);
      SetLength(stack, n);
      for k := 0 to n - 1 do
      begin
        num[k] := -1;
        onStack[k] := False;
        cyclic[k] := False;
      end;
      sp := 0;
      counter := 0;
      for k := 0 to n - 1 do
        if num[k] < 0 then
          Strong(k);
      for j := 0 to names.Count - 1 do
      begin
        k := PtrInt(names.Objects[j]);
        if not (cyclic[k] and srcEntry[k]) then Continue;
        if APos = nil then
          P := NoPos
        else if srcBlock[k] < 0 then
          P := APos.RootVar(names[j])
        else
          P := APos.ModeVar(srcBlock[k], names[j]);
        key := Format('%d:%d:%s', [P.Line, P.Col, names[j]]);
        if reported.IndexOf(key) >= 0 then Continue;
        reported.Add(key);
        EmitIssue(AIssues, P, tlkBadValue, names[j],
          '--' + names[j] + ': ' + Format(TyCssVarCycleMsg, [names[j]]));
      end;
    end;
  finally
    modes.Free;
    names.Free;
    reported.Free;
    refs.Free;
  end;
end;

{ Walk a sheet's decls: report unknown properties + undefined vars + missing assets, and
  (when AScanContrast) low-contrast rules. ADefined drives var-defined-ness; AEvalVars the
  contrast resolve. Properties are scanned via a throwaway TyApplyDeclaration whose False
  return == unknown prop; the call is guarded so an undefined-var inside the value (reported
  separately) never masks the unknown-prop signal. A raise from a known property whose
  value uses no variable the lint cannot supply is a bad value (tlkBadValue, Ex only).
  Positions come from APos (the entry document); an imported sheet passes APos = nil and
  every issue lands on AFallback (the @import that brought it in). }
procedure ScanSheet(ASheet: TTyCssStylesheet; ADefined, AEvalVars: TStrings;
  const ABaseDir: string; AScanContrast: Boolean; APos: TLintPositions;
  const AFallback: TLintPos; var AIssues: TTyLintIssues);
var
  ri, di, vi, mi: Integer;
  rule: TTyCssRule;
  mb: TTyCssModeBlock;
  prop, raw, bad: string;
  dummy: TTyStyleSet;
  known: Boolean;
  P: TLintPos;
begin
  // (a) :root values — undefined vars + assets only (no property semantics in :root)
  for vi := 0 to ASheet.RootVars.Count - 1 do
  begin
    raw := ASheet.RootVars.ValueFromIndex[vi];
    if APos <> nil then P := APos.RootVar(ASheet.RootVars.Names[vi]) else P := AFallback;
    ScanValueForUndefinedVars(raw, ADefined, P, AIssues);
    ScanValueForMissingAssets(raw, ABaseDir, P, AIssues);
  end;
  // (b) @mode block values — same
  for mi := 0 to ASheet.ModeBlocks.Count - 1 do
  begin
    mb := TTyCssModeBlock(ASheet.ModeBlocks[mi]);
    for vi := 0 to mb.Vars.Count - 1 do
    begin
      raw := mb.Vars.ValueFromIndex[vi];
      if APos <> nil then P := APos.ModeVar(mi, mb.Vars.Names[vi]) else P := AFallback;
      ScanValueForUndefinedVars(raw, ADefined, P, AIssues);
      ScanValueForMissingAssets(raw, ABaseDir, P, AIssues);
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
      if APos <> nil then P := APos.Decl(ri, di) else P := AFallback;
      // unknown property: TyApplyDeclaration returns False for an unrecognised name. Guard
      // the call: a bad VALUE (undefined var) raises inside, but that is reported by the
      // var scan below — here we only care whether the PROP name is known. A raise means the
      // prop WAS recognised (it tried to evaluate), so treat an exception as "known".
      known := True;
      bad := '';
      try
        known := TyApplyDeclaration(dummy, prop, raw, AEvalVars);
      except
        on E: Exception do
        begin
          known := True;
          bad := E.Message;
        end;
      end;
      if not known then
        EmitIssue(AIssues, P, tlkUnknownProperty, prop, Format(rsLintUnknownProperty, [prop]))
      else if (bad <> '') and not DependsOnUnknownVar(raw, ADefined, AEvalVars) then
        EmitIssue(AIssues, P, tlkBadValue, prop, prop + ': ' + bad);
    end;
    // undefined vars + missing assets across this rule's values (after the prop pass so all
    // 'unknown property' lines precede 'undefined variable' lines in the output)
    for di := 0 to High(rule.Declarations) do
    begin
      raw := Trim(rule.Declarations[di].RawValue);
      if APos <> nil then P := APos.Decl(ri, di) else P := AFallback;
      ScanValueForUndefinedVars(raw, ADefined, P, AIssues);
      ScanValueForMissingAssets(raw, ABaseDir, P, AIssues);
    end;
  end;
  // (d) low contrast — best-effort, last
  if AScanContrast then
    for ri := 0 to ASheet.Rules.Count - 1 do
    begin
      if APos <> nil then P := APos.Rule(ri) else P := AFallback;
      ScanRuleForLowContrast(TTyCssRule(ASheet.Rules[ri]), AEvalVars, P, AIssues);
    end;
end;

{ ── public entry ────────────────────────────────────────────────────────────── }

function TyLintCssEx(const ASource: string; const ABaseDir: string): TTyLintIssues;
var
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  imported: TFPList;        // owns every imported TTyCssStylesheet
  importedDirs: TStringList;
  importedTops: TLintPosArray;
  defined, evalVars, active, doneSet: TStringList;
  baseDir: string;
  i: Integer;
  allSheets: TFPList;
  positions: TLintPositions;
  errPos: TLintPos;
begin
  Result := nil;   // empty dynamic array (no issues); EmitIssue grows it as needed
  baseDir := ABaseDir;
  if (baseDir <> '') then
    baseDir := IncludeTrailingPathDelimiter(baseDir);

  // 1) parse the entry document; a parse error is itself the (only) issue, non-raising.
  sheet := nil;
  parser := TTyCssParser.Create(ASource);
  try
    try
      sheet := parser.Parse;
    except
      on E: Exception do
      begin
        errPos := NoPos;
        if E is ETyCssError then
        begin
          errPos.Line := ETyCssError(E).Line;
          errPos.Col := ETyCssError(E).Col;
        end;
        EmitIssue(Result, errPos, tlkParseError, '', Format(rsLintParseError, [E.Message]));
        sheet := nil;
      end;
    end;
  finally
    parser.Free;
  end;
  if sheet = nil then
    Exit;   // unparseable entry document -> only the parse-error issue (already emitted)

  positions := BuildPositions(ASource);
  imported := TFPList.Create;
  importedDirs := TStringList.Create;
  importedTops := nil;
  defined := TStringList.Create;
  evalVars := TStringList.Create;
  active := TStringList.Create;
  doneSet := TStringList.Create;
  allSheets := TFPList.Create;
  try
    // 2) flatten @import targets into 'imported' (lower layers first) + accumulate var names
    CollectImports(sheet, baseDir, imported, importedDirs, defined,
                   active, doneSet, 0, positions, NoPos, importedTops, Result);
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
                importedDirs[i], False, nil, importedTops[i], Result);
    ScanSheet(sheet, defined, evalVars, baseDir, True, positions, NoPos, Result);
    // 5) variables that lead back to themselves (Ex only: tlkBadValue)
    ScanVarCycles(allSheets, sheet, positions, Result);
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
    positions.Free;
    sheet.Free;
  end;
end;

function TyLintCss(const ASource: string; const ABaseDir: string): TTyLintResult;
var
  ex: TTyLintIssues;
  i: Integer;
begin
  Result := nil;
  ex := TyLintCssEx(ASource, ABaseDir);
  for i := 0 to High(ex) do
    if ex[i].Kind <> tlkBadValue then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := ex[i].Message;
    end;
end;

end.
