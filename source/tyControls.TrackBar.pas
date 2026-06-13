unit tyControls.TrackBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyTrackBar = class(TTyCustomControl)
  private
    FMin, FMax, FPosition: Integer;
    FOnChange: TNotifyEvent;
    FDragging: Boolean;
    FThumbHover: Boolean;
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    function ThumbWAtPPI(APPI: Integer): Integer;
    function TravelAtPPI(APPI: Integer): Integer;
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
    procedure DragTo(AXAlongTrack: Integer);
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
    property OnClick;
  end;

implementation

{ TTyTrackBar }

constructor TTyTrackBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMin := 0;
  FMax := 100;
  FPosition := 0;
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

function TTyTrackBar.TravelAtPPI(APPI: Integer): Integer;
begin
  Result := ClientWidth - ThumbWAtPPI(APPI);
  if Result < 0 then Result := 0;
end;

function TTyTrackBar.ThumbRect: TRect;
var
  TW, Tr, ThumbLeft: Integer;
  PPI: Integer;
begin
  PPI := Font.PixelsPerInch;
  TW := ThumbWAtPPI(PPI);
  Tr := TravelAtPPI(PPI);
  if (FMax <= FMin) or (Tr <= 0) then
    ThumbLeft := 0
  else
    ThumbLeft := (Tr * (FPosition - FMin) + (FMax - FMin) div 2) div (FMax - FMin);
  Result := Rect(ThumbLeft, 0, ThumbLeft + TW, ClientHeight);
end;

procedure TTyTrackBar.DragTo(AXAlongTrack: Integer);
var
  TW, Tr, NewLeft, NewPos: Integer;
  PPI: Integer;
begin
  PPI := Font.PixelsPerInch;
  TW := ThumbWAtPPI(PPI);
  Tr := TravelAtPPI(PPI);
  NewLeft := AXAlongTrack - TW div 2;
  if NewLeft < 0 then NewLeft := 0;
  if NewLeft > Tr then NewLeft := Tr;
  if Tr <= 0 then
    NewPos := FMin
  else
    NewPos := FMin + (NewLeft * (FMax - FMin) + Tr div 2) div Tr;
  Position := NewPos;
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

procedure TTyTrackBar.KeyDown(var Key: Word; Shift: TShiftState);
begin
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
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    DragTo(X);
    Invalidate;
  end;
end;

procedure TTyTrackBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  HoverRect: TRect;
  WasHover: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    DragTo(X);
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
  TW, Tr, ThumbLeft: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);

    // Compute thumb geometry using APPI for pixel-exact rendering
    TW := MulDiv(12, APPI, 96);
    if TW < 1 then TW := 1;
    Tr := (R.Right - R.Left) - TW;
    if Tr < 0 then Tr := 0;
    if (FMax <= FMin) or (Tr <= 0) then
      ThumbLeft := 0
    else
      ThumbLeft := (Tr * (FPosition - FMin) + (FMax - FMin) div 2) div (FMax - FMin);
    ThumbR := Rect(R.Left + ThumbLeft, R.Top, R.Left + ThumbLeft + TW, R.Bottom);

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
