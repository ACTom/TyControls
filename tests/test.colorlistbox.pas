unit test.colorlistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, Forms, fpcunit, testregistry, tyControls.ColorBox,
  tyControls.ListBox, tyControls.ColorListBox;
type
  TColorListBoxTest = class(TTestCase)
  published
    procedure TestPaletteAndColorAt;
    procedure TestSelected;
    procedure TestSortedKeepsColors;
    procedure TestAddAndClear;
    procedure TestFormFileKeepsAnExtendedSelection;
    procedure TestFormFileKeepsTheDefaultPalette;
    procedure TestFormFileNoLongerCarriesItems;
    procedure TestA300FormFileStillLoads;
    procedure TestAPlainListBoxStillWritesItsItems;
  end;
implementation

procedure TColorListBoxTest.TestPaletteAndColorAt;
var c: TTyColorListBox;
begin
  c := TTyColorListBox.Create(nil);
  try
    AssertEquals('16-colour palette', 16, c.Items.Count);
    AssertTrue('item 0 is black', c.ColorAt(0) = clBlack);
    AssertTrue('item 9 is red', c.ColorAt(9) = clRed);
    AssertTrue('out of range -> clNone', c.ColorAt(99) = clNone);
    AssertEquals('default selection', 0, c.ItemIndex);
  finally c.Free; end;
end;

procedure TColorListBoxTest.TestSelected;
var c: TTyColorListBox;
begin
  c := TTyColorListBox.Create(nil);
  try
    AssertTrue('initial selected black', c.Selected = clBlack);
    c.Selected := clRed;
    AssertEquals('picks red index', 9, c.ItemIndex);
    AssertTrue('selected red', c.Selected = clRed);
    c.Selected := TColor($00123456);
    AssertEquals('palette untouched', 16, c.Items.Count);
    AssertEquals('nothing selected', -1, c.ItemIndex);
  finally c.Free; end;
end;

procedure TColorListBoxTest.TestSortedKeepsColors;
var c: TTyColorListBox; idx: Integer;
begin
  c := TTyColorListBox.Create(nil);
  try
    c.Sorted := True;   // colours in Objects[] must ride along with the sorted names
    idx := c.Items.IndexOf('Red');
    AssertTrue('Red present', idx >= 0);
    AssertTrue('Red -> clRed after sort', c.ColorAt(idx) = clRed);
    idx := c.Items.IndexOf('White');
    AssertTrue('White -> clWhite after sort', c.ColorAt(idx) = clWhite);
  finally c.Free; end;
end;

procedure TColorListBoxTest.TestAddAndClear;
var c: TTyColorListBox;
begin
  c := TTyColorListBox.Create(nil);
  try
    c.ClearColors;
    AssertEquals('cleared', 0, c.Items.Count);
    c.AddColor('Sky', clSkyBlue);
    AssertTrue('color kept', c.ColorAt(0) = clSkyBlue);
    AssertEquals('name kept', 'Sky', c.Items[0]);
  finally c.Free; end;
end;

{ Selected is read from a form file before the palette that holds it is final: the palette is
  only rebuilt from Style in Loaded, and TTyColorListBox publishes Selected ahead of Style. A colour from the extended palette
  was looked up in the default 16, missed, and came back as nothing selected. }
procedure TColorListBoxTest.TestFormFileKeepsAnExtendedSelection;
var
  src, dst: TForm;
  c: TTyColorListBox;
  ms: TMemoryStream;
begin
  src := TForm.CreateNew(nil);
  dst := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    c := TTyColorListBox.Create(src);
    c.Name := 'CB';
    c.Parent := src;
    c.Style := [cbStandardColors, cbExtendedColors, cbPrettyNames];
    c.Selected := clMoneyGreen;
    AssertTrue('setup: the extended palette holds clMoneyGreen', c.Selected = clMoneyGreen);
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    c := dst.FindComponent('CB') as TTyColorListBox;
    AssertTrue('the palette came back', cbExtendedColors in c.Style);
    AssertEquals('and so did the selected colour', clMoneyGreen, c.Selected);
    { From here on the box's own selection is what a palette rebuild keeps, not the colour the
      form file held. }
    c.Selected := clBlue;
    c.Style := c.Style + [cbIncludeNone];
    AssertEquals('a later Style change keeps the current selection, not the loaded one',
      clBlue, c.Selected);
  finally
    ms.Free;
    src.Free;
    dst.Free;
  end;
end;

{ ---- a colour palette in a form file ----

  A form file stores a TStrings as its strings alone, so Items could only ever carry the colour
  NAMES. 3.0.0 wrote them for every box, and reading them back replaced the palette with names
  over black swatches (and lost the selection with it) on every form that left Style at its
  default -- a form that set Style was rebuilt in Loaded and escaped. The palette is now always
  rebuilt from Style in Loaded, as LCL does, and Items is no longer written. }

function CLBRoundTrip(ASrc: TForm): TForm;
var ms: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(ASrc);
    ms.Position := 0;
    ms.ReadComponent(Result);
  finally
    ms.Free;
  end;
end;

function CLBFormText(ASrc: TForm): string;
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

function CLBFromText(const AText: string): TForm;
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

procedure TColorListBoxTest.TestFormFileKeepsTheDefaultPalette;
var src, dst: TForm; c, fresh: TTyColorListBox; i: Integer;
begin
  src := TForm.CreateNew(nil);
  dst := nil;
  fresh := TTyColorListBox.Create(nil);
  try
    c := TTyColorListBox.Create(src);
    c.Name := 'CB';
    c.Parent := src;
    c.Selected := clRed;
    AssertEquals('setup: red is selected', clRed, c.Selected);
    dst := CLBRoundTrip(src);
    c := dst.FindComponent('CB') as TTyColorListBox;
    AssertEquals('the default palette came back whole', fresh.Items.Count, c.Items.Count);
    for i := 0 to fresh.Items.Count - 1 do
      AssertEquals(Format('row %d (%s) keeps its colour, not black', [i, fresh.Items[i]]),
        fresh.ColorAt(i), c.ColorAt(i));
    AssertEquals('and the selection with it', clRed, c.Selected);
  finally
    fresh.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TColorListBoxTest.TestFormFileNoLongerCarriesItems;
var src: TForm; c: TTyColorListBox; t: string;
begin
  src := TForm.CreateNew(nil);
  try
    c := TTyColorListBox.Create(src);
    c.Name := 'CB';
    c.Parent := src;
    c.Selected := clRed;
    t := CLBFormText(src);
    AssertTrue('precondition: the box is in the form file' + LineEnding + t, Pos('object CB', t) > 0);
    AssertTrue('Items is not written: it can only hold names, and Style rebuilds the palette'
      + LineEnding + t, Pos('Items.Strings', t) = 0);
  finally
    src.Free;
  end;
end;

procedure TColorListBoxTest.TestA300FormFileStillLoads;
const
  { What 3.0.0 wrote for a box on the default palette with red selected. }
  LFM =
    'object Form1: TForm' + LineEnding +
    '  object CB: TTyColorListBox' + LineEnding +
    '    Items.Strings = (' + LineEnding +
    '      ''Black''' + LineEnding + '      ''Maroon''' + LineEnding + '      ''Green''' + LineEnding +
    '      ''Olive''' + LineEnding + '      ''Navy''' + LineEnding + '      ''Purple''' + LineEnding +
    '      ''Teal''' + LineEnding + '      ''Gray''' + LineEnding + '      ''Silver''' + LineEnding +
    '      ''Red''' + LineEnding + '      ''Lime''' + LineEnding + '      ''Yellow''' + LineEnding +
    '      ''Blue''' + LineEnding + '      ''Fuchsia''' + LineEnding + '      ''Aqua''' + LineEnding +
    '      ''White''' + LineEnding +
    '    )' + LineEnding +
    '    ItemIndex = 9' + LineEnding +
    '    Selected = clRed' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
var dst: TForm; c, fresh: TTyColorListBox; i: Integer;
begin
  dst := nil;
  fresh := TTyColorListBox.Create(nil);
  try
    dst := CLBFromText(LFM);
    c := dst.FindComponent('CB') as TTyColorListBox;
    AssertEquals('the palette is rebuilt, not the 16 bare names', fresh.Items.Count, c.Items.Count);
    for i := 0 to fresh.Items.Count - 1 do
      AssertEquals(Format('row %d (%s) has its colour back', [i, fresh.Items[i]]),
        fresh.ColorAt(i), c.ColorAt(i));
    AssertEquals('and red is selected again', clRed, c.Selected);
  finally
    fresh.Free;
    dst.Free;
  end;
end;

{ The switch that keeps a colour list's Items out of the form file lives on TTyListBox, and only
  the colour list turns it off: a plain list's Items IS what the author typed in, and a list box
  that stopped writing it would come back empty. }
procedure TColorListBoxTest.TestAPlainListBoxStillWritesItsItems;
var src: TForm; lb: TTyListBox; t: string;
begin
  src := TForm.CreateNew(nil);
  try
    lb := TTyListBox.Create(src);
    lb.Name := 'LB';
    lb.Parent := src;
    lb.Items.Add('Alpha');
    lb.Items.Add('Beta');
    t := CLBFormText(src);
    AssertTrue('a plain list box writes its Items' + LineEnding + t,
      (Pos('Items.Strings', t) > 0) and (Pos('''Beta''', t) > 0));
  finally
    src.Free;
  end;
end;

initialization
  RegisterTest(TColorListBoxTest);
end.
