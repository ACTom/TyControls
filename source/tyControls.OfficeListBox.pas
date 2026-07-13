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
  TTyOfficeListBox = class(TTyListBox)
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

{ Shared header-band draw: a tinted band (the 'TyGroupBox' background) with bold, left-aligned
  text. Factored out so TTyOfficeComboBox's popup list draws identical bands. AController resolves
  the band style (each control has its own ActiveController). }
procedure TyDrawOfficeHeaderBand(P: TTyPainter; const ARowRect: TRect; const S: string;
  AController: TTyStyleController);

implementation

procedure TyDrawOfficeHeaderBand(P: TTyPainter; const ARowRect: TRect; const S: string;
  AController: TTyStyleController);
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

{ TTyOfficeListBox }

procedure TTyOfficeListBox.AddHeader(const S: string);
begin
  Items.AddObject(S, TObject(PtrInt(1)));
end;

procedure TTyOfficeListBox.AddItem(const S: string);
begin
  Items.AddObject(S, TObject(PtrInt(0)));
end;

function TTyOfficeListBox.IsHeader(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Items.Count)
    and (PtrInt(Items.Objects[AIndex]) = 1);
end;

procedure TTyOfficeListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  if IsHeader(AIndex) then
    TyDrawOfficeHeaderBand(P, ARowRect, Items[AIndex], ActiveController)
  else
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
end;

procedure TTyOfficeListBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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

function TTyOfficeListBox.NextSelectable(ATarget: Integer): Integer;
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

procedure TTyOfficeListBox.SelectItem(AIndex: Integer);
begin
  if IsHeader(AIndex) then
  begin
    AIndex := NextSelectable(AIndex);
    if AIndex < 0 then Exit;   // list is all headers — refuse
  end;
  inherited SelectItem(AIndex);
end;

end.
