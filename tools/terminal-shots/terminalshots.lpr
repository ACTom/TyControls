program terminalshots;
{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{ Screenshots of TTyTerminalView for the phase 3 acceptance (the 16 colours across the
  built-in themes, a few recordings, the light-ground colours the user decides on).
  Off screen, the way tests/test.dpi.support paints a tree: no window is shown, the
  control is parented to a form that never appears and drawn into a bitmap through
  its own RenderTo -- the path a WM_PAINT takes, minus the screen. Builds from source/
  and examples/terminal (for the asciicast reader) without the package.

    terminalshots [--out <dir>] [--recordings <dir>]

  Writes PNGs and an index.md into <dir> (default
  docs/superpowers/plans/2026-09-29-terminal-phase-3-shots under the repository). }

uses
  Interfaces, SysUtils, Classes, Math, Types, Forms, Controls, Graphics, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Terminal, uasciicast;

type
  { RenderTo and the raster budget are protected: a shot wants every glyph in one frame }
  TShotView = class(TTyTerminalView)
  public
    procedure Shot(ABmp: TBitmap; APPI: Integer);
  end;

procedure TShotView.Shot(ABmp: TBitmap; APPI: Integer);
begin
  RasterBudgetMs := 0;
  RenderTo(ABmp.Canvas, Rect(0, 0, ABmp.Width, ABmp.Height), APPI);
end;

var
  OutDir, RecDir: string;
  Index: TStringList;
  Form: TForm;

function Utf8(u: Cardinal): string;
begin
  if u < $80 then Result := Chr(u)
  else if u < $800 then Result := Chr($C0 or (u shr 6)) + Chr($80 or (u and $3F))
  else Result := Chr($E0 or (u shr 12)) + Chr($80 or ((u shr 6) and $3F)) + Chr($80 or (u and $3F));
end;

function CastBytes(const AName: string; out AW, AH: Integer): RawByteString;
var
  c: TAsciicast;
  i: Integer;
begin
  c := TAsciicast.Create;
  try
    c.LoadFromFile(RecDir + AName);
    AW := c.Width;
    AH := c.Height;
    Result := '';
    for i := 0 to c.Count - 1 do
      Result := Result + c[i].Data;
  finally
    c.Free;
  end;
end;

{ one PNG: a terminal of ACols x ARows under theme/mode, fed AData, drawn at APPI }
procedure Shoot(const AFile, ATheme, AMode: string; const AData: RawByteString; ACols, ARows, APPI: Integer;
  const AWhat: string);
var
  ctl: TTyStyleController;
  v: TShotView;
  sz: TSize;
  bmp: TBitmap;
  png: TBGRABitmap;
  w, h: Integer;
begin
  ctl := TTyStyleController.Create(nil);
  v := TShotView.Create(Form);
  try
    ctl.ThemeName := ATheme;
    ctl.Mode := AMode;
    v.Controller := ctl;
    v.Parent := Form;
    { the grid in the control's own units (Font.PixelsPerInch), the picture at APPI }
    sz := v.SizeForGrid(ACols, ARows);
    v.SetBounds(0, 0, sz.cx, sz.cy);
    v.WriteSync(AData);
    w := MulDiv(sz.cx, APPI, v.Font.PixelsPerInch);
    h := MulDiv(sz.cy, APPI, v.Font.PixelsPerInch);
    bmp := TBitmap.Create;
    try
      bmp.PixelFormat := pf24bit;
      bmp.SetSize(w, h);
      bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);   { the sentinel: must not survive }
      bmp.Canvas.FillRect(0, 0, w, h);
      v.Shot(bmp, APPI);
      png := TBGRABitmap.Create(bmp);
      try
        png.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + AFile);
      finally
        png.Free;
      end;
    finally
      bmp.Free;
    end;
    Index.Add(Format('| `%s` | %s | %s | %s |', [AFile, ATheme, AMode, AWhat]));
  finally
    v.Free;
    ctl.Free;
  end;
end;

function Sample(const AIndexes: array of Integer): RawByteString;
var
  i, n: Integer;
begin
  { per colour: its name, text in it, a block of it, and the text on it as a background }
  Result := #27'[H'#27'[2J';
  for i := 0 to High(AIndexes) do
  begin
    n := AIndexes[i];
    Result := Result + Format('%2d ', [n])
      + Format(#27'[38;5;%dm', [n]) + 'The quick brown fox 0123 ' + Utf8($2588) + Utf8($2588) + Utf8($2588) + Utf8($2588)
      + #27'[0m ' + Format(#27'[48;5;%dm', [n]) + ' on it ' + #27'[0m'#13#10;
  end;
  Result := Result + #27'[?25l';
end;

{ A full-screen program's last screen is what the recording is about: cut before the
  last switch back from the alternate screen (vim, htop); otherwise the whole thing. }
function LastScreen(const AData: RawByteString; out AWhat: string): RawByteString;
var
  p, q: Integer;
begin
  p := 0;
  q := Pos(#27'[?1049l', AData);
  while q > 0 do
  begin
    p := q;
    q := Pos(#27'[?1049l', AData, p + 1);
  end;
  if p > 0 then
  begin
    Result := Copy(AData, 1, p - 1);
    AWhat := '程序退出前的最后一屏';
  end
  else
  begin
    Result := AData;
    AWhat := '最后一帧';
  end;
end;

var
  names: TStringArray;
  i, m, w, h, k: Integer;
  data: RawByteString;
  mode, rec, what: string;
const
  Modes: array[0..1] of string = ('light', 'dark');
  Singles: array[0..2] of string = ('vim-edit.cast', 'htop-few-frames.cast', 'cat-cjk-emoji.cast');
  YellowThemes: array[0..2] of string = ('xp', 'macos', 'breeze');
begin
  TyFallbackFontName := {$IFDEF MSWINDOWS}'Segoe UI'{$ELSE}''{$ENDIF};
  OutDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../../docs/superpowers/plans/2026-09-29-terminal-phase-3-shots');
  RecDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../../examples/terminal/recordings') + PathDelim;
  i := 1;
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '--out') and (i < ParamCount) then begin Inc(i); OutDir := ParamStr(i); end
    else if (ParamStr(i) = '--recordings') and (i < ParamCount) then begin Inc(i); RecDir := IncludeTrailingPathDelimiter(ParamStr(i)); end;
    Inc(i);
  end;
  ForceDirectories(OutDir);
  Application.Initialize;
  TyRegisterBuiltinThemes;
  Form := TForm.CreateNew(nil);
  Index := TStringList.Create;
  try
    Form.SetBounds(0, 0, 1600, 1200);
    Index.Add('# 终端 3 期验收截图');
    Index.Add('');
    Index.Add('`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体（Consolas 9pt）、96 PPI，放大的注明。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots`。');
    Index.Add('');
    Index.Add('| 文件 | 主题 | 明暗 | 内容 |');
    Index.Add('|---|---|---|---|');
    names := TyBuiltinThemeNames;
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        mode := Modes[m];
        data := CastBytes('ls-color.cast', w, h);
        Shoot(Format('ls-color-%s-%s.png', [names[i], mode]), names[i], mode, data + #27'[?25l', w, h, 96,
          '`ls-color.cast`（彩色 ls）');
        data := CastBytes('palette.cast', w, h);
        Shoot(Format('palette-%s-%s.png', [names[i], mode]), names[i], mode, data + #27'[?25l', w, h, 96,
          '`palette.cast`（16 色前景 / 背景）');
        WriteLn(names[i], ' ', mode);
      end;
    for k := 0 to High(Singles) do
      for m := 0 to 1 do
      begin
        rec := Singles[k];
        data := LastScreen(CastBytes(rec, w, h), what);
        Shoot(Format('%s-default-%s.png', [ChangeFileExt(rec, ''), Modes[m]]), 'default', Modes[m], data, w, h, 96,
          '`' + rec + '`（' + what + '）');
      end;
    { 7 and 15 on the light ground, twice the size (the user decides whether to tune them) }
    for m := 0 to 1 do
      Shoot(Format('ansi-7-15-default-%s-2x.png', [Modes[m]]), 'default', Modes[m], Sample([0, 7, 8, 15]), 40, 5, 192,
        '0 / 7 / 8 / 15 号色（黑、白及其亮色）放大 2 倍');
    { 3 (yellow) and 11 on the three lightest-ground skins where 3 contrasts least }
    for k := 0 to High(YellowThemes) do
      Shoot(Format('ansi-3-%s-light-15x.png', [YellowThemes[k]]), YellowThemes[k], 'light', Sample([3, 11, 2, 6]),
        40, 5, 144, '3 号色（黄）与 11 / 2 / 6 在浅底上，放大 1.5 倍');
    Index.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + 'index.md');
  finally
    Index.Free;
    Form.Free;
  end;
  WriteLn('done: ', OutDir);
end.
