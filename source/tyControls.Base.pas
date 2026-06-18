unit tyControls.Base;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LMessages, LCLType, BGRABitmap,
  tyControls.Types, tyControls.Controller, tyControls.StyleModel,
  tyControls.Painter;
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
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
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
  published
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
    procedure CMEnabledChanged(var Msg: TLMessage); message CM_ENABLEDCHANGED;
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
  published
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

implementation

{$IFDEF WINDOWS}
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
{$IFDEF WINDOWS}
var
  imc: THandle;
  cf: TTyImeCompForm;
{$ENDIF}
begin
{$IFDEF WINDOWS}
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

procedure TTyGraphicControl.CMEnabledChanged(var Msg{%H-}: TLMessage);
begin
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
  Result := model.ResolveStyle(GetStyleTypeKey, FStyleClass, CurrentStates);
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
function TyResolveParentBg(AChild: TControl; out AColor: TTyColor): Boolean;
var
  st: TTyStyleSet;
  r, g, b: Byte;
begin
  Result := False;
  if (AChild = nil) or (AChild.Parent = nil) then Exit;
  if AChild.Parent is TTyCustomControl then
  begin
    st := TTyCustomControl(AChild.Parent).CurrentStyle;
    if not (tpBackground in st.Present) then Exit;
    case st.Background.Kind of
      tfkSolid:          begin AColor := st.Background.Color;  Result := True; end;
      tfkLinearGradient: begin AColor := st.Background.GradTo; Result := True; end; // representative
    end;
  end
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

procedure TTyGraphicControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
var
  corners, ringCorners: TTyCorners;
  off: Integer;
  ringRect: TRect;
begin
  TyFillParentBg(Self, APainter, ARect, AStyle);
  if tpOpacity in AStyle.Present then
    APainter.Opacity := AStyle.Opacity;
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  corners := TyEffectiveCorners(AStyle);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, corners);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0)
     and not ((tpBorderStyle in AStyle.Present) and (AStyle.BorderStyle = tbsNone)) then
    APainter.StrokeBorder(ARect, corners, AStyle.BorderWidth, AStyle.BorderColor);
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

procedure TTyCustomControl.CMEnabledChanged(var Msg{%H-}: TLMessage);
begin
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
  Result := model.ResolveStyle(GetStyleTypeKey, FStyleClass, CurrentStates);
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

function TTyCustomControl.ResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  // Text size priority: theme font-size, then the control's own Font.Size, then a
  // readable default — so a typeKey without a font-size rule (or an unstyled Font)
  // never renders zero-height text.
  if AStyle.FontSize > 0 then
    Result := AStyle.FontSize
  else if Font.Size > 0 then
    Result := Font.Size
  else
    Result := 9;
end;

procedure TTyCustomControl.DrawFrame(APainter: TTyPainter; const ARect: TRect; const AStyle: TTyStyleSet);
var
  corners, ringCorners: TTyCorners;
  off: Integer;
  ringRect: TRect;
begin
  TyFillParentBg(Self, APainter, ARect, AStyle);
  if tpOpacity in AStyle.Present then
    APainter.Opacity := AStyle.Opacity;
  if (tpShadow in AStyle.Present) and (TyAlphaOf(AStyle.ShadowColor) > 0) then
    APainter.DropShadow(ARect, AStyle.BorderRadius, AStyle.ShadowColor, AStyle.ShadowBlur, AStyle.ShadowOffset);
  corners := TyEffectiveCorners(AStyle);
  if tpBackground in AStyle.Present then
    APainter.FillBackground(ARect, AStyle.Background, corners);
  if (tpBorderColor in AStyle.Present) and (AStyle.BorderWidth > 0)
     and not ((tpBorderStyle in AStyle.Present) and (AStyle.BorderStyle = tbsNone)) then
    APainter.StrokeBorder(ARect, corners, AStyle.BorderWidth, AStyle.BorderColor);
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
