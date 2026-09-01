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

{ ---- validation ---- }
{ Every option in the tree that the catalog does not recognise, plus every
  enumerated option set to a value outside its list. Order is the tree's own, so
  an editor reporting them in order reports them top to bottom. }
function TyOptValidate(AOption: TTyChartOption): TTyOptIssueArray;

implementation

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
    begin
      AddIssue(C, oikUnknownOption, sub, '', '');
      { Do not descend into an unknown subtree: everything under it would be
        reported too, and one wrong key would produce a page of noise. }
      Continue;
    end;
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
