unit test.advchart.universaltransition4;
{$mode objfpc}{$H+}
{$Q-}{$R-}
{ THE REST OF THE UNIVERSAL TRANSITION, held to upstream. [F3c]

  tests/fixtures/advchart-universal-transition4.json, from the real ECharts
  6.1 build under the hand-driven clock.

  Steps of setOption -- the first at T0, each next one after the one before
  has run out (T + 10000) or `after` ms into it, notMerge unless the step
  merges, `opts` added to the options -- recorded at the last T + each
  sample. Every element type upstream morphs: a funnel's polygons, bars on a
  polar (sectors, sausages, rounded), a pictorialBar's glyphs (repeated and
  single, turned), a map's regions (a hole, two polygons, a line, a region
  no data names), a custom series' groups and turned rects, a lines
  series' lines and end symbols; a mixed batch; the texts riding the morph
  frames; the same sunburst restyled and with other data, the same
  treemap with other data; setOption's `transition` by index, by id, for a
  series that does not ask, for one the old option has not, a list, two
  old series into one, the dataGroupId the new side reads off the old
  series, a dimension, a custom series made anew; and the gallery's
  pictorialBar-bar-transition, map-bar-morph and pie-parliament-transition.

  TestRestPathsAsUpstream: every item path at rest before the last step and
  after it has run out -- its PathProxy data and its computed transform --
  against the port's path of the same item and place (TyUtLayoutPath).
  TestEveryTransitionAsUpstream: each case on a TTyAdvanceChart (zrender's
  SSR text measure, 400 x 300, camAlways); at every sample every item path
  upstream recorded, as universaltransition3 does: whether it morphs, the
  path its morph draws (every number, bit for bit, or the digest), its
  fill, stroke, line width and opacity; while it combines, every child it
  draws in its place; its text's place against where it rests at the last
  sample. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Color, tyControls.AdvChart.JsMath,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.Morph,
     tyControls.AdvChart.Custom, tyControls.AdvChart.Geo,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TUt4Probe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  { the oracle's renderItems }
  TUt4Mirror = class
  public
    function Parliament(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Pin(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Tile(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  TAdvChartUniversalTransition4Test = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TUt4Probe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FMirror: TUt4Mirror;
    FBad, FCompared, FMorphs, FPieceFrames, FTexts, FRests: Integer;
    FReport: string;
    FSeen: TStringList;
    FOldRest: TJSONArray;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart;
    procedure Draw;
    function Play(ACase: TJSONObject; ACheckRest: Boolean): Double;
    procedure RunCase(ACase: TJSONObject);
    procedure CompareRest(const ACid, ASide: string; ARest: TJSONArray; ADigest: Boolean);
    procedure ComparePath(const AId, AOnce: string; const AData: TTyDoubleArray;
      AWant: TJSONData);
    procedure CompareStyle(const AId, AOnce: string; const AFe: TTyChartElement;
      AStyle: TJSONObject; ASample: Integer);
    function CaseById(const AId: string): TJSONObject;
    function Wanted(const AId: string): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRestPathsAsUpstream;
    procedure TestEveryTransitionAsUpstream;
    procedure TestTransitionOptionTakesOverTheKeys;
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
        + 'advchart-universal-transition4.json');
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

{ {"$fn": name} -> '@name', in place, everywhere }
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

function TUt4Probe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TUt4Probe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TUt4Probe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== the renderItems ==================== }

function JsRound(A: Double): Double;
begin
  Result := Floor(A + 0.5);
end;

function Num(A: Double): TJSONFloatNumber;
begin
  Result := TJSONFloatNumber.Create(A);
end;

const
  cPalette: array[0..8] of string = ('#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df',
    '#ffd10a', '#fb628b', '#785db0', '#3fbe95');
  cParl: array[0..5] of Double = (800, 635, 580, 484, 300, 200);

{ RENDER.parliament: the gallery's seats }
function TUt4Mirror.Parliament(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  angles: array[0..6] of Double;
  sum, cur, viewSize, r0, r1, cx, cy, size, r, newSize, k, angle, kEnd: Double;
  i, idx, rows, seats: Integer;
  children: TJSONArray;
begin
  sum := 0;
  for i := 0 to 5 do sum := sum + cParl[i];
  cur := -Pi / 2;
  for i := 0 to 5 do
  begin
    angles[i] := cur;
    cur := cur + (cParl[i] / sum) * Pi * 2;
  end;
  angles[6] := -Pi / 2 + Pi * 2;
  idx := AParams.DataIndex;
  viewSize := Min(AApi.GetWidth, AApi.GetHeight);
  r0 := ((30 / 100) * viewSize) / 2;
  r1 := ((80 / 100) * viewSize) / 2;
  cx := AApi.GetWidth * 0.5;
  cy := AApi.GetHeight * 0.5;
  size := viewSize / 50;
  children := TJSONArray.Create;
  { parliamentLayout(angles[idx], angles[idx + 1], 2 pi, r0, r1, size + 3) }
  rows := Ceil((r1 - r0) / (size + 3));
  r := r0;
  for i := 0 to rows - 1 do
  begin
    seats := Round(JsRound((Pi * 2 * r) / (size + 3)));
    newSize := (Pi * 2 * r) / seats;
    k := Floor((angles[idx] * r) / newSize) * newSize;
    kEnd := Floor((angles[idx + 1] * r) / newSize) * newSize - 1e-6;
    while k < kEnd do
    begin
      angle := k / r;
      children.Add(TJSONObject.Create(['type', 'circle',
        'shape', TJSONObject.Create(['cx', Num(cx + TyJsCos(angle) * r),
          'cy', Num(cy + TyJsSin(angle) * r), 'r', Num(size / 2)]),
        'style', TJSONObject.Create(['fill', cPalette[idx mod 9]])]));
      k := k + newSize;
    end;
    r := r + (size + 3);
  end;
  Result := TJSONObject.Create(['type', 'group', 'children', children]);
end;

{ RENDER.pin: a column rect and a circle on its top }
function TUt4Mirror.Pin(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  p, b: TTyDoubleArray;
  col: TJSONData;
begin
  p := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  b := AApi.Coord([AApi.Value(0), 0]);
  col := AApi.Visual('color');
  Result := TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
    TJSONObject.Create(['type', 'rect', 'shape', TJSONObject.Create(['x', Num(p[0] - 8),
      'y', Num(p[1]), 'width', 16, 'height', Num(b[1] - p[1])]),
      'style', TJSONObject.Create(['fill', col])]),
    TJSONObject.Create(['type', 'circle', 'shape', TJSONObject.Create(['cx', Num(p[0]),
      'cy', Num(p[1]), 'r', 6]), 'style', TJSONObject.Create(['fill', '#ffd10a'])])])]);
end;

{ RENDER.tile: a rect turned 15 degrees about its centre }
function TUt4Mirror.Tile(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var p: TTyDoubleArray;
begin
  p := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  Result := TJSONObject.Create(['type', 'rect', 'x', Num(p[0]), 'y', Num(p[1]),
    'rotation', Num(Pi / 12),
    'shape', TJSONObject.Create(['x', -10, 'y', -10, 'width', 20, 'height', 20]),
    'style', TJSONObject.Create(['fill', AApi.Visual('color')])]);
end;

{ ==================== plumbing ==================== }

procedure TAdvChartUniversalTransition4Test.SetUp;
var
  sl: TStringList;
  maps: TJSONArray;
  i: Integer;
  sp: string;
  d: TJSONData;
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
  FTexts := 0;
  FRests := 0;
  FReport := '';
  FMirror := TUt4Mirror.Create;
  TyChartRegisterRenderItem('parliament', @FMirror.Parliament);
  TyChartRegisterRenderItem('pin', @FMirror.Pin);
  TyChartRegisterRenderItem('tile', @FMirror.Tile);
  maps := Fix.Arrays['maps'];
  for i := 0 to maps.Count - 1 do
  begin
    sp := '';
    d := maps.Objects[i].Find('special');
    if (d <> nil) and (d.JSONType <> jtNull) then sp := d.AsJSON;
    TyChartRegisterMap(maps.Objects[i].Strings['name'], maps.Objects[i].Strings['text'], sp);
  end;
end;

procedure TAdvChartUniversalTransition4Test.TearDown;
begin
  TyChartUnregisterRenderItem('parliament');
  TyChartUnregisterRenderItem('pin');
  TyChartUnregisterRenderItem('tile');
  FreeAndNil(FSeen);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  FreeAndNil(FMirror);
  inherited TearDown;
end;

procedure TAdvChartUniversalTransition4Test.Miss(const AWhere: string; const AOnce: string);
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

procedure TAdvChartUniversalTransition4Test.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TUt4Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := Fix.Objects['clock'].Floats['T0'];
end;

procedure TAdvChartUniversalTransition4Test.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartUniversalTransition4Test.CaseById(const AId: string): TJSONObject;
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

{ TY_UT4_CASE: a comma list of case ids to run alone }
function TAdvChartUniversalTransition4Test.Wanted(const AId: string): Boolean;
var w: string;
begin
  w := GetEnvironmentVariable('TY_UT4_CASE');
  Result := (w = '') or (Pos(',' + AId + ',', ',' + w + ',') > 0);
end;

{ the frame element of item path (series, row, place) and child APiece (0:
  the path itself); -1 for none }
function FindPath(AList: TTyPaintList; ASeries, ARow, APath: Integer; APiece: Integer = 0): Integer;
var
  i: Integer;
  el: TTyChartElement;
begin
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if TyUtPathKey(el) = '' then Continue;
    if (el.Anim.Series = ASeries) and (el.Anim.Index = ARow) and (TyUtPathOrder(el) = APath)
      and (el.Anim.UtPiece = APiece) then Exit(i);
  end;
  Result := -1;
end;

{ the transition key of item path (series, row, place), whatever is drawn in
  its place; '' for none }
function KeyOfPath(AList: TTyPaintList; ASeries, ARow, APath: Integer): string;
var
  i: Integer;
  el: TTyChartElement;
begin
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if TyUtPathKey(el) = '' then Continue;
    if (el.Anim.Series = ASeries) and (el.Anim.Index = ARow) and (TyUtPathOrder(el) = APath) then
      Exit(TyUtPathKey(el));
  end;
  Result := '';
end;

{ the text that follows the frame element AHost; -1 for none }
function FindText(AList: TTyPaintList; AHost: Integer): Integer;
var i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    if (AList.Element(i).Anim.Role = carLabel) and (AList.Element(i).Anim.HostPlus1 = AHost + 1)
      and (AList.Element(i).Caption.Text <> '') then Exit(i);
  Result := -1;
end;

{ the case's steps the oracle's way; the last one's T. ACheckRest: the old
  item paths at rest compared before the last step }
function TAdvChartUniversalTransition4Test.Play(ACase: TJSONObject; ACheckRest: Boolean): Double;
var
  steps: TJSONArray;
  st: TJSONObject;
  i: Integer;
  t, k, after: Double;
  cid, opts: string;
  d: TJSONData;
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
        FChart.AnimTick(t + after / 2);
        FChart.AnimTick(t + after);
        t := t + after;
      end;
      if ACheckRest and (i = steps.Count - 1) and (ACase.Find('oldRest') <> nil) then
        CompareRest(cid, 'old', ACase.Arrays['oldRest'], ACase.Booleans['digest']);
    end;
    FChart.AnimNow := t;
    if i = 0 then
      FChart.Option := OptionText(st.Elements['option'])
    else
    begin
      if st.Booleans['merge'] then opts := '{"notMerge":false' else opts := '{"notMerge":true';
      d := st.Find('opts');
      if d is TJSONObject then
        opts := opts + ',"transition":' + TJSONObject(d).Elements['transition'].AsJSON;
      opts := opts + '}';
      AssertTrue(cid + ': step ' + IntToStr(i) + ' sets',
        FChart.SetOption(OptionText(st.Elements['option']), opts));
    end;
    AssertEquals(cid + ': step ' + IntToStr(i) + ' parses', '', FChart.OptionError);
    if i = 0 then FChart.SetBounds(0, 0, cW, cH);
    Draw;
    if GetEnvironmentVariable('TY_UT4_DUMP') = '1' then
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

procedure TAdvChartUniversalTransition4Test.ComparePath(const AId, AOnce: string;
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

procedure TAdvChartUniversalTransition4Test.CompareStyle(const AId, AOnce: string;
  const AFe: TTyChartElement; AStyle: TJSONObject; ASample: Integer);
var
  sv: TJSONData;
  want: TTyChartColor;
begin
  sv := SampleOf(AStyle.Find('fill'), ASample);
  if (sv <> nil) and (sv.JSONType = jtString) and (sv.AsString <> 'transparent') then
  begin
    Inc(FCompared);
    if not TyTryParseChartColor(sv.AsString, want) then
      Miss(AId + ': fill ' + sv.AsString + ' does not parse')
    else if (not AFe.Style.HasFill) or (AFe.Style.FillColor <> want) then
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
  end;
  sv := SampleOf(AStyle.Find('opacity'), ASample);
  if (sv <> nil) and (sv.JSONType = jtString) then
  begin
    Inc(FCompared);
    if Hex(AFe.Style.Alpha) <> sv.AsString then
      Miss(Format('%s: opacity %s, upstream %s', [AId, FloatToStr(AFe.Style.Alpha),
        FloatToStr(FromHex(sv.AsString))]), AOnce + 'op');
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
procedure TAdvChartUniversalTransition4Test.CompareRest(const ACid, ASide: string;
  ARest: TJSONArray; ADigest: Boolean);
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
  if GetEnvironmentVariable('TY_UT4_DUMP') = '1' then
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

procedure TAdvChartUniversalTransition4Test.RunCase(ACase: TJSONObject);
var
  samples, els, pcs: TJSONArray;
  s, e, k, at, pk_, last, ser, row, pth, ti: Integer;
  el, pc: TJSONObject;
  t1: Double;
  id, cid, once, key: string;
  frm: TTyPaintList;
  fe: TTyChartElement;
  p, pp: TTyChartAnimProxy;
  isMorph, isComb, portMorph: Boolean;
  v: TTyAnimValue;
  sv: TJSONData;
  txX, txY: array of Double;
  txHas: array of Boolean;
  wx, wy, gx, gy: Double;
begin
  cid := ACase.Strings['id'];
  t1 := Play(ACase, False);
  samples := ACase.Arrays['samples'];
  els := ACase.Arrays['elements'];
  last := samples.Count - 1;
  { every text's place at every sample }
  SetLength(txX, els.Count * samples.Count);
  SetLength(txY, els.Count * samples.Count);
  SetLength(txHas, els.Count * samples.Count);
  for s := 0 to samples.Count - 1 do
  begin
    if s > 0 then FChart.AnimTick(t1 + samples.Items[s].AsFloat);
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
      { the text on the path: while it combines its first child is in its
        place }
      k := at;
      if k < 0 then k := FindPath(frm, ser, row, pth, 1);
      if k >= 0 then ti := FindText(frm, k) else ti := -1;
      if ti >= 0 then
      begin
        txHas[e * samples.Count + s] := True;
        txX[e * samples.Count + s] := frm.Element(ti).Caption.X;
        txY[e * samples.Count + s] := frm.Element(ti).Caption.Y;
      end;
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
      CompareStyle(id, once, fe, el.Objects['style'], s);
    end;
  end;
  { THE TEXTS: where each is drawn against where it rests (the last
    sample), upstream's the same way }
  for e := 0 to els.Count - 1 do
  begin
    el := els.Objects[e];
    if (el.Find('text') = nil) or not el.Booleans['item'] then Continue;
    if not txHas[e * samples.Count + last] then Continue;
    for s := 0 to samples.Count - 1 do
    begin
      id := Format('%s t=%s %s text', [cid, samples.Items[s].AsString, el.Strings['id']]);
      once := cid + el.Strings['id'] + 'text';
      if el.Objects['text'].Arrays['x'].Items[s].JSONType <> jtString then Continue;
      Inc(FCompared);
      if not txHas[e * samples.Count + s] then
      begin
        { a text faded to nought is drawn as nothing here }
        sv := SampleOf(el.Objects['text'].Find('opacity'), s);
        if (sv <> nil) and (sv.JSONType = jtString) and (FromHex(sv.AsString) < 1e-3) then Continue;
        Miss(id + ': no text here', once + 'none');
        Continue;
      end;
      Inc(FTexts);
      wx := FromHex(el.Objects['text'].Arrays['x'].Items[s].AsString)
        - FromHex(el.Objects['text'].Arrays['x'].Items[last].AsString);
      wy := FromHex(el.Objects['text'].Arrays['y'].Items[s].AsString)
        - FromHex(el.Objects['text'].Arrays['y'].Items[last].AsString);
      gx := txX[e * samples.Count + s] - txX[e * samples.Count + last];
      gy := txY[e * samples.Count + s] - txY[e * samples.Count + last];
      if (Abs(gx - wx) > 1e-6) or (Abs(gy - wy) > 1e-6) then
        Miss(Format('%s: off its rest by (%g, %g), upstream (%g, %g)', [id, gx, gy, wx, wy]), once);
    end;
  end;
end;

procedure TAdvChartUniversalTransition4Test.TestRestPathsAsUpstream;
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
    CompareRest(c.Strings['id'], 'new', c.Arrays['newRest'], c.Booleans['digest']);
    Inc(ran);
  end;
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition 4 rest paths: %d cases, %d paths, %d compared',
      [ran, FRests, FCompared]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartUniversalTransition4Test.TestEveryTransitionAsUpstream;
var
  cs: TJSONArray;
  i, ran: Integer;
begin
  cs := Fix.Arrays['charts'];
  AssertTrue('chart cases', cs.Count >= 30);
  ran := 0;
  for i := 0 to cs.Count - 1 do
  begin
    if not Wanted(cs.Objects[i].Strings['id']) then Continue;
    RunCase(cs.Objects[i]);
    Inc(ran);
  end;
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition 4: %d cases, %d compared, %d morph frames, %d child frames, %d texts',
      [ran, FCompared, FMorphs, FPieceFrames, FTexts]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartUniversalTransition4Test.TestTransitionOptionTakesOverTheKeys;
var
  t1: Double;
  i: Integer;
  p: TTyChartAnimProxy;
begin
  { a bar series a into a pie b: no key pairs them, the option does }
  t1 := Play(CaseById('opt.index'), False);
  FChart.AnimTick(t1 + 100);
  for i := 0 to 3 do
  begin
    p := FChart.AnimFindProxy(0, i, 'sector');
    AssertTrue('slice ' + IntToStr(i) + ' morphs', (p <> nil) and p.MorphOn);
  end;
  { from a series the old option has not: nothing -- not the keys either }
  t1 := Play(CaseById('opt.missing'), False);
  FChart.AnimTick(t1 + 100);
  for i := 0 to 3 do
  begin
    p := FChart.AnimFindProxy(0, i, 'sector');
    AssertFalse('slice ' + IntToStr(i) + ' does not morph', (p <> nil) and p.MorphOn);
  end;
end;

initialization
  RegisterTest(TAdvChartUniversalTransition4Test);
finalization
  FreeAndNil(GFix);
end.
