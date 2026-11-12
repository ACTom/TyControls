unit tyControls.RichEdit.Wmf;

{ Windows metafiles (WMF), as RTF's \wmetafile pictures carry them. TTyRichEdit does not draw
  metafiles in phase 1, but a metafile whose whole drawing is one device-independent bitmap is
  that bitmap and can be shown as one: WordPad saves every picture that way (a pasted bitmap
  and an inserted PNG alike), and Word writes a picture's fallback that way. This unit only
  walks the record structure and finds the bitmap; it decodes no pixels and allocates nothing,
  and it never reads past the bytes it is given - a record that is cut short or claims more
  bytes than there are makes the answer False. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TTyWmfBitmap = record
    DibStart: PtrInt;   // where the BITMAPINFOHEADER (or BITMAPCOREHEADER) starts in the bytes
    DibCount: PtrInt;   // header, colour table and bits: up to the end of the record
    Width: Integer;     // pixels
    Height: Integer;    // pixels (positive also for a top-down bitmap)
  end;

{ True when the metafile (with or without the 22-byte placeable header) draws exactly one
  bitmap - META_STRETCHDIB, META_DIBSTRETCHBLT, META_SETDIBTODEV or META_DIBBITBLT with a
  BITMAPINFO, copied as it is (SRCCOPY, RGB colours) - and otherwise only sets state: window and
  viewport, mapping mode, saved and restored contexts, colours and modes, objects made, selected
  and deleted, escapes. Anything else (lines, shapes, text, fills, regions, clipping, a second
  bitmap, device-dependent bitmaps, records this unit does not know) gives False, as does a
  metafile without its end record. }
function TyWmfSingleBitmap(AData: PByte; ACount: PtrInt; out ABitmap: TTyWmfBitmap): Boolean;
function TyWmfSingleBitmap(const AData: TBytes; out ABitmap: TTyWmfBitmap): Boolean;

implementation

const
  PlaceableKey = $9AC6CDD7;
  PlaceableBytes = 22;
  HeaderBytes = 18;        // META_HEADER: its HeaderSize field says 9 words
  RecordHeadBytes = 6;     // RecordSize (in 16-bit words, itself included) and RecordFunction
  SrcCopy = $00CC0020;

  MetaEof = $0000;
  MetaStretchDib = $0F43;
  MetaDibStretchBlt = $0B41;
  MetaSetDibToDev = $0D33;
  MetaDibBitBlt = $0940;

type
  TRecordKind = (rkState, rkBitmap, rkOther);

function W16(P: PByte; AAt: PtrInt): Cardinal; inline;
begin
  Result := Cardinal(P[AAt]) or (Cardinal(P[AAt + 1]) shl 8);
end;

function W32(P: PByte; AAt: PtrInt): Cardinal; inline;
begin
  Result := W16(P, AAt) or (W16(P, AAt + 2) shl 16);
end;

function KindOf(AFunction: Cardinal): TRecordKind;
begin
  case AFunction of
    MetaStretchDib, MetaDibStretchBlt, MetaSetDibToDev, MetaDibBitBlt:
      Result := rkBitmap;
    $001E, $0127,                                   // SaveDC, RestoreDC
    $0103, $0105, $0107,                            // map mode, rel/abs, stretch-blt mode
    $0102, $0201, $0209, $0104, $0106,              // bk mode, bk colour, text colour, ROP2, poly fill
    $012E, $0108, $020A, $0231,                     // text align, char extra, justification, mapper
    $020B, $020C, $020D, $020E, $020F, $0410, $0211, $0412,  // window / viewport org and ext
    $0214,                                          // MoveTo: a position, no ink
    $0626,                                          // Escape
    $02FA, $02FC, $02FB, $00F7, $01F9, $0142, $06FF, // pen, brush, font, palette, pattern brushes, region
    $012D, $01F0,                                   // SelectObject, DeleteObject
    $0234, $0035, $0037, $0436, $0139:              // palette selection and changes
      Result := rkState;
  else
    // drawing (LineTo, Polyline, Polygon, Rectangle, Ellipse, Arc, TextOut, ExtTextOut,
    // PatBlt, SetPixel, FloodFill, region fills, BitBlt/StretchBlt of a device-dependent
    // bitmap), clipping (it may cut the bitmap), and anything not known
    Result := rkOther;
  end;
end;

{ A BITMAPINFO followed by its bits, all inside [0, ACount): the header is one Windows writes,
  and the colour table and the bits it announces fit. }
function ValidDib(P: PByte; ACount: PtrInt; out AWidth, AHeight: Integer): Boolean;
var
  hdr, bpp, compression, colours, entry, masks: Cardinal;
  w, h, need, bits: Int64;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;
  if ACount < 12 then Exit;
  hdr := W32(P, 0);
  if hdr = 12 then
  begin
    // BITMAPCOREHEADER: 16-bit sizes, RGB triples, never compressed
    w := W16(P, 4);
    h := W16(P, 6);
    if W16(P, 8) <> 1 then Exit;
    bpp := W16(P, 10);
    compression := 0;
    colours := 0;
    entry := 3;
    masks := 0;
  end
  else if (hdr = 40) or (hdr = 52) or (hdr = 56) or (hdr = 108) or (hdr = 124) then
  begin
    if ACount < hdr then Exit;
    w := LongInt(W32(P, 4));
    h := LongInt(W32(P, 8));
    if W16(P, 12) <> 1 then Exit;
    bpp := W16(P, 14);
    compression := W32(P, 16);
    colours := W32(P, 32);
    entry := 4;
    // BI_BITFIELDS after a 40-byte header: three masks follow it; the longer headers hold them
    if (compression = 3) and (hdr = 40) then masks := 12 else masks := 0;
  end
  else
    Exit;
  if h < 0 then h := -h;
  if (w <= 0) or (h <= 0) or (w > High(Integer)) or (h > High(Integer)) then Exit;
  case bpp of
    1, 4, 8:
      begin
        if colours = 0 then colours := Cardinal(1) shl bpp;
        if colours > (Cardinal(1) shl bpp) then Exit;
      end;
    16, 24, 32: ;
  else
    Exit;
  end;
  // RGB, RLE8 (8 bits), RLE4 (4 bits), bit fields (16 or 32 bits); a JPEG or PNG inside a DIB
  // is left to the placeholder
  case compression of
    0: ;
    1: if bpp <> 8 then Exit;
    2: if bpp <> 4 then Exit;
    3: if (bpp <> 16) and (bpp <> 32) then Exit;
  else
    Exit;
  end;
  bits := Int64(hdr) + masks + Int64(colours) * entry;
  if bits > ACount then Exit;
  if (compression = 1) or (compression = 2) then
  begin
    need := W32(P, 20);    // biSizeImage: an RLE bitmap's bits say their own length
    if need = 0 then Exit;
  end
  else
    need := ((w * bpp + 31) div 32) * 4 * h;
  if bits + need > ACount then Exit;
  AWidth := Integer(w);
  AHeight := Integer(h);
  Result := True;
end;

{ The bitmap of one bitmap record [AAt, AAt + ABytes) - parameters, then the BITMAPINFO. }
function BitmapOf(P: PByte; AAt, ABytes: PtrInt; AFunction: Cardinal;
  var ABitmap: TTyWmfBitmap): Boolean;
var
  prm, dib, words: PtrInt;
  rop, usage: Cardinal;
begin
  Result := False;
  prm := AAt + RecordHeadBytes;
  words := ABytes div 2;
  usage := 0;
  rop := SrcCopy;
  case AFunction of
    MetaStretchDib:
      begin
        // RasterOp, ColorUsage, source height/width/y/x, destination height/width/y/x
        dib := 22;
        if ABytes < RecordHeadBytes + dib then Exit;
        rop := W32(P, prm);
        usage := W16(P, prm + 4);
      end;
    MetaDibStretchBlt, MetaDibBitBlt:
      begin
        // the variant without a bitmap (a pattern fill) is (RecordFunction shr 8) + 3 words
        if words = PtrInt(AFunction shr 8) + 3 then Exit;
        // RasterOp, source height/width (StretchBlt only), y/x, destination ...
        if AFunction = MetaDibStretchBlt then dib := 20 else dib := 16;
        if ABytes < RecordHeadBytes + dib then Exit;
        rop := W32(P, prm);
      end;
    MetaSetDibToDev:
      begin
        // ColorUse, ScanCount, StartScan, ...: the whole bitmap, from its first scan line
        dib := 18;
        if ABytes < RecordHeadBytes + dib then Exit;
        usage := W16(P, prm);
        if W16(P, prm + 4) <> 0 then Exit;
      end;
  else
    Exit;
  end;
  // another raster operation would combine the bitmap with what is below it; palette indices
  // instead of colours need the metafile's palette
  if (rop <> SrcCopy) or (usage <> 0) then Exit;
  ABitmap.DibStart := prm + dib;
  ABitmap.DibCount := ABytes - RecordHeadBytes - dib;
  if not ValidDib(P + ABitmap.DibStart, ABitmap.DibCount, ABitmap.Width, ABitmap.Height) then
    Exit;
  if (AFunction = MetaSetDibToDev) and (PtrInt(W16(P, prm + 2)) <> ABitmap.Height) then Exit;
  Result := True;
end;

function TyWmfSingleBitmap(AData: PByte; ACount: PtrInt; out ABitmap: TTyWmfBitmap): Boolean;
var
  at, bytes: PtrInt;
  size, fn, kind: Cardinal;
  found: Boolean;
  bm: TTyWmfBitmap;
begin
  Result := False;
  ABitmap := Default(TTyWmfBitmap);
  bm := Default(TTyWmfBitmap);
  if (AData = nil) or (ACount < HeaderBytes) then Exit;
  at := 0;
  if W32(AData, 0) = PlaceableKey then
  begin
    at := PlaceableBytes;
    if ACount - at < HeaderBytes then Exit;
  end;
  // META_HEADER: memory or disk metafile, 9 words, Windows 3.0 or later (or 2.x without DIBs)
  kind := W16(AData, at);
  if ((kind <> 1) and (kind <> 2)) or (W16(AData, at + 2) <> 9) or
     ((W16(AData, at + 4) <> $0100) and (W16(AData, at + 4) <> $0300)) then
    Exit;
  Inc(at, HeaderBytes);
  found := False;
  repeat
    if ACount - at < RecordHeadBytes then Exit;
    size := W32(AData, at);
    fn := W16(AData, at + 4);
    // a size counts 16-bit words; one below the record's own head, or past the end, is a lie
    if (size < 3) or (Int64(size) > (ACount - at) div 2) then Exit;
    bytes := PtrInt(size) * 2;
    if fn = MetaEof then Break;
    case KindOf(fn) of
      rkState: ;
      rkBitmap:
        begin
          if found then Exit;     // a second bitmap: a picture of several parts
          if not BitmapOf(AData, at, bytes, fn, bm) then Exit;
          found := True;
        end;
    else
      Exit;
    end;
    Inc(at, bytes);
  until False;
  Result := found;
  if Result then ABitmap := bm;
end;

function TyWmfSingleBitmap(const AData: TBytes; out ABitmap: TTyWmfBitmap): Boolean;
begin
  if Length(AData) = 0 then
  begin
    ABitmap := Default(TTyWmfBitmap);
    Exit(False);
  end;
  Result := TyWmfSingleBitmap(@AData[0], Length(AData), ABitmap);
end;

end.
