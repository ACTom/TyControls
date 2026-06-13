unit test.tabcontrol.collection;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Forms, Controls,
  fpcunit, testregistry,
  tyControls.Panel, tyControls.TabControl;

type
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
  end;

implementation

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

initialization
  RegisterTest(TTyTabCollectionTest);
end.
