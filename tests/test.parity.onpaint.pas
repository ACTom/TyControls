unit test.parity.onpaint;
{$mode objfpc}{$H+}
{ Guards OnPaint -- the post-draw hook an application hangs one badge, one overlay or one
  debug rectangle on without subclassing the control.

  This file replaces half of test.parity's LyingPropertiesStayUnpublished, which pinned
  OnPaint UNPUBLISHED for as long as nothing behind it fired. Publishing it is only correct
  while these tests hold, and the load-bearing one is the ORDERING: the house paint pattern
  builds into a BGRA layer and composites it onto the canvas in TTyPainter.EndPaint, so
  anything drawn to the canvas BEFORE that composite is overwritten. A hook that fires from
  inside a control's Paint would therefore be a hook whose output silently disappears --
  which is the exact defect the parity pass has been removing. So the assertions below are
  pixel assertions, not "was it called": the handler paints a colour the theme cannot
  produce over the whole client, and the test reads it back off the destination bitmap.

  Both paths are driven through the REAL LCL entry point, not through RenderTo:
    windowed -> PaintWindow(DC), the single funnel TWinControl.PaintHandler uses;
    graphic  -> an LM_PAINT message, which is what TGraphicControl.WMPaint answers.
  Driving RenderTo instead would prove nothing -- RenderTo is the composite, and the hook
  deliberately sits outside it. }
interface
uses
  Classes, SysUtils, Types, TypInfo, Graphics, Controls, Forms, LCLType, LMessages,
  BGRABitmap, BGRABitmapTypes, fpcunit, testregistry,
  tyControls.Base, tyControls.Panel, tyControls.ProgressBar;

type
  { PaintWindow is TWinControl-protected, so a descendant declared here can drive the real
    windowed paint funnel without a window handle (headless has none). }
  TPanelPaint = class(TTyPanel)
  public
    procedure DrivePaint(ADC: HDC);
  end;

  { TGraphicControl declares OnPaint PROTECTED, so the graphic half is reached through a
    descendant -- which is also why this file compiles, and fails, against a library that
    has not published the property yet. }
  TBarPaint = class(TTyProgressBar)
  public
    property OnPaint;
  end;

  TOnPaintParityTest = class(TTestCase)
  private
    FFires: Integer;
    { The CLASS of whatever arrived as Sender, not the instance: the control is freed with
      its form before the assertion runs, and `FSender is TTyPanel` on a freed pointer is an
      access violation waiting for a slow day. A TClass is a static VMT pointer and stays
      readable. }
    FSenderClass: TClass;
    procedure PaintMarker(Sender: TObject);
    procedure PaintNothing(Sender: TObject);
    { One paint into a FRESH target each time. Fresh because reading a TBitmap back through
      BGRA detaches its canvas DC: a second render into the same target would land somewhere
      other than the pixels the test then reads, and the test would fail for a reason that
      has nothing to do with the control. Caller frees the result. }
    function PaintPanel(AHandler: TNotifyEvent; ADesigning: Boolean): TBGRABitmap;
    function PaintBar(AHandler: TNotifyEvent): TBGRABitmap;
  published
    procedure OnPaintIsPublishedOnBothBaseClasses;
    procedure WindowedOnPaintDrawsOverTheComposite;
    procedure GraphicOnPaintDrawsOverTheComposite;
    procedure ANoOpHandlerChangesNoPixel;
    procedure TheHandlerRunsOncePerPaint;
    procedure TheDesignerFiresItToo;
  end;

implementation

const
  { A colour no theme in the pack can produce, so a pixel carrying it can only have come
    from the handler. }
  MarkR = 255; MarkG = 0; MarkB = 255;
  { And a different one under everything, so "the control painted at all" is checkable. }
  UnderR = 0; UnderG = 255; UnderB = 0;
  CW = 120; CH = 60;

procedure TPanelPaint.DrivePaint(ADC: HDC);
begin
  PaintWindow(ADC);
end;

{ A destination bitmap pre-filled with the UNDER colour: any pixel still carrying it was
  written by nobody. }
function NewTarget: TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(CW, CH);
  Result.Canvas.Brush.Style := bsSolid;
  Result.Canvas.Brush.Color := RGBToColor(UnderR, UnderG, UnderB);
  Result.Canvas.FillRect(0, 0, CW, CH);
end;

function Centre(ABmp: TBGRABitmap): TBGRAPixel;
begin
  Result := ABmp.GetPixel(CW div 2, CH div 2);
end;

function IsMark(const APx: TBGRAPixel): Boolean;
begin
  Result := (APx.red = MarkR) and (APx.green = MarkG) and (APx.blue = MarkB);
end;

function IsUnder(const APx: TBGRAPixel): Boolean;
begin
  Result := (APx.red = UnderR) and (APx.green = UnderG) and (APx.blue = UnderB);
end;

{ The handler under test: paints the mark colour across the WHOLE client through the
  control's own Canvas -- which is the contract ("fired with the control's own Canvas"). }
procedure TOnPaintParityTest.PaintMarker(Sender: TObject);
var
  c: TCanvas;
begin
  Inc(FFires);
  FSenderClass := Sender.ClassType;
  if Sender is TCustomControl then
    c := TCustomControl(Sender).Canvas
  else
    c := TGraphicControl(Sender).Canvas;
  c.Brush.Style := bsSolid;
  c.Brush.Color := RGBToColor(MarkR, MarkG, MarkB);
  c.FillRect(TControl(Sender).ClientRect);
end;

procedure TOnPaintParityTest.PaintNothing(Sender: TObject);
begin
  Inc(FFires);
end;

function TOnPaintParityTest.PaintPanel(AHandler: TNotifyEvent; ADesigning: Boolean): TBGRABitmap;
var
  form: TForm;
  p: TPanelPaint;
  bmp: TBitmap;
begin
  form := TForm.CreateNew(nil);
  bmp := NewTarget;
  try
    p := TPanelPaint.Create(form);
    p.Parent := form;
    p.SetBounds(0, 0, CW, CH);
    if ADesigning then p.SetDesigning(True);
    p.OnPaint := AHandler;
    p.DrivePaint(bmp.Canvas.Handle);   // the real windowed funnel, no handle required
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
    form.Free;
  end;
end;

function TOnPaintParityTest.PaintBar(AHandler: TNotifyEvent): TBGRABitmap;
var
  form: TForm;
  b: TBarPaint;
  bmp: TBitmap;
begin
  form := TForm.CreateNew(nil);
  bmp := NewTarget;
  try
    b := TBarPaint.Create(form);
    b.Parent := form;
    b.SetBounds(0, 0, CW, CH);
    b.OnPaint := AHandler;
    // LM_PAINT with the DC in the WParam slot -- exactly what TGraphicControl answers.
    b.Perform(LM_PAINT, WParam(bmp.Canvas.Handle), 0);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
    form.Free;
  end;
end;

{ The property itself. This is the assertion test.parity used to make in reverse. }
procedure TOnPaintParityTest.OnPaintIsPublishedOnBothBaseClasses;
begin
  AssertTrue('windowed base publishes OnPaint',
    GetPropInfo(TTyPanel, 'OnPaint') <> nil);
  AssertTrue('graphic base publishes OnPaint',
    GetPropInfo(TTyProgressBar, 'OnPaint') <> nil);
end;

{ The ordering guard for the windowed base. The panel's own paint is opaque (DrawFrame
  fills the parent background before anything else), so a hook that fired anywhere inside
  Paint would have its output composited away -- the mark could not survive. }
procedure TOnPaintParityTest.WindowedOnPaintDrawsOverTheComposite;
var
  bare, marked: TBGRABitmap;
begin
  { Without a handler first: establishes that the control really does cover the pixel, so
    the second half is a statement about ORDER and not about an empty control. }
  bare := PaintPanel(nil, False);
  FFires := 0;
  FSenderClass := nil;
  marked := PaintPanel(@PaintMarker, False);
  try
    AssertFalse('the panel must paint over the target for this test to mean anything',
      IsUnder(Centre(bare)));
    AssertFalse('nothing may produce the mark colour but the handler', IsMark(Centre(bare)));
    AssertEquals('the handler ran', 1, FFires);
    AssertTrue('OnPaint must draw ON TOP of the finished composite, not under it',
      IsMark(Centre(marked)));
    AssertTrue('Sender is the control that painted', FSenderClass = TPanelPaint);
  finally
    bare.Free;
    marked.Free;
  end;
end;

{ The same guard for the graphic base, driven through LM_PAINT -- the message
  TGraphicControl answers by setting its canvas handle and calling Paint. }
procedure TOnPaintParityTest.GraphicOnPaintDrawsOverTheComposite;
var
  bare, marked: TBGRABitmap;
begin
  bare := PaintBar(nil);
  FFires := 0;
  FSenderClass := nil;
  marked := PaintBar(@PaintMarker);
  try
    AssertFalse('the bar must paint over the target for this test to mean anything',
      IsUnder(Centre(bare)));
    AssertFalse('nothing may produce the mark colour but the handler', IsMark(Centre(bare)));
    AssertEquals('the handler ran', 1, FFires);
    AssertTrue('OnPaint must draw ON TOP of the finished composite, not under it',
      IsMark(Centre(marked)));
    AssertTrue('Sender is the control that painted', FSenderClass = TBarPaint);
  finally
    bare.Free;
    marked.Free;
  end;
end;

{ The cost guard. A handler that draws nothing must leave the frame exactly as the control
  drew it -- so the hook may not clear, re-blit or otherwise touch the canvas on its own
  account. Compared over every pixel, because a hook that dirtied only an edge would still
  be a hook that costs something. }
procedure TOnPaintParityTest.ANoOpHandlerChangesNoPixel;
var
  without, withNoOp: TBGRABitmap;
  x, y, diff: Integer;
begin
  FFires := 0;
  without := PaintPanel(nil, False);
  withNoOp := PaintPanel(@PaintNothing, False);
  try
    AssertEquals('the no-op handler did run', 1, FFires);
    diff := 0;
    for y := 0 to CH - 1 do
      for x := 0 to CW - 1 do
        if without.GetPixel(x, y) <> withNoOp.GetPixel(x, y) then Inc(diff);
    AssertEquals('a handler that draws nothing must change nothing', 0, diff);
  finally
    without.Free;
    withNoOp.Free;
  end;
end;

{ Once per paint on each base -- not twice (a hook wired at two levels), not zero. }
procedure TOnPaintParityTest.TheHandlerRunsOncePerPaint;
var
  form: TForm;
  p: TPanelPaint;
  b: TBarPaint;
  bmp: TBitmap;
begin
  form := TForm.CreateNew(nil);
  bmp := NewTarget;
  try
    p := TPanelPaint.Create(form);
    p.Parent := form;
    p.SetBounds(0, 0, CW, CH);
    p.OnPaint := @PaintNothing;
    FFires := 0;
    p.DrivePaint(bmp.Canvas.Handle);
    AssertEquals('windowed: exactly one fire per paint', 1, FFires);
    p.DrivePaint(bmp.Canvas.Handle);
    AssertEquals('windowed: and one per paint after that', 2, FFires);

    b := TBarPaint.Create(form);
    b.Parent := form;
    b.SetBounds(0, 0, CW, CH);
    b.OnPaint := @PaintNothing;
    FFires := 0;
    b.Perform(LM_PAINT, WParam(bmp.Canvas.Handle), 0);
    AssertEquals('graphic: exactly one fire per paint', 1, FFires);
  finally
    bmp.Free;
    form.Free;
  end;
end;

{ The LCL fires OnPaint in the designer and so do we: an overlay that vanishes while the
  form is being built is a layout you cannot see while you build it. (In the IDE the
  streamed handler is nil anyway, so this costs the designer nothing.) }
procedure TOnPaintParityTest.TheDesignerFiresItToo;
var
  designed: TBGRABitmap;
begin
  FFires := 0;
  designed := PaintPanel(@PaintMarker, True);
  try
    AssertEquals('the designer fires OnPaint too', 1, FFires);
    AssertTrue('and it still lands on top of the composite', IsMark(Centre(designed)));
  finally
    designed.Free;
  end;
end;

initialization
  RegisterTest(TOnPaintParityTest);
end.
