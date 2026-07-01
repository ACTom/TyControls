unit tyControls.Dialogs.SelectPath;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;

function TySubdirectories(const APath: string): TStringArray;
function TyPathHasSubdir(const APath: string): Boolean;
function TyDriveRoots: TStringArray;

implementation

function TySubdirectories(const APath: string): TStringArray;
var
  sr: TSearchRec;
  list: TStringList;
  base: string;
  i: Integer;
begin
  Result := nil;
  list := TStringList.Create;
  try
    list.CaseSensitive := False;
    base := IncludeTrailingPathDelimiter(APath);
    if FindFirst(base + '*', faDirectory, sr) = 0 then
    try
      repeat
        if ((sr.Attr and faDirectory) <> 0) and (sr.Name <> '.') and (sr.Name <> '..') then
          list.Add(sr.Name);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
    list.Sort;   // case-insensitive because CaseSensitive := False
    SetLength(Result, list.Count);
    for i := 0 to list.Count - 1 do
      Result[i] := list[i];
  finally
    list.Free;
  end;
end;

function TyPathHasSubdir(const APath: string): Boolean;
begin
  Result := Length(TySubdirectories(APath)) > 0;
end;

function TyDriveRoots: TStringArray;
{$IFDEF MSWINDOWS}
var
  c: Char;
  n: Integer;
begin
  Result := nil;
  n := 0;
  for c := 'A' to 'Z' do
    if DirectoryExists(c + ':\') then
    begin
      SetLength(Result, n + 1);
      Result[n] := c + ':\';
      Inc(n);
    end;
end;
{$ELSE}
begin
  SetLength(Result, 1);
  Result[0] := '/';
end;
{$ENDIF}

end.
