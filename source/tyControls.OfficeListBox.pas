unit tyControls.OfficeListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.Controller, tyControls.ListBox;

type
  { A list box with non-selectable GROUP HEADER rows (an Office-style grouped list). A row is
    a header when its Items.Objects[i] holds PtrInt(1); a normal item holds PtrInt(0). The flag
    is stored IN Objects[] so it stays aligned with its item through Sorted / Delete (no parallel
    array). A header renders as a tinted band with bold text (from the 'TyGroupBox' token) and
    cannot be selected — clicking it is swallowed. Use AddHeader / AddItem to build the list. }
  TTyCustomOfficeListBox = class(TTyCustomListBox)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { Nearest non-header index at/after ATarget in the direction of travel (inferred from ATarget
      vs the current ItemIndex, flipping at the ends); -1 if the list is all headers. }
    function NextSelectable(ATarget: Integer): Integer;
    { All selection (keyboard nav, the ItemIndex setter, a row click) funnels through SelectItem;
      redirect a header target to its group's nearest real item so headers are never selectable
      on ANY path (the MouseDown swallow keeps a header click a no-op rather than a redirect). }
    procedure SelectItem(AIndex: Integer); override;
  public
    // Append a group-header row (tinted, bold, non-selectable).
    procedure AddHeader(const S: string);
    // Append a normal, selectable item row.
    procedure AddItem(const S: string);
    // True when the row at AIndex is a group header.
    function IsHeader(AIndex: Integer): Boolean;
  end;

  { TTyOfficeListBox publishes TTyCustomOfficeListBox's properties; everything lives in TTyCustomOfficeListBox. }
  TTyOfficeListBox = class(TTyCustomOfficeListBox)
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

{ Shared header-band draw: a tinted band (the 'TyGroupBox' background) with bold, left-aligned
  text. Factored out so TTyOfficeComboBox's popup list draws identical bands. AController resolves
  the band style (each control has its own ActiveController). }
procedure TyDrawOfficeHeaderBand(P: TTyPainter; const ARowRect: TRect; const S: string;
  AController: TTyCustomStyleController);

implementation

procedure TyDrawOfficeHeaderBand(P: TTyPainter; const ARowRect: TRect; const S: string;
  AController: TTyCustomStyleController);
var
  hs: TTyStyleSet;
  textR: TRect;
  band: TTyColor;
begin
  // The band uses the 'TyGroupBox' token so the header colour tracks the theme.
  hs := AController.Model.ResolveStyle('TyGroupBox', '', []);
  if (tpBackground in hs.Present) and (TyAlphaOf(hs.Background.Color) > 0) then
    P.FillBackground(ARowRect, hs.Background, 0)
  else
  begin
    // Most themes leave TyGroupBox's background transparent; derive a subtle visible band from
    // the (theme) header text colour so groups read as bands on every theme — no hard-coded chrome.
    band := (hs.TextColor and $00FFFFFF) or $24000000;
    P.Bitmap.Canvas2D.fillStyle(TyColorToBGRA(band));
    P.Bitmap.Canvas2D.fillRect(ARowRect.Left, ARowRect.Top,
      ARowRect.Right - ARowRect.Left, ARowRect.Bottom - ARowRect.Top);
  end;
  // Bold header text, left-aligned with a small left pad.
  textR := Rect(ARowRect.Left + P.Scale(6), ARowRect.Top, ARowRect.Right, ARowRect.Bottom);
  P.DrawText(textR, S, hs.FontName, TyResolveFontSize(hs, True, 0, AController), 700, hs.TextColor,
    taLeftJustify, tlCenter, True);
end;

{ TTyCustomOfficeListBox }

procedure TTyCustomOfficeListBox.AddHeader(const S: string);
begin
  Items.AddObject(S, TObject(PtrInt(1)));
end;

procedure TTyCustomOfficeListBox.AddItem(const S: string);
begin
  Items.AddObject(S, TObject(PtrInt(0)));
end;

function TTyCustomOfficeListBox.IsHeader(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Items.Count)
    and (PtrInt(Items.Objects[AIndex]) = 1);
end;

procedure TTyCustomOfficeListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  if IsHeader(AIndex) then
    TyDrawOfficeHeaderBand(P, ARowRect, Items[AIndex], ActiveController)
  else
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
end;

procedure TTyCustomOfficeListBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  row: Integer;
begin
  // Swallow a left click on a header row so it never selects; normal rows fall through to the
  // base. NOTE: in LCL, MouseDown's Shift set INCLUDES the pressed button (ssLeft) — gate on
  // Button = mbLeft, never on `Shift = []`.
  row := RowAtY(Y);
  if (Button = mbLeft) and (row >= 0) and IsHeader(row) then Exit;
  inherited MouseDown(Button, Shift, X, Y);
end;

function TTyCustomOfficeListBox.NextSelectable(ATarget: Integer): Integer;
var dir, i: Integer;
begin
  if ATarget >= ItemIndex then dir := 1 else dir := -1;
  i := ATarget;
  while (i >= 0) and (i < Items.Count) and IsHeader(i) do Inc(i, dir);
  if (i < 0) or (i >= Items.Count) then
  begin
    // ran off that end — try from the target in the other direction
    dir := -dir; i := ATarget;
    while (i >= 0) and (i < Items.Count) and IsHeader(i) do Inc(i, dir);
    if (i < 0) or (i >= Items.Count) then Exit(-1);
  end;
  Result := i;
end;

procedure TTyCustomOfficeListBox.SelectItem(AIndex: Integer);
begin
  if IsHeader(AIndex) then
  begin
    AIndex := NextSelectable(AIndex);
    if AIndex < 0 then Exit;   // list is all headers — refuse
  end;
  inherited SelectItem(AIndex);
end;

end.
