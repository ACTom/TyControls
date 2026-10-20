unit test.advchart.universaltransition3;
{$mode objfpc}{$H+}
{$Q-}{$R-}
{ THE DIRECTION OF A TRANSITION, held to upstream. [Batch 138, D5 UT3]

  tests/fixtures/advchart-universal-transition3.json, from the real ECharts
  6.1 build under the hand-driven clock.

  Steps of setOption -- the first at T0, each next one after the one before
  has run out (T + 10000) or `after` ms into it, notMerge unless the step
  merges -- recorded at the last T + each sample. The gallery's
  bar-multi-drilldown level by level (merged as the example does): one
  level down and two, back up one and two, up from nine leaves whose child
  column was never written, down with notMerge, siblings with no common
  group, and the next level arriving 200 ms into a drill; raw items'
  childGroupId across a bar and a pie both ways, a childGroupId that
  matches nothing, a missing childGroupId keyed 'undefined', both
  directions present (the first new item that tells decides, parent ->
  child asked first); a list seriesKey drilling down and up; numeric
  encoded group columns.

  `oldGroups` / `newGroups`: what getGroupId gave every flattened item,
  compared with what the port reads off the options. Each case then runs on
  a TTyAdvanceChart (zrender's SSR text measure, 400 x 300, camAlways) and
  at every sample every item element upstream recorded is compared as
  universaltransition2 does: whether it morphs, the path its morph draws
  (every number, bit for bit), its fill, stroke, line width and opacity,
  the keys upstream tracks where it does not morph; while it combines,
  every child it draws in its place; a removed bar's opacity and how many
  bars leave. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Measure,
     tyControls.AdvanceChart.Color,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.AnimOpt,
     tyControls.AdvanceChart.AnimView, tyControls.AdvanceChart.Morph,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TUt3Probe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartUniversalTransition3Test = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TUt3Probe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FMorphs, FPieceFrames: Integer;
    FReport: string;
    FSeen: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    procedure NewChart;
    procedure Draw;
    function Play(ACase: TJSONObject): Double;
    procedure RunCase(ACase: TJSONObject);
    procedure ComparePath(const AId, AOnce: string; const AData: TTyDoubleArray;
      AWant: TJSONData);
    procedure CompareStyle(const AId, AOnce: string; const AFe: TTyChartElement;
      AStyle: TJSONObject; ASample: Integer);
    function CaseById(const AId: string): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestGroupsAsUpstream;
    procedure TestEveryTransitionAsUpstream;
    procedure TestDrillingDownSeparatesAndUpCombines;
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
        + 'advchart-universal-transition3.json');
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

{ ==================== the probe ==================== }

function TUt3Probe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TUt3Probe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TUt3Probe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== plumbing ==================== }

procedure TAdvChartUniversalTransition3Test.SetUp;
var sl: TStringList;
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
  FReport := '';
end;

procedure TAdvChartUniversalTransition3Test.TearDown;
begin
  FreeAndNil(FSeen);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartUniversalTransition3Test.Miss(const AWhere: string; const AOnce: string);
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

procedure TAdvChartUniversalTransition3Test.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TUt3Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := Fix.Objects['clock'].Floats['T0'];
end;

procedure TAdvChartUniversalTransition3Test.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

function TAdvChartUniversalTransition3Test.CaseById(const AId: string): TJSONObject;
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

{ the case's steps the oracle's way; the last one's T }
function TAdvChartUniversalTransition3Test.Play(ACase: TJSONObject): Double;
var
  steps: TJSONArray;
  st: TJSONObject;
  i: Integer;
  t, k, after: Double;
  cid: string;
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
    end;
    FChart.AnimNow := t;
    { a step may dispatch an action instead (milestone D5-D8) }
    if st.IndexOfName('action') >= 0 then
    begin
      AssertTrue(cid + ': step ' + IntToStr(i) + ' dispatches',
        FChart.DispatchAction(st.Objects['action'].AsJSON));
      Draw;
      Continue;
    end;
    if (i > 0) and st.Booleans['merge'] then
      AssertTrue(cid + ': step ' + IntToStr(i) + ' merges', FChart.MergeOption(st.Elements['option'].AsJSON))
    else
      FChart.Option := st.Elements['option'].AsJSON;
    AssertEquals(cid + ': step ' + IntToStr(i) + ' parses', '', FChart.OptionError);
    if i = 0 then FChart.SetBounds(0, 0, cW, cH);
    Draw;
  end;
  Result := t;
end;

{ ==================== the cases ==================== }

function RoleOfType(const AType: string): TTyChartAnimRole;
begin
  if AType = 'bar' then Result := carBar
  else if AType = 'pie' then Result := carSector
  else if AType = 'scatter' then Result := carSymbol
  else if AType = 'line' then Result := carLineSymbol
  else if AType = 'sunburst' then Result := carSunPiece
  else if AType = 'treemap' then Result := carTmRect
  else Result := carNone;
end;

function ProxyRoleOf(R: TTyChartAnimRole): string;
begin
  case R of
    carBar: Result := 'bar';
    carSector: Result := 'sector';
    carSymbol: Result := 'symbol';
    carLineSymbol: Result := 'lineSymbol';
    carSunPiece: Result := 'sunPiece';
    carTmRect: Result := 'tmRect';
  else
    Result := '';
  end;
end;

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

{ the frame element of (series, row, role) and child APiece (0: the element
  itself); -1 for none }
function FindEl(AList: TTyPaintList; ASeries, ARow: Integer; ARole: TTyChartAnimRole;
  APiece: Integer = 0): Integer;
var
  i: Integer;
  el: TTyChartElement;
begin
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    { a treemap node's item path: a leaf's content, a parent's background }
    if (el.Anim.Role = carTmRect) and not ((el.Anim.Sub = 1)
      or ((el.Anim.Sub = 0) and (el.Anim.G[4] = 0))) then Continue;
    if (el.Anim.Role = ARole) and (el.Anim.Series = ASeries)
      and ((ARow < 0) or (el.Anim.Index = ARow)) and (el.Anim.UtPiece = APiece) then Exit(i);
  end;
  Result := -1;
end;

{ a treemap leaf's background (disableMorphing) of row ARow; -1 for none }
function FindTmBg(AList: TTyPaintList; ASeries, ARow: Integer): Integer;
var
  i: Integer;
  el: TTyChartElement;
begin
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Anim.Role = carTmRect) and (el.Anim.Series = ASeries) and (el.Anim.Index = ARow)
      and (el.Anim.Sub = 0) and (el.Anim.G[4] <> 0) then Exit(i);
  end;
  Result := -1;
end;

{ two different values among a key's samples }
function Moves(A: TJSONData): Boolean;
var
  i: Integer;
  first: string;
  have: Boolean;
begin
  Result := False;
  if (A = nil) or (A.JSONType <> jtArray) then Exit;
  have := False;
  first := '';
  for i := 0 to A.Count - 1 do
  begin
    if A.Items[i].JSONType <> jtString then Continue;
    if not have then
    begin
      first := A.Items[i].AsString;
      have := True;
    end
    else if A.Items[i].AsString <> first then Exit(True);
  end;
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

procedure TAdvChartUniversalTransition3Test.ComparePath(const AId, AOnce: string;
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
      Miss(Format('%s: the morph path %s, upstream %s', [AId, Digest(AData), AWant.AsString]), AOnce + 'd');
    Exit;
  end;
  if Length(AData) <> AWant.Count then
  begin
    Miss(Format('%s: the morph draws %d numbers, upstream %d', [AId, Length(AData), AWant.Count]),
      AOnce + 'dlen');
    Exit;
  end;
  for k := 0 to High(AData) do
    if Hex(AData[k]) <> AWant.Items[k].AsString then
    begin
      Miss(Format('%s: the morph path [%d] %s, upstream %s', [AId, k, FloatToStr(AData[k]),
        FloatToStr(FromHex(AWant.Items[k].AsString))]), AOnce + 'd');
      Exit;
    end;
end;

procedure TAdvChartUniversalTransition3Test.CompareStyle(const AId, AOnce: string;
  const AFe: TTyChartElement; AStyle: TJSONObject; ASample: Integer);
var
  sv: TJSONData;
  want: TTyChartColor;
begin
  sv := SampleOf(AStyle.Find('fill'), ASample);
  if (sv <> nil) and (sv.JSONType = jtString) then
  begin
    Inc(FCompared);
    if not TyTryParseChartColor(sv.AsString, want) then
      Miss(AId + ': fill ' + sv.AsString + ' does not parse')
    else if (not AFe.Style.HasFill) or (AFe.Style.FillColor <> want) then
      Miss(Format('%s: fill %s, upstream %s', [AId, IntToHex(AFe.Style.FillColor, 8),
        sv.AsString]), AOnce + 'fill');
  end;
  sv := SampleOf(AStyle.Find('stroke'), ASample);
  if (sv <> nil) and (sv.JSONType = jtString) then
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

procedure TAdvChartUniversalTransition3Test.RunCase(ACase: TJSONObject);
var
  samples, els, pcs: TJSONArray;
  s, e, k, at, pk_: Integer;
  el, sn, pc: TJSONObject;
  t1: Double;
  id, cid, key, pk, once: string;
  frm: TTyPaintList;
  fe: TTyChartElement;
  role: TTyChartAnimRole;
  p, pp: TTyChartAnimProxy;
  isMorph, isComb, portMorph: Boolean;
  v: TTyAnimValue;
  sv: TJSONData;
  rects: Integer;

  { the AK-th ghost bar of the series in the frame's tail }
  function GhostBar(AFrm: TTyPaintList; ASeries, AK: Integer): Integer;
  var q, n: Integer;
  begin
    n := 0;
    for q := AFrm.Count - FChart.AnimGhostCount to AFrm.Count - 1 do
      if (q >= 0) and (AFrm.Element(q).Anim.Role = carBar) and (AFrm.Element(q).Anim.Series = ASeries) then
      begin
        if n = AK then Exit(q);
        Inc(n);
      end;
    Result := -1;
  end;

begin
  cid := ACase.Strings['id'];
  t1 := Play(ACase);
  samples := ACase.Arrays['samples'];
  els := ACase.Arrays['elements'];
  for s := 0 to samples.Count - 1 do
  begin
    if s > 0 then FChart.AnimTick(t1 + samples.Items[s].AsFloat);
    frm := FChart.Frame;
    rects := 0;
    for e := 0 to els.Count - 1 do
    begin
      el := els.Objects[e];
      id := Format('%s t=%s %s', [cid, samples.Items[s].AsString, el.Strings['id']]);
      once := cid + el.Strings['id'];
      if not el.Booleans['item'] then
      begin
        { another path of the view: a removed bar leaving (the port's
          ghosts, in order) }
        at := -1;
        if (el.Strings['seriesType'] = 'treemap') and (el.Find('owner') <> nil) then
          at := FindTmBg(frm, el.Integers['series'], el.Integers['owner'])
        else if el.Strings['type'] = 'rect' then
        begin
          at := GhostBar(frm, el.Integers['series'], rects);
          Inc(rects);
        end
        else if el.Strings['type'] = 'ec-polyline' then
          at := FindEl(frm, el.Integers['series'], -1, carLineRun)
        else if el.Strings['type'] = 'ec-polygon' then
          at := FindEl(frm, el.Integers['series'], -1, carLineArea)
        else
        begin
          Miss(id + ': a ' + el.Strings['type'] + ' is not mapped', once);
          Continue;
        end;
        if at < 0 then
        begin
          if PresentAt(el, s) then Miss(id + ': no element here', once);
          Continue;
        end;
        if not PresentAt(el, s) then Continue;
        sv := SampleOf(el.Objects['style'].Find('opacity'), s);
        if (sv = nil) or (sv.JSONType <> jtString) then Continue;
        Inc(FCompared);
        fe := frm.Element(at);
        if Hex(fe.Style.Alpha) <> sv.AsString then
          Miss(Format('%s: opacity %s, upstream %s', [id, FloatToStr(fe.Style.Alpha),
            FloatToStr(FromHex(sv.AsString))]), once + 'op');
        Continue;
      end;
      role := RoleOfType(el.Strings['seriesType']);
      p := FChart.AnimFindProxy(el.Integers['series'], el.Integers['dataIndex'], ProxyRoleOf(role));
      isComb := FlagAt(el, 'comb', s);
      Inc(FCompared);
      if isComb <> ((p <> nil) and p.CombineOn) then
        Miss(Format('%s: combining %s here, upstream %s', [id, BoolToStr((p <> nil) and p.CombineOn, True),
          BoolToStr(isComb, True)]), once + 'comb' + IntToStr(Ord(isComb)));
      if not PresentAt(el, s) then
      begin
        if FindEl(frm, el.Integers['series'], el.Integers['dataIndex'], role) >= 0 then
          Miss(id + ': drawn here, not upstream', once + 'gone');
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
        { the element's own opacity, which it draws once the children are done }
        sv := el.Objects['style'].Find('opacity');
        if Moves(sv) and (SampleOf(sv, s).JSONType = jtString) then
        begin
          v := p.GetAnimProp('style.opacity');
          Inc(FCompared);
          if (v.Kind <> avkNumber) or (Hex(v.Num) <> SampleOf(sv, s).AsString) then
            Miss(Format('%s: its own opacity %s, upstream %s', [id, FloatToStr(v.Num),
              FloatToStr(FromHex(SampleOf(sv, s).AsString))]), once + 'hop');
        end;
        for pk_ := 0 to pcs.Count - 1 do
        begin
          pc := pcs.Objects[pk_];
          if not FlagAt(pc, 'present', s) then Continue;
          at := FindEl(frm, el.Integers['series'], el.Integers['dataIndex'], role, pk_ + 1);
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
      at := FindEl(frm, el.Integers['series'], el.Integers['dataIndex'], role);
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
      end
      else
      begin
        { THE KEYS UPSTREAM TRACKS, on the proxy }
        sn := el.Objects['snap'];
        for k := 0 to sn.Count - 1 do
        begin
          key := sn.Names[k];
          if not Moves(sn.Items[k]) then Continue;
          sv := SampleOf(sn.Items[k], s);
          if sv.JSONType <> jtString then Continue;
          pk := key;
          if Copy(pk, 1, 2) = 'g.' then pk := Copy(pk, 3, MaxInt);
          if (role = carLineSymbol) and ((key = 'scaleX') or (key = 'scaleY')) then Continue;
          if p = nil then
          begin
            Miss(id + ': no proxy for a tracked ' + key, once + 'np');
            Continue;
          end;
          v := p.GetAnimProp(pk);
          Inc(FCompared);
          if v.Kind <> avkNumber then
            Miss(Format('%s: %s not held here', [id, key]), once + key)
          else if Hex(v.Num) <> sv.AsString then
            Miss(Format('%s: %s %s, upstream %s', [id, key, FloatToStr(v.Num),
              FloatToStr(FromHex(sv.AsString))]), once + key);
        end;
      end;
      CompareStyle(id, once, fe, el.Objects['style'], s);
    end;
    { as many bars leaving as upstream: an old element a morph took from
      leaves no ghost }
    k := 0;
    for e := 0 to els.Count - 1 do
      if (not els.Objects[e].Booleans['item']) and (els.Objects[e].Strings['type'] = 'rect')
        and (els.Objects[e].Find('owner') = nil) and PresentAt(els.Objects[e], s) then Inc(k);
    at := 0;
    for e := frm.Count - FChart.AnimGhostCount to frm.Count - 1 do
      if (e >= 0) and (frm.Element(e).Anim.Role = carBar) then Inc(at);
    Inc(FCompared);
    if k <> at then
      Miss(Format('%s t=%s: %d bars leaving here, upstream %d', [cid, samples.Items[s].AsString, at, k]),
        cid + 'ghosts');
  end;
end;

{ the series of an option as a list (an object is the one series) }
function SeriesList(AOption: TJSONObject): TJSONArray;
var
  d: TJSONData;
  k: Integer;
begin
  Result := TJSONArray.Create;
  d := AOption.Find('series');
  if d is TJSONArray then
  begin
    for k := 0 to d.Count - 1 do Result.Add(d.Items[k].Clone);
  end
  else if d is TJSONObject then
    Result.Add(d.Clone);
end;

procedure TAdvChartUniversalTransition3Test.TestGroupsAsUpstream;
var
  cs, steps, ser, want: TJSONArray;
  c, opt, so: TJSONObject;
  i, side, j, r, n, rows, cases: Integer;
  keys: TTyUtSeriesKeys;
  raws: TTyIntegerArray;
  groups, childs: TTyStringArray;
  typ, gotG, gotC, wantG, wantC, nm: string;
  data, it: TJSONData;
begin
  { what getGroupId reads off each item, on both sides of the last step:
    the encoded dimension, the raw item's groupId / childGroupId, the
    dataGroupId; a group the port leaves to the id is upstream's item name }
  cs := Fix.Arrays['charts'];
  cases := 0;
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    if c.Find('oldGroups') = nil then Continue;
    Inc(cases);
    steps := c.Arrays['steps'];
    for side := 0 to 1 do
    begin
      opt := steps.Objects[steps.Count - 2 + side].Objects['option'];
      if side = 0 then want := c.Arrays['oldGroups'] else want := c.Arrays['newGroups'];
      ser := SeriesList(opt);
      try
        n := 0;
        for j := 0 to ser.Count - 1 do
        begin
          so := ser.Objects[j];
          typ := so.Get('type', '');
          keys := TyUtSeriesKeysOf(so, opt, typ, 'x');
          data := so.Find('data');
          rows := 0;
          if data is TJSONArray then rows := data.Count;
          SetLength(raws, rows);
          for r := 0 to rows - 1 do raws[r] := r;
          groups := TyUtRowGroups(keys, raws);
          childs := TyUtRowChildGroups(keys, raws);
          for r := 0 to rows - 1 do
          begin
            Inc(FCompared);
            if n >= want.Count then
            begin
              Miss(Format('%s side %d: more items than upstream', [c.Strings['id'], side]));
              Break;
            end;
            if want.Arrays[n].Items[0].JSONType = jtNull then wantG := '<undefined>'
            else wantG := want.Arrays[n].Strings[0];
            if want.Arrays[n].Items[1].JSONType = jtNull then wantC := '<undefined>'
            else wantC := want.Arrays[n].Strings[1];
            if groups[r] <> '' then gotG := Copy(groups[r], 2, MaxInt)
            else
            begin
              { the id: the item's name where it has one }
              it := data.Items[r];
              nm := '';
              if it is TJSONObject then nm := TJSONObject(it).Get('name', '');
              if nm = '' then nm := wantG;
              gotG := nm;
            end;
            if childs[r] <> '' then gotC := Copy(childs[r], 2, MaxInt) else gotC := '<undefined>';
            if (gotG <> wantG) or (gotC <> wantC) then
              Miss(Format('%s side %d item %d: [%s, %s], upstream [%s, %s]', [c.Strings['id'], side, n,
                gotG, gotC, wantG, wantC]));
            Inc(n);
          end;
        end;
        Inc(FCompared);
        if n <> want.Count then
          Miss(Format('%s side %d: %d items, upstream %d', [c.Strings['id'], side, n, want.Count]));
      finally
        ser.Free;
      end;
    end;
  end;
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition 3 groups: %d cases, %d compared', [cases, FCompared]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue('group cases', cases >= 15);
end;

procedure TAdvChartUniversalTransition3Test.TestEveryTransitionAsUpstream;
var
  cs: TJSONArray;
  i, ran: Integer;
begin
  cs := Fix.Arrays['charts'];
  AssertTrue('chart cases', cs.Count >= 20);
  ran := 0;
  for i := 0 to cs.Count - 1 do
  begin
    RunCase(cs.Objects[i]);
    Inc(ran);
  end;
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition 3: %d cases, %d compared, %d morph frames, %d child frames',
      [ran, FCompared, FMorphs, FPieceFrames]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue('morph frames compared', FMorphs > 300);
  AssertTrue('child frames compared', FPieceFrames > 250);
end;

procedure TAdvChartUniversalTransition3Test.TestDrillingDownSeparatesAndUpCombines;
var
  t1: Double;
  i: Integer;
  p: TTyChartAnimProxy;
begin
  { things -> animals: the Animals bar separates into Dogs, Cats and Birds
    (the old side keyed by its childGroupId) }
  t1 := Play(CaseById('multi.down'));
  FChart.AnimTick(t1 + 200);
  for i := 0 to 2 do
  begin
    p := FChart.AnimFindProxy(0, i, 'bar');
    AssertTrue('bar ' + IntToStr(i) + ' morphs out of Animals', (p <> nil) and p.MorphOn);
  end;
  FChart.AnimTick(t1 + 2000);
  for i := 0 to 2 do
    AssertFalse('bar ' + IntToStr(i) + ' done', FChart.AnimFindProxy(0, i, 'bar').MorphOn);
  AssertEquals('nothing left to run', 0, FChart.AnimClipCount);
  { and back up: the three combine into Animals (the new side keyed by its
    childGroupId); Fruits and Cars do not morph }
  t1 := Play(CaseById('multi.up'));
  FChart.AnimTick(t1 + 200);
  p := FChart.AnimFindProxy(0, 0, 'bar');
  AssertTrue('Animals combines', (p <> nil) and p.CombineOn);
  AssertEquals('Animals: three children', 3, p.PieceCount);
  for i := 1 to 2 do
  begin
    p := FChart.AnimFindProxy(0, i, 'bar');
    AssertFalse('bar ' + IntToStr(i) + ' does not combine', (p <> nil) and p.CombineOn);
    AssertFalse('bar ' + IntToStr(i) + ' does not morph', (p <> nil) and p.MorphOn);
  end;
end;

initialization
  RegisterTest(TAdvChartUniversalTransition3Test);
finalization
  FreeAndNil(GFix);
end.
