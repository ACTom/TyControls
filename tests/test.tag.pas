unit test.tag;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Tag;

type
  { Pure-geometry tests: TyTagLayout / TyTagPreferredWidth take only integers, so they
    run with no window handle and no control instance at all. }
  TTyTagLayoutTest = class(TTestCase)
  published
    procedure TestCaptionSpansPaddedBand;
    procedure TestNotClosableHasNoSlot;
    procedure TestClosableSlotHugsRightOfBand;
    procedure TestSlotVerticallyCentred;
    procedure TestGapSeparatesCaptionAndSlot;
    procedure TestNarrowPillKeepsSlotDropsCaption;
    procedure TestSlotTallerThanPillIsClamped;
    procedure TestPaddingEatsWholePill;
    procedure TestZeroSizeEmpty;
    procedure TestPreferredWidthRoundTripsPlain;
    procedure TestPreferredWidthRoundTripsClosable;
  end;

  { Headless control behaviour: typeKey, defaults, theme-driven close geometry, the
    close gesture (and its interaction with the pill's own OnClick), and AutoSize. }
  TTyTagControlTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FClosed: Integer;      // OnClose fire count
    FClicked: Integer;     // OnClick fire count
    FAllowClose: Boolean;  // what the OnClose handler answers
    procedure HandleClose(Sender: TObject; var AllowClose: Boolean);
    procedure HandleClick(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestCloseRectEmptyWhenNotClosable;
    procedure TestCloseRectFollowsThemePadding;
    procedure TestCloseSizeMetricRetunesSlot;
    procedure TestClickCloseFiresOnCloseAndHides;
    procedure TestCloseWorksUnderActiveStatePadding;
    procedure TestCloseVetoKeepsTagVisible;
    procedure TestClickCloseDoesNotFireOnClick;
    procedure TestClickBodyFiresOnClickNotOnClose;
    procedure TestDragOffCloseCancelsGesture;
    procedure TestUnclosableIgnoresClickWhereXWouldBe;
    procedure TestPreferredSizeHugsCaption;
    procedure TestPreferredSizeGrowsForCloseSlot;
    procedure TestPreferredHeightClearsCloseSlot;
    procedure TestPillRendersThemeBackground;
    procedure TestCloseGlyphRendersThemeInk;
  end;

implementation

type
  { Reaches the protected paint + mouse seams. The mouse helpers drive the handlers in
    the SAME order LCL does (TControl.WMLButtonUp runs Click and only then DoMouseUp),
    which is exactly the ordering TTyTag.Click relies on to swallow a close gesture. }
  TTagAccess = class(TTyTag)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PressReleaseAt(X, Y: Integer);
    procedure PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
    { The size AutoSize would fit the pill to. Called directly rather than through
      AutoSize itself: LCL's AutoSizeDelayed suppresses every re-fit while the parent
      form has no handle (the headless runner never realises one), so driving AutoSize
      here would assert on inert plumbing instead of on this control's measurement. }
    procedure PreferredSize(out AWidth, AHeight: Integer);
  end;

function TTagAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TTagAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTagAccess.PressReleaseAt(X, Y: Integer);
begin
  PressAtReleaseAt(X, Y, X, Y);
end;

procedure TTagAccess.PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
begin
  MouseDown(mbLeft, [], ADownX, ADownY);
  // LCL synthesises Click BEFORE MouseUp, and only when the release is inside the
  // client rect (TControl.WMLButtonUp) — mirror both rules here.
  if (AUpX >= 0) and (AUpY >= 0) and (AUpX < Width) and (AUpY < Height) then
    Click;
  MouseUp(mbLeft, [], AUpX, AUpY);
end;

procedure TTagAccess.PreferredSize(out AWidth, AHeight: Integer);
begin
  AWidth := 0;
  AHeight := 0;
  CalculatePreferredSize(AWidth, AHeight, True);
end;

{ TTyTagLayoutTest }

procedure TTyTagLayoutTest.TestCaptionSpansPaddedBand;
var
  L: TTyTagLayout;
begin
  // 100 wide, pad 8/8, not closable -> the caption band is the pill inset by padding.
  L := TyTagLayout(100, 22, False, 8, 8, 4, 14);
  AssertEquals('caption starts at left padding', 8, L.CaptionRect.Left);
  AssertEquals('caption ends at right padding', 92, L.CaptionRect.Right);
  // The band is full-height; the painter centres the text in it vertically.
  AssertEquals('caption band top', 0, L.CaptionRect.Top);
  AssertEquals('caption band bottom', 22, L.CaptionRect.Bottom);
end;

procedure TTyTagLayoutTest.TestNotClosableHasNoSlot;
var
  L: TTyTagLayout;
begin
  L := TyTagLayout(100, 22, False, 8, 8, 4, 14);
  AssertEquals('no close slot when not closable', 0, L.CloseRect.Right - L.CloseRect.Left);
end;

procedure TTyTagLayoutTest.TestClosableSlotHugsRightOfBand;
var
  L: TTyTagLayout;
begin
  L := TyTagLayout(100, 22, True, 8, 8, 4, 14);
  // The slot's right edge is the content band's right edge (100 - 8), and it is
  // exactly ACloseSize wide.
  AssertEquals('slot right = band right', 92, L.CloseRect.Right);
  AssertEquals('slot left = band right - size', 78, L.CloseRect.Left);
  AssertEquals('slot is square-sized', 14, L.CloseRect.Right - L.CloseRect.Left);
end;

procedure TTyTagLayoutTest.TestSlotVerticallyCentred;
var
  L: TTyTagLayout;
begin
  // Height 22, slot 14 -> top = (22-14) div 2 = 4, bottom = 18.
  L := TyTagLayout(100, 22, True, 8, 8, 4, 14);
  AssertEquals('slot top centred', 4, L.CloseRect.Top);
  AssertEquals('slot bottom', 18, L.CloseRect.Bottom);
end;

procedure TTyTagLayoutTest.TestGapSeparatesCaptionAndSlot;
var
  L: TTyTagLayout;
begin
  // Gap 6: the caption must stop 6px short of the slot (slot left 78 -> caption right 72).
  L := TyTagLayout(100, 22, True, 8, 8, 6, 14);
  AssertEquals('slot left', 78, L.CloseRect.Left);
  AssertEquals('caption stops a gap before the slot', 72, L.CaptionRect.Right);
end;

procedure TTyTagLayoutTest.TestNarrowPillKeepsSlotDropsCaption;
var
  L: TTyTagLayout;
begin
  // Band = 24-8-8 = 8 px, narrower than the 14px slot. The x is the tag's only
  // affordance, so it keeps what there is and the caption collapses to nothing.
  L := TyTagLayout(24, 22, True, 8, 8, 4, 14);
  AssertEquals('slot clamped to the band left', 8, L.CloseRect.Left);
  AssertEquals('slot clamped to the band right', 16, L.CloseRect.Right);
  AssertEquals('caption dropped', 0, L.CaptionRect.Right - L.CaptionRect.Left);
end;

procedure TTyTagLayoutTest.TestSlotTallerThanPillIsClamped;
var
  L: TTyTagLayout;
begin
  // A 10px-tall pill can't hold a 14px slot: squash it into the height, never past it.
  L := TyTagLayout(100, 10, True, 8, 8, 4, 14);
  AssertEquals('slot top floors at 0', 0, L.CloseRect.Top);
  AssertEquals('slot bottom clamped to the height', 10, L.CloseRect.Bottom);
end;

procedure TTyTagLayoutTest.TestPaddingEatsWholePill;
var
  L: TTyTagLayout;
begin
  // Padding wider than the pill: nothing fits — both rects empty, never inverted.
  L := TyTagLayout(12, 22, True, 8, 8, 4, 14);
  AssertEquals('no caption', 0, L.CaptionRect.Right - L.CaptionRect.Left);
  AssertEquals('no slot', 0, L.CloseRect.Right - L.CloseRect.Left);
end;

procedure TTyTagLayoutTest.TestZeroSizeEmpty;
var
  L: TTyTagLayout;
begin
  L := TyTagLayout(0, 22, True, 8, 8, 4, 14);
  AssertEquals('zero width: no caption', 0, L.CaptionRect.Right - L.CaptionRect.Left);
  AssertEquals('zero width: no slot', 0, L.CloseRect.Right - L.CloseRect.Left);
  L := TyTagLayout(100, 0, True, 8, 8, 4, 14);
  AssertEquals('zero height: no caption', 0, L.CaptionRect.Right - L.CaptionRect.Left);
  AssertEquals('zero height: no slot', 0, L.CloseRect.Right - L.CloseRect.Left);
end;

procedure TTyTagLayoutTest.TestPreferredWidthRoundTripsPlain;
var
  w: Integer;
  L: TTyTagLayout;
begin
  // The contract: a pill of TyTagPreferredWidth(t) shows exactly t px of caption.
  w := TyTagPreferredWidth(50, False, 8, 8, 4, 14);
  AssertEquals('pad + text + pad', 66, w);
  L := TyTagLayout(w, 22, False, 8, 8, 4, 14);
  AssertEquals('caption fits exactly', 50, L.CaptionRect.Right - L.CaptionRect.Left);
end;

procedure TTyTagLayoutTest.TestPreferredWidthRoundTripsClosable;
var
  w: Integer;
  L: TTyTagLayout;
begin
  // Same round-trip with the slot reserved: pad + text + gap + slot + pad.
  w := TyTagPreferredWidth(50, True, 8, 8, 4, 14);
  AssertEquals('pad + text + gap + slot + pad', 84, w);
  L := TyTagLayout(w, 22, True, 8, 8, 4, 14);
  AssertEquals('caption still fits exactly', 50, L.CaptionRect.Right - L.CaptionRect.Left);
  AssertEquals('slot still full size', 14, L.CloseRect.Right - L.CloseRect.Left);
end;

{ TTyTagControlTest }

procedure TTyTagControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FClosed := 0;
  FClicked := 0;
  FAllowClose := True;
end;

procedure TTyTagControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyTagControlTest.HandleClose(Sender: TObject; var AllowClose: Boolean);
begin
  Inc(FClosed);
  AllowClose := FAllowClose;
end;

procedure TTyTagControlTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TTyTagControlTest.TestTypeKey;
var
  T: TTagAccess;
begin
  T := TTagAccess.Create(FForm);
  T.Parent := FForm;
  try
    AssertEquals('TyTag', T.StyleTypeKey);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestDefaults;
var
  T: TTyTag;
begin
  T := TTyTag.Create(FForm);
  try
    AssertEquals('default caption empty', '', T.Caption);
    AssertFalse('not closable by default', T.Closable);
    AssertEquals('default width 72', 72, T.Width);
    AssertEquals('default height 22', 22, T.Height);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestCloseRectEmptyWhenNotClosable;
var
  T: TTyTag;
  R: TRect;
begin
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }');
  T := TTyTag.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.SetBounds(0, 0, 100, 22);
    R := T.TyTagCloseRect;
    AssertEquals('no slot while Closable=False', 0, R.Right - R.Left);
    // Turning it on materialises the slot with no other change.
    T.Closable := True;
    R := T.TyTagCloseRect;
    AssertTrue('slot appears when Closable=True', R.Right > R.Left);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestCloseRectFollowsThemePadding;
var
  T: TTyTag;
  R: TRect;
begin
  // The slot's right edge is driven by the THEME's right padding, not a literal.
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 10px; }');
  T := TTyTag.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Closable := True;
    T.SetBounds(0, 0, 100, 22);
    R := T.TyTagCloseRect;
    AssertEquals('slot right = width - themed right padding', 90, R.Right);
    AssertEquals('slot is the default 14px slot', 14, R.Right - R.Left);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestCloseSizeMetricRetunesSlot;
var
  T: TTyTag;
  R: TRect;
begin
  // --tag-close-size is a skin-tunable metric: a theme that sets it moves the geometry
  // (and with it the hit-test), proving the slot size is not baked into the control.
  FCtl.LoadThemeCss(
    ':root { --tag-close-size: 20px; }' +
    'TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }');
  T := TTyTag.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Closable := True;
    T.SetBounds(0, 0, 100, 30);
    R := T.TyTagCloseRect;
    AssertEquals('slot takes the themed size', 20, R.Right - R.Left);
    AssertEquals('and is still right-aligned in the band', 92, R.Right);
    AssertEquals('re-centred for the new size', 5, R.Top);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestClickCloseFiresOnCloseAndHides;
var
  T: TTagAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Closable := True;
    T.SetBounds(0, 0, 100, 22);
    T.OnClose := @HandleClose;
    R := T.TyTagCloseRect;
    T.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose fired once', 1, FClosed);
    AssertFalse('default action hid the tag', T.Visible);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestCloseVetoKeepsTagVisible;
var
  T: TTagAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Closable := True;
    T.SetBounds(0, 0, 100, 22);
    T.OnClose := @HandleClose;
    FAllowClose := False;   // the host wants to own the tag's fate
    R := T.TyTagCloseRect;
    T.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose still fired', 1, FClosed);
    AssertTrue('veto suppressed the default hide', T.Visible);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestClickCloseDoesNotFireOnClick;
var
  T: TTagAccess;
  R: TRect;
begin
  // The whole point of the split gesture: "remove this tag" must not also read as
  // "the user clicked this tag" (a filter chip would toggle AND delete otherwise).
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Closable := True;
    T.SetBounds(0, 0, 100, 22);
    T.OnClose := @HandleClose;
    T.OnClick := @HandleClick;
    R := T.TyTagCloseRect;
    T.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose fired', 1, FClosed);
    AssertEquals('OnClick swallowed', 0, FClicked);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestClickBodyFiresOnClickNotOnClose;
var
  T: TTagAccess;
begin
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Closable := True;
    T.SetBounds(0, 0, 100, 22);
    T.OnClose := @HandleClose;
    T.OnClick := @HandleClick;
    T.PressReleaseAt(20, 11);   // well left of the slot (which starts at x=78)
    AssertEquals('OnClick fired', 1, FClicked);
    AssertEquals('OnClose did not', 0, FClosed);
    AssertTrue('tag still visible', T.Visible);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestDragOffCloseCancelsGesture;
var
  T: TTagAccess;
  R: TRect;
begin
  // Press the x, drag onto the caption, release: like any push button the gesture is
  // cancelled — no close, and no stray OnClick either (the press was never the pill's).
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Closable := True;
    T.SetBounds(0, 0, 100, 22);
    T.OnClose := @HandleClose;
    T.OnClick := @HandleClick;
    R := T.TyTagCloseRect;
    T.PressAtReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2, 20, 11);
    AssertEquals('no close', 0, FClosed);
    AssertEquals('no click', 0, FClicked);
    AssertTrue('tag still visible', T.Visible);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestUnclosableIgnoresClickWhereXWouldBe;
var
  T: TTagAccess;
begin
  // Closable=False: the same coordinates are ordinary pill surface, so they click.
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.SetBounds(0, 0, 100, 22);
    T.OnClose := @HandleClose;
    T.OnClick := @HandleClick;
    T.PressReleaseAt(85, 11);   // where the x sits on a closable tag
    AssertEquals('no close on a non-closable tag', 0, FClosed);
    AssertEquals('the press is a plain tag click', 1, FClicked);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestPreferredSizeHugsCaption;
var
  T: TTagAccess;
  wideW, narrowW, h: Integer;
begin
  // The pill measures its caption in the THEME's font, so a longer caption needs a
  // wider pill — and even a 1-glyph pill still clears its themed padding both sides.
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; font-size: 12px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Caption := 'W';
    T.PreferredSize(narrowW, h);
    T.Caption := 'a much longer tag caption';
    T.PreferredSize(wideW, h);
    AssertTrue('a longer caption needs a wider pill', wideW > narrowW);
    AssertTrue('pill clears its themed padding (8+8)', narrowW > 16);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestPreferredSizeGrowsForCloseSlot;
var
  T: TTagAccess;
  plainW, closableW, h: Integer;
begin
  // Turning Closable on widens the pill by exactly gap + slot, so the x is extra room
  // rather than room stolen from the caption.
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; font-size: 12px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Caption := 'draft';
    T.PreferredSize(plainW, h);
    T.Closable := True;
    T.PreferredSize(closableW, h);
    AssertEquals('grew by gap + slot', plainW + TyTagGap + TyTagCloseSize, closableW);
  finally
    T.Free;
  end;
end;

procedure TTyTagControlTest.TestPreferredHeightClearsCloseSlot;
var
  T: TTagAccess;
  w, plainH, closableH: Integer;
begin
  // Tags are padded 0px vertically, so a caption line alone is shorter than the 14px
  // slot: a closable pill must grow to clear it or TyTagLayout squashes the glyph.
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; font-size: 6px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Caption := 'x';
    T.PreferredSize(w, plainH);
    AssertTrue('a tiny-font pill is shorter than the slot', plainH < TyTagCloseSize);
    T.Closable := True;
    T.PreferredSize(w, closableH);
    AssertEquals('closable pill clears the slot', TyTagCloseSize, closableH);
  finally
    T.Free;
  end;
end;

{ TestPillRendersThemeBackground
  Theme: a strongly blue TyTag fill. Probe the pill's centre band and assert it is the
  themed fill — i.e. the pill paints from the token, not from an LCL colour. }
procedure TTyTagControlTest.TestPillRendersThemeBackground;
var
  T: TTagAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  FCtl.LoadThemeCss(
    'TyTag { background: #3B82F6; color: #FFFFFF; border-radius: 4px; padding: 0px 8px; font-size: 12px; }');
  Bmp := TBitmap.Create;
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Caption := 'tag';
    T.SetBounds(0, 0, 100, 22);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 22);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 100, 22);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 22), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Well inside the pill, clear of the rounded corners and of the caption glyphs.
      Px := Reread.GetPixel(6, 11);
      AssertTrue('pill painted in the themed accent fill',
        (Px.blue > 180) and (Px.red < 120));
    finally
      Reread.Free;
    end;
  finally
    T.Free;
    Bmp.Free;
  end;
end;

{ TestCloseGlyphRendersThemeInk
  TyTagClose sets its own colour: the x must take THAT ink (not the pill's caption
  colour), proving the glyph resolves from its own typeKey. }
procedure TTyTagControlTest.TestCloseGlyphRendersThemeInk;
var
  T: TTagAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  R: TRect;
  x, y: Integer;
  found: Boolean;
begin
  // White pill, white caption ink, GREEN x: any green pixel in the slot can only be
  // the TyTagClose colour.
  FCtl.LoadThemeCss(
    'TyTag { background: #FFFFFF; color: #FFFFFF; padding: 0px 8px; font-size: 12px; }' +
    'TyTagClose { color: #10B981; }');
  Bmp := TBitmap.Create;
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm;
    T.Controller := FCtl;
    T.Font.PixelsPerInch := 96;
    T.Caption := 'tag';
    T.Closable := True;
    T.SetBounds(0, 0, 100, 22);
    R := T.TyTagCloseRect;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(100, 22);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 100, 22);
    T.RenderTo(Bmp.Canvas, Rect(0, 0, 100, 22), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      found := False;
      for y := R.Top to R.Bottom - 1 do
        for x := R.Left to R.Right - 1 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('x drawn in the TyTagClose ink', found);
    finally
      Reread.Free;
    end;
  finally
    T.Free;
    Bmp.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): MouseDown ran `inherited` (setting FPressed) BEFORE the
  close hit-test, so PtOnClose resolved TyTag:active — whose padding moved the close rect off the
  painted (resting) x. A press on the visible x then read as a pill press. Hit-test must be
  resting. }
procedure TTyTagControlTest.TestCloseWorksUnderActiveStatePadding;
var
  T: TTagAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss('TyTag { background: #EEEEEE; color: #111111; padding: 0px 8px; }'
    + 'TyTag:active { background: #EEEEEE; padding: 0px 24px; }');
  T := TTagAccess.Create(FForm);
  try
    T.Parent := FForm; T.Controller := FCtl; T.Font.PixelsPerInch := 96;
    T.Closable := True; T.SetBounds(0, 0, 100, 22); T.OnClose := @HandleClose;
    R := T.TyTagCloseRect;   // resting (painted) slot
    T.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('a press on the visible x closes, despite :active padding', 1, FClosed);
  finally
    T.Free;
  end;
end;

initialization
  RegisterTest(TTyTagLayoutTest);
  RegisterTest(TTyTagControlTest);
end.
