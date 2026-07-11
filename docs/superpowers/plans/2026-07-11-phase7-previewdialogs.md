# Phase 7 批次 5b —— 通用预览层(`TTyPreviewBox` + 预览对话框)实施计划

> 用户加项(已批准 2026-07-11):`TTyOpenPreviewDialog`/`TTySavePreviewDialog`,右侧预览框默认支持
> 文本/图片,并可经 `OnPreview` 事件让用户自定义渲染(不认识的格式自己来)。自定义 = **交出 bitmap/text**,
> 低层 `OnPaintPreview` 兜底(用户选定的粒度)。**图片对话框改用同一个 `TTyPreviewBox`**(图片-only),全库一套预览。
> 前置:批 5 地基(`112e06e`)已建好 `TTyFileDialogForm`,预览目前是裸 `TTyImage`(`FPreview`)。

## 交付物

| # | 产物 |
|---|---|
| 1 | `source/tyControls.PreviewBox.pas` —— `TTyPreviewBox`(可复用预览控件)+ 纯分类函数 `TyPreviewClassify` |
| 2 | 改 `source/tyControls.Dialogs.FileDialog.pas` —— `FPreview` 由 `TTyImage` 换成 `TTyPreviewBox`;加 `OnPreview` 事件 + `PreviewAllowsText`;新增 `TTyOpenPreviewDialog`/`TTySavePreviewDialog` 组件 + builder/全局 |
| 3 | `tests/test.previewbox.pas` —— 无头,只测纯分类函数(控件窗口化建不了) |
| 4 | 集成:`tycontrols.lpk`、`tytests.lpr`、`Design.pas`(`TTyPreviewBox` 进 **Containers**;两个预览对话框进 **Dialogs**)、调色板图标 ×3(138→141) |
| 5 | `docs/controls/previewbox.md` + 更新 `filedialog.md` + README;`examples/filedialog`(覆盖全 6 变体 + 自定义 `OnPreview`) |

**零新增主题 token**;`themes/*`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、批 1–4 shell 单元、
`tyControls.Dialogs.pas` 基类**零改动**。

## `TTyPreviewBox`

`TTyPreviewBox = class(TTyCustomControl)` —— 一个窗口化容器,内部按内容切换子控件:
- `FImage: TTyImage`(`Proportional:=True; Center:=True`)—— 图片
- `FMemo: TTyMemo`(只读、可滚动)—— 文本
- 都不显示时,`Paint` 居中画占位消息(主题文字色)。

**状态**:`FImage`/`FMemo`(都 `Create(Self)`,`Align:=alClient`,同时最多一个 `Visible`)、`FMessage: string`(占位)、
`FAllowText: Boolean`(默认 True;图片对话框设 False → `PreviewFile` 不试文本)、`FCustom: Boolean`(自定义画模式)、
`FOnPaintPreview`(低层兜底钩子)。

**公开 API**:
```pascal
public
  function  ShowImageFile(const APath: string): Boolean;   { 内建加载图片;成功显示 FImage,失败 False }
  function  ShowTextFile(const APath: string): Boolean;    { 读前 N KB 进 FMemo;显示 FMemo }
  procedure ShowImage(ABitmap: TBGRABitmap);               { 用户交出的位图 -> FImage }
  procedure ShowText(const AText: string);                 { 用户交出的文本 -> FMemo }
  procedure ShowMessage(const AMsg: string);               { 隐藏子控件,居中画 AMsg(如 "无法预览") }
  procedure ShowCustom;                                    { 隐藏子控件,进自定义画模式 -> Paint 调 OnPaintPreview }
  procedure Clear;                                         { 隐藏一切,空白 }
  procedure PreviewFile(const APath: string);              { 内建分派:图片->ShowImageFile;(AllowText)文本->ShowTextFile;否则 ShowMessage }
published
  property AllowText: Boolean read FAllowText write FAllowText default True;
  property OnPaintPreview: TTyPaintSurfaceEvent read FOnPaintPreview write FOnPaintPreview;  { 低层兜底,同 TTyPaintPanel.OnPaintSurface }
```

- `PreviewFile(path)`:`case TyPreviewClassify(path) of pkImage: ShowImageFile; pkText: if FAllowText then ShowTextFile else ShowMessage(无法预览); else ShowMessage(无法预览)`;
  `ShowImageFile`/`ShowTextFile` 失败也回落 `ShowMessage`。
- `ShowImage(bmp)`:经 `TBitmap` 桥接进 `FImage.Picture`(BGRA 3.2.2 无 `Create(TGraphic)`,同 TTyImage 内部做法),显示 FImage。
- **主题**:占位文字用 `ActiveController` 解析的样式(nil 安全回落 `TyDefaultController`);`GetStyleTypeKey` 复用 `'TyPanel'`(**不新增 token**)。
- **图标豁免**:无(本控件不画内容图标)。

**纯分类函数(唯一可无头测)**:
```pascal
type TTyPreviewKind = (pkImage, pkText, pkOther);
function TyPreviewClassify(const AFileName: string): TTyPreviewKind;
```
- `pkImage`:扩展名 ∈ `.png .jpg .jpeg .bmp .gif .ico .tif .tiff`(大小写无关)。
- `pkText`:∈ `.txt .md .json .log .ini .xml .csv .yml .yaml .html .htm .js .css .pas .lpr .inc .pp .lfm .sh .bat`。
- 其余 `pkOther`。空名 / 无扩展名 → `pkOther`。

## 改 `TTyFileDialogForm`

- `FPreview: TTyImage` → `FPreview: TTyPreviewBox`(`SetPreviewMode` 里建 `TTyPreviewBox`,`Align`/`SetBounds` 不变)。
- 加字段 `FPreviewAllowsText: Boolean` + `FOnPreview`;新增公开 `property PreviewAllowsText` + `property OnPreview`。
- `RefreshPreview` 重写:
  ```pascal
  if (not FPreviewMode) or (FPreview = nil) then Exit;
  FPreview.AllowText := FPreviewAllowsText;
  path := FList.SelectedFile;
  handled := False;
  if Assigned(FOnPreview) then FOnPreview(Self, path, FPreview, handled);
  if not handled then
    if (path = '') or DirectoryExistsUTF8(path) then FPreview.Clear
    else FPreview.PreviewFile(path);
  ```
- 事件类型(接口区):
  ```pascal
  TTyFileDialogPreviewEvent = procedure(Sender: TObject; const AFileName: string;
    APreview: TTyPreviewBox; var AHandled: Boolean) of object;
  ```

## 组件 / builder / 全局

- 图片变体(已存在)保持:`PreviewMode=T`;**新增覆写 `PreviewAllowsText=False`**(图片-only),仍用 `TTyPreviewBox`。
- 新增基类虚函数 `PreviewAllowsText: Boolean; virtual`(默认 False)+ `TTyCustomFileDialog` 暴露 `OnPreview`(转发给 form)。
- 新组件:
  ```pascal
  TTyOpenPreviewDialog = class(TTyOpenDialog);   { PreviewMode=T, PreviewAllowsText=T, 常用格式默认过滤器 }
  TTySavePreviewDialog = class(TTySaveDialog);    { 同上 }
  ```
  覆写 `PreviewMode=True` + `PreviewAllowsText=True` + `DefaultFilter`(常用:图片+文本+所有文件)。
- `Execute` 里 seed:`d.PreviewAllowsText := PreviewAllowsText; d.OnPreview := FOnPreview`。
- builder `TyBuildFileDialog` 增参 `APreviewAllowsText: Boolean`(或建后设属性)。
- 全局:`TyOpenPreviewDialog(var AFileName: string): Boolean; TySavePreviewDialog(var AFileName, ADefaultExt: string): Boolean;`

## 无头测试

- `test.previewbox.pas`:`TyPreviewClassify` 的分类矩阵(每个图片扩展名 → pkImage、文本扩展名 → pkText、`.exe`/`.zip`/无扩展名/空 → pkOther;大小写无关 `.PNG`=pkImage)。
- **不建控件 / 不建 form**(窗口化撞 win32 基线)。box 的子控件切换、图片/文本加载、`OnPreview` 流程、自定义画 → **真机眼验**。

## 对抗式审查清单(第三个 agent)

1. **生命周期**:`FImage`/`FMemo` 都 `Create(Self)`(box 释放);box 本身 `Create(Self)`(form 释放);`ShowImage` 的 `TBitmap` 桥接临时对象释放;`FList.SelectedFile` 清空/切换不悬空。
2. **OnPreview 流程**:`AHandled` 语义(用户置 True → 不跑内建);未 handled 且路径为目录/空 → `Clear`;`PreviewFile` 每条分支都收尾到某个可见状态(不留半初始化)。
3. **图片统一**:四个已存在的图片/普通对话框行为不回归(`FPreview` 换类型后 SetBounds/Visible/懒建照旧);`PreviewAllowsText` 默认 False 让图片变体只显示图片。
4. **AllowText**:图片对话框 `PreviewFile` 对 `.txt` → `ShowMessage`(不显示文本);预览对话框 → `ShowTextFile`。
5. **主题**:占位文字与 Memo/Image 都走 ActiveController;`GetStyleTypeKey='TyPanel'`,无新 token。
6. `TyPreviewClassify` 实现与测试/契约一致;受保护文件零改;shell 单元 / Dialogs 基类零改。

## 验收

- 全量测试 0 失败(基线 2813 + 新增分类测试)。
- 零新 token;受保护文件零改;调色板漂移守卫过(141 类)。
- `examples/filedialog` 双击可跑,六个变体 + 一个自定义 `OnPreview`(例:把一个 `.md` 用 ShowText、或某假格式用 ShowMessage/ShowImage)真机眼验。
- 过 [[pre-merge-checklist]](i18n / README 中英)——同批 5,i18n 集中化留到合并回 main。
