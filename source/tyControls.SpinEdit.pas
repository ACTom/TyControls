unit tyControls.SpinEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTySpinEdit = class(TTyCustomControl)
  private
    FMinValue, FMaxValue, FValue, FIncrement: Integer;
    FOnChange: TNotifyEvent;
    procedure SetMinValue(const AValue: Integer);
    procedure SetMaxValue(const AValue: Integer);
    procedure SetValue(const AValue: Integer);
    procedure SetIncrement(const AValue: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property MinValue: Integer read FMinValue write SetMinValue default 0;
    property MaxValue: Integer read FMaxValue write SetMaxValue default 100;
    property Value: Integer read FValue write SetValue default 0;
    property Increment: Integer read FIncrement write SetIncrement default 1;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
    property OnClick;
  end;

function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer): TRect;
function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer): TRect;

implementation

function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer): TRect;
var
  BtnW, X0, HalfY: Integer;
begin
  BtnW := MulDiv(18, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0 := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, ALocal.Top, ALocal.Right, HalfY);
end;

function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer): TRect;
var
  BtnW, X0, HalfY: Integer;
begin
  BtnW := MulDiv(18, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0 := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, HalfY, ALocal.Right, ALocal.Bottom);
end;

{ TTySpinEdit }

constructor TTySpinEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMinValue := 0;
  FMaxValue := 100;
  FValue := 0;
  FIncrement := 1;
  Width := 120;
  Height := 28;
end;

function TTySpinEdit.GetStyleTypeKey: string;
begin
  Result := 'TySpinEdit';
end;

procedure TTySpinEdit.SetValue(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMinValue then Clamped := FMinValue;
  if Clamped > FMaxValue then Clamped := FMaxValue;
  if FValue = Clamped then Exit;
  FValue := Clamped;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTySpinEdit.SetMinValue(const AValue: Integer);
begin
  if FMinValue = AValue then Exit;
  FMinValue := AValue;
  if FValue < FMinValue then FValue := FMinValue;
  Invalidate;
end;

procedure TTySpinEdit.SetMaxValue(const AValue: Integer);
begin
  if FMaxValue = AValue then Exit;
  FMaxValue := AValue;
  if FValue > FMaxValue then FValue := FMaxValue;
  Invalidate;
end;

procedure TTySpinEdit.SetIncrement(const AValue: Integer);
begin
  if FIncrement = AValue then Exit;
  if AValue < 1 then
    FIncrement := 1
  else
    FIncrement := AValue;
  Invalidate;
end;

procedure TTySpinEdit.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextR, UpR, DownR: TRect;
  BtnW: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    UpR := TySpinUpButtonRect(R, APPI);
    DownR := TySpinDownButtonRect(R, APPI);
    BtnW := P.Scale(18);
    TextR := Rect(R.Left + P.Scale(S.Padding.Left), R.Top + P.Scale(S.Padding.Top),
      R.Right - BtnW, R.Bottom - P.Scale(S.Padding.Bottom));
    P.DrawText(TextR, IntToStr(FValue), S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taLeftJustify, tlCenter, True);
    P.DrawGlyph(UpR, tgArrowUp, S.TextColor, 2);
    P.DrawGlyph(DownR, tgArrowDown, S.TextColor, 2);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTySpinEdit.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
