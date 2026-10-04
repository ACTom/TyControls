unit test.fontlistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, fpcunit, testregistry, tyControls.FontListBox;
type
  TFontListBoxTest = class(TTestCase)
  published
    procedure TestSelectedFontRoundTrip;
    procedure TestRefreshDoesNotCrash;
    procedure TestAFormFileDoesNotCarryThisMachinesFonts;
    procedure TestA300FormFileShowsThisMachinesFonts;
    procedure TestAFamilyThisMachineLacksIsNotSwappedForAnother;
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
      Screen.Fonts.Count, c.Items.Count);
    AssertEquals('none of the saving machine''s missing fonts is listed', -1,
      c.Items.IndexOf('NoSuchFontA'));
    AssertEquals('the chosen family is still chosen, at the row it has here', f, c.SelectedFont);
    AssertEquals('and that row is its row on this machine', Screen.Fonts.IndexOf(f), c.ItemIndex);
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
    AssertEquals('the list is this machine''s fonts', Screen.Fonts.Count, c.Items.Count);
    AssertEquals('a family this machine lacks leaves nothing selected', -1, c.ItemIndex);
  finally
    dst.Free;
  end;
end;

initialization
  RegisterTest(TFontListBoxTest);
end.
