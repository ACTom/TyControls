unit test.capturelost;

{$mode objfpc}{$H+}

{ #147: a drag ends when the mouse capture is taken away in the middle of it -- a modal
  dialog opened from OnChange, a switch to another window, another control taking the
  capture. The button-up then goes elsewhere, and the controls went on following the
  pointer with no button held. LCL tells a control through CaptureChanged (Win32, GTK2);
  on every platform the next move shows no button held. Both end the drag. }

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, fpcunit, testregistry, BGRABitmap,
  tyControls.Types, tyControls.TrackBar, tyControls.ScrollBar, tyControls.Dial,
  tyControls.GearDial, tyControls.HSColorPicker, tyControls.LColorPicker,
  tyControls.ImageView, tyControls.Dialogs.Color;

type
  TValueOf = function(C: TControl): Double of object;
  TResetProc = procedure(C: TControl) of object;

  TCaptureLostTest = class(TTestCase)
  private
    FForm: TForm;
    function Place(C: TControl; AW, AH: Integer): TControl;
    { A held drag from A to B moves the value; after CaptureChanged, or after a move with no
      button held, a drag that follows does not. AReset puts the control back first. }
    procedure CheckDragEnds(C: TControl; AValue: TValueOf; AReset: TResetProc;
      const A, B: TPoint);
    procedure NoReset(C: TControl);
    procedure ScrollToTop(C: TControl);
    procedure FitAgain(C: TControl);
    function TrackPos(C: TControl): Double;
    function ScrollPos(C: TControl): Double;
    function DialValue(C: TControl): Double;
    function GearValue(C: TControl): Double;
    function HSValue(C: TControl): Double;
    function LValue(C: TControl): Double;
    function Fitted(C: TControl): Double;
    function SquareValue(C: TControl): Double;
    function HueValue(C: TControl): Double;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTrackBar;
    procedure TestScrollBar;
    procedure TestDial;
    procedure TestGearDial;
    procedure TestHSColorPicker;
    procedure TestLColorPicker;
    procedure TestImageView;
    procedure TestColorDialogSquare;
    procedure TestColorDialogHueStrip;
  end;

implementation

type
  TCrack = class(TControl);

{ The widgetset, made once and only when a test needs a real window (see test.base). }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TCaptureLostTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 400);
  FForm.Show;   // the dials take the focus on a press
end;

procedure TCaptureLostTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function TCaptureLostTest.Place(C: TControl; AW, AH: Integer): TControl;
begin
  C.Parent := FForm;
  C.SetBounds(0, 0, AW, AH);
  Result := C;
end;

procedure TCaptureLostTest.CheckDragEnds(C: TControl; AValue: TValueOf; AReset: TResetProc;
  const A, B: TPoint);
var
  v0: Double;
begin
  AReset(C);
  TCrack(C).MouseDown(mbLeft, [ssLeft], A.X, A.Y);
  v0 := AValue(C);
  TCrack(C).MouseMove([ssLeft], B.X, B.Y);
  AssertTrue(C.ClassName + ': setup, a held drag follows the pointer', AValue(C) <> v0);
  TCrack(C).MouseUp(mbLeft, [], B.X, B.Y);

  AReset(C);
  TCrack(C).MouseDown(mbLeft, [ssLeft], A.X, A.Y);
  v0 := AValue(C);
  TCrack(C).CaptureChanged;
  TCrack(C).MouseMove([ssLeft], B.X, B.Y);
  AssertEquals(C.ClassName + ': the capture taken away ended the drag', v0, AValue(C), 1e-9);
  TCrack(C).MouseUp(mbLeft, [], B.X, B.Y);

  AReset(C);
  TCrack(C).MouseDown(mbLeft, [ssLeft], A.X, A.Y);
  v0 := AValue(C);
  TCrack(C).MouseMove([], B.X, B.Y);
  TCrack(C).MouseMove([ssLeft], (A.X + B.X) div 2, (A.Y + B.Y) div 2);
  AssertEquals(C.ClassName + ': a move with no button held ended the drag', v0, AValue(C), 1e-9);
end;

procedure TCaptureLostTest.NoReset(C: TControl);
begin
end;

procedure TCaptureLostTest.ScrollToTop(C: TControl);
begin
  TTyScrollBar(C).Position := 0;   // the thumb back under A
end;

procedure TCaptureLostTest.FitAgain(C: TControl);
begin
  TTyImageView(C).AutoFit := True;
end;

function TCaptureLostTest.TrackPos(C: TControl): Double;
begin
  Result := TTyTrackBar(C).Position;
end;

function TCaptureLostTest.ScrollPos(C: TControl): Double;
begin
  Result := TTyScrollBar(C).Position;
end;

function TCaptureLostTest.DialValue(C: TControl): Double;
begin
  Result := TTyDial(C).Value;
end;

function TCaptureLostTest.GearValue(C: TControl): Double;
begin
  Result := TTyGearDial(C).Value;
end;

function TCaptureLostTest.HSValue(C: TControl): Double;
begin
  Result := TTyHSColorPicker(C).Hue * 1000 + TTyHSColorPicker(C).Sat;
end;

function TCaptureLostTest.LValue(C: TControl): Double;
begin
  Result := TTyLColorPicker(C).Position;
end;

function TCaptureLostTest.Fitted(C: TControl): Double;
begin
  Result := Ord(TTyImageView(C).AutoFit);   // a pan takes AutoFit off
end;

function TCaptureLostTest.SquareValue(C: TControl): Double;
begin
  Result := TTyHSVSquare(C).Sat * 1000 + TTyHSVSquare(C).Val;
end;

function TCaptureLostTest.HueValue(C: TControl): Double;
begin
  Result := TTyHueBar(C).Hue;
end;

procedure TCaptureLostTest.TestTrackBar;
var
  t: TTyTrackBar;
begin
  t := TTyTrackBar.Create(FForm);
  Place(t, 200, 30);
  t.Min := 0;
  t.Max := 100;
  CheckDragEnds(t, @TrackPos, @NoReset, Point(20, 15), Point(180, 15));
end;

procedure TCaptureLostTest.TestScrollBar;
var
  b: TTyScrollBar;
begin
  b := TTyScrollBar.Create(FForm);
  b.Kind := sbVertical;
  Place(b, 16, 200);
  b.Min := 0;
  b.Max := 100;
  b.PageSize := 25;
  CheckDragEnds(b, @ScrollPos, @ScrollToTop, Point(8, 20), Point(8, 120));   // A on the thumb
end;

procedure TCaptureLostTest.TestDial;
begin
  CheckDragEnds(Place(TTyDial.Create(FForm), 100, 100), @DialValue, @NoReset,
    Point(15, 50), Point(85, 50));
end;

procedure TCaptureLostTest.TestGearDial;
begin
  CheckDragEnds(Place(TTyGearDial.Create(FForm), 100, 100), @GearValue, @NoReset,
    Point(15, 50), Point(85, 50));
end;

procedure TCaptureLostTest.TestHSColorPicker;
begin
  CheckDragEnds(Place(TTyHSColorPicker.Create(FForm), 100, 100), @HSValue, @NoReset,
    Point(10, 10), Point(90, 90));
end;

procedure TCaptureLostTest.TestLColorPicker;
begin
  CheckDragEnds(Place(TTyLColorPicker.Create(FForm), 30, 100), @LValue, @NoReset,
    Point(15, 10), Point(15, 90));
end;

procedure TCaptureLostTest.TestImageView;
var
  v: TTyImageView;
  bmp: TBGRABitmap;
begin
  v := TTyImageView.Create(FForm);
  Place(v, 100, 100);
  bmp := TBGRABitmap.Create(400, 300);
  try
    v.AssignBitmap(bmp);
  finally
    bmp.Free;
  end;
  CheckDragEnds(v, @Fitted, @FitAgain, Point(50, 50), Point(80, 80));
end;

procedure TCaptureLostTest.TestColorDialogSquare;
begin
  CheckDragEnds(Place(TTyHSVSquare.Create(FForm), 100, 100), @SquareValue, @NoReset,
    Point(10, 10), Point(90, 90));
end;

procedure TCaptureLostTest.TestColorDialogHueStrip;
begin
  CheckDragEnds(Place(TTyHueBar.Create(FForm), 20, 100), @HueValue, @NoReset,
    Point(10, 10), Point(10, 90));
end;

initialization
  RegisterTest(TCaptureLostTest);
end.
