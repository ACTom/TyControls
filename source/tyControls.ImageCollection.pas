unit tyControls.ImageCollection;
{$mode objfpc}{$H+}

{ TTyImageCollection + TTyVirtualImageList — the RASTER companion to the icon
  font (tyControls.IconFont / tyControls.GlyphImageList).

  TTyImageCollection is a DPI-aware NAMED raster image store. You Add named
  images from a TBGRABitmap or a TPicture; the collection keeps each as one or
  more master bitmaps. Consumers then ask for a name at a target PIXEL size and
  get a bitmap scaled to that size (aspect preserved, centered on a transparent
  square) — so one master serves every DPI without the caller juggling per-size
  raster sets, and where several masters are authored for a name the closest one
  is picked before scaling. It is a plain non-visual TComponent; headless-safe,
  no timers. It complements the vector icon font: photos / true-colour PNGs live
  here, monochrome scalable glyphs live in the icon font.

  §STORAGE / .lfm — the masters live in the published `Images` collection, and
  that collection IS the store: each TTyImageItem holds its pixels as a PNG in
  `PngBase64`, and the decoded TBGRABitmap hanging off it is a derived cache.
  So images dropped in at design time are saved into the .lfm and come back at
  run time, which is the whole point — before this the pixels lived only in a
  private TStringList and nothing survived a save.

  Why base64-PNG text and not LCL's binary blob. TCustomImageList streams its
  pixels through DefineProperties (imglist.pp:314) as an opaque `Bitmap`/`Data`
  hex run. We deliberately do not, for the same reason TTyTreeView's Items does
  not (commit a8d98b7): a pseudo-property is INVISIBLE TO THE IDE. Lazarus's LFM
  checker resolves every identifier in a .lfm against the class's published RTTI,
  and DefineProperties adds no RTTI — so the IDE rejects the whole form with
  "identifier Data not found in class ..." and offers to strip it. This library
  has already been bitten: examples/demo/mainform.pas builds its NATIVE LCL tree
  in code, with a comment saying exactly that, because the streamed form would
  not open. Every property in this unit's streaming path is therefore a real
  published property with real RTTI, and nothing anywhere calls DefineProperties.
  The cost is size — base64 is 4/3 of the PNG, and an icon set is not three tree
  nodes — and the gain is a form that opens, an item-level diff that shows WHICH
  icon changed, and the stock collection editor for free.

  §MULTI-RESOLUTION — a name may appear on SEVERAL items, each a master authored
  at a different size; the format is identical whether a name has one master or
  five, so nothing about the .lfm changes when a second resolution is added. At
  render time GetBitmap picks the smallest master that is still at least the
  requested size (falling back to the largest available), then scales THAT. This
  is what makes a HiDPI render sharp: a 32px request against a 16px and a 48px
  master downsamples the 48 rather than doubling the 16. `Count` counts distinct
  NAMES, not masters — Images.Count is the master count.

  Scaled renders are CACHED per (name, sizePx), bounded by CacheCapacity with LRU
  eviction, and invalidated whenever ChangeStamp changes (every mutation bumps it). Two
  accessors sit on that cache:
    * GetBitmap       — a caller-OWNED copy. Free it; mutating it (e.g. tinting via
                        TyTintBitmapAlpha) is safe and cannot reach the cache.
    * GetCachedBitmap — a BORROWED reference. Never free it, never mutate it, don't
                        hold it across another call. Allocation-free, so this is the
                        one paint code should use to blit an icon.
  Neither is thread-safe; both assume the LCL main thread, like the controls that
  consume them.

  TTyVirtualImageList is an ordered list that REFERENCES a TTyImageCollection
  and exposes a subset of its images (by name), rendering / drawing any item on
  demand at the consumer's target pixel size. It mirrors TTyGlyphImageList's
  shape exactly, but sourced from a raster collection instead of an icon font.
  A FreeNotification nils the reference automatically if the collection is freed
  first. Because both render on demand rather than caching a fixed-resolution
  set, they are plain TComponents with Draw methods, not TCustomImageList
  descendants — the ty-controls custom-drawn controls consume these, not LCL's
  native TImageList. }

interface

uses
  Classes, SysUtils, Graphics, base64, LazMethodList, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Component, tyControls.IconFont;

{ Recolor a BGRA icon bitmap's RGB to AColor while KEEPING its alpha (antialiased edges
  included), so an icon authored as an opaque alpha mask takes on any theme text color.
  In-place; a nil / empty bitmap is a no-op. }
procedure TyTintBitmapAlpha(ABmp: TBGRABitmap; AColor: TTyColor);

{ The .lfm payload codec, exported because the design-time editor encodes with it and
  because a round trip is only assertable if both halves are reachable from a test.
  Both are BGRA-native (SaveToStreamAsPng / LoadFromStream) and neither touches TPicture
  — see the black-bitmap note on TTyImageItem.

  Encode ABmp as a base64 PNG; '' for a nil / empty bitmap. }
function TyBitmapToPngBase64(ABmp: TBGRABitmap): string;
{ Decode a base64 PNG into a NEW caller-owned bitmap; nil when AText is empty or does
  not decode. Never raises — a mangled .lfm payload must not stop a form from loading. }
function TyPngBase64ToBitmap(const AText: string): TBGRABitmap;

const
  { Default number of (name, sizePx) renders the collection keeps alive. Icons are
    small (16-48px is the norm), so this bounds a few hundred KB; a control that
    walks many sizes evicts rather than growing without limit. }
  TyImageCacheDefaultCapacity = 64;

type
  TTyImageCollection = class;

  { ONE authored master: a name plus its pixels, held as a base64-encoded PNG.
    PngBase64 is the single source of truth — Master is decoded FROM it and
    cached, never the other way round, so what a running program draws is
    byte-for-byte what a save would write. (Seeding the decoded bitmap straight
    from the caller's TBGRABitmap would be faster and would let in-memory and
    post-load pixels drift apart if the codec were ever not an identity; one
    source of truth costs an encode+decode per Add, which is not a hot path.) }
  TTyImageItem = class(TCollectionItem)
  private
    FImageName: string;
    FPngBase64: string;
    FMaster: TBGRABitmap;   // owned; decoded from FPngBase64 on demand, nil until then
    FDecoded: Boolean;      // True once decoding has been ATTEMPTED (success or not)
    procedure SetImageName(const AValue: string);
    procedure SetPngBase64(const AValue: string);
    procedure DropDecoded;
    function GetMaster: TBGRABitmap;
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(ACollection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(ASource: TPersistent); override;

    { Replace this master's pixels from ABmp. A PNG copy is encoded, so the caller
      keeps ownership of theirs. A nil / empty ABmp clears the payload. }
    procedure SetBitmap(ABmp: TBGRABitmap);

    { The decoded master — a BORROWED reference owned by this item. nil when the
      payload is empty OR could not be decoded. Do not free it; it dies with the
      item or when PngBase64 is reassigned. }
    property Master: TBGRABitmap read GetMaster;

    { A pure query: True when PngBase64 is non-empty AND decodes to a usable bitmap.
      It is False for BOTH "empty" and "corrupt" — so it does not separate them on its
      own; the PAIR does. `PngBase64 <> ''` with IsDecodable False means a MANGLED
      payload (a .lfm whose base64 a bad merge or a hand edit broke), which renders as
      a blank square rather than raising and is otherwise completely invisible. Master
      cannot be used for this: it returns nil in both cases. Decodes on first call. }
    function IsDecodable: Boolean;

    { Master's edge in pixels — Max(Width, Height), which is what the resolution
      pick compares. 0 when there is no usable master. }
    function MasterSize: Integer;
  published
    { The image key. NOT unique: several items may share a name, one per authored
      resolution (see §MULTI-RESOLUTION). Case-sensitive, like every lookup here. }
    property ImageName: string read FImageName write SetImageName;
    { The master's pixels: a PNG, base64-encoded. Readable and diffable in the
      .lfm on purpose — see the format note in the unit header. }
    property PngBase64: string read FPngBase64 write SetPngBase64;
  end;

  { The masters. Order is authoring order; Count is the number of MASTERS, which
    is only the number of images when every name has exactly one. }
  TTyImageItems = class(TCollection)
  private
    FOwner: TTyImageCollection;
    function GetItem(AIndex: Integer): TTyImageItem;
    procedure SetItem(AIndex: Integer; AValue: TTyImageItem);
  protected
    function GetOwner: TPersistent; override;
    { Both funnel into the owner's Changed, so ANY route into the store — the
      Object Inspector, the .lfm reader, Add/Clear, a direct Items[i].PngBase64 —
      invalidates the render cache and the name index. }
    procedure Notify(AItem: TCollectionItem; AAction: TCollectionNotification); override;
    procedure Update(AItem: TCollectionItem); override;
  public
    constructor Create(AOwner: TTyImageCollection);
    function Add: TTyImageItem;
    property Items[AIndex: Integer]: TTyImageItem read GetItem write SetItem; default;
  end;

  { Internal wrapper: owns one scaled render plus its LRU stamp. }
  TTyImageCacheEntry = class(TObject)
  private
    FBmp: TBGRABitmap;   // owned; the master scaled to one (name, sizePx)
    FTick: Int64;        // last-used stamp; the smallest is evicted first
  public
    constructor Create(AOwnedBmp: TBGRABitmap; ATick: Int64);
    destructor Destroy; override;
  end;

  TTyImageCollection = class(TTyComponent)
  private
    FImages: TTyImageItems;   // THE store: every master, streamed to the .lfm
    FNames: TStringList;      // distinct names in first-appearance order; lazy
    FNamesStamp: Cardinal;    // the FChangeStamp FNames was built at
    FChangeStamp: Cardinal;   // bumped by every mutation; see Changed
    FCache: TStringList;   // 'name'#1'sizePx' -> TTyImageCacheEntry (OwnsObjects, Sorted)
    FCacheStamp: Cardinal;
    FCacheCapacity: Integer;
    FTick: Int64;          // monotonic LRU clock
    procedure SetImages(AValue: TTyImageItems);
    { Rebuild FNames from FImages when a mutation has staled it. }
    procedure SyncNames;
    { Delete every master carrying AName. Returns how many went. }
    function RemoveMasters(const AName: string): Integer;
    { The master to scale for (AName, ASizePx): the SMALLEST authored master whose
      edge is still >= ASizePx, else the largest available. Borrowed; nil when the
      name has no usable master. See §MULTI-RESOLUTION. }
    function PickMaster(const AName: string; ASizePx: Integer): TBGRABitmap;
    { Scale the picked master for AName into an ASizePx square. Caller owns the
      result. Assumes ASizePx >= 1. }
    function RenderMaster(const AName: string; ASizePx: Integer): TBGRABitmap;
    { The composite cache key for (AName, ASizePx). }
    class function CacheKey(const AName: string; ASizePx: Integer): string; static;
    { Drop every cached render and re-sync to the current version. }
    procedure FlushCache;
    { Drop stale renders when a mutation has bumped Version since we last looked. }
    procedure SyncCache;
    { Evict least-recently-used entries until at most AMax remain. }
    procedure TrimCacheTo(AMax: Integer);
    procedure SetCacheCapacity(AValue: Integer);
  protected
    { Invalidates the render cache (lazily, via Version). Call after any change to
      the stored masters; descendants overriding this must call inherited. }
    procedure Changed; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Add (or replace) the image AName from ABmp. Replaces EVERY master carrying
      AName, so a name added this way ends up single-resolution — that is the old
      contract and the common case. Use AddMasterBitmap to add a resolution rather
      than replace the name. The pixels are copied (encoded to PNG), so the caller
      keeps ownership of theirs. No-op when AName is '' or ABmp nil. }
    procedure AddBitmap(const AName: string; ABmp: TBGRABitmap);

    { Add ABmp as an ADDITIONAL master for AName, keeping any already there, so a
      name can carry several authored resolutions. Order does not matter: the pick
      is by size, not by position. A master whose edge equals one already stored
      REPLACES it — two masters at the same size are indistinguishable to the pick
      and would just waste .lfm. The pixels are copied. No-op when AName is '' or
      ABmp nil. }
    procedure AddMasterBitmap(const AName: string; ABmp: TBGRABitmap);

    { How many authored masters carry AName. 0 when the name is absent. }
    function MasterCount(const AName: string): Integer;
    { The edge (Max(W,H)) of the master that a request for ASizePx would scale,
      or 0 when there is nothing to draw. This is the only external way to observe
      WHICH master was picked — the rendered square is ASizePx either way, so a
      pick regression is otherwise invisible. }
    function PickedMasterSize(const AName: string; ASizePx: Integer): Integer;
    { Add (or replace) the image AName built from APicture's current graphic. The
      caller keeps ownership of APicture. No-op when AName is '' or the picture is
      empty / has no graphic. }
    procedure AddPicture(const AName: string; APicture: TPicture);
    { Drop all images (frees every master). }
    procedure Clear;

    { Number of stored images. }
    function Count: Integer;
    { The name at AIndex, or '' when AIndex is out of range. }
    function NameOf(AIndex: Integer): string;
    { Index of the (case-sensitive) name AName, or -1 when absent. }
    function IndexOf(const AName: string): Integer;
    { True when AName is stored. }
    function Contains(const AName: string): Boolean;

    { Return a NEW caller-owned bitmap: the master for AName scaled to fit an
      ASizePx square (aspect preserved, centered on a transparent background).
      Returns an empty transparent square when AName is missing (never nil, never
      raises). ASizePx <= 0 is clamped to a 1px square.

      The scale is served from the render cache, so repeated calls cost one
      allocation + copy rather than a fresh rmFineResample. The COPY is what makes
      it safe to mutate the result in place (see TyTintBitmapAlpha). When you only
      need to blit, prefer GetCachedBitmap and skip the copy entirely. }
    function GetBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;

    { The cached render of AName at ASizePx — a BORROWED reference owned by this
      collection. The caller must NOT Free it and must NOT modify its pixels; it
      stays valid until the next mutation (Version bump) or until evicted by a
      later GetCachedBitmap / CacheCapacity change, so blit it and drop it.

      Returns nil when there is nothing to draw (AName missing). Unlike GetBitmap
      this allocates nothing on a cache hit, which is the point: a repaint that
      blits N icons does no per-icon allocation and no per-icon resample.
      ASizePx <= 0 is clamped to a 1px square. }
    function GetCachedBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;

    { Number of cached (name, sizePx) renders currently held. Diagnostics / tests. }
    function CacheCount: Integer;
    { True when (AName, ASizePx) is currently cached. A pure query: unlike
      GetCachedBitmap it does NOT count as a use, so it cannot disturb the LRU
      order. Diagnostics / tests. }
    function IsCached(const AName: string; ASizePx: Integer): Boolean;

    { Bumped on every mutation (AddBitmap / AddPicture / Clear). Consumers that
      cache anything derived from this collection can compare it to detect staleness.
      Wraps at 2^32 mutations.
      Named ChangeStamp, not Version: TTyComponent publishes `Version: string` = the
      LIBRARY version, and one name carrying two unrelated meanings on the same class
      is a trap — code would read the counter while the Object Inspector showed the
      library string. (Was `Version: Cardinal` up to 2.2.x.) }
    property ChangeStamp: Cardinal read FChangeStamp;
    { Upper bound on cached renders; least-recently-used entries are evicted past
      it. Lowering it evicts immediately. Values < 1 clamp to 1 (a cap of 0 would
      evict the very entry GetCachedBitmap is about to return). Public, not
      published: it is a memory knob with no visual effect, and publishing it would
      put a number in every .lfm that nobody authored. }
    property CacheCapacity: Integer read FCacheCapacity write SetCacheCapacity;
  published
    { The masters, and the .lfm's whole picture payload. The setter looks redundant
      — nothing "assigns a collection" — but TWriter.WriteProperty SKIPS a property
      with no setter, so without it the designer would save a form with no images
      at all and no error to explain it. That exact bug shipped once here already
      (commit 7d2c03d, the grid's Columns). The reader does not use the setter:
      vaCollection goes through ReadCollection. }
    property Images: TTyImageItems read FImages write SetImages;
  end;

  TTyVirtualImageList = class(TTyComponent)
  private
    FCollection: TTyImageCollection;
    FIconFont: TTyIconFont;
    FNames: TStrings;          // ordered image NAMES to expose (a TStringList)
    FDefaultSize: Integer;
    FGlyphColor: TTyColor;
    { The borrowed-bitmap contract of CachedIndex has to hold for glyphs too, and an icon
      font has no cache of its own to borrow from -- RenderGlyph mints a new bitmap every
      call. One slot is enough for the paint loops this feeds (a toolbar draws one icon at a
      time at one size), and it keeps the promise without a second cache to invalidate. }
    FGlyphCache: TBGRABitmap;
    FGlyphCacheName: string;
    FGlyphCacheSize: Integer;
    FGlyphCacheColor: TTyColor;
    FGlyphCacheVersion: Integer;
    { Observers. This list had NO change notification of any kind, and its FNames was a bare
      TStringList with no OnChange -- so anything holding rendered copies of these icons (the
      LCL bridge is the first, but a cache in a control is the same shape) had no way to learn
      that Names, Collection or IconFont had moved under it. Multicast rather than a single
      published OnChange, and for the reason TTyEdit records: a control assigning the published
      event would silently overwrite whatever the application had put there. }
    FChangeHandlers: TMethodList;
    procedure NamesChanged(Sender: TObject);
    procedure Changed;
    procedure SetCollection(AValue: TTyImageCollection);
    procedure SetIconFont(AValue: TTyIconFont);
    procedure SetGlyphColor(AValue: TTyColor);
    procedure SetNames(AValue: TStrings);
    procedure DropGlyphCache;
    { Which source owns AIndex: the collection when it HAS the name, else the icon font when
      it has the glyph. Returns '' in ASourceName when neither does. }
    function ResolveSource(AIndex: Integer; out AName: string): Integer;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Number of exposed items (= Names.Count). }
    function Count: Integer;
    { The image name at AIndex, or '' when AIndex is out of range. }
    function NameOf(AIndex: Integer): string;
    { Index of the (case-sensitive) name AName, or -1 when absent. }
    function IndexOf(const AName: string): Integer;
    { Render item AIndex from the Collection into an ASizePx square (aspect
      preserved, centered on transparent). Caller OWNS the returned bitmap. Never
      nil: an empty transparent square when Collection is unset, AIndex is out of
      range, or the name is missing. ASizePx <= 0 is clamped to a 1px square. }
    function RenderIndex(AIndex, ASizePx: Integer): TBGRABitmap;
    { The Collection's cached render of item AIndex at ASizePx — a BORROWED
      reference: do NOT Free it, do NOT modify its pixels, and do not hold it
      across another CachedIndex call. Returns nil when there is nothing to draw
      (no Collection, AIndex out of range, or the name is missing). This is the
      allocation-free path for paint code; use RenderIndex when you need to own or
      mutate the bitmap. ASizePx <= 0 is clamped to a 1px square. }
    function CachedIndex(AIndex, ASizePx: Integer): TBGRABitmap;
    { Paint item AIndex onto ACanvas at (AX, AY) at the list's DefaultSize.

      DELIBERATELY LCL's signature, argument for argument (imglist.pp:356
      `Draw(ACanvas: TCanvas; AX, AY, AIndex: Integer; AEnabled: Boolean = True)`).
      This method used to be Draw(ACanvas, AIndex, AX, AY, ASizePx) -- LCL's NAME with
      the index and the coordinates TRANSPOSED and a size appended. Every argument is an
      Integer, so the natural port of `Images.Draw(C, X, Y, Idx)` was to add the size and
      get `Draw(C, X, Y, Idx, 16)`, which compiled and drew image number X at (Y, Idx).
      The size-carrying form still exists as DrawIndex; the 4-Integer shape no longer
      does, so the old call site fails to COMPILE rather than transposing in silence.

      AEnabled=False draws the icon DIMMED -- the cut / unavailable / disabled look.
      NOTE that it is ENABLED, not Ghosted: the two are negations of one another and
      both are Booleans, so the wrong polarity compiles cleanly and draws every icon
      disabled. That bug has already shipped once in this library. Alpha only: the icon
      keeps its colours and loses its presence, which is what "unavailable" should look
      like -- recolouring would say "different", not "faded".

      Guards every edge case (nil canvas/Collection, bad index) so it never raises. }
    procedure Draw(ACanvas: TCanvas; AX, AY, AIndex: Integer;
      AEnabled: Boolean = True);
    { The size-carrying form: (AIndex, AX, AY, ASizePx), as Draw used to be. Renamed so
      that the two orders cannot be confused -- paint code in this library needs an
      explicit pixel size (it scales with DPI and with the row height), and LCL's Draw
      has nowhere to put one. AGhosted is the NEGATION of Draw's AEnabled, kept in that
      polarity because that is what the callers upstream of it carry. }
    procedure DrawIndex(ACanvas: TCanvas; AIndex, AX, AY, ASizePx: Integer;
      AGhosted: Boolean = False);
    { Subscribe to "something about this list changed": Names, Collection, IconFont,
      DefaultSize or GlyphColor. Remove in your destructor. }
    procedure AddHandlerOnChange(const AHandler: TNotifyEvent; AsFirst: Boolean = False);
    procedure RemoveHandlerOnChange(const AHandler: TNotifyEvent);
    procedure RemoveAllHandlersOfObject(AnObject: TObject);
  published
    { The raster image source. Setting it registers a FreeNotification so the
      reference is nil'd automatically if the collection is freed first. }
    property Collection: TTyImageCollection read FCollection write SetCollection;
    { A SECOND source: an icon font, so the same list can expose vector glyphs by name.

      This is what puts icon-font icons on a toolbar or a menu at all. Sixteen published
      Images properties in this library take a TTyVirtualImageList; none takes a
      TTyGlyphImageList, so before this a bundled icon pack could not reach any of them.

        VirtualImageList1.IconFont   := LucideIconFont1;
        VirtualImageList1.Names.Text := 'house'#13'settings'#13'search';
        ToolBar1.Images := VirtualImageList1;

      BOTH sources may be set. Per NAME, the collection is asked first and the font second,
      so a list can mix hand-drawn raster art with font glyphs. Deliberately per name and not
      "collection wins outright": an outright winner would make the other property silently
      inert, which is the defect class this library spends the most effort on. }
    property IconFont: TTyIconFont read FIconFont write SetIconFont;
    { The ordered image NAMES, one per line — a key into Collection, or a glyph name in
      IconFont. }
    property Names: TStrings read FNames write SetNames;
    { Default item edge in LOGICAL px, used by consumers that don't pass a size. }
    property DefaultSize: Integer read FDefaultSize write FDefaultSize default 16;
    { Ink for glyphs taken from IconFont. Raster images carry their own colour and ignore it.

      Defaults to OPAQUE black, not 0. TTyColor is $AARRGGBB, so 0 is fully TRANSPARENT: a
      zero default would have shipped a property whose out-of-the-box value draws nothing at
      all, and "my icons are invisible" is a much worse first experience than "my icons are
      the wrong colour". The same trap already cost this library a ShowValue readout nobody
      could see in any theme. Set it from the theme's ink on a dark background. }
    property GlyphColor: TTyColor read FGlyphColor write SetGlyphColor default $FF000000;
  end;

const
  { How much of an icon's alpha survives the ghosted draw. 96/255 is faint enough to read
    as "unavailable" and solid enough that the glyph is still identifiable -- an icon you
    cannot recognise says "broken", not "disabled". }
  TyGhostedAlpha = 96;

{ Scale every pixel's alpha by AFactor/255. Exported because the ghosted draw is the
  library's one "unavailable" look and other painters should reach for the same one. }
procedure TyFadeBitmapAlpha(ABmp: TBGRABitmap; AFactor: Byte);

implementation

{ Scale every pixel's alpha by AFactor/255, so a masked icon fades evenly and its
  antialiased edges fade with it. }
procedure TyFadeBitmapAlpha(ABmp: TBGRABitmap; AFactor: Byte);
var
  p: PBGRAPixel;
  i: Integer;
begin
  if (ABmp = nil) or (ABmp.NbPixels <= 0) then Exit;
  p := ABmp.Data;
  for i := 0 to ABmp.NbPixels - 1 do
  begin
    p^.alpha := (p^.alpha * AFactor) div 255;
    Inc(p);
  end;
  ABmp.InvalidateBitmap;
end;

procedure TyTintBitmapAlpha(ABmp: TBGRABitmap; AColor: TTyColor);
var
  p: PBGRAPixel;
  i: Integer;
  r, g, b: Byte;
begin
  if (ABmp = nil) or (ABmp.NbPixels <= 0) then Exit;
  r := TyRedOf(AColor);
  g := TyGreenOf(AColor);
  b := TyBlueOf(AColor);
  p := ABmp.Data;
  for i := 0 to ABmp.NbPixels - 1 do
  begin
    // Keep the mask's alpha (incl. antialiased edges); replace only the RGB.
    p^.red := r; p^.green := g; p^.blue := b;
    Inc(p);
  end;
  ABmp.InvalidateBitmap;
end;

{ ---- PNG <-> base64 ---- }

type
  { Scratch buffer for the decode loop. 8 KB is well past a typical icon PNG, so
    most payloads come out in one or two reads. }
  TTyB64Buf = array[0..8191] of Byte;

{ Encode ABmp as a PNG and return it base64-encoded. '' for a nil / empty bitmap.
  Deliberately BGRA-native (TBGRABitmap.SaveToStreamAsPng): the pixels never pass
  through TPicture or MakeBitmapCopy, which is the round trip that has already
  turned a runtime BGRA bitmap ENTIRELY BLACK in this library. }
function TyBitmapToPngBase64(ABmp: TBGRABitmap): string;
var
  raw: TMemoryStream;
  b64: TStringStream;
  enc: TBase64EncodingStream;
begin
  Result := '';
  if (ABmp = nil) or (ABmp.Width <= 0) or (ABmp.Height <= 0) then Exit;
  raw := TMemoryStream.Create;
  try
    ABmp.SaveToStreamAsPng(raw);
    raw.Position := 0;
    b64 := TStringStream.Create('');
    try
      enc := TBase64EncodingStream.Create(b64);
      try
        enc.CopyFrom(raw, raw.Size);
      finally
        enc.Free;   // flushes the tail; MUST precede reading b64
      end;
      Result := b64.DataString;
    finally
      b64.Free;
    end;
  finally
    raw.Free;
  end;
end;

{ Decode a base64 PNG back into a NEW caller-owned TBGRABitmap, or nil when the
  text is empty or does not decode. Never raises: a hand-edited .lfm with a
  mangled payload must leave the icon blank, not stop the form from loading. }
function TyPngBase64ToBitmap(const AText: string): TBGRABitmap;
var
  b64: TStringStream;
  dec: TBase64DecodingStream;
  raw: TMemoryStream;
  bmp: TBGRABitmap;
  buf: TTyB64Buf;
  n: LongInt;
begin
  Result := nil;
  if AText = '' then Exit;
  try
    b64 := TStringStream.Create(AText);
    try
      dec := TBase64DecodingStream.Create(b64);
      try
        raw := TMemoryStream.Create;
        try
          // Read until the decoder runs dry, rather than CopyFrom(dec, 0): that
          // overload seeks the SOURCE to 0 and trusts its Size, and a base64
          // decoding stream knows neither reliably.
          buf := Default(TTyB64Buf);
          repeat
            n := dec.Read(buf, SizeOf(buf));
            if n > 0 then raw.WriteBuffer(buf, n);
          until n <= 0;
          if raw.Size <= 0 then Exit;
          raw.Position := 0;
          bmp := TBGRABitmap.Create;
          try
            bmp.LoadFromStream(raw);
          except
            bmp.Free;
            raise;
          end;
          if (bmp.Width <= 0) or (bmp.Height <= 0) then
          begin
            bmp.Free;
            Exit;
          end;
          Result := bmp;
        finally
          raw.Free;
        end;
      finally
        dec.Free;
      end;
    finally
      b64.Free;
    end;
  except
    // Corrupt base64 or corrupt PNG. Swallowed on purpose (see above); the item's
    // IsDecodable is how a caller tells "corrupt" from "empty".
    Result := nil;
  end;
end;

{ ---- TTyImageItem ---- }

constructor TTyImageItem.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FImageName := '';
  FPngBase64 := '';
  FMaster := nil;
  FDecoded := False;
end;

destructor TTyImageItem.Destroy;
begin
  FMaster.Free;
  inherited Destroy;
end;

procedure TTyImageItem.DropDecoded;
begin
  FreeAndNil(FMaster);
  FDecoded := False;
end;

function TTyImageItem.GetMaster: TBGRABitmap;
begin
  if not FDecoded then
  begin
    // Decode once per payload, success or failure; a corrupt payload must not be
    // re-decoded on every paint.
    FMaster := TyPngBase64ToBitmap(FPngBase64);
    FDecoded := True;
  end;
  Result := FMaster;
end;

function TTyImageItem.IsDecodable: Boolean;
begin
  Result := GetMaster <> nil;
end;

function TTyImageItem.MasterSize: Integer;
var
  m: TBGRABitmap;
begin
  m := GetMaster;
  if m = nil then Exit(0);
  if m.Width >= m.Height then
    Result := m.Width
  else
    Result := m.Height;
end;

function TTyImageItem.GetDisplayName: string;
begin
  // What the stock collection editor lists. The size makes a multi-resolution
  // name readable at a glance ('save (48)' next to 'save (16)') instead of two
  // identical rows.
  if FImageName = '' then
    Result := inherited GetDisplayName
  else if MasterSize > 0 then
    Result := FImageName + ' (' + IntToStr(MasterSize) + ')'
  else
    Result := FImageName + ' (empty)';
end;

procedure TTyImageItem.SetImageName(const AValue: string);
begin
  if FImageName = AValue then Exit;
  FImageName := AValue;
  Changed(False);   // -> TTyImageItems.Update -> the owner's Changed
end;

procedure TTyImageItem.SetPngBase64(const AValue: string);
begin
  if FPngBase64 = AValue then Exit;
  FPngBase64 := AValue;
  DropDecoded;      // the cached bitmap belongs to the OLD payload
  Changed(False);
end;

procedure TTyImageItem.SetBitmap(ABmp: TBGRABitmap);
begin
  SetPngBase64(TyBitmapToPngBase64(ABmp));
end;

procedure TTyImageItem.Assign(ASource: TPersistent);
begin
  if ASource is TTyImageItem then
  begin
    FImageName := TTyImageItem(ASource).FImageName;
    // Copy the PAYLOAD, not the decoded bitmap: two items must never share one
    // TBGRABitmap, and the payload is the source of truth anyway.
    FPngBase64 := TTyImageItem(ASource).FPngBase64;
    DropDecoded;
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

{ ---- TTyImageItems ---- }

constructor TTyImageItems.Create(AOwner: TTyImageCollection);
begin
  inherited Create(TTyImageItem);
  FOwner := AOwner;
end;

function TTyImageItems.GetOwner: TPersistent;
begin
  Result := FOwner;   // makes the collection editor and the streamer find the component
end;

function TTyImageItems.GetItem(AIndex: Integer): TTyImageItem;
begin
  Result := TTyImageItem(inherited Items[AIndex]);
end;

procedure TTyImageItems.SetItem(AIndex: Integer; AValue: TTyImageItem);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyImageItems.Add: TTyImageItem;
begin
  Result := TTyImageItem(inherited Add);
end;

procedure TTyImageItems.Notify(AItem: TCollectionItem; AAction: TCollectionNotification);
begin
  inherited Notify(AItem, AAction);
  if FOwner <> nil then
    FOwner.Changed;   // add / delete / extract all stale the name index and cache
end;

procedure TTyImageItems.Update(AItem: TCollectionItem);
begin
  inherited Update(AItem);
  if FOwner <> nil then
    FOwner.Changed;   // an item's ImageName / PngBase64 changed
end;

{ ---- TTyImageCacheEntry ---- }

constructor TTyImageCacheEntry.Create(AOwnedBmp: TBGRABitmap; ATick: Int64);
begin
  inherited Create;
  FBmp := AOwnedBmp;   // takes ownership
  FTick := ATick;
end;

destructor TTyImageCacheEntry.Destroy;
begin
  FBmp.Free;
  inherited Destroy;
end;

{ ---- TTyImageCollection ---- }

constructor TTyImageCollection.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FImages := TTyImageItems.Create(Self);
  FNames := TStringList.Create;
  FNames.CaseSensitive := True;  // names are case-sensitive keys (per the contract)
  FNamesStamp := FChangeStamp;   // both start empty, so the snapshot starts valid

  FCache := TStringList.Create;
  FCache.OwnsObjects := True;    // frees each TTyImageCacheEntry (and its render)
  FCache.CaseSensitive := True;  // must precede Sorted: it selects the compare
  FCache.Sorted := True;         // binary-search lookup on the composite key
  FCache.Duplicates := dupError;
  FCacheCapacity := TyImageCacheDefaultCapacity;
  FCacheStamp := FChangeStamp;
end;

destructor TTyImageCollection.Destroy;
begin
  FCache.Free;    // OwnsObjects frees every cached render
  // Detach first: TCollection.Clear notifies per item, and each notification would
  // otherwise call Changed on a half-destroyed component.
  FImages.FOwner := nil;
  FImages.Free;   // frees every item -> every decoded master
  FNames.Free;
  inherited Destroy;
end;

class function TTyImageCollection.CacheKey(const AName: string; ASizePx: Integer): string;
begin
  // #1 cannot appear in a practical image name, so it separates the two parts
  // without a collision between e.g. ('a', 11) and ('a1', 1).
  Result := AName + #1 + IntToStr(ASizePx);
end;

procedure TTyImageCollection.Changed;
begin
  // Monotonic; SyncCache compares it lazily on the next read. Cheaper than an
  // observer list, and a mutation that forgets to flush still cannot serve a
  // stale render.
  Inc(FChangeStamp);
end;

procedure TTyImageCollection.FlushCache;
begin
  FCache.Clear;   // OwnsObjects frees every render
  FCacheStamp := FChangeStamp;
end;

procedure TTyImageCollection.SyncCache;
begin
  if FCacheStamp <> FChangeStamp then
    FlushCache;
end;

procedure TTyImageCollection.TrimCacheTo(AMax: Integer);
var
  i, victim: Integer;
  oldest: Int64;
begin
  if AMax < 0 then AMax := 0;
  while FCache.Count > AMax do
  begin
    // Linear scan for the least-recently-used entry. The cache is small (capacity
    // entries) and this only runs on insert-when-full, so it stays cheaper than
    // maintaining an intrusive LRU order.
    victim := 0;
    oldest := TTyImageCacheEntry(FCache.Objects[0]).FTick;
    for i := 1 to FCache.Count - 1 do
      if TTyImageCacheEntry(FCache.Objects[i]).FTick < oldest then
      begin
        oldest := TTyImageCacheEntry(FCache.Objects[i]).FTick;
        victim := i;
      end;
    FCache.Delete(victim);   // OwnsObjects frees the entry + its render
  end;
end;

procedure TTyImageCollection.SetCacheCapacity(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FCacheCapacity = AValue then Exit;
  FCacheCapacity := AValue;
  TrimCacheTo(FCacheCapacity);   // shrink now rather than at the next read
end;

function TTyImageCollection.CacheCount: Integer;
begin
  Result := FCache.Count;
end;

function TTyImageCollection.IsCached(const AName: string; ASizePx: Integer): Boolean;
begin
  if ASizePx < 1 then ASizePx := 1;
  SyncCache;   // a mutation since the last read means nothing is really cached
  Result := FCache.IndexOf(CacheKey(AName, ASizePx)) >= 0;
end;

procedure TTyImageCollection.SetImages(AValue: TTyImageItems);
begin
  // Assign, never take the instance: the collection is ours for our whole life.
  // Only here so TWriter.WriteProperty does not skip Images — see the property.
  FImages.Assign(AValue);
end;

procedure TTyImageCollection.SyncNames;
var
  i: Integer;
  nm: string;
begin
  if FNamesStamp = FChangeStamp then Exit;
  FNames.Clear;
  for i := 0 to FImages.Count - 1 do
  begin
    nm := FImages[i].ImageName;
    // Skip unnamed masters (a freshly-added OI row before it is filled in) and
    // fold a name's several resolutions into ONE entry: Count counts images.
    if (nm <> '') and (FNames.IndexOf(nm) < 0) then
      FNames.Add(nm);
  end;
  FNamesStamp := FChangeStamp;
end;

function TTyImageCollection.RemoveMasters(const AName: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  // Backwards: deleting shifts every later index down, and a forward loop would
  // step over the item that slid into the hole.
  for i := FImages.Count - 1 downto 0 do
    if FImages[i].ImageName = AName then
    begin
      FImages.Delete(i);
      Inc(Result);
    end;
end;

procedure TTyImageCollection.AddBitmap(const AName: string; ABmp: TBGRABitmap);
var
  it: TTyImageItem;
begin
  if (AName = '') or (ABmp = nil) then Exit;
  RemoveMasters(AName);   // replace the NAME, not just one resolution
  it := FImages.Add;
  it.ImageName := AName;
  it.SetBitmap(ABmp);     // encodes a PNG copy; the caller keeps theirs
  // Each of those already called Changed through the collection's Notify/Update.
end;

procedure TTyImageCollection.AddMasterBitmap(const AName: string; ABmp: TBGRABitmap);
var
  i, edge: Integer;
  it: TTyImageItem;
begin
  if (AName = '') or (ABmp = nil) then Exit;
  if ABmp.Width >= ABmp.Height then edge := ABmp.Width else edge := ABmp.Height;
  // A same-size master would be unreachable — the pick compares sizes — so replace
  // it rather than leaving a second copy nothing can ever choose.
  for i := FImages.Count - 1 downto 0 do
    if (FImages[i].ImageName = AName) and (FImages[i].MasterSize = edge) then
      FImages.Delete(i);
  it := FImages.Add;
  it.ImageName := AName;
  it.SetBitmap(ABmp);
end;

function TTyImageCollection.MasterCount(const AName: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  if AName = '' then Exit;
  for i := 0 to FImages.Count - 1 do
    if FImages[i].ImageName = AName then
      Inc(Result);
end;

function TTyImageCollection.PickMaster(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  i, edge, bestFitEdge, largestEdge: Integer;
  m, bestFit, largest: TBGRABitmap;
begin
  bestFit := nil; bestFitEdge := 0;
  largest := nil; largestEdge := 0;
  for i := 0 to FImages.Count - 1 do
  begin
    if FImages[i].ImageName <> AName then Continue;
    m := FImages[i].Master;          // decodes on demand; nil when empty / corrupt
    if m = nil then Continue;
    edge := FImages[i].MasterSize;
    if edge <= 0 then Continue;
    // The smallest master that still covers the request: downscaling keeps detail,
    // upscaling invents it. Ties keep the first, which is authoring order.
    if (edge >= ASizePx) and ((bestFit = nil) or (edge < bestFitEdge)) then
    begin
      bestFit := m; bestFitEdge := edge;
    end;
    if edge > largestEdge then
    begin
      largest := m; largestEdge := edge;
    end;
  end;
  // Nothing big enough -> the largest there is, which is the least bad upscale.
  if bestFit <> nil then Result := bestFit else Result := largest;
end;

function TTyImageCollection.PickedMasterSize(const AName: string; ASizePx: Integer): Integer;
var
  m: TBGRABitmap;
begin
  if ASizePx < 1 then ASizePx := 1;
  m := PickMaster(AName, ASizePx);
  if m = nil then Exit(0);
  if m.Width >= m.Height then Result := m.Width else Result := m.Height;
end;

procedure TTyImageCollection.AddPicture(const AName: string; APicture: TPicture);
var
  master: TBGRABitmap;
  tmp: TBitmap;
begin
  if (AName = '') or (APicture = nil) or (APicture.Graphic = nil)
    or APicture.Graphic.Empty then Exit;
  // Rasterize the picture's graphic (any LCL graphic — PNG/BMP/JPG, alpha kept
  // for 32-bit sources) onto an owned TBitmap, then build the master from it via
  // the TBitmap constructor overload — no dependency on a TGraphic-typed Create.
  tmp := TBitmap.Create;
  try
    tmp.Assign(APicture.Graphic);   // convert/copy the graphic into a bitmap
    if (tmp.Width <= 0) or (tmp.Height <= 0) then Exit;
    master := TBGRABitmap.Create(tmp);
  finally
    tmp.Free;
  end;
  try
    AddBitmap(AName, master);   // encodes the PNG payload; keeps its own copy
  finally
    master.Free;                // ...so this intermediate is ours to release
  end;
end;

procedure TTyImageCollection.Clear;
begin
  FImages.Clear;  // frees every item -> every decoded master; Notify -> Changed
  // Unconditionally, NOT just via the per-item Notify: clearing an already-empty
  // collection notifies nothing, and a consumer that keyed anything off ChangeStamp
  // would keep serving what it had. (ChangeStampBumpsOnClear pins exactly this.)
  Changed;
  FlushCache;     // "drop everything" should release the render memory now, not lazily
end;

function TTyImageCollection.Count: Integer;
begin
  SyncNames;
  Result := FNames.Count;
end;

function TTyImageCollection.NameOf(AIndex: Integer): string;
begin
  SyncNames;
  if (AIndex >= 0) and (AIndex < FNames.Count) then
    Result := FNames[AIndex]
  else
    Result := '';
end;

function TTyImageCollection.IndexOf(const AName: string): Integer;
begin
  SyncNames;
  Result := FNames.IndexOf(AName);
end;

function TTyImageCollection.Contains(const AName: string): Boolean;
begin
  Result := IndexOf(AName) >= 0;
end;

function TTyImageCollection.RenderMaster(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  dw, dh, ox, oy: Integer;
  master, scaled: TBGRABitmap;
  sc: Double;
begin
  // Always a non-nil transparent square of the requested size; we paint the scaled
  // master (if any) centered onto it, so consumers can blit unconditionally.
  Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent);
  // Borrowed from the item that owns it — never freed here.
  master := PickMaster(AName, ASizePx);
  if (master = nil) or (master.Width <= 0) or (master.Height <= 0) then Exit;

  // Fit the master into the square, preserving aspect (contain).
  sc := ASizePx / master.Width;
  if (ASizePx / master.Height) < sc then
    sc := ASizePx / master.Height;
  dw := Round(master.Width * sc);
  dh := Round(master.Height * sc);
  if dw < 1 then dw := 1;
  if dh < 1 then dh := 1;

  // Guard the always-created Result across the scale/composite so it is freed (not
  // leaked) if Resample or PutImage raises (e.g. under allocation failure).
  try
    scaled := master.Resample(dw, dh, rmFineResample) as TBGRABitmap;
    try
      ox := (ASizePx - dw) div 2;
      oy := (ASizePx - dh) div 2;
      Result.PutImage(ox, oy, scaled, dmDrawWithTransparency);
    finally
      scaled.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TTyImageCollection.GetCachedBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  key: string;
  idx: Integer;
  entry: TTyImageCacheEntry;
  rendered: TBGRABitmap;
begin
  Result := nil;
  if ASizePx < 1 then ASizePx := 1;
  SyncCache;                                // drop renders staled by a mutation
  if IndexOf(AName) < 0 then Exit;          // unknown name -> nothing to draw

  key := CacheKey(AName, ASizePx);
  idx := FCache.IndexOf(key);
  if idx >= 0 then
  begin
    entry := TTyImageCacheEntry(FCache.Objects[idx]);
    Inc(FTick);
    entry.FTick := FTick;   // touch: this is now the most recently used
    Exit(entry.FBmp);
  end;

  // Miss. Make room BEFORE inserting, so we can never evict the entry we are about
  // to hand back (capacity is clamped to >= 1, so this leaves at least one slot).
  TrimCacheTo(FCacheCapacity - 1);
  rendered := RenderMaster(AName, ASizePx);
  Inc(FTick);
  entry := TTyImageCacheEntry.Create(rendered, FTick);   // takes ownership
  try
    FCache.AddObject(key, entry);
  except
    entry.Free;   // frees the render too
    raise;
  end;
  Result := entry.FBmp;
end;

function TTyImageCollection.GetBitmap(const AName: string; ASizePx: Integer): TBGRABitmap;
var
  cached: TBGRABitmap;
begin
  if ASizePx < 1 then ASizePx := 1;
  cached := GetCachedBitmap(AName, ASizePx);
  if cached <> nil then
    // Copy, never the cache entry itself: callers tint the result in place.
    Result := cached.Duplicate as TBGRABitmap
  else
    Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent);
end;

{ ---- TTyVirtualImageList ---- }

procedure TTyVirtualImageList.AddHandlerOnChange(const AHandler: TNotifyEvent;
  AsFirst: Boolean);
begin
  if FChangeHandlers = nil then FChangeHandlers := TMethodList.Create;
  FChangeHandlers.Add(TMethod(AHandler), not AsFirst);
end;

procedure TTyVirtualImageList.RemoveHandlerOnChange(const AHandler: TNotifyEvent);
begin
  if FChangeHandlers <> nil then FChangeHandlers.Remove(TMethod(AHandler));
end;

procedure TTyVirtualImageList.RemoveAllHandlersOfObject(AnObject: TObject);
begin
  if FChangeHandlers <> nil then FChangeHandlers.RemoveAllMethodsOfObject(AnObject);
end;

procedure TTyVirtualImageList.Changed;
begin
  if FChangeHandlers <> nil then FChangeHandlers.CallNotifyEvents(Self);
end;

procedure TTyVirtualImageList.NamesChanged(Sender: TObject);
begin
  { FNames was a bare TStringList with no OnChange, so `List.Names.Add('x')` -- the ordinary
    way to use this component -- changed what it exposes and told nobody. }
  DropGlyphCache;
  Changed;
end;

constructor TTyVirtualImageList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNames := TStringList.Create;
  TStringList(FNames).OnChange := @NamesChanged;
  FDefaultSize := 16;
  FGlyphColor := $FF000000;   { opaque black -- see the property's note }
  FGlyphCacheVersion := -1;
end;

destructor TTyVirtualImageList.Destroy;
begin
  DropGlyphCache;
  TStringList(FNames).OnChange := nil;   { must not fire into a half-freed component }
  FNames.Free;
  FChangeHandlers.Free;
  inherited Destroy;
end;

procedure TTyVirtualImageList.DropGlyphCache;
begin
  FreeAndNil(FGlyphCache);
  FGlyphCacheName := '';
end;

procedure TTyVirtualImageList.SetCollection(AValue: TTyImageCollection);
begin
  if FCollection = AValue then Exit;
  if FCollection <> nil then
    FCollection.RemoveFreeNotification(Self);
  FCollection := AValue;
  if FCollection <> nil then
    FCollection.FreeNotification(Self);
  Changed;
end;

procedure TTyVirtualImageList.SetIconFont(AValue: TTyIconFont);
begin
  if FIconFont = AValue then Exit;
  if FIconFont <> nil then
    FIconFont.RemoveFreeNotification(Self);
  FIconFont := AValue;
  if FIconFont <> nil then
    FIconFont.FreeNotification(Self);
  DropGlyphCache;
  Changed;
end;

procedure TTyVirtualImageList.SetGlyphColor(AValue: TTyColor);
begin
  if FGlyphColor = AValue then Exit;
  FGlyphColor := AValue;
  DropGlyphCache;
  Changed;
end;

procedure TTyVirtualImageList.SetNames(AValue: TStrings);
begin
  FNames.Assign(AValue);   { fires NamesChanged, which drops the cache and announces }
end;

procedure TTyVirtualImageList.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FCollection) then
    FCollection := nil;
  if (Operation = opRemove) and (AComponent = FIconFont) then
  begin
    FIconFont := nil;
    { The cached glyph belongs to a font that is going away. }
    DropGlyphCache;
  end;
end;

{ 0 = nothing, 1 = the collection, 2 = the icon font. }
function TTyVirtualImageList.ResolveSource(AIndex: Integer; out AName: string): Integer;
begin
  Result := 0;
  AName := NameOf(AIndex);
  if AName = '' then Exit;
  if (FCollection <> nil) and (FCollection.IndexOf(AName) >= 0) then Exit(1);
  if (FIconFont <> nil) and FIconFont.HasGlyph(AName) then Exit(2);
end;

function TTyVirtualImageList.Count: Integer;
begin
  Result := FNames.Count;
end;

function TTyVirtualImageList.NameOf(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FNames.Count) then
    Result := FNames[AIndex]
  else
    Result := '';
end;

function TTyVirtualImageList.IndexOf(const AName: string): Integer;
begin
  Result := FNames.IndexOf(AName);
end;

function TTyVirtualImageList.RenderIndex(AIndex, ASizePx: Integer): TBGRABitmap;
var
  nm: string;
begin
  if ASizePx < 1 then ASizePx := 1;
  // Neither source has it (no source at all, index out of range, unknown name) -> an empty
  // transparent square of the requested size. Never nil, as before.
  case ResolveSource(AIndex, nm) of
    1: Result := FCollection.GetBitmap(nm, ASizePx);
    2: Result := FIconFont.RenderGlyph(nm, ASizePx, FGlyphColor);
  else
    Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent);
  end;
end;

function TTyVirtualImageList.CachedIndex(AIndex, ASizePx: Integer): TBGRABitmap;
var
  nm: string;
begin
  Result := nil;
  if ASizePx < 1 then ASizePx := 1;
  case ResolveSource(AIndex, nm) of
    1:
      // Borrowed: owned by the collection's render cache (nil when the name is missing).
      Result := FCollection.GetCachedBitmap(nm, ASizePx);
    2:
      begin
        { The font has no cache to borrow from, so keep one slot here. The font's Version is
          part of the key: editing its Glyphs or swapping its file changes what a name draws,
          and a cache that ignored that would keep serving the old glyph. }
        if (FGlyphCache = nil) or (FGlyphCacheName <> nm) or (FGlyphCacheSize <> ASizePx)
           or (FGlyphCacheColor <> FGlyphColor) or (FGlyphCacheVersion <> FIconFont.Version) then
        begin
          FreeAndNil(FGlyphCache);
          FGlyphCache := FIconFont.RenderGlyph(nm, ASizePx, FGlyphColor);
          FGlyphCacheName := nm;
          FGlyphCacheSize := ASizePx;
          FGlyphCacheColor := FGlyphColor;
          FGlyphCacheVersion := FIconFont.Version;
        end;
        Result := FGlyphCache;
      end;
  end;
end;

procedure TTyVirtualImageList.Draw(ACanvas: TCanvas; AX, AY, AIndex: Integer;
  AEnabled: Boolean);
begin
  // The one place the two polarities meet. Named here rather than at each call site so
  // there is exactly one `not` to get wrong, and it is under a test.
  DrawIndex(ACanvas, AIndex, AX, AY, FDefaultSize, not AEnabled);
end;

procedure TTyVirtualImageList.DrawIndex(ACanvas: TCanvas; AIndex, AX, AY, ASizePx: Integer;
  AGhosted: Boolean);
var
  bmp, dim: TBGRABitmap;
begin
  if ACanvas = nil then Exit;
  if ASizePx < 1 then ASizePx := 1;
  // Borrowed, so nothing to free. nil means "nothing to draw" (no Collection / bad
  // index / missing name) — where we previously blitted a fully transparent square,
  // which was a visual no-op anyway. The False keeps the icon's alpha.
  bmp := CachedIndex(AIndex, ASizePx);
  if bmp = nil then Exit;
  if not AGhosted then
  begin
    bmp.Draw(ACanvas, AX, AY, False);
    Exit;
  end;
  { The cached bitmap is SHARED -- dimming it in place would ghost the icon everywhere it
    is drawn from then on, including in other controls. Copy, dim the copy, free it. }
  dim := bmp.Duplicate as TBGRABitmap;
  try
    TyFadeBitmapAlpha(dim, TyGhostedAlpha);
    dim.Draw(ACanvas, AX, AY, False);
  finally
    dim.Free;
  end;
end;

initialization
  { Required for the .lfm half of the streaming to work at RUN time: the reader
    instantiates a child component by looking its class name up in this registry,
    so without it a form carrying an image collection fails to load with "Class
    TTyImageCollection not found" — the design-time pixels would stream out and
    never come back. TTyTreeView registers itself the same way. }
  RegisterClass(TTyImageCollection);
  RegisterClass(TTyVirtualImageList);

end.
