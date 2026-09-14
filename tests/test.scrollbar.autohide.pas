unit test.scrollbar.autohide;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ScrollBar;

type
  TTyScrollBarAutoHideTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyScrollBar;
    procedure UseThemeCss(const ACss: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ThemeOffByDefault;
    procedure ThemeDelayIsRead;
    procedure NegativeOneParsesAsOff;
    procedure NeverBeatsAnAutoHidingTheme;
    procedure AutoBeatsAnOffTheme;
    procedure AutoStillReadsTheThemeDelay;
  end;

implementation

procedure TTyScrollBarAutoHideTests.SetUp;
begin
  { 控件必须有父控件，并且自带 controller——否则它读的是进程级主题，
    单跑绿、全量红。 }
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(FForm);
  FBar := TTyScrollBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
end;

procedure TTyScrollBarAutoHideTests.TearDown;
begin
  FreeAndNil(FForm);   // 拥有 controller 与 bar
end;

procedure TTyScrollBarAutoHideTests.UseThemeCss(const ACss: string);
begin
  FCtl.LoadThemeCss(ACss);
end;

procedure TTyScrollBarAutoHideTests.ThemeOffByDefault;
begin
  { 主题什么都不说 -> Metric 回退到 TyScrollBarAutoHideDef = -1 = 关 }
  AssertEquals(-1, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.ThemeDelayIsRead;
begin
  { 故意不用 1200——那正好是 TyScrollBarAutoHideFallbackMs。拿一个和回退常量
    同值的数去验「读到了主题」，一旦这条路被错接到回退上，两边答案一样，
    这条断言就看不出来。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  AssertEquals(1000, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.NegativeOneParsesAsOff;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  { 探针的回退**故意不是 -1**。ResolveMetric 解析失败时原样退回 ADefault
    (tyControls.StyleModel.pas)，所以拿 -1 当回退去问「是不是 -1」，
    解析成功和解析被吞给的是同一个答案，这条断言永远绿——它看着像在守，
    其实一点信号都没有。换成 999：解析对了是 -1，解析被吞了是 999。

    守的是 TyEvalLength 那句「头两个字符都是 '-' 才算变量引用」
    (tyControls.Css.Values.pas)。谁把它收紧成「以 '-' 开头」，'-1' 就被
    当成对变量 '1' 的引用，查不到、抛异常、退回 999，这里红。 }
  AssertEquals(-1, FCtl.Metric(TyScrollBarAutoHideVar, 999));
  { 而且这个 -1 确实一路走到了控件。 }
  AssertEquals(-1, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.NeverBeatsAnAutoHidingTheme;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1200; }');
  FBar.AutoHide := sbahNever;
  AssertEquals(-1, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.AutoBeatsAnOffTheme;
begin
  { 主题说关，属性说要自动隐藏 -> 用回退延时，而不是「关」 }
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  FBar.AutoHide := sbahAuto;
  AssertEquals(TyScrollBarAutoHideFallbackMs, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.AutoStillReadsTheThemeDelay;
begin
  { sbahAuto 压过主题的是「要不要隐藏」，不是「多久」——主题给了延时就用主题的。
    这正是属性注释承诺的后半句「延时仍读主题」，而 AutoBeatsAnOffTheme 走的是
    主题说关时的回退臂，碰不到这一条。800 既不是回退的 1200，也不是别处在用的值。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 800; }');
  FBar.AutoHide := sbahAuto;
  AssertEquals(800, FBar.EffectiveAutoHideMs);
end;

initialization
  RegisterTest(TTyScrollBarAutoHideTests);
end.
