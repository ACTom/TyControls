unit test.alert;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, TypInfo, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Painter, tyControls.Controller, tyControls.Alert;

type
  { Pure-rules tests: TyAlertVariant / TyAlertGlyph / TyAlertLayout / TyAlertPreferredHeight
    take only integers and enums, so they run with no window handle and no control at all. }
  TTyAlertLayoutTest = class(TTestCase)
  published
    procedure TestTypeMapsToVariantName;
    procedure TestTypeMapsToGlyph;
    procedure TestTextColumnSpansPaddedBand;
    procedure TestIconSlotHugsLeftOfBand;
    procedure TestNoIconSlotWhenHidden;
    procedure TestIconGapSeparatesIconAndText;
    procedure TestCloseSlotHugsRightOfBand;
    procedure TestNoCloseSlotWhenNotClosable;
    procedure TestCloseGapSeparatesTextAndSlot;
    procedure TestSlotsCentreOnMessageLine;
    procedure TestNoDescriptionRectWhenAbsent;
    procedure TestDescriptionSitsAGapBelowMessage;
    procedure TestTwoLineBlockCentredInPaddedBand;
    procedure TestNarrowBannerKeepsCloseDropsIconAndText;
    procedure TestSlotTallerThanBannerIsClamped;
    procedure TestPaddingEatsWholeBanner;
    procedure TestZeroSizeEmpty;
    procedure TestPreferredHeightRoundTripsOneLine;
    procedure TestPreferredHeightRoundTripsTwoLine;
    procedure TestPreferredHeightClearsIconSlot;
    procedure TestPreferredHeightClearsCloseSlot;
  end;

  { Headless control behaviour: typeKey, defaults, the type->variant wiring, theme-driven
    geometry, the close gesture (and its interaction with the banner's own OnClick),
    AutoSize, and graceful degradation when the theme leaves a key undefined. }
  TTyAlertControlTest = class(TTestCase)
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
    procedure TestStyleVariantFollowsAlertType;
    procedure TestUserStyleClassLayersOnTopOfVariant;
    procedure TestVariantPaintsItsOwnBackground;
    procedure TestCloseRectEmptyWhenNotClosable;
    procedure TestCloseRectFollowsThemePadding;
    procedure TestIconRectEmptyWhenShowIconFalse;
    procedure TestIconSizeMetricRetunesSlot;
    procedure TestClickCloseFiresOnCloseAndHides;
    procedure TestCloseWorksUnderActiveStatePadding;
    procedure TestBackgroundlessAlertIsInert;
    procedure TestCloseVetoKeepsAlertVisible;
    procedure TestClickCloseDoesNotFireOnClick;
    procedure TestClickBodyFiresOnClickNotOnClose;
    procedure TestDragOffCloseCancelsGesture;
    procedure TestPreferredHeightGrowsForDescription;
    procedure TestPreferredWidthIsUnconstrained;
    procedure TestBarRendersThemeBackground;
    procedure TestIconRendersThemeInk;
    procedure TestCloseGlyphRendersThemeInk;
    procedure TestUndefinedBarKeyDrawsNothing;
    procedure TestUndefinedCloseKeyFallsBackToBarInk;
  end;

implementation

const
  { The one CSS the control tests share: a plain bar with room for everything. Padding
    8/12 and a 12px font are the AntD-ish shape the geometry tests assume in miniature.
    NOTE every test that needs a themed value states it HERE (or in its own CSS): a user
    rule for a typeKey suppresses the whole built-in base layer, so nothing bleeds in. }
  cBarCss = 'TyAlert { background: #FFFFFF; color: #111111; padding: 8px 12px; font-size: 12px; }';

type
  { Reaches the protected paint + mouse seams. The mouse helpers drive the handlers in the
    SAME order LCL does (TControl.WMLButtonUp runs Click and only then DoMouseUp), which is
    exactly the ordering TTyAlert.Click relies on to swallow a close gesture. }
  TAlertAccess = class(TTyAlert)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PressReleaseAt(X, Y: Integer);
    procedure PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
    { The size AutoSize would fit the banner to. Called directly rather than through
      AutoSize itself: LCL's AutoSizeDelayed suppresses every re-fit while the parent form
      has no handle (the headless runner never realises one), so driving AutoSize here
      would assert on inert plumbing instead of on this control's measurement. }
    procedure PreferredSize(out AWidth, AHeight: Integer);
  end;

function TAlertAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TAlertAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TAlertAccess.PressReleaseAt(X, Y: Integer);
begin
  PressAtReleaseAt(X, Y, X, Y);
end;

procedure TAlertAccess.PressAtReleaseAt(ADownX, ADownY, AUpX, AUpY: Integer);
begin
  MouseDown(mbLeft, [], ADownX, ADownY);
  // LCL synthesises Click BEFORE MouseUp, and only when the release is inside the client
  // rect (TControl.WMLButtonUp) — mirror both rules here.
  if (AUpX >= 0) and (AUpY >= 0) and (AUpX < Width) and (AUpY < Height) then
    Click;
  MouseUp(mbLeft, [], AUpX, AUpY);
end;

procedure TAlertAccess.PreferredSize(out AWidth, AHeight: Integer);
begin
  AWidth := 0;
  AHeight := 0;
  CalculatePreferredSize(AWidth, AHeight, True);
end;

{ Render AAlert into a fresh WxH bitmap over a white backdrop and hand back a BGRA
  re-read of it. The caller frees the result. Every pixel probe below goes through this
  so they all share one backdrop and one AA bias. }
function RenderToBGRA(AAlert: TAlertAccess; AWidth, AHeight: Integer): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AWidth, AHeight);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, AWidth, AHeight);
    AAlert.RenderTo(Bmp.Canvas, Rect(0, 0, AWidth, AHeight), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ Is there a pixel inside ARect that is convincingly GREEN (#10B981-ish: green well ahead
  of both red and blue)? The probe every "…renders the themed ink" test uses — it asserts
  STRUCTURE (the themed ink reached these pixels), never a glyph's exact extents, which
  the headless runner's fallback font would make meaningless. }
function HasGreenInk(R: TBGRABitmap; const ARect: TRect): Boolean;
var
  x, y: Integer;
  Px: TBGRAPixel;
begin
  Result := False;
  for y := ARect.Top to ARect.Bottom - 1 do
    for x := ARect.Left to ARect.Right - 1 do
    begin
      if (x < 0) or (y < 0) or (x >= R.Width) or (y >= R.Height) then Continue;
      Px := R.GetPixel(x, y);
      if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
        Exit(True);
    end;
end;

{ TTyAlertLayoutTest }

procedure TTyAlertLayoutTest.TestTypeMapsToVariantName;
begin
  // These four strings ARE the theme's contract (TyAlert.info / .success / …): the theme
  // pass writes rules against them, so a rename here is a breaking change.
  AssertEquals('info', TyAlertVariant(atInfo));
  AssertEquals('success', TyAlertVariant(atSuccess));
  AssertEquals('warning', TyAlertVariant(atWarning));
  AssertEquals('error', TyAlertVariant(atError));
end;

procedure TTyAlertLayoutTest.TestTypeMapsToGlyph;
begin
  // The other half of what AlertType is FOR: it picks the mark the control draws.
  AssertTrue('info -> tgInfo', TyAlertGlyph(atInfo) = tgInfo);
  AssertTrue('success -> tgSuccess', TyAlertGlyph(atSuccess) = tgSuccess);
  AssertTrue('warning -> tgWarning', TyAlertGlyph(atWarning) = tgWarning);
  AssertTrue('error -> tgError', TyAlertGlyph(atError) = tgError);
end;

procedure TTyAlertLayoutTest.TestTextColumnSpansPaddedBand;
var
  L: TTyAlertLayout;
begin
  // 300 wide, pad 12/12, no icon, no x -> the text column is the banner inset by padding.
  L := TyAlertLayout(300, 40, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('text starts at left padding', 12, L.MessageRect.Left);
  AssertEquals('text ends at right padding', 288, L.MessageRect.Right);
end;

procedure TTyAlertLayoutTest.TestIconSlotHugsLeftOfBand;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, True, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('slot left = band left', 12, L.IconRect.Left);
  AssertEquals('slot is the given size', 16, L.IconRect.Right - L.IconRect.Left);
end;

procedure TTyAlertLayoutTest.TestNoIconSlotWhenHidden;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('no icon slot', 0, L.IconRect.Right - L.IconRect.Left);
  // …and the text reclaims the space the slot would have taken.
  AssertEquals('text starts at the band edge', 12, L.MessageRect.Left);
end;

procedure TTyAlertLayoutTest.TestIconGapSeparatesIconAndText;
var
  L: TTyAlertLayout;
begin
  // Icon 16 at x=12 ends at 28; gap 8 -> the text starts at 36.
  L := TyAlertLayout(300, 40, True, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('icon ends', 28, L.IconRect.Right);
  AssertEquals('text starts a gap after the icon', 36, L.MessageRect.Left);
end;

procedure TTyAlertLayoutTest.TestCloseSlotHugsRightOfBand;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, False, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('slot right = band right', 288, L.CloseRect.Right);
  AssertEquals('slot left = band right - size', 274, L.CloseRect.Left);
end;

procedure TTyAlertLayoutTest.TestNoCloseSlotWhenNotClosable;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('no close slot', 0, L.CloseRect.Right - L.CloseRect.Left);
  AssertEquals('text reaches the band edge', 288, L.MessageRect.Right);
end;

procedure TTyAlertLayoutTest.TestCloseGapSeparatesTextAndSlot;
var
  L: TTyAlertLayout;
begin
  // Slot left 274; close gap 8 -> the text stops at 266.
  L := TyAlertLayout(300, 40, False, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('text stops a gap before the slot', 266, L.MessageRect.Right);
end;

procedure TTyAlertLayoutTest.TestSlotsCentreOnMessageLine;
var
  L: TTyAlertLayout;
begin
  // One line: H=40, pad 8/8 -> avail 24, block 16 -> blockT = 8 + (24-16) div 2 = 12,
  // so the message line spans 12..28 and its centre is 20. A 16px icon slot centres on
  // 20 -> 12..28; a 14px close slot -> 13..27.
  L := TyAlertLayout(300, 40, True, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('message line top', 12, L.MessageRect.Top);
  AssertEquals('message line bottom', 28, L.MessageRect.Bottom);
  AssertEquals('icon centred on the message line', 12, L.IconRect.Top);
  AssertEquals('icon bottom', 28, L.IconRect.Bottom);
  AssertEquals('x centred on the message line', 13, L.CloseRect.Top);
  AssertEquals('x bottom', 27, L.CloseRect.Bottom);
end;

procedure TTyAlertLayoutTest.TestNoDescriptionRectWhenAbsent;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(300, 40, True, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('no description band', 0, L.DescriptionRect.Right - L.DescriptionRect.Left);
end;

procedure TTyAlertLayoutTest.TestDescriptionSitsAGapBelowMessage;
var
  L: TTyAlertLayout;
begin
  // Two lines of 16 with a 2px gap = a 34px block. H=60, pad 8/8 -> avail 44,
  // blockT = 8 + (44-34) div 2 = 13. Message 13..29, gap 2, description 31..47.
  L := TyAlertLayout(300, 60, True, True, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('message line', 13, L.MessageRect.Top);
  AssertEquals('message ends', 29, L.MessageRect.Bottom);
  AssertEquals('description starts a text-gap below', 31, L.DescriptionRect.Top);
  AssertEquals('description ends', 47, L.DescriptionRect.Bottom);
  // Both lines share the one text column.
  AssertEquals('same left edge', L.MessageRect.Left, L.DescriptionRect.Left);
  AssertEquals('same right edge', L.MessageRect.Right, L.DescriptionRect.Right);
end;

procedure TTyAlertLayoutTest.TestTwoLineBlockCentredInPaddedBand;
var
  L: TTyAlertLayout;
begin
  // The two-line form is where the "slots centre on the MESSAGE line" rule earns its
  // keep: the icon must sit beside the HEADLINE, not float between the two lines.
  L := TyAlertLayout(300, 60, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('icon tracks the message line, not the block centre', L.MessageRect.Top,
    L.IconRect.Top);
  AssertTrue('icon sits above the description', L.IconRect.Bottom <= L.DescriptionRect.Top);
  // The x centres on the same line (14 tall vs the line's 16 -> inset by 1).
  AssertEquals('x centred on the message line', 14, L.CloseRect.Top);
end;

procedure TTyAlertLayoutTest.TestNarrowBannerKeepsCloseDropsIconAndText;
var
  L: TTyAlertLayout;
begin
  // The priority chain, close > icon > text, at the two widths that exercise it.
  // W=54: band 12..42. The x (14) is served first and keeps its FULL slot at 28..42;
  // the close gap then leaves the text column at 12..20, so the icon is squeezed into
  // those 8px and the text collapses rather than showing a sliver.
  L := TyAlertLayout(54, 40, True, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('the x keeps its full slot', 14, L.CloseRect.Right - L.CloseRect.Left);
  AssertEquals('the x still hugs the band right', 42, L.CloseRect.Right);
  AssertEquals('the icon starts at the band edge', 12, L.IconRect.Left);
  AssertEquals('the icon takes only what is left', 20, L.IconRect.Right);
  AssertEquals('text dropped', 0, L.MessageRect.Right - L.MessageRect.Left);

  // W=40: band 12..28 — the x alone fills it, so even the icon goes. The x survives
  // whatever happens: it is the banner's only affordance.
  L := TyAlertLayout(40, 40, True, False, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('the x still keeps its full slot', 14, L.CloseRect.Right - L.CloseRect.Left);
  AssertEquals('icon dropped too', 0, L.IconRect.Right - L.IconRect.Left);
  AssertEquals('text still dropped', 0, L.MessageRect.Right - L.MessageRect.Left);
end;

procedure TTyAlertLayoutTest.TestSlotTallerThanBannerIsClamped;
var
  L: TTyAlertLayout;
begin
  // A 10px banner can't hold a 16px icon slot or a 14px x: squash them into the height,
  // never past it. The message line centres on 8, so the 16px icon wants -8..8 (floored
  // to 0) and the 14px x wants 1..15 (its bottom clamped) — neither escapes the banner.
  L := TyAlertLayout(300, 10, True, False, True, 12, 0, 12, 0, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('icon top floors at 0', 0, L.IconRect.Top);
  AssertEquals('icon bottom clamped to the height', 10, L.IconRect.Bottom);
  AssertEquals('x top', 1, L.CloseRect.Top);
  AssertEquals('x bottom clamped to the height', 10, L.CloseRect.Bottom);
end;

procedure TTyAlertLayoutTest.TestPaddingEatsWholeBanner;
var
  L: TTyAlertLayout;
begin
  // Padding wider than the banner: nothing fits — every rect empty, never inverted.
  L := TyAlertLayout(20, 40, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('no icon', 0, L.IconRect.Right - L.IconRect.Left);
  AssertEquals('no message', 0, L.MessageRect.Right - L.MessageRect.Left);
  AssertEquals('no description', 0, L.DescriptionRect.Right - L.DescriptionRect.Left);
  AssertEquals('no x', 0, L.CloseRect.Right - L.CloseRect.Left);
end;

procedure TTyAlertLayoutTest.TestZeroSizeEmpty;
var
  L: TTyAlertLayout;
begin
  L := TyAlertLayout(0, 40, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('zero width: no message', 0, L.MessageRect.Right - L.MessageRect.Left);
  AssertEquals('zero width: no x', 0, L.CloseRect.Right - L.CloseRect.Left);
  L := TyAlertLayout(300, 0, True, True, True, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('zero height: no message', 0, L.MessageRect.Right - L.MessageRect.Left);
  AssertEquals('zero height: no icon', 0, L.IconRect.Right - L.IconRect.Left);
end;

procedure TTyAlertLayoutTest.TestPreferredHeightRoundTripsOneLine;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // The contract: a banner of TyAlertPreferredHeight lands the text block exactly on its
  // padding. pad 8 + line 16 + pad 8 = 32.
  h := TyAlertPreferredHeight(False, False, False, 8, 8, 16, 16, 2, 16, 14);
  AssertEquals('pad + line + pad', 32, h);
  L := TyAlertLayout(300, h, False, False, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('message sits on the top padding', 8, L.MessageRect.Top);
  AssertEquals('and clears the bottom padding', h - 8, L.MessageRect.Bottom);
end;

procedure TTyAlertLayoutTest.TestPreferredHeightRoundTripsTwoLine;
var
  h: Integer;
  L: TTyAlertLayout;
begin
  // pad 8 + (16 + gap 2 + 16) + pad 8 = 50.
  h := TyAlertPreferredHeight(False, True, False, 8, 8, 16, 16, 2, 16, 14);
  AssertEquals('pad + line + gap + line + pad', 50, h);
  L := TyAlertLayout(300, h, False, True, False, 12, 8, 12, 8, 16, 16, 16, 8, 2, 8, 14);
  AssertEquals('message sits on the top padding', 8, L.MessageRect.Top);
  AssertEquals('description clears the bottom padding', h - 8, L.DescriptionRect.Bottom);
end;

procedure TTyAlertLayoutTest.TestPreferredHeightClearsIconSlot;
var
  plain, withIcon: Integer;
begin
  // A tiny line with no padding is shorter than the 16px icon slot: showing the icon must
  // grow the banner to clear it, or TyAlertLayout squashes the glyph.
  plain := TyAlertPreferredHeight(False, False, False, 0, 0, 6, 6, 2, 16, 14);
  AssertEquals('a bare 6px line', 6, plain);
  withIcon := TyAlertPreferredHeight(True, False, False, 0, 0, 6, 6, 2, 16, 14);
  AssertEquals('grew to clear the icon slot', 16, withIcon);
end;

procedure TTyAlertLayoutTest.TestPreferredHeightClearsCloseSlot;
var
  h: Integer;
begin
  h := TyAlertPreferredHeight(False, False, True, 0, 0, 6, 6, 2, 16, 14);
  AssertEquals('grew to clear the close slot', 14, h);
  // A banner already taller than both slots is not padded out to them.
  h := TyAlertPreferredHeight(True, False, True, 8, 8, 16, 16, 2, 16, 14);
  AssertEquals('no floor applied when the content is taller', 32, h);
end;

{ TTyAlertControlTest }

procedure TTyAlertControlTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FClosed := 0;
  FClicked := 0;
  FAllowClose := True;
end;

procedure TTyAlertControlTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

procedure TTyAlertControlTest.HandleClose(Sender: TObject; var AllowClose: Boolean);
begin
  Inc(FClosed);
  AllowClose := FAllowClose;
end;

procedure TTyAlertControlTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TTyAlertControlTest.TestTypeKey;
var
  A: TAlertAccess;
begin
  A := TAlertAccess.Create(FForm);
  A.Parent := FForm;
  try
    AssertEquals('TyAlert', A.StyleTypeKey);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestDefaults;
var
  A: TTyAlert;
begin
  A := TTyAlert.Create(FForm);
  try
    AssertTrue('type defaults to info', A.AlertType = atInfo);
    AssertEquals('no message', '', A.Message);
    AssertEquals('no description', '', A.Description);
    AssertFalse('one-line by default', A.HasDescription);
    AssertTrue('icon shown by default', A.ShowIcon);
    AssertFalse('not closable by default', A.Closable);
    AssertEquals('default width 320', 320, A.Width);
    AssertEquals('default height 40', 40, A.Height);
    AssertTrue('props published', IsPublishedProp(A, 'AlertType')
      and IsPublishedProp(A, 'Message') and IsPublishedProp(A, 'Description')
      and IsPublishedProp(A, 'ShowIcon') and IsPublishedProp(A, 'Closable'));
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestStyleVariantFollowsAlertType;
var
  A: TTyAlert;
begin
  A := TTyAlert.Create(FForm);
  try
    AssertEquals('info by default', 'info', A.StyleVariant);
    A.AlertType := atWarning;
    AssertEquals('the type owns the variant', 'warning', A.StyleVariant);
    A.AlertType := atError;
    AssertEquals('error', 'error', A.StyleVariant);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestUserStyleClassLayersOnTopOfVariant;
var
  A: TTyAlert;
begin
  // The documented interaction: the TYPE always contributes its variant token FIRST and a
  // user StyleClass is appended, so the semantic look can never be silently dropped while
  // an explicit class still layers over it per-property (the engine's ordinary cascade).
  A := TTyAlert.Create(FForm);
  try
    A.AlertType := atSuccess;
    A.StyleClass := 'compact';
    AssertEquals('type token first, user class after', 'success compact', A.StyleVariant);
    // Whitespace-only is not a token: it must not leave a trailing separator behind.
    A.StyleClass := '   ';
    AssertEquals('blank class adds nothing', 'success', A.StyleVariant);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestVariantPaintsItsOwnBackground;
var
  A: TAlertAccess;
  R: TBGRABitmap;
  Px: TBGRAPixel;
begin
  // Proof that AlertType really reaches the style resolve: the base rule is white and only
  // the .error variant is red, so a red bar can only have come from the type's token.
  FCtl.LoadThemeCss(cBarCss + 'TyAlert.error { background: #EF4444; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.AlertType := atError;
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      // Well inside the bar, clear of the icon slot and of any text.
      Px := R.GetPixel(150, 4);
      AssertTrue('the error variant painted its own fill',
        (Px.red > 180) and (Px.green < 120) and (Px.blue < 120));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestCloseRectEmptyWhenNotClosable;
var
  A: TTyAlert;
  R: TRect;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TTyAlert.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.SetBounds(0, 0, 300, 40);
    R := A.TyAlertCloseRect;
    AssertEquals('no slot while Closable=False', 0, R.Right - R.Left);
    // Turning it on materialises the slot with no other change.
    A.Closable := True;
    R := A.TyAlertCloseRect;
    AssertTrue('slot appears when Closable=True', R.Right > R.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestCloseRectFollowsThemePadding;
var
  A: TTyAlert;
  R: TRect;
begin
  // The slot's right edge is driven by the THEME's right padding, not a literal.
  FCtl.LoadThemeCss('TyAlert { background: #FFFFFF; color: #111111; padding: 8px 20px; font-size: 12px; }');
  A := TTyAlert.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    R := A.TyAlertCloseRect;
    AssertEquals('slot right = width - themed right padding', 280, R.Right);
    AssertEquals('slot is the default 14px slot', TyAlertCloseSize, R.Right - R.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestIconRectEmptyWhenShowIconFalse;
var
  A: TTyAlert;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TTyAlert.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.SetBounds(0, 0, 300, 40);
    AssertTrue('icon slot present by default', A.TyAlertIconRect.Right > A.TyAlertIconRect.Left);
    A.ShowIcon := False;
    AssertEquals('no icon slot once hidden', 0,
      A.TyAlertIconRect.Right - A.TyAlertIconRect.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestIconSizeMetricRetunesSlot;
var
  A: TTyAlert;
  R: TRect;
begin
  // --alert-icon-size is a skin-tunable metric: a theme that sets it moves the geometry,
  // proving the slot size is not baked into the control.
  FCtl.LoadThemeCss(':root { --alert-icon-size: 24px; }' + cBarCss);
  A := TTyAlert.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.SetBounds(0, 0, 300, 40);
    R := A.TyAlertIconRect;
    AssertEquals('slot takes the themed size', 24, R.Right - R.Left);
    AssertEquals('and still hugs the padded band left', 12, R.Left);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestClickCloseFiresOnCloseAndHides;
var
  A: TAlertAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    R := A.TyAlertCloseRect;
    A.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose fired once', 1, FClosed);
    AssertFalse('default action hid the banner', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestCloseVetoKeepsAlertVisible;
var
  A: TAlertAccess;
  R: TRect;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    FAllowClose := False;   // the host wants to own the banner's fate
    R := A.TyAlertCloseRect;
    A.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose still fired', 1, FClosed);
    AssertTrue('veto suppressed the default hide', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestClickCloseDoesNotFireOnClick;
var
  A: TAlertAccess;
  R: TRect;
begin
  // The whole point of the split gesture: "dismiss this notice" must not also read as
  // "the user clicked the notice" (a banner whose body opens a details pane otherwise
  // both dismisses AND navigates).
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    A.OnClick := @HandleClick;
    R := A.TyAlertCloseRect;
    A.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('OnClose fired', 1, FClosed);
    AssertEquals('OnClick swallowed', 0, FClicked);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestClickBodyFiresOnClickNotOnClose;
var
  A: TAlertAccess;
begin
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    A.OnClick := @HandleClick;
    A.PressReleaseAt(120, 20);   // mid-bar, far from the slot (which starts near x=274)
    AssertEquals('OnClick fired', 1, FClicked);
    AssertEquals('OnClose did not', 0, FClosed);
    AssertTrue('banner still visible', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestDragOffCloseCancelsGesture;
var
  A: TAlertAccess;
  R: TRect;
begin
  // Press the x, drag onto the message, release: like any push button the gesture is
  // cancelled — no close, and no stray OnClick either (the press was never the bar's).
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose;
    A.OnClick := @HandleClick;
    R := A.TyAlertCloseRect;
    A.PressAtReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2, 120, 20);
    AssertEquals('no close', 0, FClosed);
    AssertEquals('no click', 0, FClicked);
    AssertTrue('banner still visible', A.Visible);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestPreferredHeightGrowsForDescription;
var
  A: TAlertAccess;
  w, oneLine, twoLine: Integer;
begin
  // Setting a Description switches the banner to its two-line form, which must be taller
  // by exactly a text gap plus a line.
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'Disk almost full';
    A.PreferredSize(w, oneLine);
    A.Description := 'Free at least 2 GB to continue.';
    A.PreferredSize(w, twoLine);
    AssertTrue('the second line made the banner taller', twoLine > oneLine);
    // The exact growth: gap + one more line (both lines share the one TyAlert font, so
    // the extra line is the same height as the first).
    AssertEquals('grew by gap + a line', oneLine + TyAlertTextGap + (oneLine - 8 - 8),
      twoLine);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestPreferredWidthIsUnconstrained;
var
  A: TAlertAccess;
  w, h: Integer;
begin
  // AutoSize hugs the HEIGHT only. 0 is LCL's "no preferred width — keep the bounds you
  // were given", which is what lets a banner span its host via Align/Anchors.
  FCtl.LoadThemeCss(cBarCss);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'a rather long headline that would want a very wide banner indeed';
    A.PreferredSize(w, h);
    AssertEquals('no preferred width', 0, w);
    AssertTrue('but a real preferred height', h > 0);
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestBarRendersThemeBackground;
var
  A: TAlertAccess;
  R: TBGRABitmap;
  Px: TBGRAPixel;
begin
  // A strongly blue TyAlert fill: probe the bar and assert it is the themed fill — i.e.
  // the banner paints from the token, not from an LCL colour.
  FCtl.LoadThemeCss(
    'TyAlert { background: #3B82F6; color: #FFFFFF; border-radius: 4px; padding: 8px 12px; font-size: 12px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'heads up';
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      // Well inside the bar, clear of the rounded corners and of the glyphs.
      Px := R.GetPixel(150, 4);
      AssertTrue('bar painted in the themed fill', (Px.blue > 180) and (Px.red < 120));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestIconRendersThemeInk;
var
  A: TAlertAccess;
  R: TBGRABitmap;
begin
  // White bar, GREEN ink: any green pixel in the icon slot can only be the status glyph
  // drawn in the theme's colour. (Structure, not extents — see HasGreenInk.)
  FCtl.LoadThemeCss(
    'TyAlert { background: #FFFFFF; color: #10B981; padding: 8px 12px; font-size: 12px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.AlertType := atWarning;
    A.Message := 'heads up';
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertTrue('status glyph drawn in the themed ink', HasGreenInk(R, A.TyAlertIconRect));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestCloseGlyphRendersThemeInk;
var
  A: TAlertAccess;
  R: TBGRABitmap;
begin
  // White bar, white bar-ink, GREEN x: any green pixel in the slot can only be the
  // TyAlertClose colour — proving the x resolves from its OWN typeKey.
  FCtl.LoadThemeCss(
    'TyAlert { background: #FFFFFF; color: #FFFFFF; padding: 8px 12px; font-size: 12px; }' +
    'TyAlertClose { color: #10B981; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'heads up';
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertTrue('x drawn in the TyAlertClose ink', HasGreenInk(R, A.TyAlertCloseRect));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestUndefinedBarKeyDrawsNothing;
const
  // The ONLY difference between the two phases is the background declaration. Everything
  // that could draw green ink (the colour, the icon, the x) is identical in both.
  cInk = ' color: #10B981; padding: 8px 12px; font-size: 12px; }';
var
  A: TAlertAccess;
  R: TBGRABitmap;
  whole: TRect;
begin
  // Graceful degradation: a theme that touches TyAlert but gives it no `background` gets
  // NO banner rather than a hard-coded one. (A user rule for a typeKey suppresses the
  // whole built-in base layer, so this stays true once the theme pass ships a base
  // TyAlert rule — which is exactly why the rule here is present-but-backgroundless
  // rather than absent.)
  whole := Rect(0, 0, 300, 40);
  FCtl.LoadThemeCss('TyAlert {' + cInk);
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.AlertType := atError;
    A.Message := 'heads up';
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertFalse('an unbacked TyAlert key paints nothing at all', HasGreenInk(R, whole));
    finally
      R.Free;
    end;
    // …and adding the background — the ONE thing that was missing — brings the very same
    // ink back. Without this half, a broken green probe would pass the assertion above.
    FCtl.LoadThemeCss('TyAlert { background: #FFFFFF;' + cInk);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertTrue('a backed key paints that same ink', HasGreenInk(R, whole));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TTyAlertControlTest.TestUndefinedCloseKeyFallsBackToBarInk;
var
  A: TAlertAccess;
  R: TBGRABitmap;
begin
  // Graceful degradation for the SECONDARY key: TyAlertClose exists but sets no colour
  // and no background, so the x inherits the BAR's ink and gets no chip — never a
  // hard-coded colour. (Again a present-but-silent rule, so the built-in base layer is
  // suppressed and the assertion survives the theme pass.)
  FCtl.LoadThemeCss(
    'TyAlert { background: #FFFFFF; color: #10B981; padding: 8px 12px; font-size: 12px; }' +
    'TyAlertClose { border-radius: 3px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm;
    A.Controller := FCtl;
    A.Font.PixelsPerInch := 96;
    A.Message := 'heads up';
    A.Closable := True;
    A.SetBounds(0, 0, 300, 40);
    R := RenderToBGRA(A, 300, 40);
    try
      AssertTrue('the x fell back to the bar''s own ink',
        HasGreenInk(R, A.TyAlertCloseRect));
    finally
      R.Free;
    end;
  finally
    A.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): MouseDown ran `inherited` (which sets FPressed) BEFORE
  hit-testing the close x, so PtOnClose resolved the :active variant — whose padding moved the
  close rect off the painted (resting) x. A press squarely on the visible x then read as a body
  press and never closed. The hit-test must use the RESTING geometry. }
procedure TTyAlertControlTest.TestCloseWorksUnderActiveStatePadding;
var
  A: TAlertAccess;
  R: TRect;
begin
  // :active shifts the padding hard (12 -> 40). The x is PAINTED at rest; pressing it must close.
  FCtl.LoadThemeCss(cBarCss + 'TyAlert:active { background: #FFFFFF; padding: 8px 40px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm; A.Controller := FCtl; A.Font.PixelsPerInch := 96;
    A.Closable := True; A.SetBounds(0, 0, 300, 40); A.OnClose := @HandleClose;
    R := A.TyAlertCloseRect;   // the RESTING (painted) slot
    A.PressReleaseAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    AssertEquals('a press on the visible x closes, despite :active padding', 1, FClosed);
  finally
    A.Free;
  end;
end;

{ Adversarial-review finding (CONFIRMED): a background-less (theme-degraded) alert paints NOTHING
  but still swallowed clicks and could self-hide over the invisible x. Input must honour the
  paint's "no banner" decision. }
procedure TTyAlertControlTest.TestBackgroundlessAlertIsInert;
var
  A: TAlertAccess;
begin
  // Present-but-background-less (suppresses the base layer); Closable so an x would otherwise sit.
  FCtl.LoadThemeCss('TyAlert { color: #111111; padding: 8px 12px; font-size: 12px; }');
  A := TAlertAccess.Create(FForm);
  try
    A.Parent := FForm; A.Controller := FCtl; A.Font.PixelsPerInch := 96;
    A.Closable := True; A.SetBounds(0, 0, 300, 40);
    A.OnClose := @HandleClose; A.OnClick := @HandleClick;
    A.PressReleaseAt(150, 20);   // body
    A.PressReleaseAt(285, 20);   // where the invisible x's slot would be
    AssertEquals('an invisible banner fires no OnClick', 0, FClicked);
    AssertEquals('...and no OnClose', 0, FClosed);
    AssertTrue('...and did not hide itself', A.Visible);
  finally
    A.Free;
  end;
end;

initialization
  RegisterTest(TTyAlertLayoutTest);
  RegisterTest(TTyAlertControlTest);
end.
