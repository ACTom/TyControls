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
  end;

implementation

{ TTabChangeProbe }

procedure TTabChangeProbe.Handle(Sender: TObject);
begin
  Inc(Count);
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

initialization
  RegisterTest(TTyTabCollectionTest);
end.
