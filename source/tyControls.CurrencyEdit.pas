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
    raw-edit form stays a clean editable number and parsing (which drops non-numeric
    chars) recovers the value regardless of the symbol. }
  TTyCurrencyEdit = class(TTyNumericEdit)
  private
    FCurrencySymbol: string;
    FSymbolBefore: Boolean;
    procedure SetCurrencySymbol(const AValue: string);
    procedure SetSymbolBefore(const AValue: Boolean);
  protected
    function Formatted(AValue: Double; AGroup: Boolean): string; override;
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

procedure TTyCurrencyEdit.SetCurrencySymbol(const AValue: string);
begin
  if FCurrencySymbol = AValue then Exit;
  FCurrencySymbol := AValue;
  if not Focused then Reformat(True);
end;

procedure TTyCurrencyEdit.SetSymbolBefore(const AValue: Boolean);
begin
  if FSymbolBefore = AValue then Exit;
  FSymbolBefore := AValue;
  if not Focused then Reformat(True);
end;

end.
