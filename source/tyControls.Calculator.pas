unit tyControls.Calculator;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Math, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.Controller, tyControls.Button;

type
  { A four-function calculator: a right-aligned display strip over a 5x4 keypad of TTyButton
    children (digits as 'ghost' buttons, operators/= as filled). The engine is a plain state
    machine driven by PressKey(cmd) — a single char: '0'..'9', '.', '+','-','*','/', '=',
    'C' (clear all), 'E' (clear entry), 'B' (backspace), 'N' (negate). Value / Display expose
    the result; OnChange fires on any key, OnResult on '='. Parsing/formatting use a fixed '.'
    decimal (locale-independent). Usable standalone or as a drop-down (see TTyCalcEdit). }
  TTyCalculator = class(TTyCustomControl)
  private
    FDisplay: string;
    FAccum: Double;
    FPendingOp: Char;       // #0 = none
    FResetOnNextDigit: Boolean;
    FError: Boolean;
    FButtons: array[0..19] of TTyButton;
    FDisplayHeight: Integer;   // device px, set in Resize
    FOnChange: TNotifyEvent;
    FOnResult: TNotifyEvent;
    function CurVal: Double;
    function FormatVal(AValue: Double): string;
    procedure SetError;
    procedure InputDigit(ACh: Char);
    procedure InputDot;
    procedure InputOp(AOp: Char);
    procedure InputEquals;
    procedure Backspace;
    procedure Negate;
    procedure ButtonClick(Sender: TObject);
    function GetValue: Double;
    procedure SetValue(const AValue: Double);
  protected
    function GetStyleTypeKey: string; override;   // 'TyPanel'
    procedure SetController(AValue: TTyStyleController); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Feed one key (see the class header for the command chars). Public -> unit-testable.
    procedure PressKey(ACmd: Char);
    // Reset to 0 / clear all state.
    procedure Clear;
    // The current display text (e.g. '3.14', or 'Error' on divide-by-zero / overflow).
    property Display: string read FDisplay;
    // True while in the error state (divide-by-zero / overflow); sticky until C / CE / ← clears it.
    property IsError: Boolean read FError;
  published
    // The current numeric value (0 while in the error state). Setting it seeds the display.
    property Value: Double read GetValue write SetValue;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnResult: TNotifyEvent read FOnResult write FOnResult;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
  end;

implementation

const
  { Keypad layout (row-major, 5 rows x 4 cols). Cmd is the PressKey char. }
  CKeys: array[0..19] of record Cap: string; Cmd: Char; Digit: Boolean; end = (
    (Cap: 'C';  Cmd: 'C'; Digit: False), (Cap: 'CE'; Cmd: 'E'; Digit: False), (Cap: '←'; Cmd: 'B'; Digit: False), (Cap: '÷'; Cmd: '/'; Digit: False),
    (Cap: '7';  Cmd: '7'; Digit: True),  (Cap: '8';  Cmd: '8'; Digit: True),  (Cap: '9'; Cmd: '9'; Digit: True),  (Cap: '×'; Cmd: '*'; Digit: False),
    (Cap: '4';  Cmd: '4'; Digit: True),  (Cap: '5';  Cmd: '5'; Digit: True),  (Cap: '6'; Cmd: '6'; Digit: True),  (Cap: '−'; Cmd: '-'; Digit: False),
    (Cap: '1';  Cmd: '1'; Digit: True),  (Cap: '2';  Cmd: '2'; Digit: True),  (Cap: '3'; Cmd: '3'; Digit: True),  (Cap: '+'; Cmd: '+'; Digit: False),
    (Cap: '±';  Cmd: 'N'; Digit: False), (Cap: '0';  Cmd: '0'; Digit: True),  (Cap: '.'; Cmd: '.'; Digit: True),  (Cap: '='; Cmd: '='; Digit: False)
  );

var
  CalcFmt: TFormatSettings;   // fixed '.' decimal, locale-independent

constructor TTyCalculator.Create(AOwner: TComponent);
var
  i: Integer;
  b: TTyButton;
begin
  inherited Create(AOwner);
  TabStop := True;
  FDisplay := '0';
  FPendingOp := #0;
  for i := 0 to High(CKeys) do
  begin
    b := TTyButton.Create(Self);
    b.Parent := Self;
    b.Caption := CKeys[i].Cap;
    b.Tag := i;
    if CKeys[i].Digit then b.StyleClass := 'ghost';   // digits outline, operators filled
    b.OnClick := @ButtonClick;
    FButtons[i] := b;
  end;
  Width := 220;
  Height := 300;
end;

function TTyCalculator.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

procedure TTyCalculator.SetController(AValue: TTyStyleController);
var i: Integer;
begin
  inherited SetController(AValue);
  for i := 0 to High(FButtons) do
    if FButtons[i] <> nil then FButtons[i].Controller := AValue;
end;

function TTyCalculator.CurVal: Double;
begin
  Result := StrToFloatDef(FDisplay, 0, CalcFmt);
end;

function TTyCalculator.FormatVal(AValue: Double): string;
begin
  if IsInfinite(AValue) or IsNaN(AValue) then Exit('Error');
  { Trim trailing zeros / '.' for a clean display. }
  Result := FloatToStrF(AValue, ffGeneral, 15, 0, CalcFmt);
end;

procedure TTyCalculator.SetError;
begin
  FDisplay := 'Error';
  FError := True;
  FPendingOp := #0;
  FResetOnNextDigit := True;
end;

procedure TTyCalculator.InputDigit(ACh: Char);
begin
  if FError then Exit;   // error is sticky: ignore digits until C / CE / ← clears it
  if FResetOnNextDigit then begin FDisplay := ''; FResetOnNextDigit := False; end;
  if (FDisplay = '0') or (FDisplay = '') then
    FDisplay := ACh
  else if FDisplay = '-0' then
    FDisplay := '-' + ACh
  else if Length(FDisplay) < 16 then
    FDisplay := FDisplay + ACh;
end;

procedure TTyCalculator.InputDot;
begin
  if FError then Exit;   // sticky error
  if FResetOnNextDigit then begin FDisplay := '0'; FResetOnNextDigit := False; end;
  if FDisplay = '' then FDisplay := '0';
  if Pos('.', FDisplay) = 0 then FDisplay := FDisplay + '.';
end;

procedure TTyCalculator.InputOp(AOp: Char);
begin
  if FError then Exit;
  if not FResetOnNextDigit then
  begin
    if FPendingOp <> #0 then
    begin
      InputEquals;         // chain: fold the pending op into the accumulator first
      if FError then Exit;
    end
    else
      FAccum := CurVal;
  end
  else if FPendingOp = #0 then
    FAccum := CurVal;      // op pressed right after '=' : start from the shown result
  FPendingOp := AOp;
  FResetOnNextDigit := True;
end;

procedure TTyCalculator.InputEquals;
var b, r: Double;
begin
  if FError or (FPendingOp = #0) then Exit;
  b := CurVal;
  if (FPendingOp = '/') and (b = 0) then begin SetError; Exit; end;
  try
    case FPendingOp of
      '+': r := FAccum + b;
      '-': r := FAccum - b;
      '*': r := FAccum * b;
      '/': r := FAccum / b;
    else
      r := FAccum;
    end;
  except
    on EMathError do begin SetError; Exit; end;   // overflow / invalid op (unmasked FPU raises)
  end;
  if IsInfinite(r) or IsNaN(r) then begin SetError; Exit; end;   // masked FPU: catch +Inf/NaN
  FAccum := r;
  FDisplay := FormatVal(FAccum);
  FPendingOp := #0;
  FResetOnNextDigit := True;
end;

procedure TTyCalculator.Backspace;
begin
  if FError then begin Clear; Exit; end;
  if FResetOnNextDigit then Exit;
  if Length(FDisplay) <= 1 then FDisplay := '0'
  else
  begin
    Delete(FDisplay, Length(FDisplay), 1);
    if (FDisplay = '') or (FDisplay = '-') then FDisplay := '0';
  end;
end;

procedure TTyCalculator.Negate;
begin
  if FError or (FDisplay = '0') or (FDisplay = '') then Exit;
  if (Length(FDisplay) > 0) and (FDisplay[1] = '-') then
    Delete(FDisplay, 1, 1)
  else
    FDisplay := '-' + FDisplay;
end;

procedure TTyCalculator.Clear;
begin
  FDisplay := '0';
  FAccum := 0;
  FPendingOp := #0;
  FResetOnNextDigit := False;
  FError := False;
end;

procedure TTyCalculator.PressKey(ACmd: Char);
begin
  case ACmd of
    '0'..'9': InputDigit(ACmd);
    '.': InputDot;
    '+', '-', '*', '/': InputOp(ACmd);
    '=': InputEquals;
    'C': Clear;
    'E': begin FDisplay := '0'; FResetOnNextDigit := False; FError := False; end;  // clear entry
    'B': Backspace;
    'N': Negate;
  else
    Exit;
  end;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
  if (ACmd = '=') and Assigned(FOnResult) then FOnResult(Self);
end;

function TTyCalculator.GetValue: Double;
begin
  if FError then Result := 0 else Result := CurVal;
end;

procedure TTyCalculator.SetValue(const AValue: Double);
begin
  FDisplay := FormatVal(AValue);
  FAccum := 0;
  FPendingOp := #0;
  FResetOnNextDigit := True;   // a new value: the next digit starts fresh
  FError := False;
  Invalidate;
end;

procedure TTyCalculator.ButtonClick(Sender: TObject);
begin
  if Sender is TControl then
    PressKey(CKeys[TControl(Sender).Tag].Cmd);
end;

procedure TTyCalculator.Resize;
var
  i, r, c, gap, cellW, cellH, x, y: Integer;
begin
  inherited Resize;
  FDisplayHeight := MulDiv(48, Font.PixelsPerInch, 96);
  if FDisplayHeight > ClientHeight div 2 then FDisplayHeight := ClientHeight div 2;
  gap := MulDiv(4, Font.PixelsPerInch, 96);
  cellW := (ClientWidth - gap * 5) div 4;
  cellH := (ClientHeight - FDisplayHeight - gap * 6) div 5;
  if (cellW < 1) or (cellH < 1) then Exit;
  for i := 0 to High(FButtons) do
  begin
    if FButtons[i] = nil then Continue;
    r := i div 4; c := i mod 4;
    x := gap + c * (cellW + gap);
    y := FDisplayHeight + gap + r * (cellH + gap);
    FButtons[i].SetBounds(x, y, cellW, cellH);
  end;
end;

procedure TTyCalculator.Paint;
var
  P: TTyPainter;
  R, dispR: TRect;
  es: TTyStyleSet;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    TyFillParentBg(Self, P, R, CurrentStyle);
    // Display strip — an input-styled band with the right-aligned value in a larger font.
    es := ActiveController.Model.ResolveStyle('TyEdit', StyleClass, []);
    dispR := Rect(P.Scale(4), P.Scale(4), ClientWidth - P.Scale(4),
      FDisplayHeight - P.Scale(2));
    if tpBackground in es.Present then
      P.FillBackground(dispR, es.Background, es.BorderRadius);
    if (tpBorderColor in es.Present) and (es.BorderWidth > 0) then
      P.StrokeBorder(dispR, es.BorderRadius, es.BorderWidth, es.BorderColor);
    P.DrawText(Rect(dispR.Left + P.Scale(8), dispR.Top, dispR.Right - P.Scale(8), dispR.Bottom),
      FDisplay, es.FontName, ResolveFontSize(es) + 6, es.FontWeight, es.TextColor,
      taRightJustify, tlCenter, False);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCalculator.UTF8KeyPress(var UTF8Key: TUTF8Char);
var ch: Char;
begin
  if Length(UTF8Key) = 1 then
  begin
    ch := UTF8Key[1];
    case ch of
      '0'..'9', '.', '+', '-', '*', '/', '=':
        begin PressKey(ch); UTF8Key := ''; Exit; end;
      #13: begin PressKey('='); UTF8Key := ''; Exit; end;   // Enter
    end;
  end;
  inherited UTF8KeyPress(UTF8Key);
end;

procedure TTyCalculator.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_BACK:   begin PressKey('B'); Key := 0; Exit; end;
    VK_ESCAPE: begin PressKey('C'); Key := 0; Exit; end;
    VK_RETURN: begin PressKey('='); Key := 0; Exit; end;
  end;
  inherited KeyDown(Key, Shift);
end;

initialization
  CalcFmt := DefaultFormatSettings;
  CalcFmt.DecimalSeparator := '.';
  CalcFmt.ThousandSeparator := #0;
end.
