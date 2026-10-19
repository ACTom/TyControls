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
     tyControls.AdvanceChart, LCLType,
     test.advchart.boxmerge, test.advchart.keyboard;
type
  TRootProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    function TargetAt(AX, AY: Integer): TTyChartEventTarget;
    function Key(AKey: Word; AShift: TShiftState = []): Word;
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
    procedure SameD(const AWhat: string; AGot, AWant: Double);
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
    procedure TestTheRootReachesFurtherDownTheChain;
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

function TRootProbe.Key(AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  KeyDown(Result, AShift);
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

procedure TAdvChartRootInheritOracleTest.SameD(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not SameBits(AGot, AWant) then
    Miss(Format('%s %s here, upstream %s', [AWhat, FloatToStr(AGot), FloatToStr(AWant)]));
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
        { [R2-G] where getLayoutRect put it: the first trapezium }
        if cs.Find('funnelPoints') <> nil then
        begin
          Draw(cs);
          lst := FChart.List;
          found := False;
          for k := 0 to lst.Count - 1 do
          begin
            e := lst.Element(k);
            if (e.Shape.Kind <> cskPolygon) or (e.Datum.SeriesIndex <> 0)
              or (e.Datum.DataIndex <> 0) or (e.Caption.Text <> '') then Continue;
            found := True;
            for q := 0 to cs.Arrays['funnelPoints'].Count - 1 do
            begin
              SameH(Format('funnel point %d x', [q]), e.Shape.Points[q].X,
                cs.Arrays['funnelPoints'].Arrays[q].Items[0]);
              SameH(Format('funnel point %d y', [q]), e.Shape.Points[q].Y,
                cs.Arrays['funnelPoints'].Arrays[q].Items[1]);
            end;
            Break;
          end;
          Inc(FCompared);
          if not found then Miss('no first trapezium');
        end;
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

{ ==================== further down the chain [R2-G] ==================== }

{ the first element of series ASer at data index AIdx whose shape is one of
  AKinds, a caption excluded; -1 for none }
type
  TShapeKinds = set of TTyChartShapeKind;

function ElementOf(AList: TTyPaintList; ASer, AIdx: Integer; AKinds: TShapeKinds): Integer;
var k: Integer; e: TTyChartElement;
begin
  for k := 0 to AList.Count - 1 do
  begin
    e := AList.Element(k);
    if (e.Datum.Kind = ctkSeries) and (e.Datum.SeriesIndex = ASer) and (e.Datum.DataIndex = AIdx)
      and not e.Datum.IsEdge and (e.Caption.Text = '') and (e.Shape.Kind in AKinds) then Exit(k);
  end;
  Result := -1;
end;

procedure TAdvChartRootInheritOracleTest.TestTheRootReachesFurtherDownTheChain;
var
  arr, ser, items: TJSONArray;
  cs, it: TJSONObject;
  c, s, i, k: Integer;
  e: TTyChartElement;
  b: TTyRectF;
  x0, x1, y0, y1, ang: Double;
  sel: TTyIntegerArray;
  log: TKbLog;
  zs: string;
  hl: TJSONData;
begin
  { before: a root stack, a bar size, a candlestick's width, a treemap's
    or the graphic component's z, legendHoverLink and a scatter's symbol
    were not read -- each series answered from its own option and defaults }
  arr := Cases('climb');
  log := TKbLog.Create;
  try
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      Draw(cs);
      { bars: each one's box }
      if cs.Find('bars') <> nil then
      begin
        ser := cs.Arrays['bars'];
        for s := 0 to ser.Count - 1 do
        begin
          items := ser.Arrays[s];
          for i := 0 to items.Count - 1 do
          begin
            it := items.Objects[i];
            k := ElementOf(FChart.List, s, i, [cskRect, cskRoundRect]);
            Inc(FCompared);
            if k < 0 then
            begin
              Miss(Format('no bar %d/%d', [s, i]));
              Continue;
            end;
            b := FChart.List.Element(k).Shape.Bounds;
            x0 := H(it.Find('x'));
            x1 := x0 + H(it.Find('width'));
            y0 := H(it.Find('y'));
            y1 := y0 + H(it.Find('height'));
            SameD(Format('bar %d/%d left', [s, i]), b.Left, Min(x0, x1));
            SameD(Format('bar %d/%d right', [s, i]), b.Right, Max(x0, x1));
            SameD(Format('bar %d/%d top', [s, i]), b.Top, Min(y0, y1));
            SameD(Format('bar %d/%d bottom', [s, i]), b.Bottom, Max(y0, y1));
          end;
        end;
      end;
      { a line's points: its symbols' centres }
      if cs.Find('points') <> nil then
      begin
        ser := cs.Arrays['points'];
        for s := 0 to ser.Count - 1 do
        begin
          items := ser.Arrays[s];
          for i := 0 to items.Count - 1 do
          begin
            it := items.Objects[i];
            k := ElementOf(FChart.List, s, i, [cskCircle, cskEllipse, cskPolygon, cskPath]);
            Inc(FCompared);
            if k < 0 then
            begin
              Miss(Format('no symbol %d/%d', [s, i]));
              Continue;
            end;
            e := FChart.List.Element(k);
            if e.Shape.Kind in [cskCircle, cskEllipse] then
            begin
              SameD(Format('point %d/%d x', [s, i]), e.Shape.CX, H(it.Find('x')));
              SameD(Format('point %d/%d y', [s, i]), e.Shape.CY, H(it.Find('y')));
            end
            else
            begin
              b := TyShapeBounds(e.Shape);
              SameD(Format('point %d/%d x', [s, i]), (b.Left + b.Right) / 2, H(it.Find('x')));
              SameD(Format('point %d/%d y', [s, i]), (b.Top + b.Bottom) / 2, H(it.Find('y')));
            end;
          end;
        end;
      end;
      { a polar bar's ring: its radii, and how wide it turns }
      if cs.Find('polar') <> nil then
      begin
        ser := cs.Arrays['polar'];
        for s := 0 to ser.Count - 1 do
        begin
          items := ser.Arrays[s];
          for i := 0 to items.Count - 1 do
          begin
            it := items.Objects[i];
            k := ElementOf(FChart.List, s, i, [cskSector]);
            Inc(FCompared);
            if k < 0 then
            begin
              Miss(Format('no polar bar %d/%d', [s, i]));
              Continue;
            end;
            e := FChart.List.Element(k);
            SameD(Format('polar %d/%d r0', [s, i]), e.Shape.R0, H(it.Find('r0')));
            SameD(Format('polar %d/%d r', [s, i]), e.Shape.R1, H(it.Find('r')));
            Inc(FCompared);
            if Abs(Abs(e.Shape.EndRad - e.Shape.StartRad)
              - Abs(H(it.Find('endAngle')) - H(it.Find('startAngle')))) > 1e-12 then
              Miss(Format('polar %d/%d sweep %s, upstream %s', [s, i,
                FloatToStr(Abs(e.Shape.EndRad - e.Shape.StartRad)),
                FloatToStr(Abs(H(it.Find('endAngle')) - H(it.Find('startAngle'))))]));
          end;
        end;
      end;
      { a candle's body: the brushRect's width }
      if cs.Find('candles') <> nil then
      begin
        items := cs.Arrays['candles'];
        for i := 0 to items.Count - 1 do
        begin
          k := ElementOf(FChart.List, 0, i, [cskPolygon, cskRect, cskPath]);
          Inc(FCompared);
          if k < 0 then
          begin
            Miss(Format('no candle %d', [i]));
            Continue;
          end;
          b := TyShapeBounds(FChart.List.Element(k).Shape);
          SameD(Format('candle %d body width', [i]), b.Right - b.Left, H(items.Objects[i].Find('bodyWidth')));
        end;
      end;
      { the selection a select action leaves }
      if cs.Find('selected') <> nil then
      begin
        FChart.DispatchAction('{"type":"select","seriesIndex":0,"dataIndex":1}');
        sel := FChart.SelectedDataIndices(0);
        Inc(FCompared);
        if Length(sel) <> cs.Arrays['selected'].Count then
          Miss(Format('%d selected here, %d upstream', [Length(sel), cs.Arrays['selected'].Count]));
      end;
      { a treemap's z }
      if cs.Strings['id'] = 'c-treemap-z' then
      begin
        k := ElementOf(FChart.List, 0, 1, [cskRect, cskRoundRect]);
        Inc(FCompared);
        if k < 0 then Miss('no treemap rect')
        else if FChart.List.Element(k).Z <> cs.Integers['z'] then
          Miss(Format('treemap z %d, upstream %d', [FChart.List.Element(k).Z, cs.Integers['z']]));
      end;
      { the graphic rects' z }
      if cs.Find('zs') <> nil then
      begin
        zs := '';
        for k := 0 to FChart.List.Count - 1 do
          if FChart.List.Element(k).Datum.Kind = ctkGraphic then
          begin
            if zs <> '' then zs := zs + ',';
            zs := zs + IntToStr(FChart.List.Element(k).Z);
          end;
        Inc(FCompared);
        if zs <> '7,0' then Miss('graphic z ' + zs + ', upstream 7,0');
      end;
      { legendHoverLink: a series whose get() is falsy is excluded from the
        legend item's highlight }
      if cs.Find('hoverLink') <> nil then
      begin
        log.Lines.Clear;
        AssertTrue(FChart.ChartOn('highlight', @log.Handle) >= 0);
        FChart.Key(VK_TAB);
        Inc(FCompared);
        { the heatmap (series 0) reads the root's false, the bar its own
          true default }
        if log.Lines.Count < 1 then Miss('no highlight from the legend')
        else
        begin
          hl := GetJSON(Copy(log.Lines[0], Length('highlight ') + 1, MaxInt));
          try
            if not ((hl is TJSONObject) and (TJSONObject(hl).Find('excludeSeriesId') is TJSONArray)
              and (TJSONArray(TJSONObject(hl).Find('excludeSeriesId')).Count = 1)) then
              Miss('the legend''s highlight: ' + log.Text);
          finally
            hl.Free;
          end;
        end;
      end;
      { a scatter's symbol: the root's rect, turned the root's 30 degrees }
      if cs.Find('symbols') <> nil then
      begin
        k := ElementOf(FChart.List, 0, 0, [cskPolygon, cskRect, cskCircle, cskPath]);
        Inc(FCompared);
        if k < 0 then Miss('no scatter symbol')
        else
        begin
          e := FChart.List.Element(k);
          if (e.Shape.Kind <> cskPolygon) or (Length(e.Shape.Points) <> 4) then
            Miss(Format('the scatter symbol is kind %d, not a turned rect', [Ord(e.Shape.Kind)]))
          else
          begin
            ang := ArcTan2(e.Shape.Points[1].Y - e.Shape.Points[0].Y,
              e.Shape.Points[1].X - e.Shape.Points[0].X);
            { a side's angle, whichever side comes first: 30 degrees off the
              axes either way }
            ang := Abs(ang);
            while ang > Pi / 2 do ang := ang - Pi / 2;
            Inc(FCompared);
            if (Abs(ang - Pi / 6) > 1e-9) and (Abs(ang - Pi / 3) > 1e-9) then
              Miss('the scatter symbol turned ' + FloatToStr(ang));
          end;
        end;
        { the line's own emptyCircle stands }
        k := ElementOf(FChart.List, 1, 0, [cskPolygon, cskRect, cskCircle, cskEllipse, cskPath]);
        Inc(FCompared);
        if (k < 0) or not (FChart.List.Element(k).Shape.Kind in [cskCircle, cskEllipse]) then
          Miss('the line''s symbol is not its own circle');
      end;
    end;
  finally
    log.Free;
    arr.Free;
  end;
  Verdict(120);
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
