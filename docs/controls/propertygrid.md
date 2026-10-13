# TTyPropertyGrid

## 1. 概述

TTyPropertyGrid 是属性表格:把一个对象交给它,它就列出这个对象的 published 属性,每种类型配好编辑器,用户改完直接写回对象。做设置面板、调试面板、简易的界面编辑器都用得上。

```pascal
uses tyControls.PropertyGrid;

PropGrid.SelectedObject := Button1;              // 列出 Button1 的属性,改了就写回 Button1
PropGrid.SelectObjects([Button1, Button2]);      // 同时改两个按钮
```

它建在 [TTyValueListEditor](valuelisteditor.md) 上,外观、键盘操作、两列布局和可拖的分隔条都和值列表编辑器一样。不同的是行由表格自己生成:从对象的 RTTI 读出来,写回也走 RTTI。只用 RTL 的 `TypInfo`,不依赖 IDE 的 `PropEdits`,所以就在主包 `tycontrols` 里,运行时程序直接能用。

完整演示见 [examples/propertygrid](../../examples/propertygrid/):左边几个控件,点哪个右边就检查哪个,按住 Ctrl 点可以多选;顶部有过滤框(`FilterText`)、「只看可写的」(`OnFilterProperty`)、「分类」和「显示事件」几个开关;检查左边的字符串表格时,可以给它增删列。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|---|---|
| 单元 | `tyControls.PropertyGrid` |
| 类型 | `TTyPropertyGrid`(只负责发布)、`TTyCustomPropertyGrid`(全部实现,派生用它) |
| 面板 | `TyControls Lists`,紧跟在 `TTyValueListEditor` 后面 |
| `GetStyleTypeKey` | `'TyPropertyGrid'`,经类型键链回退到 `'TyValueListEditor'` |

内置主题都没有给 `TyPropertyGrid` 写规则,所以它和值列表编辑器长得一模一样。想单独给属性表格换个样子,在主题里写 `TyPropertyGrid { ... }` 就行,不会影响值列表编辑器。行、键列、值列、分隔线、展开三角用的仍是值列表编辑器那几个部件键(`TyValueListEditorRow`、`TyValueListEditorKey` 等,见[它的文档](valuelisteditor.md#2-单元与-typekey))。

分类的标题行用 `TyValueListEditorGroup`,它挂在 `TyValueListEditorRow` 下面:没写它的主题,标题行先照普通行的样子画,再叠上基础层给它的那一条——一道淡淡的底色(正文颜色 8% 的透明度,深浅主题下都看得出来)、正文颜色、粗体。这条规则只管**平时**的样子;鼠标悬停或者选中时,标题行和普通行一样用 `TyValueListEditorRow:hover` / `:active`,所以哪个皮肤下选中的样子都一致。

---

## 3. 类型与编辑器

| 属性类型 | 行的样子 |
|---|---|
| 整数、`Int64`、`QWord`、`Cardinal` | 数字输入,只收数字;超出类型范围的值会被拒绝 |
| 字符(`Char`、`WideChar`) | 文本输入,只收一个字符;控制字符写成 `#9` 这种形式 |
| 浮点 | 数字输入。显示和解析**一律用 `.` 作小数点**,不跟系统区域设置走 |
| `TDateTime` / `TDate` / `TTime` | 按本机格式显示的日期时间文字,按文本编辑、按本机格式解析 |
| 字符串(含 `TCaption`、`TTranslateString`) | 文本输入 |
| 布尔 | `False` / `True` 下拉;选中这一行按**空格**直接切换 |
| 枚举 | 下拉,选项是这个枚举的全部名字 |
| 集合 | 显示成 `[akLeft,akTop]`;展开后每个元素一行布尔,改哪个元素就写回整个集合 |
| `TColor` | 色板下拉,最后一项「更多…」打开取色对话框 |
| `TFont` | 字体行:`…` 打开字体对话框;展开后 `Name`、`Size`、`Style` 等各占一行。不管从哪里改,都是先改一份副本,再整体写回 |
| 其他 `TPersistent` 子对象(`Constraints`、`BorderSpacing` 等),以及带 `csSubComponent` 的子组件 | 显示 `(TSizeConstraints)` 这样的类名,本行只读;展开后是子对象自己的属性,可以直接改 |
| `TCollection`(表格的列、状态栏的面板) | 显示 `(3 items)`;每一项一行,显示项的 `DisplayName`,再展开就是这一项的属性。项可以增删、调整顺序(§8) |
| 组件引用(`PopupMenu`、`Images`、`ActiveControl`……) | 下拉,第一项是 `(none)`,后面是候选组件的名字(见 §5.4) |
| `TStrings` | `…` 打开一个多行文本对话框,每行一项 |
| 事件 | 默认不显示;`TypeFilter` 加上 `tkMethod` 后显示处理程序的名字,只读 |
| 接口、变体、不是 `TPersistent` 的类 | 表格自己不显示;应用可以经 `OnGetPropertyText` / `OnSetPropertyText` 显示和编辑(§5.6) |

没有 setter 的属性一律只读。类属性没有 setter 也照样展开,因为子对象自己的属性往往可写(`Font`、`Constraints` 都是这样)。子对象的展开有深度上限(默认 6 层,`PropertyRows.MaxDepth`),防止两个对象互相引用时无限展开。

记录和超过 32 个元素的集合在 FPC 3.2.2 上根本不能 published,所以不会出现。

---

## 4. 关键成员

| 成员 | 说明 |
|---|---|
| `SelectedObject: TPersistent` | 要检查的对象,任何 `TPersistent` 都行。public,运行时用。选了多个时读回的是第一个;写它就是只选这一个 |
| `SelectedComponent: TComponent` | 和 `SelectedObject` 是同一个字段:只选了一个、而且它是组件时返回它,否则返回 nil;写它就是写 `SelectedObject`。这个是 published 的,在对象查看器里选一个组件,窗体一载入表格就显示它,设置面板一行代码都不用写 |
| `SelectObjects([...])`、`SelectedCount`、`SelectedObjects[i]` | 同时检查多个对象(§7) |
| `Rebuild` | 按选中的对象重新生成所有行。展开的行和当前行(按属性路径)都会保留 |
| `Refresh` | 只重读每一行的值,不重建。对象被代码改过之后调它。如果对象的结构变了(集合多了一项、子对象从无到有),它会自动重建,同样保留展开状态和当前行 |
| `PropertyAt(ARow, out AInstance, out APropName): Boolean` | 这一行改的是哪个对象的哪个属性。集合元素那一行返回整个集合属性;集合项本身那一行、分类标题行、以及不是表格生成的行返回 False |
| `SelectedRow`、`RowPath(ARow)` | 当前行;一行的点号路径(格式同 `ExpandedProperties`,集合项是 `Items[1]`) |
| `AddCollectionItem` / `DeleteCollectionItem` / `MoveCollectionItem` | 用代码增删、移动集合项,参数是路径(§8) |
| `PropertyOrder` | `poAlphabetical`(默认,和对象查看器一样按名字排序,不区分大小写)或 `poDeclared`(按类里声明的顺序,祖先的在前) |
| `TypeFilter: TTypeKinds` | 显示哪些种类的属性。默认是除 `tkMethod` 以外的全部,也就是不显示事件 |
| `HiddenProperties: TStrings` | 不显示的属性,写名字(`Tag`)或者点号路径(`Font.Height`) |
| `ShowCategories` | 顶层属性按分类分组(§9),默认关 |
| `FilterText` | 只显示名字里含这段文字的属性(§10),public |
| `ExpandedProperties: TStrings` | 展开着的行的路径:`Font`、`Font.Style`、`Header.Columns[0]`,分类标题是 `@Layout` 这样。切换到另一个对象时保留,所以在一个按钮上展开了 `Font`,换到下一个按钮也是展开的;往里加一条路径,对应的行马上展开 |
| `ReadOnly` | 整个表格只读 |
| `KeyColumnWidth` | 属性名那一列的宽度(逻辑像素,可以拖) |
| `PropertyRows` | 背后的对象→行映射(`TTyPropertyRows`),一般用不到;`MaxDepth` 在这里 |
| `KeyOptions` | 固定为 `[]`:属性名不能改,行不能用值列表编辑器的方式增删 |

改 `PropertyOrder`、`TypeFilter`、`HiddenProperties`、`ShowCategories`、`FilterText` 会马上重建。`OnFilterProperty`、`OnGetPropertyCategory` 这些是生成行的时候问的,处理程序的判断条件变了要自己调一次 `Rebuild`。

---

## 5. 事件与扩展点

内置的只是常用的那部分,其余的交给事件、虚方法和公开方法,用不着改控件。

### 5.1 过滤:`OnFilterProperty`

```pascal
procedure (Sender: TObject; AInstance: TPersistent; const APropName: string; var AShow: Boolean)
```

每个 published 属性生成行之前都问一次(`TypeFilter` 和 `HiddenProperties` 先滤掉的除外),`AShow := False` 就不显示。表格自己能显示的属性,`AShow` 进来是 True;接口、变体这类表格不认识的,进来是 False(见 §5.6)。子对象的属性也会问,这时 `AInstance` 是子对象(比如 `Font`)。

按名字找属性用 `FilterText` 就够了(§10),这个事件适合按别的条件筛。示例里的「只看可写的」:

```pascal
procedure TMainForm.GridFilterProperty(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var AShow: Boolean);
var pi: PPropInfo;
begin
  if not SwWritable.Checked then Exit;
  pi := GetPropInfo(AInstance, APropName);
  // 没有 setter 的去掉;但 Font、Constraints 这种子对象留着,它们自己的属性能改
  if (pi <> nil) and (pi^.SetProc = nil) and (pi^.PropType^.Kind <> tkClass) then
    AShow := False;
end;
```

### 5.2 写回:`OnPropertyChanging` / `OnPropertyChanged` / `OnPropertyError`

```pascal
OnPropertyChanging(Sender; AInstance: TPersistent; const APropName, ANewValue: string; var AAllow: Boolean)
OnPropertyChanged(Sender; AInstance: TPersistent; const APropName: string)
OnPropertyError(Sender; AInstance: TPersistent; const APropName: string; E: Exception)
```

- 写之前先问 `OnPropertyChanging`,`AAllow := False` 就不写,行保持原值。`ANewValue` 是属性写进去以后的样子:改集合的一个元素时,它是整个集合(`[akLeft,akTop,akRight]`),不是 `True`。
- 写成功后触发 `OnPropertyChanged`。
- 写失败(值解析不了、超出范围、setter 抛了异常)时,行保持对象里的值。挂了 `OnPropertyError` 就交给它处理,异常到此为止;没挂就照 LCL 的惯例把异常抛出去,最后由 `Application.HandleException` 弹出错误框。
- `AInstance` 是**真正拥有这个属性的对象**:改 `Font.Size` 时,`AInstance` 是那个 `TFont`,`APropName` 是 `Size`;在字体对话框里整体换字体时,`AInstance` 是按钮,`APropName` 是 `Font`。
- 选了多个对象时,每个对象各问、各发一次(§7)。

一个属性的 setter 常常会顺带改别的属性(`AutoSize` 改 `Width`、`Constraints` 改尺寸),所以每次写回之后,表格会把同一对象的其他行全部重读一遍。

### 5.3 改造行:`OnGetPropertyRow`

```pascal
procedure (Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo; ARow: TTyValueRow)
```

每个属性的行建好之后(连同它下面的行)调用一次;集合的元素行、集合项那一行、分类标题行不调。可以改 `ARow.EditorKind`、`EnumValues`、`DisplayValue`、样式(`Bold`、`TextColor`、`ImageIndex`),或者把行设成只读。例如把某个字符串属性换成对话框编辑:

```pascal
if APropInfo^.Name = 'FileName' then ARow.EditorKind := vekDialog;
```

### 5.4 组件引用的候选:`OnGetComponentNames`

组件引用那一行的下拉,默认列出「候选根」名下、类型兼容的组件:

- 检查的对象是窗体、数据模块或框架(`TCustomForm`、`TDataModule`、`TCustomFrame`)时,候选根就是它自己。检查一个窗体,它的 `ActiveControl` 就能从窗体上的控件里选。
- 其他组件的候选根是它的 `Owner`,一般就是它所在的窗体。
- 候选根自己类型兼容的话也列进去。
- 当前值不在清单里时也会补上,不然看起来像是选了别的。
- 选了多个对象时,按第一个对象来定候选根;选中的组件写进每一个对象。

```pascal
procedure (Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo; AList: TStrings)
```

`AList` 进来时已经是默认清单,`Objects[]` 里放着对应的组件。可以增、删、调整顺序;跨窗体的组件要连同对象一起加:`AList.AddObject('PopupMenu3', OtherForm.PopupMenu3)`,否则选了也找不到它。

### 5.5 对话框行:`OnEditProperty`

```pascal
procedure (Sender: TObject; ARow: TTyValueRow; AInstance: TPersistent;
  const APropName: string; var AHandled: Boolean)
```

点任何对话框行(`vekDialog`)的 `…` 时先触发它。处理程序自己弹对话框、自己写**属性**(不是写行),然后设 `AHandled := True`,表格随后会重读所有行;没设 `AHandled`,就走内置的处理:`TStrings` 弹多行文本对话框,其他对话框行什么都不做。不是表格生成的行,`AInstance` 为 nil、`APropName` 为空。

配合 `OnGetPropertyRow` 和 `PropertyAt`,就能给某一类属性接上自己的编辑器:

```pascal
procedure TMainForm.GridEditProperty(Sender: TObject; ARow: TTyValueRow;
  AInstance: TPersistent; const APropName: string; var AHandled: Boolean);
var dir: string;
begin
  if APropName <> 'Folder' then Exit;
  dir := GetStrProp(AInstance, 'Folder');
  if TySelectDirectory('选择文件夹', '', dir) then SetStrProp(AInstance, 'Folder', dir);
  AHandled := True;
end;
```

值列表编辑器原有的 `OnEditRow` 在属性表格上不发布,请用 `OnEditProperty`。

### 5.6 属性的文字由应用来定:`OnGetPropertyText` / `OnSetPropertyText`

```pascal
OnGetPropertyText(Sender; AInstance: TPersistent; APropInfo: PPropInfo; var AText: string; var AHandled: Boolean)
OnSetPropertyText(Sender; AInstance: TPersistent; APropInfo: PPropInfo; const AText: string; var AHandled: Boolean)
```

这两个事件接管一个属性的文字,读和写各一个。设了 `AHandled`,表格就不做自己的转换。

- **表格认识的类型**:想换个写法时用。比如颜色显示成 `#0000FF` 而不是 `clRed`,读的时候在 `OnGetPropertyText` 里给出文字,写的时候在 `OnSetPropertyText` 里自己解析、自己写属性。没处理的属性照旧走表格的转换。
- **表格不认识的类型**(接口、变体、不是 `TPersistent` 的类):`OnFilterProperty` 会问到它们,`AShow` 进来是 False。处理程序把 `AShow` 设成 True、而且 `OnGetPropertyText` 给出了文字,它就列出来。没挂 `OnSetPropertyText` 时这一行只读,挂了就能编辑。
- 集合的元素行(`Font.Style` 下面的 `fsBold`)是整个集合的一部分,不单独问。
- 选了多个对象时,每个对象各问一次;`OnSetPropertyText` 里抛的异常和 setter 抛的一样处理(`OnPropertyError`)。
- 挂上或换掉这两个事件不会自动重建,要调一次 `Rebuild`。

再加上 `OnGetPropertyRow`(编辑器种类、选项)和 `OnEditProperty`(对话框),一个表格完全不认识的类型,应用也能完整地显示和编辑。

### 5.7 派生类:`BuildPropertyRow`、`GetPropertyText`、`SetPropertyText`

要给某种类型换一套整行的做法,而且想做成可以复用的控件,就从 `TTyCustomPropertyGrid` 派生,覆盖这三个 protected 虚方法:

- `BuildPropertyRow(ANode)`:建一个属性的行。进来时 `ANode.Row` 已经建好(键是属性名,`Data` 指向节点),这个方法负责填它:编辑器种类、选项、只读、值,以及它下面的行。默认是 `PropertyRows.FillRow` 加 `PropertyRows.AddChildren`;不调默认的,下面就没有行。分类标题、集合元素、集合项不经过它。
- `GetPropertyText` / `SetPropertyText`:和 §5.6 的两个事件同一个时机、同样的含义,返回 True 表示处理了。默认就是去问那两个事件,所以派生类处理完自己的类型,其余的调 `inherited`,应用挂的事件照样有效。

```pascal
type
  { TStrings 显示成一行逗号分隔的文字,就地编辑,不再弹对话框 }
  TMyPropertyGrid = class(TTyPropertyGrid)
  protected
    procedure BuildPropertyRow(ANode: TTyPropertyNode); override;
    function GetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
      var AText: string): Boolean; override;
    function SetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
      const AText: string): Boolean; override;
  end;

procedure TMyPropertyGrid.BuildPropertyRow(ANode: TTyPropertyNode);
begin
  if ANode.Kind <> pnkStrings then
  begin
    inherited BuildPropertyRow(ANode);
    Exit;
  end;
  ANode.Row.EditorKind := vekText;
  ANode.Row.ReadOnly := False;
  ANode.Row.Value := PropertyRows.ReadText(ANode);   // 经 GetPropertyText 读
end;

function TMyPropertyGrid.GetPropertyText(AInstance: TPersistent; APropInfo: PPropInfo;
  var AText: string): Boolean;
begin
  Result := (APropInfo^.PropType^.Kind = tkClass)
    and GetTypeData(APropInfo^.PropType)^.ClassType.InheritsFrom(TStrings);
  if Result then
    AText := TStrings(GetObjectProp(AInstance, APropInfo)).CommaText
  else
    Result := inherited GetPropertyText(AInstance, APropInfo, AText);
end;
```

`SetPropertyText` 同理:是 `TStrings` 就 `CommaText := AText` 并返回 True,否则调 `inherited`。之后 `OnGetPropertyRow` 照样会调到。

---

## 6. 交互

- 点值列开始编辑:文本和数字直接输入,布尔、枚举、颜色、组件引用是下拉,字体和对话框行点尾部的 `…`。选中一行按 **F2** 或 **Enter** 也行。
- **Enter** 提交,**Esc** 放弃,点到别处也算提交。
- 选中布尔行(包括集合的元素行)按**空格**直接切换。
- 点属性名前面的三角展开或收起;分类标题行上按 **Enter** 也能展开、收起。
- 集合行和集合项上:**Insert** 加一项,**Ctrl+Delete** 删当前项,**Ctrl+↑ / Ctrl+↓** 移动当前项;右键有同样的菜单(§8)。

---

## 7. 同时检查多个对象

```pascal
PropGrid.SelectObjects([Button1, Button2, Edit1]);
```

- **列出的是大家都有的属性**:名字相同、类型也相同(`PTypeInfo` 相同)才算。两个类都有 `Kind`,一个是枚举、一个是整数,就不列。子对象(`Font`、`Constraints`)只在所有对象里是同一个类时才展开,否则这一行只读。
- **值不一样时格子是空的。** 布尔和集合元素也一样;选中这一行按空格,或者在下拉里选一次,就统一成选中的值。
- **改一处,每个对象都写。** 先对每个对象各问一次 `OnPropertyChanging`,只要有一个拒绝,就一个都不写;写成功后每个对象各发一次 `OnPropertyChanged`。
- **某个对象的 setter 抛了异常**,写到这个对象为止:前面已经写成的不回滚(和对象查看器一样),行重读、显示对象里的实际值,`OnPropertyError` 报的是出错的那个对象。
- **集合只显示 `(…)`**,只读、不展开,也不能增删:两组项没法一一对应。
- `TStrings` 对话框:各对象的内容一样时显示这份内容,不一样时从空白开始。
- 组件引用的下拉以第一个对象的候选为准(§5.4)。
- 任何一个组件被释放,就从选择里去掉它,剩下的照常显示。
- `SelectedObject` 读回第一个,写它就是只选一个;`SelectedComponent` 只在单选时有值。`SelectObjects([])` 清空;nil 和重复的会被去掉。

示例里按住 Ctrl 点控件就是这么做的:

```pascal
if ssModifier in GetKeyShiftState then
  // 把 Sender 加进或移出当前选择,再 SelectObjects(...)
else
  Grid.SelectedComponent := Sender as TComponent;
```

---

## 8. 集合项的增删和排序

检查一个对象时,它的集合(表格的列、状态栏的面板)可以就地增删、调整顺序:

| 操作 | 键盘 | 右键菜单 | 代码 |
|---|---|---|---|
| 加一项 | 集合行上按 **Insert** 加在末尾;项上按,加在这一项后面 | 「添加项」 | `AddCollectionItem('Items')`、`AddCollectionItem('Items[1]')` |
| 删一项 | 项上按 **Ctrl+Delete** | 「删除项」 | `DeleteCollectionItem('Items[1]')` |
| 上移 / 下移 | 项上按 **Ctrl+↑ / Ctrl+↓**,到头就停 | 「上移」「下移」 | `MoveCollectionItem('Items[1]', -1)` |

- 做完之后行会重建,展开的项跟着项走,当前行落在新加的或移动的那一项上;删了就落在原位置的下一项,没有就上一项,再没有就是集合行。
- 删除不弹确认框。要确认的话在 `OnCollectionChanging` 里自己问。
- 选了多个对象、表格 `ReadOnly`、设计期,都不能增删。
- 内置菜单只在表格的 `PopupMenu` 没设时出现。应用有自己的菜单时,用 `SelectedRow` 和 `RowPath` 拿到当前行的路径,再调上面三个公开方法,效果完全一样。

```pascal
OnCollectionChanging(Sender; ACollection: TCollection; AAction: TTyCollectionAction;
  AIndex, ANewIndex: Integer; var AAllow: Boolean)
OnCollectionChanged(Sender; ACollection: TCollection; AAction: TTyCollectionAction;
  AIndex, ANewIndex: Integer)
OnCreateCollectionItem(Sender; ACollection: TCollection; var AItem: TCollectionItem)
```

- `AAction` 是 `caAdd`、`caDelete`、`caMove`。加:`AIndex` 和 `ANewIndex` 都是新项的位置;删:`AIndex` 是被删的项,`ANewIndex` 为 -1;移:从 `AIndex` 移到 `ANewIndex`。`AAllow := False` 就不做。`OnCollectionChanged` 在做完、行也重建好之后发。
- `OnCreateCollectionItem` 让应用自己建新项(特定的项类、初始值):在 `ACollection` 里建好,放进 `AItem`。不管它,表格就调 `ACollection.Add`。建好的项再由表格挪到该去的位置。

**宿主自己的数据跟着项走时,要交给宿主去做。** 表格只用 `TCollection` 自己的 `Add`、`Delete` 和 `Index`,集合的宿主未必知道该连带搬什么。字符串表格就是这样:单元格按列的下标存,经集合删掉一列,后面的列会显示被删那列的数据;移动一列,表头动了、数据没动。所以示例里在 `OnCollectionChanging` 里拒绝,改调表格自己的方法,它们会把单元格一起搬:

```pascal
procedure TMainForm.GridCollectionChanging(Sender: TObject; ACollection: TCollection;
  AAction: TTyCollectionAction; AIndex, ANewIndex: Integer; var AAllow: Boolean);
begin
  if ACollection <> StringGrid1.Header.Columns then Exit;
  AAllow := False;
  case AAction of
    caAdd:    StringGrid1.InsertColumn(ANewIndex);
    caDelete: StringGrid1.DeleteColumn(AIndex);
    caMove:   StringGrid1.MoveColumn(AIndex, ANewIndex);   // 改的是显示位置,下标不变
  end;
  Grid.Refresh;
end;
```

在处理程序里调 `Refresh`(或者别的会重建行的操作)是安全的,表格发现行重建了就不再往下做。

---

## 9. 分类

`ShowCategories := True` 之后,顶层属性按分类分组,每组上面一个标题行。标题行不能编辑,没有值,也没有中间的分隔线,点三角或者按 Enter 展开、收起。组内仍按 `PropertyOrder` 排。

内置分类按属性名归:

| 分类 | 属性 |
|---|---|
| 布局 Layout | `Left`、`Top`、`Width`、`Height`、`Align`、`Anchors`、`AutoSize`、`BorderSpacing`、`Constraints`、`ChildSizing` |
| 外观 Appearance | `Color`、`Font`、`Caption`、`Text`、`Visible`、`StyleClass`、`StyleOverride`、`Images`、`ImageIndex`、`Cursor`、`ParentColor`、`ParentFont` |
| 行为 Behavior | `Enabled`、`ReadOnly`、`TabStop`、`TabOrder`、`Hint`、`ShowHint`、`PopupMenu`、`Action` |
| 事件 Events | 所有事件(要先让 `TypeFilter` 显示事件) |
| 其他 Other | 剩下的 |

分类名是 resourcestring(`rsTyPropGridCatLayout` 等),跟着程序的语言走;`TyPropertyGridCategoryOf(名字, 种类)` 返回内置的归类。

```pascal
OnGetPropertyCategory(Sender; AInstance: TPersistent; const APropName: string; var ACategory: string)
```

- `ACategory` 进来是内置的分类,可以改成别的,也可以起一个新名字。设成空字符串就归「其他」。
- 分组的顺序:布局、外观、行为、事件,然后是应用自己起的(按名字排),「其他」永远在最后。一个属性都没有的分类不出现。
- 只有顶层属性分类,子属性(`Font.Size`)跟着它的父行走,也不会为它问这个事件。
- 选了多个对象时,按第一个对象来问。

```pascal
procedure TMainForm.GridGetPropertyCategory(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var ACategory: string);
begin
  if (APropName = 'DataSource') or (APropName = 'DataField') then ACategory := '数据';
end;
```

标题行的展开状态也记在 `ExpandedProperties` 里,写成 `@` 加分类名(`@Layout`,和属性路径不会撞)。一个分类第一次出现时是展开的,它的路径会自动加进去;之后用户收起它,就一直是收起的,换对象、关了分类再打开都一样。想让某个分类一开始就收起,在设了 `ShowCategories` 之后从 `ExpandedProperties` 里删掉它。注意这里存的是显示出来的分类名,换了界面语言,名字也跟着变。

属性的路径不含分类:`Font.Size` 在分类视图里还是 `Font.Size`,`PropertyAt`、`RowPath`、集合的那几个方法都不受影响。

---

## 10. 按名字过滤

```pascal
procedure TMainForm.FilterEditChange(Sender: TObject);
begin
  Grid.FilterText := FilterEdit.Text;
end;
```

- 只显示名字里含这段文字的属性,不区分大小写;空字符串(或者只有空格)就是不过滤。
- 子属性也算:搜 `size`,`Font` 会跟着显示并自动展开,让 `Font.Size` 看得见;集合的元素(`fsBold`)、集合项里的属性同样如此。
- 一行自己的名字匹配时,它下面的行都保留(只是不自动展开):搜 `font`,展开 `Font` 还能看到它的全部子属性。
- 开着分类时,只显示有匹配的分类,标题行也自动展开。
- **清空之后恢复原来的展开状态。** 开始过滤时表格记下当时的 `ExpandedProperties`,清空时原样放回。过滤期间手动展开、收起的行,清空后不保留。
- 和 `OnFilterProperty` 同时生效:先问事件,事件留下的再按文字过滤。
- 被过滤掉的行只是藏起来,对象、值、展开状态都还在;当前行如果还看得见,清空前后都保持不变。

表格里不内置搜索框:一个自绘控件里嵌编辑框,要牵扯焦点、Tab 顺序和主题,而且只要一个表格的场合会凭空多出一块。放一个 `TTyEdit`,在 `OnChange` 里设 `FilterText`,就是上面那几行。

---

## 11. 注意事项

- **行是表格的。** 值列表编辑器的 `AddRow`、`DeleteRow`、`Clear` 还能调到,但别用:表格不认识自己没生成的行,下次重建时它们也会消失。
- **非组件对象要先清空再释放。** 组件被释放时,表格经 `FreeNotification` 自动清空(多选时只去掉它);普通的 `TPersistent` 没有这个机制,释放之前请先 `SelectedObject := nil`。
- **对象被代码改了要 `Refresh`。** 表格只在自己写回之后重读,别处改了对象它不知道。
- **控件会自己维护一些属性。** 有的控件会按自己的规则重设某些属性,比如 `TTyButton` 总是把 `Constraints.MinWidth` 维持在内容宽度,你写进去的值可能马上被它改掉。这不是没写进去:调一次 `Refresh` 就能看到控件现在的真实值。
- **设计期只看不改。** 在窗体设计器里,设了 `SelectedComponent` 的表格照样列出行,方便看效果,但不能编辑,也不能增删集合项:设计器拦着鼠标,而且绕过设计器去改被设计的组件,设计器不会知道。
- **浮点数用 `.`。** 不管系统区域设置是什么,浮点属性都显示和解析成 `1.5`;德语系统上也不是 `1,5`。日期时间则相反,按本机格式。
- **没挂 `OnPropertyError` 时会抛异常。** 用户输错值,应用会弹出 LCL 的错误框。想安静地处理(比如在状态栏提示),就挂上这个事件。

---

## 12. 内置的和应用自己加的

内置只管常见情况。没内置的,应用都能自己加上,不用改控件:

| 没内置的 | 应用怎么加 |
|---|---|
| 按名字以外的条件筛属性 | `OnFilterProperty` |
| 表格不认识的类型(接口、变体、不是 `TPersistent` 的类) | `OnFilterProperty` 放行 + `OnGetPropertyText` 给文字;要能改再挂 `OnSetPropertyText` |
| 换一种显示或解析的写法(颜色写成 `#RRGGBB`、`TPicture` 当文件名) | `OnGetPropertyText` / `OnSetPropertyText` |
| 换编辑器种类、选项、样式,或者设成只读 | `OnGetPropertyRow` |
| 自己的对话框 | `OnGetPropertyRow` 设成 `vekDialog` + `OnEditProperty` |
| 跨窗体选组件、限制可选的组件 | `OnGetComponentNames` |
| 写之前确认、校验,写之后联动 | `OnPropertyChanging` / `OnPropertyChanged` / `OnPropertyError` |
| 集合项:确认删除、交给宿主自己的方法去做 | `OnCollectionChanging` / `OnCollectionChanged` |
| 新建特定类的集合项、给初始值 | `OnCreateCollectionItem` |
| 自己的右键菜单 | 设 `PopupMenu`,用 `SelectedRow`、`RowPath`、`PropertyAt` 和 `AddCollectionItem` / `DeleteCollectionItem` / `MoveCollectionItem` |
| 自己的分类 | `OnGetPropertyCategory` |
| 搜索框 | 一个 `TTyEdit`,`OnChange` 里设 `FilterText` |
| 某种类型整行换一种做法,做成可复用的控件 | 派生 `TTyCustomPropertyGrid`,覆盖 `BuildPropertyRow`、`GetPropertyText`、`SetPropertyText` |

---

## 13. 和 LCL `TTIPropertyGrid` 的区别

| | `TTIPropertyGrid`(RTTIGrids) | `TTyPropertyGrid` |
|---|---|---|
| 依赖 | IDEIntf 的 `PropEdits`、对象查看器的代码 | 只用 RTL 的 `TypInfo`,在主包里 |
| 检查的对象 | `TIObject: TPersistent`;多个对象经底层的 `Selection` | `SelectedObject`(public)+ `SelectedComponent`(published,对象查看器里是组件下拉);多个对象用 `SelectObjects` |
| 种类过滤 | `Filter`,默认 `AllTypeKinds`,事件也显示 | `TypeFilter`,默认不显示事件(运行时没有代码可挂,显示了也只能看) |
| 按名字过滤 | 没有;`OnEditorFilter` 按属性编辑器筛 | `FilterText`,子属性命中时父行自动展开;另有 `OnFilterProperty` |
| 分类 | 没有 | `ShowCategories`,可用 `OnGetPropertyCategory` 改归类、加新分类 |
| 排序 | 按名字 | 默认按名字,`PropertyOrder = poDeclared` 可按声明顺序 |
| 展开状态 | `ExpandedProperties`,点号路径 | 同样是点号路径,切换对象时保留;分类标题写成 `@Layout` |
| 编辑器 | IDE 的属性编辑器类,可注册新的 | 固定一套常用的;要换就用事件(§12),或者派生覆盖 `BuildPropertyRow` |
| 不认识的类型 | 看有没有注册属性编辑器 | `OnGetPropertyText` / `OnSetPropertyText` |
| 改动通知 | `OnModified` | `OnPropertyChanging`(可拒绝)、`OnPropertyChanged`、`OnPropertyError` |
| 集合 | 弹出集合编辑器,在那个窗口里增删、排序 | 就地展开,每一项的属性直接改;增删、排序用右键菜单、快捷键或公开方法,`OnCollectionChanging` 可拒绝 |
| 布尔 | 可选复选框(`CheckboxForBoolean`) | 下拉,或按空格切换 |
| 外观 | 原生控件 | 自绘,跟随主题 |

---

## 14. 以后再说

下面这些还没做,记在 [#65](https://github.com/ACTom/TyControls/issues/65):

- 选了多个对象时的集合:现在只显示 `(…)`,不展开,不能增删。
- 布尔行画成复选框(LCL 的 `CheckboxForBoolean`)。
