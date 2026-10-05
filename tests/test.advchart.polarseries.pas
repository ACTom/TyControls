unit test.advchart.polarseries;
{$mode objfpc}{$H+}
{ THE SERIES ON A POLAR, HELD TO UPSTREAM [Batch 113, C4].

  tools/advchart-oracle/polar-series.js runs the real ECharts 6.1 build in
  node (server-side, animation off, zrender's width table for text, TZ=UTC)
  and records, chart by chart:

    the polar    its centre, both axes' extents, inverse flags and scales --
                 now sized by the series on it, a bar's start, a stack's
                 sums, a dataZoom's window and a bar's containShape;
    bars         per view row: element or none, ignored (clipped past
                 itself) or drawn, the layout (unclipped) and the shape as
                 drawn, Sector or Sausage, the corners, no fill where the
                 sweep is nought, the path's own rect, the background, and
                 the label: its words, its place (the innerTransformable),
                 its turn and its two alignments;
    lines        the layout points, the stacked-on points, the polyline, the
                 clip sector, each symbol (kept or not, where) and its label;
    scatter      each symbol, kept or not, where;
    heatmap      nothing drawn;
    markers      each markPoint's and markLine's layout;
    dataZoom     the series it filtered (the raw rows left) and a slider's
                 place;
    pointer      at each probe: every polar axis showing a pointer, its
                 value and element, and the series rows the tooltip lists;
    conversions  convertToPixel / FromPixel / containPixel with series
                 finders;
    states       after each action, every bar's state list, fill, stroke,
                 width and opacity.

  This replays it through the control, bit for bit. Text is measured with
  zrender's width table. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Color,
     tyControls.AdvChart.Convert, tyControls.AdvChart.Polar,
     tyControls.AdvChart.PolarBar, tyControls.AdvChart.ZrPath,
     tyControls.AdvChart.Labels, tyControls.AdvChart.Marker,
     tyControls.AdvChart.DataZoomView, tyControls.AdvChart.States,
     tyControls.AdvanceChart, test.advchart.gridbounds,
     test.advchart.categoryminmax;
type
  TPolarSeriesProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Bars(ASeriesIndex: Integer): TTyPolarBarLayout;
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
    function PointerOf(const AHit: TTyAxisHit): Double;
    function Draw(const AHit: TTyAxisHit; AW, AH: Integer;
      out D: TTyPolarPointerDraw): Boolean;
    function States(ASeries, ARow: Integer; out AItem: TTyStItem): Boolean;
    procedure PointerTo(AX, AY: Integer);
  end;

  TAdvChartPolarSeriesTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPolarSeriesProbe;
    FRoot, FTable: TJSONData;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure RenderCase(ACase: TJSONObject);
    function Cases: TJSONArray;
    function CaseById(const AId: string): TJSONObject;
    procedure Finish(const AWhat: string; AMin: Integer);
    function FindEl(ARole: TTyChartAnimRole; ASeries, AIndex: Integer;
      out AEl: TTyChartElement): Integer;
    function FindLabel(AHostIndex: Integer; out AEl: TTyChartElement): Boolean;
    procedure CheckLabel(const AWhat: string; AHost: Integer; ARec: TJSONData);
    procedure CheckBars(ASeries: TJSONObject);
    procedure CheckLine(ASeries: TJSONObject);
    procedure CheckScatter(ASeries: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePolarsTakeTheirSeries;
    procedure TestPolarBarsAreUpstreams;
    procedure TestPolarLinesAndScatterAreUpstreams;
    procedure TestHeatmapOnAPolarDrawsNothing;
    procedure TestPolarMarkersAreUpstreams;
    procedure TestPolarDataZoomIsUpstreams;
    procedure TestThePointerSnapsToThePolarSeries;
    procedure TestSeriesFindersConvertOnTheirPolar;
    procedure TestPolarBarStatesAreUpstreams;
    { beyond the fixture }
    procedure TestPolarBarsAreDrawnAndHit;
    procedure TestAPolarLineIsCutToItsRing;
    procedure TestASeriesOnAMissingPolarSaysSo;
    procedure TestHoveringAPolarBarShowsItsTooltip;
  end;

implementation

{ ==================== the probe ==================== }

function TPolarSeriesProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TPolarSeriesProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TPolarSeriesProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TPolarSeriesProbe.Bars(ASeriesIndex: Integer): TTyPolarBarLayout;
begin
  Result := PolarBarOf(ASeriesIndex);
end;

function TPolarSeriesProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

function TPolarSeriesProbe.PointerOf(const AHit: TTyAxisHit): Double;
begin
  Result := PointerValue(AHit);
end;

function TPolarSeriesProbe.Draw(const AHit: TTyAxisHit; AW, AH: Integer;
  out D: TTyPolarPointerDraw): Boolean;
begin
  Result := PolarPointerGeometry(AHit, Rect(0, 0, AW, AH), NewTextMeasurer(96), 96, D);
end;

function TPolarSeriesProbe.States(ASeries, ARow: Integer; out AItem: TTyStItem): Boolean;
begin
  Result := ItemStates(ASeries, ARow, AItem);
end;

procedure TPolarSeriesProbe.PointerTo(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

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

function Txt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavTop: Result := 'top';
    tavBottom: Result := 'bottom';
  else
    Result := 'middle';
  end;
end;

function StrOrNull(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := '' else Result := AData.AsString;
end;

{ ==================== the case ==================== }

procedure TAdvChartPolarSeriesTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-polar-series.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-polar-series.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-grid-bounds.json'));
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartPolarSeriesTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FTable);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartPolarSeriesTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartPolarSeriesTest.Same(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    Bad(AWhat + ': upstream has no number');
    Exit;
  end;
  want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartPolarSeriesTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartPolarSeriesTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True), BoolToStr(AWant, True)]));
end;

procedure TAdvChartPolarSeriesTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
end;

function TAdvChartPolarSeriesTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

function TAdvChartPolarSeriesTest.CaseById(const AId: string): TJSONObject;
var i: Integer;
begin
  for i := 0 to Cases.Count - 1 do
    if Cases.Objects[i].Strings['id'] = AId then Exit(Cases.Objects[i]);
  Result := nil;
  Fail('no case ' + AId);
end;

procedure TAdvChartPolarSeriesTest.RenderCase(ACase: TJSONObject);
var
  bmp: TBGRABitmap;
  w, h: Integer;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TPolarSeriesProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  w := ACase.Integers['W'];
  h := ACase.Integers['H'];
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, w, h);
  bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, w, h), 96);
  finally
    bmp.Free;
  end;
end;

{ the insertion index of the element of this role for (series, row) }
function TAdvChartPolarSeriesTest.FindEl(ARole: TTyChartAnimRole; ASeries,
  AIndex: Integer; out AEl: TTyChartElement): Integer;
var
  i: Integer;
  l: TTyPaintList;
begin
  AEl := Default(TTyChartElement);
  Result := -1;
  l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
    if (l.Element(i).Anim.Role = ARole) and (l.Element(i).Anim.Series = ASeries)
      and (l.Element(i).Anim.Index = AIndex) then
    begin
      AEl := l.Element(i);
      Exit(i);
    end;
end;

{ the caption the expansion made for the host at AHostIndex }
function TAdvChartPolarSeriesTest.FindLabel(AHostIndex: Integer;
  out AEl: TTyChartElement): Boolean;
var
  i: Integer;
  l: TTyPaintList;
begin
  AEl := Default(TTyChartElement);
  Result := False;
  l := FChart.List;
  for i := 0 to l.Count - 1 do
    if (l.Element(i).Anim.Role = carLabel)
      and (l.Element(i).Caption.LmHostPlus1 = AHostIndex + 1) then
    begin
      AEl := l.Element(i);
      Exit(True);
    end;
end;

procedure TAdvChartPolarSeriesTest.CheckLabel(const AWhat: string; AHost: Integer;
  ARec: TJSONData);
var
  o: TJSONObject;
  cap: TTyChartElement;
  have: Boolean;
  want: string;
begin
  if (ARec = nil) or (ARec.JSONType = jtNull) then Exit;
  o := TJSONObject(ARec);
  have := (AHost >= 0) and FindLabel(AHost, cap) and not cap.Ignore;
  SameBool(AWhat + ' label drawn', have, o.Booleans['drawn']);
  if not (have and o.Booleans['drawn']) then Exit;
  SameStr(AWhat + ' label text', cap.Caption.Text, o.Strings['text']);
  Same(AWhat + ' label x', cap.Caption.LmBaseX + cap.Caption.LmOffX, o.Find('x'));
  Same(AWhat + ' label y', cap.Caption.LmBaseY + cap.Caption.LmOffY, o.Find('y'));
  { the turn the anchor is placed in (zrender's innerTransformable.rotation) }
  if cap.Caption.LmHasAttachedRot then
    Same(AWhat + ' label turn', cap.Caption.LmAttachedRot, o.Find('rot'))
  else
    Same(AWhat + ' label turn', 0, o.Find('rot'));
  Same(AWhat + ' label drawn turn', cap.Caption.RotationRad, o.Find('rot'));
  { zrender's isInside, which picks the ink }
  SameBool(AWhat + ' label inside', cap.Caption.LmInkInside, o.Booleans['inside']);
  { the position's alignment; the text's own over it -- an array position
    has none (null), the text then its left / top }
  want := StrOrNull(o.Find('dAlign'));
  if want <> '' then SameStr(AWhat + ' label position align', AlignName(cap.Caption.LmPosAH), want);
  want := StrOrNull(o.Find('dVa'));
  if want <> '' then SameStr(AWhat + ' label position vertical align', VAlignName(cap.Caption.LmPosAV), want);
  want := StrOrNull(o.Find('align'));
  if want = '' then want := StrOrNull(o.Find('dAlign'));
  if want = '' then want := 'left';
  SameStr(AWhat + ' label align', AlignName(cap.Caption.LmStyleAH), want);
  want := StrOrNull(o.Find('va'));
  if want = '' then want := StrOrNull(o.Find('dVa'));
  if want = '' then want := 'top';
  SameStr(AWhat + ' label vertical align', VAlignName(cap.Caption.LmStyleAV), want);
end;

{ ==================== the polar ==================== }

procedure TAdvChartPolarSeriesTest.TestThePolarsTakeTheirSeries;
var
  c, i, n: Integer;
  cs, rec: TJSONObject;
  p: TTyPolar;
  a, b: Double;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Find('threw') <> nil then Continue;
    RenderCase(cs);
    for i := 0 to cs.Arrays['polars'].Count - 1 do
    begin
      rec := cs.Arrays['polars'].Objects[i];
      FWhere := cs.Strings['id'] + ' polar' + IntToStr(rec.Integers['index']);
      p := FChart.PolarLayout(rec.Integers['index']);
      if p = nil then
      begin
        Bad('no polar');
        Continue;
      end;
      Inc(n);
      Same('cx', p.CX, rec.Find('cx'));
      Same('cy', p.CY, rec.Find('cy'));
      p.RadiusAxis.LocalExtent(a, b);
      Same('radius extent 0', a, rec.Arrays['rExtent'].Items[0]);
      Same('radius extent 1', b, rec.Arrays['rExtent'].Items[1]);
      p.AngleAxis.LocalExtent(a, b);
      Same('angle extent 0', a, rec.Arrays['aExtent'].Items[0]);
      Same('angle extent 1', b, rec.Arrays['aExtent'].Items[1]);
      SameBool('radius inverse', p.RadiusInverse, rec.Booleans['rInverse']);
      SameBool('angle inverse', p.AngleInverse, rec.Booleans['aInverse']);
      Same('radius scale 0', p.RadiusAxis.Scale.GetExtent.Start, rec.Arrays['rScale'].Items[0]);
      Same('radius scale 1', p.RadiusAxis.Scale.GetExtent.Stop, rec.Arrays['rScale'].Items[1]);
      Same('angle scale 0', p.AngleAxis.Scale.GetExtent.Start, rec.Arrays['aScale'].Items[0]);
      Same('angle scale 1', p.AngleAxis.Scale.GetExtent.Stop, rec.Arrays['aScale'].Items[1]);
    end;
  end;
  AssertTrue(Format('enough polars (%d)', [n]), n >= 70);
  Finish('the polar', 900);
end;

{ ==================== bars ==================== }

procedure TAdvChartPolarSeriesTest.CheckBars(ASeries: TJSONObject);
var
  items, bgs: TJSONArray;
  it, bgo: TJSONObject;
  i, si, k, at, bgAt: Integer;
  L: TTyPolarBarLayout;
  el, bg: TTyChartElement;
  cls, what: string;
  s: TTyPolarSector;
  corners: TTyDoubleArray;
  d: TJSONData;
  box: TTyXYWH;
  zp: TTyZrPath;
  lst: TTyPaintList;
  up4: array[0..3] of Double;
  t: Double;
begin
  si := ASeries.Integers['index'];
  L := FChart.Bars(si);
  SameBool('series ' + IntToStr(si) + ' solved', L.Solved, True);
  if not L.Solved then Exit;
  SameBool('radial', L.IsRadial, ASeries.Strings['base'] = 'angle');
  items := ASeries.Arrays['items'];
  Inc(FCompared);
  if Length(L.Rows) <> items.Count then
  begin
    Bad(Format('%d rows, upstream %d', [Length(L.Rows), items.Count]));
    Exit;
  end;
  for i := 0 to items.Count - 1 do
  begin
    it := items.Objects[i];
    what := Format('s%d i%d', [si, i]);
    { the layout, unclipped }
    if it.Find('layout').JSONType <> jtNull then
    begin
      Same(what + ' layout cx', L.Rows[i].CX, it.Arrays['layout'].Items[0]);
      Same(what + ' layout cy', L.Rows[i].CY, it.Arrays['layout'].Items[1]);
      Same(what + ' layout r0', L.Rows[i].R0, it.Arrays['layout'].Items[2]);
      Same(what + ' layout r', L.Rows[i].R, it.Arrays['layout'].Items[3]);
      Same(what + ' layout start', L.Rows[i].SA, it.Arrays['layout'].Items[4]);
      Same(what + ' layout end', L.Rows[i].EA, it.Arrays['layout'].Items[5]);
      SameBool(what + ' layout clockwise', L.Rows[i].CW, it.Booleans['layoutCw']);
    end;
    at := FindEl(carPolarBar, si, i, el);
    if (at >= 0) and (it.Find('raw') <> nil) then
    begin
      Inc(FCompared);
      if el.Datum.RawDataIndex <> it.Integers['raw'] then
        Bad(Format('%s raw row %d, upstream %d', [what, el.Datum.RawDataIndex, it.Integers['raw']]));
    end;
    if at < 0 then cls := 'none'
    else if el.Ignore then cls := 'hidden'
    else cls := 'drawn';
    SameStr(what + ' class', cls, it.Strings['cls']);
    if (at < 0) or (it.Strings['cls'] = 'none') then Continue;
    s.CX := el.Anim.G[0];
    s.CY := el.Anim.G[1];
    s.R0 := el.Anim.G[2];
    s.R := el.Anim.G[3];
    s.SA := el.Anim.G[4];
    s.EA := el.Anim.G[5];
    s.CW := el.Anim.G[6] <> 0;
    for k := 0 to 5 do
      Same(what + ' shape ' + IntToStr(k), el.Anim.G[k], it.Arrays['shape'].Items[k]);
    SameBool(what + ' clockwise', s.CW, it.Booleans['cw']);
    if el.Anim.G[8] <> 0 then SameStr(what + ' type', 'sausage', it.Strings['type'])
    else SameStr(what + ' type', 'sector', it.Strings['type']);
    SameBool(what + ' zero', el.Anim.G[9] <> 0, it.Booleans['zero']);
    SameBool(what + ' zero paints nothing', (el.Anim.G[9] <> 0)
      and not el.Style.HasFill and (el.Style.StrokeWidthLogical <= 0), it.Booleans['zero']);
    { THE CORNERS THE ELEMENT CARRIES against upstream's cornerRadius,
      normalised as roundSector reads it (a number is every corner, a list
      [v] is [v, v, 0, 0] ...), its two ends swapped where the sector runs
      anticlockwise, a negative none }
    d := it.Find('corner');
    for k := 0 to 3 do up4[k] := 0;
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      for k := 0 to 3 do up4[k] := FromHex(d.AsString);
      if not (up4[0] <> 0) then for k := 0 to 3 do up4[k] := 0;
    end
    else if (d <> nil) and (d.JSONType = jtArray) and (d.Count > 0) then
    begin
      case d.Count of
        1: begin up4[0] := FromHex(d.Items[0].AsString); up4[1] := up4[0]; end;
        2: begin up4[0] := FromHex(d.Items[0].AsString); up4[1] := up4[0];
             up4[2] := FromHex(d.Items[1].AsString); up4[3] := up4[2]; end;
        3: begin up4[0] := FromHex(d.Items[0].AsString); up4[1] := FromHex(d.Items[1].AsString);
             up4[2] := FromHex(d.Items[2].AsString); up4[3] := up4[2]; end;
      else
        for k := 0 to 3 do up4[k] := FromHex(d.Items[k].AsString);
      end;
    end;
    if not s.CW then
    begin
      t := up4[0]; up4[0] := up4[1]; up4[1] := t;
      t := up4[2]; up4[2] := up4[3]; up4[3] := t;
    end;
    for k := 0 to 3 do
    begin
      if not (up4[k] > 0) then up4[k] := 0;
      Inc(FCompared);
      if not SameBits(el.Shape.SectorRadii[k], up4[k]) then
        Bad(Format('%s corner %d %s, upstream %s', [what, k, Txt(el.Shape.SectorRadii[k]), Txt(up4[k])]));
    end;
    { the list the path is built from, out of the element's corners }
    SetLength(corners, 4);
    for k := 0 to 3 do corners[k] := el.Shape.SectorRadii[k];
    if not s.CW then
    begin
      corners[0] := el.Shape.SectorRadii[1]; corners[1] := el.Shape.SectorRadii[0];
      corners[2] := el.Shape.SectorRadii[3]; corners[3] := el.Shape.SectorRadii[2];
    end;
    { the path's own rect }
    if el.Anim.G[8] <> 0 then zp := TyZrSausagePath(s) else zp := TyZrSectorPath(s, corners);
    box := TyZrBBox(zp);
    Same(what + ' rect x', box.X, it.Arrays['rect'].Items[0]);
    Same(what + ' rect y', box.Y, it.Arrays['rect'].Items[1]);
    Same(what + ' rect w', box.W, it.Arrays['rect'].Items[2]);
    Same(what + ' rect h', box.H, it.Arrays['rect'].Items[3]);
    if it.Strings['cls'] = 'drawn' then CheckLabel(what, at, it.Find('label'));
  end;
  { the background, one per row }
  if (ASeries.Find('bg') <> nil) and (ASeries.Find('bg').JSONType = jtArray) then
  begin
    bgs := ASeries.Arrays['bg'];
    lst := FChart.List;
    for i := 0 to bgs.Count - 1 do
    begin
      if bgs.Items[i].JSONType = jtNull then Continue;
      bgo := bgs.Objects[i];
      what := Format('s%d bg%d', [si, i]);
      bgAt := -1;
      for k := 0 to lst.Count - 1 do
        if lst.Element(k).Silent and (lst.Element(k).Anim.Role = carNone)
          and (lst.Element(k).Shape.Kind = cskSector)
          and (lst.Element(k).Anim.Series = si) and (lst.Element(k).Anim.Index = i) then
        begin
          bgAt := k;
          Break;
        end;
      Inc(FCompared);
      if bgAt < 0 then
      begin
        Bad(what + ' none');
        Continue;
      end;
      bg := lst.Element(bgAt);
      for k := 0 to 5 do
        Same(what + ' shape ' + IntToStr(k), bg.Anim.G[k], bgo.Arrays['shape'].Items[k]);
    end;
  end;
end;

procedure TAdvChartPolarSeriesTest.TestPolarBarsAreUpstreams;
var
  c, k, n: Integer;
  cs, sr: TJSONObject;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Find('threw') <> nil then Continue;
    { every case's bars: a dataZoom's pinned ends or a pointer case's
      bands show only in where the bars land }
    RenderCase(cs);
    for k := 0 to cs.Arrays['series'].Count - 1 do
    begin
      sr := cs.Arrays['series'].Objects[k];
      if sr.Strings['type'] <> 'bar' then Continue;
      FWhere := cs.Strings['id'];
      Inc(n);
      CheckBars(sr);
    end;
  end;
  AssertTrue(Format('enough bar series (%d)', [n]), n >= 60);
  Finish('the bars', 8000);
end;

{ ==================== lines and scatter ==================== }

procedure TAdvChartPolarSeriesTest.CheckLine(ASeries: TJSONObject);
var
  si, i, at, k: Integer;
  el, sym: TTyChartElement;
  syms: TJSONArray;
  so: TJSONObject;
  what: string;
  clip: TJSONObject;
begin
  si := ASeries.Integers['index'];
  at := FindEl(carLineRun, si, -1, el);
  Inc(FCompared);
  if at < 0 then
  begin
    if ASeries.Find('polyline').JSONType <> jtNull then Bad(Format('s%d: no line', [si]));
    Exit;
  end;
  { the whole series' layout points, as upstream holds them }
  Inc(FCompared);
  if Length(el.Anim.Pts) <> ASeries.Arrays['points'].Count then
    Bad(Format('s%d: %d point numbers, upstream %d', [si, Length(el.Anim.Pts),
      ASeries.Arrays['points'].Count]))
  else
    for k := 0 to High(el.Anim.Pts) do
      Same(Format('s%d point %d', [si, k]), el.Anim.Pts[k], ASeries.Arrays['points'].Items[k]);
  if ASeries.Find('stacked').JSONType = jtArray then
  begin
    at := FindEl(carLineArea, si, -1, el);
    Inc(FCompared);
    if at < 0 then Bad(Format('s%d: no area', [si]))
    else if Length(el.Anim.Base) <> ASeries.Arrays['stacked'].Count then
      Bad(Format('s%d: %d base numbers, upstream %d', [si, Length(el.Anim.Base),
        ASeries.Arrays['stacked'].Count]))
    else
      for k := 0 to High(el.Anim.Base) do
        Same(Format('s%d base %d', [si, k]), el.Anim.Base[k], ASeries.Arrays['stacked'].Items[k]);
  end;
  { no end label on a polar, whatever the option asks }
  Inc(FCompared);
  for k := 0 to FChart.List.Count - 1 do
    if (FChart.List.Element(k).Anim.Role = carEndLabel)
      and (FChart.List.Element(k).Anim.Series = si) then
      Bad(Format('s%d: an end label on a polar', [si]));
  { THE POLYLINE AS DRAWN, where the series is one run (no hole): its
    vertices against upstream's shape.points -- a step would add some }
  at := FindEl(carLineRun, si, -1, el);
  if (ASeries.Find('polyline').JSONType = jtArray) and (Pos('7ff8', ASeries.Arrays['polyline'].AsJSON) = 0) then
  begin
    Inc(FCompared);
    if Length(el.Shape.Points) * 2 <> ASeries.Arrays['polyline'].Count then
      Bad(Format('s%d: %d drawn vertices, upstream %d', [si, Length(el.Shape.Points),
        ASeries.Arrays['polyline'].Count div 2]))
    else
      for k := 0 to High(el.Shape.Points) do
      begin
        Same(Format('s%d drawn %d x', [si, k]), el.Shape.Points[k].X, ASeries.Arrays['polyline'].Items[k * 2]);
        Same(Format('s%d drawn %d y', [si, k]), el.Shape.Points[k].Y, ASeries.Arrays['polyline'].Items[k * 2 + 1]);
      end;
  end;
  { the clip }
  clip := ASeries.Objects['clip'];
  SameBool(Format('s%d clip is a sector', [si]), el.HasClipSector, clip.Strings['type'] = 'sector');
  Same(Format('s%d clip cx', [si]), el.ClipCX, clip.Find('cx'));
  Same(Format('s%d clip cy', [si]), el.ClipCY, clip.Find('cy'));
  Same(Format('s%d clip r0', [si]), el.ClipR0, clip.Find('r0'));
  Same(Format('s%d clip r', [si]), el.ClipR1, clip.Find('r'));
  Same(Format('s%d clip start', [si]), el.ClipSA, clip.Find('sa'));
  Same(Format('s%d clip end', [si]), el.ClipEA, clip.Find('ea'));
  SameBool(Format('s%d clip clockwise', [si]), el.ClipCW, clip.Booleans['cw']);
  { the symbols }
  syms := ASeries.Arrays['symbols'];
  for i := 0 to syms.Count - 1 do
  begin
    so := syms.Objects[i];
    what := Format('s%d symbol %d', [si, i]);
    at := FindEl(carLineSymbol, si, i, sym);
    SameBool(what + ' drawn', at >= 0, so.Booleans['drawn']);
    if (at < 0) or not so.Booleans['drawn'] then Continue;
    Same(what + ' x', sym.Anim.G[0], so.Find('x'));
    Same(what + ' y', sym.Anim.G[1], so.Find('y'));
    CheckLabel(what, at, so.Find('label'));
  end;
end;

procedure TAdvChartPolarSeriesTest.CheckScatter(ASeries: TJSONObject);
var
  si, i, at: Integer;
  sym: TTyChartElement;
  syms: TJSONArray;
  so: TJSONObject;
  what: string;
  role: TTyChartAnimRole;
begin
  si := ASeries.Integers['index'];
  if ASeries.Strings['type'] = 'effectScatter' then role := carEffectSymbol
  else role := carSymbol;
  syms := ASeries.Arrays['symbols'];
  for i := 0 to syms.Count - 1 do
  begin
    so := syms.Objects[i];
    what := Format('s%d symbol %d', [si, i]);
    at := FindEl(role, si, i, sym);
    SameBool(what + ' drawn', at >= 0, so.Booleans['drawn']);
    if (at < 0) or not so.Booleans['drawn'] then Continue;
    Same(what + ' x', sym.Anim.G[5], so.Find('x'));
    Same(what + ' y', sym.Anim.G[6], so.Find('y'));
    CheckLabel(what, at, so.Find('label'));
  end;
end;

procedure TAdvChartPolarSeriesTest.TestPolarLinesAndScatterAreUpstreams;
var
  c, k, n: Integer;
  cs, sr: TJSONObject;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Find('threw') <> nil then Continue;
    RenderCase(cs);
    for k := 0 to cs.Arrays['series'].Count - 1 do
    begin
      sr := cs.Arrays['series'].Objects[k];
      FWhere := cs.Strings['id'];
      if sr.Strings['type'] = 'line' then
      begin
        Inc(n);
        CheckLine(sr);
      end
      else if (sr.Strings['type'] = 'scatter') or (sr.Strings['type'] = 'effectScatter') then
      begin
        Inc(n);
        CheckScatter(sr);
      end;
    end;
  end;
  AssertTrue(Format('enough series (%d)', [n]), n >= 20);
  Finish('the lines and the scatter', 700);
end;

procedure TAdvChartPolarSeriesTest.TestHeatmapOnAPolarDrawsNothing;
var
  cs: TJSONObject;
  i, n: Integer;
  l: TTyPaintList;
begin
  cs := CaseById('heatmap-polar');
  RenderCase(cs);
  AssertEquals('upstream draws none', 0, cs.Arrays['series'].Objects[0].Integers['drawn']);
  l := FChart.List;
  n := 0;
  for i := 0 to l.Count - 1 do
    if l.Element(i).Datum.SeriesIndex = 0 then Inc(n);
  AssertEquals('no heatmap cell', 0, n);
end;

{ ==================== the markers ==================== }

procedure TAdvChartPolarSeriesTest.TestPolarMarkersAreUpstreams;
var
  c, m, k, j, n, placed: Integer;
  cs, mk: TJSONObject;
  blk: TTyMkBlock;
  kind: TTyMarkerKind;
  items: TJSONArray;
  lay: TJSONData;
  pts: array of TTyPointF;
  ends: array of array[0..1] of TTyPointF;
begin
  n := 0;
  placed := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'marker' then Continue;
    FWhere := cs.Strings['id'];
    if cs.Find('threw') <> nil then
    begin
      { upstream throws on a polar markArea; the port builds no area and
        draws the rest }
      RenderCase(cs);
      blk := FChart.MarkerLayout(0, mkArea);
      Inc(FCompared);
      if blk.Present then Bad('a markArea built on a polar');
      Continue;
    end;
    RenderCase(cs);
    for m := 0 to cs.Arrays['markers'].Count - 1 do
    begin
      mk := cs.Arrays['markers'].Objects[m];
      if mk.Strings['kind'] = 'markPoint' then kind := mkPoint else kind := mkLine;
      blk := FChart.MarkerLayout(mk.Integers['series'], kind);
      items := mk.Arrays['items'];
      { the survivors, in order }
      pts := nil;
      ends := nil;
      if kind = mkPoint then
      begin
        for k := 0 to High(blk.Points) do
          if blk.Points[k].Survived then
          begin
            SetLength(pts, Length(pts) + 1);
            pts[High(pts)] := blk.Points[k].E.Point;
          end;
        Inc(FCompared);
        if Length(pts) <> items.Count then
        begin
          Bad(Format('%d points, upstream %d', [Length(pts), items.Count]));
          Continue;
        end;
        for k := 0 to items.Count - 1 do
        begin
          lay := items.Objects[k].Find('layout');
          Same(Format('point %d x', [k]), pts[k].X, lay.Items[0]);
          Same(Format('point %d y', [k]), pts[k].Y, lay.Items[1]);
          if not IsNan(pts[k].X) then Inc(placed);
          Inc(n);
        end;
      end
      else
      begin
        for k := 0 to High(blk.Lines) do
          if blk.Lines[k].Survived then
          begin
            SetLength(ends, Length(ends) + 1);
            ends[High(ends)][0] := blk.Lines[k].From.Point;
            ends[High(ends)][1] := blk.Lines[k].To_.Point;
          end;
        Inc(FCompared);
        if Length(ends) <> items.Count then
        begin
          Bad(Format('%d lines, upstream %d', [Length(ends), items.Count]));
          Continue;
        end;
        for k := 0 to items.Count - 1 do
        begin
          lay := items.Objects[k].Find('layout');
          for j := 0 to 1 do
          begin
            Same(Format('line %d end %d x', [k, j]), ends[k][j].X, lay.Items[j].Items[0]);
            Same(Format('line %d end %d y', [k, j]), ends[k][j].Y, lay.Items[j].Items[1]);
          end;
          if not IsNan(ends[k][0].X) then Inc(placed);
          Inc(n);
        end;
      end;
    end;
  end;
  Finish('the markers', 40);
  AssertTrue(Format('enough markers (%d)', [n]), n >= 12);
  AssertTrue(Format('enough placed (%d)', [placed]), placed >= 8);
end;

{ ==================== dataZoom ==================== }

procedure TAdvChartPolarSeriesTest.TestPolarDataZoomIsUpstreams;
var
  c, k, i, at, n: Integer;
  cs, sr, z: TJSONObject;
  lay: TTyDzSliderLayout;
  el: TTyChartElement;
  role: TTyChartAnimRole;
  raws: TJSONArray;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'zoom' then Continue;
    FWhere := cs.Strings['id'];
    RenderCase(cs);
    { the sliders' place: no coordinate rect on a polar }
    for k := 0 to cs.Arrays['zoom'].Count - 1 do
    begin
      z := cs.Arrays['zoom'].Objects[k];
      lay := FChart.DataZoomSliderLayout(z.Integers['index']);
      SameBool('slider laid out', lay.Valid, True);
      if not lay.Valid then Continue;
      Same('slider x', lay.LocX, z.Find('x'));
      Same('slider y', lay.LocY, z.Find('y'));
      Same('slider length', lay.L, z.Find('w'));
      Same('slider thickness', lay.T, z.Find('h'));
      SameBool('slider horizontal', lay.Horizontal, z.Strings['orient'] = 'horizontal');
      Inc(n);
    end;
    { the rows each series kept }
    for k := 0 to cs.Arrays['series'].Count - 1 do
    begin
      sr := cs.Arrays['series'].Objects[k];
      raws := sr.Arrays['raw'];
      if sr.Strings['type'] = 'bar' then role := carPolarBar
      else if sr.Strings['type'] = 'line' then role := carLineSymbol
      else role := carSymbol;
      for i := 0 to raws.Count - 1 do
      begin
        at := FindEl(role, sr.Integers['index'], i, el);
        if at < 0 then Continue;
        Inc(n);
        Inc(FCompared);
        if el.Datum.RawDataIndex <> raws.Integers[i] then
          Bad(Format('s%d row %d: raw %d, upstream %d', [sr.Integers['index'], i,
            el.Datum.RawDataIndex, raws.Integers[i]]));
      end;
    end;
  end;
  AssertTrue(Format('enough (%d)', [n]), n >= 12);
  Finish('the dataZoom', 30);
end;

{ ==================== the pointer and the tooltip ==================== }

procedure TAdvChartPolarSeriesTest.TestThePointerSnapsToThePolarSeries;
var
  c, q, a, h, n, k, j, withSeries, polars: Integer;
  cs, pr, ax, el, tipAxis: TJSONObject;
  hits: TTyAxisHitArray;
  found: Integer;
  d: TTyPolarPointerDraw;
  dim, t: string;
  sh, tip, tipList, ser: TJSONArray;
  pts: array[0..5] of Double;
begin
  n := 0;
  withSeries := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'pointer' then Continue;
    RenderCase(cs);
    for q := 0 to cs.Arrays['pointer'].Count - 1 do
    begin
      pr := cs.Arrays['pointer'].Objects[q];
      FWhere := Format('%s @%d,%d', [cs.Strings['id'], pr.Integers['x'], pr.Integers['y']]);
      hits := FChart.Pointers(pr.Integers['x'], pr.Integers['y']);
      polars := 0;
      for h := 0 to High(hits) do
        if hits[h].Polar <> nil then Inc(polars);
      Inc(FCompared);
      if polars <> pr.Arrays['axes'].Count then
        Bad(Format('%d polar pointers, upstream %d', [polars, pr.Arrays['axes'].Count]));
      for a := 0 to pr.Arrays['axes'].Count - 1 do
      begin
        ax := pr.Arrays['axes'].Objects[a];
        dim := ax.Strings['dim'];
        found := -1;
        for h := 0 to High(hits) do
          if (hits[h].Polar <> nil) and (hits[h].Polar.Index = ax.Integers['polar'])
            and (hits[h].Axis.Dim = dim) then found := h;
        Inc(FCompared);
        if found < 0 then
        begin
          Bad('no pointer on the ' + dim + ' axis');
          Continue;
        end;
        Inc(n);
        Same(dim + ' value', FChart.PointerOf(hits[found]), ax.Find('value'));
        FChart.Draw(hits[found], cs.Integers['W'], cs.Integers['H'], d);
        Inc(FCompared);
        if ax.Find('el').JSONType = jtNull then
        begin
          if d.Shape.Kind <> plpkNone then Bad(dim + ': a pointer upstream does not draw');
        end
        else
        begin
          el := ax.Objects['el'];
          t := el.Strings['type'];
          sh := el.Arrays['shape'];
          case d.Shape.Kind of
            plpkLine:
              begin
                SameStr(dim + ' pointer', 'line', t);
                pts[0] := d.Shape.X1; pts[1] := d.Shape.Y1;
                pts[2] := d.Shape.X2; pts[3] := d.Shape.Y2;
                for h := 0 to 3 do Same(dim + ' line ' + IntToStr(h), pts[h], sh.Items[h]);
              end;
            plpkCircle:
              begin
                SameStr(dim + ' pointer', 'circle', t);
                Same(dim + ' circle cx', d.Shape.CX, sh.Items[0]);
                Same(dim + ' circle cy', d.Shape.CY, sh.Items[1]);
                Same(dim + ' circle r', d.Shape.R, sh.Items[2]);
              end;
            plpkSector:
              begin
                SameStr(dim + ' pointer', 'sector', t);
                pts[0] := d.Shape.CX; pts[1] := d.Shape.CY;
                pts[2] := d.Shape.R0; pts[3] := d.Shape.R;
                pts[4] := d.Shape.StartAngle; pts[5] := d.Shape.EndAngle;
                for h := 0 to 5 do Same(dim + ' sector ' + IntToStr(h), pts[h], sh.Items[h]);
              end;
          else
            Bad(dim + ': no pointer element, upstream a ' + t);
          end;
        end;
        Inc(FCompared);
        if ax.Find('label').JSONType = jtNull then
        begin
          if d.HasLabel then Bad(dim + ': a label upstream does not show');
        end
        else if not d.HasLabel then
          Bad(dim + ': no label')
        else
        begin
          el := ax.Objects['label'];
          SameStr(dim + ' label', d.Text, el.Strings['text']);
          Same(dim + ' label x', d.X, el.Find('x'));
          Same(dim + ' label y', d.Y, el.Find('y'));
        end;
      end;
      { THE TOOLTIP'S ROWS: every axis the showTip payload lists, the series
        rows on it, against the hit's }
      if (pr.Find('tip') = nil) or (pr.Find('tip').JSONType <> jtArray) then Continue;
      tip := pr.Arrays['tip'];
      for k := 0 to tip.Count - 1 do
      begin
        tipList := tip.Arrays[k];
        for j := 0 to tipList.Count - 1 do
        begin
          tipAxis := tipList.Objects[j];
          dim := tipAxis.Strings['axisDim'];
          found := -1;
          for h := 0 to High(hits) do
            if (hits[h].Polar <> nil) and (hits[h].Axis.Dim = dim) and not hits[h].Cross then
              found := h;
          ser := tipAxis.Arrays['series'];
          Inc(FCompared);
          if found < 0 then
          begin
            if ser.Count > 0 then Bad('no tooltip axis ' + dim);
            Continue;
          end;
          if Length(hits[found].Slots) <> ser.Count then
          begin
            Bad(Format('%s: %d tooltip rows, upstream %d', [dim, Length(hits[found].Slots), ser.Count]));
            Continue;
          end;
          for h := 0 to ser.Count - 1 do
          begin
            Inc(FCompared);
            if (hits[found].Rows[h] <> ser.Objects[h].Integers['i'])
              or (hits[found].Slots[h] <> ser.Objects[h].Integers['s']) then
              Bad(Format('%s row %d: s%d i%d, upstream s%d i%d', [dim, h, hits[found].Slots[h],
                hits[found].Rows[h], ser.Objects[h].Integers['s'], ser.Objects[h].Integers['i']]));
          end;
          if ser.Count > 0 then Inc(withSeries);
          Same(dim + ' tooltip value', hits[found].SnapValue, tipAxis.Find('value'));
        end;
      end;
    end;
  end;
  AssertTrue(Format('enough pointers (%d)', [n]), n >= 150);
  AssertTrue(Format('enough rows (%d)', [withSeries]), withSeries >= 60);
  Finish('the pointer', 1500);
end;

{ ==================== conversions ==================== }

function KindName(AKind: TTyConvertKind): string;
begin
  case AKind of
    cvkNumber: Result := 'num';
    cvkArray: Result := 'arr';
    cvkError: Result := 'throw';
  else
    Result := 'none';
  end;
end;

{ the oracle's input: every number written as an object whose one key is
  "h", its hex }
function Decode(AData: TJSONData): TJSONData;
var
  o: TJSONObject;
  i: Integer;
begin
  case AData.JSONType of
    jtArray:
      begin
        Result := TJSONArray.Create;
        for i := 0 to AData.Count - 1 do
          TJSONArray(Result).Add(Decode(AData.Items[i]));
      end;
    jtObject:
      begin
        o := TJSONObject(AData);
        if (o.Count = 1) and (o.Names[0] = 'h') and (o.Items[0].JSONType = jtString) then
          Exit(TJSONFloatNumber.Create(FromHex(o.Items[0].AsString)));
        Result := TJSONObject.Create;
        for i := 0 to o.Count - 1 do
          TJSONObject(Result).Add(o.Names[i], Decode(o.Items[i]));
      end;
  else
    Result := AData.Clone;
  end;
end;

procedure TAdvChartPolarSeriesTest.TestSeriesFindersConvertOnTheirPolar;
var
  cs, pb, outNode: TJSONObject;
  p, i, answered: Integer;
  op, k: string;
  finder, value: TJSONData;
  r: TTyConvertResult;
  got: Boolean;
  arr: TJSONArray;
begin
  cs := CaseById('cv-series');
  RenderCase(cs);
  answered := 0;
  for p := 0 to cs.Arrays['convert'].Count - 1 do
  begin
    pb := cs.Arrays['convert'].Objects[p];
    op := pb.Strings['op'];
    outNode := pb.Objects['out'];
    k := outNode.Strings['k'];
    FWhere := op + ' ' + pb.Objects['finder'].Strings['text'] + ' ' + pb.Objects['value'].Strings['text'];
    finder := Decode(pb.Objects['finder'].Find('in'));
    value := Decode(pb.Objects['value'].Find('in'));
    try
      if op = 'contain' then
      begin
        got := FChart.ContainPixelData(finder, value);
        Inc(FCompared);
        if got <> outNode.Booleans['v'] then
          Bad(Format('contains %s, upstream %s', [BoolToStr(got, True),
            BoolToStr(outNode.Booleans['v'], True)]));
        Continue;
      end;
      if op = 'to' then r := FChart.ConvertToPixelData(finder, value)
      else r := FChart.ConvertFromPixelData(finder, value);
      Inc(FCompared);
      if KindName(r.Kind) <> k then
      begin
        Bad(Format('%s here, upstream %s', [KindName(r.Kind), k]));
        Continue;
      end;
      if k = 'arr' then
      begin
        Inc(answered);
        arr := outNode.Arrays['v'];
        if Length(r.Values) <> arr.Count then
          Bad(Format('%d numbers, upstream %d', [Length(r.Values), arr.Count]))
        else
          for i := 0 to arr.Count - 1 do
            Same(Format('[%d]', [i]), r.Values[i], arr.Items[i]);
      end;
    finally
      finder.Free;
      value.Free;
    end;
  end;
  AssertTrue(Format('enough answers (%d)', [answered]), answered >= 30);
  Finish('the conversions', 150);
end;

{ ==================== states ==================== }

function StatesText(A: TJSONArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to A.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + A.Strings[i];
  end;
end;

procedure TAdvChartPolarSeriesTest.TestPolarBarStatesAreUpstreams;
var
  c, s, i, at, n: Integer;
  cs, st, it: TJSONObject;
  el: TTyChartElement;
  item: TTyStItem;
  want: TTyChartColor;
  bmp: TBGRABitmap;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'state' then Continue;
    RenderCase(cs);
    for s := 0 to cs.Arrays['states'].Count - 1 do
    begin
      st := cs.Arrays['states'].Objects[s];
      FWhere := cs.Strings['id'] + ' ' + st.Objects['action'].AsJSON;
      AssertTrue(FWhere + ' dispatched', FChart.DispatchAction(st.Objects['action'].AsJSON));
      bmp := TBGRABitmap.Create(cs.Integers['W'], cs.Integers['H'], BGRA(255, 255, 255, 255));
      try
        FChart.Render(bmp.Canvas, Rect(0, 0, cs.Integers['W'], cs.Integers['H']), 96);
      finally
        bmp.Free;
      end;
      for i := 0 to st.Arrays['items'].Count - 1 do
      begin
        it := st.Arrays['items'].Objects[i];
        at := FindEl(carPolarBar, it.Integers['s'], it.Integers['i'], el);
        Inc(FCompared);
        if at < 0 then
        begin
          Bad(Format('s%d i%d: no bar', [it.Integers['s'], it.Integers['i']]));
          Continue;
        end;
        Inc(n);
        if FChart.States(it.Integers['s'], it.Integers['i'], item) then
          SameStr(Format('s%d i%d states', [it.Integers['s'], it.Integers['i']]),
            TyStNamesText(item.Host.States), StatesText(it.Arrays['states']))
        else
          Bad(Format('s%d i%d: no state record', [it.Integers['s'], it.Integers['i']]));
        if (it.Find('fill') <> nil) and (it.Find('fill').JSONType = jtString)
          and TyTryParseChartColor(it.Strings['fill'], want) then
        begin
          Inc(FCompared);
          if (not el.Style.HasFill) or (el.Style.FillColor <> want) then
            Bad(Format('s%d i%d fill %s, upstream %s', [it.Integers['s'], it.Integers['i'],
              IntToHex(el.Style.FillColor, 8), it.Strings['fill']]));
        end;
        if (it.Find('stroke') <> nil) and (it.Find('stroke').JSONType = jtString)
          and TyTryParseChartColor(it.Strings['stroke'], want) then
        begin
          Inc(FCompared);
          if (el.Style.StrokeColor <> want) then
            Bad(Format('s%d i%d stroke %s, upstream %s', [it.Integers['s'], it.Integers['i'],
              IntToHex(el.Style.StrokeColor, 8), it.Strings['stroke']]));
          Same(Format('s%d i%d line width', [it.Integers['s'], it.Integers['i']]),
            el.Style.StrokeWidthLogical, it.Find('lineWidth'));
        end
        else
        begin
          Inc(FCompared);
          if el.Style.StrokeWidthLogical > 0 then
            Bad(Format('s%d i%d: a stroke upstream does not draw', [it.Integers['s'], it.Integers['i']]));
        end;
        Same(Format('s%d i%d opacity', [it.Integers['s'], it.Integers['i']]),
          el.Style.Alpha, it.Find('opacity'));
      end;
    end;
  end;
  AssertTrue(Format('enough bars (%d)', [n]), n >= 50);
  Finish('the states', 300);
end;

{ ==================== beyond the fixture ==================== }

function OptionCase(const AOption: string): TJSONObject;
begin
  Result := TJSONObject(GetJSON('{"id": "hand", "W": 600, "H": 400, "option": ' + AOption + '}'));
end;

{ the sector's middle, from the layout a bar element carries }
function MidOf(const AEl: TTyChartElement): TTyPointF;
var r, a: Double;
begin
  r := (AEl.Anim.G[2] + AEl.Anim.G[3]) / 2;
  a := (AEl.Anim.G[4] + AEl.Anim.G[5]) / 2;
  Result.X := AEl.Anim.G[0] + r * Cos(a);
  Result.Y := AEl.Anim.G[1] + r * Sin(a);
end;

procedure TAdvChartPolarSeriesTest.TestPolarBarsAreDrawnAndHit;
var
  cs: TJSONObject;
  bmp: TBGRABitmap;
  el: TTyChartElement;
  at, hit, i: Integer;
  m: TTyPointF;
  px: TBGRAPixel;
  rc, dr, a: Double;
  d: TTyChartDatumRef;
begin
  cs := OptionCase('{"polar": [{"center": ["25%", "50%"], "radius": "60%"}, {"center": ["75%", "50%"], "radius": "60%"}], '
    + '"angleAxis": [{"type": "category", "data": ["a", "b", "c", "d"], "polarIndex": 0}, {"polarIndex": 1, "max": 10}], '
    + '"radiusAxis": [{"polarIndex": 0}, {"type": "category", "data": ["a", "b", "c", "d"], "polarIndex": 1}], '
    + '"series": [{"type": "bar", "coordinateSystem": "polar", "data": [3, 5, 2, 4], "itemStyle": {"color": "#ff0000"}}, '
    + '{"type": "bar", "coordinateSystem": "polar", "polarIndex": 1, "roundCap": true, "data": [3, 5, 2, 4], '
    + '"itemStyle": {"color": "#00ff00"}}]}');
  try
    RenderCase(cs);
    bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
      for i := 0 to 3 do
      begin
        { a radial bar is red where its sector is }
        at := FindEl(carPolarBar, 0, i, el);
        AssertTrue('a radial bar', at >= 0);
        m := MidOf(el);
        px := bmp.GetPixel(Round(m.X), Round(m.Y));
        AssertTrue(Format('radial bar %d is painted', [i]), (px.red > 200) and (px.green < 80));
        d := FChart.List.HitTest(m.X, m.Y, 96);
        AssertEquals(Format('radial bar %d is hit', [i]), 0, d.SeriesIndex);
        AssertEquals(Format('radial bar %d is its row', [i]), i, d.DataIndex);
        { a tangential sausage is green, and its round end is hit too }
        at := FindEl(carPolarBar, 1, i, el);
        AssertTrue('a sausage', (at >= 0) and el.Shape.Sausage);
        m := MidOf(el);
        px := bmp.GetPixel(Round(m.X), Round(m.Y));
        AssertTrue(Format('sausage %d is painted', [i]), (px.green > 200) and (px.red < 80));
        { just past the end angle, inside the cap: a tenth of the half
          thickness on, along the ring's middle }
        dr := (el.Shape.R1 - el.Shape.R0) / 2;
        rc := el.Shape.R0 + dr;
        a := el.Shape.EndRad + 0.6 * dr / rc;
        hit := FChart.List.HitTestElement(el.Shape.CX + rc * Cos(a), el.Shape.CY + rc * Sin(a), 96);
        AssertTrue(Format('the cap of sausage %d is hit', [i]), (hit >= 0)
          and (FChart.List.Element(hit).Datum.SeriesIndex = 1)
          and (FChart.List.Element(hit).Datum.DataIndex = i));
      end;
      AssertFalse('nothing far outside', (bmp.GetPixel(5, 5).red < 250) and (bmp.GetPixel(5, 5).green < 250));
    finally
      bmp.Free;
    end;
  finally
    cs.Free;
  end;
end;

procedure TAdvChartPolarSeriesTest.TestAPolarLineIsCutToItsRing;
var
  cs: TJSONObject;
  bmp: TBGRABitmap;
  p: TTyPolar;
  pin, pout: TTyPointF;

  function Inked(const AP: TTyPointF): Boolean;
  var
    dx, dy: Integer;
    px: TBGRAPixel;
  begin
    Result := False;
    for dx := -1 to 1 do
      for dy := -1 to 1 do
      begin
        px := bmp.GetPixel(Round(AP.X) + dx, Round(AP.Y) + dy);
        if (px.blue > 150) and (px.red < 100) then Exit(True);
      end;
  end;

begin
  { a line from r 5 out to r 30 on a radius axis that ends at 10: the
    stretch past the ring is cut by the clip sector }
  cs := OptionCase('{"polar": {"radius": 100}, "angleAxis": {"type": "value", "min": 0, "max": 360, "axisLine": {"show": false}, "splitLine": {"show": false}, "axisTick": {"show": false}, "axisLabel": {"show": false}}, '
    + '"radiusAxis": {"min": 0, "max": 10, "show": false, "splitLine": {"show": false}}, '
    + '"series": [{"type": "line", "coordinateSystem": "polar", "showSymbol": false, '
    + '"lineStyle": {"color": "#0000ff", "width": 3}, "data": [[5, 90], [30, 90]]}]}');
  try
    RenderCase(cs);
    p := FChart.PolarLayout(0);
    AssertTrue('the polar', p <> nil);
    bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
      pin := p.DataToPoint([7.5, 90]);
      pout := p.DataToPoint([13, 90]);
      AssertTrue('drawn inside the ring', Inked(pin));
      AssertFalse('cut outside it', Inked(pout));
    finally
      bmp.Free;
    end;
  finally
    cs.Free;
  end;
end;

procedure TAdvChartPolarSeriesTest.TestASeriesOnAMissingPolarSaysSo;
var
  cs: TJSONObject;
  i: Integer;
  found: Boolean;
begin
  cs := OptionCase('{"polar": {}, "angleAxis": {"type": "category", "data": ["a", "b"]}, "radiusAxis": {}, '
    + '"series": [{"type": "bar", "coordinateSystem": "polar", "polarIndex": 3, "data": [1, 2]}, '
    + '{"type": "bar", "coordinateSystem": "polar", "data": [1, 2]}]}');
  try
    RenderCase(cs);
    found := False;
    for i := 0 to FChart.DiagnosticCount - 1 do
      if (Pos('polar', FChart.Diagnostic(i)) > 0) and (Pos('0', FChart.Diagnostic(i)) > 0) then
        found := True;
    AssertTrue('the diagnostic names the series and the system', found);
    AssertFalse('the lost series is not solved', FChart.Bars(0).Solved);
    AssertTrue('the other is', FChart.Bars(1).Solved);
    { and the one that lost its polar does not share the other's band: one
      column, the full auto width of a lone bar }
    AssertEquals('one row each', 2, Length(FChart.Bars(1).Rows));
  finally
    cs.Free;
  end;
end;

procedure TAdvChartPolarSeriesTest.TestHoveringAPolarBarShowsItsTooltip;
var
  cs: TJSONObject;
  el: TTyChartElement;
  m: TTyPointF;
  bmp: TBGRABitmap;
begin
  cs := OptionCase('{"tooltip": {}, "polar": {}, "angleAxis": {"type": "category", "data": ["a", "b", "c"]}, "radiusAxis": {}, '
    + '"series": [{"type": "bar", "coordinateSystem": "polar", "name": "s", "data": [3, 5, 2]}]}');
  try
    RenderCase(cs);
    AssertTrue('a bar', FindEl(carPolarBar, 0, 1, el) >= 0);
    m := MidOf(el);
    FChart.PointerTo(Round(m.X), Round(m.Y));
    bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
    finally
      bmp.Free;
    end;
    AssertEquals('an item tooltip on row 1', 'item:0:1', FChart.TooltipShownWhich);
  finally
    cs.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartPolarSeriesTest);
end.
