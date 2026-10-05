unit tyControls.FontSizeComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils,
  tyControls.ComboBox;

type
  { An EDITABLE combo of common font sizes: pick a preset or type a custom one. FontSize is
    the numeric value. No custom item paint (sizes are plain text) — reuses 'TyComboBox'. }
  TTyCustomFontSizeComboBox = class(TTyCustomComboBox)
  private
    function GetFontSize: Integer;
    procedure SetFontSize(const AValue: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    // The numeric size (parsed from the text; 0 if the text is not a number).
    property FontSize: Integer read GetFontSize write SetFontSize;
  end;

  { TTyFontSizeComboBox publishes TTyCustomFontSizeComboBox's properties; everything lives in TTyCustomFontSizeComboBox. }
  TTyFontSizeComboBox = class(TTyCustomFontSizeComboBox)
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
    property Items;
    property ItemIndex;
    property Text;
    property DropDownCount;
    property Sorted;
    property MaxLength;
    property CharCase;
    property Style;
    property ItemHeight;
    property ItemWidth;
    property TextHint;
    property ReadOnly;
    property OnDrawItem;
    property OnMeasureItem;
    property OnChange;
    property OnSelect;
    property OnDropDown;
    property OnCloseUp;
    property OnGetItems;
    property Align;
    property Anchors;
  end;

implementation

const
  cSizes: array[0..17] of Integer =
    (6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 60, 72);

constructor TTyCustomFontSizeComboBox.Create(AOwner: TComponent);
var i: Integer;
begin
  inherited Create(AOwner);
  Style := csDropDown;   // editable: type a custom size that is not a preset
  for i := Low(cSizes) to High(cSizes) do
    Items.Add(IntToStr(cSizes[i]));
  FontSize := 12;
  Width := 64;
end;

function TTyCustomFontSizeComboBox.GetFontSize: Integer;
begin
  Result := StrToIntDef(Trim(Text), 0);
end;

procedure TTyCustomFontSizeComboBox.SetFontSize(const AValue: Integer);
var idx: Integer;
begin
  idx := Items.IndexOf(IntToStr(AValue));
  if idx >= 0 then
    ItemIndex := idx           // a preset -> select it
  else
    Text := IntToStr(AValue);  // custom -> set the editable text
end;

end.
