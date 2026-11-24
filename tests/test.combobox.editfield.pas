unit test.combobox.editfield;
{$mode objfpc}{$H+}

{ #244: an editable combo box shows nothing of its item text outside its edit box.

  In the editable styles a TTyEdit lies over the text zone and shows the text; it stops one
  right padding short of the drop arrow. The combo box painted its own copy of the selected
  item under the edit box all the same, into a text zone that did NOT stop there -- and where
  that copy reached into the gap it was in view beside the edit box's text: its last letter
  when the text just fitted ("Microsoft YaHei UIII"), the dots of its ellipsis when it did
  not.

  The pictures here are the COMBO BOX's own paint (RenderTo), i.e. what lies under and beside
  the edit box. The theme draws text red on white and no border, so any red in the columns
  between the edit box and the drop arrow is that defect. Every width from narrow to wide is
  looked at, because which part of the text lands in the gap depends on the width. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Edit,
  tyControls.ComboBox, tyControls.FontComboBox;

type
  TTyComboBoxClass = class of TTyCustomComboBox;

  TComboEditFieldTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    function NewCombo(AClass: TTyComboBoxClass; AStyle: TTyComboBoxStyle;
      ARtl: Boolean = False): TTyCustomComboBox;
    { Columns [AFrom, ATo) of the combo's own paint that carry text ink, summed. }
    function InkIn(C: TTyCustomComboBox; AFrom, ATo: Integer): Integer;
    { The columns between the edit box and the drop arrow (or the far edge, with no arrow). }
    procedure Gap(C: TTyCustomComboBox; out AFrom, ATo: Integer);
    { The most ink found in the gap over every width from 90 to 260 px, and at which width. }
    function WorstGapInk(C: TTyCustomComboBox; out AWidth: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AnEditableComboPaintsNoTextBesideItsEditBox;
    procedure NorDoesAFontCombo;
    procedure NorASimpleCombo;
    procedure RightToLeftTheGapIsOnTheOtherSideAndAsClean;
    procedure APickOnlyComboKeepsItsWholeTextZone;
  end;

implementation

const
  { The right padding is the width of the gap, and it is NOT the left one here: a fix that
    took the wrong side's padding would leave half the gap inked. }
  cPadRight = 12;
  cTheme =
    'TyComboBox { background: #FFFFFF; color: #FF0000; padding: 4px 12px 4px 6px; '
    + 'border-width: 0px; }';
  cText = 'Microsoft YaHei UI';

type
  TComboCrack = class(TTyCustomComboBox);

function EditBoxOf(C: TTyCustomComboBox): TTyEdit;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to C.ControlCount - 1 do
    if C.Controls[i] is TTyEdit then Exit(TTyEdit(C.Controls[i]));
end;

procedure TComboEditFieldTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(cTheme);
  FForm := TForm.CreateNew(nil);
end;

procedure TComboEditFieldTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TComboEditFieldTest.NewCombo(AClass: TTyComboBoxClass; AStyle: TTyComboBoxStyle;
  ARtl: Boolean): TTyCustomComboBox;
begin
  Result := AClass.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  if ARtl then Result.BiDiMode := bdRightToLeft;
  Result.SetBounds(0, 0, 150, 28);
  { Its own row, whatever the class filled itself with (a font combo lists the machine's
    fonts, and a test machine need not have this one). }
  Result.Items.Clear;
  Result.Items.Add(cText);
  Result.Style := AStyle;
  Result.ItemIndex := 0;
end;

function TComboEditFieldTest.InkIn(C: TTyCustomComboBox; AFrom, ATo: Integer): Integer;
var
  bmp: TBitmap;
  img: TBGRABitmap;
  r: TRect;
  x, y: Integer;
  p: PBGRAPixel;
begin
  Result := 0;
  r := Rect(0, 0, C.Width, C.Height);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(C.Width, C.Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(r);
    TComboCrack(C).RenderTo(bmp.Canvas, r, 96);
    bmp.Canvas.FillRect(r);
    TComboCrack(C).RenderTo(bmp.Canvas, r, 96);
    img := TBGRABitmap.Create(bmp);
    try
      if AFrom < 0 then AFrom := 0;
      if ATo > img.Width then ATo := img.Width;
      for y := 0 to img.Height - 1 do
      begin
        p := img.ScanLine[y];
        for x := AFrom to ATo - 1 do
          { red text on white: the green channel falls wherever a glyph is }
          if (p[x].red > 150) and (p[x].green < 180) then Inc(Result);
      end;
    finally
      img.Free;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TComboEditFieldTest.Gap(C: TTyCustomComboBox; out AFrom, ATo: Integer);
var
  ed: TTyEdit;
  arrow: Integer;
begin
  ed := EditBoxOf(C);
  if C.Style = csSimple then arrow := 0
  else arrow := TyDropZoneWidth(FCtl);   // 96 PPI: logical = device
  if C.IsRightToLeft then
  begin
    AFrom := arrow;
    ATo := ed.Left;
  end
  else
  begin
    AFrom := ed.Left + ed.Width;
    ATo := C.ClientWidth - arrow;
  end;
end;

function TComboEditFieldTest.WorstGapInk(C: TTyCustomComboBox; out AWidth: Integer): Integer;
var
  w, a, b, n: Integer;
begin
  Result := 0;
  AWidth := 0;
  for w := 90 to 260 do
  begin
    C.Width := w;
    Gap(C, a, b);
    AssertEquals(Format('precondition: the gap is one right padding wide, at width %d', [w]),
      cPadRight, b - a);
    n := InkIn(C, a, b);
    if n > Result then
    begin
      Result := n;
      AWidth := w;
    end;
  end;
end;

procedure TComboEditFieldTest.AnEditableComboPaintsNoTextBesideItsEditBox;
var
  c: TTyCustomComboBox;
  w, n: Integer;
begin
  c := NewCombo(TTyComboBox, csDropDown);
  AssertTrue('precondition: the edit box is there', EditBoxOf(c) <> nil);
  n := WorstGapInk(c, w);
  AssertEquals('no text ink between the edit box and the drop arrow, at any width (worst at '
    + IntToStr(w) + ' px)', 0, n);
end;

procedure TComboEditFieldTest.NorDoesAFontCombo;
var
  c: TTyCustomComboBox;
  w, n: Integer;
begin
  { Where it was seen. A font combo replaces the field paint to draw the name in its own
    typeface, so it is its own way into the gap. }
  c := NewCombo(TTyFontComboBox, csDropDown);
  n := WorstGapInk(c, w);
  AssertEquals('no text ink between the edit box and the drop arrow (worst at '
    + IntToStr(w) + ' px)', 0, n);
end;

procedure TComboEditFieldTest.NorASimpleCombo;
var
  c: TTyCustomComboBox;
  w, n: Integer;
begin
  { No drop arrow: the gap is between the edit box and the edge of the field. }
  c := NewCombo(TTyComboBox, csSimple);
  c.Height := 120;
  n := WorstGapInk(c, w);
  AssertEquals('no text ink between the edit box and the edge (worst at '
    + IntToStr(w) + ' px)', 0, n);
end;

procedure TComboEditFieldTest.RightToLeftTheGapIsOnTheOtherSideAndAsClean;
var
  c: TTyCustomComboBox;
  w, n: Integer;
begin
  c := NewCombo(TTyComboBox, csDropDown, True);
  n := WorstGapInk(c, w);
  AssertEquals('no text ink between the drop arrow and the edit box (worst at '
    + IntToStr(w) + ' px)', 0, n);
end;

procedure TComboEditFieldTest.APickOnlyComboKeepsItsWholeTextZone;
var
  c: TTyCustomComboBox;
  full, w, zoneRight, tail: Integer;
begin
  { No edit box, nothing to stay clear of: the text may use the zone up to the drop arrow, as
    it always did. Looked at where a long text is cut with an ellipsis -- its dots end at the
    right edge of the zone, in the columns an editable combo must leave alone. }
  c := NewCombo(TTyComboBox, csDropDownList);
  c.Items[0] := 'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW';
  c.ItemIndex := 0;
  full := 0;
  for w := 120 to 160 do
  begin
    c.Width := w;
    zoneRight := c.ClientWidth - TyDropZoneWidth(FCtl);
    tail := InkIn(c, zoneRight - cPadRight, zoneRight);   // the last right padding of the zone
    if tail > full then full := tail;
  end;
  AssertTrue('the text of a pick-only field reaches the last padding of its zone', full > 0);
end;

initialization
  RegisterTest(TComboEditFieldTest);
end.
