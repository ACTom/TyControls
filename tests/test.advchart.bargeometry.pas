unit test.advchart.bargeometry;
{$mode objfpc}{$H+}
{ Where a bar stands, how long it is, and where its label goes -- held to
  upstream's own rectangles.

  tools/advchart-oracle/bar-geometry.js runs the real ECharts 6.1 build and
  records, per data item, what BarView made of it: 'drawn' (an element that
  paints), 'hidden' (clipped wholly off the plot) or 'none' (a missing value,
  or a start the axis cannot place), the rect as drawn after clip, and the
  label's anchor point and alignment after `outside` was resolved.

  THE RULES IT HOLDS THE PORT TO: a bar grows from the value axis' start value
  (zero, 1 on a log axis, or startValue) and not from its min; a stacked bar
  from the one below it; barMinHeight from the bar's own floor; a bar of no
  length is drawn, flat, with its label; `outside` is past the end the bar
  grows to. Every coordinate is compared exactly, twice -- the second time
  after an Invalidate, so a layout reused from the first pass is compared too.
  A pictorial bar is held to its floor only: its glyphs are another batch. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Builder,
     tyControls.AdvanceChart;
type
  TBarGeomProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartBarGeometryOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBarGeomProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport: string;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure Miss(const ACase, AWhat: string);
    procedure CheckCase(ACase: TJSONObject; APass: Integer);
  published
    procedure TestEveryBarAsUpstreamDrawsIt;
  end;

implementation

procedure TBarGeomProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBarGeomProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-bar-geometry.json';
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

var
  { the largest difference seen, in units in the last place, and how many
    a case may have: none.
    [Revised in batch 42: one on a linear axis and four on a log one, while
    an axis mapped as a + n * (b - a) between canvas edges and a log axis
    normalised over the logarithms of its ends. Upstream's own arithmetic,
    local then global, over the decades the nice step stored, leaves no
    difference.] }
  GWorstUlps: Double;
  GTolUlps: Double;

{ One unit in the last place at A's magnitude. }
function Ulp(A: Double): Double;
var e: Integer;
begin
  A := Abs(A);
  if A < 1e-300 then Exit(4.9406564584124654e-324);
  e := Floor(Log2(A));
  Result := Power(2, e - 52);
end;

function Same(A, B: Double): Boolean;
var d: Double;
begin
  { EXACT -- and -0 is 0, which a rect clipped to nothing is, upstream.
    GTolUlps stays as the dial, at nought. }
  if A = B then Exit(True);
  d := Abs(A - B) / Ulp(Max(Abs(A), Abs(B)));
  if d > GWorstUlps then GWorstUlps := d;
  Result := d <= GTolUlps;
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

procedure TAdvChartBarGeometryOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TBarGeomProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
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

procedure TAdvChartBarGeometryOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartBarGeometryOracleTest.Miss(const ACase, AWhat: string);
begin
  Inc(FBad);
  if FBad <= 30 then
    FReport := FReport + LineEnding + '  ' + ACase + ': ' + AWhat;
end;

procedure TAdvChartBarGeometryOracleTest.CheckCase(ACase: TJSONObject;
  APass: Integer);
var
  name, cls, want, got: string;
  items: TJSONArray;
  item, box, lbl, grid: TJSONObject;
  lst: TTyPaintList;
  e, mark, cap: TTyChartElement;
  i, k, si, raw, marks, caps: Integer;
  b: TTyRectF;
  xywh: TTyXYWH;
  pictorial, vertical, zero: Boolean;
  floor, e0: Double;
begin
  name := ACase.Strings['name'];
  GTolUlps := 0;
  if APass = 1 then name := name + ' (again)';
  pictorial := (ACase.Find('pictorial') <> nil) and ACase.Booleans['pictorial'];
  vertical := ACase.Strings['baseAxis'] = 'x';

  { THE PLOT FIRST: every rectangle below is measured in it }
  grid := ACase.Objects['grid'];
  xywh := FChart.Build.Grid(0).PlotXYWH;
  Inc(FCompared);
  if not (Same(xywh.X, Num(grid, 'x')) and Same(xywh.Y, Num(grid, 'y'))
    and Same(xywh.W, Num(grid, 'width')) and Same(xywh.H, Num(grid, 'height'))) then
  begin
    Miss(name, 'the plot is not upstream''s grid');
    Exit;
  end;

  lst := FChart.List;
  items := ACase.Arrays['items'];
  for k := 0 to items.Count - 1 do
  begin
    item := items.Objects[k];
    si := item.Integers['seriesIndex'];
    raw := item.Integers['dataIndex'];
    cls := item.Strings['class'];
    { the mark is the element that asked for words (or had none to ask for);
      its label is the answer, the one with a size }
    marks := 0;
    caps := 0;
    mark := Default(TTyChartElement);
    cap := Default(TTyChartElement);
    if lst <> nil then
      for i := 0 to lst.Count - 1 do
      begin
        e := lst.Element(i);
        if e.Datum.IsEdge or (e.Datum.SeriesIndex <> si)
          or (e.Datum.RawDataIndex <> raw) then Continue;
        if pictorial then
        begin
          { the inkless rect is the bar; the glyphs are its picture }
          if e.Style.HasFill or (e.Style.StrokeWidthLogical > 0) then Continue;
          if e.Caption.FontSizeLogical > 0 then Continue;
        end;
        if e.Caption.FontSizeLogical > 0 then
        begin
          Inc(caps);
          cap := e;
        end
        else
        begin
          Inc(marks);
          mark := e;
        end;
      end;

    Inc(FCompared);
    if cls <> 'drawn' then
    begin
      { hidden or none: nothing to see, nothing to read, nothing to hover }
      if (marks > 0) or (caps > 0) then
        Miss(name, Format('item %d/%d is %s upstream, drawn here',
          [si, raw, cls]));
      Continue;
    end;
    if marks <> 1 then
    begin
      Miss(name, Format('item %d/%d: %d marks here', [si, raw, marks]));
      Continue;
    end;

    b := TyShapeBounds(mark.Shape);
    if pictorial then
    begin
      floor := FromHex(item.Strings['floor']);
      { the floor is one end or the other -- whichever is nearer is the one
        held to it }
      if vertical then
      begin
        if Abs(b.Top - floor) < Abs(b.Bottom - floor) then e0 := b.Top
        else e0 := b.Bottom;
      end
      else if Abs(b.Left - floor) < Abs(b.Right - floor) then e0 := b.Left
      else e0 := b.Right;
      if not Same(e0, floor) then
        Miss(name, Format('item %d: floor %s upstream, %s here',
          [raw, Fmt(floor), Fmt(e0)]));
      Continue;
    end;

    box := item.Objects['box'];
    if not (Same(b.Left, Num(box, 'l')) and Same(b.Top, Num(box, 't'))
      and Same(b.Right, Num(box, 'r')) and Same(b.Bottom, Num(box, 'b'))) then
      Miss(name, Format('item %d/%d: box %s,%s,%s,%s upstream, %s,%s,%s,%s here',
        [si, raw, Fmt(Num(box, 'l')), Fmt(Num(box, 't')), Fmt(Num(box, 'r')),
         Fmt(Num(box, 'b')), Fmt(b.Left), Fmt(b.Top), Fmt(b.Right),
         Fmt(b.Bottom)]));
    if vertical then zero := b.Top = b.Bottom else zero := b.Left = b.Right;
    if zero <> item.Booleans['zeroLength'] then
      Miss(name, Format('item %d/%d: of no length %s upstream',
        [si, raw, BoolToStr(item.Booleans['zeroLength'], True)]));

    { THE LABEL: drawn or not, and where it hangs }
    lbl := nil;
    if item.Find('label') is TJSONObject then lbl := item.Objects['label'];
    if (lbl = nil) or not lbl.Booleans['drawn'] then
    begin
      if caps > 0 then
        Miss(name, Format('item %d/%d: a label here, none upstream', [si, raw]));
      Continue;
    end;
    Inc(FCompared);
    if caps <> 1 then
    begin
      Miss(name, Format('item %d/%d: %d labels here', [si, raw, caps]));
      Continue;
    end;
    want := lbl.Strings['align'] + '/' + lbl.Strings['verticalAlign'];
    case cap.Caption.AnchorH of
      tahLeft: got := 'left';
      tahRight: got := 'right';
    else
      got := 'center';
    end;
    case cap.Caption.AnchorV of
      tavTop: got := got + '/top';
      tavBottom: got := got + '/bottom';
    else
      got := got + '/middle';
    end;
    if want <> got then
      Miss(name, Format('item %d/%d: label %s (%s) upstream, %s here',
        [si, raw, want, lbl.Strings['word'], got]))
    else if not (Same(cap.Caption.X, FromHex(lbl.Strings['x']))
      and Same(cap.Caption.Y, FromHex(lbl.Strings['y']))) then
      Miss(name, Format('item %d/%d: label at %s,%s upstream, %s,%s here',
        [si, raw, lbl.Strings['xText'], lbl.Strings['yText'],
         Fmt(cap.Caption.X), Fmt(cap.Caption.Y)]));
  end;
end;

procedure TAdvChartBarGeometryOracleTest.TestEveryBarAsUpstreamDrawsIt;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c, pass: Integer;
begin
  GWorstUlps := 0;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if (cs.Find('deferred') <> nil) and cs.Booleans['deferred'] then Continue;
    FChart.Option := cs.Objects['option'].AsJSON;
    AssertEquals(cs.Strings['name'] + ' parses', '', FChart.OptionError);
    FChart.SetBounds(0, 0, 600, 400);
    for pass := 0 to 1 do
    begin
      if pass = 1 then FChart.Invalidate;
      { A RENDER THAT RAISES is a chart upstream draws and this does not }
      try
        FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
        CheckCase(cs, pass);
      except
        on E: Exception do
          Miss(cs.Strings['name'], E.ClassName + ': ' + E.Message);
      end;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 600);

end;

initialization
  RegisterTest(TAdvChartBarGeometryOracleTest);
end.
