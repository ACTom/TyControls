unit test.rtlreach;

{$mode objfpc}{$H+}

{ #153: with BiDiMode = bdRightToLeft these mirror as TTyLabel and the list box already do --
  the combo family's fields and their drop-downs, the cascader and tree select, the drop-down
  buttons, the advanced, font and Office list rows, the expander's, the card's and the paint
  panel's headers, a popup menu's own BiDiMode, and the glow, shadow and HTML labels and the
  alert. Each drew and answered left to right. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, Menus, StdCtrls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.Painter, tyControls.ComboBox,
  tyControls.Cascader, tyControls.TreeSelect, tyControls.DropButtons, tyControls.ListBox,
  tyControls.AdvancedListBox, tyControls.FontListBox, tyControls.OfficeListBox,
  tyControls.ExPanel, tyControls.Card, tyControls.PaintPanel, tyControls.Menu,
  tyControls.GlowLabel, tyControls.ShadowLabel, tyControls.HtmlLabel, tyControls.Alert,
  tyControls.Popup;

type
  TRtlReachTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FHref: string;
    procedure LinkClicked(Sender: TObject; const AHref: string);
    procedure PaintLeftBlock(Sender: TObject; APainter: TTyPainter; const ARect: TRect);
    { the green ink's x-span of AControl's RenderTo at AW x AH, mirrored or not }
    procedure GreenSpan(AControl: TControl; AW, AH: Integer; ARtl: Boolean; out L, R: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAComboFieldsChevronChangesSides;
    procedure TestAComboAnswersAndPlacesItsEditorMirrored;
    procedure TestAComboOpensFromItsRightEdge;
    procedure TestTheCascaderAndTreeSelectFieldsMirror;
    procedure TestTheCascaderOpensFromItsRightEdge;
    procedure TestTheTreeSelectOpensFromItsRightEdge;
    procedure TestTheFieldsTextReadsToTheRightEdge;
    procedure TestADropDownButtonsDividerAndMenuChangeSides;
    procedure TestADropDownButtonsArrowAnswersOnTheLeft;
    procedure TestListRowsMirror;
    procedure TestHeadersMirror;
    procedure TestACardTitlesLeadingPaddingChangesSides;
    procedure TestAPaintPanelsCaptionMirrorsAndItsOwnerDrawDoesNot;
    procedure TestAPopupMenuReadsItsOwnBiDiMode;
    procedure TestTheGlowAndShadowLabelsMirror;
    procedure TestAnHtmlLabelsLinksAnswerWhereTheyAreDrawn;
    procedure TestAnAlertsCloseButtonIsOnTheLeft;
  end;

implementation

type
  TListAcc = class(TTyListBox);
  TComboAcc = class(TTyComboBox);
  TCascAcc = class(TTyCascader);
  TTreeSelAcc = class(TTyTreeSelect);
  TDropAcc = class(TTyDropDownButton);
  TAdvAcc = class(TTyAdvancedListBox);
  TFontAcc = class(TTyFontListBox);
  TOfficeAcc = class(TTyOfficeListBox);
  TExAcc = class(TTyExPanel);
  TCardAcc = class(TTyCard);
  TPaintAcc = class(TTyPaintPanel);
  TGlowAcc = class(TTyGlowLabel);
  TShadowAcc = class(TTyShadowLabel);
  THtmlAcc = class(TTyHtmlLabel);
  TAlertAcc = class(TTyAlert);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TRtlReachTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FCtl := TTyStyleController.Create(nil);
  FHref := '';
end;

{ every pop-up stays where it is put: the form these tests open from is off screen }
function Everywhere(const AAnchorScreen: TRect): TRect;
begin
  Result := Rect(-100000, -100000, 100000, 100000);
end;

procedure TRtlReachTest.TearDown;
begin
  TyPopupWorkArea := @TyMonitorWorkArea;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

procedure TRtlReachTest.LinkClicked(Sender: TObject; const AHref: string);
begin
  FHref := AHref;
end;

procedure TRtlReachTest.PaintLeftBlock(Sender: TObject; APainter: TTyPainter;
  const ARect: TRect);
begin
  APainter.Bitmap.FillRect(0, 20, 10, 28, BGRA(0, 0, 255), dmSet);
end;

procedure ChannelSpan(A: TBGRABitmap; AGreen: Boolean; out L, R: Integer);
var
  x, y, mine, o1, o2: Integer;
  p: TBGRAPixel;
begin
  L := A.Width;
  R := -1;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      p := A.GetPixel(x, y);
      if AGreen then begin mine := p.green; o1 := p.red; o2 := p.blue; end
      else begin mine := p.blue; o1 := p.red; o2 := p.green; end;
      if (mine > 150) and (o1 < 110) and (o2 < 110) then
      begin
        if x < L then L := x;
        if x > R then R := x;
      end;
    end;
  if R < 0 then L := -1;
end;

procedure RenderControl(AControl: TControl; ACanvas: TCanvas; const AR: TRect);
begin
  if AControl is TTyComboBox then TComboAcc(AControl).RenderTo(ACanvas, AR, 96)
  else if AControl is TTyCascader then TCascAcc(AControl).RenderTo(ACanvas, AR, 96)
  else if AControl is TTyTreeSelect then TTreeSelAcc(AControl).RenderTo(ACanvas, AR, 96)
  else if AControl is TTyListBox then TListAcc(AControl).RenderTo(ACanvas, AR, 96)
  else if AControl is TTyExPanel then TExAcc(AControl).RenderTo(ACanvas, AR, 96)
  else if AControl is TTyCard then TCardAcc(AControl).RenderTo(ACanvas, AR, 96)
  else if AControl is TTyPaintPanel then TPaintAcc(AControl).RenderTo(ACanvas, AR, 96)
  else if AControl is TTyGlowLabel then TGlowAcc(AControl).RenderTo(ACanvas, AR, 96)
  else if AControl is TTyShadowLabel then TShadowAcc(AControl).RenderTo(ACanvas, AR, 96)
  else raise Exception.Create('no RenderTo for ' + AControl.ClassName);
end;

procedure TRtlReachTest.GreenSpan(AControl: TControl; AW, AH: Integer; ARtl: Boolean;
  out L, R: Integer);
var
  host: TBitmap;
  shot: TBGRABitmap;
begin
  if ARtl then AControl.BiDiMode := bdRightToLeft else AControl.BiDiMode := bdLeftToRight;
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(AW, AH);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, AW, AH);
    RenderControl(AControl, host.Canvas, Rect(0, 0, AW, AH));
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpan(shot, True, L, R);
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

function NewOn(AForm: TForm; AClass: TControlClass; ACtl: TTyStyleController;
  AW, AH: Integer): TControl;
begin
  Result := AClass.Create(AForm);
  Result.Parent := AForm;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, AW, AH);
  if Result is TTyCustomControl then TTyCustomControl(Result).Controller := ACtl
  else if Result is TTyGraphicControl then TTyGraphicControl(Result).Controller := ACtl;
end;

procedure TRtlReachTest.TestAComboFieldsChevronChangesSides;
var
  cb: TTyComboBox;
  l, r: Integer;
begin
  FCtl.LoadThemeCss('TyComboBox { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
  cb := TTyComboBox(NewOn(FForm, TTyComboBox, FCtl, 200, 26));
  cb.Style := csDropDownList;   // nothing chosen: the chevron is the only ink
  GreenSpan(cb, 200, 26, False, l, r);
  AssertTrue('setup: the chevron drew', l >= 0);
  AssertTrue('setup: on the right', l > 100);
  GreenSpan(cb, 200, 26, True, l, r);
  AssertTrue('mirrored, on the left', (l >= 0) and (r < 100));
end;

procedure TRtlReachTest.TestAComboAnswersAndPlacesItsEditorMirrored;
var
  cb: TTyComboBox;
  ed: TControl;
  i, ltrLeft, ltrRight: Integer;
begin
  cb := TTyComboBox(NewOn(FForm, TTyComboBox, FCtl, 200, 26));
  cb.Style := csDropDown;
  ed := nil;
  for i := 0 to cb.ControlCount - 1 do
    if cb.Controls[i].Visible then ed := cb.Controls[i];
  AssertNotNull('setup: the editor', ed);
  AssertTrue('setup: the chevron is on the right', TComboAcc(cb).PointInChevron(Point(195, 10)));
  ltrLeft := ed.Left;
  ltrRight := ed.Left + ed.Width;
  cb.BiDiMode := bdRightToLeft;
  AssertTrue('mirrored, the chevron answers on the left', TComboAcc(cb).PointInChevron(Point(3, 10)));
  AssertFalse('and not on the right', TComboAcc(cb).PointInChevron(Point(195, 10)));
  AssertEquals('the editor changes sides: its left edge', 200 - ltrRight, ed.Left);
  AssertEquals('and its right edge', 200 - ltrLeft, ed.Left + ed.Width);
end;

{ the drop-down form that holds AContent }
function FormHolding(AContent: TControl): TCustomForm;
begin
  Result := GetParentForm(AContent);
end;

procedure TRtlReachTest.TestAComboOpensFromItsRightEdge;
var
  cb: TTyComboBox;
  i, j: Integer;
  f: TForm;
  list: TTyListBox;
  right: Integer;
begin
  FForm.SetBounds(-4000, -4000, 400, 300);
  FForm.Visible := True;
  TyPopupWorkArea := @Everywhere;
  cb := TTyComboBox(NewOn(FForm, TTyComboBox, FCtl, 150, 26));
  cb.Items.Add('a');
  cb.Items.Add('b');
  cb.ItemWidth := 300;   // wider than the field, so the edge it lines up with shows
  cb.BiDiMode := bdRightToLeft;
  cb.DropDown;
  try
    list := nil;
    f := nil;
    for i := 0 to Screen.FormCount - 1 do
      for j := 0 to Screen.Forms[i].ControlCount - 1 do
        if (Screen.Forms[i].Controls[j] is TTyListBox)
           and (Screen.Forms[i].Controls[j].Owner = cb) then
        begin
          f := Screen.Forms[i];
          list := TTyListBox(Screen.Forms[i].Controls[j]);
        end;
    AssertNotNull('setup: the drop-down', f);
    right := cb.ClientToScreen(Point(cb.Width, 0)).X;
    AssertEquals('it lines its right edge up with the field''s', right, f.Left + f.Width);
    AssertTrue('and its rows read right to left', list.IsRightToLeft);
  finally
    cb.CloseUp;
  end;
end;

procedure TRtlReachTest.TestTheCascaderAndTreeSelectFieldsMirror;
var
  c: TControl;
  l, r: Integer;
begin
  FCtl.LoadThemeCss(
    'TyCascader { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyComboBox { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyTreeSelect { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
  c := NewOn(FForm, TTyCascader, FCtl, 200, 26);
  GreenSpan(c, 200, 26, False, l, r);
  AssertTrue('setup: the cascader''s chevron, on the right', l > 100);
  GreenSpan(c, 200, 26, True, l, r);
  AssertTrue('mirrored, on the left', (l >= 0) and (r < 100));
  c := NewOn(FForm, TTyTreeSelect, FCtl, 200, 26);
  GreenSpan(c, 200, 26, False, l, r);
  AssertTrue('setup: the tree select''s chevron, on the right', l > 100);
  GreenSpan(c, 200, 26, True, l, r);
  AssertTrue('mirrored, on the left', (l >= 0) and (r < 100));
end;

procedure TRtlReachTest.TestTheCascaderOpensFromItsRightEdge;
var
  c: TTyCascader;
  f: TCustomForm;
  right: Integer;
begin
  FForm.SetBounds(-4000, -4000, 400, 300);
  FForm.Visible := True;
  TyPopupWorkArea := @Everywhere;
  c := TTyCascader(NewOn(FForm, TTyCascader, FCtl, 60, 26));
  c.Nodes.AddNode('One');
  c.BiDiMode := bdRightToLeft;
  c.DropDown;
  try
    f := FormHolding(c.DropDownPanel);
    AssertNotNull('setup: the drop-down', f);
    AssertTrue('setup: wider than the field', f.Width > c.Width);
    right := c.ClientToScreen(Point(c.Width, 0)).X;
    AssertEquals('it lines its right edge up with the field''s', right, f.Left + f.Width);
    AssertTrue('and the panel reads right to left', c.DropDownPanel.IsRightToLeft);
  finally
    c.CloseUp;
  end;
end;

procedure TRtlReachTest.TestTheTreeSelectOpensFromItsRightEdge;
var
  t: TTyTreeSelect;
  f: TCustomForm;
  right: Integer;
begin
  FForm.SetBounds(-4000, -4000, 400, 300);
  FForm.Visible := True;
  TyPopupWorkArea := @Everywhere;
  t := TTyTreeSelect(NewOn(FForm, TTyTreeSelect, FCtl, 60, 26));
  t.DropDownWidth := 200;
  t.BiDiMode := bdRightToLeft;
  t.DropDown;
  try
    f := FormHolding(t.Tree);
    AssertNotNull('setup: the drop-down', f);
    AssertTrue('setup: wider than the field', f.Width > t.Width);
    right := t.ClientToScreen(Point(t.Width, 0)).X;
    AssertEquals('it lines its right edge up with the field''s', right, f.Left + f.Width);
    AssertTrue('and the tree reads right to left', t.Tree.IsRightToLeft);
  finally
    t.CloseUp;
  end;
end;

{ Is there green ink in any column of [AX0, AX1]? }
function GreenIn(AControl: TControl; AW, AH, AX0, AX1: Integer): Boolean;
var
  host: TBitmap;
  shot: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := False;
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(AW, AH);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, AW, AH);
    RenderControl(AControl, host.Canvas, Rect(0, 0, AW, AH));
    shot := TBGRABitmap.Create(host);
    try
      for y := 0 to AH - 1 do
        for x := AX0 to AX1 do
        begin
          p := shot.GetPixel(x, y);
          if (p.green > 150) and (p.red < 110) and (p.blue < 110) then Exit(True);
        end;
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

{ The field's own text, mirrored, reads to the RIGHT edge: nothing between the chevron (now
  on the left) and the middle. Unmirrored text would start right after the chevron. }
procedure TRtlReachTest.TestTheFieldsTextReadsToTheRightEdge;
var
  cb: TTyComboBox;
  c: TTyCascader;
  t: TTyTreeSelect;
  l, r: Integer;
  path: TTyCascaderPath;
begin
  FCtl.LoadThemeCss(
    'TyComboBox { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyCascader { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyTreeSelect { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyTextHint { color: #00FF00; }');
  cb := TTyComboBox(NewOn(FForm, TTyComboBox, FCtl, 400, 26));
  cb.Style := csDropDownList;
  GreenSpan(cb, 400, 26, True, l, r);   // the chevron alone
  cb.TextHint := 'Ab';
  AssertTrue('the combo''s hint sits at the right edge', GreenIn(cb, 400, 26, 380, 399));
  AssertFalse('not after the chevron', GreenIn(cb, 400, 26, r + 3, 200));
  cb.TextHint := '';
  cb.Items.Add('Ab');
  cb.ItemIndex := 0;
  AssertTrue('and so does its chosen item', GreenIn(cb, 400, 26, 380, 399));
  AssertFalse('not after the chevron either', GreenIn(cb, 400, 26, r + 3, 200));

  c := TTyCascader(NewOn(FForm, TTyCascader, FCtl, 400, 26));
  GreenSpan(c, 400, 26, True, l, r);
  c.Nodes.AddNode('Ab');
  SetLength(path, 1);
  path[0] := 0;
  c.Path := path;
  AssertTrue('the cascader''s path at the right edge', GreenIn(c, 400, 26, 380, 399));
  AssertFalse('not after the chevron', GreenIn(c, 400, 26, r + 3, 200));

  t := TTyTreeSelect(NewOn(FForm, TTyTreeSelect, FCtl, 400, 26));
  GreenSpan(t, 400, 26, True, l, r);
  t.TextHint := 'Ab';
  AssertTrue('the tree select''s text at the right edge', GreenIn(t, 400, 26, 380, 399));
  AssertFalse('not after the chevron', GreenIn(t, 400, 26, r + 3, 200));
end;

procedure TRtlReachTest.TestADropDownButtonsDividerAndMenuChangeSides;
var
  b: TTyDropDownButton;
  pm: TTyPopupMenu;
  mi: TMenuItem;
  host: TBitmap;
  shot: TBGRABitmap;
  aw, x, y, right: Integer;
  atDiv, atEdge: Boolean;
  p: TBGRAPixel;
  f: TCustomForm;
begin
  FCtl.LoadThemeCss(':root { --glyph-chevron-alpha: 255; } ' +
    'TyButton { background: #FFFFFF; color: #00FF00; border-color: #00FF00; ' +
    'border-width: 0px; padding: 0px; }');
  b := TTyDropDownButton(NewOn(FForm, TTyDropDownButton, FCtl, 160, 26));
  b.Caption := '';
  b.BiDiMode := bdRightToLeft;
  aw := TDropAcc(b).ArrowZoneWidth(96);
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(160, 26);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, 160, 26);
    TDropAcc(b).RenderTo(host.Canvas, Rect(0, 0, 160, 26), 96);
    shot := TBGRABitmap.Create(host);
    try
      atDiv := False;
      atEdge := False;
      for y := 0 to 25 do
        for x := 0 to 159 do
        begin
          p := shot.GetPixel(x, y);
          if (p.green > 150) and (p.red < 110) and (p.blue < 110) then
          begin
            if Abs(x - (aw - 1)) <= 1 then atDiv := True;
            if x <= 1 then atEdge := True;
          end;
        end;
      AssertTrue('the divider sits between the arrow and the caption', atDiv);
      AssertFalse('not on the control''s left edge', atEdge);
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;

  FForm.SetBounds(-4000, -4000, 400, 300);
  FForm.Visible := True;
  TyPopupWorkArea := @Everywhere;
  pm := TTyPopupMenu.Create(FForm);
  mi := TMenuItem.Create(pm);
  mi.Caption := 'One';
  pm.Items.Add(mi);
  b.DropDownMenu := pm;
  b.HandleNeeded;
  b.DropDownForTest;
  try
    AssertTrue('the menu knows the button raised it', pm.PopupComponent = b);
    AssertTrue('so it reads right to left', pm.RendererForTest.RightToLeft);
    f := GetParentForm(pm.RendererForTest.ViewForTest);
    AssertNotNull('setup: the menu is up', f);
    right := b.ClientToScreen(Point(b.Width, 0)).X;
    AssertTrue(Format('it drops from the button''s right edge (%d, the menu ends at %d)', [right, f.Left + f.Width]), Abs(f.Left + f.Width - right) <= 2);
  finally
    pm.Close;
  end;
end;

procedure TRtlReachTest.TestADropDownButtonsArrowAnswersOnTheLeft;
var
  b: TTyDropDownButton;
begin
  b := TTyDropDownButton(NewOn(FForm, TTyDropDownButton, FCtl, 120, 30));
  b.Caption := 'Go';
  AssertTrue('setup: the arrow answers on the right', TDropAcc(b).IsInArrowZone(115));
  AssertFalse('setup: not on the left', TDropAcc(b).IsInArrowZone(3));
  b.BiDiMode := bdRightToLeft;
  AssertTrue('mirrored, where it is drawn: on the left', TDropAcc(b).IsInArrowZone(3));
  AssertFalse('and not on the right', TDropAcc(b).IsInArrowZone(115));
end;

procedure TRtlReachTest.TestListRowsMirror;
var
  adv: TTyAdvancedListBox;
  fl: TTyFontListBox;
  ol: TTyOfficeListBox;
  l, r: Integer;
begin
  FCtl.LoadThemeCss('TyListBox { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
    'TyListItem { color: #00FF00; padding: 0px; }' +
    'TyGroupBox { color: #00FF00; background: #FFFFFF; }');
  adv := TTyAdvancedListBox(NewOn(FForm, TTyAdvancedListBox, FCtl, 200, 30));
  adv.ItemHeight := 24;
  adv.AddItem('Name', '', -1);
  GreenSpan(adv, 200, 30, False, l, r);
  AssertTrue('setup: an advanced row starts on the left', (l >= 0) and (l < 12));
  GreenSpan(adv, 200, 30, True, l, r);
  AssertTrue('mirrored, it hugs the right edge', r > 200 - 12);
  AssertTrue('and has left the left edge', l > 100);

  fl := TTyFontListBox(NewOn(FForm, TTyFontListBox, FCtl, 200, 30));
  fl.ItemHeight := 24;
  fl.Items.Clear;
  fl.Items.Add('Arial');
  GreenSpan(fl, 200, 30, True, l, r);
  AssertTrue('a mirrored font row hugs the right edge', (l > 100) and (r > 200 - 12));

  ol := TTyOfficeListBox(NewOn(FForm, TTyOfficeListBox, FCtl, 200, 30));
  ol.ItemHeight := 24;
  ol.AddHeader('Head');
  GreenSpan(ol, 200, 30, False, l, r);
  AssertTrue('setup: an Office header starts on the left', (l >= 0) and (l < 12));
  GreenSpan(ol, 200, 30, True, l, r);
  AssertTrue('mirrored, it hugs the right edge', (l > 100) and (r > 200 - 12));
end;

procedure TRtlReachTest.TestHeadersMirror;
var
  ex: TTyExPanel;
  cd: TTyCard;
  l, r: Integer;
begin
  FCtl.LoadThemeCss(
    'TyExPanel { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
    'TyExPanelHeader { background: #FFFFFF; color: #00FF00; }' +
    'TyCard { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
    'TyCardHeader { color: #00FF00; padding: 0px; }');
  ex := TTyExPanel(NewOn(FForm, TTyExPanel, FCtl, 200, 60));
  ex.Caption := 'Cap';
  GreenSpan(ex, 200, 60, False, l, r);
  AssertTrue('setup: the expander''s header starts on the left', (l >= 0) and (r < 100));
  GreenSpan(ex, 200, 60, True, l, r);
  AssertTrue('mirrored, it is on the right', l > 100);
  { the caption stops short of the chevron's gutter at the right end, as it starts after it on
    the left: the header is 26 high, so the gutter is 26 wide }
  AssertTrue('and the caption ends before the gutter', GreenIn(ex, 200, 60, 150, 172));

  cd := TTyCard(NewOn(FForm, TTyCard, FCtl, 200, 120));
  cd.Title := 'Cap';
  GreenSpan(cd, 200, 120, False, l, r);
  AssertTrue('setup: the card''s title starts on the left', (l >= 0) and (r < 100));
  GreenSpan(cd, 200, 120, True, l, r);
  AssertTrue('mirrored, it is on the right', l > 100);
end;

{ The title's two paddings change sides with it: a leading pad of 40 is on the right mirrored. }
procedure TRtlReachTest.TestACardTitlesLeadingPaddingChangesSides;
var
  cd: TTyCard;
  l, r: Integer;
begin
  FCtl.LoadThemeCss(
    'TyCard { background: #FFFFFF; border-width: 0px; padding: 0px; }' +
    'TyCardHeader { color: #00FF00; padding: 0px 0px 0px 40px; }');
  cd := TTyCard(NewOn(FForm, TTyCard, FCtl, 200, 120));
  cd.Title := 'Cap';
  GreenSpan(cd, 200, 120, False, l, r);
  AssertTrue('setup: the title starts after its leading pad', (l >= 40) and (l < 52));
  GreenSpan(cd, 200, 120, True, l, r);
  AssertTrue('mirrored, it ends before the pad, now on the right', (r < 161) and (r > 140));
end;

procedure TRtlReachTest.TestAPaintPanelsCaptionMirrorsAndItsOwnerDrawDoesNot;
var
  pp: TTyPaintPanel;
  host: TBitmap;
  shot: TBGRABitmap;
  l, r: Integer;
begin
  FCtl.LoadThemeCss(
    'TyPanel { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }' +
    'TyPaintPanel { background: #FFFFFF; color: #00FF00; border-width: 0px; padding: 0px; }');
  pp := TTyPaintPanel(NewOn(FForm, TTyPaintPanel, FCtl, 200, 30));
  pp.Caption := 'Cap';
  pp.Alignment := taLeftJustify;
  GreenSpan(pp, 200, 30, False, l, r);
  AssertTrue('setup: the caption on the left', (l >= 0) and (r < 100));
  GreenSpan(pp, 200, 30, True, l, r);
  AssertTrue('mirrored, on the right', l > 100);

  pp.OnPaintSurface := @PaintLeftBlock;
  host := TBitmap.Create;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(200, 30);
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(0, 0, 200, 30);
    TPaintAcc(pp).RenderTo(host.Canvas, Rect(0, 0, 200, 30), 96);
    shot := TBGRABitmap.Create(host);
    try
      ChannelSpan(shot, False, l, r);
      AssertTrue('the app''s own drawing stays where it drew it', (l >= 0) and (r < 12));
    finally
      shot.Free;
    end;
  finally
    host.Free;
  end;
end;

procedure TRtlReachTest.TestAPopupMenuReadsItsOwnBiDiMode;
var
  pm: TTyPopupMenu;
  mi: TMenuItem;
begin
  FForm.SetBounds(-4000, -4000, 400, 300);
  FForm.Visible := True;
  pm := TTyPopupMenu.Create(FForm);
  mi := TMenuItem.Create(pm);
  mi.Caption := 'One';
  pm.Items.Add(mi);
  pm.PopUp(100, 100);
  try
    AssertFalse('setup: on a left-to-right form it reads left to right',
      pm.RendererForTest.RightToLeft);
  finally
    pm.Close;
  end;
  pm.BiDiMode := bdRightToLeft;
  pm.PopUp(100, 100);
  try
    AssertTrue('its own BiDiMode is read', pm.RendererForTest.RightToLeft);
  finally
    pm.Close;
  end;
end;

procedure TRtlReachTest.TestTheGlowAndShadowLabelsMirror;
var
  g: TTyGlowLabel;
  s: TTyShadowLabel;
  l, r: Integer;
begin
  FCtl.LoadThemeCss('TyGlowLabel { color: #00FF00; padding: 0px; }' +
    'TyShadowLabel { color: #00FF00; padding: 0px; }');
  g := TTyGlowLabel(NewOn(FForm, TTyGlowLabel, FCtl, 200, 30));
  g.Caption := 'Cap';
  g.GlowColor := clBlack;
  GreenSpan(g, 200, 30, False, l, r);
  AssertTrue('setup: the glow label on the left', (l >= 0) and (r < 100));
  GreenSpan(g, 200, 30, True, l, r);
  AssertTrue('mirrored, on the right', l > 100);
  s := TTyShadowLabel(NewOn(FForm, TTyShadowLabel, FCtl, 200, 30));
  s.Caption := 'Cap';
  s.ShadowColor := clBlack;
  GreenSpan(s, 200, 30, False, l, r);
  AssertTrue('setup: the shadow label on the left', (l >= 0) and (r < 100));
  GreenSpan(s, 200, 30, True, l, r);
  AssertTrue('mirrored, on the right', l > 100);
end;

procedure TRtlReachTest.TestAnHtmlLabelsLinksAnswerWhereTheyAreDrawn;
var
  h: TTyHtmlLabel;
begin
  h := TTyHtmlLabel(NewOn(FForm, TTyHtmlLabel, FCtl, 200, 30));
  h.Html := '<a href="x">Link</a>';
  h.OnLinkClick := @LinkClicked;
  THtmlAcc(h).MouseUp(mbLeft, [], 6, 5);
  AssertEquals('setup: the link is on the left', 'x', FHref);
  FHref := '';
  h.BiDiMode := bdRightToLeft;
  THtmlAcc(h).MouseUp(mbLeft, [], 6, 5);
  AssertEquals('mirrored, not on the left', '', FHref);
  THtmlAcc(h).MouseUp(mbLeft, [], 194, 5);
  AssertEquals('but on the right, where it is drawn', 'x', FHref);
end;

procedure TRtlReachTest.TestAnAlertsCloseButtonIsOnTheLeft;
var
  a: TTyAlert;
  rc: TRect;
begin
  a := TTyAlert(NewOn(FForm, TTyAlert, FCtl, 300, 40));
  a.Message := 'Hi';
  a.Closable := True;
  rc := a.TyAlertCloseRect;
  AssertTrue('setup: the close button is on the right', rc.Left > 150);
  a.BiDiMode := bdRightToLeft;
  rc := a.TyAlertCloseRect;
  AssertTrue('mirrored, on the left', (rc.Right > rc.Left) and (rc.Right < 150));
end;

initialization
  RegisterTest(TRtlReachTest);
end.
