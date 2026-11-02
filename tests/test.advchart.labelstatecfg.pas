unit test.advchart.labelstatecfg;
{$mode objfpc}{$H+}
{ A SERIES LABEL'S STATE textConfig, held to ECharts 6.1. [R6-A, spec 248]

  tools/advchart-oracle/label-state-textconfig.js runs the real dist and
  records every label of series 0 at rest and after each action (highlight,
  downplay, select) -- whether it is hidden, its anchor, its turn, its
  alignment, its global rect and its ink -- for series whose
  emphasis.label, select.label or blur.label (the series' or a data item's)
  writes `position`, `distance`, `offset` or `rotate`: setLabelStyle puts
  createTextConfig of each state's label model on the host's state, and
  zrender lays the label out by the normal textConfig extended by the
  states' when they are entered.

  The control renders each option (text measured with zrender's SSR width
  table), dispatches the same actions and compares every label. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StyleModel,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Option, tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.RichStyle,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLscProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Drag(AX, AY, ADX, ADY: Integer);
  end;

  TAdvChartLabelStateTextConfigOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLscProbe;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FMoved, FTurned: Integer;
    { [R7-N] labels compared under a squashed view's whole map }
    FSquashed: Integer;
    { the case reads a graph's or a sankey's links }
    FEdges: Boolean;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Close(const AWhat: string; AGot: Double; const AHex: string);
    procedure Str(const AWhat, AGot, AWant: string);
    function Find(AD: Integer; out AEl: TTyChartElement): Boolean;
    procedure CompareLabels(ALabels, ARest: TJSONArray);
    procedure CheckCase(ACase: TJSONObject);
    procedure NewChart;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheStateTextConfigAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function TLscProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLscProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLscProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TLscProbe.Drag(AX, AY, ADX, ADY: Integer);
begin
  MouseDown(mbLeft, [ssLeft], AX, AY);
  MouseMove([ssLeft], AX + ADX, AY + ADY);
  MouseUp(mbLeft, [], AX + ADX, AY + ADY);
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

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahCentre: Result := 'center';
    tahRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavMiddle: Result := 'middle';
    tavBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-label-state-textconfig.json';
end;

procedure TAdvChartLabelStateTextConfigOracleTest.SetUp;
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
  NewChart;
  FBad := 0;
  FCompared := 0;
  FMoved := 0;
  FTurned := 0;
  FSquashed := 0;
  FReport := '';
end;

{ A CHART OF ITS OWN FOR EVERY CASE, as the oracle's: the states are the
  chart's, not the option's }
procedure TAdvChartLabelStateTextConfigOracleTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TLscProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, cW, cH);
end;

procedure TAdvChartLabelStateTextConfigOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLabelStateTextConfigOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 60 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLabelStateTextConfigOracleTest.Close(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameValue(AGot, FromHex(AHex), 1e-9) then
    Miss(Format('%s %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLabelStateTextConfigOracleTest.Str(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then Miss(Format('%s "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

function TAdvChartLabelStateTextConfigOracleTest.Find(AD: Integer;
  out AEl: TTyChartElement): Boolean;
var i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  for i := 0 to FChart.List.Count - 1 do
    { a label: its role's, or one the expansion made (a sankey's takes its
      host's role) }
    if ((FChart.List.Element(i).Anim.Role = carLabel)
        or (FChart.List.Element(i).Caption.LmKind > 0))
      and (FChart.List.Element(i).Datum.SeriesIndex = 0)
      and (FChart.List.Element(i).Datum.IsEdge = FEdges)
      and (FChart.List.Element(i).Datum.DataIndex = AD) then
    begin
      AEl := FChart.List.Element(i);
      Exit(True);
    end;
end;

{ the ink as painted: a one-run caption's colour, else its block's first
  text piece's fill }
function InkOf(const AEl: TTyChartElement): TTyChartColor;
var i: Integer;
begin
  Result := AEl.Caption.Colour;
  for i := 0 to High(AEl.Caption.RtPieces) do
    if (AEl.Caption.RtPieces[i].Kind = rpkText) and AEl.Caption.RtPieces[i].HasFill then
      Exit(AEl.Caption.RtPieces[i].Fill);
end;

procedure TAdvChartLabelStateTextConfigOracleTest.CompareLabels(ALabels, ARest: TJSONArray);
var
  i: Integer;
  moved: Boolean;
  lb: TJSONObject;
  el: TTyChartElement;
  rect, m: TJSONArray;
  b: TTyRectF;
  c: TTyChartColor;
begin
  for i := 0 to ALabels.Count - 1 do
  begin
    lb := ALabels.Objects[i];
    FName := Format('%s d%d', [FName, lb.Integers['d']]);
    Inc(FCompared);
    if not Find(lb.Integers['d'], el) then
    begin
      if not lb.Booleans['ignore'] then Miss('a label upstream, none here');
      FName := Copy(FName, 1, Pos(' d', FName) - 1);
      Continue;
    end;
    if el.Ignore <> lb.Booleans['ignore'] then
      Miss(Format('hidden %s upstream, %s here',
        [BoolToStr(lb.Booleans['ignore'], True), BoolToStr(el.Ignore, True)]))
    else if not lb.Booleans['ignore'] then
    begin
      moved := (ARest <> nil) and (i < ARest.Count)
        and ((ARest.Objects[i].Strings['x'] <> lb.Strings['x'])
          or (ARest.Objects[i].Strings['y'] <> lb.Strings['y'])
          or (ARest.Objects[i].Arrays['rect'].AsJSON <> lb.Arrays['rect'].AsJSON));
      if moved then Inc(FMoved);
      { a funnel's label hangs off its style's x / y upstream (no
        transform), and a treemap's caption stands where its words start
        (the padding in): their rects say where they are }
      if (Pos('funnel', FName) = 0) and (Pos('treemap', FName) = 0) then
      begin
        Close('x', el.Caption.X, lb.Strings['x']);
        Close('y', el.Caption.Y, lb.Strings['y']);
      end;
      { the turn: zrender's [cos, -sin, sin, cos] }
      m := lb.Arrays['m'];
      if FromHex(m.Strings[1]) <> 0 then Inc(FTurned);
      { [R7-N] a label squashed under its view (a graph edge's, scaleY not
        scaleX): the whole map it is drawn under, its place and its turn
        the state's }
      if el.Caption.HasAffine then
      begin
        Close('m0', el.Caption.Affine[0] / el.Caption.RtScale, m.Strings[0]);
        Close('m1', el.Caption.Affine[1] / el.Caption.RtScale, m.Strings[1]);
        Close('m2', el.Caption.Affine[2] / el.Caption.RtScale, m.Strings[2]);
        Close('m3', el.Caption.Affine[3] / el.Caption.RtScale, m.Strings[3]);
        Close('affine x', el.Caption.Affine[4], lb.Strings['x']);
        Close('affine y', el.Caption.Affine[5], lb.Strings['y']);
        Inc(FSquashed);
      end
      else
      begin
        Close('m0', Cos(el.Caption.RotationRad), m.Strings[0]);
        Close('m1', -Sin(el.Caption.RotationRad), m.Strings[1]);
      end;
      Str('align', AlignName(el.Caption.AnchorH), lb.Strings['align']);
      Str('verticalAlign', VAlignName(el.Caption.AnchorV), lb.Strings['verticalAlign']);
      { the box, where it is not turned (a turned one-run caption keeps its
        upright box) }
      if el.Caption.RotationRad = 0 then
      begin
        rect := lb.Arrays['rect'];
        if Length(el.Caption.RtPieces) > 0 then
          b := TyRtDeviceBox(el.Caption.RtPieces, el.Caption.X, el.Caption.Y, 0,
            el.Caption.RtScale)
        else
          b := el.Shape.Bounds;
        Close('rect x', b.Left, rect.Strings[0]);
        Close('rect y', b.Top, rect.Strings[1]);
        Close('rect w', b.Right - b.Left, rect.Strings[2]);
        Close('rect h', b.Bottom - b.Top, rect.Strings[3]);
      end;
      { THE INK WHERE A STATE MOVED THE LABEL: inside or outside as
        updateInnerText decides it on the host's textConfig, and its colour
        but where it is zrender's #333 (the theme's outside ink here) }
      if moved then
      begin
        Inc(FCompared);
        if el.Caption.LmInkInside <> lb.Booleans['inside'] then
          Miss(Format('inside %s upstream, %s here', [BoolToStr(lb.Booleans['inside'], True),
            BoolToStr(el.Caption.LmInkInside, True)]));
        Inc(FCompared);
        if (lb.Strings['fill'] <> '#333') and TyTryParseChartColor(lb.Strings['fill'], c)
          and (InkOf(el) <> c) then
          Miss(Format('ink %s upstream, $%.8x here', [lb.Strings['fill'],
            Cardinal(InkOf(el))]));
      end;
    end;
    FName := Copy(FName, 1, Pos(' d', FName) - 1);
  end;
end;

procedure TAdvChartLabelStateTextConfigOracleTest.CheckCase(ACase: TJSONObject);
var
  id: string;
  steps, states: TJSONArray;
  k: Integer;
  el: TTyChartElement;
begin
  id := ACase.Strings['id'];
  { TY_LSC_ONLY=id,id...: those cases alone (to read one case's report) }
  if (GetEnvironmentVariable('TY_LSC_ONLY') <> '')
    and (Pos(',' + id + ',', ',' + GetEnvironmentVariable('TY_LSC_ONLY') + ',') = 0) then Exit;
  FEdges := ACase.Find('edges') <> nil;
  NewChart;
  FChart.Option := ACase.Objects['option'].AsJSON;
  AssertEquals(id + ': the option parses', '', FChart.OptionError);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
  steps := ACase.Arrays['steps'];
  states := ACase.Arrays['states'];
  FName := id + ' rest';
  CompareLabels(states.Arrays[0], nil);
  for k := 0 to steps.Count - 1 do
  begin
    { a drag: pressed in the label, moved by (dx, dy) -- zrender's drift }
    if steps.Objects[k].Find('drag') <> nil then
    begin
      if Find(steps.Objects[k].Integers['drag'], el) then
        FChart.Drag(Round((el.Shape.Bounds.Left + el.Shape.Bounds.Right) / 2),
          Round((el.Shape.Bounds.Top + el.Shape.Bounds.Bottom) / 2),
          steps.Objects[k].Integers['dx'], steps.Objects[k].Integers['dy']);
    end
    else
      FChart.DispatchAction(steps.Objects[k].AsJSON);
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
    FName := Format('%s step %d', [id, k + 1]);
    CompareLabels(states.Arrays[k + 1], states.Arrays[0]);
  end;
end;

procedure TAdvChartLabelStateTextConfigOracleTest.TestTheStateTextConfigAsUpstream;
var
  cases: TJSONArray;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    CheckCase(cases.Objects[c]);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 1000);
  AssertTrue(Format('labels a state moved (%d)', [FMoved]), FMoved >= 15);
  AssertTrue(Format('labels a state turned (%d)', [FTurned]), FTurned >= 2);
  { graph.edge.squash: two labels at rest, then after each of three steps;
    [R7-O] graph.edge.squash.sym four at rest and after each of seven,
    graph.edge.squash.tall three at rest and after each of five; [R7-R]
    graph.edge.squash.oblong three at rest and after each of five }
  AssertEquals('labels compared under a squashed map', 8 + 32 + 18 + 18, FSquashed);
end;

initialization
  RegisterTest(TAdvChartLabelStateTextConfigOracleTest);
end.
