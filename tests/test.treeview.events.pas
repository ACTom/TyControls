unit test.treeview.events;
{ D2: RTTI guard for the published event surface of TTyTreeView.
  AddAssertPub a name here whenever a published event is added or renamed;
  the guard fails on the NEXT build if the source does not match. }
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, TypInfo, fpcunit, testregistry,
  tyControls.TreeView;
type
  TTreeViewEventsTest = class(TTestCase)
  private
    procedure AssertPub(const AName: string);
  published
    procedure TestTreeViewEvents;
  end;
implementation
procedure TTreeViewEventsTest.AssertPub(const AName: string);
begin
  AssertNotNull('TTyTreeView must publish ' + AName,
                GetPropInfo(TTyTreeView, AName));
end;
procedure TTreeViewEventsTest.TestTreeViewEvents;
begin
  { inherited standard set (windowed control) }
  AssertPub('OnClick');
  AssertPub('OnMouseDown');
  AssertPub('OnKeyDown');
  { lifecycle / virtual-engine events }
  AssertPub('OnFreeNode');
  AssertPub('OnInitNode');
  AssertPub('OnInitChildren');
  { expand / collapse }
  AssertPub('OnExpanding');
  AssertPub('OnExpanded');
  AssertPub('OnCollapsing');
  AssertPub('OnCollapsed');
  { selection / focus }
  AssertPub('OnChange');
  AssertPub('OnFocusChanged');
  { interaction }
  AssertPub('OnNodeClick');
  AssertPub('OnNodeDblClick');
  { paint callbacks }
  AssertPub('OnGetText');
  AssertPub('OnGetTextWithType');
  AssertPub('OnGetImageIndex');
  AssertPub('OnPaintText');
  { column/sort events (D2, D3, E1, E3) }
  AssertPub('OnColumnResized');
  AssertPub('OnColumnReorder');
  AssertPub('OnCompareNodes');
  AssertPub('OnHeaderClick');
end;
initialization
  RegisterTest(TTreeViewEventsTest);
end.
