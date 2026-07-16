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
  Classes, Controls, tyControls.Base, tyControls.StrConsts;

type
  TTyFormSurface = class(TTyCustomControl)
  private
    function GetPurpose: string;
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
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
  Forms, tyControls.Form;   // GetParentForm + TTyForm (implementation-section cycle with Form.pas, legal)

constructor TTyFormSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls];   // it hosts the form's controls (drop target)
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
    TTyForm(frm).RenderBackgroundTo(Canvas, ClientRect); // themed `form` bg -> covers the dead band
  end
  else
    inherited Paint;
end;

initialization
  // Register for streaming so a .lfm `object Surface: TTyFormSurface` resolves. Not on the component
  // palette (no RegisterComponents) — it is placed by the "TyControls Form" template and hosts the
  // form's controls; users treat it as the form's client-area panel.
  RegisterClass(TTyFormSurface);

end.
