unit test.advchart.richimage;
{$mode objfpc}{$H+}
{ A TEXT BOX'S PICTURE, backgroundColor: {image} [R2-F].

  tools/advchart-oracle/rich-image.js lays out, on ECharts 6.1, labels whose
  rich tokens or whose box have a picture behind them -- the state after a
  browser has loaded the picture: the token widened to the picture at its
  height where no width is written, a ZRImage over the box after the box's
  Rect (made only for a lineHeight or a border, and then holding the
  opacity) -- and records the label Text's children: the Rect's shape, the
  picture's box and opacity, every TSpan's place. This holds the control's
  label pieces to them, the pictures given as the same PNGs (data URLs of
  the sizes upstream was told), and paints one to see the picture drawn. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  TAdvChartRichImageOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGfxProbe;
    FRoot: TJSONObject;
    FBad, FCompared: Integer;
    FReport: string;
    procedure Bad(const AWhere, AWhat: string);
    function OptionOf(ACase: TJSONObject): string;
    procedure Show(ACase: TJSONObject);
    function LabelEl(out AEl: TTyChartElement): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePicturesAreUpstreams;
    procedure TestThePictureIsDrawn;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-rich-image.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Near(A, B: Double): Boolean;
begin
  Result := Abs(A - B) <= 1e-9 * Max(1.0, Abs(B));
end;

procedure TAdvChartRichImageOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := TJSONObject(GetJSON(sl.Text));
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartRichImageOracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartRichImageOracleTest.Bad(const AWhere, AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + AWhere + ': ' + AWhat;
end;

{ the option with every '@name' the PNG of that name }
function TAdvChartRichImageOracleTest.OptionOf(ACase: TJSONObject): string;
var
  ims: TJSONObject;
  k: Integer;
begin
  Result := ACase.Objects['option'].AsJSON;
  ims := FRoot.Objects['images'];
  for k := 0 to ims.Count - 1 do
    Result := StringReplace(Result, '"@' + ims.Names[k] + '"',
      '"' + TJSONObject(ims.Items[k]).Strings['url'] + '"', [rfReplaceAll]);
end;

procedure TAdvChartRichImageOracleTest.Show(ACase: TJSONObject);
var
  m: TJSONObject;
  bmp: TBGRABitmap;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TGfxProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := FRoot.Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, 400, 300);
  FChart.SetOption(OptionOf(ACase), True);
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
  finally
    bmp.Free;
  end;
end;

{ the bar's label: the series element whose caption is a block }
function TAdvChartRichImageOracleTest.LabelEl(out AEl: TTyChartElement): Boolean;
var k: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  for k := 0 to FChart.List.Count - 1 do
    if (Length(FChart.List.Element(k).Caption.RtPieces) > 0)
      and (FChart.List.Element(k).Datum.SeriesIndex = 0) then
    begin
      AEl := FChart.List.Element(k);
      Exit(True);
    end;
end;

procedure TAdvChartRichImageOracleTest.TestThePicturesAreUpstreams;
var
  cases, ups: TJSONArray;
  cs, u: TJSONObject;
  c, i, n: Integer;
  el: TTyChartElement;
  pcs: array of TTyRtPiece;
  q: TTyRtPiece;
  kind, where: string;
begin
  cases := FRoot.Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    where := cs.Strings['id'];
    Show(cs);
    if not LabelEl(el) then
    begin
      Bad(where, 'no label block');
      Continue;
    end;
    { the port's pieces as upstream's children: a rect that is drawn
      (zrender makes a Rect only to fill or stroke it, or for a
      lineHeight), the picture after it, the texts }
    pcs := nil;
    for i := 0 to High(el.Caption.RtPieces) do
    begin
      q := el.Caption.RtPieces[i];
      if q.Kind = rpkRect then
      begin
        if q.HasFill or q.HasStroke then
        begin
          SetLength(pcs, Length(pcs) + 1);
          pcs[High(pcs)] := q;
          pcs[High(pcs)].Image := '';
        end;
        if q.Image <> '' then
        begin
          SetLength(pcs, Length(pcs) + 1);
          pcs[High(pcs)] := q;
          { marks it the picture }
          pcs[High(pcs)].HasFill := False;
          pcs[High(pcs)].HasStroke := False;
        end;
      end
      else
      begin
        SetLength(pcs, Length(pcs) + 1);
        pcs[High(pcs)] := q;
      end;
    end;
    ups := cs.Arrays['pieces'];
    Inc(FCompared);
    if Length(pcs) <> ups.Count then
    begin
      Bad(where, Format('%d pieces here, %d upstream', [Length(pcs), ups.Count]));
      Continue;
    end;
    for n := 0 to ups.Count - 1 do
    begin
      u := ups.Objects[n];
      kind := u.Strings['kind'];
      q := pcs[n];
      Inc(FCompared);
      if kind = 'text' then
      begin
        if q.Kind <> rpkText then
        begin
          Bad(where, Format('piece %d: a text upstream', [n]));
          Continue;
        end;
        if q.Text <> u.Strings['text'] then
          Bad(where, Format('piece %d "%s", upstream "%s"', [n, q.Text, u.Strings['text']]));
        if not (Near(q.X, FromHex(u.Strings['x'])) and Near(q.Y, FromHex(u.Strings['y']))) then
          Bad(where, Format('text %d at %g, %g; upstream %g, %g', [n, q.X, q.Y,
            FromHex(u.Strings['x']), FromHex(u.Strings['y'])]));
        Continue;
      end;
      if q.Kind <> rpkRect then
      begin
        Bad(where, Format('piece %d: a %s upstream', [n, kind]));
        Continue;
      end;
      if (kind = 'image') <> (q.Image <> '') then
      begin
        Bad(where, Format('piece %d: a %s upstream', [n, kind]));
        Continue;
      end;
      if not (Near(q.X, FromHex(u.Strings['x'])) and Near(q.Y, FromHex(u.Strings['y']))
        and Near(q.W, FromHex(u.Strings['width'])) and Near(q.H, FromHex(u.Strings['height']))) then
        Bad(where, Format('%s %d: %g, %g %gx%g here; upstream %g, %g %gx%g', [kind, n,
          q.X, q.Y, q.W, q.H, FromHex(u.Strings['x']), FromHex(u.Strings['y']),
          FromHex(u.Strings['width']), FromHex(u.Strings['height'])]));
      Inc(FCompared);
      if (kind = 'image') and not Near(q.ImageOpacity, FromHex(u.Strings['opacity'])) then
        Bad(where, Format('picture %d at %g, upstream %g', [n, q.ImageOpacity,
          FromHex(u.Strings['opacity'])]));
      if (kind = 'rect') and not Near(q.Opacity, FromHex(u.Strings['opacity'])) then
        Bad(where, Format('rect %d at %g, upstream %g', [n, q.Opacity,
          FromHex(u.Strings['opacity'])]));
    end;
  end;
  AssertTrue(Format('comparisons made (%d)', [FCompared]), FCompared >= 30);
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s', [FBad, FCompared, FReport]));
end;

{ the token's picture is painted: the wide PNG, red on its left half and
  blue on its right, over the token's box }
procedure TAdvChartRichImageOracleTest.TestThePictureIsDrawn;
var
  cs: TJSONObject;
  el: TTyChartElement;
  bmp: TBGRABitmap;
  i: Integer;
  q: TTyRtPiece;
  x0, y0, x1, y1: Double;
  pl, pr: TBGRAPixel;
begin
  cs := FRoot.Arrays['cases'].Objects[0];
  AssertEquals('the first case', 'token', cs.Strings['id']);
  Show(cs);
  AssertTrue('the label', LabelEl(el));
  x0 := NaN;
  for i := 0 to High(el.Caption.RtPieces) do
  begin
    q := el.Caption.RtPieces[i];
    if (q.Kind = rpkRect) and (q.Image <> '') then
    begin
      x0 := el.Caption.X + q.X;
      y0 := el.Caption.Y + q.Y;
      x1 := x0 + q.W;
      y1 := y0 + q.H;
    end;
  end;
  AssertFalse('a picture piece', IsNan(x0));
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    pl := bmp.GetPixel(Round(x0 + (x1 - x0) * 0.2), Round((y0 + y1) / 2));
    pr := bmp.GetPixel(Round(x0 + (x1 - x0) * 0.8), Round((y0 + y1) / 2));
    AssertTrue(Format('red on the left (%d, %d, %d)', [pl.red, pl.green, pl.blue]),
      (pl.red > 200) and (pl.green < 60) and (pl.blue < 60));
    AssertTrue(Format('blue on the right (%d, %d, %d)', [pr.red, pr.green, pr.blue]),
      (pr.blue > 200) and (pr.red < 60) and (pr.green < 60));
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartRichImageOracleTest);
end.
