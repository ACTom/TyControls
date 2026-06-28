unit tyControls.ScrollBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, StdCtrls, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation;
type
  TTyScrollBarKind = (sbHorizontal, sbVertical);

  TTyScrollBar = class(TTyCustomControl)
  private
    FKind: TTyScrollBarKind;
    FMin, FMax, FPosition, FPageSize: Integer;
    FSmallChange: Integer;
    FOnChange: TNotifyEvent;
    FOnScroll: TScrollEvent;
    FDragGrabOffset: Integer;
    FDragStartTop: Integer;
    FAnimEnabled: Boolean;
    FPosAnim: TTyAnimator;      // 0..1 traversal driving FAnimFrom -> FAnimTo
    FAnimFrom, FAnimTo: Single; // displayed-thumb-position endpoints (Min..Max units)
    FTimer: TTimer;            // lazy; only created when actually animating
    function TrackRect: TRect;
    function TrackLength: Integer;
    function PosAlong(X, Y: Integer): Integer;
    procedure ButtonRects(const AClient: TRect; out ALo, AHi: TRect);
    procedure SetKind(const AValue: TTyScrollBarKind);
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetPageSize(const AValue: Integer);
    procedure SetSmallChange(const AValue: Integer);
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
  protected
    FDragging: Boolean;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    // Fire OnScroll with ACode and the proposed APos (which the handler may
    // override via the var parameter); then commit Position := APos. This keeps
    // OnChange firing too (via the Position setter). Used by the user-driven
    // keyboard/track-paging paths.
    procedure DoScroll(ACode: TScrollCode; var APos: Integer);
    procedure ScrollTo(ACode: TScrollCode; AProposed: Integer);
    // Current displayed (possibly mid-animation) thumb position, eased between
    // the from/to endpoints. At rest this equals the logical FPosition.
    function DisplayPos: Single;
    // Steppable animation seam (no wall-clock): advance the thumb ease by AMs and
    // return True iff the eased progress changed. The lazy TTimer drives it at
    // runtime; tests drive it directly via an access subclass.
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Force the *animating* path toward AValue (clamped) regardless of handle
    // state. Runtime always routes through SetPosition (which snaps headless);
    // this is the test seam so the animation is reachable without a window.
    procedure SetPositionAnimating(AValue: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetStyleTypeKey: string; override;
    procedure BeginThumbDrag(AGrabPosAlongTrack: Integer);
    procedure DragThumbTo(APosAlongTrack: Integer);
    procedure EndThumbDrag;
    { True while the user is dragging the thumb with the mouse. }
    property Dragging: Boolean read FDragging;
  published
    // On by default. When enabled and the control has a window handle, a
    // PROGRAMMATIC Position change (keyboard/wheel/track-click) eases the painted
    // thumb to the new value; with no handle (every render test) or while
    // dragging it snaps, preserving exact-pixel tests and live mouse tracking.
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
    property Kind: TTyScrollBarKind read FKind write SetKind default sbVertical;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    property PageSize: Integer read FPageSize write SetPageSize default 10;
    property SmallChange: Integer read FSmallChange write SetSmallChange default 1;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnScroll: TScrollEvent read FOnScroll write FOnScroll;
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
  Cross, MinThumb: Integer;
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
  if AKind = sbVertical then Cross := ATrack.Right - ATrack.Left else Cross := ATrack.Bottom - ATrack.Top;
  MinThumb := Cross; if MinThumb < 6 then MinThumb := 6;
  if ThumbLen < MinThumb then ThumbLen := MinThumb;
  if ThumbLen > TrackLen then ThumbLen := TrackLen;
  FreeSpace := TrackLen - ThumbLen;
  Travel := AMax - AMin;
  Pos0 := APosition - AMin;
  if Pos0 < 0 then Pos0 := 0;
  if Pos0 > Travel then Pos0 := Travel;
  if Travel <= 0 then
    Offset := 0
  else
    Offset := Integer((Int64(Pos0) * FreeSpace) div Travel);
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
  FAnimEnabled := True;
  // Thumb-glide animator: 0..1 traversal in ~120ms, decelerating. Start settled
  // at the rest endpoint so DisplayPos == FPosition before any change.
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 120;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := FPosition;
  FAnimTo := FPosition;
  Width := 16;
  Height := 160;
end;

destructor TTyScrollBar.Destroy;
begin
  // FTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  inherited Destroy;
end;

function TTyScrollBar.GetStyleTypeKey: string;
begin
  Result := 'TyScrollBar';
end;

procedure TTyScrollBar.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;  // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

procedure TTyScrollBar.HandleTimer(Sender: TObject);
begin
  if AdvanceAnimation(FTimer.Interval) then
    Invalidate;
  if not FPosAnim.Running then
    FTimer.Enabled := False;
end;

function TTyScrollBar.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyScrollBar.DisplayPos: Single;
begin
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyScrollBar.SetPositionAnimating(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  // Arm the ease from the currently displayed thumb position to the new target,
  // independent of handle state (test seam). FPosition still tracks the logical
  // value for Min/Max/value semantics.
  FAnimFrom := DisplayPos;
  FAnimTo := Clamped;
  FPosAnim.Progress := 0;
  FPosAnim.Target := 1;
  FPosition := Clamped;
  Invalidate;
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
  // Decide how the PAINTED thumb reaches the new value:
  if FDragging then
  begin
    // Live drag: the thumb must track the mouse, so snap instantly.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
  end
  else if FAnimEnabled and HandleAllocated then
  begin
    // Programmatic change with a window: ease the thumb from where it is now to
    // the new value. (Headless render tests have no handle -> they snap below.)
    FAnimFrom := DisplayPos;
    FAnimTo := Clamped;
    FPosAnim.Progress := 0;
    FPosAnim.Target := 1;
    EnsureTimer;
    FTimer.Enabled := True;
  end
  else
  begin
    // Headless (no handle) or animations off: snap so DisplayPos == new
    // immediately, keeping the existing exact-pixel scrollbar tests green.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
  end;
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

procedure TTyScrollBar.DoScroll(ACode: TScrollCode; var APos: Integer);
begin
  if Assigned(FOnScroll) then
    FOnScroll(Self, ACode, APos);
end;

procedure TTyScrollBar.ScrollTo(ACode: TScrollCode; AProposed: Integer);
var
  P: Integer;
begin
  // Clamp the proposed value first, let the OnScroll handler optionally adjust
  // it (honoring its var parameter), then commit through the Position setter
  // (which clamps again and fires OnChange).
  P := AProposed;
  if P < FMin then P := FMin;
  if P > FMax then P := FMax;
  DoScroll(ACode, P);
  Position := P;
end;

function TTyScrollBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  // Let the published OnMouseWheel/Up/Down events fire first; if a handler marks
  // the wheel handled, honor that and do not step.
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if not Enabled then Exit;
  // Convention: wheel-up (WheelDelta > 0) scrolls content up -> Position
  // DECREASES by SmallChange; wheel-down increases it. (Standard scrollbar.)
  Position := Position - Sign(WheelDelta) * FSmallChange;
  Result := True;
end;

procedure TTyScrollBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, ThumbS: TTyStyleSet;
  R, Track, ThumbR, LoR, HiR: TRect;
  ThumbFill: TTyFill;
  ThumbStates: TTyStateSet;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    Track := TyScrollTrackRect(R, FKind, TyScrollButtonSize(R, FKind));
    // The PAINTED thumb uses the displayed (possibly mid-animation) position; at
    // rest DisplayPos == FPosition so headless renders are pixel-identical. The
    // track-paging hit math, drag math and BeginThumbDrag keep using FPosition.
    ThumbR := TyScrollThumbRect(Track, FKind, FMin, FMax, Round(DisplayPos), FPageSize);
    // Thumb fill is its own sub-element typeKey (TyScrollThumb). Feed the control's
    // hover/press state so TyScrollThumb:hover/:active render (matches the pre-typeKey
    // behavior where the thumb borrowed the parent's state-resolved TextColor).
    ThumbStates := [];
    if FPressed then
      Include(ThumbStates, tysActive)
    else if FHover then
      Include(ThumbStates, tysHover);
    ThumbS := ActiveController.Model.ResolveStyle('TyScrollThumb', '', ThumbStates);
    ThumbFill := Default(TTyFill);
    ThumbFill.Kind := tfkSolid;
    ThumbFill.Color := ThumbS.Background.Color;
    P.FillBackground(ThumbR, ThumbFill, ThumbS.BorderRadius);
    ButtonRects(R, LoR, HiR);
    if (LoR.Right > LoR.Left) then   // buttons exist
    begin
      if FKind = sbVertical then
      begin
        P.DrawGlyph(LoR, tgArrowUp, S.TextColor, 2);
        P.DrawGlyph(HiR, tgArrowDown, S.TextColor, 2);
      end
      else
      begin
        P.DrawGlyph(LoR, tgArrowLeft, S.TextColor, 2);
        P.DrawGlyph(HiR, tgArrowRight, S.TextColor, 2);
      end;
    end;
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

procedure TTyScrollBar.ButtonRects(const AClient: TRect; out ALo, AHi: TRect);
var
  bs, mainLen: Integer;
begin
  bs := TyScrollButtonSize(AClient, FKind);
  if FKind = sbVertical then
    mainLen := AClient.Bottom - AClient.Top
  else
    mainLen := AClient.Right - AClient.Left;
  if mainLen <= 2 * bs then
  begin
    ALo := Rect(0, 0, 0, 0);
    AHi := Rect(0, 0, 0, 0);
    Exit;   // no buttons
  end;
  if FKind = sbVertical then
  begin
    ALo := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + bs);
    AHi := Rect(AClient.Left, AClient.Bottom - bs, AClient.Right, AClient.Bottom);
  end
  else
  begin
    ALo := Rect(AClient.Left, AClient.Top, AClient.Left + bs, AClient.Bottom);
    AHi := Rect(AClient.Right - bs, AClient.Top, AClient.Right, AClient.Bottom);
  end;
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
  // Sync the displayed thumb to the logical position on grab so DisplayPos ==
  // FPosition at drag start (subsequent drag SetPosition calls snap).
  FAnimFrom := FPosition;
  FAnimTo := FPosition;
  FPosAnim.SetTargetImmediate(1);
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
  NewPos := FMin + Integer((Int64(NewTop - TrackStart) * Travel) div FreeSpace);
  // Live drag tracking fires scTrack with the proposed value (handler may
  // adjust it); commit through the Position setter (clamps + OnChange).
  if NewPos < FMin then NewPos := FMin;
  if NewPos > FMax then NewPos := FMax;
  DoScroll(scTrack, NewPos);
  Position := NewPos;
end;

procedure TTyScrollBar.EndThumbDrag;
var
  P: Integer;
begin
  if FDragging then
  begin
    // Final committed value of the drag: scPosition then scEndScroll.
    P := FPosition;
    DoScroll(scPosition, P);
    if P <> FPosition then
      Position := P;
    P := FPosition;
    DoScroll(scEndScroll, P);
    if P <> FPosition then
      Position := P;
  end;
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
  ThumbR, LoR, HiR: TRect;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    ButtonRects(ClientRect, LoR, HiR);
    if PtInRect(LoR, Point(X, Y)) then
    begin
      ScrollTo(scLineUp, Position - FSmallChange);
      try if CanFocus then SetFocus; except end;
      Exit;
    end;
    if PtInRect(HiR, Point(X, Y)) then
    begin
      ScrollTo(scLineDown, Position + FSmallChange);
      try if CanFocus then SetFocus; except end;
      Exit;
    end;
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
        ScrollTo(scPageUp, Position - FPageSize)
      else if (FKind = sbVertical) and (Y >= ThumbR.Bottom) then
        ScrollTo(scPageDown, Position + FPageSize)
      else if (FKind = sbHorizontal) and (X < ThumbR.Left) then
        ScrollTo(scPageUp, Position - FPageSize)
      else if (FKind = sbHorizontal) and (X >= ThumbR.Right) then
        ScrollTo(scPageDown, Position + FPageSize);
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

procedure TTyScrollBar.KeyDown(var Key: Word; Shift: TShiftState);
var
  Dec1, Inc1: Word;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if FKind = sbVertical then
  begin
    Dec1 := VK_UP;
    Inc1 := VK_DOWN;
  end
  else
  begin
    Dec1 := VK_LEFT;
    Inc1 := VK_RIGHT;
  end;
  if Key = Dec1 then
  begin
    ScrollTo(scLineUp, Position - FSmallChange);
    Key := 0;
  end
  else if Key = Inc1 then
  begin
    ScrollTo(scLineDown, Position + FSmallChange);
    Key := 0;
  end
  else
    case Key of
      VK_PRIOR: begin ScrollTo(scPageUp, Position - FPageSize); Key := 0; end;
      VK_NEXT:  begin ScrollTo(scPageDown, Position + FPageSize); Key := 0; end;
      VK_HOME:  begin ScrollTo(scTop, FMin); Key := 0; end;
      VK_END:   begin ScrollTo(scBottom, FMax); Key := 0; end;
    end;
end;

end.
