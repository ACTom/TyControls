unit test.litetrio.events;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, TypInfo, fpcunit, testregistry,
  tyControls.Splitter, tyControls.StatusBar, tyControls.ToolBar;
type
  TLiteTrioEventsTest = class(TTestCase)
  private
    procedure AssertPub(AClass: TClass; const AName: string);
  published
    procedure TestSplitterEvents;
    procedure TestStatusBarEvents;
    procedure TestToolBarEvents;
  end;
implementation
procedure TLiteTrioEventsTest.AssertPub(AClass: TClass; const AName: string);
begin
  AssertNotNull(AClass.ClassName + ' must publish ' + AName, GetPropInfo(AClass, AName));
end;
procedure TLiteTrioEventsTest.TestSplitterEvents;
begin
  AssertPub(TTySplitter, 'OnClick'); AssertPub(TTySplitter, 'OnMouseDown');
  AssertPub(TTySplitter, 'OnMouseMove'); AssertPub(TTySplitter, 'OnKeyDown');
  AssertPub(TTySplitter, 'OnCanResize'); AssertPub(TTySplitter, 'OnMoved');
end;
procedure TLiteTrioEventsTest.TestStatusBarEvents;
begin
  AssertPub(TTyStatusBar, 'OnClick'); AssertPub(TTyStatusBar, 'OnDblClick');
  AssertPub(TTyStatusBar, 'OnMouseDown'); AssertPub(TTyStatusBar, 'OnResize');
end;
procedure TLiteTrioEventsTest.TestToolBarEvents;
begin
  AssertPub(TTyToolBar, 'OnClick'); AssertPub(TTyToolBar, 'OnMouseDown');
  AssertPub(TTyToolBar, 'OnContextPopup'); AssertPub(TTyToolBar, 'OnResize');
end;
initialization
  RegisterTest(TLiteTrioEventsTest);
end.
