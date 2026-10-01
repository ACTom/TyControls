program tbshots;
{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{ Screenshots of the theme builder for its acceptance sheet
  (docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md, "截图"): the seeds page on
  win11, the export dialog on green, the AI settings (the five presets, a fake key), the AI
  page with an answer and the comparison window.

  The windows are the tool's own, built for real from tools/themebuilder (no package), the way
  tests/test.themebuilder.main does: the settings go to a temporary folder (SettingsFileForTest),
  every question is answered by PromptAnswerForTest, and the comparison window arrives through
  ShowModalForTest -- nothing calls ShowModal, nothing pops a message box. The AI never reaches
  a service: the session's backend is the tests' scripted one (tests/tbaitesthelp), which
  answers from a fixed text; the only key typed anywhere is sk-test-0000, and it is never
  saved.

  A window is shown off the screen (Left = -10000, not on the task bar) and drawn into a bitmap
  through PrintWindow(flags 0): the window paints itself, title bar and all, into our DC -- that
  one window, not the screen, so a locked or covered desktop does not matter and nothing else on
  the desktop is captured. (PW_RENDERFULLCONTENT was tried first: off the screen it hands back
  DWM's copy of the window, blank at first and stale later.)
  If PrintWindow leaves it blank the form's own PaintTo is the fallback (the index says which
  one a picture took). A picture of one colour (all black, all white, the sentinel) is an
  error: nothing is written and the exit code is 1.

  No DPI-aware manifest: the process runs at 96 PPI whatever the screen is. No translation is
  loaded: the interface is the English of the sources.

    tbshots [--out <dir>] [--onscreen]

  Writes the PNGs and index.md into <dir> (default
  docs/superpowers/plans/2026-10-01-themebuilder-acceptance-shots under the repository).
  --onscreen shows the windows at the top left corner of the screen instead (for a system
  where PrintWindow cannot draw a window off the screen). Run it with its output redirected
  to a file. }

uses
  Interfaces, Windows, Classes, SysUtils, FileUtil, LazFileUtils, Forms, Controls, Graphics,
  Dialogs, BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tbmain, tbtemplates, tbdiff, tbaiformat, tbaiclient, tbaisettings, tbaisession,
  tbaiframe, tbcompareform, tbexportform, tbaisettingsform, tbaitesthelp;

function PrintWindow(AWnd: HWND; ADC: HDC; AFlags: UINT): BOOL; stdcall;
  external 'user32' name 'PrintWindow';

const
  cSentinel = $00FF00FF;      { magenta, B G R X: what PrintWindow did not paint over }
  cMinColours = 16;           { a real window has far more (anti-aliased text) }
  cMaxBytes = 400 * 1024;
  cFakeKey = 'sk-test-0000';
  cPrompt = 'Warm colours, and a bit more rounding.';

type
  TSeen = array[0..cMinColours] of DWord;

  THooks = class
    procedure AppException(Sender: TObject; E: Exception);
    procedure CompareShown(Sender: TObject);
  end;

var
  RepoDir, OutDir, TmpDir: string;
  OnScreen: Boolean;
  Index: TStringList;
  Main: TTbMainForm;
  Hooks: THooks;
  Failed: Boolean;
  Written: Integer;

procedure Log(const S: string);
begin
  WriteLn(S);
  Flush(Output);
end;

procedure Fail(const S: string);
begin
  Failed := True;
  Log('ERROR: ' + S);
end;

procedure THooks.AppException(Sender: TObject; E: Exception);
begin
  { never the LCL's message box: said here, and the run fails }
  Fail('exception in the message loop: ' + E.ClassName + ': ' + E.Message);
end;

{ let the windows paint, the timers fire, the queued calls run }
procedure Pump(AMs: Integer);
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  repeat
    Application.ProcessMessages;
    Sleep(10);
  until GetTickCount64 - t0 >= QWord(AMs);
  Application.ProcessMessages;
end;

{ off the screen (or at the corner), and kept off the task bar }
procedure Place(AForm: TCustomForm);
begin
  AForm.Position := poDesigned;
  AForm.ShowInTaskBar := stNever;
  if OnScreen then
  begin
    AForm.Left := 0;
    AForm.Top := 0;
  end
  else
  begin
    AForm.Left := -10000;
    AForm.Top := 100;
  end;
end;

function CountColours(ABmp: TBGRABitmap; out ASentinel: Int64): Integer;
var
  seen: TSeen;
  p: PBGRAPixel;
  i, k: Integer;
  c: DWord;
  known: Boolean;
begin
  seen := Default(TSeen);
  Result := 0;
  ASentinel := 0;
  p := ABmp.Data;
  for i := 0 to ABmp.NbPixels - 1 do
  begin
    c := (DWord(p^.red) shl 16) or (DWord(p^.green) shl 8) or p^.blue;
    if c = $FF00FF then
      Inc(ASentinel);
    if Result <= cMinColours then
    begin
      known := False;
      for k := 0 to Result - 1 do
        if seen[k] = c then
        begin
          known := True;
          Break;
        end;
      if not known then
      begin
        seen[Result] := c;
        Inc(Result);
      end;
    end;
    Inc(p);
  end;
end;

{ the window as Windows renders it, into ABmp; False when nothing was drawn }
function ByPrintWindow(AForm: TCustomForm; ABmp: TBGRABitmap; AFlags: UINT): Boolean;
var
  r: TRect;
  w, h, i, x, y: Integer;
  bi: TBitmapInfo;
  bits: Pointer;
  dc: HDC;
  hb, old: HBITMAP;
  src: PDWord;
  dst: PBGRAPixel;
begin
  Result := False;
  GetWindowRect(AForm.Handle, r);
  w := r.Right - r.Left;
  h := r.Bottom - r.Top;
  if (w <= 0) or (h <= 0) then Exit;
  FillChar(bi, SizeOf(bi), 0);
  bi.bmiHeader.biSize := SizeOf(bi.bmiHeader);
  bi.bmiHeader.biWidth := w;
  bi.bmiHeader.biHeight := -h;          { top-down }
  bi.bmiHeader.biPlanes := 1;
  bi.bmiHeader.biBitCount := 32;
  bi.bmiHeader.biCompression := BI_RGB;
  dc := CreateCompatibleDC(0);
  bits := nil;
  hb := CreateDIBSection(dc, bi, DIB_RGB_COLORS, bits, 0, 0);
  if (hb = 0) or (bits = nil) then
  begin
    DeleteDC(dc);
    Exit;
  end;
  old := SelectObject(dc, hb);
  try
    src := bits;
    for i := 0 to w * h - 1 do
    begin
      src^ := cSentinel;
      Inc(src);
    end;
    if not PrintWindow(AForm.Handle, dc, AFlags) then Exit;
    GdiFlush;
    ABmp.SetSize(w, h);
    src := bits;
    for y := 0 to h - 1 do
    begin
      dst := ABmp.ScanLine[y];   { a TBGRABitmap on Windows is stored bottom-up }
      for x := 0 to w - 1 do
      begin
        dst^.blue := src^ and $FF;
        dst^.green := (src^ shr 8) and $FF;
        dst^.red := (src^ shr 16) and $FF;
        dst^.alpha := 255;
        Inc(src);
        Inc(dst);
      end;
    end;
    ABmp.InvalidateBitmap;
    Result := True;
  finally
    SelectObject(dc, old);
    DeleteObject(hb);
    DeleteDC(dc);
  end;
end;

{ the fallback: the form paints itself and its children into a bitmap (client area) }
function ByPaintTo(AForm: TCustomForm; ABmp: TBGRABitmap): Boolean;
var
  bmp: TBitmap;
  tmp: TBGRABitmap;
begin
  Result := False;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(AForm.ClientWidth, AForm.ClientHeight);
    bmp.Canvas.Brush.Color := RGBToColor(255, 0, 255);
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    AForm.PaintTo(bmp.Canvas, 0, 0);
    tmp := TBGRABitmap.Create(bmp);
    try
      ABmp.Assign(tmp);
    finally
      tmp.Free;
    end;
    Result := True;
  finally
    bmp.Free;
  end;
end;

function Acceptable(ABmp: TBGRABitmap; out AWhy: string): Boolean;
var
  n: Integer;
  sentinel: Int64;
begin
  n := CountColours(ABmp, sentinel);
  AWhy := '';
  if n < cMinColours then
    AWhy := Format('only %d colours', [n])
  else if sentinel * 100 > Int64(ABmp.NbPixels) then
    AWhy := Format('%d pixels left unpainted', [sentinel]);
  Result := AWhy = '';
end;

{ AForm as it is now into OutDir\AFile, with its index line }
procedure Capture(AForm: TCustomForm; const AFile, AItems, AWhat, AHow: string);
var
  bmp: TBGRABitmap;
  why, method, path: string;
  ok: Boolean;
  sz: Int64;
begin
  bmp := TBGRABitmap.Create(1, 1);
  try
    method := 'PrintWindow';
    { flags 0: WM_PRINT, the window paints itself into our DC, now. Not PW_RENDERFULLCONTENT:
      off the screen that hands back DWM's copy of the window, which was blank on the first
      call and stale (the page shown a while ago) on later ones -- measured on Windows 10 }
    ok := ByPrintWindow(AForm, bmp, 0) and Acceptable(bmp, why);
    if not ok then
    begin
      Log(Format('%s: PrintWindow gave nothing usable (%s); PaintTo instead', [AFile, why]));
      method := 'PaintTo（PrintWindow 为空，退回）';
      ok := ByPaintTo(AForm, bmp) and Acceptable(bmp, why);
    end;
    if not ok then
    begin
      Fail(Format('%s: not written, the picture is blank (%s)', [AFile, why]));
      Exit;
    end;
    path := IncludeTrailingPathDelimiter(OutDir) + AFile;
    bmp.SaveToFile(path);
    sz := FileSizeUtf8(path);
    if sz > cMaxBytes then
    begin
      DeleteFile(path);
      Fail(Format('%s: %d bytes, over the %d limit', [AFile, sz, cMaxBytes]));
      Exit;
    end;
    Inc(Written);
    if method = 'PrintWindow' then
      Log(Format('%s: %dx%d, %d bytes, PrintWindow', [AFile, bmp.Width, bmp.Height, sz]))
    else
      Log(Format('%s: %dx%d, %d bytes, PaintTo fallback', [AFile, bmp.Width, bmp.Height, sz]));
    Index.Add(Format('| `%s` | %s | %s | %s；%s |', [AFile, AItems, AWhat, AHow, method]));
  finally
    bmp.Free;
  end;
end;

procedure ShowAndSettle(AForm: TCustomForm);
begin
  Place(AForm);
  AForm.Show;
  Pump(700);
end;

function FindRepo: string;
var
  dir: string;
  i: Integer;
begin
  dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(dir + 'themes' + PathDelim + 'builtin') and DirectoryExists(dir + 'source') then
      Exit(dir);
    dir := ExtractFilePath(ExcludeTrailingPathDelimiter(dir));
    if dir = '' then Break;
  end;
  Result := '';
end;

procedure ReadArgs;
var
  i: Integer;
begin
  OutDir := RepoDir + 'docs' + PathDelim + 'superpowers' + PathDelim + 'plans' + PathDelim +
    '2026-10-01-themebuilder-acceptance-shots';
  i := 1;
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '--out') and (i < ParamCount) then
    begin
      Inc(i);
      OutDir := ExpandFileName(ParamStr(i));
    end
    else if ParamStr(i) = '--onscreen' then
      OnScreen := True;
    Inc(i);
  end;
  ForceDirectories(OutDir);
end;

{ ---- the pictures ---- }

procedure ShootSeeds;
begin
  if not Main.OpenFile(RepoDir + 'themes' + PathDelim + 'builtin' + PathDelim + 'win11.tycss') then
  begin
    Fail('could not open win11.tycss: ' + Main.LastAsk);
    Exit;
  end;
  Main.SideBar.Collapsed := False;
  Main.SideBar.ActivateWindow(Main.SeedsWin);
  Main.RefreshNow;
  Pump(700);
  Capture(Main, 'p2-seeds-win32.png', '30、33',
    '主窗口，打开 `themes/builtin/win11.tycss`，侧栏在「种子」页：亮 / 暗两列，`--surface`、`--on-surface` 写「inherited」，圆角两列写「from :root」，色块与右边预览（win11 亮色）一致',
    '`OpenFile` 打开文件，侧栏 `ActivateWindow(SeedsWin)`');
end;

procedure ShootExport;
var
  f: TTbExportForm;
begin
  if not Main.OpenFile(RepoDir + 'themes' + PathDelim + 'green.tycss') then
  begin
    Fail('could not open green.tycss: ' + Main.LastAsk);
    Exit;
  end;
  Main.RefreshNow;
  Pump(300);
  f := Main.BuildExportForm;
  try
    ShowAndSettle(f);
    Capture(f, 'p2-export-win32.png', '43、44',
      '导出对话框，文档是 `themes/green.tycss`：文件列表里有 `assets/background.jpg`，zip 选项灰掉并写了原因，默认导出成文件夹',
      '`BuildExportForm` 建好后非模态 `Show`，截完关掉，什么都没导出');
    f.Hide;
  finally
    f.Free;
  end;
end;

procedure ShootAiSettings;
var
  f: TTbAiSettingsForm;
  p: TTbAiPreset;
begin
  f := Main.BuildAiSettingsForm;
  try
    for p := Low(TTbAiPreset) to High(TTbAiPreset) do
      f.AddPreset(p);
    { Anthropic: claude-sonnet-5, maximum output 32000; the key a fake one, masked anyway }
    f.SelectProfile(Ord(tapAnthropic));
    f.EdtKey.Text := cFakeKey;
    ShowAndSettle(f);
    Capture(f, 'p3-ai-settings-win32.png', '54',
      'AI 设置：左边五种预置都加上了，选中 Anthropic（模型 `claude-sonnet-5`、最大输出 32000），密钥框是假密钥（显示为星号）；底下有「会发给这里设置的服务」与密钥怎么存的说明',
      '`BuildAiSettingsForm` 后 `AddPreset` 五次、`SelectProfile`，密钥填 `' + cFakeKey + '`；非模态 `Show`，不点确定、什么都不保存');
    { the local preset: the Ollama context hint under the fields }
    f.SelectProfile(Ord(tapOllama));
    Pump(300);
    Capture(f, 'p3-ai-settings-ollama-win32.png', '54',
      '同一窗口选中「Local (Ollama)」：地址是本机，字段下出现 Ollama 上下文长度的提示（提示的第三行被下面的「Test connection」挡住，是工具本身的排版，不是截图的问题）',
      '同上一张，`SelectProfile` 换到本机预置');
    f.Hide;
  finally
    f.Free;
  end;
end;

{ the AI's version: the minimal template, warmer and rounder }
function WarmCandidate: string;

  procedure Swap(var S: string; const AOld, ANew: string);
  begin
    S := StringReplace(S, AOld, ANew, []);
  end;

begin
  Result := TbNormalizeEol(TbMinimalTemplate);
  { light }
  Swap(Result, '--accent: #3B82F6;', '--accent: #EA580C;');
  Swap(Result, '--surface: #FFFFFF;', '--surface: #FFFBF5;');
  Swap(Result, '--on-surface: #1F2937;', '--on-surface: #292524;');
  Swap(Result, '--border: #D1D5DB;', '--border: #E7D8C9;');
  Swap(Result, '--radius: 6px;', '--radius: 10px;');
  { dark (the first of each left, the dark block's are the next ones) }
  Swap(Result, '--accent: #60A5FA;', '--accent: #FB923C;');
  Swap(Result, '--surface: #1E1E1E;', '--surface: #1C1917;');
  Swap(Result, '--on-surface: #E5E7EB;', '--on-surface: #F5F5F4;');
  Swap(Result, '--border: #3F3F46;', '--border: #44403C;');
  Swap(Result, '--radius: 6px;', '--radius: 10px;');
end;

procedure THooks.CompareShown(Sender: TObject);
var
  f: TTbCompareForm;
begin
  if not (Sender is TTbCompareForm) then
  begin
    { the AI settings window: never expected here; left as cancelled }
    TCustomForm(Sender).ModalResult := mrCancel;
    Exit;
  end;
  f := TTbCompareForm(Sender);
  { the page first, as the answer finished (the comparison is opening) }
  Main.Ai.FlushOutput;
  Pump(400);
  Capture(Main, 'p3-ai-page-win32.png', '57',
    '主窗口，极简模板，侧栏在「AI」页：描述「' + cPrompt + '」，输出框里是模型的回答（**假后端**：测试用的脚本模型分 12 段流出一段固定回答，不连任何服务）',
    '服务是指向 127.0.0.1 的自定义预置，会话的后端换成 `tests/tbaitesthelp` 的 `TScriptedBackend`，`GenerateClick`');
  ShowAndSettle(f);
  Capture(f, 'p3-compare-win32.png', '57、69',
    '对比窗口：左「Now」是编辑器的极简模板，右是 AI 的版本（暖色、圆角 10px），改动行左红右绿、两边对齐，顶上一句「4 changes. Problems left: 0.」（**假后端**的回答）。注意改动行上的字是很浅的灰白色，几乎看不清——工具本身的绘制，不是截图的问题',
    '生成结束后主窗口经 `ShowModalForTest` 交来的对比窗口，非模态 `Show` 截图后按「放弃」的结果关掉');
  f.Hide;
  f.ModalResult := mrCancel;
end;

procedure ShootAi;
var
  prof: TTbAiProfile;
  b: TScriptedBackend;
begin
  Main.NewMinimal;
  prof := TbPresetProfile(tapCustom);
  prof.Name := 'Local test service';
  prof.BaseUrl := 'http://127.0.0.1:8080/v1';
  prof.Model := 'scripted';
  Main.AiSettings.Put(prof);
  Main.AiSettings.CurrentId := prof.Id;
  Main.Ai.RefreshProfiles;
  { the backend RefreshProfiles made is replaced before anything is sent: no request leaves }
  b := TScriptedBackend.Create;
  b.Add(TbAnswerWith(WarmCandidate,
    'Here is a warmer version: an orange accent, cream and stone surfaces, and a 10px radius in both modes.'),
    aekNone, 200, 12);
  Main.Ai.Session.Backend := b;
  Main.SideBar.Collapsed := False;
  Main.SideBar.ActivateWindow(Main.AiWin);
  Main.RefreshNow;
  Pump(500);
  Main.Ai.EdtPrompt.Text := cPrompt;
  TTbMainForm.ShowModalForTest := @Hooks.CompareShown;
  try
    Main.Ai.GenerateClick(nil);
    Pump(800);        { the comparison opens from the application's queue: CompareShown }
  finally
    TTbMainForm.ShowModalForTest := nil;
  end;
  if b.Starts = 0 then
    Fail('the AI session never started');
  if not FileExists(IncludeTrailingPathDelimiter(OutDir) + 'p3-compare-win32.png') then
    Fail('the comparison window never came: ' + Main.Ai.LblStatus.Caption);
end;

procedure WriteIndex;
var
  head: TStringList;
begin
  head := TStringList.Create;
  try
    head.Add('# 主题编辑器验收截图');
    head.Add('');
    head.Add('验收单 `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md` 「截图」一节引用的图。'
      + '由 `tools/themebuilder-shots` 生成：在进程里真建工具的主窗口（与 `tests/test.themebuilder.main` 一样，'
      + '设置写临时目录、提问由测试缝作答、不调 `ShowModal`、不弹消息框），窗口放在屏幕外，'
      + '用 `PrintWindow`（flags 0，即让窗口自己经 WM_PRINT 把标题栏和全部内容画进位图）只渲染这一个窗口'
      + '（锁屏、被遮挡都不影响，截不到桌面上的别的东西）。实测 `PW_RENDERFULLCONTENT` 对屏幕外的窗口取的是 DWM 的副本：'
      + '第一次全空、之后是几秒前的旧画面，所以不用。'
      + 'Windows 10、96 PPI（工具不带 DPI 清单）、英文界面（不加载翻译）、工具默认外观。');
    head.Add('');
    head.Add('AI 的两张图用**假后端**：测试里的脚本模型（`tests/tbaitesthelp.pas` 的 `TScriptedBackend`）给一段固定回答，'
      + '不连任何服务；唯一出现过的密钥是假密钥 `sk-test-0000`（设置窗口里显示为星号，且从未保存）。'
      + '真实服务的生成（第 57 项）仍要验收时真机做。');
    head.Add('');
    head.Add('重新生成：`lazbuild -B tools/themebuilder-shots/tbshots.lpi`，再在仓库根跑 '
      + '`tools\themebuilder-shots\tbshots.exe > tbshots.log 2>&1`（输出重定向到文件）。'
      + '退出码 0 即全部写出；某张是纯色 / 空白就不写、退出码 1。`--out <目录>` 换输出目录，'
      + '`--onscreen` 把窗口放到屏幕左上角（屏幕外截不出时用）。');
    head.Add('');
    head.Add('| 文件 | 验收项 | 看什么 | 怎么得到 |');
    head.Add('|---|---|---|---|');
    head.AddStrings(Index);
    head.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + 'index.md');
  finally
    head.Free;
  end;
end;

begin
  Failed := False;
  Written := 0;
  Index := TStringList.Create;
  Hooks := THooks.Create;
  try
    try
      RepoDir := FindRepo;
      if RepoDir = '' then
        raise Exception.Create('the repository (themes/builtin, source) was not found above the exe');
      ReadArgs;
      Log('repository: ' + RepoDir);
      Log('output: ' + OutDir);

      RequireDerivedFormResource := True;
      Application.Title := 'Theme Builder';
      Application.Initialize;
      Application.OnException := @Hooks.AppException;

      TmpDir := IncludeTrailingPathDelimiter(GetTempDir(False)) +
        Format('tbshots-%d', [GetProcessID]) + PathDelim;
      ForceDirectories(TmpDir);
      TTbMainForm.SettingsFileForTest := TmpDir + 'themebuilder.ini';
      TTbMainForm.PromptAnswerForTest := mrNo;
      TTbMainForm.SaveAsNameForTest := '';
      TTbMainForm.ShowModalForTest := nil;

      Main := TTbMainForm.Create(nil);
      try
        Place(Main);
        Main.Show;
        Pump(800);
        Log(Format('screen PPI %d, window %dx%d at %d,%d', [Screen.PixelsPerInch, Main.Width,
          Main.Height, Main.Left, Main.Top]));
        ShootSeeds;
        ShootExport;
        ShootAiSettings;
        ShootAi;
        Main.Hide;
      finally
        FreeAndNil(Main);
      end;
      WriteIndex;
    except
      on E: Exception do
        Fail(E.ClassName + ': ' + E.Message);
    end;
  finally
    if (TmpDir <> '') and DirectoryExists(TmpDir) then
      DeleteDirectory(ExcludeTrailingPathDelimiter(TmpDir), False);
    Hooks.Free;
    Index.Free;
  end;
  Log(Format('%d pictures written', [Written]));
  if Failed then
    ExitCode := 1;
end.
