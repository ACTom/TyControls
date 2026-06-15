unit tyControls.CheckBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;
type
  TTyCheckBox = class(TTyCustomControl)
  private
    FChecked: Boolean;
    procedure SetChecked(const AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;
    function CurrentStates: TTyStateSet; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Click; override;
  published
    property Checked: Boolean read FChecked write SetChecked default False;
    property Caption;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;

  TTyRadioButton = class(TTyCustomControl)
  private
    FChecked: Boolean;
    FGroupIndex: Integer;
    procedure SetChecked(const AValue: Boolean);
    procedure UncheckSiblings;
  protected
    function GetStyleTypeKey: string; override;
    function CurrentStates: TTyStateSet; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Click; override;
  published
    property Checked: Boolean read FChecked write SetChecked default False;
    property GroupIndex: Integer read FGroupIndex write FGroupIndex default 0;
    property Caption;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;
implementation

{ TTyCheckBox }

constructor TTyCheckBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
end;

function TTyCheckBox.GetStyleTypeKey: string;
begin
  Result := 'TyCheckBox';
end;

function TTyCheckBox.CurrentStates: TTyStateSet;
begin
  // A checked checkbox enters tysActive so the theme's :active rule (accent box
  // fill + white glyph) actually resolves. The :active 'color' would whiten the
  // CAPTION too, so RenderTo resolves the caption text from a separate
  // active-free state set — keeping the accent + white-glyph effect box-only.
  Result := inherited CurrentStates;
  if FChecked and Enabled then
    Include(Result, tysActive);
end;

procedure TTyCheckBox.SetChecked(const AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  Invalidate;
end;

procedure TTyCheckBox.Click;
begin
  if not Enabled then Exit;
  SetChecked(not FChecked);
  inherited Click;
end;

procedure TTyCheckBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if Key = VK_SPACE then
  begin
    Click;
    Key := 0;
  end;
end;

procedure TTyCheckBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, FrameS, CaptionS: TTyStyleSet;
  ContentRect, BoxRect, TextRect, FullRect: TRect;
  BoxSize, Gap: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    // S drives the BOX (and its glyph): when checked it carries tysActive so the
    // :active accent fill + white glyph resolve. CaptionS is resolved WITHOUT the
    // checked-derived tysActive so the :active 'color:#FFFFFF' never whitens the
    // caption text — keeping the accent + white-glyph effect box-only.
    S := CurrentStyle;
    CaptionS := ActiveController.Model.ResolveStyle(
      GetStyleTypeKey, StyleClass, CurrentStates - [tysActive]);
    // DrawFrame propagates opacity (and shadow) for the whole control, but the
    // theme's background/border style the small BOX, not the control rect —
    // so the frame copy clears them to keep the v1 transparent look.
    FrameS := S;
    FrameS.Background := Default(TTyFill);
    FrameS.BorderWidth := 0;
    // Use a (0,0)-local rect: the painter builds a (W x H) bitmap and blits it
    // at ARect.Left/Top, so a non-zero ARect origin would shift/clip the frame.
    FullRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, FullRect, FrameS);
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    // Inset content rect by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    BoxSize := P.Scale(TyCheckBoxBox);
    Gap := P.Scale(TyCheckBoxGap);
    BoxRect := Rect(ContentRect.Left,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2),
      ContentRect.Left + BoxSize,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2) + BoxSize);
    P.FillBackground(BoxRect, S.Background, S.BorderRadius);
    P.StrokeBorder(BoxRect, S.BorderRadius, S.BorderWidth, S.BorderColor);
    if FChecked then
      P.DrawGlyph(BoxRect, tgCheck, S.TextColor, 2);
    TextRect := Rect(BoxRect.Right + Gap, ContentRect.Top,
      ContentRect.Right, ContentRect.Bottom);
    P.DrawText(TextRect, Caption, S.FontName, ResolveFontSize(S), S.FontWeight,
      CaptionS.TextColor, taLeftJustify, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCheckBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ TTyRadioButton }

constructor TTyRadioButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
end;

function TTyRadioButton.GetStyleTypeKey: string;
begin
  Result := 'TyRadioButton';
end;

function TTyRadioButton.CurrentStates: TTyStateSet;
begin
  // See TTyCheckBox.CurrentStates: checked -> tysActive so :active accent fill +
  // white dot resolve; the caption text is resolved active-free in RenderTo so
  // the accent/white stays confined to the box (dot).
  Result := inherited CurrentStates;
  if FChecked and Enabled then
    Include(Result, tysActive);
end;

procedure TTyRadioButton.SetChecked(const AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  if FChecked then
    UncheckSiblings;
  Invalidate;
end;

procedure TTyRadioButton.UncheckSiblings;
var
  I: Integer;
  Sib: TControl;
begin
  if Parent = nil then Exit;
  for I := 0 to Parent.ControlCount - 1 do
  begin
    Sib := Parent.Controls[I];
    if (Sib <> Self) and (Sib is TTyRadioButton)
       and (TTyRadioButton(Sib).GroupIndex = FGroupIndex) then
      TTyRadioButton(Sib).SetChecked(False);
  end;
end;

procedure TTyRadioButton.Click;
begin
  if not Enabled then Exit;
  SetChecked(True);
  inherited Click;
end;

procedure TTyRadioButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if Key = VK_SPACE then
  begin
    Click;
    Key := 0;
  end;
end;

procedure TTyRadioButton.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, FrameS, CaptionS: TTyStyleSet;
  ContentRect, DotRect, TextRect, FullRect: TRect;
  BoxSize, Gap, DotRadiusLogical: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    // S drives the dot box (+ its glyph): checked -> tysActive -> :active accent
    // fill + white dot. CaptionS is resolved WITHOUT the checked-derived tysActive
    // so the caption text colour stays normal (box-only). See TTyCheckBox.RenderTo.
    S := CurrentStyle;
    CaptionS := ActiveController.Model.ResolveStyle(
      GetStyleTypeKey, StyleClass, CurrentStates - [tysActive]);
    // See TTyCheckBox.RenderTo: frame copy clears background/border so the
    // theme's box styling doesn't paint a control-wide fill or outline.
    FrameS := S;
    FrameS.Background := Default(TTyFill);
    FrameS.BorderWidth := 0;
    // Use a (0,0)-local rect (see TTyCheckBox.RenderTo) so a non-zero ARect
    // origin doesn't shift/clip the frame within the painter's local bitmap.
    FullRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, FullRect, FrameS);
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    // Inset content rect by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    BoxSize := P.Scale(TyCheckBoxBox);
    Gap := P.Scale(TyCheckBoxGap);
    DotRect := Rect(ContentRect.Left,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2),
      ContentRect.Left + BoxSize,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2) + BoxSize);
    // FillBackground/StrokeBorder take a LOGICAL radius (they Scale() internally),
    // so cap the token (S.BorderRadius, logical) against the dot's LOGICAL half-side.
    // The dot box is P.Scale(16) device wide → logical half = MulDiv(BoxSize,96,APPI) div 2,
    // which is 8 at 96ppi. Default TyRadioButton border-radius:8px → Min(8,8)=8 → circle
    // unchanged; only a SMALLER theme radius squares the corners.
    DotRadiusLogical := TyClampRadius(S.BorderRadius, MulDiv(BoxSize, 96, APPI) div 2);
    P.FillBackground(DotRect, S.Background, DotRadiusLogical);
    P.StrokeBorder(DotRect, DotRadiusLogical, S.BorderWidth, S.BorderColor);
    if FChecked then
      P.DrawGlyph(DotRect, tgRadioDot, S.TextColor, 2);
    TextRect := Rect(DotRect.Right + Gap, ContentRect.Top,
      ContentRect.Right, ContentRect.Bottom);
    P.DrawText(TextRect, Caption, S.FontName, ResolveFontSize(S), S.FontWeight,
      CaptionS.TextColor, taLeftJustify, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRadioButton.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
