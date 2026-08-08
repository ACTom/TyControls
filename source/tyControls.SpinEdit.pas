unit tyControls.SpinEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8,
  ExtCtrls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Animation;
type
  TTySpinEdit = class(TTyCustomControl)
  private
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
  published
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
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
    property OnClick;
  end;

function TySpinUpButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;
function TySpinDownButtonRect(const ALocal: TRect; APPI: Integer; ABtnWDev: Integer = 0): TRect;

implementation

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

{ TTySpinEdit }

constructor TTySpinEdit.Create(AOwner: TComponent);
begin
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

destructor TTySpinEdit.Destroy;
begin
  // Free the timer first so its OnTimer callback can never fire mid-teardown.
  FreeAndNil(FBlinkTimer);
  FMeasureBmp.Free;
  inherited Destroy;
end;

// ---- Blinking caret (Task 10) ----

procedure TTySpinEdit.EnsureBlinkTimer;
begin
  if FBlinkTimer = nil then
  begin
    FBlinkTimer := TTimer.Create(Self);
    FBlinkTimer.Enabled := False;
    FBlinkTimer.Interval := 530;
    FBlinkTimer.OnTimer := @HandleBlink;
  end;
end;

procedure TTySpinEdit.HandleBlink(Sender: TObject);
begin
  Inc(FBlinkElapsedMs, FBlinkTimer.Interval);
  FCaretVisible := TyCaretVisible(FBlinkElapsedMs, FBlinkTimer.Interval);
  Invalidate;
end;

procedure TTySpinEdit.ResetCaretBlink;
begin
  FCaretVisible := True;
  FBlinkElapsedMs := 0;
end;

procedure TTySpinEdit.DoEnter;
begin
  inherited DoEnter;
  ResetCaretBlink;
  if HandleAllocated then
  begin
    EnsureBlinkTimer;
    FBlinkTimer.Enabled := True;
  end;
end;

function TTySpinEdit.GetStyleTypeKey: string;
begin
  Result := 'TySpinEdit';
end;

procedure TTySpinEdit.DoChange;
begin
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTySpinEdit.DoValueChange;
begin
  if Assigned(FOnValueChange) then FOnValueChange(Self);
end;

function TTySpinEdit.GetLimitedValue(const AValue: Integer): Integer;
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

function TTySpinEdit.ValueToStr(const AValue: Integer): string;
begin
  Result := IntToStr(GetLimitedValue(AValue));
end;

function TTySpinEdit.StrToValue(const S: string): Integer;
begin
  // Unparseable text keeps the current value, as LCL's StrToValue does
  // (include/spinedit.inc:240-247), and the clamp runs on the way in.
  Result := GetLimitedValue(StrToIntDef(Trim(S), FValue));
end;

procedure TTySpinEdit.SetValue(const AValue: Integer);
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

procedure TTySpinEdit.StepValue(ADelta: Integer);
begin
  Value := FValue + ADelta;
  FModified := True;          // the arrows are the user editing, exactly like typing
end;

procedure TTySpinEdit.SetMinValue(const AValue: Integer);
begin
  if FMinValue = AValue then Exit;
  FMinValue := AValue;
  { Re-run the current value through the SAME guard the Value setter uses, so a range edit
    and a value write can never disagree about what an empty range means -- and so the
    reclamp is announced like any other value move. (LCL: SetMinValue -> UpdateControl ->
    GetLimitedValue + a widgetset text rewrite, which surfaces as Change.) }
  SetValue(FValue);
end;

procedure TTySpinEdit.SetMaxValue(const AValue: Integer);
begin
  if FMaxValue = AValue then Exit;
  FMaxValue := AValue;
  SetValue(FValue);           // same re-clamp + notify path as SetMinValue
end;

procedure TTySpinEdit.SetIncrement(const AValue: Integer);
begin
  if FIncrement = AValue then Exit;
  if AValue < 1 then
    FIncrement := 1
  else
    FIncrement := AValue;
  Invalidate;
end;

procedure TTySpinEdit.SetReadOnly(const AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  Invalidate;
end;

procedure TTySpinEdit.SetEditorEnabled(const AValue: Boolean);
begin
  if FEditorEnabled = AValue then Exit;
  FEditorEnabled := AValue;
  Invalidate;
end;

procedure TTySpinEdit.SetValueEmpty(const AValue: Boolean);
begin
  if FValueEmpty = AValue then Exit;
  FValueEmpty := AValue;
  SyncBufferToValue;   // renders '' while empty, the number again once it is not
  Invalidate;
end;

procedure TTySpinEdit.SetTextHint(const AValue: TCaption);
begin
  if FTextHint = AValue then Exit;
  FTextHint := AValue;
  Invalidate;
end;

procedure TTySpinEdit.SetCaretPos(const AValue: Integer);
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

function TTySpinEdit.RealGetText: TCaption;
begin
  Result := FEditText;
end;

procedure TTySpinEdit.RealSetText(const AValue: TCaption);
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

procedure TTySpinEdit.CalculatePreferredSize(var PreferredWidth,
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

procedure TTySpinEdit.SetAlignment(const AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  // Alignment shifts the visual text start; the caret follows via AlignOffset.
  Invalidate;
end;

procedure TTySpinEdit.SetMaxLength(const AValue: Integer);
var
  V: Integer;
begin
  V := AValue;
  if V < 0 then V := 0;
  if FMaxLength = V then Exit;
  FMaxLength := V;
  Invalidate;
end;

procedure TTySpinEdit.SyncBufferToValue;
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

function TTySpinEdit.AlignOffset(APPI: Integer): Integer;
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

function TTySpinEdit.CaretPixelX(AIdx, APPI: Integer): Integer;
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

procedure TTySpinEdit.CommitEdit;
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

procedure TTySpinEdit.InsertEditChar(const C: TUTF8Char);
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

procedure TTySpinEdit.EditBackspace;
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

procedure TTySpinEdit.EditDelete;
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

procedure TTySpinEdit.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextR, UpR, DownR, CaretRect: TRect;
  BtnW, EffSize, cx: Integer;
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
    TextR := Rect(R.Left + P.Scale(S.Padding.Left), R.Top + P.Scale(S.Padding.Top),
      R.Right - BtnW, R.Bottom - P.Scale(S.Padding.Bottom));
    EffSize := ResolveFontSize(S);   // same size feeds DrawText and CaretPixelX (caret alignment)
    if (FEditText = '') and (FTextHint <> '') then
      // Same muted ink and same rule as the sibling TTyEdit (Edit.pas:1719-1723).
      P.DrawText(TextR, FTextHint, S.FontName, EffSize, S.FontWeight,
        ActiveController.Model.ResolveStyle('TyTextHint', '', []).TextColor,
        FAlignment, tlCenter, True)
    else
      P.DrawText(TextR, FEditText, S.FontName, EffSize, S.FontWeight,
        S.TextColor, FAlignment, tlCenter, True);
    { Filled triangles in a SQUARED half at pad 1 -- the Windows spin part's shape, and the
      only pad that leaves a readable mark: the raw half is 18 x 14 and the default pad of 4
      eats 9px per axis. See TySquareGlyphBox. (v3/C5 overridable.) }
    TyDrawGlyph(P, ActiveController, TySquareGlyphBox(UpR),   tgTriangleUp,   S.TextColor, 2, 1);
    TyDrawGlyph(P, ActiveController, TySquareGlyphBox(DownR), tgTriangleDown, S.TextColor, 2, 1);
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

procedure TTySpinEdit.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTySpinEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if not Enabled then Exit;
  inherited UTF8KeyPress(UTF8Key);
  InsertEditChar(UTF8Key);
  Invalidate;
end;

procedure TTySpinEdit.KeyDown(var Key: Word; Shift: TShiftState);
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

procedure TTySpinEdit.DoExit;
begin
  inherited DoExit;
  CommitEdit;
  if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
  FCaretVisible := True;
  Invalidate;
end;

function TTySpinEdit.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
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

procedure TTySpinEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    // ReadOnly locks the value: the +/- buttons don't step (focus still allowed).
    if not FReadOnly then
    begin
      if PtInRect(TySpinUpButtonRect(ClientRect, Font.PixelsPerInch,
           MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth),
             Font.PixelsPerInch, 96)), Point(X, Y)) then
        StepValue(FIncrement)
      else if PtInRect(TySpinDownButtonRect(ClientRect, Font.PixelsPerInch,
           MulDiv(ActiveController.Metric('--field-button-width', TyFieldButtonWidth),
             Font.PixelsPerInch, 96)), Point(X, Y)) then
        StepValue(-FIncrement);
    end;
    try
      if CanFocus then SetFocus;
    except
    end;
  end;
end;

end.
