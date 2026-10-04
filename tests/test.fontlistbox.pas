unit test.fontlistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, fpcunit, testregistry, test.fontfamilies, tyControls.FontListBox,
  tyControls.FontFamilies;
type
  TFontListBoxTest = class(TTestCase)
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

procedure TFontListBoxTest.TestSelectedFontRoundTrip;
var c: TTyFontListBox;
begin
  c := TTyFontListBox.Create(nil);
  try
    c.Items.Clear;
    c.Items.Add('Arial');
    c.Items.Add('Courier New');
    c.SelectedFont := 'Courier New';
    AssertEquals('selected', 'Courier New', c.SelectedFont);
    AssertEquals('index', 1, c.ItemIndex);
    c.SelectedFont := 'Nonexistent Font';   // not present -> unchanged
    AssertEquals('unchanged', 'Courier New', c.SelectedFont);
  finally c.Free; end;
end;

procedure TFontListBoxTest.TestRefreshDoesNotCrash;
var c: TTyFontListBox;
begin
  c := TTyFontListBox.Create(nil);
  try
    c.RefreshFonts;
    AssertTrue('items count is sane', c.Items.Count >= 0);
  finally c.Free; end;
end;

{ Form-file plumbing for the tests below: what a form writes, and a form read back from text. }
function FLBFormText(ASrc: TForm): string;
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

function FLBFromText(const AText: string): TForm;
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

{ The rows a font picker shows without a filter (see test.fontfamilies). }
function FLBPlainCount: Integer;
var L: TStringList;
begin
  L := TStringList.Create;
  try FontsWithoutVerticalVariants(L); Result := L.Count; finally L.Free; end;
end;

function FLBPlainIndexOf(const AName: string): Integer;
var L: TStringList;
begin
  L := TStringList.Create;
  try FontsWithoutVerticalVariants(L); Result := L.IndexOf(AName); finally L.Free; end;
end;

{ A font this machine has, late in its list, whose name a form file can carry as a plain quoted
  string -- so the row it sits at here is not the row a stale index points at. }
function FLBLateFont: string;
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
function FLBOldForm(const AChosen: string; AIndex: Integer): string;
var t: string;
begin
  if AIndex = 2 then t := AChosen else t := 'NoSuchFontB';
  Result :=
    'object Form1: TForm' + LineEnding +
    '  object F: TTyFontListBox' + LineEnding +
    '    Items.Strings = (' + LineEnding +
    '      ''NoSuchFontA''' + LineEnding +
    '      ''NoSuchFontB''' + LineEnding +
    '      ''' + AChosen + '''' + LineEnding +
    '    )' + LineEnding +
    '    ItemIndex = ' + IntToStr(AIndex) + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
end;

procedure TFontListBoxTest.TestAFormFileDoesNotCarryThisMachinesFonts;
var src: TForm; c: TTyFontListBox; t: string;
begin
  src := TForm.CreateNew(nil);
  try
    c := TTyFontListBox.Create(src);
    c.Name := 'F';
    c.Parent := src;
    AssertTrue('setup: this machine has fonts', c.Items.Count > 0);
    t := FLBFormText(src);
    AssertTrue('the installed fonts are not written into the form' + LineEnding + t,
      Pos('Items.Strings', t) = 0);
  finally
    src.Free;
  end;
end;

procedure TFontListBoxTest.TestA300FormFileShowsThisMachinesFonts;
var dst: TForm; c: TTyFontListBox; f: string;
begin
  f := FLBLateFont;
  AssertTrue('setup: a font past row 2 with a plain name', f <> '');
  dst := FLBFromText(FLBOldForm(f, 2));
  try
    c := dst.FindComponent('F') as TTyFontListBox;
    AssertEquals('the list is this machine''s fonts, not the saved one',
      FLBPlainCount, c.Items.Count);
    AssertEquals('none of the saving machine''s missing fonts is listed', -1,
      c.Items.IndexOf('NoSuchFontA'));
    AssertEquals('the chosen family is still chosen, at the row it has here', f, c.SelectedFont);
    AssertEquals('and that row is its row on this machine', FLBPlainIndexOf(f), c.ItemIndex);
  finally
    dst.Free;
  end;
end;

procedure TFontListBoxTest.TestAFamilyThisMachineLacksIsNotSwappedForAnother;
var dst: TForm; c: TTyFontListBox;
begin
  dst := FLBFromText(FLBOldForm('NoSuchFontC', 1));
  try
    c := dst.FindComponent('F') as TTyFontListBox;
    AssertEquals('the list is this machine''s fonts', FLBPlainCount, c.Items.Count);
    AssertEquals('a family this machine lacks leaves nothing selected', -1, c.ItemIndex);
  finally
    dst.Free;
  end;
end;

procedure FLBNeedFonts;
begin
  if (Screen.Fonts.IndexOf('Courier New') < 0) or (Screen.Fonts.IndexOf('Arial') < 0) then
    raise EIgnoredTest.Create('needs Courier New and Arial installed');
end;

procedure FLBAssertSame(const AWhat: string; AExpected, AActual: TStrings);
var i: Integer;
begin
  TAssert.AssertEquals(AWhat + ': row count', AExpected.Count, AActual.Count);
  for i := 0 to AExpected.Count - 1 do
    TAssert.AssertEquals(AWhat + ': row ' + IntToStr(i), AExpected[i], AActual[i]);
end;

procedure TFontListBoxTest.TestFixedPitchOnlyListsTheSystemsFixedFamilies;
var c: TTyFontListBox; fixed, plain: TStringList;
begin
  FLBNeedFonts;
  fixed := TStringList.Create;
  plain := TStringList.Create;
  c := TTyFontListBox.Create(nil);
  try
    TyGetFontFamilies(fixed, True);
    FontsWithoutVerticalVariants(plain);
    FLBAssertSame('a new list box', plain, c.Items);
    c.FixedPitchOnly := True;
    FLBAssertSame('on', fixed, c.Items);
    AssertTrue('Arial is not offered', c.Items.IndexOf('Arial') < 0);
    c.FixedPitchOnly := False;
    FLBAssertSame('off again', plain, c.Items);
  finally
    c.Free;
    plain.Free;
    fixed.Free;
  end;
end;

procedure TFontListBoxTest.TestTogglingKeepsAFamilyStillListed;
var c: TTyFontListBox;
begin
  FLBNeedFonts;
  c := TTyFontListBox.Create(nil);
  try
    c.SelectedFont := 'Courier New';
    c.FixedPitchOnly := True;
    AssertEquals('a fixed-pitch choice stays chosen', 'Courier New', c.SelectedFont);
    c.FixedPitchOnly := False;
    AssertEquals('and back', 'Courier New', c.SelectedFont);
  finally
    c.Free;
  end;
end;

procedure TFontListBoxTest.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TFontListBoxTest.TestTogglingOnDropsAProportionalChoice;
var c: TTyFontListBox;
begin
  FLBNeedFonts;
  c := TTyFontListBox.Create(nil);
  try
    c.SelectedFont := 'Arial';
    FChanges := 0;
    c.OnChange := @CountChange;
    c.FixedPitchOnly := True;
    AssertEquals('a family no longer listed leaves nothing selected', -1, c.ItemIndex);
    AssertEquals('the choice changed: OnChange once', 1, FChanges);
  finally
    c.Free;
  end;
end;

procedure TFontListBoxTest.TestTogglingWithNothingSelectedSelectsNothing;
var c: TTyFontListBox;
begin
  FLBNeedFonts;
  c := TTyFontListBox.Create(nil);
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

procedure TFontListBoxTest.TestTogglingKeepsTheChoiceWithoutOnChange;
var c: TTyFontListBox;
begin
  FLBNeedFonts;
  c := TTyFontListBox.Create(nil);
  try
    c.SelectedFont := 'Courier New';
    FChanges := 0;
    c.OnChange := @CountChange;
    c.FixedPitchOnly := True;
    AssertEquals('on: still Courier New', 'Courier New', c.SelectedFont);
    AssertEquals('at its row in the shorter list', c.Items.IndexOf('Courier New'), c.ItemIndex);
    c.FixedPitchOnly := False;
    AssertEquals('off: still Courier New', 'Courier New', c.SelectedFont);
    AssertEquals('the same family at another row is no change: no OnChange', 0, FChanges);
  finally
    c.Free;
  end;
end;

procedure TFontListBoxTest.TestAFormFileWithFixedPitchOnlyLoadsTheFilteredList;
var dst: TForm; c: TTyFontListBox; fixed: TStringList;
begin
  FLBNeedFonts;
  fixed := TStringList.Create;
  dst := FLBFromText(
    'object Form1: TForm' + LineEnding +
    '  object F: TTyFontListBox' + LineEnding +
    '    ItemIndex = ' + IntToStr(FLBPlainIndexOf('Courier New')) + LineEnding +
    '    FixedPitchOnly = True' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding);
  try
    c := dst.FindComponent('F') as TTyFontListBox;
    TyGetFontFamilies(fixed, True);
    AssertTrue('read in', c.FixedPitchOnly);
    FLBAssertSame('the list Loaded built', fixed, c.Items);
    AssertEquals('the chosen family, by name', 'Courier New', c.SelectedFont);
  finally
    dst.Free;
    fixed.Free;
  end;
end;

procedure TFontListBoxTest.TestFixedPitchOnlyIsWrittenOnlyWhenOn;
var src: TForm; c: TTyFontListBox;
begin
  src := TForm.CreateNew(nil);
  try
    c := TTyFontListBox.Create(src);
    c.Name := 'F';
    c.Parent := src;
    AssertTrue('off is the default and is not written',
      Pos('FixedPitchOnly', FLBFormText(src)) = 0);
    c.FixedPitchOnly := True;
    AssertTrue('on is written', Pos('FixedPitchOnly = True', FLBFormText(src)) > 0);
  finally
    src.Free;
  end;
end;

initialization
  RegisterTest(TFontListBoxTest);
end.
