# TTyGlyphImageList

## 1. 概述

TTyGlyphImageList 是一个**非可视组件**:一份有序的图标字体字形列表(按**名字**排列),背后由一个 [[TTyIconFont]] 提供字形。它不是 LCL 原生 `TImageList`,而是**供 Ty 控件消费**的按需矢量图像源——工具栏、树/列表行、Ribbon 按钮等在绘制时向它索要"第 N 个图标,在这个像素尺寸、这个颜色下的位图"。因为它是**按需矢量渲染**(而非固定分辨率的位图集),所以是一个带 `Draw` 方法的普通 `TComponent`,而**不是** `TCustomImageList` 的后代。

`Glyphs` 里存的是字形**名字**(一行一个),每个名字都是所引用 `IconFont.Glyphs` 映射表里的键。渲染时按名字在 IconFont 中查找并委托 `TTyIconFont.RenderGlyph` 光栅化——因此这里的"名字↔序号"记账是纯逻辑、可无字体在无头环境下单元测试;真正的像素则需要真机 + 已注册的字体(与字体本身同一约定)。

```pascal
uses tyControls.GlyphImageList;
```

---

## 2. 单元

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.GlyphImageList` |
| 类 | `TTyGlyphImageList` |
| 基类 | `TComponent`(非可视) |

---

## 3. 属性表

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `IconFont` | `TTyIconFont` | `nil` | 字形来源。赋值时注册 `FreeNotification`,字体组件被先释放时本引用自动置 `nil`。 |
| `Glyphs` | `TStrings` | 空 | 有序的字形**名字**,一行一个——每个名字是 `IconFont.Glyphs` 里的键。 |
| `DefaultSize` | `Integer` | `16` | 默认条目边长(逻辑 px),供不显式传尺寸的消费方使用。 |
| `DefaultColor` | `TTyColor` | `0` | 默认字形颜色(`$AARRGGBB`),供不显式传颜色的消费方使用。 |

---

## 4. 方法表(供消费方)

| 方法 | 返回 | 说明 |
|------|------|------|
| `Count` | `Integer` | 条目数(= `Glyphs.Count`)。 |
| `GlyphNameOf(AIndex)` | `string` | 第 `AIndex` 个字形名;越界返回 `''`。 |
| `IndexOf(const AName)` | `Integer` | 字形名 `AName` 的序号(大小写敏感);不存在返回 `-1`。 |
| `RenderIndex(AIndex, ASizePx, AColor)` | `TBGRABitmap` | 经 IconFont 渲染第 `AIndex` 项为 `ASizePx` 见方、`AColor` 着色、透明底的位图。**调用方负责释放**。永不返回 `nil`:IconFont 未设 / 序号越界 / `ASizePx<=0`(夹到 1px)时返回一个请求尺寸的空透明位图。 |
| `Draw(ACanvas, AX, AY, AIndex, AEnabled = True)` | —— | **LCL 签名**(`imglist.pp:356`)。按 `DefaultSize` / `DefaultColor` 渲染第 `AIndex` 项并绘制到 `(AX, AY)`;`AEnabled = False` 时只淡 alpha(与 `TTyVirtualImageList` 同一套"不可用"观感)。所有边界情况(空画布 / 空 IconFont / 坏序号)都有守卫,**绝不抛异常**。 |
| `DrawIndex(ACanvas, AIndex, AX, AY, ASizePx, AColor)` | —— | 带**显式尺寸与颜色**的一版(`Draw` 从前的形状)。内部用 `RenderIndex` 得到位图后 `bmp.Draw(ACanvas, AX, AY, False)` 混合上画布再释放。 |

> ### ⚠ 3.0 破坏性变更:`Draw` 的参数顺序
>
> 与 [`TTyVirtualImageList`](imagecollection.md) 完全同因同改:`Draw` 顶着 LCL 的方法名却把序号与坐标
> 对调,而所有参数都是 `Integer`,错序照样编译。现在 `Draw` 就是 LCL 那个签名,原来的形状改名
> `DrawIndex`。**迁移**:`Draw(C, i, x, y, sz, col)` → `DrawIndex(C, i, x, y, sz, col)`。

---

## 5. 代码示例

```pascal
uses tyControls.IconFont, tyControls.GlyphImageList;

var
  Font: TTyIconFont;
  Images: TTyGlyphImageList;
begin
  Font := TTyIconFont.Create(Self);
  Font.FontFamily := 'Font Awesome 6 Free';
  Font.FontFile := 'assets/fa-solid-900.ttf';   // 私有注册,免安装(Windows)
  Font.Glyphs.Text := 'save=F0C7' + LineEnding + 'trash=F1F8';

  Images := TTyGlyphImageList.Create(Self);
  Images.IconFont := Font;
  Images.Glyphs.Text := 'save' + LineEnding + 'trash';  // 有序:0=save, 1=trash
  Images.DefaultSize := 16;

  // 某个 Ty 控件在它的 Paint 里按需绘制第 0 个图标(显式尺寸 + 颜色):
  Images.DrawIndex(SomeCanvas, 0, X, Y, 16, $FF333333);

  // 或按 DefaultSize / DefaultColor,用 LCL 的 (X, Y, 序号) 顺序:
  Images.Draw(SomeCanvas, X, Y, 0);
end;
```

---

## 6. 注意事项

- **供 Ty 控件消费,非原生 `TImageList`:** 它渲染的是矢量字形,按调用方给的尺寸/颜色即时光栅化,专为 Ty 自绘控件设计;不要把它接到期待 `TCustomImageList` 的 LCL 原生控件上。
- **`Glyphs` 存名字,不存码点:** 这里一行一个字形**名字**,码点映射(`名字=HEX`)在 [[TTyIconFont]] 的 `Glyphs` 里;两者按名字对接。
- **真机 + 字体才有像素:** 名字↔序号逻辑无头可测且已单元测试,但真正画出字形需要真机上已注册对应字体;缺字体/缺映射时渲染的是空透明位图(不崩溃)。
- **`RenderIndex` 的所有权:** 返回的位图归调用方,用完 `Free`;`Draw` / `DrawIndex` 则自行渲染、绘制、释放,消费方无需管理位图。
- **字体先释放安全:** `IconFont` 通过 `FreeNotification` 跟踪,字体组件被先释放时引用自动置 `nil`,后续 `RenderIndex`/`Draw`/`DrawIndex` 退化为空位图而不崩溃。

---

## 参见

- [[TTyIconFont]] —— 字形来源(名字→码点映射 + 光栅化)。
- [[TTyCharImage]] —— 单个图标字体字形的可视控件。
