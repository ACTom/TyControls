unit test.tabcontrol.closehover;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Panel, tyControls.TabControl;

type
  { Fresh white-box access subclass for the close-button independent :hover
    state. Kept separate from the locked subclasses in the other tabcontrol test
    units so the existing suite stays untouched. Exposes the protected mouse
    handlers so the tests can drive pointer motion headlessly, plus a Render
    into an offscreen bitmap so the hover-highlight pixel test can read back the
    painted close-glyph band. }
  TTyTabCloseHoverAccess = class(TTyTabControl)
  public
    procedure CallMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure CallMouseLeave;
    procedure RenderInto(ABmp: TBitmap; APPI: Integer);
  end;

  { Tests for the close button (x) having its own independent :hover highlight,
    distinct from whole-tab hover. The pointer being over the x sets a dedicated
    close-hover index (TyTabHoverClose); the pointer being elsewhere in the same
    header sets only the tab hover and clears the close-hover. Geometry pinned
    via Font.PixelsPerInch := 96; control wide enough that 3 short tabs never
    overflow so shifted == unshifted close rects. }
  TTyTabCloseHoverTest = class(TTestCase)
  private
    FForm: TForm;
    FTab: TTyTabCloseHoverAccess;
    procedure AddTabs(ACount: Integer);
    function CloseMid(AIndex: Integer; out CX, CY: Integer): Boolean;
    function HeaderTextMid(AIndex: Integer; out HX, HY: Integer): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaultHoverCloseIsNone;
    procedure TestNotClosableNeverSetsCloseHover;
    procedure TestMoveOverCloseSetsCloseHover;
    procedure TestMoveOverHeaderTextDoesNotSetCloseHover;
    procedure TestMoveFromCloseToTextClearsCloseHover;
    procedure TestMouseLeaveClearsCloseHover;
    procedure TestMoveBelowHeaderBandClearsCloseHover;
    procedure TestCloseHoverTracksDifferentTabs;
    procedure TestCloseHoverHighlightChangesPixels;
  end;

implementation

{ TTyTabCloseHoverAccess }

procedure TTyTabCloseHoverAccess.CallMouseMove(Shift: TShiftState; X, Y: Integer);
begin
  MouseMove(Shift, X, Y);
end;

procedure TTyTabCloseHoverAccess.CallMouseLeave;
begin
  MouseLeave;
end;

procedure TTyTabCloseHoverAccess.RenderInto(ABmp: TBitmap; APPI: Integer);
begin
  RenderTo(ABmp.Canvas, Rect(0, 0, ABmp.Width, ABmp.Height), APPI);
end;

{ TTyTabCloseHoverTest }

procedure TTyTabCloseHoverTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FTab := TTyTabCloseHoverAccess.Create(FForm);
  FTab.Parent := FForm;
  FTab.Font.PixelsPerInch := 96;
  { Wide enough that 3 short tabs never overflow, so shifted == unshifted. }
  FTab.SetBounds(0, 0, 600, 200);
end;

procedure TTyTabCloseHoverTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyTabCloseHoverTest.AddTabs(ACount: Integer);
var
  I: Integer;
begin
  for I := 1 to ACount do
    FTab.AddTab('Tab ' + IntToStr(I));
end;

{ Center of the close (x) rect for a tab. False when there is no close rect
  (e.g. TabsClosable is off, in which case the rect is degenerate). }
function TTyTabCloseHoverTest.CloseMid(AIndex: Integer;
  out CX, CY: Integer): Boolean;
var
  R: TRect;
begin
  R := FTab.TyTabCloseRect(AIndex);
  Result := (R.Right > R.Left) and (R.Bottom > R.Top);
  CX := (R.Left + R.Right) div 2;
  CY := (R.Top + R.Bottom) div 2;
end;

{ A point in the header that is to the LEFT of the close rect (the caption
  text band), so it is unambiguously "tab, not close button". }
function TTyTabCloseHoverTest.HeaderTextMid(AIndex: Integer;
  out HX, HY: Integer): Boolean;
var
  H, C: TRect;
begin
  H := FTab.TyTabHeaderRect(AIndex);
  C := FTab.TyTabCloseRect(AIndex);
  Result := (H.Right > H.Left);
  { Midway between the header's left edge and the close rect's left edge. }
  HX := (H.Left + C.Left) div 2;
  HY := (H.Top + H.Bottom) div 2;
end;

{ (1) A freshly built control reports no close-hover. }
procedure TTyTabCloseHoverTest.TestDefaultHoverCloseIsNone;
begin
  AddTabs(3);
  FTab.TabsClosable := True;
  AssertEquals('default close-hover is -1', -1, FTab.TyTabHoverClose);
end;

{ (2) When TabsClosable is off, hovering anywhere never arms close-hover even
  though the pointer is over where the x would be. }
procedure TTyTabCloseHoverTest.TestNotClosableNeverSetsCloseHover;
var
  H: TRect;
  X, Y: Integer;
begin
  AddTabs(3);
  FTab.TabsClosable := False;
  H := FTab.TyTabHeaderRect(1);
  { Right edge region of the header, where the close glyph sits when closable. }
  X := H.Right - 4;
  Y := (H.Top + H.Bottom) div 2;
  FTab.CallMouseMove([], X, Y);
  AssertEquals('no close-hover when not closable', -1, FTab.TyTabHoverClose);
end;

{ (3) Moving the pointer onto a tab's x arms close-hover for that tab index. }
procedure TTyTabCloseHoverTest.TestMoveOverCloseSetsCloseHover;
var
  CX, CY: Integer;
begin
  AddTabs(3);
  FTab.TabsClosable := True;
  AssertTrue('close rect exists', CloseMid(1, CX, CY));
  FTab.CallMouseMove([], CX, CY);
  AssertEquals('close-hover armed for tab 1', 1, FTab.TyTabHoverClose);
end;

{ (4) Moving onto the caption text (left of the x) sets tab hover but NOT
  close-hover. }
procedure TTyTabCloseHoverTest.TestMoveOverHeaderTextDoesNotSetCloseHover;
var
  HX, HY: Integer;
begin
  AddTabs(3);
  FTab.TabsClosable := True;
  AssertTrue('header exists', HeaderTextMid(1, HX, HY));
  FTab.CallMouseMove([], HX, HY);
  AssertEquals('no close-hover over caption text', -1, FTab.TyTabHoverClose);
end;

{ (5) Sliding from the x to the caption text clears the close-hover. }
procedure TTyTabCloseHoverTest.TestMoveFromCloseToTextClearsCloseHover;
var
  CX, CY, HX, HY: Integer;
begin
  AddTabs(3);
  FTab.TabsClosable := True;
  CloseMid(1, CX, CY);
  FTab.CallMouseMove([], CX, CY);
  AssertEquals('armed first', 1, FTab.TyTabHoverClose);
  HeaderTextMid(1, HX, HY);
  FTab.CallMouseMove([], HX, HY);
  AssertEquals('cleared after sliding to text', -1, FTab.TyTabHoverClose);
end;

{ (6) Leaving the control clears the close-hover. }
procedure TTyTabCloseHoverTest.TestMouseLeaveClearsCloseHover;
var
  CX, CY: Integer;
begin
  AddTabs(3);
  FTab.TabsClosable := True;
  CloseMid(1, CX, CY);
  FTab.CallMouseMove([], CX, CY);
  AssertEquals('armed first', 1, FTab.TyTabHoverClose);
  FTab.CallMouseLeave;
  AssertEquals('cleared on leave', -1, FTab.TyTabHoverClose);
end;

{ (7) Moving below the header band (into the content area) clears close-hover. }
procedure TTyTabCloseHoverTest.TestMoveBelowHeaderBandClearsCloseHover;
var
  CX, CY: Integer;
begin
  AddTabs(3);
  FTab.TabsClosable := True;
  CloseMid(1, CX, CY);
  FTab.CallMouseMove([], CX, CY);
  AssertEquals('armed first', 1, FTab.TyTabHoverClose);
  { Well below the tab strip. }
  FTab.CallMouseMove([], CX, 150);
  AssertEquals('cleared in content area', -1, FTab.TyTabHoverClose);
end;

{ (8) Close-hover follows the pointer between different tabs' close buttons. }
procedure TTyTabCloseHoverTest.TestCloseHoverTracksDifferentTabs;
var
  CX0, CY0, CX2, CY2: Integer;
begin
  AddTabs(3);
  FTab.TabsClosable := True;
  CloseMid(0, CX0, CY0);
  CloseMid(2, CX2, CY2);
  FTab.CallMouseMove([], CX0, CY0);
  AssertEquals('over tab 0 close', 0, FTab.TyTabHoverClose);
  FTab.CallMouseMove([], CX2, CY2);
  AssertEquals('over tab 2 close', 2, FTab.TyTabHoverClose);
end;

{ (9) The painted output of the close-glyph band changes when the x is hovered
  vs not (the independent highlight is visible). Renders once with no hover and
  once with the pointer parked on tab 1's x, then compares the pixels in tab 1's
  close rect; at least one pixel must differ. }
procedure TTyTabCloseHoverTest.TestCloseHoverHighlightChangesPixels;
var
  BmpCold, BmpHot: TBitmap;
  CR: TRect;
  CX, CY, PX, PY: Integer;
  Differs: Boolean;
begin
  AddTabs(3);
  FTab.TabsClosable := True;

  BmpCold := TBitmap.Create;
  BmpHot  := TBitmap.Create;
  try
    BmpCold.SetSize(600, 200);
    BmpHot.SetSize(600, 200);

    { Cold: no hover anywhere. }
    FTab.CallMouseLeave;
    FTab.RenderInto(BmpCold, 96);

    { Hot: pointer parked on tab 1's x. }
    CloseMid(1, CX, CY);
    FTab.CallMouseMove([], CX, CY);
    FTab.RenderInto(BmpHot, 96);

    CR := FTab.TyTabCloseRect(1);
    Differs := False;
    for PY := CR.Top to CR.Bottom - 1 do
      for PX := CR.Left to CR.Right - 1 do
        if BmpCold.Canvas.Pixels[PX, PY] <> BmpHot.Canvas.Pixels[PX, PY] then
        begin
          Differs := True;
          Break;
        end;

    AssertTrue('close-hover highlight changes close-rect pixels', Differs);
  finally
    BmpCold.Free;
    BmpHot.Free;
  end;
end;

initialization
  RegisterTest(TTyTabCloseHoverTest);

end.
