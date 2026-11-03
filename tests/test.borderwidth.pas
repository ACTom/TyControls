unit test.borderwidth;
{ #115: BorderWidth is extra inner padding, in logical px. The themed frame stays at the edge;
  a container's children and a control's own content move in by it. It used to work on
  TTyPanel alone, unscaled, and nowhere else. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Edit, tyControls.GroupBox, tyControls.Panel,
  tyControls.GridPanel, tyControls.PageControl, tyControls.TabSheet, tyControls.Painter,
  tyControls.ControlBar, tyControls.PaintPanel, tyControls.ExPanel, tyControls.Segmented,
  tyControls.Steps, tyControls.ButtonGroup, test.dpi.support;

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
    { #115, second pass: what the first one missed. }
    procedure TestAControlBarGrowsByIt;
    procedure TestAPaintPanelsContentMovesIn;
    procedure TestAnExPanelsHeaderMovesIn;
    procedure TestTheSegmentedTrackMovesIn;
    procedure TestTheStepsCellsMoveIn;
    procedure TestTheSelectedSegmentsCaptionMovesIn;
  end;

implementation

type
  TEditAcc = class(TTyEdit)
  public
    function Pad: Integer;
    function Want: Integer;
  end;

  TPanelAcc = class(TTyPanel);
  TExAcc = class(TTyExPanel);
  TPaintAcc = class(TTyPaintPanel);
  TGroupAcc = class(TTyButtonGroup);
  { What a paint panel hands OnPaintSurface. }
  TSurfaceCatch = class
    Content: TRect;
    procedure Catch(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
  end;
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

procedure TSurfaceCatch.Catch(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
begin
  Content := AContent;
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

procedure TBorderWidthTest.TestAControlBarGrowsByIt;
var
  cb: TTyControlBar;
  c: TTyPanel;
  h0: Integer;
begin
  cb := TTyControlBar.Create(FForm);
  cb.Parent := FForm;
  cb.Font.PixelsPerInch := 96;
  cb.Align := alTop;
  cb.SetBounds(0, 0, 300, 40);
  c := TTyPanel.Create(FForm);
  c.SetBounds(0, 0, 80, 24);
  c.Parent := cb;
  Realign(cb);
  h0 := cb.Height;
  cb.BorderWidth := 10;
  Realign(cb);
  AssertEquals('the bar grows by the width on both edges', h0 + 20, cb.Height);
end;

procedure TBorderWidthTest.TestAPaintPanelsContentMovesIn;
var
  pp: TPaintAcc;
  catch: TSurfaceCatch;
  bmp: TBitmap;
  r0: TRect;
begin
  pp := TPaintAcc.Create(FForm);
  catch := TSurfaceCatch.Create;
  bmp := TBitmap.Create;
  try
    pp.Parent := FForm;
    pp.Font.PixelsPerInch := 96;
    pp.SetBounds(0, 0, 160, 120);
    pp.OnPaintSurface := @catch.Catch;
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(160, 120);
    pp.RenderTo(bmp.Canvas, Rect(0, 0, 160, 120), 96);
    r0 := catch.Content;
    pp.BorderWidth := 10;
    pp.RenderTo(bmp.Canvas, Rect(0, 0, 160, 120), 96);
    AssertEquals('the content moves in on the left', r0.Left + 10, catch.Content.Left);
    AssertEquals('and on the top', r0.Top + 10, catch.Content.Top);
    AssertEquals('and on the right', r0.Right - 10, catch.Content.Right);
    AssertEquals('and on the bottom', r0.Bottom - 10, catch.Content.Bottom);
  finally
    bmp.Free;
    catch.Free;
  end;
end;

procedure TBorderWidthTest.TestAnExPanelsHeaderMovesIn;

  { The leftmost and rightmost dark pixel in the header band: the chevron at one end, a
    right-aligned caption at the other. }
  procedure Ends(AWidth: Integer; out ALeft, ARight: Integer);
  var
    e: TExAcc;
    bmp: TBitmap;
    b: TBGRABitmap;
    x, y: Integer;
    px: TBGRAPixel;
  begin
    ALeft := -1;
    ARight := -1;
    e := TExAcc.Create(nil);
    bmp := TBitmap.Create;
    try
      e.Font.PixelsPerInch := 96;
      e.SetBounds(0, 0, 240, 100);
      e.HeaderHeight := 30;
      e.Caption := 'MMMM';
      e.Alignment := taRightJustify;
      e.BorderWidth := AWidth;
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(240, 100);
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, 240, 100);
      e.RenderTo(bmp.Canvas, Rect(0, 0, 240, 100), 96);
      b := TBGRABitmap.Create(bmp);
      try
        for x := 3 to 236 do
          for y := 6 to 24 do
          begin
            px := b.GetPixel(x, y);
            // the chevron is a thin antialiased stroke, so any grey counts at the left end
            if (ALeft < 0) and (x < 80) and (px.red + px.green + px.blue < 3 * 200) then
              ALeft := x;
            if (px.red < 120) and (px.green < 120) and (px.blue < 120) then
              ARight := x;
          end;
      finally
        b.Free;
      end;
    finally
      bmp.Free;
      e.Free;
    end;
  end;

var
  l0, r0, l1, r1: Integer;
begin
  Ends(0, l0, r0);
  Ends(12, l1, r1);
  AssertTrue('precondition: the header is drawn', (l0 > 0) and (r0 > l0));
  AssertEquals('the chevron moves in by the width', l0 + 12, l1);
  AssertEquals('and so does the caption', r0 - 12, r1);
end;

procedure TBorderWidthTest.TestTheSegmentedTrackMovesIn;
var
  sg: TTySegmented;
  l0, w0, h0, w, h: Integer;
begin
  sg := TTySegmented.Create(FForm);
  sg.Parent := FForm;
  sg.Font.PixelsPerInch := 96;
  sg.Items.Add('One');
  sg.Items.Add('Two');
  sg.SetBounds(0, 0, 200, 40);
  l0 := sg.TySegmentRect(0).Left;
  w0 := 0;
  h0 := 0;
  sg.GetPreferredSize(w0, h0, True, False);
  sg.BorderWidth := 10;
  AssertEquals('the segments move in by the width', l0 + 10, sg.TySegmentRect(0).Left);
  w := 0;
  h := 0;
  sg.InvalidatePreferredSize;
  sg.GetPreferredSize(w, h, True, False);
  AssertEquals('and AutoSize grows by both sides', h0 + 20, h);
end;

procedure TBorderWidthTest.TestTheStepsCellsMoveIn;
var
  st: TTySteps;
  l0: Integer;
begin
  st := TTySteps.Create(FForm);
  st.Parent := FForm;
  st.Font.PixelsPerInch := 96;
  st.Items.Add('Cart');
  st.Items.Add('Pay');
  st.Items.Add('Done');
  st.SetBounds(0, 0, 300, 60);
  l0 := st.TyStepRect(0).Left;
  st.BorderWidth := 10;
  AssertEquals('the cells move in by the width', l0 + 10, st.TyStepRect(0).Left);
  st.BorderWidth := 0;
  st.StyleOverride := 'padding: 20px';
  AssertEquals('and by a padding StyleOverride sets', 20, st.TyStepRect(0).Left);
end;

procedure TBorderWidthTest.TestTheSelectedSegmentsCaptionMovesIn;

  { How wide the caption of the first, selected, segment is drawn: its rect is cut to fit, so
    an inset narrows it. }
  function Span(AWidth: Integer): Integer;
  var
    g: TGroupAcc;
    bmp: TBitmap;
    b: TBGRABitmap;
    x, y, lo, hi: Integer;
    ground, px: TBGRAPixel;
  begin
    lo := -1;
    hi := -1;
    g := TGroupAcc.Create(nil);
    bmp := TBitmap.Create;
    try
      g.Font.PixelsPerInch := 96;
      g.SetBounds(0, 0, 200, 32);
      g.Items.Add('Wwwwwwwwwwwwwwwwwwww');
      g.Items.Add('Wwwwwwwwwwwwwwwwwwww');
      g.ItemIndex := 0;
      g.BorderWidth := AWidth;
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(200, 32);
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, 200, 32);
      g.RenderTo(bmp.Canvas, Rect(0, 0, 200, 32), 96);
      b := TBGRABitmap.Create(bmp);
      try
        ground := b.GetPixel(3, 16);
        for x := 3 to 96 do
          for y := 10 to 22 do
          begin
            px := b.GetPixel(x, y);
            if (Abs(px.red - ground.red) > 60) or (Abs(px.green - ground.green) > 60)
               or (Abs(px.blue - ground.blue) > 60) then
            begin
              if lo < 0 then lo := x;
              hi := x;
            end;
          end;
      finally
        b.Free;
      end;
    finally
      bmp.Free;
      g.Free;
    end;
    if lo < 0 then Result := 0 else Result := hi - lo;
  end;

var
  s0, s1: Integer;
begin
  s0 := Span(0);
  s1 := Span(30);
  AssertTrue(Format('precondition: the caption is drawn (%d)', [s0]), s0 > 40);
  AssertTrue(Format('the selected caption is inset too (%d -> %d)', [s0, s1]), s1 < s0 - 40);
end;

initialization
  RegisterTest(TBorderWidthTest);
end.
