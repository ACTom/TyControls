unit tyControls.FontSizeComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils,
  tyControls.ComboBox;

type
  { An EDITABLE combo of common font sizes: pick a preset or type a custom one. FontSize is
    the numeric value. No custom item paint (sizes are plain text) — reuses 'TyComboBox'. }
  TTyFontSizeComboBox = class(TTyComboBox)
  private
    function GetFontSize: Integer;
    procedure SetFontSize(const AValue: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    // The numeric size (parsed from the text; 0 if the text is not a number).
    property FontSize: Integer read GetFontSize write SetFontSize;
  end;

implementation

const
  cSizes: array[0..17] of Integer =
    (6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 60, 72);

constructor TTyFontSizeComboBox.Create(AOwner: TComponent);
var i: Integer;
begin
  inherited Create(AOwner);
  Style := csDropDown;   // editable: type a custom size that is not a preset
  for i := Low(cSizes) to High(cSizes) do
    Items.Add(IntToStr(cSizes[i]));
  FontSize := 12;
  Width := 64;
end;

function TTyFontSizeComboBox.GetFontSize: Integer;
begin
  Result := StrToIntDef(Trim(Text), 0);
end;

procedure TTyFontSizeComboBox.SetFontSize(const AValue: Integer);
var idx: Integer;
begin
  idx := Items.IndexOf(IntToStr(AValue));
  if idx >= 0 then
    ItemIndex := idx           // a preset -> select it
  else
    Text := IntToStr(AValue);  // custom -> set the editable text
end;

end.
