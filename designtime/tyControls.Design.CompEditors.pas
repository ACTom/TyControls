unit tyControls.Design.CompEditors;
{$mode objfpc}{$H+}
{ Every TComponentEditor this package registers (verbs, double-clicks, and the modeless
  structure-editor links), and the one procedure that registers them all
  (RegisterComponentEditors, called from tyControls.Design.Register).

  Split out of tyControls.Design when that unit passed nineteen hundred lines; the
  drift-guard tests scan the whole designtime/ directory. }
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs, Menus, ClipBrd,
  PropEdits, PropEditUtils, ComponentEditors,
  tyControls.AdvanceChart, tyControls.Design.AdvChart.Editor,
  tyControls.IconFont, tyControls.ImageCollection,
  tyControls.Dialogs, tyControls.Dialogs.IconBrowser,
  tyControls.Dialogs.ImageCollectionEditor, tyControls.Dialogs.StructureEditor,
  tyControls.Dialogs.ListGroupsEditor, tyControls.Dialogs.TreeNodesEditor,
  tyControls.Dialogs.CascaderEditor,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.Color, tyControls.Dialogs.Font,
  tyControls.Dialogs.Find, tyControls.Dialogs.Progress, tyControls.Dialogs.About,
  tyControls.ListGroupPanel, tyControls.PageControl, tyControls.TabSheet,
  tyControls.TreeView, tyControls.Cascader, tyControls.TreeSelect,
  { The terminal's colour schemes: reading, choosing and the errors are in the runtime unit
    (tested there); the editor below is only the IDE half. }
  tyControls.Terminal, tyControls.Terminal.ColorScheme,
  { Tool window bars / tool windows. Whether a verb applies, and the model half of each verb,
    live in the runtime unit DesignRules (testable headless); this unit only does the IDE half. }
  tyControls.ToolWindows, tyControls.ToolWindows.DesignRules,
  { AddUndoAction takes its old / new values as variants. }
  Variants,
  { rsDtIconNeedsFont is shared with the GlyphName property editor. }
  tyControls.Design.PropEditors;

type
  { Right-click an icon font (or a bundled pack, or an image list fed by one) -> "Icon
    browser...". A two-thousand-entry dropdown is technically complete and practically
    useless; this is how a user actually finds the icon that means "save".

    On an icon font the picked name goes to the CLIPBOARD, because the font itself has no
    single name property to write it into -- the user is looking a name up to paste somewhere.
    On a TTyVirtualImageList it is APPENDED to Names, which is the thing that list is for. }
  TTyIconBrowserComponentEditor = class(TComponentEditor)
  private
    FPickTarget: TTyVirtualImageList;
    function FontOf(out AOwnerList: TTyVirtualImageList): TTyIconFont;
    procedure HandlePickName(Sender: TObject; const AName: string);
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { TTyImageCollection's double-click: the TImageList-style manager (list + preview +
    Add/Replace/Delete/Rename/Move over a working copy; OK commits, Cancel discards).
    The standard '...' collection grid stays available for per-item surgery — this is
    the everyday door (QQ-group request: the bare grid made adding pictures a chore). }
  TTyImageCollectionComponentEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { TTyListGroupPanel's double-click: the modeless structure editor -- ONE tree over
    every group and item (real-machine feedback: the stock collection editor shows one
    layer per open, so authoring a second group's items meant reopening editors).
    TComponentEditor, not TDefaultComponentEditor: double-click must open this, not
    generate an OnClick handler. }
  TTyListGroupPanelComponentEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { A structure editor's IDE plumbing, the stock collection editor's lifecycle: one
    shared modeless window per editor kind; the tree's selection is routed into the
    Object Inspector, every edit marks the designer modified, outside edits refresh
    the tree, and the subject going away detaches the window. Subclasses supply the
    window (CreateEditorForm) and the "is this persistent part of my model" answer
    (OwnsModelObject). }
  TTyStructureDesignerLink = class(TComponent)
  private
    FForm: TTyStructureEditorForm;
    FSubject: TComponent;
    procedure EditorSelectObject(Sender: TObject; AObject: TPersistent);
    procedure EditorEdited(Sender: TObject);
    procedure HookPersistentDeleting(APersistent: TPersistent);
    procedure HookRefresh;
  protected
    function CreateEditorForm: TTyStructureEditorForm; virtual; abstract;
    function OwnsModelObject(APersistent: TPersistent): Boolean; virtual; abstract;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    destructor Destroy; override;
    procedure ShowFor(ASubject: TComponent);
    procedure Detach;
  end;
  TTyStructureDesignerLinkClass = class of TTyStructureDesignerLink;

  TTyListGroupsDesignerLink = class(TTyStructureDesignerLink)
  protected
    function CreateEditorForm: TTyStructureEditorForm; override;
    function OwnsModelObject(APersistent: TPersistent): Boolean; override;
  end;

  TTyTreeNodesDesignerLink = class(TTyStructureDesignerLink)
  protected
    function CreateEditorForm: TTyStructureEditorForm; override;
    function OwnsModelObject(APersistent: TPersistent): Boolean; override;
  end;

  TTyCascaderDesignerLink = class(TTyStructureDesignerLink)
  protected
    function CreateEditorForm: TTyStructureEditorForm; override;
    function OwnsModelObject(APersistent: TPersistent): Boolean; override;
  end;

  { Manages TTyPageControl pages in the designer (no header click-switch on a
    custom-drawn control). Verbs: Add / Delete / Show Next / Show Previous Page. }
  TTyPageControlEditor = class(TDefaultComponentEditor)
  private
    function PC: TTyPageControl;
    procedure ShowPageMenuItemClick(Sender: TObject);
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
    { The 'Show Page' verb is a submenu listing every page by name, mirroring LCL's
      TTabControlComponentEditor: a direct jump beats cycling Next/Previous on a
      many-page control, and it is the designer answer to "switching pages needs
      typing ActivePageIndex" (QQ-group report). }
    procedure PrepareItem(Index: Integer; const AnItem: TMenuItem); override;
  end;

  { A tool window bar's context menu (spec §11): "New Tool Window" and "Show Window >".
    TDefaultComponentEditor like TTyPageControlEditor: a double-click generates the default
    event handler rather than running verb 0 (which would add a window on every double-click).
    No "Delete Tool Window": Hook.DeletePersistent skips the inherited-component check, the
    owner check and the undo record (designer.pp:3144-3179), so it could delete an inherited
    window in a descendant form. The Delete key does it properly. }
  TTyToolWindowBarEditor = class(TDefaultComponentEditor)
  private
    function Bar: TTyToolWindowBar;
    procedure ShowWindowItemClick(Sender: TObject);
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
    procedure PrepareItem(Index: Integer; const AnItem: TMenuItem); override;
  end;

  { A tool window's context menu (spec §11): "Add Actions Area", "Move to Other Side Bar",
    "Move Back into Bar >". Always the same three items, greyed when they do not apply, so the
    menu does not shift under the user's hand. Whether an item applies and what it targets are
    asked of tyControls.ToolWindows.DesignRules; nothing is decided here. }
  TTyToolWindowEditor = class(TDefaultComponentEditor)
  private
    function Win: TTyToolWindow;
    procedure MoveBackItemClick(Sender: TObject);
    { One undo step for a reparent done by "Move to Other Side Bar" / "Move Back into Bar". }
    procedure RecordParentUndo(AOldParent, ANewParent: TWinControl);
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
    procedure PrepareItem(Index: Integer; const AnItem: TMenuItem); override;
  end;

  { Opens the node editor when a TTyTreeView is double-clicked in the designer.

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

  { TTyCascader's double-click: the modeless option editor -- ONE tree over the whole
    nested Nodes model (the stock collection editor shows one nesting level per open,
    a window per branch of a province/city/district tree). }
  TTyCascaderComponentEditor = class(TComponentEditor)
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

  { TTyTreeSelect's double-click: the SAME node editor, aimed at the embedded dropdown
    tree (its published Items forward there). One editor to learn for every node tree. }
  TTyTreeSelectComponentEditor = class(TComponentEditor)
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

  { A terminal's context menu (terminal phase 6): "Import Windows Terminal colour scheme..." and
    "Export colour scheme...". Which schemes a file offers, reading one and writing one are
    runtime calls (TyTermSchemeImportPlan, TryLoadFromText, SaveToFile); here are only the file
    dialogs and the questions. TDefaultComponentEditor: a double-click still makes the default
    event handler. }
  TTyTerminalViewComponentEditor = class(TDefaultComponentEditor)
  private
    function Term: TTyTerminalView;
    { paired: which of the two schemes (light = ColorScheme, dark = DarkColorScheme);
      False when the user cancels }
    function PickSide(const APrompt: string; out ADark: Boolean): Boolean;
    procedure ImportScheme;
    procedure ExportScheme;
  public
    function GetVerbCount: Integer; override;
    function GetVerb(Index: Integer): string; override;
    procedure ExecuteVerb(Index: Integer); override;
  end;

{ All RegisterComponentEditor calls of the package; called once from tyControls.Design.Register. }
procedure RegisterComponentEditors;

implementation

type
  { GetOwner is protected on TPersistent; walking an option to its root cascader
    (TTyCascaderDesignerLink.OwnsModelObject) goes through it. }
  TNodesOwnerAccess = class(TTyCascaderNodes);

resourcestring
  rsDtCascEdit     = 'Edit options...';
  rsDtPageAdd      = 'Add Page';
  rsDtPageDelete   = 'Delete Page';
  rsDtPageShowNext = 'Show Next Page';
  rsDtPageShowPrev = 'Show Previous Page';
  rsDtPageShowPage = 'Show Page';
  rsDtDialogPreview = 'Preview';
  { The verbs this library's icon fonts, image lists and structured panels carry. IDE-facing,
    so they belong in this package's table and not the runtime package's -- the two have
    separate .po catalogues. }
  rsDtIconBrowse    = 'Icon browser...';
  rsDtImgColEdit    = 'Edit images...';
  rsDtGroupsEdit    = 'Edit groups...';
  rsDtTreeEditNodes = 'Edit Nodes...';
  { Tool window bars and tool windows (spec §11). Whether each verb applies is decided in the
    runtime unit tyControls.ToolWindows.DesignRules, where it can be tested. }
  rsDtTwNewWindow     = 'New Tool Window';
  rsDtTwShowWindow    = 'Show Window';
  rsDtTwAddActions    = 'Add Actions Area';
  rsDtTwMoveOtherSide = 'Move to Other Side Bar';
  rsDtTwMoveBack      = 'Move Back into Bar';
  { The terminal's colour schemes (terminal phase 6) }
  rsDtTermImport      = 'Import Windows Terminal colour scheme...';
  rsDtTermExport      = 'Export colour scheme...';
  rsDtTermFilter      = 'Windows Terminal colour schemes (*.json)|*.json|All files (*.*)|*.*';
  rsDtTermWhichScheme = 'Which colour scheme?';
  rsDtTermImportSide  = 'Write it into which scheme?';
  rsDtTermExportSide  = 'Export which scheme?';
  rsDtTermLight       = 'Light';
  rsDtTermDark        = 'Dark';
  rsDtTermUseScheme   = 'Use the custom colour scheme instead of the theme?';

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
    if lst <> nil then
    begin
      { Live multi-add: every pick (double-click / Enter) lands in Names at once -- the
        cell's ImageIndex badge appearing IS the feedback -- and the browser stays open,
        so ten icons cost one browse, not ten (QQ-group report). OK and Cancel both just
        close; the additions are already committed. }
      FPickTarget := lst;
      try
        dlg.OnPickName := @HandlePickName;
        dlg.ShowModal;
      finally
        FPickTarget := nil;
      end;
      Exit;
    end;
    if dlg.ShowModal <> mrOK then Exit;
    nm := dlg.GlyphName;
  finally
    dlg.Free;
  end;
  if nm = '' then Exit;
  { A font has no single name property to write into -- the user came here to look a name up.
    The clipboard is where a looked-up name is useful. }
  Clipboard.AsText := nm;
end;

procedure TTyIconBrowserComponentEditor.HandlePickName(Sender: TObject; const AName: string);
begin
  if (FPickTarget = nil) or (AName = '') then Exit;
  if FPickTarget.Names.IndexOf(AName) >= 0 then Exit;   // a re-pick is a no-op, not a dupe
  FPickTarget.Names.Add(AName);
  Modified;          { tell the designer the form changed, or the edit is lost on close }
end;

{ TTyImageCollectionComponentEditor }

function TTyImageCollectionComponentEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyImageCollectionComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then Result := rsDtImgColEdit else Result := '';
end;

procedure TTyImageCollectionComponentEditor.ExecuteVerb(Index: Integer);
begin
  if Index <> 0 then begin inherited ExecuteVerb(Index); Exit; end;
  if TyEditImageCollection(Component as TTyImageCollection) then
    Modified;    { the commit changed the collection; the designer must hear about it }
end;

{ TTyListGroupPanelComponentEditor }

function TTyListGroupPanelComponentEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyListGroupPanelComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then Result := rsDtGroupsEdit else Result := '';
end;

var
  ListGroupsLink: TTyListGroupsDesignerLink = nil;
  TreeNodesLink: TTyTreeNodesDesignerLink = nil;
  CascaderLink: TTyCascaderDesignerLink = nil;

procedure TTyListGroupPanelComponentEditor.ExecuteVerb(Index: Integer);
begin
  if Index <> 0 then begin inherited ExecuteVerb(Index); Exit; end;
  if ListGroupsLink = nil then
    ListGroupsLink := TTyListGroupsDesignerLink.Create(Application);
  ListGroupsLink.ShowFor(Component as TTyListGroupPanel);
end;

{ TTyStructureDesignerLink }

destructor TTyStructureDesignerLink.Destroy;
begin
  if GlobalDesignHook <> nil then
    GlobalDesignHook.RemoveAllHandlersForObject(Self);
  if ListGroupsLink = Self then ListGroupsLink := nil;
  if TreeNodesLink = Self then TreeNodesLink := nil;
  if CascaderLink = Self then CascaderLink := nil;
  inherited Destroy;   // FForm is owned by Self, freed with it
end;

procedure TTyStructureDesignerLink.ShowFor(ASubject: TComponent);
begin
  if ASubject = nil then Exit;
  if FForm = nil then
  begin
    FForm := CreateEditorForm;
    FForm.OnSelectObject := @EditorSelectObject;
    FForm.OnEdited := @EditorEdited;
  end;
  if FSubject <> ASubject then
  begin
    if FSubject <> nil then FSubject.RemoveFreeNotification(Self);
    FSubject := ASubject;
    FSubject.FreeNotification(Self);
    FForm.SetSubject(FSubject);
  end
  else
    FForm.RefreshFromModel;   // same target: the model may still have changed elsewhere
  if GlobalDesignHook <> nil then
  begin
    GlobalDesignHook.RemoveAllHandlersForObject(Self);
    GlobalDesignHook.AddHandlerPersistentDeleting(@HookPersistentDeleting);
    GlobalDesignHook.AddHandlerRefreshPropertyValues(@HookRefresh);
  end;
  FForm.Show;
  FForm.BringToFront;
end;

procedure TTyStructureDesignerLink.Detach;
begin
  if FSubject <> nil then FSubject.RemoveFreeNotification(Self);
  FSubject := nil;
  if FForm <> nil then
  begin
    FForm.SetSubject(nil);
    FForm.Hide;
  end;
end;

procedure TTyStructureDesignerLink.EditorSelectObject(Sender: TObject; AObject: TPersistent);
begin
  if (AObject = nil) or (FSubject = nil) or (GlobalDesignHook = nil) then Exit;
  GlobalDesignHook.LookupRoot := GetLookupRootForComponent(FSubject);
  GlobalDesignHook.SelectOnlyThis(AObject);
end;

procedure TTyStructureDesignerLink.EditorEdited(Sender: TObject);
begin
  if GlobalDesignHook <> nil then
    GlobalDesignHook.Modified(Self);
end;

procedure TTyStructureDesignerLink.HookPersistentDeleting(APersistent: TPersistent);
begin
  if FSubject = nil then Exit;
  if (APersistent = FSubject) or (APersistent = FSubject.Owner) then
    Detach
  else if OwnsModelObject(APersistent) then
    { The object still exists at this notice, so a rebuild would re-capture it: drop
      every pointer NOW; HookRefresh re-aims at the subject afterwards. }
    FForm.SetSubject(nil);
end;

procedure TTyStructureDesignerLink.HookRefresh;
begin
  if (FForm = nil) or not FForm.Visible or (FSubject = nil) then Exit;
  if FForm.Subject <> FSubject then
    FForm.SetSubject(FSubject)
  else
    FForm.RefreshFromModel;
end;

procedure TTyStructureDesignerLink.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSubject) then
    Detach;
end;

{ TTyListGroupsDesignerLink }

function TTyListGroupsDesignerLink.CreateEditorForm: TTyStructureEditorForm;
begin
  Result := TTyListGroupsEditorForm.CreateNew(Self);
end;

function TTyListGroupsDesignerLink.OwnsModelObject(APersistent: TPersistent): Boolean;
var
  P: TTyListGroupPanel;
begin
  Result := False;
  if FSubject = nil then Exit;
  P := FSubject as TTyListGroupPanel;
  if APersistent is TTyListGroup then
    Result := TTyListGroup(APersistent).Collection = P.Groups
  else if APersistent is TTyListGroupItem then
    Result := (TTyListGroupItem(APersistent).Collection as TTyListGroupItems)
                .Group.Collection = P.Groups;
end;

{ TTyTreeNodesDesignerLink }

function TTyTreeNodesDesignerLink.CreateEditorForm: TTyStructureEditorForm;
begin
  Result := TTyTreeNodesEditorForm.CreateNew(Self);
end;

function TTyTreeNodesDesignerLink.OwnsModelObject(APersistent: TPersistent): Boolean;
begin
  Result := (FSubject <> nil) and (APersistent is TTyTreeNodeItem)
    and (TTyTreeNodeItem(APersistent).Collection = (FSubject as TTyTreeView).Items);
end;

{ TTyCascaderDesignerLink }

function TTyCascaderDesignerLink.CreateEditorForm: TTyStructureEditorForm;
begin
  Result := TTyCascaderEditorForm.CreateNew(Self);
end;

function TTyCascaderDesignerLink.OwnsModelObject(APersistent: TPersistent): Boolean;

  { A cascader option can sit at any depth: walk collection -> owner-node -> its
    collection until the owner is a component, and see whether it is our cascader. }
  function RootOwnerOf(ANode: TTyCascaderNode): TPersistent;
  var
    coll: TTyCascaderNodes;
  begin
    Result := nil;
    while ANode <> nil do
    begin
      coll := ANode.Collection as TTyCascaderNodes;
      Result := TNodesOwnerAccess(coll).GetOwner;
      if Result is TTyCascaderNode then
        ANode := TTyCascaderNode(Result)
      else
        ANode := nil;
    end;
  end;

begin
  Result := (FSubject <> nil) and (APersistent is TTyCascaderNode)
    and (RootOwnerOf(TTyCascaderNode(APersistent)) = FSubject);
end;

{ TTyPageControlEditor }

function TTyPageControlEditor.PC: TTyPageControl;
begin
  Result := Component as TTyPageControl;
end;

function TTyPageControlEditor.GetVerbCount: Integer;
begin
  Result := 5;
end;

function TTyPageControlEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := rsDtPageAdd;
    1: Result := rsDtPageDelete;
    2: Result := rsDtPageShowNext;
    3: Result := rsDtPageShowPrev;
    4: Result := rsDtPageShowPage;
  else
    Result := '';
  end;
end;

procedure TTyPageControlEditor.ShowPageMenuItemClick(Sender: TObject);
var
  Item: TMenuItem;
  NewIndex: Integer;
begin
  if not (Sender is TMenuItem) then Exit;
  Item := TMenuItem(Sender);
  NewIndex := Item.MenuIndex;
  if (NewIndex < 0) or (NewIndex >= PC.PageCount) then Exit;
  PC.ActivePageIndex := NewIndex;
  GetDesigner.SelectOnlyThisComponent(PC.ActivePage);
end;

procedure TTyPageControlEditor.PrepareItem(Index: Integer; const AnItem: TMenuItem);
var
  i: Integer;
  Item: TMenuItem;
begin
  inherited PrepareItem(Index, AnItem);
  if Index <> 4 then Exit;
  AnItem.Enabled := PC.PageCount > 0;
  for i := 0 to PC.PageCount - 1 do
  begin
    Item := TMenuItem.Create(AnItem);
    Item.Name := 'TyShowPage' + IntToStr(i);
    Item.Caption := PC.Pages[i].Name + ' "' + PC.Pages[i].Caption + '"';
    Item.OnClick := @ShowPageMenuItemClick;
    AnItem.Add(Item);
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

{ TTyToolWindowBarEditor }

function TTyToolWindowBarEditor.Bar: TTyToolWindowBar;
begin
  Result := Component as TTyToolWindowBar;
end;

function TTyToolWindowBarEditor.GetVerbCount: Integer;
begin
  Result := 2;
end;

function TTyToolWindowBarEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := rsDtTwNewWindow;
    1: Result := rsDtTwShowWindow;
  else
    Result := '';
  end;
end;

procedure TTyToolWindowBarEditor.ShowWindowItemClick(Sender: TObject);
var
  i: Integer;
  W: TTyToolWindow;
begin
  if not (Sender is TMenuItem) then Exit;
  { GetDesigner is just whatever the editor was created with (componenteditors.pas:670-673).
    The IDE's two popups (the form designer's, the object inspector's component tree) always
    pass one (designer.pp, objectinspector.pp:5043-5056), but nothing promises it;
    without it there is nothing to select into. }
  if GetDesigner = nil then Exit;
  { The item carries only its position. Re-read the window list and bounds-check here instead
    of trusting what PrepareItem saw. }
  i := TMenuItem(Sender).MenuIndex;
  if (i < 0) or (i >= Bar.WindowCount) then Exit;
  W := Bar.Windows[i];
  { Design time: activate only. The bar tells the designer and refreshes the inspector
    itself (spec §5.1 step 6). }
  Bar.ActiveWindow := W;
  GetDesigner.SelectOnlyThisComponent(W);
end;

procedure TTyToolWindowBarEditor.PrepareItem(Index: Integer; const AnItem: TMenuItem);
var
  i: Integer;
  W: TTyToolWindow;
  Item: TMenuItem;
begin
  inherited PrepareItem(Index, AnItem);
  case Index of
    0: AnItem.Enabled := TyToolWindowDesignCanAddWindow(Bar);
    1: begin
         AnItem.Enabled := Bar.WindowCount > 0;
         for i := 0 to Bar.WindowCount - 1 do
         begin
           W := Bar.Windows[i];
           Item := TMenuItem.Create(AnItem);
           Item.Name := 'TyTwShow' + IntToStr(i);
           Item.Caption := W.Name + ' "' + W.Caption + '"';
           Item.OnClick := @ShowWindowItemClick;
           AnItem.Add(Item);
         end;
       end;
  end;
end;

procedure TTyToolWindowBarEditor.ExecuteVerb(Index: Integer);
var
  Hook: TPropertyEditorHook;
  W: TTyToolWindow;
begin
  if Index <> 0 then Exit;     { "Show Window" is a submenu; its items do the work }
  if not TyToolWindowDesignCanAddWindow(Bar) then Exit;
  Hook := nil;
  if not GetHook(Hook) then Exit;
  W := TTyToolWindow.Create(Bar.Owner);
  { Registering makes it the current page (the bar is not loading); a design-time switch
    tells the designer. }
  W.Parent := Bar;
  W.Name := GetDesigner.CreateUniqueComponentName(W.ClassName);
  W.Caption := W.Name;
  Hook.PersistentAdded(W, True);
  { PageControl's "Add Page" records no undo, so Ctrl+Z cannot take an added page away.
    Dropping from the palette records it with this very call (designer.pp:788). }
  GetDesigner.AddUndoAction(W, uopAdd, True, 'Name', '', W.Name);
  Modified;
end;

{ TTyToolWindowEditor }

function TTyToolWindowEditor.Win: TTyToolWindow;
begin
  Result := Component as TTyToolWindow;
end;

function TTyToolWindowEditor.GetVerbCount: Integer;
begin
  Result := 3;
end;

function TTyToolWindowEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := rsDtTwAddActions;
    1: Result := rsDtTwMoveOtherSide;
    2: Result := rsDtTwMoveBack;
  else
    Result := '';
  end;
end;

procedure TTyToolWindowEditor.RecordParentUndo(AOldParent, ANewParent: TWinControl);

  { Undo / redo find the parent again by name: the root itself, or root.FindComponent
    (designer.pp:1495-1498). Anything else (no parent at all, a control inside a frame
    instance) would come back as nil. }
  function Findable(AParent: TWinControl): Boolean;
  begin
    Result := (AParent <> nil) and (AParent.Name <> '')
      and ((AParent = Win.Owner) or (AParent.Owner = Win.Owner));
  end;

begin
  { The same record the component tree writes when it reparents a control
    (componenttreeview.pas:409-410). Undo replays it as a plain Parent := <found by name>
    (designer.pp:1487-1504), which goes through the bar's SetParent like any other design-time
    reparent: the window comes back as the current page at the end of its old bar -- its old
    position there is not restored. }
  if not (Findable(AOldParent) and Findable(ANewParent)) then Exit;
  GetDesigner.AddUndoAction(Win, uopChange, True, 'Parent', AOldParent.Name, ANewParent.Name);
end;

procedure TTyToolWindowEditor.MoveBackItemClick(Sender: TObject);
var
  targets: TTyToolWindowBarArray;
  i: Integer;
  oldParent: TWinControl;
begin
  if not (Sender is TMenuItem) then Exit;
  { GetDesigner is just whatever the editor was created with (componenteditors.pas:670-673);
    the IDE always passes one, but nothing promises it. }
  if GetDesigner = nil then Exit;
  { The item carries only its position. Recompute the candidates and bounds-check here instead
    of trusting what PrepareItem saw, like TTyPageControlEditor.ShowPageMenuItemClick. }
  targets := TyToolWindowDesignReturnTargets(Win);
  i := TMenuItem(Sender).MenuIndex;
  if (i < 0) or (i > High(targets)) then Exit;
  oldParent := Win.Parent;
  if TyToolWindowDesignReturnToBar(Win, targets[i]) then
  begin
    RecordParentUndo(oldParent, targets[i]);
    Modified;
    GetDesigner.SelectOnlyThisComponent(Win);
  end;
end;

procedure TTyToolWindowEditor.PrepareItem(Index: Integer; const AnItem: TMenuItem);
var
  targets: TTyToolWindowBarArray;
  i: Integer;
  Item: TMenuItem;
begin
  inherited PrepareItem(Index, AnItem);
  case Index of
    0: AnItem.Enabled := TyToolWindowDesignCanAddActions(Win);
    1: AnItem.Enabled := TyToolWindowDesignOtherSide(Win) <> nil;
    2: begin
         targets := TyToolWindowDesignReturnTargets(Win);
         AnItem.Enabled := Length(targets) > 0;
         for i := 0 to High(targets) do
         begin
           Item := TMenuItem.Create(AnItem);
           Item.Name := 'TyTwBack' + IntToStr(i);
           Item.Caption := targets[i].Name;
           Item.OnClick := @MoveBackItemClick;
           AnItem.Add(Item);
         end;
       end;
  end;
end;

procedure TTyToolWindowEditor.ExecuteVerb(Index: Integer);
var
  Hook: TPropertyEditorHook;
  A: TTyToolWindowActions;
  oldBar: TTyToolWindowBar;
begin
  case Index of
    0: begin
         if not TyToolWindowDesignCanAddActions(Win) then Exit;
         Hook := nil;
         if not GetHook(Hook) then Exit;
         A := Win.EnsureActions;
         A.Name := GetDesigner.CreateUniqueComponentName(A.ClassName);
         Hook.PersistentAdded(A, True);
         GetDesigner.AddUndoAction(A, uopAdd, True, 'Name', '', A.Name);
         Modified;
       end;
    1: begin
         { MoveWindow notifies the designer itself at design time (spec §11, C-phase
           correction), so no Modified here. }
         if GetDesigner = nil then Exit;
         oldBar := Win.Bar;
         if TyToolWindowDesignMoveToOtherSide(Win) then
         begin
           RecordParentUndo(oldBar, Win.Bar);
           GetDesigner.SelectOnlyThisComponent(Win);
         end;
       end;
    { 2 is the "Move Back into Bar" submenu; its items do the work. }
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
  { The structure editor: one tree, any depth, Add Node / Add Child / block moves --
    Delphi's 'TreeView Items Editor'. The stock collection editor (rows plus a
    hand-typed Level number) stays reachable through the OI's Items '...' button. }
  if TreeNodesLink = nil then
    TreeNodesLink := TTyTreeNodesDesignerLink.Create(Application);
  TreeNodesLink.ShowFor(Tree);
end;

{ TTyTreeSelectComponentEditor }

function TTyTreeSelectComponentEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyTreeSelectComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then Result := rsDtTreeEditNodes else Result := '';
end;

procedure TTyTreeSelectComponentEditor.ExecuteVerb(Index: Integer);
begin
  if Index <> 0 then begin inherited ExecuteVerb(Index); Exit; end;
  if TreeNodesLink = nil then
    TreeNodesLink := TTyTreeNodesDesignerLink.Create(Application);
  { Aim at the embedded tree: the editor's Model reads (Subject as TTyTreeView).Items,
    which is the same collection the published Items forward. The link's Owner check
    (HookPersistentDeleting: Subject.Owner) is the TreeSelect itself, so deleting the
    field detaches the window. }
  TreeNodesLink.ShowFor((Component as TTyTreeSelect).Tree);
end;

{ TTyCascaderComponentEditor }

function TTyCascaderComponentEditor.GetVerbCount: Integer;
begin
  Result := 1;
end;

function TTyCascaderComponentEditor.GetVerb(Index: Integer): string;
begin
  if Index = 0 then Result := rsDtCascEdit else Result := '';
end;

procedure TTyCascaderComponentEditor.ExecuteVerb(Index: Integer);
begin
  if Index <> 0 then begin inherited ExecuteVerb(Index); Exit; end;
  if CascaderLink = nil then
    CascaderLink := TTyCascaderDesignerLink.Create(Application);
  CascaderLink.ShowFor(Component as TTyCascader);
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

{ TTyTerminalViewComponentEditor }

function TTyTerminalViewComponentEditor.Term: TTyTerminalView;
begin
  Result := Component as TTyTerminalView;
end;

function TTyTerminalViewComponentEditor.GetVerbCount: Integer;
begin
  Result := 2;
end;

function TTyTerminalViewComponentEditor.GetVerb(Index: Integer): string;
begin
  case Index of
    0: Result := rsDtTermImport;
    1: Result := rsDtTermExport;
  else
    Result := inherited GetVerb(Index);
  end;
end;

procedure TTyTerminalViewComponentEditor.ExecuteVerb(Index: Integer);
begin
  case Index of
    0: ImportScheme;
    1: ExportScheme;
  else
    inherited ExecuteVerb(Index);
  end;
end;

function TTyTerminalViewComponentEditor.PickSide(const APrompt: string; out ADark: Boolean): Boolean;
var
  pick: Integer;
begin
  ADark := False;
  pick := InputCombo(StringReplace(rsDtTermImport, '...', '', []), APrompt, [rsDtTermLight, rsDtTermDark]);
  Result := pick >= 0;
  ADark := pick = 1;
end;

procedure TTyTerminalViewComponentEditor.ImportScheme;
var
  dlg: TOpenDialog;
  fs: TFileStream;
  txt, err, nm: string;
  names: TStringArray;
  list: TStringList;
  i, pick: Integer;
  dark: Boolean;
  target: TTyTerminalColorScheme;
begin
  dlg := TOpenDialog.Create(nil);
  try
    dlg.Filter := rsDtTermFilter;
    dlg.Options := dlg.Options + [ofFileMustExist];
    if not dlg.Execute then Exit;
    txt := '';
    try
      fs := TFileStream.Create(dlg.FileName, fmOpenRead or fmShareDenyWrite);
      try
        SetLength(txt, fs.Size);
        if Length(txt) > 0 then fs.ReadBuffer(txt[1], Length(txt));
      finally
        fs.Free;
      end;
    except
      on E: Exception do
      begin
        TyMessageDlg(E.Message, mtError, [mbOK]);
        Exit;
      end;
    end;
  finally
    dlg.Free;
  end;
  if not TyTermSchemeImportPlan(txt, names, err) then
  begin
    TyMessageDlg(err, mtError, [mbOK]);
    Exit;
  end;
  if Length(names) = 1 then
    nm := names[0]
  else
  begin
    list := TStringList.Create;
    try
      for i := 0 to High(names) do
        list.Add(names[i]);
      pick := InputCombo(StringReplace(rsDtTermImport, '...', '', []), rsDtTermWhichScheme, list);
    finally
      list.Free;
    end;
    if pick < 0 then Exit;
    nm := names[pick];
  end;
  dark := False;
  if Term.ColorSchemePaired and not PickSide(rsDtTermImportSide, dark) then Exit;
  if dark then
    target := Term.DarkColorScheme
  else
    target := Term.ColorScheme;
  if not target.TryLoadFromText(txt, nm, err) then
  begin
    TyMessageDlg(err, mtError, [mbOK]);
    Exit;
  end;
  if (Term.ColorSource = tsrcTheme)
    and (TyMessageDlg(rsDtTermUseScheme, mtConfirmation, [mbYes, mbNo]) = mrYes) then
    Term.ColorSource := tsrcScheme;
  Modified;
end;

procedure TTyTerminalViewComponentEditor.ExportScheme;
var
  dlg: TSaveDialog;
  dark: Boolean;
  src: TTyTerminalColorScheme;
begin
  dark := False;
  if Term.ColorSchemePaired and not PickSide(rsDtTermExportSide, dark) then Exit;
  if dark then
    src := Term.DarkColorScheme
  else
    src := Term.ColorScheme;
  dlg := TSaveDialog.Create(nil);
  try
    dlg.Filter := rsDtTermFilter;
    dlg.DefaultExt := 'json';
    dlg.Options := dlg.Options + [ofOverwritePrompt];
    if src.Name <> '' then
      dlg.FileName := src.Name + '.json';
    if not dlg.Execute then Exit;
    try
      { a scheme with no name or a missing colour is refused before the file is created }
      src.SaveToFile(dlg.FileName);
    except
      on E: Exception do
        TyMessageDlg(E.Message, mtError, [mbOK]);
    end;
  finally
    dlg.Free;
  end;
end;

{ ---- registration ---- }

procedure RegisterComponentEditors;
begin
  // Double-clicking the chart opens the same option dialog its property editor
  // does. One verb, one code path -- a second entry point that assembled the
  // dialog its own way is how the two drift apart.
  RegisterComponentEditor(TTyAdvanceChart, TTyAdvanceChartEditor);
  // Page management verbs (Add/Delete/Show Next/Prev) for the page control.
  RegisterComponentEditor(TTyPageControl, TTyPageControlEditor);
  // Tool window bars: New Tool Window / Show Window; tool windows: Add Actions Area / Move to
  // Other Side Bar / Move Back into Bar (spec §11). Double-click still makes the default event.
  RegisterComponentEditor(TTyToolWindowBar, TTyToolWindowBarEditor);
  RegisterComponentEditor(TTyToolWindow, TTyToolWindowEditor);
  // Double-click a tree in the designer to open its node editor, the way LCL's own
  // TTreeView opens the "TreeView Items Editor". GetComponentEditor picks the
  // most-derived registration, so this also covers TTyShellTreeView -- the editor asks
  // SupportsItemModel and offers no verb there.
  RegisterComponentEditor(TTyTreeView, TTyTreeViewComponentEditor);
  { Right-click -> "Icon browser...". Registered on the BASE icon font, so every bundled pack
    (TTyLucideIconFont and whatever follows it) inherits the verb without another line here;
    GetComponentEditor picks the most-derived registration. }
  RegisterComponentEditor([TTyIconFont, TTyVirtualImageList], TTyIconBrowserComponentEditor);
  RegisterComponentEditor(TTyImageCollection, TTyImageCollectionComponentEditor);
  RegisterComponentEditor(TTyListGroupPanel, TTyListGroupPanelComponentEditor);
  // Double-click a cascader to edit its nested option tree in one window.
  RegisterComponentEditor(TTyCascader, TTyCascaderComponentEditor);
  // Double-click a tree-select to edit its dropdown tree -- the same node editor,
  // aimed at the embedded tree the published Items forward to.
  RegisterComponentEditor(TTyTreeSelect, TTyTreeSelectComponentEditor);
  // Right-click a terminal: import / export a Windows Terminal colour scheme.
  RegisterComponentEditor(TTyTerminalView, TTyTerminalViewComponentEditor);
  // Double-click a dialog component in the designer to preview it (verb 0 = Preview),
  // mirroring LCL's TCommonDialogComponentEditor.
  RegisterComponentEditor(
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog, TTyColorDialog, TTyFontDialog,
     TTyFindDialog, TTyReplaceDialog, TTyProgressDialog, TTyAboutDialog,
     TTyIconBrowserDialog],
    TTyDialogComponentEditor);
end;

end.
