unit uicons;
{$mode objfpc}{$H+}

{ Flat, monochrome, cross-platform command icons for the ribbon example.

  Every icon is drawn as a 32x32 master TBGRABitmap with a fully transparent
  background and the shape painted in OPAQUE BLACK. The icons are consumed as
  ALPHA MASKS: the button re-tints them to the theme text colour at draw time,
  so only the alpha/coverage matters — the RGB is discarded. Antialiased BGRA
  primitives give smooth edges (smooth alpha) so the re-tinted glyphs stay crisp
  at any DPI.

  NO system fonts are used anywhere — every glyph, including the number ticks and
  the omega symbol, is built from BGRA vector primitives so the icons render
  byte-for-byte identically on Windows 7/10/11, macOS and Linux. }

interface

uses
  Classes, SysUtils, BGRABitmap, BGRABitmapTypes, tyControls.ImageCollection;

{ Populate AColl with all editor command icons (32x32 masters, opaque-black alpha
  masks, transparent background). Cross-platform: pure BGRA, no system fonts. }
procedure BuildEditorIcons(AColl: TTyImageCollection);

implementation

const
  ICON_SIZE = 32;
  STROKE    = 2.2;    // default stroke width (px)
  THIN      = 1.6;    // thin accents / inner detail

var
  INK: TBGRAPixel;    // opaque black — the only colour used (alpha is the payload)

{ ---- small drawing helpers (all operate in the 32x32 icon space) ---- }

{ A single antialiased stroke with rounded caps. }
procedure Line(B: TBGRABitmap; x1, y1, x2, y2: single; w: single = STROKE);
begin
  B.DrawLineAntialias(x1, y1, x2, y2, INK, w, True);
end;

{ An antialiased outline (unfilled) rectangle. }
procedure RectOutline(B: TBGRABitmap; x1, y1, x2, y2: single; w: single = STROKE);
begin
  B.RectangleAntialias(x1, y1, x2, y2, INK, w);
end;

{ An antialiased outline rounded rectangle. }
procedure RoundRectOutline(B: TBGRABitmap; x1, y1, x2, y2, rx, ry: single;
  w: single = STROKE);
begin
  B.RoundRectAntialias(x1, y1, x2, y2, rx, ry, INK, w, []);
end;

{ An antialiased outline (unfilled) ellipse centred at (cx,cy). }
procedure Circle(B: TBGRABitmap; cx, cy, rx, ry: single; w: single = STROKE);
begin
  B.EllipseAntialias(cx, cy, rx, ry, INK, w);
end;

{ A small filled dot. }
procedure Dot(B: TBGRABitmap; cx, cy, r: single);
begin
  B.FillEllipseAntialias(cx, cy, r, r, INK);
end;

{ An open (not closed) antialiased polyline with rounded caps. }
procedure Poly(B: TBGRABitmap; const pts: array of TPointF; w: single = STROKE);
begin
  B.DrawPolyLineAntialias(pts, INK, w, False);
end;

{ A filled antialiased polygon. }
procedure FillPoly(B: TBGRABitmap; const pts: array of TPointF);
begin
  B.FillPolyAntialias(pts, INK);
end;

{ Build an arc as a run of TPointF sample points, centred at (cx,cy), radii
  (rx,ry), sweeping from angle a0 to a1 (radians, screen coords: y grows down).
  Used for the curved undo/redo arrows and the omega glyph — no arc primitive is
  relied upon, so behaviour is identical across BGRABitmap builds. }
function ArcPts(cx, cy, rx, ry, a0, a1: single; segs: Integer): ArrayOfTPointF;
var
  i: Integer;
  t: single;
begin
  Result := nil;
  if segs < 2 then segs := 2;
  SetLength(Result, segs + 1);
  for i := 0 to segs do
  begin
    t := a0 + (a1 - a0) * i / segs;
    Result[i] := PointF(cx + rx * cos(t), cy + ry * sin(t));
  end;
end;

{ Add a finished icon to the collection and free the working bitmap (AddBitmap
  duplicates, so the caller owns and must free ABmp). }
procedure Commit(AColl: TTyImageCollection; const AName: string; B: TBGRABitmap);
begin
  AColl.AddBitmap(AName, B);
  B.Free;
end;

{ Fresh transparent 32x32 canvas. }
function NewIcon: TBGRABitmap;
begin
  Result := TBGRABitmap.Create(ICON_SIZE, ICON_SIZE, BGRAPixelTransparent);
end;

{ ===================== individual icon painters ===================== }

// 1. blank document/page with a dog-eared (folded) top-right corner
procedure DrawNew(B: TBGRABitmap);
const
  fold = 7;   // size of the folded corner
begin
  // page body: left edge, bottom, right edge (stops at fold), and top (stops at fold)
  Poly(B, [PointF(8, 4), PointF(8, 28), PointF(24, 28),
           PointF(24, 4 + fold), PointF(24 - fold, 4), PointF(8, 4)]);
  // the folded corner triangle
  Poly(B, [PointF(24 - fold, 4), PointF(24 - fold, 4 + fold), PointF(24, 4 + fold)]);
end;

// 2. open folder with an angled open front flap
procedure DrawOpen(B: TBGRABitmap);
begin
  // back of the folder (with a small tab on the top-left)
  Poly(B, [PointF(5, 24), PointF(5, 9), PointF(12, 9), PointF(14, 12), PointF(26, 12),
           PointF(26, 15)]);
  // the open front flap (a parallelogram sweeping down-right)
  Poly(B, [PointF(5, 24), PointF(9, 15), PointF(30, 15), PointF(26, 24), PointF(5, 24)]);
end;

// 3. floppy disk: body, top-right notch, top slider, bottom label
procedure DrawSave(B: TBGRABitmap);
begin
  // disk body with a clipped top-right corner (the notch)
  Poly(B, [PointF(6, 6), PointF(22, 6), PointF(26, 10), PointF(26, 26),
           PointF(6, 26), PointF(6, 6)]);
  // top metal slider (near the top edge, offset from the notch)
  RectOutline(B, 11, 6, 20, 12, THIN);
  Dot(B, 18, 9, 1.3);   // the little slider hole
  // bottom label area
  RectOutline(B, 10, 17, 22, 26, THIN);
end;

// 4. floppy disk (like save) with a small right-arrow accent to imply "as"
procedure DrawSaveAs(B: TBGRABitmap);
begin
  // slightly smaller/shifted disk so the accent has room lower-right
  Poly(B, [PointF(5, 5), PointF(18, 5), PointF(22, 9), PointF(22, 22),
           PointF(5, 22), PointF(5, 5)]);
  RectOutline(B, 9, 5, 16, 10, THIN);
  RectOutline(B, 8, 14, 19, 22, THIN);
  // small right-arrow accent (lower-right)
  Line(B, 20, 26, 29, 26, THIN);
  Poly(B, [PointF(26, 23), PointF(29, 26), PointF(26, 29)], THIN);
end;

// 5. scissors: two ring handles at the bottom, blades crossing to a point at top
procedure DrawCut(B: TBGRABitmap);
begin
  // handle rings
  Circle(B, 10, 24, 4, 4, THIN);
  Circle(B, 22, 24, 4, 4, THIN);
  // blades crossing over each other up to a common point near the top
  Line(B, 13, 21, 24, 6, THIN);   // left ring -> upper right
  Line(B, 19, 21, 8, 6, THIN);    // right ring -> upper left
  Dot(B, 16, 15, 1.2);            // the pivot rivet
end;

// 6. copy: two overlapping rounded rectangles (a page behind a page)
procedure DrawCopy(B: TBGRABitmap);
begin
  RoundRectOutline(B, 6, 5, 20, 21, 2.5, 2.5, THIN);   // back page
  RoundRectOutline(B, 12, 11, 26, 27, 2.5, 2.5);       // front page
end;

// 7. clipboard: board + clip tab at top centre + a page on it
procedure DrawPaste(B: TBGRABitmap);
begin
  RoundRectOutline(B, 7, 6, 25, 28, 2.5, 2.5);   // the board
  // the metal clip tab at the top centre
  RoundRectOutline(B, 12, 3, 20, 9, 1.6, 1.6, THIN);
  // a page/lines on the clipboard
  Line(B, 11, 15, 21, 15, THIN);
  Line(B, 11, 19, 21, 19, THIN);
  Line(B, 11, 23, 18, 23, THIN);
end;

// 8. paint brush: diagonal handle with a filled brush head at the lower-left
procedure DrawPainter(B: TBGRABitmap);
begin
  // handle (upper-right to mid)
  Line(B, 28, 5, 15, 18, STROKE);
  // ferrule
  Line(B, 12, 15, 18, 21, THIN);
  // brush head (filled trapezoid) tapering down-left to the tip
  FillPoly(B, [PointF(13, 16), PointF(17, 20), PointF(11, 27), PointF(7, 25)]);
end;

// 9. undo: counter-clockwise curved arrow with the head at the left terminus
procedure DrawUndo(B: TBGRABitmap);
begin
  // top arc: from the right (~25.9,15.8) over the top to the left (~6.0,16.3)
  Poly(B, ArcPts(16, 17, 10, 8, -0.15, -3.05, 22), STROKE);
  // arrowhead at the left terminus, opening left/down into the curve
  Poly(B, [PointF(11, 15), PointF(5.5, 16), PointF(9, 21)], STROKE);
end;

// 10. redo: clockwise curved arrow with the head at the right terminus (mirror)
procedure DrawRedo(B: TBGRABitmap);
begin
  // mirror of undo across x=16: sweep over the top to the right (~26,16.6)
  Poly(B, ArcPts(16, 17, 10, 8, 3.2916, 6.2332, 22), STROKE);
  // arrowhead at the right terminus, opening right/down into the curve
  Poly(B, [PointF(21, 15), PointF(26.5, 16), PointF(23, 21)], STROKE);
end;

// 11. find: magnifying glass (lens + short diagonal handle lower-right)
procedure DrawFind(B: TBGRABitmap);
begin
  Circle(B, 14, 14, 7, 7);
  Line(B, 19.5, 19.5, 27, 27);   // handle
end;

// 12. replace: magnifying glass with two opposing horizontal arrows in the lens
procedure DrawReplace(B: TBGRABitmap);
begin
  Circle(B, 14, 14, 7.5, 7.5);
  Line(B, 20, 20, 27, 27);       // handle
  // upper arrow pointing right
  Line(B, 9, 12, 18, 12, THIN);
  Poly(B, [PointF(15.5, 9.5), PointF(18.5, 12), PointF(15.5, 14.5)], THIN);
  // lower arrow pointing left
  Line(B, 9, 17, 18, 17, THIN);
  Poly(B, [PointF(11.5, 14.5), PointF(8.5, 17), PointF(11.5, 19.5)], THIN);
end;

// 13. select-all: dashed outer marquee + a small solid inner rectangle
procedure DrawSelectAll(B: TBGRABitmap);
var
  x: single;
begin
  // dashed border (short segments around a 4..28 square)
  x := 5;
  while x < 27 do
  begin
    Line(B, x, 5, x + 2.5, 5, THIN);     // top
    Line(B, x, 27, x + 2.5, 27, THIN);   // bottom
    x := x + 5;
  end;
  x := 5;
  while x < 27 do
  begin
    Line(B, 5, x, 5, x + 2.5, THIN);     // left
    Line(B, 27, x, 27, x + 2.5, THIN);   // right
    x := x + 5;
  end;
  // solid inner selection block
  B.FillRoundRectAntialias(11, 11, 21, 21, 1.5, 1.5, INK);
end;

// 14. bullets: three filled dots on the left + three lines to the right
procedure DrawBullets(B: TBGRABitmap);
const
  ys: array[0..2] of single = (9, 16, 23);
var
  i: Integer;
begin
  for i := 0 to 2 do
  begin
    Dot(B, 8, ys[i], 2.0);
    Line(B, 14, ys[i], 27, ys[i], THIN);
  end;
end;

// 15. number list: short vertical tick marks on the left + three lines to the right
procedure DrawNumber(B: TBGRABitmap);
const
  ys: array[0..2] of single = (9, 16, 23);
var
  i: Integer;
begin
  for i := 0 to 2 do
  begin
    // a small vertical stroke (distinct from bullets' dots) as the "digit"
    Line(B, 8, ys[i] - 3, 8, ys[i] + 3, THIN);
    // a tiny foot so it reads as a numeral column
    Line(B, 6.5, ys[i] + 3, 9.5, ys[i] + 3, 1.3);
    Line(B, 14, ys[i], 27, ys[i], THIN);
  end;
end;

// 16. symbol: an omega (Ω) glyph built from an arc plus two feet
procedure DrawSymbol(B: TBGRABitmap);
var
  a: ArrayOfTPointF;
begin
  // the open ring of the omega: a near-full circle open at the bottom
  a := ArcPts(16, 15, 8, 8, 0.55 * 3.1416, 2.45 * 3.1416, 28);
  Poly(B, a, STROKE);
  // the two feet at the bottom
  Line(B, 6.5, 24, 13, 24, STROKE);
  Line(B, 19, 24, 25.5, 24, STROKE);
end;

// 17. calendar: rounded body + two top tabs + a divider under the header
procedure DrawDateTime(B: TBGRABitmap);
begin
  RoundRectOutline(B, 5, 7, 27, 27, 2.5, 2.5);
  // two hanging tabs
  Line(B, 11, 4, 11, 9, STROKE);
  Line(B, 21, 4, 21, 9, STROKE);
  // header divider
  Line(B, 5, 13, 27, 13, THIN);
  // a couple of day dots
  Dot(B, 11, 18, 1.1);
  Dot(B, 16, 18, 1.1);
  Dot(B, 21, 18, 1.1);
  Dot(B, 11, 23, 1.1);
  Dot(B, 16, 23, 1.1);
end;

// 18. table: outer rectangle divided into a 3x3 grid
procedure DrawTable(B: TBGRABitmap);
begin
  RectOutline(B, 5, 6, 27, 26, THIN);
  // vertical dividers
  Line(B, 12.3, 6, 12.3, 26, THIN);
  Line(B, 19.6, 6, 19.6, 26, THIN);
  // horizontal dividers
  Line(B, 5, 12.6, 27, 12.6, THIN);
  Line(B, 5, 19.3, 27, 19.3, THIN);
end;

// 19. crop: two overlapping right-angle "L" brackets forming a crop frame
procedure DrawCrop(B: TBGRABitmap);
begin
  // top-left L, extended so its arms cross the frame
  Poly(B, [PointF(9, 3), PointF(9, 23), PointF(29, 23)], STROKE);
  // bottom-right L (mirrored)
  Poly(B, [PointF(23, 29), PointF(23, 9), PointF(3, 9)], STROKE);
end;

// 20. new window: a titled window + a small "+" accent lower-right
procedure DrawNewWindow(B: TBGRABitmap);
begin
  RectOutline(B, 5, 6, 23, 24, THIN);
  Line(B, 5, 11, 23, 11, THIN);   // title bar strip
  Dot(B, 8, 8.5, 0.9);            // title-bar button dots
  Dot(B, 11, 8.5, 0.9);
  // "+" accent bottom-right
  Line(B, 26, 20, 26, 30, STROKE);
  Line(B, 21, 25, 31, 25, STROKE);
end;

// 21. arrange: two rectangles side by side
procedure DrawArrange(B: TBGRABitmap);
begin
  RectOutline(B, 4, 7, 15, 25, THIN);
  RectOutline(B, 17, 7, 28, 25, THIN);
  // little title strips
  Line(B, 4, 11, 15, 11, THIN);
  Line(B, 17, 11, 28, 11, THIN);
end;

// 22. zoom in: magnifying glass with a "+" in the lens
procedure DrawZoomIn(B: TBGRABitmap);
begin
  Circle(B, 14, 14, 7.5, 7.5);
  Line(B, 20, 20, 27, 27);        // handle
  Line(B, 14, 10, 14, 18, THIN);  // vertical of +
  Line(B, 10, 14, 18, 14, THIN);  // horizontal of +
end;

// 23. zoom out: magnifying glass with a "-" in the lens
procedure DrawZoomOut(B: TBGRABitmap);
begin
  Circle(B, 14, 14, 7.5, 7.5);
  Line(B, 20, 20, 27, 27);        // handle
  Line(B, 10, 14, 18, 14, THIN);  // the minus
end;

// 24. zoom 100 (actual size): magnifying glass with a centred dot in the lens
procedure DrawZoom100(B: TBGRABitmap);
begin
  Circle(B, 14, 14, 7.5, 7.5);
  Line(B, 20, 20, 27, 27);        // handle
  Dot(B, 14, 14, 2.0);            // "fit / actual size" dot
end;

// 25. close: an X (two crossed diagonals)
procedure DrawClose(B: TBGRABitmap);
begin
  Line(B, 8, 8, 24, 24, STROKE);
  Line(B, 24, 8, 8, 24, STROKE);
end;

// 26. exit: power symbol — near-full circle open at top + vertical line through the gap
procedure DrawExit(B: TBGRABitmap);
var
  a: ArrayOfTPointF;
begin
  // ring open at the top (gap centred on the 12-o'clock position)
  a := ArcPts(16, 17, 8, 8, -0.35 * 3.1416, 1.35 * 3.1416, 26);
  Poly(B, a, STROKE);
  // the vertical line through the top gap
  Line(B, 16, 5, 16, 16, STROKE);
end;

// 27. folder: a closed folder with a tab on the top-left
procedure DrawFolder(B: TBGRABitmap);
begin
  Poly(B, [PointF(5, 25), PointF(5, 9), PointF(12, 9), PointF(15, 12),
           PointF(27, 12), PointF(27, 25), PointF(5, 25)], STROKE);
end;

// 28. recent: a clock — circle with an hour and a minute hand
procedure DrawRecent(B: TBGRABitmap);
begin
  Circle(B, 16, 16, 11, 11);
  Line(B, 16, 16, 16, 8, THIN);    // minute hand (up)
  Line(B, 16, 16, 22, 18, THIN);   // hour hand (down-right)
  Dot(B, 16, 16, 1.2);             // centre pin
end;

{ ===================== the public builder ===================== }

procedure BuildEditorIcons(AColl: TTyImageCollection);
var
  B: TBGRABitmap;
begin
  if AColl = nil then Exit;

  // Each icon: fresh transparent canvas -> paint -> commit (dup + free).
  B := NewIcon; DrawNew(B);        Commit(AColl, 'new', B);
  B := NewIcon; DrawOpen(B);       Commit(AColl, 'open', B);
  B := NewIcon; DrawSave(B);       Commit(AColl, 'save', B);
  B := NewIcon; DrawSaveAs(B);     Commit(AColl, 'saveas', B);
  B := NewIcon; DrawCut(B);        Commit(AColl, 'cut', B);
  B := NewIcon; DrawCopy(B);       Commit(AColl, 'copy', B);
  B := NewIcon; DrawPaste(B);      Commit(AColl, 'paste', B);
  B := NewIcon; DrawPainter(B);    Commit(AColl, 'painter', B);
  B := NewIcon; DrawUndo(B);       Commit(AColl, 'undo', B);
  B := NewIcon; DrawRedo(B);       Commit(AColl, 'redo', B);
  B := NewIcon; DrawFind(B);       Commit(AColl, 'find', B);
  B := NewIcon; DrawReplace(B);    Commit(AColl, 'replace', B);
  B := NewIcon; DrawSelectAll(B);  Commit(AColl, 'selectall', B);
  B := NewIcon; DrawBullets(B);    Commit(AColl, 'bullets', B);
  B := NewIcon; DrawNumber(B);     Commit(AColl, 'number', B);
  B := NewIcon; DrawSymbol(B);     Commit(AColl, 'symbol', B);
  B := NewIcon; DrawDateTime(B);   Commit(AColl, 'datetime', B);
  B := NewIcon; DrawTable(B);      Commit(AColl, 'table', B);
  B := NewIcon; DrawCrop(B);       Commit(AColl, 'crop', B);
  B := NewIcon; DrawNewWindow(B);  Commit(AColl, 'newwindow', B);
  B := NewIcon; DrawArrange(B);    Commit(AColl, 'arrange', B);
  B := NewIcon; DrawZoomIn(B);     Commit(AColl, 'zoomin', B);
  B := NewIcon; DrawZoomOut(B);    Commit(AColl, 'zoomout', B);
  B := NewIcon; DrawZoom100(B);    Commit(AColl, 'zoom100', B);
  B := NewIcon; DrawClose(B);      Commit(AColl, 'close', B);
  B := NewIcon; DrawExit(B);       Commit(AColl, 'exit', B);
  B := NewIcon; DrawFolder(B);     Commit(AColl, 'folder', B);
  B := NewIcon; DrawRecent(B);     Commit(AColl, 'recent', B);
end;

initialization
  INK := BGRA(0, 0, 0, 255);   // opaque black — the alpha mask payload

end.
