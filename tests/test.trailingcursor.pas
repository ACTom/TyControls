unit test.trailingcursor;
{$mode objfpc}{$H+}

{ #84: the pointer over the trailing widget of an edit -- TTyTrackEdit's slider, TTyComboEdit's
  drop button, TTyURLEdit's open button, the calculator button of TTyCalcEdit and
  TTyCalcCurrencyEdit, the "..." button of a TTyValueListEditor cell editor -- showed the I-beam,
  which says "text" over a part that is a button or a slider.

  They all hang the widget on the zone TTyEdit reserves on the right (RightReserve /
  TrailingZone), so TTyEdit owns the cursor there, and every one of them is run through the same
  cases: each overrides RightReserve on its own, and any one of them can be the edit whose zone
  the rule misses. TTyFloatSpinEdit manages the cursor over its spin buttons itself
  (test.spinbuttons); that suite is what keeps the two from fighting. }

interface

uses
  Classes, SysUtils, Types, Controls, fpcunit, testregistry,
  tyControls.Edit, tyControls.TrackEdit, tyControls.ComboEdit, tyControls.URLEdit,
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit, tyControls.ValueListEditor;

type
  TTrailingCursorTest = class(TTestCase)
  private
    FEdit: TTyEdit;
    procedure Build(AEdit: TTyEdit);
    function ZonePoint: TPoint;
    function TextPoint: TPoint;
    procedure Move(const APt: TPoint; AShift: TShiftState = []);
    procedure Press(const APt: TPoint);
    procedure Release(const APt: TPoint);
    procedure Leave;
    procedure CheckEveryCase(const AName: string);
  protected
    procedure TearDown; override;
  published
    procedure TestTrackEdit;
    procedure TestComboEdit;
    procedure TestURLEdit;
    procedure TestCalcEdit;
    procedure TestCalcCurrencyEdit;
    procedure TestValueEditWithEllipsis;
    { A drag on the slider keeps the arrow when it runs out over the text, as a native slider
      does; the I-beam comes back with the first move after the release. }
    procedure TestTrackEditDragKeepsTheArrow;
    { The reverse: a text selection dragged out over the widget keeps the I-beam it started
      with -- the press was on text, so the gesture is a text gesture until it ends. }
    procedure TestTextSelectionKeepsTheIBeamOverTheZone;
    { A plain edit reserves nothing, so there is no zone to be over: the I-beam everywhere. }
    procedure TestPlainEditHasNoZone;
  end;

implementation

type
  TEditAccess = class(TTyEdit)
  end;

function CursorName(C: TCursor): string;
begin
  case C of
    crIBeam: Result := 'crIBeam';
    crArrow: Result := 'crArrow';
    crDefault: Result := 'crDefault';
    crHandPoint: Result := 'crHandPoint';
  else
    Result := IntToStr(C);
  end;
end;

procedure TTrailingCursorTest.Build(AEdit: TTyEdit);
begin
  FEdit := AEdit;
  FEdit.Font.PixelsPerInch := 96;
  FEdit.SetBounds(10, 10, 200, 28);
end;

procedure TTrailingCursorTest.TearDown;
begin
  FreeAndNil(FEdit);
end;

function TTrailingCursorTest.ZonePoint: TPoint;
begin
  Result := CenterPoint(TEditAccess(FEdit).TrailingZone(96));
end;

function TTrailingCursorTest.TextPoint: TPoint;
begin
  Result := Point(10, FEdit.Height div 2);
end;

procedure TTrailingCursorTest.Move(const APt: TPoint; AShift: TShiftState);
begin
  TEditAccess(FEdit).MouseMove(AShift, APt.X, APt.Y);
end;

procedure TTrailingCursorTest.Press(const APt: TPoint);
begin
  TEditAccess(FEdit).MouseDown(mbLeft, [ssLeft], APt.X, APt.Y);
end;

procedure TTrailingCursorTest.Release(const APt: TPoint);
begin
  TEditAccess(FEdit).MouseUp(mbLeft, [], APt.X, APt.Y);
end;

procedure TTrailingCursorTest.Leave;
begin
  TEditAccess(FEdit).MouseLeave;
end;

procedure TTrailingCursorTest.CheckEveryCase(const AName: string);
var
  z: TRect;
begin
  z := TEditAccess(FEdit).TrailingZone(96);
  AssertTrue(AName + ': precondition, a trailing zone is reserved', z.Right > z.Left);
  AssertEquals(AName + ': precondition, the field shows the I-beam',
    CursorName(crIBeam), CursorName(FEdit.Cursor));
  Move(ZonePoint);
  AssertEquals(AName + ': over the trailing widget, the arrow',
    CursorName(crArrow), CursorName(FEdit.Cursor));
  Move(TextPoint);
  AssertEquals(AName + ': back over the text, the I-beam again',
    CursorName(crIBeam), CursorName(FEdit.Cursor));
  Move(ZonePoint);
  Leave;
  AssertEquals(AName + ': leaving the control from the widget puts the I-beam back too',
    CursorName(crIBeam), CursorName(FEdit.Cursor));

  FEdit.Cursor := crHandPoint;
  Move(ZonePoint);
  AssertEquals(AName + ': the arrow over the widget whatever the control''s own cursor',
    CursorName(crArrow), CursorName(FEdit.Cursor));
  Move(TextPoint);
  AssertEquals(AName + ': and the control''s own cursor back after it, not a hard-coded I-beam',
    CursorName(crHandPoint), CursorName(FEdit.Cursor));
end;

procedure TTrailingCursorTest.TestTrackEdit;
begin
  Build(TTyTrackEdit.Create(nil));
  CheckEveryCase('TTyTrackEdit');
end;

procedure TTrailingCursorTest.TestComboEdit;
begin
  Build(TTyComboEdit.Create(nil));
  CheckEveryCase('TTyComboEdit');
end;

procedure TTrailingCursorTest.TestURLEdit;
begin
  Build(TTyURLEdit.Create(nil));
  CheckEveryCase('TTyURLEdit');
end;

procedure TTrailingCursorTest.TestCalcEdit;
begin
  Build(TTyCalcEdit.Create(nil));
  CheckEveryCase('TTyCalcEdit');
end;

procedure TTrailingCursorTest.TestCalcCurrencyEdit;
begin
  Build(TTyCalcCurrencyEdit.Create(nil));
  CheckEveryCase('TTyCalcCurrencyEdit');
end;

procedure TTrailingCursorTest.TestValueEditWithEllipsis;
var
  v: TTyValueEdit;
begin
  v := TTyValueEdit.Create(nil);
  v.ShowEllipsis := True;
  Build(v);
  CheckEveryCase('TTyValueEdit');
end;

procedure TTrailingCursorTest.TestTrackEditDragKeepsTheArrow;
var
  t: TTyTrackEdit;
begin
  t := TTyTrackEdit.Create(nil);
  Build(t);
  Move(ZonePoint);
  Press(ZonePoint);
  Move(TextPoint, [ssLeft]);
  AssertEquals('dragging the slider out over the text keeps the arrow',
    CursorName(crArrow), CursorName(FEdit.Cursor));
  AssertEquals('precondition: and the drag still sets the value (the far left end)',
    0.0, t.Value, 1e-9);
  Release(TextPoint);
  Move(TextPoint);
  AssertEquals('the first move after the release: the I-beam over the text',
    CursorName(crIBeam), CursorName(FEdit.Cursor));
end;

procedure TTrailingCursorTest.TestTextSelectionKeepsTheIBeamOverTheZone;
begin
  Build(TTyComboEdit.Create(nil));
  FEdit.Text := 'some text';
  Move(TextPoint);
  Press(TextPoint);
  Move(ZonePoint, [ssLeft]);
  AssertEquals('a text selection dragged over the button keeps the I-beam',
    CursorName(crIBeam), CursorName(FEdit.Cursor));
  Release(ZonePoint);
  Move(ZonePoint);
  AssertEquals('once released, the button shows the arrow',
    CursorName(crArrow), CursorName(FEdit.Cursor));
end;

procedure TTrailingCursorTest.TestPlainEditHasNoZone;
begin
  Build(TTyEdit.Create(nil));
  Move(Point(FEdit.Width - 3, FEdit.Height div 2));
  AssertEquals('a plain edit: the I-beam at its right edge too',
    CursorName(crIBeam), CursorName(FEdit.Cursor));
end;

initialization
  RegisterTest(TTrailingCursorTest);

end.
