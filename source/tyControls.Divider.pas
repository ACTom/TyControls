unit tyControls.Divider;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;

type
  { The geometry of a labelled divider, in DEVICE pixels relative to the content
    rect's top-left. Caption occupies CaptionRect (empty when there is no caption);
    the horizontal rule is drawn as up to two segments:
      LeftRule  — from LeftRule.Left..LeftRule.Right (empty Right<=Left = none)
      RightRule — likewise
    Both segments share the same vertical band (RuleY, 1 logical-px thick — the
    caller strokes it). taLeftJustify uses RightRule only; taRightJustify uses
    LeftRule only; taCenter uses both (rule on each side of the caption).

    The two names stay PHYSICALLY true under mirroring: TyDividerLayout's
    ARightToLeft reflects the rects and swaps the pair, so LeftRule is the segment
    nearer x=0 whichever way the divider reads. (Which one is "the" segment does
    change: a mirrored taLeftJustify uses LeftRule.) }
  TTyDividerLayout = record
    CaptionRect: TRect;   // where the caption text is drawn (empty => no caption)
    LeftRule: TRect;      // left rule segment (Left..Right span; Top..Bottom band)
    RightRule: TRect;     // right rule segment
  end;

const
  { LeftIndent's "leave it to Alignment" value, and its default.

    LCL's TDividerBevel spells three things with one Integer LeftIndent
    (dividerbevel.pas:322-333): > 0 = that many pixels in, 0 = hard left,
    < 0 = centred. It has no way to say "right". Alignment has no way to say
    "60px in". Neither type contains the other, so TTyDivider carries both —
    and the tie is broken one way only: a LeftIndent >= 0 is an explicit pixel
    position and WINS; anything negative means "I am not using this knob, let
    Alignment place the caption".

    Porting note (the one place the two disagree): TDividerBevel's
    LeftIndent < 0 means CENTRED, whereas here every negative value means
    "defer". Write centring as Alignment := taCenter — which is what it says. }
  TyDividerIndentAuto = -1;

{ Pure geometry for a labelled section divider. All inputs/outputs are DEVICE px.
    AClientWidth  — the content-rect width (already inset by padding), device px.
    AClientHeight — the content-rect height, device px (rule is vertically centred).
    ACaptionWidth — measured caption width, device px (0 => no caption).
    AAlign        — the three-position placement, used only when ALeftIndent < 0.
    ALeftIndent   — device-px offset of the caption's LEADING edge from the content
                    rect's left; < 0 (TyDividerIndentAuto) hands placement back to
                    AAlign. Clamped so the caption never runs past the right edge.
    AGap          — device-px gap between the caption and an adjacent rule segment.
    AMinRule      — minimum device-px length below which a rule segment is dropped
                    (so a caption that fills the width doesn't leave a 1px nub).
    ARuleThick    — rule thickness, device px (the returned bands are this tall).
    ARightToLeft  — MIRROR the finished layout about the content rect's vertical centre
                    line. AAlign and ALeftIndent are then read as READING-ORDER
                    quantities: taLeftJustify puts the caption at the right edge and
                    ALeftIndent counts leftwards from it. Done as one reflection of the
                    finished rects rather than three mirrored branches, so a divider can
                    never come out with a gap or an overlap the left-to-right one did not
                    have — the property that is easy to break with a hand-written -1.
  Segments that would be shorter than AMinRule collapse to empty (Right = Left).
  Headless-safe: no control state, no handle — the tests call it directly. }
function TyDividerLayout(AClientWidth, AClientHeight, ACaptionWidth: Integer;
  AAlign: TAlignment; ALeftIndent: Integer;
  AGap, AMinRule, ARuleThick: Integer;
  ARightToLeft: Boolean = False): TTyDividerLayout;

type
  TTyDivider = class(TTyGraphicControl)
  private
    FAlignment: TAlignment;
    FLeftIndent: Integer;
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLeftIndent(AValue: Integer);
    { TTyGraphicControl has no ResolveFontSize helper (that lives on
      TTyCustomControl); mirror TTyLabel and resolve it locally. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
  protected
    { Repaint when Caption/Text changes -- the LCL hook that replaces our old setter. }
    procedure TextChanged; override;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    { Caption is TControl's, not a second string of our own.

      It used to be a field-backed property shadowing TControl.Caption, so a control had
      TWO captions: `P.Caption := 'x'` set ours and left TControl.Text empty, while
      anything reading Text -- an action link, an accessibility query, TControl's own
      csSetCaption wiring, generic code that walks TControl -- saw ''. On LCL these are one
      string: Caption IS Text, routed through RealSetText, and a repaint is arranged by
      overriding TextChanged. That is what this does now. }
    property Caption;
    { Where the caption sits relative to the rule:
        taLeftJustify  — caption at the left, rule fills the space to its right;
        taRightJustify — mirror (caption at the right, rule to its left);
        taCenter       — caption centred with a rule segment on each side.
      Ignored while LeftIndent >= 0. }
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    { LOGICAL-pixel offset of the caption's leading edge from the content rect's
      left, the knob TDividerBevel calls LeftIndent (dividerbevel.pas:80). >= 0
      overrides Alignment; TyDividerIndentAuto (-1, the default) leaves Alignment
      in charge — see that constant for the LCL porting note and why the default
      is "off" rather than LCL's 60 (which would silently re-indent every divider
      that already exists).

      Logical, not device, px: it is scaled through the painter alongside the gap
      and rule thickness, so an indent set once looks the same at 96 and 192 dpi. }
    property LeftIndent: Integer read FLeftIndent write SetLeftIndent default TyDividerIndentAuto;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

function TyDividerLayout(AClientWidth, AClientHeight, ACaptionWidth: Integer;
  AAlign: TAlignment; ALeftIndent: Integer;
  AGap, AMinRule, ARuleThick: Integer;
  ARightToLeft: Boolean = False): TTyDividerLayout;
var
  ruleTop, ruleBot, capLeft, capRight, lRight, rLeft: Integer;
  span, swap: TRect;

  { Reflect one rect about the content rect's vertical centre. LCL's own five-liner
    (controls.pp:2966) rather than a hand-written formula, because reflecting a gapless
    tiling is exactly where an off-by-one shows up as a hairline seam and nowhere else. }
  function Mirror(const R: TRect): TRect;
  begin
    { An empty segment must stay empty, not become a zero-width band parked at the far
      edge, or "is there a rule here" stops being answerable by Right > Left. }
    if R.Right <= R.Left then Exit(R);
    Result := BidiFlipRect(R, span, True);
  end;

begin
  Result.CaptionRect := Rect(0, 0, 0, 0);
  Result.LeftRule := Rect(0, 0, 0, 0);
  Result.RightRule := Rect(0, 0, 0, 0);
  if AClientWidth <= 0 then Exit;
  span := Rect(0, 0, AClientWidth, AClientHeight);
  if AGap < 0 then AGap := 0;
  if AMinRule < 0 then AMinRule := 0;
  if ARuleThick < 1 then ARuleThick := 1;

  // Vertically centre the rule band in the content height.
  ruleTop := (AClientHeight - ARuleThick) div 2;
  if ruleTop < 0 then ruleTop := 0;
  ruleBot := ruleTop + ARuleThick;

  // Clamp a caption that would overflow the whole width; a negative/zero caption
  // width means "no caption" and the rule fills the entire span.
  if ACaptionWidth < 0 then ACaptionWidth := 0;
  if ACaptionWidth > AClientWidth then ACaptionWidth := AClientWidth;

  if ACaptionWidth = 0 then
  begin
    // No caption: a single full-width rule (returned as RightRule so callers that
    // only look at one segment still see it; LeftRule stays empty).
    // Exits BEFORE the mirroring below, and must: a full-width band is its own
    // reflection, and swapping it into LeftRule would break that convention for
    // right-to-left dividers alone, for no visible gain.
    Result.RightRule := Rect(0, ruleTop, AClientWidth, ruleBot);
    Exit;
  end;

  if ALeftIndent >= 0 then
  begin
    // Explicit pixel placement wins over AAlign. Clamp so the caption stays
    // inside the content rect: an indent past (width - caption) would push the
    // text off the right edge, and a divider that silently loses its label is
    // worse than one whose indent quietly stops growing.
    capLeft := ALeftIndent;
    if capLeft > AClientWidth - ACaptionWidth then
      capLeft := AClientWidth - ACaptionWidth;
    if capLeft < 0 then capLeft := 0;
    capRight := capLeft + ACaptionWidth;
    Result.CaptionRect := Rect(capLeft, 0, capRight, AClientHeight);
    // A rule on each side, each dropped if too short. At ALeftIndent = 0 the
    // left segment collapses on its own (0 - AGap < AMinRule), which is exactly
    // taLeftJustify -- the two spellings agree, as they must.
    lRight := capLeft - AGap;
    if lRight >= AMinRule then
      Result.LeftRule := Rect(0, ruleTop, lRight, ruleBot);
    rLeft := capRight + AGap;
    if (AClientWidth - rLeft) >= AMinRule then
      Result.RightRule := Rect(rLeft, ruleTop, AClientWidth, ruleBot);
  end
  else
  case AAlign of
    taRightJustify:
      begin
        // Caption hugs the right edge; rule fills the space to its LEFT.
        capRight := AClientWidth;
        capLeft := AClientWidth - ACaptionWidth;
        Result.CaptionRect := Rect(capLeft, 0, capRight, AClientHeight);
        lRight := capLeft - AGap;
        if lRight >= AMinRule then
          Result.LeftRule := Rect(0, ruleTop, lRight, ruleBot);
      end;
    taCenter:
      begin
        // Caption centred; a rule segment on EACH side.
        capLeft := (AClientWidth - ACaptionWidth) div 2;
        capRight := capLeft + ACaptionWidth;
        Result.CaptionRect := Rect(capLeft, 0, capRight, AClientHeight);
        lRight := capLeft - AGap;
        if lRight >= AMinRule then
          Result.LeftRule := Rect(0, ruleTop, lRight, ruleBot);
        rLeft := capRight + AGap;
        if (AClientWidth - rLeft) >= AMinRule then
          Result.RightRule := Rect(rLeft, ruleTop, AClientWidth, ruleBot);
      end;
  else
    // taLeftJustify (default): caption at the left, rule fills the space to its RIGHT.
    Result.CaptionRect := Rect(0, 0, ACaptionWidth, AClientHeight);
    rLeft := ACaptionWidth + AGap;
    if (AClientWidth - rLeft) >= AMinRule then
      Result.RightRule := Rect(rLeft, ruleTop, AClientWidth, ruleBot);
  end;

  { MIRROR, once, at the end -- so both placement rules above (explicit indent AND the
    three-way Alignment) get it from the same three lines, and neither can be the branch
    somebody forgot. Everything up to here is the left-to-right layout verbatim, which is
    also why ARightToLeft = False costs exactly nothing. The swap keeps the field names
    physically honest (see TTyDividerLayout). }
  if ARightToLeft then
  begin
    Result.CaptionRect := Mirror(Result.CaptionRect);
    swap := Mirror(Result.LeftRule);
    Result.LeftRule := Mirror(Result.RightRule);
    Result.RightRule := swap;
  end;
end;

{ TTyDivider }

constructor TTyDivider.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAlignment := taLeftJustify;
  FLeftIndent := TyDividerIndentAuto;
  Width := 150;
  Height := TyDensityHeight(ActiveController, 24);
end;

function TTyDivider.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyLabel': this is a RULE, not text chrome — it strokes solid bands around an optional caption.
    Added to 'TyLabel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyDivider';
end;

function TTyDivider.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

procedure TTyDivider.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TTyDivider.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyDivider.SetLeftIndent(AValue: Integer);
begin
  { Every negative value is the same state ("Alignment decides"), so normalise to
    the named one -- otherwise -2 and -1 would both work but only one of them
    would match the published default and get written to the .lfm. }
  if AValue < 0 then AValue := TyDividerIndentAuto;
  if FLeftIndent = AValue then Exit;
  FLeftIndent := AValue;
  Invalidate;
end;

procedure TTyDivider.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect: TRect;
  Lay: TTyDividerLayout;
  fontSize, capW, gap, minRule, ruleThick, indent: Integer;
  ruleColor: TTyColor;

  procedure StrokeSeg(const ASeg: TRect);
  var
    f: TTyFill;
  begin
    if ASeg.Right <= ASeg.Left then Exit;
    f := Default(TTyFill);
    f.Kind := tfkSolid;
    f.Color := ruleColor;
    // A filled 1px (scaled) band — square corners; the rule is a hairline, not a border.
    P.FillBackground(Rect(ASeg.Left, ASeg.Top, ASeg.Right, ASeg.Bottom), f, 0);
  end;

begin
  P := TTyPainter.Create;
  try
    { MIRRORING: the rule/caption split comes from the pure function (mirrored below), the
      caption's own alignment inside its rect from the painter. Not interactive at all, so
      there is nothing to keep the hit test in step with. }
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    S := CurrentStyle;
    fontSize := ResolveFontSize(S);
    // The divider is a transparent overlay (like a default TTyLabel): honor opacity
    // (e.g. :disabled { opacity: 0.5 }) but never paint the theme background fill,
    // so it sits cleanly on whatever surface hosts it.
    if tpOpacity in S.Present then
      P.Opacity := S.Opacity;
    // Inset by padding so the caption/rule keep the themed left/right breathing room.
    ContentRect := Rect(
      P.Scale(S.Padding.Left),
      P.Scale(S.Padding.Top),
      (ARect.Right - ARect.Left) - P.Scale(S.Padding.Right),
      (ARect.Bottom - ARect.Top) - P.Scale(S.Padding.Bottom)
    );
    if ContentRect.Right < ContentRect.Left then ContentRect.Right := ContentRect.Left;
    if ContentRect.Bottom < ContentRect.Top then ContentRect.Bottom := ContentRect.Top;

    // Rule colour is theme-token-driven: prefer the resolved border colour; if the
    // theme set none, derive a hairline from the text colour at reduced alpha (never
    // a hard-coded colour). Both come straight from the resolved TyLabel style.
    if (tpBorderColor in S.Present) and (TyAlphaOf(S.BorderColor) > 0) then
      ruleColor := S.BorderColor
    else
      ruleColor := TyRGBA(TyRedOf(S.TextColor), TyGreenOf(S.TextColor),
        TyBlueOf(S.TextColor), TyAlphaOf(S.TextColor) * 40 div 100);

    // Measure the caption in the SAME font DrawText will use.
    capW := 0;
    if Caption <> '' then
      capW := P.MeasureText(Caption, S.FontName, fontSize, S.FontWeight).cx;

    gap := P.Scale(6);
    minRule := P.Scale(4);
    ruleThick := P.Scale(1);
    if ruleThick < 1 then ruleThick := 1;
    // The sentinel must survive scaling: P.Scale(-1) is not guaranteed to stay
    // negative, and a rounded-to-0 "auto" would silently become "hard left".
    if FLeftIndent >= 0 then indent := P.Scale(FLeftIndent)
    else                     indent := TyDividerIndentAuto;

    { LeftIndent keeps its NAME under mirroring and changes its meaning to "indent from the
      reading start", i.e. from the right edge. Renaming it would be a breaking change for
      every .lfm that carries one, and the property is documented rather than renamed --
      plans/2026-08-04-rtl-mirroring-scope.md §6.3 item 6. }
    Lay := TyDividerLayout(ContentRect.Right - ContentRect.Left,
      ContentRect.Bottom - ContentRect.Top, capW, FAlignment, indent,
      gap, minRule, ruleThick, IsRightToLeft);

    // Offset the layout (content-local) into ContentRect and paint.
    StrokeSeg(Rect(ContentRect.Left + Lay.LeftRule.Left, ContentRect.Top + Lay.LeftRule.Top,
      ContentRect.Left + Lay.LeftRule.Right, ContentRect.Top + Lay.LeftRule.Bottom));
    StrokeSeg(Rect(ContentRect.Left + Lay.RightRule.Left, ContentRect.Top + Lay.RightRule.Top,
      ContentRect.Left + Lay.RightRule.Right, ContentRect.Top + Lay.RightRule.Bottom));

    if (Caption <> '') and (Lay.CaptionRect.Right > Lay.CaptionRect.Left) then
      P.DrawText(
        Rect(ContentRect.Left + Lay.CaptionRect.Left, ContentRect.Top + Lay.CaptionRect.Top,
          ContentRect.Left + Lay.CaptionRect.Right, ContentRect.Top + Lay.CaptionRect.Bottom),
        Caption, S.FontName, fontSize, S.FontWeight, S.TextColor,
        FAlignment, tlCenter, True);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyDivider.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
