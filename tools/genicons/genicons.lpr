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
procedure GCheckBox(b: TBGRABitmap); begin RRect(b,4,4,20,20,3,Ink); PolyL(b,[PointF(8,12.4),PointF(11,15.4),PointF(16,8.6)],Acc,2.2); end;
procedure GRadio(b: TBGRABitmap); begin Circ(b,12,12,8,Ink); FillCirc(b,12,12,3.1,Acc); end;
procedure GCombo(b: TBGRABitmap); begin RRect(b,3,7,21,17,2,Ink); PolyL(b,[PointF(13.5,10.8),PointF(16,13.4),PointF(18.5,10.8)],Ink); end;
procedure GToggle(b: TBGRABitmap); begin RRect(b,3,8,21,16,4,Ink); FillCirc(b,16.5,12,2.7,Acc); end;
procedure GTrack(b: TBGRABitmap); begin Line(b,3,12,21,12,Ink); Line(b,6,10.4,6,13.6,Ink); Line(b,18,10.4,18,13.6,Ink); FillCirc(b,12,12,3,Acc); end;
procedure GProgress(b: TBGRABitmap); begin RRect(b,3,9,21,15,3,Ink); FillRRect(b,3,9,13,15,3,Acc); end;
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

type
  TGlyphProc = procedure(b: TBGRABitmap);
  TGlyph = record Name: string; Draw: TGlyphProc; end;

const
  Glyphs: array[0..28] of TGlyph = (
    (Name:'TTyButton';          Draw:@GButton),
    (Name:'TTyLabel';           Draw:@GLabel),
    (Name:'TTyEdit';            Draw:@GEdit),
    (Name:'TTyCheckBox';        Draw:@GCheckBox),
    (Name:'TTyRadioButton';     Draw:@GRadio),
    (Name:'TTyComboBox';        Draw:@GCombo),
    (Name:'TTyToggleSwitch';    Draw:@GToggle),
    (Name:'TTyTrackBar';        Draw:@GTrack),
    (Name:'TTyProgressBar';     Draw:@GProgress),
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
    (Name:'TTyTreeView';        Draw:@GTreeView)
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
