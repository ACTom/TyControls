unit tyControls.OfficeComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.Controller, tyControls.ListBox, tyControls.ComboBox;

type
  { The drop-down list for TTyOfficeComboBox. A row whose Objects[i] holds PtrInt(1) is a
    group HEADER (tinted band, bold text); all others are normal items. The flags are copied
    into this list's Items via Items.Assign from the combo, so it reads its OWN Objects[]. }
  TTyOfficeComboPopupList = class(TTyComboPopupList)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A combo box with non-selectable GROUP HEADER rows (an Office-style grouped combo). A row is
    a header when its Items.Objects[i] holds PtrInt(1); a normal item holds PtrInt(0). Headers
    render as a tinted band with bold text (from the 'TyGroupBox' token) and cannot be selected.
    Build the list with AddHeader / AddItem.

    Header rows are non-selectable on EVERY path — keyboard navigation, the ItemIndex setter and
    a popup row click all funnel through SelectItem, which redirects a header target to the nearest
    real item (so arrowing onto / clicking a header lands on that group's first entry). }
  TTyOfficeComboBox = class(TTyComboBox)
  protected
    function CreatePopupList: TTyListBox; override;
    { Nearest non-header index at/after ATarget in the direction of travel (inferred from ATarget
      vs the current ItemIndex, flipping at the ends); -1 if the list is all headers. }
    function NextSelectable(ATarget: Integer): Integer;
    { Redirect a header target to the nearest real item so no path can select a header. }
    procedure SelectItem(AIndex: Integer); override;
    { Locked to csDropDownList (pick-only). The editable csDropDown popup is prefix-FILTERED and
      commits picks via a direct FItemIndex assign that bypasses SelectItem, which would let a
      header row be selected. Grouped combos are pick-only anyway. }
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
  public
    // Append a group-header row (tinted, bold, non-selectable).
    procedure AddHeader(const S: string);
    // Append a normal, selectable item row.
    procedure AddItem(const S: string);
    // True when the row at AIndex is a group header.
    function IsHeader(AIndex: Integer): Boolean;
  end;

implementation

{ Shared header-band draw: a tinted band (the 'TyGroupBox' background) with bold, left-aligned
  text — same look as TTyOfficeListBox, kept unit-local so this combo is self-contained. }
procedure DrawHeaderBand(P: TTyPainter; const ARowRect: TRect; const S: string;
  AController: TTyStyleController);
var
  hs: TTyStyleSet;
  textR: TRect;
  band: TTyColor;
begin
  hs := AController.Model.ResolveStyle('TyGroupBox', '', []);
  if (tpBackground in hs.Present) and (TyAlphaOf(hs.Background.Color) > 0) then
    P.FillBackground(ARowRect, hs.Background, 0)
  else
  begin
    // Themes leave TyGroupBox's background transparent; derive a subtle visible band from the
    // (theme) header text colour so groups read as bands on every theme — no hard-coded chrome.
    band := (hs.TextColor and $00FFFFFF) or $24000000;
    P.Bitmap.Canvas2D.fillStyle(TyColorToBGRA(band));
    P.Bitmap.Canvas2D.fillRect(ARowRect.Left, ARowRect.Top,
      ARowRect.Right - ARowRect.Left, ARowRect.Bottom - ARowRect.Top);
  end;
  textR := Rect(ARowRect.Left + P.Scale(6), ARowRect.Top, ARowRect.Right, ARowRect.Bottom);
  P.DrawText(textR, S, hs.FontName, TyResolveFontSize(hs, True, 0, AController), 700, hs.TextColor,
    taLeftJustify, tlCenter, True);
end;

{ TTyOfficeComboPopupList }

procedure TTyOfficeComboPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  { Owner-draw first: the header branch below replaces the whole row, so leaving the collect
    to the inherited call would skip exactly the rows a grouped combo most wants to restyle.
    Note what it costs — a host that takes the rows over paints the GROUP HEADERS too; the
    band is default content like any other. Selectability is unaffected: that is a hit test,
    not a paint. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  // Read this list's OWN Objects[] (copied via Assign from the combo).
  if (AIndex >= 0) and (AIndex < Items.Count) and (PtrInt(Items.Objects[AIndex]) = 1) then
    DrawHeaderBand(P, ARowRect, Items[AIndex], ActiveController)
  else
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
end;

{ TTyOfficeComboBox }

procedure TTyOfficeComboBox.AddHeader(const S: string);
begin
  Items.AddObject(S, TObject(PtrInt(1)));
end;

procedure TTyOfficeComboBox.AddItem(const S: string);
begin
  Items.AddObject(S, TObject(PtrInt(0)));
end;

function TTyOfficeComboBox.IsHeader(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Items.Count)
    and (PtrInt(Items.Objects[AIndex]) = 1);
end;

function TTyOfficeComboBox.CreatePopupList: TTyListBox;
begin
  Result := TTyOfficeComboPopupList.Create(Self);
end;

function TTyOfficeComboBox.NextSelectable(ATarget: Integer): Integer;
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

procedure TTyOfficeComboBox.SelectItem(AIndex: Integer);
begin
  // Every selection (keyboard nav, ItemIndex setter, popup click) funnels here; a header
  // target is redirected to its group's nearest real item so headers are never selectable.
  if IsHeader(AIndex) then
  begin
    AIndex := NextSelectable(AIndex);
    if AIndex < 0 then Exit;   // list is all headers — refuse
  end;
  inherited SelectItem(AIndex);
end;

procedure TTyOfficeComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  { Pick-only, and ONLY pick-only. The reason is the edit box and nothing else: the editable
    popup commits a pick by assigning FItemIndex directly, bypassing the SelectItem override
    that keeps headers unselectable. Owner-draw does not go anywhere near that path, so
    taking it off with the edit box (which flattening to csDropDownList did) removed a
    capability for a reason that never applied to it. }
  inherited SetStyle(TyComboStylePickOnly(AValue));
end;

end.
