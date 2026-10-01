unit test.themebuilder.snippets;
{ The theme builder's "Use it in a program" snippets (phase 2), compiled. The four snippets
  are written out below as real code -- the methods of a TTyForm and the function the
  "registered by name" page generates for the minimal template -- between // >>> name and
  // <<< name marks, and TTbSnippetsTests reads this very file and compares every marked
  part, line by line, with what tbsnippets produces. So a snippet that names something the
  library does not have stops this unit (and tytests) compiling, and a snippet changed
  without changing the code here turns the comparison red. The registered snippet is also
  run once. The other three read files beside the program; they are compiled, not run
  (nothing is written next to the test program). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Controller, tyControls.ThemeRegistry, tyControls.ThemeBundle, tyControls.Form;

type
  { the snippets, compiled: each method body is exactly what the window shows }
  TSnippetHost = class(TTyForm)
  public
    procedure FromFile;
    procedure FromFolder;
    procedure FromZip;
    procedure Registered;
  end;

  TTbSnippetsTests = class(TTestCase)
  private
    function Marked(const AName: string): TStringList;
    procedure CheckSame(const ATag: string; AWant: TStrings; const AHave: string);
  published
    procedure TestTheBodiesAreTheCompiledCode;
    procedure TestTheFunctionIsTheCompiledCode;
    procedure TestTheUsesAreHere;
    procedure TestRegisteringRuns;
    procedure TestQuotingAndCutting;
    procedure TestThemeNames;
    procedure TestTheWindow;
  end;

implementation

uses
  tbsnippets, tbsnippetsform, tbtemplates, test.themebuilder.golden;

// >>> function
function ThemeCss: string;
begin
  Result :=
    '/* A minimal theme: the six seeds, light and dark. Everything else comes from the base theme. */' + LineEnding +
    '' + LineEnding +
    '@mode light {' + LineEnding +
    '  :root {' + LineEnding +
    '    --accent: #3B82F6;' + LineEnding +
    '    --surface: #FFFFFF;' + LineEnding +
    '    --on-surface: #1F2937;' + LineEnding +
    '    --border: #D1D5DB;' + LineEnding +
    '    --danger: #EF4444;' + LineEnding +
    '    --radius: 6px;' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding +
    '' + LineEnding +
    '@mode dark {' + LineEnding +
    '  :root {' + LineEnding +
    '    --accent: #60A5FA;' + LineEnding +
    '    --surface: #1E1E1E;' + LineEnding +
    '    --on-surface: #E5E7EB;' + LineEnding +
    '    --border: #3F3F46;' + LineEnding +
    '    --danger: #F87171;' + LineEnding +
    '    --radius: 6px;' + LineEnding +
    '  }' + LineEnding +
    '}' + LineEnding;
end;
// <<< function

procedure TSnippetHost.FromFile;
// >>> file
begin
  TyDefaultController.ThemeFile := ExtractFilePath(ParamStr(0)) + 'mytheme.tycss';
  ApplyChromeTheme(TyDefaultController);
end;
// <<< file

procedure TSnippetHost.FromFolder;
// >>> folder
begin
  TyRegisterThemeFolder('mytheme', ExtractFilePath(ParamStr(0)) + 'mytheme');
  TyDefaultController.ThemeName := 'mytheme';
  ApplyChromeTheme(TyDefaultController);
end;
// <<< folder

procedure TSnippetHost.FromZip;
// >>> zip
var
  bundle: ITyThemeSource;
begin
  bundle := TTyThemeZipSource.Create(ExtractFilePath(ParamStr(0)) + 'mytheme.zip');
  TyRegisterThemeCss('mytheme', bundle.RootCss);
  TyDefaultController.ThemeName := 'mytheme';
  ApplyChromeTheme(TyDefaultController);
end;
// <<< zip

procedure TSnippetHost.Registered;
// >>> register
begin
  TyRegisterThemeCss('mytheme', ThemeCss);
  TyDefaultController.ThemeName := 'mytheme';
  ApplyChromeTheme(TyDefaultController);
end;
// <<< register

{ ---- the tests ---- }

function OwnSource: TStringList;
begin
  Result := TStringList.Create;
  Result.LoadFromFile(TbRepoDir + 'tests' + PathDelim + 'test.themebuilder.snippets.pas');
end;

{ the lines between // >>> AName and // <<< AName, trailing blanks cut }
function TTbSnippetsTests.Marked(const AName: string): TStringList;
var
  src: TStringList;
  i: Integer;
  inside: Boolean;
begin
  Result := TStringList.Create;
  src := OwnSource;
  try
    inside := False;
    for i := 0 to src.Count - 1 do
    begin
      if TrimRight(src[i]) = '// >>> ' + AName then
      begin
        inside := True;
        Continue;
      end;
      if TrimRight(src[i]) = '// <<< ' + AName then
        Break;
      if inside then
        Result.Add(TrimRight(src[i]));
    end;
  finally
    src.Free;
  end;
  AssertTrue('the marks for ' + AName + ' are there', Result.Count > 0);
end;

procedure TTbSnippetsTests.CheckSame(const ATag: string; AWant: TStrings; const AHave: string);
var
  have: TStringList;
  i: Integer;
begin
  have := TStringList.Create;
  try
    have.Text := AHave;
    for i := 0 to have.Count - 1 do
      have[i] := TrimRight(have[i]);
    AssertEquals(ATag + ': the number of lines', AWant.Count, have.Count);
    for i := 0 to AWant.Count - 1 do
      AssertEquals(ATag + ': line ' + IntToStr(i + 1), AWant[i], have[i]);
  finally
    have.Free;
  end;
end;

procedure TTbSnippetsTests.TestTheBodiesAreTheCompiledCode;
const
  cNames: array[TTbSnippetKind] of string = ('file', 'folder', 'zip', 'register');
var
  k: TTbSnippetKind;
  want: TStringList;
begin
  for k := Low(TTbSnippetKind) to High(TTbSnippetKind) do
  begin
    want := Marked(cNames[k]);
    try
      CheckSame('S1: ' + cNames[k], want, TbSnippetBody(k, 'mytheme', 'mytheme.tycss'));
    finally
      want.Free;
    end;
  end;
end;

procedure TTbSnippetsTests.TestTheFunctionIsTheCompiledCode;
var
  want: TStringList;
begin
  want := Marked('function');
  try
    CheckSame('S2', want, TbPascalCssFunction('ThemeCss', TbMinimalTemplate));
  finally
    want.Free;
  end;
  AssertEquals('S2: the compiled function gives the text back', TbMinimalTemplate, ThemeCss);
end;

{ a body of AKind that calls AName (as a part of a word) has AUnit on its uses line }
procedure CheckUnit(AKind: TTbSnippetKind; const AName, AUnit: string);
begin
  if Pos(AName, TbSnippetBody(AKind, 'mytheme', 'mytheme.tycss')) > 0 then
    TAssert.AssertTrue('S3: snippet ' + IntToStr(Ord(AKind)) + ' calls ' + AName + ', its uses line needs ' + AUnit,
      Pos(LowerCase(AUnit), LowerCase(TbSnippetUses(AKind))) > 0);
end;

procedure TTbSnippetsTests.TestTheUsesAreHere;
var
  src: TStringList;
  text, usesClause, names, one: string;
  p, q: Integer;
  k: TTbSnippetKind;
begin
  src := OwnSource;
  try
    text := src.Text;
  finally
    src.Free;
  end;
  p := Pos('interface', text);
  p := p + Pos('uses', Copy(text, p, MaxInt)) - 1;
  q := p + Pos(';', Copy(text, p, MaxInt)) - 1;
  usesClause := LowerCase(Copy(text, p, q - p));
  for k := Low(TTbSnippetKind) to High(TTbSnippetKind) do
  begin
    names := TbSnippetUses(k) + ',';
    while names <> '' do
    begin
      one := Trim(Copy(names, 1, Pos(',', names) - 1));
      Delete(names, 1, Pos(',', names));
      AssertTrue('S3: the uses here have ' + one, Pos(LowerCase(one), usesClause) > 0);
    end;
    { and the uses line the window shows names the unit of everything the body calls: the
      code here compiles with all of them in scope, a program pasting one snippet has only
      what its line says }
    CheckUnit(k, 'TyDefaultController', 'tyControls.Controller');
    CheckUnit(k, 'TyRegisterTheme', 'tyControls.ThemeRegistry');
    CheckUnit(k, 'ThemeSource', 'tyControls.ThemeBundle');
    CheckUnit(k, 'TTyThemeZipSource', 'tyControls.ThemeBundle');
  end;
end;

procedure TTbSnippetsTests.TestRegisteringRuns;
var
  h: TSnippetHost;
  name, mode: string;
begin
  name := TyDefaultController.ThemeName;
  mode := TyDefaultController.Mode;
  h := TSnippetHost.CreateNew(nil);
  try
    h.Registered;
    AssertTrue('S4: registered', TyThemeRegistered('mytheme'));
    AssertEquals('S4: chosen', 'mytheme', TyDefaultController.ThemeName);
    TyDefaultController.Mode := 'light';
    AssertEquals('S4: on the theme', '#3B82F6', TyDefaultController.Model.RawVar('--accent'));
  finally
    if TyDefaultController.ThemeName <> name then
      TyDefaultController.ThemeName := name;
    if TyDefaultController.Mode <> mode then
      TyDefaultController.Mode := mode;
    TyUnregisterTheme('mytheme');
    h.Free;
  end;
end;

procedure TTbSnippetsTests.TestQuotingAndCutting;
var
  s: string;
begin
  s := TbPascalCssFunction('X', 'a''b');
  AssertTrue('S5: a quote doubled: ' + s, Pos('    ''a''''b'';', s) > 0);
  s := TbPascalCssFunction('X', StringOfChar('x', 450));
  AssertTrue('S5: 200 + 200 + 50', Pos('    ''' + StringOfChar('x', 200) + ''' + ''' + StringOfChar('x', 200)
    + ''' + ''' + StringOfChar('x', 50) + ''';', s) > 0);
  s := TbPascalCssFunction('X', StringOfChar('x', 199) + #$E4#$B8#$AD);
  AssertTrue('S5: a character is not cut', Pos('    ''' + StringOfChar('x', 199) + ''' + '''
    + #$E4#$B8#$AD + ''';', s) > 0);
  s := TbPascalCssFunction('X', '');
  AssertEquals('S5: empty', 'function X: string;' + LineEnding + 'begin' + LineEnding
    + '  Result := '''';' + LineEnding + 'end;', s);
  s := TbPascalCssFunction('X', 'a'#13#10'b');
  AssertTrue('S5: the first line', Pos('    ''a'' + LineEnding +', s) > 0);
  AssertTrue('S5: the last line without a break', Pos('    ''b'';', s) > 0);
end;

procedure TTbSnippetsTests.TestThemeNames;
begin
  {$IFDEF MSWINDOWS}
  AssertEquals('S6: a file', 'my-theme', TbSnippetThemeName('C:\t\My Theme!.tycss', ''));
  {$ELSE}
  AssertEquals('S6: a file', 'my-theme', TbSnippetThemeName('/t/My Theme!.tycss', ''));
  {$ENDIF}
  AssertEquals('S6: based on', 'win11', TbSnippetThemeName('', 'win11'));
  AssertEquals('S6: nothing', 'mytheme', TbSnippetThemeName('', ''));
  AssertEquals('S6: nothing left', 'mytheme', TbSnippetThemeName('///.tycss', ''));
end;

procedure TTbSnippetsTests.TestTheWindow;
var
  f: TTbSnippetsForm;
begin
  f := TTbSnippetsForm.Create(nil);
  try
    f.Prepare('green', 'green.tycss', 'TyButton { }');
    AssertEquals('S7: three pages', 3, f.Pages.PageCount);
    AssertTrue('S7: from a file', Pos('''green.tycss''', f.MemoFile.Lines.Text) > 0);
    AssertTrue('S7: from a folder', Pos('TyRegisterThemeFolder(''green''', f.MemoFolder.Lines.Text) > 0);
    AssertTrue('S7: from a zip', Pos('''green.zip''', f.MemoZip.Lines.Text) > 0);
    AssertTrue('S7: registered: the function', Pos('function ThemeCss', f.MemoRegister.Lines.Text) > 0);
    AssertTrue('S7: registered: the text', Pos('''TyButton { }''', f.MemoRegister.Lines.Text) > 0);
  finally
    f.Free;
  end;
end;

initialization
  RegisterTest(TTbSnippetsTests);
end.
