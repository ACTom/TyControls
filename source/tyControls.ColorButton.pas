unit tyControls.ColorButton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Button, tyControls.Dialogs.Color;

// Pure helper: '#RRGGBB' (upper-case, alpha ignored). Unit-tested.
function TyColorHex(AColor: TTyColor): string;

type
  { TTyColorButton — a TTyButton that shows a colour swatch. Clicking opens the
    themed TySelectColor dialog and updates the swatch on OK. GetStyleTypeKey stays
    'TyButton' (inherited), so it reuses the button theme token — no new .tycss. }
  TTyColorButton = class(TTyButton)
  private
    FSelectedColor: TTyColor;
    FShowText: Boolean;
    FDialogCaption: string;
    FOnColorChange: TNotifyEvent;
    procedure SetSelectedColor(AValue: TTyColor);
    procedure SetShowText(AValue: Boolean);
  protected
    // Draw the swatch (rounded, filled with SelectedColor, subtle border) inset on
    // the left of AContentRect; when ShowText, draw the '#RRGGBB' hex to its right.
    procedure DrawContent(APainter: TTyPainter; const AContentRect: TRect;
      const AStyle: TTyStyleSet); override;
  public
    constructor Create(AOwner: TComponent); override;
    // The button's click IS "open the colour dialog": pick a colour via TySelectColor,
    // and on an accepted change repaint + fire OnColorChange. inherited Click is still
    // called so OnClick fires too. (Guarded so headless tests never reach TySelectColor.)
    procedure Click; override;
  published
    // The current swatch colour. Setting it programmatically repaints but does NOT
    // fire OnColorChange (that event is reserved for dialog-driven changes).
    property SelectedColor: TTyColor read FSelectedColor write SetSelectedColor default $FF3B82F6;
    // When True, the '#RRGGBB' hex is drawn as the caption to the right of the swatch;
    // when False the swatch fills most of the content area.
    property ShowText: Boolean read FShowText write SetShowText default False;
    // Title bar text of the colour dialog opened on click.
    property DialogCaption: string read FDialogCaption write FDialogCaption;
    // Fired only when the dialog is accepted AND the colour actually changed.
    property OnColorChange: TNotifyEvent read FOnColorChange write FOnColorChange;
  end;

implementation

function TyColorHex(AColor: TTyColor): string;
begin
  // RGB only (alpha ignored), upper-case — e.g. TyRGB(59,130,246) -> '#3B82F6'.
  Result := Format('#%.2X%.2X%.2X', [TyRedOf(AColor), TyGreenOf(AColor), TyBlueOf(AColor)]);
end;

{ Build a solid TTyFill. A standalone function (NOT a method) so Default(TTyFill)
  resolves to the compiler intrinsic — inside a TTyButton descendant's method the
  inherited published 'Default' property would shadow it. }
function SolidFill(AColor: TTyColor): TTyFill;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkSolid;
  Result.Color := AColor;
end;

constructor TTyColorButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelectedColor := TyRGB(59, 130, 246);   // $FF3B82F6 — the library accent blue
  FShowText := False;
  FDialogCaption := 'Select Color';
end;

procedure TTyColorButton.SetSelectedColor(AValue: TTyColor);
begin
  if FSelectedColor = AValue then Exit;
  FSelectedColor := AValue;
  Invalidate;   // programmatic set: repaint only, no OnColorChange (dialog-driven only)
end;

procedure TTyColorButton.SetShowText(AValue: Boolean);
begin
  if FShowText = AValue then Exit;
  FShowText := AValue;
  Invalidate;
end;

procedure TTyColorButton.DrawContent(APainter: TTyPainter; const AContentRect: TRect;
  const AStyle: TTyStyleSet);
var
  swatch, capRect: TRect;
  fill: TTyFill;
  cw, gap, radius: Integer;
  borderCol: TTyColor;
begin
  // Degenerate rect (headless zero-size render) — nothing to draw, stay crash-safe.
  if (AContentRect.Right <= AContentRect.Left) or (AContentRect.Bottom <= AContentRect.Top) then
    Exit;
  gap := APainter.Scale(6);
  if FShowText then
    // Fixed square swatch on the left, its side = content height (a small min floor).
    cw := AContentRect.Bottom - AContentRect.Top
  else
    // No text: the swatch fills the whole content area.
    cw := AContentRect.Right - AContentRect.Left;
  if cw < APainter.Scale(8) then cw := APainter.Scale(8);
  if cw > (AContentRect.Right - AContentRect.Left) then
    cw := AContentRect.Right - AContentRect.Left;
  swatch := Rect(AContentRect.Left, AContentRect.Top, AContentRect.Left + cw, AContentRect.Bottom);

  // Subtle border: prefer the resolved style's border colour; else a fixed low-contrast grey.
  if tpBorderColor in AStyle.Present then
    borderCol := AStyle.BorderColor
  else
    borderCol := TyRGBA(0, 0, 0, 40);

  // Rounded swatch, filled with the selected colour.
  fill := SolidFill(FSelectedColor);
  radius := 3;   // logical px; FillBackground/StrokeBorder scale it
  APainter.FillBackground(swatch, fill, TyUniformCorners(radius));
  APainter.StrokeBorder(swatch, TyUniformCorners(radius), 1, borderCol);

  // Optional hex caption to the right of the swatch.
  if FShowText then
  begin
    capRect := Rect(swatch.Right + gap, AContentRect.Top, AContentRect.Right, AContentRect.Bottom);
    if capRect.Right > capRect.Left then
      APainter.DrawText(capRect, TyColorHex(FSelectedColor), AStyle.FontName,
        AStyle.FontSize, AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True);
  end;
end;

procedure TTyColorButton.Click;
var
  newColor: TTyColor;
  didChange: Boolean;
begin
  if not Enabled then Exit;
  newColor := FSelectedColor;
  // TySelectColor updates newColor in place; True iff the user accepted (OK).
  if TySelectColor(FDialogCaption, newColor) then
  begin
    didChange := newColor <> FSelectedColor;
    FSelectedColor := newColor;
    if didChange then
    begin
      Invalidate;
      if Assigned(FOnColorChange) then FOnColorChange(Self);
    end;
  end;
  inherited Click;   // fire OnClick too (and honour any ModalResult, per TTyButton)
end;

end.
