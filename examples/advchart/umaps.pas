unit umaps;
{$mode objfpc}{$H+}
{ The maps the gallery's examples register before they draw.

  An ECharts page fetches its GeoJSON and calls echarts.registerMap itself; the
  harvested option keeps only the map's NAME, so without this the geo examples
  draw an empty view. maps/maps.json says which file holds which name (and the
  specialAreas the example passed along with it); a map is read the first time
  an option asks for it, so starting the demo costs nothing.

  The SVG maps of the gallery are not here: TyChartRegisterMap takes GeoJSON
  only, and those examples keep saying their map is not registered. }
interface

{ Register, from AMapsDir, every map AOptionText asks for that is listed there
  and not registered yet. Quietly does nothing for text that does not parse or
  a map that is not in the list. }
procedure RegisterGalleryMapsFor(const AOptionText, AMapsDir: string);

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

procedure RegisterGalleryMapsFor(const AOptionText, AMapsDir: string);
var
  opt: TTyChartOption;
  missing: TTyGeoMissingMapArray;
  idx, entry: TJSONObject;
  d: TJSONData;
  i: Integer;
  special: string;
begin
  if AMapsDir = '' then Exit;
  try
    idx := MapsIndex(AMapsDir);
  except
    { a broken index is the demo's problem, not the chart's }
    Exit;
  end;
  if idx = nil then Exit;
  d := idx.Find('maps');
  if not (d is TJSONObject) then Exit;
  idx := TJSONObject(d);
  opt := TTyChartOption.Create;
  try
    if not opt.SetOptionText(AOptionText) then Exit;
    missing := TyGeoUnregisteredMaps(opt);
    for i := 0 to High(missing) do
    begin
      if TyChartMapRegistered(missing[i].MapName) then Continue;
      d := idx.Find(missing[i].MapName);
      if not (d is TJSONObject) then Continue;
      entry := TJSONObject(d);
      if not FileExists(AMapsDir + entry.Get('file', '')) then Continue;
      special := '';
      d := entry.Find('specialAreas');
      if d is TJSONObject then special := d.AsJSON;
      TyChartRegisterMap(missing[i].MapName,
        ReadUtf8(AMapsDir + entry.Get('file', '')), special);
    end;
  finally
    opt.Free;
  end;
end;

finalization
  FreeAndNil(GIndex);
end.
