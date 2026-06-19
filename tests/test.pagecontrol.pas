unit test.pagecontrol;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Controller, tyControls.TabSheet, tyControls.PageControl;
type
  TPageControlTest = class(TTestCase)
  private
    FForm: TForm;
    FPC: TTyPageControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddPageParentedAndOwnedByForm;
    procedure TestFirstPageAutoSelected;
    procedure TestActivePageSwitchTogglesVisibility;
    procedure TestActivePageTogglesDesignVisibleFlag;
    procedure TestRemovePageCompactsAndReselects;
    procedure TestCaptionFeedsTabLabel;
    // Controller propagation (ported from test.tabcontrol.pas)
    procedure TestControllerPropagatedOnSetAfterAddPage;
    procedure TestControllerPropagatedOnAddPageAfterSet;
  end;

implementation

procedure TPageControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 320, 240);
  FPC := TTyPageControl.Create(FForm);
  FPC.Parent := FForm;
  FPC.SetBounds(0, 0, 300, 200);
  FPC.Font.PixelsPerInch := 96;
end;

procedure TPageControlTest.TearDown;
begin
  FForm.Free;
end;

procedure TPageControlTest.TestAddPageParentedAndOwnedByForm;
var
  P: TTyTabSheet;
begin
  P := FPC.AddPage('Alpha');
  AssertSame('page parent is the page control', FPC, P.Parent);
  AssertSame('page owner is the form (LookupRoot)', FForm, P.Owner);
  AssertEquals('page count', 1, FPC.PageCount);
end;

procedure TPageControlTest.TestFirstPageAutoSelected;
begin
  FPC.AddPage('Alpha');
  AssertEquals('first page auto-selected', 0, FPC.ActivePageIndex);
end;

procedure TPageControlTest.TestActivePageSwitchTogglesVisibility;
var
  A, B: TTyTabSheet;
begin
  A := FPC.AddPage('A');
  B := FPC.AddPage('B');
  FPC.ActivePageIndex := 1;
  AssertFalse('A hidden', A.Visible);
  AssertTrue('B visible', B.Visible);
end;

procedure TPageControlTest.TestActivePageTogglesDesignVisibleFlag;
var
  A, B: TTyTabSheet;
begin
  A := FPC.AddPage('A');
  B := FPC.AddPage('B');
  FPC.ActivePageIndex := 0;
  AssertFalse('active page A: csNoDesignVisible cleared', csNoDesignVisible in A.ControlStyle);
  AssertTrue('inactive page B: csNoDesignVisible set', csNoDesignVisible in B.ControlStyle);
end;

procedure TPageControlTest.TestRemovePageCompactsAndReselects;
begin
  FPC.AddPage('A');
  FPC.AddPage('B');
  FPC.AddPage('C');
  FPC.ActivePageIndex := 2;
  FPC.RemovePage(2);
  AssertEquals('count after remove', 2, FPC.PageCount);
  AssertEquals('active clamped to last', 1, FPC.ActivePageIndex);
end;

procedure TPageControlTest.TestCaptionFeedsTabLabel;
var
  P: TTyTabSheet;
begin
  P := FPC.AddPage('Hello');
  AssertEquals('tab caption comes from the page', 'Hello', FPC.TabCaption(0));
  P.Caption := 'World';
  AssertEquals('tab caption tracks the page Caption', 'World', FPC.TabCaption(0));
end;

{ Add pages first, then set the page control's Controller -> every existing
  page's Controller updates. (Ported from the old TestControllerPropagatedOnSetAfterAddTab.) }
procedure TPageControlTest.TestControllerPropagatedOnSetAfterAddPage;
var
  Ctl: TTyStyleController;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    FPC.AddPage('One');
    FPC.AddPage('Two');
    FPC.Controller := Ctl;
    AssertSame('Pages[0].Controller = Ctl after set', Ctl, FPC.Pages[0].Controller);
    AssertSame('Pages[1].Controller = Ctl after set', Ctl, FPC.Pages[1].Controller);
  finally
    Ctl.Free;
  end;
end;

{ Set the Controller first, then add a page -> the new page gets it.
  (Ported from the old TestControllerPropagatedOnAddTabAfterSet.) }
procedure TPageControlTest.TestControllerPropagatedOnAddPageAfterSet;
var
  Ctl: TTyStyleController;
  Page: TTyTabSheet;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    FPC.Controller := Ctl;
    Page := FPC.AddPage('New');
    AssertSame('New page gets Controller when AddPage called after set',
      Ctl, Page.Controller);
  finally
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TPageControlTest);
end.
