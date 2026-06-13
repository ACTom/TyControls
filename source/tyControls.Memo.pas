unit tyControls.Memo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  // Cumulative-prefix pixel widths, length = codepoints+1 (shared name with Edit).
  TTyIntArray = array of Integer;

  TTyMemo = class(TTyCustomControl)
  private
    // Logical text model: one TStrings line per logical line. Exposed (read-only
    // direction) via the published Lines:TStrings; writes go through SetLines.
    FLines: TStringList;
    // 2D caret. FCaretLine in 0..LineCountLogical-1; FCaretCol is a codepoint
    // index in 0..UTF8Length(line). FDesiredCol remembers the column for
    // vertical motion across short lines (used by later tasks).
    FCaretLine: Integer;
    FCaretCol: Integer;
    FDesiredCol: Integer;
    // Lazy measuring bitmap (freed in Destroy). Shared by all per-line measures.
    FMeasureBmp: TBGRABitmap;
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    function EffectiveFontSize(const S: TTyStyleSet): Integer;
    function TextStartX(APPI: Integer): Integer;
  protected
    function GetStyleTypeKey: string; override;
    // --- Pure per-line geometry helpers (headless-testable; no paint state) ---
    // Floored at 1 so vertical layout never divides by zero.
    function LineHeight(APPI: Integer): Integer;
    // Always >= 1 (an empty model is one logical, visually present line).
    function LineCountLogical: Integer;
    // Clamp the caret into the current model (line then col).
    procedure ClampCaret;
    // Cumulative prefix widths for ALine, measured on the shared BGRA bitmap so
    // measurement matches drawing (lifted from TTyEdit.MeasureCodepointWidths,
    // generalised to take the line as a parameter — no per-line cache).
    function MeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
    // Pixel x of the caret boundary before codepoint ACol on ALine.
    function ColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
    // Nearest codepoint boundary to device-x AX on ALine (midpoint rule).
    function ColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
    // Caret read/write for tests and later tasks.
    function CaretLine: Integer;
    function CaretCol: Integer;
    procedure SetCaret(ALine, ACol: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Lines: TStrings read GetLines write SetLines;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;

implementation

constructor TTyMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FLines := TStringList.Create;
  FCaretLine := 0;
  FCaretCol := 0;
  FDesiredCol := 0;
  FMeasureBmp := nil;
  Width := 200;
  Height := 120;
end;

destructor TTyMemo.Destroy;
begin
  FMeasureBmp.Free;
  FLines.Free;
  inherited Destroy;
end;

function TTyMemo.GetStyleTypeKey: string;
begin
  Result := 'TyMemo';
end;

function TTyMemo.GetLines: TStrings;
begin
  Result := FLines;
end;

procedure TTyMemo.SetLines(AValue: TStrings);
begin
  FLines.Assign(AValue);
  ClampCaret;
  Invalidate;
end;

function TTyMemo.LineCountLogical: Integer;
begin
  // An empty model is still one visible line (caret can sit on line 0).
  Result := FLines.Count;
  if Result < 1 then
    Result := 1;
end;

procedure TTyMemo.ClampCaret;
var
  MaxLine, LineLen: Integer;
begin
  MaxLine := LineCountLogical - 1;
  if FCaretLine < 0 then FCaretLine := 0;
  if FCaretLine > MaxLine then FCaretLine := MaxLine;
  // Length of the caret's line in codepoints (0 for the synthetic empty line).
  if FCaretLine < FLines.Count then
    LineLen := UTF8Length(FLines[FCaretLine])
  else
    LineLen := 0;
  if FCaretCol < 0 then FCaretCol := 0;
  if FCaretCol > LineLen then FCaretCol := LineLen;
  if FDesiredCol < 0 then FDesiredCol := 0;
end;

function TTyMemo.CaretLine: Integer;
begin
  Result := FCaretLine;
end;

function TTyMemo.CaretCol: Integer;
begin
  Result := FCaretCol;
end;

procedure TTyMemo.SetCaret(ALine, ACol: Integer);
begin
  FCaretLine := ALine;
  FCaretCol := ACol;
  ClampCaret;
  FDesiredCol := FCaretCol;
  Invalidate;
end;

function TTyMemo.EffectiveFontSize(const S: TTyStyleSet): Integer;
begin
  // Verbatim from TTyEdit.EffectiveFontSize.
  if S.FontSize > 0 then
    Result := S.FontSize
  else
    Result := 12;  // fallback 12pt
end;

function TTyMemo.TextStartX(APPI: Integer): Integer;
var
  S: TTyStyleSet;
begin
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Left, APPI, 96);
end;

function TTyMemo.LineHeight(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  EffSize: Integer;
begin
  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  if FMeasureBmp = nil then
    FMeasureBmp := TBGRABitmap.Create(1, 1);
  // Configure exactly as TTyPainter.DrawText so the measured cell height matches
  // what is drawn (same BGRA engine + height semantics as TTyEdit's fix).
  TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
  // 'Ag' spans an ascender and a descender — a stable single-line cell height.
  Result := FMeasureBmp.TextSize('Ag').cy;
  if Result < 1 then
    Result := 1;
end;

function TTyMemo.MeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
// Cumulative prefix x positions (px), length = UTF8Length(ALine)+1, measured on
// the shared lazy bitmap. Lifted from TTyEdit.MeasureCodepointWidths; takes the
// line as a parameter and does NOT cache (per-line caching is a later concern).
var
  S: TTyStyleSet;
  EffSize: Integer;
  i, Len: Integer;
begin
  Result := nil;
  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  Len := UTF8Length(ALine);
  SetLength(Result, Len + 1);
  Result[0] := 0;
  if Len > 0 then
  begin
    if FMeasureBmp = nil then
      FMeasureBmp := TBGRABitmap.Create(1, 1);
    TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
    // PREFIX measurement captures inter-glyph kerning/hinting as drawn.
    for i := 1 to Len do
      Result[i] := FMeasureBmp.TextSize(UTF8Copy(ALine, 1, i)).cx;
  end;
end;

function TTyMemo.ColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
var
  Widths: TTyIntArray;
  Len: Integer;
begin
  Len := UTF8Length(ALine);
  if ACol < 0 then ACol := 0;
  if ACol > Len then ACol := Len;
  Result := TextStartX(APPI);
  if Len = 0 then
    Exit;
  Widths := MeasureLineWidths(ALine, APPI);
  Result := Result + Widths[ACol];
end;

function TTyMemo.ColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
// Midpoint-nearest codepoint boundary (lifted from TTyEdit.CaretIndexAtX,
// without horizontal-scroll handling — that belongs to the painting task).
var
  Widths: TTyIntArray;
  StartX, RelX, Len, i, MidPoint: Integer;
begin
  StartX := TextStartX(APPI);
  RelX := AX - StartX;
  Len := UTF8Length(ALine);
  if RelX <= 0 then
    Exit(0);
  Widths := MeasureLineWidths(ALine, APPI);
  if RelX >= Widths[Len] then
    Exit(Len);
  Result := 0;
  for i := 0 to Len - 1 do
  begin
    MidPoint := (Widths[i] + Widths[i + 1]) div 2;
    if RelX <= MidPoint then
      Exit(i);
    Result := i + 1;
  end;
end;

end.
