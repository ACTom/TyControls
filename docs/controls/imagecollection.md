# TTyImageCollection / TTyVirtualImageList

## 1. 概述

`TTyImageCollection` 与 `TTyVirtualImageList` 是一对**非可视**组件(`TComponent`),构成 ty-controls 的**光栅图像**基础设施——它们是矢量图标字体([[TTyIconFont]] / `TTyGlyphImageList`)的**光栅对应物**:照片、真彩 PNG 等位图放这里,单色可缩放字形放图标字体。

- **TTyImageCollection** —— DPI 感知的**命名位图集合**。你用 `TBGRABitmap` 或 `TPicture` 按名字添加图像,集合为每个名字保留一张或多张 master 位图。消费方按**目标像素尺寸**索取某个名字,得到一张缩放到该尺寸的新位图(保持宽高比、居中于透明方块)。一张 master 即可服务所有 DPI,调用方无需自行维护多套分辨率的图集;而当一个名字下**授权了多张分辨率**时,渲染前会先挑最合适的那张再缩放(见 §3.6)。母版存在 published 的 `Images` 集合里,**因而进 `.lfm`**——设计期加载的图会被保存、运行期能拿回来(见 §3.5)。
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
| 类 | `TTyImageCollection`、`TTyVirtualImageList`、`TTyImageItems` / `TTyImageItem`(母版集合) |
| typeKey / 主题 | 无(非可视组件,不解析 `.tycss`,不绘制自身背景) |
| 依赖 | `BGRABitmap`、`Graphics`(`TPicture` / `TBitmap` / `TCanvas`)、`base64`(`.lfm` 载荷编解码) |

---

## 3. TTyImageCollection API

### 添加与清空

| 方法 | 说明 |
|------|------|
| `procedure AddBitmap(const AName: string; ABmp: TBGRABitmap)` | 以 `AName` 添加(或**替换**)一张图像。会替换该名字下的**每一张**母版,所以这样加进来的名字是单分辨率的——这是老契约,也是常见情形。取 `ABmp` 的副本(编码成 PNG),调用方保留自己那份的所有权。`AName` 为空或 `ABmp` 为 `nil` 时为空操作。 |
| `procedure AddMasterBitmap(const AName: string; ABmp: TBGRABitmap)` | **2.99.0 新增。** 给 `AName` **追加**一张母版,保留已有的——一个名字因而可以带多个分辨率。加入顺序无所谓:挑选看尺寸不看位置。若已有同尺寸母版则**替换**它(同尺寸的第二张永远挑不中,留着只白占 `.lfm`)。 |
| `procedure AddPicture(const AName: string; APicture: TPicture)` | 从 `APicture` 当前图形构建 master(任意 LCL 图形——PNG/BMP/JPG)。调用方保留 `APicture` 所有权。空名 / 空图形时为空操作。语义同 `AddBitmap`(替换整个名字)。 |
| `procedure Clear` | 清空所有图像。 |

### 查询

| 方法 | 返回 | 说明 |
|------|------|------|
| `function Count: Integer` | `Integer` | 已存**图像(名字)**数。注意与 `Images.Count`(**母版**数)的区别:一个名字带 3 个分辨率时,`Count` 是 1,`Images.Count` 是 3。 |
| `function NameOf(AIndex: Integer): string` | `string` | `AIndex` 处的名字(去重后,首次出现顺序);越界返回 `''`。 |
| `function IndexOf(const AName: string): Integer` | `Integer` | 名字索引(大小写敏感);不存在返回 `-1`。 |
| `function Contains(const AName: string): Boolean` | `Boolean` | 名字是否存在。 |
| `function MasterCount(const AName: string): Integer` | `Integer` | **2.99.0 新增。** `AName` 名下有几张母版;名字不存在时为 0。 |
| `function PickedMasterSize(const AName: string; ASizePx: Integer): Integer` | `Integer` | **2.99.0 新增。** 请求 `ASizePx` 时**实际会被缩放的那张母版**的边长(`Max(W,H)`);没得画时为 0。这是从外部观察挑选结果的**唯一**途径——渲染出来的方块无论如何都是 `ASizePx`,挑错了母版从画面上看不出来。 |

### 渲染

| 方法 | 说明 |
|------|------|
| `function GetBitmap(const AName: string; ASizePx: Integer): TBGRABitmap` | 返回一张**新的、调用方拥有**的位图:`AName` 的 master 缩放到适配 `ASizePx` 见方(保持宽高比、居中于透明背景)。名字缺失时返回同尺寸的**空透明方块**(**永不为 `nil`、永不抛异常**);`ASizePx <= 0` 夹紧为 1px。**调用方负责 `Free`。** 缩放结果取自渲染缓存,因此重复调用只有一次分配 + 拷贝,不再重新 `Resample`。**正因为是副本,就地改像素(如 `TyTintBitmapAlpha` 着色)是安全的**,不会污染缓存。 |
| `function GetCachedBitmap(const AName: string; ASizePx: Integer): TBGRABitmap` | 返回缓存中 `(AName, ASizePx)` 的渲染结果——一个**借用引用**,归集合所有。**不要 `Free`、不要改它的像素**,也不要跨下一次调用继续持有。名字缺失时返回 `nil`(即"没什么可画的")。命中缓存时**零分配**:绘制代码 blit 图标应当走这条路径。`ASizePx <= 0` 夹紧为 1px。 |

### 渲染缓存

缩放结果按 `(名字, 像素尺寸)` 缓存,**LRU 淘汰**,并在集合发生任何变更时整体失效。

| 成员 | 说明 |
|------|------|
| `property ChangeStamp: Cardinal` | 每次变更自增——`AddBitmap` / `AddMasterBitmap` / `AddPicture` / `Clear`,**以及任何直接改动 `Images` 的路径**(对象查看器、`.lfm` 读入、`Images[i].PngBase64 := ...`)。外部若缓存了由本集合派生的数据,可比较它来检测过期。2^32 次变更后回绕。**2.99.0 起由 `Version` 更名**——`Version` 现在是所有组件共有的只读库版本号。 |
| `property CacheCapacity: Integer` | 缓存条数上限(默认 `TyImageCacheDefaultCapacity` = 64),超出按最近最少使用淘汰。**调小时立即淘汰**。小于 1 夹紧为 1(上限为 0 会把 `GetCachedBitmap` 正要返回的那一条也淘汰掉)。 |
| `function CacheCount: Integer` | 当前缓存的渲染条数。诊断 / 测试用。 |
| `function IsCached(const AName: string; ASizePx: Integer): Boolean` | `(AName, ASizePx)` 当前是否在缓存里。**纯查询**:与 `GetCachedBitmap` 不同,它不计一次"使用",不会打乱 LRU 次序。诊断 / 测试用。 |

> 缓存非线程安全 —— 与消费它的控件一样,假定运行在 LCL 主线程。

---

## 3.5 设计期存储:`Images` 与 `.lfm`(2.99.0 新增)

**2.99.0 之前,像素根本不进 `.lfm`。** master 只活在一个私有 `TStringList` 里,组件不流式化任何东西——在设计器里放一个集合、加载几张图、保存,再打开时一张都不剩,而且没有任何报错解释。图像只能由运行期代码添加。

现在 master 存在 **published 集合 `Images`** 里,它**就是**存储本身(不是一份镜像):

| 成员 | 说明 |
|------|------|
| `property Images: TTyImageItems` | 全部母版。**published**,因而进 `.lfm`。 |
| `TTyImageItem.ImageName: string` | 图像键。**不唯一**:同名多项 = 同一图像的多个分辨率(见 §3.6)。大小写敏感。 |
| `TTyImageItem.PngBase64: string` | 该母版的像素:一张 PNG,base64 编码。**这是唯一事实来源**——`Master` 是从它解码出来的缓存,不是反过来。 |
| `TTyImageItem.Master: TBGRABitmap` | 解码后的母版,**借用引用**(归该项所有,不要 `Free`)。载荷为空或解不开时为 `nil`。 |
| `TTyImageItem.IsDecodable: Boolean` | 纯查询:载荷非空**且**能解出可用位图。它对"空"和"坏"都是 `False`,单独用分不清两者;**配合 `PngBase64` 才分得清**:`PngBase64 <> ''` 而 `IsDecodable` 为 `False` = **载荷坏了**。`Master` 两种情况都返回 `nil`,做不到这件事。 |
| `TTyImageItem.MasterSize: Integer` | 母版边长 `Max(W,H)`;没有可用母版时为 0。 |
| `TTyImageItem.SetBitmap(ABmp)` | 用 `ABmp` 换掉本项像素(编码成 PNG 副本,调用方保留自己那份)。 |

设计期加载图片:在对象查看器里展开 `Images`(标准集合编辑器),给一项点 `PngBase64` 的 **`...` 按钮**,选一个图片文件即可。该项 `ImageName` 为空时会自动取文件主名(放进 `save.png` 就得到 `save`)。载荷本身在网格里显示为摘要(`PNG 32x32`),不可直接键入——没人手打四千字节 base64,而尝试手打正是载荷被截断、图标从此静默解不出来的由来。

### 为什么是可读的 base64 文本,而不是 LCL 那种二进制块

LCL 的 `TCustomImageList` 用 `DefineProperties`(`imglist.pp:314`)把像素写成不透明的 `Bitmap`/`Data` 十六进制块。**本库刻意不这么做**,理由与 `TTyTreeView.Items` 相同(commit `a8d98b7`):

> 伪属性**对 IDE 不可见**。Lazarus 的 LFM 检查器按类的 published RTTI 逐个解析 `.lfm` 里的标识符,而 `DefineProperties` 不产生任何 RTTI——于是 IDE 会以 `identifier Data not found in class ...` 拒绝**整个窗体**,并提示你把它删掉。

这件事本库已经吃过一次:`examples/demo/mainform.pas` 里那棵**原生 LCL** 树是用代码建的,注释里写的就是这个原因——流式化的窗体在 IDE 里打不开。

因此本单元流式化路径上的每一个属性都是**带真实 RTTI 的 published 属性**,全单元不调用 `DefineProperties`。

**代价是体积**:base64 是 PNG 的 4/3,而一套图标不是三个树节点。**换来的是**:窗体能打开;`git diff` 能看出**哪一个**图标变了(逐项,而不是一整坨十六进制);标准集合编辑器不用写一行代码就能用。

---

## 3.6 多分辨率母版(2.99.0 新增)

**2.99.0 之前,一个名字只有一张母版**,HiDPI 下只能把它缩放,不能换用为该尺寸绘制的那一张。

现在**一个名字可以出现在多个项上**,每项是一个分辨率的母版。格式不因此改变——一个名字带一张还是五张母版,`.lfm` 的形状完全一样,所以后来增加分辨率不会改动已存盘的文件。

挑选规则(`GetBitmap` / `GetCachedBitmap` 渲染前):

> 取**仍然覆盖请求尺寸的最小那张**母版;都不够大时取**最大**的那张。

```pascal
Coll.AddBitmap('ico', Bmp16);          // 名字 'ico',一张 16px 母版
Coll.AddMasterBitmap('ico', Bmp64);    // 追加 64px
Coll.AddMasterBitmap('ico', Bmp32);    // 追加 32px(顺序无所谓)

Coll.PickedMasterSize('ico', 24);      // -> 32:24 要放大 16(糊),64 是多余的降采样
Coll.PickedMasterSize('ico', 16);      // -> 16:正好覆盖
Coll.PickedMasterSize('ico', 33);      // -> 64
Coll.PickedMasterSize('ico', 128);     // -> 64:没有够大的,用最大的
Coll.Count;                            // -> 1(一个名字)
Coll.Images.Count;                     // -> 3(三张母版)
```

挑选**只在同名母版之间**进行——另一个图标的大母版不会被借用。

> 载荷坏了(比如手改 `.lfm` 把 base64 改断)时:该项 `IsDecodable` 为 `False`、`Master` 为 `nil`,渲染退化成**空白透明方块**,**不抛异常**。窗体照常打开——一个打不开的窗体比一个空白图标糟得多。

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
- **`Count` 不是 `Images.Count`:** 前者数**名字**,后者数**母版**。多分辨率下两者必然不等,`for i := 0 to Coll.Count - 1 do Coll.Images[i]` 是错的——要遍历名字用 `NameOf(i)`,要遍历母版用 `Images[i]`。
- **`.lfm` 会变大:** 像素以 base64 PNG 存进窗体文件(每张母版一段)。这是为了让窗体能在 IDE 里打开、让 diff 看得出改了哪个图标而付的代价(见 §3.5)。图标多、分辨率多时 `.lfm` 相应变大;真正巨大的图集仍应在运行期从外部资源加载。
- **同名 = 同一图像的不同分辨率:** 名字**不是**唯一键(`Images` 里可以有多项同名)。`AddBitmap` 会替换该名字下的**全部**母版,只想加一个分辨率要用 `AddMasterBitmap`。
