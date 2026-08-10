unit tyControls.Design;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, StdCtrls, ExtCtrls, Graphics, LCLIntf, LCLType,
  PropEdits, ComponentEditors, ProjectIntf, FormEditingIntf, LazIDEIntf,
  LResources, tyControls.Types, tyControls.Component,
  tyControls.Base, tyControls.Controller, tyControls.StyleModel,
  tyControls.Button, tyControls.TyLabel, tyControls.Edit, tyControls.NumericEdit,
  tyControls.CurrencyEdit, tyControls.MaskEdit, tyControls.URLEdit, tyControls.ComboEdit,
  tyControls.TrackEdit, tyControls.ColorBox, tyControls.ColorListBox, tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.CheckListBox,
  tyControls.ColorComboBox, tyControls.MRUComboBox, tyControls.ComboBoxEx,
  tyControls.OfficeListBox, tyControls.OfficeComboBox,
  tyControls.ColorGrid, tyControls.LColorPicker, tyControls.HSColorPicker,
  tyControls.AdvancedListBox, tyControls.AdvancedComboBox, tyControls.CheckComboBox,
  tyControls.ValueListEditor, tyControls.Calculator, tyControls.CalcEdit,
  tyControls.CalcCurrencyEdit,
  tyControls.CheckBox, tyControls.Panel, tyControls.ComboBox,
  tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.Gauge,
  tyControls.CircularProgress, tyControls.ActivityIndicator, tyControls.ActivityBar,
  tyControls.Meter, tyControls.LevelMeter, tyControls.Dial, tyControls.AnalogClock,
  tyControls.Sparkline, tyControls.Rating, tyControls.GearDial,
  tyControls.GearActivityIndicator, tyControls.UpDown,
  tyControls.LinkLabel, tyControls.ShadowLabel, tyControls.GlowLabel,
  tyControls.Hint, tyControls.BalloonHint,
  tyControls.IconFont, tyControls.Icons.Lucide, tyControls.CharImage,
  tyControls.GlyphImageList,
  tyControls.Image, tyControls.ImageCollection,
  tyControls.GlyphButtons, tyControls.DropButtons, tyControls.ColorButton,
  tyControls.ButtonGroup, tyControls.Ribbon, tyControls.RibbonAppMenu,
  tyControls.RibbonQuickAccess, tyControls.RibbonGallery, tyControls.RibbonBackstage,
  tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.PageControl, tyControls.TabSheet,
  tyControls.SpinEdit, tyControls.FloatSpinEdit,
  tyControls.Memo, tyControls.Menu, tyControls.NativeStyler,
  tyControls.Splitter, tyControls.StatusBar, tyControls.ToolBar,
  tyControls.Calendar, tyControls.DateTimePicker, tyControls.TabSet,
  ClipBrd,
  tyControls.TreeView, tyControls.Dialogs, tyControls.Dialogs.SelectPath,
  tyControls.Dialogs.IconBrowser,
  tyControls.Dialogs.Color, tyControls.Dialogs.Font,
  tyControls.Dialogs.Find, tyControls.Dialogs.Progress, tyControls.Dialogs.About,
  tyControls.Dialogs.FileDialog, tyControls.PreviewBox, tyControls.ImageView,
  tyControls.Chart, tyControls.HtmlLabel,
  tyControls.Bevel, tyControls.Divider, tyControls.PaintPanel, tyControls.SizeBox,
  tyControls.RadioGroup, tyControls.CheckGroup, tyControls.ToolGroupPanel,
  tyControls.ScrollBox, tyControls.ScrollPanel, tyControls.ExPanel,
  tyControls.GridPanel, tyControls.GridCell, tyControls.RelativePanel,
  tyControls.ToolBarEx, tyControls.ControlBar, tyControls.CoolBar,
  tyControls.HeaderControl, tyControls.ListGroupPanel,
  tyControls.Shape, tyControls.StarShape, tyControls.Arrow,
  tyControls.Card, tyControls.Tag, tyControls.Badge, tyControls.Grid,
  tyControls.Alert, tyControls.Notification, tyControls.Empty, tyControls.Segmented,
  tyControls.Pagination, tyControls.Steps, tyControls.Breadcrumb,
  tyControls.Transfer, tyControls.TreeSelect, tyControls.Cascader, tyControls.Popover,
  tyControls.ListView, tyControls.ShellListView, tyControls.ShellTreeView,
  tyControls.FilterComboBox, tyControls.ShellComboBox,
  { The vocabularies the value-list editors below read: the compiled-in theme pack and the
    process-wide named-theme registry. TypInfo is for the RTTI hop from a control to its
    IconFont — two unrelated classes publish that property and share no ancestor carrying it. }
  TypInfo, tyControls.BuiltinThemes, tyControls.ThemeRegistry,
  { The image-payload editor loads a picked file straight into a TBGRABitmap and encodes
    it with the collection's own codec — no TPicture anywhere on that path. }
  BGRABitmap;
type
  TTyStyleClassPropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

  { WHY EVERY LIST BELOW IS ADVISORY, NEVER A FIXED PICK-LIST.

    The Object Inspector only knows two shapes for a string property: a plain edit box, or a
    combo. Which combo it builds is decided by GetAttributes — paValueList alone gives an
    EDITABLE combo (csOwnerDrawEditableFixed), and adding paPickList turns it into a closed
    drop-down list the user cannot type into. Every vocabulary in this file is open-ended: a
    theme name may be one the app registers at runtime, a StyleClass may be a variant a theme
    that is not loaded in the IDE defines, a glyph name may be added to the icon font later.
    So these editors add paValueList and never paPickList: the list is a menu of what we can
    prove is legal, not a fence around what is. tests/test.designeditors.pas guards that
    (paPickList must not appear in this unit). paSortList is a separate question — purely
    whether the offered order carries meaning — and each editor answers it for itself. }

  { ThemeName: the compiled-in theme pack (default / system / every structural skin) plus
    whatever the process's theme registry has been told about, e.g. an app or a package that
    called TyRegisterThemeDir. Built-ins are listed FIRST and in their own order (no
    paSortList) because that is the order a maintainer thinks in — 'default' and 'system'
    before the skins — and registry extras follow, so a name added by someone else never
    hides the pack. }
  TTyThemeNamePropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
    function GetHint(HintType: TPropEditHint; x, y: integer): string; override;
  end;

  { Mode: the '@mode NAME' blocks the CURRENTLY LOADED theme declares, read off the edited
    controller's own model — a single-mode theme therefore offers nothing but the empty
    string, which is the truth rather than a menu of modes that would resolve to nothing.
    The empty entry comes first and is deliberately a BLANK row: it is the value itself
    ('' = apply no mode overrides), and a readable stand-in like '(none)' would be written
    into the .lfm verbatim and mean an unknown mode. GetHint carries the explanation. }
  TTyThemeModePropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
    function GetHint(HintType: TPropEditHint; x, y: integer): string; override;
  end;

  { ThemeFile: a .tycss stylesheet, picked with the IDE's standard file dialog (the '...'
    button) instead of typed. Only the filter and the title differ from LCL's editor. }
  TTyThemeFilePropertyEditor = class(TFileNamePropertyEditor)
  public
    function GetFilter: string; override;
    function GetDialogTitle: string; override;
  end;

  { GlyphName: the keys of the associated TTyIconFont's Glyphs map ('name=HEX' lines). That
    map is a published TStrings, so it is populated at DESIGN time and the list is real.
    (It used to say "unlike an image collection, filled only by runtime code" — no longer
    true: TTyImageCollection.Images streams too, see TTyImagePayloadPropertyEditor.)
    Reached by RTTI rather than by a cast:
    TTyCharImage and TTyGlyphButtonBase both publish IconFont but share no ancestor that
    declares it, and a future control publishing the same pair gets the dropdown for free. }
  { Right-click an icon font (or a bundled pack, or an image list fed by one) -> "Icon
    browser...". A two-thousand-entry dropdown is technically complete and practically
    useless; this is how a user actually finds the icon that means "save".

    On an icon font the picked name goes to the CLIPBOARD, because the font itself has no
    single name property to write it into -- the user is looking a name up to paste somewhere.
    On a TTyVirtualImageList it is APPENDED to Names, which is the thing that list is for. }
  TTyIconBrowserComponentEditor = class(TComponentEditor)
  private
    function FontOf(out AOwnerList: TTyVirtualImageList): TTyIconFont;
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  TTyGlyphNamePropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
    { The '...' button: opens the icon browser on the host's IconFont and writes the picked
      name back. The dropdown lists two thousand names; this is how you find one. }
    procedure Edit; override;
  end;

  { TTyIconFont.FontFamily: the font families this machine can render with. A family loaded
    PRIVATELY from FontFile may legitimately not be among them (that is the whole point of a
    private load), which is the second reason this list stays editable. }
  TTyFontFamilyPropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

  { TTyIconFont.FontFile: a font file, picked rather than typed (same treatment as ThemeFile). }
  TTyFontFilePropertyEditor = class(TFileNamePropertyEditor)
  public
    function GetFilter: string; override;
    function GetDialogTitle: string; override;
  end;

  { TTyImageItem.PngBase64 — the pixels of one master, held as a base64 PNG.

    Read-only in the grid with a '...' button that picks an image FILE and encodes it.
    Nobody hand-types four kilobytes of base64, and letting them try is exactly how a
    payload gets truncated into an icon that silently stops decoding; the grid shows a
    summary ('PNG 32x32') instead of the payload, which would otherwise make the row
    unreadable and the Object Inspector crawl.

    This editor is the design-time INTAKE for the whole collection: TTyImageCollection
    streams its masters through Images, so a picture loaded here is written into the .lfm
    and comes back at run time. Before it, images could only be added by runtime code. }
  TTyImagePayloadPropertyEditor = class(TPropertyEditor)
  private
    { The collection item this property belongs to, or nil if the editor was somehow
      attached elsewhere (defensive: an editor must never bring the IDE down). }
    function EditedItem: TTyImageItem;
  public
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
    procedure Edit; override;
  end;

  { TTyRibbonPage.Context: the contextual-tab group this page belongs to. The vocabulary is
    the set of context names the SIBLING pages of the same ribbon already use, because that is
    what TTyRibbon.ShowContext/HideContext will be called with — a page whose Context is a typo
    of its neighbours' simply never appears, silently. Offering the neighbours' spellings is
    the whole guard. }
  TTyRibbonContextPropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

  { Manages TTyPageControl pages in the designer (no header click-switch on a
    custom-drawn control). Verbs: Add / Delete / Show Next / Show Previous Page. }
  TTyPageControlEditor = class(TDefaultComponentEditor)
  private
    function PC: TTyPageControl;
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { Opens the node editor when a TTyTreeView is double-clicked in the designer.

    The node collection itself needs no custom property editor: Items is a published
    TCollection, and propedits.pp:9256 registers TCollectionPropertyEditor for every
    TCollection descendant, so the Object Inspector already shows the '...' and the
    standard add/delete/move editor, with Text and Level per item. What is missing
    without this class is the DOUBLE-CLICK -- which is how LCL's own TTreeView opens
    its 'TreeView Items Editor', and the only way a user discovers the feature at all
    (nobody scrolls the property grid looking for a collection they don't know exists).

    Descendants that own their own data (TTyShellTreeView) answer SupportsItemModel
    False and get no verb -- offering to hand-edit the nodes of a tree that repopulates
    itself from the filesystem would be an invitation to a runtime exception. }
  TTyTreeViewComponentEditor = class(TComponentEditor)
  private
    function Tree: TTyTreeView;
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { Previews a dialog component when it is double-clicked in the designer (verb 0),
    mirroring LCL's TCommonDialogComponentEditor. Modal wrappers call Execute; the two
    modeless ones (Find/Replace, Progress) call a guard-free PreviewInDesigner because
    their Execute/Show early-exit under csDesigning. }
  TTyDialogComponentEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { Editor for the read-only `Version` property: shows TyVersion in the Object Inspector and
    opens the About dialog (version + clickable homepage link) when the '...' button is clicked. }
  TTyVersionEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { Read-only `Purpose` property on TTyFormSurface: the OI shows a one-line summary and the '...'
    button explains WHY the surface exists and why it must not be deleted or re-laid-out. Together
    with `Version` it is the only property left visible on the surface (see Register). }
  TTySurfacePurposeEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { File > New entry that creates a unit whose form descends from TTyForm —a borderless
    form with a persistent chrome engine. The generated form comes WITH a top-aligned
    TTyTitleBar already associated (TitleBar = TyTitleBar1). FWithController=True (the
    TyControls Application main form) additionally drops a TTyStyleController and wires the
    form + title bar to it; the plain form leaves the controller unset so it can be pointed
    at the main window's controller later. }
  TTyFormFileDescriptor = class(TFileDescPascalUnitWithResource)
  protected
    FWithController: Boolean;
  public
    constructor Create; override;
    function GetInterfaceUsesSection: string; override;
    function GetInterfaceSource(const Filename, SourceName, ResourceName: string): string; override;
    function GetResourceSource(const ResourceName: string): string; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

  { The main form for a "TyControls Application" project: a themed TTyForm carrying its own
    TTyStyleController, with both the form and the title bar associated to it. }
  TTyMainFormFileDescriptor = class(TTyFormFileDescriptor)
  public
    constructor Create; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

  { File > New entry that creates a unit whose form descends from TTyDialog —a themed, close-only,
    non-resizable modal dialog base, with BorderIcons = [biSystemMenu] (close button only), ready for
    the user to design content + buttons on and show modally.
    The generated .lfm is BARE —no title bar, no content surface. TTyDialog builds its own title bar
    and bottom button bar in CreateNew (emitting one here gave the dialog TWO stacked title bars), and
    being non-resizable it has no WS_THICKFRAME edge band for a surface to cover. }
  TTyDialogFileDescriptor = class(TTyFormFileDescriptor)
  public
    constructor Create; override;
    function GetInterfaceUsesSection: string; override;
    function GetInterfaceSource(const Filename, SourceName, ResourceName: string): string; override;
    function GetResourceSource(const ResourceName: string): string; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

  { File > New > Project > "TyControls Application": a normal LCL GUI app whose main form is
    a themed TTyForm (title bar + style controller), with the tycontrols package dependency
    pre-added. Mirrors the IDE's built-in Application descriptor. }
  TTyApplicationDescriptor = class(TProjectDescriptor)
  public
    constructor Create; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
    function InitProject(AProject: TLazProject): TModalResult; override;
    function CreateStartFiles(AProject: TLazProject): TModalResult; override;
  end;

procedure Register;

implementation

resourcestring
  rsDtFormName        = 'TyControls Form';
  rsDtFormDescription = 'A borderless form descending from TTyForm, with a top-aligned ' +
    'TTyTitleBar already attached (drag to move, double-click to maximize). Point its ' +
    'Controller at your main window''s style controller to theme it, or lay out your controls ' +
    'below the bar.';
  rsDtMainFormName        = 'TyControls Main Form';
  rsDtMainFormDescription = 'A themed TTyForm carrying its own TTyStyleController, with the ' +
    'form and the title bar already associated to it —the root window for a TyControls application.';
  rsDtDialogName        = 'TyControls Dialog';
  rsDtDialogDescription = 'A themed custom-drawn modal dialog (TTyDialog): borderless, ' +
    'close-only, non-resizable, centered —design your own dialog content and buttons.';
  rsDtAppName        = 'TyControls Application';
  rsDtAppDescription = 'A graphical TyControls application. The main form is a themed TTyForm ' +
    '(custom title bar + style controller); the tycontrols package is added automatically.';
  rsDtAboutTitle   = 'About TyControls';
  rsDtAboutTagline = 'BGRABitmap-drawn, .tycss-themed LCL control library';
  rsDtAboutVersion = 'Version %s';
  rsDtAboutLicense = 'Modified LGPL (LCL-compatible linking exception)';
  rsDtPageAdd      = 'Add Page';
  rsDtPageDelete   = 'Delete Page';
  rsDtPageShowNext = 'Show Next Page';
  rsDtPageShowPrev = 'Show Previous Page';
  rsDtDialogPreview = 'Preview';
  { The verb this library's icon fonts and image lists carry, and what to say when there is no
    font to browse. IDE-facing, so they belong in THIS unit's table and not the runtime
    package's -- the two have separate .po catalogues. }
  rsDtIconBrowse    = 'Icon browser...';
  rsDtIconNeedsFont = 'Set IconFont first: there is no icon font to browse.';
  rsDtTreeEditNodes = 'Edit Nodes...';
  rsDtSurfacePurposeTitle = 'Why this control exists';
  rsDtSurfacePurposeText =
    'TyFormSurface is the content host of a TTyForm —the panel every control on the form lives on.' +
    LineEnding + LineEnding +
    'A borderless, resizable window cannot paint its own outermost pixels: the compositor gives it a ' +
    'backing surface smaller than the window, which leaves an unpainted band along the right and ' +
    'bottom edges. A CHILD window has no such limit and paints edge to edge, so TTyForm renders its ' +
    'themed background onto this surface instead of onto itself.' + LineEnding + LineEnding +
    'Your controls must live on the surface. Graphic (windowless) controls such as TTyLabel paint ' +
    'onto their parent, so one placed directly on the form is hidden behind the surface.' +
    LineEnding + LineEnding +
    'Keep exactly one surface per form, leave it filling the form, and do not delete it.';
  rsDtThemeFileFilter  = 'TyControls stylesheets (*.tycss)|*.tycss|All files|*';
  rsDtThemeFileTitle   = 'Select a .tycss stylesheet';
  rsDtFontFileFilter   = 'Font files (*.ttf;*.otf;*.ttc)|*.ttf;*.otf;*.ttc|All files|*';
  rsDtFontFileTitle    = 'Select an icon-font file';
  rsDtImageFileFilter  = 'Image files (*.png;*.bmp;*.jpg;*.jpeg;*.gif)|' +
    '*.png;*.bmp;*.jpg;*.jpeg;*.gif|All files|*';
  rsDtImageFileTitle   = 'Select an image for this collection entry';
  rsDtImageNoPayload   = '(no image)';
  rsDtImageBadPayload  = '(unreadable image data)';
  rsDtImageLoadFailed  = 'That file could not be read as an image.';
  rsDtThemeNameHint    = 'The theme to load by name. The list offers the themes compiled into ' +
    'TyControls plus any registered in this IDE; a name your application registers at run time ' +
    'is equally valid, so you may type one that is not listed. Setting this clears ThemeFile.';
  rsDtThemeModeHint    = 'Which "@mode NAME" block of the loaded theme is active. The list holds ' +
    'the modes THIS theme declares — the blank entry is the empty string, meaning no mode ' +
    'override at all. A single-mode theme therefore offers only the blank entry.';

var
  // The themed main-form descriptor, reused by the TyControls Application project's
  // CreateStartFiles. Held here so registration owns its (refcounted) lifetime.
  TyMainFormDescriptor: TTyMainFormFileDescriptor;

{ The design-time 'Version' property (OI '...' button) now opens the library's OWN themed
  TTyAboutDialog —so what you see at design time is exactly the dialog consumers ship, custom
  title bar and all —instead of the old code-built native TForm. Empty fields (here: copyright)
  are omitted by the dialog. }
procedure ShowTyAboutDialog;
begin
  TyShowAbout(rsDtAboutTitle, 'TyControls', Format(rsDtAboutVersion, [TyVersion]),
    rsDtAboutTagline, '', rsDtAboutLicense, TyHomepageUrl);
end;

function TTyVersionEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paReadOnly, paDialog];   // greyed value + '...' button that opens the dialog
end;

procedure TTyVersionEditor.Edit;
begin
  ShowTyAboutDialog;
end;

function TTySurfacePurposeEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paReadOnly, paDialog];   // greyed value + '...' button that opens the explanation
end;

procedure TTySurfacePurposeEditor.Edit;
begin
  MessageDlg(rsDtSurfacePurposeTitle, rsDtSurfacePurposeText, mtInformation, [mbOK], 0);
end;

function TTyStyleClassPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := (inherited GetAttributes) + [paValueList, paMultiSelect];
end;

procedure TTyStyleClassPropertyEditor.GetValues(Proc: TGetStrProc);
var
  comp: TPersistent;
  sty: ITyStyleable;
  ctrl: TTyStyleController;
  model: TTyStyleModel;
  list: TStringList;
  key: string;
  i: Integer;
begin
  // Dynamic + per control type: list exactly the variants the active theme defines for
  // THIS control's typeKey, read from its controller's model (else the global default,
  // which always carries the built-in defaults). No more hard-coded cross-control list.
  comp := GetComponent(0);
  ctrl := nil;
  if Supports(comp, ITyStyleable, sty) then
  begin
    key := sty.GetStyleTypeKey;
    // Both base classes expose a published Controller but share no ancestor.
    if comp is TTyGraphicControl then ctrl := TTyGraphicControl(comp).Controller
    else if comp is TTyCustomControl then ctrl := TTyCustomControl(comp).Controller;
  end
  else if comp is TTyPopover then
  begin
    { A popover is NOT ITyStyleable — the controller's styleable registry holds TControls and
      a non-visual component is not one — so it publishes its typeKey as a class function
      instead. Same StyleClass property, same variants, same dropdown; only the way in
      differs. Its own title key (TyPopoverTitle) is resolved with the SAME StyleClass, so
      there is nothing extra to offer. }
    key := TTyPopover.StyleTypeKey;
    ctrl := TTyPopover(comp).Controller;
  end
  else
    Exit;
  if ctrl <> nil then model := ctrl.Model else model := TyDefaultController.Model;
  list := TStringList.Create;
  try
    list.Sorted := True;            // stable display order
    list.Duplicates := dupIgnore;
    model.GetVariantsForType(key, list);
    for i := 0 to list.Count - 1 do
      Proc(list[i]);
  finally
    list.Free;
  end;
end;

{ TTyThemeNamePropertyEditor }

function TTyThemeNamePropertyEditor.GetAttributes: TPropertyAttributes;
begin
  { paValueList and NOTHING else added: no paPickList (the combo must stay typeable) and no
    paSortList (GetValues' own order is the meaningful one). }
  Result := (inherited GetAttributes) + [paValueList];
end;

procedure TTyThemeNamePropertyEditor.GetValues(Proc: TGetStrProc);
var
  seen: TStringList;
  names: TStringArray;
  i: Integer;
begin
  seen := TStringList.Create;
  try
    { Theme names resolve case-insensitively (TyResolveTheme / TyResolveThemeCss both fold
      case), so the de-dup has to as well — otherwise a registry entry spelled 'Office' would
      show up as a second, indistinguishable row next to the built-in 'office'. }
    seen.CaseSensitive := False;
    names := TyBuiltinThemeNames;                 // compiled in: always offerable
    for i := 0 to High(names) do
      if seen.IndexOf(names[i]) < 0 then
      begin
        seen.Add(names[i]);
        Proc(names[i]);
      end;
    { Whatever else this process knows about — another design-time package, or a themes/
      folder someone published with TyRegisterThemeDir. Register publishes the built-in pack
      into this same registry, so most of what comes back here is the list above again and
      the de-dup absorbs it; the pack is still enumerated from TyBuiltinThemeNames rather
      than from the registry so the dropdown is complete even if that publication is ever
      moved, deferred or removed. }
    names := TyThemeNames;
    for i := 0 to High(names) do
      if seen.IndexOf(names[i]) < 0 then
      begin
        seen.Add(names[i]);
        Proc(names[i]);
      end;
  finally
    seen.Free;
  end;
end;

function TTyThemeNamePropertyEditor.GetHint(HintType: TPropEditHint; x, y: integer): string;
begin
  Result := inherited GetHint(HintType, x, y) + LineEnding + LineEnding + rsDtThemeNameHint;
end;

{ TTyThemeModePropertyEditor }

function TTyThemeModePropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := (inherited GetAttributes) + [paValueList];
end;

procedure TTyThemeModePropertyEditor.GetValues(Proc: TGetStrProc);
var
  comp: TPersistent;
  names: TStringArray;
  i: Integer;
begin
  { '' first: it is a legal value (no mode override), and putting it at the top means the way
    BACK from a mode is always one click away. }
  Proc('');
  comp := GetComponent(0);
  if not (comp is TTyStyleController) then Exit;
  { The modes are a property of the LOADED theme, not of the library, so they are read from
    this controller's own model. A controller whose ThemeName/ThemeFile has not resolved in
    the IDE has an unloaded model and offers nothing further — the honest answer, and better
    than a list of modes that no theme here declares. }
  names := TTyStyleController(comp).Model.ModeNames;
  for i := 0 to High(names) do
    Proc(names[i]);
end;

function TTyThemeModePropertyEditor.GetHint(HintType: TPropEditHint; x, y: integer): string;
begin
  Result := inherited GetHint(HintType, x, y) + LineEnding + LineEnding + rsDtThemeModeHint;
end;

{ TTyThemeFilePropertyEditor }

function TTyThemeFilePropertyEditor.GetFilter: string;
begin
  Result := rsDtThemeFileFilter;
end;

function TTyThemeFilePropertyEditor.GetDialogTitle: string;
begin
  Result := rsDtThemeFileTitle;
end;

{ TTyIconBrowserComponentEditor }

function TTyIconBrowserComponentEditor.FontOf(out AOwnerList: TTyVirtualImageList): TTyIconFont;
begin
  AOwnerList := nil;
  Result := nil;
  if Component is TTyIconFont then
    Result := TTyIconFont(Component)          { covers TTyIconPackFont / TTyLucideIconFont }
  else if Component is TTyVirtualImageList then
  begin
    AOwnerList := TTyVirtualImageList(Component);
    Result := AOwnerList.IconFont;
  end;
end;

function TTyIconBrowserComponentEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyIconBrowserComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then Result := rsDtIconBrowse
  else Result := inherited GetVerb(Index);
end;

procedure TTyIconBrowserComponentEditor.ExecuteVerb(Index: Integer);
var
  lst: TTyVirtualImageList;
  fnt: TTyIconFont;
  dlg: TTyIconBrowserForm;
  nm: string;
begin
  if Index <> 0 then begin inherited ExecuteVerb(Index); Exit; end;
  fnt := FontOf(lst);
  if fnt = nil then
  begin
    { An image list with no IconFont has nothing to browse. Say so rather than opening an
      empty grid, which reads as "the browser is broken". }
    TyMessageDlg(rsDtIconNeedsFont, mtInformation, [mbOK]);
    Exit;
  end;
  nm := '';
  if lst <> nil then
  begin
    { Seed with the last name in the list, so re-opening the browser lands where the user was. }
    if lst.Names.Count > 0 then nm := lst.Names[lst.Names.Count - 1];
  end;
  { Opened from a list, the browser shows each icon's ImageIndex -- which is what consumers
    actually write. Opened from a font there is no index to show, and inventing one from the
    grid position would be a number that changes every time the user types in the search box. }
  dlg := TyBuildIconBrowserDialogFor('', fnt, lst);
  try
    dlg.GlyphName := nm;
    if dlg.ShowModal <> mrOK then Exit;
    nm := dlg.GlyphName;
  finally
    dlg.Free;
  end;
  if nm = '' then Exit;
  if lst <> nil then
  begin
    if lst.Names.IndexOf(nm) < 0 then
    begin
      lst.Names.Add(nm);
      Modified;        { tell the designer the form changed, or the edit is lost on close }
    end;
  end
  else
    { A font has no single name property to write into -- the user came here to look a name up.
      The clipboard is where a looked-up name is useful. }
    Clipboard.AsText := nm;
end;

{ TTyGlyphNamePropertyEditor }

function TTyGlyphNamePropertyEditor.GetAttributes: TPropertyAttributes;
begin
  { paValueList keeps the typeable dropdown; paDialog adds the '...' that opens the browser.
    Both, not either: the dropdown is faster once you know the name, and the browser is the
    only way to find one you do not. }
  Result := (inherited GetAttributes) + [paValueList, paDialog];
end;

procedure TTyGlyphNamePropertyEditor.Edit;
var
  comp: TPersistent;
  fnt: TObject;
  nm: string;
begin
  comp := GetComponent(0);
  if comp = nil then Exit;
  { Same RTTI route as GetValues, and the same TypInfo. qualification -- TPropertyEditor has a
    parameterless GetPropInfo of its own that would shadow the unit-level one. }
  if TypInfo.GetPropInfo(comp, 'IconFont') = nil then Exit;
  fnt := TypInfo.GetObjectProp(comp, 'IconFont');
  if not (fnt is TTyIconFont) then
  begin
    TyMessageDlg(rsDtIconNeedsFont, mtInformation, [mbOK]);
    Exit;
  end;
  nm := GetStrValue;
  if TyBrowseIcons('', TTyIconFont(fnt), nm) then
    SetStrValue(nm);
end;

procedure TTyGlyphNamePropertyEditor.GetValues(Proc: TGetStrProc);
var
  comp: TPersistent;
  fnt: TObject;
  names: TStrings;
  i: Integer;
begin
  comp := GetComponent(0);
  if comp = nil then Exit;
  { RTTI rather than a cast per host class: see the type declaration. GetObjectProp returns
    nil both when there is no such property and when it is unset, which is the same answer
    here — nothing to list. }
  { TypInfo. is REQUIRED here, not decoration: TPropertyEditor (propedits.pp) has its own
    parameterless GetPropInfo member, which shadows the unit-level one inside any editor
    method and fails with "wrong number of parameters". It only bites when the design-time
    package is compiled, which is why a green test build says nothing about it. }
  if TypInfo.GetPropInfo(comp, 'IconFont') = nil then Exit;
  fnt := TypInfo.GetObjectProp(comp, 'IconFont');
  if not (fnt is TTyIconFont) then Exit;
  { GlyphNames, NOT Glyphs. A bundled pack maps nothing by hand -- TTyLucideIconFont ships an
    empty Glyphs on purpose and answers through a registered lister -- so the old loop over
    Glyphs.Names produced an EMPTY dropdown for the one icon font most users will have on the
    form. GlyphNames merges the two and already drops the nameless and the unparseable, which
    is what that loop's skip was for.

    No paSortList in GetAttributes: the list arrives sorted, and paSortList would make the IDE
    re-sort two thousand strings on the fill path for nothing. A two-thousand-entry combo is
    usable but poor -- that is an argument for a browser dialog, not for changing the sort. }
  names := TTyIconFont(fnt).GlyphNames;   { owned by the component -- do not free }
  for i := 0 to names.Count - 1 do
    Proc(names[i]);
end;

{ TTyFontFamilyPropertyEditor }

function TTyFontFamilyPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := (inherited GetAttributes) + [paValueList, paSortList];
end;

procedure TTyFontFamilyPropertyEditor.GetValues(Proc: TGetStrProc);
var
  i: Integer;
begin
  { Screen.Fonts is the machine's installed families. Sorted (paSortList above) because there
    are hundreds of them and no other order is meaningful. Deliberately NOT prefixed with
    LCL's 'default' pseudo-entry: TFont.Name understands it, this property does not — it is
    matched against a real family name at render time. }
  if Screen = nil then Exit;
  for i := 0 to Screen.Fonts.Count - 1 do
    Proc(Screen.Fonts[i]);
end;

{ TTyFontFilePropertyEditor }

function TTyFontFilePropertyEditor.GetFilter: string;
begin
  Result := rsDtFontFileFilter;
end;

function TTyFontFilePropertyEditor.GetDialogTitle: string;
begin
  Result := rsDtFontFileTitle;
end;

{ TTyImagePayloadPropertyEditor }

function TTyImagePayloadPropertyEditor.EditedItem: TTyImageItem;
var
  p: TPersistent;
begin
  Result := nil;
  if PropCount <> 1 then Exit;   // multi-select: one file cannot mean several rows
  p := GetComponent(0);
  if p is TTyImageItem then
    Result := TTyImageItem(p);
end;

function TTyImagePayloadPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  // paReadOnly greys the cell (the payload is not typeable), paDialog gives the '...'
  // button that does the real work. Same shape as TTyVersionEditor above.
  Result := [paReadOnly, paDialog];
end;

function TTyImagePayloadPropertyEditor.GetValue: string;
var
  it: TTyImageItem;
  m: TBGRABitmap;
begin
  it := EditedItem;
  if it = nil then Exit(rsDtImageNoPayload);
  if it.PngBase64 = '' then Exit(rsDtImageNoPayload);
  m := it.Master;
  // Non-empty but nil master = the payload is there and does not decode. Saying so is
  // the difference between "I forgot to load it" and "my .lfm got mangled".
  if m = nil then Exit(rsDtImageBadPayload);
  Result := Format('PNG %dx%d', [m.Width, m.Height]);
end;

procedure TTyImagePayloadPropertyEditor.Edit;
var
  dlg: TOpenDialog;
  it: TTyImageItem;
  bmp: TBGRABitmap;
  ok: Boolean;
begin
  it := EditedItem;
  if it = nil then Exit;
  dlg := TOpenDialog.Create(nil);
  try
    dlg.Filter := rsDtImageFileFilter;
    dlg.Title := rsDtImageFileTitle;
    dlg.Options := dlg.Options + [ofFileMustExist];
    if not dlg.Execute then Exit;

    bmp := TBGRABitmap.Create;
    try
      ok := True;
      try
        // BGRA-native load: the pixels never pass through TPicture, which is the round
        // trip that turns a BGRA bitmap black (memory/bgra-makebitmapcopy-black).
        bmp.LoadFromFile(dlg.FileName);
      except
        ok := False;   // not an image, or a corrupt one — report, never escape into the IDE
      end;
      if ok then
        ok := (bmp.Width > 0) and (bmp.Height > 0);
      if not ok then
      begin
        ShowMessage(rsDtImageLoadFailed);
        Exit;
      end;
      it.SetBitmap(bmp);
      // The NAME is the lookup key, and an unnamed master is unreachable. Defaulting it
      // to the file's base name makes the common case (drop in save.png, get 'save')
      // work without a second edit, while never overwriting a name already chosen.
      if it.ImageName = '' then
        it.ImageName := ChangeFileExt(ExtractFileName(dlg.FileName), '');
    finally
      bmp.Free;
    end;
    Modified;
  finally
    dlg.Free;
  end;
end;

{ TTyRibbonContextPropertyEditor }

function TTyRibbonContextPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := (inherited GetAttributes) + [paValueList];
end;

procedure TTyRibbonContextPropertyEditor.GetValues(Proc: TGetStrProc);
var
  comp: TPersistent;
  page: TTyRibbonPage;
  host: TWinControl;
  i: Integer;
  seen: TStringList;
  ctx: string;
begin
  comp := GetComponent(0);
  if not (comp is TTyRibbonPage) then Exit;
  page := TTyRibbonPage(comp);
  host := page.Parent;
  if host = nil then Exit;
  seen := TStringList.Create;
  try
    seen.CaseSensitive := False;   // ShowContext matches case-insensitively; so must the list
    for i := 0 to host.ControlCount - 1 do
      if host.Controls[i] is TTyRibbonPage then
      begin
        ctx := TTyRibbonPage(host.Controls[i]).Context;
        // '' is not a context, it is the absence of one — and it is already the default.
        if (ctx <> '') and (seen.IndexOf(ctx) < 0) then
        begin
          seen.Add(ctx);
          Proc(ctx);
        end;
      end;
  finally
    seen.Free;
  end;
end;

function TTyPageControlEditor.PC: TTyPageControl;
begin
  Result := Component as TTyPageControl;
end;

function TTyPageControlEditor.GetVerbCount: Integer;
begin
  Result := 4;
end;

function TTyPageControlEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := rsDtPageAdd;
    1: Result := rsDtPageDelete;
    2: Result := rsDtPageShowNext;
    3: Result := rsDtPageShowPrev;
  else
    Result := '';
  end;
end;

procedure TTyPageControlEditor.ExecuteVerb(Index: Integer);
var
  Hook: TPropertyEditorHook;
  NewPage: TTyTabSheet;
  NewName: string;
  DelP: TPersistent;
begin
  case Index of
    0: begin
         Hook := nil;
         if not GetHook(Hook) then Exit;
         NewPage := TTyTabSheet.Create(PC.Owner);
         NewPage.Parent := PC;                       // SetParent -> RegisterPage
         NewName := GetDesigner.CreateUniqueComponentName(NewPage.ClassName);
         NewPage.Caption := NewName;
         NewPage.Name := NewName;
         PC.ActivePage := NewPage;
         Hook.PersistentAdded(NewPage, True);
         Modified;
       end;
    1: begin
         if (PC.ActivePageIndex < 0) or (PC.PageCount = 0) then Exit;
         Hook := nil;
         if not GetHook(Hook) then Exit;
         DelP := TPersistent(PC.ActivePage);
         Hook.DeletePersistent(DelP);
       end;
    2: if PC.PageCount > 0 then
         PC.ActivePageIndex := (PC.ActivePageIndex + 1) mod PC.PageCount;
    3: if PC.PageCount > 0 then
         PC.ActivePageIndex := (PC.ActivePageIndex + PC.PageCount - 1) mod PC.PageCount;
  end;
end;

{ TTyTreeViewComponentEditor }

function TTyTreeViewComponentEditor.Tree: TTyTreeView;
begin
  Result := Component as TTyTreeView;
end;

function TTyTreeViewComponentEditor.GetVerbCount: Integer;
begin
  { A tree that owns its own data (the shell tree) offers nothing to hand-edit. }
  if Tree.SupportsItemModel then Result := 1 else Result := 0;
end;

function TTyTreeViewComponentEditor.GetVerb(Index: Integer): string;
begin
  if (Index = 0) and Tree.SupportsItemModel then Result := rsDtTreeEditNodes
  else Result := inherited GetVerb(Index);
end;

procedure TTyTreeViewComponentEditor.ExecuteVerb(Index: Integer);
begin
  if (Index <> 0) or not Tree.SupportsItemModel then Exit;
  { The stock collection editor, aimed at Items -- the same form the '...' button in
    the Object Inspector opens, so there is exactly one node-editing UI to learn. }
  TCollectionPropertyEditor.ShowCollectionEditor(Tree.Items, Tree, 'Items');
end;

{ TTyDialogComponentEditor }

function TTyDialogComponentEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyDialogComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then Result := rsDtDialogPreview
  else Result := inherited GetVerb(Index);
end;

procedure TTyDialogComponentEditor.ExecuteVerb(Index: Integer);
begin
  if Index <> 0 then begin inherited ExecuteVerb(Index); Exit; end;
  // Modeless components early-exit under csDesigning, so use their guard-free preview.
  // TTyReplaceDialog IS a TTyFindDialog, so that branch covers it (must precede none).
  if      Component is TTyProgressDialog then TTyProgressDialog(Component).PreviewInDesigner
  else if Component is TTyFindDialog     then TTyFindDialog(Component).PreviewInDesigner
  else if Component is TTyMessage        then TTyMessage(Component).Execute
  else if Component is TTyInputDialog    then TTyInputDialog(Component).Execute
  else if Component is TTyPasswordDialog then TTyPasswordDialog(Component).Execute
  else if Component is TTyTextDialog     then TTyTextDialog(Component).Execute
  else if Component is TTySelectValueDialog then TTySelectValueDialog(Component).Execute
  else if Component is TTySelectPathDialog  then TTySelectPathDialog(Component).Execute
  else if Component is TTyColorDialog    then TTyColorDialog(Component).Execute
  else if Component is TTyFontDialog     then TTyFontDialog(Component).Execute
  else if Component is TTyAboutDialog    then TTyAboutDialog(Component).Execute
  else if Component is TTyIconBrowserDialog then TTyIconBrowserDialog(Component).Execute;
end;

{ TTyFormFileDescriptor }

constructor TTyFormFileDescriptor.Create;
begin
  inherited Create;
  FWithController := False;
  Name := 'TyControls form';        // internal id (File > New list)
  ResourceClass := TTyForm;         // generated class descends from TTyForm
  UseCreateFormStatements := True;  // add to the project's auto-create forms
  // Auto-add the runtime package dependency so the generated `uses tyControls.Form`
  // resolves in a fresh project (otherwise the IDE only adds LCL via its fallback).
  RequiredPackages := 'tycontrols';
end;

function TTyFormFileDescriptor.GetInterfaceUsesSection: string;
begin
  Result := inherited GetInterfaceUsesSection + ', tyControls.Form';
  if FWithController then
    Result := Result + ', tyControls.Controller';
end;

function TTyFormFileDescriptor.GetInterfaceSource(const Filename, SourceName,
  ResourceName: string): string;
const
  LE = LineEnding;
var
  fields: string;
begin
  // Declare the pre-placed components as published fields so the generated class matches the
  // .lfm GetResourceSource emits (the IDE binds streamed components to these fields by name).
  // TTyFormSurface needs no extra unit: tyControls.Form re-exports it (see that unit) precisely so
  // every designed form can carry this field with only `uses tyControls.Form`.
  fields := '    Surface: TTyFormSurface;' + LE
          + '    TyTitleBar1: TTyTitleBar;' + LE;
  if FWithController then
    fields := fields + '    TyStyleController1: TTyStyleController;' + LE;
  Result :=
     'type' + LE
    + '  T' + ResourceName + ' = class(TTyForm)' + LE
    + fields
    + '  private' + LE
    + LE
    + '  public' + LE
    + LE
    + '  end;' + LE
    + LE
    + 'var' + LE
    + '  ' + ResourceName + ': T' + ResourceName + ';' + LE
    + LE;
end;

function TTyFormFileDescriptor.GetResourceSource(const ResourceName: string): string;
const
  LE = LineEnding;
var
  s: string;
begin
  // A non-empty result OVERRIDES the IDE's automatic .lfm generation. The form class is
  // T<ResourceName> (the convention GetInterfaceSource + the IDE both use). Modelled on a
  // real IDE-generated TTyForm + title-bar .lfm (examples/demo/chromeform.lfm); the form-level
  // `TitleBar =` / `Controller =` are forward refs the LFM reader resolves via fixups.
  s :=
     'object ' + ResourceName + ': T' + ResourceName + LE
    + '  Left = 300' + LE
    + '  Height = 320' + LE
    + '  Top = 200' + LE
    + '  Width = 480' + LE
    + '  Caption = ''' + ResourceName + '''' + LE;
  if FWithController then
    s := s + '  Controller = TyStyleController1' + LE;
  { The content host wraps ALL of the form's controls (title bar included): a borderless resizable
    window cannot paint its outermost pixels, and graphic controls only render when hosted on it.
    See TTyFormSurface.Purpose. }
  s := s
    + '  TitleBar = TyTitleBar1' + LE
    + '  object Surface: TTyFormSurface' + LE
    + '    Left = 0' + LE
    + '    Height = 320' + LE
    + '    Top = 0' + LE
    + '    Width = 480' + LE
    + '    Align = alClient' + LE
    + '    object TyTitleBar1: TTyTitleBar' + LE
    + '      Left = 0' + LE
    + '      Height = 32' + LE
    + '      Top = 0' + LE
    + '      Width = 480' + LE
    + '      Align = alTop' + LE
    + '      Caption = ''' + ResourceName + '''' + LE;
  if FWithController then
    s := s + '      Controller = TyStyleController1' + LE;
  s := s
    + '    end' + LE
    + '  end' + LE;
  // The style controller is non-visual —it stays on the FORM, not inside the surface.
  if FWithController then
    s := s
      + '  object TyStyleController1: TTyStyleController' + LE
      + '    Left = 64' + LE
      + '    Top = 48' + LE
      + '  end' + LE;
  Result := s + 'end' + LE;
end;

function TTyFormFileDescriptor.GetLocalizedName: string;
begin
  Result := rsDtFormName;
end;

function TTyFormFileDescriptor.GetLocalizedDescription: string;
begin
  Result := rsDtFormDescription;
end;

{ TTyMainFormFileDescriptor }

constructor TTyMainFormFileDescriptor.Create;
begin
  inherited Create;
  FWithController := True;
  Name := 'TyControls main form';   // internal id (distinct from the plain form)
end;

function TTyMainFormFileDescriptor.GetLocalizedName: string;
begin
  Result := rsDtMainFormName;
end;

function TTyMainFormFileDescriptor.GetLocalizedDescription: string;
begin
  Result := rsDtMainFormDescription;
end;

{ TTyDialogFileDescriptor }

constructor TTyDialogFileDescriptor.Create;
begin
  inherited Create;
  Name := 'TyControls dialog';      // internal id (distinct from the forms)
  ResourceClass := TTyDialog;       // generated class descends from TTyDialog
end;

function TTyDialogFileDescriptor.GetInterfaceUsesSection: string;
begin
  // Base adds tyControls.Form (TTyTitleBar); the dialog form also needs tyControls.Dialogs
  // so `class(TTyDialog)` resolves in the generated unit.
  Result := inherited GetInterfaceUsesSection + ', tyControls.Dialogs';
end;

function TTyDialogFileDescriptor.GetInterfaceSource(const Filename, SourceName,
  ResourceName: string): string;
const
  LE = LineEnding;
begin
  { Full override (the base hard-codes TTyForm). No published fields: TTyDialog brings its own title
    bar and button bar from CreateNew, and there is no surface (see GetResourceSource). }
  Result :=
     'type' + LE
    + '  T' + ResourceName + ' = class(TTyDialog)' + LE
    + '  private' + LE
    + LE
    + '  public' + LE
    + LE
    + '  end;' + LE
    + LE
    + 'var' + LE
    + '  ' + ResourceName + ': T' + ResourceName + ';' + LE
    + LE;
end;

function TTyDialogFileDescriptor.GetResourceSource(const ResourceName: string): string;
const
  LE = LineEnding;
begin
  { Full override (the base hard-codes TTyForm). Unlike the FORM template this emits NO title bar and
    NO content surface, because TTyDialog is not TTyForm:
      - TTyDialog.CreateNew already BUILDS and associates its own title bar (and a bottom button bar).
        Emitting one here produced a second, stacked title bar and hijacked the `TitleBar =` binding.
      - A dialog is Resizable=False, so it has no WS_THICKFRAME and none of the unpaintable edge band
        the surface exists to cover —controls sit directly on the dialog, as they always have. }
  Result :=
     'object ' + ResourceName + ': T' + ResourceName + LE
    + '  Left = 300' + LE
    + '  Height = 320' + LE
    + '  Top = 200' + LE
    + '  Width = 480' + LE
    + '  BorderIcons = [biSystemMenu]' + LE
    + '  Caption = ''' + ResourceName + '''' + LE
    + 'end' + LE;
end;

function TTyDialogFileDescriptor.GetLocalizedName: string;
begin
  Result := rsDtDialogName;
end;

function TTyDialogFileDescriptor.GetLocalizedDescription: string;
begin
  Result := rsDtDialogDescription;
end;

{ TTyApplicationDescriptor }

constructor TTyApplicationDescriptor.Create;
begin
  inherited Create;
  Name := 'TyControls Application';
  // Inherit the user's IDE-wide default project compiler options, like a normal Application.
  Flags := Flags + [pfUseDefaultCompilerOptions];
end;

function TTyApplicationDescriptor.GetLocalizedName: string;
begin
  Result := rsDtAppName;
end;

function TTyApplicationDescriptor.GetLocalizedDescription: string;
begin
  Result := rsDtAppDescription;
end;

function TTyApplicationDescriptor.InitProject(AProject: TLazProject): TModalResult;
const
  LE = LineEnding;
var
  MainFile: TLazProjectFile;
  NewSource: string;
begin
  Result := inherited InitProject(AProject);

  MainFile := AProject.CreateProjectFile('project1.lpr');
  MainFile.IsPartOfProject := True;
  AProject.AddFile(MainFile, False);
  AProject.MainFileID := 0;          // the .lpr is the main file
  AProject.UseAppBundle := True;
  AProject.UseManifest := True;
  AProject.Scaled := True;
  AProject.LoadDefaultIcon;

  NewSource :=
     'program Project1;' + LE + LE
    + '{$mode objfpc}{$H+}' + LE + LE
    + 'uses' + LE
    + '  {$IFDEF UNIX}' + LE
    + '  cthreads,' + LE
    + '  {$ENDIF}' + LE
    + '  {$IFDEF HASAMIGA}' + LE
    + '  athreads,' + LE
    + '  {$ENDIF}' + LE
    + '  Interfaces, // this includes the LCL widgetset' + LE
    + '  Forms' + LE
    + '  { you can add units after this };' + LE + LE
    + 'begin' + LE
    + '  RequireDerivedFormResource := True;' + LE
    + '  Application.Scaled := True;' + LE
    + '  {$PUSH}{$WARN 5044 OFF}' + LE
    + '  Application.MainFormOnTaskbar := True;' + LE
    + '  {$POP}' + LE
    + '  Application.Initialize;' + LE
    + '  Application.Run;' + LE
    + 'end.' + LE + LE;
  AProject.MainFile.SetSourceText(NewSource, True);

  AProject.AddPackageDependency('LCL');
  AProject.AddPackageDependency('tycontrols');   // the main form descends from TTyForm
  AProject.LazCompilerOptions.Win32GraphicApp := True;
  AProject.LazCompilerOptions.UnitOutputDirectory := 'lib' + PathDelim + '$(TargetCPU)-$(TargetOS)';
  AProject.LazCompilerOptions.TargetFilename := 'project1';

  Result := mrOK;
end;

function TTyApplicationDescriptor.CreateStartFiles(AProject: TLazProject): TModalResult;
begin
  // Create + open the themed main form. UseCreateFormStatements makes the IDE add
  // `Application.CreateForm(...)` + the unit to the .lpr automatically.
  Result := LazarusIDE.DoNewEditorFile(TyMainFormDescriptor, '', '',
    [nfIsPartOfProject, nfOpenInEditor, nfCreateDefaultSrc]);
end;

procedure Register;
begin
  { Publish the compiled-in theme pack into THIS PROCESS (the IDE). An application does this
    itself at startup; the IDE never did, which made a design-time ThemeName inert — the
    controller resolved the name against an empty registry, loaded nothing, and the designer
    went on drawing the base layer. Two things depend on it now: picking a theme in the Object
    Inspector actually re-skins the form under the designer, and the Mode dropdown can list the
    '@mode' blocks of the theme that is loaded (an unloaded model declares none). Design-time
    only —nothing here runs in a built application, whose own TyRegisterBuiltinThemes call is
    still what makes ThemeName resolve at run time. }
  TyRegisterBuiltinThemes;
  // Register the component-palette icons (24x24 PNG per class, generated by
  // tools/genicons -> scripts/gen-icons.ps1). The IDE looks each up by class name;
  // this MUST run before RegisterComponents so the palette finds them.
  {$I tycontrols_icons.lrs}
  // Make TTyForm a recognized designer base class. Without this the form designer
  // cannot resolve `class(TTyForm)` as an ancestor and silently falls back to TForm
  // (sourcefilemanager FindBaseComponentClass -> StandardDesignerBaseClasses[TForm]),
  // so the Object Inspector shows none of TTyForm's published chrome properties
  // (TitleBar / TitleHeight / BorderIcons / Resizable). RegisterComponents only
  // covers droppable controls, not base form classes —this is the form-level analog.
  if FormEditingHook <> nil then
  begin
    FormEditingHook.RegisterDesignerBaseClass(TTyForm);
    // TTyDialog is a distinct designer base class (close-only modal dialog): register it so
    // `class(TTyDialog)` resolves as an ancestor and the OI shows its chrome, same as TTyForm.
    FormEditingHook.RegisterDesignerBaseClass(TTyDialog);
  end;
  // The palette is split into functional groups so no single tab is overcrowded. NOTE: both
  // scripts/gen-icons.ps1 and tests/test.paletteicons.pas parse EVERY
  // RegisterComponents('TyControls...', [...]) group here and require each registered class to
  // have a generated icon —a new control must land in one of these groups (and get a glyph in
  // genicons.lpr + the $classes entry), never a standalone unlisted class. The TEST is the guard
  // that fires without anyone running the script: TTyDrawGrid/TTyStringGrid once reached this
  // list with no icon and nothing noticed, because the test kept its own copy of the class list.
  // === Palette groups, organised by control TYPE (same class set as before) ===
  // Core (non-visual).
  RegisterComponents('TyControls',
    [TTyStyleController, TTyNativeStyler]);
  // Buttons.
  RegisterComponents('TyControls Buttons',
    [TTyButton, TTyGlyphButton, TTyGlyphContainerButton, TTySpeedButton,
     TTyDropDownButton, TTyMenuButton, TTyColorButton, TTyButtonGroup]);
  // Labels.
  RegisterComponents('TyControls Labels',
    [TTyLabel, TTyHtmlLabel, TTyLinkLabel, TTyShadowLabel, TTyGlowLabel,
     TTyTag, TTyBadge]);
  // Text edits: single/multi-line, formatted, calculator, spin.
  RegisterComponents('TyControls Edits',
    [TTyEdit, TTyNumericEdit, TTyCurrencyEdit, TTyMaskEdit, TTyURLEdit, TTyComboEdit,
     TTyTrackEdit, TTyCalcEdit, TTyCalcCurrencyEdit, TTyCalculator,
     TTyMemo, TTySpinEdit, TTyFloatSpinEdit, TTyUpDown]);
  // Checks / radios / switches + their groups.
  RegisterComponents('TyControls Choices',
    [TTyCheckBox, TTyRadioButton, TTyToggleSwitch, TTyRadioGroup, TTyCheckGroup, TTySegmented]);
  // Combo boxes & list boxes.
  RegisterComponents('TyControls Lists',
    [TTyComboBox, TTyMRUComboBox, TTyComboBoxEx, TTyOfficeComboBox, TTyAdvancedComboBox,
     TTyCheckComboBox,
     TTyListBox, TTyCheckListBox, TTyOfficeListBox, TTyAdvancedListBox, TTyValueListEditor,
     TTyTransfer, TTyTreeSelect, TTyCascader]);
  // Rich pickers: colour / font / filter / shell selectors.
  RegisterComponents('TyControls Pickers',
    [TTyColorBox, TTyColorComboBox, TTyColorListBox, TTyColorGrid, TTyLColorPicker,
     TTyHSColorPicker, TTyFontComboBox, TTyFontListBox, TTyFontSizeComboBox,
     TTyFilterComboBox, TTyShellComboBox]);
  // Instruments & indicators.
  RegisterComponents('TyControls Gauges',
    [TTyGauge, TTyMeter, TTyLevelMeter, TTyDial, TTyGearDial, TTyAnalogClock,
     TTyCircularProgress, TTyActivityIndicator, TTyActivityBar, TTyGearActivityIndicator,
     TTySparkline, TTyRating]);
  // Bars: sliders / progress / scroll / status / tool bars + header.
  RegisterComponents('TyControls Bars',
    [TTyTrackBar, TTyProgressBar, TTyScrollBar, TTyStatusBar,
     TTyToolBar, TTyToolButton, TTyToolSeparator, TTyToolBarEx, TTyControlBar, TTyCoolBar,
     TTyAlert, TTyPagination, TTySteps, TTyBreadcrumb, TTyHeaderControl]);
  // Containers & layout.
  RegisterComponents('TyControls Containers',
    [TTyPanel, TTyGroupBox, TTyBevel, TTyDivider, TTySplitter, TTyPaintPanel, TTySizeBox,
     TTyScrollBox, TTyScrollPanel, TTyExPanel, TTyGridPanel, TTyRelativePanel,
     TTyToolGroupPanel, TTyListGroupPanel,
     TTyPageControl, TTyTabSheet, TTyTabSet, TTyTitleBar,
     TTyCard, TTyEmpty]);
  // Cells are created/owned by the grid, not dragged from the palette —register the
  // class (for streaming + OI selection) without a palette button.
  RegisterNoIcon([TTyGridCell]);
  // Data views + shell/file views + date/time.
  RegisterComponents('TyControls Data Views',
    [TTyTreeView, TTyListView, TTyShellListView, TTyShellTreeView, TTyPreviewBox, TTyImageView,
     TTyCalendar, TTyDateTimePicker,
     TTyDrawGrid, TTyStringGrid]);
  // Menus.
  RegisterComponents('TyControls Menus',
    [TTyMenuBar, TTyPopupMenu, TTyImagesMenu, TTyMenuEx]);
  // Office-style ribbon parts.
  RegisterComponents('TyControls Ribbon',
    [TTyRibbon, TTyRibbonPage, TTyRibbonGroup, TTyRibbonAppMenu,
     TTyRibbonQuickAccess, TTyRibbonGallery, TTyRibbonBackstage]);
  // Icon-font, images, hints.
  RegisterComponents('TyControls Images',
    [TTyIconFont, TTyLucideIconFont, TTyCharImage, TTyGlyphImageList, TTyImage,
     TTyImageCollection, TTyVirtualImageList, TTyHint, TTyBalloonHint,
     TTyPopover]);
  // Decorative vector shapes + charts.
  RegisterComponents('TyControls Shapes & Charts',
    [TTyShape, TTyStarShape, TTyArrow, TTyChart]);
  // Dialogs: message / input family / pickers / find-replace / progress / about / file.
  RegisterComponents('TyControls Dialogs',
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog,
     TTyColorDialog, TTyFontDialog,
     TTyFindDialog, TTyReplaceDialog, TTyProgressDialog, TTyAboutDialog,
     TTyOpenDialog, TTySaveDialog, TTyOpenPictureDialog, TTySavePictureDialog,
     TTyOpenPreviewDialog, TTySavePreviewDialog, TTyNotification,
     TTyIconBrowserDialog]);
  { The content host MUST be a registered component class, or deleting it is unrecoverable. The
    designer records a delete by SERIALIZING the component to LFM text (TDesigner.AddUndoAction ->
    CopySelectionToStream) and undoes it by PASTING that text back —so undo runs through the same
    registry paste does. RegisterNoIcon, not RegisterComponents: registered (so undo works) but with
    no palette icon, since the surface only ever comes from the form template.
    Pasting a stray surface is NOT blocked: the designer's paste reaches its parent without routing
    through the SetParent a guard could hook, so the guards we tried only ever caught the form itself
    while every other container let one through —half a fence, so they were removed. Harmless in
    practice: the surface is not on the palette, so a stray one only appears if you deliberately copy
    it, and a form ignores any surface that is not its own. }
  RegisterNoIcon([TTyFormSurface]);
  // StyleClass dropdown applies to ALL styleable controls: registering on the two
  // base classes covers every TyControls control through inheritance.
  RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'StyleClass',
    TTyStyleClassPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomControl, 'StyleClass',
    TTyStyleClassPropertyEditor);
  // TTyPopover is the one class that publishes StyleClass off that tree: it is a non-visual
  // TTyComponent (its window is created on Show), so neither control base reaches it and its
  // variant list was plain free text. Same editor —it knows the popover's way in.
  RegisterPropertyEditor(TypeInfo(string), TTyPopover, 'StyleClass',
    TTyStyleClassPropertyEditor);
  { === Guided string properties ===============================================================
    A published string with a KNOWN vocabulary is unusable in the Object Inspector until an
    editor offers it: the inspector shows a bare edit box, and nothing on screen says what may
    be typed into it. Each registration below names the vocabulary in its comment; all of them
    stay typeable (see the note above the editor declarations). }
  // The three string properties of the style controller — the whole reason a controller is
  // dropped on a form, and until now three empty boxes.
  RegisterPropertyEditor(TypeInfo(string), TTyStyleController, 'ThemeName',
    TTyThemeNamePropertyEditor);          // built-in pack + this process's theme registry
  RegisterPropertyEditor(TypeInfo(string), TTyStyleController, 'Mode',
    TTyThemeModePropertyEditor);          // the loaded theme's own @mode blocks, plus ''
  RegisterPropertyEditor(TypeInfo(string), TTyStyleController, 'ThemeFile',
    TTyThemeFilePropertyEditor);          // '...' opens a *.tycss file dialog
  // Icon fonts: the family must name a renderable font, the file is a file, and a glyph name
  // must be a key of the referenced font's Glyphs map.
  RegisterPropertyEditor(TypeInfo(string), TTyIconFont, 'FontFamily',
    TTyFontFamilyPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyIconFont, 'FontFile',
    TTyFontFilePropertyEditor);
  { The design-time way pixels get INTO an image collection. Registered on the collection
    ITEM, so it applies inside the stock collection editor that TTyImageCollection.Images
    opens — no custom collection editor needed. }
  RegisterPropertyEditor(TypeInfo(string), TTyImageItem, 'PngBase64',
    TTyImagePayloadPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCharImage, 'GlyphName',
    TTyGlyphNamePropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyGlyphButtonBase, 'GlyphName',
    TTyGlyphNamePropertyEditor);          // covers TTyGlyphButton / GlyphContainer / SpeedButton
  // A contextual ribbon tab, spelled the way its siblings spell it.
  RegisterPropertyEditor(TypeInfo(string), TTyRibbonPage, 'Context',
    TTyRibbonContextPropertyEditor);
  { Paths and file filters. No value LIST is possible for these — the vocabulary is the file
    system — so they get the other half of the same treatment: a picker behind the '...'
    button instead of a path typed from memory. All three editors are LCL's own; only the
    registrations are ours. TTyControls' file dialogs, folder picker and shell views mirror
    the LCL components whose identical properties the IDE already registers these on. }
  RegisterPropertyEditor(TypeInfo(string), TTyCustomFileDialog, 'Filter', TFileDlgFilterProperty);
  RegisterPropertyEditor(TypeInfo(string), TTyFilterComboBox, 'Filter', TFileDlgFilterProperty);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomFileDialog, 'FileName', TFileNamePropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomFileDialog, 'InitialDir', TDirectoryPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTySelectPathDialog, 'Root', TDirectoryPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTySelectPathDialog, 'Directory', TDirectoryPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyShellComboBox, 'Directory', TDirectoryPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyShellListView, 'Directory', TDirectoryPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyShellTreeView, 'Directory', TDirectoryPropertyEditor);
  // Version: read-only version display + design-time About dialog, on every registered class.
  // FIVE base classes cover the whole library through inheritance: the two control bases take
  // every visual control, TTyComponent every non-visual one (TTyStyleController included —
  // it descends from TTyComponent), and the last two are the odd ancestries that cannot
  // (TTyPopupMenu descends from TPopupMenu, TTyForm from TForm), so they need their own line.
  // tests/test.version.pas READS THESE LINES: it parses this file for the registrations and
  // asserts every registered component descends from one of them, so a component that gains
  // the property off this tree —and would therefore show a dead entry in the OI —is caught.
  RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomControl, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyComponent, 'Version', TTyVersionEditor);
  { TTyVirtualImageList no longer descends from TTyComponent, so
    the editor has to be named for it explicitly or its '...' stops opening the About box.
    test.version's InheritsFromAnEditorBase resolves the bases it parses out of THIS file. }
  RegisterPropertyEditor(TypeInfo(string), TTyVirtualImageList, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyPopupMenu, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyForm, 'Version', TTyVersionEditor);
  // BorderStyle is locked to bsNone (TTyForm is a borderless custom-chrome window) —
  // hide it from the Object Inspector so it is neither shown nor editable.
  RegisterPropertyEditor(TypeInfo(TFormBorderStyle), TTyForm, 'BorderStyle', THiddenPropertyEditor);
  { TTyFormSurface is a FIXED alClient content host, not something to configure —editing its Align,
    bounds, Visible, Font, Controller—would only break it (the Controller belongs on the FORM, which
    themes the whole window). So hide EVERY inherited property and leave just the two informational
    ones. Mechanics: an empty PropertyName matches any property of that type on the class, and for
    tkClass the match follows inheritance —so TypeInfo(TPersistent) alone covers Font / Constraints /
    BorderSpacing / PopupMenu / Action / Controller / AnchorSide*. The two by-NAME registrations below
    win over these blanket ones (a named match always beats an unnamed one, whatever the order). }
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTranslateString), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(Boolean), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(Integer), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TPersistent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TAlign), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TAnchors), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TCursor), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTabOrder), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(THelpType), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(THelpContext), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TNotifyEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TMouseEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TMouseMoveEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TMouseWheelEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TMouseWheelUpDownEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TContextPopupEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TKeyEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TKeyPressEvent), TTyFormSurface, '', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TUTF8KeyPressEvent), TTyFormSurface, '', THiddenPropertyEditor);
  { The blanket rules above lose to any BY-NAME registration the IDE (or we) already made for the
    same property —a named match always beats an unnamed one. So hide those explicitly BY NAME too;
    with PersistentClass = TTyFormSurface they beat the IDE's TControl/TComponent-level editors (a
    more specific class always wins), whatever the registration order. }
  RegisterPropertyEditor(TypeInfo(TBasicAction), TTyFormSurface, 'Action', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TAnchors), TTyFormSurface, 'Anchors', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TSizeConstraints), TTyFormSurface, 'Constraints', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTyStyleController), TTyFormSurface, 'Controller', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TFont), TTyFormSurface, 'Font', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTranslateString), TTyFormSurface, 'Hint', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TComponentName), TTyFormSurface, 'Name', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TPopupMenu), TTyFormSurface, 'PopupMenu', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, 'StyleClass', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, 'StyleOverride', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTabOrder), TTyFormSurface, 'TabOrder', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(PtrInt), TTyFormSurface, 'Tag', THiddenPropertyEditor);
  // ———nd re-expose ONLY these two (named beats the blanket hides above; same class + named beats
  // the named hides too only because these are registered for the SAME class with the SAME
  // specificity —so they must be the LAST word: Version/Purpose are never in the hide list).
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, 'Version', TTyVersionEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyFormSurface, 'Purpose', TTySurfacePurposeEditor);
  // Page management verbs (Add/Delete/Show Next/Prev) for the page control.
  RegisterComponentEditor(TTyPageControl, TTyPageControlEditor);
  // Double-click a tree in the designer to open its node editor, the way LCL's own
  // TTreeView opens the "TreeView Items Editor". The Items collection itself already
  // has an editor (propedits registers TCollectionPropertyEditor for every TCollection);
  // this only supplies the double-click, which is how the feature is discovered.
  // GetComponentEditor picks the most-derived registration, so this also covers
  // TTyShellTreeView -- the editor asks SupportsItemModel and offers no verb there.
  RegisterComponentEditor(TTyTreeView, TTyTreeViewComponentEditor);
  { Right-click -> "Icon browser...". Registered on the BASE icon font, so every bundled pack
    (TTyLucideIconFont and whatever follows it) inherits the verb without another line here;
    GetComponentEditor picks the most-derived registration. }
  RegisterComponentEditor([TTyIconFont, TTyVirtualImageList], TTyIconBrowserComponentEditor);
  // Double-click a dialog component in the designer to preview it (verb 0 = Preview),
  // mirroring LCL's TCommonDialogComponentEditor.
  RegisterComponentEditor(
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog, TTyColorDialog, TTyFontDialog,
     TTyFindDialog, TTyReplaceDialog, TTyProgressDialog, TTyAboutDialog,
     TTyIconBrowserDialog],
    TTyDialogComponentEditor);
  // File > New > "TyControls Form": a unit whose form descends from TTyForm, pre-fitted
  // with a top-aligned title bar.
  RegisterProjectFileDescriptor(TTyFormFileDescriptor.Create);
  // File > New > "TyControls Dialog": a unit whose form descends from TTyDialog (close-only,
  // non-resizable modal), pre-fitted with a top-aligned title bar.
  RegisterProjectFileDescriptor(TTyDialogFileDescriptor.Create);
  // The themed main form (title bar + style controller). Intentionally NOT registered as a
  // New-item (so it doesn't appear in File > New) —it only makes sense as an application's
  // root window. The instance is kept alive for the whole IDE session because the "TyControls
  // Application" descriptor (CreateStartFiles) points File>New's project template at it.
  // TProjectFileDescriptor descends from TPersistent (not a refcounted interface), so nothing
  // owns this one now; the OS reclaims it at IDE shutdown —a benign one-per-session singleton.
  TyMainFormDescriptor := TTyMainFormFileDescriptor.Create;
  // File > New > Project > "TyControls Application": a GUI app whose main form is that
  // themed TTyForm, with the tycontrols dependency pre-added.
  RegisterProjectDescriptor(TTyApplicationDescriptor.Create);
end;

end.
