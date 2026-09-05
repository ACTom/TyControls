unit tyControls.Design.AdvChart.Descs;
{$mode objfpc}{$H+}
{ The option catalog's EN and ZH descriptions, for the design-time editor.

  WHY THEY LIVE HERE AND NOT IN THE GENERATED CATALOG. The catalog unit is a
  RUNTIME unit and the descriptions are 194 KB of mostly-CJK prose that nothing
  at runtime reads. Compiling them into the runtime package would put a fifth of
  a megabyte of documentation into every application that draws a chart.

  WHY A RESOURCE AND NOT tools/advchart/catalog.json. make-release.ps1 excludes
  tools/ from the archive, so an installed copy would find no file and the editor
  would quietly show nothing -- the worst failure shape for a feature whose whole
  job is to explain things.

  The per-node INDICES are already in the generated .pas, as DescEn and DescZh.
  Only the pool travels here. }
interface

{ The English and Chinese text for a catalog node, or '' when the node carries
  none. Both are safe before the pool has loaded; the first call loads it. }
function TyOptDescEn(ANode: Integer): string;
function TyOptDescZh(ANode: Integer): string;

{ The description in the IDE's own language: Chinese when the environment says
  so and a Chinese text exists, English otherwise. English is the fallback
  rather than an empty box, because a description in the wrong language still
  says what the option does. }
function TyOptDesc(ANode: Integer): string;

{ How many strings the pool holds. 0 means it failed to load, which is worth
  being able to assert. }
function TyOptDescCount: Integer;

implementation

uses
  SysUtils, Classes, LResources, fpjson, jsonparser,
  tyControls.AdvChart.Catalog;

var
  GPool: array of string;
  GLoaded: Boolean = False;

procedure LoadPool;
var
  res: TLResource;
  data: TJSONData;
  arr: TJSONArray;
  i: Integer;
begin
  GLoaded := True;
  res := LazarusResources.Find('TyAdvChartDescs');
  if res = nil then Exit;
  data := nil;
  try
    { res.Value is the raw UTF-8 bytes exactly as they were packed. }
    data := GetJSON(res.Value);
    if not (data is TJSONArray) then Exit;
    arr := TJSONArray(data);
    SetLength(GPool, arr.Count);
    for i := 0 to arr.Count - 1 do
      GPool[i] := arr.Items[i].AsString;
  except
    { A broken pool means no descriptions, never a broken IDE. }
    SetLength(GPool, 0);
  end;
  data.Free;
end;

function PoolAt(AIndex: Integer): string;
begin
  if not GLoaded then LoadPool;
  if (AIndex < 0) or (AIndex > High(GPool)) then Exit('');
  Result := GPool[AIndex];
end;

function TyOptDescCount: Integer;
begin
  if not GLoaded then LoadPool;
  Result := Length(GPool);
end;

function TyOptDescEn(ANode: Integer): string;
begin
  Result := '';
  if (ANode < 0) or (ANode > High(TyOptNodes)) then Exit;
  Result := PoolAt(TyOptNodes[ANode].DescEn);
end;

function TyOptDescZh(ANode: Integer): string;
begin
  Result := '';
  if (ANode < 0) or (ANode > High(TyOptNodes)) then Exit;
  Result := PoolAt(TyOptNodes[ANode].DescZh);
end;

function TyOptDesc(ANode: Integer): string;
var lang: string;
begin
  lang := LowerCase(GetEnvironmentVariable('LANG'));
  if lang = '' then lang := LowerCase(GetEnvironmentVariable('LANGUAGE'));
  if Pos('zh', lang) = 1 then
  begin
    Result := TyOptDescZh(ANode);
    if Result <> '' then Exit;
  end;
  Result := TyOptDescEn(ANode);
end;

initialization
  { AN .lrs IS A SEQUENCE OF STATEMENTS, so it has to be included inside a body.
    At unit level the compiler reads `LazarusResources.Add` as a declaration and
    reports a syntax error on the dot -- which is what it did. The icons
    resource next door is included inside Register for the same reason.

    An initialization section rather than inside LoadPool: registering is a
    one-off, and the first reader has to find it already done. }
  {$I tycontrols_advchart_desc.lrs}

end.
