unit test.dropbuttons;
{$mode objfpc}{$H+}
{ Headless fpcunit tests for tyControls.DropButtons (TTyDropDownButton split button +
  TTyMenuButton whole-button drop). The live PopUp needs a GUI, so the tests exercise
  the pure/headless seams only:
    - TyDropArrowHit hit-test with concrete numbers + boundary.
    - DoDropDown (via DropDownForTest) fires OnDropDown and records the would-pop
      intent WITHOUT calling the GUI PopUp (no window handle -> DoDropDown stops after
      recording RequestedPopup).
    - Split-button routing: a click in the arrow zone -> DoDropDown, NOT primary
      OnClick; a click in the primary area -> OnClick, NOT DoDropDown.
    - Property round-trip + FreeNotification nils DropDownMenu. }
interface
uses
  Classes, SysUtils, TypInfo, Types, Controls, Graphics, Forms, LCLType, fpcunit, testregistry,
  tyControls.Base, tyControls.Types, tyControls.Menu, tyControls.DropButtons;

type
  { Probe subclass: drives a full headless "press then click" at a device-x. LCL
    synthesises Click AFTER the mouse-up, so a real click is MouseDown(X) then Click;
    the split button reads the down-X in Click to route arrow vs primary. Also
    re-exposes the protected RenderTo so the paint path (DrawContent: arrow + divider)
    runs deterministically without a window handle. }
  TDropDownAccess = class(TTyDropDownButton)
  public
    procedure PressAndClickAt(X: Integer);
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { Probe subclass exposing TTyMenuButton's protected RenderTo. }
  TMenuButtonAccess = class(TTyMenuButton)
  public
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TDropDownButtonTest = class(TTestCase)
  private
    FDropped: Integer;
    FClicked: Integer;
    procedure HandleDropDown(Sender: TObject);
    procedure HandleClick(Sender: TObject);
  published
    procedure TestArrowHitConcreteNumbers;
    procedure TestArrowHitBoundaryAndDegenerate;
    procedure TestTypeKeyReusesButton;
    procedure TestPropertyRoundTrip;
    procedure TestDoDropDownFiresEventAndRecordsIntent;
    procedure TestDoDropDownNoMenuNoIntent;
    procedure TestArrowClickDropsNotPrimaryClick;
    procedure TestPrimaryClickFiresOnClickNotDrop;
    procedure TestFreeNotificationNilsMenu;
    procedure TestPaintSmoke;
  end;

  TMenuButtonTest = class(TTestCase)
  private
    FDropped: Integer;
    FClicked: Integer;
    procedure HandleDropDown(Sender: TObject);
    procedure HandleClick(Sender: TObject);
  published
    procedure TestTypeKeyReusesButton;
    procedure TestClickDropsAndFiresOnClick;
    procedure TestDoDropDownNoMenuNoIntent;
    procedure TestFreeNotificationNilsMenu;
    procedure TestPropertyRoundTrip;
    procedure TestPaintSmoke;
  end;

implementation

procedure TDropDownAccess.PressAndClickAt(X: Integer);
begin
  MouseDown(mbLeft, [], X, 0);   // records the down-X
  Click;                          // native click synthesised after the up; routes on down-X
end;

procedure TDropDownAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TMenuButtonAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ TDropDownButtonTest }

procedure TDropDownButtonTest.HandleDropDown(Sender: TObject);
begin
  Inc(FDropped);
end;

procedure TDropDownButtonTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TDropDownButtonTest.TestArrowHitConcreteNumbers;
begin
  // 100px control, 20px arrow zone => arrow zone is x in [80..99].
  AssertTrue('x=90 is in the 20px arrow zone', TyDropArrowHit(90, 100, 20));
  AssertTrue('x=99 (last px) is in the arrow zone', TyDropArrowHit(99, 100, 20));
  AssertFalse('x=50 (primary area) is NOT an arrow hit', TyDropArrowHit(50, 100, 20));
  AssertFalse('x=79 (just left of the zone) is NOT an arrow hit', TyDropArrowHit(79, 100, 20));
end;

procedure TDropDownButtonTest.TestArrowHitBoundaryAndDegenerate;
begin
  // Boundary: the first arrow pixel is exactly (Width - ArrowWidth).
  AssertTrue('x=80 (first arrow px) is a hit', TyDropArrowHit(80, 100, 20));
  // Degenerate widths never trap a click as an arrow hit.
  AssertFalse('zero arrow width -> never a hit', TyDropArrowHit(50, 100, 0));
  AssertFalse('arrow >= control width -> never a hit', TyDropArrowHit(50, 100, 100));
  AssertFalse('non-positive control width -> never a hit', TyDropArrowHit(0, 0, 18));
end;

procedure TDropDownButtonTest.TestTypeKeyReusesButton;
var B: TTyDropDownButton;
begin
  B := TTyDropDownButton.Create(nil);
  try
    // Reuses the TyButton token (no new .tycss); GetStyleTypeKey is inherited.
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TDropDownButtonTest.TestPropertyRoundTrip;
var
  B: TTyDropDownButton;
  M: TTyPopupMenu;
begin
  B := TTyDropDownButton.Create(nil);
  M := TTyPopupMenu.Create(nil);
  try
    AssertEquals('default arrow width', TyDefaultDropArrowWidth, B.ArrowWidth);
    AssertTrue('DropDownMenu published', IsPublishedProp(B, 'DropDownMenu'));
    AssertTrue('ArrowWidth published', IsPublishedProp(B, 'ArrowWidth'));
    AssertTrue('OnDropDown published', IsPublishedProp(B, 'OnDropDown'));
    B.ArrowWidth := 24;
    AssertEquals('arrow width round-trips', 24, B.ArrowWidth);
    B.DropDownMenu := M;
    AssertSame('menu round-trips', M, B.DropDownMenu);
    B.ArrowWidth := -5;
    AssertEquals('negative arrow width clamps to 0', 0, B.ArrowWidth);
  finally
    B.Free;
    M.Free;
  end;
end;

procedure TDropDownButtonTest.TestDoDropDownFiresEventAndRecordsIntent;
var
  B: TTyDropDownButton;
  M: TTyPopupMenu;
begin
  // With a menu assigned, DoDropDown fires OnDropDown and records that it WOULD pop
  // (RequestedPopup). No window handle here, so it never touches the GUI PopUp.
  FDropped := 0;
  B := TTyDropDownButton.Create(nil);
  M := TTyPopupMenu.Create(nil);
  try
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.DropDownForTest;
    AssertEquals('OnDropDown fired once', 1, FDropped);
    AssertTrue('would-pop recorded (menu present)', B.RequestedPopup);
  finally
    B.Free;
    M.Free;
  end;
end;

procedure TDropDownButtonTest.TestDoDropDownNoMenuNoIntent;
var B: TTyDropDownButton;
begin
  // OnDropDown still fires (a handler may assign a menu), but with none assigned there
  // is nothing to pop, so RequestedPopup stays False.
  FDropped := 0;
  B := TTyDropDownButton.Create(nil);
  try
    B.OnDropDown := @HandleDropDown;
    B.DropDownForTest;
    AssertEquals('OnDropDown still fires without a menu', 1, FDropped);
    AssertFalse('no menu -> no would-pop', B.RequestedPopup);
  finally
    B.Free;
  end;
end;

procedure TDropDownButtonTest.TestArrowClickDropsNotPrimaryClick;
var
  F: TCustomForm;
  B: TDropDownAccess;
  M: TTyPopupMenu;
begin
  // A left click in the arrow zone routes to DoDropDown and NOT the primary OnClick.
  FDropped := 0;
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  M := TTyPopupMenu.Create(F);
  try
    B := TDropDownAccess.Create(F);
    B.Parent := F;
    B.SetBounds(0, 0, 100, 30);
    B.ArrowWidth := 18;   // at 96 PPI the arrow zone is the rightmost 18px: x in [82..99]
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;
    B.PressAndClickAt(95);   // firmly inside the arrow zone
    AssertEquals('arrow click fired the drop', 1, FDropped);
    AssertEquals('arrow click did NOT fire primary OnClick', 0, FClicked);
  finally
    F.Free;
  end;
end;

procedure TDropDownButtonTest.TestPrimaryClickFiresOnClickNotDrop;
var
  F: TCustomForm;
  B: TDropDownAccess;
  M: TTyPopupMenu;
begin
  // A left click in the primary (caption) area fires the normal OnClick and does NOT
  // drop the menu.
  FDropped := 0;
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  M := TTyPopupMenu.Create(F);
  try
    B := TDropDownAccess.Create(F);
    B.Parent := F;
    B.SetBounds(0, 0, 100, 30);
    B.ArrowWidth := 18;
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;
    B.PressAndClickAt(20);   // firmly in the caption area
    AssertEquals('primary click fired OnClick', 1, FClicked);
    AssertEquals('primary click did NOT drop', 0, FDropped);
  finally
    F.Free;
  end;
end;

procedure TDropDownButtonTest.TestFreeNotificationNilsMenu;
var
  B: TTyDropDownButton;
  M: TTyPopupMenu;
begin
  B := TTyDropDownButton.Create(nil);
  try
    M := TTyPopupMenu.Create(nil);
    B.DropDownMenu := M;
    AssertSame('menu wired', M, B.DropDownMenu);
    M.Free;   // FreeNotification must nil the reference
    AssertTrue('freeing the menu nils DropDownMenu', B.DropDownMenu = nil);
  finally
    B.Free;
  end;
end;

procedure TDropDownButtonTest.TestPaintSmoke;
var
  B: TDropDownAccess;
  Bmp: TBitmap;
begin
  // DrawContent must not crash with no menu / no handle: run the paint path directly.
  B := TDropDownAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.Caption := 'Save';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 30);
    // RenderTo -> DrawContent draws the caption + arrow triangle + divider.
    B.DoRenderTo(Bmp.Canvas, Rect(0, 0, 100, 30), 96);
    AssertTrue('drop-down button painted without exception', True);
  finally
    Bmp.Free;
    B.Free;
  end;
end;

{ TMenuButtonTest }

procedure TMenuButtonTest.HandleDropDown(Sender: TObject);
begin
  Inc(FDropped);
end;

procedure TMenuButtonTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TMenuButtonTest.TestTypeKeyReusesButton;
var B: TTyMenuButton;
begin
  B := TTyMenuButton.Create(nil);
  try
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TMenuButtonTest.TestClickDropsAndFiresOnClick;
var
  B: TTyMenuButton;
  M: TTyPopupMenu;
begin
  // The whole button IS the drop: Click routes to DoDropDown (firing OnDropDown and
  // recording the would-pop), AND still runs the inherited OnClick contract.
  FDropped := 0;
  FClicked := 0;
  B := TTyMenuButton.Create(nil);
  M := TTyPopupMenu.Create(nil);
  try
    B.DropDownMenu := M;
    B.OnDropDown := @HandleDropDown;
    B.OnClick := @HandleClick;
    B.Click;
    AssertEquals('click fired the drop', 1, FDropped);
    AssertEquals('click still fired OnClick', 1, FClicked);
    AssertTrue('would-pop recorded', B.RequestedPopup);
  finally
    B.Free;
    M.Free;
  end;
end;

procedure TMenuButtonTest.TestDoDropDownNoMenuNoIntent;
var B: TTyMenuButton;
begin
  FDropped := 0;
  B := TTyMenuButton.Create(nil);
  try
    B.OnDropDown := @HandleDropDown;
    B.DropDownForTest;
    AssertEquals('OnDropDown fires without a menu', 1, FDropped);
    AssertFalse('no menu -> no would-pop', B.RequestedPopup);
  finally
    B.Free;
  end;
end;

procedure TMenuButtonTest.TestFreeNotificationNilsMenu;
var
  B: TTyMenuButton;
  M: TTyPopupMenu;
begin
  B := TTyMenuButton.Create(nil);
  try
    M := TTyPopupMenu.Create(nil);
    B.DropDownMenu := M;
    AssertSame('menu wired', M, B.DropDownMenu);
    M.Free;
    AssertTrue('freeing the menu nils DropDownMenu', B.DropDownMenu = nil);
  finally
    B.Free;
  end;
end;

procedure TMenuButtonTest.TestPropertyRoundTrip;
var
  B: TTyMenuButton;
  M: TTyPopupMenu;
begin
  B := TTyMenuButton.Create(nil);
  M := TTyPopupMenu.Create(nil);
  try
    AssertTrue('DropDownMenu published', IsPublishedProp(B, 'DropDownMenu'));
    AssertTrue('OnDropDown published', IsPublishedProp(B, 'OnDropDown'));
    B.DropDownMenu := M;
    AssertSame('menu round-trips', M, B.DropDownMenu);
  finally
    B.Free;
    M.Free;
  end;
end;

procedure TMenuButtonTest.TestPaintSmoke;
var
  B: TMenuButtonAccess;
  Bmp: TBitmap;
begin
  B := TMenuButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.Caption := 'Options';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 30);
    B.DoRenderTo(Bmp.Canvas, Rect(0, 0, 100, 30), 96);
    AssertTrue('menu button painted without exception', True);
  finally
    Bmp.Free;
    B.Free;
  end;
end;

initialization
  RegisterTest(TDropDownButtonTest);
  RegisterTest(TMenuButtonTest);
end.
