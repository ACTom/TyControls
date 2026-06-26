unit test.splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, ExtCtrls, fpcunit, testregistry,
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

initialization
  RegisterTest(TSplitterGeomTest);
  RegisterTest(TSplitterControlTest);
end.
