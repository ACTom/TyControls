unit test.advchart.pathicons;
{$mode objfpc}{$H+}
{ A COMPONENT'S path:// ICON IN ITS BOX, held to upstream. [R7-S]

  tests/fixtures/advchart-path-icons.json, from the real ECharts 6.1 build
  (tools/advchart-oracle/path-icons.js): per case and colour, the union of
  the global bounding rects of the paths upstream fills with that colour --
  a legend's icon (its symbolKeepAspect; a line series' own square marker
  covered), a gauge's pointer and anchor icons (their
  keepAspect), a piecewise visualMap's item symbols (covered), an axis'
  arrows (kept), a markLine's end symbols (covered), a dataZoom's handles
  (kept). createSymbol's makePath 'cover' stretches the path over the box,
  'center' fits it to its own aspect there.

  TestTheIconsAsUpstream: the chart drawn at 96 PPI, the pixels painted
  exactly in that colour (the inside of the shape, its antialiased rim
  aside) span the box within a pixel at each edge. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.AdvanceChart;
type
  TPiProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAdvChartPathIconsOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPiProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheIconsAsUpstream;
  end;

implementation

procedure TPiProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function HexD(const S: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + S);
  Move(q, Result, SizeOf(Result));
end;

procedure TAdvChartPathIconsOracleTest.SetUp;
var
  sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'advchart-path-icons.json');
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBmp := TBGRABitmap.Create(FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger,
    BGRA(255, 255, 255, 255));
end;

procedure TAdvChartPathIconsOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartPathIconsOracleTest.TestTheIconsAsUpstream;
var
  cs, icons: TJSONArray;
  c, ic: TJSONObject;
  i, j, x, y, nBad, nIcons, x0, y0, x1, y1, wx0, wy0, wx1, wy1: Integer;
  id, bad, col: string;
  bx, by, bw, bh: Double;
  want, px: TBGRAPixel;
begin
  nBad := 0;
  nIcons := 0;
  bad := '';
  cs := TJSONObject(FRoot).Arrays['charts'];
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    id := c.Strings['id'];
    FreeAndNil(FChart);
    FChart := TPiProbe.Create(FForm);
    FChart.Parent := FForm;
    FChart.Controller := FCtl;
    FChart.SetBounds(0, 0, FBmp.Width, FBmp.Height);
    FChart.Option := c.Objects['option'].AsJSON;
    AssertEquals(id + ' parses', '', FChart.OptionError);
    FBmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
    icons := c.Arrays['icons'];
    for j := 0 to icons.Count - 1 do
    begin
      ic := icons.Objects[j];
      Inc(nIcons);
      col := ic.Strings['colour'];
      want := StrToBGRA(col);
      wx0 := 0;
      wy0 := 0;
      wx1 := FBmp.Width - 1;
      wy1 := FBmp.Height - 1;
      if ic.Find('within') <> nil then
      begin
        wx0 := Floor(ic.Arrays['within'].Floats[0]);
        wy0 := Floor(ic.Arrays['within'].Floats[1]);
        wx1 := Min(FBmp.Width - 1, Ceil(ic.Arrays['within'].Floats[2]) - 1);
        wy1 := Min(FBmp.Height - 1, Ceil(ic.Arrays['within'].Floats[3]) - 1);
      end;
      x0 := MaxInt;
      y0 := MaxInt;
      x1 := -1;
      y1 := -1;
      for y := wy0 to wy1 do
        for x := wx0 to wx1 do
        begin
          px := FBmp.GetPixel(x, y);
          if (px.red = want.red) and (px.green = want.green) and (px.blue = want.blue) then
          begin
            x0 := Min(x0, x);
            y0 := Min(y0, y);
            x1 := Max(x1, x);
            y1 := Max(y1, y);
          end;
        end;
      bx := HexD(ic.Arrays['box'].Strings[0]);
      by := HexD(ic.Arrays['box'].Strings[1]);
      bw := HexD(ic.Arrays['box'].Strings[2]);
      bh := HexD(ic.Arrays['box'].Strings[3]);
      { the inside's pixels against the box: within a pixel at each edge }
      if (x1 < 0) or (Abs(x0 - bx) > 1) or (Abs(y0 - by) > 1) or (Abs(x1 + 1 - (bx + bw)) > 1)
        or (Abs(y1 + 1 - (by + bh)) > 1) then
      begin
        Inc(nBad);
        bad := bad + LineEnding + Format('%s %s: painted %d,%d - %d,%d; upstream''s box %g,%g %gx%g',
          [id, col, x0, y0, x1 + 1, y1 + 1, bx, by, bw, bh]);
      end;
    end;
  end;
  FreeAndNil(FChart);
  if nBad > 0 then Fail(Format('%d of %d icons differ:%s', [nBad, nIcons, bad]));
  AssertTrue('icons compared', nIcons >= 10);
end;

initialization
  RegisterTest(TAdvChartPathIconsOracleTest);
end.
