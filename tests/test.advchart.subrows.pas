unit test.advchart.subrows;
{$mode objfpc}{$H+}
{ What the series-text oracle cannot see about batch 50: how the auto series
  name's NUL is drawn.

  An unnamed series is `series#0<index>` -- upstream's model name, which `{a}`
  prints and the oracle compares with the NUL in it. A browser draws the NUL
  as nothing; a text API that takes a PChar would end the string there and
  draw `[series`. So a label `[{a}]` on an unnamed series has to MEASURE and
  DRAW exactly like `[series0]`. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Measure,
     tyControls.AdvanceChart;
type
  TSubRowsProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartSubRowsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function Draw(const AOption: string; out ACaption: string;
      out ABounds: TTyRectF): TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheInkTextDropsOnlyNuls;
    procedure TestAnUnnamedSeriesLabelDrawsLikeItsNameWithoutTheNul;
  end;

implementation

procedure TSubRowsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TSubRowsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TAdvChartSubRowsTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
end;

procedure TAdvChartSubRowsTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

{ The chart drawn on white, and its one label's text and box. }
function TAdvChartSubRowsTest.Draw(const AOption: string; out ACaption: string;
  out ABounds: TTyRectF): TBGRABitmap;
var
  chart: TSubRowsProbe;
  i: Integer;
begin
  ACaption := '';
  ABounds := Default(TTyRectF);
  chart := TSubRowsProbe.Create(FForm);
  try
    chart.Parent := FForm;
    chart.Controller := FCtl;
    chart.Option := AOption;
    AssertEquals('the option parses', '', chart.OptionError);
    chart.SetBounds(0, 0, 400, 300);
    Result := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
    chart.Render(Result.Canvas, Rect(0, 0, 400, 300), 96);
    for i := 0 to chart.List.Count - 1 do
      if chart.List.Element(i).Caption.Text <> '' then
      begin
        ACaption := chart.List.Element(i).Caption.Text;
        ABounds := chart.List.Element(i).Shape.Bounds;
      end;
  finally
    chart.Free;
  end;
end;

procedure TAdvChartSubRowsTest.TestTheInkTextDropsOnlyNuls;
begin
  AssertEquals('[series0]', TyInkText('[series'#0'0]'));
  AssertEquals('ab', TyInkText(#0'a'#0#0'b'#0));
  AssertEquals('no NUL, the same', 'a b', TyInkText('a b'));
end;

procedure TAdvChartSubRowsTest.TestAnUnnamedSeriesLabelDrawsLikeItsNameWithoutTheNul;
const
  cBody = '"xAxis": {"type": "category", "data": ["A"]}, "yAxis": {"type": "value"},'
    + ' "animation": false, "series": [{%s"type": "bar", "data": [5],'
    + ' "itemStyle": {"color": "#5470c6"},'
    + ' "label": {"show": true, "position": "inside", "formatter": "[{a}]"}}]';
var
  a, b: TBGRABitmap;
  capA, capB: string;
  boxA, boxB: TTyRectF;
  x, y, diff: Integer;
begin
  a := Draw('{' + Format(cBody, ['']) + '}', capA, boxA);
  b := nil;
  try
    b := Draw('{' + Format(cBody, ['"name": "series0", ']) + '}', capB, boxB);
    { The text keeps its NUL -- it is what {a} prints. }
    AssertEquals('the unnamed label is the auto name', '[series'#0'0]', capA);
    AssertEquals('the named one', '[series0]', capB);
    { It MEASURES as if the NUL were not there... }
    AssertEquals('the same width', boxB.Right - boxB.Left, boxA.Right - boxA.Left, 0);
    AssertEquals('the same place', boxB.Left, boxA.Left, 0);
    { ...and DRAWS so: every pixel the same. }
    diff := 0;
    for y := 0 to a.Height - 1 do
      for x := 0 to a.Width - 1 do
        if a.GetPixel(x, y) <> b.GetPixel(x, y) then Inc(diff);
    AssertEquals('pixels that differ', 0, diff);
  finally
    a.Free;
    b.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartSubRowsTest);
end.
