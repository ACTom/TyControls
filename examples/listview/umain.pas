unit umain;

{ TTyListView 示例。

  左边是集合模式:30 行文件清单,四列,可切五种视图、点表头排序、Ctrl/Shift 多选、框选、
  敲字母定位。数据里故意混了几个「文件夹」——它们没有大小、没有修改时间,用来演示
  「不可解析的单元格永远排最后,与升降序无关」:按大小降序时,顶上应该是最大的文件,
  而不是一堆空白。

  右边是虚拟模式:ItemCount = 100000,一个行对象都不建。文本在 OnGetItemText 里按需生成,
  排序也只是置换内部的显示顺序。切换、滚动、排序都应该是瞬时的。

  两边都会随主题变色——本控件不引入任何新的主题 token,外框/行/表头分别复用
  TyTreeView / TyTreeNode / TyTreeHeader。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Forms, Controls, Math,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Form, tyControls.TyLabel, tyControls.Divider,
  tyControls.Button, tyControls.CheckBox, tyControls.Columns,
  tyControls.ImageCollection, tyControls.ListView.Layout, tyControls.ListView;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;

    DivLeft: TTyDivider;
    BtnReport: TTyButton;
    BtnList: TTyButton;
    BtnIcon: TTyButton;
    BtnSmallIcon: TTyButton;
    BtnTile: TTyButton;
    ChkGrid: TTyCheckBox;
    ChkMulti: TTyCheckBox;
    ChkBoxes: TTyCheckBox;
    LV1: TTyListView;
    LblStatus: TTyLabel;
    LblHint: TTyLabel;

    DivRight: TTyDivider;
    BtnSortVirtual: TTyButton;
    BtnJumpEnd: TTyButton;
    LV2: TTyListView;
    LblVirtual: TTyLabel;
    LblVirtualNote: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure BtnReportClick(Sender: TObject);
    procedure BtnListClick(Sender: TObject);
    procedure BtnIconClick(Sender: TObject);
    procedure BtnSmallIconClick(Sender: TObject);
    procedure BtnTileClick(Sender: TObject);
    procedure ChkGridChange(Sender: TObject);
    procedure ChkMultiChange(Sender: TObject);
    procedure ChkBoxesChange(Sender: TObject);
    procedure LV1SelectItem(Sender: TObject; AIndex: Integer);
    procedure LV1Change(Sender: TObject);
    procedure LV1ColumnClick(Sender: TObject; AColumn: Integer);
    procedure LV1ItemActivate(Sender: TObject; AIndex: Integer);
    procedure LV2GetItemText(Sender: TObject; AIndex, AColumn: Integer; var AText: string);
    procedure LV2SelectItem(Sender: TObject; AIndex: Integer);
    procedure LV2GetItemState(Sender: TObject; AIndex: Integer;
      var AStates: TTyListItemStates);
    procedure LV2ItemChecked(Sender: TObject; AIndex: Integer);
    procedure LV1ItemChecked(Sender: TObject; AIndex: Integer);
    procedure LV1Edited(Sender: TObject; AIndex: Integer; var AText: string);
    procedure BtnSortVirtualClick(Sender: TObject);
    procedure BtnJumpEndClick(Sender: TObject);
  private
    FIcons: TTyImageCollection;
    FImages: TTyVirtualImageList;
    { The virtual list's check state lives HERE, not in the control. OwnerData means the
      control caches nothing: it asks OnGetItemState and tells us to flip via OnItemChecked.
      Forget to flip it and the box looks stuck. }
    FVChecked: array of Boolean;
    procedure BuildIcons;
    procedure BuildColumns;
    procedure BuildRows;
    procedure BuildVirtual;
    procedure UpdateStatus;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

{ ---------------------------------------------------------------------------
  Setup
  --------------------------------------------------------------------------- }

{ Glyphs drawn with BGRA, so the example needs no asset files.

  MASTER SIZE MATTERS. TTyImageCollection keeps ONE master per name and resamples it to
  whatever size the view asks for. The large-icon view wants 48 logical px -- 96 at 200%
  DPI -- so a 32px master gets UPSAMPLED and looks soft. Drawing the masters at 128px means
  every size the control asks for is a DOWNSAMPLE, which rmFineResample does crisply.

  AddBitmap copies, so the caller frees. }
procedure TMainForm.BuildIcons;
const
  G = 128;   { master edge, in px }

  { A slightly darker shade of the body colour, for the folder tab and the page fold. }
  function Shade(const C: TBGRAPixel; AFactor: Single): TBGRAPixel;
  begin
    Result := BGRA(Round(C.red * AFactor), Round(C.green * AFactor),
                   Round(C.blue * AFactor), C.alpha);
  end;

  procedure AddFolder(const AName: string; ABody: TBGRAPixel);
  var
    bmp: TBGRABitmap;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      { tab, then body over it }
      bmp.FillRoundRectAntialias(8, 20, 60, 46, 6, 6, Shade(ABody, 0.82));
      bmp.FillRoundRectAntialias(8, 34, 120, 112, 8, 8, ABody);
      { a lighter lip along the top of the body }
      bmp.FillRectAntialias(8, 34, 120, 42, BGRA(255, 255, 255, 40));
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

  { A page with a folded top-right corner, plus per-kind content. }
  procedure AddPage(const AName: string; ABody: TBGRAPixel; AKind: Integer);
  const
    L = 22; T = 8; R = 106; B = 120; Fold = 26;
  var
    bmp: TBGRABitmap;
    i, y: Integer;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      { page body, with the folded corner cut out }
      bmp.FillPolyAntialias([PointF(L, T), PointF(R - Fold, T), PointF(R, T + Fold),
                             PointF(R, B), PointF(L, B)], ABody);
      { the fold itself }
      bmp.FillPolyAntialias([PointF(R - Fold, T), PointF(R, T + Fold),
                             PointF(R - Fold, T + Fold)], Shade(ABody, 0.72));
      case AKind of
        0:  { document: text lines }
          for i := 0 to 3 do
          begin
            y := 52 + i * 14;
            bmp.FillRectAntialias(36, y, 92 - i * 14, y + 6,
              BGRA(255, 255, 255, 200 - i * 30));
          end;
        1:  { sheet: a small grid }
          begin
            bmp.FillRectAntialias(36, 50, 92, 100, BGRA(255, 255, 255, 60));
            for i := 0 to 2 do
              bmp.FillRectAntialias(36, 50 + i * 17, 92, 52 + i * 17, BGRA(255, 255, 255, 190));
            for i := 0 to 2 do
              bmp.FillRectAntialias(36 + i * 19, 50, 38 + i * 19, 100, BGRA(255, 255, 255, 190));
          end;
      else  { image: a sun over a mountain }
        begin
          bmp.FillEllipseAntialias(50, 60, 9, 9, BGRA(255, 255, 255, 220));
          bmp.FillPolyAntialias([PointF(34, 104), PointF(60, 70), PointF(86, 104)],
            BGRA(255, 255, 255, 190));
          bmp.FillPolyAntialias([PointF(60, 104), PointF(78, 82), PointF(96, 104)],
            BGRA(255, 255, 255, 140));
        end;
      end;
      FIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

begin
  FIcons := TTyImageCollection.Create(Self);
  AddFolder('folder',   BGRA(226, 176, 66));      // 0
  AddPage('document', BGRA(72, 128, 200), 0);     // 1
  AddPage('sheet',    BGRA(72, 160, 100), 1);     // 2
  AddPage('image',    BGRA(190, 96, 176), 2);     // 3

  FImages := TTyVirtualImageList.Create(Self);
  FImages.Collection := FIcons;
  FImages.Names.Text := 'folder' + LineEnding + 'document' + LineEnding +
                        'sheet' + LineEnding + 'image';

  { One list serves both: RenderIndex scales to whatever the view style asks for. }
  LV1.LargeImages := FImages;
  LV1.SmallImages := FImages;
end;

procedure TMainForm.BuildColumns;
var
  c: TTyColumn;
begin
  { Columns are code-created, like examples/treeview: a TCollection streams as anonymous
    `item ... end` blocks, so hand-writing them into the .lfm buys nothing. }
  c := LV1.Header.Columns.Add as TTyColumn;
  c.Text := '名称';  c.Width := 260;
  c := LV1.Header.Columns.Add as TTyColumn;
  c.Text := '大小';  c.Width := 110;  c.Alignment := taRightJustify;
  c := LV1.Header.Columns.Add as TTyColumn;
  c.Text := '类型';  c.Width := 120;
  c := LV1.Header.Columns.Add as TTyColumn;
  c.Text := '修改时间'; c.Width := 180;

  LV1.Header.Options := LV1.Header.Options + [hoVisible, hoColumnResize,
    hoShowSortGlyphs, hoHeaderClickAutoSort, hoHotTrack];

  c := LV2.Header.Columns.Add as TTyColumn;
  c.Text := '行号';  c.Width := 120;  c.Alignment := taRightJustify;
  c := LV2.Header.Columns.Add as TTyColumn;
  c.Text := '值';    c.Width := 300;
  LV2.Header.Options := LV2.Header.Options + [hoVisible, hoColumnResize, hoShowSortGlyphs];
end;

procedure TMainForm.BuildRows;

  procedure AddFile(const AName, ASize, AKind, AWhen: string; AImage: Integer);
  begin
    with LV1.Items.Add do
    begin
      Caption := AName;
      SubItems.Add(ASize);
      SubItems.Add(AKind);
      SubItems.Add(AWhen);
      ImageIndex := AImage;
    end;
  end;

  { A folder has no size and no timestamp. Under lskNumber / lskDateTime those cells do
    not parse, and an unparseable cell sorts LAST in BOTH directions -- that is the point
    of the hint label under the list. }
  procedure AddFolder(const AName: string);
  begin
    with LV1.Items.Add do
    begin
      Caption := AName;
      SubItems.Add('');
      SubItems.Add('文件夹');
      SubItems.Add('');
      ImageIndex := 0;
    end;
  end;

const
  Kinds: array[0..2] of string = ('文本文档', '电子表格', '图像');
var
  i: Integer;
begin
  AddFolder('assets');
  AddFolder('build');
  AddFolder('docs');

  AddFile('README.md',        '4096',    '文本文档', '2026-07-10 08:30', 1);
  AddFile('CHANGELOG.md',     '18944',   '文本文档', '2026-07-09 17:02', 1);
  AddFile('budget-2026.xlsx', '284672',  '电子表格', '2026-06-28 11:45', 2);
  AddFile('logo.png',         '90112',   '图像',     '2026-05-14 09:12', 3);
  AddFile('screenshot.png',   '1638400', '图像',     '2026-07-08 21:37', 3);
  AddFile('notes.txt',        '512',     '文本文档', '2026-07-01 07:05', 1);

  for i := 1 to 21 do
    AddFile(Format('sample-%.2d.%s', [i, Copy('txtxlspng', 1 + (i mod 3) * 3, 3)]),
            IntToStr(1024 * (i * i + 7)),
            Kinds[i mod 3],
            Format('2026-%.2d-%.2d %.2d:%.2d', [1 + (i mod 12), 1 + (i mod 27),
                                                (i * 3) mod 24, (i * 7) mod 60]),
            1 + (i mod 3));
end;

procedure TMainForm.BuildVirtual;
begin
  { 100,000 rows, zero row objects. The only allocation is our own check-state array. }
  LV2.OwnerData := True;
  LV2.ItemCount := 100000;
  LV2.SortKind := lskText;
  LV2.Checkboxes := True;
  SetLength(FVChecked, LV2.ItemCount);
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  LV1.ReadOnly := False;        { F2 renames; the default is read-only on purpose }
  LV1.OnItemChecked := @LV1ItemChecked;
  LV1.OnEdited := @LV1Edited;
  LV2.OnGetItemState := @LV2GetItemState;
  LV2.OnItemChecked := @LV2ItemChecked;

  BuildIcons;
  BuildColumns;
  BuildRows;
  BuildVirtual;
  UpdateStatus;

  ApplyChromeTheme(TyDefaultController);
end;

{ ---------------------------------------------------------------------------
  Left list — view styles, options, sorting, status
  --------------------------------------------------------------------------- }

procedure TMainForm.BtnReportClick(Sender: TObject);    begin LV1.ViewStyle := lvsReport;    end;
procedure TMainForm.BtnListClick(Sender: TObject);      begin LV1.ViewStyle := lvsList;      end;
procedure TMainForm.BtnIconClick(Sender: TObject);      begin LV1.ViewStyle := lvsIcon;      end;
procedure TMainForm.BtnSmallIconClick(Sender: TObject); begin LV1.ViewStyle := lvsSmallIcon; end;
procedure TMainForm.BtnTileClick(Sender: TObject);      begin LV1.ViewStyle := lvsTile;      end;

procedure TMainForm.ChkGridChange(Sender: TObject);
begin
  LV1.GridLines := ChkGrid.Checked;
end;

procedure TMainForm.ChkMultiChange(Sender: TObject);
begin
  LV1.MultiSelect := ChkMulti.Checked;
  UpdateStatus;
end;

procedure TMainForm.ChkBoxesChange(Sender: TObject);
begin
  LV1.Checkboxes := ChkBoxes.Checked;
end;

procedure TMainForm.LV1ItemChecked(Sender: TObject; AIndex: Integer);
begin
  { Collection mode: the control already wrote Items[AIndex].States for us. }
  UpdateStatus;
end;

procedure TMainForm.LV1Edited(Sender: TObject; AIndex: Integer; var AText: string);
begin
  { AIndex is an ITEM index and stays valid across a re-sort. Returning AText unchanged
    lets the control write it into Items[AIndex].Caption. Blank it to abandon. }
  LblStatus.Caption := Format('重命名 item index %d → %s', [AIndex, AText]);
end;

procedure TMainForm.LV1ColumnClick(Sender: TObject; AColumn: Integer);
begin
  { AutoSort已经用旧的 SortKind 排过一次了;这里按列挑对比较器再排一次。
    大小是数字,修改时间是 ISO 日期,其余按文本。 }
  case AColumn of
    1: LV1.SortKind := lskNumber;
    3: LV1.SortKind := lskDateTime;
  else
    LV1.SortKind := lskText;
  end;
  LV1.Sort;
end;

procedure TMainForm.LV1SelectItem(Sender: TObject; AIndex: Integer);
begin
  UpdateStatus;
end;

procedure TMainForm.LV1Change(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.LV1ItemActivate(Sender: TObject; AIndex: Integer);
begin
  { AIndex is an ITEM index and stays valid across a re-sort. }
  LblStatus.Caption := Format('双击打开:%s(item index = %d)',
    [LV1.Items[AIndex].Caption, AIndex]);
end;

procedure TMainForm.UpdateStatus;
var
  focus: string;
begin
  if (LV1.ItemIndex >= 0) and (LV1.ItemIndex < LV1.Items.Count) then
    focus := Format('%s(item index = %d)', [LV1.Items[LV1.ItemIndex].Caption, LV1.ItemIndex])
  else
    focus := '无';
  LblStatus.Caption := Format('焦点:%s   已选中:%d 项   排序:第 %d 列',
    [focus, LV1.SelCount, LV1.SortColumn]);
end;

{ ---------------------------------------------------------------------------
  Right list — 100,000 rows, owner data
  --------------------------------------------------------------------------- }

procedure TMainForm.LV2GetItemText(Sender: TObject; AIndex, AColumn: Integer;
  var AText: string);
begin
  { Called only for the rows actually on screen. AIndex is a stable item index, so a
    sort cannot make this return the wrong row's text. }
  case AColumn of
    0: AText := IntToStr(AIndex);
    1: AText := Format('第 %d 行 · 值 %.6d', [AIndex, (AIndex * 7919) mod 1000000]);
  end;
end;

procedure TMainForm.LV2SelectItem(Sender: TObject; AIndex: Integer);
begin
  if AIndex >= 0 then
    LblVirtual.Caption := Format('ItemCount = %d,行对象 = 0   ·   焦点 item index = %d',
      [LV2.ItemCount, AIndex]);
end;

{ OwnerData: the control asks us for every row's state, and never remembers the answer. }
procedure TMainForm.LV2GetItemState(Sender: TObject; AIndex: Integer;
  var AStates: TTyListItemStates);
begin
  if (AIndex >= 0) and (AIndex < Length(FVChecked)) and FVChecked[AIndex] then
    Include(AStates, lisChecked);
end;

{ ...so the flip has to happen HERE. Skip this and the checkbox never appears to toggle:
  the control computes `not Checked[i]`, and Checked[i] is whatever LV2GetItemState says. }
procedure TMainForm.LV2ItemChecked(Sender: TObject; AIndex: Integer);
var
  i, n: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FVChecked)) then Exit;
  FVChecked[AIndex] := not FVChecked[AIndex];
  n := 0;
  for i := 0 to High(FVChecked) do
    if FVChecked[i] then Inc(n);
  LblVirtual.Caption := Format('ItemCount = %d,行对象 = 0   ·   已勾选 %d 项',
    [LV2.ItemCount, n]);
end;

procedure TMainForm.BtnSortVirtualClick(Sender: TObject);
begin
  { Sorting 100k virtual rows permutes an Integer array. Nothing is allocated per row. }
  LV2.SortColumn := 1;
  if LV2.SortDirection = sdAscending then
    LV2.SortDirection := sdDescending
  else
    LV2.SortDirection := sdAscending;
  LV2.Sort;
end;

procedure TMainForm.BtnJumpEndClick(Sender: TObject);
begin
  LV2.ItemIndex := LV2.ItemCount - 1;   { focus-selects, and scrolls it into view }
  LV2.ScrollIntoView(LV2.ItemIndex);
  LV2.SetFocus;
end;

end.
