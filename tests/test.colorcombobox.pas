unit test.colorcombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Graphics, Forms, fpcunit, testregistry, Translations,
  tyControls.StrConsts, tyControls.ListBox, tyControls.ComboBox, tyControls.ColorBox,
  tyControls.ColorComboBox;
type
  TColorComboBoxTest = class(TTestCase)
  published
    procedure TestMoreItem;
    procedure TestMoreCaptionRebuild;
    procedure TestTheMoreRowFollowsTheLanguage;
    procedure TestClearingMoreCaptionBringsTheDefaultBack;
    { #121 }
    procedure TestTheMoreRowSurvivesAFormFile;
    procedure TestTheMoreRowSurvivesAPaletteChange;
    procedure TestIncludeNoneIsAColourRow;
    procedure TestTheFieldSwatchTakesTheRectWidth;
    procedure TestTheNoneRowPaintsWithNoneColorColor;
    procedure TestTheListRowsTakeTheRectWidth;
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

type
  TComboAcc = class(TTyComboBox);
  TListAcc = class(TTyListBox);

function DiffersFrom(A, B: TBitmap): Boolean;
var x, y: Integer;
begin
  Result := True;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if ColorToRGB(A.Canvas.Pixels[x, y]) <> ColorToRGB(B.Canvas.Pixels[x, y]) then Exit;
  Result := False;
end;

function NewBitmap(W, H: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(W, H);
end;

function FieldsDiffer(A, B: TTyColorComboBox): Boolean;
var ba, bb: TBitmap;
begin
  ba := NewBitmap(200, 26);
  bb := NewBitmap(200, 26);
  try
    TComboAcc(A).RenderTo(ba.Canvas, Rect(0, 0, 200, 26), 96);
    TComboAcc(B).RenderTo(bb.Canvas, Rect(0, 0, 200, 26), 96);
    Result := DiffersFrom(ba, bb);
  finally
    ba.Free; bb.Free;
  end;
end;

function MoreRows(C: TTyColorComboBox): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to C.Items.Count - 1 do
    if C.Items[i] = C.MoreText then Inc(Result);
end;

procedure TColorComboBoxTest.TestMoreItem;
var c: TTyColorComboBox;
begin
  c := TTyColorComboBox.Create(nil);
  try
    // 16 palette colours + one trailing "more…" row.
    AssertEquals('16 + more', 17, c.Items.Count);
    AssertTrue('real colour 0 intact', c.ColorAt(0) = clBlack);
    AssertTrue('the more row is not clNone, a colour a palette may carry (#121)',
      c.ColorAt(c.Items.Count - 1) <> clNone);
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
    AssertTrue('still not a colour', c.ColorAt(c.Items.Count - 1) <> clNone);
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

procedure TColorComboBoxTest.TestTheMoreRowSurvivesAFormFile;
var src, dst: TForm; c: TTyColorComboBox; ms: TMemoryStream;
begin
  src := TForm.CreateNew(nil);
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    c := TTyColorComboBox.Create(src);
    c.Name := 'CC';
    c.Parent := src;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);   // Loaded rebuilds the palette, as LCL's does
    c := dst.FindComponent('CC') as TTyColorComboBox;
    AssertEquals('the "more" row is back, last', c.MoreText, c.Items[c.Items.Count - 1]);
    AssertEquals('and only once', 1, MoreRows(c));
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TColorComboBoxTest.TestTheMoreRowSurvivesAPaletteChange;
var c: TTyColorComboBox;
begin
  c := TTyColorComboBox.Create(nil);
  try
    c.Style := c.Style + [cbExtendedColors];
    AssertEquals('the "more" row is still last', c.MoreText, c.Items[c.Items.Count - 1]);
    AssertEquals('and only once', 1, MoreRows(c));
  finally c.Free; end;
end;

procedure TColorComboBoxTest.TestIncludeNoneIsAColourRow;
var c: TTyColorComboBox;
begin
  c := TTyColorComboBox.Create(nil);
  try
    c.Style := [cbStandardColors, cbIncludeNone];
    c.MoreCaption := 'Other' + #$E2#$80#$A6;   // a rebuild of the "more" row keeps the none row
    c.Selected := clNone;
    AssertTrue('the none row is selected', c.ItemIndex >= 0);
    AssertTrue('and it is not the "more" row', c.ItemIndex < c.Items.Count - 1);
    AssertTrue('Selected reads it back', c.Selected = clNone);
  finally c.Free; end;
end;

procedure TColorComboBoxTest.TestTheFieldSwatchTakesTheRectWidth;
var a, b: TTyColorComboBox;
begin
  a := TTyColorComboBox.Create(nil);
  b := TTyColorComboBox.Create(nil);
  try
    a.Selected := clRed;
    b.Selected := clRed;
    b.ColorRectWidth := 60;
    AssertTrue('a wider swatch in the field', FieldsDiffer(a, b));
  finally a.Free; b.Free; end;
end;

procedure TColorComboBoxTest.TestTheNoneRowPaintsWithNoneColorColor;
var a, b: TTyColorComboBox;
begin
  a := TTyColorComboBox.Create(nil);
  b := TTyColorComboBox.Create(nil);
  try
    a.Style := [cbStandardColors, cbIncludeNone];
    b.Style := [cbStandardColors, cbIncludeNone];
    a.Selected := clNone;
    b.Selected := clNone;
    b.NoneColorColor := clRed;
    AssertTrue('the none swatch takes NoneColorColor', FieldsDiffer(a, b));
  finally a.Free; b.Free; end;
end;

procedure TColorComboBoxTest.TestTheListRowsTakeTheRectWidth;
var a, b: TTyColorComboBox; la, lb: TTyListBox; ba, bb: TBitmap;
begin
  a := TTyColorComboBox.Create(nil);
  b := TTyColorComboBox.Create(nil);
  ba := NewBitmap(200, 120);
  bb := NewBitmap(200, 120);
  try
    b.ColorRectWidth := 60;
    { The list the combo drops down, made as the combo makes it (owned by the combo). }
    la := TTyColorMorePopupList.Create(a);
    lb := TTyColorMorePopupList.Create(b);
    la.Items.Assign(a.Items);
    lb.Items.Assign(b.Items);
    TListAcc(la).RenderTo(ba.Canvas, Rect(0, 0, 200, 120), 96);
    TListAcc(lb).RenderTo(bb.Canvas, Rect(0, 0, 200, 120), 96);
    AssertTrue('the drop-down rows take ColorRectWidth too', DiffersFrom(ba, bb));
  finally ba.Free; bb.Free; a.Free; b.Free; end;
end;

initialization
  RegisterTest(TColorComboBoxTest);
end.
