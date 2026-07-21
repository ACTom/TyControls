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
  tyControls.Menu, tyControls.WindowEffects, tyControls.QtWS, tyControls.GtkWS,
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
    FCaption: string;
    FMinButton: TTyCaptionButton;
    FMaxButton: TTyCaptionButton;
    FCloseButton: TTyCaptionButton;
    FButtonWidth: Integer;
    FButtonWidthExplicit: Boolean;   // True once ButtonWidth is set in code/OI (overrides the theme metric)
    FTitleAlignment: TAlignment;
    FEngine: TTyChromeEngine;
    procedure SetCaption(const AValue: string);
    procedure SetButtonWidth(AValue: Integer);
    procedure SetTitleAlignment(AValue: TAlignment);
    function VisibleButtonCount: Integer;
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
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
    property MinButton: TTyCaptionButton read FMinButton;
    property MaxButton: TTyCaptionButton read FMaxButton;
    property CloseButton: TTyCaptionButton read FCloseButton;
    function RightInset: Integer;
  published
    property Caption: string read FCaption write SetCaption;
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
  public
    constructor Create;
    procedure CaptureInstalledPPI;
    procedure TitleBarMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure TitleBarMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TitleBarDblClick;
    procedure FormMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure FormMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HandleChangeBounds;
    procedure ToggleMaximize;
    property Form: TCustomForm read FForm write FForm;
    property TitleBar: TTyTitleBar read FTitleBar write FTitleBar;
    property BorderZone: Integer read FBorderZone write FBorderZone;
    property Maximized: Boolean read FMaximized write FMaximized;
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
    {$IF DEFINED(LCLGtk2) or DEFINED(LCLQt5) or DEFINED(LCLQt6)}
    { GTK/Qt resize-reception gutter: inset the client rect by FBorderZone so alClient
      children stop short of the edge and the form's edge strip receives the mouse.
      Windows (native NC border) and Cocoa (resizable styleMask) need no gutter — the
      IFDEF leaves their build with inherited only. }
    procedure AdjustClientRect(var ARect: TRect); override;
    {$ENDIF}
    procedure DoShow; override;   // first show: apply window corners + shadow once the handle exists
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
    function GetAbout: string;
  published
    { Read-only library version (TyVersion); the design-time editor opens the About dialog. }
    property About: string read GetAbout;
    { The style controller that themes this whole window. Assigning it applies the theme
      (the same effect as calling ApplyChromeTheme) and propagates the controller to the
      title bar + caption buttons; a streamed value is applied in Loaded once the title bar
      exists. Leave it unset to use the built-in default theme (TyDefaultController), or wire
      it to the main window's controller so the whole app shares one theme. }
    property Controller: TTyStyleController read FController write SetController;
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

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
{ Resize-gated edge hit-test: bhNone when not AResizable, else TyHitTestBorder. A pure
  function (no window handle) so the gating is unit-testable; the chrome engine routes its
  edge hits through this so a non-resizable form never starts a resize / shows a resize cursor. }
function TyResizeHitFor(AResizable: Boolean; const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
{ Linux resize-gutter math (pure): insets AClient by AZone on each side when
  (ANeedsGutter and AResizable and not AMaximized) — so alClient children stop short of the
  form edge and the edge strip receives the mouse — else returns AClient unchanged. }
function TyResizeGutterRect(const AClient: TRect; AZone: Integer; AResizable, AMaximized, ANeedsGutter: Boolean): TRect;
{ Which caption buttons a form's chrome shows, from the standard BorderIcons plus the
  Resizable flag: close<=biSystemMenu, minimize<=biMinimize, maximize<=(biMaximize and
  AResizable) — a fixed-size window shows no maximize. Pure (no window handle) so it is
  unit-tested directly. }
function TyResolveCaptionButtons(ABorderIcons: TBorderIcons; AResizable: Boolean): TTyCaptionButtonFlags;

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

{ Pure Windows NC hit-test mapper (no window handle -> headless-testable on any platform).
  APt is in WINDOW-relative coords. Within AZone of an edge -> the matching HT* edge/corner
  code; y < ACaptionH and NOT on a resize edge -> TyHTCAPTION (the title-bar drag band); else
  TyHTCLIENT. When not AResizable, no edge code is ever returned (TyHTCAPTION/TyHTCLIENT only),
  so a fixed window keeps its drag band but cannot be resized. A resize edge WINS over the
  caption band (the top border stays grabbable on a captioned window). The Win32 WM_NCHITTEST
  bridge feeds its window-relative cursor point straight through this. }
function TyNcHitTest(const AWinRect: TRect; const APt: TPoint;
  AZone, ACaptionH: Integer; AResizable: Boolean): Integer;
function TyResizeCursor(AHit: TTyBorderHit): TCursor;
function TyMaximizedBounds(const AWorkArea: TRect): TRect;
function TyRescaleChromeMetric(AValue, AFromPPI, AToPPI: Integer): Integer;

implementation

uses
  tyControls.Win32WS   // native Win32 NC edge-resize glue (no-op off Windows)
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
  QtWS / GtkWS. That helper handles WM_NCCALCSIZE (collapse the non-client area so the client
  fills the whole window while the WS_THICKFRAME sizing border stays hit-testable) +
  WM_NCHITTEST (return TyNcHitTest, the pure mapper that stays HERE next to TyHitTestBorder),
  and chains CallWindowProc(savedProc, ..) for everything else. WS_THICKFRAME — stripped from
  a bsNone form — is re-asserted after the handle exists (DoShow / on Resizable change). The
  install is idempotent + per-handle; the original proc is restored on WM_NCDESTROY. This is
  the standard Chrome/VS Code/WinUI custom-frame route, and mirrors the existing "LCL-Win32
  swallows WM_SETTINGCHANGE in its callback" lesson. ApplyResizeStrategy (below) drives it.
  ============================================================================ }
{$ENDIF}

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

function TyRescaleChromeMetric(AValue, AFromPPI, AToPPI: Integer): Integer;
begin
  if AFromPPI <= 0 then
  begin
    Result := AValue;
    Exit;
  end;
  Result := (AValue * AToPPI + AFromPPI div 2) div AFromPPI;
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
      TyDrawGlyph(P, ActiveController, GlyphRect, KindGlyphToken, KindGlyph, S.TextColor, P.Scale(1));
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
  FTitleAlignment := taLeftJustify;
  // A title bar belongs at the top of the window by default. (The streaming default stays
  // alNone, so existing .lfm files keep writing `Align = alTop` explicitly — no change for
  // them — but a freshly dropped/created bar now snaps to the top strip on its own.)
  Align := alTop;
  // Height follows the density axis: classic 32 (byte-identical); modern --control-height (38) when a
  // modern controller is already active at construction. Streamed forms associate the controller AFTER
  // this ctor, so TTyForm.ApplyChromeTheme re-derives the bar height once its controller is applied.
  SetBounds(0, 0, 200, TyDensityHeight(ActiveController, 32));
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

procedure TTyTitleBar.SetCaption(const AValue: string);
begin
  if FCaption = AValue then
    Exit;
  FCaption := AValue;
  Invalidate;
end;

procedure TTyTitleBar.SetButtonWidth(AValue: Integer);
begin
  FButtonWidthExplicit := True;   // an explicit set pins the width, overriding the theme metric
  if FButtonWidth = AValue then
    Exit;
  FButtonWidth := AValue;
  LayoutButtons;
  Invalidate;
end;

function TTyTitleBar.EffectiveButtonWidthPx: Integer;
begin
  if FButtonWidthExplicit then
    Result := FButtonWidth   // already device-px (form DPI-rescales it); honour the per-instance value
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

function TTyTitleBar.VisibleButtonCount: Integer;
begin
  if (FCloseButton = nil) or (FMaxButton = nil) or (FMinButton = nil) then
    Exit(0);
  Result := Ord(FMinButton.Visible) + Ord(FMaxButton.Visible) + Ord(FCloseButton.Visible);
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
var n: Integer;
begin
  n := VisibleButtonCount;
  if n = 0 then Exit(0);
  // right margin + N buttons + (N-1) gaps + a left margin (title text gap before the group)
  Result := 2 * CapMarginPx + n * EffectiveButtonWidthPx + (n - 1) * CapGapPx;
end;

function TTyTitleBar.LeftInsetPx: Integer;
begin
  Result := MulDiv(ActiveController.Metric('--titlebar-padding', TyTitleBarPad), Font.PixelsPerInch, 96);
end;

procedure TTyTitleBar.LayoutButtons;
var
  W, H, X, Y, m, my, g: Integer;
begin
  if (FCloseButton = nil) or (FMaxButton = nil) or (FMinButton = nil) then
    Exit;
  m := CapMarginPx;
  my := CapMarginYPx;
  g := CapGapPx;
  W := EffectiveButtonWidthPx;
  H := ClientHeight - 2 * my;              // inset top+bottom by the vertical margin (0 = full height)
  if H < 1 then H := ClientHeight;
  Y := my;
  X := ClientWidth - m;                    // start inset from the right edge (horizontal margin)
  if FCloseButton.Visible then begin Dec(X, W); FCloseButton.SetBounds(X, Y, W, H); Dec(X, g); end;
  if FMaxButton.Visible  then begin Dec(X, W); FMaxButton.SetBounds(X, Y, W, H); Dec(X, g); end;
  if FMinButton.Visible  then begin Dec(X, W); FMinButton.SetBounds(X, Y, W, H); end;
end;

procedure TTyTitleBar.Resize;
begin
  inherited Resize;
  LayoutButtons;
end;

procedure TTyTitleBar.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Left, LeftInsetPx);
  Dec(ARect.Right, RightInset);
  if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
end;

procedure TTyTitleBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, TextRect: TRect;
  W, H: Integer;
begin
  W := ARect.Right - ARect.Left;
  H := ARect.Bottom - ARect.Top;
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, W, H);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    TextRect := Rect(R.Left + P.Scale(ActiveController.Metric('--titlebar-padding', TyTitleBarPad)), R.Top,
                     R.Left + W - RightInset, R.Top + H);
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
    TyWin32BeginTopResize(GetParentForm(Self));
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

procedure TTyChromeEngine.TitleBarMouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and (FForm <> nil) and not FMaximized then
  begin
    // Linux: hand the drag to the window manager — a programmatic move() is ignored mid-grab on
    // Qt/X11, and gtk_window_move() gets clamped to the whole-screen bounds on GTK2 (so a window on
    // a non-bottom-aligned second monitor can't be dragged past mid-screen). Qt6 -> startSystemMove,
    // GTK2 -> begin_move_drag; both let the WM cross monitors freely. When a system move starts we
    // release LCL's just-set mouse capture so it doesn't fight the WM's move grab (else after one
    // drag the capture leaks -> the whole window stays in move-mode). No per-move repositioning then
    // (FDragging stays False -> TitleBarMouseMove no-ops). Win32/Qt5 -> False -> fallback below.
    // Qt6 -> startSystemMove, GTK2 -> begin_move_drag: both are NON-BLOCKING (the WM takes the drag
    // asynchronously), so they can start on the press. Win32's caption move (WM_NCLBUTTONDOWN) is a
    // BLOCKING modal loop that would swallow a double-click's second press -> it is deferred to
    // TitleBarMouseMove and armed only past a small drag threshold (so plain click / double-click to
    // maximize still work). Win32 therefore falls through here to the manual-drag setup below.
    if TyQtStartSystemMove(FForm) or TyGtkStartSystemMove(FForm) then
    begin
      SetCaptureControl(nil);
      Exit;
    end;
    FDragging := True;
    // Use the GLOBAL cursor + the form's start origin, not client-relative deltas: on Qt/X11 a
    // programmatic move during a mouse grab is flaky, so we set the ABSOLUTE target each move
    // (mathematically identical to the old delta on Win32/GTK2, so those are unaffected).
    FDragStart := Mouse.CursorPos;
    FDragFormStart := Point(FForm.Left, FForm.Top);
  end;
end;

procedure TTyChromeEngine.TitleBarMouseMove(Shift: TShiftState; X, Y: Integer);
{$IFDEF LCLWin32}
const
  DragThreshold = 4;   // px the pointer must travel before we hand off to the OS caption move
{$ENDIF}
begin
  { Don't drag-move a maximized window (a maximized window has no movable position; a
    post-maximize MouseMove with a still-armed drag would otherwise yank it back toward the
    press origin — the double-click-to-maximize "grew in place" bug). }
  if FDragging and (FForm <> nil) and not FMaximized then
  begin
    {$IFDEF LCLWin32}
    // Win32: once the pointer has actually moved (so a plain click / double-click never triggers it),
    // hand the rest of the drag to the OS caption-move loop -> native Aero Snap + snap preview. That
    // SendMessage blocks until button-up, so clear FDragging first (later moves no-op) and drop LCL's
    // capture the OS loop bypassed. A sub-threshold jiggle keeps the window still (no manual move).
    if (Abs(Mouse.CursorPos.X - FDragStart.X) > DragThreshold)
       or (Abs(Mouse.CursorPos.Y - FDragStart.Y) > DragThreshold) then
    begin
      FDragging := False;
      if TyWin32StartSystemMove(FForm) then
        SetCaptureControl(nil);
    end;
    {$ELSE}
    // Cocoa (+ Qt5/other fallbacks): reposition manually to the absolute target each move. Qt6/GTK2
    // never reach here (they took the async system move on the press -> FDragging stayed False).
    FForm.Left := FDragFormStart.X + (Mouse.CursorPos.X - FDragStart.X);
    FForm.Top  := FDragFormStart.Y + (Mouse.CursorPos.Y - FDragStart.Y);
    {$ENDIF}
  end;
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
    FTitleBar.Height := TyRescaleChromeMetric(FTitleBar.Height, FInstalledPPI, CurPPI);
    FTitleBar.FButtonWidth := TyRescaleChromeMetric(FTitleBar.FButtonWidth, FInstalledPPI, CurPPI);
    FTitleBar.LayoutButtons;
    FInstalledPPI := CurPPI;
    FForm.Invalidate;
    // The rescaled caption height (and possibly the border zone) feed the native NC hit-test
    // on Windows, so refresh the strategy with the new metrics (no-op off Windows / no handle).
    if FForm is TTyForm then TTyForm(FForm).ApplyResizeStrategy;
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
    FForm.BoundsRect := FSavedBounds;
    FMaximized := False;
    if FTitleBar <> nil then FTitleBar.MaxButton.Kind := cbkMax;
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
    FMaximized := True;
    if FTitleBar <> nil then FTitleBar.MaxButton.Kind := cbkRestore;
  end;
  // corners must go square when maximized and round again when restored
  if FForm is TTyForm then TTyForm(FForm).ApplyWindowEffects;
  // refresh the NC strategy: when (un)maximized the WM_NCCALCSIZE inset must turn off/on
  // (a maximized window must NOT keep the resize border, else content overhangs the work area).
  if FForm is TTyForm then TTyForm(FForm).ApplyResizeStrategy;
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

function TTyForm.GetAbout: string;
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
  FEngine.Free;
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

{$IF DEFINED(LCLGtk2) or DEFINED(LCLQt5) or DEFINED(LCLQt6)}
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
begin
  FTitleHeightExplicit := True;   // an explicit set (code/.lfm) pins the height, overriding the density metric
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
var capH, zone: Integer; resiz: Boolean;
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
    TyWin32ApplyNcResize(Self, resiz, zone, capH,
      (FEngine <> nil) and FEngine.Maximized,   // engine (work-area) maximize -> no NC inset
      resiz and (biMaximize in BorderIcons));   // allow native maximize (WS_MAXIMIZEBOX)
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
    and FController.Model.ResolveStyle('TyForm', '', []).BackgroundUnderTitlebar;
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
  bg := FController.Model.ResolveStyle('TyForm', '', []);
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
    bg := FController.Model.ResolveStyle('TyForm', '', []);
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
  bg := ctrl.Model.ResolveStyle('TyForm', '', []);
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
      controller -- classic keeps 32 (byte-identical no-op), modern grows to --control-height (38).
      Runtime only (the designer must not mutate the streamed bar's Height). DPI-scaled the same way
      EffectiveButtonWidthPx scales its metric (MulDiv by Font.PixelsPerInch), so it agrees with the
      HandleChangeBounds cross-monitor rescale instead of clobbering it. }
    if (not FTitleHeightExplicit) and not (csDesigning in ComponentState) then
      FTitleBar.Height := MulDiv(TyDensityHeight(AController, 32), FTitleBar.Font.PixelsPerInch, 96);
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
      tbBg := AController.Model.ResolveStyle('TyForm', '', []);
      if (tpBackground in tbBg.Present) and (tbBg.Background.Kind = tfkSolid) then
        FTitleBar.Color := TyColorToLCL(tbBg.Background.Color);
    end;
  end;
  bg := AController.Model.ResolveStyle('TyForm', '', []);
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
    TyResolveWindowEffect(ctrl.Model.ResolveStyle('TyForm', '', []), maximized));
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
