unit test.advchart.geolabels;
{$mode objfpc}{$H+}
{ A geo region's label beyond its words and font, held to ECharts 6.1
  [R5-C]: rich text, a text box, the text's own stroke (textBorder*),
  `distance` (which a percentage position never reads) and a state's own
  position word under highlight.

  tools/advchart-oracle/geo-labels.js registers a small map and records
  every region label after a render and after each highlight: hidden or
  not, the lines (tokens) it draws, its rect through its transform, whether
  a box is drawn, its stroke and line width. The control renders the same
  option (zrender's SSR width table measures the words) and each label is
  compared. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Geo,
     tyControls.AdvanceChart.Measure, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TGlProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartGeoLabelsTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGlProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FLabels: Integer;
    FName, FReport: string;
    procedure Miss(const AWhat: string);
    procedure Near(const AWhat: string; AGot, AWant: Double);
    procedure CheckLabels(const AId: string; ALabels: TJSONArray);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLabelsAsUpstream;
  end;

implementation

function TGlProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TGlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function IsNull(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

procedure TAdvChartGeoLabelsTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 100 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartGeoLabelsTest.Near(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not (Abs(AGot - AWant) <= 1e-9) then
    Miss(Format('%s: %.17g upstream, %.17g here', [AWhat, AWant, AGot]));
end;

{ the region labels as the list holds them: a geo's texts, in order }
procedure TAdvChartGeoLabelsTest.CheckLabels(const AId: string; ALabels: TJSONArray);
var
  idx: array of Integer;
  i, k, n: Integer;
  el: TTyChartElement;
  lb: TJSONObject;
  got, want: string;
  b: TTyRectF;
  boxed: Boolean;
  c: TTyChartColor;
begin
  idx := nil;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Datum.Kind = ctkGeo) and (el.Caption.FontSizeLogical > 0)
      and ((el.Caption.Text <> '') or (Length(el.Caption.RtPieces) > 0)) then
    begin
      n := Length(idx);
      SetLength(idx, n + 1);
      idx[n] := i;
    end;
  end;
  FName := AId;
  Inc(FCompared);
  if Length(idx) <> ALabels.Count then
  begin
    Miss(Format('%d labels upstream, %d here', [ALabels.Count, Length(idx)]));
    Exit;
  end;
  for i := 0 to ALabels.Count - 1 do
  begin
    lb := ALabels.Objects[i];
    el := FChart.List.Element(idx[i]);
    FName := Format('%s label %d', [AId, i]);
    Inc(FLabels);
    Inc(FCompared);
    if el.Ignore <> lb.Booleans['ignore'] then Miss('ignore');
    if el.Ignore then Continue;
    got := '';
    boxed := False;
    if Length(el.Caption.RtPieces) > 0 then
    begin
      for k := 0 to High(el.Caption.RtPieces) do
        if el.Caption.RtPieces[k].Kind = rpkText then
          got := got + '|' + el.Caption.RtPieces[k].Text
        else if el.Caption.RtPieces[k].Drawn then
          boxed := True;
    end
    else
      got := '|' + el.Caption.Text;
    want := '';
    for k := 0 to lb.Arrays['texts'].Count - 1 do want := want + '|' + lb.Arrays['texts'].Strings[k];
    Inc(FCompared);
    if got <> want then Miss('texts ' + want + ' upstream, ' + got + ' here');
    Inc(FCompared);
    if boxed <> lb.Booleans['box'] then Miss('box drawn');
    b := el.Shape.Bounds;
    Near('left', b.Left, FromHex(lb.Arrays['rect'].Strings[0]));
    Near('top', b.Top, FromHex(lb.Arrays['rect'].Strings[1]));
    Near('right', b.Right, FromHex(lb.Arrays['rect'].Strings[0]) + FromHex(lb.Arrays['rect'].Strings[2]));
    Near('bottom', b.Bottom, FromHex(lb.Arrays['rect'].Strings[1]) + FromHex(lb.Arrays['rect'].Strings[3]));
    { the text's own stroke }
    if not IsNull(lb.Find('stroke')) then
    begin
      Inc(FCompared);
      if not TyTryParseChartColor(lb.Strings['stroke'], c) or (c <> el.Caption.StrokeColour) then
        Miss(Format('stroke %s upstream, %.8x here', [lb.Strings['stroke'], el.Caption.StrokeColour]));
      Near('line width', el.Caption.StrokeWidthLogical, FromHex(lb.Strings['lineWidth']));
    end;
  end;
end;

procedure TAdvChartGeoLabelsTest.TestTheLabelsAsUpstream;
var
  cs, hv: TJSONArray;
  c, h, cw, ch: Integer;
  cse, mp: TJSONObject;
begin
  mp := TJSONObject(FRoot).Objects['map'];
  AssertTrue('the map registers', TyChartRegisterMap(mp.Strings['name'], mp.Strings['text'], ''));
  cs := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cs.Count - 1 do
  begin
    cse := cs.Objects[c];
    cw := cse.Integers['W'];
    ch := cse.Integers['H'];
    FChart.Option := '{}';
    FChart.Option := cse.Objects['option'].AsJSON;
    FChart.SetBounds(0, 0, cw, ch);
    FBmp.SetSize(cw, ch);
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
    CheckLabels(cse.Strings['id'], cse.Arrays['labels']);
    hv := cse.Arrays['hover'];
    for h := 0 to hv.Count - 1 do
    begin
      AssertTrue('dispatch', FChart.DispatchAction(hv.Objects[h].Objects['payload'].AsJSON));
      FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
      CheckLabels(cse.Strings['id'] + ' hover ' + IntToStr(h), hv.Objects[h].Arrays['labels']);
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('labels compared (%d)', [FLabels]), FLabels >= 18);
end;

procedure TAdvChartGeoLabelsTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TGlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-geo-labels.json');
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FLabels := 0;
  FReport := '';
end;

procedure TAdvChartGeoLabelsTest.TearDown;
begin
  TyChartClearMaps;
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

initialization
  RegisterTest(TAdvChartGeoLabelsTest);
end.
