unit tyControls.AdvChart.Pictorial;
{$mode objfpc}{$H+}
{ The pictorial bar's own options, and the arithmetic they come to.

  A PICTORIAL BAR IS A BAR WHOSE RECTANGLE IS NEVER DRAWN. It shares the whole
  bar layout -- the same band, the same column, the same offset -- and then
  replaces the rectangle with a glyph, or with a column of glyphs, sized and
  placed by five options that only make sense together.

  FOUR RECTANGLES, and a port that collapses any two of them is wrong:

    the VALUE rect     what the bar layout produced. Never painted.
    the BOUNDING length a SIGNED pixel scalar that replaces the value rect's
                       length for SIZING and ANCHORING the glyph. It is the
                       value rect's length unless `symbolBoundingData` or
                       `symbolRepeat` says otherwise.
    the BAR rect       the union of the value rect and the far end of the
                       glyph run. It is transparent and exists so an outside
                       label clears the icon rather than the data value -- and
                       so the pointer has something honest to land on.
    the CLIP rect      the base line to the real value. Repeat draws the whole
                       column at bounding size and this reveals the part the
                       data paid for.

  THE ARITHMETIC THAT DECIDES A REPEAT IS TWO PASSES AND THE SECOND ONE MOVES
  THE FIRST'S ANSWER. A count is guessed from the bounding length, then the
  margin is RE-SOLVED so that guessed count spans the bounding length exactly
  -- which can make the margin negative, and overlapping glyphs are the
  intended result rather than a fault. Only after that is the count cut down
  to the data's own length.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Data,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Color;

const
  TyPictorialSeriesTypeName = 'pictorialBar';

type
  { Where the glyph sits along the bounding length. `null` upstream, and the
    comment beside it says "auto"; there is no auto, the read is
    `get('symbolPosition') || 'start'`. }
  TTyPictorialPosition = (pspStart, pspEnd, pspCentre);

  { `symbolRepeat` is four things wearing one name.

      prNone      false, 0, '' and null -- one glyph.
      prAuto      true -- as many as fit the BOUNDING length, then cut down to
                  the data's own length.
      prFixedAuto 'fixed' -- as many as fit the bounding length, NOT cut. The
                  column always looks full and the data shows through the clip.
      prCount     a number, or a string holding one -- exactly that many, not
                  cut, and the margin option's VALUE is then dead. }
  TTyPictorialRepeat = (prNone, prAuto, prFixedAuto, prCount);

  TTyPictorialSpec = record
    { Empty means the series did not say, and the caller's own default -- a
      circle -- stands. }
    SymbolName: string;
    { `symbolSize` in either form. The percent BASES are not the same on the
      two axes and not the same with repeat on: across the bar it is always
      the column's own width; along it, the bounding length, or the column
      width again when repeating. }
    SizeW, SizeH: TTyBoxValue;
    HasSize: Boolean;
    RotateDeg: Double;
    Position: TTyPictorialPosition;
    OffsetX, OffsetY: TTyBoxValue;
    HasOffset: Boolean;
    { `symbolMargin`, split into the two things it carries. The value is a box
      value because `'15%'` is a percentage of the glyph's own length along
      the bar; the flag is the trailing `!`, which asks for a gap at the two
      ENDS as well as between. }
    Margin: TTyBoxValue;
    MarginEndGap: Boolean;
    Repeat_: TTyPictorialRepeat;
    RepeatCount: Double;
    RepeatFromStart: Boolean;
    Clip: Boolean;
    { `symbolBoundingData`: absent, one number, or a pair. A pair is sorted and
      then the end matching the bar's own direction is taken. }
    BoundHas: Integer;          { 0, 1 or 2 }
    BoundA, BoundB: Double;
    KeepAspect: Boolean;
  end;

  { What a repeat comes to, in device px along the bar. }
  TTyPictorialRun = record
    { How many glyphs. Never negative, and capped -- upstream has no cap at
      all and will happily be asked for a hundred million. }
    Count: Integer;
    { The gap on EACH side of a glyph, which may be negative: the second pass
      re-solves it so the count spans the bounding length exactly, and a count
      that had to be rounded up can only fit by overlapping. }
    Margin: Double;
    { One glyph plus its two margins. }
    Unit_: Double;
    { The whole run, ends trimmed unless the margin asked for end gaps. }
    PathLen: Double;
  end;

function TyPictorialSpecDefault: TTyPictorialSpec;
function TyPictorialSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyPictorialSpec;

{ ASpec with whatever ONE ROW wrote of its own laid over it.

  EVERY ONE OF THESE OPTIONS IS PER-DATUM UPSTREAM, and not as a courtesy: the
  view reads all of them through the item model, which is what lets one series
  draw a different icon for every row. That is how half the gallery's pictorial
  charts are written -- `data: [{ value: 123, symbol: 'path://...' }]` -- and a
  port that read only the series level draws the same circle nine times and
  looks like it lost the option rather than the row.

  ONLY THE SCALAR FORMS ARRIVE HERE. The store parks scalar leaves under their
  dotted path and skips arrays, so a row's `symbolSize: [10, 20]` is not
  readable and keeps the series'. Said out loud rather than left as a silent
  gap: the pair form on a ROW is genuinely unsupported, not merely untested. }
function TyPictorialRowSpec(const ASpec: TTyPictorialSpec;
  AStore: TTyDataStore; ARow: Integer): TTyPictorialSpec;

{ upstream's toIntTimes: round when within a ten-thousandth, otherwise CEIL.

  BOTH BRANCHES, transcribed. Replacing the pair with one Round or one Trunc
  changes the glyph count by one on every inexact fit, which is every bar
  anybody actually draws. And the input is a ratio that can be infinite or not
  a number, so the rounding has to be guarded -- Round targets Int64 here and
  raises outside it, where JavaScript just carries the infinity along. }
function TyPictorialTimes(AValue: Double): Integer;

{ The whole repeat, in upstream's own order and with its own second pass.

  AGlyphLen is one glyph's length along the bar plus its stroke; ABoundingLen
  is the SIGNED bounding length; ACutLen is the data's own signed length, which
  only `prAuto` consults. }
function TyPictorialRunOf(const ASpec: TTyPictorialSpec;
  AGlyphLen, ABoundingLen, ACutLen, AMarginBase: Double): TTyPictorialRun;

{ The centre of glyph AIndex along the bar, measured from the run's own anchor.

  A SLOT IS NOT A CREATION ORDER. `symbolRepeatDirection` swaps which end is
  drawn first, and upstream is explicit that this changes stacking and
  animation order only -- the same pixels are occupied either way. }
function TyPictorialSlot(const ARun: TTyPictorialRun; AIndex: Integer;
  AAnchor: Double): Double;

implementation

function TyPictorialSpecDefault: TTyPictorialSpec;
begin
  Result := Default(TTyPictorialSpec);
  { PictorialBarSeries.ts:142-153. }
  Result.SymbolName := '';
  Result.SizeW := TyBoxPercent(100);
  Result.SizeH := TyBoxPercent(100);
  Result.HasSize := False;
  Result.RotateDeg := 0;
  Result.Position := pspStart;
  Result.OffsetX := TyBoxPx(0);
  Result.OffsetY := TyBoxPx(0);
  Result.HasOffset := False;
  Result.Margin := TyBoxPercent(15);
  Result.MarginEndGap := False;
  Result.Repeat_ := prNone;
  Result.RepeatCount := 0;
  { `symbolRepeatDirection: 'end'`, and the word is compared against 'start'
    alone -- every other value, typo included, behaves as 'end'. }
  Result.RepeatFromStart := False;
  Result.Clip := False;
  Result.BoundHas := 0;
  Result.KeepAspect := False;
end;

{ A plain number out of a string, decimal point regardless of the locale. }
function NumOf(const AText: string; out AValue: Double): Boolean;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := TryStrToFloat(Trim(AText), AValue, fs);
end;

function NumToStr(AValue: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  fs.ThousandSeparator := #0;
  Result := FloatToStr(AValue, fs);
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function StrIn(ANode: TJSONObject; const AKey: string;
  const ADefault: string): string;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function TyPictorialSpecOf(AOption: TTyChartOption;
  ASlot: Integer): TTyPictorialSpec;
var
  node: TJSONObject;
  d: TJSONData;
  a: TJSONArray;
  s: string;
  v: Double;
begin
  Result := TyPictorialSpecDefault;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if not (d is TJSONObject) then Exit;
  node := TJSONObject(d);

  Result.SymbolName := StrIn(node, 'symbol', '');

  d := node.Find('symbolSize');
  if d <> nil then
  begin
    Result.HasSize := True;
    if d.JSONType = jtArray then
    begin
      a := TJSONArray(d);
      if a.Count > 0 then Result.SizeW := TyBoxDataOf(a.Items[0], Result.SizeW);
      if a.Count > 1 then Result.SizeH := TyBoxDataOf(a.Items[1], Result.SizeH);
    end
    else
    begin
      Result.SizeW := TyBoxDataOf(d, Result.SizeW);
      Result.SizeH := Result.SizeW;
    end;
  end;

  { CLAMPED BEFORE IT IS MULTIPLIED. A rotation of 1e308 degrees times Pi/180
    overflows, and the infinity reaches every coordinate of the glyph. }
  v := NumIn(node, 'symbolRotate', 0);
  if IsNan(v) then v := 0;
  Result.RotateDeg := Max(Double(-360), Min(Double(360), v));

  { THREE WORDS AND A CATCH-ALL, and the catch-all is NOT the default.
    The read is `get('symbolPosition') || 'start'` and the branch that
    follows tests for 'start' and then for 'end', so an absent value is
    `start` while a MISSPELLED one -- 'centre', 'middle', a typo -- lands on
    the final arm and centres the glyph. Two different answers for two
    different kinds of nothing, and collapsing them moves every misspelled
    glyph to the baseline. }
  s := StrIn(node, 'symbolPosition', '');
  if (s = '') or (s = 'start') then Result.Position := pspStart
  else if s = 'end' then Result.Position := pspEnd
  else Result.Position := pspCentre;

  d := node.Find('symbolOffset');
  if d <> nil then
  begin
    Result.HasOffset := True;
    if d.JSONType = jtArray then
    begin
      a := TJSONArray(d);
      if a.Count > 0 then Result.OffsetX := TyBoxDataOf(a.Items[0], Result.OffsetX);
      { A ONE-ELEMENT ARRAY FALLS BACK TO ITS OWN FIRST ELEMENT, not to zero:
        normalizeSymbolOffset reads the second through retrieve2(off[1],
        off[0]). So `symbolOffset: [10]` moves the glyph ten px BOTH ways. }
      if a.Count > 1 then Result.OffsetY := TyBoxDataOf(a.Items[1], Result.OffsetY)
      else if a.Count = 1 then Result.OffsetY := Result.OffsetX;
    end
    else
    begin
      Result.OffsetX := TyBoxDataOf(d, Result.OffsetX);
      Result.OffsetY := Result.OffsetX;
    end;
  end;

  d := node.Find('symbolMargin');
  if d <> nil then
  begin
    { STRINGIFIED FIRST, upstream, so even a number goes through the string
      parser -- which is why `'20px'` reads as twenty and `'10,20'` as ten. }
    if d.JSONType = jtNumber then s := NumToStr(d.AsFloat)
    else if d.JSONType = jtString then s := d.AsString
    else s := '';
    if s <> '' then
    begin
      { ONE trailing `!`, and the test is on the LAST character rather than a
        suffix search -- so `'10!%'` is not an end gap and `'10%!!'` strips
        one. }
      if s[Length(s)] = '!' then
      begin
        Result.MarginEndGap := True;
        s := Copy(s, 1, Length(s) - 1);
      end;
      Result.Margin := TyBoxStrOf(s, Result.Margin);
    end;
  end;

  d := node.Find('symbolRepeat');
  if d <> nil then
  begin
    case d.JSONType of
      jtBoolean:
        if d.AsBoolean then Result.Repeat_ := prAuto;
      jtNumber:
        begin
          Result.Repeat_ := prCount;
          Result.RepeatCount := d.AsFloat;
        end;
      jtString:
        begin
          s := Trim(d.AsString);
          if s = 'fixed' then Result.Repeat_ := prFixedAuto
          else if NumOf(s, v) then
          begin
            { A NUMBER IN QUOTES IS A NUMBER HERE. Upstream's test is
              `isNumeric`, which takes the string and then does arithmetic on
              it -- so `'5'` really does mean five glyphs. }
            Result.Repeat_ := prCount;
            Result.RepeatCount := v;
          end;
        end;
    end;
  end;

  Result.RepeatFromStart := StrIn(node, 'symbolRepeatDirection', 'end') = 'start';

  d := node.Find('symbolClip');
  if (d <> nil) and (d.JSONType = jtBoolean) then Result.Clip := d.AsBoolean;

  d := node.Find('symbolBoundingData');
  if d <> nil then
  begin
    if d.JSONType = jtNumber then
    begin
      Result.BoundHas := 1;
      Result.BoundA := d.AsFloat;
    end
    else if d.JSONType = jtArray then
    begin
      a := TJSONArray(d);
      if (a.Count > 1) and (a.Items[0].JSONType = jtNumber)
        and (a.Items[1].JSONType = jtNumber) then
      begin
        Result.BoundHas := 2;
        Result.BoundA := a.Items[0].AsFloat;
        Result.BoundB := a.Items[1].AsFloat;
        { SORTED, and upstream sorts it too -- the pair names an interval, not
          an order. A one-element array is NOT accepted here: upstream reads
          element one anyway and gets NaN, which poisons every coordinate. }
        if Result.BoundB < Result.BoundA then
        begin
          v := Result.BoundA;
          Result.BoundA := Result.BoundB;
          Result.BoundB := v;
        end;
      end;
    end;
  end;

  d := node.Find('symbolKeepAspect');
  if (d <> nil) and (d.JSONType = jtBoolean) then Result.KeepAspect := d.AsBoolean;
end;

{ One row's scalar leaf, as text -- '' when the row did not write that key.

  A NUMBER COMES BACK AS TEXT TOO, which is deliberate: every one of these
  options is read through a string parser upstream anyway (symbolMargin
  literally stringifies first), so one spelling here is one branch there. }
function RowText(AStore: TTyDataStore; ARow, AKey: Integer): string;
var v: TTyDataValue;
begin
  Result := '';
  if AStore = nil then Exit;
  if not AStore.HasOverride(ARow, AKey) then Exit;
  v := AStore.GetOverride(ARow, AKey);
  case v.Kind of
    dvkText: Result := v.Text;
    dvkNumber: Result := NumToStr(v.Num);
    dvkBool: if v.Num <> 0 then Result := 'true' else Result := 'false';
  end;
end;

function TyPictorialRowSpec(const ASpec: TTyPictorialSpec;
  AStore: TTyDataStore; ARow: Integer): TTyPictorialSpec;
var
  s: string;
  v: Double;
begin
  Result := ASpec;
  if AStore = nil then Exit;

  s := RowText(AStore, ARow, TyOverrideKey('symbol'));
  if s <> '' then Result.SymbolName := s;

  s := RowText(AStore, ARow, TyOverrideKey('symbolSize'));
  if s <> '' then
  begin
    Result.HasSize := True;
    Result.SizeW := TyBoxStrOf(s, Result.SizeW);
    Result.SizeH := Result.SizeW;
  end;

  s := RowText(AStore, ARow, TyOverrideKey('symbolRotate'));
  if (s <> '') and NumOf(s, v) and not IsNan(v) then
    Result.RotateDeg := Max(Double(-360), Min(Double(360), v));

  s := RowText(AStore, ARow, TyOverrideKey('symbolPosition'));
  if s <> '' then
  begin
    if s = 'start' then Result.Position := pspStart
    else if s = 'end' then Result.Position := pspEnd
    else Result.Position := pspCentre;
  end;

  s := RowText(AStore, ARow, TyOverrideKey('symbolOffset'));
  if s <> '' then
  begin
    Result.HasOffset := True;
    Result.OffsetX := TyBoxStrOf(s, Result.OffsetX);
    Result.OffsetY := Result.OffsetX;
  end;

  s := RowText(AStore, ARow, TyOverrideKey('symbolMargin'));
  if s <> '' then
  begin
    Result.MarginEndGap := False;
    if s[Length(s)] = '!' then
    begin
      Result.MarginEndGap := True;
      s := Copy(s, 1, Length(s) - 1);
    end;
    if s <> '' then Result.Margin := TyBoxStrOf(s, Result.Margin);
  end;

  s := RowText(AStore, ARow, TyOverrideKey('symbolRepeat'));
  if s <> '' then
  begin
    if s = 'true' then Result.Repeat_ := prAuto
    else if s = 'false' then Result.Repeat_ := prNone
    else if s = 'fixed' then Result.Repeat_ := prFixedAuto
    else if NumOf(s, v) then
    begin
      Result.Repeat_ := prCount;
      Result.RepeatCount := v;
    end;
  end;

  s := RowText(AStore, ARow, TyOverrideKey('symbolRepeatDirection'));
  if s <> '' then Result.RepeatFromStart := s = 'start';

  s := RowText(AStore, ARow, TyOverrideKey('symbolClip'));
  if s <> '' then Result.Clip := s = 'true';

  s := RowText(AStore, ARow, TyOverrideKey('symbolKeepAspect'));
  if s <> '' then Result.KeepAspect := s = 'true';

  { A ROW CAN ONLY SAY ONE NUMBER, because a pair is an array and an array is
    not parked. The one number is the whole bounding data, which is the form
    the option reference gives first anyway. }
  s := RowText(AStore, ARow, TyOverrideKey('symbolBoundingData'));
  if (s <> '') and NumOf(s, v) then
  begin
    Result.BoundHas := 1;
    Result.BoundA := v;
  end;
end;

function TyPictorialTimes(AValue: Double): Integer;
var r: Double;
begin
  { GUARDED BEFORE EITHER ROUNDING. The ratio handed in is a division by a
    length the author controls, so infinity and not-a-number are both ordinary
    -- and both of the roundings below target an Int64 and raise outside it. }
  if IsNan(AValue) or IsInfinite(AValue) or (AValue <= 0) then Exit(0);
  if AValue > 100000 then Exit(100000);
  r := Round(AValue);
  if Abs(AValue - r) < 1e-4 then Result := Trunc(r)
  else Result := Trunc(Ceil(AValue));
end;

function TyPictorialRunOf(const ASpec: TTyPictorialSpec;
  AGlyphLen, ABoundingLen, ACutLen, AMarginBase: Double): TTyPictorialRun;
var
  absBound, margin, uLen, endFix, mDiff, divisor: Double;
  n: Integer;
begin
  Result := Default(TTyPictorialRun);
  Result.Unit_ := Max(Double(0), AGlyphLen);
  Result.PathLen := Result.Unit_;
  Result.Count := 1;
  if ASpec.Repeat_ = prNone then Exit;

  absBound := Abs(ABoundingLen);
  margin := TyBoxResolve(ASpec.Margin, AMarginBase);
  if IsNan(margin) or IsInfinite(margin) then margin := 0;
  uLen := Max(Double(0), Result.Unit_ + margin * 2);
  if ASpec.MarginEndGap then endFix := 0 else endFix := margin * 2;

  { PASS ONE: how many fit. A written count skips it outright, and with it the
    margin's VALUE -- only the end-gap flag survives a written count. }
  if ASpec.Repeat_ = prCount then
    n := TyPictorialTimes(ASpec.RepeatCount)
  else if uLen > 0 then
    n := TyPictorialTimes((absBound + endFix) / uLen)
  else
    n := 0;

  { PASS TWO: the margin is re-solved so that count spans the bounding length
    EXACTLY. It can come out negative, and overlapping glyphs are the answer
    upstream gives rather than a fault -- a count that had to be rounded up
    has no other way to fit. }
  if n > 0 then
  begin
    mDiff := absBound - n * Result.Unit_;
    if ASpec.MarginEndGap then divisor := n else divisor := Max(n - 1, 1);
    if divisor <> 0 then margin := mDiff / 2 / divisor else margin := 0;
    uLen := Result.Unit_ + margin * 2;
    if ASpec.MarginEndGap then endFix := 0 else endFix := margin * 2;
  end;

  { PASS THREE, and only `true` takes it: the count is cut down to what the
    DATA paid for. `'fixed'` and a written count both keep the full column and
    let the clip show how much of it the data earned. }
  if ASpec.Repeat_ = prAuto then
  begin
    if (ACutLen = 0) or (uLen <= 0) then
      n := 0
    else
      n := TyPictorialTimes((Abs(ACutLen) + endFix) / uLen);
  end;

  Result.Count := n;
  Result.Margin := margin;
  Result.Unit_ := uLen;
  Result.PathLen := n * uLen - endFix;
end;

function TyPictorialSlot(const ARun: TTyPictorialRun; AIndex: Integer;
  AAnchor: Double): Double;
begin
  { REAL DIVISION, not integer: an odd count shifts the whole run by half a
    glyph if this is done with `div`. And the halves are written as Doubles
    because an Integer beside a bare 0.5 evaluates in Single here. }
  Result := ARun.Unit_ * (AIndex - ARun.Count / Double(2) + Double(0.5))
            + AAnchor;
end;

end.
