unit tyControls.SpinEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8,
  ExtCtrls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Animation;
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

  TTyCustomSpinEdit = class(TTyCustomControl)
  private
    FSpin: TTySpinButtons;
    FMinValue, FMaxValue, FValue, FIncrement: Integer;
    FOnChange: TNotifyEvent;
    FOnValueChange: TNotifyEvent;
    FReadOnly: Boolean;
    FEditorEnabled: Boolean;
    FAlignment: TAlignment;
    FMaxLength: Integer;
    FModified: Boolean;
    FValueEmpty: Boolean;
    FTextHint: TCaption;
    procedure SetMinValue(const AValue: Integer);
    procedure SetMaxValue(const AValue: Integer);
    procedure SetValue(const AValue: Integer);
    procedure SetIncrement(const AValue: Integer);
    procedure SetReadOnly(const AValue: Boolean);
    procedure SetEditorEnabled(const AValue: Boolean);
    procedure SetAlignment(const AValue: TAlignment);
    procedure SetMaxLength(const AValue: Integer);
    procedure SetValueEmpty(const AValue: Boolean);
    procedure SetTextHint(const AValue: TCaption);
    procedure SetCaretPos(const AValue: Integer);
    { The user moved the value with the arrows/wheel/buttons. Separate from a plain
      Value write so Modified can tell "the user did this" from "the code did this" --
      both land in the same setter. }
    procedure StepValue(ADelta: Integer);
    procedure SpinStep(ADir: Integer);
    function SpinHitAt(X, Y: Integer): Integer;
  protected
    // Inline edit buffer (lightweight, no selection/clipboard). Protected so
    // headless access subclasses (tests) can reach the buffer + helpers.
    FEditText: string;
    FCaret: Integer;      // codepoint index 0..UTF8Length(FEditText)
    FMeasureBmp: TBGRABitmap;  // lazy; used only for text measurement
    // Blinking caret (Task 10). FCaretVisible defaults True; the timer is created
    // lazily and started ONLY when HandleAllocated, so headless tests never blink
    // and the static-caret pixel tests stay deterministic.
    FCaretVisible: Boolean;
    FBlinkTimer: TTimer;
    FBlinkElapsedMs: Integer;
    procedure EnsureBlinkTimer;
    procedure HandleBlink(Sender: TObject);
    procedure ResetCaretBlink;
    procedure DoEnter; override;
    { OnChange is the EDIT's change notification, as it is on every LCL edit-derived
      control (TCustomEdit.Change, customedit.inc:622, reached from TextChanged on each
      keystroke -- and TSpinEdit IS a TCustomEdit). It therefore fires for EVERY buffer
      mutation: a typed digit, a delete, a spin step, a clamp, a programmatic Value write.
      Firing it only for a committed value move -- as this control used to -- left live
      validation and "enable OK while typing" handlers dead for the whole time the user
      was typing, because a half-typed number may never commit at all. }
    procedure DoChange; virtual;
    { OnValueChange is the other half: the committed integer actually moved. Anything that
      wants "the number is now N" (a preview, a model write-back) hangs here and is not
      woken by every keystroke. }
    procedure DoValueChange; virtual;
    // Edit-buffer helpers
    procedure SyncBufferToValue;
    procedure CommitEdit;
    procedure InsertEditChar(const C: TUTF8Char);
    procedure EditBackspace;
    procedure EditDelete;
    function CaretPixelX(AIdx, APPI: Integer): Integer;
    function AlignOffset(APPI: Integer): Integer;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
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
    { Text/Caption read straight out of the edit buffer, as they do on every LCL edit
      (TCustomFloatSpinEdit routes both through RealGetText/RealSetText,
      include/spinedit.inc:52,60). Before this, the typed-but-uncommitted string was
      protected state no host could see. }
    function RealGetText: TCaption; override;
    procedure RealSetText(const AValue: TCaption); override;
    { AutoSize is republished on the base class already; without this it had nothing to
      ask. Height only -- the digits' height is a font/theme decision that a skin with a
      bigger font or fatter padding must be able to push out, while the width is the
      form author's. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
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
    { The raw editor text, LCL's TCustomEdit.Text (stdctrls.pp:878, public). Reads what
      the user has typed BEFORE it commits; writing a string that parses sets Value,
      and one that does not is kept verbatim so the field can be preset to a
      non-canonical string (LCL's RealSetText does exactly this). }
    property Text;
    { Caret index in codepoints, matching the sibling TTyEdit.CaretPos. LCL's is a
      TPoint because TCustomEdit spans a memo too; a single-line integer field has no
      second axis, so this deliberately differs -- it will not compile against ported
      code, which is the loud failure, not the silent one. }
    property CaretPos: Integer read FCaret write SetCaretPos;
    { Dirty flag: True once the USER has changed the field (typed, deleted, or stepped
      with the arrows/wheel/buttons), False again after a programmatic Value or Text
      write. LCL keeps the same split -- SetValue arranges for Modified to come back
      False in the resulting OnChange (include/spinedit.inc:38-42,163-165) -- so a host
      can drive enable-Save / prompt-on-close off it. }
    property Modified: Boolean read FModified write FModified;
    property TabStop default True;
    property MinValue: Integer read FMinValue write SetMinValue default 0;
    { LCL's DefMaxValue is 0 (spin.pp:37) and Max <= Min means "no limit", so a freshly
      dropped spin edit accepts any integer. Ours shipped 100, which turned the same
      fresh control into a silent 0..100 clamp: type 250, get 100, no diagnostic. The
      clamp rule itself was already LCL's; only the shipped default disagreed.
      BREAKING: a form that relied on the old default now has no ceiling. }
    property MaxValue: Integer read FMaxValue write SetMaxValue default 0;
    property Value: Integer read FValue write SetValue default 0;
    property Increment: Integer read FIncrement write SetIncrement default 1;
    // ReadOnly locks the value entirely (LCL TSpinEdit semantics): it blocks
    // both inline text editing AND +/- stepping (buttons/arrows/wheel).
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    { The other half of the pair LCL keeps ORTHOGONAL to ReadOnly (spin.pp:79, default
      True): False makes the TEXT non-typeable while the arrows keep stepping -- the
      standard way to force a value onto a legal grid (multiples of 5, even numbers)
      without turning the control inert. ReadOnly locks the value entirely; this locks
      only the keyboard. Both blocking typing is the same on the Win32 widgetset
      (win32wsspin.pp:409 ORs them into EM_SETREADONLY). }
    property EditorEnabled: Boolean read FEditorEnabled write SetEditorEnabled default True;
    // Default taLeftJustify == the alignment RenderTo used before this property
    // existed, so existing pixel tests stay unchanged.
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    // 0 == unlimited; caps the inline edit buffer length in codepoints on insert.
    property MaxLength: Integer read FMaxLength write SetMaxLength default 0;
    { Show the field BLANK instead of a number -- the "nothing entered yet / mixed
      selection" state a filter form or a property-inspector row needs, and which 0
      cannot honestly stand in for. LCL: spin.pp:84. Like LCL's, this is a state the
      program sets and real input clears (include/spinedit.inc:76): typing a digit,
      deleting one, or stepping puts a number back. }
    property ValueEmpty: Boolean read FValueEmpty write SetValueEmpty default False;
    { Placeholder drawn in the muted 'TyTextHint' ink while the field is blank -- the
      same token and the same paint rule the sibling TTyEdit already uses. LCL:
      TCustomEdit.TextHint, stdctrls.pp:879. }
    property TextHint: TCaption read FTextHint write SetTextHint;
    { Text changed (see DoChange): every keystroke, delete, step, clamp and Value write. }
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
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
    property ChildSizing;
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
  TabStop := True;
  Cursor := crIBeam;
  FMinValue := 0;
  FMaxValue := 0;              // == MinValue, i.e. unbounded (LCL DefMaxValue)
  FValue := 0;
  FIncrement := 1;
  FReadOnly := False;
  FEditorEnabled := True;
  FAlignment := taLeftJustify;
  FMaxLength := 0;
  FModified := False;
  FValueEmpty := False;
  Width := 120;
  Height := TyDensityHeight(ActiveController, 28);
  FCaretVisible := True;       // solid caret until a real timer toggles it
  FBlinkTimer := nil;          // lazy: created only when HandleAllocated
  FBlinkElapsedMs := 0;
  SyncBufferToValue;
end;

destructor TTyCustomSpinEdit.Destroy;
begin
  // Stop the timers first so their OnTimer callbacks can never fire mid-teardown.
  if FSpin <> nil then FSpin.MouseUp;   // ends a held press, and the repeat timer with it
  FreeAndNil(FBlinkTimer);
  FMeasureBmp.Free;
  inherited Destroy;
  FreeAndNil(FSpin);
end;

// ---- Blinking caret (Task 10) ----

procedure TTyCustomSpinEdit.EnsureBlinkTimer;
begin
  if FBlinkTimer = nil then
  begin
    FBlinkTimer := TTimer.Create(Self);
    FBlinkTimer.Enabled := False;
    FBlinkTimer.Interval := 530;
    FBlinkTimer.OnTimer := @HandleBlink;
  end;
end;

procedure TTyCustomSpinEdit.HandleBlink(Sender: TObject);
begin
  Inc(FBlinkElapsedMs, FBlinkTimer.Interval);
  FCaretVisible := TyCaretVisible(FBlinkElapsedMs, FBlinkTimer.Interval);
  Invalidate;
end;

procedure TTyCustomSpinEdit.ResetCaretBlink;
begin
  FCaretVisible := True;
  FBlinkElapsedMs := 0;
end;

procedure TTyCustomSpinEdit.DoEnter;
begin
  inherited DoEnter;
  ResetCaretBlink;
  if HandleAllocated then
  begin
    EnsureBlinkTimer;
    FBlinkTimer.Enabled := True;
  end;
end;

function TTyCustomSpinEdit.GetStyleTypeKey: string;
begin
  Result := 'TySpinEdit';
end;

procedure TTyCustomSpinEdit.DoChange;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyCustomSpinEdit.DoValueChange;
begin
  if Assigned(FOnValueChange) then FOnValueChange(Self);
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
  SyncBufferToValue;          // always keep buffer in step with Value; fires OnChange if the text moved
  { OnValueChange goes last so the handler sees a settled control: new value AND the
    buffer already rewritten. }
  if Moved then DoValueChange;
  { A write from code is not the user touching the field. LCL arranges the same reset
    (include/spinedit.inc:163-165 sets the flag that makes Change report Modified=False),
    and the user-driven paths below put it straight back. }
  FModified := False;
  Invalidate;
end;

procedure TTyCustomSpinEdit.StepValue(ADelta: Integer);
begin
  Value := FValue + ADelta;
  FModified := True;          // the arrows are the user editing, exactly like typing
end;

procedure TTyCustomSpinEdit.SpinStep(ADir: Integer);
begin
  { A held button repeats from a timer, and ReadOnly may have been switched on meanwhile;
    every other route checks it before calling StepValue, so this one does too. }
  if FReadOnly then Exit;
  StepValue(ADir * FIncrement);
end;

function TTyCustomSpinEdit.SpinHitAt(X, Y: Integer): Integer;
var
  ppi, bw: Integer;
begin
  ppi := Font.PixelsPerInch;
  bw := MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth), ppi, 96);
  if PtInRect(TySpinUpButtonRect(ClientRect, ppi, bw), Point(X, Y)) then
    Result := 1
  else if PtInRect(TySpinDownButtonRect(ClientRect, ppi, bw), Point(X, Y)) then
    Result := -1
  else
    Result := 0;
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
  Invalidate;
end;

procedure TTyCustomSpinEdit.SetReadOnly(const AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  Invalidate;
end;

procedure TTyCustomSpinEdit.SetEditorEnabled(const AValue: Boolean);
begin
  if FEditorEnabled = AValue then Exit;
  FEditorEnabled := AValue;
  Invalidate;
end;

procedure TTyCustomSpinEdit.SetValueEmpty(const AValue: Boolean);
begin
  if FValueEmpty = AValue then Exit;
  FValueEmpty := AValue;
  SyncBufferToValue;   // renders '' while empty, the number again once it is not
  Invalidate;
end;

procedure TTyCustomSpinEdit.SetTextHint(const AValue: TCaption);
begin
  if FTextHint = AValue then Exit;
  FTextHint := AValue;
  Invalidate;
end;

procedure TTyCustomSpinEdit.SetCaretPos(const AValue: Integer);
var
  V, L: Integer;
begin
  L := UTF8Length(FEditText);
  V := AValue;
  if V < 0 then V := 0;
  if V > L then V := L;
  if FCaret = V then Exit;
  FCaret := V;
  ResetCaretBlink;
  Invalidate;
end;

function TTyCustomSpinEdit.RealGetText: TCaption;
begin
  Result := FEditText;
end;

procedure TTyCustomSpinEdit.RealSetText(const AValue: TCaption);
var
  Parsed: Integer;
begin
  if TryStrToInt(Trim(AValue), Parsed) then
    Value := Parsed          // setter clamps, rewrites the buffer and notifies
  else
  begin
    { Not a number: keep it verbatim so a host can preset a non-canonical string, which
      is what LCL does when TryStrToFloat fails (include/spinedit.inc:64-67). Value is
      left alone; the next commit re-parses and falls back to it. }
    if FEditText = AValue then Exit;
    FEditText := AValue;
    FCaret := UTF8Length(FEditText);
    FValueEmpty := False;
    FModified := False;      // written by code, not by the user
    ResetCaretBlink;
    DoChange;
    Invalidate;
  end;
end;

procedure TTyCustomSpinEdit.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi: Integer;
begin
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  if FMeasureBmp = nil then FMeasureBmp := TBGRABitmap.Create(1, 1);
  TyConfigureTextFont(FMeasureBmp, S.FontName, ResolveFontSize(S), S.FontWeight, ppi);
  { WIDTH 0 == "no preference on this axis" (LCL): the form author owns how wide a
    number field is. The height is the one a skin can push out from under us -- the
    same digits + padding + border RenderTo lays out. }
  PreferredWidth := 0;
  PreferredHeight := FMeasureBmp.TextSize('0').cy
    + MulDiv(S.Padding.Top + S.Padding.Bottom, ppi, 96)
    + 2 * MulDiv(S.BorderWidth, ppi, 96);
  if PreferredHeight < 1 then PreferredHeight := 1;
end;

procedure TTyCustomSpinEdit.SetAlignment(const AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  // Alignment shifts the visual text start; the caret follows via AlignOffset.
  Invalidate;
end;

procedure TTyCustomSpinEdit.SetMaxLength(const AValue: Integer);
var
  V: Integer;
begin
  V := AValue;
  if V < 0 then V := 0;
  if FMaxLength = V then Exit;
  FMaxLength := V;
  Invalidate;
end;

procedure TTyCustomSpinEdit.SyncBufferToValue;
var
  Old: string;
begin
  Old := FEditText;
  { The single formatting point, so ValueToStr really is the seam a descendant
    overrides. ValueEmpty renders as nothing at all -- that is the whole point of it. }
  if FValueEmpty then FEditText := '' else FEditText := ValueToStr(FValue);
  FCaret := UTF8Length(FEditText);
  ResetCaretBlink;
  { Rewriting the buffer IS a text change, so it reaches OnChange from here: a step, a
    clamp, an Esc revert and a commit that reformats '007' into '7' all arrive this way,
    and only when the text really moved (re-writing the same value stays silent). }
  if FEditText <> Old then DoChange;
end;

function TTyCustomSpinEdit.AlignOffset(APPI: Integer): Integer;
{ Horizontal shift applied to the text (and caret) so the caret tracks the
  DrawText H-alignment. 0 for taLeftJustify, or the slack inside the text rect
  for center/right. Mirrors RenderTo's TextR (Padding.Left .. Right-BtnW-Padding.Right). }
var
  S: TTyStyleSet;
  EffSize, StartX, RightPad, BtnW, ViewWidth, TextWidth, Slack: Integer;
begin
  Result := 0;
  if FAlignment = taLeftJustify then Exit;
  if ClientWidth <= 0 then Exit;
  S := CurrentStyle;
  EffSize := ResolveFontSize(S);
  StartX := MulDiv(S.Padding.Left, APPI, 96);
  RightPad := MulDiv(S.Padding.Right, APPI, 96);
  BtnW := MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth), APPI, 96);
  ViewWidth := ClientWidth - BtnW - StartX - RightPad;
  if ViewWidth <= 0 then Exit;
  TextWidth := 0;
  if FEditText <> '' then
  begin
    if FMeasureBmp = nil then FMeasureBmp := TBGRABitmap.Create(1, 1);
    TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
    TextWidth := FMeasureBmp.TextSize(FEditText).cx;
  end;
  Slack := ViewWidth - TextWidth;
  if Slack <= 0 then Exit;
  case FAlignment of
    taRightJustify: Result := Slack;
    taCenter:       Result := Slack div 2;
  end;
end;

function TTyCustomSpinEdit.CaretPixelX(AIdx, APPI: Integer): Integer;
var
  S: TTyStyleSet;
  EffSize: Integer;
begin
  S := CurrentStyle;
  EffSize := ResolveFontSize(S);   // theme font-size > Font.Size > 9; shared with RenderTo so caret stays aligned
  Result := MulDiv(S.Padding.Left, APPI, 96) + AlignOffset(APPI);   // local-left text start + H-align shift
  if (FEditText = '') or (AIdx <= 0) then Exit;
  if AIdx > UTF8Length(FEditText) then AIdx := UTF8Length(FEditText);
  if FMeasureBmp = nil then FMeasureBmp := TBGRABitmap.Create(1, 1);
  TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
  Result := Result + FMeasureBmp.TextSize(UTF8Copy(FEditText, 1, AIdx)).cx;
end;

procedure TTyCustomSpinEdit.CommitEdit;
var
  v: Integer;
  WasModified: Boolean;
begin
  { Committing is the user finishing an edit, not the program overwriting the field, so
    the dirty flag has to survive the Value write that deliberately clears it. }
  WasModified := FModified;
  v := StrToValue(FEditText);
  Value := v;                 // setter clamps to [Min,Max], rewrites the buffer, and notifies
  SyncBufferToValue;          // resync to the (possibly clamped) value
  FModified := WasModified;
  Invalidate;
end;

procedure TTyCustomSpinEdit.InsertEditChar(const C: TUTF8Char);
var
  Before, After: string;
  L: Integer;
begin
  // ReadOnly locks the value; EditorEnabled=False locks only the keyboard.
  if FReadOnly or (not FEditorEnabled) then Exit;
  // Accept digits 0..9 always; accept '-' only at position 0 and when no '-' yet.
  if C = '' then Exit;
  if not ( ((Length(C)=1) and (C[1] in ['0'..'9']))
           or ((C = '-') and (FCaret = 0) and (Pos('-', FEditText) = 0)) ) then Exit;
  L := UTF8Length(FEditText);
  // MaxLength (0 = unlimited): cap the buffer length in codepoints on insert.
  if (FMaxLength > 0) and (L >= FMaxLength) then Exit;
  if FCaret > L then FCaret := L;
  Before := UTF8Copy(FEditText, 1, FCaret);
  After  := UTF8Copy(FEditText, FCaret + 1, L - FCaret);
  FEditText := Before + C + After;
  Inc(FCaret);
  FValueEmpty := False;       // real input ends the blank state (LCL: spinedit.inc:76)
  FModified := True;
  ResetCaretBlink;
  DoChange;                   // a typed character is a text change (the path that used to be silent)
end;

procedure TTyCustomSpinEdit.EditBackspace;
var
  Before, After: string;
  L: Integer;
begin
  if FReadOnly or (not FEditorEnabled) then Exit;
  if FCaret = 0 then Exit;
  L := UTF8Length(FEditText);
  Before := UTF8Copy(FEditText, 1, FCaret - 1);
  After  := UTF8Copy(FEditText, FCaret + 1, L - FCaret);
  FEditText := Before + After;
  Dec(FCaret);
  FValueEmpty := False;
  FModified := True;
  ResetCaretBlink;
  DoChange;                   // a deleted character is a text change too
end;

procedure TTyCustomSpinEdit.EditDelete;
var
  Before, After: string;
  L: Integer;
begin
  if FReadOnly or (not FEditorEnabled) then Exit;
  L := UTF8Length(FEditText);
  if FCaret >= L then Exit;
  Before := UTF8Copy(FEditText, 1, FCaret);
  After  := UTF8Copy(FEditText, FCaret + 2, L - FCaret - 1);
  FEditText := Before + After;
  FValueEmpty := False;
  FModified := True;
  ResetCaretBlink;
  DoChange;
end;

procedure TTyCustomSpinEdit.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextR, UpR, DownR, CaretRect, Inner: TRect;
  BtnW, EffSize, cx, bw: Integer;
  UpInk, DownInk: TTyColor;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    BtnW := P.Scale(ActiveController.Metric('--field-button-width', TyFieldButtonWidth));
    { 按钮宽单一来源:上下键矩形与文字区让位用的是同一个 BtnW —— 否则
      现代密度下绘制位置和可点区域会错位。 }
    UpR := TySpinUpButtonRect(R, APPI, BtnW);
    DownR := TySpinDownButtonRect(R, APPI, BtnW);
    { Right edge subtracts Padding.Right so right/center-aligned text keeps a gap from the
      spin buttons -- AND so the text's right edge matches CaretPixelX's ViewWidth (which
      already subtracts RightPad). Without this the caret ends RightPad px short of the last
      glyph and blinks ON the digit under right/center alignment (left is unaffected: no slack). }
    TextR := Rect(R.Left + P.Scale(S.Padding.Left), R.Top + P.Scale(S.Padding.Top),
      R.Right - BtnW - P.Scale(S.Padding.Right), R.Bottom - P.Scale(S.Padding.Bottom));
    EffSize := ResolveFontSize(S);   // same size feeds DrawText and CaretPixelX (caret alignment)
    if (FEditText = '') and (FTextHint <> '') then
      // Same muted ink and same rule as the sibling TTyEdit (Edit.pas:1719-1723).
      P.DrawText(TextR, FTextHint, S.FontName, EffSize, S.FontWeight,
        ActiveController.Model.ResolveStyle('TyTextHint', '', []).TextColor,
        FAlignment, tlCenter, True)
    else
      P.DrawText(TextR, FEditText, S.FontName, EffSize, S.FontWeight,
        S.TextColor, FAlignment, tlCenter, True);
    { The hovered or pressed half first, inside the field's frame -- border and focus ring both
      (TTySpinButtons.PaintHalf) -- and its arrow in the ink that state asks for. }
    bw := TySpinFrameInsetPx(P, S);
    Inner := Rect(R.Left + bw, R.Top + bw, R.Right - bw, R.Bottom - bw);
    UpInk := FSpin.PaintHalf(P, ActiveController, UpR, Inner, S, 1);
    DownInk := FSpin.PaintHalf(P, ActiveController, DownR, Inner, S, -1);
    { Filled triangles in a SQUARED half at pad 1 -- the Windows spin part's shape, and the
      only pad that leaves a readable mark: the raw half is 18 x 14 and the default pad of 4
      eats 9px per axis. See TySquareGlyphBox. (v3/C5 overridable.) }
    TyDrawGlyph(P, ActiveController, TySquareGlyphBox(UpR),   tgTriangleUp,   UpInk, 2, 1);
    TyDrawGlyph(P, ActiveController, TySquareGlyphBox(DownR), tgTriangleDown, DownInk, 2, 1);
    if Focused and FCaretVisible then
    begin
      cx := CaretPixelX(FCaret, APPI);
      CaretRect := Rect(cx, TextR.Top + P.Scale(2), cx + P.Scale(1), TextR.Bottom - P.Scale(2));
      P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomSpinEdit.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyCustomSpinEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if not Enabled then Exit;
  inherited UTF8KeyPress(UTF8Key);
  InsertEditChar(UTF8Key);
  Invalidate;
end;

procedure TTyCustomSpinEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  case Key of
    VK_UP:
      begin
        if not FReadOnly then StepValue(FIncrement);
        Key := 0;
      end;
    VK_DOWN:
      begin
        if not FReadOnly then StepValue(-FIncrement);
        Key := 0;
      end;
    VK_RETURN: begin CommitEdit; Key := 0; end;
    VK_ESCAPE: begin SyncBufferToValue; Invalidate; Key := 0; end;
    VK_BACK:   begin EditBackspace; Invalidate; Key := 0; end;
    VK_DELETE: begin EditDelete; Invalidate; Key := 0; end;
    VK_LEFT:   begin if FCaret > 0 then Dec(FCaret); ResetCaretBlink; Invalidate; Key := 0; end;
    VK_RIGHT:  begin if FCaret < UTF8Length(FEditText) then Inc(FCaret); ResetCaretBlink; Invalidate; Key := 0; end;
    VK_HOME:   begin FCaret := 0; ResetCaretBlink; Invalidate; Key := 0; end;
    VK_END:    begin FCaret := UTF8Length(FEditText); ResetCaretBlink; Invalidate; Key := 0; end;
  end;
end;

procedure TTyCustomSpinEdit.DoExit;
begin
  inherited DoExit;
  CommitEdit;
  if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
  FCaretVisible := True;
  Invalidate;
end;

function TTyCustomSpinEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if not Enabled then Exit(False);
  // Let the user's OnMouseWheel handler run first; if it consumes the event, stop.
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then
  begin
    Result := True;
    Exit;
  end;
  // ReadOnly locks the value: don't step on the wheel.
  if FReadOnly then Exit(False);
  if WheelDelta > 0 then
    StepValue(FIncrement)
  else
    StepValue(-FIncrement);
  Result := True;
end;

procedure TTyCustomSpinEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    { A press on a button steps once and holds it, repeating until the release. ReadOnly locks
      the value: there the buttons do not step, and the press only takes focus. }
    FSpin.MouseDown(SpinHitAt(X, Y), not FReadOnly);
    try
      if CanFocus then SetFocus;
    except
    end;
  end;
end;

procedure TTyCustomSpinEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not Enabled then Exit;
  FSpin.MouseMove(SpinHitAt(X, Y), not FReadOnly);
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
