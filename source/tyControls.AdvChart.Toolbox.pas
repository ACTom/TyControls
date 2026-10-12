unit tyControls.AdvChart.Toolbox;
{$mode objfpc}{$H+}
{ The toolbox, the arithmetic and the text: what ECharts 6.1's
  component/toolbox does between the option and the pixels, and between a
  click and the option it merges -- held to the real dist by
  tools/advchart-oracle/toolbox.js. [Batch 125, C16]

  THE MODEL (ToolboxModel.ts, featureManager.ts, ToolboxView.ts): the
  features in the order the option writes them; a built-in one merged with
  its defaults (zrender's merge, not overwriting), a custom one -- a name
  starting with `my` -- as written; `show` read through the toolbox; each
  icon fitted into the item box keeping its proportions (graphic.createIcon,
  'center'); its style from the feature's iconStyle over the toolbox's; the
  emphasis style likewise, as a state over it.

  THE LAYOUT (ToolboxView.render): every icon's rect -- the path's own rect
  grown by the stroke, at least five across with no fill -- through
  layout.box in the view rect getLayoutRect gives the padding, then the
  group placed by positionElement from where it stood (a re-render starts
  from the old position, so the arithmetic is (old + (target - (rect +
  old)))), then the background around the group's rect, then the titles'
  adjustment for a horizontal toolbox: a title that would leave the canvas
  at the bottom goes on top, one past the right edge is right-aligned at
  '100%', one past the left edge left-aligned at 0 -- measured in the
  default font whatever the title's own is.

  THE HOVER (the icon's mouseover): the text position from the emphasis
  style's textPosition, else below (beside, for a vertical toolbox) unless
  the toolbox sits at that edge; the colour textFill, else the emphasis
  fill, else its stroke. The adjustment lives in the emphasis state, so it
  only applies when the hover enters that state -- an icon already
  emphasised by its status keeps the plain position.

  dataView's text (DataView.ts getContentFromModel) and its parse-back
  (parseContents, tryMergeDataOption), magicType's merge (MagicType.ts),
  saveAsImage's export options, the select dataZoom's history
  (feature/DataZoom.ts, dataZoom/history.ts) are here too; the
  select brush itself is tyControls.AdvChart.Brush's controller
  [Batch 127].

  PURE: options and numbers in, records and JSON out. The chart owns the
  pointer, the stores, the states and the dialogs. }
interface
uses SysUtils, Classes, Math, fpjson, jsonparser,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Layout, tyControls.AdvChart.ZrPath;

const
  { the built-in icons (the features' getDefaultOption) }
  TyTbIconSaveAsImage = 'M4.7,22.9L29.3,45.5L54.7,23.4M4.6,43.6L4.6,58L53.8,58L53.8,43.6M29.2,45.1L29.2,0';
  TyTbIconRestore = 'M3.8,33.4 M47,18.9h9.8V8.7 M56.3,20.1 C52.1,9,40.5,0.6,26.8,2.1C12.6,3.7,1.6,16.2,2.1,30.6 M13,41.1H3.1v10.2 M3.7,39.9c4.2,11.1,15.8,19.5,29.5,18 c14.2-1.6,25.2-14.1,24.7-28.5';
  TyTbIconDataView = 'M17.5,17.3H33 M17.5,17.3H33 M45.4,29.5h-28 M11.5,2v56H51V14.8L38.4,2H11.5z M38.4,2.2v12.7H51 M45.4,41.7h-28';
  TyTbIconZoom = 'M0,13.5h26.9 M13.5,26.9V0 M32.1,13.5H58V58H13.5 V32.1';
  TyTbIconBack = 'M22,1.4L9.9,13.5l12.3,12.3 M10.3,13.5H54.9v44.6 H10.3v-26';
  TyTbIconLine = 'M4.1,28.9h7.1l9.3-22l7.4,38l9.7-19.7l3,12.8h14.9M4.1,58h51.4';
  TyTbIconBar = 'M6.7,22.9h10V48h-10V22.9zM24.9,13h10v35h-10V13zM43.2,2h10v46h-10V2zM3.1,58h53.7';
  TyTbIconStack = 'M8.2,38.4l-8.4,4.1l30.6,15.3L60,42.5l-8.1-4.1l-21.5,11L8.2,38.4z M51.9,30l-8.1,4.2l-13.4,6.9l-13.9-6.9L8.2,30l-8.4,4.2l8.4,4.2l22.2,11l21.5-11l8.1-4.2L51.9,30z M51.9,21.7l-8.1,4.2L35.7,30l-5.3,2.8L24.9,30l-8.4-4.1l-8.3-4.2l-8.4,4.2L8.2,30l8.3,4.2l13.9,6.9l13.4-6.9l8.1-4.2l8.1-4.1L51.9,21.7zM30.4,2.2L-0.2,17.5l8.4,4.1l8.3,4.2l8.4,4.2l5.5,2.7l5.3-2.7l8.1-4.2l8.1-4.2l8.1-4.1L30.4,2.2z';
  { the brush feature's icons (feature/Brush.ts) [Batch 127] }
  TyTbIconBrushRect = 'M7.3,34.7 M0.4,10V-0.2h9.8 M89.6,10V-0.2h-9.8 M0.4,60v10.2h9.8 M89.6,60v10.2h-9.8 M12.3,22.4V10.5h13.1 M33.6,10.5h7.8 M49.1,10.5h7.8 M77.5,22.4V10.5h-13 M12.3,31.1v8.2 M77.7,31.1v8.2 M12.3,47.6v11.9h13.1 M33.6,59.5h7.6 M49.1,59.5 h7.7 M77.5,47.6v11.9h-13';
  TyTbIconBrushPolygon = 'M55.2,34.9c1.7,0,3.1,1.4,3.1,3.1s-1.4,3.1-3.1,3.1 s-3.1-1.4-3.1-3.1S53.5,34.9,55.2,34.9z M50.4,51c1.7,0,3.1,1.4,3.1,3.1c0,1.7-1.4,3.1-3.1,3.1c-1.7,0-3.1-1.4-3.1-3.1 C47.3,52.4,48.7,51,50.4,51z M55.6,37.1l1.5-7.8 M60.1,13.5l1.6-8.7l-7.8,4 M59,19l-1,5.3 M24,16.1l6.4,4.9l6.4-3.3 M48.5,11.6 l-5.9,3.1 M19.1,12.8L9.7,5.1l1.1,7.7 M13.4,29.8l1,7.3l6.6,1.6 M11.6,18.4l1,6.1 M32.8,41.9 M26.6,40.4 M27.3,40.2l6.1,1.6 M49.9,52.1l-5.6-7.6l-4.9-1.2';
  TyTbIconBrushLineX = 'M15.2,30 M19.7,15.6V1.9H29 M34.8,1.9H40.4 M55.3,15.6V1.9H45.9 M19.7,44.4V58.1H29 M34.8,58.1H40.4 M55.3,44.4 V58.1H45.9 M12.5,20.3l-9.4,9.6l9.6,9.8 M3.1,29.9h16.5 M62.5,20.3l9.4,9.6L62.3,39.7 M71.9,29.9H55.4';
  TyTbIconBrushLineY = 'M38.8,7.7 M52.7,12h13.2v9 M65.9,26.6V32 M52.7,46.3h13.2v-9 M24.9,12H11.8v9 M11.8,26.6V32 M24.9,46.3H11.8v-9 M48.2,5.1l-9.3-9l-9.4,9.2 M38.9-3.9V12 M48.2,53.3l-9.3,9l-9.4-9.2 M38.9,62.3V46.4';
  TyTbIconBrushKeep = 'M4,10.5V1h10.3 M20.7,1h6.1 M33,1h6.1 M55.4,10.5V1H45.2 M4,17.3v6.6 M55.6,17.3v6.6 M4,30.5V40h10.3 M20.7,40 h6.1 M33,40h6.1 M55.4,30.5V40H45.2 M21,18.9h62.9v48.6H21V18.9z';
  TyTbIconBrushClear = 'M22,14.7l30.9,31 M52.9,14.7L22,45.7 M4.7,16.8V4.2h13.1 M26,4.2h7.8 M41.6,4.2h7.8 M70.3,16.8V4.2H57.2 M4.7,25.9v8.6 M70.3,25.9v8.6 M4.7,43.2v12.6h13.1 M26,55.8h7.8 M41.6,55.8h7.8 M70.3,43.2v12.6H57.2';
  { MagicType's INNER_STACK_KEYWORD }
  TyTbMagicStack = '__ec_magicType_stack__';
  { DataView's BLOCK_SPLITER: new Array(60).join('-') }
  TyDataViewBlock = '-----------------------------------------------------------';

type
  { The locale's words (the port's resourcestrings). }
  TTyTbTitles = record
    SaveAsImage, Restore, DataView, Zoom, Back, Line, Bar, Stack, Tiled: string;
    DataViewClose, DataViewRefresh: string;
    { the brush feature's [Batch 127] }
    BrushRect, BrushPolygon, BrushLineX, BrushLineY, BrushKeep, BrushClear: string;
  end;

  { A colour as the option writes it: tbcTheme -- nothing written, the
    skin's; tbcNone -- `none` (no paint); tbcText -- a value to parse. }
  TTyTbColourKind = (tbcTheme, tbcNone, tbcText);
  TTyTbColour = record
    Kind: TTyTbColourKind;
    Text: string;
  end;

  { An ItemStyle as getItemStyle reads it (the keys the toolbox draws by). }
  TTyTbItemStyle = record
    HasStroke: Boolean;
    Stroke: TTyTbColour;
    HasFill: Boolean;
    Fill: TTyTbColour;
    HasLineWidth: Boolean;
    LineWidth: Double;
    HasOpacity: Boolean;
    Opacity: Double;
  end;

  { The render-time adjustment of a horizontal toolbox's title. }
  TTyTbAdjust = (tajNone, tajTop, tajRight, tajLeft);

  TTyTbIcon = record
    Feature, Name: string;
    HasTitle: Boolean;
    Title: string;
    IconText: string;
    IsImage: Boolean;
    { a feature named `my...`: its onclick as written ('' none) }
    IsUser: Boolean;
    OnClick: string;
    Path: TTyZrPath;
    DataLen: Integer;
    PathRect: TTyXYWH;
    { the normal style (every key resolved), the emphasis state's own keys }
    Normal, Emph: TTyTbItemStyle;
    { the emphasis iconStyle's text keys }
    TextFill, TextBg: TTyTbColour;
    TextPosition: string;
    TextAlign: string;
    TextFontSize: Double;
    TextFontWeight, TextFontFamily, TextFontStyle: string;
    { iconStatus 'emphasis' when rendered }
    Status: Boolean;
    { ---- the layout ---- }
    { getBoundingRect in the state it was laid out in }
    Rect: TTyXYWH;
    X, Y: Double;
    Adjust: TTyTbAdjust;
    { the adjusted position's y (array forms) }
    AdjustY: Double;
  end;
  TTyTbIconArray = array of TTyTbIcon;

  TTyToolboxSpec = record
    Index: Integer;
    Show: Boolean;
    Vertical: Boolean;
    ItemSize, ItemGap: Double;
    ShowTitle: Boolean;
    Padding: array[0..3] of Double;
    Box: TTyRawBox;
    Background, BorderColor: TTyTbColour;
    BorderWidth: Double;
    Radius: array of Double;
    Z: Integer;
    { the hover's position when the emphasis style names none }
    DefaultTextPos: string;
    Icons: TTyTbIconArray;
  end;

  TTyToolboxLayout = record
    Valid: Boolean;
    GroupX, GroupY: Double;
    { the group's own rect (its children's union) }
    Union: TTyXYWH;
    Background: TTyXYWH;
    ViewRect: TTyXYWH;
  end;

  { A hovered title's anchor, canvas CSS px: the text's position and its
    alignment ('left' / 'center' / 'right', 'top' / 'middle' / 'bottom'). }
  TTyTbTitlePlace = record
    X, Y: Double;
    Align, VAlign: string;
  end;

{ ---- the model ---- }
function TyToolboxCount(AOption: TTyChartOption): Integer;
{ The toolbox AIndex: its features and icons, styles resolved but not laid
  out. AStatus holds the iconStatus as 'feature|icon=emphasis' lines;
  AMagicTitle the title object a magicType click wrote into the feature
  ('' none). }
function TyToolboxSpecOf(AOption: TTyChartOption; AIndex: Integer;
  const ATitles: TTyTbTitles; AStatus: TStrings;
  const AMagicTitle: string): TTyToolboxSpec;
{ The feature AName of toolbox AIndex with its defaults merged in (zrender's
  merge); nil when the toolbox or the feature is absent. The caller frees
  it. }
function TyToolboxFeatureModel(AOption: TTyChartOption; AIndex: Integer;
  const AName: string; const ATitles: TTyTbTitles): TJSONObject;
{ zrUtil.merge(target, source, overwrite) }
procedure TyTbMerge(ATarget, ASource: TJSONObject; AOverwrite: Boolean);

{ ---- the layout ---- }
{ The style an icon is drawn with: its normal style, or the emphasis state
  over it }
function TyTbStyleOf(const AIcon: TTyTbIcon; AEmphasised: Boolean): TTyTbItemStyle;
{ The rect getBoundingRect gives the icon in its normal or emphasis state }
function TyToolboxIconRect(const ASpec: TTyToolboxSpec; const AIcon: TTyTbIcon;
  AEmphasised: Boolean): TTyXYWH;
{ ToolboxView.render's layout: the icons' rects and places, the group
  (placed from APrevX, APrevY), the background and the titles' adjustment.
  AW, AH: the chart, CSS px; ATitleW / ATitleH: every icon's title in the
  default font. }
function TyToolboxLayoutOf(var ASpec: TTyToolboxSpec; AW, AH, APrevX,
  APrevY: Double; const ATitleW, ATitleH: array of Double): TTyToolboxLayout;
{ [Batch 154] the same in createBoxLayoutReference's container ARef (CSS px
  from the canvas' corner) -- a matrix cell or a calendar day; the titles'
  adjustment still reads the canvas (api.getWidth / getHeight) }
function TyToolboxLayoutOf(var ASpec: TTyToolboxSpec; AW, AH: Double;
  const ARef: TTyXYWH; APrevX, APrevY: Double;
  const ATitleW, ATitleH: array of Double): TTyToolboxLayout;
{ The title of icon AIcon under the pointer. The adjustment lives in the
  emphasis state, and what of it shows depends on when the state was
  entered: APosAdjusted -- the hover entered it (the frame after the
  mouseover), so its textConfig overrides the mouseover's position;
  AAlignAdjusted -- the element is in it at all (the text's emphasis style
  holds the adjusted align, also for an icon a render emphasised by its
  status, whose position the mouseover sets after). AEmphasised: the
  icon's rect in its emphasis style. }
function TyToolboxTitlePlace(const ASpec: TTyToolboxSpec;
  const ALayout: TTyToolboxLayout; AIcon: Integer; APosAdjusted,
  AAlignAdjusted, AEmphasised: Boolean): TTyTbTitlePlace;

{ ---- saveAsImage ---- }
{ The export options SaveAsImage.onclick asks for (type, backgroundColor --
  absent when neither the feature nor the option writes one --,
  excludeComponents, pixelRatio) and the file name it downloads as. }
function TyToolboxSaveOpts(AOption: TTyChartOption; AFeature: TJSONObject;
  out AFileName, AType: string): string;

{ ---- magicType ---- }
type
  TTyMagicSeries = record
    Index: Integer;
    SubType: string;
    { the series option as the option holds it (not owned) }
    Node: TJSONObject;
    { on a cartesian2d, with an ordinal axis (CatDim '' none) }
    Cartesian: Boolean;
    CatDim: string;
    CatIndex: Integer;
  end;
  TTyMagicSeriesArray = array of TTyMagicSeries;

{ MagicType.onclick for AType ('line' | 'bar' | 'stack'): the option it
  merges -- one series entry per series up to the last it changed, an empty
  object for those it does not touch (the port maps by position, upstream by the id it
  writes), the axes' boundaryGap -- the icon statuses it sets (into AStatus,
  'magicType|<icon>'), the type the event reports and the flipped titles
  (stack only; nil otherwise). nil when AType is no magic type. }
function TyMagicTypeOption(AFeature: TJSONObject; const AType: string;
  const ASeries: TTyMagicSeriesArray; AStatus: TStrings;
  out ACurrentType: string; out ANewTitle: TJSONObject): TJSONObject;

{ ---- dataView ---- }
type
  { the series on one category axis }
  TTyDvGroup = record
    AxisDim: string;
    AxisIndex: Integer;
    Categories: TTyStringArray;
    Names: TTyStringArray;
    { one column per series: the raw value in the value axis' dimension }
    Columns: array of TTyDoubleArray;
  end;
  TTyDvGroupArray = array of TTyDvGroup;
  { any other series: every dimension of every row }
  TTyDvList = record
    Name: string;
    RowNames: TTyStringArray;
    Rows: array of TTyDoubleArray;
  end;
  TTyDvListArray = array of TTyDvList;
  TTyDvMeta = record
    AxisDim: string;
    AxisIndex: Integer;
  end;
  TTyDvMetaArray = array of TTyDvMeta;
  { getSeriesByName(name)[0]: whether one exists, and its `data` as the
    option holds it (nil for none) }
  TTyDvFindSeries = function(const AName: string; out AData: TJSONData): Boolean of object;

{ getContentFromModel: the textarea's text }
function TyDataViewText(const AGroups: TTyDvGroupArray;
  const ALists: TTyDvListArray): string;
{ parseContents: the option the text makes; nil with AError set where
  upstream throws ('Data view format error'). }
function TyDataViewParse(const AText: string; const AMeta: TTyDvMetaArray;
  out AError: string): TJSONObject;
{ the changeDataView action: the option it merges (the series by name,
  their data merged into the items they replace; a new name a scatter) }
function TyDataViewChange(AParsed: TJSONObject; AFind: TTyDvFindSeries): TJSONObject;

{ ---- the select dataZoom's brush and history ---- }
type
  TTyTbBrushType = (tbbRect, tbbLineX, tbbLineY);
  { one dataZoom's window in a snapshot: by value (the brush) or by percent
    (the window before the first brush) }
  TTyTbZoomItem = record
    Key: string;
    IsValue: Boolean;
    A, B: Double;
  end;
  TTyTbSnapshot = array of TTyTbZoomItem;
  TTyTbHistory = array of TTyTbSnapshot;

function TyTbHistoryCount(const AHistory: TTyTbHistory): Integer;
{ history.push: an item no earlier snapshot holds gets its present window
  (APercent, by key) into the first }
procedure TyTbHistoryPush(var AHistory: TTyTbHistory; const ASnap: TTyTbSnapshot;
  const APresentKeys: TTyStringArray; const APresentA, APresentB: TTyDoubleArray);
{ history.pop }
function TyTbHistoryPop(var AHistory: TTyTbHistory): TTyTbSnapshot;

{ util/number round: +(+x).toFixed(clamp(p, 0, 20)); NaN p is +x }
function TyTbRound(AValue, APrecision: Double): Double;
{ JSON text of a value with every number as JavaScript prints it (fpjson's
  own float text is not the shortest round trip); NaN and the infinities as
  null }
function TyTbJson(AData: TJSONData): string;

implementation

uses tyControls.AdvChart.Data, tyControls.AdvChart.Scale,
     tyControls.AdvChart.DataZoom, tyControls.AdvChart.OptionMerge;

{ ==================== JavaScript's arithmetic ====================
  A degenerate icon (a path with no height, say) is NaN all the way
  through upstream -- its rect, its place, the group's rect -- so the
  arithmetic runs with the FPU's traps masked, and a comparison with NaN is
  false as JavaScript's is. }

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

{ Math.max / Math.min of two: a NaN wins }
function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JFinite(A: Double): Boolean;
begin
  Result := not IsNan(A) and not IsInfinite(A);
end;

{ BoundingRect.union, a NaN through Math.min / Math.max as JavaScript's }
function JsUnion(const A, B: TTyXYWH): TTyXYWH;
begin
  Result.X := JMin(B.X, A.X);
  Result.Y := JMin(B.Y, A.Y);
  if JFinite(A.X) and JFinite(A.W) then
    Result.W := JMax(B.X + B.W, A.X + A.W) - Result.X
  else
    Result.W := B.W;
  if JFinite(A.Y) and JFinite(A.H) then
    Result.H := JMax(B.Y + B.H, A.Y + A.H) - Result.Y
  else
    Result.H := B.H;
end;

{ ==================== JSON helpers ==================== }

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if AData is TJSONObject then Result := TJSONObject(AData) else Result := nil;
end;

{ `x != null` }
function Present(AData: TJSONData): Boolean;
begin
  Result := (AData <> nil) and (AData.JSONType <> jtNull);
end;

function JsTruthy(AData: TJSONData): Boolean;
begin
  if not Present(AData) then Exit(False);
  case AData.JSONType of
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

function IsPlainObject(AData: TJSONData): Boolean;
begin
  Result := AData is TJSONObject;
end;

procedure TyTbMerge(ATarget, ASource: TJSONObject; AOverwrite: Boolean);
var
  i, k: Integer;
  key: string;
  sp, tp: TJSONData;
begin
  if (ATarget = nil) or (ASource = nil) then Exit;
  for i := 0 to ASource.Count - 1 do
  begin
    key := ASource.Names[i];
    sp := ASource.Items[i];
    k := ATarget.IndexOfName(key);
    if k >= 0 then tp := ATarget.Items[k] else tp := nil;
    if IsPlainObject(sp) and IsPlainObject(tp) then
      TyTbMerge(TJSONObject(tp), TJSONObject(sp), AOverwrite)
    else if AOverwrite or (k < 0) then
    begin
      if k >= 0 then ATarget.Delete(k);
      ATarget.Add(key, sp.Clone);
    end;
  end;
end;

{ Model.get along a path, the parent's when this one has nothing (null) }
function PathGet(ANode: TJSONObject; const APath: array of string): TJSONData;
var
  i: Integer;
  d: TJSONData;
begin
  Result := nil;
  d := ANode;
  for i := 0 to High(APath) do
  begin
    if not (d is TJSONObject) then Exit(nil);
    d := TJSONObject(d).Find(APath[i]);
    if d = nil then Exit(nil);
  end;
  if Present(d) then Result := d;
end;

function GetChain(AFirst, ASecond: TJSONObject; const APath: array of string): TJSONData;
begin
  Result := nil;
  if AFirst <> nil then Result := PathGet(AFirst, APath);
  if (Result = nil) and (ASecond <> nil) then Result := PathGet(ASecond, APath);
end;

function StrOf(AData: TJSONData): string;
begin
  if AData = nil then Exit('');
  case AData.JSONType of
    jtString: Result := AData.AsString;
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
  else
    Result := '';
  end;
end;

function ColourOf(AData: TJSONData): TTyTbColour;
begin
  Result := Default(TTyTbColour);
  if AData = nil then Exit;
  if (AData.JSONType = jtString) and (LowerCase(AData.AsString) = 'none') then
    Result.Kind := tbcNone
  else
  begin
    Result.Kind := tbcText;
    Result.Text := StrOf(AData);
  end;
end;

function NumOf(AData: TJSONData; out AValue: Double): Boolean;
begin
  Result := False;
  AValue := NaN;
  if AData = nil then Exit;
  if AData.JSONType = jtNumber then
  begin
    AValue := AData.AsFloat;
    Exit(True);
  end;
  if AData.JSONType = jtString then
  begin
    AValue := TyJsToNumber(AData.AsString);
    Exit(True);
  end;
end;

function PathPlus(const APath: array of string; const AKey: string): TTyStringArray;
var i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(APath) + 1);
  for i := 0 to High(APath) do Result[i] := APath[i];
  Result[High(Result)] := AKey;
end;

{ getItemStyle over a chain of iconStyle models }
function ItemStyleOf(AFirst, ASecond: TJSONObject; const APath: array of string): TTyTbItemStyle;
var d: TJSONData;
begin
  Result := Default(TTyTbItemStyle);
  d := GetChain(AFirst, ASecond, PathPlus(APath, 'borderColor'));
  if d <> nil then
  begin
    Result.HasStroke := True;
    Result.Stroke := ColourOf(d);
  end;
  d := GetChain(AFirst, ASecond, PathPlus(APath, 'color'));
  if d <> nil then
  begin
    Result.HasFill := True;
    Result.Fill := ColourOf(d);
  end;
  d := GetChain(AFirst, ASecond, PathPlus(APath, 'borderWidth'));
  if d <> nil then Result.HasLineWidth := NumOf(d, Result.LineWidth);
  d := GetChain(AFirst, ASecond, PathPlus(APath, 'opacity'));
  if d <> nil then Result.HasOpacity := NumOf(d, Result.Opacity);
end;

{ ==================== the model ==================== }

function TyToolboxCount(AOption: TTyChartOption): Integer;
begin
  if AOption = nil then Exit(0);
  Result := AOption.ComponentCount('toolbox');
end;

function DefaultsOf(const AName: string; const ATitles: TTyTbTitles): TJSONObject;
var o: TJSONObject;
begin
  Result := nil;
  if AName = 'saveAsImage' then
  begin
    Result := TJSONObject.Create;
    Result.Add('show', True);
    Result.Add('icon', TyTbIconSaveAsImage);
    Result.Add('title', ATitles.SaveAsImage);
    Result.Add('type', 'png');
    Result.Add('name', '');
    Result.Add('excludeComponents', TJSONArray.Create(['toolbox']));
  end
  else if AName = 'restore' then
  begin
    Result := TJSONObject.Create;
    Result.Add('show', True);
    Result.Add('icon', TyTbIconRestore);
    Result.Add('title', ATitles.Restore);
  end
  else if AName = 'dataView' then
  begin
    Result := TJSONObject.Create;
    Result.Add('show', True);
    Result.Add('readOnly', False);
    Result.Add('optionToContent', TJSONNull.Create);
    Result.Add('contentToOption', TJSONNull.Create);
    Result.Add('icon', TyTbIconDataView);
    Result.Add('title', ATitles.DataView);
    Result.Add('lang', TJSONArray.Create([ATitles.DataView, ATitles.DataViewClose,
      ATitles.DataViewRefresh]));
  end
  else if AName = 'dataZoom' then
  begin
    Result := TJSONObject.Create;
    Result.Add('show', True);
    Result.Add('filterMode', 'filter');
    o := TJSONObject.Create;
    o.Add('zoom', TyTbIconZoom);
    o.Add('back', TyTbIconBack);
    Result.Add('icon', o);
    o := TJSONObject.Create;
    o.Add('zoom', ATitles.Zoom);
    o.Add('back', ATitles.Back);
    Result.Add('title', o);
  end
  else if AName = 'magicType' then
  begin
    Result := TJSONObject.Create;
    Result.Add('show', True);
    Result.Add('type', TJSONArray.Create);
    o := TJSONObject.Create;
    o.Add('line', TyTbIconLine);
    o.Add('bar', TyTbIconBar);
    o.Add('stack', TyTbIconStack);
    Result.Add('icon', o);
    o := TJSONObject.Create;
    o.Add('line', ATitles.Line);
    o.Add('bar', ATitles.Bar);
    o.Add('stack', ATitles.Stack);
    o.Add('tiled', ATitles.Tiled);
    Result.Add('title', o);
    Result.Add('option', TJSONObject.Create);
    Result.Add('seriesIndex', TJSONObject.Create);
  end
  else if AName = 'brush' then
  begin
    { BrushFeature.getDefaultOption [Batch 127] }
    Result := TJSONObject.Create;
    Result.Add('show', True);
    Result.Add('type', TJSONArray.Create(['rect', 'polygon', 'lineX', 'lineY', 'keep', 'clear']));
    o := TJSONObject.Create;
    o.Add('rect', TyTbIconBrushRect);
    o.Add('polygon', TyTbIconBrushPolygon);
    o.Add('lineX', TyTbIconBrushLineX);
    o.Add('lineY', TyTbIconBrushLineY);
    o.Add('keep', TyTbIconBrushKeep);
    o.Add('clear', TyTbIconBrushClear);
    Result.Add('icon', o);
    o := TJSONObject.Create;
    o.Add('rect', ATitles.BrushRect);
    o.Add('polygon', ATitles.BrushPolygon);
    o.Add('lineX', ATitles.BrushLineX);
    o.Add('lineY', ATitles.BrushLineY);
    o.Add('keep', ATitles.BrushKeep);
    o.Add('clear', ATitles.BrushClear);
    Result.Add('title', o);
  end;
end;

function IsUserFeature(const AName: string): Boolean;
begin
  Result := Copy(AName, 1, 2) = 'my';
end;

function TyToolboxFeatureModel(AOption: TTyChartOption; AIndex: Integer;
  const AName: string; const ATitles: TTyTbTitles): TJSONObject;
var
  tb, feat: TJSONObject;
  d: TJSONData;
  defs: TJSONObject;
begin
  Result := nil;
  if AOption = nil then Exit;
  tb := ObjOf(AOption.ComponentAt('toolbox', AIndex));
  if tb = nil then Exit;
  feat := ObjOf(tb.Find('feature'));
  if feat = nil then Exit;
  d := feat.Find(AName);
  if d is TJSONObject then Result := TJSONObject(d.Clone)
  else if Present(d) then Result := TJSONObject.Create
  else Exit;
  if not IsUserFeature(AName) then
  begin
    defs := DefaultsOf(AName, ATitles);
    try
      TyTbMerge(Result, defs, False);
    finally
      defs.Free;
    end;
  end;
end;

function TyToolboxSpecOf(AOption: TTyChartOption; AIndex: Integer;
  const ATitles: TTyTbTitles; AStatus: TStrings;
  const AMagicTitle: string): TTyToolboxSpec;
var
  tb, feats, fm, iconMap, titleMap: TJSONObject;
  d, t: TJSONData;
  i, k, n, j: Integer;
  name, iconName, iconStr: string;
  icon: TTyTbIcon;
  defBox: TTyRawBox;
  v: Double;
  box: TTyXYWH;
  arr: TJSONArray;
  names, strs: TTyStringArray;
  fpm: TFPUExceptionMask;

  procedure AddIconName(const AIcon, AStr: string);
  begin
    SetLength(names, Length(names) + 1);
    names[High(names)] := AIcon;
    SetLength(strs, Length(strs) + 1);
    strs[High(strs)] := AStr;
  end;

begin
  Result := Default(TTyToolboxSpec);
  Result.Index := AIndex;
  Result.ItemSize := 15;
  Result.ItemGap := 10;
  Result.ShowTitle := True;
  for k := 0 to 3 do Result.Padding[k] := 15;
  Result.Z := 6;
  if AOption = nil then Exit;
  tb := ObjOf(AOption.ComponentAt('toolbox', AIndex));
  if tb = nil then Exit;
  Result.Show := True;
  d := tb.Find('show');
  if Present(d) then Result.Show := JsTruthy(d);
  d := tb.Find('orient');
  Result.Vertical := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'vertical');
  { `+get('itemSize')` }
  d := tb.Find('itemSize');
  if Present(d) and NumOf(d, v) then Result.ItemSize := v;
  d := tb.Find('itemGap');
  if Present(d) and NumOf(d, v) then Result.ItemGap := v;
  d := tb.Find('showTitle');
  if Present(d) then Result.ShowTitle := JsTruthy(d);
  { normalizeCssArray(padding) }
  d := tb.Find('padding');
  if d is TJSONArray then
  begin
    arr := TJSONArray(d);
    if arr.Count = 1 then
      for k := 0 to 3 do NumOf(arr.Items[0], Result.Padding[k])
    else if arr.Count = 2 then
    begin
      NumOf(arr.Items[0], Result.Padding[0]);
      NumOf(arr.Items[1], Result.Padding[1]);
      Result.Padding[2] := Result.Padding[0];
      Result.Padding[3] := Result.Padding[1];
    end
    else if arr.Count = 3 then
    begin
      NumOf(arr.Items[0], Result.Padding[0]);
      NumOf(arr.Items[1], Result.Padding[1]);
      NumOf(arr.Items[2], Result.Padding[2]);
      Result.Padding[3] := Result.Padding[1];
    end
    else if arr.Count >= 4 then
      for k := 0 to 3 do NumOf(arr.Items[k], Result.Padding[k]);
  end
  else if Present(d) and NumOf(d, v) then
    for k := 0 to 3 do Result.Padding[k] := v;
  { the box: left 'right', top 'top', mergeLayoutParam with ignoreSize }
  defBox := Default(TTyRawBox);
  defBox.Left := TyBoxRawStr('right');
  defBox.Top := TyBoxRawStr('top');
  Result.Box := TyMergeBoxIgnoreSize(tb, defBox);
  { the hover's default text position: by the model's own keys }
  if Result.Vertical then
  begin
    if (Result.Box.Right.Kind in [brAbsent, brNull])
      and not ((Result.Box.Left.Kind = brString) and (Result.Box.Left.Str = 'right')) then
      Result.DefaultTextPos := 'right'
    else
      Result.DefaultTextPos := 'left';
  end
  else if (Result.Box.Bottom.Kind in [brAbsent, brNull])
    and not ((Result.Box.Top.Kind = brString) and (Result.Box.Top.Str = 'bottom')) then
    Result.DefaultTextPos := 'bottom'
  else
    Result.DefaultTextPos := 'top';
  { the background }
  d := tb.Find('backgroundColor');
  if Present(d) then Result.Background := ColourOf(d)
  else
  begin
    Result.Background.Kind := tbcText;
    Result.Background.Text := 'transparent';
  end;
  d := tb.Find('borderColor');
  if Present(d) then Result.BorderColor := ColourOf(d);
  d := tb.Find('borderWidth');
  if Present(d) then NumOf(d, Result.BorderWidth) else Result.BorderWidth := 0;
  if IsNan(Result.BorderWidth) then Result.BorderWidth := 0;
  d := tb.Find('borderRadius');
  if d is TJSONArray then
  begin
    SetLength(Result.Radius, TJSONArray(d).Count);
    for k := 0 to TJSONArray(d).Count - 1 do NumOf(TJSONArray(d).Items[k], Result.Radius[k]);
  end
  else if Present(d) and NumOf(d, v) then
  begin
    SetLength(Result.Radius, 1);
    Result.Radius[0] := v;
  end;
  d := tb.Find('z');
  if Present(d) and NumOf(d, v) and not IsNan(v) then Result.Z := Round(v);
  if not Result.Show then Exit;
  feats := ObjOf(tb.Find('feature'));
  if feats = nil then Exit;
  n := 0;
  for i := 0 to feats.Count - 1 do
  begin
    name := feats.Names[i];
    if not IsUserFeature(name) and (name <> 'saveAsImage') and (name <> 'restore')
      and (name <> 'dataView') and (name <> 'dataZoom') and (name <> 'magicType')
      and (name <> 'brush') then
      Continue;
    fm := TyToolboxFeatureModel(AOption, AIndex, name, ATitles);
    if fm = nil then Continue;
    try
      { the feature's show, the toolbox's (true here) when it has none }
      d := fm.Find('show');
      if Present(d) and not JsTruthy(d) then Continue;
      { magicType's title, as a click rewrote it }
      if (name = 'magicType') and (AMagicTitle <> '') then
      begin
        t := GetJSON(AMagicTitle);
        if fm.IndexOfName('title') >= 0 then fm.Delete('title');
        fm.Add('title', t);
      end;
      names := nil;
      strs := nil;
      if (name = 'magicType') or (name = 'brush') then
      begin
        { getIcons: every listed type the icon map has (the brush feature's
          the same, [Batch 127]) }
        iconMap := ObjOf(fm.Find('icon'));
        d := fm.Find('type');
        if (d is TJSONArray) and (iconMap <> nil) then
          for k := 0 to TJSONArray(d).Count - 1 do
          begin
            iconName := StrOf(TJSONArray(d).Items[k]);
            t := iconMap.Find(iconName);
            if JsTruthy(t) then AddIconName(iconName, StrOf(t));
          end;
      end
      else
      begin
        d := fm.Find('icon');
        if (d <> nil) and (d.JSONType = jtString) then AddIconName(name, d.AsString)
        else if d is TJSONObject then
          for k := 0 to TJSONObject(d).Count - 1 do
            AddIconName(TJSONObject(d).Names[k], StrOf(TJSONObject(d).Items[k]));
      end;
      d := fm.Find('title');
      titleMap := nil;
      if d is TJSONObject then titleMap := TJSONObject(d);
      for j := 0 to High(names) do
      begin
        iconStr := strs[j];
        { createIcon of nothing is no element (upstream throws on it) }
        if iconStr = '' then Continue;
        icon := Default(TTyTbIcon);
        icon.Feature := name;
        icon.Name := names[j];
        icon.IconText := iconStr;
        icon.IsUser := IsUserFeature(name);
        if icon.IsUser then icon.OnClick := StrOf(fm.Find('onclick'));
        if (d <> nil) and (d.JSONType = jtString) then
        begin
          if names[j] = name then
          begin
            icon.HasTitle := True;
            icon.Title := d.AsString;
          end;
        end
        else if titleMap <> nil then
        begin
          t := titleMap.Find(names[j]);
          if Present(t) then
          begin
            icon.HasTitle := True;
            icon.Title := StrOf(t);
          end;
        end;
        icon.IsImage := Copy(iconStr, 1, 8) = 'image://';
        if not icon.IsImage then
        begin
          box.X := -Result.ItemSize / 2;
          box.Y := -Result.ItemSize / 2;
          box.W := Result.ItemSize;
          box.H := Result.ItemSize;
          fpm := MaskFP;
          try
            icon.Path := TyZrMakePathCenter(StringReplace(iconStr, 'path://', '', []), box);
            icon.DataLen := TyZrDataLength(icon.Path);
            icon.PathRect := TyZrBBox(icon.Path);
          finally
            UnmaskFP(fpm);
          end;
        end;
        { the styles: the feature's iconStyle over the toolbox's }
        icon.Normal := ItemStyleOf(fm, tb, ['iconStyle']);
        icon.Emph := ItemStyleOf(fm, tb, ['emphasis', 'iconStyle']);
        { the toolbox's defaults: a themed rim, no fill }
        if not icon.Normal.HasStroke then
        begin
          icon.Normal.HasStroke := True;
          icon.Normal.Stroke.Kind := tbcTheme;
        end;
        if not icon.Normal.HasFill then
        begin
          icon.Normal.HasFill := True;
          icon.Normal.Fill.Kind := tbcNone;
        end;
        if not icon.Normal.HasLineWidth then
        begin
          icon.Normal.HasLineWidth := True;
          icon.Normal.LineWidth := 1;
        end;
        if not icon.Normal.HasOpacity then
        begin
          icon.Normal.HasOpacity := True;
          icon.Normal.Opacity := 1;
        end;
        if not icon.Emph.HasStroke then
        begin
          icon.Emph.HasStroke := True;
          icon.Emph.Stroke.Kind := tbcTheme;
        end;
        t := GetChain(fm, tb, ['emphasis', 'iconStyle', 'textFill']);
        if t <> nil then icon.TextFill := ColourOf(t);
        t := GetChain(fm, tb, ['emphasis', 'iconStyle', 'textBackgroundColor']);
        if t <> nil then icon.TextBg := ColourOf(t);
        t := GetChain(fm, tb, ['emphasis', 'iconStyle', 'textPosition']);
        if (t <> nil) and JsTruthy(t) then icon.TextPosition := StrOf(t);
        t := GetChain(fm, tb, ['emphasis', 'iconStyle', 'textAlign']);
        if t <> nil then icon.TextAlign := StrOf(t);
        t := GetChain(fm, tb, ['emphasis', 'iconStyle', 'textFontSize']);
        if t <> nil then NumOf(t, icon.TextFontSize);
        if IsNan(icon.TextFontSize) then icon.TextFontSize := 0;
        t := GetChain(fm, tb, ['emphasis', 'iconStyle', 'textFontWeight']);
        if t <> nil then icon.TextFontWeight := StrOf(t);
        t := GetChain(fm, tb, ['emphasis', 'iconStyle', 'textFontFamily']);
        if t <> nil then icon.TextFontFamily := StrOf(t);
        t := GetChain(fm, tb, ['emphasis', 'iconStyle', 'textFontStyle']);
        if t <> nil then icon.TextFontStyle := StrOf(t);
        if AStatus <> nil then
          icon.Status := AStatus.Values[name + '|' + icon.Name] = 'emphasis';
        SetLength(Result.Icons, n + 1);
        Result.Icons[n] := icon;
        Inc(n);
      end;
    finally
      fm.Free;
    end;
  end;
end;

{ ==================== the layout ==================== }

function StyleHasStroke(const S: TTyTbItemStyle): Boolean;
begin
  Result := S.HasStroke and (S.Stroke.Kind <> tbcNone)
    and (S.LineWidth > 0);
end;

function StyleHasFill(const S: TTyTbItemStyle): Boolean;
begin
  Result := S.HasFill and (S.Fill.Kind <> tbcNone);
end;

{ the emphasis state over the normal style }
function EmphasisOver(const ANormal, AEmph: TTyTbItemStyle): TTyTbItemStyle;
begin
  Result := ANormal;
  if AEmph.HasStroke then Result.Stroke := AEmph.Stroke;
  if AEmph.HasFill then Result.Fill := AEmph.Fill;
  if AEmph.HasLineWidth then Result.LineWidth := AEmph.LineWidth;
  if AEmph.HasOpacity then Result.Opacity := AEmph.Opacity;
end;

function TyTbStyleOf(const AIcon: TTyTbIcon; AEmphasised: Boolean): TTyTbItemStyle;
begin
  Result := AIcon.Normal;
  if AEmphasised then Result := EmphasisOver(AIcon.Normal, AIcon.Emph);
end;

function TyToolboxIconRect(const ASpec: TTyToolboxSpec; const AIcon: TTyTbIcon;
  AEmphasised: Boolean): TTyXYWH;
var
  s: TTyTbItemStyle;
  fpm: TFPUExceptionMask;
begin
  if AIcon.IsImage then
  begin
    Result.X := -ASpec.ItemSize / 2;
    Result.Y := -ASpec.ItemSize / 2;
    Result.W := ASpec.ItemSize;
    Result.H := ASpec.ItemSize;
    Exit;
  end;
  s := AIcon.Normal;
  if AEmphasised then s := EmphasisOver(AIcon.Normal, AIcon.Emph);
  fpm := MaskFP;
  try
    Result := TyZrStrokeRect(AIcon.PathRect, AIcon.DataLen, StyleHasStroke(s),
      StyleHasFill(s), s.LineWidth, 1);
  finally
    UnmaskFP(fpm);
  end;
end;

{ Transformable's EPSILON }
function NotAroundZero(V: Double): Boolean;
begin
  Result := (V > 5e-5) or (V < -5e-5);
end;

function LayoutOfInner(var ASpec: TTyToolboxSpec; AW, AH: Double;
  const ARef: TTyXYWH; APrevX, APrevY: Double;
  const ATitleW, ATitleH: array of Double): TTyToolboxLayout;
var
  i, n: Integer;
  x, y, lineMax, moveX, moveY, nextX, nextY, offX, offY, topOff, tw, th: Double;
  r, nr, rect, lr: TTyXYWH;
  have, hasNext, top: Boolean;
  box: TTyRawBox;
begin
  Result := Default(TTyToolboxLayout);
  if not ASpec.Show then Exit;
  n := Length(ASpec.Icons);
  for i := 0 to n - 1 do
    ASpec.Icons[i].Rect := TyToolboxIconRect(ASpec, ASpec.Icons[i], ASpec.Icons[i].Status);
  Result.ViewRect := TyGetLayoutRect(ASpec.Box, ARef.X, ARef.Y, ARef.W, ARef.H,
    ASpec.Padding);
  { layout.box }
  x := 0;
  y := 0;
  lineMax := 0;
  nextX := 0;
  nextY := 0;
  for i := 0 to n - 1 do
  begin
    r := ASpec.Icons[i].Rect;
    hasNext := i + 1 < n;
    if hasNext then nr := ASpec.Icons[i + 1].Rect;
    if not ASpec.Vertical then
    begin
      moveX := r.W;
      if hasNext then moveX := r.W + (-nr.X + r.X);
      nextX := x + moveX;
      if nextX > Result.ViewRect.W then
      begin
        x := 0;
        nextX := moveX;
        y := y + lineMax + ASpec.ItemGap;
        lineMax := r.H;
      end
      else
        lineMax := JMax(lineMax, r.H);
    end
    else
    begin
      moveY := r.H;
      if hasNext then moveY := r.H + (-nr.Y + r.Y);
      nextY := y + moveY;
      if nextY > Result.ViewRect.H then
      begin
        x := x + lineMax + ASpec.ItemGap;
        y := 0;
        nextY := moveY;
        lineMax := r.W;
      end
      else
        lineMax := JMax(lineMax, r.W);
    end;
    ASpec.Icons[i].X := x;
    ASpec.Icons[i].Y := y;
    if not ASpec.Vertical then x := nextX + ASpec.ItemGap
    else y := nextY + ASpec.ItemGap;
  end;
  { the group's rect: every child's, through its own move }
  { Group.getBoundingRect: the first child's rect, then each unioned in }
  have := False;
  rect := Default(TTyXYWH);
  for i := 0 to n - 1 do
  begin
    r := TyRectApplyMat(ASpec.Icons[i].Rect, TyZrLocal(1, 1, 0, ASpec.Icons[i].X,
      ASpec.Icons[i].Y));
    if not have then
    begin
      rect := r;
      have := True;
    end;
    rect := JsUnion(rect, r);
  end;
  Result.Union := rect;
  { positionElement, from where the group stood }
  lr := rect;
  if NotAroundZero(APrevX) or NotAroundZero(APrevY) then
    lr := TyRectApplyMat(rect, TyZrLocal(1, 1, 0, APrevX, APrevY));
  box := ASpec.Box;
  box.Width := TyBoxRawNum(lr.W);
  box.Height := TyBoxRawNum(lr.H);
  r := TyGetLayoutRect(box, ARef.X, ARef.Y, ARef.W, ARef.H, ASpec.Padding);
  Result.GroupX := APrevX + (r.X - lr.X);
  Result.GroupY := APrevY + (r.Y - lr.Y);
  { makeBackground }
  Result.Background.X := rect.X - ASpec.Padding[3];
  Result.Background.Y := rect.Y - ASpec.Padding[0];
  Result.Background.W := rect.W + ASpec.Padding[1] + ASpec.Padding[3];
  Result.Background.H := rect.H + ASpec.Padding[0] + ASpec.Padding[2];
  { the titles kept on the canvas }
  for i := 0 to n - 1 do
  begin
    ASpec.Icons[i].Adjust := tajNone;
    if ASpec.Vertical or not ASpec.Icons[i].HasTitle or (ASpec.Icons[i].Title = '') then Continue;
    if i <= High(ATitleW) then tw := ATitleW[i] else tw := 0;
    if i <= High(ATitleH) then th := ATitleH[i] else th := 0;
    offX := ASpec.Icons[i].X + Result.GroupX;
    offY := ASpec.Icons[i].Y + Result.GroupY + ASpec.ItemSize;
    top := False;
    if offY + th > AH then
    begin
      ASpec.Icons[i].Adjust := tajTop;
      top := True;
    end;
    if top then topOff := -5 - th else topOff := ASpec.ItemSize + 10;
    if offX + tw / 2 > AW then
    begin
      ASpec.Icons[i].Adjust := tajRight;
      ASpec.Icons[i].AdjustY := topOff;
    end
    else if offX - tw / 2 < 0 then
    begin
      ASpec.Icons[i].Adjust := tajLeft;
      ASpec.Icons[i].AdjustY := topOff;
    end;
  end;
  Result.Valid := True;
end;

function TyToolboxLayoutOf(var ASpec: TTyToolboxSpec; AW, AH, APrevX,
  APrevY: Double; const ATitleW, ATitleH: array of Double): TTyToolboxLayout;
begin
  Result := TyToolboxLayoutOf(ASpec, AW, AH, TyXYWH(0, 0, AW, AH), APrevX,
    APrevY, ATitleW, ATitleH);
end;

function TyToolboxLayoutOf(var ASpec: TTyToolboxSpec; AW, AH: Double;
  const ARef: TTyXYWH; APrevX, APrevY: Double;
  const ATitleW, ATitleH: array of Double): TTyToolboxLayout;
var fpm: TFPUExceptionMask;
begin
  fpm := MaskFP;
  try
    Result := LayoutOfInner(ASpec, AW, AH, ARef, APrevX, APrevY, ATitleW, ATitleH);
  finally
    UnmaskFP(fpm);
  end;
end;

function TitlePlaceInner(const ASpec: TTyToolboxSpec;
  const ALayout: TTyToolboxLayout; AIcon: Integer; APosAdjusted,
  AAlignAdjusted, AEmphasised: Boolean): TTyTbTitlePlace; forward;

function TyToolboxTitlePlace(const ASpec: TTyToolboxSpec;
  const ALayout: TTyToolboxLayout; AIcon: Integer; APosAdjusted,
  AAlignAdjusted, AEmphasised: Boolean): TTyTbTitlePlace;
var fpm: TFPUExceptionMask;
begin
  fpm := MaskFP;
  try
    Result := TitlePlaceInner(ASpec, ALayout, AIcon, APosAdjusted, AAlignAdjusted,
      AEmphasised);
  finally
    UnmaskFP(fpm);
  end;
end;

function TitlePlaceInner(const ASpec: TTyToolboxSpec;
  const ALayout: TTyToolboxLayout; AIcon: Integer; APosAdjusted,
  AAlignAdjusted, AEmphasised: Boolean): TTyTbTitlePlace;
var
  ic: TTyTbIcon;
  r: TTyXYWH;
  pos: string;
  tx, ty: Double;
begin
  Result := Default(TTyTbTitlePlace);
  if (AIcon < 0) or (AIcon > High(ASpec.Icons)) then Exit;
  ic := ASpec.Icons[AIcon];
  r := TyToolboxIconRect(ASpec, ic, AEmphasised);
  { the host's global transform: the group's move, then the icon's }
  tx := ic.X + ALayout.GroupX;
  ty := ic.Y + ALayout.GroupY;
  if NotAroundZero(ic.X) or NotAroundZero(ic.Y) then
  begin
    if NotAroundZero(ALayout.GroupX) or NotAroundZero(ALayout.GroupY) then
      r := TyRectApplyMat(r, TyZrLocal(1, 1, 0, tx, ty))
    else
      r := TyRectApplyMat(r, TyZrLocal(1, 1, 0, ic.X, ic.Y));
  end
  else if NotAroundZero(ALayout.GroupX) or NotAroundZero(ALayout.GroupY) then
    r := TyRectApplyMat(r, TyZrLocal(1, 1, 0, ALayout.GroupX, ALayout.GroupY));
  pos := ic.TextPosition;
  if pos = '' then pos := ASpec.DefaultTextPos;
  if APosAdjusted and (ic.Adjust <> tajNone) then
  begin
    case ic.Adjust of
      tajTop: pos := 'top';
      tajRight, tajLeft: pos := '';
    end;
  end;
  Result.Align := 'left';
  Result.VAlign := 'top';
  if APosAdjusted and (ic.Adjust in [tajRight, tajLeft]) then
  begin
    { an array position: no alignment of its own }
    if ic.Adjust = tajRight then Result.X := r.X + r.W else Result.X := r.X + 0;
    Result.Y := r.Y + ic.AdjustY;
  end
  else if pos = 'left' then
  begin
    Result.X := r.X - 5;
    Result.Y := r.Y + r.H / 2;
    Result.Align := 'right';
    Result.VAlign := 'middle';
  end
  else if pos = 'right' then
  begin
    Result.X := r.X + (5 + r.W);
    Result.Y := r.Y + r.H / 2;
    Result.VAlign := 'middle';
  end
  else if pos = 'top' then
  begin
    Result.X := r.X + r.W / 2;
    Result.Y := r.Y - 5;
    Result.Align := 'center';
    Result.VAlign := 'bottom';
  end
  else if pos = 'bottom' then
  begin
    Result.X := r.X + r.W / 2;
    Result.Y := r.Y + (r.H + 5);
    Result.Align := 'center';
  end
  else
  begin
    { 'inside' and every other word: the middle }
    Result.X := r.X + r.W / 2;
    Result.Y := r.Y + r.H / 2;
    Result.Align := 'center';
    Result.VAlign := 'middle';
  end;
  { the text's own align wins over the position's -- and the adjusted
    one, in the emphasis state's text style, over that }
  if ic.TextAlign <> '' then Result.Align := ic.TextAlign;
  if AAlignAdjusted and (ic.Adjust = tajRight) then Result.Align := 'right'
  else if AAlignAdjusted and (ic.Adjust = tajLeft) then Result.Align := 'left';
end;

{ ==================== saveAsImage ==================== }

function TyToolboxSaveOpts(AOption: TTyChartOption; AFeature: TJSONObject;
  out AFileName, AType: string): string;
var
  o: TJSONObject;
  d: TJSONData;
  title, name: string;
begin
  o := TJSONObject.Create;
  try
    { model.get('type', true) || 'png' }
    d := nil;
    if AFeature <> nil then d := AFeature.Find('type');
    if JsTruthy(d) then AType := StrOf(d) else AType := 'png';
    o.Add('type', AType);
    { the feature's own background, else the option's }
    d := nil;
    if AFeature <> nil then d := AFeature.Find('backgroundColor');
    if not JsTruthy(d) and (AOption <> nil) and (AOption.Root is TJSONObject) then
      d := TJSONObject(AOption.Root).Find('backgroundColor');
    if JsTruthy(d) then o.Add('backgroundColor', d.Clone);
    d := nil;
    if AFeature <> nil then d := AFeature.Find('excludeComponents');
    if Present(d) then o.Add('excludeComponents', d.Clone);
    d := nil;
    if AFeature <> nil then d := AFeature.Find('pixelRatio');
    if Present(d) then o.Add('pixelRatio', d.Clone);
    { the combined export's background between the charts of a connected
      group, as written (upstream's default '#fff' is not: the port's
      export ground is the skin's) [Batch 141] }
    d := nil;
    if AFeature <> nil then d := AFeature.Find('connectedBackgroundColor');
    if Present(d) then o.Add('connectedBackgroundColor', d.Clone);
    Result := TyTbJson(o);
  finally
    o.Free;
  end;
  { model.get('name') || ecModel.get('title.0.text') || 'echarts' }
  name := '';
  if AFeature <> nil then
  begin
    d := AFeature.Find('name');
    if JsTruthy(d) then name := StrOf(d);
  end;
  if name = '' then
  begin
    title := '';
    if AOption <> nil then
    begin
      d := AOption.ComponentAt('title', 0);
      if d is TJSONObject then
      begin
        d := TJSONObject(d).Find('text');
        if JsTruthy(d) then title := StrOf(d);
      end;
    end;
    name := title;
  end;
  if name = '' then name := 'echarts';
  AFileName := name + '.' + AType;
end;

{ ==================== magicType ==================== }

function TyMagicTypeOption(AFeature: TJSONObject; const AType: string;
  const ASeries: TTyMagicSeriesArray; AStatus: TStrings;
  out ACurrentType: string; out ANewTitle: TJSONObject): TJSONObject;
var
  seriesArr, axisArr: TJSONArray;
  s, last, idx: Integer;
  d, q: TJSONData;
  gen, extra, ttl: TJSONObject;
  entries: array of TJSONObject;
  isStack: Boolean;
  wanted: array of Boolean;
  axisKey: string;

  procedure SetStatus(const AIcon, AState: string);
  begin
    if AStatus <> nil then AStatus.Values['magicType|' + AIcon] := AState;
  end;

  function Picked(AIndex: Integer): Boolean;
  var j: Integer;
  begin
    if q = nil then Exit(True);
    if q.JSONType = jtNumber then Exit(Round(q.AsFloat) = AIndex);
    if q is TJSONArray then
    begin
      for j := 0 to TJSONArray(q).Count - 1 do
        if (TJSONArray(q).Items[j].JSONType = jtNumber)
          and (Round(TJSONArray(q).Items[j].AsFloat) = AIndex) then Exit(True);
      Exit(False);
    end;
    Result := False;
  end;

  procedure CopyKey(ADest: TJSONObject; const AKey: string; ASrc: TJSONObject);
  var v: TJSONData;
  begin
    v := ASrc.Find(AKey);
    if v <> nil then ADest.Add(AKey, v.Clone);
  end;

  { zrUtil.defaults(target, source): a key the target holds as null or not
    at all takes the source's }
  procedure Defaults(ATarget, ASource: TJSONObject);
  var j, at: Integer;
  begin
    for j := 0 to ASource.Count - 1 do
    begin
      at := ATarget.IndexOfName(ASource.Names[j]);
      if (at >= 0) and Present(ATarget.Items[at]) then Continue;
      if at >= 0 then ATarget.Delete(at);
      ATarget.Add(ASource.Names[j], ASource.Items[j].Clone);
    end;
  end;

begin
  Result := nil;
  ANewTitle := nil;
  ACurrentType := AType;
  if (AType <> 'line') and (AType <> 'bar') and (AType <> 'stack') then Exit;
  q := PathGet(AFeature, ['seriesIndex', AType]);
  { the radio: line and bar off together; stack on its own }
  if (AType = 'line') or (AType = 'bar') then
  begin
    SetStatus('line', 'normal');
    SetStatus('bar', 'normal');
  end
  else
    SetStatus('stack', 'normal');
  SetStatus(AType, 'emphasis');
  Result := TJSONObject.Create;
  seriesArr := TJSONArray.Create;
  Result.Add('series', seriesArr);
  entries := nil;
  wanted := nil;
  SetLength(entries, Length(ASeries));
  SetLength(wanted, Length(ASeries));
  last := -1;
  extra := ObjOf(PathGet(AFeature, ['option', AType]));
  for s := 0 to High(ASeries) do
  begin
    entries[s] := nil;
    wanted[s] := Picked(ASeries[s].Index);
    if not wanted[s] then Continue;
    gen := nil;
    if (AType = 'line') and (ASeries[s].SubType = 'bar') then
    begin
      gen := TJSONObject.Create;
      gen.Add('type', 'line');
    end
    else if (AType = 'bar') and (ASeries[s].SubType = 'line') then
    begin
      gen := TJSONObject.Create;
      gen.Add('type', 'bar');
    end
    else if (AType = 'stack') and ((ASeries[s].SubType = 'line') or (ASeries[s].SubType = 'bar')) then
    begin
      d := nil;
      if ASeries[s].Node <> nil then d := ASeries[s].Node.Find('stack');
      isStack := (d <> nil) and (d.JSONType = jtString) and (d.AsString = TyTbMagicStack);
      if isStack then SetStatus('stack', 'normal') else SetStatus('stack', 'emphasis');
      gen := TJSONObject.Create;
      if isStack then gen.Add('stack', '') else gen.Add('stack', TyTbMagicStack);
    end;
    if (gen <> nil) and (AType <> 'stack') and (ASeries[s].Node <> nil) then
    begin
      { the data related options kept }
      CopyKey(gen, 'data', ASeries[s].Node);
      CopyKey(gen, 'stack', ASeries[s].Node);
      CopyKey(gen, 'markPoint', ASeries[s].Node);
      CopyKey(gen, 'markLine', ASeries[s].Node);
    end;
    if gen <> nil then
    begin
      if extra <> nil then TyTbMerge(gen, extra, True);
      if ASeries[s].Node <> nil then Defaults(gen, ASeries[s].Node);
      entries[s] := gen;
      last := s;
    end;
    { the category axis' boundaryGap }
    if ASeries[s].Cartesian and ((AType = 'line') or (AType = 'bar'))
      and (ASeries[s].CatDim <> '') and (ASeries[s].CatIndex >= 0) then
    begin
      axisKey := ASeries[s].CatDim + 'Axis';
      d := Result.Find(axisKey);
      if not (d is TJSONArray) then
      begin
        axisArr := TJSONArray.Create;
        Result.Add(axisKey, axisArr);
      end
      else
        axisArr := TJSONArray(d);
      idx := ASeries[s].CatIndex;
      while axisArr.Count <= idx do axisArr.Add(TJSONNull.Create);
      if not (axisArr.Items[idx] is TJSONObject) then
        axisArr.Items[idx] := TJSONObject.Create;
      d := TJSONObject(axisArr.Items[idx]).Find('boundaryGap');
      if d <> nil then TJSONObject(axisArr.Items[idx]).Delete('boundaryGap');
      TJSONObject(axisArr.Items[idx]).Add('boundaryGap', AType = 'bar');
    end;
  end;
  for s := 0 to last do
    if entries[s] <> nil then seriesArr.Add(entries[s])
    else seriesArr.Add(TJSONObject.Create);
  for s := last + 1 to High(entries) do entries[s].Free;
  { stack and tiled: the two titles flipped }
  if AType = 'stack' then
  begin
    ttl := ObjOf(AFeature.Find('title'));
    ANewTitle := TJSONObject.Create;
    if ttl <> nil then
    begin
      d := ttl.Find('tiled');
      if d <> nil then ANewTitle.Add('stack', d.Clone) else ANewTitle.Add('stack', TJSONNull.Create);
      d := ttl.Find('stack');
      if d <> nil then ANewTitle.Add('tiled', d.Clone) else ANewTitle.Add('tiled', TJSONNull.Create);
      TyTbMerge(ANewTitle, ttl, False);
    end;
    if (AStatus = nil) or (AStatus.Values['magicType|stack'] <> 'emphasis') then
      ACurrentType := 'tiled';
  end;
end;

{ ==================== dataView ==================== }

function NumText(const ACol: TTyDoubleArray; AIndex: Integer): string;
begin
  { an absent cell joins as nothing }
  if (AIndex < 0) or (AIndex > High(ACol)) then Exit('');
  Result := TyJsNumberToString(ACol[AIndex]);
end;

function TyDataViewText(const AGroups: TTyDvGroupArray;
  const ALists: TTyDvListArray): string;
var
  g, i, j: Integer;
  tables, lists, lines, line, sep: string;

  function NotBlank(const S: string): Boolean;
  var k: Integer;
  begin
    for k := 1 to Length(S) do
      if not (S[k] in [#9, #10, #11, #12, #13, ' ']) then Exit(True);
    Result := False;
  end;

begin
  sep := #10#10 + TyDataViewBlock + #10#10;
  tables := '';
  for g := 0 to High(AGroups) do
  begin
    lines := ' ';
    for j := 0 to High(AGroups[g].Names) do lines := lines + #9 + AGroups[g].Names[j];
    for i := 0 to High(AGroups[g].Categories) do
    begin
      line := AGroups[g].Categories[i];
      for j := 0 to High(AGroups[g].Columns) do
        line := line + #9 + NumText(AGroups[g].Columns[j], i);
      lines := lines + #10 + line;
    end;
    if g > 0 then tables := tables + sep;
    tables := tables + lines;
  end;
  lists := '';
  for g := 0 to High(ALists) do
  begin
    lines := ALists[g].Name;
    for i := 0 to High(ALists[g].Rows) do
    begin
      line := '';
      if (i <= High(ALists[g].RowNames)) and (ALists[g].RowNames[i] <> '') then
        line := ALists[g].RowNames[i] + #9;
      for j := 0 to High(ALists[g].Rows[i]) do
      begin
        if j > 0 then line := line + #9;
        line := line + TyJsNumberToString(ALists[g].Rows[i][j]);
      end;
      lines := lines + #10 + line;
    end;
    if g > 0 then lists := lists + sep;
    lists := lists + lines;
  end;
  Result := '';
  if NotBlank(tables) then Result := tables;
  if NotBlank(lists) then
  begin
    if Result <> '' then Result := Result + sep;
    Result := Result + lists;
  end;
end;

{ str.split(/X+/g): the runs of the separator characters as one }
function SplitRuns(const S: string; ASep: Char): TTyStringArray;
var
  i, start: Integer;
begin
  Result := nil;
  start := 1;
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = ASep then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(S, start, i - start);
      while (i <= Length(S)) and (S[i] = ASep) do Inc(i);
      start := i;
      Continue;
    end;
    Inc(i);
  end;
  SetLength(Result, Length(Result) + 1);
  Result[High(Result)] := Copy(S, start, Length(S) - start + 1);
end;

{ str.split(/\n*<block>\n*/g) }
function SplitBlocks(const S: string): TTyStringArray;
var
  i, j, start, at: Integer;
begin
  Result := nil;
  start := 1;
  i := 1;
  while i <= Length(S) do
  begin
    { a match starts at the first newline of a run that the block follows,
      or at the block itself }
    j := i;
    while (j <= Length(S)) and (S[j] = #10) do Inc(j);
    if Copy(S, j, Length(TyDataViewBlock)) = TyDataViewBlock then
    begin
      at := j + Length(TyDataViewBlock);
      while (at <= Length(S)) and (S[at] = #10) do Inc(at);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(S, start, i - start);
      start := at;
      i := at;
      Continue;
    end;
    Inc(i);
  end;
  SetLength(Result, Length(Result) + 1);
  Result[High(Result)] := Copy(S, start, Length(S) - start + 1);
end;

function TyDataViewParse(const AText: string; const AMeta: TTyDvMetaArray;
  out AError: string): TJSONObject;
var
  blocks, lines, headers, items: TTyStringArray;
  b, i, j, nl: Integer;
  block, first, axisKey, nm: string;
  series, axes, item, valueArr: TJSONData;
  heads: array of TJSONObject;
  cats, data, vals: TJSONArray;
  ser, obj, entry: TJSONObject;
  hasName: Boolean;
  v: Double;

  function NumJson(AValue: Double): TJSONData;
  begin
    { NaN and the infinities as JSON cannot hold them: their String() }
    if IsNan(AValue) or IsInfinite(AValue) then
      Result := TJSONString.Create(TyJsNumberToString(AValue))
    else if (Frac(AValue) = 0) and (Abs(AValue) < 9e15) then
      Result := TJSONInt64Number.Create(Trunc(AValue))
    else
      Result := TJSONFloatNumber.Create(AValue);
  end;

  { data[i] = x on a JavaScript array: holes before it read null }
  procedure PutAt(AArr: TJSONArray; AIndex: Integer; AValue: TJSONData);
  begin
    while AArr.Count < AIndex do AArr.Add(TJSONNull.Create);
    if AArr.Count = AIndex then AArr.Add(AValue)
    else AArr.Items[AIndex] := AValue;
  end;

begin
  AError := '';
  Result := TJSONObject.Create;
  series := TJSONArray.Create;
  TJSONObject(Result).Add('series', series);
  blocks := SplitBlocks(AText);
  for b := 0 to High(blocks) do
  begin
    block := blocks[b];
    { isTSVFormat: block.slice(0, block.indexOf('\n')) -- with no newline
      the whole block but its last character }
    nl := Pos(#10, block);
    if nl > 0 then first := Copy(block, 1, nl - 1)
    else first := Copy(block, 1, Length(block) - 1);
    if Pos(#9, first) > 0 then
    begin
      lines := SplitRuns(block, #10);
      headers := SplitRuns(TyJsTrim(lines[0]), #9);
      SetLength(heads, Length(headers));
      for j := 0 to High(headers) do
      begin
        heads[j] := TJSONObject.Create;
        heads[j].Add('name', headers[j]);
        heads[j].Add('data', TJSONArray.Create);
      end;
      cats := TJSONArray.Create;
      for i := 1 to High(lines) do
      begin
        items := SplitRuns(TyJsTrim(lines[i]), #9);
        cats.Add(items[0]);
        for j := 1 to High(items) do
          if j - 1 <= High(heads) then
            PutAt(TJSONArray(heads[j - 1].Find('data')), i - 1, TJSONString.Create(items[j]));
      end;
      if b > High(AMeta) then
      begin
        { blockMeta.axisDim of undefined }
        cats.Free;
        for j := 0 to High(heads) do heads[j].Free;
        Result.Free;
        Result := nil;
        AError := 'TypeError: Cannot read properties of undefined (reading ''axisDim'')';
        Exit;
      end;
      axisKey := AMeta[b].AxisDim + 'Axis';
      axes := TJSONObject(Result).Find(axisKey);
      if not (axes is TJSONArray) then
      begin
        axes := TJSONArray.Create;
        TJSONObject(Result).Add(axisKey, axes);
      end;
      obj := TJSONObject.Create;
      obj.Add('data', cats);
      PutAt(TJSONArray(axes), AMeta[b].AxisIndex, obj);
      for j := 0 to High(heads) do TJSONArray(series).Add(heads[j]);
    end
    else
    begin
      lines := SplitRuns(block, #10);
      ser := TJSONObject.Create;
      ser.Add('name', TyJsTrim(lines[0]));
      data := TJSONArray.Create;
      ser.Add('data', data);
      for i := 1 to High(lines) do
      begin
        if TyJsTrim(lines[i]) = '' then Continue;
        items := SplitRuns(TyJsTrim(lines[i]), #9);
        hasName := IsNan(TyJsToNumber(items[0]));
        vals := TJSONArray.Create;
        nm := '';
        if hasName then nm := items[0];
        for j := Ord(hasName) to High(items) do
        begin
          v := TyJsToNumber(items[j]);
          vals.Add(NumJson(v));
        end;
        if vals.Count = 1 then
        begin
          valueArr := vals.Extract(0);
          vals.Free;
        end
        else
          valueArr := vals;
        if hasName then
        begin
          entry := TJSONObject.Create;
          entry.Add('name', nm);
          entry.Add('value', valueArr);
          item := entry;
        end
        else
          item := valueArr;
        PutAt(data, i - 1, item);
      end;
      TJSONArray(series).Add(ser);
    end;
  end;
end;

function TyDataViewChange(AParsed: TJSONObject; AFind: TTyDvFindSeries): TJSONObject;
var
  list, newData, oldArr: TJSONArray;
  src: TJSONArray;
  i, j, k: Integer;
  so, entry, nv, orig: TJSONObject;
  d, od, item: TJSONData;
  name: string;
  oldData: TJSONData;
  delName: Boolean;
begin
  Result := TJSONObject.Create;
  list := TJSONArray.Create;
  Result.Add('series', list);
  d := AParsed.Find('series');
  if d is TJSONArray then
  begin
    src := TJSONArray(d);
    for i := 0 to src.Count - 1 do
    begin
      so := ObjOf(src.Items[i]);
      if so = nil then Continue;
      name := StrOf(so.Find('name'));
      oldData := nil;
      if not AFind(name, oldData) then
      begin
        { a new series: a scatter }
        entry := TJSONObject.Create;
        entry.Add('type', 'scatter');
        for k := 0 to so.Count - 1 do
        begin
          if entry.IndexOfName(so.Names[k]) >= 0 then entry.Delete(so.Names[k]);
          entry.Add(so.Names[k], so.Items[k].Clone);
        end;
        list.Add(entry);
        Continue;
      end;
      entry := TJSONObject.Create;
      entry.Add('name', name);
      newData := TJSONArray.Create;
      entry.Add('data', newData);
      d := so.Find('data');
      oldArr := nil;
      if oldData is TJSONArray then oldArr := TJSONArray(oldData);
      if d is TJSONArray then
        for j := 0 to TJSONArray(d).Count - 1 do
        begin
          item := TJSONArray(d).Items[j];
          { a hole (map skips it) }
          if item.JSONType = jtNull then
          begin
            newData.Add(TJSONNull.Create);
            Continue;
          end;
          od := nil;
          if (oldArr <> nil) and (j < oldArr.Count) then od := oldArr.Items[j];
          if od is TJSONObject then
          begin
            orig := TJSONObject(od);
            if item is TJSONObject then nv := TJSONObject(item.Clone)
            else
            begin
              nv := TJSONObject.Create;
              nv.Add('value', item.Clone);
            end;
            delName := Present(orig.Find('name')) and not Present(nv.Find('name'));
            for k := 0 to orig.Count - 1 do
            begin
              if Present(nv.Find(orig.Names[k])) then Continue;
              if nv.IndexOfName(orig.Names[k]) >= 0 then nv.Delete(orig.Names[k]);
              nv.Add(orig.Names[k], orig.Items[k].Clone);
            end;
            if delName and (nv.IndexOfName('name') >= 0) then nv.Delete('name');
            newData.Add(nv);
          end
          else
            newData.Add(item.Clone);
        end;
      list.Add(entry);
    end;
  end;
  { defaults(the series, payload.newOption): the axes as parsed }
  for i := 0 to AParsed.Count - 1 do
    if AParsed.Names[i] <> 'series' then
      Result.Add(AParsed.Names[i], AParsed.Items[i].Clone);
end;

{ ==================== the brush and the history ==================== }

function TyTbHistoryCount(const AHistory: TTyTbHistory): Integer;
begin
  { getStoreSnapshots: the store starts with one empty snapshot }
  Result := Length(AHistory);
  if Result = 0 then Result := 1;
end;

function FindItem(const ASnap: TTyTbSnapshot; const AKey: string): Integer;
var i: Integer;
begin
  for i := 0 to High(ASnap) do
    if ASnap[i].Key = AKey then Exit(i);
  Result := -1;
end;

procedure TyTbHistoryPush(var AHistory: TTyTbHistory; const ASnap: TTyTbSnapshot;
  const APresentKeys: TTyStringArray; const APresentA, APresentB: TTyDoubleArray);
var
  i, j, k, n: Integer;
  found: Boolean;
begin
  if Length(AHistory) = 0 then SetLength(AHistory, 1);
  for i := 0 to High(ASnap) do
  begin
    found := False;
    for j := High(AHistory) downto 0 do
      if FindItem(AHistory[j], ASnap[i].Key) >= 0 then
      begin
        found := True;
        Break;
      end;
    if found then Continue;
    for k := 0 to High(APresentKeys) do
      if APresentKeys[k] = ASnap[i].Key then
      begin
        n := Length(AHistory[0]);
        SetLength(AHistory[0], n + 1);
        AHistory[0][n].Key := ASnap[i].Key;
        AHistory[0][n].IsValue := False;
        AHistory[0][n].A := APresentA[k];
        AHistory[0][n].B := APresentB[k];
        Break;
      end;
  end;
  SetLength(AHistory, Length(AHistory) + 1);
  AHistory[High(AHistory)] := Copy(ASnap);
end;

function TyTbHistoryPop(var AHistory: TTyTbHistory): TTyTbSnapshot;
var
  head: TTyTbSnapshot;
  i, j, k, n: Integer;
begin
  Result := nil;
  if Length(AHistory) = 0 then SetLength(AHistory, 1);
  head := AHistory[High(AHistory)];
  if Length(AHistory) > 1 then SetLength(AHistory, Length(AHistory) - 1);
  for i := 0 to High(head) do
    for j := High(AHistory) downto 0 do
    begin
      k := FindItem(AHistory[j], head[i].Key);
      if k >= 0 then
      begin
        n := Length(Result);
        SetLength(Result, n + 1);
        Result[n] := AHistory[j][k];
        Break;
      end;
    end;
end;

function TyTbRound(AValue, APrecision: Double): Double;
begin
  Result := TyDzRound(AValue, APrecision);
end;

procedure WriteJson(AData: TJSONData; var AOut: string);
var
  i: Integer;
  keys: TStringArray;
  v: Double;
begin
  if AData = nil then
  begin
    AOut := AOut + 'null';
    Exit;
  end;
  case AData.JSONType of
    jtNull: AOut := AOut + 'null';
    jtBoolean: if AData.AsBoolean then AOut := AOut + 'true' else AOut := AOut + 'false';
    jtNumber:
      begin
        if (AData is TJSONIntegerNumber) or (AData is TJSONInt64Number) or (AData is TJSONQWordNumber) then
          AOut := AOut + AData.AsString
        else
        begin
          v := AData.AsFloat;
          if IsNan(v) or IsInfinite(v) then AOut := AOut + 'null'
          else AOut := AOut + TyJsNumberToString(v);
        end;
      end;
    jtString: AOut := AOut + TyJsonQuote(AData.AsString);
    jtArray:
      begin
        AOut := AOut + '[';
        for i := 0 to AData.Count - 1 do
        begin
          if i > 0 then AOut := AOut + ',';
          WriteJson(AData.Items[i], AOut);
        end;
        AOut := AOut + ']';
      end;
    jtObject:
      begin
        keys := TyJsOrderedKeys(TJSONObject(AData));
        AOut := AOut + '{';
        for i := 0 to High(keys) do
        begin
          if i > 0 then AOut := AOut + ',';
          AOut := AOut + TyJsonQuote(keys[i]) + ':';
          WriteJson(TJSONObject(AData).Find(keys[i]), AOut);
        end;
        AOut := AOut + '}';
      end;
  else
    AOut := AOut + 'null';
  end;
end;

function TyTbJson(AData: TJSONData): string;
begin
  Result := '';
  WriteJson(AData, Result);
end;

end.
