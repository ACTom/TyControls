unit test.advchart.stringidentity;
{$mode objfpc}{$H+}
{ [P2] WHICH NAMES ARE THE SAME NAME, held to upstream.

  Upstream keys names by JavaScript string identity: a node's id counts its
  name's repeats in a plain object (SeriesData.makeIdFromName), a collecting
  category axis interns names in a HashMap (OrdinalMeta). The port kept such
  names in sorted TStringLists, and a sorted TStringList compares through
  the locale: LazUTF8's UTF8CompareStr hands the first differing code point
  of the two strings to WideCompareStr, which on Windows calls them equal
  for a canonically equivalent pair (U+00C5 and U+212B) or two ignorable
  ones (U+FEFF, U+00AD) -- whatever follows. 'Åa' and 'Åb' were one name.

  TAdvChartStringIdentityOracleTest replays tools/advchart-oracle/
  string-identity.js: every row's id of a treemap and a sunburst
  (TyHierIds, the treemap's solved ids), and a collecting category axis'
  categories with every row's ordinal.

  TAdvChartStringIdentityGuardTest: every sorted, case-sensitive string list
  in the AdvChart sources compares bytes (UseLocale False) -- a list keyed
  by a name upstream keys by identity. }
interface

uses Classes, SysUtils, Math, fpjson, jsonparser, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Data, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Tree, tyControls.AdvChart.Treemap,
     tyControls.AdvChart.Sunburst;

type
  TAdvChartStringIdentityOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Miss(const ACase, AWhat: string);
    procedure Report;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryHierarchyIdIsUpstreams;
    procedure TestACollectingCategoryAxisInternsAsUpstream;
  end;

  TAdvChartStringIdentityGuardTest = class(TTestCase)
  published
    procedure TestEverySortedNameListComparesBytes;
  end;

implementation

function FixtureText(const AName: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

{ a name for the report: every byte past ASCII as its hex }
function Shown(const S: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if (Ord(S[i]) < 32) or (Ord(S[i]) > 126) then
      Result := Result + '<' + IntToHex(Ord(S[i]), 2) + '>'
    else
      Result := Result + S[i];
end;

procedure TAdvChartStringIdentityOracleTest.SetUp;
begin
  inherited SetUp;
  FRoot := GetJSON(FixtureText('advchart-string-identity.json'));
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartStringIdentityOracleTest.TearDown;
begin
  FRoot.Free;
  inherited TearDown;
end;

procedure TAdvChartStringIdentityOracleTest.Miss(const ACase, AWhat: string);
begin
  Inc(FBad);
  if FBad <= 25 then FReport := FReport + LineEnding + '  ' + ACase + ': ' + AWhat;
end;

procedure TAdvChartStringIdentityOracleTest.Report;
begin
  AssertTrue('something was compared', FCompared > 0);
  AssertEquals(Format('%d of %d disagree with upstream:%s', [FBad, FCompared, FReport]),
    0, FBad);
end;

procedure TAdvChartStringIdentityOracleTest.TestEveryHierarchyIdIsUpstreams;
var
  cases, want: TJSONArray;
  cs: TJSONObject;
  c, i: Integer;
  opt: TTyChartOption;
  ids: TTyStringArray;
  tm: TTyTreemapSolved;
  sb: TTySunburstSolved;
  isTm: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Strings['kind'] <> 'hier' then Continue;
    want := cs.Arrays['ids'];
    opt := TTyChartOption.Create;
    try
      AssertTrue(cs.Strings['id'] + ': the option parses',
        opt.SetOptionText(cs.Objects['option'].AsJSON));
      isTm := cs.Strings['seriesType'] = 'treemap';
      if isTm then
      begin
        tm := TyTreemapSolve(opt, 0, TyRectF(0, 0, 600, 400), 96);
        ids := TyHierIds(tm.Hier, tm.Series);
      end
      else
      begin
        sb := TySunburstSolve(opt, 0, TyRectF(0, 0, 600, 400), 96);
        ids := TyHierIds(sb.Hier, sb.Series);
      end;
      Inc(FCompared);
      if Length(ids) <> want.Count then
      begin
        Miss(cs.Strings['id'], Format('%d rows upstream, %d here', [want.Count, Length(ids)]));
        Continue;
      end;
      for i := 0 to want.Count - 1 do
      begin
        Inc(FCompared);
        if ids[i] <> want.Strings[i] then
          Miss(cs.Strings['id'], Format('row %d is "%s" upstream, "%s" here',
            [i, Shown(want.Strings[i]), Shown(ids[i])]));
        { the treemap's solved node carries the same id }
        if isTm and (i <= High(tm.Nodes)) then
        begin
          Inc(FCompared);
          if tm.Nodes[i].Id <> want.Strings[i] then
            Miss(cs.Strings['id'], Format('node %d is "%s" upstream, "%s" here',
              [i, Shown(want.Strings[i]), Shown(tm.Nodes[i].Id)]));
        end;
      end;
    finally
      opt.Free;
    end;
  end;
  Report;
end;

procedure TAdvChartStringIdentityOracleTest.TestACollectingCategoryAxisInternsAsUpstream;
var
  cases, cats, ords, row: TJSONArray;
  cs: TJSONObject;
  c, i, s: Integer;
  opt: TTyChartOption;
  b: TTyChartBuild;
  dims: TTySeriesDimArray;
  st: TTyDataStore;
  meta: TTyOrdinalMeta;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Strings['kind'] <> 'category' then Continue;
    cats := cs.Arrays['categories'];
    ords := cs.Arrays['ordinals'];
    opt := TTyChartOption.Create;
    b := nil;
    try
      AssertTrue(cs.Strings['id'] + ': the option parses',
        opt.SetOptionText(cs.Objects['option'].AsJSON));
      b := TyBuildGrids(opt, TyRectF(0, 0, 600, 400));
      meta := b.Axis('xAxis', 0).Categories;
      { the series intern into the axis' one list, in order }
      for s := 0 to ords.Count - 1 do
      begin
        dims := TySeriesCartesianDims(b.Grid(0).CartesianByIndex(0), s);
        st := TTyDataStore.Create;
        try
          for i := 0 to High(dims) do
          begin
            st.AddDimension(dims[i].Name, dims[i].Kind);
            if dims[i].Axis <> nil then st.UseOrdinalMeta(i, dims[i].Axis.Categories);
          end;
          TyFillSeriesStore(opt, s, dims, st);
          row := ords.Arrays[s];
          Inc(FCompared);
          if st.Count <> row.Count then
          begin
            Miss(cs.Strings['id'], Format('series %d: %d rows upstream, %d here',
              [s, row.Count, st.Count]));
            Continue;
          end;
          for i := 0 to row.Count - 1 do
          begin
            Inc(FCompared);
            if not SameValue(st.Get(0, i), row.Floats[i], 0) then
              Miss(cs.Strings['id'], Format('series %d row %d: ordinal %s upstream, %s here',
                [s, i, row.Items[i].AsJSON, FloatToStr(st.Get(0, i))]));
          end;
        finally
          st.Free;
        end;
      end;
      Inc(FCompared);
      if meta.Count <> cats.Count then
        Miss(cs.Strings['id'], Format('%d categories upstream, %d here', [cats.Count, meta.Count]))
      else
        for i := 0 to cats.Count - 1 do
        begin
          Inc(FCompared);
          if meta.CategoryAt(i) <> cats.Strings[i] then
            Miss(cs.Strings['id'], Format('category %d is "%s" upstream, "%s" here',
              [i, Shown(cats.Strings[i]), Shown(meta.CategoryAt(i))]));
        end;
    finally
      b.Free;
      opt.Free;
    end;
  end;
  Report;
end;

{ ==================== the guard ==================== }

procedure TAdvChartStringIdentityGuardTest.TestEverySortedNameListComparesBytes;
{ A SORTED TStringList with CaseSensitive compares through AnsiCompareStr
  unless UseLocale is False -- the locale compare that takes 'Åa' and 'Åb'
  as one name. Every `X.Sorted := True` in the AdvChart sources on a list
  that is not deliberately case-insensitive (CaseSensitive False: the
  image-list registry, a Pascal-side name) must say `X.UseLocale := False`
  within the few lines that set it up. }
var
  dir, src: string;
  files: TStringList;
  lines: TStringList;
  sr: TSearchRec;
  f, i, k, n: Integer;
  name, bad: string;
  p: Integer;
  found, insensitive: Boolean;
begin
  dir := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'source' + PathDelim;
  files := TStringList.Create;
  lines := TStringList.Create;
  bad := '';
  n := 0;
  try
    if FindFirst(dir + 'tyControls.AdvChart*.pas', faAnyFile, sr) = 0 then
    begin
      repeat
        files.Add(sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    files.Add('tyControls.AdvanceChart.pas');
    { and the include files the control's unit is split into [S1] }
    if FindFirst(dir + 'tyControls.AdvanceChart.*.inc', faAnyFile, sr) = 0 then
    begin
      repeat
        files.Add(sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    AssertTrue('the sources are found', files.Count > 20);
    for f := 0 to files.Count - 1 do
    begin
      lines.LoadFromFile(dir + files[f]);
      for i := 0 to lines.Count - 1 do
      begin
        src := Trim(lines[i]);
        p := Pos('.Sorted := True;', src);
        if (p <= 1) or (Copy(src, 1, 1) = '{') then Continue;
        name := Copy(src, 1, p - 1);
        Inc(n);
        found := False;
        insensitive := False;
        for k := Max(0, i - 8) to Min(lines.Count - 1, i + 4) do
        begin
          if Pos(name + '.UseLocale := False;', lines[k]) > 0 then found := True;
          if Pos(name + '.CaseSensitive := False;', lines[k]) > 0 then insensitive := True;
        end;
        if not found and not insensitive then
          bad := bad + LineEnding + '  ' + files[f] + ':' + IntToStr(i + 1) + ' ' + name;
      end;
    end;
    AssertTrue('sorted lists were found', n >= 10);
    AssertEquals('sorted name lists that compare through the locale:' + bad, '', bad);
  finally
    lines.Free;
    files.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartStringIdentityOracleTest);
  RegisterTest(TAdvChartStringIdentityGuardTest);
end.
