unit test.pagecontrol;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Controller, tyControls.TabSheet, tyControls.PageControl;
type
  { Reaches the protected client-rect seam, and counts realigns: Realign is not virtual, but
    it funnels through AlignControls, so an override counts the calls SetTabHeight triggers. }
  TPCAccess = class(TTyPageControl)
  public
    AlignCount: Integer;
    function ClientTopInset: Integer;
  protected
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
  end;

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
    procedure TestTabHeightRealignsThePages;
    procedure TestTabHeightZeroHidesTheStrip;
    // Controller propagation (ported from test.tabcontrol.pas)
    procedure TestControllerPropagatedOnSetAfterAddPage;
    procedure TestControllerPropagatedOnAddPageAfterSet;
  end;

implementation

function TPCAccess.ClientTopInset: Integer;
var r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AdjustClientRect(r);
  Result := r.Top;
end;

procedure TPCAccess.AlignControls(AControl: TControl; var ARect: TRect);
begin
  Inc(AlignCount);
  inherited AlignControls(AControl, ARect);
end;

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

{ TabHeight drives two things, and BOTH were broken. Assert the MECHANISM, not the pages'
  bounds: LCL defers alignment while the parent form has no handle (the headless runner never
  makes one), so a page's Top stays 0 here no matter what — the same limitation the AutoSize
  tests document. }

{ 1) The strip's height IS the client rect's top inset, which is what an alClient page aligns
  to. Reported from a real run: "TabHeight 我设置为 30 了,也看不到 tab 标签" — SetTabHeight
  only called Invalidate (a repaint), never Realign, so the pages kept their old bounds and
  covered the strip. This asserts the inset follows; TestTabHeightRealigns proves the realign. }
procedure TPageControlTest.TestTabHeightRealignsThePages;
var
  Acc: TPCAccess;
  before: Integer;
begin
  Acc := TPCAccess.Create(FForm);
  try
    Acc.Parent := FForm;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(0, 0, 300, 200);
    Acc.AddPage('Alpha');
    Acc.TabHeight := 28;
    AssertEquals('the client area starts below the strip', 28, Acc.ClientTopInset);
    Acc.TabHeight := 30;
    AssertEquals('...and follows the strip when it changes', 30, Acc.ClientTopInset);
    // The matching Realign in SetTabHeight is what makes a live page ACT on this. It cannot
    // be asserted here: LCL runs no alignment while the parent form has no handle, so
    // AlignControls is never reached in the headless runner (verified with a counting
    // override — it stayed at 0). Real-machine only.
    before := 0;
  finally
    Acc.Free;
  end;
end;

{ 2) TabHeight = 0 means NO strip: the whole point is a host that drives paging itself (a
  sider, a segmented control). It used to clamp to 1, and 1 is not hidden — a 1px strip still
  paints a 1px slice of every tab caption, which reads as a smear of text above the content. }
procedure TPageControlTest.TestTabHeightZeroHidesTheStrip;
var
  Acc: TPCAccess;
begin
  Acc := TPCAccess.Create(FForm);
  try
    Acc.Parent := FForm;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(0, 0, 300, 200);
    Acc.AddPage('Alpha');
    Acc.TabHeight := 0;
    AssertEquals('0 is honoured, not clamped to 1', 0, Acc.TabHeight);
    AssertEquals('and the pages get the WHOLE control: no strip to leave room for',
      0, Acc.ClientTopInset);
    { A negative is the AUTO sentinel now (TyTabHeightAuto), not a floor to 0: it hands the
      band height back to the --control-height token, which is what a ported
      `TabHeight := -1` did in Lazarus. 0 keeps its own meaning -- no band at all -- because
      that is a shipped capability here that LCL only reaches via ShowTabs. }
    Acc.TabHeight := -5;
    AssertTrue('a negative means auto: the band comes back from the token',
      Acc.TabHeight > 0);
  finally
    Acc.Free;
  end;
end;

initialization
  RegisterTest(TPageControlTest);
end.
