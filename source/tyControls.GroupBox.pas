unit tyControls.GroupBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Accel;
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
    function DialogChar(var Message: TLMKey): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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
var
  S: TTyStyleSet;
  ppi: Integer;
begin
  inherited AdjustClientRect(ARect);
  ppi := Font.PixelsPerInch;
  S := CurrentStyle;
  // Reserve the caption band (Top) AND the themed content padding on every side, so children
  // never paint over the frame's left/right/bottom border. Padding is theme-token-driven
  // (TyGroupBox) — matching how TTyPanel insets its content.
  // Top: the caption band ONLY (it already separates content from the caption; adding padding.Top
  // would double-space). Left/Right/Bottom: the themed padding, so children clear the frame border.
  Inc(ARect.Left,   MulDiv(S.Padding.Left, ppi, 96));
  Inc(ARect.Top,    CapHAtPPI(ppi));
  Dec(ARect.Right,  MulDiv(S.Padding.Right, ppi, 96));
  Dec(ARect.Bottom, MulDiv(S.Padding.Bottom, ppi, 96));
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
  if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
end;

constructor TTyGroupBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  // Designer container: the IDE drops child controls INTO the box; they lay out below
  // the caption band carved by AdjustClientRect.
  ControlStyle := ControlStyle + [csAcceptsControls];
  FCaption := '';
  FAlignment := taLeftJustify;
  Width := 185;
  Height := 105;
end;

destructor TTyGroupBox.Destroy;
begin
  TyAccelUnregister(Self);
  inherited Destroy;
end;

function TTyGroupBox.DialogChar(var Message: TLMKey): Boolean;
var pf: TCustomForm;
begin
  if Enabled and TyIsAccelKey(Message, FCaption) then
  begin
    pf := GetParentForm(Self);
    if pf <> nil then pf.SelectNext(Self, True, True);   // focus the first child after the group box
    Exit(True);
  end;
  Result := inherited DialogChar(Message);
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
  disp: string;
  mp: Integer;
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

    // The caption band strip sits ABOVE the frame, so DrawFrame never paints it.
    // On an image theme fill it with the form's photo; off-image fill it with the
    // OPAQUE resolved parent background so it is not a transparent gap (which the
    // Win10 DWM glass would show as white on deactivate).
    if not FillSharpBackdrop(P, Rect(0, 0, W, CapH div 2)) then
      TyFillParentBg(Self, P, Rect(0, 0, W, CapH div 2), S);

    // Draw caption text with a background band behind it
    if FCaption <> '' then
    begin
      TyParseMnemonic(FCaption, disp, mp);
      // Measure actual text width using a scratch bitmap canvas so CJK and
      // variable-width fonts are handled correctly (avoids byte-Length * 8).
      MeasBmp := TBitmap.Create;
      try
        MeasBmp.SetSize(1, 1);
        MeasBmp.Canvas.Font.Name := TyEffectiveFontName(S.FontName);
        // Measure with the same effective size the caption is drawn at, so the
        // erased band matches the now-readable text (ResolveFontSize fallback).
        MeasBmp.Canvas.Font.Size := MulDiv(ResolveFontSize(S), APPI, 96);
        TextW := MeasBmp.Canvas.TextWidth(disp);
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

      // Break the top border behind the caption. On an image theme show the
      // form's photo through the gap; otherwise fill the OPAQUE resolved parent
      // background (not a transparent erase — the Win10 DWM glass shows an erased
      // gap as white on deactivate).
      BandRect := Rect(BandLeft, 0, BandLeft + TextW + P.Scale(16), CapH);
      if not FillSharpBackdrop(P, BandRect) then
        TyFillParentBg(Self, P, BandRect, S);

      // Draw caption text within the band, aligned per FAlignment.
      TextRect := Rect(BandLeft + P.Scale(4), 0, BandLeft + P.Scale(4) + TextW + P.Scale(8), CapH);
      P.DrawText(TextRect, disp, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, FAlignment, tlCenter, True, TyAccelGatePos(mp));
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
