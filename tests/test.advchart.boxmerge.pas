unit test.advchart.boxmerge;
{$mode objfpc}{$H+}
{ Where a title and a legend go -- held to upstream to the bit.

  tools/advchart-oracle/box-merge.js runs ECharts 6.1 at 400 x 300 and records,
  for 21 titles, 15 legends and a scroll legend: the box option as the
  model holds it after mergeLayoutParam's ignoreSize rule (each key absent,
  null, 'auto' or a value), each parsed against its base, the two keyword
  words, and what getLayoutRect then gave -- the title's group, alignment
  and background; the legend's wrap room (maxSize), its placed rect and how
  many columns and rows its items made. 24 titles, 16 legends, one scroll. Every text is measured by the
  fixture's own widths, so nothing here depends on a font.

  THE RULES IT HOLDS THE PORT TO: an option's own left (top) with a value --
  not null, not 'auto' -- nulls the default's right (bottom), and its own
  right (bottom) nulls the default left (top); a value is parsed exactly as
  written (`centre`, ' center', '10px', true); the keyword switch reads
  `left || right` of the merged box; the wrap room is solved from the
  option's own box, keywords and all; and getLayoutRect's arithmetic goes
  in upstream's order, down to a negative width flipped. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Layout, tyControls.AdvChart.Title,
     tyControls.AdvChart.Legend;
type
  { Every text answered from the fixture's own measurements; an unknown
    one fails the case rather than guessing. }
  TTableMeasurer = class(TInterfacedObject, ITyTextMeasurer)
  public
    Names: TStringList;
    W, H: array of Double;
    Missed: string;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string; AW, AH: Double);
    procedure MeasureLine(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
    function WrapToWidth(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
  end;

  TAdvChartBoxMergeOracleTest = class(TTestCase)
  private
    FRoot: TJSONData;
    FOpt: TTyChartOption;
    FBad, FCompared: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure CheckMerged(ACase: TJSONObject; const ABox: TTyRawBox;
      const AWordH, AWordV: string);
    procedure Verdict(AMinimum: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheMergedBoxIsUpstreams;
    procedure TestTheTitleLandsWhereUpstreamPutsIt;
    procedure TestTheLegendWrapLimitIsUpstreams;
    procedure TestTheLegendIsPlacedWhereUpstreamPutsIt;
    procedure TestTheWrapLimitReachesTheItems;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-box-merge.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Result := 0;
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  Result := FloatToStr(A);
end;

{ ---- the measurer ---- }

constructor TTableMeasurer.Create;
begin
  inherited Create;
  Names := TStringList.Create;
end;

destructor TTableMeasurer.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

procedure TTableMeasurer.Add(const AText: string; AW, AH: Double);
var k: Integer;
begin
  if Names.IndexOf(AText) >= 0 then Exit;
  k := Names.Add(AText);
  SetLength(W, k + 1);
  SetLength(H, k + 1);
  W[k] := AW;
  H[k] := AH;
end;

procedure TTableMeasurer.MeasureLine(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; out AW, AH: Double);
var k: Integer;
begin
  k := Names.IndexOf(AText);
  if k < 0 then
  begin
    Missed := Missed + ' "' + AText + '"';
    AW := 0;
    AH := 0;
    Exit;
  end;
  AW := W[k];
  AH := H[k];
end;

function TTableMeasurer.WrapToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AMaxWidth: Double): string;
begin
  Result := AText;
end;

{ ---- the test ---- }

procedure TAdvChartBoxMergeOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FOpt := TTyChartOption.Create;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartBoxMergeOracleTest.TearDown;
begin
  FreeAndNil(FOpt);
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartBoxMergeOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 30 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

{ To the bit; not-a-number as itself. }
procedure TAdvChartBoxMergeOracleTest.Same(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  want := HexNum(AWant);
  if IsNan(want) and IsNan(AGot) then Exit;
  if IsNan(want) or IsNan(AGot) or (Bits(AGot) <> Bits(want)) then
    Miss(Format('%s %s, upstream %s', [AWhat, Fmt(AGot), Fmt(want)]));
end;

procedure TAdvChartBoxMergeOracleTest.Verdict(AMinimum: Integer);
begin
  AssertTrue(Format('enough was compared (%d)', [FCompared]), FCompared >= AMinimum);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' differ from upstream:' + FReport, 0, FBad);
end;

function RawOf(const ABox: TTyRawBox; const AKey: string): TTyBoxRaw;
begin
  if AKey = 'left' then Result := ABox.Left
  else if AKey = 'right' then Result := ABox.Right
  else if AKey = 'top' then Result := ABox.Top
  else if AKey = 'bottom' then Result := ABox.Bottom
  else if AKey = 'width' then Result := ABox.Width
  else Result := ABox.Height;
end;

procedure TAdvChartBoxMergeOracleTest.CheckMerged(ACase: TJSONObject;
  const ABox: TTyRawBox; const AWordH, AWordV: string);
const
  cKeys: array[0..5] of string = ('left', 'right', 'top', 'bottom', 'width', 'height');
var
  k: Integer;
  m: TJSONObject;
  r: TTyBoxRaw;
  kind, typ: string;
  base: Double;
begin
  for k := 0 to 5 do
  begin
    m := ACase.Objects['merged'].Objects[cKeys[k]];
    r := RawOf(ABox, cKeys[k]);
    kind := m.Strings['kind'];
    Inc(FCompared);
    if kind = 'absent' then
    begin
      if r.Kind <> brAbsent then Miss(cKeys[k] + ' should be absent');
    end
    else if kind = 'null' then
    begin
      if r.Kind <> brNull then Miss(cKeys[k] + ' should be null');
    end
    else if kind = 'auto' then
    begin
      if not ((r.Kind = brString) and (r.Str = 'auto')) then
        Miss(cKeys[k] + ' should be ''auto''');
    end
    else
    begin
      typ := m.Strings['type'];
      if typ = 'number' then
      begin
        if r.Kind <> brNumber then Miss(cKeys[k] + ' should be a number')
        else Same(cKeys[k], r.Num, m.Find('value'));
      end
      else if typ = 'string' then
      begin
        if (r.Kind <> brString) or (r.Str <> m.Strings['value']) then
          Miss(Format('%s should be ''%s''', [cKeys[k], m.Strings['value']]));
      end
      else if typ = 'boolean' then
      begin
        if (r.Kind <> brBool) or ((r.Num <> 0) <> m.Booleans['value']) then
          Miss(cKeys[k] + ' should be a boolean');
      end;
    end;
    { parsed against its base }
    if k in [0, 1, 4] then base := TJSONObject(FRoot).Floats['W']
    else base := TJSONObject(FRoot).Floats['H'];
    Same(cKeys[k] + ' parsed', TyBoxRawResolve(r, base),
      ACase.Objects['parsed'].Find(cKeys[k]));
  end;
  Inc(FCompared);
  if AWordH <> ACase.Strings['wordH'] then
    Miss(Format('word %s, upstream %s', [AWordH, ACase.Strings['wordH']]));
  Inc(FCompared);
  if AWordV <> ACase.Strings['wordV'] then
    Miss(Format('vertical word %s, upstream %s', [AWordV, ACase.Strings['wordV']]));
end;

function OptionText(const AKey: string; ACase: TJSONObject): string;
begin
  Result := '{ "' + AKey + '": ' + ACase.Objects['input'].AsJSON + ' }';
end;

procedure TAdvChartBoxMergeOracleTest.TestTheMergedBoxIsUpstreams;
var
  arr: TJSONArray;
  c: Integer;
  cs: TJSONObject;
  ts: TTyTitleSpec;
  ls: TTyLegendSpec;
  sect: string;
  s: Integer;
begin
  for s := 0 to 2 do
  begin
    case s of
      0: sect := 'titles';
      1: sect := 'legends';
    else
      sect := 'scroll';
    end;
    arr := TJSONObject(FRoot).Arrays[sect];
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      FName := cs.Strings['name'];
      if s = 0 then
      begin
        AssertTrue(FName + ' parses', FOpt.SetOptionText(OptionText('title', cs)));
        ts := TyTitleSpecOf(FOpt, 0);
        CheckMerged(cs, ts.Box, ts.WordH, ts.WordV);
      end
      else
      begin
        AssertTrue(FName + ' parses', FOpt.SetOptionText(OptionText('legend', cs)));
        ls := TyLegendSpecOf(FOpt, 0);
        CheckMerged(cs, ls.Box, TyBoxWord(ls.Box.Left, ls.Box.Right),
          TyBoxWord(ls.Box.Top, ls.Box.Bottom));
      end;
    end;
  end;
  Verdict(41 * 14);
end;

function AlignName(A: TTyTitleAlign): string;
begin
  case A of
    ttaCentre: Result := 'center';
    ttaRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function VAlignName(A: TTyTitleVAlign): string;
begin
  case A of
    ttvMiddle: Result := 'middle';
    ttvBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

procedure TAdvChartBoxMergeOracleTest.TestTheTitleLandsWhereUpstreamPutsIt;
var
  arr: TJSONArray;
  c: Integer;
  cs, t: TJSONObject;
  spec: TTyTitleSpec;
  lay: TTyTitleLayout;
  meas: TTableMeasurer;
  mi: ITyTextMeasurer;
  f, sf: TTyTitleFont;
  want: string;
begin
  arr := TJSONObject(FRoot).Arrays['titles'];
  f.Name := 'x';
  f.SizeLogical := 18;
  f.Weight := 700;
  sf.Name := 'x';
  sf.SizeLogical := 12;
  sf.Weight := 400;
  for c := 0 to arr.Count - 1 do
  begin
    cs := arr.Objects[c];
    FName := cs.Strings['name'];
    meas := TTableMeasurer.Create;
    mi := meas;
    t := cs.Objects['text'];
    meas.Add(t.Strings['string'], HexNum(t.Find('width')), HexNum(t.Find('height')));
    t := cs.Objects['subtext'];
    meas.Add(t.Strings['string'], HexNum(t.Find('width')), HexNum(t.Find('height')));
    AssertTrue(FName + ' parses', FOpt.SetOptionText(OptionText('title', cs)));
    spec := TyTitleSpecOf(FOpt, 0);
    lay := TyLayoutTitle(spec, TyRectF(0, 0, TJSONObject(FRoot).Floats['W'],
      TJSONObject(FRoot).Floats['H']), mi, f, sf, 96);
    if meas.Missed <> '' then Miss('measured unknown text' + meas.Missed);
    if not lay.Valid then
    begin
      Miss('no layout');
      Continue;
    end;
    Same('x', lay.TextX, cs.Objects['group'].Find('x'));
    Same('y', lay.TextY, cs.Objects['group'].Find('y'));
    { an align upstream leaves unset or cannot read is drawn as left }
    want := 'left';
    if cs.Find('align').JSONType = jtString then want := cs.Strings['align'];
    if (want <> 'center') and (want <> 'right') then want := 'left';
    Inc(FCompared);
    if AlignName(lay.Align) <> want then
      Miss(Format('align %s, upstream %s', [AlignName(lay.Align), want]));
    want := 'top';
    if cs.Find('verticalAlign').JSONType = jtString then
      want := cs.Strings['verticalAlign'];
    if (want <> 'middle') and (want <> 'bottom') then want := 'top';
    Inc(FCompared);
    if VAlignName(lay.VAlign) <> want then
      Miss(Format('verticalAlign %s, upstream %s', [VAlignName(lay.VAlign), want]));
    { THE BACKGROUND, where the block is aligned as a whole: upstream aligns
      each line by itself for middle and bottom, which is not ported. }
    Same('bg x', lay.FrameX, cs.Objects['bg'].Find('x'));
    Same('bg width', lay.FrameW, cs.Objects['bg'].Find('width'));
    if want = 'top' then
    begin
      Same('bg y', lay.FrameY, cs.Objects['bg'].Find('y'));
      Same('bg height', lay.FrameH, cs.Objects['bg'].Find('height'));
    end;
  end;
  Verdict(24 * 6);
end;

function LegendSpec(AOpt: TTyChartOption; ACase: TJSONObject): TTyLegendSpec;
begin
  AOpt.SetOptionText(OptionText('legend', ACase));
  Result := TyLegendSpecOf(AOpt, 0);
end;

procedure TAdvChartBoxMergeOracleTest.TestTheLegendWrapLimitIsUpstreams;
var
  arr: TJSONArray;
  c, s: Integer;
  cs: TJSONObject;
  r: TTyXYWH;
begin
  for s := 0 to 1 do
  begin
    if s = 0 then arr := TJSONObject(FRoot).Arrays['legends']
    else arr := TJSONObject(FRoot).Arrays['scroll'];
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      FName := cs.Strings['name'];
      r := TyLegendWrapRect(LegendSpec(FOpt, cs), TyRectF(0, 0,
        TJSONObject(FRoot).Floats['W'], TJSONObject(FRoot).Floats['H']), 96);
      Same('max x', r.X, cs.Objects['maxSize'].Find('x'));
      Same('max y', r.Y, cs.Objects['maxSize'].Find('y'));
      Same('max width', r.W, cs.Objects['maxSize'].Find('width'));
      Same('max height', r.H, cs.Objects['maxSize'].Find('height'));
    end;
  end;
  Verdict(17 * 4);
end;

procedure TAdvChartBoxMergeOracleTest.TestTheLegendIsPlacedWhereUpstreamPutsIt;
var
  arr: TJSONArray;
  c: Integer;
  cs: TJSONObject;
  r: TTyXYWH;
begin
  arr := TJSONObject(FRoot).Arrays['legends'];
  for c := 0 to arr.Count - 1 do
  begin
    cs := arr.Objects[c];
    FName := cs.Strings['name'];
    r := TyLegendPlaceRect(LegendSpec(FOpt, cs), TyRectF(0, 0,
      TJSONObject(FRoot).Floats['W'], TJSONObject(FRoot).Floats['H']),
      HexNum(cs.Objects['mainRect'].Find('width')),
      HexNum(cs.Objects['mainRect'].Find('height')), 96);
    Same('x', r.X, cs.Objects['layoutRect'].Find('x'));
    Same('y', r.Y, cs.Objects['layoutRect'].Find('y'));
    Same('width', r.W, cs.Objects['layoutRect'].Find('width'));
    Same('height', r.H, cs.Objects['layoutRect'].Find('height'));
  end;
  Verdict(16 * 4);
end;

{ THE WIRING: the whole legend layout, fed the fixture's text widths, makes
  as many columns and rows as upstream's items did, and aligns them the
  same way -- which only happens if the wrap room above is the one it
  wraps in. }
procedure TAdvChartBoxMergeOracleTest.TestTheWrapLimitReachesTheItems;
var
  arr, items, ms: TJSONArray;
  c, i, k: Integer;
  cs, m: TJSONObject;
  spec: TTyLegendSpec;
  entries: TTyLegendEntryArray;
  flags: TTyLegendFlags;
  src: TTyLegendSourceArray;
  meas: TTableMeasurer;
  mi: ITyTextMeasurer;
  f: TTyLegendFont;
  lay: TTyLegendLayout;
  xs, ys: TStringList;
  names: array of string;
  want: string;
begin
  arr := TJSONObject(FRoot).Arrays['legends'];
  f.Name := 'x';
  f.SizeLogical := 12;
  f.Weight := 400;
  xs := TStringList.Create;
  ys := TStringList.Create;
  try
    xs.Sorted := True;
    xs.Duplicates := dupIgnore;
    ys.Sorted := True;
    ys.Duplicates := dupIgnore;
    for c := 0 to arr.Count - 1 do
    begin
      cs := arr.Objects[c];
      FName := cs.Strings['name'];
      items := cs.Arrays['items'];
      ms := cs.Arrays['measure'];
      meas := TTableMeasurer.Create;
      mi := meas;
      for k := 0 to ms.Count - 1 do
      begin
        m := ms.Objects[k];
        meas.Add(m.Strings['string'], HexNum(m.Find('width')), HexNum(m.Find('height')));
      end;
      spec := LegendSpec(FOpt, cs);
      SetLength(names, items.Count);
      for k := 0 to items.Count - 1 do names[k] := items.Strings[k];
      entries := TyLegendEntries(FOpt, 0, names);
      flags := TyLegendSelected(FOpt, 0, entries, names, spec.SelectedMode);
      SetLength(src, Length(entries));
      for k := 0 to High(src) do
      begin
        { thirteen line series, as upstream's case draws them }
        src[k] := Default(TTyLegendSource);
        src[k].Found := True;
        src[k].SeriesType := 'line';
        src[k].DefaultIcon := 'emptyCircle';
        src[k].OwnIcon := True;
        src[k].Colour := 255;
        src[k].LineColour := 255;
        src[k].LineWidthLogical := 2;
      end;
      lay := TyLayoutLegend(spec, entries, flags, src, TyRectF(0, 0,
        TJSONObject(FRoot).Floats['W'], TJSONObject(FRoot).Floats['H']), mi, f, 96);
      if meas.Missed <> '' then Miss('measured unknown text' + meas.Missed);
      xs.Clear;
      ys.Clear;
      for i := 0 to High(lay.Items) do
        if TyRectFIsValid(lay.Items[i].IconBox) then
        begin
          xs.Add(FloatToStr(lay.Items[i].IconBox.Left));
          ys.Add(FloatToStr(lay.Items[i].IconBox.Top));
        end;
      Inc(FCompared);
      if (xs.Count <> cs.Integers['distinctX']) or (ys.Count <> cs.Integers['distinctY']) then
        Miss(Format('%d columns x %d rows, upstream %d x %d', [xs.Count, ys.Count,
          cs.Integers['distinctX'], cs.Integers['distinctY']]));
      want := cs.Strings['itemAlign'];
      Inc(FCompared);
      if ((lay.Align = tlaRight) and (want <> 'right'))
        or ((lay.Align <> tlaRight) and (want = 'right')) then
        Miss('itemAlign, upstream ' + want);
    end;
  finally
    xs.Free;
    ys.Free;
  end;
  Verdict(16 * 2);
end;

initialization
  RegisterTest(TAdvChartBoxMergeOracleTest);
end.
