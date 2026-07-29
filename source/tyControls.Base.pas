unit tyControls.Base;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LMessages, LCLType, BGRABitmap,
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
    function _AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function _Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet; virtual;
    function CurrentStyle: TTyStyleSet;
    procedure DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetVersion: string;
  published
    { Read-only library version (TyVersion); the design-time editor for this property opens
      the About dialog. }
    property Version: string read GetVersion;
    property Enabled;
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
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property Cursor;
    property ParentShowHint;
    property Action;
    property StyleClass: string read FStyleClass write SetStyleClass;
    { A9: a per-instance CSS declaration block (e.g. 'border-color: var(--accent);')
      applied on top of the theme for THIS control only. May reference var(--...) tokens,
      which resolve against the active theme. A malformed value is skipped, never fatal. }
    property StyleOverride: string read FStyleOverride write SetStyleOverride;
    property Controller: TTyStyleController read FController write SetController;
  end;

  TTyCustomControl = class(TCustomControl, ITyStyleable)
  private
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
    procedure SetController(AValue: TTyStyleController); virtual;
    function _AddRef: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function _Release: Integer; {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
    function GetStyleTypeKey: string; virtual; abstract;
    function ActiveController: TTyStyleController;
    function CurrentStates: TTyStateSet; virtual;
    function CurrentStyle: TTyStyleSet;
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
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetVersion: string;
  published
    { Read-only library version (TyVersion); the design-time editor for this property opens
      the About dialog. }
    property Version: string read GetVersion;
    property Enabled;
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
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property Cursor;
    property ParentShowHint;
    property Action;
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

{ Resolve the SOLID background a windowed child should composite onto (it does not
  inherit its parent's painted bg, so corner-gaps / transparent fills would otherwise
  show the child's own window colour). Styleable parent -> its themed CurrentStyle;
  a TTyForm parent -> its themed TyForm bg (via ITyThemedBackground, correct at design
  time too); otherwise the parent's raw LCL Color. False only when there is no parent.
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

function TyResolveParentBg(AChild: TControl; out AColor: TTyColor): Boolean;
var
  st: TTyStyleSet;
  r, g, b, a: Byte;
  back: TTyColor;
  tb: ITyThemedBackground;
begin
  Result := False;
  if (AChild = nil) or (AChild.Parent = nil) then Exit;
  if AChild.Parent is TTyCustomControl then
  begin
    st := TTyCustomControl(AChild.Parent).CurrentStyle;
    { A container with NO background, or a fully TRANSPARENT one (e.g. TyGroupBox
      bg = alpha(#FFFFFF,0)), shows whatever is behind IT — so walk up to the next
      opaque backdrop. Otherwise a child's corner-gap / parent fill would resolve to
      a transparent color and the Win10 DWM glass would show through (an Edit inside
      a group box had system-colored corners). }
    if not (tpBackground in st.Present) then
      Exit(TyResolveParentBg(AChild.Parent, AColor));
    case st.Background.Kind of
      tfkSolid:
        if TyAlphaOf(st.Background.Color) = 0 then
          Exit(TyResolveParentBg(AChild.Parent, AColor))
        else if TyAlphaOf(st.Background.Color) < 255 then
        begin
          { A PARTLY transparent container shows the backdrop through itself, so the opaque
            colour this function promises is that container COMPOSITED OVER what is behind
            it. Returning its raw value instead breaks the promise in a way that only shows
            up on a widgetset which never clears a damaged region: the child fills with a
            non-opaque "background", its finished bitmap is therefore non-opaque, and every
            repaint composites onto the previous one instead of replacing it. That is the
            GTK3 smearing on exactly the controls that DO call TyFillParentBg. Throwing the
            alpha away instead would keep it opaque but at the wrong hue. }
          if not TyResolveParentBg(AChild.Parent, back) then
            back := TyRGB(255, 255, 255);
          a := TyAlphaOf(st.Background.Color);
          AColor := TyRGB(
            (TyRedOf(st.Background.Color)   * a + TyRedOf(back)   * (255 - a)) div 255,
            (TyGreenOf(st.Background.Color) * a + TyGreenOf(back) * (255 - a)) div 255,
            (TyBlueOf(st.Background.Color)  * a + TyBlueOf(back)  * (255 - a)) div 255);
          Result := True;
        end
        else
        begin AColor := st.Background.Color;  Result := True; end;
      tfkLinearGradient: begin AColor := st.Background.GradTo; Result := True; end; // representative
    end;
  end
  // A TTyForm parent: use its THEMED TyForm bg (correct at design time too — the LCL
  // Color is only themed by ApplyChromeTheme at runtime). Same value as Color at runtime.
  else if Supports(AChild.Parent, ITyThemedBackground, tb) and tb.ThemedBgColor(AColor) then
    Result := True
  else
  begin
    RedGreenBlue(ColorToRGB(AChild.Parent.Color), r, g, b);
    AColor := TyRGB(r, g, b);
    Result := True;
  end;
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
  else if TyResolveParentBg(AControl, c) then
  begin
    f := Default(TTyFill);
    f.Kind := tfkSolid;
    f.Color := c;
    APainter.FillBackground(ARect, f, 0);
  end;
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

end.
