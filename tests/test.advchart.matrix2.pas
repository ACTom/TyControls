unit test.advchart.matrix2;
{$mode objfpc}{$H+}
{ THE MATRIX COORDINATE SYSTEM, part two (D12 MX2, batch 147), held to what
  ECharts 6.1 answers.

  tools/advchart-oracle/matrix2.js runs the real dist and records:

    the algebra   per matrix, dataToLayout / dataToPoint of some forty
                  coords (single values, parents, ranges in either order,
                  [x1, x2, x3], empty arrays, nulls, names that are not
                  there, fractions, a coord that is not an array) under
                  eight clamps, and pointToData of every crossing of the
                  units' edges and middles under four;
    the convert   chart.convertToPixel / convertToLayout / convertFromPixel
                  (with an opt) and containPixel through matrix, series,
                  grid and calendar finders;
    the series    a custom series' coordSys and every api.coord /
                  api.layout answer (ranges and clamps included), a graph's
                  node points and curved edge, pies and a funnel laid out in
                  cells, and the gallery's four;
    the view      turned and rich cell labels (matrix.js's records);
    the pointer   steps over cells and items: what is hit, the mouse events
                  with their params, the tooltip (a cell's text, an item's
                  rows).

  This replays each through the port: the algebra on the pure unit, the
  view through part one's checks (TAdvChartMatrixOracleTest on this
  fixture), the rest through the control. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Convert,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.Tooltip, tyControls.AdvChart.Graph,
     tyControls.AdvChart.Custom, tyControls.AdvChart.Matrix,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.matrix;
type
  TMx2Probe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Move(AX, AY: Integer);
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
  end;

  { The renderItems of matrix2.js, transcribed; each api.coord / api.layout
    answer is written down in order, as the oracle's recorder writes it. }
  TMx2Mirror = class
  public
    { per call: 'coord' x y, or 'layout' x y w h lo0 hi0 lo1 hi1 }
    Answers: TStringList;
    { per renderItem call: the coordSys' type and rect }
    Params: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Open(const AParams: TTyCustomParams);
    procedure LogLayout(const L: TTyCustomLayout);
    procedure LogCoord(const P: TTyDoubleArray);
    function MxCell(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function MxRange(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function MxGal(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  { the mouse events, one line each }
  TMx2Logger = class
  public
    Log: TStringList;
    procedure Handle(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  { the pure unit: the algebra }
  TAdvChartMatrix2AlgebraTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FOpt: TTyChartOption;
    FBad, FCompared, FLayouts, FPoints: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDataToLayoutAsUpstream;
    procedure TestPointToDataAsUpstream;
    procedure TestTheClampWords;
  end;

  { the view cases through part one's checks }
  TAdvChartMatrix2ViewTest = class(TAdvChartMatrixOracleTest)
  protected
    function FixtureFile: string; override;
    function MinCells: Integer; override;
    function MinProbes: Integer; override;
    function MinEls: Integer; override;
    function MinLabels: Integer; override;
  end;

  { the control }
  TAdvChartMatrix2ChartTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMx2Probe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FMirror: TMx2Mirror;
    FBad, FCompared, FCount: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure Draw(ACase: TJSONObject);
    procedure RenderNow;
    procedure CheckCall(ACall: TJSONObject);
    procedure CheckCustom(ACase: TJSONObject);
    procedure CheckGraphs(ACase: TJSONObject);
    procedure CheckPies(ACase: TJSONObject);
    procedure CheckFunnels(ACase: TJSONObject);
    procedure RunPointer(ACase: TJSONObject);
    function CaseOf(const AId: string): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheConversionsAsUpstream;
    procedure TestTheCustomSeriesAsUpstream;
    procedure TestTheGraphsAsUpstream;
    procedure TestThePiesAndTheFunnelInCellsAsUpstream;
    procedure TestThePointerAsUpstream;
    procedure TestConvertToLayoutPrintsJson;
    procedure TestTheApiOffAMatrixAnswersNoRange;
  end;

implementation

const
  cW = 800;
  cH = 600;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-matrix2.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
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

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function SameBits(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

{ the gallery's custom series draws with the generic cell }
procedure GalleryCustom(AOpt: TJSONObject);
var
  s: TJSONData;
  k: Integer;
begin
  s := AOpt.Find('series');
  if s is TJSONObject then
  begin
    if TJSONObject(s).Get('type', '') = 'custom' then TJSONObject(s).Strings['renderItem'] := '@mxGal';
  end
  else if s is TJSONArray then
    for k := 0 to s.Count - 1 do
      if (s.Items[k] is TJSONObject) and (TJSONObject(s.Items[k]).Get('type', '') = 'custom') then
        TJSONObject(s.Items[k]).Strings['renderItem'] := '@mxGal';
end;

{ ==================== the probe ==================== }

function TMx2Probe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TMx2Probe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TMx2Probe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TMx2Probe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TMx2Probe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

{ ==================== the mirror ==================== }

constructor TMx2Mirror.Create;
begin
  inherited Create;
  Answers := TStringList.Create;
  Params := TStringList.Create;
end;

destructor TMx2Mirror.Destroy;
begin
  Answers.Free;
  Params.Free;
  inherited Destroy;
end;

procedure TMx2Mirror.Clear;
begin
  Answers.Clear;
  Params.Clear;
end;

function HexOf(A: Double): string;
begin
  Result := LowerCase(IntToHex(Int64(Bits(A)), 16));
  if IsNan(A) then Result := '7ff8000000000000';
end;

procedure TMx2Mirror.Open(const AParams: TTyCustomParams);
begin
  Params.Add(AParams.CoordSys.Type_ + ' ' + HexOf(AParams.CoordSys.X) + ' '
    + HexOf(AParams.CoordSys.Y) + ' ' + HexOf(AParams.CoordSys.Width) + ' '
    + HexOf(AParams.CoordSys.Height));
end;

procedure TMx2Mirror.LogLayout(const L: TTyCustomLayout);
begin
  Answers.Add('layout ' + HexOf(L.Rect.X) + ' ' + HexOf(L.Rect.Y) + ' ' + HexOf(L.Rect.Width)
    + ' ' + HexOf(L.Rect.Height) + ' ' + HexOf(L.LocatorRange[0][0]) + ' '
    + HexOf(L.LocatorRange[0][1]) + ' ' + HexOf(L.LocatorRange[1][0]) + ' '
    + HexOf(L.LocatorRange[1][1]));
end;

procedure TMx2Mirror.LogCoord(const P: TTyDoubleArray);
begin
  if Length(P) < 2 then Answers.Add('coord none')
  else Answers.Add('coord ' + HexOf(P[0]) + ' ' + HexOf(P[1]));
end;

{ RENDER.mxCell }
function TMx2Mirror.MxCell(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y: Double;
  lay: TTyCustomLayout;
  p: TTyDoubleArray;
begin
  Open(AParams);
  x := AApi.Value(0);
  y := AApi.Value(1);
  lay := AApi.Layout([x, y]);
  LogLayout(lay);
  p := AApi.Coord([x, y]);
  LogCoord(p);
  if IsNan(lay.Rect.X) or IsNan(lay.Rect.Y) then Exit(nil);
  Result := TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
    TJSONObject.Create(['type', 'rect', 'shape', TJSONObject.Create(['x', lay.Rect.X + 1,
      'y', lay.Rect.Y + 1, 'width', lay.Rect.Width - 2, 'height', lay.Rect.Height - 2]),
      'style', TJSONObject.Create(['fill', '#88aadd'])]),
    TJSONObject.Create(['type', 'circle', 'shape', TJSONObject.Create(['cx', p[0], 'cy', p[1],
      'r', 3]), 'style', TJSONObject.Create(['fill', '#ffffff'])])])]);
end;

{ RENDER.mxRange: every call in JavaScript's order }
function TMx2Mirror.MxRange(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y: Double;
  a, b, d, e: TTyCustomLayout;
  c: TTyDoubleArray;
begin
  Open(AParams);
  x := AApi.Value(0);
  y := AApi.Value(1);
  a := AApi.LayoutRange([x, x + 1], [y], 1);
  LogLayout(a);
  b := AApi.LayoutRange([nil], [y], 2);
  LogLayout(b);
  c := AApi.CoordRange([x, -1], [y]);
  LogCoord(c);
  d := AApi.LayoutRange([x], [y, 'zz']);
  LogLayout(d);
  e := AApi.LayoutRange([x, x, x + 2], [-1, y], 3);
  LogLayout(e);
  if IsNan(a.Rect.X) then Exit(nil);
  Result := TJSONObject.Create(['type', 'rect', 'shape', TJSONObject.Create(['x', a.Rect.X,
    'y', b.Rect.Y, 'width', a.Rect.Width, 'height', b.Rect.Height]),
    'style', TJSONObject.Create(['fill', '#ddaa88', 'opacity', 0.5])]);
end;

{ RENDER.mxGal }
function TMx2Mirror.MxGal(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var lay: TTyCustomLayout;
begin
  Open(AParams);
  lay := AApi.Layout([AApi.Value(0), AApi.Value(1)]);
  LogLayout(lay);
  if IsNan(lay.Rect.X) or IsNan(lay.Rect.Y) then Exit(nil);
  Result := TJSONObject.Create(['type', 'rect', 'shape', TJSONObject.Create(['x', lay.Rect.X,
    'y', lay.Rect.Y, 'width', lay.Rect.Width, 'height', lay.Rect.Height]),
    'style', TJSONObject.Create(['fill', '#cccccc'])]);
end;

procedure TMx2Logger.Handle(Sender: TObject; const AEvent: TTyChartEvent);
var
  p: TTyChartCallbackParams;
  s: string;
begin
  s := AEvent.EventType;
  if AEvent.HasParams then
  begin
    p := AEvent.Params;
    s := s + ' ' + p.ComponentType;
    if p.ComponentType = 'matrix' then
    begin
      s := s + Format(' %d %s name=%s value=%s', [p.ComponentIndex, p.TargetType, p.Name, p.ValueText]);
      if Length(p.Coord) = 2 then s := s + Format(' [%s,%s]', [Fmt(p.Coord[0]), Fmt(p.Coord[1])]);
    end
    else
      s := s + Format(' %d %d name=%s', [p.SeriesIndex, p.DataIndex, p.Name]);
  end;
  Log.Add(s);
end;

{ ==================== the algebra ==================== }

procedure TAdvChartMatrix2AlgebraTest.SetUp;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  FOpt := TTyChartOption.Create;
  FBad := 0;
  FCompared := 0;
  FLayouts := 0;
  FPoints := 0;
  FReport := '';
end;

procedure TAdvChartMatrix2AlgebraTest.TearDown;
begin
  FreeAndNil(FOpt);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartMatrix2AlgebraTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMatrix2AlgebraTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if not SameBits(AGot, H(AWant)) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(H(AWant))]));
end;

procedure TAdvChartMatrix2AlgebraTest.TestDataToLayoutAsUpstream;
var
  cases, ms, lays: TJSONArray;
  cs, mj, lj, rc: TJSONObject;
  c, k, j: Integer;
  m: TTyMatrix;
  r: TTyXYWH;
  loc: TTyMatrixLocRange;
  w: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Get('group', '') <> 'algebra' then Continue;
    FOpt.SetOptionText('{}');
    FOpt.SetOptionText(cs.Objects['option'].AsJSON);
    ms := cs.Arrays['matrices'];
    for k := 0 to ms.Count - 1 do
    begin
      mj := ms.Objects[k];
      FName := Format('%s matrix %d', [cs.Strings['id'], k]);
      m := TTyMatrix.Create(FOpt, k);
      try
        m.Resize(TyRectF(0, 0, cW, cH), 96);
        rc := mj.Objects['rect'];
        SameH('rect x', m.Rect.X, rc.Find('x'));
        SameH('rect width', m.Rect.W, rc.Find('width'));
        lays := mj.Arrays['layouts'];
        for j := 0 to lays.Count - 1 do
        begin
          lj := lays.Objects[j];
          Inc(FLayouts);
          w := lj.Find('input').AsJSON + ' clamp ' + lj.Find('clamp').AsJSON;
          TyMatrixLayoutJson(m, lj.Find('input'), TyMatrixClampOf(lj.Find('clamp')), r, loc);
          rc := lj.Objects['rect'];
          SameH(w + ' x', r.X, rc.Find('x'));
          SameH(w + ' y', r.Y, rc.Find('y'));
          SameH(w + ' width', r.W, rc.Find('width'));
          SameH(w + ' height', r.H, rc.Find('height'));
          SameH(w + ' loc x0', loc[0][0], lj.Arrays['loc'].Arrays[0].Items[0]);
          SameH(w + ' loc x1', loc[0][1], lj.Arrays['loc'].Arrays[0].Items[1]);
          SameH(w + ' loc y0', loc[1][0], lj.Arrays['loc'].Arrays[1].Items[0]);
          SameH(w + ' loc y1', loc[1][1], lj.Arrays['loc'].Arrays[1].Items[1]);
          SameH(w + ' point x', r.X + r.W / 2, lj.Arrays['point'].Items[0]);
          SameH(w + ' point y', r.Y + r.H / 2, lj.Arrays['point'].Items[1]);
        end;
      finally
        m.Free;
      end;
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the layouts were compared (%d)', [FLayouts]), FLayouts >= 2300);
end;

procedure TAdvChartMatrix2AlgebraTest.TestPointToDataAsUpstream;
var
  cases, ms, pts: TJSONArray;
  cs, pj: TJSONObject;
  c, k, j: Integer;
  m: TTyMatrix;
  x, y: Double;
  w: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Get('group', '') <> 'algebra' then Continue;
    FOpt.SetOptionText('{}');
    FOpt.SetOptionText(cs.Objects['option'].AsJSON);
    ms := cs.Arrays['matrices'];
    for k := 0 to ms.Count - 1 do
    begin
      FName := Format('%s matrix %d', [cs.Strings['id'], k]);
      m := TTyMatrix.Create(FOpt, k);
      try
        m.Resize(TyRectF(0, 0, cW, cH), 96);
        pts := ms.Objects[k].Arrays['points'];
        for j := 0 to pts.Count - 1 do
        begin
          pj := pts.Objects[j];
          Inc(FPoints);
          m.PointToDataClamp(TyPointF(H(pj.Arrays['p'].Items[0]), H(pj.Arrays['p'].Items[1])),
            TyMatrixClampOf(pj.Find('clamp')), x, y);
          w := Format('(%s, %s) clamp %s', [Fmt(H(pj.Arrays['p'].Items[0])),
            Fmt(H(pj.Arrays['p'].Items[1])), pj.Find('clamp').AsJSON]);
          SameH(w + ' x', x, pj.Arrays['out'].Items[0]);
          SameH(w + ' y', y, pj.Arrays['out'].Items[1]);
        end;
      finally
        m.Free;
      end;
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the points were compared (%d)', [FPoints]), FPoints >= 2000);
end;

{ MatrixClampOption: falsy none, 2 body, 3 corner, any other truthy all }
procedure TAdvChartMatrix2AlgebraTest.TestTheClampWords;

  function C(const AJson: string): TTyMatrixClamp;
  var d: TJSONData;
  begin
    d := GetJSON(AJson);
    try
      Result := TyMatrixClampOf(d);
    finally
      d.Free;
    end;
  end;

begin
  AssertTrue('null', C('null') = mclNone);
  AssertTrue('0', C('0') = mclNone);
  AssertTrue('false', C('false') = mclNone);
  AssertTrue('empty text', C('""') = mclNone);
  AssertTrue('1', C('1') = mclAll);
  AssertTrue('true', C('true') = mclAll);
  AssertTrue('2', C('2') = mclBody);
  AssertTrue('3', C('3') = mclCorner);
  AssertTrue('the word body is truthy: all', C('"body"') = mclAll);
  AssertTrue('4', C('4') = mclAll);
  AssertTrue('an object', C('{}') = mclAll);
  AssertTrue('nil', TyMatrixClampOf(nil) = mclNone);
end;

{ ==================== the view ==================== }

function TAdvChartMatrix2ViewTest.FixtureFile: string;
begin
  Result := FixturePath;
end;

function TAdvChartMatrix2ViewTest.MinCells: Integer;
begin
  Result := 10;
end;

function TAdvChartMatrix2ViewTest.MinProbes: Integer;
begin
  Result := 0;
end;

function TAdvChartMatrix2ViewTest.MinEls: Integer;
begin
  Result := 30;
end;

function TAdvChartMatrix2ViewTest.MinLabels: Integer;
begin
  Result := 10;
end;

{ ==================== the control ==================== }

procedure TAdvChartMatrix2ChartTest.SetUp;
var m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TMx2Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  FMirror := TMx2Mirror.Create;
  TyChartRegisterRenderItem('mxCell', @FMirror.MxCell);
  TyChartRegisterRenderItem('mxRange', @FMirror.MxRange);
  TyChartRegisterRenderItem('mxGal', @FMirror.MxGal);
  FBad := 0;
  FCompared := 0;
  FCount := 0;
  FReport := '';
end;

procedure TAdvChartMatrix2ChartTest.TearDown;
begin
  TyChartUnregisterRenderItem('mxCell');
  TyChartUnregisterRenderItem('mxRange');
  TyChartUnregisterRenderItem('mxGal');
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FRoot);
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  FMirror.Free;
  inherited TearDown;
end;

procedure TAdvChartMatrix2ChartTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMatrix2ChartTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if not SameBits(AGot, H(AWant)) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(H(AWant))]));
end;

function TAdvChartMatrix2ChartTest.CaseOf(const AId: string): TJSONObject;
var
  cases: TJSONArray;
  c: Integer;
begin
  Result := nil;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    if cases.Objects[c].Strings['id'] = AId then Exit(cases.Objects[c]);
end;

procedure TAdvChartMatrix2ChartTest.RenderNow;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartMatrix2ChartTest.Draw(ACase: TJSONObject);
var
  opt: TJSONObject;
  d: TJSONData;
begin
  d := ACase.Find('gallery');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    opt := TJSONObject(LoadJson(GalleryPath(d.AsString)));
    GalleryCustom(opt);
  end
  else
    opt := TJSONObject(ACase.Objects['option'].Clone);
  try
    opt.Booleans['animation'] := False;
    FChart.SetBounds(0, 0, cW, cH);
    FChart.TooltipNow := 0;
    FMirror.Clear;
    FChart.Option := '{}';
    FChart.Option := opt.AsJSON;
    RenderNow;
  finally
    opt.Free;
  end;
end;

{ ---- the conversions ---- }

procedure TAdvChartMatrix2ChartTest.CheckCall(ACall: TJSONObject);
var
  fn, w: string;
  ret, rc: TJSONData;
  cv: TTyConvertResult;
  lay: TTyConvertLayout;
  b: Boolean;
  k: Integer;

  procedure SameRect(const AWhat: string; const R: TTyXYWH; AObj: TJSONObject);
  begin
    SameH(AWhat + ' x', R.X, AObj.Find('x'));
    SameH(AWhat + ' y', R.Y, AObj.Find('y'));
    SameH(AWhat + ' width', R.W, AObj.Find('width'));
    SameH(AWhat + ' height', R.H, AObj.Find('height'));
  end;

begin
  fn := ACall.Strings['fn'];
  w := Format('%s %s %s %s', [fn, ACall.Find('finder').AsJSON, ACall.Find('value').AsJSON,
    ACall.Find('opt').AsJSON]);
  ret := ACall.Find('ret');
  Inc(FCount);
  if fn = 'contain' then
  begin
    b := FChart.ContainPixelData(ACall.Find('finder'), ACall.Find('value'));
    Inc(FCompared);
    if b <> ret.AsBoolean then Miss(Format('%s: %s here', [w, BoolToStr(b, True)]));
    Exit;
  end;
  if fn = 'toLayout' then
  begin
    lay := FChart.ConvertToLayoutData(ACall.Find('finder'), ACall.Find('value'), ACall.Find('opt'));
    Inc(FCompared);
    if IsNull(ret) then
    begin
      if lay.Valid then Miss(w + ': an answer here, none upstream');
      Exit;
    end;
    if not lay.Valid then
    begin
      Miss(w + ': no answer here');
      Exit;
    end;
    SameRect(w + ' rect', lay.Rect, TJSONObject(ret).Objects['rect']);
    rc := TJSONObject(ret).Find('contentRect');
    Inc(FCompared);
    if (rc <> nil) <> lay.HasContentRect then Miss(w + ': the content rect differs')
    else if rc <> nil then SameRect(w + ' contentRect', lay.ContentRect, TJSONObject(rc));
    rc := TJSONObject(ret).Find('loc');
    Inc(FCompared);
    if (rc <> nil) <> lay.HasLocatorRange then Miss(w + ': the locator range differs')
    else if rc <> nil then
      for k := 0 to 3 do
        SameH(Format('%s loc %d', [w, k]), lay.LocatorRange[k div 2][k mod 2],
          TJSONArray(rc).Arrays[k div 2].Items[k mod 2]);
    Exit;
  end;
  if fn = 'toPixel' then
    cv := FChart.ConvertToPixelData(ACall.Find('finder'), ACall.Find('value'), ACall.Find('opt'))
  else
    cv := FChart.ConvertFromPixelData(ACall.Find('finder'), ACall.Find('value'), ACall.Find('opt'));
  Inc(FCompared);
  if IsNull(ret) then
  begin
    if cv.Kind <> cvkNone then Miss(w + ': an answer here, none upstream');
    Exit;
  end;
  if (cv.Kind <> cvkArray) or (Length(cv.Values) <> ret.Count) then
  begin
    Miss(Format('%s: kind %d, %d values here', [w, Ord(cv.Kind), Length(cv.Values)]));
    Exit;
  end;
  for k := 0 to ret.Count - 1 do
    SameH(Format('%s [%d]', [w, k]), cv.Values[k], TJSONArray(ret).Items[k]);
end;

procedure TAdvChartMatrix2ChartTest.TestTheConversionsAsUpstream;
var
  cs: TJSONObject;
  calls: TJSONArray;
  k: Integer;
begin
  cs := CaseOf('convert');
  AssertNotNull('the convert case', cs);
  FName := 'convert';
  Draw(cs);
  calls := cs.Arrays['calls'];
  for k := 0 to calls.Count - 1 do CheckCall(calls.Objects[k]);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the calls were made (%d)', [FCount]), FCount >= 40);
end;

{ ---- the series ---- }

procedure TAdvChartMatrix2ChartTest.CheckCustom(ACase: TJSONObject);
var
  cus, calls, api: TJSONArray;
  sj, cl, a, ret, cs: TJSONObject;
  k, j, q, at, si: Integer;
  want, w: string;
  view: TTyCustomView;
  loc: TJSONArray;

  function RectWant(R: TJSONObject; L: TJSONArray): string;
  begin
    Result := 'layout ' + R.Strings['x'] + ' ' + R.Strings['y'] + ' ' + R.Strings['width']
      + ' ' + R.Strings['height'] + ' ' + L.Arrays[0].Strings[0] + ' ' + L.Arrays[0].Strings[1]
      + ' ' + L.Arrays[1].Strings[0] + ' ' + L.Arrays[1].Strings[1];
  end;

begin
  cus := ACase.Arrays['custom'];
  at := 0;
  for k := 0 to cus.Count - 1 do
  begin
    sj := cus.Objects[k];
    si := sj.Integers['seriesIndex'];
    calls := sj.Arrays['calls'];
    for j := 0 to calls.Count - 1 do
    begin
      cl := calls.Objects[j];
      w := Format('series %d call %d', [si, j]);
      cs := cl.Objects['coordSys'];
      Inc(FCompared);
      if j >= FMirror.Params.Count then
      begin
        Miss(w + ': no call here');
        Continue;
      end;
      want := cs.Strings['type'] + ' ' + cs.Strings['x'] + ' ' + cs.Strings['y'] + ' '
        + cs.Strings['width'] + ' ' + cs.Strings['height'];
      if FMirror.Params[j] <> want then
        Miss(Format('%s: coordSys "%s" here, "%s" upstream', [w, FMirror.Params[j], want]));
      api := cl.Arrays['api'];
      for q := 0 to api.Count - 1 do
      begin
        a := api.Objects[q];
        Inc(FCompared);
        Inc(FCount);
        if a.Strings['fn'] = 'coord' then
          want := 'coord ' + TJSONArray(a.Find('ret')).Strings[0] + ' '
            + TJSONArray(a.Find('ret')).Strings[1]
        else
        begin
          ret := a.Objects['ret'];
          loc := ret.Arrays['matrixXYLocatorRange'];
          want := RectWant(ret.Objects['rect'], loc);
        end;
        if at >= FMirror.Answers.Count then
        begin
          Miss(Format('%s api %d: no answer here', [w, q]));
          Continue;
        end;
        if FMirror.Answers[at] <> want then
          Miss(Format('%s api %d: "%s" here, "%s" upstream', [w, q, FMirror.Answers[at], want]));
        Inc(at);
      end;
    end;
    view := FChart.CustomView(si);
    Inc(FCompared);
    if view = nil then Miss(Format('series %d: no view', [si]))
    else if Length(view.Root.Children) <> sj.Integers['roots'] then
      Miss(Format('series %d: %d roots here, %d upstream', [si, Length(view.Root.Children),
        sj.Integers['roots']]));
  end;
end;

procedure TAdvChartMatrix2ChartTest.TestTheCustomSeriesAsUpstream;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if (cs.Get('group', '') <> 'series') or (cs.Arrays['custom'].Count = 0) then Continue;
    FName := cs.Strings['id'];
    Draw(cs);
    CheckCustom(cs);
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the api answers were compared (%d)', [FCount]), FCount >= 140);
end;

procedure TAdvChartMatrix2ChartTest.CheckGraphs(ACase: TJSONObject);
var
  gs, ns, es: TJSONArray;
  gj, nj, ej: TJSONObject;
  k, j, si: Integer;
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
  gallery: Boolean;
  w: string;
begin
  gallery := not IsNull(ACase.Find('gallery'));
  gs := ACase.Arrays['graphs'];
  for k := 0 to gs.Count - 1 do
  begin
    gj := gs.Objects[k];
    si := gj.Integers['seriesIndex'];
    Inc(FCompared);
    if not FChart.GraphLayout(si, nodes, edges, fills) then
    begin
      Miss(Format('series %d: not laid out', [si]));
      Continue;
    end;
    ns := gj.Arrays['nodes'];
    Inc(FCompared);
    if Length(nodes) <> ns.Count then
    begin
      Miss(Format('series %d: %d nodes here, %d upstream', [si, Length(nodes), ns.Count]));
      Continue;
    end;
    for j := 0 to ns.Count - 1 do
    begin
      nj := ns.Objects[j];
      Inc(FCount);
      w := Format('series %d node %d', [si, j]);
      { A HALF-PLACED NODE (one coordinate not a number) draws nothing
        upstream; here it is not placed at all }
      if IsNan(H(nj.Arrays['p'].Items[0])) or IsNan(H(nj.Arrays['p'].Items[1])) then
      begin
        Inc(FCompared);
        if not IsNan(nodes[j].PX) then Miss(w + ': placed here, at no point upstream');
        Continue;
      end;
      SameH(w + ' x', nodes[j].PX, nj.Arrays['p'].Items[0]);
      SameH(w + ' y', nodes[j].PY, nj.Arrays['p'].Items[1]);
    end;
    { the edges: drawn when both ends are; a curved one's control point
      (the gallery's ends are cut back by its arrows: not compared) }
    if gallery then Continue;
    es := gj.Arrays['edges'];
    Inc(FCompared);
    if Length(edges) <> es.Count then
    begin
      Miss(Format('series %d: %d edges here, %d upstream', [si, Length(edges), es.Count]));
      Continue;
    end;
    for j := 0 to es.Count - 1 do
    begin
      ej := es.Objects[j];
      w := Format('series %d edge %d', [si, j]);
      Inc(FCompared);
      if (ej.Arrays['points'].Count = 3) <> edges[j].Curved then
      begin
        Miss(w + ': curved differs');
        Continue;
      end;
      if edges[j].Curved then
      begin
        SameH(w + ' cpx', edges[j].CPX, ej.Arrays['points'].Arrays[2].Items[0]);
        SameH(w + ' cpy', edges[j].CPY, ej.Arrays['points'].Arrays[2].Items[1]);
      end;
    end;
  end;
end;

procedure TAdvChartMatrix2ChartTest.TestTheGraphsAsUpstream;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if (cs.Get('group', '') <> 'series') or (cs.Arrays['graphs'].Count = 0) then Continue;
    FName := cs.Strings['id'];
    Draw(cs);
    CheckGraphs(cs);
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the nodes were compared (%d)', [FCount]), FCount >= 16);
end;

procedure TAdvChartMatrix2ChartTest.CheckPies(ACase: TJSONObject);
var
  ps, secs: TJSONArray;
  pj, sj: TJSONObject;
  k, j, q, si: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
  w: string;
begin
  lst := FChart.List;
  ps := ACase.Arrays['pies'];
  for k := 0 to ps.Count - 1 do
  begin
    pj := ps.Objects[k];
    si := pj.Integers['seriesIndex'];
    secs := pj.Arrays['sectors'];
    for j := 0 to secs.Count - 1 do
    begin
      sj := secs.Objects[j];
      w := Format('series %d sector %d', [si, j]);
      found := False;
      for q := 0 to lst.Count - 1 do
      begin
        e := lst.Element(q);
        if (e.Datum.SeriesIndex <> si) or (e.Shape.Kind <> cskSector)
          or (e.Datum.RawDataIndex <> sj.Integers['i']) then Continue;
        found := True;
        Inc(FCount);
        SameH(w + ' cx', e.Shape.CX, sj.Find('cx'));
        SameH(w + ' cy', e.Shape.CY, sj.Find('cy'));
        SameH(w + ' r0', e.Shape.R0, sj.Find('r0'));
        SameH(w + ' r', e.Shape.R1, sj.Find('r'));
        Break;
      end;
      { a centre that is not a number draws nothing }
      Inc(FCompared);
      if IsNan(H(sj.Find('cx'))) or IsNan(H(sj.Find('cy'))) then
      begin
        if found then Miss(w + ': a sector here at no centre upstream');
      end
      else if not found then Miss(w + ': no sector here');
    end;
  end;
end;

procedure TAdvChartMatrix2ChartTest.CheckFunnels(ACase: TJSONObject);
var
  fs, items, pts: TJSONArray;
  fj, ij: TJSONObject;
  k, j, q, p, si: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
  w: string;
begin
  lst := FChart.List;
  fs := ACase.Arrays['funnels'];
  for k := 0 to fs.Count - 1 do
  begin
    fj := fs.Objects[k];
    si := fj.Integers['seriesIndex'];
    items := fj.Arrays['items'];
    for j := 0 to items.Count - 1 do
    begin
      ij := items.Objects[j];
      w := Format('series %d item %d', [si, j]);
      if IsNull(ij.Find('points')) then Continue;
      pts := ij.Arrays['points'];
      found := False;
      for q := 0 to lst.Count - 1 do
      begin
        e := lst.Element(q);
        if (e.Datum.SeriesIndex <> si) or (e.Shape.Kind <> cskPolygon)
          or (e.Datum.RawDataIndex <> ij.Integers['i']) then Continue;
        found := True;
        Inc(FCount);
        Inc(FCompared);
        if Length(e.Shape.Points) <> pts.Count then
        begin
          Miss(w + ': the point count differs');
          Break;
        end;
        for p := 0 to pts.Count - 1 do
        begin
          SameH(Format('%s point %d x', [w, p]), e.Shape.Points[p].X, pts.Arrays[p].Items[0]);
          SameH(Format('%s point %d y', [w, p]), e.Shape.Points[p].Y, pts.Arrays[p].Items[1]);
        end;
        Break;
      end;
      Inc(FCompared);
      if not found then Miss(w + ': no trapezoid here');
    end;
  end;
end;

procedure TAdvChartMatrix2ChartTest.TestThePiesAndTheFunnelInCellsAsUpstream;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Get('group', '') <> 'series' then Continue;
    if (cs.Arrays['pies'].Count = 0) and (cs.Arrays['funnels'].Count = 0) then Continue;
    FName := cs.Strings['id'];
    Draw(cs);
    CheckPies(cs);
    CheckFunnels(cs);
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the sectors and trapezoids were compared (%d)', [FCount]), FCount >= 100);
end;

{ ---- the pointer ---- }

type
  TMx2Row = record
    Marker, Name, Value: string;
    HasMarker, HasName, HasValue: Boolean;
  end;

function RowsOf(ABlock: TTyTooltipBlock): string;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j: Integer;
  row: TMx2Row;

  function Q(AHas: Boolean; const S: string): string;
  begin
    if AHas then Result := '"' + S + '"' else Result := 'null';
  end;

begin
  Result := '';
  if ABlock = nil then Exit;
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  for i := 0 to High(lines) do
  begin
    row := Default(TMx2Row);
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind = ttrMarker then
      begin
        row.HasMarker := True;
        if lines[i].Runs[j].MarkerSizeLogical = 10 then row.Marker := 'item'
        else row.Marker := 'subItem';
      end
      else if lines[i].Runs[j].FontWeight = 900 then
      begin
        row.HasValue := True;
        row.Value := lines[i].Runs[j].Text;
      end
      else
      begin
        row.HasName := True;
        row.Name := lines[i].Runs[j].Text;
      end;
    Result := Result + '{' + Q(row.HasMarker, row.Marker) + ' ' + Q(row.HasName, row.Name)
      + ' ' + Q(row.HasValue, row.Value) + '}';
  end;
end;

function WantRows(ARows: TJSONArray): string;
var i: Integer;

  function Q(ARow: TJSONObject; const AKey: string): string;
  var d: TJSONData;
  begin
    d := ARow.Find(AKey);
    if (d = nil) or (d.JSONType = jtNull) then Result := 'null'
    else Result := '"' + d.AsString + '"';
  end;

begin
  Result := '';
  for i := 0 to ARows.Count - 1 do
    Result := Result + '{' + Q(ARows.Objects[i], 'marker') + ' ' + Q(ARows.Objects[i], 'name')
      + ' ' + Q(ARows.Objects[i], 'value') + '}';
end;

{ upstream's event as the logger's line; AGraph: a graph node's name is
  left out (a graph on a matrix names its array items by nothing here: see
  the batch's deviations) }
function WantEvent(E: TJSONObject; AGraph: Boolean): string;
var
  d: TJSONData;
  nm, v: string;
begin
  Result := E.Strings['type'] + ' ' + E.Get('componentType', '');
  nm := '';
  d := E.Find('name');
  if not IsNull(d) and not AGraph then nm := d.AsString;
  if E.Get('componentType', '') = 'matrix' then
  begin
    v := '';
    d := E.Find('value');
    if not IsNull(d) then v := d.AsString;
    Result := Result + Format(' %d %s name=%s value=%s', [E.Integers['componentIndex'],
      E.Strings['targetType'], nm, v]);
    d := E.Find('coord');
    if d is TJSONArray then
      Result := Result + Format(' [%s,%s]', [Fmt(TJSONArray(d).Floats[0]), Fmt(TJSONArray(d).Floats[1])]);
  end
  else
    Result := Result + Format(' %d %d name=%s', [E.Integers['seriesIndex'], E.Integers['dataIndex'], nm]);
end;

procedure TAdvChartMatrix2ChartTest.RunPointer(ACase: TJSONObject);
var
  steps, states, evs: TJSONArray;
  st, hit, tip: TJSONObject;
  lg: TMx2Logger;
  k, j, el, x, y, idOver, idOut: Integer;
  d: TTyChartDatumRef;
  info: TTyMatrixCellInfo;
  m: TTyMatrix;
  nowMs: Double;
  w, role: string;
  isGraph: Boolean;

  function IsGraphSeries(ASeries: Integer): Boolean;
  var s: TJSONData;
  begin
    Result := False;
    if ACase.Find('option') is TJSONObject then
    begin
      s := ACase.Objects['option'].Find('series');
      if (s is TJSONArray) and (ASeries >= 0) and (ASeries < s.Count) then
        Result := TJSONObject(s.Items[ASeries]).Get('type', '') = 'graph';
    end;
  end;

begin
  lg := TMx2Logger.Create;
  lg.Log := TStringList.Create;
  try
    idOver := FChart.ChartOn('mouseover', @lg.Handle);
    idOut := FChart.ChartOn('mouseout', @lg.Handle);
    Draw(ACase);
    steps := ACase.Arrays['steps'];
    states := ACase.Arrays['states'];
    for k := 0 to steps.Count - 1 do
    begin
      st := states.Objects[k];
      w := Format('step %d', [k]);
      x := steps.Objects[k].Arrays['p'].Integers[0];
      y := steps.Objects[k].Arrays['p'].Integers[1];
      nowMs := (k + 1) * 1000;
      lg.Log.Clear;
      FChart.TooltipNow := nowMs;
      FChart.Move(x, y);
      FChart.TooltipTick(nowMs + 500);
      FChart.TooltipNow := nowMs + 500;
      RenderNow;
      Inc(FCount);
      { what is under the pointer }
      d := FChart.HitTestAt(x, y, el);
      Inc(FCompared);
      if IsNull(st.Find('hit')) then
      begin
        if el >= 0 then Miss(Format('%s: something hit here (%d), nothing upstream', [w, Ord(d.Kind)]));
      end
      else
      begin
        hit := st.Objects['hit'];
        if el < 0 then Miss(w + ': nothing hit here')
        else if hit.Strings['kind'] = 'series' then
        begin
          if (d.SeriesIndex <> hit.Integers['seriesIndex']) or (d.DataIndex <> hit.Integers['dataIndex']) then
            Miss(Format('%s: item %d/%d here, %d/%d upstream', [w, d.SeriesIndex, d.DataIndex,
              hit.Integers['seriesIndex'], hit.Integers['dataIndex']]));
        end
        else if (d.Kind <> ctkMatrix) or (d.ComponentIndex <> hit.Integers['matrixIndex']) then
          Miss(Format('%s: not matrix %d here', [w, hit.Integers['matrixIndex']]))
        else
        begin
          m := FChart.MatrixLayout(d.ComponentIndex);
          info := m.CellInfo(d.DataIndex);
          if FChart.List.Element(el).Caption.Text <> '' then role := 'label' else role := 'rect';
          if (info.Target <> hit.Strings['target']) or (role <> hit.Strings['role'])
            or (info.Loc[0] <> hit.Arrays['loc'].Integers[0])
            or (info.Loc[1] <> hit.Arrays['loc'].Integers[1]) then
            Miss(Format('%s: %s %s [%d,%d] here, %s %s %s upstream', [w, role, info.Target,
              info.Loc[0], info.Loc[1], hit.Strings['role'], hit.Strings['target'],
              hit.Arrays['loc'].AsJSON]));
        end;
      end;
      { the mouse events }
      evs := st.Arrays['events'];
      Inc(FCompared);
      if lg.Log.Count <> evs.Count then
        Miss(Format('%s: %d events here (%s), %d upstream', [w, lg.Log.Count,
          StringReplace(lg.Log.Text, LineEnding, ' | ', [rfReplaceAll]), evs.Count]))
      else
        for j := 0 to evs.Count - 1 do
        begin
          Inc(FCompared);
          isGraph := (evs.Objects[j].Get('componentType', '') = 'series')
            and IsGraphSeries(evs.Objects[j].Integers['seriesIndex']);
          if lg.Log[j] <> WantEvent(evs.Objects[j], isGraph) then
            Miss(Format('%s event %d: "%s" here, "%s" upstream', [w, j, lg.Log[j],
              WantEvent(evs.Objects[j], isGraph)]));
        end;
      { the tooltip }
      if st.Find('tooltip') is TJSONObject then
      begin
        tip := st.Objects['tooltip'];
        Inc(FCompared);
        if FChart.TooltipShown <> tip.Booleans['shown'] then
          Miss(Format('%s: tooltip shown %s here', [w, BoolToStr(FChart.TooltipShown, True)]))
        else if tip.Booleans['shown'] then
        begin
          Inc(FCompared);
          if not IsNull(tip.Find('text')) then
          begin
            if FChart.TooltipFormatterText <> tip.Strings['text'] then
              Miss(Format('%s: tooltip "%s" here, "%s" upstream', [w, FChart.TooltipFormatterText,
                tip.Strings['text']]));
          end
          else if IsGraphSeries(FChart.TooltipShownDatum.SeriesIndex) then
            { a graph node's rows on a matrix: a deviation (see above) }
          else if RowsOf(FChart.ContentOf(FChart.TooltipShownDatum)) <> WantRows(tip.Arrays['rows']) then
            Miss(Format('%s: tooltip rows %s here, %s upstream', [w,
              RowsOf(FChart.ContentOf(FChart.TooltipShownDatum)), WantRows(tip.Arrays['rows'])]));
        end;
      end;
    end;
  finally
    FChart.ChartOff(idOver);
    FChart.ChartOff(idOut);
    lg.Log.Free;
    lg.Free;
  end;
end;

procedure TAdvChartMatrix2ChartTest.TestThePointerAsUpstream;
var
  cases: TJSONArray;
  cs: TJSONObject;
  c: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Get('group', '') <> 'pointer' then Continue;
    FName := cs.Strings['id'];
    RunPointer(cs);
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the steps were taken (%d)', [FCount]), FCount >= 21);
end;

{ the JSON form of convertToLayout: a rect, a locator range, nulls }
procedure TAdvChartMatrix2ChartTest.TestConvertToLayoutPrintsJson;
var s: string;
begin
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation": false, "matrix": {"left": 100, "top": 100, "width": 200,'
    + ' "height": 100, "x": {"data": ["a", "b"]}, "y": {"data": ["p"], "show": false}}}';
  RenderNow;
  s := FChart.ConvertToLayout('"matrix"', '[["a", "b"], "p"]');
  AssertEquals('a range', '{"rect":{"x":100,"y":150,"width":200,"height":50},'
    + '"matrixXYLocatorRange":[[0,1],[0,0]]}', s);
  s := FChart.ConvertToLayout('"matrix"', '[null, "p"]', '{"clamp": 3}');
  AssertEquals('clamped to the corner, both ways: the header levels',
    '{"rect":{"x":100,"y":100,"width":0,"height":50},'
    + '"matrixXYLocatorRange":[[-1,-1],[-1,-1]]}', s);
  s := FChart.ConvertToLayout('"matrix"', '["zz", "p"]');
  AssertEquals('nothing named is null', '{"rect":{"x":null,"y":150,"width":null,"height":50},'
    + '"matrixXYLocatorRange":[[null,null],[0,0]]}', s);
  AssertEquals('no coordinate system answers', '', FChart.ConvertToLayout('"grid"', '[0, 0]'));
  AssertEquals('the opt reaches convertToPixel', '[200,175]',
    FChart.ConvertToPixel('"matrix"', '[null, "p"]', '{"clamp": 1}'));
  AssertEquals('and convertFromPixel', '[0,0]',
    FChart.ConvertFromPixel('"matrix"', '[5, 5]', '{"clamp": 2}'));
end;

{ CoordRange / LayoutRange off a matrix: nothing, as upstream has no range
  there }
procedure TAdvChartMatrix2ChartTest.TestTheApiOffAMatrixAnswersNoRange;
begin
  FChart.SetBounds(0, 0, cW, cH);
  FMirror.Clear;
  FChart.Option := '{"animation": false, "xAxis": {"type": "category", "data": ["a", "b"]},'
    + ' "yAxis": {}, "series": {"type": "custom", "renderItem": "@mxRange",'
    + ' "data": [[0, 1]]}}';
  RenderNow;
  AssertTrue('the renderItem ran', FMirror.Answers.Count > 0);
  AssertEquals('a range layout off a matrix is no layout',
    'layout 0000000000000000 0000000000000000 0000000000000000 0000000000000000 '
    + '0000000000000000 0000000000000000 0000000000000000 0000000000000000', FMirror.Answers[0]);
  AssertEquals('a range coord off a matrix is none', 'coord none', FMirror.Answers[2]);
end;

initialization
  RegisterTest(TAdvChartMatrix2AlgebraTest);
  RegisterTest(TAdvChartMatrix2ViewTest);
  RegisterTest(TAdvChartMatrix2ChartTest);
end.
