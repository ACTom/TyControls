unit test.advancedlistbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Forms, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.StyleModel, tyControls.Painter,
  tyControls.IconFont, tyControls.ImageCollection, tyControls.BuiltinThemes,
  tyControls.ListBox, tyControls.AdvancedListBox, tyControls.AdvancedComboBox,
  test.devicescale.support;
type
  TAdvancedListBoxTest = class(TTestCase)
  published
    procedure TestAddItem;
    procedure TestSubtitleEmpty;
    procedure TestImageIndexOutOfRange;
    procedure TestPartsSurviveSort;
  end;

  { Reaches the row state and the mouse, and counts the repaints asked for. }
  TRichListProbe = class(TTyAdvancedListBox)
  public
    Invalidations: Integer;
    function StatesOfRow(AIndex: Integer; ABase: TTyStateSet): TTyStateSet;
    procedure Press(X, Y: Integer);
    procedure Invalidate; override;
  end;

  { Reaches the list a rich combo drops down. }
  TRichComboProbe = class(TTyAdvancedComboBox)
  public
    function NewDropList: TTyCustomListBox;
  end;

  { ItemEnabled[]: one row turned off. It is a look -- the row is drawn in the theme's
    disabled row style and can still be selected and clicked, as in LCL's check list -- and
    the flag lives in the row's own Items.Objects[] slot beside the image index, so it goes
    wherever the row goes. }
  TAdvancedListBoxItemEnabledTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FColl: TTyImageCollection;
    FFont: TTyIconFont;
    FList: TTyVirtualImageList;
    FBox: TRichListProbe;
    FChanges: Integer;
    procedure Changed(Sender: TObject);
    { the pixels of row ARow as one string, for comparing two paints of it }
    function RowPixels(ARow: Integer): string;
    function RowHasBlock(ARow: Integer; AColor: TTyColor): Boolean;
    procedure Theme(ANormal, ADisabled: TTyColor);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRowsStartEnabled;
    procedure TestOneRowIsTurnedOffAndOnAgain;
    procedure TestOutOfRangeReadsEnabledAndIgnoresAWrite;
    procedure TestARowWithNoImageWrittenAsANegativeIndex;
    procedure TestTurningARowOffOrOnRepaints;
    procedure TestImageIndexOfIsWhatItWas;
    procedure TestAnEnabledRowsSlotIsWhatItAlwaysWas;
    procedure TestTheFlagFollowsItsRowThroughASort;
    procedure TestTheFlagFollowsItsRowThroughDeleteInsertMoveAndExchange;
    procedure TestTheFlagIsCopiedWithTheItems;
    procedure TestARowCopiedIntoAComboKeepsItsImage;
    procedure TestARowCopiedIntoAComboIsDrawnWithItsImage;
    procedure TestATurnedOffRowResolvesTheDisabledState;
    procedure TestATurnedOffRowIsDrawnInTheDisabledRowStyle;
    procedure TestEveryBuiltInThemeGivesADisabledRowItsOwnInk;
    procedure TestATurnedOffRowsGlyphIsTheDisabledInkAndItsImageIsGhosted;
    procedure TestATurnedOffRowsImageIsGhostedRightToLeftToo;
    procedure TestATurnedOffRowCanStillBeSelected;
    procedure TestATurnedOffRowCanStillBeClicked;
  end;
implementation

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

const
  { Colours no default produces. }
  InkA: TTyColor   = $FFD2283C;
  InkDis: TTyColor = $FF8C6E14;
  Photo: TTyColor  = $FF145AE6;
  GLYPH = 0;
  IMAGE = 1;
  ROWH = 40;

procedure TAdvancedListBoxTest.TestAddItem;
var lb: TTyAdvancedListBox;
begin
  lb := TTyAdvancedListBox.Create(nil);
  try
    lb.AddItem('Alice', 'Engineer', 3);
    lb.AddItem('Bob', 'Designer', -1);
    AssertEquals('two items', 2, lb.Items.Count);
    AssertEquals('title 0', 'Alice', lb.TitleOf(0));
    AssertEquals('subtitle 0', 'Engineer', lb.SubtitleOf(0));
    AssertEquals('image 0', 3, lb.ImageIndexOf(0));
    AssertEquals('title 1', 'Bob', lb.TitleOf(1));
    AssertEquals('subtitle 1', 'Designer', lb.SubtitleOf(1));
    AssertEquals('image 1 -> none', -1, lb.ImageIndexOf(1));
  finally lb.Free; end;
end;

procedure TAdvancedListBoxTest.TestSubtitleEmpty;
var lb: TTyAdvancedListBox;
begin
  lb := TTyAdvancedListBox.Create(nil);
  try
    lb.AddItem('Solo', '', 0);
    AssertEquals('title kept', 'Solo', lb.TitleOf(0));
    AssertEquals('empty subtitle', '', lb.SubtitleOf(0));
    AssertEquals('image 0', 0, lb.ImageIndexOf(0));
  finally lb.Free; end;
end;

procedure TAdvancedListBoxTest.TestImageIndexOutOfRange;
var lb: TTyAdvancedListBox;
begin
  lb := TTyAdvancedListBox.Create(nil);
  try
    lb.AddItem('a', 'x', 2);
    AssertEquals('negative index -> -1', -1, lb.ImageIndexOf(-1));
    AssertEquals('past end -> -1', -1, lb.ImageIndexOf(99));
    AssertEquals('past-end title -> empty', '', lb.TitleOf(99));
    AssertEquals('past-end subtitle -> empty', '', lb.SubtitleOf(99));
  finally lb.Free; end;
end;

procedure TAdvancedListBoxTest.TestPartsSurviveSort;
var lb: TTyAdvancedListBox; idx: Integer;
begin
  lb := TTyAdvancedListBox.Create(nil);
  try
    lb.AddItem('Zebra', 'stripes', 2);
    lb.AddItem('Apple', 'fruit', 7);
    lb.AddItem('Mango', 'sweet', 4);
    lb.Sorted := True;   // reorders by joined string (title first); Objects[] must follow
    idx := lb.Items.IndexOf('Apple' + LineEnding + 'fruit');
    AssertTrue('Apple present', idx >= 0);
    AssertEquals('Apple keeps title after sort', 'Apple', lb.TitleOf(idx));
    AssertEquals('Apple keeps subtitle after sort', 'fruit', lb.SubtitleOf(idx));
    AssertEquals('Apple keeps image 7 after sort', 7, lb.ImageIndexOf(idx));
    idx := lb.Items.IndexOf('Zebra' + LineEnding + 'stripes');
    AssertEquals('Zebra keeps image 2 after sort', 2, lb.ImageIndexOf(idx));
    idx := lb.Items.IndexOf('Mango' + LineEnding + 'sweet');
    AssertEquals('Mango keeps image 4 after sort', 4, lb.ImageIndexOf(idx));
  finally lb.Free; end;
end;

{ ---- ItemEnabled ------------------------------------------------------------------------- }

function TRichListProbe.StatesOfRow(AIndex: Integer; ABase: TTyStateSet): TTyStateSet;
begin
  Result := ItemStatesFor(AIndex, ABase);
end;

procedure TRichListProbe.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

function TRichComboProbe.NewDropList: TTyCustomListBox;
begin
  Result := CreatePopupList;
end;

procedure TRichListProbe.Press(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
  MouseUp(mbLeft, [], X, Y);
end;

function Css(AColor: TTyColor): string;
begin
  Result := Format('#%.2x%.2x%.2x', [TyRedOf(AColor), TyGreenOf(AColor), TyBlueOf(AColor)]);
end;

procedure TAdvancedListBoxItemEnabledTest.SetUp;
var
  bmp: TBGRABitmap;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FCtl := TTyStyleController.Create(nil);
  FColl := TTyImageCollection.Create(nil);
  bmp := TBGRABitmap.Create(32, 32, TyColorToBGRA(Photo));
  try
    FColl.AddBitmap('photo', bmp);
  finally
    bmp.Free;
  end;
  FFont := TTyIconFont.Create(nil);
  FFont.FontFamily := 'Arial';
  FFont.MapGlyph('block', $2588);
  FList := TTyVirtualImageList.Create(nil);
  FList.Collection := FColl;
  FList.IconFont := FFont;
  FList.Names.Text := 'block' + LineEnding + 'photo';
  FBox := TRichListProbe.Create(FForm);
  FBox.Parent := FForm;
  FBox.Controller := FCtl;
  FBox.Font.PixelsPerInch := 96;
  FBox.SetBounds(0, 0, 240, 200);
  FBox.ItemHeight := ROWH;
  FBox.OnChange := @Changed;
  FChanges := 0;
end;

procedure TAdvancedListBoxItemEnabledTest.TearDown;
begin
  FForm.Free;
  FList.Free;
  FFont.Free;
  FColl.Free;
  FCtl.Free;
end;

procedure TAdvancedListBoxItemEnabledTest.Changed(Sender: TObject);
begin
  Inc(FChanges);
end;

function TAdvancedListBoxItemEnabledTest.RowPixels(ARow: Integer): string;
var
  bmp: TBGRABitmap;
  r: TRect;
  x, y, w, at: Integer;
  px: TBGRAPixel;
begin
  Result := '';
  r := FBox.ItemRect(ARow);
  AssertTrue('setup: row ' + IntToStr(ARow) + ' is on screen', r.Bottom > r.Top);
  w := r.Right - r.Left;
  bmp := TyPaintOwnSurface(FBox, 1);
  try
    SetLength(Result, (r.Bottom - r.Top) * w * 3);
    for y := r.Top to r.Bottom - 1 do
      for x := r.Left to r.Right - 1 do
      begin
        px := bmp.GetPixel(x, y);
        at := ((y - r.Top) * w + (x - r.Left)) * 3;
        Result[at + 1] := Chr(px.red);
        Result[at + 2] := Chr(px.green);
        Result[at + 3] := Chr(px.blue);
      end;
  finally
    bmp.Free;
  end;
end;

function TAdvancedListBoxItemEnabledTest.RowHasBlock(ARow: Integer; AColor: TTyColor): Boolean;
const
  CBlock = 5;
var
  bmp: TBGRABitmap;
  r: TRect;
  x, y, dx, dy: Integer;
  px: TBGRAPixel;
  solid: Boolean;
begin
  Result := False;
  r := FBox.ItemRect(ARow);
  bmp := TyPaintOwnSurface(FBox, 1);
  try
    for y := r.Top to r.Bottom - CBlock do
      for x := r.Left to r.Right - CBlock do
      begin
        solid := True;
        for dy := 0 to CBlock - 1 do
          for dx := 0 to CBlock - 1 do
          begin
            px := bmp.GetPixel(x + dx, y + dy);
            if (px.red <> TyRedOf(AColor)) or (px.green <> TyGreenOf(AColor))
               or (px.blue <> TyBlueOf(AColor)) then solid := False;
          end;
        if solid then Exit(True);
      end;
  finally
    bmp.Free;
  end;
end;

procedure TAdvancedListBoxItemEnabledTest.Theme(ANormal, ADisabled: TTyColor);
begin
  FCtl.StyleOverride := Format('TyListItem { color: %s; } TyListItem:disabled { color: %s; }',
    [Css(ANormal), Css(ADisabled)]);
end;

procedure TAdvancedListBoxItemEnabledTest.TestRowsStartEnabled;
begin
  FBox.AddItem('a', 'x', 3);
  FBox.AddItem('b', '', -1);
  FBox.Items.Add('plain');   { a row added the list box's way has an empty slot }
  AssertTrue('a row with an image', FBox.ItemEnabled[0]);
  AssertTrue('a row with none', FBox.ItemEnabled[1]);
  AssertTrue('a row added through Items', FBox.ItemEnabled[2]);
end;

procedure TAdvancedListBoxItemEnabledTest.TestOneRowIsTurnedOffAndOnAgain;
begin
  FBox.AddItem('a', 'x', 3);
  FBox.AddItem('b', 'y', 5);
  FBox.ItemEnabled[1] := False;
  AssertTrue('the other row is untouched', FBox.ItemEnabled[0]);
  AssertFalse('the row is off', FBox.ItemEnabled[1]);
  FBox.ItemEnabled[1] := True;
  AssertTrue('and on again', FBox.ItemEnabled[1]);
end;

procedure TAdvancedListBoxItemEnabledTest.TestOutOfRangeReadsEnabledAndIgnoresAWrite;
begin
  FBox.AddItem('a', 'x', 3);
  AssertTrue('before the first', FBox.ItemEnabled[-1]);
  AssertTrue('past the last', FBox.ItemEnabled[9]);
  FBox.ItemEnabled[-1] := False;
  FBox.ItemEnabled[9] := False;
  AssertTrue('the one row there is still on', FBox.ItemEnabled[0]);
  AssertEquals('and nothing was added', 1, FBox.Items.Count);
end;

procedure TAdvancedListBoxItemEnabledTest.TestARowWithNoImageWrittenAsANegativeIndex;
begin
  { "No image" is any negative index, and the slot then holds a number that is not positive.
    Such a row is on, reads back what was written, and can be turned off like any other. }
  FBox.AddItem('a', '', -5);
  AssertTrue('it starts on', FBox.ItemEnabled[0]);
  AssertEquals('and reads back the index it was given', -5, FBox.ImageIndexOf(0));
  FBox.ItemEnabled[0] := False;
  AssertFalse('it can be turned off', FBox.ItemEnabled[0]);
  AssertTrue('and still has no image', FBox.ImageIndexOf(0) < 0);
  FBox.ItemEnabled[0] := True;
  AssertTrue('and on again', FBox.ItemEnabled[0]);
  AssertTrue('still with no image', FBox.ImageIndexOf(0) < 0);
end;

procedure TAdvancedListBoxItemEnabledTest.TestTurningARowOffOrOnRepaints;
var
  before: Integer;
begin
  FBox.AddItem('a', '', -1);
  before := FBox.Invalidations;
  FBox.ItemEnabled[0] := False;
  AssertTrue('off: a repaint was asked for', FBox.Invalidations > before);
  before := FBox.Invalidations;
  FBox.ItemEnabled[0] := False;
  AssertEquals('the same value again: nothing to repaint', before, FBox.Invalidations);
  FBox.ItemEnabled[0] := True;
  AssertTrue('on: a repaint was asked for', FBox.Invalidations > before);
end;

procedure TAdvancedListBoxItemEnabledTest.TestImageIndexOfIsWhatItWas;
begin
  FBox.AddItem('a', 'x', 7);
  FBox.AddItem('b', 'y', 0);
  FBox.AddItem('c', 'z', -1);
  FBox.ItemEnabled[0] := False;
  FBox.ItemEnabled[1] := False;
  FBox.ItemEnabled[2] := False;
  AssertEquals('image 7, off', 7, FBox.ImageIndexOf(0));
  AssertEquals('image 0, off', 0, FBox.ImageIndexOf(1));
  AssertEquals('no image, off', -1, FBox.ImageIndexOf(2));
  FBox.ItemEnabled[0] := True;
  AssertEquals('image 7, on again', 7, FBox.ImageIndexOf(0));
  AssertEquals('titles are untouched', 'a', FBox.TitleOf(0));
  AssertEquals('subtitles too', 'y', FBox.SubtitleOf(1));
end;

procedure TAdvancedListBoxItemEnabledTest.TestAnEnabledRowsSlotIsWhatItAlwaysWas;
begin
  { Items.Objects[i] = image index + 1 is documented, and code reads it. }
  FBox.AddItem('a', 'x', 7);
  FBox.AddItem('b', 'y', -1);
  AssertEquals('image index + 1', 8, PtrInt(FBox.Items.Objects[0]));
  AssertEquals('0 for none', 0, PtrInt(FBox.Items.Objects[1]));
  FBox.ItemEnabled[0] := False;
  FBox.ItemEnabled[0] := True;
  AssertEquals('and again after the row was off and on', 8, PtrInt(FBox.Items.Objects[0]));
end;

procedure TAdvancedListBoxItemEnabledTest.TestTheFlagFollowsItsRowThroughASort;
var
  i: Integer;
begin
  FBox.AddItem('Zebra', 'stripes', 2);
  FBox.AddItem('Apple', 'fruit', 7);
  FBox.AddItem('Mango', 'sweet', 4);
  FBox.ItemEnabled[0] := False;     { Zebra, which sorts last }
  FBox.Sorted := True;
  for i := 0 to 2 do
    AssertEquals('row ' + FBox.TitleOf(i), FBox.TitleOf(i) <> 'Zebra', FBox.ItemEnabled[i]);
  AssertEquals('Zebra went to the end', 'Zebra', FBox.TitleOf(2));
  AssertEquals('with its image', 2, FBox.ImageIndexOf(2));
  { a row added to the sorted list lands in the middle and is on }
  FBox.AddItem('Kiwi', 'green', 1);
  for i := 0 to 3 do
    AssertEquals('after an add, row ' + FBox.TitleOf(i), FBox.TitleOf(i) <> 'Zebra',
      FBox.ItemEnabled[i]);
end;

procedure TAdvancedListBoxItemEnabledTest.TestTheFlagFollowsItsRowThroughDeleteInsertMoveAndExchange;

  procedure OnlyBIsOff(const AWhen: string);
  var
    i: Integer;
  begin
    for i := 0 to FBox.Items.Count - 1 do
      AssertEquals(AWhen + ': row ' + FBox.TitleOf(i), FBox.TitleOf(i) <> 'b', FBox.ItemEnabled[i]);
  end;

begin
  FBox.AddItem('a', '', 0);
  FBox.AddItem('b', '', 1);
  FBox.AddItem('c', '', 2);
  FBox.AddItem('d', '', 3);
  FBox.ItemEnabled[1] := False;
  FBox.Items.Delete(0);
  AssertEquals('setup: b is first now', 'b', FBox.TitleOf(0));
  OnlyBIsOff('after a delete');
  FBox.Items.Insert(0, 'new');
  AssertEquals('setup: b is second again', 'b', FBox.TitleOf(1));
  OnlyBIsOff('after an insert');
  FBox.Items.Move(1, 3);
  AssertEquals('setup: b is last', 'b', FBox.TitleOf(3));
  OnlyBIsOff('after a move');
  FBox.Items.Exchange(0, 3);
  AssertEquals('setup: b is first', 'b', FBox.TitleOf(0));
  OnlyBIsOff('after an exchange');
  AssertEquals('and b kept its image all the way', 1, FBox.ImageIndexOf(0));
end;

procedure TAdvancedListBoxItemEnabledTest.TestTheFlagIsCopiedWithTheItems;
var
  other: TTyAdvancedListBox;
begin
  FBox.AddItem('a', 'x', 3);
  FBox.AddItem('b', 'y', 5);
  FBox.ItemEnabled[1] := False;
  other := TTyAdvancedListBox.Create(nil);
  try
    other.Items.Assign(FBox.Items);
    AssertTrue('the row that was on', other.ItemEnabled[0]);
    AssertFalse('the row that was off', other.ItemEnabled[1]);
    AssertEquals('with its image', 5, other.ImageIndexOf(1));
  finally
    other.Free;
  end;
end;

procedure TAdvancedListBoxItemEnabledTest.TestARowCopiedIntoAComboKeepsItsImage;
var
  combo: TTyAdvancedComboBox;
begin
  { The rich combo keeps its rows the same way and is filled from a list like this one. }
  FBox.AddItem('a', 'x', 3);
  FBox.AddItem('b', 'y', 5);
  FBox.ItemEnabled[1] := False;
  combo := TTyAdvancedComboBox.Create(nil);
  try
    combo.Items.Assign(FBox.Items);
    AssertEquals('a row that was on', 3, combo.ImageIndexOf(0));
    AssertEquals('a row that was off', 5, combo.ImageIndexOf(1));
  finally
    combo.Free;
  end;
end;

procedure TAdvancedListBoxItemEnabledTest.TestARowCopiedIntoAComboIsDrawnWithItsImage;
const
  CBlock = 5;
var
  combo: TRichComboProbe;
  list: TTyCustomListBox;
  bmp: TBGRABitmap;
  x, y, dx, dy: Integer;
  px: TBGRAPixel;
  solid, found: Boolean;
begin
  FBox.AddItem('', '', IMAGE);
  FBox.ItemEnabled[0] := False;
  combo := TRichComboProbe.Create(FForm);
  combo.Parent := FForm;
  combo.Controller := FCtl;
  combo.Images := FList;
  combo.Items.Assign(FBox.Items);
  list := combo.NewDropList;
  list.Parent := FForm;
  list.Controller := FCtl;
  list.Font.PixelsPerInch := 96;
  list.SetBounds(0, 0, 240, 120);
  list.ItemHeight := ROWH;
  list.Items.Assign(combo.Items);
  found := False;
  bmp := TyPaintOwnSurface(list, 1);
  try
    for y := 0 to bmp.Height - CBlock do
      for x := 0 to bmp.Width - CBlock do
      begin
        solid := True;
        for dy := 0 to CBlock - 1 do
          for dx := 0 to CBlock - 1 do
          begin
            px := bmp.GetPixel(x + dx, y + dy);
            if (px.red <> TyRedOf(Photo)) or (px.green <> TyGreenOf(Photo))
               or (px.blue <> TyBlueOf(Photo)) then solid := False;
          end;
        if solid then found := True;
      end;
  finally
    bmp.Free;
  end;
  AssertTrue('the dropped-down row shows the image of a row that was off in the list', found);
end;

procedure TAdvancedListBoxItemEnabledTest.TestATurnedOffRowResolvesTheDisabledState;
begin
  FBox.AddItem('a', '', -1);
  FBox.AddItem('b', '', -1);
  FBox.ItemEnabled[1] := False;
  AssertTrue('off: disabled', tysDisabled in FBox.StatesOfRow(1, [tysNormal]));
  AssertFalse('off: not also normal', tysNormal in FBox.StatesOfRow(1, [tysNormal]));
  AssertFalse('off: nor hovered', tysHover in FBox.StatesOfRow(1, [tysHover]));
  AssertTrue('off and selected: still the selected row', tysActive in FBox.StatesOfRow(1, [tysActive]));
  AssertTrue('off and selected: and disabled', tysDisabled in FBox.StatesOfRow(1, [tysActive]));
  AssertFalse('on: not disabled', tysDisabled in FBox.StatesOfRow(0, [tysNormal]));
  AssertTrue('on: normal', tysNormal in FBox.StatesOfRow(0, [tysNormal]));
  AssertTrue('on: hovered when it is', tysHover in FBox.StatesOfRow(0, [tysHover]));
end;

procedure TAdvancedListBoxItemEnabledTest.TestATurnedOffRowIsDrawnInTheDisabledRowStyle;
var
  on0, on1, off0, off1, asDisabled1: string;
begin
  FBox.AddItem('Build failed', 'errors: 1', -1);
  FBox.AddItem('Build failed', 'errors: 1', -1);
  Theme(InkA, InkDis);
  on0 := RowPixels(0);
  on1 := RowPixels(1);
  FBox.ItemEnabled[1] := False;
  off0 := RowPixels(0);
  off1 := RowPixels(1);
  AssertTrue('the row that was turned off is drawn differently', off1 <> on1);
  AssertTrue('the other row is not', off0 = on0);
  { What "the disabled row style" draws: this row, on, in a theme whose rows are that ink. }
  FBox.ItemEnabled[1] := True;
  Theme(InkDis, InkA);
  asDisabled1 := RowPixels(1);
  AssertTrue('and it is the disabled row style, pixel for pixel', off1 = asDisabled1);
end;

procedure TAdvancedListBoxItemEnabledTest.TestEveryBuiltInThemeGivesADisabledRowItsOwnInk;
var
  n: TStringArray;
  i, md: Integer;
  m: TTyStyleModel;
  bad: string;
begin
  { Without a :disabled rule for the row a turned-off row looks like any other. }
  n := TyBuiltinThemeNames;
  bad := '';
  for i := 0 to High(n) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss(TyBuiltinThemeCss(n[i]));
      for md := 0 to 1 do
      begin
        if md = 0 then m.SetMode('light') else m.SetMode('dark');
        if m.ResolveStyle('TyListItem', '', [tysDisabled]).TextColor
           = m.ResolveStyle('TyListItem', '', [tysNormal]).TextColor then
          bad := bad + ' ' + n[i] + BoolToStr(md = 0, '(light)', '(dark)');
      end;
    finally
      m.Free;
    end;
  end;
  AssertEquals('themes whose disabled list row has the ink of an enabled one', '', bad);
end;

procedure TAdvancedListBoxItemEnabledTest.TestATurnedOffRowsGlyphIsTheDisabledInkAndItsImageIsGhosted;
begin
  FBox.Images := FList;
  FBox.AddItem('', '', GLYPH);
  FBox.AddItem('', '', IMAGE);
  Theme(InkA, InkDis);
  AssertTrue('on: the glyph in the row''s ink', RowHasBlock(0, InkA));
  AssertTrue('on: the image in its colours', RowHasBlock(1, Photo));
  FBox.ItemEnabled[0] := False;
  FBox.ItemEnabled[1] := False;
  { Exactly the disabled ink: ghosted on top of it the glyph would be a paler colour. }
  AssertTrue('off: the glyph in the disabled ink, at full strength', RowHasBlock(0, InkDis));
  AssertFalse('off: and not in the enabled one', RowHasBlock(0, InkA));
  AssertFalse('off: the image is ghosted', RowHasBlock(1, Photo));
  FBox.Images := nil;
end;

procedure TAdvancedListBoxItemEnabledTest.TestATurnedOffRowsImageIsGhostedRightToLeftToo;
begin
  FBox.BiDiMode := bdRightToLeft;
  FBox.Images := FList;
  FBox.AddItem('', '', GLYPH);
  FBox.AddItem('', '', IMAGE);
  Theme(InkA, InkDis);
  AssertTrue('on: the image in its colours', RowHasBlock(1, Photo));
  FBox.ItemEnabled[0] := False;
  FBox.ItemEnabled[1] := False;
  AssertTrue('off: the glyph in the disabled ink, at full strength', RowHasBlock(0, InkDis));
  AssertFalse('off: the image is ghosted', RowHasBlock(1, Photo));
  FBox.Images := nil;
end;

procedure TAdvancedListBoxItemEnabledTest.TestATurnedOffRowCanStillBeSelected;
begin
  FBox.AddItem('a', '', -1);
  FBox.AddItem('b', '', -1);
  FBox.ItemEnabled[1] := False;
  FBox.ItemIndex := 1;
  AssertEquals('from code', 1, FBox.ItemIndex);
  AssertFalse('and it stays off', FBox.ItemEnabled[1]);
end;

procedure TAdvancedListBoxItemEnabledTest.TestATurnedOffRowCanStillBeClicked;
var
  r: TRect;
begin
  FBox.AddItem('a', '', -1);
  FBox.AddItem('b', '', -1);
  FBox.ItemEnabled[1] := False;
  r := FBox.ItemRect(1);
  FChanges := 0;
  FBox.Press((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
  AssertEquals('the click selects it', 1, FBox.ItemIndex);
  AssertEquals('and OnChange says so', 1, FChanges);
  AssertFalse('and it stays off', FBox.ItemEnabled[1]);
end;

initialization
  RegisterTest(TAdvancedListBoxTest);
  RegisterTest(TAdvancedListBoxItemEnabledTest);
end.
