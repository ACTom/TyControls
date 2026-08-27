unit tyControls.Dialogs.ImageCollectionEditor;
{$mode objfpc}{$H+}
{ The image-collection manager: the dialog behind a TTyImageCollection's design-time
  double-click, and usable from applications the same way (QQ-group request -- the bare
  collection grid made adding real pictures a chore; a TImageList-style manager was the
  expectation).

  It edits a WORKING COPY: Add / Replace / Delete / Rename / Move act immediately on the
  copy (with a live preview), and only OK commits the copy back to the source collection --
  Cancel discards everything, which is what OK/Cancel dialogs promise. Rename renames the
  whole NAME FAMILY (several masters may share a name, one per authored resolution; a
  half-renamed family would silently fall out of its multi-resolution set).

  Construct-only builder + public action seams (AddFromFile / DeleteSelected / ...), so
  every behaviour is assertable headlessly -- the TTyIconBrowserForm pattern. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.StrConsts, tyControls.Controller,
  tyControls.Dialogs, tyControls.Dialogs.FileDialog,
  tyControls.ListBox, tyControls.Button, tyControls.PaintPanel,
  tyControls.ImageCollection;

type
  TTyImageCollectionEditorForm = class(TTyDialog)
  private
    FList: TTyListBox;
    FPreview: TTyPaintPanel;
    FAddBtn, FReplaceBtn, FDeleteBtn, FRenameBtn, FUpBtn, FDownBtn, FClearBtn: TTyButton;
    FWork: TTyImageCollection;    // the working copy; owned via Self
    procedure RefreshList(ASelect: Integer);
    procedure ListChanged(Sender: TObject; AUser: Boolean);
    procedure PreviewPaint(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
    procedure AddClick(Sender: TObject);
    procedure ReplaceClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure RenameClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    function PickFiles(AMulti: Boolean; AFiles: TStrings): Boolean;
  protected
    procedure LayoutContent; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    { Load the source into the working copy (the source itself stays untouched). }
    procedure LoadFrom(ASource: TTyImageCollection);
    { Write the working copy back -- the OK half of the contract. }
    procedure CommitTo(ATarget: TTyImageCollection);

    { Action seams (the buttons call these; tests call them directly). }
    function EntryCount: Integer;
    function EntryCaption(AIndex: Integer): string;   // what the list row shows
    function SelectedIndex: Integer;
    procedure SelectEntry(AIndex: Integer);
    { Add one file as a new master named after the file (sans extension). Any format
      BGRABitmap reads; the payload is stored as PNG. False when the file does not load. }
    function AddFromFile(const AFileName: string): Boolean;
    { Replace the selected master's pixels from a file; the name stays. }
    function ReplaceFromFile(const AFileName: string): Boolean;
    procedure DeleteSelected;
    { Rename the selected master AND every other master sharing its name -- a name is a
      multi-resolution family, and renaming half of one silently breaks the set. }
    procedure RenameSelected(const ANewName: string);
    { Move the selected master up (-1) / down (+1) in authoring order. }
    procedure MoveSelected(ADelta: Integer);
    procedure ClearAll;

    { The working copy, for assertions. }
    property Work: TTyImageCollection read FWork;
  end;

{ Construct-only builder (no ShowModal), loaded from ASource; the test seam. }
function TyBuildImageCollectionEditor(ASource: TTyImageCollection): TTyImageCollectionEditorForm;

{ The one-liner: edit ACollection in place; True (and committed) on OK. }
function TyEditImageCollection(ACollection: TTyImageCollection): Boolean;

implementation

function TyBuildImageCollectionEditor(ASource: TTyImageCollection): TTyImageCollectionEditorForm;
begin
  Result := TTyImageCollectionEditorForm.CreateNew(nil);
  Result.LoadFrom(ASource);
end;

function TyEditImageCollection(ACollection: TTyImageCollection): Boolean;
var
  dlg: TTyImageCollectionEditorForm;
begin
  Result := False;
  if ACollection = nil then Exit;
  dlg := TyBuildImageCollectionEditor(ACollection);
  try
    Result := dlg.ShowModal = mrOK;
    if Result then
      dlg.CommitTo(ACollection);
  finally
    dlg.Free;
  end;
end;

{ ---- construction / layout ---- }

constructor TTyImageCollectionEditorForm.CreateNew(AOwner: TComponent; Num: Integer);

  function MakeButton(const ACaption: string; AHandler: TNotifyEvent): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.OnClick := AHandler;
  end;

begin
  inherited CreateNew(AOwner, Num);
  Caption := rsDlgImgColTitle;
  Resizable := True;
  Constraints.MinWidth := 480;
  Constraints.MinHeight := 340;

  FWork := TTyImageCollection.Create(Self);

  FList := TTyListBox.Create(Self);
  FList.Parent := Self;

  FPreview := TTyPaintPanel.Create(Self);
  FPreview.Parent := Self;

  FAddBtn     := MakeButton(rsDlgImgColAdd, @AddClick);
  FReplaceBtn := MakeButton(rsDlgImgColReplace, @ReplaceClick);
  FDeleteBtn  := MakeButton(rsDlgImgColDelete, @DeleteClick);
  FRenameBtn  := MakeButton(rsDlgImgColRename, @RenameClick);
  FUpBtn      := MakeButton(rsDlgImgColUp, @UpClick);
  FDownBtn    := MakeButton(rsDlgImgColDown, @DownClick);
  FClearBtn   := MakeButton(rsDlgImgColClear, @ClearClick);

  { Handlers only after every child exists, so nothing fires into a half-built form. }
  FList.OnSelectionChange := @ListChanged;
  FPreview.OnPaintSurface := @PreviewPaint;

  AddButton(rsMsgBtnOK, mrOK, True, False);
  AddButton(rsMsgBtnCancel, mrCancel, False, True);
  AutoSizeToContent(620, 400);
  LayoutContent;
end;

procedure TTyImageCollectionEditorForm.LayoutContent;
const
  Gap = 8;
  BtnW = 130;
var
  r: TRect;
  x, y, listW, btnH, i: Integer;
  btns: array[0..6] of TTyButton;
begin
  if FClearBtn = nil then Exit;    { Resize can fire before construction finishes }
  r := ContentRect;
  btnH := TyDensityHeight(nil, TyDlgEditH);
  listW := (r.Right - r.Left) - 2 * TyDlgPad - BtnW - Gap;
  FList.SetBounds(r.Left + TyDlgPad, r.Top + TyDlgPad,
    listW, (r.Bottom - r.Top) - 2 * TyDlgPad);

  x := r.Left + TyDlgPad + listW + Gap;
  y := r.Top + TyDlgPad;
  btns[0] := FAddBtn; btns[1] := FReplaceBtn; btns[2] := FDeleteBtn;
  btns[3] := FRenameBtn; btns[4] := FUpBtn; btns[5] := FDownBtn; btns[6] := FClearBtn;
  for i := 0 to High(btns) do
  begin
    btns[i].SetBounds(x, y, BtnW, btnH);
    Inc(y, btnH + Gap div 2);
  end;

  { The preview takes whatever is left under the button column. }
  Inc(y, Gap);
  FPreview.SetBounds(x, y, BtnW, (r.Bottom - TyDlgPad) - y);
end;

{ ---- model <-> view ---- }

procedure TTyImageCollectionEditorForm.LoadFrom(ASource: TTyImageCollection);
begin
  if ASource <> nil then
    FWork.Images.Assign(ASource.Images)
  else
    FWork.Images.Clear;
  RefreshList(0);
end;

procedure TTyImageCollectionEditorForm.CommitTo(ATarget: TTyImageCollection);
begin
  if ATarget <> nil then
    ATarget.Images.Assign(FWork.Images);
end;

function TTyImageCollectionEditorForm.EntryCount: Integer;
begin
  Result := FWork.Images.Count;
end;

function TTyImageCollectionEditorForm.EntryCaption(AIndex: Integer): string;
var
  it: TTyImageItem;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= FWork.Images.Count) then Exit;
  it := FWork.Images[AIndex];
  if it.IsDecodable then
    Result := Format('%s  (%dx%d)', [it.ImageName, it.Master.Width, it.Master.Height])
  else if it.PngBase64 <> '' then
    Result := Format('%s  (?)', [it.ImageName])    // a mangled payload stays visible
  else
    Result := Format('%s  (-)', [it.ImageName]);
end;

procedure TTyImageCollectionEditorForm.RefreshList(ASelect: Integer);
var
  i: Integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for i := 0 to FWork.Images.Count - 1 do
      FList.Items.Add(EntryCaption(i));
  finally
    FList.Items.EndUpdate;
  end;
  if FWork.Images.Count > 0 then
  begin
    if ASelect < 0 then ASelect := 0;
    if ASelect >= FWork.Images.Count then ASelect := FWork.Images.Count - 1;
    FList.ItemIndex := ASelect;
  end;
  FPreview.Invalidate;
end;

function TTyImageCollectionEditorForm.SelectedIndex: Integer;
begin
  Result := FList.ItemIndex;
end;

procedure TTyImageCollectionEditorForm.SelectEntry(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FList.Items.Count) then
    FList.ItemIndex := AIndex;
end;

procedure TTyImageCollectionEditorForm.ListChanged(Sender: TObject; AUser: Boolean);
begin
  FPreview.Invalidate;
end;

procedure TTyImageCollectionEditorForm.PreviewPaint(Sender: TObject;
  APainter: TTyPainter; const AContent: TRect);
var
  it: TTyImageItem;
  m: TBGRABitmap;
  w, h, dw, dh: Integer;
  dst: TRect;
begin
  if (SelectedIndex < 0) or (SelectedIndex >= FWork.Images.Count) then Exit;
  it := FWork.Images[SelectedIndex];
  m := it.Master;
  if m = nil then Exit;
  { Fit, never magnify: pixel art blown up to the pane reads as broken. Centered. }
  w := AContent.Right - AContent.Left;
  h := AContent.Bottom - AContent.Top;
  if (w <= 0) or (h <= 0) then Exit;
  dw := m.Width;
  dh := m.Height;
  if (dw > w) or (dh > h) then
  begin
    if dw * h > dh * w then
    begin
      dh := (dh * w) div dw;  dw := w;
    end
    else
    begin
      dw := (dw * h) div dh;  dh := h;
    end;
    if dw < 1 then dw := 1;
    if dh < 1 then dh := 1;
  end;
  dst := Rect(0, 0, dw, dh);
  OffsetRect(dst, AContent.Left + (w - dw) div 2, AContent.Top + (h - dh) div 2);
  APainter.Bitmap.StretchPutImage(dst, m, dmDrawWithTransparency);
end;

{ ---- actions ---- }

function TTyImageCollectionEditorForm.AddFromFile(const AFileName: string): Boolean;
var
  bmp: TBGRABitmap;
  it: TTyImageItem;
begin
  Result := False;
  if not FileExists(AFileName) then Exit;
  try
    bmp := TBGRABitmap.Create(AFileName);
  except
    Exit;      { an unreadable picture is a False, not a crash }
  end;
  try
    it := FWork.Images.Add;
    it.ImageName := ChangeFileExt(ExtractFileName(AFileName), '');
    it.SetBitmap(bmp);
  finally
    bmp.Free;
  end;
  RefreshList(FWork.Images.Count - 1);
  Result := True;
end;

function TTyImageCollectionEditorForm.ReplaceFromFile(const AFileName: string): Boolean;
var
  bmp: TBGRABitmap;
  idx: Integer;
begin
  Result := False;
  idx := SelectedIndex;
  if (idx < 0) or (idx >= FWork.Images.Count) or not FileExists(AFileName) then Exit;
  try
    bmp := TBGRABitmap.Create(AFileName);
  except
    Exit;
  end;
  try
    FWork.Images[idx].SetBitmap(bmp);
  finally
    bmp.Free;
  end;
  RefreshList(idx);
  Result := True;
end;

procedure TTyImageCollectionEditorForm.DeleteSelected;
var
  idx: Integer;
begin
  idx := SelectedIndex;
  if (idx < 0) or (idx >= FWork.Images.Count) then Exit;
  FWork.Images.Delete(idx);
  RefreshList(idx);
end;

procedure TTyImageCollectionEditorForm.RenameSelected(const ANewName: string);
var
  idx, i: Integer;
  oldName: string;
begin
  idx := SelectedIndex;
  if (idx < 0) or (idx >= FWork.Images.Count) or (ANewName = '') then Exit;
  oldName := FWork.Images[idx].ImageName;
  if oldName = ANewName then Exit;
  for i := 0 to FWork.Images.Count - 1 do
    if FWork.Images[i].ImageName = oldName then
      FWork.Images[i].ImageName := ANewName;
  RefreshList(idx);
end;

procedure TTyImageCollectionEditorForm.MoveSelected(ADelta: Integer);
var
  idx, dst: Integer;
begin
  idx := SelectedIndex;
  if (idx < 0) or (idx >= FWork.Images.Count) then Exit;
  dst := idx + ADelta;
  if (dst < 0) or (dst >= FWork.Images.Count) then Exit;
  FWork.Images[idx].Index := dst;
  RefreshList(dst);
end;

procedure TTyImageCollectionEditorForm.ClearAll;
begin
  FWork.Images.Clear;
  RefreshList(-1);
end;

{ ---- button handlers (thin UI wrappers over the seams) ---- }

function TTyImageCollectionEditorForm.PickFiles(AMulti: Boolean; AFiles: TStrings): Boolean;
var
  dlg: TTyOpenPictureDialog;
begin
  dlg := TTyOpenPictureDialog.Create(Self);
  try
    if AMulti then dlg.Options := dlg.Options + [fdoAllowMultiSelect];
    Result := dlg.Execute;
    if Result then
    begin
      if AMulti and (dlg.Files.Count > 0) then
        AFiles.Assign(dlg.Files)
      else
        AFiles.Add(dlg.FileName);
    end;
  finally
    dlg.Free;
  end;
end;

procedure TTyImageCollectionEditorForm.AddClick(Sender: TObject);
var
  files: TStringList;
  i: Integer;
begin
  files := TStringList.Create;
  try
    if not PickFiles(True, files) then Exit;
    for i := 0 to files.Count - 1 do
      AddFromFile(files[i]);
  finally
    files.Free;
  end;
end;

procedure TTyImageCollectionEditorForm.ReplaceClick(Sender: TObject);
var
  files: TStringList;
begin
  if SelectedIndex < 0 then Exit;
  files := TStringList.Create;
  try
    if not PickFiles(False, files) then Exit;
    if files.Count > 0 then
      ReplaceFromFile(files[0]);
  finally
    files.Free;
  end;
end;

procedure TTyImageCollectionEditorForm.DeleteClick(Sender: TObject);
begin
  DeleteSelected;
end;

procedure TTyImageCollectionEditorForm.RenameClick(Sender: TObject);
var
  nm: string;
begin
  if (SelectedIndex < 0) or (SelectedIndex >= FWork.Images.Count) then Exit;
  nm := FWork.Images[SelectedIndex].ImageName;
  if TyInputQuery(rsDlgImgColRename, rsDlgImgColRenamePrompt, nm) then
    RenameSelected(nm);
end;

procedure TTyImageCollectionEditorForm.UpClick(Sender: TObject);
begin
  MoveSelected(-1);
end;

procedure TTyImageCollectionEditorForm.DownClick(Sender: TObject);
begin
  MoveSelected(1);
end;

procedure TTyImageCollectionEditorForm.ClearClick(Sender: TObject);
begin
  ClearAll;
end;

end.
