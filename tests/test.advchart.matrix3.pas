unit test.advchart.matrix3;
{$mode objfpc}{$H+}
{ THE MATRIX COORDINATE SYSTEM, part three (D12 MX3, batch 149), held to
  what ECharts 6.1 builds and answers.

  tools/advchart-oracle/matrix3.js runs the real dist and records:

    the view      per matrix the trees, every element of the view in order
                  (a body or corner cell in another's merge is not there, a
                  merge is its spanRect), probes through dataToLayout /
                  dataToPoint, and the body's and the corner's CELL MAPS
                  (every cell an item reached, in the map's order: the item
                  it holds or a merge's copy, the owner, the span, the
                  locator range, the spanRect; the owners in order) -- body
                  and corner data on flat and nested headers, merges that
                  overlap, nest, chain, keep a stale span, sit on header
                  locators, the hidden-header layout, labels through
                  templates and named formatters, gradient fills and a decal
                  that is not drawn, and the three gallery files;
    the algebra   dataToLayout of every locator pair and some ranges over
                  merged cells under ten opts (ignoreMergeCells, the clamps
                  that skip the body's or the corner's merges);
    the series    heatmap and scatter rows, a custom series' api answers
                  with and without ignoreMergeCells, pies in merged cells,
                  the conversions with the opt;
    the pointer   merged and valued cells under the pointer: the hit, the
                  events, the tooltip;
    the merge     the box a later setOption writes back into the matrix.

  This replays each through the port: the view through part one's checks
  (TAdvChartMatrixOracleTest on this fixture) and its own (the cell maps,
  the object fills; the gallery through the control as well), the algebra
  on the pure unit, the rest through the control. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.FontUnits,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Color,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Convert,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Events,
     tyControls.AdvChart.Custom, tyControls.AdvChart.Matrix,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.matrix, test.advchart.matrix2;
type
  { part two's probe, with the tooltip's text in reach }
  TMx3Probe = class(TMx2Probe)
  public
    function TipText: string;
  end;

  { matrix3.js's named label formatters, transcribed }
  TMx3Formatters = class
  public
    { p.name + '#' + p.componentIndex + '@' + p.coord.join(':') }
    function Fmt(const AParams: TTyChartParams): string;
    { '[' + p.value + ']' }
    function Val(const AParams: TTyChartParams): string;
  end;

  { matrix3.js's renderItems, transcribed; each api answer written down in
    order, as the oracle's recorder writes it }
  TMx3Mirror = class
  public
    Answers: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure LogLayout(const L: TTyCustomLayout);
    procedure LogCoord(const P: TTyDoubleArray);
    function Mx3Cell(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Mx3Gal(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  { the view cases through part one's checks, and this part's own }
  TAdvChartMatrix3ViewTest = class(TAdvChartMatrixOracleTest)
  private
    FFmt: TMx3Formatters;
    FMirror: TMx3Mirror;
    FMaps, FFills: Integer;
    procedure CheckMaps(M: TTyMatrix; AMaps: TJSONObject);
    procedure CheckFills(M: TTyMatrix; AM: TJSONObject);
  protected
    function FixtureFile: string; override;
    function MinCells: Integer; override;
    function MinProbes: Integer; override;
    function MinEls: Integer; override;
    function MinLabels: Integer; override;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCellMapsAsUpstream;
    procedure TestTheObjectFillsAsUpstream;
    procedure TestTheGalleryThroughTheControlAsUpstream;
  end;

  { the pure unit: dataToLayout over merged cells }
  TAdvChartMatrix3AlgebraTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FOpt: TTyChartOption;
    FBad, FCompared, FLayouts: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDataToLayoutOverMergesAsUpstream;
    procedure TestTheIgnoreMergeCellsWords;
    procedure TestAMergeCrossingIntoTheBodyIsDrawnNotRaised;
    procedure TestHostileItemsAreBounded;
  end;

  { the control }
  TAdvChartMatrix3ChartTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMx3Probe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FMirror: TMx3Mirror;
    FFmt: TMx3Formatters;
    FBad, FCompared, FCount: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
    function CaseOf(const AId: string): TJSONObject;
    procedure RenderNow;
    procedure Draw(ACase: TJSONObject);
    procedure CheckCall(ACall: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSeriesInMergedCellsAsUpstream;
    procedure TestTheConversionsAsUpstream;
    procedure TestThePointerAsUpstream;
    procedure TestTheBoxALaterOptionMergesAsUpstream;
  end;

implementation

const
  cW = 800;
  cH = 600;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-matrix3.json';
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

function HexOf(A: Double): string;
begin
  Result := LowerCase(IntToHex(Int64(Bits(A)), 16));
  if IsNan(A) then Result := '7ff8000000000000';
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

{ part one's sentinel ink }
function TestInk: TTyMatrixInk;
begin
  Result.CellBorder := $FF0A0B0C;
  Result.Divider := $FF0D0E0F;
  Result.OuterBorder := $FF101112;
  Result.LabelColour := $FF131415;
end;

{ a gallery custom series draws with the generic cell }
procedure GalleryCustom(AOpt: TJSONObject);
var
  s: TJSONData;
  k: Integer;
begin
  s := AOpt.Find('series');
  if s is TJSONObject then
  begin
    if TJSONObject(s).Get('type', '') = 'custom' then TJSONObject(s).Strings['renderItem'] := '@mx3Gal';
  end
  else if s is TJSONArray then
    for k := 0 to s.Count - 1 do
      if (s.Items[k] is TJSONObject) and (TJSONObject(s.Items[k]).Get('type', '') = 'custom') then
        TJSONObject(s.Items[k]).Strings['renderItem'] := '@mx3Gal';
end;

procedure RegisterAll(AFmt: TMx3Formatters; AMirror: TMx3Mirror);
begin
  TyChartRegisterFormatter('mx3Fmt', @AFmt.Fmt);
  TyChartRegisterFormatter('mx3Val', @AFmt.Val);
  TyChartRegisterRenderItem('mx3Cell', @AMirror.Mx3Cell);
  TyChartRegisterRenderItem('mx3Gal', @AMirror.Mx3Gal);
end;

procedure UnregisterAll;
begin
  TyChartUnregisterFormatter('mx3Fmt');
  TyChartUnregisterFormatter('mx3Val');
  TyChartUnregisterRenderItem('mx3Cell');
  TyChartUnregisterRenderItem('mx3Gal');
end;

{ ==================== the formatters and the mirror ==================== }

function TMx3Probe.TipText: string;
begin
  Result := TooltipFormatterText;
end;

function TMx3Formatters.Fmt(const AParams: TTyChartParams): string;
var p: TTyChartCallbackParams;
begin
  p := AParams[0];
  Result := p.Name + '#' + IntToStr(p.ComponentIndex) + '@';
  if Length(p.Coord) = 2 then
    Result := Result + TyChartValueText(p.Coord[0]) + ':' + TyChartValueText(p.Coord[1]);
end;

function TMx3Formatters.Val(const AParams: TTyChartParams): string;
begin
  Result := '[' + AParams[0].ValueText + ']';
end;

constructor TMx3Mirror.Create;
begin
  inherited Create;
  Answers := TStringList.Create;
end;

destructor TMx3Mirror.Destroy;
begin
  Answers.Free;
  inherited Destroy;
end;

procedure TMx3Mirror.LogLayout(const L: TTyCustomLayout);
begin
  Answers.Add('layout ' + HexOf(L.Rect.X) + ' ' + HexOf(L.Rect.Y) + ' ' + HexOf(L.Rect.Width)
    + ' ' + HexOf(L.Rect.Height) + ' ' + HexOf(L.LocatorRange[0][0]) + ' '
    + HexOf(L.LocatorRange[0][1]) + ' ' + HexOf(L.LocatorRange[1][0]) + ' '
    + HexOf(L.LocatorRange[1][1]));
end;

procedure TMx3Mirror.LogCoord(const P: TTyDoubleArray);
begin
  if Length(P) < 2 then Answers.Add('coord none')
  else Answers.Add('coord ' + HexOf(P[0]) + ' ' + HexOf(P[1]));
end;

{ RENDER.mx3Cell, every call in JavaScript's order }
function TMx3Mirror.Mx3Cell(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, y, r: Double;
  a, b, d: TTyCustomLayout;
  c: TTyDoubleArray;
begin
  x := AApi.Value(0);
  y := AApi.Value(1);
  a := AApi.Layout([x, y]);
  LogLayout(a);
  b := AApi.LayoutRange([x], [y], 0, True);
  LogLayout(b);
  c := AApi.Coord([x, y]);
  LogCoord(c);
  d := AApi.LayoutRange([x, x], [y], 2);
  LogLayout(d);
  if IsNan(a.Rect.X) or IsNan(a.Rect.Y) then Exit(nil);
  if d.Rect.Width > 0 then r := 3 else r := 2;
  Result := TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
    TJSONObject.Create(['type', 'rect', 'shape', TJSONObject.Create(['x', a.Rect.X + 2,
      'y', a.Rect.Y + 2, 'width', a.Rect.Width - 4, 'height', a.Rect.Height - 4]),
      'style', TJSONObject.Create(['fill', '#88aadd'])]),
    TJSONObject.Create(['type', 'rect', 'shape', TJSONObject.Create(['x', b.Rect.X + 4,
      'y', b.Rect.Y + 4, 'width', b.Rect.Width - 8, 'height', b.Rect.Height - 8]),
      'style', TJSONObject.Create(['fill', '#ddaa88'])]),
    TJSONObject.Create(['type', 'circle', 'shape', TJSONObject.Create(['cx', c[0], 'cy', c[1],
      'r', r]), 'style', TJSONObject.Create(['fill', '#ffffff'])])])]);
end;

{ RENDER.mx3Gal }
function TMx3Mirror.Mx3Gal(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var lay: TTyCustomLayout;
begin
  lay := AApi.Layout([AApi.Value(0), AApi.Value(1)]);
  LogLayout(lay);
  if IsNan(lay.Rect.X) or IsNan(lay.Rect.Y) then Exit(nil);
  Result := TJSONObject.Create(['type', 'rect', 'shape', TJSONObject.Create(['x', lay.Rect.X,
    'y', lay.Rect.Y, 'width', lay.Rect.Width, 'height', lay.Rect.Height]),
    'style', TJSONObject.Create(['fill', '#cccccc'])]);
end;

{ ==================== the view ==================== }

function TAdvChartMatrix3ViewTest.FixtureFile: string;
begin
  Result := FixturePath;
end;

function TAdvChartMatrix3ViewTest.MinCells: Integer;
begin
  Result := 100;
end;

function TAdvChartMatrix3ViewTest.MinProbes: Integer;
begin
  Result := 600;
end;

function TAdvChartMatrix3ViewTest.MinEls: Integer;
begin
  Result := 300;
end;

function TAdvChartMatrix3ViewTest.MinLabels: Integer;
begin
  Result := 150;
end;

procedure TAdvChartMatrix3ViewTest.SetUp;
begin
  inherited SetUp;
  FFmt := TMx3Formatters.Create;
  FMirror := TMx3Mirror.Create;
  RegisterAll(FFmt, FMirror);
  FMaps := 0;
  FFills := 0;
end;

procedure TAdvChartMatrix3ViewTest.TearDown;
begin
  UnregisterAll;
  FreeAndNil(FMirror);
  FreeAndNil(FFmt);
  inherited TearDown;
end;

procedure TAdvChartMatrix3ViewTest.CheckMaps(M: TTyMatrix; AMaps: TJSONObject);
const
  cKinds: array[0..1] of string = ('body', 'corner');
var
  kind, i, q: Integer;
  mj, cj: TJSONObject;
  cells, owners: TJSONArray;
  bc: TTyMatrixBodyCorner;
  c, o: TTyMatrixBCCell;
  w: string;
  d: TJSONData;
begin
  for kind := 0 to 1 do
  begin
    mj := AMaps.Objects[cKinds[kind]];
    cells := mj.Arrays['cells'];
    bc := M.CellMap(kind);
    Inc(FCompared);
    if bc.Count <> cells.Count then
    begin
      Miss(Format('%s map: %d cells here, %d upstream', [cKinds[kind], bc.Count, cells.Count]));
      Continue;
    end;
    for i := 0 to cells.Count - 1 do
    begin
      Inc(FMaps);
      cj := cells.Objects[i];
      c := bc.Cell(i);
      w := Format('%s cell %d %s', [cKinds[kind], i, cj.Arrays['id'].AsJSON]);
      Inc(FCompared, 5);
      if (c.X <> cj.Arrays['id'].Integers[0]) or (c.Y <> cj.Arrays['id'].Integers[1]) then
        Miss(Format('%s: at [%d,%d] here', [w, c.X, c.Y]));
      if c.Src <> cj.Integers['src'] then
        Miss(Format('%s: item %d here, %d upstream', [w, c.Src, cj.Integers['src']]));
      if c.Copied <> cj.Booleans['copy'] then Miss(w + ': the copy differs');
      if c.Owner <> cj.Booleans['owner'] then Miss(w + ': the owner differs');
      d := cj.Find('inSpanOf');
      if IsNull(d) then
      begin
        if c.InSpanOf >= 0 then Miss(w + ': in a span here, none upstream');
      end
      else if c.InSpanOf < 0 then Miss(w + ': in no span here')
      else
      begin
        o := bc.Cell(c.InSpanOf);
        if (o.X <> TJSONArray(d).Integers[0]) or (o.Y <> TJSONArray(d).Integers[1]) then
          Miss(Format('%s: in the span of [%d,%d] here, %s upstream', [w, o.X, o.Y, d.AsJSON]));
      end;
      d := cj.Find('span');
      Inc(FCompared);
      if IsNull(d) then
      begin
        if c.HasSpan then Miss(w + ': a span here, none upstream');
        Continue;
      end;
      if not c.HasSpan then
      begin
        Miss(w + ': no span here');
        Continue;
      end;
      Inc(FCompared, 2);
      if (c.Span[0] <> TJSONArray(d).Integers[0]) or (c.Span[1] <> TJSONArray(d).Integers[1]) then
        Miss(Format('%s: span [%d,%d] here, %s upstream', [w, c.Span[0], c.Span[1], d.AsJSON]));
      for q := 0 to 3 do
        SameH(Format('%s loc %d', [w, q]), c.Loc[q div 2][q mod 2],
          cj.Arrays['loc'].Arrays[q div 2].Items[q mod 2]);
      SameH(w + ' spanRect x', c.SpanRect.X, cj.Objects['spanRect'].Find('x'));
      SameH(w + ' spanRect y', c.SpanRect.Y, cj.Objects['spanRect'].Find('y'));
      SameH(w + ' spanRect width', c.SpanRect.W, cj.Objects['spanRect'].Find('width'));
      SameH(w + ' spanRect height', c.SpanRect.H, cj.Objects['spanRect'].Find('height'));
    end;
    owners := mj.Arrays['owners'];
    Inc(FCompared);
    if bc.OwnerCount <> owners.Count then
    begin
      Miss(Format('%s map: %d merges here, %d upstream', [cKinds[kind], bc.OwnerCount, owners.Count]));
      Continue;
    end;
    for q := 0 to owners.Count - 1 do
    begin
      Inc(FCompared);
      o := bc.Cell(bc.Owner(q));
      if (o.X <> owners.Arrays[q].Integers[0]) or (o.Y <> owners.Arrays[q].Integers[1]) then
        Miss(Format('%s merge %d: [%d,%d] here, %s upstream', [cKinds[kind], q, o.X, o.Y,
          owners.Arrays[q].AsJSON]));
    end;
  end;
end;

{ the fills that are objects, and the decal a cell does not get: the
  elements walked as part one walks them (a label right after its cell) }
procedure TAdvChartMatrix3ViewTest.CheckFills(M: TTyMatrix; AM: TJSONObject);
var
  list: TTyPaintList;
  els, stops: TJSONArray;
  ej, st, fo: TJSONObject;
  e: TTyChartElement;
  g: TTyRtGlobal;
  k, at, j: Integer;
  w: string;
  want: TTyChartColor;

  procedure SameN(const AWhat: string; AGot: Double; AWant: TJSONData);
  begin
    Inc(FCompared);
    if IsNull(AWant) then Exit;
    if not SameBits(AGot, AWant.AsFloat) then
      Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(AWant.AsFloat)]));
  end;

begin
  list := TTyPaintList.Create;
  try
    g := Default(TTyRtGlobal);
    g.FontFamily := 'sans-serif';
    g.FontSizeLogical := TyFontSizeFromPx(12);
    g.FontWeight := 400;
    TyBuildMatrix(M, TestInk, g, FMeas, 96, list);
    els := AM.Arrays['els'];
    at := 0;
    for k := 0 to els.Count - 1 do
    begin
      ej := els.Objects[k];
      if at >= list.Count then Exit;
      e := list.Element(at);
      Inc(at);
      if (at < list.Count) and (list.Element(at).Caption.Text <> '') then Inc(at);
      st := ej.Objects['style'];
      w := Format('el %d (%s %s)', [k, ej.Strings['role'], ej.Find('loc').AsJSON]);
      Inc(FCompared);
      if st.Booleans['decal'] <> e.Style.Decal.Present then Miss(w + ': the decal differs');
      if not (st.Find('fillObj') is TJSONObject) then
      begin
        Inc(FCompared);
        if e.Style.FillGradient.Kind <> cgkNone then Miss(w + ': a gradient here, none upstream');
        Continue;
      end;
      Inc(FFills);
      fo := st.Objects['fillObj'];
      Inc(FCompared);
      if (fo.Get('type', '') = 'radial') <> (e.Style.FillGradient.Kind = cgkRadial) then
        Miss(w + ': the gradient kind differs');
      if (fo.Get('type', '') = 'linear') <> (e.Style.FillGradient.Kind = cgkLinear) then
        Miss(w + ': the gradient kind differs');
      SameN(w + ' x', e.Style.FillGradient.X, fo.Find('x'));
      SameN(w + ' y', e.Style.FillGradient.Y, fo.Find('y'));
      if e.Style.FillGradient.Kind = cgkLinear then
      begin
        SameN(w + ' x2', e.Style.FillGradient.X2, fo.Find('x2'));
        SameN(w + ' y2', e.Style.FillGradient.Y2, fo.Find('y2'));
      end
      else
        SameN(w + ' r', e.Style.FillGradient.R, fo.Find('r'));
      Inc(FCompared);
      if e.Style.FillGradient.Global <> fo.Booleans['global'] then Miss(w + ': global differs');
      stops := fo.Arrays['stops'];
      Inc(FCompared);
      if Length(e.Style.FillGradient.Stops) <> stops.Count then
      begin
        Miss(Format('%s: %d stops here, %d upstream', [w, Length(e.Style.FillGradient.Stops),
          stops.Count]));
        Continue;
      end;
      for j := 0 to stops.Count - 1 do
      begin
        SameN(Format('%s stop %d', [w, j]), e.Style.FillGradient.Stops[j].Offset,
          stops.Objects[j].Find('offset'));
        Inc(FCompared);
        if TyTryParseChartColor(stops.Objects[j].Strings['color'], want)
          and (e.Style.FillGradient.Stops[j].Color <> want) then
          Miss(Format('%s stop %d: %.8x here, %s upstream', [w, j,
            e.Style.FillGradient.Stops[j].Color, stops.Objects[j].Strings['color']]));
      end;
      Inc(FCompared);
      if not e.Style.HasFill then Miss(w + ': a gradient cell with no fill here');
    end;
  finally
    list.Free;
  end;
end;

procedure TAdvChartMatrix3ViewTest.TestTheCellMapsAsUpstream;
var
  cases, ms: TJSONArray;
  cs, opt: TJSONObject;
  c, k: Integer;
  m: TTyMatrix;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Get('group', '') <> 'view' then Continue;
    if not Pure(cs) then Continue;
    opt := OptionOf(cs);
    try
      FOpt.SetOptionText('{}');
      FOpt.SetOptionText(opt.AsJSON);
    finally
      opt.Free;
    end;
    ms := cs.Arrays['matrices'];
    for k := 0 to ms.Count - 1 do
    begin
      FName := Format('%s matrix %d', [cs.Strings['id'], k]);
      m := TTyMatrix.Create(FOpt, k);
      try
        m.Resize(TyRectF(0, 0, cW, cH), 96);
        CheckMaps(m, ms.Objects[k].Objects['maps']);
      finally
        m.Free;
      end;
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the map cells were compared (%d)', [FMaps]), FMaps >= 150);
end;

procedure TAdvChartMatrix3ViewTest.TestTheObjectFillsAsUpstream;
var
  cases, ms: TJSONArray;
  cs, opt: TJSONObject;
  c, k: Integer;
  m: TTyMatrix;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Get('group', '') <> 'view' then Continue;
    if not Pure(cs) then Continue;
    opt := OptionOf(cs);
    try
      FOpt.SetOptionText('{}');
      FOpt.SetOptionText(opt.AsJSON);
    finally
      opt.Free;
    end;
    ms := cs.Arrays['matrices'];
    for k := 0 to ms.Count - 1 do
    begin
      FName := Format('%s matrix %d', [cs.Strings['id'], k]);
      m := TTyMatrix.Create(FOpt, k);
      try
        m.Resize(TyRectF(0, 0, cW, cH), 96);
        CheckFills(m, ms.Objects[k]);
      finally
        m.Free;
      end;
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the gradient fills were compared (%d)', [FFills]), FFills >= 2);
end;

{ THE GALLERY THROUGH THE CONTROL: the matrices the chart built (a
  collecting tree's names from a dataset through its series' encode) --
  trees, probes, picture and cell maps }
procedure TAdvChartMatrix3ViewTest.TestTheGalleryThroughTheControlAsUpstream;
var
  form: TForm;
  ctl: TTyStyleController;
  chart: TMxProbe;
  bmp: TBGRABitmap;
  cases, ms: TJSONArray;
  cs, opt: TJSONObject;
  c, k, n: Integer;
  m: TTyMatrix;
begin
  form := TForm.CreateNew(nil);
  ctl := TTyStyleController.Create(nil);
  bmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  n := 0;
  try
    ctl.Mode := 'light';
    ctl.ThemeName := 'default';
    chart := TMxProbe.Create(form);
    chart.Parent := form;
    chart.Controller := ctl;
    chart.Measurer := TPtToPxMeasurer.Create(FMeas);
    cases := TJSONObject(FRoot).Arrays['cases'];
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      if (cs.Get('group', '') <> 'view') or IsNull(cs.Find('gallery')) then Continue;
      FName := cs.Strings['id'] + ' (the control)';
      opt := TJSONObject(LoadJson(GalleryPath(cs.Strings['gallery'])));
      try
        GalleryCustom(opt);
        opt.Booleans['animation'] := False;
        chart.SetBounds(0, 0, cW, cH);
        chart.Option := '{}';
        chart.Option := opt.AsJSON;
        chart.Render(bmp.Canvas, Classes.Rect(0, 0, cW, cH), 96);
      finally
        opt.Free;
      end;
      ms := cs.Arrays['matrices'];
      for k := 0 to ms.Count - 1 do
      begin
        m := chart.MatrixLayout(k);
        Inc(FCompared);
        if m = nil then
        begin
          Miss(Format('matrix %d not built', [k]));
          Continue;
        end;
        Inc(n);
        CheckTrees(m, ms.Objects[k]);
        CheckProbes(m, ms.Objects[k]);
        CheckPicture(m, ms.Objects[k]);
        CheckMaps(m, ms.Objects[k].Objects['maps']);
      end;
    end;
    chart.Measurer := nil;
    chart.Controller := nil;
  finally
    bmp.Free;
    form.Free;
    ctl.Free;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertEquals('the three gallery matrices were compared', 3, n);
end;

{ ==================== the algebra ==================== }

procedure TAdvChartMatrix3AlgebraTest.SetUp;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  FOpt := TTyChartOption.Create;
  FBad := 0;
  FCompared := 0;
  FLayouts := 0;
  FReport := '';
end;

procedure TAdvChartMatrix3AlgebraTest.TearDown;
begin
  FreeAndNil(FOpt);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartMatrix3AlgebraTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMatrix3AlgebraTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if not SameBits(AGot, H(AWant)) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(H(AWant))]));
end;

procedure TAdvChartMatrix3AlgebraTest.TestDataToLayoutOverMergesAsUpstream;
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
        lays := mj.Arrays['layouts'];
        for j := 0 to lays.Count - 1 do
        begin
          lj := lays.Objects[j];
          Inc(FLayouts);
          w := lj.Find('input').AsJSON + ' opt ' + lj.Find('opt').AsJSON;
          TyMatrixLayoutJson(m, lj.Find('input'), TyMatrixClampOfOpt(lj.Find('opt')), r, loc,
            TyMatrixIgnoreMergeOfOpt(lj.Find('opt')));
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
  AssertTrue(Format('the layouts were compared (%d)', [FLayouts]), FLayouts >= 1000);
end;

{ `opt && opt.ignoreMergeCells`: truthy, an opt that is not an object none }
procedure TAdvChartMatrix3AlgebraTest.TestTheIgnoreMergeCellsWords;

  function I(const AJson: string): Boolean;
  var d: TJSONData;
  begin
    d := GetJSON(AJson);
    try
      Result := TyMatrixIgnoreMergeOfOpt(d);
    finally
      d.Free;
    end;
  end;

begin
  AssertFalse('nil', TyMatrixIgnoreMergeOfOpt(nil));
  AssertFalse('no key', I('{}'));
  AssertTrue('true', I('{"ignoreMergeCells": true}'));
  AssertTrue('1', I('{"ignoreMergeCells": 1}'));
  AssertTrue('a word', I('{"ignoreMergeCells": "yes"}'));
  AssertFalse('0', I('{"ignoreMergeCells": 0}'));
  AssertFalse('empty text', I('{"ignoreMergeCells": ""}'));
  AssertFalse('null', I('{"ignoreMergeCells": null}'));
  AssertFalse('false', I('{"ignoreMergeCells": false}'));
  AssertFalse('not an object', I('[true]'));
end;

{ A MERGE FROM A HEADER LEVEL INTO THE BODY: upstream's _resize throws
  (layOutRectOneDimBasedOnUnit asks the header tree for a body locator) and
  the whole setOption fails; the port draws the span, each end from its own
  tree, and raises nothing }
procedure TAdvChartMatrix3AlgebraTest.TestAMergeCrossingIntoTheBodyIsDrawnNotRaised;
var
  m: TTyMatrix;
  bc: TTyMatrixBodyCorner;
  c: TTyMatrixBCCell;
  lx, lw, bx, bw: Double;
  list: TTyPaintList;
  g: TTyRtGlobal;
  r: TTyXYWH;
  loc: TTyMatrixLocRange;
begin
  FOpt.SetOptionText('{"matrix": {"x": {"data": ["a", "b"]}, "y": {"data": ["p"]},'
    + ' "body": {"data": [{"coord": [[-1, 0], 0], "mergeCells": true, "value": "x"}]}}}');
  m := TTyMatrix.Create(FOpt, 0);
  list := TTyPaintList.Create;
  try
    m.Resize(TyRectF(0, 0, cW, cH), 96);
    bc := m.CellMap(0);
    AssertEquals('one merge', 1, bc.OwnerCount);
    c := bc.Cell(bc.Owner(0));
    AssertEquals('its top-left is the header level', -1, c.X);
    m.Dims[1].UnitOf(0, -1, lx, lw);
    m.Dims[0].UnitOf(0, 0, bx, bw);
    AssertTrue('the span starts at the level', SameBits(c.SpanRect.X, lx));
    AssertTrue('and ends with the first leaf', SameBits(c.SpanRect.W, bx + bw - lx));
    g := Default(TTyRtGlobal);
    g.FontFamily := 'sans-serif';
    g.FontSizeLogical := TyFontSizeFromPx(12);
    g.FontWeight := 400;
    AssertTrue('the picture is built', TyBuildMatrix(m, TestInk, g, nil, 96, list) > 0);
    m.DataToLayoutXYWH(0, 0, r);
    AssertTrue('dataToLayout of the leaf expands into the level', SameBits(r.X, lx));
    m.DataToLayoutRange([0], [0], mclNone, r, loc, True);
    AssertTrue('ignoreMergeCells keeps the leaf', SameBits(r.X, bx));
  finally
    list.Free;
    m.Free;
  end;
end;

{ ONE ITEM MUST NOT FILL TEN BILLION CELLS, nor twenty thousand merges take
  the square of their count: the writes and the uniting are bounded }
procedure TAdvChartMatrix3AlgebraTest.TestHostileItemsAreBounded;
var
  sb: TStringBuilder;
  i: Integer;
  m: TTyMatrix;
  bc: TTyMatrixBodyCorner;
  r: TTyXYWH;
begin
  sb := TStringBuilder.Create;
  try
    sb.Append('{"matrix": {"x": {"length": 3000}, "y": {"length": 3000}, "body": {"data": [');
    sb.Append('{"coord": [null, null], "coordClamp": true, "mergeCells": true}');
    for i := 0 to 19999 do
      sb.Append(Format(', {"coord": [%d, %d], "mergeCells": true}', [i mod 3000, i div 3000]));
    sb.Append(']}}}');
    FOpt.SetOptionText(sb.ToString);
  finally
    sb.Free;
  end;
  m := TTyMatrix.Create(FOpt, 0);
  try
    m.Resize(TyRectF(0, 0, cW, cH), 96);
    bc := m.CellMap(0);
    AssertEquals('the whole-body item writes nothing, every single cell is there', 20000, bc.Count);
    AssertTrue(Format('the merges stop uniting past the bound (%d)', [bc.OwnerCount]),
      (bc.OwnerCount > 1000) and (bc.OwnerCount < 20000));
    m.DataToLayoutXYWH(5, 5, r);
    AssertFalse('a lookup still answers', IsNan(r.X));
  finally
    m.Free;
  end;
end;

{ ==================== the control ==================== }

procedure TAdvChartMatrix3ChartTest.SetUp;
var m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TMx3Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  FMirror := TMx3Mirror.Create;
  FFmt := TMx3Formatters.Create;
  RegisterAll(FFmt, FMirror);
  FBad := 0;
  FCompared := 0;
  FCount := 0;
  FReport := '';
end;

procedure TAdvChartMatrix3ChartTest.TearDown;
begin
  UnregisterAll;
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FRoot);
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  FMirror.Free;
  FFmt.Free;
  inherited TearDown;
end;

procedure TAdvChartMatrix3ChartTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMatrix3ChartTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if not SameBits(AGot, H(AWant)) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(H(AWant))]));
end;

function TAdvChartMatrix3ChartTest.CaseOf(const AId: string): TJSONObject;
var
  cases: TJSONArray;
  c: Integer;
begin
  Result := nil;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
    if cases.Objects[c].Strings['id'] = AId then Exit(cases.Objects[c]);
end;

procedure TAdvChartMatrix3ChartTest.RenderNow;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartMatrix3ChartTest.Draw(ACase: TJSONObject);
var opt: TJSONObject;
begin
  opt := TJSONObject(ACase.Objects['option'].Clone);
  try
    opt.Booleans['animation'] := False;
    FChart.SetBounds(0, 0, cW, cH);
    FChart.TooltipNow := 0;
    FMirror.Answers.Clear;
    FChart.Option := '{}';
    FChart.Option := opt.AsJSON;
    RenderNow;
  finally
    opt.Free;
  end;
end;

procedure TAdvChartMatrix3ChartTest.CheckCall(ACall: TJSONObject);
var
  fn, w: string;
  ret, rc: TJSONData;
  cv: TTyConvertResult;
  lay: TTyConvertLayout;
  k: Integer;
begin
  fn := ACall.Strings['fn'];
  w := Format('%s %s %s %s', [fn, ACall.Find('finder').AsJSON, ACall.Find('value').AsJSON,
    ACall.Find('opt').AsJSON]);
  ret := ACall.Find('ret');
  Inc(FCount);
  if fn = 'toLayout' then
  begin
    lay := FChart.ConvertToLayoutData(ACall.Find('finder'), ACall.Find('value'), ACall.Find('opt'));
    Inc(FCompared);
    if not lay.Valid then
    begin
      Miss(w + ': no answer here');
      Exit;
    end;
    rc := TJSONObject(ret).Find('rect');
    SameH(w + ' x', lay.Rect.X, TJSONObject(rc).Find('x'));
    SameH(w + ' y', lay.Rect.Y, TJSONObject(rc).Find('y'));
    SameH(w + ' width', lay.Rect.W, TJSONObject(rc).Find('width'));
    SameH(w + ' height', lay.Rect.H, TJSONObject(rc).Find('height'));
    rc := TJSONObject(ret).Find('loc');
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
  if (cv.Kind <> cvkArray) or (Length(cv.Values) <> ret.Count) then
  begin
    Miss(Format('%s: kind %d, %d values here', [w, Ord(cv.Kind), Length(cv.Values)]));
    Exit;
  end;
  for k := 0 to ret.Count - 1 do
    SameH(Format('%s [%d]', [w, k]), cv.Values[k], TJSONArray(ret).Items[k]);
end;

{ heatmap and scatter rows in merged cells, the custom series' answers,
  the pies }
procedure TAdvChartMatrix3ChartTest.TestTheSeriesInMergedCellsAsUpstream;
var
  cs, se, row, sh, sj, a, ret: TJSONObject;
  series, rows, cus, calls, api, ps, secs: TJSONArray;
  s, j, k, q, si, at, n: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  b: TTyRectF;
  heat, found: Boolean;
  want, w: string;
  view: TTyCustomView;
begin
  cs := CaseOf('series-merged');
  AssertNotNull('the series case', cs);
  FName := 'series-merged';
  Draw(cs);
  lst := FChart.List;
  { the heatmap and the scatter }
  series := cs.Arrays['series'];
  for s := 0 to series.Count - 1 do
  begin
    se := series.Objects[s];
    si := se.Integers['seriesIndex'];
    heat := se.Strings['type'] = 'heatmap';
    rows := se.Arrays['rows'];
    for j := 0 to rows.Count - 1 do
    begin
      row := rows.Objects[j];
      w := Format('series %d row %d', [si, j]);
      found := False;
      for k := 0 to lst.Count - 1 do
      begin
        e := lst.Element(k);
        if (e.Datum.Kind <> ctkSeries) or (e.Datum.SeriesIndex <> si)
          or (e.Datum.DataIndex <> row.Integers['index']) or (e.Caption.Text <> '') then Continue;
        found := True;
        Inc(FCount);
        if heat then
        begin
          sh := row.Objects['shape'];
          SameH(w + ' x', e.Shape.Bounds.Left, sh.Find('x'));
          SameH(w + ' y', e.Shape.Bounds.Top, sh.Find('y'));
          Inc(FCompared, 2);
          if not SameBits(e.Shape.Bounds.Right, H(sh.Find('x')) + H(sh.Find('width'))) then
            Miss(w + ': the right edge differs');
          if not SameBits(e.Shape.Bounds.Bottom, H(sh.Find('y')) + H(sh.Find('height'))) then
            Miss(w + ': the bottom edge differs');
        end
        else
        begin
          b := TyShapeBounds(e.Shape);
          Inc(FCompared, 2);
          if (Abs((b.Left + b.Right) / 2 - H(row.Arrays['point'].Items[0])) > 1e-9)
            or (Abs((b.Top + b.Bottom) / 2 - H(row.Arrays['point'].Items[1])) > 1e-9) then
            Miss(Format('%s: a symbol at (%s, %s) here', [w, Fmt((b.Left + b.Right) / 2),
              Fmt((b.Top + b.Bottom) / 2)]));
        end;
        Break;
      end;
      Inc(FCompared);
      if found <> row.Booleans['drawn'] then Miss(w + ': drawn differs');
    end;
  end;
  { the custom series: every api answer in order }
  cus := cs.Arrays['custom'];
  at := 0;
  for k := 0 to cus.Count - 1 do
  begin
    sj := cus.Objects[k];
    si := sj.Integers['seriesIndex'];
    calls := sj.Arrays['calls'];
    for j := 0 to calls.Count - 1 do
    begin
      api := calls.Objects[j].Arrays['api'];
      for q := 0 to api.Count - 1 do
      begin
        a := api.Objects[q];
        w := Format('series %d call %d api %d', [si, j, q]);
        Inc(FCompared);
        Inc(FCount);
        if a.Strings['fn'] = 'coord' then
          want := 'coord ' + TJSONArray(a.Find('ret')).Strings[0] + ' '
            + TJSONArray(a.Find('ret')).Strings[1]
        else
        begin
          ret := a.Objects['ret'];
          want := 'layout ' + ret.Objects['rect'].Strings['x'] + ' ' + ret.Objects['rect'].Strings['y']
            + ' ' + ret.Objects['rect'].Strings['width'] + ' ' + ret.Objects['rect'].Strings['height'];
          for n := 0 to 3 do
            want := want + ' ' + ret.Arrays['matrixXYLocatorRange'].Arrays[n div 2].Strings[n mod 2];
        end;
        if at >= FMirror.Answers.Count then
        begin
          Miss(w + ': no answer here');
          Continue;
        end;
        if FMirror.Answers[at] <> want then
          Miss(Format('%s: "%s" here, "%s" upstream', [w, FMirror.Answers[at], want]));
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
  { the pies }
  ps := cs.Arrays['pies'];
  for k := 0 to ps.Count - 1 do
  begin
    si := ps.Objects[k].Integers['seriesIndex'];
    secs := ps.Objects[k].Arrays['sectors'];
    for j := 0 to secs.Count - 1 do
    begin
      sj := secs.Objects[j];
      w := Format('pie %d sector %d', [si, j]);
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
      Inc(FCompared);
      if not found then Miss(w + ': no sector here');
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the rows, answers and sectors were compared (%d)', [FCount]), FCount >= 23);
end;

procedure TAdvChartMatrix3ChartTest.TestTheConversionsAsUpstream;
var
  cs: TJSONObject;
  calls: TJSONArray;
  k: Integer;
begin
  cs := CaseOf('series-merged');
  AssertNotNull('the series case', cs);
  FName := 'series-merged';
  Draw(cs);
  calls := cs.Arrays['calls'];
  for k := 0 to calls.Count - 1 do CheckCall(calls.Objects[k]);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the calls were made (%d)', [FCount]), FCount >= 8);
end;

{ upstream's event as the logger's line }
function WantEvent(E: TJSONObject): string;
var
  d: TJSONData;
  nm, v: string;
begin
  Result := E.Strings['type'] + ' ' + E.Get('componentType', '');
  nm := '';
  d := E.Find('name');
  if not IsNull(d) then nm := d.AsString;
  v := '';
  d := E.Find('value');
  if not IsNull(d) then v := d.AsString;
  Result := Result + Format(' %d %s name=%s value=%s', [E.Integers['componentIndex'],
    E.Strings['targetType'], nm, v]);
  d := E.Find('coord');
  if d is TJSONArray then
    Result := Result + Format(' [%s,%s]', [Fmt(TJSONArray(d).Floats[0]), Fmt(TJSONArray(d).Floats[1])]);
end;

procedure TAdvChartMatrix3ChartTest.TestThePointerAsUpstream;
var
  cs, st, hit, tip: TJSONObject;
  steps, states, evs: TJSONArray;
  lg: TMx2Logger;
  k, j, el, x, y, idOver, idOut: Integer;
  d: TTyChartDatumRef;
  info: TTyMatrixCellInfo;
  nowMs: Double;
  w, role: string;
begin
  cs := CaseOf('ptr-cells');
  AssertNotNull('the pointer case', cs);
  FName := 'ptr-cells';
  lg := TMx2Logger.Create;
  lg.Log := TStringList.Create;
  try
    idOver := FChart.ChartOn('mouseover', @lg.Handle);
    idOut := FChart.ChartOn('mouseout', @lg.Handle);
    Draw(cs);
    steps := cs.Arrays['steps'];
    states := cs.Arrays['states'];
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
      d := FChart.HitTestAt(x, y, el);
      Inc(FCompared);
      if IsNull(st.Find('hit')) then
      begin
        if el >= 0 then Miss(w + ': something hit here, nothing upstream');
      end
      else
      begin
        hit := st.Objects['hit'];
        if el < 0 then Miss(w + ': nothing hit here')
        else if (d.Kind <> ctkMatrix) or (d.ComponentIndex <> hit.Integers['matrixIndex']) then
          Miss(Format('%s: not matrix %d here', [w, hit.Integers['matrixIndex']]))
        else
        begin
          info := FChart.MatrixLayout(d.ComponentIndex).CellInfo(d.DataIndex);
          if FChart.List.Element(el).Caption.Text <> '' then role := 'label' else role := 'rect';
          if (info.Target <> hit.Strings['target']) or (role <> hit.Strings['role'])
            or (info.Loc[0] <> hit.Arrays['loc'].Integers[0])
            or (info.Loc[1] <> hit.Arrays['loc'].Integers[1]) then
            Miss(Format('%s: %s %s [%d,%d] here, %s %s %s upstream', [w, role, info.Target,
              info.Loc[0], info.Loc[1], hit.Strings['role'], hit.Strings['target'],
              hit.Arrays['loc'].AsJSON]));
        end;
      end;
      evs := st.Arrays['events'];
      Inc(FCompared);
      if lg.Log.Count <> evs.Count then
        Miss(Format('%s: %d events here (%s), %d upstream', [w, lg.Log.Count,
          StringReplace(lg.Log.Text, LineEnding, ' | ', [rfReplaceAll]), evs.Count]))
      else
        for j := 0 to evs.Count - 1 do
        begin
          Inc(FCompared);
          if lg.Log[j] <> WantEvent(evs.Objects[j]) then
            Miss(Format('%s event %d: "%s" here, "%s" upstream', [w, j, lg.Log[j],
              WantEvent(evs.Objects[j])]));
        end;
      tip := st.Objects['tooltip'];
      Inc(FCompared);
      if FChart.TooltipShown <> tip.Booleans['shown'] then
        Miss(Format('%s: tooltip shown %s here', [w, BoolToStr(FChart.TooltipShown, True)]))
      else if tip.Booleans['shown'] and not IsNull(tip.Find('text')) then
      begin
        Inc(FCompared);
        if FChart.TipText <> tip.Strings['text'] then
          Miss(Format('%s: tooltip "%s" here, "%s" upstream', [w, FChart.TipText,
            tip.Strings['text']]));
      end;
    end;
  finally
    FChart.ChartOff(idOver);
    FChart.ChartOff(idOut);
    lg.Log.Free;
    lg.Free;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the steps were taken (%d)', [FCount]), FCount >= 7);
end;

{ a later setOption's box written back (mergeLayoutParam on the model's
  option): the rect the merged option lays out }
procedure TAdvChartMatrix3ChartTest.TestTheBoxALaterOptionMergesAsUpstream;
var
  cases, opts: TJSONArray;
  cs, rc: TJSONObject;
  c, k: Integer;
  m: TTyMatrix;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Get('group', '') <> 'merge' then Continue;
    FName := cs.Strings['id'];
    opts := cs.Arrays['options'];
    FChart.SetBounds(0, 0, cW, cH);
    FChart.Option := '{}';
    for k := 0 to opts.Count - 1 do
      if k = 0 then FChart.Option := opts.Objects[k].AsJSON
      else FChart.MergeOption(opts.Objects[k].AsJSON);
    RenderNow;
    Inc(FCount);
    m := FChart.MatrixLayout(0);
    Inc(FCompared);
    if m = nil then
    begin
      Miss('no matrix');
      Continue;
    end;
    rc := cs.Arrays['matrices'].Objects[0].Objects['rect'];
    SameH('rect x', m.Rect.X, rc.Find('x'));
    SameH('rect y', m.Rect.Y, rc.Find('y'));
    SameH('rect width', m.Rect.W, rc.Find('width'));
    SameH('rect height', m.Rect.H, rc.Find('height'));
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('the merges were replayed (%d)', [FCount]), FCount >= 4);
end;

initialization
  RegisterTest(TAdvChartMatrix3ViewTest);
  RegisterTest(TAdvChartMatrix3AlgebraTest);
  RegisterTest(TAdvChartMatrix3ChartTest);
end.
