program maxprobe;
{$mode objfpc}{$H+}
{ Which Math.Max/Min overload does FPC actually pick?

  Kept because the answer is counter-intuitive, costs real precision, and was
  disputed: `Max(0, <Double>)` returns a SINGLE -- the integer literal makes
  Single the cheaper conversion -- so every value through it is rounded to a
  24-bit mantissa. Nothing raises; the numbers stay plausible; a test comparing
  against a formula disagrees in the eighth significant digit, which reads like
  a tolerance problem rather than a precision one.

  An untyped REAL constant does NOT do this: `Max(1.0, d)` is Double, even
  though 1.0 fits a Single exactly. So the rule is about the INTEGER literal,
  not about "constants" in general.

  The decisive check is SizeOf, not a comparison: it is a compile-time fact
  about the return type, and cannot be confused by constant folding or by the
  Single result being widened back to Double before comparing.

  Build and run:  fpc -O1 maxprobe.pas && ./maxprobe }
uses Math, SysUtils;
const
  cOne  = 1.0;      { exactly representable as Single }
  cTenth = 0.10;    { not exactly representable in any binary type }
var
  d, band: Double;
  i: Integer;

  procedure Say(const AWhat: string; AGot, AWant: Double);
  begin
    if AGot = AWant then
      WriteLn('  exact    ', AWhat)
    else
      WriteLn('  TRUNCATED ', AWhat, '   got=', AGot:0:15, ' want=', AWant:0:15);
  end;

begin
  d := 78.2142857142857;

  { The peer's case: an INTEGER literal beside a Double variable. }
  Say('Max(0, d)', Max(0, d), d);
  Say('Min(999, d)', Min(999, d), d);

  { Mine: an UNTYPED REAL CONSTANT that Single can hold exactly. }
  Say('Max(cOne, d)', Max(cOne, d), d);
  Say('Max(1.0, d)', Max(1.0, d), d);

  { And one that Single cannot hold exactly. }
  Say('Max(cTenth, d)', Max(cTenth, d), d);

  { The actual shape from the solver: band clamped, then divided. }
  band := 225.0;
  Say('Max(cOne, band)', Max(cOne, band), band);
  d := 0.73 / 2.1 * band;
  Say('0.73/2.1*Max(cOne,band)', 0.73 / 2.1 * Max(cOne, band), d);

  { The memory's own case, for comparison: integer x untyped real constant. }
  i := 16777217;
  Say('i * 1.0', i * 1.0, 16777217.0);
  Say('Double(i) * 1.0', Double(i) * 1.0, 16777217.0);

  WriteLn('sizes: SizeOf(Max(cOne,d))=', SizeOf(Max(cOne, d)),
          '  SizeOf(Max(0,d))=', SizeOf(Max(0, d)),
          '  SizeOf(d)=', SizeOf(d));
end.
