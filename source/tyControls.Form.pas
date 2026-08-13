unit tyControls.Form;

{$mode objfpc}{$H+}
{$IFDEF LCLCOCOA}
{$modeswitch objectivec1}
{$ENDIF}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, Dialogs, ExtCtrls, LCLType, LMessages,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Painter, tyControls.Controller,
  tyControls.Menu, tyControls.WindowEffects, tyControls.PlatformWS,
  tyControls.FormSurface, tyControls.StrConsts;

type
  { Re-export the content-host class. The IDE adds a published `Surface: TTyFormSurface;` field to
    every designed TTyForm (it hosts the controls), and a published field's class type must be
    DIRECTLY visible — not merely reachable through this unit's own `uses`. Re-exporting it here means
    a form unit only needs `tyControls.Form` (which every TTyForm descendant already uses); it never
    has to add `tyControls.FormSurface` by hand (the IDE's field-sync does not add units). }
  TTyFormSurface = tyControls.FormSurface.TTyFormSurface;

  TTyBorderHit = (bhNone, bhLeft, bhTop, bhRight, bhBottom,
                  bhTopLeft, bhTopRight, bhBottomLeft, bhBottomRight);

  TTyCaptionButtonKind = (cbkClose, cbkMin, cbkMax, cbkRestore);

  TTyCaptionButtonFlag  = (cbfMinimize, cbfMaximize, cbfClose);
  TTyCaptionButtonFlags = set of TTyCaptionButtonFlag;

  { Where the caption cluster sits inside a title bar, in the bar's own client px, and what is
    left over for everything else.

    ONE record because the bar used to hold TWO independent claims about which side the buttons
    are on: LayoutButtons packed them from `ClientWidth - margin` leftwards, while RightInset
    restated the same cluster as a width that AdjustClientRect and CaptionSpan then subtracted
    from the RIGHT. Mirroring either claim alone lays the caption and every host child straight
    over the buttons at one end and leaves a hole at the other -- the "drawn on the right,
    answers on the left" shape this library has shipped repeatedly. Both now come out of
    TyCaptionLayoutFor, so mirroring is one reflection applied to all of them at once.

    The buttons need no separate hit test: they are windowed children, so LCL routes a press,
    a hover and a pressed state by the very bounds LayoutButtons wrote from Min/Max/CloseBtn. }
  TTyCaptionLayout = record
    MinBtn, MaxBtn, CloseBtn: TRect;   // per-button box; empty (zero width) when that one is hidden
    Band: TRect;                       // the whole strip the cluster reserves, both margins included
    Content: TRect;                    // what is left for the caption and the host's own children
  end;

  TTyChromeEngine = class;

  TTyCaptionButton = class(TTyCustomControl)
  private
    FKind: TTyCaptionButtonKind;
    FShowGlyphOnHoverOnly: Boolean;
    procedure SetKind(AValue: TTyCaptionButtonKind);
    procedure SetShowGlyphOnHoverOnly(AValue: Boolean);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Click; override;
  public
    function GetStyleTypeKey: string; override;
    function KindVariant: string;
    function KindGlyph: TTyGlyphKind;
    function KindGlyphToken: string;   // v3/C5: theme glyph-override token name for this kind
  published
    property Kind: TTyCaptionButtonKind read FKind write SetKind;
    property ShowGlyphOnHoverOnly: Boolean read FShowGlyphOnHoverOnly
      write SetShowGlyphOnHoverOnly default False;
    property OnClick;
  end;

  { What a double-click on the caption / title bar does:
      tcaMaximize — toggle maximize/restore (the standard Windows behaviour, default).
      tcaRollUp   — "window shade": collapse the window to just its title bar, toggling.
      tcaNone     — do nothing. }
  TTyCaptionAction = (tcaMaximize, tcaRollUp, tcaNone);

  TTyTitleBar = class(TTyCustomControl, ITyTitleBarTag)
  private
    FCaption: TCaption;
    FMinButton: TTyCaptionButton;
    FMaxButton: TTyCaptionButton;
    FCloseButton: TTyCaptionButton;
    FButtonWidth: Integer;
    FButtonWidthExplicit: Boolean;   // True once ButtonWidth is set in code/OI (overrides the theme metric)
    { a6256. The PPI at which ButtonWidth was pinned. ButtonWidth stays a DEVICE-px property
      (setting 50 makes the button 50 px wide right there -- test.form.pas pins that), so the
      pin alone cannot say what 50 should become on a 250% monitor. Keeping the PPI it was
      taken at turns the pair into a PPI-independent fact, and EffectiveButtonWidthPx derives
      from the pair rather than multiplying the running field. Deriving is what makes a
      monitor round trip land back on the pinned number instead of drifting away from it. }
    FButtonWidthPPI: Integer;
    FTitleAlignment: TAlignment;
    FEngine: TTyChromeEngine;
    procedure SetCaption(const AValue: TCaption);
    procedure SetButtonWidth(AValue: Integer);
    procedure SetTitleAlignment(AValue: TAlignment);
    { Device-px caption-button width: an explicit ButtonWidth wins; otherwise the theme's
      --caption-button-width metric (logical, DPI-scaled); otherwise TyTitleButtonWidth. }
    function EffectiveButtonWidthPx: Integer;
    { Theme-driven spacing (device px, DPI-scaled; default 0 = flush): --caption-button-margin
      insets the buttons from the title-bar edges, --caption-button-gap separates adjacent buttons.
      Lets a skin (classic) float the caption buttons as gapped 3D squares; the title bar shows in
      the gaps (the buttons are smaller windows over it). }
    function CapMarginPx: Integer;
    function CapMarginYPx: Integer;
    function CapGapPx: Integer;
    function LeftInsetPx: Integer;
    { The layout for a bar of AWidth x AHeight -- the seam every consumer of a caption button's
      x goes through. Separate from the public no-argument CaptionLayout because RenderTo and
      AdjustClientRect are handed a rect that need not be the live ClientRect (tests render into
      an off-screen one), and a second copy of the metric gathering is exactly what this
      function exists to prevent. }
    function CaptionLayoutAt(AWidth, AHeight: Integer): TTyCaptionLayout;
    function GetShowMinimize: Boolean;
    function GetShowMaximize: Boolean;
    function GetShowClose: Boolean;
    procedure SetShowMinimize(AValue: Boolean);
    procedure SetShowMaximize(AValue: Boolean);
    procedure SetShowClose(AValue: Boolean);
  protected
    procedure LayoutButtons;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Resize; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure Paint; override;
    { Window-drag / double-click-maximize are wired via these METHOD OVERRIDES
      (each calls inherited first, so a user-assigned published OnMouseDown/Move/
      Up/DblClick still fires) then delegates to the chrome engine. This frees the
      mouse-event slots for user assignment without clobbering the engine wiring. }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    { See TTyRadioGroup.CMBiDiModeChanged: LCL's own handling invalidates and calls AdjustSize,
      but the caption buttons are placed by SetBounds rather than redrawn from a paint, so
      without this the cluster stays on the old side until something happens to repaint the bar. }
    procedure CMBiDiModeChanged(var Message: TLMessage); message CM_BIDIMODECHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
    property MinButton: TTyCaptionButton read FMinButton;
    property MaxButton: TTyCaptionButton read FMaxButton;
    property CloseButton: TTyCaptionButton read FCloseButton;
    { Where the caption cluster and the content zone are right now, for the bar's live client
      size. Public because a host that wants to place something in the bar has to be able to ask
      ONE authority which side the buttons are on -- and because that is the only way a test can
      check the paint and the routing against the same answer. }
    function CaptionLayout: TTyCaptionLayout;
    { The total width the caption buttons reserve. A WIDTH, so it does not change with the
      reading direction -- but on a mirrored bar the strip it measures is at the LEFT edge, so
      the name lies. Kept anyway: renaming a public member is a breaking change for a gain the
      documentation can give instead (see docs/controls/titlebar.md). }
    function RightInset: Integer;
    { The horizontal span the caption may use: the bar minus the caption-button inset, minus
      whatever the host's own child controls occupy. }
    procedure CaptionSpan(AWidth: Integer; out ALeft, ARight: Integer);
  published
    property Caption: TCaption read FCaption write SetCaption;
    { Left (default) or centered title text. Centered lays out within the content
      zone (left pad .. start of the caption buttons), so it never overlaps them. }
    property TitleAlignment: TAlignment read FTitleAlignment write SetTitleAlignment default taLeftJustify;
    property Align;
    property Anchors;
    property ButtonWidth: Integer read FButtonWidth write SetButtonWidth;
    { Per-button visibility for a STANDALONE title bar (not associated with a TTyForm).
      When associated, the owning form drives these from its BorderIcons + Resizable. }
    property ShowMinimize: Boolean read GetShowMinimize write SetShowMinimize default True;
    property ShowMaximize: Boolean read GetShowMaximize write SetShowMaximize default True;
    property ShowClose: Boolean read GetShowClose write SetShowClose default True;
  end;

  TTyChromeEngine = class(TObject)
  private
    FForm: TCustomForm;
    FTitleBar: TTyTitleBar;
    FBorderZone: Integer;
    FInstalledPPI: Integer;
    FDragging: Boolean;
    FDragStart: TPoint;        // GLOBAL cursor pos at drag start (screen coords)
    FDragFormStart: TPoint;    // form Left/Top at drag start
    FResizing: Boolean;
    FResizeHit: TTyBorderHit;
    FResizeStartBounds: TRect;
    FResizeStartMouse: TPoint;
    FMaximized: Boolean;
    { True when the MAXIMIZED state belongs to the window manager (Aero Snap to the top edge,
      Win+Up, the taskbar/system menu) rather than to ToggleMaximize's own work-area resize.
      It decides who owns the way back: the OS keeps its own restore rect (and, on Win32, its
      caption-move loop restores the window under the cursor for free), whereas the engine's
      maximize must be undone from FSavedBounds. }
    FNativeMaximize: Boolean;
    FSavedBounds: TRect;
    { The form's Resizable opt-out, read off the associated TTyForm (FForm is typed
      TCustomForm for the generic engine; default True for a non-TTyForm host). The
      edge hit-test routes through this so a fixed window never starts a resize. }
    function FormResizable: Boolean;
    { Whether the engine's MANUAL (BoundsRect-drag) edge resize is active. False on Windows —
      there the native WS_THICKFRAME + WM_NCHITTEST own resize, so the manual path is disabled
      to avoid double-handling (see tyControls.Win32WS); elsewhere it follows FormResizable.
      Distinct from FormResizable so the maximize gate (which uses FormResizable) is unaffected. }
    function ManualResizeEnabled: Boolean;
    { Push a maximize state onto the WHOLE chrome, not just the flag: the caption button's
      glyph (max <-> restore), the OS window effects (a maximized window must lose its rounded
      corners) and the native NC strategy (the WM_NCCALCSIZE inset differs when maximized).
      Every path that maximizes or restores goes through here so none of them can drift. }
    procedure ApplyMaximizedState(AMaximized, ANative: Boolean);
    { Hand the in-progress title-bar drag to the platform's own window-move loop — Win32 caption
      move, Qt startSystemMove, GTK begin_move_drag — so the drag gets Aero Snap / the snap
      preview / free monitor crossing, none of which a hand-written Left/Top move can offer.
      FDragging is cleared BEFORE the handoff because the Win32 loop is modal and blocking: any
      mouse move it delivers must not re-enter here. Widgetsets with no system move (Cocoa, Qt5)
      keep the manual drag, re-seeded at ACursor so it continues from the current position. }
    procedure StartPlatformDrag(const ACursor: TPoint);
  public
    constructor Create;
    procedure CaptureInstalledPPI;
    procedure TitleBarMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    { The cursor-driven half of the title-bar drag, split out of the LCL mouse handlers above
      (which just feed them Mouse.CursorPos) so the whole gesture — including the maximized
      "tear loose and keep dragging" — can be driven from an explicit screen point in tests. }
    procedure TitleBarDragBegin(const ACursor: TPoint);
    procedure TitleBarDragUpdate(const ACursor: TPoint);
    procedure TitleBarDblClick;
    { The window manager changed the maximize state behind the engine's back. See the
      implementation for why only the OS's own transitions are honoured. }
    procedure SyncNativeMaximized(AMaximized: Boolean);
    procedure FormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure FormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    { Drop the border-resize cursor back to the default. FormMouseMove sets crSizeNS/WE while
      the pointer is over the resize gutter and only clears it on the NEXT move; on GTK/Qt no
      move is delivered after a popup menu closes, so the resize cursor sticks over the whole
      form. Callers fire this from events that DO arrive after a menu closes (re-activate,
      mouse re-enter). No-op while an actual resize drag is in progress. }
    procedure ClearResizeCursor;
    procedure HandleChangeBounds;
    { Record the PPI the chrome is now installed at. TTyForm.DoAutoAdjustLayout re-derives
      the bar height after LCL's own scaling pass and has to tell the engine, or the next
      ChangeBounds would see a stale FInstalledPPI and "correct" a height that is already
      right. }
    procedure NoteInstalledPPI(APPI: Integer);
    procedure ToggleMaximize;
    property Form: TCustomForm read FForm write FForm;
    property TitleBar: TTyTitleBar read FTitleBar write FTitleBar;
    property BorderZone: Integer read FBorderZone write FBorderZone;
    property Maximized: Boolean read FMaximized write FMaximized;
    { Whether the current maximize is the window manager's (see FNativeMaximize). }
    property NativeMaximized: Boolean read FNativeMaximize;
    { The rect an ENGINE maximize goes back to — captured when ToggleMaximize maximizes, and
      the size a title-bar drag restores the window to when it tears it loose. (A native
      maximize does not use it: the window manager keeps its own restore rect.) }
    property SavedBounds: TRect read FSavedBounds write FSavedBounds;
    property Dragging: Boolean read FDragging;
    property Resizing: Boolean read FResizing;
  end;

  { A borderless form that owns a persistent chrome engine but is born EMPTY (no
    title bar). Drop a palette TTyTitleBar onto it: the bar auto-associates via the
    Notification(opInsert) hook (the LCL Form.Menu -> TMainMenu pattern), and the
    engine + caption buttons wire to it at RUNTIME. Otherwise it behaves like an
    ordinary TForm: drop your controls straight onto it and design them in place. }
  TTyForm = class(TForm, ITyGlassHost, ITyThemedBackground)
  private
    FTitleBar: TTyTitleBar;
    FTitleHeightExplicit: Boolean;    // True once TitleHeight is set in code/.lfm (pins it; else follows density)
    { a6256. The pinned title-bar height in LOGICAL (96-PPI) px. A pinned height must scale
      with the monitor like the theme-driven one does, and it must come BACK to the same
      number when the window returns to a 96-PPI monitor -- so what is remembered is the
      PPI-independent value, and every use derives device px from it. Storing the device
      value and re-multiplying it per crossing is what made the bar grow without bound. }
    FTitleHeightLogical: Integer;
    FSurface: TTyFormSurface;         // Phase 1: runtime child content-host (covers the WS_THICKFRAME dead band)
    FMenuBar: TTyMenuBar;             // the primary menu bar (shortcut dispatch / mac global bar)
    FResizable: Boolean;              // window edge-resize opt-out (default True); see SetResizable
    FController: TTyStyleController;   // set by ApplyChromeTheme; used by Paint
    FSharpBackdrop: TBGRABitmap;      // form bg snapshot, UNblurred (fills glass corners)
    FGlassBackdrop: TBGRABitmap;      // same snapshot, blurred once for the glass pane
    FGlassKey: string;                // imagepath|WxH|blurDev — rebuild when it changes
    FGlassBlurLogical: Integer;       // theme-wide glass blur radius (0 = no glass)
    FFollowTimer: TTimer;             // P4 live-follow: polls the OS scheme/accent while following (nil unless armed)
    FDidInitialClamp: Boolean;        // macOS: clamp the window onto a visible monitor on first show only
    FCaptionAction: TTyCaptionAction; // what caption double-click does (maximize / roll-up / none)
    FRolledUp: Boolean;               // window-shade state (rolled to the title bar)
    FUnrolledHeight: Integer;         // full height saved while rolled up
    FSavedMinHeight: Integer;         // Constraints.MinHeight saved while rolled up
    { A9 per-instance StyleOverride for the window chrome (the TyForm typeKey), mirroring
      TTyCustomControl exactly — same parser (TTyStyleModel.ResolveOverride), same merge
      (TyMergeStyleSet), same (text, ThemeVersion)-keyed cache so var(--x) re-binds on a switch. }
    FStyleOverride: string;
    FOvrCache: TTyStyleSet;
    FOvrCacheText: string;
    FOvrCacheVer: Cardinal;
    FOvrCacheValid: Boolean;
    procedure SetStyleOverride(const AValue: string);
    { The form's chrome style: ACtrl's resolved 'TyForm' set with the per-instance StyleOverride
      merged on top. EVERY site that used to call Model.ResolveStyle('TyForm', ...) resolves
      through here, so an override reaches the background paint, the backdrop rebuild, the
      title-bar colour fallback, ThemedBgColor AND the OS window effects alike. ACtrl <> nil. }
    function ResolveChromeStyle(ACtrl: TTyStyleController): TTyStyleSet;
    procedure DoFollowTick(Sender: TObject);
    { Deferred so the dialog runs AFTER the designer's delete finishes. Showing it straight from
      Notification(opRemove) — i.e. inside a destruction notification — ran a modal loop in the middle
      of the designer's own delete/undo bookkeeping. }
    procedure DoWarnSurfaceDeleted(Data: PtrInt);
    procedure UpdateFollowWatch;      // (re)arm/disarm FFollowTimer per the controller's Follow policy
    // ITyGlassHost
    function GlassBackdrop: TBGRABitmap;
    function GlassSharpBackdrop: TBGRABitmap;
    function GlassClientOrigin: TPoint;
    function GlassUnderTitlebar: Boolean;
    // ITyThemedBackground — the form's themed TyForm bg, for children's parent-bg fill.
    function ThemedBgColor(out AColor: TTyColor): Boolean;
    procedure SetupChrome;
    procedure SetTitleBar(AValue: TTyTitleBar);
    procedure SetMenuBar(AValue: TTyMenuBar);
    procedure WireTitleBarButtons;
    procedure ArmEngine;
    function GetTitleHeight: Integer;
    procedure SetTitleHeight(AValue: Integer);
    procedure SetController(AValue: TTyStyleController);
    procedure SetResizable(AValue: Boolean);
    function GetBorderStyleTy: TFormBorderStyle;
    procedure SetBorderStyleTy(AValue: TFormBorderStyle);
    function GetBorderIconsTy: TBorderIcons;
    procedure SetBorderIconsTy(AValue: TBorderIcons);
    procedure SyncCaptionButtons;   // push TyResolveCaptionButtons(BorderIcons,Resizable) onto the bar
    { Per-platform resize-strategy application (WS_THICKFRAME on Win32, styleMask on
      Cocoa, gutter re-align on GTK/Qt). Stub for Phase A — the bodies land in later
      phases; the call sites (SetResizable + post-handle-creation) are wired now. }
    procedure ApplyResizeStrategy;
    procedure DoMinimizeClick(Sender: TObject);
    procedure DoMaxRestoreClick(Sender: TObject);
    procedure DoCloseClick(Sender: TObject);
  protected
    { The window-behavior engine. Protected so a test access subclass can read its
      drag/maximize state through it. }
    FEngine: TTyChromeEngine;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
    { DESIGN-TIME hint (not a block): a control dropped straight onto the form — bypassing the content
      Surface — is allowed, but a GRAPHIC (windowless) control there renders onto the form and is
      occluded by the Surface, so we warn the user to move it into the Surface. Runtime unaffected. }
    procedure InsertControl(AControl: TControl; Index: Integer); override;
    { Non-mac: the associated menu bar owns shortcut dispatch — forward the key to
      its TMainMenu before the inherited (Form.Menu / action-list) handling. On mac
      the global Form.Menu already does this, so the override just calls inherited. }
    function IsShortcut(var Message: TLMKey): Boolean; override;
    { Build (or refresh) FSharpBackdrop/FGlassBackdrop — the photo snapshot every glass
      child SAMPLES — OFFSCREEN, without a paint cycle. Keyed on imagepath|WxH|blurDev so
      it rebuilds only when something changes; frees + clears the backdrop on a non-image
      theme. Called from Paint (so the in-paint path stays in sync) AND from ApplyChromeTheme
      (so a theme-apply readies the backdrop even when WS_CLIPCHILDREN starves the form of a
      WM_PAINT — the original "photo only after min/restore" bug). Never blits to the canvas. }
    procedure RebuildBackdrop;
    procedure Paint; override;   // draws an image backdrop when the TyForm token sets one
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoOnChangeBounds; override;
    { The widgetset reports the resulting window state after every size change it originated
      (LM_SIZE -> TScrollingWinControl.WMSize -> here). This is the ONLY way a maximize the
      chrome did not perform — Aero Snap to the top edge, Win+Up, the taskbar's system menu —
      reaches the engine; see TTyChromeEngine.SyncNativeMaximized for what it does with it. }
    procedure Resizing(State: TWindowState); override;
    {$IF DEFINED(LCLGtk2) or DEFINED(LCLGtk3) or DEFINED(LCLQt5) or DEFINED(LCLQt6)}
    { GTK/Qt resize-reception gutter: inset the client rect by FBorderZone so alClient
      children stop short of the edge and the form's edge strip receives the mouse.
      GTK3 was missing from this list, which is not a style choice -- ManualResizeEnabled
      returns True for every non-Win32 widgetset, so GTK3 was running the manual resize
      hit-test on every mouse move against an edge strip that alClient children were
      covering. The hit flipped as the pointer moved, taking the cursor and the chrome's
      focus/hover rendering with it: the reported "flickers madly whenever the mouse moves,
      stops the moment it stops".
      Windows (native NC border) and Cocoa (resizable styleMask) need no gutter — the
      IFDEF leaves their build with inherited only. }
    procedure AdjustClientRect(var ARect: TRect); override;
    { #15 candidate: after a popup menu closes, GTK/Qt deliver no mouse-move, so a border-
      resize cursor set while hovering the gutter sticks over the whole form. Both events
      DO arrive on menu-close — the pointer re-enters the form, and (for a modal/native menu)
      the window re-activates — so clear the resize cursor here. Harmless: the next real move
      re-derives the correct cursor. NEEDS Qt/GTK verification. }
    procedure CMMouseEnter(var Message: TLMessage); message CM_MOUSEENTER;
    procedure Activate; override;
    {$ENDIF}
    procedure DoShow; override;   // first show: apply window corners + shadow once the handle exists
    { Re-derive the title bar's height AFTER LCL has scaled the form for a new monitor.

      a6256 removed the double application by DERIVING the height in HandleChangeBounds instead
      of multiplying the running value. That fixed the case where LCL scaled first -- but it is
      gated on CurPPI <> FInstalledPPI, so it only corrects ONCE per monitor change, and it does
      not care who ran first. Cross a monitor and ChangeBounds can arrive BEFORE
      WM_DPICHANGED: the engine then derives the correct height and records the new PPI, LCL's
      pass multiplies that correct height by To/From a moment later, and the next ChangeBounds
      sees CurPPI = FInstalledPPI and declines to fix it. The bar stays ~2.5x too tall until
      something else moves the window across a DPI boundary again -- which is exactly the
      reported "sometimes it works, sometimes the titlebar is 2x higher, only on the 250%
      monitor", and exactly why it would not reproduce on the next run.

      Overriding here removes the ordering from the question: this runs immediately after LCL's
      own adjustment, and TyTitleBarDeviceHeight is a pure function of (pinned logical height or
      theme metric, PPI), so re-deriving is idempotent no matter what ran before it. }
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: Double); override;
  public
    constructor Create(AOwner: TComponent); override;
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    procedure ApplyChromeTheme(AController: TTyStyleController);
    procedure ApplyWindowEffects;   // (re)apply OS rounded corners + native shadow from the TyForm style
    { Render the themed `form` background into ACanvas over ARect. Public so TTyFormSurface can paint
      the identical background onto its OWN (edge-reaching) canvas. Uses the form's controller (or the
      built-in default). }
    procedure RenderBackgroundTo(ACanvas: TCanvas; const ARect: TRect);
    { Public trigger for RebuildBackdrop, so the surface can keep the glass snapshot current from its
      own paint cycle (the form's own Paint no longer fires once the surface covers the client). }
    procedure EnsureBackdrop;
    { Window-shade toggle: collapse the window to just its title bar (saving the full height),
      or restore it. No-op without an associated title bar. Also driven by caption double-click
      when CaptionAction = tcaRollUp. }
    procedure ToggleRollUp;
    property RolledUp: Boolean read FRolledUp;
    { The fully-resolved chrome style this window is rendered from: the active theme's TyForm
      token with StyleOverride merged on top — exactly what ApplyWindowEffects and the
      background paint consume. Falls back to the built-in default controller when no
      Controller is assigned (same policy as ApplyWindowEffects / ThemedBgColor). Public as the
      one honest query for tests and tooling. }
    function CurrentStyle: TTyStyleSet;
    function GetVersion: string;
  published
    { Read-only library version (TyVersion); the design-time editor for this property opens
      the About dialog. }
    property Version: string read GetVersion;
    { The style controller that themes this whole window. Assigning it applies the theme
      (the same effect as calling ApplyChromeTheme) and propagates the controller to the
      title bar + caption buttons; a streamed value is applied in Loaded once the title bar
      exists. Leave it unset to use the built-in default theme (TyDefaultController), or wire
      it to the main window's controller so the whole app shares one theme. }
    property Controller: TTyStyleController read FController write SetController;
    { Per-instance chrome override: a bare CSS declaration block merged over the resolved TyForm
      style for THIS window only — the same property every styled Ty control has, parsed by the
      same engine (var(--x) binds to the active theme and re-binds after a switch). Assigning it
      at runtime re-applies the whole chrome immediately, so e.g.
        Form.StyleOverride := 'window-shadow: false; border-radius: 0;'
      flips the native OS shadow/corners live, and 'background: #202030;' recolours the window.
      The OS corner/shadow path works with or without a Controller (built-in default controller
      fallback); the themed background paint keeps its existing rule of drawing only when a
      Controller is assigned. }
    property StyleOverride: string read FStyleOverride write SetStyleOverride;
    property TitleBar: TTyTitleBar read FTitleBar write SetTitleBar;
    { Designate the primary application menu bar. Non-mac: the bar stays visible and
      owns shortcut dispatch (IsShortcut forwards to its TMainMenu). Mac: the bar's
      TMainMenu is handed to the inherited Form.Menu (the global top-of-screen bar)
      and the in-window bar is hidden. Freeing the bar nils this (FreeNotification). }
    property MenuBar: TTyMenuBar read FMenuBar write SetMenuBar;
    { Title-bar height. Unset, it follows the density axis (classic 32 / modern --control-height,
      applied by ApplyChromeTheme); an explicit value pins it. Streamed only when explicitly set
      (stored FTitleHeightExplicit) so a density-driven height is never baked into the .lfm. }
    property TitleHeight: Integer read GetTitleHeight write SetTitleHeight stored FTitleHeightExplicit;
    { Whether the window can be edge-resized. Default True (the borderless window is
      resizable — the fix for the long-standing "no TTyForm could resize" bug). Setting
      False makes a fixed-size window AND disables maximize (a fixed window can't
      maximize): the title-bar max button is disabled and double-click-maximize is gated.
      Published so it persists in the .lfm; applied at runtime (chrome paths guard
      csDesigning). }
    property Resizable: Boolean read FResizable write SetResizable default True;
    { What a caption/title-bar double-click does: maximize (default), roll-up (window shade),
      or nothing. Persists in the .lfm. }
    property CaptionAction: TTyCaptionAction read FCaptionAction write FCaptionAction default tcaMaximize;
    { Locked: a TTyForm is a borderless custom-chrome window. Any assignment is coerced
      to bsNone; hidden from the Object Inspector via a design-time property editor. }
    property BorderStyle: TFormBorderStyle read GetBorderStyleTy write SetBorderStyleTy default bsNone;
    { Standard border icons drive the caption buttons: biSystemMenu->close,
      biMinimize->minimize, biMaximize->maximize (only when Resizable). }
    property BorderIcons: TBorderIcons read GetBorderIconsTy write SetBorderIconsTy
      default [biSystemMenu, biMinimize, biMaximize];
  end;

{ The title bar's height in LOGICAL px for the density AController is on: classic returns 32
  verbatim (byte-identical -- the token is not consulted), modern reads --titlebar-height.
  WHY a token of its own rather than --control-height, which is what the bar used to follow:
  a title bar HOSTS controls, so a bar exactly one control tall leaves a full-height child
  no room -- it meets both edges, and any top offset spills past the bottom. AController may
  be nil (falls back to the default controller). }
function TyTitleBarHeightFor(AController: TTyStyleController): Integer;

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
{ Resize-gated edge hit-test: bhNone when not AResizable, else TyHitTestBorder. A pure
  function (no window handle) so the gating is unit-testable; the chrome engine routes its
  edge hits through this so a non-resizable form never starts a resize / shows a resize cursor. }
function TyResizeHitFor(AResizable: Boolean; const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
{ Linux resize-gutter math (pure): insets AClient by AZone on each side when
  (ANeedsGutter and AResizable and not AMaximized) — so alClient children stop short of the
  form edge and the edge strip receives the mouse — else returns AClient unchanged. }
function TyResizeGutterRect(const AClient: TRect; AZone: Integer; AResizable, AMaximized, ANeedsGutter: Boolean): TRect;

{ Win32's answer to the same problem the gutter solves on GTK/Qt, for the one mode where a gutter
  cannot be used. With window-shadow:false the WM_NCCALCSIZE gives the client the WHOLE window
  rect (anything less lets the OS legacy-paint a pale classic ring over the L/R/B bands), so the
  alClient content host covers every pixel and the form is never hit-tested -- which is why such a
  window could not be edge-resized with the mouse at all. Insetting the host instead would leave a
  visible band of form background around it, so the host keeps its size and reports HTTRANSPARENT
  in the band instead, handing the point down to the form.

  True = "not mine, ask the window underneath". ASurface and APt are in the SAME space (the caller
  uses screen coords, because that is what WM_NCHITTEST's lParam carries).

  A host narrower than two zones is entirely band. That is deliberate and matches the OS: a window
  shrunk to the sizing frame is all sizing frame. }
function TyEdgePassthrough(const ASurface: TRect; const APt: TPoint;
  AZone: Integer; AEnabled: Boolean): Boolean;
{ Which caption buttons a form's chrome shows, from the standard BorderIcons plus the
  Resizable flag: close<=biSystemMenu, minimize<=biMinimize, maximize<=(biMaximize and
  AResizable) — a fixed-size window shows no maximize. Pure (no window handle) so it is
  unit-tested directly. }
function TyResolveCaptionButtons(ABorderIcons: TBorderIcons; AResizable: Boolean): TTyCaptionButtonFlags;

{ The whole horizontal layout of a title bar, in one pure function -- see TTyCaptionLayout for
  why it is one. Widths are device px; ALeadPadPx is the caption's pad at the reading start.

  ARightToLeft MIRRORS the finished layout about the bar's vertical centre, so the cluster moves
  to the leading edge AND reverses: Close takes the window corner, then Maximize, then Minimize.
  Read in the direction the window reads, the sequence is still minimize / maximize / close --
  unchanged. That is what Windows does for a right-to-left window (it mirrors the entire
  non-client area via WS_EX_LAYOUTRTL), and a cluster that slid across as a block without
  reversing would put Minimize in the corner and Close in the middle, an order no platform has.

  Done as a REFLECTION of the left-to-right result rather than as a reverse packing loop, for
  the reason TyStatusPanelRects records: a reflection preserves the margins, the gaps and the
  flush-to-the-edge property for free, and those are exactly what a hand-written reverse loop
  loses to an off-by-one. }
function TyCaptionLayoutFor(AShowMin, AShowMax, AShowClose: Boolean;
  ABarWidth, ABarHeight, AButtonWidthPx, AMarginXPx, AMarginYPx, AGapPx,
  ALeadPadPx: Integer; ARightToLeft: Boolean = False): TTyCaptionLayout;

const
  { Win32 WM_NCHITTEST result codes, declared platform-neutrally so TyNcHitTest (a pure
    function compiled on EVERY widgetset for headless testing) needn't pull in the Windows
    unit. Values are the canonical winuser.h codes — identical to Windows.HTLEFT.., so on
    Win32 returning these is byte-for-byte the native protocol. See B1 spike note below. }
  TyHTCLIENT      = 1;
  TyHTCAPTION     = 2;
  TyHTLEFT        = 10;
  TyHTRIGHT       = 11;
  TyHTTOP         = 12;
  TyHTTOPLEFT     = 13;
  TyHTTOPRIGHT    = 14;
  TyHTBOTTOM      = 15;
  TyHTBOTTOMLEFT  = 16;
  TyHTBOTTOMRIGHT = 17;
  { Codes we never WANT but must recognise to reject: DefWindowProc derives a caption band
    (and the system-menu / min / max / close hot-spots inside it) from the window STYLES, so a
    custom-frame window that carries WS_CAPTION purely to get Aero Snap (see ApplyThickFrame in
    tyControls.Win32WS) is told its top strip is a caption it does not actually own. Clicking
    such a phantom hot-spot would minimize / maximize / close the window. TyResolveNcHit drops
    every code outside the TyHTLEFT..TyHTBOTTOMRIGHT sizing-frame range for exactly this reason. }
  TyHTSYSMENU     = 3;
  TyHTMINBUTTON   = 8;
  TyHTMAXBUTTON   = 9;
  TyHTCLOSE       = 20;

{ Pure Windows NC hit-test mapper (no window handle -> headless-testable on any platform).
  APt is in WINDOW-relative coords. Within AZone of an edge -> the matching HT* edge/corner
  code; y < ACaptionH and NOT on a resize edge -> TyHTCAPTION (the title-bar drag band); else
  TyHTCLIENT. When not AResizable, no edge code is ever returned (TyHTCAPTION/TyHTCLIENT only),
  so a fixed window keeps its drag band but cannot be resized. A resize edge WINS over the
  caption band (the top border stays grabbable on a captioned window). The Win32 WM_NCHITTEST
  bridge feeds its window-relative cursor point straight through this. }
function TyNcHitTest(const AWinRect: TRect; const APt: TPoint;
  AZone, ACaptionH: Integer; AResizable: Boolean): Integer;
{ Compose the OS's own WM_NCHITTEST answer with the mapper above — the whole hit-test policy of
  the borderless window in one pure function (ADefHit is what DefWindowProc returned).
  DefWindowProc is authoritative for ONE thing only: the real sizing frame it still owns
  (left/right/bottom + corners survive the top-only WM_NCCALCSIZE), because only it knows where
  that frame sits — it reaches into the invisible outer resize margin, which a mapper working
  from the window rect cannot see. Every other answer is ours: HTCLIENT (the whole custom-drawn
  window) and the phantom caption/sysmenu/min/max/close band DefWindowProc infers from
  WS_CAPTION. A MAXIMIZED window drops the frame codes too and hit-tests as caption/client only:
  it has no sizing border, and reporting the title band as HTCAPTION is precisely what makes the
  OS run its "drag a maximized window -> restore it under the cursor and keep dragging" loop. }
function TyResolveNcHit(ADefHit: Integer; const AWinRect: TRect; const APt: TPoint;
  AZone, ACaptionH: Integer; AResizable, AMaximized: Boolean): Integer;
function TyResizeCursor(AHit: TTyBorderHit): TCursor;
function TyMaximizedBounds(const AWorkArea: TRect): TRect;
{ Where a maximized window lands when the pointer tears it loose by its title bar. AMaxBounds is
  its current (maximized) rect, ANormalBounds the size to go back to, ACursor the pointer in
  screen coords. The restored window keeps ANormalBounds' SIZE and is placed so the pointer holds
  the same PROPORTIONAL spot along the title bar (grab a maximized window at 20% of its width and
  the restored one hangs 20% in from its left edge) at the same vertical offset — the native
  Windows/GNOME/KDE behaviour. A degenerate saved size falls back to half the maximized one so the
  window can never restore to nothing. Pure (no handle) -> unit-tested. }
function TyRestoreDragBounds(const AMaxBounds, ANormalBounds: TRect; const ACursor: TPoint): TRect;
function TyRescaleChromeMetric(AValue, AFromPPI, AToPPI: Integer): Integer;
{ a6256. The title bar's height in DEVICE px at APPI. Unlike TyRescaleChromeMetric above --
  which converts a value BETWEEN two PPIs and therefore accumulates when it is fed its own
  output -- this DERIVES the height from PPI-independent inputs, so it is idempotent and a
  monitor round trip is exact. Exported so the contract can be pinned directly; see
  TTitleBarDpiTest in tests/test.form.pas. }
function TyTitleBarDeviceHeight(AForm: TCustomForm; ABar: TTyTitleBar; APPI: Integer): Integer;

implementation

uses
  tyControls.StyleModel   // ResolveOverride + TyMergeStyleSet: the ONE StyleOverride parse/merge
  {$IFDEF LCLCOCOA}, CocoaAll{$ENDIF}
  {$IFDEF WINDOWS}, strings{$ENDIF}   // StrComp(PAnsiChar) for the WM_SETTINGCHANGE area check
  ;

{$IFDEF WINDOWS}
{ ============================================================================
  B1 SPIKE — how TTyForm intercepts WM_NCCALCSIZE / WM_NCHITTEST on LCL-Win32
  ----------------------------------------------------------------------------
  MECHANISM CHOSEN: subclass the HWND via SetWindowLongPtr(Handle, GWLP_WNDPROC, ..)
  after the handle exists, chaining the saved LCL window proc through CallWindowProc.
  Overriding TTyForm.WndProc does NOT work for either message — confirmed by reading
  C:\lazarus\lcl\interfaces\win32\win32callback.inc:

   - Every message enters WindowProc -> TWindowProcHelper.DoWindowProc, which inits
     WinProcess:=True, may DeliverMessage to the LCL control, then — unless the message
     is in a small "respect the LCL result" allow-list (keys / erasebkgnd / setcursor /
     IME / syscommand) — OVERWRITES the result with CallDefaultWindowProc while WinProcess
     stays True (line ~2679-2689).
   - WM_NCHITTEST (line ~2358) does SetLMessageAndParams(LM_NCHITTEST) but leaves
     WinProcess=True and is NOT in the allow-list -> a WndProc override's Result is
     discarded and DefWindowProc's value is returned. Override is futile.
   - WM_NCCALCSIZE is absent from DoWindowProc's case entirely -> PLMsg^.Msg stays
     LM_NULL, it is never delivered to the control (guard at line ~2620), and
     CallDefaultWindowProc returns. The LCL WndProc never even sees it.

  So we must sit IN FRONT of the LCL proc. Because pulling the Windows unit into THIS unit's
  global namespace shadows Types.Rect/Point + Classes.RegisterClass (which the rest of
  Form.pas relies on), the subclass machinery lives in a dedicated {$IFDEF WINDOWS} helper
  unit (tyControls.Win32WS) — the same isolation pattern as tyControls.WindowEffects /
  QtWS / Gtk2WS / Gtk3WS. That helper handles WM_NCCALCSIZE (collapse the non-client area so the client
  fills the whole window while the WS_THICKFRAME sizing border stays hit-testable) +
  WM_NCHITTEST (return TyNcHitTest, the pure mapper that stays HERE next to TyHitTestBorder),
  and chains CallWindowProc(savedProc, ..) for everything else. WS_THICKFRAME — stripped from
  a bsNone form — is re-asserted after the handle exists (DoShow / on Resizable change). The
  install is idempotent + per-handle; the original proc is restored on WM_NCDESTROY. This is
  the standard Chrome/VS Code/WinUI custom-frame route, and mirrors the existing "LCL-Win32
  swallows WM_SETTINGCHANGE in its callback" lesson. ApplyResizeStrategy (below) drives it.
  ============================================================================ }
{$ENDIF}

function TyTitleBarHeightFor(AController: TTyStyleController): Integer;
begin
  Result := TyDensityMetric(AController, TyTitleBarClassicHeight, '--titlebar-height');
end;

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
var
  OnLeft, OnRight, OnTop, OnBottom: Boolean;
begin
  Result := bhNone;
  if AZone <= 0 then
    Exit;
  if (APt.X < AClient.Left) or (APt.X > AClient.Right) or
     (APt.Y < AClient.Top) or (APt.Y > AClient.Bottom) then
    Exit;
  OnLeft := APt.X < (AClient.Left + AZone);
  OnRight := APt.X > (AClient.Right - AZone);
  OnTop := APt.Y < (AClient.Top + AZone);
  OnBottom := APt.Y > (AClient.Bottom - AZone);
  if OnTop and OnLeft then
    Result := bhTopLeft
  else if OnTop and OnRight then
    Result := bhTopRight
  else if OnBottom and OnLeft then
    Result := bhBottomLeft
  else if OnBottom and OnRight then
    Result := bhBottomRight
  else if OnLeft then
    Result := bhLeft
  else if OnRight then
    Result := bhRight
  else if OnTop then
    Result := bhTop
  else if OnBottom then
    Result := bhBottom
  else
    Result := bhNone;
end;

function TyResizeHitFor(AResizable: Boolean; const AClient: TRect;
  const APt: TPoint; AZone: Integer): TTyBorderHit;
begin
  if not AResizable then
    Result := bhNone
  else
    Result := TyHitTestBorder(AClient, APt, AZone);
end;

function TyResolveCaptionButtons(ABorderIcons: TBorderIcons; AResizable: Boolean): TTyCaptionButtonFlags;
begin
  Result := [];
  if biSystemMenu in ABorderIcons then Include(Result, cbfClose);
  if biMinimize in ABorderIcons then Include(Result, cbfMinimize);
  if (biMaximize in ABorderIcons) and AResizable then Include(Result, cbfMaximize);
end;

function TyCaptionLayoutFor(AShowMin, AShowMax, AShowClose: Boolean;
  ABarWidth, ABarHeight, AButtonWidthPx, AMarginXPx, AMarginYPx, AGapPx,
  ALeadPadPx: Integer; ARightToLeft: Boolean): TTyCaptionLayout;
var
  n, h, y, x, span: Integer;
  bar: TRect;

  { One slot, taken off the running x. The cluster PACKS: a hidden button consumes neither a
    slot nor a gap, so hiding the middle one slides the outer two together. }
  function TakeSlot(var AX: Integer): TRect;
  begin
    Dec(AX, AButtonWidthPx);
    Result := Rect(AX, y, AX + AButtonWidthPx, y + h);
    Dec(AX, AGapPx);
  end;

begin
  Result := Default(TTyCaptionLayout);
  h := ABarHeight - 2 * AMarginYPx;   // inset top+bottom by the vertical margin (0 = full height)
  if h < 1 then h := ABarHeight;
  y := AMarginYPx;
  { Always packed left-to-right first, close outermost; the mirror at the bottom turns that into
    the right-to-left picture in one step. }
  x := ABarWidth - AMarginXPx;
  if AShowClose then Result.CloseBtn := TakeSlot(x);
  if AShowMax   then Result.MaxBtn   := TakeSlot(x);
  if AShowMin   then Result.MinBtn   := TakeSlot(x);

  n := Ord(AShowMin) + Ord(AShowMax) + Ord(AShowClose);
  if n = 0 then
    span := 0                          // no buttons -> no reserved strip at all
  else
    // both margins + N buttons + (N-1) gaps: the left margin is the caption's gap before the group
    span := 2 * AMarginXPx + n * AButtonWidthPx + (n - 1) * AGapPx;
  Result.Band := Rect(ABarWidth - span, 0, ABarWidth, ABarHeight);
  Result.Content := Rect(ALeadPadPx, 0, ABarWidth - span, ABarHeight);
  if Result.Content.Right < Result.Content.Left then
    Result.Content.Right := Result.Content.Left;

  { MIRROR once, at the end, through LCL's own five-liner (controls.pp:2966) -- and over EVERY
    rect in the record, so the cluster, the strip it reserves and the zone left for the caption
    cannot end up on different sides of the bar. This one statement is the whole mirror: the
    side, the internal order, the margins and the gaps all follow from it. }
  if ARightToLeft then
  begin
    bar := Rect(0, 0, ABarWidth, 0);
    Result.MinBtn   := BidiFlipRect(Result.MinBtn, bar, True);
    Result.MaxBtn   := BidiFlipRect(Result.MaxBtn, bar, True);
    Result.CloseBtn := BidiFlipRect(Result.CloseBtn, bar, True);
    Result.Band     := BidiFlipRect(Result.Band, bar, True);
    Result.Content  := BidiFlipRect(Result.Content, bar, True);
  end;
end;

function TyResizeGutterRect(const AClient: TRect; AZone: Integer;
  AResizable, AMaximized, ANeedsGutter: Boolean): TRect;
begin
  Result := AClient;
  if ANeedsGutter and AResizable and not AMaximized then
  begin
    Inc(Result.Left, AZone);
    Inc(Result.Top, AZone);
    Dec(Result.Right, AZone);
    Dec(Result.Bottom, AZone);
    // A tiny client must not invert: clamp the far edges to the near ones.
    if Result.Right < Result.Left then Result.Right := Result.Left;
    if Result.Bottom < Result.Top then Result.Bottom := Result.Top;
  end;
end;

function TyEdgePassthrough(const ASurface: TRect; const APt: TPoint;
  AZone: Integer; AEnabled: Boolean): Boolean;
begin
  if (not AEnabled) or (AZone <= 0) then Exit(False);
  Result := (APt.X < ASurface.Left + AZone) or (APt.X >= ASurface.Right - AZone)
         or (APt.Y < ASurface.Top + AZone) or (APt.Y >= ASurface.Bottom - AZone);
end;

function TyNcHitTest(const AWinRect: TRect; const APt: TPoint;
  AZone, ACaptionH: Integer; AResizable: Boolean): Integer;
var
  Hit: TTyBorderHit;
begin
  // Edge zones first (the top edge must win over the caption band). TyResizeHitFor folds in
  // the Resizable gate, so a fixed window never yields an edge/corner code.
  Hit := TyResizeHitFor(AResizable, AWinRect, APt, AZone);
  case Hit of
    bhLeft:        Exit(TyHTLEFT);
    bhRight:       Exit(TyHTRIGHT);
    bhTop:         Exit(TyHTTOP);
    bhBottom:      Exit(TyHTBOTTOM);
    bhTopLeft:     Exit(TyHTTOPLEFT);
    bhTopRight:    Exit(TyHTTOPRIGHT);
    bhBottomLeft:  Exit(TyHTBOTTOMLEFT);
    bhBottomRight: Exit(TyHTBOTTOMRIGHT);
  end;
  // Not on a resize edge: the title-bar drag band (when a bar is associated -> ACaptionH>0),
  // else plain client. APt is window-relative, so the band is [AWinRect.Top .. +ACaptionH).
  if (ACaptionH > 0) and (APt.Y >= AWinRect.Top) and (APt.Y < AWinRect.Top + ACaptionH) then
    Result := TyHTCAPTION
  else
    Result := TyHTCLIENT;
end;

function TyResolveNcHit(ADefHit: Integer; const AWinRect: TRect; const APt: TPoint;
  AZone, ACaptionH: Integer; AResizable, AMaximized: Boolean): Integer;
var
  Sizable: Boolean;
begin
  // A maximized window has no sizing border (and a fixed one never had any), so in both cases
  // the OS's frame codes are dropped and the mapper runs with resizing off — leaving the caption
  // band and plain client, which is exactly what a maximized/fixed window should report.
  Sizable := AResizable and not AMaximized;
  if Sizable and (ADefHit >= TyHTLEFT) and (ADefHit <= TyHTBOTTOMRIGHT) then
    Exit(ADefHit);
  Result := TyNcHitTest(AWinRect, APt, AZone, ACaptionH, Sizable);
end;

function TyResizeCursor(AHit: TTyBorderHit): TCursor;
begin
  case AHit of
    bhLeft, bhRight: Result := crSizeWE;
    bhTop, bhBottom: Result := crSizeNS;
    bhTopLeft, bhBottomRight: Result := crSizeNWSE;
    bhTopRight, bhBottomLeft: Result := crSizeNESW;
  else
    Result := crDefault;
  end;
end;

function TyMaximizedBounds(const AWorkArea: TRect): TRect;
begin
  Result.Left := AWorkArea.Left;
  Result.Top := AWorkArea.Top;
  Result.Right := AWorkArea.Right;
  Result.Bottom := AWorkArea.Bottom;
end;

function TyRestoreDragBounds(const AMaxBounds, ANormalBounds: TRect; const ACursor: TPoint): TRect;
var
  W, H, MaxW, GripX: Integer;
begin
  W := ANormalBounds.Right - ANormalBounds.Left;
  H := ANormalBounds.Bottom - ANormalBounds.Top;
  MaxW := AMaxBounds.Right - AMaxBounds.Left;
  // No usable saved size (never maximized through the engine, or a zeroed rect): half the
  // maximized window is a sane, always-visible fallback.
  if W <= 0 then W := MaxW div 2;
  if H <= 0 then H := (AMaxBounds.Bottom - AMaxBounds.Top) div 2;
  if MaxW > 0 then
    GripX := ((ACursor.X - AMaxBounds.Left) * W) div MaxW
  else
    GripX := W div 2;   // degenerate maximized rect: centre the window on the pointer
  // Keep the pointer INSIDE the restored window even if it sat outside the maximized rect.
  if GripX < 0 then GripX := 0;
  if GripX > W then GripX := W;
  Result.Left := ACursor.X - GripX;
  // Vertically the pointer keeps its offset from the top edge, so it stays on the title bar:
  // the restored top is simply the maximized top.
  Result.Top := AMaxBounds.Top;
  Result.Right := Result.Left + W;
  Result.Bottom := Result.Top + H;
end;

function TyRescaleChromeMetric(AValue, AFromPPI, AToPPI: Integer): Integer;
begin
  if AFromPPI <= 0 then
  begin
    Result := AValue;
    Exit;
  end;
  Result := (AValue * AToPPI + AFromPPI div 2) div AFromPPI;
end;

function TyTitleBarDeviceHeight(AForm: TCustomForm; ABar: TTyTitleBar; APPI: Integer): Integer;
{ a6256. The title bar's height in DEVICE px at APPI, derived from PPI-independent inputs
  only: either the height the host pinned (remembered as logical px) or the active theme's
  --titlebar-height under the current density. Because the answer is a pure function of
  (pin-or-metric, APPI), applying it twice is the same as applying it once and 96->250->96
  lands back on the 96 value exactly. That is the whole cure for "the layout is broken
  forever": nothing accumulates. }
var logical: Integer;
begin
  logical := 0;
  if (AForm is TTyForm) and TTyForm(AForm).FTitleHeightExplicit then
    logical := TTyForm(AForm).FTitleHeightLogical;
  if logical <= 0 then
    logical := TyTitleBarHeightFor(ABar.ActiveController);
  if APPI <= 0 then APPI := 96;
  Result := MulDiv(logical, APPI, 96);
end;

{ TTyCaptionButton }

procedure TTyCaptionButton.SetKind(AValue: TTyCaptionButtonKind);
begin
  // NB: do NOT early-exit on FKind = AValue. cbkClose is the enum default (0), so the close
  // button (created then set to cbkClose) would otherwise never sync StyleClass to 'close' —
  // leaving `TyCaptionButton.close { }` rules (e.g. XP's red close) unmatched. StyleClass has
  // its own no-op guard, so re-assigning the same value is cheap.
  FKind := AValue;
  StyleClass := KindVariant;
  Invalidate;
end;

function TTyCaptionButton.GetStyleTypeKey: string;
begin
  Result := 'TyCaptionButton';
end;

function TTyCaptionButton.KindVariant: string;
begin
  case FKind of
    cbkClose: Result := 'close';
    cbkMin: Result := 'min';
    cbkMax: Result := 'max';
    cbkRestore: Result := 'restore';
  end;
end;

function TTyCaptionButton.KindGlyph: TTyGlyphKind;
begin
  case FKind of
    cbkClose: Result := tgClose;
    cbkMin: Result := tgMinimize;
    cbkMax: Result := tgMaximize;
    cbkRestore: Result := tgRestore;
  end;
end;

function TTyCaptionButton.KindGlyphToken: string;
begin
  case FKind of
    cbkClose: Result := '--glyph-close';
    cbkMin: Result := '--glyph-minimize';
    cbkMax: Result := '--glyph-maximize';
    cbkRestore: Result := '--glyph-restore';
  else Result := '';
  end;
end;

procedure TTyCaptionButton.SetShowGlyphOnHoverOnly(AValue: Boolean);
begin
  if FShowGlyphOnHoverOnly = AValue then
    Exit;
  FShowGlyphOnHoverOnly := AValue;
  Invalidate;
end;

procedure TTyCaptionButton.Click;
begin
  inherited Click;
end;

procedure TTyCaptionButton.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, GlyphRect: TRect;
  GlyphSize: Integer;
  CX, CY: Integer;
  DrawGlyph: Boolean;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    { Determine whether glyph should be drawn }
    if FShowGlyphOnHoverOnly then
      DrawGlyph := FHover or FPressed
    else
      DrawGlyph := True;
    if DrawGlyph then
    begin
      // DrawGlyph insets ~4 logical px per side, so the glyph box must be that much
      // larger than the desired stroke extent or the icon collapses to a few pixels.
      // Density axis: classic keeps the bespoke 18 logical px (byte-identical); modern reads
      // --icon-size (20) so the caption glyphs match the roomier modern chrome. Gated on density
      // because the classic theme DEFINES --icon-size:16 -- reading the token unconditionally would
      // shrink the classic caption glyph from 18 to 16 (a drift). 20 keeps a healthy margin over
      // DrawGlyph's ~4px/side inset floor.
      if ActiveController.Density = tdModern then
        GlyphSize := P.Scale(TyDensityMetric(ActiveController, 18, '--icon-size'))
      else
        GlyphSize := P.Scale(18);
      CX := R.Left + (R.Right - R.Left - GlyphSize) div 2;
      CY := R.Top + (R.Bottom - R.Top - GlyphSize) div 2;
      GlyphRect := Rect(CX, CY, CX + GlyphSize, CY + GlyphSize);
      // v3/C5: the caption glyph is theme-overridable with an icon-font codepoint.
      TyDrawGlyph(P, ActiveController, GlyphRect, KindGlyphToken, KindGlyph, S.TextColor, 1);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCaptionButton.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ TTyTitleBar }

constructor TTyTitleBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Act as a real container: the designer drops controls INTO the bar (a menubar,
  // a button, …) instead of as siblings, and they lay out in the content zone that
  // AdjustClientRect carves out (left pad .. start of the caption buttons).
  ControlStyle := ControlStyle + [csAcceptsControls];
  FButtonWidth := TyTitleButtonWidth;
  FButtonWidthPPI := 96;   // a6256: the un-pinned default is a LOGICAL constant
  FTitleAlignment := taLeftJustify;
  // A title bar belongs at the top of the window by default. (The streaming default stays
  // alNone, so existing .lfm files keep writing `Align = alTop` explicitly — no change for
  // them — but a freshly dropped/created bar now snaps to the top strip on its own.)
  Align := alTop;
  // Height follows the density axis: classic 32 (byte-identical); modern --titlebar-height when a
  // modern controller is already active at construction. Streamed forms associate the controller AFTER
  // this ctor, so TTyForm.ApplyChromeTheme re-derives the bar height once its controller is applied.
  SetBounds(0, 0, 200, TyTitleBarHeightFor(ActiveController));
  FMinButton := TTyCaptionButton.Create(Self);
  FMinButton.Kind := cbkMin;
  FMinButton.Parent := Self;
  FMaxButton := TTyCaptionButton.Create(Self);
  FMaxButton.Kind := cbkMax;
  FMaxButton.Parent := Self;
  FCloseButton := TTyCaptionButton.Create(Self);
  FCloseButton.Kind := cbkClose;
  FCloseButton.Parent := Self;
  LayoutButtons;
  { If the owner form auto-assigned this bar during InsertComponent (which fires
    BEFORE this ctor body, so the buttons were nil then), wire them now that they
    exist. The TTyForm-side method is design-time/nil guarded. }
  if (AOwner is TTyForm) and (TTyForm(AOwner).TitleBar = Self) then
    TTyForm(AOwner).WireTitleBarButtons;
end;

function TTyTitleBar.GetStyleTypeKey: string;
begin
  Result := 'TyTitleBar';
end;

procedure TTyTitleBar.SetCaption(const AValue: TCaption);
begin
  if FCaption = AValue then
    Exit;
  FCaption := AValue;
  Invalidate;
end;

procedure TTyTitleBar.SetButtonWidth(AValue: Integer);
begin
  FButtonWidthExplicit := True;   // an explicit set pins the width, overriding the theme metric
  { a6256: stamp the PPI the pin was taken at, so a later monitor change can derive from
    (value, PPI) instead of multiplying the field. Stamped even when the value is unchanged
    -- re-pinning the same number on a different monitor is a legitimate re-anchor. }
  FButtonWidthPPI := Font.PixelsPerInch;
  if FButtonWidthPPI <= 0 then FButtonWidthPPI := 96;
  if FButtonWidth = AValue then
    Exit;
  FButtonWidth := AValue;
  LayoutButtons;
  Invalidate;
end;

function TTyTitleBar.EffectiveButtonWidthPx: Integer;
begin
  if FButtonWidthPPI <= 0 then
    FButtonWidthPPI := 96;   // a pin taken before the stamp existed reads as logical px
  if FButtonWidthExplicit then
    { a6256: derive from the pinned (width @ PPI) pair. At the PPI it was pinned at this is
      the identity -- so ButtonWidth := 50 still measures exactly 50 -- and on another
      monitor it scales once, from the pin, never from the last scaled value. }
    Result := MulDiv(FButtonWidth, Font.PixelsPerInch, FButtonWidthPPI)
  else
    // Theme-driven default: --caption-button-width is logical px; scale to the current PPI. A skin
    // (e.g. classic's small Win9x caption buttons) sets it; unset falls back to TyTitleButtonWidth.
    Result := MulDiv(ActiveController.Metric('--caption-button-width', TyTitleButtonWidth),
                     Font.PixelsPerInch, 96);
end;

procedure TTyTitleBar.SetTitleAlignment(AValue: TAlignment);
begin
  if FTitleAlignment = AValue then
    Exit;
  FTitleAlignment := AValue;
  Invalidate;
end;

function TTyTitleBar.GetShowMinimize: Boolean;
begin Result := (FMinButton = nil) or FMinButton.Visible; end;

function TTyTitleBar.GetShowMaximize: Boolean;
begin Result := (FMaxButton = nil) or FMaxButton.Visible; end;

function TTyTitleBar.GetShowClose: Boolean;
begin Result := (FCloseButton = nil) or FCloseButton.Visible; end;

procedure TTyTitleBar.SetShowMinimize(AValue: Boolean);
begin
  if FMinButton = nil then Exit;
  if FMinButton.Visible = AValue then Exit;
  FMinButton.Visible := AValue;
  LayoutButtons;
end;

procedure TTyTitleBar.SetShowMaximize(AValue: Boolean);
begin
  if FMaxButton = nil then Exit;
  if FMaxButton.Visible = AValue then Exit;
  FMaxButton.Visible := AValue;
  LayoutButtons;
end;

procedure TTyTitleBar.SetShowClose(AValue: Boolean);
begin
  if FCloseButton = nil then Exit;
  if FCloseButton.Visible = AValue then Exit;
  FCloseButton.Visible := AValue;
  LayoutButtons;
end;

function TTyTitleBar.CapMarginPx: Integer;
begin
  Result := MulDiv(ActiveController.Metric('--caption-button-margin', 0), Font.PixelsPerInch, 96);
end;

function TTyTitleBar.CapMarginYPx: Integer;
{ Vertical (top/bottom) inset. --caption-button-margin-y if set, else the uniform margin. }
var my: Integer;
begin
  my := ActiveController.Metric('--caption-button-margin-y', -1);
  if my < 0 then my := ActiveController.Metric('--caption-button-margin', 0);
  Result := MulDiv(my, Font.PixelsPerInch, 96);
end;

function TTyTitleBar.CapGapPx: Integer;
begin
  Result := MulDiv(ActiveController.Metric('--caption-button-gap', 0), Font.PixelsPerInch, 96);
end;

function TTyTitleBar.RightInset: Integer;
begin
  { The cluster's width, taken from the band the layout reserved -- not restated here. That
    restatement was the second, independent claim about the caption buttons' x, and it is what
    made a mirror a two-place change. }
  with CaptionLayout.Band do Result := Right - Left;
end;

function TTyTitleBar.LeftInsetPx: Integer;
begin
  Result := MulDiv(ActiveController.Metric('--titlebar-padding', TyTitleBarPad), Font.PixelsPerInch, 96);
end;

function TTyTitleBar.CaptionLayoutAt(AWidth, AHeight: Integer): TTyCaptionLayout;
var
  sMin, sMax, sClose: Boolean;
begin
  { The ctor sets the bar's bounds BEFORE it builds the three buttons, so this can be reached
    with all of them still nil -- reserve nothing then, exactly as the VisibleButtonCount rule
    this replaced did. (GetShowMinimize & co. answer True for a nil button, which is right for
    the published property and wrong here.) }
  sMin := False; sMax := False; sClose := False;
  if (FMinButton <> nil) and (FMaxButton <> nil) and (FCloseButton <> nil) then
  begin
    sMin := FMinButton.Visible;
    sMax := FMaxButton.Visible;
    sClose := FCloseButton.Visible;
  end;
  Result := TyCaptionLayoutFor(sMin, sMax, sClose,
    AWidth, AHeight, EffectiveButtonWidthPx,
    CapMarginPx, CapMarginYPx, CapGapPx, LeftInsetPx, IsRightToLeft);
end;

function TTyTitleBar.CaptionLayout: TTyCaptionLayout;
begin
  Result := CaptionLayoutAt(ClientWidth, ClientHeight);
end;

procedure TTyTitleBar.LayoutButtons;
var
  lay: TTyCaptionLayout;

  procedure Place(ABtn: TTyCaptionButton; const R: TRect);
  begin
    if ABtn.Visible then
      ABtn.SetBounds(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
  end;

begin
  if (FCloseButton = nil) or (FMaxButton = nil) or (FMinButton = nil) then
    Exit;
  { These three SetBounds are also the buttons' hit test, their hover zone and their pressed
    zone: they are windowed children, so LCL routes every one of those by the bounds written
    here. That is why the cluster's geometry only ever needs to be right in ONE place. }
  lay := CaptionLayout;
  Place(FCloseButton, lay.CloseBtn);
  Place(FMaxButton, lay.MaxBtn);
  Place(FMinButton, lay.MinBtn);
end;

procedure TTyTitleBar.Resize;
begin
  inherited Resize;
  LayoutButtons;
end;

procedure TTyTitleBar.AdjustClientRect(var ARect: TRect);
var
  w: Integer;
  lay: TTyCaptionLayout;
begin
  inherited AdjustClientRect(ARect);
  { Applied as INSETS rather than as absolute edges, so an ancestor that had already narrowed
    ARect keeps its narrowing. The content zone comes from the same layout that places the
    buttons, so the side this gives up can never be the side they are not on. }
  w := ARect.Right - ARect.Left;
  lay := CaptionLayoutAt(w, ARect.Bottom - ARect.Top);
  Dec(ARect.Right, w - lay.Content.Right);
  Inc(ARect.Left, lay.Content.Left);
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
end;

{ A title bar is a CONTAINER: hosts drop theme pickers, appearance buttons and menu bars on
  it. The caption used to be drawn across the whole bar (minus only the caption-button inset)
  regardless, so with TitleAlignment = taRightJustify it ran leftwards UNDER those children
  and they painted over it -- the demo's title read "ntrols Demo" as soon as a skin with
  roomier buttons (xp) pushed the cluster further right. Clipping is not the answer either;
  the caption simply has to live in the space the children leave.

  So: take the widest contiguous gap the children do not cover. Scanning gaps rather than
  assuming children sit on the left keeps this correct for a host that anchors something to
  the right instead. }
procedure TTyTitleBar.CaptionSpan(AWidth: Integer; out ALeft, ARight: Integer);
var
  i, bl, br, gl, gr, bestL, bestR, scan: Integer;
  c: TControl;
  edges: array of Integer;
  n, j, tmp: Integer;
  lay: TTyCaptionLayout;
begin
  { The zone comes from the layout that places the buttons -- so on a mirrored bar the scan
    below starts AFTER the cluster instead of ending before it, and the gap-scanning logic
    itself needs no direction of its own: it takes the widest gap in whatever band it is given. }
  lay := CaptionLayoutAt(AWidth, ClientHeight);
  ALeft := lay.Content.Left;
  ARight := lay.Content.Right;
  if ARight < ALeft then ARight := ALeft;

  { Collect the children's spans, clipped to the caption band. }
  n := 0;
  SetLength(edges, ControlCount * 2);
  for i := 0 to ControlCount - 1 do
  begin
    c := Controls[i];
    if (c = nil) or not c.Visible then Continue;
    bl := c.Left;
    br := c.Left + c.Width;
    if br <= ALeft then Continue;
    if bl >= ARight then Continue;
    if bl < ALeft then bl := ALeft;
    if br > ARight then br := ARight;
    edges[n] := bl; edges[n + 1] := br; Inc(n, 2);
  end;
  if n = 0 then Exit;

  { Sort the spans by left edge (few children: an insertion sort is plenty). }
  for i := 2 to n - 2 do
    if (i mod 2) = 0 then
    begin
      j := i;
      while (j >= 2) and (edges[j - 2] > edges[j]) do
      begin
        tmp := edges[j - 2]; edges[j - 2] := edges[j]; edges[j] := tmp;
        tmp := edges[j - 1]; edges[j - 1] := edges[j + 1]; edges[j + 1] := tmp;
        Dec(j, 2);
      end;
    end;

  { Widest gap between the covered spans. }
  bestL := ALeft; bestR := ALeft; scan := ALeft;
  i := 0;
  while i < n do
  begin
    gl := scan;
    gr := edges[i];
    if gr - gl > bestR - bestL then begin bestL := gl; bestR := gr; end;
    if edges[i + 1] > scan then scan := edges[i + 1];
    Inc(i, 2);
  end;
  if ARight - scan > bestR - bestL then begin bestL := scan; bestR := ARight; end;

  ALeft := bestL;
  ARight := bestR;
  if ARight < ALeft then ARight := ALeft;
end;

procedure TTyTitleBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextRect: TRect;
  W, H, tl, tr: Integer;
begin
  W := ARect.Right - ARect.Left;
  H := ARect.Bottom - ARect.Top;
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, W, H);
    { Opt into the painter's alignment lever: TitleAlignment is a READING-ORDER alignment, so on
      a mirrored bar taLeftJustify has to resolve to the right-hand edge of the span. The span
      itself has already changed ends (CaptionSpan reads the mirrored layout), so both halves --
      which side the text box is on, and which side the text hugs inside it -- move together. }
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    CaptionSpan(W, tl, tr);
    TextRect := Rect(R.Left + tl, R.Top, R.Left + tr, R.Top + H);
    P.DrawText(TextRect, FCaption, S.FontName, ResolveFontSize(S), S.FontWeight,
      S.TextColor, FTitleAlignment, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTitleBar.Paint;
begin
  // Re-apply the (theme-metric) button width on every repaint, so switching to a skin that sets
  // --caption-button-width resizes the caption buttons live. LayoutButtons no-ops when the bounds
  // are already correct, so a normal repaint costs a var lookup + three unchanged SetBounds.
  LayoutButtons;
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyTitleBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  {$IFDEF LCLWin32}
  // Top-edge resize hot-zone: the bar sits flush at the window top (no NC strip there — that
  // would be an ugly thick frame), so the OS can't resize from the top edge. Grab the top
  // FBorderZone px ourselves and hand a NATIVE top-resize to the OS instead of starting a drag.
  if (Button = mbLeft) and (FEngine <> nil) and not (csDesigning in ComponentState)
     and FEngine.FormResizable and not FEngine.Maximized and (Y < FEngine.BorderZone) then
  begin
    TyNcBeginTopResize(GetParentForm(Self));
    Exit;
  end;
  {$ENDIF}
  inherited MouseDown(Button, Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.TitleBarMouseDown(Button, Shift, X, Y);
end;

procedure TTyTitleBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  {$IFDEF LCLWin32}
  // Show the N-S resize cursor over the top hot-zone (matches the MouseDown top-resize above).
  if (FEngine <> nil) and not (csDesigning in ComponentState)
     and FEngine.FormResizable and not FEngine.Maximized and (Y < FEngine.BorderZone) then
    Cursor := crSizeNS
  else
    Cursor := crDefault;
  {$ENDIF}
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.TitleBarMouseMove(Shift, X, Y);
end;

procedure TTyTitleBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.TitleBarMouseUp(Button, Shift, X, Y);
end;

procedure TTyTitleBar.DblClick;
begin
  inherited DblClick;
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.TitleBarDblClick;
end;

procedure TTyTitleBar.CMBiDiModeChanged(var Message: TLMessage);
begin
  inherited;         // LCL invalidates, tells the children, and calls AdjustSize
  LayoutButtons;     // and then the caption buttons have to actually change sides
end;

{ TTyChromeEngine }

constructor TTyChromeEngine.Create;
begin
  inherited Create;
  FBorderZone := 6;
  FMaximized := False;
end;

function TTyChromeEngine.FormResizable: Boolean;
begin
  if FForm is TTyForm then
    Result := TTyForm(FForm).Resizable
  else
    Result := True;
end;

function TTyChromeEngine.ManualResizeEnabled: Boolean;
begin
  {$IFDEF LCLWin32}
  Result := False;   // native NC resize (WS_THICKFRAME + WM_NCHITTEST) owns it on the Win32 widgetset
  {$ELSE}
  Result := FormResizable;   // Qt6/GTK (any OS): drive resize manually via the edge gutter + FormMouse*
  {$ENDIF}
end;

procedure TTyChromeEngine.CaptureInstalledPPI;
begin
  if (FForm <> nil) and (FForm.Monitor <> nil) then
    FInstalledPPI := FForm.Monitor.PixelsPerInch
  else
    FInstalledPPI := Screen.PixelsPerInch;
end;

procedure TTyChromeEngine.StartPlatformDrag(const ACursor: TPoint);
var
  WasDragging: Boolean;
begin
  if FForm = nil then Exit;
  WasDragging := FDragging;
  FDragging := False;   // clear BEFORE the (blocking, modal) Win32 loop — see the declaration
  if TyStartSystemMove(FForm) then
  begin
    SetCaptureControl(nil);   // don't let LCL's capture fight the WM's move grab
    Exit;
  end;
  // No system move on this widgetset: keep dragging by hand from where we are now.
  FDragging := WasDragging;
  FDragStart := ACursor;
  FDragFormStart := Point(FForm.Left, FForm.Top);
end;

procedure TTyChromeEngine.TitleBarMouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (FForm <> nil) then
    TitleBarDragBegin(Mouse.CursorPos);
end;

procedure TTyChromeEngine.TitleBarDragBegin(const ACursor: TPoint);
begin
  if FForm = nil then Exit;
  { A MAXIMIZED window has no position to drag, so nothing is handed to the WM on the press —
    it only ARMS the drag. TitleBarDragUpdate tears the window loose (restore under the pointer,
    then carry on dragging) once the pointer has actually travelled, so a plain click and the
    double-click-to-restore on a maximized caption still behave. }
  if not FMaximized then
  begin
    // Linux: hand the drag to the window manager — a programmatic move() is ignored mid-grab on
    // Qt/X11, and gtk_window_move() gets clamped to the whole-screen bounds on GTK2 (so a window on
    // a non-bottom-aligned second monitor can't be dragged past mid-screen). Qt6 -> startSystemMove,
    // GTK2 -> begin_move_drag; both let the WM cross monitors freely. When a system move starts we
    // release LCL's just-set mouse capture so it doesn't fight the WM's move grab (else after one
    // drag the capture leaks -> the whole window stays in move-mode). No per-move repositioning then
    // (FDragging stays False -> TitleBarDragUpdate no-ops). Win32/Qt5 -> False -> fallback below.
    // Qt6 -> startSystemMove, GTK2 -> begin_move_drag: both are NON-BLOCKING (the WM takes the drag
    // asynchronously), so they can start on the press. Win32's caption move (WM_NCLBUTTONDOWN) is a
    // BLOCKING modal loop that would swallow a double-click's second press -> it is deferred to
    // TitleBarDragUpdate and armed only past a small drag threshold (so plain click / double-click to
    // maximize still work). Win32 therefore falls through here to the manual-drag setup below.
    if TyStartSystemMove(FForm, {AIncludeBlocking:}False) then
    begin
      SetCaptureControl(nil);
      Exit;
    end;
  end;
  FDragging := True;
  // Use the GLOBAL cursor + the form's start origin, not client-relative deltas: on Qt/X11 a
  // programmatic move during a mouse grab is flaky, so we set the ABSOLUTE target each move
  // (mathematically identical to the old delta on Win32/GTK2, so those are unaffected).
  FDragStart := ACursor;
  FDragFormStart := Point(FForm.Left, FForm.Top);
end;

procedure TTyChromeEngine.TitleBarMouseMove(Shift: TShiftState; X, Y: Integer);
begin
  TitleBarDragUpdate(Mouse.CursorPos);
end;

procedure TTyChromeEngine.TitleBarDragUpdate(const ACursor: TPoint);
const
  DragThreshold = 4;   // px the pointer must travel before the drag leaves the press site
var
  Moved: Boolean;
begin
  if (not FDragging) or (FForm = nil) then Exit;
  Moved := (Abs(ACursor.X - FDragStart.X) > DragThreshold)
        or (Abs(ACursor.Y - FDragStart.Y) > DragThreshold);
  if FMaximized then
  begin
    { Tearing a maximized window loose — what every native title bar does, and what this window
      could not do before (the press used to be ignored outright, leaving a maximized window
      undraggable). Gated on real pointer travel so a click / double-click still only toggles. }
    if not Moved then Exit;
    if FNativeMaximize then
    begin
      {$IFDEF LCLWin32}
      // The OS owns this maximize AND its restore rect, and its caption-move loop already
      // implements restore-under-the-cursor-then-keep-dragging for a zoomed window. Hand the
      // gesture over untouched rather than second-guessing the geometry; the SIZE_RESTORED it
      // produces syncs the engine back through TTyForm.Resizing.
      {$ELSE}
      // No such loop here: put the window back through the WM (which holds the restore rect)
      // first, then drag the restored window.
      FForm.WindowState := wsNormal;
      ApplyMaximizedState(False, False);
      {$ENDIF}
    end
    else
    begin
      // The engine's own work-area maximize: WE hold the restore rect, so place the window back
      // under the pointer ourselves (it keeps its relative grip along the title bar).
      FForm.BoundsRect := TyRestoreDragBounds(FForm.BoundsRect, FSavedBounds, ACursor);
      ApplyMaximizedState(False, False);
    end;
    StartPlatformDrag(ACursor);
    Exit;
  end;
  {$IFDEF LCLWin32}
  // Win32: once the pointer has actually moved (so a plain click / double-click never triggers it),
  // hand the rest of the drag to the OS caption-move loop -> native Aero Snap + snap preview.
  // A sub-threshold jiggle keeps the window still (no manual move).
  if Moved then
    StartPlatformDrag(ACursor);
  {$ELSE}
  // Cocoa (+ Qt5/other fallbacks): reposition manually to the absolute target each move. Qt6/GTK2
  // never reach here (they took the async system move on the press -> FDragging stayed False); GTK2
  // modal dialogs included -- TyGtk2StartSystemMove drops GTK's modal grab across the WM move rather
  // than falling back here, so a modal dialog drags in real time instead of crawling per gtk_window_move.
  FForm.Left := FDragFormStart.X + (ACursor.X - FDragStart.X);
  FForm.Top  := FDragFormStart.Y + (ACursor.Y - FDragStart.Y);
  {$ENDIF}
end;

procedure TTyChromeEngine.TitleBarMouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
end;

procedure TTyChromeEngine.TitleBarDblClick;
begin
  FDragging := False;   // the double-click's press armed a drag; cancel it before we resize
  if FForm is TTyForm then
    case TTyForm(FForm).CaptionAction of
      tcaRollUp: begin TTyForm(FForm).ToggleRollUp; Exit; end;
      tcaNone:   Exit;
    end;
  ToggleMaximize;
end;

procedure TTyChromeEngine.FormMouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button <> mbLeft) or (FForm = nil) or FMaximized then
    Exit;
  FResizeHit := TyResizeHitFor(ManualResizeEnabled, Rect(0, 0, FForm.Width, FForm.Height),
    Point(X, Y), FBorderZone);
  if FResizeHit <> bhNone then
  begin
    FResizing := True;
    FResizeStartBounds := FForm.BoundsRect;
    FResizeStartMouse := FForm.ClientToScreen(Point(X, Y));
  end;
end;

procedure TTyChromeEngine.FormMouseMove(Shift: TShiftState; X, Y: Integer);
var
  M: TPoint;
  DX, DY: Integer;
  B: TRect;
begin
  if FForm = nil then
    Exit;
  { Hover path (not actively resizing): reflect the border zone under the cursor
    so the user sees the native resize cursor before pressing. While FResizing is
    True the cursor was already set on the hit press and the form is being sized,
    so we leave it alone and fall through to the resize-drag logic below. }
  if not FResizing then
  begin
    FForm.Cursor := TyResizeCursor(TyResizeHitFor(ManualResizeEnabled,
      Rect(0, 0, FForm.Width, FForm.Height), Point(X, Y), FBorderZone));
    Exit;
  end;
  M := FForm.ClientToScreen(Point(X, Y));
  DX := M.X - FResizeStartMouse.X;
  DY := M.Y - FResizeStartMouse.Y;
  B := FResizeStartBounds;
  case FResizeHit of
    bhNone: ;
    bhLeft: B.Left := B.Left + DX;
    bhRight: B.Right := B.Right + DX;
    bhTop: B.Top := B.Top + DY;
    bhBottom: B.Bottom := B.Bottom + DY;
    bhTopLeft: begin B.Left := B.Left + DX; B.Top := B.Top + DY; end;
    bhTopRight: begin B.Right := B.Right + DX; B.Top := B.Top + DY; end;
    bhBottomLeft: begin B.Left := B.Left + DX; B.Bottom := B.Bottom + DY; end;
    bhBottomRight: begin B.Right := B.Right + DX; B.Bottom := B.Bottom + DY; end;
  end;
  if B.Right - B.Left < 80 then
    case FResizeHit of
      bhLeft, bhTopLeft, bhBottomLeft: B.Left := B.Right - 80;
    else
      B.Right := B.Left + 80;
    end;
  if B.Bottom - B.Top < 60 then
    case FResizeHit of
      bhTop, bhTopLeft, bhTopRight: B.Top := B.Bottom - 60;
    else
      B.Bottom := B.Top + 60;
    end;
  FForm.BoundsRect := B;
end;

procedure TTyChromeEngine.FormMouseUp(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FResizing := False;
  FResizeHit := bhNone;
end;

procedure TTyChromeEngine.ClearResizeCursor;
begin
  if (FForm <> nil) and not FResizing and (FForm.Cursor <> crDefault) then
    FForm.Cursor := crDefault;
end;

procedure TTyChromeEngine.NoteInstalledPPI(APPI: Integer);
begin
  if APPI > 0 then FInstalledPPI := APPI;
end;

procedure TTyChromeEngine.HandleChangeBounds;
var
  CurPPI: Integer;
begin
  if FForm = nil then Exit;
  if FTitleBar = nil then Exit;
  if FForm.Monitor <> nil then
    CurPPI := FForm.Monitor.PixelsPerInch
  else
    CurPPI := Screen.PixelsPerInch;
  if (FInstalledPPI > 0) and (CurPPI <> FInstalledPPI) then
  begin
    { ===== a6256: DERIVED, not MUTATED ======================================
      This used to read

        FTitleBar.Height       := TyRescaleChromeMetric(FTitleBar.Height, From, To);
        FTitleBar.FButtonWidth := TyRescaleChromeMetric(FTitleBar.FButtonWidth, From, To);

      i.e. it multiplied the CURRENT height by To/From on every monitor crossing.

      THE DEFECT IS DOUBLE APPLICATION, not rounding. LCL already scales this bar:
      WM_DPICHANGED -> TCustomForm.WMDPIChanged -> AutoAdjustLayout ->
      TControl.DoAutoAdjustLayout multiplies the bounds of every alTop,
      AutoSize=False child by To/From (control.inc:3168). Crossing a monitor then
      fired ChangeBounds, and THIS method multiplied the already-scaled height a
      second time. Measured on the reporter's 100% -> 250% pair, a 32 px bar came
      out at 216 px instead of 83 -- 6.75x rather than 2.6x. That is exactly the
      "TyTitleBar is far too tall at high DPI" half of the report.

      Rounding was NOT a contributor, and the original suspicion that it was is
      recorded here so nobody re-derives it: TyRescaleChromeMetric rounds half-up,
      and over 16..120 px against 120/144/240/250 PPI, three there-and-back trips
      return the exact starting value for EVERY height. (scripts were run; see
      TTitleBarDpiTest.TestAccumulatingRescaleSquares for the shape that does bite.)
      The "layout broken forever" half of the report is a DIFFERENT defect, in the
      controls rather than the chrome -- see the FOLLOW-UP note at the end of this
      comment.

      Deriving the height from the theme metric at the current PPI removes the
      double application: the value is a pure function of (metric, CurPPI), so
      running it twice is the same as running it once, and it can no longer compose
      with LCL's pass into a squared factor. It is the same expression
      ApplyChromeTheme already uses, which is why the two no longer fight.

      FOLLOW-UP (measured, NOT fixed here -- the files belong to other controls):
      TTyButton/TTyCheckBox/TTyToggleSwitch/TTyButtonGroup write a DEVICE-px floor
      into Constraints.MinHeight (e.g. tyControls.Button.pas:697) that they derive
      from the live PPI, while LCL independently scales both Constraints and Height
      in its own pass. The two compose the same way this one did, and that one does
      NOT come back: a TTyButton measured 29 px at 96, 175 px at 240, and 70 px on
      return to 96. A plain LCL TButton in the same form round-tripped exactly.

      An EXPLICIT TitleHeight is honoured by scaling the LOGICAL value the user
      pinned (captured at its own PPI), not the running device value -- derived
      again, so it round-trips too.

      FButtonWidth is deliberately NOT touched any more: when the width is not
      pinned, EffectiveButtonWidthPx already derives it from --caption-button-width
      at the live Font.PixelsPerInch, so there is no state here to rescale; when it
      IS pinned, TTyTitleBar.SetButtonWidth records the logical value and
      EffectiveButtonWidthPx scales that. Rescaling the field as well was the third
      multiplication in the same chain. }
    FTitleBar.Height := TyTitleBarDeviceHeight(FForm, FTitleBar, CurPPI);
    FTitleBar.LayoutButtons;
    FInstalledPPI := CurPPI;
    FForm.Invalidate;
    // The rescaled caption height (and possibly the border zone) feed the native NC hit-test
    // on Windows, so refresh the strategy with the new metrics (no-op off Windows / no handle).
    if FForm is TTyForm then TTyForm(FForm).ApplyResizeStrategy;
  end;
end;

procedure TTyChromeEngine.ApplyMaximizedState(AMaximized, ANative: Boolean);
begin
  FMaximized := AMaximized;
  FNativeMaximize := AMaximized and ANative;
  if FTitleBar <> nil then
  begin
    if AMaximized then
      FTitleBar.MaxButton.Kind := cbkRestore
    else
      FTitleBar.MaxButton.Kind := cbkMax;
  end;
  if FForm is TTyForm then
  begin
    // corners must go square when maximized and round again when restored
    TTyForm(FForm).ApplyWindowEffects;
    // refresh the NC strategy: when (un)maximized the WM_NCCALCSIZE inset must turn off/on
    // (a maximized window must NOT keep the resize border, else content overhangs the work area).
    TTyForm(FForm).ApplyResizeStrategy;
  end;
end;

procedure TTyChromeEngine.SyncNativeMaximized(AMaximized: Boolean);
begin
  { Reconcile the chrome with a maximize/restore the ENGINE did not perform — Aero Snap to the
    top edge, Win+Up, the taskbar's system menu, a WM keybinding. Without this the window sits
    at maximized size while the chrome still believes it is normal: rounded corners on a
    full-screen window, a "maximize" glyph that maximizes AGAIN instead of restoring, and a
    saved-bounds rect that has been overwritten with the maximized rect — i.e. maximized but
    not restorable.

    Only the OS's own transitions count. A "restored" report that arrives while the ENGINE's
    work-area maximize is active means nothing: that maximize is a plain SetBounds, so every
    resize it causes is reported as restored, and honouring it would cancel the maximize the
    instant it happened. }
  if FForm = nil then Exit;
  if AMaximized then
  begin
    if FMaximized and FNativeMaximize then Exit;
    ApplyMaximizedState(True, True);
  end
  else
  begin
    if not (FMaximized and FNativeMaximize) then Exit;
    ApplyMaximizedState(False, False);
  end;
end;

procedure TTyChromeEngine.ToggleMaximize;
var
  Wa: TRect;
  Mon: TMonitor;
begin
  if FForm = nil then
    Exit;
  // A double-click that maximizes presses the title bar first (arming a drag); cancel it so a
  // trailing MouseMove can't move the just-maximized window.
  FDragging := False;
  // A fixed (non-resizable) window can't maximize. This gates BOTH entry points
  // (the title-bar double-click via TitleBarDblClick and the max button); the button
  // is also disabled when not resizable (SetResizable). When already maximized,
  // still allow the restore branch so a window can't get stuck maximized.
  if (not FormResizable) and (not FMaximized) then
    Exit;
  if FMaximized then
  begin
    if FNativeMaximize then
    begin
      // The window manager owns this maximize and the restore rect that goes with it, so restore
      // THROUGH it — it puts the window back exactly where it came from (with the native restore
      // animation), which no rect we could invent would match. The chrome is reconciled first so
      // the size change this triggers finds SyncNativeMaximized with nothing left to do.
      ApplyMaximizedState(False, False);
      FForm.WindowState := wsNormal;
    end
    else
    begin
      FForm.BoundsRect := FSavedBounds;
      ApplyMaximizedState(False, False);
    end;
  end
  else
  begin
    FSavedBounds := FForm.BoundsRect;
    { Screen.MonitorFromWindow can return nil (an off-screen / not-yet-mapped handle,
      or a multi-monitor edge case); guard it so double-click-to-maximize can't AV —
      fall back to the primary monitor's work area. }
    Mon := Screen.MonitorFromWindow(FForm.Handle);
    if Mon <> nil then
      Wa := Mon.WorkareaRect
    else
      Wa := Screen.WorkAreaRect;
    FForm.BoundsRect := TyMaximizedBounds(Wa);
    ApplyMaximizedState(True, False);
  end;
end;

{ TTyForm }

procedure TTyForm.SetupChrome;
begin
  BorderStyle := bsNone;
  FResizable := True;
  // Seed the standard caption-button set so SyncCaptionButtons shows min/max/close by default.
  // A CreateNew form does not inherit the full default set, and a streamed .lfm only overrides it.
  BorderIcons := [biSystemMenu, biMinimize, biMaximize];
  FEngine := TTyChromeEngine.Create;
  FEngine.Form := Self;
  // The content host (TTyFormSurface) is NOT created here — it is streamed from the .lfm as
  // `object Surface: TTyFormSurface` with the controls nested under it, so graphic controls paint on
  // its canvas (visible) and it covers the WS_THICKFRAME dead band. Loaded wires FSurface via
  // FindComponent. Creating it here (a second, code-side instance) would collide with the streamed one.
end;

function TTyForm.GetVersion: string;
begin
  Result := TyVersion;
end;

constructor TTyForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  if FEngine = nil then SetupChrome;
end;

constructor TTyForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  if FEngine = nil then SetupChrome;
end;

destructor TTyForm.Destroy;
begin
  // FSurface is owned by the form (streamed) — the inherited destructor frees it; just drop our ref.
  FSurface := nil;
  FreeAndNil(FFollowTimer);   // disarm the OS-follow poll
  FreeAndNil(FSharpBackdrop);
  FreeAndNil(FGlassBackdrop);
  if FTitleBar <> nil then FTitleBar.FEngine := nil;
  // NIL it, don't just free it: the window is still alive until inherited Destroy, so a late
  // size message (-> Resizing -> the engine) must find no engine rather than a dangling one.
  FreeAndNil(FEngine);
  inherited Destroy;
end;

procedure TTyForm.SetTitleBar(AValue: TTyTitleBar);
begin
  if AValue = FTitleBar then Exit;
  if (AValue <> nil) and (AValue.Owner <> Self) and (GetParentForm(AValue) <> Self) then
    raise EInvalidOperation.Create('TTyTitleBar can only be associated with the form it belongs to');
  // unwire old bar
  if FTitleBar <> nil then
  begin
    FTitleBar.FEngine := nil;
    // The buttons are created in the bar's ctor body. When SetTitleBar runs from
    // the owner-form Notification(opInsert) — which TComponent.Create fires BEFORE
    // the bar's ctor body — they may still be nil, so guard every deref.
    if FTitleBar.MinButton <> nil then FTitleBar.MinButton.OnClick := nil;
    if FTitleBar.MaxButton <> nil then FTitleBar.MaxButton.OnClick := nil;
    if FTitleBar.CloseButton <> nil then FTitleBar.CloseButton.OnClick := nil;
  end;
  FTitleBar := AValue;
  if FEngine <> nil then FEngine.TitleBar := AValue;
  if AValue <> nil then
  begin
    AValue.FreeNotification(Self);
    SyncCaptionButtons;   // reflect current BorderIcons onto the bar immediately
    // Arm the live engine ONLY at runtime — never in the designer (dragging the
    // title bar would move/maximize the window instead of selecting it), and not
    // mid-load: when the bar comes from the .lfm this setter runs at fixup time
    // while csLoading is still set, and ArmEngine touches Monitor (premature handle
    // realization). Loaded arms it once streaming has finished.
    if not (csDesigning in ComponentState) and not (csLoading in ComponentState) then
      ArmEngine;
  end;
end;

{ Designate (or clear) the primary application menu bar. The cross-platform split:
  on macOS the bar's TMainMenu becomes the inherited Form.Menu (LCL renders it as
  the global top-of-screen bar) and the in-window bar is hidden; everywhere else the
  in-window bar stays visible and owns shortcut dispatch via IsShortcut. }
procedure TTyForm.SetMenuBar(AValue: TTyMenuBar);
begin
  if AValue = FMenuBar then Exit;
  {$IFDEF DARWIN}
  // Detach the previous bar's menu from the global bar before switching.
  if (FMenuBar <> nil) and (Menu = FMenuBar.Menu) then
    Menu := nil;
  {$ENDIF}
  FMenuBar := AValue;
  if AValue <> nil then
  begin
    AValue.FreeNotification(Self);
    {$IFDEF DARWIN}
    // Hand the bar's TMainMenu to the inherited Form.Menu (the global bar) and hide
    // the in-window bar; the OS draws the menu at the top of the screen.
    Menu := AValue.Menu;
    AValue.Visible := False;
    {$ENDIF}
  end;
end;

function TTyForm.IsShortcut(var Message: TLMKey): Boolean;
begin
  {$IFNDEF DARWIN}
  // Non-mac: the in-window menu bar owns dispatch. Let its TMainMenu try to match
  // and fire the shortcut first; on mac the inherited path already consults the
  // global Form.Menu (assigned in SetMenuBar), so we skip straight to inherited.
  if (FMenuBar <> nil) and (FMenuBar.Menu <> nil)
     and FMenuBar.Menu.IsShortCut(Message) then
    Exit(True);
  {$ENDIF}
  Result := inherited IsShortcut(Message);
end;

{ Connect the title bar to the live engine: back-reference so the bar's mouse
  events reach the engine, capture the install DPI, and wire the caption buttons.
  Safe to call repeatedly; never runs in the designer or before load completes. }
procedure TTyForm.ArmEngine;
begin
  if (FTitleBar = nil) or (csDesigning in ComponentState) then Exit;
  FTitleBar.FEngine := FEngine;
  if FEngine <> nil then FEngine.CaptureInstalledPPI;
  WireTitleBarButtons;
  // A bar that associated AFTER the window was shown changes the caption-drag band height,
  // so refresh the native NC strategy (no-op without a handle / off Windows).
  ApplyResizeStrategy;
end;

procedure TTyForm.Loaded;
begin
  inherited Loaded;
  // Wire the streamed content host (the .lfm's `object Surface`, which already hosts every control as
  // its child — graphic controls included). nil for a code-created form with no .lfm.
  FSurface := TTyFormSurface(FindComponent('Surface'));
  // A title bar associated from the .lfm had its engine-arming deferred (see
  // SetTitleBar); now that streaming has finished, wire it to the live engine.
  ArmEngine;
  // A Controller streamed from the .lfm: SetController deferred during csLoading; apply now
  // that the title bar + every sub-component is assigned. (ApplyChromeTheme calls
  // ApplyWindowEffects itself, so the no-controller case still gets effects just below.)
  if FController <> nil then
    ApplyChromeTheme(FController);
  ApplyWindowEffects;   // handle exists post-load -> apply corners + shadow
  SyncCaptionButtons;   // streamed BorderIcons + bar: sync after all components loaded
end;

procedure TTyForm.InsertControl(AControl: TControl; Index: Integer);
begin
  inherited InsertControl(AControl, Index);
  // A control just became a DIRECT child of the form (bypassing the Surface). We do NOT block it —
  // library users must be free to parent to the form in code — but at DESIGN time a GRAPHIC control
  // there paints onto the form's canvas and is hidden behind the alClient Surface, so warn. Gated on
  // csDesigning + not loading (don't nag while an existing .lfm streams) + FSurface present (a
  // Surface-less form has no occlusion). The fired case is "form selected + double-click" — never a
  // live drag (which lands in the Surface), so a modal hint here is safe.
  if (csDesigning in ComponentState) and not (csLoading in ComponentState)
     and (FSurface <> nil) and (AControl <> nil) and (AControl <> FSurface)
     and (AControl is TGraphicControl) then
    MessageDlg('TyControls',
      Format(rsTyGraphicControlOnForm, [AControl.ClassName]), mtWarning, [mbOK], 0);
end;

procedure TTyForm.DoWarnSurfaceDeleted(Data: PtrInt);
begin
  MessageDlg('TyControls', rsTySurfaceDeleted, mtWarning, [mbOK], 0);
end;

procedure TTyForm.UpdateFollowWatch;
{ P4 (D8 / §3.7) LIVE FOLLOW. Arm a low-frequency poll timer exactly while the bound
  controller is following the OS; free it otherwise. We POLL rather than hook a window
  message because LCL-Win32 swallows WM_SETTINGCHANGE in its own callback (it calls
  Application.IntfSettingsChange and never DeliverMessage's it to a control's WndProc) and
  drops WM_DWMCOLORIZATIONCOLORCHANGED (< WM_USER) outright — so an overridden WndProc can
  never see either. The tick is cheap (PollSystemTheme no-ops until the OS scheme/accent
  actually moves), and re-evaluated on every ApplyChromeTheme so a Light/Dark button (which
  sets Follow:=tfManual) disarms it and an Auto/System button (tfFollowSystem) re-arms it. }
begin
  if (FController <> nil) and (FController.Follow = tfFollowSystem) then
  begin
    if FFollowTimer = nil then
    begin
      FFollowTimer := TTimer.Create(nil);   // no Owner: kept off the form's component list
      FFollowTimer.Enabled := False;
      FFollowTimer.Interval := 750;          // ≤0.75s latency on an OS toggle — imperceptible
      FFollowTimer.OnTimer := @DoFollowTick;
    end;
    FFollowTimer.Enabled := True;
  end
  else
    FreeAndNil(FFollowTimer);
end;

procedure TTyForm.DoFollowTick(Sender: TObject);
{ One poll tick. PollSystemTheme re-detects the OS scheme/accent and, only when it changed,
  re-applies it to the model + repaints registered controls, returning True. On True we also
  re-apply the form's OWN chrome (its solid Color / image backdrop / glass radius live in
  ApplyChromeTheme, which Changed does not touch). The whole effect is in PollSystemTheme so
  the logic stays headless-testable; this just drives it from the clock. }
begin
  if (FController <> nil) and FController.PollSystemTheme then
    ApplyChromeTheme(FController);
end;

{ Wire the caption-button click handlers. Split out so it can run both from
  SetTitleBar and from the title bar's own ctor tail — because when the bar is
  auto-assigned via Notification(opInsert) its buttons aren't created yet. }
procedure TTyForm.WireTitleBarButtons;
begin
  if FTitleBar = nil then Exit;
  SyncCaptionButtons;                               // visibility: design-time too
  if csDesigning in ComponentState then Exit;       // click handlers: runtime only
  if FTitleBar.MinButton <> nil then FTitleBar.MinButton.OnClick := @DoMinimizeClick;
  if FTitleBar.MaxButton <> nil then FTitleBar.MaxButton.OnClick := @DoMaxRestoreClick;
  if FTitleBar.CloseButton <> nil then FTitleBar.CloseButton.OnClick := @DoCloseClick;
end;

procedure TTyForm.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opInsert) and not (csLoading in ComponentState)
     and (FTitleBar = nil) and (AComponent.Owner = Self)
     and (AComponent is TTyTitleBar) then
    TitleBar := TTyTitleBar(AComponent)          // routes through SetTitleBar
  else if (Operation = opRemove) and (AComponent = FTitleBar) then
  begin
    FTitleBar := nil;
    if FEngine <> nil then FEngine.TitleBar := nil;
  end
  else if (Operation = opRemove) and (AComponent = FMenuBar) then
  begin
    {$IFDEF DARWIN}
    if Menu = FMenuBar.Menu then Menu := nil;
    {$ENDIF}
    FMenuBar := nil;
  end
  else if (Operation = opInsert) and (FSurface = nil) and (AComponent.Owner = Self)
     and (AComponent is TTyFormSurface) then
    FSurface := TTyFormSurface(AComponent)   // wire the content host (streamed or designer-added)
  else if (Operation = opRemove) and (AComponent = FSurface) then
  begin
    FSurface := nil;   // dropped ref: the one-surface guard relaxes so undo can paste it back in
    { Deleting the host takes every control it hosted with it, so say so — but NEVER from inside this
      notification (a modal loop there breaks the designer's delete/undo bookkeeping). Queue it to run
      once the delete has finished. Undo restores by PASTING, which fires opInsert, not opRemove, so
      this cannot pop spuriously on Ctrl+Z. }
    if (csDesigning in ComponentState) and not (csDestroying in ComponentState)
       and not (csLoading in ComponentState) then
      Application.QueueAsyncCall(@DoWarnSurfaceDeleted, 0);
  end
  else if (Operation = opRemove) and (AComponent = FController) then
    FController := nil;   // the bound controller was freed: drop the dangling ref
end;

procedure TTyForm.DoMinimizeClick(Sender: TObject);
begin
  // A borderless (bsNone) window minimized via WindowState shrinks to the legacy bottom-left
  // desktop box, NOT the taskbar. For the main form, minimize the whole app (LCL routes it to the
  // taskbar button); a secondary form falls back to the plain window state.
  if Application.MainForm = Self then
    Application.Minimize
  else
    WindowState := wsMinimized;
end;

procedure TTyForm.DoMaxRestoreClick(Sender: TObject);
begin
  if not FResizable then Exit;   // a fixed window can't maximize
  if FEngine <> nil then FEngine.ToggleMaximize;
end;

procedure TTyForm.DoCloseClick(Sender: TObject);
begin Close; end;

procedure TTyForm.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.FormMouseDown(Button, Shift, X, Y);
end;

procedure TTyForm.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.FormMouseMove(Shift, X, Y);
end;

procedure TTyForm.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.FormMouseUp(Button, Shift, X, Y);
end;

procedure TTyForm.DoOnChangeBounds;
begin
  inherited DoOnChangeBounds;
  FGlassKey := '';   // client size changed -> next Paint resnapshots the backdrop
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.HandleChangeBounds;
end;

procedure TTyForm.Resizing(State: TWindowState);
begin
  inherited Resizing(State);
  if (FEngine = nil) or (csDesigning in ComponentState) then Exit;
  { wsMinimized / wsFullScreen are deliberately NOT forwarded: minimizing a maximized window
    must not make the chrome forget it was maximized (Windows restores it straight back to
    maximized, and reports wsMaximized again when it does). }
  case State of
    wsMaximized: FEngine.SyncNativeMaximized(True);
    wsNormal:    FEngine.SyncNativeMaximized(False);
  end;
end;

{$IF DEFINED(LCLGtk2) or DEFINED(LCLGtk3) or DEFINED(LCLQt5) or DEFINED(LCLQt6)}
procedure TTyForm.AdjustClientRect(var ARect: TRect);
var
  zone: Integer;
  maxed: Boolean;
begin
  inherited AdjustClientRect(ARect);
  // The resize gutter (zone + maximized state live on the chrome engine). NeedsGutter=True
  // here because this override only compiles on the GTK/Qt widgetsets that require it.
  if FEngine <> nil then
  begin
    zone := FEngine.BorderZone;
    maxed := FEngine.Maximized;
  end
  else
  begin
    zone := 6;
    maxed := False;
  end;
  ARect := TyResizeGutterRect(ARect, zone, FResizable, maxed, True);
end;

procedure TTyForm.CMMouseEnter(var Message: TLMessage);
begin
  inherited;
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.ClearResizeCursor;   // #15: drop a resize cursor left stuck by a closed popup menu
end;

procedure TTyForm.Activate;
begin
  inherited Activate;
  if (FEngine <> nil) and not (csDesigning in ComponentState) then
    FEngine.ClearResizeCursor;   // #15: same, for a menu that briefly took window activation
end;
{$ENDIF}

function TTyForm.GetTitleHeight: Integer;
begin
  if FTitleBar <> nil then Result := FTitleBar.Height else Result := 0;
end;

procedure TTyForm.ToggleRollUp;
var
  th: Integer;
begin
  th := GetTitleHeight;
  if th <= 0 then Exit;   // no title bar -> nothing to roll up to
  if FRolledUp then
  begin
    FRolledUp := False;
    ApplyResizeStrategy;                        // restore WS_THICKFRAME BEFORE growing back
    Constraints.MinHeight := FSavedMinHeight;
    if FUnrolledHeight > th then Height := FUnrolledHeight;
  end
  else
  begin
    if Height <= th then Exit;   // already at/under the title bar height -> nothing to collapse
    FUnrolledHeight := Height;
    // A shown WS_THICKFRAME window won't shrink below the OS sizing-border minimum, which leaves a
    // content sliver under the title bar (Constraints can't override it). Drop the thick frame
    // while rolled (via ApplyResizeStrategy reading FRolledUp) so it collapses to exactly the title
    // bar; also lower Constraints.MinHeight. Both restored on unroll.
    FSavedMinHeight := Constraints.MinHeight;
    Constraints.MinHeight := th;
    FRolledUp := True;
    ApplyResizeStrategy;                        // strip WS_THICKFRAME BEFORE shrinking
    Height := th;
  end;
  ApplyWindowEffects;   // OS corners follow the new height
end;

procedure TTyForm.SetTitleHeight(AValue: Integer);
var ppi: Integer;
begin
  FTitleHeightExplicit := True;   // an explicit set (code/.lfm) pins the height, overriding the density metric
  { a6256. Remember the pin in LOGICAL px so a later monitor crossing can DERIVE the device
    height from it (see TyTitleBarDeviceHeight) instead of multiplying the running value.
    At 96 PPI -- the designer, the .lfm, and every single-monitor 100% run -- this is the
    identity, so nothing about the existing behaviour moves. }
  ppi := 96;
  if FTitleBar <> nil then ppi := FTitleBar.Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  FTitleHeightLogical := MulDiv(AValue, 96, ppi);
  if (FTitleBar <> nil) and (FTitleBar.Height <> AValue) then FTitleBar.Height := AValue;
end;

procedure TTyForm.SetResizable(AValue: Boolean);
begin
  if FResizable = AValue then Exit;
  FResizable := AValue;
  SyncCaptionButtons;   // Resizable gates the maximize button (hide, not just disable)
  ApplyResizeStrategy;   // per-platform style toggle (Windows: WS_THICKFRAME + NC subclass)
end;

function TTyForm.GetBorderStyleTy: TFormBorderStyle;
begin Result := inherited BorderStyle; end;

procedure TTyForm.SetBorderStyleTy(AValue: TFormBorderStyle);
begin
  if inherited BorderStyle <> bsNone then inherited BorderStyle := bsNone;
end;

function TTyForm.GetBorderIconsTy: TBorderIcons;
begin Result := inherited BorderIcons; end;

procedure TTyForm.SetBorderIconsTy(AValue: TBorderIcons);
begin
  inherited BorderIcons := AValue;
  SyncCaptionButtons;
  // biMaximize also drives the window's WS_MAXIMIZEBOX — which is what lets the OS maximize it
  // (Aero Snap to the top edge, Win+Up). The inherited setter recomputes that bit from BorderIcons
  // ALONE, ignoring Resizable, so re-assert our own combination on top of it.
  ApplyResizeStrategy;
end;

procedure TTyForm.SyncCaptionButtons;
var flags: TTyCaptionButtonFlags;
begin
  if FTitleBar = nil then Exit;
  flags := TyResolveCaptionButtons(BorderIcons, FResizable);
  FTitleBar.ShowMinimize := cbfMinimize in flags;
  FTitleBar.ShowMaximize := cbfMaximize in flags;
  FTitleBar.ShowClose    := cbfClose in flags;
end;

procedure TTyForm.ApplyResizeStrategy;
{$IFDEF LCLWin32}
var capH, zone: Integer; resiz, noFrame, maxed: Boolean; ctrl: TTyStyleController;
{$ENDIF}
begin
  if csDesigning in ComponentState then Exit;   // never poke the window on the design surface
  {$IFDEF LCLWin32}
  // Win32 widgetset native NC resize: assert/clear WS_THICKFRAME per FResizable + (re)install the HWND
  // subclass that handles WM_NCCALCSIZE/WM_NCHITTEST (see tyControls.Win32WS / the B1 note).
  // Caption-drag band height = the title bar's height when one is associated, else 0 (no caption
  // zone). Guarded by HandleAllocated (the helper also no-ops without a handle).
  if HandleAllocated then
  begin
    if FTitleBar <> nil then capH := FTitleBar.Height else capH := 0;
    if FEngine <> nil then zone := FEngine.BorderZone else zone := 6;
    // A rolled-up (window-shade) window drops WS_THICKFRAME: its sizing border enforces an OS
    // minimum window height that would otherwise leave a content sliver under the title bar, and
    // a collapsed window needs no edge-resize anyway. Restored when unrolled.
    resiz := FResizable and not FRolledUp;
    // window-shadow:false rides the NC strategy too: with DWM NC rendering disabled
    // (ApplyWindowEffects), the L/R/B frame bands would be legacy-painted as a classic ring, so
    // the NCCALCSIZE goes full-frame-eat while the opt-out is active. Same resolve (chrome style
    // incl. StyleOverride) + same controller fallback as ApplyWindowEffects, so the two stay in
    // lock-step across first show / theme switch / live override flip / maximize-restore.
    if FController <> nil then ctrl := FController else ctrl := TyDefaultController;
    noFrame := not TyResolveWindowEffect(ResolveChromeStyle(ctrl), False).Shadow;
    maxed := (FEngine <> nil) and FEngine.Maximized;
    TyNcApplyResize(Self, resiz, zone, capH,
      maxed,                                    // engine (work-area) maximize -> no NC inset
      resiz and (biMaximize in BorderIcons),    // allow native maximize (WS_MAXIMIZEBOX)
      noFrame);
    // The full-frame-eat above leaves the surface covering every pixel, so without this the
    // form is never hit-tested and the window cannot be edge-resized with the mouse at all.
    // See TyWin32SetEdgePassthrough for the measurements and for why the band is not simply
    // handed back to the OS.
    if (FSurface <> nil) and FSurface.HandleAllocated then
      TyNcSetEdgePassthrough(FSurface, zone, noFrame and resiz and not maxed);
  end;
  {$ENDIF}
  // GTK/Qt: the AdjustClientRect gutter + WM handoff (Phase C). Cocoa: resizable styleMask
  // (Phase C). Those bodies land later; the call sites (SetResizable + DoShow) are wired.
end;

function TTyForm.GlassBackdrop: TBGRABitmap;
begin
  Result := FGlassBackdrop;
end;

function TTyForm.GlassSharpBackdrop: TBGRABitmap;
begin
  Result := FSharpBackdrop;
end;

function TTyForm.GlassClientOrigin: TPoint;
begin
  Result := ClientOrigin;
end;

function TTyForm.GlassUnderTitlebar: Boolean;
begin
  Result := (FController <> nil)
    and ResolveChromeStyle(FController).BackgroundUnderTitlebar;
end;

procedure TTyForm.RebuildBackdrop;
var
  bg: TTyStyleSet;
  P: TTyPainter;
  blurDev: Integer;
  newKey: string;
begin
  // Non-image (or no controller): no photo backdrop -> drop any stale snapshot and bail.
  if FController = nil then
  begin
    FreeAndNil(FSharpBackdrop);
    FreeAndNil(FGlassBackdrop);
    FGlassKey := '';
    Exit;
  end;
  bg := ResolveChromeStyle(FController);
  if not ((tpBackground in bg.Present) and (bg.Background.Kind = tfkImage)) then
  begin
    FreeAndNil(FSharpBackdrop);   // non-image theme: drop any stale backdrop
    FreeAndNil(FGlassBackdrop);
    FGlassKey := '';
    Exit;
  end;
  if (ClientWidth <= 0) or (ClientHeight <= 0) then Exit;   // not laid out yet — nothing to snapshot
  // FSharpBackdrop is the photo base EVERY control samples for its corners, so build it for
  // ANY image theme; the once-blurred FGlassBackdrop is built only when the theme uses glass.
  // Keyed on image+client-size+blur so it rebuilds only when something changes (the blur
  // dev-px is in the key, so an image->image switch that drops glass rebuilds + frees the old
  // blurred backdrop). When the key is unchanged the snapshot is already current — skip.
  blurDev := MulDiv(FGlassBlurLogical, Font.PixelsPerInch, 96);
  newKey := bg.Background.ImagePath + '|' + IntToStr(ClientWidth) + 'x'
    + IntToStr(ClientHeight) + '|' + IntToStr(blurDev);
  if (FSharpBackdrop <> nil) and (newKey = FGlassKey) then Exit;
  // Build the snapshot OFFSCREEN. CRITICAL: pass a NIL canvas so EndPaint does NOT blit to
  // any DC (the form is WS_CLIPCHILDREN — drawing the photo here, outside a WM_PAINT, would
  // be erased or clobber the children); it still frees the painter's internal bitmap, which
  // TTyPainter only releases in EndPaint (no destructor), so this also avoids a leak. We
  // Duplicate the composited image BEFORE EndPaint frees P.Bitmap.
  P := TTyPainter.Create;
  try
    P.BeginPaint(nil, Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
    P.FillBackground(Rect(0, 0, ClientWidth, ClientHeight), bg.Background, 0);
    FreeAndNil(FSharpBackdrop);
    FreeAndNil(FGlassBackdrop);
    FSharpBackdrop := P.Bitmap.Duplicate as TBGRABitmap;  // photo base (all controls)
    if FGlassBlurLogical > 0 then
    begin
      if blurDev > 0 then
        FGlassBackdrop := FSharpBackdrop.FilterBlurRadial(blurDev, rbFast) as TBGRABitmap
      else
        FGlassBackdrop := FSharpBackdrop.Duplicate as TBGRABitmap;
    end;
    FGlassKey := newKey;
    P.EndPaint;   // nil canvas -> no blit, just frees P.Bitmap (avoids the leak)
  finally
    P.Free;
  end;
end;

procedure TTyForm.EnsureBackdrop;
begin
  RebuildBackdrop;
end;

procedure TTyForm.RenderBackgroundTo(ACanvas: TCanvas; const ARect: TRect);
var
  bg: TTyStyleSet;
  P: TTyPainter;
begin
  // Paint the themed `form` background (image / solid / gradient) OPAQUELY across ARect. Called BOTH
  // by the form's own Paint and by TTyFormSurface.Paint (onto the surface's edge-reaching canvas, so
  // the WS_THICKFRAME dead band is covered). The glass backdrop snapshot is kept current separately
  // via EnsureBackdrop. App controls paint on top in their own windows.
  if FController <> nil then
  begin
    bg := ResolveChromeStyle(FController);
    if tpBackground in bg.Present then
    begin
      P := TTyPainter.Create;
      try
        P.BeginPaint(ACanvas, ARect, Font.PixelsPerInch);
        P.FillBackground(ARect, bg.Background, 0);
        // Themed window frame (non-image themes; e.g. the XP Luna blue border). The title bar
        // covers the top run; the side + bottom runs show in the client margins.
        if (bg.Background.Kind <> tfkImage)
           and (tpBorderColor in bg.Present) and (bg.BorderWidth > 0) then
          P.StrokeBorder(ARect, bg.BorderRadius, bg.BorderWidth, bg.BorderColor);
        P.EndPaint;
      finally
        P.Free;
      end;
      Exit;
    end;
  end;
  // No controller / no bg token: opaque LCL Color fill (still covers the band with the fallback colour).
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := Color;
  ACanvas.FillRect(ARect);
end;

procedure TTyForm.Paint;
begin
  { DESIGN SURFACE: skip the full-client fill. On the Lazarus main IDE design surface the designer
    ends up drawing the form's children into the SAME DC before this runs, and this fill is a BGRA
    blit that overwrites whatever is already on the DC — so it painted OVER every child. The symptom
    was brutal and misleading: EVERY control inside a TTyForm vanished in the designer, including
    plain LCL ones (a bare TButton), while the identical form rendered perfectly at run time and
    under a headless csDesigning render, and TTy controls dropped on a plain TForm were fine.
    (Lazarus 4.4's designer paints in an order where this was harmless, which is why it only showed
    up on main.) At run time children are separate HWNDs clipped out of the parent DC, so the fill
    can't reach them and the themed background is still painted normally. The design-time background
    then comes from the form's ordinary LCL Color erase, which participates in child clipping. }
  if csDesigning in ComponentState then Exit;
  // Keep the glass snapshot current and paint the themed background on the form's own DC. Once
  // TTyFormSurface is installed it covers the client and repaints this SAME background edge-to-edge
  // (via RenderBackgroundTo) so the form's own Paint becomes a harmless fallback behind it.
  EnsureBackdrop;
  RenderBackgroundTo(Canvas, ClientRect);
end;

function TTyForm.ThemedBgColor(out AColor: TTyColor): Boolean;
{ The form's themed TyForm background colour, for a child's parent-bg fill. Resolves from
  the form's own controller when themed (= the LCL Color ApplyChromeTheme set), else from
  TyDefaultController (the built-in theme) — so it is correct in the DESIGNER too, where
  ApplyChromeTheme has not run and the raw LCL Color is the dark default. }
var
  ctrl: TTyStyleController;
  bg: TTyStyleSet;
begin
  Result := False;
  if FController <> nil then ctrl := FController else ctrl := TyDefaultController;
  bg := ResolveChromeStyle(ctrl);
  if (tpBackground in bg.Present) and (bg.Background.Kind = tfkSolid) then
  begin
    AColor := bg.Background.Color;
    Result := True;
  end;
end;

procedure TTyForm.ApplyChromeTheme(AController: TTyStyleController);
var bg, tbBg: TTyStyleSet;

  { Theme-switch glass-backdrop ordering: the form (parent) paints first and rebuilds the photo/
    glass backdrop that windowed children SAMPLE for their own glass corners; force the children
    to repaint too so they re-sample the FRESH backdrop. Without this, on a switch INTO an image
    theme the children repaint against the old/empty backdrop and the image only appears after a
    later full repaint (e.g. minimize/restore). }
  procedure InvalidateKids(AParent: TWinControl);
  var i: Integer;
  begin
    for i := 0 to AParent.ControlCount - 1 do
    begin
      AParent.Controls[i].Invalidate;
      if AParent.Controls[i] is TWinControl then
        InvalidateKids(TWinControl(AParent.Controls[i]));
    end;
  end;

begin
  if AController = nil then Exit;
  FController := AController;   // remembered so Paint can resolve an image backdrop
  FGlassBlurLogical := AController.Model.MaxGlassBlur;  // theme-wide glass radius
  FGlassKey := '';             // force a backdrop rebuild for the new theme
  { Propagate the controller to every chrome sub-component FIRST, so the whole
    window chrome themes from the SAME controller the app loaded its theme into
    (each styleable control resolves its theme via its Controller). }
  { The content host renders THIS form's `form` background (its Paint delegates to
    RenderBackgroundTo, which resolves via FController), so it must follow the same controller:
    a styleable registers with its ActiveController, and an unset one would register against the
    global default instead — then a theme change made straight on THIS controller (without going
    through ApplyChromeTheme) would never notify the surface and the background would go stale. }
  if FSurface <> nil then
    FSurface.Controller := AController;
  if FTitleBar <> nil then
  begin
    FTitleBar.Controller := AController;
    FTitleBar.MinButton.Controller := AController;
    FTitleBar.MaxButton.Controller := AController;
    FTitleBar.CloseButton.Controller := AController;
    { Density axis: with no explicit TitleHeight, re-derive the bar height from the active
      controller -- classic keeps 32 (byte-identical no-op), modern grows to --titlebar-height.
      Runtime only (the designer must not mutate the streamed bar's Height). DPI-scaled the same way
      EffectiveButtonWidthPx scales its metric (MulDiv by Font.PixelsPerInch), so it agrees with the
      HandleChangeBounds cross-monitor rescale instead of clobbering it. }
    if (not FTitleHeightExplicit) and not (csDesigning in ComponentState) then
      FTitleBar.Height := MulDiv(TyTitleBarHeightFor(AController), FTitleBar.Font.PixelsPerInch, 96);
    { Theme the title bar's OWN LCL Color, not just the form's. A windowed control hosted on
      the bar (a theme switcher, a light/dark toggle, a ghost button in its transparent state)
      erases its unpainted background to its PARENT's LCL Color -- if that stays the default
      clBtnFace the child shows a jarring OS-grey strip on top of the themed bar. Match it to the
      resolved title-bar surface (fall back to the form surface) so those areas read as themed. }
    tbBg := AController.Model.ResolveStyle('TyTitleBar', '', []);
    if (tpBackground in tbBg.Present) and (tbBg.Background.Kind = tfkSolid) then
      FTitleBar.Color := TyColorToLCL(tbBg.Background.Color)
    else
    begin
      // TyForm fallback: the form's OWN style — StyleOverride included, so an overridden
      // window background carries into the bar's erase colour too.
      tbBg := ResolveChromeStyle(AController);
      if (tpBackground in tbBg.Present) and (tbBg.Background.Kind = tfkSolid) then
        FTitleBar.Color := TyColorToLCL(tbBg.Background.Color);
    end;
  end;
  bg := ResolveChromeStyle(AController);
  if (tpBackground in bg.Present) and (bg.Background.Kind = tfkSolid) then
    Color := TyColorToLCL(bg.Background.Color);
  // arm/disarm the OS-follow poll to match the controller's Follow policy. Never at design
  // time (this can now run in the IDE designer, via the Controller property / Loaded) — a
  // polling timer has no place on the design surface; ApplyWindowEffects self-guards already.
  if not (csDesigning in ComponentState) then
    UpdateFollowWatch;
  ApplyWindowEffects;  // re-apply corners + shadow (theme may have changed border-radius/window-shadow)
  ApplyResizeStrategy; // refresh the NC subclass's edge-band fill colour to the new theme background
                       // (Win32 borderless-WS_THICKFRAME stripe fix); self-guards csDesigning/no-handle
  // Build the photo/glass snapshot NOW (offscreen, no paint needed) so it is ready BEFORE the
  // children repaint + re-sample it. A WS_CLIPCHILDREN form whose client is fully tiled by
  // windowed children gets an EMPTY update region from Invalidate -> no WM_PAINT -> Paint never
  // runs -> without this the backdrop would only build on a later full repaint (min/restore).
  RebuildBackdrop;
  Invalidate;
  InvalidateKids(Self);   // children re-sample the freshly-rebuilt glass/photo backdrop
end;

procedure TTyForm.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  if FController <> nil then RemoveFreeNotification(FController);
  FController := AValue;
  if AValue <> nil then FreeNotification(AValue);   // opRemove nils the ref if it's freed
  // During streaming the title bar / sub-components may not be assigned yet; Loaded re-applies
  // once the whole .lfm is in. ApplyChromeTheme re-sets FController (harmless) + themes everything.
  if csLoading in ComponentState then Exit;
  if AValue <> nil then
    ApplyChromeTheme(AValue)
  else
  begin
    if not (csDesigning in ComponentState) then UpdateFollowWatch;   // disarm any follow timer
    Invalidate;
  end;
end;

procedure TTyForm.SetStyleOverride(const AValue: string);
begin
  if FStyleOverride = AValue then Exit;
  FStyleOverride := AValue;
  FOvrCacheValid := False;   // force a re-parse on the next resolve
  // Streaming: record only; Loaded runs ApplyChromeTheme/ApplyWindowEffects once the .lfm is in.
  if csLoading in ComponentState then Exit;
  // Design surface: preview via repaint only (children's parent-bg resolves through
  // ThemedBgColor -> ResolveChromeStyle); never poke DWM / the NC strategy in the IDE.
  if csDesigning in ComponentState then
  begin
    Invalidate;
    Exit;
  end;
  // Runtime: re-apply the WHOLE chrome so the override lands immediately — background + LCL
  // Color + backdrop + title-bar colour + OS corner/shadow (the forum use case is flipping
  // window-shadow / border-radius live). Without a controller there is no themed background to
  // rebuild, but the OS effects still resolve via the built-in default controller.
  if FController <> nil then
    ApplyChromeTheme(FController)
  else
  begin
    ApplyWindowEffects;
    ApplyResizeStrategy;   // the shadow opt-out changes the NC model too (full-frame-eat)
    Invalidate;
  end;
end;

function TTyForm.ResolveChromeStyle(ACtrl: TTyStyleController): TTyStyleSet;
begin
  Result := ACtrl.Model.ResolveStyle('TyForm', '', []);
  // A9 layer 2 — the SAME layering as TTyCustomControl.CurrentStyle: overlay the per-instance
  // override LAST, re-parsing only when stale (text changed, or the theme version bumped so a
  // var(--x) re-binds). One parser (TTyStyleModel.ResolveOverride), one merge (TyMergeStyleSet);
  // the form forks nothing.
  if FStyleOverride <> '' then
  begin
    if (not FOvrCacheValid) or (FOvrCacheText <> FStyleOverride)
       or (FOvrCacheVer <> ACtrl.Model.ThemeVersion) then
    begin
      FOvrCache := ACtrl.Model.ResolveOverride(FStyleOverride);
      FOvrCacheText := FStyleOverride;
      FOvrCacheVer := ACtrl.Model.ThemeVersion;
      FOvrCacheValid := True;
    end;
    TyMergeStyleSet(Result, FOvrCache);
  end;
end;

function TTyForm.CurrentStyle: TTyStyleSet;
begin
  if FController <> nil then
    Result := ResolveChromeStyle(FController)
  else
    Result := ResolveChromeStyle(TyDefaultController);
end;

procedure TTyForm.ApplyWindowEffects;
var maximized: Boolean; ctrl: TTyStyleController;
begin
  if csDesigning in ComponentState then Exit;   // never poke DWM/Cocoa on the IDE design surface
  if not HandleAllocated then Exit;
  // Default-on must work even when ApplyChromeTheme was never called: fall back to the
  // always-available built-in controller (mirrors ThemedBgColor). TyResolveWindowEffect
  // supplies the radius/shadow defaults regardless of which controller resolves the style.
  if FController <> nil then ctrl := FController else ctrl := TyDefaultController;
  // The chrome engine fakes maximize via BoundsRect, so read ITS flag (not WindowState).
  maximized := (FEngine <> nil) and FEngine.Maximized;
  TyApplyWindowEffects(Self,
    TyResolveWindowEffect(ResolveChromeStyle(ctrl), maximized));
end;

procedure TTyForm.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: Double);
var
  ppi: Integer;
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if csDesigning in ComponentState then Exit;
  if (FTitleBar = nil) or (FEngine = nil) then Exit;
  if AMode <> lapAutoAdjustForDPI then Exit;
  { LCL has just multiplied every alTop child's bounds by the DPI ratio, this bar included.
    Derive the height back from (pinned logical height or theme metric, current PPI) -- see the
    declaration for why the engine's own correction is not enough on its own. }
  { Font.PixelsPerInch, NOT Monitor's: LCL has just finished its own pass and has already
    updated the font PPI (ScaleFontsPPI runs inside AutoAdjustLayout), whereas Monitor still
    answers for wherever the window physically is -- which during a WM_DPICHANGED is not
    reliably the monitor being scaled TO. Font.PixelsPerInch is what every other control in
    this library treats as the live PPI, for the same reason. }
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then
  begin
    if Monitor <> nil then ppi := Monitor.PixelsPerInch else ppi := Screen.PixelsPerInch;
  end;
  FTitleBar.Height := TyTitleBarDeviceHeight(Self, FTitleBar, ppi);
  FTitleBar.LayoutButtons;
  FEngine.NoteInstalledPPI(ppi);
end;

procedure TTyForm.DoShow;
begin
  inherited DoShow;
  {$IFDEF LCLCOCOA}
  // macOS multi-monitor fix. LCL's (0,0) is the top-left of the virtual-desktop UNION (the top of
  // the TALLEST screen, via NSGlobalScreenBottom), NOT the primary screen's corner. A poDesigned
  // form (the default) is placed at its raw streamed Left/Top with NO visibility clamp — so on a
  // bottom-aligned mixed-height layout (e.g. a portrait screen beside a shorter landscape one) the
  // designed Top can land in the dead zone above the shorter monitor, off-screen. MakeFullyVisible
  // clamps the window back onto its nearest visible monitor's work area; it no-ops if already
  // visible, so single-monitor / normal setups are unaffected. First show only (DoShow can re-fire,
  // and we must not yank a window the user has since dragged). Cocoa-gated -> Windows/Linux untouched.
  if (not (csDesigning in ComponentState)) and HandleAllocated and (not FDidInitialClamp) then
  begin
    FDidInitialClamp := True;
    MakeFullyVisible(nil);
  end;
  {$ENDIF}
  // After the handle exists, apply the per-platform resize strategy so the window honours
  // Resizable from first show. Windows (Phase B): WS_THICKFRAME + the WM_NCCALCSIZE/NCHITTEST
  // subclass. GTK/Qt + Cocoa bodies land in Phase C; the call site is wired now.
  if (not (csDesigning in ComponentState)) and HandleAllocated then
    ApplyResizeStrategy;
  ApplyWindowEffects;
end;

initialization
  { Register for streaming so a TTyTitleBar dropped on a form persists/loads from
    the .lfm at RUNTIME. A form's own published fields resolve their class via RTTI,
    but an associated title bar may be an unnamed/owner-only object — without this,
    loading such an .lfm raises EClassNotFound: Class "TTyTitleBar" not found. }
  RegisterClass(TTyTitleBar);
  { Same streaming lesson for the associated menu bar (TTyForm.MenuBar): register it
    so an .lfm referencing it loads without EClassNotFound. }
  RegisterClass(TTyMenuBar);

end.
