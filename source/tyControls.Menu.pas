unit tyControls.Menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType, LCLProc, Menus,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;

const
  { Layout metrics (logical px, 96-PPI baseline). These are spacing/size tokens, not
    visual colors — every call site scales them via TTyPainter.Scale / MulDiv(.,APPI,96).
    Visual values (colors, fonts, padding) all come from .tycss tokens, never from here. }
  TyMenuSeparatorHeight = 7;   // vertical slot a separator row occupies (the line is centered in it)
  TyMenuArrowSlot       = 16;  // width reserved at the right for a submenu ▸ arrow
  TyMenuCheckSlot       = 18;  // width reserved at the left for a check/radio glyph
  TyMenuShortcutGap     = 24;  // min gap between caption and the right-aligned shortcut text

type
  { Fired by TTyMenuView for the row at AIndex in its current row array: a leaf
    activation (Enter/click on a non-submenu enabled row), a submenu-open request
    (Right/click on a HasSubmenu row), respectively. The host (TTyMenuPopup, Tasks
    4/5/7) maps AIndex back to its TMenuItem and acts (Click / cascade). }
  TTyMenuRowEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  { Left/Right at the bar level: ADelta is -1 (previous top) / +1 (next top). The
    host (TTyMenuBar, Task 5) rotates the open dropdown to the adjacent top item. }
  TTyMenuAdjacentEvent = procedure(Sender: TObject; ADelta: Integer) of object;

  TTyMenuRowKind = (mrkItem, mrkSeparator);
  TTyMenuRow = record
    Kind: TTyMenuRowKind;
    Item: TMenuItem;        // source item (for activation / submenu)
    Caption: string;
    ShortcutText: string;   // ShortCutToText(Item.ShortCut)
    Enabled: Boolean;
    Checked: Boolean;
    RadioItem: Boolean;
    HasSubmenu: Boolean;
    DefaultItem: Boolean;   // render bold
  end;
  TTyMenuRowArray = array of TTyMenuRow;

{ Flatten a root TMenuItem's visible children into render rows. Caption '-' => separator. }
function TyBuildMenuRows(ARoot: TMenuItem): TTyMenuRowArray;

type
  { Themed renderer for a TTyMenuRowArray. Shared by the bar dropdown, submenu
    cascade and context menu (each hosted in a TTyMenuPopup — Tasks 4/5/7). It owns
    no window of its own logic: geometry is pure (MeasureHeight/RowTop/RowAtY take an
    APPI and are headless-testable, mirroring TTyComboBox.ComputePopupHeight), and
    pixels go through RenderTo following the TToggleSwitch painter idiom. All visual
    values (bg/text/padding/highlight) are resolved from the TyMenuPopup/TyMenuItem
    .tycss tokens — never hard-coded here. }
  TTyMenuView = class(TTyCustomControl)
  private
    FRows: TTyMenuRowArray;
    FHighlight: Integer;
    FOnActivateRow: TTyMenuRowEvent;
    FOnOpenSubmenu: TTyMenuRowEvent;
    FOnCloseRequested: TNotifyEvent;
    FOnNavigateAdjacentBar: TTyMenuAdjacentEvent;
    function ItemRowHeight(APPI: Integer): Integer;
    { True iff AIndex is an in-range, selectable (non-separator, enabled) item row. }
    function IsSelectable(AIndex: Integer): Boolean;
    { Fire OnActivateRow (leaf) or OnOpenSubmenu (submenu) for AIndex, if enabled. }
    procedure ActivateRow(AIndex: Integer);
  protected
    function GetStyleTypeKey: string; override;
    { Pure geometry seams (device px), driven by theme tokens + the layout metrics. }
    function RowCount: Integer;
    function MeasureHeight(APPI: Integer): Integer;
    function RowTop(AIndex, APPI: Integer): Integer;
    { Device-y -> row index, or -1 for a separator / out-of-range (not selectable). }
    function RowAtY(AY, APPI: Integer): Integer;
    { Highlight (keyboard/hover selection) navigation. SetHighlight clamps to a valid
      row or -1 (none); MoveHighlight steps by ADelta over SELECTABLE rows only,
      skipping separators + disabled items and wrapping at both ends. Pure — no
      window handle needed, mirroring TTyComboBox's headless list logic. }
    procedure SetHighlight(AIndex: Integer);
    procedure MoveHighlight(ADelta: Integer);
    function Highlight: Integer;
    { First / last selectable row index, or -1 when none exists. }
    function FirstSelectable: Integer;
    function LastSelectable: Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetRows(const ARows: TTyMenuRowArray);
    procedure Click; override;
    { Activation/navigation events consumed by the host popup/bar (Tasks 4/5/7). }
    property OnActivateRow: TTyMenuRowEvent read FOnActivateRow write FOnActivateRow;
    property OnOpenSubmenu: TTyMenuRowEvent read FOnOpenSubmenu write FOnOpenSubmenu;
    property OnCloseRequested: TNotifyEvent read FOnCloseRequested write FOnCloseRequested;
    property OnNavigateAdjacentBar: TTyMenuAdjacentEvent
      read FOnNavigateAdjacentBar write FOnNavigateAdjacentBar;
  end;

implementation

uses Math;

function TyBuildMenuRows(ARoot: TMenuItem): TTyMenuRowArray;
var i, n: Integer; mi: TMenuItem;
begin
  SetLength(Result, 0);
  if ARoot = nil then Exit;
  n := 0;
  SetLength(Result, ARoot.Count);
  for i := 0 to ARoot.Count - 1 do
  begin
    mi := ARoot.Items[i];
    if not mi.Visible then Continue;
    Result[n] := Default(TTyMenuRow);
    Result[n].Item := mi;
    if mi.IsLine then
      Result[n].Kind := mrkSeparator
    else
    begin
      Result[n].Kind := mrkItem;
      Result[n].Caption := mi.Caption;
      Result[n].ShortcutText := ShortCutToText(mi.ShortCut);
      Result[n].Enabled := mi.Enabled;
      Result[n].Checked := mi.Checked;
      Result[n].RadioItem := mi.RadioItem;
      Result[n].HasSubmenu := mi.Count > 0;
      Result[n].DefaultItem := mi.Default;
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ TTyMenuView }

constructor TTyMenuView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  SetLength(FRows, 0);
  FHighlight := -1;
end;

function TTyMenuView.GetStyleTypeKey: string;
begin
  Result := 'TyMenuView';
end;

procedure TTyMenuView.SetRows(const ARows: TTyMenuRowArray);
begin
  FRows := Copy(ARows, 0, Length(ARows));
  FHighlight := -1;
  Invalidate;
end;

function TTyMenuView.RowCount: Integer;
begin
  Result := Length(FRows);
end;

{ A normal item row is exactly tall enough for one line of text plus the TyMenuItem
  top+bottom padding — both sourced from the resolved theme style, so the row height
  tracks the theme's font-size and padding rather than any literal here. }
function TTyMenuView.ItemRowHeight(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  fontLogical, textPx, padPx: Integer;
begin
  S := ActiveController.Model.ResolveStyle('TyMenuItem', '', []);
  fontLogical := S.FontSize;
  if fontLogical <= 0 then fontLogical := ResolveFontSize(S);
  if fontLogical <= 0 then fontLogical := 9;
  // Same logical->device text-height formula the painter uses for FontHeight.
  textPx := MulDiv(Round(fontLogical * 96 / 72), APPI, 96);
  padPx := MulDiv(S.Padding.Top, APPI, 96) + MulDiv(S.Padding.Bottom, APPI, 96);
  Result := textPx + padPx;
  if Result < 1 then Result := 1;
end;

function TTyMenuView.MeasureHeight(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  i, itemH: Integer;
begin
  // Vertical chrome = the TyMenuView (popup) top+bottom padding.
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Top, APPI, 96) + MulDiv(S.Padding.Bottom, APPI, 96);
  itemH := ItemRowHeight(APPI);
  for i := 0 to High(FRows) do
    if FRows[i].Kind = mrkSeparator then
      Inc(Result, MulDiv(TyMenuSeparatorHeight, APPI, 96))
    else
      Inc(Result, itemH);
end;

function TTyMenuView.RowTop(AIndex, APPI: Integer): Integer;
var
  S: TTyStyleSet;
  i, itemH: Integer;
begin
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Top, APPI, 96);
  itemH := ItemRowHeight(APPI);
  for i := 0 to AIndex - 1 do
  begin
    if (i < 0) or (i > High(FRows)) then Break;
    if FRows[i].Kind = mrkSeparator then
      Inc(Result, MulDiv(TyMenuSeparatorHeight, APPI, 96))
    else
      Inc(Result, itemH);
  end;
end;

function TTyMenuView.RowAtY(AY, APPI: Integer): Integer;
var
  i, rowT, h, itemH, sepH: Integer;
begin
  Result := -1;
  itemH := ItemRowHeight(APPI);
  sepH := MulDiv(TyMenuSeparatorHeight, APPI, 96);
  for i := 0 to High(FRows) do
  begin
    rowT := RowTop(i, APPI);
    if FRows[i].Kind = mrkSeparator then h := sepH else h := itemH;
    if (AY >= rowT) and (AY < rowT + h) then
    begin
      // Separators are not selectable.
      if FRows[i].Kind = mrkSeparator then Exit(-1);
      Exit(i);
    end;
  end;
end;

function TTyMenuView.IsSelectable(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FRows))
    and (FRows[AIndex].Kind = mrkItem) and FRows[AIndex].Enabled;
end;

function TTyMenuView.FirstSelectable: Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to High(FRows) do
    if IsSelectable(i) then Exit(i);
end;

function TTyMenuView.LastSelectable: Integer;
var i: Integer;
begin
  Result := -1;
  for i := High(FRows) downto 0 do
    if IsSelectable(i) then Exit(i);
end;

function TTyMenuView.Highlight: Integer;
begin
  Result := FHighlight;
end;

procedure TTyMenuView.SetHighlight(AIndex: Integer);
begin
  // Clamp to a valid selectable row, or -1 (no highlight). Non-selectable indices
  // (separator / disabled / out of range) collapse to -1 so the highlight never
  // lands on something the user can't activate.
  if not IsSelectable(AIndex) then AIndex := -1;
  if FHighlight = AIndex then Exit;
  FHighlight := AIndex;
  Invalidate;
end;

procedure TTyMenuView.MoveHighlight(ADelta: Integer);
var
  step, i, idx, n: Integer;
begin
  n := Length(FRows);
  if (n = 0) or (FirstSelectable < 0) then Exit;   // nothing selectable
  if ADelta = 0 then Exit;
  if ADelta > 0 then step := 1 else step := -1;
  // Walk SELECTABLE rows from the current highlight, wrapping; at most n hops to
  // land on the next selectable index (separators + disabled rows are skipped).
  idx := FHighlight;
  for i := 1 to n do
  begin
    idx := idx + step;
    if idx < 0 then idx := idx + n
    else if idx >= n then idx := idx - n;
    if IsSelectable(idx) then
    begin
      SetHighlight(idx);
      Exit;
    end;
  end;
end;

procedure TTyMenuView.ActivateRow(AIndex: Integer);
begin
  if not IsSelectable(AIndex) then Exit;
  if FRows[AIndex].HasSubmenu then
  begin
    if Assigned(FOnOpenSubmenu) then FOnOpenSubmenu(Self, AIndex);
  end
  else
    if Assigned(FOnActivateRow) then FOnActivateRow(Self, AIndex);
end;

procedure TTyMenuView.MouseMove(Shift: TShiftState; X, Y: Integer);
var idx: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  idx := RowAtY(Y, Font.PixelsPerInch);   // -1 over a separator / gutter
  SetHighlight(idx);                        // SetHighlight collapses -1 safely
end;

procedure TTyMenuView.MouseLeave;
begin
  inherited MouseLeave;
  SetHighlight(-1);
end;

procedure TTyMenuView.Click;
begin
  inherited Click;
  ActivateRow(FHighlight);
end;

procedure TTyMenuView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_DOWN:  begin MoveHighlight(+1); Key := 0; end;
    VK_UP:    begin MoveHighlight(-1); Key := 0; end;
    VK_HOME:  begin SetHighlight(FirstSelectable); Key := 0; end;
    VK_END:   begin SetHighlight(LastSelectable);  Key := 0; end;
    VK_RETURN, VK_SPACE:
      begin ActivateRow(FHighlight); Key := 0; end;
    VK_RIGHT:
      begin
        // On a submenu row, open it; otherwise this is a bar-level "next top".
        if IsSelectable(FHighlight) and FRows[FHighlight].HasSubmenu then
        begin
          if Assigned(FOnOpenSubmenu) then FOnOpenSubmenu(Self, FHighlight);
        end
        else if Assigned(FOnNavigateAdjacentBar) then
          FOnNavigateAdjacentBar(Self, +1);
        Key := 0;
      end;
    VK_LEFT:
      begin
        // Collapse this level (a submenu cascade closes back to its parent). The
        // host decides whether "close this level" at the bar root rotates to the
        // previous top — it does so from inside its OnCloseRequested handler.
        if Assigned(FOnCloseRequested) then FOnCloseRequested(Self);
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        if Assigned(FOnCloseRequested) then FOnCloseRequested(Self);
        Key := 0;
      end;
  end;
end;

procedure TTyMenuView.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, RowStyle: TTyStyleSet;
  R, RowRect, TextRect: TRect;
  i, itemH, sepH, padL, padR, leftSlot, rightSlot, capWeight: Integer;
  RowStates: TTyStateSet;
  SepFill: TTyFill;
  SepY: Integer;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    // Surface: the TyMenuView (popup) background/border/radius from its own tokens.
    S := CurrentStyle;
    DrawFrame(P, R, S);

    itemH := ItemRowHeight(APPI);
    sepH := MulDiv(TyMenuSeparatorHeight, APPI, 96);
    leftSlot := P.Scale(TyMenuCheckSlot);
    rightSlot := P.Scale(TyMenuArrowSlot);

    for i := 0 to High(FRows) do
    begin
      if FRows[i].Kind = mrkSeparator then
      begin
        // A 1px themed line centered in the separator slot, using the TyMenuItem
        // border color (a structural divider color, not a hard-coded value).
        RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', []);
        SepY := RowTop(i, APPI) + sepH div 2;
        SepFill := Default(TTyFill);
        SepFill.Kind := tfkSolid;
        SepFill.Color := RowStyle.BorderColor;
        P.FillBackground(Rect(R.Left + P.Scale(S.Padding.Left), SepY,
          R.Right - P.Scale(S.Padding.Right), SepY + Max(1, P.Scale(1))), SepFill, 0);
        Continue;
      end;

      // Resolve TyMenuItem in the row's interaction state.
      RowStates := [];
      if not FRows[i].Enabled then
        Include(RowStates, tysDisabled)
      else if i = FHighlight then
        Include(RowStates, tysActive)
      else
        Include(RowStates, tysNormal);
      RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', RowStates);

      RowRect := Rect(R.Left + P.Scale(S.Padding.Left), RowTop(i, APPI),
        R.Right - P.Scale(S.Padding.Right), RowTop(i, APPI) + itemH);

      if tpBackground in RowStyle.Present then
        P.FillBackground(RowRect, RowStyle.Background, RowStyle.BorderRadius);

      padL := P.Scale(RowStyle.Padding.Left);
      padR := P.Scale(RowStyle.Padding.Right);

      // Check / radio glyph in the left slot.
      if FRows[i].Checked then
      begin
        if FRows[i].RadioItem then
          P.DrawGlyph(Rect(RowRect.Left + padL, RowRect.Top, RowRect.Left + padL + leftSlot,
            RowRect.Bottom), tgRadioDot, RowStyle.TextColor, 2)
        else
          P.DrawGlyph(Rect(RowRect.Left + padL, RowRect.Top, RowRect.Left + padL + leftSlot,
            RowRect.Bottom), tgCheck, RowStyle.TextColor, 2);
      end;

      // Caption: left-aligned after the check slot, ellipsized before the right slot.
      // A DefaultItem renders bold; otherwise honour the theme's font-weight.
      if FRows[i].DefaultItem then capWeight := 700 else capWeight := RowStyle.FontWeight;
      TextRect := Rect(RowRect.Left + padL + leftSlot, RowRect.Top,
        RowRect.Right - padR - rightSlot, RowRect.Bottom);
      P.DrawText(TextRect, FRows[i].Caption, RowStyle.FontName, ResolveFontSize(RowStyle),
        capWeight, RowStyle.TextColor, taLeftJustify, tlCenter, True);

      // Submenu arrow OR the right-aligned shortcut text in the right slot.
      if FRows[i].HasSubmenu then
        P.DrawGlyph(Rect(RowRect.Right - rightSlot, RowRect.Top, RowRect.Right, RowRect.Bottom),
          tgArrowRight, RowStyle.TextColor, 2)
      else if FRows[i].ShortcutText <> '' then
        P.DrawText(Rect(RowRect.Left, RowRect.Top, RowRect.Right - padR, RowRect.Bottom),
          FRows[i].ShortcutText, RowStyle.FontName, ResolveFontSize(RowStyle),
          RowStyle.FontWeight, RowStyle.TextColor, taRightJustify, tlCenter, False);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyMenuView.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
