unit test.version;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, StrUtils, TypInfo, Controls, Forms, fpcunit, testregistry,
  test.designregistry,
  tyControls.Types, tyControls.ActivityBar, tyControls.ActivityIndicator,
  tyControls.AdvancedComboBox, tyControls.AdvancedListBox, tyControls.Alert,
  tyControls.AnalogClock, tyControls.Arrow, tyControls.Badge, tyControls.BalloonHint,
  tyControls.Bevel, tyControls.Breadcrumb, tyControls.Button, tyControls.ButtonGroup,
  tyControls.CalcCurrencyEdit, tyControls.CalcEdit, tyControls.Calculator, tyControls.Calendar,
  tyControls.Card, tyControls.Cascader, tyControls.CharImage, tyControls.Chart,
  tyControls.CheckBox, tyControls.CheckComboBox, tyControls.CheckGroup,
  tyControls.CheckListBox, tyControls.CircularProgress, tyControls.ColorBox,
  tyControls.ColorButton, tyControls.ColorComboBox, tyControls.ColorGrid,
  tyControls.ColorListBox, tyControls.ComboBox, tyControls.ComboBoxEx, tyControls.ComboEdit,
  tyControls.ControlBar, tyControls.Controller, tyControls.CoolBar, tyControls.CurrencyEdit,
  tyControls.DateTimePicker, tyControls.Dial, tyControls.Dialogs, tyControls.Dialogs.About,
  tyControls.Dialogs.Color, tyControls.Dialogs.FileDialog, tyControls.Dialogs.Find,
  tyControls.Dialogs.Font, tyControls.Dialogs.Progress, tyControls.Dialogs.SelectPath,
  tyControls.Dialogs.IconBrowser,
  tyControls.Divider, tyControls.DropButtons, tyControls.Edit, tyControls.Empty,
  tyControls.ExPanel, tyControls.FilterComboBox, tyControls.FloatSpinEdit,
  tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.Form, tyControls.FormSurface,
  tyControls.Gauge, tyControls.GearActivityIndicator, tyControls.GearDial,
  tyControls.GlowLabel, tyControls.GlyphButtons, tyControls.GlyphImageList, tyControls.Grid,
  tyControls.GridPanel, tyControls.GroupBox, tyControls.HSColorPicker,
  tyControls.HeaderControl, tyControls.Hint, tyControls.HtmlLabel, tyControls.IconFont,
  tyControls.Icons.Lucide,
  tyControls.Image, tyControls.ImageCollection, tyControls.ImageView, tyControls.LColorPicker,
  tyControls.LevelMeter, tyControls.LinkLabel, tyControls.ListBox, tyControls.ListGroupPanel,
  tyControls.ListView, tyControls.MRUComboBox, tyControls.MaskEdit, tyControls.Memo,
  tyControls.Menu, tyControls.Meter, tyControls.NativeStyler, tyControls.Notification,
  tyControls.NumericEdit, tyControls.OfficeComboBox, tyControls.OfficeListBox,
  tyControls.PageControl, tyControls.Pagination, tyControls.PaintPanel, tyControls.Panel,
  tyControls.Popover, tyControls.PreviewBox, tyControls.ProgressBar, tyControls.RadioGroup,
  tyControls.Rating, tyControls.RelativePanel, tyControls.Ribbon, tyControls.RibbonAppMenu,
  tyControls.RibbonBackstage, tyControls.RibbonGallery, tyControls.RibbonQuickAccess,
  tyControls.ScrollBar, tyControls.ScrollBox, tyControls.ScrollPanel, tyControls.Segmented,
  tyControls.ShadowLabel, tyControls.Shape, tyControls.ShellComboBox, tyControls.ShellListView,
  tyControls.ShellTreeView, tyControls.SizeBox, tyControls.Sparkline, tyControls.SpinEdit,
  tyControls.Splitter, tyControls.StarShape, tyControls.StatusBar, tyControls.Steps,
  tyControls.TabSet, tyControls.TabSheet, tyControls.Tag, tyControls.ToggleSwitch,
  tyControls.ToolBar, tyControls.ToolBarEx, tyControls.ToolGroupPanel, tyControls.TrackBar,
  tyControls.TrackEdit, tyControls.Transfer, tyControls.TreeSelect, tyControls.TreeView,
  tyControls.TyLabel, tyControls.URLEdit, tyControls.UpDown, tyControls.ValueListEditor,
  { The property-editor base classes. None of them is ever dropped on a form, so nothing else
    in this uses list drags them in — but InheritsFromAnEditorBase resolves them by name, and
    an unresolvable base would make that check answer False for everything beneath it. }
  tyControls.Base, tyControls.Component;

type
  { Library-version guard.

    THE CONTRACT. Every class TyControls registers with the IDE must publish a read-only
    `Version: string` that reports TyVersion. It is not decoration: `RegisterPropertyEditor
    (TypeInfo(string), <base>, 'Version', TTyVersionEditor)` in designtime/tyControls.Design.pas
    hangs the About dialog off that property, so a component without it silently loses its
    entry point in the Object Inspector.

    WHY THIS FILE IS A SWEEP AND NOT A SAMPLE. Its predecessor (test.about) spot-checked seven
    hand-picked classes; it stayed green through the whole 2.x line while 27 of the registered
    components had no such property at all. A sample can only ever prove the sample.

    HOW IT IS GUARANTEED TO STAY EXHAUSTIVE — a control added to the palette tomorrow WITHOUT a
    Version property must turn this test red. Three links, none of which can be skipped:

      1. The population is not written here. test.designregistry's CollectRegisteredClassNames
         PARSES designtime/tyControls.Design.pas at run time and takes the class names out of
         every RegisterComponents / RegisterNoIcon / RegisterDesignerBaseClass call. That file is
         the one place a control MUST be edited to reach the palette at all, so the population
         tracks reality by construction. (tests/ cannot LINK that unit — it pulls in IDEIntf —
         but it can read the file; test.grid.streaming.pas set the precedent of a test whose
         input is a repo file.)

      2. A parsed NAME becomes a class REFERENCE only through the RTL class registry, and only
         RegisterClass populates that. Hence the RegisterClasses block at the bottom of this
         unit. That block is NOT the list under test: TestEveryRegisteredNameResolves fails on
         any parsed name it does not cover. So step 1 catches the new control even before
         anybody teaches this test how to build one.

      3. Once the class is reachable, TestEveryRegisteredComponentReportsTyVersion instantiates
         it and reads the property. Missing, wrongly typed, or reporting anything other than
         TyVersion — all three are failures, listed by name in one message.

    The parser itself lives in tests/test.designregistry.pas, not here: tests/test.paletteicons.pas
    needs the same population, and it used to keep a hand-copied array of class NAMES instead —
    which is precisely how TTyDrawGrid and TTyStringGrid reached the palette with no icon while
    the array that was supposed to guard the icon set stayed green. One parser, two callers. }
  TVersionTest = class(TTestCase)
  published
    procedure TestVersionConstantPinned;
    procedure TestEveryRegisteredNameResolves;
    procedure TestEveryRegisteredComponentReportsTyVersion;
    procedure TestPackageVersionsMatchTyVersion;
    procedure TestVersionEditorBasesResolve;
    procedure TestAboutDialogExemptionStillHolds;
  end;

implementation

const
  { NAMED EXEMPTIONS. A silent skip is a lie, so each one is spelled out here and
    re-justified from RTTI by its own test every run.

    TTyAboutDialog — its published `Version` is the HOST APPLICATION's version: the string
      this component renders on screen next to AppName, written by the user in the designer.
      The library version has no business overwriting that name, and inheriting the shared
      base would aim the About-dialog editor at the app's field, i.e. exactly backwards.
      TestAboutDialogExemptionStillHolds re-checks that the property is still a WRITABLE
      string, so the day it stops being the app's own field this exemption fails loudly
      instead of quietly covering a real gap. }
  CExempt: array[0..0] of string = ('TTyAboutDialog');

var
  GEditorBases: TStringList = nil;
  { Names of the classes this unit teaches the class registry about — recorded by Reg() at
    initialization, so the one list serves both purposes and cannot disagree with itself. }
  GKnownNames: TStringList = nil;

{ RegisterClasses, plus a record of what was registered. The recorded names are the
  REVERSE half of the drift guard: forward, every name parsed out of Design.pas must
  resolve here; backward, every name registered here must still appear in that parse. The
  backward half is what makes a shrinking parse loud — lose a whole palette group and its
  classes are suddenly registered-here-but-unregistered-there, by name. }
procedure Reg(const AClasses: array of TPersistentClass);
var i: Integer;
begin
  RegisterClasses(AClasses);
  if GKnownNames = nil then GKnownNames := TStringList.Create;
  for i := Low(AClasses) to High(AClasses) do
    if GKnownNames.IndexOf(AClasses[i].ClassName) < 0 then
      GKnownNames.Add(AClasses[i].ClassName);
end;

{ True when ACls descends from (or is) one of the classes the Version property editor is
  registered on — i.e. the Object Inspector will actually show the About '...' button. }
function InheritsFromAnEditorBase(ACls: TPersistentClass): Boolean;
var
  i: Integer;
  b: TPersistentClass;
begin
  if GEditorBases = nil then
  begin
    GEditorBases := TStringList.Create;
    CollectPropertyEditorBases('Version', GEditorBases);
  end;
  for i := 0 to GEditorBases.Count - 1 do
  begin
    b := GetClass(GEditorBases[i]);
    if (b <> nil) and ACls.InheritsFrom(b) then Exit(True);
  end;
  Result := False;
end;

function EditorBaseNames: string;
begin
  if GEditorBases = nil then
  begin
    GEditorBases := TStringList.Create;
    CollectPropertyEditorBases('Version', GEditorBases);
  end;
  Result := StringReplace(Trim(GEditorBases.Text), LineEnding, ', ', [rfReplaceAll]);
end;

function IsExempt(const AName: string): Boolean;
var i: Integer;
begin
  for i := 0 to High(CExempt) do
    if CExempt[i] = AName then Exit(True);
  Result := False;
end;

{ Build one instance for inspection. Forms cannot use Create(AOwner): TCustomForm.Create
  goes looking for a .lfm resource and raises when there is none — CreateNew is the
  resource-free constructor, and it is virtual, so this dispatches correctly. }
function InstantiateForCheck(ACls: TPersistentClass): TComponent;
begin
  if ACls.InheritsFrom(TCustomForm) then
    Result := TCustomFormClass(ACls).CreateNew(nil)
  else
    Result := TComponentClass(ACls).Create(nil);
end;

procedure TVersionTest.TestVersionConstantPinned;
begin
  AssertEquals('TyVersion pinned for this release', '3.1.0', TyVersion);
end;

{ The drift guard. Two directions:
    * every name the registrations mention must be buildable here (else the sweep below
      would silently skip a brand-new control), and
    * every exemption must still name something that is actually registered (else a stale
      exemption outlives the class it excused). }
procedure TVersionTest.TestEveryRegisteredNameResolves;
var
  names, bad: TStringList;
  i: Integer;
begin
  names := TStringList.Create;
  bad := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    { Sanity: prove each of the three parse paths actually matched something, so a broken
      parser reports itself instead of passing with an empty population. }
    AssertTrue('parser found the palette groups (RegisterComponents)',
      names.IndexOf('TTyStyleController') >= 0);
    AssertTrue('parser found the icon-less registrations (RegisterNoIcon)',
      names.IndexOf('TTyGridCell') >= 0);
    AssertTrue('parser found the designer base classes (RegisterDesignerBaseClass)',
      names.IndexOf('TTyForm') >= 0);
    for i := 0 to names.Count - 1 do
      if GetClass(names[i]) = nil then bad.Add(names[i]);
    AssertEquals('registered in designtime/tyControls.Design.pas but not reachable from this'
      + ' test — add the class (and its unit) to the Reg() block at the bottom of'
      + ' tests/test.version.pas:' + LineEnding + bad.Text, 0, bad.Count);

    { The reverse direction, and the one that keeps the POPULATION honest. A parser that
      quietly stops matching a call shape just yields a smaller list, and every
      forward-looking check still passes on the survivors — coverage silently shrinks while
      the suite stays green. Going backwards makes that loud: these classes are known to be
      registered (this unit had to name them to build them), so if the parse no longer finds
      one, the parse is what is broken. }
    bad.Clear;
    for i := 0 to GKnownNames.Count - 1 do
      if names.IndexOf(GKnownNames[i]) < 0 then bad.Add(GKnownNames[i]);
    AssertEquals('known to be registered with the IDE, but the parse of'
      + ' designtime/tyControls.Design.pas no longer finds them — either the registration was'
      + ' removed (drop them from Reg() too) or the parser has stopped matching a call shape'
      + ' and the sweep below is now covering less than it looks:' + LineEnding + bad.Text,
      0, bad.Count);

    bad.Clear;
    for i := 0 to High(CExempt) do
      if names.IndexOf(CExempt[i]) < 0 then bad.Add(CExempt[i]);
    AssertEquals('stale exemption in CExempt — no longer a registered class:' + LineEnding
      + bad.Text, 0, bad.Count);
  finally
    bad.Free;
    names.Free;
  end;
end;

{ The sweep itself: build one of everything and read the property back. }
procedure TVersionTest.TestEveryRegisteredComponentReportsTyVersion;
var
  names, bad: TStringList;
  i: Integer;
  cls: TPersistentClass;
  C: TComponent;
  pi: PPropInfo;
begin
  names := TStringList.Create;
  bad := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    for i := 0 to names.Count - 1 do
    begin
      if IsExempt(names[i]) then Continue;
      cls := GetClass(names[i]);
      { Unreachable classes are TestEveryRegisteredNameResolves' failure to report; skipping
        here keeps that one message clean instead of duplicating it 20 times. }
      if cls = nil then Continue;

      C := nil;
      try
        try
          C := InstantiateForCheck(cls);
        except
          on E: Exception do
          begin
            bad.Add(names[i] + ': constructor raised ' + E.ClassName + ': ' + E.Message);
            C := nil;
          end;
        end;
        if C = nil then Continue;

        pi := GetPropInfo(cls, 'Version');
        if pi = nil then
          bad.Add(names[i] + ': no published Version property')
        else if not (pi^.PropType^.Kind in [tkSString, tkLString, tkAString, tkWString, tkUString]) then
          { e.g. a Cardinal `Version` counter would read as garbage through GetStrProp —
            name it something else and let the library version keep the name. }
          bad.Add(names[i] + ': Version is not a string property')
        else if pi^.SetProc <> nil then
          { READ-ONLY IS LOAD-BEARING, not tidiness. TWriter skips properties with no setter,
            which is the whole reason ~26 components could be reparented onto TTyComponent
            without touching a single .lfm. Give Version a setter and every one of them
            starts streaming `Version = '2.99.0'` into saved forms — baking a build-time
            constant into user files, where it then loads back and overwrites nothing but
            sits there rotting. See source/tyControls.Component.pas, which states this
            invariant; this is the assertion that keeps the statement true. }
          bad.Add(names[i] + ': Version must be read-only (it has a setter) — a writable'
            + ' Version streams into .lfm files')
        else if GetStrProp(C, 'Version') <> TyVersion then
          bad.Add(names[i] + ': Version = ''' + GetStrProp(C, 'Version')
            + ''' (expected ''' + TyVersion + ''')')
        else if not InheritsFromAnEditorBase(cls) then
          { Having the property is only half the contract: the design-time '...' button that
            opens the About dialog comes from RegisterPropertyEditor on a handful of BASE
            classes. A component that declares Version on itself, off that inheritance tree,
            passes every check above and still shows a dead property in the Object Inspector.
            TTyAboutDialog is exactly that shape today (and is the named exemption). }
          bad.Add(names[i] + ': Version is not reachable by the design-time editor — it must'
            + ' descend from one of: ' + EditorBaseNames);
      finally
        C.Free;
      end;
    end;
    AssertEquals('registered components that do not report TyVersion through a published'
      + ' read-only Version property:' + LineEnding + bad.Text, 0, bad.Count);
  finally
    bad.Free;
    names.Free;
  end;
end;

{ The release number lives in THREE places: the TyVersion constant, and the <Version> element
  of each .lpk — and the .lpk numbers are the ones Lazarus shows in the package manager and
  would resolve dependencies against. Only the constant was pinned, so the packages could
  (and historically did) drift a whole release behind without anything noticing. Parse them
  and compare. Deliberately NOT hard-coded here: the pin lives in TestVersionConstantPinned,
  and this test only asserts the three agree, so a release bump touches one literal.

  PRE-RELEASE LABELS. TyVersion may carry a semver pre-release suffix ('3.0.0-Beta') that the
  .lpk <Version> — three integers — cannot hold. That is by design: the .lpk keeps the clean
  RELEASE number Lazarus resolves against, and the suffix is display-only. So the comparison is
  against TyVersion's numeric CORE (everything before the first '-'), not the whole string. }
procedure TVersionTest.TestPackageVersionsMatchTyVersion;

  function PackageVersion(const AFile: string): string;
  var
    sl: TStringList;
    s: string;
    p, q: Integer;

    function Attr(const AName: string): string;
    var a, b: Integer;
    begin
      Result := '0';
      a := Pos(AName + '="', s);
      if a = 0 then Exit;
      Inc(a, Length(AName) + 2);
      b := PosEx('"', s, a);
      if b > a then Result := Copy(s, a, b - a);
    end;

  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(RepoRoot + AFile);
      s := sl.Text;
    finally
      sl.Free;
    end;
    { the PACKAGE's own version element — not <Package Version="5"> (the file format) nor the
      CompilerOptions/PublishOptions ones, which carry a bare Value= and no Major= }
    p := Pos('<Version Major=', s);
    AssertTrue(AFile + ': no <Version Major=...> element found', p > 0);
    q := PosEx('/>', s, p);
    s := Copy(s, p, q - p);
    Result := Attr('Major') + '.' + Attr('Minor') + '.' + Attr('Release');
  end;

var
  core: string;
begin
  { TyVersion's numeric core: drop any '-Beta'/'-RC' pre-release label the .lpk cannot express. }
  core := TyVersion;
  if Pos('-', core) > 0 then core := Copy(core, 1, Pos('-', core) - 1);
  AssertEquals('tycontrols.lpk version must match TyVersion''s release number',
    core, PackageVersion('tycontrols.lpk'));
  AssertEquals('tycontrols_dt.lpk version must match TyVersion''s release number',
    core, PackageVersion('tycontrols_dt.lpk'));
end;

{ The design-time-reachability check in the sweep answers "does ACls descend from a class the
  Version editor is registered on?". It resolves those bases BY NAME through the class
  registry, so an unregistered base silently answers False for its whole subtree — which
  would flip that check from a guard into noise, or worse, into a wall of false failures.
  Assert the bases resolve, and that we found some at all (a parse that matched nothing
  would leave the set empty, and an empty set makes every component look unreachable). }
procedure TVersionTest.TestVersionEditorBasesResolve;
var
  bases, bad: TStringList;
  i: Integer;
begin
  bases := TStringList.Create;
  bad := TStringList.Create;
  try
    CollectPropertyEditorBases('Version', bases);
    AssertTrue('no Version property-editor registrations found in'
      + ' designtime/tyControls.Design.pas — the parse has drifted', bases.Count > 0);
    for i := 0 to bases.Count - 1 do
      if GetClass(bases[i]) = nil then bad.Add(bases[i]);
    AssertEquals('Version editor is registered on classes this test cannot resolve — add them'
      + ' to the RegisterClasses block in tests/test.version.pas, or the design-time'
      + ' reachability check silently passes everything below them:' + LineEnding + bad.Text,
      0, bad.Count);
  finally
    bad.Free;
    bases.Free;
  end;
end;

{ Keeps the one exemption honest — see CExempt. TTyAboutDialog is excused only because its
  `Version` is the app's own, user-written string; a writable string property is exactly
  what that means. If it ever becomes read-only (i.e. library-supplied) the exemption is
  wrong and this fails. }
procedure TVersionTest.TestAboutDialogExemptionStillHolds;
var
  pi: PPropInfo;
begin
  pi := GetPropInfo(TTyAboutDialog, 'Version');
  AssertNotNull('TTyAboutDialog still publishes Version', pi);
  AssertTrue('TTyAboutDialog.Version must be a string',
    pi^.PropType^.Kind in [tkSString, tkLString, tkAString, tkWString, tkUString]);
  AssertTrue('TTyAboutDialog.Version must stay WRITABLE — it is the host application''s'
    + ' version, not the library''s; a read-only one would mean the exemption is stale',
    pi^.SetProc <> nil);
end;

initialization
  { Name -> class for the sweep. See the class comment: this block is not the list under
    test, it is only what lets a parsed name be built. TestEveryRegisteredNameResolves is
    what fails when it falls behind designtime/tyControls.Design.pas. }
  Reg([
    TTyStyleController, TTyNativeStyler, TTyButton, TTyGlyphButton, TTyGlyphContainerButton,
    TTySpeedButton, TTyDropDownButton, TTyMenuButton, TTyColorButton, TTyButtonGroup, TTyLabel,
    TTyHtmlLabel, TTyLinkLabel, TTyShadowLabel, TTyGlowLabel, TTyTag, TTyBadge, TTyEdit,
    TTyNumericEdit, TTyCurrencyEdit, TTyMaskEdit, TTyURLEdit, TTyComboEdit, TTyTrackEdit,
    TTyCalcEdit, TTyCalcCurrencyEdit, TTyCalculator, TTyMemo, TTySpinEdit, TTyFloatSpinEdit,
    TTyUpDown,
    TTyCheckBox, TTyRadioButton, TTyToggleSwitch, TTyRadioGroup, TTyCheckGroup, TTySegmented,
    TTyComboBox, TTyMRUComboBox, TTyComboBoxEx, TTyOfficeComboBox]);
  Reg([
    TTyAdvancedComboBox, TTyCheckComboBox, TTyListBox, TTyCheckListBox, TTyOfficeListBox,
    TTyAdvancedListBox, TTyValueListEditor, TTyTransfer, TTyTreeSelect, TTyCascader,
    TTyColorBox, TTyColorComboBox, TTyColorListBox, TTyColorGrid, TTyLColorPicker,
    TTyHSColorPicker, TTyFontComboBox, TTyFontListBox, TTyFontSizeComboBox, TTyFilterComboBox,
    TTyShellComboBox, TTyGauge, TTyMeter, TTyLevelMeter, TTyDial, TTyGearDial, TTyAnalogClock,
    TTyCircularProgress, TTyActivityIndicator, TTyActivityBar, TTyGearActivityIndicator,
    TTySparkline, TTyRating, TTyTrackBar, TTyProgressBar, TTyScrollBar, TTyStatusBar,
    TTyToolBar, TTyToolButton, TTyToolSeparator, TTyToolBarEx]);
  Reg([
    TTyControlBar, TTyCoolBar, TTyAlert, TTyPagination, TTySteps, TTyBreadcrumb,
    TTyHeaderControl, TTyPanel, TTyGroupBox, TTyBevel, TTyDivider, TTySplitter, TTyPaintPanel,
    TTySizeBox, TTyScrollBox, TTyScrollPanel, TTyExPanel, TTyGridPanel, TTyRelativePanel,
    TTyToolGroupPanel, TTyListGroupPanel, TTyPageControl, TTyTabSheet, TTyTabSet, TTyTitleBar,
    TTyCard, TTyEmpty, TTyTreeView, TTyListView, TTyShellListView, TTyShellTreeView,
    TTyPreviewBox, TTyImageView, TTyCalendar, TTyDateTimePicker, TTyDrawGrid, TTyStringGrid,
    TTyMenuBar, TTyPopupMenu, TTyImagesMenu]);
  Reg([
    TTyMenuEx, TTyRibbon, TTyRibbonPage, TTyRibbonGroup, TTyRibbonAppMenu,
    TTyRibbonQuickAccess, TTyRibbonGallery, TTyRibbonBackstage, TTyIconFont, TTyLucideIconFont,
    TTyLucideImageList, TTyCharImage,
    TTyGlyphImageList, TTyImage, TTyImageCollection, TTyVirtualImageList, TTyHint,
    TTyBalloonHint, TTyPopover, TTyShape, TTyStarShape, TTyArrow, TTyChart, TTyMessage,
    TTyInputDialog, TTyPasswordDialog, TTyTextDialog, TTySelectValueDialog,
    TTySelectPathDialog, TTyColorDialog, TTyFontDialog, TTyFindDialog, TTyReplaceDialog,
    TTyProgressDialog, TTyAboutDialog, TTyOpenDialog, TTySaveDialog, TTyOpenPictureDialog,
    TTySavePictureDialog, TTyOpenPreviewDialog, TTySavePreviewDialog, TTyNotification,
    TTyIconBrowserDialog]);
  Reg([
    TTyGridCell, TTyFormSurface, TTyForm, TTyDialog]);
  { The BASE classes the Version property editor is registered on. They are never dropped on
    a form, so nothing else registers them — but InheritsFromAnEditorBase resolves them by
    name, and an unresolvable base would make that check quietly answer False for everything
    below it. TestVersionEditorBasesResolve is what catches that. }
  RegisterClasses([
    TTyGraphicControl, TTyCustomControl, TTyComponent]);
  RegisterTest(TVersionTest);

finalization
  GEditorBases.Free;
  GKnownNames.Free;
end.
