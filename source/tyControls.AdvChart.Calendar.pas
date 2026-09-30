unit tyControls.AdvChart.Calendar;
{$mode objfpc}{$H+}
{ The calendar: a coordinate system of days, and the component that draws it.

  EVERY DATE IS A LOCAL CIVIL DAY. Upstream reads a date through the local
  getters -- getFullYear, getMonth, getDate, getDay -- and steps with setDate,
  and it ignores `useUTC` altogether. So a date string lands on the same cell in
  every zone, and a numeric timestamp lands on whichever day it is where the
  chart runs. This unit converts each instant to a WALL CLOCK once, at the
  offset the date parser used, and does all the rest in whole days: the week
  a day falls in, the day's row, the first of each month. Upstream's own
  DST correction loop in _getRangeInfo is therefore not needed -- a wall clock
  has no DST -- and a zone whose DST starts at midnight, where upstream loses a
  day, is the one place the two can differ.

  THE BOX IS MERGED TWICE, the way CalendarModel does it: the count-based
  mergeLayoutParam over the defaults (left 80, top 60), then again with
  ignoreSize set in every direction whose cell size is a number -- after a
  `width`, or a `left` and a `right`, has already forced that cell size to
  'auto'. A shortcut that merges once gets three of the box table's rows
  wrong.

  THE PICTURE is CalendarView's, in its order: the day cells (z2 0), a
  staircase polyline at the start of the range, at every first of the month
  inside it and one day past its end (z2 20), the two edge lines, then the
  year, month and day names (z2 30). A heatmap cell (z2 1) therefore sits
  over the day cells and under the split lines.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data, tyControls.AdvChart.Layout,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Paint,
  tyControls.AdvChart.Shape, tyControls.AdvChart.Color,
  tyControls.AdvChart.Labels;

const
  TyCalendarCoordSysName = 'calendar';
  TyCalDayMs = 86400000;

type
  TTyCalOrient = (tcoHorizontal, tcoVertical);
  { Where a label's words come from: the chart's locale (no nameMap, or a
    string that is not a locale upstream knows -- 'cn' and 'en' among them),
    upstream's own two locales by their exact names, or the author's array. }
  TTyCalNames = (tcnLocale, tcnEN, tcnZH, tcnArray);
  TTyCalYearPos = (tcyDefault, tcyTop, tcyBottom, tcyLeft, tcyRight);

  { One label's font and ink, as the option wrote them. }
  TTyCalText = record
    HasColour: Boolean;
    Colour: TTyChartColor;
    HasFontSize: Boolean;
    FontSizeLogical: Integer;
    HasWeight: Boolean;
    FontWeight: Integer;
    HasFontName: Boolean;
    FontName: string;
  end;

  { A box key with whether the option object OWNS it -- mergeLayoutParam
    tells "absent" from "present and undefined", and copy() makes every key
    present. }
  TTyCalBoxKey = record
    Own: Boolean;
    V: TTyBoxRaw;
  end;
  TTyCalBoxKeys = array[0..5] of TTyCalBoxKey;   // width left right height top bottom

  TTyCalendarSpec = record
    Box: TTyRawBox;
    { per direction: the cell size when it is a number (logical px), else
      'auto' -- which the layout divides the rect by }
    CellAuto: array[0..1] of Boolean;
    Cell: array[0..1] of Double;
    Orient: TTyCalOrient;
    { the range as written, before it meets a zone: one value, or a pair }
    RangeOk: Boolean;
    RangeIsPair: Boolean;
    RangeA, RangeB: TTyDataValue;
    FirstDay: Double;
    Item: TTyOptStyle;
    SplitShow: Boolean;
    Split: TTyOptStyle;
    DayShow, DayStart: Boolean;
    DayMargin: Double;
    DayMarginPct: Boolean;
    DayNames: TTyCalNames;
    DayArray: TTyStringArray;
    DayText: TTyCalText;
    MonthShow, MonthStart, MonthCentre: Boolean;
    MonthMargin: Double;
    MonthFormatter: string;
    MonthNames: TTyCalNames;
    MonthArray: TTyStringArray;
    MonthText: TTyCalText;
    YearShow: Boolean;
    YearPos: TTyCalYearPos;
    YearMargin: Double;
    YearFormatter: string;
    YearText: TTyCalText;
    Z: Integer;
  end;

  { getDateInfo: the civil fields of an instant, and the instant. Day is the
    row within the week, counted from firstDay -- a Double, as upstream's is. }
  TTyCalDateInfo = record
    Valid: Boolean;
    Y, M, D: Integer;
    Day: Double;
    Time: Double;
    { the civil day, days since 1970-01-01 on the wall clock }
    DayNum: Int64;
    { the instant of that day's local midnight -- formatedDate re-parsed }
    Midnight: Double;
  end;

  TTyCalRangeInfo = record
    Start, Stop: TTyCalDateInfo;
    AllDay: Int64;
    Weeks: Double;
    NthWeek: Double;
    FWeek, LWeek: Double;
  end;

  TTyCalCellLayout = record
    Centre, TL, TR, BR, BL: TTyPointF;
  end;

  TTyCalendar = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FSpec: TTyCalendarSpec;
    FUTC: Boolean;
    FOffsetMs: Int64;
    FRange: TTyCalRangeInfo;
    FValid: Boolean;
    FRect: TTyXYWH;
    FSW, FSH: Double;
    FLineWidth: Double;
    FScale: Double;
    procedure InitRange(out AA, AB: Double; out AOk: Boolean);
    procedure SetUTC(AValue: Boolean);
  public
    constructor Create(const ASpec: TTyCalendarSpec);
    { The rect, the cell size and the range, from the CANVAS -- the calendar's
      box is laid out on the whole chart, with no margin. }
    procedure Resize(const AContainer: TTyRectF; APPI: Integer);
    { A date as the calendar reads it: a number is epoch ms (rounded), a
      string goes through upstream's TIME_REG, anything else is not a date. }
    function ParseDate(const AValue: TTyDataValue): Double;
    function DateInfo(AMs: Double): TTyCalDateInfo;
    function NextNDay(AMs: Double; AN: Integer): Double;
    function RangeInfo(AMs0, AMs1: Double): TTyCalRangeInfo;
    { dataToPoint: the centre of the date's cell, NaN when AClamp and the date
      is outside the range }
    function DatePoint(AMs: Double; AClamp: Boolean): TTyPointF;
    function DateCell(AMs: Double; AClamp: Boolean): TTyCalCellLayout;
    function DateLayout(AMs: Double; AClamp: Boolean): TTyCoordLayout;
    { ---- ITyCoordSys: data is [ms, value]; the value is ignored ---- }
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF;
      out AData: TTyDoubleArray): Boolean;
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
    { Test seam: read every date in UTC instead of the machine's zone, so an
      oracle run under TZ=UTC can be compared on any machine. Set before
      Resize. }
    property UTC: Boolean read FUTC write SetUTC;
    property Spec: TTyCalendarSpec read FSpec;
    property Valid: Boolean read FValid;
    property Rect: TTyXYWH read FRect;
    property CellW: Double read FSW;
    property CellH: Double read FSH;
    property Range: TTyCalRangeInfo read FRange;
    property LineWidth: Double read FLineWidth;
  end;

  { Resolved ink: the control asks the theme, this unit never does. }
  TTyCalendarInk = record
    CellFill: TTyChartColor;
    CellBorder: TTyChartColor;
    SplitLine: TTyChartColor;
    LabelColour: TTyChartColor;
    LabelFontName: string;
    LabelFontSizeLogical: Integer;
    LabelFontWeight: Integer;
    YearColour: TTyChartColor;
    YearFontName: string;
  end;

function TyCalendarSpecDefault: TTyCalendarSpec;
function TyCalendarSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyCalendarSpec;
{ mergeLayoutParam on the six keys, with ignoreSize per direction. }
procedure TyCalMergeLayoutParam(var ATarget: TTyCalBoxKeys;
  const ANew: TTyCalBoxKeys; AIgnoreW, AIgnoreH: Boolean);
{ formatTplSimple: each `(key)` in braces replaced at its FIRST occurrence, in the order
  the params are given. }
function TyCalFormatTpl(const ATpl: string; const AKeys, AValues: array of string): string;
{ The furniture of one calendar, into AList, at the calendar's z. }
function TyBuildCalendar(ACal: TTyCalendar; const AInk: TTyCalendarInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList): Integer;

implementation

uses tyControls.AdvChart.Scale, tyControls.StrConsts, tyControls.AdvChart.Handlers, tyControls.FontUnits;

{ what a named month or year label handler is given: nameMap as Name, the
  kind in Extra, and (yyyy, M) for a month, (start, end) for a year }
function CalHandler(const AHandler, AKind, ANameMap: string; A, B: Integer): string;
var prm: TTyChartCallbackParams;
begin
  prm := TyChartBlankParams;
  prm.ComponentType := 'calendar';
  prm.Extra := AKind;
  prm.Name := ANameMap;
  SetLength(prm.Values, 2);
  prm.Values[0] := A;
  prm.Values[1] := B;
  Result := TyChartRunHandler(AHandler, TyChartOneParams(prm));
end;

const
  cEnMonths: array[0..11] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May',
    'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
  cEnDays: array[0..6] of string = ('S', 'M', 'T', 'W', 'T', 'F', 'S');
  cZhMonths: array[0..11] of string = ('1月', '2月', '3月', '4月', '5月',
    '6月', '7月', '8月', '9月', '10月', '11月', '12月');
  cZhDays: array[0..6] of string = ('日', '一', '二', '三', '四', '五', '六');
  { mergeLayoutParam's HV_NAMES: [size, start, end] per direction }
  cHV: array[0..1, 0..2] of Integer = ((0, 1, 2), (3, 4, 5));
  cBoxKeyName: array[0..5] of string = ('width', 'left', 'right', 'height',
    'top', 'bottom');
  { A range wider than this many days draws nothing rather than a million
    cells. }
  cMaxDays = 100000;

{ ==================== small readers ==================== }

function ObjIn(ANode: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtObject) then Result := TJSONObject(d);
end;

{ JS truthiness of an option value that is present. }
function Truthy(AData: TJSONData): Boolean;
begin
  if AData = nil then Exit(False);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

{ `show`: a key that is not written keeps its default; a written one is read
  for its truthiness. }
function ShowIn(ANode: TJSONObject; ADefault: Boolean): Boolean;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find('show');
  if d <> nil then Result := Truthy(d);
end;

function NumOf(AData: TJSONData; ADefault: Double): Double;
begin
  Result := ADefault;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtString: Result := TyJsToNumber(AData.AsString);
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtNull: Result := 0;
  end;
end;

function StrOf(AData: TJSONData): string;
begin
  Result := '';
  if (AData <> nil) and (AData.JSONType = jtString) then Result := AData.AsString;
end;

function WeightOf(const S: string; out AWeight: Integer): Boolean;
var n: Double;
begin
  Result := True;
  if (S = 'bold') or (S = 'bolder') then AWeight := 700
  else if S = 'normal' then AWeight := 400
  else if S = 'lighter' then AWeight := 300
  else
  begin
    n := TyJsToNumber(S);
    Result := not IsNan(n) and (n > 0);
    if Result then AWeight := Round(n);
  end;
end;

procedure ReadText(ANode: TJSONObject; var AText: TTyCalText);
var
  d: TJSONData;
  c: TTyChartColor;
  w: Integer;
begin
  if ANode = nil then Exit;
  d := ANode.Find('color');
  if (d <> nil) and (d.JSONType = jtString)
    and TyTryParseChartColor(d.AsString, c) then
  begin
    AText.HasColour := True;
    AText.Colour := c;
  end;
  { CSS px, a number or zrender's string forms [Batch 83] }
  if TyOptFontSize(ANode.Find('fontSize'), 0) > 0 then
  begin
    AText.HasFontSize := True;
    AText.FontSizeLogical := TyOptFontSize(ANode.Find('fontSize'), 0);
  end;
  d := ANode.Find('fontWeight');
  if (d <> nil) and (d.JSONType in [jtString, jtNumber]) then
  begin
    if d.JSONType = jtNumber then
    begin
      AText.HasWeight := True;
      AText.FontWeight := Round(d.AsFloat);
    end
    else if WeightOf(d.AsString, w) then
    begin
      AText.HasWeight := True;
      AText.FontWeight := w;
    end;
  end;
  d := ANode.Find('fontFamily');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> '') then
  begin
    AText.HasFontName := True;
    AText.FontName := d.AsString;
  end;
end;

{ A nameMap: an array of words, one of upstream's two locales by its exact
  name, else the chart's locale. }
procedure ReadNames(ANode: TJSONObject; out AKind: TTyCalNames;
  out AArray: TTyStringArray);
var
  d: TJSONData;
  i: Integer;
begin
  AKind := tcnLocale;
  AArray := nil;
  if ANode = nil then Exit;
  d := ANode.Find('nameMap');
  if d = nil then Exit;
  if d.JSONType = jtArray then
  begin
    AKind := tcnArray;
    SetLength(AArray, d.Count);
    for i := 0 to d.Count - 1 do
      case d.Items[i].JSONType of
        jtString: AArray[i] := d.Items[i].AsString;
        jtNumber: AArray[i] := TyJsNumberToString(d.Items[i].AsFloat);
      else
        AArray[i] := '';
      end;
  end
  else if d.JSONType = jtString then
  begin
    { CASE-SENSITIVE, against the two registered keys: 'cn' is the chart's
      locale, not Chinese }
    if d.AsString = 'EN' then AKind := tcnEN
    else if d.AsString = 'ZH' then AKind := tcnZH;
  end;
end;

function BoxRawOwn(ANode: TJSONObject; const AKey: string): TTyCalBoxKey;
var d: TJSONData;
begin
  Result := Default(TTyCalBoxKey);
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d = nil then Exit;
  Result.Own := True;
  Result.V := TyBoxRawOf(d);
end;

{ hasValue: `!= null && !== 'auto'` }
function HasValue(const K: TTyCalBoxKey): Boolean;
begin
  Result := K.Own and not (K.V.Kind in [brAbsent, brNull])
    and not ((K.V.Kind = brString) and (K.V.Str = 'auto'));
end;

{ `!= null`, which 'auto' passes }
function NotNull(const K: TTyCalBoxKey): Boolean;
begin
  Result := K.Own and not (K.V.Kind in [brAbsent, brNull]);
end;

procedure TyCalMergeLayoutParam(var ATarget: TTyCalBoxKeys;
  const ANew: TTyCalBoxKeys; AIgnoreW, AIgnoreH: Boolean);
var
  res: array[0..1] of TTyCalBoxKeys;
  hv, k, n, newCount, mergedCount: Integer;
  merged, newParams: TTyCalBoxKeys;
  ignore: Boolean;
  nul: TTyCalBoxKey;
begin
  nul := Default(TTyCalBoxKey);
  nul.Own := True;
  nul.V.Kind := brNull;
  for hv := 0 to 1 do
  begin
    if hv = 0 then ignore := AIgnoreW else ignore := AIgnoreH;
    merged := Default(TTyCalBoxKeys);
    newParams := Default(TTyCalBoxKeys);
    newCount := 0;
    mergedCount := 0;
    for k := 0 to 2 do
    begin
      n := cHV[hv, k];
      merged[n] := ATarget[n];
    end;
    for k := 0 to 2 do
    begin
      n := cHV[hv, k];
      if ANew[n].Own then
      begin
        newParams[n] := ANew[n];
        merged[n] := ANew[n];
      end;
      if HasValue(newParams[n]) then Inc(newCount);
      if HasValue(merged[n]) then Inc(mergedCount);
    end;
    if ignore then
    begin
      { only one of left / right may exist }
      if HasValue(ANew[cHV[hv, 1]]) then merged[cHV[hv, 2]] := nul
      else if HasValue(ANew[cHV[hv, 2]]) then merged[cHV[hv, 1]] := nul;
      res[hv] := merged;
    end
    else if (mergedCount = 2) or (newCount = 0) then
      res[hv] := merged
    else if newCount >= 2 then
      res[hv] := newParams
    else
    begin
      { another param from the target, by priority }
      for k := 0 to 2 do
      begin
        n := cHV[hv, k];
        if (not newParams[n].Own) and ATarget[n].Own then
        begin
          newParams[n] := ATarget[n];
          Break;
        end;
      end;
      res[hv] := newParams;
    end;
  end;
  { copy(): every key becomes the target's own, undefined included }
  for hv := 0 to 1 do
    for k := 0 to 2 do
    begin
      n := cHV[hv, k];
      ATarget[n] := res[hv][n];
      ATarget[n].Own := True;
    end;
end;

{ String.prototype.replace's replacement string: `$$` is a dollar, `$&` the
  match, `$`` what precedes it, `$'` what follows; with a string pattern
  there are no groups, so `$1` stays as written. }
function JsReplacement(const AWith, ABefore, AMatch, AAfter: string): string;
var i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(AWith) do
  begin
    if (AWith[i] = '$') and (i < Length(AWith)) then
      case AWith[i + 1] of
        '$': begin Result := Result + '$'; Inc(i, 2); Continue; end;
        '&': begin Result := Result + AMatch; Inc(i, 2); Continue; end;
        '`': begin Result := Result + ABefore; Inc(i, 2); Continue; end;
        '''': begin Result := Result + AAfter; Inc(i, 2); Continue; end;
      end;
    Result := Result + AWith[i];
    Inc(i);
  end;
end;

function TyCalFormatTpl(const ATpl: string; const AKeys, AValues: array of string): string;
var
  i, p: Integer;
  tok, before, after: string;
begin
  Result := ATpl;
  for i := 0 to High(AKeys) do
  begin
    tok := '{' + AKeys[i] + '}';
    p := Pos(tok, Result);
    if p > 0 then
    begin
      before := Copy(Result, 1, p - 1);
      after := Copy(Result, p + Length(tok), Length(Result));
      Result := before + JsReplacement(AValues[i], before, tok, after) + after;
    end;
  end;
end;

{ ==================== the spec ==================== }

function TyCalendarSpecDefault: TTyCalendarSpec;
begin
  Result := Default(TTyCalendarSpec);
  Result.Box.Left := TyBoxRawNum(80);
  Result.Box.Top := TyBoxRawNum(60);
  Result.Cell[0] := 20;
  Result.Cell[1] := 20;
  Result.Orient := tcoHorizontal;
  Result.Item.BorderWidthLogical := NaN;
  Result.Item.Opacity := NaN;
  Result.Split.BorderWidthLogical := NaN;
  Result.Split.Opacity := NaN;
  Result.SplitShow := True;
  Result.DayShow := True;
  Result.DayStart := True;
  Result.DayMargin := 10;
  Result.MonthShow := True;
  Result.MonthStart := True;
  Result.MonthCentre := True;
  Result.MonthMargin := 10;
  Result.YearShow := True;
  Result.YearMargin := 30;
  { upstream's own defaults for the year, which beat the global textStyle }
  Result.YearText.HasFontSize := True;
  Result.YearText.FontSizeLogical := TyFontSizeFromPx(20);
  Result.YearText.HasWeight := True;
  Result.YearText.FontWeight := 700;
  Result.Z := 2;
end;

function TyCalendarSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyCalendarSpec;
var
  node, sub, gts: TJSONObject;
  d, e: TJSONData;
  raw, target: TTyCalBoxKeys;
  k: Integer;
  cellArr: array[0..1] of TJSONData;
  ignW, ignH: Boolean;
  s: string;

  function CellIsAuto(AData: TJSONData): Boolean;
  begin
    Result := (AData = nil) or (AData.JSONType = jtNull)
      or ((AData.JSONType = jtString) and (AData.AsString = 'auto'));
  end;

begin
  Result := TyCalendarSpecDefault;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('calendar', ASlot);
  if (d = nil) or (d.JSONType <> jtObject) then Exit;
  node := TJSONObject(d);

  { ---- the box: mergeDefaultAndTheme, then mergeAndNormalizeLayoutParams ---- }
  for k := 0 to 5 do raw[k] := BoxRawOwn(node, cBoxKeyName[k]);
  target := raw;
  if not target[1].Own then
  begin
    target[1].Own := True;
    target[1].V := TyBoxRawNum(80);
  end;
  if not target[4].Own then
  begin
    target[4].Own := True;
    target[4].V := TyBoxRawNum(60);
  end;
  TyCalMergeLayoutParam(target, raw, False, False);
  { cellSize: a number doubled, a one-array doubled }
  d := node.Find('cellSize');
  if d = nil then
  begin
    cellArr[0] := nil;
    cellArr[1] := nil;
    Result.CellAuto[0] := False;
    Result.CellAuto[1] := False;
  end
  else
  begin
    if d.JSONType = jtArray then
    begin
      if d.Count >= 1 then cellArr[0] := d.Items[0] else cellArr[0] := nil;
      if d.Count >= 2 then cellArr[1] := d.Items[1]
      else if d.Count = 1 then cellArr[1] := d.Items[0]
      else cellArr[1] := nil;
    end
    else
    begin
      cellArr[0] := d;
      cellArr[1] := d;
    end;
    for k := 0 to 1 do
    begin
      Result.CellAuto[k] := CellIsAuto(cellArr[k]);
      if not Result.CellAuto[k] then Result.Cell[k] := NumOf(cellArr[k], NaN);
    end;
  end;
  { sizeCalculable forces 'auto' }
  for k := 0 to 1 do
    if NotNull(raw[cHV[k, 0]]) or (NotNull(raw[cHV[k, 1]]) and NotNull(raw[cHV[k, 2]])) then
      Result.CellAuto[k] := True;
  ignW := not Result.CellAuto[0];
  ignH := not Result.CellAuto[1];
  TyCalMergeLayoutParam(target, raw, ignW, ignH);
  Result.Box.Width := target[0].V;
  Result.Box.Left := target[1].V;
  Result.Box.Right := target[2].V;
  Result.Box.Height := target[3].V;
  Result.Box.Top := target[4].V;
  Result.Box.Bottom := target[5].V;

  if StrOf(node.Find('orient')) = 'vertical' then Result.Orient := tcoVertical;
  d := node.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Z := Round(d.AsFloat);

  { ---- the range, as written ---- }
  d := node.Find('range');
  if (d <> nil) and (d.JSONType = jtArray) and (d.Count = 1) then d := d.Items[0];
  if d = nil then
    Result.RangeOk := False
  else if d.JSONType = jtArray then
  begin
    Result.RangeOk := d.Count >= 2;
    Result.RangeIsPair := True;
    if Result.RangeOk then
    begin
      for k := 0 to 1 do
      begin
        e := d.Items[k];
        case e.JSONType of
          jtNumber: if k = 0 then Result.RangeA := TyDataNum(e.AsFloat)
                    else Result.RangeB := TyDataNum(e.AsFloat);
          jtString:
            begin
              if k = 0 then
              begin
                Result.RangeA.Kind := dvkText;
                Result.RangeA.Text := e.AsString;
              end
              else
              begin
                Result.RangeB.Kind := dvkText;
                Result.RangeB.Text := e.AsString;
              end;
            end;
        end;
      end;
    end;
  end
  else
  begin
    { range.toString() }
    case d.JSONType of
      jtNumber: s := TyJsNumberToString(d.AsFloat);
      jtString: s := d.AsString;
      jtBoolean: if d.AsBoolean then s := 'true' else s := 'false';
    else
      s := '';
    end;
    Result.RangeOk := s <> '';
    Result.RangeIsPair := False;
    Result.RangeA.Kind := dvkText;
    Result.RangeA.Text := s;
  end;

  { ---- the cells and the split lines ---- }
  Result.Item := TyReadOptStyle(node, 'itemStyle');
  sub := ObjIn(node, 'splitLine');
  Result.SplitShow := ShowIn(sub, True);
  Result.Split := TyReadOptStyle(sub, 'lineStyle');

  { ---- the labels ---- }
  gts := nil;
  d := AOption.Find('textStyle');
  if (d <> nil) and (d.JSONType = jtObject) then gts := TJSONObject(d);
  { the global textStyle is under the day and month labels' own keys; the
    year's defaults (20, bolder) are the model's and beat it }
  ReadText(gts, Result.DayText);
  Result.DayText.HasColour := False;
  Result.MonthText := Result.DayText;

  sub := ObjIn(node, 'dayLabel');
  Result.DayShow := ShowIn(sub, True);
  if sub <> nil then
  begin
    Result.FirstDay := NumOf(sub.Find('firstDay'), 0);
    Result.DayStart := StrOf(sub.Find('position')) <> 'end';
    if sub.Find('position') <> nil then
      Result.DayStart := StrOf(sub.Find('position')) = 'start';
    d := sub.Find('margin');
    if d <> nil then
    begin
      if (d.JSONType = jtString) and (Pos('%', d.AsString) > 0) then
      begin
        Result.DayMarginPct := True;
        Result.DayMargin := TyJsToNumber(Trim(StringReplace(d.AsString, '%', '', []))) / 100;
      end
      else
        Result.DayMargin := NumOf(d, 0);
    end;
    ReadNames(sub, Result.DayNames, Result.DayArray);
    ReadText(sub, Result.DayText);
  end;

  sub := ObjIn(node, 'monthLabel');
  Result.MonthShow := ShowIn(sub, True);
  if sub <> nil then
  begin
    if sub.Find('position') <> nil then
      Result.MonthStart := StrOf(sub.Find('position')) = 'start';
    if sub.Find('align') <> nil then
      Result.MonthCentre := StrOf(sub.Find('align')) = 'center';
    d := sub.Find('margin');
    if d <> nil then Result.MonthMargin := NumOf(d, 0);
    Result.MonthFormatter := StrOf(sub.Find('formatter'));
    ReadNames(sub, Result.MonthNames, Result.MonthArray);
    ReadText(sub, Result.MonthText);
  end;

  sub := ObjIn(node, 'yearLabel');
  Result.YearShow := ShowIn(sub, True);
  if sub <> nil then
  begin
    s := StrOf(sub.Find('position'));
    if s = 'top' then Result.YearPos := tcyTop
    else if s = 'bottom' then Result.YearPos := tcyBottom
    else if s = 'left' then Result.YearPos := tcyLeft
    else if s = 'right' then Result.YearPos := tcyRight;
    d := sub.Find('margin');
    if d <> nil then Result.YearMargin := NumOf(d, 0);
    Result.YearFormatter := StrOf(sub.Find('formatter'));
    ReadText(sub, Result.YearText);
  end;
end;

{ ==================== the calendar ==================== }

{ Days since 1970-01-01 to civil fields, proleptic Gregorian (Hinnant). }
procedure CivilOf(ADays: Int64; out AY, AM, AD: Integer);
var z, era, doe, yoe, doy, mp, y: Int64;
begin
  z := ADays + 719468;
  if z >= 0 then era := z div 146097 else era := (z - 146096) div 146097;
  doe := z - era * 146097;
  yoe := (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365;
  y := yoe + era * 400;
  doy := doe - (365 * yoe + yoe div 4 - yoe div 100);
  mp := (5 * doy + 2) div 153;
  AD := doy - (153 * mp + 2) div 5 + 1;
  if mp < 10 then AM := mp + 3 else AM := mp - 9;
  if AM <= 2 then Inc(y);
  AY := y;
end;

{ Civil fields to days since 1970-01-01 (Hinnant), as wall-clock ms. }
function CivilMs(AY, AM, AD: Int64): Double;
var y, era, yoe, doy, doe, m: Int64;
begin
  y := AY;
  m := AM;
  if m <= 2 then Dec(y);
  if y >= 0 then era := y div 400 else era := (y - 399) div 400;
  yoe := y - era * 400;
  if m > 2 then doy := (153 * (m - 3) + 2) div 5 + AD - 1
  else doy := (153 * (m + 9) + 2) div 5 + AD - 1;
  doe := yoe * 365 + yoe div 4 - yoe div 100 + doy;
  Result := (era * 146097 + doe - 719468) * Int64(TyCalDayMs);
end;

function FloorDiv(A, B: Int64): Int64;
begin
  Result := A div B;
  if (A mod B <> 0) and ((A < 0) <> (B < 0)) then Dec(Result);
end;

{ JS `%` on doubles }
function JsRem(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) or IsInfinite(A) or (B = 0) then Exit(NaN);
  Result := A - B * Int(A / B);
end;

constructor TTyCalendar.Create(const ASpec: TTyCalendarSpec);
begin
  inherited Create;
  FSpec := ASpec;
  FScale := 1;
  SetUTC(False);
end;

procedure TTyCalendar.SetUTC(AValue: Boolean);
begin
  FUTC := AValue;
  { the offset the date parser applies: today's, UTC minus local }
  if FUTC then FOffsetMs := 0
  else FOffsetMs := Int64(GetLocalTimeOffset) * 60000;
end;

function TTyCalendar.ParseDate(const AValue: TTyDataValue): Double;
var ms: Double;
begin
  Result := NaN;
  case AValue.Kind of
    dvkNumber:
      if not IsNan(AValue.Num) and not IsInfinite(AValue.Num) then
        Result := TyJsRound(AValue.Num);
    dvkText:
      if TyParseDateMs(AValue.Text, ms, FUTC) then Result := ms;
  end;
end;

function TTyCalendar.DateInfo(AMs: Double): TTyCalDateInfo;
var
  w: Int64;
  dow: Integer;
begin
  Result := Default(TTyCalDateInfo);
  { parseDate: a number is new Date(Math.round(n)) -- a fraction of a
    millisecond can carry an instant into the next day }
  if not IsNan(AMs) and not IsInfinite(AMs) then AMs := TyJsRound(AMs);
  Result.Time := AMs;
  if IsNan(AMs) or IsInfinite(AMs) or (Abs(AMs) > 8.64e15) then
  begin
    Result.Day := NaN;
    Result.Midnight := NaN;
    Exit;
  end;
  Result.Valid := True;
  w := Round(AMs) - FOffsetMs;
  Result.DayNum := FloorDiv(w, TyCalDayMs);
  CivilOf(Result.DayNum, Result.Y, Result.M, Result.D);
  dow := Integer(((Result.DayNum mod 7) + 7 + 4) mod 7);
  Result.Day := Abs(JsRem(dow + 7 - FSpec.FirstDay, 7));
  Result.Midnight := Result.DayNum * TyCalDayMs + FOffsetMs;
end;

function TTyCalendar.NextNDay(AMs: Double; AN: Integer): Double;
begin
  { a wall clock has no DST, so setDate(getDate() + n) is n whole days }
  Result := AMs + Int64(AN) * TyCalDayMs;
end;

function TTyCalendar.RangeInfo(AMs0, AMs1: Double): TTyCalRangeInfo;
var
  a, b, t: TTyCalDateInfo;
  reversed: Boolean;
begin
  a := DateInfo(AMs0);
  b := DateInfo(AMs1);
  reversed := a.Time > b.Time;
  if reversed then
  begin
    t := a; a := b; b := t;
  end;
  Result.AllDay := b.DayNum - a.DayNum + 1;
  Result.Weeks := Floor((Result.AllDay + a.Day + 6) / 7);
  if reversed then Result.NthWeek := -Result.Weeks + 1
  else Result.NthWeek := Result.Weeks - 1;
  Result.FWeek := a.Day;
  Result.LWeek := b.Day;
  if reversed then
  begin
    Result.Start := b;
    Result.Stop := a;
  end
  else
  begin
    Result.Start := a;
    Result.Stop := b;
  end;
  if not (a.Valid and b.Valid) then
  begin
    Result.Weeks := NaN;
    Result.NthWeek := NaN;
  end;
end;

{ Calendar._initRangeOption: the range normalised to a [start, end] pair of
  instants, the earlier first. }
procedure TTyCalendar.InitRange(out AA, AB: Double; out AOk: Boolean);
var
  s: string;
  start, next: TTyCalDateInfo;
  y, m: Integer;

  function AllDigits(const T: string; AFrom, ACount: Integer): Boolean;
  var i: Integer;
  begin
    Result := AFrom + ACount - 1 <= Length(T);
    if not Result then Exit;
    for i := AFrom to AFrom + ACount - 1 do
      if not (T[i] in ['0'..'9']) then Exit(False);
  end;

  // `\d` AMin..AMax times at P, advancing it
  function Digits(const T: string; var P: Integer; AMin, AMax: Integer): Boolean;
  var n: Integer;
  begin
    n := 0;
    while (P <= Length(T)) and (T[P] in ['0'..'9']) and (n < AMax) do
    begin
      Inc(P);
      Inc(n);
    end;
    Result := n >= AMin;
  end;

  // /^\d{4}([\/|-]\d{1,2}){AParts}$/
  function Matches(const T: string; AParts: Integer): Boolean;
  var p, k: Integer;
  begin
    Result := False;
    if not AllDigits(T, 1, 4) then Exit;
    p := 5;
    for k := 1 to AParts do
    begin
      if (p > Length(T)) or not (T[p] in ['/', '|', '-']) then Exit;
      Inc(p);
      if not Digits(T, p, 1, 2) then Exit;
    end;
    Result := p = Length(T) + 1;
  end;

var
  ok: Boolean;
  ms: Double;
begin
  AA := NaN;
  AB := NaN;
  AOk := False;
  if not FSpec.RangeOk then Exit;
  if FSpec.RangeIsPair then
  begin
    AA := ParseDate(FSpec.RangeA);
    AB := ParseDate(FSpec.RangeB);
  end
  else
  begin
    s := FSpec.RangeA.Text;
    ok := False;
    { one year }
    if (Length(s) = 4) and AllDigits(s, 1, 4) then
    begin
      ok := TyParseDateMs(s + '-01-01', ms, FUTC);
      if ok then AA := ms;
      if TyParseDateMs(s + '-12-31', ms, FUTC) then AB := ms else AB := NaN;
      ok := True;
    end;
    { one month: its first, and the day before the next month's first }
    if Matches(s, 1) then
    begin
      if TyParseDateMs(s, ms, FUTC) then
      begin
        start := DateInfo(ms);
        y := start.Y;
        m := start.M + 1;
        if m > 12 then
        begin
          m := 1;
          Inc(y);
        end;
        next := DateInfo(CivilMs(y, m, 1) + FOffsetMs);
        AA := start.Midnight;
        AB := NextNDay(next.Midnight, -1);
      end;
      ok := True;
    end;
    { one day }
    if Matches(s, 2) then
    begin
      if TyParseDateMs(s, ms, FUTC) then
      begin
        AA := ms;
        AB := ms;
      end;
      ok := True;
    end;
    if not ok then Exit;
  end;
  if IsNan(AA) or IsNan(AB) then Exit;
  if AA > AB then
  begin
    ms := AA; AA := AB; AB := ms;
  end;
  AOk := True;
end;

procedure TTyCalendar.Resize(const AContainer: TTyRectF; APPI: Integer);
var
  a, b: Double;
  ok: Boolean;
  weeks: Double;
  n: array[0..1] of Double;
  box: TTyRawBox;
  k: Integer;

  function Scaled(const R: TTyBoxRaw): TTyBoxRaw;
  begin
    Result := R;
    if R.Kind = brNumber then Result.Num := R.Num * FScale;
  end;

begin
  FValid := False;
  if APPI > 0 then FScale := APPI / 96 else FScale := 1;
  SetUTC(FUTC);
  { the cell border's width is the inset of a cell's content }
  FLineWidth := FSpec.Item.BorderWidthLogical;
  if IsNan(FLineWidth) then FLineWidth := 1;
  FLineWidth := FLineWidth * FScale;
  InitRange(a, b, ok);
  if not ok then Exit;
  FRange := RangeInfo(a, b);
  if FRange.AllDay > cMaxDays then Exit;
  weeks := FRange.Weeks;
  if IsNan(weeks) or (weeks = 0) then weeks := 1;
  if FSpec.Orient = tcoHorizontal then
  begin
    n[0] := weeks;
    n[1] := 7;
  end
  else
  begin
    n[0] := 7;
    n[1] := weeks;
  end;
  box.Left := Scaled(FSpec.Box.Left);
  box.Right := Scaled(FSpec.Box.Right);
  box.Top := Scaled(FSpec.Box.Top);
  box.Bottom := Scaled(FSpec.Box.Bottom);
  box.Width := Scaled(FSpec.Box.Width);
  box.Height := Scaled(FSpec.Box.Height);
  for k := 0 to 1 do
    if not FSpec.CellAuto[k] then
    begin
      if k = 0 then box.Width := TyBoxRawNum(FSpec.Cell[0] * n[0] * FScale)
      else box.Height := TyBoxRawNum(FSpec.Cell[1] * n[1] * FScale);
    end;
  FRect := TyGetLayoutRect(box, AContainer.Left, AContainer.Top,
    AContainer.Right - AContainer.Left, AContainer.Bottom - AContainer.Top, []);
  if FSpec.CellAuto[0] then FSW := FRect.W / n[0] else FSW := FSpec.Cell[0] * FScale;
  if FSpec.CellAuto[1] then FSH := FRect.H / n[1] else FSH := FSpec.Cell[1] * FScale;
  FValid := True;
end;

function TTyCalendar.DatePoint(AMs: Double; AClamp: Boolean): TTyPointF;
var
  info: TTyCalDateInfo;
  nth: Double;
begin
  Result := TyPointF(NaN, NaN);
  if not FValid then Exit;
  info := DateInfo(AMs);
  if not info.Valid then Exit;
  if AClamp and not ((info.Time >= FRange.Start.Time)
    and (info.Time < FRange.Stop.Time + TyCalDayMs)) then Exit;
  nth := RangeInfo(FRange.Start.Time, info.Midnight).NthWeek;
  if FSpec.Orient = tcoVertical then
  begin
    Result.X := FRect.X + info.Day * FSW + FSW / 2;
    Result.Y := FRect.Y + nth * FSH + FSH / 2;
  end
  else
  begin
    Result.X := FRect.X + nth * FSW + FSW / 2;
    Result.Y := FRect.Y + info.Day * FSH + FSH / 2;
  end;
end;

function TTyCalendar.DateCell(AMs: Double; AClamp: Boolean): TTyCalCellLayout;
var p: TTyPointF;
begin
  p := DatePoint(AMs, AClamp);
  Result.Centre := p;
  Result.TL := TyPointF(p.X - FSW / 2, p.Y - FSH / 2);
  Result.TR := TyPointF(p.X + FSW / 2, p.Y - FSH / 2);
  Result.BR := TyPointF(p.X + FSW / 2, p.Y + FSH / 2);
  Result.BL := TyPointF(p.X - FSW / 2, p.Y + FSH / 2);
end;

{ expandOrShrinkRect on one dimension, shrinking by ADelta on both sides with
  negatives clamped: the size first, then the position }
procedure ShrinkDim(var APos, ASize: Double; ADelta: Double);
var old: Double;
begin
  if ADelta < 0 then ADelta := 0;
  old := ASize;
  ASize := ASize + (-ADelta + -ADelta);
  if ASize < 0 then
  begin
    ASize := 0;
    { delta[lt] is -ADelta: >= 0 only when it is nought }
    if -ADelta >= 0 then APos := APos + ADelta
    else if Abs(-ADelta + -ADelta) > 1e-8 then
      APos := APos + (old - 0) * (-ADelta) / (-ADelta + -ADelta);
  end
  else
    APos := APos - (-ADelta);
end;

function TTyCalendar.DateLayout(AMs: Double; AClamp: Boolean): TTyCoordLayout;
var
  p: TTyPointF;
  x, y, w, h: Double;
begin
  p := DatePoint(AMs, AClamp);
  x := p.X - FSW / 2;
  y := p.Y - FSH / 2;
  Result.Rect := TyRectF(x, y, x + FSW, y + FSH);
  w := FSW;
  h := FSH;
  ShrinkDim(x, w, FLineWidth / 2);
  ShrinkDim(y, h, FLineWidth / 2);
  Result.ContentRect := TyRectF(x, y, x + w, y + h);
end;

function TTyCalendar.CoordSysName: string;
begin
  Result := TyCalendarCoordSysName;
end;

function TTyCalendar.DimCount: Integer;
begin
  Result := 2;
end;

function TTyCalendar.GetRect: TTyRectF;
begin
  Result := TyRectF(FRect.X, FRect.Y, FRect.X + FRect.W, FRect.Y + FRect.H);
end;

function TTyCalendar.DataToPoint(const AData: array of Double): TTyPointF;
begin
  if Length(AData) = 0 then Exit(TyPointF(NaN, NaN));
  Result := DatePoint(AData[0], True);
end;

function TTyCalendar.DataToLayout(const AData: array of Double): TTyCoordLayout;
begin
  if Length(AData) = 0 then
    Result := DateLayout(NaN, True)
  else
    Result := DateLayout(AData[0], True);
end;

{ pointToDate, with upstream's first-week slip: the blank cells before the
  range answer the dates before it (its `nthWeek === 0` guard never fires,
  nthWeek being 1-based there) }
function TTyCalendar.PointToData(const APoint: TTyPointF;
  out AData: TTyDoubleArray): Boolean;
var
  nthX, nthY, nthWeek, day: Double;
  nthDay: Double;
begin
  AData := nil;
  Result := False;
  if not FValid or (FSW = 0) or (FSH = 0) then Exit;
  nthX := Floor((APoint.X - FRect.X) / FSW) + 1;
  nthY := Floor((APoint.Y - FRect.Y) / FSH) + 1;
  if FSpec.Orient = tcoVertical then
  begin
    nthWeek := nthY;
    day := nthX - 1;
  end
  else
  begin
    nthWeek := nthX;
    day := nthY - 1;
  end;
  if (nthWeek > FRange.Weeks) or ((nthWeek = 0) and (day < FRange.FWeek))
    or ((nthWeek = FRange.Weeks) and (day > FRange.LWeek)) then Exit;
  nthDay := (nthWeek - 1) * 7 - FRange.FWeek + day;
  SetLength(AData, 2);
  AData[0] := FRange.Start.Time + nthDay * TyCalDayMs;
  AData[1] := NaN;
  Result := True;
end;

function TTyCalendar.ContainPoint(const APoint: TTyPointF): Boolean;
begin
  { upstream: "Not implemented." -- so nothing on a calendar is clipped }
  Result := False;
end;

function TTyCalendar.AxisCount: Integer;
begin
  Result := 0;
end;

function TTyCalendar.GetAxis(AIndex: Integer): TTyAxis;
begin
  Result := nil;
end;

{ ==================== the picture ==================== }

type
  TPtArr = array of TTyPointF;

function MonthName(const ASpec: TTyCalendarSpec; AMonth: Integer): string;
begin
  Result := '';
  case ASpec.MonthNames of
    tcnEN: Result := cEnMonths[AMonth - 1];
    tcnZH: Result := cZhMonths[AMonth - 1];
    tcnArray:
      if AMonth - 1 <= High(ASpec.MonthArray) then
        Result := ASpec.MonthArray[AMonth - 1];
    tcnLocale: Result := TyDateTimeNames.ShortMonthNames[AMonth];
  end;
end;

{ The first character of the locale's abbreviation -- a code point, not a
  byte. A Chinese abbreviation spelled 周日 or 星期日 gives its LAST character,
  the one upstream's own ZH table holds. }
function LocaleDayLetter(AIndex: Integer): string;
var
  s: string;
  n: Integer;
begin
  s := TyDateTimeNames.ShortDayNames[AIndex + 1];
  Result := '';
  if s = '' then Exit;
  if (Copy(s, 1, 3) = '周') or (Copy(s, 1, 6) = '星期') then
  begin
    n := Length(s);
    while (n > 1) and ((Ord(s[n]) and $C0) = $80) do Dec(n);
    Exit(Copy(s, n, Length(s)));
  end;
  n := 1;
  if Ord(s[1]) >= $C0 then
    while (n < Length(s)) and ((Ord(s[n + 1]) and $C0) = $80) do Inc(n);
  Result := Copy(s, 1, n);
end;

function DayName(const ASpec: TTyCalendarSpec; AIndex: Integer): string;
begin
  Result := '';
  case ASpec.DayNames of
    tcnEN: Result := cEnDays[AIndex];
    tcnZH: Result := cZhDays[AIndex];
    tcnArray:
      if AIndex <= High(ASpec.DayArray) then Result := ASpec.DayArray[AIndex];
    tcnLocale: Result := LocaleDayLetter(AIndex);
  end;
end;

function TwoDigits(A: Integer): string;
begin
  if A < 10 then Result := '0' + IntToStr(A) else Result := IntToStr(A);
end;

function TyBuildCalendar(ACal: TTyCalendar; const AInk: TTyCalendarInk;
  const AMeasurer: ITyTextMeasurer; APPI: Integer; AList: TTyPaintList): Integer;
var
  spec: TTyCalendarSpec;
  scale, sw, sh, t, splitLw: Double;
  horiz: Boolean;
  el: TTyChartElement;
  cell: TTyCalCellLayout;
  tl, bl, fdPts: TPtArr;
  fdInfo: array of TTyCalDateInfo;
  fd: TTyCalDateInfo;
  i, k, idx, axis: Integer;
  splitStyle: TTyChartElementStyle;
  cellFill, cellStroke: TTyChartColor;
  cellLw: Double;

  procedure AddText(const AWords: string; AX, AY: Double; AH: TTyTextAnchorH;
    AV: TTyTextAnchorV; ARot: Double; const AText: TTyCalText;
    ADefColour: TTyChartColor; const ADefFont: string; ADefSize, ADefWeight: Integer);
  var
    w, h, c, s, cx, cy: Double;
    box: TTyRectF;
    fname: string;
    fsize, fweight, j: Integer;
    xs, ys: array[0..3] of Double;
  begin
    if AWords = '' then Exit;
    if IsNan(AX) or IsNan(AY) then Exit;
    fname := ADefFont;
    if AText.HasFontName then fname := AText.FontName;
    fsize := ADefSize;
    if AText.HasFontSize then fsize := AText.FontSizeLogical;
    fweight := ADefWeight;
    if AText.HasWeight then fweight := AText.FontWeight;
    AMeasurer.MeasureLine(AWords, fname, fsize, fweight, w, h);
    if (w <= 0) or (h <= 0) then Exit;
    box := TyAnchorBox(AX, AY, w, h, AH, AV);
    if ARot <> 0 then
    begin
      { the box turned about the anchor, anticlockwise on screen }
      c := Cos(ARot);
      s := Sin(ARot);
      xs[0] := box.Left; ys[0] := box.Top;
      xs[1] := box.Right; ys[1] := box.Top;
      xs[2] := box.Right; ys[2] := box.Bottom;
      xs[3] := box.Left; ys[3] := box.Bottom;
      for j := 0 to 3 do
      begin
        cx := AX + (xs[j] - AX) * c + (ys[j] - AY) * s;
        cy := AY - (xs[j] - AX) * s + (ys[j] - AY) * c;
        xs[j] := cx;
        ys[j] := cy;
      end;
      box := TyRectF(MinValue(xs), MinValue(ys), MaxValue(xs), MaxValue(ys));
    end;
    el := TyChartElement(TyShapeRect(box));
    el.Caption.Text := AWords;
    el.Caption.FontName := fname;
    el.Caption.FontSizeLogical := fsize;
    el.Caption.FontWeight := fweight;
    if AText.HasColour then el.Caption.Colour := AText.Colour
    else el.Caption.Colour := ADefColour;
    el.Caption.X := AX;
    el.Caption.Y := AY;
    el.Caption.AnchorH := AH;
    el.Caption.AnchorV := AV;
    el.Caption.RotationRad := ARot;
    el.Caption.Truncate := False;
    el.Z := spec.Z;
    el.Z2 := 30;
    el.Silent := True;
    AList.Add(el);
    Inc(Result);
  end;

  procedure AddPolyline(const APts: array of TTyPointF);
  begin
    el := TyChartElement(TyShapePolyline(APts));
    el.Style := splitStyle;
    el.Z := spec.Z;
    el.Z2 := 20;
    el.Silent := True;
    AList.Add(el);
    Inc(Result);
  end;

  { _getLinePointsOfOneWeek + addPoints }
  procedure AddPoints(AMs: Double);
  var
    pts: array[0..13] of TTyPointF;
    j, dj: Integer;
    tmp: TTyCalDateInfo;
    c: TTyCalCellLayout;
    base: TTyCalDateInfo;
  begin
    base := ACal.DateInfo(AMs);
    SetLength(fdInfo, Length(fdInfo) + 1);
    fdInfo[High(fdInfo)] := base;
    SetLength(fdPts, Length(fdPts) + 1);
    fdPts[High(fdPts)] := ACal.DateCell(AMs, False).TL;
    for j := 0 to 13 do pts[j] := TyPointF(NaN, NaN);
    for j := 0 to 6 do
    begin
      tmp := ACal.DateInfo(ACal.NextNDay(base.Time, j));
      c := ACal.DateCell(tmp.Time, False);
      dj := Trunc(tmp.Day);
      if (dj < 0) or (dj > 6) then Continue;
      pts[2 * dj] := c.TL;
      if horiz then pts[2 * dj + 1] := c.BL else pts[2 * dj + 1] := c.TR;
    end;
    SetLength(tl, Length(tl) + 1);
    tl[High(tl)] := pts[0];
    SetLength(bl, Length(bl) + 1);
    bl[High(bl)] := pts[13];
    if spec.SplitShow then AddPolyline(pts);
  end;

  procedure AddEdges(const APts: TPtArr);
  var
    rs: array[0..1] of TTyPointF;
  begin
    rs[0] := APts[0];
    rs[1] := APts[High(APts)];
    if horiz then
    begin
      rs[0].X := rs[0].X - splitLw / 2;
      rs[1].X := rs[1].X + splitLw / 2;
    end
    else
    begin
      rs[0].Y := rs[0].Y - splitLw / 2;
      rs[1].Y := rs[1].Y + splitLw / 2;
    end;
    AddPolyline(rs);
  end;

var
  pts2: array[0..1] of TTyPointF;
  xc, yc, x, y, margin, rot, startMs: Double;
  pos: TTyCalYearPos;
  name, content: string;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  tmpP: TTyPointF;
  day: Integer;
  info: TTyCalDateInfo;
begin
  Result := 0;
  if (ACal = nil) or not ACal.Valid or (AList = nil) then Exit;
  spec := ACal.Spec;
  if APPI > 0 then scale := APPI / 96 else scale := 1;
  sw := ACal.CellW;
  sh := ACal.CellH;
  horiz := spec.Orient = tcoHorizontal;

  { ---- the day cells ---- }
  if spec.Item.Color.Written and not spec.Item.Color.IsNone then
    cellFill := spec.Item.Color.Color
  else if spec.Item.Color.Written then
    cellFill := 0
  else
    cellFill := AInk.CellFill;
  if spec.Item.BorderColor.Written and not spec.Item.BorderColor.IsNone then
    cellStroke := spec.Item.BorderColor.Color
  else if spec.Item.BorderColor.Written then
    cellStroke := 0
  else
    cellStroke := AInk.CellBorder;
  cellLw := spec.Item.BorderWidthLogical;
  if IsNan(cellLw) then cellLw := 1;
  t := ACal.Range.Start.Time;
  while t <= ACal.Range.Stop.Time do
  begin
    cell := ACal.DateCell(t, False);
    el := TyChartElement(TyShapeRect(TyRectF(cell.TL.X, cell.TL.Y,
      cell.TL.X + sw, cell.TL.Y + sh)));
    el.Style.HasFill := (cellFill shr 24) <> 0;
    el.Style.FillColor := cellFill;
    el.Style.StrokeColor := cellStroke;
    el.Style.StrokeWidthLogical := cellLw;
    el.Style.DashLogical := TyDashPattern(spec.Item.Dash, spec.Item.DashLogical, cellLw);
    if not IsNan(spec.Item.Opacity) then el.Style.Alpha := spec.Item.Opacity
    else el.Style.Alpha := 1;
    el.Z := spec.Z;
    el.Z2 := 0;
    el.Silent := True;
    AList.Add(el);
    Inc(Result);
    t := ACal.NextNDay(t, 1);
  end;

  { ---- the split lines: every first of a month, and the two edges ---- }
  splitLw := spec.Split.BorderWidthLogical;
  if IsNan(splitLw) then splitLw := 1;
  splitStyle := Default(TTyChartElementStyle);
  splitStyle.HasFill := False;
  if spec.Split.Color.Written and not spec.Split.Color.IsNone then
    splitStyle.StrokeColor := spec.Split.Color.Color
  else if spec.Split.Color.Written then
    splitStyle.StrokeColor := 0
  else
    splitStyle.StrokeColor := AInk.SplitLine;
  splitStyle.StrokeWidthLogical := splitLw;
  splitStyle.DashLogical := TyDashPattern(spec.Split.Dash, spec.Split.DashLogical, splitLw);
  if not IsNan(spec.Split.Opacity) then splitStyle.Alpha := spec.Split.Opacity
  else splitStyle.Alpha := 1;
  splitLw := splitLw * scale;

  tl := nil;
  bl := nil;
  fdPts := nil;
  fdInfo := nil;
  fd := ACal.Range.Start;
  i := 0;
  while fd.Time <= ACal.Range.Stop.Time do
  begin
    AddPoints(fd.Midnight);
    { THE FIRST OF THE NEXT MONTH. Upstream first hops back to the first of
      the start's month and then does setMonth(getMonth() + 1); stepping
      straight to the next first is the same date from any day of a month }
    if fd.M = 12 then
      fd := ACal.DateInfo(CivilMs(fd.Y + 1, 1, 1) + ACal.FOffsetMs)
    else
      fd := ACal.DateInfo(CivilMs(fd.Y, fd.M + 1, 1) + ACal.FOffsetMs);
    Inc(i);
    if i > 12 * 400 then Break;
  end;
  AddPoints(ACal.DateInfo(ACal.NextNDay(ACal.Range.Stop.Time, 1)).Midnight);
  if spec.SplitShow then
  begin
    AddEdges(tl);
    AddEdges(bl);
  end;

  if AMeasurer = nil then Exit;

  { ---- the year ---- }
  if spec.YearShow then
  begin
    margin := spec.YearMargin * scale;
    pos := spec.YearPos;
    if pos = tcyDefault then
      if horiz then pos := tcyLeft else pos := tcyTop;
    pts2[0] := tl[High(tl)];
    pts2[1] := bl[0];
    xc := (pts2[0].X + pts2[1].X) / 2;
    yc := (pts2[0].Y + pts2[1].Y) / 2;
    if horiz then idx := 0 else idx := 1;
    case pos of
      tcyTop:    begin x := xc; y := pts2[idx].Y; end;
      tcyBottom: begin x := xc; y := pts2[1 - idx].Y; end;
      tcyLeft:   begin x := pts2[1 - idx].X; y := yc; end;
    else
      begin x := pts2[idx].X; y := yc; end;
    end;
    name := IntToStr(ACal.Range.Start.Y);
    if ACal.Range.Stop.Y > ACal.Range.Start.Y then
      name := name + '-' + IntToStr(ACal.Range.Stop.Y);
    if TyChartIsHandlerRef(spec.YearFormatter) then
      content := CalHandler(spec.YearFormatter, 'year', name,
        ACal.Range.Start.Y, ACal.Range.Stop.Y)
    else if spec.YearFormatter <> '' then
      content := TyCalFormatTpl(spec.YearFormatter, ['start', 'end', 'nameMap'],
        [IntToStr(ACal.Range.Start.Y), IntToStr(ACal.Range.Stop.Y), name])
    else
      content := name;
    ah := tahCentre;
    av := tavBottom;
    case pos of
      tcyBottom: begin y := y + margin; av := tavTop; end;
      tcyLeft:   x := x - margin;
      tcyRight:  begin x := x + margin; av := tavTop; end;
    else
      y := y - margin;
    end;
    if pos in [tcyLeft, tcyRight] then rot := Pi / 2 else rot := 0;
    AddText(content, x, y, ah, av, rot, spec.YearText, AInk.YearColour,
      AInk.YearFontName, TyFontSizeFromPx(20), 700);
  end;

  { ---- the months ---- }
  if spec.MonthShow then
  begin
    margin := spec.MonthMargin * scale;
    if spec.MonthStart then margin := -margin;
    if horiz then axis := 0 else axis := 1;
    for i := 0 to High(fdInfo) - 1 do
    begin
      if spec.MonthStart then tmpP := tl[i] else tmpP := bl[i];
      info := fdInfo[i];
      if spec.MonthCentre then
      begin
        if axis = 0 then tmpP.X := (fdPts[i].X + tl[i + 1].X) / 2
        else tmpP.Y := (fdPts[i].Y + tl[i + 1].Y) / 2;
      end;
      name := MonthName(spec, info.M);
      if TyChartIsHandlerRef(spec.MonthFormatter) then
        content := CalHandler(spec.MonthFormatter, 'month', name, info.Y, info.M)
      else if spec.MonthFormatter <> '' then
        content := TyCalFormatTpl(spec.MonthFormatter,
          ['yyyy', 'yy', 'MM', 'M', 'nameMap'],
          [IntToStr(info.Y), Copy(IntToStr(info.Y), 3, MaxInt),
           TwoDigits(info.M), IntToStr(info.M), name])
      else
        content := name;
      x := tmpP.X;
      y := tmpP.Y;
      ah := tahLeft;
      av := tavTop;
      if horiz then
      begin
        y := y + margin;
        if spec.MonthCentre then ah := tahCentre;
        if spec.MonthStart then av := tavBottom;
      end
      else
      begin
        x := x + margin;
        if spec.MonthCentre then av := tavMiddle;
        if spec.MonthStart then ah := tahRight;
      end;
      AddText(content, x, y, ah, av, 0, spec.MonthText, AInk.LabelColour,
        AInk.LabelFontName, AInk.LabelFontSizeLogical, AInk.LabelFontWeight);
    end;
  end;

  { ---- the days of the week ---- }
  if spec.DayShow then
  begin
    startMs := ACal.NextNDay(ACal.Range.Stop.Time, 7 - Trunc(ACal.Range.LWeek));
    if spec.DayMarginPct then margin := spec.DayMargin * Min(sh, sw)
    else margin := spec.DayMargin * scale;
    if spec.DayStart then
    begin
      startMs := ACal.NextNDay(ACal.Range.Start.Time, -(7 + Trunc(ACal.Range.FWeek)));
      margin := -margin;
    end;
    for i := 0 to 6 do
    begin
      info := ACal.DateInfo(ACal.NextNDay(startMs, i));
      tmpP := ACal.DateCell(info.Time, False).Centre;
      day := Trunc(Abs(JsRem(i + spec.FirstDay, 7)));
      x := tmpP.X;
      y := tmpP.Y;
      ah := tahCentre;
      av := tavMiddle;
      if horiz then
      begin
        if spec.DayStart then
        begin
          x := x + margin + sw / 2;
          ah := tahRight;
        end
        else
        begin
          x := x + margin - sw / 2;
          ah := tahLeft;
        end;
      end
      else
      begin
        if spec.DayStart then
        begin
          y := y + margin + sh / 2;
          av := tavBottom;
        end
        else
        begin
          y := y + margin - sh / 2;
          av := tavTop;
        end;
      end;
      AddText(DayName(spec, day), x, y, ah, av, 0, spec.DayText,
        AInk.LabelColour, AInk.LabelFontName, AInk.LabelFontSizeLogical,
        AInk.LabelFontWeight);
    end;
  end;
end;

end.
