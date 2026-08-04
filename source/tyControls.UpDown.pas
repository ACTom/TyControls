unit tyControls.UpDown;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.StyleModel;

type
  TTyUpDownOrientation = (udoVertical, udoHorizontal);
  { Which half was pressed. LCL calls these btPrev/btNext (TUDBtnType). }
  TTyUpDownButton = (udbPrev, udbNext);
  { The direction-carrying click event.

    Why a second event and not OnClick: TTyUpDown inherits the base control's plain
    TNotifyEvent OnClick under the SAME NAME that LCL's TUpDown gives to a
    (Sender; Button: TUDBtnType) event. Code ported from Lazarus compiles against
    ours, assigns the handler it expects to be told a direction, and is told nothing
    -- with no diagnostic, because both sides are legal. Renaming the inherited one
    is not on the table, so the direction-carrying event gets its own name. }
  TTyUpDownClickEvent = procedure(Sender: TObject; AButton: TTyUpDownButton) of object;
  { Which way a pending step is heading. LCL calls these updNone/updUp/updDown
    (TUpDownDirection, comctrls.pp:1913). }
  TTyUpDownDirection = (uddNone, uddUp, uddDown);
  { Veto hooks, consulted BEFORE a user-driven step commits. Setting AAllowChange
    to False refuses the step: the position does not move, OnChange does not fire
    and neither does OnArrowClick.

    Both are INTENT questions -- "may the user do this?" -- so they are asked only
    on the paths the user drives (a click on a half, and each auto-repeat tick
    while a half is held). A programmatic `Position := N` is not a proposal to be
    refused, it is an instruction, so it never consults them. LCL draws the line in
    the same place: CanChange is reached from Click (customupdown.inc:369) and not
    from SetPosition. }
  TTyUpDownChangingEvent = procedure(Sender: TObject; var AAllowChange: Boolean) of object;
  { The richer form: the same veto, plus the value the step WOULD land on and the
    direction it is heading, so a handler can allow one target and refuse another.
    LCL: TUDChangingEventEx, comctrls.pp:1917. Both fire, in this order, over the
    one shared AAllowChange -- either can refuse. }
  TTyUpDownChangingEventEx = procedure(Sender: TObject; var AAllowChange: Boolean;
    ANewValue: Integer; ADirection: TTyUpDownDirection) of object;

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
    FOnArrowClick: TTyUpDownClickEvent;
    FOnChanging: TTyUpDownChangingEvent;
    FOnChangingEx: TTyUpDownChangingEventEx;
    FMinRepeatInterval: Byte;    // floor on the hold-to-repeat interval, in ms
    FHot, FHeldDir: Integer;     // -1 down, +1 up, 0 none
    FRepeatTimer: TTimer;        // lazy auto-repeat while a half is held
    FRepeatFast: Boolean;        // False = still in the initial delay, True = fast phase
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetIncrement(const AValue: Integer);
    procedure SetOrientation(const AValue: TTyUpDownOrientation);
    procedure SetWrap(const AValue: Boolean);
    procedure SetMinRepeatInterval(const AValue: Byte);
    function IsVertical: Boolean;
    procedure Step(ADir: Integer);
    procedure EnsureRepeatTimer;
    procedure HandleRepeat(Sender: TObject);
    procedure StopRepeat;
    procedure SetHot(AValue: Integer);
  protected
    { Asks both veto hooks over one shared answer, exactly as LCL's CanChange does
      (customupdown.inc:332-341). Virtual so a descendant can add its own rule
      without shadowing the user's handlers. }
    function CanChange(ANewValue: Integer; ADirection: TTyUpDownDirection): Boolean; virtual;
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
    { Floor on the hold-to-repeat interval in milliseconds, i.e. the fastest the value
      moves while a half is held down. Clamped up to 25 like LCL's setter
      (customupdown.inc:666-670); LCL's default is 100 and so is ours. LCL ramps its
      interval down to this floor in 25ms steps from 300 (customupdown.inc:244-248);
      we keep the two-phase initial-delay-then-repeat model and use this as the repeat
      interval, so the property means the same thing: how fast a held button goes. }
    property MinRepeatInterval: Byte read FMinRepeatInterval write SetMinRepeatInterval default 100;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { Fires per STEP -- including each auto-repeat tick while a half is held, which is
      what LCL's TUpDown.OnClick does too -- and says which arrow caused it. Unlike
      OnChange it fires even when the value did not move (already at Min or Max), so
      "the user pressed down but nothing happened" is observable.

      Fired AFTER the position has moved, so a handler reading Position sees the value
      the press produced. It used to fire first, which meant every such handler read
      the value from BEFORE its own event -- a silent off-by-one-step that only shows
      up as stale data in whatever the handler drives. LCL's order is the same:
      Position := ... then OnClick (customupdown.inc:371-374). }
    property OnArrowClick: TTyUpDownClickEvent read FOnArrowClick write FOnArrowClick;
    { Refuse a user-driven step; see TTyUpDownChangingEvent. }
    property OnChanging: TTyUpDownChangingEvent read FOnChanging write FOnChanging;
    { Refuse a user-driven step, knowing where it would land; see TTyUpDownChangingEventEx. }
    property OnChangingEx: TTyUpDownChangingEventEx read FOnChangingEx write FOnChangingEx;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

const
  cRepeatDelayMs = 400;   // initial hold before auto-repeat starts (the repeat
                          // interval that follows is MinRepeatInterval)

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
    { Carry the overshoot around, do not discard it. Snapping straight to the opposite
      bound means a step of more than 1 loses whatever was left over: with Min=0, Max=10
      and Increment=4, stepping up from 9 lands on 13, which is 2 past Max -- so the
      answer is 2, not 0. Snapping returned Min and threw the remainder away, which
      quietly turned a wrapping up-down from an adder into a reset. LCL carries it. }
    if Result > AMax then
      Result := AMin + ((Result - AMax - 1) mod (AMax - AMin + 1))
    else if Result < AMin then
      Result := AMax - ((AMin - Result - 1) mod (AMax - AMin + 1));
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
  FMinRepeatInterval := 100;   // LCL's default (customupdown.inc:226)
  FHot := 0;
  FHeldDir := 0;
  Width := TyDensityMetric(ActiveController, 20, '--icon-size');  // button-column width follows the icon-slot density token
  Height := TyDensityHeight(ActiveController, 34);
end;

destructor TTyUpDown.Destroy;
begin
  FreeAndNil(FRepeatTimer);   // stop the callback before teardown
  inherited Destroy;
end;

function TTyUpDown.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyButton': two arrow halves split by a hairline divider is not one button face.
    Added to 'TyButton's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyUpDown';
end;

function TTyUpDown.IsVertical: Boolean;
begin
  Result := FOrientation = udoVertical;
end;

function TTyUpDown.CanChange(ANewValue: Integer; ADirection: TTyUpDownDirection): Boolean;
begin
  Result := True;
  if Assigned(FOnChanging) then FOnChanging(Self, Result);
  if Assigned(FOnChangingEx) then FOnChangingEx(Self, Result, ANewValue, ADirection);
end;

procedure TTyUpDown.Step(ADir: Integer);
var
  v: Integer;
  dir: TTyUpDownDirection;
begin
  v := TyUpDownClamp(FPosition + ADir * FIncrement, FMin, FMax, FWrap);
  if ADir > 0 then dir := uddUp else dir := uddDown;
  { Ask before moving, and ask even when the step would land where we already are --
    LCL consults CanChange on every click regardless (customupdown.inc:369), so a
    handler that refuses on a condition rather than on the value stays in charge. A
    refused step is not a press that happened: nothing moves and nothing is announced. }
  if not CanChange(v, dir) then Exit;
  if v <> FPosition then
  begin
    FPosition := v;
    Invalidate;
    if Assigned(FOnChange) then FOnChange(Self);
  end;
  { Then the press itself. A press that changes nothing (already pinned at Min or Max)
    is still a press, and a caller driving another control from this one needs to see
    it -- but it is announced with Position already settled, so the handler reads the
    value the press produced rather than the one before it. }
  if Assigned(FOnArrowClick) then
  begin
    if ADir > 0 then FOnArrowClick(Self, udbNext) else FOnArrowClick(Self, udbPrev);
  end;
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

procedure TTyUpDown.SetMinRepeatInterval(const AValue: Byte);
begin
  if FMinRepeatInterval = AValue then Exit;
  FMinRepeatInterval := AValue;
  // Same floor LCL applies (customupdown.inc:669): below ~25ms the repeat outruns
  // the message loop and the control becomes impossible to stop on a value.
  if FMinRepeatInterval < 25 then FMinRepeatInterval := 25;
  // A live hold picks the new speed up on its next tick.
  if (FRepeatTimer <> nil) and FRepeatFast then
    FRepeatTimer.Interval := FMinRepeatInterval;
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
    FRepeatTimer.Interval := FMinRepeatInterval;
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
