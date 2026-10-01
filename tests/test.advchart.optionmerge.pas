unit test.advchart.optionmerge;
{$mode objfpc}{$H+}
{ A MERGE setOption, HELD TO UPSTREAM [Batch 95, A10 / MG1].

  The fixture (tools/advchart-oracle/option-merge.js, the real ECharts 6.1
  build) runs sequences of setOption calls -- merges, notMerges, a few
  actions in between -- and records after each step:

    the merged option as the author wrote it and upstream merged it (the
      raw layer: no theme, no defaults), which GetOptionJson must give back
      -- every component main type an array over its indices, a hole null,
      objects in JavaScript's key order; a dataZoom's four range keys are
      left out (the control keeps an action's window outside its tree);
    every model's id, name and subType (ids with their NULs);
    what the chart draws from it: each series' row count, whether the
      legend shows it, its bars, a graph's roamed centre and zoom, the grids'
      rects, the titles' frames, the dataZoom windows;
    which series view each step kept -- the update pairing.

  Each case is replayed through the control's SetOption / MergeOption,
  DispatchAction, DispatchDataZoom and GraphDispatchRoam, rendered after
  every step with zrender's SSR text measure (600 x 400).

  Then hand tests: the Option property is a declaration (the same text is
  no change) while SetOption(text, True) is upstream's notMerge; after a
  merge the property holds the merged option; a refused merge changes
  nothing; the first merge is an init; a merge is an update (a renamed
  series keeps its view and tweens from where it was, a notMerge under the
  new name enters afresh); a type change keeps the model's name. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.OptionMerge, tyControls.AdvChart.Graph,
     tyControls.AdvChart.DataZoom, tyControls.AdvChart.Title, tyControls.AdvChart.Series,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimView,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TOmProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartOptionMergeTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TOmProbe;
    FBmp: TBGRABitmap;
    FRoot, FMeasure: TJSONData;
    FBad, FCompared: Integer;
    FReport: string;
    procedure NewChart;
    procedure Draw;
    procedure Bad(const AWhere, AWhat: string);
    procedure Same(const AWhere: string; AExp, AGot: Double; ATol: Double = 0);
    procedure CmpJson(const APath: string; AExp, AGot: TJSONData; ADz: Boolean);
    procedure CmpTree(const AWhere: string; AExp: TJSONObject);
    procedure CmpModels(const AWhere: string; AExp: TJSONObject);
    procedure CmpOut(const AWhere: string; AExp: TJSONObject; ACompareFill: Boolean);
    procedure RunStep(AStep: TJSONObject);
    function SeriesElements(ASeries: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTablesAreUpstreams;
    procedure TestMergesAsUpstream;
    procedure TestThePropertyIsADeclaration;
    procedure TestThePropertyHoldsTheMergedOption;
    procedure TestARefusedMergeChangesNothing;
    procedure TestTheFirstMergeIsAnInit;
    procedure TestAMergeIsAnUpdate;
    procedure TestATypeChangeKeepsTheName;
  end;

implementation

const
  cW = 600;
  cH = 400;
  T0 = 1700000000000.0;
  T1 = T0 + 10000;

{ ==================== the probe ==================== }

function TOmProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TOmProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TOmProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ==================== NULs through fpjson ==================== }

{ fpjson decodes `\u0000` to nothing; the ids upstream makes are full of
  them. The escape becomes U+FDD0 for the parse and #0 again after it. }
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
        { the noncharacter itself, as its UTF-8 bytes }
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

procedure TAdvChartOptionMergeTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-option-merge.json');
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

procedure TAdvChartOptionMergeTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartOptionMergeTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TOmProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartOptionMergeTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartOptionMergeTest.Bad(const AWhere, AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + AWhere + ': ' + AWhat;
end;

procedure TAdvChartOptionMergeTest.Same(const AWhere: string; AExp, AGot: Double;
  ATol: Double);
begin
  Inc(FCompared);
  if IsNan(AExp) and IsNan(AGot) then Exit;
  if (ATol = 0) and (AExp = AGot) then Exit;
  if (ATol > 0) and (Abs(AExp - AGot) <= ATol) then Exit;
  Bad(AWhere, Format('upstream %.17g, here %.17g', [AExp, AGot]));
end;

{ the four keys of a dataZoom the control keeps outside its tree }
function DzRangeKey(const AKey: string): Boolean;
begin
  Result := (AKey = 'start') or (AKey = 'end') or (AKey = 'startValue') or (AKey = 'endValue');
end;

procedure TAdvChartOptionMergeTest.CmpJson(const APath: string; AExp, AGot: TJSONData;
  ADz: Boolean);
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
          CmpJson(APath + '[' + IntToStr(i) + ']', AExp.Items[i], AGot.Items[i], False);
      end;
    jtObject:
      begin
        eo := TJSONObject(AExp);
        go := TJSONObject(AGot);
        ek := TStringList.Create;
        gk := TStringList.Create;
        try
          for i := 0 to eo.Count - 1 do
            if not (ADz and DzRangeKey(eo.Names[i])) then ek.Add(eo.Names[i]);
          for i := 0 to go.Count - 1 do
            if not (ADz and DzRangeKey(go.Names[i])) then gk.Add(go.Names[i]);
          { THE KEY ORDER TOO: upstream's is JavaScript's, deterministic }
          if ek.CommaText <> gk.CommaText then
          begin
            Bad(APath, 'keys: upstream [' + ek.CommaText + '], here [' + gk.CommaText + ']');
            Exit;
          end;
          for j := 0 to ek.Count - 1 do
            CmpJson(APath + '.' + ek[j], eo.Find(ek[j]), go.Find(ek[j]), False);
        finally
          ek.Free;
          gk.Free;
        end;
      end;
  end;
end;

procedure TAdvChartOptionMergeTest.CmpTree(const AWhere: string; AExp: TJSONObject);
var
  got: TJSONData;
  g: TJSONObject;
  i, j: Integer;
  k: string;
  e, gv: TJSONData;
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
      e := AExp.Items[i];
      gv := g.Find(k);
      if gv = nil then
      begin
        Bad(AWhere + '.' + k, 'missing here');
        Continue;
      end;
      if TyOptionIsComponentType(k) and (e.JSONType = jtArray) and (gv.JSONType = jtArray) then
      begin
        if e.Count <> gv.Count then
        begin
          Bad(AWhere + '.' + k, Format('upstream %d slots, here %d', [e.Count, gv.Count]));
          Continue;
        end;
        { a dataZoom's range keys are the control's to keep outside }
        if k = 'dataZoom' then
        begin
          for j := 0 to e.Count - 1 do
            CmpJson(Format('%s.%s[%d]', [AWhere, k, j]), e.Items[j], gv.Items[j],
              e.Items[j].JSONType = jtObject);
          Continue;
        end;
      end;
      CmpJson(AWhere + '.' + AExp.Names[i], e, gv, False);
    end;
  finally
    got.Free;
  end;
end;

procedure TAdvChartOptionMergeTest.CmpModels(const AWhere: string; AExp: TJSONObject);
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

function TAdvChartOptionMergeTest.SeriesElements(ASeries: Integer): Integer;
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

function HexOf(AColor: TTyChartColor): string;
begin
  Result := LowerCase(Format('#%.2x%.2x%.2x', [(AColor shr 16) and 255,
    (AColor shr 8) and 255, AColor and 255]));
end;

procedure TAdvChartOptionMergeTest.CmpOut(const AWhere: string; AExp: TJSONObject;
  ACompareFill: Boolean);
var
  arr, bars, b, c: TJSONArray;
  s, i, k, n: Integer;
  o: TJSONObject;
  w: string;
  lst: TTyPaintList;
  el: TTyChartElement;
  found: Boolean;
  x0, y0, x1, y1: Double;
  centre: TTyGraphCentre;
  zoom: Double;
  tl: TTyTitleLayout;
  z: TTyAxisZoom;
  win: TTyDzWindow;
  host: Integer;
  xywh: TTyXYWH;
  shown: Boolean;
  sel: TTyIntegerArray;
begin
  lst := FChart.List;
  { ---- the series ---- }
  arr := TJSONArray(AExp.Find('series'));
  for s := 0 to arr.Count - 1 do
  begin
    if arr.Items[s].JSONType = jtNull then Continue;
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
    { the selection the series model keeps (asked of shown series only) }
    if shown and (o.Find('sel') is TJSONArray) then
    begin
      c := TJSONArray(o.Find('sel'));
      sel := FChart.SelectedDataIndices(s);
      Inc(FCompared);
      if Length(sel) <> c.Count then
        Bad(w + '.sel', Format('upstream %s, here %d indices', [c.AsJSON, Length(sel)]))
      else
        for k := 0 to c.Count - 1 do
          if sel[k] <> c.Integers[k] then
            Bad(Format('%s.sel[%d]', [w, k]), Format('upstream %d, here %d', [c.Integers[k], sel[k]]));
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
        if ACompareFill and (o.Find('fill') is TJSONString) then
        begin
          Inc(FCompared);
          if HexOf(el.Style.FillColor) <> LowerCase(o.Strings['fill']) then
            Bad(Format('%s.bars[%d].fill', [w, i]), 'upstream ' + o.Strings['fill']
              + ', here ' + HexOf(el.Style.FillColor));
        end;
      end;
    { a graph's centre and zoom as the option says them -- what a roam
      wrote back, what a merge wrote over it }
    if o.Find('centre') <> nil then
    begin
      Inc(FCompared);
      if not FChart.GraphRoamState(s, centre, zoom) then
        Bad(w + '.centre', 'no graph here')
      else if o.Find('centre').JSONType = jtNull then
      begin
        if centre.Has then Bad(w + '.centre', 'none upstream, one here');
      end
      else if not centre.Has then
        Bad(w + '.centre', 'one upstream, none here')
      else
      begin
        c := TJSONArray(o.Find('centre'));
        Same(w + '.centre[0]', c.Floats[0], centre.X.V);
        Same(w + '.centre[1]', c.Floats[1], centre.Y.V);
      end;
      if o.Find('zoom').JSONType = jtNumber then Same(w + '.zoom', o.Floats['zoom'], zoom);
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

  { ---- the dataZoom windows (every case zooms xAxis 0) ---- }
  arr := TJSONArray(AExp.Find('dz'));
  for i := 0 to arr.Count - 1 do
  begin
    if arr.Items[i].JSONType = jtNull then Continue;
    b := TJSONArray(arr.Items[i]);
    if not FChart.AxisZoom('xAxis', 0, z, win, host) then
    begin
      Bad(Format('%s.dz[%d]', [AWhere, i]), 'no window here');
      Continue;
    end;
    Same(Format('%s.dz[%d].start', [AWhere, i]), b.Floats[0], win.Percent[0], 1e-9);
    Same(Format('%s.dz[%d].end', [AWhere, i]), b.Floats[1], win.Percent[1], 1e-9);
  end;
end;

procedure TAdvChartOptionMergeTest.RunStep(AStep: TJSONObject);
var
  p: TJSONObject;
  t: string;
  roam: TTyGraphRoamPayload;
begin
  if AStep.Strings['kind'] = 'set' then
  begin
    FChart.AnimNow := T0;
    FChart.SetOption(AStep.Strings['text'], AStep.Booleans['notMerge']);
    AssertEquals('the option is taken: ' + AStep.Strings['text'], '', FChart.OptionError);
  end
  else
  begin
    p := TJSONObject(AStep.Find('payload'));
    t := p.Strings['type'];
    if t = 'dataZoom' then
      FChart.DispatchDataZoom(p.Get('dataZoomIndex', 0), p.Floats['start'], p.Floats['end'])
    else if t = 'treeExpandAndCollapse' then
      FChart.TreeToggle(p.Get('seriesIndex', 0), p.Integers['dataIndex'])
    else if t = 'graphRoam' then
    begin
      roam := Default(TTyGraphRoamPayload);
      roam.SeriesIndex := p.Get('seriesIndex', -1);
      roam.HasPan := True;
      roam.DX := p.Floats['dx'];
      roam.DY := p.Floats['dy'];
      FChart.GraphDispatchRoam(roam);
    end
    else
      FChart.DispatchAction(p.AsJSON);
  end;
  Draw;
end;

{ ==================== the fixture ==================== }

procedure TAdvChartOptionMergeTest.TestTheTablesAreUpstreams;
var
  mts, deps, subs: TJSONData;
  i, j: Integer;
  mine, theirs: TStringList;
  d: string;
begin
  mts := TJSONObject(FRoot).Arrays['mainTypes'];
  AssertEquals('as many main types', mts.Count, TyOptionMainTypeCount);
  for i := 0 to mts.Count - 1 do
    AssertEquals('main type ' + IntToStr(i), mts.Items[i].AsString, TyOptionMainType(i));
  deps := TJSONObject(FRoot).Objects['deps'];
  subs := TJSONObject(FRoot).Objects['subTypes'];
  mine := TStringList.Create;
  theirs := TStringList.Create;
  try
    mine.Sorted := True;
    theirs.Sorted := True;
    for i := 0 to mts.Count - 1 do
    begin
      d := mts.Items[i].AsString;
      mine.Clear;
      theirs.Clear;
      mine.DelimitedText := TyOptionDependencies(d);
      for j := 0 to TJSONObject(deps).Arrays[d].Count - 1 do
        theirs.Add(TJSONObject(deps).Arrays[d].Strings[j]);
      AssertEquals('the dependencies of ' + d, theirs.CommaText, mine.CommaText);
      AssertEquals('whether ' + d + ' has subtypes',
        TJSONObject(subs).Find(d) <> nil, TyOptionHasSubTypes(d));
    end;
  finally
    mine.Free;
    theirs.Free;
  end;
end;

procedure TAdvChartOptionMergeTest.TestMergesAsUpstream;
var
  cases, steps: TJSONArray;
  c, st, prev: TJSONObject;
  ci, si, s, o, expPair, gotPair, n: Integer;
  w: string;
  fill: Boolean;
  pv, cv: TJSONArray;
  prevIds, prevSubs: array of string;
  k: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for ci := 0 to cases.Count - 1 do
  begin
    c := TJSONObject(cases.Items[ci]);
    NewChart;
    fill := False;
    for k := 0 to c.Arrays['compare'].Count - 1 do
      if c.Arrays['compare'].Strings[k] = 'fill' then fill := True;
    steps := c.Arrays['steps'];
    prev := nil;
    prevIds := nil;
    prevSubs := nil;
    for si := 0 to steps.Count - 1 do
    begin
      st := TJSONObject(steps.Items[si]);
      w := c.Strings['id'] + ' step ' + IntToStr(si);
      RunStep(st);
      CmpTree(w + ' tree', st.Objects['tree']);
      CmpModels(w + ' models', st.Objects['models']);
      CmpOut(w + ' out', st.Objects['out'], fill);
      { ---- the views: upstream kept one exactly where the port's
        (id, type) pairs the series to an old one ---- }
      cv := st.Arrays['views'];
      if prev <> nil then
      begin
        pv := prev.Arrays['views'];
        for s := 0 to cv.Count - 1 do
        begin
          if cv.Items[s].JSONType = jtNull then Continue;
          expPair := -1;
          for o := 0 to pv.Count - 1 do
            if (pv.Items[o].JSONType <> jtNull) and (pv.Items[o].AsInteger = cv.Items[s].AsInteger) then
              expPair := o;
          gotPair := -1;
          for o := 0 to High(prevIds) do
            if (prevIds[o] <> '') and (prevIds[o] = FChart.ComponentModelId('series', s))
              and (prevSubs[o] = FChart.ComponentModelSubType('series', s)) then
              gotPair := o;
          Inc(FCompared);
          if expPair <> gotPair then
            Bad(Format('%s views[%d]', [w, s]), Format('upstream pairs it with old %d, here %d',
              [expPair, gotPair]));
        end;
      end;
      n := cv.Count;
      SetLength(prevIds, n);
      SetLength(prevSubs, n);
      for s := 0 to n - 1 do
      begin
        prevIds[s] := FChart.ComponentModelId('series', s);
        prevSubs[s] := FChart.ComponentModelSubType('series', s);
      end;
      prev := st;
    end;
  end;
  AssertTrue('compared something', FCompared > 1000);
  AssertEquals(Format('%d of %d comparisons differ:%s', [FBad, FCompared, FReport]), 0, FBad);
end;

{ ==================== by hand ==================== }

const
  cLegend3 = '{"animation":false,"legend":{},"xAxis":{"type":"category","data":["Mon","Tue"]},'
    + '"yAxis":{},"series":[{"type":"bar","name":"A","data":[1,2]},'
    + '{"type":"bar","name":"B","data":[2,1]}]}';

function Shown(AChart: TOmProbe; ASeries: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to AChart.List.Count - 1 do
    if AChart.List.Element(i).Datum.SeriesIndex = ASeries then Exit(True);
end;

{ The property is a declaration: the text it holds again is no change -- a
  legend switched off by an action stays off. SetOption(text, True) is
  upstream's notMerge, the same text included: new models, the legend
  starts again. Upstream's setOption(o, true) after a legendToggleSelect
  shows the series again (option-merge.js, identical-notmerge). }
procedure TAdvChartOptionMergeTest.TestThePropertyIsADeclaration;
begin
  NewChart;
  FChart.Option := cLegend3;
  Draw;
  FChart.DispatchAction('{"type":"legendToggleSelect","name":"B"}');
  Draw;
  AssertFalse('B is switched off', Shown(FChart, 1));
  FChart.Option := cLegend3;
  Draw;
  AssertFalse('the same text through the property: still off', Shown(FChart, 1));
  FChart.SetOption(cLegend3, True);
  Draw;
  AssertTrue('the same text as a notMerge: on again', Shown(FChart, 1));
  FChart.DispatchAction('{"type":"legendToggleSelect","name":"B"}');
  Draw;
  FChart.SetOption(cLegend3);
  Draw;
  AssertFalse('the same text as a merge: kept off', Shown(FChart, 1));
end;

{ After a merge the property reads the merged option -- so the picture and
  the property agree -- and the text set before the merge is a change again:
  a real notMerge, back to that option. }
procedure TAdvChartOptionMergeTest.TestThePropertyHoldsTheMergedOption;
var
  before: string;
begin
  NewChart;
  FChart.Option := cLegend3;
  Draw;
  before := FChart.GetOptionJson;
  AssertTrue('merged', FChart.MergeOption('{"series":[{"data":[5,5]}]}'));
  Draw;
  AssertEquals('the property is the merged option', FChart.GetOptionJson, FChart.Option);
  AssertTrue('the merge is in it', Pos('[5,5]', FChart.Option) > 0);
  FChart.Option := cLegend3;
  Draw;
  AssertEquals('the old text again is the old option again', before, FChart.GetOptionJson);
end;

{ Upstream throws on these; the control refuses the merge whole, keeps the
  option and says why, and the next good merge clears the error. }
procedure TAdvChartOptionMergeTest.TestARefusedMergeChangesNothing;
var
  before: string;
begin
  NewChart;
  FChart.Option := cLegend3;
  Draw;
  before := FChart.GetOptionJson;
  AssertFalse('a text that does not parse', FChart.MergeOption('{"series": ['));
  AssertTrue('says why', FChart.OptionError <> '');
  AssertEquals('nothing changed', before, FChart.GetOptionJson);
  AssertFalse('no object', FChart.MergeOption('[1, 2]'));
  AssertEquals('nothing changed', before, FChart.GetOptionJson);
  AssertFalse('one id twice',
    FChart.MergeOption('{"title":{"text":"t"},"series":[{"id":"a","data":[1,1]},{"id":"a"}]}'));
  AssertTrue('says which', Pos('"a"', FChart.OptionError) > 0);
  AssertEquals('not even the title', before, FChart.GetOptionJson);
  AssertTrue('a good merge', FChart.MergeOption('{"title":{"text":"t"}}'));
  AssertEquals('clears the error', '', FChart.OptionError);
end;

{ With no option yet, a merge is the first setOption -- an init, as
  upstream's is whatever its notMerge says. }
procedure TAdvChartOptionMergeTest.TestTheFirstMergeIsAnInit;
begin
  NewChart;
  AssertTrue('taken', FChart.MergeOption(cLegend3));
  Draw;
  AssertEquals('the option is the text, as the property', cLegend3, FChart.Option);
  AssertEquals('the first series', #0'A'#0'0', FChart.ComponentModelId('series', 0));
  AssertEquals('the legend', #0'series'#0'0'#0'0', FChart.ComponentModelId('legend', 0));
  AssertTrue('drawn', Shown(FChart, 0) and Shown(FChart, 1));
end;

{ A MERGE IS AN UPDATE. A series renamed by a merge keeps its model's id
  -- the view upstream keeps (option-merge.js, series-view-kept-on-rename)
  -- so its bars tween from where they were; the same rename as a notMerge
  is a new view, and the bars grow from nothing. }
procedure TAdvChartOptionMergeTest.TestAMergeIsAnUpdate;
const
  cA = '{"xAxis":{"type":"category","data":["A","B","C"]},"yAxis":{"type":"value","max":40},'
    + '"series":[{"type":"bar","name":"A","data":[10,30,20]}]}';
  cB = '{"xAxis":{"type":"category","data":["A","B","C"]},"yAxis":{"type":"value","max":40},'
    + '"series":[{"type":"bar","name":"B","data":[20,10,30]}]}';
var
  p: TTyChartAnimProxy;
  oldH: Double;
  pass: Integer;
begin
  for pass := 0 to 1 do
  begin
    NewChart;
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := T0;
    FChart.Option := cA;
    Draw;
    FChart.AnimTick(T0 + 5000);
    p := FChart.AnimFindProxy(0, 0, 'bar');
    AssertNotNull('the first bar has a proxy', p);
    oldH := p.Num('shape.height');
    AssertTrue('and a height', oldH <> 0);
    FChart.AnimNow := T1;
    if pass = 0 then
      AssertTrue('merged', FChart.MergeOption('{"series":[{"name":"B","data":[20,10,30]}]}'))
    else
      FChart.SetOption(cB, True);
    Draw;
    AssertTrue('animating', FChart.AnimLive);
    p := FChart.AnimFindProxy(0, 0, 'bar');
    AssertNotNull('the bar has a proxy', p);
    if pass = 0 then
    begin
      AssertEquals('the merge keeps the id', #0'A'#0'0', FChart.ComponentModelId('series', 0));
      AssertEquals('an update: from the old height', oldH, p.Num('shape.height'), 0);
    end
    else
    begin
      AssertEquals('the notMerge makes a new id', #0'B'#0'0', FChart.ComponentModelId('series', 0));
      AssertEquals('an entrance: from nothing', 0, p.Num('shape.height'), 0);
    end;
  end;
end;

{ A type change rebuilds the series from the new option alone, which names
  nothing; the model keeps its name, so the legend still calls it S and a
  toggle of S still reaches it (option-merge.js, series-type-change). }
procedure TAdvChartOptionMergeTest.TestATypeChangeKeepsTheName;
begin
  NewChart;
  FChart.Option := '{"animation":false,"legend":{},"xAxis":{"type":"category","data":["a","b"]},'
    + '"yAxis":{},"series":[{"type":"bar","name":"S","data":[1,2]}]}';
  Draw;
  AssertTrue('merged', FChart.MergeOption('{"series":[{"type":"line","data":[2,1]}]}'));
  Draw;
  AssertEquals('the model is still S', 'S', FChart.ComponentModelName('series', 0));
  AssertTrue('drawn', Shown(FChart, 0));
  FChart.DispatchAction('{"type":"legendToggleSelect","name":"S"}');
  Draw;
  AssertFalse('switched off by its name', Shown(FChart, 0));
end;

initialization
  RegisterTest(TAdvChartOptionMergeTest);
end.
