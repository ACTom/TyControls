unit test.stylelayout;

{$mode objfpc}{$H+}

{ #146: a theme, StyleClass, StyleOverride, Controller or Font change that moves what the
  style decides about a layout -- padding, a row pitch, a caption band -- lays the control out
  again. It repainted and left the children, the rows and the embedded editor where they were. }

interface

uses
  Classes, SysUtils, Controls, Forms, Graphics, fpcunit, testregistry,
  tyControls.Base, tyControls.Controller, tyControls.Panel, tyControls.RadioGroup,
  tyControls.CheckGroup, tyControls.GroupBox, tyControls.Card, tyControls.ExPanel,
  tyControls.ScrollBox, tyControls.Empty, tyControls.ComboBox, tyControls.RelativePanel,
  tyControls.PageControl, tyControls.TabSheet, tyControls.Cascader;

type
  TStyleLayoutTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function Child(AParent: TWinControl): TTyPanel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestARadioGroupsRowsFollowATheme;
    procedure TestACheckGroupsRowsFollowATheme;
    procedure TestChildrenFollowAContainersStyleOverride;
    procedure TestChildrenFollowAStyleClassAndANewController;
    procedure TestAnEditableComboPlacesItsEditorAgain;
    procedure TestCaptionBandsGrowWithTheFont;
    procedure TestPageTabsGrowWithTheFont;
    procedure TestAHeaderHeightThatMatchesTheFieldStillPins;
    procedure TestASpacingThatMatchesTheFieldStillPins;
    procedure TestACascadersPanelWearsItsStyle;
  end;

implementation

type
  TTyCtlClass = class of TTyCustomControl;

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TStyleLayoutTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  { shown, off screen: an unshown form never runs LCL's align pass, and that pass is what
    these tests are about }
  FForm.SetBounds(-4000, -4000, 500, 400);
  FForm.Visible := True;
  FCtl := TTyStyleController.Create(nil);
end;

procedure TStyleLayoutTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

function TStyleLayoutTest.Child(AParent: TWinControl): TTyPanel;
begin
  Result := TTyPanel.Create(FForm);
  Result.Parent := AParent;
  Result.Align := alClient;
end;

procedure TStyleLayoutTest.TestARadioGroupsRowsFollowATheme;
var
  g: TTyRadioGroup;
  before: Integer;
begin
  FCtl.LoadThemeCss(':root { --row-height: 22; }');
  g := TTyRadioGroup.Create(FForm);
  g.Parent := FForm;
  g.Controller := FCtl;
  g.Font.PixelsPerInch := 96;
  g.SetBounds(0, 0, 200, 300);
  g.Items.Text := 'a' + LineEnding + 'b' + LineEnding + 'c';
  before := g.Controls[2].Top - g.Controls[1].Top;
  FCtl.LoadThemeCss(':root { --row-height: 60; }');
  AssertEquals('the rows are placed at the new pitch', 60, g.Controls[2].Top - g.Controls[1].Top);
  AssertTrue('setup: it was another', before <> 60);
end;

procedure TStyleLayoutTest.TestACheckGroupsRowsFollowATheme;
var
  g: TTyCheckGroup;
  before: Integer;
begin
  FCtl.LoadThemeCss(':root { --row-height: 22; }');
  g := TTyCheckGroup.Create(FForm);
  g.Parent := FForm;
  g.Controller := FCtl;
  g.Font.PixelsPerInch := 96;
  g.SetBounds(0, 0, 200, 300);
  g.Items.Text := 'a' + LineEnding + 'b' + LineEnding + 'c';
  before := g.Controls[2].Top - g.Controls[1].Top;
  FCtl.LoadThemeCss(':root { --row-height: 60; }');
  AssertEquals('the rows are placed at the new pitch', 60, g.Controls[2].Top - g.Controls[1].Top);
  AssertTrue('setup: it was another', before <> 60);
end;

procedure TStyleLayoutTest.TestChildrenFollowAContainersStyleOverride;
const
  Kinds: array[0..4] of TTyCtlClass = (TTyGroupBox, TTyCard, TTyExPanel, TTyScrollBox, TTyEmpty);
var
  i: Integer;
  host: TTyCustomControl;
  ch: TTyPanel;
  before: TRect;
begin
  for i := 0 to High(Kinds) do
  begin
    host := Kinds[i].Create(FForm);
    host.Parent := FForm;
    host.Font.PixelsPerInch := 96;
    host.SetBounds(0, 0, 300, 200);
    if host is TTyEmpty then TTyEmpty(host).ShowAction := True;   // its children live in that band
    ch := Child(host);
    before := ch.BoundsRect;
    host.StyleOverride := 'padding: 40px; border-width: 6px;';
    AssertTrue(Kinds[i].ClassName + ': the child moves in with the padding',
      ch.Left > before.Left);
    AssertTrue(Kinds[i].ClassName + ': and narrows', ch.Width < before.Right - before.Left);
    host.Free;
  end;
end;

procedure TStyleLayoutTest.TestChildrenFollowAStyleClassAndANewController;
var
  cd: TTyCard;
  ch: TTyPanel;
  other: TTyStyleController;
  before: Integer;
begin
  FCtl.LoadThemeCss('TyCard { padding: 0px; border-width: 0px; } ' +
    'TyCard.roomy { padding: 40px; border-width: 0px; }');
  cd := TTyCard.Create(FForm);
  cd.Parent := FForm;
  cd.Controller := FCtl;
  cd.Font.PixelsPerInch := 96;
  cd.SetBounds(0, 0, 300, 200);
  ch := Child(cd);
  before := ch.Left;
  cd.StyleClass := 'roomy';
  AssertTrue('a StyleClass with more padding moves the child in', ch.Left > before);
  cd.StyleClass := '';
  AssertEquals('and back out', before, ch.Left);

  other := TTyStyleController.Create(nil);
  try
    other.LoadThemeCss('TyCard { padding: 40px; border-width: 0px; }');
    cd.Controller := other;
    AssertTrue('a controller whose theme pads more moves it in too', ch.Left > before);
    cd.Controller := FCtl;
  finally
    other.Free;
  end;
end;

procedure TStyleLayoutTest.TestAnEditableComboPlacesItsEditorAgain;
var
  cb: TTyComboBox;
  ed: TControl;
  i, before: Integer;
begin
  cb := TTyComboBox.Create(FForm);
  cb.Parent := FForm;
  cb.Font.PixelsPerInch := 96;
  cb.SetBounds(0, 0, 200, 30);
  cb.Style := csDropDown;
  ed := nil;
  for i := 0 to cb.ControlCount - 1 do
    if cb.Controls[i].Visible then ed := cb.Controls[i];
  AssertNotNull('setup: the editor', ed);
  before := ed.Left;
  cb.StyleOverride := 'padding: 4px 4px 4px 40px;';
  AssertTrue('the editor moves in with the padding', ed.Left > before);
end;

procedure TStyleLayoutTest.TestCaptionBandsGrowWithTheFont;
var
  gb: TTyGroupBox;
  cd: TTyCard;
  ex: TTyExPanel;
  ch: TTyPanel;
  before: Integer;
begin
  gb := TTyGroupBox.Create(FForm);
  gb.Parent := FForm;
  gb.Font.PixelsPerInch := 96;
  gb.SetBounds(0, 0, 300, 200);
  gb.Caption := 'Caption';
  ch := Child(gb);
  before := ch.Top;
  gb.Font.Size := 30;
  AssertTrue('a group box''s band grows, and the child goes below it', ch.Top > before);

  cd := TTyCard.Create(FForm);
  cd.Parent := FForm;
  cd.Font.PixelsPerInch := 96;
  cd.SetBounds(0, 0, 300, 200);
  cd.Title := 'Title';
  ch := Child(cd);
  before := ch.Top;
  cd.Font.Size := 40;
  AssertTrue('a card''s header grows, and the child goes below it', ch.Top > before);

  ex := TTyExPanel.Create(FForm);
  ex.Parent := FForm;
  ex.Font.PixelsPerInch := 96;
  ex.SetBounds(0, 0, 300, 200);
  ex.Caption := 'Caption';
  ch := Child(ex);
  before := ch.Top;
  ex.Font.Size := 30;
  AssertTrue('an expander''s header grows, and the child goes below it', ch.Top > before);
  ex.HeaderHeight := 26;
  AssertEquals('a header height the program sets is kept', 26, ex.HeaderHeight);
end;

procedure TStyleLayoutTest.TestPageTabsGrowWithTheFont;
var
  pc: TTyPageControl;
  ts: TTyTabSheet;
  before, top0: Integer;
begin
  pc := TTyPageControl.Create(FForm);
  pc.Parent := FForm;
  pc.Font.PixelsPerInch := 96;
  pc.SetBounds(0, 0, 300, 200);
  ts := TTyTabSheet.Create(FForm);
  ts.PageControl := pc;
  ts.Caption := 'Page';
  before := pc.TabHeight;
  top0 := ts.Top;
  pc.Font.Size := 30;
  AssertTrue('the tabs grow with the font', pc.TabHeight > before);
  AssertTrue('and the page goes below them', ts.Top > top0);
end;

procedure TStyleLayoutTest.TestAHeaderHeightThatMatchesTheFieldStillPins;
var
  ex: TTyExPanel;
  ch: TTyPanel;
  before: Integer;
begin
  FCtl.LoadThemeCss(':root { --expander-header-height: 40; }');
  ex := TTyExPanel.Create(FForm);
  ex.Parent := FForm;
  ex.Controller := FCtl;
  ex.Font.PixelsPerInch := 96;
  ex.SetBounds(0, 0, 300, 200);
  ch := Child(ex);
  AssertEquals('setup: the theme''s header', 40, ex.HeaderHeight);
  before := ch.Top;
  ex.HeaderHeight := 26;   // the number the field already holds
  AssertEquals('pinned', 26, ex.HeaderHeight);
  AssertEquals('and the body moves up by the difference', before - 14, ch.Top);
end;

procedure TStyleLayoutTest.TestASpacingThatMatchesTheFieldStillPins;
var
  rp: TTyRelativePanel;
  a, b: TTyPanel;
  before: Integer;
begin
  FCtl.LoadThemeCss(':root { --spacing: 20; }');
  rp := TTyRelativePanel.Create(FForm);
  rp.Parent := FForm;
  rp.Controller := FCtl;
  rp.Font.PixelsPerInch := 96;
  rp.SetBounds(0, 0, 300, 100);
  a := TTyPanel.Create(FForm);
  a.Parent := rp;
  a.SetBounds(0, 0, 50, 20);
  b := TTyPanel.Create(FForm);
  b.Parent := rp;
  b.SetBounds(0, 0, 30, 20);
  rp.SetRules(a, [traAlignParentLeft]);
  rp.SetRules(b, [trRightOf], a);
  AssertEquals('setup: the theme''s spacing', 20, rp.Spacing);
  before := b.Left;
  rp.Spacing := 8;   // the number the field already holds
  AssertEquals('pinned', 8, rp.Spacing);
  AssertEquals('and b moves in by the difference', before - 12, b.Left);
end;

procedure TStyleLayoutTest.TestACascadersPanelWearsItsStyle;
var
  c: TTyCascader;
  p: TTyCascaderPanel;
begin
  c := TTyCascader.Create(FForm);
  c.Parent := FForm;
  c.StyleClass := 'compact';
  c.StyleOverride := 'color: #ff0000;';
  p := c.DropDownPanel;
  AssertEquals('the panel wears the field''s StyleClass', 'compact', p.StyleClass);
  AssertEquals('and its StyleOverride', 'color: #ff0000;', p.StyleOverride);
end;

initialization
  RegisterTest(TStyleLayoutTest);
end.
