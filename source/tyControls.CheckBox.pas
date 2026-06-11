unit tyControls.CheckBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyCheckBox = class(TTyCustomControl)
  private
    FChecked: Boolean;
    procedure SetChecked(const AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
  public
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
    procedure SetChecked(const AValue: Boolean);
    procedure UncheckSiblings;
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
  public
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
implementation

{ TTyCheckBox }

function TTyCheckBox.GetStyleTypeKey: string;
begin
  Result := 'TyCheckBox';
end;

procedure TTyCheckBox.SetChecked(const AValue: Boolean);
begin
  if FChecked = AValue then Exit;
  FChecked := AValue;
  Invalidate;
end;

procedure TTyCheckBox.Click;
begin
  SetChecked(not FChecked);
  inherited Click;
end;

procedure TTyCheckBox.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, ContentRect, BoxRect, TextRect: TRect;
  BoxSize, Gap: Integer;
begin
  P := TTyPainter.Create;
  try
    R := ClientRect;
    P.BeginPaint(Canvas, R, Font.PixelsPerInch);
    S := CurrentStyle;
    ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
    BoxSize := P.Scale(16);
    Gap := P.Scale(6);
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
    P.DrawText(TextRect, Caption, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taLeftJustify, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

{ TTyRadioButton }

function TTyRadioButton.GetStyleTypeKey: string;
begin
  Result := 'TyRadioButton';
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
    if (Sib <> Self) and (Sib is TTyRadioButton) then
      TTyRadioButton(Sib).SetChecked(False);
  end;
end;

procedure TTyRadioButton.Click;
begin
  SetChecked(True);
  inherited Click;
end;

procedure TTyRadioButton.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, ContentRect, DotRect, TextRect: TRect;
  BoxSize, Gap: Integer;
begin
  P := TTyPainter.Create;
  try
    R := ClientRect;
    P.BeginPaint(Canvas, R, Font.PixelsPerInch);
    S := CurrentStyle;
    ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
    BoxSize := P.Scale(16);
    Gap := P.Scale(6);
    DotRect := Rect(ContentRect.Left,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2),
      ContentRect.Left + BoxSize,
      ContentRect.Top + ((ContentRect.Bottom - ContentRect.Top - BoxSize) div 2) + BoxSize);
    P.FillBackground(DotRect, S.Background, BoxSize div 2);
    P.StrokeBorder(DotRect, BoxSize div 2, S.BorderWidth, S.BorderColor);
    if FChecked then
      P.DrawGlyph(DotRect, tgRadioDot, S.TextColor, 2);
    TextRect := Rect(DotRect.Right + Gap, ContentRect.Top,
      ContentRect.Right, ContentRect.Bottom);
    P.DrawText(TextRect, Caption, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taLeftJustify, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
