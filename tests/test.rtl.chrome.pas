unit test.rtl.chrome;
{ RTL MIRRORING, part three: the WINDOW CHROME.

  Third sibling of test.rtl.pas (phases 0-4) and test.rtl.bars.pas (the menus and the bars).
  This unit guards TTyTitleBar -- the caption, the caption-button cluster, and the content zone
  a host's own children live in.

  WHY THE CHROME IS ITS OWN UNIT AND ITS OWN ROUND. Everything inside a mirrored window already
  reads right-to-left; the frame around it did not, so the first thing a viewer saw was the one
  thing that had not moved. On Windows a right-to-left window puts its caption on the right and
  its caption buttons on the LEFT, and it does so by mirroring the whole non-client area
  (WS_EX_LAYOUTRTL), which reverses the cluster's internal order too: Close ends up in the
  window corner, then Maximize, then Minimize. Reading the cluster in the direction the window
  reads therefore still gives minimize, maximize, close -- the same sequence, read the other
  way. That is the behaviour pinned below, and it is a REFLECTION rather than a block move for
  exactly that reason.

  WHERE THE DANGER IS. The caption buttons are real windowed children, so the thing that places
  them is also the thing that answers clicks over them: LCL routes a press by the bounds
  SetBounds wrote, and the hover / pressed state is each button's own. But the bar had a SECOND,
  independent claim about which side the cluster is on -- RightInset, consumed by
  AdjustClientRect and by CaptionSpan -- and mirroring one without the other would lay the
  caption and the host's children straight over the buttons at one end while leaving a hole at
  the other. Both now come out of one function (TyCaptionLayoutFor), and the assertions here
  come in pairs: what MOVED, and what the routing / the content zone now says about the place it
  moved to.

  The probes aim at EDGES, never at a button's centre. A click at the middle of a caption button
  survives every drift this library has actually shipped: an off-by-one at a slot boundary, a
  cluster mirrored one margin short, a content zone that overlaps the buttons by a few px. The
  sweep test walks every device x across the bar and demands the routing name the button the
  layout drew there, which is the only shape that catches all three.

  Everything is headless: the pure geometry function where there is one, LCL's own ControlAtPos
  routing for the hit half, and RenderTo into an off-screen bitmap for the paint half. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, Forms, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.Form;

type
  { RenderTo, AdjustClientRect and LayoutButtons are protected; the tests call them directly
    because Paint is unreachable without a realised handle the headless runner never creates. }
  TChromeBarAccess = class(TTyTitleBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallAdjustClientRect(var ARect: TRect);
    procedure CallLayoutButtons;
  end;

  { The cluster itself: where it sits, which way round it reads, and whether the routing agrees. }
  TRtlTitleBarTest = class(TTestCase)
  published
    procedure CaptionButtonsMoveToTheLeadingCornerWhenMirrored;
    procedure CloseKeepsTheOutermostCornerSoTheClusterReadsTheSameWay;
    procedure TheMirroredClusterIsTheExactReflectionOfTheUnmirroredOne;
    procedure EveryDeviceXIsRoutedToTheButtonTheLayoutPlacedThere;
    procedure EveryButtonSitsInsideTheStripTheContentZoneWasCarvedAround;
    procedure TheClusterEdgePixelsBelongToItAndTheOnesJustOutsideDoNot;
    procedure HidingTheMiddleButtonStillPacksFlushAgainstTheMirroredCorner;
    procedure TheReservedWidthIsTheSameWhicheverWayTheBarReads;
    procedure SwitchingDirectionAtRuntimeRelaysTheButtonsWithNoPaint;
  end;

  { The other consumer of the cluster's x: the zone the caption and the host's children get. }
  TRtlTitleContentTest = class(TTestCase)
  published
    procedure ContentZoneAndTheButtonClusterNeverOverlap;
    procedure AdjustClientRectGivesUpTheMirroredSide;
    procedure CaptionInkMovesToTheReadingStartOfTheBar;
    procedure CaptionInkNeverLandsInTheMirroredButtonBand;
    procedure TitleAlignmentLeftJustifyResolvesToTheRightEdgeWhenMirrored;
    procedure CaptionStillTakesTheWidestGapTheHostsChildrenLeave;
  end;

  { What must NOT move. A window's corners are not a reading direction, and the band the bar
    hands the OS has never mentioned a button's x -- both are decisions, pinned so a later
    commit has to face them rather than walk past them. }
  TRtlChromeExclusionTest = class(TTestCase)
  published
    procedure NativeWindowEdgeCodesAreNotMirrored;
    procedure TheCaptionBandHandedToTheOsIsXIndependent;
  end;

implementation

const
  cInk = 40;   // how far a channel must lead the other two before a pixel counts as ink

type
  TChannel = (chRed, chGreen, chBlue);

procedure TChromeBarAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;
procedure TChromeBarAccess.CallAdjustClientRect(var ARect: TRect);
begin AdjustClientRect(ARect); end;
procedure TChromeBarAccess.CallLayoutButtons;
begin LayoutButtons; end;

{ Channel DOMINANCE, not colour equality -- the reasoning test.rtl.pas records: a pf32bit
  TBitmap round-tripped through TBGRABitmap loses the GDI fill, so "is this pixel dark" silently
  matches the whole bitmap. A saturated theme colour leads one channel; every grey leads none. }
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

function ChannelCount(A: TBGRABitmap; ACh: TChannel; AX0, AX1: Integer): Integer;
var x, y: Integer;
begin
  Result := 0;
  if AX0 < 0 then AX0 := 0;
  if AX1 > A.Width then AX1 := A.Width;
  for y := 0 to A.Height - 1 do
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

{ A bar of AW x AH at 96 PPI, mirrored or not. Parented to a real form because a title bar with
  no parent has no client rect worth laying out into. The caller frees the FORM, which owns it. }
function NewBar(out AForm: TForm; ARtl: Boolean; AW: Integer = 400; AH: Integer = 34): TChromeBarAccess;
begin
  AForm := TForm.CreateNew(nil);
  Result := TChromeBarAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Font.PixelsPerInch := 96;
  Result.Align := alNone;
  Result.SetBounds(0, 0, AW, AH);
  if ARtl then Result.BiDiMode := bdRightToLeft;
  Result.CallLayoutButtons;
end;

function InX(const R: TRect; AX: Integer): Boolean;
begin Result := (R.Right > R.Left) and (AX >= R.Left) and (AX < R.Right); end;

{ ------------------------------------------------------------ TRtlTitleBarTest }

{ The loudest half. Unmirrored the cluster ends at the bar's right edge; mirrored it starts at
  the left one, and -- the second clause, which a block that merely slid would fail -- it has
  left the right edge entirely. }
procedure TRtlTitleBarTest.CaptionButtonsMoveToTheLeadingCornerWhenMirrored;
var
  F: TForm;
  T: TChromeBarAccess;
  lay: TTyCaptionLayout;
begin
  T := NewBar(F, False);
  try
    lay := T.CaptionLayout;
    AssertEquals('unmirrored the cluster ends at the right edge', 400, lay.Band.Right);
    AssertEquals('...and the close button with it', 400, T.CloseButton.Left + T.CloseButton.Width);
  finally F.Free; end;

  T := NewBar(F, True);
  try
    lay := T.CaptionLayout;
    AssertEquals('mirrored the cluster starts at the LEFT edge', 0, lay.Band.Left);
    AssertTrue('...and has left the right edge entirely', lay.Band.Right < 200);
    AssertEquals('and the leftmost button is flush against x = 0', 0,
      T.CloseButton.Left);
  finally F.Free; end;
end;

{ THE ORDER DECISION. Windows mirrors the whole non-client area for a right-to-left window, so
  the cluster reverses: Close takes the window CORNER, Minimize the innermost slot. Read in the
  direction the window reads, the sequence is still minimize, maximize, close -- unchanged. A
  cluster that moved as a block without reversing would put Minimize in the corner and Close in
  the middle, an order that exists on no platform; this is the assertion that tells the two
  apart, and it is stated on the ORDER rather than on any one coordinate. }
procedure TRtlTitleBarTest.CloseKeepsTheOutermostCornerSoTheClusterReadsTheSameWay;
var
  F: TForm;
  T: TChromeBarAccess;
begin
  T := NewBar(F, False);
  try
    AssertTrue('unmirrored, reading left to right: minimize first',
      T.MinButton.Left < T.MaxButton.Left);
    AssertTrue('...then maximize, then close in the corner',
      T.MaxButton.Left < T.CloseButton.Left);
  finally F.Free; end;

  T := NewBar(F, True);
  try
    AssertTrue('mirrored, reading RIGHT to left: minimize first',
      T.MinButton.Left > T.MaxButton.Left);
    AssertTrue('...then maximize, then close in the corner',
      T.MaxButton.Left > T.CloseButton.Left);
    AssertEquals('and close really is IN the corner', 0, T.CloseButton.Left);
  finally F.Free; end;
end;

{ Reflection, not "moved to the left". Every button's mirrored box has to be its unmirrored box
  flipped about the bar's centre -- which is one statement that covers the side, the order, the
  widths, the gaps and both margins at once. A cluster re-packed from the left with a
  hand-written reverse loop passes "close is at x=0" and fails this at the first margin. }
procedure TRtlTitleBarTest.TheMirroredClusterIsTheExactReflectionOfTheUnmirroredOne;
var
  F: TForm;
  T: TChromeBarAccess;
  ltrMin, ltrMax, ltrClose, span: TRect;
begin
  T := NewBar(F, False);
  try
    ltrMin := T.MinButton.BoundsRect;
    ltrMax := T.MaxButton.BoundsRect;
    ltrClose := T.CloseButton.BoundsRect;
  finally F.Free; end;

  span := Rect(0, 0, 400, 0);
  T := NewBar(F, True);
  try
    AssertTrue('minimize is its own reflection',
      T.MinButton.BoundsRect = BidiFlipRect(ltrMin, span, True));
    AssertTrue('maximize is its own reflection',
      T.MaxButton.BoundsRect = BidiFlipRect(ltrMax, span, True));
    AssertTrue('close is its own reflection',
      T.CloseButton.BoundsRect = BidiFlipRect(ltrClose, span, True));
  finally F.Free; end;
end;

{ The pair that matters. LCL routes a press to a windowed child by the bounds SetBounds wrote,
  so ControlAtPos IS the caption buttons' hit test -- and this walks EVERY device x across the
  bar demanding it name the button the layout placed there, in both directions. Mirror the
  placement and leave any consumer behind and some x answers for a button that is no longer
  drawn under it. A probe at a button's centre is immune to all of that; this is not. }
procedure TRtlTitleBarTest.EveryDeviceXIsRoutedToTheButtonTheLayoutPlacedThere;
var
  F: TForm;
  T: TChromeBarAccess;
  lay: TTyCaptionLayout;
  rtl: Boolean;
  x: Integer;
  got, want: TControl;
begin
  for rtl := False to True do
  begin
    T := NewBar(F, rtl);
    try
      lay := T.CaptionLayout;
      for x := 0 to 399 do
      begin
        got := T.ControlAtPos(Point(x, 17), [capfAllowWinControls, capfAllowDisabled]);
        if InX(lay.CloseBtn, x) then want := T.CloseButton
        else if InX(lay.MaxBtn, x) then want := T.MaxButton
        else if InX(lay.MinBtn, x) then want := T.MinButton
        else want := nil;
        AssertTrue(Format('x=%d rtl=%s: the routing must name the button the layout drew',
          [x, BoolToStr(rtl, True)]), got = want);
      end;
    finally F.Free; end;
  end;
end;

{ THE invariant this record exists to buy, and the direct analogue of the status bar's
  GripInkStaysInsideTheZoneItsHitTestAnswersFor: every button box lies inside the strip that the
  content zone was carved around. Mirror the buttons and leave the strip (or the reverse) and
  the buttons are in one place while the hole reserved for them is in the other -- which no
  assertion about "the cluster is on the left" catches, because each half satisfies its own. }
procedure TRtlTitleBarTest.EveryButtonSitsInsideTheStripTheContentZoneWasCarvedAround;
var
  F: TForm;
  T: TChromeBarAccess;
  lay: TTyCaptionLayout;
  rtl: Boolean;

  procedure Inside(const R: TRect; const AWhat: string);
  begin
    AssertTrue(Format('rtl=%s: %s is inside the reserved strip', [BoolToStr(rtl, True), AWhat]),
      (R.Left >= lay.Band.Left) and (R.Right <= lay.Band.Right));
  end;

begin
  for rtl := False to True do
  begin
    T := NewBar(F, rtl);
    try
      lay := T.CaptionLayout;
      AssertTrue('precondition: the strip is a strip, not the whole bar',
        (lay.Band.Right - lay.Band.Left) < 200);
      Inside(T.MinButton.BoundsRect, 'minimize');
      Inside(T.MaxButton.BoundsRect, 'maximize');
      Inside(T.CloseButton.BoundsRect, 'close');
    finally F.Free; end;
  end;
end;

{ Aimed at the four boundary pixels of the cluster, because that is where an off-by-one lives
  and where a centre probe never looks: the first pixel INSIDE the corner button belongs to it,
  the pixel one past the cluster's inner edge belongs to nobody. }
procedure TRtlTitleBarTest.TheClusterEdgePixelsBelongToItAndTheOnesJustOutsideDoNot;
var
  F: TForm;
  T: TChromeBarAccess;
  lay: TTyCaptionLayout;
begin
  T := NewBar(F, True);
  try
    lay := T.CaptionLayout;
    AssertTrue('the bar''s very first pixel is the close button',
      T.ControlAtPos(Point(0, 17), [capfAllowWinControls, capfAllowDisabled]) = T.CloseButton);
    AssertTrue('the last pixel of the close button is still the close button',
      T.ControlAtPos(Point(lay.CloseBtn.Right - 1, 17),
        [capfAllowWinControls, capfAllowDisabled]) = T.CloseButton);
    AssertTrue('one past it is the NEXT button, not the same one',
      T.ControlAtPos(Point(lay.CloseBtn.Right, 17),
        [capfAllowWinControls, capfAllowDisabled]) = T.MaxButton);
    AssertTrue('the last pixel of the cluster is still a button',
      T.ControlAtPos(Point(lay.Band.Right - 1, 17),
        [capfAllowWinControls, capfAllowDisabled]) = T.MinButton);
    AssertTrue('and the first pixel past the cluster is the bare bar',
      T.ControlAtPos(Point(lay.Band.Right, 17),
        [capfAllowWinControls, capfAllowDisabled]) = nil);
  finally F.Free; end;
end;

{ The cluster PACKS, it does not fill slots: hiding the middle button slides the outer two
  together against the corner they read from. Pinned mirrored because that is the direction in
  which a slot-based layout leaves a hole nobody looks at. }
procedure TRtlTitleBarTest.HidingTheMiddleButtonStillPacksFlushAgainstTheMirroredCorner;
var
  F: TForm;
  T: TChromeBarAccess;
begin
  T := NewBar(F, True);
  try
    T.MaxButton.Visible := False;
    T.CallLayoutButtons;
    AssertEquals('close still holds the mirrored corner', 0, T.CloseButton.Left);
    AssertEquals('minimize packs into the freed middle slot (abuts close)',
      T.CloseButton.Left + T.CloseButton.Width, T.MinButton.Left);
    AssertEquals('and the cluster is two buttons wide',
      2 * T.CloseButton.Width, T.RightInset);
  finally F.Free; end;
end;

{ RightInset is a WIDTH, and a width has no direction. Its name reads as a side and now lies on
  a mirrored bar (docs/controls/titlebar.md says so); the value must not start lying too. }
procedure TRtlTitleBarTest.TheReservedWidthIsTheSameWhicheverWayTheBarReads;
var
  F: TForm;
  T: TChromeBarAccess;
  ltr: Integer;
begin
  T := NewBar(F, False);
  try ltr := T.RightInset; finally F.Free; end;
  T := NewBar(F, True);
  try
    AssertTrue('precondition: it reserves something', ltr > 0);
    AssertEquals('the reserved width does not change with the reading direction',
      ltr, T.RightInset);
  finally F.Free; end;
end;

{ BiDiMode is writable at runtime, and the buttons are placed by SetBounds rather than redrawn
  from a paint -- so without a CM_BIDIMODECHANGED hook the cluster stays on the old side until
  something happens to repaint the bar. Asserted with NO intervening paint or resize. }
procedure TRtlTitleBarTest.SwitchingDirectionAtRuntimeRelaysTheButtonsWithNoPaint;
var
  F: TForm;
  T: TChromeBarAccess;
begin
  T := NewBar(F, False);
  try
    AssertEquals('precondition: close is at the right edge', 400,
      T.CloseButton.Left + T.CloseButton.Width);
    T.BiDiMode := bdRightToLeft;
    AssertEquals('flipping the direction moves the cluster there and then', 0,
      T.CloseButton.Left);
    T.BiDiMode := bdLeftToRight;
    AssertEquals('and back again', 400, T.CloseButton.Left + T.CloseButton.Width);
  finally F.Free; end;
end;

{ -------------------------------------------------------- TRtlTitleContentTest }

{ The invariant the second x consumer exists to keep. Mirror the buttons and leave the content
  zone (or the reverse) and the two overlap at one end and leave a hole at the other -- the
  caption and every host child drawn straight over the caption buttons. Neither half alone
  fails an assertion about "the buttons are on the left"; this one fails for both. }
procedure TRtlTitleContentTest.ContentZoneAndTheButtonClusterNeverOverlap;
var
  F: TForm;
  T: TChromeBarAccess;
  lay: TTyCaptionLayout;
  rtl: Boolean;
begin
  for rtl := False to True do
  begin
    T := NewBar(F, rtl);
    try
      lay := T.CaptionLayout;
      AssertTrue(Format('rtl=%s: the content zone is not empty', [BoolToStr(rtl, True)]),
        lay.Content.Right > lay.Content.Left);
      AssertTrue(Format('rtl=%s: the cluster is not the whole bar', [BoolToStr(rtl, True)]),
        (lay.Band.Right - lay.Band.Left) < 200);
      AssertTrue(Format('rtl=%s: content and cluster do not overlap', [BoolToStr(rtl, True)]),
        (lay.Content.Right <= lay.Band.Left) or (lay.Content.Left >= lay.Band.Right));
      { ...and the zone really did change ends, which the non-overlap alone would not say. }
      if rtl then
        AssertTrue('mirrored, the content zone sits to the RIGHT of the cluster',
          lay.Content.Left >= lay.Band.Right)
      else
        AssertTrue('unmirrored, it sits to the left of it',
          lay.Content.Right <= lay.Band.Left);
    finally F.Free; end;
  end;
end;

{ The third consumer: the rect LCL's align engine gives the bar's own children. It has to give
  up the same side the buttons took, or an alTop/alClient child inside the bar is laid over them. }
procedure TRtlTitleContentTest.AdjustClientRectGivesUpTheMirroredSide;
var
  F: TForm;
  T: TChromeBarAccess;
  R: TRect;
  inset: Integer;
begin
  T := NewBar(F, True);
  try
    inset := T.RightInset;
    R := Rect(0, 0, 400, 34);
    T.CallAdjustClientRect(R);
    AssertEquals('mirrored, the LEFT edge gives up the whole button cluster', inset, R.Left);
    AssertTrue('...and the right edge only gives up the caption pad',
      (R.Right < 400) and (R.Right > 400 - inset));
    AssertTrue('the strip is still usable', R.Right > R.Left);
  finally F.Free; end;
end;

{ Shared fixture for the caption probes: green caption text on a white bar, so the one thing
  with colour on it is the caption. The buttons draw their glyphs in the SAME resolved text
  colour, which is why every caption assertion below is stated over a band that excludes them. }
const
  cBarCss = 'TyTitleBar { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }'
          + 'TyCaptionButton { background: #FFFFFF; color: #FFFFFF; border-width: 0px; }';

function RenderBar(ARtl: Boolean; AAlign: TAlignment; AW: Integer = 400; AH: Integer = 34): TBGRABitmap;
var
  Ctl: TTyStyleController;
  Form: TForm;
  T: TChromeBarAccess;
  host: TBitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  host := NewHost(AW, AH);
  try
    Ctl.LoadThemeCss(cBarCss);
    T := TChromeBarAccess.Create(Form);
    T.Parent := Form;
    T.Controller := Ctl;
    T.Font.PixelsPerInch := 96;
    T.Align := alNone;
    T.SetBounds(0, 0, AW, AH);
    T.Caption := 'Title';
    T.TitleAlignment := AAlign;
    if ARtl then T.BiDiMode := bdRightToLeft;
    T.CallLayoutButtons;
    T.RenderTo(host.Canvas, Rect(0, 0, AW, AH), 96);
    Result := TBGRABitmap.Create(host);
  finally
    host.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ The paint half of the mirror, and the one a viewer sees first. }
procedure TRtlTitleContentTest.CaptionInkMovesToTheReadingStartOfTheBar;
var
  ltr, rtl: TBGRABitmap;
  ll, lr, rl, rr: Integer;
begin
  ltr := RenderBar(False, taLeftJustify);
  rtl := RenderBar(True, taLeftJustify);
  try
    ChannelSpanX(ltr, chGreen, ll, lr);
    ChannelSpanX(rtl, chGreen, rl, rr);
    AssertTrue('the unmirrored bar drew its caption', ll >= 0);
    AssertTrue('the mirrored bar drew its caption', rl >= 0);
    AssertTrue('unmirrored the caption hugs the LEFT edge', ll < 20);
    AssertTrue('...and stays well clear of the right one', lr < 200);
    AssertTrue('mirrored the caption hugs the RIGHT edge', rr > 400 - 20);
    AssertTrue('...and has left the left one entirely', rl > 200);
  finally
    ltr.Free;
    rtl.Free;
  end;
end;

{ The pair to ContentZoneAndTheButtonClusterNeverOverlap, in pixels: mirror the caption's
  alignment through the painter and leave the SPAN it is drawn into on the old side, and the
  caption runs right across the buttons. Probed over the band the cluster now occupies. }
procedure TRtlTitleContentTest.CaptionInkNeverLandsInTheMirroredButtonBand;
var
  F: TForm;
  T: TChromeBarAccess;
  band: TRect;
  shot: TBGRABitmap;
begin
  T := NewBar(F, True);
  try band := T.CaptionLayout.Band; finally F.Free; end;

  shot := RenderBar(True, taLeftJustify);
  try
    AssertTrue('precondition: the cluster really is on the left', band.Left = 0);
    AssertEquals('no caption ink inside the mirrored button band', 0,
      ChannelCount(shot, chGreen, band.Left, band.Right));
  finally
    shot.Free;
  end;
end;

{ examples/rtl/umain.lfm pins TitleAlignment = taLeftJustify, and the library's rule is that an
  alignment the author WROTE is overridden rather than defaulted -- so on a mirrored bar that
  value has to resolve to the reading start, i.e. the right edge. taCenter must not move. }
procedure TRtlTitleContentTest.TitleAlignmentLeftJustifyResolvesToTheRightEdgeWhenMirrored;
var
  a, b: TBGRABitmap;
  al, ar, bl, br: Integer;
begin
  a := RenderBar(True, taLeftJustify);
  b := RenderBar(True, taRightJustify);
  try
    ChannelSpanX(a, chGreen, al, ar);
    ChannelSpanX(b, chGreen, bl, br);
    AssertTrue('taLeftJustify drew', al >= 0);
    AssertTrue('taRightJustify drew', bl >= 0);
    AssertTrue('mirrored, a taLeftJustify caption is against the RIGHT edge', ar > 400 - 20);
    AssertTrue('...and a taRightJustify one is against the cluster instead', br < 200);
  finally
    a.Free;
    b.Free;
  end;
end;

{ A title bar is a container: hosts drop theme pickers and menu bars on it, and the caption
  takes the widest gap they leave rather than assuming they sit on one side. LCL does not mirror
  a child's Align/Anchors (docs/rtl.md records why), so on a mirrored bar those children stay
  where the author anchored them -- and the gap scan has to keep working from the mirrored zone
  rather than from the old one. Modelled on examples/rtl: a child anchored near the right end. }
procedure TRtlTitleContentTest.CaptionStillTakesTheWidestGapTheHostsChildrenLeave;
var
  F: TForm;
  T: TChromeBarAccess;
  Kid: TTyPanel;
  l, r: Integer;
  band: TRect;
begin
  T := NewBar(F, True);
  try
    band := T.CaptionLayout.Band;
    Kid := TTyPanel.Create(F);
    Kid.Parent := T;
    Kid.SetBounds(300, 4, 90, 26);
    T.CaptionSpan(400, l, r);
    AssertEquals('the span starts exactly where the mirrored cluster ends', band.Right, l);
    { EXACT, not "<= 300". The caption buttons are themselves children of the bar, so a span
      left on the unmirrored side is partly re-derived by the gap scan walking over them -- it
      comes back with the right LEFT edge and a right edge one whole cluster short. Only naming
      the far edge tells that apart from the real answer. }
    AssertEquals('and runs right up to the child, not a cluster short', 300, r);
    AssertTrue('the widest gap really is the one between them', r - l > 100);
  finally F.Free; end;
end;

{ ----------------------------------------------------- TRtlChromeExclusionTest }

{ HTBOTTOMLEFT and HTBOTTOMRIGHT name real WINDOW corners. A window's bottom-left corner is its
  bottom-left corner in either reading direction, and a right-to-left window that resized from
  the mirror image of the grabbed corner would be unusable. TTyStatusBar already took this
  decision for its size grip (tests/test.rtl.bars.pas); the chrome follows it, and TyNcHitTest
  therefore takes no direction argument at all. This pins that: mirrored bar, same codes. }
procedure TRtlChromeExclusionTest.NativeWindowEdgeCodesAreNotMirrored;
const
  WR: TRect = (Left: 0; Top: 0; Right: 300; Bottom: 200);
  ZONE = 6; CAPH = 34;
var
  F: TForm;
  T: TChromeBarAccess;
begin
  T := NewBar(F, True, 300, CAPH);
  try
    AssertTrue('precondition: the bar really is mirrored', T.IsRightToLeft);
    AssertEquals('the bottom-LEFT window corner stays HTBOTTOMLEFT', TyHTBOTTOMLEFT,
      TyNcHitTest(WR, Point(1, 199), ZONE, CAPH, True));
    AssertEquals('the bottom-RIGHT one stays HTBOTTOMRIGHT', TyHTBOTTOMRIGHT,
      TyNcHitTest(WR, Point(299, 199), ZONE, CAPH, True));
    AssertEquals('the left edge stays HTLEFT', TyHTLEFT,
      TyNcHitTest(WR, Point(1, 100), ZONE, CAPH, True));
    AssertEquals('the right edge stays HTRIGHT', TyHTRIGHT,
      TyNcHitTest(WR, Point(299, 100), ZONE, CAPH, True));
    AssertEquals('and the composer keeps the OS''s own frame answer either way',
      TyHTBOTTOMLEFT, TyResolveNcHit(TyHTBOTTOMLEFT, WR, Point(150, 100), ZONE, CAPH, True, False));
  finally F.Free; end;
end;

{ The band the bar hands the OS is a HEIGHT, never a set of button boxes -- it answers HTCAPTION
  for every x across the top strip, and the caption buttons are windowed children the OS routes
  to by their own HWNDs. So mirroring the cluster changes nothing the OS is told, and nothing
  here needs a second copy of the cluster's geometry to keep in step. Pinned so that a later
  commit tempted to teach the NC mapper about the buttons has to face this comment first. }
procedure TRtlChromeExclusionTest.TheCaptionBandHandedToTheOsIsXIndependent;
const
  WR: TRect = (Left: 0; Top: 0; Right: 300; Bottom: 200);
  ZONE = 6; CAPH = 34;
var
  F: TForm;
  T: TChromeBarAccess;
  lay: TTyCaptionLayout;
  x: Integer;
begin
  T := NewBar(F, True, 300, CAPH);
  try
    lay := T.CaptionLayout;
    AssertTrue('precondition: the cluster is on the left', lay.Band.Left = 0);
    { Every x clear of the resize gutter, including right across the mirrored cluster. }
    for x := ZONE + 1 to 300 - ZONE - 2 do
      AssertEquals(Format('x=%d is caption band, whatever is drawn there', [x]),
        TyHTCAPTION, TyNcHitTest(WR, Point(x, ZONE + 2), ZONE, CAPH, True));
  finally F.Free; end;
end;

initialization
  RegisterTest(TRtlTitleBarTest);
  RegisterTest(TRtlTitleContentTest);
  RegisterTest(TRtlChromeExclusionTest);

end.
