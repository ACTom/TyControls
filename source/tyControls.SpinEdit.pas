unit tyControls.SpinEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8,
  ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Edit;
type
  TTySpinStepEvent = procedure(ADir: Integer) of object;

  { The pointer side of a pair of spin buttons, shared by TTySpinEdit and TTyFloatSpinEdit (they
    cannot share an ancestor: one is its own control, the other hangs its buttons in TTyEdit's
    trailing zone). Users found the buttons too small to hit. Their size is the theme's
    (--field-button-width); what this adds is what a native spinner gives a small target:
    - the arrow cursor over the buttons: the I-beam said "text" there;
    - a hover and a pressed state on the half under the pointer, filled with TyButton's :hover /
      :active background, as the stand-alone TTyUpDown fills its halves;
    - hold to repeat: one step on the press, then after a delay one step per interval until the
      release, as TTyUpDown and LCL's spin edit do.
    A direction is +1 (up), -1 (down) or 0 (neither). }
  TTySpinButtons = class
  private
    FOwner: TWinControl;
    FOnStep: TTySpinStepEvent;
    FHot, FHeld: Integer;
    FRepeatTimer: TTimer;
    FRepeatFast: Boolean;      // False = still in the initial delay
    FSavedCursor: TCursor;
    FCursorOverridden: Boolean;
    procedure SetHot(AValue: Integer);
    procedure SetArrowCursor(AOn: Boolean);
    procedure HandleRepeat(Sender: TObject);
    procedure StopRepeat;
  public
    constructor Create(AOwner: TWinControl; AOnStep: TTySpinStepEvent);
    destructor Destroy; override;
    { AHit: the half under the pointer. AEnabled: the buttons may step (False while the value is
      read-only). The cursor turns to an arrow over them either way, since they are not text,
      but a button that will not respond does not light up. }
    procedure MouseMove(AHit: Integer; AEnabled: Boolean);
    { True when the press landed on a button. With AEnabled it has stepped once and is held. }
    function MouseDown(AHit: Integer; AEnabled: Boolean): Boolean;
    procedure MouseUp;
    procedure MouseLeave;
    { The state a half is drawn in: pressed while held, hovered under the pointer. }
    function StateOf(ADir: Integer): TTyStateSet;
    { Fill one half's hover / pressed background and return the ink for its arrow. The fill is
      clipped to AInner, the field inside its frame (TySpinFrameInsetPx), and rounded only where it
      meets the field's own rounded corner. In the normal state nothing is filled and the ink is
      the field's. }
    function PaintHalf(APainter: TTyPainter; AController: TTyCustomStyleController;
      const AHalf, AInner: TRect; const AFieldStyle: TTyStyleSet; ADir: Integer): TTyColor;
    property Hot: Integer read FHot;
    property Held: Integer read FHeld;
    { The hold-to-repeat timer, nil until the first held press on a control with a window. }
    property RepeatTimer: TTimer read FRepeatTimer;
  end;

  { An INTEGER spin edit: the counterpart of LCL's TSpinEdit (spin.pp:146).

    #190: it descends from TTyCustomEdit and uses its text engine -- selection by mouse and
    Shift+arrows, Cut / Copy / Paste, Undo / Redo, the default right-click menu, the input
    method -- because LCL's TSpinEdit IS a TCustomEdit and code written against it uses all of
    those. It used to be a TTyCustomControl with a small typing buffer of its own (no selection,
    clipboard or undo), which was documented as a design choice and found wanting by the
    behaviour audit. TTyFloatSpinEdit already sat on the edit engine (through
    TTyCustomNumericEdit) and this control now hangs its buttons the same way: in TTyEdit's
    trailing zone (RightReserve / PaintTrailing / TrailingZone).

    What it keeps of its own: the committed integer Value (the text is what the user is typing;
    Enter, leaving the field or EditingDone commits it), MinValue / MaxValue / Increment,
    EditorEnabled, ValueEmpty, OnValueChange, and the three public number seams of LCL's
    spin.pp:74-76. Theme: 'TySpinEdit', as before. }
  TTyCustomSpinEdit = class(TTyCustomEdit)
  private
    FSpin: TTySpinButtons;
    FMinValue, FMaxValue, FValue, FIncrement: Integer;
    FOnValueChange: TNotifyEvent;
    FEditorEnabled: Boolean;
    FValueEmpty: Boolean;
    { True while the control itself rewrites the text from Value: that is not input, so it does
      not end ValueEmpty. }
    FSyncing: Boolean;
    procedure SetMinValue(const AValue: Integer);
    procedure SetMaxValue(const AValue: Integer);
    procedure SetValue(const AValue: Integer);
    procedure SetIncrement(const AValue: Integer);
    procedure SetEditorEnabled(const AValue: Boolean);
    procedure SetValueEmpty(const AValue: Boolean);
    function GetSpinText: TCaption;
    procedure SetSpinText(const AValue: TCaption);
    { Registered first on the edit's OnChange list: any text change that is not the control's
      own rewrite is input, and input ends the blank state. }
    procedure HandleTextChange(Sender: TObject);
    { True for the keystrokes that would change the text. Used only while EditorEnabled is
      False; the same set TTyFloatSpinEdit blocks. }
    function KeyWouldEditTheText(AKey: Word; AShift: TShiftState): Boolean;
    { Whether AText inserted at AAt into AResidual keeps a number: digits, and one '-' at the
      start. Returns what of AText may go in. }
    function NumberPart(const AResidual: string; AAt: Integer; const AText: string): string;
    procedure SpinStep(ADir: Integer);
    function SpinHitAt(X, Y: Integer): Integer;
  protected
    { OnValueChange is the other half of OnChange: the committed integer actually moved.
      Anything that wants "the number is now N" (a preview, a model write-back) hangs here and
      is not woken by every keystroke. }
    procedure DoValueChange; virtual;
    { Rewrite the text from Value (blank while ValueEmpty), as a write from code: OnChange fires
      if the text really moved, and Modified comes back False. }
    procedure SyncTextToValue;
    { The typed text is not the value's (#144): Esc has something to put back. }
    function TextDiffersFromValue: Boolean;
    { Parse the text, clamp it and make it the Value; the user finishing an edit, so Modified
      is kept. Enter, leaving the field and EditingDone all come here. }
    procedure CommitEdit;
    function GetStyleTypeKey: string; override;
    { The button column at the right of the text area, and the two arrows painted in it. }
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect;
      const AStyle: TTyStyleSet); override;
    { False: the spin buttons keep their own arrow cursor (TTySpinButtons). }
    function TrailingShowsArrow: Boolean; override;
    { Typing, paste and an input-method commit all funnel through here: only digits and a
      leading '-' go in, and nothing at all while EditorEnabled is False. }
    function FilterInsert(const AText: string): string; override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoExit; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    property SpinButtons: TTySpinButtons read FSpin;
    { Caption is Text (TTyCustomEdit), and here a Caption write takes the Text setter's number
      rule too: TTyUpDown's Associate and an action link write the value, not a string. }
    procedure RealSetText(const AValue: TCaption); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { The three seams LCL descendants override to change the number rules
      (spin.pp:74-76, all public virtual). Every clamp, every format and every parse in
      this control goes through them, so a descendant can add hex, a unit suffix or a
      snap-to-multiple without reimplementing the control. }
    function GetLimitedValue(const AValue: Integer): Integer; virtual;
    function ValueToStr(const AValue: Integer): string; virtual;
    function StrToValue(const S: string): Integer; virtual;
    { Move the value by ADelta from what is typed, the way the USER moves it: refused while
      ReadOnly, and it marks the field Modified, because the arrows are the user editing,
      exactly like typing. Every button, arrow key and wheel notch goes through here (as on
      TTyFloatSpinEdit), so a descendant can re-point or refuse all of them at once. }
    procedure StepValue(ADelta: Integer); virtual;
    { Commits what is typed first, so OnEditingDone sees the value Enter made. }
    procedure EditingDone; override;
    { The two clickable halves, in client pixels: the same rects the paint uses. }
    function UpButtonRect(APPI: Integer): TRect;
    function DownButtonRect(APPI: Integer): TRect;
    { The editor text, LCL's TCustomEdit.Text (stdctrls.pp:878, public). Reads what the user
      has typed BEFORE it commits; writing a string that parses sets Value, and one that does
      not is kept verbatim so the field can be preset to a non-canonical string (LCL's
      RealSetText does exactly this, include/spinedit.inc:64-67). }
    property Text: TCaption read GetSpinText write SetSpinText;
    property MinValue: Integer read FMinValue write SetMinValue default 0;
    { LCL's DefMaxValue is 0 (spin.pp:37) and Max <= Min means "no limit", so a freshly
      dropped spin edit accepts any integer. Ours shipped 100, which turned the same
      fresh control into a silent 0..100 clamp: type 250, get 100, no diagnostic. The
      clamp rule itself was already LCL's; only the shipped default disagreed.
      BREAKING: a form that relied on the old default now has no ceiling. }
    property MaxValue: Integer read FMaxValue write SetMaxValue default 0;
    property Value: Integer read FValue write SetValue default 0;
    property Increment: Integer read FIncrement write SetIncrement default 1;
    { The other half of the pair LCL keeps ORTHOGONAL to ReadOnly (spin.pp:79, default
      True): False makes the TEXT non-typeable while the arrows keep stepping -- the
      standard way to force a value onto a legal grid (multiples of 5, even numbers)
      without turning the control inert. ReadOnly locks the value entirely (typing and
      stepping); this locks only the keyboard: a character, Backspace, Delete, and the
      clipboard-and-undo keys, which are consumed before the edit sees them. }
    property EditorEnabled: Boolean read FEditorEnabled write SetEditorEnabled default True;
    { Show the field BLANK instead of a number -- the "nothing entered yet / mixed
      selection" state a filter form or a property-inspector row needs, and which 0
      cannot honestly stand in for. LCL: spin.pp:84. Like LCL's, this is a state the
      program sets and real input clears (include/spinedit.inc:76): typing, deleting,
      pasting or stepping puts a number back. }
    property ValueEmpty: Boolean read FValueEmpty write SetValueEmpty default False;
    { The committed Value moved (see DoValueChange). }
    property OnValueChange: TNotifyEvent read FOnValueChange write FOnValueChange;
  end;

  { TTySpinEdit publishes TTyCustomSpinEdit's properties; everything lives in TTyCustomSpinEdit. }
  TTySpinEdit = class(TTyCustomSpinEdit)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property MinValue;
    property MaxValue;
    property Value;
    property Increment;
    property ReadOnly;
    property EditorEnabled;
    property AutoSelect;
    property Alignment;
    property MaxLength;
    property ValueEmpty;
    property TextHint;
    property OnChange;
    property OnValueChange;
    property Align;
    property Anchors;
  end;

function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
{ How far in from the control's edge the field's frame reaches: its border, or its focus ring when
  that reaches further -- DrawFrame strokes the ring INSIDE the bounds, OutlineOffset in and
  OutlineWidth wide. A spin button's hover / pressed fill stops there, so it never covers the
  frame. TySpinFrameInset is in logical px (for corner radii), TySpinFrameInsetPx in device px,
  scaled piece by piece the way DrawFrame scales them. }
function TySpinFrameInset(const AFieldStyle: TTyStyleSet): Integer;
function TySpinFrameInsetPx(APainter: TTyPainter; const AFieldStyle: TTyStyleSet): Integer;

implementation

const
  cSpinRepeatDelayMs = 400;      // the hold before repeating starts: TTyUpDown's
  cSpinRepeatIntervalMs = 100;   // then one step per this: TTyUpDown's and LCL's default

{ TTySpinButtons }

constructor TTySpinButtons.Create(AOwner: TWinControl; AOnStep: TTySpinStepEvent);
begin
  inherited Create;
  FOwner := AOwner;
  FOnStep := AOnStep;
end;

destructor TTySpinButtons.Destroy;
begin
  FreeAndNil(FRepeatTimer);   // first: its OnTimer must never fire into a half-freed control
  inherited Destroy;
end;

procedure TTySpinButtons.SetHot(AValue: Integer);
begin
  if FHot = AValue then Exit;
  FHot := AValue;
  FOwner.Invalidate;
end;

{ Swap in the arrow over a button and put the control's own cursor back on the way out, the
  way TTyHeaderControl swaps in its resize cursor. }
procedure TTySpinButtons.SetArrowCursor(AOn: Boolean);
begin
  if AOn = FCursorOverridden then Exit;
  if AOn then
  begin
    FSavedCursor := FOwner.Cursor;
    FOwner.Cursor := crArrow;
  end
  else
    FOwner.Cursor := FSavedCursor;
  FCursorOverridden := AOn;
end;

procedure TTySpinButtons.StopRepeat;
begin
  if FRepeatTimer <> nil then FRepeatTimer.Enabled := False;
  FRepeatFast := False;
end;

procedure TTySpinButtons.HandleRepeat(Sender: TObject);
begin
  if (FHeld = 0) or (not FOwner.Enabled) then
  begin
    StopRepeat;
    Exit;
  end;
  if not FRepeatFast then
  begin
    FRepeatFast := True;
    FRepeatTimer.Interval := cSpinRepeatIntervalMs;
  end;
  FOnStep(FHeld);
end;

procedure TTySpinButtons.MouseMove(AHit: Integer; AEnabled: Boolean);
begin
  SetArrowCursor(AHit <> 0);
  if AEnabled then SetHot(AHit) else SetHot(0);
end;

function TTySpinButtons.MouseDown(AHit: Integer; AEnabled: Boolean): Boolean;
begin
  Result := AHit <> 0;
  if (not Result) or (not AEnabled) then Exit;
  FHeld := AHit;
  FOnStep(AHit);   // one step at once
  { Then repeat while held -- on a control with a window only, the rule the caret blink timer
    keeps too: one without (a headless test, a control never shown) is pressed by code that may
    never release it, and a timer left running would step into whatever comes next. }
  if FOwner.HandleAllocated then
  begin
    if FRepeatTimer = nil then
    begin
      FRepeatTimer := TTimer.Create(nil);
      FRepeatTimer.Enabled := False;
      FRepeatTimer.OnTimer := @HandleRepeat;
    end;
    FRepeatFast := False;
    FRepeatTimer.Interval := cSpinRepeatDelayMs;
    FRepeatTimer.Enabled := True;
  end;
  FOwner.Invalidate;
end;

procedure TTySpinButtons.MouseUp;
begin
  StopRepeat;
  if FHeld <> 0 then
  begin
    FHeld := 0;
    FOwner.Invalidate;
  end;
end;

procedure TTySpinButtons.MouseLeave;
begin
  MouseUp;
  SetHot(0);
  SetArrowCursor(False);
end;

function TTySpinButtons.StateOf(ADir: Integer): TTyStateSet;
begin
  if (ADir <> 0) and (FHeld = ADir) then
    Result := [tysActive]
  else if (ADir <> 0) and (FHeld = 0) and (FHot = ADir) then
    Result := [tysHover]
  else
    Result := [tysNormal];
end;

function TTySpinButtons.PaintHalf(APainter: TTyPainter; AController: TTyCustomStyleController;
  const AHalf, AInner: TRect; const AFieldStyle: TTyStyleSet; ADir: Integer): TTyColor;
var
  st: TTyStateSet;
  hs: TTyStyleSet;
  fillR: TRect;
  c, fc: TTyCorners;
begin
  Result := AFieldStyle.TextColor;
  st := StateOf(ADir);
  if (st = [tysNormal]) or (not FOwner.Enabled) then Exit;
  hs := AController.Model.ResolveStyle('TyButton', '', st);
  Result := hs.TextColor;
  if not IntersectRect(fillR, AHalf, AInner) then Exit;
  { Square everywhere but the field's own outer corner: the up half meets it top right, the down
    half bottom right, and a square fill there would poke through the rounding. }
  c := TyEffectiveCorners(AFieldStyle);
  fc := TyCorners(0, 0, 0, 0);
  if fillR.Right >= AInner.Right then
  begin
    if fillR.Top <= AInner.Top then fc.TR := c.TR - TySpinFrameInset(AFieldStyle);
    if fillR.Bottom >= AInner.Bottom then fc.BR := c.BR - TySpinFrameInset(AFieldStyle);
    if fc.TR < 0 then fc.TR := 0;
    if fc.BR < 0 then fc.BR := 0;
  end;
  APainter.FillBackground(fillR, hs.Background, fc);
end;

function TySpinFrameInset(const AFieldStyle: TTyStyleSet): Integer;
var
  ring: Integer;
begin
  Result := AFieldStyle.BorderWidth;
  if (tpOutline in AFieldStyle.Present) and (AFieldStyle.OutlineWidth > 0) then
  begin
    ring := AFieldStyle.OutlineOffset + AFieldStyle.OutlineWidth;
    if ring > Result then Result := ring;
  end;
  if Result < 0 then Result := 0;
end;

function TySpinFrameInsetPx(APainter: TTyPainter; const AFieldStyle: TTyStyleSet): Integer;
var
  ring: Integer;
begin
  Result := APainter.Scale(AFieldStyle.BorderWidth);
  if (tpOutline in AFieldStyle.Present) and (AFieldStyle.OutlineWidth > 0) then
  begin
    ring := APainter.Scale(AFieldStyle.OutlineOffset) + APainter.Scale(AFieldStyle.OutlineWidth);
    if ring > Result then Result := ring;
  end;
  if Result < 0 then Result := 0;
end;

function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
var
  BtnW, X0, HalfY: Integer;
begin
  { ABtnWDev>0 = 调用方已把密度令牌解析成设备像素宽,单一来源;
    0(测试等无控件上下文的调用)沿用常量。 }
  if ABtnWDev > 0 then BtnW := ABtnWDev
  else BtnW := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0 := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, ALocal.Top, ALocal.Right, HalfY);
end;

function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
var
  BtnW, X0, HalfY: Integer;
begin
  if ABtnWDev > 0 then BtnW := ABtnWDev
  else BtnW := MulDiv(TyFieldButtonWidth, APPI, 96);
  if BtnW < 1 then BtnW := 1;
  X0 := ALocal.Right - BtnW;
  HalfY := ALocal.Top + (ALocal.Bottom - ALocal.Top) div 2;
  Result := Rect(X0, HalfY, ALocal.Right, ALocal.Bottom);
end;

{ TTyCustomSpinEdit }

constructor TTyCustomSpinEdit.Create(AOwner: TComponent);
begin
  { Before inherited, and freed after it in Destroy: anything the LCL routes here while the
    control is being built or torn down (a paint, a mouse-leave) finds it there. }
  FSpin := TTySpinButtons.Create(Self, @SpinStep);
  inherited Create(AOwner);
  FMinValue := 0;
  FMaxValue := 0;              // == MinValue, i.e. unbounded (LCL DefMaxValue)
  FValue := 0;
  FIncrement := 1;
  FEditorEnabled := True;
  FValueEmpty := False;
  Width := 120;
  AddHandlerOnChange(@HandleTextChange, True);
  SyncTextToValue;
end;

destructor TTyCustomSpinEdit.Destroy;
begin
  if FSpin <> nil then FSpin.MouseUp;   // first: a held button's repeat timer must not fire mid-teardown
  inherited Destroy;
  FreeAndNil(FSpin);
end;

function TTyCustomSpinEdit.GetStyleTypeKey: string;
begin
  Result := 'TySpinEdit';
end;

procedure TTyCustomSpinEdit.DoValueChange;
begin
  if ComponentState * [csLoading, csDestroying] <> [] then Exit;
  if Assigned(FOnValueChange) then FOnValueChange(Self);
end;

procedure TTyCustomSpinEdit.HandleTextChange(Sender: TObject);
begin
  if not FSyncing then FValueEmpty := False;
end;

function TTyCustomSpinEdit.GetLimitedValue(const AValue: Integer): Integer;
begin
  Result := AValue;
  { An empty range (Max <= Min) means "no limit", not "pin everything to Min". With the
    unconditional clamp, MinValue := 0 / MaxValue := 0 -- the way you say "unbounded" --
    forced Value to 0 and nothing could ever be typed in. LCL guards the same way
    (include/spinedit.inc:223 GetLimitedValue: only clamps if FMaxValue > FMinValue). }
  if FMaxValue > FMinValue then
  begin
    if Result < FMinValue then Result := FMinValue;
    if Result > FMaxValue then Result := FMaxValue;
  end;
end;

function TTyCustomSpinEdit.ValueToStr(const AValue: Integer): string;
begin
  Result := IntToStr(GetLimitedValue(AValue));
end;

function TTyCustomSpinEdit.StrToValue(const S: string): Integer;
begin
  // Unparseable text keeps the current value, as LCL's StrToValue does
  // (include/spinedit.inc:240-247), and the clamp runs on the way in.
  Result := GetLimitedValue(StrToIntDef(Trim(S), FValue));
end;

procedure TTyCustomSpinEdit.SetValue(const AValue: Integer);
var
  Clamped: Integer;
  Moved: Boolean;
begin
  Clamped := GetLimitedValue(AValue);
  Moved := FValue <> Clamped;
  FValue := Clamped;
  { A number was written, so there is one to show: an explicit Value write ends the
    blank state, the same way LCL's TextChanged clears FValueEmpty once the value
    really moves (include/spinedit.inc:76). }
  if Moved then FValueEmpty := False;
  SyncTextToValue;            // always keep the text in step with Value; fires OnChange if it moved
  { OnValueChange goes last so the handler sees a settled control: new value AND the
    text already rewritten. }
  if Moved then DoValueChange;
  { A write from code is not the user touching the field. LCL arranges the same reset
    (include/spinedit.inc:163-165 sets the flag that makes Change report Modified=False),
    and the user-driven paths put it straight back. }
  Modified := False;
end;

procedure TTyCustomSpinEdit.StepValue(ADelta: Integer);
begin
  if ReadOnly then Exit;
  { #160: from what is typed, not from the value it has not committed yet -- value 5, type 40,
    Up gives 41. StrToValue falls back to Value when the text is not a number. }
  Value := StrToValue(Text) + ADelta;
  Modified := True;           // the arrows are the user editing, exactly like typing
end;

procedure TTyCustomSpinEdit.SpinStep(ADir: Integer);
begin
  StepValue(ADir * FIncrement);   // StepValue itself refuses while ReadOnly
end;

procedure TTyCustomSpinEdit.SetMinValue(const AValue: Integer);
begin
  if FMinValue = AValue then Exit;
  FMinValue := AValue;
  { Re-run the current value through the SAME guard the Value setter uses, so a range edit
    and a value write can never disagree about what an empty range means -- and so the
    reclamp is announced like any other value move. (LCL: SetMinValue -> UpdateControl ->
    GetLimitedValue + a widgetset text rewrite, which surfaces as Change.) }
  SetValue(FValue);
end;

procedure TTyCustomSpinEdit.SetMaxValue(const AValue: Integer);
begin
  if FMaxValue = AValue then Exit;
  FMaxValue := AValue;
  SetValue(FValue);           // same re-clamp + notify path as SetMinValue
end;

procedure TTyCustomSpinEdit.SetIncrement(const AValue: Integer);
begin
  if FIncrement = AValue then Exit;
  if AValue < 1 then
    FIncrement := 1
  else
    FIncrement := AValue;
end;

procedure TTyCustomSpinEdit.SetEditorEnabled(const AValue: Boolean);
begin
  if FEditorEnabled = AValue then Exit;
  FEditorEnabled := AValue;
end;

procedure TTyCustomSpinEdit.SetValueEmpty(const AValue: Boolean);
begin
  if FValueEmpty = AValue then Exit;
  FValueEmpty := AValue;
  SyncTextToValue;   // shows '' while empty, the number again once it is not
end;

function TTyCustomSpinEdit.GetSpinText: TCaption;
begin
  Result := TTyCustomEdit(Self).Text;
end;

procedure TTyCustomSpinEdit.SetSpinText(const AValue: TCaption);
var
  Parsed: Integer;
begin
  if TryStrToInt(Trim(AValue), Parsed) then
    Value := Parsed          // setter clamps, rewrites the text and notifies
  else
    { Not a number: kept verbatim, as LCL keeps it when TryStrToFloat fails. Value is left
      alone; the next commit re-parses and falls back to it. Written by code, so Modified
      comes back False; HandleTextChange ends ValueEmpty. }
    TTyCustomEdit(Self).Text := AValue;
end;

procedure TTyCustomSpinEdit.RealSetText(const AValue: TCaption);
begin
  if InActionChange then Exit;
  SetSpinText(AValue);
end;

function TTyCustomSpinEdit.TextDiffersFromValue: Boolean;
begin
  if FValueEmpty then Result := Text <> '' else Result := Text <> ValueToStr(FValue);
end;

procedure TTyCustomSpinEdit.SyncTextToValue;
var
  S: string;
begin
  { The single formatting point, so ValueToStr really is the seam a descendant
    overrides. ValueEmpty renders as nothing at all -- that is the whole point of it. }
  if FValueEmpty then S := '' else S := ValueToStr(FValue);
  { A step, a clamp, an Esc revert and a commit that reformats '007' into '7' all arrive
    here, and reach OnChange only when the text really moved. }
  FSyncing := True;
  try
    TTyCustomEdit(Self).Text := S;
  finally
    FSyncing := False;
  end;
end;

procedure TTyCustomSpinEdit.CommitEdit;
var
  WasModified: Boolean;
begin
  { Committing is the user finishing an edit, not the program overwriting the field, so
    the dirty flag has to survive the Value write that deliberately clears it. }
  WasModified := Modified;
  Value := StrToValue(Text);  // setter clamps to [Min,Max], rewrites the text, and notifies
  Modified := WasModified;
end;

procedure TTyCustomSpinEdit.EditingDone;
begin
  CommitEdit;
  inherited EditingDone;
end;

function TTyCustomSpinEdit.NumberPart(const AResidual: string; AAt: Integer;
  const AText: string): string;
var
  i: Integer;
  SignFree: Boolean;
begin
  Result := '';
  { A sign only at the very start, and only one: the residual text holds none, nothing
    goes in before it, and this insertion has not put one in already. }
  SignFree := (AAt = 0) and (Pos('-', AResidual) = 0);
  { Byte by byte: every byte of a multi-byte character is >= $80, so none is accepted and a
    character is dropped whole -- pasting "1,234 px" leaves 1234. }
  for i := 1 to Length(AText) do
    if AText[i] in ['0'..'9'] then
      Result := Result + AText[i]
    else if (AText[i] = '-') and SignFree and (Result = '') then
    begin
      Result := '-';
      SignFree := False;
    end;
end;

function TTyCustomSpinEdit.FilterInsert(const AText: string): string;
begin
  if not FEditorEnabled then Exit('');
  { Called after any selected text is gone: Text and CaretPos are the residual and the
    insertion point. }
  Result := NumberPart(Text, CaretPos, inherited FilterInsert(AText));
end;

function TTyCustomSpinEdit.KeyWouldEditTheText(AKey: Word; AShift: TShiftState): Boolean;
var
  Cmd: Boolean;
begin
  Cmd := (ssCtrl in AShift) or (ssMeta in AShift);
  Result := (AKey = VK_BACK) or (AKey = VK_DELETE)
    or (Cmd and ((AKey = VK_X) or (AKey = VK_V) or (AKey = VK_Z) or (AKey = VK_Y)));
end;

procedure TTyCustomSpinEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  Residual: string;
begin
  { A refused key is turned away HERE, before the edit sees it: TTyEdit deletes the selection
    before it consults FilterInsert, so a letter typed over the selected value would wipe it
    and put nothing in. A locked editor refuses every key the same way. '' is this library's
    spelling of "key rejected". }
  if not FEditorEnabled then
  begin
    UTF8Key := '';
    Exit;
  end;
  Residual := UTF8Copy(Text, 1, SelStart) + UTF8Copy(Text, SelStart + SelLength + 1, MaxInt);
  if (UTF8Key <> '') and (UTF8Key[1] >= ' ') and (NumberPart(Residual, SelStart, UTF8Key) = '') then
  begin
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyCustomSpinEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not IsEnabled then Exit;
  { Before inherited: TTyEdit's handler would already have deleted / pasted / undone by the
    time control came back here. }
  if (not FEditorEnabled) and KeyWouldEditTheText(Key, Shift) then
  begin
    Key := 0;
    Exit;
  end;
  { inherited FIRST, and the keys are read out of Key AFTERWARDS: the application's OnKeyDown
    runs inside it, so a handler that zeroes Key vetoes the step, and one that remaps it is
    obeyed. Enter commits there too, through EditingDone. }
  inherited KeyDown(Key, Shift);
  case Key of
    VK_UP:   begin StepValue(FIncrement);  Key := 0; end;
    VK_DOWN: begin StepValue(-FIncrement); Key := 0; end;
    { #144: Esc goes on to the form's cancel button unless there is a typed value to put back. }
    VK_ESCAPE:
      if TextDiffersFromValue then
      begin
        SyncTextToValue;
        Key := 0;
      end;
  end;
end;

procedure TTyCustomSpinEdit.DoExit;
begin
  inherited DoExit;
  CommitEdit;   // on a dying form it reports nothing (#145)
end;

function TTyCustomSpinEdit.RightReserve(APPI: Integer): Integer;
begin
  { Read the metric live, so the button column tracks the theme's density and lines up with
    a combo box's drop button and the float spin edit's arrows. }
  Result := MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth), APPI, 96);
end;

function TTyCustomSpinEdit.TrailingShowsArrow: Boolean;
begin
  Result := False;
end;

function TTyCustomSpinEdit.UpButtonRect(APPI: Integer): TRect;
var
  Z: TRect;
begin
  Z := TrailingZone(APPI);
  if (Z.Right - Z.Left) <= 0 then Exit(Rect(0, 0, 0, 0));
  { The column runs the field's full height, not the trailing zone's (which stops a padding
    short of the top and bottom): the same halves TTyFloatSpinEdit uses. }
  Result := TySpinUpButtonRect(Rect(Z.Left, 0, Z.Right, ClientHeight), APPI, Z.Right - Z.Left);
end;

function TTyCustomSpinEdit.DownButtonRect(APPI: Integer): TRect;
var
  Z: TRect;
begin
  Z := TrailingZone(APPI);
  if (Z.Right - Z.Left) <= 0 then Exit(Rect(0, 0, 0, 0));
  Result := TySpinDownButtonRect(Rect(Z.Left, 0, Z.Right, ClientHeight), APPI, Z.Right - Z.Left);
end;

procedure TTyCustomSpinEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect;
  const AStyle: TTyStyleSet);
var
  ppi, w, bw: Integer;
  col, upR, dnR, inner: TRect;
  upInk, dnInk: TTyColor;
begin
  w := AZone.Right - AZone.Left;
  if w <= 0 then Exit;
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  { The zone the painter was given, grown back by the padding to the field's full height, so
    the painted halves are the clickable ones (UpButtonRect). }
  col := Rect(AZone.Left, AZone.Top - APainter.Scale(AStyle.Padding.Top), AZone.Right,
    AZone.Bottom + APainter.Scale(AStyle.Padding.Bottom));
  upR := TySpinUpButtonRect(col, ppi, w);
  dnR := TySpinDownButtonRect(col, ppi, w);
  { The hovered or pressed half first, inside the field's frame -- border and focus ring both
    (TTySpinButtons.PaintHalf) -- and its arrow in the ink that state asks for. Filled
    triangles in a SQUARED half at pad 1 (TySquareGlyphBox). }
  bw := TySpinFrameInsetPx(APainter, AStyle);
  inner := Rect(0, col.Top + bw, col.Right - bw, col.Bottom - bw);
  upInk := FSpin.PaintHalf(APainter, ActiveController, upR, inner, AStyle, 1);
  dnInk := FSpin.PaintHalf(APainter, ActiveController, dnR, inner, AStyle, -1);
  TyDrawGlyph(APainter, ActiveController, TySquareGlyphBox(upR), tgTriangleUp, upInk, 2, 1);
  TyDrawGlyph(APainter, ActiveController, TySquareGlyphBox(dnR), tgTriangleDown, dnInk, 2, 1);
end;

function TTyCustomSpinEdit.SpinHitAt(X, Y: Integer): Integer;
var
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if PtInRect(UpButtonRect(ppi), Point(X, Y)) then
    Result := 1
  else if PtInRect(DownButtonRect(ppi), Point(X, Y)) then
    Result := -1
  else
    Result := 0;
end;

function TTyCustomSpinEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if not IsEnabled then Exit(False);
  // The application's OnMouseWheel runs first; if it consumed the notch, stop.
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  { Read-only: report the notch unhandled so an enclosing scroll box still gets it. }
  if ReadOnly then Exit(False);
  if WheelDelta > 0 then
    StepValue(FIncrement)
  else
    StepValue(-FIncrement);
  Result := True;
end;

procedure TTyCustomSpinEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not IsEnabled then Exit;
  { A press on a button steps once and holds it, repeating until the release. ReadOnly locks
    the value: there the press steps nothing but is still the button's. It takes the focus --
    the arrow keys continue the same gesture -- and does not move the caret or the selection. }
  if (Button = mbLeft) and FSpin.MouseDown(SpinHitAt(X, Y), not ReadOnly) then
  begin
    try
      if CanFocus then SetFocus;
    except
      // headless / not yet parented: focus is not available, and not needed
    end;
    Exit;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyCustomSpinEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not IsEnabled then Exit;
  FSpin.MouseMove(SpinHitAt(X, Y), not ReadOnly);
end;

procedure TTyCustomSpinEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FSpin.MouseUp;
end;

procedure TTyCustomSpinEdit.MouseLeave;
begin
  inherited MouseLeave;
  FSpin.MouseLeave;
end;

end.
