unit test.listview.inset;
{ #98: where a report row's icon and caption start.

  --listview-text-margin is the inset of the cell's content, whichever comes first: the
  header already put its column icon there, the rows put theirs 2 px from the edge whatever
  the margin, so the two never lined up and a larger margin only pushed the caption away
  from its icon. The rows now start the icon at the margin too, and the gap between icon and
  caption is a token of its own (--listview-icon-gap, 2 px by default, so the captions stay
  where they were). Both are read per control, so a single list can change them in its
  StyleOverride (StyleMetric, test.stylemetric).

  The icon is a solid red square; where it lands is read off the rendered list. The caption
  starts where the inline editor is put, which is the same geometry. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, Controls, ImgList, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.Edit,
  tyControls.ListView.Layout, tyControls.ListView;

type
  TLvInsetAccess = class(TTyListView)
  public
    procedure XRender(ABmp: TBitmap);
    function XEditor: TTyEdit;
  end;

  TListViewInsetTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FImages: TImageList;
    FLV: TLvInsetAccess;
    { the left edge of each red run down the rendered list: [0] the header's column icon,
      [1..] the rows' icons }
    function IconLefts: TIntegerDynArray;
    function HeaderIconLeft: Integer;
    function RowIconLeft: Integer;
    { where the first row's caption starts: the inline editor's left edge }
    function CaptionLeft: Integer;
    { the leftmost dark (caption) pixel on the first row, right of its icon }
    function CaptionInkLeft: Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRowIconLinesUpWithTheHeaderIcon;
    procedure TestRowIconFollowsTheTextMargin;
    procedure TestCaptionFollowsTheIconGap;
    procedure TestThePaintedCaptionFollowsTheGapToo;
    procedure TestAutoFitCountsTheGap;
    procedure TestTheThemeSetsItForEveryList;
  end;

implementation

const
  ICON = 16;

procedure TLvInsetAccess.XRender(ABmp: TBitmap);
begin
  RenderTo(ABmp.Canvas, Rect(0, 0, Width, Height), 96);
end;

function TLvInsetAccess.XEditor: TTyEdit;
begin
  Result := InlineEditor;
end;

procedure TListViewInsetTest.SetUp;
var
  b: TBitmap;
  c: TTyColumn;
  i: Integer;
begin
  FCtl := TTyStyleController.Create(nil);
  FImages := TImageList.Create(nil);
  FImages.Width := ICON;
  FImages.Height := ICON;
  b := TBitmap.Create;
  try
    b.PixelFormat := pf24bit;
    b.SetSize(ICON, ICON);
    b.Canvas.Brush.Color := RGBToColor(255, 0, 0);
    b.Canvas.FillRect(0, 0, ICON, ICON);
    FImages.Add(b, nil);
  finally
    b.Free;
  end;
  FLV := TLvInsetAccess.Create(nil);
  FLV.Controller := FCtl;
  FLV.Font.PixelsPerInch := 96;
  FLV.SetBounds(0, 0, 320, 160);
  FLV.ViewStyle := lvsReport;
  FLV.SmallImages := FImages;
  FLV.ReadOnly := False;
  c := FLV.Header.Columns.Add as TTyColumn;
  c.Text := 'Name';
  c.Width := 200;
  c.ImageIndex := 0;
  for i := 0 to 1 do
    with FLV.Items.Add do
    begin
      Caption := 'Item ' + IntToStr(i);
      ImageIndex := 0;
    end;
end;

procedure TListViewInsetTest.TearDown;
begin
  FLV.Free;
  FImages.Free;
  FCtl.Free;
end;

function TListViewInsetTest.IconLefts: TIntegerDynArray;
var
  bmp: TBitmap;
  bg: TBGRABitmap;
  x, y, minX, n: Integer;
  inRun: Boolean;
  p: TBGRAPixel;
begin
  Result := nil;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FLV.Width, FLV.Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    FLV.XRender(bmp);
    bg := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
  try
    inRun := False;
    n := 0;
    for y := 0 to bg.Height - 1 do
    begin
      minX := -1;
      for x := 0 to bg.Width - 1 do
      begin
        p := bg.GetPixel(x, y);
        if (p.red > 200) and (p.green < 60) and (p.blue < 60) then
        begin
          minX := x;
          Break;
        end;
      end;
      if minX >= 0 then
      begin
        if not inRun then
        begin
          Inc(n);
          SetLength(Result, n);
          Result[n - 1] := minX;
          inRun := True;
        end
        else if minX < Result[n - 1] then
          Result[n - 1] := minX;
      end
      else
        inRun := False;
    end;
  finally
    bg.Free;
  end;
end;

function TListViewInsetTest.HeaderIconLeft: Integer;
var
  a: TIntegerDynArray;
begin
  a := IconLefts;
  AssertTrue('precondition: the header icon and the rows'' icons are drawn', Length(a) >= 3);
  Result := a[0];
end;

function TListViewInsetTest.RowIconLeft: Integer;
var
  a: TIntegerDynArray;
begin
  a := IconLefts;
  AssertTrue('precondition: the header icon and the rows'' icons are drawn', Length(a) >= 3);
  AssertEquals('every row''s icon at the same x', a[1], a[2]);
  Result := a[1];
end;

function TListViewInsetTest.CaptionLeft: Integer;
begin
  FLV.BeginEdit(0);
  AssertTrue('precondition: the inline editor opened', FLV.Editing);
  Result := FLV.XEditor.Left;
  FLV.EndEdit(False);
end;

function TListViewInsetTest.CaptionInkLeft: Integer;
var
  bmp: TBitmap;
  bg: TBGRABitmap;
  x, y, top, from: Integer;
  p: TBGRAPixel;
begin
  from := RowIconLeft + ICON;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(FLV.Width, FLV.Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    FLV.XRender(bmp);
    bg := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
  try
    { the first row's band: from the row icon's top down 16 px }
    top := -1;
    for y := 0 to bg.Height - 1 do
      if (bg.GetPixel(RowIconLeft, y).red > 200) and (bg.GetPixel(RowIconLeft, y).green < 60)
         and (y > 0) and not ((bg.GetPixel(RowIconLeft, y - 1).red > 200)
                              and (bg.GetPixel(RowIconLeft, y - 1).green < 60)) then
      begin
        if top < 0 then top := y   { the header icon }
        else begin top := y; Break; end;
      end;
    for x := from to bg.Width - 1 do
      for y := top to top + ICON - 1 do
      begin
        p := bg.GetPixel(x, y);
        if (p.red < 110) and (p.green < 110) and (p.blue < 110) then Exit(x);
      end;
  finally
    bg.Free;
  end;
  Fail('precondition: the first row''s caption is drawn');
  Result := -1;
end;

procedure TListViewInsetTest.TestThePaintedCaptionFollowsTheGapToo;
var
  ink: Integer;
begin
  ink := CaptionInkLeft;
  FLV.StyleOverride := '--listview-icon-gap: 9px';
  AssertEquals('the painted caption moves with the gap, as the editor does', ink + 7,
    CaptionInkLeft);
end;

procedure TListViewInsetTest.TestRowIconLinesUpWithTheHeaderIcon;
begin
  AssertEquals('the row icon starts where the header icon does', HeaderIconLeft, RowIconLeft);
end;

procedure TListViewInsetTest.TestRowIconFollowsTheTextMargin;
var
  base: Integer;
begin
  base := RowIconLeft;
  FLV.StyleOverride := '--listview-text-margin: 16px';
  AssertEquals('a 16 px margin moves the row icon 12 px in (from 4)', base + 12, RowIconLeft);
  AssertEquals('...and the header icon with it', RowIconLeft, HeaderIconLeft);
end;

procedure TListViewInsetTest.TestCaptionFollowsTheIconGap;
begin
  AssertEquals('the caption 2 px after the icon by default', 2,
    CaptionLeft - (RowIconLeft + ICON));
  FLV.StyleOverride := '--listview-icon-gap: 9px';
  AssertEquals('--listview-icon-gap sets it', 9, CaptionLeft - (RowIconLeft + ICON));
  FLV.StyleOverride := '--listview-text-margin: 16px; --listview-icon-gap: 9px';
  AssertEquals('with a margin too', 9, CaptionLeft - (RowIconLeft + ICON));
end;

procedure TListViewInsetTest.TestAutoFitCountsTheGap;
var
  w: Integer;
begin
  FLV.AutoFitColumn(0);
  w := FLV.Header.Columns[0].Width;
  FLV.StyleOverride := '--listview-icon-gap: 9px';
  FLV.AutoFitColumn(0);
  AssertEquals('a 7 px wider gap fits a 7 px wider column', w + 7, FLV.Header.Columns[0].Width);
end;

procedure TListViewInsetTest.TestTheThemeSetsItForEveryList;
begin
  FCtl.StyleOverride := ':root { --listview-icon-gap: 6px; --listview-text-margin: 10px; }';
  AssertEquals('the theme''s gap', 6, CaptionLeft - (RowIconLeft + ICON));
  AssertEquals('the theme''s margin lines the row icon up with the header''s', HeaderIconLeft,
    RowIconLeft);
end;

initialization
  RegisterTest(TListViewInsetTest);
end.
