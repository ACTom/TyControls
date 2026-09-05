unit test.measurecache;
{$mode objfpc}{$H+}
{ The caption-measurement memo (tyControls.Painter): TyMeasureTextBlock and
  TyMeasureRenderedTextWidth are memoised, and this is the suite that says the memo cannot
  serve a stale answer.

  WHY THE STALENESS HALF IS THE LOAD-BEARING HALF. The performance case is not in doubt --
  plans/2026-08-08-permonitor-dpi.md §2e measured caption re-measurement at 57% of a
  synchronous WM_DPICHANGED pass, 480 calls at ~0.7 ms on a 60-control form. The RISK is
  that a theme change reaches these controls as a bare Invalidate, so a memo keyed on too
  little quietly keeps the previous theme's width -- which is the ellipsised-toolbar-button
  defect (memory/skin-variance-breaks-fixed-widths) that those Invalidate overrides were
  written to fix in the first place. A memo that never goes stale in tests but does in the
  field is worse than no memo, so every input in the enumeration at
  TyInvalidateTextMeasureCache gets a test that CHANGES it and demands a different answer.

  THE SHAPE EVERY STALENESS TEST HERE USES, and why it is an edge probe rather than a
  centre one (memory/tests-that-pin-the-bug): measure under configuration A first -- that
  is what POPULATES the memo -- then change exactly one input and measure again. If the key
  omitted that input, the second call is a HIT and returns A's number, so the assertion
  fires. Asserting the second number in isolation would pass whether or not the memo
  existed, which is the fake-green version of this file.

  The magnitudes asserted below were measured on this host with af881_probe before the
  assertions were written, so none of them is wishful: e.g. Arial vs Times New Roman is
  50x12 vs 46x12 on the block path and 67 vs 60 on the rendered path, and a 9 -> 24 size is
  50 -> 131. Where two configurations happened to measure the SAME (Arial and Courier New
  are both 50 wide on the LCL canvas) the pair was replaced rather than the assertion
  weakened -- a staleness test that compares two equal numbers proves nothing. }
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes;

type
  TMeasureCacheTest = class(TTestCase)
  private
    FSavedName: string;
    FSavedSize: Integer;
    FSavedEnabled: Boolean;
    { Block width under the given configuration, with the memo LIVE. }
    function BlockW(const AText, AFont: string; ASize, AWeight, APPI, AWrap, ALineH: Integer): Integer;
    function BlockH(const AText, AFont: string; ASize, AWeight, APPI, AWrap, ALineH: Integer): Integer;
    function Entries: Integer;
    function Hits: Int64;
    function Misses: Int64;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // --- the SHARED measuring surface must never change an answer -----------
    procedure AReusedSurfaceNeverChangesAnAnswer;
    // --- the memo must never change an answer -------------------------------
    procedure MemoNeverChangesAnAnswer;
    procedure RepeatedIdenticalMeasurementIsServedFromTheMemo;
    // --- staleness: one test per keyed input --------------------------------
    procedure CaptionChangeChangesTheMeasurement;
    procedure FontFamilyChangeChangesTheMeasurement;
    procedure FontSizeChangeChangesTheMeasurement;
    procedure FontWeightChangeChangesTheMeasurement;
    procedure PPIChangeChangesTheMeasurement;
    procedure WrapWidthChangeChangesTheMeasurement;
    procedure LineHeightChangeChangesTheMeasurement;
    // --- staleness: the two MUTABLE GLOBALS the key has to fold in ----------
    procedure FallbackFontSizeChangeChangesTheMeasurement;
    procedure FallbackFontNameChangeChangesTheMeasurement;
    // --- staleness through the real theme path ------------------------------
    procedure ThemeChangeChangesTheMeasuredFontSize;
    procedure TyTextMeasureCacheDropsOnThemeChange;
    // --- the key must be injective -----------------------------------------
    procedure FontNameAndCaptionCannotRunTogetherInTheKey;
    // --- mechanics ----------------------------------------------------------
    procedure InvalidateEmptiesTheCache;
    procedure CacheIsBoundedAndNeverGrowsWithoutLimit;
    procedure DisablingTheMemoStopsItCachingAndAnswersTheSame;
  end;

implementation

const
  { A caption long enough that a one-pixel metric difference is not the only signal, and
    ASCII so it measures the same way on every widgetset. }
  CAP = 'Measure Me';

procedure TMeasureCacheTest.SetUp;
begin
  FSavedName := TyFallbackFontName;
  FSavedSize := TyFallbackFontSize;
  FSavedEnabled := TyTextMeasureCacheEnabled;
  TyTextMeasureCacheEnabled := True;
  TyInvalidateTextMeasureCache;
  TyResetTextMeasureCacheStats;
end;

procedure TMeasureCacheTest.TearDown;
begin
  TyFallbackFontName := FSavedName;
  TyFallbackFontSize := FSavedSize;
  TyTextMeasureCacheEnabled := FSavedEnabled;
  { Leave nothing measured under this test's globals behind for the next test -- these
    ARE the globals the memo folds into its key, so a leftover entry would be keyed
    correctly but would still make the next test's hit/miss counts a lie. }
  TyInvalidateTextMeasureCache;
end;

function TMeasureCacheTest.BlockW(const AText, AFont: string;
  ASize, AWeight, APPI, AWrap, ALineH: Integer): Integer;
var h: Integer;
begin
  TyMeasureTextBlock(AText, AFont, ASize, AWeight, APPI, AWrap, ALineH, Result, h);
end;

function TMeasureCacheTest.BlockH(const AText, AFont: string;
  ASize, AWeight, APPI, AWrap, ALineH: Integer): Integer;
var w: Integer;
begin
  TyMeasureTextBlock(AText, AFont, ASize, AWeight, APPI, AWrap, ALineH, w, Result);
end;

function TMeasureCacheTest.Entries: Integer;
var hi, mi: Int64;
begin
  TyTextMeasureCacheStats(hi, mi, Result);
end;

function TMeasureCacheTest.Hits: Int64;
var mi: Int64; e: Integer;
begin
  TyTextMeasureCacheStats(Result, mi, e);
end;

function TMeasureCacheTest.Misses: Int64;
var hi: Int64; e: Integer;
begin
  TyTextMeasureCacheStats(hi, Result, e);
end;

{ ===== the memo must never change an answer ================================= }

procedure TMeasureCacheTest.MemoNeverChangesAnAnswer;
{ The correctness half. For a spread of configurations, the number the memo hands back on
  a HIT must equal the number computed with the memo switched off entirely -- and the
  rendered-width path is checked alongside the block path because they are two different
  rasterisers with two separate caches.

  Three readings per configuration, deliberately: OFF (the ground truth), the memo's MISS
  (which computes and stores), and the memo's HIT (which is the only one a wrong cache
  could corrupt). A test that compared only OFF against the miss would pass with a cache
  that stored garbage and never read it. }
type
  TCfg = record T, F: string; Sz, W, P, Wr, Lh: Integer; end;
const
  CFG: array[0..6] of TCfg = (
    (T: 'Measure Me';      F: 'Arial';           Sz:  9; W: 400; P:  96; Wr:  0; Lh:  0),
    (T: 'Measure Me';      F: 'Times New Roman'; Sz: 12; W: 700; P: 144; Wr:  0; Lh:  0),
    (T: 'Measure Me Now';  F: 'Arial';           Sz:  9; W: 400; P: 240; Wr: 40; Lh:  0),
    (T: 'Two'#13#10'Line'; F: 'Arial';           Sz:  9; W: 400; P:  96; Wr:  0; Lh: 30),
    (T: '';                F: 'Arial';           Sz:  9; W: 400; P:  96; Wr:  0; Lh:  0),
    (T: '你好世界';         F: '';                Sz: 11; W: 400; P:  96; Wr:  0; Lh:  0),
    (T: 'Measure Me';      F: 'Arial';           Sz:  0; W: 400; P:  96; Wr:  0; Lh:  0)
  );
var
  i, wOff, hOff, wMiss, hMiss, wHit, hHit, rOff, rMiss, rHit: Integer;
  tag: string;
begin
  for i := Low(CFG) to High(CFG) do
  begin
    tag := Format('cfg %d (%s/%s/%d)', [i, CFG[i].T, CFG[i].F, CFG[i].Sz]);

    TyTextMeasureCacheEnabled := False;
    TyMeasureTextBlock(CFG[i].T, CFG[i].F, CFG[i].Sz, CFG[i].W, CFG[i].P,
      CFG[i].Wr, CFG[i].Lh, wOff, hOff);
    rOff := TyMeasureRenderedTextWidth(CFG[i].T, CFG[i].F, CFG[i].Sz, CFG[i].W, CFG[i].P);

    TyTextMeasureCacheEnabled := True;
    TyInvalidateTextMeasureCache;
    TyMeasureTextBlock(CFG[i].T, CFG[i].F, CFG[i].Sz, CFG[i].W, CFG[i].P,
      CFG[i].Wr, CFG[i].Lh, wMiss, hMiss);
    rMiss := TyMeasureRenderedTextWidth(CFG[i].T, CFG[i].F, CFG[i].Sz, CFG[i].W, CFG[i].P);

    TyMeasureTextBlock(CFG[i].T, CFG[i].F, CFG[i].Sz, CFG[i].W, CFG[i].P,
      CFG[i].Wr, CFG[i].Lh, wHit, hHit);
    rHit := TyMeasureRenderedTextWidth(CFG[i].T, CFG[i].F, CFG[i].Sz, CFG[i].W, CFG[i].P);

    AssertEquals(tag + ': block width, memo miss vs memo off', wOff, wMiss);
    AssertEquals(tag + ': block height, memo miss vs memo off', hOff, hMiss);
    AssertEquals(tag + ': block width, memo HIT vs memo off', wOff, wHit);
    AssertEquals(tag + ': block height, memo HIT vs memo off', hOff, hHit);
    AssertEquals(tag + ': rendered width, memo miss vs memo off', rOff, rMiss);
    AssertEquals(tag + ': rendered width, memo HIT vs memo off', rOff, rHit);
  end;
end;

procedure TMeasureCacheTest.RepeatedIdenticalMeasurementIsServedFromTheMemo;
{ The performance claim, asserted as behaviour rather than as a stopwatch: the SECOND
  identical measurement must not reach the font engine. Without this the whole suite would
  pass on a memo that stores everything and reads nothing -- correct, and worthless. }
var
  m0, h0: Int64;
begin
  BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  m0 := Misses;
  h0 := Hits;
  AssertEquals('first measurement is a miss', 1, m0);
  AssertEquals('first measurement is not a hit', 0, h0);

  BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  AssertEquals('repeats add no misses', m0, Misses);
  AssertEquals('repeats are served from the memo', h0 + 2, Hits);

  { and the rendered path keeps its own counters moving too }
  TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 96);
  AssertEquals('rendered width: first is a miss', m0 + 1, Misses);
  TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 96);
  AssertEquals('rendered width: second is a hit', h0 + 3, Hits);
end;

{ ===== staleness: one per keyed input ======================================= }

procedure TMeasureCacheTest.CaptionChangeChangesTheMeasurement;
begin
  AssertTrue('a different caption must measure differently',
    BlockW('Measure Me', 'Arial', 9, 400, 96, 0, 0)
      <> BlockW('Measure Me Now Please', 'Arial', 9, 400, 96, 0, 0));
end;

procedure TMeasureCacheTest.FontFamilyChangeChangesTheMeasurement;
{ Arial 50 vs Times New Roman 46 on the block path, 67 vs 60 rendered (af881_probe).
  Courier New was the obvious second family and is NOT used: it measures 50 on the LCL
  canvas exactly as Arial does, so a block-path assertion against it would have been
  green with a completely broken key. }
var a, b: Integer;
begin
  a := BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  b := BlockW(CAP, 'Times New Roman', 9, 400, 96, 0, 0);
  AssertTrue(Format('block: a different family must re-measure (%d vs %d)', [a, b]), a <> b);

  a := TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 96);
  b := TyMeasureRenderedTextWidth(CAP, 'Times New Roman', 9, 400, 96);
  AssertTrue(Format('rendered: a different family must re-measure (%d vs %d)', [a, b]), a <> b);
end;

procedure TMeasureCacheTest.FontSizeChangeChangesTheMeasurement;
var a, b: Integer;
begin
  a := BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  b := BlockW(CAP, 'Arial', 24, 400, 96, 0, 0);
  AssertTrue(Format('block: a different size must re-measure (%d vs %d)', [a, b]), a <> b);

  a := TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 96);
  b := TyMeasureRenderedTextWidth(CAP, 'Arial', 24, 400, 96);
  AssertTrue(Format('rendered: a different size must re-measure (%d vs %d)', [a, b]), a <> b);
end;

procedure TMeasureCacheTest.FontWeightChangeChangesTheMeasurement;
{ 400 -> 700 is only 50 -> 52 here, and that narrowness is the point: the weight reaches
  the font solely through a >= 600 bold test, so this is the input most tempting to key on
  in a derived form. Two pixels are enough to fail an equality. }
var a, b: Integer;
begin
  a := BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  b := BlockW(CAP, 'Arial', 9, 700, 96, 0, 0);
  AssertTrue(Format('block: bold must re-measure (%d vs %d)', [a, b]), a <> b);

  a := TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 96);
  b := TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 700, 96);
  AssertTrue(Format('rendered: bold must re-measure (%d vs %d)', [a, b]), a <> b);
end;

procedure TMeasureCacheTest.PPIChangeChangesTheMeasurement;
{ The input the whole exercise exists for: a per-monitor DPI crossing re-measures every
  caption at the new PPI, and a memo that ignored PPI would hand every control its 96-dpi
  width at 240 dpi -- a form that scales its bounds and not its text. }
var a, b, c: Integer;
begin
  a := BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  b := BlockW(CAP, 'Arial', 9, 400, 144, 0, 0);
  c := BlockW(CAP, 'Arial', 9, 400, 240, 0, 0);
  AssertTrue(Format('96 vs 144 must differ (%d vs %d)', [a, b]), a <> b);
  AssertTrue(Format('144 vs 240 must differ (%d vs %d)', [b, c]), b <> c);
  AssertTrue('and they must GROW with PPI, not merely differ', (b > a) and (c > b));

  a := TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 96);
  b := TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 240);
  AssertTrue(Format('rendered: PPI must re-measure (%d vs %d)', [a, b]), b > a);
end;

procedure TMeasureCacheTest.WrapWidthChangeChangesTheMeasurement;
{ Block path only -- the rendered-width function neither wraps nor stacks, which is why
  its key carries 0 in both of those slots. }
var a, b: Integer;
begin
  a := BlockH('Measure Me Now Please', 'Arial', 9, 400, 96, 0, 0);
  b := BlockH('Measure Me Now Please', 'Arial', 9, 400, 96, 40, 0);
  AssertTrue(Format('wrapping to 40px must re-measure taller (%d vs %d)', [a, b]), b > a);
end;

procedure TMeasureCacheTest.LineHeightChangeChangesTheMeasurement;
{ --line-height is a THEME token (TyLineHeight(ActiveController)), so a skin that changes
  only its leading changes nothing else in the tuple. If it were missing from the key this
  is the one input whose staleness a font-identity argument would not catch. }
var a, b: Integer;
begin
  a := BlockH('Two'#13#10'Lines', 'Arial', 9, 400, 96, 0, 0);
  b := BlockH('Two'#13#10'Lines', 'Arial', 9, 400, 96, 0, 30);
  AssertTrue(Format('a themed line box must re-measure (%d vs %d)', [a, b]), a <> b);
end;

{ ===== staleness: the two mutable globals =================================== }

procedure TMeasureCacheTest.FallbackFontSizeChangeChangesTheMeasurement;
{ THE ONE THAT MATTERS MOST, because TyFallbackFontSize is rewritten from the theme's
  --font-size-base on EVERY theme apply (tyControls.Controller.pas:602). A control whose
  style rule omits font-size passes 0 down here, so the parameter is IDENTICAL across a
  theme switch and only the global moves. A key built from the raw parameter is therefore
  byte-identical before and after, hits, and hands back the old theme's width. That is
  the ellipsised-toolbar-button bug, arriving through a cache instead of through a stale
  Constraints floor. The key folds the fallback in; this asserts that it does. }
var a, b: Integer;
begin
  TyFallbackFontSize := 9;
  a := BlockW(CAP, 'Arial', 0, 400, 96, 0, 0);      // 0 = "the theme set no font-size"
  TyFallbackFontSize := 24;
  b := BlockW(CAP, 'Arial', 0, 400, 96, 0, 0);      // same arguments, different global
  AssertTrue(Format('block: the size fallback must re-measure (%d vs %d)', [a, b]), a <> b);

  TyInvalidateTextMeasureCache;
  TyFallbackFontSize := 9;
  a := TyMeasureRenderedTextWidth(CAP, 'Arial', 0, 400, 96);
  TyFallbackFontSize := 24;
  b := TyMeasureRenderedTextWidth(CAP, 'Arial', 0, 400, 96);
  AssertTrue(Format('rendered: the size fallback must re-measure (%d vs %d)', [a, b]), a <> b);
end;

procedure TMeasureCacheTest.FallbackFontNameChangeChangesTheMeasurement;
{ Same shape for the family: an empty AFontName means "the theme named no family", and
  what it resolves to is TyFallbackFontName, which the controller seeds from the real
  system font (tyControls.Controller.pas:210). Arial vs Times New Roman rather than Arial
  vs Courier New, for the reason given in FontFamilyChangeChangesTheMeasurement. }
var a, b: Integer;
begin
  TyFallbackFontName := 'Arial';
  a := BlockW(CAP, '', 9, 400, 96, 0, 0);
  TyFallbackFontName := 'Times New Roman';
  b := BlockW(CAP, '', 9, 400, 96, 0, 0);
  AssertTrue(Format('block: the family fallback must re-measure (%d vs %d)', [a, b]), a <> b);

  TyInvalidateTextMeasureCache;
  TyFallbackFontName := 'Arial';
  a := TyMeasureRenderedTextWidth(CAP, '', 9, 400, 96);
  TyFallbackFontName := 'Times New Roman';
  b := TyMeasureRenderedTextWidth(CAP, '', 9, 400, 96);
  AssertTrue(Format('rendered: the family fallback must re-measure (%d vs %d)', [a, b]), a <> b);
end;

{ ===== staleness through the real theme path ================================ }

procedure TMeasureCacheTest.ThemeChangeChangesTheMeasuredFontSize;
{ End to end, through a real controller and a real theme switch rather than by poking the
  global by hand: applying a theme rewrites TyFallbackFontSize from its --font-size-base,
  and a caption measured with NO explicit size must follow it.

  A LIMIT OF THIS TEST, stated because the next person will otherwise think it is stronger
  than it is: every theme this repo ships declares `--font-size-base: 9` (all five
  declarations of it in themes/ agree), so a genuine switch between two of them cannot
  currently move the measured number at all. What the switch really proves is the first
  assertion -- that an apply REWRITES the global, clobber and all. The second half then
  stands in for the first theme that disagrees, by writing the value a theme apply would
  have written. Replace the stand-in with a second theme name the day one differs.

  Note the two theme names must DIFFER: assigning the name it already has is a no-op and
  Changed never runs. An earlier draft of this test re-assigned 'breeze' to itself and
  failed for that reason, which is worth a line here because it fails LOOKING like the
  library forgot to sync. }
var
  c: TTyStyleController;
  a, b: Integer;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'breeze';
    a := BlockW(CAP, 'Arial', 0, 400, 96, 0, 0);
    { Clobber the global to a value no theme uses, so the assertion below cannot be
      satisfied by the value merely having been left there. }
    TyFallbackFontSize := 37;
    c.ThemeName := 'default';       // a DIFFERENT name -> Changed really runs
    AssertEquals('a theme apply rewrites the size fallback', 9, TyFallbackFontSize);

    TyFallbackFontSize := 24;       // stand in for a theme whose --font-size-base is 24
    b := BlockW(CAP, 'Arial', 0, 400, 96, 0, 0);
    AssertTrue(Format('the measurement must follow the theme (%d vs %d)', [a, b]), a <> b);
  finally
    c.Free;
  end;
end;

procedure TMeasureCacheTest.TyTextMeasureCacheDropsOnThemeChange;
{ Pins the WIRING in TTyStyleController.Changed, and it has to be asserted on the cache's
  ENTRY COUNT rather than on a measured value: the key already folds every theme-derived
  input, so a value assertion would stay green with the hook deleted and could never tell
  "dropped and recomputed" apart from "the key made it miss anyway". Counting entries can.
  The controller is created with no registered controls, so Changed's Invalidate broadcast
  cannot re-populate the cache behind this assertion. }
var
  c: TTyStyleController;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
    TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 96);
    AssertEquals('primed: both caches hold an entry', 2, Entries);

    c.ThemeName := 'breeze';        // -> TTyStyleController.Changed
    AssertEquals('a theme apply must drop every memoised measurement', 0, Entries);
  finally
    c.Free;
  end;
end;

{ ===== the key must be injective ============================================ }

procedure TMeasureCacheTest.FontNameAndCaptionCannotRunTogetherInTheKey;
{ The key ends with the font name followed by the caption. Concatenated naively, family
  'A' + caption 'BC' and family 'AB' + caption 'C' are the SAME string, and the second
  measurement would be served the first one's width -- two different questions collapsed
  onto one answer, which is memory/index-keyed-string-sort-trap in a different costume.
  The name is length-prefixed so they cannot collide. Neither family exists, so both fall
  back to the same face and the only thing left to differ is the caption -- which makes
  this a clean test of the KEY rather than of the font engine. }
var a, b: Integer;
begin
  a := BlockW('BC', 'A', 9, 400, 96, 0, 0);
  b := BlockW('C', 'AB', 9, 400, 96, 0, 0);
  AssertTrue(Format('block: name+caption must not run together (%d vs %d)', [a, b]), a <> b);

  a := TyMeasureRenderedTextWidth('BC', 'A', 9, 400, 96);
  b := TyMeasureRenderedTextWidth('C', 'AB', 9, 400, 96);
  AssertTrue(Format('rendered: name+caption must not run together (%d vs %d)', [a, b]), a <> b);
end;

{ ===== mechanics ============================================================ }

procedure TMeasureCacheTest.InvalidateEmptiesTheCache;
begin
  BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  TyMeasureRenderedTextWidth(CAP, 'Arial', 9, 400, 96);
  AssertEquals('two caches, one entry each', 2, Entries);
  TyInvalidateTextMeasureCache;
  AssertEquals('invalidate empties both', 0, Entries);
  { and the next identical call must really recompute, not report a hit on a dead entry }
  TyResetTextMeasureCacheStats;
  BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  AssertEquals('after invalidate the same call misses', 1, Misses);
  AssertEquals('and is not a hit', 0, Hits);
end;

procedure TMeasureCacheTest.CacheIsBoundedAndNeverGrowsWithoutLimit;
{ The key contains the CAPTION, so a caller measuring a stream of distinct strings -- a
  grid walking a text column is the realistic one -- would otherwise grow this for the
  life of the process. The cap is an implementation constant; what is asserted is the
  invariant, that the cache stays bounded well below the number of distinct keys fed to
  it, and that it still WORKS afterwards. }
var
  i, n: Integer;
begin
  n := 5000;
  for i := 1 to n do
    BlockW('cap probe ' + IntToStr(i), 'Arial', 9, 400, 96, 0, 0);
  AssertTrue(Format('%d distinct captions must not all be retained (kept %d)',
    [n, Entries]), Entries < n);
  AssertTrue('but the cache is not simply dead', Entries > 0);

  TyResetTextMeasureCacheStats;
  BlockW('after the cap', 'Arial', 9, 400, 96, 0, 0);
  BlockW('after the cap', 'Arial', 9, 400, 96, 0, 0);
  AssertEquals('a capped cache still serves repeats', 1, Hits);
end;

procedure TMeasureCacheTest.DisablingTheMemoStopsItCachingAndAnswersTheSame;
{ The off switch exists so the A/B in the plan could be run in ONE binary in one load
  window. It has to be genuinely inert: no entries, no counters, same answers. }
var a, b: Integer;
begin
  TyTextMeasureCacheEnabled := False;
  a := BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  b := BlockW(CAP, 'Arial', 9, 400, 96, 0, 0);
  AssertEquals('disabled: nothing is cached', 0, Entries);
  AssertEquals('disabled: no hits are counted', 0, Hits);
  AssertEquals('disabled: no misses are counted', 0, Misses);
  AssertEquals('disabled: the answer is stable', a, b);

  TyTextMeasureCacheEnabled := True;
  AssertEquals('enabling changes nothing about the answer', a,
    BlockW(CAP, 'Arial', 9, 400, 96, 0, 0));
end;

procedure TMeasureCacheTest.AReusedSurfaceNeverChangesAnAnswer;
var
  aloneA, aloneB, aloneC: Integer;
  rA, rB: Integer;
  i: Integer;
begin
  { THE SURFACE IS SHARED NOW. Both measurement functions used to allocate a 1x1
    scratch per call and free it; they keep one and reuse it, because an axis
    measures one string per LABEL and 5,000 categories cost fifteen seconds in
    those allocations alone.

    The comment that argued for per-call allocation said a kept surface "would
    carry the last caller's font across a theme switch". It cannot -- both
    functions assign every font property before measuring -- but that is an
    argument, and this is the test. MEMO OFF, so every call below really does
    land on the shared surface rather than being answered from the memo; then
    interleave three different configurations and demand each still measures
    what it measures alone.

    If any state survived from one call to the next, the interleaved answers
    would differ from the solo ones. Measuring each configuration only once
    would pass whether or not the surface was clean, which is the fake-green
    version of this test. }
  TyTextMeasureCacheEnabled := False;
  try
    aloneA := TyMeasureRenderedTextWidth('Wg', 'Arial', 13, 400, 96);
    aloneB := TyMeasureRenderedTextWidth('a much longer caption', 'Times New Roman',
                                         24, 700, 144);
    aloneC := BlockW('two' + LineEnding + 'lines', 'Arial', 9, 400, 96, 0, 0);

    AssertTrue('the three configurations really do differ', aloneA <> aloneB);

    for i := 1 to 3 do
    begin
      rA := TyMeasureRenderedTextWidth('Wg', 'Arial', 13, 400, 96);
      rB := TyMeasureRenderedTextWidth('a much longer caption', 'Times New Roman',
                                       24, 700, 144);
      AssertEquals('the small one is unchanged after the big one', aloneA, rA);
      AssertEquals('and the big one after the small one', aloneB, rB);
      AssertEquals('the block path too, interleaved with the rendered one',
        aloneC, BlockW('two' + LineEnding + 'lines', 'Arial', 9, 400, 96, 0, 0));
    end;

    { AND ACROSS AN INVALIDATION, which frees the surfaces: the next call has to
      rebuild one and get the same number, not zero and not a crash.

      This does NOT prove the freeing happens -- mutating it away leaves this
      test green, because the font is reassigned per call either way, so a kept
      surface answers identically. The freeing is there for item (10) of the
      enumeration at TyInvalidateTextMeasureCache: registering a font file
      changes what a name resolves to inside the process, and a live surface may
      hold a handle resolved before that. Nothing here registers a font, so
      there is no observable difference to assert; saying so is more honest than
      an assertion that would pass either way. }
    TyInvalidateTextMeasureCache;
    AssertEquals('a freed surface is rebuilt and measures the same', aloneA,
      TyMeasureRenderedTextWidth('Wg', 'Arial', 13, 400, 96));
    AssertEquals('the block one as well', aloneC,
      BlockW('two' + LineEnding + 'lines', 'Arial', 9, 400, 96, 0, 0));
  finally
    TyTextMeasureCacheEnabled := True;
  end;
end;

initialization
  RegisterTest(TMeasureCacheTest);
end.
