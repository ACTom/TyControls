unit tyControls.FontComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox;

{ Draw AFontName into ARect USING AFontName as the typeface (WYSIWYG), inset by the style
  padding; AFontSize is the caller's resolved size. Shared by the font combo's popup list
  and TTyFontListBox. }
procedure TyDrawFontRow(P: TTyPainter; const ARect: TRect; const AFontName: string;
  const AStyle: TTyStyleSet; AFontSize: Integer);

type
  { The drop-down list for TTyFontComboBox: each row is drawn IN ITS OWN font (the row's
    text is a font-family name, so it is rendered using that family). }
  TTyFontPopupList = class(TTyComboPopupList)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A combo of installed font families, each item (field + drop-down) drawn in its own
    typeface — a WYSIWYG font picker. Descends from TTyCustomComboBox; the chosen family is
    SelectedFont (== Text). Populated from Screen.Fonts; RefreshFonts re-reads them.
    Reuses the 'TyComboBox' / 'TyListItem' theming. }
  TTyCustomFontComboBox = class(TTyCustomComboBox)
  private
    FFixedPitchOnly: Boolean;
    function GetSelectedFont: string;
    procedure SetSelectedFont(const AValue: string);
    procedure SetFixedPitchOnly(AValue: Boolean);
  protected
    function CreatePopupList: TTyCustomListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    // Re-populate the family list from Screen.Fonts (call after installing fonts).
    procedure RefreshFonts;
    // The selected font family (== the selected item's text). Setting selects the matching
    // item if present.
    property SelectedFont: string read GetSelectedFont write SetSelectedFont;
    { List only the families the system reports as fixed-pitch (see tyControls.FontFamilies:
      the font's pitch flag, never a measurement). Turning it on or off re-reads the list and
      keeps the chosen family when it is still in it; with it off the list is Screen.Fonts. }
    property FixedPitchOnly: Boolean read FFixedPitchOnly write SetFixedPitchOnly default False;
  end;

  { TTyFontComboBox publishes TTyCustomFontComboBox's properties; everything lives in TTyCustomFontComboBox. }
  TTyFontComboBox = class(TTyCustomFontComboBox)
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
    property FixedPitchOnly;
  end;

implementation

uses tyControls.FontFamilies;

procedure TyDrawFontRow(P: TTyPainter; const ARect: TRect; const AFontName: string;
  const AStyle: TTyStyleSet; AFontSize: Integer);
begin
  P.DrawText(
    Rect(ARect.Left + P.Scale(AStyle.Padding.Left), ARect.Top,
         ARect.Right - P.Scale(AStyle.Padding.Right), ARect.Bottom),
    AFontName, AFontName, AFontSize, AStyle.FontWeight, AStyle.TextColor,
    taLeftJustify, tlCenter, True);
end;

{ TTyFontPopupList }

procedure TTyFontPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  { Owner-draw first, and it has to be spelled out here rather than left to the ancestor:
    this override replaces the whole row, so an inherited call would already be too late.
    True only when the combo really has both an owner-draw Style and a handler; the row
    background is already down and the dispatch runs after EndPaint, from the Paint override
    inherited from TTyComboPopupList. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  // Font name = the row's own text -> draw it in that very family (WYSIWYG).
  TyDrawFontRow(P, ARowRect, Items[AIndex], AStyle, ResolveFontSize(AStyle));
end;

{ TTyCustomFontComboBox }

constructor TTyCustomFontComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { The rows are the fonts installed on THIS machine, not something the author typed. Written
    into a form file they came back on every other machine as the saving machine's fonts -- a
    few hundred names in each .lfm. Reading an Items block still works, which is how a form
    saved by 3.0.0 loads; Loaded then replaces it. }
  FItemsStreamed := False;
  RefreshFonts;
end;

procedure TTyCustomFontComboBox.Loaded;
begin
  inherited Loaded;
  { This machine's fonts again, for a form that still carries another machine's list. The combo
    re-pins its selection by TEXT whenever Items changes, so the chosen family stays chosen at
    whatever row it has here, and one this machine lacks is left unselected rather than swapped
    for whichever font took its row number. }
  TyGetFontFamilies(Items, FFixedPitchOnly);
end;

procedure TTyCustomFontComboBox.RefreshFonts;
begin
  Items.BeginUpdate;
  try
    Items.Clear;
    TyGetFontFamilies(Items, FFixedPitchOnly);   // installed font families
  finally
    Items.EndUpdate;
  end;
  if Items.Count > 0 then ItemIndex := 0;
end;

procedure TTyCustomFontComboBox.SetFixedPitchOnly(AValue: Boolean);
var keep: string;
begin
  if FFixedPitchOnly = AValue then Exit;
  FFixedPitchOnly := AValue;
  { While a form is being read, Loaded fills the list once, with the final value. }
  if csLoading in ComponentState then Exit;
  keep := SelectedFont;
  RefreshFonts;
  SetSelectedFont(keep);   // still listed -> stays chosen; gone -> RefreshFonts' first row
end;

function TTyCustomFontComboBox.CreatePopupList: TTyCustomListBox;
begin
  Result := TTyFontPopupList.Create(Self);
end;

procedure TTyCustomFontComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    P.DrawText(ATextRect, Items[ItemIndex], Items[ItemIndex], ResolveFontSize(AStyle),
      AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True)
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);
end;

function TTyCustomFontComboBox.GetSelectedFont: string;
begin
  Result := Text;
end;

procedure TTyCustomFontComboBox.SetSelectedFont(const AValue: string);
var idx: Integer;
begin
  idx := Items.IndexOf(AValue);
  if idx >= 0 then ItemIndex := idx;
end;

end.
