unit test.advchart.visualmapchannels;
{$mode objfpc}{$H+}
{ The rest of a visualMap's channels -- the partial colours, symbol,
  symbolSize and liftZ -- on the marks they reach, and the controller's
  symbolSize on the component's own bar and handles, held to ECharts 6.1.

  tools/advchart-oracle/visualmap-channels.js runs the real build and
  records zrender's modifyHSL / modifyAlpha directly, and per chart every
  row's final item visuals and the symbol element upstream actually drew
  (fill, stroke, opacity, size, z2); for a controller symbolSize, the bar's
  points and each handle's matrix and label.

  EXACT, and the quantised colour of each drawn element packed here rather
  than by the port. The per-datum series -- pie, funnel, radar, gauge,
  graph -- and the legend swatches that stand for their data are held the
  same way: every slice, ring, pointer and node as drawn. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Shape, tyControls.AdvChart.VisualMap,
     tyControls.AdvChart.VisualMapView, tyControls.AdvChart.Legend,
     tyControls.AdvChart.Symbol,
     tyControls.AdvanceChart;
type
  TVmcProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartVisualMapChannelsOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVmcProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure CheckSeries(ASeries: TJSONObject);
    procedure CheckController(ARec: TJSONObject);
    procedure CheckDatumSeries(ASeries: TJSONObject);
    procedure CheckLegend(ARec: TJSONObject);
    procedure RunCases(const AIds: array of string; ADatum: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestModifyHslIsZrenders;
    procedure TestEveryCartesianRowAsUpstreamDrawsIt;
    procedure TestEveryDatumSeriesAsUpstreamDrawsIt;
    procedure TestTheRadarSymbolDefaultIsUpstreams;
  end;

implementation

type
  TTyChartElementArray = array of TTyChartElement;

const
  cCartesian: array[0..10] of string = ('C1', 'C2', 'C4a', 'C4b', 'C4c', 'C5a',
    'C5b', 'C5c', 'C5d', 'C6', 'L1');
  cDatum: array[0..11] of string = ('C3a', 'C3b', 'C3c', 'C7a', 'C7b', 'C7c',
    'C7d', 'C7e', 'R1', 'R2', 'G1', 'GL');

procedure TVmcProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TVmcProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-visualmap-channels.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A: Double; const AHex: string): Boolean;
var b: Double;
begin
  b := FromHex(AHex);
  if IsNan(A) or IsNan(b) then Exit(IsNan(A) and IsNan(b));
  if (A = 0) and (b = 0) then Exit(True);
  Result := Bits(A) = Bits(b);
end;

function SameColour(const C: TTyVisualColor; AObj: TJSONObject): Boolean;
begin
  if AObj.Booleans['undef'] then Exit(not C.Defined);
  Result := C.Defined and (C.R = AObj.Integers['r'])
    and (C.G = AObj.Integers['g']) and (C.B = AObj.Integers['b'])
    and SameNum(C.A, AObj.Strings['a']);
end;

{ packed here, not by the port }
function PackFix(AObj: TJSONData): TTyChartColor;
  function B(A: Double): Cardinal;
  begin
    Result := Cardinal(Floor(A + 0.5));
  end;
var o: TJSONObject;
begin
  if (AObj = nil) or (AObj.JSONType <> jtObject) then Exit(0);
  o := TJSONObject(AObj);
  if o.Booleans['undef'] then Exit(0);
  Result := TTyChartColor((B(FromHex(o.Strings['a']) * 255) shl 24)
    or (B(o.Integers['r']) shl 16) or (B(o.Integers['g']) shl 8)
    or B(o.Integers['b']));
end;

{ a recorded number, or nought where the field is null }
function HexOr0(AData: TJSONData): Double;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := 0
  else Result := FromHex(AData.AsString);
end;

function Str(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := ''
  else Result := AData.AsString;
end;

procedure TAdvChartVisualMapChannelsOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartVisualMapChannelsOracleTest.Num(const AWhat: string;
  AGot: Double; const AHex: string);
begin
  Inc(FCompared);
  if not SameNum(AGot, AHex) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartVisualMapChannelsOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TVmcProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartVisualMapChannelsOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartVisualMapChannelsOracleTest.TestModifyHslIsZrenders;
var
  arr: TJSONArray;
  h: TJSONObject;
  i: Integer;
  c, r: TTyVisualColor;
begin
  arr := TJSONObject(FRoot).Arrays['hsl'];
  AssertTrue('hsl rows', arr.Count >= 10);
  for i := 0 to arr.Count - 1 do
  begin
    h := arr.Objects[i];
    FName := h.Strings['id'] + ' ' + h.Strings['note'];
    AssertTrue(FName + ' parses', TyVisualTryParse(h.Strings['color'], c));
    { modifyAlpha(c, null) is undefined upstream; a mapping never hands it a
      null -- a NaN at worst -- so the port has no such call }
    if (h.Strings['fn'] = 'modifyAlpha') and (h.Find('alpha').JSONType = jtNull) then
      Continue;
    if h.Strings['fn'] = 'modifyAlpha' then
      r := TyVisualModifyAlpha(c, FromHex(h.Strings['alpha']))
    else
      r := TyVisualModifyHSL(c, HexOr0(h.Find('h')), HexOr0(h.Find('s')),
        HexOr0(h.Find('l')),
        h.Find('h').JSONType <> jtNull, h.Find('s').JSONType <> jtNull,
        h.Find('l').JSONType <> jtNull);
    Inc(FCompared);
    if not SameColour(r, h.Objects['result']) then
      Miss(Format('%s upstream, (%s,%s,%s,%s) here', [h.Objects['result'].Strings['css'],
        Fmt(r.R), Fmt(r.G), Fmt(r.B), Fmt(r.A)]));
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ:' + FReport, 0, FBad);
end;

procedure TAdvChartVisualMapChannelsOracleTest.CheckSeries(ASeries: TJSONObject);
var
  rows: TJSONArray;
  r, drawn: TJSONObject;
  si, i, k, raw, found: Integer;
  typ, sym: string;
  lst: TTyPaintList;
  e, el: TTyChartElement;
  row: TTyVisualRow;
  sz, w, lo, hi, wantAlpha: Double;
  wantFill, wantStroke: TTyChartColor;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  if (ASeries.Find('filtered') <> nil) and ASeries.Booleans['filtered'] then Exit;
  rows := ASeries.Arrays['rows'];
  lst := FChart.List;
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Objects[i];
    raw := r.Integers['i'];
    { THE ROW, as the visual pipeline wrote it: liftZ exactly }
    if FChart.VisualRow(si, raw, row) and (r.Find('liftZ') <> nil)
      and (r.Find('liftZ').JSONType <> jtNull) then
    begin
      Inc(FCompared);
      if not (row.LiftZSet and SameNum(row.LiftZ, r.Strings['liftZ'])) then
        Miss(Format('s%d row %d: liftZ %s upstream', [si, raw, r.Strings['liftZText']]));
    end;
    { THE MARK, as drawn }
    found := 0;
    el := Default(TTyChartElement);
    if lst <> nil then
      for k := 0 to lst.Count - 1 do
      begin
        e := lst.Element(k);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
          or (e.Datum.RawDataIndex <> raw) or (e.Datum.DataIndex < 0) then Continue;
        if e.Caption.FontSizeLogical > 0 then Continue;
        if e.Shape.Kind = cskPolyline then Continue;
        Inc(found);
        el := e;
      end;
    drawn := nil;
    if (r.Find('drawn') <> nil) and (r.Find('drawn').JSONType = jtObject) then
      drawn := r.Objects['drawn'];
    Inc(FCompared);
    if typ = 'bar' then
    begin
      if found <> 1 then
      begin
        Miss(Format('s%d row %d: %d bars here', [si, raw, found]));
        Continue;
      end;
      wantFill := PackFix(r.Find('fill'));
      if r.Find('opacity').JSONType = jtNull then wantAlpha := 1
      else wantAlpha := FromHex(r.Strings['opacity']);
      if (el.Style.FillColor <> wantFill) or (el.Style.Alpha <> wantAlpha) then
        Miss(Format('s%d row %d: bar $%.8x @%s here, $%.8x @%s upstream (%s)', [si, raw,
          el.Style.FillColor, Fmt(el.Style.Alpha), wantFill, Fmt(wantAlpha),
          r.Objects['fill'].Strings['css']]));
      Continue;
    end;
    { a symbol: none is nothing drawn }
    sym := Str(r.Find('symbol'));
    { a symbol of no size is an element upstream and here too -- it paints
      nothing and carries its label [Batch 71: it was dropped here] }
    if (drawn <> nil) and (sym <> 'none') and (r.Arrays['symbolSize'].Count = 1)
      and (FromHex(r.Arrays['symbolSize'].Strings[0]) = 0) then
    begin
      Inc(FCompared);
      if found <> 1 then
        Miss(Format('s%d row %d: %d elements for a symbol of no size', [si, raw, found]));
      Continue;
    end;
    if (drawn = nil) or (sym = 'none') then
    begin
      if found > 0 then Miss(Format('s%d row %d: drawn here, not upstream', [si, raw]));
      Continue;
    end;
    if found <> 1 then
    begin
      Miss(Format('s%d row %d: %d symbols here (%s)', [si, raw, found, sym]));
      Continue;
    end;
    wantFill := PackFix(drawn.Find('fill'));
    wantStroke := PackFix(drawn.Find('stroke'));
    if (el.Style.HasFill and (el.Style.FillColor <> wantFill))
      or ((not el.Style.HasFill) and (wantFill shr 24 <> 0)) then
      Miss(Format('s%d row %d: fill $%.8x here, $%.8x upstream', [si, raw,
        el.Style.FillColor, wantFill]));
    Inc(FCompared);
    if (drawn.Find('stroke').JSONType = jtObject)
      and (el.Style.StrokeColor <> wantStroke) then
      Miss(Format('s%d row %d: stroke $%.8x here, $%.8x upstream', [si, raw,
        el.Style.StrokeColor, wantStroke]));
    Inc(FCompared);
    if not SameNum(el.Style.Alpha, drawn.Strings['opacity']) then
      Miss(Format('s%d row %d: alpha %s here, %s upstream', [si, raw,
        Fmt(el.Style.Alpha), drawn.Strings['opacityText']]));
    { THE SIZE: a round or square symbol is exactly its box }
    if ((sym = 'circle') or (sym = 'emptyCircle') or (sym = 'rect')
      or (sym = 'emptyRect')) and (r.Arrays['symbolSize'].Count = 1) then
    begin
      sz := FromHex(r.Arrays['symbolSize'].Strings[0]);
      if el.Shape.Kind = cskCircle then w := 2 * el.Shape.R1
      else if el.Shape.Kind = cskPolygon then
      begin
        lo := Infinity;
        hi := NegInfinity;
        for k := 0 to High(el.Shape.Points) do
        begin
          lo := Min(lo, el.Shape.Points[k].X);
          hi := Max(hi, el.Shape.Points[k].X);
        end;
        w := hi - lo;
      end
      else w := el.Shape.Bounds.Right - el.Shape.Bounds.Left;
      Inc(FCompared);
      { a polygon's corners are absolute, so its width is a subtraction of two
        centre-plus-halves: exact to the last bit only for a circle }
      if IsNan(w) or ((el.Shape.Kind <> cskPolygon) and (w <> sz))
        or ((el.Shape.Kind = cskPolygon) and (Abs(w - sz) > 1e-9 * Max(1, sz))) then
        Miss(Format('s%d row %d: %s wide here, %s upstream', [si, raw, Fmt(w), Fmt(sz)]));
    end;
    { liftZ over a symbol's own z2, which is 100 (Symbol.ts:85) }
    if (r.Find('liftZ') <> nil) and (r.Find('liftZ').JSONType <> jtNull) then
    begin
      Inc(FCompared);
      if el.Z2 <> 100 + Round(FromHex(r.Strings['liftZ'])) then
        Miss(Format('s%d row %d: z2 %d here, lifted %s upstream', [si, raw, el.Z2,
          r.Strings['liftZText']]));
    end;
  end;
end;

procedure TAdvChartVisualMapChannelsOracleTest.CheckController(ARec: TJSONObject);
var
  L: TTyVisualMapLayout;
  hs: TJSONArray;
  h, k: Integer;

  procedure Points(const AWhat: string; const AGot: TTyPointFArray; AArr: TJSONArray);
  var i: Integer;
  begin
    Inc(FCompared);
    if Length(AGot) <> AArr.Count then
    begin
      Miss(AWhat + ': point count');
      Exit;
    end;
    for i := 0 to AArr.Count - 1 do
    begin
      Num(Format('%s %d x', [AWhat, i]), AGot[i].X, AArr.Arrays[i].Strings[0]);
      Num(Format('%s %d y', [AWhat, i]), AGot[i].Y, AArr.Arrays[i].Strings[1]);
    end;
  end;

begin
  L := FChart.VisualMapLayout(ARec.Integers['vm']);
  Inc(FCompared);
  if not L.Valid then
  begin
    Miss('the component is not laid out');
    Exit;
  end;
  Points('out of range', L.OutPoints, ARec.Objects['outOfRange'].Arrays['points']);
  Points('in range', L.InPoints, ARec.Objects['inRange'].Arrays['points']);
  if (ARec.Find('handles') = nil) or (ARec.Find('handles').JSONType <> jtArray) then
  begin
    Inc(FCompared);
    if Length(L.Handles) > 0 then Miss('handles here, none upstream');
    Exit;
  end;
  hs := ARec.Arrays['handles'];
  Inc(FCompared);
  if Length(L.Handles) <> hs.Count then
  begin
    Miss(Format('%d handles upstream, %d here', [hs.Count, Length(L.Handles)]));
    Exit;
  end;
  for h := 0 to hs.Count - 1 do
  begin
    for k := 0 to 5 do
      Num(Format('handle %d matrix %d', [h, k]), L.Handles[h].Thumb[k],
        hs.Objects[h].Objects['thumb'].Arrays['toGroup'].Strings[k]);
    Inc(FCompared);
    if L.Handles[h].Label_.Text <> hs.Objects[h].Objects['label'].Strings['string'] then
      Miss(Format('handle %d label "%s" here', [h, L.Handles[h].Label_.Text]));
    Num(Format('handle %d label x', [h]), L.Handles[h].Label_.X,
      hs.Objects[h].Objects['label'].Strings['x']);
    Num(Format('handle %d label y', [h]), L.Handles[h].Label_.Y,
      hs.Objects[h].Objects['label'].Strings['y']);
  end;
end;

procedure TAdvChartVisualMapChannelsOracleTest.TestEveryCartesianRowAsUpstreamDrawsIt;
begin
  RunCases(cCartesian, False);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 300);
end;

procedure TAdvChartVisualMapChannelsOracleTest.TestEveryDatumSeriesAsUpstreamDrawsIt;
begin
  RunCases(cDatum, True);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 200);
end;

procedure TAdvChartVisualMapChannelsOracleTest.TestTheRadarSymbolDefaultIsUpstreams;
var
  cases: TJSONArray;
  s: TJSONObject;
  c: Integer;
  spec: TTySymbolSpec;
  e: Boolean;
  p: string;
begin
  { the series-level symbol upstream resolved for R2, which writes none }
  cases := TJSONObject(FRoot).Arrays['cases'];
  s := nil;
  for c := 0 to cases.Count - 1 do
    if cases.Objects[c].Strings['id'] = 'R2' then
      s := cases.Objects[c].Arrays['series'].Objects[0];
  AssertTrue('R2 recorded', s <> nil);
  spec := TySymbolDefault('radar');
  AssertTrue('the kind', spec.Kind = TySymbolKindOf(s.Strings['symbol'], e, p));
  AssertEquals('solid, not a ring', e, spec.Empty);
  AssertTrue('the size ' + s.Arrays['symbolSizeText'].Strings[0],
    SameNum(spec.WidthPx, s.Arrays['symbolSize'].Strings[0])
    and SameNum(spec.HeightPx, s.Arrays['symbolSize'].Strings[0]));
end;

procedure TAdvChartVisualMapChannelsOracleTest.RunCases(const AIds: array of string;
  ADatum: Boolean);
const
  cPalette = '["#5070dd","#b6d634","#505372","#ff994d","#0ca8df","#ffd10a",'
    + '"#fb628b","#785db0","#3fbe95"]';
var
  cases, ser, ctl: TJSONArray;
  cs, opt: TJSONObject;
  d: TJSONData;
  sl: TStringList;
  c, k, j: Integer;
  wanted: Boolean;

  procedure Upstream(AVm: TJSONObject);
  begin
    if AVm.Find('contentColor') = nil then AVm.Add('contentColor', '#5070dd');
    if AVm.Find('inactiveColor') = nil then AVm.Add('inactiveColor', '#cfd2d7');
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    wanted := False;
    for j := 0 to High(AIds) do
      if cs.Strings['id'] = AIds[j] then wanted := True;
    if not wanted then Continue;
    FName := cs.Strings['id'];
    if cs.Find('option').JSONType = jtObject then
      opt := TJSONObject(cs.Objects['option'].Clone)
    else
    begin
      sl := TStringList.Create;
      try
        sl.LoadFromFile(GalleryPath(cs.Strings['gallery']));
        opt := TJSONObject(GetJSON(sl.Text));
      finally
        sl.Free;
      end;
    end;
    try
      if opt.Find('color') = nil then opt.Add('color', GetJSON(cPalette));
      if opt.Find('gradientColor') = nil then
        opt.Add('gradientColor', GetJSON('["rgba(212,220,247,1)","#5070dd"]'));
      d := opt.Find('visualMap');
      if (d <> nil) and (d.JSONType = jtObject) then Upstream(TJSONObject(d))
      else if (d <> nil) and (d.JSONType = jtArray) then
        for k := 0 to TJSONArray(d).Count - 1 do
          if TJSONArray(d).Items[k].JSONType = jtObject then
            Upstream(TJSONObject(TJSONArray(d).Items[k]));
      FChart.Option := opt.AsJSON;
      AssertEquals(FName + ' parses', '', FChart.OptionError);
      FChart.SetBounds(0, 0, cs.Integers['width'], cs.Integers['height']);
      try
        FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cs.Integers['width'],
          cs.Integers['height']), 96);
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Continue;
        end;
      end;
      ser := cs.Arrays['series'];
      for k := 0 to ser.Count - 1 do
        if ADatum then CheckDatumSeries(ser.Objects[k])
        else CheckSeries(ser.Objects[k]);
      if ADatum and (cs.Find('legend') <> nil) and (cs.Find('legend').JSONType = jtObject) then
        CheckLegend(cs.Objects['legend']);
      if (cs.Find('controllers') <> nil) and (cs.Find('controllers').JSONType = jtArray) then
      begin
        ctl := cs.Arrays['controllers'];
        for k := 0 to ctl.Count - 1 do
          CheckController(ctl.Objects[k]);
      end;
    finally
      opt.Free;
    end;
  end;
end;

{ every element of series ASi standing for raw row ARaw, captions aside }
function ElementsOf(AList: TTyPaintList; ASi, ARaw: Integer): TTyChartElementArray;
var k, n: Integer; e: TTyChartElement;
begin
  Result := nil;
  if AList = nil then Exit;
  for k := 0 to AList.Count - 1 do
  begin
    e := AList.Element(k);
    if e.Datum.IsEdge or (e.Datum.SeriesIndex <> ASi)
      or (e.Datum.RawDataIndex <> ARaw) then Continue;
    if e.Caption.FontSizeLogical > 0 then Continue;
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := e;
  end;
end;

procedure TAdvChartVisualMapChannelsOracleTest.CheckDatumSeries(ASeries: TJSONObject);
var
  rows, syms: TJSONArray;
  r, drawn: TJSONObject;
  si, i, k, raw, cnt: Integer;
  typ: string;
  els: TTyChartElementArray;
  want: TTyChartColor;
  wantA: Double;
  ok: Boolean;
begin
  si := ASeries.Integers['index'];
  typ := ASeries.Strings['type'];
  if (ASeries.Find('filtered') <> nil) and ASeries.Booleans['filtered'] then Exit;
  if ASeries.Find('rows').JSONType <> jtArray then Exit;
  rows := ASeries.Arrays['rows'];
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Objects[i];
    raw := r.Integers['i'];
    if (r.Find('drawn') = nil) or (r.Find('drawn').JSONType <> jtObject) then Continue;
    drawn := r.Objects['drawn'];
    els := ElementsOf(FChart.List, si, raw);
    Inc(FCompared);
    if (typ = 'pie') or (typ = 'funnel') then
    begin
      cnt := 0;
      for k := 0 to High(els) do
        if els[k].Shape.Kind in [cskSector, cskPolygon] then
        begin
          Inc(cnt);
          want := PackFix(drawn.Find('fill'));
          wantA := FromHex(drawn.Strings['opacity']);
          if (els[k].Style.FillColor <> want) or (els[k].Style.Alpha <> wantA) then
            Miss(Format('s%d row %d: $%.8x @%s here, $%.8x @%s upstream (%s)', [si, raw,
              els[k].Style.FillColor, Fmt(els[k].Style.Alpha), want, Fmt(wantA),
              drawn.Objects['fill'].Strings['css']]));
        end;
      { a slice of nothing is a zero-angle sector upstream: no picture, and
        none here }
      if (cnt = 0) and (r.Arrays['values'].Count > 0)
        and (FromHex(r.Arrays['values'].Objects[0].Strings['value']) = 0) then
        Continue;
      if cnt <> 1 then Miss(Format('s%d row %d: %d slices here', [si, raw, cnt]));
    end
    else if typ = 'radar' then
    begin
      ok := False;
      want := PackFix(drawn.Find('polylineStroke'));
      for k := 0 to High(els) do
        if (els[k].Shape.Kind = cskPolyline) or ((els[k].Shape.Kind = cskPolygon)
          and (els[k].Style.StrokeWidthLogical > 0)) then
          if els[k].Style.StrokeColor = want then ok := True;
      if not ok then Miss(Format('s%d row %d: no ring stroked $%.8x', [si, raw, want]));
      if (drawn.Find('polygonIgnore') <> nil) and not drawn.Booleans['polygonIgnore'] then
      begin
        Inc(FCompared);
        ok := False;
        want := PackFix(drawn.Find('polygonFill'));
        for k := 0 to High(els) do
          if (els[k].Shape.Kind = cskPolygon) and els[k].Style.HasFill
            and (els[k].Style.FillColor = want) then ok := True;
        if not ok then Miss(Format('s%d row %d: no area filled $%.8x', [si, raw, want]));
      end;
      { and every symbol in the ring's colour }
      if (drawn.Find('symbols') <> nil) and (drawn.Find('symbols').JSONType = jtArray) then
      begin
        syms := drawn.Arrays['symbols'];
        cnt := 0;
        for k := 0 to High(els) do
          if els[k].Shape.Kind in [cskCircle, cskRoundRect, cskRect, cskPath] then
          begin
            Inc(cnt);
            if syms.Count > 0 then
            begin
              want := PackFix(syms.Objects[0].Find('fill'));
              Inc(FCompared);
              if els[k].Style.FillColor <> want then
                Miss(Format('s%d row %d: symbol $%.8x here, $%.8x upstream', [si, raw,
                  els[k].Style.FillColor, want]));
              if (els[k].Shape.Kind = cskCircle) and (syms.Objects[0].Find('scaleX') <> nil) then
              begin
                Inc(FCompared);
                if Abs(2 * els[k].Shape.R1 - FromHex(r.Arrays['symbolSize'].Strings[0])) > 1e-9 then
                  Miss(Format('s%d row %d: symbol %s wide here, %s upstream', [si, raw,
                    Fmt(2 * els[k].Shape.R1), r.Arrays['symbolSizeText'].Strings[0]]));
              end;
            end;
          end;
        Inc(FCompared);
        if cnt <> syms.Count then
          Miss(Format('s%d row %d: %d symbols here, %d upstream', [si, raw, cnt, syms.Count]));
      end;
    end
    else if typ = 'gauge' then
    begin
      ok := False;
      want := PackFix(drawn.Find('pointerFill'));
      for k := 0 to High(els) do
        if els[k].Style.HasFill and (els[k].Style.FillColor = want) then ok := True;
      if not ok then Miss(Format('s%d row %d: no pointer filled $%.8x', [si, raw, want]));
    end
    else if typ = 'graph' then
    begin
      ok := False;
      want := PackFix(drawn.Find('fill'));
      for k := 0 to High(els) do
        if els[k].Style.HasFill and (els[k].Style.FillColor = want) then ok := True;
      if not ok then
        Miss(Format('s%d node %d: not filled $%.8x (%s)', [si, raw, want,
          drawn.Objects['fill'].Strings['css']]));
    end;
  end;
end;

procedure TAdvChartVisualMapChannelsOracleTest.CheckLegend(ARec: TJSONObject);
var
  L: TTyLegendLayout;
  items: TJSONArray;
  it, icon: TJSONObject;
  i, k, found: Integer;
  want: TTyChartColor;
  wantA, gotA: Double;
begin
  L := FChart.LegendLayout(ARec.Integers['index']);
  items := ARec.Arrays['items'];
  for i := 0 to items.Count - 1 do
  begin
    it := items.Objects[i];
    if not it.Booleans['selected'] then Continue;
    if (it.Find('icon') = nil) or (it.Find('icon').JSONType <> jtObject) then Continue;
    icon := it.Objects['icon'];
    found := -1;
    for k := 0 to High(L.Items) do
      if L.Items[k].Name = it.Strings['name'] then
      begin
        found := k;
        Break;
      end;
    Inc(FCompared);
    if found < 0 then
    begin
      Miss(Format('legend item "%s" missing here', [it.Strings['name']]));
      Continue;
    end;
    want := PackFix(icon.Find('fill'));
    if icon.Find('opacity').JSONType = jtNull then wantA := 1
    else wantA := FromHex(icon.Strings['opacity']);
    if L.Items[found].HasOpacity then gotA := L.Items[found].Opacity else gotA := 1;
    if (L.Items[found].Colour <> want) or (gotA <> wantA) then
      Miss(Format('legend "%s": $%.8x @%s here, $%.8x @%s upstream', [it.Strings['name'],
        L.Items[found].Colour, Fmt(gotA), want, Fmt(wantA)]));
  end;
end;

initialization
  RegisterTest(TAdvChartVisualMapChannelsOracleTest);
end.
