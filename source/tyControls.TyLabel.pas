unit tyControls.TyLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.Accel;
type
  TTyLabel = class(TTyGraphicControl)
  private
    FAlignment: TAlignment;
    FLayout: TTextLayout;
    FWordWrap: Boolean;
    FTransparent: Boolean;
    FFocusControl: TWinControl;
    FRefitting: Boolean;   // guards the size-floor refresh in Invalidate against re-entry
    procedure SetAlignment(AValue: TAlignment);
    procedure SetLayout(AValue: TTextLayout);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetTransparent(AValue: Boolean);
    procedure SetFocusControl(AValue: TWinControl);
    { Resolve the effective font size. TTyGraphicControl has no ResolveFontSize, so this
      thin method delegates to the shared TyResolveFontSize (theme font-size → explicit
      control font → theme --font-size-base var → inherited/default). }
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    { Greedy word-wrap of AText so each line fits AMaxWidth pixels, measured with
      the given (already PPI-scaled) canvas font. Returns the lines. }
    procedure WrapText(const AText: string; AMaxWidthPx: Integer;
      ACanvas: TCanvas; ALines: TStrings);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
    function DialogChar(var Message: TLMKey): Boolean; override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    { Clamp the label so it can never be smaller than the text it must draw. A hand-set
      Height and the theme's metrics are REQUESTS; what is possible is decided by the font
      and the padding, and only the control knows both — on Linux/Qt6 the same 9pt CJK
      caption resolves a fallback face whose ink is taller than Windows', and both text
      paths draw clipped, so a box shorter than the ink loses the BOTTOM of the text.

      Constraints, deliberately, and NOT CalculatePreferredSize's height: a proposed height
      is negotiated with the parent, and that negotiation is what once bounced a control
      against a TTyToolBar's pinned height until LCL aborted with "ChangeBounds loop
      detected". Constraints clamp inside SetBounds, with no negotiation.

      WordWrap is the interesting case, and it gets a DIFFERENT floor:
      - No width floor at all. A wrapping label is MEANT to be narrower than its text —
        flooring it at the widest line would make wrapping impossible, and the message
        dialog (which measures the block at a column it chooses, then pins that column)
        would snap back into the single-line ribbon it used to be.
      - The height floor is the block measured WITHOUT wrapping, i.e. only the breaks the
        author wrote. That number is the one thing about a wrapped block that does not move
        with the width: any width can only ADD breaks, never remove an authored one. The
        block at the CURRENT width would have been the tempting answer and is a trap — it
        is a different number for every width, so a label whose bounds are set width-and-
        height together (again: the message dialog) would be clamped by a height measured
        at the width it had a moment ago. }
    procedure UpdateSizeConstraints;
    { A theme switch reaches every control as a bare Invalidate, and the new theme owns the
      font and the padding the floor is derived from — so it has to be recomputed here. }
    procedure Invalidate; override;
    { Caption changes at runtime route here (CM_TEXTCHANGED). When AutoSize is on,
      re-measure so the label grows/shrinks to the new text (mirrors native
      TCustomLabel.TextChanged -> UpdateSize). }
    procedure TextChanged; override;
    { A WordWrap+AutoSize label's height depends on its width, so a width change must
      re-wrap and re-fit. Guarded by WidthChanged (computed before inherited), which
      settles once AdjustSize stops changing the width (native TCustomLabel idiom). }
    procedure DoSetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Measure the caption: width = widest line, height = line-count * line-height.
      Honors WordWrap at AAvailWidthPx (only used when WordWrap=True; <=0 = no wrap).
      PUBLIC because a host that sizes ITSELF around a label needs the text's real wrapped
      size before it can decide its own bounds — the message dialog does exactly that, and
      pinning a guessed box instead is how it used to cut every message past two lines. }
    procedure MeasureCaption(APPI, AAvailWidthPx: Integer; out AWidthPx, AHeightPx: Integer);
  published
    property Caption;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property Layout: TTextLayout read FLayout write SetLayout default tlCenter;
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    property AutoSize;
    property Transparent: Boolean read FTransparent write SetTransparent default True;
    property FocusControl: TWinControl read FFocusControl write SetFocusControl;
  end;

implementation

constructor TTyLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  FAlignment := taLeftJustify;
  FLayout := tlCenter;
  FWordWrap := False;
  FTransparent := True;
end;

destructor TTyLabel.Destroy;
begin
  TyAccelUnregister(Self);
  inherited Destroy;
end;

function TTyLabel.DialogChar(var Message: TLMKey): Boolean;
begin
  if (FFocusControl <> nil) and TyIsAccelKey(Message, Caption) then
  begin
    Click;   // TTyLabel.Click focuses FFocusControl
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
end;

function TTyLabel.GetStyleTypeKey: string;
begin
  Result := 'TyLabel';
end;

function TTyLabel.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  { TTyGraphicControl has no ResolveFontSize helper, so it delegates to the shared one —
    which recovers the theme's --font-size-base when a skin suppresses the typeKey font-size
    (else graphic labels fall back to the inherited OS font and render enlarged). }
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

procedure TTyLabel.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyLabel.SetLayout(AValue: TTextLayout);
begin
  if FLayout = AValue then Exit;
  FLayout := AValue;
  Invalidate;
end;

procedure TTyLabel.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  { The floor means a different thing on each side of this flag (see UpdateSizeConstraints),
    so refresh it BEFORE AdjustSize — otherwise a label that is given its caption first and
    wrapped second spends one layout pass floored at the width of its whole text on one
    line, which is exactly the shape the message dialog builds. }
  UpdateSizeConstraints;
  if AutoSize then
    InvalidatePreferredSize;
  AdjustSize;
  Invalidate;
end;

procedure TTyLabel.SetTransparent(AValue: Boolean);
begin
  if FTransparent = AValue then Exit;
  FTransparent := AValue;
  Invalidate;
end;

procedure TTyLabel.SetFocusControl(AValue: TWinControl);
begin
  if FFocusControl = AValue then Exit;
  if FFocusControl <> nil then
    FFocusControl.RemoveFreeNotification(Self);
  FFocusControl := AValue;
  if FFocusControl <> nil then
    FFocusControl.FreeNotification(Self);
end;

procedure TTyLabel.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FFocusControl) then
    FFocusControl := nil;
end;

procedure TTyLabel.Click;
begin
  inherited Click;
  if (FFocusControl <> nil) and FFocusControl.CanFocus then
    FFocusControl.SetFocus;
end;

procedure TTyLabel.UpdateSizeConstraints;
var
  S: TTyStyleSet;
  ppi, padH, w, h: Integer;
begin
  if csDestroying in ComponentState then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  if FWordWrap then
  begin
    { AAvailWidthPx = 0 is MeasureCaption's "do not wrap", so this is the authored-breaks
      block — the width-independent lower bound (see the declaration). }
    MeasureCaption(ppi, 0, w, h);
    S := CurrentStyle;
    padH := MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);
    Constraints.MinWidth := 0;
    Constraints.MinHeight := h + padH;
  end
  else
  begin
    { No wrap: CalculatePreferredSize already measures exactly this block plus the style's
      padding — the padding RenderTo insets by — so the floor asks IT rather than repeating
      the arithmetic, and the two can never disagree. }
    w := 0;
    h := 0;
    CalculatePreferredSize(w, h, True);
    Constraints.MinHeight := h;
  end;
  { HEIGHT ONLY, for a label, in both branches. Clipping a caption vertically is never
    something anyone asked for -- that is the bug this floor exists to stop. Being NARROWER
    than the text is different: a label ellipsises, and a status strip or a fixed column that
    deliberately shows 'Some very long value...' is an ordinary layout, not a mistake. A width
    floor would silently overrule the Width its host set, which is exactly what it did: the
    label test set Width := 60 and got the whole caption's width back.
    Buttons are the opposite case and DO floor their width -- there the caption is the
    affordance, and an ellipsised button label is a usability failure rather than a layout. }
  Constraints.MinWidth := 0;
end;

procedure TTyLabel.Invalidate;
begin
  inherited Invalidate;
  { A theme switch arrives as a bare Invalidate (the controller broadcasts one to every
    registered control), and the new theme brings a different font and padding — so the
    floor derived from them moved too. FRefitting guards the re-entry: setting a constraint
    can trigger a resize, and a resize repaints. }
  if not FRefitting and not (csDestroying in ComponentState) then
  begin
    FRefitting := True;
    try
      UpdateSizeConstraints;
    finally
      FRefitting := False;
    end;
  end;
end;

procedure TTyLabel.TextChanged;
begin
  inherited TextChanged;
  UpdateSizeConstraints;   // the new caption needs a different floor
  if AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
  Invalidate;
end;

procedure TTyLabel.DoSetBounds(ALeft, ATop, AWidth, AHeight: Integer);
var
  WidthChanged: Boolean;
begin
  WidthChanged := AWidth <> Width;
  inherited DoSetBounds(ALeft, ATop, AWidth, AHeight);
  if WidthChanged and FWordWrap and AutoSize then
  begin
    InvalidatePreferredSize;
    AdjustSize;
  end;
end;

procedure TTyLabel.WrapText(const AText: string; AMaxWidthPx: Integer;
  ACanvas: TCanvas; ALines: TStrings);
{ Greedy CJK-aware wrap. The algorithm now lives in tyControls.Painter (TyWrapTextCJK)
  so TTyNotification shares the exact same line-breaking; kept as a method for the two
  internal call sites. Behaviour is byte-identical — TestWordWrapCJK guards it. }
begin
  TyWrapTextCJK(AText, AMaxWidthPx, ACanvas, ALines);
end;

procedure TTyLabel.MeasureCaption(APPI, AAvailWidthPx: Integer;
  out AWidthPx, AHeightPx: Integer);
{ The body of this used to live here: build a measuring bitmap, set the four font fields,
  split or wrap, widest line x line count. It is now TyMeasureTextBlock in tyControls.Painter,
  because a size FLOOR needs exactly this measurement and every control that grows one would
  otherwise carry a near-copy — near-copies are how measuring and drawing drift apart.
  Behaviour is unchanged: the same font, the same 'Ag' line box, the same wrap. }
var
  S: TTyStyleSet;
  mpos, wrapW: Integer;
  disp: string;
begin
  S := CurrentStyle;
  TyParseMnemonic(Caption, disp, mpos);
  if FWordWrap then
    wrapW := AAvailWidthPx    // <=0 there already meant "unconstrained", and still does
  else
    wrapW := 0;
  TyMeasureTextBlock(disp, S.FontName, ResolveFontSize(S), S.FontWeight, APPI,
    wrapW, TyLineHeight(ActiveController), AWidthPx, AHeightPx);
end;

procedure TTyLabel.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, availW, padW, padH, tw, th: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  padW := MulDiv(S.Padding.Left + S.Padding.Right, ppi, 96);
  padH := MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96);

  // For WordWrap, wrap at the current content width; non-wrap measures the whole line.
  if FWordWrap then
  begin
    availW := Width - padW;
    if availW < 1 then availW := 1;
  end
  else
    availW := 0;

  MeasureCaption(ppi, availW, tw, th);
  PreferredWidth := tw + padW;
  PreferredHeight := th + padH;
  if PreferredWidth < 1 then PreferredWidth := 1;
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

procedure TTyLabel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect, LineRect: TRect;
  Meas: TBitmap;
  Lines: TStringList;
  lineH, i, availW, fontSize, contentH, blockH, yOff, mp: Integer;
  dispCap: string;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    fontSize := ResolveFontSize(S);
    TyParseMnemonic(Caption, dispCap, mp);
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    // When opaque, paint the style background (DrawFrame fill). When transparent
    // (default), skip the fill so no background paints regardless of theme — but
    // still honor the style opacity (e.g. :disabled { opacity: 0.5 }) so the
    // default transparent label dims exactly as before.
    if not FTransparent then
      DrawFrame(P, ContentRect, S)
    else if tpOpacity in S.Present then
      P.Opacity := S.Opacity;
    // Inset content by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );

    if FWordWrap then
    begin
      Meas := TBitmap.Create;
      Lines := TStringList.Create;
      try
        Meas.SetSize(1, 1);
        TyConfigureMeasureFont(Meas.Canvas, S.FontName, fontSize, S.FontWeight, APPI);
        { The SAME line box MeasureCaption used, or the label draws its lines at the font's
          natural spacing inside a box it sized for the theme's --line-height. }
        lineH := TyLineHeight(ActiveController);
        if lineH > 0 then
          lineH := MulDiv(lineH, APPI, 96)
        else
          lineH := TyNaturalLineHeight(Meas.Canvas);
        availW := ContentRect.Right - ContentRect.Left;
        WrapText(dispCap, availW, Meas.Canvas, Lines);
        // Position the whole wrapped block per Layout (native vertically anchors
        // the block, not each line): compute a one-off vertical offset, then draw
        // each wrapped line top-anchored within its single-line rect.
        contentH := ContentRect.Bottom - ContentRect.Top;
        blockH := Lines.Count * lineH;
        case FLayout of
          tlCenter: yOff := Max(0, (contentH - blockH) div 2);
          tlBottom: yOff := Max(0, contentH - blockH);
        else
          yOff := 0; // tlTop
        end;
        for i := 0 to Lines.Count - 1 do
        begin
          LineRect := Rect(ContentRect.Left, ContentRect.Top + yOff + i * lineH,
            ContentRect.Right, ContentRect.Top + yOff + (i + 1) * lineH);
          if LineRect.Top >= ContentRect.Bottom then Break;
          P.DrawText(LineRect, Lines[i], S.FontName, fontSize, S.FontWeight,
            S.TextColor, FAlignment, tlCenter, False);
        end;
      finally
        Lines.Free;
        Meas.Free;
      end;
    end
    else
      { Multi-line even with WordWrap off: MeasureCaption has ALWAYS counted the author's
        line breaks as lines (so an AutoSize label is already sized for them), but the draw
        forced SingleLine and ran them together. Passing the line breaks through is what
        makes the drawn label match the box it was measured into. }
      P.DrawText(ContentRect, dispCap, S.FontName, fontSize, S.FontWeight,
        S.TextColor, FAlignment, FLayout, False, TyAccelGatePos(mp), False,
        True, TyLineHeight(ActiveController));
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyLabel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
