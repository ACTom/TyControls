unit tyControls.CurrencyEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils,
  tyControls.NumericEdit;

type
  { A currency edit: TTyNumericEdit with a currency symbol on the GROUPED (blur) display.
    Everything else — input filtering, edit-raw/display-grouped, clamping, the 'TyEdit'
    theme — is inherited. The symbol is added only to the display form, so the focused
    raw-edit form stays a clean editable number, and StripDecoration takes it off again
    before the display is parsed. }
  TTyCurrencyEdit = class(TTyNumericEdit)
  private
    FCurrencySymbol: string;
    FSymbolBefore: Boolean;
    procedure SetCurrencySymbol(const AValue: string);
    procedure SetSymbolBefore(const AValue: Boolean);
  protected
    function Formatted(AValue: Double; AGroup: Boolean): string; override;
    function StripDecoration(const AText: string): string; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property CurrencySymbol: string read FCurrencySymbol write SetCurrencySymbol;
    property SymbolBefore: Boolean read FSymbolBefore write SetSymbolBefore default True;
  end;

implementation

constructor TTyCurrencyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCurrencySymbol := '$';
  FSymbolBefore := True;
  // NumericEdit already defaults Decimals=2; refresh the initial display with the symbol.
  Text := Formatted(0, True);
end;

function TTyCurrencyEdit.Formatted(AValue: Double; AGroup: Boolean): string;
begin
  Result := inherited Formatted(AValue, AGroup);
  if AGroup and (FCurrencySymbol <> '') then
  begin
    if FSymbolBefore then Result := FCurrencySymbol + Result
    else Result := Result + FCurrencySymbol;
  end;
end;

function TTyCurrencyEdit.StripDecoration(const AText: string): string;
begin
  { Only what Formatted added, where it added it -- never by character, since a symbol may hold
    digits, dots or signs. The focused raw form carries no symbol and passes through. }
  Result := AText;
  if FCurrencySymbol = '' then Exit;
  if FSymbolBefore then
  begin
    if Copy(Result, 1, Length(FCurrencySymbol)) = FCurrencySymbol then
      Delete(Result, 1, Length(FCurrencySymbol));
  end
  else if (Length(Result) >= Length(FCurrencySymbol))
    and (Copy(Result, Length(Result) - Length(FCurrencySymbol) + 1, MaxInt) = FCurrencySymbol) then
    SetLength(Result, Length(Result) - Length(FCurrencySymbol));
end;

procedure TTyCurrencyEdit.SetCurrencySymbol(const AValue: string);
var
  v: Double;
begin
  if FCurrencySymbol = AValue then Exit;
  v := Value;   { read under the symbol the text carries now, before it changes }
  FCurrencySymbol := AValue;
  if not Focused then ShowValue(v, True);
end;

procedure TTyCurrencyEdit.SetSymbolBefore(const AValue: Boolean);
var
  v: Double;
begin
  if FSymbolBefore = AValue then Exit;
  v := Value;   { read with the symbol where the text has it now }
  FSymbolBefore := AValue;
  if not Focused then ShowValue(v, True);
end;

end.
