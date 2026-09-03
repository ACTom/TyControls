unit tyControls.AdvChart.Complete;
{$mode objfpc}{$H+}
{ Lookup, completion and validation over the generated option catalog.

  The catalog unit next door is pure GENERATED data; everything that reasons
  about it lives here, hand-written, so it stays readable and headless-testable.
  Same split as Css.Catalog / Css.Complete.

  TWO PATH SPELLINGS, and keeping them apart is the whole job:

    CATALOG path   series-line.itemStyle.color
                   Variant-qualified, index-free. This is the schema's own
                   spelling and it is what the DAG is keyed by.

    RUNTIME path   series[0].itemStyle.color
                   What a user writes and what TTyChartOption.Find takes.

  A runtime path is AMBIGUOUS on its own: `series[0].itemStyle` means twenty-three
  different things depending on what `series[0].type` says, and that is precisely
  why a catalog is worth generating. Resolving it therefore needs the actual
  option tree in hand -- see TyOptFindFor and TyOptValidate, which read the
  neighbouring `type` value to pick the variant.

  LCL-free: SysUtils, Classes, fpjson and the two AdvChart units. }
interface
uses
  SysUtils, Classes, fpjson,
  tyControls.AdvChart.Catalog, tyControls.AdvChart.Option;

type
  TTyOptLookup = record
    Found: Boolean;
    Node: Integer;
    { When Found is False: the 0-based path segment that could not be resolved --
      what an editor underlines. -1 when the failure is not positional. }
    FailedAt: Integer;
    { The segment text that failed, for a message that names the offender. }
    FailedName: string;
  end;

  { One thing wrong with an option tree. Positional, so an editor can point. }
  TTyOptIssueKind = (oikUnknownOption, oikBadEnumValue);
  TTyOptIssue = record
    Kind: TTyOptIssueKind;
    { The RUNTIME path, as the user wrote it. }
    Path: string;
    { For oikBadEnumValue: what was written and what is allowed. }
    Value: string;
    Allowed: string;
  end;
  TTyOptIssueArray = array of TTyOptIssue;

{ ---- raw catalog access ---- }
function TyOptStrAt(AIndex: Integer): string;
function TyOptTypeOf(ANode: Integer): string;
function TyOptUiOf(ANode: Integer): string;
{ False when the schema states no default at all, which is different from a
  default that happens to be empty. }
function TyOptDefaultOf(ANode: Integer; out AValue: string): Boolean;
{ '' when the option is not marked with a version. }
function TyOptSinceOf(ANode: Integer): string;
{ False when the option has no enumerated values in the schema. NOTE that a
  False here does NOT mean anything goes: 5,776 string options carry their
  allowed values only as prose, xAxis.type among them. }
function TyOptEnumOf(ANode: Integer; AList: TStrings): Boolean;
{ Property names of a node's children, for a completion list. Structural edges
  ('[]' and '=tag') are excluded -- they are not things a user types. }
procedure TyOptChildNames(ANode: Integer; AList: TStrings);
{ True when this node is one of the five discriminated unions. }
function TyOptIsVariantContainer(ANode: Integer): Boolean;
{ The tags of a union's members ('line', 'bar', ...). False when not a union. }
function TyOptVariantTags(ANode: Integer; AList: TStrings): Boolean;
{ The child reached by a plain property name, or -1. }
function TyOptChild(ANode: Integer; const AName: string): Integer;
{ The element node of a homogeneous array, or -1. }
function TyOptArrayItem(ANode: Integer): Integer;
{ The member of a union with this tag, or -1. }
function TyOptVariant(ANode: Integer; const ATag: string): Integer;

{ ---- paths ---- }
{ Resolve a CATALOG path: dotted, index-free, variants written as 'series-line'. }
function TyOptFind(const APath: string): TTyOptLookup;
{ Resolve a RUNTIME path ('series[0].itemStyle.color') against a real option
  tree, using its own `type` values to choose union variants. }
function TyOptFindFor(AOption: TTyChartOption; const APath: string): TTyOptLookup;

{ ---- completion ---- }
type
  { Where the caret is, and therefore what may be offered. }
  TTyOptCaretKind = (ockKey, ockValue);

  TTyOptCaretContext = record
    Kind: TTyOptCaretKind;
    { The CONTAINER the caret sits inside, as a catalog node. -1 when the text
      leads somewhere the catalog does not know, which is not an error while
      someone is still typing. }
    Node: Integer;
    { That container's path, variant-qualified, for a status line. }
    Path: string;
    { What has been typed at the caret so far, for prefix filtering. }
    Partial: string;
    { When Kind is ockValue: the key whose value the caret is on. }
    ValueOf: string;
    { True when the caret is inside an array element whose union variant could
      not be decided because no `type` has been written yet. An editor should
      say "which series type?" rather than silently offer nothing. }
    NeedsVariantType: Boolean;
  end;

{ Where is the caret, structurally?

  Scans the text BEFORE the caret, tolerantly. It must NOT use the JSON reader:
  while someone is typing the text is almost never parseable -- an unclosed
  brace is the normal state mid-edit -- and a completion list that only appeared
  once the document was valid would appear approximately never.

  The scan also remembers the `type` value of each object it enters, so a union
  variant resolves without a parsed tree: `series[0].itemStyle` means twenty-three
  different things, and by the time the caret is inside it the `type` has usually
  been typed a line above. }
function TyOptContextAt(const ATextBeforeCaret: string): TTyOptCaretContext;

{ The completion list for that position: property names at a key position, the
  enumerated values at a value position, filtered by what has been typed.
  False when there is nothing sensible to offer. }
function TyOptCompletionsAt(const ATextBeforeCaret: string; AList: TStrings): Boolean;


{ ---- what an editor needs that a shell must not work out for itself ----

  Everything below exists so the design-time dialog can stay wiring. Each one is
  a decision about the catalog or about text, and a decision in designtime/ is a
  decision with no test behind it: that directory is not in the test build. }

{ The text before a caret at 1-based ALINE and 1-based BYTE column ACOL.

  Named and tested rather than inlined at the call site because the obvious
  reflex -- hand the whole document to TyOptContextAt, the way the CSS editor
  hands it FEdit.Lines.Text -- is wrong here: text AFTER the caret must not
  decide a union variant, and TestTypeWrittenAfterTheCaretIsNotSeen exists
  because it once did. Handles LF, CRLF and lone CR, and clamps a column past
  the end of its line. }
function TyOptSliceBefore(const AText: string; ALine, ACol: Integer): string;

type
  { A catalog edge, keeping the structure TyOptChildNames drops on purpose. }
  TTyOptEdgeKind = (oekProperty, oekArrayItem, oekVariant);
  TTyOptEdge = record
    Kind: TTyOptEdgeKind;
    { For oekProperty the property name; for oekVariant the tag without its
      '='; for oekArrayItem the empty string. }
    Name: string;
    Node: Integer;
  end;
  TTyOptEdgeArray = array of TTyOptEdge;

{ Every edge of a node, classified. A reference tree needs the structural ones a
  completion list must not offer: '[]' is how you learn series is an array, and
  '=bar' is how you learn which twenty-three things it can hold. }
function TyOptEdgesOf(ANode: Integer): TTyOptEdgeArray;

{ One line about a node for a status bar: its type, its stated default, its
  numeric range and the version it arrived in, whichever of those exist. }
function TyOptSummary(ANode: Integer): string;

{ What may be OFFERED at a value position -- wider than TyOptEnumOf, which is
  the schema's enumeration alone. Adds true/false for a boolean option and the
  stated default for anything else that has one. Over the 2,455 nodes: 154 carry
  an enumeration, 246 are boolean, 1,367 state a default. It invents nothing for
  the string options whose allowed values live only in prose. }
function TyOptValueCandidates(ANode: Integer; AList: TStrings): Boolean;

{ The help for a union whose variant is still undecided: at a key position the
  single word `type`, at that key's value the union's tags. }
function TyOptVariantHelpAt(const ATextBeforeCaret: string;
  AList: TStrings): Boolean;

{ The caret's variant-qualified catalog path for a status line, or the prompt
  saying a `type` has to be written before anything under here can be known.
  Exists so the dialog never calls TyOptContextAt itself. }
function TyOptStatusAt(const ATextBeforeCaret: string): string;

{ The text a completion actually inserts, and how far to put the caret back
  inside it.

  Not just the name: an object-valued key wants its braces, a string-valued one
  wants its quotes, and an enum member at a value position must be QUOTED --
  fcl-json accepts an unquoted KEY but rejects an unquoted string VALUE, so
  inserting a bare `line` for `type` produces text that cannot parse. }
function TyOptCompletionInsert(const ATextBeforeCaret, AItem: string;
  out AInsert: string; out ACaretBack: Integer): Boolean;

{ The text a double-click in the reference tree inserts, given what already
  follows on the caret's line -- so it can add the comma the user would
  otherwise have to notice was missing. }
function TyOptTreeInsert(ANode: Integer; const AName: string;
  AKind: TTyOptEdgeKind; const ACurrentLineTail: string): string;

{ The closest known sibling name to a misspelling, for a "did you mean" -- or ''
  when nothing is close enough to be worth guessing at. }
function TyOptSuggestName(ANode: Integer; const AWrong: string): string;

{ ---- validation ---- }
{ Every option in the tree that the catalog does not recognise, plus every
  enumerated option set to a value outside its list. Order is the tree's own, so
  an editor reporting them in order reports them top to bottom. }
function TyOptValidate(AOption: TTyChartOption): TTyOptIssueArray;

implementation

uses
  { Only for the editor vocabulary below; kept out of the interface uses so this
    unit's public face still names only the AdvChart layer. }
  tyControls.StrConsts;

function TyOptStrAt(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(TyOptStr)) then Exit('');
  Result := TyOptStr[AIndex];
end;

function ValidNode(ANode: Integer): Boolean;
begin
  Result := (ANode >= 0) and (ANode <= High(TyOptNodes));
end;

function TyOptTypeOf(ANode: Integer): string;
begin
  if not ValidNode(ANode) then Exit('');
  Result := TyOptStrAt(TyOptNodes[ANode].TypeStr);
end;

function TyOptUiOf(ANode: Integer): string;
begin
  if not ValidNode(ANode) then Exit('');
  Result := TyOptStrAt(TyOptNodes[ANode].UiStr);
end;

function TyOptDefaultOf(ANode: Integer; out AValue: string): Boolean;
begin
  AValue := '';
  if not ValidNode(ANode) then Exit(False);
  Result := TyOptNodes[ANode].DefaultStr >= 0;
  if Result then
    AValue := TyOptStrAt(TyOptNodes[ANode].DefaultStr);
end;

function TyOptSinceOf(ANode: Integer): string;
begin
  if not ValidNode(ANode) then Exit('');
  Result := TyOptStrAt(TyOptNodes[ANode].SinceStr);
end;

function TyOptEnumOf(ANode: Integer; AList: TStrings): Boolean;
var
  raw: string;
begin
  if AList <> nil then AList.Clear;
  if not ValidNode(ANode) then Exit(False);
  Result := TyOptNodes[ANode].EnumStr >= 0;
  if not Result then Exit;
  raw := TyOptStrAt(TyOptNodes[ANode].EnumStr);
  if AList = nil then Exit;
  { Comma-separated, unquoted, and no value in the whole schema contains a
    comma -- so a plain split is safe. Do NOT trim: 'Courier New' has a space
    that belongs to it. }
  AList.Delimiter := ',';
  AList.StrictDelimiter := True;
  AList.DelimitedText := raw;
end;

{ A structural edge is one the schema invented, not one a user types. }
function IsStructuralName(const AName: string): Boolean;
begin
  Result := (AName = '[]') or ((AName <> '') and (AName[1] = '='));
end;

procedure TyOptChildNames(ANode: Integer; AList: TStrings);
var
  i: Integer;
  n: string;
begin
  if AList = nil then Exit;
  AList.Clear;
  if not ValidNode(ANode) then Exit;
  for i := TyOptNodes[ANode].FirstChild to
           TyOptNodes[ANode].FirstChild + TyOptNodes[ANode].ChildCount - 1 do
  begin
    n := TyOptStrAt(TyOptEdges[i].NameStr);
    if not IsStructuralName(n) then
      AList.Add(n);
  end;
end;

function TyOptIsVariantContainer(ANode: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if not ValidNode(ANode) then Exit;
  for i := TyOptNodes[ANode].FirstChild to
           TyOptNodes[ANode].FirstChild + TyOptNodes[ANode].ChildCount - 1 do
    if Copy(TyOptStrAt(TyOptEdges[i].NameStr), 1, 1) = '=' then
      Exit(True);
end;

function TyOptVariantTags(ANode: Integer; AList: TStrings): Boolean;
var
  i: Integer;
  n: string;
begin
  if AList <> nil then AList.Clear;
  Result := False;
  if not ValidNode(ANode) then Exit;
  for i := TyOptNodes[ANode].FirstChild to
           TyOptNodes[ANode].FirstChild + TyOptNodes[ANode].ChildCount - 1 do
  begin
    n := TyOptStrAt(TyOptEdges[i].NameStr);
    if Copy(n, 1, 1) = '=' then
    begin
      Result := True;
      if AList <> nil then AList.Add(Copy(n, 2, MaxInt));
    end;
  end;
end;

function EdgeNamed(ANode: Integer; const AName: string): Integer;
var i: Integer;
begin
  Result := -1;
  if not ValidNode(ANode) then Exit;
  for i := TyOptNodes[ANode].FirstChild to
           TyOptNodes[ANode].FirstChild + TyOptNodes[ANode].ChildCount - 1 do
    if TyOptStrAt(TyOptEdges[i].NameStr) = AName then
      Exit(TyOptEdges[i].Node);
end;

function TyOptChild(ANode: Integer; const AName: string): Integer;
begin
  Result := EdgeNamed(ANode, AName);
  { The one wildcard the schema has: rich text style names are user-chosen, so
    any name under `rich` resolves to the single <style_name> child. Without
    this every real rich style would validate as an unknown option. }
  if (Result < 0) and (not IsStructuralName(AName)) then
    Result := EdgeNamed(ANode, '<style_name>');
end;

function TyOptArrayItem(ANode: Integer): Integer;
begin
  Result := EdgeNamed(ANode, '[]');
end;

function TyOptVariant(ANode: Integer; const ATag: string): Integer;
begin
  Result := EdgeNamed(ANode, '=' + ATag);
end;

{ Split 'series-line' into 'series' + 'line'. Property names never contain a
  dash, so the first one is unambiguous. }
procedure SplitVariant(const ASeg: string; out AName, ATag: string);
var p: Integer;
begin
  p := Pos('-', ASeg);
  if p > 0 then
  begin
    AName := Copy(ASeg, 1, p - 1);
    ATag := Copy(ASeg, p + 1, MaxInt);
  end
  else
  begin
    AName := ASeg;
    ATag := '';
  end;
end;

function NoLookup(AAt: Integer; const AName: string): TTyOptLookup;
begin
  Result.Found := False;
  Result.Node := -1;
  Result.FailedAt := AAt;
  Result.FailedName := AName;
end;

function OkLookup(ANode: Integer): TTyOptLookup;
begin
  Result.Found := True;
  Result.Node := ANode;
  Result.FailedAt := -1;
  Result.FailedName := '';
end;

procedure SplitPath(const APath: string; AOut: TStrings);
begin
  AOut.Delimiter := '.';
  AOut.StrictDelimiter := True;
  AOut.DelimitedText := APath;
end;

function TyOptFind(const APath: string): TTyOptLookup;
var
  segs: TStringList;
  i, cur, nxt: Integer;
  name, tag: string;
begin
  Result := NoLookup(0, APath);
  if APath = '' then Exit;
  cur := TyOptRoot;
  segs := TStringList.Create;
  try
    SplitPath(APath, segs);
    for i := 0 to segs.Count - 1 do
    begin
      if segs[i] = '' then Exit(NoLookup(i, ''));
      SplitVariant(segs[i], name, tag);
      nxt := TyOptChild(cur, name);
      if nxt < 0 then Exit(NoLookup(i, segs[i]));
      if tag <> '' then
      begin
        nxt := TyOptVariant(nxt, tag);
        if nxt < 0 then Exit(NoLookup(i, segs[i]));
      end;
      cur := nxt;
    end;
    Result := OkLookup(cur);
  finally
    segs.Free;
  end;
end;

{ Strip a trailing [n] from a runtime segment. }
procedure SplitIndex(const ASeg: string; out AName: string; out AIndex: Integer);
var lb, rb: Integer;
begin
  AName := ASeg;
  AIndex := -1;
  lb := Pos('[', ASeg);
  if lb = 0 then Exit;
  rb := Pos(']', ASeg);
  if rb <= lb then Exit;
  AName := Copy(ASeg, 1, lb - 1);
  AIndex := StrToIntDef(Copy(ASeg, lb + 1, rb - lb - 1), -1);
end;

function TyOptFindFor(AOption: TTyChartOption; const APath: string): TTyOptLookup;
var
  segs: TStringList;
  i, cur, nxt, idx: Integer;
  name, runtimePath, tag: string;
begin
  Result := NoLookup(0, APath);
  if APath = '' then Exit;
  cur := TyOptRoot;
  runtimePath := '';
  segs := TStringList.Create;
  try
    SplitPath(APath, segs);
    for i := 0 to segs.Count - 1 do
    begin
      if segs[i] = '' then Exit(NoLookup(i, ''));
      SplitIndex(segs[i], name, idx);
      if runtimePath = '' then runtimePath := segs[i]
      else runtimePath := runtimePath + '.' + segs[i];

      nxt := TyOptChild(cur, name);
      if nxt < 0 then Exit(NoLookup(i, segs[i]));

      { A union has to be resolved by the tree's own `type` value. Without the
        tree we could not know which of twenty-three shapes this is. }
      if TyOptIsVariantContainer(nxt) then
      begin
        tag := '';
        if AOption <> nil then
          tag := AOption.GetStr(runtimePath + '.type', '');
        if tag = '' then
        begin
          { No type stated. ECharts' own defaults would be the honest answer,
            but they differ per container, so report rather than guess -- an
            editor can then say "which series type?" instead of validating
            against the wrong one. }
          Exit(NoLookup(i, segs[i]));
        end;
        nxt := TyOptVariant(nxt, tag);
        if nxt < 0 then Exit(NoLookup(i, segs[i]));
      end
      else if idx >= 0 then
      begin
        { A plain array: descend into its element type. }
        if TyOptArrayItem(nxt) >= 0 then
          nxt := TyOptArrayItem(nxt);
      end;
      cur := nxt;
    end;
    Result := OkLookup(cur);
  finally
    segs.Free;
  end;
end;


{ ---- completion ---- }

type
  { One open container in the tolerant scan. }
  TScanFrame = record
    IsArray: Boolean;
    { The key that introduced this container; '' for the document root and for
      an element inside an array. }
    Name: string;
    { Object only: True right after an opening brace or a comma, i.e. a key is
      expected next. (Do not write a brace character in a comment here: FPC
      nests brace comments, so it would open a second level and swallow the
      rest of the file.) }
    ExpectKey: Boolean;
    { The key most recently completed with ':'. }
    PendingKey: string;
    { Object only: the value of a `type` key seen anywhere in this object. This
      is what lets a union variant resolve without a parsed tree. }
    TypeVal: string;
  end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '-'];
end;

{ Walk the frame stack down from the root, resolving each container against the
  catalog. Returns -1 as soon as a step is unknown -- which is the ordinary case
  for a misspelling and must not be treated as an error here. }
function ResolveFrames(const AFrames: array of TScanFrame; ACount: Integer;
  out APath: string; out ANeedsType: Boolean): Integer;
var
  i, cur: Integer;
begin
  APath := '';
  ANeedsType := False;
  cur := TyOptRoot;
  for i := 0 to ACount - 1 do
  begin
    if AFrames[i].Name <> '' then
    begin
      cur := TyOptChild(cur, AFrames[i].Name);
      if cur < 0 then Exit(-1);
      if APath = '' then APath := AFrames[i].Name
      else APath := APath + '.' + AFrames[i].Name;
    end;
    if AFrames[i].IsArray then
      Continue;
    { An object. If its parent container is a union, this object IS one of the
      members, and only its own `type` can say which. }
    if TyOptIsVariantContainer(cur) then
    begin
      if AFrames[i].TypeVal = '' then
      begin
        ANeedsType := True;
        Exit(-1);
      end;
      cur := TyOptVariant(cur, AFrames[i].TypeVal);
      if cur < 0 then Exit(-1);
      APath := APath + '-' + AFrames[i].TypeVal;
    end
    else if TyOptArrayItem(cur) >= 0 then
      cur := TyOptArrayItem(cur);
  end;
  Result := cur;
end;

function TyOptContextAt(const ATextBeforeCaret: string): TTyOptCaretContext;
var
  frames: array of TScanFrame;
  depth, i, n, tokStart: Integer;
  c, quote: Char;
  tok: string;
  inTrailingToken: Boolean;

  procedure Push(AIsArray: Boolean);
  var nm: string;
  begin
    nm := '';
    if (depth > 0) and (not frames[depth - 1].IsArray) then
    begin
      nm := frames[depth - 1].PendingKey;
      frames[depth - 1].PendingKey := '';
    end;
    if depth = Length(frames) then SetLength(frames, 8 + depth * 2);
    frames[depth].IsArray := AIsArray;
    frames[depth].Name := nm;
    frames[depth].ExpectKey := not AIsArray;
    frames[depth].PendingKey := '';
    frames[depth].TypeVal := '';
    Inc(depth);
  end;

  procedure Pop;
  begin
    if depth > 1 then Dec(depth);   { never pop the synthetic root }
  end;

  { A completed token: either a key, a `type` value worth remembering, or
    something we do not care about. }
  procedure TakeToken(const AText: string);
  begin
    if depth = 0 then Exit;
    if frames[depth - 1].IsArray then Exit;
    if frames[depth - 1].ExpectKey then
      frames[depth - 1].PendingKey := AText
    else if frames[depth - 1].PendingKey = 'type' then
      frames[depth - 1].TypeVal := AText;
  end;

begin
  Result.Kind := ockKey;
  Result.Node := -1;
  Result.Path := '';
  Result.Partial := '';
  Result.ValueOf := '';
  Result.NeedsVariantType := False;

  SetLength(frames, 16);
  depth := 0;
  { A synthetic root object, so text with no outer brace at all still resolves
    against the option root instead of against nothing. }
  Push(False);

  n := Length(ATextBeforeCaret);
  i := 1;
  inTrailingToken := False;
  tok := '';
  while i <= n do
  begin
    c := ATextBeforeCaret[i];
    { comments }
    if (c = '/') and (i < n) and (ATextBeforeCaret[i + 1] = '/') then
    begin
      while (i <= n) and not (ATextBeforeCaret[i] in [#10, #13]) do Inc(i);
      Continue;
    end;
    if (c = '/') and (i < n) and (ATextBeforeCaret[i + 1] = '*') then
    begin
      Inc(i, 2);
      while (i < n) and not ((ATextBeforeCaret[i] = '*') and (ATextBeforeCaret[i + 1] = '/')) do Inc(i);
      Inc(i, 2);
      Continue;
    end;
    { strings }
    if (c = '''') or (c = '"') then
    begin
      quote := c;
      tokStart := i + 1;
      Inc(i);
      while (i <= n) and (ATextBeforeCaret[i] <> quote) do
      begin
        if (ATextBeforeCaret[i] = '\') and (i < n) then Inc(i);
        Inc(i);
      end;
      tok := Copy(ATextBeforeCaret, tokStart, i - tokStart);
      if i > n then
      begin
        { The string is still open at the caret -- this is what is being typed. }
        Result.Partial := tok;
        inTrailingToken := True;
        Break;
      end;
      TakeToken(tok);
      Inc(i);
      inTrailingToken := False;
      Continue;
    end;
    { bare identifiers and numbers }
    if IsIdentChar(c) then
    begin
      tokStart := i;
      while (i <= n) and IsIdentChar(ATextBeforeCaret[i]) do Inc(i);
      tok := Copy(ATextBeforeCaret, tokStart, i - tokStart);
      if i > n then
      begin
        { It runs up to the caret, so it is the partial being typed. Do not
          take it as a completed key: half a word is not a key yet. }
        Result.Partial := tok;
        inTrailingToken := True;
        Break;
      end;
      TakeToken(tok);
      inTrailingToken := False;
      Continue;
    end;
    case c of
      '{': Push(False);
      '[': Push(True);
      '}', ']': Pop;
      ':': if not frames[depth - 1].IsArray then frames[depth - 1].ExpectKey := False;
      ',': if frames[depth - 1].IsArray then
             { nothing: element index does not affect which options are legal }
           else
           begin
             frames[depth - 1].ExpectKey := True;
             frames[depth - 1].PendingKey := '';
           end;
    end;
    if not (c in [' ', #9, #10, #13]) then
      inTrailingToken := False;
    Inc(i);
  end;

  if depth > 0 then
  begin
    if frames[depth - 1].IsArray then
      Result.Kind := ockValue
    else if frames[depth - 1].ExpectKey then
      Result.Kind := ockKey
    else
    begin
      Result.Kind := ockValue;
      Result.ValueOf := frames[depth - 1].PendingKey;
    end;
  end;

  Result.Node := ResolveFrames(frames, depth, Result.Path, Result.NeedsVariantType);
end;

function TyOptCompletionsAt(const ATextBeforeCaret: string; AList: TStrings): Boolean;
var
  ctx: TTyOptCaretContext;
  all: TStringList;
  i, target: Integer;
  low: string;
begin
  Result := False;
  if AList = nil then Exit;
  AList.Clear;
  ctx := TyOptContextAt(ATextBeforeCaret);
  if ctx.Node < 0 then Exit;

  all := TStringList.Create;
  try
    if ctx.Kind = ockKey then
      TyOptChildNames(ctx.Node, all)
    else
    begin
      { A value position: only an enumerated option has anything to offer. The
        5,776 string options whose allowed values exist only as prose in the
        docs cannot be completed, and offering nothing is the honest answer
        rather than offering something invented. }
      if ctx.ValueOf = '' then Exit;
      target := TyOptChild(ctx.Node, ctx.ValueOf);
      if target < 0 then Exit;
      if not TyOptEnumOf(target, all) then Exit;
    end;

    low := LowerCase(ctx.Partial);
    for i := 0 to all.Count - 1 do
      if (low = '') or (Pos(low, LowerCase(all[i])) = 1) then
        AList.Add(all[i]);
    Result := AList.Count > 0;
  finally
    all.Free;
  end;
end;

{ ---- validation ---- }

type
  TIssueCollector = record
    Items: TTyOptIssueArray;
    Count: Integer;
  end;

procedure AddIssue(var C: TIssueCollector; AKind: TTyOptIssueKind;
  const APath, AValue, AAllowed: string);
begin
  if C.Count = Length(C.Items) then
    SetLength(C.Items, 8 + C.Count * 2);
  C.Items[C.Count].Kind := AKind;
  C.Items[C.Count].Path := APath;
  C.Items[C.Count].Value := AValue;
  C.Items[C.Count].Allowed := AAllowed;
  Inc(C.Count);
end;

procedure WalkValidate(AData: TJSONData; ANode: Integer; const APath: string;
  var C: TIssueCollector); forward;

procedure ValidateLeaf(AData: TJSONData; ANode: Integer; const APath: string;
  var C: TIssueCollector);
var
  list: TStringList;
  v: string;
begin
  if AData.JSONType <> jtString then Exit;
  if TyOptNodes[ANode].EnumStr < 0 then Exit;
  v := AData.AsString;
  list := TStringList.Create;
  try
    TyOptEnumOf(ANode, list);
    if list.IndexOf(v) < 0 then
      AddIssue(C, oikBadEnumValue, APath, v, TyOptStrAt(TyOptNodes[ANode].EnumStr));
  finally
    list.Free;
  end;
end;

procedure WalkObject(AObj: TJSONObject; ANode: Integer; const APath: string;
  var C: TIssueCollector);
var
  i, child: Integer;
  key, sub: string;
begin
  for i := 0 to AObj.Count - 1 do
  begin
    key := AObj.Names[i];
    if APath = '' then sub := key else sub := APath + '.' + key;
    child := TyOptChild(ANode, key);
    if child < 0 then
      AddIssue(C, oikUnknownOption, sub, '', '');
    { Descending with child = -1 is deliberate rather than guarded here: the
      ValidNode test at the top of WalkValidate is what stops an unknown subtree
      from being walked. An explicit Continue was here first and mutation showed
      it changed nothing -- the guard below was already doing the work, so the
      comment claiming otherwise was the only thing it added. }
    WalkValidate(AObj.Items[i], child, sub, C);
  end;
end;

procedure WalkValidate(AData: TJSONData; ANode: Integer; const APath: string;
  var C: TIssueCollector);
var
  i, item, variant: Integer;
  arr: TJSONArray;
  tag, sub: string;
begin
  { An unresolvable node stops the walk. This is what keeps ONE misspelled
    container from producing a page of issues about everything inside it: the
    key is reported once and its whole subtree is skipped. }
  if (AData = nil) or (not ValidNode(ANode)) then Exit;
  case AData.JSONType of
    jtObject:
      WalkObject(TJSONObject(AData), ANode, APath, C);
    jtArray:
      begin
        arr := TJSONArray(AData);
        for i := 0 to arr.Count - 1 do
        begin
          sub := APath + '[' + IntToStr(i) + ']';
          if TyOptIsVariantContainer(ANode) then
          begin
            tag := '';
            if arr.Items[i].JSONType = jtObject then
              tag := TJSONObject(arr.Items[i]).Get('type', '');
            variant := TyOptVariant(ANode, tag);
            { An unstated or unknown type is not reported as an unknown option:
              the value itself may be perfectly good and it is the TYPE that is
              missing. Saying "series[0].data is unknown" because the series has
              no type would be actively misleading. }
            if variant >= 0 then
              WalkValidate(arr.Items[i], variant, sub, C);
          end
          else
          begin
            item := TyOptArrayItem(ANode);
            if item >= 0 then
              WalkValidate(arr.Items[i], item, sub, C);
          end;
        end;
      end;
  else
    ValidateLeaf(AData, ANode, APath, C);
  end;
end;

{ ============ what an editor needs ============ }

function TyOptSliceBefore(const AText: string; ALine, ACol: Integer): string;
var
  i, len, line, lineStart: Integer;
begin
  Result := '';
  if (ALine < 1) or (ACol < 1) then Exit;
  len := Length(AText);
  line := 1;
  lineStart := 1;
  i := 1;
  while (i <= len) and (line < ALine) do
  begin
    if AText[i] = #13 then
    begin
      Inc(line);
      if (i < len) and (AText[i + 1] = #10) then Inc(i);
      lineStart := i + 1;
    end
    else if AText[i] = #10 then
    begin
      Inc(line);
      lineStart := i + 1;
    end;
    Inc(i);
  end;
  { Past the last line: everything is before the caret. }
  if line < ALine then Exit(AText);
  { Clamp to this line's end -- a caret past the end of a line, which the CSS
    editor turns off with eoScrollPastEol, still has to give a sane answer. }
  i := lineStart;
  while (i <= len) and (AText[i] <> #13) and (AText[i] <> #10) do Inc(i);
  if lineStart + ACol - 1 < i then i := lineStart + ACol - 1;
  Result := Copy(AText, 1, i - 1);
end;

function TyOptEdgesOf(ANode: Integer): TTyOptEdgeArray;
var
  i, n: Integer;
  nm: string;
begin
  Result := nil;
  if not ValidNode(ANode) then Exit;
  n := 0;
  SetLength(Result, TyOptNodes[ANode].ChildCount);
  for i := TyOptNodes[ANode].FirstChild to
           TyOptNodes[ANode].FirstChild + TyOptNodes[ANode].ChildCount - 1 do
  begin
    nm := TyOptStrAt(TyOptEdges[i].NameStr);
    if nm = '[]' then
    begin
      Result[n].Kind := oekArrayItem;
      Result[n].Name := '';
    end
    else if Copy(nm, 1, 1) = '=' then
    begin
      Result[n].Kind := oekVariant;
      Result[n].Name := Copy(nm, 2, MaxInt);
    end
    else
    begin
      Result[n].Kind := oekProperty;
      Result[n].Name := nm;
    end;
    Result[n].Node := TyOptEdges[i].Node;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyOptSummary(ANode: Integer): string;
var
  t, d, since, lo, hi: string;
begin
  Result := '';
  if not ValidNode(ANode) then Exit;
  t := TyOptTypeOf(ANode);
  if t <> '' then Result := t;
  if TyOptDefaultOf(ANode, d) then
  begin
    if d = '' then d := '''''';
    if Result <> '' then Result := Result + '  ';
    Result := Result + Format(rsTyOptSummaryDefault, [d]);
  end;
  { The range is two strings in the schema, either of which may be absent -- an
    option with only a lower bound is common. }
  lo := TyOptStrAt(TyOptNodes[ANode].MinStr);
  hi := TyOptStrAt(TyOptNodes[ANode].MaxStr);
  if (lo <> '') or (hi <> '') then
  begin
    if Result <> '' then Result := Result + '  ';
    if lo = '' then lo := '?';
    if hi = '' then hi := '?';
    Result := Result + Format(rsTyOptSummaryRange, [lo, hi]);
  end;
  since := TyOptSinceOf(ANode);
  if since <> '' then
  begin
    if Result <> '' then Result := Result + '  ';
    Result := Result + Format(rsTyOptSummarySince, [since]);
  end;
end;

function TyOptValueCandidates(ANode: Integer; AList: TStrings): Boolean;
var
  d: string;
begin
  Result := False;
  if AList = nil then Exit;
  AList.Clear;
  if not ValidNode(ANode) then Exit;
  { The schema's own enumeration wins outright when there is one. }
  if TyOptEnumOf(ANode, AList) then Exit(True);
  { A boolean's two values are not stored as an enumeration anywhere, and they
    are the single most-typed value in an option tree. }
  if Pos('boolean', LowerCase(TyOptTypeOf(ANode))) > 0 then
  begin
    AList.Add('true');
    AList.Add('false');
    Exit(True);
  end;
  { Otherwise the stated default, which is a suggestion rather than a
    constraint -- and better than an empty popup. }
  if TyOptDefaultOf(ANode, d) and (d <> '') then
  begin
    AList.Add(d);
    Exit(True);
  end;
end;

function TyOptVariantHelpAt(const ATextBeforeCaret: string;
  AList: TStrings): Boolean;
var
  ctx: TTyOptCaretContext;
  lk: TTyOptLookup;
begin
  Result := False;
  if AList = nil then Exit;
  AList.Clear;
  ctx := TyOptContextAt(ATextBeforeCaret);
  if not ctx.NeedsVariantType then Exit;
  if ctx.Kind = ockKey then
  begin
    { One word, because until it is written nothing else under here is knowable. }
    AList.Add('type');
    Exit(True);
  end;
  { NOT ctx.Node -- it is -1 here BY DESIGN. The context cannot resolve a node
    inside a union whose variant is undecided, which is exactly the state this
    function exists for; what it does leave behind is the container's PATH. }
  if not SameText(ctx.ValueOf, 'type') then Exit;
  lk := TyOptFind(ctx.Path);
  if lk.Found then
    Result := TyOptVariantTags(lk.Node, AList);
end;

function TyOptStatusAt(const ATextBeforeCaret: string): string;
var
  ctx: TTyOptCaretContext;
begin
  ctx := TyOptContextAt(ATextBeforeCaret);
  if ctx.NeedsVariantType then Exit(rsTyOptStatusNeedsType);
  if ctx.Path = '' then Exit(rsTyOptStatusRoot);
  Result := ctx.Path;
end;

{ A bare number, locale-independently -- a value that may go in unquoted. Hand
  written rather than TryStrToFloat because that one honours the machine's
  decimal separator, and an option tree's numbers always use '.'. }
function LooksNumeric(const A: string): Boolean;
var
  i: Integer;
  seenDigit, seenDot: Boolean;
begin
  Result := False;
  seenDigit := False;
  seenDot := False;
  i := 1;
  if (i <= Length(A)) and ((A[i] = '-') or (A[i] = '+')) then Inc(i);
  while i <= Length(A) do
  begin
    if (A[i] >= '0') and (A[i] <= '9') then seenDigit := True
    else if A[i] = '.' then
    begin
      if seenDot then Exit;
      seenDot := True;
    end
    else
      Exit;
    Inc(i);
  end;
  Result := seenDigit;
end;

{ Does the caret already sit inside an open string literal? Then an inserted
  value must NOT bring its own quotes. Counts unescaped quotes of each kind. }
function InOpenString(const ABefore: string): Boolean;
var
  i: Integer;
  q: Char;
begin
  Result := False;
  q := #0;
  i := 1;
  while i <= Length(ABefore) do
  begin
    if (q <> #0) and (ABefore[i] = '\') then Inc(i)
    else if q <> #0 then
    begin
      if ABefore[i] = q then q := #0;
    end
    else if (ABefore[i] = '"') or (ABefore[i] = '''') then
      q := ABefore[i];
    Inc(i);
  end;
  Result := q <> #0;
end;

function TyOptCompletionInsert(const ATextBeforeCaret, AItem: string;
  out AInsert: string; out ACaretBack: Integer): Boolean;
var
  ctx: TTyOptCaretContext;
  child: Integer;
  t: string;
begin
  AInsert := AItem;
  ACaretBack := 0;
  Result := False;
  if AItem = '' then Exit;
  ctx := TyOptContextAt(ATextBeforeCaret);

  if ctx.Kind = ockValue then
  begin
    { A string value MUST be quoted: fcl-json is relaxed about keys, not about
      values, so a bare `line` for `type` yields text that cannot parse. }
    if InOpenString(ATextBeforeCaret) then Exit(True);
    if (AItem = 'true') or (AItem = 'false') then Exit(True);
    if LooksNumeric(AItem) then Exit(True);
    AInsert := '''' + AItem + '''';
    Exit(True);
  end;

  child := -1;
  if ctx.Node >= 0 then child := TyOptChild(ctx.Node, AItem);
  t := LowerCase(TyOptTypeOf(child));
  if Pos('object', t) > 0 then
  begin
    AInsert := AItem + ': {}';
    ACaretBack := 1;
  end
  else if Pos('array', t) > 0 then
  begin
    AInsert := AItem + ': []';
    ACaretBack := 1;
  end
  else if Pos('string', t) > 0 then
  begin
    AInsert := AItem + ': ''''';
    ACaretBack := 1;
  end
  else
    AInsert := AItem + ': ';
  Result := True;
end;

function TyOptTreeInsert(ANode: Integer; const AName: string;
  AKind: TTyOptEdgeKind; const ACurrentLineTail: string): string;
var
  child: Integer;
  t, tail: string;
  i: Integer;
begin
  case AKind of
    oekArrayItem: Result := '{}';
    oekVariant:   Result := 'type: ''' + AName + '''';
  else
    begin
      child := TyOptChild(ANode, AName);
      t := LowerCase(TyOptTypeOf(child));
      if Pos('object', t) > 0 then Result := AName + ': {}'
      else if Pos('array', t) > 0 then Result := AName + ': []'
      else if Pos('string', t) > 0 then Result := AName + ': '''''
      else Result := AName + ': ';
    end;
  end;
  { The comma the user would otherwise have to notice was missing: only when
    something that is not already a separator or a closer follows on the line. }
  tail := '';
  for i := 1 to Length(ACurrentLineTail) do
    if ACurrentLineTail[i] > ' ' then
    begin
      tail := Copy(ACurrentLineTail, i, MaxInt);
      Break;
    end;
  if (tail <> '') and (tail[1] <> ',') and (tail[1] <> '}') and (tail[1] <> ']') then
    Result := Result + ',';
end;

{ Levenshtein, bounded -- the strings here are option names, never long. }
function EditDistance(const A, B: string): Integer;
var
  prev, cur: array of Integer;
  i, j, cost: Integer;
begin
  if A = B then Exit(0);
  if A = '' then Exit(Length(B));
  if B = '' then Exit(Length(A));
  SetLength(prev, Length(B) + 1);
  SetLength(cur, Length(B) + 1);
  for j := 0 to Length(B) do prev[j] := j;
  for i := 1 to Length(A) do
  begin
    cur[0] := i;
    for j := 1 to Length(B) do
    begin
      if A[i] = B[j] then cost := 0 else cost := 1;
      cur[j] := prev[j] + 1;
      if cur[j - 1] + 1 < cur[j] then cur[j] := cur[j - 1] + 1;
      if prev[j - 1] + cost < cur[j] then cur[j] := prev[j - 1] + cost;
    end;
    prev := Copy(cur, 0, Length(cur));
  end;
  Result := prev[Length(B)];
end;

function TyOptSuggestName(ANode: Integer; const AWrong: string): string;
var
  names: TStringList;
  i, d, best, limit: Integer;
begin
  Result := '';
  if (AWrong = '') or not ValidNode(ANode) then Exit;
  { A budget proportional to the word, floored at one. Too generous and a
    genuinely new key gets a confident wrong suggestion, which is worse than
    none: the reader stops looking for their own typo. }
  limit := Length(AWrong) div 3;
  if limit < 1 then limit := 1;
  best := MaxInt;
  names := TStringList.Create;
  try
    TyOptChildNames(ANode, names);
    for i := 0 to names.Count - 1 do
    begin
      if SameText(names[i], AWrong) then Exit(names[i]);
      d := EditDistance(LowerCase(AWrong), LowerCase(names[i]));
      if (d <= limit) and (d < best) then
      begin
        best := d;
        Result := names[i];
      end;
    end;
  finally
    names.Free;
  end;
end;


function TyOptValidate(AOption: TTyChartOption): TTyOptIssueArray;
var
  c: TIssueCollector;
begin
  c.Items := nil;
  c.Count := 0;
  if (AOption <> nil) and (AOption.Root <> nil) then
    WalkValidate(AOption.Root, TyOptRoot, '', c);
  SetLength(c.Items, c.Count);
  Result := c.Items;
end;

end.
