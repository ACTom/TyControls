unit umaps;
{$mode objfpc}{$H+}
{ The maps the gallery's examples register before they draw.

  An ECharts page fetches its GeoJSON and calls echarts.registerMap itself; the
  harvested option keeps only the map's NAME, so without this the geo examples
  draw an empty view. maps/maps.json says which file holds which name (and the
  specialAreas the example passed along with it); a map is read the first time
  an option asks for it, so starting the demo costs nothing.

  An SVG map is registered the same way: TyChartRegisterMap takes the
  markup as it is (upstream's registerMap(name, {svg})). Three of the
  gallery's seven SVG maps are shipped; the others have no recorded licence
  (THIRD-PARTY-NOTICES.md) and are picked up from maps/ as <name>.svg when a
  user puts them there.

  MAPS THAT DRAW NATIONAL BORDERS ARE NOT SHIPPED (china, world, HK; the
  "notShipped" list of maps.json). Borders are disputed, and some places
  require published maps to be reviewed -- mainland China, for one, under its
  Surveying and Mapping Law and its Map Management Regulations -- so neither the
  library nor the demo includes one. A user who has a suitable file drops it in
  maps/ as <name>.json (or <name>.geo.json) and it is picked up like the
  others; until then the demo says why the example is empty. }
interface

{ Register, from AMapsDir, every map AOptionText asks for that is listed there
  and not registered yet. Quietly does nothing for text that does not parse or
  a map that is not in the list. }
procedure RegisterGalleryMapsFor(const AOptionText, AMapsDir: string);

{ The maps AOptionText asks for that are still not registered and are on the
  "notShipped" list of AMapsDir's maps.json, comma-separated; '' for none. }
function BorderMapsMissing(const AOptionText, AMapsDir: string): string;

implementation

uses
  Classes, SysUtils, fpjson, jsonparser,
  tyControls.AdvChart.Option, tyControls.AdvChart.Geo;

var
  GIndex: TJSONObject = nil;
  GIndexDir: string = '';

function ReadUtf8(const AFile: string): string;
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

function MapsIndex(const AMapsDir: string): TJSONObject;
var d: TJSONData;
begin
  if (GIndex <> nil) and (GIndexDir = AMapsDir) then Exit(GIndex);
  FreeAndNil(GIndex);
  GIndexDir := AMapsDir;
  if FileExists(AMapsDir + 'maps.json') then
  begin
    d := GetJSON(ReadUtf8(AMapsDir + 'maps.json'));
    if d is TJSONObject then GIndex := TJSONObject(d) else d.Free;
  end;
  Result := GIndex;
end;

function MissingMaps(const AOptionText: string): TTyGeoMissingMapArray;
var opt: TTyChartOption;
begin
  Result := nil;
  opt := TTyChartOption.Create;
  try
    if opt.SetOptionText(AOptionText) then
      Result := TyGeoUnregisteredMaps(opt);
  finally
    opt.Free;
  end;
end;

procedure RegisterGalleryMapsFor(const AOptionText, AMapsDir: string);
var
  missing: TTyGeoMissingMapArray;
  idx, entry: TJSONObject;
  d: TJSONData;
  i: Integer;
  special, fn: string;
begin
  if AMapsDir = '' then Exit;
  idx := nil;
  try
    idx := MapsIndex(AMapsDir);
  except
    { a broken index is the demo's problem, not the chart's }
    idx := nil;
  end;
  if idx <> nil then
  begin
    d := idx.Find('maps');
    if d is TJSONObject then idx := TJSONObject(d) else idx := nil;
  end;
  missing := MissingMaps(AOptionText);
  for i := 0 to High(missing) do
  begin
    if TyChartMapRegistered(missing[i].MapName) then Continue;
    fn := '';
    special := '';
    if idx <> nil then
    begin
      d := idx.Find(missing[i].MapName);
      if d is TJSONObject then
      begin
        entry := TJSONObject(d);
        fn := entry.Get('file', '');
        d := entry.Find('specialAreas');
        if d is TJSONObject then special := d.AsJSON;
      end;
    end;
    { NOT LISTED: a file the user put here under the map's own name }
    if (fn = '') or not FileExists(AMapsDir + fn) then
    begin
      fn := missing[i].MapName + '.json';
      if not FileExists(AMapsDir + fn) then fn := missing[i].MapName + '.geo.json';
      if not FileExists(AMapsDir + fn) then fn := missing[i].MapName + '.svg';
      if not FileExists(AMapsDir + fn) then Continue;
    end;
    TyChartRegisterMap(missing[i].MapName, ReadUtf8(AMapsDir + fn), special);
  end;
end;

function BorderMapsMissing(const AOptionText, AMapsDir: string): string;
var
  missing: TTyGeoMissingMapArray;
  idx: TJSONObject;
  list: TJSONArray;
  d: TJSONData;
  i, j: Integer;
begin
  Result := '';
  if AMapsDir = '' then Exit;
  try
    idx := MapsIndex(AMapsDir);
  except
    Exit;
  end;
  if idx = nil then Exit;
  d := idx.Find('notShipped');
  if not (d is TJSONArray) then Exit;
  list := TJSONArray(d);
  missing := MissingMaps(AOptionText);
  for i := 0 to High(missing) do
  begin
    if TyChartMapRegistered(missing[i].MapName) then Continue;
    for j := 0 to list.Count - 1 do
      if list.Items[j].AsString = missing[i].MapName then
      begin
        if Pos('"' + missing[i].MapName + '"', Result) > 0 then Break;
        if Result <> '' then Result := Result + ', ';
        Result := Result + '"' + missing[i].MapName + '"';
        Break;
      end;
  end;
end;

finalization
  FreeAndNil(GIndex);
end.
