unit test.fontcombobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, fpcunit, testregistry, tyControls.FontComboBox,
  tyControls.FontFamilies;
type
  TFontComboBoxTest = class(TTestCase)
  private
    FChanges: Integer;
    procedure CountChange(Sender: TObject);
  published
    procedure TestSelectedFontRoundTrip;
    procedure TestRefreshDoesNotCrash;
    procedure TestAFormFileDoesNotCarryThisMachinesFonts;
    procedure TestA300FormFileShowsThisMachinesFonts;
    procedure TestAFamilyThisMachineLacksIsNotSwappedForAnother;
    { FixedPitchOnly (#27) }
    procedure TestFixedPitchOnlyListsTheSystemsFixedFamilies;
    procedure TestTogglingKeepsAFamilyStillListed;
    procedure TestTogglingOnDropsAProportionalChoice;
    procedure TestTogglingWithNothingSelectedSelectsNothing;
    procedure TestTogglingKeepsTheChoiceWithoutOnChange;
    procedure TestAFormFileWithFixedPitchOnlyLoadsTheFilteredList;
    procedure TestFixedPitchOnlyIsWrittenOnlyWhenOn;
  end;
implementation

procedure TFontComboBoxTest.TestSelectedFontRoundTrip;
var c: TTyFontComboBox;
begin
  c := TTyFontComboBox.Create(nil);
  try
    // Replace the Screen.Fonts population with a deterministic set.
    c.Items.Clear;
    c.Items.Add('Arial');
    c.Items.Add('Courier New');
    c.Items.Add('Times New Roman');
    c.SelectedFont := 'Courier New';
    AssertEquals('selected', 'Courier New', c.SelectedFont);
    AssertEquals('index', 1, c.ItemIndex);
    c.SelectedFont := 'Nonexistent Font';   // not present -> selection unchanged
    AssertEquals('unchanged', 'Courier New', c.SelectedFont);
  finally c.Free; end;
end;

procedure TFontComboBoxTest.TestRefreshDoesNotCrash;
var c: TTyFontComboBox;
begin
  // Construction reads Screen.Fonts; RefreshFonts re-reads. Neither may crash headless.
  c := TTyFontComboBox.Create(nil);
  try
    c.RefreshFonts;
    AssertTrue('items count is sane', c.Items.Count >= 0);
  finally c.Free; end;
end;

{ Form-file plumbing for the tests below: what a form writes, and a form read back from text. }
function FCBFormText(ASrc: TForm): string;
var ms, ts: TMemoryStream; L: TStringList;
begin
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  L := TStringList.Create;
  try
    ms.WriteComponent(ASrc);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    Result := L.Text;
  finally
    L.Free;
    ts.Free;
    ms.Free;
  end;
end;

function FCBFromText(const AText: string): TForm;
var ts: TStringStream; bs: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  ts := TStringStream.Create(AText);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(Result);
  finally
    bs.Free;
    ts.Free;
  end;
end;

{ A font this machine has, late in its list, whose name a form file can carry as a plain quoted
  string -- so the row it sits at here is not the row a stale index points at. }
function FCBLateFont: string;
var i: Integer; nm: string; ok: Boolean; ch: Char;
begin
  Result := '';
  for i := Screen.Fonts.Count - 1 downto 3 do
  begin
    nm := Screen.Fonts[i];
    ok := nm <> '';
    for ch in nm do
      if (ch < ' ') or (ch > '~') or (ch = '''') then ok := False;
    if ok then Exit(nm);
  end;
end;

{ What 3.0.0 wrote: another machine's list, with ItemIndex at row 2 (AChosen) or row 1 (a family
  this machine does not have). }
function FCBOldForm(const AChosen: string; AIndex: Integer): string;
var t: string;
begin
  if AIndex = 2 then t := AChosen else t := 'NoSuchFontB';
  Result :=
    'object Form1: TForm' + LineEnding +
    '  object F: TTyFontComboBox' + LineEnding +
    '    Items.Strings = (' + LineEnding +
    '      ''NoSuchFontA''' + LineEnding +
    '      ''NoSuchFontB''' + LineEnding +
    '      ''' + AChosen + '''' + LineEnding +
    '    )' + LineEnding +
    '    ItemIndex = ' + IntToStr(AIndex) + LineEnding +
    '    Text = ''' + t + '''' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
end;

procedure TFontComboBoxTest.TestAFormFileDoesNotCarryThisMachinesFonts;
var src: TForm; c: TTyFontComboBox; t: string;
begin
  src := TForm.CreateNew(nil);
  try
    c := TTyFontComboBox.Create(src);
    c.Name := 'F';
    c.Parent := src;
    AssertTrue('setup: this machine has fonts', c.Items.Count > 0);
    t := FCBFormText(src);
    AssertTrue('the installed fonts are not written into the form' + LineEnding + t,
      Pos('Items.Strings', t) = 0);
  finally
    src.Free;
  end;
end;

procedure TFontComboBoxTest.TestA300FormFileShowsThisMachinesFonts;
var dst: TForm; c: TTyFontComboBox; f: string;
begin
  f := FCBLateFont;
  AssertTrue('setup: a font past row 2 with a plain name', f <> '');
  dst := FCBFromText(FCBOldForm(f, 2));
  try
    c := dst.FindComponent('F') as TTyFontComboBox;
    AssertEquals('the list is this machine''s fonts, not the saved one',
      Screen.Fonts.Count, c.Items.Count);
    AssertEquals('none of the saving machine''s missing fonts is listed', -1,
      c.Items.IndexOf('NoSuchFontA'));
    AssertEquals('the chosen family is still chosen, at the row it has here', f, c.SelectedFont);
    AssertEquals('and that row is its row on this machine', Screen.Fonts.IndexOf(f), c.ItemIndex);
  finally
    dst.Free;
  end;
end;

procedure TFontComboBoxTest.TestAFamilyThisMachineLacksIsNotSwappedForAnother;
var dst: TForm; c: TTyFontComboBox;
begin
  dst := FCBFromText(FCBOldForm('NoSuchFontC', 1));
  try
    c := dst.FindComponent('F') as TTyFontComboBox;
    AssertEquals('the list is this machine''s fonts', Screen.Fonts.Count, c.Items.Count);
    AssertEquals('a family this machine lacks leaves nothing selected', -1, c.ItemIndex);
  finally
    dst.Free;
  end;
end;

procedure FCBNeedFonts;
begin
  if (Screen.Fonts.IndexOf('Courier New') < 0) or (Screen.Fonts.IndexOf('Arial') < 0) then
    raise EIgnoredTest.Create('needs Courier New and Arial installed');
end;

procedure FCBAssertSame(const AWhat: string; AExpected, AActual: TStrings);
var i: Integer;
begin
  TAssert.AssertEquals(AWhat + ': row count', AExpected.Count, AActual.Count);
  for i := 0 to AExpected.Count - 1 do
    TAssert.AssertEquals(AWhat + ': row ' + IntToStr(i), AExpected[i], AActual[i]);
end;

procedure TFontComboBoxTest.TestFixedPitchOnlyListsTheSystemsFixedFamilies;
var c: TTyFontComboBox; fixed: TStringList;
begin
  FCBNeedFonts;
  fixed := TStringList.Create;
  c := TTyFontComboBox.Create(nil);
  try
    TyGetFontFamilies(fixed, True);
    c.FixedPitchOnly := True;
    FCBAssertSame('on', fixed, c.Items);
    AssertTrue('Arial is not offered', c.Items.IndexOf('Arial') < 0);
    c.FixedPitchOnly := False;
    FCBAssertSame('off again', Screen.Fonts, c.Items);
  finally
    c.Free;
    fixed.Free;
  end;
end;

procedure TFontComboBoxTest.TestTogglingKeepsAFamilyStillListed;
var c: TTyFontComboBox;
begin
  FCBNeedFonts;
  c := TTyFontComboBox.Create(nil);
  try
    c.SelectedFont := 'Courier New';
    c.FixedPitchOnly := True;
    AssertEquals('a fixed-pitch choice stays chosen', 'Courier New', c.SelectedFont);
    AssertEquals('at its row in the shorter list', c.Items.IndexOf('Courier New'), c.ItemIndex);
    c.FixedPitchOnly := False;
    AssertEquals('and back', 'Courier New', c.SelectedFont);
  finally
    c.Free;
  end;
end;

procedure TFontComboBoxTest.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TFontComboBoxTest.TestTogglingOnDropsAProportionalChoice;
var c: TTyFontComboBox;
begin
  FCBNeedFonts;
  c := TTyFontComboBox.Create(nil);
  try
    c.SelectedFont := 'Arial';
    FChanges := 0;
    c.OnChange := @CountChange;
    c.FixedPitchOnly := True;
    AssertEquals('a family no longer listed leaves nothing selected', -1, c.ItemIndex);
    AssertTrue('and is not swapped for the first row', c.SelectedFont <> c.Items[0]);
    AssertEquals('the choice changed: OnChange once', 1, FChanges);
  finally
    c.Free;
  end;
end;

procedure TFontComboBoxTest.TestTogglingWithNothingSelectedSelectsNothing;
var c: TTyFontComboBox;
begin
  FCBNeedFonts;
  c := TTyFontComboBox.Create(nil);
  try
    c.ItemIndex := -1;
    FChanges := 0;
    c.OnChange := @CountChange;
    c.FixedPitchOnly := True;
    AssertEquals('on: still nothing selected', -1, c.ItemIndex);
    c.FixedPitchOnly := False;
    AssertEquals('off: still nothing selected', -1, c.ItemIndex);
    AssertEquals('nothing changed: no OnChange', 0, FChanges);
  finally
    c.Free;
  end;
end;

procedure TFontComboBoxTest.TestTogglingKeepsTheChoiceWithoutOnChange;
var c: TTyFontComboBox;
begin
  FCBNeedFonts;
  c := TTyFontComboBox.Create(nil);
  try
    c.SelectedFont := 'Courier New';
    FChanges := 0;
    c.OnChange := @CountChange;
    c.FixedPitchOnly := True;
    AssertEquals('on: still Courier New', 'Courier New', c.SelectedFont);
    c.FixedPitchOnly := False;
    AssertEquals('off: still Courier New', 'Courier New', c.SelectedFont);
    AssertEquals('the same family at another row is no change: no OnChange', 0, FChanges);
  finally
    c.Free;
  end;
end;

procedure TFontComboBoxTest.TestAFormFileWithFixedPitchOnlyLoadsTheFilteredList;
var dst: TForm; c: TTyFontComboBox; fixed: TStringList;
begin
  FCBNeedFonts;
  fixed := TStringList.Create;
  dst := FCBFromText(
    'object Form1: TForm' + LineEnding +
    '  object F: TTyFontComboBox' + LineEnding +
    '    Text = ''Courier New''' + LineEnding +
    '    FixedPitchOnly = True' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding);
  try
    c := dst.FindComponent('F') as TTyFontComboBox;
    TyGetFontFamilies(fixed, True);
    AssertTrue('read in', c.FixedPitchOnly);
    FCBAssertSame('the list Loaded built', fixed, c.Items);
    AssertEquals('the chosen family, by name', 'Courier New', c.SelectedFont);
  finally
    dst.Free;
    fixed.Free;
  end;
end;

procedure TFontComboBoxTest.TestFixedPitchOnlyIsWrittenOnlyWhenOn;
var src: TForm; c: TTyFontComboBox;
begin
  src := TForm.CreateNew(nil);
  try
    c := TTyFontComboBox.Create(src);
    c.Name := 'F';
    c.Parent := src;
    AssertTrue('off is the default and is not written',
      Pos('FixedPitchOnly', FCBFormText(src)) = 0);
    c.FixedPitchOnly := True;
    AssertTrue('on is written', Pos('FixedPitchOnly = True', FCBFormText(src)) > 0);
  finally
    src.Free;
  end;
end;

initialization
  RegisterTest(TFontComboBoxTest);
end.
