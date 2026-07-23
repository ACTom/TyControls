# TTyRibbonBackstage

Office 式「文件」**backstage** 视图:一个铺满窗口(除标题栏外)的浮层,左侧强调色**命令栏** +
右侧**内容区**。由 [TTyRibbonAppMenu](ribbonappmenu.md) 在设置了 `Backstage` 时打开(取代小下拉),
顶部返回箭头(←)或 Esc 关闭。

## 主题

内容区表面现在有**自己的 typeKey `TyRibbonBackstage`**,不再借 `TyRibbon` —— 一个铺满窗口、带强调色
命令栏和逐行悬停/选中态的浮层,与顶部那条 ribbon 命令带不是一回事,借着 `TyRibbon` 时皮肤根本够不着它。

| typeKey | 画什么 |
|---|---|
| `TyRibbonBackstage` | 右侧内容区的表面底色,以及无宿主内容时那个大号标题的字体/字色 |
| `TyButton` + `primary` | 左侧命令栏面板底色、行文字色与字体;`:hover` / `:active` 分别是悬停行与选中行的填充 |

尺寸走 metric token:`--backstage-sidebar-width`(默认 190)、`--backstage-back-height`(48)、
`--backstage-row-height`(42)、`--backstage-icon-x`(14)、`--backstage-icon-size`(18)、
`--backstage-text-inset`(40)。

> **命令栏仍然借 `TyButton.primary`,这是"尚未拆分"而非"设计如此"。** 现状是:皮肤没法把命令栏调成
> 主按钮以外的颜色,也没法把某一行的悬停/选中与按钮的悬停/按下分开配。`TyRibbonBackstageSidebar` /
> `TyRibbonBackstageItem`(+`:hover`/`:selected`) / `TyRibbonBackstageBack` /
> `TyRibbonBackstageSeparator` 是**有意推迟**的子部件键,**目前并不存在**,写进皮肤不会被解析。
> 清单与推迟原因见 `docs/superpowers/plans/2026-07-23-typekey-explicit-borrowers.md`。
>
> 另有几处视觉数值仍写死在绘制代码里:命令栏字号是 `ResolveFontSize(SideS) + 2`、大标题是 `fs + 8`
> 且字重固定 `600`、分隔线用的是命令栏的**文字色**(拿墨色当线色)、返回箭头几何与若干内边距为
> `P.Scale(...)` 常量。

## 属性 / 事件

| 成员 | 说明 |
|------|------|
| `Commands` | 左侧命令栏的条目(TStrings,如 开始/新建/打开/信息/保存…)。 |
| `ItemIndex` | 当前选中的命令(-1 = 无);改变时触发 `OnCommandSelect`。 |
| `SidebarWidth` | 命令栏宽度(逻辑 px)。不显式赋值时跟随主题的 `--backstage-sidebar-width`(内建回落 190);一旦写过就固定,不再跟主题走。 |
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
