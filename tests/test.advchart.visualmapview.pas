unit test.advchart.visualmapview;
{$mode objfpc}{$H+}
{ A continuous visualMap's own picture -- where its bar, texts, handles and
  background land -- held to what ECharts 6.1 draws.

  tools/advchart-oracle/visualmap-view.js runs the real build and records
  per component: the item alignment it derived, the bar group's matrix, the
  interval and the handle ends, both bars' points and gradient stops, the end
  texts and the handle labels with their rects, each handle thumb's matrix
  and rects, the background, the two bounding rects the view reads (one for
  the background, one to place the group) and where the group went.

  EXACT: every number bit for bit (a negative nought counts as nought), every
  colour as zrender holds it. Texts are measured by a table of the fixture's
  own zrender measurements -- the widths are the oracle's, the arithmetic
  with them is the port's. The options get upstream's content and inactive
  colours written in, since those are the skin's here. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Layout, tyControls.AdvChart.VisualMap,
     tyControls.AdvChart.VisualMapView, tyControls.AdvanceChart;
type
  TVmvMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    Names: TStringList;
    W, H: array of Double;
    Missed: string;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string; AW, AH: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TVmvProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartVisualMapViewOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TVmvProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FMeas: TVmvMeasurer;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Rect(const AWhat: string; const AGot: TTyXYWH; ARec: TJSONObject);
    procedure Mat(const AWhat: string; const AGot: TTyMat2D; AArr: TJSONArray);
    procedure CheckText(const AWhat: string; const AGot: TTyVmText; ARec: TJSONObject;
      AGlobalX, AGlobalY: Double);
    procedure CheckStops(const AWhat: string; const AGot: TTyVisualGradStopArray;
      AStops: TJSONArray);
    procedure CheckView(AIndex: Integer; AVm: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryComponentAsUpstreamLaysItOut;
    procedure TestTheDefaultHandleIconFitsAsZrenderFitsIt;
  end;

implementation

{ ---- the measurer ---- }

constructor TVmvMeasurer.Create;
begin
  inherited Create;
  Names := TStringList.Create;
end;

destructor TVmvMeasurer.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

procedure TVmvMeasurer.Add(const AText: string; AW, AH: Double);
var k: Integer;
begin
  if Names.IndexOf(AText) >= 0 then Exit;
  k := Names.Add(AText);
  SetLength(W, k + 1);
  SetLength(H, k + 1);
  W[k] := AW;
  H[k] := AH;
end;

procedure TVmvMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var k: Integer;
begin
  k := Names.IndexOf(AText);
  if k < 0 then
  begin
    if Pos('"' + AText + '"', Missed) = 0 then
      Missed := Missed + ' "' + AText + '"';
    AW := 0;
    AH := 12;
    Exit;
  end;
  AW := W[k];
  AH := H[k];
end;

function TVmvMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

{ ---- the probe ---- }

function TVmvProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Exit(Measurer);
  Result := inherited NewTextMeasurer(APPI);
end;

procedure TVmvProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TVmvProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ---- helpers ---- }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-visualmap-view.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

{ bit for bit, but -0 and 0 are one }
function SameNum(A: Double; const AHex: string): Boolean;
var b: Double;
begin
  b := FromHex(AHex);
  if IsNan(A) or IsNan(b) then Exit(IsNan(A) and IsNan(b));
  if (A = 0) and (b = 0) then Exit(True);
  Result := Bits(A) = Bits(b);
end;

function SameColour(const C: TTyVisualColor; AObj: TJSONObject): Boolean;
begin
  if AObj.Booleans['undef'] then Exit(not C.Defined);
  Result := C.Defined and (C.R = AObj.Integers['r'])
    and (C.G = AObj.Integers['g']) and (C.B = AObj.Integers['b'])
    and SameNum(C.A, AObj.Strings['a']);
end;

function HText(A: TTyTextAnchorH): string;
begin
  case A of
    tahRight: Result := 'right';
    tahCentre: Result := 'center';
  else
    Result := 'left';
  end;
end;

function VText(A: TTyTextAnchorV): string;
begin
  case A of
    tavBottom: Result := 'bottom';
    tavMiddle: Result := 'middle';
  else
    Result := 'top';
  end;
end;

procedure TAdvChartVisualMapViewOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartVisualMapViewOracleTest.Num(const AWhat: string;
  AGot: Double; const AHex: string);
begin
  Inc(FCompared);
  if not SameNum(AGot, AHex) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartVisualMapViewOracleTest.Rect(const AWhat: string;
  const AGot: TTyXYWH; ARec: TJSONObject);
begin
  Inc(FCompared);
  if not (SameNum(AGot.X, ARec.Strings['x']) and SameNum(AGot.Y, ARec.Strings['y'])
    and SameNum(AGot.W, ARec.Strings['width'])
    and SameNum(AGot.H, ARec.Strings['height'])) then
    Miss(Format('%s: %s,%s %sx%s upstream, %s,%s %sx%s here', [AWhat,
      Fmt(FromHex(ARec.Strings['x'])), Fmt(FromHex(ARec.Strings['y'])),
      Fmt(FromHex(ARec.Strings['width'])), Fmt(FromHex(ARec.Strings['height'])),
      Fmt(AGot.X), Fmt(AGot.Y), Fmt(AGot.W), Fmt(AGot.H)]));
end;

procedure TAdvChartVisualMapViewOracleTest.Mat(const AWhat: string;
  const AGot: TTyMat2D; AArr: TJSONArray);
var k: Integer; ok: Boolean;
begin
  Inc(FCompared);
  ok := True;
  for k := 0 to 5 do
    if not SameNum(AGot[k], AArr.Strings[k]) then ok := False;
  if not ok then
    Miss(Format('%s: [%s %s %s %s %s %s] upstream, [%s %s %s %s %s %s] here',
      [AWhat, Fmt(FromHex(AArr.Strings[0])), Fmt(FromHex(AArr.Strings[1])),
       Fmt(FromHex(AArr.Strings[2])), Fmt(FromHex(AArr.Strings[3])),
       Fmt(FromHex(AArr.Strings[4])), Fmt(FromHex(AArr.Strings[5])),
       Fmt(AGot[0]), Fmt(AGot[1]), Fmt(AGot[2]), Fmt(AGot[3]), Fmt(AGot[4]),
       Fmt(AGot[5])]));
end;

procedure TAdvChartVisualMapViewOracleTest.CheckText(const AWhat: string;
  const AGot: TTyVmText; ARec: TJSONObject; AGlobalX, AGlobalY: Double);
var lst: TTyPaintList; k, found: Integer; e: TTyChartElement;
begin
  Inc(FCompared);
  if AGot.Text <> ARec.Strings['string'] then
  begin
    Miss(Format('%s: "%s" upstream, "%s" here', [AWhat, ARec.Strings['string'], AGot.Text]));
    Exit;
  end;
  Num(AWhat + ' x', AGot.X, ARec.Strings['x']);
  Num(AWhat + ' y', AGot.Y, ARec.Strings['y']);
  Inc(FCompared);
  if (HText(AGot.AlignH) <> ARec.Strings['align'])
    or (VText(AGot.AlignV) <> ARec.Strings['verticalAlign']) then
    Miss(Format('%s: %s/%s upstream, %s/%s here', [AWhat, ARec.Strings['align'],
      ARec.Strings['verticalAlign'], HText(AGot.AlignH), VText(AGot.AlignV)]));
  Rect(AWhat + ' rect', AGot.Rect, ARec.Objects['rect']);
  { AND DRAWN THERE: a caption with these words at the global point }
  if AGot.Text = '' then Exit;
  lst := FChart.List;
  found := 0;
  if lst <> nil then
    for k := 0 to lst.Count - 1 do
    begin
      e := lst.Element(k);
      if (e.Caption.Text = AGot.Text) and SameNum(e.Caption.X, ARec.Strings['gx'])
        and SameNum(e.Caption.Y, ARec.Strings['gy']) then Inc(found);
    end;
  Inc(FCompared);
  if found = 0 then
    Miss(Format('%s: no caption "%s" drawn at %s,%s', [AWhat, AGot.Text,
      ARec.Strings['gxText'], ARec.Strings['gyText']]));
end;

procedure TAdvChartVisualMapViewOracleTest.CheckStops(const AWhat: string;
  const AGot: TTyVisualGradStopArray; AStops: TJSONArray);
var k: Integer;
begin
  Inc(FCompared);
  if Length(AGot) <> AStops.Count then
  begin
    Miss(Format('%s: %d stops upstream, %d here', [AWhat, AStops.Count, Length(AGot)]));
    Exit;
  end;
  for k := 0 to AStops.Count - 1 do
    if not (SameNum(AGot[k].Offset, AStops.Objects[k].Strings['offset'])
      and SameColour(AGot[k].Color, AStops.Objects[k].Objects['color'])) then
    begin
      Miss(Format('%s stop %d: %s %s upstream, %s (%s,%s,%s,%s) here', [AWhat, k,
        AStops.Objects[k].Strings['offsetText'],
        AStops.Objects[k].Objects['color'].Strings['css'], Fmt(AGot[k].Offset),
        Fmt(AGot[k].Color.R), Fmt(AGot[k].Color.G), Fmt(AGot[k].Color.B),
        Fmt(AGot[k].Color.A)]));
      Exit;
    end;
end;

procedure TAdvChartVisualMapViewOracleTest.CheckView(AIndex: Integer;
  AVm: TJSONObject);
var
  L: TTyVisualMapLayout;
  res, v, bar: TJSONObject;
  pts, hs, tx: TJSONArray;
  k: Integer;
  gx, gy: Double;

  procedure Points(const AWhat: string; const AGot: TTyPointFArray; AArr: TJSONArray);
  var i: Integer;
  begin
    Inc(FCompared);
    if Length(AGot) <> AArr.Count then
    begin
      Miss(Format('%s: %d points upstream, %d here', [AWhat, AArr.Count, Length(AGot)]));
      Exit;
    end;
    for i := 0 to AArr.Count - 1 do
    begin
      Num(Format('%s point %d x', [AWhat, i]), AGot[i].X, AArr.Arrays[i].Strings[0]);
      Num(Format('%s point %d y', [AWhat, i]), AGot[i].Y, AArr.Arrays[i].Strings[1]);
    end;
  end;

begin
  L := FChart.VisualMapLayout(AIndex);
  Inc(FCompared);
  if not AVm.Booleans['show'] then
  begin
    if L.Valid then Miss('shown here, hidden upstream');
    Exit;
  end;
  if not L.Valid then
  begin
    Miss('not laid out here');
    Exit;
  end;
  res := AVm.Objects['resolved'];
  v := AVm.Objects['view'];
  Inc(FCompared);
  if L.ItemAlign <> res.Strings['itemAlignDerived'] then
    Miss(Format('item align %s upstream, %s here', [res.Strings['itemAlignDerived'],
      L.ItemAlign]));
  Num('interval 0', L.Interval[0], res.Arrays['interval'].Strings[0]);
  Num('interval 1', L.Interval[1], res.Arrays['interval'].Strings[1]);
  Num('handle end 0', L.HandleEnds[0], res.Arrays['handleEnds'].Strings[0]);
  Num('handle end 1', L.HandleEnds[1], res.Arrays['handleEnds'].Strings[1]);
  bar := v.Objects['bar'];
  Mat('bar matrix', L.Bar, bar.Arrays['toGroup']);
  Points('out of range', L.OutPoints, v.Objects['outOfRange'].Arrays['points']);
  Points('in range', L.InPoints, v.Objects['inRange'].Arrays['points']);
  { and their rects, from the float32 path data: the gradient's own box }
  Rect('out of range rect', L.OutRect, v.Objects['outOfRange'].Objects['rect']);
  Rect('in range rect', L.InRect, v.Objects['inRange'].Objects['rect']);
  CheckStops('out of range', L.OutStops,
    v.Objects['outOfRange'].Objects['fill'].Arrays['stops']);
  CheckStops('in range', L.InStops,
    v.Objects['inRange'].Objects['fill'].Arrays['stops']);
  Rect('sketch rect', L.BBoxBackground, v.Objects['bboxBackground'].Objects['rect']);
  Rect('background', L.Background, v.Objects['background'].Objects['shape']);
  Rect('placing rect', L.BBoxPosition, v.Objects['bboxPosition'].Objects['rect']);
  Num('group x', L.GroupX, v.Objects['group'].Strings['x']);
  Num('group y', L.GroupY, v.Objects['group'].Strings['y']);
  gx := L.GroupX;
  gy := L.GroupY;
  tx := nil;
  if (v.Find('texts') <> nil) and (v.Find('texts').JSONType = jtArray) then
    tx := v.Arrays['texts'];
  Inc(FCompared);
  if tx = nil then
  begin
    if Length(L.Texts) > 0 then Miss('end texts here, none upstream');
  end
  else if Length(L.Texts) <> tx.Count then
    Miss(Format('%d end texts upstream, %d here', [tx.Count, Length(L.Texts)]))
  else
    for k := 0 to tx.Count - 1 do
      CheckText(Format('end text %d', [tx.Objects[k].Integers['end']]),
        L.Texts[tx.Objects[k].Integers['end']], tx.Objects[k], gx, gy);
  hs := nil;
  if (v.Find('handles') <> nil) and (v.Find('handles').JSONType = jtArray) then
    hs := v.Arrays['handles'];
  Inc(FCompared);
  if hs = nil then
  begin
    if Length(L.Handles) > 0 then Miss('handles here, none upstream');
  end
  else if Length(L.Handles) <> hs.Count then
    Miss(Format('%d handles upstream, %d here', [hs.Count, Length(L.Handles)]))
  else
    for k := 0 to hs.Count - 1 do
    begin
      Mat(Format('handle %d matrix', [k]), L.Handles[k].Thumb,
        hs.Objects[k].Objects['thumb'].Arrays['toGroup']);
      Rect(Format('handle %d icon', [k]), L.Handles[k].PathRect,
        hs.Objects[k].Objects['thumb'].Objects['pathRect']);
      Rect(Format('handle %d rect', [k]), L.Handles[k].Rect,
        hs.Objects[k].Objects['thumb'].Objects['rect']);
      Inc(FCompared);
      if not SameColour(L.Handles[k].Fill, hs.Objects[k].Objects['thumb'].Objects['fill']) then
        Miss(Format('handle %d fill', [k]));
      CheckText(Format('handle %d label', [k]), L.Handles[k].Label_,
        hs.Objects[k].Objects['label'], gx, gy);
    end;
  pts := nil;
  if pts <> nil then;
end;

{ ---- the tests ---- }

procedure TAdvChartVisualMapViewOracleTest.SetUp;
var sl: TStringList; ms: TJSONArray; k: Integer; m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TVmvProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FMeas := TVmvMeasurer.Create;
  FChart.Measurer := FMeas;
  ms := TJSONObject(FRoot).Arrays['measure'];
  for k := 0 to ms.Count - 1 do
  begin
    m := ms.Objects[k];
    FMeas.Add(m.Strings['string'], FromHex(m.Strings['width']),
      FromHex(m.Strings['height']));
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartVisualMapViewOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  if FChart <> nil then FChart.Measurer := nil;
  FChart := nil;
  FMeas := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartVisualMapViewOracleTest.TestEveryComponentAsUpstreamLaysItOut;
const
  cPalette = '["#5070dd","#b6d634","#505372","#ff994d","#0ca8df","#ffd10a",'
    + '"#fb628b","#785db0","#3fbe95"]';
var
  cases, vms: TJSONArray;
  cs, opt, vm: TJSONObject;
  d: TJSONData;
  c, k: Integer;

  procedure Upstream(AVm: TJSONObject);
  begin
    if AVm.Find('contentColor') = nil then AVm.Add('contentColor', '#5070dd');
    if AVm.Find('inactiveColor') = nil then AVm.Add('inactiveColor', '#cfd2d7');
  end;

begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FName := cs.Strings['id'];
    opt := TJSONObject(cs.Objects['option'].Clone);
    try
      if opt.Find('color') = nil then opt.Add('color', GetJSON(cPalette));
      if opt.Find('gradientColor') = nil then
        opt.Add('gradientColor', GetJSON('["rgba(212,220,247,1)","#5070dd"]'));
      d := opt.Find('visualMap');
      if (d <> nil) and (d.JSONType = jtObject) then Upstream(TJSONObject(d))
      else if (d <> nil) and (d.JSONType = jtArray) then
        for k := 0 to TJSONArray(d).Count - 1 do
          if TJSONArray(d).Items[k].JSONType = jtObject then
            Upstream(TJSONObject(TJSONArray(d).Items[k]));
      FChart.Option := opt.AsJSON;
      AssertEquals(FName + ' parses', '', FChart.OptionError);
      FChart.SetBounds(0, 0, 800, 600);
      try
        FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Continue;
        end;
      end;
      vms := cs.Arrays['visualMaps'];
      for k := 0 to vms.Count - 1 do
      begin
        vm := vms.Objects[k];
        if vm.Strings['subType'] <> 'continuous' then Continue;
        FName := cs.Strings['id'] + ' vm' + IntToStr(vm.Integers['index']);
        CheckView(vm.Integers['index'], vm);
      end;
    finally
      opt.Free;
    end;
  end;
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > 800);
end;

procedure TAdvChartVisualMapViewOracleTest.TestTheDefaultHandleIconFitsAsZrenderFitsIt;
var r: TTyXYWH; box: TTyXYWH;
begin
  { V7: handleSize 120% of 20 -- the pill fitted into 24 x 24, float32 }
  box.X := -12; box.Y := -12; box.W := 24; box.H := 24;
  r := TyVmIconRect(TyVmDefaultHandleIcon, box);
  AssertTrue('x -12: ' + Fmt(r.X), SameNum(r.X, 'c028000000000000'));
  AssertTrue('y: ' + Fmt(r.Y), SameNum(r.Y, 'c0072c2380000000'));
  AssertTrue('w 24: ' + Fmt(r.W), SameNum(r.W, '4038000000000000'));
  AssertTrue('h: ' + Fmt(r.H), SameNum(r.H, '40172c2380000000'));
end;

initialization
  RegisterTest(TAdvChartVisualMapViewOracleTest);
end.
