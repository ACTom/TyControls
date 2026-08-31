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
  tyControls.IconFont, tyControls.ImageCollection,
  tyControls.Dialogs, tyControls.Dialogs.IconBrowser,
  tyControls.Dialogs.ImageCollectionEditor, tyControls.Dialogs.StructureEditor,
  tyControls.Dialogs.ListGroupsEditor, tyControls.Dialogs.TreeNodesEditor,
  tyControls.Dialogs.CascaderEditor,
  tyControls.Dialogs.SelectPath, tyControls.Dialogs.Color, tyControls.Dialogs.Font,
  tyControls.Dialogs.Find, tyControls.Dialogs.Progress, tyControls.Dialogs.About,
  tyControls.ListGroupPanel, tyControls.PageControl, tyControls.TabSheet,
  tyControls.TreeView, tyControls.Cascader, tyControls.TreeSelect,
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

{ ---- registration ---- }

procedure RegisterComponentEditors;
begin
  // Page management verbs (Add/Delete/Show Next/Prev) for the page control.
  RegisterComponentEditor(TTyPageControl, TTyPageControlEditor);
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
