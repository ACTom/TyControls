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
    { Content-driven popup width (device px): the widest item row's caption + the
      check/arrow slots + the shortcut text + min gap, themed via TyMenuItem. Pure;
      the popup host sizes to it (clamped to a host minimum). }
    function MeasureWidth(APPI: Integer): Integer;
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

  { Borderless TForm host for a TTyMenuView, plus the submenu-cascade manager.
    One TTyMenuPopup owns one popup level: its lazy FForm wraps an FView that
    renders the rows of FRoot; opening a submenu row spawns a child TTyMenuPopup
    (FChild) anchored to the right of that row, and so the cascade nests. Mirrors
    the TTyComboBox popup idiom exactly: bsNone / stNever / fsStayOnTop, PopupParent
    + pmExplicit, KeyPreview, OnDeactivate -> CloseAll with the handler DETACHED
    around Hide, a FCloseTick 200 ms reopen guard, and Application.RemoveAsyncCalls
    in the destructor. The window needs a GUI loop, so geometry lives in the pure,
    headless-testable ComputeBounds seam (anchor -> screen rect, flipping above/left
    near screen edges) and activation runs through ActivateRowForTest. }
  TTyMenuPopup = class(TComponent)
  private
    FForm: TForm;             // lazy; created on first Popup; freed in Destroy
    FView: TTyMenuView;       // owned by FForm once shown; else freed by us
    FChild: TTyMenuPopup;     // open submenu cascade (this level's child), or nil
    FRoot: TMenuItem;         // the item whose children this level renders
    FController: TTyStyleController;
    FCloseTick: QWord;        // tick at last close; reopen guard (ComboBox idiom)
    FOnNavigateAdjacent: TTyMenuAdjacentEvent;
    procedure EnsureForm;
    procedure HandleActivateRow(Sender: TObject; AIndex: Integer);
    procedure HandleOpenSubmenu(Sender: TObject; AIndex: Integer);
    procedure HandleCloseRequested(Sender: TObject);
    procedure HandleNavigateAdjacent(Sender: TObject; ADelta: Integer);
    procedure FormDeactivate(Sender: TObject);
  protected
    { Pure placement: turn an anchor rect (screen coords) + the popup's size into a
      screen rect, flipping ABOVE the anchor when there is no room below and (for a
      submenu, AToRight=True) LEFT of the anchor when there is no room to the right.
      Headless-testable; the live Popup calls it so on-screen sizing cannot drift. }
    function ComputeBounds(const AAnchor: TRect; AWidth, AHeight, APPI: Integer;
      AToRight: Boolean): TRect;
    { Run the activation path for row AIndex exactly as a click/Enter would: a leaf
      fires its item's OnClick and closes the whole cascade; a submenu row opens its
      child. Shared by the live OnActivateRow handler and ActivateRowForTest. }
    procedure DoActivateRow(AIndex: Integer);
    procedure DoOpenSubmenu(AIndex: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Point this level at the item whose visible children it should render. }
    procedure SetRoot(AItem: TMenuItem);
    { Show the popup with its top-left anchored to AAnchor (a screen-coord rect, e.g.
      a menu-bar cell or the parent row); AToRight places a submenu to the right of
      its parent row. Lazily builds the borderless form on first call. }
    procedure Popup(const AAnchor: TRect; AToRight: Boolean = False);
    { Close this level: free the child cascade first, then hide the form (with the
      OnDeactivate handler detached around Hide), and arm the reopen guard. }
    procedure CloseAll;
    function IsOpen: Boolean;
    { Test seam: activate a row as if it were clicked (same path as a real click). }
    procedure ActivateRowForTest(AIndex: Integer);
    property Controller: TTyStyleController read FController write FController;
    property Root: TMenuItem read FRoot;
    { Left/Right at the bar-root dropdown: ADelta -1/+1. A bare popup has no adjacent
      top to rotate to, so this is meaningful only when a host (TTyMenuBar, Task 5)
      wires it and rotates the open dropdown to the adjacent top item. }
    property OnNavigateAdjacent: TTyMenuAdjacentEvent
      read FOnNavigateAdjacent write FOnNavigateAdjacent;
  end;

  { Themed application menu bar: renders an associated LCL TMainMenu's visible
    top-level items as a row of horizontal cells (TyMenuBar background + TyMenuItem
    cells with hover/active states), and opens a TTyMenuPopup dropdown rooted at the
    clicked top item. The cell layout + hit-test are pure geometry seams
    (TopCount/TopCaption/TopLeft/TopAtX, each taking an APPI), headless-testable like
    TTyMenuView's row geometry; all visual values come from the TyMenuBar/TyMenuItem
    .tycss tokens. Left/Right rotate the open dropdown to the adjacent top while one
    is open (via the shared view's OnNavigateAdjacentBar). Follows the TToggleSwitch
    anatomy: class(TTyCustomControl), GetStyleTypeKey, RenderTo seam + Paint. }
  TTyMenuBar = class(TTyCustomControl)
  private
    FMenu: TMainMenu;
    FOpenIndex: Integer;      // index of the open top dropdown, or -1 (none open)
    FHotIndex: Integer;       // hovered top cell, or -1
    FPopup: TTyMenuPopup;     // lazy dropdown host for the open top item
    FAutoSizeWidth: Boolean;  // shrink-to-fit the top cells (see FitWidth)
    FInAutoSizeWidth: Boolean;// re-entrancy guard around the Width := FitWidth set
    procedure SetMenu(AValue: TMainMenu);
    procedure SetAutoSizeWidth(AValue: Boolean);
    { Apply content-fit sizing when enabled and Align permits it (not alTop/alBottom,
      where the LCL force-stretches the bar to the parent width). Sets Width to
      FitWidth; guarded against the Resize -> SetBounds -> Resize re-entry. }
    procedure ApplyAutoSizeWidth;
    { Index of the AIndex-th VISIBLE top item back into Menu.Items, or -1. }
    function VisibleTopItem(AIndex: Integer): TMenuItem;
    procedure HandleNavigateAdjacent(Sender: TObject; ADelta: Integer);
    procedure ClosePopup;
    { Open (or re-open) the dropdown for top cell AIndex, anchored to its cell rect. }
    procedure OpenTop(AIndex: Integer);
  protected
    function GetStyleTypeKey: string; override;
    { Pure top-cell geometry seams (device px), driven by theme tokens. }
    function TopCount: Integer;
    function TopCaption(AIndex: Integer): string;
    { Resolve the width of the AIndex-th top cell in device px (caption + the
      TyMenuItem left/right padding), theme-driven. }
    function TopCellWidth(AIndex, APPI: Integer): Integer;
    function TopLeft(AIndex, APPI: Integer): Integer;
    { Device-x -> top cell index, or -1 when X is past the last cell. }
    function TopAtX(AX, APPI: Integer): Integer;
    { Pure content-fit width (device px): the sum of the top-cell widths plus the bar's
      own left+right padding — i.e. TopLeft(last) + TopCellWidth(last) + right padding.
      The width an AutoSizeWidth bar shrinks to; headless-testable like TopLeft/TopAtX. }
    function FitWidth(APPI: Integer): Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    { The associated LCL data model. Setting it (re)builds the rendered top cells;
      freeing it nils this reference (FreeNotification). TTyForm.MenuBar reads this
      for the non-mac shortcut dispatch and the mac global-bar handoff (Task 6). }
    property Menu: TMainMenu read FMenu write SetMenu;
    { Shrink-to-fit the bar's Width to its top-level cells + horizontal padding. A
      distinct flag (not the LCL AutoSize/CanAutoSize machinery, which fights the
      auto-size layout system): when True it sets Width to FitWidth — but only while
      Align is NOT alTop/alBottom, where the LCL force-stretches the bar to the parent
      width and a content fit would be overridden anyway. Recomputed when Menu is
      (re)assigned, when this flag is set True, and on resize/relayout. }
    property AutoSizeWidth: Boolean read FAutoSizeWidth write SetAutoSizeWidth default False;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

  { Themed context menu over the LCL TPopupMenu model. It IS a TPopupMenu (so it slots
    into any control's PopupMenu property and the LCL right-click path keeps working),
    but its virtual PopUp(X,Y) is overridden to route through our themed TTyMenuView /
    TTyMenuPopup renderer instead of the native OS menu. The renderer is rooted at the
    inherited Items, themed via the assigned Controller. Verified seam (menus.pp:485):
    TPopupMenu.PopUp(X, Y: Integer) is VIRTUAL, so a direct override is correct (no
    DoContextPopup fallback needed). Assigning a TTyPopupMenu to a control's PopupMenu
    makes right-click show the themed menu, since LCL's DoContextPopup calls
    PopupMenu.PopUp(X, Y). }
  TTyPopupMenu = class(TPopupMenu)
  private
    FRenderer: TTyMenuPopup;     // lazy themed popup host; created on first PopUp
    FController: TTyStyleController;
    procedure EnsureRenderer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Show the themed context menu at screen point (X, Y) instead of the native menu.
      Roots the shared renderer at the inherited Items and pops it (a zero-size anchor
      at the cursor; the renderer measures its own size). Overrides the virtual seam. }
    procedure PopUp(X, Y: Integer); override;
    { Test seam: activate the row at AIndex exactly as choosing it in the themed popup
      would (fires the source item's OnClick). Mirrors TTyMenuPopup.ActivateRowForTest. }
    procedure ActivateRowForTest(AIndex: Integer);
  published
    { The .tycss style controller the themed popup resolves its tokens through. }
    property Controller: TTyStyleController read FController write FController;
  end;

implementation

uses Math, BGRABitmap;

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

function TTyMenuView.MeasureWidth(APPI: Integer): Integer;
var
  S, RowStyle: TTyStyleSet;
  Bmp: TBGRABitmap;
  i, effSize, capW, scW, padLR, leftSlot, rightSlot, gap, rowW: Integer;
begin
  // Vertical chrome (popup) left+right padding bounds every row; each row's content
  // = check slot + caption + (gap + shortcut) + arrow slot, themed via TyMenuItem.
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Left, APPI, 96) + MulDiv(S.Padding.Right, APPI, 96);
  RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', []);
  effSize := ResolveFontSize(RowStyle);
  padLR := MulDiv(RowStyle.Padding.Left, APPI, 96) + MulDiv(RowStyle.Padding.Right, APPI, 96);
  leftSlot := MulDiv(TyMenuCheckSlot, APPI, 96);
  rightSlot := MulDiv(TyMenuArrowSlot, APPI, 96);
  gap := MulDiv(TyMenuShortcutGap, APPI, 96);

  Bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(Bmp, RowStyle.FontName, effSize, RowStyle.FontWeight, APPI);
    rowW := 0;
    for i := 0 to High(FRows) do
    begin
      if FRows[i].Kind <> mrkItem then Continue;
      capW := 0;
      if FRows[i].Caption <> '' then capW := Bmp.TextSize(FRows[i].Caption).cx;
      scW := 0;
      if FRows[i].ShortcutText <> '' then scW := gap + Bmp.TextSize(FRows[i].ShortcutText).cx;
      rowW := Max(rowW, padLR + leftSlot + capW + scW + rightSlot);
    end;
  finally
    Bmp.Free;
  end;
  Inc(Result, rowW);
  if Result < 1 then Result := 1;
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

{ TTyMenuPopup }

constructor TTyMenuPopup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FForm := nil;
  FView := nil;
  FChild := nil;
  FRoot := nil;
  FController := nil;
  FCloseTick := 0;
end;

destructor TTyMenuPopup.Destroy;
begin
  { Cancel any queued async calls so they can't fire into a freed popup. }
  Application.RemoveAsyncCalls(Self);
  { Free the child cascade first (it parents under our form path). }
  FreeAndNil(FChild);
  { Detach OnDeactivate before tearing the form down to avoid re-entering CloseAll
    from the TForm destruction path (the ComboBox lesson). FView is owned by FForm
    once it has been parented; if the form was never created, free FView directly. }
  if FForm <> nil then
  begin
    FForm.OnDeactivate := nil;
    FreeAndNil(FForm);
    FView := nil;  // was owned by FForm
  end
  else
    FreeAndNil(FView);
  inherited Destroy;
end;

procedure TTyMenuPopup.SetRoot(AItem: TMenuItem);
begin
  FRoot := AItem;
  if FView <> nil then
    FView.SetRows(TyBuildMenuRows(AItem));
end;

procedure TTyMenuPopup.EnsureForm;
begin
  if FForm <> nil then Exit;
  FForm := TForm.CreateNew(nil);
  FForm.BorderStyle := bsNone;
  FForm.ShowInTaskBar := stNever;
  FForm.FormStyle := fsStayOnTop;
  FForm.PopupMode := pmExplicit;
  FForm.KeyPreview := True;
  FForm.OnDeactivate := @FormDeactivate;

  FView := TTyMenuView.Create(FForm);
  FView.Parent := FForm;
  FView.Align := alClient;
  FView.OnActivateRow := @HandleActivateRow;
  FView.OnOpenSubmenu := @HandleOpenSubmenu;
  FView.OnCloseRequested := @HandleCloseRequested;
  FView.OnNavigateAdjacentBar := @HandleNavigateAdjacent;
  if FRoot <> nil then
    FView.SetRows(TyBuildMenuRows(FRoot));
end;

function TTyMenuPopup.ComputeBounds(const AAnchor: TRect;
  AWidth, AHeight, APPI: Integer; AToRight: Boolean): TRect;
var
  L, T, sw, sh: Integer;
begin
  sw := Screen.Width;
  sh := Screen.Height;

  if AToRight then
  begin
    // A submenu sits to the RIGHT of its parent row; flip LEFT if it would overflow.
    L := AAnchor.Right;
    if L + AWidth > sw then
      L := AAnchor.Left - AWidth;
  end
  else
  begin
    // A dropdown aligns its left edge with the anchor; nudge left if it overflows.
    L := AAnchor.Left;
    if L + AWidth > sw then
      L := sw - AWidth;
  end;
  if L < 0 then L := 0;

  // Hang BELOW the anchor; flip ABOVE when there isn't room below the bottom.
  T := AAnchor.Bottom;
  if T + AHeight > sh then
    T := AAnchor.Top - AHeight;
  if T < 0 then T := 0;

  Result := Rect(L, T, L + AWidth, T + AHeight);
end;

procedure TTyMenuPopup.Popup(const AAnchor: TRect; AToRight: Boolean);
var
  ppi, w, h: Integer;
  R: TRect;
  ParentForm: TCustomForm;
begin
  EnsureForm;
  FView.Controller := FController;

  ParentForm := nil;
  if (Owner <> nil) and (Owner is TControl) then
    ParentForm := GetParentForm(TControl(Owner));
  if ParentForm <> nil then
    FForm.PopupParent := ParentForm;

  ppi := FView.Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  h := FView.MeasureHeight(ppi);
  // Content-driven width, but never narrower than the anchor (e.g. a bar cell), so
  // a top dropdown is at least as wide as its trigger.
  w := Max(FView.MeasureWidth(ppi), AAnchor.Right - AAnchor.Left);
  R := ComputeBounds(AAnchor, w, h, ppi, AToRight);
  FForm.SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
  FForm.Show;
end;

procedure TTyMenuPopup.CloseAll;
begin
  { Collapse the cascade from the leaf up: free the child first. }
  FreeAndNil(FChild);
  if (FForm <> nil) and FForm.Visible then
  begin
    // Detach OnDeactivate around Hide so hiding can't re-enter CloseAll (ComboBox).
    FForm.OnDeactivate := nil;
    FForm.Hide;
    FForm.OnDeactivate := @FormDeactivate;
  end;
  FCloseTick := GetTickCount64;
end;

function TTyMenuPopup.IsOpen: Boolean;
begin
  Result := (FForm <> nil) and FForm.Visible;
end;

procedure TTyMenuPopup.DoActivateRow(AIndex: Integer);
var
  rows: TTyMenuRowArray;
begin
  rows := TyBuildMenuRows(FRoot);
  if (AIndex < 0) or (AIndex > High(rows)) then Exit;
  if rows[AIndex].Kind <> mrkItem then Exit;
  if not rows[AIndex].Enabled then Exit;
  if rows[AIndex].HasSubmenu then
  begin
    DoOpenSubmenu(AIndex);
    Exit;
  end;
  CloseAll;
  if rows[AIndex].Item <> nil then
    rows[AIndex].Item.Click;   // fire the source item's OnClick (the activation)
end;

procedure TTyMenuPopup.DoOpenSubmenu(AIndex: Integer);
var
  rows: TTyMenuRowArray;
  anchor: TRect;
begin
  rows := TyBuildMenuRows(FRoot);
  if (AIndex < 0) or (AIndex > High(rows)) then Exit;
  if not rows[AIndex].HasSubmenu then Exit;

  FreeAndNil(FChild);   // only one open submenu per level
  FChild := TTyMenuPopup.Create(Self);
  FChild.Controller := FController;
  FChild.SetRoot(rows[AIndex].Item);

  // Anchor the child to the right of the parent row (screen coords). When the form
  // is live we have a real row rect; headless callers use ActivateRowForTest, which
  // never opens a window, so no anchor/window is built there.
  if (FForm <> nil) and FForm.HandleAllocated then
  begin
    // A zero-width anchor at the parent's right edge: the child opens flush to the
    // right of the parent column (ComputeBounds uses AAnchor.Right for AToRight),
    // and its own width is carried by Popup via the form width below.
    anchor.Left := FForm.Left + FForm.Width;
    anchor.Right := anchor.Left;
    anchor.Top := FForm.Top + FView.RowTop(AIndex, FView.Font.PixelsPerInch);
    anchor.Bottom := anchor.Top;
    FChild.Popup(anchor, True);
  end;
end;

procedure TTyMenuPopup.HandleActivateRow(Sender: TObject; AIndex: Integer);
begin
  DoActivateRow(AIndex);
end;

procedure TTyMenuPopup.HandleOpenSubmenu(Sender: TObject; AIndex: Integer);
begin
  DoOpenSubmenu(AIndex);
end;

procedure TTyMenuPopup.HandleCloseRequested(Sender: TObject);
begin
  CloseAll;
end;

procedure TTyMenuPopup.HandleNavigateAdjacent(Sender: TObject; ADelta: Integer);
begin
  // Bar-level rotation is the host bar's concern (Task 5): forward Left/Right at the
  // bar root to whoever wired OnNavigateAdjacent (the TTyMenuBar). A bare popup with
  // no host leaves it nil and the navigation is a no-op.
  if Assigned(FOnNavigateAdjacent) then
    FOnNavigateAdjacent(Self, ADelta);
end;

procedure TTyMenuPopup.FormDeactivate(Sender: TObject);
begin
  CloseAll;
end;

procedure TTyMenuPopup.ActivateRowForTest(AIndex: Integer);
begin
  DoActivateRow(AIndex);
end;

{ TTyMenuBar }

constructor TTyMenuBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FMenu := nil;
  FOpenIndex := -1;
  FHotIndex := -1;
  FPopup := nil;
  Height := 28;
end;

destructor TTyMenuBar.Destroy;
begin
  FreeAndNil(FPopup);
  inherited Destroy;
end;

function TTyMenuBar.GetStyleTypeKey: string;
begin
  Result := 'TyMenuBar';
end;

procedure TTyMenuBar.SetMenu(AValue: TMainMenu);
begin
  if FMenu = AValue then Exit;
  ClosePopup;
  FMenu := AValue;
  if FMenu <> nil then
    FMenu.FreeNotification(Self);
  ApplyAutoSizeWidth;   // the cell set changed -> refit when enabled
  Invalidate;
end;

procedure TTyMenuBar.SetAutoSizeWidth(AValue: Boolean);
begin
  if FAutoSizeWidth = AValue then Exit;
  FAutoSizeWidth := AValue;
  ApplyAutoSizeWidth;   // fit immediately when turned on
end;

procedure TTyMenuBar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FMenu) then
  begin
    ClosePopup;
    FMenu := nil;
    ApplyAutoSizeWidth;   // no cells left -> refit (to bare padding) when enabled
    Invalidate;
  end;
end;

function TTyMenuBar.TopCount: Integer;
var i: Integer;
begin
  Result := 0;
  if FMenu = nil then Exit;
  for i := 0 to FMenu.Items.Count - 1 do
    if FMenu.Items[i].Visible then Inc(Result);
end;

function TTyMenuBar.VisibleTopItem(AIndex: Integer): TMenuItem;
var i, n: Integer;
begin
  Result := nil;
  if (FMenu = nil) or (AIndex < 0) then Exit;
  n := 0;
  for i := 0 to FMenu.Items.Count - 1 do
    if FMenu.Items[i].Visible then
    begin
      if n = AIndex then Exit(FMenu.Items[i]);
      Inc(n);
    end;
end;

function TTyMenuBar.TopCaption(AIndex: Integer): string;
var mi: TMenuItem;
begin
  mi := VisibleTopItem(AIndex);
  if mi <> nil then Result := mi.Caption else Result := '';
end;

{ A top cell is the item's caption width plus the TyMenuItem left+right padding, all
  theme-driven (font + padding tokens), so the bar tracks the active theme metrics. }
function TTyMenuBar.TopCellWidth(AIndex, APPI: Integer): Integer;
var
  RowStyle: TTyStyleSet;
  Bmp: TBGRABitmap;
  effSize, padLR, capW: Integer;
  cap: string;
begin
  RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', []);
  effSize := ResolveFontSize(RowStyle);
  padLR := MulDiv(RowStyle.Padding.Left, APPI, 96) + MulDiv(RowStyle.Padding.Right, APPI, 96);
  cap := TopCaption(AIndex);
  capW := 0;
  Bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(Bmp, RowStyle.FontName, effSize, RowStyle.FontWeight, APPI);
    if cap <> '' then capW := Bmp.TextSize(cap).cx;
  finally
    Bmp.Free;
  end;
  Result := capW + padLR;
  if Result < 1 then Result := 1;
end;

function TTyMenuBar.TopLeft(AIndex, APPI: Integer): Integer;
var
  S: TTyStyleSet;
  i: Integer;
begin
  // The bar's own left padding offsets the first cell; cells then pack edge-to-edge.
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Left, APPI, 96);
  for i := 0 to AIndex - 1 do
    Inc(Result, TopCellWidth(i, APPI));
end;

function TTyMenuBar.TopAtX(AX, APPI: Integer): Integer;
var
  i, cellL, cellR: Integer;
begin
  Result := -1;
  for i := 0 to TopCount - 1 do
  begin
    cellL := TopLeft(i, APPI);
    cellR := cellL + TopCellWidth(i, APPI);
    if (AX >= cellL) and (AX < cellR) then Exit(i);
  end;
end;

function TTyMenuBar.FitWidth(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  n: Integer;
begin
  // The cells pack from the bar's left padding (TopLeft(0)) edge-to-edge, so the last
  // cell's right edge is TopLeft(last) + TopCellWidth(last); add the bar's own right
  // padding to close the symmetric chrome. Reuses the pure cell-geometry seams so this
  // stays headless-testable (no window). With no cells it collapses to just the
  // left+right padding.
  S := CurrentStyle;
  n := TopCount;
  if n <= 0 then
    Result := MulDiv(S.Padding.Left, APPI, 96) + MulDiv(S.Padding.Right, APPI, 96)
  else
    Result := TopLeft(n - 1, APPI) + TopCellWidth(n - 1, APPI)
      + MulDiv(S.Padding.Right, APPI, 96);
  if Result < 1 then Result := 1;
end;

procedure TTyMenuBar.ApplyAutoSizeWidth;
var
  ppi, w: Integer;
begin
  if not FAutoSizeWidth then Exit;
  // alTop/alBottom hand width control to the LCL align layout (full parent width), so
  // a content fit would just be overridden — leave those alone.
  if Align in [alTop, alBottom] then Exit;
  if FInAutoSizeWidth then Exit;   // guard the Width set's Resize re-entry
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  w := FitWidth(ppi);
  if w = Width then Exit;
  FInAutoSizeWidth := True;
  try
    Width := w;
  finally
    FInAutoSizeWidth := False;
  end;
end;

procedure TTyMenuBar.ClosePopup;
begin
  FOpenIndex := -1;
  FreeAndNil(FPopup);
  Invalidate;
end;

procedure TTyMenuBar.OpenTop(AIndex: Integer);
var
  mi: TMenuItem;
  ppi, cellL, cellW: Integer;
  origin: TPoint;
  anchor: TRect;
begin
  mi := VisibleTopItem(AIndex);
  if (mi = nil) or (mi.Count = 0) then begin ClosePopup; Exit; end;

  // Reuse the live host across adjacent-cell rotation; rebuild it only when needed.
  if FPopup = nil then
  begin
    FPopup := TTyMenuPopup.Create(Self);
    FPopup.OnNavigateAdjacent := @HandleNavigateAdjacent;
  end;
  FPopup.Controller := ActiveController;
  FPopup.SetRoot(mi);
  FOpenIndex := AIndex;

  // Anchor the dropdown to this cell's screen rect (just below the bar). Only
  // meaningful with a live window handle; headless callers never reach here.
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  cellL := TopLeft(AIndex, ppi);
  cellW := TopCellWidth(AIndex, ppi);
  if HandleAllocated then
  begin
    origin := ClientToScreen(Point(0, 0));
    anchor := Rect(origin.X + cellL, origin.Y,
      origin.X + cellL + cellW, origin.Y + Height);
    FPopup.Popup(anchor, False);
  end;
  Invalidate;
end;

procedure TTyMenuBar.HandleNavigateAdjacent(Sender: TObject; ADelta: Integer);
var
  n, idx: Integer;
begin
  // Left/Right at the bar root rotates the open dropdown to the adjacent top item,
  // wrapping at both ends (mirrors the row-highlight wrap inside a dropdown).
  n := TopCount;
  if (n = 0) or (FOpenIndex < 0) then Exit;
  idx := FOpenIndex + ADelta;
  if idx < 0 then idx := idx + n
  else if idx >= n then idx := idx - n;
  OpenTop(idx);
end;

procedure TTyMenuBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var idx: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  idx := TopAtX(X, Font.PixelsPerInch);
  if idx <> FHotIndex then
  begin
    FHotIndex := idx;
    Invalidate;
  end;
  // While a dropdown is open, hovering a different top cell switches to it (the
  // standard menu-bar "track on hover" behaviour).
  if (FOpenIndex >= 0) and (idx >= 0) and (idx <> FOpenIndex) then
    OpenTop(idx);
end;

procedure TTyMenuBar.MouseLeave;
begin
  inherited MouseLeave;
  if FHotIndex <> -1 then
  begin
    FHotIndex := -1;
    Invalidate;
  end;
end;

procedure TTyMenuBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var idx: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  idx := TopAtX(X, Font.PixelsPerInch);
  if idx < 0 then begin ClosePopup; Exit; end;
  // Click the already-open cell to close it; otherwise open (or switch to) it.
  if idx = FOpenIndex then
    ClosePopup
  else
    OpenTop(idx);
end;

procedure TTyMenuBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, CellStyle: TTyStyleSet;
  R, CellRect: TRect;
  i, cellL, cellW, padL: Integer;
  CellStates: TTyStateSet;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    // Surface: the TyMenuBar background/border from its own tokens.
    S := CurrentStyle;
    DrawFrame(P, R, S);

    for i := 0 to TopCount - 1 do
    begin
      cellL := TopLeft(i, APPI);
      cellW := TopCellWidth(i, APPI);

      // A cell is active when its dropdown is open, hover when the mouse is over it.
      CellStates := [];
      if i = FOpenIndex then
        Include(CellStates, tysActive)
      else if i = FHotIndex then
        Include(CellStates, tysHover)
      else
        Include(CellStates, tysNormal);
      CellStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', CellStates);

      CellRect := Rect(R.Left + cellL, R.Top, R.Left + cellL + cellW, R.Bottom);
      if tpBackground in CellStyle.Present then
        P.FillBackground(CellRect, CellStyle.Background, CellStyle.BorderRadius);

      padL := P.Scale(CellStyle.Padding.Left);
      P.DrawText(Rect(CellRect.Left + padL, CellRect.Top, CellRect.Right, CellRect.Bottom),
        TopCaption(i), CellStyle.FontName, ResolveFontSize(CellStyle),
        CellStyle.FontWeight, CellStyle.TextColor, taLeftJustify, tlCenter, True);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyMenuBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyMenuBar.Resize;
begin
  inherited Resize;
  // Re-fit on a relayout (e.g. the parent resized us, or a DPI/font change moved the
  // cell metrics). The re-entrancy guard inside ApplyAutoSizeWidth keeps the Width set
  // from looping back through Resize.
  ApplyAutoSizeWidth;
end;

{ TTyPopupMenu }

constructor TTyPopupMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRenderer := nil;
  FController := nil;
end;

destructor TTyPopupMenu.Destroy;
begin
  FreeAndNil(FRenderer);
  inherited Destroy;
end;

procedure TTyPopupMenu.EnsureRenderer;
begin
  if FRenderer = nil then
    FRenderer := TTyMenuPopup.Create(Self);
  FRenderer.Controller := FController;
  // Root the shared renderer at this popup menu's items (the inherited LCL model).
  FRenderer.SetRoot(Items);
end;

procedure TTyPopupMenu.PopUp(X, Y: Integer);
var
  anchor: TRect;
begin
  EnsureRenderer;
  // A zero-size anchor at the cursor: the renderer hangs its dropdown below/right of
  // (X, Y) and measures its own size (ComputeBounds flips near screen edges).
  anchor := Rect(X, Y, X, Y);
  FRenderer.Popup(anchor, False);
end;

procedure TTyPopupMenu.ActivateRowForTest(AIndex: Integer);
begin
  EnsureRenderer;
  FRenderer.ActivateRowForTest(AIndex);
end;

end.
