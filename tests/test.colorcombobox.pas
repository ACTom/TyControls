unit test.colorcombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, fpcunit, testregistry, Translations, tyControls.StrConsts,
  tyControls.ColorComboBox;
type
  TColorComboBoxTest = class(TTestCase)
  published
    procedure TestMoreItem;
    procedure TestMoreCaptionRebuild;
    procedure TestTheMoreRowFollowsTheLanguage;
    procedure TestClearingMoreCaptionBringsTheDefaultBack;
  end;
implementation


{ Translate tyControls.StrConsts with a two-entry catalogue, then back to English. }
procedure UseCatalogue(const AText: string);
var po: TPOFile;
begin
  po := TPOFile.Create(True);
  try
    po.ReadPOText(AText);
    TranslateUnitResourceStrings('tyControls.StrConsts', po);
  finally
    po.Free;
  end;
end;

const
  ZH_PO =
    'msgid ""' + LineEnding + 'msgstr "Content-Type: text/plain; charset=UTF-8\n"' + LineEnding + LineEnding +
    '#: tycontrols.strconsts.rscolorbuttondialogtitle' + LineEnding +
    'msgid "Select Color"' + LineEnding + 'msgstr "PICK A COLOUR"' + LineEnding + LineEnding +
    '#: tycontrols.strconsts.rscolorcombomore' + LineEnding +
    'msgid "More' + #$E2#$80#$A6 + '"' + LineEnding + 'msgstr "MORE COLOURS"' + LineEnding;
  EN_PO =
    'msgid ""' + LineEnding + 'msgstr "Content-Type: text/plain; charset=UTF-8\n"' + LineEnding + LineEnding +
    '#: tycontrols.strconsts.rscolorbuttondialogtitle' + LineEnding +
    'msgid "Select Color"' + LineEnding + 'msgstr "Select Color"' + LineEnding + LineEnding +
    '#: tycontrols.strconsts.rscolorcombomore' + LineEnding +
    'msgid "More' + #$E2#$80#$A6 + '"' + LineEnding + 'msgstr "More' + #$E2#$80#$A6 + '"' + LineEnding;

procedure TColorComboBoxTest.TestMoreItem;
var c: TTyColorComboBox;
begin
  c := TTyColorComboBox.Create(nil);
  try
    // 16 palette colours + one trailing "more…" sentinel (clNone).
    AssertEquals('16 + more', 17, c.Items.Count);
    AssertTrue('real colour 0 intact', c.ColorAt(0) = clBlack);
    AssertTrue('last is the clNone sentinel', c.ColorAt(c.Items.Count - 1) = clNone);
    AssertEquals('more caption', 'More…', c.Items[c.Items.Count - 1]);
  finally c.Free; end;
end;

procedure TColorComboBoxTest.TestMoreCaptionRebuild;
var c: TTyColorComboBox;
begin
  c := TTyColorComboBox.Create(nil);
  try
    c.MoreCaption := 'Custom…';
    AssertEquals('still 17 (old more dropped)', 17, c.Items.Count);
    AssertEquals('rebuilt caption last', 'Custom…', c.Items[c.Items.Count - 1]);
    AssertTrue('still clNone sentinel', c.ColorAt(c.Items.Count - 1) = clNone);
  finally c.Free; end;
end;

procedure TColorComboBoxTest.TestTheMoreRowFollowsTheLanguage;
var c: TTyColorComboBox;
begin
  UseCatalogue(ZH_PO);
  try
    c := TTyColorComboBox.Create(nil);
    try
      AssertEquals('MoreCaption stays empty', '', c.MoreCaption);
      AssertEquals('the row shows the translated default', 'MORE COLOURS',
        c.Items[c.Items.Count - 1]);
    finally c.Free; end;
  finally
    UseCatalogue(EN_PO);
  end;
end;

procedure TColorComboBoxTest.TestClearingMoreCaptionBringsTheDefaultBack;
var c: TTyColorComboBox;
begin
  c := TTyColorComboBox.Create(nil);
  try
    c.MoreCaption := 'Custom' + #$E2#$80#$A6;
    AssertEquals('setup: an own caption', 'Custom' + #$E2#$80#$A6, c.Items[c.Items.Count - 1]);
    c.MoreCaption := '';
    AssertEquals('cleared: the default again', rsColorComboMore, c.Items[c.Items.Count - 1]);
  finally c.Free; end;
end;

initialization
  RegisterTest(TColorComboBoxTest);
end.
