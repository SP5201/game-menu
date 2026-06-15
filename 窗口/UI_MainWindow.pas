unit UI_MainWindow;

interface

uses
  Windows, Messages, SysUtils, Classes, XCGUI, UI_Form, UI_Button,
  UI_ListBox, UI_ListView, UI_SidebarGrip, UI_MessageBox, UI_SearchBox,
  UI_EditItemDialog, UI_CategoryDialog, UI_PopupMenu, LibraryStore, ListItemTypes,
  DiskSearch, Core.Model, EverythingIndex, ShellIconLoader;

type
  TMainFormUI = class(TFormUI)
  private
    class var
      { 左侧分类列表 }
      CListBoxUI: TListBoxUI;
      { 右侧应用条目列表 }
      CListViewUI: TListViewUI;
      { 列表框项索引 → 数据库分组 GroupIndex }
      CGroupMap: array of Integer;
      { 列表框项索引 → 分类图标文件名 }
      CGroupIconMap: array of string;
      { 本地库持久化（分组与条目） }
      CStore: TLibraryStore;
      { 全库搜索结果的排序方式（不写数据库） }
      CSearchListSortKind: TLibraryListSortKind;
      CSearchListAsc: Boolean;
      CSearchBox: TSearchBoxUI;
      CSearchGeneration: Cardinal;
      CSearchLogGeneration: Cardinal;
      CSearchSortThread: TThread;
      CMainHWINDOW: HWINDOW;
      CShapeSearchIndexStatus: HELE;
      CLastSearchIndexStatusText: string;
      CLastSearchIndexBuilding: Boolean;
      { 列表筛选：完整数据集与当前选中分类（0=全部） }
      CListFilterSourceItems: TListViewFileItemArray;
      CListFilterIndex: Integer;
      { 全盘搜索命中下标（搜索视图专用，不预拼路径） }
      CSearchHitIndices: TEverythingHitArray;
      { 右侧列表当前上下文：-1=全盘搜索视图，>=0=库分组 GroupIndex }
      CActiveListGroupIndex: Integer;
      { 程序同步选中「搜索」项时不重复加载列表 }
      CSuppressCategorySelectReload: Boolean;
    { 从数据库加载分类到左侧列表框 }
    class procedure LoadListBoxFromStore;
    { 按指定分组索引加载右侧列表项（含排序与图标） }
    class procedure LoadListViewFromStore(const AGroupIndex: Integer);
    { 全盘搜索，结果填入右侧列表 }
    class procedure SearchUiDebug(const ASummary: string; const ADetail: string = ''); static;
    class procedure RequestDiskSearch(const ANeedle: string; AEnableLog: Boolean = False);
    class procedure PerformDiskSearchFromBox(AEnableLog: Boolean = True);
    class procedure ScheduleDebouncedDiskSearch;
    class function OnSearchDebounceTimer(hWindow: XCGUI.HWINDOW; nIDEvent: UINT; pbHandled: PBOOL): Integer; stdcall; static;
    class procedure ApplyIndexHitChanges(const AData: PIndexHitChangesMsg);
    class procedure RefreshSearchIndexStatusLabel;
    class procedure StartSearchIndexStatusTimer;
    class procedure ApplyDiskSearchResults(const AData: PDiskSearchResult);
    class procedure ApplySearchSortDone(const AData: PSearchSortDoneMsg);
    class procedure ScheduleSearchHitSort(AGeneration: Cardinal);
    class procedure StopSearchHitSortThread;
    class procedure ApplyListIconLoadResult(AData: PShellIconLoadResult);
    class procedure HandleDiskSearchError(const AData: PDiskSearchErrorMsg);
    class procedure ShowDiskSearchError(const AError: TDiskSearchError);
    class procedure BridgeDiskSearchResult(AData: PDiskSearchResult); static;
    class procedure BridgeDiskSearchError(AData: PDiskSearchErrorMsg); static;
    { 从 Win32 队列取出尚未分发的搜索结果 }
    class procedure DrainPendingDiskSearchMessages;
    { 内部：切换分类并加载列表（不经过事件 pbHandled） }
    class procedure ReloadListForCategoryIndex(const iItem: Integer);
    class procedure SelectSearchCategoryItem;
    { 数据库增改分组成功后，从库重载左侧列表并选中指定 group_index }
    class procedure ReloadCategoriesAndSelectGroup(const AGroupIndex: Integer);
    { 拖放前若尚无分类则补一条默认分类并选中 }
    class procedure SyncCategoriesForDrop;
    { 左侧分类切换：保存宽度、加载对应分组条目 }
    class function OnCategorySelect(hEle: XCGUI.HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    { 分类列表右键菜单：增删改分类、设置项等 }
    class function OnCategoryMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    { 主内容列表右键菜单：打开、编辑、删除、添加文件/夹等 }
    class function OnContentMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    { 窗口 WM_DROPFILES：批量拖入文件到当前分组 }
    class function OnWndDropFiles(hWindow: XCGUI.HWINDOW; hDrop: XCGUI.HDROP; pbHandled: PBOOL): Integer; stdcall; static;
    { 主窗口附加消息（WM_QD_STAT_*、关闭前释放模态栈等） }
    class function OnWinProc(hWindow: XCGUI.HWINDOW; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    { 批量插入数据库并刷新列表中已成功的项 }
    class procedure InsertBatchItemsToUI(const AGroupIndex: Integer; const AUIItems: array of TListViewFileItem; const ADBItems: TLibraryItemArray); static;
    { 排序按钮：弹出排序方式菜单 }
    class function OnListSortButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    { 列表布局按钮：打开间距/圆角/滚动条设置对话框 }
    class function OnListLayoutButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    { 安全日志按钮：打开 SafeLog 窗口 }
    class function OnSafeLogButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    { 排序菜单选择：写回数据库或仅重排当前搜索结果 }
    class function OnListSortMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    { 搜索按钮：按编辑框关键字全库搜索；空则显示全部索引文件 }
    class function OnMainSearchButtonClick(Sender: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    { TLibraryListSortKind → TListViewUI.SortItems }
    class procedure ApplyListSort(const AKind: TLibraryListSortKind; const AAsc: Boolean); static;
    { 分组增删：写日志（概要不含分组 ID，详情含分组 ID） }
    class procedure LogGroupDbOp(const AAction, AGroupName: string; ASuccess: Boolean; AGroupIndex: Integer); static;
    { 按当前列表条目刷新筛选按钮文案（标签 + 数量） }
    class procedure RefreshListFilterButtonCounts; static;
    class procedure SetListFilterSource(const AItems: array of TListViewFileItem; AResetFilter: Boolean); static;
    class procedure SyncListFilterSourceFromView; static;
    class procedure ApplyListFilterToView; static;
    class procedure ApplySearchHitsToViewPreserveScroll; static;
    class procedure UpdateListFilterButtonStyles; static;
    class procedure SelectListFilter(const AIndex: Integer); static;
    class procedure RemoveListFilterSourceItem(const AFilePath: string); static;
    class procedure UpdateListFilterSourceItem(const AFilePath: string; const AItem: TListViewFileItem); static;
    class function OnListFilterButtonClick(hSender: HELE; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    destructor Destroy; override;
    { 从布局 XML 创建主窗体实例 }
    class function LoadLayout(const LayoutFile: PWideChar): TMainFormUI; reintroduce;
  end;


function ListViewItemToLibraryItem(const AItem: TListViewFileItem): TLibraryItem;
function LibraryItemToListViewItem(const AItem: TLibraryItem; const AIndex, AGroupIndex: Integer): TListViewFileItem;
procedure InvalidateListViewItemIcon(var AItem: TListViewFileItem; const APreviousIconPath: string = '');
procedure MainWindowListViewPrepareContextMenu(ASender: TListViewUI; AMenu: TPopupMenuUI; AItemIndex: Integer;
  const AFilePath: string);
procedure MainWindowListViewItemActivate(ASender: TListViewUI; AItemIndex: Integer);
procedure MainWindowListViewItemWidthChanged(ASender: TListViewUI; AWidth: Integer);
procedure ApplyListViewLayoutFromConfig(AListView: TListViewUI);
function NormalizeCategoryIconFile(const AIconFile: string): string;
procedure ApplyDefaultStyles(hXCGUI: hXCGUI);
procedure ClampWindowBoundsToWorkArea(var ALeft, ATop, AWidth, AHeight: Integer);
procedure RestoreMainWindowBounds(AWnd: HWINDOW);
procedure SaveMainWindowBounds(AWnd: HWINDOW);

implementation

uses
  Math, StrUtils, ShellAPI, AppConfig, AppPaths, ShellHelper, ShellOpenWith, WeatherFetcher,
  UI_MainWindowTools, UI_MainWindowStat, UI_Theme,
  UI_ListViewSettingsDialog, NetHttpWorker, UI_SafeLogWindow, SafeLog, UI_HintPopup, UI_ScrollBar,
  ShlObj, ActiveX, PawnIoClient;

const
  ID_LISTVIEW_MENU_OPEN = 101;
  ID_LISTVIEW_MENU_EDIT = 102;
  ID_LISTVIEW_MENU_DELETE = 103;
  ID_LISTVIEW_MENU_OPEN_FOLDER = 104;
  ID_LISTVIEW_MENU_ADD_FILE = 105;
  ID_LISTVIEW_MENU_ADD_FOLDER = 106;
  ID_LISTVIEW_MENU_RUN_AS_ADMIN = 107;
  ID_MAIN_LIST_SORT_ASC = 801;
  ID_MAIN_LIST_SORT_DESC = 802;
  ID_MAIN_LIST_SORT_BY_NAME = 803;
  ID_MAIN_LIST_SORT_BY_TIME = 804;
  ID_MAIN_LIST_SORT_BY_FILETYPE = 805;
  cMainSearchDebounceTimerId = 901;
  cMainSearchDebounceMs = 20;
  cMainIndexStatusTimerId = 902;
  cMainIndexStatusTimerMs = 500;
  cCategorySearchListIndex = 0;
  cCategorySearchTitle = '搜索';
  cListFilterCount = 9;
  cListFilterFolderIndex = 6;
  cListFilterArchiveIndex = 7;
  cListFilterOtherIndex = cListFilterCount - 1;
  cListFilterAppExts = ';exe;msi;bat;cmd;com;scr;lnk;msc;msix;appx;appxbundle;ps1;vbs;jar;';
  cListFilterDocExts = ';doc;docx;pdf;txt;xls;xlsx;ppt;pptx;rtf;odt;ods;odp;wps;md;csv;';
  cListFilterImageExts = ';jpg;jpeg;png;gif;bmp;webp;ico;tif;tiff;psd;heic;svg;';
  cListFilterVideoExts = ';mp4;mkv;avi;mov;wmv;flv;webm;m4v;mpeg;mpg;ts;3gp;rmvb;';
  cListFilterAudioExts = ';mp3;wav;flac;aac;ogg;wma;m4a;ape;aiff;';
  cListFilterArchiveExts = ';zip;rar;7z;tar;gz;bz2;xz;iso;cab;';
  cListFilterBtnNames: array[0..cListFilterCount - 1] of PChar = (
    'btn_main_filter_all', 'btn_main_filter_app', 'btn_main_filter_doc',
    'btn_main_filter_image', 'btn_main_filter_video', 'btn_main_filter_audio',
    'btn_main_filter_folder', 'btn_main_filter_archive', 'btn_main_filter_other');
  cListFilterLabels: array[0..cListFilterCount - 1] of PChar = (
    '全部', '应用程序', '文档', '图片', '视频', '音频', '文件夹', '压缩包', '其他');
  cListFilterExtSets: array[0..cListFilterCount - 1] of PChar = (
    nil, cListFilterAppExts, cListFilterDocExts, cListFilterImageExts,
    cListFilterVideoExts, cListFilterAudioExts, nil, cListFilterArchiveExts, nil);

var
  GExtIdToFilterKind: TExtFilterKindMap;
  GExtIdToFilterKindBuiltFor: Integer;

type
  TSearchHitSortThread = class(TThread)
  private
    FGeneration: Cardinal;
    FSortKind: TLibraryListSortKind;
    FSortAsc: Boolean;
    FSourceIndices: TEverythingHitArray;
    FMainWindow: HWINDOW;
  protected
    procedure Execute; override;
  public
    constructor Create(AMainWindow: HWINDOW; AGeneration: Cardinal;
      const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean;
      const ASourceIndices: TEverythingHitArray);
  end;

function ListFilterExtInSet(const AExt, ASet: string): Boolean;
var
  ext: string;
begin
  ext := LowerCase(Trim(AExt));
  if (ext <> '') and (ext[1] = '.') then
    Delete(ext, 1, 1);
  Result := (ext <> '') and (Pos(';' + ext + ';', ASet) > 0);
end;

procedure ListFilterEnsureExtIdMap;
var
  extCount, extId, kind, i: Integer;
  extName: string;
begin
  if not EverythingIndexIsReady then
    Exit;
  extCount := EverythingIndexGetExtCount;
  if (extCount = GExtIdToFilterKindBuiltFor) and (Length(GExtIdToFilterKind) > 0) then
    Exit;
  SetLength(GExtIdToFilterKind, extCount + 1);
  GExtIdToFilterKindBuiltFor := extCount;
  for extId := 1 to extCount do
  begin
    extName := LowerCase(EverythingIndexGetExtNameById(Word(extId)));
    kind := cListFilterOtherIndex;
    for i := 1 to cListFilterOtherIndex - 1 do
    begin
      if i = cListFilterFolderIndex then
        Continue;
      if (cListFilterExtSets[i] <> nil) and ListFilterExtInSet(extName, string(cListFilterExtSets[i])) then
      begin
        kind := i;
        Break;
      end;
    end;
    GExtIdToFilterKind[extId] := Byte(kind);
  end;
end;

constructor TSearchHitSortThread.Create(AMainWindow: HWINDOW; AGeneration: Cardinal;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean;
  const ASourceIndices: TEverythingHitArray);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FMainWindow := AMainWindow;
  FGeneration := AGeneration;
  FSortKind := ASortKind;
  FSortAsc := ASortAsc;
  FSourceIndices := ASourceIndices;
end;

procedure TSearchHitSortThread.Execute;
var
  sorted: TEverythingHitArray;
  sortStart: Cardinal;
  doneMsg: PSearchSortDoneMsg;
  hRealWnd: Windows.HWND;
begin
  try
    if Terminated or (FGeneration <> TMainFormUI.CSearchGeneration) then
      Exit;
    SetLength(sorted, Length(FSourceIndices));
    if Length(FSourceIndices) > 0 then
      Move(FSourceIndices[0], sorted[0], Length(FSourceIndices) * SizeOf(Integer));
    sortStart := GetTickCount;
    EverythingIndexSortHitIndices(sorted, FSortKind, FSortAsc);
    if Terminated or (FGeneration <> TMainFormUI.CSearchGeneration) then
      Exit;
    New(doneMsg);
    doneMsg^.Generation := FGeneration;
    doneMsg^.SortMs := GetTickCount - sortStart;
    doneMsg^.HitIndices := sorted;
    hRealWnd := 0;
    if XC_GetObjectType(FMainWindow) = XC_WINDOW then
      hRealWnd := XWnd_GetHWND(FMainWindow);
    if hRealWnd <> 0 then
      PostMessageW(hRealWnd, WM_QD_DISK_SEARCH_SORT_DONE, 0, LPARAM(doneMsg))
    else
      DiskSearchDisposeSortDone(doneMsg);
  finally
    if TMainFormUI.CSearchSortThread = Self then
      TMainFormUI.CSearchSortThread := nil;
  end;
end;

function ListFilterExtFromPath(const APath: string): string;
begin
  Result := LowerCase(Trim(ExtractFileExt(APath)));
  if (Result <> '') and (Result[1] = '.') then
    Delete(Result, 1, 1);
end;

procedure ListFilterAssignSourceItem(var ADest: TListViewFileItem; const ASrc: TListViewFileItem);
begin
  ADest := ASrc;
  { 源缓存不持有 HIMAGE：图标由 ListView.FFileImages 单独管理 }
  ADest.FileImage := 0;
end;

function ListFilterHitKindIndex(AHitIndex: Integer): Integer;
begin
  ListFilterEnsureExtIdMap;
  Result := EverythingIndexGetHitFilterKind(AHitIndex, GExtIdToFilterKind,
    cListFilterFolderIndex, cListFilterOtherIndex);
end;

function ListFilterItemKindIndex(const APath: string): Integer;
var
  i: Integer;
  ext, extSet: string;
begin
  if (Length(APath) > 0) and CharInSet(APath[Length(APath)], ['\', '/']) then
    Exit(cListFilterFolderIndex);
  ext := ListFilterExtFromPath(APath);
  for i := 1 to cListFilterOtherIndex - 1 do
  begin
    if cListFilterExtSets[i] = nil then
      Continue;
    extSet := string(cListFilterExtSets[i]);
    if ListFilterExtInSet(ext, extSet) then
      Exit(i);
  end;
  Result := -1;
end;

procedure SetListFilterButtonCount(const AXmlName, ALabel: string; ACount: Integer);
var
  hBtn: HELE;
  caption: string;
begin
  hBtn := XC_GetObjectByName(PWideChar(AXmlName));
  if XC_GetObjectType(hBtn) <> XC_BUTTON then
    Exit;
  caption := Format('%s %d', [ALabel, ACount]);
  XBtn_SetText(hBtn, PWideChar(caption));
  XEle_AdjustLayoutEx(hBtn, adjustLayout_self);
end;

procedure SetListFilterButtonVisible(const AXmlName: string; AVisible: Boolean);
var
  hBtn: HELE;
begin
  hBtn := XC_GetObjectByName(PWideChar(AXmlName));
  if XC_GetObjectType(hBtn) <> XC_ERROR then
    XWidget_Show(hBtn, AVisible);
end;

procedure AdjustListFilterToolbarLayout;
var
  i: Integer;
  hBtn, hFilterLayout, hToolbar: HELE;
begin
  for i := 0 to cListFilterCount - 1 do
  begin
    hBtn := XC_GetObjectByName(cListFilterBtnNames[i]);
    if XC_GetObjectType(hBtn) <> XC_ERROR then
      XEle_AdjustLayoutEx(hBtn, adjustLayout_self);
  end;
  hFilterLayout := XC_GetObjectByName('layout_main_list_filter');
  if XC_GetObjectType(hFilterLayout) <> XC_ERROR then
    XEle_AdjustLayoutEx(hFilterLayout, adjustLayout_all);
  hToolbar := XC_GetObjectByName('layout_main_list_toolbar');
  if XC_GetObjectType(hToolbar) <> XC_ERROR then
  begin
    XEle_AdjustLayoutEx(hToolbar, adjustLayout_all);
    XEle_Redraw(hToolbar);
  end;
end;

procedure AdjustMainSearchAreaLayout;
var
  hSearchRow, hHeaderBar: HELE;
begin
  hSearchRow := XC_GetObjectByName('layout_main_search_row');
  if XC_GetObjectType(hSearchRow) <> XC_ERROR then
  begin
    XEle_AdjustLayoutEx(hSearchRow, adjustLayout_all);
    XEle_Redraw(hSearchRow);
  end;
  hHeaderBar := XC_GetObjectByName('layout_main_header_bar');
  if XC_GetObjectType(hHeaderBar) <> XC_ERROR then
    XEle_AdjustLayoutEx(hHeaderBar, adjustLayout_all);
end;

class procedure TMainFormUI.InsertBatchItemsToUI(const AGroupIndex: Integer; const AUIItems: array of TListViewFileItem; const ADBItems: TLibraryItemArray);
var
  insertedFlags: TLibraryInsertResultArray;
  insertedCount, i, n: Integer;
  batchItems: array of TListViewFileItem;
  data2: TListViewFileItem;
begin
  try
    insertedCount := CStore.TryInsertItemsBatch(AGroupIndex, ADBItems, insertedFlags);
  except
    on E: Exception do
    begin
      SafeLogRecord('批量', '插入', '批量插入失败，改为逐条插入: ' + E.Message, False);
      insertedCount := 0;
      SetLength(insertedFlags, Length(ADBItems));
      for i := 0 to High(ADBItems) do
      begin
        insertedFlags[i] := CStore.TryInsertItem(AGroupIndex, ADBItems[i].FilePath, ADBItems[i].FileName, ADBItems[i].IconCachePath,
          ADBItems[i].FileParams, ADBItems[i].WorkingDir, ADBItems[i].ShowCmd);
        if insertedFlags[i] then
          Inc(insertedCount)
        else
          SafeLogRecord('批量', '插入', '逐条插入失败: ' + ADBItems[i].FilePath, False);
      end;
    end;
  end;
  if insertedCount > 0 then
  begin
    n := 0;
    SetLength(batchItems, insertedCount);
    for i := 0 to High(AUIItems) do
      if (i < Length(insertedFlags)) and insertedFlags[i] then
      begin
        data2 := AUIItems[i];
        data2.ItemGroupIndex := AGroupIndex;
        batchItems[n] := data2;
        Inc(n);
      end;
    SetLength(batchItems, n);
    n := Length(CListFilterSourceItems);
    SetLength(CListFilterSourceItems, n + Length(batchItems));
    for i := 0 to High(batchItems) do
      ListFilterAssignSourceItem(CListFilterSourceItems[n + i], batchItems[i]);
    ApplyListFilterToView;
    CListViewUI.Redraw();
    RefreshListFilterButtonCounts;
  end;
end;

class procedure TMainFormUI.LogGroupDbOp(const AAction, AGroupName: string; ASuccess: Boolean; AGroupIndex: Integer);
var
  summary, detail, statusText: string;
begin
  if ASuccess then
    statusText := '成功'
  else
    statusText := '失败';
  summary := AAction + ' ' + AGroupName + statusText;
  detail := summary;
  if AGroupIndex >= 0 then
    detail := detail + sLineBreak + '分组ID' + IntToStr(AGroupIndex);
  SafeLogRecord('local', AAction, summary, ASuccess, detail);
end;

class procedure TMainFormUI.SyncCategoriesForDrop;
var
  groupIndex, sel: Integer;
  createOk: Boolean;
begin
  if Length(CGroupMap) > 0 then
    Exit;
  createOk := CStore.CreateGroup('默认', '', groupIndex);
  LogGroupDbOp('创建分组', '默认', createOk, groupIndex);
  if not createOk then
    Exit;
  LoadListBoxFromStore;
  sel := CListBoxUI.GetSelectItem;
  if sel > cCategorySearchListIndex then
    ReloadListForCategoryIndex(sel);
end;

class procedure TMainFormUI.ReloadCategoriesAndSelectGroup(const AGroupIndex: Integer);
var
  i, listIdx: Integer;
begin
  LoadListBoxFromStore;
  for i := 0 to High(CGroupMap) do
  begin
    if CGroupMap[i] = AGroupIndex then
    begin
      listIdx := i + 1;
      XListBox_SetSelectItem(CListBoxUI.Handle, listIdx);
      ReloadListForCategoryIndex(listIdx);
      Exit;
    end;
  end;
end;

class procedure TMainFormUI.LoadListBoxFromStore;
var
  groups: TLibraryGroupArray;
  i, idx: Integer;
  iconFile: string;
begin
  CListBoxUI.ClearItems;
  SetLength(CGroupMap, 0);
  SetLength(CGroupIconMap, 0);
  CListBoxUI.AddItem(cCategorySearchTitle, CDefaultSearchSvg);
  groups := CStore.LoadGroups;
  if Length(groups) = 0 then
  begin
    SyncCategoriesForDrop;
    Exit;
  end;

  SetLength(CGroupMap, Length(groups));
  SetLength(CGroupIconMap, Length(groups));
  for i := 0 to High(groups) do
  begin
    iconFile := NormalizeCategoryIconFile(groups[i].iconFile);
    idx := CListBoxUI.AddItem(groups[i].GroupName, iconFile);
    CGroupMap[idx - 1] := groups[i].GroupIndex;
    CGroupIconMap[idx - 1] := iconFile;
  end;
  if CListBoxUI.GetCount > cCategorySearchListIndex + 1 then
    XListBox_SetSelectItem(CListBoxUI.Handle, cCategorySearchListIndex + 1)
  else
    XListBox_SetSelectItem(CListBoxUI.Handle, cCategorySearchListIndex);
  XEle_Redraw(CListBoxUI.Handle);
end;

class procedure TMainFormUI.ApplyListSort(const AKind: TLibraryListSortKind; const AAsc: Boolean);
var
  savedFilter: Integer;
begin
  savedFilter := CListFilterIndex;
  if savedFilter <> 0 then
  begin
    CListFilterIndex := 0;
    ApplyListFilterToView;
  end;
  CListViewUI.SortItems(AKind, AAsc);
  SyncListFilterSourceFromView;
  CListFilterIndex := savedFilter;
  if savedFilter <> 0 then
    ApplyListFilterToView;
end;

class procedure TMainFormUI.LoadListViewFromStore(const AGroupIndex: Integer);
var
  items: TLibraryItemArray;
  uiItems: array of TListViewFileItem;
  i: Integer;
  listSortKind: TLibraryListSortKind;
  asc: Boolean;
begin
  SetLength(CSearchHitIndices, 0);
  CActiveListGroupIndex := AGroupIndex;
  items := CStore.LoadItemsByGroup(AGroupIndex);
  SetLength(uiItems, Length(items));
  for i := 0 to High(items) do
    uiItems[i] := LibraryItemToListViewItem(items[i], i, AGroupIndex);
  SetListFilterSource(uiItems, True);
  if AGroupIndex >= 0 then
  begin
    CStore.GetGroupListSort(AGroupIndex, listSortKind, asc);
    ApplyListSort(listSortKind, asc);
  end;
  CListViewUI.RefreshVisibleItems;
end;

class procedure TMainFormUI.SetListFilterSource(const AItems: array of TListViewFileItem; AResetFilter: Boolean);
var
  i: Integer;
begin
  SetLength(CListFilterSourceItems, Length(AItems));
  for i := 0 to High(AItems) do
    ListFilterAssignSourceItem(CListFilterSourceItems[i], AItems[i]);
  if AResetFilter then
  begin
    CListFilterIndex := 0;
    UpdateListFilterButtonStyles;
  end;
  ApplyListFilterToView;
  RefreshListFilterButtonCounts;
end;

class procedure TMainFormUI.SyncListFilterSourceFromView;
var
  i, n: Integer;
begin
  if CListViewUI = nil then
    Exit;
  n := CListViewUI.GetItemCount;
  SetLength(CListFilterSourceItems, n);
  for i := 0 to n - 1 do
  begin
    CListViewUI.TryGetItem(i, CListFilterSourceItems[i]);
    CListFilterSourceItems[i].FileImage := 0;
  end;
  CListViewUI.ResetRowMapIdentity;
end;

class procedure TMainFormUI.ApplySearchHitsToViewPreserveScroll;
var
  rowMap: TEverythingHitArray;
begin
  if CListViewUI = nil then
    Exit;
  if CActiveListGroupIndex <> -1 then
    Exit;
  if CListFilterIndex = 0 then
    SetLength(rowMap, 0)
  else
  begin
    ListFilterEnsureExtIdMap;
    EverythingIndexBuildSearchFilterRowMap(CSearchHitIndices, CListFilterIndex,
      cListFilterFolderIndex, cListFilterOtherIndex, GExtIdToFilterKind, rowMap);
  end;
  CListViewUI.RefreshSearchHits(CSearchHitIndices, rowMap);
end;

class procedure TMainFormUI.ApplyListFilterToView;
var
  i, n, m, kindIdx: Integer;
  rowMap: TEverythingHitArray;
begin
  if CListViewUI = nil then
    Exit;
  if CActiveListGroupIndex < 0 then
  begin
    if CListFilterIndex = 0 then
    begin
      SetLength(rowMap, 0);
      CListViewUI.BindSearchHits(CSearchHitIndices, rowMap, True);
      CListViewUI.RefreshVisibleItems;
      Exit;
    end;
    ListFilterEnsureExtIdMap;
    EverythingIndexBuildSearchFilterRowMap(CSearchHitIndices, CListFilterIndex,
      cListFilterFolderIndex, cListFilterOtherIndex, GExtIdToFilterKind, rowMap);
    CListViewUI.BindSearchHits(CSearchHitIndices, rowMap, True);
    CListViewUI.RefreshVisibleItems;
    Exit;
  end;
  n := Length(CListFilterSourceItems);
  if CListFilterIndex = 0 then
  begin
    SetLength(rowMap, 0);
    CListViewUI.BindItems(CListFilterSourceItems, rowMap, True);
    CListViewUI.RefreshVisibleItems;
    Exit;
  end;
  SetLength(rowMap, n);
  m := 0;
  for i := 0 to n - 1 do
  begin
    kindIdx := ListFilterItemKindIndex(CListFilterSourceItems[i].FilePath);
    if CListFilterIndex = cListFilterOtherIndex then
    begin
      if kindIdx < 0 then
      begin
        rowMap[m] := i;
        Inc(m);
      end;
    end
    else if kindIdx = CListFilterIndex then
    begin
      rowMap[m] := i;
      Inc(m);
    end;
  end;
  SetLength(rowMap, m);
  CListViewUI.BindItems(CListFilterSourceItems, rowMap, True);
  CListViewUI.RefreshVisibleItems;
end;

class procedure TMainFormUI.UpdateListFilterButtonStyles;
var
  i: Integer;
  hBtn: HELE;
  flags: TButtonPaintFlags;
begin
  for i := 0 to cListFilterCount - 1 do
  begin
    hBtn := XC_GetObjectByName(cListFilterBtnNames[i]);
    if XC_GetObjectType(hBtn) <> XC_BUTTON then
      Continue;
    if i = CListFilterIndex then
      flags := BB_EnableHighlightBk
    else
      flags := BB_EnableNormalBk;
    TButtonUI.FormHandle(hBtn, flags, '');
    XEle_Redraw(hBtn);
  end;
end;

class procedure TMainFormUI.SelectListFilter(const AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= cListFilterCount) then
    Exit;
  if CListFilterIndex = AIndex then
    Exit;
  CListFilterIndex := AIndex;
  UpdateListFilterButtonStyles;
  ApplyListFilterToView;
end;

class procedure TMainFormUI.RemoveListFilterSourceItem(const AFilePath: string);
var
  i, j, n: Integer;
begin
  n := Length(CListFilterSourceItems);
  for i := 0 to n - 1 do
  begin
    if SameText(CListFilterSourceItems[i].FilePath, AFilePath) then
    begin
      for j := i to n - 2 do
        CListFilterSourceItems[j] := CListFilterSourceItems[j + 1];
      SetLength(CListFilterSourceItems, n - 1);
      Exit;
    end;
  end;
end;

class procedure TMainFormUI.UpdateListFilterSourceItem(const AFilePath: string; const AItem: TListViewFileItem);
var
  i: Integer;
begin
  for i := 0 to High(CListFilterSourceItems) do
  begin
    if SameText(CListFilterSourceItems[i].FilePath, AFilePath) then
    begin
      ListFilterAssignSourceItem(CListFilterSourceItems[i], AItem);
      Exit;
    end;
  end;
end;

class function TMainFormUI.OnListFilterButtonClick(hSender: HELE; pbHandled: PBOOL): Integer; stdcall;
var
  i: Integer;
  hBtn: HELE;
begin
  Result := 0;
  for i := 0 to cListFilterCount - 1 do
  begin
    hBtn := XC_GetObjectByName(cListFilterBtnNames[i]);
    if hBtn = hSender then
    begin
      SelectListFilter(i);
      pbHandled^ := True;
      Exit;
    end;
  end;
end;

class procedure TMainFormUI.RefreshListFilterButtonCounts;
var
  i, j, nAll, kindIdx: Integer;
  counts: array of Integer;
  btnVisible, filterReset: Boolean;
begin
  SetLength(counts, cListFilterCount);
  if CActiveListGroupIndex < 0 then
  begin
    ListFilterEnsureExtIdMap;
    EverythingIndexCountHitFilterKinds(CSearchHitIndices, cListFilterFolderIndex,
      cListFilterOtherIndex, GExtIdToFilterKind, counts);
  end
  else
  begin
    nAll := Length(CListFilterSourceItems);
    FillChar(counts[0], cListFilterCount * SizeOf(Integer), 0);
    counts[0] := nAll;
    for i := 0 to nAll - 1 do
    begin
      kindIdx := ListFilterItemKindIndex(CListFilterSourceItems[i].FilePath);
      if kindIdx >= 0 then
        Inc(counts[kindIdx])
      else
        Inc(counts[cListFilterOtherIndex]);
    end;
  end;
  filterReset := False;
  for j := 0 to cListFilterCount - 1 do
  begin
    btnVisible := (j = 0) or (counts[j] > 0);
    SetListFilterButtonVisible(string(cListFilterBtnNames[j]), btnVisible);
    if btnVisible then
      SetListFilterButtonCount(string(cListFilterBtnNames[j]), string(cListFilterLabels[j]), counts[j]);
  end;
  if (CListFilterIndex > 0) and (counts[CListFilterIndex] = 0) then
  begin
    CListFilterIndex := 0;
    filterReset := True;
  end;
  AdjustListFilterToolbarLayout;
  if filterReset then
  begin
    UpdateListFilterButtonStyles;
    if CActiveListGroupIndex < 0 then
      ApplySearchHitsToViewPreserveScroll
    else
      ApplyListFilterToView;
  end;
end;

class procedure TMainFormUI.ShowDiskSearchError(const AError: TDiskSearchError);
var
  msg: string;
  ownerWnd: XCGUI.HWINDOW;
begin
  case AError of
    dseIndexMissing:
      msg := 'NTFS 文件索引未就绪。请确认系统存在 NTFS 磁盘且索引构建已完成。';
    dseIndexAccess:
      msg := '全盘索引构建失败。若需完整 USN 高速索引，请以管理员身份运行 QDesktop。';
  else
    msg := '全盘搜索失败，请稍后重试。';
  end;
  ownerWnd := 0;
  if XC_GetObjectType(CMainHWINDOW) = XC_WINDOW then
    ownerWnd := CMainHWINDOW
  else if (CListViewUI <> nil) and XC_IsHWINDOW(CListViewUI.HWINDOW) then
    ownerWnd := CListViewUI.HWINDOW;
  TMessageBoxUI.Confirm('全盘搜索', msg, ownerWnd);
end;

class procedure TMainFormUI.BridgeDiskSearchResult(AData: PDiskSearchResult);
begin
  try
    ApplyDiskSearchResults(AData);
  finally
    DiskSearchDisposeResult(AData);
  end;
end;

class procedure TMainFormUI.BridgeDiskSearchError(AData: PDiskSearchErrorMsg);
begin
  try
    HandleDiskSearchError(AData);
  finally
    DiskSearchDisposeError(AData);
  end;
end;

class procedure TMainFormUI.SearchUiDebug(const ASummary: string; const ADetail: string = '');
begin
  SafeLogRecord('调试', '搜索UI', ASummary, True, ADetail);
  OutputDebugString(PChar('[SearchUI] ' + ASummary +
    IfThen(ADetail <> '', ' | ' + ADetail, '') + #0));
end;

class procedure TMainFormUI.RequestDiskSearch(const ANeedle: string; AEnableLog: Boolean);
var
  errKind: TDiskSearchError;
begin
  StopSearchHitSortThread;
  if XC_GetObjectType(CMainHWINDOW) <> XC_WINDOW then
  begin
    ShowDiskSearchError(dseQueryFailed);
    Exit;
  end;
  StartSearchIndexStatusTimer;
  if not DiskSearchPrepare(CMainHWINDOW, errKind) then
  begin
    SearchUiDebug('索引准备失败', '错误=' + IntToStr(Ord(errKind)));
    ShowDiskSearchError(errKind);
    Exit;
  end;
  if CListViewUI = nil then
    Exit;
  CActiveListGroupIndex := -1;
  SelectSearchCategoryItem;
  DiskSearchRequest(CMainHWINDOW, ANeedle, CSearchListSortKind, CSearchListAsc);
  CSearchGeneration := DiskSearchCurrentGeneration;
  if AEnableLog then
    CSearchLogGeneration := CSearchGeneration
  else
    CSearchLogGeneration := 0;
end;

class procedure TMainFormUI.ApplyDiskSearchResults(const AData: PDiskSearchResult);
var
  hitCount: Integer;
  editNeedle: string;
  assignStart, filterBtnStart, bindStart, paintStart: Cardinal;
  assignMs, filterBtnMs, bindMs, paintMs, filterCountMs, uiTotalMs: Cardinal;
  rowMap: array of Integer;
  logDetail: string;
  grp: Integer;
begin
  if AData = nil then
  begin
    SearchUiDebug('忽略结果', 'AData=nil');
    Exit;
  end;
  if AData.Generation <> CSearchGeneration then
  begin
    SearchUiDebug('忽略结果', Format('代次不匹配 msg=%d ui=%d 关键字=%s 命中数=%d',
      [AData.Generation, CSearchGeneration, AData.Needle, Length(AData.HitIndices)]));
    Exit;
  end;
  grp := CActiveListGroupIndex;
  if grp <> -1 then
  begin
    SearchUiDebug('忽略结果', Format('当前非搜索视图 group=%d 关键字=%s', [grp, AData.Needle]));
    Exit;
  end;
  editNeedle := CSearchBox.GetTrimmedText;
  if not SameText(editNeedle, AData.Needle) then
  begin
    SearchUiDebug('忽略结果', Format('关键字已变化 edit=%s msg=%s 命中数=%d',
      [editNeedle, AData.Needle, Length(AData.HitIndices)]));
    Exit;
  end;

  assignStart := GetTickCount;
  hitCount := Length(AData.HitIndices);
  CSearchHitIndices := AData.HitIndices;
  SetLength(CListFilterSourceItems, 0);
  CActiveListGroupIndex := -1;
  CListFilterIndex := 0;
  assignMs := GetTickCount - assignStart;

  filterBtnStart := GetTickCount;
  UpdateListFilterButtonStyles;
  filterBtnMs := GetTickCount - filterBtnStart;

  bindStart := GetTickCount;
  SetLength(rowMap, 0);
  CListViewUI.BindSearchHits(CSearchHitIndices, rowMap, True);
  bindMs := GetTickCount - bindStart;

  paintStart := GetTickCount;
  CListViewUI.RefreshVisibleItems;
  paintMs := GetTickCount - paintStart;

  filterBtnStart := GetTickCount;
  RefreshListFilterButtonCounts;
  filterCountMs := GetTickCount - filterBtnStart;
  uiTotalMs := assignMs + filterBtnMs + bindMs + paintMs + filterCountMs;

  if Cardinal(hitCount) < AData.TotalCount then
    logDetail := Format('搜索关键字：%s%s匹配项数：%d个%s已载入列表：%d个',
      [AData.Needle, sLineBreak, AData.TotalCount, sLineBreak, hitCount])
  else
    logDetail := Format('搜索关键字：%s%s搜索项数：%d个',
      [AData.Needle, sLineBreak, hitCount]);
  logDetail := logDetail + sLineBreak +
    Format('索引等待：%s%s编译关键字：%s%s扫描文件：%s%s扫描文件夹：%s%s清理命中：%s%s排序：%s',
      [SafeLogFormatElapsed(AData.IndexWaitMs), sLineBreak,
       SafeLogFormatElapsed(AData.SearchTiming.CompileMs), sLineBreak,
       SafeLogFormatElapsed(AData.SearchTiming.ScanFileMs), sLineBreak,
       SafeLogFormatElapsed(AData.SearchTiming.ScanFolderMs), sLineBreak,
       SafeLogFormatElapsed(AData.SearchTiming.SanitizeMs), sLineBreak,
       IfThen(AData.SearchTiming.SortMs > 0, SafeLogFormatElapsed(AData.SearchTiming.SortMs),
         '0ms（后台）')]) + sLineBreak +
    Format('搜索总耗时：%s%s准备数据：%s%s绑定列表：%s%s首屏绘制：%s%s筛选按钮：%s%s更新计数：%s%sUI总耗时：%s',
      [SafeLogFormatElapsed(AData.QueryElapsedMs), sLineBreak,
       SafeLogFormatElapsed(assignMs), sLineBreak,
       SafeLogFormatElapsed(bindMs), sLineBreak,
       SafeLogFormatElapsed(paintMs), sLineBreak,
       SafeLogFormatElapsed(filterBtnMs), sLineBreak,
       SafeLogFormatElapsed(filterCountMs), sLineBreak,
       SafeLogFormatElapsed(uiTotalMs)]);
  if AData.Generation = CSearchLogGeneration then
  begin
    SafeLogRecord('搜索', '搜索', '全盘搜索', True, logDetail);
    CSearchLogGeneration := 0;
  end;
  ScheduleSearchHitSort(AData.Generation);
end;

class procedure TMainFormUI.StopSearchHitSortThread;
var
  oldThread: TThread;
begin
  oldThread := CSearchSortThread;
  CSearchSortThread := nil;
  if oldThread = nil then
    Exit;
  oldThread.Terminate;
end;

class procedure TMainFormUI.ScheduleSearchHitSort(AGeneration: Cardinal);
begin
  if Length(CSearchHitIndices) < 2 then
    Exit;
  StopSearchHitSortThread;
  CSearchSortThread := TSearchHitSortThread.Create(CMainHWINDOW, AGeneration,
    CSearchListSortKind, CSearchListAsc, CSearchHitIndices);
  CSearchSortThread.Start;
end;

class procedure TMainFormUI.ApplySearchSortDone(const AData: PSearchSortDoneMsg);
var
  sortMs: Cardinal;
begin
  if AData = nil then
    Exit;
  sortMs := AData.SortMs;
  try
    if AData.Generation <> CSearchGeneration then
      Exit;
    if CActiveListGroupIndex <> -1 then
      Exit;
    CSearchHitIndices := AData.HitIndices;
    SetLength(AData.HitIndices, 0);
    ApplyListFilterToView;
    SafeLogRecord('搜索', '搜索', '搜索后台排序', True,
      Format('排序耗时：%s', [SafeLogFormatElapsed(sortMs)]));
  finally
    DiskSearchDisposeSortDone(AData);
  end;
end;

class procedure TMainFormUI.HandleDiskSearchError(const AData: PDiskSearchErrorMsg);
begin
  if AData = nil then
    Exit;
  if AData.Generation <> CSearchGeneration then
  begin
    SearchUiDebug('忽略错误', Format('代次不匹配 msg=%d ui=%d', [AData.Generation, CSearchGeneration]));
    Exit;
  end;
  if CActiveListGroupIndex <> -1 then
    Exit;
  if not SameText(CSearchBox.GetTrimmedText, AData.Needle) then
    Exit;
  SearchUiDebug('显示搜索错误', Format('关键字=%s 错误=%d', [AData.Needle, Ord(AData.ErrorKind)]));
  ShowDiskSearchError(AData.ErrorKind);
end;

class procedure TMainFormUI.DrainPendingDiskSearchMessages;
var
  hRealWnd: Windows.HWND;
  msg: TMsg;
  searchData: PDiskSearchResult;
  errorData: PDiskSearchErrorMsg;
  latestSearch: PDiskSearchResult;
  latestError: PDiskSearchErrorMsg;
begin
  if XC_GetObjectType(CMainHWINDOW) <> XC_WINDOW then
    Exit;
  hRealWnd := XWnd_GetHWND(CMainHWINDOW);
  if hRealWnd = 0 then
    Exit;
  latestSearch := nil;
  latestError := nil;
  while PeekMessageW(msg, hRealWnd, WM_QD_DISK_SEARCH, WM_QD_DISK_SEARCH_ERROR, PM_REMOVE) do
  begin
    case msg.message of
      WM_QD_DISK_SEARCH:
        begin
          searchData := PDiskSearchResult(msg.lParam);
          if latestSearch <> nil then
            DiskSearchDisposeResult(latestSearch);
          latestSearch := searchData;
        end;
      WM_QD_DISK_SEARCH_ERROR:
        begin
          errorData := PDiskSearchErrorMsg(msg.lParam);
          if latestError <> nil then
            DiskSearchDisposeError(latestError);
          latestError := errorData;
        end;
    end;
  end;
  if latestSearch <> nil then
  try
    ApplyDiskSearchResults(latestSearch);
  finally
    DiskSearchDisposeResult(latestSearch);
  end;
  if latestError <> nil then
  try
    HandleDiskSearchError(latestError);
  finally
    DiskSearchDisposeError(latestError);
  end;
end;

class procedure TMainFormUI.ReloadListForCategoryIndex(const iItem: Integer);
var
  groupListIdx: Integer;
begin
  if iItem < 0 then
    Exit;
  if iItem = cCategorySearchListIndex then
  begin
    CActiveListGroupIndex := -1;
    PerformDiskSearchFromBox(False);
    Exit;
  end;
  groupListIdx := iItem - 1;
  if (groupListIdx >= 0) and (groupListIdx < Length(CGroupMap)) then
    LoadListViewFromStore(CGroupMap[groupListIdx]);
end;

class procedure TMainFormUI.SelectSearchCategoryItem;
begin
  if CListBoxUI = nil then
    Exit;
  if CListBoxUI.GetSelectItem = cCategorySearchListIndex then
    Exit;
  CSuppressCategorySelectReload := True;
  try
    XListBox_SetSelectItem(CListBoxUI.Handle, cCategorySearchListIndex);
  finally
    CSuppressCategorySelectReload := False;
  end;
end;

class function TMainFormUI.OnCategorySelect(hEle: XCGUI.HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if CSuppressCategorySelectReload then
    Exit;
  DiskSearchStopAndWait;
  ReloadListForCategoryIndex(iItem);
end;

class function TMainFormUI.OnCategoryMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  sel, groupIndex, deleteGroupIndex: Integer;
  oldName, newName, oldIconFile, iconFile: string;
  createOk, deleteOk: Boolean;
begin
  Result := 0;

  if nItem = ID_LISTBOX_CATEGORY_ADD then
  begin
    newName := '新分类';
    iconFile := '';
    if not TCategoryDialogUI.EditCategory(newName, iconFile, '添加分类', '创建', XWidget_GetHWINDOW(CListBoxUI.Handle)) then
      Exit;
    newName := Trim(newName);
    iconFile := NormalizeCategoryIconFile(iconFile);
    if newName = '' then
      Exit;
    createOk := CStore.CreateGroup(newName, iconFile, groupIndex);
    LogGroupDbOp('创建分组', newName, createOk, groupIndex);
    if createOk then
      ReloadCategoriesAndSelectGroup(groupIndex);
    Exit;
  end;

  if nItem = ID_LISTBOX_CATEGORY_EDIT then
  begin
    sel := CListBoxUI.GetSelectItem;
    if (sel <= cCategorySearchListIndex) or (sel - 1 >= Length(CGroupMap)) then
      Exit;
    oldName := CListBoxUI.GetItemTitle(sel);
    if sel - 1 < Length(CGroupIconMap) then
      oldIconFile := CGroupIconMap[sel - 1]
    else
      oldIconFile := '';
    iconFile := oldIconFile;
    newName := oldName;
    if not TCategoryDialogUI.EditCategory(newName, iconFile, '编辑分类', '保存', XWidget_GetHWINDOW(CListBoxUI.Handle)) then
      Exit;
    newName := Trim(newName);
    oldIconFile := NormalizeCategoryIconFile(oldIconFile);
    iconFile := NormalizeCategoryIconFile(iconFile);
    if (newName = '') or ((newName = oldName) and SameText(Trim(iconFile), Trim(oldIconFile))) then
      Exit;
    groupIndex := CGroupMap[sel - 1];
    if CStore.UpdateGroup(groupIndex, newName, iconFile) then
      ReloadCategoriesAndSelectGroup(groupIndex);
    Exit;
  end;

  if nItem = ID_LISTBOX_CATEGORY_DELETE then
  begin
    sel := CListBoxUI.GetSelectItem;
    if (sel <= cCategorySearchListIndex) or (sel - 1 >= Length(CGroupMap)) then
      Exit;
    oldName := CListBoxUI.GetItemTitle(sel);
    if not TMessageBoxUI.Confirm('删除分类', '确定删除分类 "' + oldName + '" 吗？该分类下的应用也会被删除。', XWidget_GetHWINDOW(CListBoxUI.Handle)) then
      Exit;

    deleteGroupIndex := CGroupMap[sel - 1];
    deleteOk := CStore.DeleteGroup(deleteGroupIndex);
    LogGroupDbOp('删除分组', oldName, deleteOk, deleteGroupIndex);
    if deleteOk then
    begin
      LoadListBoxFromStore;
      sel := CListBoxUI.GetSelectItem;
      if sel >= 0 then
        ReloadListForCategoryIndex(sel)
      else
      begin
        SetLength(CListFilterSourceItems, 0);
        CListFilterIndex := 0;
        UpdateListFilterButtonStyles;
        CListViewUI.ClearItems;
        RefreshListFilterButtonCounts;
      end;
      CListViewUI.Redraw();
    end;
    Exit;
  end;

  if nItem = ID_LISTBOX_CATEGORY_TOGGLE_COMMON_TOOLS then
  begin
    TAppConfig.SetShowCommonTools(not TAppConfig.IsShowCommonTools);
    TAppConfig.Save;
    Exit;
  end;

  if nItem = ID_LISTBOX_CATEGORY_TOGGLE_TRAFFIC then
  begin
    TAppConfig.SetShowTrafficMonitor(not TAppConfig.IsShowTrafficMonitor);
    TAppConfig.Save;
    TMainWindowStat.SyncNetTrafficSamplerWithConfig;
    Exit;
  end;
end;

class function TMainFormUI.OnContentMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  itm: Integer;
  data: TListViewFileItem;
  groupIndex: Integer;
  fileName: string;
  hOwnerWnd: XCGUI.HWINDOW;
  newTitle, newParams, newWorkDir, iconPath, oldIconPath: string;
  newShowCmd: Integer;
  iconChanged: Boolean;
  activeGroupIndex: Integer;
  folderPath: string;
  grpIdx: Integer;
  dbItems: TLibraryItemArray;
  uiItems: array of TListViewFileItem;
  i, n: Integer;
  data2: TListViewFileItem;
  pickedFiles: TStringList;
begin
  pbHandled^ := True;
  Result := 0;
  hOwnerWnd := CListViewUI.HWINDOW;
  if ShellOpenWithHandleMenuCommand(nItem, CListViewUI.HWND) then
    Exit;

  if nItem = ID_LISTVIEW_MENU_ADD_FILE then
  begin
    SyncCategoriesForDrop;
    grpIdx := CActiveListGroupIndex;
    if grpIdx < 0 then
      Exit;
    pickedFiles := TStringList.Create;
    try
      if OpenFileDialogMulti(CListViewUI.HWND, '添加文件',
        '可执行文件 (*.exe)|*.exe|快捷方式 (*.lnk)|*.lnk|所有文件 (*.*)|*.*', pickedFiles) then
      begin
        SetLength(dbItems, pickedFiles.Count);
        SetLength(uiItems, pickedFiles.Count);
        for i := 0 to pickedFiles.Count - 1 do
        begin
          data2 := GetListViewFileItemFromParsingPath(pickedFiles[i], False);
          uiItems[i] := data2;
          dbItems[i] := ListViewItemToLibraryItem(data2);
        end;
        InsertBatchItemsToUI(grpIdx, uiItems, dbItems);
      end;
    finally
      pickedFiles.Free;
    end;
    Exit;
  end;

  if nItem = ID_LISTVIEW_MENU_ADD_FOLDER then
  begin
    SyncCategoriesForDrop;
    grpIdx := CActiveListGroupIndex;
    if grpIdx < 0 then
      Exit;
    folderPath := '';
    if BrowseForFolderPath('添加文件夹', CListViewUI.HWND, folderPath) then
    begin
      data2 := GetListViewFileItemFromParsingPath(folderPath, False);
      if CStore.TryInsertItem(grpIdx, data2.FilePath, data2.FileName, data2.IconCachePath, data2.FileParams, data2.WorkingDir, data2.ShowCmd) then
      begin
        data2.ItemGroupIndex := grpIdx;
        n := Length(CListFilterSourceItems);
        SetLength(CListFilterSourceItems, n + 1);
        ListFilterAssignSourceItem(CListFilterSourceItems[n], data2);
        ApplyListFilterToView;
        CListViewUI.Redraw;
        RefreshListFilterButtonCounts;
      end;
    end;
    Exit;
  end;

  if not CListViewUI.TryGetSelectedItem(groupIndex, itm, data) then
    Exit;

  if (CActiveListGroupIndex < 0) and (data.FilePath = '') then
    data.FilePath := CListViewUI.ResolveSearchItemPath(itm);

  if (nItem = ID_LISTVIEW_MENU_OPEN) or (nItem = ID_LISTVIEW_MENU_RUN_AS_ADMIN) then
  begin
    if data.FilePath = '' then
      Exit;
    if nItem = ID_LISTVIEW_MENU_OPEN then
      ShellExecuteDefaultVerb(CListViewUI.HWND, data.FilePath, data.FileParams, data.WorkingDir, data.ShowCmd)
    else if not ShellExecuteRunAs(CListViewUI.HWND, data.FilePath, data.FileParams, data.WorkingDir, data.ShowCmd) then
      MessageBoxW(CListViewUI.HWND, '无法以管理员身份运行该项，请确认路径和权限设置。', '提示', MB_OK or MB_ICONWARNING);
    Exit;
  end;

  if nItem = ID_LISTVIEW_MENU_OPEN_FOLDER then
  begin
    if data.FilePath <> '' then
    begin
      if SysUtils.DirectoryExists(data.FilePath) then
      begin
        ShellExecuteDefaultVerb(CListViewUI.HWND, data.FilePath, '', '', SW_SHOWNORMAL);
        Exit;
      end;
      if FileExists(data.FilePath) then
      begin
        ShellOpenFolderAndSelectPath(CListViewUI.HWND, data.FilePath);
        Exit;
      end;
      fileName := ExtractFilePath(data.FilePath);
      if SysUtils.DirectoryExists(fileName) then
      begin
        ShellExecuteDefaultVerb(CListViewUI.HWND, fileName, '', '', SW_SHOWNORMAL);
        Exit;
      end;
    end;

    if (data.WorkingDir <> '') and SysUtils.DirectoryExists(data.WorkingDir) then
      ShellExecuteDefaultVerb(CListViewUI.HWND, data.WorkingDir, '', '', SW_SHOWNORMAL);
    Exit;
  end;

  if nItem = ID_LISTVIEW_MENU_EDIT then
  begin
    newTitle := data.FileName;
    newParams := data.FileParams;
    newWorkDir := data.WorkingDir;
    newShowCmd := data.ShowCmd;
    iconPath := data.IconCachePath;
    if TEditItemDialogUI.EditItem(data.FilePath, data.FileImage, newTitle, newParams, newWorkDir, newShowCmd, iconPath, iconChanged, hOwnerWnd) then
    begin
      activeGroupIndex := CActiveListGroupIndex;
      if data.ItemGroupIndex >= 0 then
        activeGroupIndex := data.ItemGroupIndex;
      if activeGroupIndex < 0 then
        Exit;

      if CStore.UpdateItem(activeGroupIndex, data.FilePath, newTitle, iconPath, newParams, newWorkDir, newShowCmd) then
      begin
        oldIconPath := data.IconCachePath;
        data.FileName := newTitle;
        data.FileParams := newParams;
        data.WorkingDir := newWorkDir;
        data.ShowCmd := newShowCmd;
        data.IconCachePath := iconPath;
        if iconChanged then
          InvalidateListViewItemIcon(data, oldIconPath);
        data.DisplayTitle := ListViewItemDisplayTitle(data);
        CListViewUI.UpdateItemAt(itm, data);
        UpdateListFilterSourceItem(data.FilePath, data);
        CListViewUI.RefreshVisibleItems;
        CListViewUI.Redraw();
      end;
    end;
    Exit;
  end;

  if nItem = ID_LISTVIEW_MENU_DELETE then
  begin
    fileName := data.FileName;
    if fileName = '' then
      fileName := ExtractFileName(data.FilePath);
    if fileName = '' then
      fileName := data.FilePath;

    if not TMessageBoxUI.Confirm('删除项', '确定要删除' + fileName + '吗？', hOwnerWnd) then
      Exit;

    activeGroupIndex := CActiveListGroupIndex;
    if data.ItemGroupIndex >= 0 then
      activeGroupIndex := data.ItemGroupIndex;
    if activeGroupIndex < 0 then
      Exit;
    if CStore.DeleteItem(activeGroupIndex, data.FilePath) then
    begin
      RemoveListFilterSourceItem(data.FilePath);
      ApplyListFilterToView;
      CListViewUI.Redraw();
      RefreshListFilterButtonCounts;
    end;
  end;
end;



class function TMainFormUI.OnWndDropFiles(hWindow: XCGUI.HWINDOW; hDrop: XCGUI.HDROP; pbHandled: PBOOL): Integer; stdcall;
var
  cnt, nChars: UINT;
  cntInt, i: Integer;
  wpath: string;
  grpIdx: Integer;
  data: TListViewFileItem;
  uiItems: array of TListViewFileItem;
  dbItems: TLibraryItemArray;
begin
  Result := 0;
  pbHandled^ := True;
  try
    SyncCategoriesForDrop;
    grpIdx := CActiveListGroupIndex;
    if grpIdx < 0 then
      Exit;

    cnt := DragQueryFileW(hDrop, $FFFFFFFF, nil, 0);
    if cnt = 0 then
      Exit;
    cntInt := Integer(cnt);
    SetLength(dbItems, cntInt);
    SetLength(uiItems, cntInt);
    for i := 0 to cntInt - 1 do
    begin
      nChars := DragQueryFileW(hDrop, UINT(i), nil, 0);
      SetLength(wpath, nChars);
      DragQueryFileW(hDrop, UINT(i), PWideChar(wpath), nChars + 1);
      data := GetListViewFileItemFromParsingPath(wpath, False);
      uiItems[i] := data;
      dbItems[i] := ListViewItemToLibraryItem(data);
    end;

    InsertBatchItemsToUI(grpIdx, uiItems, dbItems);
  finally
    DragFinish(hDrop);
  end;
end;

class procedure TMainFormUI.ScheduleDebouncedDiskSearch;
begin
  if XC_GetObjectType(CMainHWINDOW) <> XC_WINDOW then
    Exit;
  DiskSearchStop;
  XWnd_KillTimer(CMainHWINDOW, cMainSearchDebounceTimerId);
  XWnd_SetTimer(CMainHWINDOW, cMainSearchDebounceTimerId, cMainSearchDebounceMs);
end;

class procedure TMainFormUI.ApplyIndexHitChanges(const AData: PIndexHitChangesMsg);
var
  needle: string;
begin
  if AData = nil then
    Exit;
  if CActiveListGroupIndex <> -1 then
    Exit;
  if CListViewUI = nil then
    Exit;
  needle := CSearchBox.GetTrimmedText;
  if needle = '' then
    Exit;
  EverythingIndexPatchSearchHits(CSearchHitIndices, needle, AData^.Changes);
  ApplySearchHitsToViewPreserveScroll;
  RefreshListFilterButtonCounts;
end;

class procedure TMainFormUI.RefreshSearchIndexStatusLabel;
var
  statusText: string;
  building: Boolean;
  hEditWrap: HXCGUI;
begin
  building := EverythingIndexIsBuilding;
  statusText := EverythingIndexGetBuildStatusText;
  if (statusText = CLastSearchIndexStatusText) and (building = CLastSearchIndexBuilding) then
    Exit;
  CLastSearchIndexStatusText := statusText;
  CLastSearchIndexBuilding := building;

  if XC_GetObjectType(CShapeSearchIndexStatus) = XC_SHAPE_TEXT then
  begin
    XShapeText_SetText(CShapeSearchIndexStatus, PWideChar(statusText));
    XWidget_Show(CShapeSearchIndexStatus, building);
    XShape_AdjustLayout(CShapeSearchIndexStatus);
    XShape_Redraw(CShapeSearchIndexStatus);
  end;

  if XC_GetObjectType(CSearchBox.Edit.Handle) = XC_EDIT then
  begin
    hEditWrap := XWidget_GetParent(CSearchBox.Edit.Handle);
    if XC_GetObjectType(hEditWrap) <> XC_ERROR then
      XWidget_Show(hEditWrap, not building);
    if building and (XC_GetObjectType(CMainHWINDOW) = XC_WINDOW) then
      XWnd_KillTimer(CMainHWINDOW, cMainSearchDebounceTimerId);
  end;

  AdjustMainSearchAreaLayout;
end;

class procedure TMainFormUI.StartSearchIndexStatusTimer;
begin
  if XC_GetObjectType(CMainHWINDOW) <> XC_WINDOW then
    Exit;
  RefreshSearchIndexStatusLabel;
  XWnd_SetTimer(CMainHWINDOW, cMainIndexStatusTimerId, cMainIndexStatusTimerMs);
end;

class function TMainFormUI.OnSearchDebounceTimer(hWindow: XCGUI.HWINDOW; nIDEvent: UINT; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if nIDEvent = cMainSearchDebounceTimerId then
  begin
    pbHandled^ := True;
    XWnd_KillTimer(CMainHWINDOW, cMainSearchDebounceTimerId);
    PerformDiskSearchFromBox(True);
    Exit;
  end;
  if nIDEvent = cMainIndexStatusTimerId then
  begin
    pbHandled^ := True;
    DrainPendingDiskSearchMessages;
    RefreshSearchIndexStatusLabel;
    if (not EverythingIndexIsBuilding) and (not DiskSearchIsActive) then
      XWnd_KillTimer(CMainHWINDOW, cMainIndexStatusTimerId);
  end;
end;

class procedure TMainFormUI.PerformDiskSearchFromBox(AEnableLog: Boolean);
var
  needle: string;
begin
  needle := CSearchBox.GetTrimmedText;
  RequestDiskSearch(needle, AEnableLog);
end;

class function TMainFormUI.OnMainSearchButtonClick(Sender: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  if XC_GetObjectType(CMainHWINDOW) = XC_WINDOW then
    XWnd_KillTimer(CMainHWINDOW, cMainSearchDebounceTimerId);
  PerformDiskSearchFromBox(True);
end;

class function TMainFormUI.OnWinProc(hWindow: XCGUI.HWINDOW; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
var
  searchData: PDiskSearchResult;
  errorData: PDiskSearchErrorMsg;
  iconData: PShellIconLoadResult;
  hitChanges: PIndexHitChangesMsg;
begin
  Result := 0;
  TFormUI.HandleWndSize(hWindow, Msg, wParam);
  if TMainWindowStat.TryHandleWinProc(Msg, wParam, lParam, pbHandled) then
    Exit;
  case Msg of
    WM_QD_LIST_ICON_READY:
      begin
        iconData := PShellIconLoadResult(lParam);
        try
          ApplyListIconLoadResult(iconData);
        finally
          ShellIconLoaderDisposeResult(iconData);
        end;
        pbHandled^ := True;
        Exit;
      end;
    WM_QD_LIST_DEFERRED_REFRESH:
      begin
        if CListViewUI <> nil then
          CListViewUI.RefreshVisibleItems;
        pbHandled^ := True;
        Exit;
      end;
    WM_QD_DISK_SEARCH_SORT_DONE:
      begin
        ApplySearchSortDone(PSearchSortDoneMsg(lParam));
        pbHandled^ := True;
        Exit;
      end;
    WM_QD_DISK_SEARCH:
      begin
        searchData := PDiskSearchResult(lParam);
        try
          ApplyDiskSearchResults(searchData);
        finally
          DiskSearchDisposeResult(searchData);
        end;
        pbHandled^ := True;
        Exit;
      end;
    WM_QD_DISK_SEARCH_ERROR:
      begin
        errorData := PDiskSearchErrorMsg(lParam);
        try
          HandleDiskSearchError(errorData);
        finally
          DiskSearchDisposeError(errorData);
        end;
        pbHandled^ := True;
        Exit;
      end;
    WM_QD_INDEX_HIT_CHANGES:
      begin
        hitChanges := PIndexHitChangesMsg(lParam);
        try
          ApplyIndexHitChanges(hitChanges);
        finally
          EverythingIndexDisposeHitChangesMsg(hitChanges);
        end;
        pbHandled^ := True;
        Exit;
      end;
  end;
  if Msg = WM_SYSCOMMAND then
  begin
    if (wParam and $FFF0) = SC_CLOSE then
    begin
      TMainWindowStat.StopWorkers;
      TFormUI.ReleaseModalStack;
    end;
  end;
  DrainPendingDiskSearchMessages;
end;

class function TMainFormUI.OnSafeLogButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  TSafeLogWindow.ShowWindow;
  pbHandled^ := True;
end;

class function TMainFormUI.OnListLayoutButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  TListViewSettingsDialogUI.ShowDialog(CMainHWINDOW, NativeInt(CListViewUI), 0);
end;

class function TMainFormUI.OnListSortButtonClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
var
  Menu: TPopupMenuUI;
  pt: TPoint;
  rc: TRect;
  fAsc, fDesc, fName, fTime, fType: Integer;
  grp: Integer;
  listSortKind: TLibraryListSortKind;
  asc: Boolean;
begin
  Result := 0;
  pbHandled^ := True;
  listSortKind := llskAddTime;
  asc := True;
  grp := CActiveListGroupIndex;
  if grp >= 0 then
    CStore.GetGroupListSort(grp, listSortKind, asc)
  else
  begin
    listSortKind := CSearchListSortKind;
    asc := CSearchListAsc;
  end;
  Menu := TPopupMenuUI.Create(hEle);
  try
    fAsc := 0;
    if asc then
      fAsc := menu_item_flag_Check;
    Menu.AddItem(ID_MAIN_LIST_SORT_ASC, '递增', 0, fAsc);
    fDesc := 0;
    if not asc then
      fDesc := menu_item_flag_Check;
    Menu.AddItem(ID_MAIN_LIST_SORT_DESC, '递减', 0, fDesc);
    Menu.AddItem(0, '', 0, menu_item_flag_separator);
    fTime := 0;
    if listSortKind = llskAddTime then
      fTime := menu_item_flag_Check;
    Menu.AddItem(ID_MAIN_LIST_SORT_BY_TIME, '添加时间', 0, fTime);
    fName := 0;
    if listSortKind = llskName then
      fName := menu_item_flag_Check;
    Menu.AddItem(ID_MAIN_LIST_SORT_BY_NAME, '名称', 0, fName);
    fType := 0;
    if listSortKind = llskFileType then
      fType := menu_item_flag_Check;
    Menu.AddItem(ID_MAIN_LIST_SORT_BY_FILETYPE, '文件类型', 0, fType);
    XEle_GetRect(hEle, rc);
    pt.X := rc.Right;
    pt.Y := rc.Bottom;
    Menu.Popup(hEle, pt, menu_popup_position_right_top);
  finally
    Menu.Free;
  end;
end;

class function TMainFormUI.OnListSortMenuSelect(hEle: XCGUI.HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  grp: Integer;
  listSortKind: TLibraryListSortKind;
  asc: Boolean;
  isSearchView: Boolean;
begin
  Result := 0;
  pbHandled^ := True;
  grp := CActiveListGroupIndex;
  isSearchView := grp < 0;
  if isSearchView then
  begin
    listSortKind := CSearchListSortKind;
    asc := CSearchListAsc;
  end
  else
    CStore.GetGroupListSort(grp, listSortKind, asc);
  case nItem of
    ID_MAIN_LIST_SORT_ASC:
      asc := True;
    ID_MAIN_LIST_SORT_DESC:
      asc := False;
    ID_MAIN_LIST_SORT_BY_NAME:
      listSortKind := llskName;
    ID_MAIN_LIST_SORT_BY_TIME:
      listSortKind := llskAddTime;
    ID_MAIN_LIST_SORT_BY_FILETYPE:
      listSortKind := llskFileType;
  else
    Exit;
  end;
  if isSearchView then
  begin
    CSearchListSortKind := listSortKind;
    CSearchListAsc := asc;
    StopSearchHitSortThread;
    EverythingIndexSortHitIndices(CSearchHitIndices, listSortKind, asc);
    ApplyListFilterToView;
    Exit;
  end
  else
    CStore.UpdateGroupListSort(grp, listSortKind, asc);
  ApplyListSort(listSortKind, asc);
end;

procedure TMainFormUI.Init;
var
  pGrip: TSidebarGripUI;
  btnUi: TButtonUI;
  btnStatWeather: HELE;
  i: Integer;
begin
  inherited;
  CMainHWINDOW := Handle;
  EverythingIndexSetNotifyHwnd(XWnd_GetHWND(Handle));
  TFormUI.ApplyTitleLogo('pic_main_logo', 50, Handle);
  try
    CStore := TLibraryStore.Create(TAppConfig.DatabaseFilePath);
    SafeLogStartupAppendStep('数据库', '加载本地数据库', True);
    if PawnIoAvailable then
      SafeLogStartupAppendStep('驱动', 'PawnIO MSR 模块加载成功', True)
    else
      SafeLogStartupAppendStep('驱动', PawnIoLoadFailureDetail, True);
    SafeLogStartupCommit;
  except
    on E: Exception do
    begin
      SafeLogStartupAppendStep('数据库', E.Message, False);
      SafeLogStartupCommit;
      raise;
    end;
  end;
  CSearchListSortKind := llskName;
  CSearchListAsc := True;
  CSearchGeneration := 0;
  CSearchLogGeneration := 0;
  CSearchSortThread := nil;
  CShapeSearchIndexStatus := XC_GetObjectByName('txt_main_search_index_status');
  CLastSearchIndexStatusText := '';
  CLastSearchIndexBuilding := not EverythingIndexIsBuilding;
  EverythingIndexStartupAsync;
  CListFilterIndex := 0;
  SetLength(CListFilterSourceItems, 0);
  RestoreMainWindowBounds(Handle);
  btnUi := TButtonUI.FromXmlName('btn_main_settings', BB_NONE, 'Resource\Settings.svg');
  btnUi.RegEvent(XE_BNCLICK, @MainWindowSettings_OnButtonClick);
  XEle_RegEvent(btnUi.Handle, XE_MENU_SELECT, @MainWindowSettings_OnMenuSelect);
  TButtonUI.FromXmlName('btn_main_min', BB_NONE, 'Resource\min.svg');
  btnUi := TButtonUI.FromXmlName('btn_main_max', BB_NONE, cBtnSvgMax);
  TButtonUI.BindMaxButton(Handle, btnUi.Handle);
  TButtonUI.SyncMaxButtonSvg(Handle);
  btnUi := TButtonUI.FromXmlName('btn_main_close', BB_NONE, 'Resource\close.svg');
  if btnUi.IsHELE then
    THintPopupUI.BindHoverHint(btnUi.Handle, '关闭程序', hpsBubble);
  btnUi := TButtonUI.FromXmlName('btn_main_commonTools', BB_NONE, 'Resource\CommonTools.svg', 16, 16);
  btnUi.RegEvent(XE_BNCLICK, @MainWindowCommonTools_OnButtonClick);
  XEle_RegEvent(btnUi.Handle, XE_MENU_SELECT, @MainWindowCommonTools_OnMenuSelect);
  btnUi := TButtonUI.FromXmlName('btn_main_sysTools', BB_NONE, 'Resource\tools.svg', 16, 16);
  btnUi.RegEvent(XE_BNCLICK, @MainWindowTools_OnButtonClick);
  XEle_RegEvent(btnUi.Handle, XE_MENU_SELECT, @MainWindowTools_OnMenuSelect);
  TButtonUI.FromXmlName('btn_main_notify', BB_NONE, 'Resource\bell.svg', 16, 16).RegEvent(XE_BNCLICK, @TMainFormUI.OnSafeLogButtonClick);
  for i := 0 to cListFilterCount - 1 do
  begin
    if i = 0 then
      btnUi := TButtonUI.FromXmlName(string(cListFilterBtnNames[i]), BB_EnableHighlightBk, '')
    else
      btnUi := TButtonUI.FromXmlName(string(cListFilterBtnNames[i]), BB_EnableNormalBk, '');
    btnUi.RegEvent(XE_BNCLICK, @TMainFormUI.OnListFilterButtonClick);
  end;
  btnUi := TButtonUI.FromXmlName('btn_main_list_layout', BB_NONE, 'Resource\list_view_layout.svg', 16, 16);
  btnUi.RegEvent(XE_BNCLICK, @TMainFormUI.OnListLayoutButtonClick);
  btnUi := TButtonUI.FromXmlName('btn_main_list_sort', BB_NONE, 'Resource\list_view_sort.svg', 16, 16);
  btnUi.RegEvent(XE_BNCLICK, @TMainFormUI.OnListSortButtonClick);
  XEle_RegEvent(btnUi.Handle, XE_MENU_SELECT, @TMainFormUI.OnListSortMenuSelect);
  btnStatWeather := TButtonUI.FromXmlName('btn_main_stat_weather', BB_NONE, PWideChar(WeatherIconSvgPath(999)), 16, 16).Handle;
  CSearchBox := TSearchBoxUI.FromXml('edit_main_search');
  CSearchBox.RegOnSearchClick(@TMainFormUI.OnMainSearchButtonClick);
  CSearchBox.RegOnSearchInputChanged(@TMainFormUI.ScheduleDebouncedDiskSearch);
  CListBoxUI := TListBoxUI.FromXmlName('list_main_category');
  CListBoxUI.SetProtectedHeadCount(1);
  CListViewUI := TListViewUI.FromXmlName('list_main_content');
  ShellIconLoaderInit(Handle);
  CListViewUI.OnPrepareContextMenu := MainWindowListViewPrepareContextMenu;
  CListViewUI.OnItemActivate := MainWindowListViewItemActivate;
  CListViewUI.OnItemWidthChanged := MainWindowListViewItemWidthChanged;
  CListViewUI.SetItemWidth(TAppConfig.GetListItemWidth);
  pGrip := TSidebarGripUI.FromXmlName('layout_main_sidebar_grip');
  pGrip.Attach(XWidget_GetParent(CListBoxUI.Parent), pGrip.HWINDOW);
  CListBoxUI.RegEvent(XE_LISTBOX_SELECT, @TMainFormUI.OnCategorySelect);
  CListBoxUI.RegEvent(XE_MENU_SELECT, @TMainFormUI.OnCategoryMenuSelect);
  CListViewUI.RegEvent(XE_MENU_SELECT, @TMainFormUI.OnContentMenuSelect);
  LoadListBoxFromStore;
  if CListBoxUI.GetCount > cCategorySearchListIndex + 1 then
    CListBoxUI.SendEvent(XE_LISTBOX_SELECT, cCategorySearchListIndex + 1, 0)
  else
    CListBoxUI.SendEvent(XE_LISTBOX_SELECT, cCategorySearchListIndex, 0);
  EnableDragFiles(True);
  RegEvent(WM_DROPFILES, @TMainFormUI.OnWndDropFiles);
  RegEvent(WM_TIMER, @TMainFormUI.OnSearchDebounceTimer);
  RegEvent(XWM_WINDPROC, @TMainFormUI.OnWinProc);
  DiskSearchSetHandlers(@TMainFormUI.BridgeDiskSearchResult, @TMainFormUI.BridgeDiskSearchError);
  ApplyDefaultStyles(Handle);
  ApplyListViewLayoutFromConfig(CListViewUI);
  TMainWindowStat.Init(Handle, GetCurrentThreadId, btnStatWeather);
  if XC_GetObjectType(CShapeSearchIndexStatus) = XC_SHAPE_TEXT then
    XShapeText_SetTextColor(CShapeSearchIndexStatus, UITheme_PrimaryColor);
  StartSearchIndexStatusTimer;
end;

destructor TMainFormUI.Destroy;
begin
  if XC_GetObjectType(CMainHWINDOW) = XC_WINDOW then
  begin
    XWnd_KillTimer(CMainHWINDOW, cMainSearchDebounceTimerId);
    XWnd_KillTimer(CMainHWINDOW, cMainIndexStatusTimerId);
  end;
  DiskSearchSetHandlers(nil, nil);
  DiskSearchStopAndWait;
  ShellIconLoaderShutdown;
  TAppConfig.SetListItemWidth(CListViewUI.GetItemWidth);
  SaveMainWindowBounds(Handle);
  TMainWindowStat.StopWorkers;
  CStore.Free;
  CStore := nil;
  ReleaseFileTypeImageCache;
  inherited;
end;

class function TMainFormUI.LoadLayout(const LayoutFile: PWideChar): TMainFormUI;
var
  hRealWnd: Windows.HWND;
begin
  Result := FromHandle(XC_LoadLayout(LayoutFile, 0, 0));
  if Result <> nil then
  begin
    hRealWnd := XWnd_GetHWND(Result.Handle);
    SetWindowTextW(hRealWnd, 'QDesktop');
  end;
end;


function ListViewItemToLibraryItem(const AItem: TListViewFileItem): TLibraryItem;
begin
  Result.FilePath := AItem.FilePath;
  Result.FileName := AItem.FileName;
  Result.IconCachePath := AItem.IconCachePath;
  Result.FileParams := AItem.FileParams;
  Result.WorkingDir := AItem.WorkingDir;
  Result.ShowCmd := AItem.ShowCmd;
end;

function LibraryItemToListViewItem(const AItem: TLibraryItem; const AIndex, AGroupIndex: Integer): TListViewFileItem;
begin
  Result := GetListViewFileItemFromParsingPath(AItem.FilePath, False);
  if Trim(AItem.FileName) <> '' then
    Result.FileName := AItem.FileName;
  if Trim(AItem.IconCachePath) <> '' then
    Result.IconCachePath := AItem.IconCachePath;
  if Trim(AItem.FileParams) <> '' then
    Result.FileParams := AItem.FileParams;
  if Trim(AItem.WorkingDir) <> '' then
    Result.WorkingDir := AItem.WorkingDir;
  Result.ShowCmd := AItem.ShowCmd;
  Result.DisplayTitle := ListViewItemDisplayTitle(Result);
  Result.InsertOrder := AIndex;
  Result.FileImage := 0;
  Result.ItemGroupIndex := AGroupIndex;
end;

procedure InvalidateListViewItemIcon(var AItem: TListViewFileItem; const APreviousIconPath: string = '');
var
  oldImg: HIMAGE;
begin
  if Trim(APreviousIconPath) <> '' then
    InvalidateListItemIconCaches(APreviousIconPath, AItem.FilePath);
  InvalidateListItemIconCaches(AItem.IconCachePath, AItem.FilePath);

  oldImg := AItem.FileImage;
  if XC_GetObjectType(oldImg) = XC_IMAGE then
    XImage_Release(oldImg);
  AItem.FileImage := 0;
end;

class procedure TMainFormUI.ApplyListIconLoadResult(AData: PShellIconLoadResult);
begin
  if (AData = nil) or (CListViewUI = nil) then
    Exit;
  if AData.ListGeneration <> ShellIconLoaderCurrentListGeneration then
    Exit;
  if AData.ScrollGeneration <> ShellIconLoaderCurrentScrollGeneration then
    Exit;
  if AData.ListEle <> CListViewUI.Handle then
    Exit;
  CListViewUI.ApplyIconLoadResult(AData.ListGeneration, AData.ScrollGeneration, AData.ItemIndex, AData.FilePath,
    AData.IconCachePathOut, AData.PixelKey, AData.FromCache, AData.CachedImage);
end;

procedure MainWindowListViewPrepareContextMenu(ASender: TListViewUI; AMenu: TPopupMenuUI; AItemIndex: Integer;
  const AFilePath: string);
var
  isSearchView: Boolean;
begin
  ShellOpenWithResetMenuState;
  isSearchView := TMainFormUI.CActiveListGroupIndex < 0;
  if (AItemIndex >= 0) and (AFilePath <> '') then
  begin
    AMenu.AddItem(ID_LISTVIEW_MENU_OPEN, '打开', 0);
    if SameText(ExtractFileExt(AFilePath), '.exe') then
      AMenu.AddItemShieldIcon(ID_LISTVIEW_MENU_RUN_AS_ADMIN, '以管理员身份运行', 0, 0);
    AMenu.AddItem(ID_LISTVIEW_MENU_OPEN_FOLDER, UI_Utf8Src(UTF8String('打开所在目录')));
    ShellOpenWithAppendContextMenuItems(AMenu, AFilePath);
    if not isSearchView then
    begin
      AMenu.AddItem(0, '', 0, menu_item_flag_separator);
      AMenu.AddItemIcon(ID_LISTVIEW_MENU_EDIT, '修改', 0, 'Resource\menu_edit.svg', 0);
      AMenu.AddItem(ID_LISTVIEW_MENU_DELETE, '删除');
      AMenu.AddItem(0, '', 0, menu_item_flag_separator);
    end;
  end;
  AMenu.AddItem(ID_LISTVIEW_MENU_ADD_FILE, '添加文件');
  AMenu.AddItem(ID_LISTVIEW_MENU_ADD_FOLDER, UI_Utf8Src(UTF8String('添加文件夹')));
end;

procedure MainWindowListViewItemActivate(ASender: TListViewUI; AItemIndex: Integer);
begin
  if ASender = nil then
    Exit;
  XEle_SendEvent(ASender.Handle, XE_MENU_SELECT, ID_LISTVIEW_MENU_OPEN, 0);
end;

procedure MainWindowListViewItemWidthChanged(ASender: TListViewUI; AWidth: Integer);
begin
  TAppConfig.SetListItemWidth(AWidth);
end;

procedure ApplyListViewLayoutFromConfig(AListView: TListViewUI);
begin
  if AListView = nil then
    Exit;
  AListView.ApplyLayoutSettings(TAppConfig.GetListColumnSpace, TAppConfig.GetListRowSpace,
    TAppConfig.GetListItemCornerRadius, TAppConfig.GetListScrollBarSize,
    TAppConfig.GetListScrollSliderMinLen, TAppConfig.GetListScrollThumbRadius);
end;

function NormalizeCategoryIconFile(const AIconFile: string): string;
begin
  Result := ExtractFileName(Trim(AIconFile));
end;

procedure ApplyDefaultStyles(hXCGUI: hXCGUI);
var
  i, n: Integer;
  hChild: XCGUI.HXCGUI;
begin
  if XC_IsSViewExtend(hXCGUI) then
    TScrollBarUI.ApplyDefault(hXCGUI);
  if XC_IsHWINDOW(hXCGUI) then
  begin
    n := XWnd_GetChildCount(hXCGUI);
    for i := 0 to n - 1 do
    begin
      hChild := XWnd_GetChildByIndex(hXCGUI, i);
      ApplyDefaultStyles(hChild);
    end;
  end
  else if XC_IsHELE(hXCGUI) then
  begin
    n := XEle_GetChildCount(hXCGUI);
    for i := 0 to n - 1 do
    begin
      hChild := XEle_GetChildByIndex(hXCGUI, i);
      ApplyDefaultStyles(hChild);
    end;
  end;
end;

procedure ClampWindowBoundsToWorkArea(var ALeft, ATop, AWidth, AHeight: Integer);
var
  workRect: TRect;
begin
  AWidth := Max(AWidth, 640);
  AHeight := Max(AHeight, 420);

  workRect := TRect.Create(GetSystemMetrics(SM_XVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN), GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN), GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN));
  if workRect.IsEmpty then
    workRect := TRect.Create(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));

  AWidth := Min(AWidth, workRect.Width);
  AHeight := Min(AHeight, workRect.Height);
  ALeft := EnsureRange(ALeft, workRect.Left, workRect.Right - AWidth);
  ATop := EnsureRange(ATop, workRect.Top, workRect.Bottom - AHeight);
end;

procedure RestoreMainWindowBounds(AWnd: HWINDOW);
var
  L, T, W, H: Integer;
begin
  if TAppConfig.TryGetMainWindowBounds(L, T, W, H) then
  begin
    ClampWindowBoundsToWorkArea(L, T, W, H);
    XWnd_SetWindowPos(AWnd, 0, L, T, W, H, SWP_NOZORDER or SWP_NOACTIVATE);
  end;
  if TAppConfig.IsMainWindowMaximized then
    XWnd_MaxWindow(AWnd, True);
end;

procedure SaveMainWindowBounds(AWnd: HWINDOW);
var
  rc: TRect;
  hWndReal: Windows.HWND;
  wp: TWindowPlacement;
  isMaximized: Boolean;
begin
  if not XC_IsHWINDOW(AWnd) then
    Exit;
  hWndReal := XWnd_GetHWND(AWnd);
  wp.length := SizeOf(TWindowPlacement);
  if GetWindowPlacement(hWndReal, wp) then
  begin
    rc := wp.rcNormalPosition;
    isMaximized := (wp.showCmd = SW_SHOWMAXIMIZED)
      or ((wp.showCmd = SW_SHOWMINIMIZED) and ((wp.flags and WPF_RESTORETOMAXIMIZED) <> 0));
  end
  else
  begin
    if IsIconic(hWndReal) then
      Exit;
    isMaximized := IsZoomed(hWndReal);
    XWnd_GetRect(AWnd, rc);
  end;

  TAppConfig.SetMainWindowBounds(rc.Left, rc.Top, rc.Right - rc.Left, rc.Bottom - rc.Top);
  TAppConfig.SetMainWindowMaximized(isMaximized);
  TAppConfig.Save;
end;

end.
