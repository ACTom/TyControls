program tytests;

{$mode objfpc}{$H+}

uses
  Interfaces, consoletestrunner, tyControls.Painter, tyControls.Controller,
  test.Types, test.Css.Tokens, test.Css.Lexer, test.Css.Parser,
  test.Css.Values, test.StyleModel, test.painter, test.controller,
  test.controller.hotreload, test.base,
  test.baseevents,
  test.eventfiring,
  test.base.drawframe, test.button, test.tylabel, test.edit, test.edit.word, test.edit.undo, test.checkbox,
  test.radiobutton, test.controls.panel, test.controls.combobox,
  test.controls.scrollbar, test.form, test.themes,
  test.listbox,
  test.progressbar,
  test.toggleswitch,
  test.trackbar,
  test.groupbox,
  test.tabstrip,
  test.defaulttheme, test.spinedit, test.memo, test.memo.selection, test.memo.undo,
  test.memo.props,
  test.memo.visualrows,
  test.memo.hscroll,
  test.memo.wrap,
  test.memo.wrap.nav,
  test.animation,
  test.animation.toggle,
  test.animation.button,
  test.undostack,
  test.themeregistry,
  test.themebundle,
  test.systemtheme,
  test.themelint,
  test.menu,
  test.builtinthemes,
  test.paletteicons,
  test.tabsheet,
  test.pagecontrol,
  test.pagecontrol.streaming,
  test.about,
  test.windoweffects,
  test.accel,
  test.i18n,
  test.controller.changelistener,
  test.nativestyler,
  test.splitter,
  test.statusbar;

type
  TTyTestRunner = class(TTestRunner)
  protected
  end;

var
  Application: TTyTestRunner;

begin
  // Headless determinism: keep the empty-FontName render path so position-
  // sensitive pixel tests are unaffected by the real system font. Disable the
  // controller's system-font fallback BEFORE any controller is created, and
  // force the fallback name empty. (The runner links the LCL widgetset, so
  // Screen.SystemFont is real here -- without this gate it would leak in.)
  TyAutoSystemFontFallback := False;
  TyFallbackFontName := '';
  Application := TTyTestRunner.Create(nil);
  Application.Initialize;
  Application.Title := 'TyControls Test Runner';
  Application.Run;
  Application.Free;
end.
