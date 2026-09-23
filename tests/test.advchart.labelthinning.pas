unit test.advchart.labelthinning;
{$mode objfpc}{$H+}
{ Which of an axis' labels are drawn -- held to upstream's own answers.

  tools/advchart-oracle/label-thinning.js runs the real ECharts 6.1 build and
  records, per case, axis and pass (the estimate on the raw grid rect, the
  pass that is drawn on the final one): a category axis' interval with every
  number that went into it -- the sampled labels' sizes, the band width, the
  two ratios -- and the labels upstream built, each with its flags (off the
  interval, a time axis' ragged end, its level, whether the estimate hid it)
  and its box with and without the text margin, placed by its matrix; and
  which of them it drew.

  FOUR LEVELS:
  1. the measurer is zrender's table, bit for bit;
  2. fed upstream's own sizes and band widths, the auto interval and the band
     width are upstream's to the bit, and so is the list of labels built;
  3. fed upstream's own boxes and flags, the end rules and hideOverlap keep
     exactly the labels upstream kept;
  4. the whole pipeline -- options read, labels formatted and placed by the
     port, two passes, the grid shrunk -- draws the labels upstream draws, at
     the stride upstream chose, on the rect upstream solved. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
     tyControls.AdvChart.Layout, tyControls.AdvChart.AxisLabels,
     tyControls.AdvChart.JsMath, tyControls.StrConsts, test.advchart.gridbounds;
type
  TAdvChartLabelThinningOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FM: ITyTextMeasurer;
    FOpt: TTyChartOption;
    FBuild: TTyChartBuild;
    FStores: array of TTyDataStore;
    FIndex: TTyAxisSeriesIndex;
    FSavedSource: TTyDateTimeNameSource;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure FreeRun;
    procedure RunCase(ACase: TJSONObject);
  published
    procedure TestTheMeasurerIsZrendersToTheBit;
    procedure TestTheAutoIntervalIsUpstreamsToTheBit;
    procedure TestTheBuiltListIsUpstreams;
    procedure TestTheEndRulesAndHideOverlapKeepWhatUpstreamKeeps;
    procedure TestEveryAxisDrawsTheLabelsUpstreamDraws;
    procedure TestEveryAxisDrawsTheFurnitureUpstreamDraws;
    { ---- what the cases do not reach ---- }
    procedure TestTheSevenPixelFloorHoldsBothWays;
    procedure TestABandOfNoLengthKeepsTheFirstAlone;
    procedure TestTheOrientedTestAsksBothBoxesAxes;
    procedure TestTheOrientedTestPullsInByTheThreshold;
    procedure TestTheOrientedTestAsksWhetherTheOtherIsEmpty;
    procedure TestTheTwoThresholdsAreTheirOwn;
    procedure TestANeighbourHiddenLastTimeGoes;
    procedure TestAHiddenEndCrowdsNothing;
    procedure TestTheOptionsAreReadAsUpstreamReadsThem;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-label-thinning.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Num(AObj: TJSONObject; const AKey: string): Double;
begin
  Result := FromHex(AObj.Strings[AKey]);
end;

function NumAt(AArr: TJSONArray; AIndex: Integer): Double;
begin
  Result := FromHex(AArr.Strings[AIndex]);
end;

function XYWHOf(AObj: TJSONObject): TTyXYWH;
begin
  Result := TyXYWH(Num(AObj, 'x'), Num(AObj, 'y'), Num(AObj, 'width'),
    Num(AObj, 'height'));
end;

function XYWHAt(AArr: TJSONArray): TTyXYWH;
begin
  Result := TyXYWH(NumAt(AArr, 0), NumAt(AArr, 1), NumAt(AArr, 2), NumAt(AArr, 3));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function IsDeferred(ACase: TJSONObject): Boolean;
begin
  Result := (ACase.Find('deferred') <> nil) and ACase.Booleans['deferred'];
end;

{ DEFERRED FOR THE PIPELINE ONLY: a case the port cannot build yet (a
  category axis narrowed by min / max, a grid box past its container) still
  carries upstream's own numbers, and the pure functions are held to them }
function PureSkipped(ACase: TJSONObject): Boolean;
var why: string;
begin
  Result := IsDeferred(ACase);
  if not Result then Exit;
  why := ACase.Get('why', '');
  if (Pos('the port does not narrow', why) > 0) or (Pos('grid box', why) > 0) then
    Result := False;
end;

function Same(A, B: Double): Boolean;
var qa, qb: QWord;
begin
  Move(A, qa, SizeOf(qa));
  Move(B, qb, SizeOf(qb));
  Result := qa = qb;
end;

function KindOf(AAxis: TJSONObject): TTyLabelAxisKind;
begin
  if AAxis.Strings['type'] = 'category' then Result := lakCategory
  else if AAxis.Strings['type'] = 'time' then Result := lakTime
  else Result := lakValue;
end;

function EndOptOf(AAxis: TJSONObject; const AKey: string): TTyAxisEndLabel;
var d: TJSONData;
begin
  Result := aelAuto;
  d := AAxis.Find(AKey);
  if (d <> nil) and (d.JSONType = jtBoolean) then
    if d.AsBoolean then Result := aelShow else Result := aelHide;
end;

{ upstream's interval: a number, or the string 'Infinity' }
function IntervalOf(ACat: TJSONObject): Double;
var d: TJSONData;
begin
  d := ACat.Find('interval');
  if d.JSONType = jtString then Result := Infinity
  else Result := d.AsFloat;
end;

function Joined(const AList: TStringList): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to AList.Count - 1 do
  begin
    if i > 0 then Result := Result + '|';
    Result := Result + AList[i];
  end;
end;

{ ==================== plumbing ==================== }

procedure TAdvChartLabelThinningOracleTest.SetUp;
var
  sl: TStringList;
  ratios: TJSONObject;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  ratios := TJSONObject(FRoot).Objects['ratios'];
  FM := TZrSsrMeasurer.Create(ratios.Arrays['ratio'], ratios.Integers['firstCode']);
  FOpt := TTyChartOption.Create;
  FIndex := TTyAxisSeriesIndex.Create;
  { the month names upstream writes, whatever this machine's locale }
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
end;

procedure TAdvChartLabelThinningOracleTest.FreeRun;
var i: Integer;
begin
  for i := 0 to High(FStores) do FStores[i].Free;
  FStores := nil;
  FreeAndNil(FBuild);
end;

procedure TAdvChartLabelThinningOracleTest.TearDown;
begin
  FreeRun;
  FreeAndNil(FIndex);
  FreeAndNil(FOpt);
  FM := nil;
  FreeAndNil(FRoot);
  TyDateTimeNameSource := FSavedSource;
  inherited TearDown;
end;

function TestTextStyle: TTyAxisTextStyle;
begin
  Result := Default(TTyAxisTextStyle);
  Result.FontName := 'sans-serif';
  Result.FontSizeLogical := 12;
  Result.FontWeight := 400;
  Result.EmphasisFontWeight := 700;
  Result.LabelMarginLogical := 8;
  Result.TickLengthLogical := 5;
  Result.NameGapLogical := 15;
  Result.NameFontName := 'sans-serif';
  Result.NameFontSizeLogical := 12;
  Result.NameFontWeight := 400;
end;

procedure TAdvChartLabelThinningOracleTest.RunCase(ACase: TJSONObject);
var
  bind: TTySeriesBindingArray;
  dims: TTySeriesDimArray;
  i, k: Integer;
  st: TTyDataStore;
begin
  FreeRun;
  AssertTrue(ACase.Strings['name'] + ' parses',
    FOpt.SetOptionText(ACase.Objects['option'].AsJSON));
  FBuild := TyBuildGrids(FOpt, TyRectF(0, 0, ACase.Integers['W'],
    ACase.Integers['H']));
  bind := TyBindSeries(FOpt, FBuild);
  SetLength(FStores, Length(bind));
  for i := 0 to High(bind) do
  begin
    st := TTyDataStore.Create;
    FStores[i] := st;
    if not bind[i].HasAxes then Continue;
    dims := TySeriesCartesianDims(bind[i].Cart, 0);
    for k := 0 to High(dims) do
    begin
      st.AddDimension(dims[k].Name, dims[k].Kind);
      if dims[k].Axis <> nil then st.UseOrdinalMeta(k, dims[k].Axis.Categories);
    end;
    TyFillSeriesStore(FOpt, i, dims, st);
  end;
  FIndex.Clear;
  TyIndexSeries(bind, FIndex);
  TyApplyAxisExtents(FOpt, FBuild, bind, FStores, nil, FIndex);
  TyLayoutGrids(FBuild, FOpt, FM, 96, TestTextStyle);
end;

{ ==================== 1. the measurer ==================== }

procedure TAdvChartLabelThinningOracleTest.TestTheMeasurerIsZrendersToTheBit;
var
  list: TJSONArray;
  m: TJSONObject;
  i, bad: Integer;
  w, h: Double;
  report: string;
begin
  list := TJSONObject(FRoot).Arrays['measure'];
  bad := 0;
  report := '';
  for i := 0 to list.Count - 1 do
  begin
    m := list.Objects[i];
    FM.MeasureLine(m.Strings['text'], 'sans-serif', m.Integers['px'], 400, w, h);
    if (w <> Num(m, 'width')) or (h <> Num(m, 'height')) then
    begin
      Inc(bad);
      if bad <= 10 then
        report := report + LineEnding + Format('  %s @%d: %s x %s upstream, %s x %s here',
          [m.Strings['text'], m.Integers['px'], m.Strings['widthText'],
           m.Strings['heightText'], Fmt(w), Fmt(h)]);
    end;
  end;
  AssertTrue('enough strings', list.Count >= 100);
  AssertEquals(IntToStr(bad) + ' widths differ:' + report, 0, bad);
end;

{ ==================== 2. the interval and the list ==================== }

procedure TAdvChartLabelThinningOracleTest.TestTheAutoIntervalIsUpstreamsToTheBit;
var
  cases, axes, passes, ws, hs: TJSONArray;
  cs, ax, ps, cat, smp: TJSONObject;
  c, a, p, k, bad, compared, infinite, overForty, turned: Integer;
  wa, ha: array of Double;
  ext0, ext1, len, unitSpan, got, want: Double;
  inverse: Boolean;
  report: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  infinite := 0;
  overForty := 0;
  turned := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if PureSkipped(cs) then Continue;
    axes := cs.Arrays['axes'];
    for a := 0 to axes.Count - 1 do
    begin
      ax := axes.Objects[a];
      if not (ax.Find('passes') is TJSONArray) then Continue;
      passes := ax.Arrays['passes'];
      for p := 0 to passes.Count - 1 do
      begin
        ps := passes.Objects[p];
        if not (ps.Find('category') is TJSONObject) then Continue;
        cat := ps.Objects['category'];
        if not cat.Booleans['auto'] then Continue;
        if not (cat.Find('samples') is TJSONObject) then Continue;
        { THE BAND WIDTH, from the pass' own pixel extent }
        ext0 := NumAt(cat.Arrays['extent'], 0);
        ext1 := NumAt(cat.Arrays['extent'], 1);
        inverse := ext0 > ext1;
        if inverse then len := ext0 else len := ext1;
        unitSpan := TyCategoryUnitSpan(len, ax.Integers['count'],
          ax.Booleans['onBand'], inverse);
        { THE INTERVAL, from upstream's own sampled sizes }
        smp := cat.Objects['samples'];
        ws := smp.Arrays['widths'];
        hs := smp.Arrays['heights'];
        SetLength(wa, ws.Count);
        SetLength(ha, hs.Count);
        for k := 0 to ws.Count - 1 do
        begin
          wa[k] := NumAt(ws, k);
          ha[k] := NumAt(hs, k);
        end;
        got := TyCategoryAutoInterval(wa, ha, Num(cat, 'unitSpan'),
          ax.Integers['axisRotate'], ax.Floats['rotate'], 7);
        want := IntervalOf(cat);
        Inc(compared);
        if IsInfinite(want) then Inc(infinite);
        if ax.Integers['count'] > 40 then Inc(overForty);
        if ax.Floats['rotate'] <> 0 then Inc(turned);
        if (TyCategorySampleStep(ax.Integers['count']) <> cat.Integers['sampleStep'])
          or (not Same(unitSpan, Num(cat, 'unitSpan')))
          or (IsInfinite(want) <> IsInfinite(got))
          or ((not IsInfinite(want)) and (got <> want)) then
        begin
          Inc(bad);
          if bad <= 20 then
            report := report + LineEnding + Format('  %s / %s%d %s: interval %s (upstream %s), band %s (upstream %s)',
              [cs.Strings['name'], ax.Strings['dim'], ax.Integers['index'],
               ps.Strings['kind'], Fmt(got), Fmt(want), Fmt(unitSpan),
               cat.Strings['unitSpanText']]);
        end;
      end;
    end;
  end;
  AssertTrue(Format('enough intervals (%d)', [compared]), compared >= 60);
  AssertTrue(Format('an infinite one (%d)', [infinite]), infinite >= 1);
  AssertTrue(Format('some sampled (%d)', [overForty]), overForty >= 2);
  AssertTrue(Format('some turned (%d)', [turned]), turned >= 4);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared) + ' differ:' + report, 0, bad);
end;

procedure TAdvChartLabelThinningOracleTest.TestTheBuiltListIsUpstreams;
var
  cases, axes, passes, labels: TJSONArray;
  cs, ax, ps, cat: TJSONObject;
  c, a, p, k, bad, compared, offStart: Integer;
  values: TTyIntegerArray;
  offs: TTyBoolArray;
  why, report: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  offStart := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if PureSkipped(cs) then Continue;
    axes := cs.Arrays['axes'];
    for a := 0 to axes.Count - 1 do
    begin
      ax := axes.Objects[a];
      if ax.Strings['type'] <> 'category' then Continue;
      if not (ax.Find('passes') is TJSONArray) then Continue;
      passes := ax.Arrays['passes'];
      for p := 0 to passes.Count - 1 do
      begin
        ps := passes.Objects[p];
        labels := ps.Arrays['labels'];
        if (labels.Count = 0) or not (ps.Find('category') is TJSONObject) then Continue;
        cat := ps.Objects['category'];
        TyCategoryBuiltList(ax.Arrays['ordinalExtent'].Integers[0],
          ax.Integers['count'], IntervalOf(cat), values, offs);
        Inc(compared);
        if ax.Arrays['ordinalExtent'].Integers[0] <> 0 then Inc(offStart);
        why := '';
        if Length(values) <> labels.Count then
          why := Format('%d built, upstream %d', [Length(values), labels.Count])
        else
          for k := 0 to High(values) do
            if (values[k] <> FromHex(labels.Objects[k].Strings['tick']))
              or (offs[k] <> labels.Objects[k].Booleans['offInterval']) then
            begin
              why := Format('label %d: %d%s, upstream %s%s', [k, values[k],
                BoolToStr(offs[k], ' off', ''),
                Fmt(FromHex(labels.Objects[k].Strings['tick'])),
                BoolToStr(labels.Objects[k].Booleans['offInterval'], ' off', '')]);
              Break;
            end;
        if why <> '' then
        begin
          Inc(bad);
          if bad <= 20 then
            report := report + LineEnding + Format('  %s / %s%d %s: %s',
              [cs.Strings['name'], ax.Strings['dim'], ax.Integers['index'],
               ps.Strings['kind'], why]);
        end;
      end;
    end;
  end;
  AssertTrue(Format('enough lists (%d)', [compared]), compared >= 60);
  AssertTrue(Format('some not starting at nought (%d)', [offStart]), offStart >= 1);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared) + ' differ:' + report, 0, bad);
end;

{ ==================== 3. the end rules and hideOverlap ==================== }

procedure TAdvChartLabelThinningOracleTest.TestTheEndRulesAndHideOverlapKeepWhatUpstreamKeeps;
var
  cases, axes, passes, labels, tr: TJSONArray;
  cs, ax, ps, lb: TJSONObject;
  c, a, p, k, j, bad, compared, hidden, byOverlap, turned: Integer;
  cands: TTyLabelCandidateArray;
  m: TTyMat2D;
  why, report: string;
  hide: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  hidden := 0;
  byOverlap := 0;
  turned := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if PureSkipped(cs) then Continue;
    axes := cs.Arrays['axes'];
    for a := 0 to axes.Count - 1 do
    begin
      ax := axes.Objects[a];
      if not (ax.Find('passes') is TJSONArray) then Continue;
      passes := ax.Arrays['passes'];
      hide := ax.Booleans['hideOverlap'];
      for p := 0 to passes.Count - 1 do
      begin
        ps := passes.Objects[p];
        labels := ps.Arrays['labels'];
        if labels.Count = 0 then Continue;
        SetLength(cands, labels.Count);
        for k := 0 to labels.Count - 1 do
        begin
          lb := labels.Objects[k];
          cands[k] := Default(TTyLabelCandidate);
          cands[k].Index := k;
          cands[k].OffInterval := lb.Booleans['offInterval'];
          cands[k].NotNice := lb.Booleans['notNice'];
          cands[k].SuggestIgnore := lb.Booleans['suggestIgnore'];
          cands[k].Priority := lb.Integers['priority'];
          if lb.Find('localRect') is TJSONArray then
          begin
            if lb.Find('transform') is TJSONArray then
            begin
              tr := lb.Arrays['transform'];
              for j := 0 to 5 do m[j] := NumAt(tr, j);
            end
            else
              m := TyMatIdentity;
            cands[k].Margin.LocalRect := XYWHAt(lb.Arrays['localRect']);
            cands[k].Margin.M := m;
            cands[k].Margin.Rect := TyRectApplyMat(cands[k].Margin.LocalRect, m);
            cands[k].Margin.AxisAligned := lb.Booleans['axisAligned'];
            cands[k].Bare.LocalRect := XYWHAt(lb.Arrays['bareLocalRect']);
            cands[k].Bare.M := m;
            cands[k].Bare.Rect := TyRectApplyMat(cands[k].Bare.LocalRect, m);
            cands[k].Bare.AxisAligned := cands[k].Margin.AxisAligned;
            cands[k].HasBox := True;
            if not cands[k].Margin.AxisAligned then Inc(turned);
          end;
        end;
        TyFixMinMaxLabelShow(cands, KindOf(ax), ax.Booleans['showAll'],
          EndOptOf(ax, 'showMinLabel'), EndOptOf(ax, 'showMaxLabel'), hide);
        if hide then TyHideOverlap(cands);
        Inc(compared);
        why := '';
        for k := 0 to labels.Count - 1 do
        begin
          lb := labels.Objects[k];
          if not lb.Booleans['shown'] then
          begin
            Inc(hidden);
            if not (lb.Booleans['offInterval'] or lb.Booleans['notNice']
              or lb.Booleans['suggestIgnore']) then Inc(byOverlap);
          end;
          if cands[k].Ignore = lb.Booleans['shown'] then
          begin
            why := Format('label %d (%s): %s here, %s upstream', [k,
              lb.Strings['text'], BoolToStr(not cands[k].Ignore, 'shown', 'hidden'),
              BoolToStr(lb.Booleans['shown'], 'shown', 'hidden')]);
            Break;
          end;
        end;
        if why <> '' then
        begin
          Inc(bad);
          if bad <= 20 then
            report := report + LineEnding + Format('  %s / %s%d %s: %s',
              [cs.Strings['name'], ax.Strings['dim'], ax.Integers['index'],
               ps.Strings['kind'], why]);
        end;
      end;
    end;
  end;
  AssertTrue(Format('enough passes (%d)', [compared]), compared >= 150);
  AssertTrue(Format('enough labels hidden (%d)', [hidden]), hidden >= 50);
  AssertTrue(Format('some for crowding alone (%d)', [byOverlap]), byOverlap >= 20);
  AssertTrue(Format('some turned off the axes (%d)', [turned]), turned >= 10);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared) + ' passes differ:' + report, 0, bad);
end;

{ ==================== 4. the pipeline ==================== }

function AxisFor(ABuild: TTyChartBuild; AGrid: Integer; const ADim: string;
  AIndex: Integer): TTyAxis;
var
  gb: TTyGridBuild;
  i: Integer;
begin
  Result := nil;
  gb := ABuild.Grid(AGrid);
  if ADim = 'x' then
  begin
    for i := 0 to gb.XAxisCount - 1 do
      if gb.XAxis(i).ComponentIndex = AIndex then Exit(gb.XAxis(i));
  end
  else
    for i := 0 to gb.YAxisCount - 1 do
      if gb.YAxis(i).ComponentIndex = AIndex then Exit(gb.YAxis(i));
end;

procedure TAdvChartLabelThinningOracleTest.TestEveryAxisDrawsTheLabelsUpstreamDraws;
var
  cases, axes, passes, labels: TJSONArray;
  cs, ax, ps, cat: TJSONObject;
  c, a, g, k, bad, compared, axesCompared, strides: Integer;
  axis: TTyAxis;
  spec: PTyAxisLayoutSpec;
  want, got: TStringList;
  wantRect: TTyXYWH;
  plot: TTyRectF;
  tol, iv: Double;
  report, why: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  axesCompared := 0;
  strides := 0;
  report := '';
  want := TStringList.Create;
  got := TStringList.Create;
  try
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      if IsDeferred(cs) then Continue;
      Inc(compared);
      try
        RunCase(cs);
      except
        on E: Exception do
        begin
          Inc(bad);
          report := report + LineEnding + '  ' + cs.Strings['name'] + ': '
            + E.ClassName + ': ' + E.Message;
          Continue;
        end;
      end;
      g := cs.Integers['grid'];
      tol := Num(cs, 'tol');
      why := '';
      { THE RECT the grid was solved to }
      wantRect := XYWHOf(cs.Objects['rect']);
      plot := FBuild.Grid(g).PlotRect;
      if (Abs(plot.Left - wantRect.X) > tol) or (Abs(plot.Top - wantRect.Y) > tol)
        or (Abs((plot.Right - plot.Left) - wantRect.W) > tol)
        or (Abs((plot.Bottom - plot.Top) - wantRect.H) > tol) then
        why := Format('rect %s,%s,%s,%s, upstream %s,%s,%s,%s', [Fmt(plot.Left),
          Fmt(plot.Top), Fmt(plot.Right - plot.Left), Fmt(plot.Bottom - plot.Top),
          cs.Objects['rectText'].Strings['x'], cs.Objects['rectText'].Strings['y'],
          cs.Objects['rectText'].Strings['width'], cs.Objects['rectText'].Strings['height']]);
      axes := cs.Arrays['axes'];
      for a := 0 to axes.Count - 1 do
      begin
        if why <> '' then Break;
        ax := axes.Objects[a];
        if not ax.Booleans['shown'] then Continue;
        if not (ax.Find('passes') is TJSONArray) then Continue;
        passes := ax.Arrays['passes'];
        ps := passes.Objects[passes.Count - 1];
        axis := AxisFor(FBuild, g, ax.Strings['dim'], ax.Integers['index']);
        if axis = nil then
        begin
          why := ax.Strings['dim'] + ' axis missing';
          Break;
        end;
        spec := FBuild.Grid(g).SpecFor(axis);
        Inc(axesCompared);
        { THE LABELS DRAWN, by their text, in order }
        want.Clear;
        got.Clear;
        labels := ps.Arrays['labels'];
        for k := 0 to labels.Count - 1 do
          if labels.Objects[k].Booleans['shown'] then
            want.Add(labels.Objects[k].Strings['text']);
        for k := 0 to High(spec^.Placements) do
          if spec^.Placements[k].Shown then got.Add(spec^.Placements[k].Text);
        if Joined(got) <> Joined(want) then
          why := Format('%s%d draws %s, upstream %s', [ax.Strings['dim'],
            ax.Integers['index'], Joined(got), Joined(want)]);
        { AND A CATEGORY AXIS' STRIDE, which the ticks walk }
        if (why = '') and (ax.Strings['type'] = 'category')
          and (ps.Find('category') is TJSONObject) then
        begin
          cat := ps.Objects['category'];
          iv := IntervalOf(cat);
          if not IsInfinite(iv) and (iv + 1 <= Length(spec^.Labels)) then
          begin
            Inc(strides);
            { Math.max(interval + 1, 1): a negative one is every label }
            if spec^.LabelStep <> Max(1, Trunc(iv) + 1) then
              why := Format('%s%d stride %d, upstream interval %s', [ax.Strings['dim'],
                ax.Integers['index'], spec^.LabelStep, Fmt(iv)]);
          end;
        end;
      end;
      if why <> '' then
      begin
        Inc(bad);
        if bad <= 30 then
          report := report + LineEnding + '  ' + cs.Strings['name'] + ': ' + why;
      end;
    end;
  finally
    got.Free;
    want.Free;
  end;
  AssertTrue(Format('enough cases (%d)', [compared]), compared >= 100);
  AssertTrue(Format('enough axes (%d)', [axesCompared]), axesCompared >= 180);
  AssertTrue(Format('enough strides (%d)', [strides]), strides >= 40);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared) + ' cases differ:' + report, 0, bad);
end;

{ THE FURNITURE: every tick mark, split line and split area of every axis'
  drawn pass -- the ticks it stands for and whether it is drawn exactly, where
  it goes within the case's tolerance. }
procedure TAdvChartLabelThinningOracleTest.TestEveryAxisDrawsTheFurnitureUpstreamDraws;
var
  cases, axes, passes, vals, drawn, coords, rects, r: TJSONArray;
  cs, ax, ps, rec: TJSONObject;
  c, a, g, k, bad, compared, closing, synced, areas, exactPlots: Integer;
  axis: TTyAxis;
  spec: PTyAxisLayoutSpec;
  tol, lo, hi, wlo, whi: Double;
  why, report: string;
  exactPlot: Boolean;
  xywh, want: TTyXYWH;

  function MarksDiffer(const AName: string; const AMarks: TTyAxisMarkArray;
    ARec: TJSONObject; ACheckDrawn: Boolean): string;
  var q: Integer;
  begin
    Result := '';
    vals := ARec.Arrays['values'];
    coords := ARec.Arrays['globalCoords'];
    drawn := ARec.Arrays['drawn'];
    if Length(AMarks) <> vals.Count then
      Exit(Format('%s: %d, upstream %d', [AName, Length(AMarks), vals.Count]));
    for q := 0 to vals.Count - 1 do
    begin
      if AMarks[q].Value <> NumAt(vals, q) then
        Exit(Format('%s %d: tick %s, upstream %s', [AName, q, Fmt(AMarks[q].Value),
          Fmt(NumAt(vals, q))]));
      { EXACT where the plot is upstream's to the bit; where rotated labels'
        boxes -- a unit off in their turn until the decomposed matrix is
        ported -- moved the shrink, within the case's tolerance }
      if (exactPlot and (AMarks[q].Coord <> NumAt(coords, q)))
        or (Abs(AMarks[q].Coord - NumAt(coords, q)) > tol) then
        Exit(Format('%s %d: at %s, upstream %s', [AName, q, Fmt(AMarks[q].Coord),
          Fmt(NumAt(coords, q))]));
      if ACheckDrawn and (AMarks[q].Drawn <> drawn.Booleans[q]) then
        Exit(Format('%s %d (tick %s): drawn %s, upstream %s', [AName, q,
          Fmt(AMarks[q].Value), BoolToStr(AMarks[q].Drawn, True),
          BoolToStr(drawn.Booleans[q], True)]));
    end;
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  closing := 0;
  synced := 0;
  areas := 0;
  exactPlots := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if IsDeferred(cs) then Continue;
    try
      RunCase(cs);
    except
      on E: Exception do
      begin
        Inc(bad);
        report := report + LineEnding + '  ' + cs.Strings['name'] + ': '
          + E.ClassName + ': ' + E.Message;
        Continue;
      end;
    end;
    g := cs.Integers['grid'];
    tol := Num(cs, 'tol');
    xywh := FBuild.Grid(g).PlotXYWH;
    want := XYWHOf(cs.Objects['rect']);
    exactPlot := (xywh.X = want.X) and (xywh.Y = want.Y) and (xywh.W = want.W)
      and (xywh.H = want.H);
    if exactPlot then Inc(exactPlots);
    axes := cs.Arrays['axes'];
    why := '';
    for a := 0 to axes.Count - 1 do
    begin
      if why <> '' then Break;
      ax := axes.Objects[a];
      if not ax.Booleans['shown'] then Continue;
      if not (ax.Find('passes') is TJSONArray) then Continue;
      passes := ax.Arrays['passes'];
      ps := passes.Objects[passes.Count - 1];
      if not (ps.Find('ticks') is TJSONObject) then Continue;
      axis := AxisFor(FBuild, g, ax.Strings['dim'], ax.Integers['index']);
      spec := FBuild.Grid(g).SpecFor(axis);
      Inc(compared);
      rec := ps.Objects['ticks'];
      why := MarksDiffer(ax.Strings['dim'] + ' ticks', spec^.TickMarks, rec, True);
      if why = '' then
      begin
        for k := 0 to rec.Arrays['drawn'].Count - 1 do
          if (not rec.Arrays['drawn'].Booleans[k]) and ax.Objects['axisTick'].Booleans['shown'] then
            Inc(synced);
        if rec.Booleans['onBand'] and (rec.Arrays['values'].Count > 0) then Inc(closing);
        why := MarksDiffer(ax.Strings['dim'] + ' split lines', spec^.SplitLineMarks,
          ps.Objects['splitLines'], True);
      end;
      if (why = '') and (ps.Objects['splitAreas'].Arrays['rects'].Count > 0) then
      begin
        { THE AREAS, each between two consecutive edges }
        Inc(areas);
        rects := ps.Objects['splitAreas'].Arrays['rects'];
        if Length(spec^.SplitAreaMarks) - 1 <> rects.Count then
          why := Format('%s areas: %d, upstream %d', [ax.Strings['dim'],
            Length(spec^.SplitAreaMarks) - 1, rects.Count])
        else
          for k := 0 to rects.Count - 1 do
          begin
            r := rects.Arrays[k];
            if ax.Strings['dim'] = 'x' then
            begin
              wlo := NumAt(r, 0);
              whi := NumAt(r, 0) + NumAt(r, 2);
            end
            else
            begin
              wlo := NumAt(r, 1);
              whi := NumAt(r, 1) + NumAt(r, 3);
            end;
            lo := Min(spec^.SplitAreaMarks[k].Coord, spec^.SplitAreaMarks[k + 1].Coord);
            hi := Max(spec^.SplitAreaMarks[k].Coord, spec^.SplitAreaMarks[k + 1].Coord);
            if (Abs(lo - Min(wlo, whi)) > tol) or (Abs(hi - Max(wlo, whi)) > tol) then
            begin
              why := Format('%s area %d: %s..%s, upstream %s..%s', [ax.Strings['dim'],
                k, Fmt(lo), Fmt(hi), Fmt(Min(wlo, whi)), Fmt(Max(wlo, whi))]);
              Break;
            end;
          end;
      end;
    end;
    if why <> '' then
    begin
      Inc(bad);
      if bad <= 30 then
        report := report + LineEnding + '  ' + cs.Strings['name'] + ': ' + why;
    end;
  end;
  AssertTrue(Format('enough axes (%d)', [compared]), compared >= 180);
  AssertTrue(Format('banded ones (%d)', [closing]), closing >= 30);
  AssertTrue(Format('ticks hidden with their labels (%d)', [synced]), synced >= 5);
  AssertTrue(Format('split areas (%d)', [areas]), areas >= 4);
  AssertTrue(Format('plots upstream''s to the bit (%d)', [exactPlots]),
    exactPlots >= 80);
  AssertEquals(IntToStr(bad) + ' cases differ:' + report, 0, bad);
end;

{ ==================== 5. what the cases do not reach ==================== }

{ A box of ALocal placed at (AX, AY) turned by ARotDeg, as zrender holds it. }
function Box(ALX, ALY, ALW, ALH, AX, AY, ARotDeg: Double): TTyLabelBox;
var deg: Double;
begin
  deg := ARotDeg;
  Result.LocalRect := TyXYWH(ALX, ALY, ALW, ALH);
  Result.M := TyMatLocal(AX, AY, deg * Pi / 180);
  Result.Rect := TyRectApplyMat(Result.LocalRect, Result.M);
  Result.AxisAligned := TyMatAxisAligned(Result.M);
end;

function Cand(AIndex: Integer; const ABox: TTyLabelBox): TTyLabelCandidate;
begin
  Result := Default(TTyLabelCandidate);
  Result.Index := AIndex;
  Result.Margin := ABox;
  Result.Bare := ABox;
  Result.HasBox := True;
  Result.Priority := 10;
end;

function ShownOf(const ACands: TTyLabelCandidateArray): string;
var k: Integer;
begin
  Result := '';
  for k := 0 to High(ACands) do
    if ACands[k].Ignore then Result := Result + '-' else Result := Result + '+';
end;

procedure TAdvChartLabelThinningOracleTest.TestTheSevenPixelFloorHoldsBothWays;
begin
  { EMPTY LABELS STILL TAKE SEVEN PIXELS each way: over a band of 2 that is
    three and a half -- an interval of 3 across an x axis and up a y one }
  AssertEquals('across', 3, TyCategoryAutoInterval([0], [0], 2, 0, 0, 7), 0);
  AssertEquals('up', 3, TyCategoryAutoInterval([0], [0], 2, 90, 0, 7), 0);
end;

procedure TAdvChartLabelThinningOracleTest.TestABandOfNoLengthKeepsTheFirstAlone;
var s: TTyAxisLayoutSpec;
begin
  { an axis of no length: the interval is infinite, and the stride the ticks
    walk passes every label but the first }
  s := Default(TTyAxisLayoutSpec);
  s.Side := asBottom;
  s.LabelKind := lakCategory;
  s.ShowLabels := True;
  s.Labels := TTyStringArray.Create('a', 'b', 'c');
  s.Positions := TTyDoubleArray.Create(0, 0.5, 1);
  s.FontName := 'sans-serif';
  s.FontSizeLogical := 12;
  s.FontWeight := 400;
  AssertEquals('every label but the first stepped over', 3,
    TyAxisLabelStep(s, TyRectF(10, 10, 10, 100), FM, 96));
end;

procedure TAdvChartLabelThinningOracleTest.TestTheOrientedTestAsksBothBoxesAxes;
var a, b: TTyLabelBox;
begin
  { A long thin label turned 45 degrees past the corner of a level one: on
    the level one's axes their shadows overlap, and only along the turned
    one's short side do they part. }
  a := Box(-5, -5, 10, 10, 0, 0, 0);
  b := Box(-20, -0.5, 40, 1, 9, 9, 45);
  AssertTrue('their rects meet', (b.Rect.X < 5) and (b.Rect.Y < 5));
  AssertFalse('the turned one parts them', TyLabelBoxesIntersect(a, b, 0.05));
  AssertFalse('either way round', TyLabelBoxesIntersect(b, a, 0.05));
end;

procedure TAdvChartLabelThinningOracleTest.TestTheOrientedTestPullsInByTheThreshold;
var a, b, c: TTyLabelBox;
  d: Double;
begin
  { Two squares turned alike, 0.05 into each other along their shared turn:
    each pulled in by the 0.05 threshold, they no longer meet; 0.15 in, they
    do. }
  d := 9.95;
  a := Box(-5, -5, 10, 10, 0, 0, 45);
  b := Box(-5, -5, 10, 10, d * TyJsCos(Pi / 4), -d * TyJsSin(Pi / 4), 45);
  AssertFalse('0.05 in: apart', TyObbIntersect(a, b, 0.05));
  d := 9.85;
  c := Box(-5, -5, 10, 10, d * TyJsCos(Pi / 4), -d * TyJsSin(Pi / 4), 45);
  AssertTrue('0.15 in: together', TyObbIntersect(a, c, 0.05));
end;

procedure TAdvChartLabelThinningOracleTest.TestTheOrientedTestAsksWhetherTheOtherIsEmpty;
var a, b: TTyLabelBox;
begin
  { A sliver 0.04 thin lying across a turned box: pulled in by the threshold
    it has no inside, and zrender calls that no intersection }
  a := Box(-5, -5, 10, 10, 0, 0, 45);
  b := Box(-5, -0.02, 10, 0.04, 0, 0, 45);
  AssertFalse('a sliver meets nothing', TyObbIntersect(a, b, 0.05));
end;

procedure TAdvChartLabelThinningOracleTest.TestTheTwoThresholdsAreTheirOwn;
var c: TTyLabelCandidateArray;
begin
  { Two level labels 0.15 into each other. The end rules pull each in by
    0.1 and find them apart; hideOverlap pulls in by 0.05 and finds them
    together. }
  SetLength(c, 2);
  c[0] := Cand(0, Box(0, 0, 10, 10, 0, 0, 0));
  c[1] := Cand(1, Box(0, 0, 10, 10, 9.85, 0, 0));
  TyFixMinMaxLabelShow(c, lakValue, False, aelAuto, aelAuto, False);
  AssertEquals('the ends stay', '++', ShownOf(c));
  TyFixMinMaxLabelShow(c, lakValue, False, aelAuto, aelAuto, True);
  AssertEquals('under hideOverlap too', '++', ShownOf(c));
  TyHideOverlap(c);
  AssertEquals('but hideOverlap drops the second', '+-', ShownOf(c));
end;

procedure TAdvChartLabelThinningOracleTest.TestANeighbourHiddenLastTimeGoes;
var c: TTyLabelCandidateArray;
begin
  { far apart, and the middle one hidden by the estimate: the end rules drop
    it whatever the boxes say }
  SetLength(c, 3);
  c[0] := Cand(0, Box(0, 0, 10, 10, 0, 0, 0));
  c[1] := Cand(1, Box(0, 0, 10, 10, 100, 0, 0));
  c[2] := Cand(2, Box(0, 0, 10, 10, 200, 0, 0));
  c[1].SuggestIgnore := True;
  TyFixMinMaxLabelShow(c, lakValue, False, aelAuto, aelAuto, False);
  AssertEquals('+-+', ShownOf(c));
end;

procedure TAdvChartLabelThinningOracleTest.TestAHiddenEndCrowdsNothing;
var c: TTyLabelCandidateArray;
begin
  { Two labels on top of each other: the min rule drops the first, and the
    max rule then finds nothing to weigh the second against -- a hidden
    label meets nothing -- so the second stays. }
  SetLength(c, 2);
  c[0] := Cand(0, Box(0, 0, 10, 10, 0, 0, 0));
  c[1] := Cand(1, Box(0, 0, 10, 10, 2, 0, 0));
  TyFixMinMaxLabelShow(c, lakValue, False, aelAuto, aelAuto, False);
  AssertEquals('-+', ShownOf(c));
end;

procedure TAdvChartLabelThinningOracleTest.TestTheOptionsAreReadAsUpstreamReadsThem;

  function X(const AAxis: string): TTyAxisLayoutSpec;
  var cs: TJSONObject;
  begin
    cs := TJSONObject(GetJSON('{"name": "a unit case", "W": 600, "H": 400, "grid": 0}'));
    try
      cs.Add('option', GetJSON('{"xAxis": ' + AAxis + ', "yAxis": {"type": "value"}}'));
      RunCase(cs);
    finally
      cs.Free;
    end;
    Result := FBuild.Grid(0).SpecFor(AxisFor(FBuild, 0, 'x', 0))^;
  end;

const
  cCat = '{"type": "category", "data": ["a", "b", "c"], "axisLabel": ';
begin
  { hideOverlap: JavaScript's truthiness }
  AssertTrue('true', X(cCat + '{"hideOverlap": true}}').HideOverlap);
  AssertTrue('1', X(cCat + '{"hideOverlap": 1}}').HideOverlap);
  AssertTrue('a string', X(cCat + '{"hideOverlap": "yes"}}').HideOverlap);
  AssertTrue('an object', X(cCat + '{"hideOverlap": {}}}').HideOverlap);
  AssertFalse('0', X(cCat + '{"hideOverlap": 0}}').HideOverlap);
  AssertFalse('the empty string', X(cCat + '{"hideOverlap": ""}}').HideOverlap);
  AssertFalse('absent', X(cCat + '{}}').HideOverlap);
  { interval: nought exactly shows all; a negative one does not }
  AssertTrue('interval 0', X(cCat + '{"interval": 0}}').ShowAllLabels);
  AssertFalse('interval -1', X(cCat + '{"interval": -1}}').ShowAllLabels);
  AssertFalse('interval auto', X(cCat + '{"interval": "auto"}}').ShowAllLabels);
  { and the kinds }
  AssertTrue('a category axis', X(cCat + '{}}').LabelKind = lakCategory);
  AssertTrue('a time axis', X('{"type": "time"}').LabelKind = lakTime);
  AssertTrue('a log axis is a value one', X('{"type": "log"}').LabelKind = lakValue);
end;

initialization
  RegisterTest(TAdvChartLabelThinningOracleTest);
end.
