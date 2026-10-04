unit test.advchart.axisfinish;
{$mode objfpc}{$H+}
{ The axis' finishing touches -- roadmap B6, batch 101 -- held to upstream.

  tools/advchart-oracle/axis-finish.js runs the real ECharts 6.1 build and
  records, render by render: the arrows at the ends of each axis line (their
  symbol, box, place and turn), each axis name cut to nameTruncate.maxWidth
  (the lines drawn, where the name stands and its turn, the grid rect the
  shrink left), every split line's and split area's colour and the index it
  took in its list -- across zooms, merges, a notMerge and a resize, where a
  band keeps the colour it had -- each category axis' auto interval with the
  raw one, whether the axis model's store held the last one, the store as the
  render left it and the labels drawn, and for pointer probes the rect an
  axis pointer's shadow fills on value, time and category axes.

  THE REPLAY is the control's own: the option as written, the actions through
  DispatchAction, merges through SetOption, a resize through the bounds, a
  render after each step, text measured with zrender's width table. Every
  number is compared to the bit.

  Hand-written beside it: the arrows, the colours and the shadow are on the
  screen and not only in the layout; a merge that brings an axis in new
  forgets what the old one kept. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Paint,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Layout,
     tyControls.AdvChart.Color, tyControls.AdvChart.Data,
     tyControls.AdvanceChart, test.advchart.gridbounds,
     test.advchart.categoryminmax;
type
  TAxisFinishProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function Pointers(AX, AY: Integer): TTyAxisHitArray;
    function Shadow(const AHit: TTyAxisHit; out AShape: TTyXYWH): Boolean;
    procedure PointerTo(AX, AY: Integer);
  end;

  TAdvChartAxisFinishOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TAxisFinishProbe;
    FRoot, FTable: TJSONData;
    FBad, FCompared, FArrows, FNames, FLines, FAreas, FHeld, FIntervals,
      FProbes: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameInt(const AWhat: string; AGot, AWant: Int64);
    function AxisOf(const ADim: string; AIndex: Integer): TTyAxis;
    procedure RenderAt(AW, AH: Integer);
    procedure ReplayGroup(const AGroup: string);
    procedure CheckRender(const ACase: TJSONObject; ARender: TJSONObject; AStep: Integer);
    procedure CheckAxis(const AGroup: string; AAxis: TJSONObject; const ATag: string);
    procedure CheckProbe(AProbe: TJSONObject);
    procedure Report;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheArrowsAsUpstreamPlacesThem;
    procedure TestTheNamesAsUpstreamCutsThem;
    procedure TestTheSplitColoursAsUpstreamCyclesThem;
    procedure TestTheSplitColoursAcrossRenders;
    procedure TestTheIntervalAsUpstreamHoldsIt;
    procedure TestTheShadowAsUpstreamFillsIt;
    procedure TestArrowsAreOnTheScreen;
    procedure TestSplitColoursAreOnTheScreen;
    procedure TestAValueAxisShadowIsOnTheScreen;
    procedure TestANewAxisForgetsTheOldOnesMemory;
    procedure TestTheHoldLastsOneStep;
  end;

implementation

uses tyControls.AdvChart.AxisPointer;

procedure TAxisFinishProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TAxisFinishProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

function TAxisFinishProbe.Pointers(AX, AY: Integer): TTyAxisHitArray;
begin
  Result := ResolveAxisPointers(AX, AY);
end;

procedure TAxisFinishProbe.PointerTo(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

function TAxisFinishProbe.Shadow(const AHit: TTyAxisHit; out AShape: TTyXYWH): Boolean;
begin
  Result := PointerShadowShape(AHit, AShape);
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-axis-finish.json';
end;

{ 16 hex digits, or a name for a value that is not finite }
function NumOf(AData: TJSONData): Double;
var
  q: QWord;
  s: string;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  s := AData.AsString;
  if s = 'NaN' then Exit(NaN);
  if s = 'Infinity' then Exit(Infinity);
  if s = '-Infinity' then Exit(NegInfinity);
  Result := 0;
  q := StrToQWord('$' + s);
  Move(q, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

function ColourOf(const AText: string): TTyChartColor;
begin
  Result := 0;
  if not TyTryParseChartColor(AText, Result) then Result := $DEADBEEF;
end;

procedure TAdvChartAxisFinishOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TAxisFinishProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
      + 'advchart-grid-bounds.json');
    FTable := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(
    TJSONObject(FTable).Objects['ratios'].Arrays['ratio'],
    TJSONObject(FTable).Objects['ratios'].Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartAxisFinishOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FTable);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartAxisFinishOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 300 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartAxisFinishOracleTest.Same(const AWhat: string;
  AGot: Double; AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := NumOf(AWant);
  if IsNan(want) or IsNan(AGot) then
  begin
    if not (IsNan(want) and IsNan(AGot)) then
      Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
  end
  else if AGot <> want then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartAxisFinishOracleTest.SameInt(const AWhat: string;
  AGot, AWant: Int64);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Miss(Format('%s is %d upstream, %d here', [AWhat, AWant, AGot]));
end;

function TAdvChartAxisFinishOracleTest.AxisOf(const ADim: string;
  AIndex: Integer): TTyAxis;
var
  g: TTyGridBuild;
  i: Integer;
begin
  Result := nil;
  if (FChart.Build = nil) or (FChart.Build.GridCount = 0) then Exit;
  g := FChart.Build.Grid(0);
  if ADim = 'x' then
  begin
    for i := 0 to g.XAxisCount - 1 do
      if g.XAxis(i).ComponentIndex = AIndex then Exit(g.XAxis(i));
  end
  else
    for i := 0 to g.YAxisCount - 1 do
      if g.YAxis(i).ComponentIndex = AIndex then Exit(g.YAxis(i));
end;

procedure TAdvChartAxisFinishOracleTest.RenderAt(AW, AH: Integer);
var bmp: TBGRABitmap;
begin
  FChart.SetBounds(0, 0, AW, AH);
  bmp := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
  finally
    bmp.Free;
  end;
end;

procedure TAdvChartAxisFinishOracleTest.CheckAxis(const AGroup: string;
  AAxis: TJSONObject; const ATag: string);
var
  ax: TTyAxis;
  spec: PTyAxisLayoutSpec;
  arr, lines: TJSONArray;
  rec, o: TJSONObject;
  i, k, ci, shownN: Integer;
  want, got: string;
  mem: PTyAxisMemory;
  marks: TTyAxisMarkArray;
  ink: TTyChartColor;
begin
  ax := AxisOf(AAxis.Strings['dim'], AAxis.Integers['index']);
  if ax = nil then
  begin
    Miss(ATag + ': no such axis here');
    Exit;
  end;
  if not AAxis.Booleans['shown'] then Exit;
  spec := FChart.Build.Grid(0).SpecFor(ax);
  if spec = nil then
  begin
    Miss(ATag + ': no layout spec');
    Exit;
  end;
  { the frame everything else stands in }
  if AAxis.Find('frame') is TJSONObject then
  begin
    o := AAxis.Objects['frame'];
    Same(ATag + ' frame x', spec^.NameFrame.PosX, o.Find('x'));
    Same(ATag + ' frame y', spec^.NameFrame.PosY, o.Find('y'));
    Same(ATag + ' frame rotation', spec^.NameFrame.Rotation, o.Find('rotation'));
  end;

  { ARROWS }
  if AAxis.Find('arrows') is TJSONArray then
  begin
    arr := AAxis.Arrays['arrows'];
    SameInt(ATag + ' arrows', Length(spec^.Arrows), arr.Count);
    if Length(spec^.Arrows) = arr.Count then
      for i := 0 to arr.Count - 1 do
      begin
        rec := arr.Objects[i];
        Inc(FArrows);
        SameInt(ATag + Format(' arrow %d end', [i]), spec^.Arrows[i].End_, rec.Integers['end']);
        Inc(FCompared);
        if spec^.Arrows[i].SymbolType <> rec.Strings['type'] then
          Miss(Format('%s arrow %d is %s upstream, %s here', [ATag, i,
            rec.Strings['type'], spec^.Arrows[i].SymbolType]));
        Same(ATag + Format(' arrow %d x', [i]), spec^.Arrows[i].X, rec.Find('x'));
        Same(ATag + Format(' arrow %d y', [i]), spec^.Arrows[i].Y, rec.Find('y'));
        Same(ATag + Format(' arrow %d rotation', [i]), spec^.Arrows[i].Rotation, rec.Find('rotation'));
        Same(ATag + Format(' arrow %d width', [i]), spec^.Arrows[i].W, rec.Objects['shape'].Find('width'));
        Same(ATag + Format(' arrow %d height', [i]), spec^.Arrows[i].H, rec.Objects['shape'].Find('height'));
        Same(ATag + Format(' arrow %d box x', [i]), -spec^.Arrows[i].W / 2, rec.Objects['shape'].Find('x'));
        Same(ATag + Format(' arrow %d box y', [i]), -spec^.Arrows[i].H / 2, rec.Objects['shape'].Find('y'));
      end;
  end;

  { THE NAME }
  if AGroup = 'truncate' then
  begin
    if (AAxis.Find('name') = nil) or (AAxis.Find('name').JSONType = jtNull) then
    begin
      Inc(FCompared);
      if spec^.NamePlacement.Shown then Miss(ATag + ': a name here, none upstream');
    end
    else
    begin
      rec := AAxis.Objects['name'];
      lines := rec.Arrays['lines'];
      want := '';
      for i := 0 to lines.Count - 1 do
      begin
        if i > 0 then want := want + #10;
        want := want + lines.Strings[i];
      end;
      Inc(FNames);
      Inc(FCompared);
      if Trim(StringReplace(want, #10, '', [rfReplaceAll])) = '' then
      begin
        { cut to nothing: no name laid out here (a known deviation: upstream
          lays out an empty box) }
        if spec^.NamePlacement.Shown and (spec^.NamePlacement.Text <> '') then
          Miss(ATag + ': a name cut to nothing upstream, "' + spec^.NamePlacement.Text + '" here');
      end
      else
      begin
        got := spec^.NamePlacement.Text;
        { a block draws its pieces: the text is what they say }
        if Length(spec^.NamePlacement.Rt) > 0 then
        begin
          got := '';
          for i := 0 to High(spec^.NamePlacement.Rt) do
            if spec^.NamePlacement.Rt[i].Kind = rpkText then
            begin
              if (got <> '') and (spec^.NamePlacement.Rt[i].Token = 0) then got := got + #10;
              got := got + spec^.NamePlacement.Rt[i].Text;
            end;
        end;
        if not spec^.NamePlacement.Shown then
          Miss(ATag + ': no name here, "' + want + '" upstream')
        else
        begin
          if got <> want then
            Miss(Format('%s name "%s" upstream, "%s" here', [ATag, want, got]));
          Same(ATag + ' name x', spec^.NamePlacement.X, rec.Find('x'));
          Same(ATag + ' name y', spec^.NamePlacement.Y, rec.Find('y'));
          Same(ATag + ' name rotation', spec^.NamePlacement.RotationRad, rec.Find('rotation'));
        end;
      end;
    end;
  end;

  { THE SPLIT LINES: the drawn ones in order, each its colour's index and
    the colour where the author wrote a list }
  if AAxis.Find('splitLines') is TJSONArray then
  begin
    arr := AAxis.Arrays['splitLines'];
    k := 0;
    for i := 0 to High(spec^.SplitLineMarks) do
    begin
      if not spec^.SplitLineMarks[i].Drawn then Continue;
      if k >= arr.Count then
      begin
        Miss(Format('%s: split line %s here, not upstream', [ATag,
          TyJsNumberToString(spec^.SplitLineMarks[i].Value)]));
        Inc(k);
        Continue;
      end;
      rec := arr.Objects[k];
      Inc(FLines);
      Inc(FCompared);
      if TyJsNumberToString(spec^.SplitLineMarks[i].Value) <> rec.Strings['value'] then
        Miss(Format('%s split line %d at %s upstream, %s here', [ATag, k,
          rec.Strings['value'], TyJsNumberToString(spec^.SplitLineMarks[i].Value)]));
      SameInt(Format('%s split line %d colour index', [ATag, k]),
        spec^.SplitLineMarks[i].ColourIndex, rec.Integers['ci']);
      if Length(spec^.SplitLineInks) > 0 then
      begin
        ci := spec^.SplitLineMarks[i].ColourIndex;
        if ci > High(spec^.SplitLineInks) then ci := 0;
        Inc(FCompared);
        if (not spec^.SplitLineInks[ci].Ok)
          or (spec^.SplitLineInks[ci].Colour <> ColourOf(rec.Strings['stroke'])) then
          Miss(Format('%s split line %d in %s upstream', [ATag, k, rec.Strings['stroke']]));
      end;
      Inc(k);
    end;
    SameInt(ATag + ' split lines', k, arr.Count);
  end;

  { THE SPLIT AREAS: band by band, its tick, its colour's index, the
    colour where written, and its edges }
  if AAxis.Find('splitAreas') is TJSONArray then
  begin
    arr := AAxis.Arrays['splitAreas'];
    marks := spec^.SplitAreaMarks;
    k := 0;
    for i := 0 to High(marks) - 1 do
    begin
      if not marks[i].Drawn then Continue;
      if k >= arr.Count then
      begin
        Miss(Format('%s: split area at %s here, not upstream', [ATag,
          TyJsNumberToString(marks[i].Value)]));
        Inc(k);
        Continue;
      end;
      rec := arr.Objects[k];
      Inc(FAreas);
      Inc(FCompared);
      if TyJsNumberToString(marks[i].Value) <> rec.Strings['value'] then
        Miss(Format('%s split area %d at %s upstream, %s here', [ATag, k,
          rec.Strings['value'], TyJsNumberToString(marks[i].Value)]));
      SameInt(Format('%s split area %d colour index', [ATag, k]),
        marks[i].ColourIndex, rec.Integers['ci']);
      if Length(spec^.SplitAreaInks) > 0 then
      begin
        ci := marks[i].ColourIndex;
        if ci > High(spec^.SplitAreaInks) then ci := 0;
        ink := ColourOf(rec.Strings['fill']);
        Inc(FCompared);
        if (not spec^.SplitAreaInks[ci].Ok) or (spec^.SplitAreaInks[ci].Colour <> ink) then
          Miss(Format('%s split area %d in %s upstream', [ATag, k, rec.Strings['fill']]));
      end;
      if ax.Horizontal then
      begin
        Same(Format('%s split area %d x', [ATag, k]), marks[i].Coord, rec.Objects['shape'].Find('x'));
        Same(Format('%s split area %d width', [ATag, k]), marks[i + 1].Coord - marks[i].Coord,
          rec.Objects['shape'].Find('width'));
      end
      else
      begin
        Same(Format('%s split area %d y', [ATag, k]), marks[i].Coord, rec.Objects['shape'].Find('y'));
        Same(Format('%s split area %d height', [ATag, k]), marks[i + 1].Coord - marks[i].Coord,
          rec.Objects['shape'].Find('height'));
      end;
      Inc(k);
    end;
    SameInt(ATag + ' split areas', k, arr.Count);
  end;

  { THE INTERVAL, and the store the render left }
  if AAxis.Find('interval') is TJSONObject then
  begin
    rec := AAxis.Objects['interval'];
    Inc(FIntervals);
    if rec.Booleans['held'] then Inc(FHeld);
    SameInt(ATag + ' interval', spec^.LabelStep - 1, rec.Integers['used']);
    mem := FChart.AxisMemory.Find(ax.MainType + IntToStr(ax.ComponentIndex), False);
    Inc(FCompared);
    if mem = nil then
      Miss(ATag + ': no memory kept')
    else if rec.Find('cache') is TJSONObject then
    begin
      o := rec.Objects['cache'];
      Inc(FCompared);
      if not mem^.HasInterval then Miss(ATag + ': no interval kept')
      else
      begin
        Same(ATag + ' kept interval', mem^.LastInterval, o.Find('last'));
        SameInt(ATag + ' kept count', mem^.LastCount, o.Integers['count']);
        Same(ATag + ' kept extent 0', mem^.Extent0, o.Find('e0'));
        Same(ATag + ' kept extent 1', mem^.Extent1, o.Find('e1'));
      end;
    end;
    { the labels drawn }
    arr := rec.Arrays['shown'];
    shownN := 0;
    want := '';
    got := '';
    for i := 0 to arr.Count - 1 do want := want + IntToStr(arr.Integers[i]) + ' ';
    for i := 0 to High(spec^.Placements) do
      if spec^.Placements[i].Shown and (i <= High(spec^.TickValues)) then
      begin
        got := got + IntToStr(Round(spec^.TickValues[i])) + ' ';
        Inc(shownN);
      end;
    Inc(FCompared);
    if want <> got then
      Miss(Format('%s labels [%s] upstream, [%s] here', [ATag, want, got]));
  end;
end;

procedure TAdvChartAxisFinishOracleTest.CheckRender(const ACase: TJSONObject;
  ARender: TJSONObject; AStep: Integer);
var
  axes: TJSONArray;
  i: Integer;
  r: TTyXYWH;
  o: TJSONObject;
begin
  { the grid rect: the names' shrink shows here }
  r := FChart.Build.Grid(0).PlotXYWH;
  o := ARender.Objects['rect'];
  Same(Format('render %d rect x', [AStep]), r.X, o.Find('x'));
  Same(Format('render %d rect y', [AStep]), r.Y, o.Find('y'));
  Same(Format('render %d rect width', [AStep]), r.W, o.Find('width'));
  Same(Format('render %d rect height', [AStep]), r.H, o.Find('height'));
  axes := ARender.Arrays['axes'];
  for i := 0 to axes.Count - 1 do
    CheckAxis(ACase.Strings['group'], axes.Objects[i], Format('render %d %s%d',
      [AStep, axes.Objects[i].Strings['dim'], axes.Objects[i].Integers['index']]));
end;

procedure TAdvChartAxisFinishOracleTest.CheckProbe(AProbe: TJSONObject);
var
  hits: TTyAxisHitArray;
  i, found: Integer;
  dim: string;
  sh: TTyXYWH;
  arr: TJSONArray;
  at: string;
begin
  Inc(FProbes);
  at := Format('at %d,%d', [AProbe.Integers['x'], AProbe.Integers['y']]);
  hits := FChart.Pointers(AProbe.Integers['x'], AProbe.Integers['y']);
  if (AProbe.Find('type') = nil) or (AProbe.Find('type').JSONType = jtNull) then
  begin
    for i := 0 to High(hits) do
      if (hits[i].Axis <> nil) and (hits[i].Spec.PointerType = aptShadow) then
        Miss(at + ': a shadow here, none upstream');
    Exit;
  end;
  dim := AProbe.Strings['axisDim'];
  found := -1;
  for i := 0 to High(hits) do
    if (not hits[i].Cross) and (hits[i].Axis <> nil) and (hits[i].Axis.Dim = dim) then
    begin
      found := i;
      Break;
    end;
  Inc(FCompared);
  if found < 0 then
  begin
    Miss(at + ': no pointer on ' + dim + ' here');
    Exit;
  end;
  Inc(FCompared);
  if AProbe.Strings['type'] <> 'rect' then
  begin
    if hits[found].Spec.PointerType = aptShadow then Miss(at + ': a shadow here, a line upstream');
    Exit;
  end;
  if not FChart.Shadow(hits[found], sh) then
  begin
    Miss(at + ': no shadow shape here');
    Exit;
  end;
  arr := AProbe.Arrays['shape'];
  Same(at + ' shadow x', sh.X, arr.Items[0]);
  Same(at + ' shadow y', sh.Y, arr.Items[1]);
  Same(at + ' shadow width', sh.W, arr.Items[2]);
  Same(at + ' shadow height', sh.H, arr.Items[3]);
end;

procedure TAdvChartAxisFinishOracleTest.ReplayGroup(const AGroup: string);
var
  cases, steps, renders, probes: TJSONArray;
  cs, st: TJSONObject;
  c, k, w, h: Integer;
  typ: string;
  ran: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  ran := 0;
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Strings['group'] <> AGroup then Continue;
    Inc(ran);
    FName := cs.Strings['id'];
    w := cs.Integers['W'];
    h := cs.Integers['H'];
    { a fresh chart, as each upstream case is: notMerge, whatever the last
      case left (the Option setter skips a text it already has) }
    FChart.SetOption(cs.Objects['option'].AsJSON, True);
    AssertEquals(FName + ' parses', '', FChart.OptionError);
    RenderAt(w, h);
    renders := cs.Arrays['renders'];
    CheckRender(cs, renders.Objects[0], 0);
    steps := cs.Arrays['steps'];
    for k := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[k];
      typ := st.Strings['type'];
      if typ = 'zoom' then
        AssertTrue(FName + ' takes the action', FChart.DispatchDataZoom(0,
          st.Objects['payload'].Floats['start'], st.Objects['payload'].Floats['end']))
      else if typ = 'merge' then
        AssertTrue(FName + ' takes the merge', FChart.MergeOption(st.Objects['option'].AsJSON))
      else if typ = 'notMerge' then
        FChart.SetOption(st.Objects['option'].AsJSON, True)
      else if typ = 'resize' then
      begin
        w := st.Integers['W'];
        h := st.Integers['H'];
      end;
      RenderAt(w, h);
      CheckRender(cs, renders.Objects[k + 1], k + 1);
    end;
    if cs.Find('pointer') is TJSONArray then
    begin
      probes := cs.Arrays['pointer'];
      for k := 0 to probes.Count - 1 do CheckProbe(probes.Objects[k]);
    end;
  end;
  AssertTrue('the group ' + AGroup + ' has cases', ran > 0);
end;

procedure TAdvChartAxisFinishOracleTest.Report;
begin
  if FBad > 0 then
    Fail(Format('%d of %d comparisons differ from upstream:%s',
      [FBad, FCompared, FReport]));
end;

procedure TAdvChartAxisFinishOracleTest.TestTheArrowsAsUpstreamPlacesThem;
begin
  FArrows := 0;
  ReplayGroup('arrow');
  Report;
  AssertTrue(Format('enough arrows compared (%d)', [FArrows]), FArrows >= 20);
end;

procedure TAdvChartAxisFinishOracleTest.TestTheNamesAsUpstreamCutsThem;
begin
  FNames := 0;
  ReplayGroup('truncate');
  Report;
  AssertTrue(Format('enough names compared (%d)', [FNames]), FNames >= 12);
end;

procedure TAdvChartAxisFinishOracleTest.TestTheSplitColoursAsUpstreamCyclesThem;
begin
  FLines := 0;
  FAreas := 0;
  ReplayGroup('colour');
  Report;
  AssertTrue(Format('enough split lines (%d) and areas (%d) compared', [FLines, FAreas]),
    (FLines >= 20) and (FAreas >= 20));
end;

procedure TAdvChartAxisFinishOracleTest.TestTheSplitColoursAcrossRenders;
begin
  FAreas := 0;
  ReplayGroup('sequence');
  Report;
  AssertTrue(Format('enough split areas compared (%d)', [FAreas]), FAreas >= 60);
end;

procedure TAdvChartAxisFinishOracleTest.TestTheIntervalAsUpstreamHoldsIt;
begin
  FHeld := 0;
  FIntervals := 0;
  ReplayGroup('interval');
  Report;
  AssertTrue(Format('the store held an interval (%d of %d)', [FHeld, FIntervals]),
    (FHeld >= 3) and (FIntervals >= 30));
end;

procedure TAdvChartAxisFinishOracleTest.TestTheShadowAsUpstreamFillsIt;
begin
  FProbes := 0;
  ReplayGroup('pointer');
  Report;
  AssertTrue(Format('enough probes (%d)', [FProbes]), FProbes >= 15);
end;

{ ---- hand-written ---- }

function CountDiff(A, B: TBGRABitmap; AX0, AY0, AX1, AY1: Integer): Integer;
var x, y: Integer; p, q: TBGRAPixel;
begin
  Result := 0;
  for y := AY0 to AY1 do
    for x := AX0 to AX1 do
    begin
      p := A.GetPixel(x, y);
      q := B.GetPixel(x, y);
      if (p.red <> q.red) or (p.green <> q.green) or (p.blue <> q.blue) then Inc(Result);
    end;
end;

function Snapshot(AChart: TAxisFinishProbe; const AOption: string; AW, AH: Integer): TBGRABitmap;
begin
  AChart.Option := AOption;
  AChart.SetBounds(0, 0, AW, AH);
  Result := TBGRABitmap.Create(AW, AH, BGRA(255, 255, 255, 255));
  AChart.Render(Result.Canvas, Rect(0, 0, AW, AH), 96);
end;

const
  cArrowBase = '{"animation":false,"xAxis":{"type":"category","data":["a","b","c"],'
    + '"axisLine":{"symbol":%s,"symbolSize":[12,20]}},"yAxis":{"type":"value"},'
    + '"series":[{"type":"bar","data":[1,2,3]}]}';

procedure TAdvChartAxisFinishOracleTest.TestArrowsAreOnTheScreen;
var a, b: TBGRABitmap; spec: PTyAxisLayoutSpec; ex, ey: Integer;
begin
  b := Snapshot(FChart, Format(cArrowBase, ['"none"']), 600, 400);
  a := nil;
  try
    a := Snapshot(FChart, Format(cArrowBase, ['["none","arrow"]']), 600, 400);
    spec := FChart.Build.Grid(0).SpecFor(FChart.Build.Grid(0).XAxis(0));
    AssertEquals('one arrow laid out', 1, Length(spec^.Arrows));
    ex := Round(spec^.Arrows[0].X);
    ey := Round(spec^.Arrows[0].Y);
    { the tip stands on the line's end and points right: ink on both sides
      of the line just behind it, and nothing where there was nothing }
    AssertTrue('the arrow is drawn behind its tip',
      CountDiff(a, b, ex - 12, ey - 7, ex, ey + 7) > 20);
    AssertEquals('and nothing past its tip', 0,
      CountDiff(a, b, ex + 3, ey - 7, ex + 10, ey + 7));
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TAdvChartAxisFinishOracleTest.TestSplitColoursAreOnTheScreen;
var a, b: TBGRABitmap; spec: PTyAxisLayoutSpec; m: TTyAxisMarkArray; p: TBGRAPixel;
  x, y, i: Integer;
begin
  a := Snapshot(FChart, '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"],'
    + '"splitArea":{"show":true,"areaStyle":{"color":["#ff0000","#0000ff","#00ff00"]}}},'
    + '"yAxis":{"type":"value","splitLine":{"show":false}},"series":[]}', 600, 400);
  try
    spec := FChart.Build.Grid(0).SpecFor(FChart.Build.Grid(0).XAxis(0));
    m := spec^.SplitAreaMarks;
    AssertTrue('four bands', Length(m) >= 5);
    y := Round((FChart.Build.Grid(0).PlotRect.Top + FChart.Build.Grid(0).PlotRect.Bottom) / 2);
    for i := 0 to 3 do
    begin
      x := Round((m[i].Coord + m[i + 1].Coord) / 2);
      p := a.GetPixel(x, y);
      case i mod 3 of
        0: AssertTrue(Format('band %d red', [i]), (p.red > 200) and (p.green < 50) and (p.blue < 50));
        1: AssertTrue(Format('band %d blue', [i]), (p.blue > 200) and (p.red < 50) and (p.green < 50));
        2: AssertTrue(Format('band %d green', [i]), (p.green > 200) and (p.red < 50) and (p.blue < 50));
      end;
    end;
  finally
    a.Free;
  end;
  { THE SKIN'S PAIR: the first band in the skin's colour, the second in
    none -- the ground shows through, as the chart without areas has it }
  b := Snapshot(FChart, '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"]},'
    + '"yAxis":{"type":"value","splitLine":{"show":false}},"series":[]}', 600, 400);
  a := Snapshot(FChart, '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"],'
    + '"splitArea":{"show":true}},'
    + '"yAxis":{"type":"value","splitLine":{"show":false}},"series":[]}', 600, 400);
  try
    spec := FChart.Build.Grid(0).SpecFor(FChart.Build.Grid(0).XAxis(0));
    m := spec^.SplitAreaMarks;
    y := Round((FChart.Build.Grid(0).PlotRect.Top + FChart.Build.Grid(0).PlotRect.Bottom) / 2);
    x := Round((m[0].Coord + m[1].Coord) / 2);
    AssertTrue('the first band in the skin''s colour', CountDiff(a, b, x - 3, y - 3, x + 3, y + 3) > 0);
    x := Round((m[1].Coord + m[2].Coord) / 2);
    AssertEquals('the second band shows the ground', 0, CountDiff(a, b, x - 3, y - 3, x + 3, y + 3));
  finally
    a.Free;
    b.Free;
  end;
  { lines: the second drawn line in the second colour }
  a := Snapshot(FChart, '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d"],'
    + '"splitLine":{"show":true,"lineStyle":{"color":["#ff0000","#0000ff"]}}},'
    + '"yAxis":{"type":"value","splitLine":{"show":false}},"series":[]}', 600, 400);
  try
    spec := FChart.Build.Grid(0).SpecFor(FChart.Build.Grid(0).XAxis(0));
    m := spec^.SplitLineMarks;
    y := Round((FChart.Build.Grid(0).PlotRect.Top + FChart.Build.Grid(0).PlotRect.Bottom) / 2);
    p := a.GetPixel(Floor(m[1].Coord), y);
    AssertTrue('the second line in the second colour', (p.blue > 150) and (p.red < 100));
    p := a.GetPixel(Floor(m[2].Coord), y);
    AssertTrue('the third line in the first again', (p.red > 150) and (p.blue < 100));
  finally
    a.Free;
  end;
end;

procedure TAdvChartAxisFinishOracleTest.TestAValueAxisShadowIsOnTheScreen;
var
  hits: TTyAxisHitArray;
  sh: TTyXYWH;
  a, b: TBGRABitmap;
  i, found: Integer;
const
  opt = '{"animation":false,"tooltip":{"trigger":"axis","axisPointer":{"type":"shadow"}},'
    + '"xAxis":{"type":"value"},"yAxis":{"type":"value","splitLine":{"show":false}},'
    + '"series":[{"type":"bar","data":[[1,3],[3,5],[4,2]]}]}';
begin
  b := Snapshot(FChart, opt, 600, 400);
  a := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    hits := FChart.Pointers(370, 200);
    found := -1;
    for i := 0 to High(hits) do
      if (hits[i].Axis <> nil) and (hits[i].Axis.Dim = 'x') then found := i;
    AssertTrue('a pointer on x', found >= 0);
    AssertTrue('with a shadow', FChart.Shadow(hits[found], sh));
    AssertEquals('the bars'' gap wide', 90, sh.W, 0);
    FChart.PointerTo(370, 200);
    FChart.Render(a.Canvas, Rect(0, 0, 600, 400), 96);
    { a band and not a hairline: the middle of it and its far edge are
      both shaded }
    AssertTrue('the band is drawn across its width',
      (CountDiff(a, b, Round(sh.X) + 5, 150, Round(sh.X) + 10, 160) > 20)
      and (CountDiff(a, b, Round(sh.X + sh.W) - 10, 150, Round(sh.X + sh.W) - 5, 160) > 20));
  finally
    a.Free;
    b.Free;
  end;
end;

procedure TAdvChartAxisFinishOracleTest.TestANewAxisForgetsTheOldOnesMemory;
const
  opt = '{"animation":false,"xAxis":{"type":"category","data":["a","b","c","d","e"],'
    + '"splitArea":{"show":true}},"yAxis":{"type":"value"},"series":[{"type":"bar","data":[1,2,3,4,5]}]}';
var a: TBGRABitmap;
begin
  a := Snapshot(FChart, opt, 600, 400);
  a.Free;
  AssertTrue('the axis keeps its colours', FChart.AxisMemory.Find('xAxis0', False) <> nil);
  { a merge that keeps the model keeps it }
  AssertTrue(FChart.MergeOption('{"yAxis":{"name":"v"}}'));
  AssertTrue('a merge keeps it', FChart.AxisMemory.Find('xAxis0', False) <> nil);
  { replaceMerge with no id: the old model goes, a new one takes the slot }
  AssertTrue(FChart.SetOption('{"xAxis":[{"type":"category","data":["p","q"]}]}',
    '{"replaceMerge":["xAxis"]}'));
  AssertTrue('a new axis in the slot starts over', FChart.AxisMemory.Find('xAxis0', False) = nil);
  a := Snapshot(FChart, opt, 600, 400);
  a.Free;
  FChart.SetOption(opt, True);
  AssertTrue('a notMerge starts over', FChart.AxisMemory.Find('xAxis0', False) = nil);
end;

procedure TAdvChartAxisFinishOracleTest.TestTheHoldLastsOneStep;
var mem: TTyAxisMemory;
begin
  mem := Default(TTyAxisMemory);
  AssertEquals('nothing kept: the raw one', 5, TyCategoryIntervalHold(@mem, 5, 50, 0, 450), 0);
  AssertEquals('one smaller: kept', 5, TyCategoryIntervalHold(@mem, 4, 51, 0, 450), 0);
  AssertEquals('and not written', 50, mem.LastCount);
  AssertEquals('again: still kept', 5, TyCategoryIntervalHold(@mem, 4, 49, 0, 450), 0);
  AssertEquals('two away in count: let go', 4, TyCategoryIntervalHold(@mem, 4, 48, 0, 450), 0);
  AssertEquals('written', 48, mem.LastCount);
  AssertEquals('bigger: never kept', 5, TyCategoryIntervalHold(@mem, 5, 47, 0, 450), 0);
  AssertEquals('one smaller elsewhere on the screen: let go', 4,
    TyCategoryIntervalHold(@mem, 4, 47, 0, 460), 0);
  AssertEquals('the other end moved: let go', 3,
    TyCategoryIntervalHold(@mem, 3, 47, 1, 460), 0);
  AssertEquals('two smaller: let go', 1, TyCategoryIntervalHold(@mem, 1, 47, 1, 460), 0);
  AssertEquals('no store: the raw one', 7, TyCategoryIntervalHold(nil, 7, 47, 1, 460), 0);
end;

initialization
  RegisterTest(TAdvChartAxisFinishOracleTest);
end.
