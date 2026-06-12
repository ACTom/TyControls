# TTyStyleController — API 参考

## 1. 概述

`TTyStyleController` 是 TyControls 的主题/样式管理组件。它持有一个解析后的 `TTyStyleModel`（规则树），向注册的控件广播样式变化，并通过 `RegisterStyleable`/`UnregisterStyleable` 维护控件注册表。

**全局默认控制器 `TyDefaultController`：** 全局函数，返回一个按需惰性创建的单例 `TTyStyleController`（Owner 为 nil）。任何没有显式赋值 `Controller` 属性的 TyControls 控件在构造时自动注册到此全局实例。程序退出时由单元 `finalization` 节自动释放。

## 2. 单元

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Controller` |
| 基类 | `TComponent` |
| 可视 | 否（非控件） |

## 3. 属性表

### published 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `ThemeFile` | `string` | `''` | 主题文件路径（`.tycss` 文件）。赋值时若新值非空且文件存在则立即调用 `LoadTheme(AValue)`；若文件不存在则仅更新内部字段，不报错也不加载。 |

### public 只读属性（non-published）

| 属性 | 类型 | 说明 |
|------|------|------|
| `Model` | `TTyStyleModel` | 内部样式模型，持有解析后的 CSS 规则树。只读；通过 `LoadTheme` / `LoadThemeCss` 更新内容。 |

## 4. 方法

### public 方法

#### `procedure LoadTheme(const AFileName: string)`

从文件加载主题。等价于：

```pascal
FModel.LoadFromFile(AFileName);
FThemeFile := AFileName;
Changed;   // 广播 Invalidate 给所有注册控件
```

文件必须是 `.tycss` 格式（TyControls CSS 方言）。加载完成后立即广播样式变化，所有注册控件重绘——即**热重载**效果。

#### `procedure LoadThemeCss(const ASource: string)`

从内存字符串加载主题 CSS。等价于：

```pascal
FModel.LoadFromCss(ASource);
Changed;
```

适合在运行时动态生成样式或嵌入默认主题。`ThemeFile` 字段**不会**被此方法更新。

#### `procedure Changed`

遍历已注册控件列表（倒序，安全应对迭代中的删除），对每个控件调用 `Invalidate`，触发重绘。

这是**热重载**的核心：调用 `LoadTheme` 或 `LoadThemeCss` 后，所有已注册控件在下一个消息循环周期自动重绘为新样式，无需手动触发。

#### `procedure RegisterStyleable(AControl: TControl)`

将控件加入注册表（`FControls: TFPList`）。若控件已在列表中则忽略（防重复）。

通常由 `TTyCustomControl`/`TTyGraphicControl` 的构造函数自动调用，以及 `SetController` 切换控制器时调用。无需手动调用。

#### `procedure UnregisterStyleable(AControl: TControl)`

从注册表中移除控件。

由 `TTyCustomControl`/`TTyGraphicControl` 的析构函数和 `SetController` 自动调用。无需手动调用。

### 全局函数

#### `function TyDefaultController: TTyStyleController`

```pascal
function TyDefaultController: TTyStyleController;
```

返回全局默认控制器。内部逻辑：

```pascal
if GDefaultController = nil then
  GDefaultController := TTyStyleController.Create(nil);
Result := GDefaultController;
```

**语义：** 所有未显式设置 `Controller` 属性的 TyControls 控件在 `Create` 时调用 `ActiveController.RegisterStyleable(Self)`，而 `ActiveController` 在 `FController = nil` 时返回 `TyDefaultController`。因此，默认情况下所有控件统一由全局单例管理。

单元的 `finalization` 节执行 `FreeAndNil(GDefaultController)`，程序退出时自动清理。

## 5. 控件注册迁移与 FreeNotification 安全

当控件的 `Controller` 属性被更改时（`SetController` 被调用）：

```
旧 Controller != nil →
    旧 Controller.RemoveFreeNotification(Self)
    旧 Controller.UnregisterStyleable(Self)
旧 Controller == nil →
    TyDefaultController.UnregisterStyleable(Self)

FController := 新值

新 Controller != nil →
    新 Controller.FreeNotification(Self)  // 订阅释放通知
ActiveController.RegisterStyleable(Self) // 注册到新控制器
Invalidate
```

**FreeNotification 安全：** 控件通过 `FreeNotification` 订阅 `TTyStyleController` 的释放事件。当控制器被释放时，`TTyCustomControl.Notification(opRemove)` 将 `FController := nil`，此后该控件自动回退到 `TyDefaultController`。

## 6. ThemeFile 属性的热重载语义

```pascal
Controller.ThemeFile := 'themes/light.tycss';   // 立即加载并广播
Controller.ThemeFile := 'themes/dark.tycss';    // 再次赋值，切换主题
Controller.ThemeFile := '';                     // 只清空字段，不清除已加载样式
```

- 赋值时若文件不存在：仅更新 `FThemeFile` 字段，不调用 `LoadTheme`，已加载的样式不受影响，也不报错。
- 赋值相同路径（值未变）：`SetThemeFile` 中 `if FThemeFile = AValue then Exit`，不重复加载。
- 要强制重新加载同一文件，直接调用 `LoadTheme(FileName)` 方法。

## 7. 代码示例

### 使用全局默认控制器（最简场景）

```pascal
// 什么都不做——所有控件自动注册到 TyDefaultController
// 只需在程序启动时加载主题：

uses tyControls.Controller;

procedure TForm1.FormCreate(Sender: TObject);
begin
  TyDefaultController.LoadTheme(
    ExtractFilePath(ParamStr(0)) + 'themes/light.tycss');
end;
```

### 通过 ThemeFile 属性（IDE 设计器 / published 方式）

```pascal
// 在 Object Inspector 中设置 ThemeFile，或代码中：
StyleController1.ThemeFile := 'themes/light.tycss';  // 立即加载
```

### 运行时切换主题（热重载）

```pascal
procedure TForm1.BtnDarkThemeClick(Sender: TObject);
begin
  // 调用 LoadTheme 而非赋值 ThemeFile，避免被"值相同则跳过"拦截
  StyleController1.LoadTheme(
    ExtractFilePath(ParamStr(0)) + 'themes/dark.tycss');
  // 所有注册控件自动 Invalidate，下一帧重绘为暗色主题
end;
```

### 从内嵌字符串加载样式

```pascal
const
  MinimalCss =
    'TyButton { background: #EEEEEE; color: #333333; border-width: 1px; border-color: #AAAAAA; }';

begin
  TyDefaultController.LoadThemeCss(MinimalCss);
end;
```

### 多个独立样式控制器

```pascal
// 窗体 A 的控件使用 ControllerA（红色主题）
// 窗体 B 的控件使用 ControllerB（蓝色主题）
ControllerA := TTyStyleController.Create(Self);
ControllerA.LoadThemeCss('TyButton { background: #FFEEEE; }');

ButtonOnFormA.Controller := ControllerA;
// ButtonOnFormB 不设置 Controller，使用全局默认
```

### 安全释放场景

```pascal
// 若 ControllerA 被提前释放（如 Owner 释放），
// 已注册在 ControllerA 的控件会通过 FreeNotification → Notification(opRemove)
// 自动将 FController 置 nil，回退到 TyDefaultController。
// 控件的下次 Paint 会使用全局默认控制器的样式，不会崩溃。
```

## 8. 注意事项

1. **TyDefaultController 是惰性单例：** 第一次访问时创建，程序退出时由 `finalization` 释放；无需也不应手动释放它。
2. **ThemeFile 赋同值不重载：** `SetThemeFile` 有相同值保护；切换回同一文件需调用 `LoadTheme` 方法。
3. **文件不存在不报错：** `SetThemeFile` 检查 `FileExists` 后才调用 `LoadTheme`，文件缺失时静默忽略；建议在加载前自行检查文件路径。
4. **LoadThemeCss 不更新 ThemeFile 字段：** 调用 `LoadThemeCss` 后，`ThemeFile` 属性仍为旧值（或空字符串），不影响运行但需注意序列化/保存场景下的一致性。
5. **Changed 遍历是倒序的：** `for i := FControls.Count - 1 downto 0` 保证在 `Invalidate` 回调中即使控件从列表删除自身也不会跳过其他控件。
6. **控件 Controller 切换时注册迁移原子性：** `SetController` 先注销旧控制器、再注册新控制器，两个操作之间没有中间状态窗口，不会出现控件同时注册到两个控制器的情形。
7. **TTyFormChrome 不注册：** `TTyFormChrome` 继承 `TComponent` 而非 TyControls 控件基类，不参与控制器注册机制；其内部的 `TTyTitleBar` 和 `TTyCaptionButton` 各自独立注册。
