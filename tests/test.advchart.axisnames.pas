unit test.advchart.axisnames;
{$mode objfpc}{$H+}
{ Where a cartesian axis' NAME goes -- held to upstream's own layout.

  tools/advchart-oracle/axis-names.js runs the real ECharts 6.1 build and
  records, per case and per axis, each pass that laid a name out: the axis
  frame the pass used (the line's position, turn, extent, label offset, the
  side that is out), the margin level, every label in the order upstream
  keeps them with its box, matrix and screen rect, and the name itself --
  its alignment, local turn, padded box, the matrix before the move, the
  rect before and after, each translation, and where it is finally drawn.

  THREE LEVELS:
  1. the preconditions: the text is measured with zrender's own table, bit
     for bit, and the trigonometry of a quarter turn gives V8's bits -- the
     name of a y axis carries 6.123233995736766e-17 into its anchor;
  2. the name layout alone, bitwise: upstream's frame, level and label
     geometry fed to TyLayoutAxisName must give upstream's alignment, turn,
     box, anchor, matrix, rects, obstacle and moves to the last bit;
  3. the whole pipeline -- options read, labels laid out by the port, two
     passes, the grid shrunk -- within the case's tolerance: the port builds
     its label boxes its own way round, and a name moved by one inherits
     its rounding. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
     tyControls.AdvChart.Layout, tyControls.AdvChart.AxisName,
     tyControls.AdvChart.JsMath,
     test.advchart.gridbounds;
type
  TAdvChartAxisNamesOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FM: ITyTextMeasurer;
    FOpt: TTyChartOption;
    FBuild: TTyChartBuild;
    FStores: array of TTyDataStore;
    FIndex: TTyAxisSeriesIndex;
    FStyle: TTyAxisTextStyle;
    procedure SetUp; override;
    procedure TearDown; override;
    procedure FreeRun;
    procedure RunCase(ACase: TJSONObject);
    function SpecAfter(const AOption: string; const ADim: string): TTyAxisLayoutSpec;
  published
    procedure TestTheMeasurerIsZrendersToTheBit;
    procedure TestAQuarterTurnIsV8sToTheBit;
    procedure TestEveryNameIsUpstreamsToTheBit;
    procedure TestEveryDrawnNameAsUpstreamPlacesIt;
    procedure TestEveryGridAsUpstreamSolvesIt;
    { ---- what the fixture's cases do not reach ---- }
    procedure TestATurnedNameThatMeetsALabelIsLeftWhereItIs;
    procedure TestTheNameIsMeasuredInItsOwnFont;
    procedure TestTheNameOptionsAreReadAsUpstreamReadsThem;
    procedure TestTheTextLayoutsTurnAsUpstreamTurnsThem;
    procedure TestTheLevelBoundaryGoesToTheSmallerMargin;
    procedure TestTheBandIsUnitedInTheOrderTheLabelsWereLaidOut;
    procedure TestAMoveAgainstTheAxisMeetsTheFarLabelFirst;
    procedure TestTheShortestAllowedTranslationWins;
    procedure TestLabelsAreSortedAlongTheirAxisStably;
    procedure TestAMiddleNameOnTheZeroLineStaysWithTheLabels;
    procedure TestTheEstimateFindsTheLineOnTheOtherZero;
    procedure TestTheMarginLevelIsOfTheCanvas;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-axis-names.json';
end;

function AxisFor(ABuild: TTyChartBuild; AGrid: Integer; const ADim: string;
  AIndex: Integer): TTyAxis; forward;
function TestTextStyle: TTyAxisTextStyle; forward;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Num(AObj: TJSONObject; const AKey: string): Double;
begin
  Result := FromHex(AObj.Strings[AKey]);
end;

function NumAt(AArr: TJSONArray; AIndex: Integer): Double;
begin
  Result := FromHex(AArr.Strings[AIndex]);
end;

function XYWHOf(AObj: TJSONObject): TTyXYWH;
begin
  Result := TyXYWH(Num(AObj, 'x'), Num(AObj, 'y'), Num(AObj, 'width'),
    Num(AObj, 'height'));
end;

function MatOf(AArr: TJSONArray): TTyMat2D;
var k: Integer;
begin
  for k := 0 to 5 do Result[k] := NumAt(AArr, k);
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function IsDeferred(ACase: TJSONObject): Boolean;
begin
  Result := (ACase.Find('deferred') <> nil) and ACase.Booleans['deferred'];
end;

{ Bit for bit: NaN matches NaN, and nought matches nought of either sign
  only if the bits do. }
function Same(A, B: Double): Boolean;
var qa, qb: QWord;
begin
  Move(A, qa, SizeOf(qa));
  Move(B, qb, SizeOf(qb));
  Result := qa = qb;
end;

function SameRect(const A, B: TTyXYWH): Boolean;
begin
  Result := Same(A.X, B.X) and Same(A.Y, B.Y) and Same(A.W, B.W)
    and Same(A.H, B.H);
end;

function RectStr(const A: TTyXYWH): string;
begin
  Result := Format('[%s, %s, %s, %s]', [Fmt(A.X), Fmt(A.Y), Fmt(A.W), Fmt(A.H)]);
end;

function AlignOf(const S: string): TTyTextAnchorH;
begin
  if S = 'right' then Result := tahRight
  else if S = 'center' then Result := tahCentre
  else Result := tahLeft;
end;

function VAlignOf(const S: string): TTyTextAnchorV;
begin
  if S = 'bottom' then Result := tavBottom
  else if S = 'middle' then Result := tavMiddle
  else Result := tavTop;
end;

function LocationOf(const S: string): TTyAxisNameLocation;
begin
  if S = 'start' then Result := anlStart
  else if (S = 'middle') or (S = 'center') then Result := anlMiddle
  else Result := anlEnd;
end;

{ ==================== plumbing ==================== }

procedure TAdvChartAxisNamesOracleTest.SetUp;
var
  sl: TStringList;
  ratios: TJSONObject;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  ratios := TJSONObject(FRoot).Objects['ratios'];
  FM := TZrSsrMeasurer.Create(ratios.Arrays['ratio'], ratios.Integers['firstCode']);
  FOpt := TTyChartOption.Create;
  FIndex := TTyAxisSeriesIndex.Create;
  FStyle := TestTextStyle;
end;

procedure TAdvChartAxisNamesOracleTest.FreeRun;
var i: Integer;
begin
  for i := 0 to High(FStores) do FStores[i].Free;
  FStores := nil;
  FreeAndNil(FBuild);
end;

procedure TAdvChartAxisNamesOracleTest.TearDown;
begin
  FreeRun;
  FreeAndNil(FIndex);
  FreeAndNil(FOpt);
  FM := nil;
  FreeAndNil(FRoot);
  inherited TearDown;
end;

function TestTextStyle: TTyAxisTextStyle;
begin
  Result := Default(TTyAxisTextStyle);
  { upstream's axis label and name: 12px sans-serif, margin 8, tick 5, gap 15 }
  Result.FontName := 'sans-serif';
  Result.FontSizeLogical := 12;
  Result.FontWeight := 400;
  Result.LabelMarginLogical := 8;
  Result.TickLengthLogical := 5;
  Result.NameGapLogical := 15;
  Result.NameFontName := 'sans-serif';
  Result.NameFontSizeLogical := 12;
  Result.NameFontWeight := 400;
end;

procedure TAdvChartAxisNamesOracleTest.RunCase(ACase: TJSONObject);
var
  bind: TTySeriesBindingArray;
  dims: TTySeriesDimArray;
  i, k: Integer;
  st: TTyDataStore;
begin
  FreeRun;
  AssertTrue(ACase.Strings['name'] + ' parses',
    FOpt.SetOptionText(ACase.Objects['option'].AsJSON));
  FBuild := TyBuildGrids(FOpt, TyRectF(0, 0, ACase.Integers['W'],
    ACase.Integers['H']));
  bind := TyBindSeries(FOpt, FBuild);
  SetLength(FStores, Length(bind));
  for i := 0 to High(bind) do
  begin
    st := TTyDataStore.Create;
    FStores[i] := st;
    if not bind[i].HasAxes then Continue;
    dims := TySeriesCartesianDims(bind[i].Cart, 0);
    for k := 0 to High(dims) do
    begin
      st.AddDimension(dims[k].Name, dims[k].Kind);
      if dims[k].Axis <> nil then st.UseOrdinalMeta(k, dims[k].Axis.Categories);
    end;
    TyFillSeriesStore(FOpt, i, dims, st);
  end;
  FIndex.Clear;
  TyIndexSeries(bind, FIndex);
  TyApplyAxisExtents(FOpt, FBuild, bind, FStores, nil, FIndex);
  TyLayoutGrids(FBuild, FOpt, FM, 96, FStyle);
end;

{ One axis' spec after the whole pipeline, for an option with no series. }
function TAdvChartAxisNamesOracleTest.SpecAfter(const AOption: string;
  const ADim: string): TTyAxisLayoutSpec;
var
  cs: TJSONObject;
  axis: TTyAxis;
begin
  cs := TJSONObject(GetJSON('{"name": "a unit case", "W": 600, "H": 400, "grid": 0}'));
  try
    cs.Add('option', GetJSON(AOption));
    RunCase(cs);
  finally
    cs.Free;
  end;
  axis := AxisFor(FBuild, 0, ADim, 0);
  AssertNotNull('the axis', axis);
  Result := FBuild.Grid(0).SpecFor(axis)^;
end;

{ One pass of one axis as the fixture recorded it, turned into what the pure
  layout reads: the spec's name inputs, the frame, the level. }
procedure SpecOf(AAxis: TJSONObject; out ASpec: TTyAxisLayoutSpec);
var
  sp, mg: TJSONObject;
  d: TJSONData;
  k: Integer;
begin
  ASpec := Default(TTyAxisLayoutSpec);
  sp := AAxis.Objects['spec'];
  if AAxis.Strings['dim'] = 'x' then ASpec.Side := asBottom else ASpec.Side := asLeft;
  d := sp.Find('text');
  if (d <> nil) and (d.JSONType = jtString) then ASpec.Name := d.AsString;
  ASpec.NameLocation := LocationOf(sp.Strings['location']);
  ASpec.NameGapLogical := Num(sp, 'gap');
  d := sp.Find('rotate');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    ASpec.HasNameRotate := True;
    ASpec.NameRotateRad := FromHex(d.AsString);
  end;
  d := sp.Find('align');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    ASpec.HasNameAlignH := True;
    ASpec.NameAlignH := AlignOf(d.AsString);
  end;
  d := sp.Find('verticalAlign');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    ASpec.HasNameAlignV := True;
    ASpec.NameAlignV := VAlignOf(d.AsString);
  end;
  mg := sp.Objects['margin'];
  if mg.Strings['kind'] = 'textMargin' then
  begin
    ASpec.NameMarginKind := nmkTextMargin;
    for k := 0 to 3 do ASpec.NameMargin[k] := NumAt(mg.Arrays['value'], k);
  end
  else if mg.Strings['kind'] = 'minMargin' then
  begin
    ASpec.NameMarginKind := nmkMinMargin;
    { the fixture records the half each side gets }
    ASpec.NameMinMarginLogical := NumAt(mg.Arrays['value'], 0) * 2;
  end;
  ASpec.NameNoMove := not sp.Booleans['moveOverlap'];
  ASpec.NameFontName := 'sans-serif';
  ASpec.NameFontSizeLogical := 12;
  ASpec.NameFontWeight := 400;
end;

function FrameOf(APass: TJSONObject): TTyAxisNameFrame;
var cfg: TJSONObject;
begin
  Result := Default(TTyAxisNameFrame);
  cfg := APass.Objects['cfg'];
  Result.PosX := NumAt(cfg.Arrays['position'], 0);
  Result.PosY := NumAt(cfg.Arrays['position'], 1);
  Result.Rotation := Num(cfg, 'rotation');
  Result.Ext0 := NumAt(cfg.Arrays['extent'], 0);
  Result.Ext1 := NumAt(cfg.Arrays['extent'], 1);
  Result.LabelOffset := Num(cfg, 'labelOffset');
  Result.NameDirection := cfg.Integers['nameDirection'];
  Result.Inverse := cfg.Booleans['inverse'];
end;

{ The labels of one pass, in the fixture's order -- upstream's sorted one --
  as the pure layout meets them. }
function GeomsOf(APass: TJSONObject): TTyLabelGeomArray;
var
  labels: TJSONArray;
  lb: TJSONObject;
  i, n: Integer;
begin
  Result := nil;
  labels := APass.Arrays['labels'];
  SetLength(Result, labels.Count);
  n := 0;
  for i := 0 to labels.Count - 1 do
  begin
    lb := labels.Objects[i];
    if lb.Booleans['ignore'] then Continue;
    { where it was laid out, before upstream sorted them }
    Result[n].Index := lb.Integers['layoutIndex'];
    Result[n].M := MatOf(lb.Arrays['transform']);
    Result[n].X := Result[n].M[4];
    Result[n].Y := Result[n].M[5];
    Result[n].LocalRect := XYWHOf(lb.Objects['localRect']);
    Result[n].Rect := XYWHOf(lb.Objects['rect']);
    Result[n].AxisAligned := lb.Booleans['axisAligned'];
    Inc(n);
  end;
  SetLength(Result, n);
end;

function PassOf(AAxis: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  d := AAxis.Find(AKey);
  if d is TJSONObject then Result := TJSONObject(d);
end;

{ ==================== 1. the preconditions ==================== }

procedure TAdvChartAxisNamesOracleTest.TestTheMeasurerIsZrendersToTheBit;
var
  list: TJSONArray;
  m: TJSONObject;
  i, bad: Integer;
  w, h: Double;
  report: string;
begin
  list := TJSONObject(FRoot).Arrays['measure'];
  bad := 0;
  report := '';
  for i := 0 to list.Count - 1 do
  begin
    m := list.Objects[i];
    FM.MeasureLine(m.Strings['text'], 'sans-serif', m.Integers['px'], 400, w, h);
    if (w <> Num(m, 'width')) or (h <> Num(m, 'height')) then
    begin
      Inc(bad);
      report := report + LineEnding + Format('  %s @%d: %s x %s upstream, %s x %s here',
        [m.Strings['text'], m.Integers['px'], m.Strings['widthText'],
         m.Strings['heightText'], Fmt(w), Fmt(h)]);
    end;
  end;
  AssertTrue('enough strings', list.Count >= 40);
  AssertEquals(IntToStr(bad) + ' widths differ:' + report, 0, bad);
end;

procedure TAdvChartAxisNamesOracleTest.TestAQuarterTurnIsV8sToTheBit;
var r, v: Double;
begin
  { A Y AXIS IS TURNED A QUARTER, and every number of its name goes through
    that turn: the cosine that is not quite nought is in its anchor, and the
    three-quarter turn an end name takes back is in its matrix. The exact
    comparisons below mean nothing unless these are V8's bits. }
  AssertTrue('cos(pi/2)', Same(TyJsCos(Pi / 2), FromHex('3c91a62633145c07')));
  AssertTrue('sin(pi/2)', Same(TyJsSin(Pi / 2), 1.0));
  r := TyRemRadian(0 - Pi / 2);
  AssertTrue('remRadian(-pi/2) = ' + Fmt(r), Same(r, FromHex('4012d97c7f3321d2')));
  AssertTrue('cos(3pi/2)', Same(TyJsCos(r), FromHex('bcaa79394c9e8a0a')));
  AssertTrue('sin(3pi/2)', Same(TyJsSin(r), -1.0));
  { JavaScript's % is the exact remainder, whatever the size of the turn --
    V8's answers, from node }
  v := 7;
  AssertTrue('remRadian of seven turns and a bit',
    Same(TyRemRadian(v * 2 * Pi + 0.25), FromHex('3fd0000000000000')));
  AssertTrue('remRadian(-7)', Same(TyRemRadian(-v), FromHex('401643f6a8885a30')));
  AssertTrue('remRadian(-0.25)', Same(TyRemRadian(-0.25), FromHex('401821fb54442d18')));
  AssertTrue('remRadian(20)', Same(TyRemRadian(20), FromHex('3ff268380ccde2e0')));
  v := 450;
  AssertTrue('remRadian of 450 degrees',
    Same(TyRemRadian(v * Pi / 180), FromHex('3ff921fb54442d18')));
end;

{ ==================== 2. the layout alone ==================== }

procedure TAdvChartAxisNamesOracleTest.TestEveryNameIsUpstreamsToTheBit;
const
  cPasses: array[0..1] of string = ('estimate', 'determine');
var
  cases, axes, tr: TJSONArray;
  cs, ax, other, pass, opass, nm: TJSONObject;
  c, a, o, p, k, bad, compared, moved, occupied: Integer;
  spec: TTyAxisLayoutSpec;
  own: TTyLabelGeomArray;
  perp: array of TTyLabelGeomArray;
  perpRot, sx, sy: Double;
  got: TTyAxisNamePlacement;
  want: TTyMat2D;
  report, why: string;

  procedure Miss(const AWhat: string);
  begin
    if why = '' then why := AWhat;
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  moved := 0;
  occupied := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if IsDeferred(cs) then Continue;
    axes := cs.Arrays['axes'];
    for a := 0 to axes.Count - 1 do
    begin
      ax := axes.Objects[a];
      for p := 0 to 1 do
      begin
        pass := PassOf(ax, cPasses[p]);
        if pass = nil then Continue;
        if not (pass.Find('name') is TJSONObject) then Continue;
        nm := pass.Objects['name'];
        SpecOf(ax, spec);
        own := GeomsOf(pass);
        { every axis across this one, in the fixture's order, on the same pass }
        perp := nil;
        perpRot := 0;
        for o := 0 to axes.Count - 1 do
        begin
          other := axes.Objects[o];
          if other.Strings['dim'] = ax.Strings['dim'] then Continue;
          opass := PassOf(other, cPasses[p]);
          if opass = nil then Continue;
          SetLength(perp, Length(perp) + 1);
          perp[High(perp)] := GeomsOf(opass);
          perpRot := Num(opass.Objects['cfg'], 'rotation');
        end;
        got := TyLayoutAxisName(spec, FrameOf(pass), pass.Integers['level'],
          own, perp, perpRot, FM, 96);
        Inc(compared);
        why := '';
        if not got.Shown then Miss('not shown');
        if got.Text <> nm.Strings['text'] then Miss('text ' + got.Text);
        if got.Level <> pass.Integers['level'] then Miss('level');
        if got.AnchorH <> AlignOf(nm.Strings['align']) then Miss('align');
        if got.AnchorV <> VAlignOf(nm.Strings['verticalAlign']) then Miss('verticalAlign');
        if not Same(got.LocalRotationRad, Num(nm, 'localRotation')) then
          Miss('local rotation ' + Fmt(got.LocalRotationRad));
        if not SameRect(got.LocalRect, XYWHOf(nm.Objects['localRect'])) then
          Miss('localRect ' + RectStr(got.LocalRect));
        if not (Same(got.AnchorX, NumAt(nm.Arrays['anchor'], 0))
          and Same(got.AnchorY, NumAt(nm.Arrays['anchor'], 1))) then
          Miss('anchor ' + Fmt(got.AnchorX) + ', ' + Fmt(got.AnchorY));
        want := MatOf(nm.Arrays['transform']);
        for k := 0 to 3 do
          if not Same(got.M[k], want[k]) then Miss('transform ' + IntToStr(k));
        if not SameRect(got.PreRect, XYWHOf(nm.Objects['preRect'])) then
          Miss('pre-move rect ' + RectStr(got.PreRect));
        if got.AxisAligned <> nm.Booleans['axisAligned'] then Miss('axisAligned');
        { the obstacle a middle name meets }
        if pass.Find('stOccupiedRect') is TJSONObject then
        begin
          Inc(occupied);
          if not (got.HasOccupied and SameRect(got.Occupied,
            XYWHOf(pass.Objects['stOccupiedRect']))) then
            Miss('stOccupiedRect ' + RectStr(got.Occupied));
        end
        else if got.HasOccupied then
          Miss('an obstacle upstream did not make');
        { every move, summed in upstream's order }
        tr := nm.Arrays['translations'];
        if tr.Count > 0 then Inc(moved);
        if got.Moves <> tr.Count then
          Miss(Format('%d moves, upstream %d', [got.Moves, tr.Count]));
        sx := 0;
        sy := 0;
        for k := 0 to tr.Count - 1 do
        begin
          sx := sx + Num(tr.Objects[k], 'x');
          sy := sy + Num(tr.Objects[k], 'y');
        end;
        if not (Same(got.MovedX, sx) and Same(got.MovedY, sy)) then
          Miss('moved ' + Fmt(got.MovedX) + ', ' + Fmt(got.MovedY));
        want := MatOf(nm.Arrays['finalTransform']);
        for k := 0 to 5 do
          if not Same(got.M[k], want[k]) then Miss('final transform ' + IntToStr(k));
        if not (Same(got.X, NumAt(nm.Arrays['finalAnchor'], 0))
          and Same(got.Y, NumAt(nm.Arrays['finalAnchor'], 1))) then
          Miss('final anchor ' + Fmt(got.X) + ', ' + Fmt(got.Y));
        if not SameRect(got.Rect, XYWHOf(nm.Objects['rect'])) then
          Miss('rect ' + RectStr(got.Rect));
        if not Same(got.RotationRad, Num(nm, 'rotation')) then
          Miss('rotation ' + Fmt(got.RotationRad));
        if why <> '' then
        begin
          Inc(bad);
          if bad <= 30 then
            report := report + LineEnding + Format('  %s / %s%d %s: %s',
              [cs.Strings['name'], ax.Strings['dim'], ax.Integers['index'],
               cPasses[p], why]);
        end;
      end;
    end;
  end;
  AssertTrue(Format('enough names were compared (%d)', [compared]), compared >= 100);
  AssertTrue(Format('enough of them were moved (%d)', [moved]), moved >= 20);
  AssertTrue(Format('enough met a band of labels (%d)', [occupied]), occupied >= 20);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared)
    + ' names differ:' + report, 0, bad);
end;

{ ==================== 3. the pipeline ==================== }

function AxisFor(ABuild: TTyChartBuild; AGrid: Integer; const ADim: string;
  AIndex: Integer): TTyAxis;
var
  gb: TTyGridBuild;
  i: Integer;
begin
  Result := nil;
  gb := ABuild.Grid(AGrid);
  if ADim = 'x' then
  begin
    for i := 0 to gb.XAxisCount - 1 do
      if gb.XAxis(i).ComponentIndex = AIndex then Exit(gb.XAxis(i));
  end
  else
    for i := 0 to gb.YAxisCount - 1 do
      if gb.YAxis(i).ComponentIndex = AIndex then Exit(gb.YAxis(i));
end;

procedure TAdvChartAxisNamesOracleTest.TestEveryDrawnNameAsUpstreamPlacesIt;
var
  cases, axes: TJSONArray;
  cs, ax, pass, nm: TJSONObject;
  c, a, g, bad, compared, absent: Integer;
  axis: TTyAxis;
  spec: PTyAxisLayoutSpec;
  got: TTyAxisNamePlacement;
  want, xywh, rect: TTyXYWH;
  tol: Double;
  report, why: string;
  exactPlot, moved: Boolean;
  exactNames: Integer;

  procedure Miss(const AWhat: string);
  begin
    if why = '' then why := AWhat;
  end;

  function Near(A, B: Double): Boolean;
  begin
    Result := Abs(A - B) <= tol;
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  absent := 0;
  exactNames := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if IsDeferred(cs) then Continue;
    try
      RunCase(cs);
    except
      on E: Exception do
      begin
        Inc(bad);
        report := report + LineEnding + '  ' + cs.Strings['name'] + ': '
          + E.ClassName + ': ' + E.Message;
        Continue;
      end;
    end;
    g := cs.Integers['grid'];
    tol := Num(cs, 'tol');
    { EXACT where the plot is upstream's to the bit -- the name stands off
      the axis' own [0, w], not its edges -- and within the case's tolerance
      where rotated labels moved the shrink }
    xywh := FBuild.Grid(g).PlotXYWH;
    rect := XYWHOf(cs.Objects['rect']);
    exactPlot := (xywh.X = rect.X) and (xywh.Y = rect.Y) and (xywh.W = rect.W)
      and (xywh.H = rect.H);
    axes := cs.Arrays['axes'];
    for a := 0 to axes.Count - 1 do
    begin
      ax := axes.Objects[a];
      axis := AxisFor(FBuild, g, ax.Strings['dim'], ax.Integers['index']);
      if axis = nil then
      begin
        Inc(bad);
        report := report + LineEnding + Format('  %s / %s%d: no such axis',
          [cs.Strings['name'], ax.Strings['dim'], ax.Integers['index']]);
        Continue;
      end;
      spec := FBuild.Grid(g).SpecFor(axis);
      AssertNotNull('a spec', spec);
      got := spec^.NamePlacement;
      pass := PassOf(ax, 'determine');
      why := '';
      if (pass = nil) or not (pass.Find('name') is TJSONObject) then
      begin
        { NO NAME DRAWN upstream -- none here either }
        Inc(absent);
        if got.Shown then Miss('a name upstream does not draw: ' + got.Text);
      end
      else
      begin
        nm := pass.Objects['name'];
        Inc(compared);
        if not got.Shown then Miss('not shown')
        else
        begin
          if got.Text <> nm.Strings['text'] then Miss('text ' + got.Text);
          if got.Level <> pass.Integers['level'] then
            Miss(Format('level %d, upstream %d', [got.Level, pass.Integers['level']]));
          if got.AnchorH <> AlignOf(nm.Strings['align']) then Miss('align');
          if got.AnchorV <> VAlignOf(nm.Strings['verticalAlign']) then Miss('verticalAlign');
          if Abs(got.RotationRad - Num(nm, 'rotation')) > 1e-12 then
            Miss('rotation ' + Fmt(got.RotationRad));
          { BEFORE ANY MOVE, to the bit; after one too when there was none. A
            move is measured off the labels' boxes through upstream's
            decomposed label matrix, whose 1e-16 shear is not ported yet. }
          if exactPlot then Inc(exactNames);
          moved := (nm.Find('translations') is TJSONArray)
            and (nm.Arrays['translations'].Count > 0);
          if exactPlot and not ((got.AnchorX = NumAt(nm.Arrays['anchor'], 0))
            and (got.AnchorY = NumAt(nm.Arrays['anchor'], 1))) then
            Miss(Format('anchored at %s, %s; upstream %s, %s exactly',
              [Fmt(got.AnchorX), Fmt(got.AnchorY), nm.Arrays['anchorText'].Strings[0],
               nm.Arrays['anchorText'].Strings[1]]))
          else if exactPlot and (not moved) and not ((got.X = NumAt(nm.Arrays['finalAnchor'], 0))
            and (got.Y = NumAt(nm.Arrays['finalAnchor'], 1))) then
            Miss(Format('at %s, %s; upstream %s, %s exactly', [Fmt(got.X), Fmt(got.Y),
              nm.Arrays['finalAnchorText'].Strings[0],
              nm.Arrays['finalAnchorText'].Strings[1]]))
          else if not (Near(got.X, NumAt(nm.Arrays['finalAnchor'], 0))
            and Near(got.Y, NumAt(nm.Arrays['finalAnchor'], 1))) then
            Miss(Format('at %s, %s; upstream %s, %s', [Fmt(got.X), Fmt(got.Y),
              nm.Arrays['finalAnchorText'].Strings[0],
              nm.Arrays['finalAnchorText'].Strings[1]]));
          want := XYWHOf(nm.Objects['rect']);
          if not (Near(got.Rect.X, want.X) and Near(got.Rect.Y, want.Y)
            and Near(got.Rect.W, want.W) and Near(got.Rect.H, want.H)) then
            Miss('rect ' + RectStr(got.Rect) + ', upstream ' + RectStr(want));
        end;
      end;
      if why <> '' then
      begin
        Inc(bad);
        if bad <= 30 then
          report := report + LineEnding + Format('  %s / %s%d: %s',
            [cs.Strings['name'], ax.Strings['dim'], ax.Integers['index'], why]);
      end;
    end;
  end;
  AssertTrue(Format('enough names were compared (%d)', [compared]), compared >= 80);
  AssertTrue(Format('and enough axes drew none (%d)', [absent]), absent >= 4);
  AssertTrue(Format('names on a plot upstream''s to the bit (%d)', [exactNames]),
    exactNames >= 60);
  AssertEquals(IntToStr(bad) + ' names differ:' + report, 0, bad);
end;

procedure TAdvChartAxisNamesOracleTest.TestEveryGridAsUpstreamSolvesIt;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c, g, bad, compared: Integer;
  want: TTyXYWH;
  plot: TTyRectF;
  tol: Double;
  report: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  bad := 0;
  compared := 0;
  report := '';
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if IsDeferred(cs) then Continue;
    try
      RunCase(cs);
    except
      on E: Exception do
      begin
        Inc(bad);
        report := report + LineEnding + '  ' + cs.Strings['name'] + ': '
          + E.ClassName + ': ' + E.Message;
        Continue;
      end;
    end;
    g := cs.Integers['grid'];
    want := XYWHOf(cs.Objects['rect']);
    tol := Num(cs, 'tol');
    Inc(compared);
    plot := FBuild.Grid(g).PlotRect;
    if (Abs(plot.Left - want.X) > tol) or (Abs(plot.Top - want.Y) > tol)
      or (Abs((plot.Right - plot.Left) - want.W) > tol)
      or (Abs((plot.Bottom - plot.Top) - want.H) > tol) then
    begin
      Inc(bad);
      if bad <= 30 then
        report := report + LineEnding + Format('  %s: %s,%s,%s,%s upstream, %s,%s,%s,%s here',
          [cs.Strings['name'], cs.Objects['rectText'].Strings['x'],
           cs.Objects['rectText'].Strings['y'],
           cs.Objects['rectText'].Strings['width'],
           cs.Objects['rectText'].Strings['height'], Fmt(plot.Left),
           Fmt(plot.Top), Fmt(plot.Right - plot.Left),
           Fmt(plot.Bottom - plot.Top)]);
    end;
  end;
  AssertTrue(Format('enough was compared (%d)', [compared]), compared >= 50);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared)
    + ' grids differ:' + report, 0, bad);
end;

{ ==================== 4. what the cases do not reach ==================== }

procedure TAdvChartAxisNamesOracleTest.TestATurnedNameThatMeetsALabelIsLeftWhereItIs;
var
  spec: TTyAxisLayoutSpec;
  frame: TTyAxisNameFrame;
  own: TTyLabelGeomArray;
  level, turned: TTyAxisNamePlacement;
begin
  { AN OVERLAP WITH SOMETHING TURNED OFF THE AXES is upstream's oriented-box
    test, which the port does not have: the name stays where it was put. The
    same name level, on the same label, is moved -- so what decides is the
    turn and nothing else. }
  spec := Default(TTyAxisLayoutSpec);
  spec.Side := asBottom;
  spec.Name := 'Name';
  spec.NameFontName := 'sans-serif';
  spec.NameFontSizeLogical := 12;
  spec.NameFontWeight := 400;
  frame := Default(TTyAxisNameFrame);
  frame.PosX := 0;
  frame.PosY := 100;
  frame.Ext0 := 0;
  frame.Ext1 := 200;
  frame.NameDirection := 1;
  { a label standing across where the name begins }
  SetLength(own, 1);
  own[0].Index := 0;
  own[0].M := TyMatLocal(200, 95, 0);
  own[0].X := 200;
  own[0].Y := 95;
  own[0].LocalRect := TyXYWH(-10, 0, 20, 12);
  own[0].Rect := TyRectApplyMat(own[0].LocalRect, own[0].M);
  own[0].AxisAligned := True;
  level := TyLayoutAxisName(spec, frame, 1, own, [], Pi / 2, FM, 96);
  AssertTrue('a level name is moved off it', level.Moves > 0);
  AssertTrue('along the axis, outwards', level.MovedX > 0);
  spec.HasNameRotate := True;
  spec.NameRotateRad := 30 * Pi / 180;
  turned := TyLayoutAxisName(spec, frame, 1, own, [], Pi / 2, FM, 96);
  AssertFalse('the turned one is not axis-aligned', turned.AxisAligned);
  AssertTrue('its box does meet the label',
    (turned.Rect.X < own[0].Rect.X + own[0].Rect.W)
    and (own[0].Rect.X < turned.Rect.X + turned.Rect.W)
    and (turned.Rect.Y < own[0].Rect.Y + own[0].Rect.H)
    and (own[0].Rect.Y < turned.Rect.Y + turned.Rect.H));
  AssertEquals('and it is left where it was', 0, turned.Moves);
  AssertTrue('exactly', Same(turned.X, turned.AnchorX) and Same(turned.Y, turned.AnchorY));
end;

procedure TAdvChartAxisNamesOracleTest.TestTheNameIsMeasuredInItsOwnFont;
var
  spec: TTyAxisLayoutSpec;
  frame: TTyAxisNameFrame;
  got: TTyAxisNamePlacement;
  w12, w20, h: Double;
begin
  { THE NAME'S FONT, NOT THE LABELS'. The two are the same in the shipped
    theme and upstream's default, so nothing in the fixture tells them
    apart; a skin that sizes them differently does. }
  FM.MeasureLine('Revenue', 'sans-serif', 12, 400, w12, h);
  FM.MeasureLine('Revenue', 'sans-serif', 20, 400, w20, h);
  spec := Default(TTyAxisLayoutSpec);
  spec.Side := asBottom;
  spec.Name := 'Revenue';
  spec.FontName := 'sans-serif';
  spec.FontSizeLogical := 12;
  spec.FontWeight := 400;
  spec.NameFontName := 'sans-serif';
  spec.NameFontSizeLogical := 20;
  spec.NameFontWeight := 400;
  frame := Default(TTyAxisNameFrame);
  frame.Ext1 := 300;
  frame.NameDirection := 1;
  { level 1 at the end: three either side }
  got := TyLayoutAxisName(spec, frame, 1, nil, [], Pi / 2, FM, 96);
  AssertTrue('twenty pixels wide', Same(got.LocalRect.W, w20 + 6));
  AssertTrue('and twenty tall', Same(got.LocalRect.H, 20.0));
  { a spec that names no size of its own falls back to the labels' }
  spec.NameFontSizeLogical := 0;
  got := TyLayoutAxisName(spec, frame, 1, nil, [], Pi / 2, FM, 96);
  AssertTrue('the labels'' twelve', Same(got.LocalRect.W, w12 + 6));

  { AND THE BUILDER HANDS IT OVER: the style's name font reaches the spec }
  FStyle := TestTextStyle;
  FStyle.NameFontSizeLogical := 20;
  spec := SpecAfter('{"xAxis": {"type": "category", "data": ["A"], "name": "Revenue"},'
    + ' "yAxis": {"type": "value"}}', 'x');
  AssertEquals('the spec carries it', 20, spec.NameFontSizeLogical);
  AssertTrue('and the name drawn is measured in it',
    Same(spec.NamePlacement.LocalRect.W, w20 + 6));
end;

procedure TAdvChartAxisNamesOracleTest.TestTheNameOptionsAreReadAsUpstreamReadsThem;

  function Y(const AAxis: string): TTyAxisLayoutSpec;
  begin
    Result := SpecAfter('{"xAxis": {"type": "category", "data": ["A"]},'
      + ' "yAxis": ' + AAxis + '}', 'y');
  end;

var
  s: TTyAxisLayoutSpec;
  deg: Double;
begin
  { normalizeCssArray: two numbers are vertical and horizontal, three are
    top, the sides, bottom }
  s := Y('{"name": "V", "nameTextStyle": {"textMargin": [4, 8]}}');
  AssertTrue('textMargin', s.NameMarginKind = nmkTextMargin);
  AssertEquals('[4, 8]: top', 4, s.NameMargin[0], 0);
  AssertEquals('right', 8, s.NameMargin[1], 0);
  AssertEquals('bottom', 4, s.NameMargin[2], 0);
  AssertEquals('left', 8, s.NameMargin[3], 0);
  s := Y('{"name": "V", "nameTextStyle": {"textMargin": [1, 2, 3]}}');
  AssertEquals('[1, 2, 3]: top', 1, s.NameMargin[0], 0);
  AssertEquals('right', 2, s.NameMargin[1], 0);
  AssertEquals('bottom', 3, s.NameMargin[2], 0);
  AssertEquals('left is the right', 2, s.NameMargin[3], 0);
  s := Y('{"name": "V", "nameTextStyle": {"textMargin": [9]}}');
  AssertEquals('[9]: every side', 9, s.NameMargin[3], 0);
  { minMargin wins over textMargin, and a non-number is nought }
  s := Y('{"name": "V", "nameTextStyle": {"textMargin": 4, "minMargin": 10}}');
  AssertTrue('minMargin', s.NameMarginKind = nmkMinMargin);
  AssertEquals('ten', 10, s.NameMinMarginLogical, 0);
  s := Y('{"name": "V", "nameTextStyle": {"minMargin": "10"}}');
  AssertTrue('minMargin as a string', s.NameMarginKind = nmkMinMargin);
  AssertEquals('is nought', 0, s.NameMinMarginLogical, 0);

  { align and verticalAlign: zrender's three and three }
  s := Y('{"name": "V", "nameTextStyle": {"align": "right", "verticalAlign": "middle"}}');
  AssertTrue('align right', s.HasNameAlignH and (s.NameAlignH = tahRight));
  AssertTrue('verticalAlign middle', s.HasNameAlignV and (s.NameAlignV = tavMiddle));
  s := Y('{"name": "V", "nameTextStyle": {"align": "center", "verticalAlign": "bottom"}}');
  AssertTrue('align center', s.NameAlignH = tahCentre);
  AssertTrue('verticalAlign bottom', s.NameAlignV = tavBottom);
  s := Y('{"name": "V"}');
  AssertFalse('no align of its own', s.HasNameAlignH or s.HasNameAlignV);

  { nameRotate: degrees in, radians out, as upstream turns them }
  s := Y('{"name": "V", "nameRotate": 30}');
  deg := 30;
  AssertTrue('nameRotate', s.HasNameRotate and Same(s.NameRotateRad, deg * Pi / 180));
  s := Y('{"name": "V", "nameRotate": null}');
  AssertFalse('null is auto', s.HasNameRotate);

  { nameGap: `|| 0` -- the theme's when absent }
  s := Y('{"name": "V"}');
  AssertEquals('the theme''s gap', 15, s.NameGapLogical, 0);
  s := Y('{"name": "V", "nameGap": false}');
  AssertEquals('false is nought', 0, s.NameGapLogical, 0);
  s := Y('{"name": "V", "nameGap": 22}');
  AssertEquals('a number is itself', 22, s.NameGapLogical, 0);

  { nameLocation }
  s := Y('{"name": "V", "nameLocation": "start"}');
  AssertTrue('start', s.NameLocation = anlStart);
  s := Y('{"name": "V", "nameLocation": "center"}');
  AssertTrue('center is middle', s.NameLocation = anlMiddle);
  s := Y('{"name": "V", "nameLocation": "foo"}');
  AssertTrue('anything else is the end', s.NameLocation = anlEnd);

  { nameMoveOverlap: JavaScript's truthiness, null and 'auto' the grid's }
  s := Y('{"name": "V", "nameMoveOverlap": 0}');
  AssertTrue('0 does not move', s.NameNoMove);
  s := Y('{"name": "V", "nameMoveOverlap": 2}');
  AssertFalse('2 moves', s.NameNoMove);
  s := Y('{"name": "V", "nameMoveOverlap": ""}');
  AssertTrue('the empty string does not move', s.NameNoMove);
  s := Y('{"name": "V", "nameMoveOverlap": "yes"}');
  AssertFalse('a string moves', s.NameNoMove);
  s := Y('{"name": "V", "nameMoveOverlap": false}');
  AssertTrue('false does not move', s.NameNoMove);
  s := Y('{"name": "V", "nameMoveOverlap": null}');
  AssertFalse('null is the grid''s: moves', s.NameNoMove);
  s := SpecAfter('{"grid": {"containLabel": true}, "xAxis": {"type": "category",'
    + ' "data": ["A"]}, "yAxis": {"name": "V", "nameMoveOverlap": "auto"}}', 'y');
  AssertTrue('auto under containLabel: does not move', s.NameNoMove);
  s := SpecAfter('{"grid": {"containLabel": true}, "xAxis": {"type": "category",'
    + ' "data": ["A"]}, "yAxis": {"name": "V", "nameMoveOverlap": true}}', 'y');
  AssertFalse('unless it says so', s.NameNoMove);

  { inverse reaches the name's frame }
  s := Y('{"name": "V", "inverse": true}');
  AssertTrue('inverse', s.Inverse);
  AssertTrue('the extent runs from the far end', s.NameFrame.Ext0 > s.NameFrame.Ext1);
end;

function PlainSpec(const AName: string): TTyAxisLayoutSpec;
begin
  Result := Default(TTyAxisLayoutSpec);
  Result.Side := asBottom;
  Result.Name := AName;
  Result.NameFontName := 'sans-serif';
  Result.NameFontSizeLogical := 12;
  Result.NameFontWeight := 400;
end;

function XFrame(AY, ALen: Double): TTyAxisNameFrame;
begin
  Result := Default(TTyAxisNameFrame);
  Result.PosY := AY;
  Result.Ext1 := ALen;
  Result.NameDirection := 1;
end;

function Geom(AIndex: Integer; AX, AY, AW, AH: Double): TTyLabelGeom;
begin
  Result.Index := AIndex;
  Result.M := TyMatIdentity;
  Result.X := AX;
  Result.Y := AY;
  Result.LocalRect := TyXYWH(AX, AY, AW, AH);
  Result.Rect := Result.LocalRect;
  Result.AxisAligned := True;
end;

procedure TAdvChartAxisNamesOracleTest.TestTheTextLayoutsTurnAsUpstreamTurnsThem;
var
  spec: TTyAxisLayoutSpec;
  frame: TTyAxisNameFrame;
  got: TTyAxisNamePlacement;
  deg: Double;

  procedure Turn(ADeg: Double; ALocation: TTyAxisNameLocation);
  begin
    spec.NameLocation := ALocation;
    spec.HasNameRotate := True;
    deg := ADeg;
    spec.NameRotateRad := deg * Pi / 180;
    got := TyLayoutAxisName(spec, frame, 1, nil, [], Pi / 2, FM, 96);
  end;

begin
  { The fixture's middle names are all level or a quarter turn; the ones it
    turns by anything else take the oriented-box path and are deferred. So
    the layout rules are held here, by upstream's own reading of them. }
  spec := PlainSpec('Name');
  frame := XFrame(100, 300);
  { three degrees is not level: "around nought" is within 1e-4 }
  Turn(3, anlMiddle);
  AssertTrue('3 degrees: right', got.AnchorH = tahRight);
  AssertTrue('and middle', got.AnchorV = tavMiddle);
  { a half turn hangs the other way from level }
  Turn(180, anlMiddle);
  AssertTrue('180: centred', got.AnchorH = tahCentre);
  AssertTrue('hanging from its foot', got.AnchorV = tavBottom);
  { turned into the upper half on the outward side }
  Turn(30, anlMiddle);
  AssertTrue('30: right', got.AnchorH = tahRight);
  AssertTrue('middle', got.AnchorV = tavMiddle);
  { and a y axis' middle name made level }
  frame := Default(TTyAxisNameFrame);
  frame.PosY := 300;
  frame.Rotation := Pi / 2;
  frame.Ext1 := 300;
  frame.NameDirection := -1;
  Turn(0, anlMiddle);
  AssertTrue('a level y name: right', got.AnchorH = tahRight);
  AssertTrue('middle', got.AnchorV = tavMiddle);
  { an end name three degrees past upright is not upright }
  frame := XFrame(100, 300);
  Turn(93, anlEnd);
  AssertTrue('93 at the end: right', got.AnchorH = tahRight);
  AssertTrue('middle', got.AnchorV = tavMiddle);
  Turn(90, anlEnd);
  AssertTrue('90 at the end: centred', got.AnchorH = tahCentre);
  AssertTrue('hanging from its head', got.AnchorV = tavTop);
end;

procedure TAdvChartAxisNamesOracleTest.TestTheLevelBoundaryGoesToTheSmallerMargin;
begin
  { `<=`: a grid exactly half the canvas is level nought }
  AssertEquals('y, exactly half', 0, TyAxisNameLevel(False, 300, 100, 600, 400));
  AssertEquals('y, past half', 2, TyAxisNameLevel(False, 300.5, 100, 600, 400));
  AssertEquals('x, exactly half', 0, TyAxisNameLevel(True, 500, 200, 600, 400));
  AssertEquals('x, past half', 1, TyAxisNameLevel(True, 500, 200.5, 600, 400));
end;

procedure TAdvChartAxisNamesOracleTest.TestTheBandIsUnitedInTheOrderTheLabelsWereLaidOut;
var
  spec: TTyAxisLayoutSpec;
  own: TTyLabelGeomArray;
  got: TTyAxisNamePlacement;
  a, b, c, strip, inOrder, sorted: TTyXYWH;
begin
  { THE UNION IS NOT ASSOCIATIVE TO THE BIT: a width taken back from a right
    edge is not always the width that made it. Three label boxes that come
    out 27.049999999999997 tall united as they were laid out, and 27.05 in
    the order they are sorted in. Upstream unites them before it sorts. }
  a := TyXYWH(79.35, -7.54, 30.9, 12);
  b := TyXYWH(107.21, -16.79, 47.87, 12);
  c := TyXYWH(220.2, -1.74, 26.69, 12);
  strip := TyXYWH(0, 0, 300, 1);
  inOrder := TyRectUnion(TyRectUnion(TyRectUnion(a, b), c), strip);
  sorted := TyRectUnion(TyRectUnion(TyRectUnion(c, a), b), strip);
  AssertFalse('the premise: the order shows', Same(inOrder.H, sorted.H));
  spec := PlainSpec('N');
  spec.NameLocation := anlMiddle;
  spec.NameNoMove := True;
  SetLength(own, 3);
  { handed over sorted, carrying where each was laid out }
  own[0] := Geom(2, c.X, c.Y, c.W, c.H);
  own[1] := Geom(0, a.X, a.Y, a.W, a.H);
  own[2] := Geom(1, b.X, b.Y, b.W, b.H);
  got := TyLayoutAxisName(spec, XFrame(0, 300), 1, own, [], Pi / 2, FM, 96);
  AssertTrue('a band', got.HasOccupied);
  AssertTrue('united as laid out: ' + RectStr(got.Occupied), SameRect(got.Occupied, inOrder));
end;

procedure TAdvChartAxisNamesOracleTest.TestAMoveAgainstTheAxisMeetsTheFarLabelFirst;
var
  spec: TTyAxisLayoutSpec;
  frame: TTyAxisNameFrame;
  own: TTyLabelGeomArray;
  probe, got: TTyAxisNamePlacement;
  w: Double;
begin
  { A START NAME MOVES AGAINST ITS AXIS, and upstream then walks the labels
    from the far end in: a label it would only meet after the first push is
    already behind it by then, and it stays overlapping. Walked near to far,
    the same two labels push it twice. }
  spec := PlainSpec('Name');
  spec.NameLocation := anlStart;
  frame := XFrame(100, 200);
  frame.PosX := 100;
  { where it lands with nothing in the way: right-aligned on (100, 100),
    three to either side }
  probe := TyLayoutAxisName(spec, frame, 1, nil, [], Pi / 2, FM, 96);
  w := probe.Rect.W;
  AssertEquals('its right edge', 103.0, probe.Rect.X + probe.Rect.W, 1e-9);
  SetLength(own, 2);
  { near: across its right end; far: just beyond its left end }
  own[0] := Geom(0, 95, 94, 20, 12);
  own[1] := Geom(1, 103 - w - 12, 94, 6, 12);
  got := TyLayoutAxisName(spec, frame, 1, own, [], Pi / 2, FM, 96);
  AssertEquals('one push', 1, got.Moves);
  AssertEquals('its right edge a tenth inside the near label', 95.1,
    got.Rect.X + got.Rect.W, 1e-9);
end;

procedure TAdvChartAxisNamesOracleTest.TestTheShortestAllowedTranslationWins;
var mx, my: Double;
begin
  { Along an axis only one way is ever allowed; off it, two are, and the
    shorter wins -- here the one that lifts it out over the top. }
  AssertTrue('they meet', TyRectIntersectDir(TyXYWH(0, 0, 10, 10),
    TyXYWH(7, 8.5, 10, 10), Pi / 4, 0.05, mx, my));
  AssertEquals('by y''s way: x', 1.4, mx, 1e-9);
  AssertEquals('y', 1.4, my, 1e-9);
end;

procedure TAdvChartAxisNamesOracleTest.TestLabelsAreSortedAlongTheirAxisStably;
var
  g: TTyLabelGeomArray;
  frame: TTyAxisNameFrame;
begin
  { by the distance from the axis' origin, along the axis, ties kept }
  SetLength(g, 4);
  g[0] := Geom(0, 50, 7, 1, 1);
  g[1] := Geom(1, 10, 7, 1, 1);
  g[2] := Geom(2, 30, 7, 1, 1);
  g[3] := Geom(3, -10, 7, 1, 1);
  frame := XFrame(7, 100);
  TySortLabelGeoms(g, frame);
  AssertEquals('nearest', 1, g[0].Index);
  AssertEquals('the tie, as it came', 3, g[1].Index);
  AssertEquals('then', 2, g[2].Index);
  AssertEquals('farthest', 0, g[3].Index);
  { a y axis, from its origin at the bottom }
  SetLength(g, 3);
  g[0] := Geom(0, 5, 100, 1, 1);
  g[1] := Geom(1, 5, 280, 1, 1);
  g[2] := Geom(2, 5, 200, 1, 1);
  frame := Default(TTyAxisNameFrame);
  frame.PosY := 300;
  frame.Rotation := Pi / 2;
  TySortLabelGeoms(g, frame);
  AssertEquals('y: nearest the bottom', 1, g[0].Index);
  AssertEquals('y: then', 2, g[1].Index);
  AssertEquals('y: farthest', 0, g[2].Index);
end;

procedure TAdvChartAxisNamesOracleTest.TestAMiddleNameOnTheZeroLineStaysWithTheLabels;
var
  s: TTyAxisLayoutSpec;
  plot: TTyRectF;
begin
  { THE LINE GOES TO ZERO, THE LABELS STAY AT THE EDGE, and a middle name
    goes with the labels -- 15 past the edge, not past the line. With the
    labels hidden there is nothing to move it there, so this is the frame's
    label offset alone. }
  s := SpecAfter('{"xAxis": {"type": "category", "data": ["A"], "name": "X",'
    + ' "nameLocation": "middle", "axisLabel": {"show": false}},'
    + ' "yAxis": {"type": "value", "min": -100, "max": 100}}', 'x');
  plot := FBuild.Grid(0).PlotRect;
  AssertTrue('the line is inside the plot',
    Abs(s.NameFrame.PosY - (plot.Top + plot.Bottom) / 2) < 1e-6);
  AssertEquals('the name hangs 15 below the bottom edge', plot.Bottom + 15,
    s.NamePlacement.AnchorY, 1e-9);
  { and on top, above the top edge }
  s := SpecAfter('{"xAxis": {"type": "category", "data": ["A"], "name": "X",'
    + ' "position": "top", "nameLocation": "middle", "axisLabel": {"show": false}},'
    + ' "yAxis": {"type": "value", "min": -100, "max": 100}}', 'x');
  plot := FBuild.Grid(0).PlotRect;
  AssertEquals('on top, 15 above the top edge', plot.Top - 15,
    s.NamePlacement.AnchorY, 1e-9);
end;

procedure TAdvChartAxisNamesOracleTest.TestTheEstimateFindsTheLineOnTheOtherZero;
var s: TTyAxisLayoutSpec;
begin
  { A y axis on the x axis' zero: its end name stands over the middle of the
    plot, well inside the canvas, and costs the grid nothing -- in the
    estimate too, where a frame on the plot's left edge would have it half
    off a grid written at left 0. }
  s := SpecAfter('{"grid": {"left": 0}, "xAxis": {"type": "value", "min": -100,'
    + ' "max": 100, "axisLabel": {"show": false}}, "yAxis": {"type": "value",'
    + ' "min": 0, "max": 10, "name": "A long y axis name",'
    + ' "axisLabel": {"show": false}}}', 'y');
  AssertTrue('the name is on the middle of the plot', s.NamePlacement.X > 100);
  AssertEquals('and the grid keeps its left edge', 0.0,
    FBuild.Grid(0).PlotRect.Left, 0);
end;

procedure TAdvChartAxisNamesOracleTest.TestTheMarginLevelIsOfTheCanvas;
var w, h: Double;
begin
  { A GRID NO MORE THAN HALF THE CANVAS TALL pads its x name by level
    nought -- one pixel either end -- in the estimate as well: the name at
    the end of a grid against the canvas' right edge overflows by its gap,
    its width and that one pixel, and the grid gives up exactly that. }
  FM.MeasureLine('Day', 'sans-serif', 12, 400, w, h);
  SpecAfter('{"grid": {"left": "60%", "right": 0, "top": "60%", "bottom": 0},'
    + ' "xAxis": {"type": "category", "data": ["A"], "name": "Day",'
    + ' "axisLabel": {"show": false}}, "yAxis": {"type": "value",'
    + ' "axisLabel": {"show": false}}}', 'x');
  AssertEquals('the right edge', 600 - (15 + w + 1), FBuild.Grid(0).PlotRect.Right, 1e-9);
end;

initialization
  RegisterTest(TAdvChartAxisNamesOracleTest);
end.
