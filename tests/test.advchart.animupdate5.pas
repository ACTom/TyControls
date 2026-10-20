unit test.advchart.animupdate5;
{$mode objfpc}{$H+}
{ THE UPDATE TRANSITIONS THE PORT DID NOT ANIMATE, HELD TO UPSTREAM
  [round-2 batch R2-I7].

  tools/advchart-oracle/anim-update5.js runs the real ECharts 6.1 build in
  node and samples, on the animation clock, what each case's probes name:

    markPoint  SymbolDraw's update diffs mpData by its ids: a max that moved
               to another category is a symbol that fades (leave timing)
               and one that pops in (enter timing), a symbol whose id stays
               slides (update timing);
    pictorial  a kept bar's update: the bundle's place, a repeated column's
               kept paths sliding on their {index, count} delays, new ones
               growing, extra ones shrinking and going, a single glyph's
               place / scale / turn, a symbolClip's clip;
    tmLabel    the treemap's labels after a merge: the kept ones ride their
               hosts (LabelManager's move is no move), the new ones fade in
               at enter timing.

  This replays every case through the control and compares, bit for bit,
  the proxies the control animates -- where it animates nothing, the
  element's rest values. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint, tyControls.AdvChart.Anim,
     tyControls.AdvChart.AnimView, tyControls.AdvChart.AnimOpt, tyControls.AdvChart.Shape,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax,
     test.advchart.graphic;
type
  TAu5Probe = class(TGfxProbe)
  public
    function Frame: TTyPaintList;
  end;

  TAdvChartAnimUpdate5OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAu5Probe;
    FRoot: TJSONData;
    FBad, FCompared, FSamples: Integer;
    FWhere, FReport: string;
    { [R2-I8] the case's last sample (every tween at rest): where a label's
      move is measured from }
    FLastRec: TJSONObject;
    FMerged: Boolean;
    procedure Bad(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure NearVal(const AWhat: string; AGot, AWant: Double);
    function FrameEl(ASeries, AIndex, ASub: Integer; ARole: TTyChartAnimRole;
      out AEl: TTyChartElement): Boolean;
    procedure SameKeyOr(const AWhat: string; P: TTyChartAnimProxy; const AKey: string;
      ARest: Double; AWant: TJSONData);
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    function ListEl(ASeries, AIndex: Integer; ARole: TTyChartAnimRole;
      out AEl: TTyChartElement; ASub: Integer = -1): Boolean;
    procedure ProbeMp(ARec: TJSONObject);
    procedure ProbePict(ARec: TJSONObject);
    procedure ProbePictGone(ARec: TJSONObject; const AName: string);
    procedure ProbeTml(ARec: TJSONObject);
    function HPidx30(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
    procedure CheckSample(const AProbes: TJSONArray; ARec: TJSONObject);
    procedure RunCase(ACase: TJSONObject);
    procedure RunGroup(const AGroup: string; AMin: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAMarkPointIsDiffedByItsIdAsUpstream;
    procedure TestAPictorialBarsUpdateAsUpstream;
    procedure TestATreemapsLabelsAfterAMergeAsUpstream;
  end;

implementation

const
  cNulMark = #$E2#$90#$80;

function TAu5Probe.Frame: TTyPaintList;
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

{ {"$fn": name} -> '@name', in place, everywhere }
procedure Au5Fns(AData: TJSONData);
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
      Au5Fns(child);
  end;
end;

{ an id as the fixture writes it: every NUL U+2400 }
function IdText(const AId: string): string;
begin
  Result := StringReplace(AId, #0, cNulMark, [rfReplaceAll]);
end;

{ ==================== the oracle ==================== }

function TAdvChartAnimUpdate5OracleTest.HPidx30(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
begin
  { (idx, params) => params && params.index != null ? params.index * 30 : 0 }
  if AParams.Present and AParams.HasIndex then Result := AParams.Index * 30
  else Result := 0;
end;

procedure TAdvChartAnimUpdate5OracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath('advchart-anim-update5.json')));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-anim-update5.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  Au5Fns(FRoot);
  TyChartRegisterAnimDelay('pidx*30', @HPidx30);
  FChart := nil;
  FBad := 0;
  FCompared := 0;
  FSamples := 0;
  FReport := '';
end;

procedure TAdvChartAnimUpdate5OracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  TyChartUnregisterAnimDelay('pidx*30');
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAnimUpdate5OracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartAnimUpdate5OracleTest.SameNum(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := WantNum(AWant);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TAdvChartAnimUpdate5OracleTest.NearVal(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if IsNan(AWant) or IsNan(AGot) or (Abs(AGot - AWant) > 1e-6) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(AWant)]));
end;

{ an element of the frame drawn now }
function TAdvChartAnimUpdate5OracleTest.FrameEl(ASeries, AIndex, ASub: Integer;
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
    if (e.Anim.Role = ARole) and (e.Anim.Series = ASeries) and (e.Anim.Index = AIndex)
      and (e.Anim.Sub = ASub) then
    begin
      AEl := e;
      Exit(True);
    end;
  end;
end;

{ the proxy's key where it holds one, else the rest value }
procedure TAdvChartAnimUpdate5OracleTest.SameKeyOr(const AWhat: string;
  P: TTyChartAnimProxy; const AKey: string; ARest: Double; AWant: TJSONData);
var v: TTyAnimValue;
begin
  if P <> nil then
  begin
    v := P.GetAnimProp(AKey);
    if v.Kind = avkNumber then
    begin
      SameNum(AWhat + '.' + AKey, v.Num, AWant);
      Exit;
    end;
  end;
  SameNum(AWhat + '.' + AKey + ' (rest)', ARest, AWant);
end;

procedure TAdvChartAnimUpdate5OracleTest.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TAu5Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TAdvChartAnimUpdate5OracleTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ an element of the render standing (its rest values) }
function TAdvChartAnimUpdate5OracleTest.ListEl(ASeries, AIndex: Integer;
  ARole: TTyChartAnimRole; out AEl: TTyChartElement; ASub: Integer): Boolean;
var
  l: TTyPaintList;
  i: Integer;
  e: TTyChartElement;
begin
  Result := False;
  AEl := Default(TTyChartElement);
  l := FChart.List;
  if l = nil then Exit;
  for i := 0 to l.Count - 1 do
  begin
    e := l.Element(i);
    if (e.Anim.Role <> ARole) or (e.Anim.Series <> ASeries) or (e.Anim.Index <> AIndex) then
      Continue;
    if (ASub >= 0) and (e.Anim.Sub <> ASub) then Continue;
    AEl := e;
    Exit(True);
  end;
end;

{ ---- markPoint: the live symbols by mpData index, the gone ones by id ---- }
procedure TAdvChartAnimUpdate5OracleTest.ProbeMp(ARec: TJSONObject);
var
  i, k, s, idx, slash, n, g: Integer;
  name, rest: string;
  leaf, o: TJSONObject;
  gone: TJSONArray;
  p: TTyChartAnimProxy;
  el: TTyChartElement;
  found: Boolean;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'mp' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    rest := Copy(name, slash + 1, MaxInt);
    if rest = 'gone' then
    begin
      gone := ARec.Arrays[name];
      n := 0;
      for g := 0 to FChart.AnimGhostCount - 1 do
      begin
        p := FChart.AnimGhostAt(g);
        if (p = nil) or (p.Role <> 'markPoint') or (p.Series <> s) then Continue;
        Inc(n);
        found := False;
        for k := 0 to gone.Count - 1 do
        begin
          o := gone.Objects[k];
          if o.Strings['id'] <> IdText(p.Ghost.Anim.Key) then Continue;
          found := True;
          SameKeyOr(name + ' ' + o.Strings['id'], p, 'x', NaN, o.Find('x'));
          SameKeyOr(name + ' ' + o.Strings['id'], p, 'y', NaN, o.Find('y'));
          SameKeyOr(name + ' ' + o.Strings['id'], p, 'scaleX', NaN, o.Find('sx'));
          SameKeyOr(name + ' ' + o.Strings['id'], p, 'scaleY', NaN, o.Find('sy'));
          SameKeyOr(name + ' ' + o.Strings['id'], p, 'style.opacity', NaN, o.Find('op'));
        end;
        Inc(FCompared);
        if not found then Bad(name + ': the port fades ' + IdText(p.Ghost.Anim.Key) + ', upstream does not');
      end;
      Inc(FCompared);
      if n <> gone.Count then
        Bad(Format('%s: %d fading, upstream %d', [name, n, gone.Count]));
      Continue;
    end;
    idx := StrToInt(rest);
    leaf := TJSONObject(ARec.Items[i]);
    Inc(FCompared);
    if not ListEl(s, idx, carMarkPoint, el) then
    begin
      Bad(name + ': not drawn');
      Continue;
    end;
    Inc(FCompared);
    if IdText(el.Anim.Key) <> leaf.Strings['id'] then
      Bad(Format('%s: id %s, upstream %s', [name, IdText(el.Anim.Key), leaf.Strings['id']]));
    p := FChart.AnimFindProxy(s, idx, 'markPoint');
    Inc(FCompared);
    if (p = nil) and (leaf.Integers['n'] > 0) then
      Bad(name + ': upstream animates it, the port has no proxy');
    SameKeyOr(name, p, 'x', el.Anim.G[0], leaf.Find('x'));
    SameKeyOr(name, p, 'y', el.Anim.G[1], leaf.Find('y'));
    SameKeyOr(name, p, 'scaleX', el.Anim.G[2], leaf.Find('sx'));
    SameKeyOr(name, p, 'scaleY', el.Anim.G[3], leaf.Find('sy'));
    SameKeyOr(name, p, 'style.opacity', el.Anim.G[4], leaf.Find('op'));
  end;
end;

{ ---- pictorial: the bundle, its paths, the clip ---- }
procedure TAdvChartAnimUpdate5OracleTest.ProbePict(ARec: TJSONObject);
var
  i, k, s, idx, slash, ai, live, ghosts, g: Integer;
  name, rk: string;
  leaf, pa, cl: TJSONObject;
  paths: TJSONArray;
  p: TTyChartAnimProxy;
  el, any, fe: TTyChartElement;
  clipBar: Boolean;
  bx: TTyRectF;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'pb' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    if Copy(name, slash + 1, MaxInt) = 'gone' then
    begin
      ProbePictGone(ARec, name);
      Continue;
    end;
    idx := StrToInt(Copy(name, slash + 1, MaxInt));
    leaf := TJSONObject(ARec.Items[i]);
    clipBar := not IsNull(leaf.Find('clip'));
    Inc(FCompared);
    if clipBar then
    begin
      if not ListEl(s, idx, carPictorialClip, any) then
      begin
        Bad(name + ': no glyph drawn');
        Continue;
      end;
    end
    else if not ListEl(s, idx, carPictorialGlyph, any) then
    begin
      Bad(name + ': no glyph drawn');
      Continue;
    end;
    { the bundle }
    p := FChart.AnimFindProxy(s, idx, 'pbundle');
    SameKeyOr(name + ' bundle', p, 'x', any.Caption.LgG[6], leaf.Find('x'));
    SameKeyOr(name + ' bundle', p, 'y', any.Caption.LgG[7], leaf.Find('y'));
    { the clip: its length along the value axis }
    if clipBar then
    begin
      cl := leaf.Objects['clip'];
      p := FChart.AnimFindProxy(s, idx, 'pclip');
      if any.Anim.G[1] <> 0 then
        SameKeyOr(name + ' clip', p, 'shape.height', any.Anim.G[2], cl.Arrays['sh'].Items[3])
      else
        SameKeyOr(name + ' clip', p, 'shape.width', any.Anim.G[2], cl.Arrays['sh'].Items[2]);
    end;
    { [R2-I8] THE BAR RECT, the label's host: its shape on its proxy, and
      as the frame draws it }
    if not IsNull(leaf.Find('rect')) then
    begin
      Inc(FCompared);
      if not ListEl(s, idx, carPictorialRect, el) then
        Bad(name + ': no bar rect')
      else
      begin
        p := FChart.AnimFindProxy(s, idx, 'prect');
        Inc(FCompared);
        if (p = nil) and (leaf.Integers['rn'] > 0) then
          Bad(name + ' rect: upstream tweens it, the port has no proxy');
        SameKeyOr(name + ' rect', p, 'shape.x', el.Anim.G[0], leaf.Arrays['rect'].Items[0]);
        SameKeyOr(name + ' rect', p, 'shape.y', el.Anim.G[1], leaf.Arrays['rect'].Items[1]);
        SameKeyOr(name + ' rect', p, 'shape.width', el.Anim.G[2], leaf.Arrays['rect'].Items[2]);
        SameKeyOr(name + ' rect', p, 'shape.height', el.Anim.G[3], leaf.Arrays['rect'].Items[3]);
        if FrameEl(s, idx, el.Anim.Sub, carPictorialRect, fe) then
        begin
          bx := TyShapeBounds(fe.Shape);
          NearVal(name + ' rect drawn top', bx.Top,
            Min(WantNum(leaf.Arrays['rect'].Items[1]),
              WantNum(leaf.Arrays['rect'].Items[1]) + WantNum(leaf.Arrays['rect'].Items[3])));
          NearVal(name + ' rect drawn left', bx.Left,
            Min(WantNum(leaf.Arrays['rect'].Items[0]),
              WantNum(leaf.Arrays['rect'].Items[0]) + WantNum(leaf.Arrays['rect'].Items[2])));
          NearVal(name + ' rect drawn height', bx.Bottom - bx.Top,
            Abs(WantNum(leaf.Arrays['rect'].Items[3])));
        end;
      end;
    end;
    { [R2-I8] THE LABEL rides its host: its move from where it rests is
      upstream's (the text's computed translation against the last
      sample's) }
    if FMerged and (not IsNull(leaf.Find('label'))) and (FLastRec <> nil)
      and (FLastRec.Find(name) is TJSONObject)
      and not IsNull(TJSONObject(FLastRec.Find(name)).Find('label')) then
    begin
      cl := TJSONObject(TJSONObject(FLastRec.Find(name)).Find('label'));
      Inc(FCompared);
      if not (ListEl(s, idx, carLabel, el) and FrameEl(s, idx, el.Anim.Sub, carLabel, fe)) then
        Bad(name + ': no label drawn')
      else
      begin
        NearVal(name + ' label moved x', fe.Caption.X - el.Caption.X,
          WantNum(leaf.Objects['label'].Find('gx')) - WantNum(cl.Find('gx')));
        NearVal(name + ' label moved y', fe.Caption.Y - el.Caption.Y,
          WantNum(leaf.Objects['label'].Find('gy')) - WantNum(cl.Find('gy')));
      end;
    end;
    { the paths: how many (the live ones and the ones shrinking), and each }
    paths := leaf.Arrays['paths'];
    live := 0;
    ghosts := 0;
    for k := 0 to FChart.List.Count - 1 do
    begin
      el := FChart.List.Element(k);
      if (el.Anim.Series = s) and (el.Anim.Index = idx)
        and (el.Anim.Role in [carPictorialGlyph, carPictorialClip]) then Inc(live);
    end;
    for g := 0 to FChart.AnimGhostCount - 1 do
    begin
      p := FChart.AnimGhostAt(g);
      if (p <> nil) and (p.Series = s) and (p.Index = idx) and (Copy(p.Role, 1, 6) = 'pglyph') then
        Inc(ghosts);
    end;
    Inc(FCompared);
    if live + ghosts <> paths.Count then
      Bad(Format('%s: %d paths (%d shrinking), upstream %d', [name, live + ghosts, ghosts, paths.Count]));
    for k := 0 to paths.Count - 1 do
    begin
      pa := paths.Objects[k];
      if IsNull(pa.Find('ai')) then ai := 0 else ai := pa.Integers['ai'];
      rk := 'pglyph' + IntToStr(ai);
      if clipBar then
      begin
        { [R2-I8] a clipped column's paths tween on their own proxies
          [Revised in R2-I8: their rest was compared, the paths stood] }
        if not ListEl(s, idx, carPictorialClip, el, ai) then Continue;
        p := FChart.AnimFindProxy(s, idx, 'pcpath' + IntToStr(ai));
        Inc(FCompared);
        if (p = nil) and (pa.Integers['n'] > 0) then
          Bad(Format('%s path %d: upstream animates it, the port has no proxy', [name, ai]));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'x', el.Caption.LgG[0], pa.Find('x'));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'y', el.Caption.LgG[1], pa.Find('y'));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'scaleX', el.Caption.LgG[2], pa.Find('sx'));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'scaleY', el.Caption.LgG[3], pa.Find('sy'));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'rotation', el.Caption.LgG[5], pa.Find('rot'));
        if (WantNum(pa.Find('sx')) <> 0) and (WantNum(pa.Find('sy')) <> 0)
          and FrameEl(s, idx, ai, carPictorialClip, fe) then
        begin
          bx := TyShapeBounds(fe.Shape);
          if TyRectFIsValid(bx) then
          begin
            NearVal(Format('%s path %d drawn x', [name, ai]), (bx.Left + bx.Right) / 2,
              WantNum(pa.Find('gx')));
            NearVal(Format('%s path %d drawn y', [name, ai]), (bx.Top + bx.Bottom) / 2,
              WantNum(pa.Find('gy')));
          end;
        end;
        Continue;
      end;
      if ListEl(s, idx, carPictorialGlyph, el, ai) then
      begin
        p := FChart.AnimFindProxy(s, idx, rk);
        Inc(FCompared);
        if (p = nil) and (pa.Integers['n'] > 0) then
          Bad(Format('%s path %d: upstream animates it, the port has no proxy', [name, ai]));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'x', el.Caption.LgG[0], pa.Find('x'));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'y', el.Caption.LgG[1], pa.Find('y'));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'scaleX', el.Anim.G[2], pa.Find('sx'));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'scaleY', el.Anim.G[3], pa.Find('sy'));
        SameKeyOr(Format('%s path %d', [name, ai]), p, 'rotation', el.Anim.G[5], pa.Find('rot'));
        { THE FRAME: the path drawn about the bundle's place plus its own
          (a rect is symmetric about its place, turned or not) }
        if (WantNum(pa.Find('sx')) <> 0) and (WantNum(pa.Find('sy')) <> 0)
          and FrameEl(s, idx, ai, carPictorialGlyph, fe) then
        begin
          bx := TyShapeBounds(fe.Shape);
          if TyRectFIsValid(bx) then
          begin
            NearVal(Format('%s path %d drawn x', [name, ai]), (bx.Left + bx.Right) / 2,
              WantNum(leaf.Find('x')) + WantNum(pa.Find('x')));
            NearVal(Format('%s path %d drawn y', [name, ai]), (bx.Top + bx.Bottom) / 2,
              WantNum(leaf.Find('y')) + WantNum(pa.Find('y')));
          end;
        end;
      end
      else
      begin
        { past the new count: the ghost that shrinks }
        p := FChart.AnimFindGhost(s, idx, rk);
        Inc(FCompared);
        if p = nil then
        begin
          Bad(Format('%s path %d: upstream shrinks it, the port has no ghost', [name, ai]));
          Continue;
        end;
        SameKeyOr(Format('%s path %d (going)', [name, ai]), p, 'scaleX', NaN, pa.Find('sx'));
        SameKeyOr(Format('%s path %d (going)', [name, ai]), p, 'scaleY', NaN, pa.Find('sy'));
        SameNum(Format('%s path %d (going).x', [name, ai]), p.Ghost.Caption.LgG[0], pa.Find('x'));
        SameNum(Format('%s path %d (going).y', [name, ai]), p.Ghost.Caption.LgG[1], pa.Find('y'));
        { [R2-I8] AS DRAWN: in its bundle as the bundle is now
          [Revised in R2-I8: it stayed where the old bundle was] }
        if (WantNum(pa.Find('sx')) <> 0) and (WantNum(pa.Find('sy')) <> 0)
          and FrameEl(s, idx, ai, carPictorialGlyph, fe) then
        begin
          bx := TyShapeBounds(fe.Shape);
          if TyRectFIsValid(bx) then
          begin
            NearVal(Format('%s path %d (going) drawn x', [name, ai]), (bx.Left + bx.Right) / 2,
              WantNum(pa.Find('gx')));
            NearVal(Format('%s path %d (going) drawn y', [name, ai]), (bx.Top + bx.Bottom) / 2,
              WantNum(pa.Find('gy')));
          end;
        end;
      end;
    end;
  end;
end;

{ ---- [R2-I8] the bars removeBar is shrinking ---- }
procedure TAdvChartAnimUpdate5OracleTest.ProbePictGone(ARec: TJSONObject;
  const AName: string);
var
  gone, paths: TJSONArray;
  b, k, g, s, ai, want, got: Integer;
  pa: TJSONObject;
  p: TTyChartAnimProxy;
  found: Boolean;
  e: TTyChartElement;
  bx: TTyRectF;
  l: TTyPaintList;
  j: Integer;
begin
  s := StrToInt(Copy(AName, 3, Pos('/', AName) - 3));
  gone := ARec.Arrays[AName];
  want := 0;
  for b := 0 to gone.Count - 1 do
    Inc(want, gone.Objects[b].Arrays['paths'].Count);
  { the removed bars' paths still drawn: the ghosts of no kept column }
  got := 0;
  for g := 0 to FChart.AnimGhostCount - 1 do
  begin
    p := FChart.AnimGhostAt(g);
    if (p <> nil) and (p.Series = s) and not p.Gone and not p.PictRide
      and (Copy(p.Role, 1, 6) = 'pglyph') then Inc(got);
  end;
  Inc(FCompared);
  if got <> want then
    Bad(Format('%s: %d paths of removed bars, upstream %d', [AName, got, want]));
  for b := 0 to gone.Count - 1 do
  begin
    paths := gone.Objects[b].Arrays['paths'];
    for k := 0 to paths.Count - 1 do
    begin
      pa := paths.Objects[k];
      if IsNull(pa.Find('ai')) then ai := 0 else ai := pa.Integers['ai'];
      found := False;
      for g := 0 to FChart.AnimGhostCount - 1 do
      begin
        p := FChart.AnimGhostAt(g);
        if (p <> nil) and (p.Series = s) and not p.Gone and not p.PictRide
          and (p.Role = 'pglyph' + IntToStr(ai)) then
        begin
          found := True;
          Break;
        end;
      end;
      Inc(FCompared);
      if not found then
      begin
        Bad(Format('%s path %d: upstream shrinks it, the port has no ghost', [AName, ai]));
        Continue;
      end;
      SameKeyOr(Format('%s path %d', [AName, ai]), p, 'scaleX', NaN, pa.Find('sx'));
      SameKeyOr(Format('%s path %d', [AName, ai]), p, 'scaleY', NaN, pa.Find('sy'));
      { as drawn: about its place }
      if (WantNum(pa.Find('sx')) <> 0) and (WantNum(pa.Find('sy')) <> 0) then
      begin
        l := FChart.Frame;
        if l = nil then Continue;
        for j := 0 to l.Count - 1 do
        begin
          e := l.Element(j);
          if (e.Anim.Role = carPictorialGlyph) and (e.Anim.Series = s)
            and (e.Anim.Index = p.Index) and (e.Anim.Sub = ai) then
          begin
            bx := TyShapeBounds(e.Shape);
            NearVal(Format('%s path %d drawn x', [AName, ai]), (bx.Left + bx.Right) / 2,
              WantNum(pa.Find('gx')));
            NearVal(Format('%s path %d drawn y', [AName, ai]), (bx.Top + bx.Bottom) / 2,
              WantNum(pa.Find('gy')));
            Break;
          end;
        end;
      end;
    end;
  end;
end;

{ ---- the treemap's labels: their fade (their own layout never moves) ---- }
procedure TAdvChartAnimUpdate5OracleTest.ProbeTml(ARec: TJSONObject);
var
  i, s, idx, slash: Integer;
  name: string;
  leaf: TJSONObject;
  p: TTyChartAnimProxy;
begin
  for i := 0 to ARec.Count - 1 do
  begin
    name := ARec.Names[i];
    if Copy(name, 1, 2) <> 'tl' then Continue;
    slash := Pos('/', name);
    s := StrToInt(Copy(name, 3, slash - 3));
    idx := StrToInt(Copy(name, slash + 1, MaxInt));
    leaf := TJSONObject(ARec.Items[i]);
    p := FChart.TreemapAnimProxy(s, idx, 'label');
    Inc(FCompared);
    if (p = nil) and (leaf.Integers['n'] > 0) then
    begin
      Bad(name + ': upstream fades it, the port has no proxy');
      Continue;
    end;
    SameKeyOr(name, p, 'style.opacity', 1, leaf.Find('op'));
    { the layout in the host's frame: nought, upstream's too }
    SameNum(name + '.x', 0, leaf.Find('x'));
    SameNum(name + '.y', 0, leaf.Find('y'));
  end;
end;

procedure TAdvChartAnimUpdate5OracleTest.CheckSample(const AProbes: TJSONArray;
  ARec: TJSONObject);
var i: Integer;
begin
  for i := 0 to AProbes.Count - 1 do
    if AProbes.Strings[i] = 'mp' then ProbeMp(ARec)
    else if AProbes.Strings[i] = 'pict' then ProbePict(ARec)
    else if AProbes.Strings[i] = 'tml' then ProbeTml(ARec)
    else Bad('a probe the test does not know: ' + AProbes.Strings[i]);
end;

procedure TAdvChartAnimUpdate5OracleTest.RunCase(ACase: TJSONObject);
var
  events: TJSONArray;
  ev: TJSONObject;
  j: Integer;
  t0, now_: Double;
  act: string;
begin
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  t0 := TJSONObject(FRoot).Objects['clock'].Floats['T0'];
  FChart.AnimationMode := camAlways;
  FChart.AnimNow := t0;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
  events := ACase.Arrays['events'];
  { [R2-I8] the last sample: every tween at rest -- the label's measure
    after the merge }
  FLastRec := nil;
  FMerged := False;
  for j := events.Count - 1 downto 0 do
    if events.Objects[j].Strings['do'] = 'sample' then
    begin
      FLastRec := events.Objects[j].Objects['rec'];
      Break;
    end;
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
      CheckSample(ACase.Arrays['probes'], ev.Objects['rec']);
    end
    else if act = 'frame' then
    begin
      FChart.AnimTick(now_);
      RenderNow;
    end
    else if act = 'merge' then
    begin
      FChart.SetOption(ev.Objects['option'].AsJSON, False);
      FMerged := True;
      RenderNow;
    end
    else
      Bad('an event it does not know: ' + act);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

procedure TAdvChartAnimUpdate5OracleTest.RunGroup(const AGroup: string; AMin: Integer);
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
        on E: Exception do
        begin
          Bad(E.ClassName + ': ' + E.Message);
          if FChart <> nil then FChart.Measurer := nil;
          FreeAndNil(FChart);
        end;
      end;
      Inc(n);
    end;
  AssertTrue('cases run', n > 0);
  if FBad > 0 then
    Fail(Format('%s: %d of %d comparisons differ from upstream:%s',
      [AGroup, FBad, FCompared, FReport]));
  AssertTrue(Format('%s: comparisons made (%d)', [AGroup, FCompared]), FCompared >= AMin);
end;

procedure TAdvChartAnimUpdate5OracleTest.TestAMarkPointIsDiffedByItsIdAsUpstream;
begin
  RunGroup('markPoint', 300);
end;

procedure TAdvChartAnimUpdate5OracleTest.TestAPictorialBarsUpdateAsUpstream;
begin
  RunGroup('pictorial', 1000);
end;

procedure TAdvChartAnimUpdate5OracleTest.TestATreemapsLabelsAfterAMergeAsUpstream;
begin
  RunGroup('tmLabel', 100);
end;

initialization
  RegisterTest(TAdvChartAnimUpdate5OracleTest);
end.
