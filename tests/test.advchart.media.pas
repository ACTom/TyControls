unit test.advchart.media;
{$mode objfpc}{$H+}
{ MEDIA QUERIES, HELD TO UPSTREAM [Batch 107, B12].

  The fixture (tools/advchart-oracle/media.js, the real ECharts 6.1 build)
  runs sequences of setOption calls and resizes over options with `media`
  and records after each step: the chart's size, the indices of the units
  the option manager merged last (_currentMediaIndices), the merged option
  as the author wrote it and upstream merged it (the raw layer GetOptionJson
  must give), every model's id / name / subType, what the chart draws --
  each series' rows, elements and bars, a tree's expand state, the grids'
  rects, the titles' frames, each legend's names and position -- and which
  series view each step kept. A query table gives applyMediaQuery's answer
  at sizes the cases do not reach (zero heights, fractions).

  Each case is replayed through SetOption and a resize of the control
  (SetBounds: the Resize asks the queries again), rendered after every step
  at 96 PPI with zrender's SSR text measure.

  Then by hand: a resize across a breakpoint snaps while the same change by
  a merge animates; the Option property keeps the host's text through a
  resize; the size asked is CSS px at the control's PPI; a unit with one id
  twice is dropped; parseRawOption's corners; a later merge that names no
  media keeps them. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.OptionMerge, tyControls.AdvChart.Media,
     tyControls.AdvChart.Title, tyControls.AdvChart.Legend,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TMdProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartMediaTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMdProbe;
    FBmp: TBGRABitmap;
    FRoot, FMeasure: TJSONData;
    FBad, FCompared: Integer;
    FReport: string;
    FKeysNow, FKeysBefore: array of string;
    procedure NewChart(AW, AH: Integer; AMode: TTyChartAnimationMode = camOff);
    procedure Draw;
    procedure Bad(const AWhere, AWhat: string);
    procedure Same(const AWhere: string; AExp, AGot: Double; ATol: Double = 0);
    procedure CmpJson(const APath: string; AExp, AGot: TJSONData);
    procedure CmpTree(const AWhere: string; AExp: TJSONObject);
    procedure CmpModels(const AWhere: string; AExp: TJSONObject);
    procedure CmpOut(const AWhere: string; AExp: TJSONObject);
    procedure CmpIndices(const AWhere: string; AExp: TJSONArray);
    function SeriesElements(ASeries: Integer): Integer;
    function TitleText: string;
    procedure Settle(AStart: Double);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestQueriesAsUpstream;
    procedure TestMediaAsUpstream;
    procedure TestAResizeSnapsAndAMergeAnimates;
    procedure TestThePropertyKeepsTheHostsText;
    procedure TestTheSizeIsCssPx;
    procedure TestAUnitWithADuplicateIdIsDropped;
    procedure TestParseRawOptionCorners;
    procedure TestAMergeWithoutMediaKeepsThem;
    procedure TestNoMediaNoMerge;
    procedure TestAQueryUpstreamThrowsOnNeverApplies;
  end;

implementation

const
  T0 = 1700000000000.0;
  T1 = T0 + 10000;

{ ==================== the probe ==================== }

function TMdProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TMdProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TMdProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ==================== NULs through fpjson ==================== }

{ fpjson decodes `\u0000` to nothing; upstream's ids are full of them. The
  escape becomes U+FDD0 for the parse and #0 again after it. }
function NulSafeJson(const AText: string): TJSONData;

  procedure Restore(AData: TJSONData);
  var i: Integer;
  begin
    case AData.JSONType of
      jtString:
        if Pos(#$EF#$B7#$90, AData.AsString) > 0 then
          AData.AsString := StringReplace(AData.AsString, #$EF#$B7#$90, #0, [rfReplaceAll]);
      jtArray, jtObject:
        for i := 0 to AData.Count - 1 do Restore(AData.Items[i]);
    end;
  end;

var
  s: string;
  i, n: Integer;
begin
  s := '';
  i := 1;
  n := Length(AText);
  while i <= n do
  begin
    if AText[i] = '\' then
    begin
      if (i + 5 <= n) and (Copy(AText, i, 6) = '\u0000') then
      begin
        s := s + #$EF#$B7#$90;
        Inc(i, 6);
        Continue;
      end;
      s := s + Copy(AText, i, 2);
      Inc(i, 2);
      Continue;
    end;
    s := s + AText[i];
    Inc(i);
  end;
  Result := GetJSON(s);
  Restore(Result);
end;

function Printable(const AText: string): string;
begin
  Result := StringReplace(AText, #0, '\0', [rfReplaceAll]);
end;

{ ==================== plumbing ==================== }

procedure TAdvChartMediaTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := nil;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-media.json');
    FRoot := NulSafeJson(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartMediaTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartMediaTest.NewChart(AW, AH: Integer; AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TMdProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  { the size the queries are asked about is CSS px at this PPI }
  FChart.Font.PixelsPerInch := 96;
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartMediaTest.Draw;
begin
  if (FBmp = nil) or (FBmp.Width <> FChart.Width) or (FBmp.Height <> FChart.Height) then
  begin
    FreeAndNil(FBmp);
    FBmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  end;
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
end;

procedure TAdvChartMediaTest.Settle(AStart: Double);
var t: Integer;
begin
  t := 16;
  while t <= 5000 do
  begin
    FChart.AnimNow := AStart + t;
    FChart.AnimTick(AStart + t);
    Inc(t, 250);
  end;
  Draw;
  AssertEquals('settled', 0, FChart.AnimClipCount);
end;

procedure TAdvChartMediaTest.Bad(const AWhere, AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + AWhere + ': ' + AWhat;
end;

procedure TAdvChartMediaTest.Same(const AWhere: string; AExp, AGot: Double;
  ATol: Double);
begin
  Inc(FCompared);
  if IsNan(AExp) and IsNan(AGot) then Exit;
  if (ATol = 0) and (AExp = AGot) then Exit;
  if (ATol > 0) and (Abs(AExp - AGot) <= ATol) then Exit;
  Bad(AWhere, Format('upstream %.17g, here %.17g', [AExp, AGot]));
end;

procedure TAdvChartMediaTest.CmpJson(const APath: string; AExp, AGot: TJSONData);
var
  i, j: Integer;
  eo, go: TJSONObject;
  ek, gk: TStringList;
begin
  Inc(FCompared);
  if AGot = nil then
  begin
    Bad(APath, 'missing here');
    Exit;
  end;
  if AExp.JSONType <> AGot.JSONType then
  begin
    Bad(APath, 'upstream ' + AExp.AsJSON + ', here ' + AGot.AsJSON);
    Exit;
  end;
  case AExp.JSONType of
    jtNull: ;
    jtBoolean:
      if AExp.AsBoolean <> AGot.AsBoolean then Bad(APath, 'upstream ' + AExp.AsJSON + ', here ' + AGot.AsJSON);
    jtNumber: Same(APath, AExp.AsFloat, AGot.AsFloat);
    jtString:
      if AExp.AsString <> AGot.AsString then
        Bad(APath, 'upstream "' + Printable(AExp.AsString) + '", here "' + Printable(AGot.AsString) + '"');
    jtArray:
      begin
        if AExp.Count <> AGot.Count then
        begin
          Bad(APath, Format('upstream %d items, here %d', [AExp.Count, AGot.Count]));
          Exit;
        end;
        for i := 0 to AExp.Count - 1 do
          CmpJson(APath + '[' + IntToStr(i) + ']', AExp.Items[i], AGot.Items[i]);
      end;
    jtObject:
      begin
        eo := TJSONObject(AExp);
        go := TJSONObject(AGot);
        ek := TStringList.Create;
        gk := TStringList.Create;
        try
          for i := 0 to eo.Count - 1 do ek.Add(eo.Names[i]);
          for i := 0 to go.Count - 1 do gk.Add(go.Names[i]);
          { the key order too: JavaScript's, deterministic }
          if ek.CommaText <> gk.CommaText then
          begin
            Bad(APath, 'keys: upstream [' + ek.CommaText + '], here [' + gk.CommaText + ']');
            Exit;
          end;
          for j := 0 to ek.Count - 1 do
            CmpJson(APath + '.' + ek[j], eo.Find(ek[j]), go.Find(ek[j]));
        finally
          ek.Free;
          gk.Free;
        end;
      end;
  end;
end;

procedure TAdvChartMediaTest.CmpTree(const AWhere: string; AExp: TJSONObject);
var
  got: TJSONData;
  g: TJSONObject;
  i: Integer;
  k: string;
begin
  got := NulSafeJson(FChart.GetOptionJson);
  try
    if not (got is TJSONObject) then
    begin
      Bad(AWhere, 'GetOptionJson is no object');
      Exit;
    end;
    g := TJSONObject(got);
    { the root's keys as a set: upstream orders them by its topological
      travel, which the port does not reproduce }
    for i := 0 to g.Count - 1 do
      if AExp.Find(g.Names[i]) = nil then Bad(AWhere + '.' + g.Names[i], 'only here');
    for i := 0 to AExp.Count - 1 do
    begin
      k := AExp.Names[i];
      CmpJson(AWhere + '.' + k, AExp.Items[i], g.Find(k));
    end;
  finally
    got.Free;
  end;
end;

procedure TAdvChartMediaTest.CmpModels(const AWhere: string; AExp: TJSONObject);
var
  i, j: Integer;
  mt: string;
  arr: TJSONArray;
  m: TJSONObject;
begin
  for i := 0 to AExp.Count - 1 do
  begin
    mt := AExp.Names[i];
    arr := TJSONArray(AExp.Items[i]);
    for j := 0 to arr.Count - 1 do
    begin
      Inc(FCompared);
      if arr.Items[j].JSONType = jtNull then
      begin
        if FChart.ComponentModelId(mt, j) <> '' then
          Bad(Format('%s.%s[%d]', [AWhere, mt, j]), 'a hole upstream, a model here');
        Continue;
      end;
      m := TJSONObject(arr.Items[j]);
      if FChart.ComponentModelId(mt, j) <> m.Get('id', '') then
        Bad(Format('%s.%s[%d].id', [AWhere, mt, j]), 'upstream "' + Printable(m.Get('id', ''))
          + '", here "' + Printable(FChart.ComponentModelId(mt, j)) + '"');
      if FChart.ComponentModelName(mt, j) <> m.Get('name', '') then
        Bad(Format('%s.%s[%d].name', [AWhere, mt, j]), 'upstream "' + Printable(m.Get('name', ''))
          + '", here "' + Printable(FChart.ComponentModelName(mt, j)) + '"');
      if FChart.ComponentModelSubType(mt, j) <> m.Get('sub', '') then
        Bad(Format('%s.%s[%d].sub', [AWhere, mt, j]), 'upstream "' + m.Get('sub', '')
          + '", here "' + FChart.ComponentModelSubType(mt, j) + '"');
    end;
    if FChart.ComponentModelId(mt, arr.Count) <> '' then
      Bad(Format('%s.%s[%d]', [AWhere, mt, arr.Count]), 'a model only here');
  end;
end;

procedure TAdvChartMediaTest.CmpIndices(const AWhere: string; AExp: TJSONArray);
var
  got: TTyMediaIndices;
  i: Integer;
  e, g: string;
begin
  Inc(FCompared);
  got := FChart.MediaIndices;
  e := '';
  for i := 0 to AExp.Count - 1 do e := e + IntToStr(AExp.Integers[i]) + ',';
  g := '';
  for i := 0 to High(got) do g := g + IntToStr(got[i]) + ',';
  if e <> g then Bad(AWhere + '.indices', 'upstream [' + e + '], here [' + g + ']');
end;

function TAdvChartMediaTest.SeriesElements(ASeries: Integer): Integer;
var
  i: Integer;
  lst: TTyPaintList;
begin
  Result := 0;
  lst := FChart.List;
  if lst = nil then Exit;
  for i := 0 to lst.Count - 1 do
    if lst.Element(i).Datum.SeriesIndex = ASeries then Inc(Result);
end;

procedure TAdvChartMediaTest.CmpOut(const AWhere: string; AExp: TJSONObject);
var
  arr, bars, b, c: TJSONArray;
  s, i, k, n: Integer;
  o: TJSONObject;
  w: string;
  lst: TTyPaintList;
  el: TTyChartElement;
  found, shown: Boolean;
  x0, y0, x1, y1: Double;
  tl: TTyTitleLayout;
  xywh: TTyXYWH;
  lg: TTyLegendLayout;
begin
  lst := FChart.List;
  { ---- the series ---- }
  arr := TJSONArray(AExp.Find('series'));
  for s := 0 to arr.Count - 1 do
  begin
    if arr.Items[s].JSONType = jtNull then
    begin
      Inc(FCompared);
      if SeriesElements(s) > 0 then
        Bad(Format('%s.series[%d]', [AWhere, s]), 'a hole upstream, elements here');
      Continue;
    end;
    o := TJSONObject(arr.Items[s]);
    w := Format('%s.series[%d]', [AWhere, s]);
    shown := o.Booleans['shown'];
    n := o.Integers['count'];
    if (n > 0) and (shown <> (SeriesElements(s) > 0)) then
      Bad(w + '.shown', BoolToStr(shown, 'shown', 'filtered') + ' upstream, '
        + IntToStr(SeriesElements(s)) + ' elements here');
    if shown then
    begin
      Inc(FCompared);
      if FChart.SeriesStore(s) = nil then Bad(w + '.count', 'no store here')
      else if FChart.SeriesStore(s).Count <> n then
        Bad(w + '.count', Format('upstream %d, here %d', [n, FChart.SeriesStore(s).Count]));
    end;
    { a tree's expand state, which is its data's }
    if o.Find('expanded') is TJSONArray then
    begin
      c := TJSONArray(o.Find('expanded'));
      for k := 0 to c.Count - 1 do
      begin
        Inc(FCompared);
        if FChart.TreeExpanded(s, k) <> c.Booleans[k] then
          Bad(Format('%s.expanded[%d]', [w, k]), 'upstream ' + BoolToStr(c.Booleans[k], True));
      end;
    end;
    bars := nil;
    if o.Find('bars') is TJSONArray then bars := TJSONArray(o.Find('bars'));
    if shown and (bars <> nil) then
      for i := 0 to bars.Count - 1 do
      begin
        found := False;
        el := Default(TTyChartElement);
        for k := 0 to lst.Count - 1 do
        begin
          el := lst.Element(k);
          if (el.Datum.SeriesIndex <> s) or (el.Datum.DataIndex <> i) then Continue;
          if not (el.Shape.Kind in [cskRect, cskRoundRect]) then Continue;
          found := True;
          Break;
        end;
        Inc(FCompared);
        if bars.Items[i].JSONType = jtNull then
        begin
          if found then Bad(Format('%s.bars[%d]', [w, i]), 'no bar upstream, one here');
          Continue;
        end;
        if not found then
        begin
          Bad(Format('%s.bars[%d]', [w, i]), 'no bar here');
          Continue;
        end;
        b := TJSONArray(bars.Items[i]);
        x0 := Min(b.Floats[0], b.Floats[0] + b.Floats[2]);
        x1 := Max(b.Floats[0], b.Floats[0] + b.Floats[2]);
        y0 := Min(b.Floats[1], b.Floats[1] + b.Floats[3]);
        y1 := Max(b.Floats[1], b.Floats[1] + b.Floats[3]);
        Same(Format('%s.bars[%d].left', [w, i]), x0, el.Shape.Bounds.Left, 1e-9);
        Same(Format('%s.bars[%d].right', [w, i]), x1, el.Shape.Bounds.Right, 1e-9);
        Same(Format('%s.bars[%d].top', [w, i]), y0, el.Shape.Bounds.Top, 1e-9);
        Same(Format('%s.bars[%d].bottom', [w, i]), y1, el.Shape.Bounds.Bottom, 1e-9);
      end;
  end;

  { ---- the grids: the plot rect ---- }
  arr := TJSONArray(AExp.Find('grids'));
  for i := 0 to arr.Count - 1 do
  begin
    if arr.Items[i].JSONType = jtNull then Continue;
    b := TJSONArray(arr.Items[i]);
    if (FChart.Build = nil) or (i >= FChart.Build.GridCount) then
    begin
      Bad(Format('%s.grids[%d]', [AWhere, i]), 'no grid here');
      Continue;
    end;
    xywh := FChart.Build.Grid(i).PlotXYWH;
    Same(Format('%s.grids[%d].x', [AWhere, i]), b.Floats[0], xywh.X, 1e-9);
    Same(Format('%s.grids[%d].y', [AWhere, i]), b.Floats[1], xywh.Y, 1e-9);
    Same(Format('%s.grids[%d].w', [AWhere, i]), b.Floats[2], xywh.W, 1e-9);
    Same(Format('%s.grids[%d].h', [AWhere, i]), b.Floats[3], xywh.H, 1e-9);
  end;

  { ---- the titles: their frames ---- }
  arr := TJSONArray(AExp.Find('titles'));
  for i := 0 to arr.Count - 1 do
  begin
    tl := FChart.TitleLayoutOf(i);
    Inc(FCompared);
    if arr.Items[i].JSONType = jtNull then
    begin
      if tl.Valid then Bad(Format('%s.titles[%d]', [AWhere, i]), 'no title upstream, one here');
      Continue;
    end;
    if not tl.Valid then
    begin
      Bad(Format('%s.titles[%d]', [AWhere, i]), 'no title here');
      Continue;
    end;
    b := TJSONArray(arr.Items[i]);
    Same(Format('%s.titles[%d].x', [AWhere, i]), b.Floats[0], tl.FrameX, 1e-9);
    Same(Format('%s.titles[%d].y', [AWhere, i]), b.Floats[1], tl.FrameY, 1e-9);
    Same(Format('%s.titles[%d].w', [AWhere, i]), b.Floats[2], tl.FrameW, 1e-9);
    Same(Format('%s.titles[%d].h', [AWhere, i]), b.Floats[3], tl.FrameH, 1e-9);
  end;

  { ---- the legends: the names each lists, where its group stands ---- }
  arr := TJSONArray(AExp.Find('legend'));
  if arr <> nil then
    for i := 0 to arr.Count - 1 do
    begin
      if arr.Items[i].JSONType = jtNull then Continue;
      o := TJSONObject(arr.Items[i]);
      Inc(FCompared);
      if i >= FChart.LegendLayoutCount then
      begin
        Bad(Format('%s.legend[%d]', [AWhere, i]), 'no legend here');
        Continue;
      end;
      lg := FChart.LegendLayout(i);
      c := o.Arrays['names'];
      if Length(lg.Items) <> c.Count then
      begin
        Bad(Format('%s.legend[%d]', [AWhere, i]), Format('upstream %s, here %d items',
          [c.AsJSON, Length(lg.Items)]));
        Continue;
      end;
      for k := 0 to c.Count - 1 do
        if lg.Items[k].Name <> c.Strings[k] then
          Bad(Format('%s.legend[%d][%d]', [AWhere, i, k]), 'upstream ' + c.Strings[k]
            + ', here ' + lg.Items[k].Name);
      { where its items stand: the content's extent, absolute }
      c := o.Arrays['content'];
      Same(Format('%s.legend[%d].x', [AWhere, i]), c.Floats[0], lg.Content.Left, 1e-9);
      Same(Format('%s.legend[%d].y', [AWhere, i]), c.Floats[1], lg.Content.Top, 1e-9);
      Same(Format('%s.legend[%d].w', [AWhere, i]), c.Floats[2], lg.Content.Right - lg.Content.Left, 1e-9);
      Same(Format('%s.legend[%d].h', [AWhere, i]), c.Floats[3], lg.Content.Bottom - lg.Content.Top, 1e-9);
    end;
end;

function TAdvChartMediaTest.TitleText: string;
var d: TJSONData;
begin
  Result := '';
  d := GetJSON(FChart.GetOptionJson);
  try
    if (d is TJSONObject) and (TJSONObject(d).Find('title') is TJSONArray)
      and (TJSONArray(TJSONObject(d).Find('title')).Count > 0)
      and (TJSONArray(TJSONObject(d).Find('title')).Items[0] is TJSONObject) then
      Result := TJSONObject(TJSONArray(TJSONObject(d).Find('title')).Items[0]).Get('text', '');
  finally
    d.Free;
  end;
end;

{ ==================== the fixture ==================== }

procedure TAdvChartMediaTest.TestQueriesAsUpstream;
var
  arr: TJSONArray;
  o: TJSONObject;
  q: TJSONData;
  i: Integer;
begin
  arr := TJSONObject(FRoot).Arrays['queries'];
  AssertTrue('the table is there', arr.Count > 10);
  for i := 0 to arr.Count - 1 do
  begin
    o := TJSONObject(arr.Items[i]);
    q := GetJSON(o.Strings['query']);
    try
      Inc(FCompared);
      if TyMediaQueryApplies(q, o.Floats['w'], o.Floats['h']) <> o.Booleans['applies'] then
        Bad(Format('%s at %g x %g', [o.Strings['query'], o.Floats['w'], o.Floats['h']]),
          'upstream ' + BoolToStr(o.Booleans['applies'], True));
    finally
      q.Free;
    end;
  end;
  AssertEquals(Format('%d of %d queries differ:%s', [FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartMediaTest.TestMediaAsUpstream;
var
  cases, steps, views, prevViews: TJSONArray;
  cs, st: TJSONObject;
  ci, si, s: Integer;
  where, kind: string;
  upSame, hereSame: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  AssertTrue('the cases are there', cases.Count >= 40);
  for ci := 0 to cases.Count - 1 do
  begin
    cs := TJSONObject(cases.Items[ci]);
    NewChart(cs.Integers['w'], cs.Integers['h']);
    steps := cs.Arrays['steps'];
    prevViews := nil;
    FKeysBefore := nil;
    for si := 0 to steps.Count - 1 do
    begin
      st := TJSONObject(steps.Items[si]);
      kind := st.Strings['kind'];
      where := Format('%s step %d (%s)', [cs.Strings['id'], si, kind]);
      if kind = 'set' then
      begin
        if st.Find('opts') is TJSONString then
          AssertTrue(where + ': the options form takes it',
            FChart.SetOption(st.Strings['text'], st.Strings['opts']))
        else
          FChart.SetOption(st.Strings['text'], st.Booleans['notMerge']);
        AssertEquals(where + ': the option is taken', '', FChart.OptionError);
      end
      else if kind = 'resize' then
        FChart.SetBounds(0, 0, st.Integers['w'], st.Integers['h'])
      else if TJSONObject(st.Find('payload')).Strings['type'] = 'treeExpandAndCollapse' then
        FChart.TreeToggle(TJSONObject(st.Find('payload')).Get('seriesIndex', 0),
          TJSONObject(st.Find('payload')).Integers['dataIndex'])
      else
        FChart.DispatchAction(st.Find('payload').AsJSON);
      Inc(FCompared);
      if (FChart.ClientWidth <> st.Integers['w']) or (FChart.ClientHeight <> st.Integers['h']) then
        Bad(where, Format('the size is %d x %d here', [FChart.ClientWidth, FChart.ClientHeight]));
      Draw;
      CmpIndices(where, st.Arrays['indices']);
      CmpTree(where + ' tree', TJSONObject(st.Find('tree')));
      CmpModels(where + ' models', TJSONObject(st.Find('models')));
      CmpOut(where + ' out', TJSONObject(st.Find('out')));
      { THE VIEWS: upstream kept a series' view across the step exactly
        where the port's pairing key -- model id and type -- stayed }
      views := st.Arrays['views'];
      SetLength(FKeysNow, views.Count);
      for s := 0 to views.Count - 1 do FKeysNow[s] := FChart.SeriesViewKey(s);
      if prevViews <> nil then
        for s := 0 to Min(views.Count, prevViews.Count) - 1 do
        begin
          if (views.Items[s].JSONType = jtNull) or (prevViews.Items[s].JSONType = jtNull) then Continue;
          if s > High(FKeysBefore) then Continue;
          Inc(FCompared);
          upSame := views.Integers[s] = prevViews.Integers[s];
          hereSame := FKeysNow[s] = FKeysBefore[s];
          if upSame <> hereSame then
            Bad(Format('%s views[%d]', [where, s]), 'upstream ' + BoolToStr(upSame, 'kept', 'new')
              + ', here ' + BoolToStr(hereSame, 'kept', 'new'));
        end;
      prevViews := views;
      FKeysBefore := Copy(FKeysNow);
    end;
  end;
  AssertEquals(Format('%d of %d comparisons differ:%s', [FBad, FCompared, FReport]), 0, FBad);
  AssertTrue('compared enough', FCompared > 3000);
end;

{ ==================== by hand ==================== }

const
  cBreak = '{"animation":true,"animationDurationUpdate":1000,'
    + '"xAxis":{"type":"category","data":["a","b","c","d"]},"yAxis":{},'
    + '"series":[{"type":"bar","data":[1,2,3,4]}],'
    + '"media":[{"query":{"maxWidth":500},"option":{"grid":{"left":150}}}]}';

{ UPSTREAM'S RESIZE UPDATES WITH duration 0: the grid that a breakpoint
  moved is where it goes at once. The same change by a merge is an update
  that animates. }
procedure TAdvChartMediaTest.TestAResizeSnapsAndAMergeAnimates;
begin
  NewChart(600, 400, camAlways);
  FChart.SetOption(cBreak, True);
  Draw;
  Settle(T0);
  FChart.AnimNow := T1;
  FChart.SetBounds(0, 0, 450, 400);
  AssertEquals('the unit applies', 1, Length(FChart.MediaIndices));
  Draw;
  AssertEquals('a resize across a breakpoint snaps', 0, FChart.AnimClipCount);
  AssertEquals('the grid moved', 150, FChart.Build.Grid(0).PlotXYWH.X, 1e-9);
  { the same grid by a merge, at a size with no unit }
  NewChart(600, 400, camAlways);
  FChart.SetOption(cBreak, True);
  Draw;
  Settle(T0);
  FChart.AnimNow := T1;
  AssertTrue(FChart.MergeOption('{"grid":{"left":150}}'));
  Draw;
  AssertTrue('a merge animates', FChart.AnimClipCount > 0);
end;

{ THE PROPERTY IS THE HOST'S TEXT: a resize merges units into the models,
  not into the declaration -- saved, it would lose its media. The same text
  again is no change. }
procedure TAdvChartMediaTest.TestThePropertyKeepsTheHostsText;
var text: string;
begin
  NewChart(600, 400);
  text := '{"animation":false,"title":{"text":"base"},'
    + '"media":[{"query":{"maxWidth":500},"option":{"title":{"text":"narrow"}}},'
    + '{"option":{"title":{"text":"wide"}}}]}';
  FChart.Option := text;
  AssertEquals('the default', 'wide', TitleText);
  FChart.SetBounds(0, 0, 400, 400);
  AssertEquals('the unit', 'narrow', TitleText);
  AssertEquals('the property is the text written', text, FChart.Option);
  FChart.Option := text;
  AssertEquals('the same text is no change', 'narrow', TitleText);
  FChart.SetBounds(0, 0, 600, 400);
  AssertEquals('and the default again', 'wide', TitleText);
end;

{ THE SIZE ASKED IS CSS px: the client area at the control's PPI scaled to
  96 -- 1000 device px at 192 PPI is 500 }
procedure TAdvChartMediaTest.TestTheSizeIsCssPx;
const
  cText = '{"animation":false,"media":['
    + '{"query":{"maxWidth":500,"minWidth":500},"option":{"title":{"text":"five hundred"}}},'
    + '{"option":{"title":{"text":"other"}}}]}';
begin
  NewChart(1000, 800);
  FChart.Font.PixelsPerInch := 192;
  FChart.SetOption(cText, True);
  AssertEquals('1000 px at 192 PPI is 500 CSS px', 'five hundred', TitleText);
  FChart.SetBounds(0, 0, 1001, 800);
  AssertEquals('1001 px is 500.5', 'other', TitleText);
  FChart.Font.PixelsPerInch := 96;
  FChart.SetBounds(0, 0, 500, 800);
  AssertEquals('500 px at 96 PPI', 'five hundred', TitleText);
end;

{ A UNIT WITH ONE ID TWICE IN A MAIN TYPE is dropped when it is read:
  upstream asserts when it merges it; the indices are of the units kept }
procedure TAdvChartMediaTest.TestAUnitWithADuplicateIdIsDropped;
var idx: TTyMediaIndices;
begin
  NewChart(600, 400);
  FChart.SetOption('{"animation":false,"media":['
    + '{"query":{"minWidth":1},"option":{"series":[{"id":"a","type":"bar"},{"id":"a","type":"line"}]}},'
    + '{"query":{"minWidth":1},"option":{"title":{"text":"kept"}}}]}', True);
  AssertEquals('taken', '', FChart.OptionError);
  idx := FChart.MediaIndices;
  AssertEquals('one unit applies', 1, Length(idx));
  AssertEquals('the second, now the first', 0, idx[0]);
  AssertEquals('kept', 'kept', TitleText);
  AssertEquals('no series came in', '', FChart.ComponentModelId('series', 0));
end;

function Compact(AData: TJSONData): string;
begin
  Result := AData.FormatJSON([foSingleLineArray, foSingleLineObject, foSkipWhiteSpace]);
end;

procedure TAdvChartMediaTest.TestParseRawOptionCorners;
var
  raw: TJSONObject;
  mset: TTyMediaSet;

  procedure Parse(const AText: string);
  begin
    FreeAndNil(raw);
    TyMediaSetFree(mset);
    raw := TJSONObject(GetJSON(AText));
    TyParseRawOption(raw, mset);
  end;

begin
  raw := nil;
  mset := Default(TTyMediaSet);
  try
    { baseOption: the root's other keys are not read; a timeline beside it
      goes into a base without one }
    Parse('{"baseOption":{"grid":{}},"title":{},"timeline":{"axisType":"category"},'
      + '"media":[{"query":{"minWidth":1},"option":{"grid":{"left":1}}},{"option":{"title":{}}}]}');
    AssertEquals('{"grid":{},"timeline":{"axisType":"category"}}', Compact(raw));
    AssertEquals(1, Length(mset.Units));
    AssertNotNull('the default', mset.DefaultOpt);
    { a base with a timeline keeps its own }
    Parse('{"baseOption":{"timeline":{"show":false}},"timeline":{"show":true}}');
    AssertEquals('{"timeline":{"show":false}}', Compact(raw));
    { a falsy timeline in the base is the root's -- undefined, gone }
    Parse('{"baseOption":{"timeline":0}}');
    AssertEquals('{}', Compact(raw));
    { a baseOption that is no object: an empty base }
    Parse('{"baseOption":"x","grid":{}}');
    AssertEquals('{}', Compact(raw));
    { no baseOption: media and options taken off the root }
    Parse('{"grid":{},"media":[],"options":[1]}');
    AssertEquals('{"grid":{}}', Compact(raw));
    AssertEquals('an empty list', 0, Length(mset.Units));
    { a falsy media stays, a root key like any other; so do options with no
      media or timeline to read }
    Parse('{"media":0,"options":0}');
    AssertEquals('{"media":0,"options":0}', Compact(raw));
    { a media that is no array: nothing read, but it goes }
    Parse('{"media":{"query":{},"option":{}}}');
    AssertEquals('{}', Compact(raw));
    AssertEquals(0, Length(mset.Units));
    AssertNull(mset.DefaultOpt);
    { an option that is no object merges as nothing }
    Parse('{"media":[{"query":{"minWidth":1},"option":5}]}');
    AssertEquals(1, Length(mset.Units));
    AssertEquals('{}', Compact(mset.Units[0].Option));
  finally
    raw.Free;
    TyMediaSetFree(mset);
  end;
end;

{ A MERGE NAMING NO MEDIA keeps the list and the default, forgets the
  indices, and merges what applies over its base again }
procedure TAdvChartMediaTest.TestAMergeWithoutMediaKeepsThem;
begin
  NewChart(400, 400);
  FChart.SetOption('{"animation":false,"title":{"text":"base"},'
    + '"media":[{"query":{"maxWidth":500},"option":{"title":{"text":"narrow"}}}]}', True);
  AssertEquals('narrow', TitleText);
  AssertTrue(FChart.MergeOption('{"title":{"text":"merged"}}'));
  AssertEquals('the unit over the merge', 'narrow', TitleText);
  FChart.SetBounds(0, 0, 600, 400);
  AssertEquals('none applies, no default: nothing undone', 'narrow', TitleText);
  AssertEquals(0, Length(FChart.MediaIndices));
  AssertTrue(FChart.MergeOption('{"title":{"text":"merged again"}}'));
  AssertEquals('none applies: the merge stands', 'merged again', TitleText);
  FChart.SetBounds(0, 0, 500, 400);
  AssertEquals('the list is still there', 'narrow', TitleText);
  { a notMerge forgets it }
  FChart.SetOption('{"animation":false,"title":{"text":"fresh"}}', True);
  FChart.SetBounds(0, 0, 450, 400);
  AssertEquals('no media after a notMerge', 'fresh', TitleText);
end;

{ AN OPTION WITHOUT MEDIA merges nothing on a resize: the tree is the same
  object, its text unchanged }
procedure TAdvChartMediaTest.TestNoMediaNoMerge;
var before: string;
begin
  NewChart(600, 400);
  FChart.SetOption('{"animation":false,"title":{"text":"t"},"grid":{"left":10}}', True);
  before := FChart.GetOptionJson;
  FChart.SetBounds(0, 0, 300, 200);
  AssertEquals(before, FChart.GetOptionJson);
  AssertFalse('nothing to ask', FChart.MediaRecheck);
  AssertEquals(0, Length(FChart.MediaIndices));
end;

{ A QUERY UPSTREAM THROWS ON -- zrender's each walks a non-empty array or
  string by index, and an index has no `match` -- never applies here; the
  empty ones walk nothing and apply }
procedure TAdvChartMediaTest.TestAQueryUpstreamThrowsOnNeverApplies;

  function Applies(const AQuery: string): Boolean;
  var q: TJSONData;
  begin
    q := GetJSON(AQuery);
    try
      Result := TyMediaQueryApplies(q, 600, 400);
    finally
      q.Free;
    end;
  end;

begin
  AssertFalse('an array', Applies('[{"minWidth":1}]'));
  AssertFalse('a string', Applies('"minWidth"'));
  AssertFalse('an object with a length', Applies('{"length":2,"minWidth":1}'));
  AssertTrue('an empty array', Applies('[]'));
  AssertTrue('an empty string', Applies('""'));
  AssertTrue('a length of nought', Applies('{"length":0,"minWidth":9000}'));
end;

initialization
  RegisterTest(TAdvChartMediaTest);
end.
