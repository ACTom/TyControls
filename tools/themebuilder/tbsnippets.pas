unit tbsnippets;
{ "Use it in a program": the code that puts the theme on an application, in the three ways
  the library offers -- from the .tycss file next to the program, from a theme bundle (a
  folder, or a zip for a theme that refers to no other file), and compiled in, registered
  under a name (the text becomes a Pascal function).

  Every snippet goes in the main form's OnCreate and ends with ApplyChromeTheme, as the
  examples do. A bundle is registered under a name and chosen with ThemeName, never loaded
  into the model by hand (Model.LoadFromSource): a density change reloads the controller's
  theme layer from ThemeFile / ThemeName, and a theme put in any other way would be dropped.

  The snippets are compiled: tests/test.themebuilder.snippets.pas holds each one as real code
  in a TTyForm, and a test compares it line by line with what this unit produces -- change
  a snippet here and that test goes red until the real code is changed with it. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils;

resourcestring
  rsTbSnippetWhere = 'in your main form (a TTyForm):';

type
  TTbSnippetKind = (tsnFile, tsnFolder, tsnZip, tsnRegister);

{ the name a theme is registered under: the file's name, else the built-in theme it is based
  on, else 'mytheme'; lower case, runs of anything but a-z 0-9 _ - made one '-' }
function TbSnippetThemeName(const AFileName, ABasedOn: string): string;
function TbSnippetUses(AKind: TTbSnippetKind): string;          { 'tyControls.Controller, ...' }
function TbSnippetBody(AKind: TTbSnippetKind; const AName, AFileName: string): string;
{ ACss as a function returning it: one quoted line per line, 200-byte pieces at most (never
  cut inside a UTF-8 character), LineEnding between lines and after the last when ACss ends
  with a line break }
function TbPascalCssFunction(const AFuncName, ACss: string): string;
{ what the window shows: the uses line, where it goes, (the function,) the body }
function TbSnippet(AKind: TTbSnippetKind; const AName, AFileName, ACss: string): string;

implementation

const
  cPieceMax = 200;

function TbPascalQuote(const S: string): string;
begin
  Result := StringReplace(S, '''', '''''', [rfReplaceAll]);
end;

function TbSnippetThemeName(const AFileName, ABasedOn: string): string;
var
  s: string;
  i: Integer;
  dash: Boolean;
begin
  if AFileName <> '' then
  begin
    { the name without its extension -- '.tycss' alone is all extension (ChangeFileExt
      keeps a name that starts with its only dot) }
    s := ExtractFileName(AFileName);
    i := LastDelimiter('.', s);
    if i > 0 then
      s := Copy(s, 1, i - 1);
  end
  else
    s := ABasedOn;
  s := LowerCase(s);
  Result := '';
  dash := False;
  for i := 1 to Length(s) do
    if s[i] in ['a'..'z', '0'..'9', '_', '-'] then
    begin
      Result := Result + s[i];
      dash := False;
    end
    else if not dash then
    begin
      Result := Result + '-';
      dash := True;
    end;
  while (Result <> '') and (Result[1] = '-') do
    Delete(Result, 1, 1);
  while (Result <> '') and (Result[Length(Result)] = '-') do
    SetLength(Result, Length(Result) - 1);
  if Result = '' then
    Result := 'mytheme';
end;

function TbSnippetUses(AKind: TTbSnippetKind): string;
begin
  case AKind of
    tsnFile: Result := 'tyControls.Controller';
    tsnZip: Result := 'tyControls.Controller, tyControls.ThemeRegistry, tyControls.ThemeBundle';
  else
    Result := 'tyControls.Controller, tyControls.ThemeRegistry';
  end;
end;

function TbSnippetBody(AKind: TTbSnippetKind; const AName, AFileName: string): string;
var
  n, f: string;

  procedure Line(const S: string);
  begin
    if Result <> '' then
      Result := Result + LineEnding;
    Result := Result + S;
  end;

begin
  Result := '';
  n := TbPascalQuote(AName);
  f := TbPascalQuote(AFileName);
  case AKind of
    tsnFile:
      begin
        Line('begin');
        Line('  TyDefaultController.ThemeFile := ExtractFilePath(ParamStr(0)) + ''' + f + ''';');
      end;
    tsnFolder:
      begin
        Line('begin');
        Line('  TyRegisterThemeFolder(''' + n + ''', ExtractFilePath(ParamStr(0)) + ''' + n + ''');');
        Line('  TyDefaultController.ThemeName := ''' + n + ''';');
      end;
    tsnZip:
      begin
        Line('var');
        Line('  bundle: ITyThemeSource;');
        Line('begin');
        Line('  bundle := TTyThemeZipSource.Create(ExtractFilePath(ParamStr(0)) + ''' + n + '.zip'');');
        Line('  TyRegisterThemeCss(''' + n + ''', bundle.RootCss);');
        Line('  TyDefaultController.ThemeName := ''' + n + ''';');
      end;
    tsnRegister:
      begin
        Line('begin');
        Line('  TyRegisterThemeCss(''' + n + ''', ThemeCss);');
        Line('  TyDefaultController.ThemeName := ''' + n + ''';');
      end;
  end;
  Line('  ApplyChromeTheme(TyDefaultController);');
  Line('end;');
end;

{ the lines of S, broken at LF, CRLF or a lone CR; ATrailing: S ends with a break (which
  then makes no empty last line) }
function SplitLines(const S: string; out ATrailing: Boolean): TStringArray;
var
  i, start, n: Integer;
begin
  Result := nil;
  ATrailing := False;
  if S = '' then Exit;
  n := 0;
  start := 1;
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] in [#10, #13] then
    begin
      SetLength(Result, n + 1);
      Result[n] := Copy(S, start, i - start);
      Inc(n);
      if (S[i] = #13) and (i < Length(S)) and (S[i + 1] = #10) then
        Inc(i);
      start := i + 1;
    end;
    Inc(i);
  end;
  if start <= Length(S) then
  begin
    SetLength(Result, n + 1);
    Result[n] := Copy(S, start, MaxInt);
  end
  else
    ATrailing := True;
end;

{ one line as quoted pieces joined with ' + ' }
function QuotedPieces(const ALine: string): string;
var
  rest: string;
  cut: Integer;
begin
  Result := '';
  rest := ALine;
  repeat
    cut := Length(rest);
    if cut > cPieceMax then
    begin
      cut := cPieceMax;
      { never between the bytes of one character: back to where one starts }
      while (cut > 0) and (Ord(rest[cut + 1]) in [$80..$BF]) do
        Dec(cut);
      if cut = 0 then
        cut := cPieceMax;
    end;
    if Result <> '' then
      Result := Result + ' + ';
    Result := Result + '''' + TbPascalQuote(Copy(rest, 1, cut)) + '''';
    Delete(rest, 1, cut);
  until rest = '';
end;

function TbPascalCssFunction(const AFuncName, ACss: string): string;
var
  lines: TStringArray;
  trailing: Boolean;
  i: Integer;
begin
  Result := 'function ' + AFuncName + ': string;' + LineEnding + 'begin' + LineEnding;
  lines := SplitLines(ACss, trailing);
  if Length(lines) = 0 then
    Exit(Result + '  Result := '''';' + LineEnding + 'end;');
  Result := Result + '  Result :=' + LineEnding;
  for i := 0 to High(lines) do
  begin
    Result := Result + '    ' + QuotedPieces(lines[i]);
    if i < High(lines) then
      Result := Result + ' + LineEnding +' + LineEnding
    else
    begin
      if trailing then
        Result := Result + ' + LineEnding';
      Result := Result + ';' + LineEnding;
    end;
  end;
  Result := Result + 'end;';
end;

function TbSnippet(AKind: TTbSnippetKind; const AName, AFileName, ACss: string): string;
begin
  Result := '// uses ' + TbSnippetUses(AKind) + ';' + LineEnding
    + '// ' + rsTbSnippetWhere + LineEnding;
  if AKind = tsnRegister then
    Result := Result + TbPascalCssFunction('ThemeCss', ACss) + LineEnding + LineEnding;
  Result := Result + 'procedure TMainForm.FormCreate(Sender: TObject);' + LineEnding
    + TbSnippetBody(AKind, AName, AFileName);
end;

end.
