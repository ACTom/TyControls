unit tyControls.Design.PropEditors;
{$mode objfpc}{$H+}
{ Every TPropertyEditor this package registers, and the one procedure that registers
  them all (RegisterPropertyEditors, called from tyControls.Design.Register).

  Split out of tyControls.Design when that unit passed nineteen hundred lines; the
  drift-guard tests (test.version / test.designeditors / test.designregistry) scan the
  whole designtime/ directory, so registrations are found wherever they live. }
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, Graphics, LCLType,
  PropEdits, TypInfo, BGRABitmap,
  tyControls.Types, tyControls.Component, tyControls.Base, tyControls.Controller,
  tyControls.StyleModel, tyControls.BuiltinThemes, tyControls.ThemeRegistry,
  tyControls.IconFont, tyControls.Icons.Lucide, tyControls.ImageCollection,
  tyControls.Ribbon, tyControls.Popover, tyControls.Form, tyControls.Menu,
  tyControls.Dialogs, tyControls.Dialogs.About, tyControls.Dialogs.IconBrowser,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.FileDialog,
  tyControls.ShellComboBox, tyControls.ShellListView, tyControls.ShellTreeView,
  tyControls.FilterComboBox, tyControls.CharImage, tyControls.GlyphButtons,
  { The SynEdit-backed tycss editor for StyleOverride (design-time only). }
  tyControls.Design.Css.Editor;

type
  TTyStyleClassPropertyEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure GetValues(Proc: TGetStrProc); override;
  end;

  { License (TTyLucideImageList): read-only attribution. paReadOnly so it cannot be edited in
    place; paDialog so the '...' pops the FULL ISC + MIT licence text in a Ty message box. }
  TTyLucideLicenseProperty = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { TTyColor (= Cardinal $AARRGGBB) shows as a raw integer (4278190080) in the OI, which nobody
    can read or fill. This shows it as $AARRGGBB hex and opens a colour picker on '...', keeping
    the existing alpha byte (the picker only chooses RGB). }
  TTyColorPropertyEditor = class(TOrdinalPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
    procedure SetValue(const NewValue: string); override;
    procedure Edit; override;
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
    (paPickList must not appear in this package). paSortList is a separate question — purely
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
    Reached by RTTI rather than by a cast:
    TTyCharImage and TTyGlyphButtonBase both publish IconFont but share no ancestor that
    declares it, and a future control publishing the same pair gets the dropdown for free. }
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

  { Editor for the read-only `Version` property: shows TyVersion in the Object Inspector and
    opens the About dialog (version + clickable homepage link) when the '...' button is clicked. }
  TTyVersionEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

  { Read-only `Purpose` property on TTyFormSurface: the OI shows a one-line summary and the '...'
    button explains WHY the surface exists and why it must not be deleted or re-laid-out. Together
    with `Version` it is the only property left visible on the surface (see RegisterPropertyEditors). }
  TTySurfacePurposeEditor = class(TStringPropertyEditor)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

{ All RegisterPropertyEditor calls of the package (including the THiddenPropertyEditor
  hides); called once from tyControls.Design.Register. }
procedure RegisterPropertyEditors;

resourcestring
  { Shared with the component editors: both the GlyphName '...' and the icon-browser verb
    say it when there is no font to browse. }
  rsDtIconNeedsFont = 'Set IconFont first: there is no icon font to browse.';

implementation

resourcestring
  rsDtAboutTitle   = 'About TyControls';
  rsDtAboutTagline = 'BGRABitmap-drawn, .tycss-themed LCL control library';
  rsDtAboutVersion = 'Version %s';
  rsDtAboutLicense = 'Modified LGPL (LCL-compatible linking exception)';
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

{ The design-time 'Version' property (OI '...' button) opens the library's OWN themed
  TTyAboutDialog —so what you see at design time is exactly the dialog consumers ship, custom
  title bar and all. Empty fields (here: copyright) are omitted by the dialog. }
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

function TTyLucideLicenseProperty.GetAttributes: TPropertyAttributes;
begin
  { Read-only text with a dialog: the '...' shows the full licence, but the field cannot be typed
    into (it is not a setting). paReadOnly keeps it out of the inline-edit / streaming path. }
  Result := (inherited GetAttributes) + [paReadOnly, paDialog];
end;

procedure TTyLucideLicenseProperty.Edit;
begin
  { The full ISC + MIT (Feather) text, in the library's own message box, out of respect for
    Lucide. Design-time only -- no run-time dependency is added to the component. }
  TyMessageDlg(TyLucideLicense, mtInformation, [mbOK], 0);
end;

function TTyColorPropertyEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paDialog, paRevertable, paAutoUpdate];
end;

function TTyColorPropertyEditor.GetValue: string;
begin
  Result := '$' + IntToHex(Cardinal(GetOrdValue), 8);   { $AARRGGBB }
end;

procedure TTyColorPropertyEditor.SetValue(const NewValue: string);
var
  s: string;
  v: Int64;
begin
  s := Trim(NewValue);
  if (s <> '') and (s[1] = '#') then s := '$' + Copy(s, 2, MaxInt);   { accept #AARRGGBB too }
  if (s <> '') and (s[1] <> '$') then s := '$' + s;                    { and bare hex }
  if TryStrToInt64(s, v) then SetOrdValue(LongInt(Cardinal(v)));
end;

procedure TTyColorPropertyEditor.Edit;
var
  dlg: TColorDialog;
  ty: Cardinal;
  a, r, g, b: Byte;
begin
  ty := Cardinal(GetOrdValue);
  a := (ty shr 24) and $FF; r := (ty shr 16) and $FF; g := (ty shr 8) and $FF; b := ty and $FF;
  dlg := TColorDialog.Create(nil);
  try
    dlg.Color := RGBToColor(r, g, b);
    if dlg.Execute then
    begin
      RedGreenBlue(ColorToRGB(dlg.Color), r, g, b);
      { keep the existing alpha -- the picker only offers RGB }
      SetOrdValue(LongInt((Cardinal(a) shl 24) or (Cardinal(r) shl 16) or (Cardinal(g) shl 8) or b));
    end;
  finally
    dlg.Free;
  end;
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

{ ---- registration ---- }

procedure RegisterPropertyEditors;
begin
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
  // StyleOverride: the '...' opens a SynEdit tycss editor with catalog completion. Control-level
  // (no selectors) on the two bases; controller-level (with selectors) on the controller.
  RegisterPropertyEditor(TypeInfo(string), TTyGraphicControl, 'StyleOverride',
    TTyStyleOverrideProperty);
  RegisterPropertyEditor(TypeInfo(string), TTyCustomControl, 'StyleOverride',
    TTyStyleOverrideProperty);
  RegisterPropertyEditor(TypeInfo(string), TTyStyleController, 'StyleOverride',
    TTyStyleOverrideProperty);
  // Both bundled Lucide components carry their attribution: '...' pops the full ISC + MIT text.
  RegisterPropertyEditor(TypeInfo(string), TTyLucideImageList, 'License',
    TTyLucideLicenseProperty);
  RegisterPropertyEditor(TypeInfo(string), TTyLucideIconFont, 'License',
    TTyLucideLicenseProperty);
  { The bundled Lucide font is fixed: family is 'lucide', there is no file, and Glyphs is empty
    (a resolver maps all 2000 names). Hide the three so the OI does not offer edits that would
    only break the pack or mislead. }
  RegisterPropertyEditor(TypeInfo(string), TTyLucideIconFont, 'FontFamily', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(string), TTyLucideIconFont, 'FontFile', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TStringList), TTyLucideIconFont, 'Glyphs', THiddenPropertyEditor);
  { The bundled Lucide LIST is fixed the same way (real-machine feedback: the inherited
    source pickers read as "wire me up"): its IconFont is the shared Lucide font the
    constructor sets, and the bitmap-collection source is never this component's way in --
    you pick NAMES. Hide both; Names/DefaultSize/GlyphColor stay, they are the point. }
  RegisterPropertyEditor(TypeInfo(TTyImageCollection), TTyLucideImageList, 'Collection', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TTyIconFont), TTyLucideImageList, 'IconFont', THiddenPropertyEditor);
  // Every TTyColor property ($AARRGGBB) gets a readable hex value + a colour picker on '...',
  // instead of a raw integer like 4278190080 nobody can fill (DefaultColor, GlyphColor, ...).
  RegisterPropertyEditor(TypeInfo(TTyColor), nil, '', TTyColorPropertyEditor);
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
  // tests/test.version.pas READS THESE LINES: it parses the designtime sources for the
  // registrations and asserts every registered component descends from one of them, so a
  // component that gains the property off this tree —and would therefore show a dead entry
  // in the OI —is caught.
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
  { These three leak through the by-type hides above because their types are not plain
    Integer/etc.: TBorderWidth is a subrange, TDragKind/TDragMode are enums. The Surface is an
    internal content host -- none of them mean anything on it. }
  RegisterPropertyEditor(TypeInfo(TBorderWidth), TTyFormSurface, 'BorderWidth', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TDragKind), TTyFormSurface, 'DragKind', THiddenPropertyEditor);
  RegisterPropertyEditor(TypeInfo(TDragMode), TTyFormSurface, 'DragMode', THiddenPropertyEditor);
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
end;

end.
