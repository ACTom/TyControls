unit test.advchart.lines;
{$mode objfpc}{$H+}
{ The lines series -- held to upstream to the bit [Batch 121, C12].

  tools/advchart-oracle/lines.js runs the real ECharts 6.1 build through
  lines on a cartesian, a polar and a calendar and records: per series the
  count, whether it drew a large batch, the zlevel's motion blur a trail asks
  for, the view group's clip; per row the laid-out line (ends and control
  point, or the polyline's points), its style, the end symbols (type, place,
  turn, size, colour, opacity), the label (its words, x / y and origin, the
  point it hangs from, turn, alignment, opacity) and the effect symbol (type,
  z2, colour, the clip's life and delay); per animation frame the line's
  percent, the symbols and the label following it, and the effect symbol's
  place, turn and scale; per pointer step the element and the row under the
  pointer, the chart events, the tooltip's rows and every row's states; the
  legend's icons.

  The port is driven the same way -- SetOption, AnimTick on the same clock
  (T0 1700000000000: the effect's fractional delays round at the epoch's
  ulp), MouseMove / MouseLeave / DispatchAction -- and compared through
  LinesSolvedOf, the paint list, the animation proxies (the line's
  shape.percent, the effect's run), HitTestAt, the events, TooltipContent,
  ItemStates and LegendLayout. Every number to the bit; the values a frame
  derives from the line's percent (the symbols' place and size, the label's
  anchor and fade) are the ones the port derives from its own proxy, through
  the functions its frames use. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Shape, tyControls.AdvChart.Large,
     tyControls.AdvChart.States, tyControls.AdvChart.Events,
     tyControls.AdvChart.Symbol, tyControls.AdvChart.Data,
     tyControls.AdvChart.Tooltip, tyControls.AdvChart.Legend,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.Lines,
     tyControls.AdvanceChart;
type
  TLnProbe = class(TTyAdvanceChart)
  public
    Events: TStringList;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Cached(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Move(AX, AY: Integer);
    procedure Leave;
    function List: TTyPaintList;
    function Frame: TTyPaintList;
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
  end;

  TAdvChartLinesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLnProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameHex(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameColour(const AWhat: string; AGot: TTyChartColor; AWant: TJSONData);
    procedure NewChart(AMode: TTyChartAnimationMode);
    procedure RenderNow;
    function Cases(const AGroup: string): TJSONArray;
    function ElOf(ASeries, ARow: Integer; ARole: TTyChartAnimRole): Integer;
    function LabelOf(ASeries, ARow: Integer): Integer;
    procedure CheckSeries(ARec: TJSONObject);
    procedure CheckItem(ASeries: Integer; const ASol: TTyLinesSolved; AItem: TJSONObject);
    procedure CheckFrame(AFrame: TJSONObject);
    procedure CheckStep(AStep: TJSONObject; ALegend: Boolean);
    procedure CheckLegend(AWant: TJSONArray);
    procedure Finish(ACount: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheDrawingAsUpstream;
    procedure TestTheLargeBatchAsUpstream;
    procedure TestTheEffectFramesAsUpstream;
    procedure TestTheEnterFramesAsUpstream;
    procedure TestThePointerAsUpstream;
  end;

  { What the oracle does not reach. }
  TAdvChartLinesTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLnProbe;
    FBmp: TBGRABitmap;
    procedure Show(const AOption: string; AMode: TTyChartAnimationMode);
    procedure RenderNow;
    function CountRole(ARole: TTyChartAnimRole): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheDataForms;
    procedure TestTheLabelPlaceMatchesTheGraphsAtPercentOne;
    procedure TestTheEffectRunsWithAnimationOffAndStopsWhenNotLooping;
    procedure TestTheTrailLayerFades;
    procedure TestALargeBatchIsOneElementWithNoRow;
    procedure TestTheHookIsTheOnlyWayToAPoint;
    procedure TestTheLinesArePainted;
    procedure TestAnUpdateKeepsTheEffectRunning;
  end;

implementation

const
  T0 = 1700000000000.0;

{ ==================== helpers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-lines.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  System.Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function KindWord(AKind: TTySymbolKind): string;
begin
  case AKind of
    tsyCircle: Result := 'circle';
    tsyRect: Result := 'rect';
    tsyRoundRect: Result := 'roundRect';
    tsySquare: Result := 'square';
    tsyTriangle: Result := 'triangle';
    tsyDiamond: Result := 'diamond';
    tsyPin: Result := 'pin';
    tsyArrow: Result := 'arrow';
    tsyLine: Result := 'line';
    tsyNone: Result := 'none';
  else
    Result := 'path';
  end;
end;

function NameWord(const AName: string): string;
var em: Boolean; pd: string;
begin
  Result := KindWord(TySymbolKindOf(AName, em, pd));
end;

function AlignWordH(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahLeft: Result := 'left';
    tahCentre: Result := 'center';
  else
    Result := 'right';
  end;
end;

function AlignWordV(AV: TTyTextAnchorV): string;
begin
  case AV of
    tavTop: Result := 'top';
    tavMiddle: Result := 'middle';
  else
    Result := 'bottom';
  end;
end;

function StrOrNull(AData: TJSONData): string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Result := '<null>'
  else Result := AData.AsString;
end;

{ ==================== the probe ==================== }

constructor TLnProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Events := TStringList.Create;
end;

destructor TLnProbe.Destroy;
begin
  Events.Free;
  inherited Destroy;
end;

procedure TLnProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TLnProbe.Cached(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

procedure TLnProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TLnProbe.Leave;
begin
  MouseLeave;
end;

function TLnProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TLnProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

function TLnProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

procedure TLnProbe.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  Events.Add(Format('%s'#9'%d'#9'%d'#9'%s', [AEvent.EventType, AEvent.Params.SeriesIndex,
    AEvent.Params.DataIndex, AEvent.Params.Name]));
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartLinesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBmp := TBGRABitmap.Create(FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger,
    BGRA(255, 255, 255, 255));
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartLinesOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLinesOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 80 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLinesOracleTest.SameHex(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double; ok: Boolean;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) or IsNan(AGot) then ok := IsNan(want) and IsNan(AGot)
  else ok := AGot = want;
  if not ok then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartLinesOracleTest.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is "%s" upstream, "%s" here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartLinesOracleTest.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %d upstream, %d here', [AWhat, AWant, AGot]));
end;

procedure TAdvChartLinesOracleTest.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  SameStr(AWhat, BoolToStr(AGot, True), BoolToStr(AWant, True));
end;

procedure TAdvChartLinesOracleTest.SameColour(const AWhat: string;
  AGot: TTyChartColor; AWant: TJSONData);
var a: TJSONArray;
begin
  Inc(FCompared);
  if not (AWant is TJSONArray) then
  begin
    Miss(AWhat + ': no colour upstream');
    Exit;
  end;
  a := TJSONArray(AWant);
  if ((AGot shr 16) and $FF <> Cardinal(a.Integers[0]))
    or ((AGot shr 8) and $FF <> Cardinal(a.Integers[1]))
    or (AGot and $FF <> Cardinal(a.Integers[2]))
    or ((AGot shr 24) and $FF <> Cardinal(Round(a.Floats[3] * 255))) then
    Miss(Format('%s is rgba(%d,%d,%d,%s) upstream, $%.8x here', [AWhat,
      a.Integers[0], a.Integers[1], a.Integers[2], Fmt(a.Floats[3]), AGot]));
end;

procedure TAdvChartLinesOracleTest.NewChart(AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TLnProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, FRoot.FindPath('W').AsInteger, FRoot.FindPath('H').AsInteger);
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.ChartOn('mouseover', @FChart.OnEv);
  FChart.ChartOn('mousemove', @FChart.OnEv);
  FChart.ChartOn('mouseout', @FChart.OnEv);
end;

procedure TAdvChartLinesOracleTest.RenderNow;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FBmp.Width, FBmp.Height), 96);
end;

function TAdvChartLinesOracleTest.Cases(const AGroup: string): TJSONArray;
var all: TJSONArray; i: Integer;
begin
  Result := TJSONArray.Create;
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Strings['group'] = AGroup then
      Result.Add(all.Objects[i].Clone);
end;

{ the series' element of a role for a row, in the list as laid out }
function TAdvChartLinesOracleTest.ElOf(ASeries, ARow: Integer;
  ARole: TTyChartAnimRole): Integer;
var list: TTyPaintList; k: Integer; el: TTyChartElement;
begin
  Result := -1;
  list := FChart.List;
  if list = nil then Exit;
  for k := 0 to list.Count - 1 do
  begin
    el := list.Element(k);
    if (el.Datum.SeriesIndex = ASeries) and (el.Datum.DataIndex = ARow)
      and (el.Anim.Role = ARole) and (el.Caption.FontSizeLogical = 0) then
      Exit(k);
  end;
end;

function TAdvChartLinesOracleTest.LabelOf(ASeries, ARow: Integer): Integer;
var list: TTyPaintList; k: Integer; el: TTyChartElement;
begin
  Result := -1;
  list := FChart.List;
  if list = nil then Exit;
  for k := 0 to list.Count - 1 do
  begin
    el := list.Element(k);
    if (el.Datum.SeriesIndex = ASeries) and (el.Datum.DataIndex = ARow)
      and (el.Caption.FontSizeLogical > 0) then
      Exit(k);
  end;
end;

procedure TAdvChartLinesOracleTest.CheckItem(ASeries: Integer;
  const ASol: TTyLinesSolved; AItem: TJSONObject);
var
  k, e, idx, j: Integer;
  what: string;
  g: TTyLinesGeom;
  ink: TTyLinesInk;
  shp, st, lab, eff, sym: TJSONObject;
  syms, pts: TJSONArray;
  el: TTyChartElement;
  p: TTyPointF;
  x, y, ox, oy, rot, ax, ay: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  runSt: TTyLinesEffect;
begin
  k := AItem.Integers['dataIndex'];
  what := Format('series %d row %d', [ASeries, k]);
  if k > High(ASol.Geoms) then
  begin
    Miss(what + ': no row here');
    Exit;
  end;
  g := ASol.Geoms[k];
  ink := ASol.Inks[k];
  SameBool(what + ' drawn', g.Drawn, AItem.Booleans['drawn']);
  if not (AItem.Booleans['drawn'] and g.Drawn) then Exit;
  { the line }
  if AItem.Strings['kind'] = 'polyline' then
  begin
    SameBool(what + ' a polyline', ASol.Poly, True);
    pts := AItem.Arrays['points'];
    SameInt(what + ' points', Length(g.Pts) * 2, pts.Count);
    if Length(g.Pts) * 2 = pts.Count then
      for j := 0 to High(g.Pts) do
      begin
        SameHex(Format('%s point %d x', [what, j]), g.Pts[j].X, pts.Items[j * 2]);
        SameHex(Format('%s point %d y', [what, j]), g.Pts[j].Y, pts.Items[j * 2 + 1]);
      end;
    idx := -1;
    for j := 0 to FChart.List.Count - 1 do
      if (FChart.List.Element(j).Datum.SeriesIndex = ASeries)
        and (FChart.List.Element(j).Datum.DataIndex = k)
        and (FChart.List.Element(j).Shape.Kind = cskPolyline) then
      begin
        idx := j;
        Break;
      end;
  end
  else
  begin
    shp := AItem.Objects['shape'];
    SameHex(what + ' x1', g.Pts[0].X, shp.Find('x1'));
    SameHex(what + ' y1', g.Pts[0].Y, shp.Find('y1'));
    SameHex(what + ' x2', g.Pts[1].X, shp.Find('x2'));
    SameHex(what + ' y2', g.Pts[1].Y, shp.Find('y2'));
    if g.Curved then
    begin
      SameHex(what + ' cpx1', g.CP.X, shp.Find('cpx1'));
      SameHex(what + ' cpy1', g.CP.Y, shp.Find('cpy1'));
    end
    else
    begin
      SameHex(what + ' cpx1 (straight)', NaN, shp.Find('cpx1'));
      SameHex(what + ' cpy1 (straight)', NaN, shp.Find('cpy1'));
    end;
    idx := ElOf(ASeries, k, carLinesLine);
    if idx >= 0 then
    begin
      el := FChart.List.Element(idx);
      SameHex(what + ' line element x1', el.Anim.G[0], shp.Find('x1'));
      SameHex(what + ' line element y2', el.Anim.G[3], shp.Find('y2'));
    end;
  end;
  if idx < 0 then
  begin
    Miss(what + ': no line element');
    Exit;
  end;
  el := FChart.List.Element(idx);
  st := AItem.Objects['style'];
  SameColour(what + ' stroke', ink.Stroke, st.Find('stroke'));
  SameColour(what + ' element stroke', el.Style.StrokeColor, st.Find('stroke'));
  SameHex(what + ' line width', ink.Width, st.Find('lineWidth'));
  SameHex(what + ' element line width', el.Style.StrokeWidthLogical, st.Find('lineWidth'));
  SameHex(what + ' opacity', el.Style.Alpha, st.Find('opacity'));
  SameBool(what + ' dashed', Length(el.Style.DashLogical) > 0, st.Find('lineDash').JSONType <> jtNull);
  SameInt(what + ' z2', el.Z2, AItem.Integers['z2']);
  { the end symbols }
  syms := AItem.Arrays['symbols'];
  for j := 0 to syms.Count - 1 do
  begin
    sym := syms.Objects[j];
    if sym.Strings['name'] = 'fromSymbol' then e := 0 else e := 1;
    if e = 0 then idx := ElOf(ASeries, k, carLinesFrom) else idx := ElOf(ASeries, k, carLinesTo);
    if idx < 0 then
    begin
      Miss(Format('%s %s: no element', [what, sym.Strings['name']]));
      Continue;
    end;
    el := FChart.List.Element(idx);
    SameStr(what + ' ' + sym.Strings['name'] + ' type', KindWord(TTySymbolKind(Round(el.Anim.G[7]))),
      sym.Strings['symbolType']);
    if e = 0 then p := TyLinesPointAt(g, 0) else p := TyLinesPointAt(g, 1);
    SameHex(what + ' ' + sym.Strings['name'] + ' x', p.X, sym.Find('x'));
    SameHex(what + ' ' + sym.Strings['name'] + ' y', p.Y, sym.Find('y'));
    SameHex(what + ' ' + sym.Strings['name'] + ' rotation', el.Anim.G[11], sym.Find('rotation'));
    SameHex(what + ' ' + sym.Strings['name'] + ' rotation (the function)',
      TyLinesSymbolRotation(g, e = 1), sym.Find('rotation'));
    SameHex(what + ' ' + sym.Strings['name'] + ' width', el.Anim.G[8], sym.Arrays['box'].Items[2]);
    SameHex(what + ' ' + sym.Strings['name'] + ' height', el.Anim.G[9], sym.Arrays['box'].Items[3]);
    SameHex(what + ' ' + sym.Strings['name'] + ' opacity', el.Style.Alpha, sym.Find('opacity'));
    if el.Anim.G[10] <> 0 then
      SameColour(what + ' ' + sym.Strings['name'] + ' stroke', el.Style.StrokeColor, sym.Find('stroke'))
    else
      SameColour(what + ' ' + sym.Strings['name'] + ' fill', el.Style.FillColor, sym.Find('fill'));
  end;
  { no symbol here that upstream has not }
  SameInt(what + ' symbols', Ord(ElOf(ASeries, k, carLinesFrom) >= 0)
    + Ord(ElOf(ASeries, k, carLinesTo) >= 0), syms.Count);
  { the label }
  if AItem.Find('label').JSONType = jtObject then
  begin
    lab := AItem.Objects['label'];
    idx := LabelOf(ASeries, k);
    if lab.Strings['text'] = '' then
      SameBool(what + ' no label for no words', idx >= 0, False)
    else if idx < 0 then
      Miss(what + ': no label')
    else
    begin
      el := FChart.List.Element(idx);
      SameStr(what + ' label text', el.Caption.Text, lab.Strings['text']);
      SameHex(what + ' label anchor x', el.Caption.X, lab.Arrays['anchor'].Items[0]);
      SameHex(what + ' label anchor y', el.Caption.Y, lab.Arrays['anchor'].Items[1]);
      SameHex(what + ' label rotation', el.Caption.RotationRad, lab.Find('rotation'));
      SameStr(what + ' label align', AlignWordH(el.Caption.AnchorH), lab.Strings['align']);
      SameStr(what + ' label vertical align', AlignWordV(el.Caption.AnchorV), lab.Strings['verticalAlign']);
      SameHex(what + ' label opacity', el.Style.Alpha, lab.Find('opacity'));
      { x / y and the origin as Line.beforeUpdate sets them }
      TyLinesLabelPlace(g, 1, ink.LabelPos, ink.DistX, ink.DistY, x, y, ox, oy, rot,
        ax, ay, ah, av);
      SameHex(what + ' label x', x, lab.Find('x'));
      SameHex(what + ' label y', y, lab.Find('y'));
      SameHex(what + ' label origin x', ox, lab.Arrays['origin'].Items[0]);
      SameHex(what + ' label origin y', oy, lab.Arrays['origin'].Items[1]);
    end;
  end
  else
    SameBool(what + ' no label', LabelOf(ASeries, k) >= 0, False);
  { the effect symbol }
  idx := ElOf(ASeries, k, carLinesEffect);
  if AItem.Find('effect').JSONType <> jtObject then
  begin
    SameBool(what + ' no effect', idx >= 0, False);
    Exit;
  end;
  eff := AItem.Objects['effect'];
  if idx < 0 then
  begin
    Miss(what + ': no effect element');
    Exit;
  end;
  el := FChart.List.Element(idx);
  SameStr(what + ' effect type', NameWord(el.Anim.Mono), eff.Strings['symbolType']);
  SameInt(what + ' effect z2', el.Z2, eff.Integers['z2']);
  { a 'line' is stroked in the colour (symbolPathSetColor), the rest filled }
  if eff.Strings['symbolType'] = 'line' then
    SameColour(what + ' effect stroke', el.Style.StrokeColor, eff.Find('stroke'))
  else
    SameColour(what + ' effect fill', el.Style.FillColor, eff.Find('fill'));
  SameHex(what + ' effect opacity', el.Style.Alpha, eff.Find('opacity'));
  { the clip's life: the period, twice it for a round trip }
  if (Round(el.Anim.G[9]) and 2) <> 0 then
    SameHex(what + ' effect life', el.Anim.G[7] * 2, eff.Find('life'))
  else
    SameHex(what + ' effect life', el.Anim.G[7], eff.Find('life'));
  SameHex(what + ' effect delay', el.Anim.G[8], eff.Find('delay'));
  SameBool(what + ' effect loop', (Round(el.Anim.G[9]) and 1) <> 0, eff.Booleans['loop']);
  SameHex(what + ' effect scaleX (the size)', el.Anim.G[10], eff.Find('scaleX'));
  { where the clip's first step leaves it: __t 0 }
  TyLinesEffectOfElement(el, runSt);
  TyLinesEffectStep(runSt, 0);
  SameHex(what + ' effect x at 0', runSt.X, eff.Find('x'));
  SameHex(what + ' effect y at 0', runSt.Y, eff.Find('y'));
  SameHex(what + ' effect rotation at 0', runSt.Rotation, eff.Find('rotation'));
  SameHex(what + ' effect scaleY at 0', runSt.ScaleY, eff.Find('scaleY'));
end;

procedure TAdvChartLinesOracleTest.CheckSeries(ARec: TJSONObject);
var
  si, j: Integer;
  sol: TTyLinesSolved;
  mode, what: string;
  clip, el: TJSONObject;
  items, sh: TJSONArray;
  st: TTyDataStore;
  g: TTyLargeGeom;
  k: Integer;
  pair: TJSONArray;
  key: string;
begin
  si := ARec.Integers['seriesIndex'];
  what := Format('series %d', [si]);
  sol := FChart.LinesSolvedOf(si);
  mode := ARec.Strings['mode'];
  if mode = 'none' then
  begin
    SameBool(what + ' drawn', sol.Valid, False);
    Exit;
  end;
  SameBool(what + ' drawn', sol.Valid, True);
  if not sol.Valid then Exit;
  SameBool(what + ' large', sol.IsLarge, mode = 'large');
  st := FChart.SeriesStore(si);
  if st <> nil then SameInt(what + ' count', st.Count, ARec.Integers['count'])
  else Miss(what + ': no store');
  { the trail }
  if ARec.Find('trail').JSONType = jtNull then
    SameStr(what + ' no trail', Fmt(sol.TrailAlpha), '0')
  else
    SameHex(what + ' lastFrameAlpha', sol.TrailAlpha, ARec.Objects['trail'].Find('lastFrameAlpha'));
  { the clip }
  if ARec.Find('clip').JSONType = jtNull then
  begin
    SameBool(what + ' clip', sol.HasClip or sol.HasClipSector, False);
  end
  else
  begin
    clip := ARec.Objects['clip'];
    if clip.Strings['kind'] = 'rect' then
    begin
      SameBool(what + ' rect clip', sol.HasClip, True);
      SameHex(what + ' clip x', sol.Clip.Left, clip.Arrays['rect'].Items[0]);
      SameHex(what + ' clip y', sol.Clip.Top, clip.Arrays['rect'].Items[1]);
      SameHex(what + ' clip w', sol.Clip.Right - sol.Clip.Left, clip.Arrays['rect'].Items[2]);
      SameHex(what + ' clip h', sol.Clip.Bottom - sol.Clip.Top, clip.Arrays['rect'].Items[3]);
    end
    else
    begin
      SameBool(what + ' sector clip', sol.HasClipSector, True);
      sh := clip.Arrays['shape'];
      for j := 0 to sh.Count - 1 do
      begin
        pair := TJSONArray(sh.Items[j]);
        key := pair.Strings[0];
        if key = 'cx' then SameHex(what + ' clip cx', sol.ClipCX, pair.Items[1])
        else if key = 'cy' then SameHex(what + ' clip cy', sol.ClipCY, pair.Items[1])
        else if key = 'r' then SameHex(what + ' clip r', sol.ClipR1, pair.Items[1])
        else if key = 'r0' then SameHex(what + ' clip r0', sol.ClipR0, pair.Items[1])
        else if key = 'startAngle' then SameHex(what + ' clip start', sol.ClipSA, pair.Items[1])
        else if key = 'endAngle' then SameHex(what + ' clip end', sol.ClipEA, pair.Items[1])
        else if key = 'clockwise' then SameBool(what + ' clip clockwise', sol.ClipCW, pair.Booleans[1]);
      end;
    end;
  end;
  if mode = 'large' then
  begin
    SameInt(what + ' batches', Ord(sol.IsLarge), ARec.Arrays['els'].Count);
    if ARec.Arrays['els'].Count = 0 then Exit;
    el := ARec.Arrays['els'].Objects[0];
    g := sol.Large;
    SameInt(what + ' segs', Length(g.Pts), el.Arrays['segs'].Count);
    if Length(g.Pts) = el.Arrays['segs'].Count then
      for k := 0 to High(g.Pts) do
        SameHex(Format('%s seg %d', [what, k]), g.Pts[k], el.Arrays['segs'].Items[k]);
    SameBool(what + ' polyline batch', g.LinesPoly, el.Booleans['polyline']);
    SameHex(what + ' curveness', g.LinesCurve, el.Find('curveness'));
    SameHex(what + ' bbox x', g.Box.X, el.Arrays['bbox'].Items[0]);
    SameHex(what + ' bbox y', g.Box.Y, el.Arrays['bbox'].Items[1]);
    SameHex(what + ' bbox w', g.Box.W, el.Arrays['bbox'].Items[2]);
    SameHex(what + ' bbox h', g.Box.H, el.Arrays['bbox'].Items[3]);
    SameColour(what + ' batch stroke', sol.LargeStroke, el.Objects['style'].Find('stroke'));
    SameHex(what + ' batch width', g.LineW, el.Objects['style'].Find('lineWidth'));
    SameHex(what + ' batch opacity', sol.LargeOpacity, el.Objects['style'].Find('opacity'));
    SameBool(what + ' no startIndex', el.Find('startIndex').JSONType = jtNull, True);
    Exit;
  end;
  items := ARec.Arrays['items'];
  SameInt(what + ' rows', Length(sol.Geoms), items.Count);
  for j := 0 to items.Count - 1 do
    CheckItem(si, sol, items.Objects[j]);
end;

procedure TAdvChartLinesOracleTest.Finish(ACount: Integer);
begin
  WriteLn(Format('  lines oracle: %d comparisons over %d cases', [FCompared, ACount]));
  if FBad > 0 then
    Fail(Format('%d of %d comparisons over %d cases differ:%s',
      [FBad, FCompared, ACount, FReport]));
end;

procedure TAdvChartLinesOracleTest.TestTheDrawingAsUpstream;
var
  arr, series: TJSONArray;
  c: TJSONObject;
  i, j: Integer;
begin
  arr := Cases('draw');
  try
    for i := 0 to arr.Count - 1 do
    begin
      c := arr.Objects[i];
      FName := c.Strings['id'];
      NewChart(camOff);
      FChart.SetOption(c.Objects['option'].AsJSON, True);
      RenderNow;
      series := c.Objects['record'].Arrays['series'];
      for j := 0 to series.Count - 1 do CheckSeries(series.Objects[j]);
      if c.Find('legend').JSONType = jtArray then CheckLegend(c.Arrays['legend']);
      FreeAndNil(FChart);
    end;
    Finish(arr.Count);
    AssertTrue('compared', FCompared > 800);
  finally
    arr.Free;
  end;
end;

procedure TAdvChartLinesOracleTest.TestTheLargeBatchAsUpstream;
var
  arr, series: TJSONArray;
  c: TJSONObject;
  i, j: Integer;
begin
  arr := Cases('large');
  try
    for i := 0 to arr.Count - 1 do
    begin
      c := arr.Objects[i];
      FName := c.Strings['id'];
      NewChart(camOff);
      FChart.SetOption(c.Objects['option'].AsJSON, True);
      RenderNow;
      series := c.Objects['record'].Arrays['series'];
      for j := 0 to series.Count - 1 do CheckSeries(series.Objects[j]);
      for j := 0 to c.Arrays['steps'].Count - 1 do
      begin
        FName := c.Strings['id'] + '/' + IntToStr(j);
        FChart.TooltipNow := (j + 1) * 1000;
        FChart.Events.Clear;
        if c.Arrays['steps'].Objects[j].Strings['t'] = 'move' then
          FChart.Move(c.Arrays['steps'].Objects[j].Integers['x'],
            c.Arrays['steps'].Objects[j].Integers['y'])
        else
          FChart.Leave;
        FChart.TooltipTick((j + 1) * 1000 + 500);
        RenderNow;
        CheckStep(c.Arrays['steps'].Objects[j], False);
      end;
      FreeAndNil(FChart);
    end;
    Finish(arr.Count);
    AssertTrue('compared', FCompared > 100);
  finally
    arr.Free;
  end;
end;

{ one frame: the line's percent from its proxy and what it derives -- the
  symbols' place and scale, the label's anchor and fade; the effect symbol's
  run }
procedure TAdvChartLinesOracleTest.CheckFrame(AFrame: TJSONObject);
var
  items, syms: TJSONArray;
  it, sym, lab, eff: TJSONObject;
  j, s, k, e, idx: Integer;
  what: string;
  p: TTyChartAnimProxy;
  pct, x, y, ox, oy, rot, ax, ay: Double;
  sol: TTyLinesSolved;
  g: TTyLinesGeom;
  ink: TTyLinesInk;
  at: TTyPointF;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  runSt: TTyLinesEffect;
  el: TTyChartElement;
begin
  items := AFrame.Arrays['items'];
  for j := 0 to items.Count - 1 do
  begin
    it := items.Objects[j];
    s := it.Integers['seriesIndex'];
    k := it.Integers['dataIndex'];
    what := Format('t %s series %d row %d', [AFrame.Strings['t'], s, k]);
    sol := FChart.LinesSolvedOf(s);
    if (not sol.Valid) or (k > High(sol.Geoms)) then
    begin
      Miss(what + ': no row');
      Continue;
    end;
    g := sol.Geoms[k];
    ink := sol.Inks[k];
    pct := 1;
    if it.Find('line') <> nil then
    begin
      p := FChart.AnimFindProxy(s, k, 'linesLine');
      if p <> nil then pct := p.Num('shape.percent');
      SameHex(what + ' percent', pct, it.Objects['line'].Find('percent'));
    end;
    syms := it.Arrays['symbols'];
    for e := 0 to syms.Count - 1 do
    begin
      sym := syms.Objects[e];
      if sym.Strings['name'] = 'fromSymbol' then at := TyLinesPointAt(g, 0)
      else at := TyLinesPointAt(g, pct);
      SameHex(what + ' ' + sym.Strings['name'] + ' x', at.X, sym.Find('x'));
      SameHex(what + ' ' + sym.Strings['name'] + ' y', at.Y, sym.Find('y'));
      SameHex(what + ' ' + sym.Strings['name'] + ' scale', pct, sym.Find('scale'));
      SameHex(what + ' ' + sym.Strings['name'] + ' rotation',
        TyLinesSymbolRotation(g, sym.Strings['name'] = 'toSymbol'), sym.Find('rotation'));
    end;
    if (it.Find('label').JSONType = jtObject) and ink.LabelShow and (ink.LabelText <> '') then
    begin
      lab := it.Objects['label'];
      TyLinesLabelPlace(g, pct, ink.LabelPos, ink.DistX, ink.DistY, x, y, ox, oy, rot,
        ax, ay, ah, av);
      SameHex(what + ' label anchor x', ax, lab.Arrays['anchor'].Items[0]);
      SameHex(what + ' label anchor y', ay, lab.Arrays['anchor'].Items[1]);
      SameHex(what + ' label rotation', rot, lab.Find('rotation'));
      SameHex(what + ' label opacity', ink.Opacity * pct, lab.Find('opacity'));
      { and the frame draws it there }
      idx := LabelOf(s, k);
      if (idx >= 0) and (FChart.Frame <> nil) and (idx < FChart.Frame.Count) then
      begin
        el := FChart.Frame.Element(idx);
        if pct > 0 then
        begin
          SameHex(what + ' the frame label x', el.Caption.X, lab.Arrays['anchor'].Items[0]);
          SameHex(what + ' the frame label opacity', el.Style.Alpha, lab.Find('opacity'));
        end;
      end;
    end;
    if it.Find('effect').JSONType = jtObject then
    begin
      eff := it.Objects['effect'];
      p := FChart.AnimFindProxy(s, k, 'linesEffect');
      if p = nil then
      begin
        Miss(what + ': no effect proxy');
        Continue;
      end;
      SameBool(what + ' effect present', not p.LinesEffectGone, eff.Booleans['present']);
      if not eff.Booleans['present'] then Continue;
      runSt := p.LinesEffect;
      SameBool(what + ' effect ignore', runSt.Ignore, eff.Booleans['ignore']);
      SameHex(what + ' effect t', p.Num('__t'), eff.Find('t'));
      SameHex(what + ' effect x', runSt.X, eff.Find('x'));
      SameHex(what + ' effect y', runSt.Y, eff.Find('y'));
      SameHex(what + ' effect rotation', runSt.Rotation, eff.Find('rotation'));
      SameHex(what + ' effect scaleX', runSt.ScaleX, eff.Find('scaleX'));
      SameHex(what + ' effect scaleY', runSt.ScaleY, eff.Find('scaleY'));
    end;
  end;
end;

procedure TAdvChartLinesOracleTest.TestTheEffectFramesAsUpstream;
var
  arr, frames: TJSONArray;
  c, fr: TJSONObject;
  i, j: Integer;
  t: Double;
  sol: TTyLinesSolved;
begin
  arr := Cases('effect');
  try
    for i := 0 to arr.Count - 1 do
    begin
      c := arr.Objects[i];
      FName := c.Strings['id'];
      NewChart(camAlways);
      FChart.SetOption(c.Objects['option'].AsJSON, True);
      RenderNow;
      for j := 0 to c.Objects['record'].Arrays['series'].Count - 1 do
        CheckSeries(c.Objects['record'].Arrays['series'].Objects[j]);
      frames := c.Arrays['frames'];
      for j := 0 to frames.Count - 1 do
      begin
        fr := frames.Objects[j];
        t := fr.Floats['t'];
        if t > 0 then FChart.AnimTick(T0 + t);
        CheckFrame(fr);
      end;
      { the effect loops on: the chart never rests while one does }
      sol := FChart.LinesSolvedOf(c.Objects['record'].Arrays['series'].Objects[0].Integers['seriesIndex']);
      if sol.Valid and (Length(sol.Inks) > 0) and sol.Inks[0].EffLoop then
        SameBool('a looping effect keeps the chart live', FChart.AnimLive, True);
      FreeAndNil(FChart);
    end;
    Finish(arr.Count);
    AssertTrue('compared', FCompared > 2000);
  finally
    arr.Free;
  end;
end;

procedure TAdvChartLinesOracleTest.TestTheEnterFramesAsUpstream;
var
  arr, frames: TJSONArray;
  c, fr: TJSONObject;
  i, j: Integer;
  t: Double;
begin
  arr := Cases('enter');
  try
    for i := 0 to arr.Count - 1 do
    begin
      c := arr.Objects[i];
      FName := c.Strings['id'];
      NewChart(camAlways);
      FChart.SetOption(c.Objects['option'].AsJSON, True);
      RenderNow;
      frames := c.Arrays['frames'];
      for j := 0 to frames.Count - 1 do
      begin
        fr := frames.Objects[j];
        t := fr.Floats['t'];
        if t > 0 then FChart.AnimTick(T0 + t);
        CheckFrame(fr);
      end;
      FreeAndNil(FChart);
    end;
    Finish(arr.Count);
    AssertTrue('compared', FCompared > 200);
  finally
    arr.Free;
  end;
end;

{ ---- the tooltip's rows ---- }

type
  TLnRow = record
    Marker, Name, Value: string;
    HasMarker, HasName, HasValue: Boolean;
  end;
  TLnRows = array of TLnRow;

function RowsOf(ABlock: TTyTooltipBlock): TLnRows;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j, n: Integer;
  row: TLnRow;
begin
  Result := nil;
  if ABlock = nil then Exit;
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  n := 0;
  for i := 0 to High(lines) do
  begin
    row := Default(TLnRow);
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind = ttrMarker then
      begin
        row.HasMarker := True;
        row.Marker := 'item';
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
    SetLength(Result, n + 1);
    Result[n] := row;
    Inc(n);
  end;
end;

function RowText(const R: TLnRow): string;
  function Q(AHas: Boolean; const S: string): string;
  begin
    if AHas then Result := '"' + S + '"' else Result := 'null';
  end;
begin
  Result := '{' + Q(R.HasMarker, R.Marker) + ' ' + Q(R.HasName, R.Name) + ' '
    + Q(R.HasValue, R.Value) + '}';
end;

function WantRowText(ARow: TJSONObject): string;
  function Q(const AKey: string): string;
  var d: TJSONData;
  begin
    d := ARow.Find(AKey);
    if (d = nil) or (d.JSONType = jtNull) then Result := 'null'
    else Result := '"' + d.AsString + '"';
  end;
begin
  Result := '{' + Q('marker') + ' ' + Q('name') + ' ' + Q('value') + '}';
end;

procedure TAdvChartLinesOracleTest.CheckLegend(AWant: TJSONArray);
var
  lay: TTyLegendLayout;
  j, k: Integer;
  w: TJSONObject;
  found: Boolean;
begin
  if FChart.LegendLayoutCount = 0 then
  begin
    Miss('no legend here');
    Exit;
  end;
  lay := FChart.LegendLayout(0);
  for j := 0 to AWant.Count - 1 do
  begin
    w := AWant.Objects[j];
    found := False;
    for k := 0 to High(lay.Items) do
      if lay.Items[k].Name = w.Strings['name'] then
      begin
        found := True;
        SameStr('legend ' + w.Strings['name'] + ' icon', lay.Items[k].Icon, w.Strings['icon']);
        SameBool('legend ' + w.Strings['name'] + ' selected', lay.Items[k].Selected, w.Booleans['selected']);
        { an unselected item is in the inactive ink, the skin's here }
        if w.Booleans['selected'] then
          SameColour('legend ' + w.Strings['name'] + ' colour', lay.Items[k].Colour, w.Find('fill'));
      end;
    if not found then Miss('no legend item ' + w.Strings['name']);
  end;
end;

procedure TAdvChartLinesOracleTest.CheckStep(AStep: TJSONObject; ALegend: Boolean);
var
  hv, tip, er, sym: TJSONObject;
  ev, rows, states, syms: TJSONArray;
  el, j, k, s, r: Integer;
  d: TTyChartDatumRef;
  e: TTyChartElement;
  role, got, want: string;
  item: TTyStItem;
  block: TTyTooltipBlock;
  lrows: TLnRows;
  isLarge: Boolean;
  parts: TStringList;
begin
  isLarge := False;
  { the element and the row under the pointer }
  if AStep.Find('hover').JSONType = jtObject then
  begin
    hv := AStep.Objects['hover'];
    d := FChart.HitTestAt(AStep.Integers['x'], AStep.Integers['y'], el);
    role := 'none';
    if el >= 0 then
    begin
      e := FChart.List.Element(el);
      if (e.Shape.Kind = cskLarge) and (e.Shape.Large.Kind = lgkLines) then role := 'large'
      else if e.Anim.Role = carLinesLine then role := 'line'
      else if e.Anim.Role = carLinesFrom then role := 'fromSymbol'
      else if e.Anim.Role = carLinesTo then role := 'toSymbol'
      else if e.Anim.Role = carLinesEffect then role := 'effect'
      else if (e.Shape.Kind = cskPolyline) and (e.Caption.FontSizeLogical = 0) then role := 'line'
      else role := 'other';
    end;
    SameStr('the hovered element', role, hv.Strings['role']);
    isLarge := hv.Strings['role'] = 'large';
    if isLarge then
    begin
      { UPSTREAM'S row is null (row 0) or not a number (an unset
        startIndex): the port hovers the batch and names no row }
      SameBool('a lines batch names no row', TyChartDatumValid(d), False);
      Inc(FCompared);
      if not ((hv.Find('dataIndex').JSONType = jtNull)
        or (hv.Find('dataIndex').AsString = 'NaN')) then
        Miss('upstream named a row of a lines batch: ' + hv.Find('dataIndex').AsJSON);
    end
    else if role = hv.Strings['role'] then
    begin
      SameInt('its series', d.SeriesIndex, hv.Integers['seriesIndex']);
      SameInt('its row', d.DataIndex, hv.Integers['dataIndex']);
    end;
  end
  else if AStep.Find('x').JSONType <> jtNull then
  begin
    FChart.HitTestAt(AStep.Integers['x'], AStep.Integers['y'], el);
    Inc(FCompared);
    if el >= 0 then Miss(Format('something under (%d, %d) here, nothing upstream',
      [AStep.Integers['x'], AStep.Integers['y']]));
  end;
  { the chart's mouse events: a lines batch's upstream are NaN-indexed, the
    port's none }
  ev := AStep.Arrays['events'];
  isLarge := isLarge or ((ev.Count > 0) and (ev.Objects[0].Find('dataIndex').JSONType = jtString));
  if isLarge then
    SameInt('no events over a lines batch', FChart.Events.Count, 0)
  else
  begin
    SameInt('events', FChart.Events.Count, ev.Count);
    if FChart.Events.Count = ev.Count then
    begin
      parts := TStringList.Create;
      try
        parts.Delimiter := #9;
        parts.StrictDelimiter := True;
        for j := 0 to ev.Count - 1 do
        begin
          er := ev.Objects[j];
          parts.DelimitedText := FChart.Events[j];
          got := Format('%s %s:%s "%s"', [parts[0], parts[1], parts[2], parts[3]]);
          want := Format('%s %d:%d "%s"', [er.Strings['type'], er.Integers['seriesIndex'],
            er.Integers['dataIndex'], StrOrNull(er.Find('name'))]);
          SameStr(Format('event %d', [j]), got, want);
        end;
      finally
        parts.Free;
      end;
    end
    else
      for j := 0 to FChart.Events.Count - 1 do
        Miss('  here: ' + FChart.Events[j]);
  end;
  { the tooltip }
  tip := AStep.Objects['tooltip'];
  if isLarge then
    SameBool('no tooltip over a lines batch', FChart.TooltipShown, False)
  else
  begin
    SameBool('the tooltip shown', FChart.TooltipShown, tip.Booleans['shown']);
    if tip.Booleans['shown'] and FChart.TooltipShown then
    begin
      rows := tip.Arrays['rows'];
      block := FChart.ContentOf(FChart.TooltipShownDatum);
      try
        lrows := RowsOf(block);
      finally
        block.Free;
      end;
      SameInt('tooltip rows', Length(lrows), rows.Count);
      if Length(lrows) = rows.Count then
        for j := 0 to rows.Count - 1 do
          SameStr(Format('tooltip row %d', [j]), RowText(lrows[j]), WantRowText(rows.Objects[j]));
    end;
  end;
  { every row's states }
  states := AStep.Arrays['states'];
  for j := 0 to states.Count - 1 do
  begin
    er := states.Objects[j];
    s := er.Integers['seriesIndex'];
    r := er.Integers['dataIndex'];
    if not FChart.ItemStates(s, r, item) then
    begin
      Miss(Format('no states for series %d row %d', [s, r]));
      Continue;
    end;
    want := '';
    for k := 0 to er.Objects['line'].Arrays['states'].Count - 1 do
    begin
      if want <> '' then want := want + ',';
      want := want + er.Objects['line'].Arrays['states'].Strings[k];
    end;
    SameStr(Format('series %d row %d line states', [s, r]), TyStNamesText(item.Host.States), want);
    if item.Host.Cur.Has[stkStroke] then
      SameColour(Format('series %d row %d stroke', [s, r]), item.Host.Cur.Color[stkStroke],
        er.Objects['line'].Find('stroke'));
    if item.Host.Cur.Has[stkOpacity] then
      SameHex(Format('series %d row %d opacity', [s, r]), item.Host.Cur.Num[stkOpacity],
        er.Objects['line'].Find('opacity'));
    if item.Host.Cur.Has[stkLineWidth] then
      SameHex(Format('series %d row %d line width', [s, r]), item.Host.Cur.Num[stkLineWidth],
        er.Objects['line'].Find('lineWidth'));
    if item.Host.Cur.Has[stkZ2] then
      SameInt(Format('series %d row %d z2', [s, r]), Round(item.Host.Cur.Num[stkZ2]),
        er.Objects['line'].Integers['z2']);
    syms := er.Arrays['symbols'];
    SameInt(Format('series %d row %d symbols with states', [s, r]), Length(item.Parts), syms.Count);
    if Length(item.Parts) = syms.Count then
      for k := 0 to syms.Count - 1 do
      begin
        sym := syms.Objects[k];
        want := '';
        for el := 0 to sym.Arrays['states'].Count - 1 do
        begin
          if want <> '' then want := want + ',';
          want := want + sym.Arrays['states'].Strings[el];
        end;
        SameStr(Format('series %d row %d %s states', [s, r, sym.Strings['name']]),
          TyStNamesText(item.Parts[k].States), want);
        if item.Parts[k].Cur.Has[stkFill] and (sym.Find('fill').JSONType <> jtNull) then
          SameColour(Format('series %d row %d %s fill', [s, r, sym.Strings['name']]),
            item.Parts[k].Cur.Color[stkFill], sym.Find('fill'));
        if item.Parts[k].Cur.Has[stkOpacity] then
          SameHex(Format('series %d row %d %s opacity', [s, r, sym.Strings['name']]),
            item.Parts[k].Cur.Num[stkOpacity], sym.Find('opacity'));
      end;
    if (er.Find('label').JSONType = jtObject) and item.Label_.Exists then
    begin
      want := '';
      for k := 0 to er.Objects['label'].Arrays['states'].Count - 1 do
      begin
        if want <> '' then want := want + ',';
        want := want + er.Objects['label'].Arrays['states'].Strings[k];
      end;
      SameStr(Format('series %d row %d label states', [s, r]),
        TyStNamesText(item.Label_.States), want);
    end;
  end;
  if ALegend and (AStep.Find('legend') <> nil) and (AStep.Find('legend').JSONType = jtArray) then
    CheckLegend(AStep.Arrays['legend']);
  { a legend toggle: the series left out are not drawn }
  if (AStep.Find('series') <> nil) and (AStep.Find('series').JSONType = jtArray) then
    for s := 0 to 1 do
    begin
      r := 0;
      for k := 0 to AStep.Arrays['series'].Count - 1 do
        if AStep.Arrays['series'].Objects[k].Integers['seriesIndex'] = s then r := 1;
      SameBool(Format('series %d drawn after the toggle', [s]),
        FChart.LinesSolvedOf(s).Valid, r = 1);
    end;
end;

procedure TAdvChartLinesOracleTest.TestThePointerAsUpstream;
var
  arr, steps: TJSONArray;
  c, st: TJSONObject;
  i, j: Integer;
  t: string;
  nowMs: Double;
  hasLegend: Boolean;
begin
  arr := Cases('hover');
  try
    for i := 0 to arr.Count - 1 do
    begin
      c := arr.Objects[i];
      FName := c.Strings['id'];
      NewChart(camOff);
      FChart.TooltipNow := 0;
      FChart.SetOption(c.Objects['option'].AsJSON, True);
      RenderNow;
      hasLegend := c.Find('legend').JSONType = jtArray;
      if hasLegend then CheckLegend(c.Arrays['legend']);
      steps := c.Arrays['steps'];
      for j := 0 to steps.Count - 1 do
      begin
        st := steps.Objects[j];
        t := st.Strings['t'];
        FName := c.Strings['id'] + '/' + IntToStr(j) + ' ' + t;
        nowMs := (j + 1) * 1000;
        FChart.TooltipNow := nowMs;
        FChart.Events.Clear;
        if t = 'move' then
          FChart.Move(st.Integers['x'], st.Integers['y'])
        else if t = 'leave' then
          FChart.Leave
        else if t = 'action' then
          FChart.DispatchAction(st.Objects['payload'].AsJSON);
        FChart.TooltipTick(nowMs + 500);
        FChart.TooltipNow := nowMs + 500;
        RenderNow;
        CheckStep(st, hasLegend);
      end;
      FreeAndNil(FChart);
    end;
    Finish(arr.Count);
    AssertTrue('compared', FCompared > 300);
  finally
    arr.Free;
  end;
end;

{ ==================== hand-written ==================== }

procedure TAdvChartLinesTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartLinesTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  inherited TearDown;
end;

procedure TAdvChartLinesTest.Show(const AOption: string; AMode: TTyChartAnimationMode);
begin
  FreeAndNil(FChart);
  FChart := TLnProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 600, 400);
  FChart.AnimationMode := AMode;
  FChart.AnimNow := T0;
  FChart.SetOption(AOption, True);
  RenderNow;
end;

procedure TAdvChartLinesTest.RenderNow;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
end;

function TAdvChartLinesTest.CountRole(ARole: TTyChartAnimRole): Integer;
var k: Integer;
begin
  Result := 0;
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Anim.Role = ARole then Inc(Result);
end;

const
  cBase = '{"animation":false,"grid":{"left":60,"right":40,"top":40,"bottom":40},'
    + '"xAxis":{"type":"value","min":0,"max":100},"yAxis":{"type":"value","min":0,"max":100},';

procedure TAdvChartLinesTest.TestTheDataForms;
var
  o: TJSONObject;
  r: TTyLinesRawArray;
begin
  { the flat form: counts, then that many pairs; a value of 0 }
  o := TJSONObject(GetJSON('{"data":[2,1,2,3,4,3,5,6,7,8,9,10]}'));
  try
    r := TyLinesRawsOf(o);
    AssertEquals('two rows', 2, Length(r));
    AssertEquals('the first has two points', 4, Length(r[0].XY));
    AssertEquals('the second three', 6, Length(r[1].XY));
    AssertEquals('its last y', 10, r[1].XY[5].Num, 0);
    AssertTrue('flat', r[0].RawIsFlat);
    AssertEquals('the value is 0', 0, r[0].Value, 0);
  finally
    o.Free;
  end;
  { the ec2 pairs: the first point's name, from and to }
  o := TJSONObject(GetJSON('{"data":[[{"coord":[1,2],"name":"a","value":5},{"coord":[3,4],"name":"b"}]]}'));
  try
    r := TyLinesRawsOf(o);
    AssertEquals('one row', 1, Length(r));
    AssertEquals('named by its first point', 'a', r[0].Name);
    AssertEquals('from', 'a', r[0].FromName);
    AssertEquals('to', 'b', r[0].ToName);
    AssertEquals('its value', 5, r[0].Value, 0);
    AssertEquals('the second point x', 3, r[0].XY[2].Num, 0);
  finally
    o.Free;
  end;
  { a bare coords array: no value, the array its raw value }
  o := TJSONObject(GetJSON('{"data":[[[1,2],[3,4]],{"coords":[[5,6],[7,8]],"value":[9,10]}]}'));
  try
    r := TyLinesRawsOf(o);
    AssertTrue('not a number', IsNan(r[0].Value));
    AssertTrue('raw is the array', r[0].RawJson is TJSONArray);
    AssertEquals('an array value: its first', 9, r[1].Value, 0);
  finally
    o.Free;
  end;
end;

procedure TAdvChartLinesTest.TestTheLabelPlaceMatchesTheGraphsAtPercentOne;
var
  g: TTyLinesGeom;
  x, y, ox, oy, rot, ax, ay: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
begin
  { a reversed straight line, 'middle': turned by pi plus the tangent's
    angle, centred above the middle }
  g := Default(TTyLinesGeom);
  SetLength(g.Pts, 2);
  g.Pts[0] := TyPointF(200, 100);
  g.Pts[1] := TyPointF(100, 100);
  g.Drawn := True;
  TyLinesLabelPlace(g, 1, llpMiddle, 5, 5, x, y, ox, oy, rot, ax, ay, ah, av);
  AssertEquals('middle x', 150, x, 0);
  AssertEquals('5 above', 95, y, 0);
  { pi plus the tangent's -pi: a reversed line's words stay upright }
  AssertEquals('upright', 0, rot, 0);
  AssertTrue('centred', ah = tahCentre);
  AssertTrue('hangs from its bottom', av = tavBottom);
  { at percent 0 the end is the start: d is the zero vector, 'end' sits on
    the start, centred }
  TyLinesLabelPlace(g, 0, llpEnd, 5, 5, x, y, ox, oy, rot, ax, ay, ah, av);
  AssertEquals('on the start', 200, x, 0);
  AssertTrue('centred at 0', ah = tahCentre);
  AssertTrue('middle at 0', av = tavMiddle);
end;

procedure TAdvChartLinesTest.TestTheEffectRunsWithAnimationOffAndStopsWhenNotLooping;
var
  p: TTyChartAnimProxy;
  x0: Double;
begin
  Show(cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d",'
    + '"effect":{"show":true,"loop":false,"period":1},'
    + '"data":[{"coords":[[10,10],[80,60]]}]}]}', camAlways);
  p := FChart.AnimFindProxy(0, 0, 'linesEffect');
  AssertNotNull('the effect has its proxy with the series animation off', p);
  x0 := p.LinesEffect.X;
  FChart.AnimTick(T0 + 500);
  AssertTrue('it moved', p.LinesEffect.X > x0);
  AssertTrue('live', FChart.AnimLive);
  FChart.AnimTick(T0 + 1001);
  AssertTrue('a clip that does not loop removes the symbol', p.LinesEffectGone);
  AssertFalse('and the chart rests', FChart.AnimLive);
  { off: the static first frame }
  Show(cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d",'
    + '"effect":{"show":true},"data":[{"coords":[[10,10],[80,60]]}]}]}', camOff);
  AssertEquals('one effect element at rest', 1, CountRole(carLinesEffect));
  AssertNull('no proxy when off', FChart.AnimFindProxy(0, 0, 'linesEffect'));
end;

{ THE TRAIL is the canvas' motion blur: every frame the layer's last
  picture comes back at lastFrameAlpha under the series drawn again. A line
  of opacity 0.5 drawn over itself that way saturates -- 0.5, then
  0.5 + 0.5 * 0.95 * 0.5, ... towards 0.5 / (1 - 0.95 * 0.5) -- which is the
  look of upstream's trail charts; without a trail it stays at 0.5. }
procedure TAdvChartLinesTest.TestTheTrailLayerFades;

  function RedOnTheLine(const ATrail: string): Integer;
  var k: Integer;
  begin
    Show(cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d",'
      + '"lineStyle":{"color":"#0000ff","width":4},'
      + '"effect":{"show":true,"trailLength":' + ATrail + ',"period":4,"symbolSize":8},'
      + '"data":[{"coords":[[10,50],[90,50]]}]}]}', camAlways);
    for k := 1 to 12 do
    begin
      FChart.AnimTick(T0 + k * 16);
      FBmp.Fill(BGRA(255, 255, 255, 255));
      FChart.Cached(FBmp.Canvas, Rect(0, 0, 600, 400), 96);
    end;
    { ahead of the symbol (at about x 110 + 400 * 0.05) }
    Result := FBmp.GetPixel(450, 200).red;
  end;

var
  i: Integer;
  frm: TTyPaintList;
  hasLine: Boolean;
  plain, trail: Integer;
begin
  Show(cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d",'
    + '"effect":{"show":true,"trailLength":0.5,"period":2,"symbolSize":8},'
    + '"data":[{"coords":[[10,50],[90,50]]}]}]}', camAlways);
  AssertEquals('lastFrameAlpha 0.95', 0.95, FChart.LinesSolvedOf(0).TrailAlpha, 1e-12);
  AssertTrue('only the loop is left: continuous', FChart.AnimContinuous);
  frm := FChart.Frame;
  hasLine := False;
  for i := 0 to frm.Count - 1 do
    if frm.Element(i).Anim.Role = carLinesLine then hasLine := True;
  AssertTrue('the line is in the frame', hasLine);
  plain := RedOnTheLine('0');
  trail := RedOnTheLine('0.5');
  { (BGRA blends in linear light: half a blue over white reads about 170) }
  AssertTrue(Format('a line at 0.5 lets the white through without a trail (red %d)',
    [plain]), (plain > 100) and (plain < 200));
  AssertTrue(Format('with one it saturates (red %d against %d)', [trail, plain]),
    trail < plain - 60);
end;

procedure TAdvChartLinesTest.TestALargeBatchIsOneElementWithNoRow;
var
  d: TTyChartDatumRef;
  el, n, k: Integer;
begin
  Show(cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d","large":true,'
    + '"largeThreshold":3,"data":[{"coords":[[10,10],[90,10]]},{"coords":[[10,50],[90,50]]},'
    + '{"coords":[[10,90],[90,90]]}]}]}', camOff);
  n := 0;
  for k := 0 to FChart.List.Count - 1 do
    if FChart.List.Element(k).Datum.SeriesIndex = 0 then Inc(n);
  AssertEquals('one element for three rows', 1, n);
  AssertTrue('a lines batch', FChart.SeriesLargeKind(0) = lgkLines);
  { y = 50 is pixel 200 }
  d := FChart.HitTestAt(300, 200, el);
  AssertTrue('the batch is hovered', el >= 0);
  AssertFalse('with no row', TyChartDatumValid(d));
  { under its threshold: one element per row }
  Show(cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d","large":true,'
    + '"largeThreshold":4,"data":[{"coords":[[10,10],[90,10]]},{"coords":[[10,50],[90,50]]},'
    + '{"coords":[[10,90],[90,90]]}]}]}', camOff);
  AssertEquals('three lines', 3, CountRole(carLinesLine));
  AssertTrue('not large', FChart.SeriesLargeKind(0) = lgkNone);
end;

procedure TAdvChartLinesTest.TestTheHookIsTheOnlyWayToAPoint;
var sol: TTyLinesSolved;
begin
  { a geo (none here) draws nothing; the same rows on a polar and on a
    calendar are laid out by their own dataToPoint }
  Show('{"animation":false,"series":[{"type":"lines","data":[{"coords":[[1,2],[3,4]]}]}]}', camOff);
  AssertFalse('no geo: nothing', FChart.LinesSolvedOf(0).Valid);
  Show('{"animation":false,"polar":{},"radiusAxis":{"type":"value","min":0,"max":10},'
    + '"angleAxis":{"type":"value","min":0,"max":360},'
    + '"series":[{"type":"lines","coordinateSystem":"polar","data":[{"coords":[[0,0],[10,90]]}]}]}', camOff);
  sol := FChart.LinesSolvedOf(0);
  AssertTrue('a polar row', sol.Valid and (Length(sol.Geoms) = 1) and sol.Geoms[0].Drawn);
  AssertTrue('radius 0 is the centre', Abs(sol.Geoms[0].Pts[0].X - 300) < 1e-9);
  AssertTrue('a sector clip', sol.HasClipSector);
end;

procedure TAdvChartLinesTest.TestTheLinesArePainted;
var
  c: TBGRAPixel;
begin
  Show(cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d",'
    + '"lineStyle":{"width":6,"opacity":1,"color":"#ff0000"},'
    + '"data":[{"coords":[[10,50],[90,50]]}]}]}', camOff);
  c := FBmp.GetPixel(300, 200);
  AssertTrue('red on the line', (c.red > 200) and (c.green < 60) and (c.blue < 60));
  c := FBmp.GetPixel(300, 100);
  AssertTrue('white off it', (c.red > 240) and (c.green > 240));
  { a large batch is painted too }
  Show(cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d","large":true,'
    + '"largeThreshold":1,"lineStyle":{"width":6,"opacity":1,"color":"#0000ff"},'
    + '"data":[{"coords":[[10,50],[90,50]]}]}]}', camOff);
  c := FBmp.GetPixel(300, 200);
  AssertTrue('blue on the batch', (c.blue > 200) and (c.red < 60));
end;

{ EffectLine.updateData: the same period, loop and round trip keep the clip
  running through an update, on the new path; a new period starts it over
  from where __t was (delay -period * __t) }
procedure TAdvChartLinesTest.TestAnUpdateKeepsTheEffectRunning;
var
  p, q: TTyChartAnimProxy;
  t1, t2: Double;
  opt: string;
begin
  opt := cBase + '"series":[{"type":"lines","coordinateSystem":"cartesian2d","animation":false,'
    + '"effect":{"show":true,"period":4},"data":[{"coords":[[10,10],[80,60]]}]}]}';
  Show(opt, camAlways);
  FChart.AnimTick(T0 + 1000);
  p := FChart.AnimFindProxy(0, 0, 'linesEffect');
  AssertNotNull('the effect runs', p);
  t1 := p.Num('__t');
  AssertEquals('a quarter of the way', 0.25, t1, 1e-12);
  FChart.AnimNow := T0 + 1000;
  FChart.SetOption(StringReplace(opt, '[80,60]', '[90,90]', []), True);
  RenderNow;
  FChart.AnimTick(T0 + 2000);
  q := FChart.AnimFindProxy(0, 0, 'linesEffect');
  AssertNotNull('still there', q);
  t2 := q.Num('__t');
  AssertEquals('the same clip runs on: half way', 0.5, t2, 1e-12);
  AssertTrue('on the new path', q.LinesEffect.P2.X > 500);
end;

initialization
  RegisterTest(TAdvChartLinesOracleTest);
  RegisterTest(TAdvChartLinesTest);
end.
