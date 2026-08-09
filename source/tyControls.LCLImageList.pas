unit tyControls.LCLImageList;
{$mode objfpc}{$H+}

{ The bridge: this library's icons, in a shape stock LCL controls can consume.

  WHY A BRIDGE AND NOT A BASE CLASS. Making TTyVirtualImageList descend from TCustomImageList
  looks like the obvious move and does not work. LCL has no "give me item N at size S" paint-time
  hook: Count is not overridable (a non-virtual property over a private field, written only by
  private methods) and every consumer gates on it; TScaledImageListResolution.Draw falls through
  to a NON-virtual StretchDraw whenever the canvas scale factor is not 1, so an override silently
  stops applying on a hi-DPI Cocoa/Qt canvas; and many consumers never call Draw at all -- a
  TListView hands the native HIMAGELIST to LVM_SETIMAGELIST, a TMenuItem calls the non-virtual
  GetBitmap. Reparenting would also drop the published Version that every registered component
  here carries, since TCustomImageList publishes nothing at all. The repo had already recorded
  that question as overruled (plans/2026-07-30-control-parity-inventory.md).

  What DOES work is what LCL does for its own icons: TLCLGlyphs descends from TCustomImageList
  and materialises real rasters, at widths registered up front. This is that, fed from a
  TTyVirtualImageList -- which is already the seam, already ordered and indexed, and already
  resolves a name to either a raster collection or an icon font.

  THE COST, SAID PLAINLY: icons are baked at the registered widths rather than rendered at the
  exact size asked for. That is the price LCL's interface charges, and it is why this is a
  SEPARATE component instead of a change to the ones the library's own controls use -- those
  keep negotiating size at paint time.

  The library already needed this twice and hand-rolled it both times: TTyShellTreeView owns a
  private TImageList it fills from a TTyImageCollection at a hardcoded 16px with hand-written
  index constants, and TTyMenu carries an LCLImages row path. }

interface

uses
  Classes, SysUtils, Types, Math, LCLType, LCLIntf, Graphics, ImgList, Controls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.ImageCollection;

type
  { Feeds a TCustomImageList from a TTyVirtualImageList.

    Index i here is index i in Source.Names, ALWAYS -- a name that resolves to nothing still
    takes its slot, as a blank transparent image. Consumers address icons by ImageIndex and
    several of this library's own controls carry hand-written index constants; a fill that
    skipped a bad name would renumber everything after it. }
  TTyLCLImageList = class(TCustomImageList)
  private
    FSource: TTyVirtualImageList;
    FImageWidth: Integer;        // LOGICAL px at 96 PPI
    FMultiResolution: Boolean;
    FFilling: Boolean;
    FFillCount: Integer;
    procedure SetSource(AValue: TTyVirtualImageList);
    procedure SetImageWidth(AValue: Integer);
    procedure SetMultiResolution(AValue: Boolean);
    procedure SourceChanged(Sender: TObject);
    procedure ApplySize;
    function GetVersion: string;
  protected
    procedure Loaded; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { The pixel blob suppression, and NOT via DefineProperties.
      TComponent.DefineProperties is where a non-visual component's designer Left/Top live, and
      Pascal cannot skip one level of an inherited chain -- an empty override kills the icon
      position on the form surface along with the blob (measured: the component streams with no
      Left and no Top, so every reopen snaps it back to 0,0). These four are public virtuals for
      exactly this, and the residue is a two-byte `Bitmap = { }`.
      Suppressing it at all matters because the blob would be STALE: rasters baked on whatever
      machine the form was last saved on, at that machine's DPI, then thrown away and rebuilt on
      load anyway. }
    procedure WriteData(AStream: TStream); override;
    procedure ReadData(AStream: TStream); override;
    procedure WriteAdvData(AStream: TStream); override;
    procedure ReadAdvData(AStream: TStream); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Re-render every slot from Source. Called for you on load, on a property change, when the
      source changes and (when a colour token is in play) on a theme change -- so an explicit
      call is only for a source this component cannot observe. }
    procedure Refill;
    { How many times a fill has actually run. A test seam, and the honest way to assert that a
      trigger fired: asserting on Count cannot tell a refill from no refill. }
    property FillCount: Integer read FFillCount;
  published
    { The icons. Nil empties the list. }
    property Source: TTyVirtualImageList read FSource write SetSource;
    { The base edge in LOGICAL px at 96 PPI. Writing it re-registers the widths and refills --
      and note that LCL's inherited Width/Height, which stay public, CLEAR the list when
      written; use this instead. }
    property ImageWidth: Integer read FImageWidth write SetImageWidth default 16;
    { Bake the 1.5x / 2x / 3x variants as well, so Scaled picks a crisp one per monitor instead
      of upscaling the base. On by default because it is what a hi-DPI user needs and the cost
      is a few small bitmaps per icon.

      Turn it OFF when the consumer cannot use it. TTyTreeView is the notable one: it paints
      through Images.Draw, which routes to GetResolution(FWidth), and lays out on Images.Height
      -- so it only ever pulls the base width, and the other three are rendered for nothing.
      TTyMenu does pull a resolution (ResolutionForPPI), and stock LCL controls generally do. }
    property MultiResolution: Boolean read FMultiResolution write SetMultiResolution default True;
    { Every component in this library reports the library version; TCustomImageList publishes
      nothing, so it is re-declared here (test.version enforces this on every registered class). }
    property Version: string read GetVersion stored False;
  end;

implementation

{ TTyLCLImageList }

constructor TTyLCLImageList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FImageWidth := 16;
  FMultiResolution := True;
  { Scaled tells LCL it may pick a registered resolution per monitor instead of stretching the
    base one. Same line TLCLGlyphs opens with. }
  Scaled := True;
end;

destructor TTyLCLImageList.Destroy;
begin
  if FSource <> nil then
    FSource.RemoveHandlerOnChange(@SourceChanged);
  inherited Destroy;
end;

function TTyLCLImageList.GetVersion: string;
begin
  Result := TyVersion;
end;

procedure TTyLCLImageList.WriteData(AStream: TStream);
begin
  // Deliberately empty -- see the declaration.
end;

procedure TTyLCLImageList.WriteAdvData(AStream: TStream);
begin
  // Deliberately empty.
end;

procedure TTyLCLImageList.ReadData(AStream: TStream);
begin
  { A blob from an .lfm written by an older build (or by hand) is read and discarded: it is
    stale by construction, and Loaded refills from Source a moment later. Consuming the stream
    rather than raising is what keeps such a form loadable. }
  if AStream <> nil then AStream.Seek(0, soEnd);
end;

procedure TTyLCLImageList.ReadAdvData(AStream: TStream);
begin
  if AStream <> nil then AStream.Seek(0, soEnd);
end;

procedure TTyLCLImageList.SetSource(AValue: TTyVirtualImageList);
begin
  if FSource = AValue then Exit;
  if FSource <> nil then
  begin
    FSource.RemoveHandlerOnChange(@SourceChanged);
    FSource.RemoveFreeNotification(Self);
  end;
  FSource := AValue;
  if FSource <> nil then
  begin
    FSource.FreeNotification(Self);
    FSource.AddHandlerOnChange(@SourceChanged);
  end;
  Refill;
end;

procedure TTyLCLImageList.SetImageWidth(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FImageWidth = AValue then Exit;
  FImageWidth := AValue;
  Refill;
end;

procedure TTyLCLImageList.SetMultiResolution(AValue: Boolean);
begin
  if FMultiResolution = AValue then Exit;
  FMultiResolution := AValue;
  Refill;
end;

procedure TTyLCLImageList.SourceChanged(Sender: TObject);
begin
  Refill;
end;

procedure TTyLCLImageList.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSource) then
  begin
    { No RemoveHandlerOnChange here -- the source is already going away, and reaching into it
      during its own destruction is how a use-after-free starts. }
    FSource := nil;
    Refill;
  end;
end;

procedure TTyLCLImageList.Loaded;
begin
  inherited Loaded;
  { Not the constructor: at construction the .lfm has not delivered Source or ImageWidth yet,
    and the theme is not resolved. TTyShellTreeView documents the same ordering trap. }
  Refill;
end;

procedure TTyLCLImageList.ApplySize;
var
  w: Integer;
begin
  w := FImageWidth;
  if w < 1 then w := 1;
  { SetWidthHeight CLEARS the list. Harmless here and only here, because Refill calls this
    before it adds anything. }
  SetWidthHeight(w, w);
  if FMultiResolution then
    { The four widths LCL's own 100/125/150/175/200/300% buckets resolve to. Above 300% it
      upscales from the largest, which is the documented limit of this interface. }
    RegisterResolutions([w, MulDiv(w, 3, 2), w * 2, w * 3])
  else
    RegisterResolutions([w]);
end;

procedure TTyLCLImageList.Refill;
var
  widths: array of Integer;
  i, k, w: Integer;
  src: TBGRABitmap;
  bmp: TBitmap;
begin
  { A refill can be triggered from a setter that a fill itself provokes (Clear -> Change ->
    a listener -> Refill); without this the first theme change would recurse. }
  if FFilling then Exit;
  if csLoading in ComponentState then Exit;
  FFilling := True;
  try
    Clear;
    ApplySize;
    if (FSource = nil) or (FSource.Count = 0) then Exit;

    w := FImageWidth;
    if w < 1 then w := 1;
    if FMultiResolution then
    begin
      SetLength(widths, 4);
      widths[0] := w; widths[1] := MulDiv(w, 3, 2); widths[2] := w * 2; widths[3] := w * 3;
    end
    else
    begin
      SetLength(widths, 1);
      widths[0] := w;
    end;

    { Ink comes from the source, as authored -- icon-font glyphs take Source.GlyphColor and
      raster images carry their own. There is deliberately no theme token here: the bridge does
      not know which surface its icons will be drawn on, so it cannot resolve one honestly, and
      guessing would be worse than letting the application say. A dark theme sets
      Source.GlyphColor, the same as it does for the library's own consumers. }
    for i := 0 to FSource.Count - 1 do
        for k := 0 to High(widths) do
        begin
          { RenderIndex never returns nil and always returns the requested square, so an
            unresolvable name lands as a blank slot and index i stays index i. }
          src := FSource.RenderIndex(i, widths[k]);
          try
            bmp := src.Bitmap;      { owned by src -- do NOT free separately }
            if k = 0 then
              AddSlice(bmp, Rect(0, 0, bmp.Width, bmp.Height))
            else
              ReplaceSliceCentered(i, widths[k], bmp, False);
          finally
            src.Free;
          end;
      end;
    Inc(FFillCount);
    { Change alone early-exits unless something marked the list dirty first; both, in this
      order, is what makes consumers repaint. }
    MarkAsChanged;
    Change;
  finally
    FFilling := False;
  end;
end;

initialization
  { Same reason TTyImageCollection registers itself: a component the designer may have to
    serialize and paste back (undo) must be findable by name. }
  RegisterClass(TTyLCLImageList);

end.
