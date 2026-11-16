unit test.richedit.layoutdevice;

{ A text device for layout tests (tyControls.RichEdit.Layout): advances by character class, a
  fixed share of the pixel height, so a test can work out every position by hand; a glyph
  repertoire per font name that a test sets; and the device's call counters. The same on
  every platform. Drawing records what was drawn where and fills each glyph's box. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Generics.Collections, BGRABitmap, BGRABitmapTypes,
  tyControls.RichEdit.Layout;

type
  TTyRichTestDevice = class(TTyRichTextDevice)
  private
    FRepertoires: specialize TDictionary<string, TObject>;
    FDrawLog: TStringList;
  protected
    function DoMetrics(AFont: TTyRichFontId): TTyRichFontMetrics; override;
    function DoTextWidth(AFont: TTyRichFontId; const AText: UTF8String): Integer; override;
    function DoFitCount(AFont: TTyRichFontId; const AText: UTF8String;
      AMaxWidth: Integer): Integer; override;
    function DoHasGlyph(AFont: TTyRichFontId; ACode: Cardinal): Boolean; override;
    procedure DoDrawText(ATarget: TBGRABitmap; AFont: TTyRichFontId; AX, ABaseline: Integer;
      const AText: UTF8String; AColor: TBGRAPixel); override;
  public
    constructor Create;
    destructor Destroy; override;
    { AFontName (any case) has exactly the glyphs in ARanges, given as pairs (first, last);
      a font never given one has every glyph. }
    procedure SetRepertoire(const AFontName: string; const ARanges: array of Cardinal);
    { The advance of one code point at APx: a space a quarter, a CJK character, an emoji,
      U+FFFD and U+FFFC the whole, a mark that extends a cluster and a control character
      none, anything else half. Metrics: ascent four fifths, descent the rest, no leading. }
    class function Advance(ACode: Cardinal; APx: Integer): Integer;
    { "text|x|baseline" per DrawText call. }
    property DrawLog: TStringList read FDrawLog;
  end;

type
  TCardinalDynArray = array of Cardinal;

{ The code points of a UTF-8 string, one after another (an invalid byte is U+FFFD). }
function TestCodes(const S: UTF8String): TCardinalDynArray;

implementation

uses
  Math, tyControls.Painter;

type
  TRanges = class
    Pairs: array of Cardinal;
  end;

function TestCodes(const S: UTF8String): TCardinalDynArray;
var
  i, n, len: Integer;
  b: Byte;
  c: Cardinal;
begin
  Result := nil;
  SetLength(Result, Length(S));
  n := 0;
  i := 1;
  while i <= Length(S) do
  begin
    b := Byte(S[i]);
    if b < $80 then
    begin
      c := b;
      len := 1;
    end
    else if (b >= $C2) and (b < $E0) and (i + 1 <= Length(S)) then
    begin
      c := (Cardinal(b and $1F) shl 6) or (Byte(S[i + 1]) and $3F);
      len := 2;
    end
    else if (b >= $E0) and (b < $F0) and (i + 2 <= Length(S)) then
    begin
      c := (Cardinal(b and $0F) shl 12) or (Cardinal(Byte(S[i + 1]) and $3F) shl 6) or
        (Byte(S[i + 2]) and $3F);
      len := 3;
    end
    else if (b >= $F0) and (b < $F5) and (i + 3 <= Length(S)) then
    begin
      c := (Cardinal(b and $07) shl 18) or (Cardinal(Byte(S[i + 1]) and $3F) shl 12) or
        (Cardinal(Byte(S[i + 2]) and $3F) shl 6) or (Byte(S[i + 3]) and $3F);
      len := 4;
    end
    else
    begin
      c := $FFFD;
      len := 1;
    end;
    Result[n] := c;
    Inc(n);
    Inc(i, len);
  end;
  SetLength(Result, n);
end;

constructor TTyRichTestDevice.Create;
begin
  inherited Create;
  FRepertoires := specialize TDictionary<string, TObject>.Create;
  FDrawLog := TStringList.Create;
end;

destructor TTyRichTestDevice.Destroy;
var
  o: TObject;
begin
  for o in FRepertoires.Values do o.Free;
  FRepertoires.Free;
  FDrawLog.Free;
  inherited Destroy;
end;

procedure TTyRichTestDevice.SetRepertoire(const AFontName: string;
  const ARanges: array of Cardinal);
var
  r: TRanges;
  o: TObject;
  i: Integer;
begin
  if FRepertoires.TryGetValue(LowerCase(AFontName), o) then
  begin
    o.Free;
    FRepertoires.Remove(LowerCase(AFontName));
  end;
  r := TRanges.Create;
  SetLength(r.Pairs, Length(ARanges));
  for i := 0 to High(ARanges) do r.Pairs[i] := ARanges[i];
  FRepertoires.Add(LowerCase(AFontName), r);
end;

class function TTyRichTestDevice.Advance(ACode: Cardinal; APx: Integer): Integer;
begin
  if ACode = $20 then Exit(Max(1, APx div 4));
  if ACode < $20 then Exit(0);
  if TyRichIsClusterExtend(ACode) then Exit(0);
  if TyIsCJKCodepoint(ACode) or (ACode >= $1F000) or (ACode = $FFFD) or (ACode = $FFFC) or
    ((ACode >= $2600) and (ACode <= $27BF)) then
    Exit(APx);
  Result := Max(1, APx div 2);
end;

function TTyRichTestDevice.DoMetrics(AFont: TTyRichFontId): TTyRichFontMetrics;
var
  px: Integer;
begin
  px := FontPixelHeight(AFont);
  Result.Ascent := px * 4 div 5;
  Result.Descent := px - Result.Ascent;
  Result.Leading := 0;
end;

function TTyRichTestDevice.DoTextWidth(AFont: TTyRichFontId; const AText: UTF8String): Integer;
var
  codes: TCardinalDynArray;
  i, px: Integer;
begin
  px := FontPixelHeight(AFont);
  codes := TestCodes(AText);
  Result := 0;
  for i := 0 to High(codes) do Inc(Result, Advance(codes[i], px));
end;

function TTyRichTestDevice.DoFitCount(AFont: TTyRichFontId; const AText: UTF8String;
  AMaxWidth: Integer): Integer;
var
  codes: TCardinalDynArray;
  i, px, w: Integer;
begin
  px := FontPixelHeight(AFont);
  codes := TestCodes(AText);
  CountMeasure(Length(codes));
  w := 0;
  Result := 0;
  for i := 0 to High(codes) do
  begin
    Inc(w, Advance(codes[i], px));
    if w > AMaxWidth then Exit;
    Result := i + 1;
  end;
end;

function TTyRichTestDevice.DoHasGlyph(AFont: TTyRichFontId; ACode: Cardinal): Boolean;
var
  o: TObject;
  r: TRanges;
  i: Integer;
begin
  if not FRepertoires.TryGetValue(LowerCase(FontName(AFont)), o) then Exit(True);
  r := TRanges(o);
  i := 0;
  while i + 1 <= High(r.Pairs) do
  begin
    if (ACode >= r.Pairs[i]) and (ACode <= r.Pairs[i + 1]) then Exit(True);
    Inc(i, 2);
  end;
  Result := False;
end;

procedure TTyRichTestDevice.DoDrawText(ATarget: TBGRABitmap; AFont: TTyRichFontId;
  AX, ABaseline: Integer; const AText: UTF8String; AColor: TBGRAPixel);
var
  codes: TCardinalDynArray;
  i, px, x, w: Integer;
  m: TTyRichFontMetrics;
begin
  FDrawLog.Add(AText + '|' + IntToStr(AX) + '|' + IntToStr(ABaseline));
  if ATarget = nil then Exit;
  px := FontPixelHeight(AFont);
  m := Metrics(AFont);
  codes := TestCodes(AText);
  x := AX;
  for i := 0 to High(codes) do
  begin
    w := Advance(codes[i], px);
    if (w > 1) and (codes[i] <> $20) then
      ATarget.FillRect(x + 1, ABaseline - m.Ascent + 1, x + w - 1, ABaseline + m.Descent - 1,
        AColor, dmSet);
    Inc(x, w);
  end;
end;

end.
