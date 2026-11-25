unit test.shell.i18n;
{$mode objfpc}{$H+}

{ #249: the file list's own words come from the catalogue.

  The four column headers of TTyShellListView were literals in BuildColumns, and the names in
  its Type column -- which are also the headings of its groups -- were literals in
  TyFsTypeName. No catalogue could have them, so the open and save dialogs of an application
  that loads a translation of the library kept that part of themselves in English.

  The catalogue used here is written in this unit and names the strings by identifier, as
  LazUtils keys them: an identifier the library does not declare is passed over, which is
  what makes these tests fail against the literals rather than not compile. English is put
  back by the same means before each test ends, whatever it found. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Translations,
  tyControls.FileSystem, tyControls.ListView, tyControls.ShellListView;

type
  TShellListI18nTest = class(TTestCase)
  private
    procedure Load(const APo: string);
    function Headers: string;
    function TypeOf(const AName: string; AIsDir: Boolean): string;
  protected
    procedure TearDown; override;
  published
    procedure InEnglishTheHeadersAndTheTypeNamesReadAsTheyDid;
    procedure TheColumnHeadersAreTheCataloguesWords;
    procedure TheTypeNamesAreTheCataloguesWords;
    procedure AListBuiltBeforeTheCatalogueCameKeepsItsWords;
    procedure TheChineseCatalogueThatShipsHasAllSeven;
  end;

implementation

const
  cHead =
    'msgid ""' + LineEnding +
    'msgstr ""' + LineEnding +
    '"Content-Type: text/plain; charset=UTF-8\n"' + LineEnding + LineEnding;

  { identifier, the English text, the translation used here }
  cWords: array[0..6, 0..2] of string = (
    ('rsfdcolname',     'Name',     '名称'),
    ('rsfdcolsize',     'Size',     '大小'),
    ('rsfdcoltype',     'Type',     '类型'),
    ('rsfdcolmodified', 'Modified', '修改日期'),
    ('rsfdtypefolder',  'Folder',   '文件夹'),
    ('rsfdtypefile',    'File',     '文件'),
    ('rsfdtypefileof',  '%s File',  '%s 文件'));

{ A catalogue of the seven strings: column 2 of cWords when ATranslated, else English again. }
function Catalogue(ATranslated: Boolean): string;
var
  i: Integer;
begin
  Result := cHead;
  for i := 0 to High(cWords) do
    Result := Result
      + '#: tycontrols.strconsts.' + cWords[i, 0] + LineEnding
      + 'msgid "' + cWords[i, 1] + '"' + LineEnding
      + 'msgstr "' + cWords[i, 1 + Ord(ATranslated)] + '"' + LineEnding + LineEnding;
end;

procedure TShellListI18nTest.Load(const APo: string);
var
  po: TPOFile;
begin
  po := TPOFile.Create(True);
  try
    po.ReadPOText(APo);
    AssertTrue('the catalogue loads', TranslateUnitResourceStrings('tyControls.StrConsts', po));
  finally
    po.Free;
  end;
end;

procedure TShellListI18nTest.TearDown;
begin
  Load(Catalogue(False));   { English again, for whoever runs next }
end;

function TShellListI18nTest.Headers: string;
var
  lv: TTyShellListView;
  i: Integer;
begin
  Result := '';
  lv := TTyShellListView.Create(nil);
  try
    for i := 0 to lv.Header.Columns.Count - 1 do
    begin
      if i > 0 then Result := Result + '|';
      Result := Result + lv.Header.Columns[i].Text;
    end;
  finally
    lv.Free;
  end;
end;

function TShellListI18nTest.TypeOf(const AName: string; AIsDir: Boolean): string;
var
  e: TTyFsEntry;
begin
  e := Default(TTyFsEntry);
  e.Name := AName;
  e.IsDir := AIsDir;
  Result := TyFsTypeName(e);
end;

procedure TShellListI18nTest.InEnglishTheHeadersAndTheTypeNamesReadAsTheyDid;
begin
  AssertEquals('the four headers, in their order', 'Name|Size|Type|Modified', Headers);
  AssertEquals('a folder', 'Folder', TypeOf('src', True));
  AssertEquals('a file with an extension', 'TXT File', TypeOf('notes.txt', False));
  AssertEquals('the extension in capitals, whatever its case on disk', 'PAS File',
    TypeOf('unit1.Pas', False));
  AssertEquals('a file with none', 'File', TypeOf('Makefile', False));
  AssertEquals('a name that ends in its dot has none either', 'File', TypeOf('odd.', False));
  AssertEquals('a folder is a folder whatever its name ends in', 'Folder',
    TypeOf('photos.old', True));
end;

procedure TShellListI18nTest.TheColumnHeadersAreTheCataloguesWords;
begin
  Load(Catalogue(True));
  AssertEquals('each header is the word the catalogue has for it, in the same order',
    '名称|大小|类型|修改日期', Headers);
end;

procedure TShellListI18nTest.TheTypeNamesAreTheCataloguesWords;
begin
  Load(Catalogue(True));
  AssertEquals('a folder', '文件夹', TypeOf('src', True));
  AssertEquals('a file with an extension: the extension goes where the catalogue puts it',
    'TXT 文件', TypeOf('notes.txt', False));
  AssertEquals('a file with none', '文件', TypeOf('Makefile', False));
end;

procedure TShellListI18nTest.AListBuiltBeforeTheCatalogueCameKeepsItsWords;
var
  lv: TTyShellListView;
begin
  { The headers are column texts, the application's to change once the list exists; a
    catalogue that arrives later must not write over them. }
  lv := TTyShellListView.Create(nil);
  try
    lv.Header.Columns[0].Text := 'Document';
    Load(Catalogue(True));
    AssertEquals('the text the application gave the column', 'Document',
      lv.Header.Columns[0].Text);
    AssertEquals('and a column it left alone', 'Size', lv.Header.Columns[1].Text);
  finally
    lv.Free;
  end;
end;

procedure TShellListI18nTest.TheChineseCatalogueThatShipsHasAllSeven;
var
  po: TPOFile;
  i: Integer;
  got: string;
begin
  { Read through TPOFile, so the running program stays in English. Asked with the English
    text, as LazUtils asks: an entry that is missing answers with that text again. }
  po := TPOFile.Create(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'languages'
    + PathDelim + 'tycontrols.strconsts.zh_CN.po');
  try
    for i := 0 to High(cWords) do
    begin
      got := po.Translate('tycontrols.strconsts.' + cWords[i, 0], cWords[i, 1]);
      AssertEquals('zh_CN for ' + cWords[i, 0], cWords[i, 2], got);
    end;
  finally
    po.Free;
  end;
end;

initialization
  RegisterTest(TShellListI18nTest);
end.
