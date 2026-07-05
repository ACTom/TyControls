# TTyIconFont

图标字体源（非可视组件）:注册一个图标字体(FontAwesome 之类的 .ttf),把字形**名字**映射到
Unicode 码点,再按需把任意命名字形渲染成 BGRA 位图(指定像素大小 + 颜色)。它是可缩放矢量图标
的骨干,被 [TTyCharImage](charimage.md)、[TTyGlyphImageList](glyphimagelist.md) 以及后续的
Ribbon 按钮消费。

渲染复用 BGRABitmap 的系统字体渲染路径——**不引入额外 FreeType 依赖**。字体文件加载走 Windows
原生 `AddFontResourceEx(FR_PRIVATE)`(无需系统安装即进程内可用);其他 widgetset 请自行安装该字体族
(后续可补 per-widgetset 加载器)。name→codepoint 映射是纯逻辑、已 headless 单测;实际栅格像素需
真机 + 字体。

## 属性

| 属性 | 说明 |
|------|------|
| `FontFamily` | 渲染用的字体族名(须与已注册/已安装的族一致;设了 `FontFile` 时通常就是该文件的族名)。 |
| `FontFile` | 可选 .ttf 路径,进程内私有加载(Windows);重设/清空会注销上一个。 |
| `Glyphs` | `name=HEX` 码点映射,每行一条,如 `save=F0C7`。设计期可编辑或从文件载入。 |

## 方法

| 方法 | 说明 |
|------|------|
| `MapGlyph(AName, ACodepoint)` | 增/改一个 name→codepoint 映射。 |
| `CodepointOf(AName): Cardinal` | 名字对应的码点,未映射返回 0。 |
| `GlyphText(AName): string` | 字形的 UTF-8 文本,未映射返回 ''。 |
| `HasGlyph(AName): Boolean` | 名字是否映射到有效码点。 |
| `RenderGlyph(AName, ASizePx, AColor): TBGRABitmap` | 把字形居中渲染进 ASizePx 见方的透明位图,**调用方负责释放**;未映射/尺寸≤0 返回空透明位图(永不为 nil)。 |

## 用法

```pascal
uses tyControls.IconFont;

Icons := TTyIconFont.Create(Self);
Icons.FontFile := 'assets/fa-solid-900.ttf';
Icons.FontFamily := 'Font Awesome 6 Free';   // 该 .ttf 的族名
Icons.MapGlyph('save', $F0C7);
Icons.MapGlyph('trash', $F1F8);

bmp := Icons.RenderGlyph('save', 24, TyRGB(60,60,60));
try
  bmp.Draw(Canvas, 8, 8, False);
finally
  bmp.Free;
end;
```

## 纯辅助

`TyParseCodepoint(AHex): Cardinal` — 解析 `'F0C7'` / `'0xF0C7'` / `'$F0C7'` / `'U+F0C7'`,空/非法/越界返回 0。

## 说明

- 字体文件私有加载目前仅 Windows;非 Windows 请安装字体族。
- 渲染像素需真机验证(headless 测试只覆盖映射与尺寸逻辑)。
- 参见 [[TTyCharImage]]、[[TTyGlyphImageList]]。
