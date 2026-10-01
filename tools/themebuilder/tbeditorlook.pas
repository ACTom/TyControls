unit tbeditorlook;
{ The editor's colours come from the TOOL's theme (the one "View > Editor appearance"
  picks), never from the theme being edited, and never written into the code: SynEdit is the
  one control here that is not a Ty control, so its colours are read off the controller's
  tokens and pushed into it and its CSS highlighter.

    background          --input-bg          (else TyMemo's background)
    text, identifiers   --on-surface        (else TyMemo's text)
    selection           --selection over the background (it carries alpha)
    gutter              --surface-chrome    (else the background)
    line numbers, comments  --muted over their ground
    keywords, selectors --accent            strings  --success
    numbers, units      --warning           at-rules --info (TSynCssSyn colours them as
                                             keywords: no attribute of their own)
    problem lines       --danger / --warning, 18 % over the background
    comparison: added   --success, 18 % over the background (the AI comparison window)
                removed --danger, 18 % over the background
                filler  --surface-chrome (a row one side has no line for)
    text on a tinted row    the text colour (one colour, so it reads on the tint)
    font                --terminal-font-family (monospace -> the platform's), --font-size-base,
                        smooth (ClearType on Windows, antialiased elsewhere)

  A token the theme does not define falls back as listed, or to the text colour. Borders and
  scroll bars are the platform's (SynEdit draws them natively). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, SynEdit, SynHighlighterCss, tyControls.Controller;

type
  TTbEditorColors = record
    Background, Text, Selection, Gutter, LineNumbers, Comment, Keyword, Str, Number,
    AtRule, ErrorLine, WarningLine: TColor;
    AddedLine, RemovedLine, FillerLine: TColor;   { the comparison window's rows }
    FontName: string;
    FontSize: Integer;       { points }
  end;

function TbEditorColors(AController: TTyStyleController): TTbEditorColors;
procedure TbApplyEditorColors(AEdit: TSynEdit; AHighlighter: TSynCssSyn;
  const AColors: TTbEditorColors);

implementation

uses
  SynGutterBase, tyControls.Types, tyControls.Css.Values, tyControls.Design.CssEditKit;

{ the face the tycss editors share: Consolas (else Courier New), Menlo, DejaVu Sans Mono
  (else monospace) }
function PlatformMonospace: string;
begin
  Result := TyCssEditFontName;
end;

{ a token's colour; False when the theme does not define it (or it is not a colour) }
function TokenColor(AController: TTyStyleController; const AName: string;
  out AColor: TTyColor): Boolean;
var
  s: TTyStyleSet;
begin
  AColor := tyTransparent;
  Result := False;
  try
    s := AController.Model.ResolveOverride('color: var(--' + AName + ');');
  except
    Exit;
  end;
  if tpTextColor in s.Present then
  begin
    AColor := s.TextColor;
    Result := True;
  end;
end;

{ AColor laid over AGround by its alpha, as an opaque LCL colour }
function Over(AColor, AGround: TTyColor): TColor;
var
  a: Integer;
begin
  a := TyAlphaOf(AColor);
  if a < 255 then
    AColor := TyMix(AGround or TTyColor($FF000000), AColor or TTyColor($FF000000), a * 100 / 255);
  Result := TyColorToLCL(AColor);
end;

function TbEditorColors(AController: TTyStyleController): TTbEditorColors;
var
  memo: TTyStyleSet;
  bg, fg, c, gutter: TTyColor;
  fname: string;
  px: Integer;

  function Pick(const AName: string; AFallback: TTyColor): TTyColor;
  begin
    if not TokenColor(AController, AName, Result) then
      Result := AFallback;
  end;

begin
  Result := Default(TTbEditorColors);
  if AController = nil then
    AController := TyDefaultController;
  try
    memo := AController.Model.ResolveStyle('TyMemo', '', []);
  except
    memo := Default(TTyStyleSet);
  end;
  if tpBackground in memo.Present then bg := memo.Background.Color else bg := TTyColor($FFFFFFFF);
  if tpTextColor in memo.Present then fg := memo.TextColor else fg := TTyColor($FF000000);
  bg := Pick('input-bg', bg) or TTyColor($FF000000);    { the ground is opaque }
  fg := Pick('on-surface', fg);
  Result.Background := TyColorToLCL(bg);
  Result.Text := Over(fg, bg);

  if not TokenColor(AController, 'selection', c) then
  begin
    try
      c := AController.Model.ResolveStyle('TyTextSelection', '', []).Background.Color;
    except
      c := TTyColor($FF3399FF);
    end;
  end;
  Result.Selection := Over(c, bg);

  gutter := Pick('surface-chrome', bg) or TTyColor($FF000000);
  Result.Gutter := TyColorToLCL(gutter);
  c := Pick('muted', fg);
  Result.LineNumbers := Over(c, gutter);
  Result.Comment := Over(c, bg);
  Result.Keyword := Over(Pick('accent', fg), bg);
  Result.Str := Over(Pick('success', fg), bg);
  Result.Number := Over(Pick('warning', fg), bg);
  Result.AtRule := Over(Pick('info', fg), bg);
  c := Pick('danger', fg) or TTyColor($FF000000);
  Result.ErrorLine := TyColorToLCL(TyMix(bg, c, 18));
  c := Pick('warning', fg) or TTyColor($FF000000);
  Result.WarningLine := TyColorToLCL(TyMix(bg, c, 18));
  c := Pick('success', fg) or TTyColor($FF000000);
  Result.AddedLine := TyColorToLCL(TyMix(bg, c, 18));
  c := Pick('danger', fg) or TTyColor($FF000000);
  Result.RemovedLine := TyColorToLCL(TyMix(bg, c, 18));
  Result.FillerLine := Result.Gutter;

  fname := Trim(AController.Model.RawVar('--terminal-font-family'));
  if (Length(fname) >= 2) and (fname[1] in ['"', '''']) and (fname[Length(fname)] = fname[1]) then
    fname := Copy(fname, 2, Length(fname) - 2);
  if (fname = '') or SameText(fname, 'monospace') then
    fname := PlatformMonospace;
  Result.FontName := fname;
  px := AController.Model.ResolveMetric('--font-size-base', 13);
  Result.FontSize := px * 72 div 96;
  if Result.FontSize < 8 then
    Result.FontSize := 8;
end;

procedure TbApplyEditorColors(AEdit: TSynEdit; AHighlighter: TSynCssSyn;
  const AColors: TTbEditorColors);
var
  i: Integer;
  part: TSynGutterPartBase;
begin
  if AEdit = nil then Exit;
  AEdit.Color := AColors.Background;
  AEdit.Font.Color := AColors.Text;
  AEdit.Font.Name := AColors.FontName;
  AEdit.Font.Size := AColors.FontSize;
  { smooth text (SynEdit's default is pixel text): ClearType on Windows, antialiased elsewhere }
  AEdit.Font.Quality := TyCssEditFontQuality;
  AEdit.SelectedColor.Background := AColors.Selection;
  AEdit.SelectedColor.Foreground := AColors.Text;
  AEdit.Gutter.Color := AColors.Gutter;
  for i := 0 to AEdit.Gutter.Parts.Count - 1 do
  begin
    part := AEdit.Gutter.Parts[i];
    if part.MarkupInfo <> nil then
    begin
      part.MarkupInfo.Background := AColors.Gutter;
      part.MarkupInfo.Foreground := AColors.LineNumbers;
    end;
  end;
  if AHighlighter <> nil then
  begin
    AHighlighter.IdentifierAttri.Foreground := AColors.Text;
    AHighlighter.SymbolAttri.Foreground := AColors.Text;
    AHighlighter.SpaceAttri.Foreground := AColors.Text;
    AHighlighter.CommentAttri.Foreground := AColors.Comment;
    { TSynCssSyn colours @-rules as keywords: they share AColors.Keyword }
    AHighlighter.KeyAttri.Foreground := AColors.Keyword;
    AHighlighter.SelectorAttri.Foreground := AColors.Keyword;
    AHighlighter.StringAttri.Foreground := AColors.Str;
    AHighlighter.NumberAttri.Foreground := AColors.Number;
    AHighlighter.MeasurementUnitAttri.Foreground := AColors.Number;
  end;
  AEdit.Invalidate;
end;

end.
