unit test.rtl.bars;
{ RTL MIRRORING, part two: the MENUS and the BARS.

  Sibling of test.rtl.pas, which guards phases 0 and 1 (the painter's alignment lever and the
  form controls that already had a left/right switch). This unit guards §3.12 and §3.14 of
  plans/2026-08-04-rtl-mirroring-scope.md: TTyPopupMenu / TTyMenuBar, and TTyStatusBar /
  TTyCoolBar / TTyControlBar.

  The difference from the earlier batch matters, and shapes every test here. Those controls
  were safe to mirror because NONE of them hit-tests internally -- the click lands on the
  whole face. These do. A menu bar answers "which top did I click", a status bar answers
  "which panel is the pointer over" and "is this the size grip", a cool bar answers "is this
  a band's gripper". So the assertions come in pairs: what MOVED, and what the hit test now
  says about the place it moved to. A test that only looked at pixels would pass on exactly
  the bug this whole programme exists to stop.

  The size grip is the sharpest case and gets the most attention below. Its paint and its hit
  test were computed in two separate functions before any of this work -- `W - Scale(3) -
  k*Scale(4)` in RenderTo and `X >= W - grip` in ResizeHitAt -- so it was already one
  copy-paste away from drawing the handle in one corner and resizing from the other. They now
  take the corner from one pure function, and GripInkStaysInsideTheZoneItsHitTestAnswersFor
  pins that: mirror either half alone and it turns red.

  Everything is headless: pure geometry functions where there are any, RenderTo into an
  off-screen bitmap where there are not. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, Menus, Forms, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.StatusBar, tyControls.ControlBar, tyControls.CoolBar,
  tyControls.Menu;

type
  { RenderTo, the hit test and the geometry seams are protected on every one of these. }
  TStatusAccess = class(TTyStatusBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function ResizeAt(X, Y: Integer): Integer;
  end;

  TControlBarAccess2 = class(TTyControlBar)
  public
    procedure ForceLayout;
    { The band box: the client rect minus the strip the painted frame owns. Every geometry
      assertion below is stated relative to it rather than to the bar's edge, so it survives a
      skin that strokes a wider border. }
    function ContentBox: TRect;
    { The grippers are drawn from Paint, straight onto the control's Canvas -- there is no
      RenderTo seam to call -- so the probe builds the painter itself and calls the same
      protected overridable the live Paint calls. }
    procedure DrawGripsTo(ACanvas: TCanvas; AW, AH: Integer);
  end;

  TCoolBarAccess2 = class(TTyCoolBar)
  public
    procedure ForceLayout;
    function ContentBox: TRect;
    function SeamOwner(ACtl: TControl): TControl;
    function BandRect(ACtl: TControl): TRect;
    procedure CallMouseDown(X, Y: Integer);
    procedure CallMouseMove(X, Y: Integer);
    procedure CallMouseUp(X, Y: Integer);
  end;

  TMenuViewAccess2 = class(TTyMenuView)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function RowAtY(AY, APPI: Integer): Integer;
    function RowTopPx(AIndex, APPI: Integer): Integer;
    procedure SetHighlight(AIndex: Integer);
    function Highlighted: Integer;
    procedure Press(AKey: Word);
  end;

  TMenuPopupAccess2 = class(TTyMenuPopup)
  public
    function Bounds(const AAnchor: TRect; AWidth, AHeight, APPI: Integer;
      AToRight, ARtl: Boolean): TRect;
  end;

  TMenuBarAccess2 = class(TTyMenuBar)
  public
    function TopLeftPx(AIndex, APPI: Integer): Integer;
    function TopLeftUnmirroredPx(AIndex, APPI: Integer): Integer;
    function TopWidthPx(AIndex, APPI: Integer): Integer;
    function TopAt(AX, APPI: Integer): Integer;
    function FitPx(APPI: Integer): Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { §3.14, the status bar. Panel tiling is one pure function with two consumers; the grip is
    the pair that used to be written twice. }
  TRtlStatusBarTest = class(TTestCase)
  published
    procedure PanelsTileFromTheRightWhenMirrored;
    procedure MirroredPanelsStillTileFlushAcrossTheWholeBar;
    procedure MirroredPanelsKeepTheirWidthsAndTheirOrder;
    procedure PanelHitTestFollowsTheMirroredTiling;
    procedure PanelTextAndSeparatorAreDrawnInTheMirroredCells;
    procedure SizeGripInkMovesToTheBottomLeftCorner;
    procedure SizeGripHitTestMovesWithIt;
    procedure MirroredGripHandsTheOsTheBottomLeftEdgeCode;
    procedure BottomEdgeCornersAreWindowCornersAndDoNotMirror;
    procedure GripInkStaysInsideTheZoneItsHitTestAnswersFor;
  end;

  { §3.14, the two band hosts. TTyCoolBar overrides the packing, so every claim about the
    base is re-asked of the descendant -- half a fix on this pair is a known failure mode. }
  TRtlBandBarTest = class(TTestCase)
  published
    procedure ControlBarPackFillsFromTheRight;
    procedure MirroredControlBarPackKeepsItsBandBreaks;
    procedure MirroredControlBarPackLeavesNoSeamBetweenNeighbours;
    procedure ControlBarChildrenAreLaidOutRightToLeft;
    procedure ControlBarGripperRailsAreDrawnOnTheMirroredSide;
    procedure ChangingDirectionRelaysTheBands;
    procedure CoolBarPackFillsFromTheRight;
    procedure CoolBarChildrenAreLaidOutRightToLeft;
    procedure VerticalCoolBarChildrenColumnsFillFromTheRight;
    procedure MirroredVerticalBandMovesColumnTowardsTheReadingEnd;
    procedure CoolBarGripperMovesToTheBandsRightWhenMirrored;
    procedure CoolBarGripperHitTestFindsTheMirroredStrip;
    procedure MirroredRejoinSqueezesTheRowAndBringsTheBandBack;
    procedure MirroredResizeDragGrowsTheBandTowardsTheReadingEnd;
    procedure VerticalCoolBarColumnsRunFromTheRight;
    procedure VerticalCoolBarGripperStaysAboveItsBand;
  end;

  { §3.12, the menu bar: one geometry seam, three consumers. }
  TRtlMenuBarTest = class(TTestCase)
  published
    procedure TopCellsPackFromTheRightWhenMirrored;
    procedure TopCellHitTestAgreesWithTheMirroredCells;
    procedure RightJustifiedTopsPackAgainstTheOtherEdge;
    procedure FitWidthIsTheSameWhicheverWayTheBarReads;
    procedure TopCaptionMovesToTheCellsTrailingEdge;
    procedure BarDirectionReachesItsDropdown;
  end;

  { §3.12, the popup: row slots, the cascade direction, and the keys. }
  TRtlPopupMenuTest = class(TTestCase)
  private
    FOpened: Integer;
    FWentBack: Integer;
    procedure OnOpen(Sender: TObject; AIndex: Integer);
    procedure OnBack(Sender: TObject);
    function OneRow(AWithSubmenu: Boolean; const AShortcut: string): TTyMenuRowArray;
  published
    procedure CheckSlotMovesToTheRightHandEndOfTheRow;
    procedure RowCaptionMovesToTheReadingStartSideOfTheRow;
    procedure ShortcutTextMovesToTheLeftHandEnd;
    procedure SubmenuArrowMovesAndTurnsRound;
    procedure BannerStripMovesToTheOtherEndOfThePopup;
    procedure RowHitTestIsVerticalOnlyAndSoCannotDisagree;
    procedure LeftAndRightSwapRolesInAMirroredMenu;
    procedure VerticalKeysAreUntouchedByMirroring;
    procedure MirroredDropdownHangsItsRightEdgeUnderTheAnchor;
    procedure MirroredSubmenuCascadesToTheLeft;
    procedure MirroredSubmenuFlipsBackAtTheScreenEdge;
    procedure ContextMenuTakesItsDirectionFromTheControlItWasRaisedOn;
    procedure ContextMenuAlignmentShiftsTheAnchorTheOtherWayWhenMirrored;
  end;

implementation

const
  cInk = 40;   // how far a channel must lead the other two before a pixel counts as ink

procedure TStatusAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;
function TStatusAccess.ResizeAt(X, Y: Integer): Integer;
begin Result := ResizeHitAt(X, Y); end;

procedure TControlBarAccess2.ForceLayout;
var dummy: TRect;
begin
  dummy := Rect(0, 0, Width, Height);
  AlignControls(nil, dummy);
end;

function TControlBarAccess2.ContentBox: TRect; begin Result := BandContentRect; end;

procedure TControlBarAccess2.DrawGripsTo(ACanvas: TCanvas; AW, AH: Integer);
var
  P: TTyPainter;
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, Rect(0, 0, AW, AH), ppi, IsRightToLeft);
    PaintGrippers(P, CurrentStyle, 1,
      MulDiv(BandHeight, ppi, 96), MulDiv(GripperWidth, ppi, 96),
      MulDiv(BandSpacing, ppi, 96));
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TCoolBarAccess2.ForceLayout;
var dummy: TRect;
begin
  dummy := Rect(0, 0, Width, Height);
  AlignControls(nil, dummy);
end;
function TCoolBarAccess2.ContentBox: TRect;                 begin Result := BandContentRect; end;
function TCoolBarAccess2.SeamOwner(ACtl: TControl): TControl; begin Result := SeamOwnerOf(ACtl); end;
function TCoolBarAccess2.BandRect(ACtl: TControl): TRect; begin Result := BandRectFor(ACtl); end;
procedure TCoolBarAccess2.CallMouseDown(X, Y: Integer);    begin MouseDown(mbLeft, [ssLeft], X, Y); end;
procedure TCoolBarAccess2.CallMouseMove(X, Y: Integer);    begin MouseMove([ssLeft], X, Y); end;
procedure TCoolBarAccess2.CallMouseUp(X, Y: Integer);      begin MouseUp(mbLeft, [], X, Y); end;

procedure TMenuViewAccess2.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;
function TMenuViewAccess2.RowAtY(AY, APPI: Integer): Integer;
begin Result := inherited RowAtY(AY, APPI); end;
function TMenuViewAccess2.RowTopPx(AIndex, APPI: Integer): Integer;
begin Result := RowTop(AIndex, APPI); end;
procedure TMenuViewAccess2.SetHighlight(AIndex: Integer);
begin inherited SetHighlight(AIndex); end;
function TMenuViewAccess2.Highlighted: Integer;
begin Result := Highlight; end;
procedure TMenuViewAccess2.Press(AKey: Word);
var k: Word;
begin k := AKey; KeyDown(k, []); end;

function TMenuPopupAccess2.Bounds(const AAnchor: TRect; AWidth, AHeight, APPI: Integer;
  AToRight, ARtl: Boolean): TRect;
begin Result := ComputeBounds(AAnchor, AWidth, AHeight, APPI, AToRight, ARtl); end;

function TMenuBarAccess2.TopLeftPx(AIndex, APPI: Integer): Integer;
begin Result := TopLeft(AIndex, APPI); end;
function TMenuBarAccess2.TopLeftUnmirroredPx(AIndex, APPI: Integer): Integer;
begin Result := TopLeftUnmirrored(AIndex, APPI); end;
function TMenuBarAccess2.TopWidthPx(AIndex, APPI: Integer): Integer;
begin Result := TopCellWidth(AIndex, APPI); end;
function TMenuBarAccess2.TopAt(AX, APPI: Integer): Integer;
begin Result := TopAtX(AX, APPI); end;
function TMenuBarAccess2.FitPx(APPI: Integer): Integer;
begin Result := FitWidth(APPI); end;
procedure TMenuBarAccess2.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;

{ ---------------------------------------------------------------- helpers -- }

type
  TChannel = (chRed, chGreen, chBlue);

{ Channel DOMINANCE, not colour equality -- the same reasoning test.rtl.pas records: a pf32bit
  TBitmap round-tripped through TBGRABitmap loses the GDI fill, so "is this pixel dark"
  silently matches the whole bitmap. A saturated theme colour leads one channel; black, white
  and every grey lead none.

  A MARGIN rather than test.rtl.pas's "this channel is high AND the others are low", because
  of the size grip: it is three 2px squares drawn with a 1px corner radius, so every pixel of
  it is antialiased and not one is ever saturated. Blending a pure channel over any grey keeps
  that channel ahead of the other two by 255 * coverage, which is what this measures -- and it
  is still false for every grey, which is all the discrimination these fixtures need. }
function Dominant(const P: TBGRAPixel; ACh: TChannel): Boolean;
var mine, o1, o2: Integer;
begin
  case ACh of
    chRed:   begin mine := P.red;   o1 := P.green; o2 := P.blue;  end;
    chGreen: begin mine := P.green; o1 := P.red;   o2 := P.blue;  end;
  else       begin mine := P.blue;  o1 := P.red;   o2 := P.green; end;
  end;
  Result := (mine - o1 > cInk) and (mine - o2 > cInk);
end;

procedure ChannelSpanX(A: TBGRABitmap; ACh: TChannel; out L, R: Integer);
var x, y: Integer;
begin
  L := A.Width; R := -1;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if Dominant(A.GetPixel(x, y), ACh) then
      begin
        if x < L then L := x;
        if x > R then R := x;
      end;
  if R < 0 then L := -1;
end;

{ Ink of one channel in the half-open column band [AX0, AX1), from row AY0 down. AY0 exists for
  the status bar's separators, which share the border colour with the top hairline: skipping
  the first rows is what makes "is there a rule between these two panels" answerable at all. }
function ChannelCount(A: TBGRABitmap; ACh: TChannel; AX0, AX1: Integer;
  AY0: Integer = 0): Integer;
var x, y: Integer;
begin
  Result := 0;
  if AX0 < 0 then AX0 := 0;
  if AX1 > A.Width then AX1 := A.Width;
  if AY0 < 0 then AY0 := 0;
  for y := AY0 to A.Height - 1 do
    for x := AX0 to AX1 - 1 do
      if Dominant(A.GetPixel(x, y), ACh) then Inc(Result);
end;

function NewHost(AW, AH: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := clWhite;
  Result.Canvas.FillRect(0, 0, AW, AH);
end;

function Sz(AW, AH: Integer): TSize;
begin
  Result.cx := AW; Result.cy := AH;
end;

{ ------------------------------------------------------- TRtlStatusBarTest -- }

procedure TRtlStatusBarTest.PanelsTileFromTheRightWhenMirrored;
var
  ltr, rtl: TTyRectArray;
begin
  ltr := TyStatusPanelRects([60, 40, 50], 300, 6, False);
  rtl := TyStatusPanelRects([60, 40, 50], 300, 6, True);
  AssertEquals('left-to-right: panel 0 starts at the padding', 6, ltr[0].Left);
  AssertEquals('mirrored: panel 0 ENDS at the far padding', 300 - 6, rtl[0].Right);
  AssertTrue('mirrored: panel 1 sits entirely left of panel 0', rtl[1].Right <= rtl[0].Left);
  AssertTrue('mirrored: panel 2 sits entirely left of panel 1', rtl[2].Right <= rtl[1].Left);
end;

{ The "last panel runs to the edge" rule exists so the bar has no strip of bare parent in it.
  A mirrored bar owes the same, at the other end, and an odd width is where a reflection that
  is off by one would show. }
procedure TRtlStatusBarTest.MirroredPanelsStillTileFlushAcrossTheWholeBar;
var
  r: TTyRectArray;
  i: Integer;
begin
  r := TyStatusPanelRects([37, 41, 0], 301, 5, True);
  AssertEquals('the first panel reaches the right padding', 301 - 5, r[0].Right);
  for i := 1 to High(r) do
    AssertEquals('each panel starts exactly where the previous one ended',
      r[i - 1].Left, r[i].Right);
  AssertEquals('the last panel reaches the left padding', 5, r[High(r)].Left);
end;

{ The fill panel keeps its slack and the fixed ones keep their widths: mirroring reverses the
  order the cells are laid in, it does not redistribute them. }
procedure TRtlStatusBarTest.MirroredPanelsKeepTheirWidthsAndTheirOrder;
var
  ltr, rtl: TTyRectArray;
  i: Integer;
begin
  ltr := TyStatusPanelRects([60, 0, 50], 300, 6, False);
  rtl := TyStatusPanelRects([60, 0, 50], 300, 6, True);
  for i := 0 to High(ltr) do
    AssertEquals('panel width is unchanged by mirroring',
      ltr[i].Right - ltr[i].Left, rtl[i].Right - rtl[i].Left);
  { Panel 1 is the fill panel; it still absorbs the slack, and it is still panel 1 -- a
    mirrored bar reverses where the cells SIT, not which cell is which. }
  AssertTrue('the fill panel is still the widest one', (rtl[1].Right - rtl[1].Left) > 100);
  AssertEquals('and the fixed panels kept their exact widths', 60, rtl[0].Right - rtl[0].Left);
  AssertEquals('...both of them', 50, rtl[2].Right - rtl[2].Left);
end;

{ The hint hit test (PanelAtPos, and its LCL-spelled alias) reads the SAME pure function the
  paint does. Asserted through the control rather than the function so the wiring is what is
  under test: a call site left unmirrored answers for the panel that used to be there. }
procedure TRtlStatusBarTest.PanelHitTestFollowsTheMirroredTiling;
var
  Form: TForm;
  B: TTyStatusBar;
begin
  Form := TForm.CreateNew(nil);
  try
    B := TTyStatusBar.Create(Form);
    B.Parent := Form;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 300, 22);
    B.Panels.Add.Width := 60;
    B.Panels.Add.Width := 40;
    B.Panels.Add.Width := 50;
    AssertEquals('unmirrored: a click near the left edge is panel 0', 0, B.PanelAtPos(10, 5));
    B.BiDiMode := bdRightToLeft;
    AssertEquals('mirrored: the same click is now the LAST panel',
      B.Panels.Count - 1, B.PanelAtPos(10, 5));
    AssertEquals('mirrored: panel 0 answers near the RIGHT edge', 0, B.PanelAtPos(290, 5));
    AssertEquals('and the LCL-spelled alias agrees', 0, B.GetPanelIndexAt(290, 5));
  finally
    Form.Free;
  end;
end;

{ The other consumer of TyStatusPanelRects: the PAINT. Mirror the hit test and leave this one
  and the bar answers for cells nothing was drawn in -- the same defect as the reverse, and
  invisible to a test that only asked PanelAtPos. Both the panel text and the rule that
  separates the cells are probed, because they are placed by two different expressions. }
procedure TRtlStatusBarTest.PanelTextAndSeparatorAreDrawnInTheMirroredCells;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TStatusAccess;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(300, 22);
  try
    { Green text, RED rules: two channels, so the two placements are told apart. SizeGrip off
      -- it is green too, and it has its own tests. }
    Ctl.LoadThemeCss('TyStatusBar { background: #FFFFFF; color: #00FF00; ' +
      'border-color: #FF0000; border-width: 1px; padding: 0px; }');
    B := TStatusAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 300, 22);
    B.SizeGrip := False;
    B.Panels.Add.Width := 60;
    B.Panels[0].Text := 'Ready';
    B.Panels.Add.Width := 0;      // the fill panel, left blank
    B.BiDiMode := bdRightToLeft;
    B.RenderTo(host.Canvas, Rect(0, 0, 300, 22), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the panel drew its text', l >= 0);
      { Panel 0 mirrors to [234, 294): its text has to be in there, not in [6, 66). }
      AssertTrue('the text is in the mirrored cell', l > 200);
      AssertTrue('...and inside its right-hand edge', r < 300);
      { Both halves. The CELL moved (that is the assertion above) and the text re-aligned
        INSIDE it: a panel's taLeftJustify means the reading start, which mirrored is the
        cell's right-hand edge. Arm the painter and not the geometry, or the geometry and not
        the painter, and the text ends up hugging the wrong side of the right cell. }
      AssertTrue('and the text hugs the mirrored cell''s trailing edge', r > 280);
      { The rule sits on the leading edge of every panel after the first, so mirrored it is on
        panel 1's RIGHT -- i.e. at panel 0's left edge, x = 234. Rows from 3 down, to step
        past the border-coloured top hairline. }
      AssertTrue('the separator moved to the mirrored cell boundary',
        ChannelCount(shot, chRed, 230, 240, 3) > 0);
      AssertEquals('and left nothing at the unmirrored one', 0,
        ChannelCount(shot, chRed, 62, 72, 3));
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ Shared fixture for the grip probes: the grip dots are drawn in the resolved TextColor, so a
  bar with no panels and an empty simple text has exactly one thing on it that is green.

  Rendered at 192 PPI, not 96, and that is not incidental. At 96 the grip is three 2px squares
  with a 1px corner radius -- a circle of diameter two -- whose every pixel comes out about
  12% covered, indistinguishable from stray antialiasing by any threshold that would still
  reject grey. Doubling the PPI doubles the dots and the radius together, so the same geometry
  produces ink an assertion can be built on. }
const
  cGripPPI = 192;
  cGripCss =
    'TyStatusBar { background: #FFFFFF; color: #00FF00; border-color: #FFFFFF; padding: 0px; }';

function RenderGripBar(ARtl: Boolean; AW, AH: Integer): TBGRABitmap;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TStatusAccess;
  host: TBitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(AW, AH);
  try
    Ctl.LoadThemeCss(cGripCss);
    B := TStatusAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := cGripPPI;
    B.SetBounds(0, 0, AW, AH);
    B.SimplePanel := True;
    B.SimpleText := '';
    B.SizeGrip := True;
    if ARtl then B.BiDiMode := bdRightToLeft;
    B.RenderTo(host.Canvas, Rect(0, 0, AW, AH), cGripPPI);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlStatusBarTest.SizeGripInkMovesToTheBottomLeftCorner;
var
  ltr, rtl: TBGRABitmap;
  ll, lr, rl, rr: Integer;
begin
  ltr := RenderGripBar(False, 400, 44);
  rtl := RenderGripBar(True, 400, 44);
  try
    ChannelSpanX(ltr, chGreen, ll, lr);
    ChannelSpanX(rtl, chGreen, rl, rr);
    AssertTrue('the unmirrored grip drew something', ll >= 0);
    AssertTrue('the mirrored grip drew something', rl >= 0);
    AssertTrue('unmirrored, the grip is against the right edge', lr > 400 - 8);
    AssertTrue('mirrored, the grip is against the LEFT edge', rl < 8);
    AssertTrue('and has left the right edge entirely', rr < 200);
    AssertTrue('...as the unmirrored one has left the left edge', ll > 200);
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

{ The half that was written in a different function. Probed at a point that is inside the grip
  corner and outside the bottom-edge strip, so only the grip branch can answer. }
procedure TRtlStatusBarTest.SizeGripHitTestMovesWithIt;
var
  Form: TForm;
  B: TStatusAccess;
begin
  Form := TForm.CreateNew(nil);
  try
    B := TStatusAccess.Create(Form);
    B.Parent := Form;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 200, 22);
    { The grip zone is 18 device px at 96 PPI, the bottom-edge strip 5: (12, 10) is inside a
      LEFT grip corner and outside every edge strip, (190, 10) likewise for a RIGHT one. }
    AssertTrue('unmirrored: the right corner is the grip', B.ResizeAt(190, 10) <> 0);
    AssertEquals('unmirrored: the left corner is nothing at all', 0, B.ResizeAt(12, 10));
    B.BiDiMode := bdRightToLeft;
    AssertTrue('mirrored: the LEFT corner is the grip', B.ResizeAt(12, 10) <> 0);
    AssertEquals('mirrored: the right corner is nothing at all', 0, B.ResizeAt(190, 10));
  finally
    Form.Free;
  end;
end;

{ The grip does not merely move: the drag it hands the OS has to name the corner it is now in,
  or the window resizes from the far side of itself. }
procedure TRtlStatusBarTest.MirroredGripHandsTheOsTheBottomLeftEdgeCode;
var
  Form: TForm;
  B: TStatusAccess;
  ltrCode, rtlCode: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    B := TStatusAccess.Create(Form);
    B.Parent := Form;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 200, 22);
    ltrCode := B.ResizeAt(190, 10);
    B.BiDiMode := bdRightToLeft;
    rtlCode := B.ResizeAt(12, 10);
    { 16 = HTBOTTOMLEFT, 17 = HTBOTTOMRIGHT (winuser.h), the codes TyStartNativeResize speaks. }
    AssertEquals('unmirrored the grip is the bottom-RIGHT window corner', 17, ltrCode);
    AssertEquals('mirrored it is the bottom-LEFT one', 16, rtlCode);
  finally
    Form.Free;
  end;
end;

{ A window's corners are not a reading direction. The bottom-edge strip's two ends name real
  window corners and must keep naming them, mirrored or not -- flipping those as well would
  make a right-to-left form resize from the wrong corner along its whole bottom edge. }
procedure TRtlStatusBarTest.BottomEdgeCornersAreWindowCornersAndDoNotMirror;
var
  Form: TForm;
  B: TStatusAccess;
begin
  Form := TForm.CreateNew(nil);
  try
    B := TStatusAccess.Create(Form);
    B.Parent := Form;
    B.Font.PixelsPerInch := 96;
    B.SetBounds(0, 0, 200, 22);
    B.SizeGrip := False;         // the grip would otherwise own one of the two corners
    B.BiDiMode := bdRightToLeft;
    AssertEquals('the far LEFT of the bottom edge is still HTBOTTOMLEFT', 16, B.ResizeAt(1, 21));
    AssertEquals('the far RIGHT of it is still HTBOTTOMRIGHT', 17, B.ResizeAt(199, 21));
    AssertEquals('and the middle is still the plain bottom edge', 15, B.ResizeAt(100, 21));
  finally
    Form.Free;
  end;
end;

{ THE guard this control needed. Paint and hit test now take the corner from one function, and
  what that buys is exactly this: every drawn dot lies inside the box ResizeHitAt answers for.
  Mirror the paint and leave the hit test (or the reverse) and the ink is in one corner while
  the box is in the other, so this fails -- which no assertion about "the grip is on the left"
  would, because each half satisfies its own. }
procedure TRtlStatusBarTest.GripInkStaysInsideTheZoneItsHitTestAnswersFor;
var
  shot: TBGRABitmap;
  box: TRect;
  l, r: Integer;
  rtl: Boolean;
begin
  for rtl := False to True do
  begin
    shot := RenderGripBar(rtl, 400, 44);
    try
      ChannelSpanX(shot, chGreen, l, r);
      box := TyStatusGripRect(400, 44, TyStatusGripZonePx(cGripPPI), rtl);
      AssertTrue('the grip drew something', l >= 0);
      AssertTrue('every grip pixel is inside the corner the hit test answers for',
        (l >= box.Left) and (r < box.Right));
      { ...and the box is not simply the whole bar. Without this the assertion above is
        satisfied by a hit test that says yes everywhere. }
      AssertTrue('and that corner is a corner, not the whole bar',
        (box.Right - box.Left) < 400 div 2);
    finally
      shot.Free;
    end;
  end;
end;

{ --------------------------------------------------------- TRtlBandBarTest -- }

procedure TRtlBandBarTest.ControlBarPackFillsFromTheRight;
var
  ltr, rtl: TTyRectArray;
begin
  ltr := TyControlBarPack([Sz(80, 20), Sz(60, 20)], 300, 26, 12, 4, False);
  rtl := TyControlBarPack([Sz(80, 20), Sz(60, 20)], 300, 26, 12, 4, True);
  AssertEquals('left-to-right: the first child starts past the gripper', 12, ltr[0].Left);
  AssertEquals('mirrored: the first child ENDS a gripper in from the right edge',
    300 - 12, rtl[0].Right);
  AssertEquals('mirrored: it keeps its width', 80, rtl[0].Right - rtl[0].Left);
  AssertTrue('mirrored: the second child follows it leftwards', rtl[1].Right <= rtl[0].Left);
  AssertEquals('bands are not mirrored -- both are still on row 0', rtl[0].Top, rtl[1].Top);
end;

{ The wrap rule inverts with the layout: what overflowed the right end now overflows the left
  one, and it must break onto a new band at exactly the same child. Asserted as "the same
  children share a band", which is the thing a user sees, rather than as coordinates. }
procedure TRtlBandBarTest.MirroredControlBarPackKeepsItsBandBreaks;
var
  ltr, rtl: TTyRectArray;
  i: Integer;
begin
  { 200 avail, 12 gripper, 4 spacing: 120 + 4 + 60 = 184 fits in 188; the third does not. }
  ltr := TyControlBarPack([Sz(120, 20), Sz(60, 20), Sz(60, 20)], 200, 26, 12, 4, False);
  rtl := TyControlBarPack([Sz(120, 20), Sz(60, 20), Sz(60, 20)], 200, 26, 12, 4, True);
  AssertEquals('the third child wrapped in the unmirrored layout', ltr[0].Bottom + 4, ltr[2].Top);
  for i := 0 to 2 do
    AssertEquals('mirroring changes no child''s band', ltr[i].Top, rtl[i].Top);
end;

{ A reflection of a row with a 4px gap in it has a 4px gap in it. Stated as a test because the
  obvious alternative -- packing backwards from contentRight -- is where the gap becomes 3 or
  5, and a one-pixel drift between two toolbars is invisible in review. }
procedure TRtlBandBarTest.MirroredControlBarPackLeavesNoSeamBetweenNeighbours;
var
  rtl: TTyRectArray;
begin
  rtl := TyControlBarPack([Sz(81, 20), Sz(57, 20)], 301, 26, 11, 5, True);
  AssertEquals('the gap between neighbours is exactly the spacing', 5,
    rtl[0].Left - rtl[1].Right);
  AssertEquals('the first child still ends a gripper in from the edge', 301 - 11, rtl[0].Right);
  AssertEquals('both widths survive the odd numbers (first)', 81, rtl[0].Right - rtl[0].Left);
  AssertEquals('both widths survive the odd numbers (second)', 57, rtl[1].Right - rtl[1].Left);
end;

function MakeChild(AParent: TWinControl; AW, AH: Integer): TControl;
var c: TTyPanel;
begin
  c := TTyPanel.Create(AParent);
  c.Parent := AParent;
  c.SetBounds(0, 0, AW, AH);
  Result := c;
end;

procedure TRtlBandBarTest.ControlBarChildrenAreLaidOutRightToLeft;
var
  Form: TForm;
  CB: TControlBarAccess2;
  a, b: TControl;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TControlBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 300, 60);
    CB.GripperWidth := 12;
    CB.BandSpacing := 4;
    CB.BiDiMode := bdRightToLeft;
    a := MakeChild(CB, 80, 20);
    b := MakeChild(CB, 60, 20);
    CB.ForceLayout;
    AssertEquals('the first child ends a gripper in from the content''s right edge',
      CB.ContentBox.Right - 12, a.Left + a.Width);
    AssertTrue('the second child is entirely left of the first', b.Left + b.Width <= a.Left);
  finally
    Form.Free;
  end;
end;

{ The gripper COLUMN is drawn by a different expression from the one that indents the children
  past it, so it gets its own probe: a bar whose children mirrored and whose grip rails did not
  has every band overlapping its own handle. Rails are two 1px lines centred in the column, and
  the probe bands stop short of the frame edge so a themed border cannot be mistaken for one. }
procedure TRtlBandBarTest.ControlBarGripperRailsAreDrawnOnTheMirroredSide;
var
  Ctl: TTyStyleController;
  Form: TForm;
  CB: TControlBarAccess2;
  host: TBitmap;
  shot: TBGRABitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(300, 40);
  try
    Ctl.LoadThemeCss('TyControlBar { background: #FFFFFF; color: #FFFFFF; ' +
      'border-color: #00FF00; border-width: 0px; padding: 0px; }');
    CB := TControlBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Controller := Ctl;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 300, 40);
    CB.GripperWidth := 12;
    CB.BiDiMode := bdRightToLeft;
    MakeChild(CB, 80, 20);
    CB.ForceLayout;
    CB.DrawGripsTo(host.Canvas, 300, 40);
    shot := TBGRABitmap.Create(host);
    try
      { The rails sit around the middle of the 12px column: [0,12) unmirrored, [288,300)
        mirrored. Probed 2px in from either frame edge. }
      AssertTrue('the grip rails are in the mirrored column',
        ChannelCount(shot, chGreen, 280, 298) > 0);
      AssertEquals('and nothing is left in the unmirrored one', 0,
        ChannelCount(shot, chGreen, 2, 20));
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ LCL's own CM_BIDIMODECHANGED invalidates and calls AdjustSize; neither re-runs a layout done
  with SetBounds. Without the handler the gripper column would change ends and every child
  would stay where it was -- the same hole the check/radio groups had to plug in phase 1. }
procedure TRtlBandBarTest.ChangingDirectionRelaysTheBands;
var
  Form: TForm;
  CB: TControlBarAccess2;
  a: TControl;
  before: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TControlBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 300, 60);
    CB.GripperWidth := 12;
    a := MakeChild(CB, 80, 20);
    CB.ForceLayout;
    before := a.Left;
    { Measured from the CONTENT box: the bands sit inside the stroke the frame paints, not on
      top of it. Stated as a bare 12 this pinned the pre-fix layout, in which a band overwrote
      the bar's own border. }
    AssertEquals('laid out from the left to begin with', CB.ContentBox.Left + 12, before);
    CB.BiDiMode := bdRightToLeft;
    AssertTrue('changing direction moved the child, not merely the paint', a.Left <> before);
    AssertEquals('and it moved to the mirrored position', CB.ContentBox.Right - 12 - 80, a.Left);
  finally
    Form.Free;
  end;
end;

{ TTyCoolBar packs with its OWN function, not the base's -- one gripper per band rather than
  one per row -- so every claim above is re-asked here. A fix that lands on the base and not
  the override is half a fix. }
procedure TRtlBandBarTest.CoolBarPackFillsFromTheRight;
var
  ltr, rtl: TTyRectArray;
begin
  ltr := TyCoolBarPack([Sz(80, 20), Sz(60, 20)], [False, False], [0, 0], 300, 26, 10, 4, False);
  rtl := TyCoolBarPack([Sz(80, 20), Sz(60, 20)], [False, False], [0, 0], 300, 26, 10, 4, True);
  AssertEquals('left-to-right: band 0 starts past its own gripper', 10, ltr[0].Left);
  AssertEquals('mirrored: band 0 ends a gripper in from the right edge', 300 - 10, rtl[0].Right);
  AssertTrue('mirrored: band 1 follows leftwards', rtl[1].Right <= rtl[0].Left);
  AssertEquals('mirrored: band 1 keeps its width', 60, rtl[1].Right - rtl[1].Left);
  AssertEquals('and its own gripper still fits between them', 10 + 4,
    rtl[0].Left - rtl[1].Right);
end;

{ The same claim at the CONTROL level, where the descendant's own PackBands is what runs. The
  pure-function test above cannot see a PackBands override that forgot to pass the direction
  through -- and that override is the whole difference between the two band hosts. }
procedure TRtlBandBarTest.CoolBarChildrenAreLaidOutRightToLeft;
var
  Form: TForm;
  CB: TCoolBarAccess2;
  a, b: TControl;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TCoolBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 300, 60);
    CB.GripperWidth := 10;
    CB.BandSpacing := 3;
    CB.BiDiMode := bdRightToLeft;
    a := MakeChild(CB, 80, 20);
    b := MakeChild(CB, 60, 20);
    CB.ForceLayout;
    AssertEquals('the first band ends a gripper in from the content''s right edge',
      CB.ContentBox.Right - 10, a.Left + a.Width);
    AssertTrue('the second band is entirely left of the first', b.Left + b.Width <= a.Left);
    AssertTrue('with room for its own gripper between them',
      a.Left - (b.Left + b.Width) >= 10);
  finally
    Form.Free;
  end;
end;

{ Vertical, at the control level: the packer's cross-axis extent has to reach it from
  PackBands, which is the one place that knows the bar's width. Asserted as "the first column
  reaches the right edge", which needs no knowledge of the themed band thickness. }
procedure TRtlBandBarTest.VerticalCoolBarChildrenColumnsFillFromTheRight;
var
  Form: TForm;
  CB: TCoolBarAccess2;
  a, b: TControl;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TCoolBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 300, 120);
    CB.GripperWidth := 10;
    CB.BandSpacing := 3;
    CB.Vertical := True;
    CB.BiDiMode := bdRightToLeft;
    a := MakeChild(CB, 24, 60);
    b := MakeChild(CB, 24, 60);
    CB.ForceLayout;
    AssertEquals('the first column ends at the content''s right edge',
      CB.ContentBox.Right, a.Left + a.Width);
    AssertTrue('and the second column is left of it', b.Left + b.Width <= a.Left);
  finally
    Form.Free;
  end;
end;

{ Moving a band between COLUMNS is a sideways drag, so mirroring inverts which way "the next
  column" is. Another sign with no static symptom: the bar renders correctly and dragging a
  band towards the reading end pushes it the wrong way. }
procedure TRtlBandBarTest.MirroredVerticalBandMovesColumnTowardsTheReadingEnd;
var
  Form: TForm;
  CB: TCoolBarAccess2;
  b: TControl;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TCoolBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 300, 120);
    CB.GripperWidth := 10;
    CB.BandHeight := 20;      // explicit: the column step is BandHeight + BandSpacing = 24
    CB.BandSpacing := 4;
    CB.Vertical := True;
    CB.BiDiMode := bdRightToLeft;
    b := TTyPanel.Create(CB);
    b.Parent := CB;
    b.SetBounds(280, 10, 20, 60);   // column 0 of a mirrored bar: hard against the right edge
    AssertFalse('the band starts on the column it was packed into', CB.BandBreak(b));
    CB.CallMouseDown(290, 5);       // the gripper, which sits above a vertical band
    CB.CallMouseMove(200, 5);       // ...dragged towards the reading end, i.e. leftwards
    CB.CallMouseUp(200, 5);
    AssertTrue('dragging leftwards on a mirrored vertical bar moves the band ONWARDS',
      CB.BandBreak(b));
  finally
    Form.Free;
  end;
end;

{ BandRectFor is the single source: PaintGrippers draws what it returns and BandAtPoint hit-
  tests what it returns. So this one assertion covers both sides -- which is the whole reason
  it is derived rather than restated in each. }
procedure TRtlBandBarTest.CoolBarGripperMovesToTheBandsRightWhenMirrored;
var
  Form: TForm;
  CB: TCoolBarAccess2;
  b: TControl;
  r: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TCoolBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 200, 60);
    CB.BiDiMode := bdRightToLeft;
    b := TTyPanel.Create(CB);
    b.Parent := CB;
    { Where the mirrored packer puts it: content.Right - gripper - width. }
    b.SetBounds(CB.ContentBox.Right - 10 - 80, CB.ContentBox.Top, 80, 30);
    r := CB.BandRect(b);
    AssertEquals('the gripper starts where the band ends', CB.ContentBox.Right - 10, r.Left);
    AssertEquals('and runs a grip width to its right, stopping at the frame',
      CB.ContentBox.Right, r.Right);
    AssertEquals('band top', CB.ContentBox.Top, r.Top);
    AssertEquals('band bottom', CB.ContentBox.Top + 30, r.Bottom);
  finally
    Form.Free;
  end;
end;

{ Two mirrored bands sharing a row: band0 hard against the reading start (the right edge),
  band1 to its left. Band1's gripper is on band1's RIGHT -- i.e. it is the SEAM between the two
  -- so dragging it is what resizes band0.

  Both tests below used to use a SINGLE band and drag its own gripper, expecting that band to
  resize. That pinned the defect: a lone band opens its row, so under the reference semantics
  its gripper is a move handle, not a resize handle. }
procedure MakeMirroredPair(CB: TCoolBarAccess2; out b0, b1: TControl);
var box: TRect;
begin
  box := CB.ContentBox;
  b0 := TTyPanel.Create(CB);
  b0.Parent := CB;
  b0.SetBounds(box.Right - 10 - 80, box.Top, 80, 30);      // mirrored first band
  b1 := TTyPanel.Create(CB);
  b1.Parent := CB;
  b1.SetBounds(box.Right - 10 - 80 - 4 - 60, box.Top, 60, 30);   // and the one left of it
  CB.SetBandWidth(b0, 80);
  CB.SetBandWidth(b1, 60);
end;

{ The hit test, reached the way a user reaches it: press on the mirrored strip and drag. If
  BandAtPoint were still looking left of the child, the press would find no band and the drag
  would do nothing at all. }
procedure TRtlBandBarTest.CoolBarGripperHitTestFindsTheMirroredStrip;
var
  Form: TForm;
  CB: TCoolBarAccess2;
  b0, b1: TControl;
  gx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TCoolBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 200, 60);
    CB.BiDiMode := bdRightToLeft;
    MakeMirroredPair(CB, b0, b1);
    AssertSame('precondition: band0 is the seam under band1''s gripper', b0, CB.SeamOwner(b1));
    { Band1's gripper is the strip immediately RIGHT of band1 -- nowhere near the left-hand
      strip an unmirrored hit test would look at. }
    gx := b1.Left + b1.Width + 5;
    CB.CallMouseDown(gx, CB.ContentBox.Top + 15);
    CB.CallMouseMove(gx - 50, CB.ContentBox.Top + 15);
    CB.CallMouseUp(gx - 50, CB.ContentBox.Top + 15);
    AssertTrue('a press on the mirrored gripper started a real drag',
      CB.GetBandWidth(b0) <> 80);
  finally
    Form.Free;
  end;
end;

{ The drag SIGN -- the failure mode no static render can catch (§5 item 2): the screenshot is
  perfect and the band shrinks when you pull it open. The seam owner grows AWAY from the
  gripper, and mirrored the gripper is on the dragged band's right, so dragging LEFT is what
  widens it. }
procedure TRtlBandBarTest.MirroredResizeDragGrowsTheBandTowardsTheReadingEnd;
var
  Form: TForm;
  CB: TCoolBarAccess2;
  b0, b1: TControl;
  gx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TCoolBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 200, 60);
    CB.BiDiMode := bdRightToLeft;
    MakeMirroredPair(CB, b0, b1);
    gx := b1.Left + b1.Width + 5;
    CB.CallMouseDown(gx, CB.ContentBox.Top + 15);
    CB.CallMouseMove(gx - 50, CB.ContentBox.Top + 15);   // 50 px towards the reading end
    CB.CallMouseUp(gx - 50, CB.ContentBox.Top + 15);
    AssertEquals('dragging away from the mirrored gripper grew the SEAM OWNER by the delta',
      130, CB.GetBandWidth(b0));
    AssertEquals('and the grabbed band was not resized in isolation', 60,
      CB.GetBandWidth(b1));
  finally
    Form.Free;
  end;
end;

{ REJOINING a full row, mirrored. A band that overflowed onto row 1 is dragged back UP, and the
  row has to give up the width to take it. Rows are the one axis mirroring does NOT touch --
  top-to-bottom is not a reading direction -- so what this pins is that the mirrored geometry
  still finds the right row, the right gripper strip and the right band to squeeze. The squeeze
  itself is arithmetic on extents and is direction-agnostic by construction; if it were not,
  b0's width would come out wrong here and right in the unmirrored test. }
procedure TRtlBandBarTest.MirroredRejoinSqueezesTheRowAndBringsTheBandBack;
var
  Form: TForm;
  CB: TCoolBarAccess2;
  b0, b1: TControl;
  box: TRect;
  step, avail, w0, deficit: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TCoolBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 300, 120);
    CB.BiDiMode := bdRightToLeft;
    CB.BandHeight := 26;
    CB.BandSpacing := 3;
    CB.GripperWidth := 10;
    box := CB.ContentBox;
    step := CB.BandHeight + CB.BandSpacing;
    avail := box.Right - box.Left;
    w0 := avail - 40;
    { Mirrored, a row fills from the RIGHT and each gripper is the strip immediately right of
      its band. b1 overflowed onto row 1 and opens it. }
    b0 := TTyPanel.Create(CB);
    b0.Parent := CB;
    b0.SetBounds(box.Right - 10 - w0, box.Top, w0, 26);
    b1 := TTyPanel.Create(CB);
    b1.Parent := CB;
    b1.SetBounds(box.Right - 10 - 60, box.Top + step, 60, 26);
    CB.SetBandWidth(b0, w0);
    CB.SetBandWidth(b1, 60);
    deficit := (10 + w0) + CB.BandSpacing + (10 + 60) - avail;
    AssertTrue('precondition: the mirrored row really is over-full', deficit > 0);
    AssertFalse('precondition: b1 came down by overflow, not by Break', CB.BandBreak(b1));

    { Grab b1's gripper -- on its RIGHT once mirrored -- and drag straight up onto row 0. }
    CB.CallMouseDown(b1.Left + 60 + 5, box.Top + step + 13);
    CB.CallMouseMove(b0.Left + 5, box.Top + 13);
    CB.CallMouseUp(b0.Left + 5, box.Top + 13);

    AssertEquals('the mirrored row gave up exactly the room the band needed', w0 - deficit,
      CB.GetBandWidth(b0));
    AssertFalse('and the rejoined band does not break its new row', CB.BandBreak(b1));
  finally
    Form.Free;
  end;
end;

{ Turned on its side the mirrored axis is the one AAvail is NOT describing, which is why the
  vertical packer needs the width told to it separately. Columns reverse; nothing else does. }
procedure TRtlBandBarTest.VerticalCoolBarColumnsRunFromTheRight;
var
  ltr, rtl: TTyRectArray;
begin
  { AAvail is the column RUN (the height); 30 + 8 + 30 + 8 > 60 so the second band starts a
    new column. ACrossExtent is the bar's width. }
  ltr := TyCoolBarPackVertical([Sz(24, 30), Sz(24, 30)], [False, False], [0, 0],
    60, 24, 8, 4, False, 200);
  rtl := TyCoolBarPackVertical([Sz(24, 30), Sz(24, 30)], [False, False], [0, 0],
    60, 24, 8, 4, True, 200);
  AssertEquals('left-to-right: the first column starts at x = 0', 0, ltr[0].Left);
  AssertEquals('mirrored: the first column ENDS at the right edge', 200, rtl[0].Right);
  AssertTrue('mirrored: the second column is left of the first', rtl[1].Right <= rtl[0].Left);
  AssertEquals('column thickness is unchanged', 24, rtl[0].Right - rtl[0].Left);
end;

{ Up is not a reading direction. A mirrored vertical rebar moves its columns and leaves every
  gripper exactly where it was, above its own band. }
procedure TRtlBandBarTest.VerticalCoolBarGripperStaysAboveItsBand;
var
  Form: TForm;
  CB: TCoolBarAccess2;
  b: TControl;
  r: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    CB := TCoolBarAccess2.Create(Form);
    CB.Parent := Form;
    CB.Font.PixelsPerInch := 96;
    CB.SetBounds(0, 0, 200, 120);
    CB.Vertical := True;
    CB.BiDiMode := bdRightToLeft;
    b := TTyPanel.Create(CB);
    b.Parent := CB;
    b.SetBounds(CB.ContentBox.Right - 24, CB.ContentBox.Top + 10, 24, 60);
    r := CB.BandRect(b);
    AssertEquals('the grip still ends where the band begins',
      CB.ContentBox.Top + 10, r.Bottom);
    AssertEquals('and still starts a grip height above it, inside the frame',
      CB.ContentBox.Top, r.Top);
    AssertEquals('spanning the band, on whichever side of the bar it landed', b.Left, r.Left);
  finally
    Form.Free;
  end;
end;

{ --------------------------------------------------------- TRtlMenuBarTest -- }

function MakeBar(AOwner: TComponent; const ACaptions: array of string;
  ARightJustifyFrom: Integer): TMenuBarAccess2;
var
  mm: TMainMenu;
  mi: TMenuItem;
  i: Integer;
begin
  mm := TMainMenu.Create(AOwner);
  for i := 0 to High(ACaptions) do
  begin
    mi := TMenuItem.Create(mm);
    mi.Caption := ACaptions[i];
    if (ARightJustifyFrom >= 0) and (i >= ARightJustifyFrom) then mi.RightJustify := True;
    mm.Items.Add(mi);
  end;
  Result := TMenuBarAccess2.Create(AOwner);
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 24);
  Result.Menu := mm;
end;

procedure TRtlMenuBarTest.TopCellsPackFromTheRightWhenMirrored;
var
  Form: TForm;
  bar: TMenuBarAccess2;
  ltr0, w0, l0, l1: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    bar := MakeBar(Form, ['File', 'Edit', 'View'], -1);
    bar.Parent := Form;
    ltr0 := bar.TopLeftPx(0, 96);
    w0 := bar.TopWidthPx(0, 96);
    AssertTrue('the first top has a real width', w0 > 0);
    AssertTrue('and unmirrored it starts near the left edge', ltr0 < 40);

    bar.BiDiMode := bdRightToLeft;
    l0 := bar.TopLeftPx(0, 96);
    l1 := bar.TopLeftPx(1, 96);
    { A reflection about the bar's own width -- so the near-edge inset the theme gave the
      first cell becomes the same inset from the far edge, rather than a fresh number. }
    AssertEquals('the first top''s right edge is the reflection of its left edge',
      400 - ltr0, l0 + w0);
    AssertEquals('and its width came through the reflection unchanged',
      w0, bar.TopWidthPx(0, 96));
    AssertTrue('the second top is entirely left of the first',
      l1 + bar.TopWidthPx(1, 96) <= l0);
  finally
    Form.Free;
  end;
end;

{ TopLeft is the ONE place the mirroring happens and TopAtX inverts it by calling it, so this
  cannot come apart -- which is exactly the claim worth pinning, because the alternative
  (a mirrored paint over an unmirrored TopAtX) is a bar that opens the wrong menu. }
procedure TRtlMenuBarTest.TopCellHitTestAgreesWithTheMirroredCells;
var
  Form: TForm;
  bar: TMenuBarAccess2;
  i, mid: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    bar := MakeBar(Form, ['File', 'Edit', 'View'], -1);
    bar.Parent := Form;
    bar.BiDiMode := bdRightToLeft;
    for i := 0 to 2 do
    begin
      mid := bar.TopLeftPx(i, 96) + bar.TopWidthPx(i, 96) div 2;
      AssertEquals('the hit test answers for the cell the paint drew there',
        i, bar.TopAt(mid, 96));
    end;
    AssertEquals('and just past the last cell there is no cell at all',
      -1, bar.TopAt(bar.TopLeftPx(2, 96) - 2, 96));
  finally
    Form.Free;
  end;
end;

{ RightJustify packs a group against the trailing edge and keeps it glued there. Mirrored,
  that edge is the LEFT one -- both packing rules go through the same reflection, so neither
  can be the branch somebody forgot. }
procedure TRtlMenuBarTest.RightJustifiedTopsPackAgainstTheOtherEdge;
var
  Form: TForm;
  bar: TMenuBarAccess2;
  lHelp, wHelp: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    bar := MakeBar(Form, ['File', 'Edit', 'Help'], 2);
    bar.Parent := Form;
    wHelp := bar.TopWidthPx(2, 96);
    AssertTrue('unmirrored, the right-justified top is right of the left-packed ones',
      bar.TopLeftPx(2, 96) > bar.TopLeftPx(1, 96) + bar.TopWidthPx(1, 96));

    bar.BiDiMode := bdRightToLeft;
    lHelp := bar.TopLeftPx(2, 96);
    AssertTrue('mirrored, it packs against the OTHER edge -- left of both the others',
      lHelp + wHelp <= bar.TopLeftPx(1, 96));
    AssertEquals('and the hit test agrees with where it went', 2,
      bar.TopAt(lHelp + wHelp div 2, 96));
  finally
    Form.Free;
  end;
end;

{ FitWidth measures an EXTENT, and the reflection is taken about Width -- the very number
  FitWidth produces. Reading a mirrored x there is circular, and the symptom is an AutoSizeWidth
  bar that shrinks to nothing or grows without bound the moment it is mirrored. }
procedure TRtlMenuBarTest.FitWidthIsTheSameWhicheverWayTheBarReads;
var
  Form: TForm;
  bar: TMenuBarAccess2;
  before: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    bar := MakeBar(Form, ['File', 'Edit', 'View'], -1);
    bar.Parent := Form;
    before := bar.FitPx(96);
    AssertTrue('a bar with cells fits into a positive width', before > 0);
    AssertTrue('and into less than the bar it was given', before < 400);
    bar.BiDiMode := bdRightToLeft;
    AssertEquals('a reflection preserves extent, so the fit is unchanged',
      before, bar.FitPx(96));
  finally
    Form.Free;
  end;
end;

procedure TRtlMenuBarTest.TopCaptionMovesToTheCellsTrailingEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  bar: TMenuBarAccess2;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(400, 24);
  try
    { A GENEROUS cell padding, 16px, on purpose: the two ways to get this half-right differ
      from the right answer by exactly one padding, so a small one would make the difference
      a couple of pixels and put the assertions inside the glyphs' own side bearings. }
    Ctl.LoadThemeCss(
      'TyMenuBar { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
      'TyMenuItem { background: #FFFFFF; color: #00FF00; padding: 16px; }');
    bar := MakeBar(Form, ['File'], -1);
    bar.Parent := Form;
    bar.Controller := Ctl;
    bar.BiDiMode := bdRightToLeft;
    bar.RenderTo(host.Canvas, Rect(0, 0, 400, 24), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpanX(shot, chGreen, l, r);
      AssertTrue('the bar drew its caption', l >= 0);
      AssertTrue('a mirrored top caption sits at the RIGHT end of the bar', r > 400 - 40);
      AssertTrue('and has vacated the left end', l > 300);
      { The two halves, each of which the other would hide. The SLOT moved -- the cell's own
        16px padding is on the trailing side now, so the caption stops short of the bar's edge
        rather than running into it. And the TEXT re-aligned inside that slot -- taLeftJustify
        means the reading start, which mirrored is the slot's right-hand edge, so the caption
        hugs it instead of sitting a padding-and-a-caption away from it. }
      AssertTrue('the cell''s padding travelled to the trailing side', r < 400 - 8);
      AssertTrue('and the caption is aligned against that side, not the other one', r > 375);
    finally
      shot.Free;
    end;
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ The dropdown is a window of its own, built by us with TForm.CreateNew: it inherits no
  BiDiMode from anything, so the bar has to hand its direction down or the bar mirrors and the
  menu that drops out of it does not. }
procedure TRtlMenuBarTest.BarDirectionReachesItsDropdown;
var
  Form: TForm;
  bar: TMenuBarAccess2;
  mi: TMenuItem;
begin
  Form := TForm.CreateNew(nil);
  try
    bar := MakeBar(Form, ['File'], -1);
    bar.Parent := Form;
    mi := bar.Menu.Items[0];
    mi.Add(NewItem('One', 0, False, True, nil, 0, ''));
    bar.BiDiMode := bdRightToLeft;
    bar.OpenTopForTest(0);
    AssertTrue('the bar built its dropdown host', bar.PopupForTest <> nil);
    AssertTrue('and told it which way it reads', bar.PopupForTest.RightToLeft);
    AssertTrue('which reaches the renderer that lays the rows out',
      bar.PopupForTest.ViewForTest.IsRightToLeft);
  finally
    Form.Free;
  end;
end;

{ ------------------------------------------------------- TRtlPopupMenuTest -- }

procedure TRtlPopupMenuTest.OnOpen(Sender: TObject; AIndex: Integer);
begin
  Inc(FOpened);
end;

procedure TRtlPopupMenuTest.OnBack(Sender: TObject);
begin
  Inc(FWentBack);
end;

{ One item row, built by hand: TTyMenuRow is a public record and SetRows is public, so a test
  can put exactly one thing on the row and probe it by colour without a TMenuItem tree. }
function TRtlPopupMenuTest.OneRow(AWithSubmenu: Boolean; const AShortcut: string): TTyMenuRowArray;
begin
  SetLength(Result, 1);
  Result[0] := Default(TTyMenuRow);
  Result[0].Kind := mrkItem;
  Result[0].Caption := '';
  Result[0].Display := '';
  Result[0].Enabled := True;
  Result[0].HasSubmenu := AWithSubmenu;
  Result[0].ShortcutText := AShortcut;
  Result[0].ImageIndex := -1;
end;

const
  { DELIBERATELY LOPSIDED: a 16px check slot behind a 6px pad on one side, a 40px arrow slot
    behind a 24px pad on the other. With the library's own near-symmetric defaults (18 and 16,
    4 and 4) a row-internal rect that was never mirrored lands two pixels from where the
    mirrored one does -- inside the glyphs' side bearings, and indistinguishable from it by any
    assertion. Every gap between the two ends here is at least twenty pixels wide.
    Vertical padding stays at 4 so a row is still 24px tall and fits the fixtures' bitmaps.
    TyMenuItem:active is the fill the decorative banner strip borrows; no row is highlighted in
    any of these fixtures, so red on the bitmap means the banner and nothing else. }
  cMenuCss =
    ':root { --menu-check-slot: 16px; --menu-arrow-slot: 40px; }' +
    'TyMenuView { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
    'TyMenuItem { background: #FFFFFF; color: #00FF00; padding: 4px 24px 4px 6px; ' +
      'font-size: 12px; }' +
    'TyMenuItem:active { background: #FF0000; }';

function RenderRow(const ARows: TTyMenuRowArray; ARtl: Boolean; AW, AH: Integer;
  ABannerPx: Integer = 0): TBGRABitmap;
var
  Ctl: TTyStyleController;
  Form: TForm;
  V: TMenuViewAccess2;
  host: TBitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(AW, AH);
  try
    Ctl.LoadThemeCss(cMenuCss);
    V := TMenuViewAccess2.Create(Form);
    V.Parent := Form;
    V.Controller := Ctl;
    V.Font.PixelsPerInch := 96;
    V.BannerWidth := ABannerPx;
    if ARtl then V.BiDiMode := bdRightToLeft;
    V.SetRows(ARows);
    V.RenderTo(host.Canvas, Rect(0, 0, AW, AH), 96);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRtlPopupMenuTest.CheckSlotMovesToTheRightHandEndOfTheRow;
var
  rows: TTyMenuRowArray;
  ltr, rtl: TBGRABitmap;
  ll, lr, rl, rr: Integer;
begin
  rows := OneRow(False, '');
  rows[0].Checked := True;
  ltr := RenderRow(rows, False, 200, 24);
  rtl := RenderRow(rows, True, 200, 24);
  try
    ChannelSpanX(ltr, chGreen, ll, lr);
    ChannelSpanX(rtl, chGreen, rl, rr);
    AssertTrue('the check glyph drew in both directions', (ll >= 0) and (rl >= 0));
    { The slot is [6, 22) unmirrored and [178, 194) mirrored. }
    AssertTrue('unmirrored it is in the leading slot', lr < 30);
    AssertTrue('mirrored it is in the slot at the other end', rl > 170);
    AssertTrue('and it did not simply stay put', rl > lr);
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

{ The caption occupies the band BETWEEN the two slots, so its rect is the one that has to move
  and re-align rather than merely widen. Probed with no check glyph and no shortcut, so the
  ink found is the caption and only the caption. }
procedure TRtlPopupMenuTest.RowCaptionMovesToTheReadingStartSideOfTheRow;
var
  rows: TTyMenuRowArray;
  ltr, rtl: TBGRABitmap;
  ll, lr, rl, rr: Integer;
begin
  rows := OneRow(False, '');
  rows[0].Display := 'Open';
  ltr := RenderRow(rows, False, 200, 24);
  rtl := RenderRow(rows, True, 200, 24);
  try
    ChannelSpanX(ltr, chGreen, ll, lr);
    ChannelSpanX(rtl, chGreen, rl, rr);
    AssertTrue('the caption drew in both directions', (ll >= 0) and (rl >= 0));
    { The caption band is [22, 136) unmirrored and [64, 178) mirrored -- a whole 42px apart at
      its trailing edge, which is what the lopsided fixture buys: a caption rect that was
      never mirrored still right-aligns, just against the wrong end of the row. }
    AssertTrue('unmirrored it starts just past the leading slot', ll < 40);
    AssertTrue('mirrored it ENDS just before the slot at the other end', rr > 160);
    AssertTrue('and it left the left-hand end of the row', rl > 40);
    AssertEquals('the caption kept its own width through the move', lr - ll, rr - rl);
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

procedure TRtlPopupMenuTest.ShortcutTextMovesToTheLeftHandEnd;
var
  ltr, rtl: TBGRABitmap;
  ll, lr, rl, rr: Integer;
begin
  ltr := RenderRow(OneRow(False, 'Ctrl+S'), False, 200, 24);
  rtl := RenderRow(OneRow(False, 'Ctrl+S'), True, 200, 24);
  try
    ChannelSpanX(ltr, chGreen, ll, lr);
    ChannelSpanX(rtl, chGreen, rl, rr);
    AssertTrue('the shortcut drew in both directions', (ll >= 0) and (rl >= 0));
    AssertTrue('unmirrored the shortcut hugs the right end', lr > 160);
    AssertTrue('mirrored it hugs the LEFT end', rl < 40);
    { Both halves: the SLOT moved and the text re-aligned inside it. Mirror only the rect and
      the taRightJustify would park the text back against the slot's right edge. }
    AssertTrue('and it aligned to the mirrored edge, not the far side of its own slot',
      rr < 100);
    { ...and the rect moved too. Its mirrored left edge is the row's 24px trailing pad, so a
      shortcut that came to rest on x = 0 is one drawn into the UNmirrored rect. }
    AssertTrue('the slot itself moved -- the text starts at the mirrored padding', rl > 12);
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

{ A left-hand slot with a right-pointing chevron in it is the classic half-mirrored menu: it
  points away from where the submenu actually appears. The arrow is a shaft plus a head, and
  the head is all the ink in the last third -- so which half of the slot carries more ink says
  which way it points, whatever the glyph's exact strokes are. }
procedure TRtlPopupMenuTest.SubmenuArrowMovesAndTurnsRound;
var
  ltr, rtl: TBGRABitmap;
  slot: Integer;
begin
  ltr := RenderRow(OneRow(True, ''), False, 200, 24);
  rtl := RenderRow(OneRow(True, ''), True, 200, 24);
  try
    slot := 40;   // --menu-arrow-slot, as the fixture's theme sets it, at 96 PPI
    AssertTrue('the unmirrored arrow is in the right-hand slot',
      ChannelCount(ltr, chGreen, 200 - slot, 200) > 0);
    AssertTrue('the mirrored arrow moved to the left-hand slot',
      ChannelCount(rtl, chGreen, 0, slot) > 0);
    AssertEquals('and left nothing behind in the old one', 0,
      ChannelCount(rtl, chGreen, 200 - slot, 200));
    AssertTrue('the unmirrored arrow head is at the RIGHT of its slot',
      ChannelCount(ltr, chGreen, 200 - slot div 2, 200)
        > ChannelCount(ltr, chGreen, 200 - slot, 200 - slot div 2));
    AssertTrue('the mirrored arrow head is at the LEFT of its slot -- it turned round',
      ChannelCount(rtl, chGreen, 0, slot div 2)
        > ChannelCount(rtl, chGreen, slot div 2, slot));
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

{ The banner is the strip every row is indented past, so it has to change ends WITH them or
  the rows are indented away from it into open space. }
procedure TRtlPopupMenuTest.BannerStripMovesToTheOtherEndOfThePopup;
var
  rows: TTyMenuRowArray;
  ltr, rtl: TBGRABitmap;
begin
  rows := OneRow(False, '');
  rows[0].Checked := True;
  { Probed through the ROW rather than the strip's own fill: the strip reuses TyMenuItem:active
    for its background, which this fixture leaves at the base colour, and the load-bearing
    claim is anyway that the rows moved WITH it -- a banner that changed ends alone would
    leave every row indented into open space at the other. }
  ltr := RenderRow(rows, False, 200, 24, 20);
  rtl := RenderRow(rows, True, 200, 24, 20);
  try
    { The strip itself, by its own fill colour. }
    AssertTrue('unmirrored the strip is at the left end',
      ChannelCount(ltr, chRed, 0, 20) > 0);
    AssertEquals('and nowhere else', 0, ChannelCount(ltr, chRed, 20, 200));
    AssertTrue('mirrored it is at the RIGHT end', ChannelCount(rtl, chRed, 180, 200) > 0);
    AssertEquals('...and nowhere else', 0, ChannelCount(rtl, chRed, 0, 180));
    { ...and the rows moved WITH it, which is the part that matters: a strip that changed ends
      alone leaves every row indented into open space at the other. }
    AssertTrue('unmirrored, the row content clears the left banner',
      ChannelCount(ltr, chGreen, 0, 20) = 0);
    AssertTrue('mirrored, the row content clears the RIGHT banner',
      ChannelCount(rtl, chGreen, 180, 200) = 0);
    AssertTrue('and the check glyph is inside the mirrored content area',
      ChannelCount(rtl, chGreen, 140, 180) > 0);
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

{ The property that makes moving these slots SAFE, asserted rather than assumed: a row's hit
  test reads y and nothing else, so no amount of moving things along x can put paint and hit
  test out of step. If a later change ever gives a row an x-dependent hit test, this is the
  test that has to be looked at first. }
procedure TRtlPopupMenuTest.RowHitTestIsVerticalOnlyAndSoCannotDisagree;
var
  Form: TForm;
  V: TMenuViewAccess2;
  rows: TTyMenuRowArray;
  inRow, ltrAns, rtlAns: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    V := TMenuViewAccess2.Create(Form);
    V.Parent := Form;
    V.Font.PixelsPerInch := 96;
    rows := OneRow(False, '');
    rows[0].Display := 'One';
    V.SetRows(rows);
    inRow := V.RowTopPx(0, 96) + 1;
    ltrAns := V.RowAtY(inRow, 96);
    V.BiDiMode := bdRightToLeft;
    rtlAns := V.RowAtY(inRow, 96);
    AssertEquals('the row answers inside its own band', 0, ltrAns);
    AssertEquals('and mirroring cannot change that, because the hit test never reads x',
      ltrAns, rtlAns);
    AssertEquals('above the first row there is no row', -1, V.RowAtY(-1, 96));
    AssertEquals('below every row there is no row', -1, V.RowAtY(10000, 96));
  finally
    Form.Free;
  end;
end;

{ §6.3 item 4 draws the line: these are LAYOUT arrows, so they flip. Missing it is not a
  cosmetic bug -- a right-to-left user has no keyboard route into a submenu at all, and no
  screenshot shows it. }
procedure TRtlPopupMenuTest.LeftAndRightSwapRolesInAMirroredMenu;
var
  Form: TForm;
  V: TMenuViewAccess2;
begin
  Form := TForm.CreateNew(nil);
  try
    V := TMenuViewAccess2.Create(Form);
    V.Parent := Form;
    V.Font.PixelsPerInch := 96;
    V.SetRows(OneRow(True, ''));
    V.OnOpenSubmenu := @OnOpen;
    V.OnNavigateLeft := @OnBack;
    V.SetHighlight(0);

    FOpened := 0; FWentBack := 0;
    V.Press(VK_RIGHT);
    AssertEquals('unmirrored, Right opens the submenu', 1, FOpened);
    AssertEquals('and does not go back', 0, FWentBack);
    V.Press(VK_LEFT);
    AssertEquals('unmirrored, Left goes back', 1, FWentBack);
    AssertEquals('and does not open anything', 1, FOpened);

    V.BiDiMode := bdRightToLeft;
    FOpened := 0; FWentBack := 0;
    V.Press(VK_LEFT);
    AssertEquals('mirrored, LEFT is the key that opens the submenu', 1, FOpened);
    AssertEquals('and it does not go back', 0, FWentBack);
    V.Press(VK_RIGHT);
    AssertEquals('mirrored, RIGHT is the key that returns to the parent', 1, FWentBack);
    AssertEquals('and it does not open anything', 1, FOpened);
  finally
    Form.Free;
  end;
end;

{ Up and Down are not reading directions. Pinned because "flip the arrow keys" is the kind of
  change that gets applied to all four of them. }
procedure TRtlPopupMenuTest.VerticalKeysAreUntouchedByMirroring;
var
  Form: TForm;
  V: TMenuViewAccess2;
  rows: TTyMenuRowArray;
begin
  Form := TForm.CreateNew(nil);
  try
    V := TMenuViewAccess2.Create(Form);
    V.Parent := Form;
    V.Font.PixelsPerInch := 96;
    SetLength(rows, 2);
    rows[0] := Default(TTyMenuRow); rows[0].Kind := mrkItem; rows[0].Enabled := True; rows[0].ImageIndex := -1;
    rows[1] := Default(TTyMenuRow); rows[1].Kind := mrkItem; rows[1].Enabled := True; rows[1].ImageIndex := -1;
    V.SetRows(rows);
    V.BiDiMode := bdRightToLeft;
    V.SetHighlight(0);
    V.Press(VK_DOWN);
    AssertEquals('Down still moves down a mirrored menu', 1, V.Highlighted);
    V.Press(VK_UP);
    AssertEquals('and Up still moves up', 0, V.Highlighted);
  finally
    Form.Free;
  end;
end;

procedure TRtlPopupMenuTest.MirroredDropdownHangsItsRightEdgeUnderTheAnchor;
var
  pop: TMenuPopupAccess2;
  r: TRect;
  anchor: TRect;
begin
  pop := TMenuPopupAccess2.Create(nil);
  try
    { The anchor is deliberately NARROWER than the popup. Give it the popup's own width and
      "aligned to the anchor's left" and "aligned to the anchor's right" are the same rect,
      and the test passes whether or not anything was mirrored. }
    anchor := Rect(200, 40, 260, 64);
    r := pop.Bounds(anchor, 120, 80, 96, False, False);
    AssertEquals('unmirrored: the dropdown aligns to the anchor''s left', anchor.Left, r.Left);
    r := pop.Bounds(anchor, 120, 80, 96, False, True);
    AssertEquals('mirrored: it aligns to the anchor''s RIGHT', anchor.Right, r.Right);
    AssertTrue('...which is a different rect entirely, not the same one twice',
      r.Left < anchor.Left);
    AssertEquals('width preserved', 120, r.Right - r.Left);
    AssertEquals('it still hangs BELOW the anchor -- down is not a reading direction',
      anchor.Bottom, r.Top);
  finally
    pop.Free;
  end;
end;

procedure TRtlPopupMenuTest.MirroredSubmenuCascadesToTheLeft;
var
  pop: TMenuPopupAccess2;
  r, anchor: TRect;
begin
  pop := TMenuPopupAccess2.Create(nil);
  try
    anchor := Rect(400, 100, 400, 100);   // the zero-width anchor a live cascade builds
    r := pop.Bounds(anchor, 120, 80, 96, True, False);
    AssertEquals('unmirrored: the submenu opens to the RIGHT of its parent',
      anchor.Right, r.Left);
    r := pop.Bounds(anchor, 120, 80, 96, True, True);
    AssertEquals('mirrored: it opens to the LEFT of its parent', anchor.Left, r.Right);
    AssertEquals('width preserved', 120, r.Right - r.Left);
  finally
    pop.Free;
  end;
end;

{ The edge flip is the only case in ComputeBounds that is invisible until a user hits the
  screen border -- §5 item 6. Mirrored, the border that matters is the LEFT one. }
procedure TRtlPopupMenuTest.MirroredSubmenuFlipsBackAtTheScreenEdge;
var
  pop: TMenuPopupAccess2;
  r, anchor: TRect;
begin
  pop := TMenuPopupAccess2.Create(nil);
  try
    anchor := Rect(4, 100, 8, 100);       // hard against the left edge of the work area
    r := pop.Bounds(anchor, 120, 80, 96, True, True);
    AssertTrue('a mirrored submenu with no room on the left flips back to the right',
      r.Left >= anchor.Right - 1);
    AssertEquals('width preserved through the flip', 120, r.Right - r.Left);
  finally
    pop.Free;
  end;
end;

{ A TPopupMenu is a component, not a control, so it has no direction of its own. A context
  menu belongs to whatever it was raised over, which is what LCL records in PopupComponent. }
procedure TRtlPopupMenuTest.ContextMenuTakesItsDirectionFromTheControlItWasRaisedOn;
var
  Form: TForm;
  host: TTyPanel;
  m: TTyPopupMenu;
begin
  Form := TForm.CreateNew(nil);
  try
    host := TTyPanel.Create(Form);
    host.Parent := Form;
    m := TTyPopupMenu.Create(Form);
    m.Items.Add(NewItem('One', 0, False, True, nil, 0, ''));

    m.PopupComponent := host;
    AssertFalse('a left-to-right host gives a left-to-right menu',
      m.RendererForTest.RightToLeft);

    host.BiDiMode := bdRightToLeft;
    AssertTrue('a mirrored host gives a mirrored menu', m.RendererForTest.RightToLeft);
    AssertTrue('and the renderer passes it to the view that lays the rows out',
      m.RendererForTest.ViewForTest.IsRightToLeft);
  finally
    Form.Free;
  end;
end;

{ The anchor shift PopUp applies for TPopupMenu.Alignment. Pure, because PopUp itself needs a
  live window: without this the sign lives only in a line nobody re-reads, and a mirrored
  right-aligned context menu opens a whole width away from the cursor. }
procedure TRtlPopupMenuTest.ContextMenuAlignmentShiftsTheAnchorTheOtherWayWhenMirrored;
begin
  AssertEquals('paLeft never shifts: the renderer already hangs from the reading start',
    0, TyPopupAnchorShift(paLeft, 120, False));
  AssertEquals('...on either reading', 0, TyPopupAnchorShift(paLeft, 120, True));
  AssertEquals('paRight pulls the anchor back by the whole width',
    -120, TyPopupAnchorShift(paRight, 120, False));
  AssertEquals('and mirrored it pushes it forward by the same',
    120, TyPopupAnchorShift(paRight, 120, True));
  AssertEquals('paCenter is half of it', -60, TyPopupAnchorShift(paCenter, 120, False));
  AssertEquals('...and half of it the other way', 60, TyPopupAnchorShift(paCenter, 120, True));
end;

initialization
  RegisterTest(TRtlStatusBarTest);
  RegisterTest(TRtlBandBarTest);
  RegisterTest(TRtlMenuBarTest);
  RegisterTest(TRtlPopupMenuTest);
end.
