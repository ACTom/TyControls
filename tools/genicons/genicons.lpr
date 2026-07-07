program genicons;
{$mode objfpc}{$H+}
uses
  Interfaces, SysUtils, BGRABitmap, BGRABitmapTypes;

const
  ST = 1.7;   // stroke width at the 24px base; scales with GScale

var
  Ink, Acc, Faint: TBGRAPixel;
  { Coordinates in the glyph routines are authored in a 24-unit space. GScale maps
    that to the actual output size (1.0 -> 24px, 1.5 -> 36px, 2.0 -> 48px) so each
    HiDPI variant is RENDERED crisply at native size, not upscaled from 24px. }
  GScale: single = 1.0;

function ScalePts(const pts: array of TPointF): ArrayOfTPointF;
var i: Integer;
begin
  SetLength(Result, Length(pts));
  for i := 0 to High(pts) do
    Result[i] := PointF(pts[i].x * GScale, pts[i].y * GScale);
end;

procedure Line(b: TBGRABitmap; x1, y1, x2, y2: single; c: TBGRAPixel; w: single = ST);
begin
  b.DrawLineAntialias(x1*GScale, y1*GScale, x2*GScale, y2*GScale, c, w*GScale);
end;

procedure RRect(b: TBGRABitmap; l, t, r, bot, rad: single; c: TBGRAPixel; w: single = ST);
begin
  b.RoundRectAntialias(l*GScale, t*GScale, r*GScale, bot*GScale, rad*GScale, rad*GScale, c, w*GScale);
end;

procedure FillRRect(b: TBGRABitmap; l, t, r, bot, rad: single; c: TBGRAPixel);
begin
  b.FillRoundRectAntialias(l*GScale, t*GScale, r*GScale, bot*GScale, rad*GScale, rad*GScale, c);
end;

procedure Circ(b: TBGRABitmap; cx, cy, rad: single; c: TBGRAPixel; w: single = ST);
begin
  b.EllipseAntialias(cx*GScale, cy*GScale, rad*GScale, rad*GScale, c, w*GScale);
end;

procedure FillCirc(b: TBGRABitmap; cx, cy, rad: single; c: TBGRAPixel);
begin
  b.FillEllipseAntialias(cx*GScale, cy*GScale, rad*GScale, rad*GScale, c);
end;

procedure PolyL(b: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel; w: single = ST);
begin
  b.DrawPolyLineAntialias(ScalePts(pts), c, w*GScale);
end;

procedure FillPolyG(b: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel);
begin
  b.FillPolyAntialias(ScalePts(pts), c);
end;

procedure GButton(b: TBGRABitmap); begin RRect(b,3,7,21,17,3,Ink); Line(b,8,12,16,12,Acc,2.4); end;
procedure GLabel(b: TBGRABitmap); begin PolyL(b,[PointF(6,18),PointF(12,6),PointF(18,18)],Ink); Line(b,8.6,13.2,15.4,13.2,Ink); end;
procedure GEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Line(b,7,9.5,7,14.5,Acc,2); Line(b,10,12,16,12,Faint,1.3); end;
{ TTyNumericEdit: an edit box with accent digit bars + a decimal dot }
procedure GNumericEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Line(b,8,10,8,14,Acc,1.6); Line(b,11,10,11,14,Acc,1.6); Line(b,14,10,14,14,Acc,1.6); FillCirc(b,16.6,13.4,0.95,Acc); end;
{ TTyCurrencyEdit: an edit box with an accent coin + vertical bar ($) }
procedure GCurrencyEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Circ(b,12,12,3.4,Acc,1.6); Line(b,12,7.6,12,16.4,Acc,1.6); end;
{ TTyMaskEdit: an edit box with slot underscores (first filled = accent, rest faint) }
procedure GMaskEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Line(b,6,14.5,9,14.5,Acc,1.5); Line(b,11,14.5,14,14.5,Faint,1.5); Line(b,16,14.5,19,14.5,Faint,1.5); end;
{ TTyURLEdit: an edit box with an accent open-arrow (->) }
procedure GURLEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Line(b,8,12,15,12,Acc,1.6); PolyL(b,[PointF(12.5,9.5),PointF(15,12),PointF(12.5,14.5)],Acc,1.6); end;
{ TTyComboEdit: an edit box with an accent caret + a drop chevron on the right }
procedure GComboEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Line(b,6,9.5,6,14.5,Acc,1.6); PolyL(b,[PointF(14,10.8),PointF(16.5,13.4),PointF(19,10.8)],Ink,1.4); end;
{ TTyTrackEdit: an edit box with a mini slider (faint track + accent thumb) }
procedure GTrackEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Line(b,6,12,18,12,Faint,1.4); FillCirc(b,13,12,2,Acc); end;
{ TTyColorBox: a combo box with an accent colour swatch + a drop chevron }
procedure GColorBox(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); FillRRect(b,6,9.5,11,14.5,1,Acc); PolyL(b,[PointF(14,10.8),PointF(16.5,13.4),PointF(19,10.8)],Ink,1.4); end;
{ TTyColorComboBox: a colour combo with a "+" (more…) + a drop chevron }
procedure GColorComboBox(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); FillRRect(b,5.5,9.5,9.5,14.5,1,Acc); Line(b,12,12,14.5,12,Ink,1.2); Line(b,13.25,10.75,13.25,13.25,Ink,1.2); PolyL(b,[PointF(16,10.8),PointF(17.5,12.6),PointF(19,10.8)],Ink,1.3); end;
{ TTyMRUComboBox: a combo box with a small clock (history) + a drop chevron }
procedure GMRUComboBox(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Circ(b,8,12,2.8,Acc,1.2); Line(b,8,12,8,10.4,Acc,1); Line(b,8,12,9.2,12.6,Acc,1); PolyL(b,[PointF(15,10.8),PointF(17,13),PointF(19,10.8)],Ink,1.3); end;
{ TTyComboBoxEx: a combo box with an image tile + two text lines + a drop chevron }
procedure GComboBoxEx(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); FillRRect(b,5,9.5,9,13.5,0.8,Acc); Line(b,10.5,10.6,15,10.6,Faint,1.2); Line(b,10.5,13,14,13,Faint,1.2); PolyL(b,[PointF(16.5,10.8),PointF(18,12.6),PointF(19.5,10.8)],Ink,1.2); end;
{ TTyOfficeListBox: a list box with a tinted group-header band + item rows }
procedure GOfficeListBox(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); FillRRect(b,4,6,20,9,0.5,Faint); Line(b,6,7.5,13,7.5,Ink,1.4); Line(b,6,12,18,12,Faint,1.1); Line(b,6,15,18,15,Faint,1.1); Line(b,6,18,14,18,Faint,1.1); end;
{ TTyOfficeComboBox: a combo box with a tinted group-header hint band + a drop chevron }
procedure GOfficeComboBox(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); FillRRect(b,5,9,12,11,0.4,Faint); Line(b,5,13.4,12,13.4,Faint,1.1); PolyL(b,[PointF(15.5,10.8),PointF(17.5,13),PointF(19.5,10.8)],Ink,1.3); end;
{ TTyColorGrid: a 3x3 grid of colour swatches with one selected (accent ring) }
procedure GColorGrid(b: TBGRABitmap); begin FillRRect(b,5,5,9.5,9.5,0.6,Acc); FillRRect(b,10.5,5,15,9.5,0.6,Faint); FillRRect(b,16,5,20.5,9.5,0.6,Ink); FillRRect(b,5,10.5,9.5,15,0.6,Faint); FillRRect(b,10.5,10.5,15,15,0.6,Ink); FillRRect(b,16,10.5,20.5,15,0.6,Acc); FillRRect(b,5,16,9.5,20.5,0.6,Ink); FillRRect(b,10.5,16,15,20.5,0.6,Acc); FillRRect(b,16,16,20.5,20.5,0.6,Faint); RRect(b,10,10,15.5,15.5,0.8,Acc,1.6); end;
{ TTyLColorPicker: a vertical brightness bar (light->accent->dark) + a marker triangle }
procedure GLColorPicker(b: TBGRABitmap); begin RRect(b,8,3,16,21,1.5,Ink); FillRRect(b,9,4,15,8.5,0,Faint); FillRRect(b,9,8.5,15,14,0,Acc); FillRRect(b,9,14,15,20,0,Ink); Line(b,7,11,17,11,Ink,1.6); FillPolyG(b,[PointF(17.6,11),PointF(19,9.7),PointF(19,12.3)],Acc); end;
{ TTyHSColorPicker: a hue/sat square with an accent gradient corner + a crosshair marker }
procedure GHSColorPicker(b: TBGRABitmap); begin RRect(b,4,4,20,20,2,Ink); FillRRect(b,5,5,19,19,1,Faint); FillPolyG(b,[PointF(5,5),PointF(15,5),PointF(5,15)],Acc); Circ(b,9.5,9.5,2.2,Ink,1.4); Line(b,9.5,6.4,9.5,12.6,Ink,0.9); Line(b,6.4,9.5,12.6,9.5,Ink,0.9); end;
{ TTyAdvancedListBox: rich rows = an image tile + a title line + a dim subtitle line }
procedure GAdvancedListBox(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); FillRRect(b,5,6,9,10,0.6,Acc); Line(b,10.5,7,18,7,Ink,1.3); Line(b,10.5,9.2,15,9.2,Faint,1); FillRRect(b,5,13,9,17,0.6,Faint); Line(b,10.5,14,18,14,Ink,1.3); Line(b,10.5,16.2,15,16.2,Faint,1); end;
{ TTyAdvancedComboBox: a combo box with an image tile + title + subtitle + a drop chevron }
procedure GAdvancedComboBox(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); FillRRect(b,5,9.5,9,13.5,0.6,Acc); Line(b,10.5,10.6,15,10.6,Ink,1.3); Line(b,10.5,12.8,13.5,12.8,Faint,1); PolyL(b,[PointF(16.5,10.8),PointF(18,12.6),PointF(19.5,10.8)],Ink,1.2); end;
{ TTyCheckComboBox: a combo box with a ticked checkbox + a drop chevron }
procedure GCheckComboBox(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); RRect(b,5.5,9.5,9,13,0.6,Ink); PolyL(b,[PointF(6,11.2),PointF(6.9,12.1),PointF(8.4,10.3)],Acc,1.3); PolyL(b,[PointF(15.5,10.8),PointF(17.5,13),PointF(19.5,10.8)],Ink,1.3); end;
{ TTyValueListEditor: a 2-column name/value grid — a divider + key tiles left, value lines right }
procedure GValueListEditor(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); Line(b,10,5,10,19,Faint,1); FillRRect(b,5,7,8.5,8.8,0.3,Acc); Line(b,11.5,7.9,18,7.9,Faint,1.1); FillRRect(b,5,11,8.5,12.8,0.3,Faint); Line(b,11.5,11.9,16,11.9,Faint,1.1); FillRRect(b,5,15,8.5,16.8,0.3,Faint); Line(b,11.5,15.9,17,15.9,Faint,1.1); end;
{ TTyCalculator: a calculator body — a display band over a grid of button dots (right col = ops) }
procedure GCalculator(b: TBGRABitmap); begin RRect(b,5,3,19,21,2,Ink); FillRRect(b,6.5,4.5,17.5,8,0.6,Faint); FillCirc(b,8,11,0.9,Ink); FillCirc(b,10.5,11,0.9,Ink); FillCirc(b,13,11,0.9,Ink); FillCirc(b,15.5,11,0.9,Acc); FillCirc(b,8,14,0.9,Ink); FillCirc(b,10.5,14,0.9,Ink); FillCirc(b,13,14,0.9,Ink); FillCirc(b,15.5,14,0.9,Acc); FillCirc(b,8,17,0.9,Ink); FillCirc(b,10.5,17,0.9,Ink); FillCirc(b,13,17,0.9,Ink); FillCirc(b,15.5,17,0.9,Acc); end;
{ TTyCalcEdit: a numeric edit with a trailing 2x2 keypad (calculator) button }
procedure GCalcEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); Line(b,6,12,10,12,Ink,1.4); FillCirc(b,14.6,10.6,0.8,Acc); FillCirc(b,17.4,10.6,0.8,Acc); FillCirc(b,14.6,13.4,0.8,Acc); FillCirc(b,17.4,13.4,0.8,Acc); end;
{ TTyCalcCurrencyEdit: a currency (¥) edit with a trailing calculator button }
procedure GCalcCurrencyEdit(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); PolyL(b,[PointF(5,9.5),PointF(6.6,11.6),PointF(8.2,9.5)],Acc,1.1); Line(b,6.6,11.6,6.6,14.5,Acc,1.1); Line(b,5.2,12.6,8,12.6,Acc,1); Line(b,5.2,13.8,8,13.8,Acc,1); FillCirc(b,14.6,10.6,0.8,Ink); FillCirc(b,17.4,10.6,0.8,Ink); FillCirc(b,14.6,13.4,0.8,Ink); FillCirc(b,17.4,13.4,0.8,Ink); end;
{ TTyColorListBox: a list box with swatch rows }
procedure GColorListBox(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); FillRRect(b,5.5,7,8.5,10,0.6,Acc); Line(b,10.5,8.5,18,8.5,Faint,1.2); FillRRect(b,5.5,10.8,8.5,13.8,0.6,Ink); Line(b,10.5,12.3,18,12.3,Faint,1.2); FillRRect(b,5.5,14.6,8.5,17.6,0.6,Faint); Line(b,10.5,16.1,18,16.1,Faint,1.2); end;
{ TTyFontComboBox: a combo box with an "A" glyph + a drop chevron }
procedure GFontComboBox(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); PolyL(b,[PointF(6,15),PointF(8.5,9),PointF(11,15)],Acc,1.6); Line(b,7,12.6,10,12.6,Acc,1.2); PolyL(b,[PointF(14,10.8),PointF(16.5,13.4),PointF(19,10.8)],Ink,1.4); end;
{ TTyFontListBox: a list box with "A" rows }
procedure GFontListBox(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); PolyL(b,[PointF(6,10),PointF(7.4,7),PointF(8.8,10)],Acc,1.2); Line(b,11,8.5,18,8.5,Faint,1.1); PolyL(b,[PointF(6,14.6),PointF(7.4,11.6),PointF(8.8,14.6)],Ink,1.2); Line(b,11,13.1,18,13.1,Faint,1.1); end;
{ TTyFontSizeComboBox: a combo box with a small "A" + a big "A" + a drop chevron }
procedure GFontSizeComboBox(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); PolyL(b,[PointF(6,14),PointF(7.3,10.8),PointF(8.6,14)],Acc,1.2); PolyL(b,[PointF(9.6,14.5),PointF(11.6,8.5),PointF(13.6,14.5)],Acc,1.5); PolyL(b,[PointF(15.2,11),PointF(17,13),PointF(18.8,11)],Ink,1.3); end;
{ TTyCheckListBox: a list box with a checked row + an unchecked row }
procedure GCheckListBox(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); RRect(b,5.5,7,8.5,10,0.6,Ink); PolyL(b,[PointF(6,8.6),PointF(7,9.6),PointF(8,7.6)],Acc,1.3); Line(b,11,8.6,18,8.6,Faint,1.1); RRect(b,5.5,13,8.5,16,0.6,Ink); Line(b,11,14.6,18,14.6,Faint,1.1); end;
procedure GCheckBox(b: TBGRABitmap); begin RRect(b,4,4,20,20,3,Ink); PolyL(b,[PointF(8,12.4),PointF(11,15.4),PointF(16,8.6)],Acc,2.2); end;
procedure GRadio(b: TBGRABitmap); begin Circ(b,12,12,8,Ink); FillCirc(b,12,12,3.1,Acc); end;
procedure GCombo(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); PolyL(b,[PointF(13.5,10.8),PointF(16,13.4),PointF(18.5,10.8)],Ink); end;
procedure GToggle(b: TBGRABitmap); begin RRect(b,3,8,21,16,4,Ink); FillCirc(b,16.5,12,2.7,Acc); end;
procedure GTrack(b: TBGRABitmap); begin Line(b,3,12,21,12,Ink); Line(b,6,10.4,6,13.6,Ink); Line(b,18,10.4,18,13.6,Ink); FillCirc(b,12,12,3,Acc); end;
procedure GProgress(b: TBGRABitmap); begin RRect(b,3,9,21,15,3,Ink); FillRRect(b,3,9,13,15,3,Acc); end;
{ TTyGauge: a speedometer — upper scale arc + accent needle + hub }
procedure GGauge(b: TBGRABitmap); begin PolyL(b,[PointF(3.5,15),PointF(5,10.5),PointF(8.5,7.5),PointF(12,6.5),PointF(15.5,7.5),PointF(19,10.5),PointF(20.5,15)],Ink,1.8); Line(b,12,16,16.5,9,Acc,2); FillCirc(b,12,16,1.6,Acc); end;
{ TTyCircularProgress: a faint track ring + a ~3/4 accent progress arc }
procedure GCircularProgress(b: TBGRABitmap); begin Circ(b,12,12,7,Faint,2); PolyL(b,[PointF(12,5),PointF(16.9,7),PointF(19,12),PointF(16.9,17),PointF(12,19),PointF(7.1,17)],Acc,2.4); end;
{ TTyActivityIndicator: a spinning accent "C" arc (no track) }
procedure GActivityIndicator(b: TBGRABitmap); begin PolyL(b,[PointF(7.1,17),PointF(12,19),PointF(16.9,17),PointF(19,12),PointF(16.9,7),PointF(12,5)],Acc,2.6); end;
{ TTyActivityBar: an indeterminate linear bar — track outline + a mid-track accent segment (marching) }
procedure GActivityBar(b: TBGRABitmap); begin RRect(b,3,9,21,15,3,Ink); FillRRect(b,9,9,15,15,3,Acc); end;
{ TTyMeter: a dial arc with tick marks + accent needle + hub }
procedure GMeter(b: TBGRABitmap); begin PolyL(b,[PointF(4,14),PointF(6,9),PointF(12,6.5),PointF(18,9),PointF(20,14)],Ink,1.6); Line(b,4,14,5.4,13.3,Ink,1.2); Line(b,12,6.5,12,8,Ink,1.2); Line(b,20,14,18.6,13.3,Ink,1.2); Line(b,12,16,15.5,9.5,Acc,2); FillCirc(b,12,16,1.6,Acc); end;
{ TTyLevelMeter: a VU bar — track + lit accent segments + a peak line }
procedure GLevelMeter(b: TBGRABitmap); begin RRect(b,3,8,21,16,2,Ink); FillRRect(b,5,10,7.5,14,0.8,Acc); FillRRect(b,8.5,10,11,14,0.8,Acc); FillRRect(b,12,10,14.5,14,0.8,Acc); FillRRect(b,15.5,10,18,14,0.8,Faint); Line(b,19.5,8,19.5,16,Acc,1.6); end;
{ TTyDial: a knob body + accent pointer + hub }
procedure GDial(b: TBGRABitmap); begin FillCirc(b,12,12,9,Faint); Circ(b,12,12,9,Ink); Line(b,12,12,6,6,Acc); FillCirc(b,12,12,2,Ink); end;
{ TTyAnalogClock: a face with 4 ticks + hour/minute/accent-second hands + hub }
procedure GAnalogClock(b: TBGRABitmap); begin Circ(b,12,12,8.5,Ink,1.4); Line(b,12,4.5,12,6,Ink,1); Line(b,12,18,12,19.5,Ink,1); Line(b,4.5,12,6,12,Ink,1); Line(b,18,12,19.5,12,Ink,1); Line(b,12,12,12,7.5,Ink,1.6); Line(b,12,12,15.5,12,Ink,1.4); Line(b,12,12,9,15.5,Acc,1); FillCirc(b,12,12,1.4,Acc); end;
{ TTySparkline: an accent trend polyline + last-point dot over a faint baseline }
procedure GSparkline(b: TBGRABitmap); begin PolyL(b,[PointF(4,15),PointF(7,11),PointF(10,13),PointF(13,6),PointF(16,10),PointF(20,7)],Acc,2); FillCirc(b,20,7,1.8,Acc); Line(b,3,19,21,19,Faint,1.2); end;
{ TTyRating: a single filled accent star }
procedure GRating(b: TBGRABitmap); begin FillPolyG(b,[PointF(12,3.8),PointF(13.94,9.33),PointF(19.8,9.47),PointF(15.14,13.02),PointF(16.82,18.63),PointF(12,15.3),PointF(7.18,18.63),PointF(8.86,13.02),PointF(4.2,9.47),PointF(10.06,9.33)],Acc); end;
{ TTyGearDial: a gear body (teeth around the rim) + accent pointer + hub }
procedure GGearDial(b: TBGRABitmap); var i: Integer; a, cx, cy, rr, tr: Double; begin cx:=12; cy:=12; rr:=8; tr:=10.5; for i:=0 to 7 do begin a:=i*Pi/4; Line(b, cx+rr*Cos(a), cy+rr*Sin(a), cx+tr*Cos(a), cy+tr*Sin(a), Ink, 2.2); end; FillCirc(b,12,12,8,Faint); Circ(b,12,12,8,Ink); Circ(b,12,12,4.6,Ink); Line(b,12,12,6.5,6.5,Acc); FillCirc(b,12,12,1.8,Acc); end;
{ TTyGearActivityIndicator: a spinning accent gear (teeth + disc, faint hub, no pointer) }
procedure GGearActivityIndicator(b: TBGRABitmap); var i: Integer; a, cx, cy, rr, tr: Double; begin cx:=12; cy:=12; rr:=7; tr:=9.5; for i:=0 to 7 do begin a:=i*Pi/4+0.2; Line(b, cx+rr*Cos(a), cy+rr*Sin(a), cx+tr*Cos(a), cy+tr*Sin(a), Acc, 2.4); end; FillCirc(b,12,12,7,Acc); FillCirc(b,12,12,3,Faint); end;
{ TTyUpDown: stacked up/down spin buttons — a box split in two with accent arrows }
procedure GUpDown(b: TBGRABitmap); begin RRect(b,7,3,17,21,3,Ink); Line(b,7,12,17,12,Ink,1.2); FillPolyG(b,[PointF(12,6),PointF(14.6,9.4),PointF(9.4,9.4)],Acc); FillPolyG(b,[PointF(12,18),PointF(14.6,14.6),PointF(9.4,14.6)],Acc); end;
{ TTyLinkLabel: a chain link + an accent underline }
procedure GLinkLabel(b: TBGRABitmap); begin Circ(b,9,10,3,Ink,1.8); Circ(b,15,10,3,Ink,1.8); Line(b,10.5,10,13.5,10,Ink,1.8); Line(b,4,17,20,17,Acc,1.6); end;
{ TTyShadowLabel: an "A" with a faint offset shadow "A" behind it }
procedure GShadowLabel(b: TBGRABitmap); begin PolyL(b,[PointF(7.6,19),PointF(13.6,7),PointF(19.6,19)],Faint); Line(b,10.2,14.2,17,14.2,Faint); PolyL(b,[PointF(6,18),PointF(12,6),PointF(18,18)],Ink); Line(b,8.6,13.2,15.4,13.2,Ink); end;
{ TTyGlowLabel: an "A" over a soft accent halo }
procedure GGlowLabel(b: TBGRABitmap); begin FillCirc(b,12,13,7,Faint); PolyL(b,[PointF(6,18),PointF(12,6),PointF(18,18)],Ink); Line(b,8.6,13.2,15.4,13.2,Ink); end;
{ TTyHint: a tooltip bubble with a tail + two text lines }
procedure GHint(b: TBGRABitmap); begin FillRRect(b,3,4,21,16,3,Faint); FillPolyG(b,[PointF(7,16),PointF(7,20),PointF(12,16)],Faint); RRect(b,3,4,21,16,3,Ink); Line(b,6,9,18,9,Ink,1.5); Line(b,6,12,14,12,Ink,1.5); end;
{ TTyBalloonHint: a callout with an accent icon dot + title/body lines + tail }
procedure GBalloonHint(b: TBGRABitmap); begin FillRRect(b,3,3,21,15,3,Faint); FillPolyG(b,[PointF(8,15),PointF(8,20),PointF(13,15)],Faint); RRect(b,3,3,21,15,3,Ink); FillCirc(b,8,9,2.6,Acc); Line(b,12,8,18,8,Ink,1.5); Line(b,12,11,17,11,Ink,1.4); end;
{ TTyIconFont: a glyph tile — a filled rounded frame with an accent asterisk (a font of symbols) }
procedure GIconFont(b: TBGRABitmap); begin FillRRect(b,3,3,21,21,4,Faint); RRect(b,3,3,21,21,4,Ink); Line(b,12,7,12,17,Acc,1.8); Line(b,7.5,9.5,16.5,14.5,Acc,1.8); Line(b,16.5,9.5,7.5,14.5,Acc,1.8); end;
{ TTyCharImage: a rounded frame with an accent 5-point star (a single glyph char as an image) }
procedure GCharImage(b: TBGRABitmap); begin RRect(b,3,3,21,21,4,Ink,2); FillPolyG(b,[PointF(12,6),PointF(13.6,10.1),PointF(18,10.4),PointF(14.6,13.2),PointF(15.7,17.5),PointF(12,15),PointF(8.3,17.5),PointF(9.4,13.2),PointF(6,10.4),PointF(10.4,10.1)],Acc); end;
{ TTyGlyphImageList: two overlapping glyph tiles, the front carrying an accent mark }
procedure GGlyphImageList(b: TBGRABitmap); begin FillRRect(b,3,3,16,16,3,Faint); RRect(b,3,3,16,16,3,Ink,1.2); Line(b,9.5,4,9.5,15,Ink,1); Line(b,4,9.5,15,9.5,Ink,1); FillRRect(b,8,8,21,21,3,Faint); RRect(b,8,8,21,21,3,Ink,1.2); PolyL(b,[PointF(11,15),PointF(13.5,18),PointF(18,12)],Acc,1.6); FillCirc(b,18.5,10.5,1.6,Acc); end;
{ TTyImage: a rounded photo frame with an accent sun + a mountain silhouette }
procedure GImage(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); FillCirc(b,7.5,9,2,Acc); PolyL(b,[PointF(4,18),PointF(9,12),PointF(12,15),PointF(16,9),PointF(20,18)],Ink); end;
{ TTyImageCollection: a stack of overlapping photo tiles (mountain + sun in the front) }
procedure GImageCollection(b: TBGRABitmap);
begin
  FillRRect(b,9,5,22,15,2,Faint); RRect(b,9,5,22,15,2,Ink,1);
  FillRRect(b,5,9,18,19,2,Acc);   RRect(b,5,9,18,19,2,Ink,1);
  FillCirc(b,9,12,1.4,Faint);
  FillPolyG(b,[PointF(6,18),PointF(11,13),PointF(17,18)],Ink);
end;
{ TTyVirtualImageList: a list of image rows — a thumbnail square + a label line each }
procedure GVirtualImageList(b: TBGRABitmap);
var y: Integer;
begin
  for y := 0 to 2 do
  begin
    FillRRect(b,4,5+y*6,9,10+y*6,1,Acc); RRect(b,4,5+y*6,9,10+y*6,1,Ink,1);
    Line(b,12,7+y*6,20,7+y*6,Ink,1);
  end;
end;
{ TTyGlyphButton: a rounded command button — accent icon square on the left + caption lines }
procedure GGlyphButton(b: TBGRABitmap); begin RRect(b,3,7,21,17,3,Ink); FillRRect(b,6,10,11,15,1.5,Acc); Line(b,13,11,18,11,Ink,1.4); Line(b,13,14,17,14,Ink,1.4); end;
{ TTyGlyphContainerButton: a tall ribbon button — big accent icon on top over a caption line }
procedure GGlyphContainerButton(b: TBGRABitmap); begin RRect(b,6,3,18,21,3,Ink); FillRRect(b,9,6,15,12,1.5,Acc); Line(b,8,16,16,16,Ink,1.4); end;
{ TTySpeedButton: a flat toolbar button (faint outline only) with an accent glyph }
procedure GSpeedButton(b: TBGRABitmap); begin RRect(b,4,4,20,20,3,Faint); FillCirc(b,12,12,4,Acc); end;
{ TTyDropDownButton: a split button — a divider carving off a right zone with a down triangle }
procedure GDropDownButton(b: TBGRABitmap); begin RRect(b,3,7,21,17,3,Ink); Line(b,15.5,7.5,15.5,16.5,Faint,1.3); FillPolyG(b,[PointF(16.4,11),PointF(19.6,11),PointF(18,13.6)],Acc); end;
{ TTyMenuButton: a button with a caption line + a trailing down triangle (whole button drops) }
procedure GMenuButton(b: TBGRABitmap); begin RRect(b,3,7,21,17,3,Ink); Line(b,7,12,14,12,Acc,2.2); FillPolyG(b,[PointF(15.4,10.8),PointF(18.6,10.8),PointF(17,13.4)],Ink); end;
{ TTyColorButton: a button with an accent colour swatch + faint hex-text ticks }
procedure GColorButton(b: TBGRABitmap); begin RRect(b,3,7,21,17,3,Ink); FillRRect(b,6,10,12,15,1.5,Acc); Line(b,15,11,19,11,Faint,1.3); Line(b,15,14,18,14,Faint,1.3); end;
{ TTyButtonGroup: three adjacent segments in one rounded outline, the middle one accent-selected }
procedure GButtonGroup(b: TBGRABitmap); begin FillRRect(b,9,8,15,16,0,Acc); RRect(b,3,8,21,16,2,Ink); Line(b,9,8,9,16,Ink,1); Line(b,15,8,15,16,Ink,1); end;
{ TTyRibbon: a command band — a tab strip on top (accent active tab) + a content band with group dividers }
procedure GRibbon(b: TBGRABitmap); begin RRect(b,2,4,22,20,2,Ink); Line(b,2,9,22,9,Ink,1); FillRRect(b,3,5,8,9,1,Acc); Line(b,10,7,13,7,Ink); Line(b,15,7,19,7,Ink); Line(b,8,12,8,18,Ink,1); Line(b,15,12,15,18,Ink,1); end;
{ TTyRibbonPage: one ribbon page with group dividers + an accent control }
procedure GRibbonPage(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); Line(b,10,4,10,20,Ink,1); Line(b,15,4,15,20,Ink,1); FillRRect(b,5,7,8,13,1,Acc); end;
{ TTyRibbonGroup: a labelled group box — a bottom caption band + an accent control + text lines }
procedure GRibbonGroup(b: TBGRABitmap); begin RRect(b,4,4,20,20,2,Ink); Line(b,4,16,20,16,Ink,1); Line(b,8,18,16,18,Faint); FillRRect(b,7,7,10,14,1,Acc); Line(b,13,8,17,8,Faint); Line(b,13,12,17,12,Faint); end;
{ TTyRibbonAppMenu: the accent "File" application button with a down triangle }
procedure GRibbonAppMenu(b: TBGRABitmap); begin FillRRect(b,3,7,17,17,3,Acc); Line(b,6,12,12,12,Faint,1.6); RRect(b,3,7,17,17,3,Ink); FillPolyG(b,[PointF(18.4,10.6),PointF(21.6,10.6),PointF(20,13.4)],Ink); end;
{ TTyRibbonQuickAccess: a compact command strip with three tiny command marks }
procedure GRibbonQuickAccess(b: TBGRABitmap); begin FillRRect(b,2,8,22,16,3,Faint); RRect(b,2,8,22,16,3,Ink); FillRRect(b,4,10,8,14,1,Ink); FillCirc(b,12,12,2,Ink); FillRRect(b,15,10,19,14,1,Acc); end;
{ TTyRibbonGallery: a 3x2 grid of thumbnail cells (one accent-selected) + a dropdown chevron }
procedure GRibbonGallery(b: TBGRABitmap);
var i: Integer; cx, cy: single;
begin
  RRect(b,2,3,22,17,2,Ink);
  for i := 0 to 5 do
  begin
    cx := 4 + (i mod 3) * 6.2; cy := 5 + (i div 3) * 6.2;
    if i = 1 then FillRRect(b, cx, cy, cx+5, cy+5, 1, Acc)
    else RRect(b, cx, cy, cx+5, cy+5, 1, Faint);
  end;
  FillPolyG(b,[PointF(9,20),PointF(15,20),PointF(12,23)],Ink);
end;
{ TTyRibbonBackstage: a window with an accent left sidebar (rows) + a content area (the File view) }
procedure GRibbonBackstage(b: TBGRABitmap); begin FillRRect(b,3,4,9,20,1,Acc); RRect(b,3,4,21,20,2,Ink); Line(b,5,8,7,8,Faint); Line(b,5,12,7,12,Faint); Line(b,5,16,7,16,Faint); Line(b,12,8,19,8,Ink); Line(b,12,12,17,12,Faint); Line(b,12,16,18,16,Faint); end;
procedure GListBox(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); Line(b,6,9,18,9,Acc,2); Line(b,6,13,18,13,Ink); Line(b,6,17,15,17,Ink); end;
procedure GTabControl(b: TBGRABitmap); begin FillRRect(b,3.5,5,11.5,10.5,1.5,Acc); RRect(b,12.5,6.2,20,10.5,1.5,Ink); RRect(b,3,10,21,20,2,Ink); end;
procedure GTabSheet(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); Line(b,3,9,21,9,Acc,2); end;
procedure GGroupBox(b: TBGRABitmap); begin RRect(b,4,7,20,20,2,Ink); Line(b,6.5,7,11.5,7,Acc,2.6); end;
procedure GPanel(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); end;
procedure GScrollBar(b: TBGRABitmap); begin RRect(b,9,3,15,21,3,Ink); PolyL(b,[PointF(10.5,7),PointF(12,5.5),PointF(13.5,7)],Ink); PolyL(b,[PointF(10.5,17),PointF(12,18.5),PointF(13.5,17)],Ink); FillRRect(b,9.5,10,14.5,15,1.5,Acc); end;
procedure GSpinEdit(b: TBGRABitmap); begin RRect(b,3,7,15,17,2,Ink); Line(b,6,9.5,6,14.5,Acc,2); Line(b,15,7,15,17,Ink); PolyL(b,[PointF(16.5,11),PointF(18,9.5),PointF(19.5,11)],Ink); PolyL(b,[PointF(16.5,13),PointF(18,14.5),PointF(19.5,13)],Ink); end;
procedure GMemo(b: TBGRABitmap); begin RRect(b,3,3,21,21,2,Ink); Line(b,6,8,17,8,Ink); Line(b,6,12,17,12,Ink); Line(b,6,16,13,16,Ink); end;
procedure GTitleBar(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); Line(b,3,9,21,9,Ink); FillCirc(b,15,6.5,0.9,Ink); FillCirc(b,17,6.5,0.9,Ink); FillCirc(b,19,6.5,0.9,Acc); end;
procedure GMenuBar(b: TBGRABitmap); begin RRect(b,3,6,21,12,2,Ink); Line(b,6,9,8,9,Acc); Line(b,10,9,12,9,Ink); Line(b,14,9,16,9,Ink); end;
procedure GStyleController(b: TBGRABitmap); begin RRect(b,4,4,20,20,3,Ink); FillPolyG(b,[PointF(5,19),PointF(19,19),PointF(5,5)],Acc); end;
procedure GPopupMenu(b: TBGRABitmap); begin RRect(b,4,3,19,21,2,Ink); Line(b,7,7,16,7,Ink); Line(b,7,11,16,11,Acc); Line(b,7,15,16,15,Ink); end;

{ TTyNativeStyler: a plain rect (native control) with an accent paint-drop swatch in the corner }
procedure GNativeStyler(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  FillRRect(b,14,13,20,19,2,Acc);
  RRect(b,14,13,20,19,2,Acc);
end;

{ TTySplitter: vertical centre line with left+right arrowheads (resize handle) }
procedure GSplitter(b: TBGRABitmap);
begin
  Line(b,12,3,12,21,Ink,2);
  PolyL(b,[PointF(8,10),PointF(5,12),PointF(8,14)],Acc,1.8);
  PolyL(b,[PointF(16,10),PointF(19,12),PointF(16,14)],Acc,1.8);
end;

{ TTyStatusBar: rounded rect with thin bottom band divided into 3 cells }
procedure GStatusBar(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  Line(b,3,15,21,15,Ink);
  FillRRect(b,3.5,15.5,20.5,19.5,1,Faint);
  Line(b,9,15,9,20,Ink,1);
  Line(b,15,15,15,20,Ink,1);
end;

{ TTyToolBar: rounded rect with a top band holding 3 small dot-buttons }
procedure GToolBar(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  Line(b,3,10,21,10,Ink);
  FillRRect(b,3.5,4.5,20.5,9.5,1,Faint);
  FillCirc(b,7.5,7,1.8,Acc);
  FillCirc(b,12,7,1.8,Ink);
  FillCirc(b,16.5,7,1.8,Ink);
end;

{ TTyToolSeparator: a single short vertical line centred in the icon }
procedure GToolSeparator(b: TBGRABitmap);
begin
  Line(b,12,6,12,18,Faint,1.4);
  Line(b,12,7,12,17,Ink,1.8);
end;

{ TTyBevel: a 3D framed rectangle (outer bevel highlight/shadow + inset inner ring -> groove/ridge) }
procedure GBevel(b: TBGRABitmap);
begin
  Line(b,4,4,20,4,Acc,1.7); Line(b,4,4,4,20,Acc,1.7);
  Line(b,4,20,20,20,Ink,1.7); Line(b,20,4,20,20,Ink,1.7);
  Line(b,7,7,17,7,Ink,1.3); Line(b,7,7,7,17,Ink,1.3);
  Line(b,7,17,17,17,Faint,1.3); Line(b,17,7,17,17,Faint,1.3);
end;

{ TTyDivider: a short accent caption bar on the left + a thin rule filling to the right }
procedure GDivider(b: TBGRABitmap);
begin
  Line(b,4,12,9,12,Acc,2.4); Line(b,11,12,20,12,Ink,1.4);
  Line(b,4,7,7,7,Faint,1.1); Line(b,4,17,6,17,Faint,1.1);
end;

{ TTyPaintPanel: a panel frame with an accent paint swipe + brush nib (owner-draw surface) }
procedure GPaintPanel(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2.5,Ink);
  PolyL(b,[PointF(6,17),PointF(10,10),PointF(15,8)],Acc,2.2);
  FillPolyG(b,[PointF(15,8),PointF(18.4,6.2),PointF(16.8,10.4)],Acc);
  Line(b,7.2,14.6,9.2,13.6,Faint,1.2);
end;

{ TTySizeBox: a panel corner with a diagonal 3/2/1 ladder of dots (the Windows size grip) }
procedure GSizeBox(b: TBGRABitmap);
begin
  RRect(b,3,3,21,21,2,Ink);
  FillCirc(b,9,17,1.15,Acc);  FillCirc(b,13,17,1.15,Ink);  FillCirc(b,17,17,1.15,Ink);
  FillCirc(b,13,13,1.15,Ink); FillCirc(b,17,13,1.15,Ink);
  FillCirc(b,17,9,1.15,Ink);
end;

{ TTyRadioGroup: a group-box frame (caption stub) enclosing a selected + an unselected radio row }
procedure GRadioGroup(b: TBGRABitmap);
begin
  RRect(b,4,7,20,20,2,Ink); Line(b,6.5,7,11.5,7,Acc,2.6);
  Circ(b,8,12,2,Ink,1.2); FillCirc(b,8,12,0.9,Acc); Line(b,11.5,12,17,12,Faint,1.2);
  Circ(b,8,16.5,2,Ink,1.2); Line(b,11.5,16.5,17,16.5,Faint,1.2);
end;

{ TTyCheckGroup: a titled group frame with two check rows — first ticked (accent), second empty }
procedure GCheckGroup(b: TBGRABitmap);
begin
  RRect(b,3,6,21,20,2,Ink); Line(b,6,6,11,6,Acc,2.6);
  RRect(b,6,9.5,9,12.5,0.6,Ink); PolyL(b,[PointF(6.4,11),PointF(7.3,11.9),PointF(8.7,10.1)],Acc,1.3);
  Line(b,11,11,18,11,Faint,1.2);
  RRect(b,6,14.5,9,17.5,0.6,Ink); Line(b,11,16,18,16,Faint,1.2);
end;

{ TTyToolGroupPanel: a group box with a bottom caption band + a row of small tool-button tiles }
procedure GToolGroupPanel(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink); Line(b,3,16,21,16,Ink,1); Line(b,8,18,16,18,Faint);
  FillRRect(b,5.5,6.5,9.5,13.5,1,Acc);
  FillRRect(b,10.5,6.5,14.5,13.5,1,Faint);
  FillRRect(b,15.5,6.5,19.5,13.5,1,Faint);
end;

{ TTyCalendar: rounded rect with a top header bar + two rows of day dots }
procedure GCalendar(b: TBGRABitmap);
begin
  RRect(b,3,4,21,21,2,Ink);
  FillRRect(b,3.5,4.5,20.5,9.5,1,Acc);
  // two small page-turn dots in the header
  FillCirc(b,7,7,1.2,BGRAWhite);
  FillCirc(b,17,7,1.2,BGRAWhite);
  // grid dots: two rows of three
  FillCirc(b,8,13,1.2,Ink);
  FillCirc(b,12,13,1.2,Ink);
  FillCirc(b,16,13,1.2,Acc);
  FillCirc(b,8,17.5,1.2,Ink);
  FillCirc(b,12,17.5,1.2,Ink);
  FillCirc(b,16,17.5,1.2,Ink);
end;

{ TTyDateTimePicker: edit-field rounded rect with a chevron-down button on the right }
procedure GDateTimePicker(b: TBGRABitmap);
begin
  RRect(b,3,7,21,17,2,Ink);
  Line(b,16,7,16,17,Ink,1);
  // chevron-down glyph inside the button area (x: 16..21 range)
  PolyL(b,[PointF(17.5,11.3),PointF(19,13),PointF(20.5,11.3)],Acc,1.8);
end;

{ TTyTreeView: a root row with a triangle expand button + two indented child rows }
procedure GTreeView(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  // root row: triangle (expand button) + row line
  FillPolyG(b,[PointF(6,7.5),PointF(9,9),PointF(6,10.5)],Acc);
  Line(b,10.5,9,19,9,Ink);
  // child row 1 (indented)
  Line(b,8,13,8,16,Faint,1.2);   // tree connector
  Line(b,8,13,10,13,Faint,1.2);
  Line(b,10.5,13,19,13,Ink);
  // child row 2 (indented)
  Line(b,8,16,10,16,Faint,1.2);
  Line(b,10.5,17,19,17,Ink);
end;

{ --- Dialogs palette group --------------------------------------------------- }

{ TTyMessage: dialog rect + a centred accent "!" (exclamation) }
procedure GTyMessage(b: TBGRABitmap);
begin
  RRect(b,4,4,20,20,3,Ink);
  Line(b,12,7.5,12,13.5,Acc,2.2);
  FillCirc(b,12,16.4,1.15,Acc);
end;

{ TTyInputDialog: dialog rect containing a small edit field with an accent caret }
procedure GTyInputDialog(b: TBGRABitmap);
begin
  RRect(b,3,5,21,19,2,Ink);
  RRect(b,6,10,18,14,1.2,Faint,1.3);
  Line(b,8,10.8,8,13.2,Acc,1.8);
end;

{ TTyPasswordDialog: dialog rect + a short row of accent dots (masked input) }
procedure GTyPasswordDialog(b: TBGRABitmap);
begin
  RRect(b,3,5,21,19,2,Ink);
  RRect(b,6,10,18,14,1.2,Faint,1.3);
  FillCirc(b,8.5,12,1.05,Acc);
  FillCirc(b,11.2,12,1.05,Acc);
  FillCirc(b,13.9,12,1.05,Ink);
  FillCirc(b,16.6,12,1.05,Ink);
end;

{ TTyTextDialog: dialog rect + 3 text lines (multi-line, GMemo-inside-a-frame) }
procedure GTyTextDialog(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  Line(b,6,9,18,9,Ink);
  Line(b,6,12,18,12,Ink);
  Line(b,6,15,13,15,Acc);
end;

{ TTySelectValueDialog: dialog rect + a combo chevron (reuse the GCombo motif) }
procedure GTySelectValueDialog(b: TBGRABitmap);
begin
  RRect(b,3,7,21,17,2,Ink);
  Line(b,15.5,7,15.5,17,Ink,1);
  PolyL(b,[PointF(17,11),PointF(18.5,13),PointF(20,11)],Acc,1.8);
  Line(b,6,12,13,12,Faint,1.3);
end;

{ TTySelectPathDialog: dialog rect + a folder glyph }
procedure GTySelectPathDialog(b: TBGRABitmap);
begin
  RRect(b,3,5,21,19,2,Ink);
  // folder tab + body
  PolyL(b,[PointF(7,9),PointF(9.5,9),PointF(11,10.5),PointF(16,10.5)],Acc,1.6);
  RRect(b,7,10.5,17,16,1.2,Acc);
end;

{ TTyColorDialog: dialog rect + an accent-filled swatch square }
procedure GTyColorDialog(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  FillRRect(b,8,8,16,16,1.5,Acc);
  RRect(b,8,8,16,16,1.5,Ink,1.2);
end;

{ TTyFontDialog: dialog rect + a serif "A" }
procedure GTyFontDialog(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  // 'A' strokes
  PolyL(b,[PointF(9,17),PointF(12,7),PointF(15,17)],Acc,1.9);
  Line(b,10.2,13,13.8,13,Acc,1.6);
  // serif feet
  Line(b,7.8,17,10.2,17,Ink,1.4);
  Line(b,13.8,17,16.2,17,Ink,1.4);
end;

{ TTyFindDialog: dialog rect + a magnifier (circle + short handle) }
procedure GTyFindDialog(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  Circ(b,11,11,3.6,Acc,1.9);
  Line(b,13.6,13.6,17,17,Acc,2);
end;

{ TTyReplaceDialog: a magnifier + two small swap arrows }
procedure GTyReplaceDialog(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  Circ(b,10,10,3.3,Ink,1.7);
  Line(b,12.4,12.4,15,15,Ink,1.8);
  // swap arrows (bottom-right)
  Line(b,13.5,17,19,17,Acc,1.5);
  PolyL(b,[PointF(17.5,15.5),PointF(19,17),PointF(17.5,18.5)],Acc,1.5);
  Line(b,13.5,20,19,20,Acc,1.5);
  PolyL(b,[PointF(15,18.5),PointF(13.5,20),PointF(15,21.5)],Acc,1.5);
end;

{ TTyProgressDialog: dialog rect + a progress-bar band (reuse the GProgress motif) }
procedure GTyProgressDialog(b: TBGRABitmap);
begin
  RRect(b,3,4,21,20,2,Ink);
  Line(b,6,9,18,9,Faint,1.3);
  RRect(b,6,13,18,17,2,Ink);
  FillRRect(b,6,13,13,17,2,Acc);
end;

{ TTyAboutDialog: dialog rect + an accent info mark ("i" = dot over a stem) }
procedure GTyAboutDialog(b: TBGRABitmap);
begin
  RRect(b,4,4,20,20,3,Ink);
  FillCirc(b,12,8.6,1.2,Acc);         // dot (top)
  Line(b,12,11.2,12,16.8,Acc,2.2);    // stem (below)
end;

{ TTyTabSet: a pure tab strip — one selected tab + two unselected + baseline }
procedure GTabSet(b: TBGRABitmap); begin FillRRect(b,3,5,9,11,1.5,Acc); RRect(b,9.5,5,15.5,11,1.5,Ink); RRect(b,16,5,21,11,1.5,Ink); Line(b,3,11,21,11,Ink,1.4); end;

type
  TGlyphProc = procedure(b: TBGRABitmap);
  TGlyph = record Name: string; Draw: TGlyphProc; end;

const
  Glyphs: array[0..113] of TGlyph = (
    (Name:'TTyButton';          Draw:@GButton),
    (Name:'TTyLabel';           Draw:@GLabel),
    (Name:'TTyEdit';            Draw:@GEdit),
    (Name:'TTyNumericEdit';     Draw:@GNumericEdit),
    (Name:'TTyCurrencyEdit';    Draw:@GCurrencyEdit),
    (Name:'TTyMaskEdit';        Draw:@GMaskEdit),
    (Name:'TTyURLEdit';         Draw:@GURLEdit),
    (Name:'TTyComboEdit';       Draw:@GComboEdit),
    (Name:'TTyTrackEdit';       Draw:@GTrackEdit),
    (Name:'TTyColorBox';        Draw:@GColorBox),
    (Name:'TTyColorComboBox';   Draw:@GColorComboBox),
    (Name:'TTyMRUComboBox';     Draw:@GMRUComboBox),
    (Name:'TTyComboBoxEx';      Draw:@GComboBoxEx),
    (Name:'TTyOfficeListBox';   Draw:@GOfficeListBox),
    (Name:'TTyOfficeComboBox';  Draw:@GOfficeComboBox),
    (Name:'TTyColorGrid';       Draw:@GColorGrid),
    (Name:'TTyLColorPicker';    Draw:@GLColorPicker),
    (Name:'TTyHSColorPicker';   Draw:@GHSColorPicker),
    (Name:'TTyAdvancedListBox'; Draw:@GAdvancedListBox),
    (Name:'TTyAdvancedComboBox';Draw:@GAdvancedComboBox),
    (Name:'TTyCheckComboBox';   Draw:@GCheckComboBox),
    (Name:'TTyValueListEditor'; Draw:@GValueListEditor),
    (Name:'TTyCalculator';      Draw:@GCalculator),
    (Name:'TTyCalcEdit';        Draw:@GCalcEdit),
    (Name:'TTyCalcCurrencyEdit';Draw:@GCalcCurrencyEdit),
    (Name:'TTyColorListBox';    Draw:@GColorListBox),
    (Name:'TTyFontComboBox';    Draw:@GFontComboBox),
    (Name:'TTyFontListBox';     Draw:@GFontListBox),
    (Name:'TTyFontSizeComboBox'; Draw:@GFontSizeComboBox),
    (Name:'TTyCheckListBox';    Draw:@GCheckListBox),
    (Name:'TTyCheckBox';        Draw:@GCheckBox),
    (Name:'TTyRadioButton';     Draw:@GRadio),
    (Name:'TTyComboBox';        Draw:@GCombo),
    (Name:'TTyToggleSwitch';    Draw:@GToggle),
    (Name:'TTyTrackBar';        Draw:@GTrack),
    (Name:'TTyProgressBar';     Draw:@GProgress),
    (Name:'TTyGauge';           Draw:@GGauge),
    (Name:'TTyCircularProgress'; Draw:@GCircularProgress),
    (Name:'TTyActivityIndicator'; Draw:@GActivityIndicator),
    (Name:'TTyActivityBar';      Draw:@GActivityBar),
    (Name:'TTyMeter';            Draw:@GMeter),
    (Name:'TTyLevelMeter';       Draw:@GLevelMeter),
    (Name:'TTyDial';             Draw:@GDial),
    (Name:'TTyAnalogClock';      Draw:@GAnalogClock),
    (Name:'TTySparkline';        Draw:@GSparkline),
    (Name:'TTyRating';           Draw:@GRating),
    (Name:'TTyGearDial';         Draw:@GGearDial),
    (Name:'TTyGearActivityIndicator'; Draw:@GGearActivityIndicator),
    (Name:'TTyUpDown';           Draw:@GUpDown),
    (Name:'TTyLinkLabel';        Draw:@GLinkLabel),
    (Name:'TTyShadowLabel';      Draw:@GShadowLabel),
    (Name:'TTyGlowLabel';        Draw:@GGlowLabel),
    (Name:'TTyHint';             Draw:@GHint),
    (Name:'TTyBalloonHint';      Draw:@GBalloonHint),
    (Name:'TTyIconFont';         Draw:@GIconFont),
    (Name:'TTyCharImage';        Draw:@GCharImage),
    (Name:'TTyGlyphImageList';   Draw:@GGlyphImageList),
    (Name:'TTyImage';            Draw:@GImage),
    (Name:'TTyImageCollection';  Draw:@GImageCollection),
    (Name:'TTyVirtualImageList'; Draw:@GVirtualImageList),
    (Name:'TTyGlyphButton';      Draw:@GGlyphButton),
    (Name:'TTyGlyphContainerButton'; Draw:@GGlyphContainerButton),
    (Name:'TTySpeedButton';      Draw:@GSpeedButton),
    (Name:'TTyDropDownButton';   Draw:@GDropDownButton),
    (Name:'TTyMenuButton';       Draw:@GMenuButton),
    (Name:'TTyColorButton';      Draw:@GColorButton),
    (Name:'TTyButtonGroup';      Draw:@GButtonGroup),
    (Name:'TTyRibbon';           Draw:@GRibbon),
    (Name:'TTyRibbonPage';       Draw:@GRibbonPage),
    (Name:'TTyRibbonGroup';      Draw:@GRibbonGroup),
    (Name:'TTyRibbonAppMenu';    Draw:@GRibbonAppMenu),
    (Name:'TTyRibbonQuickAccess'; Draw:@GRibbonQuickAccess),
    (Name:'TTyRibbonGallery';     Draw:@GRibbonGallery),
    (Name:'TTyRibbonBackstage';   Draw:@GRibbonBackstage),
    (Name:'TTyListBox';         Draw:@GListBox),
    (Name:'TTyPageControl';     Draw:@GTabControl),
    (Name:'TTyTabSheet';        Draw:@GTabSheet),
    (Name:'TTyGroupBox';        Draw:@GGroupBox),
    (Name:'TTyPanel';           Draw:@GPanel),
    (Name:'TTyScrollBar';       Draw:@GScrollBar),
    (Name:'TTySpinEdit';        Draw:@GSpinEdit),
    (Name:'TTyMemo';            Draw:@GMemo),
    (Name:'TTyTitleBar';        Draw:@GTitleBar),
    (Name:'TTyMenuBar';         Draw:@GMenuBar),
    (Name:'TTyStyleController';  Draw:@GStyleController),
    (Name:'TTyPopupMenu';       Draw:@GPopupMenu),
    (Name:'TTyNativeStyler';   Draw:@GNativeStyler),
    (Name:'TTySplitter';        Draw:@GSplitter),
    (Name:'TTyStatusBar';       Draw:@GStatusBar),
    (Name:'TTyToolBar';         Draw:@GToolBar),
    (Name:'TTyToolSeparator';   Draw:@GToolSeparator),
    (Name:'TTyCalendar';        Draw:@GCalendar),
    (Name:'TTyDateTimePicker';  Draw:@GDateTimePicker),
    (Name:'TTyTreeView';        Draw:@GTreeView),
    (Name:'TTyMessage';           Draw:@GTyMessage),
    (Name:'TTyInputDialog';       Draw:@GTyInputDialog),
    (Name:'TTyPasswordDialog';    Draw:@GTyPasswordDialog),
    (Name:'TTyTextDialog';        Draw:@GTyTextDialog),
    (Name:'TTySelectValueDialog'; Draw:@GTySelectValueDialog),
    (Name:'TTySelectPathDialog';  Draw:@GTySelectPathDialog),
    (Name:'TTyColorDialog';       Draw:@GTyColorDialog),
    (Name:'TTyFontDialog';        Draw:@GTyFontDialog),
    (Name:'TTyFindDialog';        Draw:@GTyFindDialog),
    (Name:'TTyReplaceDialog';     Draw:@GTyReplaceDialog),
    (Name:'TTyProgressDialog';    Draw:@GTyProgressDialog),
    (Name:'TTyAboutDialog';       Draw:@GTyAboutDialog),
    (Name:'TTyTabSet';            Draw:@GTabSet),
    (Name:'TTyBevel';             Draw:@GBevel),
    (Name:'TTyDivider';           Draw:@GDivider),
    (Name:'TTyPaintPanel';        Draw:@GPaintPanel),
    (Name:'TTySizeBox';           Draw:@GSizeBox),
    (Name:'TTyRadioGroup';        Draw:@GRadioGroup),
    (Name:'TTyCheckGroup';        Draw:@GCheckGroup),
    (Name:'TTyToolGroupPanel';    Draw:@GToolGroupPanel)
  );

const
  { Lazarus HiDPI palette convention: base name = 100% (24px); '_150' = 150% (36px);
    '_200' = 200% (48px). The IDE picks the variant matching the display scaling, so
    no upscaling/blur. (Verified against stock components/PascalScript/pascalscript.lrs.) }
  SizePx:     array[0..2] of Integer = (24, 36, 48);
  SizeSuffix: array[0..2] of string  = ('', '_150', '_200');

var
  OutDir: string;
  i, s, total: Integer;
  bmp: TBGRABitmap;
begin
  Ink   := BGRA($3C, $3C, $3C, 255);
  Acc   := BGRA($3B, $82, $F6, 255);
  Faint := BGRA($3C, $3C, $3C, 140);

  if ParamCount >= 1 then OutDir := ParamStr(1) else OutDir := GetCurrentDir;
  OutDir := IncludeTrailingPathDelimiter(OutDir);
  ForceDirectories(OutDir);

  total := 0;
  for s := 0 to High(SizePx) do
  begin
    GScale := SizePx[s] / 24.0;
    for i := 0 to High(Glyphs) do
    begin
      bmp := TBGRABitmap.Create(SizePx[s], SizePx[s]);   // fully transparent
      try
        Glyphs[i].Draw(bmp);
        if (bmp.Width <> SizePx[s]) or (bmp.Height <> SizePx[s]) then
        begin
          writeln('ERROR: ', Glyphs[i].Name, ' wrong size');
          Halt(2);
        end;
        bmp.SaveToFile(OutDir + Glyphs[i].Name + SizeSuffix[s] + '.png');
        Inc(total);
      finally
        bmp.Free;
      end;
    end;
  end;
  writeln('Wrote ', total, ' icons (', Length(Glyphs), ' x ', Length(SizePx), ' sizes) to ', OutDir);
end.
