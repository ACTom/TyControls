unit tyControls.Menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType, LCLProc, LCLIntf, LMessages, Menus,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Accel;

const
  { Layout metrics (logical px, 96-PPI baseline). These are spacing/size tokens, not
    visual colors — every call site scales them via TTyPainter.Scale / MulDiv(.,APPI,96).
    Visual values (colors, fonts, padding) all come from .tycss tokens, never from here. }
  TyMenuSeparatorHeight = 7;   // vertical slot a separator row occupies (the line is centered in it)
  TyMenuArrowSlot       = 16;  // width reserved at the right for a submenu ▸ arrow
  TyMenuCheckSlot       = 18;  // width reserved at the left for a check/radio glyph
  TyMenuShortcutGap     = 24;  // min gap between caption and the right-aligned shortcut text
  TyMenuHoverOpenDelay  = 350; // ms the highlight must rest on a submenu row before it auto-opens

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
    Display: string;        // Caption with the mnemonic '&' removed (what is drawn + measured)
    Mnemonic: Char;         // upper-cased mnemonic char (for Alt+key), or #0
    MnemonicPos: Integer;   // 1-based index of the mnemonic char within Display, or 0
    ShortcutText: string;   // ShortCutToText(Item.ShortCut)
    Enabled: Boolean;
    Checked: Boolean;
    RadioItem: Boolean;
    HasSubmenu: Boolean;
    DefaultItem: Boolean;   // render bold
  end;
  TTyMenuRowArray = array of TTyMenuRow;

{ Flatten a root TMenuItem's visible children into render rows. Caption '-' => separator.
  (TyParseMnemonic lives in tyControls.Accel — the shared mnemonic facility.) }
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
    FOnCloseChild: TNotifyEvent;
    FOnNavigateAdjacentBar: TTyMenuAdjacentEvent;
    FOnNavigateLeft: TNotifyEvent;
    { Lazy hover-open timer (the ToggleSwitch/ComboBox lazy-TTimer idiom): while the
      highlight rests on a submenu row, it (re)starts; on fire it requests opening that
      row's submenu. FHoverPending is the row armed for opening, or -1 (disarmed). }
    FHoverTimer: TTimer;
    FHoverPending: Integer;
    procedure EnsureHoverTimer;
    procedure HandleHoverTimer(Sender: TObject);
    function ItemRowHeight(APPI: Integer): Integer;
    { True iff AIndex is an in-range, selectable (non-separator, enabled) item row. }
    function IsSelectable(AIndex: Integer): Boolean;
    { First selectable row whose mnemonic equals AChar (upper-cased), or -1. }
    function FindMnemonicRow(AChar: Char): Integer;
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
    { Arm/disarm the lazy hover-open for the current highlight: if it is a submenu row,
      (re)start the timer toward opening it; otherwise cancel any pending open and ask
      the host to close any already-open child (a non-submenu row has none). Driven from
      MouseMove when the highlight changes; exposed (protected) for the hover-open test. }
    procedure UpdateHoverOpen;
    { Steppable hover-open seam (no wall-clock): run exactly what the lazy hover
      timer's OnTimer fire would — if the highlight is still the armed submenu row,
      fire OnOpenSubmenu for it. Tests drive this directly via an access subclass;
      the lazy TTimer drives it at runtime. }
    procedure TickHoverForTest;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetRows(const ARows: TTyMenuRowArray);
    procedure Click; override;
    { Activation/navigation events consumed by the host popup/bar (Tasks 4/5/7). }
    property OnActivateRow: TTyMenuRowEvent read FOnActivateRow write FOnActivateRow;
    property OnOpenSubmenu: TTyMenuRowEvent read FOnOpenSubmenu write FOnOpenSubmenu;
    property OnCloseRequested: TNotifyEvent read FOnCloseRequested write FOnCloseRequested;
    { Close just this level's OPEN CHILD cascade (NOT this level itself): fired when the
      hover highlight moves onto a non-submenu row, so a previously-opened sibling
      submenu collapses while this dropdown stays up. Distinct from OnCloseRequested,
      which collapses this whole level (ESC/Left). }
    property OnCloseChild: TNotifyEvent read FOnCloseChild write FOnCloseChild;
    property OnNavigateAdjacentBar: TTyMenuAdjacentEvent
      read FOnNavigateAdjacentBar write FOnNavigateAdjacentBar;
    { Left key: the host popup decides by level — a submenu collapses to its parent, the
      ROOT dropdown rotates to the previous top. Distinct from OnCloseRequested (Esc). }
    property OnNavigateLeft: TNotifyEvent read FOnNavigateLeft write FOnNavigateLeft;
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
    FPopupRect: TRect;        // computed screen rect of the last Popup (for the deferred Qt re-apply)
    FOnNavigateAdjacent: TTyMenuAdjacentEvent;
    FOnClose: TNotifyEvent;   // fired by CloseAll so a host (bar) can reset its open state
    procedure EnsureForm;
    procedure HandleActivateRow(Sender: TObject; AIndex: Integer);
    procedure HandleOpenSubmenu(Sender: TObject; AIndex: Integer);
    procedure HandleCloseRequested(Sender: TObject);
    procedure HandleCloseChild(Sender: TObject);
    procedure HandleNavigateAdjacent(Sender: TObject; ADelta: Integer);
    procedure HandleNavigateLeft(Sender: TObject);
    function IsSubmenuLevel: Boolean;
    procedure FormDeactivate(Sender: TObject);
    procedure DeferredDismiss(Data: PtrInt);
    procedure DeferredForceClose(Data: PtrInt);
    procedure DeferredCollapseChild(Data: PtrInt);
    { Qt/X11 re-places + un-masks a frameless window at MAP time, AFTER Show returns; re-assert the
      popup's bounds + rounded region on the next event-loop turn, once the native window has settled. }
    procedure DeferredReapplyGeometry(Data: PtrInt);
  protected
    { Pure placement: turn an anchor rect (screen coords) + the popup's size into a
      screen rect, flipping ABOVE the anchor when there is no room below and (for a
      submenu, AToRight=True) LEFT of the anchor when there is no room to the right.
      Headless-testable; the live Popup calls it so on-screen sizing cannot drift. }
    function ComputeBounds(const AAnchor: TRect; AWidth, AHeight, APPI: Integer;
      AToRight: Boolean): TRect;
    { Shape the borderless popup window with a rounded region matching the popup's
      own themed BorderRadius (TyMenuPopup), scaled to device PPI, so the opaque
      rectangular corners outside the rounded fill are clipped away. Guarded on
      HandleAllocated and re-applied on every Popup so it tracks a new size/PPI/theme.
      No-op when the radius is 0 (leave rectangular) or off Windows. }
    procedure ApplyFormRegion(AWidth, AHeight: Integer);
    { Run the activation path for row AIndex exactly as a click/Enter would: a leaf
      fires its item's OnClick and closes the whole cascade; a submenu row opens its
      child. Shared by the live OnActivateRow handler and ActivateRowForTest. }
    procedure DoActivateRow(AIndex: Integer);
    procedure DoOpenSubmenu(AIndex: Integer);
    { Test seam: -1 when no open child exists, else the number of rows the open child
      cascade's view was populated with. Lets a headless test assert that opening a
      submenu row created AND populated the child (without a live window). }
    function ChildRowCountForTest: Integer;
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
    { Fired whenever this level closes (CloseAll). A host (TTyMenuBar) wires it on the
      root dropdown to clear its open-index when the cascade collapses — whether from an
      activation, a focus-loss dismiss, or Esc. }
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
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
    FPendingTop: Integer;     // deferred keyboard-rotation target, or -1
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
    procedure HandlePopupClosed(Sender: TObject);
    procedure ClosePopup;
    { Open (or re-open) the dropdown for top cell AIndex, anchored to its cell rect. }
    procedure OpenTop(AIndex: Integer);
    { Deferred OpenTop(FPendingTop): keyboard rotation must not free FPopup synchronously
      while the dropdown view's KeyDown is on the stack (rotating onto a childless top frees it). }
    procedure DeferredOpenTop(Data: PtrInt);
    function AccelPos(AIndex: Integer): Integer;   // gated mnemonic pos via the shared facility
  protected
    function GetStyleTypeKey: string; override;
    { Pure top-cell geometry seams (device px), driven by theme tokens. }
    function TopCount: Integer;
    function TopCaption(AIndex: Integer): string;   // mnemonic '&' stripped (display text)
    function TopMnemonic(AIndex: Integer): Char;    // upper-cased Alt+key mnemonic, or #0
    function TopMnemonicPos(AIndex: Integer): Integer;  // 1-based mnemonic index in TopCaption, or 0
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
    { Alt+<mnemonic>: open the matching top menu (LCL broadcasts DialogChar to children). }
    function DialogChar(var Message: TLMKey): Boolean; override;
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
    function GetAbout: string;
  published
    { Read-only library version (TyVersion); the design-time editor opens the About dialog. }
    property About: string read GetAbout;
    { The .tycss style controller the themed popup resolves its tokens through. }
    property Controller: TTyStyleController read FController write FController;
  end;

implementation

// Rounded popup corners use the CROSS-PLATFORM LCLIntf SetWindowRgn/CreateRoundRectRgn (the
// win32/gtk2/qt widgetsets all implement them) — no Windows unit needed. (Rect()/Point() call
// sites remain qualified Types.* — harmless now that the Windows POINT=TPOINT shadow is gone.)
uses Math, BGRABitmap;

{ Opt-in geometry diagnostics for the Linux popup/menu-position investigation: set the env var
  TY_MENU_DEBUG (any value) and run from a terminal to see the computed-vs-actual screen rects.
  No-op (one getenv) otherwise. }
procedure TyGeomLog(const AMsg: string);
begin
  if GetEnvironmentVariable('TY_MENU_DEBUG') = '' then Exit;
  WriteLn(StdErr, '[ty-menu] ' + AMsg);
  Flush(StdErr);
end;

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
      Result[n].Mnemonic := TyParseMnemonic(mi.Caption, Result[n].Display, Result[n].MnemonicPos);
      // Only render shortcut text for a REAL shortcut — ShortCutToText(0) returns 'Unknown'
      // (not ''), which would otherwise show on every item that has no accelerator.
      if mi.ShortCut <> 0 then
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
  FHoverPending := -1;
end;

destructor TTyMenuView.Destroy;
begin
  // FHoverTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown (ToggleSwitch).
  FreeAndNil(FHoverTimer);
  inherited Destroy;
end;

procedure TTyMenuView.EnsureHoverTimer;
begin
  if FHoverTimer = nil then
  begin
    FHoverTimer := TTimer.Create(Self);
    FHoverTimer.Enabled := False;
    FHoverTimer.Interval := TyMenuHoverOpenDelay;
    FHoverTimer.OnTimer := @HandleHoverTimer;
  end;
end;

procedure TTyMenuView.HandleHoverTimer(Sender: TObject);
begin
  // One-shot: disarm the wall-clock timer, then run the (re-checked) open.
  if FHoverTimer <> nil then FHoverTimer.Enabled := False;
  TickHoverForTest;
end;

procedure TTyMenuView.TickHoverForTest;
begin
  // Only open if the highlight is still resting on the armed submenu row (the user may
  // have moved on since the timer was started). Re-validate against the live rows.
  if (FHoverPending >= 0) and (FHoverPending = FHighlight)
    and IsSelectable(FHoverPending) and FRows[FHoverPending].HasSubmenu then
  begin
    if Assigned(FOnOpenSubmenu) then FOnOpenSubmenu(Self, FHoverPending);
  end;
end;

procedure TTyMenuView.UpdateHoverOpen;
begin
  if IsSelectable(FHighlight) and FRows[FHighlight].HasSubmenu then
  begin
    // Submenu row: (re)arm the lazy hover-open timer toward this row. Restarting it
    // (disable+enable) resets the countdown so a quick pass-through doesn't open.
    FHoverPending := FHighlight;
    EnsureHoverTimer;
    FHoverTimer.Enabled := False;
    FHoverTimer.Enabled := True;
  end
  else
  begin
    // Non-submenu (or no) row: cancel any pending open and ask the host to close any
    // already-open CHILD cascade (not this level) — the new highlight has no submenu of
    // its own, so a sibling submenu opened earlier should collapse while this stays up.
    FHoverPending := -1;
    if FHoverTimer <> nil then FHoverTimer.Enabled := False;
    if Assigned(FOnCloseChild) then FOnCloseChild(Self);
  end;
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
      if FRows[i].Display <> '' then capW := Bmp.TextSize(FRows[i].Display).cx;
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

function TTyMenuView.FindMnemonicRow(AChar: Char): Integer;
var i: Integer;
begin
  Result := -1;
  if AChar = #0 then Exit;
  for i := 0 to High(FRows) do
    if IsSelectable(i) and (FRows[i].Mnemonic = AChar) then Exit(i);
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
var idx, prev: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  prev := FHighlight;
  idx := RowAtY(Y, Font.PixelsPerInch);   // -1 over a separator / gutter
  SetHighlight(idx);                        // SetHighlight collapses -1 safely
  // Only (re)arm/cancel the lazy hover-open when the highlight actually moved to a new
  // row, so a jittery mouse inside one cell doesn't keep resetting the countdown.
  if FHighlight <> prev then
    UpdateHoverOpen;
end;

procedure TTyMenuView.MouseLeave;
begin
  inherited MouseLeave;
  // Cancel any pending hover-open; don't fire OnCloseRequested here, because the mouse
  // may be travelling INTO an open child cascade (closing it would collapse the path).
  FHoverPending := -1;
  if FHoverTimer <> nil then FHoverTimer.Enabled := False;
  SetHighlight(-1);
end;

procedure TTyMenuView.Click;
begin
  inherited Click;
  ActivateRow(FHighlight);
end;

procedure TTyMenuView.KeyDown(var Key: Word; Shift: TShiftState);
var idx: Integer;
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
        // Left: a submenu collapses back to its parent; the ROOT dropdown rotates to the
        // PREVIOUS top. The host popup decides by level (it knows if it is a child cascade).
        if Assigned(FOnNavigateLeft) then FOnNavigateLeft(Self);
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        if Assigned(FOnCloseRequested) then FOnCloseRequested(Self);
        Key := 0;
      end;
  else
    // Bare letter/digit (no Ctrl/Alt): jump to / activate the row whose mnemonic matches.
    if (Shift * [ssCtrl, ssAlt] = []) and
       (((Key >= VK_A) and (Key <= VK_Z)) or ((Key >= VK_0) and (Key <= VK_9))) then
    begin
      idx := FindMnemonicRow(UpCase(Chr(Key)));
      if idx >= 0 then begin SetHighlight(idx); ActivateRow(idx); Key := 0; end;
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
    R := Types.Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
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
        P.FillBackground(Types.Rect(R.Left + P.Scale(S.Padding.Left), SepY,
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

      RowRect := Types.Rect(R.Left + P.Scale(S.Padding.Left), RowTop(i, APPI),
        R.Right - P.Scale(S.Padding.Right), RowTop(i, APPI) + itemH);

      if tpBackground in RowStyle.Present then
        P.FillBackground(RowRect, RowStyle.Background, RowStyle.BorderRadius);

      padL := P.Scale(RowStyle.Padding.Left);
      padR := P.Scale(RowStyle.Padding.Right);

      // Check / radio glyph in the left slot.
      if FRows[i].Checked then
      begin
        if FRows[i].RadioItem then
          P.DrawGlyph(Types.Rect(RowRect.Left + padL, RowRect.Top, RowRect.Left + padL + leftSlot,
            RowRect.Bottom), tgRadioDot, RowStyle.TextColor, 2)
        else
          P.DrawGlyph(Types.Rect(RowRect.Left + padL, RowRect.Top, RowRect.Left + padL + leftSlot,
            RowRect.Bottom), tgCheck, RowStyle.TextColor, 2);
      end;

      // Caption: left-aligned after the check slot, ellipsized before the right slot.
      // A DefaultItem renders bold; otherwise honour the theme's font-weight.
      if FRows[i].DefaultItem then capWeight := 700 else capWeight := RowStyle.FontWeight;
      TextRect := Types.Rect(RowRect.Left + padL + leftSlot, RowRect.Top,
        RowRect.Right - padR - rightSlot, RowRect.Bottom);
      P.DrawText(TextRect, FRows[i].Display, RowStyle.FontName, ResolveFontSize(RowStyle),
        capWeight, RowStyle.TextColor, taLeftJustify, tlCenter, True, FRows[i].MnemonicPos);

      // Submenu arrow OR the right-aligned shortcut text in the right slot.
      if FRows[i].HasSubmenu then
        P.DrawGlyph(Types.Rect(RowRect.Right - rightSlot, RowRect.Top, RowRect.Right, RowRect.Bottom),
          tgArrowRight, RowStyle.TextColor, 2)
      else if FRows[i].ShortcutText <> '' then
        P.DrawText(Types.Rect(RowRect.Left, RowRect.Top, RowRect.Right - padR, RowRect.Bottom),
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
  FView.OnCloseChild := @HandleCloseChild;
  FView.OnNavigateAdjacentBar := @HandleNavigateAdjacent;
  FView.OnNavigateLeft := @HandleNavigateLeft;
  if FRoot <> nil then
    FView.SetRows(TyBuildMenuRows(FRoot));
end;

function TTyMenuPopup.ComputeBounds(const AAnchor: TRect;
  AWidth, AHeight, APPI: Integer; AToRight: Boolean): TRect;
var
  L, T: Integer;
  wa: TRect;
  mon: TMonitor;
begin
  // Clamp/flip against the WORK AREA of the monitor the anchor sits on, NOT the global virtual
  // desktop. With multiple monitors (GTK2 reports positions in the global coordinate space), comparing
  // a global anchor.Y against a single Screen.Height mis-flipped a low menu upward and could place the
  // popup on the wrong monitor. The anchor's-monitor work area fixes both.
  wa := Types.Rect(0, 0, Screen.Width, Screen.Height);   // fallback (headless / no monitor info)
  mon := Screen.MonitorFromPoint(Types.Point((AAnchor.Left + AAnchor.Right) div 2, AAnchor.Top));
  if mon <> nil then wa := mon.WorkareaRect;

  if AToRight then
  begin
    // A submenu sits to the RIGHT of its parent row; flip LEFT if it would overflow.
    L := AAnchor.Right;
    if L + AWidth > wa.Right then
      L := AAnchor.Left - AWidth;
  end
  else
  begin
    // A dropdown aligns its left edge with the anchor; nudge left if it overflows.
    L := AAnchor.Left;
    if L + AWidth > wa.Right then
      L := wa.Right - AWidth;
  end;
  if L < wa.Left then L := wa.Left;

  // Hang BELOW the anchor; flip ABOVE only when there's no room below AND genuinely room above.
  // (Never flip a top-anchored menu up off the bar — the GTK2 'menu opens upward' symptom, where a
  // too-small reported Screen.Height or an inflated anchor.Y falsely tripped the old unconditional flip.)
  T := AAnchor.Bottom;
  if (T + AHeight > wa.Bottom) and (AAnchor.Top - AHeight >= wa.Top) then
    T := AAnchor.Top - AHeight;
  if T < wa.Top then T := wa.Top;

  Result := Types.Rect(L, T, L + AWidth, T + AHeight);
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
  FPopupRect := R;
  FForm.SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
  FForm.Show;
  // Qt/X11 RE-PLACES + un-masks a frameless stay-on-top window at MAP time; re-assert now AND again
  // next event-loop turn (DeferredReapplyGeometry), once the native window settles. No-op on Win32/GTK2.
  FForm.SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
  // Route keyboard navigation to the dropdown: without focus, arrow/Esc keys never reach
  // TTyMenuView.KeyDown and a keypress can instead deactivate (and dismiss) the popup.
  if FView.CanFocus then FView.SetFocus;
  ApplyFormRegion(R.Right - R.Left, R.Bottom - R.Top);
  TyGeomLog(Format('Popup computed=(%d,%d %dx%d) actual=(%d,%d %dx%d) screen=%dx%d',
    [R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top,
     FForm.Left, FForm.Top, FForm.Width, FForm.Height, Screen.Width, Screen.Height]));
  Application.QueueAsyncCall(@DeferredReapplyGeometry, 0);
end;

{ Shape the popup window with a rounded region matching the popup's themed
  BorderRadius (TyMenuPopup, scaled to device PPI). Non-Windows: graceful no-op. }
procedure TTyMenuPopup.ApplyFormRegion(AWidth, AHeight: Integer);
var
  S: TTyStyleSet;
  d: Integer;
  Rgn: HRGN;
begin
  if (FForm = nil) or (not FForm.HandleAllocated) or (FView = nil) then Exit;
  { Resolve the popup's own style so the corner radius tracks the theme. The
    rendered surface (TyMenuView) and the popup-host selector (TyMenuPopup) carry
    the same radius token; use the host selector named in the spec. }
  S := FView.ActiveController.Model.ResolveStyle('TyMenuPopup', '', []);
  // Paint the window background with the popup's own surface so the corner gaps OUTSIDE the rounded
  // region are not the dark default form Color (the Linux 'black corners') if a widgetset's region
  // is a no-op; on widgetsets where the region clips (win32/gtk2/qt), the gaps are hidden anyway.
  if S.Background.Kind = tfkSolid then
    FForm.Color := TyColorToLCL(S.Background.Color);
  d := MulDiv(S.BorderRadius, FForm.Font.PixelsPerInch, 96) * 2;
  if d <= 0 then
  begin
    { Radius 0: leave rectangular (clear any region carried over from a prior open). }
    SetWindowRgn(FForm.Handle, 0, True);
    Exit;
  end;
  { +1: CreateRoundRectRgn's right/bottom extents are exclusive. SetWindowRgn takes ownership of the
    region handle, so it must not be deleted afterwards. LCLIntf routes to the widgetset: win32 =
    native region, gtk2 = gdk_window_shape_combine_region, qt = QWidget.setMask. }
  Rgn := CreateRoundRectRgn(0, 0, AWidth + 1, AHeight + 1, d, d);
  SetWindowRgn(FForm.Handle, Rgn, True);
end;

procedure TTyMenuPopup.DeferredReapplyGeometry(Data: PtrInt);
begin
  // Runs one event-loop turn after Popup's Show, by when Qt's map-time reparent/flag-recreation has
  // settled — so this SetBounds + region finally stick (on Win32/GTK2 it's a harmless re-assert).
  if (FForm = nil) or (not FForm.Visible) then Exit;
  FForm.SetBounds(FPopupRect.Left, FPopupRect.Top,
    FPopupRect.Right - FPopupRect.Left, FPopupRect.Bottom - FPopupRect.Top);
  ApplyFormRegion(FPopupRect.Right - FPopupRect.Left, FPopupRect.Bottom - FPopupRect.Top);
  TyGeomLog(Format('DeferredReapply actual=(%d,%d %dx%d)',
    [FForm.Left, FForm.Top, FForm.Width, FForm.Height]));
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
  if Assigned(FOnClose) then FOnClose(Self);   // let a host (bar) reset its open state
end;

procedure TTyMenuPopup.DeferredForceClose(Data: PtrInt);
begin
  CloseAll;   // unconditional cascade collapse after a leaf activation
end;

function TTyMenuPopup.IsOpen: Boolean;
begin
  Result := (FForm <> nil) and FForm.Visible;
end;

procedure TTyMenuPopup.DoActivateRow(AIndex: Integer);
var
  rows: TTyMenuRowArray;
  rootPopup: TTyMenuPopup;
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
  CloseAll;   // close THIS level immediately (instant feedback for the clicked level)
  if rows[AIndex].Item <> nil then
    rows[AIndex].Item.Click;   // fire the source item's OnClick (the activation)
  // Collapse the REST of the cascade (the parent dropdown(s) + reset the bar). Activating a
  // leaf in a submenu must dismiss every level above it — not just this one. Defer it and run
  // on the ROOT so we never free a popup from inside its own activation handler; the root's
  // CloseAll fires OnClose so the bar clears its open-index.
  rootPopup := Self;
  while (rootPopup.Owner <> nil) and (rootPopup.Owner is TTyMenuPopup) do
    rootPopup := TTyMenuPopup(rootPopup.Owner);
  if rootPopup <> Self then
    Application.QueueAsyncCall(@rootPopup.DeferredForceClose, 0);
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
  // Create the child's form+view and set its root BEFORE any FView access: SetRoot only
  // populates rows when FView already exists (FView is built lazily by EnsureForm), so we
  // build the view first, then root it — guaranteeing FChild.FView exists and is filled.
  FChild.EnsureForm;
  FChild.SetRoot(rows[AIndex].Item);

  // Anchor the child to the right of the parent row (screen coords). This needs a live
  // parent window: our own FView/RowTop give the row's on-screen Y. Headless callers
  // (ActivateRowForTest) have no parent window/handle, so we stop after building +
  // populating the child (above) and never compute an anchor or pop a window — which is
  // exactly what the previous FView nil-deref crashed on when FForm/FView weren't live.
  if (FForm <> nil) and FForm.HandleAllocated and (FView <> nil) then
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

function TTyMenuPopup.ChildRowCountForTest: Integer;
begin
  // Same-unit access to FChild/FView (non-strict private) + RowCount (protected).
  if (FChild = nil) or (FChild.FView = nil) then
    Result := -1
  else
    Result := FChild.FView.RowCount;
end;

procedure TTyMenuPopup.HandleActivateRow(Sender: TObject; AIndex: Integer);
begin
  DoActivateRow(AIndex);
end;

procedure TTyMenuPopup.HandleOpenSubmenu(Sender: TObject; AIndex: Integer);
begin
  DoOpenSubmenu(AIndex);
end;

function TTyMenuPopup.IsSubmenuLevel: Boolean;
begin
  // A submenu cascade is Create(parentPopup); the bar's root dropdown is Create(bar).
  Result := (Owner <> nil) and (Owner is TTyMenuPopup);
end;

procedure TTyMenuPopup.DeferredCollapseChild(Data: PtrInt);
begin
  // Free our open child cascade and return keyboard focus to THIS level. Deferred so we
  // never free a popup whose own view's KeyDown is still on the stack (cf. DeferredForceClose).
  if FChild <> nil then FreeAndNil(FChild);
  if (FForm <> nil) and FForm.Visible and (FView <> nil) and FView.CanFocus then
    FView.SetFocus;
end;

procedure TTyMenuPopup.HandleCloseRequested(Sender: TObject);
begin
  // Esc: a submenu collapses back to its parent; the root dropdown closes the whole menu.
  if IsSubmenuLevel then
    Application.QueueAsyncCall(@TTyMenuPopup(Owner).DeferredCollapseChild, 0)
  else
    CloseAll;
end;

procedure TTyMenuPopup.HandleNavigateLeft(Sender: TObject);
begin
  // Left: a submenu collapses back to its parent; the root dropdown rotates to the PREVIOUS top.
  if IsSubmenuLevel then
    Application.QueueAsyncCall(@TTyMenuPopup(Owner).DeferredCollapseChild, 0)
  else if Assigned(FOnNavigateAdjacent) then
    FOnNavigateAdjacent(Self, -1)
  else
    CloseAll;
end;

procedure TTyMenuPopup.HandleCloseChild(Sender: TObject);
begin
  // Hover moved onto a non-submenu row: collapse only the open child cascade (free it
  // and any window/handle it allocated), leaving THIS dropdown up. CloseAll would close
  // this level too — wrong while the user is still hovering inside it.
  FreeAndNil(FChild);
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
var
  rootPopup: TTyMenuPopup;
begin
  // When we open a submenu, focus moves to the CHILD popup within our own cascade, which
  // deactivates us — that is NOT a dismiss, and collapsing here would free the child while
  // it is still being shown (AV at FForm.Show). So don't decide synchronously: DEFER the
  // dismiss to the next message cycle (by then the active window has settled and we can tell
  // a cascade hand-off from a real focus loss), and run it on the ROOT popup so CloseAll
  // tears down the children without freeing a form from inside its own deactivate handler.
  rootPopup := Self;
  while (rootPopup.Owner <> nil) and (rootPopup.Owner is TTyMenuPopup) do
    rootPopup := TTyMenuPopup(rootPopup.Owner);
  Application.QueueAsyncCall(@rootPopup.DeferredDismiss, 0);
end;

procedure TTyMenuPopup.DeferredDismiss(Data: PtrInt);
var
  p: TTyMenuPopup;
  af: TCustomForm;
begin
  // Runs on the ROOT after a deactivate has settled. If the active window is still any popup
  // in our cascade (we just moved between levels / opened a submenu), it is not a dismiss —
  // stay open. Otherwise focus genuinely left the menu, so collapse the whole cascade.
  af := Screen.ActiveForm;
  p := Self;
  while p <> nil do
  begin
    if (p.FForm <> nil) and (p.FForm = af) then Exit;
    p := p.FChild;
  end;
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
  FPendingTop := -1;
  TyAccelRegister(Self);   // shared Alt-state: repaint the bar when Alt is pressed/released
  Height := 28;
end;

destructor TTyMenuBar.Destroy;
begin
  TyAccelUnregister(Self);
  Application.RemoveAsyncCalls(Self);   // cancel any pending DeferredOpenTop
  FreeAndNil(FPopup);
  inherited Destroy;
end;

function TTyMenuBar.AccelPos(AIndex: Integer): Integer;
begin
  Result := TyAccelGatePos(TopMnemonicPos(AIndex));
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
var mi: TMenuItem; pos: Integer;
begin
  mi := VisibleTopItem(AIndex);
  if mi <> nil then TyParseMnemonic(mi.Caption, Result, pos) else Result := '';
end;

function TTyMenuBar.TopMnemonic(AIndex: Integer): Char;
var mi: TMenuItem; disp: string; pos: Integer;
begin
  Result := #0;
  mi := VisibleTopItem(AIndex);
  if mi <> nil then Result := TyParseMnemonic(mi.Caption, disp, pos);
end;

function TTyMenuBar.TopMnemonicPos(AIndex: Integer): Integer;
var mi: TMenuItem; disp: string;
begin
  Result := 0;
  mi := VisibleTopItem(AIndex);
  if mi <> nil then TyParseMnemonic(mi.Caption, disp, Result);
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

procedure TTyMenuBar.HandlePopupClosed(Sender: TObject);
begin
  // The dropdown cascade collapsed (leaf activation / focus-loss dismiss / Esc). Clear the
  // open-index and repaint the active cell. Do NOT free FPopup — this fires from inside the
  // popup's own CloseAll, and the bar keeps the (now hidden) host for reuse.
  FOpenIndex := -1;
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
    FPopup.OnClose := @HandlePopupClosed;
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
    origin := ClientToScreen(Types.Point(0, 0));
    anchor := Types.Rect(origin.X + cellL, origin.Y,
      origin.X + cellL + cellW, origin.Y + Height);
    TyGeomLog(Format('OpenTop[%d] origin=(%d,%d) barH=%d anchor=(%d,%d-%d,%d) screen=%dx%d',
      [AIndex, origin.X, origin.Y, Height, anchor.Left, anchor.Top, anchor.Right, anchor.Bottom,
       Screen.Width, Screen.Height]));
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
  // Defer: we are inside the open dropdown view's KeyDown, and OpenTop may FreeAndNil(FPopup)
  // (rotating onto a childless top), which would free the very view whose KeyDown is on the stack.
  FPendingTop := idx;
  Application.QueueAsyncCall(@DeferredOpenTop, 0);
end;

procedure TTyMenuBar.DeferredOpenTop(Data: PtrInt);
begin
  if FPendingTop >= 0 then OpenTop(FPendingTop);
  FPendingTop := -1;
end;

function TTyMenuBar.DialogChar(var Message: TLMKey): Boolean;
var i: Integer; ch: Char; mi: TMenuItem;
begin
  // Only Alt+<mnemonic> opens a top menu (mirrors TCustomLabel.DialogChar); a plain keystroke
  // that reaches the form-level DialogChar broadcast must not spuriously open one.
  if KeyDataToShiftState(Message.KeyData) * [ssCtrl, ssAlt, ssShift] = [ssAlt] then
  begin
    // Message.CharCode here is the TRANSLATED character (lowercase 'f' for Alt+F), NOT a VK code:
    // map only ASCII letters/digits to an upper-cased char; anything else stays #0 (no match).
    ch := #0;
    case Message.CharCode of
      Ord('0')..Ord('9'), Ord('A')..Ord('Z'), Ord('a')..Ord('z'):
        ch := UpCase(Chr(Message.CharCode));
    end;
    if ch <> #0 then
      for i := 0 to TopCount - 1 do
      begin
        mi := VisibleTopItem(i);
        if (mi <> nil) and mi.Enabled and (TopMnemonic(i) = ch) then
        begin
          OpenTop(i);
          Exit(True);
        end;
      end;
  end;
  Result := inherited DialogChar(Message);
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
    R := Types.Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
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

      CellRect := Types.Rect(R.Left + cellL, R.Top, R.Left + cellL + cellW, R.Bottom);
      if tpBackground in CellStyle.Present then
        P.FillBackground(CellRect, CellStyle.Background, CellStyle.BorderRadius);

      padL := P.Scale(CellStyle.Padding.Left);
      P.DrawText(Types.Rect(CellRect.Left + padL, CellRect.Top, CellRect.Right, CellRect.Bottom),
        TopCaption(i), CellStyle.FontName, ResolveFontSize(CellStyle),
        CellStyle.FontWeight, CellStyle.TextColor, taLeftJustify, tlCenter, True, AccelPos(i));
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

function TTyPopupMenu.GetAbout: string;
begin
  Result := TyVersion;
end;

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
  anchor := Types.Rect(X, Y, X, Y);
  FRenderer.Popup(anchor, False);
end;

procedure TTyPopupMenu.ActivateRowForTest(AIndex: Integer);
begin
  EnsureRenderer;
  FRenderer.ActivateRowForTest(AIndex);
end;

end.
