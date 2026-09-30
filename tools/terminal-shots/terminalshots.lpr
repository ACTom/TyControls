program terminalshots;
{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{ Screenshots of TTyTerminalView for the phase 3 acceptance (the 16 colours across the
  built-in themes, a few recordings, the light-ground colours the user decides on), and
  with --phase4 for the phase 4 one (a selection unfocused and focused, a column
  selection, a Ctrl-hovered web address, on four skins), and with --phase5 for the
  phase 5 one (the reflow at three widths and under an old ConPTY, the minimum
  contrast at 1 and 4.5, the glyphs it leaves alone, powerline and braille drawn), and
  with --phase6 for the phase 6 one (colour schemes: the seven the example ships, a
  light / dark pair, following the theme, a program's OSC 11 over a scheme, the minimum
  contrast on a light scheme, a partial scheme, the selection at 0.3 and a scheme's own
  unfocused selection colour), and with --phase7 for the phase 7 one (ZModem in the
  terminal: the progress line, the summary with the prompt after it, the ConPTY
  refusal, a local selection while the stream is claimed -- the real core and the
  example's glue fed lrzsz's recording, the clock injected).
  Off screen, the way tests/test.dpi.support paints a tree: no window is shown, the
  control is parented to a form that never appears and drawn into a bitmap through
  its own RenderTo -- the path a WM_PAINT takes, minus the screen. Builds from source/
  and examples/terminal (for the asciicast reader) without the package.

    terminalshots [--phase4 | --phase5 | --phase6 | --phase7] [--out <dir>] [--recordings <dir>]

  Writes PNGs and an index.md into <dir> (default
  docs/superpowers/plans/2026-09-29-terminal-phase-3-shots under the repository, or
  ...-phase-4-shots with --phase4, ...-phase-5-shots with --phase5,
  docs/superpowers/plans/2026-09-30-terminal-phase-6-shots with --phase6,
  ...-phase-7-shots with --phase7). }

uses
  Interfaces, SysUtils, Classes, Math, Types, Forms, Controls, Graphics, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal, uasciicast, uzmodemsession,
  uzmodemterm;

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
      '同上，4.5：对底色不到 4.5:1 的字压暗到 4.5:1（xp 上差得最多的是 3、14、10 号）；█ 块和当底色的格不变', spNone, 4.5);
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

{ Phase 6: colour schemes. The seven come from the example's own scheme file. }
function SchemeText: string;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(ExpandFileName(RecDir + '..' + PathDelim + 'colorschemes' + PathDelim
    + 'windows-terminal.json'), fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, fs.Size);
    if Length(Result) > 0 then fs.ReadBuffer(Result[1], Length(Result));
  finally
    fs.Free;
  end;
end;

{ a terminal under theme/mode, the scheme ALight (paired with ADark when that is not ''),
  fed AData, then AAfter, prepared, drawn at 96 PPI }
procedure ShootScheme(const AFile, ATheme, AMode: string; const AData: RawByteString; ACols, ARows: Integer;
  const AWhat, ALight, ADark: string; APrep: TShotPrep = spNone; AContrast: Double = 1;
  const AAfter: RawByteString = '');
var
  ctl: TTyStyleController;
  v: TShotView;
  txt: string;
begin
  txt := SchemeText;
  ctl := TTyStyleController.Create(nil);
  try
    ctl.ThemeName := ATheme;
    ctl.Mode := AMode;
    v := NewShotView(ctl, ACols, ARows);
    try
      v.ColorScheme.LoadFromText(txt, ALight);
      if ADark <> '' then
      begin
        v.DarkColorScheme.LoadFromText(txt, ADark);
        v.ColorSchemePaired := True;
      end;
      v.ColorSource := tsrcScheme;
      v.MinimumContrastRatio := AContrast;
      v.WriteSync(AData);
      v.WriteSync(AAfter);
      v.Prepare(APrep);
      SaveShot(v, AFile, ATheme, AMode, 96, AWhat);
    finally
      v.Free;
    end;
  finally
    ctl.Free;
  end;
end;

{ the pixels of a view drawn now (the sentinel ground under it) }
function Pixels(AView: TShotView): TBGRABitmap;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(AView.Width, AView.Height);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    AView.Shot(bmp, AView.Font.PixelsPerInch);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function CountDifferent(A, B: TBGRABitmap): Integer;
var
  x, y: Integer;
  p, q: TBGRAPixel;
begin
  if (A.Width <> B.Width) or (A.Height <> B.Height) then Exit(-1);
  Result := 0;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
    begin
      p := A.GetPixel(x, y);
      q := B.GetPixel(x, y);
      if (p.red <> q.red) or (p.green <> q.green) or (p.blue <> q.blue) then Inc(Result);
    end;
end;

procedure Phase6;
const
  Seven: array[0..6, 0..1] of string = (('campbell', 'Campbell'), ('onehalf-dark', 'One Half Dark'),
    ('onehalf-light', 'One Half Light'), ('solarized-dark', 'Solarized Dark'),
    ('solarized-light', 'Solarized Light'), ('tango-dark', 'Tango Dark'), ('tango-light', 'Tango Light'));
  Modes: array[0..1] of string = ('light', 'dark');
var
  pal, sel, lines: RawByteString;
  w, h, k, m, diff: Integer;
  ctl: TTyStyleController;
  plain, loaded: TShotView;
  a, b, old: TBGRABitmap;
  oldFile: string;
begin
  pal := CastBytes('palette.cast', w, h) + #27'[?25l';
  Index.Add('# 终端 6 期验收截图');
  Index.Add('');
  Index.Add('`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体、96 PPI。方案取自示例的 `examples/terminal/colorschemes/windows-terminal.json`（Windows Terminal 自带的七套）。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots --phase6`。');
  Index.Add('');
  Index.Add('| 文件 | 主题 | 明暗 | 看什么 |');
  Index.Add('|---|---|---|---|');
  { 1. the seven, palette.cast under the default light theme }
  for k := 0 to High(Seven) do
    ShootScheme(Format('scheme-%s.png', [Seven[k][0]]), 'default', 'light', pal, w, h,
      Format('`palette.cast`，方案 %s：16 色、前景、底色（连内边距）都是这一套的，不跟主题', [Seven[k][1]]),
      Seven[k][1], '');
  { 2. a pair: Tango Light on the light theme, Tango Dark on the dark one }
  for m := 0 to 1 do
    ShootScheme(Format('scheme-pair-tango-%s.png', [Modes[m]]), 'default', Modes[m], pal, w, h,
      '明暗配对（Tango Light / Tango Dark）：浅色主题是 Tango Light，深色主题是 Tango Dark', 'Tango Light', 'Tango Dark');
  { 3. following the theme: a control that never had a scheme, and one with Campbell loaded
    but ColorSource = tsrcTheme, must be the same picture }
  for m := 0 to 1 do
  begin
    ctl := TTyStyleController.Create(nil);
    try
      ctl.ThemeName := 'default';
      ctl.Mode := Modes[m];
      plain := NewShotView(ctl, w, h);
      loaded := NewShotView(ctl, w, h);
      try
        loaded.ColorScheme.LoadFromText(SchemeText, 'Campbell');
        plain.WriteSync(pal);
        loaded.WriteSync(pal);
        a := Pixels(plain);
        b := Pixels(loaded);
        try
          diff := CountDifferent(a, b);
          WriteLn(Format('scheme-follow-default-%s: never set vs Campbell loaded but following the theme: %d pixels differ',
            [Modes[m], diff]));
          oldFile := ExpandFileName(OutDir + PathDelim + '..' + PathDelim + '2026-09-29-terminal-phase-3-shots'
            + PathDelim + Format('palette-default-%s.png', [Modes[m]]));
          if FileExists(oldFile) then
          begin
            old := TBGRABitmap.Create(oldFile);
            try
              WriteLn(Format('scheme-follow-default-%s vs phase 3 palette-default-%s.png: %d pixels differ',
                [Modes[m], Modes[m], CountDifferent(a, old)]));
            finally
              old.Free;
            end;
          end;
        finally
          a.Free;
          b.Free;
        end;
        SaveShot(loaded, Format('scheme-follow-default-%s.png', [Modes[m]]), 'default', Modes[m], 96,
          Format('跟随主题：方案里装着 Campbell 但 `ColorSource = tsrcTheme`，和从没设过方案的控件逐像素比，%d 个像素不同', [diff]));
      finally
        plain.Free;
        loaded.Free;
      end;
    finally
      ctl.Free;
    end;
  end;
  { 4. the program's OSC 11 over a scheme: the padding follows }
  ShootScheme('scheme-osc11-solarized-dark.png', 'default', 'light', pal, w, h,
    'Solarized Dark 下程序发 `OSC 11 ;#203040`：底色连内边距换成程序的颜色', 'Solarized Dark', '', spNone, 1,
    #27']11;#203040'#7);
  { 5. the minimum contrast on a light scheme: the 16 colours as text }
  lines := Sample([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
  ShootScheme('scheme-contrast-1-solarized-light.png', 'default', 'light', lines, 44, 17,
    'Solarized Light，16 色写字、█ 块、当底色，最低对比度 1（不调）', 'Solarized Light', '');
  ShootScheme('scheme-contrast-45-solarized-light.png', 'default', 'light', lines, 44, 17,
    '同上，4.5：对方案底色 #FDF6E3 不到 4.5:1 的字压暗；█ 块和当底色的格不变', 'Solarized Light', '', spNone, 4.5);
  { 6. a partial scheme: foreground, background and red; the rest follows the theme }
  ctl := TTyStyleController.Create(nil);
  try
    ctl.ThemeName := 'default';
    ctl.Mode := 'light';
    plain := NewShotView(ctl, w, h);
    try
      plain.ColorScheme.Foreground := RGBToColor($30, $30, $60);
      plain.ColorScheme.Background := RGBToColor($FF, $F4, $E0);
      plain.ColorScheme.Red := RGBToColor($E0, $00, $70);
      plain.ColorSource := tsrcScheme;
      plain.WriteSync(pal);
      SaveShot(plain, 'scheme-partial-default-light.png', 'default', 'light', 96,
        '方案只设了前景（#303060）、底色（#FFF4E0）、红（#E00070）：其余 15 色跟主题（浅底那套）');
    finally
      plain.Free;
    end;
  finally
    ctl.Free;
  end;
  { 7. the selection at 0.3 of Campbell's (unset: WT's #FFFFFF) over its ground }
  sel := #27'[?25l'
    + '$ echo ' + Utf8($9009) + Utf8($533A) + Utf8($6D4B) + Utf8($8BD5) + ' selection test'#13#10
    + Utf8($4E2D) + Utf8($6587) + Utf8($4E0E) + ' English ' + Utf8($6DF7) + Utf8($6392)
    + ', see https://example.com/docs here'#13#10
    + Utf8($7B2C) + Utf8($4E09) + Utf8($884C) + ' third line 12345'#13#10;
  ShootScheme('scheme-selection-unfocused-campbell.png', 'default', 'light', sel, 60, 4,
    'Campbell 的选区（#FFFFFF 降到 0.3，在底色 #0C0C0C 上混成 #555555），失焦：没设失焦色，用同一色', 'Campbell', '',
    spSelection);
  ShootScheme('scheme-selection-focused-campbell.png', 'default', 'light', sel, 60, 4,
    '同上，聚焦', 'Campbell', '', spSelectionFocused);
  { 8. the scheme sets an unfocused selection colour: unfocused, that one is used (cyan at
    0.3), not the focused one (the grey above) }
  ctl := TTyStyleController.Create(nil);
  try
    ctl.ThemeName := 'default';
    ctl.Mode := 'light';
    plain := NewShotView(ctl, 60, 4);
    try
      plain.ColorScheme.LoadFromText(SchemeText, 'Campbell');
      plain.ColorScheme.SelectionInactiveBackground := RGBToColor($00, $FF, $FF);
      plain.ColorSource := tsrcScheme;
      plain.WriteSync(sel);
      plain.Prepare(spSelection);
      SaveShot(plain, 'scheme-selection-inactive-campbell.png', 'default', 'light', 96,
        'Campbell 另设了失焦选区色 #00FFFF：失焦时用它（降到 0.3，在 #0C0C0C 上混成偏青的 #085555），'
        + '不是聚焦那一色（对照前两张的灰 #555555）');
    finally
      plain.Free;
    end;
  finally
    ctl.Free;
  end;
end;

{ ---- phase 7: ZModem in the terminal ------------------------------------------------------ }

type
  { the example's glue on a shot view: a clock the shots set, a download folder answered
    at once (no dialog off screen) }
  TZmShot = class
  public
    Now_: Double;
    Dir: string;
    Zm: TZmodemStreamHandler;
    function Clock: Double;
    procedure OnDownload(Sender: TObject);
  end;

function TZmShot.Clock: Double;
begin
  Result := Now_;
end;

procedure TZmShot.OnDownload(Sender: TObject);
begin
  Zm.AcceptDownload(Dir);
end;

function ZmRecording(const AName: string): RawByteString;
var
  f: TFileStream;
begin
  f := TFileStream.Create(ExpandFileName(ExtractFilePath(ParamStr(0)) + '../../tests/fixtures/terminal-zmodem/' + AName),
    fmOpenRead or fmShareDenyWrite);
  try
    Result := '';
    SetLength(Result, f.Size);
    if f.Size > 0 then
      f.ReadBuffer(Result[1], f.Size);
  finally
    f.Free;
  end;
end;

procedure RemoveShotDir(const ADir: string);
var
  sr: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
        DeleteFile(IncludeTrailingPathDelimiter(ADir) + sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  RemoveDir(ADir);
end;

{ AHow: 0 = the progress line half way, 1 = done and the prompt after it, 2 = behind
  ConPTY, 3 = a local selection while claimed (the program wanted the mouse) }
procedure ShootZmodem(const AFile, AMode: string; AHow: Integer; const AWhat: string);
const
  Cols = 72;
  Rows = 8;
var
  ctl: TTyStyleController;
  v: TShotView;
  z: TZmShot;
  sz: RawByteString;
  pty: TTyTerminalWindowsPty;
  p, n, stop: Integer;
begin
  sz := ZmRecording('big-block.sz.bin');
  ctl := TTyStyleController.Create(nil);
  z := TZmShot.Create;
  try
    ctl.ThemeName := 'default';
    ctl.Mode := AMode;
    z.Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tyzm-shots-' + IntToStr(GetTickCount64);
    ForceDirectories(z.Dir);
    z.Now_ := 1000;
    v := NewShotView(ctl, Cols, Rows);
    try
      z.Zm := TZmodemStreamHandler.Create(v.Core);
      try
        z.Zm.Clock := @z.Clock;
        z.Zm.OnDownloadRequest := @z.OnDownload;
        if AHow = 2 then
        begin
          pty.Backend := twpConPty;
          pty.BuildNumber := 19044;
          v.Core.WindowsPty := pty;
        end;
        if AHow = 3 then
          v.WriteSync('$ cat notes.txt'#13#10'The ZModem transfer keeps the stream,'#13#10
            + 'the mouse selects text on this side.'#13#10#27'[?1000h');
        v.WriteSync(#27'[?25l$ sz big.bin'#13#10);
        { the recording in 500-byte reads, 40 ms apart: the progress line at its pace }
        case AHow of
          0: stop := 11000;
          1: stop := Length(sz);
          2: stop := 24;                 { "rz" and the ZRQINIT: what sz says before it waits }
        else
          stop := 400;
        end;
        p := 1;
        while p <= stop do
        begin
          n := 500;
          if p + n - 1 > stop then n := stop - p + 1;
          z.Now_ := z.Now_ + 40;
          v.WriteSync(Copy(sz, p, n));
          Inc(p, n);
        end;
        if AHow = 1 then
          v.WriteSync('$ ');
        if AHow = 3 then
          v.Prepare(spSelectionFocused);
        SaveShot(v, AFile, 'default', AMode, 96, AWhat);
      finally
        z.Zm.Free;
      end;
    finally
      v.Free;
    end;
  finally
    RemoveShotDir(z.Dir);
    z.Free;
    ctl.Free;
  end;
end;

procedure Phase7;
const
  Modes: array[0..1] of string = ('light', 'dark');
var
  m: Integer;
begin
  Index.Add('# 终端 7 期验收截图');
  Index.Add('');
  Index.Add('`tools/terminal-shots` 离屏画出来的（不开窗口，控件自己的 RenderTo），Windows、默认字体、96 PPI。传输走真的 Core 和示例的 ZModem（`uzmodemterm`），喂的是 lrzsz 自己的录制 `tests/fixtures/terminal-zmodem/big-block.sz.bin`（`sz -8`，20000 字节），时钟注入（每 500 字节 40 ms），所以数字每次一样。重新生成：编 `tools/terminal-shots/terminalshots.lpi`，跑 `terminalshots --phase7`。');
  Index.Add('');
  Index.Add('| 文件 | 主题 | 明暗 | 看什么 |');
  Index.Add('|---|---|---|---|');
  for m := 0 to 1 do
    ShootZmodem(Format('zmodem-progress-%s.png', [Modes[m]]), Modes[m], 0,
      '传输到一半：`sz` 打的 `rz` 被进度行原地盖掉，一行：箭头、文件名、已收 / 总大小、百分比、速度');
  for m := 0 to 1 do
    ShootZmodem(Format('zmodem-done-%s.png', [Modes[m]]), Modes[m], 1,
      '传完：进度行换成摘要（文件数、大小、用时、平均速度），下一行是交还之后程序接着输出的提示符 `$ `');
  ShootZmodem('zmodem-conpty-refused.png', 'light', 2,
    'ConPTY 后面：终端里一行说明 ConPTY 会改坏二进制数据、请改用管道模式，`sz` 收到中止序列');
  ShootZmodem('claimed-selection.png', 'light', 3,
    '程序开着鼠标（1000）时接管：拖动出的是本地选区（程序拿不到这次拖动），传输照常');
end;

var
  names: TStringArray;
  i, m, w, h, k: Integer;
  data: RawByteString;
  mode, rec, what: string;
  doPhase4, doPhase5, doPhase6, doPhase7: Boolean;
const
  Modes: array[0..1] of string = ('light', 'dark');
  Singles: array[0..2] of string = ('vim-edit.cast', 'htop-few-frames.cast', 'cat-cjk-emoji.cast');
  YellowThemes: array[0..2] of string = ('xp', 'macos', 'breeze');
begin
  TyFallbackFontName := {$IFDEF MSWINDOWS}'Segoe UI'{$ELSE}''{$ENDIF};
  doPhase4 := False;
  doPhase5 := False;
  doPhase6 := False;
  doPhase7 := False;
  for i := 1 to ParamCount do
  begin
    if ParamStr(i) = '--phase4' then doPhase4 := True;
    if ParamStr(i) = '--phase5' then doPhase5 := True;
    if ParamStr(i) = '--phase6' then doPhase6 := True;
    if ParamStr(i) = '--phase7' then doPhase7 := True;
  end;
  if doPhase7 then
    OutDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../../docs/superpowers/plans/2026-09-30-terminal-phase-7-shots')
  else if doPhase6 then
    OutDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../../docs/superpowers/plans/2026-09-30-terminal-phase-6-shots')
  else if doPhase5 then
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
    if doPhase7 then
    begin
      Phase7;
      Index.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + 'index.md');
      WriteLn('done: ', OutDir);
      Exit;
    end;
    if doPhase6 then
    begin
      Phase6;
      Index.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + 'index.md');
      WriteLn('done: ', OutDir);
      Exit;
    end;
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
