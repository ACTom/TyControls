unit test.advchart.hoverlayer;
{$mode objfpc}{$H+}
{ THE HOVER LAYER, HELD TO UPSTREAM [R2-I9].

  tools/advchart-oracle/hover-layer.js runs the real ECharts 6.1 build with
  progressive.js's recipe (a canvas-typed painter, env.node false) and
  records, after the setOption and after every frame, pointer move or
  action: whether the threshold is in use and the storage's count, the
  display list's elements on zrender's hover layer in list order, and every
  series path with a state list or on the hover layer -- its states, its own
  style (fill, stroke, lineWidth, opacity), its hover style, its z2 and
  scale against the setOption's.

  The replay drives the control the same way -- SetOption, ProgressTick at a
  step cost of 0 (upstream's frames there finish every chunk), MouseMove /
  MouseLeave, DispatchAction, a headless render per step -- and compares the
  hover layer's copies (series, data index, in order, and the style they
  are drawn with), and for every recorded element its state list, whether
  it is on the hover layer, its own layer's values (the state record's and
  the list element's), its hover values, its z2 and scale; and how many
  rows of each series have a state at all. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Style,
     tyControls.AdvanceChart.States, tyControls.AdvanceChart.Shape, tyControls.AdvanceChart;
type
  THlProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Layered(ACanvas: TCanvas; const ARect: TRect);
    procedure Move(AX, AY: Integer);
    procedure Leave;
    procedure Drag(AX0, AY0, AX1, AY1: Integer);
    function List: TTyPaintList;
    function Primary: TTyChartColor;
  end;

  TAdvChartHoverLayerOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: THlProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FName, FReport: string;
    FBad, FCompared, FSnaps, FOnLayer, FCopies: Integer;
    FSkipEls: Boolean;
    procedure Miss(const AWhat: string);
    procedure NewChart(AW, AH: Integer);
    procedure Draw;
    procedure CheckStyle(const AWhat: string; AWant: TJSONObject;
      const AObj: TTyStObject);
    procedure CheckDrawn(const AWhat: string; AWant: TJSONObject;
      const AEl: TTyChartElement);
    procedure CheckEl(AEl: TJSONObject);
    procedure CheckSnap(ASnap: TJSONObject; ASeriesCount: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheHoverLayerAsUpstream;
  end;

  { what the replay does not reach on its own }
  TAdvChartHoverLayerTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: THlProbe;
    FBmp: TBGRABitmap;
    procedure NewChart(const AOption: string);
    procedure Draw;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCopyIsDrawnOverEveryLayer;
    procedure TestAHoverOnlyFrameLeavesTheListAlone;
    procedure TestALabelledSymbolIsLiftedInItsLayer;
    procedure TestTheCachedPaintDrawsTheCopy;
    procedure TestAZoomPastTheThresholdKeepsTheEmphasisInItsLayer;
  end;

  { [R2-I9] the list an update built drawn as it stands, and the visual
    map's own states on the list's end }
  TAdvChartListFreshTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function NewChart(AW, AH: Integer; AMode: TTyChartAnimationMode;
      const AOption: string): THlProbe;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAFreshListIsTheBuiltList;
    procedure TestAnUpdateBuildsOnce;
    procedure TestTheFirstIndicatorBuildsNoList;
    procedure TestARefusedPatchAfterAnUpdateBuilds;
  end;

implementation

const
  cW = 600;
  cH = 400;

var
  GFix: TJSONData = nil;

function Fix: TJSONData;
var sl: TStringList;
begin
  if GFix = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-hover-layer.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := GFix;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

var
  { the skin's primary ink: upstream's default theme primary '#3c3c41' (a
    select border) is the skin's here, as every states oracle takes it }
  GPrimary: TTyChartColor = 0;

{ a colour as upstream holds it: null and 'none' draw nothing }
function WantColour(AData: TJSONData; out AC: TTyChartColor): Boolean;
begin
  AC := 0;
  if (AData = nil) or (AData.JSONType <> jtString) or (AData.AsString = 'none') then
    Exit(False);
  Result := TyTryParseChartColor(AData.AsString, AC);
  if Result and (AC = TTyChartColor($FF3C3C41)) and (GPrimary <> 0) then AC := GPrimary;
end;

function ColourText(AHas: Boolean; AC: TTyChartColor): string;
begin
  if not AHas then Result := '(none)' else Result := '$' + IntToHex(AC, 8);
end;

{ ==================== the probe ==================== }

procedure THlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure THlProbe.Layered(ACanvas: TCanvas; const ARect: TRect);
begin
  RenderCached(ACanvas, ARect, 96);
end;

procedure THlProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure THlProbe.Leave;
begin
  MouseLeave;
end;

procedure THlProbe.Drag(AX0, AY0, AX1, AY1: Integer);
begin
  MouseMove([], AX0, AY0);
  MouseDown(mbLeft, [ssLeft], AX0, AY0);
  MouseMove([ssLeft], (AX0 + AX1) div 2, (AY0 + AY1) div 2);
  MouseMove([ssLeft], AX1, AY1);
  MouseUp(mbLeft, [], AX1, AY1);
end;

function THlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function THlProbe.Primary: TTyChartColor;
begin
  Result := StPrimaryInk;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartHoverLayerOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FChart := nil;
end;

procedure TAdvChartHoverLayerOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartHoverLayerOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartHoverLayerOracleTest.NewChart(AW, AH: Integer);
begin
  FreeAndNil(FChart);
  FChart := THlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, AW, AH);
  FChart.AnimationMode := camOff;
  { a clock that stands still; a frame finishes every chunk, as upstream's
    frames do where a step costs no time }
  FChart.AnimNow := 0;
  FChart.ProgressiveStepCostMs := 0;
end;

procedure TAdvChartHoverLayerOracleTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ a state object's style keys against upstream's style record }
procedure TAdvChartHoverLayerOracleTest.CheckStyle(const AWhat: string;
  AWant: TJSONObject; const AObj: TTyStObject);
var
  c: TTyChartColor;
  has, got: Boolean;
begin
  has := WantColour(AWant.Find('fill'), c);
  got := TyStHasColour(AObj, stkFill);
  Inc(FCompared);
  if (has <> got) or (has and (AObj.Color[stkFill] <> c)) then
    Miss(Format('%s fill %s upstream, %s here', [AWhat, ColourText(has, c),
      ColourText(got, AObj.Color[stkFill])]));
  has := WantColour(AWant.Find('stroke'), c);
  got := TyStHasColour(AObj, stkStroke);
  Inc(FCompared);
  if (has <> got) or (has and (AObj.Color[stkStroke] <> c)) then
    Miss(Format('%s stroke %s upstream, %s here', [AWhat, ColourText(has, c),
      ColourText(got, AObj.Color[stkStroke])]));
  { the width of a stroke drawn }
  if has and (AWant.Find('lineWidth') <> nil) and (AWant.Find('lineWidth').JSONType = jtString) then
  begin
    Inc(FCompared);
    if Hex(AObj.Num[stkLineWidth]) <> AWant.Strings['lineWidth'] then
      Miss(Format('%s lineWidth %g upstream, %g here', [AWhat,
        FromHex(AWant.Strings['lineWidth']), AObj.Num[stkLineWidth]]));
  end;
  if (AWant.Find('opacity') <> nil) and (AWant.Find('opacity').JSONType = jtString) then
  begin
    Inc(FCompared);
    if Hex(AObj.Num[stkOpacity]) <> AWant.Strings['opacity'] then
      Miss(Format('%s opacity %g upstream, %g here', [AWhat,
        FromHex(AWant.Strings['opacity']), AObj.Num[stkOpacity]]));
  end;
end;

{ an element as it is drawn against upstream's style record }
procedure TAdvChartHoverLayerOracleTest.CheckDrawn(const AWhat: string;
  AWant: TJSONObject; const AEl: TTyChartElement);
var
  c: TTyChartColor;
  has, got: Boolean;
begin
  has := WantColour(AWant.Find('fill'), c);
  got := AEl.Style.HasFill;
  Inc(FCompared);
  if (has <> got) or (has and (AEl.Style.FillColor <> c)) then
    Miss(Format('%s drawn fill %s upstream, %s here', [AWhat, ColourText(has, c),
      ColourText(got, AEl.Style.FillColor)]));
  has := WantColour(AWant.Find('stroke'), c);
  got := AEl.Style.StrokeColor <> 0;
  Inc(FCompared);
  if (has <> got) or (has and (AEl.Style.StrokeColor <> c)) then
    Miss(Format('%s drawn stroke %s upstream, %s here', [AWhat, ColourText(has, c),
      ColourText(got, AEl.Style.StrokeColor)]));
  if has and (AWant.Find('lineWidth') <> nil) and (AWant.Find('lineWidth').JSONType = jtString) then
  begin
    Inc(FCompared);
    if Hex(AEl.Style.StrokeWidthLogical) <> AWant.Strings['lineWidth'] then
      Miss(Format('%s drawn lineWidth %g upstream, %g here', [AWhat,
        FromHex(AWant.Strings['lineWidth']), AEl.Style.StrokeWidthLogical]));
  end;
  if (AWant.Find('opacity') <> nil) and (AWant.Find('opacity').JSONType = jtString) then
  begin
    Inc(FCompared);
    if Hex(AEl.Style.Alpha) <> AWant.Strings['opacity'] then
      Miss(Format('%s drawn opacity %g upstream, %g here', [AWhat,
        FromHex(AWant.Strings['opacity']), AEl.Style.Alpha]));
  end;
end;

procedure TAdvChartHoverLayerOracleTest.CheckEl(AEl: TJSONObject);
var
  s, d, k: Integer;
  item, area: TTyStItem;
  st: TTyStElement;
  arr: TJSONArray;
  want, what: string;
  list: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
begin
  s := AEl.Integers['s'];
  d := AEl.Integers['d'];
  what := Format('s%d d%d', [s, d]);
  { a datum's second path (a treemap node's content): its host's states }
  if AEl.Integers['p'] > 0 then Exit;
  if d < 0 then
  begin
    { a line's polyline }
    if not FChart.LineStates(s, item, area) then
    begin
      Miss(what + ': no polyline here');
      Exit;
    end;
  end
  else if not FChart.ItemStates(s, d, item) then
  begin
    Miss(what + ': no state record here');
    Exit;
  end;
  st := item.Host;
  arr := AEl.Arrays['cs'];
  want := '';
  for k := 0 to arr.Count - 1 do
  begin
    if want <> '' then want := want + ',';
    want := want + arr.Strings[k];
  end;
  Inc(FCompared);
  if TyStNamesText(st.States) <> want then
    Miss(Format('%s states "%s" upstream, "%s" here', [what, want, TyStNamesText(st.States)]));
  Inc(FCompared);
  if st.InHover <> AEl.Booleans['ih'] then
    Miss(Format('%s on the hover layer %s upstream, %s here', [what,
      BoolToStr(AEl.Booleans['ih'], True), BoolToStr(st.InHover, True)]));
  if st.InHover then Inc(FOnLayer);
  { the own layer }
  CheckStyle(what + ' own', AEl.Objects['st'], st.Cur);
  Inc(FCompared);
  if Round(st.Cur.Num[stkZ2] - st.Rest.Num[stkZ2]) <> AEl.Integers['dz2'] then
    Miss(Format('%s z2 %+d upstream, %+d here', [what, AEl.Integers['dz2'],
      Round(st.Cur.Num[stkZ2] - st.Rest.Num[stkZ2])]));
  Inc(FCompared);
  if (st.Cur.Has[stkScale] and (Hex(st.Cur.Num[stkScale]) <> AEl.Strings['ds']))
    or (not st.Cur.Has[stkScale] and (AEl.Strings['ds'] <> Hex(1))) then
    Miss(Format('%s scale %g upstream, %g here', [what, FromHex(AEl.Strings['ds']),
      st.Cur.Num[stkScale]]));
  { the hover style }
  if st.InHover and (AEl.Find('hs') <> nil) and (AEl.Find('hs').JSONType = jtObject) then
    CheckStyle(what + ' hover', AEl.Objects['hs'], TyStHoverValues(st));
  { and the list's own element: the own layer as drawn }
  if d >= 0 then
  begin
    list := FChart.List;
    found := False;
    for k := 0 to list.Count - 1 do
    begin
      e := list.Element(k);
      if (e.Datum.SeriesIndex <> s) or (e.Datum.DataIndex <> d) or e.Datum.IsEdge
        or e.Silent or (e.Caption.FontSizeLogical > 0) or e.IsGuide then Continue;
      found := True;
      CheckDrawn(what + ' own', AEl.Objects['st'], e);
      Break;
    end;
    if not found then Miss(what + ': no element in the list');
  end;
end;

procedure TAdvChartHoverLayerOracleTest.CheckSnap(ASnap: TJSONObject; ASeriesCount: Integer);
var
  hv, els: TJSONArray;
  layer: TTyPaintList;
  i, n, s, want, k: Integer;
  e, own: TTyChartElement;
  h, w: TJSONObject;
  got: string;
  bc, bo: TTyRectF;
begin
  Inc(FSnaps);
  hv := ASnap.Arrays['hover'];
  els := ASnap.Arrays['els'];
  layer := FChart.HoverLayerForTest;
  if layer = nil then n := 0 else n := layer.Count;
  Inc(FCompared);
  if n <> hv.Count then
  begin
    got := '';
    for i := 0 to n - 1 do
      got := got + Format(' s%d d%d', [layer.Element(i).Datum.SeriesIndex,
        layer.Element(i).Datum.DataIndex]);
    Miss(Format('%d on the hover layer upstream, %d here:%s', [hv.Count, n, got]));
  end
  else
    for i := 0 to n - 1 do
    begin
      h := hv.Objects[i];
      e := layer.Element(i);
      Inc(FCompared);
      Inc(FCopies);
      { a line's polyline is no datum: upstream's d is -1 }
      if (e.Datum.SeriesIndex <> h.Integers['s'])
        or ((h.Integers['d'] >= 0) and (e.Datum.DataIndex <> h.Integers['d'])) then
        Miss(Format('hover layer #%d is s%d d%d upstream, s%d d%d here', [i,
          h.Integers['s'], h.Integers['d'], e.Datum.SeriesIndex, e.Datum.DataIndex]))
      else
        { the copy as it is drawn: the element's hover style }
        for s := 0 to els.Count - 1 do
        begin
          w := els.Objects[s];
          if (w.Integers['s'] = h.Integers['s']) and (w.Integers['d'] = h.Integers['d'])
            and (w.Integers['p'] = h.Integers['p']) and (w.Find('hs') <> nil)
            and (w.Find('hs').JSONType = jtObject) then
            CheckDrawn(Format('hover layer #%d', [i]), w.Objects['hs'], e);
        end;
      { [r2v] AND WHERE: the hover layer brushes the element itself, with
        its own transform -- the copy's shape is the own element's as the
        list holds it (a scale the own layer took is not taken again) }
      if (h.Integers['d'] >= 0) and (h.Integers['p'] = 0) then
        for k := 0 to FChart.List.Count - 1 do
        begin
          own := FChart.List.Element(k);
          if (own.Datum.SeriesIndex <> h.Integers['s']) or (own.Datum.DataIndex <> h.Integers['d'])
            or own.Datum.IsEdge or own.Silent or (own.Caption.FontSizeLogical > 0) or own.IsGuide then
            Continue;
          Inc(FCompared);
          bc := TyShapeBounds(e.Shape);
          bo := TyShapeBounds(own.Shape);
          if (Hex(bc.Left) <> Hex(bo.Left)) or (Hex(bc.Top) <> Hex(bo.Top))
            or (Hex(bc.Right) <> Hex(bo.Right)) or (Hex(bc.Bottom) <> Hex(bo.Bottom)) then
            Miss(Format('hover layer #%d: drawn at %g..%g, its own element at %g..%g', [i,
              bc.Left, bc.Right, bo.Left, bo.Right]));
          Break;
        end;
    end;
  if not FSkipEls then
    for i := 0 to els.Count - 1 do CheckEl(els.Objects[i]);
  { and no other row has a state here }
  for s := 0 to ASeriesCount - 1 do
  begin
    want := 0;
    for i := 0 to els.Count - 1 do
      if (els.Objects[i].Integers['s'] = s) and (els.Objects[i].Integers['d'] >= 0)
        and (els.Objects[i].Integers['p'] = 0) then Inc(want);
    Inc(FCompared);
    if FChart.StRowsInStatesForTest(s) <> want then
      Miss(Format('series %d: %d rows with a state upstream, %d here', [s, want,
        FChart.StRowsInStatesForTest(s)]));
  end;
end;

procedure TAdvChartHoverLayerOracleTest.TestTheHoverLayerAsUpstream;
var
  cases, snaps, steps, st: TJSONArray;
  c, sn: TJSONObject;
  ci, si, nSeries: Integer;
  t: string;
begin
  FRoot := Fix;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for ci := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[ci];
    FName := c.Strings['id'] + ' init';
    NewChart(TJSONObject(FRoot).Integers['W'], TJSONObject(FRoot).Integers['H']);
    FChart.SetOption(c.Objects['option'].AsJSON, True);
    Draw;
    GPrimary := FChart.Primary;
    { a treemap node's paths are two upstream and one host and a part here,
      in another order: its rows are compared by their states' count and
      the hover layer only }
    FSkipEls := Pos('treemap', c.Strings['id']) = 1;
    if c.Objects['option'].Find('series') is TJSONArray then
      nSeries := c.Objects['option'].Arrays['series'].Count
    else
      nSeries := 1;
    snaps := c.Arrays['snaps'];
    steps := c.Arrays['steps'];
    CheckSnap(snaps.Objects[0], nSeries);
    for si := 1 to snaps.Count - 1 do
    begin
      sn := snaps.Objects[si];
      st := steps.Arrays[sn.Integers['at']];
      t := sn.Strings['t'];
      FName := Format('%s/%d %s', [c.Strings['id'], sn.Integers['at'], t]);
      if t = 'frame' then FChart.ProgressTick
      else if t = 'move' then FChart.Move(st.Arrays[1].Integers[0], st.Arrays[1].Integers[1])
      else if t = 'leave' then FChart.Leave
      else if t = 'act' then FChart.DispatchAction(st.Objects[1].AsJSON);
      Draw;
      CheckSnap(sn, nSeries);
    end;
    FreeAndNil(FChart);
  end;
  WriteLn(Format('  hover layer oracle: %d comparisons, %d snapshots, %d copies, %d on the layer',
    [FCompared, FSnaps, FCopies, FOnLayer]));
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ:%s', [FBad, FCompared, FReport]));
  AssertTrue('copies were compared', FCopies >= 20);
  AssertTrue('elements on the layer were compared', FOnLayer >= 20);
end;

{ ==================== hand-written ==================== }

procedure TAdvChartHoverLayerTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  FChart := nil;
end;

procedure TAdvChartHoverLayerTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartHoverLayerTest.NewChart(const AOption: string);
begin
  FreeAndNil(FChart);
  FChart := THlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimationMode := camOff;
  FChart.AnimNow := 0;
  FChart.SetOption(AOption, True);
  Draw;
end;

procedure TAdvChartHoverLayerTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

const
  { two big symbols on one spot, series 1 over series 0 by z; the grid
    60..560 x 40..360 puts (50, 50) at (310, 200) }
  cStack = '{"animation":false,%s"grid":{"left":60,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":100},"yAxis":{"type":"value","min":0,"max":100},'
    + '"series":[{"type":"scatter","z":2,"symbolSize":40,"itemStyle":{"color":"#ff0000","opacity":1},'
    + '"emphasis":{"itemStyle":{"color":"#0000ff"}},"data":[[50,50],[10,10]]},'
    + '{"type":"scatter","z":3,"symbolSize":20,"itemStyle":{"color":"#00ff00","opacity":1},'
    + '"silent":true,"data":[[50,50]]}]}';

procedure TAdvChartHoverLayerTest.TestTheCopyIsDrawnOverEveryLayer;
var px: TBGRAPixel;
begin
  { UNDER THE THRESHOLD the hovered symbol is restyled in its own place:
    the green one of the later z stays over it }
  NewChart(Format(cStack, ['']));
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":0}');
  Draw;
  AssertNull('no hover layer', FChart.HoverLayerForTest);
  px := FBmp.GetPixel(310, 200);
  AssertTrue('green over the restyled symbol', (px.green > 200) and (px.blue < 60));
  px := FBmp.GetPixel(310, 200 - 15);
  AssertTrue('blue around it', (px.blue > 200) and (px.red < 60));
  { PAST IT the hover layer brushes the symbol over everything: blue over
    the green, and the own layer keeps red underneath }
  NewChart(Format(cStack, ['"hoverLayerThreshold":1,']));
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":0}');
  Draw;
  AssertNotNull('a hover layer', FChart.HoverLayerForTest);
  AssertEquals('one copy', 1, FChart.HoverLayerForTest.Count);
  px := FBmp.GetPixel(310, 200);
  AssertTrue('blue over the green', (px.blue > 200) and (px.green < 60));
  px := FBmp.GetPixel(310, 200 - 15);
  AssertTrue('blue around it', (px.blue > 200) and (px.red < 60));
  { and not enlarged: the emphasis scale is no style }
  px := FBmp.GetPixel(310, 200 - 21);
  AssertFalse('nothing past its own size', (px.blue > 200) and (px.red < 60));
  { gone with the downplay }
  FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":0}');
  Draw;
  AssertNull('the layer empties', FChart.HoverLayerForTest);
  px := FBmp.GetPixel(310, 200 - 15);
  AssertTrue('red again', (px.red > 200) and (px.blue < 60));
end;

{ [r2v] THE CACHED PAINT DRAWS THE COPY TOO: a highlight past the threshold
  with nothing else dynamic (no tooltip, no pointer) -- the hover layer alone
  is what the dynamic pass has to draw }
procedure TAdvChartHoverLayerTest.TestTheCachedPaintDrawsTheCopy;
var
  bmp: TBitmap;
  c: TColor;
begin
  NewChart(Format(cStack, ['"hoverLayerThreshold":1,']));
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(cW, cH);
    FChart.Layered(bmp.Canvas, Rect(0, 0, cW, cH));
    c := bmp.Canvas.Pixels[310, 200];
    AssertTrue('green on top at rest', (Green(c) > 200) and (Blue(c) < 60));
    FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":0}');
    FChart.Layered(bmp.Canvas, Rect(0, 0, cW, cH));
    AssertNotNull('a hover layer', FChart.HoverLayerForTest);
    c := bmp.Canvas.Pixels[310, 200];
    AssertTrue('the copy over the green', (Blue(c) > 200) and (Green(c) < 60));
    FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":0}');
    FChart.Layered(bmp.Canvas, Rect(0, 0, cW, cH));
    c := bmp.Canvas.Pixels[310, 200];
    AssertTrue('green again', (Green(c) > 200) and (Blue(c) < 60));
  finally
    bmp.Free;
  end;
end;

{ [r2v] A ZOOM THAT TAKES THE COUNT PAST THE THRESHOLD while a symbol is
  highlighted: the symbol keeps its emphasis in its own layer (updateStates
  puts its states back before updateHoverLayerStatus flags it) -- with the
  update's list drawn as it stands and with the paint building it again }
procedure TAdvChartHoverLayerTest.TestAZoomPastTheThresholdKeepsTheEmphasisInItsLayer;
var
  sb: string;
  i: Integer;
  fresh: Boolean;
begin
  sb := '[';
  for i := 0 to 3499 do
  begin
    if i > 0 then sb := sb + ',';
    sb := sb + Format('[%d,%d]', [(i * 37) mod 1000, (i * 53) mod 500]);
  end;
  sb := sb + ']';
  try
    for fresh := False to True do
    begin
      TyAdvChartListFreshForTest(fresh);
      NewChart('{"animation":false,"dataZoom":[{"type":"inside","xAxisIndex":0,"start":0,"end":50}],'
        + '"xAxis":{"type":"value","min":0,"max":1000},"yAxis":{"type":"value","min":0,"max":500},'
        + '"series":[{"type":"scatter","progressive":0,"symbolSize":8,"data":' + sb + '}]}');
      FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":1}');
      Draw;
      AssertNull('under the threshold: no hover layer', FChart.HoverLayerForTest);
      FChart.DispatchAction('{"type":"dataZoom","start":0,"end":100}');
      Draw;
      AssertNull(Format('past it after the zoom (fresh %s): still no copy',
        [BoolToStr(fresh, True)]), FChart.HoverLayerForTest);
      Draw;
      AssertNull(Format('nor at the next paint (fresh %s)', [BoolToStr(fresh, True)]),
        FChart.HoverLayerForTest);
      { out and in again: now the flagged emphasis takes it there }
      FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":1}');
      Draw;
      FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":1}');
      Draw;
      AssertNotNull('hovered again past the threshold: the copy', FChart.HoverLayerForTest);
    end;
  finally
    TyAdvChartListFreshForTest(True);
  end;
end;

procedure TAdvChartHoverLayerTest.TestAHoverOnlyFrameLeavesTheListAlone;
var
  bmp: TBitmap;
  patches, i: Integer;
  before: array of TTyChartElement;
  sb: string;
begin
  { past the threshold a hover changes no element of the list: no state
    patch, no build -- the static layer stays as it is, the copy is the
    dynamic layer's }
  sb := '[';
  for i := 0 to 3499 do
  begin
    if i > 0 then sb := sb + ',';
    sb := sb + Format('[%d,%d]', [(i * 37) mod 1000, (i * 53) mod 500]);
  end;
  sb := sb + ']';
  NewChart('{"animation":false,"xAxis":{"type":"value","min":0,"max":1000},'
    + '"yAxis":{"type":"value","min":0,"max":500},"series":[{"type":"scatter",'
    + '"progressive":0,"symbolSize":8,"data":' + sb + '}]}');
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(cW, cH);
    FChart.Layered(bmp.Canvas, Rect(0, 0, cW, cH));
    SetLength(before, FChart.List.Count);
    for i := 0 to FChart.List.Count - 1 do before[i] := FChart.List.Element(i);
    patches := TyAdvChartStPatchesForTest;
    FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":5}');
    FChart.Layered(bmp.Canvas, Rect(0, 0, cW, cH));
    AssertEquals('no state patch', patches, TyAdvChartStPatchesForTest);
    AssertEquals('the same list', Length(before), FChart.List.Count);
    for i := 0 to FChart.List.Count - 1 do
      if (FChart.List.Element(i).Style.FillColor <> before[i].Style.FillColor)
        or (FChart.List.Element(i).Z2 <> before[i].Z2)
        or (Hex(FChart.List.Element(i).Shape.Bounds.Left) <> Hex(before[i].Shape.Bounds.Left)) then
        Fail(Format('element %d changed', [i]));
    AssertNotNull('the copy', FChart.HoverLayerForTest);
    AssertEquals('one copy', 1, FChart.HoverLayerForTest.Count);
    AssertEquals('of row 5', 5, FChart.HoverLayerForTest.Element(0).Datum.DataIndex);
    AssertTrue('lifted', FChart.HoverLayerForTest.Element(0).Style.FillColor
      <> before[0].Style.FillColor);
    FChart.DispatchAction('{"type":"downplay","seriesIndex":0,"dataIndex":5}');
    FChart.Layered(bmp.Canvas, Rect(0, 0, cW, cH));
    AssertEquals('no state patch leaving it', patches, TyAdvChartStPatchesForTest);
    AssertNull('no copy', FChart.HoverLayerForTest);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartHoverLayerTest.TestALabelledSymbolIsLiftedInItsLayer;
var item: TTyStItem;
begin
  { a symbol whose label any state shows has a textContent: past the
    threshold all the same its own element takes the state (z2, scale) }
  NewChart('{"animation":false,"hoverLayerThreshold":1,"xAxis":{"type":"value"},'
    + '"yAxis":{"type":"value"},"series":[{"type":"scatter","symbolSize":10,'
    + '"emphasis":{"label":{"show":true}},"data":[[1,2],[3,4]]}]}');
  FChart.DispatchAction('{"type":"highlight","seriesIndex":0,"dataIndex":1}');
  Draw;
  AssertNull('no hover layer', FChart.HoverLayerForTest);
  AssertTrue(FChart.ItemStates(0, 1, item));
  AssertFalse('not on it', item.Host.InHover);
  AssertEquals('emphasis', 'emphasis', TyStNamesText(item.Host.States));
  AssertEquals('lifted by 10 in its layer', 10, Round(item.Host.Cur.Num[stkZ2]
    - item.Host.Rest.Num[stkZ2]));
end;

{ ==================== the fresh list ==================== }

procedure TAdvChartListFreshTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
end;

procedure TAdvChartListFreshTest.TearDown;
begin
  TyAdvChartListFreshForTest(True);
  TyAdvChartListTailForTest(True);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartListFreshTest.NewChart(AW, AH: Integer; AMode: TTyChartAnimationMode;
  const AOption: string): THlProbe;
begin
  Result := THlProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.AnimationMode := AMode;
  Result.AnimNow := 1000;
  { the tooltip's clock stands with the animation's: no real time }
  Result.TooltipNow := 1000;
  Result.ProgressiveStepCostMs := 1;
  Result.SetBounds(0, 0, AW, AH);
  Result.Option := AOption;
end;

function Frame(B: TBitmap): RawByteString;
var
  y, n: Integer;
begin
  n := B.Width * 3;
  SetLength(Result, n * B.Height);
  for y := 0 to B.Height - 1 do
    Move(B.ScanLine[y]^, Result[1 + y * n], n);
end;

{ the paint list as a text: each element's kind, place in the order, box,
  inks, visibility and words }
function ListSig(AChart: THlProbe): string;
var
  L: TTyPaintList;
  i: Integer;
  pe: PTyChartElement;
begin
  L := AChart.List;
  if L = nil then Exit('nil');
  Result := IntToStr(L.Count);
  for i := 0 to L.Count - 1 do
  begin
    pe := L.Ref(L.PaintOrder(i));
    Result := Result + Format('|%d %d %d %s %s %s %s %x %x %s %d %d %s',
      [Ord(pe^.Shape.Kind), pe^.Z, pe^.Z2, Hex(pe^.Shape.Bounds.Left),
       Hex(pe^.Shape.Bounds.Top), Hex(pe^.Shape.Bounds.Right), Hex(pe^.Shape.Bounds.Bottom),
       pe^.Style.FillColor, pe^.Style.StrokeColor, Hex(pe^.Style.Alpha),
       Ord(pe^.Ignore), Ord(pe^.ProgHidden), pe^.Caption.Text]);
  end;
end;

const
  cFreshW = 480;
  cFreshH = 360;

function FreshOptions(AIndex: Integer): string;
var
  sb: TStringBuilder;
  i, j: Integer;
begin
  sb := TStringBuilder.Create;
  try
    case AIndex of
      0:
        begin
          sb.Append('{"legend": {}, "tooltip": {"trigger": "axis"}, "xAxis": {"type": "category", "data": [');
          for i := 0 to 59 do
          begin
            if i > 0 then sb.Append(',');
            sb.Append('"c' + IntToStr(i) + '"');
          end;
          sb.Append(']}, "yAxis": {"type": "value"}, "dataZoom": [{"type": "inside"}, {"type": "slider"}],');
          sb.Append(' "series": [{"name": "a", "type": "bar", "data": [');
          for i := 0 to 59 do
          begin
            if i > 0 then sb.Append(',');
            sb.Append(IntToStr(5 + (i * 37) mod 90));
          end;
          sb.Append(']}, {"name": "b", "type": "line", "data": [');
          for i := 0 to 59 do
          begin
            if i > 0 then sb.Append(',');
            sb.Append(IntToStr(10 + (i * 53) mod 70));
          end;
          sb.Append(']}]}');
        end;
      1:
        begin
          sb.Append('{"tooltip": {}, "xAxis": {"type": "category"}, "yAxis": {"type": "category"},');
          sb.Append(' "dataZoom": [{"type": "slider"}], "visualMap": {"min": 0, "max": 1, "calculable": true,');
          sb.Append(' "orient": "horizontal", "left": "center", "top": 0},');
          sb.Append(' "series": [{"type": "heatmap", "progressive": 60, "progressiveThreshold": 100, "data": [');
          for i := 0 to 19 do
            for j := 0 to 19 do
            begin
              if (i > 0) or (j > 0) then sb.Append(',');
              sb.Append(Format('[%d,%d,%s]', [i, j, FloatToStr(((i * 7 + j * 13) mod 20) / 20)]));
            end;
          sb.Append(']}]}');
        end;
    else
      sb.Append('{"legend": {}, "series": [{"type": "pie", "radius": "50%", "selectedMode": "single",');
      sb.Append(' "data": [{"name": "p", "value": 3}, {"name": "q", "value": 5}, {"name": "r", "value": 7},');
      sb.Append(' {"name": "s", "value": 2}]}]}');
    end;
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

function FreshActions(AIndex: Integer): TStringArray;
begin
  case AIndex of
    0: Result := TStringArray.Create(
         '{"type": "dataZoom", "start": 20, "end": 60}',
         '{"type": "dataZoom", "start": 30, "end": 70}',
         '{"type": "legendToggleSelect", "name": "b"}',
         '{"type": "highlight", "seriesIndex": 0, "dataIndex": 30}',
         '{"type": "legendToggleSelect", "name": "b"}',
         '{"type": "downplay", "seriesIndex": 0, "dataIndex": 30}',
         '{"type": "dataZoom", "start": 0, "end": 100}',
         { the slider under the pointer, dragged, left }
         'move:120,335', 'move:240,335', 'move:395,335', 'drag:240,335,300,335',
         'drag:395,335,350,335', 'move:200,150', 'leave');
    1: Result := TStringArray.Create(
         { a cell hovered, its box up, then the window moves under it }
         'move:220,180',
         '{"type": "dataZoom", "start": 40, "end": 60}',
         '{"type": "dataZoom", "start": 41, "end": 61}',
         '{"type": "highlight", "seriesIndex": 0, "dataIndex": 3}',
         'move:200,160',
         '{"type": "dataZoom", "start": 0, "end": 100}',
         'move:150,150', 'move:220,180', 'move:240,335', 'drag:240,335,280,335',
         'move:160,330', 'leave');
  else
    Result := TStringArray.Create(
      '{"type": "legendToggleSelect", "name": "q"}',
      '{"type": "select", "seriesIndex": 0, "dataIndex": 2}',
      '{"type": "legendToggleSelect", "name": "q"}');
  end;
end;

procedure TAdvChartListFreshTest.TestAFreshListIsTheBuiltList;
var
  frames: array[Boolean] of TStringList;
  fresh: Boolean;
  chart: THlProbe;
  bmp: TBitmap;
  o, a, k, t, n0, used: Integer;
  mode: TTyChartAnimationMode;
  acts: TStringArray;

  procedure Snap(const AWhat: string);
  begin
    chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
    frames[fresh].Add(AWhat);
    frames[fresh].Add(Frame(bmp));
    frames[fresh].Add(ListSig(chart));
  end;

  { an action, or the pointer: move:x,y drag:x0,y0,x1,y1 leave }
  procedure Act(const A: string);
  var p: TStringArray;
  begin
    if Copy(A, 1, 5) = 'move:' then
    begin
      p := Copy(A, 6, MaxInt).Split([',']);
      chart.Move(StrToInt(p[0]), StrToInt(p[1]));
    end
    else if Copy(A, 1, 5) = 'drag:' then
    begin
      p := Copy(A, 6, MaxInt).Split([',']);
      chart.Drag(StrToInt(p[0]), StrToInt(p[1]), StrToInt(p[2]), StrToInt(p[3]));
    end
    else if A = 'leave' then chart.Leave
    else chart.DispatchAction(A);
  end;

begin
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(cFreshW, cFreshH);
    used := 0;
    for o := 0 to 2 do
      for mode := Low(TTyChartAnimationMode) to High(TTyChartAnimationMode) do
      begin
        if not (mode in [camOff, camAlways]) then Continue;
        frames[False].Clear;
        frames[True].Clear;
        for fresh := False to True do
        begin
          TyAdvChartListFreshForTest(fresh);
          TyAdvChartListTailForTest(fresh);
          n0 := TyAdvChartListFreshesForTest;
          chart := NewChart(cFreshW, cFreshH, mode, FreshOptions(o));
          try
            Snap('first');
            k := 0;
            while chart.ProgressiveUnfinished and (k < 100) do
            begin
              chart.ProgressTick;
              Snap('chunk');
              Inc(k);
            end;
            acts := FreshActions(o);
            for a := 0 to High(acts) do
            begin
              Act(acts[a]);
              Snap(acts[a]);
              { the update's animation, frame by frame, and the chunks }
              for t := 1 to 6 do
              begin
                chart.AnimNow := 1000 + a * 10000 + t * 150;
                chart.TooltipNow := chart.AnimNow;
                chart.TooltipTick(chart.AnimNow);
                chart.AnimTick(chart.AnimNow);
                if chart.ProgressiveUnfinished then chart.ProgressTick;
                Snap(Format('%s +%d', [acts[a], t]));
              end;
              chart.AnimNow := 1000 + (a + 1) * 10000;
              chart.TooltipNow := chart.AnimNow;
              chart.TooltipTick(chart.AnimNow);
              chart.AnimTick(chart.AnimNow);
              k := 0;
              while chart.ProgressiveUnfinished and (k < 100) do
              begin
                chart.ProgressTick;
                Inc(k);
              end;
              Snap(acts[a] + ' settled');
            end;
            if fresh then Inc(used, TyAdvChartListFreshesForTest - n0)
            else AssertEquals('switched off: none drawn as it stands', n0, TyAdvChartListFreshesForTest);
          finally
            chart.Free;
          end;
        end;
        AssertEquals(Format('option %d mode %d: as many frames', [o, Ord(mode)]),
          frames[False].Count, frames[True].Count);
        for k := 0 to frames[False].Count - 1 do
          if frames[False][k] <> frames[True][k] then
          begin
            if k mod 3 = 0 then
              Fail(Format('option %d mode %d: step "%s" against "%s"', [o, Ord(mode),
                frames[False][k], frames[True][k]]))
            else if k mod 3 = 1 then
              Fail(Format('option %d mode %d: the frame of %s differs', [o, Ord(mode),
                frames[False][k - 1]]))
            else
              Fail(Format('option %d mode %d: the list of %s differs', [o, Ord(mode),
                frames[False][k - 2]]));
          end;
      end;
    AssertTrue(Format('the fresh list was drawn (%d)', [used]), used >= 20);
  finally
    frames[False].Free;
    frames[True].Free;
    bmp.Free;
  end;
end;

procedure TAdvChartListFreshTest.TestAnUpdateBuildsOnce;
var
  chart: THlProbe;
  bmp: TBitmap;
  b0: Integer;
  fresh: Boolean;
  drag: array[Boolean] of Integer;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(cFreshW, cFreshH);
    for fresh := False to True do
    begin
      TyAdvChartListFreshForTest(fresh);
      TyAdvChartListTailForTest(fresh);
      chart := NewChart(cFreshW, cFreshH, camOff, FreshOptions(0));
      try
        chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
        { a dataZoom step: the update builds the list, the paint draws it
          [was: thrown away by DzSyncLayout and built again by the paint] }
        b0 := TyAdvChartListBuildsForTest;
        chart.DispatchAction('{"type": "dataZoom", "start": 20, "end": 60}');
        chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
        if fresh then
          AssertEquals('a dataZoom step builds the list once', b0 + 1, TyAdvChartListBuildsForTest)
        else
          AssertEquals('switched off: twice', b0 + 2, TyAdvChartListBuildsForTest);
        { a legend toggle, the same }
        b0 := TyAdvChartListBuildsForTest;
        chart.DispatchAction('{"type": "legendToggleSelect", "name": "b"}');
        chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
        if fresh then
          AssertEquals('a legend toggle builds the list once', b0 + 1, TyAdvChartListBuildsForTest)
        else
          AssertEquals('switched off: twice', b0 + 2, TyAdvChartListBuildsForTest);
        { a drag of the slider's window: an update a step, the slider's own
          view the list's end }
        b0 := TyAdvChartListBuildsForTest;
        chart.Drag(240, 335, 300, 335);
        chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
        drag[fresh] := TyAdvChartListBuildsForTest - b0;
      finally
        chart.Free;
      end;
    end;
    AssertTrue(Format('a drag builds less (%d against %d)', [drag[True], drag[False]]),
      (drag[True] >= 1) and (drag[True] < drag[False]));
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartListFreshTest.TestTheFirstIndicatorBuildsNoList;
var
  chart: THlProbe;
  bmp: TBitmap;
  b0, t0, k: Integer;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(cFreshW, cFreshH);
    chart := NewChart(cFreshW, cFreshH, camOff, FreshOptions(1));
    try
      chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
      while chart.ProgressiveUnfinished do
      begin
        chart.ProgressTick;
        chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
      end;
      { the first hover over a cell: the indicator shows and the handle
        labels blur -- the visual map's own elements, the list's end alone
        [was: the blur dropped the whole list, every cell built again] }
      b0 := TyAdvChartListBuildsForTest;
      t0 := TyAdvChartListTailsForTest;
      for k := 0 to 5 do
      begin
        chart.Move(120 + k * 31, 140 + (k mod 3) * 37);
        chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
        AssertEquals(Format('no list built by move %d', [k]), b0, TyAdvChartListBuildsForTest);
      end;
      AssertTrue('its end built again', TyAdvChartListTailsForTest > t0);
      { off the chart: the indicator and the slider's hover go, the list's
        end alone [was: DzViewUpdate dropped the whole list] }
      chart.Leave;
      chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
      AssertEquals('no list built leaving', b0, TyAdvChartListBuildsForTest);
    finally
      chart.Free;
    end;
  finally
    bmp.Free;
  end;
end;

{ [r2v] A STATE PATCH REFUSED AFTER AN UPDATE: the update's list is no
  longer the one to draw -- the paint builds it with the states, the same
  frames as with the fresh list switched off }
procedure TAdvChartListFreshTest.TestARefusedPatchAfterAnUpdateBuilds;
var
  frames: array[Boolean] of TStringList;
  fresh: Boolean;
  chart: THlProbe;
  bmp: TBitmap;
  k: Integer;
begin
  frames[False] := TStringList.Create;
  frames[True] := TStringList.Create;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(cFreshW, cFreshH);
    for fresh := False to True do
    begin
      TyAdvChartListFreshForTest(fresh);
      TyAdvChartListTailForTest(fresh);
      chart := NewChart(cFreshW, cFreshH, camOff, FreshOptions(0));
      try
        chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
        TyAdvChartStPatchForTest(False);
        try
          { the update builds its list; a highlight before the paint }
          chart.DispatchAction('{"type": "legendToggleSelect", "name": "b"}');
          chart.DispatchAction('{"type": "highlight", "seriesIndex": 0, "dataIndex": 30}');
          chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
          frames[fresh].Add(Frame(bmp));
          frames[fresh].Add(ListSig(chart));
          chart.DispatchAction('{"type": "downplay", "seriesIndex": 0, "dataIndex": 30}');
          chart.Layered(bmp.Canvas, Rect(0, 0, cFreshW, cFreshH));
          frames[fresh].Add(Frame(bmp));
          frames[fresh].Add(ListSig(chart));
        finally
          TyAdvChartStPatchForTest(True);
        end;
      finally
        chart.Free;
      end;
    end;
    AssertEquals('as many records', frames[False].Count, frames[True].Count);
    for k := 0 to frames[False].Count - 1 do
      AssertTrue(Format('record %d: the same with the fresh list on', [k]),
        frames[False][k] = frames[True][k]);
    AssertTrue('the highlight is drawn', frames[True][0] <> frames[True][2]);
  finally
    frames[False].Free;
    frames[True].Free;
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartHoverLayerOracleTest);
  RegisterTest(TAdvChartHoverLayerTest);
  RegisterTest(TAdvChartListFreshTest);
finalization
  FreeAndNil(GFix);
end.
