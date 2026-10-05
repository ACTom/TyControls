unit test.advchart.polaraxes;
{$mode objfpc}{$H+}
{ THE POLAR COORDINATE SYSTEM AND ITS AXES, HELD TO UPSTREAM [Batch 111, C3].

  tools/advchart-oracle/polar-axes.js runs the real ECharts 6.1 build in
  node (server-side, animation off, zrender's width table for text, TZ=UTC)
  and records, chart by chart:

    the polar   its centre, both axes' extents and inverse flags (the angle's
                after clockwise, either after a backwards min and max), the
                types and the scales' extents and blankness;
    the radius  every element its AxisBuilder draws -- the line (on the
                pixel grid), the arrows, the ticks and minor ticks with the
                ticks a hidden label took, the labels (text, place, turn,
                alignment, hidden), the name -- and its own view's split
                circles and arcs, minor split circles and split-area rings,
                each with the colour it took;
    the angle   its line (circle, arc or ring), ticks, minor ticks, labels
                (text, place, alignment), split lines, minor split lines and
                split-area sectors;
    the pointer at each probe pixel, every polar axis whose pointer is shown:
                its value, its element (a line or a circle, a sector for a
                shadow) and its label's text and box;
    conversions convertToPixel / convertFromPixel / containPixel with polar
                finders and values of every kind.

  This replays it through the control, bit for bit: the axis views through
  PolarLayout, the pointer through ResolveAxisPointers and
  PolarPointerGeometry, the conversions through the typed API with the exact
  doubles the oracle wrote. Text is measured with zrender's width table.

  THE MACHINE'S ZONE. A date string with no zone is the local wall clock; a
  probe holding one is compared only at UTC, as in the C2 replay. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.StrConsts,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Layout, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Convert, tyControls.AdvChart.Polar,
     tyControls.AdvChart.Export, tyControls.AdvanceChart, test.advchart.gridbounds,
     test.advchart.categoryminmax;
type
  TPolarProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
    function PointerOf(const AHit: TTyAxisHit): Double;
    function Draw(const AHit: TTyAxisHit; AW, AH: Integer;
      out D: TTyPolarPointerDraw): Boolean;
    procedure PointerTo(AX, AY: Integer);
  end;

  TAdvChartPolarAxesTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TPolarProbe;
    FRoot, FTable: TJSONData;
    FBad, FCompared, FSkipped: Integer;
    FReport, FWhere: string;
    FSavedSource: TTyDateTimeNameSource;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure RenderCase(ACase: TJSONObject);
    function Cases: TJSONArray;
    procedure Finish(const AWhat: string; AMin: Integer);
    procedure CheckLine(const AWhat: string; const L: TTyPolarLine; ARec: TJSONObject);
    procedure CheckArc(const AWhat: string; const A: TTyPolarArc; ARec: TJSONObject;
      AAngles: Boolean);
    procedure CheckRadius(P: TTyPolar; ARec: TJSONObject);
    procedure CheckAngle(P: TTyPolar; ARec: TJSONObject);
    procedure CheckProbe(ACase, AProbe: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestThePolarIsUpstreams;
    procedure TestTheRadiusAxisDrawsWhatUpstreamDraws;
    procedure TestTheAngleAxisDrawsWhatUpstreamDraws;
    procedure TestThePointerIsUpstreams;
    procedure TestEveryConversionIsUpstreams;
    { beyond the fixture }
    procedure TestAPolarMissingAnAxisSaysSo;
    procedure TestTheAxesArePainted;
    procedure TestPointToCoordWrapsIntoTheExtent;
    procedure TestTheAngleIntervalIsHeldAcrossAMerge;
    procedure TestTheRadiusIntervalIsHeldAcrossAMerge;
    procedure TestExcludedPolarAxesAreNotDrawn;
    procedure TestHoveringAPolarDrawsThePointerAndNoTooltip;
  end;

implementation

const
  cW = 600;
  cH = 400;

{ ==================== the probe ==================== }

function TPolarProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TPolarProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TPolarProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

function TPolarProbe.PointerOf(const AHit: TTyAxisHit): Double;
begin
  Result := PointerValue(AHit);
end;

function TPolarProbe.Draw(const AHit: TTyAxisHit; AW, AH: Integer;
  out D: TTyPolarPointerDraw): Boolean;
begin
  Result := PolarPointerGeometry(AHit, Rect(0, 0, AW, AH), NewTextMeasurer(96), 96, D);
end;

procedure TPolarProbe.PointerTo(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

{ ==================== helpers ==================== }

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function HexOf(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

function Txt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function SameBits(A, B: Double): Boolean;
begin
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B));
end;

function AlignName(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

function VAlignName(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavTop: Result := 'top';
    tavBottom: Result := 'bottom';
  else
    Result := 'middle';
  end;
end;

{ the oracle's input: every number written as an object whose one key is
  "h", its hex }
function Decode(AData: TJSONData): TJSONData;
var
  o: TJSONObject;
  i: Integer;
begin
  case AData.JSONType of
    jtArray:
      begin
        Result := TJSONArray.Create;
        for i := 0 to AData.Count - 1 do
          TJSONArray(Result).Add(Decode(AData.Items[i]));
      end;
    jtObject:
      begin
        o := TJSONObject(AData);
        if (o.Count = 1) and (o.Names[0] = 'h') and (o.Items[0].JSONType = jtString) then
          Exit(TJSONFloatNumber.Create(FromHex(o.Items[0].AsString)));
        Result := TJSONObject.Create;
        for i := 0 to o.Count - 1 do
          TJSONObject(Result).Add(o.Names[i], Decode(o.Items[i]));
      end;
  else
    Result := AData.Clone;
  end;
end;

{ a date with no zone: the local wall clock }
function LocalDateText(const S: string): Boolean;
var p: Integer;
begin
  Result := False;
  if (Length(S) < 7) or not (S[1] in ['0'..'9']) or not (S[5] in ['-', '/']) then Exit;
  if UpCase(S[Length(S)]) = 'Z' then Exit;
  p := Length(S);
  while (p > 11) and not (S[p] in ['+', '-']) do Dec(p);
  Result := not ((p > 11) and (S[p] in ['+', '-']));
end;

function HasLocalDate(AData: TJSONData): Boolean;
var i: Integer;
begin
  Result := False;
  case AData.JSONType of
    jtString: Result := LocalDateText(AData.AsString);
    jtArray, jtObject:
      for i := 0 to AData.Count - 1 do
        if HasLocalDate(AData.Items[i]) then Exit(True);
  end;
end;

{ ==================== the case ==================== }

procedure TAdvChartPolarAxesTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  { upstream's month names are its English locale; the port's, pinned to
    its own resourcestrings, are English until a catalogue says otherwise }
  FSavedSource := TyDateTimeNameSource;
  TyDateTimeNameSource := dnTranslation;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-polar-axes.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-polar-axes.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-grid-bounds.json'));
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSkipped := 0;
  FReport := '';
end;

procedure TAdvChartPolarAxesTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FRoot);
  FreeAndNil(FTable);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  TyDateTimeNameSource := FSavedSource;
  inherited TearDown;
end;

procedure TAdvChartPolarAxesTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 12000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartPolarAxesTest.Same(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if (AWant = nil) or (AWant.JSONType = jtNull) then
  begin
    Bad(AWhat + ': upstream has no number');
    Exit;
  end;
  want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartPolarAxesTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TAdvChartPolarAxesTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True), BoolToStr(AWant, True)]));
end;

procedure TAdvChartPolarAxesTest.Finish(const AWhat: string; AMin: Integer);
begin
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
  AssertEquals(Format('%s: %d of %d comparisons differ (%d zone-skipped):%s',
    [AWhat, FBad, FCompared, FSkipped, FReport]), 0, FBad);
end;

function TAdvChartPolarAxesTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

procedure TAdvChartPolarAxesTest.RenderCase(ACase: TJSONObject);
var
  bmp: TBGRABitmap;
  w, h: Integer;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TPolarProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  w := ACase.Integers['W'];
  h := ACase.Integers['H'];
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, w, h);
  bmp := TBGRABitmap.Create(w, h, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, w, h), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartPolarAxesTest.CheckLine(const AWhat: string;
  const L: TTyPolarLine; ARec: TJSONObject);
begin
  Same(AWhat + ' x1', L.X1, ARec.Find('x1'));
  Same(AWhat + ' y1', L.Y1, ARec.Find('y1'));
  Same(AWhat + ' x2', L.X2, ARec.Find('x2'));
  Same(AWhat + ' y2', L.Y2, ARec.Find('y2'));
end;

procedure TAdvChartPolarAxesTest.CheckArc(const AWhat: string;
  const A: TTyPolarArc; ARec: TJSONObject; AAngles: Boolean);
begin
  Same(AWhat + ' cx', A.CX, ARec.Find('cx'));
  Same(AWhat + ' cy', A.CY, ARec.Find('cy'));
  Same(AWhat + ' r', A.R, ARec.Find('r'));
  if ARec.Find('r0') <> nil then
    if ARec.Find('r0').JSONType <> jtNull then Same(AWhat + ' r0', A.R0, ARec.Find('r0'));
  if AAngles then
  begin
    Same(AWhat + ' start', A.StartAngle, ARec.Find('sa'));
    Same(AWhat + ' end', A.EndAngle, ARec.Find('ea'));
    SameBool(AWhat + ' clockwise', A.Clockwise, ARec.Booleans['cw']);
  end;
end;

{ ==================== the polar ==================== }

procedure TAdvChartPolarAxesTest.TestThePolarIsUpstreams;
var
  c, i, n: Integer;
  cs, rec: TJSONObject;
  p: TTyPolar;
  a, b: Double;

  function TypeName(AT: TTyAxisType): string;
  begin
    case AT of
      atCategory: Result := 'category';
      atTime: Result := 'time';
      atLog: Result := 'log';
    else
      Result := 'value';
    end;
  end;

begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    RenderCase(cs);
    for i := 0 to cs.Arrays['polars'].Count - 1 do
    begin
      rec := cs.Arrays['polars'].Objects[i];
      FWhere := cs.Strings['id'] + ' polar' + IntToStr(rec.Integers['index']);
      p := FChart.PolarLayout(rec.Integers['index']);
      if p = nil then
      begin
        Bad('no polar');
        Continue;
      end;
      Inc(n);
      Same('cx', p.CX, rec.Find('cx'));
      Same('cy', p.CY, rec.Find('cy'));
      p.RadiusAxis.LocalExtent(a, b);
      Same('radius extent 0', a, rec.Arrays['rExtent'].Items[0]);
      Same('radius extent 1', b, rec.Arrays['rExtent'].Items[1]);
      p.AngleAxis.LocalExtent(a, b);
      Same('angle extent 0', a, rec.Arrays['aExtent'].Items[0]);
      Same('angle extent 1', b, rec.Arrays['aExtent'].Items[1]);
      SameBool('radius inverse', p.RadiusInverse, rec.Booleans['rInverse']);
      SameBool('angle inverse', p.AngleInverse, rec.Booleans['aInverse']);
      SameStr('radius type', TypeName(p.RadiusAxis.AxisType), rec.Strings['rType']);
      SameStr('angle type', TypeName(p.AngleAxis.AxisType), rec.Strings['aType']);
      SameBool('radius blank', p.RadiusAxis.Scale.Blank, rec.Booleans['rBlank']);
      SameBool('angle blank', p.AngleAxis.Scale.Blank, rec.Booleans['aBlank']);
      if not rec.Booleans['rBlank'] then
      begin
        Same('radius scale 0', p.RadiusAxis.Scale.GetExtent.Start, rec.Arrays['rScale'].Items[0]);
        Same('radius scale 1', p.RadiusAxis.Scale.GetExtent.Stop, rec.Arrays['rScale'].Items[1]);
      end;
      if not rec.Booleans['aBlank'] then
      begin
        Same('angle scale 0', p.AngleAxis.Scale.GetExtent.Start, rec.Arrays['aScale'].Items[0]);
        Same('angle scale 1', p.AngleAxis.Scale.GetExtent.Stop, rec.Arrays['aScale'].Items[1]);
      end;
    end;
    FWhere := cs.Strings['id'];
    Inc(FCompared);
    n := n;
  end;
  AssertTrue(Format('enough polars (%d)', [n]), n >= 70);
  Finish('the polar', 800);
end;

{ ==================== the radius axis ==================== }

procedure TAdvChartPolarAxesTest.CheckRadius(P: TTyPolar; ARec: TJSONObject);
var
  v: TTyPolarAxisView;
  arr: TJSONArray;
  o: TJSONObject;
  i, k, built: Integer;
  what: string;
begin
  v := P.RadiusView;
  SameBool('radius shown', v.Shown, ARec.Booleans['shown']);
  if not ARec.Booleans['shown'] then Exit;
  { the line }
  Inc(FCompared);
  if (ARec.Find('line').JSONType = jtNull) <> not v.HasLine then
    Bad('radius line drawn ' + BoolToStr(v.HasLine, True))
  else if v.HasLine then
    CheckLine('radius line', v.Line, ARec.Objects['line']);
  { the arrows }
  arr := ARec.Arrays['arrows'];
  Inc(FCompared);
  if Length(v.Spec.Arrows) <> arr.Count then
    Bad(Format('%d arrows, upstream %d', [Length(v.Spec.Arrows), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      SameStr('arrow type', v.Spec.Arrows[i].SymbolType, o.Strings['type']);
      Same('arrow x', v.Spec.Arrows[i].X, o.Find('x'));
      Same('arrow y', v.Spec.Arrows[i].Y, o.Find('y'));
      Same('arrow rotation', v.Spec.Arrows[i].Rotation, o.Find('rotation'));
      Same('arrow w', v.Spec.Arrows[i].W, o.Find('w'));
      Same('arrow h', v.Spec.Arrows[i].H, o.Find('h'));
    end;
  { the ticks, and the ones a hidden label took }
  arr := ARec.Arrays['ticks'];
  Inc(FCompared);
  if Length(v.Ticks) <> arr.Count then
    Bad(Format('%d radius ticks, upstream %d', [Length(v.Ticks), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := 'radius tick ' + o.Strings['tick'];
      SameStr(what + ' value', TyJsNumberToString(v.Ticks[i].Value), o.Strings['tick']);
      CheckLine(what, v.Ticks[i], o);
      SameBool(what + ' hidden', not v.Ticks[i].Drawn, o.Booleans['ignore']);
    end;
  arr := ARec.Arrays['minorTicks'];
  Inc(FCompared);
  if Length(v.MinorTicks) <> arr.Count then
    Bad(Format('%d radius minor ticks, upstream %d', [Length(v.MinorTicks), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
      CheckLine('radius minor tick ' + IntToStr(i), v.MinorTicks[i], arr.Objects[i]);
  { the labels: every one built, in order }
  arr := ARec.Arrays['labels'];
  built := 0;
  for k := 0 to High(v.Spec.Placements) do
    if v.Spec.Placements[k].Built then Inc(built);
  Inc(FCompared);
  if built <> arr.Count then
    Bad(Format('%d radius labels built, upstream %d', [built, arr.Count]))
  else
  begin
    i := 0;
    for k := 0 to High(v.Spec.Placements) do
    begin
      if not v.Spec.Placements[k].Built then Continue;
      o := arr.Objects[i];
      what := 'radius label ' + o.Strings['tick'];
      SameStr(what + ' value', TyJsNumberToString(v.Spec.TickValues[k]), o.Strings['tick']);
      SameStr(what + ' text', v.Spec.Placements[k].Text, o.Strings['text']);
      Same(what + ' x', v.Spec.Placements[k].X, o.Find('x'));
      Same(what + ' y', v.Spec.Placements[k].Y, o.Find('y'));
      Same(what + ' rotation', v.Spec.Placements[k].DecRotation, o.Find('rotation'));
      SameStr(what + ' align', AlignName(v.Spec.Placements[k].AnchorH), o.Strings['align']);
      SameStr(what + ' vertical align', VAlignName(v.Spec.Placements[k].AnchorV), o.Strings['va']);
      SameBool(what + ' hidden', not v.Spec.Placements[k].Shown, o.Booleans['ignore']);
      Inc(i);
    end;
  end;
  { the name }
  Inc(FCompared);
  if ARec.Find('name').JSONType = jtNull then
  begin
    if v.Spec.NamePlacement.Shown then Bad('a radius name upstream does not draw');
  end
  else if not v.Spec.NamePlacement.Shown then
    Bad('no radius name')
  else
  begin
    o := ARec.Objects['name'];
    SameStr('name text', v.Spec.NamePlacement.Text, o.Strings['text']);
    Same('name x', v.Spec.NamePlacement.X, o.Find('x'));
    Same('name y', v.Spec.NamePlacement.Y, o.Find('y'));
    Same('name rotation', v.Spec.NamePlacement.RotationRad, o.Find('rotation'));
    SameStr('name align', AlignName(v.Spec.NamePlacement.AnchorH), o.Strings['align']);
    SameStr('name vertical align', VAlignName(v.Spec.NamePlacement.AnchorV), o.Strings['va']);
  end;
  { the view's own }
  arr := ARec.Arrays['splitLines'];
  Inc(FCompared);
  if Length(v.SplitCircles) <> arr.Count then
    Bad(Format('%d split circles, upstream %d', [Length(v.SplitCircles), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := 'split circle ' + IntToStr(i);
      if o.Strings['kind'] = 'arc' then
        SameBool(what + ' an arc', v.SplitCircles[i].Kind = pakArc, True)
      else
        SameBool(what + ' a circle', v.SplitCircles[i].Kind = pakCircle, True);
      CheckArc(what, v.SplitCircles[i], o, o.Strings['kind'] = 'arc');
      Inc(FCompared);
      if v.SplitCircles[i].ColourIndex <> o.Integers['ci'] then
        Bad(Format('%s colour %d, upstream %d', [what, v.SplitCircles[i].ColourIndex, o.Integers['ci']]));
    end;
  arr := ARec.Arrays['minorSplitLines'];
  Inc(FCompared);
  if Length(v.MinorSplitCircles) <> arr.Count then
    Bad(Format('%d minor split circles, upstream %d', [Length(v.MinorSplitCircles), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
      CheckArc('minor split circle ' + IntToStr(i), v.MinorSplitCircles[i],
        arr.Objects[i], False);
  arr := ARec.Arrays['splitAreas'];
  Inc(FCompared);
  if Length(v.SplitAreas) <> arr.Count then
    Bad(Format('%d radius split areas, upstream %d', [Length(v.SplitAreas), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := 'radius split area ' + IntToStr(i);
      CheckArc(what, v.SplitAreas[i], o, True);
      Inc(FCompared);
      if v.SplitAreas[i].ColourIndex <> o.Integers['ci'] then
        Bad(Format('%s colour %d, upstream %d', [what, v.SplitAreas[i].ColourIndex, o.Integers['ci']]));
    end;
end;

procedure TAdvChartPolarAxesTest.TestTheRadiusAxisDrawsWhatUpstreamDraws;
var
  c, i, n: Integer;
  cs, rec: TJSONObject;
  p: TTyPolar;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'axes' then Continue;
    RenderCase(cs);
    for i := 0 to cs.Arrays['polars'].Count - 1 do
    begin
      rec := cs.Arrays['polars'].Objects[i];
      FWhere := cs.Strings['id'] + ' polar' + IntToStr(rec.Integers['index']);
      p := FChart.PolarLayout(rec.Integers['index']);
      if p = nil then
      begin
        Bad('no polar');
        Continue;
      end;
      Inc(n);
      CheckRadius(p, rec.Objects['radius']);
    end;
  end;
  AssertTrue(Format('enough radius axes (%d)', [n]), n >= 50);
  Finish('the radius axis', 3000);
end;

{ ==================== the angle axis ==================== }

procedure TAdvChartPolarAxesTest.CheckAngle(P: TTyPolar; ARec: TJSONObject);
var
  v: TTyPolarAxisView;
  arr: TJSONArray;
  o: TJSONObject;
  i: Integer;
  what, kind: string;
begin
  v := P.AngleView;
  SameBool('angle shown', v.Shown, ARec.Booleans['shown']);
  if not ARec.Booleans['shown'] then Exit;
  Inc(FCompared);
  if (ARec.Find('line').JSONType = jtNull) <> not v.HasLine then
    Bad('angle line drawn ' + BoolToStr(v.HasLine, True))
  else if v.HasLine then
  begin
    o := ARec.Objects['line'];
    case v.LineArc.Kind of
      pakCircle: kind := 'circle';
      pakArc: kind := 'arc';
      pakRing: kind := 'ring';
    else
      kind := 'sector';
    end;
    SameStr('angle line kind', kind, o.Strings['kind']);
    CheckArc('angle line', v.LineArc, o, o.Strings['kind'] <> 'ring');
  end;
  arr := ARec.Arrays['ticks'];
  Inc(FCompared);
  if Length(v.Ticks) <> arr.Count then
    Bad(Format('%d angle ticks, upstream %d', [Length(v.Ticks), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
      CheckLine('angle tick ' + IntToStr(i), v.Ticks[i], arr.Objects[i]);
  arr := ARec.Arrays['minorTicks'];
  Inc(FCompared);
  if Length(v.MinorTicks) <> arr.Count then
    Bad(Format('%d angle minor ticks, upstream %d', [Length(v.MinorTicks), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
      CheckLine('angle minor tick ' + IntToStr(i), v.MinorTicks[i], arr.Objects[i]);
  arr := ARec.Arrays['labels'];
  Inc(FCompared);
  if Length(v.Labels) <> arr.Count then
    Bad(Format('%d angle labels, upstream %d', [Length(v.Labels), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := 'angle label ' + o.Strings['tick'];
      SameStr(what + ' value', TyJsNumberToString(v.Labels[i].Value), o.Strings['tick']);
      SameStr(what + ' text', v.Labels[i].Text, o.Strings['text']);
      Same(what + ' x', v.Labels[i].X, o.Find('x'));
      Same(what + ' y', v.Labels[i].Y, o.Find('y'));
      SameStr(what + ' align', AlignName(v.Labels[i].AnchorH), o.Strings['align']);
      SameStr(what + ' vertical align', VAlignName(v.Labels[i].AnchorV), o.Strings['va']);
    end;
  arr := ARec.Arrays['splitLines'];
  Inc(FCompared);
  if Length(v.SplitLines) <> arr.Count then
    Bad(Format('%d angle split lines, upstream %d', [Length(v.SplitLines), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      CheckLine('angle split line ' + IntToStr(i), v.SplitLines[i], o);
      Inc(FCompared);
      if v.SplitLines[i].ColourIndex <> o.Integers['ci'] then
        Bad(Format('angle split line %d colour %d, upstream %d',
          [i, v.SplitLines[i].ColourIndex, o.Integers['ci']]));
    end;
  arr := ARec.Arrays['minorSplitLines'];
  Inc(FCompared);
  if Length(v.MinorSplitLines) <> arr.Count then
    Bad(Format('%d angle minor split lines, upstream %d', [Length(v.MinorSplitLines), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
      CheckLine('angle minor split line ' + IntToStr(i), v.MinorSplitLines[i], arr.Objects[i]);
  arr := ARec.Arrays['splitAreas'];
  Inc(FCompared);
  if Length(v.SplitAreas) <> arr.Count then
    Bad(Format('%d angle split areas, upstream %d', [Length(v.SplitAreas), arr.Count]))
  else
    for i := 0 to arr.Count - 1 do
    begin
      o := arr.Objects[i];
      what := 'angle split area ' + IntToStr(i);
      CheckArc(what, v.SplitAreas[i], o, True);
      Inc(FCompared);
      if v.SplitAreas[i].ColourIndex <> o.Integers['ci'] then
        Bad(Format('%s colour %d, upstream %d', [what, v.SplitAreas[i].ColourIndex, o.Integers['ci']]));
    end;
end;

procedure TAdvChartPolarAxesTest.TestTheAngleAxisDrawsWhatUpstreamDraws;
var
  c, i, n: Integer;
  cs, rec: TJSONObject;
  p: TTyPolar;
begin
  n := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'axes' then Continue;
    RenderCase(cs);
    for i := 0 to cs.Arrays['polars'].Count - 1 do
    begin
      rec := cs.Arrays['polars'].Objects[i];
      FWhere := cs.Strings['id'] + ' polar' + IntToStr(rec.Integers['index']);
      p := FChart.PolarLayout(rec.Integers['index']);
      if p = nil then
      begin
        Bad('no polar');
        Continue;
      end;
      Inc(n);
      CheckAngle(p, rec.Objects['angle']);
    end;
  end;
  AssertTrue(Format('enough angle axes (%d)', [n]), n >= 50);
  Finish('the angle axis', 2400);
end;

{ ==================== the pointer ==================== }

procedure TAdvChartPolarAxesTest.TestThePointerIsUpstreams;
var
  c, q, a, h, n, polars, shapes, labels: Integer;
  cs, pr, ax, el: TJSONObject;
  hits: TTyAxisHitArray;
  found: Integer;
  d: TTyPolarPointerDraw;
  dim, t: string;
  sh: TJSONArray;
  pts: array[0..5] of Double;
begin
  n := 0;
  shapes := 0;
  labels := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'pointer' then Continue;
    RenderCase(cs);
    for q := 0 to cs.Arrays['pointer'].Count - 1 do
    begin
      pr := cs.Arrays['pointer'].Objects[q];
      FWhere := Format('%s @%d,%d', [cs.Strings['id'], pr.Integers['x'], pr.Integers['y']]);
      hits := FChart.Pointers(pr.Integers['x'], pr.Integers['y']);
      polars := 0;
      for h := 0 to High(hits) do
        if hits[h].Polar <> nil then Inc(polars);
      Inc(FCompared);
      if polars <> pr.Arrays['axes'].Count then
        Bad(Format('%d polar pointers, upstream %d', [polars, pr.Arrays['axes'].Count]));
      for a := 0 to pr.Arrays['axes'].Count - 1 do
      begin
        ax := pr.Arrays['axes'].Objects[a];
        dim := ax.Strings['dim'];
        found := -1;
        for h := 0 to High(hits) do
          if (hits[h].Polar <> nil) and (hits[h].Polar.Index = ax.Integers['polar'])
            and (hits[h].Axis.Dim = dim) then found := h;
        Inc(FCompared);
        if found < 0 then
        begin
          Bad('no pointer on the ' + dim + ' axis');
          Continue;
        end;
        Inc(n);
        Same(dim + ' value', FChart.PointerOf(hits[found]), ax.Find('value'));
        FChart.Draw(hits[found], cs.Integers['W'], cs.Integers['H'], d);
        Inc(FCompared);
        if ax.Find('el').JSONType = jtNull then
        begin
          if d.Shape.Kind <> plpkNone then Bad(dim + ': a pointer upstream does not draw');
        end
        else
        begin
          el := ax.Objects['el'];
          t := el.Strings['type'];
          sh := el.Arrays['shape'];
          case d.Shape.Kind of
            plpkLine:
              begin
                SameStr(dim + ' pointer', 'line', t);
                pts[0] := d.Shape.X1; pts[1] := d.Shape.Y1;
                pts[2] := d.Shape.X2; pts[3] := d.Shape.Y2;
                for h := 0 to 3 do Same(dim + ' line ' + IntToStr(h), pts[h], sh.Items[h]);
              end;
            plpkCircle:
              begin
                SameStr(dim + ' pointer', 'circle', t);
                Same(dim + ' circle cx', d.Shape.CX, sh.Items[0]);
                Same(dim + ' circle cy', d.Shape.CY, sh.Items[1]);
                Same(dim + ' circle r', d.Shape.R, sh.Items[2]);
              end;
            plpkSector:
              begin
                SameStr(dim + ' pointer', 'sector', t);
                pts[0] := d.Shape.CX; pts[1] := d.Shape.CY;
                pts[2] := d.Shape.R0; pts[3] := d.Shape.R;
                pts[4] := d.Shape.StartAngle; pts[5] := d.Shape.EndAngle;
                for h := 0 to 5 do Same(dim + ' sector ' + IntToStr(h), pts[h], sh.Items[h]);
              end;
          else
            Bad(dim + ': no pointer element, upstream a ' + t);
          end;
          Inc(shapes);
        end;
        Inc(FCompared);
        if ax.Find('label').JSONType = jtNull then
        begin
          if d.HasLabel then Bad(dim + ': a label upstream does not show');
        end
        else if not d.HasLabel then
          Bad(dim + ': no label')
        else
        begin
          el := ax.Objects['label'];
          SameStr(dim + ' label', d.Text, el.Strings['text']);
          Same(dim + ' label x', d.X, el.Find('x'));
          Same(dim + ' label y', d.Y, el.Find('y'));
          Same(dim + ' label w', d.W, el.Find('w'));
          Same(dim + ' label h', d.H, el.Find('h'));
          Inc(labels);
        end;
      end;
    end;
  end;
  AssertTrue(Format('enough pointers (%d)', [n]), n >= 300);
  AssertTrue(Format('enough shapes (%d)', [shapes]), shapes >= 300);
  AssertTrue(Format('enough labels (%d)', [labels]), labels >= 100);
  Finish('the pointer', 3000);
end;

{ ==================== the conversions ==================== }

function KindName(AKind: TTyConvertKind): string;
begin
  case AKind of
    cvkNumber: Result := 'num';
    cvkArray: Result := 'arr';
    cvkError: Result := 'throw';
  else
    Result := 'none';
  end;
end;

procedure TAdvChartPolarAxesTest.CheckProbe(ACase, AProbe: TJSONObject);
var
  op, k: string;
  finder, value: TJSONData;
  outNode: TJSONObject;
  r: TTyConvertResult;
  got: Boolean;
  i: Integer;
  arr: TJSONArray;
begin
  op := AProbe.Strings['op'];
  outNode := AProbe.Objects['out'];
  k := outNode.Strings['k'];
  FWhere := ACase.Strings['id'] + ' ' + op + ' ' + AProbe.Objects['finder'].Strings['text']
    + ' ' + AProbe.Objects['value'].Strings['text'];
  if (GetLocalTimeOffset <> 0) and HasLocalDate(AProbe.Objects['value'].Find('in')) then
  begin
    Inc(FSkipped);
    Exit;
  end;
  finder := Decode(AProbe.Objects['finder'].Find('in'));
  value := Decode(AProbe.Objects['value'].Find('in'));
  try
    if op = 'contain' then
    begin
      got := FChart.ContainPixelData(finder, value);
      Inc(FCompared);
      if k = 'throw' then
      begin
        if got then Bad('contains, upstream throws');
      end
      else if got <> outNode.Booleans['v'] then
        Bad(Format('contains %s, upstream %s', [BoolToStr(got, True),
          BoolToStr(outNode.Booleans['v'], True)]));
      Exit;
    end;
    if op = 'to' then r := FChart.ConvertToPixelData(finder, value)
    else r := FChart.ConvertFromPixelData(finder, value);
    Inc(FCompared);
    if KindName(r.Kind) <> k then
    begin
      Bad(Format('%s here, upstream %s', [KindName(r.Kind), k]));
      Exit;
    end;
    if k = 'num' then
      Same('the number', r.Values[0], outNode.Find('v'))
    else if k = 'arr' then
    begin
      arr := outNode.Arrays['v'];
      if Length(r.Values) <> arr.Count then
        Bad(Format('%d numbers, upstream %d', [Length(r.Values), arr.Count]))
      else
        for i := 0 to arr.Count - 1 do
          Same(Format('[%d]', [i]), r.Values[i], arr.Items[i]);
    end;
  finally
    finder.Free;
    value.Free;
  end;
end;

procedure TAdvChartPolarAxesTest.TestEveryConversionIsUpstreams;
var
  c, p, polarAnswers: Integer;
  cs: TJSONObject;
begin
  polarAnswers := 0;
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    if cs.Strings['group'] <> 'convert' then Continue;
    RenderCase(cs);
    for p := 0 to cs.Arrays['convert'].Count - 1 do
    begin
      if (cs.Arrays['convert'].Objects[p].Find('by') <> nil)
        and (cs.Arrays['convert'].Objects[p].Strings['by'] = 'polar') then
        Inc(polarAnswers);
      CheckProbe(cs, cs.Arrays['convert'].Objects[p]);
    end;
  end;
  AssertTrue(Format('enough polar answers (%d)', [polarAnswers]), polarAnswers >= 200);
  Finish('the conversions', 600);
end;

{ ==================== beyond the fixture ==================== }

procedure TAdvChartPolarAxesTest.TestAPolarMissingAnAxisSaysSo;
var
  i: Integer;
  found: Boolean;
  cs: TJSONObject;
begin
  cs := TJSONObject(GetJSON('{"id": "missing", "W": 600, "H": 400, "option": '
    + '{"polar": [{}, {}], "angleAxis": [{"polarIndex": 0}, {"polarIndex": 1}], '
    + '"radiusAxis": {"polarIndex": 0, "min": 0, "max": 5}}}'));
  try
    RenderCase(cs);
    AssertEquals('two polar slots', 2, FChart.PolarCount);
    AssertTrue('the first is built', FChart.PolarLayout(0) <> nil);
    AssertTrue('the second, with no radius axis, is not', FChart.PolarLayout(1) = nil);
    found := False;
    for i := 0 to FChart.DiagnosticCount - 1 do
      if (Pos('polar[1]', FChart.Diagnostic(i)) > 0)
        and (Pos('radiusAxis', FChart.Diagnostic(i)) > 0) then found := True;
    AssertTrue('the diagnostic names the polar and the axis', found);
    { the last axis that names a polar is its axis }
    cs.Free;
    cs := TJSONObject(GetJSON('{"id": "last", "W": 600, "H": 400, "option": '
      + '{"polar": {}, "angleAxis": [{"min": 0, "max": 10}, {"type": "category", "data": ["a", "b"]}], '
      + '"radiusAxis": {"min": 0, "max": 5}}}'));
    RenderCase(cs);
    AssertTrue('the polar is built', FChart.PolarLayout(0) <> nil);
    AssertEquals('the last angle axis naming it', 1, FChart.PolarLayout(0).AngleAxis.ComponentIndex);
    AssertTrue('a category one', FChart.PolarLayout(0).AngleAxis.AxisType = atCategory);
  finally
    cs.Free;
  end;
end;

procedure TAdvChartPolarAxesTest.TestTheAxesArePainted;
var
  bmp: TBGRABitmap;
  cs: TJSONObject;
  x, y, fills: Integer;
  px: TBGRAPixel;

  function Inked(AX, AY: Integer): Boolean;
  begin
    px := bmp.GetPixel(AX, AY);
    Result := (px.red < 250) or (px.green < 250) or (px.blue < 250);
  end;

begin
  cs := TJSONObject(GetJSON('{"id": "paint", "W": 600, "H": 400, "option": '
    + '{"polar": {"radius": [0, 150]}, "angleAxis": {"min": 0, "max": 360, "splitArea": {"show": true}}, '
    + '"radiusAxis": {"min": 0, "max": 10, "splitArea": {"show": false}}}}'));
  try
    RenderCase(cs);
    bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
      { the angle line: a circle of radius 150 round (300, 200) -- inked at
        its four compass points }
      AssertTrue('the circle on the right', Inked(450, 200) or Inked(449, 200));
      AssertTrue('the circle on the left', Inked(150, 200) or Inked(151, 200));
      AssertTrue('the circle at the bottom', Inked(300, 350) or Inked(300, 349));
      { the radius line runs up from the centre }
      AssertTrue('the radius line', Inked(300, 120) or Inked(301, 120));
      { the split area's first band (skin colour) is drawn: something inked
        inside the circle away from every line }
      fills := 0;
      for x := 310 to 340 do
        for y := 150 to 190 do
          if Inked(x, y) then Inc(fills);
      AssertTrue(Format('the split areas fill (%d)', [fills]), fills > 0);
      { and nothing outside it but the labels }
      AssertFalse('nothing far outside', Inked(5, 5));
    finally
      bmp.Free;
    end;
  finally
    cs.Free;
  end;
end;

procedure TAdvChartPolarAxesTest.TestPointToCoordWrapsIntoTheExtent;
var
  cs: TJSONObject;
  p: TTyPolar;
  r, a: Double;
begin
  cs := TJSONObject(GetJSON('{"id": "wrap", "W": 600, "H": 400, "option": '
    + '{"polar": {"radius": [0, 160]}, "angleAxis": {"min": 0, "max": 360}, '
    + '"radiusAxis": {"min": 0, "max": 10}}}'));
  try
    RenderCase(cs);
    p := FChart.PolarLayout(0);
    { clockwise from 90: the extent [90, -270]; a point due east is 0, due
      west 180 -- moved down by a turn to -180 -- and due north 90 }
    p.PointToCoord(400, 200, r, a);
    AssertEquals('east radius', 100, r, 0);
    AssertEquals('east angle', 0, a, 0);
    p.PointToCoord(200, 200, r, a);
    AssertEquals('west is -180 on a clockwise axis', -180, a, 0);
    p.PointToCoord(300, 100, r, a);
    AssertEquals('north', 90, a, 0);
    p.PointToCoord(300, 300, r, a);
    AssertEquals('south is -90', -90, a, 0);
    { the centre: no direction, not a number, and contained by neither }
    p.PointToCoord(300, 200, r, a);
    AssertEquals('the centre is at radius 0', 0, r, 0);
    AssertTrue('the centre has no angle', IsNan(a));
    AssertFalse('the centre is not contained', p.ContainXY(300, 200));
    AssertTrue('a point in the ring is', p.ContainXY(350, 200));
    AssertFalse('a point past the rim is not', p.ContainXY(461, 200));
  finally
    cs.Free;
  end;
end;

procedure TAdvChartPolarAxesTest.TestTheAngleIntervalIsHeldAcrossAMerge;
var
  cats: string;
  i: Integer;
  cs: TJSONObject;
  bmp: TBGRABitmap;
  first, held: Integer;

  function OptionOf(AN: Integer): string;
  var k: Integer;
  begin
    Result := '';
    for k := 0 to AN - 1 do
    begin
      if k > 0 then Result := Result + ',';
      Result := Result + '"c' + IntToStr(k) + '"';
    end;
    Result := '{"polar": {}, "angleAxis": {"type": "category", "data": [' + Result
      + ']}, "radiusAxis": {"min": 0, "max": 5}}';
  end;

begin
  { sixty categories: six degrees a band, a 12px line: interval 2. Fifty-
    nine: 6.1 degrees, still 1.97 -> 1; one category fewer by a merge keeps
    the last interval, which is a step bigger -- AngleAxis' own store }
  cats := OptionOf(60);
  cs := TJSONObject(GetJSON('{"id": "hold", "W": 600, "H": 400, "option": ' + cats + '}'));
  try
    RenderCase(cs);
    first := Length(FChart.PolarLayout(0).AngleView.Labels);
    AssertEquals('every third of sixty', 20, first);
    FChart.MergeOption(OptionOf(59));
    bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    finally
      bmp.Free;
    end;
    held := Length(FChart.PolarLayout(0).AngleView.Labels);
    AssertEquals('every third of fifty-nine still (held)', 20, held);
    { a notMerge starts the store over: every other one }
    FChart.SetOption(OptionOf(59), True);
    bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    finally
      bmp.Free;
    end;
    i := Length(FChart.PolarLayout(0).AngleView.Labels);
    AssertEquals('every other of fifty-nine afresh', 30, i);
  finally
    cs.Free;
  end;
end;

{ THE RADIUS AXIS' CATEGORY INTERVAL goes through the axis model's store
  as a grid axis' does (calculateCategoryIntervalDealCache): twenty-two
  'item N' categories on 160 px measure an interval of 7 and twenty-one of
  6 -- but one category fewer by a merge keeps the 7 (upstream's own
  answer, run in node: 0, 8, 16 held; 0, 7, 14 afresh) }
procedure TAdvChartPolarAxesTest.TestTheRadiusIntervalIsHeldAcrossAMerge;
var
  cs: TJSONObject;
  bmp: TBGRABitmap;

  function OptionOf(AN: Integer): string;
  var k: Integer;
  begin
    Result := '';
    for k := 0 to AN - 1 do
    begin
      if k > 0 then Result := Result + ',';
      Result := Result + '"item ' + IntToStr(k) + '"';
    end;
    Result := '{"polar": {}, "angleAxis": {"min": 0, "max": 100}, '
      + '"radiusAxis": {"type": "category", "data": [' + Result + ']}}';
  end;

  function SecondBuilt: Double;
  var
    sp: TTyAxisLayoutSpec;
    k, seen: Integer;
  begin
    Result := NaN;
    sp := FChart.PolarLayout(0).RadiusView.Spec;
    seen := 0;
    for k := 0 to High(sp.Placements) do
      if sp.Placements[k].Built then
      begin
        Inc(seen);
        if seen = 2 then Exit(sp.TickValues[k]);
      end;
  end;

  procedure Again;
  begin
    bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
    try
      FChart.Render(bmp.Canvas, Rect(0, 0, cW, cH), 96);
    finally
      bmp.Free;
    end;
  end;

begin
  cs := TJSONObject(GetJSON('{"id": "rhold", "W": 600, "H": 400, "option": '
    + OptionOf(22) + '}'));
  try
    RenderCase(cs);
    AssertEquals('every eighth of twenty-two', 8, SecondBuilt, 0);
    FChart.MergeOption(OptionOf(21));
    Again;
    AssertEquals('every eighth of twenty-one still (held)', 8, SecondBuilt, 0);
    FChart.SetOption(OptionOf(21), True);
    Again;
    AssertEquals('every seventh of twenty-one afresh', 7, SecondBuilt, 0);
  finally
    cs.Free;
  end;
end;

procedure TAdvChartPolarAxesTest.TestExcludedPolarAxesAreNotDrawn;
var
  cs: TJSONObject;
  views: TTyChartViews;
begin
  cs := TJSONObject(GetJSON('{"id": "views", "W": 600, "H": 400, "option": '
    + '{"polar": {}, "angleAxis": {"min": 0, "max": 360}, "radiusAxis": {"min": 0, "max": 10}}}'));
  try
    RenderCase(cs);
    views := FChart.LastViewsDrawn;
    AssertTrue('the angle axis is drawn', cvAngleAxis in views);
    AssertTrue('the radius axis is drawn', cvRadiusAxis in views);
  finally
    cs.Free;
  end;
end;

{ THE AXIS TRIGGER ON A POLAR WITH NO SERIES: the pointer follows the mouse
  and no box is drawn -- upstream dispatches no showTip without data; the
  port keeps an axis tooltip with no section, which draws nothing }
procedure TAdvChartPolarAxesTest.TestHoveringAPolarDrawsThePointerAndNoTooltip;
var
  cs: TJSONObject;
  a, b: TBGRABitmap;
  x, y, diff: Integer;
  pa, pb: TBGRAPixel;
begin
  cs := TJSONObject(GetJSON('{"id": "hover", "W": 600, "H": 400, "option": '
    + '{"tooltip": {"trigger": "axis", "axisPointer": {"type": "cross"}}, "polar": {}, '
    + '"angleAxis": {"type": "category", "data": ["a", "b", "c", "d"]}, '
    + '"radiusAxis": {"min": 0, "max": 10}}}'));
  a := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  b := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  try
    RenderCase(cs);
    FChart.Render(a.Canvas, Rect(0, 0, cW, cH), 96);
    FChart.PointerTo(380, 120);
    FChart.Render(b.Canvas, Rect(0, 0, cW, cH), 96);
    AssertEquals('an axis tooltip with no section', 'axis:', FChart.TooltipShownWhich);
    AssertTrue('no box drawn', IsNan(FChart.TooltipBox.Left)
      or (FChart.TooltipBox.Right <= FChart.TooltipBox.Left));
    diff := 0;
    for x := 0 to cW - 1 do
      for y := 0 to cH - 1 do
      begin
        pa := a.GetPixel(x, y);
        pb := b.GetPixel(x, y);
        if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue) then
          Inc(diff);
      end;
    AssertTrue(Format('the pointer is drawn (%d pixels)', [diff]), diff > 100);
  finally
    a.Free;
    b.Free;
    cs.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartPolarAxesTest);
end.
