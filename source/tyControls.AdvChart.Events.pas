unit tyControls.AdvChart.Events;
{$mode objfpc}{$H+}
{ Chart-level mouse events and the query that filters them -- upstream's
  `chart.on(type, [query], handler)`.

  THE EVENT is a record rather than a string of JavaScript: the type
  ('click', 'dblclick', 'mousedown', 'mouseup', 'mousemove', 'mouseover',
  'mouseout', 'globalout', 'contextmenu'), the params upstream hands a handler
  (its getDataParams for a series item, a component's own for a title, a
  legend item or an axis label), and the pointer's offset. globalout carries
  no params at all, which is HasParams False.

  THE QUERY is ECEventProcessor's, parsed once when a handler is registered:
    a string is `mainType` or `mainType.subType` -- an empty part constrains
      nothing, so '' and 'series.' match every event;
    an object (written as JSON text here) turns every key ending in Index,
      Name or Id into the component main type plus that condition -- a null
      value still sets the main type -- takes name, dataIndex and dataType as
      conditions on the event, and ignores every other key.
  It is matched against the MODEL the event came from (a marker's is its host
  series'), with strict equality, and passes unconditionally where there is
  no model: globalout.

  LCL-free: SysUtils, fpjson and the Handlers unit. }
interface
uses
  SysUtils, fpjson, jsonparser,
  tyControls.AdvChart.Handlers;

type
  TTyChartEvent = record
    EventType: string;
    HasParams: Boolean;
    Params: TTyChartCallbackParams;
    { the pointer, in the control's client pixels; globalout has none }
    HasOffset: Boolean;
    OffsetX, OffsetY: Integer;
  end;

  TTyChartEventHandler = procedure(Sender: TObject;
    const AEvent: TTyChartEvent) of object;

  { What an event's model is, for the query to be matched against. }
  TTyEventModel = record
    Valid: Boolean;
    MainType, SubType: string;
    Index: Integer;
    Name, Id: string;
  end;

  TTyEventQueryValue = record
    Has: Boolean;
    IsNumber: Boolean;
    Num: Double;
    Str: string;
  end;

  TTyEventQuery = record
    MainType, SubType: string;
    Index, Name, Id: TTyEventQueryValue;
    DataName, DataIndex, DataType: TTyEventQueryValue;
  end;

{ AQuery as written: '' (no query), a class type ('series.bar'), or a JSON
  object ('{"seriesIndex": 1}'). A JSON text that does not parse is taken as
  a class type, as a string would be. }
function TyEventQueryOf(const AQuery: string): TTyEventQuery;

{ ECEventProcessor.filter }
function TyEventQueryMatches(const AQuery: TTyEventQuery;
  const AModel: TTyEventModel; const AEvent: TTyChartEvent): Boolean;

{ The nine the chart emits, lowercased as upstream lowercases a name it is
  given; '' for one it does not know. }
function TyChartEventTypeOf(const AName: string): string;

implementation

function TyChartEventTypeOf(const AName: string): string;
const
  cTypes: array[0..8] of string = ('click', 'dblclick', 'mousedown', 'mouseup',
    'mousemove', 'mouseover', 'mouseout', 'globalout', 'contextmenu');
var i: Integer;
begin
  Result := LowerCase(AName);
  for i := 0 to High(cTypes) do
    if Result = cTypes[i] then Exit;
  Result := '';
end;

function ValueOf(AData: TJSONData): TTyEventQueryValue;
begin
  Result := Default(TTyEventQueryValue);
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  Result.Has := True;
  if AData.JSONType = jtNumber then
  begin
    Result.IsNumber := True;
    Result.Num := AData.AsFloat;
  end
  else if AData.JSONType = jtString then
    Result.Str := AData.AsString
  else
    { a boolean, an object: never strictly equal to anything an event holds }
    Result.Str := #0 + AData.AsJSON;
end;

function TyEventQueryOf(const AQuery: string): TTyEventQuery;
const
  cSuffix: array[0..2] of string = ('Index', 'Name', 'Id');
var
  d: TJSONData;
  o: TJSONObject;
  k, s, p: Integer;
  key, main: string;
  v: TTyEventQueryValue;
begin
  Result := Default(TTyEventQuery);
  s := Length(AQuery);
  d := nil;
  if (s > 0) and (Trim(AQuery)[1] = '{') then
    try
      d := GetJSON(AQuery);
    except
      d := nil;
    end;
  if not (d is TJSONObject) then
  begin
    d.Free;
    { parseClassType: 'main.sub'; an empty part is no constraint }
    p := Pos('.', AQuery);
    if p > 0 then
    begin
      Result.MainType := Copy(AQuery, 1, p - 1);
      Result.SubType := Copy(AQuery, p + 1, MaxInt);
    end
    else
      Result.MainType := AQuery;
    Exit;
  end;
  o := TJSONObject(d);
  try
    for k := 0 to o.Count - 1 do
    begin
      key := o.Names[k];
      v := ValueOf(o.Items[k]);
      for s := 0 to High(cSuffix) do
      begin
        p := Length(key) - Length(cSuffix[s]) + 1;
        if (p > 1) and (Copy(key, p, MaxInt) = cSuffix[s]) then
        begin
          main := Copy(key, 1, p - 1);
          if main <> 'data' then
          begin
            Result.MainType := main;
            case s of
              0: Result.Index := v;
              1: Result.Name := v;
              2: Result.Id := v;
            end;
          end;
        end;
      end;
      if key = 'name' then Result.DataName := v
      else if key = 'dataIndex' then Result.DataIndex := v
      else if key = 'dataType' then Result.DataType := v;
    end;
  finally
    o.Free;
  end;
end;

function SameStr(const AQ: TTyEventQueryValue; const AHost: string;
  AHostHas: Boolean): Boolean;
begin
  if not AQ.Has then Exit(True);
  Result := AHostHas and not AQ.IsNumber and (AQ.Str = AHost);
end;

function SameNum(const AQ: TTyEventQueryValue; AHost: Integer;
  AHostHas: Boolean): Boolean;
begin
  if not AQ.Has then Exit(True);
  Result := AHostHas and AQ.IsNumber and (AQ.Num = AHost);
end;

function TyEventQueryMatches(const AQuery: TTyEventQuery;
  const AModel: TTyEventModel; const AEvent: TTyChartEvent): Boolean;
begin
  { for globalout: nothing to check against }
  if not AModel.Valid then Exit(True);
  Result := ((AQuery.MainType = '') or (AQuery.MainType = AModel.MainType))
    and ((AQuery.SubType = '') or (AQuery.SubType = AModel.SubType))
    and SameNum(AQuery.Index, AModel.Index, True)
    and SameStr(AQuery.Name, AModel.Name, True)
    and SameStr(AQuery.Id, AModel.Id, AModel.Id <> '')
    and SameStr(AQuery.DataName, AEvent.Params.Name, AEvent.HasParams)
    and SameNum(AQuery.DataIndex, AEvent.Params.RawDataIndex,
      AEvent.HasParams and (AEvent.Params.RawDataIndex >= 0))
    and SameStr(AQuery.DataType, AEvent.Params.DataType,
      AEvent.HasParams and (AEvent.Params.DataType <> ''));
end;

end.
