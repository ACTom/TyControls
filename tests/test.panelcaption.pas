unit test.panelcaption;
{ #116: TTyExPanel's header and TTyPaintPanel draw their caption the way TTyPanel does, so
  Alignment, VerticalAlignment, WordWrap and ShowAccelChar act on them; a new scroll box or
  grid panel no longer takes its Name as a caption, as LCL's TScrollBox has none. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Graphics, Forms, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Panel, tyControls.ExPanel,
  tyControls.PaintPanel, tyControls.ScrollBox, tyControls.GridPanel;

type
  TPanelCaptionTest = class(TTestCase)
  published
    procedure TestAnExPanelsHeaderStartsAtTheLeft;
    procedure TestAnExPanelsHeaderFollowsAlignment;
    procedure TestAPaintPanelsCaptionWraps;
    procedure TestAPaintPanelsCaptionTakesItsAccessKey;
    procedure TestANewScrollBoxOrGridPanelHasNoCaption;
  end;

implementation

type
  TExAcc = class(TTyExPanel);
  TPaintAcc = class(TTyPaintPanel);

type
  TInk = record
    Left, Right, Top, Bottom: Integer;
  end;

function InkOf(AControl: TControl; W, H, ATop, ABottom: Integer): TInk;
var
  bmp: TBitmap;
  b: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
begin
  Result.Left := MaxInt; Result.Right := -1; Result.Top := MaxInt; Result.Bottom := -1;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, W, H);
    if AControl is TTyExPanel then TExAcc(AControl).RenderTo(bmp.Canvas, Rect(0, 0, W, H), 96)
    else TPaintAcc(AControl).RenderTo(bmp.Canvas, Rect(0, 0, W, H), 96);
    b := TBGRABitmap.Create(bmp);
    try
      for y := ATop to ABottom - 1 do
        for x := 30 to W - 4 do   // past an expander's chevron
        begin
          px := b.GetPixel(x, y);
          if (px.red < 130) and (px.green < 130) and (px.blue < 130) then
          begin
            if x < Result.Left then Result.Left := x;
            if x > Result.Right then Result.Right := x;
            if y < Result.Top then Result.Top := y;
            if y > Result.Bottom then Result.Bottom := y;
          end;
        end;
    finally
      b.Free;
    end;
  finally
    bmp.Free;
  end;
end;

function NewEx: TTyExPanel;
begin
  Result := TTyExPanel.Create(nil);
  Result.SetBounds(0, 0, 300, 120);
  Result.Caption := 'MMMM';
end;

procedure TPanelCaptionTest.TestAnExPanelsHeaderStartsAtTheLeft;
var
  e: TTyExPanel;
begin
  e := NewEx;
  try
    AssertTrue('Alignment starts at the left, where the header always drew it',
      e.Alignment = taLeftJustify);
    AssertTrue('and it is drawn there', InkOf(e, 300, 120, 0, 28).Left < 100);
  finally
    e.Free;
  end;
end;

procedure TPanelCaptionTest.TestAnExPanelsHeaderFollowsAlignment;
var
  e: TTyExPanel;
begin
  e := NewEx;
  try
    e.Alignment := taRightJustify;
    AssertTrue('a right-aligned header caption sits at the right',
      InkOf(e, 300, 120, 0, 28).Left > 200);
  finally
    e.Free;
  end;
end;

procedure TPanelCaptionTest.TestAPaintPanelsCaptionWraps;
var
  p: TTyPaintPanel;
  one, wrapped: TInk;
begin
  p := TTyPaintPanel.Create(nil);
  try
    p.SetBounds(0, 0, 160, 160);
    p.Caption := 'MMMM WWWW MMMM WWWW MMMM WWWW MMMM WWWW MMMM';
    one := InkOf(p, 160, 160, 0, 160);
    p.WordWrap := True;
    wrapped := InkOf(p, 160, 160, 0, 160);
    AssertTrue(Format('wrapped onto more lines (%d -> %d px tall)',
      [one.Bottom - one.Top, wrapped.Bottom - wrapped.Top]),
      (wrapped.Bottom - wrapped.Top) > 2 * (one.Bottom - one.Top));
  finally
    p.Free;
  end;
end;

procedure TPanelCaptionTest.TestAPaintPanelsCaptionTakesItsAccessKey;
var
  p: TTyPaintPanel;
  plain, keyed: TInk;
begin
  p := TTyPaintPanel.Create(nil);
  try
    p.SetBounds(0, 0, 240, 60);
    p.Alignment := taLeftJustify;
    p.Caption := '&MMMM';
    plain := InkOf(p, 240, 60, 0, 60);
    p.ShowAccelChar := True;
    keyed := InkOf(p, 240, 60, 0, 60);
    AssertTrue(Format('the ampersand is taken as the access key, not drawn (%d -> %d px wide)',
      [plain.Right - plain.Left, keyed.Right - keyed.Left]),
      (keyed.Right - keyed.Left) < (plain.Right - plain.Left));
  finally
    p.Free;
  end;
end;

procedure TPanelCaptionTest.TestANewScrollBoxOrGridPanelHasNoCaption;
var
  f: TForm;
  sb: TTyScrollBox;
  gp: TTyGridPanel;
begin
  f := TForm.CreateNew(nil);
  try
    sb := TTyScrollBox.Create(f);
    sb.Name := 'Box1';
    gp := TTyGridPanel.Create(f);
    gp.Name := 'Grid1';
    AssertEquals('a scroll box takes no caption from its name', '', sb.Caption);
    AssertEquals('nor does a grid panel', '', gp.Caption);
  finally
    f.Free;
  end;
end;

initialization
  RegisterTest(TPanelCaptionTest);
end.
