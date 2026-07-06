unit tyControls.UpDown;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel;

type
  TTyUpDownOrientation = (udoVertical, udoHorizontal);

{ Device rect of the up (increment) or down (decrement) half within [0,0,AW,AH].
  Vertical: up = top, down = bottom. Horizontal: up = right, down = left. }
function TyUpDownButtonRect(AUp: Boolean; AW, AH: Integer; AVertical: Boolean): TRect;
{ Which half a point hits: +1 = up/increment, -1 = down/decrement, 0 = outside. }
function TyUpDownHit(AX, AY, AW, AH: Integer; AVertical: Boolean): Integer;
{ Clamp (or WRAP to the opposite bound) a proposed value into [AMin,AMax]. }
function TyUpDownClamp(AValue, AMin, AMax: Integer; AWrap: Boolean): Integer;

type
  { A standalone up/down spin-button pair (no edit of its own — bind it to any control
    via OnChange reading Position). Click a half to step Position by Increment; HOLD to
    auto-repeat (an initial delay, then fast). Vertical (default) stacks up-over-down;
    horizontal places down-left, up-right. Reuses the 'TyButton' theming (no extra
    .tycss); a leaf TTyGraphicControl so it needs no backdrop fill. }
  TTyUpDown = class(TTyGraphicControl)
  private
    FMin, FMax, FPosition, FIncrement: Integer;
    FOrientation: TTyUpDownOrientation;
    FWrap: Boolean;
    FOnChange: TNotifyEvent;
    FHot, FHeldDir: Integer;     // -1 down, +1 up, 0 none
    FRepeatTimer: TTimer;        // lazy auto-repeat while a half is held
    FRepeatFast: Boolean;        // False = still in the initial delay, True = fast phase
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetIncrement(const AValue: Integer);
    procedure SetOrientation(const AValue: TTyUpDownOrientation);
    procedure SetWrap(const AValue: Boolean);
    function IsVertical: Boolean;
    procedure Step(ADir: Integer);
    procedure EnsureRepeatTimer;
    procedure HandleRepeat(Sender: TObject);
    procedure StopRepeat;
    procedure SetHot(AValue: Integer);
  protected
    function GetStyleTypeKey: string; override;   // 'TyButton'
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property Increment: Integer read FIncrement write SetIncrement default 1;
    property Orientation: TTyUpDownOrientation read FOrientation write SetOrientation default udoVertical;
    property Wrap: Boolean read FWrap write SetWrap default False;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  cRepeatDelayMs = 400;   // initial hold before auto-repeat starts
  cRepeatFastMs  = 60;    // repeat interval once going

function TyUpDownButtonRect(AUp: Boolean; AW, AH: Integer; AVertical: Boolean): TRect;
begin
  if AVertical then
  begin
    if AUp then Result := Rect(0, 0, AW, AH div 2)
    else Result := Rect(0, AH div 2, AW, AH);
  end
  else
  begin
    if AUp then Result := Rect(AW div 2, 0, AW, AH)   // up = right
    else Result := Rect(0, 0, AW div 2, AH);          // down = left
  end;
end;

function TyUpDownHit(AX, AY, AW, AH: Integer; AVertical: Boolean): Integer;
begin
  Result := 0;
  if (AX < 0) or (AY < 0) or (AX >= AW) or (AY >= AH) then Exit;
  if AVertical then
  begin
    if AY < AH div 2 then Result := 1 else Result := -1;
  end
  else
  begin
    if AX >= AW div 2 then Result := 1 else Result := -1;
  end;
end;

function TyUpDownClamp(AValue, AMin, AMax: Integer; AWrap: Boolean): Integer;
begin
  if AMax < AMin then Exit(AMin);
  Result := AValue;
  if AWrap then
  begin
    if Result > AMax then Result := AMin
    else if Result < AMin then Result := AMax;
  end
  else
  begin
    if Result > AMax then Result := AMax
    else if Result < AMin then Result := AMin;
  end;
end;

{ TTyUpDown }

constructor TTyUpDown.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FIncrement := 1;
  FOrientation := udoVertical;
  FWrap := False;
  FHot := 0;
  FHeldDir := 0;
  Width := 20;
  Height := 34;
end;

destructor TTyUpDown.Destroy;
begin
  FreeAndNil(FRepeatTimer);   // stop the callback before teardown
  inherited Destroy;
end;

function TTyUpDown.GetStyleTypeKey: string;
begin
  Result := 'TyButton';
end;

function TTyUpDown.IsVertical: Boolean;
begin
  Result := FOrientation = udoVertical;
end;

procedure TTyUpDown.Step(ADir: Integer);
var v: Integer;
begin
  v := TyUpDownClamp(FPosition + ADir * FIncrement, FMin, FMax, FWrap);
  if v = FPosition then Exit;
  FPosition := v;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyUpDown.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  SetPosition(FPosition);   // re-clamp
  Invalidate;
end;

procedure TTyUpDown.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  SetPosition(FPosition);   // re-clamp
  Invalidate;
end;

procedure TTyUpDown.SetPosition(const AValue: Integer);
var v: Integer;
begin
  v := TyUpDownClamp(AValue, FMin, FMax, False);   // direct set never wraps
  if v = FPosition then Exit;
  FPosition := v;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyUpDown.SetIncrement(const AValue: Integer);
begin
  if FIncrement = AValue then Exit;
  FIncrement := Math.Max(1, AValue);
end;

procedure TTyUpDown.SetOrientation(const AValue: TTyUpDownOrientation);
begin
  if FOrientation = AValue then Exit;
  FOrientation := AValue;
  Invalidate;
end;

procedure TTyUpDown.SetWrap(const AValue: Boolean);
begin
  if FWrap = AValue then Exit;
  FWrap := AValue;
end;

procedure TTyUpDown.SetHot(AValue: Integer);
begin
  if FHot = AValue then Exit;
  FHot := AValue;
  Invalidate;
end;

procedure TTyUpDown.EnsureRepeatTimer;
begin
  if FRepeatTimer = nil then
  begin
    FRepeatTimer := TTimer.Create(Self);
    FRepeatTimer.Enabled := False;
    FRepeatTimer.OnTimer := @HandleRepeat;
  end;
end;

procedure TTyUpDown.HandleRepeat(Sender: TObject);
begin
  if FHeldDir = 0 then begin StopRepeat; Exit; end;
  if not FRepeatFast then
  begin
    FRepeatFast := True;
    FRepeatTimer.Interval := cRepeatFastMs;
  end;
  Step(FHeldDir);
end;

procedure TTyUpDown.StopRepeat;
begin
  if FRepeatTimer <> nil then FRepeatTimer.Enabled := False;
  FRepeatFast := False;
end;

procedure TTyUpDown.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var hit: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  hit := TyUpDownHit(X, Y, ClientWidth, ClientHeight, IsVertical);
  if hit = 0 then Exit;
  FHeldDir := hit;
  Step(hit);                       // one immediate step
  EnsureRepeatTimer;               // then auto-repeat while held
  FRepeatFast := False;
  FRepeatTimer.Interval := cRepeatDelayMs;
  FRepeatTimer.Enabled := True;
  Invalidate;
end;

procedure TTyUpDown.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  SetHot(TyUpDownHit(X, Y, ClientWidth, ClientHeight, IsVertical));
end;

procedure TTyUpDown.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  StopRepeat;
  if FHeldDir <> 0 then begin FHeldDir := 0; Invalidate; end;
end;

procedure TTyUpDown.MouseLeave;
begin
  inherited MouseLeave;
  StopRepeat;
  FHeldDir := 0;
  SetHot(0);
end;

procedure TTyUpDown.Paint;
var
  P: TTyPainter;
  S, halfS: TTyStyleSet;
  R, upR, dnR, fillR, divR: TRect;
  bw, mid: Integer;
  df: TTyFill;

  procedure PaintHalf(AUp: Boolean; ADir: Integer; const AHalf: TRect);
  var states: TTyStateSet;
  begin
    states := [tysNormal];
    if FHeldDir = ADir then states := [tysActive]
    else if (FHeldDir = 0) and (FHot = ADir) then states := [tysHover];
    if states <> [tysNormal] then
    begin
      // Overlay the hovered/pressed half with its state background (inset past the frame border).
      halfS := ActiveController.Model.ResolveStyle('TyButton', StyleClass, states);
      fillR := Rect(AHalf.Left + bw, AHalf.Top + bw, AHalf.Right - bw, AHalf.Bottom - bw);
      if (fillR.Right > fillR.Left) and (fillR.Bottom > fillR.Top) then
        P.FillBackground(fillR, halfS.Background, 0);
    end
    else
      halfS := S;
    if AUp then P.DrawGlyph(AHalf, tgArrowUp, halfS.TextColor, 3)
    else P.DrawGlyph(AHalf, tgArrowDown, halfS.TextColor, 3);
  end;

begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    S := CurrentStyle;                          // 'TyButton' frame/bg/border/text
    DrawFrame(P, R, S);                          // shared frame + background + border
    bw := P.Scale(S.BorderWidth);
    if bw < 1 then bw := 1;

    upR := TyUpDownButtonRect(True, R.Right, R.Bottom, IsVertical);
    dnR := TyUpDownButtonRect(False, R.Right, R.Bottom, IsVertical);
    PaintHalf(True, 1, upR);
    PaintHalf(False, -1, dnR);

    // Crisp divider between the two halves, in the border colour (solid fill, radius 0).
    df := Default(TTyFill);
    df.Kind := tfkSolid;
    df.Color := S.BorderColor;
    if IsVertical then
    begin
      mid := R.Bottom div 2;
      divR := Rect(R.Left + bw, mid, R.Right - bw, mid + bw);
    end
    else
    begin
      mid := R.Right div 2;
      divR := Rect(mid, R.Top + bw, mid + bw, R.Bottom - bw);
    end;
    P.FillBackground(divR, df, 0);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
