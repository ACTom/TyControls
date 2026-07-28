unit tyControls.GlyphButtons;
{$mode objfpc}{$H+}

{ Glyph command buttons — three themed buttons that pair an icon-font glyph (from
  a TTyIconFont) with the button caption, built on top of TTyButton:

    TTyGlyphButton          glyph-LEFT: a compact command button (icon + caption
                            side by side), default ~96x30.
    TTyGlyphContainerButton glyph-TOP: a large ribbon-style button (big icon over
                            caption), default ~72x64 with a larger default glyph.
    TTySpeedButton          a flat/toolbar toggle button (glyph-left), groupable
                            by GroupIndex like a classic TSpeedButton.

  All three subclass TTyButton and ONLY override DrawContent (plus Click/Create
  where noted) — the frame, hover bg-fade, states, focus ring and numeric badge
  come for free and the glyph simply shares the resolved TextColor and box.

  TTyGlyphButton keeps the inherited 'TyButton' key: it IS a push button, just
  with an icon in front of the caption, so it must stay in lockstep with every
  other button. The other two do NOT — they need a different FRAME from a push
  button (a ribbon tile is borderless, a toolbar toggle is flat), which is a
  theme decision, so each owns a key (see the overrides below). Nothing else
  changes: with no rule for the new keys the base layer still inherits the
  TyButton chrome, so the default look is identical until a skin says otherwise.

  The shared base (TTyGlyphButtonBase) adds the glyph plumbing: an IconFont
  reference (nilled via FreeNotification), a GlyphName, a logical GlyphSize
  (0 = auto from the content box), a GlyphColor with a "use the theme TextColor"
  sentinel, and a protected GlyphLayout the two orientations set. DrawContent
  renders the glyph (delegating rasterization to TTyIconFont.RenderGlyph, exactly
  like TTyCharImage), places it per the layout, then calls the inherited caption
  draw in the leftover rect. With no IconFont / an unmapped glyph / no window
  handle it degrades to a plain caption button — headless-safe, never crashes.

  AutoSize (inherited from TTyButton, still off by default) is taught about the
  glyph here: TTyButton only knows about the caption plus the theme's padding, but
  these buttons draw a glyph too, so an AutoSize glyph button that reserved only the
  caption's width would push the caption out of the box the moment the skin grew the
  padding or the font. CalculatePreferredSize below therefore mirrors DrawContent's
  own geometry — same glyph size, same gap metric, same layout — because a preferred
  size that disagrees with the paint is worse than none at all: AutoSize would then
  report a fit while the caption still clips.

  The SIZE FLOOR (TTyButton.UpdateSizeConstraints) rides on that same measurement, so it
  needs no second geometry here: the width minimum simply IS what CalculatePreferredSize
  asks for, glyph slot and gap included. Only the HEIGHT is stated separately, in
  MeasureContentHeight below — and only for the ribbon tile, because glyph-TOP is the one layout
  that stacks the glyph on the CAPTION's axis. That axis is where the bug lived: Qt6 resolves
  a CJK caption through a fallback face whose ink is taller than the theme's --control-height
  assumed, and DrawText clips with tlCenter, so it was the BOTTOM of 新建/打开 that silently
  went missing. A hand-set Height is a request; the font and the padding decide what is
  possible. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Button, tyControls.Controller, tyControls.IconFont,
  tyControls.ImageCollection;

const
  { Sentinel GlyphColor meaning "use the resolved theme TextColor". A fully
    transparent value ($00000000) can never be a meaningful visible glyph color,
    so it doubles as the unambiguous "not set" marker (mirrors TTyCharImage's
    TyGlyphColorDefault and the alpha=0 = "unset" idiom used across the library). }
  TyGlyphButtonColorDefault = tyTransparent;

  { Default logical gap (px) between the glyph and the caption. Scaled by PPI at
    paint time. }
  TyGlyphButtonGap = 6;

type
  { Glyph placement relative to the caption. }
  TTyGlyphLayout = (glLeft, glTop);

  { Shared base: TTyButton + an icon-font glyph placed per GlyphLayout. Usable on
    its own (it defaults to glyph-left) but primarily the parent of the three
    concrete controls below; it is NOT registered on the palette itself. }
  TTyGlyphButtonBase = class(TTyButton)
  private
    FIconFont: TTyIconFont;
    FGlyphName: string;
    FGlyphSize: Integer;
    FGlyphColor: TTyColor;
    FImages: TTyImageCollection;
    FImageName: string;
    procedure SetIconFont(AValue: TTyIconFont);
    procedure SetGlyphName(const AValue: string);
    procedure SetGlyphSize(AValue: Integer);
    procedure SetGlyphColor(AValue: TTyColor);
    procedure SetImages(AValue: TTyImageCollection);
    procedure SetImageName(const AValue: string);
    { The glyph bitmap to draw at ASizePx in AColor: from Images[ImageName] (tinted to
      AColor) when an image source is set, else from IconFont[GlyphName]. Caller owns it. }
    function ResolveGlyphBitmap(ASizePx: Integer; AColor: TTyColor): TBGRABitmap;
  protected
    { The orientation this button paints in. Set once in each concrete class's
      constructor (glLeft for TTyGlyphButton/TTySpeedButton, glTop for
      TTyGlyphContainerButton); honored by DrawContent. }
    FGlyphLayout: TTyGlyphLayout;
    { Draw the glyph (if any) then the inherited caption in the leftover rect. }
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); override;
    { True exactly when DrawContent will really paint a glyph: an image icon
      (Images + ImageName, which wins) or a font glyph (IconFont + GlyphName).
      The preferred width may only reserve a slot the paint actually uses —
      otherwise an AutoSize button with a GlyphName but no font would sit on a
      pocket of empty space its plain-caption paint never fills. }
    function HasGlyphSource: Boolean;
    { The glyph square's edge in DEVICE px at APPI under AStyle, mirroring the choice
      DrawContent makes: an explicit GlyphSize (scaled) wins, otherwise auto-fit. }
    function MeasureGlyphSlot(APPI: Integer; const AStyle: TTyStyleSet): Integer;
    { The glyph's edge in DEVICE px when — and only when — GlyphSize was set EXPLICITLY and
      there is really a glyph to draw; 0 otherwise. Deliberately NOT MeasureGlyphSlot: that
      one falls back to the AUTO square, which is derived FROM the content box, so feeding it
      into a size FLOOR would pin the control at whatever height it happens to have and it
      could never shrink again — the minimum would stop being a measurement and become a
      ratchet. An auto glyph demands nothing; it takes the box it is given. }
    function FixedGlyphPx(APPI: Integer): Integer;
    { A ribbon tile (glyph-TOP) stacks glyph, gap and caption down the box — exactly what
      TyGlyphButtonSplit lays out — so all three are part of the minimum HEIGHT: a shorter box
      clamps the glyph and then collapses the caption rect to nothing, which is the vertical
      twin of the clipped caption this floor exists to stop.
      Glyph-LEFT adds nothing here. Its slot displaces the caption SIDEWAYS, and that cost is
      already in CalculatePreferredSize's width; counting it again as height would quietly
      grow every tool-bar row that carries an icon. }
    function MeasureContentHeight(APPI: Integer): Integer; override;
    { The caption's width plus the theme padding (TTyButton's answer), WIDENED by the
      glyph slot — and, for glyph-left, by the gap between glyph and caption — so the
      box AutoSize asks for is the box DrawContent paints into. Width only: the
      inherited PreferredHeight of 0 is kept deliberately (see TTyButton), because a
      speed button in a tool bar must take the bar's row height, not argue for its own. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    property GlyphLayout: TTyGlyphLayout read FGlyphLayout write FGlyphLayout;
  public
    constructor Create(AOwner: TComponent); override;
  published
    { Inherited from TTyButton and still off by default (a designed button keeps the
      width its .lfm gave it). Re-published only to record what it hugs HERE: the glyph
      slot and the glyph/caption gap count too, so switching to a skin with roomier
      padding — or raising GlyphSize, or a longer translated caption — lengthens the
      button instead of ellipsising its text. Every glyph property setter already ends
      in Invalidate, which is where TTyButton re-fits an auto-sized button. }
    property AutoSize;
    { Icon-font source for the glyph. Nilled automatically (FreeNotification) when
      the referenced font is freed, so no dangling reference remains. }
    property IconFont: TTyIconFont read FIconFont write SetIconFont;
    { The glyph name to draw (a key in IconFont.Glyphs, e.g. 'save'). Empty or
      unmapped -> no glyph, caption fills the whole content box. }
    property GlyphName: string read FGlyphName write SetGlyphName;
    { Glyph edge length in LOGICAL px (scaled by PPI). 0 = auto: derive from the
      content box (the short side for glyph-top, the box height for glyph-left). }
    property GlyphSize: Integer read FGlyphSize write SetGlyphSize default 0;
    { Glyph fill color. TyGlyphButtonColorDefault (the default) = use the theme's
      resolved TextColor (so the glyph matches the caption); any other value wins. }
    property GlyphColor: TTyColor read FGlyphColor write SetGlyphColor default TyGlyphButtonColorDefault;
    { Cross-platform IMAGE glyph source (a TTyImageCollection of BGRA icons). When Images
      and ImageName are both set they WIN over IconFont/GlyphName — the named icon is drawn
      (tinted to GlyphColor/TextColor). Unlike a system icon font this renders identically
      on every OS. Nilled via FreeNotification. }
    property Images: TTyImageCollection read FImages write SetImages;
    { The icon name in Images to draw. Empty -> fall back to the IconFont glyph. }
    property ImageName: string read FImageName write SetImageName;
  end;

  { Compact command button: glyph on the LEFT, caption to its right. }
  TTyGlyphButton = class(TTyGlyphButtonBase)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { Large ribbon-style button: a big glyph on TOP, caption below. }
  TTyGlyphContainerButton = class(TTyGlyphButtonBase)
  protected
    { Own key: this is a ribbon TILE (glTop, GlyphSize 24, 72x64 — what
      examples/ribbon drops into a TyRibbonGroup), not a push button. Borrowing
      'TyButton' resolved the tile's background/border/radius/padding from the
      same rule as a dialog OK button, so a theme author could not give tiles the
      conventional borderless, transparent-at-rest look with their own hover tint
      without flattening every button in the app. TyRibbon and TyRibbonGroup
      already own keys so a skin can restyle the ribbon band; this is that band's
      missing third key. }
    function GetStyleTypeKey: string; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  { Flat/toolbar toggle button (glyph-left). Groupable like a classic
    TSpeedButton: with GroupIndex > 0 it behaves as a radio within its Parent —
    clicking presses it (Down) and releases sibling TTySpeedButtons that share the
    GroupIndex. AllowAllUp lets a click on the already-down button toggle it back
    up (so the whole group can be up). Inherits the resting :selected state via
    Down. }
  TTySpeedButton = class(TTyGlyphButtonBase)
  private
    FGroupIndex: Integer;
    FAllowAllUp: Boolean;
    procedure SetGroupIndex(AValue: Integer);
    { Release (Down := False) every sibling TTySpeedButton in the same Parent that
      shares FGroupIndex, except Self. No-op when parentless. }
    procedure UnpressSiblings;
  protected
    { Own key: a flat toolbar TOGGLE rests flat where a push button rests framed,
      and which one it is must be the THEME's call, not app code's. Borrowing
      'TyButton' left only one lever — hand every speed button a 'speed'/'toolbar'
      StyleClass — which pushes a styling decision into every app AND is
      unreliable: TTyToolBar.ApplyToButton overwrites its children's StyleClass
      wholesale (it owns the ghost/non-ghost class), and a speed button used
      OUTSIDE a toolbar got full push-button chrome with no way for the theme to
      say otherwise. With its own key a skin can state the flat resting frame
      once, for every speed button, wherever it sits. }
    function GetStyleTypeKey: string; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Radio/toggle grouping. GroupIndex = 0 keeps the plain button behaviour
      (Click just fires OnClick). GroupIndex > 0 makes Click press Self and
      release same-group siblings; AllowAllUp additionally lets a click on the
      down button toggle it back up. }
    procedure Click; override;
  published
    property GroupIndex: Integer read FGroupIndex write SetGroupIndex default 0;
    property AllowAllUp: Boolean read FAllowAllUp write FAllowAllUp default False;
    { Back to False, matching what the constructor sets. The declared default has to agree
      with the constructed value or the streamer writes the property into EVERY .lfm that
      holds one of these (TTyButton declares it True); a host that wants a focusable speed
      button still says TabStop=True and that one line streams. }
    property TabStop default False;
  end;

{ Pure helper: split a content rect (device px) into a glyph rect + a caption rect
  for the given layout and glyph pixel size, separated by AGapPx.

  glLeft: the glyph is an AGlyphPx-wide, AGlyphPx-tall square anchored at the LEFT
  and vertically centered; the caption takes the rest to its right, past the gap.
  glTop:  the glyph is an AGlyphPx square anchored at the TOP and horizontally
  centered; the caption takes the rest below, past the gap.

  AGlyphPx <= 0 (no glyph) -> the glyph rect is empty and the caption keeps the
  whole content rect. The glyph rect is clamped to the content box so an oversized
  glyph never pushes the caption to a negative-width rect. Headless-testable with
  no font. }
procedure TyGlyphButtonSplit(const AContentRect: TRect; AGlyphPx, AGapPx: Integer;
  ALayout: TTyGlyphLayout; out AGlyphRect, ACaptionRect: TRect);

implementation

procedure TyGlyphButtonSplit(const AContentRect: TRect; AGlyphPx, AGapPx: Integer;
  ALayout: TTyGlyphLayout; out AGlyphRect, ACaptionRect: TRect);
var
  cw, ch, gp, gx, gy: Integer;
begin
  cw := AContentRect.Right - AContentRect.Left;
  ch := AContentRect.Bottom - AContentRect.Top;
  // No glyph (or a degenerate box): caption keeps the whole content rect.
  if (AGlyphPx <= 0) or (cw <= 0) or (ch <= 0) then
  begin
    AGlyphRect := Rect(AContentRect.Left, AContentRect.Top, AContentRect.Left, AContentRect.Top);
    ACaptionRect := AContentRect;
    Exit;
  end;
  if AGapPx < 0 then AGapPx := 0;
  gp := AGlyphPx;
  case ALayout of
    glTop:
      begin
        // Clamp the glyph height so the caption never gets a negative height.
        if gp > ch then gp := ch;
        gx := AContentRect.Left + (cw - gp) div 2;    // horizontally centered
        AGlyphRect := Rect(gx, AContentRect.Top, gx + gp, AContentRect.Top + gp);
        ACaptionRect := Rect(AContentRect.Left, AGlyphRect.Bottom + AGapPx,
          AContentRect.Right, AContentRect.Bottom);
        // Degenerate: glyph + gap overran the box -> caption collapses (not inverts).
        if ACaptionRect.Top > ACaptionRect.Bottom then
          ACaptionRect.Top := ACaptionRect.Bottom;
      end;
  else
    // glLeft
    begin
      if gp > cw then gp := cw;
      gy := AContentRect.Top + (ch - gp) div 2;       // vertically centered
      AGlyphRect := Rect(AContentRect.Left, gy, AContentRect.Left + gp, gy + gp);
      ACaptionRect := Rect(AGlyphRect.Right + AGapPx, AContentRect.Top,
        AContentRect.Right, AContentRect.Bottom);
      if ACaptionRect.Left > ACaptionRect.Right then
        ACaptionRect.Left := ACaptionRect.Right;
    end;
  end;
end;

{ TTyGlyphButtonBase }

constructor TTyGlyphButtonBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGlyphSize := 0;
  FGlyphColor := TyGlyphButtonColorDefault;
  FGlyphLayout := glLeft;
end;

procedure TTyGlyphButtonBase.SetIconFont(AValue: TTyIconFont);
begin
  if FIconFont = AValue then Exit;
  if FIconFont <> nil then
    FIconFont.RemoveFreeNotification(Self);
  FIconFont := AValue;
  if FIconFont <> nil then
    FIconFont.FreeNotification(Self);
  Invalidate;
end;

procedure TTyGlyphButtonBase.SetGlyphName(const AValue: string);
begin
  if FGlyphName = AValue then Exit;
  FGlyphName := AValue;
  Invalidate;
end;

procedure TTyGlyphButtonBase.SetGlyphSize(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FGlyphSize = AValue then Exit;
  FGlyphSize := AValue;
  Invalidate;
end;

procedure TTyGlyphButtonBase.SetGlyphColor(AValue: TTyColor);
begin
  if FGlyphColor = AValue then Exit;
  FGlyphColor := AValue;
  Invalidate;
end;

procedure TTyGlyphButtonBase.SetImages(AValue: TTyImageCollection);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyGlyphButtonBase.SetImageName(const AValue: string);
begin
  if FImageName = AValue then Exit;
  FImageName := AValue;
  Invalidate;
end;

function TTyGlyphButtonBase.ResolveGlyphBitmap(ASizePx: Integer; AColor: TTyColor): TBGRABitmap;
begin
  if (FImages <> nil) and (FImageName <> '') then
  begin
    // Image source wins: a cross-platform BGRA icon, tinted to the text color.
    Result := FImages.GetBitmap(FImageName, ASizePx);
    TyTintBitmapAlpha(Result, AColor);
  end
  else if FIconFont <> nil then
    Result := FIconFont.RenderGlyph(FGlyphName, ASizePx, AColor)
  else
    Result := TBGRABitmap.Create(ASizePx, ASizePx);   // empty (guarded by DrawContent)
end;

function TTyGlyphButtonBase.HasGlyphSource: Boolean;
begin
  // The exact negation of the condition DrawContent falls through to the plain
  // caption on — the two must never disagree about whether a glyph exists.
  Result := ((FImages <> nil) and (FImageName <> ''))
         or ((FIconFont <> nil) and (FGlyphName <> ''));
end;

function TTyGlyphButtonBase.MeasureGlyphSlot(APPI: Integer; const AStyle: TTyStyleSet): Integer;
var
  scaledSize: Integer;
begin
  scaledSize := MulDiv(FGlyphSize, APPI, 96);
  if scaledSize > 0 then
    Result := scaledSize
  else
    { Auto (GlyphSize = 0). DrawContent derives the square from the CONTENT box — the
      client rect minus the theme's padding, the very inset RenderTo applies — so the
      measurement has to start from the same place. glyph-left takes that box's HEIGHT
      (a caption-height icon beside the text); glyph-top takes min(width, height), and
      the width we are about to ask for is at least this square plus the padding, so
      that min settles on the same number. One expression is therefore honest for both
      layouts. Height is used, not proposed: it stays whatever the layout gave us. }
    Result := ClientHeight - MulDiv(AStyle.Padding.Top + AStyle.Padding.Bottom, APPI, 96);
  if Result < 0 then Result := 0;
end;

function TTyGlyphButtonBase.FixedGlyphPx(APPI: Integer): Integer;
begin
  Result := 0;
  // No source -> DrawContent paints a plain caption; nothing to reserve for.
  if not HasGlyphSource then Exit;
  // Auto (GlyphSize = 0): computed FROM the box, so it can never be a demand ON the box.
  if FGlyphSize <= 0 then Exit;
  Result := MulDiv(FGlyphSize, APPI, 96);
  if Result < 0 then Result := 0;
end;

function TTyGlyphButtonBase.MeasureContentHeight(APPI: Integer): Integer;
var
  gpx, lineH, gapPx: Integer;
begin
  lineH := inherited MeasureContentHeight(APPI);   // the caption's own line
  gpx := FixedGlyphPx(APPI);
  if (gpx < 1) or (FGlyphLayout <> glTop) then
  begin
    // Glyph beside the caption, or no fixed glyph at all: the caption's line still decides.
    Result := lineH;
    Exit;
  end;
  Result := gpx;
  { The gap — and the caption's line under it — are only paid for when a caption is really
    drawn: DrawContent skips the caption rect entirely when Caption is empty, exactly as the
    preferred WIDTH refuses to pay a glyph-left gap to nothing. The metric is the same
    '--glyph-button-gap' DrawContent scales, so a skin retuning it moves both together. }
  if Caption <> '' then
  begin
    gapPx := MulDiv(ActiveController.Metric('--glyph-button-gap', TyGlyphButtonGap), APPI, 96);
    if gapPx < 0 then gapPx := 0;
    Inc(Result, gapPx + lineH);
  end;
end;

procedure TTyGlyphButtonBase.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, glyphPx, padX: Integer;
begin
  // TTyButton contributes the caption plus the theme's horizontal padding, and leaves
  // PreferredHeight at 0 ("no preference on this axis") — both are kept as they are.
  inherited CalculatePreferredSize(PreferredWidth, PreferredHeight, WithThemeSpace);
  // No glyph source: DrawContent paints a plain centered caption over the whole content
  // rect, so the inherited width already IS the truth. Same for a slot that scales away
  // to nothing — DrawContent takes the plain path there too (glyphPx < 1).
  if not HasGlyphSource then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  glyphPx := MeasureGlyphSlot(ppi, S);
  if glyphPx < 1 then Exit;
  padX := MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
  if FGlyphLayout = glTop then
  begin
    // Ribbon tile: the glyph sits ABOVE the caption, so the two SHARE the width instead
    // of adding up, and the gap between them is vertical — it costs nothing sideways.
    // The tile still may not be narrower than its own icon plus the padding.
    if glyphPx + padX > PreferredWidth then
      PreferredWidth := glyphPx + padX;
  end
  else
  begin
    // glyph-left: glyph, gap and caption stand side by side exactly as TyGlyphButtonSplit
    // lays them out, so all three plus the padding is what the button needs.
    Inc(PreferredWidth, glyphPx);
    // The gap is only paid for when a caption is actually drawn: DrawContent skips the
    // caption rect entirely when Caption is empty, and a pure-icon toolbar button must
    // not carry a gap to nothing (that would be a visibly off-centre glyph).
    if Caption <> '' then
      Inc(PreferredWidth,
        MulDiv(ActiveController.Metric('--glyph-button-gap', TyGlyphButtonGap), ppi, 96));
  end;
  if PreferredWidth < 1 then PreferredWidth := 1;
end;

procedure TTyGlyphButtonBase.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FIconFont) then
    FIconFont := nil;
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
end;

procedure TTyGlyphButtonBase.DrawContent(APainter: TTyPainter;
  const AContentRect: TRect; const AStyle: TTyStyleSet);
var
  cw, ch, scaledSize, autoPx, glyphPx, gapPx, gx, gy, renderPx: Integer;
  glyphCol: TTyColor;
  glyphRect, captionRect: TRect;
  glyph: TBGRABitmap;
begin
  cw := AContentRect.Right - AContentRect.Left;
  ch := AContentRect.Bottom - AContentRect.Top;
  // No glyph source (neither an image nor a font glyph) / degenerate box: fall straight
  // through to the inherited centered caption over the whole content rect (plain button).
  if (((FImages = nil) or (FImageName = '')) and ((FIconFont = nil) or (FGlyphName = '')))
     or (cw <= 0) or (ch <= 0) then
  begin
    inherited DrawContent(APainter, AContentRect, AStyle);
    Exit;
  end;

  // Device-px glyph size: explicit GlyphSize (scaled) wins; else auto-fit from the
  // content box — the short side for glyph-top (big square icon), the box height
  // for glyph-left (a caption-height icon beside the text).
  scaledSize := APainter.Scale(FGlyphSize);
  if scaledSize > 0 then
    glyphPx := scaledSize
  else
  begin
    if FGlyphLayout = glTop then
    begin
      autoPx := cw;
      if ch < autoPx then autoPx := ch;
    end
    else
      autoPx := ch;
    glyphPx := autoPx;
  end;
  if glyphPx < 1 then
  begin
    inherited DrawContent(APainter, AContentRect, AStyle);
    Exit;
  end;

  gapPx := APainter.Scale(ActiveController.Metric('--glyph-button-gap', TyGlyphButtonGap));
  TyGlyphButtonSplit(AContentRect, glyphPx, gapPx, FGlyphLayout, glyphRect, captionRect);

  // Glyph color: sentinel -> the theme's TextColor (matches the caption); else override.
  if FGlyphColor = TyGlyphButtonColorDefault then
    glyphCol := AStyle.TextColor
  else
    glyphCol := FGlyphColor;

  // Render at the CLAMPED glyph-rect size (TyGlyphButtonSplit may have shrunk the
  // rect to fit a small content box); rendering at the raw glyphPx would produce a
  // bitmap larger than its rect and bleed past it (negative centering offset).
  renderPx := glyphRect.Right - glyphRect.Left;
  if (glyphRect.Bottom - glyphRect.Top) < renderPx then
    renderPx := glyphRect.Bottom - glyphRect.Top;
  if renderPx < 1 then renderPx := 1;
  // Image icon (tinted) or font glyph — never nil; an empty transparent bitmap when the
  // name is unmapped or the font family is unset, still safe to center + free (headless).
  glyph := ResolveGlyphBitmap(renderPx, glyphCol);
  try
    gx := glyphRect.Left + ((glyphRect.Right - glyphRect.Left) - glyph.Width) div 2;
    gy := glyphRect.Top  + ((glyphRect.Bottom - glyphRect.Top) - glyph.Height) div 2;
    APainter.Bitmap.PutImage(gx, gy, glyph, dmDrawWithTransparency);
  finally
    glyph.Free;
  end;

  // Caption in the leftover rect. Skip when there's no caption or no room, so a
  // pure-icon button doesn't ask the text path to draw into an empty rect.
  if (Caption <> '') and (captionRect.Right > captionRect.Left)
     and (captionRect.Bottom > captionRect.Top) then
    inherited DrawContent(APainter, captionRect, AStyle);
end;

{ TTyGlyphButton }

constructor TTyGlyphButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGlyphLayout := glLeft;
  Width := 96;
  Height := TyDensityHeight(ActiveController, 30);
end;

{ TTyGlyphContainerButton }

function TTyGlyphContainerButton.GetStyleTypeKey: string;
begin
  Result := 'TyGlyphContainerButton';
end;

constructor TTyGlyphContainerButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGlyphLayout := glTop;
  // A larger default glyph than the auto-fit, so the ribbon icon reads big even
  // with a caption below (auto-fit would otherwise shrink to leave caption room).
  FGlyphSize := 24;
  Width := 72;
  Height := TyDensityHeight(ActiveController, 64);
end;

{ TTySpeedButton }

function TTySpeedButton.GetStyleTypeKey: string;
begin
  Result := 'TySpeedButton';
end;

constructor TTySpeedButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { A speed button is the one button that deliberately does NOT take focus — that is the
    whole point of the classic TSpeedButton: you click the toolbar and the editor you were
    typing in keeps its caret. TTyButton turns TabStop on for push buttons, so undo it
    here: a bar of ten of these would otherwise put ten dead stops in the Tab cycle, and
    a click on one would pull focus out of whatever the command acts upon. The keyboard
    path to a speed button is its mnemonic (TyAccelRegister in TTyButton), not Tab. }
  TabStop := False;
  FGlyphLayout := glLeft;
  FGroupIndex := 0;
  FAllowAllUp := False;
  // A compact, roughly square toolbar footprint by default.
  Width := 32;
  Height := TyDensityHeight(ActiveController, 32);
end;

procedure TTySpeedButton.SetGroupIndex(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FGroupIndex = AValue then Exit;
  FGroupIndex := AValue;
  Invalidate;
end;

procedure TTySpeedButton.UnpressSiblings;
var
  i: Integer;
  sib: TTySpeedButton;
begin
  if Parent = nil then Exit;
  for i := 0 to Parent.ControlCount - 1 do
    if (Parent.Controls[i] <> Self) and (Parent.Controls[i] is TTySpeedButton) then
    begin
      sib := TTySpeedButton(Parent.Controls[i]);
      if (sib.FGroupIndex = FGroupIndex) and sib.Down then
        sib.Down := False;
    end;
end;

procedure TTySpeedButton.Click;
begin
  if not Enabled then Exit;
  if FGroupIndex > 0 then
  begin
    if Down then
    begin
      // Already the pressed one. AllowAllUp -> a click toggles it back up (the
      // whole group may now be up); otherwise a radio stays pressed (no-op down).
      if FAllowAllUp then
        Down := False;
    end
    else
    begin
      Down := True;
      UnpressSiblings;
    end;
  end;
  inherited Click;   // fire OnClick / ModalResult after the group state settles
end;

end.
