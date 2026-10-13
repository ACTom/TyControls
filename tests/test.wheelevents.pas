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
  Classes, SysUtils, Types, Forms, Controls, Graphics, LCLIntf, LCLType, LMessages, fpcunit,
  testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Columns, tyControls.Grid, tyControls.ImageView, tyControls.Cascader,
  test.designregistry;

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

  {$IFDEF MSWINDOWS}
  { Where the wheel points, on a real window. LCL hands DoMouseWheel the pointer in CLIENT
    coordinates: TMouseWheelEvent.MousePos is documented so, and the win32 widgetset converts
    WM_MOUSEWHEEL's screen point before it dispatches. The image view and the cascader panel
    converted it a second time with ScreenToClient, so on any window not sitting at the
    screen's origin the image zoomed about a point far off the control, and the cascader found
    no column under the pointer and did not scroll at all.

    Calling DoMouseWheel directly would only test whichever space the test assumed, so these
    send WM_MOUSEWHEEL through the widgetset to a shown form -- off screen, as TTyClickFocusTest
    does it, which also makes "not at the origin" certain. }
  TWheelPositionTest = class(TTestCase)
  private
    FForm: TForm;
    FSeen: TPoint;
    FSeenCount: Integer;
    procedure Seen(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    { One notch on AControl as the system delivers it: WM_MOUSEWHEEL carrying the SCREEN point
      of AControl's client point APt. }
    procedure SendNotch(AControl: TWinControl; const APt: TPoint; ADelta: Integer);
    function NewView(ALeft: Integer): TTyImageView;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheImageViewZoomsAboutThePointer;
    procedure TestTheCascaderScrollsTheColumnUnderThePointer;
  end;
  {$ENDIF}

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

{$IFDEF MSWINDOWS}

{ ===== TWheelPositionTest ===== }

var
  WheelWidgetSetReady: Boolean = False;

type
  TPosImageView = class(TTyImageView);   // RenderTo is protected

procedure TWheelPositionTest.SetUp;
begin
  { The console runner registers no window classes until the widgetset is up. }
  if not WheelWidgetSetReady then
  begin
    Forms.Application.Initialize;
    WheelWidgetSetReady := True;
  end;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 1300, 500);
  FForm.Visible := True;
  FForm.HandleNeeded;
end;

procedure TWheelPositionTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TWheelPositionTest.Seen(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  FSeen := MousePos;
  Inc(FSeenCount);
end;

procedure TWheelPositionTest.SendNotch(AControl: TWinControl; const APt: TPoint;
  ADelta: Integer);
var
  sp: TPoint;
begin
  sp := AControl.ClientToScreen(APt);
  FSeen := Point(MaxInt, MaxInt);
  FSeenCount := 0;
  { wParam: the delta in the high word; lParam: the screen point, 16 bits a coordinate. }
  SendMessage(AControl.Handle, LM_MOUSEWHEEL, WPARAM(Word(SmallInt(ADelta))) shl 16,
    LPARAM((sp.Y shl 16) or (sp.X and $FFFF)));
end;

function TWheelPositionTest.NewView(ALeft: Integer): TTyImageView;
var
  bmp: TBGRABitmap;
begin
  Result := TTyImageView.Create(FForm);
  Result.Parent := FForm;
  Result.AnimationDuration := 0;        // settle at once, handle or not
  Result.SetBounds(ALeft, 23, 400, 300);
  { Four quadrants of four colours: where the image's centre lands after a zoom shows which
    point the zoom was about. }
  bmp := TBGRABitmap.Create(800, 600, BGRA(220, 40, 40));
  try
    bmp.FillRect(400, 0, 800, 300, BGRA(40, 180, 40), dmSet);
    bmp.FillRect(0, 300, 400, 600, BGRA(40, 40, 220), dmSet);
    bmp.FillRect(400, 300, 800, 600, BGRA(230, 210, 40), dmSet);
    Result.AssignBitmap(bmp);
  finally
    bmp.Free;
  end;
  Result.HandleNeeded;
end;

function RenderOf(AView: TTyImageView): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AView.Width, AView.Height);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, AView.Width, AView.Height);
    TPosImageView(AView).RenderTo(bmp.Canvas, Rect(0, 0, AView.Width, AView.Height), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function PixelsApart(A, B: TBGRABitmap): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y) <> B.GetPixel(x, y) then Inc(Result);
end;

procedure TWheelPositionTest.TestTheImageViewZoomsAboutThePointer;
var
  v, twin, other: TTyImageView;
  got, want, elsewhere: TBGRABitmap;
  at: TPoint;
begin
  { Off the centre on purpose: a zoom about the centre leaves the centre where it was, and the
    centre is where a confused anchor would most likely land. }
  at := Point(70, 50);
  v := NewView(37);
  twin := NewView(450);
  other := NewView(870);
  v.OnMouseWheel := @Seen;
  SendNotch(v, at, 120);
  AssertEquals('setup: the notch reached the view', 1, FSeenCount);
  AssertEquals('setup: LCL hands the wheel over in client coordinates (x)', at.X, FSeen.X);
  AssertEquals('setup: LCL hands the wheel over in client coordinates (y)', at.Y, FSeen.Y);
  { What a zoom about the pointer looks like, and what one about the centre does. }
  twin.ZoomAt(1.15, at.X, at.Y);
  other.ZoomAt(1.15, other.Width div 2, other.Height div 2);
  got := RenderOf(v);
  want := RenderOf(twin);
  elsewhere := RenderOf(other);
  try
    AssertTrue('setup: the image tells one anchor from another',
      PixelsApart(want, elsewhere) > 1000);
    AssertEquals('the wheel zoomed as much as ZoomAt', twin.Zoom, v.Zoom, 1e-9);
    AssertEquals('the wheel zoomed about the pointer: the view looks as ZoomAt at the pointer'
      + ' makes it look', 0, PixelsApart(got, want));
  finally
    got.Free;
    want.Free;
    elsewhere.Free;
  end;
end;

procedure TWheelPositionTest.TestTheCascaderScrollsTheColumnUnderThePointer;
var
  nodes: TTyCascaderNodes;
  p: TTyCascaderPanel;
  path: TTyCascaderPath;
  i: Integer;
  r: TRect;
  at: TPoint;
begin
  nodes := TTyCascaderNodes.Create(nil);
  p := nil;
  try
    for i := 0 to 29 do nodes.AddNode('n' + IntToStr(i));
    for i := 0 to 29 do nodes[0].Children.AddNode('c' + IntToStr(i));
    p := TTyCascaderPanel.Create(nil);
    p.Parent := FForm;
    p.SetBounds(37, 23, 500, 160);
    p.Root := nodes;
    SetLength(path, 1);
    path[0] := 0;
    p.Path := path;                      // two columns, both taller than the panel
    p.HandleNeeded;
    TWheelAccess(p).OnMouseWheel := @Seen;   // the panel publishes no events
    AssertEquals('setup: two columns', 2, p.ColumnCount);
    r := p.TyPanelColumnRect(1);
    AssertTrue('setup: the second column is on the panel', r.Right > r.Left);
    at := Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2);
    SendNotch(p, at, -120);
    AssertEquals('setup: the notch reached the panel', 1, FSeenCount);
    AssertEquals('setup: LCL hands the wheel over in client coordinates (x)', at.X, FSeen.X);
    AssertEquals('setup: LCL hands the wheel over in client coordinates (y)', at.Y, FSeen.Y);
    AssertEquals('the column under the pointer scrolled down a row', 1, p.TyPanelFirstRow(1));
    AssertEquals('the other column stayed', 0, p.TyPanelFirstRow(0));
  finally
    p.Free;
    nodes.Free;
  end;
end;

{$ENDIF}

initialization
  RegisterTest(TWheelEventTest);
  {$IFDEF MSWINDOWS}
  RegisterTest(TWheelPositionTest);
  {$ENDIF}
end.
