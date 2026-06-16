# 配方：Traffic-Light 风格标题栏按钮

本配方演示如何将 `TTyCaptionButton` 样式化为类似 macOS traffic-light（红/黄/绿圆形）的效果，
并配合 `ShowGlyphOnHoverOnly` 属性，让图标仅在鼠标悬停时才显示。

> **注意：** 这只是视觉上的近似，并非原生 macOS 标准窗口控件。原生 traffic-light
> 按钮集成了系统级动画和可访问性支持，本方案不提供这些特性。

---

## 1. tycss 样式片段

将以下规则加入你的主题 CSS 文件（或通过 `TTyStyleController.LoadThemeCss` 加载）：

```css
/* === Traffic-Light 标题栏按钮 === */

/* 基础尺寸与形状：12px 圆形（border-radius 设为高度的一半） */
TyCaptionButton.close,
TyCaptionButton.min,
TyCaptionButton.max {
    width: 12px;
    height: 12px;
    border-radius: 6px;
    border-width: 0px;
}

/* 关闭按钮 — 红色 */
TyCaptionButton.close {
    background: #FF5F57;
    color: #000000;
}
TyCaptionButton.close:hover {
    background: #E0423A;
    color: #6C0100;
}

/* 最小化按钮 — 黄色 */
TyCaptionButton.min {
    background: #FEBC2E;
    color: #000000;
}
TyCaptionButton.min:hover {
    background: #D99B0A;
    color: #7C4800;
}

/* 最大化按钮 — 绿色 */
TyCaptionButton.max {
    background: #28C840;
    color: #000000;
}
TyCaptionButton.max:hover {
    background: #1BA02E;
    color: #003D0F;
}
```

颜色来源：
- 红 `#FF5F57` / 悬停 `#E0423A`
- 黄 `#FEBC2E` / 悬停 `#D99B0A`
- 绿 `#28C840` / 悬停 `#1BA02E`

---

## 2. Pascal 代码：启用 ShowGlyphOnHoverOnly

窗体继承自 `TTyForm`，通过窗体只读的 `TitleBar` 属性访问三个系统按钮并设置属性：

```pascal
type
  TMainForm = class(TTyForm)   // 自绘窗框窗口
  end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  TitleBar.CloseButton.ShowGlyphOnHoverOnly := True;
  TitleBar.MinButton.ShowGlyphOnHoverOnly   := True;
  TitleBar.MaxButton.ShowGlyphOnHoverOnly   := True;
end;
```

**按钮访问器名称对照表：**

| 按钮       | 访问路径                  | Kind       |
|------------|---------------------------|------------|
| 关闭       | `TitleBar.CloseButton`    | cbkClose   |
| 最小化     | `TitleBar.MinButton`      | cbkMin     |
| 最大化     | `TitleBar.MaxButton`      | cbkMax     |

---

## 3. 效果说明

- **无悬停时：** 按钮显示纯色圆圈，不显示 ×/−/+ 图标。
- **悬停时：** 按钮变为较深的同色系颜色，并显示对应图标（颜色由 `color:` 属性决定）。
- **按下时（`:active` 状态）：** 图标同样可见（`FHover` 或 `FPressed` 任一为 True 均触发绘制）。

---

## 4. 完整示例

```pascal
// 窗体继承自 TTyForm：
//   type TMainForm = class(TTyForm) ... end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  // 加载主题
  StyleCtrl := TTyStyleController.Create(Self);
  StyleCtrl.LoadThemeCss(GetThemesDir + 'light.tycss');
  // 追加 traffic-light 规则
  StyleCtrl.LoadThemeCss(
    'TyCaptionButton.close { background: #FF5F57; color: #000000; ' +
    '  border-radius: 6px; border-width: 0px; }' +
    'TyCaptionButton.close:hover { background: #E0423A; color: #6C0100; }' +
    'TyCaptionButton.min { background: #FEBC2E; color: #000000; ' +
    '  border-radius: 6px; border-width: 0px; }' +
    'TyCaptionButton.min:hover { background: #D99B0A; color: #7C4800; }' +
    'TyCaptionButton.max { background: #28C840; color: #000000; ' +
    '  border-radius: 6px; border-width: 0px; }' +
    'TyCaptionButton.max:hover { background: #1BA02E; color: #003D0F; }'
  );

  ApplyChromeTheme(StyleCtrl);     // 窗体背景取自 TyForm 主题令牌
  TitleBar.Caption := '我的应用';

  // 启用 hover-only 图标显示
  TitleBar.CloseButton.ShowGlyphOnHoverOnly := True;
  TitleBar.MinButton.ShowGlyphOnHoverOnly   := True;
  TitleBar.MaxButton.ShowGlyphOnHoverOnly   := True;
end;
```

---

## 5. 已知限制

- 本方案是视觉近似，不是原生 macOS traffic-light 实现。
- macOS 原生按钮在光标离开窗口时会同时变灰，本方案仅处理单个按钮的悬停状态。
- 如需更接近原生体验，可在 macOS 上改用普通 `TForm`（原生路径，保留系统标题栏与红绿灯按钮），而不继承 `TTyForm`；可用 `{$IFDEF LCLCOCOA}` 条件编译选择窗体基类。
- Windows 上不存在 traffic-light 按钮的设计规范；此样式仅适合跨平台应用的 macOS 变体或完全自定义风格的应用。
