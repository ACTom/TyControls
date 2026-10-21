unit test.advchart.universaltransition2;
{$mode objfpc}{$H+}
{$Q-}{$R-}
{ COMBINING AND SEPARATING, held to upstream. [Batch 137, D5 UT2]

  tests/fixtures/advchart-universal-transition2.json, from the real ECharts
  6.1 build under the hand-driven clock.

  `engine`: what combining and separating read besides the morph itself --
  PathProxy.getBoundingRect over path data, Path.getBoundingRect's stroke
  (the hover threshold, strokeNoScale under a scale), setLocalTransform and
  the transform an element with no parent then computes, sortPaths' order.

  `charts`: steps of setOption -- the first at T0, each next one after the
  one before has run out (T + 10000) or `after` ms into it, notMerge unless
  the step merges -- recorded at the last T + each sample. Two bar series
  become a pie whose seriesKey lists them (each slice combines two bars),
  and back (each slice separates); with the transition's delay (each child
  on its own), clone, the update timing; the root's dataGroupId, a
  dataGroupId on both sides (many to many), item groupIds of five, one and
  none, ungrouped items by id, a null bar whose points fade in; turned
  triangles split into polygons and cloned, circles combined into them; a
  line's stroked circles combined; the gallery's scatter-aggregate-bar both
  ways (507 points, path digests) and bar-drilldown down and up (merged);
  the next option arriving while things combine and separate.

  Each case runs on a TTyAdvanceChart (zrender's SSR text measure, 400 x
  300, camAlways) and at every sample every item element upstream recorded
  is compared: whether it morphs, the path its morph draws (every number,
  bit for bit -- or its digest), its fill, stroke, line width and opacity,
  the keys upstream tracks on its proxy where it does not morph; while it
  combines, every child it draws in its place -- whether it morphs, its
  path while it does, its style; and every other path of the new views
  (a line's polyline and area): its opacity. }
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
  TUt2Probe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartUniversalTransition2Test = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TUt2Probe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FMorphs, FPieceFrames: Integer;
    FReport: string;
    FSeen: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    function HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function HUt2(AIndex, ACount: Integer): Double;
    function HGal(AIndex, ACount: Integer): Double;
    procedure NewChart;
    procedure Draw;
    function Play(ACase: TJSONObject): Double;
    procedure RunCase(ACase: TJSONObject);
    procedure ComparePath(const AId, AOnce: string; const AData: TTyDoubleArray;
      AWant: TJSONData);
    procedure CompareStyle(const AId, AOnce: string; const AFe: TTyChartElement;
      AStyle: TJSONObject; ASample: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEngineAsUpstream;
    procedure TestEveryTransitionAsUpstream;
    procedure TestACombineDrawsItsChildrenAndEndsOnTheLayout;
    procedure TestAListKeyWithAMissingItemTransitionsTheRest;
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
        + 'advchart-universal-transition2.json');
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

function HexArr(A: TJSONData): TTyDoubleArray;
var i: Integer;
begin
  Result := nil;
  if (A = nil) or (A.JSONType <> jtArray) then Exit;
  SetLength(Result, A.Count);
  for i := 0 to A.Count - 1 do Result[i] := FromHex(A.Items[i].AsString);
end;

function HexMat(A: TJSONData; out M: TTyMat2D): Boolean;
var i: Integer;
begin
  for i := 0 to 5 do M[i] := 0;
  Result := (A <> nil) and (A.JSONType = jtArray);
  if Result then
    for i := 0 to 5 do M[i] := FromHex(A.Items[i].AsString);
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

// {"$fn": name} -> '@name', in place, everywhere
procedure ConvertFns(AData: TJSONData);
var
  i: Integer;
  o: TJSONObject;
  child: TJSONData;
begin
  if AData = nil then Exit;
  if AData.JSONType = jtArray then
  begin
    for i := 0 to AData.Count - 1 do
    begin
      child := AData.Items[i];
      if (child.JSONType = jtObject) and (TJSONObject(child).Count = 1)
        and (TJSONObject(child).Find('$fn') <> nil) then
        TJSONArray(AData).Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
      else
        ConvertFns(child);
    end;
  end
  else if AData.JSONType = jtObject then
  begin
    o := TJSONObject(AData);
    for i := 0 to o.Count - 1 do
    begin
      child := o.Items[i];
      if (child.JSONType = jtObject) and (TJSONObject(child).Count = 1)
        and (TJSONObject(child).Find('$fn') <> nil) then
        o.Items[i] := TJSONString.Create('@' + TJSONObject(child).Strings['$fn'])
      else
        ConvertFns(child);
    end;
  end;
end;

function OptionText(AData: TJSONData): string;
var c: TJSONData;
begin
  c := AData.Clone;
  try
    ConvertFns(c);
    Result := c.AsJSON;
  finally
    c.Free;
  end;
end;

{ ==================== the probe ==================== }

function TUt2Probe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TUt2Probe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TUt2Probe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== plumbing ==================== }

function TAdvChartUniversalTransition2Test.HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if AHasIndex then Result := ADataIndex * 50 else Result := NaN;
end;

function TAdvChartUniversalTransition2Test.HUt2(AIndex, ACount: Integer): Double;
begin
  { (idx, count) => 30 + idx * 40 + count * 10 }
  Result := 30 + AIndex * 40 + ACount * 10;
end;

function TAdvChartUniversalTransition2Test.HGal(AIndex, ACount: Integer): Double;
var r, c: Double;
begin
  { (idx, count) => idx * 7919 % count / count * 400 }
  r := (Int64(AIndex) * 7919) mod ACount;
  c := ACount;
  Result := r / c * 400;
end;

procedure TAdvChartUniversalTransition2Test.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  TyChartRegisterAnimTiming('idx*50', @HIdx50);
  TyChartRegisterUtDelay('ut2', @HUt2);
  TyChartRegisterUtDelay('gal', @HGal);
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

procedure TAdvChartUniversalTransition2Test.TearDown;
begin
  TyChartClearAnimTimings;
  FreeAndNil(FSeen);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FBmp);
  FreeAndNil(FMeasure);
  inherited TearDown;
end;

procedure TAdvChartUniversalTransition2Test.Miss(const AWhere: string; const AOnce: string);
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

procedure TAdvChartUniversalTransition2Test.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TUt2Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := Fix.Objects['clock'].Floats['T0'];
end;

procedure TAdvChartUniversalTransition2Test.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

{ the case's steps the oracle's way; the last one's T }
function TAdvChartUniversalTransition2Test.Play(ACase: TJSONObject): Double;
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
    if (i > 0) and st.Booleans['merge'] then
      AssertTrue(cid + ': step ' + IntToStr(i) + ' merges', FChart.MergeOption(OptionText(st.Elements['option'])))
    else
      FChart.Option := OptionText(st.Elements['option']);
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
  else Result := carNone;
end;

function ProxyRoleOf(R: TTyChartAnimRole): string;
begin
  case R of
    carBar: Result := 'bar';
    carSector: Result := 'sector';
    carSymbol: Result := 'symbol';
    carLineSymbol: Result := 'lineSymbol';
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
    if (el.Anim.Role = ARole) and (el.Anim.Series = ASeries)
      and ((ARow < 0) or (el.Anim.Index = ARow)) and (el.Anim.UtPiece = APiece) then Exit(i);
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

procedure TAdvChartUniversalTransition2Test.ComparePath(const AId, AOnce: string;
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

procedure TAdvChartUniversalTransition2Test.CompareStyle(const AId, AOnce: string;
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

procedure TAdvChartUniversalTransition2Test.RunCase(ACase: TJSONObject);
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
        { another path of the view: a line's polyline or area fades; a rect
          is a removed bar leaving (the port's ghosts, in order) }
        at := -1;
        if el.Strings['type'] = 'rect' then
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
        and PresentAt(els.Objects[e], s) then Inc(k);
    at := 0;
    for e := frm.Count - FChart.AnimGhostCount to frm.Count - 1 do
      if (e >= 0) and (frm.Element(e).Anim.Role = carBar) then Inc(at);
    Inc(FCompared);
    if k <> at then
      Miss(Format('%s t=%s: %d bars leaving here, upstream %d', [cid, samples.Items[s].AsString, at, k]),
        cid + 'ghosts');
  end;
end;

procedure TAdvChartUniversalTransition2Test.TestEngineAsUpstream;
var
  cs: TJSONArray;
  c, st, pth: TJSONObject;
  i, j, n: Integer;
  kind, want, got: string;
  r: TTyXYWH;
  m, mo: TTyMat2D;
  hasM, hasO, hasStroke, hasFill: Boolean;
  data: TTyDoubleArray;
  cx, cy: TTyDoubleArray;
  order: TTyIntegerArray;
  lw: Double;

  function RectHex(const R2: TTyXYWH): string;
  begin
    Result := Hex(R2.X) + ',' + Hex(R2.Y) + ',' + Hex(R2.W) + ',' + Hex(R2.H);
  end;

  function JoinHex(A: TJSONArray): string;
  var q: Integer;
  begin
    Result := '';
    for q := 0 to A.Count - 1 do
    begin
      if q > 0 then Result := Result + ',';
      Result := Result + A.Items[q].AsString;
    end;
  end;

  function StyleOn(AV: TJSONData): Boolean;
  begin
    Result := (AV <> nil) and (AV.JSONType = jtString) and (AV.AsString <> 'none');
  end;

begin
  cs := Fix.Arrays['engine'];
  n := 0;
  for i := 0 to cs.Count - 1 do
  begin
    c := cs.Objects[i];
    kind := c.Strings['kind'];
    if kind = 'bbox' then
    begin
      got := RectHex(TyPathDataRect(HexArr(c.Arrays['data'])));
      want := JoinHex(c.Arrays['out']);
    end
    else if kind = 'pathrect' then
    begin
      st := c.Objects['style'];
      data := HexArr(c.Arrays['data']);
      hasM := HexMat(c.Find('m'), m);
      lw := FromHex(st.Strings['lineWidth']);
      hasStroke := StyleOn(st.Find('stroke')) and (lw > 0);
      hasFill := StyleOn(st.Find('fill'));
      r := TyPathDataRect(data);
      if Length(data) > 0 then
        r := TyPathStrokeRect(r, hasStroke, hasFill, lw, st.Booleans['strokeNoScale'], hasM, m);
      got := RectHex(r);
      want := JoinHex(c.Arrays['out']);
    end
    else if kind = 'recompose' then
    begin
      HexMat(c.Find('m'), m);
      TyMorphRecompose(m, hasO, mo);
      if hasO then
        got := Hex(mo[0]) + ',' + Hex(mo[1]) + ',' + Hex(mo[2]) + ',' + Hex(mo[3]) + ','
          + Hex(mo[4]) + ',' + Hex(mo[5])
      else
        got := 'null';
      if c.Find('out').JSONType = jtArray then want := JoinHex(c.Arrays['out']) else want := 'null';
    end
    else if kind = 'sort' then
    begin
      SetLength(cx, c.Arrays['paths'].Count);
      SetLength(cy, c.Arrays['paths'].Count);
      for j := 0 to c.Arrays['paths'].Count - 1 do
      begin
        pth := c.Arrays['paths'].Objects[j];
        data := HexArr(pth.Arrays['data']);
        hasM := HexMat(pth.Find('m'), m);
        lw := FromHex(pth.Strings['lineWidth']);
        r := TyPathDataRect(data);
        if Length(data) > 0 then
          r := TyPathStrokeRect(r, StyleOn(pth.Find('stroke')) and (lw > 0), StyleOn(pth.Find('fill')),
            lw, False, hasM, m);
        if hasM then
        begin
          cx[j] := r.X + r.W / 2 + m[4];
          cy[j] := r.Y + r.H / 2 + m[5];
        end
        else
        begin
          cx[j] := r.X + r.W / 2;
          cy[j] := r.Y + r.H / 2;
        end;
      end;
      order := TyMorphSortOrder(cx, cy);
      got := '';
      for j := 0 to High(order) do
      begin
        if j > 0 then got := got + ',';
        got := got + IntToStr(order[j]);
      end;
      want := '';
      for j := 0 to c.Arrays['out'].Count - 1 do
      begin
        if j > 0 then want := want + ',';
        want := want + IntToStr(c.Arrays['out'].Integers[j]);
      end;
    end
    else
      Continue;
    Inc(n);
    Inc(FCompared);
    if got <> want then Miss(Format('%s: %s, upstream %s', [c.Strings['id'], got, want]));
  end;
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition 2 engine: %d compared', [n]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue('engine cases', n >= 30);
end;

procedure TAdvChartUniversalTransition2Test.TestEveryTransitionAsUpstream;
var
  cs: TJSONArray;
  i: Integer;
begin
  cs := Fix.Arrays['charts'];
  AssertTrue('chart cases', cs.Count >= 20);
  for i := 0 to cs.Count - 1 do RunCase(cs.Objects[i]);
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition 2: %d cases, %d compared, %d morph frames, %d child frames',
      [cs.Count, FCompared, FMorphs, FPieceFrames]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue('morph frames compared', FMorphs > 1000);
  AssertTrue('child frames compared', FPieceFrames > 1000);
end;

procedure TAdvChartUniversalTransition2Test.TestACombineDrawsItsChildrenAndEndsOnTheLayout;
var
  cs: TJSONArray;
  c: TJSONObject;
  i, at, k: Integer;
  frm: TTyPaintList;
  t1: Double;
  p: TTyChartAnimProxy;
begin
  { bars2-pie: each slice is drawn as two children while it combines -- the
    first in its place, the second after the list and silent -- and as its
    sector once it is done }
  cs := Fix.Arrays['charts'];
  c := nil;
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = 'bars2-pie' then c := cs.Objects[i];
  AssertTrue('bars2-pie case', c <> nil);
  t1 := Play(c);
  FChart.AnimTick(t1 + 200);
  frm := FChart.Frame;
  for i := 0 to 3 do
  begin
    p := FChart.AnimFindProxy(0, i, 'sector');
    AssertTrue('slice ' + IntToStr(i) + ' combines', (p <> nil) and p.CombineOn);
    AssertEquals('slice ' + IntToStr(i) + ': two children', 2, p.PieceCount);
    AssertEquals('slice ' + IntToStr(i) + ' itself not drawn', -1, FindEl(frm, 0, i, carSector, 0));
    for k := 1 to 2 do
    begin
      at := FindEl(frm, 0, i, carSector, k);
      AssertTrue(Format('slice %d child %d drawn', [i, k]), at >= 0);
      AssertTrue('a path', (frm.Element(at).Shape.Kind = cskPolygon)
        and (frm.Element(at).Shape.Cmds[0].Kind = pckMove));
      AssertEquals(Format('slice %d child %d silent', [i, k]), k > 1, frm.Element(at).Silent);
    end;
  end;
  FChart.AnimTick(t1 + 2000);
  frm := FChart.Frame;
  for i := 0 to 3 do
  begin
    at := FindEl(frm, 0, i, carSector, 0);
    AssertTrue('slice ' + IntToStr(i) + ' is drawn again', at >= 0);
    AssertTrue('slice ' + IntToStr(i) + ' is a sector again', frm.Element(at).Shape.Kind = cskSector);
    AssertFalse('slice ' + IntToStr(i) + ' not combining', FChart.AnimFindProxy(0, i, 'sector').CombineOn);
    AssertEquals('no child drawn', -1, FindEl(frm, 0, i, carSector, 1));
  end;
  AssertEquals('nothing left to run', 0, FChart.AnimClipCount);
end;

procedure TAdvChartUniversalTransition2Test.TestAListKeyWithAMissingItemTransitionsTheRest;
var
  t0: Double;
  i: Integer;
  p: TTyChartAnimProxy;
begin
  { seriesKey ['a', 'b'] with no old series 'b': upstream reads `.data` of
    undefined and throws out of setOption; the port leaves 'b' out and
    transitions from 'a' alone (one to one by id) }
  NewChart;
  t0 := Fix.Objects['clock'].Floats['T0'];
  FChart.Option := '{"color":["#5070dd"],"xAxis":{"type":"category","data":["A","B","C"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"bar","id":"a","universalTransition":true,'
    + '"data":[1,2,3]}]}';
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
  FChart.AnimTick(t0 + 5000);
  FChart.AnimNow := t0 + 10000;
  FChart.Option := '{"color":["#5070dd"],"series":[{"type":"pie","id":"p","label":{"show":false},'
    + '"universalTransition":{"enabled":true,"seriesKey":["a","b"]},'
    + '"data":[{"name":"A","value":1},{"name":"B","value":2},{"name":"C","value":3}]}]}';
  Draw;
  FChart.AnimTick(t0 + 10000 + 100);
  for i := 0 to 2 do
  begin
    p := FChart.AnimFindProxy(0, i, 'sector');
    AssertTrue('slice ' + IntToStr(i) + ' morphs from bar ' + IntToStr(i), (p <> nil) and p.MorphOn);
  end;
end;

initialization
  RegisterTest(TAdvChartUniversalTransition2Test);
finalization
  FreeAndNil(GFix);
end.
