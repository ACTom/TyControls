# TTyFormChrome —— 已移除（被 TTyForm 取代）

> **本控件已不复存在。** 旧的窗框控制器 `TTyFormChrome`（一个挂在普通 `TForm` 上、把它改造为自绘无边框窗口的非可视 `TComponent`）已被**移除**。自绘窗框现在的**唯一**入口是窗体基类 **`TTyForm`**。
>
> **新文档见 [ttyform.md](ttyform.md)。**

## 为什么取代

控制器方案需要在运行期把宿主窗体改成无边框、注入标题栏，并把既有控件重新归位到一个运行期才创建的内容区——这条路径脆弱，且会出现"覆盖 bug"（标题栏画到既有控件之上，因为它们保留了设计期的 `Top`）。`TTyForm = class(TForm)` 从**构造上**解决了这些问题：它出生即无边框，代码创建标题栏（`alTop`）与内容面板（`alClient`），应用控件放在内容面板里，原点已在标题栏下方——设计期与运行期都不会被覆盖，且布局是设计器 WYSIWYG 的。

## 迁移指引

| 旧（`TTyFormChrome`，已移除） | 新（`TTyForm`） |
|------|------|
| `TForm1 = class(TForm)` + 一个 `Chrome: TTyFormChrome` 字段 | `TForm1 = class(TTyForm)`（直接继承）|
| `Chrome.Active := True` 激活窗框 | 无需"激活"——继承 `TTyForm` 即是自绘窗框 |
| `Chrome.TitleBar` | `TitleBar`（窗体的只读属性）|
| `Chrome.TitleHeight` | `TitleHeight`（published）|
| `Chrome.ShowMinimize` / `ShowMaximize` | `ShowMinimize` / `ShowMaximize`（published）|
| `Chrome.BorderZone` | **已移除**——缩放感应边框是固定的 6px 内部环 |
| `Chrome.ToggleMaximize` | 引擎内部处理（最大化按钮 / 双击标题栏），无需直接调用 |
| `Chrome.OnMinimize/OnMaximize/OnRestore` | **已废弃**——改用标准 `TForm` 生命周期（最大化由引擎处理，最小化即 `WindowState`）|
| `Chrome.OnCloseQuery` / `OnClose` | 直接用窗体自带的标准 `OnCloseQuery` / `OnClose` |
| `TTyTitleBar` 在调色板上单独拖放 | 标题栏是 `TTyForm` 的子组件，**不再**单独出现在调色板 |
| 设置窗体背景色 | `ApplyChromeTheme(AController)`（背景取自 `TyForm` 主题令牌）|

迁移示例：

```pascal
// 旧（已不可用）：
// type TMainForm = class(TForm)
//   private Chrome: TTyFormChrome;
// procedure TMainForm.FormCreate(Sender: TObject);
// begin
//   Chrome := TTyFormChrome.Create(Self);
//   Chrome.Active := True;
// end;

// 新：
type
  TMainForm = class(TTyForm)   // 直接继承
    // 应用控件拖到内容面板（ContentPanel）上
  end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(StyleCtrl);       // 背景取自 TyForm 主题令牌
  TitleBar.Caption := Caption;       // 同步标题
  // ShowMinimize / ShowMaximize / TitleHeight 可在对象查看器或此处设置
end;
```

需要**原生**窗口（系统标题栏与边框）时，继续继承普通 `TForm`——这是原生路径，无需任何 TyControls 处理。

## 相关文档

- [ttyform.md](ttyform.md) —— 新的自绘窗框窗口完整文档。
- [titlebar.md](titlebar.md) —— `TTyTitleBar`（现为 `TTyForm` 子组件）。
- [captionbutton.md](captionbutton.md) —— `TTyCaptionButton` 标题栏系统按钮。
