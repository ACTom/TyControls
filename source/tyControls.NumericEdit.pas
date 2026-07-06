unit tyControls.NumericEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, LCLType,
  tyControls.Edit;

{ Format AValue with ADecimals fixed places, using ADecimalSep for the point and
  (when AUseThousands) AThousands to group the integer part in threes. Locale-safe
  (never leaks the system separators). Pure — unit-tested. }
function TyFormatNumber(AValue: Double; ADecimals: Integer;
  AThousands, ADecimalSep: Char; AUseThousands: Boolean): string;
{ Parse a possibly-grouped/formatted numeric string to a Double: drop AThousands,
  treat ADecimalSep as the decimal point. Returns False (AValue:=0) on no number. }
function TyParseNumber(const AText: string; AThousands, ADecimalSep: Char;
  out AValue: Double): Boolean;

type
  { A numeric edit: subclasses TTyEdit and reuses its whole text engine + the 'TyEdit'
    theme. Input is filtered to digits / sign / decimal separator. The field is edited
    RAW (no grouping) while focused and re-displayed GROUPED on blur, so the caret never
    fights a live-reformatted string. Value is the typed accessor; MinValue/MaxValue
    clamp on blur (only when MaxValue > MinValue). }
  TTyNumericEdit = class(TTyEdit)
  private
    FDecimals: Integer;
    FThousands: Char;
    FDecimalSep: Char;
    FUseThousands: Boolean;
    FMinValue, FMaxValue: Double;
    function GetValue: Double;
    procedure SetValue(const AValue: Double);
    procedure SetDecimals(const AValue: Integer);
    procedure SetUseThousands(const AValue: Boolean);
    procedure SetMinValue(const AValue: Double);
    procedure SetMaxValue(const AValue: Double);
    function ClampVal(AValue: Double): Double;
  protected
    // Re-derive the displayed text from the current value (AGroup = grouped display form).
    // Protected so a subclass can refresh after changing a display-affecting property.
    procedure Reformat(AGroup: Boolean);
    // Format AValue for display. AGroup = the blur/display form (grouped); False = the
    // focused raw-edit form. Virtual so TTyCurrencyEdit can wrap it with a currency symbol
    // (only on the grouped form, so the raw-edit form stays a clean editable number).
    function Formatted(AValue: Double; AGroup: Boolean): string; virtual;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure DoEnter; override;   // show RAW (ungrouped) for editing
    procedure DoExit; override;    // clamp + re-display GROUPED on blur
  public
    constructor Create(AOwner: TComponent); override;
    property Value: Double read GetValue write SetValue;
  published
    property Decimals: Integer read FDecimals write SetDecimals default 2;
    property UseThousands: Boolean read FUseThousands write SetUseThousands default True;
    property MinValue: Double read FMinValue write SetMinValue;
    property MaxValue: Double read FMaxValue write SetMaxValue;
  end;

implementation

function TyFormatNumber(AValue: Double; ADecimals: Integer;
  AThousands, ADecimalSep: Char; AUseThousands: Boolean): string;
var
  fs: TFormatSettings;
  s, intPart, fracPart, grp: string;
  dot, i, cnt: Integer;
  neg: Boolean;
begin
  if ADecimals < 0 then ADecimals := 0;
  neg := AValue < 0;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  s := FloatToStrF(Abs(AValue), ffFixed, 15, ADecimals, fs);
  dot := Pos('.', s);
  if dot > 0 then
  begin
    intPart := Copy(s, 1, dot - 1);
    fracPart := Copy(s, dot + 1, MaxInt);
  end
  else
  begin
    intPart := s;
    fracPart := '';
  end;
  if AUseThousands and (AThousands <> #0) then
  begin
    grp := '';
    cnt := 0;
    for i := Length(intPart) downto 1 do
    begin
      grp := intPart[i] + grp;
      Inc(cnt);
      if (cnt mod 3 = 0) and (i > 1) then grp := AThousands + grp;
    end;
    intPart := grp;
  end;
  Result := intPart;
  if ADecimals > 0 then Result := Result + ADecimalSep + fracPart;
  if neg and (Result <> '0') then Result := '-' + Result;
end;

function TyParseNumber(const AText: string; AThousands, ADecimalSep: Char;
  out AValue: Double): Boolean;
var
  fs: TFormatSettings;
  s: string;
  i: Integer;
  c: Char;
begin
  s := '';
  for i := 1 to Length(AText) do
  begin
    c := AText[i];
    if c = AThousands then Continue;
    if c = ADecimalSep then c := '.';
    if c in ['0'..'9', '.', '-', '+'] then s := s + c;
  end;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := TryStrToFloat(s, AValue, fs);
  if not Result then AValue := 0;
end;

{ TTyNumericEdit }

constructor TTyNumericEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDecimals := 2;
  FThousands := ',';
  FDecimalSep := '.';
  FUseThousands := True;
  FMinValue := 0;
  FMaxValue := 0;
  Alignment := taRightJustify;   // numbers read right-aligned
  Text := Formatted(0, True);
end;

function TTyNumericEdit.ClampVal(AValue: Double): Double;
begin
  Result := AValue;
  if FMaxValue > FMinValue then
  begin
    if Result < FMinValue then Result := FMinValue
    else if Result > FMaxValue then Result := FMaxValue;
  end;
end;

function TTyNumericEdit.Formatted(AValue: Double; AGroup: Boolean): string;
begin
  Result := TyFormatNumber(AValue, FDecimals, FThousands, FDecimalSep,
    AGroup and FUseThousands);
end;

function TTyNumericEdit.GetValue: Double;
begin
  if not TyParseNumber(Text, FThousands, FDecimalSep, Result) then Result := 0;
  Result := ClampVal(Result);
end;

procedure TTyNumericEdit.SetValue(const AValue: Double);
begin
  Text := Formatted(ClampVal(AValue), not Focused);
end;

procedure TTyNumericEdit.Reformat(AGroup: Boolean);
begin
  Text := Formatted(GetValue, AGroup);
end;

procedure TTyNumericEdit.SetDecimals(const AValue: Integer);
var v: Integer;
begin
  v := AValue;
  if v < 0 then v := 0;
  if FDecimals = v then Exit;
  FDecimals := v;
  if not Focused then Reformat(True);
end;

procedure TTyNumericEdit.SetUseThousands(const AValue: Boolean);
begin
  if FUseThousands = AValue then Exit;
  FUseThousands := AValue;
  if not Focused then Reformat(True);
end;

procedure TTyNumericEdit.SetMinValue(const AValue: Double);
begin
  if FMinValue = AValue then Exit;
  FMinValue := AValue;
  if not Focused then Reformat(True);
end;

procedure TTyNumericEdit.SetMaxValue(const AValue: Double);
begin
  if FMaxValue = AValue then Exit;
  FMaxValue := AValue;
  if not Focused then Reformat(True);
end;

procedure TTyNumericEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var c: Char;
begin
  if Length(UTF8Key) = 1 then
  begin
    c := UTF8Key[1];
    if (c in ['0'..'9']) or (c = '-') or ((c = FDecimalSep) and (FDecimals > 0)) then
      inherited UTF8KeyPress(UTF8Key)
    else
      UTF8Key := '';   // reject any other printable char
  end
  else
    UTF8Key := '';      // reject multi-byte (non-numeric) input
end;

procedure TTyNumericEdit.DoEnter;
begin
  Reformat(False);      // strip grouping so the raw number is easy to edit
  inherited DoEnter;
end;

procedure TTyNumericEdit.DoExit;
begin
  Text := Formatted(ClampVal(GetValue), True);   // clamp + regroup on blur
  inherited DoExit;
end;

end.
