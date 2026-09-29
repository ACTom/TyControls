program terminalshots;
{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{ Screenshots of TTyTerminalView for the phase 3 acceptance (the 16 colours across the
  built-in themes, a few recordings, the light-ground colours the user decides on), and
  with --phase4 for the phase 4 one (a selection unfocused and focused, a column
  selection, a Ctrl-hovered web address, on four skins), and with --phase5 for the
  phase 5 one (the reflow at three widths and under an old ConPTY, the minimum
  contrast at 1 and 4.5, the glyphs it leaves alone, powerline and braille drawn).
  Off screen, the way tests/test.dpi.support paints a tree: no window is shown, the
  control is parented to a form that never appears and drawn into a bitmap through
  its own RenderTo -- the path a WM_PAINT takes, minus the screen. Builds from source/
  and examples/terminal (for the asciicast reader) without the package.

    terminalshots [--phase4 | --phase5] [--out <dir>] [--recordings <dir>]

  Writes PNGs and an index.md into <dir> (default
  docs/superpowers/plans/2026-09-29-terminal-phase-3-shots under the repository, or
  ...-phase-4-shots with --phase4, ...-phase-5-shots with --phase5). }

uses
  Interfaces, SysUtils, Classes, Math, Types, Forms, Controls, Graphics, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Terminal.Buffer, tyControls.Terminal, uasciicast;

type
  { what a phase 4 shot does to the terminal after the text is in }
  TShotPrep = (spNone, spSelection, spSelectionFocused, spColumn, spLinkHover);

  { RenderTo and the raster budget are protected: a shot wants every glyph in one frame }
  TShotView = class(TTyTerminalView)
  public
    procedure Shot(ABmp: TBitmap; APPI: Integer);
    procedure Prepare(APrep: TShotPrep);
  end;

procedure TShotView.Shot(ABmp: TBitmap; APPI: Integer);
begin
  RasterBudgetMs := 0;
  RenderTo(ABmp.Canvas, Rect(0, 0, ABmp.Width, ABmp.Height), APPI);
end;

{ the mouse as a user drives it: MouseDown / MouseMove / MouseUp are protected }
procedure TShotView.Prepare(APrep: TShotPrep);

  function Mid(ACol, ARow: Integer): TPoint;
  var
    r: TRect;
  begin
    r := CellRect(ACol, ARow);
    Result := Point(r.Left + (r.Right - r.Left) div 4, (r.Top + r.Bottom) div 2);
  end;

var
  a, b: TPoint;
begin
  case APrep of
    spSelection, spSelectionFocused:
      begin
        { from the middle of the first row into the second (text on both, Chinese included) }
        a := Mid(7, 0);
        b := Mid(14, 1);
        MouseDown(mbLeft, [ssLeft], a.X, a.Y);
        MouseMove([ssLeft], b.X, b.Y);
        MouseUp(mbLeft, [], b.X, b.Y);
        if APrep = spSelectionFocused then
          DoEnter;
      end;
    spColumn:
      begin
        a := Mid(3, 0);
        b := Mid(15, 2);
        MouseDown(mbLeft, [ssLeft, ssAlt], a.X, a.Y);
        MouseMove([ssLeft, ssAlt], b.X, b.Y);
        MouseUp(mbLeft, [ssAlt], b.X, b.Y);
        DoEnter;                               { focused, as right after the drag }
      end;
    spLinkHover:
      begin
        a := Mid(33, 1);                       { inside https://example.com/docs }
        MouseMove([ssCtrl], a.X, a.Y);
      end;
  end;
end;

var
  OutDir, RecDir: string;
  Index: TStringList;
  Form: TForm;

function Utf8(u: Cardinal): string;
begin
  if u < $80 then Result := Chr(u)
  else if u < $800 then Result := Chr($C0 or (u shr 6)) + Chr($80 or (u and $3F))
  else if u < $10000 then Result := Chr($E0 or (u shr 12)) + Chr($80 or ((u shr 6) and $3F)) + Chr($80 or (u and $3F))
  else Result := Chr($F0 or (u shr 18)) + Chr($80 or ((u shr 12) and $3F)) + Chr($80 or ((u shr 6) and $3F))
    + Chr($80 or (u and $3F));
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

{ a terminal of ACols x ARows under a controller (theme / mode set by the caller) }
function NewShotView(ACtl: TTyStyleController; ACols, ARows: Integer): TShotView;
var
  sz: TSize;
begin
  Result := TShotView.Create(Form);
  Result.Controller := ACtl;
  Result.Parent := Form;
  { the grid in the control's own units (Font.PixelsPerInch), the picture at APPI }
  sz := Result.SizeForGrid(ACols, ARows);
  Result.SetBounds(0, 0, sz.cx, sz.cy);
end;

{ the view as it is now, drawn at APPI, into AFile, with its index line }
procedure SaveShot(AView: TShotView; const AFile, ATheme, AMode: string; APPI: Integer; const AWhat: string);
var
  bmp: TBitmap;
  png: TBGRABitmap;
  w, h: Integer;
begin
  w := MulDiv(AView.Width, APPI, AView.Font.PixelsPerInch);
  h := MulDiv(AView.Height, APPI, AView.Font.PixelsPerInch);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(w, h);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);   { the sentinel: must not survive }
    bmp.Canvas.FillRect(0, 0, w, h);
    AView.Shot(bmp, APPI);
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
end;

{ one PNG: a terminal of ACols x ARows under theme/mode, fed AData, prepared, drawn at APPI }
procedure Shoot(const AFile, ATheme, AMode: string; const AData: RawByteString; ACols, ARows, APPI: Integer;
  const AWhat: string; APrep: TShotPrep = spNone; AContrast: Double = 1);
var
  ctl: TTyStyleController;
  v: TShotView;
begin
  ctl := TTyStyleController.Create(nil);
  try
    ctl.ThemeName := ATheme;
    ctl.Mode := AMode;
    v := NewShotView(ctl, ACols, ARows);
    try
      v.MinimumContrastRatio := AContrast;
      v.WriteSync(AData);
      v.Prepare(APrep);
      SaveShot(v, AFile, ATheme, AMode, APPI, AWhat);
    finally
      v.Free;
    end;
  finally
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

{ Phase 4: a selection, a column and a hovered link on the same few lines of mixed text }
procedure Phase4;
const
  Skins: array[0..3] of array[0..1] of string = (('default', 'light'), ('default', 'dark'),
    ('xp', 'light'), ('macos', 'light'));
var
  text: RawByteString;
  k: Integer;
  tag: string;
begin
  text := #27'[?25l'
    + '$ echo ' + Utf8($9009) + Utf8($533A) + Utf8($6D4B) + Utf8($8BD5) + ' selection test'#13#10
    + Utf8($4E2D) + Utf8($6587) + Utf8($4E0E) + ' English ' + Utf8($6DF7) + Utf8($6392)
    + ', see https://example.com/docs here'#13#10
    + Utf8($7B2C) + Utf8($4E09) + Utf8($884C) + ' third line 12345'#13#10;
  Index.Add('# 终端 4 期验收截图');
  Index.Add('');
  Index.Add('`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体、96 PPI。鼠标动作经控件自己的 MouseDown / MouseMove / MouseUp。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots --phase4`。');
  Index.Add('');
  Index.Add('| 文件 | 主题 | 明暗 | 看什么 |');
  Index.Add('|---|---|---|---|');
  for k := 0 to High(Skins) do
  begin
    tag := Skins[k][0] + '-' + Skins[k][1];
    Shoot(Format('selection-%s.png', [tag]), Skins[k][0], Skins[k][1], text, 60, 4, 96,
      '失焦的选区：从第一行中间拖到第二行；选中格的底色换成选区色（在主题底色上混成不透明），字色不变', spSelection);
    Shoot(Format('selection-focused-%s.png', [tag]), Skins[k][0], Skins[k][1], text, 60, 4, 96,
      '聚焦的选区：同一段，换成聚焦那一色', spSelectionFocused);
    Shoot(Format('column-%s.png', [tag]), Skins[k][0], Skins[k][1], text, 60, 4, 96,
      '聚焦的列选区（Alt+拖）：三行都是第 3–14 列；宽字符按它的第一列算——第二、三行的「文」「三」第一列在 2、起点落在它们后半，整字不选；第一行的「试」（13–14 列）整字选中', spColumn);
    Shoot(Format('link-hover-%s.png', [tag]), Skins[k][0], Skins[k][1], text, 60, 4, 96,
      '按着 Ctrl 悬停网址：只有网址那一段有链接色的下划线', spLinkHover);
    WriteLn(tag);
  end;
end;

{ Phase 5: the reflow, the minimum contrast, the drawn powerline and braille }
procedure Phase5;
const
  Rows = 9;
var
  text, dark, excluded, powerline, braille, pal: RawByteString;
  ctl: TTyStyleController;
  v: TShotView;
  pty: TTyTerminalWindowsPty;
  m, k, c: Integer;
  mode: string;

  procedure Resize(ACols: Integer);
  var
    sz: TSize;
  begin
    sz := v.SizeForGrid(ACols, Rows);
    v.SetBounds(0, 0, sz.cx, sz.cy);
  end;

const
  Modes: array[0..1] of string = ('light', 'dark');
  YellowThemes: array[0..2] of string = ('xp', 'macos', 'breeze');
begin
  { long lines: mixed Chinese and English, an emoji, colours, an OSC 8 link, and a wide
    character that ends exactly on column 80 }
  text := #27'[?25l'
    + '$ echo ' + Utf8($91CD) + Utf8($65B0) + Utf8($6298) + Utf8($884C) + ' reflow test'#13#10
    + #27'[32m' + Utf8($8FD9) + Utf8($662F) + Utf8($4E00) + Utf8($884C) + Utf8($5F88) + Utf8($957F)
    + Utf8($7684) + Utf8($4E2D) + Utf8($82F1) + Utf8($6DF7) + Utf8($6392) + #27'[0m'
    + ' text with an emoji ' + Utf8($1F600) + ' and '#27'[1;35mcolours'#27'[0m that runs past forty-seven columns, '
    + #27']8;;https://example.com/phase5'#7'a hyperlink'#27']8;;'#7' at the end'#13#10
    + StringOfChar('-', 78) + Utf8($5B57) + #13#10
    + 'short line'#13#10;
  Index.Add('# 终端 5 期验收截图');
  Index.Add('');
  Index.Add('`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体、96 PPI，放大的注明。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots --phase5`。');
  Index.Add('');
  Index.Add('| 文件 | 主题 | 明暗 | 看什么 |');
  Index.Add('|---|---|---|---|');
  { 1. the reflow: 80 -> 47 -> 80 on one control }
  for m := 0 to 1 do
  begin
    mode := Modes[m];
    ctl := TTyStyleController.Create(nil);
    try
      ctl.ThemeName := 'default';
      ctl.Mode := mode;
      v := NewShotView(ctl, 80, Rows);
      try
        v.WriteSync(text);
        SaveShot(v, Format('reflow-wide-default-%s.png', [mode]), 'default', mode, 96,
          '80 列：第二行（中英混排、表情、彩色、链接）是一整行；第三行 78 个减号加一个宽字符，正好压在第 80 列');
        Resize(47);
        SaveShot(v, Format('reflow-narrow-default-%s.png', [mode]), 'default', mode, 96,
          '改到 47 列：长行按新宽度折回，宽字符不劈开（放不下就整个挪到下一行），颜色、链接跟着字走');
        Resize(80);
        SaveShot(v, Format('reflow-back-default-%s.png', [mode]), 'default', mode, 96,
          '再改回 80 列：和第一张一样（折回的行接回去）');
      finally
        v.Free;
      end;
    finally
      ctl.Free;
    end;
  end;
  { 2. the same under an old ConPTY: no reflow }
  ctl := TTyStyleController.Create(nil);
  try
    ctl.ThemeName := 'default';
    ctl.Mode := 'light';
    v := NewShotView(ctl, 80, Rows);
    try
      pty.Backend := twpConPty;
      pty.BuildNumber := 19044;
      v.Core.WindowsPty := pty;
      v.WriteSync(text);
      Resize(47);
      SaveShot(v, 'reflow-oldconpty-narrow-default-light.png', 'default', 'light', 96,
        '同样内容，`WindowsPty = {conpty, 19044}` 下改到 47 列：不重新折行，长行截在网格外（老 ConPTY 自己会重画）');
    finally
      v.Free;
    end;
  finally
    ctl.Free;
  end;
  { 3. the 16 colours as text on the three light grounds where colour 3 contrasts least,
    at 1 and 4.5 (palette.cast draws its foregrounds as full blocks, which the contrast
    leaves alone: its two shots would be the same picture) }
  pal := Sample([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
  for k := 0 to High(YellowThemes) do
  begin
    Shoot(Format('contrast-1-%s-light.png', [YellowThemes[k]]), YellowThemes[k], 'light',
      pal, 44, 17, 96, '16 色写字、█ 块、当底色，最低对比度 1（不调）');
    Shoot(Format('contrast-45-%s-light.png', [YellowThemes[k]]), YellowThemes[k], 'light',
      pal, 44, 17, 96,
      '同上，4.5：浅色的字压暗到对底色 4.5:1（3 号黄、11 号最明显）；█ 块和当底色的格不变', spNone, 4.5);
  end;
  { 4. on the dark ground: Tango 0 on pure black, faint text, selected text, ls's
    other-writable directory (black on green) and an inverse one }
  dark := #27'[?25l'
    + #27'[30;48;2;0;0;0m' + ' Tango 0 (#2e3436) on pure black ' + #27'[0m'#13#10
    + #27'[2m' + 'faint text, dim grey on the ground' + #27'[0m'#13#10
    + 'selected text: the selection is the ground'#13#10
    + #27'[30;42m' + 'other-writable' + #27'[0m  ' + #27'[7;34m' + 'inverse-dir' + #27'[0m  '
    + #27'[01;34m' + 'directory' + #27'[0m'#13#10;
  for c := 0 to 1 do
  begin
    ctl := TTyStyleController.Create(nil);
    try
      ctl.ThemeName := 'default';
      ctl.Mode := 'dark';
      v := NewShotView(ctl, 50, 5);
      try
        if c = 1 then v.MinimumContrastRatio := 4.5;
        v.WriteSync(dark);
        v.Select(0, v.Core.Buffer.YBase + 2, 42);
        if c = 0 then
          SaveShot(v, 'contrast-1-default-dark.png', 'default', 'dark', 96,
            '深底，最低对比度 1：纯黑底上的 0 号色、暗淡文字、选区里的字（第三行，失焦选区）、ls 的反显目录')
        else
          SaveShot(v, 'contrast-45-default-dark.png', 'default', 'dark', 96,
            '同上，4.5：纯黑底上的 0 号色提亮，绿底上的黑字压暗；暗淡文字（比值减半）和选区里的字（对选区色比）本来就够，不变');
      finally
        v.Free;
      end;
    finally
      ctl.Free;
    end;
  end;
  { 5. what 4.5 leaves alone: a double-line box, block elements, powerline, all in a pale
    grey on the light ground, next to text in the same grey (which is adjusted) }
  excluded := #27'[?25l'#27'[38;2;200;200;200m'
    + Utf8($2554) + Utf8($2550) + Utf8($2550) + Utf8($2550) + Utf8($2550) + Utf8($2557)
    + ' ' + Utf8($2588) + Utf8($2593) + Utf8($2592) + Utf8($2591) + Utf8($2580) + Utf8($2584)
    + ' ' + Utf8($E0B0) + Utf8($E0B2) + Utf8($E0B4) + Utf8($E0B6) + ' text in the same grey'#13#10
    + Utf8($255A) + Utf8($2550) + Utf8($2550) + Utf8($2550) + Utf8($2550) + Utf8($255D) + #27'[0m'#13#10;
  Shoot('contrast-excluded-default-light.png', 'default', 'light', excluded, 50, 3, 96,
    '4.5 下框线、块元素、Powerline 用的浅灰不变；右边同色的文字被压暗', spNone, 4.5);
  { 6. powerline and braille, drawn }
  powerline := #27'[?25l'
    + #27'[44;97m' + ' main ' + #27'[34;42m' + Utf8($E0B0) + #27'[30m' + ' ~/src ' + #27'[32;49m' + Utf8($E0B0)
    + #27'[0m  ' + #27'[35;49m' + Utf8($E0B6) + #27'[45;97m' + ' round ' + #27'[35;49m' + Utf8($E0B4) + #27'[0m  '
    + Utf8($E0B1) + ' ' + Utf8($E0B3) + ' ' + Utf8($E0B9) + ' ' + Utf8($E0BB) + #13#10
    + Utf8($E0A0) + ' branch  ' + Utf8($E0A1) + ' ln  ' + Utf8($E0A2) + ' lock  ' + Utf8($E0A3) + ' cn'#13#10;
  for k := $E0B8 to $E0D4 do
    powerline := powerline + Utf8(k) + ' ';
  powerline := powerline + #13#10;
  braille := #27'[?25l';
  for k := 0 to 255 do
  begin
    braille := braille + Utf8($2800 + k);
    if k mod 64 = 63 then braille := braille + #13#10;
  end;
  braille := braille + Utf8($28FF) + Utf8($28FF) + ' ' + Utf8($2847) + Utf8($28B8) + ' btop-style graph: '
    + Utf8($2840) + Utf8($28C0) + Utf8($28E0) + Utf8($28F0) + Utf8($28F8) + Utf8($28FC) + Utf8($28FE) + Utf8($28FF);
  for m := 0 to 1 do
  begin
    Shoot(Format('glyphs-powerline-%s.png', [Modes[m]]), 'default', Modes[m], powerline, 70, 4, 96,
      'Powerline（控件自己画，Consolas 里没有这些字形）：箭头、半圆和相邻格的底色严丝合缝；分支、行号、锁；E0B8–E0D4');
    Shoot(Format('glyphs-braille-%s.png', [Modes[m]]), 'default', Modes[m], braille, 66, 5, 96,
      '盲文 U+2800–28FF 全部 256 个（每行 64 个），末行是 btop 式的图');
  end;
  Shoot('glyphs-powerline-light-3x.png', 'default', 'light', powerline, 70, 4, 288, '同上，放大 3 倍');
  Shoot('glyphs-braille-light-3x.png', 'default', 'light', braille, 66, 5, 288, '同上，放大 3 倍');
end;

var
  names: TStringArray;
  i, m, w, h, k: Integer;
  data: RawByteString;
  mode, rec, what: string;
  doPhase4, doPhase5: Boolean;
const
  Modes: array[0..1] of string = ('light', 'dark');
  Singles: array[0..2] of string = ('vim-edit.cast', 'htop-few-frames.cast', 'cat-cjk-emoji.cast');
  YellowThemes: array[0..2] of string = ('xp', 'macos', 'breeze');
begin
  TyFallbackFontName := {$IFDEF MSWINDOWS}'Segoe UI'{$ELSE}''{$ENDIF};
  doPhase4 := False;
  doPhase5 := False;
  for i := 1 to ParamCount do
  begin
    if ParamStr(i) = '--phase4' then doPhase4 := True;
    if ParamStr(i) = '--phase5' then doPhase5 := True;
  end;
  if doPhase5 then
    OutDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../../docs/superpowers/plans/2026-09-29-terminal-phase-5-shots')
  else if doPhase4 then
    OutDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../../docs/superpowers/plans/2026-09-29-terminal-phase-4-shots')
  else
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
    if doPhase5 then
    begin
      Phase5;
      Index.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + 'index.md');
      WriteLn('done: ', OutDir);
      Exit;
    end;
    if doPhase4 then
    begin
      Phase4;
      Index.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + 'index.md');
      WriteLn('done: ', OutDir);
      Exit;
    end;
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
