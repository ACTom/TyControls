unit tyControls.Edit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyEdit = class(TTyCustomControl)
  private
    FText: string;
    procedure SetText(const AValue: string);
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure InjectKey(const AChar: TUTF8Char);
    procedure InjectBackspace;
  published
    property Text: string read FText write SetText;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;
implementation

constructor TTyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FText := '';
end;

function TTyEdit.GetStyleTypeKey: string;
begin
  Result := 'TyEdit';
end;

procedure TTyEdit.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  Invalidate;
end;

procedure TTyEdit.InjectKey(const AChar: TUTF8Char);
begin
  if (AChar <> '') and (AChar[1] >= #32) then
  begin
    FText := FText + AChar;
    Invalidate;
  end;
end;

procedure TTyEdit.InjectBackspace;
begin
  if FText <> '' then
  begin
    System.Delete(FText, Length(FText), 1);
    Invalidate;
  end;
end;

procedure TTyEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  inherited UTF8KeyPress(UTF8Key);
  InjectKey(UTF8Key);
end;

procedure TTyEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if Key = VK_BACK then
  begin
    InjectBackspace;
    Key := 0;
  end;
end;

procedure TTyEdit.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, ContentRect, CaretRect: TRect;
  PadL: Integer;
begin
  P := TTyPainter.Create;
  try
    R := ClientRect;
    P.BeginPaint(Canvas, R, Font.PixelsPerInch);
    S := CurrentStyle;
    ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
    DrawFrame(P, ContentRect, S);
    PadL := P.Scale(S.Padding.Left);
    P.DrawText(Rect(ContentRect.Left + PadL, ContentRect.Top,
      ContentRect.Right, ContentRect.Bottom), FText, S.FontName, S.FontSize,
      S.FontWeight, S.TextColor, taLeftJustify, tlCenter, True);
    if Focused then
    begin
      CaretRect := Rect(ContentRect.Left + PadL, ContentRect.Top + P.Scale(4),
        ContentRect.Left + PadL + P.Scale(1), ContentRect.Bottom - P.Scale(4));
      P.FillBackground(CaretRect, Default(TTyFill), 0);
      P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
