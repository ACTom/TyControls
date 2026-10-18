unit test.advchart.rootinherit;
{$mode objfpc}{$H+}
{ The option root reaching the models through their parent, and the grid's
  box as getLayoutRect lays it out -- held to upstream to the bit [F4c].

  tools/advchart-oracle/root-inherit.js runs ECharts 6.1 at 600 x 400 and
  records, per case: getBoxLayoutParams() of the component or series the
  case is about (its six keys raw, the root's where the model's own option
  leaves one null or undefined) and the rect the model lays out by it -- a
  grid's and a single axis' getRect(), a title's group and frame, a tree's,
  a treemap's and a sankey's layoutInfo, a pie's centre and radius, a
  parallel's rect; a series view group's `silent` and a markLine's under the
  root's `silent`, with the bar and the line to hit-test; getProgressive(),
  getProgressiveThreshold() and progressiveChunkMode with the root's under
  them. Every option of the fixture also goes through the diagnostics, which
  must not call a root key the models read unknown. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Layout, tyControls.AdvChart.Builder,
     tyControls.AdvChart.Single, tyControls.AdvChart.Parallel,
     tyControls.AdvChart.Title, tyControls.AdvChart.Legend,
     tyControls.AdvChart.Pie, tyControls.AdvChart.Funnel,
     tyControls.AdvChart.Tree, tyControls.AdvChart.Calendar,
     tyControls.AdvChart.Sankey, tyControls.AdvChart.Treemap,
     tyControls.AdvChart.Progressive, tyControls.AdvChart.Diagnose,
     tyControls.AdvanceChart,
     test.advchart.boxmerge;
type
  TRootProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function TargetAt(AX, AY: Integer): TTyChartEventTarget;
  end;

  TAdvChartRootInheritOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FOpt: TTyChartOption;
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TRootProbe;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameRect(const AWhat: string; const R: TTyXYWH; AWant: TJSONData);
    procedure SameRaw(const AWhat: string; const AGot: TTyBoxRaw; AWant: TJSONData);
    procedure SameRawBox(const AWhat: string; const AGot: TTyRawBox; AWant: TJSONData);
    procedure SameValue(const AWhat: string; const AGot: TTyBoxValue; AWant: TJSONData);
    procedure Verdict(AMinimum: Integer);
    procedure Load(ACase: TJSONObject);
    procedure Draw(ACase: TJSONObject);
    function Cases(const AGroup: string): TJSONArray;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGridIsLaidOutAsUpstream;
    procedure TestTheSingleAxisIsLaidOutAsUpstream;
    procedure TestTheRootReachesTheBoxes;
    procedure TestTheRootSilencesTheSeries;
    procedure TestTheRootProgressiveReachesTheSeries;
    procedure TestTheDiagnosticsKnowTheRootKeys;
    procedure TestTheClimbNeedsAnObjectRoot;
  end;

implementation

const
  cBoxKeys: array[0..5] of string = ('left', 'top', 'right', 'bottom', 'width', 'height');

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-root-inherit.json';
end;

function LoadJson(const APath: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function H(A: TJSONData): Double;
begin
  if (A = nil) or (A.JSONType <> jtString) then Exit(NaN);
  Result := FromHex(A.AsString);
end;

function Bits(A: Double): QWord;
begin
  Result := 0;
  Move(A, Result, SizeOf(Result));
end;

function SameBits(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function RawOf(const ABox: TTyRawBox; AK: Integer): TTyBoxRaw;
begin
  case AK of
    0: Result := ABox.Left;
    1: Result := ABox.Top;
    2: Result := ABox.Right;
    3: Result := ABox.Bottom;
    4: Result := ABox.Width;
  else
    Result := ABox.Height;
  end;
end;

function ValueOf(const ASpec: TTyBoxSpec; AK: Integer): TTyBoxValue;
begin
  case AK of
    0: Result := ASpec.Left;
    1: Result := ASpec.Top;
    2: Result := ASpec.Right;
    3: Result := ASpec.Bottom;
    4: Result := ASpec.Width;
  else
    Result := ASpec.Height;
  end;
end;

{ ---- the probe ---- }

procedure TRootProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TRootProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function TRootProbe.TargetAt(AX, AY: Integer): TTyChartEventTarget;
begin
  Result := EventTargetAt(AX, AY);
end;

{ ---- the harness ---- }

procedure TAdvChartRootInheritOracleTest.SetUp;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  FOpt := TTyChartOption.Create;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TRootProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := nil;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartRootInheritOracleTest.TearDown;
begin
  FreeAndNil(FBmp);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  FreeAndNil(FOpt);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartRootInheritOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartRootInheritOracleTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if not SameBits(AGot, H(AWant)) then
    Miss(Format('%s %s here, upstream %s', [AWhat, FloatToStr(AGot), FloatToStr(H(AWant))]));
end;

procedure TAdvChartRootInheritOracleTest.SameRect(const AWhat: string;
  const R: TTyXYWH; AWant: TJSONData);
var o: TJSONObject;
begin
  if not (AWant is TJSONObject) then
  begin
    Miss(AWhat + ': no upstream rect');
    Exit;
  end;
  o := TJSONObject(AWant);
  SameH(AWhat + ' x', R.X, o.Find('x'));
  SameH(AWhat + ' y', R.Y, o.Find('y'));
  SameH(AWhat + ' width', R.W, o.Find('width'));
  SameH(AWhat + ' height', R.H, o.Find('height'));
end;

{ a raw box key against upstream's getBoxLayoutParams value: '<undef>'
  absent, null null, {n} a number to the bit, a string the same string }
procedure TAdvChartRootInheritOracleTest.SameRaw(const AWhat: string;
  const AGot: TTyBoxRaw; AWant: TJSONData);
var ok: Boolean;
begin
  Inc(FCompared);
  if AWant = nil then ok := False
  else if AWant.JSONType = jtNull then ok := AGot.Kind = brNull
  else if AWant.JSONType = jtObject then
    ok := (AGot.Kind = brNumber) and SameBits(AGot.Num, H(TJSONObject(AWant).Find('n')))
  { undefined: absent, or a null the merge left (getLayoutRect and the
    keyword's `||` read the two alike) }
  else if AWant.AsString = '<undef>' then ok := AGot.Kind in [brAbsent, brNull]
  else ok := (AGot.Kind = brString) and (AGot.Str = AWant.AsString);
  if not ok then
    Miss(Format('%s: kind %d %s / %s here, upstream %s', [AWhat, Ord(AGot.Kind),
      FloatToStr(AGot.Num), AGot.Str, AWant.AsJSON]));
end;

procedure TAdvChartRootInheritOracleTest.SameRawBox(const AWhat: string;
  const AGot: TTyRawBox; AWant: TJSONData);
var k: Integer;
begin
  if not (AWant is TJSONObject) then
  begin
    Miss(AWhat + ': no upstream box');
    Exit;
  end;
  for k := 0 to 5 do
    SameRaw(AWhat + '.' + cBoxKeys[k], RawOf(AGot, k), TJSONObject(AWant).Find(cBoxKeys[k]));
end;

{ a parsed box value (a pie's, a funnel's): a number its px to the bit, a
  value upstream leaves undefined or null the port's auto }
procedure TAdvChartRootInheritOracleTest.SameValue(const AWhat: string;
  const AGot: TTyBoxValue; AWant: TJSONData);
var ok: Boolean;
begin
  Inc(FCompared);
  if AWant = nil then ok := False
  else if AWant.JSONType = jtObject then
    ok := (AGot.Kind = buPx) and SameBits(AGot.Value, H(TJSONObject(AWant).Find('n')))
  else if (AWant.JSONType = jtNull) or (AWant.AsString = '<undef>') then
    ok := AGot.Kind = buAuto
  else ok := True;   { a string: parsed by the shared reader, not compared }
  if not ok then
    Miss(Format('%s: kind %d %s here, upstream %s', [AWhat, Ord(AGot.Kind),
      FloatToStr(AGot.Value), AWant.AsJSON]));
end;

procedure TAdvChartRootInheritOracleTest.Verdict(AMinimum: Integer);
begin
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared >= AMinimum);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ from upstream:' + FReport, 0, FBad);
end;

function TAdvChartRootInheritOracleTest.Cases(const AGroup: string): TJSONArray;
var
  all: TJSONArray;
  i: Integer;
begin
  Result := TJSONArray.Create;
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Strings['group'] = AGroup then
      Result.Add(all.Objects[i].Clone);
end;

procedure TAdvChartRootInheritOracleTest.Load(ACase: TJSONObject);
begin
  FName := ACase.Strings['id'];
  AssertTrue(FName + ' parses', FOpt.SetOptionText(ACase.Objects['option'].AsJSON));
end;

procedure TAdvChartRootInheritOracleTest.Draw(ACase: TJSONObject);
begin
  FName := ACase.Strings['id'];
  FreeAndNil(FBmp);
  FBmp := TBGRABitmap.Create(ACase.Integers['W'], ACase.Integers['H'], BGRAWhite);
  FChart.Option := ACase.Objects['option'].AsJSON;
  FChart.SetBounds(0, 0, ACase.Integers['W'], ACase.Integers['H']);
  FChart.Render(FBmp.Canvas, Rect(0, 0, ACase.Integers['W'], ACase.Integers['H']), 96);
end;

{ ==================== the grid ==================== }

procedure TAdvChartRootInheritOracleTest.TestTheGridIsLaidOutAsUpstream;
var
  arr: TJSONArray;
  cs: TJSONObject;
  c: Integer;
  build: TTyChartBuild;
begin
  arr := Cases('grid');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      Load(cs);
      build := TyBuildGrids(FOpt, TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']));
      try
        Inc(FCompared);
        if build.GridCount < 1 then
        begin
          Miss('no grid');
          Continue;
        end;
        SameRect('grid', build.Grid(0).OuterXYWH, cs.Find('grid'));
      finally
        build.Free;
      end;
    end;
  finally
    arr.Free;
  end;
  Verdict(13 * 5);
end;

procedure TAdvChartRootInheritOracleTest.TestTheSingleAxisIsLaidOutAsUpstream;
var
  arr: TJSONArray;
  cs: TJSONObject;
  c, k: Integer;
  singles: TTySingleArray;
begin
  arr := Cases('single');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      Load(cs);
      singles := TyBuildSingles(FOpt, TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']));
      try
        Inc(FCompared);
        if (Length(singles) < 1) or (singles[0] = nil) then
        begin
          Miss('no single axis');
          Continue;
        end;
        SameRect('single', singles[0].Rect, cs.Find('single'));
      finally
        for k := 0 to High(singles) do singles[k].Free;
      end;
    end;
  finally
    arr.Free;
  end;
  Verdict(2 * 5);
end;

{ ==================== the boxes ==================== }

procedure TAdvChartRootInheritOracleTest.TestTheRootReachesTheBoxes;
var
  arr: TJSONArray;
  cs, t: TJSONObject;
  c, k, q: Integer;
  ts: TTyTitleSpec;
  tl: TTyTitleLayout;
  meas: TTableMeasurer;
  mi: ITyTextMeasurer;
  f, sf: TTyTitleFont;
  pie: TTyPieSpec;
  fun: TTyFunnelSpec;
  pars: TTyParallelArray;
  lst: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
begin
  f.Name := 'x';
  f.SizeLogical := 18;
  f.Weight := 700;
  sf.Name := 'x';
  sf.SizeLogical := 12;
  sf.Weight := 400;
  arr := Cases('box');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      Load(cs);
      if cs.Find('titleBox') <> nil then
      begin
        ts := TyTitleSpecOf(FOpt, 0);
        SameRawBox('title box', ts.Box, cs.Find('titleBox'));
        t := cs.Objects['title'];
        meas := TTableMeasurer.Create;
        mi := meas;
        meas.Add(ts.Text, H(t.Objects['measured'].Find('width')),
          H(t.Objects['measured'].Find('height')));
        tl := TyLayoutTitle(ts, TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']),
          mi, f, sf, 96);
        Inc(FCompared);
        if not tl.Valid then Miss('no title layout')
        else
        begin
          SameH('title x', tl.TextX, t.Find('x'));
          SameH('title y', tl.TextY, t.Find('y'));
          SameH('title frame x', tl.FrameX, t.Objects['bg'].Find('x'));
          SameH('title frame y', tl.FrameY, t.Objects['bg'].Find('y'));
          SameH('title frame width', tl.FrameW, t.Objects['bg'].Find('width'));
          SameH('title frame height', tl.FrameH, t.Objects['bg'].Find('height'));
        end;
      end;
      if cs.Find('legendBox') <> nil then
        SameRawBox('legend box', TyLegendSpecOf(FOpt, 0).Box, cs.Find('legendBox'));
      if cs.Find('calendarBox') <> nil then
        SameRawBox('calendar box', TyCalendarSpecOf(FOpt, 0).Box, cs.Find('calendarBox'));
      if cs.Find('treeBox') <> nil then
        SameRawBox('tree box', TyTreeSpecOf(FOpt, 0).Box, cs.Find('treeBox'));
      if cs.Find('funnelBox') <> nil then
      begin
        fun := TyFunnelSpecOf(FOpt, 0);
        for k := 0 to 5 do
          SameValue('funnel box.' + cBoxKeys[k], ValueOf(fun.Box, k),
            TJSONObject(cs.Find('funnelBox')).Find(cBoxKeys[k]));
      end;
      if cs.Find('pieBox') <> nil then
      begin
        q := 0;
        if cs.Find('legendBox') <> nil then q := 0;
        pie := TyPieSpecOf(FOpt, q);
        for k := 0 to 5 do
          SameValue('pie box.' + cBoxKeys[k], ValueOf(pie.Box, k),
            TJSONObject(cs.Find('pieBox')).Find(cBoxKeys[k]));
      end;
      if cs.Find('parallel') <> nil then
      begin
        pars := TyBuildParallels(FOpt, TyRectF(0, 0, cs.Integers['W'], cs.Integers['H']));
        try
          Inc(FCompared);
          if (Length(pars) < 1) or (pars[0] = nil) then Miss('no parallel')
          else SameRect('parallel', pars[0].Rect, cs.Find('parallel'));
        finally
          for k := 0 to High(pars) do pars[k].Free;
        end;
      end;
      { the series laid out by the control itself }
      if (cs.Find('tree') <> nil) or (cs.Find('treemap') <> nil)
        or (cs.Find('sankey') <> nil) or (cs.Find('pie') <> nil) then
      begin
        Draw(cs);
        if cs.Find('tree') <> nil then
          SameRect('tree layoutInfo', FChart.TreeSolved(0).Box, cs.Find('tree'));
        if cs.Find('treemap') <> nil then
          SameRect('treemap layoutInfo', FChart.TreemapSolved(0).Box, cs.Find('treemap'));
        if cs.Find('sankey') <> nil then
          SameRect('sankey layoutInfo', FChart.SankeySolved(0).Box, cs.Find('sankey'));
        if cs.Find('pie') <> nil then
        begin
          lst := FChart.List;
          found := False;
          for k := 0 to lst.Count - 1 do
          begin
            e := lst.Element(k);
            if (e.Shape.Kind <> cskSector) or (e.Datum.RawDataIndex <> 0) then Continue;
            found := True;
            SameH('pie cx', e.Shape.CX, cs.Objects['pie'].Find('cx'));
            SameH('pie cy', e.Shape.CY, cs.Objects['pie'].Find('cy'));
            SameH('pie r', e.Shape.R1, cs.Objects['pie'].Find('r'));
            Break;
          end;
          Inc(FCompared);
          if not found then Miss('no first sector');
        end;
      end;
    end;
  finally
    arr.Free;
  end;
  Verdict(80);
end;

{ ==================== silent ==================== }

procedure TAdvChartRootInheritOracleTest.TestTheRootSilencesTheSeries;
var
  arr: TJSONArray;
  cs, b, ml: TJSONObject;
  c, x, y: Integer;
  d: TTyChartDatumRef;
  tg: TTyChartEventTarget;
  wantSilent: Boolean;
begin
  arr := Cases('silent');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      Draw(cs);
      b := cs.Objects['bar'];
      { the bar's centre: its rect is upstream's (no label moves the grid) }
      x := Round(H(b.Find('x')) + H(b.Find('width')) / 2);
      y := Round(H(b.Find('y')) + H(b.Find('height')) / 2);
      d := FChart.HitTestAt(x, y);
      wantSilent := cs.Booleans['seriesSilent'];
      Inc(FCompared);
      if wantSilent and (d.SeriesIndex >= 0) then
        Miss(Format('the bar at %d,%d answers the pointer; upstream''s series is silent', [x, y]))
      else if (not wantSilent) and ((d.SeriesIndex <> 0) or (d.RawDataIndex <> 1)) then
        Miss(Format('the bar at %d,%d does not answer the pointer (series %d row %d)',
          [x, y, d.SeriesIndex, d.RawDataIndex]));
      if cs.Find('markLine') <> nil then
      begin
        ml := cs.Objects['markLine'];
        x := Round((H(ml.Find('x1')) + H(ml.Find('x2'))) / 2);
        y := Round(H(ml.Find('y1')));
        tg := FChart.TargetAt(x, y);
        Inc(FCompared);
        if cs.Booleans['markerSilent'] and tg.HasData
          and (tg.Params.ComponentType = 'markLine') then
          Miss(Format('the markLine at %d,%d answers the pointer; upstream''s is silent', [x, y]))
        else if (not cs.Booleans['markerSilent'])
          and not (tg.HasData and (tg.Params.ComponentType = 'markLine')) then
          Miss(Format('the markLine at %d,%d does not answer the pointer', [x, y]));
      end;
    end;
  finally
    arr.Free;
  end;
  Verdict(6);
end;

{ ==================== progressive ==================== }

procedure TAdvChartRootInheritOracleTest.TestTheRootProgressiveReachesTheSeries;
var
  arr, progs: TJSONArray;
  cs, p: TJSONObject;
  c, k: Integer;
  node: TJSONObject;
  spec: TTyProgSpec;
  want, wantTh: Double;
  wantOn, wantMod: Boolean;
  v: TJSONData;
begin
  arr := Cases('prog');
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      Load(cs);
      progs := cs.Arrays['prog'];
      for k := 0 to progs.Count - 1 do
      begin
        p := progs.Objects[k];
        node := TJSONObject(FOpt.ComponentAt('series', k));
        spec := TyProgSpecOf(p.Strings['type'], node, TJSONObject(FOpt.Root));
        { getProgressive: false or a falsy value turns it off; a step is
          Math.round of it }
        v := p.Find('progressive');
        wantOn := False;
        want := NaN;
        if v.JSONType = jtObject then
        begin
          want := H(TJSONObject(v).Find('n'));
          wantOn := (not IsNan(want)) and (want <> 0);
        end;
        Inc(FCompared);
        if spec.Enabled <> wantOn then
          Miss(Format('series %d: progressive %s here, upstream %s',
            [k, BoolToStr(spec.Enabled, True), v.AsJSON]))
        else if wantOn then
        begin
          Inc(FCompared);
          if spec.Step <> Round(want) then
            Miss(Format('series %d: step %d here, upstream %s', [k, spec.Step, FloatToStr(want)]));
        end;
        v := p.Find('threshold');
        if v.JSONType = jtObject then wantTh := H(TJSONObject(v).Find('n'))
        else wantTh := NaN;
        Inc(FCompared);
        if not SameBits(spec.Threshold, wantTh) then
          Miss(Format('series %d: threshold %s here, upstream %s',
            [k, FloatToStr(spec.Threshold), v.AsJSON]));
        v := p.Find('chunkMode');
        wantMod := (v.JSONType = jtString) and (v.AsString = 'mod');
        Inc(FCompared);
        if spec.ModMode <> wantMod then
          Miss(Format('series %d: chunk mode mod %s here, upstream %s',
            [k, BoolToStr(spec.ModMode, True), v.AsJSON]));
      end;
    end;
  finally
    arr.Free;
  end;
  Verdict(9 * 3);
end;

{ ==================== the diagnostics ==================== }

procedure TAdvChartRootInheritOracleTest.TestTheDiagnosticsKnowTheRootKeys;
var
  all: TJSONArray;
  cs: TJSONObject;
  c, i: Integer;
  diags: TTyOptDiagArray;
  root: TJSONObject;
  k: Integer;
  key: string;
begin
  all := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to all.Count - 1 do
  begin
    cs := all.Objects[c];
    FName := cs.Strings['id'];
    diags := TyOptDiagnose(cs.Objects['option'].AsJSON);
    root := cs.Objects['option'];
    for k := 0 to root.Count - 1 do
    begin
      key := root.Names[k];
      if (key <> 'left') and (key <> 'top') and (key <> 'right') and (key <> 'bottom')
        and (key <> 'width') and (key <> 'height') and (key <> 'silent')
        and (key <> 'progressive') and (key <> 'progressiveThreshold')
        and (key <> 'progressiveChunkMode') then Continue;
      Inc(FCompared);
      for i := 0 to High(diags) do
        if (diags[i].Kind = odkUnknownOption) and (diags[i].Path = key) then
          Miss('the root ' + key + ' is reported: ' + diags[i].Text);
    end;
  end;
  Verdict(20);
end;

{ ==================== no object root ==================== }

{ the climb reads the root only when it is an object: none (no option) or
  an option that is no object leaves a null or missing key as it was }
procedure TAdvChartRootInheritOracleTest.TestTheClimbNeedsAnObjectRoot;
var
  box: TTyRawBox;
  arr: TJSONArray;
  obj: TJSONObject;
begin
  box := Default(TTyRawBox);
  box.Left.Kind := brNull;
  TyBoxClimbRoot(box, nil);
  AssertTrue('no root: the null stays', box.Left.Kind = brNull);
  AssertTrue('no root: the missing stays', box.Width.Kind = brAbsent);
  arr := TJSONArray.Create([10]);
  try
    TyBoxClimbRoot(box, arr);
    AssertTrue('an array root: the null stays', box.Left.Kind = brNull);
    AssertTrue('an array root: the missing stays', box.Width.Kind = brAbsent);
  finally
    arr.Free;
  end;
  obj := TJSONObject.Create(['left', 10, 'width', 'auto']);
  try
    TyBoxClimbRoot(box, obj);
    AssertTrue('an object root: its left', (box.Left.Kind = brNumber) and (box.Left.Num = 10));
    AssertTrue('an object root: its width', (box.Width.Kind = brString) and (box.Width.Str = 'auto'));
  finally
    obj.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartRootInheritOracleTest);
end.
