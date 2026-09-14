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
  UseThemeCss(':root { --scrollbar-auto-hide: 1200; }');
  AssertEquals(1200, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.NegativeOneParsesAsOff;
begin
  { 整条链路压在 TyEvalLength 那句「头两个字符都是 '-' 才算变量引用」上。
    谁把那个判断收紧成「以 '-' 开头」，-1 就会静默变成默认值。 }
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
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

initialization
  RegisterTest(TTyScrollBarAutoHideTests);
end.
