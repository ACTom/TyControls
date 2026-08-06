unit test.parity.combo;
{$mode objfpc}{$H+}
{ Parity guards for the three combo families against LCL's TComboBox
  (stdctrls.pp), TComboBoxEx and TCheckComboBox (comboex.pas). Each test names the
  LCL member it pins, so a later refactor that quietly drops one goes red here and
  not in a user's ported form. }
interface
uses
  Classes, SysUtils, Types, Math, Graphics, Controls, Forms, StdCtrls,
  LCLType, LCLIntf, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.ComboBox, tyControls.ComboBoxEx, tyControls.CheckComboBox,
  tyControls.ListBox, tyControls.CheckListBox;

type
  { Exposes the protected RenderTo so a paint-path claim (TextHint) can be pinned by
    comparing two renders instead of trusting the property setter. }
  TComboRender = class(TTyComboBox)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { DropDown must never build a real popup window in a headless run; this records the
    call instead, which is all the OnGetItems / DroppedDown-setter guards need. }
  TComboDropProbe = class(TTyComboBox)
  public
    Opens: Integer;
    procedure DropDown; override;
  end;

  TComboBoxParityTest = class(TTestCase)
  private
    FIndexSeen: Integer;
    FItemChanges: Integer;
    FGetItemsCalls: Integer;
    procedure OnGetItemsHandler(Sender: TObject);
    procedure OnItemChangeHandler(Sender: TObject; AIndex: Integer);
  published
    { --- TTyComboBox --- }
    procedure TestItemHeightDrivesPopupHeight;          // stdctrls.pp:394
    procedure TestItemHeightZeroFollowsTheList;         // ditto (0 = theme)
    procedure TestItemWidthWidensTheDropdown;           // stdctrls.pp:395
    procedure TestTextHintReachesTheEditor;             // stdctrls.pp:444
    procedure TestTextHintPaintsInPickOnlyField;        // ditto, the csDropDownList half
    procedure TestTextHintHiddenOnceTextIsSet;
    procedure TestReadOnlyReachesTheEditor;             // stdctrls.pp:437
    procedure TestDroppedDownIsWritable;                // stdctrls.pp:420
    procedure TestSelectionForwardsToTheEditor;         // stdctrls.pp:438-440, :421
    procedure TestSelectionSafeWithoutEditor;
    procedure TestAddHistoryItemPromotesAndCaps;        // stdctrls.pp:413
    procedure TestAddHistoryItemCaseSensitivity;
    procedure TestAddHistoryItemCarriesObject;          // stdctrls.pp:415
    procedure TestOnGetItemsFiresBeforeTheEmptyGuard;   // stdctrls.pp:401

    { --- TTyComboBoxEx --- }
    procedure TestItemsExIsTheItemSource;               // comboex.pas:181
    procedure TestItemsExCarriesTheFourExtraFields;     // comboex.pas:73-90
    procedure TestAddItemObjectOverloadStillReachable;  // comboex.pas:167 (the hiding bug)
    procedure TestAddItemImageOverloadStillWorks;
    procedure TestExAddInsertDeleteDeleteSelected;      // comboex.pas:164-176
    procedure TestExAssignItemsEx;
    procedure TestDirectItemsEditStaysConsistent;
    procedure TestItemsExSortByText;                    // TListControlItems.SortType
    procedure TestItemsExStreamsToLfm;                  // comboex.pas:213 (published)
    procedure TestItemsExRoundTripsThroughAStream;
    procedure TestItemIndexSurvivesStreamingOrder;      // the ItemsEx-before-ItemIndex trap

    { --- TTyCheckComboBox --- }
    procedure TestStateIsTriState;                      // comboex.pas:328
    procedure TestCheckedStillAgreesWithState;
    procedure TestAllowGrayedDrivesToggleCycle;         // comboex.pas:323, comboex.inc:842
    procedure TestItemEnabledBlocksUserToggle;          // comboex.pas:326
    procedure TestCheckAllHonoursExclusions;            // comboex.inc:533
    procedure TestOnItemChangeCarriesTheIndex;          // comboex.pas:329
    procedure TestCheckAddItemAssignItemsDeleteItem;    // comboex.pas:317-320
    procedure TestObjectsSlotSurvivesChecking;          // comboex.pas:327 (already shipped)
  end;

const
  { One popup-list geometry for every row test: three 24px rows and room to spare, so a
    scrolled-out row never quietly reduces the number of callbacks under test. }
  ListW = 140;
  ListH = 100;

type
  { Counts repaints, so "the setter invalidates" is a measured claim rather than a reading
    of the source. TControl.Invalidate is virtual, which is what makes this possible. }
  TComboInvalidateProbe = class(TTyComboBox)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
  end;

  { Owner-draw: the Style values, OnDrawItem, and the two things that can only be seen in
    the pixels -- that the host's pass runs on the COMPOSITED canvas, and that every one of
    its calls inks with its own state rather than the previous call's. }
  TComboOwnerDrawTest = class(TTestCase)
  private
    FForm: TForm;
    FCalls: Integer;
    FSeen: Integer;
    FIndexSeen: array of Integer;
    FStateSeen: array of TOwnerDrawState;
    FRectSeen: array of TRect;
    FStaleInkRows: Integer;    // calls whose DC ink was NOT the one the handler asked for
    procedure RecordCall(AIndex: Integer; const ARect: TRect; AState: TOwnerDrawState);
    procedure HandleDrawSilent(Sender: TObject; ACanvas: TCanvas; Index: Integer;
      ARect: TRect; AState: TOwnerDrawState);
    procedure HandleDrawSameStateEveryCall(Sender: TObject; ACanvas: TCanvas;
      Index: Integer; ARect: TRect; AState: TOwnerDrawState);
    procedure HandleDrawOverflowing(Sender: TObject; ACanvas: TCanvas; Index: Integer;
      ARect: TRect; AState: TOwnerDrawState);
    function MakeCombo(AStyle: TTyComboBoxStyle; AHandler: TTyDrawItemEvent): TTyComboBox;
    function MakeList(ACombo: TTyComboBox): TTyComboPopupList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestStyleValuesAppendedAndDefaultOrdinalHeld;   // stdctrls.pp:262
    procedure TestEditableOwnerDrawStyleShowsTheEditor;       // stdctrls.pp:268
    procedure TestOwnerDrawFieldSuppressesTheDefaultContent;  // stdctrls.pp:399
    procedure TestOwnerDrawStyleWithoutAHandlerKeepsTheThemedField;
    procedure TestHandlerIsInertAtTheDefaultStyle;
    procedure TestOwnerDrawFieldSurvivesTheComposite;
    procedure TestOwnerDrawFieldClipsToTheTextZone;
    procedure TestOwnerDrawRowsSuppressTheDefaultRowContent;
    procedure TestOwnerDrawRowIndexIsAnItemsIndex;
    procedure TestOwnerDrawRowsClipToTheirOwnRow;
    procedure TestOwnerDrawRowStateSurvivesEveryRow;
    procedure TestRowCollectionDoesNotAccumulateAcrossPaints;
    procedure TestAssigningTheHandlerRepaints;
    procedure TestOwnerDrawReachesComboBoxEx;
    procedure TestOwnerDrawReachesCheckComboBox;
    procedure TestPickOnlyLockDropsTheEditBoxNotTheOwnerDraw;
  end;

implementation

procedure TComboRender.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TComboDropProbe.DropDown;
begin
  Inc(Opens);
end;

procedure TComboBoxParityTest.OnGetItemsHandler(Sender: TObject);
begin
  Inc(FGetItemsCalls);
  { Exactly the lazy-population use LCL documents: fill the list only when it is about
    to be shown. }
  TTyComboBox(Sender).Items.Add('lazy');
end;

procedure TComboBoxParityTest.OnItemChangeHandler(Sender: TObject; AIndex: Integer);
begin
  Inc(FItemChanges);
  FIndexSeen := AIndex;
end;

{ ---------------- TTyComboBox ---------------- }

procedure TComboBoxParityTest.TestItemHeightDrivesPopupHeight;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Items.AddStrings(['a', 'b', 'c']);
    c.DropDownCount := 3;
    c.ItemHeight := 40;
    { 3 rows x 40 + the 2px popup frame. Pinning the arithmetic, not just the setter:
      an ItemHeight the popup sizer ignores is the defect this pass exists to remove. }
    AssertEquals('ItemHeight sizes the popup', 3 * 40 + 2, c.ComputePopupHeightForTest(96));
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestItemHeightZeroFollowsTheList;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Items.AddStrings(['a', 'b']);
    AssertEquals('unset by default', 0, c.ItemHeight);
    { 0 keeps the themed --item-height (24 headless), so a skin still owns row height. }
    AssertEquals('theme row height still used', 2 * 24 + 2, c.ComputePopupHeightForTest(96));
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestItemWidthWidensTheDropdown;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Width := 100;
    AssertEquals('unset by default', 0, c.ItemWidth);
    AssertEquals('0 = exactly the field width', 100, c.ComputePopupWidthForTest(96));
    c.ItemWidth := 260;
    AssertEquals('wider than the field', 260, c.ComputePopupWidthForTest(96));
    c.ItemWidth := 40;
    AssertEquals('never narrower than the field', 100, c.ComputePopupWidthForTest(96));
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestTextHintReachesTheEditor;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csDropDown;
    c.TextHint := 'Select a country';
    AssertEquals('forwarded to the embedded editor', 'Select a country',
      c.EditorTextHintForTest);
  finally c.Free; end;
end;

function ComboRenderDiffers(A, B: TTyComboBox; AW, AH: Integer): Boolean;
var
  BmpA, BmpB: TBitmap;
  x, y: Integer;
begin
  Result := False;
  BmpA := TBitmap.Create;
  BmpB := TBitmap.Create;
  try
    BmpA.PixelFormat := pf32bit; BmpA.SetSize(AW, AH);
    BmpB.PixelFormat := pf32bit; BmpB.SetSize(AW, AH);
    TComboRender(A).Render(BmpA.Canvas, Rect(0, 0, AW, AH), 96);
    TComboRender(B).Render(BmpB.Canvas, Rect(0, 0, AW, AH), 96);
    for y := 0 to AH - 1 do
      for x := 0 to AW - 1 do
        if ColorToRGB(BmpA.Canvas.Pixels[x, y]) <> ColorToRGB(BmpB.Canvas.Pixels[x, y]) then
          Exit(True);
  finally
    BmpA.Free; BmpB.Free;
  end;
end;

procedure TComboBoxParityTest.TestTextHintPaintsInPickOnlyField;
var plain, hinted: TComboRender;
begin
  { The pick-only field has no editor to borrow a hint from, so the combo must paint it
    itself. Two renders that differ is the only honest proof the paint path READS the
    property -- a setter test would pass with the paint left unwired. }
  plain  := TComboRender.Create(nil);
  hinted := TComboRender.Create(nil);
  try
    hinted.TextHint := 'Pick one';
    AssertTrue('an empty pick-only field paints its TextHint',
      ComboRenderDiffers(plain, hinted, 140, 26));
  finally
    plain.Free; hinted.Free;
  end;
end;

procedure TComboBoxParityTest.TestTextHintHiddenOnceTextIsSet;
var withText, hintedWithText: TComboRender;
begin
  withText := TComboRender.Create(nil);
  hintedWithText := TComboRender.Create(nil);
  try
    withText.Items.Add('Belgium');       withText.ItemIndex := 0;
    hintedWithText.Items.Add('Belgium'); hintedWithText.ItemIndex := 0;
    hintedWithText.TextHint := 'Pick one';
    AssertFalse('a hint never shows behind real text',
      ComboRenderDiffers(withText, hintedWithText, 140, 26));
  finally
    withText.Free; hintedWithText.Free;
  end;
end;

procedure TComboBoxParityTest.TestReadOnlyReachesTheEditor;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    AssertFalse('LCL default', c.ReadOnly);
    c.Style := csDropDown;
    c.ReadOnly := True;
    AssertTrue('forwarded to the embedded editor', c.EditorReadOnlyForTest);
    c.ReadOnly := False;
    AssertFalse('and back', c.EditorReadOnlyForTest);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestDroppedDownIsWritable;
var p: TComboDropProbe;
begin
  p := TComboDropProbe.Create(nil);
  try
    p.Items.Add('a');
    AssertFalse('starts closed', p.DroppedDown);
    p.DroppedDown := True;
    AssertEquals('the writable property routes through DropDown', 1, p.Opens);
    { A second write while (probe-)closed must still reach DropDown -- the setter may not
      short-circuit on its own idea of the state. }
    p.DroppedDown := False;
    AssertFalse('closing is safe with no popup', p.DroppedDown);
  finally p.Free; end;
end;

procedure TComboBoxParityTest.TestSelectionForwardsToTheEditor;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csDropDown;
    c.Text := 'Amsterdam';
    c.SelStart := 0;
    c.SelLength := 9;
    AssertEquals('SelText reads the highlighted run', 'Amsterdam', c.SelText);
    c.SelStart := 4;
    c.SelLength := 5;
    AssertEquals('SelStart moved', 4, c.SelStart);
    AssertEquals('SelLength moved', 5, c.SelLength);
    AssertEquals('SelText follows', 'erdam', c.SelText);
    c.SelText := 'X';
    AssertEquals('writing SelText replaces the run', 'AmstX', c.Text);
    c.SelectAll;
    AssertEquals('SelectAll spans the field', 5, c.SelLength);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestSelectionSafeWithoutEditor;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    { Pick-only mode has no editable run. Reading must be quiet zeros, not an exception,
      because generic code (a formatting toolbar) touches Sel* without knowing the mode. }
    AssertEquals('SelStart', 0, c.SelStart);
    AssertEquals('SelLength', 0, c.SelLength);
    AssertEquals('SelText', '', c.SelText);
    c.SelectAll;
    c.SelStart := 3;
    AssertEquals('still zero after a write', 0, c.SelLength);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestAddHistoryItemPromotesAndCaps;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.AddHistoryItem('one',   3, False, False);
    c.AddHistoryItem('two',   3, False, False);
    c.AddHistoryItem('three', 3, False, False);
    AssertEquals('newest first', 'three', c.Items[0]);
    AssertEquals('oldest last',  'one',   c.Items[2]);
    { Re-use PROMOTES rather than duplicating. Checked with a cap far above the row count
      on purpose: at cap = 3 the trim silently eats the duplicate off the tail, so the
      count alone cannot tell a real de-dup from an overflow. }
    c.AddHistoryItem('one', 99, False, False);
    AssertEquals('promoted, not duplicated', 3, c.Items.Count);
    AssertEquals('promoted to the top', 'one', c.Items[0]);
    AssertEquals('and there is no second copy anywhere', 2, c.Items.IndexOf('two'));
    AssertEquals('exactly one row per distinct entry', 'three', c.Items[1]);
    c.AddHistoryItem('four', 3, True, False);   // overflows the cap of 3
    AssertEquals('capped', 3, c.Items.Count);
    AssertEquals('the least recent fell off', -1, c.Items.IndexOf('two'));
    AssertEquals('SetAsText applied', 'four', c.Text);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestAddHistoryItemCaseSensitivity;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.AddHistoryItem('Alpha', 10, False, False);
    c.AddHistoryItem('alpha', 10, False, False);   // case-INsensitive: same entry
    AssertEquals('one entry when matching loosely', 1, c.Items.Count);
    c.Items.Clear;
    c.AddHistoryItem('Alpha', 10, False, True);
    c.AddHistoryItem('alpha', 10, False, True);    // case-sensitive: two entries
    AssertEquals('two entries when matching exactly', 2, c.Items.Count);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestAddHistoryItemCarriesObject;
var c: TTyComboBox; payload: TObject;
begin
  c := TTyComboBox.Create(nil);
  payload := TObject.Create;
  try
    c.AddHistoryItem('one', payload, 5, False, False);
    AssertSame('the object overload keeps the payload', payload, c.Items.Objects[0]);
  finally c.Free; payload.Free; end;
end;

procedure TComboBoxParityTest.TestOnGetItemsFiresBeforeTheEmptyGuard;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    FGetItemsCalls := 0;
    c.OnGetItems := @OnGetItemsHandler;
    AssertEquals('starts empty', 0, c.Items.Count);
    c.DropDown;
    { The whole point of the claim: DropDown bails out on an empty list, so a hook that
      fires after that guard can never populate anything -- the first click on a lazy
      combo would do nothing at all. }
    AssertEquals('OnGetItems fired', 1, FGetItemsCalls);
    AssertEquals('and its rows landed', 1, c.Items.Count);
  finally c.Free; end;
end;

{ ---------------- TTyComboBoxEx ---------------- }

procedure TComboBoxParityTest.TestItemsExIsTheItemSource;
var c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(nil);
  try
    c.ItemsEx.AddItem('Save', 3);
    c.ItemsEx.AddItem('Open', 4);
    AssertEquals('the collection is the list', 2, c.Items.Count);
    AssertEquals('caption projected into Items', 'Save', c.Items[0]);
    AssertEquals('image index readable through the old accessor', 3, c.ImageIndexOf(0));
    c.ItemsEx[0].Caption := 'Store';
    AssertEquals('a caption edit reaches the painted list', 'Store', c.Items[0]);
    c.ItemsEx.Delete(0);
    AssertEquals('a collection delete reaches the painted list', 1, c.Items.Count);
    AssertEquals('and the survivor keeps its image', 4, c.ImageIndexOf(0));
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestItemsExCarriesTheFourExtraFields;
var c: TTyComboBoxEx; it: TTyComboExItem; payload: TObject;
begin
  c := TTyComboBoxEx.Create(nil);
  payload := TObject.Create;
  try
    it := c.ItemsEx.Add;
    AssertEquals('LCL default ImageIndex',         -1, it.ImageIndex);
    AssertEquals('LCL default Indent',             -1, it.Indent);
    AssertEquals('LCL default OverlayImageIndex',  -1, it.OverlayImageIndex);
    AssertEquals('LCL default SelectedImageIndex', -1, it.SelectedImageIndex);
    it.Caption := 'Row';
    it.Indent := 2;
    it.OverlayImageIndex := 7;
    it.SelectedImageIndex := 9;
    it.Data := payload;
    AssertEquals('Indent kept', 2, c.ItemsEx[0].Indent);
    AssertEquals('OverlayImageIndex kept', 7, c.ItemsEx[0].OverlayImageIndex);
    AssertEquals('SelectedImageIndex kept', 9, c.ItemsEx[0].SelectedImageIndex);
    AssertSame('per-item Data kept', payload, c.ItemsEx[0].Data);
  finally c.Free; payload.Free; end;
end;

procedure TComboBoxParityTest.TestAddItemObjectOverloadStillReachable;
var c: TTyComboBoxEx; payload: TObject;
begin
  c := TTyComboBoxEx.Create(nil);
  payload := TObject.Create;
  try
    { The inherited AddItem(text, TObject) used to be HIDDEN by the Ex combo's two-arg
      integer form, so ported code stopped compiling; and once un-hidden it must NOT
      land in the image slot. }
    c.AddItem('with data', payload);
    AssertEquals('row added', 1, c.Items.Count);
    AssertEquals('the object is not read as an image index', -1, c.ImageIndexOf(0));
    AssertSame('it is the row payload', payload, c.ItemsEx[0].Data);
  finally c.Free; payload.Free; end;
end;

procedure TComboBoxParityTest.TestAddItemImageOverloadStillWorks;
var c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(nil);
  try
    c.AddItem('a', 5);
    c.AddItem('b', -1);
    AssertEquals('a keeps image 5', 5, c.ImageIndexOf(0));
    AssertEquals('b has no image', -1, c.ImageIndexOf(1));
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestExAddInsertDeleteDeleteSelected;
var c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(nil);
  try
    c.Add('one', -1, 1);
    c.Add('three', -1, 3);
    c.Insert(1, 'two', -1, 2);                 // image-aware insert, no hand-rolled encoding
    AssertEquals('three rows', 3, c.Items.Count);
    AssertEquals('inserted in place', 'two', c.Items[1]);
    AssertEquals('with its image', 2, c.ImageIndexOf(1));
    AssertEquals('and the row after it kept its own', 3, c.ImageIndexOf(2));
    c.ItemIndex := 1;
    c.DeleteSelected;
    AssertEquals('selected row gone', 2, c.Items.Count);
    AssertEquals('the right one went', 'three', c.Items[1]);
    c.Delete(0);
    AssertEquals('one row left', 1, c.Items.Count);
    AssertEquals('image still paired', 3, c.ImageIndexOf(0));
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestExAssignItemsEx;
var c, other: TTyComboBoxEx; src: TStringList;
begin
  c := TTyComboBoxEx.Create(nil);
  other := TTyComboBoxEx.Create(nil);
  src := TStringList.Create;
  try
    src.AddStrings(['x', 'y']);
    c.AssignItemsEx(src);
    AssertEquals('bulk load from TStrings', 2, c.Items.Count);
    AssertEquals('no image on a bare string', -1, c.ImageIndexOf(0));
    c.ItemsEx[1].ImageIndex := 6;
    other.AssignItemsEx(c.ItemsEx);
    AssertEquals('bulk copy of a collection', 2, other.Items.Count);
    AssertEquals('images copied too', 6, other.ImageIndexOf(1));
    AssertEquals('captions copied too', 'y', other.Items[1]);
  finally c.Free; other.Free; src.Free; end;
end;

procedure TComboBoxParityTest.TestDirectItemsEditStaysConsistent;
var c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(nil);
  try
    { Items is still a public TStringList, so people will keep writing to it. Every row
      must still end up with an extended entry rather than a nil slot the painter reads
      as a garbage image index. }
    c.Items.Add('typed straight in');
    AssertEquals('collection followed', 1, c.ItemsEx.Count);
    AssertEquals('caption matches', 'typed straight in', c.ItemsEx[0].Caption);
    AssertEquals('no image', -1, c.ImageIndexOf(0));
    c.AddItem('with image', 2);
    c.Items.Delete(0);
    AssertEquals('collection followed the delete', 1, c.ItemsEx.Count);
    AssertEquals('survivor keeps its image', 2, c.ImageIndexOf(0));
    c.Items.Clear;
    AssertEquals('collection emptied too', 0, c.ItemsEx.Count);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestItemsExSortByText;
var c: TTyComboBoxEx;
begin
  c := TTyComboBoxEx.Create(nil);
  try
    c.ItemsEx.AddItem('Zebra', 1);
    c.ItemsEx.AddItem('apple', 2);
    c.ItemsEx.AddItem('Mango', 3);
    c.ItemsEx.SortType := stText;
    AssertEquals('sorted case-insensitively by default', 'apple', c.Items[0]);
    AssertEquals('and the image travelled with it', 2, c.ImageIndexOf(0));
    AssertEquals('Mango', c.Items[1]);
    AssertEquals('Zebra', c.Items[2]);
  finally c.Free; end;
end;

type
  { A streamable root that owns the design tree, exactly as a real form does. }
  TComboExHost = class(TForm)
  published
    CB: TTyComboBoxEx;
  end;

{ Write AHost to the binary component stream and return its .lfm TEXT form -- the same
  conversion the IDE performs when it saves a form. }
function HostToLfmText(AHost: TComponent): string;
var bin, txt: TMemoryStream; ss: TStringStream;
begin
  bin := TMemoryStream.Create;
  txt := TMemoryStream.Create;
  try
    bin.WriteComponent(AHost);
    bin.Position := 0;
    ObjectBinaryToText(bin, txt);
    txt.Position := 0;
    ss := TStringStream.Create('');
    try
      ss.CopyFrom(txt, txt.Size);
      Result := ss.DataString;
    finally ss.Free; end;
  finally
    txt.Free; bin.Free;
  end;
end;

procedure TComboBoxParityTest.TestItemsExStreamsToLfm;
var host: TComboExHost; lfm: string; it: TTyComboExItem;
begin
  { A runtime-only collection would not close the gap the claim is about: the point of a
    published TCollection is that the Object Inspector's collection editor edits it and
    the result lands in the .lfm. This pins the second half -- the .lfm text -- which is
    also the only half a headless run can see. }
  host := TComboExHost.CreateNew(nil);
  try
    host.Name := 'HostForm1';
    host.CB := TTyComboBoxEx.Create(host);
    host.CB.Name := 'CB';
    host.CB.Parent := host;
    it := host.CB.ItemsEx.AddItem('Save', 3, 4, 5, 6);
    AssertEquals('the entry took its values', 3, it.ImageIndex);
    lfm := HostToLfmText(host);
    AssertTrue('ItemsEx is written as a collection block',  Pos('ItemsEx = <', lfm) > 0);
    AssertTrue('the caption is in the .lfm',                Pos('Caption = ' + QuotedStr('Save'), lfm) > 0);
    AssertTrue('ImageIndex is in the .lfm',                 Pos('ImageIndex = 3', lfm) > 0);
    AssertTrue('OverlayImageIndex is in the .lfm',          Pos('OverlayImageIndex = 4', lfm) > 0);
    AssertTrue('SelectedImageIndex is in the .lfm',         Pos('SelectedImageIndex = 5', lfm) > 0);
    AssertTrue('Indent is in the .lfm',                     Pos('Indent = 6', lfm) > 0);
    { The projected string list must NOT also be written -- two sources of truth in one
      .lfm is how a form comes back with its rows doubled. }
    AssertTrue('Items is not streamed alongside it', Pos('Items.Strings', lfm) = 0);
  finally host.Free; end;
end;

procedure TComboBoxParityTest.TestItemsExRoundTripsThroughAStream;
var src, dst: TComboExHost; ms: TMemoryStream; cb: TTyComboBoxEx;
begin
  src := TComboExHost.CreateNew(nil);
  dst := TComboExHost.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    src.Name := 'HostForm1';
    src.CB := TTyComboBoxEx.Create(src);
    src.CB.Name := 'CB';
    src.CB.Parent := src;
    src.CB.ItemsEx.AddItem('Save', 3, 4, 5, 6);
    src.CB.ItemsEx.AddItem('Open', 1);
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);

    cb := dst.FindComponent('CB') as TTyComboBoxEx;
    AssertNotNull('combo survived', cb);
    AssertEquals('collection survived', 2, cb.ItemsEx.Count);
    { And the PROJECTION was rebuilt on load, so the control is paintable straight away
      rather than only after the first edit. }
    AssertEquals('Items rebuilt from the collection', 2, cb.Items.Count);
    AssertEquals('caption projected', 'Save', cb.Items[0]);
    AssertEquals('image paired', 3, cb.ImageIndexOf(0));
    AssertEquals('overlay survived', 4, cb.ItemsEx[0].OverlayImageIndex);
    AssertEquals('selected image survived', 5, cb.ItemsEx[0].SelectedImageIndex);
    AssertEquals('indent survived', 6, cb.ItemsEx[0].Indent);
    AssertEquals('second row', 1, cb.ImageIndexOf(1));
  finally
    ms.Free; dst.Free; src.Free;
  end;
end;

{ Read AText (an .lfm text form) back into AHost. }
procedure LfmTextIntoHost(const AText: string; AHost: TComponent);
var txt, bin: TMemoryStream; ss: TStringStream;
begin
  txt := TMemoryStream.Create;
  bin := TMemoryStream.Create;
  ss := TStringStream.Create(AText);
  try
    txt.CopyFrom(ss, 0);
    txt.Position := 0;
    ObjectTextToBinary(txt, bin);
    bin.Position := 0;
    bin.ReadComponent(AHost);
  finally
    ss.Free; bin.Free; txt.Free;
  end;
end;

procedure TComboBoxParityTest.TestItemIndexSurvivesStreamingOrder;
var
  src, dst: TComboExHost;
  cb: TTyComboBoxEx;
  lines: TStringList;
  lfm: string;
  i, idxLine, exLine: Integer;
begin
  { ItemIndex is published on the ANCESTOR and ItemsEx on this class. LCL guards the same
    hazard by hand (comboex.pas:213 'do not change order; ItemsEx must be before
    ItemIndex'), because whichever arrives first wins: with ItemIndex first the list is
    still empty and the index clamps to -1, losing a design-time selection on every load.
    So this feeds the control the ADVERSE order explicitly -- moving the ItemIndex line
    above the ItemsEx block in the .lfm text -- rather than trusting the order FPC's
    property walk happens to produce today. }
  src := TComboExHost.CreateNew(nil);
  dst := TComboExHost.CreateNew(nil);
  lines := TStringList.Create;
  try
    src.Name := 'HostForm1';
    src.CB := TTyComboBoxEx.Create(src);
    src.CB.Name := 'CB';
    src.CB.Parent := src;
    src.CB.ItemsEx.AddItem('one', 0);
    src.CB.ItemsEx.AddItem('two', 1);
    src.CB.ItemsEx.AddItem('three', 2);
    src.CB.ItemIndex := 2;
    lines.Text := HostToLfmText(src);

    idxLine := -1;
    exLine := -1;
    for i := 0 to lines.Count - 1 do
    begin
      if (idxLine < 0) and (Pos('ItemIndex = ', lines[i]) > 0) then idxLine := i;
      if (exLine < 0) and (Pos('ItemsEx = <', lines[i]) > 0) then exLine := i;
    end;
    AssertTrue('ItemIndex is in the .lfm', idxLine >= 0);
    AssertTrue('ItemsEx is in the .lfm', exLine >= 0);
    if idxLine > exLine then
    begin
      lfm := lines[idxLine];
      lines.Delete(idxLine);
      lines.Insert(exLine, lfm);   // force ItemIndex ahead of the rows
    end;

    LfmTextIntoHost(lines.Text, dst);
    cb := dst.FindComponent('CB') as TTyComboBoxEx;
    AssertNotNull('combo survived', cb);
    AssertEquals('rows loaded', 3, cb.Items.Count);
    AssertEquals('selection survived ItemIndex arriving before the rows', 2, cb.ItemIndex);
    AssertEquals('and points at the right row', 'three', cb.Text);
  finally
    lines.Free; dst.Free; src.Free;
  end;
end;

{ ---------------- TTyCheckComboBox ---------------- }

function MakeChecks: TTyCheckComboBox;
begin
  Result := TTyCheckComboBox.Create(nil);
  Result.Items.Add('Apple');
  Result.Items.Add('Banana');
  Result.Items.Add('Cherry');
end;

procedure TComboBoxParityTest.TestStateIsTriState;
var c: TTyCheckComboBox;
begin
  c := MakeChecks;
  try
    AssertTrue('unchecked by default', c.State[0] = cbUnchecked);
    c.State[0] := cbGrayed;
    AssertTrue('the third state exists', c.State[0] = cbGrayed);
    AssertFalse('grayed is not checked', c.Checked[0]);
    AssertEquals('and does not count as checked', 0, c.CheckedCount);
    c.State[0] := cbChecked;
    AssertTrue('checked', c.Checked[0]);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestCheckedStillAgreesWithState;
var c: TTyCheckComboBox;
begin
  c := MakeChecks;
  try
    c.Checked[1] := True;
    AssertTrue('Checked writes State', c.State[1] = cbChecked);
    c.Checked[1] := False;
    AssertTrue('and clears it', c.State[1] = cbUnchecked);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestAllowGrayedDrivesToggleCycle;
var c: TTyCheckComboBox;
begin
  c := MakeChecks;
  try
    AssertFalse('LCL default', c.AllowGrayed);
    c.Toggle(0);
    AssertTrue('two-state toggle checks', c.State[0] = cbChecked);
    c.Toggle(0);
    AssertTrue('and unchecks', c.State[0] = cbUnchecked);
    c.AllowGrayed := True;
    { LCL's cycle (comboex.inc:842): unchecked -> grayed -> checked -> unchecked. }
    c.Toggle(0);
    AssertTrue('grayed comes first', c.State[0] = cbGrayed);
    c.Toggle(0);
    AssertTrue('then checked', c.State[0] = cbChecked);
    c.Toggle(0);
    AssertTrue('then back to unchecked', c.State[0] = cbUnchecked);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestItemEnabledBlocksUserToggle;
var c: TTyCheckComboBox; lst: TTyCheckListBox;
begin
  c := MakeChecks;
  try
    AssertTrue('enabled by default', c.ItemEnabled[1]);
    c.ItemEnabled[1] := False;
    AssertFalse('and can be turned off', c.ItemEnabled[1]);
    { A disabled row stays settable from code but must ignore what the user does in the
      popup -- otherwise 'unavailable on your licence' can only be done by deleting it. }
    c.Checked[1] := True;
    AssertTrue('code can still set it', c.Checked[1]);
    c.Checked[1] := False;

    lst := TTyCheckListBox.Create(nil);
    try
      lst.Items.Assign(c.Items);
      lst.Checked[0] := True;    // the user ticked an ENABLED row
      lst.Checked[1] := True;    // ...and a DISABLED one
      c.PullChecksForTest(lst);
      AssertTrue('the enabled row took', c.Checked[0]);
      AssertFalse('the disabled row refused', c.Checked[1]);
    finally lst.Free; end;
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestCheckAllHonoursExclusions;
var c: TTyCheckComboBox;
begin
  c := MakeChecks;
  try
    c.State[0] := cbGrayed;
    c.ItemEnabled[1] := False;
    c.CheckAll(cbChecked, False, False);   // skip grayed rows AND disabled rows
    AssertTrue('grayed row left alone', c.State[0] = cbGrayed);
    AssertTrue('disabled row left alone', c.State[1] = cbUnchecked);
    AssertTrue('the plain row was checked', c.State[2] = cbChecked);
    c.CheckAll(cbChecked);                 // defaults sweep everything
    AssertTrue('grayed row swept', c.State[0] = cbChecked);
    AssertTrue('disabled row swept', c.State[1] = cbChecked);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestOnItemChangeCarriesTheIndex;
var c: TTyCheckComboBox;
begin
  c := MakeChecks;
  try
    FItemChanges := 0;
    FIndexSeen := -99;
    c.OnItemChange := @OnItemChangeHandler;
    c.Checked[2] := True;
    AssertEquals('a programmatic write notifies', 1, FItemChanges);
    AssertEquals('and says which row', 2, FIndexSeen);
    c.Checked[2] := True;         // no change
    AssertEquals('no event without a change', 1, FItemChanges);
    c.State[0] := cbGrayed;
    AssertEquals('State writes notify too', 2, FItemChanges);
    AssertEquals('with their own index', 0, FIndexSeen);
  finally c.Free; end;
end;

procedure TComboBoxParityTest.TestCheckAddItemAssignItemsDeleteItem;
var c: TTyCheckComboBox; src: TStringList;
begin
  c := TTyCheckComboBox.Create(nil);
  src := TStringList.Create;
  try
    c.AddItem('on',       cbChecked);
    c.AddItem('off',      cbUnchecked);
    c.AddItem('locked',   cbGrayed, False);
    AssertEquals('three rows in three calls', 3, c.Items.Count);
    AssertTrue('state came with the row', c.State[0] = cbChecked);
    AssertTrue('and the grayed one', c.State[2] = cbGrayed);
    AssertFalse('and the enabled flag', c.ItemEnabled[2]);
    c.DeleteItem(1);
    AssertEquals('row removed', 2, c.Items.Count);
    AssertTrue('states did not shift', c.State[1] = cbGrayed);
    src.AddStrings(['fresh', 'list']);
    c.AssignItems(src);
    AssertEquals('bulk load', 2, c.Items.Count);
    AssertEquals('nothing carried over', 0, c.CheckedCount);
    AssertTrue('and the rows start enabled', c.ItemEnabled[0]);
  finally c.Free; src.Free; end;
end;

procedure TComboBoxParityTest.TestObjectsSlotSurvivesChecking;
var c: TTyCheckComboBox; payload: TObject;
begin
  c := MakeChecks;
  payload := TObject.Create;
  try
    c.Objects[1] := payload;
    c.Checked[1] := True;
    AssertSame('checking did not clobber the payload', payload, c.Objects[1]);
    AssertTrue('and the payload did not read as checked', c.Checked[1]);
    c.Checked[1] := False;
    AssertFalse('a non-nil payload is not a check', c.Checked[1]);
    AssertSame('payload still there', payload, c.Objects[1]);
  finally c.Free; payload.Free; end;
end;

{ ===================== owner-draw ===================================================== }

function IsGreenInk(const P: TBGRAPixel): Boolean;
begin
  Result := (P.green > 150) and (P.green > P.red + 40) and (P.green > P.blue + 40);
end;

{ The two popup-list families do not share an ancestor (the check combo's descends from
  TTyCheckListBox), so the render seam is reached by class, exactly as the protocol is. }
procedure RenderAnyPopupList(AList: TTyListBox; ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  if AList is TTyCheckComboPopupList then
    TTyCheckComboPopupList(AList).RenderWithOwnerDraw(ACanvas, ARect, APPI)
  else
    TTyComboPopupList(AList).RenderWithOwnerDraw(ACanvas, ARect, APPI);
end;

{ Renders two popup lists and reports whether ANY pixel differs. }
function ListRenderDiffers(A, B: TTyListBox; AW, AH: Integer): Boolean;
var
  BmpA, BmpB: TBitmap;
  x, y: Integer;
begin
  Result := False;
  BmpA := TBitmap.Create;
  BmpB := TBitmap.Create;
  try
    BmpA.PixelFormat := pf32bit; BmpA.SetSize(AW, AH);
    BmpB.PixelFormat := pf32bit; BmpB.SetSize(AW, AH);
    RenderAnyPopupList(A, BmpA.Canvas, Rect(0, 0, AW, AH), 96);
    RenderAnyPopupList(B, BmpB.Canvas, Rect(0, 0, AW, AH), 96);
    for y := 0 to AH - 1 do
      for x := 0 to AW - 1 do
        if ColorToRGB(BmpA.Canvas.Pixels[x, y]) <> ColorToRGB(BmpB.Canvas.Pixels[x, y]) then
          Exit(True);
  finally
    BmpA.Free; BmpB.Free;
  end;
end;

procedure TComboInvalidateProbe.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

procedure TComboOwnerDrawTest.SetUp;
begin
  FCalls := 0;
  FSeen := 0;
  FStaleInkRows := 0;
  SetLength(FIndexSeen, 0);
  SetLength(FStateSeen, 0);
  SetLength(FRectSeen, 0);
  FForm := TForm.CreateNew(nil);
end;

procedure TComboOwnerDrawTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TComboOwnerDrawTest.RecordCall(AIndex: Integer; const ARect: TRect;
  AState: TOwnerDrawState);
begin
  Inc(FCalls);
  if FSeen = Length(FIndexSeen) then
  begin
    SetLength(FIndexSeen, FSeen + 8);
    SetLength(FStateSeen, FSeen + 8);
    SetLength(FRectSeen,  FSeen + 8);
  end;
  FIndexSeen[FSeen] := AIndex;
  FStateSeen[FSeen] := AState;
  FRectSeen[FSeen]  := ARect;
  Inc(FSeen);
end;

procedure TComboOwnerDrawTest.HandleDrawSilent(Sender: TObject; ACanvas: TCanvas;
  Index: Integer; ARect: TRect; AState: TOwnerDrawState);
begin
  { Records and paints NOTHING. What it proves is the suppression half: with this handler
    assigned, an owner-draw style must render exactly as an empty control does. }
  RecordCall(Index, ARect, AState);
end;

{ The shape that catches a canvas whose cached state no longer describes its DC: the SAME
  pen colour and the SAME ink on EVERY call. An LCL TCanvas re-selects one of its objects
  only when a property actually CHANGES, so from the second row on nothing is re-selected
  and the stroke lands with whatever object the DC is holding.

  Brush + FillRect is deliberately NOT used: LCL hands FillRect the brush handle explicitly,
  so it is the one primitive this defect cannot bite, and a guard written around it passes
  against the broken code -- that exact guard was fake-green for two months in TTyTreeView.
  The strokes run ALONG the row's top and bottom edges, never across it, so what gets probed
  is the four corner pixels; a probe in the middle of a row survives any drift that leaves
  SOME of the row green. }
procedure TComboOwnerDrawTest.HandleDrawSameStateEveryCall(Sender: TObject;
  ACanvas: TCanvas; Index: Integer; ARect: TRect; AState: TOwnerDrawState);
const
  Probe = TColor($00C800);   // GREEN, identical on every call
begin
  RecordCall(Index, ARect, AState);
  ACanvas.Pen.Color   := Probe;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color  := Probe;
  { LineTo stops one short of its end point, so these two strokes cover exactly the four
    corners: (Left,Top), (Right-1,Top), (Left,Bottom-1) and (Right-1,Bottom-1). }
  ACanvas.MoveTo(ARect.Left, ARect.Top);
  ACanvas.LineTo(ARect.Right, ARect.Top);
  ACanvas.MoveTo(ARect.Left, ARect.Bottom - 1);
  ACanvas.LineTo(ARect.Right, ARect.Bottom - 1);
  { The same question asked of the TEXT path, which is what an owner-drawn caption rides on.
    LCL sets the DC's text colour inside the FONT selection, so a font the canvas still
    believes is selected means SetTextColor is never reached and the ink is whatever the
    restore put back. }
  ACanvas.TextOut(ARect.Left + 2, ARect.Top + 2, 'x');
  if LCLIntf.GetTextColor(ACanvas.Handle) <> Probe then Inc(FStaleInkRows);
end;

{ Strokes WELL OUTSIDE its own rect. Everything it draws beyond ARect must be clipped away. }
procedure TComboOwnerDrawTest.HandleDrawOverflowing(Sender: TObject; ACanvas: TCanvas;
  Index: Integer; ARect: TRect; AState: TOwnerDrawState);
const
  Probe = TColor($00C800);
begin
  RecordCall(Index, ARect, AState);
  ACanvas.Pen.Color := Probe;
  ACanvas.Brush.Color := Probe;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.FillRect(ARect.Left, ARect.Top - 40, ARect.Right, ARect.Bottom + 40);
end;

{ ---- the closed field ------------------------------------------------------------- }

procedure TComboOwnerDrawTest.TestStyleValuesAppendedAndDefaultOrdinalHeld;
var c: TTyComboBox;
begin
  { csDropDownList MUST stay ordinal 0. A .lfm stores Style by identifier, but the published
    property's `default csDropDownList` is stored as an ORDINAL, and every .lfm in this repo
    and in users' projects omits Style and is read against it. Appending values is safe;
    inserting one silently re-reads every existing form. }
  AssertEquals('csDropDownList is still ordinal 0', 0, Ord(csDropDownList));
  AssertEquals('csDropDown is still ordinal 1', 1, Ord(csDropDown));
  AssertEquals('the owner-draw values were APPENDED, not inserted', 2, Ord(csOwnerDrawFixed));
  AssertEquals('...both of them', 3, Ord(csOwnerDrawEditableFixed));
  c := TTyComboBox.Create(nil);
  try
    AssertTrue('a fresh combo is STILL pick-only -- the inverted default is deliberate',
      c.Style = csDropDownList);
  finally c.Free; end;
  { The two predicates LCL spells as TComboBoxStyleHelper (stdctrls.pp:271-278). }
  AssertFalse('csDropDownList has no edit box', TyComboStyleHasEditBox(csDropDownList));
  AssertTrue ('csDropDown has one',             TyComboStyleHasEditBox(csDropDown));
  AssertFalse('csOwnerDrawFixed is pick-only',  TyComboStyleHasEditBox(csOwnerDrawFixed));
  AssertTrue ('csOwnerDrawEditableFixed is not',TyComboStyleHasEditBox(csOwnerDrawEditableFixed));
  AssertFalse('csDropDown is not owner-drawn',  TyComboStyleIsOwnerDrawn(csDropDown));
  AssertTrue ('csOwnerDrawFixed is',            TyComboStyleIsOwnerDrawn(csOwnerDrawFixed));
  AssertTrue ('csOwnerDrawEditableFixed is',    TyComboStyleIsOwnerDrawn(csOwnerDrawEditableFixed));
end;

procedure TComboOwnerDrawTest.TestEditableOwnerDrawStyleShowsTheEditor;
var c: TTyComboBox;
begin
  { The editable/pick-only split is orthogonal to owner-draw, and every place that asked
    `Style = csDropDown` had to become the predicate or the new editable style would come up
    with no edit field at all. }
  c := TTyComboBox.Create(nil);
  try
    c.Style := csOwnerDrawEditableFixed;
    AssertTrue('csOwnerDrawEditableFixed shows the embedded editor', c.EditorVisibleForTest);
    c.Style := csOwnerDrawFixed;
    AssertFalse('csOwnerDrawFixed does not', c.EditorVisibleForTest);
  finally c.Free; end;
end;

procedure TComboOwnerDrawTest.TestOwnerDrawFieldSuppressesTheDefaultContent;
var owned, blank: TComboRender;
begin
  { A silent handler paints nothing, so an owner-drawn field must come out EXACTLY as an
    empty one: proof the default content is gone rather than merely covered. }
  owned := TComboRender.Create(nil);
  blank := TComboRender.Create(nil);
  try
    owned.Items.Add('Belgium'); owned.ItemIndex := 0;
    owned.OnDrawItem := @HandleDrawSilent;
    owned.Style := csOwnerDrawFixed;
    AssertFalse('an owner-drawn field shows none of the default text',
      ComboRenderDiffers(owned, blank, 140, 26));
    AssertEquals('and the handler was asked exactly once, for the field', 1, FCalls);
    AssertTrue('with odComboBoxEdit, which is how a shared handler knows it is the field',
      odComboBoxEdit in FStateSeen[0]);
    AssertTrue('and odBackgroundPainted, because DrawFrame already ran',
      odBackgroundPainted in FStateSeen[0]);
    AssertEquals('Index is the selected row', 0, FIndexSeen[0]);
  finally
    owned.Free; blank.Free;
  end;
end;

procedure TComboOwnerDrawTest.TestOwnerDrawStyleWithoutAHandlerKeepsTheThemedField;
var owned, plain: TComboRender;
begin
  { Setting Style alone must never blank a control. LCL/Win32 paints nothing in that case;
    keeping the themed default is the strictly better rule and this is what pins it. }
  owned := TComboRender.Create(nil);
  plain := TComboRender.Create(nil);
  try
    owned.Items.Add('Belgium'); owned.ItemIndex := 0;
    plain.Items.Add('Belgium'); plain.ItemIndex := 0;
    owned.Style := csOwnerDrawFixed;         // no OnDrawItem
    AssertFalse('an owner-draw style with no handler renders the themed default',
      ComboRenderDiffers(owned, plain, 140, 26));
  finally
    owned.Free; plain.Free;
  end;
end;

procedure TComboOwnerDrawTest.TestHandlerIsInertAtTheDefaultStyle;
var
  owned, plain: TComboRender;
  cOwned, cPlain: TTyComboBox;
begin
  { The other half of the same gate, and the one that protects every existing form: a combo
    left at csDropDownList must be byte-identical whether or not an OnDrawItem is hanging
    off it. BOTH surfaces have to say so -- the field and the drop-down rows read the gate
    through different predicates, and a version that checked only Assigned(OnDrawItem) for
    the rows passed a field-only version of this test. }
  owned := TComboRender.Create(nil);
  plain := TComboRender.Create(nil);
  try
    owned.Items.Add('Belgium'); owned.ItemIndex := 0;
    plain.Items.Add('Belgium'); plain.ItemIndex := 0;
    owned.OnDrawItem := @HandleDrawSameStateEveryCall;
    AssertFalse('a handler on a csDropDownList combo changes the field not at all',
      ComboRenderDiffers(owned, plain, 140, 26));
    AssertEquals('and is never called for it', 0, FCalls);
  finally
    owned.Free; plain.Free;
  end;
  cOwned := MakeCombo(csDropDownList, @HandleDrawSameStateEveryCall);
  cPlain := MakeCombo(csDropDownList, nil);
  AssertFalse('...nor the drop-down rows',
    ListRenderDiffers(MakeList(cOwned), MakeList(cPlain), ListW, ListH));
  AssertEquals('and is never called for those either', 0, FCalls);
  AssertFalse('OwnerDrawsRows answers on the STYLE, not merely on the handler',
    cOwned.OwnerDrawsRows);
end;

procedure TComboOwnerDrawTest.TestOwnerDrawFieldSurvivesTheComposite;
const
  W = 140; H = 26;
var
  c: TComboRender;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  R: TRect;
  P: TBGRAPixel;
begin
  { THE TRAP. The painter builds into a BGRA layer and EndPaint blits it over the canvas, so
    a handler dispatched before that line has its pixels ERASED and the control renders as
    if no handler existed. Nothing but the pixels can tell the two apart -- the call count is
    the same either way. }
  c := TComboRender.Create(nil);
  Bmp := TBitmap.Create;
  try
    c.Items.Add('Belgium'); c.ItemIndex := 0;
    c.OnDrawItem := @HandleDrawSameStateEveryCall;
    c.Style := csOwnerDrawFixed;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, W, H);
    c.Render(Bmp.Canvas, Rect(0, 0, W, H), 96);
    AssertEquals('the field handler ran', 1, FCalls);
    R := FRectSeen[0];
    Img := TBGRABitmap.Create(Bmp);
    try
      P := Img.GetPixel(R.Left, R.Top);
      AssertTrue(Format('the field handler''s ink survived EndPaint at (%d,%d) ' +
        '(got R%d G%d B%d)', [R.Left, R.Top, P.red, P.green, P.blue]), IsGreenInk(P));
    finally Img.Free; end;
  finally
    c.Free; Bmp.Free;
  end;
end;

procedure TComboOwnerDrawTest.TestOwnerDrawFieldClipsToTheTextZone;
const
  W = 140; H = 26;
var
  c: TComboRender;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  R: TRect;
  y: Integer;
  P: TBGRAPixel;
begin
  { The field handler is given the text zone -- the same rect PaintFieldContent would have
    had, inset by the theme's padding and stopping short of the chevron. It must not be able
    to paint over the frame or the drop arrow, so the clip is set to that rect inside the
    same bracket as the call. This handler deliberately paints 40px past both ends. }
  c := TComboRender.Create(nil);
  Bmp := TBitmap.Create;
  try
    c.Items.Add('Belgium'); c.ItemIndex := 0;
    c.OnDrawItem := @HandleDrawOverflowing;
    c.Style := csOwnerDrawFixed;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, W, H);
    c.Render(Bmp.Canvas, Rect(0, 0, W, H), 96);
    AssertEquals('the field handler ran', 1, FCalls);
    R := FRectSeen[0];
    AssertTrue('the field rect leaves a band above and below to probe',
      (R.Top >= 2) and (R.Bottom <= H - 2));
    Img := TBGRABitmap.Create(Bmp);
    try
      for y := 1 to 2 do
      begin
        P := Img.GetPixel(R.Left + 2, R.Top - y);
        AssertFalse(Format('the field handler bled %d px above its rect (R%d G%d B%d)',
          [y, P.red, P.green, P.blue]), IsGreenInk(P));
        P := Img.GetPixel(R.Left + 2, R.Bottom - 1 + y);
        AssertFalse(Format('the field handler bled %d px below its rect (R%d G%d B%d)',
          [y, P.red, P.green, P.blue]), IsGreenInk(P));
      end;
    finally Img.Free; end;
  finally
    c.Free; Bmp.Free;
  end;
end;

{ ---- the drop-down rows ------------------------------------------------------------ }

function TComboOwnerDrawTest.MakeCombo(AStyle: TTyComboBoxStyle;
  AHandler: TTyDrawItemEvent): TTyComboBox;
begin
  Result := TTyComboBox.Create(FForm);
  Result.Items.Add('Alpha');
  Result.Items.Add('Beta');
  Result.Items.Add('Gamma');
  Result.OnDrawItem := AHandler;
  Result.Style := AStyle;
end;

function TComboOwnerDrawTest.MakeList(ACombo: TTyComboBox): TTyComboPopupList;
begin
  { Owner is the COMBO and Parent is the form -- the real arrangement (CreatePopupList does
    Create(Self), then the popup helper parents the list into its own window), and the one
    the protocol reads: it finds the combo through Owner. }
  Result := TTyComboPopupList.Create(ACombo);
  Result.Parent := FForm;
  Result.Font.PixelsPerInch := 96;
  Result.ItemHeight := 24;
  Result.SetBounds(0, 0, ListW, ListH);
  Result.Items.Assign(ACombo.Items);
  Result.SelectItem(1);
  Result.TopIndex := 0;
end;

procedure TComboOwnerDrawTest.TestOwnerDrawRowsSuppressTheDefaultRowContent;
var
  cOwn, cPlain, cEmpty: TTyComboBox;
  lOwn, lPlain, lEmpty: TTyComboPopupList;
begin
  { Three renders. Owner-drawn-with-a-silent-handler must DIFFER from the themed default
    (the captions really did go) and must be IDENTICAL to the same list holding empty
    strings (nothing but the captions went -- the row backgrounds and the selection
    highlight are still down, which is what odBackgroundPainted promises the handler). }
  cOwn   := MakeCombo(csOwnerDrawFixed, @HandleDrawSilent);
  cPlain := MakeCombo(csDropDownList, nil);
  cEmpty := MakeCombo(csDropDownList, nil);
  cEmpty.Items.Clear;
  cEmpty.Items.Add(''); cEmpty.Items.Add(''); cEmpty.Items.Add('');
  lOwn   := MakeList(cOwn);
  lPlain := MakeList(cPlain);
  lEmpty := MakeList(cEmpty);
  AssertTrue('owner-drawn rows do not show the default captions',
    ListRenderDiffers(lOwn, lPlain, ListW, ListH));
  AssertEquals('every visible row was offered to the handler', 3, FCalls);
  AssertTrue('the selected row is reported as odSelected', odSelected in FStateSeen[1]);
  AssertFalse('an unselected row is not', odSelected in FStateSeen[0]);
  AssertTrue('and every row carries odBackgroundPainted',
    odBackgroundPainted in FStateSeen[0]);
  AssertFalse('a row is NOT told odComboBoxEdit -- that is the field''s marker',
    odComboBoxEdit in FStateSeen[0]);
  AssertFalse('and nothing but the captions went: backgrounds and highlight remain',
    ListRenderDiffers(lOwn, lEmpty, ListW, ListH));
end;

procedure TComboOwnerDrawTest.TestOwnerDrawRowIndexIsAnItemsIndex;
var
  c: TTyComboBox;
  l: TTyComboPopupList;
  Bmp: TBitmap;
begin
  { The popup does not always hold Items: typing in an editable combo fills it with the
    prefix-FILTERED subset. OnDrawItem's Index is documented as an index into Items, so a
    handler doing the obvious Items[Index] must not read the wrong row. }
  c := MakeCombo(csOwnerDrawEditableFixed, @HandleDrawSilent);
  l := TTyComboPopupList.Create(c);
  Bmp := TBitmap.Create;
  try
    l.Parent := FForm;
    l.Font.PixelsPerInch := 96;
    l.ItemHeight := 24;
    l.SetBounds(0, 0, ListW, ListH);
    l.Items.Add('Gamma');          // the filtered subset: one row, Items' LAST one
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(ListW, ListH);
    l.RenderWithOwnerDraw(Bmp.Canvas, Rect(0, 0, ListW, ListH), 96);
    AssertEquals('one filtered row was drawn', 1, FCalls);
    AssertEquals('Index is the row''s position in ITEMS, not in the filtered list',
      2, FIndexSeen[0]);
  finally
    Bmp.Free;
  end;
end;

procedure TComboOwnerDrawTest.TestOwnerDrawRowsClipToTheirOwnRow;
const
  Overhang = 6;
var
  c: TTyComboBox;
  l: TTyComboPopupList;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  y: Integer;
  P: TBGRAPixel;
begin
  { A handler that draws outside its rect must not reach its neighbour -- or the popup's own
    frame. The clip is per row and set inside the same bracket as the callback. }
  c := MakeCombo(csOwnerDrawFixed, @HandleDrawOverflowing);
  l := MakeList(c);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(ListW, ListH);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, ListW, ListH);
    l.RenderWithOwnerDraw(Bmp.Canvas, Rect(0, 0, ListW, ListH), 96);
    AssertEquals('three rows drew', 3, FCalls);
    Img := TBGRABitmap.Create(Bmp);
    try
      { Above the FIRST row: the list's own padding / border band. The handler filled 40px
        past its top edge, so without the clip this is green. }
      for y := 1 to Overhang do
        if FRectSeen[0].Top - y >= 0 then
        begin
          P := Img.GetPixel(FRectSeen[0].Left + 2, FRectSeen[0].Top - y);
          AssertFalse(Format('row 0 bled %d px above its rect (R%d G%d B%d)',
            [y, P.red, P.green, P.blue]), IsGreenInk(P));
        end;
      { Below the LAST row, same reasoning at the other end. }
      for y := 1 to Overhang do
        if FRectSeen[2].Bottom - 1 + y < ListH then
        begin
          P := Img.GetPixel(FRectSeen[2].Left + 2, FRectSeen[2].Bottom - 1 + y);
          AssertFalse(Format('row 2 bled %d px below its rect (R%d G%d B%d)',
            [y, P.red, P.green, P.blue]), IsGreenInk(P));
        end;
    finally Img.Free; end;
  finally
    Bmp.Free;
  end;
end;

procedure TComboOwnerDrawTest.TestOwnerDrawRowStateSurvivesEveryRow;
const
  SeedRed = TColor($0000DC);   // BGR literal: pure red
var
  c: TTyComboBox;
  l: TTyComboPopupList;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  k, xr: Integer;
  R: TRect;

  procedure AssertGreenAt(const AWhere: string; x, y: Integer);
  var P: TBGRAPixel;
  begin
    P := Img.GetPixel(x, y);
    AssertTrue(Format('%s at (%d,%d) drew with the DC''s pen, not the handler''s ' +
      '(got R%d G%d B%d, seeded red)', [AWhere, x, y, P.red, P.green, P.blue]),
      (P.green > 160) and (P.red < 96) and (P.blue < 96));
  end;

begin
  { EVERY owner-drawn row must ink with what ITS handler asked for, not with what the row
    before it left in the DC. The dispatch brackets each callback in a DC save/restore; the
    restore has to be one the LCL canvas knows about (SaveHandleState/RestoreHandleState), or
    the canvas goes on believing its Pen/Font are still selected while the restore has swapped
    them out -- and from the SECOND row onwards the handler's assignments become silent
    no-ops. This exact defect shipped twice this week: 2477173 (tree), 7629c14 (menu).

    Non-vacuous by construction: the canvas's pen and ink are seeded RED and driven into the
    DC first, so a row that skips the re-select strokes red, not green. }
  c := MakeCombo(csOwnerDrawFixed, @HandleDrawSameStateEveryCall);
  l := MakeList(c);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(ListW, ListH);
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, ListW, ListH);
    { Seed the canvas's PEN and INK red and drive BOTH into the DC, so "whatever the DC is
      currently holding" is a colour the handler never asks for. Off-surface, so the seed
      strokes cannot be mistaken for a probe. }
    Bmp.Canvas.Pen.Color  := SeedRed;
    Bmp.Canvas.Font.Color := SeedRed;
    Bmp.Canvas.MoveTo(-8, -8);
    Bmp.Canvas.LineTo(-4, -8);
    Bmp.Canvas.TextOut(-40, -40, 'x');

    l.RenderWithOwnerDraw(Bmp.Canvas, Rect(0, 0, ListW, ListH), 96);
    AssertEquals('three rows were owner-drawn -- the defect starts at the SECOND call',
      3, FCalls);
    Img := TBGRABitmap.Create(Bmp);
    try
      for k := 0 to FCalls - 1 do
      begin
        R := FRectSeen[k];
        xr := Min(R.Right - 1, ListW - 1);
        AssertTrue('the probed row has room to stroke',
          (R.Left < xr) and (R.Bottom - R.Top >= 4));
        AssertGreenAt(Format('row %d: top-left', [k]),     R.Left, R.Top);
        AssertGreenAt(Format('row %d: top-right', [k]),    xr,     R.Top);
        AssertGreenAt(Format('row %d: bottom-left', [k]),  R.Left, R.Bottom - 1);
        AssertGreenAt(Format('row %d: bottom-right', [k]), xr,     R.Bottom - 1);
      end;
      AssertEquals('every row inked with the colour its handler set', 0, FStaleInkRows);
    finally Img.Free; end;
  finally
    Bmp.Free;
  end;
end;

procedure TComboOwnerDrawTest.TestRowCollectionDoesNotAccumulateAcrossPaints;
const
  Rows = 3;
var
  c: TTyComboBox;
  l: TTyComboPopupList;
  Bmp: TBitmap;
begin
  { A live drop-down repaints on every hover and every scroll. The pending row list is
    rebuilt from scratch each time, so it has to be CLEARED first -- leave that out and the
    dispatch grows by one screenful per paint, replaying stale rects for ever. }
  c := MakeCombo(csOwnerDrawFixed, @HandleDrawSilent);
  l := MakeList(c);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(ListW, ListH);
    l.RenderWithOwnerDraw(Bmp.Canvas, Rect(0, 0, ListW, ListH), 96);
    AssertEquals('three rows on the first paint', Rows, FCalls);
    l.RenderWithOwnerDraw(Bmp.Canvas, Rect(0, 0, ListW, ListH), 96);
    AssertEquals('three MORE on the second -- not the first paint''s rows again as well',
      Rows * 2, FCalls);
    AssertEquals('the pending list holds one screenful, not two',
      Rows, c.RowOwnerDrawCountForTest);
  finally
    Bmp.Free;
  end;
end;

procedure TComboOwnerDrawTest.TestAssigningTheHandlerRepaints;
var p: TComboInvalidateProbe;
begin
  { Style first and the handler second is the ordinary order, and it is the SECOND write
    that switches an owner-draw combo from the themed default to the host's paint. Without a
    repaint there the control keeps the render it had before the handler existed. }
  p := TComboInvalidateProbe.Create(nil);
  try
    p.Style := csOwnerDrawFixed;
    p.Invalidations := 0;
    p.OnDrawItem := @HandleDrawSilent;
    AssertTrue('assigning OnDrawItem repaints', p.Invalidations > 0);
    p.Invalidations := 0;
    p.OnDrawItem := nil;
    AssertTrue('and so does clearing it', p.Invalidations > 0);
  finally p.Free; end;
end;

{ ---- the two siblings --------------------------------------------------------------- }

procedure TComboOwnerDrawTest.TestOwnerDrawReachesComboBoxEx;
var
  c: TTyComboBoxEx;
  lOwn, lPlain: TTyComboBoxExPopupList;

  function BuildEx(AStyle: TTyComboBoxStyle; AHandler: TTyDrawItemEvent): TTyComboBoxEx;
  begin
    Result := TTyComboBoxEx.Create(FForm);
    Result.Items.Add('Alpha'); Result.Items.Add('Beta'); Result.Items.Add('Gamma');
    Result.OnDrawItem := AHandler;
    Result.Style := AStyle;
  end;

  function BuildList(ACombo: TTyComboBoxEx): TTyComboBoxExPopupList;
  begin
    Result := TTyComboBoxExPopupList.Create(ACombo);
    Result.Parent := FForm;
    Result.Font.PixelsPerInch := 96;
    Result.ItemHeight := 24;
    Result.SetBounds(0, 0, ListW, ListH);
    Result.Items.Assign(ACombo.Items);
    Result.TopIndex := 0;
  end;

begin
  { A fix that lands on a base and not its override is half a fix. TTyComboBoxEx replaces
    the row painter outright (image + name), so the skip has to be spelled out in ITS
    PaintItemContent -- an inherited call would already be too late. }
  c := BuildEx(csOwnerDrawFixed, @HandleDrawSilent);
  lOwn := BuildList(c);
  lPlain := BuildList(BuildEx(csDropDownList, nil));
  AssertTrue('TTyComboBoxEx rows reach the host handler',
    ListRenderDiffers(lOwn, lPlain, ListW, ListH));
  AssertEquals('once per visible row', 3, FCalls);
end;

procedure TComboOwnerDrawTest.TestOwnerDrawReachesCheckComboBox;
var
  c: TTyCheckComboBox;
  lOwn, lPlain: TTyCheckComboPopupList;

  function BuildCheck(AStyle: TTyComboBoxStyle; AHandler: TTyDrawItemEvent): TTyCheckComboBox;
  begin
    Result := TTyCheckComboBox.Create(FForm);
    Result.Items.Add('Alpha'); Result.Items.Add('Beta'); Result.Items.Add('Gamma');
    Result.OnDrawItem := AHandler;
    Result.Style := AStyle;
  end;

  function BuildList(ACombo: TTyCheckComboBox): TTyCheckComboPopupList;
  begin
    Result := TTyCheckComboPopupList.Create(ACombo);
    Result.Parent := FForm;
    Result.Font.PixelsPerInch := 96;
    Result.ItemHeight := 24;
    Result.SetBounds(0, 0, ListW, ListH);
    Result.Items.Assign(ACombo.Items);
    Result.TopIndex := 0;
  end;

begin
  { The other override, and the one whose popup list descends from TTyCheckListBox instead
    of TTyListBox -- no shared shim class can reach it, which is why the protocol is three
    calls it copies rather than an ancestor it inherits. }
  c := BuildCheck(csOwnerDrawFixed, @HandleDrawSilent);
  AssertTrue('the pick-only lock lets an owner-draw style THROUGH',
    c.Style = csOwnerDrawFixed);
  lOwn := BuildList(c);
  lPlain := BuildList(BuildCheck(csDropDownList, nil));
  AssertTrue('TTyCheckComboBox rows reach the host handler',
    ListRenderDiffers(lOwn, lPlain, ListW, ListH));
  AssertEquals('once per visible row', 3, FCalls);
end;

procedure TComboOwnerDrawTest.TestPickOnlyLockDropsTheEditBoxNotTheOwnerDraw;
var c: TTyCheckComboBox;
begin
  { The lock used to replace the whole style with csDropDownList. Owner-draw is orthogonal
    to editability, so it now takes only the EDIT BOX off -- LCL's SetEditBox(False). }
  c := TTyCheckComboBox.Create(nil);
  try
    c.Style := csDropDown;
    AssertTrue('an editable style is still refused', c.Style = csDropDownList);
    c.Style := csOwnerDrawEditableFixed;
    AssertTrue('the EDITABLE owner-draw style lands as its pick-only twin',
      c.Style = csOwnerDrawFixed);
    c.Style := csDropDownList;
    c.Style := csOwnerDrawFixed;
    AssertTrue('and the pick-only one passes through untouched',
      c.Style = csOwnerDrawFixed);
  finally c.Free; end;
  { The two style-mapping cases stated once, on the function itself. }
  AssertTrue(TyComboStylePickOnly(csDropDown) = csDropDownList);
  AssertTrue(TyComboStylePickOnly(csOwnerDrawEditableFixed) = csOwnerDrawFixed);
  AssertTrue(TyComboStylePickOnly(csOwnerDrawFixed) = csOwnerDrawFixed);
  AssertTrue(TyComboStylePickOnly(csDropDownList) = csDropDownList);
end;

initialization
  RegisterTest(TComboBoxParityTest);
  RegisterTest(TComboOwnerDrawTest);
end.
