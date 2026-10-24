unit test.chevron;
{$mode objfpc}{$H+}

{ The disclosure chevron: the V and > a drop field, a tree node, a submenu row, a list group, an
  expander and an inspector row draw. Measured against Windows 11, macOS and GNOME, the library
  drew a shafted arrow for submenus, filled triangles for two expanders, and chevrons that
  filled whatever slot they were given -- five sizes and four stroke weights for one mark, the
  1px ones straddling two pixels. These pin the one mark that replaced them:

  - the painter draws ONE size whatever the slot, with a solid pixel at 100 % and 200 %;
  - every site goes through the themable routine (a theme that blanks the token blanks the
    mark -- font-independent, the space codepoint has no ink in any font);
  - and at every site the mark is the 7px chevron's size, which each of the old marks the
    sites drew exceeded or bypassed. }

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, Menus, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  test.dpi.support,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Form,
  tyControls.ComboBox, tyControls.DateTimePicker, tyControls.TreeView, tyControls.Menu,
  tyControls.ExPanel, tyControls.ListGroupPanel, tyControls.ListView, tyControls.ListView.Layout,
  tyControls.ValueListEditor,
  tyControls.Ribbon;

type
  TChevronMenuProbe = class(TTyMenuView)
  public
    function W(APPI: Integer): Integer;
    function H(APPI: Integer): Integer;
  end;

  TInkBox = record
    N: Integer;     // pixels that changed
    R: TRect;       // their bounding box (empty when N = 0)
  end;

  TChevronTest = class(TTestCase)
  private
    FCss: string;
    FKind: Integer;
    function PaintShot(AKind: Integer; const ACss: string): TBitmap;
    function Erased(AKind: Integer; const AToken: string): TInkBox;
    procedure CheckMark(const AWhat: string; AKind: Integer; const AToken: string;
      APointsSideways: Boolean);
  published
    { painter }
    procedure TestOneSizeWhateverTheZone;
    procedure TestEveryDirectionHasASolidPixel;
    procedure TestTheMarkIsCentredAndPointsItsWay;
    procedure TestInkIsTheTextColourAtTheThemesAlpha;
    procedure TestDropChevronAsksForGlyphDropdownItself;
    procedure TestExPanelChevronKind;
    { sites }
    procedure TestMenuSubmenuMarkIsTheChevron;
    procedure TestRibbonCollapseMarkIsTheChevron;
    procedure TestExPanelHeaderMarkIsTheChevron;
    procedure TestInspectorRowMarkIsTheChevron;
    procedure TestListViewGroupMarkIsTheChevron;
    procedure TestTreeNodeMarkIsTheChevron;
    procedure TestListGroupHeaderMarkIsTheChevron;
    procedure TestComboBoxDropMarkIsTheChevron;
    procedure TestDateTimePickerHonoursGlyphDropdown;
  end;

implementation

const
  KMenu = 0; KRibbon = 1; KExPanel = 2; KInspector = 3; KListView = 4; KTree = 5;
  KListGroup = 6; KCombo = 7; KPicker = 8;
  { A blank replacement: valid token, no ink in any font. }
  CBlank = '"Arial" "\20"';
  { The 7px chevron at 96 PPI: centre line 3.5 x 7 plus a 1.25 stroke, so ink of about 5 x 9
    with the antialiased fringe. The bounds leave a pixel either way; every mark the sites drew
    before was outside them on one axis (tree 7x12, list group 12x7, menu arrow 10x8, ExPanel
    triangle 11x10, drop V 11x7) or never went through a token at all. }
  CNarrowMin = 3; CNarrowMax = 7;
  CLongMin = 6;   CLongMax = 10;

function TChevronMenuProbe.W(APPI: Integer): Integer;
begin
  Result := MeasureWidth(APPI);
end;

function TChevronMenuProbe.H(APPI: Integer): Integer;
begin
  Result := MeasureHeight(APPI);
end;

{ ---- helpers ------------------------------------------------------------------------------ }

function Coverage(const px: TBGRAPixel): Double;
begin
  Result := (px.alpha / 255) * (1 - (px.red * 0.299 + px.green * 0.587 + px.blue * 0.114) / 255);
end;

{ The ink box of what a painter call drew in black on white, at >= 10 % coverage. }
function PaintedBox(ABmp: TBGRABitmap; out APeak: Double): TRect;
var
  x, y: Integer;
  c: Double;
begin
  Result := Rect(MaxInt, MaxInt, -1, -1);
  APeak := 0;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
    begin
      c := Coverage(ABmp.GetPixel(x, y));
      if c > APeak then APeak := c;
      if c >= 0.10 then
      begin
        if x < Result.Left then Result.Left := x;
        if y < Result.Top then Result.Top := y;
        if x + 1 > Result.Right then Result.Right := x + 1;
        if y + 1 > Result.Bottom then Result.Bottom := y + 1;
      end;
    end;
  if Result.Right < 0 then Result := Rect(0, 0, 0, 0);
end;

function DrawOne(AW, AH, APPI: Integer; AKind: TTyGlyphKind; out APeak: Double): TRect;
var
  P: TTyPainter;
  b: TBGRABitmap;
begin
  b := TBGRABitmap.Create(AW, AH, BGRAWhite);
  P := TTyPainter.Create;
  try
    P.BeginPaintOn(nil, Rect(0, 0, AW, AH), APPI, b);
    P.DrawChevron(Rect(0, 0, AW, AH), AKind, TyRGBA(0, 0, 0, 255), 7);
    P.EndPaint;
    Result := PaintedBox(b, APeak);
  finally
    P.Free;
    b.Free;
  end;
end;

function DiffBox(A, B: TBitmap): TInkBox;
var
  ba, bb: TBGRABitmap;
  x, y: Integer;
  pa, pb: TBGRAPixel;
begin
  Result.N := 0;
  Result.R := Rect(MaxInt, MaxInt, -1, -1);
  ba := TBGRABitmap.Create(A);
  bb := TBGRABitmap.Create(B);
  try
    for y := 0 to Min(ba.Height, bb.Height) - 1 do
      for x := 0 to Min(ba.Width, bb.Width) - 1 do
      begin
        pa := ba.GetPixel(x, y);
        pb := bb.GetPixel(x, y);
        if (Abs(pa.red - pb.red) > 6) or (Abs(pa.green - pb.green) > 6) or
           (Abs(pa.blue - pb.blue) > 6) then
        begin
          Inc(Result.N);
          if x < Result.R.Left then Result.R.Left := x;
          if y < Result.R.Top then Result.R.Top := y;
          if x + 1 > Result.R.Right then Result.R.Right := x + 1;
          if y + 1 > Result.R.Bottom then Result.R.Bottom := y + 1;
        end;
      end;
  finally
    ba.Free;
    bb.Free;
  end;
  if Result.N = 0 then Result.R := Rect(0, 0, 0, 0);
end;

{ One control on a host, painted headless (TyTestPaintTree, as the DPI snapshot tests do) at
  96 PPI under a controller whose theme is the stock one plus ACss. }
function TChevronTest.PaintShot(AKind: Integer; const ACss: string): TBitmap;
var
  ctl: TTyStyleController;
  host: TTyForm;
  c: TControl;
  w, h: Integer;
  mm: TPopupMenu;
  sub, it: TMenuItem;
  v: TChevronMenuProbe;
  rib: TTyRibbon;
  ex: TTyExPanel;
  vle: TTyValueListEditor;
  row: TTyValueRow;
  lv: TTyListView;
  g: TTyListGroup;
  li: TTyListItem;
  tv: TTyTreeView;
  nd: TTyTreeNodeItem;
  lg: TTyListGroupPanel;
  gi: Integer;
  cb: TTyComboBox;
  dt: TTyDateTimePicker;
begin
  ctl := TTyStyleController.Create(nil);
  host := TTyForm.CreateNew(nil);
  mm := nil;
  try
    ctl.LoadThemeCss(ACss);
    w := 220;
    h := 120;
    case AKind of
      KMenu:
        begin
          mm := TPopupMenu.Create(nil);
          mm.Items.Add(NewItem('Open', 0, False, True, nil, 0, ''));
          sub := TMenuItem.Create(mm);
          sub.Caption := 'Recent';
          it := TMenuItem.Create(mm);
          it.Caption := 'doc.txt';
          sub.Add(it);
          mm.Items.Add(sub);
          v := TChevronMenuProbe.Create(host);
          v.Font.PixelsPerInch := 96;
          v.Controller := ctl;
          v.SetRows(TyBuildMenuRows(mm.Items));
          w := v.W(96);
          h := v.H(96);
          c := v;
        end;
      KRibbon:
        begin
          rib := TTyRibbon.Create(host);
          rib.Font.PixelsPerInch := 96;
          rib.Controller := ctl;
          rib.AddPage('Home');
          w := 400;
          h := 140;
          c := rib;
        end;
      KExPanel:
        begin
          ex := TTyExPanel.Create(host);
          ex.Font.PixelsPerInch := 96;
          ex.Controller := ctl;
          ex.Caption := 'Panel';
          c := ex;
        end;
      KInspector:
        begin
          vle := TTyValueListEditor.Create(host);
          vle.Font.PixelsPerInch := 96;
          vle.Controller := ctl;
          vle.AddRow('A', '1');
          row := vle.AddRow('Font', '(node)');
          row.AddChild('Size', '9');
          vle.SetExpanded(row, False);
          c := vle;
        end;
      KListView:
        begin
          lv := TTyListView.Create(host);
          lv.Font.PixelsPerInch := 96;
          lv.Controller := ctl;
          lv.ViewStyle := lvsSmallIcon;
          g := lv.Groups.Add;
          g.Caption := 'Group';
          li := lv.Items.Add;
          li.Caption := 'item';
          li.GroupIndex := 0;
          lv.GroupView := True;
          c := lv;
        end;
      KTree:
        begin
          tv := TTyTreeView.Create(host);
          tv.Font.PixelsPerInch := 96;
          tv.Controller := ctl;
          nd := tv.Items.Add(nil, 'Collapsed');
          tv.Items.AddChild(nd, 'child');
          nd := tv.Items.Add(nil, 'Expanded');
          tv.Items.AddChild(nd, 'child');
          nd.Expanded := True;
          c := tv;
        end;
      KListGroup:
        begin
          lg := TTyListGroupPanel.Create(host);
          lg.Font.PixelsPerInch := 96;
          lg.Controller := ctl;
          gi := lg.AddGroup('Collapsed');
          lg.AddItem(gi, 'item');
          lg.Expanded[gi] := False;
          gi := lg.AddGroup('Expanded');
          lg.AddItem(gi, 'item');
          lg.Expanded[gi] := True;
          c := lg;
        end;
      KCombo:
        begin
          cb := TTyComboBox.Create(host);
          cb.Font.PixelsPerInch := 96;
          cb.Controller := ctl;
          cb.Items.Add('Item');
          cb.ItemIndex := 0;
          h := 28;
          c := cb;
        end;
    else
      begin
        dt := TTyDateTimePicker.Create(host);
        dt.Font.PixelsPerInch := 96;
        dt.Controller := ctl;
        dt.Kind := dtkDate;
        h := 28;
        c := dt;
      end;
    end;
    host.SetBounds(0, 0, w, h);
    c.Parent := host;
    c.SetBounds(0, 0, w, h);
    TyTestSettle(host);
    Result := TBitmap.Create;
    Result.PixelFormat := pf24bit;
    Result.SetSize(w, h);
    Result.Canvas.Brush.Color := clWhite;
    Result.Canvas.FillRect(0, 0, w, h);
    TyTestPaintTree(host, Result, nil);
  finally
    host.Free;
    mm.Free;
    ctl.Free;
  end;
end;

{ What blanking AToken removed from the control's picture: the mark it reaches, and nothing
  else (no other part of these controls draws through those tokens). }
function TChevronTest.Erased(AKind: Integer; const AToken: string): TInkBox;
var
  a, b: TBitmap;
begin
  a := PaintShot(AKind, ':root { --chevron-test-baseline: 1px; }');
  b := nil;
  try
    b := PaintShot(AKind, ':root { ' + AToken + ': ' + CBlank + '; }');
    Result := DiffBox(a, b);
  finally
    a.Free;
    b.Free;
  end;
end;

{ AToken reaches the site's mark, and the mark is the 7px chevron. APointsSideways: a > or <
  (narrow and tall) rather than a V or ^ (wide and short). Where a control draws two marks with
  the same token the box spans both, so those tests pick a token only one of them uses. }
procedure TChevronTest.CheckMark(const AWhat: string; AKind: Integer; const AToken: string;
  APointsSideways: Boolean);
var
  e: TInkBox;
  w, h: Integer;
begin
  e := Erased(AKind, AToken);
  AssertTrue(AWhat + ': blanking ' + AToken + ' removes the mark (it goes through the themable chevron)',
    e.N > 0);
  w := e.R.Right - e.R.Left;
  h := e.R.Bottom - e.R.Top;
  if APointsSideways then
  begin
    AssertTrue(Format('%s: the mark is %d px wide, the 7px chevron''s %d..%d', [AWhat, w, CNarrowMin, CNarrowMax]),
      (w >= CNarrowMin) and (w <= CNarrowMax));
    AssertTrue(Format('%s: the mark is %d px tall, the 7px chevron''s %d..%d', [AWhat, h, CLongMin, CLongMax]),
      (h >= CLongMin) and (h <= CLongMax));
  end
  else
  begin
    AssertTrue(Format('%s: the mark is %d px wide, the 7px chevron''s %d..%d', [AWhat, w, CLongMin, CLongMax]),
      (w >= CLongMin) and (w <= CLongMax));
    AssertTrue(Format('%s: the mark is %d px tall, the 7px chevron''s %d..%d', [AWhat, h, CNarrowMin, CNarrowMax]),
      (h >= CNarrowMin) and (h <= CNarrowMax));
  end;
end;

{ ---- painter --------------------------------------------------------------------------------- }

procedure TChevronTest.TestOneSizeWhateverTheZone;
const
  CZones: array[0..3] of TSize = ((cx: 12; cy: 12), (cx: 16; cy: 16), (cx: 22; cy: 22), (cx: 40; cy: 28));
  CKinds: array[0..3] of TTyGlyphKind = (tgChevronDown, tgChevronRight, tgChevronLeft, tgChevronUp);
var
  k, z: Integer;
  r, first: TRect;
  peak: Double;
begin
  { The slot places the mark; it does not size it. DrawGlyph's chevrons stretched to their box,
    which is how one library ended up with a 5px and a 13px version of the same V. }
  for k := 0 to High(CKinds) do
  begin
    first := DrawOne(CZones[0].cx, CZones[0].cy, 96, CKinds[k], peak);
    for z := 1 to High(CZones) do
    begin
      r := DrawOne(CZones[z].cx, CZones[z].cy, 96, CKinds[k], peak);
      AssertEquals(Format('kind %d: same width in a %dx%d zone', [Ord(CKinds[k]), CZones[z].cx, CZones[z].cy]),
        first.Right - first.Left, r.Right - r.Left);
      AssertEquals(Format('kind %d: same height in a %dx%d zone', [Ord(CKinds[k]), CZones[z].cx, CZones[z].cy]),
        first.Bottom - first.Top, r.Bottom - r.Top);
    end;
  end;
end;

procedure TChevronTest.TestEveryDirectionHasASolidPixel;
const
  CKinds: array[0..3] of TTyGlyphKind = (tgChevronDown, tgChevronRight, tgChevronLeft, tgChevronUp);
var
  k, ppi: Integer;
  peak: Double;
begin
  { The old 1px chevron put its points at x.3 and its darkest pixel at 0.64: a grey smear at
    100 %. The apex on a pixel centre and a 1.25 stroke (what BGRA's linear-light blending needs
    to carry the ink Direct2D gives 1px) leave at least one solid pixel. }
  for ppi := 1 to 2 do
    for k := 0 to High(CKinds) do
    begin
      DrawOne(24 * ppi, 24 * ppi, 96 * ppi, CKinds[k], peak);
      AssertTrue(Format('kind %d at %d PPI: darkest pixel %.2f, not a two-pixel smear',
        [Ord(CKinds[k]), 96 * ppi, peak]), peak >= 0.9);
    end;
end;

procedure TChevronTest.TestTheMarkIsCentredAndPointsItsWay;
const
  CKinds: array[0..3] of TTyGlyphKind = (tgChevronDown, tgChevronUp, tgChevronRight, tgChevronLeft);
var
  k, i, mid, edge, tip: Integer;
  r: TRect;
  peak: Double;
  P: TTyPainter;
  b: TBGRABitmap;

  function Inked(x, y: Integer): Boolean;
  begin
    Result := Coverage(b.GetPixel(x, y)) >= 0.1;
  end;

begin
  for k := 0 to High(CKinds) do
  begin
    { The 24px zone's centre is 11.5 in pixel-centre coordinates; the ink box straddles it to
      within the half pixel the apex is rounded by. }
    r := DrawOne(24, 24, 96, CKinds[k], peak);
    AssertTrue(Format('kind %d centred across (%d..%d)', [Ord(CKinds[k]), r.Left, r.Right]),
      Abs((r.Left + r.Right - 1) / 2 - 11.5) <= 1);
    AssertTrue(Format('kind %d centred down (%d..%d)', [Ord(CKinds[k]), r.Top, r.Bottom]),
      Abs((r.Top + r.Bottom - 1) / 2 - 11.5) <= 1);
    { The apex is the point: on the middle line the ink reaches further in the pointing
      direction than on the box's edge line, where the arms' open ends are. }
    b := TBGRABitmap.Create(24, 24, BGRAWhite);
    P := TTyPainter.Create;
    try
      P.BeginPaintOn(nil, Rect(0, 0, 24, 24), 96, b);
      P.DrawChevron(Rect(0, 0, 24, 24), CKinds[k], TyRGBA(0, 0, 0, 255), 7);
      P.EndPaint;
      case CKinds[k] of
        tgChevronRight, tgChevronLeft:
          begin
            mid := (r.Top + r.Bottom) div 2;
            tip := -1; edge := -1;
            for i := 0 to 23 do
            begin
              if Inked(i, mid) and ((tip < 0) or ((CKinds[k] = tgChevronRight) = (i > tip))) then tip := i;
              if Inked(i, r.Top) and ((edge < 0) or ((CKinds[k] = tgChevronRight) = (i > edge))) then edge := i;
            end;
            if CKinds[k] = tgChevronRight then
              AssertTrue('> points right', tip > edge)
            else
              AssertTrue('< points left', tip < edge);
          end;
      else
        begin
          mid := (r.Left + r.Right) div 2;
          tip := -1; edge := -1;
          for i := 0 to 23 do
          begin
            if Inked(mid, i) and ((tip < 0) or ((CKinds[k] = tgChevronDown) = (i > tip))) then tip := i;
            if Inked(r.Left, i) and ((edge < 0) or ((CKinds[k] = tgChevronDown) = (i > edge))) then edge := i;
          end;
          if CKinds[k] = tgChevronDown then
            AssertTrue('V points down', tip > edge)
          else
            AssertTrue('^ points up', tip < edge);
        end;
      end;
    finally
      P.Free;
      b.Free;
    end;
  end;
end;

procedure TChevronTest.TestInkIsTheTextColourAtTheThemesAlpha;
var
  ctl: TTyStyleController;
begin
  AssertEquals('default: the colour, at TyChevronAlpha of its own alpha',
    Int64(TTyColor(TyChevronAlpha) shl 24 or $102030), Int64(TyChevronInk(nil, $FF102030)));
  AssertTrue('and that is lighter than the text', TyChevronAlpha < 255);
  AssertEquals('a half-transparent colour is dimmed proportionally',
    Int64(((128 * TyChevronAlpha) div 255) shl 24 or $102030), Int64(TyChevronInk(nil, $80102030)));
  ctl := TTyStyleController.Create(nil);
  try
    ctl.LoadThemeCss(':root { --glyph-chevron-alpha: 255; }');
    AssertEquals('255: full text colour', Int64($FF102030), Int64(TyChevronInk(ctl, $FF102030)));
    ctl.LoadThemeCss(':root { --glyph-chevron-alpha: 0; }');
    AssertEquals('0: no ink', Int64($00102030), Int64(TyChevronInk(ctl, $FF102030)));
  finally
    ctl.Free;
  end;
end;

procedure TChevronTest.TestDropChevronAsksForGlyphDropdownItself;

  function InkWith(const ACss: string): Double;
  var
    ctl: TTyStyleController;
    P: TTyPainter;
    b: TBGRABitmap;
  begin
    ctl := TTyStyleController.Create(nil);
    b := TBGRABitmap.Create(18, 28, BGRAWhite);
    P := TTyPainter.Create;
    try
      ctl.LoadThemeCss(ACss);
      P.BeginPaintOn(nil, Rect(0, 0, 18, 28), 96, b);
      TyDrawDropChevron(P, ctl, Rect(0, 0, 18, 28), TyRGBA(0, 0, 0, 255));
      P.EndPaint;
      PaintedBox(b, Result);
    finally
      P.Free;
      b.Free;
      ctl.Free;
    end;
  end;

begin
  { Six of the nine drop fields called TyDrawDropChevron without asking for the theme's
    --glyph-dropdown first, so a skin's drop mark reached a combo box and not the date picker
    beside it. The routine asks now, so every caller is covered by being a caller. }
  AssertTrue('the vector chevron draws', InkWith(':root { --chevron-test-baseline: 1px; }') > 0.5);
  AssertTrue('a blank --glyph-dropdown replaces it', InkWith(':root { --glyph-dropdown: ' + CBlank + '; }') < 0.05);
end;

procedure TChevronTest.TestExPanelChevronKind;
begin
  AssertTrue('expanded: down', TyExPanelChevronKind(True) = tgChevronDown);
  AssertTrue('collapsed: right', TyExPanelChevronKind(False) = tgChevronRight);
end;

{ ---- sites ----------------------------------------------------------------------------------- }

procedure TChevronTest.TestMenuSubmenuMarkIsTheChevron;
begin
  { Was tgArrowRight at 2px: a shaft and a head, 10px wide, painted straight through the
    painter so no theme could reach it. }
  CheckMark('menu submenu', KMenu, '--glyph-chevron-right', True);
end;

procedure TChevronTest.TestRibbonCollapseMarkIsTheChevron;
begin
  { An open ribbon offers to collapse: the chevron points up. Was tgArrowUp. }
  CheckMark('ribbon collapse', KRibbon, '--glyph-chevron-up', False);
end;

procedure TChevronTest.TestExPanelHeaderMarkIsTheChevron;
begin
  { Was a filled triangle 10px square, hand-filled on the Canvas2D. }
  CheckMark('ExPanel header', KExPanel, '--glyph-chevron-down', False);
end;

procedure TChevronTest.TestInspectorRowMarkIsTheChevron;
begin
  { Was a filled triangle hand-filled on the Canvas2D. }
  CheckMark('inspector row', KInspector, '--glyph-chevron-right', True);
end;

procedure TChevronTest.TestListViewGroupMarkIsTheChevron;
begin
  { Was P.DrawGlyph straight, so --glyph-chevron-down never reached it. }
  CheckMark('list view group', KListView, '--glyph-chevron-down', False);
end;

procedure TChevronTest.TestTreeNodeMarkIsTheChevron;
begin
  { Was the slot-filling > : 7x12 ink, taller than the caption's capitals. The tree has one
    collapsed node, so --glyph-chevron-right reaches exactly one mark. }
  CheckMark('tree node', KTree, '--glyph-chevron-right', True);
end;

procedure TChevronTest.TestListGroupHeaderMarkIsTheChevron;
begin
  { Was the slot-filling V: 12x7. One group is open, so --glyph-chevron-down reaches one mark. }
  CheckMark('list group header', KListGroup, '--glyph-chevron-down', False);
end;

procedure TChevronTest.TestComboBoxDropMarkIsTheChevron;
begin
  { Was the 9px V: 11x7 ink. }
  CheckMark('combo box', KCombo, '--glyph-dropdown', False);
end;

procedure TChevronTest.TestDateTimePickerHonoursGlyphDropdown;
begin
  { The picker drew its drop V without asking for --glyph-dropdown. }
  CheckMark('date picker', KPicker, '--glyph-dropdown', False);
end;

initialization
  RegisterTest(TChevronTest);
end.
