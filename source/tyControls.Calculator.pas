unit tyControls.Calculator;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Math, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.Controller, tyControls.Button;

type
  { An EXPRESSION calculator: the user builds a full expression (e.g. '333*222+5'), shown on the
    top display line for proof-reading; '=' evaluates it with PROPER OPERATOR PRECEDENCE (× ÷
    before + −) via TyEvalExpr. The large bottom line shows the live value / result. Driven by
    PressKey(cmd) — one char: '0'..'9', '.', '+','-','*','/', '=', 'C' (clear), 'E' (clear entry),
    'B' (backspace), 'N' (negate the trailing number). Value / Display / Expression expose the
    state; OnChange on any key, OnResult on '='. Locale-independent '.' parsing. The keypad is
    TTyButton children; usable standalone or as a drop-down (see TTyCalcEdit). }
  TTyCalculator = class(TTyCustomControl)
  private
    FExpr: string;          // the expression being built, e.g. '333*222'
    FResult: string;        // last evaluated result text (shown after '=')
    FJustEval: Boolean;     // True right after '='
    FError: Boolean;
    FButtons: array[0..19] of TTyButton;
    FDisplayHeight: Integer;   // device px, set in Resize
    FOnChange: TNotifyEvent;
    FOnResult: TNotifyEvent;
    function FormatVal(AValue: Double): string;
    function BottomText: string;                 // the large line: value / result / 'Error'
    function TrailingNumberStart: Integer;       // 1-based index where the trailing number begins
    procedure InputDigit(ACh: Char);
    procedure InputDot;
    procedure InputOp(AOp: Char);
    procedure InputEquals;
    procedure Backspace;
    procedure ClearEntry;
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
    procedure PressKey(ACmd: Char);
    procedure Clear;
    // The large-line text: the current value / result, or 'Error'.
    property Display: string read BottomText;
    // The full expression being built (the small top line).
    property Expression: string read FExpr;
    // True while in the error state (divide-by-zero / overflow / malformed); sticky until C / CE / ←.
    property IsError: Boolean read FError;
  published
    // The current numeric value (0 while in the error state). Setting it seeds the expression.
    property Value: Double read GetValue write SetValue;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnResult: TNotifyEvent read FOnResult write FOnResult;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
  end;

{ Pure expression evaluator for + − × ÷ with precedence + unary minus (locale-independent '.').
  Returns False on empty / malformed / divide-by-zero / overflow / non-finite. Headless-testable. }
function TyEvalExpr(const AExpr: string; out AResult: Double): Boolean;

implementation

const
  { Keypad layout (row-major, 5 rows x 4 cols). Cmd is the PressKey char. Kind: 0=digit,
    1=operator (+ − × ÷ =), 2=utility (C CE ← ±). }
  CKeys: array[0..19] of record Cap: string; Cmd: Char; Kind: Integer; end = (
    (Cap: 'C';  Cmd: 'C'; Kind: 2), (Cap: 'CE'; Cmd: 'E'; Kind: 2), (Cap: '←'; Cmd: 'B'; Kind: 2), (Cap: '÷'; Cmd: '/'; Kind: 1),
    (Cap: '7';  Cmd: '7'; Kind: 0), (Cap: '8';  Cmd: '8'; Kind: 0), (Cap: '9'; Cmd: '9'; Kind: 0), (Cap: '×'; Cmd: '*'; Kind: 1),
    (Cap: '4';  Cmd: '4'; Kind: 0), (Cap: '5';  Cmd: '5'; Kind: 0), (Cap: '6'; Cmd: '6'; Kind: 0), (Cap: '−'; Cmd: '-'; Kind: 1),
    (Cap: '1';  Cmd: '1'; Kind: 0), (Cap: '2';  Cmd: '2'; Kind: 0), (Cap: '3'; Cmd: '3'; Kind: 0), (Cap: '+'; Cmd: '+'; Kind: 1),
    (Cap: '±';  Cmd: 'N'; Kind: 2), (Cap: '0';  Cmd: '0'; Kind: 0), (Cap: '.'; Cmd: '.'; Kind: 0), (Cap: '='; Cmd: '='; Kind: 1)
  );

var
  CalcFmt: TFormatSettings;   // fixed '.' decimal, locale-independent

function TyEvalExpr(const AExpr: string; out AResult: Double): Boolean;
var
  s: string;
  n, i, numStart, expStart: Integer;
  c: Char;
  numStk: array of Double;
  opStk: array of Char;
  expectOperand, ok, hadDigit: Boolean;
  num: Double;

  function Prec(op: Char): Integer;
  begin
    if (op = '*') or (op = '/') then Result := 2 else Result := 1;
  end;

  procedure PushNum(v: Double); begin SetLength(numStk, Length(numStk) + 1); numStk[High(numStk)] := v; end;
  procedure PushOp(op: Char);   begin SetLength(opStk, Length(opStk) + 1);   opStk[High(opStk)] := op; end;

  function ApplyTop: Boolean;   // pop op + 2 numbers, push result; False on error
  var a, b, r: Double; op: Char;
  begin
    Result := False;
    if (Length(numStk) < 2) or (Length(opStk) < 1) then Exit;
    op := opStk[High(opStk)]; SetLength(opStk, Length(opStk) - 1);
    b := numStk[High(numStk)]; SetLength(numStk, Length(numStk) - 1);
    a := numStk[High(numStk)]; SetLength(numStk, Length(numStk) - 1);
    if (op = '/') and (b = 0) then Exit;
    try
      case op of
        '+': r := a + b;
        '-': r := a - b;
        '*': r := a * b;
        '/': r := a / b;
      else r := a;
      end;
    except
      on EMathError do Exit;   // overflow / invalid op (unmasked FPU raises)
    end;
    if IsInfinite(r) or IsNaN(r) then Exit;
    PushNum(r);
    Result := True;
  end;

begin
  Result := False;
  AResult := 0;
  s := StringReplace(AExpr, ' ', '', [rfReplaceAll]);
  n := Length(s);
  if n = 0 then Exit;
  expectOperand := True;
  i := 1;
  while i <= n do
  begin
    c := s[i];
    if (c in ['0'..'9', '.']) or (expectOperand and (c = '-')) then
    begin
      numStart := i;
      if c = '-' then Inc(i);   // unary minus folded into the number
      hadDigit := False;
      while (i <= n) and (s[i] in ['0'..'9', '.']) do
      begin
        if s[i] <> '.' then hadDigit := True;
        Inc(i);
      end;
      if (i <= n) and (s[i] in ['e', 'E']) then   // scientific notation (a result may be '1E308')
      begin
        Inc(i);
        if (i <= n) and (s[i] in ['+', '-']) then Inc(i);
        expStart := i;
        while (i <= n) and (s[i] in ['0'..'9']) do Inc(i);
        if i = expStart then Exit;   // incomplete exponent ('1e', '1e+', '1e-')
      end;
      if not hadDigit then Exit;     // digit-less token (lone '.', '-', '-.') — StrToFloatDef returns 0
      num := StrToFloatDef(Copy(s, numStart, i - numStart), NaN, CalcFmt);
      if IsNaN(num) then Exit;   // malformed number (e.g. '1.2.3')
      PushNum(num);
      expectOperand := False;
    end
    else if c in ['+', '-', '*', '/'] then
    begin
      if expectOperand then Exit;   // operator where an operand was expected
      while (Length(opStk) > 0) and (Prec(opStk[High(opStk)]) >= Prec(c)) do
        if not ApplyTop then Exit;
      PushOp(c);
      expectOperand := True;
      Inc(i);
    end
    else
      Exit;   // invalid character
  end;
  if expectOperand then Exit;   // trailing operator: incomplete
  while Length(opStk) > 0 do
    if not ApplyTop then Exit;
  if Length(numStk) <> 1 then Exit;
  AResult := numStk[0];
  ok := not (IsInfinite(AResult) or IsNaN(AResult));
  Result := ok;
end;

{ ---- TTyCalculator ---- }

constructor TTyCalculator.Create(AOwner: TComponent);
var
  i: Integer;
  b: TTyButton;
begin
  inherited Create(AOwner);
  TabStop := True;
  FExpr := '';
  FResult := '0';
  for i := 0 to High(CKeys) do
  begin
    b := TTyButton.Create(Self);
    b.Parent := Self;
    b.Caption := CKeys[i].Cap;
    b.Tag := i;
    { digits + utility keys are neutral 'ghost' outlines; operators / '=' are filled (primary). }
    if CKeys[i].Kind <> 1 then b.StyleClass := 'ghost';
    b.OnClick := @ButtonClick;
    FButtons[i] := b;
  end;
  { Landing size scales with density: classic keeps 224x320 byte-for-byte (ratio 30/30 = 1);
    modern grows by --control-height/30 so the derived key cells (sized off ClientWidth/Height in
    Resize) get proportionally taller and wider. 30 is the classic --control-height baseline. }
  Width  := MulDiv(224, TyDensityHeight(ActiveController, 30), 30);
  Height := MulDiv(320, TyDensityHeight(ActiveController, 30), 30);
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

function TTyCalculator.FormatVal(AValue: Double): string;
begin
  if IsInfinite(AValue) or IsNaN(AValue) then Exit('Error');
  Result := FloatToStrF(AValue, ffGeneral, 15, 0, CalcFmt);
end;

function TTyCalculator.TrailingNumberStart: Integer;
var i: Integer;
begin
  i := Length(FExpr);
  while (i >= 1) and (FExpr[i] in ['0'..'9', '.']) do Dec(i);
  { The trailing number may be in E-notation (a result like '1E-7' copied back on continue) — walk
    back over a '[sign]E' + its mantissa so the WHOLE number is the entry, not just the exponent. }
  if (i >= 2) and (FExpr[i] in ['+', '-']) and (FExpr[i - 1] in ['e', 'E']) then
  begin
    Dec(i, 2);
    while (i >= 1) and (FExpr[i] in ['0'..'9', '.']) do Dec(i);
  end
  else if (i >= 1) and (FExpr[i] in ['e', 'E']) then
  begin
    Dec(i);
    while (i >= 1) and (FExpr[i] in ['0'..'9', '.']) do Dec(i);
  end;
  Result := i + 1;   // 1-based start of the trailing number
  { Include a leading unary '-' (start-of-string or after an operator) so the entry keeps its sign. }
  if (Result > 1) and (FExpr[Result - 1] = '-')
    and ((Result - 1 = 1) or (FExpr[Result - 2] in ['+', '-', '*', '/'])) then
    Dec(Result);
end;

function TTyCalculator.BottomText: string;
begin
  { The large line = the current ENTRY being typed (or the result after '='); the full expression
    lives on the small top line. }
  if FError then Exit('Error');
  if FJustEval then Exit(FResult);
  if FExpr = '' then Exit('0');
  if TrailingNumberStart <= Length(FExpr) then
    Result := Copy(FExpr, TrailingNumberStart, MaxInt)
  else
    Result := '0';   // just after an operator: the entry is empty
end;

procedure TTyCalculator.InputDigit(ACh: Char);
begin
  if FError then Exit;                       // sticky error: ignore until C / CE / ←
  if FJustEval then begin FExpr := ''; FJustEval := False; end;
  FExpr := FExpr + ACh;
end;

procedure TTyCalculator.InputDot;
var p: Integer;
begin
  if FError then Exit;
  if FJustEval then begin FExpr := ''; FJustEval := False; end;
  { A '.' only if the trailing number has none yet. }
  p := TrailingNumberStart;
  if (p > Length(FExpr)) then
    FExpr := FExpr + '0.'                     // start a fresh number
  else if Pos('.', Copy(FExpr, p, MaxInt)) = 0 then
    FExpr := FExpr + '.';
end;

procedure TTyCalculator.InputOp(AOp: Char);
begin
  if FError then Exit;
  if FJustEval then begin FExpr := FResult; FJustEval := False; end;
  if FExpr = '' then
  begin
    if AOp = '-' then FExpr := '-' else FExpr := '0' + AOp;   // allow a leading unary minus
    Exit;
  end;
  { Replace a trailing operator rather than stacking two. }
  if FExpr[Length(FExpr)] in ['+', '-', '*', '/'] then
    FExpr[Length(FExpr)] := AOp
  else
    FExpr := FExpr + AOp;
end;

procedure TTyCalculator.InputEquals;
var r: Double;
begin
  if FError or (FExpr = '') then Exit;
  if TyEvalExpr(FExpr, r) then
  begin
    FResult := FormatVal(r);
    FJustEval := True;
  end
  else
  begin
    FResult := 'Error';
    FError := True;
  end;
end;

procedure TTyCalculator.Backspace;
begin
  if FError then begin Clear; Exit; end;
  if FJustEval then begin FExpr := FResult; FJustEval := False; end;
  if FExpr <> '' then Delete(FExpr, Length(FExpr), 1);
end;

procedure TTyCalculator.ClearEntry;
begin
  if FError then begin Clear; Exit; end;
  if FJustEval then begin Clear; Exit; end;
  { Drop the trailing number (back to the last operator). }
  if TrailingNumberStart <= Length(FExpr) then
    FExpr := Copy(FExpr, 1, TrailingNumberStart - 1);
end;

procedure TTyCalculator.Negate;
var p: Integer;
begin
  if FError then Exit;
  if FJustEval then begin FExpr := FResult; FJustEval := False; end;
  p := TrailingNumberStart;                    // includes a leading unary '-' if present
  if p > Length(FExpr) then Exit;             // no trailing number to negate
  if FExpr[p] = '-' then
    Delete(FExpr, p, 1)                         // already negative: drop the '-'
  else if (p = 1) or (FExpr[p - 1] in ['+', '-', '*', '/']) then
    Insert('-', FExpr, p);                     // insert a unary '-'
end;

procedure TTyCalculator.Clear;
begin
  FExpr := '';
  FResult := '0';
  FJustEval := False;
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
    'E': ClearEntry;
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
var r: Double; e: string;
begin
  if FError then Exit(0);
  if FJustEval then
  begin
    if TyEvalExpr(FResult, r) then Exit(r) else Exit(0);
  end;
  { Strip any trailing operator so an incomplete expression ('333*') still yields its last
    complete value (333) rather than 0 (matters when a drop-down closes mid-entry). }
  e := FExpr;
  while (e <> '') and (e[Length(e)] in ['+', '-', '*', '/']) do Delete(e, Length(e), 1);
  if (e <> '') and TyEvalExpr(e, r) then Result := r else Result := 0;
end;

procedure TTyCalculator.SetValue(const AValue: Double);
begin
  FExpr := '';
  FResult := FormatVal(AValue);
  FJustEval := True;      // a seeded value; the next digit starts fresh, an op continues from it
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
  { Display strip = two text lines, each one control-height (classic 2*30 = 60); the density
    pack raises --control-height for modern. Key spacing follows the --pad-control token
    (classic 4px). Both stay byte-identical under the classic default theme. }
  FDisplayHeight := MulDiv(TyDensityHeight(ActiveController, 30) * 2, Font.PixelsPerInch, 96);   // two lines: expression + value
  if FDisplayHeight > ClientHeight div 2 then FDisplayHeight := ClientHeight div 2;
  gap := MulDiv(ActiveController.Metric('--pad-control', 4), Font.PixelsPerInch, 96);
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
  st, es: TTyStyleSet;
  R, dispR, topR, botR: TRect;
  pad, mid: Integer;
  dim: TTyColor;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    st := CurrentStyle;
    { Fill our OWN themed panel background (not the parent's — in a drop-down the parent is the
      white popup form, which is what made the calculator look un-themed). }
    if tpBackground in st.Present then
      P.FillBackground(R, st.Background, st.BorderRadius)
    else
      TyFillParentBg(Self, P, R, st);
    // Display strip — an input-styled band with the expression (small) over the value (large).
    es := ActiveController.Model.ResolveStyle('TyEdit', StyleClass, []);
    pad := P.Scale(6);
    dispR := Rect(P.Scale(4), P.Scale(4), ClientWidth - P.Scale(4), FDisplayHeight - P.Scale(2));
    if tpBackground in es.Present then
      P.FillBackground(dispR, es.Background, es.BorderRadius);
    if (tpBorderColor in es.Present) and (es.BorderWidth > 0) then
      P.StrokeBorder(dispR, es.BorderRadius, es.BorderWidth, es.BorderColor);
    mid := dispR.Top + (dispR.Bottom - dispR.Top) * 2 div 5;
    dim := (es.TextColor and $00FFFFFF) or $A0000000;   // dimmer for the expression line
    topR := Rect(dispR.Left + pad, dispR.Top + P.Scale(2), dispR.Right - pad, mid);
    P.DrawText(topR, FExpr, es.FontName, ResolveFontSize(es) - 1, es.FontWeight, dim,
      taRightJustify, tlCenter, False);
    botR := Rect(dispR.Left + pad, mid, dispR.Right - pad, dispR.Bottom - P.Scale(2));
    P.DrawText(botR, BottomText, es.FontName, ResolveFontSize(es) + 6, es.FontWeight,
      es.TextColor, taRightJustify, tlCenter, False);
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
      #13: begin PressKey('='); UTF8Key := ''; Exit; end;
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
