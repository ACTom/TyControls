unit test.advchart.customseries;
{$mode objfpc}{$H+}
{ THE CUSTOM SERIES, HELD TO UPSTREAM [Batch 123, C14].

  tools/advchart-oracle/custom-series.js runs the real ECharts 6.1 build in
  node (server-side, zrender's width table for text) with every renderItem a
  recorder around a JavaScript function, and writes down, state by state --
  after setOption and after every merge, action or pointer step:

    the calls     every renderItem call in order: its params, every api
                  call with its arguments and answer, the element tree it
                  returned;
    the elements  every element of every custom series' view, depth first:
                  type, name, flags, z / zlevel / z2, the transform, the
                  shape and its PathProxy data, the style, a text's pieces,
                  a textContent's place, defaults and pieces, the item it
                  carries, its info;
    the order     the custom displayables in the display list;
    the clip      each series' clip rect;
    the pointer   the hovered element and item, the tooltip's rows, every
                  path's states and state style;
    the legend    its items.

  This replays it through the control with a Pascal transcription of every
  renderItem, registered under the same name, bit for bit. Text is measured
  with zrender's width table. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.ZrPath,
     tyControls.AdvanceChart.States, tyControls.AdvanceChart.Events,
     tyControls.AdvanceChart.Tooltip, tyControls.AdvanceChart.Legend,
     tyControls.AdvanceChart.Anim, tyControls.AdvanceChart.RichText,
     tyControls.AdvanceChart.Color, tyControls.AdvanceChart.JsMath,
     tyControls.AdvanceChart.Scale,
     tyControls.AdvanceChart.GfxEl, tyControls.AdvanceChart.Custom,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TCuProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Move(AX, AY: Integer);
    procedure Leave;
    function ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
  end;

  { The renderItems of custom-series.js, transcribed; each api call is
    written down as the oracle's recorder writes it. The helpers are a
    descendant's too (custom-series2's mirror) [Batch 124]. }
  TCuMirror = class
  protected
    FCur: TJSONObject;
    FApi: TJSONArray;
    { a calendar's instants as the oracle writes them: the port reads a date
      on the local wall clock, the oracle runs at UTC -- this is the local
      midnight of the range's start less its UTC midnight (0 at UTC)
      [Batch 124] }
    FShift: Double;
    procedure Log(const AFn: string; AArgs: TJSONArray; ARet: TJSONData);
    procedure Open(const AName: string; const AParams: TTyCustomParams);
    function Done(ARet: TJSONData): TJSONData;
    function Value(AApi: TTyCustomApi; ADim: Integer): Double;
    function OrdRaw(AApi: TTyCustomApi; ADim: Integer): string;
    function Coord(AApi: TTyCustomApi; AX, AY: Double): TTyDoubleArray;
    function Size(AApi: TTyCustomApi; AX, AY: Double): TTyDoubleArray;
    function Size2(AApi: TTyCustomApi; AX, AY, AIX, AIY: Double): TTyDoubleArray;
    function Style(AApi: TTyCustomApi; AExtra: TJSONObject): TJSONObject;
    function StyleEmph(AApi: TTyCustomApi): TJSONObject;
    function Visual(AApi: TTyCustomApi; const AType: string): TJSONData;
    function BarLayout(AApi: TTyCustomApi; AOpt: TJSONObject): TTyCustomBarLayout;
    function Font(AApi: TTyCustomApi; AOpt: TJSONObject): string;
    function Width(AApi: TTyCustomApi): Double;
    function Height(AApi: TTyCustomApi): Double;
    function Dpr(AApi: TTyCustomApi): Double;
    function CurSeries(AApi: TTyCustomApi): TTyIntegerArray;
    function BarOf(const AParams: TTyCustomParams; AApi: TTyCustomApi; AK: Integer): TJSONData;
  public
    Calls: TJSONArray;
    constructor Create;
    destructor Destroy; override;
    function Gantt(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function ErrorBar(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Hexagon(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Texts(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Groups(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Bar0(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Bar1(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Square(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Dot(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Span(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Hover(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
  end;

  { THE REPLAY every custom-series fixture shares: the comparisons, the
    readers, a case run [Batch 124: out of the C14 oracle test, for the
    second fixture's] }
  TCuOracleBase = class(TTestCase)
  protected
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCuProbe;
    FMirror: TCuMirror;
    FRoot: TJSONData;
    FBad, FCompared, FCalls, FEls, FSteps: Integer;
    FReport, FWhere: string;
    { the fixture's file name; the mirror, its handlers registered }
    function FixtureName: string; virtual; abstract;
    function NewMirror: TCuMirror; virtual; abstract;
    procedure Bad(const AWhat: string);
    procedure Same(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameStr(const AWhat, AGot, AWant: string);
    procedure SameBool(const AWhat: string; AGot, AWant: Boolean);
    procedure SameInt(const AWhat: string; AGot, AWant: Integer);
    procedure SameColour(const AWhat: string; AHas: Boolean; AGot: TTyChartColor;
      AWant: TJSONData);
    procedure SameRgba(const AWhat: string; AHas: Boolean; AGot: TTyChartColor;
      AWant: TJSONData);
    procedure SameValue(const AWhat: string; const AGot: TTyAnimValue; AWant: TJSONData);
    procedure SameMatrix(const AWhat: string; AHas: Boolean; const AGot: TTyMat2D;
      AWant: TJSONData);
    procedure SameJson(const AWhat: string; AGot, AWant: TJSONData);
    procedure Finish(const AWhat: string; AMin: Integer);
    function Cases(const AGroup: string): TJSONArray;
    procedure NewChart(AW, AH: Integer);
    procedure RenderNow;
    function KeyOf(AEl: TTyGfxEl): string;
    function Keyed: TStringList;
    function PathsOfItem(ASeries, ARaw: Integer): TTyIntegerArray;
    procedure CheckPieces(const AWhat: string; const APieces: TTyRtPieceArray;
      AWant: TJSONArray);
    procedure CheckTextStyle(const AWhat: string; AEl: TTyGfxEl; AWant: TJSONObject);
    procedure CheckEl(AEl: TTyGfxEl; AWant: TJSONObject); virtual;
    procedure CheckCalls(AWant: TJSONArray);
    procedure CheckEls(AWant: TJSONArray);
    procedure CheckOrder(AWant: TJSONArray);
    procedure CheckClips(AWant: TJSONArray);
    procedure CheckSt(AWant: TJSONArray);
    procedure CheckLegend(AWant: TJSONData);
    procedure CheckPointer(AState: TJSONObject);
    procedure CheckState(AState: TJSONObject; APointer: Boolean);
    procedure RunCase(ACase: TJSONObject); virtual;
    procedure RunGroup(const AGroup: string; AMin: Integer);
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  TAdvChartCustomSeriesOracleTest = class(TCuOracleBase)
  protected
    function FixtureName: string; override;
    function NewMirror: TCuMirror; override;
  published
    procedure TestTheShapesAreUpstreams;
    procedure TestTheMergesAreUpstreams;
    procedure TestTheLegendIsUpstreams;
    procedure TestTheDataZoomIsUpstreams;
    procedure TestTheEmphasisIsUpstreams;
  end;

  { What the fixture does not reach. }
  TAdvChartCustomSeriesTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TCuProbe;
    FCount: Integer;
    FRaise: Boolean;
    FInfos: TStringList;
    procedure Show(const AOption: string);
    procedure RenderNow;
    function Diag: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  public
    function Plain(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Deep(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function Unknown(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function WithInfo(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    function PathByValue(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
    procedure OnEv(Sender: TObject; const AEvent: TTyChartEvent);
  published
    procedure TestTheRegistryFindsANameEitherWay;
    procedure TestAnUnregisteredRenderItemIsNamed;
    procedure TestARaisingRenderItemIsNamedAndDrawsNothing;
    procedure TestATreeTooDeepIsRefused;
    procedure TestTheBarLayoutIsCalcBarWidthAndOffset;
    procedure TestTheElementsArePainted;
    procedure TestAnUnknownTypeStopsTheRender;
    procedure TestTheInfoRidesTheEvent;
    procedure TestAGeoCustomSaysItIsNotDrawn;
    procedure TestItPaintsWithTheAnimationOn;
    { [R2-V] a path whose path data changes is made anew }
    procedure TestAPathOfNewPathDataIsMadeAnew;
  end;

{ ---- the fixture helpers, a second fixture's too [Batch 124] ---- }
function FixturePath(const AName: string): string;
function FromHex(const AHex: string): Double;
function HexOf(A: Double): string;
function Txt(A: Double): string;
function IsNull(AData: TJSONData): Boolean;
function IsHex(AData: TJSONData): Boolean;
{ the oracle's recorded value: every number as its hex }
function Rv(A: TJSONData): TJSONData;
function RvNum(A: Double): TJSONData;
function RvNums(const A: array of Double): TJSONArray;
function Num(A: Double): TJSONFloatNumber;
function Pts(const A: array of Double): TJSONArray;

implementation

{ ==================== helpers ==================== }

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
  { the oracle's NaN, whatever bits this one carries [Batch 124] }
  if IsNan(A) then Exit('7ff8000000000000');
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
  Result := (HexOf(A) = HexOf(B)) or (IsNan(A) and IsNan(B))
    or ((A = 0) and (B = 0));
end;

function IsNull(AData: TJSONData): Boolean;
begin
  Result := (AData = nil) or (AData.JSONType = jtNull);
end;

function IsHex(AData: TJSONData): Boolean;
var s: string; i: Integer;
begin
  Result := False;
  if (AData = nil) or (AData.JSONType <> jtString) then Exit;
  s := AData.AsString;
  if Length(s) <> 16 then Exit;
  for i := 1 to 16 do
    if not (s[i] in ['0'..'9', 'a'..'f']) then Exit;
  Result := True;
end;

{ the oracle's recorded value: every number as its hex }
function Rv(A: TJSONData): TJSONData;
var i: Integer; o: TJSONObject; arr: TJSONArray;
begin
  if A = nil then Exit(TJSONNull.Create);
  case A.JSONType of
    jtNumber: Result := TJSONString.Create(HexOf(A.AsFloat));
    jtObject:
      begin
        o := TJSONObject.Create;
        for i := 0 to A.Count - 1 do o.Add(TJSONObject(A).Names[i], Rv(A.Items[i]));
        Result := o;
      end;
    jtArray:
      begin
        arr := TJSONArray.Create;
        for i := 0 to A.Count - 1 do arr.Add(Rv(A.Items[i]));
        Result := arr;
      end;
  else
    Result := A.Clone;
  end;
end;

function RvNum(A: Double): TJSONData;
begin
  Result := TJSONString.Create(HexOf(A));
end;

function RvNums(const A: array of Double): TJSONArray;
var i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(A) do Result.Add(HexOf(A[i]));
end;

function Num(A: Double): TJSONFloatNumber;
begin
  Result := TJSONFloatNumber.Create(A);
end;

function Pts(const A: array of Double): TJSONArray;
var i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(A) do Result.Add(Num(A[i]));
end;

{ PathProxy's data: each command's code, then its numbers }
function PathData(const APath: TTyZrPath): TTyDoubleArray;
const
  cCode: array[TTyZrCmd] of Integer = (1, 2, 3, 4, 5, 6, 7);
var
  i, k, n: Integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to High(APath) do
  begin
    SetLength(Result, n + 1 + TyZrArgCount(APath[i].Cmd));
    Result[n] := cCode[APath[i].Cmd];
    Inc(n);
    for k := 0 to TyZrArgCount(APath[i].Cmd) - 1 do
    begin
      Result[n] := APath[i].V[k];
      Inc(n);
    end;
  end;
end;

function AlignName(A: TTyRtAlign): string;
begin
  case A of
    rtaCenter: Result := 'center';
    rtaRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

{ ==================== the probe ==================== }

function TCuProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TCuProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TCuProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TCuProbe.Move(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TCuProbe.Leave;
begin
  MouseLeave;
end;

function TCuProbe.ContentOf(const ADatum: TTyChartDatumRef): TTyTooltipBlock;
begin
  Result := TooltipContent(ADatum, TooltipSpecFor(ADatum));
end;

{ ==================== the mirrors ==================== }

constructor TCuMirror.Create;
begin
  inherited Create;
  Calls := TJSONArray.Create;
end;

destructor TCuMirror.Destroy;
begin
  FreeAndNil(FCur);
  Calls.Free;
  inherited Destroy;
end;

procedure TCuMirror.Log(const AFn: string; AArgs: TJSONArray; ARet: TJSONData);
begin
  FApi.Add(TJSONObject.Create(['fn', AFn, 'args', AArgs, 'ret', ARet]));
end;

{ a calendar date record as getDateInfo writes it, its Date an empty object }
function CalDateRec(const ADate: TTyCustomCalDate; AShift: Double): TJSONObject;
begin
  Result := TJSONObject.Create(['y', ADate.Y, 'm', ADate.M, 'd', ADate.D,
    'day', RvNum(ADate.Day), 'time', RvNum(ADate.Time - AShift),
    'formatedDate', ADate.FormatedDate, 'date', TJSONObject.Create]);
end;

procedure TCuMirror.Open(const AName: string; const AParams: TTyCustomParams);
var
  p, cs: TJSONObject;
  csData: TJSONData;
  y, m, d: Integer;
begin
  FreeAndNil(FCur);
  { coordSys as each prepareCustom writes it [Batch 124]; none is null }
  cs := nil;
  if AParams.CoordSys.Type_ = '' then
    csData := TJSONNull.Create
  else if AParams.CoordSys.Type_ = 'polar' then
  begin
    cs := TJSONObject.Create(['type', AParams.CoordSys.Type_,
      'cx', RvNum(AParams.CoordSys.Cx), 'cy', RvNum(AParams.CoordSys.Cy),
      'r', RvNum(AParams.CoordSys.R), 'r0', RvNum(AParams.CoordSys.R0)]);
    csData := cs;
  end
  else
  begin
    cs := TJSONObject.Create(['type', AParams.CoordSys.Type_,
      'x', RvNum(AParams.CoordSys.X), 'y', RvNum(AParams.CoordSys.Y),
      'width', RvNum(AParams.CoordSys.Width), 'height', RvNum(AParams.CoordSys.Height)]);
    csData := cs;
    if AParams.CoordSys.Type_ = 'calendar' then
    begin
      { the zone's shift: the start's local midnight less its UTC one }
      y := StrToIntDef(AParams.CoordSys.RangeStart.Y, 1970);
      m := StrToIntDef(AParams.CoordSys.RangeStart.M, 1);
      d := StrToIntDef(AParams.CoordSys.RangeStart.D, 1);
      FShift := AParams.CoordSys.RangeStart.Time
        - (EncodeDate(y, m, d) - UnixDateDelta) * 86400000.0;
      cs.Add('cellWidth', RvNum(AParams.CoordSys.CellWidth));
      cs.Add('cellHeight', RvNum(AParams.CoordSys.CellHeight));
      cs.Add('rangeInfo', TJSONObject.Create([
        'start', CalDateRec(AParams.CoordSys.RangeStart, FShift),
        'end', CalDateRec(AParams.CoordSys.RangeEnd, FShift),
        'weeks', RvNum(AParams.CoordSys.Weeks),
        'dayCount', RvNum(AParams.CoordSys.DayCount)]));
    end;
  end;
  p := TJSONObject.Create(['dataIndex', AParams.DataIndex,
    'dataIndexInside', AParams.DataIndexInside,
    'dataInsideLength', AParams.DataInsideLength,
    'seriesId', StringReplace(AParams.SeriesId, #0, '~', [rfReplaceAll]),
    'seriesName', StringReplace(AParams.SeriesName, #0, '~', [rfReplaceAll]),
    'seriesIndex', AParams.SeriesIndex, 'coordSys', csData,
    'encode', AParams.Encode.Clone, 'itemPayload', AParams.ItemPayload.Clone,
    'context', Rv(AParams.Context)]);
  if AParams.ActionType = '' then p.Add('actionType', TJSONNull.Create)
  else p.Add('actionType', AParams.ActionType);
  FApi := TJSONArray.Create;
  FCur := TJSONObject.Create(['s', AParams.SeriesIndex, 'name', AName, 'params', p,
    'api', FApi]);
end;

function TCuMirror.Done(ARet: TJSONData): TJSONData;
begin
  FCur.Add('ret', Rv(ARet));
  Calls.Add(FCur);
  FCur := nil;
  Result := ARet;
end;

function TCuMirror.Value(AApi: TTyCustomApi; ADim: Integer): Double;
var t: string;
begin
  Result := AApi.Value(ADim);
  if IsNan(Result) then
  begin
    { a text the value is: the recorder writes it as text }
    t := AApi.ValueText(ADim);
    if t <> 'NaN' then
    begin
      Log('value', RvNums([ADim]), TJSONString.Create(t));
      Exit;
    end;
  end;
  Log('value', RvNums([ADim]), RvNum(Result));
end;

function TCuMirror.OrdRaw(AApi: TTyCustomApi; ADim: Integer): string;
begin
  Result := AApi.OrdinalRawValue(ADim);
  Log('ordinalRawValue', RvNums([ADim]), TJSONString.Create(Result));
end;

function TCuMirror.Coord(AApi: TTyCustomApi; AX, AY: Double): TTyDoubleArray;
var args: TJSONArray;
begin
  Result := AApi.Coord([AX, AY]);
  args := TJSONArray.Create;
  args.Add(RvNums([AX, AY]));
  Log('coord', args, RvNums(Result));
end;

function TCuMirror.Size(AApi: TTyCustomApi; AX, AY: Double): TTyDoubleArray;
var args: TJSONArray;
begin
  Result := AApi.Size([AX, AY]);
  args := TJSONArray.Create;
  args.Add(RvNums([AX, AY]));
  Log('size', args, RvNums(Result));
end;

function TCuMirror.Size2(AApi: TTyCustomApi; AX, AY, AIX, AIY: Double): TTyDoubleArray;
var args: TJSONArray;
begin
  Result := AApi.Size([AX, AY], [AIX, AIY]);
  args := TJSONArray.Create;
  args.Add(RvNums([AX, AY]));
  args.Add(RvNums([AIX, AIY]));
  Log('size', args, RvNums(Result));
end;

function TCuMirror.Style(AApi: TTyCustomApi; AExtra: TJSONObject): TJSONObject;
var args: TJSONArray;
begin
  args := TJSONArray.Create;
  if AExtra <> nil then args.Add(Rv(AExtra));
  Result := AApi.Style(AExtra);
  Log('style', args, Rv(Result));
end;

function TCuMirror.StyleEmph(AApi: TTyCustomApi): TJSONObject;
begin
  Result := AApi.StyleEmphasis;
  Log('styleEmphasis', TJSONArray.Create, Rv(Result));
end;

function TCuMirror.Visual(AApi: TTyCustomApi; const AType: string): TJSONData;
var args: TJSONArray;
begin
  Result := AApi.Visual(AType);
  args := TJSONArray.Create;
  args.Add(AType);
  Log('visual', args, Rv(Result));
end;

function TCuMirror.BarLayout(AApi: TTyCustomApi; AOpt: TJSONObject): TTyCustomBarLayout;
var
  args, ret: TJSONArray;
  i: Integer;
  r: TJSONData;
begin
  args := TJSONArray.Create;
  args.Add(Rv(AOpt));
  try
    Result := AApi.BarLayout(AOpt);
  finally
    AOpt.Free;
  end;
  if Result = nil then r := TJSONNull.Create
  else
  begin
    ret := TJSONArray.Create;
    for i := 0 to High(Result) do
      ret.Add(TJSONObject.Create(['bandWidth', RvNum(Result[i].BandWidth),
        'offset', RvNum(Result[i].Offset), 'width', RvNum(Result[i].Width),
        'offsetCenter', RvNum(Result[i].OffsetCenter)]));
    r := ret;
  end;
  Log('barLayout', args, r);
end;

function TCuMirror.Font(AApi: TTyCustomApi; AOpt: TJSONObject): string;
var args: TJSONArray;
begin
  args := TJSONArray.Create;
  args.Add(Rv(AOpt));
  try
    Result := AApi.Font(AOpt);
  finally
    AOpt.Free;
  end;
  Log('font', args, TJSONString.Create(Result));
end;

function TCuMirror.Width(AApi: TTyCustomApi): Double;
begin
  Result := AApi.GetWidth;
  Log('getWidth', TJSONArray.Create, RvNum(Result));
end;

function TCuMirror.Height(AApi: TTyCustomApi): Double;
begin
  Result := AApi.GetHeight;
  Log('getHeight', TJSONArray.Create, RvNum(Result));
end;

function TCuMirror.Dpr(AApi: TTyCustomApi): Double;
begin
  Result := AApi.GetDevicePixelRatio;
  Log('getDevicePixelRatio', TJSONArray.Create, RvNum(Result));
end;

function TCuMirror.CurSeries(AApi: TTyCustomApi): TTyIntegerArray;
var r: TJSONArray; i: Integer;
begin
  Result := AApi.CurrentSeriesIndices;
  r := TJSONArray.Create;
  for i := 0 to High(Result) do r.Add(HexOf(Result[i]));
  Log('currentSeriesIndices', TJSONArray.Create, r);
end;

{ EVERY API CALL IN ITS OWN STATEMENT, in the order JavaScript evaluates
  the original: FPC evaluates a call's arguments -- and an open array's
  elements -- in an order of its own, and the recorded sequence is part of
  what is compared. }

{ RENDER.gantt }
function TCuMirror.Gantt(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  cat, v1, v2, h: Double;
  start, stop, sz: TTyDoubleArray;
  shape: TJSONObject;
begin
  Open('gantt', AParams);
  cat := Value(AApi, 0);
  v1 := Value(AApi, 1);
  start := Coord(AApi, v1, cat);
  v2 := Value(AApi, 2);
  stop := Coord(AApi, v2, cat);
  sz := Size(AApi, 0, 1);
  h := sz[1] * 0.6;
  shape := TJSONObject.Create(['x', Num(start[0]), 'y', Num(start[1] - h / 2),
    'width', Num(stop[0] - start[0]), 'height', Num(h)]);
  Result := Done(TJSONObject.Create(['type', 'rect', 'shape', shape,
    'style', Style(AApi, nil)]));
end;

{ RENDER.errorbar }
function TCuMirror.ErrorBar(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  x, v1, v2, half: Double;
  hi, lo, sz: TTyDoubleArray;
  col: TJSONData;

  function St: TJSONObject;
  begin
    Result := TJSONObject.Create(['stroke', col.Clone, 'lineWidth', 2, 'fill', 'none']);
  end;

begin
  Open('errorbar', AParams);
  x := Value(AApi, 0);
  v2 := Value(AApi, 2);
  hi := Coord(AApi, x, v2);
  v1 := Value(AApi, 1);
  lo := Coord(AApi, x, v1);
  sz := Size(AApi, 1, 0);
  half := sz[0] * 0.1;
  col := Visual(AApi, 'color');
  try
    Result := Done(TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
      TJSONObject.Create(['type', 'line', 'shape', TJSONObject.Create(['x1', Num(hi[0] - half),
        'y1', Num(hi[1]), 'x2', Num(hi[0] + half), 'y2', Num(hi[1])]), 'style', St]),
      TJSONObject.Create(['type', 'line', 'shape', TJSONObject.Create(['x1', Num(hi[0]),
        'y1', Num(hi[1]), 'x2', Num(lo[0]), 'y2', Num(lo[1])]), 'style', St]),
      TJSONObject.Create(['type', 'line', 'shape', TJSONObject.Create(['x1', Num(lo[0] - half),
        'y1', Num(lo[1]), 'x2', Num(lo[0] + half), 'y2', Num(lo[1])]), 'style', St])])]));
  finally
    col.Free;
  end;
end;

{ RENDER.hexagon }
function TCuMirror.Hexagon(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  c, r: TTyDoubleArray;
  poly: TJSONArray;
  k: Integer;
  a, third, v0, v1, s0, s1, i0, i1, w, h, dp: Double;
  bc, fill, stroke: TJSONData;
  info, sty: TJSONObject;
begin
  Open('hexagon', AParams);
  v0 := Value(AApi, 0);
  v1 := Value(AApi, 1);
  c := Coord(AApi, v0, v1);
  s0 := Value(AApi, 2);
  s1 := Value(AApi, 2);
  i0 := Value(AApi, 0);
  i1 := Value(AApi, 1);
  r := Size2(AApi, s0, s1, i0, i1);
  poly := TJSONArray.Create;
  third := Pi;
  third := third / 3;
  for k := 0 to 5 do
  begin
    a := third * k;
    poly.Add(Pts([c[0] + r[0] / 2 * TyJsCos(a), c[1] + r[1] / 2 * TyJsSin(a)]));
  end;
  BarLayout(AApi, TJSONObject.Create(['count', 1]));
  w := Width(AApi);
  h := Height(AApi);
  dp := Dpr(AApi);
  info := TJSONObject.Create(['w', Num(w), 'h', Num(h), 'dpr', Num(dp)]);
  fill := Visual(AApi, 'color');
  { api.visual('borderColor') || '#333' }
  bc := Visual(AApi, 'borderColor');
  if (bc = nil) or (bc.JSONType <> jtString) or (bc.AsString = '') then
  begin
    bc.Free;
    stroke := TJSONString.Create('#333');
  end
  else
    stroke := bc;
  sty := TJSONObject.Create(['fill', fill, 'opacity', 0.7, 'stroke', stroke, 'lineWidth', 1]);
  Result := Done(TJSONObject.Create(['type', 'polygon',
    'shape', TJSONObject.Create(['points', poly]), 'info', info, 'style', sty]));
end;

{ RENDER.texts }
function TCuMirror.Texts(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  n, v0, v1, vText: Double;
  p: TTyDoubleArray;
  d, fill: TJSONData;
  o2, o0, f: string;
  extra, circle, text, rect: TJSONObject;
begin
  Open('texts', AParams);
  d := AParams.Context.Find('n');
  if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat <> 0) then n := d.AsFloat
  else n := 0;
  n := n + 1;
  if AParams.Context.IndexOfName('n') >= 0 then AParams.Context.Delete('n');
  AParams.Context.Add('n', n);
  v0 := Value(AApi, 0);
  v1 := Value(AApi, 1);
  p := Coord(AApi, v0, v1);
  fill := Visual(AApi, 'color');
  vText := Value(AApi, 1);
  circle := TJSONObject.Create(['type', 'circle',
    'shape', TJSONObject.Create(['cx', Num(p[0]), 'cy', Num(p[1]), 'r', 6]),
    'style', TJSONObject.Create(['fill', fill]),
    'textContent', TJSONObject.Create(['style', TJSONObject.Create([
      'text', TyJsNumberToString(vText), 'fill', '#333'])]),
    'textConfig', TJSONObject.Create(['position', 'top', 'distance', 4])]);
  o2 := OrdRaw(AApi, 2);
  o0 := OrdRaw(AApi, 0);
  f := Font(AApi, TJSONObject.Create(['fontSize', 14, 'fontWeight', 'bold']));
  text := TJSONObject.Create(['type', 'text', 'x', Num(p[0]), 'y', Num(p[1] + 12),
    'style', TJSONObject.Create(['text', o2 + '@' + o0 + '#' + TyJsNumberToString(n),
      'font', f, 'fill', '#444', 'align', 'center', 'verticalAlign', 'top'])]);
  extra := TJSONObject.Create(['text', 'L' + IntToStr(AParams.DataIndex),
    'textPosition', 'insideTop']);
  try
    rect := TJSONObject.Create(['type', 'rect',
      'shape', TJSONObject.Create(['x', Num(p[0] - 20), 'y', Num(p[1] - 50),
        'width', 40, 'height', 20]),
      'style', Style(AApi, extra)]);
  finally
    extra.Free;
  end;
  Result := Done(TJSONObject.Create(['type', 'group', 'children',
    TJSONArray.Create([circle, text, rect])]));
end;

{ RENDER.groups }
function TCuMirror.Groups(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  p: TTyDoubleArray;
  v0, v1, mode, rot: Double;
  box, ring, boxStyle: TJSONObject;
  kids: TJSONArray;
  g: TJSONObject;
begin
  Open('groups', AParams);
  v0 := Value(AApi, 0);
  v1 := Value(AApi, 1);
  p := Coord(AApi, v0, v1);
  mode := Value(AApi, 2);
  { the box strokes only in variant 0 }
  if mode = 0 then
    boxStyle := TJSONObject.Create(['fill', Visual(AApi, 'color'), 'stroke', '#333'])
  else
    boxStyle := TJSONObject.Create(['fill', Visual(AApi, 'color')]);
  box := TJSONObject.Create(['type', 'rect', 'name', 'box',
    'shape', TJSONObject.Create(['x', -12, 'y', -8, 'width', 24, 'height', 16]),
    'style', boxStyle]);
  ring := TJSONObject.Create(['type', 'ring', 'name', 'ring',
    'shape', TJSONObject.Create(['cx', 0, 'cy', 0, 'r', 10, 'r0', 5]),
    'style', TJSONObject.Create(['fill', '#91cc75'])]);
  kids := TJSONArray.Create;
  if mode = 1 then
  begin
    kids.Add(box);
    ring.Free;
  end
  else if mode = 2 then
  begin
    kids.Add(ring);
    kids.Add(box);
  end
  else
  begin
    kids.Add(box);
    kids.Add(ring);
  end;
  rot := 0;
  if mode = 2 then
  begin
    rot := Pi;
    rot := rot / 6;
  end;
  g := TJSONObject.Create(['type', 'group', 'x', Num(p[0]), 'y', Num(p[1]),
    'rotation', Num(rot), 'info', TJSONObject.Create(['row', AParams.DataIndex,
      'mode', Num(mode)]), 'children', kids]);
  if mode = 2 then g.Add('$mergeChildren', 'byName');
  Result := Done(g);
end;

function TCuMirror.BarOf(const AParams: TTyCustomParams; AApi: TTyCustomApi;
  AK: Integer): TJSONData;
var
  layout: TTyCustomBarLayout;
  base, top: TTyDoubleArray;
  b0, t0, t1: Double;
  shape: TJSONObject;
begin
  layout := BarLayout(AApi, TJSONObject.Create(['count', 2, 'barGap', '20%',
    'barCategoryGap', 10]));
  BarLayout(AApi, TJSONObject.Create(['count', 3, 'barWidth', 12, 'barMaxWidth', 10]));
  b0 := Value(AApi, 0);
  base := Coord(AApi, b0, 0);
  t0 := Value(AApi, 0);
  t1 := Value(AApi, 1);
  top := Coord(AApi, t0, t1);
  shape := TJSONObject.Create(['x', Num(base[0] + layout[AK].Offset), 'y', Num(top[1]),
    'width', Num(layout[AK].Width), 'height', Num(base[1] - top[1])]);
  Result := TJSONObject.Create(['type', 'rect', 'shape', shape,
    'style', TJSONObject.Create(['fill', Visual(AApi, 'color')])]);
end;

function TCuMirror.Bar0(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
begin
  Open('bar0', AParams);
  Result := Done(BarOf(AParams, AApi, 0));
end;

function TCuMirror.Bar1(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
begin
  Open('bar1', AParams);
  Result := Done(BarOf(AParams, AApi, 1));
end;

{ RENDER.square }
function TCuMirror.Square(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  c, s: TTyDoubleArray;
  v0, v1: Double;
  shape: TJSONObject;
begin
  Open('square', AParams);
  v0 := Value(AApi, 0);
  v1 := Value(AApi, 1);
  c := Coord(AApi, v0, v1);
  s := Size(AApi, 3, 3);
  shape := TJSONObject.Create(['x', Num(c[0] - s[0] / 2), 'y', Num(c[1] - s[1] / 2),
    'width', Num(s[0]), 'height', Num(s[1])]);
  Result := Done(TJSONObject.Create(['type', 'rect', 'shape', shape,
    'style', TJSONObject.Create(['fill', Visual(AApi, 'color')])]));
end;

{ RENDER.dot }
function TCuMirror.Dot(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  c: TTyDoubleArray;
  cur: TTyIntegerArray;
  arr: TJSONArray;
  i: Integer;
  v0, v1: Double;
  info: TJSONObject;
begin
  Open('dot', AParams);
  v0 := Value(AApi, 0);
  v1 := Value(AApi, 1);
  c := Coord(AApi, v0, v1);
  cur := CurSeries(AApi);
  arr := TJSONArray.Create;
  for i := 0 to High(cur) do arr.Add(cur[i]);
  info := TJSONObject.Create(['cur', arr]);
  Result := Done(TJSONObject.Create(['type', 'circle',
    'shape', TJSONObject.Create(['cx', Num(c[0]), 'cy', Num(c[1]), 'r', 8]),
    'info', info, 'style', TJSONObject.Create(['fill', Visual(AApi, 'color')])]));
end;

{ RENDER.span }
function TCuMirror.Span(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  cat, v1, v2, h: Double;
  start, stop, sz: TTyDoubleArray;
  info, shape: TJSONObject;
  fill: TJSONData;
begin
  Open('span', AParams);
  cat := Value(AApi, 0);
  v1 := Value(AApi, 1);
  start := Coord(AApi, v1, cat);
  v2 := Value(AApi, 2);
  stop := Coord(AApi, v2, cat);
  sz := Size(AApi, 0, 1);
  h := sz[1] * 0.5;
  shape := TJSONObject.Create(['x', Num(start[0]), 'y', Num(start[1] - h / 2),
    'width', Num(stop[0] - start[0]), 'height', Num(h)]);
  fill := Visual(AApi, 'color');
  info := TJSONObject.Create(['inside', AParams.DataIndexInside,
    'of', AParams.DataInsideLength]);
  if AParams.ActionType = '' then info.Add('act', TJSONNull.Create)
  else info.Add('act', AParams.ActionType);
  Result := Done(TJSONObject.Create(['type', 'rect', 'shape', shape,
    'style', TJSONObject.Create(['fill', fill]), 'info', info]));
end;

{ RENDER.hover }
function TCuMirror.Hover(const AParams: TTyCustomParams; AApi: TTyCustomApi): TJSONData;
var
  p, base: TTyDoubleArray;
  v0, v1, b0: Double;
  rect: TJSONObject;
begin
  Open('hover', AParams);
  v0 := Value(AApi, 0);
  v1 := Value(AApi, 1);
  p := Coord(AApi, v0, v1);
  b0 := Value(AApi, 0);
  base := Coord(AApi, b0, 0);
  StyleEmph(AApi).Free;
  rect := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', Num(p[0] - 15), 'y', Num(p[1]), 'width', 30,
      'height', Num(base[1] - p[1])]),
    'style', TJSONObject.Create(['fill', Visual(AApi, 'color')]),
    'emphasis', TJSONObject.Create(['style', TJSONObject.Create(['fill', '#ee6666',
      'stroke', '#000', 'lineWidth', 2])])]);
  Result := Done(TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([
    rect,
    TJSONObject.Create(['type', 'circle',
      'shape', TJSONObject.Create(['cx', Num(p[0]), 'cy', Num(p[1] - 12), 'r', 8]),
      'z2', 3, 'style', TJSONObject.Create(['fill', '#73c0de', 'stroke', '#5470c6',
        'lineWidth', 1])])])]));
end;

{ ==================== the oracle test ==================== }

procedure TCuOracleBase.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  AssertTrue('the fixture is where the suite expects it',
    FileExists(FixturePath(FixtureName)));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath(FixtureName));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FChart := nil;
  TyChartClearRenderItems;
  FMirror := NewMirror;
  FBad := 0;
  FCompared := 0;
  FCalls := 0;
  FEls := 0;
  FSteps := 0;
  FReport := '';
end;

function TAdvChartCustomSeriesOracleTest.FixtureName: string;
begin
  Result := 'advchart-custom-series.json';
end;

function TAdvChartCustomSeriesOracleTest.NewMirror: TCuMirror;
begin
  Result := TCuMirror.Create;
  TyChartRegisterRenderItem('gantt', @Result.Gantt);
  TyChartRegisterRenderItem('errorbar', @Result.ErrorBar);
  TyChartRegisterRenderItem('hexagon', @Result.Hexagon);
  TyChartRegisterRenderItem('texts', @Result.Texts);
  TyChartRegisterRenderItem('groups', @Result.Groups);
  TyChartRegisterRenderItem('bar0', @Result.Bar0);
  TyChartRegisterRenderItem('bar1', @Result.Bar1);
  TyChartRegisterRenderItem('square', @Result.Square);
  TyChartRegisterRenderItem('dot', @Result.Dot);
  TyChartRegisterRenderItem('span', @Result.Span);
  TyChartRegisterRenderItem('hover', @Result.Hover);
end;

procedure TCuOracleBase.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  TyChartClearRenderItems;
  FreeAndNil(FMirror);
  FreeAndNil(FRoot);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TCuOracleBase.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 16000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TCuOracleBase.Same(const AWhat: string; AGot: Double;
  AWant: TJSONData);
var want: Double;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    Bad(AWhat + ': upstream has no number');
    Exit;
  end;
  if AWant.JSONType = jtNumber then want := AWant.AsFloat
  else want := FromHex(AWant.AsString);
  if not SameBits(AGot, want) then
    Bad(Format('%s %s, upstream %s', [AWhat, Txt(AGot), Txt(want)]));
end;

procedure TCuOracleBase.SameStr(const AWhat, AGot, AWant: string);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s "%s", upstream "%s"', [AWhat, AGot, AWant]));
end;

procedure TCuOracleBase.SameBool(const AWhat: string; AGot, AWant: Boolean);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %s, upstream %s', [AWhat, BoolToStr(AGot, True), BoolToStr(AWant, True)]));
end;

procedure TCuOracleBase.SameInt(const AWhat: string; AGot, AWant: Integer);
begin
  Inc(FCompared);
  if AGot <> AWant then
    Bad(Format('%s %d, upstream %d', [AWhat, AGot, AWant]));
end;

procedure TCuOracleBase.SameColour(const AWhat: string; AHas: Boolean;
  AGot: TTyChartColor; AWant: TJSONData);
var want: TTyChartColor;
begin
  Inc(FCompared);
  if IsNull(AWant) or (AWant.JSONType <> jtString)
    or not TyTryParseChartColor(AWant.AsString, want) then
  begin
    if AHas then Bad(Format('%s %s, upstream no colour', [AWhat, IntToHex(AGot, 8)]));
    Exit;
  end;
  if (not AHas) or (AGot <> want) then
    Bad(Format('%s %s (%s), upstream %s', [AWhat, IntToHex(AGot, 8),
      BoolToStr(AHas, True), AWant.AsString]));
end;

{ a packed colour against echarts.color.parse's [r, g, b, a] }
procedure TCuOracleBase.SameRgba(const AWhat: string; AHas: Boolean;
  AGot: TTyChartColor; AWant: TJSONData);
var r, g, b: Integer; a: Double;
begin
  Inc(FCompared);
  if IsNull(AWant) then
  begin
    if AHas then Bad(Format('%s %s, upstream none', [AWhat, IntToHex(AGot, 8)]));
    Exit;
  end;
  if not AHas then
  begin
    Bad(AWhat + ': none, upstream ' + AWant.AsJSON);
    Exit;
  end;
  r := (AGot shr 16) and $FF;
  g := (AGot shr 8) and $FF;
  b := AGot and $FF;
  a := ((AGot shr 24) and $FF) / 255;
  if (r <> AWant.Items[0].AsInteger) or (g <> AWant.Items[1].AsInteger)
    or (b <> AWant.Items[2].AsInteger) or (Abs(a - AWant.Items[3].AsFloat) > 0.003) then
    Bad(Format('%s [%d,%d,%d,%s], upstream %s', [AWhat, r, g, b, Txt(a), AWant.AsJSON]));
end;

procedure TCuOracleBase.SameValue(const AWhat: string;
  const AGot: TTyAnimValue; AWant: TJSONData);
var
  i, k, n: Integer;
  row: TJSONData;
begin
  if IsNull(AWant) then
  begin
    Inc(FCompared);
    if AGot.Kind <> avkNull then Bad(AWhat + ': a value, upstream none');
    Exit;
  end;
  case AWant.JSONType of
    jtBoolean:
      begin
        Inc(FCompared);
        if (AGot.Kind <> avkBool) or ((AGot.Num <> 0) <> AWant.AsBoolean) then
          Bad(AWhat + ': not the boolean ' + AWant.AsJSON);
      end;
    jtString:
      if IsHex(AWant) then
      begin
        if AGot.Kind = avkNumber then Same(AWhat, AGot.Num, AWant)
        else Bad(AWhat + ': no number, upstream ' + Txt(FromHex(AWant.AsString)));
      end
      else
      begin
        if AGot.Kind = avkString then SameStr(AWhat, AGot.Str, AWant.AsString)
        else Bad(AWhat + ': no text, upstream ' + AWant.AsString);
      end;
    jtArray:
      begin
        if AGot.Kind <> avkArray then
        begin
          Bad(AWhat + ': no array');
          Exit;
        end;
        if (AWant.Count > 0) and (AWant.Items[0].JSONType = jtArray) then
        begin
          n := 0;
          for i := 0 to AWant.Count - 1 do
          begin
            row := AWant.Items[i];
            for k := 0 to row.Count - 1 do
            begin
              if n <= High(AGot.Arr) then Same(Format('%s[%d][%d]', [AWhat, i, k]), AGot.Arr[n], row.Items[k])
              else Bad(AWhat + ': short');
              Inc(n);
            end;
          end;
        end
        else
        begin
          SameInt(AWhat + ' length', Length(AGot.Arr), AWant.Count);
          for i := 0 to Min(AWant.Count, Length(AGot.Arr)) - 1 do
            Same(Format('%s[%d]', [AWhat, i]), AGot.Arr[i], AWant.Items[i]);
        end;
      end;
  else
    Bad(AWhat + ': an unexpected record ' + AWant.AsJSON);
  end;
end;

procedure TCuOracleBase.SameMatrix(const AWhat: string; AHas: Boolean;
  const AGot: TTyMat2D; AWant: TJSONData);
var
  k: Integer;
  m: TTyMat2D;
begin
  if not AHas then
  begin
    m[0] := 1; m[1] := 0; m[2] := 0; m[3] := 1; m[4] := 0; m[5] := 0;
  end
  else
    m := AGot;
  if IsNull(AWant) then
  begin
    Inc(FCompared);
    if not ((m[0] = 1) and (m[1] = 0) and (m[2] = 0) and (m[3] = 1) and (m[4] = 0) and (m[5] = 0)) then
      Bad(AWhat + ': a transform, upstream none');
    Exit;
  end;
  for k := 0 to 5 do Same(Format('%s[%d]', [AWhat, k]), m[k], AWant.Items[k]);
end;

{ two recorded values: an object's keys in any order, everything else as
  written }
procedure TCuOracleBase.SameJson(const AWhat: string; AGot, AWant: TJSONData);
var
  i, k: Integer;
  nm: string;
begin
  if IsNull(AWant) or IsNull(AGot) then
  begin
    Inc(FCompared);
    if IsNull(AWant) <> IsNull(AGot) then
    begin
      if AGot = nil then Bad(AWhat + ': nothing, upstream ' + AWant.AsJSON)
      else if AWant = nil then Bad(AWhat + ': ' + AGot.AsJSON + ', upstream nothing')
      else Bad(AWhat + ': ' + AGot.AsJSON + ', upstream ' + AWant.AsJSON);
    end;
    Exit;
  end;
  if AGot.JSONType <> AWant.JSONType then
  begin
    Inc(FCompared);
    Bad(AWhat + ': ' + AGot.AsJSON + ', upstream ' + AWant.AsJSON);
    Exit;
  end;
  case AWant.JSONType of
    jtObject:
      begin
        for i := 0 to AWant.Count - 1 do
        begin
          nm := TJSONObject(AWant).Names[i];
          SameJson(AWhat + '.' + nm, TJSONObject(AGot).Find(nm), AWant.Items[i]);
        end;
        for k := 0 to AGot.Count - 1 do
          if TJSONObject(AWant).IndexOfName(TJSONObject(AGot).Names[k]) < 0 then
          begin
            Inc(FCompared);
            if not IsNull(AGot.Items[k]) then
              Bad(AWhat + '.' + TJSONObject(AGot).Names[k] + ': ' + AGot.Items[k].AsJSON
                + ', upstream none');
          end;
      end;
    jtArray:
      begin
        SameInt(AWhat + ' length', AGot.Count, AWant.Count);
        for i := 0 to Min(AGot.Count, AWant.Count) - 1 do
          SameJson(Format('%s[%d]', [AWhat, i]), AGot.Items[i], AWant.Items[i]);
      end;
  else
    begin
      Inc(FCompared);
      if AGot.AsJSON <> AWant.AsJSON then
      begin
        if IsHex(AGot) and IsHex(AWant) then
          Bad(Format('%s %s, upstream %s', [AWhat, Txt(FromHex(AGot.AsString)),
            Txt(FromHex(AWant.AsString))]))
        else
          Bad(AWhat + ': ' + AGot.AsJSON + ', upstream ' + AWant.AsJSON);
      end;
    end;
  end;
end;

procedure TCuOracleBase.Finish(const AWhat: string; AMin: Integer);
begin
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AWhat, FBad, FCompared, FReport]), 0, FBad);
  AssertTrue(Format('%s: only %d compared', [AWhat, FCompared]), FCompared >= AMin);
end;

function TCuOracleBase.Cases(const AGroup: string): TJSONArray;
var
  all: TJSONArray;
  i: Integer;
begin
  Result := TJSONArray.Create;
  all := TJSONObject(FRoot).Arrays['cases'];
  for i := 0 to all.Count - 1 do
    if all.Objects[i].Strings['group'] = AGroup then Result.Add(all.Objects[i].Clone);
end;

procedure TCuOracleBase.NewChart(AW, AH: Integer);
var m: TJSONObject;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FChart);
  FChart := TCuProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(
    TZrSsrMeasurer.Create(m.Arrays['ratio'], m.Integers['firstCode']));
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, AW, AH);
end;

procedure TCuOracleBase.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ 's<series>:<raw>' for an item's root, '/k' per child, '#label' for a
  textContent }
function TCuOracleBase.KeyOf(AEl: TTyGfxEl): string;
var
  el, p: TTyGfxEl;
  s, k, raw: Integer;
  view: TTyCustomView;
  suffix: string;
begin
  Result := '';
  if AEl = nil then Exit;
  suffix := '';
  el := AEl;
  if el.Host <> nil then
  begin
    suffix := '#label';
    el := el.Host;
  end;
  while el <> nil do
  begin
    p := el.Parent;
    if p = nil then Exit('');
    for s := 0 to 9 do
    begin
      view := FChart.CustomView(s);
      if (view <> nil) and (view.Root = p) then
      begin
        raw := view.RawOfRoot(el);
        Exit('s' + IntToStr(s) + ':' + IntToStr(raw) + Result + suffix);
      end;
    end;
    for k := 0 to High(p.Children) do
      if p.Children[k] = el then Result := '/' + IntToStr(k) + Result;
    el := p;
  end;
end;

{ every element of every custom view, depth first, by key }
function TCuOracleBase.Keyed: TStringList;
var
  s, i: Integer;
  view: TTyCustomView;

  procedure Walk(AEl: TTyGfxEl; const AKey: string);
  var k: Integer;
  begin
    Result.AddObject(AKey, AEl);
    for k := 0 to High(AEl.Children) do Walk(AEl.Children[k], AKey + '/' + IntToStr(k));
  end;

begin
  Result := TStringList.Create;
  for s := 0 to 9 do
  begin
    view := FChart.CustomView(s);
    if view = nil then Continue;
    for i := 0 to High(view.Root.Children) do
      Walk(view.Root.Children[i], 's' + IntToStr(s) + ':'
        + IntToStr(view.RawOfRoot(view.Root.Children[i])));
  end;
end;

{ the paint list entries of an item's paths, in list order }
function TCuOracleBase.PathsOfItem(ASeries, ARaw: Integer): TTyIntegerArray;
var
  k: Integer;
  e: TTyChartElement;
  gel: TTyGfxEl;
begin
  Result := nil;
  for k := 0 to FChart.List.Count - 1 do
  begin
    e := FChart.List.Element(k);
    gel := FChart.CustomPaintSource(k);
    if (gel = nil) or not gel.StatePath or (gel.Host <> nil) then Continue;
    if (e.Datum.SeriesIndex <> ASeries) or (e.Datum.RawDataIndex <> ARaw) then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := k;
  end;
end;

procedure TCuOracleBase.CheckPieces(const AWhat: string;
  const APieces: TTyRtPieceArray; AWant: TJSONArray);
var
  i: Integer;
  w: TJSONObject;
  p: TTyRtPiece;
  px: Double;
  weight: Integer;
  family: string;
  italic: Boolean;
  where: string;
begin
  SameInt(AWhat + ' pieces', Length(APieces), AWant.Count);
  for i := 0 to Min(Length(APieces), AWant.Count) - 1 do
  begin
    w := AWant.Objects[i];
    p := APieces[i];
    where := Format('%s piece %d', [AWhat, i]);
    if w.Strings['k'] = 't' then
    begin
      if p.Kind <> rpkText then
      begin
        Bad(where + ': not a text');
        Continue;
      end;
      SameStr(where + ' text', p.Text, w.Get('text', ''));
      Same(where + ' x', p.X, w.Find('x'));
      Same(where + ' y', p.Y, w.Find('y'));
      TyGfxParseFont(w.Get('font', ''), px, weight, family, italic);
      Same(where + ' font size', p.FontSizePx, TJSONFloatNumber.Create(px));
      SameBool(where + ' bold', p.FontWeight >= 600, weight >= 600);
      SameStr(where + ' family', p.FontFamily, family);
      SameStr(where + ' align', AlignName(p.TextAlign), w.Get('align', 'left'));
      SameColour(where + ' fill', p.HasFill, p.Fill, w.Find('fill'));
      SameColour(where + ' stroke', p.HasStroke, p.Stroke, w.Find('stroke'));
      if p.HasStroke and not IsNull(w.Find('stroke')) then
        Same(where + ' lineWidth', p.LineWidth, w.Find('lineWidth'));
      Same(where + ' opacity', p.Opacity, w.Find('opacity'));
    end
    else if w.Strings['k'] = 'r' then
    begin
      if p.Kind <> rpkRect then
      begin
        Bad(where + ': not a rect');
        Continue;
      end;
      Same(where + ' x', p.X, w.Find('x'));
      Same(where + ' y', p.Y, w.Find('y'));
      Same(where + ' width', p.W, w.Find('width'));
      Same(where + ' height', p.H, w.Find('height'));
    end;
  end;
end;

procedure TCuOracleBase.CheckTextStyle(const AWhat: string;
  AEl: TTyGfxEl; AWant: TJSONObject);
var
  font: string;
  v: TTyAnimValue;
  d: TJSONData;
begin
  d := AEl.Style.Find('text');
  if IsNull(AWant.Find('text')) then SameBool(AWhat + ' no text', IsNull(d), True)
  else if d = nil then Bad(AWhat + ': no text')
  else if d.JSONType = jtNumber then SameStr(AWhat + ' text', TyJsNumberToString(d.AsFloat), AWant.Strings['text'])
  else SameStr(AWhat + ' text', d.AsString, AWant.Strings['text']);
  font := TyGfxMakeFont(AEl.Style);
  if IsNull(AWant.Find('font')) then SameStr(AWhat + ' font', font, '')
  else SameStr(AWhat + ' font', font, AWant.Strings['font']);
  v := AEl.StyleValue('fill');
  if v.Kind = avkString then SameStr(AWhat + ' fill', v.Str, AWant.Get('fill', ''))
  else SameBool(AWhat + ' no fill', True, IsNull(AWant.Find('fill')));
  v := AEl.StyleValue('stroke');
  if v.Kind = avkString then SameStr(AWhat + ' stroke', v.Str, AWant.Get('stroke', ''))
  else SameBool(AWhat + ' no stroke', True, IsNull(AWant.Find('stroke')));
  v := AEl.StyleValue('align');
  if (v.Kind = avkString) and not IsNull(AWant.Find('align')) then
    SameStr(AWhat + ' align', v.Str, AWant.Strings['align'])
  else
    SameBool(AWhat + ' no align', v.Kind <> avkString, IsNull(AWant.Find('align')));
end;

procedure TCuOracleBase.CheckEl(AEl: TTyGfxEl; AWant: TJSONObject);
const
  cT: array[0..6] of string = ('x', 'y', 'rotation', 'scaleX', 'scaleY',
    'originX', 'originY');
var
  t, sh, st, lab, inner, def, ec: TJSONObject;
  k, i, inside: Integer;
  path: TTyDoubleArray;
  want: TJSONArray;
  d: TJSONData;
  tc, root: TTyGfxEl;
  wantInfo: TJSONData;
  meas: ITyTextMeasurer;
  view: TTyCustomView;
begin
  Inc(FEls);
  meas := FChart.Measurer;
  SameStr('type', AEl.ZrType, AWant.Strings['type']);
  SameStr('name', AEl.Name, AWant.Get('name', ''));
  SameBool('silent', AEl.Silent, AWant.Booleans['silent']);
  SameBool('ignore', AEl.Ignore, AWant.Booleans['ignore']);
  SameBool('invisible', AEl.Invisible, AWant.Booleans['invisible']);
  if not AEl.IsGroup then
  begin
    Same('z', AEl.Z, AWant.Find('z'));
    Same('zlevel', AEl.ZLevel, AWant.Find('zlevel'));
    Same('z2', AEl.Z2, AWant.Find('z2'));
  end;
  t := AWant.Objects['t'];
  for k := 0 to High(cT) do Same(cT[k], AEl.GetAnimProp(cT[k]).Num, t.Find(cT[k]));
  SameMatrix('transform', AEl.HasTransform, AEl.Transform, AWant.Find('transform'));
  { the item the element carries: the root's dataIndexInside }
  ec := nil;
  if AWant.Find('ec') is TJSONObject then ec := AWant.Objects['ec'];
  if ec <> nil then
  begin
    root := AEl;
    while (root.Parent <> nil) and (root.Parent.Parent <> nil) do root := root.Parent;
    inside := -1;
    for i := 0 to 9 do
    begin
      view := FChart.CustomView(i);
      if (view <> nil) and (view.Root = root.Parent) then
      begin
        inside := view.InsideOfRoot(root);
        SameInt('ec.seriesIndex', i, ec.Integers['seriesIndex']);
      end;
    end;
    SameInt('ec.dataIndex', inside, ec.Integers['dataIndex']);
  end;
  d := AWant.Find('info');
  if IsNull(d) then SameBool('no info', AEl.Info = nil, True)
  else
  begin
    wantInfo := GetJSON(d.AsString);
    try
      if AEl.Info = nil then Bad('no info, upstream ' + d.AsString)
      else SameJson('info', Rv(AEl.Info), Rv(wantInfo));
    finally
      wantInfo.Free;
    end;
  end;
  sh := nil;
  if AWant.Find('shape') is TJSONObject then sh := AWant.Objects['shape'];
  if sh <> nil then
    for i := 0 to sh.Count - 1 do
      SameValue('shape.' + sh.Names[i], AEl.GetAnimProp('shape.' + sh.Names[i]), sh.Items[i]);
  if AWant.Find('path') is TJSONArray then
  begin
    want := AWant.Arrays['path'];
    path := PathData(TyGfxPath(AEl));
    SameInt('path length', Length(path), want.Count);
    for i := 0 to Min(Length(path), want.Count) - 1 do
      Same(Format('path[%d]', [i]), path[i], want.Items[i]);
  end;
  st := nil;
  if AWant.Find('style') is TJSONObject then st := AWant.Objects['style'];
  if st <> nil then
  begin
    if AEl.Kind = gkText then CheckTextStyle('style', AEl, st)
    else
    begin
      SameValue('style.fill', AEl.StyleValue('fill'), st.Find('fill'));
      SameValue('style.stroke', AEl.StyleValue('stroke'), st.Find('stroke'));
      SameValue('style.lineWidth', AEl.StyleValue('lineWidth'), st.Find('lineWidth'));
      SameValue('style.opacity', AEl.StyleValue('opacity'), st.Find('opacity'));
    end;
  end;
  if AWant.Find('pieces') is TJSONArray then
    CheckPieces('text', TyGfxTextLayout(AEl, meas).Pieces, AWant.Arrays['pieces']);
  tc := AEl.TextContent;
  if AWant.Find('label') is TJSONObject then
  begin
    lab := AWant.Objects['label'];
    if tc = nil then
      Bad('no textContent')
    else
    begin
      SameMatrix('label transform', tc.HasTransform, tc.Transform, lab.Find('transform'));
      inner := lab.Objects['inner'];
      Same('label inner.x', tc.InX, inner.Find('x'));
      Same('label inner.y', tc.InY, inner.Find('y'));
      Same('label inner.rotation', tc.InRot, inner.Find('rotation'));
      def := lab.Objects['def'];
      SameStr('label def.fill', tc.DefFill, def.Get('fill', ''));
      SameStr('label def.stroke', tc.DefStroke, def.Get('stroke', ''));
      SameBool('label def.autoStroke', tc.DefAutoStroke, def.Booleans['autoStroke']);
      SameStr('label def.align', tc.DefAlign, def.Get('align', ''));
      SameStr('label def.verticalAlign', tc.DefVAlign, def.Get('verticalAlign', ''));
      CheckTextStyle('label style', tc, lab.Objects['style']);
      CheckPieces('label', TyGfxTextLayout(tc, meas).Pieces, lab.Arrays['pieces']);
      Same('label z', tc.Z, lab.Find('z'));
      Same('label z2', tc.Z2, lab.Find('z2'));
      Same('label zlevel', tc.ZLevel, lab.Find('zlevel'));
      SameBool('label ignore', tc.Ignore, lab.Booleans['ignore']);
      SameBool('label silent', tc.Silent, lab.Booleans['silent']);
    end;
  end
  else if not AEl.IsGroup then
    SameBool('no textContent', tc = nil, True);
end;

procedure TCuOracleBase.CheckCalls(AWant: TJSONArray);
var
  i: Integer;
  was: string;
begin
  was := FWhere;
  SameInt('renderItem calls', FMirror.Calls.Count, AWant.Count);
  for i := 0 to Min(FMirror.Calls.Count, AWant.Count) - 1 do
  begin
    Inc(FCalls);
    FWhere := Format('%s call %d', [was, i]);
    SameJson('call', FMirror.Calls.Items[i], AWant.Items[i]);
  end;
  FWhere := was;
  FMirror.Calls.Clear;
end;

procedure TCuOracleBase.CheckEls(AWant: TJSONArray);
var
  got: TStringList;
  i: Integer;
  was: string;
begin
  was := FWhere;
  got := Keyed;
  try
    SameInt('elements', got.Count, AWant.Count);
    for i := 0 to Min(got.Count, AWant.Count) - 1 do
    begin
      FWhere := was + ' ' + AWant.Objects[i].Strings['key'];
      SameStr('key', got[i], AWant.Objects[i].Strings['key']);
      if got[i] = AWant.Objects[i].Strings['key'] then
        CheckEl(TTyGfxEl(got.Objects[i]), AWant.Objects[i]);
    end;
  finally
    got.Free;
    FWhere := was;
  end;
end;

{ the custom displayables in paint order, runs merged }
procedure TCuOracleBase.CheckOrder(AWant: TJSONArray);
var
  list: TTyPaintList;
  i: Integer;
  gel: TTyGfxEl;
  key: string;
  got: TStringList;
begin
  list := FChart.List;
  got := TStringList.Create;
  try
    for i := 0 to list.Count - 1 do
    begin
      gel := FChart.CustomPaintSource(list.PaintOrder(i));
      if gel = nil then Continue;
      key := KeyOf(gel);
      if (got.Count = 0) or (got[got.Count - 1] <> key) then got.Add(key);
    end;
    SameInt('order length', got.Count, AWant.Count);
    for i := 0 to Min(got.Count, AWant.Count) - 1 do
      SameStr(Format('order[%d]', [i]), got[i], AWant.Strings[i]);
  finally
    got.Free;
  end;
end;

procedure TCuOracleBase.CheckClips(AWant: TJSONArray);
var
  i: Integer;
  w: TJSONObject;
  r: TTyXYWH;
  has: Boolean;
begin
  for i := 0 to AWant.Count - 1 do
  begin
    w := AWant.Objects[i];
    has := FChart.CustomClip(w.Integers['s'], r);
    SameBool(Format('clip %d', [w.Integers['s']]), has, not IsNull(w.Find('rect')));
    if has and not IsNull(w.Find('rect')) then
    begin
      Same('clip.x', r.X, w.Arrays['rect'].Items[0]);
      Same('clip.y', r.Y, w.Arrays['rect'].Items[1]);
      Same('clip.w', r.W, w.Arrays['rect'].Items[2]);
      Same('clip.h', r.H, w.Arrays['rect'].Items[3]);
    end;
  end;
end;

procedure TCuOracleBase.CheckSt(AWant: TJSONArray);
var
  i, k, s, raw, part, idx, n, inside: Integer;
  w: TJSONObject;
  key, names, rootKey: string;
  p: Integer;
  paths: TTyIntegerArray;
  item: TTyStItem;
  el: TTyStElement;
  e: TTyChartElement;
  got: TStringList;
  gel: TTyGfxEl;
  nm: TTyStName;
  view: TTyCustomView;
begin
  got := Keyed;
  try
    for i := 0 to AWant.Count - 1 do
    begin
      w := AWant.Objects[i];
      key := w.Strings['key'];
      k := got.IndexOf(key);
      if k < 0 then
      begin
        Bad('st: no element ' + key);
        Continue;
      end;
      gel := TTyGfxEl(got.Objects[k]);
      { the item: series and raw from the key }
      p := Pos(':', key);
      s := StrToInt(Copy(key, 2, p - 2));
      n := Pos('/', key);
      if n = 0 then raw := StrToInt(Copy(key, p + 1, MaxInt))
      else raw := StrToInt(Copy(key, p + 1, n - p - 1));
      paths := PathsOfItem(s, raw);
      part := -1;
      for idx := 0 to High(paths) do
        if FChart.CustomPaintSource(paths[idx]) = gel then part := idx;
      if part < 0 then
      begin
        Bad('st: ' + key + ' is not drawn');
        Continue;
      end;
      e := FChart.List.Element(paths[part]);
      view := FChart.CustomView(s);
      if n = 0 then rootKey := key else rootKey := Copy(key, 1, n - 1);
      inside := view.InsideOfRoot(TTyGfxEl(got.Objects[got.IndexOf(rootKey)]));
      if not FChart.ItemStates(s, inside, item) then
      begin
        Bad('st: no state record for ' + key);
        Continue;
      end;
      if part = 0 then el := item.Host
      else if part - 1 <= High(item.Parts) then el := item.Parts[part - 1]
      else
      begin
        Bad('st: no part for ' + key);
        Continue;
      end;
      names := '';
      for nm := Low(TTyStName) to High(TTyStName) do
        if nm in el.States then
        begin
          if names <> '' then names := names + ',';
          case nm of
            stnSelect: names := names + 'select';
            stnEmphasis: names := names + 'emphasis';
            stnBlur: names := names + 'blur';
          end;
        end;
      SameStr(key + ' states', names, StringReplace(StringReplace(w.Arrays['states'].AsJSON,
        '"', '', [rfReplaceAll]), '[', '', [rfReplaceAll]).Replace(']', '').Replace(' ', ''));
      SameRgba(key + ' fill', e.Style.HasFill, e.Style.FillColor, w.Find('fill'));
      SameRgba(key + ' stroke', (e.Style.StrokeWidthLogical > 0) and (e.Style.StrokeColor <> 0),
        e.Style.StrokeColor, w.Find('stroke'));
      if not IsNull(w.Find('stroke')) then
        Same(key + ' lineWidth', e.Style.StrokeWidthLogical, w.Find('lineWidth'));
      Same(key + ' opacity', e.Style.Alpha, w.Find('opacity'));
      SameInt(key + ' z2', e.Z2, w.Integers['z2']);
    end;
  finally
    got.Free;
  end;
end;

procedure TCuOracleBase.CheckLegend(AWant: TJSONData);
var
  lay: TTyLegendLayout;
  j, k: Integer;
  w: TJSONObject;
  found: Boolean;
begin
  if IsNull(AWant) then Exit;
  if FChart.LegendLayoutCount = 0 then
  begin
    Bad('no legend here');
    Exit;
  end;
  lay := FChart.LegendLayout(0);
  SameInt('legend items', Length(lay.Items), AWant.Count);
  for j := 0 to AWant.Count - 1 do
  begin
    w := TJSONArray(AWant).Objects[j];
    found := False;
    for k := 0 to High(lay.Items) do
      if lay.Items[k].Name = w.Strings['name'] then
      begin
        found := True;
        SameStr('legend ' + w.Strings['name'] + ' icon', lay.Items[k].Icon, w.Strings['icon']);
        SameBool('legend ' + w.Strings['name'] + ' selected', lay.Items[k].Selected,
          w.Booleans['selected']);
        if w.Booleans['selected'] then
          SameRgba('legend ' + w.Strings['name'] + ' colour', True, lay.Items[k].Colour,
            w.Find('fill'));
      end;
    if not found then Bad('no legend item ' + w.Strings['name']);
  end;
end;

type
  TCuRow = record
    Marker, Name, Value: string;
    HasMarker, HasName, HasValue: Boolean;
  end;

function RowsOf(ABlock: TTyTooltipBlock): string;
var
  ink: TTyTooltipInk;
  lines: TTyTooltipLineArray;
  i, j: Integer;
  row: TCuRow;

  function Q(AHas: Boolean; const S: string): string;
  begin
    if AHas then Result := '"' + S + '"' else Result := 'null';
  end;

begin
  Result := '';
  if ABlock = nil then Exit;
  ink := Default(TTyTooltipInk);
  ink.NameWeight := 400;
  ink.ValueWeight := 900;
  ink.MarkerSizeLogical := 10;
  lines := TyTooltipFlatten(ABlock, ink);
  for i := 0 to High(lines) do
  begin
    row := Default(TCuRow);
    for j := 0 to High(lines[i].Runs) do
      if lines[i].Runs[j].Kind = ttrMarker then
      begin
        row.HasMarker := True;
        if lines[i].Runs[j].MarkerSizeLogical = 10 then row.Marker := 'item'
        else row.Marker := 'subItem';
      end
      else if lines[i].Runs[j].FontWeight = 900 then
      begin
        row.HasValue := True;
        row.Value := lines[i].Runs[j].Text;
      end
      else
      begin
        row.HasName := True;
        row.Name := lines[i].Runs[j].Text;
      end;
    Result := Result + '{' + Q(row.HasMarker, row.Marker) + ' ' + Q(row.HasName, row.Name)
      + ' ' + Q(row.HasValue, row.Value) + '}';
  end;
end;

function WantRows(ARows: TJSONArray): string;
var i: Integer;

  function Q(ARow: TJSONObject; const AKey: string): string;
  var d: TJSONData;
  begin
    d := ARow.Find(AKey);
    if (d = nil) or (d.JSONType = jtNull) then Result := 'null'
    else Result := '"' + d.AsString + '"';
  end;

begin
  Result := '';
  for i := 0 to ARows.Count - 1 do
    Result := Result + '{' + Q(ARows.Objects[i], 'marker') + ' ' + Q(ARows.Objects[i], 'name')
      + ' ' + Q(ARows.Objects[i], 'value') + '}';
end;

procedure TCuOracleBase.CheckPointer(AState: TJSONObject);
var
  hv, tip: TJSONObject;
  d: TTyChartDatumRef;
  el: Integer;
begin
  if AState.Find('hover') is TJSONObject then
  begin
    hv := AState.Objects['hover'];
    d := FChart.HitTestAt(AState.Arrays['point'].Integers[0], AState.Arrays['point'].Integers[1], el);
    if el < 0 then Bad('nothing hovered, upstream ' + hv.Get('key', ''))
    else
    begin
      SameStr('hovered', KeyOf(FChart.CustomPaintSource(el)), hv.Get('key', ''));
      SameInt('hovered series', d.SeriesIndex, hv.Integers['seriesIndex']);
      SameInt('hovered item', d.DataIndex, hv.Integers['dataIndex']);
    end;
  end;
  if AState.Find('tooltip') is TJSONObject then
  begin
    tip := AState.Objects['tooltip'];
    SameBool('the tooltip shown', FChart.TooltipShown, tip.Booleans['shown']);
    if tip.Booleans['shown'] and FChart.TooltipShown then
      SameStr('tooltip rows', RowsOf(FChart.ContentOf(FChart.TooltipShownDatum)),
        WantRows(tip.Arrays['rows']));
  end;
end;

procedure TCuOracleBase.CheckState(AState: TJSONObject; APointer: Boolean);
begin
  CheckCalls(AState.Arrays['calls']);
  if AState.Find('els') is TJSONArray then CheckEls(AState.Arrays['els']);
  if AState.Find('order') is TJSONArray then CheckOrder(AState.Arrays['order']);
  if AState.Find('clips') is TJSONArray then CheckClips(AState.Arrays['clips']);
  CheckSt(AState.Arrays['st']);
  CheckLegend(AState.Find('legend'));
  if APointer then CheckPointer(AState);
end;

procedure TCuOracleBase.RunCase(ACase: TJSONObject);
var
  steps, states: TJSONArray;
  step: TJSONObject;
  j: Integer;
  nowMs: Double;
  pointer: Boolean;
begin
  FWhere := ACase.Strings['id'];
  NewChart(ACase.Integers['W'], ACase.Integers['H']);
  FChart.TooltipNow := 0;
  FMirror.Calls.Clear;
  FChart.SetOption(ACase.Objects['option'].AsJSON, True);
  RenderNow;
  states := ACase.Arrays['states'];
  CheckState(states.Objects[0], False);
  steps := ACase.Arrays['steps'];
  for j := 0 to steps.Count - 1 do
  begin
    step := steps.Objects[j];
    FWhere := Format('%s step %d', [ACase.Strings['id'], j]);
    nowMs := (j + 1) * 1000;
    FChart.TooltipNow := nowMs;
    pointer := False;
    if step.Find('move') <> nil then
    begin
      FChart.Move(states.Objects[j + 1].Arrays['point'].Integers[0],
        states.Objects[j + 1].Arrays['point'].Integers[1]);
      pointer := True;
    end
    else if step.Find('leave') <> nil then
    begin
      FChart.Leave;
      pointer := True;
    end
    else if (step.Find('action') <> nil)
      and (step.Objects['action'].Get('type', '') = 'dataZoom') then
      { the port's dataZoom action is its own method }
      FChart.DispatchDataZoom(step.Objects['action'].Get('dataZoomIndex', 0),
        step.Objects['action'].Floats['start'], step.Objects['action'].Floats['end'])
    else if step.Find('action') <> nil then
      FChart.DispatchAction(step.Objects['action'].AsJSON)
    else if step.Find('merge') <> nil then
      FChart.SetOption(step.Objects['merge'].AsJSON, False);
    FChart.TooltipTick(nowMs + 500);
    FChart.TooltipNow := nowMs + 500;
    RenderNow;
    Inc(FSteps);
    CheckState(states.Objects[j + 1], pointer);
  end;
  FreeAndNil(FChart);
end;

procedure TCuOracleBase.RunGroup(const AGroup: string; AMin: Integer);
var
  arr: TJSONArray;
  i: Integer;
begin
  arr := Cases(AGroup);
  try
    AssertTrue('the group has cases', arr.Count > 0);
    for i := 0 to arr.Count - 1 do RunCase(arr.Objects[i]);
    Finish(AGroup, AMin);
  finally
    arr.Free;
  end;
end;

procedure TAdvChartCustomSeriesOracleTest.TestTheShapesAreUpstreams;
begin
  RunGroup('shape', 1500);
end;

procedure TAdvChartCustomSeriesOracleTest.TestTheMergesAreUpstreams;
begin
  RunGroup('merge', 300);
end;

procedure TAdvChartCustomSeriesOracleTest.TestTheLegendIsUpstreams;
begin
  RunGroup('legend', 200);
end;

procedure TAdvChartCustomSeriesOracleTest.TestTheDataZoomIsUpstreams;
begin
  RunGroup('zoom', 200);
end;

procedure TAdvChartCustomSeriesOracleTest.TestTheEmphasisIsUpstreams;
begin
  RunGroup('hover', 100);
end;

{ ==================== hand-written ==================== }

procedure TAdvChartCustomSeriesTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := nil;
  FCount := 0;
  FRaise := False;
  FInfos := TStringList.Create;
  TyChartClearRenderItems;
end;

procedure TAdvChartCustomSeriesTest.TearDown;
begin
  FreeAndNil(FChart);
  FreeAndNil(FInfos);
  TyChartClearRenderItems;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartCustomSeriesTest.Show(const AOption: string);
begin
  FreeAndNil(FChart);
  FChart := TCuProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.AnimationMode := camOff;
  FChart.SetBounds(0, 0, 400, 300);
  FChart.SetOption(AOption, True);
  RenderNow;
end;

function TAdvChartCustomSeriesTest.Diag: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to FChart.DiagnosticCount - 1 do
    Result := Result + FChart.Diagnostic(i) + '|';
end;

procedure TAdvChartCustomSeriesTest.RenderNow;
var bmp: TBGRABitmap;
begin
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
  finally
    bmp.Free;
  end;
end;

{ a red square of 20 px at the item's point }
function TAdvChartCustomSeriesTest.Plain(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var c: TTyDoubleArray;
begin
  Inc(FCount);
  if FRaise then raise Exception.Create('boom');
  c := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  Result := TJSONObject.Create(['type', 'rect',
    'shape', TJSONObject.Create(['x', c[0] - 10, 'y', c[1] - 10, 'width', 20, 'height', 20]),
    'style', TJSONObject.Create(['fill', '#ff0000'])]);
end;

{ a group nested far past what any reader takes }
function TAdvChartCustomSeriesTest.Deep(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  i: Integer;
  g: TJSONObject;
begin
  Inc(FCount);
  Result := TJSONObject.Create(['type', 'rect']);
  for i := 1 to 400 do
  begin
    g := TJSONObject.Create(['type', 'group', 'children', TJSONArray.Create([Result])]);
    Result := g;
  end;
end;

const
  cPlainOption = '{"animation":false,"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},'
    + '"series":[{"type":"custom","renderItem":"%s","data":[[2,3],[5,5],[8,7]]}]}';

procedure TAdvChartCustomSeriesTest.TestTheRegistryFindsANameEitherWay;
var h: TTyChartRenderItem;
begin
  TyChartRegisterRenderItem('Plain', @Plain);
  AssertTrue('by its name', TyChartFindRenderItem('Plain', h));
  AssertTrue('and as a handler reference', TyChartFindRenderItem('@Plain', h));
  AssertFalse('case matters', TyChartFindRenderItem('plain', h));
  Show(Format(cPlainOption, ['@Plain']));
  AssertEquals('one call per item, the @ form', 3, FCount);
  FCount := 0;
  Show(Format(cPlainOption, ['Plain']));
  AssertEquals('and the registerCustomSeries form', 3, FCount);
  TyChartUnregisterRenderItem('@Plain');
  AssertFalse('gone', TyChartFindRenderItem('Plain', h));
end;

procedure TAdvChartCustomSeriesTest.TestAnUnregisteredRenderItemIsNamed;
begin
  Show(Format(cPlainOption, ['@Nobody']));
  AssertTrue('the note names the handler: ' + Diag,
    Pos('Nobody', Diag) > 0);
  AssertEquals('and nothing is drawn', 0, Length(FChart.CustomView(0).Root.Children));
  AssertTrue('and custom is no longer "not drawn yet"',
    Pos('not drawn yet', Diag) = 0);
end;

procedure TAdvChartCustomSeriesTest.TestARaisingRenderItemIsNamedAndDrawsNothing;
begin
  TyChartRegisterRenderItem('Plain', @Plain);
  FRaise := True;
  Show(Format(cPlainOption, ['@Plain']));
  AssertTrue('the note says it raised: ' + Diag,
    Pos('boom', Diag) > 0);
  AssertEquals('every item was asked', 3, FCount);
  AssertEquals('none is drawn', 0, Length(FChart.CustomView(0).Root.Children));
end;

procedure TAdvChartCustomSeriesTest.TestATreeTooDeepIsRefused;
begin
  TyChartRegisterRenderItem('Deep', @Deep);
  Show(Format(cPlainOption, ['@Deep']));
  AssertEquals('every item was asked', 3, FCount);
  AssertEquals('none is drawn', 0, Length(FChart.CustomView(0).Root.Children));
  AssertTrue('and the chart says why: ' + Diag, Pos('Deep', Diag) > 0);
end;

procedure TAdvChartCustomSeriesTest.TestTheBarLayoutIsCalcBarWidthAndOffset;
var
  opt: TJSONObject;
  r: TTyCustomBarLayout;
begin
  { one column, the defaults: barCategoryGap 31% of a 100 px band, so 69 px
    centred }
  opt := TJSONObject.Create(['count', 1]);
  try
    r := TyCustomBarLayout(100, opt);
  finally
    opt.Free;
  end;
  AssertEquals(1, Length(r));
  AssertEquals('width', 69, r[0].Width, 1e-12);
  AssertEquals('offset', -34.5, r[0].Offset, 1e-12);
  AssertEquals('centre', 0, r[0].OffsetCenter, 1e-12);
  { a width and a cap: barWidth 12 under barMaxWidth 10 is 10 }
  opt := TJSONObject.Create(['count', 2, 'barWidth', 12, 'barMaxWidth', 10, 'barGap', 0]);
  try
    r := TyCustomBarLayout(100, opt);
  finally
    opt.Free;
  end;
  AssertEquals(2, Length(r));
  AssertEquals('capped', 10, r[0].Width, 1e-12);
  AssertEquals('side by side', -10, r[0].Offset, 1e-12);
  AssertEquals('and the next', 0, r[1].Offset, 1e-12);
  { no count is no columns }
  opt := TJSONObject.Create;
  try
    AssertEquals('no count', 0, Length(TyCustomBarLayout(100, opt)));
  finally
    opt.Free;
  end;
end;

procedure TAdvChartCustomSeriesTest.TestTheElementsArePainted;
var
  bmp: TBGRABitmap;
  p: TBGRAPixel;
  c: TTyDoubleArray;
  x, y: Integer;
begin
  TyChartRegisterRenderItem('Plain', @Plain);
  Show(Format(cPlainOption, ['@Plain']));
  { the second item's square, read off the paint list's geometry }
  AssertTrue('three elements', FChart.List.Count >= 3);
  bmp := TBGRABitmap.Create(FChart.Width, FChart.Height, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, FChart.Width, FChart.Height), 96);
    c := nil;
    SetLength(c, 2);
    c[0] := FChart.CustomView(0).ElOf(1).Shape.Floats['x'] + 10;
    c[1] := FChart.CustomView(0).ElOf(1).Shape.Floats['y'] + 10;
    x := Round(c[0]);
    y := Round(c[1]);
    p := bmp.GetPixel(x, y);
    AssertTrue(Format('red at the item, got %d,%d,%d', [p.red, p.green, p.blue]),
      (p.red > 200) and (p.green < 60) and (p.blue < 60));
  finally
    bmp.Free;
  end;
end;

{ a compoundPath for the second item: upstream throws out of render -- the
  item before it is drawn, nothing after it, and the chart says why }
function TAdvChartCustomSeriesTest.Unknown(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
begin
  Inc(FCount);
  if AParams.DataIndex = 1 then
    Exit(TJSONObject.Create(['type', 'compoundPath']));
  Result := Plain(AParams, AApi);
  Dec(FCount);
end;

procedure TAdvChartCustomSeriesTest.TestAnUnknownTypeStopsTheRender;
begin
  TyChartRegisterRenderItem('Unknown', @Unknown);
  Show(Format(cPlainOption, ['@Unknown']));
  AssertEquals('asked until it stopped', 2, FCount);
  AssertEquals('the first is drawn', 1, Length(FChart.CustomView(0).Root.Children));
  AssertTrue('and the note says why: ' + Diag,
    Pos('compoundPath', Diag) > 0);
  { the next render starts over: no element of the aborted one is kept as
    the data's }
  FCount := 0;
  FChart.SetOption('{"series":[{"data":[[2,3]]}]}', False);
  RenderNow;
  AssertEquals('one item again', 1, FCount);
  AssertEquals('drawn once', 1, Length(FChart.CustomView(0).Root.Children));
end;

{ the plain square, its info naming the item }
function TAdvChartCustomSeriesTest.WithInfo(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
begin
  Result := Plain(AParams, AApi);
  TJSONObject(Result).Add('info', TJSONObject.Create(['row', AParams.DataIndex]));
end;

{ [R2-V] a path at the item's point: across under 5, down above it }
function TAdvChartCustomSeriesTest.PathByValue(const AParams: TTyCustomParams;
  AApi: TTyCustomApi): TJSONData;
var
  c: TTyDoubleArray;
  pd: string;
begin
  c := AApi.Coord([AApi.Value(0), AApi.Value(1)]);
  if AApi.Value(1) > 5 then pd := 'M0 0L0 20' else pd := 'M0 0L20 0';
  Result := TJSONObject.Create(['type', 'path', 'x', c[0], 'y', c[1],
    'shape', TJSONObject.Create(['pathData', pd]),
    'style', TJSONObject.Create(['fill', 'none', 'stroke', '#ff0000'])]);
end;

{ [R2-V] doesElNeedRecreate: a path whose own pathData differs from the one
  it was made of is made anew (the path element keeps no pathData of its
  own to update -- makePath built it once) }
procedure TAdvChartCustomSeriesTest.TestAPathOfNewPathDataIsMadeAnew;
var
  el: TTyGfxEl;
  bb: TTyXYWH;
begin
  TyChartRegisterRenderItem('PathByValue', @PathByValue);
  Show(Format(cPlainOption, ['@PathByValue']));
  el := FChart.CustomView(0).ElOf(0);
  AssertTrue('drawn', el <> nil);
  bb := TyZrBBox(el.PathData);
  AssertTrue(Format('across at 3 (%g x %g)', [bb.W, bb.H]), (bb.W > 19) and (bb.H < 1e-9));
  FChart.SetOption('{"series":[{"data":[[2,9],[5,5],[8,7]]}]}', False);
  RenderNow;
  el := FChart.CustomView(0).ElOf(0);
  AssertTrue('drawn again', el <> nil);
  bb := TyZrBBox(el.PathData);
  AssertTrue(Format('down at 9: the new path data (%g x %g)', [bb.W, bb.H]),
    (bb.H > 19) and (bb.W < 1e-9));
end;

procedure TAdvChartCustomSeriesTest.OnEv(Sender: TObject; const AEvent: TTyChartEvent);
begin
  FInfos.Add(AEvent.EventType + ' ' + IntToStr(AEvent.Params.DataIndex) + ' '
    + AEvent.Params.Info);
end;

{ [Batch 124: a polar is drawn now -- a geo is the system this port has
  none of] [Batch 152: the port has a geo now; a custom naming one where the
  option has no geo component has no coordinate system, and says so] }
procedure TAdvChartCustomSeriesTest.TestAGeoCustomSaysItIsNotDrawn;
begin
  TyChartRegisterRenderItem('Plain', @Plain);
  Show('{"animation":false,'
    + '"series":[{"type":"custom","coordinateSystem":"geo","renderItem":"@Plain",'
    + '"data":[[1,2]]}]}');
  AssertEquals('not asked', 0, FCount);
  AssertTrue('the note names the system: ' + Diag, Pos('geo', Diag) > 0);
end;

procedure TAdvChartCustomSeriesTest.TestTheInfoRidesTheEvent;
var el: TTyGfxEl;
begin
  TyChartRegisterRenderItem('WithInfo', @WithInfo);
  Show(Format(cPlainOption, ['@WithInfo']));
  FChart.OnChartEvent := @OnEv;
  el := FChart.CustomView(0).ElOf(2);
  FChart.Move(Round(el.Shape.Floats['x'] + 10), Round(el.Shape.Floats['y'] + 10));
  AssertTrue('a mouseover of item 2 with its info: ' + FInfos.Text,
    FInfos.IndexOf('mouseover 2 { "row" : 2 }') >= 0);
end;

procedure TAdvChartCustomSeriesTest.TestItPaintsWithTheAnimationOn;
var
  bmp: TBGRABitmap;
  p: TBGRAPixel;
  el: TTyGfxEl;
begin
  { with the animation on, an element with no enterFrom enters as it is:
    drawn where renderItem put it, at once [Batch 124: the transitions are
    there now, and an empty enterFrom animates nothing] }
  TyChartRegisterRenderItem('Plain', @Plain);
  FreeAndNil(FChart);
  FChart := TCuProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 400, 300);
  FChart.SetOption('{"xAxis":{"type":"value","min":0,"max":10},'
    + '"yAxis":{"type":"value","min":0,"max":10},'
    + '"series":[{"type":"custom","renderItem":"@Plain","data":[[2,3],[5,5],[8,7]]}]}', True);
  bmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
  try
    FChart.Render(bmp.Canvas, Rect(0, 0, 400, 300), 96);
    el := FChart.CustomView(0).ElOf(1);
    AssertTrue('drawn', el <> nil);
    p := bmp.GetPixel(Round(el.Shape.Floats['x'] + 10), Round(el.Shape.Floats['y'] + 10));
    AssertTrue(Format('red at the item, got %d,%d,%d', [p.red, p.green, p.blue]),
      (p.red > 200) and (p.green < 60) and (p.blue < 60));
  finally
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartCustomSeriesOracleTest);
  RegisterTest(TAdvChartCustomSeriesTest);
end.
