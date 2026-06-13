unit test.tabcontrol.streaming;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  fpcunit, testregistry,
  tyControls.Panel, tyControls.TabControl;

type
  { LFM streaming round-trip + Assign coverage for the Tabs collection. These
    exercise the streaming paths the in-memory collection tests do not touch:
    Tabs.Assign, WriteComponent/ReadComponent caption survival, and the
    page-duplication-on-load defect (ControlCount must stay at N). }
  TTyTabStreamingTest = class(TTestCase)
  private
    function CountPanels(ATab: TTyTabControl): Integer;
  published
    procedure TestTabsAssignCopiesCaptions;
    procedure TestRoundTripPreservesCaptionsAndCount;
    procedure TestRoundTripDoesNotDuplicatePages;
    procedure TestDoubleRoundTripDoesNotCompound;
  end;

implementation

function TTyTabStreamingTest.CountPanels(ATab: TTyTabControl): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ATab.ControlCount - 1 do
    if ATab.Controls[I] is TTyPanel then
      Inc(Result);
end;

{ Tabs.Assign must copy captions without raising EConvertError and without
  spawning extra child panels in the destination. }
procedure TTyTabStreamingTest.TestTabsAssignCopiesCaptions;
var
  Owner: TComponent;
  Src, Dst: TTyTabControl;
begin
  Owner := TComponent.Create(nil);
  try
    Src := TTyTabControl.Create(Owner);
    Src.AddTab('Alpha');
    Src.AddTab('Beta');
    Src.AddTab('Gamma');

    Dst := TTyTabControl.Create(Owner);
    Dst.Tabs := Src.Tabs;  // SetTabs -> FTabs.Assign

    AssertEquals('Dst.TabCount = 3', 3, Dst.TabCount);
    AssertEquals('Dst.Tabs.Count = 3', 3, Dst.Tabs.Count);
    AssertEquals('cap[0]', 'Alpha', Dst.TabCaption(0));
    AssertEquals('cap[1]', 'Beta', Dst.TabCaption(1));
    AssertEquals('cap[2]', 'Gamma', Dst.TabCaption(2));
    AssertEquals('no duplicate panels after Assign', 3, CountPanels(Dst));
  finally
    Owner.Free;
  end;
end;

{ A WriteComponent/ReadComponent cycle keeps TabCount and every displayed
  caption (defect 2: captions were lost on reload). }
procedure TTyTabStreamingTest.TestRoundTripPreservesCaptionsAndCount;
var
  Owner: TComponent;
  Src, Dst: TTyTabControl;
  Ms: TMemoryStream;
begin
  Owner := TComponent.Create(nil);
  Ms := TMemoryStream.Create;
  try
    Src := TTyTabControl.Create(Owner);
    Src.AddTab('One');
    Src.AddTab('Two');
    Src.AddTab('Three');

    Ms.WriteComponent(Src);
    Ms.Position := 0;
    Dst := Ms.ReadComponent(nil) as TTyTabControl;
    try
      AssertEquals('TabCount survives', 3, Dst.TabCount);
      AssertEquals('Tabs.Count survives', 3, Dst.Tabs.Count);
      AssertEquals('displayed cap[0]', 'One', Dst.TabCaption(0));
      AssertEquals('displayed cap[1]', 'Two', Dst.TabCaption(1));
      AssertEquals('displayed cap[2]', 'Three', Dst.TabCaption(2));
      AssertEquals('item cap[0]', 'One', Dst.Tabs.Items[0].Caption);
      AssertEquals('first tab auto-selected', 0, Dst.TabIndex);
    finally
      Dst.Free;
    end;
  finally
    Ms.Free;
    Owner.Free;
  end;
end;

{ A round-trip must not duplicate the owned pages (defect 3: ControlCount went
  3 -> 6). Each item's Page is a live, distinct child panel. }
procedure TTyTabStreamingTest.TestRoundTripDoesNotDuplicatePages;
var
  Owner: TComponent;
  Src, Dst: TTyTabControl;
  Ms: TMemoryStream;
begin
  Owner := TComponent.Create(nil);
  Ms := TMemoryStream.Create;
  try
    Src := TTyTabControl.Create(Owner);
    Src.AddTab('A');
    Src.AddTab('B');
    Src.AddTab('C');

    Ms.WriteComponent(Src);
    Ms.Position := 0;
    Dst := Ms.ReadComponent(nil) as TTyTabControl;
    try
      AssertEquals('exactly N panels after load', 3, CountPanels(Dst));
      AssertEquals('Pages array length = N', 3, Dst.Tabs.Count);
      AssertNotNull('item 0 page wired', Dst.Tabs.Items[0].Page);
      AssertNotNull('item 2 page wired', Dst.Tabs.Items[2].Page);
      AssertSame('Pages[1] = item 1 page', Dst.Pages[1], Dst.Tabs.Items[1].Page);
      AssertTrue('item pages are distinct',
        Dst.Tabs.Items[0].Page <> Dst.Tabs.Items[1].Page);
    finally
      Dst.Free;
    end;
  finally
    Ms.Free;
    Owner.Free;
  end;
end;

{ Two consecutive round-trips must not compound the page count. }
procedure TTyTabStreamingTest.TestDoubleRoundTripDoesNotCompound;
var
  Owner: TComponent;
  Src, Mid, Dst: TTyTabControl;
  Ms: TMemoryStream;
begin
  Owner := TComponent.Create(nil);
  Ms := TMemoryStream.Create;
  try
    Src := TTyTabControl.Create(Owner);
    Src.AddTab('P');
    Src.AddTab('Q');

    Ms.WriteComponent(Src);
    Ms.Position := 0;
    Mid := Ms.ReadComponent(nil) as TTyTabControl;
    try
      Ms.Clear;
      Ms.WriteComponent(Mid);
      Ms.Position := 0;
      Dst := Ms.ReadComponent(nil) as TTyTabControl;
      try
        AssertEquals('TabCount after 2 cycles', 2, Dst.TabCount);
        AssertEquals('no compounding of panels', 2, CountPanels(Dst));
        AssertEquals('cap[0]', 'P', Dst.TabCaption(0));
        AssertEquals('cap[1]', 'Q', Dst.TabCaption(1));
      finally
        Dst.Free;
      end;
    finally
      Mid.Free;
    end;
  finally
    Ms.Free;
    Owner.Free;
  end;
end;

initialization
  RegisterTest(TTyTabStreamingTest);
  RegisterClass(TTyTabControl);
  RegisterClass(TTyPanel);
end.
