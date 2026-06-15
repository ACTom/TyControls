unit tyControls.ScrollBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyScrollBarKind = (sbHorizontal, sbVertical);

  TTyScrollBar = class(TTyCustomControl)
  private
    FKind: TTyScrollBarKind;
    FMin, FMax, FPosition, FPageSize: Integer;
    FSmallChange: Integer;
    FOnChange: TNotifyEvent;
    FDragging: Boolean;
    FDragGrabOffset: Integer;
    FDragStartTop: Integer;
    function TrackRect: TRect;
    function TrackLength: Integer;
    function PosAlong(X, Y: Integer): Integer;
    procedure SetKind(const AValue: TTyScrollBarKind);
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetPageSize(const AValue: Integer);
    procedure SetSmallChange(const AValue: Integer);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
    procedure BeginThumbDrag(AGrabPosAlongTrack: Integer);
    procedure DragThumbTo(APosAlongTrack: Integer);
    procedure EndThumbDrag;
  published
    property Kind: TTyScrollBarKind read FKind write SetKind default sbVertical;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property PageSize: Integer read FPageSize write SetPageSize default 10;
    property SmallChange: Integer read FSmallChange write SetSmallChange default 1;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
  AMin, AMax, APosition, APageSize: Integer): TRect;

function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind;
  AButtonSize: Integer): TRect;

implementation

function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
  AMin, AMax, APosition, APageSize: Integer): TRect;
var
  TrackLen, Span, ThumbLen, FreeSpace, Travel, Pos0, Offset: Integer;
begin
  if AKind = sbVertical then
    TrackLen := ATrack.Bottom - ATrack.Top
  else
    TrackLen := ATrack.Right - ATrack.Left;
  Span := (AMax - AMin) + APageSize;
  if (Span <= 0) or (APageSize <= 0) or (AMax <= AMin) then
  begin
    // degenerate: nothing to scroll, thumb fills the whole track
    Result := ATrack;
    Exit;
  end;
  ThumbLen := (APageSize * TrackLen) div Span;
  if ThumbLen < 1 then ThumbLen := 1;
  if ThumbLen > TrackLen then ThumbLen := TrackLen;
  FreeSpace := TrackLen - ThumbLen;
  Travel := AMax - AMin;
  Pos0 := APosition - AMin;
  if Pos0 < 0 then Pos0 := 0;
  if Pos0 > Travel then Pos0 := Travel;
  if Travel <= 0 then
    Offset := 0
  else
    Offset := (Pos0 * FreeSpace) div Travel;
  if AKind = sbVertical then
    Result := Rect(ATrack.Left, ATrack.Top + Offset,
      ATrack.Right, ATrack.Top + Offset + ThumbLen)
  else
    Result := Rect(ATrack.Left + Offset, ATrack.Top,
      ATrack.Left + Offset + ThumbLen, ATrack.Bottom);
end;

function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
begin
  if AKind = sbVertical then
    Result := AClient.Right - AClient.Left
  else
    Result := AClient.Bottom - AClient.Top;
  if Result < 1 then Result := 1;
end;

function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind;
  AButtonSize: Integer): TRect;
var
  mainLen: Integer;
begin
  Result := AClient;
  if AKind = sbVertical then
    mainLen := AClient.Bottom - AClient.Top
  else
    mainLen := AClient.Right - AClient.Left;
  if mainLen <= 2 * AButtonSize then Exit;   // too short for two buttons -> whole client, no buttons
  if AKind = sbVertical then
    Result := Rect(AClient.Left, AClient.Top + AButtonSize,
      AClient.Right, AClient.Bottom - AButtonSize)
  else
    Result := Rect(AClient.Left + AButtonSize, AClient.Top,
      AClient.Right - AButtonSize, AClient.Bottom);
end;

constructor TTyScrollBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := sbVertical;
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FPageSize := 10;
  FSmallChange := 1;
  Width := 16;
  Height := 160;
end;

function TTyScrollBar.GetStyleTypeKey: string;
begin
  Result := 'TyScrollBar';
end;

procedure TTyScrollBar.SetKind(const AValue: TTyScrollBarKind);
begin
  if FKind = AValue then Exit;
  FKind := AValue;
  Invalidate;
end;

procedure TTyScrollBar.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  Invalidate;
end;

procedure TTyScrollBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
end;

procedure TTyScrollBar.SetPosition(const AValue: Integer);
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

procedure TTyScrollBar.SetPageSize(const AValue: Integer);
begin
  if FPageSize = AValue then Exit;
  if AValue < 0 then
    FPageSize := 0
  else
    FPageSize := AValue;
  Invalidate;
end;

procedure TTyScrollBar.SetSmallChange(const AValue: Integer);
begin
  if AValue < 1 then
    FSmallChange := 1
  else
    FSmallChange := AValue;
end;

procedure TTyScrollBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, Track, ThumbR: TRect;
  ThumbFill: TTyFill;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    Track := TyScrollTrackRect(R, FKind, TyScrollButtonSize(R, FKind));
    ThumbR := TyScrollThumbRect(Track, FKind, FMin, FMax, FPosition, FPageSize);
    ThumbFill := Default(TTyFill);
    ThumbFill.Kind := tfkSolid;
    ThumbFill.Color := S.TextColor;
    P.FillBackground(ThumbR, ThumbFill, S.BorderRadius);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyScrollBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

function TTyScrollBar.TrackRect: TRect;
begin
  // Inset client by a button-size at each end so the thumb/drag/paging
  // operate on the track between the (Task 5) end arrow buttons.
  Result := TyScrollTrackRect(ClientRect, FKind, TyScrollButtonSize(ClientRect, FKind));
end;

function TTyScrollBar.TrackLength: Integer;
var
  Track: TRect;
begin
  // Derive from the inset track so drag and paint share the same rect basis
  // (TyScrollThumbRect is now computed against the inset track).
  Track := TrackRect;
  if FKind = sbVertical then
    Result := Track.Bottom - Track.Top
  else
    Result := Track.Right - Track.Left;
end;

procedure TTyScrollBar.BeginThumbDrag(AGrabPosAlongTrack: Integer);
var
  ThumbR: TRect;
  ThumbStart: Integer;
begin
  ThumbR := TyScrollThumbRect(TrackRect, FKind, FMin, FMax, FPosition, FPageSize);
  if FKind = sbVertical then
    ThumbStart := ThumbR.Top
  else
    ThumbStart := ThumbR.Left;
  FDragging := True;
  FDragStartTop := ThumbStart;
  FDragGrabOffset := AGrabPosAlongTrack - ThumbStart;
end;

procedure TTyScrollBar.DragThumbTo(APosAlongTrack: Integer);
var
  Track, ThumbR: TRect;
  ThumbLen, FreeSpace, NewTop, Travel, NewPos, TrackStart: Integer;
begin
  if not FDragging then Exit;
  Track := TrackRect;
  ThumbR := TyScrollThumbRect(Track, FKind, FMin, FMax, FPosition, FPageSize);
  if FKind = sbVertical then
    ThumbLen := ThumbR.Bottom - ThumbR.Top
  else
    ThumbLen := ThumbR.Right - ThumbR.Left;
  FreeSpace := TrackLength - ThumbLen;
  if FreeSpace < 1 then FreeSpace := 1;
  // The thumb lives in [TrackStart, TrackStart+FreeSpace] in CLIENT coords,
  // because the track is inset by a button-size at each end.
  if FKind = sbVertical then
    TrackStart := Track.Top
  else
    TrackStart := Track.Left;
  NewTop := APosAlongTrack - FDragGrabOffset;
  if NewTop < TrackStart then NewTop := TrackStart;
  if NewTop > TrackStart + FreeSpace then NewTop := TrackStart + FreeSpace;
  Travel := FMax - FMin;
  NewPos := FMin + ((NewTop - TrackStart) * Travel) div FreeSpace;
  Position := NewPos;
end;

procedure TTyScrollBar.EndThumbDrag;
begin
  FDragging := False;
end;

function TTyScrollBar.PosAlong(X, Y: Integer): Integer;
begin
  if FKind = sbVertical then
    Result := Y
  else
    Result := X;
end;

procedure TTyScrollBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ThumbR: TRect;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    ThumbR := TyScrollThumbRect(TrackRect, FKind, FMin, FMax, FPosition, FPageSize);
    if PtInRect(ThumbR, Point(X, Y)) then
    begin
      BeginThumbDrag(PosAlong(X, Y));
      MouseCapture := True;
    end
    else
    begin
      // click on the track: page one PageSize toward the click
      if (FKind = sbVertical) and (Y < ThumbR.Top) then
        Position := Position - FPageSize
      else if (FKind = sbVertical) and (Y >= ThumbR.Bottom) then
        Position := Position + FPageSize
      else if (FKind = sbHorizontal) and (X < ThumbR.Left) then
        Position := Position - FPageSize
      else if (FKind = sbHorizontal) and (X >= ThumbR.Right) then
        Position := Position + FPageSize;
    end;
    try
      if CanFocus then SetFocus;
    except
    end;
  end;
end;

procedure TTyScrollBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then
    DragThumbTo(PosAlong(X, Y));
end;

procedure TTyScrollBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    EndThumbDrag;
    MouseCapture := False;
  end;
end;

end.
