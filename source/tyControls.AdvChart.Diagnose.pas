unit tyControls.AdvChart.Diagnose;
{$mode objfpc}{$H+}
{ Everything wrong with a piece of option text, as one list an editor can show.

  ONE CALL IS THE POINT. The design-time dialog is not in the test build, so
  every judgement made inside it is a judgement with nothing behind it. This
  unit is where the judgements live: what counts as a problem, in what order,
  with what wording, pointing where. The dialog's job is to put the list in a
  box.

  A SEPARATE UNIT FROM Complete, because this one needs Builder and Series, and
  Complete's dependency contract -- Catalog plus Option, nothing else -- is
  worth keeping. Validation of the OPTION TREE belongs there; validation of what
  a CHART can be made of belongs here.

  IT NEVER RAISES. It is called on a timer while somebody types. }
interface
uses
  SysUtils, Classes,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Complete, tyControls.AdvChart.Locate;

type
  TTyOptDiagKind = (
    { The text is not an option at all. Exactly one of these, and nothing else:
      a document that does not parse has no tree to derive complaints from, and
      a page of them would bury the one that matters. }
    odkParseError,
    { The catalog does not know this option. }
    odkUnknownOption,
    { An enumerated option set to something outside its list. }
    odkBadEnumValue,
    { An element of a discriminated union with no `type` written yet. The
      catalog kernel is deliberately SILENT about this -- an untyped series'
      children are not unknown options, they are unknowable ones -- so it is
      the editor that has to say the useful thing. }
    odkNoSeriesType,
    { The option parses and the catalog accepts it, but the chart cannot be
      built from it: axes that name no grid, a series bound to an axis that
      does not exist. }
    odkBuild,
    { Nothing is wrong. Said out loud on purpose: a correct bar config draws
      axes and no bars today, and a developer who is not told that concludes
      the editor lied to them. }
    odkNothingPaintsYet);

  TTyOptDiag = record
    Kind: TTyOptDiagKind;
    { The runtime path this is about, or '' when it is about the whole text. }
    Path: string;
    { 1-based. Line = 0 means there is nowhere to jump: the diagnostic is about
      the document rather than about a place in it. }
    Line, Col, Len: Integer;
    { Ready to show. Already carries the "did you mean" when there is one. }
    Text: string;
  end;
  TTyOptDiagArray = array of TTyOptDiag;

{ Everything wrong with this text, in the order an editor should list it. }
function TyOptDiagnose(const AText: string): TTyOptDiagArray;

{ The text re-emitted as tidy JSON. False when it does not parse, in which case
  AOut is the input unchanged -- a Format button must never eat what somebody
  was in the middle of writing. }
function TyOptFormat(const AText: string; out AOut: string): Boolean;

implementation

uses
  fpjson,
  tyControls.AdvChart.Catalog, tyControls.AdvChart.Builder,
  tyControls.AdvChart.Series, tyControls.StrConsts;

const
  { Enough that a real config's problems all fit, small enough that a pathological
    one cannot flood the box. }
  cMaxRows = 100;

type
  TCollector = record
    Items: TTyOptDiagArray;
    Count: Integer;
    Keys: TTyOptKeyPosArray;
  end;

procedure Add(var C: TCollector; AKind: TTyOptDiagKind;
  const APath, AText: string);
var pos: TTyOptKeyPos;
begin
  if C.Count = Length(C.Items) then
    SetLength(C.Items, 8 + C.Count * 2);
  C.Items[C.Count].Kind := AKind;
  C.Items[C.Count].Path := APath;
  C.Items[C.Count].Text := AText;
  C.Items[C.Count].Line := 0;
  C.Items[C.Count].Col := 0;
  C.Items[C.Count].Len := 0;
  { Nearest, not exact: a diagnostic can name something nobody typed a name for
    -- an array element, a leaf the build derived. Landing on the container is
    useful; refusing to land is not. }
  if (APath <> '') and TyOptFindNearestKey(C.Keys, APath, pos) then
  begin
    C.Items[C.Count].Line := pos.Line;
    C.Items[C.Count].Col := pos.Col;
    C.Items[C.Count].Len := pos.Len;
  end;
  Inc(C.Count);
end;

{ Has this exact path already been reported under this kind? }
function AlreadyReported(const C: TCollector; AKind: TTyOptDiagKind;
  const APath: string): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to C.Count - 1 do
    if (C.Items[i].Kind = AKind) and (C.Items[i].Path = APath) then
      Exit(True);
end;

{ Text order, stable, with the document-level rows first.

  THE LIST IS READ TOP TO BOTTOM and its rows are caret targets, so the order
  has to be the order of the text -- not the order of the three passes that
  happened to produce them. A row with no position (the parse error, the all
  clear) is about the document, so it goes first. }
procedure SortByPosition(var C: TCollector);
var
  i, j: Integer;
  t: TTyOptDiag;
begin
  for i := 1 to C.Count - 1 do
  begin
    t := C.Items[i];
    j := i - 1;
    while (j >= 0)
      and ((C.Items[j].Line > t.Line)
        or ((C.Items[j].Line = t.Line) and (C.Items[j].Col > t.Col))) do
    begin
      C.Items[j + 1] := C.Items[j];
      Dec(j);
    end;
    C.Items[j + 1] := t;
  end;
end;

{ The parent of a runtime path, for asking the catalog what its siblings are. }
function ParentOf(const APath: string): string;
var i: Integer;
begin
  Result := '';
  for i := Length(APath) downto 1 do
    if APath[i] = '.' then Exit(Copy(APath, 1, i - 1));
end;

function LeafOf(const APath: string): string;
var i: Integer;
begin
  Result := APath;
  for i := Length(APath) downto 1 do
    if APath[i] = '.' then Exit(Copy(APath, i + 1, MaxInt));
end;

{ 'series[0].itemStyle is not an option ECharts 6.1 knows. Did you mean
  "itemStyle"?' -- the suggestion only when there is one worth making. }
function UnknownText(AOption: TTyChartOption; const APath: string): string;
var
  lk: TTyOptLookup;
  guess, parent: string;
  node: Integer;
begin
  Result := Format(rsTyOptDiagUnknown, [APath]);
  parent := ParentOf(APath);
  if parent = '' then
  begin
    { A TOP-LEVEL typo has no parent path, and asking the resolver for '' gets
      nothing -- so `xAxes` used to be reported with no suggestion at all,
      which is the one place a suggestion is easiest and most wanted. The
      parent of a root key is the root. }
    node := TyOptRoot;
  end
  else
  begin
    lk := TyOptFindFor(AOption, parent);
    if not lk.Found then Exit;
    node := lk.Node;
  end;
  guess := TyOptSuggestName(node, LeafOf(APath));
  if guess <> '' then
    Result := Result + ' ' + Format(rsTyOptDiagDidYouMean, [guess]);
end;

{ Every element of a variant container that has not said which variant it is.
  Walks the tree rather than the text so it sees exactly what the builder will. }
procedure NoteUntypedElements(AOption: TTyChartOption; var C: TCollector);
var
  i, j, n: Integer;
  el: TJSONData;
  tags, roots: TStringList;
  path, list: string;
  lk: TTyOptLookup;
begin
  tags := TStringList.Create;
  roots := TStringList.Create;
  try
    { Every top-level option, so this finds series, dataZoom, visualMap and any
      union a later ECharts adds -- rather than a hand-kept list of five that
      goes stale the first time the catalog is regenerated. }
    TyOptChildNames(TyOptRoot, roots);
    for i := 0 to roots.Count - 1 do
    begin
      path := roots[i];
      lk := TyOptFind(path);
      if not lk.Found then Continue;
      if not TyOptIsVariantContainer(lk.Node) then Continue;
      n := AOption.ComponentCount(path);
      for j := 0 to n - 1 do
      begin
        el := AOption.ComponentAt(path, j);
        if (el = nil) or not (el is TJSONObject) then Continue;
        if TJSONObject(el).Get('type', '') <> '' then Continue;
        if not TyOptVariantTags(lk.Node, tags) then Continue;
        list := tags.CommaText;
        Add(C, odkNoSeriesType, path + '[' + IntToStr(j) + ']',
          Format(rsTyOptDiagNoType, [path, j, list]));
      end;
    end;
  finally
    roots.Free;
    tags.Free;
  end;
end;

function TyOptDiagnose(const AText: string): TTyOptDiagArray;
var
  C: TCollector;
  opt: TTyChartOption;
  issues: TTyOptIssueArray;
  build: TTyChartBuild;
  bindings: TTySeriesBindingArray;
  i, resolved: Integer;
  msg, path: string;
  withAxes: Boolean;
begin
  C.Items := nil;
  C.Count := 0;
  C.Keys := nil;
  Result := nil;

  opt := TTyChartOption.Create;
  try
   try
    if not opt.SetOptionText(AText) then
    begin
      { EXACTLY ONE, and then stop. Everything below derives from a tree, and
        there is no tree. The message already carries the template-string hint
        when a pasted JS function is what broke it. }
      SetLength(C.Items, 1);
      C.Items[0].Kind := odkParseError;
      C.Items[0].Path := '';
      C.Items[0].Line := opt.Error.Line;
      C.Items[0].Col := opt.Error.Col;
      C.Items[0].Len := 0;
      C.Items[0].Text := opt.Error.Message;
      Exit(Copy(C.Items, 0, 1));
    end;

    { One pass over the text; every diagnostic below is positioned from it. }
    C.Keys := TyOptKeyPositions(AText);

    issues := TyOptValidate(opt);
    for i := 0 to High(issues) do
      case issues[i].Kind of
        oikUnknownOption:
          Add(C, odkUnknownOption, issues[i].Path,
            UnknownText(opt, issues[i].Path));
        oikBadEnumValue:
          Add(C, odkBadEnumValue, issues[i].Path,
            Format(rsTyOptDiagBadEnum,
              [issues[i].Path, issues[i].Value, issues[i].Allowed]));
      end;

    NoteUntypedElements(opt, C);

    { What the CHART cannot be made of, as opposed to what the option tree got
      wrong. The build is freed here whatever happens: this runs on a timer
      while somebody types, and one leaked build per keystroke inside a
      long-running IDE is a real leak. }
    build := TyBuildGrids(opt, TyRectF(0, 0, 400, 300));
    try
      bindings := TyBindSeries(opt, build);
      resolved := 0;
      for i := 0 to High(bindings) do
        if bindings[i].Resolved then Inc(resolved);
      for i := 0 to build.DiagnosticCount - 1 do
      begin
        msg := build.Diagnostic(i);
        path := TyOptPathInMessage(msg);
        { TWO PRODUCERS, ONE PROBLEM. An untyped series is noticed here and by
          the builder, in two different sentences about the same element. Two
          rows saying the same thing is how a diagnostics list stops being
          read. }
        if (path <> '') and AlreadyReported(C, odkNoSeriesType, path) then
          Continue;
        Add(C, odkBuild, path, msg);
      end;
    finally
      build.Free;
    end;

    { Nothing wrong -- which is worth saying, because a correct bar config
      draws axes and no bars today, and a developer told nothing concludes the
      editor lied.

      TWO THINGS THE FIRST VERSION GOT WRONG. It promised axes to charts that
      have none: a pie resolves with HasAxes False, and the sentence told the
      user it "draws its axes". And it was gated on `resolved > 0`, so a valid
      option with no series at all -- `{ xAxis: {}, yAxis: {} }` -- produced an
      EMPTY list, which is exactly the silence this row was invented to
      prevent. }
    if C.Count = 0 then
    begin
      withAxes := False;
      for i := 0 to High(bindings) do
        if bindings[i].Resolved and bindings[i].HasAxes then withAxes := True;
      if resolved = 0 then
        Add(C, odkNothingPaintsYet, '', rsTyOptDiagNoSeries)
      else if withAxes then
        Add(C, odkNothingPaintsYet, '', rsTyOptDiagNothingPaintsYet)
      else
        Add(C, odkNothingPaintsYet, '', rsTyOptDiagNoMarksAtAll);
    end;
   except
     { THE HEADER PROMISES THIS NEVER RAISES, and a promise a timer depends on
       has to be enforced rather than asserted. Whatever was collected before
       the failure is still worth showing. }
     on E: Exception do
       Add(C, odkBuild, '', E.Message);
   end;
  finally
    opt.Free;
  end;

  SortByPosition(C);

  { A CAP, because the count is otherwise unbounded: a misspelled option under
    a hundred-element series produces a hundred rows, and nobody reads the
    hundredth. The last row says what was dropped rather than the list simply
    stopping, which would read as "that is all of them". }
  if C.Count > cMaxRows then
  begin
    C.Items[cMaxRows - 1].Kind := odkBuild;
    C.Items[cMaxRows - 1].Path := '';
    C.Items[cMaxRows - 1].Line := 0;
    C.Items[cMaxRows - 1].Col := 0;
    C.Items[cMaxRows - 1].Len := 0;
    C.Items[cMaxRows - 1].Text :=
      Format(rsTyOptDiagMoreRows, [C.Count - cMaxRows + 1]);
    C.Count := cMaxRows;
  end;

  Result := Copy(C.Items, 0, C.Count);
end;

function TyOptFormat(const AText: string; out AOut: string): Boolean;
var opt: TTyChartOption;
begin
  AOut := AText;
  Result := False;
  opt := TTyChartOption.Create;
  try
    if not opt.SetOptionText(AText) then Exit;
    if opt.Root = nil then Exit;
    AOut := opt.Root.FormatJSON([foSingleLineArray], 2);
    Result := True;
  finally
    opt.Free;
  end;
end;

end.
