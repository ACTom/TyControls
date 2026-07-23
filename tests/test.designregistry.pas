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
  Classes, SysUtils, StrUtils;

{ Repo root — the test exe lives in tests/ (mirrors test.grid.streaming.pas). }
function RepoRoot: string;
{ Full path of the registration source everything here parses. }
function DesignSourceFile: string;

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

implementation

function RepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

function DesignSourceFile: string;
begin
  Result := RepoRoot + 'designtime' + PathDelim + 'tyControls.Design.pas';
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

{ Read the registration source, comments (and optionally literals) already removed. }
function LoadDesignSource(AKeepLiterals: Boolean = False): string;
var
  sl: TStringList;
  fn: string;
begin
  fn := DesignSourceFile;
  if not FileExists(fn) then
    raise Exception.Create('design-time registration source not found: ' + fn);
  sl := TStringList.Create;
  try
    sl.LoadFromFile(fn);
    Result := StripCommentsAndLiterals(sl.Text, AKeepLiterals);
  finally
    sl.Free;
  end;
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

{ The classes RegisterPropertyEditor actually hangs an editor on, read out of the registration
  source rather than copied into a const somewhere.

  Why parse instead of listing: the Version set moved twice during the change that introduced
  it (a base class was added, another folded away). A hand-kept copy would have gone stale
  inside one session. Splitting on top-level commas — depth-counted, because the first argument
  is itself a call, TypeInfo(string) — and keeping the second argument of every call whose third
  is the wanted property literal makes the registrations themselves the source of truth. }
procedure CollectPropertyEditorBases(const APropertyName: string; ADest: TStrings);
var
  src, up, want: string;
  args: TStringList;
  p, i, depth, st, want2, got2: Integer;
begin
  src := LoadDesignSource(True);
  up := UpperCase(src);
  want := QuotedStr(APropertyName);

  { Whole-identifier match with the paren NOT glued on — the same discipline ParseCallLists
    documents a few dozen lines up. Spelling it 'REGISTERPROPERTYEDITOR(' would make a single
    space before the paren yield an EMPTY base list, and an empty list makes the caller's
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
      if (args.Count >= 3) and (args[2] = want) and (ADest.IndexOf(args[1]) < 0) then
        ADest.Add(args[1]);
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

end.
