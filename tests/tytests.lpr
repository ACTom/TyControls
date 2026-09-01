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
  test.base.drawframe, test.formgradientbg, test.button, test.skinfit, test.englishfit, test.utf8, test.designeditors, test.focus.tabstop, test.tylabel, test.edit, test.edit.word, test.edit.undo, test.numericedit, test.currencyedit, test.maskedit, test.urledit, test.comboedit, test.trackedit, test.colorbox, test.colorcombobox, test.colorlistbox, test.fontcombobox, test.fontlistbox, test.fontsizecombobox, test.checklistbox,
  test.mrucombobox, test.comboboxex, test.officelistbox, test.officecombobox, test.colorgrid, test.lcolorpicker,
  test.hscolorpicker, test.advancedlistbox, test.advancedcombobox, test.checkcombobox, test.valuelisteditor,
  test.calculator, test.calcedit,
  test.bevel, test.divider, test.paintpanel, test.sizebox,
  test.radiogroup, test.checkgroup, test.toolgrouppanel,
  test.scrollbox, test.scrollpanel, test.expanel,
  test.gridpanel, test.gridcell, test.relativepanel,
  test.toolbarex, test.controlbar, test.coolbar,
  test.headercontrol, test.listgrouppanel, test.listgrouppanel.entries,
  test.listgrouppanel.editor, test.structureeditors,
  test.checkbox,
  test.radiobutton, test.controls.panel, test.controls.combobox,
  test.controls.scrollbar, test.form, test.formsurface, test.edgepassthrough, test.release, test.themes,
  test.listbox, test.listbox.scroll,
  test.progressbar,
  test.toggleswitch,
  test.trackbar,
  test.groupbox,
  test.tabstrip, test.tabstrip.axis, test.tabstrip.multiline,
  test.defaulttheme, test.spinedit, test.memo, test.memo.selection, test.memo.undo,
  test.floatspinedit,
  test.memo.props,
  test.memo.visualrows,
  test.memo.hscroll,
  test.memo.wrap,
  test.memo.wrap.nav,
  test.memo.bidi,
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
  test.modecoherence,
  test.paletteicons,
  test.appicon,
  test.trailingzone,
  test.glyphthickness,
  test.lucide, test.glyphnames,
  test.virtualimagelist.iconfont,
  test.virtualimagelist.baked,
  test.imagedraw,
  test.imagename,
  test.css.catalog,
  test.controller.styleoverride,
  test.tabsheet,
  test.pagecontrol,
  test.pagecontrol.streaming,
  test.version,
  test.windoweffects,
  test.accel,
  test.i18n, test.paintcost, test.measurecache, test.memo.linesadd, test.parity, test.parity.valuelist, test.parity.splitter, test.parity.listview, test.parity.memo, test.parity.toolbar, test.parity.maskedit, test.parity.shelldivider, test.parity.grid, test.parity.ranges, test.parity.menu, test.parity.header, test.parity.onpaint, test.parity.spincheck,
  test.controller.changelistener,
  test.nativestyler,
  test.splitter,
  test.statusbar,
  test.toolbar,
  test.toolbar.paintbutton,
  test.litetrio.events,
  test.datetime.events,
  test.popup,
  test.calendar,
  test.datetimepicker,
  test.treeview.events,
  test.treeview,
  test.treeview.columns,
  test.treeview.streaming,
  test.treeview.items,
  test.treeview.edit,
  test.treeview.drag,
  test.dialogs,
  test.dialogs.chrome,
  test.dialogs.selectpath, test.dialogs.iconbrowser, test.dialogs.imagecollectioneditor,
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
  test.imagecollection.streaming,
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
  test.combobox.simple,
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
  test.advchart.types, test.advchart.scale, test.advchart.scale.break,
  test.advchart.coord, test.advchart.layout,
  test.painter.vector,
  test.advchart.axis,
  test.advchart.measure,
  test.advchart.shape, test.advchart.paint, test.advchart.render,
  test.subpixel,
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
  test.combohint,
  test.bidi,
  test.rtl,
  test.edit.bidi,
  test.rtl.bars,
  test.rtl.chrome,
  test.card, test.tag, test.badge,
  test.grid.layout, test.grid, test.grid.streaming, test.grid.bidi,
  test.grid.objects, test.grid.options,
  test.alert, test.notification, test.empty, test.segmented,
  test.pagination, test.steps, test.breadcrumb, test.transfer,
  test.treeselect, test.cascader, test.popover,
  test.dpi.fontlatch,
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
  //
  // The THIRD source of machine-dependence -- month/weekday NAMES -- needs no pin
  // here, because its default already resolves deterministically in this process:
  // TyDateTimeNameSource = dnAuto renders DefaultFormatSettings' names unless a
  // catalogue is loaded, and no test leaves one loaded (test.calendar's
  // TearDown restores the rsTyDateTimeNamesLang sentinel it translates; the
  // AutoWithNothingLoadedFollowsTheLocale precondition enforces the contract).
  // A test whose ASSERTION mentions a month or weekday name must not read the
  // machine's names into its expected value blind: either force
  // TyDateTimeNameSource := dnTranslation (fixed English resourcestrings,
  // machine-independent) or pin DefaultFormatSettings locally -- save, poke,
  // restore, as test.chart does for the numeric separators. Both knobs are
  // plain globals precisely so tests can inject them.
  TyLocaleFirstDayOfWeek := wdSunday;
  Application := TTyTestRunner.Create(nil);
  Application.Initialize;
  Application.Title := 'TyControls Test Runner';
  Application.Run;
  Application.Free;
end.
