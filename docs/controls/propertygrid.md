# TTyPropertyGrid

## 1. 概述

TTyPropertyGrid 是属性表格:把一个对象交给它,它就列出这个对象的 published 属性,每种类型配好编辑器,用户改完直接写回对象。做设置面板、调试面板、简易的界面编辑器都用得上。

```pascal
uses tyControls.PropertyGrid;

PropGrid.SelectedObject := Button1;   // 列出 Button1 的属性,改了就写回 Button1
```

它建在 [TTyValueListEditor](valuelisteditor.md) 上,外观、键盘操作、两列布局和可拖的分隔条都和值列表编辑器一样。不同的是行由表格自己生成:从对象的 RTTI 读出来,写回也走 RTTI。只用 RTL 的 `TypInfo`,不依赖 IDE 的 `PropEdits`,所以就在主包 `tycontrols` 里,运行时程序直接能用。

完整演示见 [examples/propertygrid](../../examples/propertygrid/):左边几个控件,点哪个右边就检查哪个;顶部有「显示事件」开关和一个用 `OnFilterProperty` 实现的过滤框。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|---|---|
| 单元 | `tyControls.PropertyGrid` |
| 类型 | `TTyPropertyGrid`(只负责发布)、`TTyCustomPropertyGrid`(全部实现,派生用它) |
| 面板 | `TyControls Lists`,紧跟在 `TTyValueListEditor` 后面 |
| `GetStyleTypeKey` | `'TyPropertyGrid'`,经类型键链回退到 `'TyValueListEditor'` |

内置主题都没有给 `TyPropertyGrid` 写规则,所以它和值列表编辑器长得一模一样。想单独给属性表格换个样子,在主题里写 `TyPropertyGrid { ... }` 就行,不会影响值列表编辑器。行、键列、值列、分隔线、展开三角用的仍是值列表编辑器那几个部件键(`TyValueListEditorRow`、`TyValueListEditorKey` 等,见[它的文档](valuelisteditor.md#2-单元与-typekey))。

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
| `TCollection`(表格的列、状态栏的面板) | 显示 `(3 items)`;每一项一行,显示项的 `DisplayName`,再展开就是这一项的属性 |
| 组件引用(`PopupMenu`、`Images`、`ActiveControl`……) | 下拉,第一项是 `(none)`,后面是候选组件的名字(见 §5.4) |
| `TStrings` | `…` 打开一个多行文本对话框,每行一项 |
| 事件 | 默认不显示;`TypeFilter` 加上 `tkMethod` 后显示处理程序的名字,只读 |
| 接口、变体、记录、超过 32 个元素的集合 | 不显示 |

没有 setter 的属性一律只读。类属性没有 setter 也照样展开,因为子对象自己的属性往往可写(`Font`、`Constraints` 都是这样)。子对象的展开有深度上限(默认 6 层,`PropertyRows.MaxDepth`),防止两个对象互相引用时无限展开。

---

## 4. 关键成员

| 成员 | 说明 |
|---|---|
| `SelectedObject: TPersistent` | 要检查的对象,任何 `TPersistent` 都行。public,运行时用 |
| `SelectedComponent: TComponent` | 和 `SelectedObject` 是同一个字段:当前对象是组件就返回它,否则返回 nil;写它就是写 `SelectedObject`。这个是 published 的,在对象查看器里选一个组件,窗体一载入表格就显示它,设置面板一行代码都不用写 |
| `Rebuild` | 按 `SelectedObject` 重新生成所有行。展开的行和当前行(按属性路径)都会保留 |
| `Refresh` | 只重读每一行的值,不重建。对象被代码改过之后调它。如果对象的结构变了(集合多了一项、子对象从无到有),它会自动重建,同样保留展开状态和当前行 |
| `PropertyAt(ARow, out AInstance, out APropName): Boolean` | 这一行改的是哪个对象的哪个属性。集合元素那一行返回整个集合属性;集合项本身那一行、以及不是表格生成的行返回 False |
| `PropertyOrder` | `poAlphabetical`(默认,和对象查看器一样按名字排序,不区分大小写)或 `poDeclared`(按类里声明的顺序,祖先的在前) |
| `TypeFilter: TTypeKinds` | 显示哪些种类的属性。默认是除 `tkMethod` 以外的全部,也就是不显示事件 |
| `HiddenProperties: TStrings` | 不显示的属性,写名字(`Tag`)或者点号路径(`Font.Height`) |
| `ExpandedProperties: TStrings` | 展开着的行的路径:`Font`、`Font.Style`、`Header.Columns[0]`。切换到另一个对象时保留,所以在一个按钮上展开了 `Font`,换到下一个按钮也是展开的;往里加一条路径,对应的行马上展开 |
| `ReadOnly` | 整个表格只读 |
| `KeyColumnWidth` | 属性名那一列的宽度(逻辑像素,可以拖) |
| `PropertyRows` | 背后的对象→行映射(`TTyPropertyRows`),一般用不到;`MaxDepth` 在这里 |
| `KeyOptions` | 固定为 `[]`:属性名不能改,行不能增删 |

改 `PropertyOrder`、`TypeFilter`、`HiddenProperties` 会马上重建。`OnFilterProperty` 是生成行的时候问的,过滤条件变了要自己调一次 `Rebuild`。

---

## 5. 事件与扩展点

内置的只是常用的那部分,其余的交给事件。

### 5.1 过滤:`OnFilterProperty`

```pascal
procedure (Sender: TObject; AInstance: TPersistent; const APropName: string; var AShow: Boolean)
```

每个属性生成行之前问一次,`AShow := False` 就不显示。子对象的属性也会问,这时 `AInstance` 是子对象(比如 `Font`)。示例里的过滤框只过滤控件自己的属性:

```pascal
procedure TMainForm.GridFilterProperty(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var AShow: Boolean);
begin
  if AInstance <> Grid.SelectedObject then Exit;   // Font.Size 这类子属性不过滤
  if FilterEdit.Text <> '' then
    AShow := Pos(LowerCase(FilterEdit.Text), LowerCase(APropName)) > 0;
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

一个属性的 setter 常常会顺带改别的属性(`AutoSize` 改 `Width`、`Constraints` 改尺寸),所以每次写回之后,表格会把同一对象的其他行全部重读一遍。

### 5.3 改造行:`OnGetPropertyRow`

```pascal
procedure (Sender: TObject; AInstance: TPersistent; APropInfo: PPropInfo; ARow: TTyValueRow)
```

每个属性的行建好之后调用一次(集合的元素行、集合项那一行不调)。可以改 `ARow.EditorKind`、`EnumValues`、`DisplayValue`、样式(`Bold`、`TextColor`、`ImageIndex`),或者把行设成只读。例如把某个字符串属性换成对话框编辑:

```pascal
if APropInfo^.Name = 'FileName' then ARow.EditorKind := vekDialog;
```

### 5.4 组件引用的候选:`OnGetComponentNames`

组件引用那一行的下拉,默认列出「候选根」名下、类型兼容的组件:

- 检查的对象是窗体、数据模块或框架(`TCustomForm`、`TDataModule`、`TCustomFrame`)时,候选根就是它自己。检查一个窗体,它的 `ActiveControl` 就能从窗体上的控件里选。
- 其他组件的候选根是它的 `Owner`,一般就是它所在的窗体。
- 候选根自己类型兼容的话也列进去。
- 当前值不在清单里时也会补上,不然看起来像是选了别的。

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

---

## 6. 交互

- 点值列开始编辑:文本和数字直接输入,布尔、枚举、颜色、组件引用是下拉,字体和对话框行点尾部的 `…`。选中一行按 **F2** 或 **Enter** 也行。
- **Enter** 提交,**Esc** 放弃,点到别处也算提交。
- 选中布尔行(包括集合的元素行)按**空格**直接切换。
- 点属性名前面的三角展开或收起。

---

## 7. 注意事项

- **行是表格的。** 值列表编辑器的 `AddRow`、`DeleteRow`、`Clear` 还能调到,但别用:表格不认识自己没生成的行,下次重建时它们也会消失。
- **非组件对象要先清空再释放。** 组件被释放时,表格经 `FreeNotification` 自动清空;普通的 `TPersistent` 没有这个机制,释放之前请先 `SelectedObject := nil`。
- **对象被代码改了要 `Refresh`。** 表格只在自己写回之后重读,别处改了对象它不知道。
- **控件会自己维护一些属性。** 有的控件会按自己的规则重设某些属性,比如 `TTyButton` 总是把 `Constraints.MinWidth` 维持在内容宽度,你写进去的值可能马上被它改掉。这不是没写进去:调一次 `Refresh` 就能看到控件现在的真实值。
- **设计期只看不改。** 在窗体设计器里,设了 `SelectedComponent` 的表格照样列出行,方便看效果,但不能编辑:设计器拦着鼠标,而且绕过设计器去改被设计的组件,设计器不会知道。
- **浮点数用 `.`。** 不管系统区域设置是什么,浮点属性都显示和解析成 `1.5`;德语系统上也不是 `1,5`。日期时间则相反,按本机格式。
- **没挂 `OnPropertyError` 时会抛异常。** 用户输错值,应用会弹出 LCL 的错误框。想安静地处理(比如在状态栏提示),就挂上这个事件。

---

## 8. 和 LCL `TTIPropertyGrid` 的区别

| | `TTIPropertyGrid`(RTTIGrids) | `TTyPropertyGrid` |
|---|---|---|
| 依赖 | IDEIntf 的 `PropEdits`、对象查看器的代码 | 只用 RTL 的 `TypInfo`,在主包里 |
| 检查的对象 | `TIObject: TPersistent` | `SelectedObject`(public)+ `SelectedComponent`(published,对象查看器里是组件下拉) |
| 种类过滤 | `Filter`,默认 `AllTypeKinds`,事件也显示 | `TypeFilter`,默认不显示事件(运行时没有代码可挂,显示了也只能看) |
| 排序 | 按名字 | 默认按名字,`PropertyOrder = poDeclared` 可按声明顺序 |
| 展开状态 | `ExpandedProperties`,点号路径 | 同样是点号路径,切换对象时保留 |
| 编辑器 | IDE 的属性编辑器类,可注册新的 | 固定一套常用的;要换就用 `OnGetPropertyRow`、`OnEditProperty` |
| 改动通知 | `OnModified` | `OnPropertyChanging`(可拒绝)、`OnPropertyChanged`、`OnPropertyError` |
| 集合 | 弹出集合编辑器 | 就地展开,每一项的属性直接改(增删项见第二期) |
| 布尔 | 可选复选框(`CheckboxForBoolean`) | 下拉,或按空格切换 |
| 外观 | 原生控件 | 自绘,跟随主题 |

---

## 9. 第二期

下面这些不在第一期里,记在 [#65](https://github.com/ACTom/TyControls/issues/65):

- 同时检查多个对象:只显示共同的属性,改一处写回全部。
- 集合项的增加、删除和调整顺序。
- 属性分类和分组。
- 表格自带的搜索框(现在用 `OnFilterProperty` 自己做)。
