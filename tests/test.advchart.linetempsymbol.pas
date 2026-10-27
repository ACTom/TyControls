unit test.advchart.linetempsymbol;
{$mode objfpc}{$H+}
{ A LINE'S TEMPORARY SYMBOL, held to ECharts 6.1. [R5-F, spec 243]

  tools/advchart-oracle/line-temp-symbol.js runs the real dist: a highlight
  of one row of a line that has no symbol for it (showSymbol false, or the
  category interval thinned it) builds the row's symbol in emphasis
  (LineView.highlight), a downplay of the row takes it away again, a
  highlight of a list builds none, a point outside the symbol clip gets
  none. Per step it records every symbol of the series: its row, its global
  rect, fill, stroke, line width and label.

  The control renders each option, dispatches the same actions and renders
  again; the symbols of the series are compared step by step. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLtsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartLineTempSymbolOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLtsProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FTemps: Integer;
    FReport, FName: string;
    procedure NewChart;
    procedure Miss(const AWhat: string);
    procedure Close(const AWhat: string; AGot: Double; const AHex: string);
    procedure Ink(const AWhat: string; AGot: TTyChartColor; AWant: TJSONData);
    procedure CompareStep(const AId: string; AStep: Integer; ASymbols: TJSONArray;
      const ASeries: array of Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheTemporarySymbolsAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TLtsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLtsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLtsProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function IsNull(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-line-temp-symbol.json';
end;

procedure TAdvChartLineTempSymbolOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FTemps := 0;
  FReport := '';
end;

{ a chart of its own for every case: a highlight is the chart's state }
procedure TAdvChartLineTempSymbolOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TLtsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartLineTempSymbolOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLineTempSymbolOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLineTempSymbolOracleTest.Close(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameValue(AGot, FromHex(AHex), 1e-9) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLineTempSymbolOracleTest.Ink(const AWhat: string; AGot: TTyChartColor;
  AWant: TJSONData);
var c: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    if (AGot shr 24) <> 0 then Miss(Format('%s none upstream, $%.8x here', [AWhat, AGot]));
    Exit;
  end;
  if not TyTryParseChartColor(AWant.AsString, c) then
  begin
    Miss(AWhat + ' unparsed ' + AWant.AsString);
    Exit;
  end;
  if c <> AGot then
    Miss(Format('%s %s ($%.8x) upstream, $%.8x here', [AWhat, AWant.AsString, c, AGot]));
end;

procedure TAdvChartLineTempSymbolOracleTest.CompareStep(const AId: string; AStep: Integer;
  ASymbols: TJSONArray; const ASeries: array of Integer);
var
  i, k, s, n, found: Integer;
  sym, lab: TJSONObject;
  el, cap: TTyChartElement;
  b: TTyRectF;
  rect: TJSONArray;
  got: Boolean;
begin
  { as many symbols, series by series }
  for k := 0 to High(ASeries) do
  begin
    s := ASeries[k];
    n := 0;
    for i := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(i);
      if (el.Anim.Role = carLineSymbol) and (el.Datum.SeriesIndex = s) and not el.Ignore then
        Inc(n);
    end;
    found := 0;
    for i := 0 to ASymbols.Count - 1 do
      if ASymbols.Objects[i].Integers['s'] = s then Inc(found);
    FName := Format('%s step %d s%d', [AId, AStep, s]);
    Inc(FCompared);
    if n <> found then Miss(Format('%d symbols upstream, %d here', [found, n]));
  end;
  for i := 0 to ASymbols.Count - 1 do
  begin
    sym := ASymbols.Objects[i];
    FName := Format('%s step %d s%d d%d', [AId, AStep, sym.Integers['s'], sym.Integers['d']]);
    if sym.Booleans['temp'] then Inc(FTemps);
    got := False;
    for k := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(k);
      if (el.Anim.Role = carLineSymbol) and (el.Datum.SeriesIndex = sym.Integers['s'])
        and (el.Datum.DataIndex = sym.Integers['d']) and not el.Ignore then
      begin
        got := True;
        Break;
      end;
    end;
    Inc(FCompared);
    if not got then
    begin
      Miss('a symbol upstream, none here');
      Continue;
    end;
    b := TyShapeBounds(el.Shape);
    rect := sym.Arrays['rect'];
    { the path's rect: the drawn shape's bounds, the stroke left out }
    if not IsNull(sym.Find('lineWidth')) and not IsNull(sym.Find('stroke')) then
    begin
      Close('rect x', b.Left - el.Style.StrokeWidthLogical / 2, rect.Strings[0]);
      Close('rect y', b.Top - el.Style.StrokeWidthLogical / 2, rect.Strings[1]);
      Close('rect w', b.Right - b.Left + el.Style.StrokeWidthLogical, rect.Strings[2]);
      Close('rect h', b.Bottom - b.Top + el.Style.StrokeWidthLogical, rect.Strings[3]);
    end
    else
    begin
      Close('rect x', b.Left, rect.Strings[0]);
      Close('rect y', b.Top, rect.Strings[1]);
      Close('rect w', b.Right - b.Left, rect.Strings[2]);
      Close('rect h', b.Bottom - b.Top, rect.Strings[3]);
    end;
    Ink('fill', el.Style.FillColor, sym.Find('fill'));
    Ink('stroke', el.Style.StrokeColor, sym.Find('stroke'));
    if not IsNull(sym.Find('lineWidth')) and not IsNull(sym.Find('stroke')) then
      Close('lineWidth', el.Style.StrokeWidthLogical, sym.Strings['lineWidth']);
    { its label, where it has a shown one }
    if not IsNull(sym.Find('label')) then
    begin
      lab := sym.Objects['label'];
      if not lab.Booleans['shown'] then Continue;
      got := False;
      for k := 0 to FChart.List.Count - 1 do
      begin
        cap := FChart.List.Element(k);
        if (cap.Caption.FontSizeLogical > 0) and (cap.Datum.SeriesIndex = sym.Integers['s'])
          and (cap.Datum.DataIndex = sym.Integers['d']) and not cap.Ignore then
        begin
          got := True;
          Break;
        end;
      end;
      Inc(FCompared);
      if not got then Miss('a label upstream, none here')
      else if cap.Caption.Text <> lab.Strings['text'] then
        Miss(Format('label "%s" upstream, "%s" here', [lab.Strings['text'], cap.Caption.Text]));
    end;
  end;
end;

procedure TAdvChartLineTempSymbolOracleTest.TestTheTemporarySymbolsAsUpstream;
var
  cases, steps, sa: TJSONArray;
  c, k, j: Integer;
  cs, st: TJSONObject;
  series: array of Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    NewChart;
    FChart.Option := cs.Objects['option'].AsJSON;
    AssertEquals(cs.Strings['id'] + ': the option parses', '', FChart.OptionError);
    { the series the case reads }
    sa := TJSONArray(cs.Objects['option'].Find('series'));
    SetLength(series, sa.Count);
    for j := 0 to sa.Count - 1 do series[j] := j;
    steps := cs.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      if not IsNull(st.Find('action')) then
        FChart.DispatchAction(st.Objects['action'].AsJSON);
      FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
      CompareStep(cs.Strings['id'], k, st.Arrays['symbols'], series);
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 150);
  AssertTrue(Format('temporary symbols compared (%d)', [FTemps]), FTemps >= 12);
end;

initialization
  RegisterTest(TAdvChartLineTempSymbolOracleTest);
end.
