unit tyControls.Card;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel;

const
  // Logical (96ppi) fallbacks for the two strip-height metrics, used only when the
  // theme defines neither token. Header: a base-font title with comfortable air.
  // Actions: tall enough to centre a default-height TTyButton (30) with breathing room.
  TyCardHeaderHeight  = 36;
  TyCardActionsHeight = 44;

type
  { The three horizontal bands of a card, in DEVICE pixels, expressed in the SAME
    coordinate space as the client rect handed in:
      Header  — the title strip across the top (empty when hidden/no room)
      Body    — the child-hosting band between the strips (never negative)
      Actions — the bottom strip (empty when hidden/no room)
    The bands tile the client exactly: Header.Bottom = Body.Top and Body.Bottom =
    Actions.Top, so nothing is double-counted and no gap is left unpainted. }
  TTyCardLayout = record
    Header: TRect;
    Body: TRect;
    Actions: TRect;
  end;

{ Pure band geometry for a card. All inputs/outputs are DEVICE px.
    AClient   — the card's client rect (the caller has already scaled the heights).
    AHeaderH  — header strip height; pass 0 for "no header".
    AActionsH — actions strip height; pass 0 for "no actions".
  Both heights are clamped so the strips can never overflow the client: the header
  wins first (a title matters more than an actions rail), the actions strip takes
  what is left, and the body absorbs the remainder — collapsing to empty rather
  than inverting. Headless-safe: no control state, no handle — the tests call it
  directly. }
function TyCardLayout(const AClient: TRect; AHeaderH, AActionsH: Integer): TTyCardLayout;

type
  { TTyCard — a card container: a themed surface carrying an optional title strip,
    a body that HOSTS CHILD CONTROLS, and an optional bottom actions strip.

    This is the modern "surface with a title" primitive. TTyGroupBox is a bordered
    caption group (its caption breaks the frame line) and TTyPanel is a bare
    container; a card is neither — it is one solid elevated surface divided into
    bands by hairline separators.

    WINDOWED (TTyCustomControl): a container must own a handle — child controls
    can only be parented to a TWinControl, and a graphic control has no handle to
    parent them to. csAcceptsControls makes the IDE designer drop controls INTO
    the body.

    Only the strips are painted by the card; the body's contents are the user's
    children. AdjustClientRect carves the child area out of the body (strips +
    themed padding excluded), so ALIGNED children lay out inside the body
    automatically. NOTE that LCL's GetClientRect returns the RAW (0,0,W,H) rect and
    AdjustClientRect only steers ALIGNED children — a child placed by hand
    (Align=alNone + SetBounds) is positioned in raw client coordinates and would
    happily sit under the header. Such children should be placed against the public
    ContentRect (which is AdjustClientRect's own output, so the two can never drift).

    Theming: 'TyCard' is the surface (background/border/radius/shadow/padding);
    'TyCardHeader' and 'TyCardActions' style their strips (background = an opt-in
    band tint, border-color/border-width = the hairline separator, and the header's
    font/color = the title). Every visual value is theme-token-driven — a card that
    lifts on hover is just a 'TyCard:hover' rule (the base already tracks hover). }

  TTyCard = class(TTyCustomControl)
  private
    FTitle: string;
    FTitleAlignment: TAlignment;
    FShowHeader: Boolean;
    FShowActions: Boolean;
    procedure SetTitle(const AValue: string);
    procedure SetTitleAlignment(AValue: TAlignment);
    procedure SetShowHeader(AValue: Boolean);
    procedure SetShowActions(AValue: Boolean);
    { Strip heights in DEVICE px at APPI, from the theme metrics. RenderTo AND
      AdjustClientRect both route through LayoutAtPPI, so the painted band and the
      carved child area cannot drift apart. }
    function HeaderHAtPPI(APPI: Integer): Integer;
    function ActionsHAtPPI(APPI: Integer): Integer;
    function LayoutAtPPI(const AClient: TRect; APPI: Integer): TTyCardLayout;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
  public
    constructor Create(AOwner: TComponent); override;
    { The painted title strip, in CLIENT coordinates; empty when ShowHeader is False. }
    function HeaderRect: TRect;
    { The painted actions strip, in CLIENT coordinates; empty when ShowActions is False. }
    function ActionsRect: TRect;
    { The child area, in CLIENT coordinates: the body band inset by the themed padding.
      This is exactly what AdjustClientRect carves — position hand-placed (alNone)
      children against it, since raw client coords would let them slide under the
      header. }
    function ContentRect: TRect;
  published
    { The header strip's title. Drawn literally (no mnemonic parsing — a card titles
      a surface, it does not activate anything), ellipsised when it does not fit. }
    property Title: string read FTitle write SetTitle;
    property TitleAlignment: TAlignment read FTitleAlignment write SetTitleAlignment
      default taLeftJustify;
    { Whether the title strip is drawn AND carved out of the child area. The flag is
      authoritative, not the Title text: a header with an empty Title still reserves
      its band, so clearing the title never makes the body jump. }
    property ShowHeader: Boolean read FShowHeader write SetShowHeader default True;
    { Whether the bottom actions strip is drawn AND carved out of the child area. }
    property ShowActions: Boolean read FShowActions write SetShowActions default False;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ ---- pure geometry ---- }

function TyCardLayout(const AClient: TRect; AHeaderH, AActionsH: Integer): TTyCardLayout;
var
  top_, bottom_, clientH, h, a: Integer;
begin
  // Normalise an inverted/degenerate client so every band comes out non-negative.
  top_ := AClient.Top;
  bottom_ := AClient.Bottom;
  if bottom_ < top_ then bottom_ := top_;
  clientH := bottom_ - top_;

  h := AHeaderH;
  if h < 0 then h := 0;
  if h > clientH then h := clientH;          // header first: it never loses to the rail
  a := AActionsH;
  if a < 0 then a := 0;
  if a > clientH - h then a := clientH - h;  // actions take only what the header left

  Result.Header := Rect(AClient.Left, top_, AClient.Right, top_ + h);
  Result.Actions := Rect(AClient.Left, bottom_ - a, AClient.Right, bottom_);
  Result.Body := Rect(AClient.Left, top_ + h, AClient.Right, bottom_ - a);
end;

{ ---- TTyCard ---- }

constructor TTyCard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Designer container: the IDE drops child controls INTO the card; they lay out in
  // the body carved by AdjustClientRect.
  ControlStyle := ControlStyle + [csAcceptsControls];
  FTitle := '';
  FTitleAlignment := taLeftJustify;
  FShowHeader := True;
  FShowActions := False;
  Width := 240;
  Height := 160;
end;

function TTyCard.GetStyleTypeKey: string;
begin
  Result := 'TyCard';
end;

function TTyCard.HeaderHAtPPI(APPI: Integer): Integer;
begin
  // Strip heights are a skin decision (a card's proportions ARE its look), so they
  // come from theme metrics rather than published sizes — same pattern as TTyGroupBox's
  // --groupbox-caption-height.
  Result := MulDiv(ActiveController.Metric('--card-header-height', TyCardHeaderHeight), APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyCard.ActionsHAtPPI(APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric('--card-actions-height', TyCardActionsHeight), APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyCard.LayoutAtPPI(const AClient: TRect; APPI: Integer): TTyCardLayout;
var
  h, a: Integer;
begin
  if FShowHeader then h := HeaderHAtPPI(APPI) else h := 0;
  if FShowActions then a := ActionsHAtPPI(APPI) else a := 0;
  Result := TyCardLayout(AClient, h, a);
end;

function TTyCard.HeaderRect: TRect;
begin
  Result := LayoutAtPPI(ClientRect, Font.PixelsPerInch).Header;
end;

function TTyCard.ActionsRect: TRect;
begin
  Result := LayoutAtPPI(ClientRect, Font.PixelsPerInch).Actions;
end;

function TTyCard.ContentRect: TRect;
begin
  // Delegate to AdjustClientRect itself: the child area has exactly ONE definition,
  // so a hand-placed child and an aligned one land in the same band by construction.
  Result := ClientRect;
  AdjustClientRect(Result);
end;

procedure TTyCard.AdjustClientRect(var ARect: TRect);
var
  S: TTyStyleSet;
  lay: TTyCardLayout;
  ppi: Integer;
begin
  inherited AdjustClientRect(ARect);
  ppi := Font.PixelsPerInch;
  S := CurrentStyle;
  // Children live in the BODY band only — never under the header or the actions rail.
  lay := LayoutAtPPI(ARect, ppi);
  ARect := lay.Body;
  // Then inset by the themed padding on all four sides, so content clears the card's
  // border and keeps the surface's breathing room. Unlike TTyGroupBox (whose caption
  // band already separates content from the caption) the card's padding.Top applies
  // BELOW the header separator — the strip is a divider, not the content's air.
  Inc(ARect.Left, MulDiv(S.Padding.Left, ppi, 96));
  Inc(ARect.Top, MulDiv(S.Padding.Top, ppi, 96));
  Dec(ARect.Right, MulDiv(S.Padding.Right, ppi, 96));
  Dec(ARect.Bottom, MulDiv(S.Padding.Bottom, ppi, 96));
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
  if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
end;

procedure TTyCard.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  Invalidate;
end;

procedure TTyCard.SetTitleAlignment(AValue: TAlignment);
begin
  if FTitleAlignment = AValue then Exit;
  FTitleAlignment := AValue;
  Invalidate;
end;

procedure TTyCard.SetShowHeader(AValue: Boolean);
begin
  if FShowHeader = AValue then Exit;
  FShowHeader := AValue;
  Realign;      // the body just grew/shrank — re-lay the children out
  Invalidate;
end;

procedure TTyCard.SetShowActions(AValue: Boolean);
begin
  if FShowActions = AValue then Exit;
  FShowActions := AValue;
  Realign;
  Invalidate;
end;

procedure TTyCard.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, hs, acts: TTyStyleSet;
  R, textRect: TRect;
  lay: TTyCardLayout;
  corners: TTyCorners;
  states: TTyStateSet;
  bw, bwLogical, sepT: Integer;
  hpad: TRect;

  { Fill a strip band with its own themed tint (when the theme set one) and stroke its
    hairline separator. The band is inset by the card's border width so it never paints
    OVER the frame, and its outer corners are rounded to match the card (a square fill
    on a rounded card would spill into the corner arcs). ATop = the header (rounded at
    the top, separator along its bottom edge); otherwise the actions rail (mirrored). }
  procedure PaintStrip(const ABand: TRect; const AStyle: TTyStyleSet; ATop: Boolean);
  var
    fillRect, sepRect: TRect;
    bandCorners: TTyCorners;
    f: TTyFill;
  begin
    if ABand.Bottom <= ABand.Top then Exit;

    // The card's border is stroked INSIDE its rect, so pull the band off it.
    if ATop then
      fillRect := Rect(ABand.Left + bw, ABand.Top + bw, ABand.Right - bw, ABand.Bottom)
    else
      fillRect := Rect(ABand.Left + bw, ABand.Top, ABand.Right - bw, ABand.Bottom - bw);
    if fillRect.Right <= fillRect.Left then Exit;

    if tpBackground in AStyle.Present then
    begin
      // Only the OUTER corners follow the card; the edge facing the body stays square. The
      // radii shrink by the border width (in LOGICAL px, matching corners' unit) because the
      // band sits inside the stroke — but by bwLogical, which is 0 when the border isn't
      // drawn, so a border-less card keeps its full radius instead of under-rounding.
      bandCorners := Default(TTyCorners);
      if ATop then
      begin
        bandCorners.TL := corners.TL - bwLogical;
        bandCorners.TR := corners.TR - bwLogical;
      end
      else
      begin
        bandCorners.BR := corners.BR - bwLogical;
        bandCorners.BL := corners.BL - bwLogical;
      end;
      if bandCorners.TL < 0 then bandCorners.TL := 0;
      if bandCorners.TR < 0 then bandCorners.TR := 0;
      if bandCorners.BR < 0 then bandCorners.BR := 0;
      if bandCorners.BL < 0 then bandCorners.BL := 0;
      if fillRect.Bottom > fillRect.Top then
        P.FillBackground(fillRect, AStyle.Background, bandCorners);
    end;

    // The hairline separator between the strip and the body — a filled band, not a
    // border: it is one edge, and squaring it keeps it crisp at any radius.
    if TyBorderVisible(AStyle) then
    begin
      if ATop then
        sepRect := Rect(fillRect.Left, ABand.Bottom - sepT, fillRect.Right, ABand.Bottom)
      else
        sepRect := Rect(fillRect.Left, ABand.Top, fillRect.Right, ABand.Top + sepT);
      if sepRect.Bottom > sepRect.Top then
      begin
        f := Default(TTyFill);
        f.Kind := tfkSolid;
        f.Color := AStyle.BorderColor;
        P.FillBackground(sepRect, f, 0);
      end;
    end;
  end;

begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // One themed surface spans the WHOLE card — background, border, radius, shadow.
    // The strips are bands drawn ON it, not separate frames.
    DrawFrame(P, R, S);

    corners := TyEffectiveCorners(S);
    // The band is inset by the border ONLY when the border is actually stroked. bw is the
    // inset in DEVICE px (for the fill rect); bwLogical is the SAME inset in LOGICAL px, for
    // shrinking the band's corner radii (FillBackground scales corners itself). When the
    // border is present-but-not-drawn, both are 0 — the band fills flush and keeps the card's
    // full corner radius instead of under-rounding by a border that never appears.
    if TyBorderVisible(S) then
    begin
      bw := P.Scale(S.BorderWidth);
      bwLogical := S.BorderWidth;
    end
    else
    begin
      bw := 0;
      bwLogical := 0;
    end;
    lay := LayoutAtPPI(R, APPI);
    // The strips share the card's states, so a disabled/hovered card carries its
    // header and rail with it (':disabled { opacity }' on all three, for instance).
    states := CurrentStates;

    if FShowHeader and (lay.Header.Bottom > lay.Header.Top) then
    begin
      hs := ActiveController.Model.ResolveStyle('TyCardHeader', StyleClass, states);
      sepT := P.Scale(hs.BorderWidth);
      if sepT < 1 then sepT := 1;
      PaintStrip(lay.Header, hs, True);

      if FTitle <> '' then
      begin
        // Horizontal air for the title: the header's own padding when the theme set one,
        // else the card's — so by default the title lines up with the body's content.
        if tpPadding in hs.Present then hpad := hs.Padding else hpad := S.Padding;
        // A skin that styles TyCard but forgets TyCardHeader resolves an EMPTY style set,
        // whose colour is $00000000 — a fully TRANSPARENT (invisible) title. Fall back to
        // the card's own text colour so a partial skin degrades to a readable card instead
        // of a blank strip. (Same class of bug as the font-size-0 one TyFallbackFontSize
        // guards; the size is already covered by ResolveFontSize.)
        if not (tpTextColor in hs.Present) then hs.TextColor := S.TextColor;
        textRect := Rect(
          lay.Header.Left + bw + P.Scale(hpad.Left),
          lay.Header.Top + bw,
          lay.Header.Right - bw - P.Scale(hpad.Right),
          lay.Header.Bottom - sepT);
        if textRect.Right > textRect.Left then
          P.DrawText(textRect, FTitle, hs.FontName, ResolveFontSize(hs), hs.FontWeight,
            hs.TextColor, FTitleAlignment, tlCenter, True);
      end;
    end;

    if FShowActions and (lay.Actions.Bottom > lay.Actions.Top) then
    begin
      acts := ActiveController.Model.ResolveStyle('TyCardActions', StyleClass, states);
      sepT := P.Scale(acts.BorderWidth);
      if sepT < 1 then sepT := 1;
      PaintStrip(lay.Actions, acts, False);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCard.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
</content>
