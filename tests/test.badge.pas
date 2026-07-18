unit test.badge;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, Graphics, Forms, Controls, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Badge, tyControls.Button, tyControls.Divider,
  tyControls.Types;

type
  { Pure rules / geometry: plain integers in, plain values out — no control, no
    handle, no theme. }
  TTyBadgeRulesTest = class(TTestCase)
  published
    procedure TestTextMirrorsButtonCap;
    procedure TestTextNotClampedBelowZero;
    procedure TestDotHasNoText;
    procedure TestVisibleZeroRule;
    procedure TestSizeSingleGlyphIsCircle;
    procedure TestSizeWideTextKeepsPillHeight;
    procedure TestSizeFloorsDegenerateMeasure;
    procedure TestSizeDotIgnoresTextAndPadding;
    procedure TestCornerPositions;
  end;

  { Control behaviour: attachment (the reason this control exists), the theme-driven
    geometry, hit-transparency, and rendering. }
  TTyBadgeControlTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsButtonsBadgeKey;
    procedure TestDefaults;
    procedure TestAttachParentsIntoWindowedTarget;
    procedure TestAttachedFollowsTargetResize;
    procedure TestPositionMovesToTheOtherCorner;
    procedure TestAttachToGraphicTargetBecomesSibling;
    procedure TestTargetFreedDetachesSafely;
    procedure TestAttachedIsHitTransparent;
    procedure TestValueWidensBadge;
    procedure TestThemeChangeResizesBadge;
    procedure TestDotSizeComesFromThemeToken;
    procedure TestInsetComesFromThemeToken;
    procedure TestMinSizeComesFromThemeToken;
    procedure TestInsetTokenMovesBothBadgesTogether;
    procedure TestHiddenAtZeroDrawsNothing;
    procedure TestRendersThemedPill;
    procedure TestMatchesButtonBadgeGeometry;
  end;

implementation

type
  TBadgeAccess = class(TTyBadge)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  // TTyButton's RenderTo is protected; reach it to render its BUILT-IN badge, the
  // reference this control has to match.
  TButtonAccess = class(TTyButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

function TBadgeAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TBadgeAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ Bounding box of the badge's accent-blue CORE pixels (#3B82F6 = 59,130,246: strong
  blue, weak red — a white button face and black padding are both excluded, and so are
  the pill's half-covered anti-aliased edges). Rect(0,0,0,0) when there is no such
  pixel. Two bitmaps measured this way over the SAME backdrop are directly comparable:
  the identical AA bias cancels out. }
function BlueCoreBBox(R: TBGRABitmap): TRect;
var
  x, y: Integer;
  px: TBGRAPixel;
  found: Boolean;
begin
  Result := Rect(0, 0, 0, 0);
  found := False;
  for y := 0 to R.Height - 1 do
    for x := 0 to R.Width - 1 do
    begin
      px := R.GetPixel(x, y);
      if (px.blue > 200) and (px.red < 128) then
      begin
        if not found then
        begin
          Result := Rect(x, y, x + 1, y + 1);
          found := True;
        end
        else
        begin
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
      end;
    end;
end;

function HasBlueCore(R: TBGRABitmap): Boolean;
var bb: TRect;
begin
  bb := BlueCoreBBox(R);
  Result := (bb.Right > bb.Left) and (bb.Bottom > bb.Top);
end;

{ Bounding box of every BLUE-DOMINANT pixel — the pill's full SHAPE, anti-aliased rim
  included. BlueCoreBBox deliberately drops half-covered edge pixels, which makes it the
  right tool for "is the accent really painted" and for comparing two pills over one
  backdrop (the bias cancels), but the WRONG tool for measuring how far the pill reaches:
  a badge whose radius is half its height is a circle/pill whose topmost and bottommost
  rows are ENTIRELY anti-aliased, so its core can never span the control's full height.
  Blue-dominance (blue clearly above red) accepts an accent pixel blended toward the
  black backdrop, while still rejecting the black backdrop and the white digit (r=g=b). }
function BluePillBBox(R: TBGRABitmap): TRect;
var
  x, y: Integer;
  px: TBGRAPixel;
  found: Boolean;
begin
  Result := Rect(0, 0, 0, 0);
  found := False;
  for y := 0 to R.Height - 1 do
    for x := 0 to R.Width - 1 do
    begin
      px := R.GetPixel(x, y);
      if px.blue > px.red + 40 then
      begin
        if not found then
        begin
          Result := Rect(x, y, x + 1, y + 1);
          found := True;
        end
        else
        begin
          if x < Result.Left then Result.Left := x;
          if y < Result.Top then Result.Top := y;
          if x + 1 > Result.Right then Result.Right := x + 1;
          if y + 1 > Result.Bottom then Result.Bottom := y + 1;
        end;
      end;
    end;
end;

// Drive the CM_HITTEST handler the way LCL's ControlAtPos does while routing a mouse
// message: a control that answers 0 is skipped, and the message falls through.
function AskHitTest(ACtl: TControl): Integer;
var Msg: TCMHitTest;
begin
  FillChar(Msg, SizeOf(Msg), 0);
  Msg.Msg := CM_HITTEST;
  Msg.Result := 1;
  ACtl.Dispatch(Msg);
  Result := Msg.Result;
end;

{ TTyBadgeRulesTest }

procedure TTyBadgeRulesTest.TestTextMirrorsButtonCap;
begin
  // Exactly TTyButton's rule: > 99 collapses to '99+', everything else is decimal.
  AssertEquals('0', TyBadgeText(0, False));
  AssertEquals('7', TyBadgeText(7, False));
  AssertEquals('99 is still a number', '99', TyBadgeText(99, False));
  AssertEquals('100 caps', '99+', TyBadgeText(100, False));
  AssertEquals('150 caps', '99+', TyBadgeText(150, False));
end;

procedure TTyBadgeRulesTest.TestTextNotClampedBelowZero;
begin
  // The built-in badge does not clamp a negative either — mirror it rather than invent.
  AssertEquals('-3', TyBadgeText(-3, False));
end;

procedure TTyBadgeRulesTest.TestDotHasNoText;
begin
  AssertEquals('a dot carries no number', '', TyBadgeText(42, True));
  AssertEquals('not even a capped one', '', TyBadgeText(500, True));
end;

procedure TTyBadgeRulesTest.TestVisibleZeroRule;
begin
  AssertFalse('0 hides by default', TyBadgeVisible(0, False));
  AssertTrue('0 shows when asked', TyBadgeVisible(0, True));
  AssertTrue('any count shows', TyBadgeVisible(1, False));
  AssertTrue('a negative is still "something"', TyBadgeVisible(-3, False));
end;

procedure TTyBadgeRulesTest.TestSizeSingleGlyphIsCircle;
var sz: TSize;
begin
  // Text 6 wide, no padding, glyph 12 tall: the pill would be 6x12, so it widens to
  // its own height — a single digit lands in a circle, never a thin sliver.
  sz := TyBadgeSize(6, 12, 0, 0, 8, False, 8);
  AssertEquals('height = glyph + 2*padY', 12, sz.cy);
  AssertEquals('narrow text widens to the height', 12, sz.cx);
end;

procedure TTyBadgeRulesTest.TestSizeWideTextKeepsPillHeight;
var sz: TSize;
begin
  // '99+' at 24 wide with padX 4 => 32 wide; height is unchanged by the wider text
  // (it is measured from the reference glyph, so '1' and '99+' are the same height).
  sz := TyBadgeSize(24, 12, 4, 0, 8, False, 8);
  AssertEquals('text + 2*padX', 32, sz.cx);
  AssertEquals('height untouched by width', 12, sz.cy);
  // padY still grows the height.
  sz := TyBadgeSize(24, 12, 4, 3, 8, False, 8);
  AssertEquals('height = glyph + 2*padY', 18, sz.cy);
end;

procedure TTyBadgeRulesTest.TestSizeFloorsDegenerateMeasure;
var sz: TSize;
begin
  // A measure that came back as nothing must not collapse the badge out of sight.
  sz := TyBadgeSize(0, 0, 0, 0, 8, False, 8);
  AssertEquals('height floors', 8, sz.cy);
  AssertEquals('and stays square', 8, sz.cx);
end;

procedure TTyBadgeRulesTest.TestSizeDotIgnoresTextAndPadding;
var sz: TSize;
begin
  // A dot is one themed diameter — text metrics and padding do not enter into it.
  sz := TyBadgeSize(99, 40, 10, 10, 8, True, 6);
  AssertEquals('dot width = diameter', 6, sz.cx);
  AssertEquals('dot height = diameter', 6, sz.cy);
  // A theme asking for a zero/negative diameter still leaves something drawable.
  sz := TyBadgeSize(0, 0, 0, 0, 8, True, 0);
  AssertEquals('dot never collapses', 1, sz.cx);
end;

procedure TTyBadgeRulesTest.TestCornerPositions;
var
  host: TRect;
  p: TPoint;
begin
  // A 16x10 badge inset by 2 in a 100x40 host.
  host := Rect(0, 0, 100, 40);
  p := TyBadgeCornerPos(host, 16, 10, 2, bpTopLeft);
  AssertEquals('top-left x', 2, p.X);
  AssertEquals('top-left y', 2, p.Y);
  p := TyBadgeCornerPos(host, 16, 10, 2, bpTopRight);
  AssertEquals('top-right x = right - inset - w', 82, p.X);
  AssertEquals('top-right y', 2, p.Y);
  p := TyBadgeCornerPos(host, 16, 10, 2, bpBottomLeft);
  AssertEquals('bottom-left x', 2, p.X);
  AssertEquals('bottom-left y = bottom - inset - h', 28, p.Y);
  p := TyBadgeCornerPos(host, 16, 10, 2, bpBottomRight);
  AssertEquals('bottom-right x', 82, p.X);
  AssertEquals('bottom-right y', 28, p.Y);
  // The host need not start at the origin (a windowless target's bounds do not).
  p := TyBadgeCornerPos(Rect(200, 100, 350, 124), 16, 10, 2, bpBottomRight);
  AssertEquals('offset host x', 332, p.X);
  AssertEquals('offset host y', 112, p.Y);
end;

{ TTyBadgeControlTest }

procedure TTyBadgeControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Font.PixelsPerInch := 96;
end;

procedure TTyBadgeControlTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyBadgeControlTest.TestTypeKeyIsButtonsBadgeKey;
var Acc: TBadgeAccess;
begin
  Acc := TBadgeAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    // The SAME key TTyButton.DrawBadge resolves: one theme rule drives both badges.
    AssertEquals('TyBadge', Acc.StyleTypeKey);
  finally
    Acc.Free;
  end;
end;

procedure TTyBadgeControlTest.TestDefaults;
var B: TTyBadge;
begin
  B := TTyBadge.Create(FForm);
  try
    AssertEquals('value defaults to 0', 0, B.Value);
    AssertFalse('ShowZero off', B.ShowZero);
    AssertFalse('Dot off', B.Dot);
    // Same default corner as TTyButton.BadgePosition.
    AssertTrue('position defaults bottom-right', B.Position = bpBottomRight);
    AssertTrue('standalone by default', B.Target = nil);
    AssertFalse('0 without ShowZero draws nothing', B.IsShowing);
    AssertTrue('props published', IsPublishedProp(B, 'Target') and IsPublishedProp(B, 'Value')
      and IsPublishedProp(B, 'ShowZero') and IsPublishedProp(B, 'Dot')
      and IsPublishedProp(B, 'Position'));
  finally
    B.Free;
  end;
end;

procedure TTyBadgeControlTest.TestAttachParentsIntoWindowedTarget;
var
  Btn: TTyButton;
  B: TTyBadge;
begin
  Btn := TTyButton.Create(FForm);
  Btn.Parent := FForm;
  Btn.SetBounds(10, 10, 100, 40);
  B := TTyBadge.Create(FForm);
  B.Parent := FForm;          // dropped on the form...
  B.Font.PixelsPerInch := 96;
  B.Value := 7;
  B.Target := Btn;            // ...and attached: it must MOVE onto the button
  // A windowless badge can only appear ON a control that owns a handle by painting on
  // that control's own canvas, i.e. by becoming its child.
  AssertTrue('badge reparents into the windowed target', B.Parent = Btn);
  AssertEquals('button client rect is its bounds', 100, Btn.ClientWidth);
  // Placed in the target's client corner, inset like TTyButton's own badge.
  AssertEquals('x = client right - inset - w', 100 - 2 - B.Width, B.Left);
  AssertEquals('y = client bottom - inset - h', 40 - 2 - B.Height, B.Top);
  AssertTrue('sized to the measured pill, not the drop size', (B.Width > 0) and (B.Height > 0));
end;

procedure TTyBadgeControlTest.TestAttachedFollowsTargetResize;
var
  Btn: TTyButton;
  B: TTyBadge;
  oldLeft: Integer;
begin
  Btn := TTyButton.Create(FForm);
  Btn.Parent := FForm;
  Btn.SetBounds(10, 10, 100, 40);
  B := TTyBadge.Create(FForm);
  B.Font.PixelsPerInch := 96;
  B.Value := 7;
  B.Target := Btn;
  oldLeft := B.Left;
  // The badge observes the target's bounds handler list, so it re-glues itself.
  Btn.SetBounds(10, 10, 160, 60);
  AssertTrue('badge moved with the target''s corner', B.Left <> oldLeft);
  AssertEquals('x tracks the new client width', 160 - 2 - B.Width, B.Left);
  AssertEquals('y tracks the new client height', 60 - 2 - B.Height, B.Top);
end;

procedure TTyBadgeControlTest.TestPositionMovesToTheOtherCorner;
var
  Btn: TTyButton;
  B: TTyBadge;
begin
  Btn := TTyButton.Create(FForm);
  Btn.Parent := FForm;
  Btn.SetBounds(10, 10, 100, 40);
  B := TTyBadge.Create(FForm);
  B.Font.PixelsPerInch := 96;
  B.Value := 7;
  B.Target := Btn;
  B.Position := bpTopLeft;
  AssertEquals('top-left x = inset', 2, B.Left);
  AssertEquals('top-left y = inset', 2, B.Top);
  B.Position := bpTopRight;
  AssertEquals('top-right x', 100 - 2 - B.Width, B.Left);
  AssertEquals('top-right y', 2, B.Top);
end;

procedure TTyBadgeControlTest.TestAttachToGraphicTargetBecomesSibling;
var
  Dv: TTyDivider;
  B: TTyBadge;
begin
  // A windowless target cannot be a parent, so the badge joins it as a sibling and
  // anchors to its BOUNDS in the parent they share.
  Dv := TTyDivider.Create(FForm);
  Dv.Parent := FForm;
  Dv.SetBounds(200, 100, 150, 24);
  B := TTyBadge.Create(FForm);
  B.Font.PixelsPerInch := 96;
  B.Value := 3;
  B.Target := Dv;
  AssertTrue('badge joins the target''s parent', B.Parent = FForm);
  AssertEquals('x = target right - inset - w', 350 - 2 - B.Width, B.Left);
  AssertEquals('y = target bottom - inset - h', 124 - 2 - B.Height, B.Top);
end;

procedure TTyBadgeControlTest.TestTargetFreedDetachesSafely;
var
  Dv: TTyDivider;
  B: TTyBadge;
begin
  Dv := TTyDivider.Create(FForm);
  Dv.Parent := FForm;
  Dv.SetBounds(200, 100, 150, 24);
  B := TTyBadge.Create(FForm);
  B.Font.PixelsPerInch := 96;
  B.Value := 3;
  B.Target := Dv;
  Dv.Free;   // the badge must drop the reference AND its bounds hook, without an AV
  AssertTrue('target reference cleared', B.Target = nil);
  // Still a live, usable, standalone control afterwards.
  B.Value := 9;
  AssertEquals('9', B.DisplayText);
  AssertEquals('detached badge takes the mouse again', 1, AskHitTest(B));
end;

procedure TTyBadgeControlTest.TestAttachedIsHitTransparent;
var
  Btn: TTyButton;
  B: TTyBadge;
begin
  Btn := TTyButton.Create(FForm);
  Btn.Parent := FForm;
  Btn.SetBounds(10, 10, 100, 40);
  B := TTyBadge.Create(FForm);
  B.Font.PixelsPerInch := 96;
  B.Value := 7;
  AssertEquals('standalone badge is a normal, clickable control', 1, AskHitTest(B));
  B.Target := Btn;
  // Sitting ON the button, it must not swallow the button's clicks: answering 0 makes
  // LCL's ControlAtPos skip it, so the mouse message reaches the button underneath.
  AssertEquals('attached badge is hit-transparent', 0, AskHitTest(B));
end;

procedure TTyBadgeControlTest.TestValueWidensBadge;
var
  B: TTyBadge;
  w1, h1: Integer;
begin
  B := TTyBadge.Create(FForm);
  B.Parent := FForm;
  B.Font.PixelsPerInch := 96;
  B.Value := 1;
  w1 := B.Width;
  h1 := B.Height;
  // TyBadgeSize only ever WIDENS a narrow pill to its own height (cx >= cy) — it never
  // narrows a wide one, so 'circle' is not the invariant: under a theme whose padding
  // makes text+2*padX exceed the pill height, one glyph is legitimately wider than tall.
  // What must hold is that a single glyph never comes out a thin sliver.
  AssertTrue(Format('a single glyph is never narrower than it is tall (%dx%d)', [w1, h1]),
    w1 >= h1);
  B.Value := 150;   // '99+'
  AssertTrue('three glyphs are wider than one', B.Width > w1);
  AssertEquals('but the pill height is unchanged', h1, B.Height);
end;

procedure TTyBadgeControlTest.TestThemeChangeResizesBadge;
var
  Ctl: TTyStyleController;
  B: TTyBadge;
  h1: Integer;
begin
  // The badge's geometry is ENTIRELY theme-derived, so a theme switch must resize it,
  // not merely repaint it.
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyBadge { background: #3B82F6; color: #FFFFFF; font-size: 10px; padding: 0px 4px; }');
    B := TTyBadge.Create(FForm);
    B.Parent := FForm;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Value := 8;
    h1 := B.Height;
    AssertTrue('measured something', h1 > 0);
    Ctl.LoadThemeCss('TyBadge { background: #3B82F6; color: #FFFFFF; font-size: 24px; padding: 0px 4px; }');
    AssertTrue('a bigger theme font grows the pill', B.Height > h1);
  finally
    Ctl.Free;
  end;
end;

procedure TTyBadgeControlTest.TestDotSizeComesFromThemeToken;
var
  Ctl: TTyStyleController;
  B: TTyBadge;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    B := TTyBadge.Create(FForm);
    B.Parent := FForm;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Value := 1;
    B.Dot := True;
    // Unset token: the built-in fallback keeps the badge drawable.
    Ctl.LoadThemeCss('TyBadge { background: #3B82F6; }');
    AssertEquals('dot falls back to TyBadgeDotSize', TyBadgeDotSize, B.Width);
    AssertEquals('and is square', B.Width, B.Height);
    // A skin retunes the dot through the metric token, with no code change.
    Ctl.LoadThemeCss(':root { --badge-dot-size: 14px; }' + LineEnding
      + 'TyBadge { background: #3B82F6; }');
    AssertEquals('dot takes --badge-dot-size', 14, B.Width);
    AssertEquals('and stays square', 14, B.Height);
  finally
    Ctl.Free;
  end;
end;

procedure TTyBadgeControlTest.TestInsetComesFromThemeToken;
var
  Ctl: TTyStyleController;
  Btn: TTyButton;
  B: TTyBadge;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Btn := TTyButton.Create(FForm);
    Btn.Parent := FForm;
    Btn.Controller := Ctl;
    Btn.SetBounds(0, 0, 100, 40);
    B := TTyBadge.Create(FForm);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Value := 7;
    B.Position := bpTopLeft;   // the corner where the inset IS the position
    B.Target := Btn;
    // Unset token: the built-in fallback keeps the badge where it has always sat.
    Ctl.LoadThemeCss('TyBadge { background: #3B82F6; }');
    AssertEquals('inset falls back to TyBadgeInset', TyBadgeInset, B.Left);
    AssertEquals('on both axes', TyBadgeInset, B.Top);
    // A skin pushes the badge off the corner through the token, with no code change.
    Ctl.LoadThemeCss(':root { --badge-inset: 6px; }' + LineEnding
      + 'TyBadge { background: #3B82F6; }');
    AssertEquals('inset takes --badge-inset', 6, B.Left);
    AssertEquals('on both axes', 6, B.Top);
  finally
    Ctl.Free;
  end;
end;

procedure TTyBadgeControlTest.TestMinSizeComesFromThemeToken;
var
  Ctl: TTyStyleController;
  B: TTyBadge;
begin
  // --badge-min-size is the floor a degenerate measure falls back to, so drive the
  // measure to nothing (empty text via Dot is a different path — use a 0-size font)
  // and watch the floor, not the text, decide the height.
  Ctl := TTyStyleController.Create(nil);
  try
    B := TTyBadge.Create(FForm);
    B.Parent := FForm;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Value := 7;
    Ctl.LoadThemeCss('TyBadge { background: #3B82F6; font-size: 1px; padding: 0px 0px; }');
    AssertEquals('a degenerate measure floors at TyBadgeMinSize', TyBadgeMinSize, B.Height);
    Ctl.LoadThemeCss(':root { --badge-min-size: 20px; }' + LineEnding
      + 'TyBadge { background: #3B82F6; font-size: 1px; padding: 0px 0px; }');
    AssertEquals('the floor takes --badge-min-size', 20, B.Height);
    AssertEquals('and the pill stays at least as wide as it is tall', 20, B.Width);
  finally
    Ctl.Free;
  end;
end;

{ The REASON these two metrics became tokens: TTyButton's built-in badge and TTyBadge
  must retune TOGETHER. Tokenising only one call site would let an attached badge drift
  off the pixels the button's own badge uses — so assert they still coincide once a skin
  has moved the inset, not merely that each reads the token. }
procedure TTyBadgeControlTest.TestInsetTokenMovesBothBadgesTogether;
var
  Ctl: TTyStyleController;
  Btn: TButtonAccess;
  B: TBadgeAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  boxA, boxB: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    // A skin that moves the badge well off the corner: a drifting call site shows up as
    // a badge in a different place, not a subpixel rounding difference.
    Ctl.LoadThemeCss(':root { --badge-inset: 7px; }' + LineEnding
      + 'TyBadge { background: #3B82F6; color: #FFFFFF; font-size: 12px; padding: 0px 4px; }');
    Btn := TButtonAccess.Create(FForm);
    Btn.Parent := FForm;
    Btn.Controller := Ctl;
    Btn.Caption := '';
    Btn.Font.PixelsPerInch := 96;
    Btn.SetBounds(0, 0, 100, 40);
    Btn.BadgePosition := bpBottomRight;
    Btn.BadgeValue := 7;

    Btn.ShowBadge := True;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 40);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 100, 40);
    Btn.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      boxA := BlueCoreBBox(Reread);
    finally
      Reread.Free;
    end;
    AssertTrue('the button drew its built-in badge', boxA.Right > boxA.Left);

    Btn.ShowBadge := False;
    B := TBadgeAccess.Create(FForm);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Value := 7;
    B.Position := bpBottomRight;
    B.Target := Btn;
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 100, 40);
    Btn.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);
    B.RenderTo(Bmp.Canvas, Rect(B.Left, B.Top, B.Left + B.Width, B.Top + B.Height), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      boxB := BlueCoreBBox(Reread);
    finally
      Reread.Free;
    end;
    AssertTrue('the attached badge drew a pill', boxB.Right > boxB.Left);
    AssertTrue(Format('both badges honoured --badge-inset: left (button %d, badge %d)',
      [boxA.Left, boxB.Left]), Abs(boxA.Left - boxB.Left) <= 1);
    AssertTrue(Format('both badges honoured --badge-inset: top (button %d, badge %d)',
      [boxA.Top, boxB.Top]), Abs(boxA.Top - boxB.Top) <= 1);
    // ...and actually MOVED: the default inset is 2, so a 7px inset must sit further in.
    AssertTrue(Format('the token really moved the pair (right edge %d of 100)', [boxA.Right]),
      boxA.Right < 100 - 5);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyBadgeControlTest.TestHiddenAtZeroDrawsNothing;
var
  Ctl: TTyStyleController;
  B: TBadgeAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyBadge { background: #3B82F6; color: #FFFFFF; font-size: 12px; padding: 0px 4px; }');
    B := TBadgeAccess.Create(FForm);
    B.Parent := FForm;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Value := 0;   // hidden: 0 without ShowZero
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(40, 24);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 40, 24);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 40, 24), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      AssertFalse('0 without ShowZero paints nothing at all', HasBlueCore(Reread));
    finally
      Reread.Free;
    end;
    // ShowZero flips exactly that decision, and nothing else.
    B.ShowZero := True;
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 40, 24);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 40, 24), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      AssertTrue('ShowZero paints the 0 pill', HasBlueCore(Reread));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyBadgeControlTest.TestRendersThemedPill;
var
  Ctl: TTyStyleController;
  B: TBadgeAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  bb: TRect;
  px: TBGRAPixel;
  x, gotText: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyBadge { background: #3B82F6; color: #FFFFFF; font-size: 12px;'
      + ' font-weight: 700; padding: 0px 4px; }');
    B := TBadgeAccess.Create(FForm);
    B.Parent := FForm;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Value := 8;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(40, 24);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 40, 24);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, B.Width, B.Height), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      // Solid accent pixels prove the theme's background really landed (not just a rim
      // of anti-aliasing) — measured with the core predicate.
      AssertTrue('themed accent pill painted', HasBlueCore(Reread));
      // ...but the pill's EXTENT is measured on its shape, rim included: at this size a
      // single glyph makes the badge a circle, whose outermost rows/columns are wholly
      // anti-aliased. The pill is always exactly the control's natural size, so the
      // shape must reach every edge of it.
      bb := BluePillBBox(Reread);
      AssertEquals('pill spans the control width', B.Width, bb.Right - bb.Left);
      // Height tolerates 1px, for a measurement confound rather than a drawing flaw: the
      // digit is painted ON the pill, and at the circle's bottom the shape narrows to a
      // sliver a couple of px wide, which the glyph's own ink can cover outright. It shows
      // up headlessly because tytests.lpr disables the system-font fallback (for
      // determinism), leaving text to BGRA's default font, whose digits sit lower in the
      // line box than the UI font a real app resolves via TyFallbackFontName.
      AssertTrue(Format('pill spans the control height (%d of %d)',
        [bb.Bottom - bb.Top, B.Height]), (bb.Bottom - bb.Top) >= B.Height - 1);
      // The digit is drawn in the theme's text colour ON the pill: scan the middle row
      // for a white glyph pixel between the blue ends.
      gotText := 0;
      for x := bb.Left to bb.Right - 1 do
      begin
        px := Reread.GetPixel(x, (bb.Top + bb.Bottom) div 2);
        if (px.red > 200) and (px.green > 200) and (px.blue > 200) then Inc(gotText);
      end;
      AssertTrue('the count is drawn in the theme text colour', gotText > 0);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

{ TestMatchesButtonBadgeGeometry
  The whole promise of this control: a TTyBadge attached to a button must land where
  that button's OWN badge would have. Render the button with its built-in badge, then
  render the same button WITHOUT it and paint an attached TTyBadge over that identical
  backdrop — measuring both pills with the same predicate on the same backdrop, so the
  anti-aliasing bias cancels and the boxes can be compared edge for edge. A drift in the
  padding / floor / font / radius / inset maths would move an edge by more than 1px. }
procedure TTyBadgeControlTest.TestMatchesButtonBadgeGeometry;
var
  Ctl: TTyStyleController;
  Btn: TButtonAccess;
  B: TBadgeAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  boxA, boxB: TRect;
begin
  // A dedicated controller (built-in light theme: TyBadge background = var(--accent)
  // = #3B82F6), isolating from any theme another test left on the global controller.
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Btn := TButtonAccess.Create(FForm);
    Btn.Parent := FForm;
    Btn.Controller := Ctl;
    Btn.Caption := '';
    Btn.Font.PixelsPerInch := 96;
    Btn.SetBounds(0, 0, 100, 40);
    Btn.BadgePosition := bpBottomRight;
    Btn.BadgeValue := 7;

    // A: the button drawing its own built-in badge.
    Btn.ShowBadge := True;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 40);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 100, 40);
    Btn.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      boxA := BlueCoreBBox(Reread);
    finally
      Reread.Free;
    end;
    AssertTrue('the button drew its built-in badge', boxA.Right > boxA.Left);

    // B: the same button WITHOUT its badge (an identical backdrop), plus an attached
    // TTyBadge painted at the place it glued itself to.
    Btn.ShowBadge := False;
    B := TBadgeAccess.Create(FForm);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Value := 7;
    B.Position := bpBottomRight;
    B.Target := Btn;   // parents into the button and places itself in its corner
    AssertTrue('attached', B.Parent = Btn);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 100, 40);
    Btn.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 40), 96);
    // The button was rendered at the origin, so its client space IS the bitmap space:
    // the badge's own bounds are where its Paint would put the pill.
    B.RenderTo(Bmp.Canvas, Rect(B.Left, B.Top, B.Left + B.Width, B.Top + B.Height), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      boxB := BlueCoreBBox(Reread);
    finally
      Reread.Free;
    end;

    AssertTrue('standalone badge drew a pill', boxB.Right > boxB.Left);
    // Same size AND same corner, within the 1px the two blend paths may round apart.
    AssertTrue(Format('left edge matches (button %d, badge %d)', [boxA.Left, boxB.Left]),
      Abs(boxA.Left - boxB.Left) <= 1);
    AssertTrue(Format('top edge matches (button %d, badge %d)', [boxA.Top, boxB.Top]),
      Abs(boxA.Top - boxB.Top) <= 1);
    AssertTrue(Format('right edge matches (button %d, badge %d)', [boxA.Right, boxB.Right]),
      Abs(boxA.Right - boxB.Right) <= 1);
    AssertTrue(Format('bottom edge matches (button %d, badge %d)', [boxA.Bottom, boxB.Bottom]),
      Abs(boxA.Bottom - boxB.Bottom) <= 1);
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyBadgeRulesTest);
  RegisterTest(TTyBadgeControlTest);
end.
