unit tyControls.FormSurface;

{$mode objfpc}{$H+}

{ TTyFormSurface — the content host for TTyForm.

  A top-level WS_THICKFRAME window's OWN GDI client DC is clipped ~frame px short of its visible
  edge (the DWM backing surface is only `windowHeight - 2*frame` tall), so painting the form
  directly leaves an unpaintable "dead band" on the right/bottom. A CHILD window has no thick frame
  and its backing surface spans its full rect, so it paints edge-to-edge.

  TTyFormSurface is that child: an alClient container that fills the form client, renders the themed
  `form` background (delegated back to the form so the theme/controller/backdrop logic stays in one
  place) and HOSTS every control. Because the controls are ITS children, graphic (windowless)
  controls such as TTyLabel paint onto the surface's own canvas and stay visible — a plain back-most
  layer would occlude them. It is streamed from the .lfm as `object Surface: TTyFormSurface` with the
  controls nested under it; the designer treats it as an ordinary client-area panel (drops land in it;
  it is visible/selectable in the Object Inspector). Harmless on every widgetset. }

interface

uses
  Classes, Controls, Graphics, Forms, tyControls.Base, tyControls.StrConsts;

type
  TTyFormSurface = class(TTyCustomControl)
  private
    { The form's background as last rendered, and what it was rendered from (see
      PaintFormBackground). }
    FBgCache: TTyPaintCache;
    FBgKey: string;
    FBgRenders: Integer;   // FOR THE TESTS: renders, not blits
    function GetPurpose: string;
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
    { Paint's work, on any canvas: the owning form's background, from the cache when nothing
      it depends on has changed. AForm is the form Paint found (a TTyForm). }
    procedure PaintFormBackground(AForm: TCustomForm; ACanvas: TCanvas);
    property BgRenders: Integer read FBgRenders;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Drops the cached background, as a container's own Invalidate does (TTyPanel). }
    procedure Invalidate; override;
  published
    { Why this control exists: TyFormSurface is the content host of a TTyForm — the panel every
      control on the form lives on.

      A borderless, resizable window cannot paint its own outermost pixels: the compositor gives it a
      backing surface smaller than the window, which leaves an unpainted band along the right and
      bottom edges. A CHILD window has no such limit and paints edge to edge, so TTyForm renders its
      themed background onto this surface instead of onto itself.

      Your controls must live on the surface. Graphic (windowless) controls such as TTyLabel paint
      onto their parent, so one placed directly on the form is hidden behind the surface.

      Keep exactly one surface per form, leave it filling the form, and do not delete it.

      (This comment is what the Object Inspector shows in its description pane, so it is written for
      the user and mirrors the '...' dialog text in tyControls.Design / rsDtSurfacePurposeText.) }
    property Purpose: string read GetPurpose;
    { A "custom" base (TTyCustomControl) does not publish these; the container needs them published so
      a streamed `object Surface` can carry `Align = alClient`. All three are HIDDEN in the Object
      Inspector by the design-time package (see tyControls.Design) — published for streaming only. }
    property Align;
    property Anchors;
    property Visible;
  end;

implementation

uses
  BGRABitmap, BGRABitmapTypes, tyControls.Painter,
  tyControls.Form;   // TTyForm (implementation-section cycle with Form.pas, legal)

constructor TTyFormSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];   // it hosts the form's controls (drop target)
end;

destructor TTyFormSurface.Destroy;
begin
  FBgCache.Free;
  inherited Destroy;
end;

procedure TTyFormSurface.Invalidate;
begin
  if FBgCache <> nil then FBgCache.Drop;
  inherited Invalidate;
end;

function TTyFormSurface.GetPurpose: string;
begin
  Result := rsTySurfacePurpose;   // one-liner in the OI; the '...' editor explains the full why
end;

function TTyFormSurface.GetStyleTypeKey: string;
begin
  // The surface has NO CSS of its own — it renders the owner form's `form` background (see Paint),
  // and hosts controls that resolve their own styles. A neutral key means no accidental TyForm
  // padding/border is applied to the surface's own layout.
  Result := 'TyFormSurface';
end;

procedure TTyFormSurface.Paint;
var
  frm: TCustomForm;
begin
  // Delegate the themed `form` background to the owning form (keeps controller + backdrop/glass in
  // one place); we paint it onto OUR canvas, which — being a child window — reaches the true edge
  // and thus covers the form's dead band.
  frm := GetParentForm(Self);
  if frm is TTyForm then
  begin
    TTyForm(frm).EnsureBackdrop;                         // keep the glass backdrop snapshot current
    PaintFormBackground(frm, Canvas);                    // themed `form` bg -> covers the dead band
  end
  else
    inherited Paint;
end;

{ THE FORM'S BACKGROUND IS RENDERED ONCE PER LOOK.
  A windowless control's repaint damages its parent, and for every control placed on a form
  the parent is this surface: a spinner turning on a 1200 x 800 form re-rendered the whole
  form background for every frame: 14 ms each, most of it laying the bitmap down with its
  transparency, which reads the canvas back to blend. This is TTyPanel's cache
  (TTyPaintCache) with one addition. A panel's look changes only through its own
  Invalidate; this surface paints the FORM's look, which also changes with what the form
  holds -- its StyleOverride, Color, PPI, the controller's theme -- and a change there need
  not reach the surface's Invalidate: one made on the controller's Model directly bumps the
  theme version and tells no control, and the direct path still showed it on the next
  paint. So the form's BackgroundCacheKey is compared on every paint, and a different key
  drops the cache.

  Only a background every pixel of which is opaque is kept: the cache is an opaque bitmap,
  and a translucent one (a glass theme letting the window behind show) is composited onto
  whatever the window holds, which a snapshot cannot reproduce -- that is rendered every
  time, as it always was. A kept background is the same bytes the direct path lays down: an
  opaque pixel drawn with transparency replaces the one under it. }
procedure TTyFormSurface.PaintFormBackground(AForm: TCustomForm; ACanvas: TCanvas);
var
  frm: TTyForm;
  w, h: Integer;
  key: string;
  bmp: TBGRABitmap;
  themed: Boolean;
begin
  frm := AForm as TTyForm;
  w := ClientWidth;
  h := ClientHeight;
  { The designer repaints rarely and streams while it does, so cache only at run time. }
  if (csDesigning in ComponentState) or (w <= 0) or (h <= 0) then
  begin
    frm.RenderBackgroundTo(ACanvas, ClientRect);
    Exit;
  end;
  key := frm.BackgroundCacheKey;
  if FBgCache = nil then FBgCache := TTyPaintCache.Create;
  if key <> FBgKey then
  begin
    FBgCache.Drop;
    FBgKey := key;
  end;
  if FBgCache.NeedsRender(w, h) then
  begin
    Inc(FBgRenders);
    bmp := TBGRABitmap.Create(w, h, BGRAPixelTransparent);
    try
      themed := frm.PaintBackgroundInto(bmp);
      if themed and TyBitmapIsOpaque(bmp) then
        bmp.Draw(FBgCache.Canvas, 0, 0, True)
      else
      begin
        FBgCache.Drop;   // nothing to keep: this frame is painted the way every frame was
        if themed then
          bmp.Draw(ACanvas, 0, 0, False)
        else
          frm.RenderBackgroundTo(ACanvas, ClientRect);
        Exit;
      end;
    finally
      bmp.Free;
    end;
  end;
  FBgCache.Blit(ACanvas);
end;

initialization
  // Register for streaming so a .lfm `object Surface: TTyFormSurface` resolves. Not on the component
  // palette (no RegisterComponents) — it is placed by the "TyControls Form" template and hosts the
  // form's controls; users treat it as the form's client-area panel.
  RegisterClass(TTyFormSurface);

end.
