{ 拿 examples/containers 的**真窗体**做真机确认。

  加载的就是 example 自己的 umain + umain.lfm(TTyForm + TTyFormSurface + 完整主题),
  不是复刻件;只把窗口挪到屏幕外,免得 1200x890 的 poScreenCenter 弹在正在用电脑的人脸上。
  然后把 ScrollDemo / PanDemo 各存一张 PNG,并打印它们的滚动条状态。

  用法:exampleshot.exe [输出目录] }
program exampleshot;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Graphics, Controls, Classes, SysUtils, Types,
  tyControls.Types, tyControls.Controller, tyControls.ScrollBar, tyControls.ScrollBox,
  umain;

var
  OutDir: string;
  MainForm: TMainForm;

function BarOf(ABox: TTyScrollBox; AKind: TTyScrollBarKind): TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ABox.ControlCount - 1 do
    if (ABox.Controls[i] is TTyScrollBar)
       and (TTyScrollBar(ABox.Controls[i]).Kind = AKind) then
      Exit(TTyScrollBar(ABox.Controls[i]));
end;

var
  LogF: TextFile;
  LogOpen: Boolean = False;

{ 分步日志:每一步都落盘并 flush,卡住时能看出卡在哪一行。 }
procedure Step(const AMsg: string);
begin
  WriteLn(AMsg);
  Flush(Output);
  if LogOpen then
  begin
    WriteLn(LogF, AMsg);
    Flush(LogF);
  end;
end;

procedure Report(const AName: string; ABox: TTyScrollBox);
var
  V, H: TTyScrollBar;

  function S(ABar: TTyScrollBar): string;
  begin
    if ABar = nil then Exit('<nil>');
    Result := Format('visible=%s (%d,%d %dx%d) max=%d page=%d',
      [BoolToStr(ABar.Visible, True), ABar.Left, ABar.Top, ABar.Width, ABar.Height,
       ABar.Max, ABar.PageSize]);
  end;

begin
  V := BarOf(ABox, sbVertical);
  H := BarOf(ABox, sbHorizontal);
  Step(Format('%s  %dx%d  content=%dx%d  scroll=(%d,%d)',
    [AName, ABox.Width, ABox.Height, ABox.ContentWidth, ABox.ContentHeight,
     ABox.ScrollX, ABox.ScrollY]));
  Step('    vbar: ' + S(V));
  Step('    hbar: ' + S(H));
end;

procedure Shot(AControl: TWinControl; const AName: string);
var
  bmp: TBitmap;
  png: TPortableNetworkGraphic;
begin
  Application.ProcessMessages;
  bmp := TBitmap.Create;
  png := TPortableNetworkGraphic.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AControl.Width, AControl.Height);
    bmp.Canvas.Brush.Color := clFuchsia;
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    AControl.PaintTo(bmp.Canvas, 0, 0);
    png.Assign(bmp);
    png.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + AName + '.png');
    Step('    shot  ' + AName + '.png');
  finally
    png.Free;
    bmp.Free;
  end;
end;

{ 把 AlignScrollDemo 的子控件按"子控件表顺序"整个倒出来:Align、bounds、AutoSize，
  以及相邻两行之间的间隙(0 = 首尾相接,负 = 重叠)。 }
procedure DumpRows;
var
  i, prevBottom: Integer;
  c: TControl;
  gap: string;
begin
  prevBottom := MaxInt;
  for i := 0 to MainForm.AlignScrollDemo.ControlCount - 1 do
  begin
    c := MainForm.AlignScrollDemo.Controls[i];
    if c is TTyScrollBar then Continue;
    if prevBottom = MaxInt then
      gap := ''
    else
      gap := Format('  gap=%d', [c.Top - prevBottom]);
    Step(Format('    [%d] %-8s align=%d autosize=%s (%d,%d %dx%d)%s',
      [i, c.Name, Ord(c.Align), BoolToStr(c.AutoSize, True),
       c.Left, c.Top, c.Width, c.Height, gap]));
    prevBottom := c.Top + c.Height;
  end;
end;

var
  V: TTyScrollBar;
begin
  OutDir := ExtractFilePath(ParamStr(0));
  if ParamCount >= 1 then OutDir := ParamStr(1);
  ForceDirectories(OutDir);

  AssignFile(LogF, IncludeTrailingPathDelimiter(OutDir) + 'exampleshot.log');
  Rewrite(LogF);
  LogOpen := True;

  Step('01 Application.Initialize');
  Application.Initialize;
  Step('02 CreateForm');
  Application.CreateForm(TMainForm, MainForm);
  Step('03 move off-screen');
  MainForm.Position := poDesigned;      { 别跑到屏幕中央去 }
  MainForm.Left := -3000;
  MainForm.Top := 100;
  Step('04 Show');
  MainForm.Show;
  Step('05 ProcessMessages');
  Application.ProcessMessages;

  Step('06 report ScrollDemo');
  Report('ScrollDemo', MainForm.ScrollDemo);
  Step('07 shot top');
  Shot(MainForm.ScrollDemo, 'ex-scrolldemo-top');

  Step('08 find vbar');
  V := BarOf(MainForm.ScrollDemo, sbVertical);
  if (V <> nil) and V.Visible then
  begin
    Step('09 set Position := Max');
    V.Position := V.Max;                { 拖到底 }
    Step('10 ProcessMessages after scroll');
    Application.ProcessMessages;
    Step('11 report scrolled');
    Report('ScrollDemo(拖到底)', MainForm.ScrollDemo);
    Step('12 shot bottom');
    Shot(MainForm.ScrollDemo, 'ex-scrolldemo-bottom');
  end;

  { 对齐子控件的滚动框 —— example 里唯一覆盖"滚动框当容器用"这条路径的地方。 }
  Step('12a 四行的真实堆叠(alTop 应当首尾相接,不重叠不留缝)');
  DumpRows;
  Step('12b report AlignScrollDemo');
  Report('AlignScrollDemo', MainForm.AlignScrollDemo);
  Step(Format('    AsBtn1=(%d,%d %dx%d)  AsBtn4=(%d,%d %dx%d)',
    [MainForm.AsBtn1.Left, MainForm.AsBtn1.Top, MainForm.AsBtn1.Width, MainForm.AsBtn1.Height,
     MainForm.AsBtn4.Left, MainForm.AsBtn4.Top, MainForm.AsBtn4.Width, MainForm.AsBtn4.Height]));
  Shot(MainForm.AlignScrollDemo, 'ex-alignscroll-top');

  V := BarOf(MainForm.AlignScrollDemo, sbVertical);
  if (V <> nil) and V.Visible then
  begin
    Step('12c AlignScrollDemo 拖到底');
    V.Position := V.Max;
    Application.ProcessMessages;
    Report('AlignScrollDemo(拖到底)', MainForm.AlignScrollDemo);
    Step(Format('    AsBtn1=(%d,%d %dx%d)  AsBtn4=(%d,%d %dx%d)  视口高=%d',
      [MainForm.AsBtn1.Left, MainForm.AsBtn1.Top, MainForm.AsBtn1.Width, MainForm.AsBtn1.Height,
       MainForm.AsBtn4.Left, MainForm.AsBtn4.Top, MainForm.AsBtn4.Width, MainForm.AsBtn4.Height,
       MainForm.AlignScrollDemo.Height]));
    Shot(MainForm.AlignScrollDemo, 'ex-alignscroll-bottom');
  end
  else
    Step('    !! AlignScrollDemo 没有垂直条(内容 112 > 视口 76,本该有)');

  Step('13 report PanDemo');
  Report('PanDemo', MainForm.PanDemo);
  Step('14 shot PanDemo');
  Shot(MainForm.PanDemo, 'ex-pandemo');

  Step('15 done');
  CloseFile(LogF);
  MainForm.Hide;
end.
