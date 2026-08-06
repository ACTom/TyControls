unit test.updown;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.UpDown;
type
  TUpDownTest = class(TTestCase)
  published
    procedure TestButtonRect;
    procedure TestHit;
    procedure TestClamp;
    procedure TestPositionClamps;
    { The three pure rules behind Associate. LCL keeps all three inside methods that need a
      live Parent, a live handle and a live associate, which is why none of them is unit
      tested there -- and they are the only places the feature can be arithmetically wrong. }
    procedure TestFormatPositionMatchesLclGrouping;
    procedure TestParsePositionIsTheInverse;
    procedure TestAlignedBoundsSnapToEachSide;
  end;
implementation

procedure TUpDownTest.TestButtonRect;
var r: TRect;
begin
  // Vertical 20x34: up = top half, down = bottom half.
  r := TyUpDownButtonRect(True, 20, 34, True);
  AssertEquals('v up top', 0, r.Top);   AssertEquals('v up bottom', 17, r.Bottom);
  r := TyUpDownButtonRect(False, 20, 34, True);
  AssertEquals('v down top', 17, r.Top); AssertEquals('v down bottom', 34, r.Bottom);
  // Horizontal 40x20: up = right, down = left.
  r := TyUpDownButtonRect(True, 40, 20, False);
  AssertEquals('h up left', 20, r.Left); AssertEquals('h up right', 40, r.Right);
  r := TyUpDownButtonRect(False, 40, 20, False);
  AssertEquals('h down left', 0, r.Left); AssertEquals('h down right', 20, r.Right);
end;

procedure TUpDownTest.TestHit;
begin
  AssertEquals('v top -> up', 1, TyUpDownHit(10, 4, 20, 34, True));
  AssertEquals('v bottom -> down', -1, TyUpDownHit(10, 30, 20, 34, True));
  AssertEquals('outside', 0, TyUpDownHit(25, 4, 20, 34, True));
  AssertEquals('h right -> up', 1, TyUpDownHit(30, 10, 40, 20, False));
  AssertEquals('h left -> down', -1, TyUpDownHit(5, 10, 40, 20, False));
end;

procedure TUpDownTest.TestClamp;
begin
  AssertEquals('clamp high', 5, TyUpDownClamp(9, 0, 5, False));
  AssertEquals('clamp low', 0, TyUpDownClamp(-3, 0, 5, False));
  AssertEquals('in range', 3, TyUpDownClamp(3, 0, 5, False));
  AssertEquals('wrap over -> min', 0, TyUpDownClamp(6, 0, 5, True));
  AssertEquals('wrap under -> max', 5, TyUpDownClamp(-1, 0, 5, True));
  AssertEquals('inverted range -> min', 0, TyUpDownClamp(3, 0, -5, False));
end;

procedure TUpDownTest.TestPositionClamps;
var c: TTyUpDown;
begin
  c := TTyUpDown.Create(nil);
  try
    c.Min := 0; c.Max := 10;
    c.Position := 20;   AssertEquals('clamped to max', 10, c.Position);
    c.Position := 8;    AssertEquals('set in range', 8, c.Position);
    c.Max := 3;         AssertEquals('shrinking max re-clamps', 3, c.Position);
    c.Position := -5;   AssertEquals('clamped to min', 0, c.Position);
    c.Increment := 0;   AssertEquals('increment floored to 1', 1, c.Increment);
  finally c.Free; end;
end;

procedure TUpDownTest.TestFormatPositionMatchesLclGrouping;
{ The expected strings are not invented here: they are what
  FloatToStrF(v, ffNumber, 0, 0) -- the call LCL makes at customupdown.inc:259 -- returns
  for the same v under a ',' group separator, checked against a throwaway FPC program
  before this guard was written. Grouping that disagrees with LCL by one digit produces a
  field a ported form reads back wrongly, silently. }
begin
  AssertEquals('zero', '0', TyUpDownFormatPosition(0, True, ','));
  AssertEquals('single digit', '7', TyUpDownFormatPosition(7, True, ','));
  AssertEquals('last ungrouped', '999', TyUpDownFormatPosition(999, True, ','));
  AssertEquals('first grouped', '1,000', TyUpDownFormatPosition(1000, True, ','));
  AssertEquals('four digits', '1,234', TyUpDownFormatPosition(1234, True, ','));
  AssertEquals('two groups', '1,234,567', TyUpDownFormatPosition(1234567, True, ','));
  AssertEquals('negative groups', '-1,234', TyUpDownFormatPosition(-1234, True, ','));
  AssertEquals('negative ungrouped', '-999', TyUpDownFormatPosition(-999, True, ','));
  AssertEquals('LCL SmallInt ceiling', '32,767', TyUpDownFormatPosition(32767, True, ','));
  { Abs(Low(Integer)) does not fit in an Integer -- it wraps back to itself -- so a
    formatter that abs()es in Integer prints this one with a stray sign or no digits. }
  AssertEquals('most negative Integer', '-2,147,483,648',
    TyUpDownFormatPosition(Low(Integer), True, ','));
  // Thousands=False is plain IntToStr, group char or no group char.
  AssertEquals('ungrouped', '1234567', TyUpDownFormatPosition(1234567, False, ','));
  AssertEquals('ungrouped negative', '-1234', TyUpDownFormatPosition(-1234, False, ','));
  // The separator is an argument, not the locale: a euro-style group char groups the same.
  AssertEquals('euro group char', '1.234.567', TyUpDownFormatPosition(1234567, True, '.'));
  AssertEquals('space group char', '1 234', TyUpDownFormatPosition(1234, True, ' '));
end;

procedure TUpDownTest.TestParsePositionIsTheInverse;
var v: Integer;
begin
  AssertTrue('reads grouped', TyUpDownParsePosition('1,234', ',', v));
  AssertEquals('grouped value', 1234, v);
  AssertTrue('reads plain', TyUpDownParsePosition('42', ',', v));
  AssertEquals('plain value', 42, v);
  AssertTrue('tolerates surrounding space', TyUpDownParsePosition('  7  ', ',', v));
  AssertEquals('trimmed value', 7, v);
  AssertTrue('reads negative grouped', TyUpDownParsePosition('-1,234', ',', v));
  AssertEquals('negative value', -1234, v);
  AssertTrue('reads a euro-grouped field', TyUpDownParsePosition('1.234', '.', v));
  AssertEquals('euro value', 1234, v);
  { Failure has to be reported, not guessed at: an unreadable field means "keep the value
    you have", and a parser that silently answered 0 would reset the pair every time the
    user cleared the box or typed the '-' of '-5'. }
  AssertFalse('rejects words', TyUpDownParsePosition('abc', ',', v));
  AssertFalse('rejects empty', TyUpDownParsePosition('', ',', v));
  AssertFalse('rejects a lone sign', TyUpDownParsePosition('-', ',', v));
  AssertFalse('rejects a half-typed decimal', TyUpDownParsePosition('1.5', ',', v));
  // Round trip: every value this control can write, it can read back.
  AssertTrue('round trip', TyUpDownParsePosition(
    TyUpDownFormatPosition(-98765, True, ','), ',', v));
  AssertEquals('round-trip value', -98765, v);
end;

procedure TUpDownTest.TestAlignedBoundsSnapToEachSide;
{ The field sits at (100,50) and is 80x24; the pair is 20x34 on its own.
  Left/right keep the pair's WIDTH and take the field's height; top/bottom keep the pair's
  HEIGHT and take the field's width (LCL UpdateAlignButtonPos, customupdown.inc:303-329). }
var
  fld: TRect;
  r: TRect;
begin
  fld := Rect(100, 50, 180, 74);
  r := TyUpDownAlignedBounds(fld, 20, 34, udaRight);
  AssertEquals('right: hugs the field''s right edge', 180, r.Left);
  AssertEquals('right: keeps own width', 20, r.Right - r.Left);
  AssertEquals('right: shares the top', 50, r.Top);
  AssertEquals('right: takes the field''s height', 24, r.Bottom - r.Top);

  r := TyUpDownAlignedBounds(fld, 20, 34, udaLeft);
  AssertEquals('left: sits its own width before the field', 80, r.Left);
  AssertEquals('left: right edge meets the field', 100, r.Right);
  AssertEquals('left: shares the top', 50, r.Top);
  AssertEquals('left: takes the field''s height', 24, r.Bottom - r.Top);

  r := TyUpDownAlignedBounds(fld, 20, 34, udaTop);
  AssertEquals('top: shares the left', 100, r.Left);
  AssertEquals('top: takes the field''s width', 80, r.Right - r.Left);
  AssertEquals('top: sits its own height above', 16, r.Top);
  AssertEquals('top: bottom edge meets the field', 50, r.Bottom);

  r := TyUpDownAlignedBounds(fld, 20, 34, udaBottom);
  AssertEquals('bottom: shares the left', 100, r.Left);
  AssertEquals('bottom: takes the field''s width', 80, r.Right - r.Left);
  AssertEquals('bottom: hugs the field''s bottom edge', 74, r.Top);
  AssertEquals('bottom: keeps own height', 34, r.Bottom - r.Top);
end;

initialization
  RegisterTest(TUpDownTest);
end.
