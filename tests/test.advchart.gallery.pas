unit test.advchart.gallery;
{$mode objfpc}{$H+}
{ Every option in the gallery, rendered.

  The gallery is 245 real ECharts options -- not fixtures written to suit the
  port, but the examples upstream ships, carrying every spelling of every value
  that a person might actually write. That makes it the one place where the
  port meets option text it did not anticipate, and it is worth exactly two
  assertions.

  ONE: NOTHING MAY RAISE. A chart that cannot draw a series type yet should
  come out blank and say so; a chart that throws out of a paint takes the
  host's window with it. `symbolSize: ['80%', '60%']` -- legal on a
  pictorialBar and written in two of the gallery entries -- reached
  `TJSONArray.Floats[]`, which coerces, and the render died with `Invalid float
  value : 80%`. That is a different kind of defect from `not built yet`, and
  the only thing that finds it is running all of them.

  TWO: WHAT DRAWS MUST GO ON DRAWING. A count of how many entries put coloured
  ink inside the plot, held against a floor. It cannot say a chart is RIGHT --
  no cheap assertion can -- but it says that a change did not silently empty a
  page of charts that used to work, which is the failure this repository keeps
  finding by eye weeks later.

  Deliberately NOT a golden-image test: goldens over 245 charts would go red on
  every theme tweak and be regenerated without being read, which is worse than
  no test. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     BGRABitmap, BGRABitmapTypes,
     tyControls.Types, tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Builder,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartGalleryTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    FBmp: TBGRABitmap;
    procedure SetUp; override;
    procedure TearDown; override;
    function GalleryDir: string;
    { Renders one option. Returns the count of coloured pixels inside the plot;
      lets anything it raises escape. }
    function RenderOne(const AFile: string): Integer;
  published
    { ONE test and two assertions, not two tests. Each render is most of a
      second and there are 245 of them; asking the same question twice costs
      six minutes to say the same thing. The message names which assertion
      broke. }
    procedure TestTheWholeGalleryRendersAndStillDraws;
  end;

implementation

const
  cW = 700;
  cH = 420;
  { What the sweep of 2026-09-14 measured: 95 of 245 entries put coloured ink
    in a cartesian plot. The rest are coordinate systems and series types that
    are not built yet, and they say so.

    A FLOOR, not the number. It moves UP as series types land, and a test that
    pinned the exact count would go red on good news. It goes red on a change
    that empties charts, which is the point. }
  cDrawingFloor = 90;

procedure TAdvChartGalleryTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
end;

procedure TAdvChartGalleryTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TAdvChartGalleryTest.GalleryDir: string;
var d: string; i: Integer;
begin
  { Walk up from the test binary until the examples tree appears. The suite is
    run from tests/ by hand and from the repo root by the build, and hardcoding
    either one makes the test pass in one place and vanish in the other. }
  Result := '';
  d := ExtractFilePath(ParamStr(0));
  for i := 0 to 5 do
  begin
    if DirectoryExists(d + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery') then
      Exit(d + 'examples' + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim);
    d := d + '..' + PathDelim;
  end;
end;

function TAdvChartGalleryTest.RenderOne(const AFile: string): Integer;
var
  sl: TStringList;
  x, y, lo, hi, x0, x1, y0, y1: Integer;
  row: PBGRAPixel;
  plot: TTyRectF;
begin
  Result := 0;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AFile);
    FreeAndNil(FBmp);
    FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
    FChart.Option := sl.Text;
    FChart.SetBounds(0, 0, cW, cH);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  finally
    sl.Free;
  end;
  plot := TyRectF(0, 0, 0, 0);
  if (FChart.Build <> nil) and (FChart.Build.GridCount > 0) then
    plot := FChart.Build.Grid(0).PlotRect;
  if TyRectFWidth(plot) <= 0 then Exit;
  x0 := Max(1, Round(plot.Left));
  x1 := Min(cW - 2, Round(plot.Right));
  y0 := Max(1, Round(plot.Top));
  y1 := Min(cH - 2, Round(plot.Bottom));
  { SCANLINE, not GetPixel. Seventy million property reads across the gallery
    is six minutes of the suite spent on an assertion that takes one line. }
  for y := y0 to y1 do
  begin
    row := FBmp.ScanLine[y];
    Inc(row, x0);
    for x := x0 to x1 do
    begin
      if row^.alpha <> 0 then
      begin
        { COLOUR, not `differs from the background`. Every piece of axis
          furniture is neutral grey by theme and a chart can be thick with it
          and still show no data; a series is coloured. Asking `what is not
          the background` needs to know which white is the card and which is
          the page, and any tolerance wide enough to merge those two also
          swallows the pale split lines. }
        lo := Min(row^.red, Min(row^.green, row^.blue));
        hi := Max(row^.red, Max(row^.green, row^.blue));
        if hi - lo > 25 then Inc(Result);
      end;
      Inc(row);
    end;
  end;
end;

procedure TAdvChartGalleryTest.TestTheWholeGalleryRendersAndStillDraws;
var
  rec: TSearchRec;
  dir, broke: string;
  n, drew, ink: Integer;
begin
  dir := GalleryDir;
  AssertTrue('the gallery is where the test can reach it', dir <> '');
  n := 0;
  drew := 0;
  broke := '';
  if FindFirst(dir + '*.json', faAnyFile, rec) = 0 then
  try
    repeat
      if (rec.Attr and faDirectory) <> 0 then Continue;
      Inc(n);
      try
        ink := RenderOne(dir + rec.Name);
        if ink > 0 then Inc(drew);
      except
        on E: Exception do
          { COLLECTED, not re-raised at the first one. A single name tells you
            one option is bad; the list tells you whether it is one option or a
            whole family, which is the difference between a typo and a missing
            guard. }
          broke := broke + Format('%s(%s) ', [rec.Name, E.Message]);
      end;
    until FindNext(rec) <> 0;
  finally
    FindClose(rec);
  end;
  AssertTrue('the gallery was found and walked', n > 200);
  AssertEquals('options that killed the render: ' + broke, '', broke);
  AssertTrue(Format('%d of %d gallery options drew data, floor is %d',
                    [drew, n, cDrawingFloor]),
             drew >= cDrawingFloor);
end;

initialization
  RegisterTest(TAdvChartGalleryTest);
end.
