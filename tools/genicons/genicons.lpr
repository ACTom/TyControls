program genicons;
{$mode objfpc}{$H+}
uses
  Interfaces, SysUtils, BGRABitmap, BGRABitmapTypes;

const
  ST = 1.7;

var
  Ink, Acc, Faint: TBGRAPixel;

procedure Line(b: TBGRABitmap; x1, y1, x2, y2: single; c: TBGRAPixel; w: single = ST);
begin
  b.DrawLineAntialias(x1, y1, x2, y2, c, w);
end;

procedure RRect(b: TBGRABitmap; l, t, r, bot, rad: single; c: TBGRAPixel; w: single = ST);
begin
  b.RoundRectAntialias(l, t, r, bot, rad, rad, c, w);
end;

procedure FillRRect(b: TBGRABitmap; l, t, r, bot, rad: single; c: TBGRAPixel);
begin
  b.FillRoundRectAntialias(l, t, r, bot, rad, rad, c);
end;

procedure Circ(b: TBGRABitmap; cx, cy, rad: single; c: TBGRAPixel; w: single = ST);
begin
  b.EllipseAntialias(cx, cy, rad, rad, c, w);
end;

procedure FillCirc(b: TBGRABitmap; cx, cy, rad: single; c: TBGRAPixel);
begin
  b.FillEllipseAntialias(cx, cy, rad, rad, c);
end;

procedure PolyL(b: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel; w: single = ST);
begin
  b.DrawPolyLineAntialias(pts, c, w);
end;

procedure FillPolyG(b: TBGRABitmap; const pts: array of TPointF; c: TBGRAPixel);
begin
  b.FillPolyAntialias(pts, c);
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
procedure GGroupBox(b: TBGRABitmap); begin RRect(b,4,7,20,20,2,Ink); Line(b,6.5,7,11.5,7,Acc,2.6); end;
procedure GPanel(b: TBGRABitmap); begin RRect(b,3,5,21,19,2,Ink); end;
procedure GScrollBar(b: TBGRABitmap); begin RRect(b,9,3,15,21,3,Ink); PolyL(b,[PointF(10.5,7),PointF(12,5.5),PointF(13.5,7)],Ink); PolyL(b,[PointF(10.5,17),PointF(12,18.5),PointF(13.5,17)],Ink); FillRRect(b,9.5,10,14.5,15,1.5,Acc); end;
procedure GSpinEdit(b: TBGRABitmap); begin RRect(b,3,7,15,17,2,Ink); Line(b,6,9.5,6,14.5,Acc,2); Line(b,15,7,15,17,Ink); PolyL(b,[PointF(16.5,11),PointF(18,9.5),PointF(19.5,11)],Ink); PolyL(b,[PointF(16.5,13),PointF(18,14.5),PointF(19.5,13)],Ink); end;
procedure GMemo(b: TBGRABitmap); begin RRect(b,3,3,21,21,2,Ink); Line(b,6,8,17,8,Ink); Line(b,6,12,17,12,Ink); Line(b,6,16,13,16,Ink); end;
procedure GTitleBar(b: TBGRABitmap); begin RRect(b,3,4,21,20,2,Ink); Line(b,3,9,21,9,Ink); FillCirc(b,15,6.5,0.9,Ink); FillCirc(b,17,6.5,0.9,Ink); FillCirc(b,19,6.5,0.9,Acc); end;
procedure GMenuBar(b: TBGRABitmap); begin RRect(b,3,6,21,12,2,Ink); Line(b,6,9,8,9,Acc); Line(b,10,9,12,9,Ink); Line(b,14,9,16,9,Ink); end;
procedure GStyleController(b: TBGRABitmap); begin RRect(b,4,4,20,20,3,Ink); FillPolyG(b,[PointF(5,19),PointF(19,19),PointF(5,5)],Acc); end;
procedure GPopupMenu(b: TBGRABitmap); begin RRect(b,4,3,19,21,2,Ink); Line(b,7,7,16,7,Ink); Line(b,7,11,16,11,Acc); Line(b,7,15,16,15,Ink); end;

type
  TGlyphProc = procedure(b: TBGRABitmap);
  TGlyph = record Name: string; Draw: TGlyphProc; end;

const
  Glyphs: array[0..19] of TGlyph = (
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
    (Name:'TTyTabControl';      Draw:@GTabControl),
    (Name:'TTyGroupBox';        Draw:@GGroupBox),
    (Name:'TTyPanel';           Draw:@GPanel),
    (Name:'TTyScrollBar';       Draw:@GScrollBar),
    (Name:'TTySpinEdit';        Draw:@GSpinEdit),
    (Name:'TTyMemo';            Draw:@GMemo),
    (Name:'TTyTitleBar';        Draw:@GTitleBar),
    (Name:'TTyMenuBar';         Draw:@GMenuBar),
    (Name:'TTyStyleController';  Draw:@GStyleController),
    (Name:'TTyPopupMenu';       Draw:@GPopupMenu)
  );

var
  OutDir: string;
  i: Integer;
  bmp: TBGRABitmap;
begin
  Ink   := BGRA($3C, $3C, $3C, 255);
  Acc   := BGRA($3B, $82, $F6, 255);
  Faint := BGRA($3C, $3C, $3C, 140);

  if ParamCount >= 1 then OutDir := ParamStr(1) else OutDir := GetCurrentDir;
  OutDir := IncludeTrailingPathDelimiter(OutDir);
  ForceDirectories(OutDir);

  for i := 0 to High(Glyphs) do
  begin
    bmp := TBGRABitmap.Create(24, 24);   // fully transparent
    try
      Glyphs[i].Draw(bmp);
      if (bmp.Width <> 24) or (bmp.Height <> 24) then
      begin
        writeln('ERROR: ', Glyphs[i].Name, ' is not 24x24');
        Halt(2);
      end;
      bmp.SaveToFile(OutDir + Glyphs[i].Name + '.png');
    finally
      bmp.Free;
    end;
  end;
  writeln('Wrote ', Length(Glyphs), ' icons to ', OutDir);
end.
