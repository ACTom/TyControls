unit ujsonedit;

{$mode objfpc}{$H+}

{ THE OPTION EDITOR'S LOOK, read off the running theme. SynEdit is not a Ty
  control, so nothing paints it from the theme by itself: its colours are taken
  from the controller's tokens and pushed into it and its highlighter, again on
  every theme or light/dark change (the form calls ApplyJsonEditorLook after
  each). Nothing here is a fixed colour.

    background          --input-bg          (else TyMemo's background)
    text, punctuation   --on-surface        (else TyMemo's text)
    selection           --selection over the background (it carries alpha)
    gutter              --surface-chrome    (else the background)
    line numbers        --muted over the gutter
    keys and strings    --success           (JSON keys are strings)
    numbers             --warning
    true, false, null   --accent            (the highlighter's keywords)
    font                --terminal-font-family (monospace -> the platform's),
                        TyMemo's size, smooth (ClearType on Windows,
                        antialiased elsewhere)

  The highlighter is SynEdit's JavaScript one: SynEdit has no JSON highlighter,
  and a gallery option is a JavaScript object literal anyway. Borders and
  scroll bars are the platform's (SynEdit draws them natively). }

interface

uses
  Classes, SysUtils, Graphics, SynEdit, SynHighlighterJScript,
  tyControls.Controller;

procedure ApplyJsonEditorLook(AEdit: TSynEdit; AHighlighter: TSynJScriptSyn;
  AController: TTyCustomStyleController);

implementation

uses
  Forms, SynGutterBase, tyControls.Types, tyControls.Css.Values, tyControls.Painter;

function PlatformMonospace: string;
begin
  {$IFDEF MSWINDOWS}
  if Screen.Fonts.IndexOf('Consolas') >= 0 then Result := 'Consolas'
  else Result := 'Courier New';
  {$ELSE}
  {$IFDEF DARWIN}
  Result := 'Menlo';
  {$ELSE}
  if Screen.Fonts.IndexOf('DejaVu Sans Mono') >= 0 then Result := 'DejaVu Sans Mono'
  else Result := 'monospace';
  {$ENDIF}
  {$ENDIF}
end;

{ a token's colour; False when the theme does not define it }
function TokenColor(AController: TTyCustomStyleController; const AName: string;
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

procedure ApplyJsonEditorLook(AEdit: TSynEdit; AHighlighter: TSynJScriptSyn;
  AController: TTyCustomStyleController);
var
  memo: TTyStyleSet;
  bg, fg, c, gutter: TTyColor;
  text, key, str, num: TColor;
  fname: string;
  px, i: Integer;
  part: TSynGutterPartBase;

  function Pick(const AName: string; AFallback: TTyColor): TTyColor;
  begin
    if not TokenColor(AController, AName, Result) then
      Result := AFallback;
  end;

begin
  if AEdit = nil then Exit;
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
  text := Over(fg, bg);
  key := Over(Pick('accent', fg), bg);
  str := Over(Pick('success', fg), bg);
  num := Over(Pick('warning', fg), bg);

  AEdit.Color := TyColorToLCL(bg);
  AEdit.Font.Color := text;

  if not TokenColor(AController, 'selection', c) then
  begin
    try
      c := AController.Model.ResolveStyle('TyTextSelection', '', []).Background.Color;
    except
      c := TTyColor($FF3399FF);
    end;
  end;
  AEdit.SelectedColor.Background := Over(c, bg);
  AEdit.SelectedColor.Foreground := text;

  gutter := Pick('surface-chrome', bg) or TTyColor($FF000000);
  AEdit.Gutter.Color := TyColorToLCL(gutter);
  c := Pick('muted', fg);
  for i := 0 to AEdit.Gutter.Parts.Count - 1 do
  begin
    part := AEdit.Gutter.Parts[i];
    if part.MarkupInfo <> nil then
    begin
      part.MarkupInfo.Background := TyColorToLCL(gutter);
      part.MarkupInfo.Foreground := Over(c, gutter);
    end;
  end;

  fname := Trim(AController.Model.RawVar('--terminal-font-family'));
  if (Length(fname) >= 2) and (fname[1] in ['"', '''']) and (fname[Length(fname)] = fname[1]) then
    fname := Copy(fname, 2, Length(fname) - 2);
  if (fname = '') or SameText(fname, 'monospace') then
    fname := PlatformMonospace;
  AEdit.Font.Name := fname;
  { the size the TyMemo it replaces draws at (a theme size is points unless
    written in px) }
  if (tpFontSize in memo.Present) and (memo.FontSize <> 0) then
    px := TyFontHeightPx(memo.FontSize, Screen.PixelsPerInch)
  else
    px := TyFontHeightPx(AController.Model.ResolveMetric('--font-size-base', 9), Screen.PixelsPerInch);
  AEdit.Font.Height := -px;
  { smooth text: SynEdit's default is pixel text }
  {$IFDEF MSWINDOWS}
  AEdit.Font.Quality := fqCleartypeNatural;
  {$ELSE}
  AEdit.Font.Quality := fqAntialiased;
  {$ENDIF}

  if AHighlighter <> nil then
  begin
    AHighlighter.IdentifierAttri.Foreground := text;
    AHighlighter.SymbolAttri.Foreground := text;
    AHighlighter.BracketAttri.Foreground := text;
    AHighlighter.SpaceAttri.Foreground := text;
    AHighlighter.CommentAttri.Foreground := Over(Pick('muted', fg), bg);
    AHighlighter.KeyAttri.Foreground := key;
    AHighlighter.NonReservedKeyAttri.Foreground := key;
    AHighlighter.EventAttri.Foreground := key;
    AHighlighter.StringAttri.Foreground := str;
    AHighlighter.NumberAttri.Foreground := num;
  end;
  AEdit.Invalidate;
end;

end.
