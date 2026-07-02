unit tyControls.Dialogs.Font;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics;
type
  TTyFontChecks = record Bold, Italic, Underline, Strikeout: Boolean; end;
function TyFontStyleToChecks(AStyle: TFontStyles): TTyFontChecks;
function TyChecksToFontStyle(const AChecks: TTyFontChecks): TFontStyles;
implementation
function TyFontStyleToChecks(AStyle: TFontStyles): TTyFontChecks;
begin
  Result.Bold := fsBold in AStyle;
  Result.Italic := fsItalic in AStyle;
  Result.Underline := fsUnderline in AStyle;
  Result.Strikeout := fsStrikeOut in AStyle;
end;
function TyChecksToFontStyle(const AChecks: TTyFontChecks): TFontStyles;
begin
  Result := [];
  if AChecks.Bold then Include(Result, fsBold);
  if AChecks.Italic then Include(Result, fsItalic);
  if AChecks.Underline then Include(Result, fsUnderline);
  if AChecks.Strikeout then Include(Result, fsStrikeOut);
end;
end.
