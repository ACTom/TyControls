unit tyControls.AdvChart.Custom;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- THE CUSTOM SERIES: a host's renderItem draws every data
  item. [Batch 123, C14]

  UPSTREAM'S renderItem IS A FUNCTION; HERE IT IS A NAMED HANDLER. The option
  says `renderItem: '@Gantt'` (or `'Gantt'`, the form ECharts 6's
  registerCustomSeries gives a string renderItem), and the host registers a
  method under that name once:

      TyChartRegisterRenderItem('Gantt', @Form1.RenderGantt);

      function TForm1.RenderGantt(const AParams: TTyCustomParams;
        AApi: TTyCustomApi): TJSONData;
      var start, stop, size: TTyDoubleArray; cat, h: Double;
      begin
        cat := AApi.Value(0);
        start := AApi.Coord([AApi.Value(1), cat]);
        stop := AApi.Coord([AApi.Value(2), cat]);
        size := AApi.Size([0, 1]);
        h := size[1] * 0.6;
        Result := TJSONObject.Create(['type', 'rect',
          'shape', TJSONObject.Create(['x', start[0], 'y', start[1] - h / 2,
            'width', stop[0] - start[0], 'height', h]),
          'style', AApi.Style]);
      end;

  THE PARAMS (TTyCustomParams) are upstream's: the round's shared
  `context` object, the series' id, name and index, `dataIndex` (the item in
  the data as written) and `dataIndexInside` (in the data as shown, after a
  dataZoom or a legend filter), `dataInsideLength`, `actionType` (the type
  of the action whose update this is; '' for a setOption), `coordSys` (the
  coordinate system's prepareCustom, below), `encode` (coordinate dimension
  name -> the data dimension indices) and `itemPayload`.

  THE COORDINATE SYSTEMS [Batch 124, C15], each upstream's prepareCustom:
    cartesian2d   coordSys the grid's rect; Coord([x, y]) a point; Size per
                  axis (a category axis' band); BarLayout on a category base
                  axis
    polar         coordSys cx, cy, r, r0; Coord([radius, angle]) answers
                  four numbers: x, y, the radius in px and the angle in
                  radians; Size([dr, da] [, item]) px along the radius and
                  RADIANS around (a category angle axis' band)
    calendar      coordSys the rect, cellWidth / cellHeight and the range;
                  Coord([date]) a day's centre (NaN outside the range);
                  Layout([date]) its cell and content rect; no Size
    singleAxis    coordSys the axis' rect; Coord([v]) a point (the value as
                  JavaScript's +v); Size([d], [v]) ONE number
    'none'        no coordSys (Type_ ''), no Coord, no Size: the dimensions x
                  and y are whatever the author makes of them
  An api method a system has no counterpart of answers an empty array (or a
  Layout with Valid False) where upstream has no such function.

  THE API (TTyCustomApi) is upstream's, a method per function:
    Value(dim[, dataIndexInside])       the parsed value (an ordinal's index on
                                        a category axis); NaN for a text,
                                        whose ValueText says it
    ValueText(dim[, ...])               the value as JavaScript's String()
    OrdinalRawValue(dim[, ...])         a category's name, else ValueText
    Coord([x, y])                       the point, chart px; a text is a
                                        category name
    Size([dx, dy] [, [x, y]])           a data size in px per axis -- a
                                        category axis' band width
    Style([extra])                      the deprecated item style: the
                                        series' and the item's itemStyle with
                                        the visual colour and opacity, the ec4
                                        label keys, `legacy: true`, extra over
                                        it
    StyleEmphasis([extra])              the same for the emphasis state
    Visual('color' | 'borderColor' ...) the visual (a colour as text); nil for
                                        what upstream answers undefined
    BarLayout(opt)                      api.barLayout on the base category
                                        axis: one column per `count`;
                                        empty where upstream answers undefined
    CurrentSeriesIndices                the series the legend kept
    Font(opt)                           getFont over the global text style
    GetWidth / GetHeight / GetDevicePixelRatio
  A dimension is an index or a name ('x', or a name in `dimensions`); every
  method that reads an item takes an optional dataIndexInside, -1 the
  current one. upstream's getZr has no counterpart.

  WHAT IT RETURNS is an element option tree -- the same shapes the graphic
  component reads (AdvChart.GfxEl): `type` rect, circle, ellipse, ring,
  sector, arc, polygon, polyline, line, bezierCurve, image, text or group;
  transform keys, shape, style, z2, silent, ignore, invisible, info, name,
  textContent and textConfig, emphasis / blur / select (style, z2), a
  group's children with $mergeChildren ('byName', false, or by index) --
  and on the root focus, blurScope, emphasisDisabled. The result is the
  chart's (it frees it); nil, JSON null or false draws nothing for the item.
  A JSON value the api answers (Style, Visual) is the caller's until it is
  put into the tree.

  THE ELEMENTS follow upstream's merge principle (CustomView.ts): an item
  that was drawn before is updated in place -- a key the new option does not
  write keeps its value, `style` is replaced as a whole -- matched by the
  data item's id across updates (DataDiffer), a type that changed makes a
  new element, and a group's children merge by index (a null child is
  ignored, a shorter list removes the rest), by name, or not at all.

  THE TRANSITIONS [Batch 124, C15] are applyUpdateTransition's with the
  series as the animatable model: a new element runs from its `enterFrom`
  (the root's, the style's, the shape's) on the series' enter timing, an
  updated one from its old values of what `transition` names -- by default
  ['x', 'y'], 'all' every transform prop, the words 'shape' and 'style', the
  shape's and the style's own lists -- on the update timing; `enterAnimation`
  / `updateAnimation` override the timing. A removed element goes at once.
  One with a `leaveTo` stops the render: upstream's applyLeaveTransition
  reads an option CustomView never stores and throws there (6.1).
  [Batch 139: `extra` transitions, enters and leaves beside the shape;
  `additive` in enterAnimation / updateAnimation adds to what runs.]

  KEYFRAME ANIMATIONS [Batch 139, D6]: every element (a textContent too)
  first has its keyframe animations stopped and their values put back, and
  after its update runs the option's `keyframeAnimation` over the series
  (Graphic's TyGfxApplyKeyframes; a duration not written is the series'
  enter duration at data index 0).

  PURE: SysUtils, Classes, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Classes, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.GfxEl,
  tyControls.AdvChart.Graphic, tyControls.AdvChart.Anim,
  tyControls.AdvChart.AnimOpt;

const
  { the series type this unit draws }
  TyCustomSeriesType = 'custom';

  { what applyLeaveTransition throws on an element with a leaveTo (6.1) }
  TyCustomLeaveThrow = 'Cannot read properties of undefined (reading ''updateAnimation'')';

type
  { a calendar range end as getDateInfo writes it: the year, month and day
    as text ('2017', '02', '01'), the row within the week, the instant, and
    formatedDate [Batch 124] }
  TTyCustomCalDate = record
    Y, M, D: string;
    Day, Time: Double;
    FormatedDate: string;
  end;

  { params.coordSys: the prepareCustom of the series' coordinate system;
    Type_ says which fields mean anything [Batch 124] }
  TTyCustomCoordSys = record
    { 'cartesian2d', 'polar', 'calendar', 'singleAxis'; '' -- upstream's
      undefined -- on no coordinate system ('none') }
    Type_: string;
    { cartesian2d, calendar, singleAxis: the rect }
    X, Y, Width, Height: Double;
    { polar: the centre and the radius extent, the lesser first }
    Cx, Cy, R, R0: Double;
    { calendar: the cell size, and rangeInfo's start, end, weeks and
      dayCount }
    CellWidth, CellHeight: Double;
    RangeStart, RangeEnd: TTyCustomCalDate;
    Weeks, DayCount: Double;
    { [Batch 152] geo: the rect is the map's data rect (lng / lat, not
      pixels), and the zoom the view's (viewCoordSysGetZoomOption) }
    Zoom: Double;
  end;

  TTyCustomRect = record
    X, Y, Width, Height: Double;
  end;

  { api.layout on a calendar: the day's cell and its content rect (the cell
    less half the border); Valid False where upstream has no api.layout }
  TTyCustomLayout = record
    Valid: Boolean;
    Rect, ContentRect: TTyCustomRect;
  end;

  TTyCustomParams = record
    { one object for every call of one render (owned by the chart): what a
      call writes into it the next one reads }
    Context: TJSONObject;
    SeriesId, SeriesName: string;
    SeriesIndex: Integer;
    DataIndex, DataIndexInside, DataInsideLength: Integer;
    { the action whose update this is ('dataZoom', 'legendToggleSelect');
      '' -- upstream's null -- for a setOption, a resize }
    ActionType: string;
    CoordSys: TTyCustomCoordSys;
    { read-only, owned by the chart }
    Encode: TJSONObject;
    ItemPayload: TJSONObject;
  end;

  TTyCustomBarLayoutItem = record
    BandWidth, Offset, OffsetCenter, Width: Double;
  end;
  TTyCustomBarLayout = array of TTyCustomBarLayoutItem;

  { one cell of a Coord / Layout argument: a number or a text }
  TTyCustomCellKind = (cckNone, cckNumber, cckText);
  TTyCustomCell = record
    Kind: TTyCustomCellKind;
    Num: Double;
    Text: string;
  end;
  TTyCustomCellArray = array of TTyCustomCell;

  { The api a renderItem is handed. Abstract: the chart implements it over
    the series' data, visuals and coordinate system. }
  TTyCustomApi = class
  protected
    { a dimension name to its index (getDimensionIndex); -1 none }
    function DimIndexOf(const AName: string): Integer; virtual; abstract;
    function DoCoord(const ACells: TTyCustomCellArray): TTyDoubleArray; virtual; abstract;
    function DoLayout(const ACells: TTyCustomCellArray): TTyCustomLayout; virtual; abstract;
  public
    function Value(ADim: Integer; ADataIndexInside: Integer = -1): Double; overload; virtual; abstract;
    function Value(const ADim: string; ADataIndexInside: Integer = -1): Double; overload;
    function ValueText(ADim: Integer; ADataIndexInside: Integer = -1): string; overload; virtual; abstract;
    function ValueText(const ADim: string; ADataIndexInside: Integer = -1): string; overload;
    function OrdinalRawValue(ADim: Integer; ADataIndexInside: Integer = -1): string; overload; virtual; abstract;
    function OrdinalRawValue(const ADim: string; ADataIndexInside: Integer = -1): string; overload;
    { the point; on a polar [x, y, radius, angle in radians]; nothing on no
      coordinate system }
    function Coord(const AData: array of const): TTyDoubleArray;
    { a calendar day's cell [Batch 124] }
    function Layout(const AData: array of const): TTyCustomLayout;
    { no data item: upstream's undefined -- [0, 0] on a cartesian and a
      polar, NaN on a single axis }
    function Size(const ADataSize: array of Double): TTyDoubleArray; overload;
    { per dimension; ONE number on a single axis, nothing on a calendar or no
      coordinate system }
    function Size(const ADataSize, ADataItem: array of Double): TTyDoubleArray; overload; virtual; abstract;
    function Style(AExtra: TJSONObject = nil; ADataIndexInside: Integer = -1): TJSONObject; virtual; abstract;
    function StyleEmphasis(AExtra: TJSONObject = nil; ADataIndexInside: Integer = -1): TJSONObject; virtual; abstract;
    function Visual(const AType: string; ADataIndexInside: Integer = -1): TJSONData; virtual; abstract;
    { the visual as text: '' when it is undefined }
    function VisualText(const AType: string; ADataIndexInside: Integer = -1): string;
    function BarLayout(AOpt: TJSONObject): TTyCustomBarLayout; virtual; abstract;
    function CurrentSeriesIndices: TTyIntegerArray; virtual; abstract;
    function Font(AOpt: TJSONObject): string; virtual; abstract;
    function GetWidth: Double; virtual; abstract;
    function GetHeight: Double; virtual; abstract;
    function GetDevicePixelRatio: Double; virtual; abstract;
  end;

  { A renderItem. `of object`, as every named handler of the chart is. }
  TTyChartRenderItem = function(const AParams: TTyCustomParams;
    AApi: TTyCustomApi): TJSONData of object;

{ ---- the registry ----
  The rules of every handler registry: a name, registered once, replaced
  when registered again. '@Name' and 'Name' both find it. }
procedure TyChartRegisterRenderItem(const AName: string; AHandler: TTyChartRenderItem);
procedure TyChartUnregisterRenderItem(const AName: string);
function TyChartFindRenderItem(const ASpec: string; out AHandler: TTyChartRenderItem): Boolean;
procedure TyChartRenderItemNames(AList: TStrings);
procedure TyChartClearRenderItems;

{ calcBarWidthAndOffset as computeBarLayoutForCustomSeries runs it: ACount
  columns in a band of ABandWidth, the opt's barWidth, barMaxWidth,
  barMinWidth, barGap and barCategoryGap read as upstream reads them there
  (the first three as numbers, the gaps through parsePercent) }
function TyCustomBarLayout(ABandWidth: Double; AOpt: TJSONObject): TTyCustomBarLayout;

{ a packed colour as a CSS colour: '#rrggbb', or rgba() when not opaque }
function TyCustomColorText(AColor: Cardinal): string;

type
  { What the custom series keeps on an element it made (TTyGfxEl.Custom). }
  TTyCustomElInfo = class
  public
    { the option's type word, and whether it named the element }
    GType: string;
    HasName: Boolean;
    { the state objects' styles as the last update set them: 0 emphasis,
      1 blur, 2 select (owned; nil: no style) and z2 (NaN: not set) }
    StateStyle: array[0..2] of TJSONObject;
    StateZ2: array[0..2] of Double;
    { a root's: emphasis.focus as written ('' none), blurScope,
      emphasisDisabled, tooltipDisabled }
    Focus, BlurScope: string;
    EmphasisDisabled, TooltipDisabled: Boolean;
    { an image's source when made }
    ImagePath: string;
    constructor Create;
    destructor Destroy; override;
  end;

  { What the view calls for an item: the option renderItem returned (the
    view frees it), nil for nothing. }
  TTyCustomCallFn = function(AIndexInside: Integer): TJSONData of object;

  { the animation a render runs under [Batch 124] }
  TTyCustomAnim = record
    { hasAnimation: the series' isAnimationEnabled, and the chart's own
      switch }
    Enabled: Boolean;
    { the series: getAnimationConfig's timing (an update payload's
      included) }
    Model: TTyAnimModel;
    { the driver every element's animators join (nil: none) }
    Driver: TTyAnimation;
  end;

  { One series' view: its group of item roots, the last data's ids and
    elements (CustomView's _data), what render leaves behind. }
  TTyCustomView = class
  private
    FRoot: TTyGfxEl;
    FDetached, FGone: TFPList;
    FHasData: Boolean;
    FIds: TTyStringArray;
    FRaws: TTyIntegerArray;
    FEls: TTyGfxElArray;
    FZ, FZLevel: Double;
    FError: string;
    FAbort: Boolean;
    FAnim: TTyCustomAnim;
    { the dataIndexInside of the item being updated: getAnimationConfig's
      dataIndex }
    FIdx: Integer;
    function CreateEl(AOpt: TJSONObject): TTyGfxEl;
    procedure Discard(AEl: TTyGfxEl);
    { applyLeaveTransition: gone at once, or -- a leaveTo -- upstream's throw }
    procedure Leave(AEl: TTyGfxEl);
    procedure AddTo(AGroup, AEl: TTyGfxEl);
    function NeedRecreate(AEl: TTyGfxEl; AOpt: TJSONObject): Boolean;
    function ElementCfg(AType: TTyAnimType; AOpt: TJSONObject): TTyAnimCfg;
    procedure ApplyTransition(AEl: TTyGfxEl; AOpt: TJSONObject; AIsInit: Boolean);
    procedure UpdateNormal(AEl: TTyGfxEl; AOpt, ATxCfg: TJSONObject; AIsInit: Boolean);
    procedure UpdateAttachedTx(AEl: TTyGfxEl; AOpt: TJSONObject; AIsInit: Boolean);
    procedure UpdateStates(AEl: TTyGfxEl; AOpt: TJSONObject);
    procedure UpdateZ(AEl: TTyGfxEl; AOpt: TJSONObject);
    procedure MergeChildren(AEl: TTyGfxEl; AOpt: TJSONObject);
    function DoCreateOrUpdate(AExists: TTyGfxEl; AOpt: TJSONObject;
      AGroup: TTyGfxEl): TTyGfxEl;
    function CreateOrUpdateItem(AExists: TTyGfxEl; AOpt: TJSONData): TTyGfxEl;
    procedure AnimateLabels;
  public
    { the series model the view is for (its id and type) }
    Key: string;
    constructor Create;
    destructor Destroy; override;
    { CustomView.render: AIds the data's ids (getId) and ARaws its raw
      indices, by dataIndexInside; ACall renderItem's answer for one; AZ /
      AZLevel the series' z and zlevel (updateZ); AAnim the transitions'
      [Batch 124] }
    procedure Render(const AIds: TTyStringArray; const ARaws: TTyIntegerArray;
      ACall: TTyCustomCallFn; AZ, AZLevel: Double); overload;
    procedure Render(const AIds: TTyStringArray; const ARaws: TTyIntegerArray;
      ACall: TTyCustomCallFn; AZ, AZLevel: Double; const AAnim: TTyCustomAnim); overload;
    { every transition at its last frame (an animation switched off) }
    procedure Snap;
    { ChartView.remove (a series the legend switched off): the group
      emptied, the data and its elements kept for the next render }
    procedure RemoveAll;
    { the elements render removed, freed: call when nothing holds them }
    procedure FreeGone;
    { the root drawn for an item of the data as shown; nil none }
    function ElOf(AIndexInside: Integer): TTyGfxEl;
    { the raw index of an attached root; -1 for anything else }
    function RawOfRoot(AEl: TTyGfxEl): Integer;
    { the root drawn for the item of raw index ARaw; nil none [Batch 124] }
    function ElOfRaw(ARaw: Integer): TTyGfxEl;
    { the dataIndexInside of an attached root; -1 for anything else }
    function InsideOfRoot(AEl: TTyGfxEl): Integer;
    property Root: TTyGfxEl read FRoot;
    { what stopped the last render (upstream throws), '' none }
    property Error: string read FError;
    property HasData: Boolean read FHasData;
  end;

implementation

uses
  tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
  tyControls.AdvChart.AnimView;

{ ==================== JSON ==================== }

function JNull(A: TJSONData): Boolean; inline;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

function Truthy(A: TJSONData): Boolean;
begin
  if A = nil then Exit(False);
  case A.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

function ObjOf(AObj: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if AObj = nil then Exit;
  d := AObj.Find(AKey);
  if d is TJSONObject then Result := TJSONObject(d);
end;

procedure PutKey(AObj: TJSONObject; const AKey: string; AValue: TJSONData);
var i: Integer;
begin
  i := AObj.IndexOfName(AKey);
  if i >= 0 then AObj.Items[i] := AValue else AObj.Add(AKey, AValue);
end;

function StrOf(A: TJSONData): string;
begin
  Result := '';
  if A = nil then Exit;
  case A.JSONType of
    jtString: Result := A.AsString;
    jtNumber: Result := TyJsNumberToString(A.AsFloat);
  end;
end;

{ +v as JavaScript reads a JSON value }
function JsNum(A: TJSONData): Double;
begin
  if A = nil then Exit(NaN);
  case A.JSONType of
    jtNumber: Result := A.AsFloat;
    jtNull: Result := 0;
    jtBoolean: if A.AsBoolean then Result := 1 else Result := 0;
    jtString: Result := TyJsToNumber(A.AsString);
  else
    Result := NaN;
  end;
end;

{ ==================== the api's sugar ==================== }

function TTyCustomApi.Value(const ADim: string; ADataIndexInside: Integer): Double;
var d: Integer;
begin
  d := DimIndexOf(ADim);
  if d < 0 then Exit(NaN);
  Result := Value(d, ADataIndexInside);
end;

function TTyCustomApi.ValueText(const ADim: string; ADataIndexInside: Integer): string;
var d: Integer;
begin
  d := DimIndexOf(ADim);
  if d < 0 then Exit('undefined');
  Result := ValueText(d, ADataIndexInside);
end;

function TTyCustomApi.OrdinalRawValue(const ADim: string; ADataIndexInside: Integer): string;
var d: Integer;
begin
  d := DimIndexOf(ADim);
  if d < 0 then Exit('undefined');
  Result := OrdinalRawValue(d, ADataIndexInside);
end;

{ the cells of an `array of const`: a number, a text, a boolean as 0 / 1 }
function CellsOf(const AData: array of const): TTyCustomCellArray;
var i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AData));
  for i := 0 to High(AData) do
  begin
    Result[i] := Default(TTyCustomCell);
    case AData[i].VType of
      vtInteger:
        begin
          Result[i].Kind := cckNumber;
          Result[i].Num := AData[i].VInteger;
        end;
      vtInt64:
        begin
          Result[i].Kind := cckNumber;
          Result[i].Num := AData[i].VInt64^;
        end;
      vtQWord:
        begin
          Result[i].Kind := cckNumber;
          Result[i].Num := AData[i].VQWord^;
        end;
      vtExtended:
        begin
          Result[i].Kind := cckNumber;
          Result[i].Num := AData[i].VExtended^;
        end;
      vtCurrency:
        begin
          Result[i].Kind := cckNumber;
          Result[i].Num := AData[i].VCurrency^;
        end;
      vtString:
        begin
          Result[i].Kind := cckText;
          Result[i].Text := AData[i].VString^;
        end;
      vtAnsiString:
        begin
          Result[i].Kind := cckText;
          Result[i].Text := AnsiString(AData[i].VAnsiString);
        end;
      vtUnicodeString:
        begin
          Result[i].Kind := cckText;
          Result[i].Text := UTF8Encode(UnicodeString(AData[i].VUnicodeString));
        end;
      vtWideString:
        begin
          Result[i].Kind := cckText;
          Result[i].Text := UTF8Encode(WideString(AData[i].VWideString));
        end;
      vtChar:
        begin
          Result[i].Kind := cckText;
          Result[i].Text := AData[i].VChar;
        end;
      vtBoolean:
        begin
          Result[i].Kind := cckNumber;
          if AData[i].VBoolean then Result[i].Num := 1 else Result[i].Num := 0;
        end;
    end;
  end;
end;

function TTyCustomApi.Coord(const AData: array of const): TTyDoubleArray;
begin
  Result := DoCoord(CellsOf(AData));
end;

function TTyCustomApi.Layout(const AData: array of const): TTyCustomLayout;
begin
  Result := DoLayout(CellsOf(AData));
end;

function TTyCustomApi.Size(const ADataSize: array of Double): TTyDoubleArray;
begin
  { no dataItem: each system reads its undefined its own way }
  Result := Size(ADataSize, []);
end;

function TTyCustomApi.VisualText(const AType: string; ADataIndexInside: Integer): string;
var d: TJSONData;
begin
  d := Visual(AType, ADataIndexInside);
  try
    Result := StrOf(d);
  finally
    d.Free;
  end;
end;

{ ==================== the registry ==================== }

type
  TRenderItemEntry = class
    Handler: TTyChartRenderItem;
  end;

var
  GRenderItems: TStringList = nil;

function Registry: TStringList;
begin
  if GRenderItems = nil then
  begin
    GRenderItems := TStringList.Create;
    GRenderItems.CaseSensitive := True;
    GRenderItems.Sorted := True;
    GRenderItems.Duplicates := dupError;
    GRenderItems.OwnsObjects := True;
  end;
  Result := GRenderItems;
end;

function BareName(const ASpec: string): string;
begin
  Result := ASpec;
  if (Result <> '') and (Result[1] = '@') then Delete(Result, 1, 1);
end;

procedure TyChartRegisterRenderItem(const AName: string; AHandler: TTyChartRenderItem);
var
  i: Integer;
  e: TRenderItemEntry;
  nm: string;
begin
  nm := BareName(AName);
  if nm = '' then Exit;
  i := Registry.IndexOf(nm);
  if i >= 0 then
  begin
    TRenderItemEntry(Registry.Objects[i]).Handler := AHandler;
    Exit;
  end;
  e := TRenderItemEntry.Create;
  e.Handler := AHandler;
  Registry.AddObject(nm, e);
end;

procedure TyChartUnregisterRenderItem(const AName: string);
var i: Integer;
begin
  if GRenderItems = nil then Exit;
  i := GRenderItems.IndexOf(BareName(AName));
  if i >= 0 then GRenderItems.Delete(i);
end;

function TyChartFindRenderItem(const ASpec: string; out AHandler: TTyChartRenderItem): Boolean;
var i: Integer;
begin
  AHandler := nil;
  Result := False;
  if GRenderItems = nil then Exit;
  i := GRenderItems.IndexOf(BareName(ASpec));
  if i < 0 then Exit;
  AHandler := TRenderItemEntry(GRenderItems.Objects[i]).Handler;
  Result := Assigned(AHandler);
end;

procedure TyChartRenderItemNames(AList: TStrings);
var i: Integer;
begin
  if AList = nil then Exit;
  AList.Clear;
  if GRenderItems = nil then Exit;
  for i := 0 to GRenderItems.Count - 1 do AList.Add(GRenderItems[i]);
end;

procedure TyChartClearRenderItems;
begin
  if GRenderItems <> nil then GRenderItems.Clear;
end;

{ ==================== the bar layout ==================== }

{ JavaScript's arithmetic: a division by nought is an infinity or NaN, not a
  raise (the trap masked, MXCSR's sticky bits cleared before it is
  restored -- see the graph layout's pair) }
function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ Math.min / Math.max: NaN wins }
function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B < A then Result := B else Result := A;
end;

function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B > A then Result := B else Result := A;
end;

{ number.parsePercent: the position words, a percent of AAll, parseFloat
  of any other text, +v of the rest (null NaN) }
function JsParsePercent(A: TJSONData; AAll: Double): Double;
var s: string;
begin
  if JNull(A) then Exit(NaN);
  if A.JSONType = jtString then
  begin
    s := A.AsString;
    if (s = 'center') or (s = 'middle') then s := '50%'
    else if (s = 'left') or (s = 'top') then s := '0%'
    else if (s = 'right') or (s = 'bottom') then s := '100%';
    if (Trim(s) <> '') and (Trim(s)[Length(Trim(s))] = '%') then
      Exit(TyJsParseFloat(s) / 100 * AAll);
    Exit(TyJsParseFloat(s));
  end;
  Result := JsNum(A);
end;

function TyCustomBarLayout(ABandWidth: Double; AOpt: TJSONObject): TTyCustomBarLayout;
type
  TColumn = record
    Width, MaxWidth, MinWidth: Double;
  end;
var
  count, i, autoCount: Integer;
  remained, autoWidth, gapNum, gapPct, widthSum, offset, finalWidth, v: Double;
  barWidth, maxW, minW: Double;
  gapOpt, catGapOpt: TJSONData;
  cols: array of TColumn;
  mask: TFPUExceptionMask;

  function OptNum(const AKey: string): Double;
  var d: TJSONData;
  begin
    if AOpt = nil then Exit(NaN);
    d := AOpt.Find(AKey);
    if JNull(d) then Exit(NaN);
    Result := JsNum(d);
  end;

  { JavaScript's truthiness of a number }
  function T(V: Double): Boolean; inline;
  begin
    Result := not IsNan(V) and (V <> 0);
  end;

begin
  Result := nil;
  { `for (i = 0; i < opt.count || 0; i++)` }
  v := OptNum('count');
  if IsNan(v) or (v <= 0) then Exit;
  count := Ceil(v);
  cols := nil;
  SetLength(cols, count);
  mask := MaskFP;
  try
  remained := ABandWidth;
  autoCount := 0;
  gapOpt := nil;
  catGapOpt := nil;
  { every column is the opt again, under a stack of its own: the barGap of
    the last written (the first column's defaultBarGap, undefined, || 0) }
  for i := 0 to count - 1 do
  begin
    Inc(autoCount);
    cols[i].Width := 0;
    cols[i].MaxWidth := 0;
    cols[i].MinWidth := NaN;
    barWidth := OptNum('barWidth');
    if T(barWidth) then
    begin
      cols[i].Width := barWidth;
      barWidth := JMin(remained, barWidth);
      remained := remained - barWidth;
    end;
    maxW := OptNum('barMaxWidth');
    if T(maxW) then cols[i].MaxWidth := maxW;
    minW := OptNum('barMinWidth');
    if T(minW) then cols[i].MinWidth := minW;
    if (AOpt <> nil) and not JNull(AOpt.Find('barGap')) then gapOpt := AOpt.Find('barGap');
    if (AOpt <> nil) and not JNull(AOpt.Find('barCategoryGap')) then
      catGapOpt := AOpt.Find('barCategoryGap');
  end;
  { the default barCategoryGap is the text max(35 - n * 4, 15) + '%':
    parseFloat / 100 * all, in that order }
  if catGapOpt = nil then gapNum := Max(35 - count * 4, 15) / 100 * ABandWidth
  else gapNum := JsParsePercent(catGapOpt, ABandWidth);
  if gapOpt = nil then gapPct := 0 else gapPct := JsParsePercent(gapOpt, 1);
  autoWidth := (remained - gapNum) / (autoCount + (autoCount - 1) * gapPct);
  autoWidth := JMax(autoWidth, 0);
  for i := 0 to count - 1 do
  begin
    if not T(cols[i].Width) then
    begin
      finalWidth := autoWidth;
      if T(cols[i].MaxWidth) and (cols[i].MaxWidth < finalWidth) then
        finalWidth := JMin(cols[i].MaxWidth, remained);
      if T(cols[i].MinWidth) and (cols[i].MinWidth > finalWidth) then
        finalWidth := cols[i].MinWidth;
      if finalWidth <> autoWidth then
      begin
        cols[i].Width := finalWidth;
        remained := remained - (finalWidth + gapPct * finalWidth);
        Dec(autoCount);
      end;
    end
    else
    begin
      finalWidth := cols[i].Width;
      if T(cols[i].MaxWidth) then finalWidth := JMin(finalWidth, cols[i].MaxWidth);
      if T(cols[i].MinWidth) then finalWidth := JMax(finalWidth, cols[i].MinWidth);
      cols[i].Width := finalWidth;
      remained := remained - (finalWidth + gapPct * finalWidth);
      Dec(autoCount);
    end;
  end;
  autoWidth := (remained - gapNum) / (autoCount + (autoCount - 1) * gapPct);
  autoWidth := JMax(autoWidth, 0);
  widthSum := 0;
  for i := 0 to count - 1 do
  begin
    if not T(cols[i].Width) then cols[i].Width := autoWidth;
    widthSum := widthSum + cols[i].Width * (1 + gapPct);
  end;
  widthSum := widthSum - cols[count - 1].Width * gapPct;
  offset := -widthSum / 2;
  SetLength(Result, count);
  for i := 0 to count - 1 do
  begin
    Result[i].BandWidth := ABandWidth;
    Result[i].Offset := offset;
    Result[i].Width := cols[i].Width;
    Result[i].OffsetCenter := offset + cols[i].Width / 2;
    offset := offset + cols[i].Width * (1 + gapPct);
  end;
  finally
    UnmaskFP(mask);
  end;
end;

function TyCustomColorText(AColor: Cardinal): string;
var a: Cardinal;
begin
  a := (AColor shr 24) and $FF;
  if a = $FF then
    Result := '#' + LowerCase(IntToHex((AColor shr 16) and $FF, 2)
      + IntToHex((AColor shr 8) and $FF, 2) + IntToHex(AColor and $FF, 2))
  else
    Result := 'rgba(' + IntToStr((AColor shr 16) and $FF) + ','
      + IntToStr((AColor shr 8) and $FF) + ',' + IntToStr(AColor and $FF) + ','
      + TyJsNumberToString(a / 255) + ')';
end;

{ ==================== the element info ==================== }

constructor TTyCustomElInfo.Create;
var i: Integer;
begin
  inherited Create;
  for i := 0 to 2 do StateZ2[i] := NaN;
end;

destructor TTyCustomElInfo.Destroy;
var i: Integer;
begin
  for i := 0 to 2 do FreeAndNil(StateStyle[i]);
  inherited Destroy;
end;

function InfoOf(AEl: TTyGfxEl): TTyCustomElInfo;
begin
  if (AEl <> nil) and (AEl.Custom is TTyCustomElInfo) then
    Result := TTyCustomElInfo(AEl.Custom)
  else
    Result := nil;
end;

{ ==================== the view ==================== }

const
  cStates: array[0..2] of string = ('emphasis', 'blur', 'select');

constructor TTyCustomView.Create;
begin
  inherited Create;
  FRoot := TTyGfxEl.Create(gkGroup, 'group');
  FDetached := TFPList.Create;
  FGone := TFPList.Create;
  FZ := 2;
  FZLevel := 0;
end;

destructor TTyCustomView.Destroy;
var i: Integer;
begin
  FreeGone;
  for i := 0 to FDetached.Count - 1 do TTyGfxEl(FDetached[i]).Free;
  FreeAndNil(FDetached);
  FreeAndNil(FGone);
  FreeAndNil(FRoot);
  FEls := nil;
  inherited Destroy;
end;

procedure TTyCustomView.FreeGone;
var i: Integer;
begin
  for i := 0 to FGone.Count - 1 do TTyGfxEl(FGone[i]).Free;
  FGone.Clear;
end;

{ removed for good: off its parent (or out of the detached), to be freed }
procedure TTyCustomView.Discard(AEl: TTyGfxEl);
begin
  if AEl = nil then Exit;
  if FGone.IndexOf(AEl) >= 0 then Exit;
  if AEl.Parent <> nil then TyGfxRemoveChild(AEl.Parent, AEl);
  FDetached.Remove(AEl);
  FGone.Add(AEl);
end;

{ applyLeaveTransition: without a leaveTo the element is removed at once;
  with one upstream reads customInnerStore(el).option -- which CustomView
  never sets -- for the `updateAnimation` of the config and throws, so the
  render stops here [Batch 124] }
procedure TTyCustomView.Leave(AEl: TTyGfxEl);
begin
  if AEl = nil then Exit;
  if AEl.HasLeaveTo then
  begin
    FError := TyCustomLeaveThrow;
    FAbort := True;
    Exit;
  end;
  Discard(AEl);
end;

{ Group.add: a child already there stays where it is }
procedure TTyCustomView.AddTo(AGroup, AEl: TTyGfxEl);
begin
  if (AGroup = nil) or (AEl = nil) or (AEl.Parent = AGroup) then Exit;
  FDetached.Remove(AEl);
  TyGfxAddChild(AGroup, AEl);
end;

function TTyCustomView.CreateEl(AOpt: TJSONObject): TTyGfxEl;
var
  tp: string;
  info: TTyCustomElInfo;
  has: Boolean;
  st: TJSONObject;
begin
  tp := StrOf(AOpt.Find('type'));
  { path and compoundPath have no element here; an unknown type has no
    class upstream either -- both throw there }
  Result := TyGfxCreate(tp);
  if Result = nil then
  begin
    FError := 'graphic type "' + tp + '" can not be found.';
    FAbort := True;
    Exit;
  end;
  info := TTyCustomElInfo.Create;
  Result.Custom := info;
  info.GType := tp;
  { its animators join the chart's driver [Batch 124] }
  Result.Animation := FAnim.Driver;
  Result.Name := TyGfxIdOf(AOpt.Find('name'), has);
  info.HasName := has;
  if tp = 'image' then
  begin
    st := ObjOf(AOpt, 'style');
    if st <> nil then info.ImagePath := StrOf(st.Find('image'));
  end;
end;

{ doesElNeedRecreate: a type written and not the element's, an image whose
  source changed }
function TTyCustomView.NeedRecreate(AEl: TTyGfxEl; AOpt: TJSONObject): Boolean;
var
  tp: TJSONData;
  info: TTyCustomElInfo;
  st: TJSONObject;
begin
  info := InfoOf(AEl);
  tp := AOpt.Find('type');
  if not JNull(tp) and ((info = nil) or (StrOf(tp) <> info.GType)) then Exit(True);
  Result := False;
  if (info <> nil) and (info.GType = 'image') then
  begin
    st := ObjOf(AOpt, 'style');
    if (st <> nil) and (st.IndexOfName('image') >= 0)
      and (StrOf(st.Find('image')) <> info.ImagePath) then Result := True;
  end;
end;

{ getElementAnimationConfig: getAnimationConfig over the series (or an
  empty object: no duration when the series does not animate), setToFinal and the scope
  only when that duration is above 0, then the option's enterAnimation /
  updateAnimation over it [Batch 124] }
function TTyCustomView.ElementCfg(AType: TTyAnimType; AOpt: TJSONObject): TTyAnimCfg;
var
  timing: TTyAnimTiming;
  ext: TJSONObject;
  d: TJSONData;
  word: string;
begin
  Result := Default(TTyAnimCfg);
  if AType = atEnter then word := 'enter' else word := 'update';
  Result.HasDuration := False;
  Result.Delay := NaN;
  if TyAnimGetConfig(AType, FAnim.Model, TyAnimCallAt(FIdx), timing) then
  begin
    Result.Duration := timing.Duration;
    Result.HasDuration := True;
    Result.Delay := timing.Delay;
    Result.Easing := timing.Easing;
    if Result.Duration > 0 then
    begin
      Result.SetToFinal := True;
      Result.Scope := word;
    end;
  end;
  ext := ObjOf(AOpt, word + 'Animation');
  if ext <> nil then
  begin
    d := ext.Find('duration');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      Result.Duration := d.AsFloat;
      Result.HasDuration := True;
    end;
    d := ext.Find('easing');
    if (d <> nil) and (d.JSONType = jtString) then Result.Easing := d.AsString;
    d := ext.Find('delay');
    if (d <> nil) and (d.JSONType = jtNumber) then Result.Delay := d.AsFloat;
    { extend copies every key: `additive` too [Batch 139] }
    d := ext.Find('additive');
    if d <> nil then Result.Additive := Truthy(d);
  end;
  { the animator's `delay || 0` }
  if IsNan(Result.Delay) then Result.Delay := 0;
end;

{ applyUpdateTransition with clearStyle: the from props of an update, the
  final props at once (the style replaced), then the enter or the update
  animation, and the leaveTo kept [Batch 124] }
procedure TTyCustomView.ApplyTransition(AEl: TTyGfxEl; AOpt: TJSONObject;
  AIsInit: Boolean);
var
  from_, enter: TTyAnimProps;
  cfg: TTyAnimCfg;
begin
  from_ := nil;
  if not AIsInit and FAnim.Enabled then TyGfxTransitionFrom(AEl, AOpt, from_);
  TyGfxApplyDirect(AEl, AOpt, True);
  if FAnim.Enabled and (AEl.Animation <> nil) then
  begin
    if AIsInit then
    begin
      enter := nil;
      TyGfxEnterFrom(AOpt, enter);
      cfg := ElementCfg(atEnter, AOpt);
      if cfg.HasDuration and (cfg.Duration > 0) then AEl.AnimateFrom(enter, cfg);
    end
    else
    begin
      cfg := ElementCfg(atUpdate, AOpt);
      if cfg.HasDuration and (cfg.Duration > 0) then AEl.AnimateFrom(from_, cfg);
    end;
  end;
  TyGfxUpdateLeaveTo(AEl, AOpt);
end;

{ updateElNormal: the keyframe animations stopped and restored, setTextConfig,
  the default transition, the text's ec4 fill / stroke, applyUpdateTransition
  with clearStyle, then the option's keyframe animations [Batch 139] }
procedure TTyCustomView.UpdateNormal(AEl: TTyGfxEl; AOpt, ATxCfg: TJSONObject;
  AIsInit: Boolean);
var
  st: TJSONObject;
  timing: TTyAnimTiming;
  kfDur: Double;
begin
  { stopPreviousKeyframeAnimationAndRestore, before anything else }
  TyGfxStopKeyframes(AEl);
  if ATxCfg <> nil then
  begin
    if AEl.TextConfig = nil then AEl.TextConfig := TJSONObject.Create;
    TyGfxExtend(AEl.TextConfig, ATxCfg);
  end;
  { DEFAULT_TRANSITION, written into the option as upstream writes it: an
    element whose option names none moves its x and y }
  if JNull(AOpt.Find('transition')) then
    PutKey(AOpt, 'transition', TJSONArray.Create(['x', 'y']));
  st := ObjOf(AOpt, 'style');
  if (st <> nil) and (AEl.Kind = gkText) then
  begin
    if st.IndexOfName('textFill') >= 0 then PutKey(st, 'fill', st.Find('textFill').Clone);
    if st.IndexOfName('textStroke') >= 0 then PutKey(st, 'stroke', st.Find('textStroke').Clone);
  end;
  ApplyTransition(AEl, AOpt, AIsInit);
  { applyKeyframeAnimation over the series: a duration not written is the
    series' enter one at data index 0 }
  if FAnim.Enabled and (AEl.Animation <> nil) and Truthy(AOpt.Find('keyframeAnimation')) then
  begin
    kfDur := 0;
    if TyAnimGetConfig(atEnter, FAnim.Model, TyAnimCallAt(0), timing) then
      kfDur := timing.Duration;
    TyGfxApplyKeyframes(AEl, AOpt.Find('keyframeAnimation'), True, kfDur);
  end;
end;

{ processTxInfo for the normal state and doCreateOrUpdateAttachedTx: the
  textConfig and the textContent option -- written, or made from an ec4
  style -- and the textContent updated from it }
procedure TTyCustomView.UpdateAttachedTx(AEl: TTyGfxEl; AOpt: TJSONObject;
  AIsInit: Boolean);
var
  styleOpt, txCfg, txCon, convCfg, convCon, ownCfg, ownCon: TJSONObject;
  d: TJSONData;
  tc: TTyGfxEl;
  info: TTyCustomElInfo;
begin
  ownCfg := nil;
  ownCon := nil;
  try
    styleOpt := ObjOf(AOpt, 'style');
    txCfg := ObjOf(AOpt, 'textConfig');
    { a textContent: false is no option here (`!txConOptNormal ? null`) }
    txCon := ObjOf(AOpt, 'textContent');
    if (styleOpt <> nil) and TyGfxIsEC4(styleOpt, StrOf(AOpt.Find('type')),
      txCfg <> nil, txCon <> nil) then
    begin
      TyGfxConvertEC4(styleOpt, StrOf(AOpt.Find('type')), True, convCfg, convCon);
      if (txCfg = nil) and (convCfg <> nil) then
      begin
        ownCfg := convCfg;
        txCfg := convCfg;
      end
      else
        convCfg.Free;
      if (txCon = nil) and (convCon <> nil) then
      begin
        ownCon := convCon;
        txCon := convCon;
      end
      else
        convCon.Free;
    end;
    if (txCon <> nil) and JNull(txCon.Find('type')) then PutKey(txCon, 'type', TJSONString.Create('text'));
    { the group, a compoundPath: no text of their own }
    if AEl.IsGroup then Exit;
    if txCon <> nil then
    begin
      tc := AEl.TextContent;
      if tc = nil then
      begin
        tc := TTyGfxEl.Create(gkText, 'text');
        info := TTyCustomElInfo.Create;
        info.GType := 'text';
        tc.Custom := info;
        tc.Animation := FAnim.Driver;
        d := txCon.Find('name');
        if not JNull(d) then tc.Name := StrOf(d);
        tc.Host := AEl;
        AEl.TextContent := tc;
      end;
      { the host's isInit, whether the content is new or not }
      UpdateNormal(tc, txCon, nil, AIsInit);
    end;
    { setTextConfig after the content, as updateElNormal runs it }
    if txCfg <> nil then
    begin
      if AEl.TextConfig = nil then AEl.TextConfig := TJSONObject.Create;
      TyGfxExtend(AEl.TextConfig, txCfg);
    end;
  finally
    ownCfg.Free;
    ownCon.Free;
  end;
end;

{ updateElOnState for each state: the style of the state replaced (false or
  nothing: none) -- and retrieveStyleOptionOnState's styleEmphasis }
procedure TTyCustomView.UpdateStates(AEl: TTyGfxEl; AOpt: TJSONObject);
var
  info: TTyCustomElInfo;
  i: Integer;
  so: TJSONObject;
  st: TJSONData;
begin
  info := InfoOf(AEl);
  if (info = nil) or AEl.IsGroup then Exit;
  for i := 0 to 2 do
  begin
    so := ObjOf(AOpt, cStates[i]);
    st := nil;
    if so <> nil then st := so.Find('style');
    if JNull(st) and (i = 0) then st := AOpt.Find('styleEmphasis');
    FreeAndNil(info.StateStyle[i]);
    if st is TJSONObject then info.StateStyle[i] := TJSONObject(st.Clone);
  end;
end;

{ updateZ: z and zlevel always the series', z2 where written, and each
  state's z2 where written }
procedure TTyCustomView.UpdateZ(AEl: TTyGfxEl; AOpt: TJSONObject);
var
  d: TJSONData;
  info: TTyCustomElInfo;
  so: TJSONObject;
  i: Integer;
  v: Double;
begin
  if AEl.IsGroup then Exit;
  AEl.Z := FZ;
  AEl.ZLevel := FZLevel;
  d := AOpt.Find('z2');
  if not JNull(d) then
  begin
    v := JsNum(d);
    if IsNan(v) then v := 0;
    AEl.Z2 := v;
  end;
  info := InfoOf(AEl);
  if info = nil then Exit;
  for i := 0 to 2 do
  begin
    so := ObjOf(AOpt, cStates[i]);
    if so = nil then Continue;
    d := so.Find('z2');
    if JNull(d) then Continue;
    v := JsNum(d);
    if IsNan(v) then v := 0;
    info.StateZ2[i] := v;
  end;
end;

{ mergeChildren: by name (DataDiffer over the names), not at all
  ($mergeChildren false: every child replaced), or by index -- a null new
  child ignores the old one at its place, a shorter list removes the rest }
procedure TTyCustomView.MergeChildren(AEl: TTyGfxEl; AOpt: TJSONObject);
var
  kids: TJSONArray;
  n, i, idx: Integer;
  mc, d: TJSONData;
  byName, notMerge, has: Boolean;
  oldKids: TTyGfxElArray;
  oldKeys, newKeys: TTyStringArray;
  cmds: TTyDataDiffCmdArray;
  child: TTyGfxEl;
  info: TTyCustomElInfo;
  opt: TJSONObject;
begin
  kids := nil;
  if AOpt.Find('children') is TJSONArray then kids := TJSONArray(AOpt.Find('children'));
  if kids <> nil then n := kids.Count else n := 0;
  mc := AOpt.Find('$mergeChildren');
  byName := ((mc <> nil) and (mc.JSONType = jtString) and (mc.AsString = 'byName'))
    or Truthy(AOpt.Find('diffChildrenByName'));
  notMerge := (mc <> nil) and (mc.JSONType = jtBoolean) and not mc.AsBoolean;
  if (n = 0) and not byName and not notMerge then Exit;
  if byName then
  begin
    oldKids := Copy(AEl.Children);
    SetLength(oldKeys, Length(oldKids));
    for i := 0 to High(oldKids) do
    begin
      info := InfoOf(oldKids[i]);
      if (info <> nil) and info.HasName then oldKeys[i] := oldKids[i].Name
      else oldKeys[i] := 'e'#0#0 + IntToStr(i);
    end;
    SetLength(newKeys, n);
    for i := 0 to n - 1 do
    begin
      newKeys[i] := '';
      has := False;
      d := kids.Items[i];
      if d is TJSONObject then newKeys[i] := TyGfxIdOf(TJSONObject(d).Find('name'), has);
      if not has then newKeys[i] := 'e'#0#0 + IntToStr(i);
    end;
    cmds := TyDataDiff(oldKeys, newKeys);
    for i := 0 to High(cmds) do
    begin
      if FAbort then Exit;
      case cmds[i].Kind of
        ddkAdd, ddkUpdate:
          begin
            if not (kids.Items[cmds[i].NewIdx] is TJSONObject) then Continue;
            if cmds[i].Kind = ddkUpdate then child := oldKids[cmds[i].OldIdx]
            else child := nil;
            DoCreateOrUpdate(child, TJSONObject(kids.Items[cmds[i].NewIdx]), AEl);
          end;
        ddkRemove:
          { processRemove: applyLeaveTransition }
          Leave(oldKids[cmds[i].OldIdx]);
      end;
    end;
    Exit;
  end;
  if notMerge then
    while Length(AEl.Children) > 0 do Discard(AEl.Children[High(AEl.Children)]);
  idx := 0;
  while idx < n do
  begin
    if FAbort then Exit;
    d := kids.Items[idx];
    if idx <= High(AEl.Children) then child := AEl.Children[idx] else child := nil;
    if Truthy(d) then
    begin
      if d is TJSONObject then
      begin
        opt := TJSONObject(d);
        { an old child was ignored by a null: back on }
        if JNull(opt.Find('ignore')) then PutKey(opt, 'ignore', TJSONBoolean.Create(False));
        DoCreateOrUpdate(child, opt, AEl);
      end;
    end
    else if child <> nil then
      child.Ignore := True;
    Inc(idx);
  end;
  { removeChildFromGroup: applyLeaveTransition, the last first }
  for i := High(AEl.Children) downto idx do
  begin
    Leave(AEl.Children[i]);
    if FAbort then Exit;
  end;
end;

function TTyCustomView.DoCreateOrUpdate(AExists: TTyGfxEl; AOpt: TJSONObject;
  AGroup: TTyGfxEl): TTyGfxEl;
var
  replaceAt, i: Integer;
  oldEl, el: TTyGfxEl;
  d: TJSONData;
  info: TTyCustomElInfo;
  isInit: Boolean;
begin
  Result := nil;
  replaceAt := -1;
  oldEl := AExists;
  if (AExists <> nil) and NeedRecreate(AExists, AOpt) then
  begin
    { keep the place, or "merge by index" goes wrong }
    for i := 0 to High(AGroup.Children) do
      if AGroup.Children[i] = AExists then replaceAt := i;
    AExists := nil;
  end;
  { isInit: a new element (or one made again) enters }
  isInit := AExists = nil;
  el := AExists;
  if el = nil then
  begin
    el := CreateEl(AOpt);
    if el = nil then Exit;
    if oldEl <> nil then
    begin
      { copyElement }
      el.X := oldEl.X;
      el.Y := oldEl.Y;
      el.Rotation := oldEl.Rotation;
      el.ScaleX := oldEl.ScaleX;
      el.ScaleY := oldEl.ScaleY;
      el.OriginX := oldEl.OriginX;
      el.OriginY := oldEl.OriginY;
      el.SkewX := oldEl.SkewX;
      el.SkewY := oldEl.SkewY;
      el.AnchorX := oldEl.AnchorX;
      el.AnchorY := oldEl.AnchorY;
      if not el.IsGroup and not oldEl.IsGroup then
      begin
        TyGfxSetStyle(el, oldEl.Style);
        el.Z := oldEl.Z;
        el.Z2 := oldEl.Z2;
        el.ZLevel := oldEl.ZLevel;
        el.Invisible := oldEl.Invisible;
        el.Ignore := oldEl.Ignore;
        if el.StatePath and oldEl.StatePath then TyGfxSetShape(el, oldEl.Shape);
      end;
    end;
  end;
  info := InfoOf(el);
  if (info <> nil) and Truthy(AOpt.Find('tooltipDisabled')) then info.TooltipDisabled := True;
  UpdateAttachedTx(el, AOpt, isInit);
  UpdateNormal(el, AOpt, nil, isInit);
  { info: replaced only when the option says it }
  d := AOpt.Find('info');
  if (d <> nil) and (AOpt.IndexOfName('info') >= 0) then
  begin
    FreeAndNil(el.Info);
    el.Info := d.Clone;
  end;
  UpdateStates(el, AOpt);
  UpdateZ(el, AOpt);
  if StrOf(AOpt.Find('type')) = 'group' then MergeChildren(el, AOpt);
  if replaceAt >= 0 then
  begin
    { group.replaceAt: the new one in the old one's place }
    if el.Parent <> nil then TyGfxRemoveChild(el.Parent, el);
    FDetached.Remove(el);
    AGroup.Children[replaceAt] := el;
    el.Parent := AGroup;
    oldEl.Parent := nil;
    if FGone.IndexOf(oldEl) < 0 then FGone.Add(oldEl);
  end
  else
    AddTo(AGroup, el);
  Result := el;
end;

{ createOrUpdateItem: nothing returned removes the element there was }
function TTyCustomView.CreateOrUpdateItem(AExists: TTyGfxEl; AOpt: TJSONData): TTyGfxEl;
var
  opt: TJSONObject;
  info: TTyCustomElInfo;
  d: TJSONData;
begin
  Result := nil;
  if not Truthy(AOpt) or not (AOpt is TJSONObject) then
  begin
    if AExists <> nil then Discard(AExists);
    Exit;
  end;
  opt := TJSONObject(AOpt);
  Result := DoCreateOrUpdate(AExists, opt, FRoot);
  info := InfoOf(Result);
  if info = nil then Exit;
  { toggleHoverEmphasis(el, focus, blurScope, emphasisDisabled) }
  d := opt.Find('focus');
  if (d <> nil) and (d.JSONType = jtString) then info.Focus := d.AsString
  else info.Focus := '';
  d := opt.Find('blurScope');
  if (d <> nil) and (d.JSONType = jtString) then info.BlurScope := d.AsString
  else info.BlurScope := '';
  info.EmphasisDisabled := Truthy(opt.Find('emphasisDisabled'));
end;

procedure TTyCustomView.Render(const AIds: TTyStringArray;
  const ARaws: TTyIntegerArray; ACall: TTyCustomCallFn; AZ, AZLevel: Double);
var none: TTyCustomAnim;
begin
  none := Default(TTyCustomAnim);
  none.Enabled := False;
  none.Model := TyAnimNoModel;
  Render(AIds, ARaws, ACall, AZ, AZLevel, none);
end;

procedure TTyCustomView.Render(const AIds: TTyStringArray;
  const ARaws: TTyIntegerArray; ACall: TTyCustomCallFn; AZ, AZLevel: Double;
  const AAnim: TTyCustomAnim);
var
  oldIds: TTyStringArray;
  newEls: TTyGfxElArray;
  cmds: TTyDataDiffCmdArray;
  i, k: Integer;
  opt: TJSONData;
  old, el: TTyGfxEl;
  keep: Boolean;
begin
  FError := '';
  FAbort := False;
  FZ := AZ;
  FZLevel := AZLevel;
  FAnim := AAnim;
  FIdx := 0;
  if not FHasData then
  begin
    { a first render: whatever there was goes }
    while Length(FRoot.Children) > 0 do Discard(FRoot.Children[High(FRoot.Children)]);
    oldIds := nil;
    FEls := nil;
  end
  else
    oldIds := FIds;
  newEls := nil;
  SetLength(newEls, Length(AIds));
  cmds := TyDataDiff(oldIds, AIds);
  for i := 0 to High(cmds) do
  begin
    case cmds[i].Kind of
      ddkAdd, ddkUpdate:
        begin
          if cmds[i].Kind = ddkUpdate then old := FEls[cmds[i].OldIdx] else old := nil;
          FIdx := cmds[i].NewIdx;
          opt := ACall(cmds[i].NewIdx);
          try
            el := CreateOrUpdateItem(old, opt);
          finally
            opt.Free;
          end;
          newEls[cmds[i].NewIdx] := el;
        end;
      ddkRemove:
        { applyLeaveTransition }
        if (cmds[i].OldIdx <= High(FEls)) and (FEls[cmds[i].OldIdx] <> nil) then
          Leave(FEls[cmds[i].OldIdx]);
    end;
    if FAbort then Break;
  end;
  if FAbort then
  begin
    { upstream threw out of render: _data never became this data. Nothing
      the old data held can be trusted now -- the next render starts over }
    FHasData := False;
    FIds := nil;
    FRaws := nil;
    FEls := nil;
    for i := FDetached.Count - 1 downto 0 do Discard(TTyGfxEl(FDetached[i]));
    Exit;
  end;
  FIds := Copy(AIds);
  FRaws := Copy(ARaws);
  FEls := newEls;
  FHasData := True;
  AnimateLabels;
  { a detached element no item holds any more is gone }
  for i := FDetached.Count - 1 downto 0 do
  begin
    keep := False;
    for k := 0 to High(FEls) do
      if FEls[k] = TTyGfxEl(FDetached[i]) then keep := True;
    if not keep then Discard(TTyGfxEl(FDetached[i]));
  end;
end;

{ LabelManager.processLabelsOverall's _animateLabels over this view's group
  (a series that animates): every element not ignored -- an ignored one
  hides its subtree -- whose textContent is shown and not leaving, and
  which the manager has not laid out yet, fades that text in from 0 to its
  opacity (initProps: the series' enter timing at the item's data index).
  A text laid out before keeps its opacity; its x / y / rotation would move
  from the old layout, which a custom textContent never changes here.
  [Milestone D5-D8: a custom series' text was never faded in.] }
procedure TTyCustomView.AnimateLabels;

  procedure Walk(AEl: TTyGfxEl; AIdx: Integer);
  var
    tc: TTyGfxEl;
    k: Integer;
    timing: TTyAnimTiming;
    cfg: TTyAnimCfg;
    op: TTyAnimValue;
    props: TTyAnimProps;
  begin
    if AEl.Ignore then Exit;
    tc := AEl.TextContent;
    if (tc <> nil) and not tc.Ignore and not tc.Invisible and not AEl.Leaving then
    begin
      if not tc.LabelLaidOut then
      begin
        op := tc.StyleValue('opacity');
        if op.Kind <> avkNumber then op := TyAnimNum(1);
        props := nil;
        TyAnimPropPut(props, 'style.opacity', op);
        if TyAnimGetConfig(atEnter, FAnim.Model, TyAnimCallAt(AIdx), timing)
          and (timing.Duration > 0) and (tc.Animation <> nil) then
        begin
          tc.SetAnimProp('style.opacity', TyAnimNum(0));
          cfg := Default(TTyAnimCfg);
          cfg.Duration := timing.Duration;
          cfg.HasDuration := True;
          if IsNan(timing.Delay) then cfg.Delay := 0 else cfg.Delay := timing.Delay;
          cfg.Easing := timing.Easing;
          cfg.SetToFinal := True;
          cfg.Scope := 'enter';
          tc.AnimateTo(props, cfg);
        end
        else
        begin
          { no duration: stopAnimation, then the props at once }
          tc.StopAnimation;
          tc.Attr(props);
        end;
      end;
      tc.LabelLaidOut := True;
    end;
    for k := 0 to High(AEl.Children) do Walk(AEl.Children[k], AIdx);
  end;

var i: Integer;
begin
  if not FAnim.Enabled then Exit;
  for i := 0 to High(FRoot.Children) do
    Walk(FRoot.Children[i], InsideOfRoot(FRoot.Children[i]));
end;

procedure TTyCustomView.Snap;

  procedure Walk(AEl: TTyGfxEl);
  var k: Integer;
  begin
    AEl.StopAnimation('', True);
    if AEl.TextContent <> nil then AEl.TextContent.StopAnimation('', True);
    for k := 0 to High(AEl.Children) do Walk(AEl.Children[k]);
  end;

var i: Integer;
begin
  Walk(FRoot);
  for i := 0 to FDetached.Count - 1 do Walk(TTyGfxEl(FDetached[i]));
end;

procedure TTyCustomView.RemoveAll;
var el: TTyGfxEl;
begin
  while Length(FRoot.Children) > 0 do
  begin
    el := FRoot.Children[High(FRoot.Children)];
    TyGfxRemoveChild(FRoot, el);
    if FDetached.IndexOf(el) < 0 then FDetached.Add(el);
  end;
end;

function TTyCustomView.ElOf(AIndexInside: Integer): TTyGfxEl;
begin
  Result := nil;
  if (AIndexInside >= 0) and (AIndexInside <= High(FEls)) then Result := FEls[AIndexInside];
end;

function TTyCustomView.InsideOfRoot(AEl: TTyGfxEl): Integer;
var i: Integer;
begin
  Result := -1;
  if (AEl = nil) or (AEl.Parent <> FRoot) then Exit;
  for i := 0 to High(FEls) do
    if FEls[i] = AEl then Exit(i);
end;

function TTyCustomView.ElOfRaw(ARaw: Integer): TTyGfxEl;
var i: Integer;
begin
  Result := nil;
  if ARaw < 0 then Exit;
  for i := 0 to Min(High(FRaws), High(FEls)) do
    if FRaws[i] = ARaw then Exit(FEls[i]);
end;

function TTyCustomView.RawOfRoot(AEl: TTyGfxEl): Integer;
var i: Integer;
begin
  Result := -1;
  i := InsideOfRoot(AEl);
  if (i >= 0) and (i <= High(FRaws)) then Result := FRaws[i];
end;

finalization
  FreeAndNil(GRenderItems);
end.
