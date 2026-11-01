unit test.advchart.universaltransition6;
{$mode objfpc}{$H+}
{$Q-}{$R-}
{ THE UNIVERSAL TRANSITION'S STRUCTURAL GAPS, held to upstream. [R6-C]

  tests/fixtures/advchart-universal-transition6.json, from the real ECharts
  6.1 build under the hand-driven clock (tools/advchart-oracle/
  universal-transition6.js).

  Steps of setOption or dispatchAction -- the first at T0, each next one
  after the one before has run out (T + 10000) or `after` ms into it,
  notMerge unless the step merges -- recorded at the last T + each sample:
  the style track past fill / stroke / lineWidth / opacity (the shadow's
  four keys, fillOpacity / strokeOpacity, gradients); an old series the
  legend has switched off (in the store, its items without elements: the
  items they pair with fade in); the children of a combining host (each one
  hit and drawn at the host's place; a leaving host draws them); the
  encoded group dimensions read from the store; the view groups of a tree
  and a sankey.

  TestRestPathsAsUpstream / TestEveryTransitionAsUpstream: as
  universaltransition5's -- every item path at rest, and at every sample
  whether it morphs, the path its morph draws, its style (here with the
  shadow, the two opacities and a gradient fill), the children it combines
  into. TestEveryChildIsHit: the pointer at the middle of each combining
  child names its host's datum, as upstream's findHover does.
  TestTheChildrenDrawInTheHostsPlace: the item paths and children in paint
  order, as the display list has them. TestALeavingHostDrawsItsChildren:
  every path drawn for the leaving bars, as upstream's display list draws
  them under the series' views. TestTheOpacitiesAreDrawn: a custom rect's
  fillOpacity is the canvas' globalAlpha for its fill. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.JsMath,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.AnimOpt,
     tyControls.AdvanceChart.AnimView, tyControls.AdvanceChart.Morph,
     tyControls.AdvanceChart.Custom,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TUt6Probe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  { the oracle's renderItems }
  TUt6Mirror = class
  public
    function OpRect(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    { the test's own: the same column at opacity 0.4 }
    function AlphaRect(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  TAdvChartUniversalTransition6Test = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TUt6Probe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FMirror: TUt6Mirror;
    FBad, FCompared, FMorphs, FPieceFrames, FRests, FStyleKeys: Integer;
    FReport: string;
    FSeen: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart;
    procedure Draw;
    function Play(ACase: TJSONObject; ACheckRest: Boolean): Double;
    procedure RunCase(ACase: TJSONObject);
    procedure CompareRest(const ACid, ASide: string; ARest: TJSONArray);
    procedure ComparePath(const AId, AOnce: string; const AData: TTyDoubleArray;
      AWant: TJSONData);
    procedure CompareStyle(const AId, AOnce: string; const AFe: TTyChartElement;
      AStyle: TJSONObject; ASample: Integer);
    procedure CompareFill(const AId, AOnce: string; const AFe: TTyChartElement;
      AWant: TJSONData);
    function CaseById(const AId: string): TJSONObject;
    function Wanted(const AId: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRestPathsAsUpstream;
    procedure TestEveryTransitionAsUpstream;
    procedure TestEveryChildIsHit;
    procedure TestTheChildrenDrawInTheHostsPlace;
    procedure TestALeavingHostDrawsItsChildren;
    procedure TestTheOpacitiesAreDrawn;
  end;

implementation

const
  cW = 400;
  cH = 300;

var
  GFix: TJSONData = nil;

function Fix: TJSONObject;
var sl: TStringList;
begin
  if GFix = nil then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
        + 'advchart-universal-transition6.json');
      GFix := GetJSON(sl.Text);
    finally
      sl.Free;
    end;
  end;
  Result := TJSONObject(GFix);
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

{ the oracle's digest: 'fnv' + count + ':' + FNV-1a 32 of the hexes joined by ',' }
function Digest(const AData: TTyDoubleArray): string;
var
  s: string;
  i: Integer;
  h: LongWord;
begin
  s := '';
  for i := 0 to High(AData) do
  begin
    if i > 0 then s := s + ',';
    s := s + Hex(AData[i]);
  end;
  h := $811C9DC5;
  for i := 1 to Length(s) do
  begin
    h := h xor Ord(s[i]);
    h := LongWord(QWord(h) * $01000193);
  end;
  Result := 'fnv' + IntToStr(Length(AData)) + ':' + LowerCase(IntToHex(h, 8));
end;

{ a key written once (the same at every sample) or per sample }
function SampleOf(AData: TJSONData; ASample: Integer): TJSONData;
begin
  if (AData <> nil) and (AData.JSONType = jtArray) then Result := AData.Items[ASample]
  else Result := AData;
end;

{ the object with a $fn key -> '@name', in place, everywhere }
procedure Materialize(AData: TJSONData);
var
  i: Integer;
  child: TJSONData;
  o: TJSONObject;
begin
  if AData is TJSONArray then
  begin
    for i := 0 to AData.Count - 1 do
    begin
      child := AData.Items[i];
      if (child is TJSONObject) and (TJSONObject(child).Find('$fn') <> nil) then
        TJSONArray(AData).Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
      else
        Materialize(child);
    end;
  end
  else if AData is TJSONObject then
  begin
    o := TJSONObject(AData);
    for i := 0 to o.Count - 1 do
    begin
      child := o.Items[i];
      if (child is TJSONObject) and (TJSONObject(child).Find('$fn') <> nil) then
        o.Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
      else
        Materialize(child);
    end;
  end;
end;

function OptionText(AData: TJSONData): string;
var c: TJSONData;
begin
  c := AData.Clone;
  try
    Materialize(c);
    Result := c.AsJSON;
  finally
    c.Free;
  end;
end;

{ ==================== the probe ==================== }

function TUt6Probe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TUt6Probe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TUt6Probe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== the renderItems ==================== }

function Num(A: Double): TJSONFloatNumber;
begin
  Result := TJSONFloatNumber.Create(A);
end;

{ RENDER.opRect: a column whose fill and stroke have opacities of their own }
function TUt6Mirror.OpRect(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var p, b: TTyDoubleArray;
begin
  p := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  b := AApi.Coord([AApi.Value(0), 0]);
  Result := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', Num(p[0] - 8), 'y', Num(p[1]), 'width', 16,
      'height', Num(b[1] - p[1])]),
    'style', TJSONObject.Create(['fill', AApi.Visual('color'), 'fillOpacity', Num(0.4),
      'stroke', '#ff994d', 'lineWidth', 2, 'strokeOpacity', Num(0.6)])]);
end;

{ the same column, no fillOpacity, at opacity 0.4 (the test's own) }
function TUt6Mirror.AlphaRect(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var p, b: TTyDoubleArray;
begin
  p := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  b := AApi.Coord([AApi.Value(0), 0]);
  Result := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', Num(p[0] - 8), 'y', Num(p[1]), 'width', 16,
      'height', Num(b[1] - p[1])]),
    'style', TJSONObject.Create(['fill', AApi.Visual('color'), 'opacity', Num(0.4)])]);
end;

{ ==================== plumbing ==================== }

procedure TAdvChartUniversalTransition6Test.SetUp;
var
  sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-text-style.json');
    FMeasure := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  FSeen := TStringList.Create;
  FBad := 0;
  FCompared := 0;
  FMorphs := 0;
  FPieceFrames := 0;
  FRests := 0;
  FStyleKeys := 0;
  FReport := '';
  FMirror := TUt6Mirror.Create;
  TyChartRegisterRenderItem('opRect', @FMirror.OpRect);
  TyChartRegisterRenderItem('alphaRect', @FMirror.AlphaRect);
end;

procedure TAdvChartUniversalTransition6Test.TearDown;
begin
  TyChartUnregisterRenderItem('opRect');
  TyChartUnregisterRenderItem('alphaRect');
  FreeAndNil(FSeen);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  FreeAndNil(FMirror);
  inherited TearDown;
end;

procedure TAdvChartUniversalTransition6Test.Miss(const AWhere: string; const AOnce: string);
begin
  Inc(FBad);
  if AOnce <> '' then
  begin
    if FSeen.IndexOf(AOnce) >= 0 then Exit;
    FSeen.Add(AOnce);
  end;
  if FSeen.Count + Ord(AOnce = '') <= 40 then
    FReport := FReport + LineEnding + '  ' + AWhere;
end;

procedure TAdvChartUniversalTransition6Test.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TUt6Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := Fix.Objects['clock'].Floats['T0'];
end;

procedure TAdvChartUniversalTransition6Test.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartUniversalTransition6Test.CaseById(const AId: string): TJSONObject;
var
  cs: TJSONArray;
  i: Integer;
begin
  cs := Fix.Arrays['charts'];
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = AId then Exit(cs.Objects[i]);
  Fail('no case ' + AId);
  Result := nil;
end;

{ TY_UT6_CASE: a comma list of case ids to run alone }
function TAdvChartUniversalTransition6Test.Wanted(const AId: string): Boolean;
var w: string;
begin
  w := GetEnvironmentVariable('TY_UT6_CASE');
  Result := (w = '') or (Pos(',' + AId + ',', ',' + w + ',') > 0);
end;

{ the order value of the APath-th path of item (series, row): the item's
  paths sorted by their order (whatever is drawn in their place); -1 none }
function OrderOfPath(AList: TTyPaintList; ASeries, ARow, APath: Integer): Integer;
var
  i, j, n, t: Integer;
  ords: array of Integer;
  el: TTyChartElement;
  seen: Boolean;
begin
  ords := nil;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if TyUtPathKey(el) = '' then Continue;
    if (el.Anim.Series <> ASeries) or (TyUtPathRow(el) <> ARow) then Continue;
    seen := False;
    for j := 0 to High(ords) do
      if ords[j] = TyUtPathOrder(el) then seen := True;
    if seen then Continue;
    n := Length(ords);
    SetLength(ords, n + 1);
    ords[n] := TyUtPathOrder(el);
    while (n > 0) and (ords[n - 1] > ords[n]) do
    begin
      t := ords[n - 1];
      ords[n - 1] := ords[n];
      ords[n] := t;
      Dec(n);
    end;
  end;
  if (APath < 0) or (APath > High(ords)) then Result := -1 else Result := ords[APath];
end;

{ the place of the frame element's path among its item's (OrderOfPath's
  inverse); -1 none }
function PlaceOfPath(AList: TTyPaintList; const AEl: TTyChartElement): Integer;
var k, o: Integer;
begin
  for k := 0 to 15 do
  begin
    o := OrderOfPath(AList, AEl.Anim.Series, TyUtPathRow(AEl), k);
    if o < 0 then Break;
    if o = TyUtPathOrder(AEl) then Exit(k);
  end;
  Result := -1;
end;

{ the frame element of item path (series, row, place) and child APiece (0:
  the path itself); -1 for none }
function FindPath(AList: TTyPaintList; ASeries, ARow, APath: Integer; APiece: Integer = 0): Integer;
var
  i, o: Integer;
  el: TTyChartElement;
begin
  o := OrderOfPath(AList, ASeries, ARow, APath);
  if o < 0 then Exit(-1);
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if TyUtPathKey(el) = '' then Continue;
    if (el.Anim.Series = ASeries) and (TyUtPathRow(el) = ARow) and (TyUtPathOrder(el) = o)
      and (el.Anim.UtPiece = APiece) then Exit(i);
  end;
  Result := -1;
end;

function KeyOfPath(AList: TTyPaintList; ASeries, ARow, APath: Integer): string;
var
  i, o: Integer;
  el: TTyChartElement;
begin
  Result := '';
  o := OrderOfPath(AList, ASeries, ARow, APath);
  if o < 0 then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if TyUtPathKey(el) = '' then Continue;
    if (el.Anim.Series = ASeries) and (TyUtPathRow(el) = ARow) and (TyUtPathOrder(el) = o) then
      Exit(TyUtPathKey(el));
  end;
end;

{ the case's steps the oracle's way; the last one's T. ACheckRest: the old
  item paths at rest compared before the last step }
function TAdvChartUniversalTransition6Test.Play(ACase: TJSONObject; ACheckRest: Boolean): Double;
var
  steps: TJSONArray;
  st: TJSONObject;
  i: Integer;
  t, k, after: Double;
  cid, opts: string;
begin
  cid := ACase.Strings['id'];
  steps := ACase.Arrays['steps'];
  t := Fix.Objects['clock'].Floats['T0'];
  NewChart;
  for i := 0 to steps.Count - 1 do
  begin
    st := steps.Objects[i];
    if i > 0 then
    begin
      if st.Find('after').JSONType <> jtNumber then
      begin
        k := 16;
        while k <= 5000 do
        begin
          FChart.AnimTick(t + k);
          k := k + 250;
        end;
        t := t + Fix.Objects['clock'].Floats['gap'];
      end
      else
      begin
        after := st.Floats['after'];
        FChart.AnimTick(t + 16);
        Draw;
        FChart.AnimTick(t + after / 2);
        Draw;
        FChart.AnimTick(t + after);
        Draw;
        t := t + after;
      end;
      if ACheckRest and (i = steps.Count - 1) and (ACase.Find('oldRest') <> nil) then
        CompareRest(cid, 'old', ACase.Arrays['oldRest']);
    end;
    FChart.AnimNow := t;
    if st.Find('action') is TJSONObject then
      AssertTrue(cid + ': step ' + IntToStr(i) + ' dispatches',
        FChart.DispatchAction(st.Objects['action'].AsJSON))
    else if i = 0 then
      FChart.Option := OptionText(st.Elements['option'])
    else
    begin
      if st.Booleans['merge'] then opts := '{"notMerge":false}' else opts := '{"notMerge":true}';
      AssertTrue(cid + ': step ' + IntToStr(i) + ' sets',
        FChart.SetOption(OptionText(st.Elements['option']), opts));
    end;
    AssertEquals(cid + ': step ' + IntToStr(i) + ' parses', '', FChart.OptionError);
    if i = 0 then FChart.SetBounds(0, 0, cW, cH);
    Draw;
    if GetEnvironmentVariable('TY_UT6_DUMP') = '1' then
      WriteLn(Format('%s step %d: %d elements, error "%s"', [cid, i, FChart.Frame.Count,
        FChart.OptionError]));
  end;
  Result := t;
end;

{ ==================== the cases ==================== }

function PresentAt(AEl: TJSONObject; ASample: Integer): Boolean;
var d: TJSONData;
begin
  d := AEl.Find('present');
  if (d = nil) or (d.JSONType <> jtArray) then Exit(True);
  Result := d.Items[ASample].AsBoolean;
end;

function FlagAt(AEl: TJSONObject; const AKey: string; ASample: Integer): Boolean;
var d: TJSONData;
begin
  d := AEl.Find(AKey);
  Result := (d is TJSONArray) and d.Items[ASample].AsBoolean;
end;

{ a frame element's path as PathProxy data: its commands }
function CmdsData(const AEl: TTyChartElement): TTyDoubleArray;
var
  i, n: Integer;
  c: TTyPathCmd;

  procedure Put(V: Double);
  begin
    SetLength(Result, n + 1);
    Result[n] := V;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  for i := 0 to High(AEl.Shape.Cmds) do
  begin
    c := AEl.Shape.Cmds[i];
    case c.Kind of
      pckMove: begin Put(1); Put(c.X); Put(c.Y); end;
      pckLine: begin Put(2); Put(c.X); Put(c.Y); end;
      pckCurve: begin Put(3); Put(c.X1); Put(c.Y1); Put(c.X2); Put(c.Y2); Put(c.X); Put(c.Y); end;
      pckClose: Put(6);
    end;
  end;
end;

procedure TAdvChartUniversalTransition6Test.ComparePath(const AId, AOnce: string;
  const AData: TTyDoubleArray; AWant: TJSONData);
var k: Integer;
begin
  Inc(FCompared);
  if AWant = nil then
  begin
    Miss(AId + ': no path upstream', AOnce + 'nod');
    Exit;
  end;
  if AWant.JSONType = jtString then
  begin
    if Digest(AData) <> AWant.AsString then
      Miss(Format('%s: the path %s, upstream %s', [AId, Digest(AData), AWant.AsString]), AOnce + 'd');
    Exit;
  end;
  if Length(AData) <> AWant.Count then
  begin
    Miss(Format('%s: the path has %d numbers, upstream %d', [AId, Length(AData), AWant.Count]),
      AOnce + 'dlen');
    Exit;
  end;
  for k := 0 to High(AData) do
    if Hex(AData[k]) <> AWant.Items[k].AsString then
    begin
      Miss(Format('%s: the path [%d] %s, upstream %s', [AId, k, FloatToStr(AData[k]),
        FloatToStr(FromHex(AWant.Items[k].AsString))]), AOnce + 'd');
      Exit;
    end;
end;

{ A GRADIENT FILL against upstream's: its kind, its numbers and its stops
  (each colour as it parses) }
procedure TAdvChartUniversalTransition6Test.CompareFill(const AId, AOnce: string;
  const AFe: TTyChartElement; AWant: TJSONData);
var
  w: TJSONObject;
  g: TTyChartGradient;
  stops: TJSONArray;
  k: Integer;
  want: TTyChartColor;
  bad: string;

  procedure Coord(const AKey: string; AGot: Double);
  var d: TJSONData;
  begin
    d := w.Find(AKey);
    if (d <> nil) and (d.JSONType = jtString) and (Hex(AGot) <> d.AsString) and (bad = '') then
      bad := Format('%s %g, upstream %g', [AKey, AGot, FromHex(d.AsString)]);
  end;

begin
  Inc(FCompared);
  Inc(FStyleKeys);
  w := TJSONObject(AWant);
  g := AFe.Style.FillGradient;
  if not AFe.Style.HasFill or (g.Kind = cgkNone) then
  begin
    Miss(AId + ': no gradient fill here, upstream a ' + w.Strings['type'], AOnce + 'grad0');
    Exit;
  end;
  bad := '';
  if (w.Strings['type'] = 'radial') <> (g.Kind = cgkRadial) then bad := 'the kind';
  if g.Kind = cgkRadial then
  begin
    Coord('x', g.X);
    Coord('y', g.Y);
    Coord('r', g.R);
  end
  else
  begin
    Coord('x', g.X);
    Coord('y', g.Y);
    Coord('x2', g.X2);
    Coord('y2', g.Y2);
  end;
  stops := w.Arrays['stops'];
  if (bad = '') and (Length(g.Stops) <> stops.Count) then
    bad := Format('%d stops, upstream %d', [Length(g.Stops), stops.Count]);
  if bad = '' then
    for k := 0 to stops.Count - 1 do
    begin
      if Hex(g.Stops[k].Offset) <> stops.Arrays[k].Strings[0] then
      begin
        bad := Format('stop %d at %g, upstream %g', [k, g.Stops[k].Offset,
          FromHex(stops.Arrays[k].Strings[0])]);
        Break;
      end;
      if not TyTryParseChartColor(stops.Arrays[k].Strings[1], want) then
      begin
        bad := 'stop ' + IntToStr(k) + ' ' + stops.Arrays[k].Strings[1] + ' does not parse';
        Break;
      end;
      if g.Stops[k].Color <> want then
      begin
        bad := Format('stop %d %s, upstream %s', [k, IntToHex(g.Stops[k].Color, 8),
          stops.Arrays[k].Strings[1]]);
        Break;
      end;
    end;
  if bad <> '' then Miss(AId + ': the gradient: ' + bad, AOnce + 'grad');
end;

procedure TAdvChartUniversalTransition6Test.CompareStyle(const AId, AOnce: string;
  const AFe: TTyChartElement; AStyle: TJSONObject; ASample: Integer);
var
  sv, sb, sx, sy: TJSONData;
  want: TTyChartColor;
  v: Double;
begin
  sv := SampleOf(AStyle.Find('fill'), ASample);
  { 'none' fills nothing }
  if (sv <> nil) and (sv.JSONType = jtString) and (sv.AsString = 'none') then
  begin
    Inc(FCompared);
    if AFe.Style.HasFill and (AFe.Shape.Kind <> cskPolyline) then
      Miss(AId + ': a fill here, none upstream', AOnce + 'fill');
  end
  else if sv is TJSONObject then
    CompareFill(AId, AOnce, AFe, sv)
  else if (sv <> nil) and (sv.JSONType = jtString) and (sv.AsString <> 'transparent') then
  begin
    Inc(FCompared);
    if not TyTryParseChartColor(sv.AsString, want) then
      Miss(AId + ': fill ' + sv.AsString + ' does not parse')
    else if (not AFe.Style.HasFill) or (AFe.Style.FillColor <> want)
      or (AFe.Style.FillGradient.Kind <> cgkNone) then
      Miss(Format('%s: fill %s, upstream %s', [AId, IntToHex(AFe.Style.FillColor, 8),
        sv.AsString]), AOnce + 'fill');
  end;
  sv := SampleOf(AStyle.Find('stroke'), ASample);
  if (sv <> nil) and (sv.JSONType = jtString) and (sv.AsString <> 'transparent') then
  begin
    Inc(FCompared);
    if not TyTryParseChartColor(sv.AsString, want) then
      Miss(AId + ': stroke ' + sv.AsString + ' does not parse')
    else if AFe.Style.StrokeColor <> want then
      Miss(Format('%s: stroke %s, upstream %s', [AId, IntToHex(AFe.Style.StrokeColor, 8),
        sv.AsString]), AOnce + 'stroke');
    sv := SampleOf(AStyle.Find('lineWidth'), ASample);
    if (sv <> nil) and (sv.JSONType = jtString) then
    begin
      Inc(FCompared);
      if Hex(AFe.Style.StrokeWidthLogical) <> sv.AsString then
        Miss(Format('%s: lineWidth %s, upstream %s', [AId, FloatToStr(AFe.Style.StrokeWidthLogical),
          FloatToStr(FromHex(sv.AsString))]), AOnce + 'lw');
    end;
    { strokeOpacity, where it strokes }
    sv := SampleOf(AStyle.Find('strokeOpacity'), ASample);
    if (sv <> nil) and (sv.JSONType = jtString) then
    begin
      Inc(FCompared);
      Inc(FStyleKeys);
      if AFe.Style.HasStrokeOpacity then v := AFe.Style.StrokeOpacity else v := 1;
      if Hex(v) <> sv.AsString then
        Miss(Format('%s: strokeOpacity %g, upstream %g', [AId, v, FromHex(sv.AsString)]),
          AOnce + 'sop');
    end;
  end;
  sv := SampleOf(AStyle.Find('opacity'), ASample);
  if (sv <> nil) and (sv.JSONType = jtString) then
  begin
    Inc(FCompared);
    if Hex(AFe.Style.Alpha) <> sv.AsString then
      Miss(Format('%s: opacity %s, upstream %s', [AId, FloatToStr(AFe.Style.Alpha),
        FloatToStr(FromHex(sv.AsString))]), AOnce + 'op');
  end;
  { fillOpacity, where it fills }
  sv := SampleOf(AStyle.Find('fillOpacity'), ASample);
  if (sv <> nil) and (sv.JSONType = jtString) and AFe.Style.HasFill then
  begin
    Inc(FCompared);
    Inc(FStyleKeys);
    if AFe.Style.HasFillOpacity then v := AFe.Style.FillOpacity else v := 1;
    if Hex(v) <> sv.AsString then
      Miss(Format('%s: fillOpacity %g, upstream %g', [AId, v, FromHex(sv.AsString)]),
        AOnce + 'fop');
  end;
  { THE SHADOW: its three numbers, and its colour where it casts one }
  sb := SampleOf(AStyle.Find('shadowBlur'), ASample);
  sx := SampleOf(AStyle.Find('shadowOffsetX'), ASample);
  sy := SampleOf(AStyle.Find('shadowOffsetY'), ASample);
  if (sb <> nil) and (sb.JSONType = jtString) and (sx <> nil) and (sx.JSONType = jtString)
    and (sy <> nil) and (sy.JSONType = jtString) then
  begin
    Inc(FCompared, 3);
    Inc(FStyleKeys, 3);
    if Hex(AFe.Style.ShadowBlur) <> sb.AsString then
      Miss(Format('%s: shadowBlur %g, upstream %g', [AId, AFe.Style.ShadowBlur,
        FromHex(sb.AsString)]), AOnce + 'sb');
    if Hex(AFe.Style.ShadowOffsetX) <> sx.AsString then
      Miss(Format('%s: shadowOffsetX %g, upstream %g', [AId, AFe.Style.ShadowOffsetX,
        FromHex(sx.AsString)]), AOnce + 'sx');
    if Hex(AFe.Style.ShadowOffsetY) <> sy.AsString then
      Miss(Format('%s: shadowOffsetY %g, upstream %g', [AId, AFe.Style.ShadowOffsetY,
        FromHex(sy.AsString)]), AOnce + 'sy');
    sv := SampleOf(AStyle.Find('shadowColor'), ASample);
    if (FromHex(sb.AsString) <> 0) or (FromHex(sx.AsString) <> 0) or (FromHex(sy.AsString) <> 0) then
      if (sv <> nil) and (sv.JSONType = jtString) then
      begin
        Inc(FCompared);
        Inc(FStyleKeys);
        if not TyTryParseChartColor(sv.AsString, want) then
          Miss(AId + ': shadowColor ' + sv.AsString + ' does not parse')
        else if AFe.Style.ShadowColor <> want then
          Miss(Format('%s: shadowColor %s, upstream %s', [AId, IntToHex(AFe.Style.ShadowColor, 8),
            sv.AsString]), AOnce + 'sc');
      end;
  end;
end;

{ id 's<series>/<dataIndex>/<path>' }
procedure SplitId(const AId: string; out ASeries, ARow, APath: Integer);
var
  parts: TStringList;
begin
  parts := TStringList.Create;
  try
    parts.Delimiter := '/';
    parts.StrictDelimiter := True;
    parts.DelimitedText := Copy(AId, 2, MaxInt);
    ASeries := StrToIntDef(parts[0], -1);
    ARow := StrToIntDef(parts[1], -1);
    APath := StrToIntDef(parts[2], -1);
  finally
    parts.Free;
  end;
end;

{ every item path upstream had at rest against the port's at the layout }
procedure TAdvChartUniversalTransition6Test.CompareRest(const ACid, ASide: string;
  ARest: TJSONArray);
var
  i, k, s, r, p, at: Integer;
  it: TJSONObject;
  lst: TTyPaintList;
  data: TTyDoubleArray;
  hasM: Boolean;
  m: TTyMat2D;
  wm: TJSONData;
  id: string;
begin
  lst := FChart.Frame;
  if GetEnvironmentVariable('TY_UT6_DUMP') = '1' then
    for i := 0 to lst.Count - 1 do
      WriteLn(Format('%s %s el %d role %d s %d i %d sub %d kind %d key %s', [ACid, ASide, i,
        Ord(lst.Element(i).Anim.Role), lst.Element(i).Anim.Series, lst.Element(i).Anim.Index,
        lst.Element(i).Anim.Sub, Ord(lst.Element(i).Shape.Kind), TyUtPathKey(lst.Element(i))]));
  for i := 0 to ARest.Count - 1 do
  begin
    it := ARest.Objects[i];
    id := Format('%s %s %s', [ACid, ASide, it.Strings['id']]);
    SplitId(it.Strings['id'], s, r, p);
    at := FindPath(lst, s, r, p);
    Inc(FCompared);
    Inc(FRests);
    if at < 0 then
    begin
      Miss(id + ' (' + it.Strings['type'] + '): no such path here', ACid + ASide + 'none' + it.Strings['type']);
      Continue;
    end;
    TyUtLayoutPath(lst.Element(at), data, hasM, m);
    ComparePath(id, ACid + ASide + 'rest', data, it.Elements['d']);
    wm := it.Find('m');
    Inc(FCompared);
    { an identity matrix upstream keeps is no transform's numbers }
    if (wm <> nil) and (wm.JSONType = jtArray) and (not hasM)
      and (wm.Items[0].AsString = Hex(1)) and (wm.Items[1].AsString = Hex(0))
      and (wm.Items[2].AsString = Hex(0)) and (wm.Items[3].AsString = Hex(1))
      and (wm.Items[4].AsString = Hex(0)) and (wm.Items[5].AsString = Hex(0)) then
      wm := nil;
    if (wm = nil) or (wm.JSONType = jtNull) then
    begin
      if hasM then Miss(id + ': a transform here, none upstream', ACid + ASide + 'm0');
    end
    else if not hasM then
      Miss(id + ': no transform here', ACid + ASide + 'm1')
    else
      for k := 0 to 5 do
        if Hex(m[k]) <> wm.Items[k].AsString then
        begin
          Miss(Format('%s: transform [%d] %s, upstream %s', [id, k, FloatToStr(m[k]),
            FloatToStr(FromHex(wm.Items[k].AsString))]), ACid + ASide + 'm');
          Break;
        end;
  end;
end;

procedure TAdvChartUniversalTransition6Test.RunCase(ACase: TJSONObject);
var
  samples, els, pcs: TJSONArray;
  s, e, at, pk_, ser, row, pth: Integer;
  el, pc: TJSONObject;
  t1: Double;
  id, cid, once, key: string;
  frm: TTyPaintList;
  fe: TTyChartElement;
  p, pp: TTyChartAnimProxy;
  isMorph, isComb, portMorph: Boolean;
  v: TTyAnimValue;
  sv: TJSONData;
begin
  cid := ACase.Strings['id'];
  t1 := Play(ACase, False);
  samples := ACase.Arrays['samples'];
  els := ACase.Arrays['elements'];
  for s := 0 to samples.Count - 1 do
  begin
    if s > 0 then FChart.AnimTick(t1 + samples.Items[s].AsFloat);
    Draw;
    frm := FChart.Frame;
    for e := 0 to els.Count - 1 do
    begin
      el := els.Objects[e];
      if not el.Booleans['item'] then Continue;
      id := Format('%s t=%s %s', [cid, samples.Items[s].AsString, el.Strings['id']]);
      once := cid + el.Strings['id'];
      ser := el.Integers['series'];
      row := el.Integers['dataIndex'];
      pth := el.Integers['path'];
      at := FindPath(frm, ser, row, pth);
      key := KeyOfPath(frm, ser, row, pth);
      if key <> '' then p := FChart.AnimFindProxy(ser, row, key) else p := nil;
      isComb := FlagAt(el, 'comb', s);
      Inc(FCompared);
      if isComb <> ((p <> nil) and p.CombineOn) then
        Miss(Format('%s: combining %s here, upstream %s', [id, BoolToStr((p <> nil) and p.CombineOn, True),
          BoolToStr(isComb, True)]), once + 'comb' + IntToStr(Ord(isComb)));
      if not PresentAt(el, s) then
      begin
        if at >= 0 then Miss(id + ': drawn here, not upstream', once + 'gone');
        Continue;
      end;
      if isComb then
      begin
        { THE CHILDREN, drawn in its place }
        if (p = nil) or not p.CombineOn then Continue;
        pcs := el.Arrays['pieces'];
        Inc(FCompared);
        if p.PieceCount <> pcs.Count then
        begin
          Miss(Format('%s: %d children here, upstream %d', [id, p.PieceCount, pcs.Count]), once + 'pc');
          Continue;
        end;
        for pk_ := 0 to pcs.Count - 1 do
        begin
          pc := pcs.Objects[pk_];
          if not FlagAt(pc, 'present', s) then Continue;
          at := FindPath(frm, ser, row, pth, pk_ + 1);
          if at < 0 then
          begin
            Miss(Format('%s child %d: not drawn', [id, pk_]), once + 'pcnone');
            Continue;
          end;
          fe := frm.Element(at);
          pp := p.Piece(pk_);
          v := pp.GetAnimProp('__morphT');
          portMorph := (v.Kind = avkNumber) and (not IsNan(v.Num)) and (v.Num >= 0);
          isMorph := FlagAt(pc, 'morph', s);
          Inc(FCompared);
          if isMorph <> portMorph then
            Miss(Format('%s child %d: morphing %s here, upstream %s', [id, pk_,
              BoolToStr(portMorph, True), BoolToStr(isMorph, True)]), once + 'pcm' + IntToStr(Ord(isMorph)));
          if isMorph and pp.MorphOn then
          begin
            Inc(FPieceFrames);
            ComparePath(Format('%s child %d', [id, pk_]), once + 'pc', CmdsData(fe),
              pc.Arrays['d'].Items[s]);
          end;
          CompareStyle(Format('%s child %d', [id, pk_]), once + 'pcs', fe, pc.Objects['style'], s);
        end;
        Continue;
      end;
      if at < 0 then
      begin
        Miss(id + ': no element here', once + 'none');
        Continue;
      end;
      fe := frm.Element(at);
      { THE MORPH }
      isMorph := FlagAt(el, 'morph', s);
      Inc(FCompared);
      if isMorph <> ((p <> nil) and p.MorphOn) then
        Miss(Format('%s: morphing %s here, upstream %s', [id, BoolToStr((p <> nil) and p.MorphOn, True),
          BoolToStr(isMorph, True)]), once + 'morph' + IntToStr(Ord(isMorph)));
      if isMorph then
      begin
        Inc(FMorphs);
        ComparePath(id, once, CmdsData(fe), el.Arrays['d'].Items[s]);
      end;
      { a symbol scaled to nought is drawn as nothing here: its style is
        not drawn }
      sv := SampleOf(el.Objects['snap'].Find('scaleX'), s);
      if not ((sv <> nil) and (sv.JSONType = jtString) and (FromHex(sv.AsString) = 0)) then
        CompareStyle(id, once, fe, el.Objects['style'], s);
    end;
  end;
end;

procedure TAdvChartUniversalTransition6Test.TestRestPathsAsUpstream;
var
  cs: TJSONArray;
  i, ran, k: Integer;
  c: TJSONObject;
  t1: Double;
begin
  cs := Fix.Arrays['charts'];
  ran := 0;
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    if not Wanted(c.Strings['id']) then Continue;
    t1 := Play(c, True);
    k := 16;
    while k <= 5000 do
    begin
      FChart.AnimTick(t1 + 1500 + k);
      k := k + 250;
    end;
    Draw;
    CompareRest(c.Strings['id'], 'new', c.Arrays['newRest']);
    Inc(ran);
  end;
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition 6 rest paths: %d cases, %d paths, %d compared',
      [ran, FRests, FCompared]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartUniversalTransition6Test.TestEveryTransitionAsUpstream;
var
  cs: TJSONArray;
  i, ran: Integer;
begin
  cs := Fix.Arrays['charts'];
  AssertTrue('chart cases', cs.Count >= 40);
  ran := 0;
  for i := 0 to cs.Count - 1 do
  begin
    if not Wanted(cs.Objects[i].Strings['id']) then Continue;
    RunCase(cs.Objects[i]);
    Inc(ran);
  end;
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition 6: %d cases, %d compared, %d morph frames, %d child frames, '
      + '%d new style keys', [ran, FCompared, FMorphs, FPieceFrames, FStyleKeys]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
end;

{ THE POINTER AT EACH COMBINING CHILD: upstream's findHover lands on the
  child (it is in the display list, not the host), and the mouse event's
  ecData is its host's, the child's parent. The port's hit test at the same
  whole pixel names the same datum. }
procedure TAdvChartUniversalTransition6Test.TestEveryChildIsHit;
const
  cCases: array[0..1] of string = ('sub.hit', 'sub.hit-pie');
var
  c, h, pr: TJSONObject;
  hits, samples, probes: TJSONArray;
  ci, s, hi, k, el, past: Integer;
  t1: Double;
  d: TTyChartDatumRef;
  id: string;
begin
  past := 0;
  for ci := 0 to High(cCases) do
  begin
    c := CaseById(cCases[ci]);
    samples := c.Arrays['samples'];
    hits := c.Arrays['hits'];
    t1 := Play(c, False);
    hi := 0;
    for s := 0 to samples.Count - 1 do
    begin
      if s > 0 then FChart.AnimTick(t1 + samples.Items[s].AsFloat);
      Draw;
      if (hi >= hits.Count) or (hits.Objects[hi].Integers['sample'] <> s) then Continue;
      h := hits.Objects[hi];
      Inc(hi);
      probes := h.Arrays['probes'];
      for k := 0 to probes.Count - 1 do
      begin
        pr := probes.Objects[k];
        if not pr.Booleans['child'] then Continue;
        id := Format('%s t=%s %s', [cCases[ci], samples.Items[s].AsString, pr.Strings['of']]);
        if Pos('#0', pr.Strings['of']) = 0 then Inc(past);
        d := FChart.HitTestAt(Round(FromHex(pr.Strings['x'])), Round(FromHex(pr.Strings['y'])), el);
        Inc(FCompared);
        if (d.SeriesIndex <> pr.Integers['series']) or (d.DataIndex <> pr.Integers['dataIndex']) then
          Miss(Format('%s: the pointer names (%d, %d) here, upstream (%d, %d)', [id, d.SeriesIndex,
            d.DataIndex, pr.Integers['series'], pr.Integers['dataIndex']]), cCases[ci] + pr.Strings['of']);
      end;
    end;
    AssertEquals(cCases[ci] + ': every hit sample met', hits.Count, hi);
  end;
  AssertTrue('children past the first are hit', past >= 8);
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
end;

{ THE CHILDREN AT THE HOST'S PLACE: Storage adds a combining host's
  childrenRef where the host would be, so the item paths and the children
  go in the display list in that order -- the port's paint order the same }
procedure TAdvChartUniversalTransition6Test.TestTheChildrenDrawInTheHostsPlace;
const
  cCases: array[0..1] of string = ('sub.hit', 'sub.hit-pie');
var
  c: TJSONObject;
  orders, samples, want: TJSONArray;
  ci, s, k, idx, place: Integer;
  t1: Double;
  frm: TTyPaintList;
  fe: TTyChartElement;
  got, wants: string;
begin
  for ci := 0 to High(cCases) do
  begin
    c := CaseById(cCases[ci]);
    samples := c.Arrays['samples'];
    orders := c.Arrays['orders'];
    t1 := Play(c, False);
    for s := 0 to samples.Count - 1 do
    begin
      if s > 0 then FChart.AnimTick(t1 + samples.Items[s].AsFloat);
      Draw;
      frm := FChart.Frame;
      got := '';
      for k := 0 to frm.Count - 1 do
      begin
        idx := frm.PaintOrder(k);
        fe := frm.Element(idx);
        if (TyUtPathKey(fe) = '') or fe.Silent or fe.Ignore then Continue;
        place := PlaceOfPath(frm, fe);
        got := got + Format(',s%d/%d/%d', [fe.Anim.Series, TyUtPathRow(fe), place]);
        if fe.Anim.UtPiece > 0 then got := got + '#' + IntToStr(fe.Anim.UtPiece - 1);
      end;
      want := orders.Arrays[s];
      wants := '';
      for k := 0 to want.Count - 1 do wants := wants + ',' + want.Strings[k];
      Inc(FCompared);
      if got <> wants then
        Miss(Format('%s t=%s: painted %s, upstream %s', [cCases[ci], samples.Items[s].AsString,
          Copy(got, 2, MaxInt), Copy(wants, 2, MaxInt)]), cCases[ci] + 'order');
    end;
  end;
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
end;

{ A HOST THAT LEAVES WHILE IT COMBINES: removeElementWithFadeOut fades the
  host, which is not drawn -- its children are, with their own style, and
  go on morphing until the host is removed. Every path the port draws for
  the bars (the ghosts too) against upstream's paths under the series'
  views: as many, each child's path and opacity the same (sorted). }
procedure TAdvChartUniversalTransition6Test.TestALeavingHostDrawsItsChildren;
const
  cCases: array[0..1] of string = ('sub.leave', 'sub.leave-control');
var
  c: TJSONObject;
  disp, samples, want: TJSONArray;
  ci, s, k, children: Integer;
  t1: Double;
  frm: TTyPaintList;
  fe: TTyChartElement;
  wl, gl: TStringList;
begin
  wl := TStringList.Create;
  gl := TStringList.Create;
  try
    for ci := 0 to High(cCases) do
    begin
      c := CaseById(cCases[ci]);
      samples := c.Arrays['samples'];
      disp := c.Arrays['display'];
      t1 := Play(c, False);
      children := 0;
      for s := 0 to samples.Count - 1 do
      begin
        if s > 0 then FChart.AnimTick(t1 + samples.Items[s].AsFloat);
        Draw;
        frm := FChart.Frame;
        wl.Clear;
        gl.Clear;
        want := disp.Arrays[s];
        { a child: its path and opacity; a host drawn as itself: its opacity }
        for k := 0 to want.Count - 1 do
          if want.Objects[k].Booleans['child'] then
          begin
            wl.Add(want.Objects[k].Strings['d'] + ' ' + want.Objects[k].Strings['opacity']);
            Inc(children);
          end
          else
            wl.Add('host ' + want.Objects[k].Strings['opacity']);
        for k := 0 to frm.Count - 1 do
        begin
          fe := frm.Element(k);
          if fe.Anim.Series <> 0 then Continue;
          if not (fe.Anim.Role in [carBar, carSymbol]) and (fe.Anim.UtPiece = 0) then Continue;
          if fe.Ignore or not (fe.Style.Alpha > 0) then Continue;
          if not fe.Style.HasFill and not (fe.Style.StrokeWidthLogical > 0) then Continue;
          if fe.Anim.UtPiece > 0 then gl.Add(Digest(CmdsData(fe)) + ' ' + Hex(fe.Style.Alpha))
          else gl.Add('host ' + Hex(fe.Style.Alpha));
        end;
        wl.Sort;
        gl.Sort;
        Inc(FCompared);
        if wl.Text <> gl.Text then
          Miss(Format('%s t=%s: %d paths drawn here, upstream %d (%s / %s)', [cCases[ci],
            samples.Items[s].AsString, gl.Count, wl.Count, Copy(gl.CommaText, 1, 90),
            Copy(wl.CommaText, 1, 90)]), cCases[ci] + 'disp');
      end;
      if ci = 0 then AssertTrue('upstream draws the children', children >= 6);
    end;
  finally
    wl.Free;
    gl.Free;
  end;
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
end;

{ FILLOPACITY IS DRAWN: zrender's brushPath fills with globalAlpha =
  opacity x fillOpacity -- the custom rect's fill at fillOpacity 0.4 is the
  same ink as the same rect at opacity 0.4 (inside it, away from its pen) }
procedure TAdvChartUniversalTransition6Test.TestTheOpacitiesAreDrawn;
var
  c: TJSONObject;
  t1: Double;
  px, ref: TBGRAPixel;
begin
  c := CaseById('style.bar-opacity-custom');
  t1 := Play(c, False);
  FChart.AnimTick(t1 + 6000);
  Draw;
  { rect 0 rests at x 89.5 .. 105.5, y 123.125 .. 220 }
  px := FBmp.GetPixel(97, 171);
  { the reference: the same rect, its opacity 0.4 }
  NewChart;
  FChart.Option := '{"color":["#5070dd"],"xAxis":{"type":"category","data":["A","B","C","D"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"custom","renderItem":"@alphaRect",'
    + '"data":[{"name":"A","value":[0,5]},{"name":"B","value":[1,8]},{"name":"C","value":[2,3]},'
    + '{"name":"D","value":[3,6]}]}]}';
  FChart.SetBounds(0, 0, cW, cH);
  FChart.AnimTick(Fix.Objects['clock'].Floats['T0'] + 6000);
  Draw;
  ref := FBmp.GetPixel(97, 171);
  AssertTrue('the reference is not the bare fill', ref.red > 120);
  AssertTrue(Format('the fill at fillOpacity 0.4: (%d, %d, %d), at opacity 0.4: (%d, %d, %d)',
    [px.red, px.green, px.blue, ref.red, ref.green, ref.blue]),
    (Abs(px.red - ref.red) <= 1) and (Abs(px.green - ref.green) <= 1)
    and (Abs(px.blue - ref.blue) <= 1));
end;

initialization
  RegisterTest(TAdvChartUniversalTransition6Test);
finalization
  FreeAndNil(GFix);
end.
