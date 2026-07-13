unit test.builtinskins;
{ The structural skins (classic, xp, office, win11, …) are compiled IN from themes/builtin/*.tycss
  via the GENERATED unit tyControls.BuiltinSkins. This guard keeps the two in sync: every
  themes/builtin/<name>.tycss file must have a matching compiled-in skin whose registered CSS is
  line-for-line identical. If you edit a themes/builtin/*.tycss and forget to re-run
  gen-builtinskins.ps1 (or vice-versa), this test fails and names the drifting skin. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.ThemeRegistry, tyControls.BuiltinSkins;
type
  TBuiltinSkinsSyncTest = class(TTestCase)
  private
    function BuiltinDir: string;
    function NormLines(const S: string): string;
  published
    procedure TestNamesMatchDirectory;
    procedure TestEachSkinMatchesItsFile;
  end;

implementation

function TBuiltinSkinsSyncTest.BuiltinDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim
            + 'builtin' + PathDelim;
end;

{ Normalise CSS for comparison the same way the generator does: split into lines (any EOL),
  strip trailing whitespace per line, drop trailing blank lines. This makes the compiled-in
  const (LineEnding-joined) and the on-disk file (CRLF/LF, maybe a trailing newline) comparable. }
function TBuiltinSkinsSyncTest.NormLines(const S: string): string;
var sl: TStringList; i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Text := S;
    for i := 0 to sl.Count - 1 do sl[i] := TrimRight(sl[i]);
    while (sl.Count > 0) and (Trim(sl[sl.Count - 1]) = '') do sl.Delete(sl.Count - 1);
    Result := sl.Text;
  finally sl.Free; end;
end;

procedure TBuiltinSkinsSyncTest.TestNamesMatchDirectory;
{ Every themes/builtin/*.tycss must be represented in TyBuiltinSkinNames, and vice-versa —
  no orphan file (forgot to regenerate) and no phantom name (deleted a file). }
var
  names: TStringArray;
  onDisk: TStringList;
  sr: TSearchRec;
  i: Integer;
begin
  TyRegisterBuiltinSkins;
  names := TyBuiltinSkinNames;
  onDisk := TStringList.Create;
  try
    onDisk.Sorted := True;
    if FindFirst(BuiltinDir + '*.tycss', faAnyFile, sr) = 0 then
      try
        repeat
          if (sr.Attr and faDirectory) = 0 then
            onDisk.Add(ChangeFileExt(sr.Name, ''));
        until FindNext(sr) <> 0;
      finally
        FindClose(sr);
      end;
    AssertTrue('themes/builtin/ has skin files', onDisk.Count > 0);
    AssertEquals('compiled-in skin count == themes/builtin/ file count',
      onDisk.Count, Length(names));
    for i := 0 to High(names) do
      AssertTrue('compiled-in skin has a file: ' + names[i],
        onDisk.IndexOf(names[i]) >= 0);
  finally
    onDisk.Free;
  end;
end;

procedure TBuiltinSkinsSyncTest.TestEachSkinMatchesItsFile;
{ Each compiled-in skin's registered CSS must be line-for-line identical to its source file. }
var
  names: TStringArray;
  i: Integer;
  css, fileText, failed: string;
  f: TStringList;
begin
  TyRegisterBuiltinSkins;
  names := TyBuiltinSkinNames;
  failed := '';
  f := TStringList.Create;
  try
    for i := 0 to High(names) do
    begin
      if not TyResolveThemeCss(names[i], css) then
      begin
        failed := failed + names[i] + ' <not registered>; ';
        Continue;
      end;
      f.LoadFromFile(BuiltinDir + names[i] + '.tycss');
      fileText := f.Text;
      if NormLines(css) <> NormLines(fileText) then
        failed := failed + names[i] + ' <compiled-in CSS differs from file — re-run gen-builtinskins.ps1>; ';
    end;
  finally
    f.Free;
  end;
  AssertEquals('every compiled-in skin matches its themes/builtin/ file', '', failed);
end;

initialization
  RegisterTest(TBuiltinSkinsSyncTest);
end.
