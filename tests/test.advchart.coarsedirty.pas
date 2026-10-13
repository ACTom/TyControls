unit test.advchart.coarsedirty;
{$mode objfpc}{$H+}
{ The coarse pointer and the dirty-rectangle repaint, HELD TO UPSTREAM
  [Batch 142, roadmap D9].

  tools/advchart-oracle/coarse-dirty.js runs the real ECharts 6.1 build in
  node and records:
    samples  the points zrender's findHover asks about, in order, for a set
             of pointer sizes (a wrapped `contain` on a far candidate);
    coarse   what findHover finds on real charts with useCoarsePointer /
             pointerSize, probe by probe;
    dirty    for real zrender displayables on a canvas painter with
             useDirtyRect: every element as createRepaintRects reads it
             (flags, getPaintRect, getPrevPaintRect), frame by frame, and
             the rects it answered.

  The oracle class replays them through AdvChart.DirtyRect and the control's
  HitTestAt (text measured with zrender's SSR table, as upstream's layout
  was). The second class holds the control to its own contract: the
  dirty-rect path puts on the canvas exactly what the full path puts there,
  frame after frame -- hovers, tooltips, axis pointers, emphasis, blur, an
  enter animation, a roam -- and it does repaint less. }
interface
uses Classes, SysUtils, Math, TypInfo, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Events, tyControls.AdvChart.DirtyRect,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TCdProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Hover(AX, AY: Integer);
    procedure Leave;
    procedure Press(AX, AY: Integer);
    procedure Release(AX, AY: Integer);
    function List: TTyPaintList;
    function RepaintFull: Boolean;
    function RepaintRects: TTyZrRectArray;
    function Size: Integer;
  end;

  TAdvChartCoarseDirtyOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Bad(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; const AHex: string);
    procedure SameRect(const AWhat: string; const AGot: TTyXYWH; ARect: TJSONData);
    procedure Finish(const AWhat: string);
    function Ssr: ITyTextMeasurer;
    function ItemOf(AItem: TJSONObject; AInStorage: Boolean): TTyRepaintItem;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSamplesAreUpstreams;
    procedure TestTheCoarseHitsAreUpstreams;
    procedure TestThePaintRectsAreUpstreams;
    procedure TestTheRepaintRectsAreUpstreams;
  end;

  TAdvChartCoarseDirtyTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FA, FB: TCdProbe;
    FBmpA, FBmpB: TBGRABitmap;
    FW, FH, FPPI: Integer;
    FFrames, FPartial, FFull: Integer;
    FEvents: TStringList;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    function NewChart(const AOption: string; AW, AH: Integer): TCdProbe;
    { two charts of one option: A on the dirty-rect path, B on the full one }
    procedure Pair(const AOption: string; AW, AH: Integer; APPI: Integer = 96;
      AAnimate: Boolean = False);
    { one frame of both, onto their own canvases; every pixel compared }
    procedure Frame(const AWhat: string);
    procedure HoverBoth(AX, AY: Integer);
    procedure FreePair;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheInitOptionsDefaultToUpstreams;
    procedure TestTheSamplesScaleWithThePPI;
    procedure TestThePadIsLeftOutOnlyUnderACoarsePointer;
    procedure TestALargeBatchIsNeverACoarseTarget;
    procedure TestTheCoarseHitReachesTheMouseEvents;
    procedure TestDirtyEqualsFullOverHoversAndTooltips;
    procedure TestDirtyEqualsFullUnderAnAxisPointer;
    procedure TestDirtyEqualsFullOverEmphasisAndBlur;
    procedure TestDirtyEqualsFullThroughAnEnterAnimation;
    procedure TestAnUnboundedBatchUnderARectIsDrawnAgain;
    procedure TestDirtyEqualsFullThroughARoam;
    procedure TestDirtyEqualsFullAtTwiceThePPI;
    procedure TestAHoverRepaintsAroundTheBarOnly;
    procedure TestALayoutChangeRepaintsEverything;
    procedure TestTheDiffRules;
    procedure TestAnElementsPaintRect;
    procedure TestTheInkTiles;
    procedure TestAWindowFlushesOnceAndInvalidatesTheRects;
  end;

implementation

const
  cNulMark = #$E2#$90#$80;

{ ==================== helpers ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function XYWH(AX, AY, AW, AH: Double): TTyXYWH;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

function RectOfHex(AArr: TJSONData): TTyXYWH;
var a: TJSONArray;
begin
  a := TJSONArray(AArr);
  Result := XYWH(FromHex(a.Strings[0]), FromHex(a.Strings[1]),
    FromHex(a.Strings[2]), FromHex(a.Strings[3]));
end;

{ ==================== the probe ==================== }

function TCdProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TCdProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TCdProbe.Layered(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

procedure TCdProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TCdProbe.Leave;
begin
  MouseLeave;
end;

procedure TCdProbe.Press(AX, AY: Integer);
begin
  MouseDown(mbLeft, [ssLeft], AX, AY);
end;

procedure TCdProbe.Release(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TCdProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TCdProbe.RepaintFull: Boolean;
begin
  Result := LastRepaintFull;
end;

function TCdProbe.RepaintRects: TTyZrRectArray;
begin
  Result := LastRepaintRects;
end;

function TCdProbe.Size: Integer;
begin
  Result := CoarseSize;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartCoarseDirtyOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-coarse-dirty.json'));
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixturePath('advchart-text-style.json'));
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartCoarseDirtyOracleTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartCoarseDirtyOracleTest.Ssr: ITyTextMeasurer;
begin
  Result := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
end;

procedure TAdvChartCoarseDirtyOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then FReport := FReport + LineEnding + '  ' + AWhat;
end;

procedure TAdvChartCoarseDirtyOracleTest.SameHex(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if HexOf(AGot) <> AHex then
    Bad(Format('%s %s (%s), upstream %s (%s)', [AWhat, FloatToStr(AGot), HexOf(AGot),
      FloatToStr(FromHex(AHex)), AHex]));
end;

procedure TAdvChartCoarseDirtyOracleTest.SameRect(const AWhat: string;
  const AGot: TTyXYWH; ARect: TJSONData);
var a: TJSONArray;
begin
  if (ARect = nil) or (ARect.JSONType <> jtArray) then
  begin
    Inc(FCompared);
    Bad(AWhat + ': upstream has no rect');
    Exit;
  end;
  a := TJSONArray(ARect);
  SameHex(AWhat + '.x', AGot.X, a.Strings[0]);
  SameHex(AWhat + '.y', AGot.Y, a.Strings[1]);
  SameHex(AWhat + '.width', AGot.W, a.Strings[2]);
  SameHex(AWhat + '.height', AGot.H, a.Strings[3]);
end;

procedure TAdvChartCoarseDirtyOracleTest.Finish(const AWhat: string);
begin
  if GetEnvironmentVariable('TY_COARSEDIRTY_COUNTS') = '1' then
    WriteLn(StdErr, AWhat, ': ', FCompared, ' comparisons');
  AssertTrue(AWhat + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartCoarseDirtyOracleTest.TestTheSamplesAreUpstreams;
var
  cases, pts, rings: TJSONArray;
  c: TJSONObject;
  i, k, n, total: Integer;
  got: TTyDoubleArray;
begin
  cases := TJSONObject(FRoot).Arrays['samples'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    got := TyCoarseSamples(c.Integers['x'], c.Integers['y'], c.Floats['pointerSize']);
    pts := c.Arrays['pts'];
    rings := c.Arrays['rings'];
    total := 0;
    for k := 0 to rings.Count - 1 do total := total + rings.Integers[k];
    Inc(FCompared);
    if (Length(got) <> 2 * pts.Count) or (total <> pts.Count) then
    begin
      Bad(Format('%s: %d samples, upstream %d', [c.Strings['id'], Length(got) div 2, pts.Count]));
      Continue;
    end;
    for n := 0 to pts.Count - 1 do
    begin
      SameHex(Format('%s sample %d x', [c.Strings['id'], n]), got[2 * n],
        TJSONArray(pts.Items[n]).Strings[0]);
      SameHex(Format('%s sample %d y', [c.Strings['id'], n]), got[2 * n + 1],
        TJSONArray(pts.Items[n]).Strings[1]);
    end;
  end;
  Finish('samples');
end;

procedure TAdvChartCoarseDirtyOracleTest.TestTheCoarseHitsAreUpstreams;
var
  cases, probes: TJSONArray;
  c, init, p: TJSONObject;
  i, k, want, idx: Integer;
  chart: TCdProbe;
  d: TTyChartDatumRef;
  hit, uc: TJSONData;
  what: string;
begin
  cases := TJSONObject(FRoot).Arrays['coarse'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    init := c.Objects['init'];
    chart := TCdProbe.Create(FForm);
    try
      chart.Parent := FForm;
      chart.Controller := FCtl;
      chart.Measurer := Ssr;
      chart.SetBounds(0, 0, c.Integers['W'], c.Integers['H']);
      { echarts.init's options as the port's properties }
      uc := init.Find('useCoarsePointer');
      if uc = nil then chart.CoarsePointer := ccpAuto
      else if uc.JSONType = jtBoolean then
      begin
        if uc.AsBoolean then chart.CoarsePointer := ccpOn
        else chart.CoarsePointer := ccpOff;
      end
      else chart.CoarsePointer := ccpAuto;
      if init.Find('pointerSize') <> nil then
        chart.PointerSize := init.Integers['pointerSize'];
      chart.Option := c.Objects['option'].AsJSON;
      FBmp.SetSize(c.Integers['W'], c.Integers['H']);
      chart.Render(FBmp.Canvas, Rect(0, 0, c.Integers['W'], c.Integers['H']), 96);
      { the handler's pointer size: null is off, which is the port's 0 }
      Inc(FCompared);
      if c.Find('resolvedPointerSize').JSONType = jtNull then want := 0
      else want := c.Integers['resolvedPointerSize'];
      if (want > 0) <> (chart.Size > 0) then
        Bad(Format('%s: pointer size %d, upstream %d', [c.Strings['id'], chart.Size, want]))
      else if (want > 0) and (chart.Size <> want) then
        Bad(Format('%s: pointer size %d, upstream %d', [c.Strings['id'], chart.Size, want]));
      probes := c.Arrays['probes'];
      for k := 0 to probes.Count - 1 do
      begin
        p := probes.Objects[k];
        what := Format('%s (%d, %d) %s', [c.Strings['id'], p.Integers['x'],
          p.Integers['y'], p.Strings['aim']]);
        { WITH THE FALLBACK OFF the port's mouse keeps its pad round a symbol
          (HitPadLogical, a port deviation of long standing); upstream's
          answer is the list's own containment without it }
        if chart.Size > 0 then
          d := chart.HitTestAt(p.Integers['x'], p.Integers['y'])
        else
        begin
          idx := chart.List.HitTestElement(p.Integers['x'], p.Integers['y'], 96, False);
          if idx >= 0 then d := chart.List.Element(idx).Datum else d := TyChartNoDatum;
        end;
        hit := p.Find('hit');
        Inc(FCompared);
        if (hit = nil) or (hit.JSONType = jtNull) then
        begin
          if TyChartDatumValid(d) then
            Bad(Format('%s: hit series %d row %d, upstream nothing',
              [what, d.SeriesIndex, d.RawDataIndex]));
          Continue;
        end;
        if not TyChartDatumValid(d) then
        begin
          Bad(what + ': nothing, upstream ' + hit.AsJSON);
          Continue;
        end;
        if d.SeriesIndex <> TJSONObject(hit).Integers['s'] then
          Bad(Format('%s: series %d, upstream %s', [what, d.SeriesIndex, hit.AsJSON]))
        { a line's polyline names its series and no row upstream; the port
          names the nearest row -- the series is what is compared }
        else if (TJSONObject(hit).Find('d').JSONType <> jtNull)
          and (d.RawDataIndex <> TJSONObject(hit).Integers['d']) then
          Bad(Format('%s: row %d, upstream %s', [what, d.RawDataIndex, hit.AsJSON]));
      end;
    finally
      chart.Free;
    end;
  end;
  Finish('coarse hits');
end;

{ an element as the case defines it, its ops applied so far }
function DefBox(ADef: TJSONObject; out AHasFill: Boolean; out ALineWidth,
  ABlur, AOffX, AOffY: Double): TTyXYWH;
var
  shp, st: TJSONObject;
  d: TJSONData;
  hasStroke: Boolean;
begin
  shp := ADef.Objects['shape'];
  st := ADef.Objects['style'];
  if ADef.Strings['type'] = 'circle' then
    Result := TyRectToXYWH(TyShapeBounds(TyShapeCircle(shp.Floats['cx'], shp.Floats['cy'],
      shp.Floats['r'])))
  else
    Result := TyRectToXYWH(TyShapeBounds(TyShapeRect(TyRectF(shp.Floats['x'],
      shp.Floats['y'], shp.Floats['x'] + shp.Floats['width'],
      shp.Floats['y'] + shp.Floats['height']))));
  d := st.Find('fill');
  AHasFill := (d <> nil) and (d.JSONType = jtString) and (d.AsString <> 'none');
  d := st.Find('stroke');
  hasStroke := (d <> nil) and (d.JSONType = jtString) and (d.AsString <> 'none');
  ALineWidth := 1;
  if st.Find('lineWidth') <> nil then ALineWidth := st.Floats['lineWidth'];
  if not hasStroke then ALineWidth := 0;
  ABlur := 0;
  AOffX := 0;
  AOffY := 0;
  if st.Find('shadowBlur') <> nil then ABlur := st.Floats['shadowBlur'];
  if st.Find('shadowOffsetX') <> nil then AOffX := st.Floats['shadowOffsetX'];
  if st.Find('shadowOffsetY') <> nil then AOffY := st.Floats['shadowOffsetY'];
end;

procedure MergeInto(ATarget, ASource: TJSONObject);
var i, j: Integer;
begin
  for i := 0 to ASource.Count - 1 do
  begin
    j := ATarget.IndexOfName(ASource.Names[i]);
    if j >= 0 then ATarget.Delete(j);
    ATarget.Add(ASource.Names[i], ASource.Items[i].Clone);
  end;
end;

procedure TAdvChartCoarseDirtyOracleTest.TestThePaintRectsAreUpstreams;
var
  cases, frames, ops, list: TJSONArray;
  c, defs, fr, op, it, def: TJSONObject;
  i, f, k: Integer;
  box: TTyXYWH;
  hasFill: Boolean;
  lw, blur, ox, oy: Double;
  what: string;
begin
  cases := TJSONObject(FRoot).Arrays['dirty'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    defs := TJSONObject(c.Objects['elements'].Clone);
    try
      frames := c.Arrays['frames'];
      for f := 0 to frames.Count - 1 do
      begin
        fr := frames.Objects[f];
        ops := fr.Arrays['ops'];
        for k := 0 to ops.Count - 1 do
        begin
          op := ops.Objects[k];
          def := defs.Objects[op.Strings['el']];
          if op.Strings['op'] = 'style' then MergeInto(def.Objects['style'], op.Objects['style'])
          else if op.Strings['op'] = 'shape' then MergeInto(def.Objects['shape'], op.Objects['shape']);
        end;
        list := fr.Arrays['list'];
        for k := 0 to list.Count - 1 do
        begin
          it := list.Objects[k];
          def := defs.Objects[it.Strings['id']];
          what := Format('%s frame %d %s', [c.Strings['id'], f, it.Strings['id']]);
          box := DefBox(def, hasFill, lw, blur, ox, oy);
          { getBoundingRect: the stroke's allowance }
          if lw > 0 then box := TyGrowByStroke(box, hasFill, lw);
          SameRect(what + ' box', box, it.Find('box'));
          if it.Find('paint').JSONType <> jtNull then
            SameRect(what + ' paint', TyZrPaintRect(box, blur, ox, oy, 0), it.Find('paint'));
        end;
      end;
    finally
      defs.Free;
    end;
  end;
  Finish('paint rects');
end;

function TAdvChartCoarseDirtyOracleTest.ItemOf(AItem: TJSONObject;
  AInStorage: Boolean): TTyRepaintItem;
begin
  Result := Default(TTyRepaintItem);
  Result.ShouldPaint := AItem.Booleans['shouldPaint'];
  Result.Rendered := AItem.Booleans['rendered'];
  Result.Dirty := AItem.Booleans['dirty'];
  Result.InStorage := AItem.Booleans['inStorage'];
  Result.HasPaint := AItem.Find('paint').JSONType <> jtNull;
  if Result.HasPaint then Result.Paint := RectOfHex(AItem.Find('paint'));
  Result.HasPrev := AItem.Find('prevPaint').JSONType <> jtNull;
  if Result.HasPrev then Result.Prev := RectOfHex(AItem.Find('prevPaint'));
  if not AInStorage then Exit;
end;

procedure TAdvChartCoarseDirtyOracleTest.TestTheRepaintRectsAreUpstreams;
var
  cases, frames, list, prev, want: TJSONArray;
  c, fr: TJSONObject;
  i, f, k, dirty: Integer;
  items, prevs: TTyRepaintItemArray;
  got: TTyZrRectArray;
  rects: TJSONData;
  what: string;
begin
  cases := TJSONObject(FRoot).Arrays['dirty'];
  for i := 0 to cases.Count - 1 do
  begin
    c := cases.Objects[i];
    frames := c.Arrays['frames'];
    for f := 0 to frames.Count - 1 do
    begin
      fr := frames.Objects[f];
      what := Format('%s frame %d', [c.Strings['id'], f]);
      list := fr.Arrays['list'];
      prev := fr.Arrays['prev'];
      SetLength(items, list.Count);
      for k := 0 to list.Count - 1 do items[k] := ItemOf(list.Objects[k], True);
      SetLength(prevs, prev.Count);
      for k := 0 to prev.Count - 1 do prevs[k] := ItemOf(prev.Objects[k], True);
      rects := fr.Find('rects');
      Inc(FCompared);
      if rects.JSONType = jtNull then
      begin
        { the first paint is full upstream, and in the port }
        if f <> 0 then Bad(what + ': upstream painted everything after the first frame');
        Continue;
      end;
      if rects.JSONType = jtString then
      begin
        { not called: nothing was dirty -- and the transcription agrees there
          is nothing to repaint }
        dirty := 0;
        for k := 0 to High(items) do if items[k].Dirty then Inc(dirty);
        if dirty > 0 then Bad(what + ': dirty elements, upstream computed no rects');
        got := TyCreateRepaintRects(items, prevs);
        if Length(got) <> 0 then Bad(what + ': rects where upstream had none');
        Continue;
      end;
      want := TJSONArray(rects);
      got := TyCreateRepaintRects(items, prevs);
      if Length(got) <> want.Count then
      begin
        Bad(Format('%s: %d rects, upstream %d', [what, Length(got), want.Count]));
        Continue;
      end;
      for k := 0 to want.Count - 1 do
        SameRect(Format('%s rect %d', [what, k]), got[k], want.Items[k]);
    end;
  end;
  Finish('repaint rects');
end;

{ ==================== the control ==================== }

const
  cBarsTip =
    '{"animation":false,"tooltip":{},"xAxis":{"type":"category","data":["A","B","C","D","E"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","name":"Sales","data":[20,40,60,80,50]}]}';
  cBarsPlain =
    '{"animation":false,"xAxis":{"type":"category","data":["A","B","C","D","E"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","data":[20,40,60,80,50]}]}';
  cLineAxis =
    '{"animation":false,"tooltip":{"trigger":"axis","axisPointer":{"type":"cross"}},' +
    '"xAxis":{"type":"category","data":["A","B","C","D","E","F"]},"yAxis":{"type":"value"},' +
    '"series":[{"type":"line","data":[5,20,36,10,10,20]},' +
    '{"type":"bar","data":[3,12,20,8,6,11]}]}';
  cScatterPie =
    '{"animation":false,"tooltip":{},"grid":{"right":"55%"},' +
    '"xAxis":{"type":"value"},"yAxis":{"type":"value"},' +
    '"series":[{"type":"scatter","symbolSize":12,"emphasis":{"scale":1.6},' +
    '"data":[[1,2],[2,4],[3,1],[4,5],[5,3]]},' +
    '{"type":"pie","center":["75%","50%"],"radius":"30%",' +
    '"data":[{"name":"a","value":3},{"name":"b","value":5},{"name":"c","value":2}]}]}';
  cBlur =
    '{"animation":false,"legend":{},"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value"},' +
    '"series":[{"type":"bar","name":"one","emphasis":{"focus":"series"},"data":[5,8,3,6]},' +
    '{"type":"bar","name":"two","emphasis":{"focus":"series"},"data":[4,2,7,5]}]}';
  { a title over the plot: a bar's repaint goes under it }
  cTitleOver =
    '{"animation":false,"title":{"text":"Over the bars","left":"center","top":"middle"},' +
    '"xAxis":{"type":"category","data":["A","B","C","D","E"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","data":[90,90,90,90,90]}]}';
  cEnter =
    '{"tooltip":{},"xAxis":{"type":"category","data":["A","B","C","D"]},' +
    '"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"bar","data":[20,40,60,80]}]}';
  cGraph =
    '{"animation":false,"series":[{"type":"graph","layout":"none","roam":true,' +
    '"data":[{"name":"a","x":100,"y":100},{"name":"b","x":300,"y":120},' +
    '{"name":"c","x":200,"y":250}],' +
    '"links":[{"source":"a","target":"b"},{"source":"b","target":"c"}]}]}';

procedure TAdvChartCoarseDirtyTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FEvents := TStringList.Create;
end;

procedure TAdvChartCoarseDirtyTest.TearDown;
begin
  FreePair;
  FreeAndNil(FEvents);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartCoarseDirtyTest.OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if AEvent.HasParams then
    FEvents.Add(Format('%s %d %d', [AEvent.EventType, AEvent.Params.SeriesIndex,
      AEvent.Params.DataIndex]))
  else
    FEvents.Add(AEvent.EventType);
end;

function TAdvChartCoarseDirtyTest.NewChart(const AOption: string; AW, AH: Integer): TCdProbe;
begin
  Result := TCdProbe.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.TooltipNow := 0;
  Result.SetBounds(0, 0, AW, AH);
  Result.Option := AOption;
end;

procedure TAdvChartCoarseDirtyTest.FreePair;
begin
  FreeAndNil(FA);
  FreeAndNil(FB);
  FreeAndNil(FBmpA);
  FreeAndNil(FBmpB);
end;

procedure TAdvChartCoarseDirtyTest.Pair(const AOption: string; AW, AH, APPI: Integer;
  AAnimate: Boolean);
begin
  FreePair;
  FW := AW;
  FH := AH;
  FPPI := APPI;
  FA := NewChart(AOption, AW, AH);
  FB := NewChart(AOption, AW, AH);
  if AAnimate then
  begin
    FA.AnimationMode := camAlways;
    FB.AnimationMode := camAlways;
    FA.AnimNow := 1000;
    FB.AnimNow := 1000;
  end;
  FA.UseDirtyRect := True;
  FBmpA := TBGRABitmap.Create(AW, AH, BGRA(1, 2, 3, 255));
  FBmpB := TBGRABitmap.Create(AW, AH, BGRA(1, 2, 3, 255));
  FFrames := 0;
  FPartial := 0;
  FFull := 0;
end;

procedure TAdvChartCoarseDirtyTest.Frame(const AWhat: string);
var
  x, y, n: Integer;
  a, b: PBGRAPixel;
  first: string;
begin
  FA.Layered(FBmpA.Canvas, Rect(0, 0, FW, FH), FPPI);
  { THE FULL PATH paints every pixel of its canvas every frame: the canvas
    it is given is cleared to a colour no chart draws, so a pixel it did not
    paint would show }
  FBmpB.Fill(BGRA(1, 2, 3, 255));
  FB.Layered(FBmpB.Canvas, Rect(0, 0, FW, FH), FPPI);
  Inc(FFrames);
  if FA.RepaintFull then Inc(FFull) else Inc(FPartial);
  n := 0;
  first := '';
  for y := 0 to FH - 1 do
  begin
    a := FBmpA.ScanLine[y];
    b := FBmpB.ScanLine[y];
    for x := 0 to FW - 1 do
    begin
      if (a^.red <> b^.red) or (a^.green <> b^.green) or (a^.blue <> b^.blue) then
      begin
        if n = 0 then
          first := Format(' first at (%d, %d): dirty %d,%d,%d full %d,%d,%d',
            [x, y, a^.red, a^.green, a^.blue, b^.red, b^.green, b^.blue]);
        Inc(n);
      end;
      Inc(a);
      Inc(b);
    end;
  end;
  AssertEquals(AWhat + ': pixels the dirty path drew differently' + first, 0, n);
end;

procedure TAdvChartCoarseDirtyTest.HoverBoth(AX, AY: Integer);
begin
  FA.Hover(AX, AY);
  FB.Hover(AX, AY);
end;

procedure TAdvChartCoarseDirtyTest.TestTheInitOptionsDefaultToUpstreams;
var c: TCdProbe;
begin
  c := NewChart(cBarsPlain, 300, 200);
  try
    AssertTrue('useCoarsePointer: auto', c.CoarsePointer = ccpAuto);
    AssertEquals('pointerSize 44', 44, c.PointerSize);
    AssertFalse('useDirtyRect off', c.UseDirtyRect);
    { 'auto' on a desktop widgetset is a mouse }
    AssertFalse('a desktop build is no touch platform', TyTouchPlatform);
    AssertEquals('auto here: off', 0, c.Size);
    c.CoarsePointer := ccpOn;
    AssertEquals('on: 44', 44, c.Size);
    c.PointerSize := 0;
    AssertEquals('pointerSize 0 is falsy: off', 0, c.Size);
    c.PointerSize := -8;
    AssertEquals('a negative size reaches no ring: off', 0, c.Size);
  finally
    c.Free;
  end;
  AssertEquals('auto on a touch platform', 44, TyCoarsePointerSize(ccpAuto, 44, True));
  AssertEquals('off on a touch platform', 0, TyCoarsePointerSize(ccpOff, 44, True));
  AssertEquals('on with its own size', 30, TyCoarsePointerSize(ccpOn, 30, False));
end;

procedure TAdvChartCoarseDirtyTest.TestTheSamplesScaleWithThePPI;
var a, b: TTyDoubleArray; i: Integer;
begin
  a := TyCoarseSamples(100, 100, 44, 1);
  b := TyCoarseSamples(100, 100, 44, 2);
  AssertEquals('the same walk', Length(a), Length(b));
  AssertEquals('six rings of 25', 2 * 6 * 25, Length(a));
  for i := 0 to Length(a) div 2 - 1 do
  begin
    AssertEquals('x twice as far', 2 * (a[2 * i] - 100), b[2 * i] - 100, 1e-9);
    AssertEquals('y twice as far', 2 * (a[2 * i + 1] - 100), b[2 * i + 1] - 100, 1e-9);
  end;
end;

const
  cOneScatter =
    '{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},' +
    '"xAxis":{"type":"value","min":0,"max":100,"splitLine":{"show":false}},' +
    '"yAxis":{"type":"value","min":0,"max":100,"splitLine":{"show":false}},' +
    '"series":[{"type":"scatter","symbolSize":4,"data":[[50,50]]}]}';

procedure TAdvChartCoarseDirtyTest.TestThePadIsLeftOutOnlyUnderACoarsePointer;
var
  c: TCdProbe;
  bmp: TBGRABitmap;
  idx, cx, cy: Integer;
  b: TTyRectF;
begin
  { the symbol at (200, 150) in a 400 x 300 chart, 4 px wide }
  c := NewChart(cOneScatter, 400, 300);
  bmp := TBGRABitmap.Create(400, 300);
  try
    c.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    { 5 px off: inside the mouse's pad, outside upstream's circle }
    idx := c.List.HitTestElement(200, 155, 96, True);
    AssertTrue('a mouse reaches it with the pad', idx >= 0);
    AssertEquals('without the pad, as upstream', -1, c.List.HitTestElement(200, 155, 96, False));
    c.CoarsePointer := ccpOff;
    AssertTrue('a mouse: found directly', TyChartDatumValid(c.HitTestAt(200, 155)));
    c.CoarsePointer := ccpOn;
    AssertTrue('a finger: found by the rings', TyChartDatumValid(c.HitTestAt(200, 155)));
    { 9 px off: past the pad -- a mouse misses, a finger does not }
    c.CoarsePointer := ccpOff;
    AssertFalse('a mouse misses 9 px off', TyChartDatumValid(c.HitTestAt(200, 159)));
    c.CoarsePointer := ccpOn;
    AssertTrue('a finger finds 9 px off', TyChartDatumValid(c.HitTestAt(200, 159)));
    { 23 px off: a candidate no ring reaches }
    AssertFalse('23 px off: out of reach', TyChartDatumValid(c.HitTestAt(200, 173)));
    { AT TWICE THE PPI the rings are twice as wide: 18 device px is 9 logical }
    c.SetBounds(0, 0, 800, 600);
    bmp.SetSize(800, 600);
    c.Render(bmp.Canvas, Rect(0, 0, 800, 600), 192);
    idx := c.List.IndexOfDatum(0, 0);
    AssertTrue('the symbol', idx >= 0);
    b := TyShapeBounds(c.List.Element(idx).Shape);
    cx := Round((b.Left + b.Right) / 2);
    cy := Round((b.Top + b.Bottom) / 2);
    { the symbol keeps its 4 px (option geometry is not scaled by the PPI
      here); the pointer, a finger's size, is: logical px, as the pad }
    AssertTrue('192 PPI: 17 device px off is found', TyChartDatumValid(c.HitTestAt(cx, cy + 17)));
    AssertFalse('192 PPI: 46 device px off is not', TyChartDatumValid(c.HitTestAt(cx, cy + 46)));
  finally
    bmp.Free;
    c.Free;
  end;
end;

procedure TAdvChartCoarseDirtyTest.TestALargeBatchIsNeverACoarseTarget;
var
  c: TCdProbe;
  bmp: TBGRABitmap;
  i, large: Integer;
const
  cLarge =
    '{"animation":false,"grid":{"left":40,"right":40,"top":40,"bottom":40},' +
    '"xAxis":{"type":"value","min":0,"max":100},"yAxis":{"type":"value","min":0,"max":100},' +
    '"series":[{"type":"scatter","large":true,"largeThreshold":2,"symbolSize":4,' +
    '"data":[[50,50],[10,10],[90,90]]}]}';
begin
  c := NewChart(cLarge, 400, 300);
  bmp := TBGRABitmap.Create(400, 300);
  try
    c.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    large := 0;
    for i := 0 to c.List.Count - 1 do
      if c.List.Element(i).Shape.Kind = cskLarge then Inc(large);
    AssertEquals('one batch', 1, large);
    c.CoarsePointer := ccpOn;
    { ignoreCoarsePointer: 10 px off a batch's symbol finds nothing }
    AssertFalse('the batch is no candidate', TyChartDatumValid(c.HitTestAt(200, 160)));
    AssertEquals('nor at the list', -1, TyCoarseHitTest(c.List, 200, 160, 96, 44));
  finally
    bmp.Free;
    c.Free;
  end;
end;

procedure TAdvChartCoarseDirtyTest.TestTheCoarseHitReachesTheMouseEvents;
var
  c: TCdProbe;
  bmp: TBGRABitmap;
begin
  c := NewChart(cOneScatter, 400, 300);
  bmp := TBGRABitmap.Create(400, 300);
  try
    c.OnChartEvent := @OnEvent;
    c.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    c.Hover(200, 162);
    AssertEquals('a mouse 12 px off: no mouseover', -1, FEvents.IndexOf('mouseover 0 0'));
    c.Leave;
    c.Hover(10, 10);
    FEvents.Clear;
    c.CoarsePointer := ccpOn;
    c.Hover(200, 162);
    AssertTrue('a finger 12 px off: the symbol''s mouseover', FEvents.IndexOf('mouseover 0 0') >= 0);
  finally
    bmp.Free;
    c.Free;
  end;
end;

procedure TAdvChartCoarseDirtyTest.TestDirtyEqualsFullOverHoversAndTooltips;
var x: Integer;
begin
  Pair(cBarsTip, 420, 300);
  Frame('first');
  Frame('nothing changed');
  { across the bars, through the gaps, onto the axis, off the chart }
  x := 60;
  while x < 400 do
  begin
    HoverBoth(x, 200);
    Frame(Format('hover %d', [x]));
    Inc(x, 23);
  end;
  HoverBoth(250, 150);
  Frame('a bar from above');
  HoverBoth(251, 151);
  Frame('one px on');
  FA.Leave;
  FB.Leave;
  Frame('left');
  Frame('after');
  AssertTrue('the dirty path engaged: partial frames', FPartial >= 10);
end;

procedure TAdvChartCoarseDirtyTest.TestDirtyEqualsFullUnderAnAxisPointer;
var x: Integer;
begin
  Pair(cLineAxis, 480, 320);
  Frame('first');
  x := 70;
  while x < 460 do
  begin
    HoverBoth(x, 120 + (x mod 70));
    Frame(Format('pointer %d', [x]));
    Inc(x, 31);
  end;
  FA.Leave;
  FB.Leave;
  Frame('left');
  AssertTrue('the dirty path engaged', FPartial >= 8);
end;

procedure TAdvChartCoarseDirtyTest.TestDirtyEqualsFullOverEmphasisAndBlur;
var
  i: Integer;
  pts: array[0..9] of TPoint = ((X: 60; Y: 230), (X: 100; Y: 180), (X: 140; Y: 250),
    (X: 180; Y: 120), (X: 220; Y: 190), (X: 380; Y: 150), (X: 420; Y: 170),
    (X: 360; Y: 190), (X: 10; Y: 10), (X: 400; Y: 150));
begin
  Pair(cScatterPie, 520, 320);
  Frame('first');
  for i := 0 to High(pts) do
  begin
    HoverBoth(pts[i].X, pts[i].Y);
    Frame(Format('scatter / pie %d', [i]));
  end;
  Pair(cBlur, 480, 320);
  Frame('first');
  for i := 0 to 12 do
  begin
    HoverBoth(60 + i * 31, 200 + (i mod 3) * 20);
    Frame(Format('blur %d', [i]));
  end;
  { the legend's own hover }
  HoverBoth(200, 12);
  Frame('legend');
  HoverBoth(260, 12);
  Frame('legend 2');
  FA.Leave;
  FB.Leave;
  Frame('left');
  AssertTrue('the dirty path engaged', FPartial >= 5);
  { A TITLE OVER THE BARS: the rect under it is repainted with it on top }
  Pair(cTitleOver, 420, 300);
  Frame('first');
  for i := 0 to 8 do
  begin
    HoverBoth(80 + i * 37, 150);
    Frame(Format('under the title %d', [i]));
  end;
  AssertTrue('the dirty path engaged under the title', FPartial >= 5);
end;

procedure TAdvChartCoarseDirtyTest.TestDirtyEqualsFullThroughAnEnterAnimation;
var
  t: Integer;
  early: TBGRABitmap;
  x, y, moved: Integer;
begin
  Pair(cEnter, 420, 300, 96, True);
  Frame('armed');
  early := nil;
  try
    t := 1000;
    while t <= 2200 do
    begin
      Inc(t, 50);
      FA.AnimNow := t;
      FB.AnimNow := t;
      FA.AnimTick(t);
      FB.AnimTick(t);
      if t = 1400 then HoverBoth(180, 200);
      Frame(Format('tick %d', [t]));
      if t = 1100 then early := FBmpA.Duplicate as TBGRABitmap;
    end;
    HoverBoth(260, 120);
    Frame('at rest, hovered');
    { THE BARS GREW between the early frame and the last: the frames
      compared were frames of an animation }
    moved := 0;
    for y := 0 to FH - 1 do
      for x := 0 to FW - 1 do
        if early.GetPixel(x, y) <> FBmpA.GetPixel(x, y) then Inc(moved);
    AssertTrue('the animation moved the picture', moved > 500);
    AssertTrue('the ticks went the dirty way', FPartial >= 10);
  finally
    early.Free;
  end;
end;

{ [Milestone D9-D14] A LARGE BATCH HAS NO PAINT RECT (one element for every
  point), so the partial repaint draws it wherever it is -- unchanged, its
  points still sit over the bar the hover repaints, and leaving it out would
  paint the bar over them }
procedure TAdvChartCoarseDirtyTest.TestAnUnboundedBatchUnderARectIsDrawnAgain;
var k: Integer; pts: string;
begin
  pts := '';
  for k := 0 to 59 do
  begin
    if k > 0 then pts := pts + ',';
    pts := pts + Format('[%d,%d]', [k mod 4, 5 + (k * 7) mod 70]);
  end;
  Pair('{"animation":false,"xAxis":{"type":"category","data":["A","B","C","D"]},'
    + '"yAxis":{"type":"value","min":0,"max":100},'
    + '"series":[{"type":"bar","data":[50,70,60,80]},'
    + '{"type":"scatter","large":true,"largeThreshold":10,"symbolSize":6,'
    + '"itemStyle":{"color":"#000"},"data":[' + pts + ']}]}', 420, 300, 96);
  Frame('first');
  for k := 0 to 3 do
  begin
    HoverBoth(84 + k * 84, 200);
    Frame(Format('on bar %d', [k]));
  end;
  FA.Leave;
  FB.Leave;
  Frame('left');
  AssertTrue('the dirty path engaged', FPartial >= 3);
end;

procedure TAdvChartCoarseDirtyTest.TestDirtyEqualsFullThroughARoam;
var i: Integer;
begin
  Pair(cGraph, 420, 320);
  Frame('first');
  HoverBoth(100, 100);
  Frame('on a node');
  FA.Press(60, 280);
  FB.Press(60, 280);
  for i := 1 to 6 do
  begin
    HoverBoth(60 + i * 9, 280 - i * 5);
    Frame(Format('roam %d', [i]));
  end;
  FA.Release(114, 250);
  FB.Release(114, 250);
  Frame('released');
  AssertTrue('a roam step repaints everything', FFull >= 6);
end;

procedure TAdvChartCoarseDirtyTest.TestDirtyEqualsFullAtTwiceThePPI;
var x: Integer;
begin
  Pair(cBarsTip, 840, 600, 192);
  Frame('first');
  x := 120;
  while x < 800 do
  begin
    HoverBoth(x, 400);
    Frame(Format('hover %d', [x]));
    Inc(x, 57);
  end;
  AssertTrue('the dirty path engaged', FPartial >= 6);
end;

procedure TAdvChartCoarseDirtyTest.TestAHoverRepaintsAroundTheBarOnly;
var
  c: TCdProbe;
  bmp: TBGRABitmap;
  rects: TTyZrRectArray;
  i, bar: Integer;
  area: Double;
  r: TTyXYWH;
  el: TTyChartElement;
begin
  c := NewChart(cBarsPlain, 420, 300);
  bmp := TBGRABitmap.Create(420, 300);
  try
    c.UseDirtyRect := True;
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    AssertTrue('the first frame is full', c.RepaintFull);
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    AssertFalse('a frame with nothing new is not full', c.RepaintFull);
    AssertEquals('...and repaints nothing', 0, Length(c.RepaintRects));
    { the third bar }
    bar := c.List.IndexOfDatum(0, 2);
    AssertTrue('the bar', bar >= 0);
    el := c.List.Element(bar);
    c.Hover(Round((el.Shape.Bounds.Left + el.Shape.Bounds.Right) / 2),
      Round(el.Shape.Bounds.Bottom - 5));
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    AssertFalse('a hover is not full', c.RepaintFull);
    rects := c.RepaintRects;
    AssertTrue('a rect', Length(rects) >= 1);
    area := 0;
    for i := 0 to High(rects) do area := area + rects[i].W * rects[i].H;
    AssertTrue('a small part of the chart', area < 420 * 300 / 8);
    { the bar's rect is inside the repaint }
    AssertTrue('the bar is bounded', TyElementPaintRect(c.List.Element(bar), 96, r));
    AssertTrue('and repainted', TyZrRectIntersect(r, rects[0]));
    AssertTrue('wholly', (rects[0].X <= r.X) and (rects[0].Y <= r.Y)
      and (rects[0].X + rects[0].W >= r.X + r.W) and (rects[0].Y + rects[0].H >= r.Y + r.H));
    { and off again: the same rect }
    c.Hover(5, 5);
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    AssertFalse('leaving is not full', c.RepaintFull);
    AssertEquals('one rect', 1, Length(c.RepaintRects));
  finally
    bmp.Free;
    c.Free;
  end;
end;

procedure TAdvChartCoarseDirtyTest.TestALayoutChangeRepaintsEverything;
var
  c: TCdProbe;
  bmp: TBGRABitmap;
begin
  c := NewChart(cBarsPlain, 420, 300);
  bmp := TBGRABitmap.Create(420, 300);
  try
    c.UseDirtyRect := True;
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    AssertFalse('settled', c.RepaintFull);
    c.Option := cBarsTip;
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    AssertTrue('a new option: full', c.RepaintFull);
    c.SetBounds(0, 0, 400, 300);
    c.Layered(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    AssertTrue('a new size: full', c.RepaintFull);
    c.Layered(bmp.Canvas, Rect(0, 0, 400, 300), 120);
    AssertTrue('a new PPI: full', c.RepaintFull);
    c.UseDirtyRect := False;
    c.UseDirtyRect := True;
    c.Layered(bmp.Canvas, Rect(0, 0, 400, 300), 120);
    AssertTrue('switched on again: full', c.RepaintFull);
  finally
    bmp.Free;
    c.Free;
  end;
end;

procedure TAdvChartCoarseDirtyTest.TestTheDiffRules;
var
  a, b: TTyChartElement;
  s1, s2: TTyDirtySnap;
  rects: TTyZrRectArray;
  z: Double;
begin
  a := TyChartElement(TyShapePolyline([TyPointF(10, 10), TyPointF(40, 30)]));
  a.Style.StrokeWidthLogical := 2;
  a.Style.StrokeColor := $FF000000;
  a.Caption.Text := 'x';
  b := a;
  AssertTrue('a copy is the same', TyElementsSame(a, b));
  SetLength(b.Shape.Points, 2);
  b.Shape.Points := Copy(a.Shape.Points);
  b.Shape.Points[1].X := 41;
  AssertFalse('a point inside a dynamic array', TyElementsSame(a, b));
  b := a;
  b.Shape.Points := Copy(a.Shape.Points);
  AssertTrue('a copied array of the same points', TyElementsSame(a, b));
  b.Caption.Text := 'y';
  AssertFalse('a string', TyElementsSame(a, b));
  b := a;
  b.Style.Alpha := NaN;
  a.Style.Alpha := NaN;
  AssertTrue('NaN is NaN', TyElementsSame(a, b));
  z := 0;
  a.Style.Alpha := z;
  b.Style.Alpha := -z;
  AssertFalse('-0 is not 0 (an extra repaint, never a missed one)', TyElementsSame(a, b));
  a.Style.Alpha := 1;
  b := a;
  { the snapshots }
  SetLength(s1, 1);
  SetLength(s2, 1);
  s1[0].El := a;
  s1[0].Painted := True;
  s1[0].Bounded := TyElementPaintRect(a, 96, s1[0].Rect);
  s2[0] := s1[0];
  AssertTrue('unchanged', TyDirtyDiff(s1, s2, rects));
  AssertEquals('nothing to repaint', 0, Length(rects));
  SetLength(s2, 2);
  s2[1] := s1[0];
  AssertFalse('another length: everything', TyDirtyDiff(s1, s2, rects));
  SetLength(s2, 1);
  s2[0].El.Style.StrokeColor := $FFFF0000;
  AssertTrue('a restyle', TyDirtyDiff(s1, s2, rects));
  AssertEquals('one rect', 1, Length(rects));
  s2[0].El.GfxUnder := True;
  AssertFalse('a change under the axes: everything', TyDirtyDiff(s1, s2, rects));
  s2[0].El.GfxUnder := False;
  s2[0].Bounded := False;
  AssertFalse('a change nothing bounds: everything', TyDirtyDiff(s1, s2, rects));
  s2[0] := s1[0];
  s2[0].Bounded := False;
  s1[0].Bounded := False;
  AssertTrue('unchanged and unbounded: fine', TyDirtyDiff(s1, s2, rects));
  { a rich caption has no bound }
  b := a;
  SetLength(b.Caption.RtPieces, 1);
  AssertFalse('a rich caption', TyElementPaintRect(b, 96, s2[0].Rect));
end;

procedure TAdvChartCoarseDirtyTest.TestAnElementsPaintRect;
var
  el: TTyChartElement;
  r: TTyXYWH;
begin
  { a stroked rect: zrender's box (stroke grown), the port's pixel of
    antialiasing, then getPaintRect's floor / ceil }
  el := TyChartElement(TyShapeRect(TyRectF(10, 10, 30, 40)));
  el.Style.HasFill := True;
  el.Style.FillColor := $FFFF0000;
  el.Style.StrokeWidthLogical := 2;
  el.Style.StrokeColor := $FF000000;
  AssertTrue(TyElementPaintRect(el, 96, r));
  AssertEquals('x', 8, r.X, 0);
  AssertEquals('y', 8, r.Y, 0);
  AssertEquals('w', 25, r.W, 0);
  AssertEquals('h', 35, r.H, 0);
  { at 192 PPI the pen is 4 device px }
  AssertTrue(TyElementPaintRect(el, 192, r));
  AssertEquals('x at 192', 7, r.X, 0);
  AssertEquals('w at 192', 27, r.W, 0);
  { a polyline's mitred corner: 4.5 pens more on each side }
  el := TyChartElement(TyShapePolyline([TyPointF(10, 10), TyPointF(40, 10), TyPointF(10, 12)]));
  el.Style.StrokeWidthLogical := 2;
  el.Style.StrokeColor := $FF000000;
  AssertTrue(TyElementPaintRect(el, 96, r));
  { no fill: max(2, 5) = 5 -> x 7.5, then 9 more, then 1 }
  AssertEquals('mitre x', Floor(10 - 2.5 - 9 - 1), r.X, 0);
  { a caption: the text tolerance }
  el := TyChartElement(TyShapeRect(TyRectF(10, 10, 30, 20)));
  el.Caption.Text := 'label';
  el.Caption.FontName := 'x';
  AssertTrue(TyElementPaintRect(el, 96, r));
  { halo 0 + 1, the pixel, tolerance 10: 10 - 1 - 1 - 10 }
  AssertEquals('caption x', -2, r.X, 0);
  { a large batch has none }
  el := Default(TTyChartElement);
  el.Shape.Kind := cskLarge;
  AssertFalse('a large batch', TyElementPaintRect(el, 96, r));
end;

procedure TAdvChartCoarseDirtyTest.TestTheInkTiles;
var
  bmp: TBGRABitmap;
  rects: TTyZrRectArray;
begin
  bmp := TBGRABitmap.Create(100, 70, BGRAPixelTransparent);
  try
    rects := nil;
    TyInkTiles(bmp, 32, rects);
    AssertEquals('nothing inked', 0, Length(rects));
    bmp.SetPixel(40, 65, BGRA(0, 0, 0, 1));
    bmp.SetPixel(99, 0, BGRA(0, 0, 0, 255));
    TyInkTiles(bmp, 32, rects);
    AssertEquals('two tiles', 2, Length(rects));
    { row by row: the top-right tile first, cut at the bitmap's edge }
    AssertEquals('x', 96, rects[0].X, 0);
    AssertEquals('w cut', 4, rects[0].W, 0);
    AssertEquals('x 2', 32, rects[1].X, 0);
    AssertEquals('y 2', 64, rects[1].Y, 0);
    AssertEquals('h cut', 6, rects[1].H, 0);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartCoarseDirtyTest.TestAWindowFlushesOnceAndInvalidatesTheRects;
var
  c: TCdProbe;
  bmp: TBGRABitmap;
  bar: Integer;
  el: TTyChartElement;
begin
  c := NewChart(cBarsPlain, 420, 300);
  bmp := TBGRABitmap.Create(420, 300);
  try
    c.UseDirtyRect := True;
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    c.Layered(bmp.Canvas, Rect(0, 0, 420, 300), 96);
    AssertFalse('settled', c.RepaintFull);
    { A WINDOW NEEDS THE WIDGETSET, and initialising it here would move every
      later suite's text onto the real fonts (suite-order-widgetset-init):
      this runs when something before it initialised the widgetset, or when
      TY_COARSEDIRTY_WINDOW=1 asks for it in a run of its own }
    if not (AppInitialized in Application.Flags) then
    begin
      if GetEnvironmentVariable('TY_COARSEDIRTY_WINDOW') = '1' then Application.Initialize
      else Ignore('needs an initialised widgetset (TY_COARSEDIRTY_WINDOW=1)');
    end;
    { a window: the hover's frame is flushed by the queue, before any paint }
    FForm.HandleNeeded;
    c.HandleNeeded;
    AssertTrue('a handle', c.HandleAllocated);
    { settled at the window's own size and PPI: the handle's resize asked
      for a layout, which a full frame does }
    c.Invalidate;
    c.InvalidateFrame;
    Application.ProcessMessages;
    AssertTrue('the layout: a full frame', c.RepaintFull);
    c.InvalidateFrame;
    Application.ProcessMessages;
    AssertFalse('a settled window frame', c.RepaintFull);
    AssertEquals('...repaints nothing', 0, Length(c.RepaintRects));
    bar := c.List.IndexOfDatum(0, 1);
    el := c.List.Element(bar);
    c.Hover(Round((el.Shape.Bounds.Left + el.Shape.Bounds.Right) / 2),
      Round(el.Shape.Bounds.Bottom - 5));
    { TWO REQUESTS, ONE FLUSH: a second would find nothing new and report
      no rect }
    c.InvalidateFrame;
    c.InvalidateFrame;
    Application.ProcessMessages;
    AssertFalse('the flushed frame was a partial one', c.RepaintFull);
    AssertEquals('around the bar, once', 1, Length(c.RepaintRects));
  finally
    bmp.Free;
    c.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartCoarseDirtyOracleTest);
  RegisterTest(TAdvChartCoarseDirtyTest);
end.
