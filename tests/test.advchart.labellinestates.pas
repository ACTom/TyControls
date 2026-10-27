unit test.advchart.labellinestates;
{$mode objfpc}{$H+}
{ A LABEL LINE'S STYLE IN A STATE, held to ECharts 6.1. [R5-F, spec 243]

  tools/advchart-oracle/label-line-states.js runs the real dist: a pie's and
  a scatter's label lines whose emphasis / select labelLine.lineStyle write
  colour, width, opacity, type, dashOffset, cap, join and miterLimit; after
  each highlight, downplay or select, every line's style as it stands.

  The control renders each option, dispatches the same actions and renders
  again; every label line of the series is compared step by step. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLlsProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartLabelLineStatesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLlsProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FLines: Integer;
    FReport, FName: string;
    procedure NewChart;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; AWant: TJSONData; ADefault: Double);
    procedure CompareLines(ALines: TJSONArray);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheLineStatesAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TLlsProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLlsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLlsProbe.List: TTyPaintList;
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
    + 'advchart-label-line-states.json';
end;

procedure TAdvChartLabelLineStatesOracleTest.SetUp;
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
  FLines := 0;
  FReport := '';
end;

procedure TAdvChartLabelLineStatesOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TLlsProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartLabelLineStatesOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLabelLineStatesOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

{ a number as the style holds it; none is the canvas default }
procedure TAdvChartLabelLineStatesOracleTest.Num(const AWhat: string; AGot: Double;
  AWant: TJSONData; ADefault: Double);
var w: Double;
begin
  Inc(FCompared);
  if IsNull(AWant) then w := ADefault else w := FromHex(AWant.AsString);
  if not SameValue(AGot, w, 1e-12) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(w), Fmt(AGot)]));
end;

function CapName(AB: Byte): string;
begin
  case AB of
    cTyCapRound: Result := 'round';
    cTyCapSquare: Result := 'square';
  else
    Result := 'butt';
  end;
end;

function JoinName(AB: Byte): string;
begin
  case AB of
    cTyJoinRound: Result := 'round';
    cTyJoinBevel: Result := 'bevel';
  else
    Result := 'miter';
  end;
end;

procedure TAdvChartLabelLineStatesOracleTest.CompareLines(ALines: TJSONArray);
var
  i, k, j: Integer;
  ln: TJSONObject;
  el: TTyChartElement;
  got: Boolean;
  c: TTyChartColor;
  want, have: string;
  dash: TJSONData;
begin
  for i := 0 to ALines.Count - 1 do
  begin
    ln := ALines.Objects[i];
    got := False;
    for k := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(k);
      if el.IsGuide and (el.Datum.SeriesIndex = 0) and (el.Datum.DataIndex = ln.Integers['d']) then
      begin
        got := True;
        Break;
      end;
    end;
    Inc(FCompared);
    if not got then
    begin
      if not ln.Booleans['ignore'] then Miss(Format('d%d: a line upstream, none here', [ln.Integers['d']]));
      Continue;
    end;
    FName := FName + '';
    if ln.Booleans['ignore'] then Continue;
    Inc(FLines);
    { the ink }
    Inc(FCompared);
    if TyTryParseChartColor(ln.Strings['stroke'], c) and (c <> el.Style.StrokeColor) then
      Miss(Format('d%d stroke %s upstream, $%.8x here', [ln.Integers['d'], ln.Strings['stroke'], el.Style.StrokeColor]));
    Num(Format('d%d lineWidth', [ln.Integers['d']]), el.Style.StrokeWidthLogical, ln.Find('lineWidth'), 1);
    Num(Format('d%d opacity', [ln.Integers['d']]), el.Style.Alpha, ln.Find('opacity'), 1);
    Num(Format('d%d lineDashOffset', [ln.Integers['d']]), el.Style.DashOffsetLogical, ln.Find('lineDashOffset'), 0);
    if el.Style.MiterLimit = 0 then
      Num(Format('d%d miterLimit', [ln.Integers['d']]), 10, ln.Find('miterLimit'), 10)
    else
      Num(Format('d%d miterLimit', [ln.Integers['d']]), el.Style.MiterLimit, ln.Find('miterLimit'), 10);
    Inc(FCompared);
    want := 'butt';
    if not IsNull(ln.Find('lineCap')) then want := ln.Strings['lineCap'];
    if CapName(el.Style.LineCap) <> want then
      Miss(Format('d%d lineCap %s upstream, %s here', [ln.Integers['d'], want, CapName(el.Style.LineCap)]));
    Inc(FCompared);
    want := 'miter';
    if not IsNull(ln.Find('lineJoin')) then want := ln.Strings['lineJoin'];
    if JoinName(el.Style.LineJoin) <> want then
      Miss(Format('d%d lineJoin %s upstream, %s here', [ln.Integers['d'], want, JoinName(el.Style.LineJoin)]));
    { the dash: a word as the word (the painter measures it against the
      width), a list as its lengths, none / 'solid' as none }
    Inc(FCompared);
    dash := ln.Find('lineDash');
    if IsNull(dash) or ((dash.JSONType = jtString) and (dash.AsString = 'solid')) then want := ''
    else if dash.JSONType = jtString then want := dash.AsString
    else
    begin
      want := '';
      for j := 0 to dash.Count - 1 do
        want := want + Fmt(FromHex(dash.Items[j].AsString)) + ' ';
    end;
    case el.Style.DashWord of
      1: have := 'dashed';
      2: have := 'dotted';
    else
      begin
        have := '';
        for j := 0 to High(el.Style.DashLogical) do
          have := have + Fmt(el.Style.DashLogical[j]) + ' ';
      end;
    end;
    if have <> want then
      Miss(Format('d%d lineDash "%s" upstream, "%s" here', [ln.Integers['d'], want, have]));
  end;
end;

procedure TAdvChartLabelLineStatesOracleTest.TestTheLineStatesAsUpstream;
var
  cases, steps: TJSONArray;
  c, k: Integer;
  cs, st: TJSONObject;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    NewChart;
    FChart.Option := cs.Objects['option'].AsJSON;
    AssertEquals(cs.Strings['id'] + ': the option parses', '', FChart.OptionError);
    steps := cs.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      if not IsNull(st.Find('action')) then
        FChart.DispatchAction(st.Objects['action'].AsJSON);
      FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
      FName := Format('%s step %d', [cs.Strings['id'], k]);
      CompareLines(st.Arrays['lines']);
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 300);
  AssertTrue(Format('lines compared (%d)', [FLines]), FLines >= 40);
end;

initialization
  RegisterTest(TAdvChartLabelLineStatesOracleTest);
end.
