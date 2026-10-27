unit test.advchart.animedges;
{$mode objfpc}{$H+}
{ THE ANIMATION EDGES THE PORT DID NOT FOLLOW, HELD TO UPSTREAM [spec 243b].

  tools/advchart-oracle/anim-edges.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock, the elements of each case
  (a candlestick's boxes, a funnel's pieces and labels, ...).

  This replays every case through the control and compares what each
  element is drawn with in the frame, and whether its animation is
  running. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Anim,
     tyControls.AdvanceChart.AnimView, tyControls.AdvanceChart.AnimOpt, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.Parallel, tyControls.AdvanceChart.ThemeRiver,
     tyControls.AdvanceChart.Chord, tyControls.AdvanceChart.PolarBar,
     tyControls.AdvanceChart.ZrPath,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  TAeProbe = class(TGfxProbe)
  public
    function Frame: TTyPaintList;
  end;

  TAdvChartAnimEdgesOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAeProbe;
    FRoot: TJSONData;
    FBad, FCompared, FSamples: Integer;
    { a pictorial glyph's box at rest, the port's and upstream's }
    FGlHave: array[0..7] of Boolean;
    FGlP, FGlU: array[0..7] of TTyRectF;
    FWhere, FReport: string;
    { [R5-I] the last render's picture, and the case it is of }
    FBmp: TBGRABitmap;
    FCase: TJSONObject;
    procedure Bad(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData); overload;
    procedure SameNum(const AWhat: string; AGot, AWant: Double); overload;
    function RoleEl(ASeries, ARow: Integer; ARole: TTyChartAnimRole;
      out AEl: TTyChartElement): Boolean;
    procedure SameRun(const AWhat: string; AProxy: TTyChartAnimProxy; AWant: TJSONObject);
    procedure NearNum(const AWhat: string; AGot, AWant: Double);
    function SubEl(ASeries, ARow, ASub: Integer; ARole: TTyChartAnimRole;
      out AEl: TTyChartElement): Boolean;
    procedure SameGuideCmds(const AWhat: string; const AEl: TTyChartElement; AWant: TJSONArray);
    function HIdx100(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    procedure CheckSample(ARec: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
    procedure RunGroup(const AGroup: string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestACandlesticksBoxesAsUpstream;
    procedure TestAFunnelsPiecesAndLabelsAsUpstream;
    procedure TestABarClippedPastThePlotAsUpstream;
    procedure TestTheMarkersAsUpstream;
    procedure TestEachSetOptionRendersAsUpstream;
    procedure TestBarsOnAPolarAsUpstream;
    procedure TestLabelLinesAsUpstream;
    procedure TestAVisualMapsHandleLabelsFadeAsUpstream;
    procedure TestStateAnimationsFormsAsUpstream;
    procedure TestAHeatmapsTooltipColumnAsUpstream;
    procedure TestARadarsPointLabelsAsUpstream;
    procedure TestAThemeRiversLabelsUnderTheClipAsUpstream;
    procedure TestAThemeRiversLabelIsInkedOnlyInsideTheClip;
    procedure TestAPictorialGlyphsEmphasisScaleAsUpstream;
    procedure TestTheContinuousPhasesZOrderAsUpstream;
  end;

implementation

function TAeProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

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
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := (HexOf(A) = HexOf(B)) or ((A = 0) and (B = 0));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function WantNum(AData: TJSONData): Double;
begin
  if IsNull(AData) then Result := NaN else Result := FromHex(AData.AsString);
end;

function Nums(AArr: TJSONArray): TTyDoubleArray;
var i: Integer;
begin
  Result := nil;
  if AArr = nil then Exit;
  SetLength(Result, AArr.Count);
  for i := 0 to AArr.Count - 1 do Result[i] := WantNum(AArr.Items[i]);
end;

{ {"$fn": name} -> '@name', in place, everywhere }
procedure AeFns(AData: TJSONData);
var
  i: Integer;
  child: TJSONData;
begin
  if (AData = nil) or not (AData.JSONType in [jtArray, jtObject]) then Exit;
  for i := 0 to AData.Count - 1 do
  begin
    child := AData.Items[i];
    if (child.JSONType = jtObject) and (TJSONObject(child).Count = 1)
      and (TJSONObject(child).Find('$fn') <> nil) then
      AData.Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
    else
      AeFns(child);
  end;
end;

{ ==================== the oracle ==================== }

function TAdvChartAnimEdgesOracleTest.HIdx100(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  { idx => idx * 100 }
  Result := ADataIndex * 100;
end;

procedure TAdvChartAnimEdgesOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-anim-edges.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-anim-edges.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  AeFns(FRoot);
  TyChartRegisterAnimDelay('idx*100', @HIdx100);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartAnimEdgesOracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FreeAndNil(FBmp);
  TyChartUnregisterAnimDelay('idx*100');
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAnimEdgesOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAnimEdgesOracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  SameNum(AWhat, AGot, WantNum(AWant));
end;

procedure TAdvChartAnimEdgesOracleTest.SameNum(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not SameBits(AGot, AWant) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
end;

{ the frame's element of a role at a row }
function TAdvChartAnimEdgesOracleTest.RoleEl(ASeries, ARow: Integer;
  ARole: TTyChartAnimRole; out AEl: TTyChartElement): Boolean;
var
  l: TTyPaintList;
  i: Integer;
  e: TTyChartElement;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  l := FChart.Frame;
  if (l = nil) or (l.Count = 0) then l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
  begin
    e := l.Element(i);
    if (e.Anim.Role <> ARole) or (e.Anim.Series <> ASeries) or (e.Anim.Index <> ARow) then Continue;
    AEl := e;
    Exit(True);
  end;
end;

{ a guide's path as drawn: its commands (move, line, curve) against the
  ones PathProxy.rebuildPath gave a canvas }
procedure TAdvChartAnimEdgesOracleTest.SameGuideCmds(const AWhat: string;
  const AEl: TTyChartElement; AWant: TJSONArray);
var
  got: array of string;
  i, k: Integer;

  procedure Push(const S: string);
  begin
    SetLength(got, Length(got) + 1);
    got[High(got)] := S;
  end;

  procedure PushN(A: Double);
  begin
    Push(HexOf(A));
  end;

begin
  got := nil;
  if Length(AEl.Shape.Cmds) > 0 then
    for i := 0 to High(AEl.Shape.Cmds) do
      case AEl.Shape.Cmds[i].Kind of
        pckMove:
          begin
            Push('M');
            PushN(AEl.Shape.Cmds[i].X);
            PushN(AEl.Shape.Cmds[i].Y);
          end;
        pckLine:
          begin
            Push('L');
            PushN(AEl.Shape.Cmds[i].X);
            PushN(AEl.Shape.Cmds[i].Y);
          end;
        pckCurve:
          begin
            Push('C');
            PushN(AEl.Shape.Cmds[i].X1);
            PushN(AEl.Shape.Cmds[i].Y1);
            PushN(AEl.Shape.Cmds[i].X2);
            PushN(AEl.Shape.Cmds[i].Y2);
            PushN(AEl.Shape.Cmds[i].X);
            PushN(AEl.Shape.Cmds[i].Y);
          end;
        pckClose: Push('Z');
      end
  else if AEl.Style.StrokeWidthLogical > 0 then
    for i := 0 to High(AEl.Shape.Points) do
    begin
      if i = 0 then Push('M') else Push('L');
      PushN(AEl.Shape.Points[i].X);
      PushN(AEl.Shape.Points[i].Y);
    end;
  Inc(FCompared);
  if Length(got) <> AWant.Count then
  begin
    Bad(Format('%s: %d command items, upstream %d', [AWhat, Length(got), AWant.Count]));
    Exit;
  end;
  for k := 0 to High(got) do
  begin
    Inc(FCompared);
    if (Length(got[k]) = 1) or (Length(AWant.Strings[k]) = 1) then
    begin
      if got[k] <> AWant.Strings[k] then
        Bad(Format('%s item %d: %s, upstream %s', [AWhat, k, got[k], AWant.Strings[k]]));
    end
    else if not SameBits(FromHex(got[k]), FromHex(AWant.Strings[k])) then
      Bad(Format('%s item %d: %s, upstream %s', [AWhat, k, Txt(FromHex(got[k])),
        Txt(FromHex(AWant.Strings[k]))]));
  end;
end;

procedure TAdvChartAnimEdgesOracleTest.NearNum(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not (Abs(AGot - AWant) <= 1e-6) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
end;

{ a proxy's key, or the rest value where the proxy has none }
function PNumOr(P: TTyChartAnimProxy; const AKey: string; AOr: Double): Double;
begin
  if (P <> nil) and (P.GetAnimProp(AKey).Kind = avkNumber) then Result := P.Num(AKey)
  else Result := AOr;
end;

{ the frame's element of a role at a row and sub-place (a radar item's
  points' labels) }
function TAdvChartAnimEdgesOracleTest.SubEl(ASeries, ARow, ASub: Integer;
  ARole: TTyChartAnimRole; out AEl: TTyChartElement): Boolean;
var
  l: TTyPaintList;
  i: Integer;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  l := FChart.Frame;
  if (l = nil) or (l.Count = 0) then l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
    if (l.Element(i).Anim.Role = ARole) and (l.Element(i).Anim.Series = ASeries)
      and (l.Element(i).Anim.Index = ARow) and (l.Element(i).Anim.Sub = ASub) then
    begin
      AEl := l.Element(i);
      Exit(True);
    end;
end;

{ upstream's clips on the element against the proxy running }
procedure TAdvChartAnimEdgesOracleTest.SameRun(const AWhat: string;
  AProxy: TTyChartAnimProxy; AWant: TJSONObject);
var running: Boolean;
begin
  running := (AProxy <> nil) and (AProxy.AnimatorCount > 0);
  Inc(FCompared);
  if running <> (AWant.Integers['n'] > 0) then
    Bad(Format('%s: running %s, upstream %d clips', [AWhat, BoolToStr(running, True),
      AWant.Integers['n']]));
end;

procedure TAdvChartAnimEdgesOracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TAeProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartAnimEdgesOracleTest.RenderNow;
begin
  { the picture kept for a probe that reads pixels }
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
end;

procedure TAdvChartAnimEdgesOracleTest.CheckSample(ARec: TJSONObject);
var
  i, k, s, slash, idx: Integer;
  name, pre, rest: string;
  leaf: TJSONObject;
  el: TTyChartElement;
  v: TTyDoubleArray;
  p: TTyChartAnimProxy;
  got: TTyAnimValue;
  gone: TJSONArray;
  ops: TTyDoubleArray;
  c: TTyChartColor;
  tipPos: TTyIntegerArray;
  pts: TTyPointFArray;
  l: TTyPaintList;
  found: Boolean;
  bx: TTyRectF;
  px: TBGRAPixel;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    slash := Pos('/', name);
    pre := Copy(name, 1, 2);
    s := StrToInt(Copy(name, 3, slash - 3));
    rest := Copy(name, slash + 1, MaxInt);
    idx := StrToIntDef(rest, -1);
    leaf := nil;
    if ARec.Items[i].JSONType = jtObject then leaf := TJSONObject(ARec.Items[i]);
    if pre = 'cd' then
    begin
      { the box's proxy holds upstream's eight points }
      v := Nums(leaf.Arrays['pts']);
      p := FChart.AnimFindProxy(s, idx, 'candle');
      if p = nil then
      begin
        Bad(name + ': no proxy');
        Continue;
      end;
      got := p.GetAnimProp('shape.points');
      SameNum(name + ' points', Length(got.Arr), Length(v));
      for k := 0 to Min(High(got.Arr), High(v)) do
        SameNum(Format('%s point %d', [name, k]), got.Arr[k], v[k]);
      SameRun(name, p, leaf);
      { a simple box: its one stroke in the frame, the highest to the lowest }
      if leaf.Booleans['simple'] then
      begin
        if not RoleEl(s, idx, carCandleWickHigh, el) then
          Bad(name + ': the simple box is not drawn')
        else
        begin
          SameNum(name + ' stroke points', Length(el.Shape.Points), 2);
          if Length(el.Shape.Points) = 2 then
          begin
            SameNum(name + ' stroke x0', el.Shape.Points[0].X, v[8]);
            SameNum(name + ' stroke y0', el.Shape.Points[0].Y, v[9]);
            SameNum(name + ' stroke x1', el.Shape.Points[1].X, v[12]);
            SameNum(name + ' stroke y1', el.Shape.Points[1].Y, v[13]);
          end;
        end;
      end;
    end
    else if pre = 'br' then
    begin
      { the bar's proxy holds upstream's rect; the element is ignored as
        upstream's }
      v := Nums(leaf.Arrays['sh']);
      p := FChart.AnimFindProxy(s, idx, 'bar');
      if not RoleEl(s, idx, carBar, el) then
      begin
        Bad(name + ': not in the list');
        Continue;
      end;
      Inc(FCompared);
      if el.Ignore <> leaf.Booleans['ig'] then
        Bad(Format('%s: ignore %s, upstream %s', [name, BoolToStr(el.Ignore, True),
          BoolToStr(leaf.Booleans['ig'], True)]));
      if p = nil then
      begin
        Bad(name + ': no proxy');
        Continue;
      end;
      SameNum(name + ' x', p.Num('shape.x'), v[0]);
      SameNum(name + ' y', p.Num('shape.y'), v[1]);
      SameNum(name + ' width', p.Num('shape.width'), v[2]);
      SameNum(name + ' height', p.Num('shape.height'), v[3]);
      SameRun(name, p, leaf);
    end
    else if pre = 'ml' then
    begin
      { a markLine's proxy: its ends and its percent }
      v := Nums(leaf.Arrays['sh']);
      p := FChart.AnimFindProxy(s, idx, 'markLine');
      if p = nil then
      begin
        Bad(name + ': no proxy');
        Continue;
      end;
      { an entering proxy holds the percent alone: the ends are the line's }
      if not RoleEl(s, idx, carMarkLine, el) then el := Default(TTyChartElement);
      SameNum(name + ' x1', PNumOr(p, 'shape.x1', el.Anim.G[0]), v[0]);
      SameNum(name + ' y1', PNumOr(p, 'shape.y1', el.Anim.G[1]), v[1]);
      SameNum(name + ' x2', PNumOr(p, 'shape.x2', el.Anim.G[2]), v[2]);
      SameNum(name + ' y2', PNumOr(p, 'shape.y2', el.Anim.G[3]), v[3]);
      SameNum(name + ' percent', PNumOr(p, 'shape.percent', 1), leaf.Find('pc'));
      SameRun(name, p, leaf);
    end
    else if pre = 'mk' then
    begin
      { a markPoint's proxy: its group's place and its path's scale }
      p := FChart.AnimFindProxy(s, idx, 'markPoint');
      if p = nil then
      begin
        Bad(name + ': no proxy');
        Continue;
      end;
      if not RoleEl(s, idx, carMarkPoint, el) then el := Default(TTyChartElement);
      SameNum(name + ' x', PNumOr(p, 'x', el.Anim.G[0]), leaf.Find('x'));
      SameNum(name + ' y', PNumOr(p, 'y', el.Anim.G[1]), leaf.Find('y'));
      SameNum(name + ' scaleX', PNumOr(p, 'scaleX', el.Anim.G[2]), leaf.Find('sx'));
      SameRun(name, p, leaf);
    end
    else if pre = 'po' then
    begin
      { a polar bar: its proxy's sector, the list's corners and its
        label's turn (the static picture: what updateStyle set) }
      v := Nums(leaf.Arrays['sh']);
      if not RoleEl(s, idx, carPolarBar, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      p := FChart.AnimFindProxy(s, idx, 'bar');
      SameNum(name + ' cx', PNumOr(p, 'shape.cx', el.Anim.G[0]), v[0]);
      SameNum(name + ' cy', PNumOr(p, 'shape.cy', el.Anim.G[1]), v[1]);
      SameNum(name + ' r0', PNumOr(p, 'shape.r0', el.Anim.G[2]), v[2]);
      SameNum(name + ' r', PNumOr(p, 'shape.r', el.Anim.G[3]), v[3]);
      SameNum(name + ' startAngle', PNumOr(p, 'shape.startAngle', el.Anim.G[4]), v[4]);
      SameNum(name + ' endAngle', PNumOr(p, 'shape.endAngle', el.Anim.G[5]), v[5]);
      Inc(FCompared);
      if (el.Anim.G[8] <> 0) <> (leaf.Strings['type'] = 'sausage') then
        Bad(Format('%s: sausage %s, upstream a %s', [name, BoolToStr(el.Anim.G[8] <> 0, True),
          leaf.Strings['type']]));
      if (leaf.Find('cr') is TJSONArray) and (leaf.Strings['type'] <> 'sausage') then
      begin
        v := Nums(leaf.Arrays['cr']);
        SameNum(name + ' corners', Length(el.Anim.Pts), Length(v));
        for k := 0 to Min(High(el.Anim.Pts), High(v)) do
          SameNum(Format('%s corner %d', [name, k]), el.Anim.Pts[k], v[k]);
      end;
      if not IsNull(leaf.Find('rot')) then
        SameNum(name + ' label turn', el.Caption.SecRot, leaf.Find('rot'));
      SameRun(name, p, leaf);
    end
    else if pre = 'pg' then
    begin
      { a pie's label line as a frame draws it: its commands (a curve's
        first part while it draws in), its stroke and width (a state's
        tween) }
      if not RoleEl(s, idx, carGuide, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      SameGuideCmds(name, el, leaf.Arrays['cmds']);
      { nothing drawn: no width to speak of }
      if leaf.Arrays['cmds'].Count > 0 then
        SameNum(name + ' width', el.Style.StrokeWidthLogical, leaf.Find('lw'));
      if TyTryParseChartColor(leaf.Strings['stroke'], c) then
      begin
        Inc(FCompared);
        if (el.Style.StrokeColor and $FFFFFF) <> (c and $FFFFFF) then
          Bad(Format('%s stroke %s, upstream %s', [name, IntToHex(el.Style.StrokeColor, 8),
            leaf.Strings['stroke']]));
      end;
    end
    else if pre = 'bf' then
    begin
      { a bar's fill as drawn now; a fill that is no colour upstream (a
        tween to not-a-number) is not compared }
      if not RoleEl(s, idx, carBar, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      if TyTryParseChartColor(leaf.Strings['fill'], c) and (Pos('NaN', leaf.Strings['fill']) = 0) then
      begin
        Inc(FCompared);
        if (el.Style.FillColor and $FFFFFF) <> (c and $FFFFFF) then
          Bad(Format('%s fill %s, upstream %s', [name, IntToHex(el.Style.FillColor, 8),
            leaf.Strings['fill']]));
      end;
    end
    else if pre = 'ht' then
    begin
      { a heatmap's tooltip columns }
      gone := leaf.Arrays['tip'];
      if FChart.SeriesStore(s) = nil then
      begin
        Bad(name + ': no store');
        Continue;
      end;
      tipPos := FChart.SeriesStore(s).TooltipPositions;
      SameNum(name + ' tooltip columns', Length(tipPos), gone.Count);
      for k := 0 to Min(High(tipPos), gone.Count - 1) do
        SameNum(Format('%s tooltip column %d', [name, k]), tipPos[k], gone.Integers[k]);
    end
    else if pre = 'rs' then
    begin
      { a radar point's label and its line, as a frame draws them }
      idx := StrToInt(Copy(rest, 1, Pos('.', rest) - 1));
      k := StrToInt(Copy(rest, Pos('.', rest) + 1, MaxInt));
      if not IsNull(leaf.Find('lx')) then
      begin
        if not SubEl(s, idx, k + 1, carLabel, el) then Bad(name + ': no label drawn')
        else
        begin
          SameNum(name + ' label x', el.Caption.X, leaf.Find('lx'));
          SameNum(name + ' label y', el.Caption.Y, leaf.Find('ly'));
        end;
      end;
      if not IsNull(leaf.Find('g')) then
      begin
        if not SubEl(s, idx, k + 1, carGuide, el) then Bad(name + ': no line drawn')
        else
        begin
          v := Nums(leaf.Arrays['g']);
          SetLength(pts, Length(v) div 2);
          for k := 0 to High(pts) do pts[k] := TyPointF(v[2 * k], v[2 * k + 1]);
          pts := TyPolylinePrefix(pts, WantNum(leaf.Find('gp')));
          SameNum(name + ' line points', Length(el.Shape.Points), Length(pts));
          for k := 0 to Min(High(pts), High(el.Shape.Points)) do
          begin
            SameNum(Format('%s line point %d x', [name, k]), el.Shape.Points[k].X, pts[k].X);
            SameNum(Format('%s line point %d y', [name, k]), el.Shape.Points[k].Y, pts[k].Y);
          end;
        end;
      end;
    end
    else if pre = 'rl' then
    begin
      { a themeRiver layer's label: cut to its polygon's clip while it
        grows, uncut after }
      l := FChart.Frame;
      if (l = nil) or (l.Count = 0) then l := FChart.List;
      found := False;
      for k := 0 to l.Count - 1 do
      begin
        el := l.Element(k);
        if (el.Anim.Role <> carLabel) or (el.Caption.LmHostPlus1 <= 0)
          or (el.Caption.LmHostPlus1 > l.Count) then Continue;
        if (l.Element(el.Caption.LmHostPlus1 - 1).Anim.Role <> carRiver)
          or (l.Element(el.Caption.LmHostPlus1 - 1).Anim.Series <> s)
          or (l.Element(el.Caption.LmHostPlus1 - 1).Anim.TwKey <> rest) then Continue;
        found := True;
        Break;
      end;
      Inc(FCompared);
      if not found then
      begin
        Bad(name + ': no label');
        Continue;
      end;
      if IsNull(leaf.Find('clip')) then
      begin
        Inc(FCompared);
        if Length(el.ClipPaths) > 0 then Bad(name + ': cut, upstream whole');
      end
      else
      begin
        v := Nums(leaf.Arrays['clip']);
        Inc(FCompared);
        if Length(el.ClipPaths) = 0 then Bad(name + ': whole, upstream cut')
        else
        begin
          bx := TyShapeBounds(el.ClipPaths[0]);
          SameNum(name + ' clip left', bx.Left, v[0]);
          SameNum(name + ' clip top', bx.Top, v[1]);
          SameNum(name + ' clip right', bx.Right, v[0] + v[2]);
          SameNum(name + ' clip bottom', bx.Bottom, v[1] + v[3]);
        end;
      end;
    end
    else if pre = 'gl' then
    begin
      { a pictorial glyph's box as drawn, against its box at rest (the
        first sample): how far each edge moved -- the state's scale about the
        path's origin: its centre across, its top and its bottom. Within a
        millionth: the box of a curved path, whose extent across the port
        measures tighter than zrender's arc box }
      gone := ARec.Arrays[name];
      for k := 0 to Min(gone.Count - 1, 7) do
      begin
        if not SubEl(s, idx, k, carPictorialGlyph, el) then
        begin
          Bad(Format('%s path %d: not drawn', [name, k]));
          Continue;
        end;
        v := Nums(gone.Objects[k].Arrays['gb']);
        bx := TyShapeBounds(el.Shape);
        if not FGlHave[k] then
        begin
          FGlHave[k] := True;
          FGlP[k] := bx;
          FGlU[k] := TyRectF(v[0], v[1], v[0] + v[2], v[1] + v[3]);
        end;
        NearNum(Format('%s path %d centre x moved', [name, k]),
          (bx.Left + bx.Right) / 2 - (FGlP[k].Left + FGlP[k].Right) / 2,
          v[0] + v[2] / 2 - (FGlU[k].Left + FGlU[k].Right) / 2);
        NearNum(Format('%s path %d top moved', [name, k]), bx.Top - FGlP[k].Top, v[1] - FGlU[k].Top);
        NearNum(Format('%s path %d bottom moved', [name, k]), bx.Bottom - FGlP[k].Bottom,
          v[1] + v[3] - FGlU[k].Bottom);
      end;
    end
    else if pre = 'vl' then
      { a visual map's handle label: its opacity now (its blur's fade) }
      SameNum(name + ' opacity', FChart.VmHandleLabelOpacity(s, idx), leaf.Find('op'))
    else if pre = 'gh' then
    begin
      { a bar view's leaving elements: the bar ghosts of the series, their
        opacities in order }
      gone := ARec.Arrays[name];
      SetLength(ops, 0);
      for k := 0 to FChart.AnimGhostCount - 1 do
      begin
        p := FChart.AnimGhostAt(k);
        if (p = nil) or p.Gone or (p.Series <> s) or (p.Role <> 'bar') then Continue;
      { a polar bar's ghost: the sector is a ghost as a rect is }
        SetLength(ops, Length(ops) + 1);
        ops[High(ops)] := p.Num('style.opacity');
      end;
      SameNum(name + ' count', Length(ops), gone.Count);
      for k := 0 to Min(High(ops), gone.Count - 1) do
        SameNum(Format('%s %d opacity', [name, k]), ops[k], gone.Objects[k].Find('op'));
    end
    else if pre = 'fn' then
    begin
      v := Nums(leaf.Arrays['pts']);
      if not RoleEl(s, idx, carFunnel, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      SameNum(name + ' points', Length(el.Shape.Points), 4);
      for k := 0 to Min(High(el.Shape.Points), 3) do
      begin
        SameNum(Format('%s point %d x', [name, k]), el.Shape.Points[k].X, v[2 * k]);
        SameNum(Format('%s point %d y', [name, k]), el.Shape.Points[k].Y, v[2 * k + 1]);
      end;
      SameNum(name + ' opacity', el.Style.Alpha, leaf.Find('op'));
      SameRun(name, FChart.AnimFindProxy(s, idx, 'funnel'), leaf);
    end
    else if pre = 'fl' then
    begin
      if not RoleEl(s, idx, carLabel, el) then
      begin
        Bad(name + ': not drawn');
        Continue;
      end;
      SameNum(name + ' x', el.Caption.X, leaf.Find('x'));
      SameNum(name + ' y', el.Caption.Y, leaf.Find('y'));
      SameRun(name, FChart.AnimFindProxy(s, idx, 'label'), leaf);
    end
    else if pre = 'zo' then
    begin
      { [R5-I] what is on top at the point: where upstream's top element is
        an opaque fill (a bar, the title's box) over a ripple, the picture's
        pixel is that fill's }
      Inc(FCompared);
      if not leaf.Booleans['rip'] then
      begin
        Bad(name + ': upstream has no ripple there (the case is off)');
        Continue;
      end;
      if leaf.Strings['top'] = 'ripple' then Continue;
      if not TyTryParseChartColor(leaf.Strings['top'], c) then
      begin
        Bad(name + ': colour ' + leaf.Strings['top']);
        Continue;
      end;
      px := FBmp.GetPixel(FCase.Arrays['pts'].Arrays[idx].Integers[0],
        FCase.Arrays['pts'].Arrays[idx].Integers[1]);
      if (px.red <> (c shr 16) and $FF) or (px.green <> (c shr 8) and $FF)
        or (px.blue <> c and $FF) then
        Bad(Format('%s: the pixel %d,%d,%d, upstream''s top %s', [name, px.red, px.green,
          px.blue, leaf.Strings['top']]));
    end
    else
      Bad(name + ': a probe the suite does not know');
  end;
end;

procedure TAdvChartAnimEdgesOracleTest.RunCase(ACase: TJSONObject);
var
  events: TJSONArray;
  ev: TJSONObject;
  j: Integer;
  t0, now_: Double;
  act: string;
begin
  FWhere := ACase.Strings['id'];
  FCase := ACase;
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  t0 := TJSONObject(FRoot).Objects['clock'].Floats['T0'];
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := t0;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
  events := ACase.Arrays['events'];
  for j := 0 to events.Count - 1 do
  begin
    ev := events.Objects[j];
    now_ := t0 + ev.Floats['t'];
    act := ev.Strings['do'];
    FWhere := Format('%s t=%s %s', [ACase.Strings['id'], Txt(ev.Floats['t']), act]);
    FChart.AnimNow := now_;
    if act = 'sample' then
    begin
      FChart.AnimTick(now_);
      RenderNow;
      Inc(FSamples);
      CheckSample(ev.Objects['rec']);
    end
    else if act = 'frame' then
    begin
      FChart.AnimTick(now_);
      RenderNow;
    end
    else if act = 'merge' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, False);
      RenderNow;
    end
    else if act = 'move' then
      { the pointer, no paint after it (as an action) }
      FChart.Move(ev.Integers['x'], ev.Integers['y'])
    else if act = 'mergeq' then
      { the next setOption comes before any paint }
      FChart.SetOption(ev.Objects['option'].AsJSON, False)
    else if act = 'set' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, True);
      RenderNow;
    end
    else if act = 'resize' then
    begin
      { chart.resize: a layout at the new size, rendered at once }
      FChart.SetBounds(0, 0, ev.Integers['W'], ev.Integers['H']);
      RenderNow;
    end
    else if act = 'export' then
      { getDataURL at another pixel ratio (the window's layout after it) }
      FChart.SaveToBytes(Format('{"pixelRatio": %d}', [ev.Integers['pixelRatio']]))
    else if act = 'act' then
      { no paint after it: upstream applies an action's states in the frame
        that follows (its animators step from the one after) -- the next
        sample's tick and paint are that frame }
      FChart.DispatchAction(ev.Objects['action'].AsJSON)
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartAnimEdgesOracleTest.RunGroup(const AGroup: string; AMin: Integer);
var
  cases: TJSONArray;
  i, n: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  n := 0;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['group'] = AGroup then
    begin
      try
        RunCase(cases.Objects[i]);
      except
        on E: Exception do Bad(cases.Objects[i].Strings['id'] + ' raised ' + E.ClassName + ': ' + E.Message);
      end;
      Inc(n);
    end;
  AssertTrue('cases run', n > 0);
  if FBad > 0 then
    Fail(Format('%s: %d of %d comparisons over %d samples differ:%s',
      [AGroup, FBad, FCompared, FSamples, FReport]));
  AssertTrue('compared', FCompared >= AMin);
end;

procedure TAdvChartAnimEdgesOracleTest.TestACandlesticksBoxesAsUpstream;
begin
  RunGroup('candle', 300);
end;

procedure TAdvChartAnimEdgesOracleTest.TestAFunnelsPiecesAndLabelsAsUpstream;
begin
  RunGroup('funnel', 300);
end;

procedure TAdvChartAnimEdgesOracleTest.TestABarClippedPastThePlotAsUpstream;
begin
  RunGroup('bar', 200);
end;

procedure TAdvChartAnimEdgesOracleTest.TestTheMarkersAsUpstream;
begin
  RunGroup('mark', 150);
end;

procedure TAdvChartAnimEdgesOracleTest.TestEachSetOptionRendersAsUpstream;
begin
  RunGroup('setopt', 300);
end;

procedure TAdvChartAnimEdgesOracleTest.TestBarsOnAPolarAsUpstream;
begin
  RunGroup('polar', 600);
end;

procedure TAdvChartAnimEdgesOracleTest.TestLabelLinesAsUpstream;
begin
  RunGroup('guide', 300);
end;

procedure TAdvChartAnimEdgesOracleTest.TestAVisualMapsHandleLabelsFadeAsUpstream;
begin
  RunGroup('vmap', 20);
end;

procedure TAdvChartAnimEdgesOracleTest.TestStateAnimationsFormsAsUpstream;
begin
  RunGroup('stanim', 40);
end;

procedure TAdvChartAnimEdgesOracleTest.TestAHeatmapsTooltipColumnAsUpstream;
begin
  RunGroup('htip', 15);
end;

procedure TAdvChartAnimEdgesOracleTest.TestARadarsPointLabelsAsUpstream;
begin
  RunGroup('radar', 60);
end;

procedure TAdvChartAnimEdgesOracleTest.TestAThemeRiversLabelsUnderTheClipAsUpstream;
begin
  RunGroup('river', 40);
end;

procedure TAdvChartAnimEdgesOracleTest.TestAPictorialGlyphsEmphasisScaleAsUpstream;
begin
  RunGroup('pemph', 18);
end;

procedure TAdvChartAnimEdgesOracleTest.TestTheContinuousPhasesZOrderAsUpstream;
begin
  RunGroup('zorder', 12);
end;

{ HAND-WRITTEN: the label's ink in a frame of the enter is cut where the
  clip is -- none of a long label past the clip's right edge halfway in,
  there at rest }
procedure TAdvChartAnimEdgesOracleTest.TestAThemeRiversLabelIsInkedOnlyInsideTheClip;
var
  t0: Double;
  bmp: TBGRABitmap;
  box: TTyRectF;
  i, inkEarly, inkRest: Integer;
  el: TTyChartElement;

  function InkIn(ABmp: TBGRABitmap): Integer;
  var
    px: TBGRAPixel;
    x, y: Integer;
  begin
    Result := 0;
    for y := Max(0, Floor(box.Top)) to Min(ABmp.Height - 1, Ceil(box.Bottom)) do
      for x := Max(0, Floor(box.Left)) to Min(ABmp.Width - 1, Ceil(box.Right)) do
      begin
        px := ABmp.GetPixel(x, y);
        if (px.red < 200) and (px.green < 200) and (px.blue < 200) then Inc(Result);
      end;
  end;

begin
  NewChart(400, 300);
  t0 := 1700000000000;
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := t0;
  FChart.SetOption('{"animation":true,"animationDuration":1000,"animationEasing":"linear",'
    + '"singleAxis":{"type":"time","top":40,"bottom":40},"series":[{"type":"themeRiver",'
    + '"label":{"show":true,"color":"#000"},"color":["#ffffff","#ffffff"],"data":[["2024-01-01",10,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],'
    + '["2024-01-02",20,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],["2024-01-03",15,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]]}]}', True);
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    { the label's box, from the list }
    box := TyRectF(0, 0, 0, 0);
    for i := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(i);
      if (el.Anim.Role = carLabel) and (Copy(el.Caption.Text, 1, 4) = 'aaaa') then
        box := TyShapeBounds(el.Shape);
    end;
    AssertTrue('a label past the clip at 500 ms', box.Right > 260);
    { the part of it past where the clip has got to at 500 ms (x - 10 +
      230) }
    box.Left := 240;
    FChart.AnimNow := t0 + 500;
    FChart.AnimTick(t0 + 500);
    bmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    inkEarly := InkIn(bmp);
    FChart.AnimNow := t0 + 2000;
    FChart.AnimTick(t0 + 2000);
    bmp.Fill(BGRA(255, 255, 255, 255));
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    inkRest := InkIn(bmp);
  finally
    bmp.Free;
  end;
  AssertTrue(Format('the label inked at rest (%d)', [inkRest]), inkRest > 20);
  AssertEquals(Format('none of it past the clip (of %d at rest)', [inkRest]), 0, inkEarly);
end;

initialization
  RegisterTest(TAdvChartAnimEdgesOracleTest);
end.
