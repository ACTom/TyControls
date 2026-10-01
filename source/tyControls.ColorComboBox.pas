unit tyControls.ColorComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox, tyControls.ColorBox, tyControls.Dialogs.Color;

type
  { The drop-down list for TTyColorComboBox: like TTyColorPopupList, but a row whose colour
    is clNone (the "more…" sentinel) is drawn as plain text instead of a swatch. }
  TTyColorMorePopupList = class(TTyComboPopupList)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A colour box (TTyCustomColorBox) + a trailing "more…" row that opens the themed colour dialog; the picked
    colour is inserted before "more" and selected. The "more…" item is marked by a clNone
    colour in Objects[], so it renders as plain text and is detected without a side flag.
    Kept last, so appended custom colours slot in above it. }
  TTyCustomColorComboBox = class(TTyCustomColorBox)
  private
    FMoreCaption: string;
    FPrevIndex: Integer;    // last real selection, to revert a cancelled "more…"
    procedure SetMoreCaption(const AValue: string);
    function IsMoreIndex(AIndex: Integer): Boolean;
    procedure RebuildMoreItem;
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    procedure DoSelect; override;
  public
    constructor Create(AOwner: TComponent); override;
    property MoreCaption: string read FMoreCaption write SetMoreCaption;
  end;

  { TTyColorComboBox publishes TTyCustomColorComboBox's properties; everything lives in TTyCustomColorComboBox. }
  TTyColorComboBox = class(TTyCustomColorComboBox)
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
    property Selected;
    property ColorRectWidth;
    property ColorRectOffset;
    property DefaultColorColor;
    property NoneColorColor;
    property OnGetColors;
    property MoreCaption;
  end;

implementation

{ TTyColorMorePopupList }

procedure TTyColorMorePopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var c: TColor;
begin
  { Owner-draw first: both branches below replace the whole row, so an inherited call would
    be too late. Inert unless the combo has both an owner-draw Style and a handler. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  c := TyColorOfItem(Items, AIndex);
  if c = clNone then
    // the "more…" row: plain text, no swatch.
    P.DrawText(
      Rect(ARowRect.Left + P.Scale(AStyle.Padding.Left), ARowRect.Top,
           ARowRect.Right - P.Scale(AStyle.Padding.Right), ARowRect.Bottom),
      Items[AIndex], AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
      AStyle.TextColor, taLeftJustify, tlCenter, True)
  else
    TyDrawColorRow(P, ARowRect, c, Items[AIndex], AStyle, ResolveFontSize(AStyle));
end;

{ TTyCustomColorComboBox }

constructor TTyCustomColorComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);        // fills the 16-colour palette + selects index 0
  FMoreCaption := 'More…';
  FPrevIndex := ItemIndex;
  RebuildMoreItem;
end;

procedure TTyCustomColorComboBox.RebuildMoreItem;
var i: Integer;
begin
  // Drop any existing "more…" (clNone) row, then append a fresh one at the end.
  for i := Items.Count - 1 downto 0 do
    if TyColorOfItem(Items, i) = clNone then Items.Delete(i);
  TyAddColorItem(Items, FMoreCaption, clNone);
end;

procedure TTyCustomColorComboBox.SetMoreCaption(const AValue: string);
begin
  if FMoreCaption = AValue then Exit;
  FMoreCaption := AValue;
  RebuildMoreItem;
end;

function TTyCustomColorComboBox.IsMoreIndex(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Items.Count) and (ColorAt(AIndex) = clNone);
end;

function TTyCustomColorComboBox.CreatePopupList: TTyListBox;
begin
  Result := TTyColorMorePopupList.Create(Self);
end;

procedure TTyCustomColorComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) and not IsMoreIndex(ItemIndex) then
    TyDrawColorRow(P, ATextRect, ColorAt(ItemIndex), Items[ItemIndex], AStyle, ResolveFontSize(AStyle))
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);   // "more…" / none -> plain text
end;

procedure TTyCustomColorComboBox.DoSelect;
var
  c: TColor;
  a: Byte;
  moreIdx: Integer;
begin
  if IsMoreIndex(ItemIndex) then
  begin
    moreIdx := ItemIndex;
    c := ColorAt(FPrevIndex);
    if c = clNone then c := clBlack;
    a := 255;
    if TySelectColor(FMoreCaption, c, a) then
    begin
      // Insert the picked colour just above "more…" and select it.
      Items.InsertObject(moreIdx, Format('#%.2x%.2x%.2x',
        [Red(ColorToRGB(c)), Green(ColorToRGB(c)), Blue(ColorToRGB(c))]), TObject(PtrInt(c)));
      ItemIndex := moreIdx;
      FPrevIndex := moreIdx;
      inherited DoSelect;
    end
    else
      ItemIndex := FPrevIndex;   // cancelled -> restore the previous real selection
  end
  else
  begin
    FPrevIndex := ItemIndex;
    inherited DoSelect;
  end;
end;

end.
