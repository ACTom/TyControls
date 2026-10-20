unit test.advchart.gallerytext;
{$mode objfpc}{$H+}
{ [R2-J2] THE GALLERY AS THE ORACLES BEFORE R2-J2 READ IT.

  Since R2-J2 the harvest writes every function of a page as a name
  ('@<id>.<key>', '@<id>.<key>#2'); before, only a renderItem and a
  projection were named and every other function was dropped. The suites
  whose fixtures feed a gallery file to upstream as it stands (markers,
  matrix, series on a calendar, sunburst, treemap, the dataZoom slider)
  recorded what upstream draws WITHOUT those functions, so they read the
  file without them -- as their oracles do
  (tools/advchart-oracle/gallery-functions.js). What the functions do is
  test.advchart.galleryrenderitem's TAdvChartGalleryCallbackOracleTest. A
  renderItem's name ('@<id>', '@<id>#2') and a projection's
  ('@<id>.project' / '.unproject') stay. }
interface
uses SysUtils, fpjson;

{ '@<id>.<key>' or '@<id>.<key>#<n>' under any key but project / unproject }
function IsGalleryFunctionRef(const AKey: string; AValue: TJSONData): Boolean;
{ every such key taken out of AData, at any depth; answers AData }
function GalleryWithoutFunctions(AData: TJSONData): TJSONData;

implementation

function IsGalleryFunctionRef(const AKey: string; AValue: TJSONData): Boolean;
var
  s: string;
  i, dot: Integer;
begin
  Result := False;
  if (AValue = nil) or (AValue.JSONType <> jtString) then Exit;
  if (AKey = 'project') or (AKey = 'unproject') then Exit;
  s := AValue.AsString;
  if (Length(s) < 4) or (s[1] <> '@') then Exit;
  { the id: letters, digits, '_' and '-'; then '.', the key (letters), and
    an optional '#' and digits }
  dot := Pos('.', s);
  if dot <= 2 then Exit;
  for i := 2 to dot - 1 do
    if not (s[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then Exit;
  i := dot + 1;
  if (i > Length(s)) or not (s[i] in ['A'..'Z', 'a'..'z']) then Exit;
  while (i <= Length(s)) and (s[i] in ['A'..'Z', 'a'..'z']) do Inc(i);
  if i > Length(s) then Exit(True);
  if s[i] <> '#' then Exit;
  Inc(i);
  if i > Length(s) then Exit;
  while (i <= Length(s)) and (s[i] in ['0'..'9']) do Inc(i);
  Result := i > Length(s);
end;

function GalleryWithoutFunctions(AData: TJSONData): TJSONData;
var i: Integer;
begin
  Result := AData;
  if AData is TJSONObject then
  begin
    for i := TJSONObject(AData).Count - 1 downto 0 do
      if IsGalleryFunctionRef(TJSONObject(AData).Names[i], TJSONObject(AData).Items[i]) then
        TJSONObject(AData).Delete(i)
      else
        GalleryWithoutFunctions(TJSONObject(AData).Items[i]);
  end
  else if AData is TJSONArray then
    for i := 0 to TJSONArray(AData).Count - 1 do
      GalleryWithoutFunctions(TJSONArray(AData).Items[i]);
end;

end.
