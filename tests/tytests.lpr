program tytests;

{$mode objfpc}{$H+}

uses
  Interfaces, consoletestrunner, tyControls.Painter, tyControls.Controller,
  tyControls.Calendar,
  test.Types, test.Css.Tokens, test.Css.Lexer, test.Css.Parser,
  test.Css.Values, test.StyleModel, test.accent, test.gradient, test.bevelborder, test.nineslice, test.metric, test.glyph, test.skins, test.fontcascade, test.darktext, test.painter, test.controller,
  test.controller.hotreload, test.base,
  test.baseevents,
  test.eventfiring,
  test.base.drawframe, test.button, test.skinfit, test.utf8, test.designeditors, test.focus.tabstop, test.tylabel, test.edit, test.edit.word, test.edit.undo, test.numericedit, test.currencyedit, test.maskedit, test.urledit, test.comboedit, test.trackedit, test.colorbox, test.colorcombobox, test.colorlistbox, test.fontcombobox, test.fontlistbox, test.fontsizecombobox, test.checklistbox,
  test.mrucombobox, test.comboboxex, test.officelistbox, test.officecombobox, test.colorgrid, test.lcolorpicker,
  test.hscolorpicker, test.advancedlistbox, test.advancedcombobox, test.checkcombobox, test.valuelisteditor,
  test.calculator, test.calcedit,
  test.bevel, test.divider, test.paintpanel, test.sizebox,
  test.radiogroup, test.checkgroup, test.toolgrouppanel,
  test.scrollbox, test.scrollpanel, test.expanel,
  test.gridpanel, test.gridcell, test.relativepanel,
  test.toolbarex, test.controlbar, test.coolbar,
  test.headercontrol, test.listgrouppanel,
  test.checkbox,
  test.radiobutton, test.controls.panel, test.controls.combobox,
  test.controls.scrollbar, test.form, test.formsurface, test.themes,
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
  test.builtinskins,
  test.paletteicons,
  test.tabsheet,
  test.pagecontrol,
  test.pagecontrol.streaming,
  test.version,
  test.windoweffects,
  test.accel,
  test.i18n, test.paintcost, test.memo.linesadd, test.parity, test.parity.valuelist, test.parity.splitter, test.parity.listview, test.parity.memo, test.parity.toolbar, test.parity.maskedit, test.parity.shelldivider, test.parity.grid, test.parity.ranges, test.parity.menu, test.parity.header, test.parity.onpaint, test.parity.spincheck,
  test.controller.changelistener,
  test.nativestyler,
  test.splitter,
  test.statusbar,
  test.toolbar,
  test.litetrio.events,
  test.datetime.events,
  test.popup,
  test.calendar,
  test.datetimepicker,
  test.treeview.events,
  test.treeview,
  test.treeview.columns,
  test.treeview.streaming,
  test.treeview.edit,
  test.treeview.drag,
  test.dialogs,
  test.dialogs.chrome,
  test.dialogs.selectpath,
  test.colormath,
  test.dialogs.color,
  test.dialogs.font,
  test.dialogs.find,
  test.dialogs.progress,
  test.dialogs.about,
  test.gauge,
  test.circularprogress,
  test.activityindicator,
  test.activitybar,
  test.meter,
  test.levelmeter,
  test.dial,
  test.analogclock,
  test.sparkline,
  test.rating,
  test.gearactivityindicator,
  test.updown,
  test.geardial,
  test.linklabel,
  test.shadowlabel,
  test.glowlabel,
  test.hint,
  test.balloonhint,
  test.iconfont,
  test.charimage,
  test.glyphimagelist,
  test.image,
  test.imagecollection,
  test.glyphbuttons,
  test.dropbuttons,
  test.colorbutton,
  test.buttongroup,
  test.ribbon,
  test.ribbonappmenu,
  test.ribbonquickaccess,
  test.ribbongallery,
  test.ribbonbackstage,
  test.popupsurface,
  test.keytips,
  test.combobox,
  test.tabset,
  test.columns.compat,
  test.listview.layout,
  test.listview,
  test.filesystem,
  test.shelllistview,
  test.shelltreeview,
  test.filtercombobox,
  test.shellcombobox,
  test.dialogs.filedialog,
  test.previewbox,
  test.imageview,
  test.chart,
  test.transitions,
  test.htmllabel,
  test.shape,
  test.starshape,
  test.arrow,
  test.parity.shapearrow,
  test.parity.starshape,
  test.parity.image,
  test.parity.shell,
  test.parity.numeric,
  test.parity.treeview,
  test.parity.grid.members,
  test.parity.barsmenus,
  test.parity.container,
  test.parity.buttons,
  test.parity.listtext,
  test.parity.combo,
  test.card, test.tag, test.badge,
  test.grid.layout, test.grid, test.grid.streaming,
  test.alert, test.notification, test.empty, test.segmented,
  test.pagination, test.steps, test.breadcrumb, test.transfer,
  test.treeselect, test.cascader, test.popover,
  test.parity.datetime;

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
  // Same reason, second source of machine-dependence: TTyCalendar.FirstDayOfWeek
  // defaults to wdLocaleDefault, which tyControls.Calendar resolves from the OS at
  // unit start. Every calendar geometry assertion would otherwise be measuring the
  // developer's Control Panel -- a Monday-first machine shifts the whole day grid by
  // one column. Pin it here so a new calendar test cannot inherit the machine's
  // answer by omission; the one test that is ABOUT locale resolution overrides this
  // variable itself and restores it.
  TyLocaleFirstDayOfWeek := wdSunday;
  Application := TTyTestRunner.Create(nil);
  Application.Initialize;
  Application.Title := 'TyControls Test Runner';
  Application.Run;
  Application.Free;
end.
