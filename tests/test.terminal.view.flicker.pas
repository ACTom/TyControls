unit test.terminal.view.flicker;
{$mode objfpc}{$H+}
{ 按键闪屏:真窗口上,一次重画的中间状态不能露出去。

  ConPTY 每按一个键吐一块:从光标行到最后一行逐行 CUP + 原样的字 + ECH(vim 里录的,每个键
  600–800 字节,一块里写完)。这些行内容没变、修订号变了,整行重画。离屏(RenderTo 到位图)
  每一帧都是完整的新行,录下来的字节逐块喂进去也复现不出来——闪烁出在真 WM_PAINT 的路上。
  所以这里用显示出来的窗体、真失效、真 UpdateWindow,在 Paint 进门时从窗口读回此刻的像素:
  LCL 已经做完它在 Paint 之前做的事,我们还没贴图,DWM 在这时合成一次,屏幕上就是它。它必须
  还是上一帧贴上去的像素。 }

interface

uses
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, LCLType, LCLIntf, fpcunit, testregistry,
  tyControls.Terminal, test.terminal.view;

type
  TTyTerminalViewFlickerTests = class(TTestCase)
  published
    procedure TestARepaintNeverShowsTheRowsErased;
  end;

implementation

{$IFDEF LCLWin32}
type
  { 一行网格的像素($RRGGBB),从窗口读回 }
  TRowPixels = array of Cardinal;

  { 每次 Paint:进门读回网格的每一行(擦除之后、贴图之前),和上一帧出门时读回的比 }
  TFlickerProbe = class(TTyTerminalViewProbe)
  private
    FPresented: array of TRowPixels;    { 每一行上一帧呈现出去的像素 }
    function GrabRow(ARow: Integer): TRowPixels;
  protected
    procedure Paint; override;
  public
    Recording: Boolean;
    Paints: Integer;
    { 进门时和上一帧呈现的不一样的行(次数);其中成了一片纯色、而上一帧有字的(次数) }
    Differed, Blanked: Integer;
    FirstBlanked: string;
    function PresentedHasInk(ARow: Integer): Boolean;
  end;

function Uniform(const A: TRowPixels): Boolean;
var
  i: Integer;
begin
  for i := 1 to High(A) do
    if A[i] <> A[0] then
      Exit(False);
  Result := True;
end;

function SameRow(const A, B: TRowPixels): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A) * SizeOf(Cardinal)));
end;

{ 窗口自己的 DC(Paint 的 DC 只读得到这次的更新区)BitBlt 进一张自上而下的 32 位 DIB }
function TFlickerProbe.GrabRow(ARow: Integer): TRowPixels;
var
  r: TRect;
  w, h, i: Integer;
  info: Windows.BITMAPINFO;
  bits: Pointer;
  dib: HBITMAP;
  src, mem: HDC;
  old: HGDIOBJ;
begin
  r := CellRect(0, ARow);
  r.Right := CellRect(Core.Cols - 1, ARow).Right;
  w := r.Right - r.Left;
  h := r.Bottom - r.Top;
  Result := nil;
  SetLength(Result, w * h);
  FillChar(info, SizeOf(info), 0);
  info.bmiHeader.biSize := SizeOf(info.bmiHeader);
  info.bmiHeader.biWidth := w;
  info.bmiHeader.biHeight := -h;
  info.bmiHeader.biPlanes := 1;
  info.bmiHeader.biBitCount := 32;
  info.bmiHeader.biCompression := BI_RGB;
  bits := nil;
  src := Windows.GetDC(Handle);
  mem := Windows.CreateCompatibleDC(src);
  dib := Windows.CreateDIBSection(mem, info, DIB_RGB_COLORS, bits, 0, 0);
  old := Windows.SelectObject(mem, dib);
  try
    Windows.BitBlt(mem, 0, 0, w, h, src, r.Left, r.Top, SRCCOPY);
    Windows.GdiFlush;
    Move(bits^, Result[0], w * h * SizeOf(Cardinal));
    for i := 0 to High(Result) do
      Result[i] := Result[i] and $FFFFFF;
  finally
    Windows.SelectObject(mem, old);
    Windows.DeleteObject(dib);
    Windows.DeleteDC(mem);
    Windows.ReleaseDC(Handle, src);
  end;
end;

function TFlickerProbe.PresentedHasInk(ARow: Integer): Boolean;
begin
  Result := (ARow <= High(FPresented)) and (Length(FPresented[ARow]) > 0) and not Uniform(FPresented[ARow]);
end;

procedure TFlickerProbe.Paint;
var
  r: Integer;
  now: TRowPixels;
begin
  if Recording and (Length(FPresented) = Core.Rows) then
    for r := 0 to Core.Rows - 1 do
    begin
      now := GrabRow(r);
      if (Length(FPresented[r]) > 0) and not SameRow(now, FPresented[r]) then
      begin
        Inc(Differed);
        if Uniform(now) and not Uniform(FPresented[r]) then
        begin
          Inc(Blanked);
          if FirstBlanked = '' then
            FirstBlanked := Format('paint %d, row %d', [Paints, r]);
        end;
      end;
    end;
  inherited Paint;
  Inc(Paints);
  SetLength(FPresented, Core.Rows);
  for r := 0 to Core.Rows - 1 do
    FPresented[r] := GrabRow(r);
end;

const
  Cols = 100;
  Rows = 30;

{ vim 打开一个 40 行的文件:29 行正文 + 状态行 }
function ScreenChunk: RawByteString;
var
  i: Integer;
begin
  Result := #27'[H';
  for i := 1 to Rows - 1 do
    Result := Result + 'line number ' + IntToStr(i) + #27'[K'#13#10;
  Result := Result + #27'[1m'#27'[97m-- REPLACE --'#27'[m' + #27'[H'#27'[?25h';
end;

{ 一个键(录下来的 A 键那一块的样子):第 1 行第 3 列改了一个字,其余各行从第 3 列起原样
  重写、ECH 擦到行尾;状态行;光标回来 }
function KeyChunk(AKey: Char): RawByteString;
var
  i: Integer;
  body: string;
begin
  Result := #27'[25l'#27'[1;3H' + AKey + 'e number 1'#27'[72X';
  for i := 2 to Rows - 1 do
  begin
    body := 'ne number ' + IntToStr(i);
    Result := Result + #27'[' + IntToStr(i) + ';3H' + body + #27'[' + IntToStr(Cols - 2 - Length(body)) + 'X';
  end;
  Result := Result + #27'[1m'#27'[97m'#27'[30;3H REPLACE --'#27'[m' + #27'[1;4H'#27'[?25h';
end;

{ 画到没有待画的行(光栅化预算留下的行下一帧补) }
procedure Pump(AView: TFlickerProbe);
var
  i: Integer;
begin
  AView.Update;
  for i := 1 to 200 do
  begin
    Forms.Application.ProcessMessages;
    if not AView.RowsPending then Break;
    AView.Update;
  end;
  for i := 1 to 5 do
    Forms.Application.ProcessMessages;
end;
{$ENDIF}

{ 真窗口上 vim 的几次按键:每次从第 1 行到最后一行整行重画。每次 Paint 进门时窗口上仍是
  上一帧呈现的像素——没有一行先成了一片底色。(Win32 上 LCL 在 WM_PAINT 里先发
  WM_ERASEBKGND,没开双缓冲时 TWinControl.EraseBackground 拿 Brush 把更新区直接填在窗口上;
  贴图要等这一帧的行都画完,这段时间 DWM 合成一次,那几行就闪成一片底色。) }
procedure TTyTerminalViewFlickerTests.TestARepaintNeverShowsTheRowsErased;
{$IFDEF LCLWin32}
var
  fx: TTyTermViewFixture;
  v: TFlickerProbe;
  sz: TSize;
  r, k, painted, paints: Integer;
  keys: string;
{$ENDIF}
begin
  {$IFNDEF LCLWin32}
  Ignore('reads the window back with GDI: Win32 only');
  {$ELSE}
  TyTermNeedWidgetSet;
  fx := TTyTermViewFixture.Create;
  try
    fx.View.Visible := False;
    v := TFlickerProbe.Create(fx.Form);
    v.Controller := fx.Ctl;
    v.Parent := fx.Form;
    sz := v.SizeForGrid(Cols, Rows);
    v.SetBounds(0, 0, sz.cx, sz.cy);
    fx.Form.SetBounds(60, 60, sz.cx + 40, sz.cy + 60);
    fx.Form.Show;
    for r := 1 to 20 do Forms.Application.ProcessMessages;
    AssertEquals('grid cols', Cols, v.Core.Cols);
    AssertEquals('grid rows', Rows, v.Core.Rows);
    v.Recording := True;
    v.WriteSync(ScreenChunk);
    Pump(v);
    for r := 0 to Rows - 2 do
      AssertTrue(Format('row %d shows its line before the keys', [r]), v.PresentedHasInk(r));
    v.Differed := 0;
    v.Blanked := 0;
    painted := v.PaintedRows;
    paints := v.Paints;
    keys := 'Axyz';
    for k := 1 to Length(keys) do
    begin
      v.WriteSync(KeyChunk(keys[k]));
      Pump(v);
    end;
    { 不是空转:每个键都把正文各行重画了一遍,也真的经 WM_PAINT 画到了窗口上 }
    AssertTrue(Format('the keys repainted the rows (%d)', [v.PaintedRows - painted]),
      v.PaintedRows - painted >= Length(keys) * (Rows - 1));
    AssertTrue(Format('the keys were painted on the window (%d paints)', [v.Paints - paints]),
      v.Paints - paints >= Length(keys));
    for r := 0 to Rows - 2 do
      AssertTrue(Format('row %d shows its line after the keys', [r]), v.PresentedHasInk(r));
    AssertEquals('rows blanked to one colour before the paint (' + v.FirstBlanked + ')', 0, v.Blanked);
    AssertEquals('rows whose pixels changed before the paint', 0, v.Differed);
    fx.Form.Hide;
  finally
    fx.Free;
  end;
  {$ENDIF}
end;

initialization
  RegisterTest(TTyTerminalViewFlickerTests);
end.
