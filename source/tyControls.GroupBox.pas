unit tyControls.GroupBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyGroupBox = class(TTyCustomControl)
  private
    FCaption: string;
    procedure SetCaption(const AValue: string);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyGroupBox }

constructor TTyGroupBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaption := '';
  Width := 185;
  Height := 105;
end;

function TTyGroupBox.GetStyleTypeKey: string;
begin
  Result := 'TyGroupBox';
end;

procedure TTyGroupBox.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Invalidate;
end;

procedure TTyGroupBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, CapH: Integer;
  FrameRect, BandRect, TextRect: TRect;
  BandFill: TTyFill;
  TextW: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;

    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;

    // Caption band height: Scale(16) logical pixels
    CapH := P.Scale(16);
    if CapH < 1 then CapH := 1;

    // Draw the frame rect inset from caption mid-line
    FrameRect := Rect(0, CapH div 2, W, H);
    DrawFrame(P, FrameRect, S);

    // Draw caption text with a background band behind it
    if FCaption <> '' then
    begin
      // Estimate text width: Scale(FontSize) * char_count roughly, or use a simple formula.
      // Simple conservative approximation: char_count * Scale(S.FontSize * 0.6 + 2)
      // For simplicity, we paint the full caption area and let text clip itself.
      // Band x-start at Scale(8), text at Scale(12).
      TextW := Length(FCaption) * P.Scale(8);
      if TextW < P.Scale(8) then TextW := P.Scale(8);

      // Fill a background-colored band behind the text to hide the border line
      BandRect := Rect(P.Scale(8), 0, P.Scale(8) + TextW + P.Scale(8), CapH);
      BandFill := S.Background;
      // If no background set, use a solid transparent fill to avoid painting garbage
      if not (tpBackground in S.Present) then
      begin
        BandFill := Default(TTyFill);
        BandFill.Kind := tfkSolid;
        BandFill.Color := $FF000000; // opaque black fallback; themes should set background
      end;
      P.FillBackground(BandRect, BandFill, 0);

      // Draw caption text
      TextRect := Rect(P.Scale(12), 0, W - P.Scale(4), CapH);
      P.DrawText(TextRect, FCaption, S.FontName, S.FontSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlCenter, True);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyGroupBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
