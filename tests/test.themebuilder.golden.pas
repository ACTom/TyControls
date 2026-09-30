unit test.themebuilder.golden;
{ Why this exists: the theme builder needs positions from the CSS parser (ETyCssError.Line /
  Col) and from the linter (TyLintCssEx). Both changes touch code whose TEXT other code
  depends on -- ThemeLint wraps the parser's message in rsLintParseError, and TyLintCss's
  output (order and wording) is what every existing caller reads. The two fixtures under
  tests/fixtures/themebuilder/ were written by the code as it was BEFORE those changes
  (TY_WRITE_GOLDEN=1), over every theme in themes/ and a set of broken snippets; these tests
  hold the changed code to them, byte for byte (line endings aside).

  The corpus (TbGoldenCorpus) is shared with test.themebuilder.lint, which checks that
  TyLintCss is exactly TyLintCssEx minus the Ex-only kind. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry;

const
  { Broken and borderline snippets. Line breaks are spelled out (LF, CRLF, CR); the one
    with a Chinese character carries its UTF-8 bytes (E4 B8 AD). }
  GoldenSnippets: array[0..24] of string = (
    'TyButton {'#10'  color red;'#10'}',
    'TyButton {'#13#10'  color red;'#13#10'}',
    'TyButton {'#13'  color red;'#13'}',
    'TyButton:hover2 { }',
    ':root { --a: 1px;',
    'TyButton { color: red;',
    '@mode dark {'#10'  :root { --x: 1px; }',
    'TyButton { }'#10'@import "a.tycss";',
    '@media x { }',
    '@ x',
    '@mode dark { TyButton { } }',
    '@mode dark { :rot { } }',
    '@import url(1);',
    '@import 5;',
    ':nope { }',
    '5px { }',
    '/* '#$E4#$B8#$AD' */ TyButton:x {}',
    '/* a'#10'b */ TyButton {'#10' color red; }',
    'TyButton { frobnicate: var(--nope); }',
    'TyButton { color: var(--ghost); background: darken(--missing, 4%); }',
    ':root { --c: #112233; }'#10'TyButton { background: #111111; color: #131313; }',
    'TyButton { border-radius: 1px 2px 3px; }',
    'TyPanel { background-image: url(nope.png) slice(4 4 4 4); }',
    '@import "definitely_not_here.tycss";',
    '');

type
  TThemeLintGoldenTests = class(TTestCase)
  private
    procedure CheckOrWrite(const AFixture: string; AActual: TStrings);
  published
    procedure TestTheLintOutputIsUnchanged;
    procedure TestTheParseErrorsReadTheSame;
  end;

{ The repo's themes/ directory (with a trailing delimiter). }
function TbRepoDir: string;
function TbThemesDir: string;
function TbFixtureDir: string;
{ Every *.tycss under themes/ (sorted by relative path, '/' separators) followed by each
  GoldenSnippets entry: ANames gets 'themes/<rel>' or 'snippet:N', ATexts the source, ADirs
  the base dir to lint it with (the file's own folder; '' for a snippet). }
procedure TbGoldenCorpus(ANames, ATexts, ADirs: TStrings);

implementation

uses
  Math, FileUtil, tyControls.Css.Parser, tyControls.ThemeLint, tyControls.StyleModel;

function TbRepoDir: string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..') + PathDelim;
end;

function TbThemesDir: string;
begin
  Result := TbRepoDir + 'themes' + PathDelim;
end;

function TbFixtureDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + 'themebuilder' + PathDelim;
end;

function ReadWhole(const AFileName: string): string;
var
  fs: TFileStream;
begin
  Result := '';
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

procedure TbGoldenCorpus(ANames, ATexts, ADirs: TStrings);
var
  files, rel: TStringList;
  i: Integer;
  root, r: string;
begin
  root := TbThemesDir;
  files := FindAllFiles(root, '*.tycss', True);
  rel := TStringList.Create;
  try
    for i := 0 to files.Count - 1 do
    begin
      r := Copy(files[i], Length(root) + 1, MaxInt);
      r := StringReplace(r, '\', '/', [rfReplaceAll]);
      rel.AddObject(r, TObject(PtrInt(i)));
    end;
    rel.Sorted := True;
    for i := 0 to rel.Count - 1 do
    begin
      ANames.Add('themes/' + rel[i]);
      ATexts.Add(ReadWhole(files[PtrInt(rel.Objects[i])]));
      ADirs.Add(ExtractFilePath(files[PtrInt(rel.Objects[i])]));
    end;
  finally
    rel.Free;
    files.Free;
  end;
  for i := 0 to High(GoldenSnippets) do
  begin
    ANames.Add('snippet:' + IntToStr(i));
    ATexts.Add(GoldenSnippets[i]);
    ADirs.Add('');
  end;
end;

function Unify(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
end;

procedure TThemeLintGoldenTests.CheckOrWrite(const AFixture: string; AActual: TStrings);
var
  path, actual, expected: string;
  fs: TFileStream;
  a, e: TStringList;
  i: Integer;
begin
  path := TbFixtureDir + AFixture;
  actual := '';
  for i := 0 to AActual.Count - 1 do
    actual := actual + AActual[i] + #10;
  if GetEnvironmentVariable('TY_WRITE_GOLDEN') = '1' then
  begin
    ForceDirectories(TbFixtureDir);
    fs := TFileStream.Create(path, fmCreate);
    try
      if actual <> '' then
        fs.WriteBuffer(actual[1], Length(actual));
    finally
      fs.Free;
    end;
    Exit;
  end;
  AssertTrue('the fixture exists: ' + path, FileExists(path));
  expected := Unify(ReadWhole(path));
  actual := Unify(actual);
  if expected = actual then
    Exit;
  a := TStringList.Create;
  e := TStringList.Create;
  try
    a.Text := actual;
    e.Text := expected;
    for i := 0 to Max(a.Count, e.Count) - 1 do
      if (i >= a.Count) or (i >= e.Count) or (a[i] <> e[i]) then
      begin
        if i < e.Count then expected := e[i] else expected := '<end>';
        if i < a.Count then actual := a[i] else actual := '<end>';
        Fail(Format('%s differs at line %d:'#10'  expected: %s'#10'  actual:   %s',
          [AFixture, i + 1, expected, actual]));
      end;
    Fail(AFixture + ' differs (line endings only?)');
  finally
    a.Free;
    e.Free;
  end;
end;

procedure TThemeLintGoldenTests.TestTheLintOutputIsUnchanged;
var
  names, texts, dirs, lines: TStringList;
  res: TTyLintResult;
  i, j: Integer;
begin
  names := TStringList.Create;
  texts := TStringList.Create;
  dirs := TStringList.Create;
  lines := TStringList.Create;
  try
    TbGoldenCorpus(names, texts, dirs);
    AssertTrue('the corpus has the themes', names.Count > Length(GoldenSnippets) + 10);
    for i := 0 to names.Count - 1 do
    begin
      lines.Add('== ' + names[i]);
      res := TyLintCss(texts[i], dirs[i]);
      for j := 0 to High(res) do
        lines.Add(res[j]);
    end;
    CheckOrWrite('lint-golden.txt', lines);
  finally
    names.Free;
    texts.Free;
    dirs.Free;
    lines.Free;
  end;
end;

procedure TThemeLintGoldenTests.TestTheParseErrorsReadTheSame;
var
  lines: TStringList;
  i: Integer;
  parser: TTyCssParser;
  sheet: TTyCssStylesheet;
  model: TTyStyleModel;
begin
  lines := TStringList.Create;
  try
    for i := 0 to High(GoldenSnippets) do
    begin
      parser := TTyCssParser.Create(GoldenSnippets[i]);
      try
        try
          sheet := parser.Parse;
          sheet.Free;
        except
          on E: Exception do
            lines.Add(Format('snippet:%d %s: %s', [i, E.ClassName, E.Message]));
        end;
      finally
        parser.Free;
      end;
    end;
    model := TTyStyleModel.Create;
    try
      try
        model.LoadFromCss('@import "definitely_missing.tycss";');
        lines.Add('model: no error');
      except
        on E: Exception do
          lines.Add('model ' + E.ClassName + ': ' + E.Message);
      end;
    finally
      model.Free;
    end;
    AssertTrue('some snippets fail to parse', lines.Count > 10);
    CheckOrWrite('parse-golden.txt', lines);
  finally
    lines.Free;
  end;
end;

initialization
  RegisterTest(TThemeLintGoldenTests);
end.
