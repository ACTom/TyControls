unit test.advchart.visualmaptext;
{$mode objfpc}{$H+}
{ A visualMap's texts -- held to upstream [F4c].

  tools/advchart-oracle/visualmap-text.js runs ECharts 6.1 at 600 x 400 and
  records every Text of the visualMap view: a continuous view's end texts
  (with a line break: a block of lines; the text style's own align and
  verticalAlign before the bar's turn's), its handle labels, a piecewise
  view's item labels and end texts -- string, place, alignment and global
  rect. This holds the control's layout to them, and holds the PICTURE to
  them too: every one of them is inked in a headless render (RenderToBitmap)
  -- the T1 harvest found them missing there. The control measures with
  zrender's width table, so the texts sit where upstream's do. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Paint, tyControls.AdvChart.VisualMapView,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Color,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TVmTextProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function ComponentList: TTyPaintList;
  end;

  TAdvChartVisualMapTextOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVmTextProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Show(ACase: TJSONObject);
    function AllTexts(const L: TTyVisualMapLayout): TTyVmTextArray;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTextsAreUpstreams;
    procedure TestEveryTextIsInkedHeadless;
    procedure TestAPartialBarIsClippedRound;
  end;

implementation

const
  cW = 600;
  cH = 400;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-visualmap-text.json';
end;

function LoadJson(const APath: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function H(A: TJSONData): Double;
begin
  if (A = nil) or (A.JSONType <> jtString) then Exit(NaN);
  Result := FromHex(A.AsString);
end;

function HText(A: TTyTextAnchorH): string;
begin
  case A of
    tahCentre: Result := 'center';
    tahRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function VText(A: TTyTextAnchorV): string;
begin
  case A of
    tavMiddle: Result := 'middle';
    tavBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

function TVmTextProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TVmTextProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TVmTextProbe.ComponentList: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TAdvChartVisualMapTextOracleTest.SetUp;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRAWhite);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartVisualMapTextOracleTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartVisualMapTextOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartVisualMapTextOracleTest.Show(ACase: TJSONObject);
var m: TJSONObject;
begin
  FName := ACase.Strings['id'];
  m := TJSONObject(FRoot).Objects['measure'];
  FreeAndNil(FChart);
  FChart := TVmTextProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ every text of the view, in the group's frame: the end texts, the handle
  labels, the piecewise items' labels }
function TAdvChartVisualMapTextOracleTest.AllTexts(const L: TTyVisualMapLayout): TTyVmTextArray;
var k, n: Integer;

  procedure Push(const T: TTyVmText; ADX: Double = 0; ADY: Double = 0);
  begin
    if T.Text = '' then Exit;
    SetLength(Result, n + 1);
    Result[n] := T;
    Result[n].Rect.X := T.Rect.X + ADX;
    Result[n].Rect.Y := T.Rect.Y + ADY;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  for k := 0 to High(L.Texts) do Push(L.Texts[k]);
  for k := 0 to High(L.Handles) do Push(L.Handles[k].Label_);
  { an item's label is in the item's frame }
  for k := 0 to High(L.Items) do Push(L.Items[k].Label_, L.Items[k].X, L.Items[k].Y);
end;

procedure TAdvChartVisualMapTextOracleTest.TestTheTextsAreUpstreams;
var
  cases, texts: TJSONArray;
  cs, t: TJSONObject;
  c, k, q: Integer;
  L: TTyVisualMapLayout;
  got: TTyVmTextArray;
  found: Boolean;
  gx, gy: Double;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    Show(cs);
    L := FChart.VisualMapLayout(0);
    Inc(FCompared);
    if not L.Valid then
    begin
      Miss('no layout');
      Continue;
    end;
    got := AllTexts(L);
    texts := cs.Arrays['texts'];
    Inc(FCompared);
    if Length(got) <> texts.Count then
      Miss(Format('%d texts upstream, %d here', [texts.Count, Length(got)]));
    for k := 0 to texts.Count - 1 do
    begin
      t := texts.Objects[k];
      found := False;
      for q := 0 to High(got) do
      begin
        if got[q].Text <> StringReplace(t.Strings['string'], #10, LineEnding, []) then
          if got[q].Text <> t.Strings['string'] then Continue;
        found := True;
        gx := L.GroupX;
        gy := L.GroupY;
        Inc(FCompared);
        if (HText(got[q].AlignH) <> t.Strings['align'])
          or (VText(got[q].AlignV) <> t.Strings['verticalAlign']) then
          Miss(Format('"%s": %s/%s here, upstream %s/%s', [got[q].Text,
            HText(got[q].AlignH), VText(got[q].AlignV), t.Strings['align'],
            t.Strings['verticalAlign']]));
        Inc(FCompared);
        if (Abs(got[q].Rect.X + gx - H(t.Objects['rect'].Find('x'))) > 1e-9)
          or (Abs(got[q].Rect.Y + gy - H(t.Objects['rect'].Find('y'))) > 1e-9)
          or (Abs(got[q].Rect.W - H(t.Objects['rect'].Find('width'))) > 1e-9)
          or (Abs(got[q].Rect.H - H(t.Objects['rect'].Find('height'))) > 1e-9) then
          Miss(Format('"%s": rect %g,%g,%g,%g here, upstream %s', [got[q].Text,
            got[q].Rect.X + gx, got[q].Rect.Y + gy, got[q].Rect.W, got[q].Rect.H,
            t.Objects['rect'].Strings['text']]));
        Break;
      end;
      Inc(FCompared);
      if not found then Miss('no text "' + t.Strings['string'] + '"');
    end;
  end;
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared >= 50);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ from upstream:' + FReport, 0, FBad);
end;

{ RenderToBitmap: in every upstream text's rect, ink that is not the ground }
procedure TAdvChartVisualMapTextOracleTest.TestEveryTextIsInkedHeadless;
var
  cases, texts: TJSONArray;
  cs, r: TJSONObject;
  c, k, x, y, x0, y0, x1, y1, inked: Integer;
  bmp: TBGRABitmap;
  sx, sy: Double;
  p, ground: TBGRAPixel;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    Show(cs);
    bmp := FChart.RenderToBitmap('');
    try
      AssertTrue(FName + ': a picture', bmp <> nil);
      sx := bmp.Width / cW;
      sy := bmp.Height / cH;
      ground := bmp.GetPixel(2, 2);
      texts := cs.Arrays['texts'];
      for k := 0 to texts.Count - 1 do
      begin
        r := texts.Objects[k].Objects['rect'];
        x0 := Floor(H(r.Find('x')) * sx);
        y0 := Floor(H(r.Find('y')) * sy);
        x1 := Ceil((H(r.Find('x')) + H(r.Find('width'))) * sx);
        y1 := Ceil((H(r.Find('y')) + H(r.Find('height'))) * sy);
        inked := 0;
        for y := Max(0, y0) to Min(bmp.Height - 1, y1) do
          for x := Max(0, x0) to Min(bmp.Width - 1, x1) do
          begin
            p := bmp.GetPixel(x, y);
            if (Abs(p.red - ground.red) + Abs(p.green - ground.green)
              + Abs(p.blue - ground.blue) > 120) then Inc(inked);
          end;
        Inc(FCompared);
        if inked < 3 then
          Miss(Format('"%s" is not inked in its rect (%d,%d)-(%d,%d)',
            [texts.Objects[k].Strings['string'], x0, y0, x1, y1]));
      end;
    finally
      bmp.Free;
    end;
  end;
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared >= 15);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' texts not drawn:' + FReport, 0, FBad);
end;

{ [F4c] ContinuousView._renderBar: the gradient group -- the out-of-range
  and the in-range polygons -- is clipped by the bar's rect with r 3; a
  partial range's polygon used to be clipped square }
procedure TAdvChartVisualMapTextOracleTest.TestAPartialBarIsClippedRound;
var
  cs: TJSONObject;
  lst: TTyPaintList;
  k, polys: Integer;
  e: TTyChartElement;
begin
  cs := TJSONObject(GetJSON('{"id": "partial", "option": {"animation": false,'
    + ' "xAxis": {}, "yAxis": {}, "visualMap": {"min": 0, "max": 10, "range": [2, 6],'
    + ' "calculable": true, "dimension": 1}, "series": [{"type": "scatter",'
    + ' "data": [[1, 2], [2, 5]]}]}}'));
  try
    Show(cs);
    lst := FChart.ComponentList;
    polys := 0;
    for k := 0 to lst.Count - 1 do
    begin
      e := lst.Element(k);
      if e.Shape.Kind <> cskPolygon then Continue;
      if e.Style.FillGradient.Kind = cgkNone then Continue;
      Inc(polys);
      AssertTrue('the polygon is clipped', e.HasClip);
      AssertEquals('by the rect with r 3', 3, e.ClipRadius, 0);
    end;
    AssertTrue('the partial bar is a clipped polygon', polys > 0);
  finally
    cs.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartVisualMapTextOracleTest);
end.
