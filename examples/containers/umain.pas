unit umain;

{ Phase-5 容器 & 布局示例。随各控件建成逐步扩充;当前展示 Batch 1 的装饰/绘制叶子:
  TTyBevel(3D 线条/边框)、TTyDivider(带标题分割线)、TTyPaintPanel(自绘表面)、
  TTySizeBox(右下角尺寸手柄)。纯代码创建,主题走全局 TyDefaultController。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Forms, Controls, BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Controller, tyControls.Form, tyControls.Types, tyControls.Painter,
  tyControls.ColorMath, tyControls.TyLabel, tyControls.Bevel, tyControls.Divider,
  tyControls.PaintPanel, tyControls.SizeBox;

type
  TMainForm = class(TTyForm)
  private
    FSurface: TTyPaintPanel;
    procedure PaintSurface(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
    procedure BuildUI;
    function Divider(const ACap: string; AAlign: TAlignment; AY: Integer): TTyDivider;
    function Bevel(AShape: TTyBevelShape; AStyle: TTyBevelStyle; AL, AT, AW, AH: Integer): TTyBevel;
    function Lbl(const AText: string; AL, AT: Integer): TTyLabel;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

function ThemesDir: string;
var Dir: string; i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

constructor TMainForm.Create(AOwner: TComponent);
var Bar: TTyTitleBar;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TyControls — 容器与布局(Phase 5 · Batch 1)';
  Position := poScreenCenter;
  SetBounds(0, 0, 620, 470);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := '容器与布局  · TyControls';

  BuildUI;
  ApplyChromeTheme(TyDefaultController);
end;

function TMainForm.Lbl(const AText: string; AL, AT: Integer): TTyLabel;
begin
  Result := TTyLabel.Create(Self);
  Result.Parent := Self;
  Result.Caption := AText;
  Result.SetBounds(AL, AT, 260, 18);
end;

function TMainForm.Divider(const ACap: string; AAlign: TAlignment; AY: Integer): TTyDivider;
begin
  Result := TTyDivider.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACap;
  Result.Alignment := AAlign;
  Result.SetBounds(20, AY, 580, 24);
end;

function TMainForm.Bevel(AShape: TTyBevelShape; AStyle: TTyBevelStyle;
  AL, AT, AW, AH: Integer): TTyBevel;
begin
  Result := TTyBevel.Create(Self);
  Result.Parent := Self;
  Result.Shape := AShape;
  Result.Style := AStyle;
  Result.SetBounds(AL, AT, AW, AH);
end;

procedure TMainForm.PaintSurface(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
var ctx: TBGRACanvas2D;
begin
  // 用库绘制器直接画到面板表面,与面板同遍合成(owner-draw)。
  ctx := APainter.Bitmap.Canvas2D;
  ctx.fillStyle(BGRA(59, 130, 246));
  ctx.fillRect(AContent.Left + 14, AContent.Top + 14, 44, 44);
  ctx.fillStyle(BGRA(16, 185, 129));
  ctx.beginPath;
  ctx.arc(AContent.Left + 96, AContent.Top + 36, 22, 0, 2 * Pi, False);
  ctx.fill;
  APainter.DrawText(AContent, 'OnPaintSurface — 应用用 TTyPainter 自绘', 'Segoe UI', 12, 500,
    TyColorFromLCL(clWhite, 255), taCenter, tlBottom, True);
end;

procedure TMainForm.BuildUI;
var grip: TTySizeBox; baseY: Integer;
begin
  baseY := 44;   // below the title bar
  Divider('分割线 TTyDivider(左 / 中 / 右)', taLeftJustify, baseY + 4);
  Divider('居中标题', taCenter, baseY + 32);
  Divider('右对齐', taRightJustify, baseY + 60);

  Divider('装饰 TTyBevel', taLeftJustify, baseY + 96);
  Lbl('Box / Frame(凹 / 凸)', 20, baseY + 122);
  Bevel(tbsBox,   tbsLowered, 20,  baseY + 142, 120, 60);
  Bevel(tbsFrame, tbsLowered, 152, baseY + 142, 120, 60);
  Bevel(tbsFrame, tbsRaised,  284, baseY + 142, 120, 60);
  Lbl('单边线', 430, baseY + 122);
  Bevel(tbsTopLine,    tbsLowered, 430, baseY + 146, 160, 2);
  Bevel(tbsBottomLine, tbsRaised,  430, baseY + 170, 160, 2);

  Divider('自绘表面 TTyPaintPanel', taLeftJustify, baseY + 220);
  FSurface := TTyPaintPanel.Create(Self);
  FSurface.Parent := Self;
  FSurface.SetBounds(20, baseY + 246, 384, 130);
  FSurface.OnPaintSurface := @PaintSurface;

  Lbl('右下角 → 尺寸手柄 TTySizeBox(拖动改窗口大小)', 20, baseY + 386);

  // 右下角尺寸手柄:拖动缩放本窗体(Target 默认取 owner 窗体)。
  grip := TTySizeBox.Create(Self);
  grip.Parent := Self;
  grip.Anchors := [akRight, akBottom];
  grip.SetBounds(ClientWidth - 20, ClientHeight - 20, 16, 16);
end;

end.
