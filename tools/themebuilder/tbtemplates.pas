unit tbtemplates;
{ What File > New starts from: a built-in theme copied whole under a one-line header (the
  text comes from the library's compiled-in pack, so this works without a checkout), or a
  minimal theme -- the six seeds of themes/auto.tycss in a light and a dark block, and
  nothing else: the rest comes from the base theme the document is loaded over. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils;

resourcestring
  rsTbBasedOn = 'Based on the built-in theme "%s".';
  rsTbMinimalHeader = 'A minimal theme: the six seeds, light and dark. Everything else comes from the base theme.';

function TbMinimalTemplate: string;
{ a header comment naming the theme, then TyBuiltinThemeCss(AName) unchanged; '' if unknown }
function TbFromBuiltin(const AName: string): string;
function TbBuiltinHeader(const AName: string): string;

implementation

uses
  tyControls.BuiltinThemes;

function TbBuiltinHeader(const AName: string): string;
begin
  Result := '/* ' + Format(rsTbBasedOn, [AName]) + ' */' + LineEnding + LineEnding;
end;

function TbFromBuiltin(const AName: string): string;
var
  css: string;
begin
  css := TyBuiltinThemeCss(AName);
  if css = '' then
    Exit('');
  Result := TbBuiltinHeader(AName) + css;
end;

function TbMinimalTemplate: string;

  procedure Block(var S: string; const AMode, AAccent, ASurface, AOnSurface, ABorder,
    ADanger: string);
  begin
    S := S + '@mode ' + AMode + ' {' + LineEnding
      + '  :root {' + LineEnding
      + '    --accent: ' + AAccent + ';' + LineEnding
      + '    --surface: ' + ASurface + ';' + LineEnding
      + '    --on-surface: ' + AOnSurface + ';' + LineEnding
      + '    --border: ' + ABorder + ';' + LineEnding
      + '    --danger: ' + ADanger + ';' + LineEnding
      + '    --radius: 6px;' + LineEnding
      + '  }' + LineEnding
      + '}' + LineEnding;
  end;

begin
  Result := '/* ' + StringReplace(rsTbMinimalHeader, '*/', '* /', [rfReplaceAll]) + ' */'
    + LineEnding + LineEnding;
  { the seed values of themes/auto.tycss }
  Block(Result, 'light', '#3B82F6', '#FFFFFF', '#1F2937', '#D1D5DB', '#EF4444');
  Result := Result + LineEnding;
  Block(Result, 'dark', '#60A5FA', '#1E1E1E', '#E5E7EB', '#3F3F46', '#F87171');
end;

end.
