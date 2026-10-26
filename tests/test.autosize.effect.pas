unit test.autosize.effect;
{ #114: AutoSize := True now does something on the controls where it did nothing. One line
  fields take one line of the font plus the padding (as TTySpinEdit always did, and LCL's
  TEdit does); bars keep their theme height and grow for a bigger font; content-sized
  controls take their content; a control with no natural size keeps its bounds rather than
  shrinking to an internal scroll bar. And a theme switch re-fits them, since the padding
  and the font come from the theme. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Edit,
  tyControls.NumericEdit, tyControls.SpinEdit, tyControls.ComboBox, tyControls.StatusBar,
  tyControls.ScrollBar, tyControls.Rating, tyControls.Memo, tyControls.TreeView,
  tyControls.Badge, test.dpi.support;

type
  TAutoSizeEffectTest = class(TTestCase)
  private
    FForm: TForm;
    function ThemePath(const AName: string): string;
    procedure Place(AControl: TControl; W, H: Integer);
    { LCL applies AutoSize once the form can lay out, which a headless form never does;
      TyTestSettle runs the same step: GetPreferredSize, then the bounds. }
    procedure Fit;
    { The preferred size LCL holds now, NOT invalidated first: what a re-fit would have
      to have refreshed. }
    function Held(AControl: TControl): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnEditTakesOneLineOfItsFont;
    procedure TestAnEditGrowsWithItsFont;
    procedure TestANumericEditInheritsIt;
    procedure TestAnEditAndASpinEditAgree;
    procedure TestAComboTakesOneLineButASimpleOneKeepsItsHeight;
    procedure TestAStatusBarKeepsItsThemeHeightAndGrowsForABigFont;
    procedure TestAScrollBarTakesItsThickness;
    procedure TestARatingTakesItsStars;
    procedure TestABadgeTakesItsPill;
    procedure TestAMemoAndATreeKeepTheirBounds;
    procedure TestAThemeSwitchRefits;
  end;

implementation

type
  TEditAcc = class(TTyEdit)
  public
    function Want: Integer;
  end;

function TEditAcc.Want: Integer;
begin
  Result := TyFieldPreferredHeight(CurrentStyle, ResolveFontSize(CurrentStyle), Font.PixelsPerInch);
end;

procedure TAutoSizeEffectTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
end;

procedure TAutoSizeEffectTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TAutoSizeEffectTest.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim
    + 'builtin' + PathDelim + AName;
end;

procedure TAutoSizeEffectTest.Fit;
begin
  TyTestSettle(FForm);
end;

function TAutoSizeEffectTest.Held(AControl: TControl): Integer;
var
  w, h: Integer;
begin
  w := 0;
  h := 0;
  AControl.GetPreferredSize(w, h, True, False);
  Result := h;
end;

procedure TAutoSizeEffectTest.Place(AControl: TControl; W, H: Integer);
begin
  AControl.Parent := FForm;
  AControl.Font.PixelsPerInch := 96;
  AControl.SetBounds(10, 10, W, H);
end;

procedure TAutoSizeEffectTest.TestAnEditTakesOneLineOfItsFont;
var
  e: TEditAcc;
begin
  e := TEditAcc.Create(FForm);
  Place(e, 150, 60);
  e.AutoSize := True;
  Fit;
  AssertEquals('one line of the font plus the padding', e.Want, e.Height);
  AssertTrue('and that is less than the 60 it had', e.Height < 60);
  AssertEquals('the width stays the form''s', 150, e.Width);
end;

procedure TAutoSizeEffectTest.TestAnEditGrowsWithItsFont;
var
  e: TEditAcc;
  was: Integer;
begin
  e := TEditAcc.Create(FForm);
  Place(e, 150, 28);
  e.AutoSize := True;
  Fit;
  was := e.Height;
  e.Font.Size := 24;
  Fit;
  AssertTrue(Format('a bigger font, a taller edit (%d -> %d)', [was, e.Height]), e.Height > was + 10);
end;

procedure TAutoSizeEffectTest.TestANumericEditInheritsIt;
var
  n: TTyNumericEdit;
begin
  n := TTyNumericEdit.Create(FForm);
  Place(n, 120, 60);
  n.AutoSize := True;
  Fit;
  AssertTrue('a descendant of the edit sizes too', n.Height < 60);
end;

procedure TAutoSizeEffectTest.TestAnEditAndASpinEditAgree;
var
  e: TTyEdit;
  s: TTySpinEdit;
begin
  e := TTyEdit.Create(FForm);
  Place(e, 120, 40);
  s := TTySpinEdit.Create(FForm);
  Place(s, 120, 40);
  e.AutoSize := True;
  Fit;
  s.AutoSize := True;
  Fit;
  AssertEquals('side by side they line up', s.Height, e.Height);
end;

procedure TAutoSizeEffectTest.TestAComboTakesOneLineButASimpleOneKeepsItsHeight;
var
  c, simple: TTyComboBox;
begin
  c := TTyComboBox.Create(FForm);
  Place(c, 150, 60);
  c.AutoSize := True;
  Fit;
  AssertTrue('a drop-down combo sizes to its field', c.Height < 60);
  simple := TTyComboBox.Create(FForm);
  Place(simple, 150, 160);
  simple.Style := csSimple;
  simple.Height := 160;
  simple.AutoSize := True;
  Fit;
  AssertEquals('a simple one keeps field + list', 160, simple.Height);
end;

procedure TAutoSizeEffectTest.TestAStatusBarKeepsItsThemeHeightAndGrowsForABigFont;
var
  b: TTyStatusBar;
  themed: Integer;
begin
  b := TTyStatusBar.Create(FForm);
  b.Align := alNone;
  Place(b, 300, 60);
  b.AutoSize := True;
  Fit;
  themed := b.Height;
  AssertTrue('the theme''s bar height, not the 60 it was given', themed < 60);
  b.Font.Size := 28;
  Fit;
  AssertTrue(Format('a font the bar cannot hold grows it (%d -> %d)', [themed, b.Height]),
    b.Height > themed);
end;

procedure TAutoSizeEffectTest.TestAScrollBarTakesItsThickness;
var
  s: TTyScrollBar;
  thick: Integer;
begin
  s := TTyScrollBar.Create(FForm);
  Place(s, 50, 160);
  thick := s.Width;
  s.Width := 50;
  s.AutoSize := True;
  Fit;
  AssertTrue('the thickness, not the 50 it was given', s.Width < 50);
  AssertEquals('the length stays the form''s', 160, s.Height);
end;

procedure TAutoSizeEffectTest.TestARatingTakesItsStars;
var
  r: TTyRating;
  one: Integer;
begin
  r := TTyRating.Create(FForm);
  Place(r, 40, 40);
  r.AutoSize := True;
  Fit;
  one := r.Height;
  AssertEquals('five square cells', 5 * one, r.Width);
  r.Count := 7;
  Fit;
  AssertEquals('seven of them', 7 * one, r.Width);
end;

procedure TAutoSizeEffectTest.TestABadgeTakesItsPill;
var
  b: TTyBadge;
  w, h: Integer;
begin
  { The badge sizes itself to its pill whatever AutoSize says; what AutoSize adds is that
    LCL, asking the badge what it wants -- as a parent that sizes to its children does --
    hears the pill too, and not 0 x 0. }
  b := TTyBadge.Create(FForm);
  b.Value := 5;
  Place(b, 200, 100);
  b.AutoSize := True;
  Fit;
  w := 0;
  h := 0;
  b.InvalidatePreferredSize;
  b.GetPreferredSize(w, h, True, False);
  AssertEquals('LCL hears the pill''s width', b.Width, w);
  AssertEquals('and its height', b.Height, h);
  AssertTrue('a pill, not the 200 x 100 it was given', (w > 0) and (w < 200) and (h < 100));
end;

procedure TAutoSizeEffectTest.TestAMemoAndATreeKeepTheirBounds;
var
  m: TTyMemo;
  t: TTyTreeView;
  i: Integer;
begin
  m := TTyMemo.Create(FForm);
  Place(m, 200, 150);
  for i := 1 to 60 do m.Lines.Add('line ' + IntToStr(i));
  m.AutoSize := True;
  Fit;
  AssertEquals('the memo keeps its width', 200, m.Width);
  AssertEquals('and its height', 150, m.Height);
  t := TTyTreeView.Create(FForm);
  Place(t, 200, 150);
  for i := 1 to 60 do t.Items.Add(nil, 'node ' + IntToStr(i));
  t.AutoSize := True;
  Fit;
  AssertEquals('the tree keeps its width', 200, t.Width);
  AssertEquals('and its height', 150, t.Height);
end;

procedure TAutoSizeEffectTest.TestAThemeSwitchRefits;
var
  ctl: TTyStyleController;
  e: TEditAcc;
  before: Integer;
begin
  ctl := TTyStyleController.Create(nil);
  try
    e := TEditAcc.Create(FForm);
    e.Controller := ctl;
    Place(e, 150, 60);
    e.AutoSize := True;
    Fit;
    before := Held(e);
    ctl.LoadThemeCss('TyEdit { padding: 14px 6px; font-size: 9px; }');   // roomier fields
    AssertEquals('the edit asks again under the new theme', e.Want, Held(e));
    AssertTrue(Format('and that moved it (%d -> %d)', [before, Held(e)]), Held(e) <> before);
  finally
    FreeAndNil(FForm);   // the edit goes before its controller
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TAutoSizeEffectTest);
end.
