# TTyImageCollection / TTyVirtualImageList

## 1. 概述

`TTyImageCollection` 与 `TTyVirtualImageList` 是一对**非可视**组件(`TComponent`),构成 ty-controls 的**光栅图像**基础设施——它们是矢量图标字体([[TTyIconFont]] / `TTyGlyphImageList`)的**光栅对应物**:照片、真彩 PNG 等位图放这里,单色可缩放字形放图标字体。

- **TTyImageCollection** —— DPI 感知的**命名位图集合**。你用 `TBGRABitmap` 或 `TPicture` 按名字添加图像,集合为每个名字保留一张 master(最高分辨率源)位图。消费方按**目标像素尺寸**索取某个名字,得到一张缩放到该尺寸的新位图(保持宽高比、居中于透明方块)。一张 master 服务所有 DPI,调用方无需自行维护多套分辨率的图集。
- **TTyVirtualImageList** —— 引用一个 `TTyImageCollection` 的**有序虚拟图像列表**。按名字暴露集合中的一个子集,并可在消费方的目标像素尺寸上**按需**渲染 / 绘制任意一项。形态与 `TTyGlyphImageList` 完全一致,只是源自光栅集合而非图标字体。

两者都**按需渲染**、不缓存固定分辨率的图集,因此是带 `Draw` 方法的普通 `TComponent`,而非 `TCustomImageList` 后代——ty-controls 的自绘控件消费它们,而非 LCL 原生 `TImageList`。**headless 安全,无计时器。**

```pascal
uses tyControls.ImageCollection;
```

---

## 2. 单元

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.ImageCollection` |
| 类 | `TTyImageCollection`、`TTyVirtualImageList` |
| typeKey / 主题 | 无(非可视组件,不解析 `.tycss`,不绘制自身背景) |
| 依赖 | `BGRABitmap`、`Graphics`(`TPicture` / `TBitmap` / `TCanvas`) |

---

## 3. TTyImageCollection API

### 添加与清空

| 方法 | 说明 |
|------|------|
| `procedure AddBitmap(const AName: string; ABmp: TBGRABitmap)` | 以 `AName` 添加(或替换)一张图像。取 `ABmp` 的**副本**(`Duplicate`),调用方保留自己那份的所有权。`AName` 为空或 `ABmp` 为 `nil` 时为空操作。 |
| `procedure AddPicture(const AName: string; APicture: TPicture)` | 从 `APicture` 当前图形构建 master(任意 LCL 图形——PNG/BMP/JPG)。调用方保留 `APicture` 所有权。空名 / 空图形时为空操作。 |
| `procedure Clear` | 清空所有图像(释放每张 master)。 |

### 查询

| 方法 | 返回 | 说明 |
|------|------|------|
| `function Count: Integer` | `Integer` | 已存图像数。 |
| `function NameOf(AIndex: Integer): string` | `string` | `AIndex` 处的名字;越界返回 `''`。 |
| `function IndexOf(const AName: string): Integer` | `Integer` | 名字索引(大小写敏感);不存在返回 `-1`。 |
| `function Contains(const AName: string): Boolean` | `Boolean` | 名字是否存在。 |

### 渲染

| 方法 | 说明 |
|------|------|
| `function GetBitmap(const AName: string; ASizePx: Integer): TBGRABitmap` | 返回一张**新的、调用方拥有**的位图:`AName` 的 master 缩放到适配 `ASizePx` 见方(保持宽高比、居中于透明背景)。名字缺失时返回同尺寸的**空透明方块**(**永不为 `nil`、永不抛异常**);`ASizePx <= 0` 夹紧为 1px。**调用方负责 `Free`。** 缩放结果取自渲染缓存,因此重复调用只有一次分配 + 拷贝,不再重新 `Resample`。**正因为是副本,就地改像素(如 `TyTintBitmapAlpha` 着色)是安全的**,不会污染缓存。 |
| `function GetCachedBitmap(const AName: string; ASizePx: Integer): TBGRABitmap` | 返回缓存中 `(AName, ASizePx)` 的渲染结果——一个**借用引用**,归集合所有。**不要 `Free`、不要改它的像素**,也不要跨下一次调用继续持有。名字缺失时返回 `nil`(即"没什么可画的")。命中缓存时**零分配**:绘制代码 blit 图标应当走这条路径。`ASizePx <= 0` 夹紧为 1px。 |

### 渲染缓存

缩放结果按 `(名字, 像素尺寸)` 缓存,**LRU 淘汰**,并在集合发生任何变更时整体失效。

| 成员 | 说明 |
|------|------|
| `property ChangeStamp: Cardinal` | 每次变更(`AddBitmap` / `AddPicture` / `Clear`)自增。外部若缓存了由本集合派生的数据,可比较它来检测过期。2^32 次变更后回绕。**2.99.0 起由 `Version` 更名**——`Version` 现在是所有组件共有的只读库版本号。 |
| `property CacheCapacity: Integer` | 缓存条数上限(默认 `TyImageCacheDefaultCapacity` = 64),超出按最近最少使用淘汰。**调小时立即淘汰**。小于 1 夹紧为 1(上限为 0 会把 `GetCachedBitmap` 正要返回的那一条也淘汰掉)。 |
| `function CacheCount: Integer` | 当前缓存的渲染条数。诊断 / 测试用。 |
| `function IsCached(const AName: string; ASizePx: Integer): Boolean` | `(AName, ASizePx)` 当前是否在缓存里。**纯查询**:与 `GetCachedBitmap` 不同,它不计一次"使用",不会打乱 LRU 次序。诊断 / 测试用。 |

> 缓存非线程安全 —— 与消费它的控件一样,假定运行在 LCL 主线程。

---

## 4. TTyVirtualImageList API

### 属性(published)

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `Collection` | `TTyImageCollection` | `nil` | 光栅图像源。赋值时注册 `FreeNotification`,集合被先释放时引用自动置 `nil`。 |
| `Names` | `TStrings` | 空 | 要暴露的图像**名字**(有序,每行一个)——每个都是 `Collection` 中的键。 |
| `DefaultSize` | `Integer` | `16` | 默认项边长(**逻辑**像素),供不传尺寸的消费方使用。 |

### 方法

| 方法 | 说明 |
|------|------|
| `function Count: Integer` | 暴露项数(= `Names.Count`)。 |
| `function NameOf(AIndex: Integer): string` | `AIndex` 处的名字;越界返回 `''`。 |
| `function IndexOf(const AName: string): Integer` | 名字索引;不存在返回 `-1`。 |
| `function RenderIndex(AIndex, ASizePx: Integer): TBGRABitmap` | 从 `Collection` 渲染第 `AIndex` 项到 `ASizePx` 见方。**调用方拥有**返回位图。`Collection` 未设 / 索引越界 / 名字缺失时返回空透明方块(**永不为 `nil`**);`ASizePx <= 0` 夹紧为 1px。 |
| `function CachedIndex(AIndex, ASizePx: Integer): TBGRABitmap` | 第 `AIndex` 项在 `Collection` 渲染缓存中的结果——**借用引用**:**不要 `Free`、不要改像素**,也不要跨下一次调用继续持有。没什么可画时(`Collection` 未设 / 索引越界 / 名字缺失)返回 `nil`。这是绘制代码的**零分配**路径;需要拥有或修改位图时才用 `RenderIndex`。`ASizePx <= 0` 夹紧为 1px。 |
| `procedure Draw(ACanvas: TCanvas; AX, AY, AIndex: Integer; AEnabled: Boolean = True)` | **LCL 签名**(`imglist.pp:356`,逐参数一致)。按 `DefaultSize` 绘制第 `AIndex` 项到 `(AX, AY)`。`AEnabled = False` 画**变淡**的一版(见下)。守护所有边界情况(`nil` 画布 / 集合、坏索引),**永不抛异常**。 |
| `procedure DrawIndex(ACanvas: TCanvas; AIndex, AX, AY, ASizePx: Integer; AGhosted: Boolean = False)` | 带**显式像素尺寸**的一版——本库的绘制代码需要它(尺寸随 DPI 与行高变化),而 LCL 的 `Draw` 没地方放。走 `CachedIndex`,常规绘制无临时位图;`AGhosted = True` 时复制一份缓存位图再淡化,多一次分配。注意 `AGhosted` 是 `Draw` 里 `AEnabled` 的**反义**。 |

> ### ⚠ 3.0 破坏性变更:`Draw` 的参数顺序
>
> 从前是 `Draw(ACanvas, AIndex, AX, AY, ASizePx)`——顶着 LCL 的**方法名**,却把序号和坐标**对调**、
> 还多一个尺寸。所有参数都是 `Integer`,所以把 `Images.Draw(C, X, Y, Idx)` 移植过来最自然的改法
> 就是补上尺寸,写成 `Draw(C, X, Y, Idx, 16)`——**编译通过**,然后把第 X 号图画到了 `(Y, Idx)`。
>
> 现在 `Draw` 就是 LCL 那个签名,带尺寸的那版改名 `DrawIndex`。**四个 `Integer` 的 `Draw` 已不存在**,
> 所以旧调用点会**编译失败**而不是悄悄对调。**迁移**:`Draw(C, i, x, y, sz)` → `DrawIndex(C, i, x, y, sz)`。
>
> 同理,末位的旗标是 **`AEnabled` 而不是 `Ghosted`**:两者互为反义且都是 `Boolean`,写反了照样编译,
> 结果是每个图标都画成禁用态——这个 bug 在本库里已经出过一次。

### 变淡(ghosted)绘制

| 成员 | 说明 |
|------|------|
| `const TyGhostedAlpha = 96` | 变淡后保留的 alpha 比例(`96/255`)。淡到读得出"不可用",又浓到字形仍认得出——认不出的图标传达的是"坏了"而不是"禁用"。 |
| `procedure TyFadeBitmapAlpha(ABmp: TBGRABitmap; AFactor: Byte)` | 把每个像素的 alpha 按 `AFactor/255` 缩放(**就地修改**),连抗锯齿边缘一起均匀变淡。单元级导出,因为这是全库唯一的"不可用"观感,别的绘制代码也应当用它。 |

只改 alpha、不改颜色:图标保留自己的配色而失去存在感,这才是"不可用"该有的样子——换色说的是"另一个东西",不是"淡出"。`DrawIndex` 内部会先 `Duplicate` 再淡化:缓存位图是**共享**的,就地淡化会让这个图标从此在所有地方(包括别的控件里)都变淡。

---

## 5. 内存所有权

- **`AddBitmap` 取副本** —— 传入的 `TBGRABitmap` 被 `Duplicate`;调用方之后可自由释放 / 复用自己那份。
- **集合拥有 master** —— 每张 master 由集合持有,`Clear` / 析构时全部释放,无泄漏。
- **`GetBitmap` / `RenderIndex` 返回值归调用方** —— 用完必须 `Free`(见示例)。它们返回的是缓存渲染的**副本**,可以随意就地修改。
- **`GetCachedBitmap` / `CachedIndex` 返回值是借用的** —— 归集合的渲染缓存所有:**不要 `Free`、不要改像素**,blit 完即弃,别跨下一次调用继续持有(可能已被 LRU 淘汰或因变更失效)。绘制路径用它可以做到每个图标零分配、零重采样。
- **`Draw` / `DrawIndex` 自行管理** —— 走借用路径直接绘制,调用方无需理会;淡化时内部自建并释放一份副本,缓存不受污染。

---

## 6. 代码示例

```pascal
uses Graphics, BGRABitmap, BGRABitmapTypes, tyControls.ImageCollection;

var
  Coll: TTyImageCollection;
  VList: TTyVirtualImageList;
  Src, Bmp: TBGRABitmap;
begin
  Coll := TTyImageCollection.Create(Self);

  // 从 TBGRABitmap 添加(集合取副本,调用方可释放自己那份)
  Src := TBGRABitmap.Create(64, 64, BGRAWhite);
  try
    Coll.AddBitmap('logo', Src);
  finally
    Src.Free;
  end;

  // 从 TPicture 添加(PNG/BMP/JPG 均可)
  // Coll.AddPicture('avatar', SomePicture);

  // 按目标像素尺寸取图 —— 返回值归调用方
  Bmp := Coll.GetBitmap('logo', 24);   // 24x24,居中于透明方块
  try
    Bmp.Draw(Canvas, 8, 8, False);
  finally
    Bmp.Free;
  end;

  // 虚拟列表:引用集合,按名字暴露有序子集
  VList := TTyVirtualImageList.Create(Self);
  VList.Collection := Coll;
  VList.Names.Add('logo');
  VList.Names.Add('avatar');
  VList.DefaultSize := 20;

  // LCL 签名:(画布, X, Y, 序号)——按 DefaultSize 绘制第 0 项到 (40, 8)
  VList.Draw(Canvas, 40, 8, 0);

  // 同一项的"不可用"观感(剪切 / 禁用):只淡 alpha,不改颜色。注意是 Enabled=False
  VList.Draw(Canvas, 80, 8, 0, False);

  // 需要指定像素尺寸时用 DrawIndex:(画布, 序号, X, Y, 尺寸)
  VList.DrawIndex(Canvas, 0, 120, 8, 32);
end;
```

---

## 7. 注意事项

- **矢量 vs 光栅:** 单色、需任意缩放的图标用 [[TTyIconFont]] / `TTyGlyphImageList`(矢量按需光栅化);照片 / 真彩位图用本对组件(保留 master、按 DPI 缩放)。要把一张图当**可视控件**摆到界面上,用 [[TTyImage]]。
- **DPI 感知:** `GetBitmap` / `GetCachedBitmap` / `RenderIndex` / `CachedIndex` 的 `ASizePx` 是**设备(物理)像素**;`TTyVirtualImageList.DefaultSize` 是**逻辑**像素,消费方应自行乘以缩放因子后再传给渲染方法。
- **宽高比:** 缩放采用 **contain**(整图适配方块,不裁剪),多余区域为透明——非方形 master 会有透明留白带。
- **永不为 nil / 永不抛异常:** 缺失名字、坏索引、`ASizePx <= 0`、未设 `Collection` 等均安全返回空透明位图(`Draw` 直接安全空操作),消费方可无条件 blit。
- **headless 安全:** 纯逻辑 + BGRA 光栅操作,无窗口句柄、无计时器依赖,可在无 GUI 的 fpcunit 中完整测试。
