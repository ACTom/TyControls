unit test.numericedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, LCLType, fpcunit, testregistry,
  tyControls.NumericEdit, tyControls.CurrencyEdit, tyControls.SpinEdit;
type
  { DoEnter / DoExit are protected and real focus never happens in a headless run, so the
    focus-in / blur reformats have to be driven directly. }
  TNumericFocusProbe = class(TTyNumericEdit)
  public
    procedure SimulateEnter;
    procedure SimulateExit;
  end;

  { The THIRD control of the spin-shaped family. It reaches the dirty-flag rule only by
    inheritance -- it has no reformat of its own, its two setters call TTyNumericEdit's --
    so nothing pinned it, and a `Text := Formatted(...)` added to CurrencyEdit later would
    break the contract silently while every existing guard stayed green. }
  TCurrencyFocusProbe = class(TTyCurrencyEdit)
  public
    procedure SimulateEnter;
    procedure SimulateExit;
  end;

  { The spin edit's keyboard seams, for the one guard that pins the two SIBLINGS against
    each other rather than each against itself. }
  TSpinModifiedProbe = class(TTySpinEdit)
  public
    procedure TypeChar(const C: TUTF8Char);
    procedure DoKey(K: Word);
  end;

  TNumericEditTest = class(TTestCase)
  published
    procedure TestFormat;
    procedure TestParse;
    procedure TestControl;
    { Modified (LCL TCustomEdit.Modified, stdctrls.pp:867) answers "did the USER touch this",
      which is what drives enable-Save. The reformats below are the control re-deriving its
      own display from the value the field already holds -- they must not read as the user
      undoing the edit they just finished. }
    procedure TestModifiedSurvivesTheBlurReformat;
    procedure TestModifiedSurvivesTheFocusInReformat;
    procedure TestADisplayOnlyPropertyChangeLeavesModifiedAlone;
    procedure TestModifiedStillClearedByAProgrammaticValueWrite;
    procedure TestNumericAndSpinAgreeAfterTheirOwnReformat;
  end;
implementation

procedure TNumericFocusProbe.SimulateEnter;
begin
  DoEnter;
end;

procedure TNumericFocusProbe.SimulateExit;
begin
  DoExit;
end;

procedure TCurrencyFocusProbe.SimulateEnter;
begin
  DoEnter;
end;

procedure TCurrencyFocusProbe.SimulateExit;
begin
  DoExit;
end;

procedure TSpinModifiedProbe.TypeChar(const C: TUTF8Char);
var K: TUTF8Char;
begin
  K := C;
  UTF8KeyPress(K);
end;

procedure TSpinModifiedProbe.DoKey(K: Word);
var W: Word;
begin
  W := K;
  KeyDown(W, []);
end;

procedure TNumericEditTest.TestFormat;
begin
  AssertEquals('grouped', '1,234.50', TyFormatNumber(1234.5, 2, ',', '.', True));
  AssertEquals('ungrouped', '1234.50', TyFormatNumber(1234.5, 2, ',', '.', False));
  AssertEquals('negative', '-1,234.50', TyFormatNumber(-1234.5, 2, ',', '.', True));
  AssertEquals('zero', '0.00', TyFormatNumber(0, 2, ',', '.', True));
  AssertEquals('int millions', '1,234,567', TyFormatNumber(1234567, 0, ',', '.', True));
  AssertEquals('euro separators', '1.234,50', TyFormatNumber(1234.5, 2, '.', ',', True));
end;

procedure TNumericEditTest.TestParse;
var d: Double;
begin
  AssertTrue('parses grouped', TyParseNumber('1,234.50', ',', '.', d));
  AssertEquals('grouped value', 1234.5, d, 1e-9);
  AssertTrue('parses negative', TyParseNumber('-1,234.50', ',', '.', d));
  AssertEquals('negative value', -1234.5, d, 1e-9);
  AssertFalse('rejects non-number', TyParseNumber('abc', ',', '.', d));
  AssertEquals('failed -> 0', 0.0, d, 1e-9);
  AssertTrue('parses euro', TyParseNumber('1.234,50', '.', ',', d));   // thousands '.', decimal ','
  AssertEquals('euro value', 1234.5, d, 1e-9);
end;

procedure TNumericEditTest.TestControl;
var c: TTyNumericEdit;
begin
  c := TTyNumericEdit.Create(nil);
  try
    AssertEquals('default text', '0.00', c.Text);
    AssertEquals('default value', 0.0, c.Value, 1e-9);
    c.Value := 1234.5;
    AssertEquals('grouped display', '1,234.50', c.Text);
    AssertEquals('value roundtrip', 1234.5, c.Value, 1e-9);
    c.MaxValue := 100;   // enables clamping (Max > Min)
    c.Value := 500;
    AssertEquals('clamped to max', 100.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TNumericEditTest.TestModifiedSurvivesTheBlurReformat;
{ Tabbing out of a numeric field re-groups the display through the published Text setter,
  whose contract is to clear Modified. Without a save/restore the user's edit is silently
  un-marked at the exact moment they finish it -- the field a Save button most needs. }
var c: TNumericFocusProbe;
begin
  c := TNumericFocusProbe.Create(nil);
  try
    c.Text := '';                       // programmatic seed: clean slate
    AssertFalse('a freshly seeded field is clean', c.Modified);
    c.InjectKey('1'); c.InjectKey('2'); c.InjectKey('3'); c.InjectKey('4');
    AssertTrue('typing dirties it', c.Modified);
    c.SimulateExit;                     // blur: clamp + regroup
    AssertEquals('the blur reformat still runs', '1,234.00', c.Text);
    AssertTrue('a reformat is the control''s own bookkeeping, not the user undoing the edit',
      c.Modified);
  finally c.Free; end;
end;

procedure TNumericEditTest.TestModifiedSurvivesTheFocusInReformat;
{ The other half of the same round trip: focus-in strips the grouping so the raw number is
  easy to edit. Tabbing back into a field must not clean it either. Deliberately does NOT
  go through the blur first -- otherwise a broken DoExit would fail this guard too and hide
  which of the two reformats is at fault. }
var c: TNumericFocusProbe;
begin
  c := TNumericFocusProbe.Create(nil);
  try
    c.Decimals := 0;
    c.Value := 1234;                    // programmatic, grouped display
    AssertEquals('grouped', '1,234', c.Text);
    AssertFalse('clean after the setup write', c.Modified);
    c.InjectKey('9');                   // the user appends a digit
    AssertTrue('typing dirties it', c.Modified);
    c.SimulateEnter;
    AssertEquals('the focus-in reformat still runs', '12349', c.Text);
    AssertTrue('re-entering the field is not the user undoing the edit', c.Modified);
  finally c.Free; end;
end;

procedure TNumericEditTest.TestADisplayOnlyPropertyChangeLeavesModifiedAlone;
{ Decimals / UseThousands / Min / Max all re-derive the display from the SAME value. A host
  changing how a number is shown has not changed what the user typed -- in EITHER direction:
  the reformat must not clear a dirty field, and must not invent an edit on a clean one. }
var c: TTyNumericEdit;
begin
  c := TTyNumericEdit.Create(nil);
  try
    c.Text := '';
    c.InjectKey('9');
    AssertTrue('typing dirties it', c.Modified);
    c.UseThousands := False;            // display form only -- the value is untouched
    AssertEquals('reformatted', '9.00', c.Text);
    AssertTrue('changing only the display format is not an edit', c.Modified);
  finally c.Free; end;

  c := TTyNumericEdit.Create(nil);
  try
    c.Value := 1234.5;                  // programmatic -> clean
    AssertFalse('clean after a programmatic write', c.Modified);
    c.UseThousands := False;            // the same reformat, on a clean field
    AssertEquals('reformatted', '1234.50', c.Text);
    AssertFalse('a reformat does not invent an edit either', c.Modified);
  finally c.Free; end;
end;

procedure TNumericEditTest.TestModifiedStillClearedByAProgrammaticValueWrite;
{ The other half of the contract, and the half the save/restore must not swallow: writing
  Value IS the program overwriting the field, so it cleans the flag. }
var c: TTyNumericEdit;
begin
  c := TTyNumericEdit.Create(nil);
  try
    c.Text := '5';
    AssertFalse('a programmatic write is not the user editing', c.Modified);
    c.InjectKey('7');
    AssertTrue('typing dirties it', c.Modified);
    c.Value := 42;
    AssertEquals('the code''s value won', '42.00', c.Text);
    AssertFalse('the code wrote it, so the user did not', c.Modified);
  finally c.Free; end;
end;

procedure TNumericEditTest.TestNumericAndSpinAgreeAfterTheirOwnReformat;
{ The spin-shaped controls in one library must answer "did the user touch this" the same
  way. Each reformats its own text at the end of an edit -- the numeric edit on blur, the
  spin edit on commit, the currency edit on blur through its parent's Reformat -- and none
  of those is a programmatic overwrite. This guard fails if ANY side drifts, which is the
  point: it has no preferred side.

  The currency edit is here because it is the one that agrees by ACCIDENT of inheritance:
  it owns no reformat and no dirty-flag code at all, so the two guards above cover it only
  as long as it stays that way. Add one `Text := Formatted(...)` to CurrencyEdit and the
  contract breaks with every other test still green. }
var
  n: TNumericFocusProbe;
  s: TSpinModifiedProbe;
  c: TCurrencyFocusProbe;
begin
  n := TNumericFocusProbe.Create(nil);
  s := TSpinModifiedProbe.Create(nil);
  c := TCurrencyFocusProbe.Create(nil);
  try
    n.Text := '';
    n.InjectKey('5'); n.InjectKey('9');
    n.SimulateExit;                     // the numeric edit's own reformat

    s.MinValue := 0; s.MaxValue := 100;
    s.TypeChar('5'); s.TypeChar('9');
    s.DoKey(VK_RETURN);                 // the spin edit's own reformat

    c.Text := '';
    c.InjectKey('5'); c.InjectKey('9');
    c.SimulateExit;                     // the currency edit's INHERITED reformat

    AssertEquals('both committed the same number', 59, Round(n.Value));
    AssertEquals('both committed the same number', 59, s.Value);
    AssertEquals('and so did the third', 59, Round(c.Value));
    AssertEquals('the two siblings agree on Modified after their own reformat',
      s.Modified, n.Modified);
    AssertEquals('and the currency edit agrees with them',
      n.Modified, c.Modified);
    AssertTrue('and they agree on TRUE -- the user did type it', n.Modified);
    { The other direction, on the currency edit specifically: its OWN setters go through
      the same Reformat, so changing the symbol must not read as the user editing either. }
    c.CurrencySymbol := 'EUR';
    AssertTrue('changing the symbol is a display change, not an edit', c.Modified);
    c.Value := 12;
    AssertFalse('but a programmatic value write still cleans it', c.Modified);
  finally
    n.Free; s.Free; c.Free;
  end;
end;

initialization
  RegisterTest(TNumericEditTest);
end.
