# TTyRibbonBackstage

Office 式「文件」**backstage** 视图:一个铺满窗口(除标题栏外)的浮层,左侧强调色**命令栏** +
右侧**内容区**。由 [TTyRibbonAppMenu](ribbonappmenu.md) 在设置了 `Backstage` 时打开(取代小下拉),
顶部返回箭头(←)或 Esc 关闭。

配色**令牌驱动**(不新增 .tycss):命令栏用 accent 的 `TyButton` `primary` 样式,内容区用 `TyRibbon`
表面,随主题变化。

## 属性 / 事件

| 成员 | 说明 |
|------|------|
| `Commands` | 左侧命令栏的条目(TStrings,如 开始/新建/打开/信息/保存…)。 |
| `ItemIndex` | 当前选中的命令(-1 = 无);改变时触发 `OnCommandSelect`。 |
| `SidebarWidth` | 命令栏宽度(逻辑 px,默认 180)。 |
| `OnCommandSelect(Sender, AIndex)` | 选中某命令时触发。 |
| `OnClose` | backstage 关闭时触发。 |

## 方法

| 方法 | 说明 |
|------|------|
| `ShowOver(AHost, ATopPx)` | 覆盖 AHost(窗体)顶部 ATopPx px 以下的区域(= 标题栏高度),显示 + 置顶。 |
| `Close` | 关闭。 |

## 用法(配合 TTyRibbonAppMenu)

```pascal
Backstage := TTyRibbonBackstage.Create(Self);
Backstage.Commands.Add('开始');
Backstage.Commands.Add('新建');
Backstage.Commands.Add('打开');
Backstage.Commands.Add('保存');
Backstage.ItemIndex := 0;

AppMenu := TTyRibbonAppMenu.Create(Self);
AppMenu.Backstage := Backstage;         // 点 File 就铺满窗口显示 backstage
AppMenu.BackstageTopInset := 34;        // = 标题栏高度,backstage 从其下方开始
```

## 说明

- 纯几何(`TyBackstageRowRect` / `TyBackstageRowAt`)已 headless 单测;渲染 + 覆盖窗体的交互需真机。
- 参见 [[TTyRibbonAppMenu]]、[[TTyRibbon]]。
