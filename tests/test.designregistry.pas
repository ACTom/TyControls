unit test.designregistry;
{$mode objfpc}{$H+}

{ THE ONE PARSER for designtime/tyControls.Design.pas.

  WHY A UNIT AND NOT A CONST ARRAY. Every check that asks "what does TyControls publish to the
  IDE?" needs the same answer, and the honest source of that answer is the registration source
  itself: designtime/tyControls.Design.pas is the single file a control MUST be edited into to
  reach the palette at all, so a population derived from it tracks reality by construction. The
  tests/ project cannot LINK that unit (it pulls in IDEIntf), but it can read the file —
  test.grid.streaming.pas set the precedent of a test whose input is a repo file.

  WHY IT IS SHARED. test.version.pas grew this parser first; test.paletteicons.pas needed the
  same population and — before this unit existed — kept a hand-copied array of ~158 class names
  instead. That copy went stale silently: TTyDrawGrid and TTyStringGrid reached the palette with
  no icon, and the array that was supposed to guard the icon set simply did not mention them, so
  nothing failed. A second copy of a parser is a second thing to drift; hence one unit, two
  callers, no arrays.

  REGISTERS NO TESTS. It is a helper unit — the guards live in the units that use it. }

interface

uses
  Classes, SysUtils, StrUtils, FileUtil;

{ Repo root — the test exe lives in tests/ (mirrors test.grid.streaming.pas). }
function RepoRoot: string;
{ EVERY design-time registration source, sorted, at least one.

  This was a single hardcoded file name, and that was a trap waiting for the first second
  design-time unit: three separate guards draw their whole population from here
  (test.paletteicons' palette-icon coverage, test.version's property-editor bases,
  test.designeditors' RegisterPropertyEditor validity), and a file that is never READ raises
  nothing anywhere -- the anti-shrink self-check in ParseCallLists compares parsed argument
  lists against occurrences within the same string, so it cannot notice a string that was never
  loaded. tycontrols_dt.lpk's search path is the whole directory, so a new unit also compiles
  fine before it is listed anywhere: the developer sees nothing, and only the guards go quiet. }
procedure CollectDesignSourceFiles(ADest: TStrings);
{ That source as CODE: comments blanked out (and, unless AKeepLiterals, string literals too), so
  a caller searching for an identifier cannot be answered by prose ABOUT it. The collectors below
  all read it through here; it is exported for the guards that ask a whole-file question rather
  than a per-call one. }
function DesignSourceCode(AKeepLiterals: Boolean = False): string;

{ The three ways into the IDE, each a distinct population with distinct obligations:

    RegisterComponents('group', [A, B, …])  palette buttons — these MUST have a palette icon
    RegisterNoIcon([A, …])                  registered, no palette button (grid cells, the form
                                            surface) — streamed and selectable, but never
                                            dragged, so they must NOT have one
    RegisterDesignerBaseClass(A)            form base classes (TTyForm / TTyDialog)

  Kept separate rather than merged because the icon guard has to tell them apart; the merged
  view is CollectRegisteredClassNames, for callers that only care about "reachable from the
  IDE at all". }
procedure CollectPaletteClassNames(ADest: TStrings);
procedure CollectNoIconClassNames(ADest: TStrings);
procedure CollectDesignerBaseClassNames(ADest: TStrings);
procedure CollectRegisteredClassNames(ADest: TStrings);

{ The classes a property editor is registered on for APropertyName, e.g. 'Version' -> the base
  classes whose Object Inspector entry opens the About dialog. }
procedure CollectPropertyEditorBases(const APropertyName: string; ADest: TStrings);

{ EVERY RegisterPropertyEditor call, one line each, as four '|'-separated fields:

    <type expression>|<persistent class>|<property name>|<editor class>

  verbatim from the source but with the property name's quotes stripped. A line is emitted only
  when all four arguments are present, so an EMPTY property name (the blanket registrations that
  match any property of a type) is unambiguous rather than indistinguishable from a short call.

  Why the whole record and not just one field: the three arguments have to AGREE for an editor
  to appear at all. RegisterPropertyEditor matches a registration to a property by comparing the
  registered PTypeInfo with the property's own (kind AND type name — so a TypeInfo(string) editor
  aimed at a TCaption property is simply never chosen) and the name case-insensitively against a
  property the class really publishes. Get any of the three wrong and nothing happens: no error,
  no warning, just a plain edit box where a dropdown was intended. Only a caller holding all four
  fields can check that against RTTI, which is what tests/test.designeditors.pas does. }
procedure CollectPropertyEditorRegistrations(ADest: TStrings);

{ Every `TName = class(TAncestor)` declaration in the file, as <name>|<ancestor>. Lets a caller
  follow a declared editor back to the LCL base it specialises — which is what says whether a
  property is picked from a file dialog or typed into a box. }
procedure CollectClassDeclarations(ADest: TStrings);

{ Take one line of either collection apart again. False (and empty outputs) when the line does
  not carry the expected field count — callers assert on that rather than reading a half-record. }
function SplitEditorRegistration(const ALine: string;
  out AType, ABase, AProp, AEditor: string): Boolean;
function SplitClassDeclaration(const ALine: string; out AName, AAncestor: string): Boolean;

implementation

function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

procedure CollectDesignSourceFiles(ADest: TStrings);
var
  found: TStringList;
begin
  ADest.Clear;
  found := FindAllFiles(RepoRoot + 'designtime', '*.pas', False);
  try
    found.Sort;   { stable population -> stable failure messages }
    ADest.AddStrings(found);
  finally
    found.Free;
  end;
  if ADest.Count = 0 then
    raise Exception.Create('no design-time registration source found under designtime/');
end;

{ Blank out Pascal comments, and collapse string literals to ''. Both matter: the
  design-time unit discusses "RegisterNoIcon, not RegisterComponents" in prose, and the
  palette group names are string literals that would otherwise be scanned for identifiers. }
{ AKeepLiterals: the class-name scans want literals blanked (a palette group name like
  'TyControls Ribbon' must not look like an argument), but the property-editor scan has to read
  the property-name literal to tell a 'Version' registration from a 'StyleClass' one. }
function StripCommentsAndLiterals(const S: string; AKeepLiterals: Boolean = False): string;
var
  i, n, st: Integer;
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create;
  try
    i := 1; n := Length(S);
    while i <= n do
    begin
      if S[i] = '{' then
      begin
        while (i <= n) and (S[i] <> '}') do Inc(i);
        Inc(i);
        sb.Append(' ');
      end
      else if (S[i] = '(') and (i < n) and (S[i + 1] = '*') then
      begin
        Inc(i, 2);
        while (i < n) and not ((S[i] = '*') and (S[i + 1] = ')')) do Inc(i);
        Inc(i, 2);
        sb.Append(' ');
      end
      else if (S[i] = '/') and (i < n) and (S[i + 1] = '/') then
      begin
        while (i <= n) and (S[i] <> #10) do Inc(i);
        sb.Append(' ');
      end
      else if S[i] = '''' then
      begin
        st := i;
        Inc(i);
        while (i <= n) and (S[i] <> '''') do Inc(i);
        Inc(i);
        if AKeepLiterals then sb.Append(Copy(S, st, i - st)) else sb.Append(' ');
      end
      else
      begin
        sb.Append(S[i]);
        Inc(i);
      end;
    end;
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

{ Read the registration sources, comments (and optionally literals) already removed.

  Concatenated, because every collector above asks a question of the form "does the registry
  contain X" -- which is a question about the registry as a whole, not about any one file.
  Stripped per file and then joined, so a construct cannot straddle a file boundary and a
  comment cannot swallow the start of the next unit. }
function LoadDesignSource(AKeepLiterals: Boolean = False): string;
var
  files, sl: TStringList;
  i: Integer;
begin
  Result := '';
  files := TStringList.Create;
  sl := TStringList.Create;
  try
    CollectDesignSourceFiles(files);
    for i := 0 to files.Count - 1 do
    begin
      sl.LoadFromFile(files[i]);
      Result := Result + StripCommentsAndLiterals(sl.Text, AKeepLiterals) + LineEnding;
    end;
  finally
    sl.Free;
    files.Free;
  end;
end;

function DesignSourceCode(AKeepLiterals: Boolean = False): string;
begin
  Result := LoadDesignSource(AKeepLiterals);
end;

{ Every identifier starting with 'T' inside ASrc[AFrom..ATo], appended to ADest once. }
procedure AddIdentifiers(const ASrc: string; AFrom, ATo: Integer; ADest: TStrings);
var
  i, st: Integer;
  id: string;
begin
  i := AFrom;
  while i <= ATo do
  begin
    if ASrc[i] in ['A'..'Z', 'a'..'z', '_'] then
    begin
      st := i;
      while (i <= ATo) and (ASrc[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(i);
      id := Copy(ASrc, st, i - st);
      if (id[1] = 'T') and (ADest.IndexOf(id) < 0) then ADest.Add(id);
    end
    else
      Inc(i);
  end;
end;

{ Is the ALen-long run at AUpSrc[AAt] a whole identifier, rather than part of a longer one?
  Shared so both parsers below apply the same rule — REGISTERCOMPONENTS must not match
  inside REGISTERCOMPONENTEDITOR, and neither may require the '(' to be glued on. }
function IsWholeIdentifierAt(const AUpSrc: string; AAt, ALen: Integer): Boolean;
begin
  Result := ((AAt = 1) or not (AUpSrc[AAt - 1] in ['A'..'Z', '0'..'9', '_']))
        and ((AAt + ALen > Length(AUpSrc))
             or not (AUpSrc[AAt + ALen] in ['A'..'Z', '0'..'9', '_']));
end;

{ How many times AIdent occurs in AUpSrc as a WHOLE identifier. This is the denominator the
  parsers check themselves against. }
function CountBareIdentifier(const AUpSrc, AIdent: string): Integer;
var
  p: Integer;
begin
  Result := 0;
  p := PosEx(AIdent, AUpSrc, 1);
  while p > 0 do
  begin
    if IsWholeIdentifierAt(AUpSrc, p, Length(AIdent)) then Inc(Result);
    p := PosEx(AIdent, AUpSrc, p + 1);
  end;
end;

{ Harvest every identifier from each AIdent(...) call's argument list, delimited by
  AOpen/AClose.

  SELF-CHECKING BY CONSTRUCTION. The obvious spelling — search for 'REGISTERCOMPONENTS('
  with the paren glued on — silently loses an entire palette group the day someone writes
  `RegisterComponents ('TyControls Ribbon', [...])`, because Pascal allows the space and the
  scan simply does not match. Nothing downstream notices: the sweep just checks fewer
  classes and stays green. So this counts the bare identifier FIRST and raises unless it
  matched exactly that many argument lists. A parse that quietly shrinks the population is
  worse than no parse at all — it reads as coverage. }
function ParseCallLists(const ASrc, AUpSrc, AIdent: string;
  AOpen, AClose: Char): TStringList;
var
  want, got, p, ob, cb, semi: Integer;
begin
  Result := TStringList.Create;
  want := CountBareIdentifier(AUpSrc, AIdent);
  got := 0;
  p := 1;
  repeat
    p := PosEx(AIdent, AUpSrc, p);
    if p = 0 then Break;
    if IsWholeIdentifierAt(AUpSrc, p, Length(AIdent)) then
    begin
      ob := PosEx(AOpen, ASrc, p + Length(AIdent));
      cb := PosEx(AClose, ASrc, ob + 1);
      { Bound the search to this statement. Without it, a call whose argument list went
        missing would happily adopt the NEXT statement's list and report success. }
      semi := PosEx(';', ASrc, p + Length(AIdent));
      if (ob > 0) and (cb > 0) and ((semi = 0) or (ob < semi)) then
      begin
        AddIdentifiers(ASrc, ob + 1, cb - 1, Result);
        Inc(got);
        p := cb;
        Continue;
      end;
    end;
    p := p + Length(AIdent);
  until False;
  if got <> want then
    raise Exception.CreateFmt('%s: parsed %d argument list(s) but the source names it %d '
      + 'time(s) — the registration parser has drifted and would silently under-report the '
      + 'registered classes', [AIdent, got, want]);
end;

{ Append ASrc's entries to ADest (skipping ones already there) and free ASrc — the callers
  chain several ParseCallLists results into one population. }
procedure MergeUnique(ASrc: TStringList; ADest: TStrings);
var i: Integer;
begin
  try
    for i := 0 to ASrc.Count - 1 do
      if ADest.IndexOf(ASrc[i]) < 0 then ADest.Add(ASrc[i]);
  finally
    ASrc.Free;
  end;
end;

{ Whole-identifier matching keeps 'RegisterComponents' from colliding with
  'RegisterComponentEditor'. }
procedure CollectPaletteClassNames(ADest: TStrings);
var src: string;
begin
  src := LoadDesignSource;
  MergeUnique(ParseCallLists(src, UpperCase(src), 'REGISTERCOMPONENTS', '[', ']'), ADest);
end;

procedure CollectNoIconClassNames(ADest: TStrings);
var src: string;
begin
  src := LoadDesignSource;
  MergeUnique(ParseCallLists(src, UpperCase(src), 'REGISTERNOICON', '[', ']'), ADest);
end;

procedure CollectDesignerBaseClassNames(ADest: TStrings);
var src: string;
begin
  { single-argument call, so the delimiters are the parentheses themselves }
  src := LoadDesignSource;
  MergeUnique(ParseCallLists(src, UpperCase(src), 'REGISTERDESIGNERBASECLASS', '(', ')'), ADest);
end;

procedure CollectRegisteredClassNames(ADest: TStrings);
begin
  CollectPaletteClassNames(ADest);
  CollectNoIconClassNames(ADest);
  CollectDesignerBaseClassNames(ADest);
end;

{ Every RegisterPropertyEditor call, read out of the registration source rather than copied into
  a const somewhere.

  Why parse instead of listing: the Version set moved twice during the change that introduced
  it (a base class was added, another folded away). A hand-kept copy would have gone stale
  inside one session. Splitting on top-level commas — depth-counted, because the first argument
  is itself a call, TypeInfo(string) — makes the registrations themselves the source of truth. }
procedure CollectPropertyEditorRegistrations(ADest: TStrings);
var
  src, up, prop: string;
  args: TStringList;
  p, i, depth, st, want2, got2: Integer;
begin
  src := LoadDesignSource(True);
  up := UpperCase(src);

  { Whole-identifier match with the paren NOT glued on — the same discipline ParseCallLists
    documents a few dozen lines up. Spelling it 'REGISTERPROPERTYEDITOR(' would make a single
    space before the paren yield an EMPTY list, and an empty list makes the caller's
    reachability check pass on everything: a silent shrink that reads as coverage. }
  want2 := CountBareIdentifier(up, 'REGISTERPROPERTYEDITOR');
  got2 := 0;
  p := 1;
  repeat
    p := PosEx('REGISTERPROPERTYEDITOR', up, p);
    if p = 0 then Break;
    if not IsWholeIdentifierAt(up, p, Length('REGISTERPROPERTYEDITOR')) then
    begin
      p := p + Length('REGISTERPROPERTYEDITOR');
      Continue;
    end;
    Inc(got2);
    i := PosEx('(', src, p + Length('REGISTERPROPERTYEDITOR') - 1);
    { walk to the matching ')', splitting the top-level arguments as we go }
    args := TStringList.Create;
    try
      depth := 0; st := i + 1;
      while i <= Length(src) do
      begin
        if src[i] = '(' then Inc(depth)
        else if src[i] = ')' then
        begin
          Dec(depth);
          if depth = 0 then
          begin
            args.Add(Trim(Copy(src, st, i - st)));
            Break;
          end;
        end
        else if (src[i] = ',') and (depth = 1) then
        begin
          args.Add(Trim(Copy(src, st, i - st)));
          st := i + 1;
        end;
        Inc(i);
      end;
      { Four arguments or nothing: a short list means the walk lost the closing paren, and
        emitting a partial record would hand the caller a registration that reads as valid. }
      if args.Count >= 4 then
      begin
        prop := args[2];
        if (Length(prop) >= 2) and (prop[1] = '''') then
          prop := AnsiDequotedStr(prop, '''');
        ADest.Add(args[0] + '|' + args[1] + '|' + prop + '|' + args[3]);
      end;
    finally
      args.Free;
    end;
    p := i;
  until False;
  if got2 <> want2 then
    raise Exception.CreateFmt('REGISTERPROPERTYEDITOR: parsed %d call(s) but the source names'
      + ' it %d time(s) — the property-editor parser has drifted and would silently return an'
      + ' empty base list, which makes every reachability check pass vacuously',
      [got2, want2]);
end;

{ '|'-separated fields, exactly ACount of them or nothing. Written out rather than reached for
  via TStringHelper.Split, which needs a modeswitch this unit does not enable. }
function SplitFields(const ALine: string; ACount: Integer; out AFields: TStringArray): Boolean;
var
  i, st, n: Integer;
begin
  SetLength(AFields, ACount);
  for i := 0 to ACount - 1 do AFields[i] := '';
  n := 0; st := 1;
  for i := 1 to Length(ALine) do
    if ALine[i] = '|' then
    begin
      if n >= ACount then Exit(False);
      AFields[n] := Copy(ALine, st, i - st);
      Inc(n); st := i + 1;
    end;
  if n <> ACount - 1 then Exit(False);
  AFields[n] := Copy(ALine, st, Length(ALine) - st + 1);
  Result := True;
end;

function SplitEditorRegistration(const ALine: string;
  out AType, ABase, AProp, AEditor: string): Boolean;
var f: TStringArray;
begin
  AType := ''; ABase := ''; AProp := ''; AEditor := '';
  Result := SplitFields(ALine, 4, f);
  if not Result then Exit;
  AType := f[0]; ABase := f[1]; AProp := f[2]; AEditor := f[3];
end;

function SplitClassDeclaration(const ALine: string; out AName, AAncestor: string): Boolean;
var f: TStringArray;
begin
  AName := ''; AAncestor := '';
  Result := SplitFields(ALine, 2, f);
  if not Result then Exit;
  AName := f[0]; AAncestor := f[1];
end;

{ The classes an editor is registered on for APropertyName, e.g. 'Version' -> the base classes
  whose Object Inspector entry opens the About dialog. A view over the records above, so the
  drift self-check that guards them guards this too. }
procedure CollectPropertyEditorBases(const APropertyName: string; ADest: TStrings);
var
  regs: TStringList;
  i: Integer;
  ty, base, prop, ed: string;
begin
  regs := TStringList.Create;
  try
    CollectPropertyEditorRegistrations(regs);
    for i := 0 to regs.Count - 1 do
      if SplitEditorRegistration(regs[i], ty, base, prop, ed)
         and (prop = APropertyName) and (ADest.IndexOf(base) < 0) then
        ADest.Add(base);
  finally
    regs.Free;
  end;
end;

procedure CollectClassDeclarations(ADest: TStrings);
{ `TName = class(TAncestor)`. Walking backwards from the 'class' keyword rather than forwards
  from an identifier is what keeps `class function` / `class procedure` / `class of` out: those
  have no '=' behind them. A forward declaration (`TName = class;`) and an ancestor-less
  `= class` have no '(' after the keyword and are skipped for the same reason — there is no
  ancestor to report. }
var
  src, up, nm, anc: string;
  p, e, s, a, b: Integer;
begin
  src := LoadDesignSource;          { comments AND literals blanked: the file builds .lfm text
                                      containing 'class(TTyForm)' inside string literals }
  up := UpperCase(src);
  p := 1;
  repeat
    p := PosEx('CLASS', up, p);
    if p = 0 then Break;
    if IsWholeIdentifierAt(up, p, Length('CLASS')) then
    begin
      { back over whitespace to the '=' }
      e := p - 1;
      while (e >= 1) and (src[e] in [' ', #9, #13, #10]) do Dec(e);
      if (e >= 1) and (src[e] = '=') then
      begin
        { back over whitespace again, then over the declared name }
        s := e - 1;
        while (s >= 1) and (src[s] in [' ', #9, #13, #10]) do Dec(s);
        b := s;
        while (s >= 1) and (src[s] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Dec(s);
        nm := Copy(src, s + 1, b - s);
        { forward over whitespace to the ancestor's '(' }
        a := p + Length('CLASS');
        while (a <= Length(src)) and (src[a] in [' ', #9, #13, #10]) do Inc(a);
        if (nm <> '') and (a <= Length(src)) and (src[a] = '(') then
        begin
          b := PosEx(')', src, a + 1);
          if b > 0 then
          begin
            anc := Trim(Copy(src, a + 1, b - a - 1));
            if anc <> '' then ADest.Add(nm + '|' + anc);
          end;
        end;
      end;
    end;
    p := p + Length('CLASS');
  until False;
end;

end.
