unit test.advchart.galleryrenderitem;
{$mode objfpc}{$H+}
{ THE GALLERY'S renderItem HANDLERS, HELD TO UPSTREAM [R2-J].

  The demo (examples/advchart) draws fifteen gallery examples whose custom
  series upstream draws with a JavaScript renderItem; the harvest names each
  function and examples/advchart/urenderitems.pas registers a Pascal
  transcription under that name. tools/advchart-oracle/gallery-renderitem.js
  runs the same gallery files through the real ECharts 6.1 build with the
  page's own functions (the harvest's sandbox, seeded the same way) and
  writes down every element of every custom series: the custom-series
  records (type, flags, z, the transform, the shape and its path data, the
  style, a text's pieces, a textContent, the item), the display order and the
  series' clip. This sets the same files on the control, with the demo's
  handlers registered, and compares them bit for bit.

  The gallery files are read from examples/advchart/gallery, as the demo
  reads them; the SVG map an option names from examples/advchart/maps.

  [R2-J2] THE GALLERY'S OTHER FUNCTIONS: the label, axis label and gauge
  formatters, symbolSize, itemStyle.color, labelLayout and a transform's
  itemNameFormatter the gallery names '<id>.<key>' and
  examples/advchart/ucallbacks.pas transcribes -- every answer each gives
  while the chart draws, held to what the page's own function answers
  upstream (tools/advchart-oracle/gallery-callbacks.js); and d3-geo's
  geoAlbersUsa, transcribed in examples/advchart/ualbersusa.pas, held to
  d3-geo 2.0.1 point by point (gallery-projection.js).

  [R2-J3] THE FUNCTIONS NOTHING CALLS WHILE A CHART DRAWS: an animation
  timing function's arguments and answers on an animated set and on the
  update after it (dataIndex, and a pictorial bar's index and count); the
  tooltip formatters, positions and valueFormatters and the axis pointer
  label formatters, by the answers they give for the same showTip -- by
  series and data index, by a geo's region name, at a point -- upstream
  and here. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Contnrs, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller, tyControls.AdvanceChart,
     tyControls.AdvChart.Anim, tyControls.AdvChart.Handlers,
     tyControls.AdvChart.GfxEl, tyControls.AdvChart.Custom,
     tyControls.AdvChart.Geo, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Dataset,
     tyControls.AdvChart.AnimOpt,
     test.advchart.customseries, urenderitems, ugenerated, ucallbacks,
     ualbersusa, umaps;
type
  TAdvChartGalleryRenderItemTest = class(TCuOracleBase)
  private
    FGallery, FMaps: string;
    FCase: string;
    { wind-barb's weather days on a machine not at UTC: the one shift every
      picture moves by (NaN until the first) }
    FZoneShift: Double;
    FZoned: Integer;
    FShifting: Boolean;
    function ZoneShifted(AEl: TTyGfxEl; AWant: TJSONObject): TJSONObject;
    function ReadText(const AFile: string): string;
    procedure RunEntry(ACase: TJSONObject);
    procedure RunIds(const AIds: array of string; AMin: Integer);
  protected
    function FixtureName: string; override;
    function NewMirror: TCuMirror; override;
    procedure CheckEl(AEl: TTyGfxEl; AWant: TJSONObject); override;
    procedure SetUp; override;
  published
    procedure TestEveryGalleryHandlerIsTranscribed;
    procedure TestTheCartesianOnesAreUpstreams;
    procedure TestTheCalendarAndPolarOnesAreUpstreams;
    procedure TestTheMatrixOnesAreUpstreams;
    procedure TestThePathsAreUpstreams;
    procedure TestTheParliamentIsUpstreams;
  end;

  { THE GALLERY'S GENERATED DATA [R2-J]: the five examples whose data the
    page computes ship without it, and examples/advchart/ugenerated.pas makes
    it. The harvest ran the page's own generator on the seeded Math.random and
    wrote, for every array it emptied, the length and an FNV-1a hash of the
    values (index.json `generated.fill`); each Pascal generator must give the
    very same values. }
  TAdvChartGalleryGeneratedTest = class(TTestCase)
  private
    FGallery: string;
    FIndex: TJSONData;
    function Entry(const AId: string): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryGeneratorGivesThePagesData;
    procedure TestTheFilledOptionHoldsTheData;
  end;

  { one gallery function's answers while a chart draws, written as the
    oracle writes them; it stands in front of the demo's handler }
  TCbLog = class
  public
    Name: string;
    Answers: TStringList;
    Fmt: TTyChartFormatter;
    Vis: TTyChartVisualHandler;
    Lay: TTyChartLabelLayoutHandler;
    { [R2-J3] a tooltip position; an animation timing, either kind }
    PosH: TTyChartPositionHandler;
    Tim: TTyAnimTimingHandler;
    Del: TTyAnimDelayHandler;
    constructor Create(const AName: string);
    destructor Destroy; override;
    function DoFmt(const AParams: TTyChartParams): string;
    function DoVis(const AParams: TTyChartCallbackParams): TJSONData;
    function DoLay(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
    function DoPos(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
    function DoDel(ADataIndex: Integer; AHasIndex: Boolean;
      const AParams: TTyAnimDelayParams): Double;
  end;

  { [R2-J2] what the demo's transcriptions answer while a gallery chart
    draws, against the page's own functions upstream }
  TAdvChartGalleryCallbackOracleTest = class(TCuOracleBase)
  private
    FGallery, FMaps: string;
    FLogs: TObjectList;
    procedure Wrap;
    procedure RunOne(ACase: TJSONObject);
    procedure RunPrefixes(const APrefixes: array of string; AMin: Integer);
    procedure ClearLogs;
    function LogOf(const AName: string): TCbLog;
    procedure LoadCase(ACase: TJSONObject; AAnimate: Boolean);
    procedure CompareAnim(const APhase: string; AWant: TJSONObject);
    procedure RunAnim(ACase: TJSONObject);
    procedure RunHover(ACase: TJSONObject);
    procedure RunHoverPrefixes(const APrefixes: array of string; AMin: Integer);
  protected
    function FixtureName: string; override;
    function NewMirror: TCuMirror; override;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryCaseIsInAGroup;
    procedure TestTheBarsAndLinesAreUpstreams;
    procedure TestTheScattersAreUpstreams;
    procedure TestTheCalendarsAndGaugesAreUpstreams;
    procedure TestTheRestAreUpstreams;
    { [R2-J3] }
    procedure TestTheAnimationTimingsAreUpstreams;
    procedure TestTheBarAndLineHoversAreUpstreams;
    procedure TestTheScatterHoversAreUpstreams;
    procedure TestTheOtherHoversAreUpstreams;
  end;

  { [R2-J2] the handlers the demo registers against the names the gallery
    uses, and d3's geoAlbersUsa }
  TAdvChartGalleryCallbackTest = class(TTestCase)
  private
    FGallery: string;
    function ReadText(const AFile: string): string;
  protected
    procedure SetUp; override;
  published
    procedure TestEveryGalleryCallbackIsTranscribed;
    procedure TestTheProjectionIsD3s;
    { [R2-J3] }
    procedure TestTheTableReadersAreThePages;
  end;

  { [R2-J] backwardCompat's text-style compatibility: a label's ec2
    `textStyle` copied up into the label, everywhere compatStyle.ts calls
    compatTextStyle -- matrix-periodic-table writes its label's size, colour
    and align that way, and drew them at 12 px, white on the series colour }
  TAdvChartCompatTextStyleTest = class(TTestCase)
  published
    procedure TestTheTextStyleKeysMoveUpIntoTheLabel;
    procedure TestEveryPlaceUpstreamLooks;
    procedure TestTheOptionIsPreprocessedWhenSet;
  end;

implementation

uses DateUtils, tyControls.AdvChart.Data;

function FindUp(const ARel: string): string;
var d: string; i: Integer;
begin
  Result := '';
  d := ExtractFilePath(ParamStr(0));
  for i := 0 to 5 do
  begin
    if DirectoryExists(d + ARel) then Exit(d + ARel + PathDelim);
    d := d + '..' + PathDelim;
  end;
end;

{ a file's bytes as they are }
function ReadFileText(const AFile: string): string;
var st: TFileStream;
begin
  Result := '';
  st := TFileStream.Create(AFile, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, st.Size);
    if st.Size > 0 then st.ReadBuffer(Result[1], st.Size);
  finally
    st.Free;
  end;
end;

procedure TAdvChartGalleryRenderItemTest.SetUp;
begin
  inherited SetUp;
  FGallery := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'gallery');
  FMaps := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'maps');
  AssertTrue('the gallery is where the test can reach it', FGallery <> '');
end;

function TAdvChartGalleryRenderItemTest.FixtureName: string;
begin
  Result := 'advchart-gallery-renderitem.json';
end;

function TAdvChartGalleryRenderItemTest.NewMirror: TCuMirror;
begin
  Result := TCuMirror.Create;
  RegisterGalleryRenderItems;
  { [R2-J2] matrix-confusion's and matrix-periodic-table's labels come from
    their formatters }
  RegisterGalleryCallbacks;
end;

{ THE WEATHER DAYS ARE LOCAL DATES. wind-barb's second custom series reads
  '2017-06-28' -- a bare date, local midnight to ECharts and to the port --
  and the oracle runs at UTC. Off UTC every weather picture and its text
  sit the same distance along the time axis from upstream's (the wind,
  written with a Z, does not move): that distance is measured on the first
  one and every other must agree with it to the bit; the record compared is
  then upstream's moved by it. At UTC nothing is moved. }
function TAdvChartGalleryRenderItemTest.ZoneShifted(AEl: TTyGfxEl;
  AWant: TJSONObject): TJSONObject;
var
  t: TJSONObject;
  tr: TJSONArray;
  wantX, shift: Double;
begin
  Result := nil;
  if FShifting or (FCase <> 'wind-barb') or (GetLocalTimeOffset = 0) then Exit;
  if Copy(AWant.Strings['key'], 1, 3) <> 's3:' then Exit;
  t := AWant.Objects['t'];
  wantX := FromHex(t.Strings['x']);
  if wantX = 0 then Exit;
  shift := AEl.X - wantX;
  if IsNan(FZoneShift) then FZoneShift := shift
  else SameStr('the zone shift of ' + AWant.Strings['key'], HexOf(shift), HexOf(FZoneShift));
  Inc(FZoned);
  Result := TJSONObject(AWant.Clone);
  Result.Objects['t'].Strings['x'] := HexOf(AEl.X);
  if Result.Find('transform') is TJSONArray then
  begin
    tr := Result.Arrays['transform'];
    tr.Strings[4] := HexOf(AEl.Transform[4]);
  end;
end;

function TAdvChartGalleryRenderItemTest.ReadText(const AFile: string): string;
var st: TFileStream;
begin
  Result := '';
  st := TFileStream.Create(AFile, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, st.Size);
    if st.Size > 0 then st.ReadBuffer(Result[1], st.Size);
  finally
    st.Free;
  end;
end;

{ an image: no shape and no path, its own style keys }
procedure TAdvChartGalleryRenderItemTest.CheckEl(AEl: TTyGfxEl; AWant: TJSONObject);
const
  cKeys: array[0..3] of string = ('x', 'y', 'width', 'height');
var
  st: TJSONObject;
  k: Integer;
  img: TJSONData;
  w: TJSONObject;
begin
  w := ZoneShifted(AEl, AWant);
  if w <> nil then
  begin
    FShifting := True;
    try
      CheckEl(AEl, w);
    finally
      FShifting := False;
      w.Free;
    end;
    Exit;
  end;
  if AWant.Get('type', '') <> 'image' then
  begin
    inherited CheckEl(AEl, AWant);
    Exit;
  end;
  st := AWant.Objects['style'];
  { the rest of the record without the style: the base compares a path's
    fill and stroke there }
  w := TJSONObject(AWant.Clone);
  try
    w.Delete('style');
    inherited CheckEl(AEl, w);
  finally
    w.Free;
  end;
  img := AEl.Style.Find('image');
  if img is TJSONString then SameStr('style.image', img.AsString, st.Get('image', ''))
  else Bad('style.image: none, upstream ' + st.Get('image', ''));
  for k := 0 to High(cKeys) do
    SameValue('style.' + cKeys[k], AEl.StyleValue(cKeys[k]), st.Find(cKeys[k]));
end;

procedure TAdvChartGalleryRenderItemTest.RunEntry(ACase: TJSONObject);
var
  files, maps: TJSONArray;
  i: Integer;
  text, opts: string;
  m: TJSONObject;
  root: TJSONObject;
begin
  FCase := ACase.Strings['id'];
  FWhere := FCase;
  FZoneShift := NaN;
  FZoned := 0;
  maps := ACase.Arrays['maps'];
  for i := 0 to maps.Count - 1 do
  begin
    m := maps.Objects[i];
    if FMaps = '' then Bad('no maps folder')
    else TyChartRegisterMap(m.Strings['name'], ReadText(FMaps + m.Strings['file']), '');
  end;
  NewChart(TJSONObject(FRoot).Integers['W'], TJSONObject(FRoot).Integers['H']);
  files := ACase.Arrays['files'];
  for i := 0 to files.Count - 1 do
  begin
    text := ReadText(FGallery + files.Objects[i].Strings['file']);
    if i = 0 then
    begin
      { the oracle's Object.assign of animation false and the option: the
        option's own animation wins }
      root := TJSONObject(GetJSON(text));
      try
        if root.IndexOfName('animation') < 0 then root.Add('animation', False);
        { upstream's own palette and ramp where the option names none: the
          chart's theme is the control's }
        if root.IndexOfName('color') < 0 then
          root.Add('color', GetJSON('["#5070dd","#b6d634","#505372","#ff994d",'
            + '"#0ca8df","#ffd10a","#fb628b","#785db0","#3fbe95"]'));
        if root.IndexOfName('gradientColor') < 0 then
          root.Add('gradientColor', GetJSON('["rgba(212,220,247,1)","#5070dd"]'));
        FChart.SetOption(root.AsJSON, True);
      finally
        root.Free;
      end;
    end
    else
    begin
      opts := '';
      if files.Objects[i].Find('opts') is TJSONObject then
        opts := files.Objects[i].Objects['opts'].AsJSON;
      if opts = '' then FChart.SetOption(text, False)
      else FChart.SetOption(text, opts);
    end;
    RenderNow;
  end;
  CheckEls(ACase.Objects['state'].Arrays['els']);
  CheckOrder(ACase.Objects['state'].Arrays['order']);
  CheckClips(ACase.Objects['state'].Arrays['clips']);
  FChart.Measurer := nil;
  FreeAndNil(FChart);
  for i := 0 to maps.Count - 1 do TyChartUnregisterMap(maps.Objects[i].Strings['name']);
end;

procedure TAdvChartGalleryRenderItemTest.RunIds(const AIds: array of string; AMin: Integer);
var
  all: TJSONArray;
  i, k, found: Integer;
begin
  all := TJSONObject(FRoot).Arrays['cases'];
  found := 0;
  for k := 0 to High(AIds) do
    for i := 0 to all.Count - 1 do
      if all.Objects[i].Strings['id'] = AIds[k] then
      begin
        RunEntry(all.Objects[i]);
        Inc(found);
      end;
  AssertEquals('every case is in the fixture', Length(AIds), found);
  Finish(AIds[0], AMin);
end;

{ every name a gallery file uses is one the demo registers, and the other
  way round }
procedure TAdvChartGalleryRenderItemTest.TestEveryGalleryHandlerIsTranscribed;
var
  idx: TJSONData;
  entries, hs: TJSONArray;
  i, k: Integer;
  used, ours: TStringList;
  h: TTyChartRenderItem;
begin
  idx := GetJSON(ReadText(FGallery + 'index.json'));
  used := TStringList.Create;
  ours := TStringList.Create;
  try
    used.Sorted := True;
    used.Duplicates := dupIgnore;
    entries := TJSONObject(idx).Arrays['entries'];
    for i := 0 to entries.Count - 1 do
    begin
      if not entries.Objects[i].Get('ok', False) then Continue;
      if not (entries.Objects[i].Find('handlers') is TJSONArray) then Continue;
      hs := entries.Objects[i].Arrays['handlers'];
      for k := 0 to hs.Count - 1 do
        { a projection's handlers are not renderItems }
        if Pos('.', hs.Strings[k]) = 0 then used.Add(hs.Strings[k]);
    end;
    GalleryRenderItemNames(ours);
    for i := 0 to used.Count - 1 do
      AssertTrue(used[i] + ' is registered', TyChartFindRenderItem('@' + used[i], h));
    for i := 0 to ours.Count - 1 do
      AssertTrue(ours[i] + ' is used by the gallery', used.IndexOf(ours[i]) >= 0);
    for i := 0 to TJSONObject(FRoot).Arrays['cases'].Count - 1 do
      AssertTrue('the fixture''s case uses a handler of the demo',
        ours.IndexOf(TJSONObject(FRoot).Arrays['cases'].Objects[i].Strings['id']) >= 0);
  finally
    used.Free;
    ours.Free;
    idx.Free;
  end;
end;

procedure TAdvChartGalleryRenderItemTest.TestTheCartesianOnesAreUpstreams;
begin
  RunIds(['custom-bar-trend', 'custom-cartesian-polygon', 'custom-error-bar',
    'custom-error-scatter', 'custom-ohlc', 'custom-profit', 'flame-graph'], 5000);
end;

procedure TAdvChartGalleryRenderItemTest.TestTheCalendarAndPolarOnesAreUpstreams;
begin
  RunIds(['custom-calendar-icon', 'custom-polar-heatmap'], 3000);
end;

procedure TAdvChartGalleryRenderItemTest.TestTheMatrixOnesAreUpstreams;
begin
  RunIds(['matrix-confusion', 'matrix-mini-bar-data-collection',
    'matrix-periodic-table'], 2000);
end;

procedure TAdvChartGalleryRenderItemTest.TestThePathsAreUpstreams;
begin
  RunIds(['wind-barb', 'geo-svg-custom-effect'], 2000);
end;

procedure TAdvChartGalleryRenderItemTest.TestTheParliamentIsUpstreams;
begin
  RunIds(['pie-parliament-transition'], 5000);
end;

{ ==================== the other functions [R2-J2] ==================== }

constructor TCbLog.Create(const AName: string);
begin
  inherited Create;
  Name := AName;
  Answers := TStringList.Create;
  Answers.Sorted := True;
  Answers.Duplicates := dupIgnore;
  Answers.CaseSensitive := True;
  Answers.UseLocale := False;
end;

destructor TCbLog.Destroy;
begin
  Answers.Free;
  inherited Destroy;
end;

function TCbLog.DoFmt(const AParams: TTyChartParams): string;
begin
  Result := Fmt(AParams);
  Answers.Add('s:' + Result);
end;

function TCbLog.DoVis(const AParams: TTyChartCallbackParams): TJSONData;
begin
  Result := Vis(AParams);
  if Result = nil then Answers.Add('u')
  else if Result.JSONType = jtNumber then Answers.Add('n:' + HexOf(Result.AsFloat))
  else if Result.JSONType = jtString then Answers.Add('s:' + Result.AsString)
  else Answers.Add('j:?');
end;

{ [R2-J3] a position as the oracle writes the page's answer: an array or an
  object of numbers (hex) and words, a word, nothing }
function PosValueJson(const AV: TTyChartPosValue): string;
begin
  case AV.Kind of
    cpvNumber: Result := '"' + HexOf(AV.Num) + '"';
    cpvText: Result := '"' + AV.Text + '"';
  else
    Result := 'null';
  end;
end;

function TCbLog.DoPos(const AArgs: TTyChartTooltipPosArgs): TTyChartTooltipPos;
var s: string;

  procedure Key(const AKey: string; const AV: TTyChartPosValue);
  begin
    if AV.Kind = cpvAbsent then Exit;
    if s <> '' then s := s + ',';
    s := s + '"' + AKey + '":' + PosValueJson(AV);
  end;

begin
  Result := PosH(AArgs);
  case Result.Kind of
    ctpPoint: Answers.Add('j:[' + PosValueJson(Result.X) + ',' + PosValueJson(Result.Y) + ']');
    ctpSide: Answers.Add('s:' + Result.Side);
    ctpBox:
      begin
        s := '';
        Key('bottom', Result.Bottom);
        Key('left', Result.Left);
        Key('right', Result.Right);
        Key('top', Result.Top);
        Answers.Add('j:{' + s + '}');
      end;
  else
    Answers.Add('u');
  end;
end;

{ [R2-J3] a timing function's call as the oracle writes it:
  'i:<index> p:<params> => <answer>' }
function TCbLog.DoDel(ADataIndex: Integer; AHasIndex: Boolean;
  const AParams: TTyAnimDelayParams): Double;
var a, p: string;
begin
  if Assigned(Del) then Result := Del(ADataIndex, AHasIndex, AParams)
  else if Assigned(Tim) then Result := Tim(ADataIndex, AHasIndex)
  else Result := NaN;
  { [R2-I7] null 'z', undefined 'u' }
  if AHasIndex then a := 'i:n:' + IntToStr(ADataIndex)
  else if AParams.IndexNull then a := 'i:z'
  else a := 'i:u';
  if not AParams.Present then p := 'u'
  else
  begin
    p := '';
    if AParams.HasCount then p := '"count":"' + HexOf(AParams.Count) + '"';
    if AParams.HasIndex then
    begin
      if p <> '' then p := p + ',';
      p := p + '"index":"' + HexOf(AParams.Index) + '"';
    end;
    p := 'j:{' + p + '}';
  end;
  Answers.Add(a + ' p:' + p + ' => n:' + HexOf(Result));
end;

{ the object the page's function answered, as the oracle writes it: its
  keys sorted, numbers hex }
function TCbLog.DoLay(const AArgs: TTyChartLabelLayoutArgs): TTyChartLabelLayout;
var
  s: string;
  i: Integer;
  keys: TStringList;
begin
  Result := Lay(AArgs);
  keys := TStringList.Create;
  try
    keys.Sorted := True;
    keys.UseLocale := False;
    keys.CaseSensitive := True;
    if Result.HasLabelLinePoints then
    begin
      s := '"labelLinePoints":[';
      for i := 0 to High(Result.LabelLinePoints) do
      begin
        if i > 0 then s := s + ',';
        s := s + '["' + HexOf(Result.LabelLinePoints[i].X) + '","'
          + HexOf(Result.LabelLinePoints[i].Y) + '"]';
      end;
      keys.Add(s + ']');
    end;
    if Result.MoveOverlap <> '' then keys.Add('"moveOverlap":"' + Result.MoveOverlap + '"');
    if Result.X.Kind = cpvNumber then keys.Add('"x":"' + HexOf(Result.X.Num) + '"');
    if Result.Y.Kind = cpvNumber then keys.Add('"y":"' + HexOf(Result.Y.Num) + '"');
    s := '';
    for i := 0 to keys.Count - 1 do
    begin
      if i > 0 then s := s + ',';
      s := s + keys[i];
    end;
    Answers.Add('j:{' + s + '}');
  finally
    keys.Free;
  end;
end;

function TAdvChartGalleryCallbackOracleTest.FixtureName: string;
begin
  Result := 'advchart-gallery-callbacks.json';
end;

function TAdvChartGalleryCallbackOracleTest.NewMirror: TCuMirror;
begin
  Result := TCuMirror.Create;
  RegisterGalleryRenderItems;
  RegisterGalleryCallbacks;
end;

procedure TAdvChartGalleryCallbackOracleTest.SetUp;
begin
  inherited SetUp;
  FGallery := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'gallery');
  FMaps := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'maps');
  GalleryDataDir := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'data');
  AssertTrue('the gallery is where the test can reach it', FGallery <> '');
  FLogs := TObjectList.Create(True);
  Wrap;
end;

procedure TAdvChartGalleryCallbackOracleTest.TearDown;
var i: Integer;
begin
  { the demo's own handlers back in place of the loggers: a timing logger
    stands in the delay registry, which a timing's registration does not
    replace }
  if FLogs <> nil then
    for i := 0 to FLogs.Count - 1 do
      if Assigned(TCbLog(FLogs[i]).Tim) or Assigned(TCbLog(FLogs[i]).Del) then
        TyChartUnregisterAnimDelay(TCbLog(FLogs[i]).Name);
  RegisterGalleryCallbacks;
  FreeAndNil(FLogs);
  inherited TearDown;
end;

{ a logger in front of every handler the demo registered }
procedure TAdvChartGalleryCallbackOracleTest.Wrap;
var
  names: TStringList;
  i: Integer;
  lg: TCbLog;
  f: TTyChartFormatter;
  v: TTyChartVisualHandler;
  l: TTyChartLabelLayoutHandler;
  ps: TTyChartPositionHandler;
  tm: TTyAnimTimingHandler;
  dl: TTyAnimDelayHandler;
begin
  names := TStringList.Create;
  try
    GalleryCallbackNames(names);
    for i := 0 to names.Count - 1 do
    begin
      lg := TCbLog.Create(names[i]);
      FLogs.Add(lg);
      if TyChartFindFormatter(names[i], f) and Assigned(f) then
      begin
        lg.Fmt := f;
        TyChartRegisterFormatter(names[i], @lg.DoFmt);
      end
      else if TyChartFindVisualHandler(names[i], v) then
      begin
        lg.Vis := v;
        TyChartRegisterVisualHandler(names[i], @lg.DoVis);
      end
      else if TyChartFindLabelLayoutHandler(names[i], l) then
      begin
        lg.Lay := l;
        TyChartRegisterLabelLayoutHandler(names[i], @lg.DoLay);
      end
      { [R2-J3] }
      else if TyChartFindPositionHandler(names[i], ps) then
      begin
        lg.PosH := ps;
        TyChartRegisterPositionHandler(names[i], @lg.DoPos);
      end
      else if TyChartFindAnimDelay(names[i], dl) then
      begin
        lg.Del := dl;
        TyChartRegisterAnimDelay(names[i], @lg.DoDel);
      end
      else if TyChartFindAnimTiming(names[i], tm) then
      begin
        lg.Tim := tm;
        TyChartRegisterAnimDelay(names[i], @lg.DoDel);
      end;
    end;
  finally
    names.Free;
  end;
end;

procedure TAdvChartGalleryCallbackOracleTest.RunOne(ACase: TJSONObject);
var
  text: string;
  root: TJSONObject;
  calls: TJSONObject;
  i, k: Integer;
  lg: TCbLog;
  want: TJSONArray;
  got, exp: string;
begin
  FWhere := ACase.Strings['id'];
  for i := 0 to FLogs.Count - 1 do TCbLog(FLogs[i]).Answers.Clear;
  text := ReadFileText(FGallery + ACase.Strings['file']);
  if FMaps <> '' then RegisterGalleryMapsFor(text, FMaps);
  NewChart(TJSONObject(FRoot).Integers['W'], TJSONObject(FRoot).Integers['H']);
  root := TJSONObject(GetJSON(text));
  try
    if root.IndexOfName('animation') < 0 then root.Add('animation', False);
    FChart.SetOption(root.AsJSON, True);
  finally
    root.Free;
  end;
  RenderNow;
  calls := ACase.Objects['calls'];
  for i := 0 to FLogs.Count - 1 do
  begin
    lg := TCbLog(FLogs[i]);
    if calls.IndexOfName(lg.Name) < 0 then
    begin
      Inc(FCompared);
      if lg.Answers.Count > 0 then
        Bad(lg.Name + ': called here (' + lg.Answers[0] + '), never upstream');
      Continue;
    end;
    want := calls.Arrays[lg.Name];
    { NOT COMPARED: line-tooltip-touch's pointer label. Its x axis pointer
      has a value and a handle; the handle keeps it shown upstream, and
      axisPointer.handle is one of the port's declared non-goals (spec §6),
      so the label it formats is never drawn here. }
    if lg.Name = 'line-tooltip-touch.formatter' then Continue;
    if Assigned(lg.Fmt) then
    begin
      { a formatter: every answer upstream gave is among the port's (a
        category axis is formatted whole here, sampled upstream) }
      for k := 0 to want.Count - 1 do
      begin
        exp := want.Strings[k];
        { THE ONE DEVIATION: bar-race-country's flags come from a CDN; the
          page run on the harvest's empty table prints 'undefined' where the
          demo leaves the flag out (ucallbacks.pas) }
        if lg.Name = 'bar-race-country.formatter#2' then
          exp := StringReplace(exp, '{flag|undefined}', '{flag|}', []);
        Inc(FCompared);
        if lg.Answers.IndexOf(exp) < 0 then
          Bad(lg.Name + ': upstream answers ' + exp + ', the port never does');
      end;
      Continue;
    end;
    exp := '';
    for k := 0 to want.Count - 1 do exp := exp + '|' + want.Strings[k];
    got := '';
    for k := 0 to lg.Answers.Count - 1 do got := got + '|' + lg.Answers[k];
    SameStr(lg.Name + ' answers', got, exp);
  end;
  for i := 0 to calls.Count - 1 do
  begin
    k := 0;
    while (k < FLogs.Count) and (TCbLog(FLogs[k]).Name <> calls.Names[i]) do Inc(k);
    if k >= FLogs.Count then Bad(calls.Names[i] + ': the demo has no such handler');
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

{ ==================== [R2-J3] animation and hover ==================== }

procedure TAdvChartGalleryCallbackOracleTest.ClearLogs;
var i: Integer;
begin
  for i := 0 to FLogs.Count - 1 do TCbLog(FLogs[i]).Answers.Clear;
end;

function TAdvChartGalleryCallbackOracleTest.LogOf(const AName: string): TCbLog;
var i: Integer;
begin
  for i := 0 to FLogs.Count - 1 do
    if TCbLog(FLogs[i]).Name = AName then Exit(TCbLog(FLogs[i]));
  Result := nil;
end;

{ the case's file on a new chart: animated as the page wrote it, or with the
  root's animation off as the oracle's hover chart is }
procedure TAdvChartGalleryCallbackOracleTest.LoadCase(ACase: TJSONObject;
  AAnimate: Boolean);
var
  text: string;
  root: TJSONObject;
begin
  FWhere := ACase.Strings['id'];
  text := ReadFileText(FGallery + ACase.Strings['file']);
  if FMaps <> '' then RegisterGalleryMapsFor(text, FMaps);
  NewChart(TJSONObject(FRoot).Integers['W'], TJSONObject(FRoot).Integers['H']);
  if AAnimate then
  begin
    FChart.AnimationMode := camAlways;
    FChart.AnimNow := 1700000000000;
    FChart.SetOption(text);
  end
  else
  begin
    root := TJSONObject(GetJSON(text));
    try
      if root.IndexOfName('animation') < 0 then root.Add('animation', False);
      FChart.SetOption(root.AsJSON, True);
    finally
      root.Free;
    end;
  end;
  RenderNow;
end;

{ every timing logger's calls against the phase's: the same set (a function
  of Math.random's answer is '?' upstream) }
procedure TAdvChartGalleryCallbackOracleTest.CompareAnim(const APhase: string;
  AWant: TJSONObject);
var
  i, k: Integer;
  lg: TCbLog;
  want: TJSONArray;
  got, exp, s: string;
  random: Boolean;
  gl: TStringList;
begin
  for i := 0 to FLogs.Count - 1 do
  begin
    lg := TCbLog(FLogs[i]);
    if not (Assigned(lg.Tim) or Assigned(lg.Del)) then Continue;
    exp := '';
    random := False;
    if AWant.IndexOfName(lg.Name) >= 0 then
    begin
      want := AWant.Arrays[lg.Name];
      for k := 0 to want.Count - 1 do
      begin
        exp := exp + '|' + want.Strings[k];
        if Copy(want.Strings[k], Length(want.Strings[k]), 1) = '?' then random := True;
      end;
    end;
    gl := TStringList.Create;
    try
      gl.Sorted := True;
      gl.Duplicates := dupIgnore;
      gl.CaseSensitive := True;
      gl.UseLocale := False;
      for k := 0 to lg.Answers.Count - 1 do
      begin
        s := lg.Answers[k];
        if random then s := Copy(s, 1, System.Pos(' => ', s) + 3) + '?';
        gl.Add(s);
      end;
      got := '';
      for k := 0 to gl.Count - 1 do got := got + '|' + gl[k];
    finally
      gl.Free;
    end;
    SameStr(lg.Name + ' ' + APhase, got, exp);
  end;
end;

procedure TAdvChartGalleryCallbackOracleTest.RunAnim(ACase: TJSONObject);
var
  anim: TJSONObject;
  text: string;
begin
  anim := ACase.Objects['anim'];
  ClearLogs;
  LoadCase(ACase, True);
  CompareAnim('enter', anim.Objects['enter']);
  { the same option again: an update }
  ClearLogs;
  text := ReadFileText(FGallery + ACase.Strings['file']);
  FChart.SetOption(text);
  RenderNow;
  CompareAnim('update', anim.Objects['update']);
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

{ A MARKER'S STYLE NAME IS NUMBERED FROM A RANDOM BASE upstream
  (TooltipMarkupStyleCreator: Math.round(Math.random() * 10)), from 0 here:
  the marker's rich token compared without its number }
function NormMarkers(const S: string): string;
const cTok = '{__EC_aUTo_';
var i, q: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if Copy(S, i, Length(cTok)) = cTok then
    begin
      Result := Result + cTok + '#';
      q := i + Length(cTok);
      while (q <= Length(S)) and (S[q] in ['0'..'9']) do Inc(q);
      i := q;
    end
    else
    begin
      Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

{ WIND-BARB'S TIMES ARE THE PAGE'S LOCAL TIME (echarts.format.formatTime of
  a Date): the oracle runs in UTC, this machine in its own zone -- an
  upstream answer that opens 'yyyy-MM-dd hh:mm' is read as UTC and written
  in local time before it is compared }
function LocalStamp(const S: string): string;
var
  dt: TDateTime;
  y, mo, d, hh, mi: Integer;
begin
  Result := S;
  if (Length(S) < 16) or (S[5] <> '-') or (S[8] <> '-') or (S[11] <> ' ')
    or (S[14] <> ':') then Exit;
  if not (TryStrToInt(Copy(S, 1, 4), y) and TryStrToInt(Copy(S, 6, 2), mo)
    and TryStrToInt(Copy(S, 9, 2), d) and TryStrToInt(Copy(S, 12, 2), hh)
    and TryStrToInt(Copy(S, 15, 2), mi)) then Exit;
  dt := UniversalTimeToLocal(EncodeDate(y, mo, d) + EncodeTime(hh, mi, 0, 0));
  Result := FormatDateTime('yyyy"-"mm"-"dd hh":"nn', dt) + Copy(S, 17, MaxInt);
end;

{ NOT COMPARED ON A HOVER, each a difference the port declares:
    line-tooltip-touch, candlestick-touch  the pointer's handle
        (axisPointer.handle keeps an axis' pointer and its tooltip up --
        spec §6 leaves the handle out): the label formatter of the one, the
        position of the other's volume grid
    scatter-nutrients-matrix  an axis' own pointer (axisPointer.show on
        axes a 'none' tooltip does not trigger): upstream's
        saveTooltipAxisInfo collects it and shows its axis tooltip; the
        port collects only a tooltip's axes (reported in spec §229d)
    scatter-weight at a pointer  a marker's hit slop (4 logical px, a
        declared port difference) puts the pointer on the male symbol the
        exact circle misses }
function HoverSkipped(const AName, AWhat: string): Boolean;
begin
  Result := (AName = 'line-tooltip-touch.formatter')
    or ((AName = 'candlestick-touch.position') and (Pos('"x"', AWhat) > 0)
      and (Pos('"y" : 290', AWhat) > 0))
    or (Pos('scatter-nutrients-matrix.', AName) = 1)
    or ((AName = 'scatter-weight.formatter') and (Pos('"x"', AWhat) > 0));
end;

{ every step's showTip, and what each hover function answered: upstream's
  answers all among the port's; a function the drawing never calls
  (tooltip's, position's) answers exactly upstream's, and nothing where
  upstream says nothing }
procedure TAdvChartGalleryCallbackOracleTest.RunHover(ACase: TJSONObject);
var
  steps, want: TJSONArray;
  step, calls, drawn: TJSONObject;
  i, j, k: Integer;
  lg: TCbLog;
  what, got, exp, s: string;
begin
  LoadCase(ACase, False);
  { [R2-I8] THE ORACLE RUNS IN NODE, where renderMode 'auto' is richText:
    params.marker is richText's token there, html's span in a browser }
  FChart.TooltipAutoRichText := True;
  FChart.TooltipNow := 0;
  steps := ACase.Arrays['hover'];
  drawn := ACase.Objects['calls'];
  for i := 0 to steps.Count - 1 do
  begin
    step := steps.Objects[i];
    what := step.Objects['action'].AsJSON;
    ClearLogs;
    FChart.DispatchAction(what);
    RenderNow;
    calls := step.Objects['calls'];
    for j := 0 to FLogs.Count - 1 do
    begin
      lg := TCbLog(FLogs[j]);
      if not (Assigned(lg.Fmt) or Assigned(lg.PosH)) then Continue;
      if HoverSkipped(lg.Name, what) then Continue;
      if calls.IndexOfName(lg.Name) >= 0 then
      begin
        want := calls.Arrays[lg.Name];
        if drawn.IndexOfName(lg.Name) >= 0 then
        begin
          { a label's or an axis label's formatter: upstream's answers among
            the port's }
          for k := 0 to want.Count - 1 do
          begin
            Inc(FCompared);
            if lg.Answers.IndexOf(want.Strings[k]) < 0 then
              Bad(lg.Name + ' on ' + what + ': upstream answers ' + want.Strings[k]
                + ', the port never does');
          end;
          Continue;
        end;
        exp := '';
        for k := 0 to want.Count - 1 do
        begin
          s := NormMarkers(want.Strings[k]);
          if Pos('wind-barb.', lg.Name) = 1 then
            s := 's:' + LocalStamp(Copy(s, 3, MaxInt));
          exp := exp + '|' + s;
        end;
        got := '';
        for k := 0 to lg.Answers.Count - 1 do got := got + '|' + NormMarkers(lg.Answers[k]);
        SameStr(lg.Name + ' on ' + what, got, exp);
      end
      else if (drawn.IndexOfName(lg.Name) < 0) and (lg.Answers.Count > 0) then
      begin
        Inc(FCompared);
        Bad(lg.Name + ' on ' + what + ': called here (' + lg.Answers[0]
          + '), never upstream');
      end
      else Inc(FCompared);
    end;
    { the tip hidden for good before the next step (hideLater's delay
      run out): a box still on its way out is painted, and its formatter
      asked, by the next step's render }
    FChart.DispatchAction('{"type":"hideTip"}');
    FChart.TooltipNow := FChart.TooltipNow + 1000;
    FChart.TooltipTick(FChart.TooltipNow);
  end;
  FChart.Measurer := nil;
  FreeAndNil(FChart);
end;

function HasPrefix(const AId: string; const APrefixes: array of string): Boolean;
var i: Integer;
begin
  for i := 0 to High(APrefixes) do
    if Copy(AId, 1, Length(APrefixes[i])) = APrefixes[i] then Exit(True);
  Result := False;
end;

const
  cBarsLines: array[0..11] of string = ('bar-', 'line-', 'candlestick-',
    'confidence-band', 'intraday-', 'mix-', 'multiple-x-axis', 'pictorialBar-',
    'boxplot-', 'area-', 'dynamic-data2', 'custom-ohlc');
  cScatters: array[0..3] of string = ('scatter-', 'bubble-gradient',
    'geo-svg-scatter-simple', 'effectScatter-');
  cCalGauge: array[0..1] of string = ('calendar-', 'gauge-');
  cRest: array[0..8] of string = ('matrix-', 'treemap-', 'sunburst-', 'radar-',
    'pie-', 'flame-graph', 'geo-svg-map', 'wind-barb', 'graph-');

procedure TAdvChartGalleryCallbackOracleTest.RunPrefixes(
  const APrefixes: array of string; AMin: Integer);
var
  all: TJSONArray;
  i: Integer;
begin
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if HasPrefix(all.Objects[i].Strings['id'], APrefixes) then
      RunOne(all.Objects[i]);
  Finish(APrefixes[0], AMin);
end;

procedure TAdvChartGalleryCallbackOracleTest.RunHoverPrefixes(
  const APrefixes: array of string; AMin: Integer);
var
  all: TJSONArray;
  i: Integer;
begin
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if HasPrefix(all.Objects[i].Strings['id'], APrefixes)
      and (all.Objects[i].Find('hover') <> nil) then
      RunHover(all.Objects[i]);
  Finish(APrefixes[0] + ' hovers', AMin);
end;

procedure TAdvChartGalleryCallbackOracleTest.TestTheAnimationTimingsAreUpstreams;
var
  all: TJSONArray;
  i, n: Integer;
begin
  all := TJSONObject(FRoot).Arrays['cases'];
  n := 0;
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Find('anim') <> nil then
    begin
      RunAnim(all.Objects[i]);
      Inc(n);
    end;
  AssertTrue('the fixture animates its timing cases', n >= 6);
  Finish('animation timings', 6);
end;

procedure TAdvChartGalleryCallbackOracleTest.TestTheBarAndLineHoversAreUpstreams;
begin
  RunHoverPrefixes(cBarsLines, 500);
end;

procedure TAdvChartGalleryCallbackOracleTest.TestTheScatterHoversAreUpstreams;
begin
  RunHoverPrefixes(cScatters, 100);
end;

procedure TAdvChartGalleryCallbackOracleTest.TestTheOtherHoversAreUpstreams;
var p: array of string;
  i: Integer;
begin
  SetLength(p, Length(cCalGauge) + Length(cRest));
  for i := 0 to High(cCalGauge) do p[i] := cCalGauge[i];
  for i := 0 to High(cRest) do p[Length(cCalGauge) + i] := cRest[i];
  RunHoverPrefixes(p, 300);
end;

procedure TAdvChartGalleryCallbackOracleTest.TestEveryCaseIsInAGroup;
var
  all: TJSONArray;
  i: Integer;
  id: string;
begin
  all := TJSONObject(FRoot).Arrays['cases'];
  AssertTrue('the fixture has its cases', all.Count > 30);
  for i := 0 to all.Count - 1 do
  begin
    id := all.Objects[i].Strings['id'];
    AssertTrue(id + ' is in a group', HasPrefix(id, cBarsLines)
      or HasPrefix(id, cScatters) or HasPrefix(id, cCalGauge) or HasPrefix(id, cRest));
  end;
end;

procedure TAdvChartGalleryCallbackOracleTest.TestTheBarsAndLinesAreUpstreams;
begin
  RunPrefixes(cBarsLines, 1000);
end;

procedure TAdvChartGalleryCallbackOracleTest.TestTheScattersAreUpstreams;
begin
  RunPrefixes(cScatters, 1000);
end;

procedure TAdvChartGalleryCallbackOracleTest.TestTheCalendarsAndGaugesAreUpstreams;
begin
  RunPrefixes(cCalGauge, 500);
end;

procedure TAdvChartGalleryCallbackOracleTest.TestTheRestAreUpstreams;
begin
  RunPrefixes(cRest, 1000);
end;

{ [R2-J3] the two functions that read a table of the page's -- lines-
  airline's routes and airports (carried as data), scatter-nutrients-
  matrix's colours (computed from the option, GalleryPrepare) -- handed the
  params the oracle handed the page's own and answering what it answered }
procedure TAdvChartGalleryCallbackTest.TestTheTableReadersAreThePages;
var
  sl: TStringList;
  root: TJSONData;
  direct, arr, row: TJSONArray;
  d: TJSONObject;
  i, j, k: Integer;
  prm: TTyChartParams;
  f: TTyChartFormatter;
  got, id: string;
  cell: TJSONData;
  n: Integer;
begin
  RegisterGalleryCallbacks;
  GalleryDataDir := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'data');
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-gallery-callbacks.json'));
    root := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  try
    direct := TJSONObject(root).Arrays['direct'];
    AssertTrue('the fixture calls them', direct.Count >= 6);
    n := 0;
    for i := 0 to direct.Count - 1 do
    begin
      d := direct.Objects[i];
      id := d.Strings['id'];
      if id = 'scatter-nutrients-matrix' then
        GalleryPrepare(id, ReadText(FGallery + id + '.json'));
      if d.Elements['params'] is TJSONArray then
      begin
        arr := d.Arrays['params'];
        SetLength(prm, arr.Count);
        for j := 0 to arr.Count - 1 do
        begin
          prm[j] := TyChartBlankParams;
          prm[j].ComponentType := 'series';
          prm[j].AxisDimension := arr.Objects[j].Strings['axisDim'];
          row := arr.Objects[j].Arrays['data'];
          prm[j].Raw.Shape := rshArray;
          SetLength(prm[j].Raw.Cells, row.Count);
          for k := 0 to row.Count - 1 do
          begin
            cell := row.Items[k];
            prm[j].Raw.Cells[k] := Default(TTyDataValue);
            case cell.JSONType of
              jtNumber:
                begin
                  prm[j].Raw.Cells[k].Kind := dvkNumber;
                  prm[j].Raw.Cells[k].Num := cell.AsFloat;
                end;
              jtString:
                begin
                  prm[j].Raw.Cells[k].Kind := dvkText;
                  prm[j].Raw.Cells[k].Text := cell.AsString;
                end;
            end;
          end;
        end;
      end
      else
      begin
        SetLength(prm, 1);
        prm[0] := TyChartBlankParams;
        prm[0].ComponentType := 'series';
        prm[0].DataIndex := d.Objects['params'].Integers['dataIndex'];
        prm[0].RawDataIndex := prm[0].DataIndex;
      end;
      AssertTrue(d.Strings['name'] + ' is registered',
        TyChartFindFormatter(d.Strings['name'], f) and Assigned(f));
      got := 's:' + f(prm);
      AssertEquals(d.Strings['name'] + ' on ' + d.Elements['params'].AsJSON,
        d.Strings['answer'], got);
      Inc(n);
    end;
    AssertTrue('both functions answered', n >= 6);
  finally
    root.Free;
  end;
end;

procedure TAdvChartGalleryCallbackTest.SetUp;
begin
  inherited SetUp;
  FGallery := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'gallery');
  AssertTrue('the gallery is where the test can reach it', FGallery <> '');
end;

function TAdvChartGalleryCallbackTest.ReadText(const AFile: string): string;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AFile);
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

{ every '<id>.<key>' name a gallery entry lists is registered by the demo or
  said not to be (with its reason); every registered name is used; the
  projection's two are registered as projections }
procedure TAdvChartGalleryCallbackTest.TestEveryGalleryCallbackIsTranscribed;
var
  idx: TJSONData;
  entries, hs: TJSONArray;
  i, k: Integer;
  used, ours, untr: TStringList;
  h: TTyGeoProjectHandler;
  nm: string;
begin
  idx := GetJSON(ReadText(FGallery + 'index.json'));
  used := TStringList.Create;
  ours := TStringList.Create;
  untr := TStringList.Create;
  try
    used.Sorted := True;
    used.Duplicates := dupIgnore;
    entries := TJSONObject(idx).Arrays['entries'];
    for i := 0 to entries.Count - 1 do
    begin
      if not entries.Objects[i].Get('ok', False) then Continue;
      AssertEquals(entries.Objects[i].Strings['id'] + ': no function is lost but '
        + 'watermark''s canvas', Ord(entries.Objects[i].Strings['id'] = 'watermark') * 3,
        entries.Objects[i].Get('callbacks', 0));
      if not (entries.Objects[i].Find('handlers') is TJSONArray) then Continue;
      hs := entries.Objects[i].Arrays['handlers'];
      for k := 0 to hs.Count - 1 do
        if Pos('.', hs.Strings[k]) > 0 then used.Add(hs.Strings[k]);
    end;
    GalleryCallbackNames(ours);
    GalleryUntranscribed(untr);
    RegisterAlbersUsa;
    for i := 0 to used.Count - 1 do
    begin
      nm := used[i];
      if (Copy(nm, Length(nm) - 7, 8) = '.project') or (Copy(nm, Length(nm) - 9, 10) = '.unproject') then
        AssertTrue(nm + ' is a registered projection', TyChartFindGeoProjection('@' + nm, h))
      else
        AssertTrue(nm + ' is transcribed or said not to be',
          (ours.IndexOf(nm) >= 0) or (untr.IndexOfName(nm) >= 0));
    end;
    for i := 0 to ours.Count - 1 do
      AssertTrue(ours[i] + ' is used by the gallery', used.IndexOf(ours[i]) >= 0);
    for i := 0 to untr.Count - 1 do
    begin
      AssertTrue(untr.Names[i] + ' is used by the gallery', used.IndexOf(untr.Names[i]) >= 0);
      AssertTrue(untr.Names[i] + ' is not also transcribed', ours.IndexOf(untr.Names[i]) < 0);
      AssertTrue(untr.Names[i] + ' says why', Length(untr.ValueFromIndex[i]) > 20);
    end;
  finally
    used.Free;
    ours.Free;
    untr.Free;
    idx.Free;
  end;
end;

{ d3-geo 2.0.1's albersUsa and its invert, point by point, to the bit }
procedure TAdvChartGalleryCallbackTest.TestTheProjectionIsD3s;
var
  root: TJSONData;
  arr, r: TJSONArray;
  i, bad, n: Integer;
  x, y: Double;
  ok: Boolean;
  first: string;
begin
  root := GetJSON(ReadText(FixturePath('advchart-gallery-projection.json')));
  try
    bad := 0;
    n := 0;
    first := '';
    arr := TJSONObject(root).Arrays['project'];
    for i := 0 to arr.Count - 1 do
    begin
      r := arr.Arrays[i];
      ok := AlbersUsa.Project(FromHex(r.Strings[0]), FromHex(r.Strings[1]), x, y);
      Inc(n);
      if r.Items[2].JSONType = jtNull then
      begin
        if ok then
        begin
          Inc(bad);
          if first = '' then first := Format('project %d: a point, upstream null', [i]);
        end;
      end
      else if not ok or (HexOf(x) <> r.Strings[2]) or (HexOf(y) <> r.Strings[3]) then
      begin
        Inc(bad);
        if first = '' then
          first := Format('project %d: %s %s, upstream %s %s', [i, HexOf(x), HexOf(y),
            r.Strings[2], r.Strings[3]]);
      end;
    end;
    arr := TJSONObject(root).Arrays['unproject'];
    for i := 0 to arr.Count - 1 do
    begin
      r := arr.Arrays[i];
      ok := AlbersUsa.Unproject(FromHex(r.Strings[0]), FromHex(r.Strings[1]), x, y);
      Inc(n);
      if not ok or (HexOf(x) <> r.Strings[2]) or (HexOf(y) <> r.Strings[3]) then
      begin
        Inc(bad);
        if first = '' then
          first := Format('unproject %d: %s %s, upstream %s %s', [i, HexOf(x), HexOf(y),
            r.Strings[2], r.Strings[3]]);
      end;
    end;
    AssertEquals(Format('%d of %d points differ; first: %s', [bad, n, first]), 0, bad);
    AssertTrue('points compared', n > 2500);
  finally
    root.Free;
  end;
end;

{ ==================== the generated data ==================== }

procedure TAdvChartGalleryGeneratedTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  { [R2-J2] custom-wind reads data/winds.json.gz }
  GalleryDataDir := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'data');
  FGallery := FindUp('examples' + PathDelim + 'advchart' + PathDelim + 'gallery');
  AssertTrue('the gallery is where the test can reach it', FGallery <> '');
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FGallery + 'index.json');
    FIndex := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartGalleryGeneratedTest.TearDown;
begin
  FreeAndNil(FIndex);
  inherited TearDown;
end;

function TAdvChartGalleryGeneratedTest.Entry(const AId: string): TJSONObject;
var
  arr: TJSONArray;
  i: Integer;
begin
  Result := nil;
  arr := TJSONObject(FIndex).Arrays['entries'];
  for i := 0 to arr.Count - 1 do
    if arr.Objects[i].Get('id', '') = AId then Exit(arr.Objects[i]);
end;

procedure TAdvChartGalleryGeneratedTest.TestEveryGeneratorGivesThePagesData;
var
  arr, fill: TJSONArray;
  i, k, n: Integer;
  e, g: TJSONObject;
  id: string;
  paths, hashes: TStringArray;
  counts: array[0..7] of Integer;
begin
  arr := TJSONObject(FIndex).Arrays['entries'];
  n := 0;
  for i := 0 to arr.Count - 1 do
  begin
    e := arr.Objects[i];
    if not (e.Find('generated') is TJSONObject) then Continue;
    Inc(n);
    id := e.Strings['id'];
    g := e.Objects['generated'];
    fill := g.Arrays['fill'];
    AssertTrue(id + ' has a generator', GalleryIsGenerated(id));
    paths := GalleryGeneratedPaths(id);
    AssertEquals(id + ': the paths the harvest emptied', fill.Count, Length(paths));
    AssertTrue(id + ' generates', GalleryGeneratedHash(id, hashes, counts));
    for k := 0 to fill.Count - 1 do
    begin
      AssertEquals(id + ': path ' + IntToStr(k), fill.Objects[k].Strings['path'], paths[k]);
      AssertEquals(id + ' ' + paths[k] + ': the length', fill.Objects[k].Integers['count'], counts[k]);
      AssertEquals(id + ' ' + paths[k] + ': the values (hash)', fill.Objects[k].Strings['hash'], hashes[k]);
    end;
  end;
  AssertEquals('the six generated examples', 6, n);
end;

{ the skeleton filled: the same option text around the arrays, which now
  hold what the generator made }
procedure TAdvChartGalleryGeneratedTest.TestTheFilledOptionHoldsTheData;
var
  sl: TStringList;
  skeleton, text: string;
  root, d: TJSONData;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FGallery + 'heatmap-large.json');
    skeleton := sl.Text;
  finally
    sl.Free;
  end;
  AssertTrue('heatmap-large fills', GalleryFillGenerated('heatmap-large', skeleton, text));
  AssertTrue('the text grew', Length(text) > Length(skeleton) + 100000);
  root := GetJSON(text);
  try
    d := TJSONObject(root).Objects['xAxis'].Arrays['data'];
    AssertEquals('xAxis.data', Entry('heatmap-large').Objects['generated']
      .Arrays['fill'].Objects[0].Integers['count'], d.Count);
    d := TJSONObject(root).Arrays['series'].Objects[0].Arrays['data'];
    AssertEquals('series.0.data', 20301, d.Count);
    AssertEquals('a row is i, j, the noise', 3, TJSONArray(d).Arrays[20300].Count);
    AssertEquals('the last row''s i', 200, TJSONArray(d).Arrays[20300].Integers[0]);
    { the rest of the option as the harvest wrote it }
    AssertEquals('visualMap.max', 1, TJSONObject(root).Objects['visualMap'].Integers['max']);
  finally
    root.Free;
  end;
  AssertFalse('an id with no generator', GalleryFillGenerated('bar-simple', skeleton, text));
  AssertEquals('and the text as it was', skeleton, text);
end;

{ ==================== the text-style compatibility ==================== }

function Compat(const AText: string): TJSONObject;
begin
  Result := TJSONObject(GetJSON(AText));
  TyCompatTextStyle(Result);
end;

procedure TAdvChartCompatTextStyleTest.TestTheTextStyleKeysMoveUpIntoTheLabel;
var
  o, lab: TJSONObject;
begin
  o := Compat('{"series": [{"type": "custom", "label": {"fontSize": 10, "show": true,'
    + ' "textStyle": {"fontSize": 14, "color": "#555", "align": "center",'
    + ' "bogus": 1, "rich": {"a": {"color": "red"}}}}}]}');
  try
    lab := o.Arrays['series'].Objects[0].Objects['label'];
    AssertEquals('fontSize over the label''s own', 14, lab.Integers['fontSize']);
    AssertEquals('a key already there keeps its place', 'fontSize', lab.Names[0]);
    AssertEquals('color', '#555', lab.Strings['color']);
    AssertEquals('align', 'center', lab.Strings['align']);
    AssertTrue('rich', lab.Find('rich') is TJSONObject);
    AssertTrue('a key that is no text style stays behind', lab.Find('bogus') = nil);
    AssertTrue('the textStyle itself stays', lab.Find('textStyle') is TJSONObject);
  finally
    o.Free;
  end;
end;

procedure TAdvChartCompatTextStyleTest.TestEveryPlaceUpstreamLooks;
var o: TJSONObject;
begin
  o := Compat('{"series": [{"type": "gauge", "detail": {"textStyle": {"fontSize": 21}},'
    + ' "emphasis": {"label": {"textStyle": {"fontSize": 22}}},'
    + ' "data": [{"value": 1, "label": {"textStyle": {"fontSize": 23}}}, 5],'
    + ' "markLine": {"label": {"textStyle": {"fontSize": 24}},'
    + ' "data": [[{"label": {"textStyle": {"fontSize": 25}}}, {}]]}},'
    + ' {"type": "graph", "nodes": [{"label": {"textStyle": {"fontSize": 26}}}],'
    + ' "links": [{"label": {"textStyle": {"fontSize": 27}}}]}],'
    + ' "xAxis": {"axisLabel": {"textStyle": {"fontSize": 31}},'
    + ' "axisPointer": {"label": {"textStyle": {"fontSize": 32}}}},'
    + ' "calendar": [{"dayLabel": {"textStyle": {"fontSize": 33}}}],'
    + ' "radar": {"name": {"textStyle": {"fontSize": 34}}},'
    + ' "tooltip": {"axisPointer": {"label": {"textStyle": {"fontSize": 35}}}}}');
  try
    with o.Arrays['series'].Objects[0] do
    begin
      AssertEquals('gauge detail', 21, Objects['detail'].Integers['fontSize']);
      AssertEquals('emphasis label', 22, Objects['emphasis'].Objects['label'].Integers['fontSize']);
      AssertEquals('a data item''s label', 23, Arrays['data'].Objects[0].Objects['label'].Integers['fontSize']);
      AssertEquals('the marker''s label', 24, Objects['markLine'].Objects['label'].Integers['fontSize']);
      AssertEquals('a marker pair''s end', 25, Objects['markLine'].Arrays['data'].Arrays[0]
        .Objects[0].Objects['label'].Integers['fontSize']);
    end;
    with o.Arrays['series'].Objects[1] do
    begin
      AssertEquals('a graph node', 26, Arrays['nodes'].Objects[0].Objects['label'].Integers['fontSize']);
      AssertEquals('a graph link', 27, Arrays['links'].Objects[0].Objects['label'].Integers['fontSize']);
    end;
    AssertEquals('axisLabel', 31, o.Objects['xAxis'].Objects['axisLabel'].Integers['fontSize']);
    AssertEquals('the axis pointer label', 32, o.Objects['xAxis'].Objects['axisPointer']
      .Objects['label'].Integers['fontSize']);
    AssertEquals('a calendar day label', 33, o.Arrays['calendar'].Objects[0]
      .Objects['dayLabel'].Integers['fontSize']);
    AssertEquals('a radar name', 34, o.Objects['radar'].Objects['name'].Integers['fontSize']);
    AssertEquals('the tooltip axis pointer label', 35, o.Objects['tooltip'].Objects['axisPointer']
      .Objects['label'].Integers['fontSize']);
  finally
    o.Free;
  end;
end;

procedure TAdvChartCompatTextStyleTest.TestTheOptionIsPreprocessedWhenSet;
var
  opt: TTyChartOption;
  s: TJSONObject;
begin
  opt := TTyChartOption.Create;
  try
    AssertTrue(opt.SetOptionText('{"series": [{"type": "bar", "label": {"textStyle": {"fontSize": 14}}}]}'));
    s := TJSONObject(opt.ComponentAt('series', 0));
    AssertEquals('set', 14, s.Objects['label'].Integers['fontSize']);
  finally
    opt.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartGalleryRenderItemTest);
  RegisterTest(TAdvChartGalleryCallbackOracleTest);
  RegisterTest(TAdvChartGalleryCallbackTest);
  RegisterTest(TAdvChartGalleryGeneratedTest);
  RegisterTest(TAdvChartCompatTextStyleTest);
end.
