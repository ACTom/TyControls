unit test.parity.listtext;
{ API-PARITY guards for the list/text family -- TTyListBox, TTyCheckListBox, TTyColorBox,
  TTyColorListBox and TTyListView -- written against the LCL declarations they mirror:

    C:/lazarus/lcl/colorbox.pas:35-43      TColorBoxStyles / TColorBoxStyle
    C:/lazarus/lcl/colorbox.pas:84-92      Style / Colors / ColorNames / Default- / NoneColorColor
    C:/lazarus/lcl/colorbox.pas:211-216    the TCustomColorListBox twins (Colors has a SETTER)
    C:/lazarus/lcl/colorbox.pas:669-688    SetColorList
    C:/lazarus/lcl/stdctrls.pp:435/647     Items: TStrings
    C:/lazarus/lcl/stdctrls.pp:529/668     TSelectionChangeEvent / OnSelectionChange
    C:/lazarus/lcl/stdctrls.pp:625/631     Lock- / UnlockSelectionChange
    C:/lazarus/lcl/stdctrls.pp:642         ExtendedSelect ... default true
    C:/lazarus/lcl/checklst.pas:79/84/85   AllowGrayed / ItemEnabled[] / State[]
    C:/lazarus/lcl/checklst.pas:233-243    Toggle's NextStateMap
    C:/lazarus/lcl/comctrls.pp:1582/1664/1665  Columns / Column[] / ColumnCount
    C:/lazarus/lcl/comctrls.pp:1610/1613   OnDeletion / OnInsert

  The defect at the centre of this file is TTyColorBox.Style. The Object Inspector offered
  it, the .lfm streamed it, and TTyColorBox.SetStyle threw every value away -- it forced
  csDropDownList and returned. There was no test to turn red, because the property did
  exactly what a test written against it would have asserted: nothing. It now carries what
  Style means on a colour box (which palette), and the combo mode is reached through the
  ancestor, exactly as LCL reintroduces it over TCustomComboBox's.

  Everything here is headless: controls are Create(nil), never parented, never painted. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, StdCtrls, Controls, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.ComboBox, tyControls.ListBox, tyControls.CheckListBox,
  tyControls.ColorBox, tyControls.ColorListBox, tyControls.ListView,
  tyControls.Columns;

type
  { Reaches the protected input seams: the row-hit geometry a click needs, and MouseDown. }
  TListBoxProbe = class(TTyListBox)
  public
    procedure ClickRow(ARow: Integer; AShift: TShiftState = []);
    function  StatesOfRow(AIndex: Integer): TTyStateSet;
  end;

  TCheckListProbe = class(TTyCheckListBox)
  public
    procedure ClickCheckColumn(ARow: Integer);
    procedure PressSpace;
    function  StatesOfRow(AIndex: Integer): TTyStateSet;
  end;

  TColourParityTest = class(TTestCase)
  private
    FAppended: Integer;
    procedure AppendBrand(Sender: TObject; AItems: TStrings);
  published
    procedure DefaultStyleReproducesTheCuratedSixteen;
    procedure StyleWritesRecomposeThePalette;
    procedure StyleCanAddTheSystemColours;
    procedure StyleCanAddNoneAndDefaultRows;
    procedure PrettyNamesAreOptedIntoNotBakedIn;
    procedure CustomColorSlotHoldsAnUnknownColour;
    procedure WithoutTheCustomSlotAnUnknownColourStillClears;
    procedure OnGetColorsRunsOnEveryRebuild;
    procedure SelectedColourSurvivesARecompose;
    procedure ColorsIndexerReadsAndWrites;
    procedure ColorNamesIndexerReadsTheRowName;
    procedure PseudoRowsPaintTheirOwnColour;
    procedure ListBoxTwinCarriesTheSamePaletteSurface;
  end;

  TListBoxParityTest = class(TTestCase)
  private
    FUserFlags: array of Boolean;
    FChanges:   Integer;
    procedure HSelectionChange(Sender: TObject; AUser: Boolean);
  published
    procedure ItemsAcceptsAnyTStrings;
    procedure OnSelectionChangeSaysUserForAClick;
    procedure OnSelectionChangeSaysCodeForAWrite;
    procedure OnSelectionChangeSaysUserForAKey;
    procedure LockSelectionChangeDemotesTheUserFlag;
    procedure ExtendedSelectDefaultsToLCLsDiscipline;
    procedure SimpleMultiSelectTogglesOnAPlainClick;
    procedure ExtendedMultiSelectStillReplacesOnAPlainClick;
  end;

  TCheckListParityTest = class(TTestCase)
  published
    procedure StateCarriesTheThirdValue;
    procedure CheckedReportsGrayedAsChecked;
    procedure ToggleSkipsGrayedUnlessAllowed;
    procedure DisabledRowRefusesTheMouse;
    procedure DisabledRowRefusesTheKeyboard;
    procedure ToggleItselfRefusesADisabledRow;
    procedure DisabledRowResolvesTheDisabledStyle;
    procedure DisabledSurvivesACheck;
    procedure ForeignObjectIsNotACheckState;
    procedure CheckAllHonoursItsTwoGuards;
  end;

  TListViewParityTest = class(TTestCase)
  private
    FInserted: array of Integer;
    FDeleted:  array of Integer;
    FCaptionsAtDeletion: TStringList;
    FLV: TTyListView;
    procedure HInsert(Sender: TObject; AIndex: Integer);
    procedure HDelete(Sender: TObject; AIndex: Integer);
  published
    procedure ColumnsReachableWithoutTheHeaderHop;
    procedure ColumnIndexerIsNilOutOfRange;
    procedure OnInsertFiresWithTheNewIndex;
    procedure OnDeletionFiresWhileTheRowStillExists;
    procedure OnDeletionFiresForEveryRowOnClear;
    procedure OwnerDataRaisesNeitherNotification;
  end;

implementation

{ ---------------------------------------------------------------- probes --- }

procedure TListBoxProbe.ClickRow(ARow: Integer; AShift: TShiftState);
begin
  MouseDown(mbLeft, AShift + [ssLeft], 4,
    ContentTopOffset + ARow * MulDiv(ItemHeight, Font.PixelsPerInch, 96) + 1);
end;

function TListBoxProbe.StatesOfRow(AIndex: Integer): TTyStateSet;
begin
  Result := ItemStatesFor(AIndex, [tysNormal]);
end;

procedure TCheckListProbe.ClickCheckColumn(ARow: Integer);
begin
  { X = 1 is inside the check column for any theme: the column is at least the row's left
    padding wide. }
  MouseDown(mbLeft, [ssLeft], 1,
    ContentTopOffset + ARow * MulDiv(ItemHeight, Font.PixelsPerInch, 96) + 1);
end;

procedure TCheckListProbe.PressSpace;
var k: Word;
begin
  k := VK_SPACE;
  KeyDown(k, []);
end;

function TCheckListProbe.StatesOfRow(AIndex: Integer): TTyStateSet;
begin
  Result := ItemStatesFor(AIndex, [tysNormal]);
end;

{ ------------------------------------------------------------ the colours --- }

procedure TColourParityTest.AppendBrand(Sender: TObject; AItems: TStrings);
begin
  Inc(FAppended);
  TyAddColorItem(AItems, 'Brand', TColor($00AB12CD));
end;

procedure TColourParityTest.DefaultStyleReproducesTheCuratedSixteen;
{ The default value of a published property is what every .lfm that omits the line is read
  as, so the one thing the new Style must NOT do is re-compose the palettes already in the
  field. TyDefaultColorBoxStyle is chosen to rebuild exactly the list the hard-coded
  constructor used to add -- same count, same order, same names. }
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  try
    AssertTrue('default style', c.Style = TyDefaultColorBoxStyle);
    AssertEquals('still the curated 16', 16, c.Items.Count);
    AssertEquals('row 0 name',  'Black', c.Items[0]);
    AssertEquals('row 9 name',  'Red',   c.Items[9]);
    AssertEquals('row 15 name', 'White', c.Items[15]);
    AssertTrue('row 0 colour',  c.ColorAt(0)  = clBlack);
    AssertTrue('row 9 colour',  c.ColorAt(9)  = clRed);
    AssertTrue('row 15 colour', c.ColorAt(15) = clWhite);
  finally c.Free; end;
end;

procedure TColourParityTest.StyleWritesRecomposeThePalette;
{ THE defect: Style was the combo's dropdown mode here, and SetStyle discarded every value
  written to it. A write now changes what the control holds. }
var c: TTyColorBox; before: Integer;
begin
  c := TTyColorBox.Create(nil);
  try
    before := c.Items.Count;
    c.Style := [cbStandardColors, cbExtendedColors, cbPrettyNames];
    AssertTrue('a Style write must change the palette', c.Items.Count <> before);
    AssertEquals('16 standard + 4 extended', 20, c.Items.Count);
    AssertEquals('extended row name', 'Sky Blue', c.Items[17]);
    AssertTrue('extended row colour', c.ColorAt(17) = clSkyBlue);
  finally c.Free; end;
end;

procedure TColourParityTest.StyleCanAddTheSystemColours;
var c: TTyColorBox; i, found: Integer;
begin
  c := TTyColorBox.Create(nil);
  try
    c.Style := [cbStandardColors, cbSystemColors, cbPrettyNames];
    AssertTrue('system colours joined the list', c.Items.Count > 16);
    found := -1;
    for i := 0 to c.Items.Count - 1 do
      if c.ColorAt(i) = clBtnFace then found := i;
    AssertTrue('clBtnFace is in the palette', found >= 0);
    AssertEquals('and is prettily named', 'Button Face', c.Items[found]);
    { and the opposite direction: the default composition has none of them }
    c.Style := TyDefaultColorBoxStyle;
    for i := 0 to c.Items.Count - 1 do
      AssertTrue('no system colour survives the standard-only style',
        c.ColorAt(i) <> clBtnFace);
  finally c.Free; end;
end;

procedure TColourParityTest.StyleCanAddNoneAndDefaultRows;
var c: TTyColorListBox; i, none_, def: Integer;
begin
  c := TTyColorListBox.Create(nil);
  try
    none_ := -1; def := -1;
    c.Style := [cbStandardColors, cbIncludeNone, cbIncludeDefault, cbPrettyNames];
    for i := 0 to c.Items.Count - 1 do
    begin
      if c.ColorAt(i) = clNone    then none_ := i;
      if c.ColorAt(i) = clDefault then def   := i;
    end;
    AssertTrue('a clNone row exists',    none_ >= 0);
    AssertTrue('a clDefault row exists', def   >= 0);
    AssertEquals('named None',    'None',    c.Items[none_]);
    AssertEquals('named Default', 'Default', c.Items[def]);
    { A clNone row must be SELECTABLE -- the whole point of asking for it. The old
      select-by-colour helper treated clNone as "clear the selection" unconditionally. }
    c.Selected := clNone;
    AssertEquals('clNone selects its row, it does not clear', none_, c.ItemIndex);
  finally c.Free; end;
end;

procedure TColourParityTest.PrettyNamesAreOptedIntoNotBakedIn;
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  try
    c.Style := [cbStandardColors];          { no cbPrettyNames }
    AssertEquals('raw identifier', 'clBlack', c.Items[0]);
    AssertEquals('raw identifier', 'clRed',   c.Items[9]);
    c.Style := [cbStandardColors, cbPrettyNames];
    AssertEquals('pretty', 'Black', c.Items[0]);
    AssertEquals('pretty', 'Red',   c.Items[9]);
  finally c.Free; end;
end;

procedure TColourParityTest.CustomColorSlotHoldsAnUnknownColour;
{ cbCustomColor makes row 0 a writable slot, which is what gives a colour the palette does
  not contain somewhere to live (LCL SetIndexOnColor, colorbox.pas:576-598). }
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  try
    c.Style := [cbCustomColor, cbStandardColors, cbPrettyNames];
    AssertEquals('custom slot plus the 16', 17, c.Items.Count);
    c.Selected := TColor($00123456);
    AssertEquals('it landed in the slot', 0, c.ItemIndex);
    AssertTrue('and the slot now holds it', c.ColorAt(0) = TColor($00123456));
    AssertEquals('without growing the palette', 17, c.Items.Count);
    { a colour that IS in the palette still wins over the slot }
    c.Selected := clRed;
    AssertTrue('a palette colour is not diverted into the slot', c.ItemIndex > 0);
  finally c.Free; end;
end;

procedure TColourParityTest.WithoutTheCustomSlotAnUnknownColourStillClears;
{ The behaviour the picker has always had, and which must not regress: no slot, no growth,
  ItemIndex = -1. }
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  try
    c.Selected := TColor($00123456);
    AssertEquals('palette untouched', 16, c.Items.Count);
    AssertEquals('nothing selected', -1, c.ItemIndex);
  finally c.Free; end;
end;

procedure TColourParityTest.OnGetColorsRunsOnEveryRebuild;
var c: TTyColorBox;
begin
  c := TTyColorBox.Create(nil);
  FAppended := 0;
  try
    c.OnGetColors := @AppendBrand;
    AssertEquals('not fired without cbCustomColors', 0, FAppended);
    c.Style := [cbStandardColors, cbPrettyNames, cbCustomColors];
    AssertEquals('fired once on the rebuild', 1, FAppended);
    AssertEquals('and its row is last', 'Brand', c.Items[c.Items.Count - 1]);
    AssertTrue('with its colour', c.ColorAt(c.Items.Count - 1) = TColor($00AB12CD));
    c.Style := [cbStandardColors, cbExtendedColors, cbPrettyNames, cbCustomColors];
    AssertEquals('and again on the next rebuild', 2, FAppended);
    AssertEquals('the brand row is not duplicated inside one pass', 'Brand',
      c.Items[c.Items.Count - 1]);
  finally c.Free; end;
end;

procedure TColourParityTest.SelectedColourSurvivesARecompose;
{ LCL keeps the chosen COLOUR across SetColorList, not its row index -- the row a colour
  sits in moves whenever the composition changes. }
var c: TTyColorBox; wasAt: Integer;
begin
  c := TTyColorBox.Create(nil);
  try
    c.Selected := clRed;
    wasAt := c.ItemIndex;
    c.Style := [cbCustomColor, cbStandardColors, cbPrettyNames];
    AssertTrue('still red', c.Selected = clRed);
    AssertTrue('at a different row', c.ItemIndex <> wasAt);
  finally c.Free; end;
end;

procedure TColourParityTest.ColorsIndexerReadsAndWrites;
{ `CLB.Colors[3] := clRed` -- recolouring one row in place. Ours was a read-only ColorAt
  function, so this needed a full palette rebuild. }
var l: TTyColorListBox; b: TTyColorBox;
begin
  l := TTyColorListBox.Create(nil);
  b := TTyColorBox.Create(nil);
  try
    AssertTrue('reads', l.Colors[9] = clRed);
    l.Colors[3] := clFuchsia;
    AssertTrue('writes', l.Colors[3] = clFuchsia);
    AssertTrue('and ColorAt agrees', l.ColorAt(3) = clFuchsia);
    AssertEquals('without disturbing the name', 'Olive', l.Items[3]);
    l.Colors[999] := clRed;                 { out of range is ignored, never raises }
    AssertEquals('still 16 rows', 16, l.Items.Count);
    b.Colors[2] := clAqua;
    AssertTrue('the combo carries the setter too', b.Colors[2] = clAqua);
  finally b.Free; l.Free; end;
end;

procedure TColourParityTest.ColorNamesIndexerReadsTheRowName;
var l: TTyColorListBox;
begin
  l := TTyColorListBox.Create(nil);
  try
    AssertEquals('names', 'Navy', l.ColorNames[4]);
    AssertEquals('out of range is empty, not an exception', '', l.ColorNames[999]);
  finally l.Free; end;
end;

procedure TColourParityTest.PseudoRowsPaintTheirOwnColour;
{ clNone / clDefault are sentinels: painted raw they are whatever $1FFFFFFF looks like.
  The swatch resolution is what DefaultColorColor / NoneColorColor exist for. }
var l: TTyColorListBox;
begin
  l := TTyColorListBox.Create(nil);
  try
    AssertTrue('None defaults to black',    l.NoneColorColor = clBlack);
    AssertTrue('Default defaults to black', l.DefaultColorColor = clBlack);
    l.NoneColorColor := clRed;
    AssertTrue('and is settable', l.NoneColorColor = clRed);
  finally l.Free; end;
end;

procedure TColourParityTest.ListBoxTwinCarriesTheSamePaletteSurface;
{ A fix that lands on one of the pair and not the other is half a fix. }
var l: TTyColorListBox;
begin
  l := TTyColorListBox.Create(nil);
  try
    AssertTrue('same default', l.Style = TyDefaultColorBoxStyle);
    AssertEquals('same curated 16', 16, l.Items.Count);
    l.Style := [cbStandardColors, cbExtendedColors, cbPrettyNames];
    AssertEquals('same recomposition', 20, l.Items.Count);
    AssertEquals('same swatch knobs', 0, l.ColorRectWidth);
    AssertEquals('same swatch knobs', 0, l.ColorRectOffset);
  finally l.Free; end;
end;

{ ----------------------------------------------------------- the list box --- }

procedure TListBoxParityTest.HSelectionChange(Sender: TObject; AUser: Boolean);
begin
  SetLength(FUserFlags, Length(FUserFlags) + 1);
  FUserFlags[High(FUserFlags)] := AUser;
  Inc(FChanges);
end;

procedure TListBoxParityTest.ItemsAcceptsAnyTStrings;
{ `LB.Items := AnyTStrings` was a compile error: the property was typed TStringList, the
  concrete class, where LCL types it as the abstract TStrings every other source is. }
var
  lb: TTyListBox;
  src: TStrings;
begin
  lb := TTyListBox.Create(nil);
  src := TStringList.Create;
  try
    src.Add('one'); src.Add('two');
    lb.Items := src;                        { the assignment that did not compile }
    AssertEquals('copied', 2, lb.Items.Count);
    AssertEquals('one', lb.Items[0]);
    AssertTrue('and the property is the abstract type', lb.Items is TStrings);
    AssertTrue('the backing store is still reachable for an OnChange hook',
      lb.ItemsList <> nil);
  finally src.Free; lb.Free; end;
end;

procedure TListBoxParityTest.OnSelectionChangeSaysUserForAClick;
var lb: TListBoxProbe;
begin
  lb := TListBoxProbe.Create(nil);
  SetLength(FUserFlags, 0); FChanges := 0;
  try
    lb.Items.Add('a'); lb.Items.Add('b'); lb.Items.Add('c');
    lb.Height := 200;
    lb.OnSelectionChange := @HSelectionChange;
    lb.ClickRow(1);
    AssertEquals('one notification', 1, FChanges);
    AssertTrue('a click is a USER change', FUserFlags[0]);
    AssertEquals('and it selected the row', 1, lb.ItemIndex);
  finally lb.Free; end;
end;

procedure TListBoxParityTest.OnSelectionChangeSaysCodeForAWrite;
var lb: TTyListBox;
begin
  lb := TTyListBox.Create(nil);
  SetLength(FUserFlags, 0); FChanges := 0;
  try
    lb.Items.Add('a'); lb.Items.Add('b');
    lb.OnSelectionChange := @HSelectionChange;
    lb.ItemIndex := 1;
    AssertEquals('one notification', 1, FChanges);
    AssertFalse('code moving the selection is NOT a user change', FUserFlags[0]);
  finally lb.Free; end;
end;

procedure TListBoxParityTest.OnSelectionChangeSaysUserForAKey;
var lb: TTyListBox;
begin
  lb := TTyListBox.Create(nil);
  SetLength(FUserFlags, 0); FChanges := 0;
  try
    lb.Items.Add('a'); lb.Items.Add('b'); lb.Items.Add('c');
    lb.Height := 200;
    lb.ItemIndex := 0;
    lb.OnSelectionChange := @HSelectionChange;
    lb.SimulateKeyDown(VK_DOWN);
    AssertEquals('one notification', 1, FChanges);
    AssertTrue('an arrow key is a USER change', FUserFlags[0]);
  finally lb.Free; end;
end;

procedure TListBoxParityTest.LockSelectionChangeDemotesTheUserFlag;
{ The lock does not suppress the event -- it says "whatever happens in here, I did it".
  customlistbox.inc:360 passes FLockSelectionChange = 0 as the User flag. }
var lb: TListBoxProbe;
begin
  lb := TListBoxProbe.Create(nil);
  SetLength(FUserFlags, 0); FChanges := 0;
  try
    lb.Items.Add('a'); lb.Items.Add('b'); lb.Items.Add('c');
    lb.Height := 200;
    lb.OnSelectionChange := @HSelectionChange;
    lb.LockSelectionChange;
    lb.ClickRow(2);
    lb.UnlockSelectionChange;
    AssertEquals('still notified', 1, FChanges);
    AssertFalse('but reported as programmatic', FUserFlags[0]);
    lb.ClickRow(1);
    AssertEquals('and the lock is released', 2, FChanges);
    AssertTrue('user again', FUserFlags[1]);
  finally lb.Free; end;
end;

procedure TListBoxParityTest.ExtendedSelectDefaultsToLCLsDiscipline;
var lb: TTyListBox;
begin
  lb := TTyListBox.Create(nil);
  try
    AssertTrue('default true, as stdctrls.pp:642', lb.ExtendedSelect);
  finally lb.Free; end;
end;

procedure TListBoxParityTest.SimpleMultiSelectTogglesOnAPlainClick;
{ ExtendedSelect = False: every plain click toggles that row and touches nothing else. The
  discipline was hard-coded to the extended one, so a touch/kiosk pick-many list -- where
  no modifier key is reachable -- could not be built at all. }
var lb: TListBoxProbe;
begin
  lb := TListBoxProbe.Create(nil);
  try
    lb.Items.Add('a'); lb.Items.Add('b'); lb.Items.Add('c');
    lb.Height := 200;
    lb.MultiSelect := True;
    lb.ExtendedSelect := False;
    lb.ClickRow(0);
    lb.ClickRow(2);
    AssertEquals('two rows picked with no modifier', 2, lb.SelCount);
    AssertTrue('row 0', lb.Selected[0]);
    AssertTrue('row 2', lb.Selected[2]);
    lb.ClickRow(0);
    AssertFalse('and a second tap unpicks it', lb.Selected[0]);
    AssertTrue('leaving the other alone', lb.Selected[2]);
  finally lb.Free; end;
end;

procedure TListBoxParityTest.ExtendedMultiSelectStillReplacesOnAPlainClick;
var lb: TListBoxProbe;
begin
  lb := TListBoxProbe.Create(nil);
  try
    lb.Items.Add('a'); lb.Items.Add('b'); lb.Items.Add('c');
    lb.Height := 200;
    lb.MultiSelect := True;
    lb.ClickRow(0);
    lb.ClickRow(2);
    AssertEquals('the default discipline still replaces', 1, lb.SelCount);
    AssertTrue('only the last', lb.Selected[2]);
  finally lb.Free; end;
end;

{ ----------------------------------------------------- the check list box --- }

procedure TCheckListParityTest.StateCarriesTheThirdValue;
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a'); c.Items.Add('b');
    AssertTrue('starts unchecked', c.State[0] = cbUnchecked);
    c.State[0] := cbGrayed;
    AssertTrue('a partially-selected row can say so', c.State[0] = cbGrayed);
    c.State[0] := cbChecked;
    AssertTrue('and back', c.State[0] = cbChecked);
    AssertTrue('the neighbour is untouched', c.State[1] = cbUnchecked);
  finally c.Free; end;
end;

procedure TCheckListParityTest.CheckedReportsGrayedAsChecked;
{ LCL checklst.pas:279-282 -- Checked[] is the two-value view: "not fully off". }
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a');
    c.State[0] := cbGrayed;
    AssertTrue('grayed reads as checked', c.Checked[0]);
    AssertEquals('and counts', 1, c.CheckedCount);
    c.Checked[0] := True;
    AssertTrue('writing True resolves it to cbChecked', c.State[0] = cbChecked);
    c.Checked[0] := False;
    AssertTrue('writing False resolves it to cbUnchecked', c.State[0] = cbUnchecked);
  finally c.Free; end;
end;

procedure TCheckListParityTest.ToggleSkipsGrayedUnlessAllowed;
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a');
    AssertFalse('AllowGrayed default False, as checklst.pas:79', c.AllowGrayed);
    c.Toggle(0);
    AssertTrue('off -> on', c.State[0] = cbChecked);
    c.Toggle(0);
    AssertTrue('on -> off', c.State[0] = cbUnchecked);
    c.AllowGrayed := True;
    c.Toggle(0);
    AssertTrue('off -> grayed', c.State[0] = cbGrayed);
    c.Toggle(0);
    AssertTrue('grayed -> on', c.State[0] = cbChecked);
    c.Toggle(0);
    AssertTrue('on -> off', c.State[0] = cbUnchecked);
  finally c.Free; end;
end;

procedure TCheckListParityTest.DisabledRowRefusesTheMouse;
var c: TCheckListProbe;
begin
  c := TCheckListProbe.Create(nil);
  try
    c.Items.Add('a'); c.Items.Add('b');
    c.Height := 200;
    c.ItemEnabled[0] := False;
    c.ClickCheckColumn(0);
    AssertFalse('a click cannot tick a disabled row', c.Checked[0]);
    c.ClickCheckColumn(1);
    AssertTrue('but the enabled neighbour still ticks', c.Checked[1]);
  finally c.Free; end;
end;

procedure TCheckListParityTest.DisabledRowRefusesTheKeyboard;
{ LCL's gate is `if (ItemIndex >= 0) and ItemEnabled[ItemIndex]`, checklst.pas:336. }
var c: TCheckListProbe;
begin
  c := TCheckListProbe.Create(nil);
  try
    c.Items.Add('a');
    c.Height := 200;
    c.ItemIndex := 0;
    c.ItemEnabled[0] := False;
    c.PressSpace;
    AssertFalse('Space cannot tick a disabled row', c.Checked[0]);
    c.ItemEnabled[0] := True;
    c.PressSpace;
    AssertTrue('and can once it is enabled', c.Checked[0]);
  finally c.Free; end;
end;

procedure TCheckListParityTest.ToggleItselfRefusesADisabledRow;
{ Toggle is public, and both input paths route through it -- but each of those also gates on
  ItemEnabled first, so the gate INSIDE Toggle was covered by nothing: removing it left the
  suite green. This is the guard for it.

  A deliberate divergence from LCL, where Toggle applies NextStateMap unconditionally and
  only the keyboard path (checklst.pas:336) consults ItemEnabled. Here "disabled" is a
  property of the row, not of one input path: a descendant that toggles from a gesture of
  its own would otherwise silently reactivate a row the host turned off. LCL's own CheckAll
  carries an aAllowDisabled guard for the same reason. }
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a');
    c.ItemEnabled[0] := False;
    c.Toggle(0);
    AssertTrue('a disabled row does not move, whoever asks', c.State[0] = cbUnchecked);
    c.AllowGrayed := True;
    c.Toggle(0);
    AssertTrue('nor with the grayed cycle on', c.State[0] = cbUnchecked);
    c.ItemEnabled[0] := True;
    c.Toggle(0);
    AssertTrue('and moves once re-enabled', c.State[0] = cbGrayed);
  finally c.Free; end;
end;

procedure TCheckListParityTest.DisabledRowResolvesTheDisabledStyle;
{ Refusing input without looking different reads to a user as a control that has stopped
  responding, so the row has to resolve the theme's disabled style too. }
var c: TCheckListProbe;
begin
  c := TCheckListProbe.Create(nil);
  try
    c.Items.Add('a'); c.Items.Add('b');
    c.ItemEnabled[0] := False;
    AssertTrue('disabled row', tysDisabled in c.StatesOfRow(0));
    AssertFalse('and not also normal', tysNormal in c.StatesOfRow(0));
    AssertFalse('enabled row is untouched', tysDisabled in c.StatesOfRow(1));
    AssertTrue('and still normal', tysNormal in c.StatesOfRow(1));
  finally c.Free; end;
end;

procedure TCheckListParityTest.DisabledSurvivesACheck;
{ Both live in one packed word; writing either must not clobber the other. }
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a');
    c.ItemEnabled[0] := False;
    c.State[0] := cbGrayed;
    AssertFalse('still disabled after a state write', c.ItemEnabled[0]);
    AssertTrue('and the state took', c.State[0] = cbGrayed);
    c.ItemEnabled[0] := True;
    AssertTrue('state survives an enable', c.State[0] = cbGrayed);
  finally c.Free; end;
end;

procedure TCheckListParityTest.ForeignObjectIsNotACheckState;
{ Items.Objects[] may hold the application's own object. Reading it as "non-zero, so
  checked" made every such row arrive pre-ticked. }
var c: TTyCheckListBox; o: TObject;
begin
  c := TTyCheckListBox.Create(nil);
  o := TStringList.Create;
  try
    c.Items.AddObject('a', o);
    AssertFalse('an app object is not a tick', c.Checked[0]);
    AssertTrue('nor a state',   c.State[0] = cbUnchecked);
    AssertTrue('nor a disable', c.ItemEnabled[0]);
    c.Checked[0] := True;
    AssertTrue('and a write replaces the slot wholesale, low bits and all',
      PtrUInt(c.Items.Objects[0]) < 8);
  finally o.Free; c.Free; end;
end;

procedure TCheckListParityTest.CheckAllHonoursItsTwoGuards;
var c: TTyCheckListBox;
begin
  c := TTyCheckListBox.Create(nil);
  try
    c.Items.Add('a'); c.Items.Add('b'); c.Items.Add('c');
    c.State[1] := cbGrayed;
    c.ItemEnabled[2] := False;
    c.CheckAll(cbChecked, False, False);
    AssertTrue('plain row set',        c.State[0] = cbChecked);
    AssertTrue('grayed row skipped',   c.State[1] = cbGrayed);
    AssertTrue('disabled row skipped', c.State[2] = cbUnchecked);
    c.CheckAll(cbChecked);
    AssertTrue('and with both allowed, everything moves', c.State[1] = cbChecked);
    AssertTrue('everything', c.State[2] = cbChecked);
  finally c.Free; end;
end;

{ ---------------------------------------------------------- the list view --- }

procedure TListViewParityTest.HInsert(Sender: TObject; AIndex: Integer);
begin
  SetLength(FInserted, Length(FInserted) + 1);
  FInserted[High(FInserted)] := AIndex;
end;

procedure TListViewParityTest.HDelete(Sender: TObject; AIndex: Integer);
begin
  SetLength(FDeleted, Length(FDeleted) + 1);
  FDeleted[High(FDeleted)] := AIndex;
  { The point of OnDeletion is that the row -- and its Data payload -- is still there. }
  if (FCaptionsAtDeletion <> nil) and (FLV <> nil)
     and (AIndex >= 0) and (AIndex < FLV.Items.Count) then
    FCaptionsAtDeletion.Add(FLV.Items[AIndex].Caption);
end;

procedure TListViewParityTest.ColumnsReachableWithoutTheHeaderHop;
{ `LV.Columns[0].Width := 120` and `LV.ColumnCount` are how every line of ported column
  code is written; Header.Columns was the only spelling here. }
var lv: TTyListView;
begin
  lv := TTyListView.Create(nil);
  try
    lv.Header.Columns.Add;
    lv.Header.Columns.Add;
    AssertEquals('ColumnCount', 2, lv.ColumnCount);
    AssertTrue('Columns is the header collection', lv.Columns = lv.Header.Columns);
    lv.Columns[0].Width := 120;
    AssertEquals('and writes through', 120, lv.Header.Columns[0].Width);
    AssertEquals('Column[] is the same object', 120, lv.Column[0].Width);
  finally lv.Free; end;
end;

procedure TListViewParityTest.ColumnIndexerIsNilOutOfRange;
var lv: TTyListView;
begin
  lv := TTyListView.Create(nil);
  try
    lv.Header.Columns.Add;
    AssertTrue('in range', lv.Column[0] <> nil);
    AssertTrue('past the end', lv.Column[9] = nil);
    AssertTrue('negative', lv.Column[-1] = nil);
  finally lv.Free; end;
end;

procedure TListViewParityTest.OnInsertFiresWithTheNewIndex;
var lv: TTyListView;
begin
  lv := TTyListView.Create(nil);
  SetLength(FInserted, 0); SetLength(FDeleted, 0);
  FCaptionsAtDeletion := nil; FLV := nil;
  try
    lv.OnInsert := @HInsert;
    lv.Items.Add.Caption := 'one';
    lv.Items.Add.Caption := 'two';
    AssertEquals('two inserts', 2, Length(FInserted));
    AssertEquals('first at 0', 0, FInserted[0]);
    AssertEquals('second at 1', 1, FInserted[1]);
  finally lv.Free; end;
end;

procedure TListViewParityTest.OnDeletionFiresWhileTheRowStillExists;
{ Items carrying an owned object in Data leaked: TTyListItems is a plain TCollection whose
  Notify is protected and already consumed internally, so there was no hook at all. }
var lv: TTyListView;
begin
  lv := TTyListView.Create(nil);
  SetLength(FInserted, 0); SetLength(FDeleted, 0);
  FCaptionsAtDeletion := TStringList.Create;
  FLV := lv;
  try
    lv.Items.Add.Caption := 'one';
    lv.Items.Add.Caption := 'two';
    lv.OnDeletion := @HDelete;
    lv.Items.Delete(0);
    AssertEquals('one deletion', 1, Length(FDeleted));
    AssertEquals('at index 0', 0, FDeleted[0]);
    AssertEquals('and the row was still readable', 1, FCaptionsAtDeletion.Count);
    AssertEquals('one', FCaptionsAtDeletion[0]);
  finally
    lv.OnDeletion := nil; FLV := nil;
    FreeAndNil(FCaptionsAtDeletion);
    lv.Free;
  end;
end;

procedure TListViewParityTest.OnDeletionFiresForEveryRowOnClear;
var lv: TTyListView;
begin
  lv := TTyListView.Create(nil);
  SetLength(FDeleted, 0);
  FCaptionsAtDeletion := nil; FLV := nil;
  try
    lv.Items.Add; lv.Items.Add; lv.Items.Add;
    lv.OnDeletion := @HDelete;
    lv.Items.Clear;
    AssertEquals('every row is reported, which is what a Data owner needs',
      3, Length(FDeleted));
  finally lv.OnDeletion := nil; lv.Free; end;
end;

procedure TListViewParityTest.OwnerDataRaisesNeitherNotification;
{ In virtual mode there is no collection lifetime to report and the app owns the store. }
var lv: TTyListView;
begin
  lv := TTyListView.Create(nil);
  SetLength(FInserted, 0); SetLength(FDeleted, 0);
  FCaptionsAtDeletion := nil; FLV := nil;
  try
    lv.OwnerData := True;
    lv.OnInsert := @HInsert;
    lv.OnDeletion := @HDelete;
    lv.Items.Add;
    lv.Items.Clear;
    AssertEquals('no inserts', 0, Length(FInserted));
    AssertEquals('no deletions', 0, Length(FDeleted));
  finally lv.OnInsert := nil; lv.OnDeletion := nil; lv.Free; end;
end;

initialization
  RegisterTest(TColourParityTest);
  RegisterTest(TListBoxParityTest);
  RegisterTest(TCheckListParityTest);
  RegisterTest(TListViewParityTest);
end.
