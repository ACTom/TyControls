unit tyControls.GlyphImageList;
{$mode objfpc}{$H+}

{ TTyGlyphImageList — an ordered list of icon-font glyphs (by NAME), backed by a
  TTyIconFont, that renders any item crisply on demand at the consumer's pixel
  size + color. It is the scalable "image list" that ty-controls' own custom
  controls consume (toolbars, tree/list rows, ribbon buttons, …) — NOT LCL's
  native TImageList. Because it renders vectors on demand rather than holding a
  fixed-resolution raster set, it is a plain TComponent with a Draw method, not
  a TCustomImageList descendant.

  The Glyphs list holds the glyph NAMES (one per line) — each name is a key into
  the referenced IconFont.Glyphs map. RenderIndex/Draw look the name up in the
  IconFont and delegate the rasterization to TTyIconFont.RenderGlyph, so the
  name->index bookkeeping here is pure and unit-tested headlessly; the actual
  pixels need a real machine + the registered font (same contract as the font). }

interface

uses
  Classes, SysUtils, Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.IconFont;

type
  TTyGlyphImageList = class(TComponent)
  private
    FGlyphs: TStrings;          // ordered glyph NAMES, one per line (a TStringList)
    FIconFont: TTyIconFont;
    FDefaultSize: Integer;
    FDefaultColor: TTyColor;
    procedure SetGlyphs(AValue: TStrings);
    procedure SetIconFont(AValue: TTyIconFont);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Number of items (= Glyphs.Count). }
    function Count: Integer;
    { The glyph name at AIndex, or '' when AIndex is out of range. }
    function GlyphNameOf(AIndex: Integer): string;
    { Index of the (case-sensitive) glyph name AName, or -1 when absent. }
    function IndexOf(const AName: string): Integer;
    { Render item AIndex via IconFont into an ASizePx square, colored AColor, on a
      transparent background. Caller OWNS the returned bitmap. Never nil: returns an
      empty transparent bitmap of the requested size when IconFont is unset, AIndex
      is out of range, or ASizePx <= 0 (clamped to a 1px square). }
    function RenderIndex(AIndex: Integer; ASizePx: Integer; AColor: TTyColor): TBGRABitmap;
    { Render item AIndex and paint it onto ACanvas at (AX, AY). Guards every edge
      case (nil canvas/IconFont, bad index, ASizePx <= 0) so it never raises. }
    procedure Draw(ACanvas: TCanvas; AIndex, AX, AY, ASizePx: Integer; AColor: TTyColor);
  published
    { The glyph source. Setting it registers a FreeNotification so the reference is
      nil'd automatically if the font component is freed first. }
    property IconFont: TTyIconFont read FIconFont write SetIconFont;
    { The ordered glyph NAMES, one per line — each a key into IconFont.Glyphs. }
    property Glyphs: TStrings read FGlyphs write SetGlyphs;
    { Default item edge in LOGICAL px, used by consumers that don't pass a size. }
    property DefaultSize: Integer read FDefaultSize write FDefaultSize default 16;
    { Default glyph color ($AARRGGBB), used by consumers that don't pass a color. }
    property DefaultColor: TTyColor read FDefaultColor write FDefaultColor;
  end;

implementation

constructor TTyGlyphImageList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGlyphs := TStringList.Create;
  FDefaultSize := 16;
  FDefaultColor := 0;
end;

destructor TTyGlyphImageList.Destroy;
begin
  FGlyphs.Free;
  inherited Destroy;
end;

procedure TTyGlyphImageList.SetGlyphs(AValue: TStrings);
begin
  FGlyphs.Assign(AValue);
end;

procedure TTyGlyphImageList.SetIconFont(AValue: TTyIconFont);
begin
  if FIconFont = AValue then Exit;
  if FIconFont <> nil then
    FIconFont.RemoveFreeNotification(Self);
  FIconFont := AValue;
  if FIconFont <> nil then
    FIconFont.FreeNotification(Self);
end;

procedure TTyGlyphImageList.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FIconFont) then
    FIconFont := nil;
end;

function TTyGlyphImageList.Count: Integer;
begin
  Result := FGlyphs.Count;
end;

function TTyGlyphImageList.GlyphNameOf(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FGlyphs.Count) then
    Result := FGlyphs[AIndex]
  else
    Result := '';
end;

function TTyGlyphImageList.IndexOf(const AName: string): Integer;
begin
  Result := FGlyphs.IndexOf(AName);
end;

function TTyGlyphImageList.RenderIndex(AIndex: Integer; ASizePx: Integer;
  AColor: TTyColor): TBGRABitmap;
var
  gname: string;
begin
  if ASizePx < 1 then ASizePx := 1;
  gname := GlyphNameOf(AIndex);
  // No font, or index out of range -> an empty transparent square of the
  // requested size (never nil), so consumers can blit it unconditionally.
  if (FIconFont = nil) or (gname = '') then
    Result := TBGRABitmap.Create(ASizePx, ASizePx, BGRAPixelTransparent)
  else
    Result := FIconFont.RenderGlyph(gname, ASizePx, AColor);
end;

procedure TTyGlyphImageList.Draw(ACanvas: TCanvas; AIndex, AX, AY, ASizePx: Integer;
  AColor: TTyColor);
var
  bmp: TBGRABitmap;
begin
  if ACanvas = nil then Exit;
  if ASizePx < 1 then ASizePx := 1;
  // RenderIndex always returns a non-nil bitmap (empty when unrenderable), so the
  // blit is safe even with no IconFont / a bad index. bmp.Draw blends onto the LCL
  // canvas at (AX, AY); the False keeps its alpha (transparent background).
  bmp := RenderIndex(AIndex, ASizePx, AColor);
  try
    bmp.Draw(ACanvas, AX, AY, False);
  finally
    bmp.Free;
  end;
end;

end.
