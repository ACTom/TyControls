unit tyControls.TabSheet;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, ImgList, LCLType, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.TabStrip,
  tyControls.ImageDraw;
type
  { One page of a TTyPageControl. A themed background surface that hosts dropped
    controls. Its Caption is the TAB label (drawn by the host header), NOT painted
    on the page body. The design-time ControlStyle flags mirror Lazarus TTabSheet so
    the IDE treats it as a fixed, droppable, hide-on-inactive design surface. }
  TTyTabSheet = class(TTyCustomControl)
  protected
    { protected, not private: a test drives the invalidation rule through it. }
    FPaintCache: TTyPaintCache;
  private
    FOnShow: TNotifyEvent;
    FOnHide: TNotifyEvent;
    FImageIndex: Integer;         // last written BY index; a fallback view (see ImageIndex)
    FImageName: string;           // the durable icon key, resolved against the pager's Images
    FImageIndexPending: Boolean;  // an ImageIndex write not yet turned into a name (no pager list)
    function  GetPageControl: TTyCustomTabStrip;
    procedure SetPageControl(AValue: TTyCustomTabStrip);
    function  GetPageIndex: Integer;
    procedure SetPageIndex(AValue: Integer);
    function  GetImageIndex: Integer;
    procedure SetImageIndex(AValue: Integer);
    procedure SetImageName(const AValue: string);
    function  ImageIndexIsStored: Boolean;
    function  OwnerImages: TCustomImageList;
  protected
    { Repaint when Caption/Text changes -- the LCL hook that replaces our old setter. }
    procedure TextChanged; override;
    procedure SetParent(AParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { The pager switches pages by toggling Visible, so this message IS the page's
      activation edge -- the same hook TCustomPage fires OnShow/OnHide from
      (C:/lazarus/lcl/include/custompage.inc:150-157). }
    procedure CMVisibleChanged(var Message: TLMessage); message CM_VISIBLECHANGED;
    procedure DoShow; virtual;
    procedure DoHide; virtual;
  public
    destructor Destroy; override;
    procedure Invalidate; override;
    constructor Create(AOwner: TComponent); override;
    { Re-resolve a pending ImageIndex into a name against the pager's list. Called when the page
      joins a pager and by TTyPageControl.DoImagesChanged when the pager's Images changes. Public
      because the pager lives in another unit and is not a descendant. Idempotent and cheap. }
    procedure ResolveImageIndex;
    { The pager this page belongs to, READ/WRITE -- assigning it moves the page to another
      pager, exactly as TTabSheet.PageControl does (comctrls.pp:530). Reading it used to mean
      reading Parent and hard-casting, which compiles for any parent at all and only fails at
      run time.

      Typed TTyCustomTabStrip and not TTyPageControl on purpose, and it is the unit graph
      that decides: tyControls.PageControl's INTERFACE needs TTyTabSheet (its page array,
      AddPage's result), so the concrete pager type cannot appear in this unit's interface
      without a circular interface-uses. The strip base is the closest type that says
      "a tab host" at compile time; page-level members still need the cast this property
      cannot give. }
    property PageControl: TTyCustomTabStrip read GetPageControl write SetPageControl;
  published
    { Caption is TControl's, not a second string of our own.

      It used to be a field-backed property shadowing TControl.Caption, so a control had
      TWO captions: `P.Caption := 'x'` set ours and left TControl.Text empty, while
      anything reading Text -- an action link, an accessibility query, TControl's own
      csSetCaption wiring, generic code that walks TControl -- saw ''. On LCL these are one
      string: Caption IS Text, routed through RealSetText, and a repaint is arranged by
      overriding TextChanged. That is what this does now. }
    property Caption;
    { The page's position in the pager, ASSIGNABLE: writing it MOVES the page (and its tab).
      Before this, ordering could only be changed by the user dragging a tab -- the reorder
      primitive was protected and had no entry point -- so data-driven ordering (most
      recently used, sorted documents) was not expressible from code at all.

      `stored False`, as TTabSheet declares it (comctrls.pp:545): the order is already
      carried by the order the pages stream in, and storing it too would give the .lfm two
      sources of truth for one fact. }
    property PageIndex: Integer read GetPageIndex write SetPageIndex stored False;
    { The page's tab icon BY NAME -- the durable key, resolved against the PAGER's Images. When
      that list is one of ours the name outlives a reorder of the list, so the page keeps its icon
      rather than inheriting whatever slid into the old slot. '' = none; a foreign LCL list has no
      names, so there this is inert and ImageIndex is the key. }
    property ImageName: string read FImageName write SetImageName;
    { Index into the PAGER's Images list -- a VIEW of ImageName: reading resolves the name to its
      slot, writing turns the position into the name at that slot. Falls back to the last index
      written only when nothing resolves. Same name/type as TTabSheet.ImageIndex (comctrls.pp:541)
      so a ported page streams, but it streams ONLY when a name cannot capture the choice (see
      ImageIndexIsStored) -- the name is the reorder-safe state.

      The icon lives on the PAGE, not in a parallel list on the pager, for the same reason Caption
      does: reordering pages must carry the icon with the page. The pager reads it through
      GetTabImageIndex, and OnGetImageIndex still has the last word over whatever this says. }
    property ImageIndex: Integer read GetImageIndex write SetImageIndex stored ImageIndexIsStored default -1;
    { Fired when this page becomes / stops being the shown page. Per-page enter/leave logic
      (lazy content loading, validate-on-leave) previously had to be centralised in the
      pager's OnChange and dispatched with an if/case chain on the index, so a page could
      not own its own behaviour -- and a ported OnShow/OnHide handler had nothing to bind
      to. Same names, same signature and same firing edge as TCustomPage's. }
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnHide: TNotifyEvent read FOnHide write FOnHide;
    { All six redeclared `stored False`, as TCustomPage does (comctrls.pp:270-275). The pager
      owns every one of them: the constructor forces Align := alClient and Visible := False,
      and the host rewrites Visible on every page switch. Streamed, they made each page write
      a Visible = False plus a set of bounds that the align engine overwrites on load -- .lfm
      noise that re-churned the diff on every designer visit, and a persisted Visible = False
      whose undoing depended on Loaded running rather than on never having been written.
      Writing only; a .lfm that already carries them still reads them. }
    property Left stored False;
    property Top stored False;
    property Width stored False;
    property Height stored False;
    property TabOrder stored False;
    property Visible stored False;
    property StyleClass;
    property Controller;
  end;

implementation

uses
  tyControls.PageControl;   // for TTyPageControl in SetParent (one-way: impl only)

constructor TTyTabSheet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds,
    csNoDesignVisible, csNoFocus];
  FImageIndex := -1;
  Align := alClient;
  Visible := False;
end;

{ The icon is measured INTO the tab header's width, so changing it re-lays the strip --
  the same reason TextChanged invalidates the host rather than the page. }
function TTyTabSheet.OwnerImages: TCustomImageList;
var pager: TTyCustomTabStrip;
begin
  pager := GetPageControl;
  if pager <> nil then Result := pager.Images else Result := nil;
end;

function TTyTabSheet.GetImageIndex: Integer;
var n: Integer;
begin
  // DERIVED from the name whenever it resolves against the pager's list; otherwise the last
  // index written -- so "set the name, read the index" and its inverse agree with no precedence.
  if FImageName <> '' then
  begin
    n := TyImageIndexOfName(OwnerImages, FImageName);
    if n >= 0 then Exit(n);
  end;
  Result := FImageIndex;
end;

procedure TTyTabSheet.SetImageIndex(AValue: Integer);
begin
  if AValue < -1 then AValue := -1;   // one "no icon" value, not a range of them
  FImageIndex := AValue;
  // Mark FIRST: the request stands whether or not the pager has a list yet; marking it only when
  // it can be served is how a streamed ImageIndex would vanish before the page has a pager.
  FImageIndexPending := True;
  ResolveImageIndex;
  if Parent <> nil then Parent.Invalidate;
end;

procedure TTyTabSheet.SetImageName(const AValue: string);
begin
  if FImageName = AValue then Exit;
  FImageName := AValue;
  if Parent <> nil then Parent.Invalidate;
end;

procedure TTyTabSheet.ResolveImageIndex;
begin
  if not FImageIndexPending then Exit;   // nothing outstanding: never touch a set ImageName
  if OwnerImages = nil then Exit;        // no pager list yet; a later attach / SetImages retries
  FImageIndexPending := False;
  if FImageIndex < 0 then
    SetImageName('')                     // an explicit -1 clears the icon
  else
    SetImageName(TyImageNameOfIndex(OwnerImages, FImageIndex));  // '' foreign list / past end
end;

function TTyTabSheet.ImageIndexIsStored: Boolean;
begin
  // The NAME is the durable state; the index streams only as the fallback a name cannot hold.
  // See TTyImage.ImageIndexIsStored for the full reasoning.
  Result := (FImageName = '') and (FImageIndex >= 0);
end;

function TTyTabSheet.GetStyleTypeKey: string;
begin
  Result := 'TyTabSheet';
end;

procedure TTyTabSheet.TextChanged;
begin
  inherited TextChanged;
  { The tab LABEL changed, so it is the host header that has to re-lay, not us. }
  if Parent <> nil then
    Parent.Invalidate;
end;

procedure TTyTabSheet.SetParent(AParent: TWinControl);
var
  Old: TWinControl;
begin
  Old := Parent;
  inherited SetParent(AParent);
  { LEAVING a pager is as much a page-list event as joining one, and only the joining half
    was wired: un-registration hung off Notification(opRemove), which fires when a page is
    freed, not when it is re-parented. So moving a page to a second pager left it counted,
    tabbed and handed out by BOTH -- the old one drew a tab for a control that was no longer
    inside it. Skipped while either side is being torn down: Notification already covers the
    free path, and the old host may be half-destroyed by then. }
  if (Old <> AParent) and (Old is TTyPageControl)
     and not (csDestroying in ComponentState)
     and not (csDestroying in Old.ComponentState) then
    TTyPageControl(Old).UnregisterPage(Self, False);
  { Register with the hosting page control. Fires for AddPage (Parent := PC), for a
    designer drop onto a page control, and for a streamed load when the Parent
    property is applied — so the page list is rebuilt uniformly in all paths. }
  if (AParent <> nil) and (AParent is TTyPageControl) then
    TTyPageControl(AParent).RegisterPage(Self);
  { Now that the page has a pager (and thus a list to resolve against), a streamed-but-pending
    ImageIndex can become its durable name. Harmless when nothing is pending. }
  ResolveImageIndex;
end;

function TTyTabSheet.GetPageControl: TTyCustomTabStrip;
begin
  if Parent is TTyCustomTabStrip then Result := TTyCustomTabStrip(Parent) else Result := nil;
end;

procedure TTyTabSheet.SetPageControl(AValue: TTyCustomTabStrip);
begin
  if GetPageControl = AValue then Exit;
  { Parent, not a private list edit: SetParent is what un-registers from the old pager and
    self-registers with the new one, so routing through it keeps the ONE registration path
    every other route already uses. }
  Parent := AValue;
end;

function TTyTabSheet.GetPageIndex: Integer;
var
  Host: TTyPageControl;
  I: Integer;
begin
  Result := -1;
  if not (Parent is TTyPageControl) then Exit;
  Host := TTyPageControl(Parent);
  for I := 0 to Host.PageCount - 1 do
    if Host.Pages[I] = Self then Exit(I);
end;

procedure TTyTabSheet.SetPageIndex(AValue: Integer);
var
  Cur: Integer;
begin
  if not (Parent is TTyPageControl) then Exit;
  Cur := GetPageIndex;
  if (Cur < 0) or (Cur = AValue) then Exit;
  TTyPageControl(Parent).MovePage(Cur, AValue);   // clamps, re-syncs the shown page, repaints
end;

procedure TTyTabSheet.CMVisibleChanged(var Message: TLMessage);
begin
  inherited;
  if Visible then DoShow else DoHide;
end;

procedure TTyTabSheet.DoShow;
begin
  if Assigned(FOnShow) then FOnShow(Self);
end;

procedure TTyTabSheet.DoHide;
begin
  if Assigned(FOnHide) then FOnHide(Self);
end;

procedure TTyTabSheet.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, R, S);   // themed background only — no caption text on the body
    P.EndPaint;
  finally
    P.Free;
  end;
end;

destructor TTyTabSheet.Destroy;
begin
  FPaintCache.Free;
  inherited Destroy;
end;

procedure TTyTabSheet.Invalidate;
begin
  { The one thing the cache keys on: our OWN look changed. A child's damage never reaches
    here, which is exactly why the cache survives it. }
  if FPaintCache <> nil then FPaintCache.Drop;
  inherited Invalidate;
end;

procedure TTyTabSheet.Paint;
var
  w, h: Integer;
begin
  { The designer repaints rarely and streams while it does, so cache only at runtime. }
  if csDesigning in ComponentState then
  begin
      RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  w := ClientWidth; h := ClientHeight;
  if (w <= 0) or (h <= 0) then Exit;
  if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
  if FPaintCache.NeedsRender(w, h) then
    RenderTo(FPaintCache.Canvas, Rect(0, 0, w, h), Font.PixelsPerInch);
  FPaintCache.Blit(Canvas);
end;


initialization
  { Runtime LFM streaming resolves nested (non-field) page objects via the class
    registry; register so a saved form's pages load (mirrors TTyTitleBar in Form.pas). }
  RegisterClass(TTyTabSheet);
end.
