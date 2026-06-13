unit tyControls.ProgressBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyProgressBar = class(TTyGraphicControl)
  private
    FMin, FMax, FPosition: Integer;
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TyProgressFillRect(const ATrack: TRect; AMin, AMax, APosition: Integer): TRect;

implementation

function TyProgressFillRect(const ATrack: TRect; AMin, AMax, APosition: Integer): TRect;
var
  TrackW, Travel, Pos0, FillW: Integer;
begin
  Result := ATrack;
  Result.Right := Result.Left;  // default: empty (zero width)
  TrackW := ATrack.Right - ATrack.Left;
  Travel := AMax - AMin;
  if Travel <= 0 then
    Exit;  // degenerate: Max <= Min → zero fill
  Pos0 := APosition - AMin;
  if Pos0 <= 0 then
  begin
    // Pos <= Min → zero fill (Result already has Right=Left)
    Exit;
  end;
  if Pos0 >= Travel then
  begin
    // Pos >= Max → full fill
    Result.Right := ATrack.Right;
    Exit;
  end;
  // Normal case: scale by Pos0/Travel
  FillW := (TrackW * Pos0) div Travel;
  Result.Right := ATrack.Left + FillW;
end;

{ TTyProgressBar }

constructor TTyProgressBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  Width := 200;
  Height := 20;
end;

function TTyProgressBar.GetStyleTypeKey: string;
begin
  Result := 'TyProgressBar';
end;

procedure TTyProgressBar.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  Invalidate;
end;

procedure TTyProgressBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
end;

procedure TTyProgressBar.SetPosition(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  if FPosition = Clamped then Exit;
  FPosition := Clamped;
  Invalidate;
end;

procedure TTyProgressBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, FillS: TTyStyleSet;
  R, TrackR, FillR: TRect;
  BW: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    // Inset the fill track by the border width so the fill doesn't paint over the border
    BW := P.Scale(S.BorderWidth);
    TrackR := Rect(R.Left + BW, R.Top + BW, R.Right - BW, R.Bottom - BW);
    // Resolve fill style for the progress fill
    FillS := ActiveController.Model.ResolveStyle('TyProgressFill', '', []);
    FillR := TyProgressFillRect(TrackR, FMin, FMax, FPosition);
    if FillR.Right > FillR.Left then
      P.FillBackground(FillR, FillS.Background, FillS.BorderRadius);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyProgressBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
