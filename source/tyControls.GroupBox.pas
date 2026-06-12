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
    procedure SetCaption(const AValue: string);
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
        MeasBmp.Canvas.Font.Name := S.FontName;
        MeasBmp.Canvas.Font.Size := MulDiv(S.FontSize, APPI, 96);
        TextW := MeasBmp.Canvas.TextWidth(FCaption);
      finally
        MeasBmp.Free;
      end;
      if TextW < 1 then TextW := 1;

      // Fill a background-colored band behind the text to hide the border line.
      // Band: Scale(8) left margin, text width, Scale(8) right margin.
      BandRect := Rect(P.Scale(8), 0, P.Scale(8) + TextW + P.Scale(8), CapH);
      BandFill := S.Background;
      // If no background set, use a solid black fill as fallback
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
