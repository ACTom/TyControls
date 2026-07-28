unit test.i18n;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, FileUtil,
  Translations,            // TPOFile, TranslateUnitResourceStrings (LazUtils)
  tyControls.StrConsts;    // the unit that DECLARES the resourcestrings
type
  TI18NTest = class(TTestCase)
  published
    procedure TestZhCNTranslatesAndRestores;
    procedure TestNoCatalogueEntryIsWhollyEmpty;
  end;

implementation

const
  ZH_CN_PO =
    'msgid ""'                                          + LineEnding +
    'msgstr ""'                                         + LineEnding +
    '"Content-Type: text/plain; charset=UTF-8\n"'       + LineEnding +
    '"Language: zh_CN\n"'                               + LineEnding +
    ''                                                  + LineEnding +
    '#: tycontrols.strconsts.rslintemptyimportpath'     + LineEnding +
    'msgid "empty @import path"'                        + LineEnding +
    'msgstr "@import 路径为空"'                          + LineEnding;

  EN_PO =                       // identity catalog to restore English (no untranslate API)
    'msgid ""'                                          + LineEnding +
    'msgstr ""'                                         + LineEnding +
    '"Content-Type: text/plain; charset=UTF-8\n"'       + LineEnding +
    '"Language: en\n"'                               + LineEnding +
    ''                                                  + LineEnding +
    '#: tycontrols.strconsts.rslintemptyimportpath'     + LineEnding +
    'msgid "empty @import path"'                        + LineEnding +
    'msgstr "empty @import path"'                       + LineEnding;

procedure TI18NTest.TestZhCNTranslatesAndRestores;
var
  po: TPOFile;
begin
  AssertEquals('precondition: English default', 'empty @import path', rsLintEmptyImportPath);
  po := TPOFile.Create(True);
  try
    po.ReadPOText(ZH_CN_PO);
    AssertTrue('translate call succeeded',
      TranslateUnitResourceStrings('tyControls.StrConsts', po));
    AssertEquals('translated to zh_CN', '@import 路径为空', rsLintEmptyImportPath);
  finally
    po.Free;
  end;
  po := TPOFile.Create(True);     // restore so later tests see English
  try
    po.ReadPOText(EN_PO);
    TranslateUnitResourceStrings('tyControls.StrConsts', po);
    AssertEquals('restored to English', 'empty @import path', rsLintEmptyImportPath);
  finally
    po.Free;
  end;
end;

{ A .po entry that is empty on BOTH sides is a landmine, not a no-op. LazUtils'
  TPOFile.Translate looks an item up by identifier, takes Item.Translation or falls back
  to Item.Original, and then:

      if Result='' then Raise Exception.Create('TPOFile.Translate Inconsistency');

  So a wholly empty entry does not translate to nothing -- it RAISES, during form
  streaming, before OnCreate runs. The LCL answers with a modal error box, which blocks
  Application.CreateForm forever: the program never opens its window and never exits. That
  is how ad81fa4 (retyping the text properties as TCaption, which made Lazarus emit
  catalogue entries for captions whose value is the empty string) left the groupbox,
  radiobutton and toggleswitch examples unable to start at all.

  An empty msgid with a REAL msgstr is fine and deliberate -- tyControls.StrConsts'
  rsGridCheckedWord ships empty in English precisely so a catalogue can give the Grid an
  extra truthy word ('是'). Only the both-sides-empty shape is forbidden. }
procedure TI18NTest.TestNoCatalogueEntryIsWhollyEmpty;
var
  files: TStringList;
  lines: TStringList;
  i, j, k: Integer;
  bad, root: string;
  sawHeader: Boolean;
begin
  root := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
  files := FindAllFiles(root, '*.po', True);
  try
    AssertTrue('found catalogues to check', files.Count > 0);
    bad := '';
    for i := 0 to files.Count - 1 do
    begin
      lines := TStringList.Create;
      try
        lines.LoadFromFile(files[i]);
        sawHeader := False;
        for j := 0 to lines.Count - 1 do
        begin
          if Trim(lines[j]) <> 'msgid ""' then Continue;
          { The first such block is the header (msgstr "" followed by continuation
            lines carrying the metadata) -- skip exactly one. }
          if not sawHeader then begin sawHeader := True; Continue; end;
          k := j + 1;
          while (k < lines.Count) and (Trim(lines[k]) = '') do Inc(k);
          if (k < lines.Count) and (Trim(lines[k]) = 'msgstr ""') then
          begin
            { A continuation line right after means the value is non-empty. }
            if (k + 1 >= lines.Count) or (Copy(Trim(lines[k + 1]), 1, 1) <> '"') then
              bad := bad + LineEnding + '  ' + ExtractFileName(files[i]) + ':' + IntToStr(j + 1);
          end;
        end;
      finally
        lines.Free;
      end;
    end;
    AssertEquals('catalogue entries empty on BOTH sides (these raise at form-load time):'
      + bad, '', bad);
  finally
    files.Free;
  end;
end;

initialization
  RegisterTest(TI18NTest);
end.
