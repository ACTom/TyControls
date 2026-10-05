unit tyControls.FontUnits;
{$mode objfpc}{$H+}
{ A FONT SIZE IN PIXELS, carried in the same Integer every text routine takes.

  A logical font size is points -- what a theme writes, and what TTyPainter
  turns into a pixel height as pt * 96/72 at 96 DPI. Some callers are handed
  pixels by their author instead: a chart option's `fontSize: 14` is CSS px,
  and 14px is 10.5pt, which no whole point holds. Such a size is encoded as
  cTyFontPxBase plus hundredths of a pixel -- still positive, so every
  "size > 0 means drawn" test keeps working, and far above any point size a
  theme writes. The two font-configuration procedures in tyControls.Painter
  decode it; everything in between passes it through untouched.

  A unit of its own because both sides need it: the painter, which is LCL, and
  the chart's pure units, which must not reach the LCL. SysUtils and Math
  only. }
interface

const
  cTyFontPxBase = 1000000;

{ APx pixels as a logical size; 0 (no size -- the caller's default stands)
  for a NaN or a size that is not positive. }
function TyFontSizeFromPx(APx: Double): Integer;
{ True when the logical size carries pixels rather than points. }
function TyFontSizeIsPx(AFontSizeLogical: Integer): Boolean;
{ The size in pixels at 96 DPI: a point size times 96/72, a pixel size as
  encoded. Nothing is substituted for a size of 0 -- that is the caller's to
  decide. }
function TyFontPxOf(AFontSizeLogical: Integer): Double;

implementation

uses Math;

function TyFontSizeFromPx(APx: Double): Integer;
begin
  if IsNan(APx) or (APx <= 0) then Exit(0);
  { ten thousand pixels is a size nobody means, and every size past it is
    that one -- the Integer must not overflow }
  if APx > 10000 then APx := 10000;
  Result := cTyFontPxBase + Round(APx * 100);
  { a size too small to carry is still a size }
  if Result = cTyFontPxBase then Result := cTyFontPxBase + 1;
end;

function TyFontSizeIsPx(AFontSizeLogical: Integer): Boolean;
begin
  Result := AFontSizeLogical > cTyFontPxBase;
end;

function TyFontPxOf(AFontSizeLogical: Integer): Double;
begin
  if TyFontSizeIsPx(AFontSizeLogical) then
    Result := (AFontSizeLogical - cTyFontPxBase) / 100
  else
    Result := AFontSizeLogical * 96 / 72;
end;

end.
