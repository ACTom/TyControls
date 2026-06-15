unit tyControls.TrackBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyTrackOrientation = (toHorizontal, toVertical);

  TTyTrackBar = class(TTyCustomControl)
  private
    FMin, FMax, FPosition: Integer;
    FOrientation: TTyTrackOrientation;
    FFrequency: Integer;
    FOnChange: TNotifyEvent;
    FDragging: Boolean;
    FThumbHover: Boolean;
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetOrientation(const AValue: TTyTrackOrientation);
    procedure SetFrequency(const AValue: Integer);
    function ThumbWAtPPI(APPI: Integer): Integer;
    function MainLen: Integer;
    function Inverted: Boolean;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    function ThumbRect: TRect;
    procedure DragTo(APos: Integer);
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property Orientation: TTyTrackOrientation read FOrientation write SetOrientation default toHorizontal;
    property Frequency: Integer read FFrequency write SetFrequency default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
    property OnClick;
  end;

function TyTrackThumbOffset(AMainLen, AThumbLen, AMin, AMax, APos: Integer; AInvert: Boolean): Integer;
function TyTrackPosFromOffset(AMainLen, AThumbLen, AMin, AMax, AOffset: Integer; AInvert: Boolean): Integer;

implementation

function TyTrackThumbOffset(AMainLen, AThumbLen, AMin, AMax, APos: Integer; AInvert: Boolean): Integer;
var travel, span, eff: Integer;
begin
  travel := AMainLen - AThumbLen;
  span := AMax - AMin;
  if (travel <= 0) or (span <= 0) then Exit(0);
  if APos < AMin then APos := AMin;
  if APos > AMax then APos := AMax;
  if AInvert then eff := AMax - APos else eff := APos - AMin;   // distance from the "0-offset" end
  Result := (travel * eff + span div 2) div span;
end;

function TyTrackPosFromOffset(AMainLen, AThumbLen, AMin, AMax, AOffset: Integer; AInvert: Boolean): Integer;
var travel, span, eff: Integer;
begin
  travel := AMainLen - AThumbLen;
  span := AMax - AMin;
  if (travel <= 0) or (span <= 0) then Exit(AMin);
  if AOffset < 0 then AOffset := 0;
  if AOffset > travel then AOffset := travel;
  eff := (AOffset * span + travel div 2) div travel;
  if AInvert then Result := AMax - eff else Result := AMin + eff;
end;

{ TTyTrackBar }

constructor TTyTrackBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FOrientation := toHorizontal;
  FFrequency := 0;
  FDragging := False;
  FThumbHover := False;
  Width := 160;
  Height := 24;
end;

function TTyTrackBar.GetStyleTypeKey: string;
begin
  Result := 'TyTrackBar';
end;

function TTyTrackBar.ThumbWAtPPI(APPI: Integer): Integer;
begin
  Result := MulDiv(12, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyTrackBar.MainLen: Integer;
begin
  if FOrientation = toVertical then Result := ClientHeight
  else Result := ClientWidth;
end;

function TTyTrackBar.Inverted: Boolean;
begin
  Result := (FOrientation = toVertical);
end;

function TTyTrackBar.ThumbRect: TRect;
var
  TW, Off: Integer;
  PPI: Integer;
begin
  PPI := Font.PixelsPerInch;
  TW := ThumbWAtPPI(PPI);
  Off := TyTrackThumbOffset(MainLen, TW, FMin, FMax, FPosition, Inverted);
  if FOrientation = toVertical then
    Result := Rect(0, Off, ClientWidth, Off + TW)
  else
    Result := Rect(Off, 0, Off + TW, ClientHeight);
end;

procedure TTyTrackBar.DragTo(APos: Integer);
var
  TW, Off: Integer;
  PPI: Integer;
begin
  PPI := Font.PixelsPerInch;
  TW := ThumbWAtPPI(PPI);
  Off := APos - TW div 2;
  Position := TyTrackPosFromOffset(MainLen, TW, FMin, FMax, Off, Inverted);
end;

procedure TTyTrackBar.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  Invalidate;
end;

procedure TTyTrackBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
end;

procedure TTyTrackBar.SetPosition(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  if FPosition = Clamped then Exit;
  FPosition := Clamped;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTrackBar.SetOrientation(const AValue: TTyTrackOrientation);
begin
  if FOrientation = AValue then Exit;
  FOrientation := AValue;
  Invalidate;
end;

procedure TTyTrackBar.SetFrequency(const AValue: Integer);
begin
  if AValue < 0 then
    FFrequency := 0
  else
    FFrequency := AValue;
  Invalidate;
end;

procedure TTyTrackBar.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  case Key of
    VK_LEFT:
      begin
        Position := FPosition - 1;
        Key := 0;
      end;
    VK_RIGHT:
      begin
        Position := FPosition + 1;
        Key := 0;
      end;
  end;
end;

procedure TTyTrackBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    if FOrientation = toVertical then DragTo(Y) else DragTo(X);
    Invalidate;
  end;
end;

procedure TTyTrackBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  HoverRect: TRect;
  WasHover: Boolean;
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    if FOrientation = toVertical then DragTo(Y) else DragTo(X);
    Invalidate;
  end
  else
  begin
    HoverRect := ThumbRect;
    WasHover := FThumbHover;
    FThumbHover := (X >= HoverRect.Left) and (X < HoverRect.Right)
               and (Y >= HoverRect.Top) and (Y < HoverRect.Bottom);
    if FThumbHover <> WasHover then
      Invalidate;
  end;
end;

procedure TTyTrackBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := False;
    Invalidate;
  end;
end;

procedure TTyTrackBar.MouseLeave;
begin
  inherited MouseLeave;
  FThumbHover := False;
  // FDragging is NOT cleared here: drag ends on MouseUp only, so dragging
  // outside the control bounds and back stays consistent.
  Invalidate;
end;

procedure TTyTrackBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, ThumbS: TTyStyleSet;
  R, ThumbR: TRect;
  ThumbStates: TTyStateSet;
  TW, MLen, Off: Integer;
  TickFill: TTyFill;
  TickLen, TickW, V, TickOff, C: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);

    // Compute thumb geometry using APPI for pixel-exact rendering.
    // Horizontal goes through the non-inverted branch of TyTrackThumbOffset,
    // which equals the legacy formula exactly (pixel regression).
    TW := MulDiv(12, APPI, 96);
    if TW < 1 then TW := 1;
    if FOrientation = toVertical then
      MLen := R.Bottom - R.Top
    else
      MLen := R.Right - R.Left;
    Off := TyTrackThumbOffset(MLen, TW, FMin, FMax, FPosition, Inverted);
    if FOrientation = toVertical then
      ThumbR := Rect(R.Left, R.Top + Off, R.Right, R.Top + Off + TW)
    else
      ThumbR := Rect(R.Left + Off, R.Top, R.Left + Off + TW, R.Bottom);

    // Resolve thumb style with hover/drag states
    ThumbStates := [];
    if FDragging then
      Include(ThumbStates, tysActive)
    else if FThumbHover then
      Include(ThumbStates, tysHover)
    else
      Include(ThumbStates, tysNormal);
    ThumbS := ActiveController.Model.ResolveStyle('TyTrackThumb', '', ThumbStates);

    if (tpBackground in ThumbS.Present) then
      P.FillBackground(ThumbR, ThumbS.Background, ThumbS.BorderRadius);

    // Tick marks: one every FFrequency value-units, lined up with where the
    // thumb centre would sit at value v. Theme-driven color (S.TextColor).
    if (FFrequency > 0) and (FMax > FMin) then
    begin
      TickLen := P.Scale(4);
      TickW := P.Scale(1);
      if TickW < 1 then TickW := 1;
      TickFill := Default(TTyFill);
      TickFill.Kind := tfkSolid;
      TickFill.Color := S.TextColor;
      V := FMin;
      while V <= FMax do
      begin
        TickOff := TyTrackThumbOffset(MLen, TW, FMin, FMax, V, Inverted);
        C := TickOff + TW div 2;
        if FOrientation = toVertical then
          P.FillBackground(Rect(R.Right - TickLen, R.Top + C,
            R.Right, R.Top + C + TickW), TickFill, 0)
        else
          P.FillBackground(Rect(R.Left + C, R.Bottom - TickLen,
            R.Left + C + TickW, R.Bottom), TickFill, 0);
        Inc(V, FFrequency);
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTrackBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
