unit tyControls.Base;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LMessages, LCLType,
  BGRABitmap, BGRABitmapTypes, BGRAGradientScanner,
  tyControls.Types, tyControls.Controller, tyControls.StyleModel,
  tyControls.Css.Values, tyControls.Painter, tyControls.IconFont;
type
  ITyStyleable = interface
    ['{A1B2C3D4-0001-0002-0003-000000000001}']
    function GetStyleTypeKey: string;
  end;

  { Implemented by TTyForm: lets a glass control sample the form's pre-blurred
    background. Declared here (not in Form) so Base never `uses` the Form unit. }
  ITyGlassHost = interface
    ['{A1B2C3D4-0001-0002-0003-000000000002}']
    function GlassBackdrop: TBGRABitmap;       // blurred backdrop (nil if no glass)
    function GlassSharpBackdrop: TBGRABitmap;  // unblurred — fills glass corners
    function GlassClientOrigin: TPoint;        // screen coords of the form client (0,0)
    function GlassUnderTitlebar: Boolean;
  end;

  { Marker implemented by TTyTitleBar so the glass gate can detect a control that
    is (or sits inside) the title bar without Base depending on the Form unit. }
  ITyTitleBarTag = interface
    ['{A1B2C3D4-0001-0002-0003-000000000003}']
  end;

  { Implemented by TTyForm: lets a child resolve the form's THEMED background colour
    (the TyForm token) instead of the un-themed LCL Color. ApplyChromeTheme only sets
    the LCL Color at RUNTIME, so without this a child's corner-gaps / transparent body
    paint the dark default Color in the DESIGNER. Declared here so Base needn't `uses`
    the Form unit (same decoupling as ITyGlassHost). True + a solid colour, or False. }
  ITyThemedBackground = interface
    ['{A1B2C3D4-0001-0002-0003-000000000004}']
    function ThemedBgColor(out AColor: TTyColor): Boolean;
  end;

  { A container's own look does not change between the frames a moving CHILD forces out of it.
    A graphic control's Invalidate damages its PARENT (that is how it gets a background), and
    the parent's Paint then renders its WHOLE client area -- measured at ~23 ns/px once warm,
    so 14.9 ms for a 900x700 page. Three 60 fps instruments on one page therefore ask for
    ~190 full-page re-renders a second, or 282% of a core: unachievable, so frames are dropped
    and the page visibly stutters.

    This caches the rendered result in a DEVICE bitmap. A repaint that FOLLOWS an Invalidate
    re-renders; a repaint that does not -- which is exactly the child-damage case -- blits the
    cache instead, and the blit is clipped by the DC to the damaged rectangle, so it costs the
    child's area rather than the page's.

    The invalidation rule is the whole design: everything that can change a container's look
    (theme, state, caption, font, enabled) already goes through Invalidate, and child damage by
    construction does not. There is no key to enumerate and get wrong. }
  TTyPaintCache = class
  private
    FBmp: TBitmap;
    FValid: Boolean;
  public
    destructor Destroy; override;
    procedure Drop;   // mark stale; the bitmap itself is kept for reuse
    { True when the caller must render into Canvas at AW x AH; False when Blit alone will do. }
    function NeedsRender(AW, AH: Integer): Boolean;
    procedure Blit(ACanvas: TCanvas);
    function Canvas: TCanvas;
  end;

  TTyGraphicControl = class(TGraphicControl, ITyStyleable)
  private
    FStyleClass: string;
    FController: TTyStyleController;
    { A9 per-instance StyleOverride: a bare CSS decl block layered on top of the resolved
      theme style. FOvrCache holds the parsed+evaluated set; recomputed only when the text
      or the model's ThemeVersion changes (so var(--...) re-binds on a theme switch). }
    FStyleOverride: string;
    FOvrCache: TTyStyleSet;
    FOvrCacheText: string;
    FOvrCacheVer: Cardinal;
    FOvrCacheValid: Boolean;
    procedure SetStyleClass(const AValue: string);
    procedure SetStyleOverride(const AValue: string);
    procedure SetController(AValue: TTyStyleController);
  protected
    FHover, FPressed: Boolean;
    FDpiAdjusting: Boolean;
    function _AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function _Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet; virtual;
    function CurrentStyle: TTyStyleSet;
    { ===== PER-MONITOR DPI: the size floor (see the twin on TTyCustomControl, and
      plans/2026-08-08-permonitor-dpi.md) =====================================

      A control that clamps itself with Constraints computes that clamp in DEVICE px from
      the live Font.PixelsPerInch. LCL's per-monitor pass ALSO scales Constraints
      (TControl.DoAutoAdjustLayout -> TSizeConstraints.AutoAdjustLayout, control.inc:3232),
      and LCL's pass RE-DERIVES the floor for us on the way: ScaleFontsPPI runs first
      (control.inc:4224), the font change reaches TControl.FontChanged -> Invalidate
      (control.inc:623), and every one of these controls recomputes its floor from that
      Invalidate. So one monitor crossing applied the factor TWICE -- exactly the shape
      that made the title bar "far too tall" (tyControls.Form.pas, TyTitleBarDeviceHeight),
      here on the controls instead of the chrome. Measured 96->240->96 on a TTyButton:
      29 -> 175 -> 70 px, and it never comes back, because the inflated floor re-clamps
      the height on the way down. A plain LCL TButton in the same form is exact.

      The cure is the invariant the chrome now obeys: PPI-derived state is a pure function
      of (PPI-independent input, current PPI), never X := f(X). UpdateSizeConstraints
      ALREADY is such a function -- it measures the caption at the current PPI and reads
      the theme, it never reads the old Constraints -- so the fix is not to change how the
      floor is computed but to make sure it is applied ONCE per crossing:

        - during the pass the recompute is suppressed (InDpiAdjust), leaving LCL's own
          proportional scaling of Constraints as the single application, which keeps the
          bounds clamp inside DoAutoAdjustLayout meaningful;
        - after the pass the floor is re-derived exactly at the settled PPI, so what
          finally sits in Constraints is F(PPI) and not a product of round-off factors.

      Call UpdateSizeConstraints (guarded); override DoUpdateSizeConstraints (the work). }
    function InDpiAdjust: Boolean;
    { Re-derive the Constraints floor at the CURRENT PPI. Empty here: most controls have no
      floor and pay nothing. Overridden by every control that writes Constraints. }
    procedure DoUpdateSizeConstraints; virtual;
    { The guarded entry point every call site uses. A no-op while LCL's DPI pass is running
      on this control; see InDpiAdjust's comment for why that is the whole fix. }
    procedure UpdateSizeConstraints;
    procedure AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
      const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer); override;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The post-draw hook's entry point on the GRAPHIC side. See the body: it is here, one
      level ABOVE Paint, because every control's Paint ends in a composite that would
      overwrite anything an OnPaint handler drew. }
    procedure WndProc(var TheMessage: TLMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetVersion: string;
  published
    { Read-only library version (TyVersion); the design-time editor for this property opens
      the About dialog. }
    property Version: string read GetVersion;
    property Enabled;
    { Visible was never published anywhere in this library, on either base class, so
      no TTy control could be hidden from the designer or from a .lfm -- only from
      code. TControl.Visible is public, which is exactly why it went unnoticed: it
      works everywhere except the one place you look for it. Default True, so it
      streams only where someone actually hid something. }
    property Visible;
    property Font;
    property Hint;
    property ShowHint;
    { Tier A universal events/props (published; dispatch intact via inherited). }
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
    { AutoSize, republished. 21 controls here already override CalculatePreferredSize --
      the whole point of which is to answer "how big do I want to be" -- and TControl's
      AutoSize is what asks. It was reachable from code and absent from the designer, so
      the measurement work was done and could not be switched on where forms are built.
      Default False, so no existing form changes; a control that does NOT implement a
      preferred size simply keeps its bounds, exactly as in the LCL. }
    property AutoSize;
    { Drag-and-drop, republished. Every one of these is a TControl member with the
      dispatch already implemented by the LCL -- DragMode := dmAutomatic and
      OnDragOver/OnDragDrop work on a self-drawn control exactly as on a native one,
      because dragging is decided above the paint layer. They were simply never
      republished on either base class, so NO control in this library could be made a
      drag source or a drop target from the designer or a .lfm. Like Visible, the gap
      was invisible from the code side: TControl declares them public, so
      `Ctl.DragMode := dmAutomatic` always compiled. It was the Object Inspector and
      the streamed form that had nothing. }
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    { Horizontal / tilt wheel. The vertical three were already here; these are what a
      side-scrolling control (a non-wrapping memo, a wide grid, a long header strip) is
      driven by, and a tilt wheel or a trackpad's horizontal gesture arrives through
      them and nowhere else. }
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    { Per-instance hint customisation -- the seam for a row-dependent tooltip, which is
      the only way to say "this hint depends on what the pointer is over". }
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property Cursor;
    property ParentShowHint;
    property Action;
    { Fired AFTER the control has finished drawing itself, with the control's own Canvas --
      the seam for one badge, one overlay, one debug rectangle, without subclassing. It is
      NOT an owner-draw replacement: the themed control is already on the canvas when the
      handler runs, and the handler draws over it. Ordering is the whole property, and it is
      why the fire site is WMPaint rather than Paint -- see the body. }
    property OnPaint;
    property StyleClass: string read FStyleClass write SetStyleClass;
    { A9: a per-instance CSS declaration block (e.g. 'border-color: var(--accent);')
      applied on top of the theme for THIS control only. May reference var(--...) tokens,
      which resolve against the active theme. A malformed value is skipped, never fatal. }
    property StyleOverride: string read FStyleOverride write SetStyleOverride;
    property Controller: TTyStyleController read FController write SetController;
  end;

  TTyCustomControl = class(TCustomControl, ITyStyleable)
  private
    {$IFDEF LCLGTK3}
    FEraseThemeVer: Cardinal;   // theme version the erase Colour was derived from; 0 = never
    FInEraseRefresh: Boolean;
    {$ENDIF}
    FStyleClass: string;
    FController: TTyStyleController;
    { A9 per-instance StyleOverride (mirrors the TTyGraphicControl twin — the two base
      classes share no ancestor, so the field + setter + cache are duplicated). }
    FStyleOverride: string;
    FOvrCache: TTyStyleSet;
    FOvrCacheText: string;
    FOvrCacheVer: Cardinal;
    FOvrCacheValid: Boolean;
    procedure SetStyleClass(const AValue: string);
    procedure SetStyleOverride(const AValue: string);
  protected
    FHover, FPressed: Boolean;
    FDpiAdjusting: Boolean;
    procedure SetController(AValue: TTyStyleController); virtual;
    function _AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function _Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet; virtual;
    function CurrentStyle: TTyStyleSet;
    { ===== PER-MONITOR DPI: the size floor ===================================
      The twin of the block on TTyGraphicControl -- read it there. Duplicated, not shared,
      because the two bases descend from TGraphicControl and TCustomControl and have no
      common ancestor below TControl; five of the six controls that own a floor
      (TTyButton, TTyCheckBox, TTyRadioButton, TTyToggleSwitch, TTyButtonGroup) are on
      this side and TTyLabel is on the other. }
    function InDpiAdjust: Boolean;
    procedure DoUpdateSizeConstraints; virtual;
    procedure UpdateSizeConstraints;
    procedure AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
      const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer); override;
    {$IFDEF LCLGTK3}
    { LCL-GTK3 is the only widgetset that never clears a damaged region -- see the body. This
      hands its remaining clear a colour to work with, ONCE per theme change. }
    procedure RefreshGtk3EraseColor;
  public
    procedure Invalidate; override;
  protected
    {$ENDIF}
    function ResolveFontSize(const AStyle: TTyStyleSet): Integer;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    { Paint ARect with the form's sharp photo slice ONLY when an image-backed glass
      host is reachable; returns whether it painted. For control regions OUTSIDE the
      styled frame (a group-box caption band, the empty part of a tab header strip)
      so they read as the form's photo on image themes. A no-op (False) off-image and
      headless, so the caller's existing opaque/transparent path is left untouched. }
    function FillSharpBackdrop(APainter: TTyPainter; const ARect: TRect): Boolean;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The post-draw hook's entry point on the WINDOWED side -- TWinControl.PaintHandler's
      single funnel into Paint. See the body for why it cannot live in Paint itself. }
    procedure PaintWindow(DC: HDC); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetVersion: string;
  published
    { Read-only library version (TyVersion); the design-time editor for this property opens
      the About dialog. }
    property Version: string read GetVersion;
    property Enabled;
    { Visible was never published anywhere in this library, on either base class, so
      no TTy control could be hidden from the designer or from a .lfm -- only from
      code. TControl.Visible is public, which is exactly why it went unnoticed: it
      works everywhere except the one place you look for it. Default True, so it
      streams only where someone actually hid something. }
    property Visible;
    property Font;
    property Hint;
    property ShowHint;
    property TabOrder;
    property TabStop;
    { Tier A universal events/props (published; dispatch intact via inherited). }
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
    { AutoSize, republished. 21 controls here already override CalculatePreferredSize --
      the whole point of which is to answer "how big do I want to be" -- and TControl's
      AutoSize is what asks. It was reachable from code and absent from the designer, so
      the measurement work was done and could not be switched on where forms are built.
      Default False, so no existing form changes; a control that does NOT implement a
      preferred size simply keeps its bounds, exactly as in the LCL. }
    property AutoSize;
    { Container geometry, republished for the windowed base only -- both are TWinControl
      members and meaningless on a graphic control that hosts nothing.
      BorderWidth insets the child area; ChildSizing is the LCL's per-container child
      layout engine (Layout, ControlsPerLine, the spacings, EnlargeHorizontal and friends),
      already fully implemented in TWinControl's align pass. Neither was published, so a
      TTy container could not be given either from the designer. }
    property BorderWidth;
    property ChildSizing;
    { Drag-and-drop, republished. Every one of these is a TControl member with the
      dispatch already implemented by the LCL -- DragMode := dmAutomatic and
      OnDragOver/OnDragDrop work on a self-drawn control exactly as on a native one,
      because dragging is decided above the paint layer. They were simply never
      republished on either base class, so NO control in this library could be made a
      drag source or a drop target from the designer or a .lfm. Like Visible, the gap
      was invisible from the code side: TControl declares them public, so
      `Ctl.DragMode := dmAutomatic` always compiled. It was the Object Inspector and
      the streamed form that had nothing. }
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    { Horizontal / tilt wheel. The vertical three were already here; these are what a
      side-scrolling control (a non-wrapping memo, a wide grid, a long header strip) is
      driven by, and a tilt wheel or a trackpad's horizontal gesture arrives through
      them and nowhere else. }
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    { Per-instance hint customisation -- the seam for a row-dependent tooltip, which is
      the only way to say "this hint depends on what the pointer is over". }
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property Cursor;
    property ParentShowHint;
    property Action;
    { Fired AFTER the control has finished drawing itself, with the control's own Canvas.
      Same contract as the graphic base's -- see there. On a CACHED container (TTyPanel and
      friends) the handler runs after the cache blit, so its output is never baked into the
      cache: a child's damage still costs a blit, and the overlay is still redrawn on top of
      it. That is the reason the hook is outside RenderTo and not merely after EndPaint. }
    property OnPaint;
    { Tier B focusable events (TWinControl-declared; custom control only). }
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass: string read FStyleClass write SetStyleClass;
    { A9: per-instance CSS declaration block applied on top of the theme for THIS control
      only. May reference var(--...) tokens (resolved against the active theme); a
      malformed value is skipped, never fatal. }
    property StyleOverride: string read FStyleOverride write SetStyleOverride;
    property Controller: TTyStyleController read FController write SetController;
  end;

{ Position the Windows IME composition window at a CLIENT-space caret point, so a
  CJK composition/candidate popup appears at the caret instead of the screen origin
  (custom-drawn text controls have no system caret for the IME to follow). No-op
  off Windows or when the control has no allocated handle. }
procedure TySetImeCaretPos(AControl: TWinControl; AClientX, AClientY: Integer);

{ Shared font-size resolution for every ty control (windowed AND graphic — the label family
  each carried its own copy). Priority:
    1. the typeKey's own theme font-size (AStyle.FontSize);
    2. an EXPLICITLY-set control Font.Size (AParentFont=False — an OI/code override to honour);
    3. the theme's --font-size-base var, via AController;
    4. an inherited control Font.Size / a readable 9px default.
  Step 3 is the fix for "file-skins render font-enlarged": a skin's own `TyButton {}` (etc.) rule
  suppresses the built-in typeKey layer under the all-or-nothing cascade — INCLUDING its
  `font-size: var(--font-size-base)` — so AStyle.FontSize=0 and the control would otherwise fall
  through to its INHERITED OS/system font (larger at real DPI). The --font-size-base var survives
  the skin load (vars merge separately), and ty controls are theme-locked, so their size follows
  the theme, not the inherited system font. (Headless masks the bug: rootless Font.Size is 0.) }
function TyResolveFontSize(const AStyle: TTyStyleSet; AParentFont: Boolean;
  AControlFontSize: Integer; AController: TTyStyleController): Integer;

{ Resolve the background a windowed child should composite onto (it does not inherit its
  parent's painted bg, so corner-gaps / transparent fills would otherwise show the child's
  own window colour), as a FILL and at the child's own position. Styleable parent -> its
  themed CurrentStyle; a TTyForm parent -> its themed TyForm bg (via ITyThemedBackground,
  correct at design time too); otherwise the parent's raw LCL Color. False only when there
  is no parent.

  ARect is in the CHILD's paint space (what TyFillParentBg is handed), and the fill comes
  back in that same space: hand it straight to APainter.FillBackground(ARect, ...) and the
  result is the parent's backdrop where the child covers it. That is what a gradient parent
  needs -- a windowed child gets its own SLICE of the sweep instead of one flat colour, so
  it stops reading as a rectangular hole punched in the ramp. The returned fill is always
  OPAQUE (see the alpha notes in the body).
  Exposed for tests. }
function TyResolveParentBgFill(AChild: TControl; const ARect: TRect;
  out AFill: TTyFill): Boolean;

{ The one-colour form of the above, for callers that can only take a TTyColor: an erase
  brush, an opacity floor, the corner gaps outside a rounded silhouette. Samples the fill
  at the child's own CENTRE -- see TyFillCentreColor for why that point and no other.
  Exposed for tests. }
function TyResolveParentBg(AChild: TControl; out AColor: TTyColor): Boolean;

{ Fill ARect with AControl's backdrop: the form's photo/glass on an image theme, else
  the OPAQUE resolved parent background (solid); a no-op only when there is no parent
  and no image host. Exposed so controls with regions DrawFrame does not cover (e.g. a
  group box caption band) can fill them opaque instead of leaving transparent pixels. }
procedure TyFillParentBg(AControl: TControl; APainter: TTyPainter; const ARect: TRect;
  const AStyle: TTyStyleSet);
{ Push AStyle's opacity onto APainter so EndPaint dims the whole control when it carries
  one — chiefly ':disabled { opacity }'. DrawFrame already does this; controls that PAINT
  THEIR OWN frame (the instruments: Dial, Rating, Meter, clocks, colour pickers…) must call
  this from their Paint with the state-resolved style, or their disabled opacity is dead.
  Dims TOWARD the opaque parent background (not toward transparency) — see TTyPainter.EndPaint
  and DrawFrame's note. A no-op when AStyle has no opacity. }
procedure TyApplyStyleOpacity(AControl: TControl; APainter: TTyPainter;
  const AStyle: TTyStyleSet);
{ v3/C5. Draw a control glyph: if the active theme sets ATokenName (e.g. '--glyph-check')
  to a valid override '"Family" "\cp"', render that icon-font glyph; otherwise draw the
  built-in vector AVectorKind. A valid override is honoured even if it yields no ink (the
  theme asked for it); only an unset/malformed token falls back to the vector. The second
  overload derives the token from the kind (--glyph-<kind>) — the 1-line form for the many
  P.DrawGlyph(rect, kind, ...) call sites. }
{ APadLogical is forwarded to TTyPainter.DrawGlyph and defaults to ITS default (4 logical px
  PER SIDE). That default suits a glyph drawn inside a control's whole rect (a caption button),
  where the pad IS the air around the mark. It is wrong for a caller that already measured a
  DEDICATED slot from a size token: 4+4 (+1 for the inclusive right edge) eats 9 logical px, so
  a 12px slot leaves a 3px mark — an unreadable smudge, not an arrow. Such callers pass a small
  pad so the slot's token size means the MARK's size. ~12px is otherwise the practical floor. }
procedure TyDrawGlyph(APainter: TTyPainter; AController: TTyStyleController;
  const ARect: TRect; const ATokenName: string; AVectorKind: TTyGlyphKind;
  AColor: TTyColor; AThickness: Integer; APadLogical: Integer = 4); overload;
procedure TyDrawGlyph(APainter: TTyPainter; AController: TTyStyleController;
  const ARect: TRect; AVectorKind: TTyGlyphKind; AColor: TTyColor; AThickness: Integer;
  APadLogical: Integer = 4); overload;
{ v3/C5. Try to draw a theme glyph override into ARect; True = drawn (icon path), False =
  unset/malformed so the CALLER draws its own default (used where the default isn't a plain
  vector kind, e.g. the drop chevron). And the canonical token for a vector kind. }
function TyTryDrawGlyphOverride(APainter: TTyPainter; AController: TTyStyleController;
  const ARect: TRect; const ATokenName: string; AColor: TTyColor): Boolean;
function TyGlyphKindToken(AKind: TTyGlyphKind): string;

{ Contextual styling for a control hosted ON a title bar. A title bar is a container, and
  several skins paint it in a strong colour -- xp and classic use a blue gradient, office the
  accent, showcase an accent gradient. A control dropped on such a bar resolves the ordinary
  ink for its type, which is tuned for the SURFACE, and its caption then sits nearly
  invisible. The bar's own caption stays readable because TyTitleBar carries its own
  contrasting ink; a child has no way to reach it. So the child appends an 'on-titlebar'
  variant and the theme says, once, what ink belongs on its own bar. }
function TyOnTitleBar(AControl: TControl): Boolean;
{ The control's own StyleClass, plus 'on-titlebar' when it is hosted on one. Appended LAST so
  it wins on the properties it sets, and COMPOSED rather than replacing, so a ghost button on
  a title bar stays a ghost button and only its ink moves. A theme that says nothing about
  .on-titlebar is unaffected: the variant matches no rule. }
function TyStyleClassFor(AControl: TControl; const AStyleClass: string): string;

implementation

function TyOnTitleBar(AControl: TControl): Boolean;
var
  p: TControl;
  tag: ITyTitleBarTag;
begin
  Result := False;
  if AControl = nil then Exit;
  p := AControl.Parent;
  while p <> nil do
  begin
    if Supports(p, ITyTitleBarTag, tag) then Exit(True);
    p := p.Parent;
  end;
end;

function TyStyleClassFor(AControl: TControl; const AStyleClass: string): string;
begin
  Result := AStyleClass;
  if not TyOnTitleBar(AControl) then Exit;
  if Result = '' then Result := 'on-titlebar'
  else Result := Result + ' on-titlebar';
end;

{$IFDEF LCLWin32}   // IMM32 IME caret positioning is Win32-widgetset-only (HWND-based); Qt/GTK use their own IME path
const
  CFS_POINT = 2;
type
  TTyImeCompForm = record
    dwStyle: LongWord;
    ptCurrentPos: TPoint;
    rcArea: TRect;
  end;
function ImmGetContext(AWnd: THandle): THandle; stdcall;
  external 'imm32.dll' name 'ImmGetContext';
function ImmReleaseContext(AWnd, AImc: THandle): LongBool; stdcall;
  external 'imm32.dll' name 'ImmReleaseContext';
function ImmSetCompositionWindow(AImc: THandle; ACompForm: Pointer): LongBool; stdcall;
  external 'imm32.dll' name 'ImmSetCompositionWindow';
{$ENDIF}

procedure TySetImeCaretPos(AControl: TWinControl; AClientX, AClientY: Integer);
{$IFDEF LCLWin32}
var
  imc: THandle;
  cf: TTyImeCompForm;
{$ENDIF}
begin
{$IFDEF LCLWin32}
  if (AControl = nil) or not AControl.HandleAllocated then Exit;
  imc := ImmGetContext(AControl.Handle);
  if imc = 0 then Exit;
  try
    FillChar(cf, SizeOf(cf), 0);
    cf.dwStyle := CFS_POINT;
    cf.ptCurrentPos.X := AClientX;
    cf.ptCurrentPos.Y := AClientY;
    ImmSetCompositionWindow(imc, @cf);
  finally
    ImmReleaseContext(AControl.Handle, imc);
  end;
{$ENDIF}
end;

{ TTyGraphicControl }

constructor TTyGraphicControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ActiveController.RegisterStyleable(Self);
end;

function TTyGraphicControl.GetVersion: string;
begin
  Result := TyVersion;
end;

function TTyGraphicControl._AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

function TTyGraphicControl._Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

destructor TTyGraphicControl.Destroy;
begin
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  inherited Destroy;
end;

procedure TTyGraphicControl.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Invalidate;
end;

procedure TTyGraphicControl.SetStyleOverride(const AValue: string);
begin
  if FStyleOverride = AValue then Exit;
  FStyleOverride := AValue;
  FOvrCacheValid := False;   // force a re-parse on the next CurrentStyle
  Invalidate;
end;

procedure TTyGraphicControl.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  { Unregister from current active controller and remove free-notification }
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  { Register with new active controller and wire free-notification }
  if FController <> nil then
    FController.FreeNotification(Self);
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyGraphicControl.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FController) then
    FController := nil;
end;

function TTyGraphicControl.ActiveController: TTyStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyGraphicControl.InDpiAdjust: Boolean;
begin
  Result := FDpiAdjusting;
end;

procedure TTyGraphicControl.DoUpdateSizeConstraints;
begin
  // Most controls own no size floor. Overridden where one exists.
end;

procedure TTyGraphicControl.UpdateSizeConstraints;
begin
  { The one guard, in the one place every call site already goes through. See the
    declaration: while LCL's DPI pass is running it is LCL that scales this control's
    Constraints, and a recompute here would compose with it into a squared factor. }
  if InDpiAdjust then Exit;
  DoUpdateSizeConstraints;
end;

procedure TTyGraphicControl.AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
  const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer);
begin
  { Overridden NOWHERE in this library before a6256/ac2363 -- no control took part in LCL's
    DPI protocol at all, which is why every control that scaled did so by mutating its own
    state and the trip was one-way. }
  FDpiAdjusting := True;
  try
    inherited AutoAdjustLayout(AMode, AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth);
  finally
    FDpiAdjusting := False;
  end;
  { The flag is clear again, so THIS call runs: one exact re-derivation at the settled PPI.
    It is what keeps the floor a function of the current PPI rather than of however many
    proportional steps the control has been dragged through.

    ...but ONLY once this control's font has actually arrived at the new PPI, and for the
    LCL default (ParentFont = True) it has NOT yet. TControl.AutoAdjustLayout brackets the
    pass with `savedParentFont := ParentFont ... finally ParentFont := savedParentFont`
    (control.inc:4221/4228), and restoring ParentFont RE-COPIES the parent's font -- which
    is still at the old PPI, because TWinControl.AutoAdjustLayout walks the children BEFORE
    itself (wincontrol.inc:3932). So on exit from `inherited` a ParentFont child's
    Font.PixelsPerInch is back where it started, and re-deriving here would measure the
    caption at the OLD PPI and then clamp the bounds to that -- undoing the scaling LCL had
    just done correctly. Measured without this test: TTyButton 100x29 -> 250x72 -> 175x70,
    i.e. still "broken forever", just by a different route.

    Skipping is safe and is not a hole: the parent's own pass pushes the new font down
    through CM_PARENTFONTCHANGED, that reaches TControl.FontChanged -> Invalidate
    (control.inc:623), the guard above is down by then, and the control re-derives its floor
    at the correct PPI in the ordinary way. The explicit call here exists for the OTHER
    case -- ParentFont = False -- where nothing arrives later and this is the only chance. }
  if (AMode in [lapAutoAdjustWithoutHorizontalScrolling, lapAutoAdjustForDPI])
     and (AToPPI > 0) and (Font.PixelsPerInch = AToPPI) then
    UpdateSizeConstraints;
end;

function TTyGraphicControl.CurrentStates: TTyStateSet;
begin
  Result := [];
  if not Enabled then
  begin
    Include(Result, tysDisabled);
    Exit;
  end;
  if FHover then Include(Result, tysHover);
  if FPressed then Include(Result, tysActive);
  if Result = [] then
    Include(Result, tysNormal);
end;

function TTyGraphicControl.CurrentStyle: TTyStyleSet;
var
  model: TTyStyleModel;
begin
  model := ActiveController.Model;
  Result := model.ResolveStyle(GetStyleTypeKey,
    TyStyleClassFor(Self, FStyleClass), CurrentStates);
  // A9 layer 2: overlay the per-instance override last. Recompute only when stale —
  // the override text changed or the theme version bumped (so var(--...) re-binds).
  if FStyleOverride <> '' then
  begin
    if (not FOvrCacheValid) or (FOvrCacheText <> FStyleOverride)
       or (FOvrCacheVer <> model.ThemeVersion) then
    begin
      FOvrCache := model.ResolveOverride(FStyleOverride);
      FOvrCacheText := FStyleOverride;
      FOvrCacheVer := model.ThemeVersion;
      FOvrCacheValid := True;
    end;
    TyMergeStyleSet(Result, FOvrCache);   // override wins per Present flag (§3.3)
  end;
end;

{ Resolve the background a child should composite onto. A windowed child does NOT
  inherit its parent's painted/erased background, so a transparent background or the
  triangles OUTSIDE rounded corners would show the child's own window colour (a
  stray patch / haloed AA edge) rather than what's behind it. When the parent is a
  styleable tyControl, use its resolved style background; otherwise (a plain form or
  panel) use the parent's window colour. Returns False only with no parent (e.g. a
  control rendered offscreen in isolation), leaving that path untouched. }
destructor TTyPaintCache.Destroy;
begin
  FBmp.Free;
  inherited Destroy;
end;

procedure TTyPaintCache.Drop;
begin
  FValid := False;
end;

function TTyPaintCache.NeedsRender(AW, AH: Integer): Boolean;
begin
  Result := False;
  if (AW <= 0) or (AH <= 0) then Exit;
  if FBmp = nil then
  begin
    FBmp := TBitmap.Create;
    FBmp.PixelFormat := pf32bit;
  end;
  if (FBmp.Width <> AW) or (FBmp.Height <> AH) then
  begin
    FBmp.SetSize(AW, AH);
    FValid := False;   // a resized surface holds nothing usable
  end;
  Result := not FValid;
  FValid := True;
end;

procedure TTyPaintCache.Blit(ACanvas: TCanvas);
begin
  { The destination DC is clipped to the invalid region, so this transfers the damaged
    rectangle only -- which is the entire point. }
  if FBmp <> nil then ACanvas.Draw(0, 0, FBmp);
end;

function TTyPaintCache.Canvas: TCanvas;
begin
  if FBmp <> nil then Result := FBmp.Canvas else Result := nil;
end;

{ The painter's linear-gradient geometry, mirrored. TTyPainter.GradientEndpoints
  (tyControls.Painter.pas:571) is private, so a child that has to work out WHERE IN its
  parent's ramp it sits must recompute the same two endpoints; the two are a pair and have
  to move together.

  The convention they encode is worth spelling out, because the name does not and guessing
  it costs a whole fixture: the angle is a plain MATH angle in screen space — dx = cos, dy
  = sin, y growing DOWN — so 0deg runs left->right and 90deg runs top->bottom. 180deg is
  therefore HORIZONTAL again (right->left), NOT the CSS reading where 180deg means "to
  bottom". The endpoints are the rect's centre pushed out along that direction by the
  half-diagonal's projection, so the ramp always spans the rect exactly. }
procedure TyGradientEndpoints(const ARect: TRect; AAngleDeg: Single; out P1, P2: TPointF);
var
  rad, dx, dy, cx, cy, hw, hh, t: Single;
begin
  rad := AAngleDeg * Pi / 180;
  dx := Cos(rad);
  dy := Sin(rad);
  cx := (ARect.Left + ARect.Right) / 2;
  cy := (ARect.Top + ARect.Bottom) / 2;
  hw := (ARect.Right - ARect.Left) / 2;
  hh := (ARect.Bottom - ARect.Top) / 2;
  t := Abs(dx) * hw + Abs(dy) * hh;
  P1.x := cx - dx * t;
  P1.y := cy - dy * t;
  P2.x := cx + dx * t;
  P2.y := cy + dy * t;
end;

function TyColorFromBGRA(const APx: TBGRAPixel): TTyColor;
begin
  Result := TyRGBA(APx.red, APx.green, APx.blue, APx.alpha);
end;

{ Build the very scanner TTyPainter.FillBackground would build for AFill over ARect
  (tyControls.Painter.pas:642-679), so a sample taken from it IS the pixel the parent
  painted rather than an approximation of it.

  The two colour paths are NOT interchangeable, which is why this mirrors the painter's
  choice instead of picking one: >2 stops go through a multi-gradient created with gamma
  correction OFF, while the 2-stop fast path uses the simple scanner whose
  gammaColorCorrection argument DEFAULTS to ON. Read a black->white ramp with the wrong one
  and the middle is out by ~60 levels — which is exactly the seam this whole function
  exists to remove. AOwned is the multi-gradient (nil on the fast path); the scanner does
  not own it, so the caller frees both. }
function TyGradientScannerFor(const AFill: TTyFill; const ARect: TRect;
  out AOwned: TBGRACustomGradient): TBGRAGradientScanner;
var
  p1, p2: TPointF;
  cols: array of TBGRAPixel;
  poss: array of Single;
  i: Integer;
begin
  AOwned := nil;
  TyGradientEndpoints(ARect, AFill.GradAngleDeg, p1, p2);
  if Length(AFill.GradStops) > 2 then
  begin
    SetLength(cols, Length(AFill.GradStops));
    SetLength(poss, Length(AFill.GradStops));
    for i := 0 to High(AFill.GradStops) do
    begin
      cols[i] := TyColorToBGRA(AFill.GradStops[i].Color);
      poss[i] := AFill.GradStops[i].Pos;
    end;
    AOwned := TBGRAMultiGradient.Create(cols, poss, False, False);
    Result := TBGRAGradientScanner.Create(AOwned, gtLinear, p1, p2);
  end
  else
    Result := TBGRAGradientScanner.Create(TyColorToBGRA(AFill.GradFrom),
      TyColorToBGRA(AFill.GradTo), gtLinear, p1, p2);
end;

{ The ONE colour that stands for AFill over ARect: its value at the rect's CENTRE.

  The centre is not an arbitrary pick, it is the minimax point. Every caller reduced to a
  single colour is one whose error shows up as a SEAM around the control's outline — the
  window erase brush, the gaps outside a rounded shape, the colour opacity dims toward —
  and for a ramp the largest distance from the sample to any point of the rect is smallest
  at the centre: half the sweep instead of all of it. Sampling an edge would put the whole
  error on the opposite edge, which is the defect this file just removed. }
function TyFillCentreColor(const AFill: TTyFill; const ARect: TRect): TTyColor;
var
  scan: TBGRAGradientScanner;
  owned: TBGRACustomGradient;
begin
  if AFill.Kind <> tfkLinearGradient then Exit(AFill.Color);
  scan := TyGradientScannerFor(AFill, ARect, owned);
  try
    Result := TyColorFromBGRA(scan.ScanAt((ARect.Left + ARect.Right) / 2,
                                          (ARect.Top + ARect.Bottom) / 2));
  finally
    scan.Free;
    owned.Free;
  end;
end;

{ Re-express AFill — a gradient laid out over APR — as the gradient a painter must lay over
  a rect of ACR's SIZE for the two to be the same ramp where they overlap. This is the fix:
  the child does not get a representative colour, it gets its own slice of the parent's sweep.

  The reparametrisation is exact, not a fit. The painter's endpoints depend only on a rect's
  centre and half-extents, so both rects project onto the SAME axis; within one stop segment
  the colour is an affine function of that projection; and a sub-interval of an affine ramp
  is an affine ramp. So the endpoint colours are SAMPLED from the parent's own scanner —
  which settles the gamma question for free, whichever space it interpolates in — and every
  parent stop falling inside the child's span is carried across at its remapped position.

  The stop COUNT is preserved on purpose either side of the painter's >2 threshold: a parent
  drawn through the multi-stop path interpolated without gamma correction, and a two-stop
  child would silently switch to the gamma-corrected fast path and drift off the ramp it is
  supposed to continue. When no parent stop lands inside the span, a midpoint sampled from
  the parent keeps the count above two — collinear, so it changes nothing but the path. }
function TyRebaseGradient(const AFill: TTyFill; const APR, ACR: TRect): TTyFill;
var
  p1, p2, q1, q2: TPointF;
  scan: TBGRAGradientScanner;
  owned: TBGRACustomGradient;
  u0, u1, den: Single;
  i, n: Integer;

  procedure AddStop(AColor: TTyColor; APos: Single);
  begin
    SetLength(Result.GradStops, n + 1);
    Result.GradStops[n].Color := AColor;
    Result.GradStops[n].Pos := APos;
    Inc(n);
  end;

begin
  Result := AFill;
  Result.GradStops := nil;   // rebuilt below; never share the parent's array
  n := 0;
  TyGradientEndpoints(APR, AFill.GradAngleDeg, p1, p2);
  TyGradientEndpoints(ACR, AFill.GradAngleDeg, q1, q2);
  den := Sqr(p2.x - p1.x) + Sqr(p2.y - p1.y);
  scan := TyGradientScannerFor(AFill, APR, owned);
  try
    { A parent with no extent along the axis has no ramp to slice. }
    if den <= 0 then
    begin
      Result.Kind := tfkSolid;
      Result.Color := TyColorFromBGRA(scan.ScanAt(p1.x, p1.y));
      Exit;
    end;
    { The BGRA linear scanner's parameter is the projection onto P1->P2 normalised by its
      squared length (TBGRAGradientScanner.ScanAtLinear + InitTransform). }
    u0 := ((q1.x - p1.x) * (p2.x - p1.x) + (q1.y - p1.y) * (p2.y - p1.y)) / den;
    u1 := ((q2.x - p1.x) * (p2.x - p1.x) + (q2.y - p1.y) * (p2.y - p1.y)) / den;
    Result.GradFrom := TyColorFromBGRA(scan.ScanAt(q1.x, q1.y));
    Result.GradTo := TyColorFromBGRA(scan.ScanAt(q2.x, q2.y));
    { A child that is a sliver ACROSS the axis (or has no size at all) covers a single
      point of the ramp: one colour really is the whole truth there. }
    if u1 - u0 <= 1E-6 then
    begin
      Result.Kind := tfkSolid;
      Result.Color := Result.GradFrom;
      Exit;
    end;
    AddStop(Result.GradFrom, 0);
    if Length(AFill.GradStops) > 2 then
    begin
      for i := 0 to High(AFill.GradStops) do
        if (AFill.GradStops[i].Pos > u0) and (AFill.GradStops[i].Pos < u1) then
          AddStop(AFill.GradStops[i].Color, (AFill.GradStops[i].Pos - u0) / (u1 - u0));
      if n = 1 then
        AddStop(TyColorFromBGRA(scan.ScanAt((q1.x + q2.x) / 2, (q1.y + q2.y) / 2)), 0.5);
    end;
    AddStop(Result.GradTo, 1);
  finally
    scan.Free;
    owned.Free;
  end;
end;

{ Alpha-composite ATop over the OPAQUE AUnder. }
function TyCompositeOver(ATop, AUnder: TTyColor): TTyColor;
var a: Integer;
begin
  a := TyAlphaOf(ATop);
  if a >= 255 then Exit(ATop);
  Result := TyRGB(
    (TyRedOf(ATop)   * a + TyRedOf(AUnder)   * (255 - a)) div 255,
    (TyGreenOf(ATop) * a + TyGreenOf(AUnder) * (255 - a)) div 255,
    (TyBlueOf(ATop)  * a + TyBlueOf(AUnder)  * (255 - a)) div 255);
end;

{ Composite AFill and the opaque AOther against each other, colour by colour: the solid
  face, both gradient ends and every stop. AFillOnTop says which side AFill is — the TOP
  layer when it is a partly transparent background being flattened onto a resolved backdrop,
  the BOTTOM layer when a translucent container is being laid over the backdrop AFill
  describes. Over a gradient the result is still a gradient: a constant layer over an affine
  ramp stays affine, so a translucent panel on a gradient form keeps the sweep. }
procedure TyCompositeFill(var AFill: TTyFill; AOther: TTyColor; AFillOnTop: Boolean);

  function Mix(c: TTyColor): TTyColor;
  begin
    if AFillOnTop then Result := TyCompositeOver(c, AOther)
    else Result := TyCompositeOver(AOther, c);
  end;

var i: Integer;
begin
  if AFill.Kind = tfkLinearGradient then
  begin
    AFill.GradFrom := Mix(AFill.GradFrom);
    AFill.GradTo := Mix(AFill.GradTo);
    for i := 0 to High(AFill.GradStops) do
      AFill.GradStops[i].Color := Mix(AFill.GradStops[i].Color);
  end
  else
    AFill.Color := Mix(AFill.Color);
end;

function TyFillHasAlpha(const AFill: TTyFill): Boolean;
var i: Integer;
begin
  if AFill.Kind <> tfkLinearGradient then
    Exit(TyAlphaOf(AFill.Color) < 255);
  Result := (TyAlphaOf(AFill.GradFrom) < 255) or (TyAlphaOf(AFill.GradTo) < 255);
  for i := 0 to High(AFill.GradStops) do
    if TyAlphaOf(AFill.GradStops[i].Color) < 255 then Result := True;
end;

{ The gradient counterpart of ITyThemedBackground.ThemedBgColor: reconstruct a themed
  form's LINEAR-GRADIENT background as the slice a child at ACR (in the form's client
  space, laid out over APR) must paint. ThemedBgColor answers solid backgrounds only —
  its out-param cannot carry a ramp, and widening the interface means changing its
  implementor (tyControls.Form) — so before this the gradient case fell through to the
  raw LCL Color fallback. ApplyChromeTheme never themes Color for a non-solid background
  either, so that read clDefault, and ColorToRGB(clDefault) masks $20000000 to $000000:
  on aero (the one built-in whose TyForm bg is a gradient, and whose controls carry
  shadows) every windowed control painted OPAQUE BLACK corner notches, on every repaint.
  Measured 2026-08-06/07; guarded by test.formgradientbg.

  The style is resolved through the CHILD's ActiveController — ApplyChromeTheme hands
  the same controller to the surface and (in every stock layout) to the controls, and
  headless/designer fall back to TyDefaultController exactly as ThemedBgColor does. A
  child given a DIFFERENT controller than its form would reconstruct its own theme's
  form ramp; accepted, matching how such a child already resolves everything else.

  APR is the FORM's client rect. A surface/title-bar layout paints the same sweep over
  a rect shortened by the bar, so a vertical ramp's reconstruction can sit tbH early —
  bounded by tbH/formH of the sweep (~1 RGB step on aero's 19-step wash). Knowing the
  true layout rect would take the surface telling us it paints a delegated background;
  not worth an interface for a sub-tolerance error. }
function TyThemedFormGradient(AChild: TControl; const APR, ACR: TRect;
  out AFill: TTyFill): Boolean;
var
  ctrl: TTyStyleController;
  st: TTyStyleSet;
begin
  Result := False;
  if AChild is TTyCustomControl then
    ctrl := TTyCustomControl(AChild).ActiveController
  else if AChild is TTyGraphicControl then
    ctrl := TTyGraphicControl(AChild).ActiveController
  else
    ctrl := TyDefaultController;
  if ctrl = nil then Exit;
  st := ctrl.Model.ResolveStyle('TyForm', '', []);
  if not ((tpBackground in st.Present) and (st.Background.Kind = tfkLinearGradient)) then
    Exit;
  AFill := TyRebaseGradient(st.Background, APR, ACR);
  { The same opaque promise as every other branch: alpha stops are flattened. A top-level
    form has nothing themed behind it, so the backdrop is white, matching the gradient
    branch's own fallback for an unresolvable underlay. }
  if TyFillHasAlpha(AFill) then
    TyCompositeFill(AFill, TyRGB(255, 255, 255), True);
  Result := True;
end;

function TyResolveParentBgFill(AChild: TControl; const ARect: TRect;
  out AFill: TTyFill): Boolean;
var
  st: TTyStyleSet;
  r, g, b: Byte;
  back: TTyFill;
  under: TTyColor;
  tb: ITyThemedBackground;
  par: TControl;
  pr, cr: TRect;
  pw, ph: Integer;
begin
  Result := False;
  AFill := Default(TTyFill);
  AFill.Kind := tfkSolid;
  if (AChild = nil) or (AChild.Parent = nil) then Exit;
  par := AChild.Parent;
  { ARect arrives in the CHILD's paint space; everything below reasons in the PARENT's,
    because that is the space the parent's background was laid out in. A child's Left/Top
    are already relative to the parent's CLIENT origin, and the client origin is also where
    the parent starts painting (RenderTo fills Rect(0,0,ClientWidth,ClientHeight)), so the
    shift between the two spaces is just the child's bounds. Carrying ARect through rather
    than the child's whole rect is what keeps the SUB-rect callers honest — a group box
    caption band, a tab strip header — since those ask for a slice of themselves. }
  cr := Rect(ARect.Left + AChild.Left, ARect.Top + AChild.Top,
             ARect.Right + AChild.Left, ARect.Bottom + AChild.Top);
  { Headless, and before a handle exists, ClientWidth is the bounds width; the fallback is
    for the reverse case of a control asked about before it has been sized at all. }
  pw := par.ClientWidth;  if pw <= 0 then pw := par.Width;
  ph := par.ClientHeight; if ph <= 0 then ph := par.Height;
  pr := Rect(0, 0, pw, ph);
  if par is TTyCustomControl then
  begin
    st := TTyCustomControl(par).CurrentStyle;
    { A container with NO background, or a fully TRANSPARENT one (e.g. TyGroupBox
      bg = alpha(#FFFFFF,0)), shows whatever is behind IT — so walk up to the next
      opaque backdrop. Otherwise a child's corner-gap / parent fill would resolve to
      a transparent color and the Win10 DWM glass would show through (an Edit inside
      a group box had system-colored corners). The rect goes up translated, so the
      grandparent's own gradient is still sampled where the CHILD sits. }
    if not (tpBackground in st.Present) then
      Exit(TyResolveParentBgFill(par, cr, AFill));
    case st.Background.Kind of
      tfkSolid:
        if TyAlphaOf(st.Background.Color) = 0 then
          Exit(TyResolveParentBgFill(par, cr, AFill))
        else if TyAlphaOf(st.Background.Color) < 255 then
        begin
          { A PARTLY transparent container shows the backdrop through itself, so the opaque
            background this function promises is that container COMPOSITED OVER what is behind
            it. Returning its raw value instead breaks the promise in a way that only shows
            up on a widgetset which never clears a damaged region: the child fills with a
            non-opaque "background", its finished bitmap is therefore non-opaque, and every
            repaint composites onto the previous one instead of replacing it. That is the
            GTK3 smearing on exactly the controls that DO call TyFillParentBg. Throwing the
            alpha away instead would keep it opaque but at the wrong hue. }
          if not TyResolveParentBgFill(par, cr, AFill) then
          begin
            AFill := Default(TTyFill);
            AFill.Kind := tfkSolid;
            AFill.Color := TyRGB(255, 255, 255);
          end;
          TyCompositeFill(AFill, st.Background.Color, False);
          Result := True;
        end
        else
        begin
          AFill.Kind := tfkSolid;
          AFill.Color := st.Background.Color;
          Result := True;
        end;
      tfkLinearGradient:
        begin
          AFill := TyRebaseGradient(st.Background, pr, cr);
          { A gradient may carry alpha stops, and the opaque promise above is the same one
            here for the same reason. Flatten onto the backdrop behind the parent, sampled
            where the child sits so a translucent ramp over a ramp still tracks position. }
          if TyFillHasAlpha(AFill) then
          begin
            if TyResolveParentBgFill(par, cr, back) then
              under := TyFillCentreColor(back, cr)
            else
              under := TyRGB(255, 255, 255);
            TyCompositeFill(AFill, under, True);
          end;
          Result := True;
        end;
    end;
  end
  // A TTyForm parent: use its THEMED TyForm bg (correct at design time too — the LCL
  // Color is only themed by ApplyChromeTheme at runtime). Same value as Color at runtime.
  // Solid via the interface; a GRADIENT via TyThemedFormGradient (the interface's out-param
  // is one colour — see that function for why, and for the aero black-corner history).
  else if Supports(par, ITyThemedBackground, tb) then
  begin
    if tb.ThemedBgColor(AFill.Color) then
      Result := True
    else if TyThemedFormGradient(AChild, pr, cr, AFill) then
      Result := True
    else
    begin
      { An image bg with no live backdrop (headless), or no bg token at all: the LCL
        colour — RESOLVED, never raw. ColorToRGB(clDefault) masks to $000000, and that
        black is exactly what the aero corner notches were made of. }
      RedGreenBlue(ColorToRGB(par.GetColorResolvingParent), r, g, b);
      AFill.Color := TyRGB(r, g, b);
      Result := True;
    end;
  end
  else
  begin
    RedGreenBlue(ColorToRGB(par.GetColorResolvingParent), r, g, b);
    AFill.Color := TyRGB(r, g, b);
    Result := True;
  end;
end;

function TyResolveParentBg(AChild: TControl; out AColor: TTyColor): Boolean;
var
  f: TTyFill;
  r: TRect;
  w, h: Integer;
begin
  Result := False;
  if AChild = nil then Exit;
  { The child's own rect is the space the resolved fill comes back in, so it is also the
    rect the single colour has to be sampled over. }
  w := AChild.ClientWidth;  if w <= 0 then w := AChild.Width;
  h := AChild.ClientHeight; if h <= 0 then h := AChild.Height;
  r := Rect(0, 0, w, h);
  Result := TyResolveParentBgFill(AChild, r, f);
  if Result then AColor := TyFillCentreColor(f, r);
end;

{ True when AControl sits on an image-backed TTyForm (a glass host with a live
  backdrop) AND passes the title-bar gate; then AOffset is the control's top-left in
  the form's backdrop space. False -> caller uses the plain solid parent fill:
  off-form, headless/no-backdrop, an unrealized window, or under-titlebar gated. }
function TyResolveGlassHost(AControl: TControl; out AHost: ITyGlassHost;
  out AOffset: TPoint): Boolean;
var
  p: TControl;
  tag: ITyTitleBarTag;
  co, fo: TPoint;
  inTitle: Boolean;
begin
  Result := False;
  AHost := nil;
  if (AControl = nil) or (AControl.Parent = nil) then Exit;
  // A windowed control needs its handle for ClientOrigin; graphic controls resolve
  // through their parent chain, so only gate the TWinControl case.
  if (AControl is TWinControl) and not TWinControl(AControl).HandleAllocated then Exit;
  p := AControl;
  while (p <> nil) and not Supports(p, ITyGlassHost, AHost) do p := p.Parent;
  if (AHost = nil) or (AHost.GlassSharpBackdrop = nil) then
  begin
    AHost := nil;  // no image backdrop (plain form / headless) — solid fill stands
    Exit;
  end;
  // Title-bar gate: controls in the title bar only see the photo when the theme
  // extended the background under the bar.
  inTitle := False;
  p := AControl;
  while p <> nil do
  begin
    if Supports(p, ITyTitleBarTag, tag) then begin inTitle := True; Break; end;
    p := p.Parent;
  end;
  if inTitle and not AHost.GlassUnderTitlebar then begin AHost := nil; Exit; end;
  co := AControl.ClientOrigin;    // control client (0,0) in screen px
  fo := AHost.GlassClientOrigin;  // form client (0,0) in screen px
  AOffset := Point(co.X - fo.X, co.Y - fo.Y);
  Result := True;
end;

procedure TyFillParentBg(AControl: TControl; APainter: TTyPainter; const ARect: TRect;
  const AStyle: TTyStyleSet);
var
  host: ITyGlassHost;
  off: TPoint;
  c: TTyColor;
  f: TTyFill;
begin
  if TyResolveGlassHost(AControl, host, off) then
  begin
    // Image-backed form: the SHARP photo slice is the opaque base for EVERY control,
    // so the corners outside its rounded shape read as the form's photo, not a flat
    // fill. Glass controls then get the round-clipped blurred pane + tint on top.
    // ARect may be a sub-rect (group-box frame below its caption, tab content frame
    // below the header), so fold its origin into the backdrop sample — the painter
    // puts ASrcOffset at FBmp(ARect.Left,ARect.Top), and FBmp(cx,cy) must show
    // backdrop(off.X+cx, off.Y+cy) for the photo to stay seamless across the frame.
    APainter.FillImageSlice(ARect, host.GlassSharpBackdrop,
      Point(off.X + ARect.Left, off.Y + ARect.Top));
    if tpGlass in AStyle.Present then
      APainter.FillGlass(ARect, host.GlassBackdrop,
        Point(off.X + ARect.Left, off.Y + ARect.Top),
        AStyle.Background.GlassTint, TyEffectiveCorners(AStyle));
  end
  { Not the single-colour resolver: the fill comes back already re-expressed in THIS rect's
    space, so a gradient parent hands down the slice of its sweep that ARect covers instead
    of one representative colour smeared flat across it. }
  else if TyResolveParentBgFill(AControl, ARect, f) then
    APainter.FillBackground(ARect, f, 0);
end;

procedure TyApplyStyleOpacity(AControl: TControl; APainter: TTyPainter;
  const AStyle: TTyStyleSet);
var pc: TTyColor;
begin
  if tpOpacity in AStyle.Present then
  begin
    APainter.Opacity := AStyle.Opacity;
    // Dim TOWARD the opaque parent/surface bg, not toward transparency (see EndPaint):
    // a disabled control must not expose the Win10 DWM glass. 0 base = plain alpha-reduce.
    if TyResolveParentBg(AControl, pc) then APainter.OpacityBase := pc;
  end;
end;

{ v3/B2. Draw an outset/inset two-tone 3D bevel for the border, deriving the light/dark edge
  colours from border-color (lighten TL / darken BR for a raised outset; swapped for a sunken
  inset). Bevels are square by nature — the fill's corner radius is not applied to the edges. }
procedure TyDrawBevelBorder(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
var light, dark: TTyColor;
begin
  light := TyLighten(AStyle.BorderColor, 40);   // Pct is 0..100
  dark := TyDarken(AStyle.BorderColor, 40);
  if AStyle.BorderStyle = tbsInset then
    APainter.DrawEdge(ARect, AStyle.BorderWidth, dark, light)   // sunken: TL dark, BR light
  else
    APainter.DrawEdge(ARect, AStyle.BorderWidth, light, dark);  // raised (outset): TL light, BR dark
end;

function TyTryDrawGlyphOverride(APainter: TTyPainter; AController: TTyStyleController;
  const ARect: TRect; const ATokenName: string; AColor: TTyColor): Boolean;
{ v3/C5 core. If the theme sets ATokenName to a valid glyph override, render that icon-font
  glyph into ARect and return True (honoured even if it renders blank — the theme asked for
  it); else return False so the caller draws its OWN default (a vector glyph, DrawDropChevron,
  …). This is the seam controls that don't use a plain vector kind (e.g. the drop chevron) hook. }
var
  token: string;
  sz: Integer;
  bmp: TBGRABitmap;
begin
  Result := False;
  if AController = nil then Exit;
  token := AController.Model.RawVar(ATokenName);
  if token = '' then Exit;
  sz := ARect.Right - ARect.Left;
  if ARect.Bottom - ARect.Top < sz then sz := ARect.Bottom - ARect.Top;
  bmp := TyRenderGlyphToken(token, sz, AColor);   // nil when the token is malformed
  if bmp = nil then Exit;
  try
    APainter.DrawGlyphBitmap(ARect, bmp);
  finally
    bmp.Free;
  end;
  Result := True;
end;

function TyGlyphKindToken(AKind: TTyGlyphKind): string;
{ v3/C5. Canonical '--glyph-<kind>' override token for a vector glyph kind ('' = no token). }
begin
  case AKind of
    tgClose:              Result := '--glyph-close';
    tgMinimize:           Result := '--glyph-minimize';
    tgMaximize:           Result := '--glyph-maximize';
    tgRestore:            Result := '--glyph-restore';
    tgCheck:              Result := '--glyph-check';
    tgCheckIndeterminate: Result := '--glyph-check-indeterminate';
    tgRadioDot:           Result := '--glyph-radio';
    tgChevronDown:        Result := '--glyph-chevron-down';
    tgChevronRight:       Result := '--glyph-chevron-right';
    tgChevronLeft:        Result := '--glyph-chevron-left';
    tgArrowUp:            Result := '--glyph-arrow-up';
    tgArrowDown:          Result := '--glyph-arrow-down';
    tgArrowLeft:          Result := '--glyph-arrow-left';
    tgArrowRight:         Result := '--glyph-arrow-right';
    tgInfo:               Result := '--glyph-info';
    tgSuccess:            Result := '--glyph-success';
    tgWarning:            Result := '--glyph-warning';
    tgError:              Result := '--glyph-error';
  else
    Result := '';
  end;
end;

procedure TyDrawGlyph(APainter: TTyPainter; AController: TTyStyleController;
  const ARect: TRect; const ATokenName: string; AVectorKind: TTyGlyphKind;
  AColor: TTyColor; AThickness: Integer; APadLogical: Integer = 4);
begin
  // The icon-font override fills ARect itself — a font glyph has its own side bearings, so the
  // vector's pad does not apply to it.
  if not TyTryDrawGlyphOverride(APainter, AController, ARect, ATokenName, AColor) then
    APainter.DrawGlyph(ARect, AVectorKind, AColor, AThickness, APadLogical);
end;

procedure TyDrawGlyph(APainter: TTyPainter; AController: TTyStyleController;
  const ARect: TRect; AVectorKind: TTyGlyphKind; AColor: TTyColor; AThickness: Integer;
  APadLogical: Integer = 4);
{ v3/C5. Convenience: the override token is derived from the kind (--glyph-<kind>). }
begin
  TyDrawGlyph(APainter, AController, ARect, TyGlyphKindToken(AVectorKind), AVectorKind, AColor,
    AThickness, APadLogical);
end;

{ v3/D. Expand a render-style FAMILY preset into concrete border/radius defaults — only for
  properties the theme did NOT set explicitly — so a skin writes 'render-style: bevel3d'
  instead of border-style + border-width + border-color + border-radius on every control.
  bevel3d = raised (outset), inset3d = sunken (inset); both are square and, when the theme
  gives no border-color, derive the bevel from the (solid) background face. }
procedure TyApplyRenderStyle(var AStyle: TTyStyleSet; var ACorners: TTyCorners);
begin
  if not (tpRenderStyle in AStyle.Present) then Exit;
  if AStyle.RenderStyle = trsFlat then Exit;
  if not (tpBorderStyle in AStyle.Present) then
  begin
    if AStyle.RenderStyle = trsInset3D then AStyle.BorderStyle := tbsInset
    else AStyle.BorderStyle := tbsOutset;
    Include(AStyle.Present, tpBorderStyle);
  end;
  if not (tpBorderWidth in AStyle.Present) then
  begin
    AStyle.BorderWidth := 2;   // classic 3D default
    Include(AStyle.Present, tpBorderWidth);
  end;
  if (not (tpBorderColor in AStyle.Present)) and (tpBackground in AStyle.Present) then
  begin
    AStyle.BorderColor := AStyle.Background.Color;   // derive the bevel from the face
    Include(AStyle.Present, tpBorderColor);
  end;
  ACorners := TyUniformCorners(0);   // 3D bevels are square
end;

procedure TTyGraphicControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
var
  corners, ringCorners: TTyCorners;
  off: Integer;
  ringRect: TRect;
  effStyle: TTyStyleSet;
begin
  TyFillParentBg(Self, APainter, ARect, AStyle);
  TyApplyStyleOpacity(Self, APainter, AStyle);
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  corners := TyEffectiveCorners(AStyle);
  effStyle := AStyle;
  TyApplyRenderStyle(effStyle, corners);   // v3/D: expand a render-style family preset
  if tpBackground in effStyle.Present then
    APainter.FillBackground(ARect, effStyle.Background, corners);
  if TyBorderVisible(effStyle) then
    if effStyle.BorderStyle in [tbsOutset, tbsInset] then
      TyDrawBevelBorder(APainter, ARect, effStyle)   // v3/B2 two-tone 3D bevel
    else
      APainter.StrokeBorder(ARect, corners, effStyle.BorderWidth, effStyle.BorderColor);
  // Focus ring: only present when a ':focus { outline: ... }' rule resolved.
  if (tpOutline in AStyle.Present) and (AStyle.OutlineWidth > 0) then
  begin
    off := APainter.Scale(AStyle.OutlineOffset);
    ringRect := Rect(ARect.Left + off, ARect.Top + off, ARect.Right - off, ARect.Bottom - off);
    ringCorners.TL := corners.TL - AStyle.OutlineOffset; if ringCorners.TL < 0 then ringCorners.TL := 0;
    ringCorners.TR := corners.TR - AStyle.OutlineOffset; if ringCorners.TR < 0 then ringCorners.TR := 0;
    ringCorners.BR := corners.BR - AStyle.OutlineOffset; if ringCorners.BR < 0 then ringCorners.BR := 0;
    ringCorners.BL := corners.BL - AStyle.OutlineOffset; if ringCorners.BL < 0 then ringCorners.BL := 0;
    APainter.StrokeBorder(ringRect, ringCorners, AStyle.OutlineWidth, AStyle.OutlineColor);
  end;
end;

procedure TTyGraphicControl.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TTyGraphicControl.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TTyGraphicControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := True;
    Invalidate;
  end;
end;

procedure TTyGraphicControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := False;
    Invalidate;
  end;
end;

procedure TTyGraphicControl.WndProc(var TheMessage: TLMessage);
var
  dc: HDC;
begin
  { WHY the hook is here and not at the end of Paint.

    Every control in this library paints the same way: build the frame into a BGRA layer,
    then let TTyPainter.EndPaint composite that layer onto the canvas. EndPaint OVERWRITES
    the canvas rectangle it owns, so anything drawn to the canvas earlier in the same pass
    is gone -- the two-pass GDI note in tyControls.Menu and the ghosted-icon work in
    tyControls.TreeView are both scars from exactly that. A hook fired from inside Paint
    would therefore be a hook whose output silently disappears, and a property the control
    offers but ignores is the defect this pass exists to remove.

    Paint itself is not a place a BASE class can wrap: 100+ controls override it, none call
    inherited, and each one's Paint/RenderTo pair finishes its composite differently (one
    painter, several painters, or a cached blit). LM_PAINT is the one point upstream of all
    of them -- whatever shape Paint took, it has returned by the time we get control back,
    so the composite is finished by construction and there is nothing per-control to wire.

    WHY WndProc and not a WMPaint message handler: TGraphicControl.WMPaint is PRIVATE, so a
    descendant in another unit cannot call it, and a same-message handler here would REPLACE
    it -- swallowing the LCL's canvas-handle setup and, worse, whatever the LCL adds to it
    later. Post-processing after inherited WndProc keeps that layer whole. The LCL clears
    Canvas.Handle on its way out, so the handle is re-established for the handler and
    released again -- and none of that runs unless a handler exists. With OnPaint unassigned
    this override is one integer compare per message. }
  inherited WndProc(TheMessage);
  if (TheMessage.Msg <> LM_PAINT) or not Assigned(OnPaint) then Exit;
  // TLMPaint.DC occupies the WParam slot (both sit directly after Msg/UnusedMsg), which is
  // also where Perform(LM_PAINT, DC, 0) puts it.
  dc := HDC(TheMessage.WParam);
  if dc = 0 then Exit;
  Canvas.Lock;
  try
    Canvas.Handle := dc;
    try
      OnPaint(Self);
    finally
      Canvas.Handle := 0;
    end;
  finally
    Canvas.Unlock;
  end;
end;

{ TTyCustomControl }

constructor TTyCustomControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Render to one offscreen buffer and blit once: eliminates the background-erase
  // flash on every repaint (notably the 530ms caret-blink Invalidate). Pixel output
  // is unchanged; only the on-screen WMPaint path is affected (RenderTo bypasses it).
  DoubleBuffered := True;
  ActiveController.RegisterStyleable(Self);
end;

function TTyCustomControl.GetVersion: string;
begin
  Result := TyVersion;
end;

function TTyCustomControl._AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

function TTyCustomControl._Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
begin
  Result := -1;
end;

destructor TTyCustomControl.Destroy;
begin
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  inherited Destroy;
end;

procedure TTyCustomControl.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Invalidate;
end;

procedure TTyCustomControl.SetStyleOverride(const AValue: string);
begin
  if FStyleOverride = AValue then Exit;
  FStyleOverride := AValue;
  FOvrCacheValid := False;   // force a re-parse on the next CurrentStyle
  Invalidate;
end;

{$IFDEF LCLGTK3}
procedure TTyCustomControl.Invalidate;
begin
  RefreshGtk3EraseColor;
  inherited Invalidate;
end;

procedure TTyCustomControl.RefreshGtk3EraseColor;
var
  st: TTyStyleSet;
  c: TTyColor;
  ver: Cardinal;
begin
  { LCL-GTK3 clears nothing before a repaint. InvalidateRect drops bErase; the LM_ERASEBKGND it
    does send is gated on wcfEraseBackground, which it never sets and cannot (the field is
    private to TWinControl); TWinControl's own erase branch is unreachable because GTK3 always
    supplies a DC. The one clear still standing is TGtk3CustomControl.DoBeforeLCLPaint -- and it
    skips its fillRect whenever the control's Color is clDefault, which {$DEFINE UseCLDefault}
    makes the default for anything that never assigns one. That is every control here.

    So nothing writes the pixels under a GRAPHIC child, which paints only its glyphs and leaves
    the rest to whatever the host erased. On GTK3 nothing did, so the rectangle keeps the
    PREVIOUS theme's pixels: a label sits in a pale block after a switch to dark, and its ink,
    now light, vanishes into it. Giving the control a real Colour brings the backend's own clear
    back, and the value is the opaque background we paint anyway, so it can only agree.

    ONCE PER THEME CHANGE, and this is the part the first attempt got wrong. That version ran
    from CurrentStyle -- a getter, called on every paint -- and assigning Color invalidates, so
    each child's paint invalidated its parent and the parent's repaint invalidated it back: a
    repaint storm that starved the GTK main loop, and windows that cannot finish a frame cannot
    be dragged and popups cannot finish mapping. Keyed on the theme version, the assignment
    happens once and the re-entrant Invalidate it triggers finds nothing left to do. The flag
    is belt and braces. }
  if FInEraseRefresh then Exit;
  ver := ActiveController.Model.ThemeVersion;
  if (ver = FEraseThemeVer) and (ver <> 0) then Exit;
  FInEraseRefresh := True;
  try
    FEraseThemeVer := ver;
    st := CurrentStyle;
    c := 0;
    if (tpBackground in st.Present) and (st.Background.Kind = tfkSolid)
       and (TyAlphaOf(st.Background.Color) = 255) then
      c := st.Background.Color
    else if not TyResolveParentBg(Self, c) then
      Exit;
    if Color <> TyColorToLCL(c) then
      Color := TyColorToLCL(c);
  finally
    FInEraseRefresh := False;
  end;
end;
{$ENDIF}

procedure TTyCustomControl.SetController(AValue: TTyStyleController);
begin
  if FController = AValue then Exit;
  { Unregister from current active controller and remove free-notification }
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  { Register with new active controller and wire free-notification }
  if FController <> nil then
    FController.FreeNotification(Self);
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyCustomControl.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FController) then
    FController := nil;
end;

function TTyCustomControl.ActiveController: TTyStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyCustomControl.InDpiAdjust: Boolean;
begin
  Result := FDpiAdjusting;
end;

procedure TTyCustomControl.DoUpdateSizeConstraints;
begin
  // Most controls own no size floor. Overridden where one exists.
end;

procedure TTyCustomControl.UpdateSizeConstraints;
begin
  // See the TTyGraphicControl twin.
  if InDpiAdjust then Exit;
  DoUpdateSizeConstraints;
end;

procedure TTyCustomControl.AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
  const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer);
begin
  // See the TTyGraphicControl twin.
  FDpiAdjusting := True;
  try
    inherited AutoAdjustLayout(AMode, AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth);
  finally
    FDpiAdjusting := False;
  end;
  { See the TTyGraphicControl twin for why the font PPI is tested here -- it is the
    ParentFont default, and getting it wrong reintroduces the whole defect. }
  if (AMode in [lapAutoAdjustWithoutHorizontalScrolling, lapAutoAdjustForDPI])
     and (AToPPI > 0) and (Font.PixelsPerInch = AToPPI) then
    UpdateSizeConstraints;
end;

function TTyCustomControl.CurrentStates: TTyStateSet;
begin
  Result := [];
  if not Enabled then
  begin
    Include(Result, tysDisabled);
    Exit;
  end;
  if FHover then Include(Result, tysHover);
  if FPressed then Include(Result, tysActive);
  if Focused then Include(Result, tysFocused);
  if Result = [] then
    Include(Result, tysNormal);
end;

function TTyCustomControl.CurrentStyle: TTyStyleSet;
var
  model: TTyStyleModel;
begin
  model := ActiveController.Model;
  Result := model.ResolveStyle(GetStyleTypeKey,
    TyStyleClassFor(Self, FStyleClass), CurrentStates);
  // A9 layer 2: overlay the per-instance override last. Recompute only when stale —
  // the override text changed or the theme version bumped (so var(--...) re-binds).
  if FStyleOverride <> '' then
  begin
    if (not FOvrCacheValid) or (FOvrCacheText <> FStyleOverride)
       or (FOvrCacheVer <> model.ThemeVersion) then
    begin
      FOvrCache := model.ResolveOverride(FStyleOverride);
      FOvrCacheText := FStyleOverride;
      FOvrCacheVer := model.ThemeVersion;
      FOvrCacheValid := True;
    end;
    TyMergeStyleSet(Result, FOvrCache);   // override wins per Present flag (§3.3)
  end;
end;

function TyResolveFontSize(const AStyle: TTyStyleSet; AParentFont: Boolean;
  AControlFontSize: Integer; AController: TTyStyleController): Integer;
var
  base: Integer;
begin
  if AStyle.FontSize > 0 then
    Exit(AStyle.FontSize);
  if (not AParentFont) and (AControlFontSize > 0) then
    Exit(AControlFontSize);
  base := 0;
  if AController <> nil then
    base := AController.Metric('--font-size-base', 0);
  if base > 0 then
    Result := base
  else if AControlFontSize > 0 then
    Result := AControlFontSize
  else
    Result := 9;
end;

function TTyCustomControl.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

procedure TTyCustomControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
var
  corners, ringCorners: TTyCorners;
  off: Integer;
  ringRect: TRect;
  pc: TTyColor;
  gHost: ITyGlassHost;
  gOff: TPoint;
  effStyle: TTyStyleSet;
begin
  TyFillParentBg(Self, APainter, ARect, AStyle);
  TyApplyStyleOpacity(Self, APainter, AStyle);
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  corners := TyEffectiveCorners(AStyle);
  effStyle := AStyle;
  TyApplyRenderStyle(effStyle, corners);   // v3/D: expand a render-style family preset
  if tpBackground in effStyle.Present then
    APainter.FillBackground(ARect, effStyle.Background, corners);
  if TyBorderVisible(effStyle) then
    if effStyle.BorderStyle in [tbsOutset, tbsInset] then
      TyDrawBevelBorder(APainter, ARect, effStyle)   // v3/B2 two-tone 3D bevel
    else
      APainter.StrokeBorder(ARect, corners, effStyle.BorderWidth, effStyle.BorderColor);
  // A windowed control paints into its own opaque bitmap, so a drop shadow's blur bleeds
  // into the corner gaps OUTSIDE the rounded background — it can't cast onto the parent, so
  // it just leaves a dirty patch there. Re-paint those gaps with the flat parent background
  // to keep the rounded silhouette clean. Only when there IS a shadow + a solid (non-glass)
  // parent — the glass path already shows the form photo through the corners. (The shadow
  // INSIDE the rounded shape, e.g. a checkbox box, is untouched.)
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0)
     and not TyResolveGlassHost(Self, gHost, gOff) and TyResolveParentBg(Self, pc) then
    APainter.FillCornerGaps(ARect, corners, pc);
  // Focus ring: only present when a ':focus { outline: ... }' rule resolved.
  if (tpOutline in AStyle.Present) and (AStyle.OutlineWidth > 0) then
  begin
    off := APainter.Scale(AStyle.OutlineOffset);
    ringRect := Rect(ARect.Left + off, ARect.Top + off, ARect.Right - off, ARect.Bottom - off);
    ringCorners.TL := corners.TL - AStyle.OutlineOffset; if ringCorners.TL < 0 then ringCorners.TL := 0;
    ringCorners.TR := corners.TR - AStyle.OutlineOffset; if ringCorners.TR < 0 then ringCorners.TR := 0;
    ringCorners.BR := corners.BR - AStyle.OutlineOffset; if ringCorners.BR < 0 then ringCorners.BR := 0;
    ringCorners.BL := corners.BL - AStyle.OutlineOffset; if ringCorners.BL < 0 then ringCorners.BL := 0;
    APainter.StrokeBorder(ringRect, ringCorners, AStyle.OutlineWidth, AStyle.OutlineColor);
  end;
end;

function TTyCustomControl.FillSharpBackdrop(APainter: TTyPainter; const ARect: TRect): Boolean;
var
  host: ITyGlassHost;
  off: TPoint;
begin
  Result := TyResolveGlassHost(Self, host, off);
  if Result then
    // ARect is control-local; shift the backdrop sample by the sub-rect's origin.
    APainter.FillImageSlice(ARect, host.GlassSharpBackdrop,
      Point(off.X + ARect.Left, off.Y + ARect.Top));
end;

procedure TTyCustomControl.MouseEnter;
begin
  inherited MouseEnter;
  FHover := True;
  Invalidate;
end;

procedure TTyCustomControl.MouseLeave;
begin
  inherited MouseLeave;
  FHover := False;
  Invalidate;
end;

procedure TTyCustomControl.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := True;
    Invalidate;
    { LCL does NOT auto-focus a custom-drawn TCustomControl on click -- only native
      widgets do -- so without this a click never moves focus (it lingers on whatever
      had it, e.g. the Edit you clicked away from). Focus a click on a focusable control
      so a plain click behaves like Tab. Gated on TabStop (the "participates in focus"
      signal, so panels/labels/non-activating popups with TabStop=False never steal it)
      and guarded for the headless test runner (CanFocus is False there anyway). }
    if TabStop and CanFocus and not Focused then
      try SetFocus except end;
  end;
end;

procedure TTyCustomControl.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FPressed := False;
    Invalidate;
  end;
end;

procedure TTyCustomControl.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TTyCustomControl.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TTyCustomControl.PaintWindow(DC: HDC);
var
  dcChanged: Boolean;
begin
  { The windowed twin of TTyGraphicControl.WMPaint -- the same reasoning, one level higher.
    TWinControl.PaintHandler reaches a windowed control's own surface through PaintWindow
    and nowhere else, so this is where Paint has provably returned and every painter in it
    has composited. Firing from inside Paint would put the handler's ink UNDER the very
    composite it is meant to sit on; on a cached container it would also be baked into the
    cache and then repeated, frozen, on every child-damage blit.

    TCustomControl.PaintWindow puts the DC on the canvas for Paint and takes it off again,
    so the handler needs it back. Mirror the LCL's own condition rather than assuming: it
    only restores the handle it actually replaced, and a caller that had already parked this
    DC on the canvas must keep it. Nothing here runs without a handler -- an unassigned
    OnPaint costs one pointer test per paint and not a single DC call. }
  inherited PaintWindow(DC);
  if (DC = 0) or not Assigned(OnPaint) then Exit;
  dcChanged := (not Canvas.HandleAllocated) or (Canvas.Handle <> DC);
  if dcChanged then Canvas.Handle := DC;
  try
    OnPaint(Self);
  finally
    if dcChanged then Canvas.Handle := 0;
  end;
end;

end.
