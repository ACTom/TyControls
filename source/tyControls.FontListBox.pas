unit tyControls.FontListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Forms,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.FontComboBox;

type
  { A list box of installed font families, each row drawn IN ITS OWN typeface (via the
    TTyListBox.PaintItemContent hook + the shared TyDrawFontRow). The list-box sibling of
    TTyFontComboBox. Populated from Screen.Fonts; SelectedFont is the chosen family. }
  TTyCustomFontListBox = class(TTyCustomListBox)
  private
    function GetSelectedFont: string;
    procedure SetSelectedFont(const AValue: string);
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshFonts;
    property SelectedFont: string read GetSelectedFont write SetSelectedFont;
  end;

  { TTyFontListBox publishes TTyCustomFontListBox's properties; everything lives in TTyCustomFontListBox. }
  TTyFontListBox = class(TTyCustomFontListBox)
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
    property MultiSelect;
    property ExtendedSelect;
    property Sorted;
    property ItemHeight;
    property ScrollWidth;
    property ScrollBarAutoHide;
    property TopIndex;
    property OnChange;
    property OnSelectionChange;
    property Align;
    property Anchors;
  end;

implementation

constructor TTyCustomFontListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { This machine's fonts are not written into the form file -- see TTyCustomFontComboBox.Create. }
  FItemsStreamed := False;
  RefreshFonts;
end;

procedure TTyCustomFontListBox.Loaded;
var
  keep: string;
begin
  inherited Loaded;
  { This machine's fonts again, for a form that still carries another machine's list, with the
    chosen family found by NAME: its row number is different on every machine, and a family this
    machine lacks leaves nothing selected rather than whatever font now sits at that row. }
  keep := SelectedFont;
  Items.Assign(Screen.Fonts);
  ItemIndex := Items.IndexOf(keep);
end;

procedure TTyCustomFontListBox.RefreshFonts;
begin
  Items.BeginUpdate;
  try
    Items.Clear;
    Items.Assign(Screen.Fonts);
  finally
    Items.EndUpdate;
  end;
  if Items.Count > 0 then ItemIndex := 0;
end;

procedure TTyCustomFontListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  TyDrawFontRow(P, ARowRect, Items[AIndex], AStyle, ResolveFontSize(AStyle));
end;

function TTyCustomFontListBox.GetSelectedFont: string;
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    Result := Items[ItemIndex]
  else
    Result := '';
end;

procedure TTyCustomFontListBox.SetSelectedFont(const AValue: string);
var idx: Integer;
begin
  idx := Items.IndexOf(AValue);
  if idx >= 0 then ItemIndex := idx;
end;

end.
