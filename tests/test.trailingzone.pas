unit test.trailingzone;
{$mode objfpc}{$H+}

{ Where a field puts the widget at its right-hand end.

  WHY THIS EXISTS. A user reported that a combo box's drop arrow "has a nice gap from the right
  edge, but everywhere else it is jammed against the border". Measured, the report was inverted:
  the combo box is the TIGHTEST of the family, and everything built on TTyEdit's trailing-widget
  seam sat one Padding.Right FURTHER from the frame -- because there were two conventions for
  deriving the same rectangle.

    TTyComboBox / TTyCascader / TTyTreeSelect / TTySpinEdit   zone hangs on the FRAME
    TTyComboEdit / TTyURLEdit / TTyCalcEdit / TTyFloatSpinEdit / TTyTrackEdit
                                                              zone hangs on the PADDED content

  So the same 9px chevron ended up 3px from the border in a TTyComboBox and 7 in a
  TTyComboEdit, with TTyCalcEdit and TTyFloatSpinEdit further in again. TTyFloatSpinEdit's own
  comment claimed it "lines up with a combo box's drop button and a spin edit's arrows"; it did
  not.

  So the invariant is: the trailing zone is FLUSH to the field's right edge, on every control
  that has one. That is one property, it is exact, and it is what these tests assert.

  WHY IT IS ASSERTED ON THE ZONE AND NOT ON PIXELS. The zone is the input to both the painter
  and the hit test -- they call one function now, which is the other half of this fix (they used
  to be two independent copies of the formula). A pixel assertion would measure the glyph
  centred inside the zone and would pass just as well if the two copies drifted apart again. }

interface

uses
  Classes, SysUtils, Types, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Edit, tyControls.ComboEdit, tyControls.URLEdit,
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit, tyControls.FloatSpinEdit,
  tyControls.TrackEdit;

type
  TTrailingZoneTest = class(TTestCase)
  private
    FForm: TForm;
    { The zone of one live control, sized AWidth x AHeight at 96 PPI. }
    function ZoneOf(AEdit: TTyEdit; AWidth, AHeight: Integer): TRect;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPureZoneIsFlushRight;
    procedure TestPureZoneEmptyWhenNothingReserved;
    procedure TestEveryTrailingFieldIsFlushRight;
    procedure TestZoneWidthIsTheReserve;
  end;

implementation

type
  TEditAccess = class(TTyEdit)
  public
    function Zone(APPI: Integer): TRect;
    function Reserve(APPI: Integer): Integer;
  end;

function TEditAccess.Zone(APPI: Integer): TRect;
begin
  Result := TrailingZone(APPI);
end;

function TEditAccess.Reserve(APPI: Integer): Integer;
begin
  Result := RightReserve(APPI);
end;

procedure TTrailingZoneTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Font.PixelsPerInch := 96;
end;

procedure TTrailingZoneTest.TearDown;
begin
  FForm.Free;
end;

function TTrailingZoneTest.ZoneOf(AEdit: TTyEdit; AWidth, AHeight: Integer): TRect;
begin
  AEdit.Parent := FForm;
  AEdit.Font.PixelsPerInch := 96;
  AEdit.SetBounds(0, 0, AWidth, AHeight);
  Result := TEditAccess(AEdit).Zone(96);
end;

{ The pure function, on its own. A rect in, a rect out -- no control, no theme. }
procedure TTrailingZoneTest.TestPureZoneIsFlushRight;
var
  r: TRect;
begin
  r := TyTrailingZone(Rect(0, 0, 200, 26), 18, 3, 3);
  AssertEquals('right edge is the field edge, not one padding short', 200, r.Right);
  AssertEquals('left edge is the reserve back from it', 182, r.Left);
  AssertEquals('top honours the vertical padding', 3, r.Top);
  AssertEquals('bottom honours the vertical padding', 23, r.Bottom);
end;

procedure TTrailingZoneTest.TestPureZoneEmptyWhenNothingReserved;
var
  r: TRect;
begin
  { A plain TTyEdit reserves nothing; the zone must be empty rather than a zero-width sliver
    at the right edge, because PaintTrailing and the hit test both gate on "is it empty". }
  r := TyTrailingZone(Rect(0, 0, 200, 26), 0, 3, 3);
  AssertEquals('empty left', 0, r.Left);
  AssertEquals('empty right', 0, r.Right);
  AssertEquals('empty top', 0, r.Top);
  AssertEquals('empty bottom', 0, r.Bottom);
end;

{ Every shipped control that reserves a trailing zone puts it in the same place. }
procedure TTrailingZoneTest.TestEveryTrailingFieldIsFlushRight;
const
  W = 200;
var
  ctls: array of TTyEdit;
  i: Integer;
  z: TRect;
  bad: string;
begin
  ctls := nil;
  SetLength(ctls, 6);
  ctls[0] := TTyComboEdit.Create(FForm);
  ctls[1] := TTyURLEdit.Create(FForm);
  ctls[2] := TTyCalcEdit.Create(FForm);
  ctls[3] := TTyCalcCurrencyEdit.Create(FForm);
  ctls[4] := TTyFloatSpinEdit.Create(FForm);
  ctls[5] := TTyTrackEdit.Create(FForm);
  bad := '';
  for i := 0 to High(ctls) do
  begin
    z := ZoneOf(ctls[i], W, 26);
    if z.Right <> W then
      bad := bad + LineEnding + '  ' + ctls[i].ClassName + ': zone ends at ' +
             IntToStr(z.Right) + ', field ends at ' + IntToStr(W);
  end;
  AssertEquals('trailing zones that are not flush with the field edge:' + bad, '', bad);
end;

procedure TTrailingZoneTest.TestZoneWidthIsTheReserve;
var
  e: TTyComboEdit;
  z: TRect;
begin
  { The zone's WIDTH is the control's own reserve, and its right edge is the field edge -- so
    the widget's position follows --field-button-width alone. A zone measured from the padded
    box would still be Reserve wide, which is why the flush assertion above is the one that
    catches the defect, and this one only pins that the width did not move with it. }
  e := TTyComboEdit.Create(FForm);
  z := ZoneOf(e, 200, 26);
  AssertEquals('zone width is RightReserve', TEditAccess(e).Reserve(96), z.Right - z.Left);
  AssertEquals('and RightReserve is the field-button token', TyFieldButtonWidth,
    TEditAccess(e).Reserve(96));
end;

initialization
  RegisterTest(TTrailingZoneTest);

end.
