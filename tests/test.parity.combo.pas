unit test.parity.combo;
{$mode objfpc}{$H+}
{ Parity guards for the three combo families against LCL's TComboBox
  (stdctrls.pp), TComboBoxEx and TCheckComboBox (comboex.pas). Each test names the
  LCL member it pins, so a later refactor that quietly drops one goes red here and
  not in a user's ported form. }
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, StdCtrls, fpcunit, testregistry,
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

initialization
  RegisterTest(TComboBoxParityTest);
end.
