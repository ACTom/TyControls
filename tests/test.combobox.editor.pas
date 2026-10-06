unit test.combobox.editor;
{$mode objfpc}{$H+}

{ The editable combo's text is the same line the pick-only combo draws.

  An editable combo (csDropDown) lays a real TTyEdit, StyleClass 'embedded', over its text zone,
  inset by the combo's own padding. The embedded variant dropped the edit's border and radius but
  kept its padding, so the text was inset twice: at the default 26px height the editor got 18px,
  its own 4 + 4 left a 10px zone for a 12px line, and the descenders of g, y, p and q were cut off
  -- 'Engineering' read 'Enaineerina'. The pick-only style draws the same text straight into the
  combo's 18px zone and showed it whole, a few pixels further left. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, StdCtrls, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.BuiltinThemes,
  tyControls.Edit, tyControls.ComboBox;

type
  TComboEditorTest = class(TTestCase)
  published
    procedure TestEveryThemeLeavesTheEmbeddedEditorNoPadding;
    procedure TestTheEditableComboShowsTheSameWholeLine;
  end;

implementation

type
  TComboAccess = class(TTyComboBox);
  TEditAccess = class(TTyEdit);

const
  CText = 'gypq Engineering';

procedure TComboEditorTest.TestEveryThemeLeavesTheEmbeddedEditorNoPadding;
var
  n: TStringArray;
  i, m: Integer;
  model: TTyStyleModel;
  s: TTyStyleSet;
  bad: string;
const
  Modes: array[0..1] of string = ('light', 'dark');
begin
  bad := '';
  n := TyBuiltinThemeNames;
  AssertTrue('setup: the built-in themes are listed', Length(n) > 10);
  for i := 0 to High(n) do
  begin
    model := TTyStyleModel.Create;
    try
      model.LoadFromCss(TyBuiltinThemeCss(n[i]));
      for m := 0 to High(Modes) do
      begin
        model.SetMode(Modes[m]);
        s := model.ResolveStyle('TyEdit', 'embedded', []);
        if (s.Padding.Left <> 0) or (s.Padding.Top <> 0) or (s.Padding.Right <> 0)
          or (s.Padding.Bottom <> 0) then
          bad := bad + Format('%s/%s: %d %d %d %d', [n[i], Modes[m], s.Padding.Left,
            s.Padding.Top, s.Padding.Right, s.Padding.Bottom]) + LineEnding;
      end;
    finally model.Free; end;
  end;
  AssertEquals('themes whose embedded editor insets the text a second time:' + LineEnding + bad,
    '', bad);
end;

{ The darkest pixels of the text zone -- the glyphs, not the border, the chevron or the field. }
procedure TextInk(B: TBitmap; AZone: TRect; out L, T, R, Bot: Integer);
var
  x, y: Integer;
  c: TColor;
begin
  L := MaxInt; T := MaxInt; R := -1; Bot := -1;
  for y := AZone.Top to AZone.Bottom - 1 do
    for x := AZone.Left to AZone.Right - 1 do
    begin
      c := ColorToRGB(B.Canvas.Pixels[x, y]);
      if (Red(c) + Green(c) + Blue(c)) div 3 < 128 then
      begin
        if x < L then L := x;
        if x > R then R := x;
        if y < T then T := y;
        if y > Bot then Bot := y;
      end;
    end;
end;

procedure TComboEditorTest.TestTheEditableComboShowsTheSameWholeLine;
var
  f: TForm;
  pick, edit: TTyComboBox;
  ed: TTyEdit;
  i: Integer;
  bp, be: TBitmap;
  zone: TRect;
  pl, pt, pr, pb, el, et, er, eb: Integer;
begin
  f := TForm.CreateNew(nil);
  bp := TBitmap.Create;
  be := TBitmap.Create;
  try
    pick := TTyComboBox.Create(f);
    pick.Parent := f;
    pick.Style := csDropDownList;
    pick.Items.Add(CText);
    pick.ItemIndex := 0;
    edit := TTyComboBox.Create(f);
    edit.Parent := f;
    edit.Style := csDropDown;
    edit.Text := CText;
    ed := nil;
    for i := 0 to edit.ControlCount - 1 do
      if edit.Controls[i] is TTyEdit then ed := TTyEdit(edit.Controls[i]);
    AssertTrue('setup: the editable combo has its editor', ed <> nil);
    AssertEquals('setup: both at the default height', pick.Height, edit.Height);

    bp.SetSize(pick.Width, pick.Height);
    bp.Canvas.Brush.Color := clWhite;
    bp.Canvas.FillRect(0, 0, bp.Width, bp.Height);
    TComboAccess(pick).RenderTo(bp.Canvas, Rect(0, 0, pick.Width, pick.Height), 96);
    be.SetSize(edit.Width, edit.Height);
    be.Canvas.Brush.Color := clWhite;
    be.Canvas.FillRect(0, 0, be.Width, be.Height);
    { What the screen composes: the combo's field, then its editor window on top of it. }
    TComboAccess(edit).RenderTo(be.Canvas, Rect(0, 0, edit.Width, edit.Height), 96);
    TEditAccess(ed).RenderTo(be.Canvas, Rect(ed.Left, ed.Top, ed.Left + ed.Width, ed.Top + ed.Height), 96);

    { The text zone: inside the frame, short of the chevron. }
    zone := Rect(2, 2, ed.Left + ed.Width, edit.Height - 2);
    TextInk(bp, zone, pl, pt, pr, pb);
    TextInk(be, zone, el, et, er, eb);
    AssertTrue('setup: the pick-only combo drew its text', pr >= 0);
    AssertTrue('setup: the editable combo drew its text', er >= 0);
    AssertEquals('the descenders reach as low in both styles', pb, eb);
    AssertEquals('the line starts as high', pt, et);
    AssertEquals('and as far left', pl, el);
    AssertEquals('and as far right: the same font, the same width', pr, er);
  finally
    be.Free;
    bp.Free;
    f.Free;
  end;
end;

initialization
  RegisterTest(TComboEditorTest);
end.
