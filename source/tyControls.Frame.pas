unit tyControls.Frame;
{$mode objfpc}{$H+}
{ TTyFrame: the designer base class for an embeddable composite view -- what TTyForm is to a
  window, for the part of one that is drawn in the designer with its own .lfm and put on a
  host at run time:

    TMyView = class(TTyFrame)   // File > New > TyControls Frame

  A frame is scaffolding, not a surface: the default theme gives the TyFrame key no rule, so
  it paints what is behind it -- its host's themed background, the slice of it the frame
  covers -- and the controls on it see the host through it. A theme, a StyleClass or a
  StyleOverride that gives it a background makes it a surface of its own.

  Plain LCL controls on it (ParentColor) take its LCL Color, which at run time is the colour
  behind them, as on every themed container. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller,
  tyControls.StyleModel;
type
  { Not split into a custom class and a published one: like TTyForm it stands where LCL's
    own class stands (TFrame, which publishes for TCustomFrame), and its descendants are
    designed, not put on the palette. }
  TTyFrame = class(TFrame, ITyStyleable, ITyBackgroundHost, ITyThemedBackground)
  private
    FStyleClass: string;
    FController: TTyCustomStyleController;
    { The per-instance StyleOverride, parsed again only when its text or the theme changes
      (TTyCustomControl's, which shares no ancestor with a frame). }
    FStyleOverride: string;
    FOvrCache: TTyStyleSet;
    FOvrCacheText: string;
    FOvrCacheVer: Cardinal;
    FOvrCacheValid: Boolean;
    { The rendered frame, kept between the paints a child's damage asks for (TTyPaintCache),
      and what it was rendered for. }
    FPaintCache: TTyPaintCache;
    FPaintKey: string;
    { The LCL Color the frame last gave itself: see TTyCustomControl.KeepColorThemed, whose
      twin this is. A frame's Invalidate is not the hot path a control's is (it has no
      hover, no caret), so the frame asks on every one and needs no version to compare. }
    FThemedColor: TColor;
    FThemedColorSet: Boolean;
    FInThemedColor: Boolean;
    function ColorIsThemed: Boolean;
    function ThemedColorNotStored: Boolean;
    procedure KeepColorThemed;
    procedure CMParentColorChanged(var Message: TLMessage); message CM_PARENTCOLORCHANGED;
    procedure SetStyleClass(const AValue: string);
    procedure SetStyleOverride(const AValue: string);
    { What is behind the frame when nothing themed is: its LCL colour, resolved. }
    function LclBackdrop: TTyFill;
    { On an image theme the frame shows the form's photo where it sits (TyFillParentBg). }
    function OnImageBackdrop: Boolean;
  protected
    procedure SetController(AValue: TTyCustomStyleController); virtual;
    { ITyStyleable. 'TyFrame'; a family of views may answer a key of its own. }
    function GetStyleTypeKey: string; virtual;
    function ActiveController: TTyCustomStyleController;
    { The theme's rule for the key and StyleClass, with StyleOverride over it. A frame has no
      hover or focus of its own: the rest state, or disabled. }
    function CurrentStyle: TTyStyleSet;
    { The frame is what the designer is editing: it has no host there, and stands on the
      designer's own window. }
    function IsDesignRoot: Boolean;
    { ITyBackgroundHost: the background the frame paints as its own, for the controls on it.
      CurrentStyle's; as the designer's root with none, the TyForm background it paints
      there. False: the frame shows its host. }
    function OwnBackground(out AFill: TTyFill): Boolean; virtual;
    { ITyThemedBackground: what is behind the controls on the frame, when that is one colour
      -- its own solid background, or its host's. False for a gradient. }
    function ThemedBgColor(out AColor: TTyColor): Boolean;
    { The whole frame onto ACanvas: what is behind it, then its own background and border
      as every control draws them. Virtual, for a view that draws more of itself. }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); virtual;
    { Everything the rendered frame depends on besides its size. Its own inputs, and what
      its host resolves to where the frame sits: a host changes its look without telling
      the frame (its StyleOverride is its own), and a frame moved along a gradient covers
      another slice. }
    function PaintKey: string;
    procedure Paint; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function ColorIsStored: Boolean; override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
    function GetVersion: string;
  published
    { Read-only library version (TyVersion); the design-time editor for this property opens
      the About dialog. }
    property Version: string read GetVersion;
    { The style controller the frame reads its theme from; unset, the built-in default
      controller. The controls on the frame have their own. }
    property Controller: TTyCustomStyleController read FController write SetController;
    property StyleClass: string read FStyleClass write SetStyleClass;
    { A CSS declaration block for THIS frame only, over the theme: 'background: var(--surface);'
      makes it a surface. }
    property StyleOverride: string read FStyleOverride write SetStyleOverride;
    { TFrame publishes these two, and assigning a Color switches both off. The colour a
      themed frame gives itself at run time is derived, so none of it goes to a form file. }
    property ParentBackground stored ThemedColorNotStored;
    property ParentColor stored ThemedColorNotStored;
  end;

implementation

{ A frame class other than TFrame is built from its form file, and TCustomFrame.Create
  raises when there is none. TTyFrame itself has none and is still a frame code may create
  (TFrame can be); its descendants go on to LCL's loader, and to its error. }
function TyBareFrameInit(Instance: TComponent; RootAncestor: TClass): Boolean;
begin
  Result := Instance.ClassType = TTyFrame;
end;

function TyFillKey(const AFill: TTyFill): string;
var
  i: Integer;
begin
  Result := Format('%d:%x', [Ord(AFill.Kind), AFill.Color]);
  if AFill.Kind <> tfkLinearGradient then Exit;
  Result := Result + Format(':%x:%x:%g', [AFill.GradFrom, AFill.GradTo, AFill.GradAngleDeg]);
  for i := 0 to High(AFill.GradStops) do
    Result := Result + Format(':%x@%g', [AFill.GradStops[i].Color, AFill.GradStops[i].Pos]);
end;

{ TTyFrame }

constructor TTyFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { One offscreen buffer, blitted once: no erase flash before the themed fill. }
  DoubleBuffered := True;
  { After the form file is read: a Controller it names is the one to listen to. }
  ActiveController.RegisterStyleable(Self);
end;

destructor TTyFrame.Destroy;
begin
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  FreeAndNil(FPaintCache);
  inherited Destroy;
end;

procedure TTyFrame.Invalidate;
begin
  { Everything that changes the frame's own look ends here; a child's damage does not. }
  if FPaintCache <> nil then FPaintCache.Drop;
  inherited Invalidate;
  { A theme change reaches the frame only as this; so does a Color the application sets
    back to clDefault, which hands the colour back. }
  KeepColorThemed;
end;

procedure TTyFrame.KeepColorThemed;
var
  st: TTyStyleSet;
  f: TTyFill;
  r: TRect;
  w, h: Integer;
  c: TColor;
begin
  if FInThemedColor or ([csDesigning, csLoading, csDestroying] * ComponentState <> []) then
    Exit;
  if not (ParentColor or (Color = clDefault) or ColorIsThemed) then
  begin
    FThemedColorSet := False;   // somebody else's colour
    Exit;
  end;
  st := Default(TTyStyleSet);
  if OwnBackground(st.Background) then Include(st.Present, tpBackground);
  w := ClientWidth;  if w <= 0 then w := Width;
  h := ClientHeight; if h <= 0 then h := Height;
  r := Rect(0, 0, w, h);
  if not TyStyledBackdropFill(Self, st, r, f, True) then Exit;
  c := TyColorToLCL(TyFillCentreColor(f, r));
  { A frame without a background on a themed host is already there: its host carries the
    colour and the frame follows it by ParentColor. }
  if Color = c then Exit;
  FInThemedColor := True;
  try
    Color := c;
    FThemedColor := c;
    FThemedColorSet := True;
  finally
    FInThemedColor := False;
  end;
end;

function TTyFrame.ColorIsThemed: Boolean;
begin
  Result := FThemedColorSet and (Color = FThemedColor);
end;

function TTyFrame.ColorIsStored: Boolean;
begin
  Result := inherited ColorIsStored and not ColorIsThemed;
end;

function TTyFrame.ThemedColorNotStored: Boolean;
begin
  Result := not ColorIsThemed;
end;

procedure TTyFrame.CMParentColorChanged(var Message: TLMessage);
begin
  inherited;
  KeepColorThemed;   // a new parent, or the parent's colour moved
end;

procedure TTyFrame.Loaded;
begin
  inherited Loaded;
  { a frame read as part of a form gets its parent's colour here without a message, and
    without a repaint when that colour is the one it had }
  KeepColorThemed;
end;

function TTyFrame.GetVersion: string;
begin
  Result := TyVersion;
end;

procedure TTyFrame.SetStyleClass(const AValue: string);
begin
  if FStyleClass = AValue then Exit;
  FStyleClass := AValue;
  Invalidate;
end;

procedure TTyFrame.SetStyleOverride(const AValue: string);
begin
  if FStyleOverride = AValue then Exit;
  FStyleOverride := AValue;
  FOvrCacheValid := False;   // parsed again on the next CurrentStyle
  Invalidate;
end;

procedure TTyFrame.SetController(AValue: TTyCustomStyleController);
begin
  if FController = AValue then Exit;
  if FController <> nil then
  begin
    FController.RemoveFreeNotification(Self);
    FController.UnregisterStyleable(Self);
  end
  else
    TyDefaultController.UnregisterStyleable(Self);
  FController := AValue;
  if FController <> nil then
    FController.FreeNotification(Self);
  ActiveController.RegisterStyleable(Self);
  Invalidate;
end;

procedure TTyFrame.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FController) then
  begin
    FController := nil;
    if not (csDestroying in ComponentState) then
    begin
      TyDefaultController.RegisterStyleable(Self);
      Invalidate;
    end;
  end;
end;

function TTyFrame.GetStyleTypeKey: string;
begin
  Result := 'TyFrame';
end;

function TTyFrame.ActiveController: TTyCustomStyleController;
begin
  if FController <> nil then
    Result := FController
  else
    Result := TyDefaultController;
end;

function TTyFrame.CurrentStyle: TTyStyleSet;
var
  model: TTyStyleModel;
begin
  model := ActiveController.Model;
  Result := model.ResolveStyle(GetStyleTypeKey, FStyleClass,
    TyStatesUnlessDisabled(Self, [tysNormal]));
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
    TyMergeStyleSet(Result, FOvrCache);
  end;
end;

function TTyFrame.IsDesignRoot: Boolean;
begin
  { LCL's own test for it (TCustomFrame.CalculatePreferredSize): a frame placed on a form in
    the designer is owned by that form. }
  Result := (csDesigning in ComponentState) and (Owner = nil);
end;

function TTyFrame.OwnBackground(out AFill: TTyFill): Boolean;
var
  st: TTyStyleSet;
begin
  st := CurrentStyle;
  Result := tpBackground in st.Present;
  if (not Result) and IsDesignRoot then
  begin
    st := ActiveController.Model.ResolveStyle('TyForm', '', []);
    Result := tpBackground in st.Present;
  end;
  if Result then
    AFill := st.Background
  else
    AFill := Default(TTyFill);
end;

function TTyFrame.ThemedBgColor(out AColor: TTyColor): Boolean;
var
  st: TTyStyleSet;
  f: TTyFill;
  w, h: Integer;
begin
  AColor := 0;
  st := Default(TTyStyleSet);
  if OwnBackground(st.Background) then Include(st.Present, tpBackground);
  w := ClientWidth;  if w <= 0 then w := Width;
  h := ClientHeight; if h <= 0 then h := Height;
  Result := TyStyledBackdropFill(Self, st, Rect(0, 0, w, h), f) and (f.Kind = tfkSolid);
  if Result then AColor := f.Color;
end;

function TTyFrame.LclBackdrop: TTyFill;
var
  r, g, b: Byte;
begin
  Result := Default(TTyFill);
  Result.Kind := tfkSolid;
  RedGreenBlue(ColorToRGB(GetColorResolvingParent), r, g, b);
  Result.Color := TyRGB(r, g, b);
end;

function TTyFrame.OnImageBackdrop: Boolean;
var
  p: TControl;
  host: ITyGlassHost;
begin
  Result := False;
  p := Parent;
  while p <> nil do
  begin
    if Supports(p, ITyGlassHost, host) then
      Exit(host.GlassSharpBackdrop <> nil);
    p := p.Parent;
  end;
end;

procedure TTyFrame.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, formStyle: TTyStyleSet;
  r: TRect;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    r := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    if IsDesignRoot then
    begin
      { No host in the designer: the form background it will most likely sit on, so the
        design surface looks like the application. Its own background goes over it below. }
      P.FillBackground(r, LclBackdrop, 0);
      formStyle := ActiveController.Model.ResolveStyle('TyForm', '', []);
      if tpBackground in formStyle.Present then
        P.FillBackground(r, formStyle.Background, 0);
    end
    else if Parent <> nil then
      { The host's backdrop where the frame sits -- a gradient's slice, an image theme's
        photo -- or a plain parent's colour. }
      TyFillParentBg(Self, P, r, S)
    else
      P.FillBackground(r, LclBackdrop, 0);
    { Then what every control draws: DrawFrame's steps, so a background brings its border,
      radius and shadow with it. }
    TyApplyStyleOpacity(Self, P, S);
    TyDrawFrameUnderlay(P, r, S);
    TyDrawFrameChrome(Self, P, r, S);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

function TTyFrame.PaintKey: string;
var
  ctrl: TTyCustomStyleController;
  f: TTyFill;
  w, h: Integer;
begin
  ctrl := ActiveController;
  Result := Format('%p|%u|%s|%s|%d|%d|', [Pointer(ctrl), ctrl.Model.ThemeVersion,
    FStyleClass, FStyleOverride, Ord(IsEnabled), Font.PixelsPerInch]);
  w := ClientWidth;  if w <= 0 then w := Width;
  h := ClientHeight; if h <= 0 then h := Height;
  if TyResolveParentBgFill(Self, Rect(0, 0, w, h), f) then
    Result := Result + TyFillKey(f)
  else
    Result := Result + TyFillKey(LclBackdrop);
end;

procedure TTyFrame.Paint;
var
  w, h: Integer;
  key: string;
begin
  w := ClientWidth;
  h := ClientHeight;
  if (w > 0) and (h > 0) then
    { The designer repaints rarely and streams while it does; the photo of an image theme
      is a slice no key can stand for. Both render every paint. }
    if (csDesigning in ComponentState) or OnImageBackdrop then
      RenderTo(Canvas, Rect(0, 0, w, h), Font.PixelsPerInch)
    else
    begin
      { A view is a large surface under many small controls: a graphic child's damage must
        cost that child's rectangle, not a render of the whole frame (see TTyPaintCache). }
      if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
      key := PaintKey;
      if key <> FPaintKey then
      begin
        FPaintCache.Drop;
        FPaintKey := key;
      end;
      if FPaintCache.NeedsRender(w, h, TyCanvasDeviceScale(Canvas)) then
        RenderTo(FPaintCache.Canvas, Rect(0, 0, w, h), Font.PixelsPerInch);
      FPaintCache.Blit(Canvas);
    end;
  inherited Paint;
end;

initialization
  RegisterInitComponentHandler(TTyFrame, @TyBareFrameInit);

end.
