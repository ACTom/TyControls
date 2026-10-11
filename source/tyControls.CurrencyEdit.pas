unit tyControls.CurrencyEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils,
  tyControls.NumericEdit;

type
  { A currency edit: a numeric edit (TTyCustomNumericEdit) with a currency symbol on the GROUPED (blur) display.
    Everything else — input filtering, edit-raw/display-grouped, clamping, the 'TyEdit'
    theme — is inherited. The symbol is added only to the display form, so the focused
    raw-edit form stays a clean editable number, and StripDecoration takes it off again
    before the display is parsed. }
  TTyCustomCurrencyEdit = class(TTyCustomNumericEdit)
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
    property CurrencySymbol: string read FCurrencySymbol write SetCurrencySymbol;
    property SymbolBefore: Boolean read FSymbolBefore write SetSymbolBefore default True;
  end;

  { TTyCurrencyEdit publishes TTyCustomCurrencyEdit's properties; everything lives in TTyCustomCurrencyEdit. }
  TTyCurrencyEdit = class(TTyCustomCurrencyEdit)
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
    property Text;
    property ReadOnly;
    property MaxLength;
    property PasswordChar;
    property EchoMode;
    property HideSelection;
    property AutoSelect;
    property TextHint;
    property Alignment;
    property CharCase;
    property NumbersOnly;
    property Align;
    property Anchors;
    property OnChange;
    property Decimals;
    property UseThousands;
    property MinValue;
    property MaxValue;
    property CurrencySymbol;
    property SymbolBefore;
  end;

implementation

constructor TTyCustomCurrencyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCurrencySymbol := '$';
  FSymbolBefore := True;
  // NumericEdit already defaults Decimals=2; refresh the initial display with the symbol.
  Text := Formatted(0, True);
end;

function TTyCustomCurrencyEdit.Formatted(AValue: Double; AGroup: Boolean): string;
begin
  Result := inherited Formatted(AValue, AGroup);
  if AGroup and (FCurrencySymbol <> '') then
  begin
    if FSymbolBefore then Result := FCurrencySymbol + Result
    else Result := Result + FCurrencySymbol;
  end;
end;

function TTyCustomCurrencyEdit.StripDecoration(const AText: string): string;
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

procedure TTyCustomCurrencyEdit.SetCurrencySymbol(const AValue: string);
var
  v: Double;
begin
  if FCurrencySymbol = AValue then Exit;
  v := Value;   { read under the symbol the text carries now, before it changes }
  FCurrencySymbol := AValue;
  if not Focused then ShowValue(v, True);
end;

procedure TTyCustomCurrencyEdit.SetSymbolBefore(const AValue: Boolean);
var
  v: Double;
begin
  if FSymbolBefore = AValue then Exit;
  v := Value;   { read with the symbol where the text has it now }
  FSymbolBefore := AValue;
  if not Focused then ShowValue(v, True);
end;

end.
