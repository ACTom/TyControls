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
    LeftRule only; taCenter uses both (rule on each side of the caption). }
  TTyDividerLayout = record
    CaptionRect: TRect;   // where the caption text is drawn (empty => no caption)
    LeftRule: TRect;      // left rule segment (Left..Right span; Top..Bottom band)
    RightRule: TRect;     // right rule segment
  end;

{ Pure geometry for a labelled section divider. All inputs/outputs are DEVICE px.
    AClientWidth  — the content-rect width (already inset by padding), device px.
    AClientHeight — the content-rect height, device px (rule is vertically centred).
    ACaptionWidth — measured caption width, device px (0 => no caption).
    AGap          — device-px gap between the caption and an adjacent rule segment.
    AMinRule      — minimum device-px length below which a rule segment is dropped
                    (so a caption that fills the width doesn't leave a 1px nub).
    ARuleThick    — rule thickness, device px (the returned bands are this tall).
  Segments that would be shorter than AMinRule collapse to empty (Right = Left).
  Headless-safe: no control state, no handle — the tests call it directly. }
function TyDividerLayout(AClientWidth, AClientHeight, ACaptionWidth: Integer;
  AAlign: TAlignment; AGap, AMinRule, ARuleThick: Integer): TTyDividerLayout;

type
  TTyDivider = class(TTyGraphicControl)
  private
    FCaption: string;
    FAlignment: TAlignment;
    procedure SetCaption(const AValue: string);
    procedure SetAlignment(AValue: TAlignment);
    { TTyGraphicControl has no ResolveFontSize helper (that lives on
      TTyCustomControl); mirror TTyLabel and resolve it locally. }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;
    { Where the caption sits relative to the rule:
        taLeftJustify  — caption at the left, rule fills the space to its right;
        taRightJustify — mirror (caption at the right, rule to its left);
        taCenter       — caption centred with a rule segment on each side. }
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

function TyDividerLayout(AClientWidth, AClientHeight, ACaptionWidth: Integer;
  AAlign: TAlignment; AGap, AMinRule, ARuleThick: Integer): TTyDividerLayout;
var
  ruleTop, ruleBot, capLeft, capRight, lRight, rLeft: Integer;
begin
  Result.CaptionRect := Rect(0, 0, 0, 0);
  Result.LeftRule := Rect(0, 0, 0, 0);
  Result.RightRule := Rect(0, 0, 0, 0);
  if AClientWidth <= 0 then Exit;
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
    Result.RightRule := Rect(0, ruleTop, AClientWidth, ruleBot);
    Exit;
  end;

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
end;

{ TTyDivider }

constructor TTyDivider.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaption := '';
  FAlignment := taLeftJustify;
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

procedure TTyDivider.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Invalidate;
end;

procedure TTyDivider.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyDivider.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect: TRect;
  Lay: TTyDividerLayout;
  fontSize, capW, gap, minRule, ruleThick: Integer;
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
    P.BeginPaint(ACanvas, ARect, APPI);
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
    if FCaption <> '' then
      capW := P.MeasureText(FCaption, S.FontName, fontSize, S.FontWeight).cx;

    gap := P.Scale(6);
    minRule := P.Scale(4);
    ruleThick := P.Scale(1);
    if ruleThick < 1 then ruleThick := 1;

    Lay := TyDividerLayout(ContentRect.Right - ContentRect.Left,
      ContentRect.Bottom - ContentRect.Top, capW, FAlignment, gap, minRule, ruleThick);

    // Offset the layout (content-local) into ContentRect and paint.
    StrokeSeg(Rect(ContentRect.Left + Lay.LeftRule.Left, ContentRect.Top + Lay.LeftRule.Top,
      ContentRect.Left + Lay.LeftRule.Right, ContentRect.Top + Lay.LeftRule.Bottom));
    StrokeSeg(Rect(ContentRect.Left + Lay.RightRule.Left, ContentRect.Top + Lay.RightRule.Top,
      ContentRect.Left + Lay.RightRule.Right, ContentRect.Top + Lay.RightRule.Bottom));

    if (FCaption <> '') and (Lay.CaptionRect.Right > Lay.CaptionRect.Left) then
      P.DrawText(
        Rect(ContentRect.Left + Lay.CaptionRect.Left, ContentRect.Top + Lay.CaptionRect.Top,
          ContentRect.Left + Lay.CaptionRect.Right, ContentRect.Top + Lay.CaptionRect.Bottom),
        FCaption, S.FontName, fontSize, S.FontWeight, S.TextColor,
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
