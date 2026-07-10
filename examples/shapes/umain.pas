unit umain;

{ Phase-9 矢量形状示例(TTyShape / TTyStarShape / TTyArrow)。

  控件全部在设计器里摆放(umain.lfm),运行时由 TTyForm 流式加载;代码只做两件 .lfm 表达不了的事:
  加载主题、把滑块接到形状属性上。

  三个控件的填充 / 描边都来自解析后的 TyPanel 样式,所以:
    - 换主题 → 没写 StyleOverride 的形状整体换色;
    - 写了 StyleOverride 的形状按自己的规则走(字面色或 var(--accent) 之类的主题变量)。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel, tyControls.Divider,
  tyControls.Button, tyControls.TrackBar,
  tyControls.Shape, tyControls.StarShape, tyControls.Arrow;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;

    DivKinds: TTyDivider;
    ShRect: TTyShape;
    ShRound: TTyShape;
    ShSquare: TTyShape;
    ShEllipse: TTyShape;
    ShCircle: TTyShape;
    ShTriangle: TTyShape;
    ShDiamond: TTyShape;
    ShLine: TTyShape;
    LblRect: TTyLabel;
    LblRound: TTyLabel;
    LblSquare: TTyLabel;
    LblEllipse: TTyLabel;
    LblCircle: TTyLabel;
    LblTriangle: TTyLabel;
    LblDiamond: TTyLabel;
    LblLine: TTyLabel;

    DivStyle: TTyDivider;
    ShOver1: TTyShape;
    ShOver2: TTyShape;
    ShNoBorder: TTyShape;
    ShZeroWidth: TTyShape;
    ShThick: TTyShape;
    ShLineThick: TTyShape;
    LblOver1: TTyLabel;
    LblOver2: TTyLabel;
    LblNoBorder: TTyLabel;
    LblZeroWidth: TTyLabel;
    LblThick: TTyLabel;
    LblLineThick: TTyLabel;

    DivStar: TTyDivider;
    StarBig: TTyStarShape;
    LblPoints: TTyLabel;
    TrackPoints: TTyTrackBar;
    LblInner: TTyLabel;
    TrackInner: TTyTrackBar;
    LblStarHint: TTyLabel;

    DivArrow: TTyDivider;
    ArrRight: TTyArrow;
    ArrLeft: TTyArrow;
    ArrUp: TTyArrow;
    ArrDown: TTyArrow;
    LblArrRight: TTyLabel;
    LblArrLeft: TTyLabel;
    LblArrUp: TTyLabel;
    LblArrDown: TTyLabel;
    ArrowBig: TTyArrow;
    LblHead: TTyLabel;
    TrackHead: TTyTrackBar;
    LblShaft: TTyLabel;
    TrackShaft: TTyTrackBar;

    DivTheme: TTyDivider;
    BtnLight: TTyButton;
    BtnDark: TTyButton;
    BtnGreen: TTyButton;
    LblThemeHint: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure TrackPointsChange(Sender: TObject);
    procedure TrackInnerChange(Sender: TObject);
    procedure TrackHeadChange(Sender: TObject);
    procedure TrackShaftChange(Sender: TObject);
    procedure BtnLightClick(Sender: TObject);
    procedure BtnDarkClick(Sender: TObject);
    procedure BtnGreenClick(Sender: TObject);
  private
    procedure UseTheme(const AFile: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ 从 exe 位置向上找 themes/,这样双击 exe 和从仓库根跑都能找到主题。 }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
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

procedure TMainForm.UseTheme(const AFile: string);
begin
  // 全局默认控制器:Controller=nil 的控件都经 ActiveController 回退到它。
  TyDefaultController.LoadTheme(ThemesDir + AFile);
  ApplyChromeTheme(TyDefaultController);   // 标题栏 + 窗口圆角/阴影
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  UseTheme('light.tycss');
end;

procedure TMainForm.TrackPointsChange(Sender: TObject);
begin
  StarBig.Points := TrackPoints.Position;
  LblPoints.Caption := Format('角数 Points = %d', [StarBig.Points]);
end;

procedure TMainForm.TrackInnerChange(Sender: TObject);
begin
  StarBig.InnerRatio := TrackInner.Position / 100;
  LblInner.Caption := Format('内半径比 InnerRatio = %.2f', [StarBig.InnerRatio]);
end;

procedure TMainForm.TrackHeadChange(Sender: TObject);
begin
  ArrowBig.HeadRatio := TrackHead.Position / 100;
  LblHead.Caption := Format('头部占长度 HeadRatio = %.2f', [ArrowBig.HeadRatio]);
end;

procedure TMainForm.TrackShaftChange(Sender: TObject);
begin
  ArrowBig.ShaftRatio := TrackShaft.Position / 100;
  LblShaft.Caption := Format('箭杆占宽度 ShaftRatio = %.2f', [ArrowBig.ShaftRatio]);
end;

procedure TMainForm.BtnLightClick(Sender: TObject);
begin
  UseTheme('light.tycss');
end;

procedure TMainForm.BtnDarkClick(Sender: TObject);
begin
  UseTheme('dark.tycss');
end;

procedure TMainForm.BtnGreenClick(Sender: TObject);
begin
  UseTheme('green.tycss');
end;

end.
