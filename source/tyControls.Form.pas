unit tyControls.Form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller;

type
  TTyBorderHit = (bhNone, bhLeft, bhTop, bhRight, bhBottom,
                  bhTopLeft, bhTopRight, bhBottomLeft, bhBottomRight);

  TTyCaptionButtonKind = (cbkClose, cbkMin, cbkMax, cbkRestore);

  TTyCaptionButton = class(TTyCustomControl)
  private
    FKind: TTyCaptionButtonKind;
    procedure SetKind(AValue: TTyCaptionButtonKind);
  protected
    procedure Paint; override;
    procedure Click; override;
  public
    function GetStyleTypeKey: string; override;
    function KindVariant: string;
    function KindGlyph: TTyGlyphKind;
  published
    property Kind: TTyCaptionButtonKind read FKind write SetKind;
    property OnClick;
  end;

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
function TyMaximizedBounds(const AWorkArea: TRect): TRect;

implementation

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
var
  OnLeft, OnRight, OnTop, OnBottom: Boolean;
begin
  Result := bhNone;
  if AZone <= 0 then
    Exit;
  if (APt.X < AClient.Left) or (APt.X > AClient.Right) or
     (APt.Y < AClient.Top) or (APt.Y > AClient.Bottom) then
    Exit;
  OnLeft := APt.X < (AClient.Left + AZone);
  OnRight := APt.X > (AClient.Right - AZone);
  OnTop := APt.Y < (AClient.Top + AZone);
  OnBottom := APt.Y > (AClient.Bottom - AZone);
  if OnTop and OnLeft then
    Result := bhTopLeft
  else if OnTop and OnRight then
    Result := bhTopRight
  else if OnBottom and OnLeft then
    Result := bhBottomLeft
  else if OnBottom and OnRight then
    Result := bhBottomRight
  else if OnLeft then
    Result := bhLeft
  else if OnRight then
    Result := bhRight
  else if OnTop then
    Result := bhTop
  else if OnBottom then
    Result := bhBottom
  else
    Result := bhNone;
end;

function TyMaximizedBounds(const AWorkArea: TRect): TRect;
begin
  Result.Left := AWorkArea.Left;
  Result.Top := AWorkArea.Top;
  Result.Right := AWorkArea.Right;
  Result.Bottom := AWorkArea.Bottom;
end;

{ TTyCaptionButton }

procedure TTyCaptionButton.SetKind(AValue: TTyCaptionButtonKind);
begin
  if FKind = AValue then
    Exit;
  FKind := AValue;
  StyleClass := KindVariant;
  Invalidate;
end;

function TTyCaptionButton.GetStyleTypeKey: string;
begin
  Result := 'TyCaptionButton';
end;

function TTyCaptionButton.KindVariant: string;
begin
  case FKind of
    cbkClose: Result := 'close';
    cbkMin: Result := 'min';
    cbkMax: Result := 'max';
    cbkRestore: Result := 'restore';
  else
    Result := 'close';
  end;
end;

function TTyCaptionButton.KindGlyph: TTyGlyphKind;
begin
  case FKind of
    cbkClose: Result := tgClose;
    cbkMin: Result := tgMinimize;
    cbkMax: Result := tgMaximize;
    cbkRestore: Result := tgRestore;
  else
    Result := tgClose;
  end;
end;

procedure TTyCaptionButton.Click;
begin
  inherited Click;
end;

procedure TTyCaptionButton.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  GlyphRect: TRect;
  GlyphSize: Integer;
  CX, CY: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    S := CurrentStyle;
    DrawFrame(P, ClientRect, S);
    GlyphSize := P.Scale(10);
    CX := (ClientWidth - GlyphSize) div 2;
    CY := (ClientHeight - GlyphSize) div 2;
    GlyphRect := Rect(CX, CY, CX + GlyphSize, CY + GlyphSize);
    P.DrawGlyph(GlyphRect, KindGlyph, S.TextColor, P.Scale(1));
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
