unit tyControls.GroupBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyGroupBox = class(TTyCustomControl)
  private
    FCaption: string;
    FAlignment: TAlignment;
    procedure SetCaption(const AValue: string);
    procedure SetAlignment(AValue: TAlignment);
    { Shared caption-band height: 16 logical px scaled to APPI.
      Used by both RenderTo and AdjustClientRect so they stay in sync. }
    function CapHAtPPI(APPI: Integer): Integer;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyGroupBox }

function TTyGroupBox.CapHAtPPI(APPI: Integer): Integer;
begin
  Result := MulDiv(16, APPI, 96);
  if Result < 1 then Result := 1;
end;

procedure TTyGroupBox.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Top, CapHAtPPI(Font.PixelsPerInch));
end;

constructor TTyGroupBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaption := '';
  FAlignment := taLeftJustify;
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

procedure TTyGroupBox.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;

procedure TTyGroupBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, CapH: Integer;
  FrameRect, BandRect, TextRect: TRect;
  TextW, BandLeft: Integer;
  MeasBmp: TBitmap;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;

    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;

    // Caption band height: 16 logical pixels (matches AdjustClientRect inset)
    CapH := CapHAtPPI(APPI);
    if CapH < 1 then CapH := 1;

    // Draw the frame rect inset from caption mid-line
    FrameRect := Rect(0, CapH div 2, W, H);
    DrawFrame(P, FrameRect, S);

    // Draw caption text with a background band behind it
    if FCaption <> '' then
    begin
      // Measure actual text width using a scratch bitmap canvas so CJK and
      // variable-width fonts are handled correctly (avoids byte-Length * 8).
      MeasBmp := TBitmap.Create;
      try
        MeasBmp.SetSize(1, 1);
        MeasBmp.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
        // Measure with the same effective size the caption is drawn at, so the
        // erased band matches the now-readable text (ResolveFontSize fallback).
        MeasBmp.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
        TextW := MeasBmp.Canvas.TextWidth(FCaption);
      finally
        MeasBmp.Free;
      end;
      if TextW < 1 then TextW := 1;

      // Position the erase band AND the text from the SAME BandLeft per
      // Alignment, so the erased gap stays centered on the caption ink.
      case FAlignment of
        taCenter:      BandLeft := (W - (TextW + P.Scale(16))) div 2;
        taRightJustify:BandLeft := W - (TextW + P.Scale(16)) - P.Scale(4);
      else             BandLeft := P.Scale(4);   // taLeftJustify (current look: band starts ~Scale(8))
      end;
      if BandLeft < 0 then BandLeft := 0;

      // Erase the band pixels so the parent background shows through with no
      // border segment. Band: Scale(8) margin + text width + Scale(8) margin.
      BandRect := Rect(BandLeft, 0, BandLeft + TextW + P.Scale(16), CapH);
      P.EraseRect(BandRect);

      // Draw caption text within the band, aligned per FAlignment.
      TextRect := Rect(BandLeft + P.Scale(4), 0, BandLeft + P.Scale(4) + TextW + P.Scale(8), CapH);
      P.DrawText(TextRect, FCaption, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, FAlignment, tlCenter, True);
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
