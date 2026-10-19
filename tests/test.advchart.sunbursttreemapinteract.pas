unit test.advchart.sunbursttreemapinteract;
{$mode objfpc}{$H+}
{ Sunburst and treemap interaction -- held to upstream to the bit
  [Batch 115].

  tools/advchart-oracle/sunburst-treemap-interact.js runs the real ECharts
  6.1 build through cases of pointer steps (zrender's own Handler: a click is
  press, release and the click after it; a drag; a hover; the wheel),
  dispatched actions, resizes and clock ticks, and records after every step:
  for a sunburst, its view root, every piece the view's group holds (the
  return circle among them) -- its ring, fill, opacity and z2, its label's
  words, place, turn and opacity -- and containPixel at fixed probes; for a
  treemap, its view root, the tree root's layout, every node's background
  and content (its global rect, opacity, fill, z2, its label's words as they
  are cut, its anchor and opacity), every element still leaving, the
  breadcrumb's arrows and words, and whether the view is animating; the
  tooltip a hover shows; and every action event a step emitted.

  The port is driven the same way -- MouseDown / MouseMove / MouseUp /
  DoMouseWheel, DispatchAction, SetBounds, AnimTick on its own clock -- with
  a headless render after each step, and compared through its own API and
  its frame (the paint list as the animations have it now).

  Before the first tick of a case that animates, upstream's first render is
  still entering (a sunburst's rings grow, a treemap's labels fade in); the
  port has no enter animation for either (§124), so that one state is not
  compared. Everything else is compared to the bit; a fill upstream writes
  in its theme colour (the return circle's neutral, a background's white)
  is the port's theme's and is passed over, counted. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Color,
     tyControls.AdvChart.Tree, tyControls.AdvChart.Sunburst,
     tyControls.AdvChart.Treemap, tyControls.AdvChart.Tooltip,
     tyControls.AdvChart.Events,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TStiProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    Events: array of TTyChartEvent;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function Frame: TTyPaintList;
    procedure Down(AX, AY: Integer);
    procedure Move(AX, AY: Integer);
    procedure Up(AX, AY: Integer);
    function Wheel(ADelta, AX, AY: Integer): Boolean;
    procedure OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
  end;

  TAdvChartSunburstTreemapInteractOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TStiProbe;
    FRoot: TJSONData;
    FBad, FCompared, FCases, FStates, FPieces, FRects, FGhosts, FFrames,
      FSkipped, FTips, FEvents: Integer;
    { [R2-I1] events whose payload keys were compared }
    FKeyed: Integer;
    FReport, FName: string;
    FClock: Double;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot, AWant: Double);
    procedure NewChart(AAnimate: Boolean);
    procedure RenderNow(AW, AH: Integer);
    procedure Step(AStep: TJSONObject; var AW, AH: Integer);
    procedure CheckSunburst(ACase, ASeries: TJSONObject);
    procedure CheckTreemap(ACase, ASeries: TJSONObject);
    procedure CheckEvents(ACase, AState: TJSONObject);
    procedure CheckTip(AState: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryDrillZoomAndRoamLandsWhereUpstreamPutsIt;
  end;

  { What the oracle does not reach. }
  TAdvChartSunburstTreemapInteractTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TStiProbe;
    procedure Show(const AOption: string; AW: Integer = 400; AH: Integer = 400);
    procedure RenderNow(AW: Integer = 400; AH: Integer = 400);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestANewOptionForgetsTheViewRoot;
    procedure TestAMergeRebuildsTheTreeAndForgetsTheViewRoot;
    procedure TestAnUnknownTargetLeavesTheViewAlone;
    procedure TestASunburstActionNeedsItsType;
    procedure TestTheBreadcrumbIsNotAClickOnTheRectUnderIt;
    procedure TestARoamOffTreemapDoesNotPan;
  end;

implementation

const
  T0 = 1700000000000;

{ ==================== the probe ==================== }

function TStiProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TStiProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TStiProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TStiProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

procedure TStiProbe.Down(AX, AY: Integer);
begin
  MouseDown(mbLeft, [], AX, AY);
end;

procedure TStiProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TStiProbe.Up(AX, AY: Integer);
begin
  MouseUp(mbLeft, [], AX, AY);
end;

function TStiProbe.Wheel(ADelta, AX, AY: Integer): Boolean;
begin
  Result := DoMouseWheel([], ADelta, Point(AX, AY));
end;

procedure TStiProbe.OnEvent(Sender: TObject; const AEvent: TTyChartEvent);
begin
  if AEvent.Payload = '' then Exit;
  if (AEvent.EventType <> 'sunburstroottonode') and (AEvent.EventType <> 'treemapzoomtonode')
    and (AEvent.EventType <> 'treemaproottonode') and (AEvent.EventType <> 'treemapmove')
    and (AEvent.EventType <> 'treemaprender') then Exit;
  SetLength(Events, Length(Events) + 1);
  Events[High(Events)] := AEvent;
end;

function TStiProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

{ ==================== the fixture's numbers ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-sunburst-treemap-interact.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  System.Move(q, Result, SizeOf(Result));
end;

function NumAt(AObj: TJSONObject; const AKey: string; AIndex: Integer = -1): Double;
var d: TJSONData;
begin
  d := AObj.Find(AKey);
  if AIndex >= 0 then
  begin
    if (d is TJSONArray) and (AIndex < TJSONArray(d).Count) then
      d := TJSONArray(d).Items[AIndex]
    else
      d := nil;
  end;
  Result := HexNum(d);
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function StrOr(AObj: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if AObj = nil then Exit;
  d := AObj.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function IsNull(AObj: TJSONObject; const AKey: string): Boolean;
var d: TJSONData;
begin
  d := AObj.Find(AKey);
  Result := (d = nil) or (d.JSONType = jtNull);
end;

{ the drawn element of a series: AKind 'sun' (a piece, ARow 0 the return
  circle), 'bg' / 'ct' (a treemap rect), 'lbl' (a label; ASpec its item spec,
  0 any) }
function FindIn(AList: TTyPaintList; ASeries, ARow: Integer; const AKind: string;
  ASpec: Integer = 0): Integer;
var i: Integer; el: TTyChartElement;
begin
  Result := -1;
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if AKind = 'sun' then
    begin
      if (el.Anim.Role = carSunPiece) and (el.Anim.Series = ASeries) and (el.Anim.Index = ARow) then
        Exit(i);
    end
    else if (AKind = 'bg') or (AKind = 'ct') then
    begin
      if (el.Anim.Role = carTmRect) and (el.Anim.Series = ASeries) and (el.Anim.Index = ARow)
        and (el.Anim.Sub = Ord(AKind = 'ct')) then Exit(i);
    end
    else if (el.Anim.Role = carLabel) and (el.Datum.SeriesIndex = ASeries)
      and (el.Anim.Index = ARow) and ((ASpec = 0) or (el.Caption.ItemSpec = ASpec)) then
      Exit(i);
  end;
end;

{ ==================== the oracle test ==================== }

procedure TAdvChartSunburstTreemapInteractOracleTest.SetUp;
var sl: TStringList; m: TJSONObject;
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
  FBad := 0;
  FCompared := 0;
  FCases := 0;
  FStates := 0;
  FPieces := 0;
  FRects := 0;
  FGhosts := 0;
  FFrames := 0;
  FSkipped := 0;
  FTips := 0;
  FEvents := 0;
  FReport := '';
  m := TJSONObject(FRoot).Objects['measure'];
  if m = nil then Fail('no measure table');
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FRoot);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 400 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.Same(const AWhat: string;
  AGot, AWant: Double);
var ok: Boolean;
begin
  Inc(FCompared);
  if IsNan(AWant) or IsNan(AGot) then ok := IsNan(AWant) and IsNan(AGot)
  else ok := (AGot = AWant);
  if not ok then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(AWant), Fmt(AGot)]));
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.NewChart(AAnimate: Boolean);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TStiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.OnChartEvent := @FChart.OnEvent;
  if AAnimate then FChart.AnimationMode := camAlways
  else FChart.AnimationMode := camOff;
  FChart.AnimNow := T0;
  FClock := T0;
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.RenderNow(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.Step(AStep: TJSONObject;
  var AW, AH: Integer);
var a, q: TJSONArray; d: TJSONData; k: Integer;
begin
  d := AStep.Find('click');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Down(a.Integers[0], a.Integers[1]);
    FChart.Up(a.Integers[0], a.Integers[1]);
    Exit;
  end;
  d := AStep.Find('drag');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    q := TJSONArray(a.Items[0]);
    FChart.Down(q.Integers[0], q.Integers[1]);
    for k := 1 to a.Count - 1 do
    begin
      q := TJSONArray(a.Items[k]);
      FChart.Move(q.Integers[0], q.Integers[1]);
    end;
    q := TJSONArray(a.Items[a.Count - 1]);
    FChart.Up(q.Integers[0], q.Integers[1]);
    Exit;
  end;
  d := AStep.Find('hover');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Move(a.Integers[0], a.Integers[1]);
    Exit;
  end;
  d := AStep.Find('wheel');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    FChart.Wheel(a.Integers[2], a.Integers[0], a.Integers[1]);
    Exit;
  end;
  if AStep.Find('leave') <> nil then
  begin
    FChart.Move(-10, -10);
    Exit;
  end;
  d := AStep.Find('action');
  if d is TJSONObject then
  begin
    if not FChart.DispatchAction(d.AsJSON) then Miss('the action was refused: ' + d.AsJSON);
    Exit;
  end;
  d := AStep.Find('resize');
  if d is TJSONArray then
  begin
    a := TJSONArray(d);
    AW := a.Integers[0];
    AH := a.Integers[1];
    FChart.SetBounds(0, 0, AW, AH);
    Exit;
  end;
  d := AStep.Find('tick');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    FClock := FClock + d.AsFloat;
    FChart.AnimTick(FClock);
    Exit;
  end;
  Miss('an unknown step ' + AStep.AsJSON);
end;

function AlignWord(AH: TTyTextAnchorH): string;
begin
  case AH of
    tahLeft: Result := 'left';
    tahRight: Result := 'right';
  else
    Result := 'center';
  end;
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.CheckSunburst(ACase, ASeries: TJSONObject);
var
  si, k, row, at, la, i: Integer;
  pieces: TJSONArray;
  p, lbl: TJSONObject;
  lst: TTyPaintList;
  el, le: TTyChartElement;
  a, b: Double;
  want: TTyChartColor;
  seen: array of Boolean;
  probes, cont: TJSONArray;
  w: string;
begin
  si := ASeries.Integers['index'];
  Inc(FCompared);
  if FChart.SunburstViewRoot(si) <> ASeries.Integers['viewRoot'] then
    Miss(Format('series %d: view root %d upstream, %d here',
      [si, ASeries.Integers['viewRoot'], FChart.SunburstViewRoot(si)]));
  lst := FChart.Frame;
  pieces := ASeries.Arrays['pieces'];
  seen := nil;
  SetLength(seen, lst.Count);
  for k := 0 to pieces.Count - 1 do
  begin
    p := pieces.Objects[k];
    if p.Booleans['v'] then row := 0 else row := p.Integers['di'];
    w := Format('series %d piece %d', [si, row]);
    at := FindIn(lst, si, row, 'sun');
    Inc(FCompared);
    if at < 0 then
    begin
      Miss(w + ': drawn upstream, not here');
      Continue;
    end;
    seen[at] := True;
    Inc(FPieces);
    el := lst.Element(at);
    a := NumAt(p, 'sh', 4);
    b := NumAt(p, 'sh', 5);
    Same(w + ' cx', el.Shape.CX, NumAt(p, 'sh', 0));
    Same(w + ' cy', el.Shape.CY, NumAt(p, 'sh', 1));
    Same(w + ' r0', el.Shape.R0, NumAt(p, 'sh', 2));
    Same(w + ' r', el.Shape.R1, NumAt(p, 'sh', 3));
    Same(w + ' start', el.Shape.StartRad, Math.Min(a, b));
    Same(w + ' end', el.Shape.EndRad, Math.Max(a, b));
    Same(w + ' opacity', el.Style.Alpha, NumAt(p, 'op'));
    Inc(FCompared);
    if el.Z2 <> p.Integers['z2'] then
      Miss(Format('%s: z2 %d upstream, %d here', [w, p.Integers['z2'], el.Z2]));
    { the return circle's fill is the theme's }
    if row = 0 then Inc(FSkipped)
    else if TyTryParseChartColor(StrOr(p, 'fill'), want) then
    begin
      Inc(FCompared);
      if el.Style.FillColor <> want then
        Miss(Format('%s: fill %s upstream, %.8x here', [w, StrOr(p, 'fill'), el.Style.FillColor]));
    end;
    { its words }
    la := FindIn(lst, si, row, 'lbl');
    if (p.Find('label') = nil) or (p.Find('label').JSONType = jtNull) then lbl := nil
    else lbl := p.Objects['label'];
    if (lbl = nil) or IsNull(lbl, 'text') or lbl.Booleans['ignore'] then
    begin
      Inc(FCompared);
      if (la >= 0) and not lst.Element(la).Ignore and (lst.Element(la).Caption.Text <> '') then
        Miss(w + ': no words upstream, "' + lst.Element(la).Caption.Text + '" here');
      if la >= 0 then seen[la] := True;
      Continue;
    end;
    Inc(FCompared);
    if la < 0 then
    begin
      Miss(w + ': words "' + lbl.Strings['text'] + '" upstream, none here');
      Continue;
    end;
    seen[la] := True;
    le := lst.Element(la);
    { a label at opacity 0 is drawn inkless here }
    if NumAt(lbl, 'op') = 0 then
    begin
      Inc(FCompared);
      if (le.Caption.Text <> '') and (le.Style.Alpha <> 0) then
        Miss(w + ': words at opacity 0 upstream, drawn here');
      Continue;
    end;
    Inc(FCompared, 2);
    if le.Caption.Text <> lbl.Strings['text'] then
      Miss(Format('%s: words "%s" upstream, "%s" here', [w, lbl.Strings['text'], le.Caption.Text]));
    if AlignWord(le.Caption.AnchorH) <> StrOr(lbl, 'align') then
      Miss(Format('%s: words aligned %s upstream, %s here', [w, StrOr(lbl, 'align'),
        AlignWord(le.Caption.AnchorH)]));
    Same(w + ' words x', le.Caption.X, NumAt(lbl, 'x'));
    Same(w + ' words y', le.Caption.Y, NumAt(lbl, 'y'));
    Same(w + ' words turn', le.Caption.RotationRad, NumAt(lbl, 'rot'));
    Same(w + ' words opacity', le.Style.Alpha, NumAt(lbl, 'op'));
  end;
  { nothing drawn here that upstream does not draw }
  for i := 0 to lst.Count - 1 do
  begin
    el := lst.Element(i);
    if seen[i] then Continue;
    if (el.Anim.Role = carSunPiece) and (el.Anim.Series = si) then
      Miss(Format('series %d: piece %d drawn here, not upstream', [si, el.Anim.Index]));
  end;
  { containPixel }
  probes := nil;
  if (ACase.Find('probes') <> nil) and (ACase.Find('probes').JSONType = jtArray) then
    probes := ACase.Arrays['probes'];
  if (probes <> nil) and (ASeries.Find('contain') is TJSONArray) then
  begin
    cont := ASeries.Arrays['contain'];
    for k := 0 to probes.Count - 1 do
    begin
      Inc(FCompared);
      if FChart.ContainPixel(Format('{"seriesIndex":%d}', [si]),
        TJSONArray(probes.Items[k]).Floats[0], TJSONArray(probes.Items[k]).Floats[1])
        <> (cont.Strings[k] = '1') then
        Miss(Format('series %d: containPixel at probe %d is %s upstream', [si, k, cont.Strings[k]]));
    end;
  end;
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.CheckTreemap(ACase, ASeries: TJSONObject);
var
  si, k, j, i, row, at, la, sub, n: Integer;
  nodes, ghosts, crumbs, lines: TJSONArray;
  nd, rec, lbl, cr: TJSONObject;
  lst: TTyPaintList;
  el, le: TTyChartElement;
  ts: TTyTreemapSolved;
  tx, ty, sx, sy, sw, sh: Double;
  want: TTyChartColor;
  seen: array of Boolean;
  w, kind, txt, sep: string;
  animating: Boolean;

  procedure OneRect(R: TJSONObject; ARow, ASub: Integer; const AWhat: string; AGhost: Boolean);
  var jj: Integer;
  begin
    if R = nil then Exit;
    { an invisible element is not drawn }
    if (not AGhost) and R.Booleans['inv'] then
    begin
      at := FindIn(lst, si, ARow, kind);
      Inc(FCompared);
      if at >= 0 then
      begin
        seen[at] := True;
        Miss(AWhat + ': invisible upstream, drawn here');
      end;
      Exit;
    end;
    at := FindIn(lst, si, ARow, kind);
    Inc(FCompared);
    if at < 0 then
    begin
      Miss(AWhat + ': drawn upstream, not here');
      Exit;
    end;
    seen[at] := True;
    if AGhost then Inc(FGhosts) else Inc(FRects);
    el := lst.Element(at);
    tx := 0;
    ty := 0;
    if not IsNull(R, 't') then
    begin
      tx := NumAt(R, 't', 0);
      ty := NumAt(R, 't', 1);
    end;
    sx := NumAt(R, 'sh', 0);
    sy := NumAt(R, 'sh', 1);
    sw := NumAt(R, 'sh', 2);
    sh := NumAt(R, 'sh', 3);
    Same(AWhat + ' left', el.Shape.Bounds.Left, sx + tx);
    Same(AWhat + ' top', el.Shape.Bounds.Top, sy + ty);
    Same(AWhat + ' right', el.Shape.Bounds.Right, (sx + sw) + tx);
    Same(AWhat + ' bottom', el.Shape.Bounds.Bottom, (sy + sh) + ty);
    Same(AWhat + ' opacity', el.Style.Alpha, NumAt(R, 'op'));
    if not AGhost then
    begin
      Inc(FCompared);
      if el.Z2 <> R.Integers['z2'] then
        Miss(Format('%s: z2 %d upstream, %d here', [AWhat, R.Integers['z2'], el.Z2]));
      if (StrOr(R, 'fill') = '#fff') or (StrOr(R, 'fill') = 'white')
        or (StrOr(R, 'fill') = '#ffffff') then Inc(FSkipped)
      else if TyTryParseChartColor(StrOr(R, 'fill'), want) then
      begin
        Inc(FCompared);
        if (not el.Style.HasFill) or (el.Style.FillColor <> want) then
          Miss(Format('%s: fill %s upstream, %.8x here', [AWhat, StrOr(R, 'fill'),
            el.Style.FillColor]));
      end;
    end;
    { a content's words: as they are cut now, at the rect's anchor }
    if ASub <> 1 then Exit;
    if (R.Find('label') = nil) or (R.Find('label').JSONType = jtNull) then Exit;
    lbl := R.Objects['label'];
    lines := lbl.Arrays['lines'];
    txt := '';
    sep := '';
    for jj := 0 to lines.Count - 1 do
    begin
      txt := txt + sep + lines.Strings[jj];
      sep := #10;
    end;
    la := FindIn(lst, si, ARow, 'lbl', ARow + 1);
    if lbl.Booleans['ign'] or lbl.Booleans['inv']
      or (StringReplace(txt, #10, '', [rfReplaceAll]) = '') then
    begin
      Inc(FCompared);
      if (la >= 0) and not lst.Element(la).Ignore and (lst.Element(la).Caption.Text <> '') then
        Miss(AWhat + ': no words upstream, "' + lst.Element(la).Caption.Text + '" here');
      if la >= 0 then seen[la] := True;
      Exit;
    end;
    Inc(FCompared);
    if (la < 0) or lst.Element(la).Ignore then
    begin
      Miss(AWhat + ': words "' + txt + '" upstream, none here');
      Exit;
    end;
    seen[la] := True;
    le := lst.Element(la);
    if NumAt(lbl, 'op') = 0 then
    begin
      Inc(FCompared);
      if (le.Caption.Text <> '') and (le.Style.Alpha <> 0) then
        Miss(AWhat + ': words at opacity 0 upstream, drawn here');
      Exit;
    end;
    Inc(FCompared);
    if le.Caption.Text <> txt then
      Miss(Format('%s: words "%s" upstream, "%s" here', [AWhat, txt, le.Caption.Text]));
    Same(AWhat + ' words x', le.Caption.X, NumAt(lbl, 't', 0));
    Same(AWhat + ' words y', le.Caption.Y, NumAt(lbl, 't', 1));
    Same(AWhat + ' words opacity', le.Style.Alpha, NumAt(lbl, 'op'));
  end;

begin
  si := ASeries.Integers['index'];
  ts := FChart.TreemapSolved(si);
  Inc(FCompared, 2);
  if not ts.Valid then
  begin
    Miss(Format('series %d: no treemap here', [si]));
    Exit;
  end;
  if ts.ViewRoot <> ASeries.Integers['viewRoot'] then
    Miss(Format('series %d: view root %d upstream, %d here', [si,
      ASeries.Integers['viewRoot'], ts.ViewRoot]));
  animating := StrOr(ASeries, 'state') = 'animating';
  if FChart.TreemapAnimating(si) <> animating then
    Miss(Format('series %d: animating is %s upstream', [si, StrOr(ASeries, 'state')]));
  Same(Format('series %d root x', [si]), ts.Nodes[0].X, NumAt(ASeries, 'root', 0));
  Same(Format('series %d root y', [si]), ts.Nodes[0].Y, NumAt(ASeries, 'root', 1));
  Same(Format('series %d root width', [si]), ts.Nodes[0].W, NumAt(ASeries, 'root', 2));
  Same(Format('series %d root height', [si]), ts.Nodes[0].H, NumAt(ASeries, 'root', 3));
  lst := FChart.Frame;
  seen := nil;
  SetLength(seen, lst.Count);
  nodes := ASeries.Arrays['nodes'];
  for k := 0 to nodes.Count - 1 do
  begin
    nd := nodes.Objects[k];
    row := nd.Integers['di'];
    for sub := 0 to 1 do
    begin
      if sub = 0 then kind := 'bg' else kind := 'ct';
      if (nd.Find(kind) = nil) or (nd.Find(kind).JSONType = jtNull) then Continue;
      rec := nd.Objects[kind];
      OneRect(rec, row, sub, Format('series %d row %d %s', [si, row, kind]), False);
    end;
  end;
  ghosts := ASeries.Arrays['ghosts'];
  for k := 0 to ghosts.Count - 1 do
  begin
    rec := ghosts.Objects[k];
    row := rec.Integers['di'];
    kind := rec.Strings['kind'];
    OneRect(rec, row, Ord(kind = 'ct'), Format('series %d row %d %s (leaving)', [si, row, kind]), True);
  end;
  { nothing drawn here that upstream does not draw }
  for i := 0 to lst.Count - 1 do
  begin
    el := lst.Element(i);
    if seen[i] then Continue;
    if (el.Anim.Role = carTmRect) and (el.Anim.Series = si) then
      Miss(Format('series %d: row %d rect %d drawn here, not upstream', [si,
        el.Anim.Index, el.Anim.Sub]));
  end;
  { the breadcrumb }
  crumbs := ASeries.Arrays['crumbs'];
  Inc(FCompared);
  if Length(ts.Crumbs) <> crumbs.Count then
  begin
    Miss(Format('series %d: %d crumbs upstream, %d here', [si, crumbs.Count, Length(ts.Crumbs)]));
    Exit;
  end;
  for k := 0 to crumbs.Count - 1 do
  begin
    cr := crumbs.Objects[k];
    w := Format('series %d crumb %d', [si, k]);
    Inc(FCompared, 2);
    if ts.Crumbs[k].Row <> cr.Get('di', -1) then
      Miss(Format('%s: row %d upstream, %d here', [w, cr.Get('di', -1), ts.Crumbs[k].Row]));
    if ts.Crumbs[k].Text <> StrOr(cr, 'text') then
      Miss(Format('%s: "%s" upstream, "%s" here', [w, StrOr(cr, 'text'), ts.Crumbs[k].Text]));
    n := TJSONArray(cr.Find('pts')).Count div 2;
    Inc(FCompared);
    if Length(ts.Crumbs[k].Points) <> n then
    begin
      Miss(Format('%s: %d points upstream, %d here', [w, n, Length(ts.Crumbs[k].Points)]));
      Continue;
    end;
    for j := 0 to n - 1 do
    begin
      Same(Format('%s point %d x', [w, j]), ts.Crumbs[k].Points[j].X, NumAt(cr, 'pts', 2 * j));
      Same(Format('%s point %d y', [w, j]), ts.Crumbs[k].Points[j].Y, NumAt(cr, 'pts', 2 * j + 1));
    end;
    if (StrOr(cr, 'text') <> '') and not IsNull(cr, 'l') then
    begin
      Same(w + ' words x', ts.Crumbs[k].LabelX, NumAt(cr, 'l', 0));
      Same(w + ' words y', ts.Crumbs[k].LabelY, NumAt(cr, 'l', 1));
    end;
  end;
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.CheckEvents(ACase, AState: TJSONObject);
var
  evs: TJSONArray;
  ev, rr: TJSONObject;
  got: TJSONData;
  gp: TJSONObject;
  k, si, slot, row, r, gsi: Integer;
  ids: TTyStringArray;
  hier: TTyHierarchy;
  ser: TJSONData;
  opt: TJSONData;
  w, id, ks: string;
  keys: array[0..3] of string = ('x', 'y', 'width', 'height');
begin
  evs := AState.Arrays['events'];
  Inc(FCompared);
  if evs.Count <> Length(FChart.Events) then
  begin
    Miss(Format('%d action events upstream, %d here', [evs.Count, Length(FChart.Events)]));
    FChart.Events := nil;
    Exit;
  end;
  opt := ACase.Find('option');
  for k := 0 to evs.Count - 1 do
  begin
    ev := evs.Objects[k];
    Inc(FEvents);
    w := Format('event %d', [k]);
    Inc(FCompared);
    if FChart.Events[k].EventType <> ev.Strings['type'] then
    begin
      Miss(Format('%s: %s upstream, %s here', [w, ev.Strings['type'], FChart.Events[k].EventType]));
      Continue;
    end;
    try
      got := GetJSON(FChart.Events[k].Payload);
    except
      got := nil;
    end;
    if not (got is TJSONObject) then
    begin
      got.Free;
      Miss(w + ': the payload is no object');
      Continue;
    end;
    gp := TJSONObject(got);
    try
      Inc(FCompared);
      if StrOr(gp, 'direction') <> StrOr(ev, 'direction') then
        Miss(Format('%s: direction "%s" upstream, "%s" here', [w, StrOr(ev, 'direction'),
          StrOr(gp, 'direction')]));
      { a gesture's target is a node upstream, its id here }
      if (not IsNull(ev, 'target')) and IsNull(ev, 'targetNode') then
      begin
        si := ev.Get('seriesIndex', -1);
        Inc(FCompared);
        { [R2-B] a treemap view's own dispatch names its series by id, as
          upstream's (the fixture turned that into the index) }
        gsi := gp.Get('seriesIndex', -1);
        if gp.Find('seriesId') <> nil then
          for r := 0 to 15 do
            if StringReplace(FChart.SeriesModelId(r), #0, '', [rfReplaceAll])
              = StringReplace(gp.Strings['seriesId'], #0, '', [rfReplaceAll]) then
            begin
              gsi := r;
              Break;
            end;
        if gsi <> si then
          Miss(Format('%s: series %d upstream, %d here', [w, si, gsi]));
        id := StrOr(gp, 'targetNode');
        row := -1;
        if FChart.SunburstSolved(si).Valid then hier := FChart.SunburstSolved(si).Hier
        else hier := FChart.TreemapSolved(si).Hier;
        ser := nil;
        if (opt is TJSONObject) and (TJSONObject(opt).Find('series') is TJSONArray) then
          ser := TJSONArray(TJSONObject(opt).Find('series')).Items[si];
        if ser is TJSONObject then ids := TyHierIds(hier, TJSONObject(ser))
        else ids := TyHierIds(hier, nil);
        { fpjson drops a  : the generated ids are compared without it }
        for r := 0 to High(ids) do
          if StringReplace(ids[r], #0, '', [rfReplaceAll]) = StringReplace(id, #0, '', [rfReplaceAll]) then
          begin
            row := r;
            Break;
          end;
        Inc(FCompared);
        if row <> ev.Integers['target'] then
          Miss(Format('%s: target %d upstream, %d (%s) here', [w, ev.Integers['target'], row, id]));
      end;
      if not IsNull(ev, 'targetNode') then
      begin
        Inc(FCompared);
        if StrOr(gp, 'targetNode') <> StrOr(ev, 'targetNode') then
          Miss(Format('%s: targetNode "%s" upstream, "%s" here', [w, StrOr(ev, 'targetNode'),
            StrOr(gp, 'targetNode')]));
      end;
      { [R2-I1] a case with keys: the payload's own keys in order }
      if ev.Find('keys') <> nil then
      begin
        Inc(FCompared);
        Inc(FKeyed);
        ks := '';
        for r := 0 to gp.Count - 1 do
        begin
          if r > 0 then ks := ks + ',';
          ks := ks + gp.Names[r];
        end;
        if ks <> ev.Strings['keys'] then
          Miss(Format('%s: keys "%s" upstream, "%s" here', [w, ev.Strings['keys'], ks]));
        if ev.Booleans['fromView'] and not ((gp.Find('from') <> nil)
          and (gp.Find('from').JSONType = jtString)) then
          Miss(w + ': no view uid as from');
      end;
      if not IsNull(ev, 'rootRect') then
      begin
        Inc(FCompared);
        if not (gp.Find('rootRect') is TJSONObject) then
        begin
          Miss(w + ': a rootRect upstream, none here');
          Continue;
        end;
        rr := TJSONObject(gp.Find('rootRect'));
        for slot := 0 to 3 do
        begin
          Inc(FCompared);
          if Abs(rr.Get(keys[slot], NaN) - NumAt(ev, 'rootRect', slot))
            > 1e-12 * Math.Max(1, Abs(NumAt(ev, 'rootRect', slot))) then
            Miss(Format('%s: rootRect %s %s upstream, %s here', [w, keys[slot],
              Fmt(NumAt(ev, 'rootRect', slot)), Fmt(rr.Get(keys[slot], NaN))]));
        end;
      end;
    finally
      gp.Free;
    end;
  end;
  FChart.Events := nil;
end;

type
  TTipRow = record
    Marker, Name, Value: string;
    HasMarker, HasName, HasValue: Boolean;
  end;

function TipRowsText(ABlock: TTyTooltipBlock): string;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j, k: Integer;
  row: TTipRow;

  function Q(AHas: Boolean; const S: string): string;
  begin
    if AHas then Result := '"' + S + '"' else Result := 'null';
  end;

begin
  Result := '';
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  for i := 0 to High(lines) do
  begin
    for k := 1 to lines[i].BlankLinesBefore do Result := Result + '{null null null}';
    row := Default(TTipRow);
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

procedure TAdvChartSunburstTreemapInteractOracleTest.CheckTip(AState: TJSONObject);
var
  tip: TJSONObject;
  lines: TJSONArray;
  k: Integer;
  want, got: string;
  block: TTyTooltipBlock;

  function Q(ARow: TJSONObject; const AKey: string): string;
  begin
    if IsNull(ARow, AKey) then Result := 'null' else Result := '"' + ARow.Strings[AKey] + '"';
  end;

begin
  { upstream records the show a step made; a step that made none leaves the
    last box to its hide delay, here as there }
  if (AState.Find('tip') = nil) or (AState.Find('tip').JSONType = jtNull) then Exit;
  tip := AState.Objects['tip'];
  Inc(FTips);
  Inc(FCompared);
  if FChart.TooltipShownWhich <> tip.Strings['which'] then
  begin
    Miss(Format('the tooltip shows %s upstream, %s here', [tip.Strings['which'],
      FChart.TooltipShownWhich]));
    Exit;
  end;
  lines := tip.Arrays['lines'];
  want := '';
  for k := 0 to lines.Count - 1 do
    want := want + '{' + Q(lines.Objects[k], 'marker') + ' ' + Q(lines.Objects[k], 'name')
      + ' ' + Q(lines.Objects[k], 'value') + '}';
  block := FChart.ContentOf(FChart.TooltipShownDatum);
  try
    if block = nil then got := '' else got := TipRowsText(block);
  finally
    block.Free;
  end;
  Inc(FCompared);
  if got <> want then Miss('the tooltip reads ' + got + ' here, ' + want + ' upstream');
end;

procedure TAdvChartSunburstTreemapInteractOracleTest.TestEveryDrillZoomAndRoamLandsWhereUpstreamPutsIt;
var
  cases, steps, states, series: TJSONArray;
  cs, st, se, opt: TJSONObject;
  c, k, s, w, h: Integer;
  anim: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    FName := cs.Strings['id'];
    Inc(FCases);
    anim := Pos('anim', cs.Strings['group']) > 0;
    NewChart(anim);
    w := cs.Integers['W'];
    h := cs.Integers['H'];
    FChart.SetBounds(0, 0, w, h);
    { upstream's default palette, which the default theme's ramp is not }
    opt := TJSONObject(cs.Objects['option'].Clone);
    try
      if opt.Find('color') = nil then
        opt.Add('color', GetJSON('["#5070dd","#b6d634","#505372","#ff994d",'
          + '"#0ca8df","#ffd10a","#fb628b","#785db0","#3fbe95"]'));
      FChart.Option := opt.AsJSON;
    finally
      opt.Free;
    end;
    steps := cs.Arrays['steps'];
    states := cs.Arrays['states'];
    for k := 0 to states.Count - 1 do
    begin
      FName := Format('%s state %d', [cs.Strings['id'], k]);
      try
        if k > 0 then Step(steps.Objects[k - 1], w, h);
        RenderNow(w, h);
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Break;
        end;
      end;
      st := states.Objects[k];
      { upstream's first render still entering: the port has no enter }
      if anim and (k = 0) then
      begin
        FChart.Events := nil;
        Continue;
      end;
      Inc(FStates);
      if anim then Inc(FFrames);
      CheckEvents(cs, st);
      series := st.Arrays['series'];
      for s := 0 to series.Count - 1 do
      begin
        se := series.Objects[s];
        if se.Strings['type'] = 'sunburst' then CheckSunburst(cs, se)
        else CheckTreemap(cs, se);
      end;
      { a hover's tooltip (upstream records the show a step made) }
      if (k > 0) and (steps.Objects[k - 1].Find('hover') <> nil) then
        CheckTip(st);
    end;
  end;
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('compared %d cases, %d states (%d animated), %d pieces, %d rects, '
    + '%d leaving, %d tooltips, %d events (%d theme fills passed over)',
    [FCases, FStates, FFrames, FPieces, FRects, FGhosts, FTips, FEvents, FSkipped]),
    (FCases >= 20) and (FPieces >= 300) and (FRects >= 500) and (FGhosts >= 20)
    and (FTips >= 8) and (FEvents >= 30) and (FKeyed >= 2));
end;

{ ==================== by hand ==================== }

procedure TAdvChartSunburstTreemapInteractTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TStiProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.OnChartEvent := @FChart.OnEvent;
end;

procedure TAdvChartSunburstTreemapInteractTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartSunburstTreemapInteractTest.RenderNow(AW: Integer; AH: Integer);
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartSunburstTreemapInteractTest.Show(const AOption: string; AW: Integer;
  AH: Integer);
begin
  FChart.SetBounds(0, 0, AW, AH);
  FChart.Option := AOption;
  RenderNow(AW, AH);
end;

const
  cSb = '{"series":[{"type":"sunburst","name":"S","data":[{"name":"a","children":'
    + '[{"name":"a1","value":3},{"name":"a2","value":2}]},{"name":"b","value":4}]}]}';
  cTm = '{"series":[{"type":"treemap","name":"T","animation":false,"data":[{"name":"a","children":'
    + '[{"name":"a1","value":6},{"name":"a2","value":4}]},{"name":"b","value":5},'
    + '{"name":"c","value":3}]}]}';

procedure TAdvChartSunburstTreemapInteractTest.TestANewOptionForgetsTheViewRoot;
begin
  Show(cSb);
  AssertTrue('the drill is taken',
    FChart.DispatchAction('{"type":"sunburstRootToNode","targetNode":"a"}'));
  RenderNow;
  AssertEquals('drilled into a', 1, FChart.SunburstViewRoot(0));
  { resetViewRoot finds no such node in the new tree (the same text would
    be no new option at all) }
  Show(StringReplace(cSb, '"name":"S"', '"name":"S2"', []));
  AssertEquals('a new option: back at the root', 0, FChart.SunburstViewRoot(0));
  AssertFalse('and no return circle to contain the centre',
    FChart.ContainPixel('{"seriesIndex":0}', 200, 200));
end;

procedure TAdvChartSunburstTreemapInteractTest.TestAMergeRebuildsTheTreeAndForgetsTheViewRoot;
begin
  Show(cTm);
  AssertTrue(FChart.DispatchAction('{"type":"treemapRootToNode","targetNode":"a"}'));
  RenderNow;
  AssertEquals('drilled into a', 1, FChart.TreemapSolved(0).ViewRoot);
  { backwardCompat writes `series` into every option, so every merge visits
    the series, rebuilds its data and makes a new tree: resetViewRoot finds
    its node in none }
  FChart.MergeOption('{"title":{"text":"x"}}');
  RenderNow;
  AssertEquals('a merge makes a new tree', 0, FChart.TreemapSolved(0).ViewRoot);
end;

procedure TAdvChartSunburstTreemapInteractTest.TestAnUnknownTargetLeavesTheViewAlone;
begin
  Show(cSb);
  AssertTrue(FChart.DispatchAction('{"type":"sunburstRootToNode","targetNode":"a"}'));
  RenderNow;
  FChart.Events := nil;
  { the action still runs and its event goes, with no direction }
  AssertTrue(FChart.DispatchAction('{"type":"sunburstRootToNode","targetNode":"zz"}'));
  RenderNow;
  AssertEquals('the view root is kept', 1, FChart.SunburstViewRoot(0));
  AssertEquals('one event', 1, Length(FChart.Events));
  AssertTrue('no direction', Pos('direction', FChart.Events[0].Payload) = 0);
  { a number never matches an id (getNodeById compares with ===) }
  AssertTrue(FChart.DispatchAction('{"type":"sunburstRootToNode","targetNodeId":1}'));
  RenderNow;
  AssertEquals('a numeric id finds nothing', 1, FChart.SunburstViewRoot(0));
end;

procedure TAdvChartSunburstTreemapInteractTest.TestASunburstActionNeedsItsType;
begin
  Show(cSb);
  { a treemap's action does not drill a sunburst }
  FChart.DispatchAction('{"type":"treemapRootToNode","targetNode":"a"}');
  RenderNow;
  AssertEquals('not drilled', 0, FChart.SunburstViewRoot(0));
end;

procedure TAdvChartSunburstTreemapInteractTest.TestTheBreadcrumbIsNotAClickOnTheRectUnderIt;
var
  ts: TTyTreemapSolved;
  x, y: Integer;
begin
  Show(cTm, 600, 400);
  { a pan that puts the treemap under its own breadcrumb }
  FChart.Down(300, 200);
  FChart.Move(300, 300);
  FChart.Up(300, 300);
  RenderNow(600, 400);
  ts := FChart.TreemapSolved(0);
  AssertTrue('a breadcrumb', Length(ts.Crumbs) > 0);
  x := Round((ts.Crumbs[0].Points[0].X + ts.Crumbs[0].Points[1].X) / 2);
  y := Round((ts.Crumbs[0].Points[0].Y + ts.Crumbs[0].Points[2].Y) / 2);
  FChart.Events := nil;
  FChart.Down(x, y);
  FChart.Up(x, y);
  RenderNow(600, 400);
  { the crumb's own: a zoom to the root, not to the rect beneath }
  AssertEquals('one event', 1, Length(FChart.Events));
  AssertEquals('a zoom', 'treemapzoomtonode', FChart.Events[0].EventType);
  AssertTrue('to the root', Pos('"targetNode" : "T"', FChart.Events[0].Payload) > 0);
end;

procedure TAdvChartSunburstTreemapInteractTest.TestARoamOffTreemapDoesNotPan;
begin
  Show(StringReplace(cTm, '"animation":false', '"animation":false,"roam":false', []), 600, 400);
  FChart.Down(300, 200);
  FChart.Move(320, 220);
  FChart.Up(320, 220);
  RenderNow(600, 400);
  AssertEquals('no pan', 0, FChart.TreemapSolved(0).Nodes[0].X);
  AssertEquals('no event', 0, Length(FChart.Events));
end;

initialization
  RegisterTest(TAdvChartSunburstTreemapInteractOracleTest);
  RegisterTest(TAdvChartSunburstTreemapInteractTest);
end.
