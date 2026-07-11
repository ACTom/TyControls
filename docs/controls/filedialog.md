# 文件对话框 —— TTyOpenDialog / TTySaveDialog / TTyOpenPictureDialog / TTySavePictureDialog

## 概述

主题化的自绘文件对话框。四个变体由**一个** `TTyFileDialogForm`(`TTyDialog` 子类)靠两个标志
(`SaveMode` / `PreviewMode`)拼出:把已建的 shell 控件 —— 目录树([TTyShellTreeView](shelltreeview.md))
+ 文件列表([TTyShellListView](shelllistview.md))+ 查找范围([TTyShellComboBox](shellcombobox.md))
+ 类型过滤([TTyFilterComboBox](filtercombobox.md))—— 加文件名框 + 确定/取消组装进对话框。图片变体右侧
多一个 [TTyImage](image.md) 预览窗格。**零新增主题 token**。

三层 API 对齐 LCL 的 `TOpenDialog`/`TSaveDialog`/`TOpenPictureDialog`/`TSavePictureDialog`。

## 用法

**全局函数(最省事)**:
```pascal
uses tyControls.Dialogs.FileDialog;

var fn: string;
begin
  fn := 'C:\Users\Tom\notes.txt';
  if TyOpenDialog(fn, '文本 (*.txt)|*.txt|所有文件 (*.*)|*.*') then
    OpenFile(fn);                         // fn = 选中的文件

  if TySaveDialog(fn, '文本 (*.txt)|*.txt', 'txt') then
    SaveFile(fn);                         // fn 已补默认扩展名、已过覆盖确认

  if TyOpenPictureDialog(fn) then         // 默认图片过滤器 + 右侧预览
    LoadImage(fn);
end;
```

**可流式组件(拖到窗体上)**:
```pascal
Dlg := TTyOpenDialog.Create(Self);
Dlg.Title := '选择文档';
Dlg.Filter := '文本 (*.txt)|*.txt|所有文件 (*.*)|*.*';
Dlg.InitialDir := 'C:\Users\Tom';
Dlg.Options := [fdoFileMustExist, fdoAllowMultiSelect];
if Dlg.Execute then
  for s in Dlg.Files do ...;             // 多选结果;单选时 Dlg.FileName
```

## 属性 / 方法(组件)

| 成员 | 说明 |
|---|---|
| `Execute: Boolean` | 弹模态;确定返回 True。 |
| `FileName: string` | 输入=预填名;输出=选中/解析后的结果。 |
| `Files: TStrings` | 只读;Open 多选的全部结果(单选时含一项)。 |
| `Filter` / `FilterIndex` | LCL 过滤串 / 生效段(1-based)。为空时回落到变体默认过滤器。 |
| `InitialDir: string` | 起始目录。 |
| `DefaultExt: string` | Save:文件名无扩展名时补它。 |
| `Options: TTyFileDialogOptions` | `fdoOverwritePrompt`(Save 覆盖确认)/ `fdoFileMustExist`(Open 必须存在)/ `fdoPathMustExist` / `fdoAllowMultiSelect`。 |
| `Title: string` | 标题栏文字。 |
| `OnShow`/`OnClose`/`OnCanClose` | 转发给内部表单。 |

四个组件类:`TTyOpenDialog`(F/F)、`TTySaveDialog`(T/F)、`TTyOpenPictureDialog`(F/T)、
`TTySavePictureDialog`(T/T),只覆写 `SaveMode`/`PreviewMode`/默认过滤器。

## 关键设计

- **一个 form 两个标志 = 四变体**;`FBtnNewFolder` 仅 SaveMode 建,`FPreview` 仅 PreviewMode 建(标志 setter 懒建)。
- **四方联动**(树↔列表↔查找范围)靠一个 `FSyncing` 防回环;查找范围字段是纯显示同步(写 `Directory` 不触发事件)。
  过滤下拉 `OnFilterChange` → `List.Mask`。选中文件 → 填文件名框;双击文件(Open)→ 直接接受。
- **OK 在 `CloseQuery` 里校验**(不是按钮 OnClick):Save 走 `TyFsResolveSaveName` 解析 + `TyMessageDlg` 覆盖确认;
  Open 收集选中集 + `fdoFileMustExist` 校验;不通过返回 False 把对话框留住。
- **Open 手敲优先**:文件名框非空时以它为准(带路径原样、裸名对当前目录展开),空框才回落到列表选中项。
- **Save 存名解析**(`TyFileDialogResolveName` → `TyFsResolveSaveName`):裸名对当前目录展开,无扩展名补 `DefaultExt`,已有扩展名不动。
- **图片预览**:选中图片时 `TTyImage.Picture.LoadFromFile`(`try/except`,读不了清空),`Proportional+Center` 缩放适配;
  跨平台(PNG/JPG/BMP/GIF)。

## 通用预览对话框

`TTyOpenPreviewDialog` / `TTySavePreviewDialog` —— 右侧预览框默认支持**图片 + 文本**,并可经
`OnPreview` 事件自定义:

```pascal
Dlg := TTyOpenPreviewDialog.Create(Self);
Dlg.OnPreview := @MyPreview;
Dlg.Execute;

procedure TForm1.MyPreview(Sender: TObject; const AFileName: string;
  APreview: TTyPreviewBox; var AHandled: Boolean);
begin
  if ExtractFileExt(AFileName) = '.myfmt' then
  begin
    APreview.ShowImage(DecodeMyFormat(AFileName));   // 交出位图
    AHandled := True;                                // 跳过内建分派
  end;
  // 不 handled → 内建:图片→文本→"无法预览"
end;
```

预览框是可复用的 [TTyPreviewBox](previewbox.md);**图片变体也用同一个 box**(`AllowText=False`,图片-only),
全库一套预览机制。自定义 = 交出 bitmap/text(`APreview.ShowImage`/`ShowText`/`ShowMessage`),低层
`APreview.OnPaintPreview` 兜底。

六个组件:普通 `TTyOpenDialog`/`TTySaveDialog`、图片 `TTyOpenPictureDialog`/`TTySavePictureDialog`
(对齐 LCL)、通用预览 `TTyOpenPreviewDialog`/`TTySavePreviewDialog`(加值)。

## 待办 / 后续

- 真机眼验(六变体组装/联动/Save 覆盖流/图片+文本预览/自定义 `OnPreview`);i18n 集中化到
  `tyControls.StrConsts`(合并回 main 时统一做)。
