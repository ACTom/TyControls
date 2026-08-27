unit test.listgrouppanel.entries;
{$mode objfpc}{$H+}
{ The design-time entry collection (QQ-group request): a published, OI-editable, .lfm-
  streamable model behind the sider, with the code-building API (AddGroup/AddItem/...)
  kept as a delegating facade. The collection is FLAT with a Kind per row -- the
  TTyTreeNodes precedent -- so one standard collection editor shows the whole sider. }
interface

uses
  Classes, SysUtils, Types, Controls, Forms, fpcunit, testregistry,
  tyControls.ListGroupPanel;

type
  TListGroupEntriesTest = class(TTestCase)
  private
    FPanel: TTyListGroupPanel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure EntriesBuildTheModel;
    procedure LegacyAddersFillEntries;
    procedure AddItemInsertsInsideItsGroup;
    procedure OrphanLeadingItemsFormAnImplicitGroup;
    procedure StreamingRoundTripsTheEntries;
    procedure EditsClampTheSelection;
  end;

implementation

type
  THostForm = class(TForm)
  published
    LGP: TTyListGroupPanel;
  end;

procedure TListGroupEntriesTest.SetUp;
begin
  FPanel := TTyListGroupPanel.Create(nil);
  FPanel.Font.PixelsPerInch := 96;
  FPanel.SetBounds(0, 0, 200, 300);
end;

procedure TListGroupEntriesTest.TearDown;
begin
  FPanel.Free;
end;

procedure TListGroupEntriesTest.EntriesBuildTheModel;
begin
  with FPanel.Entries.Add do begin Kind := lgeGroup; Caption := 'Contacts'; ImageIndex := 3; end;
  with FPanel.Entries.Add do begin Kind := lgeItem; Caption := 'Alice'; ImageIndex := 5; end;
  with FPanel.Entries.Add do begin Kind := lgeItem; Caption := 'Bob'; end;
  with FPanel.Entries.Add do begin Kind := lgeGroup; Caption := 'Tasks'; Expanded := False; end;
  with FPanel.Entries.Add do begin Kind := lgeItem; Caption := 'Report'; end;

  AssertEquals('two groups', 2, FPanel.GroupCount);
  AssertEquals('first group holds its two items', 2, FPanel.ItemCount(0));
  AssertEquals('by caption', 'Bob', FPanel.ItemCaption(0, 1));
  AssertEquals('item icon carried', 5, FPanel.ItemImageIndex(0, 0));
  AssertEquals('second group', 'Tasks', FPanel.GroupCaption[1]);
  AssertFalse('a collapsed group streams in collapsed', FPanel.Expanded[1]);
  AssertEquals('its item', 'Report', FPanel.ItemCaption(1, 0));
end;

procedure TListGroupEntriesTest.LegacyAddersFillEntries;
var
  g: Integer;
begin
  g := FPanel.AddGroup('Nav', 7);
  FPanel.AddItem(g, 'Home', 1);
  FPanel.AddItem(g, 'About');
  AssertEquals('three entries behind the facade', 3, FPanel.Entries.Count);
  AssertEquals('a group row first', Ord(lgeGroup), Ord(FPanel.Entries[0].Kind));
  AssertEquals('with its icon', 7, FPanel.Entries[0].ImageIndex);
  AssertEquals('then the items', Ord(lgeItem), Ord(FPanel.Entries[1].Kind));
  AssertEquals('in order', 'About', FPanel.Entries[2].Caption);
end;

procedure TListGroupEntriesTest.AddItemInsertsInsideItsGroup;
var
  gA: Integer;
begin
  gA := FPanel.AddGroup('A');
  FPanel.AddGroup('B');
  FPanel.AddItem(gA, 'a1');    // must land BEFORE group B's row, not at the flat end
  AssertEquals('group A owns it', 1, FPanel.ItemCount(0));
  AssertEquals('group B stays empty', 0, FPanel.ItemCount(1));
  AssertEquals('flat order: A, a1, B', 'a1', FPanel.Entries[1].Caption);
  AssertEquals('B pushed after', 'B', FPanel.Entries[2].Caption);
end;

procedure TListGroupEntriesTest.OrphanLeadingItemsFormAnImplicitGroup;
begin
  // The designer can author an item before any group; dropping the row silently would
  // be hostile, so it belongs to an implicit caption-less group that is always expanded.
  with FPanel.Entries.Add do begin Kind := lgeItem; Caption := 'Loose'; end;
  with FPanel.Entries.Add do begin Kind := lgeGroup; Caption := 'Real'; end;
  with FPanel.Entries.Add do begin Kind := lgeItem; Caption := 'Inside'; end;

  AssertEquals('the implicit group counts', 2, FPanel.GroupCount);
  AssertEquals('it has no caption', '', FPanel.GroupCaption[0]);
  AssertEquals('and holds the orphan', 'Loose', FPanel.ItemCaption(0, 0));
  AssertTrue('it is always expanded', FPanel.Expanded[0]);
  AssertEquals('the real group follows', 'Real', FPanel.GroupCaption[1]);
  AssertEquals('with its own item', 'Inside', FPanel.ItemCaption(1, 0));
end;

procedure TListGroupEntriesTest.StreamingRoundTripsTheEntries;
var
  Src, Dst: THostForm;
  MS: TMemoryStream;
  DstP: TTyListGroupPanel;
begin
  Src := THostForm.CreateNew(nil);
  Dst := THostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostForm1';
    Src.LGP := TTyListGroupPanel.Create(Src);
    Src.LGP.Name := 'LGP';
    Src.LGP.Parent := Src;
    Src.LGP.AddGroup('Nav', 2);
    Src.LGP.AddItem(0, 'Home', 4);
    Src.LGP.AddItem(0, 'About');
    Src.LGP.Expanded[0] := False;
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);

    DstP := Dst.FindComponent('LGP') as TTyListGroupPanel;
    AssertNotNull('the panel survived', DstP);
    AssertEquals('three entries', 3, DstP.Entries.Count);
    AssertEquals('one group', 1, DstP.GroupCount);
    AssertEquals('its icon', 2, DstP.Entries[0].ImageIndex);
    AssertEquals('items intact', 'Home', DstP.ItemCaption(0, 0));
    AssertEquals('item icon intact', 4, DstP.ItemImageIndex(0, 0));
    AssertEquals('default icon not written, restored as -1', -1, DstP.ItemImageIndex(0, 1));
    AssertFalse('the collapsed flag survived', DstP.Expanded[0]);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

procedure TListGroupEntriesTest.EditsClampTheSelection;
begin
  FPanel.AddGroup('A');
  FPanel.AddItem(0, 'a1');
  FPanel.AddGroup('B');
  FPanel.AddItem(1, 'b1');
  FPanel.SelectItem(1, 0);
  AssertEquals('fixture: selected in group B', 1, FPanel.SelectedGroup);

  // Deleting group B's rows from the collection must not leave a dangling selection.
  FPanel.Entries.Delete(3);
  FPanel.Entries.Delete(2);
  AssertEquals('one group left', 1, FPanel.GroupCount);
  AssertTrue('the selection was clamped away',
    (FPanel.SelectedGroup < FPanel.GroupCount)
    and ((FPanel.SelectedGroup < 0)
      or (FPanel.SelectedItem < FPanel.ItemCount(FPanel.SelectedGroup))));
end;

initialization
  RegisterClasses([TTyListGroupPanel]);
  RegisterTest(TListGroupEntriesTest);

end.
