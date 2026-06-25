unit test.i18n;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  Translations,            // TPOFile, TranslateUnitResourceStrings (LazUtils)
  tyControls.StrConsts;    // the unit that DECLARES the resourcestrings
type
  TI18NTest = class(TTestCase)
  published
    procedure TestZhCNTranslatesAndRestores;
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

initialization
  RegisterTest(TI18NTest);
end.
