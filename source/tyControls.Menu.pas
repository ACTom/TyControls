unit tyControls.Menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType, LCLProc, LCLIntf, LMessages, Menus,
  ImgList,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Accel,
  tyControls.PlatformWS, tyControls.ImageCollection, tyControls.ImageDraw;

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

  TTyMenuRowKind = (mrkItem, mrkSeparator, mrkHeader);
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
    ImageIndex: Integer;    // icon-column index into the menu's Images (-1 = none)
    Hint: string;           // published to Application.Hint while the row is highlighted
    AlwaysCheckable: Boolean;  // draw an empty check slot even when unchecked
    GlyphVisible: Boolean;  // TMenuItem.GlyphShowMode says this row's icon may be drawn
    { The LCL image list this row resolved to, per TMenuItem.GetImageList: the nearest
      ancestor's SubMenuImages, else the parent menu's own Images. nil when there is
      none, in which case the renderer falls back to its TTyVirtualImageList. Width is
      the list's 96-PPI image width (SubMenuImagesWidth / ImagesWidth; 0 = natural). }
    LCLImages: TCustomImageList;
    LCLImagesWidth: Integer;
  end;
  TTyMenuRowArray = array of TTyMenuRow;

{ Whether AItem's icon may be drawn at all, per TMenuItem.GlyphShowMode. This mirrors the
  private CanShowIcon nested in LCL's TMenuItem.HasIcon; HasIcon ITSELF cannot be used,
  because it also insists the icon comes from an LCL TCustomImageList and would therefore
  hide every icon this library draws out of a TTyVirtualImageList. Nothing consulted the
  mode before, so gsmNever drew the glyph anyway and the property was decoration. }
function TyMenuGlyphVisible(AItem: TMenuItem): Boolean;

{ How far a context menu's anchor moves for a given TPopupMenu.Alignment and a measured popup
  width. The renderer hangs the popup from the anchor's LEADING edge, so alignment is expressed
  by moving that edge; AAlignment is read as a READING-ORDER quantity (paLeft = "aligned to the
  reading start"), the same rule TAlignment follows through BidiFlipAlignment, so mirroring
  turns each shift round.

  Pure, and separate from PopUp, because PopUp needs a live window and this is a SIGN in a
  one-line offset -- precisely the kind of thing plans/2026-08-04-rtl-mirroring-scope.md §5
  item 2 warns has no static symptom: every screenshot is right and the menu opens on the
  wrong side of the cursor. }
function TyPopupAnchorShift(AAlignment: TPopupAlignment; AWidth: Integer;
  ARightToLeft: Boolean): Integer;

{ Flatten a root TMenuItem's visible children into render rows. Caption '-' => separator.
  When AAllowHeaders, a Caption of '-Text' (a dash followed by text) becomes a non-selectable
  SECTION HEADER captioned 'Text' (a bare '-' stays a plain separator) — the TTyMenuEx opt-in.
  (TyParseMnemonic lives in tyControls.Accel — the shared mnemonic facility.) }
function TyBuildMenuRows(ARoot: TMenuItem; AAllowHeaders: Boolean = False): TTyMenuRowArray;

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
    FImages: TCustomImageList;      // icon-column source (transient; set per popup by the host)
    FBannerCaption: string;         // decorative left-strip caption (rotated), '' = no banner text
    FBannerWidth: Integer;          // decorative left-strip width in logical px, 0 = no banner
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
    FTrackButton: TTrackButton;
    FOwnerDraw: Boolean;
    { Row sizes, one per row, valid only for (FMeasuredPPI, FMeasuredVer); FMeasuredPPI = 0
      means "none". RowTop walks every earlier row, so re-deriving a height per hop would
      make one paint O(n^2) style resolutions -- and, under OwnerDraw, would ask the app's
      OnMeasureItem that many times. Both are answered ONCE per row here. Dropped whenever
      the rows, the OwnerDraw flag or the THEME change (a hot theme reload moves the row
      height, and a cache that outlived it would paint at the old geometry). }
    FMeasured: array of TSize;
    FMeasuredPPI: Integer;
    FMeasuredVer: Cardinal;
    procedure EnsureHoverTimer;
    procedure HandleHoverTimer(Sender: TObject);
    procedure SetOwnerDraw(AValue: Boolean);
    procedure InvalidateMeasure;
    procedure EnsureMeasured(APPI: Integer);
    { Device size of the LCL image-list icons these rows resolved to, or (0,0) when no
      row has one. Drives the left-slot width and the row-height floor: an image list
      carries its own pixel size and SubMenuImagesWidth can ask for a bigger one. }
    function LCLIconSize(APPI: Integer): TSize;
    { The TyMenuItem theme states for row AIndex (disabled wins, then the highlight).
      Shared by the default row render and the owner-draw branch so both agree. }
    function RowStateSet(AIndex: Integer): TTyStateSet;
    { The same row state expressed as LCL's TOwnerDrawState, for OnDrawItem. }
    function RowOwnerDrawState(AIndex: Integer): TOwnerDrawState;
    function ItemRowHeight(APPI: Integer): Integer;
    function SeparatorHeight(APPI: Integer): Integer;
    { Widest DEFAULT item-row content in device px (no popup padding, no banner). Split
      out of MeasureWidth so the owner-draw measure can seed OnMeasureItem with it
      without re-entering MeasureWidth. }
    function ContentWidth(APPI: Integer): Integer;
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
    { Height of row AIndex in device px: the separator slot, the item height (floored at
      the icon height), or whatever OnMeasureItem answered when OwnerDraw is on. Every
      vertical seam goes through here so a variable-height owner-drawn menu still
      hit-tests where it paints. }
    function RowHeight(AIndex, APPI: Integer): Integer;
    { Device width of the left check/icon slot: the themed --menu-check-slot, widened
      when a resolved LCL image list draws wider icons than the slot reserves. }
    function LeftSlotWidth(APPI: Integer): Integer;
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
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
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
    { Whether AButton activates the row under it while this menu is up. The LEFT button
      always does (TControl.Click); the RIGHT one only under tbRightButton, which is what
      TPM_RIGHTBUTTON means on Win32 and what Qt's tbLeftButton filter says in reverse:
      tbRightButton = both buttons select, tbLeftButton = left only. }
    function ActivatesOn(AButton: TMouseButton): Boolean;
  public
    { When True, the popup surface is painted with SQUARE corners (frame radius forced to 0). The
      host popup sets this on Wayland, where the window can't be shape-masked, so a square paint
      matches the square window and avoids the rounded-paint-vs-square-window edge artifact. }
    ForceSquareSurface: Boolean;
    { Icon-column source: when set, an item's ImageIndex renders in the left slot (unless the
      item is checked, where the check glyph wins). Set transiently by the host each popup. }
    property Images: TCustomImageList read FImages write FImages;
    { Decorative left banner (classic Office style): a themed accent strip BannerWidth px wide
      down the left, with BannerCaption drawn rotated. 0 width = no banner. Set per popup. }
    property BannerCaption: string read FBannerCaption write FBannerCaption;
    property BannerWidth: Integer read FBannerWidth write FBannerWidth;
    { TPopupMenu.TrackButton, pushed here by the host each popup. }
    property TrackButton: TTrackButton read FTrackButton write FTrackButton;
    { TMenu.OwnerDraw, pushed here by the host each popup: each row's size then comes from
      OnMeasureItem and its pixels from OnDrawItem (the item's own handler, else the
      parent menu's -- TMenuItem.DoMeasureItem/DoDrawItem own that fallback). }
    property OwnerDraw: Boolean read FOwnerDraw write SetOwnerDraw;
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
    FAllowHeaders: Boolean;   // TTyMenuEx opt-in: build '-Text' items as section headers
    FImages: TCustomImageList;      // icon-column source (TTyImagesMenu/TTyMenuEx opt-in)
    FBannerCaption: string;   // decorative left-banner caption (root menu only)
    FBannerWidth: Integer;    // decorative left-banner width (logical px), 0 = none
    FOwnerDraw: Boolean;      // TMenu.OwnerDraw, forwarded to the view + submenu cascades
    FTrackButton: TTrackButton;  // TPopupMenu.TrackButton, likewise forwarded
    FRightToLeft: Boolean;    // mirrored layout, forwarded to the view + submenu cascades
    FWlParent: TCustomForm;   // GTK3/Wayland: the popup's transient parent (app form, or the parent popup for a submenu)
    FWlRect: TRect;           // GTK3/Wayland: anchor rect in FWlParent's CLIENT coords (never screen coords)
    FWlMode: TTyPopupAnchorMode; // GTK3/Wayland: drop-below (bar/context) vs fly-out-to-a-side (submenu)
    procedure EnsureForm;
    { Push the per-popup options the host set onto the live view. Called from EnsureForm
      AND from Popup: EnsureForm early-exits on every re-open, so a host that changed
      Images / OwnerDraw / TrackButton between two popups would otherwise keep showing
      the values the FIRST popup was built with. }
    procedure ApplyViewOptions;
    procedure HandleActivateRow(Sender: TObject; AIndex: Integer);
    procedure HandleOpenSubmenu(Sender: TObject; AIndex: Integer);
    procedure HandleCloseRequested(Sender: TObject);
    procedure HandleCloseChild(Sender: TObject);
    procedure HandleNavigateAdjacent(Sender: TObject; ADelta: Integer);
    procedure HandleNavigateLeft(Sender: TObject);
    function IsSubmenuLevel: Boolean;
    function RootPopup: TTyMenuPopup;
    procedure FormDeactivate(Sender: TObject);
    procedure DeferredDismiss(Data: PtrInt);
    procedure DeferredForceClose(Data: PtrInt);
    procedure DeferredCollapseChild(Data: PtrInt);
    { Qt/X11 re-places + un-masks a frameless window at MAP time, AFTER Show returns; re-assert the
      popup's bounds + rounded region on the next event-loop turn, once the native window has settled. }
    procedure DeferredReapplyGeometry(Data: PtrInt);
    { Qt clears a window's mask on every resize; with scrollable-forms (Qt6 default) the popup is
      resized by its layout AFTER Show, wiping the rounded region set in Popup/DeferredReapply and
      leaving opaque corners. Re-assert the region on every resize so it survives. Harmless re-apply
      on Win32/GTK2. }
    procedure FormResize(Sender: TObject);
  protected
    { Pure placement: turn an anchor rect (screen coords) + the popup's size into a
      screen rect, flipping ABOVE the anchor when there is no room below and (for a
      submenu, AToRight=True) LEFT of the anchor when there is no room to the right.
      Headless-testable; the live Popup calls it so on-screen sizing cannot drift. }
    function ComputeBounds(const AAnchor: TRect; AWidth, AHeight, APPI: Integer;
      AToRight: Boolean; ARightToLeft: Boolean = False): TRect;
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
    { GTK3/Wayland only: register the parent-relative anchor the NEXT Popup should use, because a
      Wayland client cannot place a top-level by the screen rect Popup otherwise takes. AParent is
      the transient parent (the app form for a bar dropdown / context menu; the PARENT POPUP's form
      for a submenu) and ARect is the anchor rect in AParent's client coords. Consumed and cleared
      by Popup; a no-op on every other widgetset (the screen rect still drives placement there). }
    procedure SetWaylandAnchor(AParent: TCustomForm; const ARect: TRect; AMode: TTyPopupAnchorMode);
    { Close this level: free the child cascade first, then hide the form (with the
      OnDeactivate handler detached around Hide), and arm the reopen guard. }
    procedure CloseAll;
    { The width this level WILL take when shown, in device px -- the same content-driven
      measure Popup uses to size the form. Public so a host can place the popup relative
      to its own right edge (TTyPopupMenu.Alignment) without duplicating the measure. }
    function MeasuredWidth: Integer;
    function IsOpen: Boolean;
    { Test seam: activate a row as if it were clicked (same path as a real click). }
    procedure ActivateRowForTest(AIndex: Integer);
    property Controller: TTyStyleController read FController write FController;
    { When True, '-Text' items build as section headers (propagated to submenu cascades). }
    property AllowHeaders: Boolean read FAllowHeaders write FAllowHeaders;
    { Icon-column source (propagated to the view + submenu cascades). }
    property Images: TCustomImageList read FImages write FImages;
    { Decorative left banner on THIS level's view (root only — not propagated to submenus). }
    property BannerCaption: string read FBannerCaption write FBannerCaption;
    property BannerWidth: Integer read FBannerWidth write FBannerWidth;
    { LCL owner-draw + track-button, forwarded to the view and to every submenu cascade
      (an owner-drawn menu is owner-drawn all the way down, as it is in the LCL). }
    property OwnerDraw: Boolean read FOwnerDraw write FOwnerDraw;
    property TrackButton: TTrackButton read FTrackButton write FTrackButton;
    { MIRRORED layout, pushed down to the view (which has no other way to learn it: the popup
      form is a bare TForm.CreateNew of ours, so it inherits no BiDiMode from the application
      window) and inherited by every submenu cascade -- a menu reads one way all the way down.
      Set by the host: TTyMenuBar from its own IsRightToLeft, TTyPopupMenu from the control
      the context menu was raised on. }
    property RightToLeft: Boolean read FRightToLeft write FRightToLeft;
    { Test seam: this level's live view, building the (hidden) host form on demand. Lets a
      headless test read what the host actually pushed into the renderer -- the wiring,
      not merely the property it was written to. }
    function ViewForTest: TTyMenuView;
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
    FHoverPollTimer: TTimer;  // non-Win32: poll the cursor to switch top menus on hover while a
                              // dropdown is open (its mouse grab starves the bar's own MouseMove)
    procedure StartHoverPoll;
    procedure StopHoverPoll;
    procedure HoverPollTick(Sender: TObject);
    procedure SetMenu(AValue: TMainMenu);
    procedure SetAutoSizeWidth(AValue: Boolean);
    { Apply content-fit sizing when enabled and Align permits it (not alTop/alBottom,
      where the LCL force-stretches the bar to the parent width). Sets Width to
      FitWidth; guarded against the Resize -> SetBounds -> Resize re-entry. }
    procedure ApplyAutoSizeWidth;
    { Index of the AIndex-th VISIBLE top item back into Menu.Items, or -1. }
    function VisibleTopItem(AIndex: Integer): TMenuItem;
    { True when the AIndex-th visible top item is right-justified (TMenuItem.RightJustify).
      Ours packed every cell left to right and ignored the flag, so the classic
      right-aligned Help / Window menu could not be built at all -- the property is
      published on TMenuItem, the designer offers it, and nothing read it. }
    function TopRightJustified(AIndex: Integer): Boolean;
    { Whether the AIndex-th visible top item is enabled. A missing item counts as
      disabled -- nothing to open is the same as not being allowed to. }
    function TopEnabled(AIndex: Integer): Boolean;
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
    { The cell's physical left edge. MIRRORED when the bar reads right-to-left, and the ONLY
      place that mirroring happens: paint, hit test and dropdown anchor all read this. }
    function TopLeft(AIndex, APPI: Integer): Integer;
    { The same in reading order, before mirroring — for measuring an extent, not placing a
      cell. See the implementation for why FitWidth may not use the mirrored one. }
    function TopLeftUnmirrored(AIndex, APPI: Integer): Integer;
    { Device-x -> top cell index, or -1 when X is past the last cell. }
    function TopAtX(AX, APPI: Integer): Integer;
    { Pure content-fit width (device px): the sum of the top-cell widths plus the bar's
      own left+right padding — i.e. TopLeftUnmirrored(last) + TopCellWidth(last) + right
      padding. The width an AutoSizeWidth bar shrinks to; headless-testable like TopLeft/TopAtX. }
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
    { Test seams. OpenTop is the single door into a top-level item -- click, hover-switch
      and Alt mnemonic all arrive there -- so driving it directly exercises the disabled
      and childless rules without a window handle or a real menu grab. }
    procedure OpenTopForTest(AIndex: Integer);
    function TopEnabledForTest(AIndex: Integer): Boolean;
    function TopRightJustifiedForTest(AIndex: Integer): Boolean;
    function TopLeftForTest(AIndex, APPI: Integer): Integer;
    { Which top's dropdown is open, or -1. The observable that says whether OpenTop was
      allowed to proceed -- a disabled top with children must leave this at -1. }
    function OpenIndexForTest: Integer;
    { Test seam: the dropdown host OpenTop built, or nil when none has been opened yet.
      Lets a test read what the bar pushed into the shared renderer (e.g. the associated
      TMainMenu's OwnerDraw) without a real menu grab. }
    function PopupForTest: TTyMenuPopup;
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
    { The constructor turns this on (the bar walks its top cells with the arrow keys);
      declaring the default to match is what lets a host turn it OFF in the .lfm — against
      the inherited `default False` that value is dropped as "already the default" and the
      constructor's True wins again at run time. }
    property TabStop default True;
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
    { Which way this menu reads. A TPopupMenu is a component, not a control, so it has no
      BiDiMode of its own; a context menu belongs to whatever it was raised over, which LCL
      records in PopupComponent (include/control.inc:2496) before popping. Falls back to the
      owner, which is what a menu invoked from code (PopUp called directly) has. }
    function ResolveRightToLeft: Boolean;
    procedure EnsureRenderer;
    { Wired to the renderer's OnClose so the LCL side of the protocol -- OnClose,
      and clearing the global ActivePopupMenu -- runs when the themed popup goes
      away, whichever way it went away (activation, Esc, click-outside). }
    procedure HandleRendererClosed(Sender: TObject);
  protected
    { Hook for subclasses to configure the shared renderer (e.g. opt into section headers)
      after its controller is set and BEFORE its rows are built. Base does nothing. }
    procedure ConfigureRenderer(ARenderer: TTyMenuPopup); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Show the themed context menu at screen point (X, Y) instead of the native menu.

      This runs the LCL popup protocol before handing off to the themed renderer, and
      the ORDER is the point. It used to be EnsureRenderer + Popup and nothing else, so:
      OnPopup never fired; PopupPoint stayed at whatever it was last set to; Close was a
      silent no-op and OnClose never fired; and action-linked items never refreshed their
      Enabled/Caption/Checked. Building the rows first also meant that even a handler
      that DID fire could not usefully add or remove items -- the snapshot was already
      taken. OnPopup exists to populate a context menu from the thing under the cursor;
      that is most of what a context menu is for. }
    procedure PopUp(X, Y: Integer); override;
    { Test seam: activate the row at AIndex exactly as choosing it in the themed popup
      would (fires the source item's OnClick). Mirrors TTyMenuPopup.ActivateRowForTest. }
    procedure ActivateRowForTest(AIndex: Integer);
    { Test seam: the shared themed renderer, built + configured on demand (the same
      EnsureRenderer a real PopUp runs). Mirrors ActivateRowForTest. }
    function RendererForTest: TTyMenuPopup;
    function GetVersion: string;
  published
    { Read-only library version (TyVersion); the design-time editor for this property opens
      the About dialog. }
    property Version: string read GetVersion;
    { The .tycss style controller the themed popup resolves its tokens through. }
    property Controller: TTyStyleController read FController write FController;
  end;

  { Image-list-backed themed context menu: renders each item's ImageIndex icon (from Images --
    a TTyVirtualImageList draws its vector exactly; a plain LCL list is materialised) in the left
    slot; a checked item shows its check glyph instead.
    Same LCL TPopupMenu model + Controller; assign it to a control's PopupMenu like TTyPopupMenu. }
  TTyImagesMenu = class(TTyPopupMenu)
  private
    FImages: TCustomImageList;
    procedure SetImages(AValue: TCustomImageList);
  protected
    procedure ConfigureRenderer(ARenderer: TTyMenuPopup); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  published
    { The icon source; each item's ImageIndex draws from here. }
    property Images: TCustomImageList read FImages write SetImages;
  end;

  { Enhanced themed context menu: everything TTyImagesMenu does (icon column) PLUS SECTION HEADERS
    ('-Text' captions → non-selectable section labels; a bare '-' stays a separator) and an
    optional decorative SIDE BANNER (a themed accent strip down the left with a rotated caption). }
  TTyMenuEx = class(TTyImagesMenu)
  private
    FBannerCaption: string;
    FBannerWidth: Integer;
  protected
    procedure ConfigureRenderer(ARenderer: TTyMenuPopup); override;
  published
    { Decorative left banner: a BannerWidth-px accent strip with BannerCaption drawn rotated
      down it (classic Office look). BannerWidth = 0 (default) = no banner. }
    property BannerCaption: string read FBannerCaption write FBannerCaption;
    property BannerWidth: Integer read FBannerWidth write FBannerWidth default 0;
  end;

implementation

// Rounded popup corners use the CROSS-PLATFORM LCLIntf SetWindowRgn/CreateRoundRectRgn (the
// win32/gtk2/qt widgetsets all implement them) — no Windows unit needed. (Rect()/Point() call
// sites remain qualified Types.* — harmless now that the Windows POINT=TPOINT shadow is gone.)
uses Math, Themes, BGRABitmap, BGRABitmapTypes;

type
  { Reaches TMenuItem's protected InitiateActions / DoDrawItem / DoMeasureItem. Those three
    are declared protected in another unit, so a same-unit descendant is the way in -- the
    LCL itself calls them from inside Menus. }
  TMenuItemAccess = class(TMenuItem);

function TyPopupAnchorShift(AAlignment: TPopupAlignment; AWidth: Integer;
  ARightToLeft: Boolean): Integer;
begin
  { paLeft is the reading start and the renderer already hangs the popup from there, whichever
    end that is -- so it never shifts. paCenter is half of paRight's shift, and mirroring
    negates both: one sign, one place, all three cases. }
  if AAlignment = paLeft then Exit(0);
  Result := AWidth;
  if AAlignment <> paRight then Result := Result div 2;   // paCenter
  if not ARightToLeft then Result := -Result;
end;

function TyMenuGlyphVisible(AItem: TMenuItem): Boolean;

  { LCL's own system rule (SystemShowMenuGlyphs in menuitem.inc), which is not exported. }
  function SystemShowsGlyphs: Boolean;
  begin
    Result := ThemeServices.GetOption(toShowMenuImages) = 1;
  end;

begin
  Result := False;
  if AItem = nil then Exit;
  { At design time every glyph shows regardless of the run-time policy -- an author who
    cannot see the icons cannot arrange them. LCL makes the same exception. }
  if csDesigning in AItem.ComponentState then Exit(True);
  case AItem.GlyphShowMode of
    gsmNever:  Result := False;
    gsmAlways: Result := True;
    gsmSystem: Result := SystemShowsGlyphs;
  else  // gsmApplication (the TMenuItem default): defer to Application.ShowMenuGlyphs
    case Application.ShowMenuGlyphs of
      sbgNever:  Result := False;
      sbgSystem: Result := SystemShowsGlyphs;
    else         Result := True;   // sbgAlways
    end;
  end;
end;

{ True when AItem has an owner-draw painter reachable: its own OnDrawItem, else the parent
  menu's (the fallback TMenuItem.DoDrawItem implements). Asked BEFORE the default row
  content is skipped -- DoDrawItem only reports "no handler" after the fact, and a row
  skipped for a handler that never ran would paint as an empty gap. It also keeps us off
  DoDrawItem's unguarded GetParentMenu deref when an item has no menu at all. }
function MenuItemHasDrawHandler(AItem: TMenuItem): Boolean;
var
  m: TMenu;
begin
  Result := False;
  if AItem = nil then Exit;
  if Assigned(AItem.OnDrawItem) then Exit(True);
  m := AItem.GetParentMenu;
  Result := (m <> nil) and Assigned(m.OnDrawItem);
end;

{ The OnMeasureItem twin of MenuItemHasDrawHandler, and the same nil-menu guard. }
function MenuItemHasMeasureHandler(AItem: TMenuItem): Boolean;
var
  m: TMenu;
begin
  Result := False;
  if AItem = nil then Exit;
  if Assigned(AItem.OnMeasureItem) then Exit(True);
  m := AItem.GetParentMenu;
  Result := (m <> nil) and Assigned(m.OnMeasureItem);
end;

function TyBuildMenuRows(ARoot: TMenuItem; AAllowHeaders: Boolean): TTyMenuRowArray;
var
  i, n, imgW: Integer;
  mi: TMenuItem;
  imgList: TCustomImageList;
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
    Result[n].ImageIndex := -1;   // Default() would zero it, but 0 is a valid image index
    if mi.IsLine then
      Result[n].Kind := mrkSeparator
    else if AAllowHeaders and (Length(mi.Caption) > 1) and (mi.Caption[1] = '-') then
    begin
      // '-Text' => section header captioned 'Text' (a bare '-' was caught by IsLine above).
      Result[n].Kind := mrkHeader;
      Result[n].Caption := Trim(Copy(mi.Caption, 2, Length(mi.Caption)));
      // Strip any '&' for display; the parsed mnemonic is stored but unused (headers aren't activatable).
      Result[n].Mnemonic := TyParseMnemonic(Result[n].Caption, Result[n].Display, Result[n].MnemonicPos);
    end
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
      Result[n].ImageIndex := mi.ImageIndex;
      Result[n].Hint := mi.Hint;
      { A menu item that can be toggled should LOOK toggleable before it is toggled --
        otherwise "View > Toolbar" and "File > Open" are indistinguishable until you have
        already clicked one.

        BOTH of the LCL flags that say so are read, because LCL reads both:
        TMenuItem.IsCheckItem is `Checked or RadioItem or AutoCheck or ShowAlwaysCheckable`
        (menuitem.inc:1247-1250). ShowAlwaysCheckable (menus.pp:345) is the EXPLICIT
        opt-in -- "this is a toggle, show the box" -- and it was the one still being
        ignored: it is published, the Object Inspector offers it, and only AutoCheck (the
        flag that also makes the item toggle ITSELF on click, which many apps deliberately
        do not want) reached the paint. Setting the property meant for exactly this job
        drew nothing. }
      Result[n].AlwaysCheckable := mi.AutoCheck or mi.ShowAlwaysCheckable;
      Result[n].GlyphVisible := TyMenuGlyphVisible(mi);
      { The icon SOURCE is a per-item question in the LCL, not a per-menu one: GetImageList
        walks the parent chain for the nearest SubMenuImages and only then falls back to the
        menu's own Images. Resolving it here is what gives a submenu its own icon set -- the
        cascade used to inherit the level above unconditionally, so SubMenuImages could not
        change anything. GetImageList leaves aImagesWidth UNTOUCHED on the nil path (an out
        parameter of ordinal type is not zeroed), hence the explicit reset. }
      mi.GetImageList(imgList, imgW);
      if imgList = nil then imgW := 0;
      Result[n].LCLImages := imgList;
      Result[n].LCLImagesWidth := imgW;
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
  FTrackButton := tbRightButton;   // the TPopupMenu.TrackButton default
  InvalidateMeasure;
  // Share the Alt-state so the row underlines appear/disappear as Alt is pressed/released
  // while the popup is open -- and are HIDDEN when it opens by mouse (no Alt), like Windows.
  TyAccelRegister(Self);
end;

destructor TTyMenuView.Destroy;
begin
  // FHoverTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown (ToggleSwitch).
  FreeAndNil(FHoverTimer);
  TyAccelUnregister(Self);
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
  InvalidateMeasure;
  Invalidate;
end;

procedure TTyMenuView.SetOwnerDraw(AValue: Boolean);
begin
  if FOwnerDraw = AValue then Exit;
  FOwnerDraw := AValue;
  InvalidateMeasure;   // row heights are the app's answer now (or ours again)
  Invalidate;
end;

procedure TTyMenuView.InvalidateMeasure;
begin
  SetLength(FMeasured, 0);
  FMeasuredPPI := 0;   // no live PPI is 0, so the next EnsureMeasured always recomputes
  FMeasuredVer := 0;
end;

function TTyMenuView.ActivatesOn(AButton: TMouseButton): Boolean;
begin
  case AButton of
    mbLeft:  Result := True;   // under either setting; this is TControl.Click's path
    mbRight: Result := FTrackButton = tbRightButton;
  else
    Result := False;
  end;
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
  fontLogical, textPx, padPx, iconH: Integer;
begin
  S := ActiveController.Model.ResolveStyle('TyMenuItem', '', []);
  fontLogical := S.FontSize;
  if fontLogical <= 0 then fontLogical := ResolveFontSize(S);
  if fontLogical <= 0 then fontLogical := 9;
  // Same logical->device text-height formula the painter uses for FontHeight.
  textPx := MulDiv(Round(fontLogical * 96 / 72), APPI, 96);
  padPx := MulDiv(S.Padding.Top, APPI, 96) + MulDiv(S.Padding.Bottom, APPI, 96);
  Result := textPx + padPx;
  { An LCL image list brings its own pixel size, and SubMenuImagesWidth can ask for a
    bigger one; a 32px icon in a text-height row would be clipped top and bottom. The
    themed text+padding height is the FLOOR, not the ceiling -- no visual value is
    hard-coded here, the extra comes from the app's own image list. }
  iconH := LCLIconSize(APPI).cy;
  if iconH > Result then Result := iconH;
  if Result < 1 then Result := 1;
end;

function TTyMenuView.SeparatorHeight(APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric('--menu-separator-height', TyMenuSeparatorHeight),
    APPI, 96);
end;

function TTyMenuView.LCLIconSize(APPI: Integer): TSize;
var
  i: Integer;
  Res: TScaledImageListResolution;
begin
  Result.cx := 0;
  Result.cy := 0;
  for i := 0 to High(FRows) do
    if (FRows[i].Kind = mrkItem) and FRows[i].GlyphVisible and (FRows[i].LCLImages <> nil)
       and (FRows[i].ImageIndex >= 0) and (FRows[i].ImageIndex < FRows[i].LCLImages.Count) then
    begin
      { LCLImagesWidth is the 96-PPI image width the LCL contract asks for; 0 means "the
        list's own", which GetWidthForPPI already handles. Canvas factor 1: we draw onto
        the control canvas, not a scaled backing store. }
      Res := FRows[i].LCLImages.ResolutionForPPI[FRows[i].LCLImagesWidth, APPI, 1];
      if Res.Width > Result.cx then Result.cx := Res.Width;
      if Res.Height > Result.cy then Result.cy := Res.Height;
    end;
end;

function TTyMenuView.LeftSlotWidth(APPI: Integer): Integer;
var
  iconW: Integer;
begin
  Result := MulDiv(ActiveController.Metric('--menu-check-slot', TyMenuCheckSlot), APPI, 96);
  // Same floor rule as ItemRowHeight: a wider icon would otherwise paint over the caption.
  iconW := LCLIconSize(APPI).cx;
  if iconW > Result then Result := iconW;
end;

function TTyMenuView.RowHeight(AIndex, APPI: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then Exit(0);
  EnsureMeasured(APPI);
  Result := Max(1, FMeasured[AIndex].cy);
end;

procedure TTyMenuView.EnsureMeasured(APPI: Integer);
var
  i, defW, itemH, sepH, w, h: Integer;
begin
  if (FMeasuredPPI = APPI) and (FMeasuredVer = ActiveController.Model.ThemeVersion)
     and (Length(FMeasured) = Length(FRows)) then Exit;
  SetLength(FMeasured, Length(FRows));
  // Resolved ONCE, not once per row: both walk the style model.
  itemH := ItemRowHeight(APPI);
  sepH := SeparatorHeight(APPI);
  defW := 0;
  if FOwnerDraw then defW := ContentWidth(APPI);   // only owner-draw seeds a width
  for i := 0 to High(FRows) do
  begin
    if FRows[i].Kind = mrkSeparator then h := sepH else h := itemH;
    FMeasured[i].cx := defW;
    FMeasured[i].cy := h;
    if not FOwnerDraw then Continue;   // OwnerDraw is the gate on the whole protocol
    // A section header is a TyControls-only '-Text' row with no LCL counterpart, so the
    // LCL owner-draw protocol does not speak for it.
    if FRows[i].Kind = mrkHeader then Continue;
    if not MenuItemHasMeasureHandler(FRows[i].Item) then Continue;
    { LCL seeds the handler with the size the menu would have used and lets it adjust
      either axis (win32wsmenus does exactly this), so a handler that only wants a taller
      row does not have to re-derive the width. }
    w := defW;
    if TMenuItemAccess(FRows[i].Item).DoMeasureItem(Canvas, w, h) then
    begin
      if w > 0 then FMeasured[i].cx := w;
      if h > 0 then FMeasured[i].cy := h;
    end;
  end;
  FMeasuredPPI := APPI;
  FMeasuredVer := ActiveController.Model.ThemeVersion;
end;

function TTyMenuView.MeasureHeight(APPI: Integer): Integer;
var
  S, BannerStyle: TTyStyleSet;
  i, bannerNeed: Integer;
begin
  // Vertical chrome = the TyMenuView (popup) top+bottom padding.
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Top, APPI, 96) + MulDiv(S.Padding.Bottom, APPI, 96);
  for i := 0 to High(FRows) do
    Inc(Result, RowHeight(i, APPI));
  // The decorative banner caption is drawn ROTATED up the side strip, so the popup must be at
  // least as TALL as the caption is WIDE -- a short menu (few rows) otherwise clips it. Floor
  // the height to the measured caption plus the 8px end insets TextOutAngle anchors within.
  if (FBannerWidth > 0) and (FBannerCaption <> '') then
  begin
    BannerStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', [tysActive]);
    bannerNeed := TyMeasureRenderedTextWidth(FBannerCaption, BannerStyle.FontName,
        ResolveFontSize(BannerStyle) + 1, 600, APPI) + MulDiv(16, APPI, 96);
    if Result < bannerNeed then Result := bannerNeed;
  end;
end;

function TTyMenuView.ContentWidth(APPI: Integer): Integer;
var
  RowStyle: TTyStyleSet;
  Bmp: TBGRABitmap;
  i, effSize, capW, scW, padLR, leftSlot, rightSlot, gap: Integer;
begin
  // Each row's content = check slot + caption + (gap + shortcut) + arrow slot, themed
  // via TyMenuItem; the widest row wins.
  Result := 0;
  RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', []);
  effSize := ResolveFontSize(RowStyle);
  padLR := MulDiv(RowStyle.Padding.Left, APPI, 96) + MulDiv(RowStyle.Padding.Right, APPI, 96);
  leftSlot := LeftSlotWidth(APPI);
  rightSlot := MulDiv(ActiveController.Metric('--menu-arrow-slot', TyMenuArrowSlot), APPI, 96);
  gap := MulDiv(ActiveController.Metric('--menu-shortcut-gap', TyMenuShortcutGap), APPI, 96);

  Bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(Bmp, RowStyle.FontName, effSize, RowStyle.FontWeight, APPI);
    for i := 0 to High(FRows) do
    begin
      if FRows[i].Kind <> mrkItem then Continue;
      capW := 0;
      if FRows[i].Display <> '' then capW := Bmp.TextSize(FRows[i].Display).cx;
      scW := 0;
      if FRows[i].ShortcutText <> '' then scW := gap + Bmp.TextSize(FRows[i].ShortcutText).cx;
      Result := Max(Result, padLR + leftSlot + capW + scW + rightSlot);
    end;
  finally
    Bmp.Free;
  end;
end;

function TTyMenuView.MeasureWidth(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  i, rowW: Integer;
begin
  // Vertical chrome (popup) left+right padding bounds every row.
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Left, APPI, 96) + MulDiv(S.Padding.Right, APPI, 96);
  rowW := ContentWidth(APPI);
  { OnMeasureItem answers a WIDTH as well as a height, and a row wider than the default
    would be clipped by the popup if only the height were honoured. }
  EnsureMeasured(APPI);
  for i := 0 to High(FMeasured) do
    rowW := Max(rowW, FMeasured[i].cx);
  Inc(Result, rowW);
  if FBannerWidth > 0 then
    Inc(Result, MulDiv(FBannerWidth, APPI, 96));   // reserve the decorative left banner
  if Result < 1 then Result := 1;
end;

function TTyMenuView.RowTop(AIndex, APPI: Integer): Integer;
var
  S: TTyStyleSet;
  i: Integer;
begin
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Top, APPI, 96);
  for i := 0 to AIndex - 1 do
  begin
    if (i < 0) or (i > High(FRows)) then Break;
    Inc(Result, RowHeight(i, APPI));
  end;
end;

function TTyMenuView.RowAtY(AY, APPI: Integer): Integer;
var
  i, rowT, h: Integer;
begin
  Result := -1;
  for i := 0 to High(FRows) do
  begin
    rowT := RowTop(i, APPI);
    h := RowHeight(i, APPI);
    if (AY >= rowT) and (AY < rowT + h) then
    begin
      // Separators and section headers are not selectable.
      if FRows[i].Kind <> mrkItem then Exit(-1);
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
  { Publish the highlighted item's Hint, which is how a status bar or a long-hint panel
    describes the command under the cursor. TMenuItem.Hint was carried on the row and read
    by nobody, so setting it in the designer did exactly nothing. Clearing on -1 matters as
    much as setting: a stale description of a command no longer under the pointer is worse
    than none. }
  if (FHighlight >= 0) and (FHighlight <= High(FRows)) then
    Application.Hint := FRows[FHighlight].Hint
  else
    Application.Hint := '';
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

procedure TTyMenuView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  { Rows were only ever activated through TControl.Click, which the LCL raises for the
    LEFT button alone. So under tbRightButton -- the TPopupMenu default, and what
    TPM_RIGHTBUTTON means on Win32: BOTH buttons select -- the ordinary "hold the right
    button down, drag onto a row, let go" gesture did nothing at all, and setting
    TrackButton to tbLeftButton changed nothing either, because nothing read it.
    Take the position from the release point: on a press-and-drag the highlight may
    never have been set by a MouseMove. }
  if (Button = mbRight) and ActivatesOn(mbRight) then
  begin
    SetHighlight(RowAtY(Y, Font.PixelsPerInch));
    ActivateRow(FHighlight);
  end;
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
    VK_RIGHT, VK_LEFT:
      begin
        { MIRRORING: these are LAYOUT arrows, not text arrows (plans/2026-08-04-rtl-mirroring
          -scope.md §6.3 item 4) -- a cascade opens toward the READING end, so on a mirrored
          menu the key that goes deeper is LEFT and the key that returns to the parent is
          RIGHT. Left unswapped, a right-to-left user has no keyboard route into a submenu at
          all: the failure is total, not cosmetic, and invisible in any screenshot. }
        if (Key = VK_RIGHT) <> IsRightToLeft then
        begin
          // Deeper: on a submenu row, open it; otherwise this is a bar-level "next top".
          if IsSelectable(FHighlight) and FRows[FHighlight].HasSubmenu then
          begin
            if Assigned(FOnOpenSubmenu) then FOnOpenSubmenu(Self, FHighlight);
          end
          else if Assigned(FOnNavigateAdjacentBar) then
            FOnNavigateAdjacentBar(Self, +1);
        end
        else
          // Back: a submenu collapses to its parent; the ROOT dropdown rotates to the
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

function TTyMenuView.RowStateSet(AIndex: Integer): TTyStateSet;
begin
  Result := [];
  if (AIndex < 0) or (AIndex > High(FRows)) or (FRows[AIndex].Kind <> mrkItem) then
    Include(Result, tysNormal)
  else if not FRows[AIndex].Enabled then
    Include(Result, tysDisabled)
  else if AIndex = FHighlight then
    Include(Result, tysActive)
  else
    Include(Result, tysNormal);
end;

function TTyMenuView.RowOwnerDrawState(AIndex: Integer): TOwnerDrawState;
begin
  { odBackgroundPainted always: the row's themed background goes down before the handler
    runs, so a handler that only writes text still sits on the right highlight -- and it
    has to be TOLD, or it will paint one of its own over ours. }
  Result := [odBackgroundPainted];
  if (AIndex < 0) or (AIndex > High(FRows)) or (FRows[AIndex].Kind <> mrkItem) then Exit;
  if not FRows[AIndex].Enabled then
    Result := Result + [odDisabled, odGrayed]
  else if AIndex = FHighlight then
    Include(Result, odSelected);
  if FRows[AIndex].Checked then Include(Result, odChecked);
  if FRows[AIndex].DefaultItem then Include(Result, odDefault);
end;

procedure TTyMenuView.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, RowStyle, BannerStyle: TTyStyleSet;
  R, RowRect, TextRect: TRect;
  i, rowT, rowH, padL, padR, leftSlot, rightSlot, capWeight, iconSz, bannerPx: Integer;
  RowStates: TTyStateSet;
  SepFill: TTyFill;
  SepY: Integer;
  ownerDrawOn: Boolean;
  { Both GDI passes are COLLECTED here and run after P.EndPaint: anything drawn straight
    to ACanvas during the loop is erased by EndPaint's blit of the BGRA layer (the same
    trap the tree view's node icons hit). Rects are painter-local, offset by ARect below. }
  pendingIcon: array of record Res: TScaledImageListResolution; Idx, X, Y: Integer;
    Enabled: Boolean; Clip: TRect; end;
  pendingIconCount: Integer;
  pendingDraw: array of record Item: TMenuItem; R: TRect; St: TOwnerDrawState; end;
  pendingDrawCount: Integer;
  k: Integer;
  IconRes: TScaledImageListResolution;
  rtl: Boolean;
  Slot, Banner: TRect;

  { Reflect one rect inside ABox when this frame is mirrored — LCL's BidiFlipRect
    (controls.pp:2966). Applied to EVERY x a row lays out rather than to a chosen few, so a
    slot cannot be the one somebody forgot, and applied to the finished left-to-right rect so
    the row's own paddings and gaps come out as their own mirror image. The identity when the
    menu reads left-to-right, which is why an unmirrored popup renders exactly as before. }
  function Mir(const R, ABox: TRect): TRect;
  begin
    if rtl then Result := BidiFlipRect(R, ABox, True) else Result := R;
  end;

begin
  P := TTyPainter.Create;
  try
    R := Types.Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    { MIRRORING: the check/icon slot moves to the right, the shortcut text and the submenu
      arrow to the left, and the arrow turns round. There is no row-internal HIT TEST to keep
      in step — RowAtY answers from y alone and MouseUp uses only y — which is what makes
      moving these slots a safe change rather than the paint half of a split. Direction comes
      from this view's own BiDiMode, which the host popup pushes down (ApplyViewOptions);
      the popup form is created by us, so nothing else would ever set it. }
    rtl := IsRightToLeft;
    P.BeginPaint(ACanvas, ARect, APPI, rtl);
    // Surface: the TyMenuView (popup) background/border/radius from its own tokens.
    S := CurrentStyle;
    // Wayland: the window can't be shape-masked, so paint the surface SQUARE to match it (no edge).
    // Per-corner Radius wins in TyEffectiveCorners, so zero BOTH it and BorderRadius.
    if ForceSquareSurface then
    begin
      S.BorderRadius := 0;
      S.Radius := Default(TTyCorners);
    end;
    DrawFrame(P, R, S);

    // Decorative left banner (classic Office style): a themed accent strip that reuses the
    // TyMenuItem:active bg/text (NO new theme token), with the caption drawn rotated down it.
    // Every row's content is already shifted right by bannerPx. bannerPx = 0 disables it.
    bannerPx := P.Scale(FBannerWidth);
    if bannerPx < 0 then bannerPx := 0;   // a negative width must not push rows left of the frame
    if bannerPx > 0 then
    begin
      BannerStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', [tysActive]);
      // The strip is on the READING-start side, so it swaps ends with the rows it indents.
      Banner := Mir(Types.Rect(R.Left, R.Top, R.Left + bannerPx, R.Bottom), R);
      P.FillBackground(Banner, BannerStyle.Background, 0);
      if FBannerCaption <> '' then
      begin
        TyConfigureTextFont(P.Bitmap, BannerStyle.FontName, ResolveFontSize(BannerStyle) + 1, 600, APPI);
        // 90° CCW: reads bottom-to-top up the strip, anchored near the bottom, centered across it.
        // The ROTATION is not mirrored -- a vertical banner reads bottom-to-top in either
        // direction; only which end of the popup it decorates changes.
        P.Bitmap.TextOutAngle(Banner.Left + bannerPx div 2, R.Bottom - P.Scale(8), 900,
          FBannerCaption, TyColorToBGRA(BannerStyle.TextColor), taLeftJustify);
      end;
    end;

    leftSlot := LeftSlotWidth(APPI);
    rightSlot := P.Scale(ActiveController.Metric('--menu-arrow-slot', TyMenuArrowSlot));
    ownerDrawOn := FOwnerDraw;
    SetLength(pendingIcon, 0);
    pendingIconCount := 0;
    SetLength(pendingDraw, 0);
    pendingDrawCount := 0;

    for i := 0 to High(FRows) do
    begin
      rowT := RowTop(i, APPI);
      rowH := RowHeight(i, APPI);
      RowRect := Mir(Types.Rect(R.Left + bannerPx + P.Scale(S.Padding.Left), rowT,
        R.Right - P.Scale(S.Padding.Right), rowT + rowH), R);

      { OwnerDraw: this row's content belongs to the app. The themed row background still
        goes down (odBackgroundPainted says so), then the handler runs after EndPaint.
        A SECTION HEADER is skipped: '-Text' is a TyControls-only row kind with no LCL
        counterpart, so the LCL owner-draw protocol does not speak for it. }
      if ownerDrawOn and (FRows[i].Kind <> mrkHeader)
         and MenuItemHasDrawHandler(FRows[i].Item) then
      begin
        RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', RowStateSet(i));
        if tpBackground in RowStyle.Present then
          P.FillBackground(RowRect, RowStyle.Background, RowStyle.BorderRadius);
        if pendingDrawCount = Length(pendingDraw) then
          SetLength(pendingDraw, Length(pendingDraw) + 8);
        pendingDraw[pendingDrawCount].Item := FRows[i].Item;
        pendingDraw[pendingDrawCount].R := RowRect;
        pendingDraw[pendingDrawCount].St := RowOwnerDrawState(i);
        Inc(pendingDrawCount);
        Continue;
      end;

      if FRows[i].Kind = mrkSeparator then
      begin
        // A 1px themed line centered in the separator slot, using the TyMenuItem
        // border color (a structural divider color, not a hard-coded value).
        RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', []);
        SepY := rowT + rowH div 2;
        SepFill := Default(TTyFill);
        SepFill.Kind := tfkSolid;
        SepFill.Color := RowStyle.BorderColor;
        // Same horizontal span as the row (already mirrored), so the two cannot disagree.
        P.FillBackground(Types.Rect(RowRect.Left, SepY,
          RowRect.Right, SepY + Max(1, P.Scale(1))), SepFill, 0);
        Continue;
      end;

      if FRows[i].Kind = mrkHeader then
      begin
        // Section header: a non-interactive, muted + bold label (TyMenuItem :disabled color).
        RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', [tysDisabled]);
        padL := P.Scale(RowStyle.Padding.Left);
        P.DrawText(Mir(Types.Rect(RowRect.Left + padL, RowRect.Top, RowRect.Right, RowRect.Bottom), RowRect),
          FRows[i].Display, RowStyle.FontName, ResolveFontSize(RowStyle),
          700, RowStyle.TextColor, taLeftJustify, tlCenter, True);
        Continue;
      end;

      // Resolve TyMenuItem in the row's interaction state.
      RowStates := RowStateSet(i);
      RowStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', RowStates);

      if tpBackground in RowStyle.Present then
        P.FillBackground(RowRect, RowStyle.Background, RowStyle.BorderRadius);

      padL := P.Scale(RowStyle.Padding.Left);
      padR := P.Scale(RowStyle.Padding.Right);

      // Check / radio glyph OR the item's icon in the LEADING slot (a check wins when both apply).
      Slot := Mir(Types.Rect(RowRect.Left + padL, RowRect.Top,
        RowRect.Left + padL + leftSlot, RowRect.Bottom), RowRect);
      if FRows[i].Checked then
      begin
        if FRows[i].RadioItem then
          P.DrawGlyph(Slot, tgRadioDot, RowStyle.TextColor, 2)
        else
          P.DrawGlyph(Slot, tgCheck, RowStyle.TextColor, 2);
      end
      else if FRows[i].AlwaysCheckable then
        { An UNCHECKED but checkable item draws an empty box, so the user can see that this
          command toggles BEFORE clicking it -- otherwise "View > Toolbar" and "File > Open"
          look identical until one of them has already been used. Set by either LCL flag
          that declares the item checkable: ShowAlwaysCheckable or AutoCheck. }
        P.StrokeBorder(Types.Rect(Slot.Left + P.Scale(3),
          RowRect.Top + (rowH - leftSlot) div 2 + P.Scale(3),
          Slot.Right - P.Scale(3),
          RowRect.Top + (rowH + leftSlot) div 2 - P.Scale(3)), 2, 1, RowStyle.TextColor)
      { GlyphShowMode decides whether this item takes part in the icon column at all.
        Nothing consulted it before, so gsmNever drew the icon anyway. }
      else if FRows[i].GlyphVisible and (FRows[i].LCLImages <> nil)
              and (FRows[i].ImageIndex >= 0)
              and (FRows[i].ImageIndex < FRows[i].LCLImages.Count) then
      begin
        { An LCL image list resolved for THIS row (SubMenuImages walked up the parent
          chain, else the menu's Images) wins over the library's TTyVirtualImageList: a
          SubMenuImages is a deliberate per-submenu override, and TTyImagesMenu.Images
          shadows TMenu.Images so the two cannot collide by accident from the designer.
          It is a GDI list, so it is collected and drawn after EndPaint. }
        IconRes := FRows[i].LCLImages.ResolutionForPPI[FRows[i].LCLImagesWidth, APPI, 1];
        if pendingIconCount = Length(pendingIcon) then
          SetLength(pendingIcon, Length(pendingIcon) + 8);
        pendingIcon[pendingIconCount].Res := IconRes;
        pendingIcon[pendingIconCount].Idx := FRows[i].ImageIndex;
        { The GDI pass runs after EndPaint, on the composited canvas, and it has to be
          mirrored HERE with everything else: it is the only piece of a row whose position is
          carried out of the loop as a bare point rather than a rect. Centred in the slot the
          check glyph would have used, so an icon row and a checked row line up either way. }
        pendingIcon[pendingIconCount].X :=
          Slot.Left + ((Slot.Right - Slot.Left) - IconRes.Width) div 2;
        pendingIcon[pendingIconCount].Y := RowRect.Top + (rowH - IconRes.Height) div 2;
        { NOTE the parameter. TScaledImageListResolution.Draw's 5th argument is AEnabled,
          NOT "greyed" -- it also has a TGraphicsDrawEffect overload, so passing the wrong
          sense here compiles cleanly and draws every icon disabled. A disabled row wants
          the greyed icon, which is Enabled = False. }
        pendingIcon[pendingIconCount].Enabled := FRows[i].Enabled;
        pendingIcon[pendingIconCount].Clip := RowRect;
        Inc(pendingIconCount);
      end
      else if FRows[i].GlyphVisible and (FImages <> nil) and (FRows[i].ImageIndex >= 0)
              and (FRows[i].ImageIndex < TyImageCount(FImages)) then
      begin
        iconSz := leftSlot - P.Scale(2);
        if iconSz < 8 then iconSz := 8;
        { In-layer, both branches: our own list renders the vector exactly at iconSz, a foreign
          list is materialised. Centred in the iconSz slot the check glyph would have used. }
        TyBlitImage(P.Bitmap, FImages, FRows[i].ImageIndex,
          Slot.Left + ((Slot.Right - Slot.Left) - iconSz) div 2,
          RowRect.Top + (rowH - iconSz) div 2, iconSz, APPI, False);
      end;

      // Caption: left-aligned after the check slot, ellipsized before the right slot.
      // A DefaultItem renders bold; otherwise honour the theme's font-weight.
      if FRows[i].DefaultItem then capWeight := 700 else capWeight := RowStyle.FontWeight;
      TextRect := Mir(Types.Rect(RowRect.Left + padL + leftSlot, RowRect.Top,
        RowRect.Right - padR - rightSlot, RowRect.Bottom), RowRect);
      P.DrawText(TextRect, FRows[i].Display, RowStyle.FontName, ResolveFontSize(RowStyle),
        capWeight, RowStyle.TextColor, taLeftJustify, tlCenter, True,
        TyAccelGatePos(FRows[i].MnemonicPos));   // underline only while Alt is held (Windows idiom)

      // Submenu arrow OR the trailing-aligned shortcut text in the trailing slot.
      if FRows[i].HasSubmenu then
      begin
        { The arrow POINTS the way the cascade opens, so mirroring has to turn the glyph
          round as well as move it -- a left-hand slot with a right-pointing chevron in it is
          the classic half-mirrored menu, and it points away from where the submenu appears. }
        if rtl then
          P.DrawGlyph(Mir(Types.Rect(RowRect.Right - rightSlot, RowRect.Top, RowRect.Right, RowRect.Bottom), RowRect),
            tgArrowLeft, RowStyle.TextColor, 2)
        else
          P.DrawGlyph(Types.Rect(RowRect.Right - rightSlot, RowRect.Top, RowRect.Right, RowRect.Bottom),
            tgArrowRight, RowStyle.TextColor, 2);
      end
      else if FRows[i].ShortcutText <> '' then
        P.DrawText(Mir(Types.Rect(RowRect.Left, RowRect.Top, RowRect.Right - padR, RowRect.Bottom), RowRect),
          FRows[i].ShortcutText, RowStyle.FontName, ResolveFontSize(RowStyle),
          RowStyle.FontWeight, RowStyle.TextColor, taRightJustify, tlCenter, False);
    end;

    P.EndPaint;

    { --- the two GDI passes, on the COMPOSITED canvas ------------------------
      Everything above went into the painter's BGRA layer, which EndPaint has just
      blitted over ACanvas; a GDI draw made before that point is simply erased. Both
      passes are clipped to their own row so nothing can bleed into a neighbour, and
      the painter-local rects are offset by ARect into ACanvas device coords.

      The per-row bracket is Canvas.SaveHandleState/RestoreHandleState and NOT the raw
      SaveDC/RestoreDC it used to be. RestoreDC swaps the DC's selected pen/font/brush
      back, but an LCL TCanvas caches which of ITS objects it believes are selected and
      only re-selects one when a property actually CHANGES -- so after the first callback
      the cache is a lie, and a handler that assigns the same Font.Color (or Pen.Color)
      it assigned last row gets a silent no-op and draws with whatever the restore put
      back. From the app's side that is undefendable: an OnDrawItem doing the ordinary
      thing -- same ink on every row -- would paint row one correctly and every row after
      it in a foreign colour. The canvas-aware pair calls DeselectHandles on BOTH sides,
      so the cache never outlives the DC state it describes; it is the same bracket LCL's
      own per-cell owner-draw hook uses (TCustomGrid.DoDrawCell around OnDrawCell,
      grids.pas), and what LCLIntf's own header tells LCL users to reach for instead of
      SaveDC/RestoreDC. Note FillRect is NOT affected (LCL hands it the brush handle
      explicitly), which is why the fill-based owner-draw tests stayed green through it.
      The sibling defect in TTyTreeView's per-cell dispatch was the same construct. }
    if pendingIconCount > 0 then
      for k := 0 to pendingIconCount - 1 do
      begin
        ACanvas.SaveHandleState;
        try
          IntersectClipRect(ACanvas.Handle,
            ARect.Left + pendingIcon[k].Clip.Left,  ARect.Top + pendingIcon[k].Clip.Top,
            ARect.Left + pendingIcon[k].Clip.Right, ARect.Top + pendingIcon[k].Clip.Bottom);
          pendingIcon[k].Res.Draw(ACanvas, ARect.Left + pendingIcon[k].X,
            ARect.Top + pendingIcon[k].Y, pendingIcon[k].Idx, pendingIcon[k].Enabled);
        finally
          ACanvas.RestoreHandleState;
        end;
      end;

    if pendingDrawCount > 0 then
      for k := 0 to pendingDrawCount - 1 do
      begin
        ACanvas.SaveHandleState;
        try
          IntersectClipRect(ACanvas.Handle,
            ARect.Left + pendingDraw[k].R.Left,  ARect.Top + pendingDraw[k].R.Top,
            ARect.Left + pendingDraw[k].R.Right, ARect.Top + pendingDraw[k].R.Bottom);
          RowRect := pendingDraw[k].R;
          Types.OffsetRect(RowRect, ARect.Left, ARect.Top);
          { TMenuItem.DoDrawItem picks the item's own OnDrawItem, else the parent menu's
            -- the same fallback the LCL uses. MenuItemHasDrawHandler already proved one
            of the two exists, so this never returns False and never derefs a nil menu. }
          TMenuItemAccess(pendingDraw[k].Item).DoDrawItem(ACanvas, RowRect, pendingDraw[k].St);
        finally
          ACanvas.RestoreHandleState;
        end;
      end;
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
  FTrackButton := tbRightButton;   // the TPopupMenu.TrackButton default
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
    FView.SetRows(TyBuildMenuRows(AItem, FAllowHeaders));
end;

procedure TTyMenuPopup.EnsureForm;
begin
  if FForm <> nil then Exit;
  FForm := TForm.CreateNew(nil);
  FForm.BorderStyle := bsNone;
  TyPreparePopupWindow(FForm);   // GTK3: opt into a native POPUP window (switch, default off)
  FForm.ShowInTaskBar := stNever;
  FForm.FormStyle := fsStayOnTop;
  FForm.PopupMode := pmExplicit;
  FForm.KeyPreview := True;
  FForm.OnDeactivate := @FormDeactivate;
  FForm.OnResize := @FormResize;   // re-mask rounded corners after Qt's layout-driven resize

  FView := TTyMenuView.Create(FForm);
  FView.Parent := FForm;
  FView.Align := alClient;
  ApplyViewOptions;          // Images / banner / OwnerDraw / TrackButton, before the rows render
  FView.ForceSquareSurface := TyIsWayland;   // Wayland can't shape-mask the window -> square paint

  FView.OnActivateRow := @HandleActivateRow;
  FView.OnOpenSubmenu := @HandleOpenSubmenu;
  FView.OnCloseRequested := @HandleCloseRequested;
  FView.OnCloseChild := @HandleCloseChild;
  FView.OnNavigateAdjacentBar := @HandleNavigateAdjacent;
  FView.OnNavigateLeft := @HandleNavigateLeft;
  if FRoot <> nil then
    FView.SetRows(TyBuildMenuRows(FRoot, FAllowHeaders));
end;

procedure TTyMenuPopup.ApplyViewOptions;
begin
  if FView = nil then Exit;
  FView.Images := FImages;                 // icon-column source
  FView.BannerCaption := FBannerCaption;   // decorative left banner (this level only)
  FView.BannerWidth := FBannerWidth;
  FView.OwnerDraw := FOwnerDraw;
  FView.TrackButton := FTrackButton;
  { The view reads its own IsRightToLeft (BiDiMode is public on TControl even though nothing
    publishes it), so this one assignment arms its painter, moves its slots and swaps the
    meaning of its Left/Right keys together. Written every time, not once at build: a host
    that changed direction between two popups must be honoured, exactly like OwnerDraw. }
  if FRightToLeft then FView.BiDiMode := bdRightToLeft else FView.BiDiMode := bdLeftToRight;
end;

function TTyMenuPopup.ViewForTest: TTyMenuView;
begin
  EnsureForm;         // the view is built lazily; a test must see it without a real Popup
  ApplyViewOptions;   // ...and see it in the state a (re-)Popup would leave it in
  Result := FView;
end;

function TTyMenuPopup.ComputeBounds(const AAnchor: TRect;
  AWidth, AHeight, APPI: Integer; AToRight: Boolean; ARightToLeft: Boolean = False): TRect;
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

  { MIRRORING: a cascade grows toward the reading end, so a mirrored submenu opens to the
    LEFT of its parent row and flips right only when it would run off the screen -- the same
    rule, read the other way. Note AToRight keeps its name: it means "this is a SUBMENU"
    (the caller says AToRight=True for a cascade and False for a dropdown), and renaming it
    would touch every call site to express the same two cases. }
  if AToRight then
  begin
    if ARightToLeft then
    begin
      // A mirrored submenu sits to the LEFT of its parent row; flip RIGHT if it would run off.
      L := AAnchor.Left - AWidth;
      if L < wa.Left then
        L := AAnchor.Right;
    end
    else
    begin
      // A submenu sits to the RIGHT of its parent row; flip LEFT if it would overflow.
      L := AAnchor.Right;
      if L + AWidth > wa.Right then
        L := AAnchor.Left - AWidth;
    end;
  end
  else if ARightToLeft then
  begin
    // A mirrored dropdown hangs its RIGHT edge under the anchor's right; the shared clamp
    // below nudges it right when it would run off the left of the work area.
    L := AAnchor.Right - AWidth;
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
  ApplyViewOptions;   // re-assert: EnsureForm early-exits on a re-open, so a host that
                      // changed any of these between two popups must still be honoured

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
  R := ComputeBounds(AAnchor, w, h, ppi, AToRight, FRightToLeft);
  FPopupRect := R;
  TyPreparePopupNative(FForm);   // Qt: re-type as Qt::Popup BEFORE Show so it maps app-positioned (no top-left flash)
  FForm.SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
  // GTK3/Wayland: the screen rect above is ignored by the compositor, so anchor the window to its
  // transient parent instead (bar cell / parent-row rect, both in parent-client coords). No-op off
  // GTK3-Wayland; when no anchor was registered (headless / other widgetset) the screen rect stands.
  if FWlParent <> nil then
  begin
    // A mapped Wayland xdg_popup cannot be repositioned. On a menu-bar hover-switch (File->Edit)
    // the bar reuses this one visible form, so move_to_rect would be ignored and Edit's items would
    // appear at File's spot. Pop it DOWN first; the move_to_rect + Show below then re-map it as a
    // fresh popup at the new cell -- the same pop-down-then-pop-up a native menu bar does. Detach
    // OnDeactivate around the interim Hide so it can't fire a dismiss. Off Wayland the old reuse
    // (SetBounds moves the visible window) still stands, so no flicker there.
    if TyIsGtk3Wayland and FForm.Visible then
    begin
      FForm.OnDeactivate := nil;
      FForm.Hide;
      FForm.OnDeactivate := @FormDeactivate;
    end;
    TyAnchorPopupRect(FForm, FWlParent, FWlRect, FWlMode);
    FWlParent := nil;   // consume: a later screen-anchored reopen must not reuse a stale rect
  end;
  FForm.Show;
  // Qt/X11 may still RE-PLACE + un-mask a frameless window at MAP time; re-assert now AND again next
  // event-loop turn (DeferredReapplyGeometry), once the native window settles. No-op on Win32/GTK2.
  FForm.SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
  // Route keyboard navigation to the dropdown: without focus, arrow/Esc keys never reach
  // TTyMenuView.KeyDown and a keypress can instead deactivate (and dismiss) the popup.
  if FView.CanFocus then FView.SetFocus;
  ApplyFormRegion(R.Right - R.Left, R.Bottom - R.Top);
  Application.QueueAsyncCall(@DeferredReapplyGeometry, 0);
end;

procedure TTyMenuPopup.SetWaylandAnchor(AParent: TCustomForm; const ARect: TRect;
  AMode: TTyPopupAnchorMode);
begin
  FWlParent := AParent;
  FWlRect := ARect;
  FWlMode := AMode;
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
  // Wayland ignores window masks (no XShape): skip shaping entirely — the view paints square corners
  // (ForceSquareSurface) so the popup is a clean rectangle instead of rounded-paint-on-square-window.
  if TyIsWayland then Exit;
  d := MulDiv(S.BorderRadius, FForm.Font.PixelsPerInch, 96) * 2;
  if d <= 0 then
  begin
    { Radius 0: leave rectangular (clear any region carried over from a prior open). On Qt, deep-clear
      first — SetWindowRgn(.,0) is a no-op there, so a reused popup would keep stale viewport/child
      masks (no-op off Qt). }
    TyClearPopupWindowMask(FForm, FView);
    SetWindowRgn(FForm.Handle, 0, True);
    Exit;
  end;
  { +1: CreateRoundRectRgn's right/bottom extents are exclusive. SetWindowRgn takes ownership of the
    region handle, so it must not be deleted afterwards. LCLIntf routes to the widgetset: win32 =
    native region, gtk2 = gdk_window_shape_combine_region, qt = QWidget.setMask (top-level ONLY). }
  Rgn := CreateRoundRectRgn(0, 0, AWidth + 1, AHeight + 1, d, d);
  { Qt6/X11 (QTSCROLLABLEFORMS): the painted surface is the scroll-area viewport + the alClient
    TTyMenuView's own native widget, which the top-level mask never reaches. Deep-mask them with the
    SAME region BEFORE SetWindowRgn (which only masks the top-level and doesn't consume Rgn). No-op
    off Qt. }
  TyMaskPopupWindow(FForm, FView, Rgn);
  SetWindowRgn(FForm.Handle, Rgn, True);
end;

procedure TTyMenuPopup.FormResize(Sender: TObject);
begin
  // Re-assert the rounded region at the form's ACTUAL realized size — Qt drops the mask on resize,
  // and the post-Show layout resize is exactly when that happens (Win32/GTK2: idempotent re-apply).
  if (FForm <> nil) and FForm.Visible and FForm.HandleAllocated then
    ApplyFormRegion(FForm.Width, FForm.Height);
end;

procedure TTyMenuPopup.DeferredReapplyGeometry(Data: PtrInt);
begin
  // Runs one event-loop turn after Popup's Show, by when Qt's map-time reparent/flag-recreation has
  // settled — so this SetBounds + region finally stick (on Win32/GTK2 it's a harmless re-assert).
  if (FForm = nil) or (not FForm.Visible) then Exit;
  FForm.SetBounds(FPopupRect.Left, FPopupRect.Top,
    FPopupRect.Right - FPopupRect.Left, FPopupRect.Bottom - FPopupRect.Top);
  ApplyFormRegion(FPopupRect.Right - FPopupRect.Left, FPopupRect.Bottom - FPopupRect.Top);
end;

function TTyMenuPopup.MeasuredWidth: Integer;
var
  ppi: Integer;
begin
  if FView = nil then Exit(0);
  ppi := FView.Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  Result := FView.MeasureWidth(ppi);
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
begin
  rows := TyBuildMenuRows(FRoot, FAllowHeaders);
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
  if RootPopup <> Self then
    Application.QueueAsyncCall(@RootPopup.DeferredForceClose, 0);
end;

procedure TTyMenuPopup.DoOpenSubmenu(AIndex: Integer);
var
  rows: TTyMenuRowArray;
  anchor: TRect;
  ppi, rowT: Integer;
  wlMode: TTyPopupAnchorMode;
begin
  rows := TyBuildMenuRows(FRoot, FAllowHeaders);
  if (AIndex < 0) or (AIndex > High(rows)) then Exit;
  if not rows[AIndex].HasSubmenu then Exit;

  FreeAndNil(FChild);   // only one open submenu per level
  FChild := TTyMenuPopup.Create(Self);
  FChild.Controller := FController;
  FChild.AllowHeaders := FAllowHeaders;   // submenus honour section headers too
  FChild.Images := FImages;               // ...and the icon column
  { An owner-drawn menu is owner-drawn all the way down, and the track button applies to
    the whole cascade -- both are properties of the MENU, not of one level of it.
    (The per-submenu icon list is NOT propagated like this: TyBuildMenuRows resolves
    SubMenuImages per item, which is what lets a submenu carry its own icons.) }
  FChild.OwnerDraw := FOwnerDraw;
  FChild.TrackButton := FTrackButton;
  FChild.RightToLeft := FRightToLeft;     // a menu reads one way all the way down the cascade
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
    // A zero-width anchor at the parent's TRAILING edge: the child opens flush to the far
    // side of the parent column (ComputeBounds reads AAnchor.Right for AToRight, or
    // AAnchor.Left when mirrored), and its own width is carried by Popup via the form width
    // below. Mirrored, the parent's trailing edge is its LEFT one.
    if FRightToLeft then
      anchor.Left := FForm.Left
    else
      anchor.Left := FForm.Left + FForm.Width;
    anchor.Right := anchor.Left;
    ppi := FView.Font.PixelsPerInch;
    if ppi <= 0 then ppi := 96;
    rowT := FView.RowTop(AIndex, ppi);
    anchor.Top := FForm.Top + rowT;
    anchor.Bottom := anchor.Top;
    // GTK3/Wayland: the child can't be placed by FForm.Left/Top (a Wayland client's own screen
    // position is unreliable). Anchor it to THIS popup's window instead, at the parent row's rect
    // in this form's client coords -- flying out to the trailing side (left when mirrored). Runtime-
    // gated: dead work off Wayland, and folded away entirely off GTK3 (TyIsGtk3Wayland = const False).
    if TyIsGtk3Wayland then
    begin
      if FRightToLeft then wlMode := pamLeftOf else wlMode := pamRightOf;
      FChild.SetWaylandAnchor(FForm,
        Rect(FView.Left, FView.Top + rowT,
             FView.Left + FView.Width, FView.Top + rowT + FView.RowHeight(AIndex, ppi)),
        wlMode);
    end;
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

function TTyMenuPopup.RootPopup: TTyMenuPopup;
begin
  Result := Self;
  while (Result.Owner <> nil) and (Result.Owner is TTyMenuPopup) do
    Result := TTyMenuPopup(Result.Owner);
end;

procedure TTyMenuPopup.FormDeactivate(Sender: TObject);
begin
  // When we open a submenu, focus moves to the CHILD popup within our own cascade, which
  // deactivates us — that is NOT a dismiss, and collapsing here would free the child while
  // it is still being shown (AV at FForm.Show). So don't decide synchronously: DEFER the
  // dismiss to the next message cycle (by then the active window has settled and we can tell
  // a cascade hand-off from a real focus loss), and run it on the ROOT popup so CloseAll
  // tears down the children without freeing a form from inside its own deactivate handler.
  Application.QueueAsyncCall(@RootPopup.DeferredDismiss, 0);
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
  Height := TyDensityHeight(ActiveController, 28);
end;

destructor TTyMenuBar.Destroy;
begin
  TyAccelUnregister(Self);
  Application.RemoveAsyncCalls(Self);   // cancel any pending DeferredOpenTop
  StopHoverPoll;
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

function TTyMenuBar.OpenIndexForTest: Integer;
begin
  Result := FOpenIndex;
end;

function TTyMenuBar.PopupForTest: TTyMenuPopup;
begin
  Result := FPopup;
end;

function TTyMenuBar.TopRightJustifiedForTest(AIndex: Integer): Boolean;
begin
  Result := TopRightJustified(AIndex);
end;

function TTyMenuBar.TopLeftForTest(AIndex, APPI: Integer): Integer;
begin
  Result := TopLeft(AIndex, APPI);
end;

procedure TTyMenuBar.OpenTopForTest(AIndex: Integer);
begin
  OpenTop(AIndex);
end;

function TTyMenuBar.TopEnabledForTest(AIndex: Integer): Boolean;
begin
  Result := TopEnabled(AIndex);
end;

function TTyMenuBar.TopEnabled(AIndex: Integer): Boolean;
var
  mi: TMenuItem;
begin
  mi := VisibleTopItem(AIndex);
  Result := (mi <> nil) and mi.Enabled;
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

function TTyMenuBar.TopRightJustified(AIndex: Integer): Boolean;
var
  mi: TMenuItem;
begin
  mi := VisibleTopItem(AIndex);
  Result := (mi <> nil) and mi.RightJustify;
end;

{ Where the cell would sit on a left-to-right bar: the packing rules themselves, with no
  mirroring applied. Split out of TopLeft because FitWidth measures the bar's CONTENT EXTENT
  and must not read a mirrored x -- a reflection is taken about Width, and Width is the very
  thing FitWidth is computing, so mirroring there would be circular. Nothing else uses it:
  every consumer that means a position on screen goes through TopLeft. }
function TTyMenuBar.TopLeftUnmirrored(AIndex, APPI: Integer): Integer;
var
  S: TTyStyleSet;
  i: Integer;
begin
  S := CurrentStyle;
  if TopRightJustified(AIndex) then
  begin
    { A right-justified top and everything after it pack against the TRAILING edge, in order.
      Measuring from the far end rather than the near one is the whole point: the group has to
      stay glued to the edge as the bar resizes, which a near-packed offset cannot do. }
    Result := Width - MulDiv(S.Padding.Right, APPI, 96);
    for i := AIndex to TopCount - 1 do
      Dec(Result, TopCellWidth(i, APPI));
    Exit;
  end;
  // The bar's own left padding offsets the first cell; cells then pack edge-to-edge.
  Result := MulDiv(S.Padding.Left, APPI, 96);
  for i := 0 to AIndex - 1 do
    Inc(Result, TopCellWidth(i, APPI));
end;

function TTyMenuBar.TopLeft(AIndex, APPI: Integer): Integer;
begin
  Result := TopLeftUnmirrored(AIndex, APPI);
  { MIRROR once, here, so BOTH packing rules above get it and neither can be the branch
    somebody forgot -- and, more to the point, so the paint (RenderTo), the hit test (TopAtX)
    and the dropdown anchor (OpenTop) go on taking their x from ONE expression. All three
    call this; a mirrored bar that answered clicks on the old side would need somebody to
    add a second copy first. }
  if IsRightToLeft then
    Result := Width - Result - TopCellWidth(AIndex, APPI);
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
    { The UNMIRRORED x on purpose: this is an extent, not a position, and a reflection is
      taken about Width -- which is what this function exists to produce. A mirrored bar
      fits into exactly the same width, because a reflection preserves extent. }
    Result := TopLeftUnmirrored(n - 1, APPI) + TopCellWidth(n - 1, APPI)
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
  StopHoverPoll;
  FreeAndNil(FPopup);
  Invalidate;
end;

procedure TTyMenuBar.HandlePopupClosed(Sender: TObject);
begin
  // The dropdown cascade collapsed (leaf activation / focus-loss dismiss / Esc). Clear the
  // open-index and repaint the active cell. Do NOT free FPopup — this fires from inside the
  // popup's own CloseAll, and the bar keeps the (now hidden) host for reuse.
  FOpenIndex := -1;
  StopHoverPoll;
  Invalidate;
end;

procedure TTyMenuBar.StartHoverPoll;
begin
  // Only where an open popup grabs the pointer (Qt/GTK) does the bar stop getting MouseMove and need
  // to poll; on Win32 the ordinary MouseMove path handles hover-switch, so there is nothing to start.
  if not TyPopupGrabsPointer then Exit;
  if FHoverPollTimer = nil then
  begin
    FHoverPollTimer := TTimer.Create(Self);
    FHoverPollTimer.Interval := 60;
    FHoverPollTimer.OnTimer := @HoverPollTick;
  end;
  FHoverPollTimer.Enabled := True;
end;

procedure TTyMenuBar.StopHoverPoll;
begin
  if FHoverPollTimer <> nil then FHoverPollTimer.Enabled := False;   // ref'd on all widgetsets (nil off-poll)
end;

procedure TTyMenuBar.HoverPollTick(Sender: TObject);
var
  p: TPoint;
  idx, ppi: Integer;
begin
  // Only started where the popup grabs the pointer (see StartHoverPoll), so this never fires on Win32.
  if (FOpenIndex < 0) or not HandleAllocated then begin StopHoverPoll; Exit; end;
  // A Qt/GTK dropdown grabs the mouse, so the bar never receives MouseMove while open. Poll the
  // GLOBAL cursor instead and reuse the exact same "hover a different top cell -> switch" rule.
  p := ScreenToClient(Mouse.CursorPos);
  if (p.Y < 0) or (p.Y >= Height) then Exit;   // cursor is in the dropdown / off the bar -> no switch
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  idx := TopAtX(p.X, ppi);
  if (idx >= 0) and (idx <> FOpenIndex) then OpenTop(idx);
end;

procedure TTyMenuBar.OpenTop(AIndex: Integer);
var
  mi: TMenuItem;
  ppi, cellL, cellW: Integer;
  origin, cp: TPoint;
  anchor: TRect;
  pf: TCustomForm;
begin
  mi := VisibleTopItem(AIndex);
  if mi = nil then begin ClosePopup; Exit; end;
  { A disabled top cannot be opened -- by click, by hover-switch, or by its Alt mnemonic.
    All three routes come through here, which is why the check lives here and not in
    MouseDown. }
  if not mi.Enabled then begin ClosePopup; Exit; end;
  { A childless top-level item is a COMMAND BUTTON, not a dead cell. In a native menu bar
    clicking it fires its OnClick; here it silently closed whatever was open and returned,
    so a bar with a bare "Help" top did nothing at all and there was no way to tell that
    from a menu whose items had failed to load. }
  if mi.Count = 0 then
  begin
    ClosePopup;
    mi.Click;
    Exit;
  end;

  // Reuse the live host across adjacent-cell rotation; rebuild it only when needed.
  if FPopup = nil then
  begin
    FPopup := TTyMenuPopup.Create(Self);
    FPopup.OnNavigateAdjacent := @HandleNavigateAdjacent;
    FPopup.OnClose := @HandlePopupClosed;
  end;
  FPopup.Controller := ActiveController;
  { A TMainMenu publishes the same owner-draw protocol as a TPopupMenu, and the dropdown is
    rendered by the very same view -- without this, OwnerDraw would work in a context menu
    and silently not in a menu-bar dropdown. }
  FPopup.OwnerDraw := (FMenu <> nil) and FMenu.OwnerDraw;
  { The dropdown reads the way the bar does -- rows, slots, cascade direction and the
    Left/Right keys all follow from this one assignment. Re-asserted on every open, like
    OwnerDraw, so a bar whose direction changed between two opens is honoured. }
  FPopup.RightToLeft := IsRightToLeft;
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
    // GTK3/Wayland: the compositor ignores that screen rect, so also register the cell's rect in
    // the app form's client coords (a plain control-tree walk, no screen coords) as the anchor the
    // dropdown drops from. Gated at runtime -- this is dead work on every other widgetset, and off
    // GTK3 TyIsGtk3Wayland is a constant False so it folds away entirely.
    if TyIsGtk3Wayland then
    begin
      pf := GetParentForm(Self);
      if pf <> nil then
      begin
        cp := ClientToParent(Types.Point(cellL, 0), pf);
        FPopup.SetWaylandAnchor(pf, Types.Rect(cp.X, cp.Y, cp.X + cellW, cp.Y + Height), pamBelow);
      end;
    end;
    FPopup.Popup(anchor, False);
    StartHoverPoll;   // non-Win32: track the cursor for hover-switch while the dropdown is up
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
  R, CellRect, CapRect: TRect;
  i, cellL, cellW, padL: Integer;
  CellStates: TTyStateSet;
  rtl: Boolean;
begin
  P := TTyPainter.Create;
  try
    R := Types.Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    { MIRRORING: the cells pack from the right. Their x comes from TopLeft, which is also
      what TopAtX inverts and what OpenTop anchors the dropdown to, so this loop cannot end
      up painting cells the hit test does not agree with. }
    rtl := IsRightToLeft;
    P.BeginPaint(ACanvas, ARect, APPI, rtl);
    // Surface: the TyMenuBar background/border from its own tokens.
    S := CurrentStyle;
    DrawFrame(P, R, S);

    for i := 0 to TopCount - 1 do
    begin
      cellL := TopLeft(i, APPI);
      cellW := TopCellWidth(i, APPI);

      // A cell is active when its dropdown is open, hover when the mouse is over it.
      CellStates := [];
      { Disabled wins over both. It was not resolved at all, so a disabled top-level menu
        painted identically to an enabled one -- the user clicks, nothing opens, and the
        bar has told them nothing. Disabled also suppresses the hover highlight, which
        would otherwise invite exactly that click. }
      if not TopEnabled(i) then
        Include(CellStates, tysDisabled)
      else if i = FOpenIndex then
        Include(CellStates, tysActive)
      else if i = FHotIndex then
        Include(CellStates, tysHover)
      else
        Include(CellStates, tysNormal);
      CellStyle := ActiveController.Model.ResolveStyle('TyMenuItem', '', CellStates);

      CellRect := Types.Rect(R.Left + cellL, R.Top, R.Left + cellL + cellW, R.Bottom);
      if tpBackground in CellStyle.Present then
        P.FillBackground(CellRect, CellStyle.Background, CellStyle.BorderRadius);

      { The caption's own slot is inset from the cell's LEADING edge, so under mirroring it is
        inset from the right -- and the painter turns the taLeftJustify into that side. Both
        halves, or the text hugs a padding that is no longer where the text is. }
      padL := P.Scale(CellStyle.Padding.Left);
      CapRect := Types.Rect(CellRect.Left + padL, CellRect.Top, CellRect.Right, CellRect.Bottom);
      if rtl then CapRect := BidiFlipRect(CapRect, CellRect, True);
      P.DrawText(CapRect,
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

function TTyPopupMenu.GetVersion: string;
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

function TTyPopupMenu.ResolveRightToLeft: Boolean;
var
  c: TComponent;
begin
  c := PopupComponent;
  if not (c is TControl) then c := Owner;
  Result := (c is TControl) and TControl(c).IsRightToLeft;
end;

procedure TTyPopupMenu.EnsureRenderer;
begin
  if FRenderer = nil then
    FRenderer := TTyMenuPopup.Create(Self);
  FRenderer.Controller := FController;
  FRenderer.OnClose := @HandleRendererClosed;
  { The two inherited LCL knobs the themed renderer has to be told about. Both were
    published (TMenu.OwnerDraw, TPopupMenu.TrackButton), settable in the Object Inspector,
    and read by nobody -- OwnerDraw + OnDrawItem/OnMeasureItem because the renderer painted
    every row itself, TrackButton because activation only ever ran through TControl.Click. }
  FRenderer.OwnerDraw := OwnerDraw;
  FRenderer.TrackButton := TrackButton;
  { Resolved here, with the other per-popup knobs, so it is in place before the view is built
    and before MeasuredWidth is asked -- the alignment shift below depends on that width. }
  FRenderer.RightToLeft := ResolveRightToLeft;
  ConfigureRenderer(FRenderer);   // subclasses opt into headers/etc. BEFORE the rows are built
  // Root the shared renderer at this popup menu's items (the inherited LCL model).
  FRenderer.SetRoot(Items);
end;

procedure TTyPopupMenu.ConfigureRenderer(ARenderer: TTyMenuPopup);
begin
  // Base: no extra configuration.
end;

procedure TTyImagesMenu.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
end;

procedure TTyImagesMenu.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then FImages := nil;
end;

procedure TTyImagesMenu.ConfigureRenderer(ARenderer: TTyMenuPopup);
begin
  inherited ConfigureRenderer(ARenderer);
  ARenderer.Images := FImages;   // plumb the icon source to the shared renderer
end;

procedure TTyMenuEx.ConfigureRenderer(ARenderer: TTyMenuPopup);
begin
  inherited ConfigureRenderer(ARenderer);   // TTyImagesMenu: sets Images
  ARenderer.AllowHeaders := True;            // '-Text' items render as section headers
  ARenderer.BannerCaption := FBannerCaption; // + the decorative left banner
  ARenderer.BannerWidth := FBannerWidth;
end;

procedure TTyPopupMenu.PopUp(X, Y: Integer);
var
  anchor: TRect;
  w: Integer;
begin
  // Mirrors popupmenu.inc, minus the native handle it does not need.
  if (ActivePopupMenu <> nil) and (ActivePopupMenu <> Self) then
    ActivePopupMenu.Close;
  SetPopupPoint(Point(X, Y));       // so PopupPoint reads the cursor, not history
  DoPopup(Self);                    // OnPopup -- may add, remove or re-enable items
  if Items.Count = 0 then Exit;     // an empty menu shows nothing, as LCL decides here
  ActivePopupMenu := Self;          // what makes Close/OnClose reachable at all
  { TMenuItem.InitiateActions is protected and declared in another unit, so a
    same-unit descendant is the way in -- LCL calls it from inside Menus itself. }
  TMenuItemAccess(Items).InitiateActions;   // action-linked items refresh before we snapshot
  // ...and only NOW take the snapshot: SetRoot walks Items, so a handler that populated
  // the menu in OnPopup would otherwise have populated it into the void.
  EnsureRenderer;
  // A zero-size anchor at the cursor: the renderer hangs its dropdown below/right of
  // (X, Y) and measures its own size (ComputeBounds flips near screen edges).
  { Honour Alignment. It is inherited from TPopupMenu, so the Object Inspector has always
    offered paLeft/paRight/paCenter -- and nothing read it, which made a right-aligned
    context menu (the normal choice for a menu opened from a right-hand toolbar, where a
    left-aligned one runs off the edge) silently identical to a left-aligned one.
    The renderer hangs its dropdown from the anchor's LEADING edge, so alignment is expressed
    by moving that edge: the popup's own width is not known until it measures itself, so
    paRight/paCenter shift the anchor by the width the renderer reports. The shift itself is
    TyPopupAnchorShift -- a pure function, because it carries a SIGN that mirroring turns
    round and nothing about a live popup can be tested. }
  anchor := Types.Rect(X, Y, X, Y);
  if Alignment <> paLeft then
  begin
    w := FRenderer.MeasuredWidth;
    if w > 0 then
      OffsetRect(anchor, TyPopupAnchorShift(Alignment, w, FRenderer.RightToLeft), 0);
  end;
  FRenderer.Popup(anchor, False);
end;

procedure TTyPopupMenu.HandleRendererClosed(Sender: TObject);
begin
  Close;   { TPopupMenu.Close: DoClose -> OnClose, and ActivePopupMenu := nil }
end;

procedure TTyPopupMenu.ActivateRowForTest(AIndex: Integer);
begin
  EnsureRenderer;
  FRenderer.ActivateRowForTest(AIndex);
end;

function TTyPopupMenu.RendererForTest: TTyMenuPopup;
begin
  EnsureRenderer;   // same configuration pass a real PopUp runs
  Result := FRenderer;
end;

end.
