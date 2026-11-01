unit test.popupmonitor;

{$mode objfpc}{$H+}

{ #148: a drop-down, the balloon hint and the popover are placed against the work area of the
  monitor their anchor is on. They were placed against a screen at 0, 0 the primary monitor's
  height tall: on a monitor left of or above it, or of another size, they opened partly off
  screen or flipped the wrong way. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, fpcunit, testregistry,
  tyControls.Popup, tyControls.BalloonHint, tyControls.Popover, tyControls.Panel;

type
  TPopupMonitorTest = class(TTestCase)
  private
    FForm: TForm;
    function WindowOf(const AClassName: string): TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestADropDownFlipsAtItsMonitorsBottom;
    procedure TestADropDownStaysOnItsMonitorSideways;
    procedure TestABalloonStaysOnItsMonitor;
    procedure TestADropDownAsksForItsMonitor;
    procedure TestABalloonAsksForItsMonitor;
    procedure TestAPopoverAsksForItsMonitor;
  end;

implementation

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

{ A second monitor, right of everything, 400 x 600. }
function FarMonitor(const AAnchorScreen: TRect): TRect;
begin
  Result := Rect(5000, 0, 5400, 600);
end;

procedure TPopupMonitorTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 200);
end;

procedure TPopupMonitorTest.TearDown;
begin
  TyPopupWorkArea := @TyMonitorWorkArea;
  FreeAndNil(FForm);
end;

function TPopupMonitorTest.WindowOf(const AClassName: string): TForm;
var
  i: Integer;
begin
  for i := 0 to Screen.FormCount - 1 do
    if Screen.Forms[i].ClassName = AClassName then Exit(Screen.Forms[i]);
  Result := nil;
end;

procedure TPopupMonitorTest.TestADropDownFlipsAtItsMonitorsBottom;
var
  r: TRect;
begin
  { a monitor above the primary one: its bottom is at y = 0 }
  r := TyPopupRect(Rect(10, -60, 210, -40), 200, 100, Rect(0, -1080, 1920, 0));
  AssertEquals('no room below on its monitor: it opens above', -160, r.Top);
  AssertEquals('ending at the anchor', -60, r.Bottom);
  r := TyPopupRect(Rect(10, -500, 210, -480), 200, 100, Rect(0, -1080, 1920, 0));
  AssertEquals('room below: it drops', -480, r.Top);
end;

procedure TPopupMonitorTest.TestADropDownStaysOnItsMonitorSideways;
var
  r: TRect;
begin
  r := TyPopupRect(Rect(3100, 100, 3180, 120), 300, 200, Rect(1920, 0, 3200, 1000));
  AssertEquals('moved in from the monitor''s right edge', 2900, r.Left);
  AssertEquals('ending at it', 3200, r.Right);
  AssertEquals('still below the anchor', 120, r.Top);
  r := TyPopupRect(Rect(-1270, 100, -1250, 120), 240, 200, Rect(-1280, 0, 0, 1024), True);
  AssertEquals('mirrored, moved in from the left monitor''s left edge', -1280, r.Left);
  AssertEquals('its width kept', -1040, r.Right);
end;

procedure TPopupMonitorTest.TestABalloonStaysOnItsMonitor;
var
  pl: TTyBalloonPlacement;
begin
  pl := TyBalloonPlacement(Rect(3150, 950, 3170, 970), 200, 80, 8, Rect(1920, 0, 3200, 1000));
  AssertFalse('no room below on its monitor: above', pl.Below);
  AssertEquals('moved in from the monitor''s right edge', 3000, pl.Body.Left);
  pl := TyBalloonPlacement(Rect(10, -60, 30, -40), 200, 80, 8, Rect(0, -1080, 1920, 0));
  AssertFalse('a monitor above the primary one: above too', pl.Below);
end;

procedure TPopupMonitorTest.TestADropDownAsksForItsMonitor;
var
  anchor, content: TTyPanel;
  pop: TTyDropdownPopup;
begin
  anchor := TTyPanel.Create(FForm);
  anchor.Parent := FForm;
  anchor.SetBounds(10, 10, 100, 24);
  TyPopupWorkArea := @FarMonitor;
  pop := TTyDropdownPopup.Create;
  content := TTyPanel.Create(nil);
  try
    pop.SetContent(content);
    pop.Popup(anchor, 300, 100);
    AssertTrue('placed on the monitor it was given', pop.Form.Left >= 5000);
    AssertTrue('and in it', pop.Form.Left + pop.Form.Width <= 5400);
    pop.Close;
  finally
    pop.Free;
    content.Free;
  end;
end;

procedure TPopupMonitorTest.TestABalloonAsksForItsMonitor;
var
  b: TTyBalloonHint;
  w: TForm;
begin
  TyPopupWorkArea := @FarMonitor;
  b := TTyBalloonHint.Create(nil);
  try
    b.Title := 'Title';
    b.HideInterval := 0;
    b.ShowAt(Rect(5390, 100, 5398, 110));   // at the monitor's right edge
    w := WindowOf('TTyBalloonWindow');
    AssertNotNull('setup: the balloon is up', w);
    AssertTrue('kept in the monitor it was given', w.Left + w.Width <= 5400);
    AssertTrue('and on it', w.Left >= 5000);
    b.HideHint;
  finally
    b.Free;
  end;
end;

procedure TPopupMonitorTest.TestAPopoverAsksForItsMonitor;
var
  p: TTyPopover;
  w: TForm;
begin
  TyPopupWorkArea := @FarMonitor;
  p := TTyPopover.Create(nil);
  try
    p.ShowAt(Rect(5390, 100, 5398, 110));
    w := WindowOf('TTyPopoverWindow');
    AssertNotNull('setup: the popover is up', w);
    AssertTrue('kept in the monitor it was given', w.Left + w.Width <= 5400);
    AssertTrue('and on it', w.Left >= 5000);
    p.Hide;
  finally
    p.Free;
  end;
end;

initialization
  RegisterTest(TPopupMonitorTest);
end.
