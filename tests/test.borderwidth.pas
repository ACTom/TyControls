unit test.borderwidth;
{ #115: BorderWidth is extra inner padding, in logical px. The themed frame stays at the edge;
  a container's children and a control's own content move in by it. It used to work on
  TTyPanel alone, unscaled, and nowhere else. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Edit, tyControls.GroupBox, tyControls.Panel,
  tyControls.GridPanel, tyControls.PageControl, tyControls.TabSheet, test.dpi.support;

type
  TBorderWidthTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAGroupBoxInsetsItsChildren;
    procedure TestAnEditsContentMovesIn;
    procedure TestItScalesWithThePPI;
    procedure TestAPanelsCaptionMovesIn;
    procedure TestGridPanelCellsMoveIn;
    procedure TestTabSheetsMoveInsideThePageFrame;
  end;

implementation

type
  TEditAcc = class(TTyEdit)
  public
    function Pad: Integer;
    function Want: Integer;
  end;

  TPanelAcc = class(TTyPanel);
  TWinAcc = class(TWinControl);

{ LCL's align pass on one container, headless: AlignControls adjusts the rect it is handed
  itself (wincontrol.inc:3259), so it gets the RAW client rect. }
procedure Realign(AControl: TWinControl);
var
  r: TRect;
begin
  r := AControl.ClientRect;
  TWinAcc(AControl).AlignControls(nil, r);
end;

function TEditAcc.Pad: Integer;
begin
  Result := CurrentStyle.Padding.Left;
end;

function TEditAcc.Want: Integer;
var
  w, h: Integer;
begin
  w := 0;
  h := 0;
  InvalidatePreferredSize;
  GetPreferredSize(w, h, True, False);
  Result := h;
end;

procedure TBorderWidthTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
end;

procedure TBorderWidthTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TBorderWidthTest.TestAGroupBoxInsetsItsChildren;
var
  g: TTyGroupBox;
  c: TTyPanel;
  r0: TRect;
begin
  g := TTyGroupBox.Create(FForm);
  g.Parent := FForm;
  g.Font.PixelsPerInch := 96;
  g.SetBounds(0, 0, 300, 200);
  c := TTyPanel.Create(FForm);
  c.Parent := g;
  c.Align := alClient;
  Realign(g);
  r0 := c.BoundsRect;
  g.BorderWidth := 8;
  Realign(g);
  AssertEquals('left moved in', r0.Left + 8, c.Left);
  AssertEquals('top moved in', r0.Top + 8, c.Top);
  AssertEquals('narrower by both sides', (r0.Right - r0.Left) - 16, c.Width);
  AssertEquals('shorter by both sides', (r0.Bottom - r0.Top) - 16, c.Height);
end;

procedure TBorderWidthTest.TestAnEditsContentMovesIn;
var
  e: TEditAcc;
  pad0, want0: Integer;
begin
  e := TEditAcc.Create(FForm);
  e.Parent := FForm;
  e.Font.PixelsPerInch := 96;
  e.SetBounds(0, 0, 150, 40);
  pad0 := e.Pad;
  want0 := e.Want;
  e.BorderWidth := 6;
  AssertEquals('the text moves in by it', pad0 + 6, e.Pad);
  AssertEquals('and AutoSize grows by both sides', want0 + 12, e.Want);
end;

procedure TBorderWidthTest.TestItScalesWithThePPI;
var
  g: TTyGroupBox;
begin
  g := TTyGroupBox.Create(FForm);
  g.BorderWidth := 8;
  g.Font.PixelsPerInch := 192;
  AssertEquals('logical px: twice as many device px at 200%', 16, g.BorderInsetPx);
end;

procedure TBorderWidthTest.TestAPanelsCaptionMovesIn;

  function LeftInk(AWidth: Integer): Integer;
  var
    p: TPanelAcc;
    bmp: TBitmap;
    b: TBGRABitmap;
    x, y: Integer;
    px: TBGRAPixel;
  begin
    Result := -1;
    p := TPanelAcc.Create(nil);
    bmp := TBitmap.Create;
    try
      p.SetBounds(0, 0, 240, 60);
      p.Caption := 'MMMM';
      p.Alignment := taLeftJustify;
      p.BorderWidth := AWidth;
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(240, 60);
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, 240, 60);
      p.RenderTo(bmp.Canvas, Rect(0, 0, 240, 60), 96);
      b := TBGRABitmap.Create(bmp);
      try
        for x := 4 to 239 do
        begin
          for y := 10 to 50 do
          begin
            px := b.GetPixel(x, y);
            if (px.red < 120) and (px.green < 120) and (px.blue < 120) then Exit(x);
          end;
        end;
      finally
        b.Free;
      end;
    finally
      bmp.Free;
      p.Free;
    end;
  end;

var
  x0, x1: Integer;
begin
  x0 := LeftInk(0);
  x1 := LeftInk(12);
  AssertTrue('precondition: the caption is drawn', x0 > 0);
  AssertEquals('the caption moved in by the width', x0 + 12, x1);
end;

procedure TBorderWidthTest.TestGridPanelCellsMoveIn;
var
  gp: TTyGridPanel;
  cell: TControl;
begin
  gp := TTyGridPanel.Create(FForm);
  gp.Parent := FForm;
  gp.Font.PixelsPerInch := 96;
  gp.SetBounds(0, 0, 200, 200);
  gp.BorderWidth := 10;
  gp.Width := 201;   // a resize lays the cells out again
  cell := TControl(gp.CellAt(0));
  AssertEquals('the first cell starts inside the band', 10, cell.Left);
  AssertEquals('and below it', 10, cell.Top);
end;

procedure TBorderWidthTest.TestTabSheetsMoveInsideThePageFrame;
var
  pc: TTyPageControl;
  sh: TTyTabSheet;
  r0: TRect;
begin
  pc := TTyPageControl.Create(FForm);
  pc.Parent := FForm;
  pc.Font.PixelsPerInch := 96;
  pc.SetBounds(0, 0, 300, 200);
  sh := pc.AddPage('One');
  Realign(pc);
  r0 := sh.BoundsRect;
  pc.BorderWidth := 7;
  Realign(pc);
  AssertEquals('the sheet moved in on the left', r0.Left + 7, sh.Left);
  AssertEquals('and below the band', r0.Top + 7, sh.Top);
  AssertEquals('narrower by both sides', (r0.Right - r0.Left) - 14, sh.Width);
end;

initialization
  RegisterTest(TBorderWidthTest);
end.
