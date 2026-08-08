unit tyControls.UpDown;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, TypInfo, Controls, Graphics, ExtCtrls, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.StyleModel, tyControls.StrConsts;

type
  TTyUpDownOrientation = (udoVertical, udoHorizontal);
  { Which side of the ASSOCIATED control the button pair snaps to. LCL calls these
    udLeft/udRight/udTop/udBottom (TUDAlignButton, comctrls.pp:1911); the names are
    prefixed here for the same reason every other enum in this unit is -- `udb` was
    already taken by TTyUpDownButton, so this one is `uda`. }
  TTyUpDownAlignButton = (udaLeft, udaRight, udaTop, udaBottom);
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

{ --- Associate: the three pure rules, exposed so they are testable without a form ---

  LCL keeps all three buried in methods that need a live Parent, a live handle and a live
  associate, which is why none of them has ever been unit-tested there. They are the only
  places the Associate feature can be got WRONG arithmetically, so they are functions. }

{ Render APosition the way an associated control's text should read it. Matches LCL's
  FloatToStrF(FPosition, ffNumber, 0, 0) (customupdown.inc:259) -- integer digits grouped
  in threes, no decimal part, sign in front -- but takes the group character as an
  argument instead of reading DefaultFormatSettings, so the rule is locale-independent and
  the caller decides. AThousands=False gives plain IntToStr. }
function TyUpDownFormatPosition(APosition: Integer; AThousands: Boolean;
  AThousandSep: Char): string;
{ The inverse: strip AThousandSep, trim, parse. False (and AValue=0) if there is no integer
  in there at all -- the caller keeps its current position, exactly as LCL does
  (customupdown.inc:630-631). }
function TyUpDownParsePosition(const AText: string; AThousandSep: Char;
  out AValue: Integer): Boolean;
{ Where the button pair sits once it is snapped to AAssociateBounds. On the left/right the
  pair keeps its own WIDTH and takes the associate's height; on top/bottom it keeps its own
  HEIGHT and takes the associate's width. LCL: UpdateAlignButtonPos, customupdown.inc:303-329. }
function TyUpDownAlignedBounds(const AAssociateBounds: TRect;
  AOwnWidth, AOwnHeight: Integer; AAlign: TTyUpDownAlignButton): TRect;

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
    FAssociate: TWinControl;     // the companion field this pair drives (nil = standalone)
    FAlignButton: TTyUpDownAlignButton;
    FThousands: Boolean;
    FArrowKeys: Boolean;
    FSyncing: Boolean;           // re-entrancy guard for the Position <-> associate-text round trip
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    function GetPosition: Integer;
    procedure SetPosition(const AValue: Integer);
    procedure SetIncrement(const AValue: Integer);
    procedure SetOrientation(const AValue: TTyUpDownOrientation);
    procedure SetWrap(const AValue: Boolean);
    procedure SetMinRepeatInterval(const AValue: Byte);
    procedure SetAssociate(const AValue: TWinControl);
    procedure SetAlignButton(const AValue: TTyUpDownAlignButton);
    procedure SetThousands(const AValue: Boolean);
    function IsVertical: Boolean;
    procedure Step(ADir: Integer);
    procedure EnsureRepeatTimer;
    procedure HandleRepeat(Sender: TObject);
    procedure StopRepeat;
    procedure SetHot(AValue: Integer);
    // --- associate plumbing ---
    function ThousandSepChar: Char;
    function AssociateTextProp: PPropInfo;
    function GetAssociateText: string;
    procedure SetAssociateText(const AValue: string);
    procedure WriteAssociateText;
    procedure DetachAssociate;
    procedure UpdateAlignButtonPos;
    procedure AssociateKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure AssociateMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure AssociateBoundsChanged(Sender: TObject);
    procedure AssociateEnabledChanged(Sender: TObject);
    procedure AssociateVisibleChanged(Sender: TObject);
  protected
    { Drops a dying associate. Without it the pair keeps a pointer to freed memory and the
      next step writes through it. LCL does the same (customupdown.inc:598-602). }
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
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
    { Reading this READS THROUGH to the associated control when there is one, because while
      a field is bound the field's text is the value -- the user can type into it, and LCL
      answers with what they typed (customupdown.inc:623-642 parses Associate.Caption,
      clamps it and stores it before returning). Without the read-through, typing 42 into
      the field and then clicking up gives 1, not 43: the pair would step from the last
      number IT wrote and silently discard the user's. Unassociated -- the only shape that
      existed before -- this is a plain field read. }
    property Position: Integer read GetPosition write SetPosition default 0;
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
    { The companion field this pair drives -- the headline reason anyone drops an up-down on
      a form. Setting it: writes Position into the field's text, snaps the pair to the side
      named by AlignButton, and from then on keeps the two in step in BOTH directions (a
      step rewrites the text; reading Position re-reads it). The pair also follows the
      field's bounds, Enabled and Visible, and -- when ArrowKeys is on -- steps when Up/Down
      is pressed INSIDE the field. Set to nil to unbind.

      WHICH TEXT. LCL writes Associate.Caption (customupdown.inc:254-262), which reaches the
      visible string on every LCL edit because they route Caption through RealSetText. It
      does NOT reach it on this library's own edits: TTyEdit paints its private FText and
      publishes `Text` as a property of its own, leaving TControl.Caption pointing at the
      handle's invisible native text. Binding the LCL way would therefore have moved nothing
      on screen for the single most likely associate in this package. So the target is
      resolved: a published `Text` if the field has one (TTyEdit, TTyMemo, LCL's TEdit),
      Caption otherwise (TTyLabel, and anything that overrides RealSetText -- TTySpinEdit
      does). Both spellings land on the right string, on both families.

      REFUSED BINDINGS. Pointing a second up-down at a field a first one already drives
      raises, as it does in LCL: two steppers on one field is a fight, not a setting. Self
      and another TTyUpDown are refused silently (there is no text to drive). Unlike LCL
      this does NOT refuse a field with a different Parent -- LCL's silent refusal there
      quietly DROPS the property while an .lfm is streaming, which is worse than the thing
      it prevents; instead the binding stands and only the auto-positioning is skipped,
      because a Left/Top from another parent means nothing in ours. }
    property Associate: TWinControl read FAssociate write SetAssociate;
    { Which side of Associate the pair snaps to (LCL: udRight). Left/right keep the pair's
      own width and match the field's height; top/bottom keep its own height and match the
      field's width. Ignored while there is no associate. }
    property AlignButton: TTyUpDownAlignButton read FAlignButton write SetAlignButton default udaRight;
    { Up/Down (Left/Right when horizontal) pressed INSIDE the associated field step the
      value, LCL's default (comctrls.pp:1989). Only the bare arrow -- any modifier falls
      through to the field, so Shift+Up still selects text there.

      This is what makes a bound pair reachable from the keyboard at all: the pair itself is
      a graphic control with no handle and no focus, so it can never be tabbed to, and the
      earlier reading that this made ArrowKeys impossible was measuring the wrong control.
      LCL's ArrowKeys is not about keys arriving at the up-down -- they arrive at the
      ASSOCIATE, which does have a handle and does have focus, and LCL simply hangs a
      key-down handler on it (customupdown.inc:408). Nothing in that needs the pair to be
      windowed, and nothing here does either. }
    property ArrowKeys: Boolean read FArrowKeys write FArrowKeys default True;
    { Group the number written into the field in threes (LCL's default is True,
      comctrls.pp:2000). Reading back tolerates the separator either way, so turning this
      off never strands a value that was written with it on. Unlike LCL's setter this
      re-renders the field immediately instead of leaving the old spelling until the next
      step -- a display switch that does not change the display is not one. }
    property Thousands: Boolean read FThousands write SetThousands default True;
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

function TyUpDownFormatPosition(APosition: Integer; AThousands: Boolean;
  AThousandSep: Char): string;
var
  s, grp: string;
  i, cnt: Integer;
  neg: Boolean;
begin
  neg := APosition < 0;
  { Int64 on purpose: Abs(Low(Integer)) does not fit in an Integer and wraps back to
    itself, which would print the most negative position without its digits. }
  s := IntToStr(Abs(Int64(APosition)));
  if AThousands and (AThousandSep <> #0) then
  begin
    grp := '';
    cnt := 0;
    for i := Length(s) downto 1 do
    begin
      grp := s[i] + grp;
      Inc(cnt);
      if (cnt mod 3 = 0) and (i > 1) then grp := AThousandSep + grp;
    end;
    s := grp;
  end;
  if neg then s := '-' + s;
  Result := s;
end;

function TyUpDownParsePosition(const AText: string; AThousandSep: Char;
  out AValue: Integer): Boolean;
var
  s: string;
  i: Integer;
begin
  s := '';
  for i := 1 to Length(AText) do
    if (AText[i] <> AThousandSep) or (AThousandSep = #0) then s := s + AText[i];
  Result := TryStrToInt(Trim(s), AValue);
  if not Result then AValue := 0;
end;

function TyUpDownAlignedBounds(const AAssociateBounds: TRect;
  AOwnWidth, AOwnHeight: Integer; AAlign: TTyUpDownAlignButton): TRect;
var
  W, H, L, T: Integer;
begin
  if AAlign in [udaLeft, udaRight] then
  begin
    { Beside the field: keep our own width (a spin column is as wide as it is), take the
      field's height so the two line up top and bottom. }
    W := AOwnWidth;
    H := AAssociateBounds.Bottom - AAssociateBounds.Top;
    if AAlign = udaLeft then L := AAssociateBounds.Left - W
    else L := AAssociateBounds.Right;
    T := AAssociateBounds.Top;
  end
  else
  begin
    // Above/below: keep our own height, take the field's width.
    W := AAssociateBounds.Right - AAssociateBounds.Left;
    H := AOwnHeight;
    L := AAssociateBounds.Left;
    if AAlign = udaTop then T := AAssociateBounds.Top - H
    else T := AAssociateBounds.Bottom;
  end;
  Result := Rect(L, T, L + W, T + H);
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
  FAssociate := nil;
  FAlignButton := udaRight;    // LCL's default (comctrls.pp:1988)
  FThousands := True;          // LCL's default (comctrls.pp:2000)
  FArrowKeys := True;          // LCL's default (comctrls.pp:1989)
  FSyncing := False;
  Width := TyDensityMetric(ActiveController, 20, '--icon-size');  // button-column width follows the icon-slot density token
  Height := TyDensityHeight(ActiveController, 34);
end;

destructor TTyUpDown.Destroy;
begin
  DetachAssociate;            // unhook before anything of ours can be called back into
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
  v, base: Integer;
  dir: TTyUpDownDirection;
begin
  { Step from what the FIELD says, not from the last number this pair wrote. Between two
    clicks the user may have typed straight into the associated control, and stepping from
    the stale internal value would throw their entry away without a word. GetPosition is
    the read-through (and is a plain FPosition read when nothing is associated, so an
    unbound pair behaves exactly as it did). LCL reads back the same way -- its Click reads
    the `Position` PROPERTY, whose getter parses the associate (customupdown.inc:341,623). }
  base := GetPosition;
  v := TyUpDownClamp(base + ADir * FIncrement, FMin, FMax, FWrap);
  if ADir > 0 then dir := uddUp else dir := uddDown;
  { Ask before moving, and ask even when the step would land where we already are --
    LCL consults CanChange on every click regardless (customupdown.inc:369), so a
    handler that refuses on a condition rather than on the value stays in charge. A
    refused step is not a press that happened: nothing moves and nothing is announced. }
  if not CanChange(v, dir) then Exit;
  if v <> FPosition then
  begin
    FPosition := v;
    WriteAssociateText;   // the bound field is a VIEW of Position; keep it in step
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

function TTyUpDown.GetPosition: Integer;
var
  v: Integer;
begin
  Result := FPosition;
  if FAssociate = nil then Exit;
  { Not while a sync is already in flight (SetPosition writes the text, whose OnChange may
    read Position straight back), not in the designer -- where the field's text is the
    developer's design-time content and parsing it would clobber the streamed Position --
    and not mid-stream or mid-teardown. LCL guards only the WRITE with csDesigning
    (customupdown.inc:256); guarding the read too is the same intent said out loud. }
  if FSyncing or (csDesigning in ComponentState)
     or ([csLoading, csDestroying] * ComponentState <> []) then Exit;
  FSyncing := True;
  try
    { Unparseable text is not a value: keep what we have, exactly as LCL does. This is what
      lets the user clear the field or type '-' on the way to '-5' without the pair
      snapping the entry back to a number under their cursor. }
    if TyUpDownParsePosition(GetAssociateText, ThousandSepChar, v) then
      SetPosition(v);       // clamps, and announces via OnChange only if it really moved
  finally
    FSyncing := False;
  end;
  Result := FPosition;
end;

procedure TTyUpDown.SetPosition(const AValue: Integer);
var v: Integer;
begin
  v := TyUpDownClamp(AValue, FMin, FMax, False);   // direct set never wraps
  { Deliberately NO text rewrite on the no-move path, matching LCL (SetPosition returns
    early before UpdateUpDownPositionText, customupdown.inc:694-701). It looks like a hole
    -- Position := 5 while the field reads '005' leaves '005' -- but the alternative is
    worse: the field would be re-canonicalised out from under a user in the middle of
    typing, since a bare READ of Position reaches here through GetPosition. }
  if v = FPosition then Exit;
  FPosition := v;
  { A programmatic write moves the bound field too. This is a STATE question -- "what does
    the pair hold now" -- and the field is a second view of that one number, so a view that
    ignored code writes would simply be showing something false. It is the veto hooks
    (OnChanging/OnChangingEx) that stay silent here, because those ask an INTENT question
    and `Position := N` is an instruction, not a proposal. }
  WriteAssociateText;
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

// ---- Associate ----

function TTyUpDown.ThousandSepChar: Char;
begin
  Result := DefaultFormatSettings.ThousandSeparator;
  { A locale whose group character is NUL -- or, absurdly but legally, a digit or the minus
    sign -- would produce text this control cannot read back, so the number would survive
    exactly one round trip. LCL has the same hole (it hands FloatToStrF the locale settings
    and strips the same char again without checking either end); closed here. }
  if (Result = #0) or (Result in ['0'..'9']) or (Result = '-') then Result := ',';
end;

function TTyUpDown.AssociateTextProp: PPropInfo;
begin
  { The published `Text` of a TTyEdit / TTyMemo / LCL TEdit, when there is one. Nil sends
    the caller to Caption instead. The kind check matters: `Text` is only the right target
    if it really is a string -- a published Text of some other type on some future associate
    must fall through rather than be written through a string setter. }
  Result := nil;
  if FAssociate = nil then Exit;
  Result := GetPropInfo(FAssociate, 'Text');
  if (Result <> nil)
     and not (Result^.PropType^.Kind in [tkSString, tkLString, tkAString, tkWString, tkUString]) then
    Result := nil;
end;

function TTyUpDown.GetAssociateText: string;
var
  pi: PPropInfo;
begin
  Result := '';
  if FAssociate = nil then Exit;
  pi := AssociateTextProp;
  if pi <> nil then Result := GetStrProp(FAssociate, pi)
  else Result := FAssociate.Caption;
end;

procedure TTyUpDown.SetAssociateText(const AValue: string);
var
  pi: PPropInfo;
begin
  if FAssociate = nil then Exit;
  pi := AssociateTextProp;
  if pi <> nil then SetStrProp(FAssociate, pi, AValue)
  else FAssociate.Caption := AValue;
end;

procedure TTyUpDown.WriteAssociateText;
begin
  if FAssociate = nil then Exit;
  { Not at design time: the field shows whatever the developer typed into the Object
    Inspector, and stamping the position over it would make Associate destructive to touch.
    LCL draws the line in the same place (customupdown.inc:256). }
  if csDesigning in ComponentState then Exit;
  if csDestroying in ComponentState then Exit;
  if FSyncing then Exit;   // already inside a round trip; do not re-enter through OnChange
  FSyncing := True;
  try
    SetAssociateText(TyUpDownFormatPosition(FPosition, FThousands, ThousandSepChar));
  finally
    FSyncing := False;
  end;
end;

procedure TTyUpDown.DetachAssociate;
begin
  if FAssociate = nil then Exit;
  FAssociate.RemoveAllHandlersOfObject(Self);
  FAssociate.RemoveFreeNotification(Self);
  FAssociate := nil;
end;

procedure TTyUpDown.SetAssociate(const AValue: TWinControl);
var
  i: Integer;
  other: TControl;
begin
  if AValue = FAssociate then Exit;
  { Refuse a field a sibling pair already drives, out loud. Two steppers writing one text is
    not a configuration; the silent version is a field that jumps by two and a bug report
    nobody can reproduce. LCL raises the same way (customupdown.inc:380-389) -- but reaches
    Parent.ControlCount with no nil check, so `Ud.Associate := Ed` written before
    `Ud.Parent := Self` access-violates there. Guarded. }
  if (AValue <> nil) and (Parent <> nil) then
    for i := 0 to Parent.ControlCount - 1 do
    begin
      other := Parent.Controls[i];
      if (other <> Self) and (other is TTyUpDown)
         and (TTyUpDown(other).FAssociate = AValue) then
        raise Exception.CreateFmt(rsTyUpDownAlreadyAssociated, [AValue.Name, other.Name]);
    end;
  DetachAssociate;
  { LCL additionally refuses an associate that is itself a TCustomUpDown; here the TYPE
    already does it -- Associate is a TWinControl and this pair is a graphic control, so
    `Ud2.Associate := Ud1` does not compile. A field under a different parent IS accepted:
    see the property comment for why LCL's silent refusal there is the worse failure. }
  if AValue <> nil then
  begin
    FAssociate := AValue;
    FAssociate.FreeNotification(Self);          // so Notification fires if it is destroyed
    FAssociate.AddHandlerOnKeyDown(@AssociateKeyDown, True);
    FAssociate.AddHandlerOnMouseWheel(@AssociateMouseWheel, True);
    FAssociate.AddHandlerOnChangeBounds(@AssociateBoundsChanged, True);
    FAssociate.AddHandlerOnEnabledChanged(@AssociateEnabledChanged, True);
    FAssociate.AddHandlerOnVisibleChanged(@AssociateVisibleChanged, True);
    WriteAssociateText;
    UpdateAlignButtonPos;
  end;
  Invalidate;
end;

procedure TTyUpDown.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAssociate) then
  begin
    { Drop the reference WITHOUT going through DetachAssociate: the associate is already in
      its destructor, so reaching back into its handler lists is a use-after-free. They die
      with it anyway. (LCL routes this through SetAssociate(nil), which does touch them.) }
    FAssociate := nil;
    Invalidate;
  end;
end;

procedure TTyUpDown.SetAlignButton(const AValue: TTyUpDownAlignButton);
begin
  if FAlignButton = AValue then Exit;
  FAlignButton := AValue;
  UpdateAlignButtonPos;
end;

procedure TTyUpDown.SetThousands(const AValue: Boolean);
begin
  if FThousands = AValue then Exit;
  FThousands := AValue;
  WriteAssociateText;   // a display switch has to change the display; LCL's setter does not
end;

procedure TTyUpDown.UpdateAlignButtonPos;
var
  R: TRect;
begin
  if FAssociate = nil then Exit;
  { A Left/Top belonging to another parent is measured from another origin, so snapping to
    it would land the pair somewhere arbitrary. Leave the designer's own bounds alone
    instead -- visibly unsnapped beats invisibly misplaced. }
  if FAssociate.Parent <> Parent then Exit;
  R := TyUpDownAlignedBounds(FAssociate.BoundsRect, Width, Height, FAlignButton);
  SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
end;

procedure TTyUpDown.AssociateKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if not FArrowKeys then Exit;
  { Bare arrow only. With a modifier the key belongs to the field -- Shift+Up extends a
    selection there, Ctrl+Up may mean something to a memo -- and swallowing it would make
    binding an up-down quietly break editing. LCL: customupdown.inc:440. }
  if Shift <> [] then Exit;
  { An arrow pressed in the bound field IS pressing that arrow: this is the same gesture
    path a mouse click takes, so it consults OnChanging/OnChangingEx and reports through
    OnArrowClick. LCL agrees -- AssociateKeyDown goes through AdjustPos to the button's
    Click, which is the method that calls CanChange (customupdown.inc:434-470, 341). }
  if IsVertical then
  begin
    case Key of
      VK_UP:    begin Step(1);  Key := 0; end;
      VK_DOWN:  begin Step(-1); Key := 0; end;
    end;
  end
  else
  begin
    // Horizontal: up = right, down = left -- the same halves the pair paints.
    case Key of
      VK_RIGHT: begin Step(1);  Key := 0; end;
      VK_LEFT:  begin Step(-1); Key := 0; end;
    end;
  end;
end;

procedure TTyUpDown.AssociateMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  { Not gated on ArrowKeys -- LCL does not gate it either (customupdown.inc:475-492), and a
    user who can arrow the field expects the wheel over it to do the same thing. }
  if Handled then Exit;
  if WheelDelta > 0 then begin Step(1); Handled := True; end
  else if WheelDelta < 0 then begin Step(-1); Handled := True; end;
end;

procedure TTyUpDown.AssociateBoundsChanged(Sender: TObject);
begin
  UpdateAlignButtonPos;
end;

procedure TTyUpDown.AssociateEnabledChanged(Sender: TObject);
begin
  if FAssociate <> nil then Enabled := FAssociate.Enabled;
end;

procedure TTyUpDown.AssociateVisibleChanged(Sender: TObject);
begin
  if FAssociate <> nil then Visible := FAssociate.Visible;
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
    { The stand-alone spinner draws exactly what an embedded one does. }
    if AUp then P.DrawGlyph(TySquareGlyphBox(AHalf), tgTriangleUp, halfS.TextColor, 3, 1)
    else P.DrawGlyph(TySquareGlyphBox(AHalf), tgTriangleDown, halfS.TextColor, 3, 1);
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
