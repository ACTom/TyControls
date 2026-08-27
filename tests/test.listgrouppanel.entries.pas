unit test.listgrouppanel.entries;
{$mode objfpc}{$H+}
{ The design-time model (QQ-group request): a published, OI-editable, .lfm-streamable
  collection behind the sider, with the code-building API (AddGroup/AddItem/...) kept
  as a delegating facade. The model is NESTED -- Groups, each with its own Items --
  matching how a sider is authored (real-machine feedback: a flat kind-per-row list
  read as "everything is an item"). }
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
    procedure GroupsBuildTheModel;
    procedure LegacyAddersFillTheGroups;
    procedure StreamingRoundTripsTheGroups;
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

procedure TListGroupEntriesTest.GroupsBuildTheModel;
var
  g: TTyListGroup;
begin
  g := FPanel.Groups.Add;
  g.Caption := 'Contacts';
  g.ImageIndex := 3;
  with g.Items.Add do begin Caption := 'Alice'; ImageIndex := 5; end;
  g.Items.Add.Caption := 'Bob';
  g := FPanel.Groups.Add;
  g.Caption := 'Tasks';
  g.Expanded := False;
  g.Items.Add.Caption := 'Report';

  AssertEquals('two groups', 2, FPanel.GroupCount);
  AssertEquals('first group holds its two items', 2, FPanel.ItemCount(0));
  AssertEquals('by caption', 'Bob', FPanel.ItemCaption(0, 1));
  AssertEquals('item icon carried', 5, FPanel.ItemImageIndex(0, 0));
  AssertEquals('second group', 'Tasks', FPanel.GroupCaption[1]);
  AssertTrue('a designer-made group starts open', FPanel.Groups[0].Expanded);
  AssertFalse('an authored-closed group reads closed', FPanel.Expanded[1]);
  AssertEquals('its item', 'Report', FPanel.ItemCaption(1, 0));
end;

procedure TListGroupEntriesTest.LegacyAddersFillTheGroups;
var
  gA: Integer;
begin
  gA := FPanel.AddGroup('Nav', 7);
  FPanel.AddGroup('B');
  FPanel.AddItem(gA, 'Home', 1);
  FPanel.AddItem(gA, 'About');
  AssertEquals('two groups behind the facade', 2, FPanel.Groups.Count);
  AssertEquals('with the icon', 7, FPanel.Groups[0].ImageIndex);
  AssertFalse('the facade keeps its historical closed default', FPanel.Groups[0].Expanded);
  AssertEquals('the items landed inside THEIR group', 2, FPanel.Groups[0].Items.Count);
  AssertEquals('in order', 'About', FPanel.Groups[0].Items[1].Caption);
  AssertEquals('and not in the neighbour', 0, FPanel.Groups[1].Items.Count);
end;

procedure TListGroupEntriesTest.StreamingRoundTripsTheGroups;
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
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);

    DstP := Dst.FindComponent('LGP') as TTyListGroupPanel;
    AssertNotNull('the panel survived', DstP);
    AssertEquals('one group', 1, DstP.GroupCount);
    AssertEquals('its icon', 2, DstP.Groups[0].ImageIndex);
    AssertEquals('the nested items streamed with it', 2, DstP.Groups[0].Items.Count);
    AssertEquals('items intact', 'Home', DstP.ItemCaption(0, 0));
    AssertEquals('item icon intact', 4, DstP.ItemImageIndex(0, 0));
    AssertEquals('default icon not written, restored as -1', -1, DstP.ItemImageIndex(0, 1));
    AssertFalse('the facade-closed flag survived', DstP.Expanded[0]);
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

  // Deleting group B from the collection must not leave a dangling selection.
  FPanel.Groups.Delete(1);
  AssertEquals('one group left', 1, FPanel.GroupCount);
  AssertTrue('the group selection was clamped away',
    (FPanel.SelectedGroup < FPanel.GroupCount)
    and ((FPanel.SelectedGroup < 0)
      or (FPanel.SelectedItem < FPanel.ItemCount(FPanel.SelectedGroup))));

  // And the same through the NESTED level: deleting a selected item bubbles up too.
  FPanel.SelectItem(0, 0);
  FPanel.Groups[0].Items.Delete(0);
  AssertTrue('the item selection was clamped away',
    (FPanel.SelectedGroup < 0) or (FPanel.SelectedItem < FPanel.ItemCount(FPanel.SelectedGroup)));
end;

initialization
  RegisterClasses([TTyListGroupPanel]);
  RegisterTest(TListGroupEntriesTest);

end.
