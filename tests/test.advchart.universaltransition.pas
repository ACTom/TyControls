unit test.advchart.universaltransition;
{$mode objfpc}{$H+}
{ THE UNIVERSAL TRANSITION ON THE REAL CONTROL, held to upstream.
  [Batch 136, D5 UT1]

  tests/fixtures/advchart-universal-transition.json's `charts`, from the
  real ECharts 6.1 build under the hand-driven clock: the first option at
  T0 and run out (or, in flight, `mid` ms into its enter), the second set
  whole at T1, recorded at T1 + 0, 1, 16, 50, 100, 150, 250, 300, 400, 499,
  500, 501, 750, 1000 and 1500 ms. Bars become slices and slices bars; bars
  become scatter symbols and line symbols, symbols bars; turned triangles,
  a ring, rounded and horizontal bars, bars with a border; ids that match,
  ids that do not, a seriesKey; the transition off on either side, the
  new series not animating; names that do not all match, a missing old
  element; the update timing, the transition's delay, both divideShapes;
  the same series recoloured; the next option arriving in flight.

  Each case runs on a TTyAdvanceChart (zrender's SSR text measure, 400 x
  300, camAlways) the oracle's way, and at every sample every item element
  upstream recorded is found in the frame by its series, data index and
  role, and compared:

    - whether it is morphing, and the path its morph draws -- every command
      and every number of the replaced buildPath, bit for bit;
    - its fill and stroke (as the painter's colours) and its opacity (bit
      for bit), its line width where it strokes;
    - an element that is not morphing: every transform and shape key
      upstream tracks, on its proxy, bit for bit;
  and every other path of the new views (a line's polyline and area): its
  opacity, the fade every path with no animation gets. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Measure,
     tyControls.AdvChart.Color,
     tyControls.AdvChart.Anim, tyControls.AdvChart.AnimOpt,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.Morph,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TUtProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Frame: TTyPaintList;
  end;

  TAdvChartUniversalTransitionTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TUtProbe;
    FMeasure: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FMorphs: Integer;
    FReport: string;
    FSeen: TStringList;
    procedure Miss(const AWhere: string; const AOnce: string = '');
    function HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
    function HUt120(ADataIndex: Integer; AHasIndex: Boolean): Double;
    procedure NewChart;
    procedure Draw;
    procedure RunCase(ACase: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryTransitionAsUpstream;
    procedure TestAMorphDrawsOnePathAndEndsOnTheLayout;
    procedure TestNoTransitionWithoutAnUpdate;
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
        + 'advchart-universal-transition.json');
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

function TUtProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TUtProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TUtProbe.Frame: TTyPaintList;
begin
  Result := AnimFrame;
end;

{ ==================== plumbing ==================== }

function TAdvChartUniversalTransitionTest.HIdx50(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  if AHasIndex then Result := ADataIndex * 50 else Result := NaN;
end;

function TAdvChartUniversalTransitionTest.HUt120(ADataIndex: Integer; AHasIndex: Boolean): Double;
begin
  { (idx, count) => 120 + idx * 50 + (count - 1) * 1000: the count is 1 one
    to one, and the handler is given the index alone }
  if AHasIndex then Result := 120 + ADataIndex * 50 else Result := NaN;
end;

procedure TAdvChartUniversalTransitionTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  TyChartRegisterAnimTiming('idx*50', @HIdx50);
  TyChartRegisterAnimTiming('ut120', @HUt120);
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
  FReport := '';
end;

procedure TAdvChartUniversalTransitionTest.TearDown;
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

procedure TAdvChartUniversalTransitionTest.Miss(const AWhere: string; const AOnce: string);
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

procedure TAdvChartUniversalTransitionTest.NewChart;
begin
  FreeAndNil(FChart);
  FChart := TUtProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FMeasure).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FMeasure).Objects['ratios'].Integers['firstCode']));
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := Fix.Objects['clock'].Floats['T0'];
end;

procedure TAdvChartUniversalTransitionTest.Draw;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
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

{ the frame element of (series, row, role); -1 for none }
function FindEl(AList: TTyPaintList; ASeries, ARow: Integer; ARole: TTyChartAnimRole): Integer;
var
  i: Integer;
  el: TTyChartElement;
begin
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Anim.Role = ARole) and (el.Anim.Series = ASeries)
      and ((ARow < 0) or (el.Anim.Index = ARow)) then Exit(i);
  end;
  Result := -1;
end;

{ two different values among a key's samples }
function Moves(A: TJSONArray): Boolean;
var
  i: Integer;
  first: string;
  have: Boolean;
begin
  Result := False;
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

procedure TAdvChartUniversalTransitionTest.RunCase(ACase: TJSONObject);
var
  samples, els: TJSONArray;
  s, e, k, at: Integer;
  el, st, sn: TJSONObject;
  t1, t, mid: Double;
  id, cid, key, pk: string;
  frm: TTyPaintList;
  fe: TTyChartElement;
  role: TTyChartAnimRole;
  p: TTyChartAnimProxy;
  d: TTyDoubleArray;
  dw: TJSONArray;
  isMorph: Boolean;
  want: TTyChartColor;
  v: TTyAnimValue;
  sv: TJSONData;
  strokes: Boolean;
begin
  cid := ACase.Strings['id'];
  NewChart;
  FChart.Option := OptionText(ACase.Elements['option']);
  AssertEquals(cid + ': the option parses', '', FChart.OptionError);
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
  if ACase.Find('mid').JSONType = jtNumber then
  begin
    { in flight: frames at 16, mid / 2 and mid }
    mid := ACase.Floats['mid'];
    FChart.AnimTick(Fix.Objects['clock'].Floats['T0'] + 16);
    FChart.AnimTick(Fix.Objects['clock'].Floats['T0'] + mid / 2);
    FChart.AnimTick(Fix.Objects['clock'].Floats['T0'] + mid);
    t1 := Fix.Objects['clock'].Floats['T0'] + mid;
  end
  else
  begin
    t := 16;
    while t <= 5000 do
    begin
      FChart.AnimTick(Fix.Objects['clock'].Floats['T0'] + t);
      t := t + 250;
    end;
    t1 := Fix.Objects['clock'].Floats['T0'] + Fix.Objects['clock'].Floats['T1Offset'];
  end;
  FChart.AnimNow := t1;
  FChart.Option := OptionText(ACase.Elements['next']);
  AssertEquals(cid + ': the next option parses', '', FChart.OptionError);
  Draw;
  if ACase.Find('then').JSONType = jtObject then
  begin
    { a third option while the second one's transition runs }
    mid := ACase.Objects['then'].Floats['at'];
    FChart.AnimTick(t1 + 16);
    FChart.AnimTick(t1 + mid / 2);
    FChart.AnimTick(t1 + mid);
    t1 := t1 + mid;
    FChart.AnimNow := t1;
    FChart.Option := OptionText(ACase.Objects['then'].Elements['next']);
    AssertEquals(cid + ': the third option parses', '', FChart.OptionError);
    Draw;
  end;
  samples := Fix.Arrays['samplesMs'];
  els := ACase.Arrays['elements'];
  for s := 0 to samples.Count - 1 do
  begin
    if s > 0 then FChart.AnimTick(t1 + samples.Items[s].AsFloat);
    frm := FChart.Frame;
    for e := 0 to els.Count - 1 do
    begin
      el := els.Objects[e];
      id := Format('%s t=%s %s', [cid, samples.Items[s].AsString, el.Strings['id']]);
      if not el.Booleans['item'] then
      begin
        { another path of the view: a line's polyline or area fades }
        if el.Strings['type'] = 'ec-polyline' then role := carLineRun
        else if el.Strings['type'] = 'ec-polygon' then role := carLineArea
        else
        begin
          Miss(id + ': a ' + el.Strings['type'] + ' is not mapped', cid + el.Strings['id']);
          Continue;
        end;
        at := FindEl(frm, el.Integers['series'], -1, role);
        if at < 0 then
        begin
          if PresentAt(el, s) then Miss(id + ': no element here', cid + el.Strings['id']);
          Continue;
        end;
        if not PresentAt(el, s) then Continue;
        sv := el.Objects['style'].Arrays['opacity'].Items[s];
        if sv.JSONType <> jtString then Continue;
        Inc(FCompared);
        fe := frm.Element(at);
        if Hex(fe.Style.Alpha) <> sv.AsString then
          Miss(Format('%s: opacity %s, upstream %s', [id, FloatToStr(fe.Style.Alpha),
            FloatToStr(FromHex(sv.AsString))]), cid + el.Strings['id'] + 'op');
        Continue;
      end;
      role := RoleOfType(el.Strings['seriesType']);
      at := FindEl(frm, el.Integers['series'], el.Integers['dataIndex'], role);
      if not PresentAt(el, s) then
      begin
        if at >= 0 then Miss(id + ': drawn here, not upstream', cid + el.Strings['id'] + 'gone');
        Continue;
      end;
      if at < 0 then
      begin
        Miss(id + ': no element here', cid + el.Strings['id'] + 'none');
        Continue;
      end;
      fe := frm.Element(at);
      p := FChart.AnimFindProxy(el.Integers['series'], el.Integers['dataIndex'], ProxyRoleOf(role));
      { THE MORPH }
      isMorph := (el.Find('morph') is TJSONArray) and el.Arrays['morph'].Items[s].AsBoolean;
      Inc(FCompared);
      if isMorph <> ((p <> nil) and p.MorphOn) then
        Miss(Format('%s: morphing %s here, upstream %s', [id, BoolToStr((p <> nil) and p.MorphOn, True),
          BoolToStr(isMorph, True)]), cid + el.Strings['id'] + 'morph' + IntToStr(Ord(isMorph)));
      if isMorph then
      begin
        Inc(FMorphs);
        d := CmdsData(fe);
        dw := el.Arrays['d'].Arrays[s];
        Inc(FCompared);
        if Length(d) <> dw.Count then
          Miss(Format('%s: the morph draws %d numbers, upstream %d', [id, Length(d), dw.Count]),
            cid + el.Strings['id'] + 'dlen')
        else
          for k := 0 to High(d) do
            if Hex(d[k]) <> dw.Strings[k] then
            begin
              Miss(Format('%s: the morph path [%d] %s, upstream %s', [id, k, FloatToStr(d[k]),
                FloatToStr(FromHex(dw.Strings[k]))]), cid + el.Strings['id'] + 'd');
              Break;
            end;
      end
      else
      begin
        { THE KEYS UPSTREAM TRACKS, on the proxy }
        sn := el.Objects['snap'];
        for k := 0 to sn.Count - 1 do
        begin
          key := sn.Names[k];
          { only the keys that move }
          if not Moves(TJSONArray(sn.Items[k])) then Continue;
          sv := sn.Items[k].Items[s];
          if sv.JSONType <> jtString then Continue;
          pk := key;
          if Copy(pk, 1, 2) = 'g.' then pk := Copy(pk, 3, MaxInt);
          { a scatter symbol's path scale and opacity, its group's place, are
            the symbol proxy's; a line symbol's group scale its own }
          if (role = carLineSymbol) and ((key = 'scaleX') or (key = 'scaleY')) then Continue;
          if p = nil then
          begin
            Miss(id + ': no proxy for a tracked ' + key, cid + el.Strings['id'] + 'np');
            Continue;
          end;
          v := p.GetAnimProp(pk);
          Inc(FCompared);
          if v.Kind <> avkNumber then
            Miss(Format('%s: %s not held here', [id, key]), cid + el.Strings['id'] + key)
          else if Hex(v.Num) <> sv.AsString then
            Miss(Format('%s: %s %s, upstream %s', [id, key, FloatToStr(v.Num),
              FloatToStr(FromHex(sv.AsString))]), cid + el.Strings['id'] + key);
        end;
      end;
      { THE STYLE }
      st := el.Objects['style'];
      sv := st.Arrays['fill'].Items[s];
      if sv.JSONType = jtString then
      begin
        Inc(FCompared);
        if not TyTryParseChartColor(sv.AsString, want) then
          Miss(id + ': fill ' + sv.AsString + ' does not parse')
        else if (not fe.Style.HasFill) or (fe.Style.FillColor <> want) then
          Miss(Format('%s: fill %s, upstream %s', [id, IntToHex(fe.Style.FillColor, 8),
            sv.AsString]), cid + el.Strings['id'] + 'fill');
      end;
      sv := st.Arrays['stroke'].Items[s];
      strokes := sv.JSONType = jtString;
      if strokes then
      begin
        Inc(FCompared);
        if not TyTryParseChartColor(sv.AsString, want) then
          Miss(id + ': stroke ' + sv.AsString + ' does not parse')
        else if fe.Style.StrokeColor <> want then
          Miss(Format('%s: stroke %s, upstream %s', [id, IntToHex(fe.Style.StrokeColor, 8),
            sv.AsString]), cid + el.Strings['id'] + 'stroke');
        sv := st.Arrays['lineWidth'].Items[s];
        if sv.JSONType = jtString then
        begin
          Inc(FCompared);
          if Hex(fe.Style.StrokeWidthLogical) <> sv.AsString then
            Miss(Format('%s: lineWidth %s, upstream %s', [id, FloatToStr(fe.Style.StrokeWidthLogical),
              FloatToStr(FromHex(sv.AsString))]), cid + el.Strings['id'] + 'lw');
        end;
      end;
      sv := st.Arrays['opacity'].Items[s];
      if sv.JSONType = jtString then
      begin
        Inc(FCompared);
        if Hex(fe.Style.Alpha) <> sv.AsString then
          Miss(Format('%s: opacity %s, upstream %s', [id, FloatToStr(fe.Style.Alpha),
            FloatToStr(FromHex(sv.AsString))]), cid + el.Strings['id'] + 'op');
      end;
    end;
  end;
end;

procedure TAdvChartUniversalTransitionTest.TestEveryTransitionAsUpstream;
var
  cs: TJSONArray;
  i: Integer;
begin
  cs := Fix.Arrays['charts'];
  AssertTrue('chart cases', cs.Count >= 33);
  for i := 0 to cs.Count - 1 do RunCase(cs.Objects[i]);
  if GetEnvironmentVariable('TY_UT_COUNTS') = '1' then
    WriteLn(Format('universal transition: %d cases, %d compared, %d morph frames',
      [cs.Count, FCompared, FMorphs]));
  AssertTrue(Format('%d of %d differ from upstream:%s', [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue('morph frames compared', FMorphs > 800);
end;

procedure TAdvChartUniversalTransitionTest.TestAMorphDrawsOnePathAndEndsOnTheLayout;
var
  cs: TJSONArray;
  c: TJSONObject;
  i, at: Integer;
  frm, lst: TTyPaintList;
  t0: Double;
begin
  { bar -> pie: the slices are polygons of cubics while the morph runs and
    the layout's slices when it is done }
  cs := Fix.Arrays['charts'];
  c := nil;
  for i := 0 to cs.Count - 1 do
    if cs.Objects[i].Strings['id'] = 'bar-pie' then c := cs.Objects[i];
  AssertTrue('bar-pie case', c <> nil);
  NewChart;
  t0 := Fix.Objects['clock'].Floats['T0'];
  FChart.Option := OptionText(c.Elements['option']);
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
  FChart.AnimTick(t0 + 5000);
  FChart.AnimNow := t0 + 10000;
  FChart.Option := OptionText(c.Elements['next']);
  Draw;
  FChart.AnimTick(t0 + 10000 + 200);
  frm := FChart.Frame;
  for i := 0 to 3 do
  begin
    at := FindEl(frm, 0, i, carSector);
    AssertTrue('slice ' + IntToStr(i) + ' drawn', at >= 0);
    AssertTrue('slice ' + IntToStr(i) + ' is a path while it morphs',
      (frm.Element(at).Shape.Kind = cskPolygon) and (Length(frm.Element(at).Shape.Cmds) > 0));
    AssertTrue('its first command is a move', frm.Element(at).Shape.Cmds[0].Kind = pckMove);
  end;
  FChart.AnimTick(t0 + 10000 + 2000);
  frm := FChart.Frame;
  for i := 0 to 3 do
  begin
    at := FindEl(frm, 0, i, carSector);
    AssertTrue('slice ' + IntToStr(i) + ' is a sector again', frm.Element(at).Shape.Kind = cskSector);
    AssertFalse('slice ' + IntToStr(i) + ' not morphing',
      FChart.AnimFindProxy(0, i, 'sector').MorphOn);
  end;
  AssertEquals('nothing left to run', 0, FChart.AnimClipCount);
end;

procedure TAdvChartUniversalTransitionTest.TestNoTransitionWithoutAnUpdate;
var
  t0: Double;
  i: Integer;
begin
  { the first option is no transition: there was nothing before it }
  NewChart;
  t0 := Fix.Objects['clock'].Floats['T0'];
  FChart.Option := '{"color":["#5070dd"],"series":[{"type":"pie","universalTransition":true,'
    + '"label":{"show":false},"data":[{"name":"A","value":1},{"name":"B","value":2}]}]}';
  FChart.SetBounds(0, 0, cW, cH);
  Draw;
  FChart.AnimTick(t0 + 100);
  for i := 0 to 1 do
    AssertFalse('no morph on a first render', FChart.AnimFindProxy(0, i, 'sector').MorphOn);
end;

initialization
  RegisterTest(TAdvChartUniversalTransitionTest);
finalization
  FreeAndNil(GFix);
end.
