unit test.wheelevents;
{$mode objfpc}{$H+}

{ #62. OnMouseWheel, OnMouseWheelUp and OnMouseWheelDown are fired by TControl.DoMouseWheel, so a
  control that overrides DoMouseWheel and never calls inherited never fires them. The grid
  scrolled and the image view zoomed without asking anyone: a handler that wanted the wheel for
  itself (Ctrl+wheel to zoom a grid, say) never ran.

  The contract, as LCL's TControl.DoMouseWheel and TCustomGrid have it: OnMouseWheel first; if
  it does not set Handled, OnMouseWheelUp or OnMouseWheelDown; each fires once a notch, and a
  handler that sets Handled has the last word -- nothing after it in that chain fires, and the
  control does nothing of its own.

  The sweep asks every registered control the event half of that, so a control added later that
  forgets inherited turns it red. "Does nothing of its own" needs to know what the control would
  have done, so the two that got it wrong have their own tests. }

interface

uses
  Classes, SysUtils, Types, Forms, Controls, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Columns, tyControls.Grid, tyControls.ImageView, test.designregistry;

type
  TWheelEventTest = class(TTestCase)
  private
    FForm: TForm;
    FWheel, FUp, FDown: Integer;
    FHandleIn: Integer;   // 0 = nobody sets Handled, 1 = OnMouseWheel does, 2 = OnMouseWheelUp/Down do
    procedure Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure WheelUp(Sender: TObject; Shift: TShiftState; MousePos: TPoint;
      var Handled: Boolean);
    procedure WheelDown(Sender: TObject; Shift: TShiftState; MousePos: TPoint;
      var Handled: Boolean);
    { One notch on AControl with its three wheel events hooked; AHandleIn as FHandleIn. Returns
      what DoMouseWheel answered. }
    function Notch(AControl: TControl; ADelta, AHandleIn: Integer): Boolean;
    function NewGrid: TTyStringGrid;
    function NewImageView: TTyImageView;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryControlFiresTheWheelEventsOncePerNotch;
    procedure TestAHandledWheelDoesNotScrollTheGrid;
    procedure TestAnUnhandledWheelStillScrollsTheGrid;
    procedure TestAHandledWheelDoesNotZoomTheImageView;
    procedure TestAnUnhandledWheelStillZoomsTheImageView;
  end;

implementation

type
  { DoMouseWheel and the three wheel events are protected in TControl. The call is virtual, so it
    runs the concrete control's override. }
  TWheelAccess = class(TControl);

procedure TWheelEventTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 640, 480);
end;

procedure TWheelEventTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TWheelEventTest.Wheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  Inc(FWheel);
  if FHandleIn = 1 then Handled := True;
end;

procedure TWheelEventTest.WheelUp(Sender: TObject; Shift: TShiftState; MousePos: TPoint;
  var Handled: Boolean);
begin
  Inc(FUp);
  if FHandleIn = 2 then Handled := True;
end;

procedure TWheelEventTest.WheelDown(Sender: TObject; Shift: TShiftState; MousePos: TPoint;
  var Handled: Boolean);
begin
  Inc(FDown);
  if FHandleIn = 2 then Handled := True;
end;

function TWheelEventTest.Notch(AControl: TControl; ADelta, AHandleIn: Integer): Boolean;
begin
  TWheelAccess(AControl).OnMouseWheel := @Wheel;
  TWheelAccess(AControl).OnMouseWheelUp := @WheelUp;
  TWheelAccess(AControl).OnMouseWheelDown := @WheelDown;
  FWheel := 0;
  FUp := 0;
  FDown := 0;
  FHandleIn := AHandleIn;
  { MousePos is in client coordinates (LCL's TMouseWheelEvent). }
  Result := TWheelAccess(AControl).DoMouseWheel([], ADelta, Point(20, 20));
end;

function TWheelEventTest.NewGrid: TTyStringGrid;
var
  i: Integer;
begin
  Result := TTyStringGrid.Create(FForm);
  Result.Parent := FForm;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 240);
  for i := 0 to 2 do
    (Result.Header.Columns.Add as TTyColumn).Width := 100;
  Result.RowCount := 200;
end;

function TWheelEventTest.NewImageView: TTyImageView;
var
  bmp: TBGRABitmap;
begin
  Result := TTyImageView.Create(FForm);
  Result.Parent := FForm;
  Result.SetBounds(0, 0, 400, 300);
  bmp := TBGRABitmap.Create(200, 150, BGRA(200, 40, 40));
  try
    Result.AssignBitmap(bmp);
  finally
    bmp.Free;
  end;
end;

procedure TWheelEventTest.TestEveryControlFiresTheWheelEventsOncePerNotch;
var
  names, bad: TStringList;
  i, swept: Integer;
  cls: TPersistentClass;
  c: TControl;
  handled: Boolean;

  procedure Check(const AWhat: string; AWant, AWantUp, AWantDown: Integer);
  begin
    if (FWheel <> AWant) or (FUp <> AWantUp) or (FDown <> AWantDown) or not handled then
      bad.Add(Format('%s, %s: OnMouseWheel %d, Up %d, Down %d, answered %s'
        + ' (want %d, %d, %d, True)', [names[i], AWhat, FWheel, FUp, FDown,
        BoolToStr(handled, True), AWant, AWantUp, AWantDown]));
  end;

begin
  names := TStringList.Create;
  bad := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    AssertTrue('the design-registry parser found the palette', names.IndexOf('TTyButton') >= 0);
    swept := 0;
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      if (cls = nil) or not cls.InheritsFrom(TControl) then Continue;
      if cls.InheritsFrom(TCustomForm) then Continue;
      c := TControlClass(cls).Create(FForm);
      try
        try
          c.Parent := FForm;
          c.SetBounds(0, 0, 300, 200);
          { OnMouseWheel takes the notch: nothing after it fires. }
          handled := Notch(c, -120, 1);
          Check('OnMouseWheel handles a notch down', 1, 0, 0);
          { OnMouseWheel passes; the direction event fires once and takes it. }
          handled := Notch(c, -120, 2);
          Check('OnMouseWheelDown handles a notch down', 1, 0, 1);
          handled := Notch(c, 120, 2);
          Check('OnMouseWheelUp handles a notch up', 1, 1, 0);
          Inc(swept);
        except
          on E: Exception do
            bad.Add(names[i] + ': ' + E.ClassName + ': ' + E.Message);
        end;
      finally
        c.Free;
      end;
    end;
    AssertTrue(Format('the sweep must cover the palette, and it covered %d controls', [swept]),
      swept > 80);
    AssertEquals('controls whose wheel events do not fire once a notch, or do not stop at'
      + ' Handled:' + LineEnding + bad.Text, 0, bad.Count);
  finally
    bad.Free;
    names.Free;
  end;
end;

procedure TWheelEventTest.TestAHandledWheelDoesNotScrollTheGrid;
var
  g: TTyStringGrid;
begin
  g := NewGrid;
  AssertEquals('setup: at the top', 0, g.TopRow);
  Notch(g, -120, 1);
  AssertEquals('OnMouseWheel ran', 1, FWheel);
  AssertEquals('OnMouseWheel took the notch: the grid stays put', 0, g.TopRow);
  Notch(g, -120, 2);
  AssertEquals('OnMouseWheelDown ran', 1, FDown);
  AssertEquals('OnMouseWheelDown took the notch: the grid stays put', 0, g.TopRow);
end;

procedure TWheelEventTest.TestAnUnhandledWheelStillScrollsTheGrid;
var
  g: TTyStringGrid;
  top1: Integer;
begin
  g := NewGrid;
  AssertTrue('nobody took it: the grid answers for the notch', Notch(g, -120, 0));
  AssertEquals('the events still ran', 1, FWheel);
  AssertEquals('OnMouseWheelDown ran', 1, FDown);
  top1 := g.TopRow;
  AssertTrue('a notch down scrolls the grid down', top1 > 0);
  Notch(g, 120, 0);
  AssertEquals('OnMouseWheelUp ran', 1, FUp);
  AssertTrue('a notch up scrolls it back up', g.TopRow < top1);
end;

procedure TWheelEventTest.TestAHandledWheelDoesNotZoomTheImageView;
var
  v: TTyImageView;
  z0: Double;
begin
  v := NewImageView;
  z0 := v.Zoom;
  Notch(v, 120, 1);
  AssertEquals('OnMouseWheel ran with an image shown', 1, FWheel);
  AssertEquals('OnMouseWheel took the notch: no zoom', z0, v.Zoom, 1e-9);
  Notch(v, 120, 2);
  AssertEquals('OnMouseWheelUp ran', 1, FUp);
  AssertEquals('OnMouseWheelUp took the notch: no zoom', z0, v.Zoom, 1e-9);
end;

procedure TWheelEventTest.TestAnUnhandledWheelStillZoomsTheImageView;
var
  v: TTyImageView;
  z0: Double;
begin
  v := NewImageView;
  z0 := v.Zoom;
  AssertTrue('nobody took it: the view answers for the notch', Notch(v, 120, 0));
  AssertEquals('the events still ran', 1, FWheel);
  AssertEquals('OnMouseWheelUp ran', 1, FUp);
  AssertTrue(Format('a notch up zooms in (%.4f -> %.4f)', [z0, v.Zoom]), v.Zoom > z0);
end;

initialization
  RegisterTest(TWheelEventTest);
end.
