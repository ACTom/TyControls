unit test.splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Base,
  tyControls.Splitter;
type
  TSplitterGeomTest = class(TTestCase)
  published
    procedure TestNewSizeGrowShrink;
    procedure TestNewSizeClamps;
  end;

  TTySplitterProbe = class(TTySplitter)
  public
    procedure FakeDrag(AStartX, AEndX, AYMid: Integer);
  end;

  TSplitterControlTest = class(TTestCase)
  published
    procedure TestDragResizesLeftNeighbor;
  end;

  { Access subclass that re-exposes protected RenderTo as public }
  TTySplitterPixAccess = class(TTySplitter)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TSplitterPixelTest = class(TTestCase)
  published
    procedure TestGripDotIsBlue;
  end;

implementation

procedure TSplitterGeomTest.TestNewSizeGrowShrink;
begin
  // alLeft/alTop: sibling precedes the splitter -> +delta grows it
  AssertEquals('alLeft +20', 120, TySplitterNewSize(alLeft, 100, 20, 30, 1000));
  AssertEquals('alTop  +20', 120, TySplitterNewSize(alTop,  100, 20, 30, 1000));
  // alRight/alBottom: sibling follows the splitter -> +delta shrinks it
  AssertEquals('alRight +20', 80, TySplitterNewSize(alRight,  100, 20, 30, 1000));
  AssertEquals('alBottom +20', 80, TySplitterNewSize(alBottom, 100, 20, 30, 1000));
end;

procedure TSplitterGeomTest.TestNewSizeClamps;
begin
  AssertEquals('floor at MinSize', 30, TySplitterNewSize(alLeft, 100, -500, 30, 1000));
  AssertEquals('ceil at MaxSize',  200, TySplitterNewSize(alLeft, 100, 500, 30, 200));
  // MaxSize < MinSize means "no max" (unknown) -> only the floor applies
  AssertEquals('no max when max<min', 600, TySplitterNewSize(alLeft, 100, 500, 30, -1));
end;

{ TTySplitterProbe }

procedure TTySplitterProbe.FakeDrag(AStartX, AEndX, AYMid: Integer);
begin
  MouseDown(mbLeft, [], AStartX, AYMid);
  MouseMove([ssLeft], AEndX, AYMid);
  MouseUp(mbLeft, [], AEndX, AYMid);
end;

{ TSplitterControlTest }

procedure TSplitterControlTest.TestDragResizesLeftNeighbor;
var
  Form: TForm;
  Pan: TPanel;
  Sp: TTySplitterProbe;
begin
  // Use Align=alNone + explicit bounds for both controls so LCL's auto-alignment
  // engine never repositions them during the test, making FindResizeTarget
  // deterministic: the panel always occupies [0..100) and the splitter [100..105).
  // The splitter's Align is set to alLeft last so that Vertical() returns True
  // (alLeft in [alLeft, alRight]) and the correct axis (Width) is used.
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 200);

    Pan := TPanel.Create(Form);
    Pan.Parent := Form;
    Pan.Align := alNone;
    Pan.SetBounds(0, 0, 100, 200);

    Sp := TTySplitterProbe.Create(Form);
    Sp.Parent := Form;
    Sp.Align := alNone;        // prevent auto-layout while we set bounds
    Sp.SetBounds(100, 0, 5, 200);
    Sp.Align := alLeft;        // now set; Vertical() -> True; FindResizeTarget uses Self.Left=100
    Sp.MinSize := 40;

    // Positive drag: move right by 60 -> grows the left neighbour
    Sp.FakeDrag(0, 60, 100);
    AssertTrue('left panel grew past its start width', Pan.Width > 100);

    // After the first drag Pan.Width changed; since the splitter is alLeft but the
    // panel is alNone, LCL may have auto-repositioned the splitter to Left=0.
    // Restore it to just right of the panel so FindResizeTarget picks it up again.
    Sp.Left := Pan.Width;

    // Large negative drag: floor the neighbour at MinSize (deterministic)
    Sp.FakeDrag(0, -1000, 100);
    AssertEquals('left panel floored at MinSize', 40, Pan.Width);
  finally
    Form.Free;
  end;
end;

{ TTySplitterPixAccess }

procedure TTySplitterPixAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ TSplitterPixelTest }

procedure TSplitterPixelTest.TestGripDotIsBlue;
{ Theme: color: #3B82F6 (blue) on the grip dots.
  Control: 10x100 vertical splitter (alLeft). At 96 ppi, Scale(2)=2px dot, Scale(3)=3px gap.
  Pre-fill the bitmap white so blue dots stand out clearly.
  Centre column = x=5 (10 div 2). Centre row = y=50 (100 div 2).
  The 3 grip dots are at y ~ 44..46, 47..50, 50..53 centred in the column.
  Scan a 4px-wide band (x=4..7) around the centre column across all rows
  for any pixel with blue > red (blue channel clearly dominant).
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  Sp: TTySplitterPixAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
  FoundBlue: Boolean;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TySplitter { color: #3B82F6; }');

    Sp := TTySplitterPixAccess.Create(Form);
    Sp.Parent := Form;
    Sp.Controller := Ctl;
    Sp.Align := alLeft;
    Sp.SetBounds(0, 0, 10, 100);
    Sp.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(10, 100);
    // Pre-fill white so blue dots stand out clearly
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 10, 100);
    Sp.RenderTo(Bmp.Canvas, Rect(0, 0, 10, 100), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Scan a 4px-wide band around the centre column for any blue-dominant pixel
      // #3B82F6 = R=59, G=130, B=246 — blue is distinctly > red
      FoundBlue := False;
      for x := 4 to 7 do
      begin
        for y := 0 to 99 do
        begin
          px := Reread.GetPixel(x, y);
          if px.blue > px.red + 50 then
          begin
            FoundBlue := True;
            Break;
          end;
        end;
        if FoundBlue then Break;
      end;
      AssertTrue(
        'expected a blue-dominant grip-dot pixel in the centre band (x=4..7, y=0..99)',
        FoundBlue);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TSplitterGeomTest);
  RegisterTest(TSplitterControlTest);
  RegisterTest(TSplitterPixelTest);
end.
