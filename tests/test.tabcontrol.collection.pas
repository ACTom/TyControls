unit test.tabcontrol.collection;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Forms, Controls,
  fpcunit, testregistry,
  tyControls.Panel, tyControls.TabControl;

type
  { Change-count probe (local copy so this unit never depends on the locked
    test.tabcontrol unit's private probe). }
  TTabChangeProbe = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  { Access subclass exposing the protected streaming lifecycle hooks so the
    csLoading -> Loaded sequence can be driven headlessly without an IDE/reader.
    Loading/Loaded are protected virtual TComponent methods; Loading sets
    csLoading, Loaded (inherited) clears it. }
  TTyTabControlAccess = class(TTyTabControl)
  public
    procedure SetLoadingState(AValue: Boolean);
    procedure CallLoaded;
  end;

  TTyTabCollectionTest = class(TTestCase)
  private
    FForm: TForm;
    FTab: TTyTabControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddTabCreatesItem;
    procedure TestCollectionAddCreatesPageAndCaption;
    procedure TestCollectionDeleteRemovesPage;
    procedure TestEditItemCaptionUpdatesTabCaption;
    // Backward-compat regression guard for the collection rewrite. These
    // duplicate the intent of the locked test.tabcontrol cases but live here so
    // the locked file is never edited.
    procedure TestAddTabFirstAutoSelectsNoOnChange;
    procedure TestRemoveTabIndexMathMatchesLegacy;
    procedure TestRemoveActiveFiresOnChangeOnce;
    procedure TestExternalFreePageDeletesItem;
    procedure TestRemoveTabOutOfRangeNoOp;
    // Streaming lifecycle: TabItemAdded defers page creation during csLoading,
    // and Loaded materializes the streamed items and applies the saved TabIndex.
    procedure TestLoadedMaterializesStreamedItems;
    procedure TestLoadedAppliesSavedTabIndex;
    procedure TestTabIndexPublishedDefaultMinusOne;
    // Reorder: moving a collection item (TCollectionItem.SetIndex -> Changed(True)
    // -> Update(nil)) must re-sync the parallel page/caption arrays to the new
    // item order and keep the same page object active.
    procedure TestReorderItemsReordersPages;
    // Full text-format round-trip: WriteComponent -> ObjectBinaryToText asserts the
    // serialized Tabs <...> block + saved TabIndex; ObjectTextToBinary ->
    // ReadComponent into a FRESH owner rehydrates the collection, pages, selection.
    procedure TestStreamRoundTrip;
  end;

implementation

{ TTabChangeProbe }

procedure TTabChangeProbe.Handle(Sender: TObject);
begin
  Inc(Count);
end;

{ TTyTabControlAccess }

procedure TTyTabControlAccess.SetLoadingState(AValue: Boolean);
begin
  if AValue then
    Loading            // protected: Include(csLoading)
  else
    Loaded;            // protected: clears csLoading (+ our materialization)
end;

procedure TTyTabControlAccess.CallLoaded;
begin
  Loaded;
end;

procedure TTyTabCollectionTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FTab := TTyTabControl.Create(FForm);
  FTab.Parent := FForm;
  FTab.SetBounds(0, 0, 300, 200);
  FTab.Font.PixelsPerInch := 96;
end;

procedure TTyTabCollectionTest.TearDown;
begin
  FForm.Free;
end;

{ (a) AddTab creates a backing collection item; page returned by AddTab is the
  same object as Pages[0] and as Tabs.Items[0].Page. }
procedure TTyTabCollectionTest.TestAddTabCreatesItem;
var
  Page: TTyPanel;
begin
  Page := FTab.AddTab('A');
  AssertEquals('Tabs.Count = 1', 1, FTab.Tabs.Count);
  AssertEquals('Tabs.Items[0].Caption = A', 'A', FTab.Tabs.Items[0].Caption);
  AssertSame('AddTab result = Pages[0]', FTab.Pages[0], Page);
  AssertSame('Pages[0] = Tabs.Items[0].Page', FTab.Pages[0], FTab.Tabs.Items[0].Page);
end;

{ (b) Adding through the collection creates the page + caption, bumps TabCount,
  and the first add auto-selects index 0. }
procedure TTyTabCollectionTest.TestCollectionAddCreatesPageAndCaption;
var
  Item: TTyTabItem;
begin
  Item := FTab.Tabs.Add;
  Item.Caption := 'X';
  AssertEquals('TabCount = 1', 1, FTab.TabCount);
  AssertEquals('TabCaption(0) = X', 'X', FTab.TabCaption(0));
  AssertNotNull('Pages[0] not nil', FTab.Pages[0]);
  AssertEquals('first add auto-selects index 0', 0, FTab.TabIndex);
end;

{ (c) Deleting a middle item through the collection removes its page and
  compacts captions. }
procedure TTyTabCollectionTest.TestCollectionDeleteRemovesPage;
var
  A, B, C: TTyTabItem;
begin
  A := FTab.Tabs.Add; A.Caption := 'A';
  B := FTab.Tabs.Add; B.Caption := 'B';
  C := FTab.Tabs.Add; C.Caption := 'C';
  AssertEquals('3 tabs', 3, FTab.TabCount);
  FTab.Tabs.Delete(1);
  AssertEquals('2 tabs after delete', 2, FTab.TabCount);
  AssertEquals('caption[1] now C', 'C', FTab.TabCaption(1));
end;

{ (d) Editing an item's Caption updates the displayed tab caption. }
procedure TTyTabCollectionTest.TestEditItemCaptionUpdatesTabCaption;
begin
  FTab.AddTab('A');
  FTab.Tabs.Items[0].Caption := 'Renamed';
  AssertEquals('TabCaption(0) reflects item caption', 'Renamed', FTab.TabCaption(0));
end;

{ (a) Attaching an OnChange probe BEFORE the first AddTab and then adding one
  tab must auto-select index 0 WITHOUT firing OnChange (first add is not a
  selection "change" from a previous state). }
procedure TTyTabCollectionTest.TestAddTabFirstAutoSelectsNoOnChange;
var
  Probe: TTabChangeProbe;
begin
  Probe := TTabChangeProbe.Create;
  try
    FTab.OnChange := @Probe.Handle;
    FTab.AddTab('A');
    AssertEquals('first add auto-selects index 0', 0, FTab.TabIndex);
    AssertEquals('first add fires no OnChange', 0, Probe.Count);
  finally
    Probe.Free;
  end;
end;

{ (b) Removing a tab BEFORE the active one shifts the index down by one, keeps
  the SAME page object active and visible, and does NOT fire OnChange (the
  active page did not change). }
procedure TTyTabCollectionTest.TestRemoveTabIndexMathMatchesLegacy;
var
  Probe: TTabChangeProbe;
  PageC: TTyPanel;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  PageC := FTab.AddTab('C');
  FTab.TabIndex := 2;
  Probe := TTabChangeProbe.Create;
  try
    FTab.OnChange := @Probe.Handle;
    FTab.RemoveTab(0);
    AssertEquals('index shifts 2 -> 1', 1, FTab.TabIndex);
    AssertSame('same C page still active', PageC, FTab.Pages[1]);
    AssertTrue('active C page still visible', FTab.Pages[1].Visible);
    AssertEquals('OnChange NOT fired (same page active)', 0, Probe.Count);
  finally
    Probe.Free;
  end;
end;

{ (c) Removing the ACTIVE last tab selects the new last neighbor, fires
  OnChange exactly once, and compacts the backing Tabs collection in lockstep. }
procedure TTyTabCollectionTest.TestRemoveActiveFiresOnChangeOnce;
var
  Probe: TTabChangeProbe;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  FTab.AddTab('C');
  FTab.TabIndex := 2;
  Probe := TTabChangeProbe.Create;
  try
    FTab.OnChange := @Probe.Handle;
    FTab.RemoveTab(2);
    AssertEquals('index falls back to new last (1)', 1, FTab.TabIndex);
    AssertEquals('OnChange fired exactly once', 1, Probe.Count);
    AssertEquals('Tabs collection compacted in lockstep', 2, FTab.Tabs.Count);
  finally
    Probe.Free;
  end;
end;

{ (d) Freeing a page externally (PageB.Free) must delete the owning collection
  item through the Notification path without double-freeing the page, compacting
  captions, pages and the Tabs collection together. }
procedure TTyTabCollectionTest.TestExternalFreePageDeletesItem;
var
  PageB: TTyPanel;
begin
  FTab.AddTab('A');
  PageB := FTab.AddTab('B');
  FTab.AddTab('C');
  AssertEquals('3 tabs before free', 3, FTab.TabCount);
  PageB.Free;
  AssertEquals('TabCount = 2 after external free', 2, FTab.TabCount);
  AssertEquals('Tabs.Count = 2 (item deleted in lockstep)', 2, FTab.Tabs.Count);
  AssertEquals('caption[1] now C', 'C', FTab.TabCaption(1));
  AssertSame('Pages[1] = Tabs.Items[1].Page', FTab.Pages[1], FTab.Tabs.Items[1].Page);
end;

{ (e) RemoveTab with an out-of-range index is a no-op. }
procedure TTyTabCollectionTest.TestRemoveTabOutOfRangeNoOp;
begin
  FTab.AddTab('A');
  FTab.RemoveTab(5);
  FTab.RemoveTab(-1);
  AssertEquals('still 1 tab in collection', 1, FTab.Tabs.Count);
end;

{ Streaming (a): items added to the Tabs collection while csLoading is active
  must NOT get a page yet (TabItemAdded defers). After Loaded the parallel
  arrays are rebuilt: TabCount reflects the items, each item has a live page,
  and Pages[i] is the same object as Tabs.Items[i].Page. }
procedure TTyTabCollectionTest.TestLoadedMaterializesStreamedItems;
var
  Acc: TTyTabControlAccess;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  try
    Acc.Parent := FForm;
    Acc.SetLoadingState(True);
    Acc.Tabs.Add.Caption := 'S1';
    Acc.Tabs.Add.Caption := 'S2';
    // page creation deferred while loading
    Acc.CallLoaded;
    AssertEquals('2 tabs after Loaded', 2, Acc.TabCount);
    AssertNotNull('Pages[0] materialized', Acc.Pages[0]);
    AssertNotNull('Pages[1] materialized', Acc.Pages[1]);
    AssertSame('Tabs.Items[0].Page = Pages[0]', Acc.Pages[0], Acc.Tabs.Items[0].Page);
    AssertSame('Tabs.Items[1].Page = Pages[1]', Acc.Pages[1], Acc.Tabs.Items[1].Page);
  finally
    Acc.Free;
  end;
end;

{ Streaming (b): a TabIndex written during csLoading is captured (pending) and
  applied in Loaded so the saved selection is restored. }
procedure TTyTabCollectionTest.TestLoadedAppliesSavedTabIndex;
var
  Acc: TTyTabControlAccess;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  try
    Acc.Parent := FForm;
    Acc.SetLoadingState(True);
    Acc.Tabs.Add.Caption := 'S1';
    Acc.Tabs.Add.Caption := 'S2';
    Acc.TabIndex := 1;          // stored as pending while loading
    Acc.CallLoaded;
    AssertEquals('saved TabIndex applied', 1, Acc.TabIndex);
    AssertTrue('Pages[1] visible', Acc.Pages[1].Visible);
    AssertFalse('Pages[0] hidden', Acc.Pages[0].Visible);
  finally
    Acc.Free;
  end;
end;

{ Streaming (c): TabIndex is published with default -1 so a fresh control reads
  -1 (RTTI default honored). }
procedure TTyTabCollectionTest.TestTabIndexPublishedDefaultMinusOne;
var
  Fresh: TTyTabControl;
begin
  Fresh := TTyTabControl.Create(FForm);
  try
    Fresh.Parent := FForm;
    AssertEquals('fresh TabIndex default -1', -1, Fresh.TabIndex);
  finally
    Fresh.Free;
  end;
end;

{ Reorder: add A,B,C; move C (index 2) to the front via Items[2].Index := 0.
  TCollectionItem.SetIndex moves the item then Changed(True) -> Update(nil),
  which must rebuild FPages/FCaptions to the new order. The active page object
  (A was active via the first-add auto-select) must remain the active page after
  the move, just at its new index. }
procedure TTyTabCollectionTest.TestReorderItemsReordersPages;
var
  PA, PB, PC, ActiveBefore: TTyPanel;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  FTab.AddTab('C');
  PA := FTab.Pages[0];
  PB := FTab.Pages[1];
  PC := FTab.Pages[2];
  ActiveBefore := FTab.Pages[FTab.TabIndex];

  FTab.Tabs.Items[2].Index := 0;   // move C to the front

  AssertEquals('caption[0] now C', 'C', FTab.TabCaption(0));
  AssertEquals('caption[1] now A', 'A', FTab.TabCaption(1));
  AssertEquals('caption[2] still B', 'B', FTab.TabCaption(2));
  AssertSame('Pages[0] = C page', PC, FTab.Pages[0]);
  AssertSame('Pages[1] = A page', PA, FTab.Pages[1]);
  AssertSame('Pages[2] = B page', PB, FTab.Pages[2]);
  AssertSame('active page object unchanged after reorder',
    ActiveBefore, FTab.Pages[FTab.TabIndex]);
end;

{ Full headless streaming round-trip via the RTL Classes APIs, proving the
  published Tabs collection + TabIndex persist and rehydrate without an IDE.

  Phase 1 (write + text assertions): a TTyTabControl with two tabs and a saved
  selection is serialized with WriteComponent into a binary TMemoryStream, then
  ObjectBinaryToText'd into a human-readable DFM/LFM text form. We assert the
  text carries the `Tabs = <` items block with both item captions and the saved
  `TabIndex = 1`.

  Phase 2 (read back into a FRESH owner): the text is turned back to binary with
  ObjectTextToBinary and ReadComponent'd. The reader drives the csLoading ->
  Loaded lifecycle, so the rehydrated control must expose 2 tabs with the right
  captions, the restored selection, and a visible active page. }
procedure TTyTabCollectionTest.TestStreamRoundTrip;
var
  Root: TForm;
  Src: TTyTabControl;
  BinStream, TextStream, RehydStream: TMemoryStream;
  TextStr: string;
  NewRoot: TForm;
  Loaded: TTyTabControl;
begin
  Root := TForm.CreateNew(nil);
  BinStream := TMemoryStream.Create;
  TextStream := TMemoryStream.Create;
  try
    { Build the source tree: control must be owned by the root so it streams as
      a top-level component whose child pages are nested owned objects. }
    Src := TTyTabControl.Create(Root);
    Src.Parent := Root;
    Src.AddTab('General');
    Src.AddTab('Network');
    Src.TabIndex := 1;

    { Write to a BINARY stream, then convert to TEXT for content assertions. }
    BinStream.WriteComponent(Src);
    BinStream.Position := 0;
    ObjectBinaryToText(BinStream, TextStream);
    TextStream.Position := 0;
    SetLength(TextStr, TextStream.Size);
    if TextStream.Size > 0 then
      TextStream.ReadBuffer(TextStr[1], TextStream.Size);

    AssertTrue('serialized text has an object block',
      Pos('object ', TextStr) > 0);
    AssertTrue('serialized text has a Tabs = < items block',
      Pos('Tabs = <', TextStr) > 0);
    AssertTrue('serialized General caption present',
      Pos('Caption = ''General''', TextStr) > 0);
    AssertTrue('serialized Network caption present',
      Pos('Caption = ''Network''', TextStr) > 0);
    AssertTrue('serialized TabIndex = 1 present',
      Pos('TabIndex = 1', TextStr) > 0);

    { Phase 2: rehydrate from TEXT back to BINARY into a fresh owner. }
    RehydStream := TMemoryStream.Create;
    NewRoot := TForm.CreateNew(nil);
    try
      TextStream.Position := 0;
      ObjectTextToBinary(TextStream, RehydStream);
      RehydStream.Position := 0;

      { ReadComponent with nil instance constructs a fresh TTyTabControl and
        drives csLoading -> Loaded; owner is assigned via the InsertComponent
        the reader performs. We parent it under a fresh root form. }
      Loaded := RehydStream.ReadComponent(nil) as TTyTabControl;
      NewRoot.InsertComponent(Loaded);
      Loaded.Parent := NewRoot;

      AssertEquals('rehydrated TabCount = 2', 2, Loaded.TabCount);
      AssertEquals('rehydrated TabCaption(0) = General', 'General', Loaded.TabCaption(0));
      AssertEquals('rehydrated TabCaption(1) = Network', 'Network', Loaded.TabCaption(1));
      AssertEquals('rehydrated TabIndex = 1', 1, Loaded.TabIndex);
      AssertNotNull('rehydrated Pages[1] exists', Loaded.Pages[1]);
      AssertTrue('rehydrated active Pages[1] visible', Loaded.Pages[1].Visible);
    finally
      RehydStream.Free;
      NewRoot.Free;     // frees the rehydrated control (owned after InsertComponent)
    end;
  finally
    TextStream.Free;
    BinStream.Free;
    Root.Free;
  end;
end;

initialization
  RegisterTest(TTyTabCollectionTest);
  { Streaming needs RTTI class lookup for the reader to construct nested objects. }
  RegisterClass(TTyTabControl);
  RegisterClass(TTyPanel);
end.
