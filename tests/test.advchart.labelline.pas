unit test.advchart.labelline;
{$mode objfpc}{$H+}
{ Label-line routing -- updateLabelLinePoints (the nearest point of the
  host's path from four candidate anchors on the label), limitTurnAngle,
  limitSurfaceAngle, the smooth path and the line's states -- held to
  ECharts 6.1 bit for bit. [Batch 112, roadmap B14]

  tools/advchart-oracle/label-line.js runs the real dist with read-only hooks
  inside updateLabelLinePoints and round the pie's two limits, and records:
    - RULES: nearestPointOnPath on sectors, rects, polylines, svg paths with
      curves and elliptical arcs, and every built-in symbol's unit path;
      limitTurnAngle / limitSurfaceAngle on random lines and angles;
      buildLabelLinePath's calls for random lines and smooth values;
    - every chart's routing calls (the inputs and the points before and
      after the turn limit), the pie's own limit calls, and every label line
      as drawn and under highlight.

  Three layers, reported apart:
    - THE RULES fed straight into AdvChart.LabelGuide;
    - THE ROUTES: each recorded call's inputs fed into TyLabelLineRoute and
      the limits, and the symbol paths the port builds against the ones
      upstream measured;
    - THE WIRING: the control renders each option and every label line is
      compared -- hidden or not, its points, its smooth path, its ink and
      width, its z against its host -- and again under highlight. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.ZrPath, tyControls.AdvChart.LabelGuide,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Color,
     tyControls.AdvChart.States,
     tyControls.AdvChart.Measure, tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TLgProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TLgHandlers = class
  public
    function Fan(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function XY(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function PieLine(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function PieXY(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
  end;

  TAdvChartLabelLineTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TLgProbe;
    FH: TLgHandlers;
    FRoot, FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FGuides, FHidden, FCurved, FHover, FExtra, FRoutes, FBent, FHosts: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Num(const AWhat: string; AGot: Double; const AHex: string);
    procedure Same(const AWhat: string; AGot, AWant: Boolean);
    function Rules: TJSONObject;
    function Cases: TJSONArray;
    procedure Show(ACase: TJSONObject);
    procedure Finish(AMin: Integer);
    procedure CheckPoints(const AWhat: string; const AGot: array of TTyPointF;
      APts: TJSONArray);
    procedure CheckCalls(const AWhat: string; const APts: array of TTyPointF;
      const ACmds: TTyPathCmdArray; ACalls: TJSONArray);
    procedure CheckGuides(ACase: TJSONObject);
    procedure CheckHover(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheProjectionsAsUpstream;
    procedure TestTheSymbolPathsAsUpstream;
    procedure TestTheLimitsAsUpstream;
    procedure TestTheSmoothPathAsUpstream;
    procedure TestTheRoutesAsUpstream;
    procedure TestTheChartAsUpstream;
    procedure TestTheGuardsWereKept;
    procedure TestTheReaders;
    procedure TestALineTakesItsItemsColour;
  end;

implementation

const
  W = 600;

{ ---------------- the probe ---------------- }

function TLgProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TLgProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TLgProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ---------------- the handlers (label-line.js's) ---------------- }

function TLgHandlers.Fan(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Result := Default(TTyChartLabelLayout);
  Result.HasDx := True;
  Result.Dx := (AArgs.DataIndex * 37) mod 81 - 40;
  Result.HasDy := True;
  Result.Dy := (AArgs.DataIndex * 53) mod 61 - 30;
end;

function TLgHandlers.XY(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Result := Default(TTyChartLabelLayout);
  Result.X := TyChartPosNum(40 + (AArgs.DataIndex * 97) mod 520);
  Result.Y := TyChartPosNum(30 + (AArgs.DataIndex * 61) mod 320);
end;

function TLgHandlers.PieLine(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
var pts: TTyPointFArray;
begin
  Result := Default(TTyChartLabelLayout);
  if Length(AArgs.LabelLinePoints) = 0 then Exit;
  pts := Copy(AArgs.LabelLinePoints);
  if AArgs.LabelRectX < W / 2 then pts[2].X := AArgs.LabelRectX
  else pts[2].X := AArgs.LabelRectX + AArgs.LabelRectW;
  pts[2].Y := AArgs.LabelRectY + AArgs.LabelRectH / 2;
  Result.HasLabelLinePoints := True;
  Result.LabelLinePoints := pts;
end;

function TLgHandlers.PieXY(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
begin
  Result := PieLine(AArgs);
  if AArgs.LabelRectX < W / 2 then Result.X := TyChartPosNum(40)
  else Result.X := TyChartPosNum(560);
end;

{ ---------------- numbers ---------------- }

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

{ bit for bit, a not-a-number equal to any other }
function SameNum(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function IsNull(D: TJSONData): Boolean;
begin
  Result := (D = nil) or (D.JSONType = jtNull);
end;

function HexArray(A: TJSONArray): TTyDoubleArray;
var i: Integer;
begin
  SetLength(Result, A.Count);
  for i := 0 to A.Count - 1 do Result[i] := FromHex(A.Strings[i]);
end;

function RectOf(A: TJSONArray): TTyXYWH;
begin
  Result := TyXYWH(FromHex(A.Strings[0]), FromHex(A.Strings[1]),
    FromHex(A.Strings[2]), FromHex(A.Strings[3]));
end;

function MatOf(A: TJSONData; out M: TTyMat2D): Boolean;
var i: Integer;
begin
  Result := not IsNull(A);
  for i := 0 to 5 do M[i] := 0;
  if not Result then Exit;
  for i := 0 to 5 do M[i] := FromHex(TJSONArray(A).Strings[i]);
end;

function PtsOf(A: TJSONArray): TTyGuidePoints;
var i: Integer;
begin
  for i := 0 to 2 do
    Result[i] := TyPointF(FromHex(TJSONArray(A.Items[i]).Strings[0]),
      FromHex(TJSONArray(A.Items[i]).Strings[1]));
end;

{ a recorded angle (JSON as fed) as the limits coerce it }
function AngleOf(D: TJSONData): Double;
begin
  if D = nil then Exit(NaN);
  Result := TyGuideJsNumber(D, NaN);
end;

function FixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim;
end;

{ ---------------- the test case ---------------- }

procedure TAdvChartLabelLineTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 120 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartLabelLineTest.Num(const AWhat: string; AGot: Double;
  const AHex: string);
begin
  Inc(FCompared);
  if not SameNum(AGot, FromHex(AHex)) then
    Miss(Format('%s: %s upstream, %s here', [AWhat, Fmt(FromHex(AHex)), Fmt(AGot)]));
end;

procedure TAdvChartLabelLineTest.Same(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s: %s upstream, %s here', [AWhat, BoolToStr(AWant, True),
      BoolToStr(AGot, True)]));
end;

function TAdvChartLabelLineTest.Rules: TJSONObject;
begin
  Result := TJSONObject(FRoot).Objects['rules'];
end;

function TAdvChartLabelLineTest.Cases: TJSONArray;
begin
  Result := TJSONObject(FRoot).Arrays['cases'];
end;

procedure TAdvChartLabelLineTest.Show(ACase: TJSONObject);
var cw, ch: Integer;
begin
  cw := ACase.Integers['W'];
  ch := ACase.Integers['H'];
  FBmp.SetSize(cw, ch);
  FChart.Option := '{}';
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, cw, ch);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
end;

procedure TAdvChartLabelLineTest.Finish(AMin: Integer);
begin
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared > AMin);
end;

procedure TAdvChartLabelLineTest.CheckPoints(const AWhat: string;
  const AGot: array of TTyPointF; APts: TJSONArray);
var k: Integer;
begin
  Inc(FCompared);
  if Length(AGot) <> APts.Count then
  begin
    Miss(Format('%s: %d points upstream, %d here', [AWhat, APts.Count, Length(AGot)]));
    Exit;
  end;
  for k := 0 to APts.Count - 1 do
  begin
    Num(AWhat + ' x' + IntToStr(k), AGot[k].X, TJSONArray(APts.Items[k]).Strings[0]);
    Num(AWhat + ' y' + IntToStr(k), AGot[k].Y, TJSONArray(APts.Items[k]).Strings[1]);
  end;
end;

{ buildLabelLinePath's calls against the commands drawn (the points joined
  where there are none) }
procedure TAdvChartLabelLineTest.CheckCalls(const AWhat: string;
  const APts: array of TTyPointF; const ACmds: TTyPathCmdArray; ACalls: TJSONArray);
var
  k: Integer;
  op: string;
  cl: TJSONArray;
begin
  Inc(FCompared);
  if Length(ACmds) = 0 then
  begin
    if ACalls.Count <> Length(APts) then
    begin
      Miss(Format('%s: %d calls upstream, %d points joined here', [AWhat, ACalls.Count, Length(APts)]));
      Exit;
    end;
    for k := 0 to ACalls.Count - 1 do
    begin
      cl := TJSONArray(ACalls.Items[k]);
      if k = 0 then op := 'M' else op := 'L';
      if cl.Strings[0] <> op then
      begin
        Miss(Format('%s: call %d is %s upstream, %s here', [AWhat, k, cl.Strings[0], op]));
        Exit;
      end;
      Num(AWhat + ' ' + op + IntToStr(k) + ' x', APts[k].X, cl.Strings[1]);
      Num(AWhat + ' ' + op + IntToStr(k) + ' y', APts[k].Y, cl.Strings[2]);
    end;
    Exit;
  end;
  if ACalls.Count <> Length(ACmds) then
  begin
    Miss(Format('%s: %d calls upstream, %d commands here', [AWhat, ACalls.Count, Length(ACmds)]));
    Exit;
  end;
  for k := 0 to ACalls.Count - 1 do
  begin
    cl := TJSONArray(ACalls.Items[k]);
    case ACmds[k].Kind of
      pckMove: op := 'M';
      pckLine: op := 'L';
      pckCurve: op := 'C';
    else
      op := 'Z';
    end;
    if cl.Strings[0] <> op then
    begin
      Miss(Format('%s: call %d is %s upstream, %s here', [AWhat, k, cl.Strings[0], op]));
      Exit;
    end;
    if op = 'C' then
    begin
      Num(AWhat + ' C' + IntToStr(k) + ' x1', ACmds[k].X1, cl.Strings[1]);
      Num(AWhat + ' C' + IntToStr(k) + ' y1', ACmds[k].Y1, cl.Strings[2]);
      Num(AWhat + ' C' + IntToStr(k) + ' x2', ACmds[k].X2, cl.Strings[3]);
      Num(AWhat + ' C' + IntToStr(k) + ' y2', ACmds[k].Y2, cl.Strings[4]);
      Num(AWhat + ' C' + IntToStr(k) + ' x', ACmds[k].X, cl.Strings[5]);
      Num(AWhat + ' C' + IntToStr(k) + ' y', ACmds[k].Y, cl.Strings[6]);
    end
    else
    begin
      Num(AWhat + ' ' + op + IntToStr(k) + ' x', ACmds[k].X, cl.Strings[1]);
      Num(AWhat + ' ' + op + IntToStr(k) + ' y', ACmds[k].Y, cl.Strings[2]);
    end;
  end;
end;

{ ---------------- the rules ---------------- }

procedure TAdvChartLabelLineTest.TestTheProjectionsAsUpstream;
var
  pr: TJSONArray;
  paths: TJSONObject;
  i: Integer;
  r: TJSONObject;
  data: TTyDoubleArray;
  ox, oy, d: Double;
begin
  pr := Rules.Arrays['project'];
  paths := Rules.Objects['paths'];
  for i := 0 to pr.Count - 1 do
  begin
    r := pr.Objects[i];
    FName := 'project ' + r.Strings['path'] + ' #' + IntToStr(i);
    data := HexArray(paths.Objects[r.Strings['path']].Arrays['data']);
    { a sentinel where nothing writes }
    ox := 12345.5;
    oy := -6789.25;
    d := TyNearestPointOnPath(data, FromHex(r.Arrays['pt'].Strings[0]),
      FromHex(r.Arrays['pt'].Strings[1]), ox, oy);
    Num('distance', d, r.Strings['dist']);
    if IsNull(r.Find('out')) then
    begin
      Same('nothing written', (ox = 12345.5) and (oy = -6789.25), True);
    end
    else
    begin
      Num('x', ox, r.Arrays['out'].Strings[0]);
      Num('y', oy, r.Arrays['out'].Strings[1]);
    end;
  end;
  Finish(3000);
  AssertTrue(Format('projections (%d)', [pr.Count]), pr.Count >= 1000);
end;

{ the unit paths createSymbol builds, as this port's ZrPath builds them }
procedure TAdvChartLabelLineTest.TestTheSymbolPathsAsUpstream;
const
  cNames: array[0..7] of string = ('circle', 'rect', 'roundRect', 'triangle',
    'diamond', 'pin', 'arrow', 'emptyCircle');
var
  paths: TJSONObject;
  i, k: Integer;
  want, got: TTyDoubleArray;
begin
  paths := Rules.Objects['paths'];
  for i := 0 to High(cNames) do
  begin
    FName := 'symbol ' + cNames[i];
    want := HexArray(paths.Objects['sym.' + cNames[i]].Arrays['data']);
    got := TyGuidePathData(TyZrSymbol(cNames[i], -1, -1, 2, 2));
    Inc(FCompared);
    if Length(got) <> Length(want) then
    begin
      Miss(Format('%d numbers upstream, %d here', [Length(want), Length(got)]));
      Continue;
    end;
    for k := 0 to High(want) do
      if not SameNum(got[k], want[k]) then
        Miss(Format('number %d: %s upstream, %s here', [k, Fmt(want[k]), Fmt(got[k])]));
    Inc(FCompared, Length(want));
  end;
  Finish(80);
end;

procedure TAdvChartLabelLineTest.TestTheLimitsAsUpstream;
var
  a: TJSONArray;
  i, bent: Integer;
  r: TJSONObject;
  p: TTyGuidePoints;
begin
  bent := 0;
  a := Rules.Arrays['turn'];
  for i := 0 to a.Count - 1 do
  begin
    r := a.Objects[i];
    FName := 'turn #' + IntToStr(i);
    p := PtsOf(r.Arrays['pts']);
    TyLimitTurnAngle(p, AngleOf(r.Find('angle')));
    CheckPoints('points', p, r.Arrays['out']);
    if r.Arrays['out'].AsJSON <> r.Arrays['pts'].AsJSON then Inc(bent);
  end;
  a := Rules.Arrays['surface'];
  for i := 0 to a.Count - 1 do
  begin
    r := a.Objects[i];
    FName := 'surface #' + IntToStr(i);
    p := PtsOf(r.Arrays['pts']);
    TyLimitSurfaceAngle(p, FromHex(r.Arrays['normal'].Strings[0]),
      FromHex(r.Arrays['normal'].Strings[1]), AngleOf(r.Find('angle')));
    CheckPoints('points', p, r.Arrays['out']);
    if r.Arrays['out'].AsJSON <> r.Arrays['pts'].AsJSON then Inc(bent);
  end;
  Finish(4000);
  AssertTrue(Format('lines the limits bent (%d)', [bent]), bent >= 100);
end;

procedure TAdvChartLabelLineTest.TestTheSmoothPathAsUpstream;
var
  a, pa: TJSONArray;
  i, k, curved: Integer;
  r: TJSONObject;
  pts: array of TTyPointF;
  cmds: TTyPathCmdArray;
begin
  curved := 0;
  a := Rules.Arrays['smooth'];
  for i := 0 to a.Count - 1 do
  begin
    r := a.Objects[i];
    FName := 'smooth #' + IntToStr(i);
    pa := r.Arrays['pts'];
    SetLength(pts, pa.Count);
    for k := 0 to pa.Count - 1 do
      pts[k] := TyPointF(FromHex(TJSONArray(pa.Items[k]).Strings[0]),
        FromHex(TJSONArray(pa.Items[k]).Strings[1]));
    cmds := TyLabelLineCmds(pts, FromHex(r.Strings['smooth']));
    if Length(cmds) > 0 then Inc(curved);
    CheckCalls('path', pts, cmds, r.Arrays['calls']);
  end;
  Finish(3000);
  AssertTrue(Format('smooth lines (%d)', [curved]), curved >= 200);
end;

{ ---------------- the routes ---------------- }

procedure TAdvChartLabelLineTest.TestTheRoutesAsUpstream;
var
  c, i: Integer;
  cs, l: TJSONObject;
  lines: TJSONArray;
  host: TTyGuideHost;
  lm: TTyMat2D;
  hasLm: Boolean;
  p: TTyGuidePoints;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    lines := cs.Arrays['lines'];
    for i := 0 to lines.Count - 1 do
    begin
      l := lines.Objects[i];
      FName := Format('%s route s%d d%d', [cs.Strings['id'], l.Integers['s'], l.Integers['d']]);
      host := Default(TTyGuideHost);
      host.IsPath := not IsNull(l.Find('path'));
      if host.IsPath then host.Data := HexArray(l.Arrays['path']);
      host.HasM := MatOf(l.Find('targetM'), host.M);
      host.HasAnchor := not IsNull(l.Find('anchor'));
      if host.HasAnchor then
      begin
        host.AnchorX := FromHex(l.Arrays['anchor'].Strings[0]);
        host.AnchorY := FromHex(l.Arrays['anchor'].Strings[1]);
      end;
      hasLm := MatOf(l.Find('labelM'), lm);
      TyLabelLineRoute(RectOf(l.Arrays['raw']), hasLm, lm, host,
        FromHex(l.Strings['len']), p);
      CheckPoints('before the limit', p, l.Arrays['pre']);
      TyLimitTurnAngle(p, AngleOf(l.Find('minTurnAngle')));
      CheckPoints('after the limit', p, l.Arrays['post']);
      Inc(FRoutes);
    end;
    lines := cs.Arrays['pie'];
    for i := 0 to lines.Count - 1 do
    begin
      l := lines.Objects[i];
      FName := Format('%s pie s%d d%d', [cs.Strings['id'], l.Integers['s'], l.Integers['d']]);
      p := PtsOf(l.Arrays['pre']);
      TyLimitTurnAngle(p, AngleOf(l.Find('minTurnAngle')));
      TyLimitSurfaceAngle(p, FromHex(l.Arrays['normal'].Strings[0]),
        FromHex(l.Arrays['normal'].Strings[1]), AngleOf(l.Find('maxSurfaceAngle')));
      CheckPoints('pie limits', p, l.Arrays['post']);
      if l.Arrays['pre'].AsJSON <> l.Arrays['post'].AsJSON then Inc(FBent);
    end;
  end;
  Finish(10000);
  AssertTrue(Format('routes (%d)', [FRoutes]), FRoutes >= 500);
  AssertTrue(Format('pie lines bent (%d)', [FBent]), FBent >= 50);
end;

{ ---------------- the wiring ---------------- }

function FindGuide(AList: TTyPaintList; ASeries, AData: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = carGuide) and (AList.Element(i).Anim.Series = ASeries)
      and (AList.Element(i).Anim.Index = AData) then
      Exit(i);
  Result := -1;
end;

{ the label element of a datum (an attached label, or a pie's) }
function FindLabel(AList: TTyPaintList; ASeries, AData: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Caption.LmKind > 0) and (AList.Element(i).Anim.Role <> carGuide)
      and (AList.Element(i).Caption.FontSizeLogical > 0)
      and (AList.Element(i).Datum.SeriesIndex = ASeries)
      and (AList.Element(i).Datum.DataIndex = AData) then
      Exit(i);
  Result := -1;
end;

function ColourOf(const S: string; out C: TTyChartColor): Boolean;
begin
  Result := TyTryParseChartColor(S, C);
end;

{ ECHARTS 6'S DEFAULT PALETTE: a line in one of these took its item's colour
  (no lineStyle said otherwise) -- the port's theme has its own palette }
function IsPaletteColour(const S: string): Boolean;
begin
  Result := (S = '#5070dd') or (S = '#b6d634') or (S = '#505372') or (S = '#ff994d')
    or (S = '#0ca8df') or (S = '#ffd10a') or (S = '#fb628b') or (S = '#785db0')
    or (S = '#3fbe95');
end;

procedure TAdvChartLabelLineTest.CheckGuides(ACase: TJSONObject);
var
  gs, lines: TJSONArray;
  i, g, lb, hi, k, s, d: Integer;
  gr, ln: TJSONObject;
  el, lab, host: TTyChartElement;
  c: TTyChartColor;
  seen: array of Boolean;
  gh: TTyGuideHost;
  m: TTyMat2D;
  hasM: Boolean;
  want: TTyDoubleArray;
begin
  SetLength(seen, FChart.List.Count);
  gs := ACase.Arrays['guides'];
  for i := 0 to gs.Count - 1 do
  begin
    gr := gs.Objects[i];
    s := gr.Integers['s'];
    d := gr.Integers['d'];
    FName := Format('%s guide s%d d%d', [ACase.Strings['id'], s, d]);
    g := FindGuide(FChart.List, s, d);
    Inc(FCompared);
    if g < 0 then
    begin
      Miss('a label line upstream, none here');
      Continue;
    end;
    seen[g] := True;
    el := FChart.List.Element(g);
    Inc(FGuides);
    Same('ignore', el.Ignore, gr.Booleans['ignore']);
    if el.Ignore then Inc(FHidden);
    CheckPoints('points', el.Shape.Points, gr.Arrays['points']);
    CheckCalls('path', el.Shape.Points, el.Shape.Cmds, gr.Arrays['calls']);
    if Length(el.Shape.Cmds) > 0 then Inc(FCurved);
    Num('smooth', el.Caption.LgSmooth, gr.Strings['smooth']);
    { the ink: a declared colour as written, the palette's as the item's
      (its host's, here) }
    lb := FindLabel(FChart.List, s, d);
    if not IsNull(gr.Find('stroke')) then
    begin
      Inc(FCompared);
      if IsPaletteColour(gr.Strings['stroke']) then
      begin
        if (lb >= 0) and (FChart.List.Element(lb).Caption.LmHostPlus1 > 0) then
        begin
          host := FChart.List.Element(FChart.List.Element(lb).Caption.LmHostPlus1 - 1);
          if host.Caption.LgColor <> el.Style.StrokeColor then
            Miss(Format('stroke: the item''s %.8x, %.8x here', [host.Caption.LgColor, el.Style.StrokeColor]));
        end;
      end
      else if not ColourOf(gr.Strings['stroke'], c) then Miss('stroke ' + gr.Strings['stroke'] + ' unread')
      else if c <> el.Style.StrokeColor then
        Miss(Format('stroke %s upstream, %.8x here', [gr.Strings['stroke'], el.Style.StrokeColor]));
    end;
    if not IsNull(gr.Find('lineWidth')) then
      Num('line width', el.Style.StrokeWidthLogical, gr.Strings['lineWidth']);
    if not IsNull(gr.Find('opacity')) then
      Num('opacity', el.Style.Alpha, gr.Strings['opacity']);
    Same('dashed', Length(el.Style.DashLogical) > 0,
      (not IsNull(gr.Find('lineDash'))) and (gr.Find('lineDash').JSONType = jtString)
      and (gr.Strings['lineDash'] = 'dashed'));
    { its z against its host's: under it, or over it with showAbove }
    if (lb >= 0) and (FChart.List.Element(lb).Caption.LmHostPlus1 > 0) then
    begin
      lab := FChart.List.Element(lb);
      hi := lab.Caption.LmHostPlus1 - 1;
      host := FChart.List.Element(hi);
      Inc(FCompared);
      if Sign(el.Z2 - host.Z2) <> Sign(gr.Integers['z2'] - gr.Integers['hostZ2']) then
        Miss(Format('z2 %d against its host''s %d upstream, %d against %d here',
          [gr.Integers['z2'], gr.Integers['hostZ2'], el.Z2, host.Z2]));
      { the host's path and transform, as upstream measured them }
      lines := ACase.Arrays['lines'];
      for k := 0 to lines.Count - 1 do
      begin
        ln := lines.Objects[k];
        if (ln.Integers['s'] <> s) or (ln.Integers['d'] <> d) or IsNull(ln.Find('path')) then Continue;
        if not TyGuideHostOf(host.Caption, gh) then
        begin
          Miss('no host path here');
          Break;
        end;
        Inc(FHosts);
        want := HexArray(ln.Arrays['path']);
        Inc(FCompared);
        if Length(want) <> Length(gh.Data) then
          Miss(Format('host path: %d numbers upstream, %d here', [Length(want), Length(gh.Data)]))
        else
          for hi := 0 to High(want) do
            if not SameNum(want[hi], gh.Data[hi]) then
            begin
              Miss(Format('host path number %d: %s upstream, %s here', [hi, Fmt(want[hi]), Fmt(gh.Data[hi])]));
              Break;
            end;
        hasM := MatOf(ln.Find('targetM'), m);
        Same('host transform', gh.HasM, hasM);
        if hasM and gh.HasM then
          for hi := 0 to 5 do Num('host m' + IntToStr(hi), gh.M[hi], ln.Arrays['targetM'].Strings[hi]);
        Break;
      end;
    end;
  end;
  { lines here upstream has none of: never drawn in any state }
  for i := 0 to FChart.List.Count - 1 do
    if (FChart.List.Element(i).Anim.Role = carGuide) and not seen[i] then
    begin
      FName := Format('%s guide s%d d%d', [ACase.Strings['id'],
        FChart.List.Element(i).Anim.Series, FChart.List.Element(i).Anim.Index]);
      Inc(FExtra);
      Same('a line upstream has not is hidden', FChart.List.Element(i).Ignore, True);
    end;
end;

procedure TAdvChartLabelLineTest.CheckHover(ACase: TJSONObject);
var
  hv, gs: TJSONArray;
  h, i, g, cw, ch: Integer;
  pl, gr: TJSONObject;
  el: TTyChartElement;
  c: TTyChartColor;
  back: string;
begin
  hv := ACase.Arrays['hover'];
  cw := ACase.Integers['W'];
  ch := ACase.Integers['H'];
  for h := 0 to hv.Count - 1 do
  begin
    pl := hv.Objects[h].Objects['payload'];
    AssertTrue('dispatch', FChart.DispatchAction(pl.AsJSON));
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
    gs := hv.Objects[h].Arrays['guides'];
    for i := 0 to gs.Count - 1 do
    begin
      gr := gs.Objects[i];
      FName := Format('%s %s %d, s%d d%d', [ACase.Strings['id'], pl.Strings['type'],
        pl.Integers['dataIndex'], gr.Integers['s'], gr.Integers['d']]);
      g := FindGuide(FChart.List, gr.Integers['s'], gr.Integers['d']);
      Inc(FCompared);
      if g < 0 then
      begin
        Miss('no line here');
        Continue;
      end;
      el := FChart.List.Element(g);
      Inc(FHover);
      Same('ignore', el.Ignore, gr.Booleans['ignore']);
      { straight unless the state says: the curves upstream's smooth draws
        through these points }
      Same('curved', Length(el.Shape.Cmds) > 0,
        Length(TyLabelLineCmds(el.Shape.Points, FromHex(gr.Strings['smooth']))) > 0);
      if not IsNull(gr.Find('stroke')) and not IsPaletteColour(gr.Strings['stroke']) then
      begin
        Inc(FCompared);
        if not ColourOf(gr.Strings['stroke'], c) then Miss('stroke unread')
        else if c <> el.Style.StrokeColor then
          Miss(Format('stroke %s upstream, %.8x here', [gr.Strings['stroke'], el.Style.StrokeColor]));
      end;
      if not IsNull(gr.Find('lineWidth')) then
        Num('line width', el.Style.StrokeWidthLogical, gr.Strings['lineWidth']);
    end;
    if pl.Strings['type'] = 'select' then back := 'unselect' else back := 'downplay';
    pl.Strings['type'] := back;
    FChart.DispatchAction(pl.AsJSON);
    if back = 'unselect' then pl.Strings['type'] := 'select' else pl.Strings['type'] := 'highlight';
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cw, ch), 96);
  end;
end;

procedure TAdvChartLabelLineTest.TestTheChartAsUpstream;
var
  c: Integer;
  cs: TJSONObject;
begin
  for c := 0 to Cases.Count - 1 do
  begin
    cs := Cases.Objects[c];
    FName := cs.Strings['id'];
    Show(cs);
    CheckGuides(cs);
    CheckHover(cs);
  end;
  Finish(20000);
  AssertTrue(Format('label lines compared (%d)', [FGuides]), FGuides >= 900);
  AssertTrue(Format('hidden lines compared (%d)', [FHidden]), FHidden >= 50);
  AssertTrue(Format('smooth lines compared (%d)', [FCurved]), FCurved >= 80);
  AssertTrue(Format('lines under a state compared (%d)', [FHover]), FHover >= 100);
  AssertTrue(Format('host paths compared (%d)', [FHosts]), FHosts >= 400);
end;

procedure TAdvChartLabelLineTest.TestTheGuardsWereKept;
var
  g: TJSONArray;
  i: Integer;
begin
  g := TJSONObject(FRoot).Arrays['guards'];
  AssertTrue('guards', g.Count >= 15);
  for i := 0 to g.Count - 1 do
    AssertTrue(g.Objects[i].Strings['id'], g.Objects[i].Booleans['ok']);
end;

{ the readers: JavaScript's coercions where a product or a comparison meets
  an option value }
procedure TAdvChartLabelLineTest.TestTheReaders;
var d: TJSONData;

  function J(const S: string): TJSONData;
  begin
    FreeAndNil(d);
    d := GetJSON(S);
    Result := d;
  end;

begin
  d := nil;
  try
    AssertEquals('smooth true', 0.3, TyLabelLineSmoothOf(J('true')), 0);
    AssertEquals('smooth false', 0, TyLabelLineSmoothOf(J('false')), 0);
    AssertEquals('smooth absent', 0, TyLabelLineSmoothOf(nil), 0);
    AssertEquals('smooth -1', 0, TyLabelLineSmoothOf(J('-1')), 0);
    AssertEquals('smooth "0.4"', 0.4, TyLabelLineSmoothOf(J('"0.4"')), 0);
    AssertEquals('smooth "x"', 0, TyLabelLineSmoothOf(J('"x"')), 0);
    AssertEquals('smooth 2', 2, TyLabelLineSmoothOf(J('2')), 0);
    AssertEquals('length2 absent', 7, TyGuideLength2(nil, 7), 0);
    AssertEquals('length2 0', 0, TyGuideLength2(J('0'), 7), 0);
    AssertEquals('length2 ""', 0, TyGuideLength2(J('""'), 7), 0);
    AssertEquals('length2 "9"', 9, TyGuideLength2(J('"9"'), 7), 0);
    AssertTrue('length2 "10%"', IsNan(TyGuideLength2(J('"10%"'), 7)));
    AssertEquals('length2 true', 1, TyGuideLength2(J('true'), 7), 0);
    AssertEquals('length2 null', 0, TyGuideLength2(J('null'), 7), 0);
    AssertEquals('angle "120"', 120, TyGuideJsNumber(J('"120"'), NaN), 0);
    AssertEquals('angle null', 0, TyGuideJsNumber(J('null'), NaN), 0);
    AssertTrue('angle absent', IsNan(TyGuideJsNumber(nil, NaN)));
  finally
    d.Free;
  end;
end;

{ A LINE WITHOUT A lineStyle COLOUR TAKES ITS ITEM'S: the visual colour by
  the series' draw type -- an empty symbol's went to its pen (its fill is the
  ground), a bar's is its fill. The wiring test reads the port's palette off
  the hosts, so this pins which of the host's inks that is. }
procedure TAdvChartLabelLineTest.TestALineTakesItsItemsColour;

  procedure Check(const AOption, AWhat: string; AStroke: Boolean);
  var
    g, lb: Integer;
    el, host: TTyChartElement;
  begin
    FChart.Option := '{}';
    FChart.Option := AOption;
    FChart.SetBounds(0, 0, 600, 400);
    FBmp.SetSize(600, 400);
    FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 600, 400), 96);
    g := FindGuide(FChart.List, 0, 1);
    AssertTrue(AWhat + ': a line', g >= 0);
    el := FChart.List.Element(g);
    lb := FindLabel(FChart.List, 0, 1);
    AssertTrue(AWhat + ': a label on a host', (lb >= 0)
      and (FChart.List.Element(lb).Caption.LmHostPlus1 > 0));
    host := FChart.List.Element(FChart.List.Element(lb).Caption.LmHostPlus1 - 1);
    AssertTrue(AWhat + ': the pen and the fill differ', host.Style.StrokeColor <> host.Style.FillColor);
    if AStroke then
      AssertEquals(AWhat + ': the pen''s colour', host.Style.StrokeColor, el.Style.StrokeColor)
    else
      AssertEquals(AWhat + ': the fill''s colour', host.Style.FillColor, el.Style.StrokeColor);
  end;

begin
  Check('{"animation":false,"xAxis":{},"yAxis":{},"series":[{"type":"scatter",'
    + '"symbol":"emptyCircle","symbolSize":16,"label":{"show":true},"labelLine":{"show":true},'
    + '"labelLayout":{"dx":30,"dy":-20},"data":[[1,2],[3,4],[5,1]]}]}', 'an empty circle', True);
  Check('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"line","label":{"show":true},"labelLine":{"show":true},'
    + '"labelLayout":{"dy":-30},"data":[3,5,2]}]}', 'a line''s symbol', True);
  Check('{"animation":false,"xAxis":{"type":"category","data":["a","b","c"]},"yAxis":{},'
    + '"series":[{"type":"bar","itemStyle":{"borderColor":"#333","borderWidth":2},'
    + '"label":{"show":true,"position":"top"},"labelLine":{"show":true},'
    + '"labelLayout":{"dy":-30},"data":[3,5,2]}]}', 'a bordered bar', False);
end;

{ ---------------- plumbing ---------------- }

procedure TAdvChartLabelLineTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TLgProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  FH := TLgHandlers.Create;
  TyChartRegisterLabelLayoutHandler('LG_FAN', @FH.Fan);
  TyChartRegisterLabelLayoutHandler('LG_XY', @FH.XY);
  TyChartRegisterLabelLayoutHandler('LG_PIELINE', @FH.PieLine);
  TyChartRegisterLabelLayoutHandler('LG_PIEXY', @FH.PieXY);
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixtureDir + 'advchart-label-line.json'));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixtureDir + 'advchart-label-line.json');
    FRoot := GetJSON(sl.Text);
    sl.LoadFromFile(FixtureDir + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FReport := '';
  FGuides := 0;
  FHidden := 0;
  FCurved := 0;
  FHover := 0;
  FExtra := 0;
  FRoutes := 0;
  FBent := 0;
  FHosts := 0;
end;

procedure TAdvChartLabelLineTest.TearDown;
begin
  TyChartClearLabelLayoutHandlers;
  FreeAndNil(FH);
  FreeAndNil(FRoot);
  FreeAndNil(FMeasure);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

initialization
  RegisterTest(TAdvChartLabelLineTest);
end.
