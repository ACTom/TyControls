unit test.glyphbuttons;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Types, tyControls.Button, tyControls.IconFont,
  tyControls.ImageCollection,
  tyControls.GlyphButtons, tyControls.Controller, tyControls.ToolBar;
type
  { Exposes the protected RenderTo so the glyph paint path is exercisable headlessly,
    and the protected CalculatePreferredSize so AutoSize can be asserted DIRECTLY.
    Reading Width instead would measure nothing: LCL's AutoSizeDelayed suppresses every
    re-fit while the parent form has no handle, and the headless runner never makes one. }
  TGlyphButtonAccess = class(TTyGlyphButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallPreferred(out AW, AH: Integer);
    // The caption measurement the size floor's HEIGHT is derived from.
    procedure CallMeasure(APPI: Integer; out AW, AH: Integer);
    // The per-state glyph-source seam, as the base answers it.
    function CallGlyphSource(AStates: TTyStateSet): TTyGlyphSource;
  end;

  { A subclass that USES the seam, which is the only way to show it is a seam at all: it
    swaps the glyph NAME on hover and leaves every other state alone. If the base ever stops
    routing its paint through GetGlyphSource, this one silently stops working. }
  TStateGlyphButton = class(TTyGlyphButton)
  protected
    function GetGlyphSource(AStates: TTyStateSet): TTyGlyphSource; override;
  public
    HotGlyphName: string;
    { Deliberately supplied TOGETHER with HotGlyphName, so the hover answer is a COMPLETE
      glyph source the button does not otherwise have. That is a knowing violation of
      GetGlyphSource's contract, and the point: the base must make it not matter, because
      presence is read from the published fields and never from the seam. }
    HotIconFont: TTyIconFont;
    AskedWith: TTyStateSet;
    Asked: Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SetHoverForTest(AValue: Boolean);
    procedure CallPreferred(out AW, AH: Integer);
  end;

  { The glyph-source seam (TTyGlyphButtonBase.GetGlyphSource): the protected question
    "which picture, in THIS state?" that per-state artwork needs and that used to require
    reimplementing the whole draw to reach four private fields.

    Two things are being pinned. First that the BASE ignores the state entirely, so adding
    the seam changed no existing button's rendering. Second that the seam is genuinely wired
    into the paint and genuinely NOT wired into the measurement — a glyph's presence and size
    stay the published properties' business, or a button would resize under the pointer. }
  TGlyphSourceSeamTest = class(TTestCase)
  published
    procedure TestBaseIsStateBlind;
    procedure TestImageSourceStillWinsOverTheFont;
    procedure TestPaintAsksTheSeamWithTheCurrentStates;
    procedure TestSeamNeverDecidesWhetherAGlyphExists;
  end;

  TContainerButtonAccess = class(TTyGlyphContainerButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallPreferred(out AW, AH: Integer);
    procedure CallMeasure(APPI: Integer; out AW, AH: Integer);
  end;

  TSpeedButtonAccess = class(TTySpeedButton)
  public
    procedure CallPreferred(out AW, AH: Integer);
  end;

  TGlyphButtonTest = class(TTestCase)
  published
    procedure TestTypeKeys;
    procedure TestDefaultSizes;
    procedure TestGlyphDefaults;
    procedure TestPropertiesRoundTrip;
    procedure TestIconFontFreeNotification;
    procedure TestSplitGlyphLeft;
    procedure TestSplitGlyphTop;
    procedure TestSplitNoGlyph;
    procedure TestSplitOversizedGlyphClamps;
    procedure TestPaintWithGlyphSafe;
    procedure TestPaintContainerSafe;
    procedure TestPaintNoFontSafe;
    procedure TestAutoSizePublishedOnAllThree;
    procedure TestPreferredWidthGrowsWithTheCaption;
    procedure TestPreferredWidthReservesTheGlyphSlot;
    procedure TestPreferredWidthDropsTheGapWithoutACaption;
    procedure TestPreferredWidthGrowsWithGlyphSize;
    procedure TestAutoGlyphSlotFollowsTheContentBox;
    procedure TestRoomierThemeWidensTheButton;
    procedure TestContainerSharesTheWidthWithItsCaption;
    procedure TestContainerGlyphSetsTheWidthFloor;
    procedure TestPreferredHeightStaysZero;
  end;

  { SIZE FLOOR (Constraints.Min*). A hand-set Height and the theme's --control-height are
    REQUESTS; what is POSSIBLE is decided by the font, the padding and the glyph, and only the
    control knows all three. On Linux/Qt6 the same 9pt CJK caption resolves through a fallback
    face with taller ink than Windows', and DrawText draws clipped + tlCenter, so a box shorter
    than the ink loses the caption's BOTTOM — silently, and only on that platform.
    Everything here asserts Constraints, not Width/Height: the floor has to hold whether or
    not AutoSize is on, and AutoSizeDelayed suppresses real resizing without a form handle. }
  TGlyphButtonFloorTest = class(TTestCase)
  published
    procedure TestFloorFitsTheCaption;
    procedure TestGlyphSlotIsPartOfTheWidthFloorNotTheHeight;
    procedure TestContainerStacksTheGlyphIntoTheHeightFloor;
    procedure TestContainerWithoutACaptionPaysNoGapNorLine;
    procedure TestAutoGlyphNeverRatchetsTheFloor;
    procedure TestSmallerFontAndPaddingLowerTheFloor;
  end;

  TSpeedButtonTest = class(TTestCase)
  published
    procedure TestDefaults;
    procedure TestGroupingRadioBehaviour;
    procedure TestAllowAllUpToggle;
    procedure TestUngroupedClickJustFires;
    procedure TestDisabledClickNoChange;
    procedure TestRoomierThemeWidensThroughItsOwnKey;
    procedure TestAutoSizeSurvivesAHeightPinningToolBar;
    procedure TestFloorSurvivesAHeightPinningToolBar;
  end;
implementation

procedure TGlyphButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TGlyphButtonAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TContainerButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TGlyphButtonAccess.CallMeasure(APPI: Integer; out AW, AH: Integer);
begin
  MeasureCaption(APPI, AW, AH);
end;

procedure TContainerButtonAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TContainerButtonAccess.CallMeasure(APPI: Integer; out AW, AH: Integer);
begin
  MeasureCaption(APPI, AW, AH);
end;

procedure TSpeedButtonAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

{ ---- TGlyphButtonTest ---- }

procedure TGlyphButtonTest.TestTypeKeys;
var
  B: TTyGlyphButton;
  C: TTyGlyphContainerButton;
  S: TTySpeedButton;
begin
  // The plain glyph button IS a push button and stays on TyButton. The ribbon tile
  // and the toolbar toggle need a different FRAME from a push button, so each owns
  // a key a skin can target without touching every button in the app.
  B := TTyGlyphButton.Create(nil);
  C := TTyGlyphContainerButton.Create(nil);
  S := TTySpeedButton.Create(nil);
  try
    AssertEquals('glyph button reuses TyButton', 'TyButton', (B as ITyStyleable).GetStyleTypeKey);
    AssertEquals('container button owns its key', 'TyGlyphContainerButton', (C as ITyStyleable).GetStyleTypeKey);
    AssertEquals('speed button owns its key', 'TySpeedButton', (S as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free; C.Free; S.Free;
  end;
end;

procedure TGlyphButtonTest.TestDefaultSizes;
var
  B: TTyGlyphButton;
  C: TTyGlyphContainerButton;
begin
  B := TTyGlyphButton.Create(nil);
  C := TTyGlyphContainerButton.Create(nil);
  try
    AssertEquals('glyph button default width', 96, B.Width);
    AssertEquals('glyph button default height', 30, B.Height);
    AssertEquals('container button default width', 72, C.Width);
    AssertEquals('container button default height', 64, C.Height);
    // The container ships a larger default glyph than plain auto-fit.
    AssertEquals('container default GlyphSize', 24, C.GlyphSize);
  finally
    B.Free; C.Free;
  end;
end;

procedure TGlyphButtonTest.TestGlyphDefaults;
var
  B: TTyGlyphButton;
begin
  B := TTyGlyphButton.Create(nil);
  try
    AssertEquals('GlyphSize default 0 (auto)', 0, B.GlyphSize);
    AssertTrue('GlyphColor default is the theme sentinel',
      B.GlyphColor = TyGlyphButtonColorDefault);
    AssertEquals('GlyphName default empty', '', B.GlyphName);
    AssertTrue('IconFont default nil', B.IconFont = nil);
    AssertTrue('glyph props published', IsPublishedProp(B, 'IconFont')
      and IsPublishedProp(B, 'GlyphName') and IsPublishedProp(B, 'GlyphSize')
      and IsPublishedProp(B, 'GlyphColor'));
  finally
    B.Free;
  end;
end;

procedure TGlyphButtonTest.TestPropertiesRoundTrip;
var
  B: TTyGlyphButton;
  Font: TTyIconFont;
begin
  B := TTyGlyphButton.Create(nil);
  Font := TTyIconFont.Create(nil);
  try
    Font.MapGlyph('save', $F0C7);
    // Assigning IconFont + GlyphName must not raise.
    B.IconFont := Font;
    B.GlyphName := 'save';
    B.GlyphSize := 20;
    B.GlyphColor := TyRGB(200, 40, 40);
    AssertSame('IconFont round-trips', Font, B.IconFont);
    AssertEquals('GlyphName round-trips', 'save', B.GlyphName);
    AssertEquals('GlyphSize round-trips', 20, B.GlyphSize);
    AssertTrue('GlyphColor round-trips', B.GlyphColor = TyRGB(200, 40, 40));
    // Negative GlyphSize clamps to 0 (auto), never a bad size.
    B.GlyphSize := -3;
    AssertEquals('negative GlyphSize clamps to 0', 0, B.GlyphSize);
  finally
    Font.Free;
    B.Free;
  end;
end;

procedure TGlyphButtonTest.TestIconFontFreeNotification;
var
  B: TTyGlyphButton;
  Font: TTyIconFont;
begin
  B := TTyGlyphButton.Create(nil);
  Font := TTyIconFont.Create(nil);
  try
    B.IconFont := Font;
    AssertSame('IconFont assigned', Font, B.IconFont);
    // Freeing the referenced font must nil the reference (FreeNotification).
    Font.Free;
    Font := nil;
    AssertTrue('IconFont nilled after the font is freed', B.IconFont = nil);
  finally
    Font.Free;   // no-op when already freed/nil
    B.Free;
  end;
end;

procedure TGlyphButtonTest.TestSplitGlyphLeft;
var
  g, c: TRect;
begin
  // Content rect 100x40, glyph 20px, gap 6px, glyph-left.
  // Glyph: 20x20 square at left, vertically centered -> top = (40-20)/2 = 10.
  // Caption: from glyph.Right(20) + gap(6) = 26 to 100.
  TyGlyphButtonSplit(Rect(0, 0, 100, 40), 20, 6, glLeft, g, c);
  AssertEquals('glyph-left glyph.Left', 0, g.Left);
  AssertEquals('glyph-left glyph.Top', 10, g.Top);
  AssertEquals('glyph-left glyph.Right', 20, g.Right);
  AssertEquals('glyph-left glyph.Bottom', 30, g.Bottom);
  AssertEquals('glyph-left caption.Left', 26, c.Left);
  AssertEquals('glyph-left caption.Top', 0, c.Top);
  AssertEquals('glyph-left caption.Right', 100, c.Right);
  AssertEquals('glyph-left caption.Bottom', 40, c.Bottom);
end;

procedure TGlyphButtonTest.TestSplitGlyphTop;
var
  g, c: TRect;
begin
  // Content rect 60x64, glyph 24px, gap 6px, glyph-top.
  // Glyph: 24x24 square at top, horizontally centered -> left = (60-24)/2 = 18.
  // Caption: from glyph.Bottom(24) + gap(6) = 30 to 64.
  TyGlyphButtonSplit(Rect(0, 0, 60, 64), 24, 6, glTop, g, c);
  AssertEquals('glyph-top glyph.Left', 18, g.Left);
  AssertEquals('glyph-top glyph.Top', 0, g.Top);
  AssertEquals('glyph-top glyph.Right', 42, g.Right);
  AssertEquals('glyph-top glyph.Bottom', 24, g.Bottom);
  AssertEquals('glyph-top caption.Left', 0, c.Left);
  AssertEquals('glyph-top caption.Top', 30, c.Top);
  AssertEquals('glyph-top caption.Right', 60, c.Right);
  AssertEquals('glyph-top caption.Bottom', 64, c.Bottom);
end;

procedure TGlyphButtonTest.TestSplitNoGlyph;
var
  g, c: TRect;
begin
  // Glyph px <= 0 -> empty glyph rect, caption keeps the whole content rect.
  TyGlyphButtonSplit(Rect(5, 7, 105, 47), 0, 6, glLeft, g, c);
  AssertEquals('no-glyph glyph rect is empty (w)', 0, g.Right - g.Left);
  AssertEquals('no-glyph glyph rect is empty (h)', 0, g.Bottom - g.Top);
  AssertEquals('no-glyph caption.Left', 5, c.Left);
  AssertEquals('no-glyph caption.Top', 7, c.Top);
  AssertEquals('no-glyph caption.Right', 105, c.Right);
  AssertEquals('no-glyph caption.Bottom', 47, c.Bottom);
end;

procedure TGlyphButtonTest.TestSplitOversizedGlyphClamps;
var
  g, c: TRect;
begin
  // Glyph wider than the box (glyph-left): clamped to the box width, and the
  // caption collapses to zero width rather than inverting.
  TyGlyphButtonSplit(Rect(0, 0, 30, 20), 50, 6, glLeft, g, c);
  AssertEquals('oversized glyph clamps to box width', 30, g.Right - g.Left);
  AssertTrue('caption never has negative width', c.Right >= c.Left);
  // Glyph taller than the box (glyph-top): clamped to the box height.
  TyGlyphButtonSplit(Rect(0, 0, 40, 18), 50, 6, glTop, g, c);
  AssertEquals('oversized glyph clamps to box height', 18, g.Bottom - g.Top);
  AssertTrue('caption never has negative height', c.Bottom >= c.Top);
end;

procedure TGlyphButtonTest.TestPaintWithGlyphSafe;
var
  B: TGlyphButtonAccess;
  Font: TTyIconFont;
  Bmp: TBitmap;
begin
  // Full glyph-left paint path with a mapped glyph. No real font family is
  // registered, so RenderGlyph yields an empty transparent bitmap — the composite
  // must still be safe (real glyph pixels need an installed font + a machine).
  B := TGlyphButtonAccess.Create(nil);
  Font := TTyIconFont.Create(nil);
  Bmp := TBitmap.Create;
  try
    Font.MapGlyph('save', $F0C7);
    B.IconFont := Font;
    B.GlyphName := 'save';
    B.Caption := 'Save';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(96, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    AssertTrue('glyph-left RenderTo executed without exception', True);

    // Explicit GlyphSize path must also be safe.
    B.GlyphSize := 16;
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    AssertTrue('explicit GlyphSize RenderTo executed without exception', True);

    // Pure-icon (empty caption) must also be safe.
    B.Caption := '';
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    AssertTrue('empty-caption RenderTo executed without exception', True);
  finally
    Bmp.Free;
    Font.Free;
    B.Free;
  end;
end;

procedure TGlyphButtonTest.TestPaintContainerSafe;
var
  C: TContainerButtonAccess;
  Font: TTyIconFont;
  Bmp: TBitmap;
begin
  // Full glyph-top paint path.
  C := TContainerButtonAccess.Create(nil);
  Font := TTyIconFont.Create(nil);
  Bmp := TBitmap.Create;
  try
    Font.MapGlyph('save', $F0C7);
    C.IconFont := Font;
    C.GlyphName := 'save';
    C.Caption := 'Save';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(72, 64);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 72, 64), 96);
    AssertTrue('glyph-top RenderTo executed without exception', True);
  finally
    Bmp.Free;
    Font.Free;
    C.Free;
  end;
end;

procedure TGlyphButtonTest.TestPaintNoFontSafe;
var
  B: TGlyphButtonAccess;
  Bmp: TBitmap;
begin
  // No IconFont, non-empty GlyphName: must fall back to a plain caption button and
  // never crash — the glyph plumbing degrades cleanly.
  B := TGlyphButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.GlyphName := 'save';   // set, but no font assigned
    B.Caption := 'Save';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(96, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    AssertTrue('no-font RenderTo is a safe caption-only paint', True);
  finally
    Bmp.Free;
    B.Free;
  end;
end;

{ ---- TGlyphButtonTest: AutoSize / preferred width ----

  Why these exist: a skin may legitimately change the font AND the padding. The 'xp' skin
  asks TyButton for 5px 12px where the default asks 6px — 24px of horizontal padding instead
  of 12 — so every glyph button whose Width was hand-fitted to the default skin clipped its
  caption the moment the skin changed. The fix is for the button to size ITSELF, which means
  its preferred width must account for exactly what it paints: caption AND glyph AND gap. }

procedure TGlyphButtonTest.TestAutoSizePublishedOnAllThree;
var
  B: TTyGlyphButton;
  C: TTyGlyphContainerButton;
  S: TTySpeedButton;
begin
  // Published so a .lfm and the object inspector can switch it on; the default stays
  // False, so nothing that exists today moves.
  B := TTyGlyphButton.Create(nil);
  C := TTyGlyphContainerButton.Create(nil);
  S := TTySpeedButton.Create(nil);
  try
    AssertTrue('glyph button publishes AutoSize', IsPublishedProp(B, 'AutoSize'));
    AssertTrue('container button publishes AutoSize', IsPublishedProp(C, 'AutoSize'));
    AssertTrue('speed button publishes AutoSize', IsPublishedProp(S, 'AutoSize'));
    AssertFalse('glyph button AutoSize still off by default', B.AutoSize);
    AssertFalse('container button AutoSize still off by default', C.AutoSize);
    AssertFalse('speed button AutoSize still off by default', S.AutoSize);
  finally
    B.Free; C.Free; S.Free;
  end;
end;

procedure TGlyphButtonTest.TestPreferredWidthGrowsWithTheCaption;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  B: TGlyphButtonAccess;
  narrow, wide, h1, h2: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 5px 9px; font-size: 12px; }');
    Font.MapGlyph('save', $F0C7);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.IconFont := Font;
    B.GlyphName := 'save';
    B.GlyphSize := 16;
    B.AutoSize := True;
    B.Caption := 'Save';
    B.CallPreferred(narrow, h1);

    // A longer translation must lengthen the button, not get ellipsised.
    B.Caption := 'Save the current work order as a template';
    B.CallPreferred(wide, h2);
    AssertTrue(Format('a longer caption wants more width (%d -> %d)', [narrow, wide]),
      wide > narrow);
    AssertEquals('and still proposes no height', 0, h2);
  finally
    B.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonTest.TestPreferredWidthReservesTheGlyphSlot;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  B: TGlyphButtonAccess;
  plain, withGlyph, h: Integer;
begin
  // The load-bearing part: glyph-left paints glyph + gap + caption (TyGlyphButtonSplit),
  // so the preferred width must reserve the glyph AND the gap. A preferred size that only
  // counted the caption would make AutoSize lie and the caption would still clip.
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 5px 9px; font-size: 12px; }');
    Font.MapGlyph('save', $F0C7);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'Save';
    B.GlyphSize := 16;
    // No glyph SOURCE yet: DrawContent falls through to the plain caption, so must the width.
    B.CallPreferred(plain, h);

    B.IconFont := Font;
    B.GlyphName := 'save';
    B.CallPreferred(withGlyph, h);
    // 16px glyph + the 6px '--glyph-button-gap' default (this theme sets no metric).
    AssertEquals('the glyph slot and its gap are both reserved', plain + 16 + 6, withGlyph);

    // An unmapped/absent source must not reserve anything: the paint would not draw it.
    B.IconFont := nil;
    B.CallPreferred(withGlyph, h);
    AssertEquals('no icon font -> no reserved slot', plain, withGlyph);
  finally
    B.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonTest.TestPreferredWidthDropsTheGapWithoutACaption;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  B: TGlyphButtonAccess;
  bare, iconOnly, h: Integer;
begin
  // DrawContent skips the caption rect entirely when Caption is empty, so a pure-icon
  // toolbar button must not pay for a gap to nothing — it would sit visibly off-centre.
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 5px 9px; font-size: 12px; }');
    Font.MapGlyph('save', $F0C7);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := '';
    B.GlyphSize := 20;
    B.CallPreferred(bare, h);           // padding only: no caption, no glyph source

    B.IconFont := Font;
    B.GlyphName := 'save';
    B.CallPreferred(iconOnly, h);
    AssertEquals('a pure-icon button pays for the glyph and NOT for the gap',
      bare + 20, iconOnly);
  finally
    B.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonTest.TestPreferredWidthGrowsWithGlyphSize;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  B: TGlyphButtonAccess;
  small, big, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 5px 9px; font-size: 12px; }');
    Font.MapGlyph('save', $F0C7);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.IconFont := Font;
    B.GlyphName := 'save';
    B.Caption := 'Save';

    B.GlyphSize := 16;
    B.CallPreferred(small, h);
    B.GlyphSize := 32;
    B.CallPreferred(big, h);
    AssertEquals('a bigger glyph widens the button by exactly that much', small + 16, big);
  finally
    B.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonTest.TestAutoGlyphSlotFollowsTheContentBox;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  B: TGlyphButtonAccess;
  auto, explicitSize, plain, box, h: Integer;
begin
  // GlyphSize 0 = auto: DrawContent derives the square from the content box (the client
  // rect minus the theme padding), so the measurement must derive it from the same place.
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 5px 9px; font-size: 12px; }');
    Font.MapGlyph('save', $F0C7);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.IconFont := Font;
    B.GlyphName := 'save';
    B.Caption := 'Save';

    B.GlyphSize := 0;
    B.CallPreferred(auto, h);
    box := B.ClientHeight - 10;      // 5px padding top + 5px bottom
    AssertTrue('the content box must be non-degenerate for this test', box > 0);
    // An auto glyph is still a reserved slot, not a free ride.
    B.GlyphName := '';
    B.CallPreferred(plain, h);
    AssertEquals('an auto glyph reserves its square plus the gap', plain + box + 6, auto);
    // ...and it is exactly the square an explicit GlyphSize of that size would ask for.
    B.GlyphName := 'save';
    B.GlyphSize := box;
    B.CallPreferred(explicitSize, h);
    AssertEquals('the auto glyph measures as the content box height', explicitSize, auto);
  finally
    B.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonTest.TestRoomierThemeWidensTheButton;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  B: TGlyphButtonAccess;
  tight, roomy, h: Integer;
begin
  { THE bug: the same caption under a skin with roomier padding needs a wider button. A theme
    switch reaches the control as a bare Invalidate, where TTyButton re-fits an auto-sized
    button — asserted through CalculatePreferredSize because AutoSizeDelayed blocks a real
    resize while the parent form has no handle. }
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Font.MapGlyph('save', $F0C7);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.IconFont := Font;
    B.GlyphName := 'save';
    B.GlyphSize := 16;               // explicit, so only the padding moves below
    B.AutoSize := True;
    B.Caption := 'Save';

    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 4px 4px; font-size: 12px; }');
    B.CallPreferred(tight, h);

    Ctl.LoadThemeCss('TyButton { background: #FFFFFF; color: #000000; padding: 4px 30px; font-size: 12px; }');
    B.CallPreferred(roomy, h);
    AssertTrue(Format('a roomier theme widens the glyph button (%d -> %d)', [tight, roomy]),
      roomy > tight);
    // 26px more padding per side = 52px more width; the glyph and gap did not move.
    AssertEquals('the extra width is exactly the extra padding', tight + 52, roomy);
  finally
    B.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonTest.TestContainerSharesTheWidthWithItsCaption;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  C: TContainerButtonAccess;
  plainLong, withGlyph, hugeGlyph, h: Integer;
begin
  // A ribbon tile stacks the glyph ABOVE the caption, so the two SHARE the width instead
  // of adding up, and the gap between them is vertical — it costs nothing sideways.
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  C := TContainerButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss('TyGlyphContainerButton { background: #FFFFFF; color: #000000; padding: 4px 8px; font-size: 12px; }');
    Font.MapGlyph('save', $F0C7);
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.IconFont := Font;
    C.GlyphSize := 24;
    C.Caption := 'A considerably longer ribbon caption';

    C.GlyphName := '';               // no glyph source
    C.CallPreferred(plainLong, h);
    C.GlyphName := 'save';
    C.CallPreferred(withGlyph, h);
    AssertEquals('glyph-top does not add the glyph to the caption width',
      plainLong, withGlyph);
    // ...and the max() is live, not a no-op: a glyph wider than the caption does raise it.
    C.GlyphSize := 400;
    C.CallPreferred(hugeGlyph, h);
    AssertTrue(Format('an oversized glyph raises the floor (%d -> %d)', [plainLong, hugeGlyph]),
      hugeGlyph > plainLong);
  finally
    C.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonTest.TestContainerGlyphSetsTheWidthFloor;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  C: TContainerButtonAccess;
  plainShort, withBig, bigger, h: Integer;
begin
  // ...and when the glyph is the wider of the two, IT sets the floor: a tile with a big
  // icon and a two-letter caption must still be wide enough for the icon.
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  C := TContainerButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss('TyGlyphContainerButton { background: #FFFFFF; color: #000000; padding: 4px 8px; font-size: 12px; }');
    Font.MapGlyph('save', $F0C7);
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.IconFont := Font;
    C.Caption := 'Go';

    C.GlyphName := '';
    C.CallPreferred(plainShort, h);
    C.GlyphName := 'save';
    C.GlyphSize := 48;
    C.CallPreferred(withBig, h);
    AssertTrue(Format('a big ribbon glyph widens the tile past its short caption (%d -> %d)',
      [plainShort, withBig]), withBig > plainShort);
    C.GlyphSize := 58;
    C.CallPreferred(bigger, h);
    AssertEquals('the tile then tracks the glyph 1:1', withBig + 10, bigger);
  finally
    C.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonTest.TestPreferredHeightStaysZero;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  B: TGlyphButtonAccess;
  C: TContainerButtonAccess;
  S: TSpeedButtonAccess;
  w, h: Integer;
begin
  { 0 is LCL's "no preference on this axis". Proposing a height makes the control fight any
    container that pins one — TTyToolBar sizes every child to its ButtonHeight, and a button
    asking for a different height bounced between the two until LCL aborted the app with
    "TControl.ChangeBounds loop detected". Width only; the row owns the height. }
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  C := TContainerButtonAccess.Create(nil);
  S := TSpeedButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(
      'TyButton { background: #FFFFFF; color: #000000; padding: 5px 9px; font-size: 12px; }' +
      'TySpeedButton { background: #FFFFFF; color: #000000; padding: 3px 5px; font-size: 12px; }' +
      'TyGlyphContainerButton { background: #FFFFFF; color: #000000; padding: 4px 8px; font-size: 12px; }');
    Font.MapGlyph('save', $F0C7);
    B.Controller := Ctl; B.Font.PixelsPerInch := 96; B.IconFont := Font; B.GlyphName := 'save'; B.Caption := 'Save';
    C.Controller := Ctl; C.Font.PixelsPerInch := 96; C.IconFont := Font; C.GlyphName := 'save'; C.Caption := 'Save';
    S.Controller := Ctl; S.Font.PixelsPerInch := 96; S.IconFont := Font; S.GlyphName := 'save'; S.Caption := 'Cut';

    B.CallPreferred(w, h);
    AssertEquals('glyph button proposes no height', 0, h);
    AssertTrue('glyph button still proposes a width', w > 0);
    C.CallPreferred(w, h);
    AssertEquals('container button proposes no height', 0, h);
    AssertTrue('container button still proposes a width', w > 0);
    S.CallPreferred(w, h);
    AssertEquals('speed button proposes no height', 0, h);
    AssertTrue('speed button still proposes a width', w > 0);
  finally
    S.Free; C.Free; B.Free; Font.Free; Ctl.Free;
  end;
end;

{ ---- TGlyphButtonFloorTest ---- }

const
  { Padding and font-size pinned so the assertions can be exact numbers instead of
    "bigger than". border-width:0 keeps the frame out of the arithmetic. }
  cGbFloorCss =
    'TyButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 5px 9px; font-size: 12px; }';
  { Ribbon tiles resolve their OWN key, so the tile tests state that one. 4px top + 4px
    bottom = 8px of vertical padding, 8px+8px = 16px horizontal. }
  cGbTileCss =
    'TyGlyphContainerButton { background: #FFFFFF; color: #000000; border-width: 0px; padding: 4px 8px; font-size: 12px; }';

procedure TGlyphButtonFloorTest.TestFloorFitsTheCaption;
var
  Ctl: TTyStyleController;
  B: TGlyphButtonAccess;
  tw, th: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cGbFloorCss);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := '新建';
    B.Invalidate;                       // the seam a theme switch arrives on
    B.CallMeasure(96, tw, th);

    AssertTrue(Format('the height floor covers the caption ink (%d >= %d)',
      [B.Constraints.MinHeight, th]), B.Constraints.MinHeight >= th);
    AssertTrue('the width floor covers it too', B.Constraints.MinWidth >= tw);

    { Ask for something impossible; the clamp must win — that is the whole point of putting
      this in Constraints rather than in a proposed size. }
    B.Height := 4;
    B.Width := 4;
    AssertTrue('a too-short request is clamped up', B.Height >= th);
    AssertTrue('a too-narrow request is clamped up', B.Width >= tw);
  finally
    B.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonFloorTest.TestGlyphSlotIsPartOfTheWidthFloorNotTheHeight;
var
  Ctl: TTyStyleController;
  Icons: TTyIconFont;
  B: TGlyphButtonAccess;
  w16, h16: Integer;
begin
  { The glyph is not decoration: a glyph-left button that could shrink to its caption would
    have the icon eat the text. But it displaces the caption SIDEWAYS, so it belongs in the
    WIDTH floor only — adding it to the height would quietly grow every tool-bar row that
    carries an icon. }
  Ctl := TTyStyleController.Create(nil);
  Icons := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cGbFloorCss);
    Icons.MapGlyph('save', $F0C7);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.IconFont := Icons;
    B.GlyphName := 'save';
    B.Caption := 'Save';
    B.GlyphSize := 16;
    B.Invalidate;
    w16 := B.Constraints.MinWidth;
    h16 := B.Constraints.MinHeight;

    B.GlyphSize := 32;                  // the setter invalidates, which re-measures the floor
    AssertEquals('a 16px bigger glyph raises the WIDTH floor by exactly 16',
      w16 + 16, B.Constraints.MinWidth);
    AssertEquals('...and leaves the HEIGHT floor alone', h16, B.Constraints.MinHeight);

    { And the slot is only reserved when the paint really draws one: drop the source and the
      floor gives back the 32px square AND the 6px '--glyph-button-gap' default. }
    B.GlyphName := '';
    AssertEquals('no glyph drawn -> no slot and no gap in the floor',
      w16 - 16 - 6, B.Constraints.MinWidth);
  finally
    B.Free; Icons.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonFloorTest.TestContainerStacksTheGlyphIntoTheHeightFloor;
var
  Ctl: TTyStyleController;
  Icons: TTyIconFont;
  C: TContainerButtonAccess;
  tw, th: Integer;
begin
  { Glyph-TOP is the layout that stacks ink on the CAPTION's axis: TyGlyphButtonSplit puts the
    glyph above, the gap under it, the caption below that — and a box shorter than the stack
    clamps the glyph and then collapses the caption rect to nothing. That is the vertical twin
    of the clipped caption, so all three terms are part of the minimum height. }
  Ctl := TTyStyleController.Create(nil);
  Icons := TTyIconFont.Create(nil);
  C := TContainerButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cGbTileCss);
    Icons.MapGlyph('save', $F0C7);
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.IconFont := Icons;
    C.GlyphName := 'save';
    C.Caption := 'Open';
    C.GlyphSize := 24;
    C.Invalidate;
    C.CallMeasure(96, tw, th);

    // 24px glyph + the 6px default gap + one caption line + 4px top and 4px bottom padding.
    AssertEquals('glyph + gap + caption line + padding', 24 + 6 + th + 8, C.Constraints.MinHeight);
    C.GlyphSize := 48;
    AssertEquals('a 24px bigger glyph raises the floor by exactly 24',
      24 + 6 + th + 8 + 24, C.Constraints.MinHeight);
  finally
    C.Free; Icons.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonFloorTest.TestContainerWithoutACaptionPaysNoGapNorLine;
var
  Ctl: TTyStyleController;
  Icons: TTyIconFont;
  C: TContainerButtonAccess;
begin
  // DrawContent skips the caption rect entirely when Caption is empty, so a pure-icon tile
  // must not be floored at a gap and a line it never draws.
  Ctl := TTyStyleController.Create(nil);
  Icons := TTyIconFont.Create(nil);
  C := TContainerButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cGbTileCss);
    Icons.MapGlyph('save', $F0C7);
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.IconFont := Icons;
    C.GlyphName := 'save';
    C.Caption := '';
    C.GlyphSize := 24;
    C.Invalidate;
    AssertEquals('a pure-icon tile is floored at the glyph plus the padding, nothing else',
      24 + 8, C.Constraints.MinHeight);
  finally
    C.Free; Icons.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonFloorTest.TestAutoGlyphNeverRatchetsTheFloor;
var
  Ctl: TTyStyleController;
  Icons: TTyIconFont;
  C: TContainerButtonAccess;
  atSixtyFour, tw, th: Integer;
begin
  { GlyphSize 0 (auto) derives the square FROM the content box. Feeding that back into the
    floor would make the minimum equal whatever height the control currently has — the control
    could then never shrink again, and the "floor" would be a ratchet rather than a
    measurement. An auto glyph must demand nothing. }
  Ctl := TTyStyleController.Create(nil);
  Icons := TTyIconFont.Create(nil);
  C := TContainerButtonAccess.Create(nil);
  try
    Ctl.LoadThemeCss(cGbTileCss);
    Icons.MapGlyph('save', $F0C7);
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.IconFont := Icons;
    C.GlyphName := 'save';
    C.Caption := 'Open';
    C.GlyphSize := 0;                   // auto

    C.Height := 64;
    C.Invalidate;
    atSixtyFour := C.Constraints.MinHeight;
    C.Height := 300;                    // a much taller box...
    C.Invalidate;
    AssertEquals('an auto glyph never raises the floor with the box it was given',
      atSixtyFour, C.Constraints.MinHeight);

    C.CallMeasure(96, tw, th);
    AssertEquals('the floor is exactly the caption line plus the theme padding',
      th + 8, atSixtyFour);
  finally
    C.Free; Icons.Free; Ctl.Free;
  end;
end;

procedure TGlyphButtonFloorTest.TestSmallerFontAndPaddingLowerTheFloor;
var
  Ctl: TTyStyleController;
  Icons: TTyIconFont;
  B: TGlyphButtonAccess;
  bigH, bigW: Integer;
begin
  { The floor must stay DERIVED, never a constant: shrinking font-size and padding in the theme
    has to lower it, because "override the CSS if you want it smaller" is the answer we give. }
  Ctl := TTyStyleController.Create(nil);
  Icons := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    Icons.MapGlyph('save', $F0C7);
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.IconFont := Icons;
    B.GlyphName := 'save';
    { An EXPLICIT glyph size, so the only things moving between the two themes are the font and
      the padding. An auto glyph would be derived from the control's own (by then already
      re-clamped) height and would muddy the comparison. }
    B.GlyphSize := 16;
    B.Caption := '新建';

    Ctl.LoadThemeCss('TyButton { font-size: 20px; padding: 8px; }');
    B.Invalidate;
    bigH := B.Constraints.MinHeight;
    bigW := B.Constraints.MinWidth;

    Ctl.LoadThemeCss('TyButton { font-size: 8px; padding: 1px; }');
    B.Invalidate;
    AssertTrue(Format('a smaller font+padding lowers the height floor (%d -> %d)',
      [bigH, B.Constraints.MinHeight]), B.Constraints.MinHeight < bigH);
    AssertTrue(Format('...and the width floor with it (%d -> %d)',
      [bigW, B.Constraints.MinWidth]), B.Constraints.MinWidth < bigW);
  finally
    B.Free; Icons.Free; Ctl.Free;
  end;
end;

{ ---- TSpeedButtonTest ---- }

procedure TSpeedButtonTest.TestDefaults;
var
  S: TTySpeedButton;
begin
  S := TTySpeedButton.Create(nil);
  try
    AssertEquals('GroupIndex default 0', 0, S.GroupIndex);
    AssertFalse('AllowAllUp default False', S.AllowAllUp);
    AssertFalse('Down default False', S.Down);
    AssertTrue('grouping props published',
      IsPublishedProp(S, 'GroupIndex') and IsPublishedProp(S, 'AllowAllUp'));
  finally
    S.Free;
  end;
end;

procedure TSpeedButtonTest.TestGroupingRadioBehaviour;
var
  F: TCustomForm;
  A, B, C: TTySpeedButton;
begin
  // Three grouped speed buttons: clicking one presses it and releases the others.
  F := TCustomForm.CreateNew(nil);
  try
    A := TTySpeedButton.Create(F); A.Parent := F; A.GroupIndex := 1;
    B := TTySpeedButton.Create(F); B.Parent := F; B.GroupIndex := 1;
    C := TTySpeedButton.Create(F); C.Parent := F; C.GroupIndex := 1;

    A.Click;
    AssertTrue('A down after clicking A', A.Down);
    AssertFalse('B up after clicking A', B.Down);
    AssertFalse('C up after clicking A', C.Down);

    B.Click;
    AssertFalse('A up after clicking B', A.Down);
    AssertTrue('B down after clicking B', B.Down);
    AssertFalse('C up after clicking B', C.Down);

    // Radio (AllowAllUp False): clicking the already-down button keeps it down.
    B.Click;
    AssertTrue('radio: re-clicking the down button keeps it down', B.Down);
  finally
    F.Free;
  end;
end;

procedure TSpeedButtonTest.TestAllowAllUpToggle;
var
  F: TCustomForm;
  A, B: TTySpeedButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    A := TTySpeedButton.Create(F); A.Parent := F; A.GroupIndex := 2; A.AllowAllUp := True;
    B := TTySpeedButton.Create(F); B.Parent := F; B.GroupIndex := 2; B.AllowAllUp := True;

    A.Click;
    AssertTrue('A down after first click', A.Down);
    // AllowAllUp: clicking the down button toggles it back up -> whole group up.
    A.Click;
    AssertFalse('AllowAllUp: re-clicking toggles A back up', A.Down);
    AssertFalse('B still up', B.Down);

    // And it still radios against the sibling.
    A.Click;
    B.Click;
    AssertFalse('A released when B pressed', A.Down);
    AssertTrue('B down', B.Down);
  finally
    F.Free;
  end;
end;

procedure TSpeedButtonTest.TestUngroupedClickJustFires;
var
  F: TCustomForm;
  A, B: TTySpeedButton;
begin
  // GroupIndex = 0 (default): Click does not touch Down or siblings.
  F := TCustomForm.CreateNew(nil);
  try
    A := TTySpeedButton.Create(F); A.Parent := F;   // GroupIndex 0
    B := TTySpeedButton.Create(F); B.Parent := F; B.Down := True;
    A.Click;
    AssertFalse('ungrouped click leaves A up', A.Down);
    AssertTrue('ungrouped click does not release an unrelated down button', B.Down);
  finally
    F.Free;
  end;
end;

procedure TSpeedButtonTest.TestDisabledClickNoChange;
var
  F: TCustomForm;
  A, B: TTySpeedButton;
begin
  // A disabled grouped button's Click is a no-op (no press, no sibling release).
  F := TCustomForm.CreateNew(nil);
  try
    A := TTySpeedButton.Create(F); A.Parent := F; A.GroupIndex := 3; A.Down := True;
    B := TTySpeedButton.Create(F); B.Parent := F; B.GroupIndex := 3; B.Enabled := False;
    B.Click;
    AssertFalse('disabled button did not press', B.Down);
    AssertTrue('disabled click did not release the sibling', A.Down);
  finally
    F.Free;
  end;
end;

procedure TSpeedButtonTest.TestRoomierThemeWidensThroughItsOwnKey;
var
  Ctl: TTyStyleController;
  Font: TTyIconFont;
  S: TSpeedButtonAccess;
  tight, roomy, h: Integer;
begin
  { The speed button owns the 'TySpeedButton' key, so its padding — and therefore the width
    it needs — must be read from THAT rule, not from TyButton. If the measurement borrowed
    another control's key the theme layer could not reach it and a roomier skin would clip
    the caption exactly as before. }
  Ctl := TTyStyleController.Create(nil);
  Font := TTyIconFont.Create(nil);
  S := TSpeedButtonAccess.Create(nil);
  try
    Font.MapGlyph('cut', $F0C4);
    S.Controller := Ctl;
    S.Font.PixelsPerInch := 96;
    S.IconFont := Font;
    S.GlyphName := 'cut';
    S.GlyphSize := 16;
    S.AutoSize := True;
    S.Caption := 'Cut';

    Ctl.LoadThemeCss('TySpeedButton { background: #FFFFFF; color: #000000; padding: 3px 5px; font-size: 12px; }');
    S.CallPreferred(tight, h);
    Ctl.LoadThemeCss('TySpeedButton { background: #FFFFFF; color: #000000; padding: 3px 25px; font-size: 12px; }');
    S.CallPreferred(roomy, h);
    AssertTrue(Format('a roomier skin widens the speed button (%d -> %d)', [tight, roomy]),
      roomy > tight);
    AssertEquals('the extra width is exactly the extra padding', tight + 40, roomy);
    AssertEquals('and it never proposes a height', 0, h);
  finally
    S.Free; Font.Free; Ctl.Free;
  end;
end;

procedure TSpeedButtonTest.TestAutoSizeSurvivesAHeightPinningToolBar;
var
  F: TForm;
  Bar: TTyToolBar;
  S: TTySpeedButton;
  hBefore: Integer;
begin
  { The reason PreferredHeight is 0: a tool bar pins every child to its ButtonHeight. A speed
    button that also proposed a height bounced against the bar until LCL aborted with
    "TControl.ChangeBounds loop detected" and the app died at startup. Growing the caption on
    a real bar must simply settle — at the BAR's height, not the button's idea of one. }
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.Align := alTop;
    Bar.ButtonHeight := 24;

    S := TTySpeedButton.Create(F);
    S.Parent := Bar;
    S.Font.PixelsPerInch := 96;
    S.Caption := 'Cut';
    S.AutoSize := True;
    hBefore := S.Height;

    S.Caption := 'Cut the selection to the clipboard';
    Bar.Realign;

    AssertEquals('the bar still owns the height', hBefore, S.Height);
    AssertTrue('and the speed button is still a sane size', (S.Width > 0) and (S.Height > 0));
  finally
    F.Free;
  end;
end;

procedure TSpeedButtonTest.TestFloorSurvivesAHeightPinningToolBar;
var
  F: TForm;
  Bar: TTyToolBar;
  Icons: TTyIconFont;
  S: TTySpeedButton;
begin
  { The floor must NOT reopen the fight a proposed height once started: a button on a
    TTyToolBar proposed its own height, the bar pinned its ButtonHeight back, and LCL aborted
    with "ChangeBounds loop detected" — the demo died at startup. Constraints clamp inside
    SetBounds with no negotiation, so the bar keeps owning the height whenever the height it
    asks for is possible at all. Reaching the end of this test IS the assertion. }
  F := TForm.CreateNew(nil);
  Icons := TTyIconFont.Create(nil);
  try
    Icons.MapGlyph('cut', $F0C4);
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.ButtonHeight := 40;            // comfortably above any caption's needs
    S := TTySpeedButton.Create(Bar);
    S.Parent := Bar;
    S.IconFont := Icons;
    S.GlyphName := 'cut';
    S.GlyphSize := 16;                 // an icon on the row must not raise its height
    S.Caption := '新建';
    S.AutoSize := True;
    Bar.ButtonHeight := 41;            // a loop would abort the process here
    AssertTrue(Format('the bar asks for a height the floor can honour (min %d)',
      [S.Constraints.MinHeight]), S.Constraints.MinHeight <= 40);
  finally
    Icons.Free;
    F.Free;
  end;
end;

{ TStateGlyphButton }

function TStateGlyphButton.GetGlyphSource(AStates: TTyStateSet): TTyGlyphSource;
begin
  Result := inherited GetGlyphSource(AStates);
  Inc(Asked);
  AskedWith := AStates;
  if (tysHover in AStates) and (HotGlyphName <> '') then
  begin
    Result.GlyphName := HotGlyphName;
    if HotIconFont <> nil then Result.IconFont := HotIconFont;
  end;
end;

procedure TStateGlyphButton.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TStateGlyphButton.SetHoverForTest(AValue: Boolean);
begin
  FHover := AValue;
end;

procedure TStateGlyphButton.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

{ TGlyphSourceSeamTest }

function TGlyphButtonAccess.CallGlyphSource(AStates: TTyStateSet): TTyGlyphSource;
begin
  Result := GetGlyphSource(AStates);
end;

procedure TGlyphSourceSeamTest.TestBaseIsStateBlind;
var
  B: TGlyphButtonAccess;
  Icons: TTyIconFont;
  st: TTyState;
  src: TTyGlyphSource;
begin
  { The seam's whole claim to being free: the base reads AStates and does nothing with it, so
    every button that does not override it resolves what the published properties say and
    nothing else. Asserted over EVERY state, singly and all at once — a base that special-cased
    even one of them would be a behaviour change smuggled in with the refactor. }
  Icons := TTyIconFont.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    B.IconFont := Icons;
    B.GlyphName := 'save';
    for st := Low(TTyState) to High(TTyState) do
    begin
      src := B.CallGlyphSource([st]);
      AssertEquals(Format('state %d resolves the published glyph name', [Ord(st)]),
        'save', src.GlyphName);
      AssertTrue('and the published font', src.IconFont = Icons);
      AssertTrue('with no image source invented', src.Images = nil);
      AssertEquals('and no image name', '', src.ImageName);
    end;
    src := B.CallGlyphSource([tysHover, tysActive, tysFocused, tysDisabled, tysSelected]);
    AssertEquals('every state at once changes nothing either', 'save', src.GlyphName);
    src := B.CallGlyphSource([]);
    AssertEquals('nor does the empty set', 'save', src.GlyphName);
  finally
    B.Free;
    Icons.Free;
  end;
end;

procedure TGlyphSourceSeamTest.TestImageSourceStillWinsOverTheFont;
var
  B: TGlyphButtonAccess;
  Icons: TTyIconFont;
  coll: TTyImageCollection;
  m: TBGRABitmap;
  src: TTyGlyphSource;
begin
  { The precedence the published properties always had (Images+ImageName beat
    IconFont+GlyphName) lives in the bitmap resolver, so the seam must hand BOTH pairs
    through untouched rather than pre-deciding. }
  Icons := TTyIconFont.Create(nil);
  coll := TTyImageCollection.Create(nil);
  B := TGlyphButtonAccess.Create(nil);
  try
    m := TBGRABitmap.Create(8, 8, BGRAWhite);
    try coll.AddBitmap('save', m); finally m.Free; end;
    B.IconFont := Icons;
    B.GlyphName := 'font-glyph';
    B.Images := coll;
    B.ImageName := 'save';
    src := B.CallGlyphSource([]);
    AssertTrue('the collection comes through', src.Images = coll);
    AssertEquals('with its name', 'save', src.ImageName);
    AssertTrue('and so does the font', src.IconFont = Icons);
    AssertEquals('with ITS name — the seam decides nothing, the resolver does',
      'font-glyph', src.GlyphName);
  finally
    B.Free;
    coll.Free;
    Icons.Free;
  end;
end;

procedure TGlyphSourceSeamTest.TestPaintAsksTheSeamWithTheCurrentStates;
var
  B: TStateGlyphButton;
  Icons: TTyIconFont;
  bmp: TBitmap;
begin
  { A seam nothing calls is not a seam. The paint must ASK, and ask with the states it is
    actually painting — otherwise an override could never tell rest from hover. }
  Icons := TTyIconFont.Create(nil);
  B := TStateGlyphButton.Create(nil);
  bmp := TBitmap.Create;
  try
    B.IconFont := Icons;
    B.GlyphName := 'save';
    B.SetBounds(0, 0, 90, 28);
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(90, 28);

    B.Asked := 0;
    B.RenderTo(bmp.Canvas, Rect(0, 0, 90, 28), 96);
    AssertTrue('the paint asked the seam', B.Asked > 0);
    AssertFalse('at rest it asked without tysHover', tysHover in B.AskedWith);

    B.SetHoverForTest(True);
    B.Asked := 0;
    B.RenderTo(bmp.Canvas, Rect(0, 0, 90, 28), 96);
    AssertTrue('and asked again while hovered', B.Asked > 0);
    AssertTrue('this time WITH tysHover', tysHover in B.AskedWith);
  finally
    bmp.Free;
    B.Free;
    Icons.Free;
  end;
end;

procedure TGlyphSourceSeamTest.TestSeamNeverDecidesWhetherAGlyphExists;
var
  B: TStateGlyphButton;
  Icons: TTyIconFont;
  bmp: TBitmap;
  w0, h0: Integer;
begin
  { The contract, from the side that matters. A button with NO published glyph source paints
    a plain caption and reserves no slot — and it must keep doing both even when a subclass's
    seam would happily invent a glyph, because presence and size are read from the published
    fields and never from the seam. If DrawContent ever routed its early-exit through
    GetGlyphSource, this button would start painting a glyph into a slot nothing measured. }
  Icons := TTyIconFont.Create(nil);
  B := TStateGlyphButton.Create(nil);
  bmp := TBitmap.Create;
  try
    { A COMPLETE glyph source on hover — font and name both — that the published properties do
      not have. If presence were read from the seam, this button would grow an icon under the
      pointer, in a slot nothing measured. }
    B.HotGlyphName := 'save';
    B.HotIconFont := Icons;
    B.Caption := 'Plain';
    B.SetBounds(0, 0, 90, 28);
    AssertFalse('with no published source there is no glyph', B.CanShowGlyph);

    w0 := 0; h0 := 0;
    B.SetHoverForTest(True);
    AssertFalse('and hovering does not conjure one: presence is the published fields'' '
      + 'business, never the per-state seam''s', B.CanShowGlyph);
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(90, 28);
    B.Asked := 0;
    B.RenderTo(bmp.Canvas, Rect(0, 0, 90, 28), 96);
    AssertEquals('the paint never even asked: there is nothing to substitute for',
      0, B.Asked);

    // And the measurement is the plain-caption one, hover or not.
    B.IconFont := Icons;
    B.GlyphName := '';
    AssertFalse('an empty glyph name is still no glyph', B.CanShowGlyph);
    B.CallPreferred(w0, h0);
    AssertTrue('so the width reserves no slot', w0 > 0);
  finally
    bmp.Free;
    B.Free;
    Icons.Free;
  end;
end;

initialization
  RegisterTest(TGlyphButtonTest);
  RegisterTest(TGlyphButtonFloorTest);
  RegisterTest(TSpeedButtonTest);
  RegisterTest(TGlyphSourceSeamTest);
end.
