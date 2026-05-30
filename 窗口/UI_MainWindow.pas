unit UI_MainWindow;

interface

uses
  Windows, Messages, SysUtils, Classes, ShellAPI, XCGUI, UI_Form, UI_Button,
  UI_ListBox, UI_ListView, UI_SidebarGrip, UI_MessageBox, UI_SearchBox,
  UI_EditItemDialog, UI_CategoryDialog, LibraryStore, ListItemTypes;

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
    { 从数据库加载分类到左侧列表框 }
    class procedure LoadListBoxFromStore;
    { 按指定分组索引加载右侧列表项（含排序与图标） }
    class procedure LoadListViewFromStore(const AGroupIndex: Integer);
    { 全库关键字搜索，结果填入右侧列表（不限制当前分类） }
    class procedure LoadListViewGlobalSearch(const ANeedle: string);
    { 内部：切换分类并加载列表（不经过事件 pbHandled） }
    class procedure ReloadListForCategoryIndex(const iItem: Integer);
    { 拖放前若尚无分类则补一条默认分类并选中 }
    class procedure SyncCategoriesForDrop;
    { 左侧分类切换：保存宽度、加载对应分组条目 }
    class function OnCategorySelect(hEle: HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    { 分类列表右键菜单：增删改分类、设置项等 }
    class function OnCategoryMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    { 主内容列表右键菜单：打开、编辑、删除、添加文件/夹等 }
    class function OnContentMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    { 窗口 WM_DROPFILES：批量拖入文件到当前分组 }
    class function OnWndDropFiles(hWindow: HWINDOW; hDrop: HDROP; pbHandled: PBOOL): Integer; stdcall; static;
    { 主窗口附加消息（WM_QD_STAT_*、关闭前释放模态栈等） }
    class function OnWinProc(hWindow: HWINDOW; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    { 批量插入数据库并刷新列表中已成功的项 }
    class procedure InsertBatchItemsToUI(const AGroupIndex: Integer; const AUIItems: array of TListViewFileItem; const ADBItems: TLibraryItemArray); static;
    { 排序按钮：弹出排序方式菜单 }
    class function OnListSortButtonClick(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    { 安全日志按钮：打开 SafeLog 窗口 }
    class function OnSafeLogButtonClick(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    { 排序菜单选择：写回数据库或仅重排当前搜索结果 }
    class function OnListSortMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    { 搜索按钮：按编辑框关键字全库搜索；空则恢复当前分类列表 }
    class function OnMainSearchButtonClick(Sender: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    { TLibraryListSortKind → TListViewUI.SortItems }
    class procedure ApplyListSort(const AKind: TLibraryListSortKind; const AAsc: Boolean); static;
  protected
    procedure Init; override;
  public
    destructor Destroy; override;
    { 从布局 XML 创建主窗体实例 }
    class function LoadLayout(const LayoutFile: PWideChar): TMainFormUI; reintroduce;
  end;

implementation

uses
  Math, AppConfig, ShellHelper, ShellOpenWith, WeatherFetcher,
  UI_MainWindowHelpers, UI_MainWindowTools, UI_MainWindowStat, UI_PopupMenu,
  NetHttpWorker, UI_SafeLogWindow, SafeLog;

const
  ID_MAIN_LIST_SORT_ASC = 801;
  ID_MAIN_LIST_SORT_DESC = 802;
  ID_MAIN_LIST_SORT_BY_NAME = 803;
  ID_MAIN_LIST_SORT_BY_TIME = 804;
  ID_MAIN_LIST_SORT_BY_FILETYPE = 805;
  cDefaultListItemWidth = 130;

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
      SafeLogRecord(string('批量'), string('插入'), string('批量插入失败，改为逐条插入: ') + E.Message, False);
      insertedCount := 0;
      SetLength(insertedFlags, Length(ADBItems));
      for i := 0 to High(ADBItems) do
      begin
        insertedFlags[i] := CStore.TryInsertItem(AGroupIndex, ADBItems[i].FilePath, ADBItems[i].FileName, ADBItems[i].IconCachePath, ADBItems[i].FileParams, ADBItems[i].WorkingDir);
        if insertedFlags[i] then
          Inc(insertedCount)
        else
          SafeLogRecord(string('批量'), string('插入'), string('逐条插入失败: ') + ADBItems[i].FilePath, False);
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
    CListViewUI.AddItemsFromData(batchItems);
    CListViewUI.Redraw();
  end;
end;

class procedure TMainFormUI.SyncCategoriesForDrop;
var
  i, nList: Integer;
begin
  nList := CListBoxUI.GetCount;
  if nList <= 0 then
  begin
    i := CListBoxUI.AddItem('默认', '');
    SetLength(CGroupMap, 1);
    SetLength(CGroupIconMap, 1);
    CGroupMap[0] := 0;
    CGroupIconMap[0] := '';
    CStore.RenameGroup(0, '默认');
    CStore.UpdateGroup(0, '默认', CGroupIconMap[0]);
    XListBox_SetSelectItem(CListBoxUI.Handle, i);
    XEle_Redraw(CListBoxUI.Handle);
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
    CGroupMap[idx] := groups[i].GroupIndex;
    CGroupIconMap[idx] := iconFile;
  end;
  XListBox_SetSelectItem(CListBoxUI.Handle, 0);
  XEle_Redraw(CListBoxUI.Handle);
end;

class procedure TMainFormUI.ApplyListSort(const AKind: TLibraryListSortKind; const AAsc: Boolean);
begin
  case AKind of
    llskName:
      CListViewUI.SortItems(lvskTitle, AAsc);
    llskAddTime:
      CListViewUI.SortItems(lvskAddTime, AAsc);
    llskFileType:
      CListViewUI.SortItems(lvskFileType, AAsc);
  end;
end;

class procedure TMainFormUI.LoadListViewFromStore(const AGroupIndex: Integer);
var
  items: TLibraryItemArray;
  uiItems: array of TListViewFileItem;
  i: Integer;
  listSortKind: TLibraryListSortKind;
  asc: Boolean;
begin
  CListViewUI.SetItemWidth(CStore.GetGroupItemWidth(AGroupIndex, cDefaultListItemWidth));
  CListViewUI.ClearItems;
  CListViewUI.SetActiveGroupIndex(AGroupIndex);
  items := CStore.LoadItemsByGroup(AGroupIndex);
  SetLength(uiItems, Length(items));
  for i := 0 to High(items) do
    uiItems[i] := LibraryItemToListViewItem(items[i], i, AGroupIndex);
  CListViewUI.AddItemsFromData(uiItems);
  if AGroupIndex >= 0 then
  begin
    CStore.GetGroupListSort(AGroupIndex, listSortKind, asc);
    ApplyListSort(listSortKind, asc);
  end;
  CListViewUI.RefreshVisibleItems;
  CListViewUI.Redraw;
end;

class procedure TMainFormUI.LoadListViewGlobalSearch(const ANeedle: string);
var
  hits: TLibrarySearchHitArray;
  uiItems: array of TListViewFileItem;
  i: Integer;
  sel: Integer;
  iw: Integer;
begin
  sel := CListBoxUI.GetSelectItem;
  iw := cDefaultListItemWidth;
  if (sel >= 0) and (sel < Length(CGroupMap)) then
    iw := CStore.GetGroupItemWidth(CGroupMap[sel], cDefaultListItemWidth);
  CListViewUI.SetItemWidth(iw);
  CListViewUI.ClearItems;
  CListViewUI.SetActiveGroupIndex(-1);
  hits := CStore.SearchLibraryGlobal(WideString(ANeedle));
  SetLength(uiItems, Length(hits));
  for i := 0 to High(hits) do
    uiItems[i] := LibraryItemToListViewItem(hits[i].Item, i, hits[i].GroupIndex);
  CListViewUI.AddItemsFromData(uiItems);
  ApplyListSort(CSearchListSortKind, CSearchListAsc);
  CListViewUI.RefreshVisibleItems;
  CListViewUI.Redraw;
end;

class procedure TMainFormUI.ReloadListForCategoryIndex(const iItem: Integer);
var
  oldGroupIndex: Integer;
begin
  if iItem < 0 then
    Exit;
  oldGroupIndex := CListViewUI.GetActiveGroupIndex;
  if oldGroupIndex >= 0 then
    CStore.UpdateGroupItemWidth(oldGroupIndex, CListViewUI.GetItemWidth)
  else
  begin
    if (iItem >= 0) and (iItem < Length(CGroupMap)) then
      CStore.UpdateGroupItemWidth(CGroupMap[iItem], CListViewUI.GetItemWidth);
  end;
  if iItem < Length(CGroupMap) then
    LoadListViewFromStore(CGroupMap[iItem])
  else
    LoadListViewFromStore(iItem);
end;

class function TMainFormUI.OnCategorySelect(hEle: hEle; iItem: Integer; pbHandled: PBOOL): Integer;
begin
  Result := 0;
  ReloadListForCategoryIndex(iItem);
end;

class function TMainFormUI.OnCategoryMenuSelect(hEle: hEle; nItem: Integer; pbHandled: PBOOL): Integer;
var
  sel, groupIndex, targetGroupIndex: Integer;
  oldName, newName, oldIconFile, iconFile: string;
  needReloadAndReselect: Boolean;
begin
  Result := 0;
  needReloadAndReselect := False;
  targetGroupIndex := -1;

  if nItem = ID_LISTBOX_CATEGORY_ADD then
  begin
    newName := string('新分类');
    iconFile := '';
    if not TCategoryDialogUI.EditCategory(newName, iconFile, '添加分类', '创建', XWidget_GetHWINDOW(CListBoxUI.Handle)) then
      Exit;
    newName := Trim(newName);
    iconFile := NormalizeCategoryIconFile(iconFile);
    if newName = '' then
      Exit;
    groupIndex := CStore.CreateGroup(newName, iconFile);
    targetGroupIndex := groupIndex;
    needReloadAndReselect := True;
  end;

  if nItem = ID_LISTBOX_CATEGORY_EDIT then
  begin
    sel := CListBoxUI.GetSelectItem;
    if (sel < 0) or (sel >= Length(CGroupMap)) then
      Exit;
    oldName := CListBoxUI.GetItemTitle(sel);
    if sel < Length(CGroupIconMap) then
      oldIconFile := CGroupIconMap[sel]
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
    groupIndex := CGroupMap[sel];
    if CStore.UpdateGroup(groupIndex, newName, iconFile) then
    begin
      targetGroupIndex := groupIndex;
      needReloadAndReselect := True;
    end;
  end;

  if nItem = ID_LISTBOX_CATEGORY_DELETE then
  begin
    sel := CListBoxUI.GetSelectItem;
    if (sel < 0) or (sel >= Length(CGroupMap)) then
      Exit;
    oldName := CListBoxUI.GetItemTitle(sel);
    if not TMessageBoxUI.Confirm('删除分类', '确定删除分类 "' + oldName + '" 吗？该分类下的应用也会被删除。', XWidget_GetHWINDOW(CListBoxUI.Handle)) then
      Exit;

    if CStore.DeleteGroup(CGroupMap[sel]) then
    begin
      LoadListBoxFromStore;
      sel := CListBoxUI.GetSelectItem;
      if sel >= 0 then
        ReloadListForCategoryIndex(sel)
      else
        CListViewUI.ClearItems;
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

  if needReloadAndReselect and (targetGroupIndex >= 0) then
  begin
    LoadListBoxFromStore;
    sel := 0;
    while sel < Length(CGroupMap) do
    begin
      if CGroupMap[sel] = targetGroupIndex then
      begin
        XListBox_SetSelectItem(CListBoxUI.Handle, sel);
        ReloadListForCategoryIndex(sel);
        Break;
      end;
      Inc(sel);
    end;
  end;
end;

class function TMainFormUI.OnContentMenuSelect(hEle: hEle; nItem: Integer; pbHandled: PBOOL): Integer;
var
  itm: Integer;
  data: TListViewFileItem;
  groupIndex: Integer;
  fileName: string;
  hOwnerWnd: Integer;
  newTitle, newParams, newWorkDir, iconPath: string;
  activeGroupIndex: Integer;
  folderPath: string;
  grpIdx: Integer;
  dbItems: TLibraryItemArray;
  uiItems: array of TListViewFileItem;
  i: Integer;
  data2: TListViewFileItem;
  pickedFiles: TStringList;
  cachePaths: TShellIconCachePaths;
begin
  pbHandled^ := True;
  Result := 0;
  hOwnerWnd := CListViewUI.HWINDOW;
  cachePaths := GetShellIconCachePaths;
  if ShellOpenWithHandleMenuCommand(nItem, CListViewUI.HWND) then
    Exit;

  if nItem = ID_LISTVIEW_MENU_ADD_FILE then
  begin
    SyncCategoriesForDrop;
    grpIdx := CListViewUI.GetActiveGroupIndex;
    if grpIdx < 0 then
      Exit;
    pickedFiles := TStringList.Create;
    try
      if OpenFileDialogMulti(CListViewUI.HWND, string('添加文件'),
        string('可执行文件 (*.exe)|*.exe|快捷方式 (*.lnk)|*.lnk|所有文件 (*.*)|*.*'), pickedFiles) then
      begin
        SetLength(dbItems, pickedFiles.Count);
        SetLength(uiItems, pickedFiles.Count);
        for i := 0 to pickedFiles.Count - 1 do
        begin
          data2 := GetListViewFileItemFromParsingPath(pickedFiles[i], cachePaths);
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
    grpIdx := CListViewUI.GetActiveGroupIndex;
    if grpIdx < 0 then
      Exit;
    folderPath := '';
    if BrowseForFolderPath(string('添加文件夹'), CListViewUI.HWND, folderPath) then
    begin
      data2 := GetListViewFileItemFromParsingPath(folderPath, cachePaths);
      if CStore.TryInsertItem(grpIdx, data2.FilePath, data2.FileName, data2.IconCachePath, data2.FileParams, data2.WorkingDir) then
      begin
        data2.ItemGroupIndex := grpIdx;
        CListViewUI.AddItemFromData(data2, False);
        CListViewUI.Redraw;
      end;
    end;
    Exit;
  end;

  if not CListViewUI.TryGetSelectedItem(groupIndex, itm, data) then
    Exit;

  if (nItem = ID_LISTVIEW_MENU_OPEN) or (nItem = ID_LISTVIEW_MENU_RUN_AS_ADMIN) then
  begin
    if data.FilePath = '' then
      Exit;
    if nItem = ID_LISTVIEW_MENU_OPEN then
      ShellExecuteDefaultVerb(CListViewUI.HWND, data.FilePath, data.FileParams, data.WorkingDir)
    else if not ShellExecuteRunAs(CListViewUI.HWND, data.FilePath, data.FileParams, data.WorkingDir) then
      MessageBoxW(CListViewUI.HWND, '无法以管理员身份运行该项，请确认路径和权限设置。', '提示', MB_OK or MB_ICONWARNING);
    Exit;
  end;

  if nItem = ID_LISTVIEW_MENU_OPEN_FOLDER then
  begin
    if data.FilePath <> '' then
    begin
      if SysUtils.DirectoryExists(data.FilePath) then
      begin
        ShellExecuteDefaultVerb(CListViewUI.HWND, data.FilePath, '', '');
        Exit;
      end;
      if FileExists(data.FilePath) then
      begin
        if not ShellOpenFolderAndSelectPath(CListViewUI.HWND, data.FilePath) then
          ShellExecuteW(CListViewUI.HWND, 'open', 'explorer.exe', PWideChar(WideString('/select,"' + data.FilePath + '"')), nil, SW_SHOWNORMAL);
        Exit;
      end;
      fileName := ExtractFilePath(data.FilePath);
      if SysUtils.DirectoryExists(fileName) then
      begin
        ShellExecuteDefaultVerb(CListViewUI.HWND, fileName, '', '');
        Exit;
      end;
    end;

    if (data.WorkingDir <> '') and SysUtils.DirectoryExists(data.WorkingDir) then
      ShellExecuteDefaultVerb(CListViewUI.HWND, data.WorkingDir, '', '');
    Exit;
  end;

  if nItem = ID_LISTVIEW_MENU_EDIT then
  begin
    newTitle := data.FileName;
    newParams := data.FileParams;
    newWorkDir := data.WorkingDir;
    if TEditItemDialogUI.EditItem(data.FilePath, data.FileImage, newTitle, newParams, newWorkDir, data.IconCachePath, hOwnerWnd) then
    begin
      activeGroupIndex := CListViewUI.GetActiveGroupIndex;
      if data.ItemGroupIndex >= 0 then
        activeGroupIndex := data.ItemGroupIndex;
      if activeGroupIndex < 0 then
        Exit;

      if CStore.UpdateItem(activeGroupIndex, data.FilePath, newTitle, newParams, newWorkDir) then
      begin
        data.FileName := newTitle;
        data.FileParams := newParams;
        data.WorkingDir := newWorkDir;
        iconPath := ResolveItemIconPath(data.IconCachePath);
        if FileExists(iconPath) then
          data.FileImage := LoadXImageFromFileMemory(iconPath);
        CListViewUI.UpdateItemAt(itm, data);
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

    if not TMessageBoxUI.Confirm(string('删除项'), string('确定要删除') + fileName + string('吗？'), hOwnerWnd) then
      Exit;

    activeGroupIndex := CListViewUI.GetActiveGroupIndex;
    if data.ItemGroupIndex >= 0 then
      activeGroupIndex := data.ItemGroupIndex;
    if activeGroupIndex < 0 then
      Exit;
    if CStore.DeleteItem(activeGroupIndex, data.FilePath) then
    begin
      CListViewUI.DeleteItemAt(itm);
      CListViewUI.Redraw();
    end;
  end;
end;



class function TMainFormUI.OnWndDropFiles(hWindow: hWindow; hDrop: hDrop; pbHandled: PBOOL): Integer;
var
  cnt, nChars: UINT;
  cntInt, i: Integer;
  wpath: string;
  grpIdx: Integer;
  data: TListViewFileItem;
  uiItems: array of TListViewFileItem;
  dbItems: TLibraryItemArray;
  cachePaths: TShellIconCachePaths;
begin
  Result := 0;
  pbHandled^ := True;
  try
    SyncCategoriesForDrop;
    grpIdx := CListViewUI.GetActiveGroupIndex;
    if grpIdx < 0 then
      Exit;

    cachePaths := GetShellIconCachePaths;
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
      data := GetListViewFileItemFromParsingPath(wpath, cachePaths);
      uiItems[i] := data;
      dbItems[i] := ListViewItemToLibraryItem(data);
    end;

    InsertBatchItemsToUI(grpIdx, uiItems, dbItems);
  finally
    DragFinish(hDrop);
  end;
end;

class function TMainFormUI.OnMainSearchButtonClick(Sender: HELE; pbHandled: PBOOL): Integer;
var
  needle: string;
  sel: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  needle := CSearchBox.GetTrimmedText;
  if needle = '' then
  begin
    sel := CListBoxUI.GetSelectItem;
    if sel >= 0 then
      ReloadListForCategoryIndex(sel);
    Exit;
  end;
  LoadListViewGlobalSearch(needle);
end;

class function TMainFormUI.OnWinProc(hWindow: HWINDOW; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  TFormUI.HandleWndSize(hWindow, Msg, wParam);
  if TMainWindowStat.TryHandleWinProc(Msg, wParam, lParam, pbHandled) then
    Exit;
  if Msg = WM_SYSCOMMAND then
  begin
    if (wParam and $FFF0) = SC_CLOSE then
    begin
      TMainWindowStat.StopWorkers;
      TFormUI.ReleaseModalStack;
    end;
  end;
end;

class function TMainFormUI.OnSafeLogButtonClick(hEle: HELE; pbHandled: PBOOL): Integer;
begin
  Result := 0;
  TSafeLogWindow.ShowWindow;
  pbHandled^ := True;
end;

class function TMainFormUI.OnListSortButtonClick(hEle: HELE; pbHandled: PBOOL): Integer;
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
  grp := CListViewUI.GetActiveGroupIndex;
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

class function TMainFormUI.OnListSortMenuSelect(hEle: HELE; nItem: Integer; pbHandled: PBOOL): Integer;
var
  grp: Integer;
  listSortKind: TLibraryListSortKind;
  asc: Boolean;
  isSearchView: Boolean;
begin
  Result := 0;
  pbHandled^ := True;
  grp := CListViewUI.GetActiveGroupIndex;
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
  cachePaths: TShellIconCachePaths;
begin
  inherited;
  try
    CStore := TLibraryStore.Create(TAppConfig.DatabaseFilePath);
    SafeLogStartupAppendStep(string('数据库'), string('加载本地数据库'), True);
    SafeLogStartupCommit;
  except
    on E: Exception do
    begin
      SafeLogStartupAppendStep(string('数据库'), E.Message, False);
      SafeLogStartupCommit;
      raise;
    end;
  end;
  CSearchListSortKind := llskAddTime;
  CSearchListAsc := True;
  RestoreMainWindowBounds(Handle);
  btnUi := TButtonUI.FromXmlName('btn_main_settings', BB_NONE, 'Resource\Settings.svg');
  btnUi.RegEvent(XE_BNCLICK, @MainWindowSettings_OnButtonClick);
  XEle_RegEvent(btnUi.Handle, XE_MENU_SELECT, @MainWindowSettings_OnMenuSelect);
  TButtonUI.FromXmlName('btn_main_min', BB_NONE, 'Resource\min.svg');
  btnUi := TButtonUI.FromXmlName('btn_main_max', BB_NONE, cBtnSvgMax);
  TButtonUI.BindMaxButton(Handle, btnUi.Handle);
  TButtonUI.SyncMaxButtonSvg(Handle);
  TButtonUI.FromXmlName('btn_main_close', BB_NONE, 'Resource\close.svg');
  btnUi := TButtonUI.FromXmlName('btn_main_commonTools', BB_NONE, 'Resource\CommonTools.svg', 16, 16);
  btnUi.RegEvent(XE_BNCLICK, @MainWindowCommonTools_OnButtonClick);
  XEle_RegEvent(btnUi.Handle, XE_MENU_SELECT, @MainWindowCommonTools_OnMenuSelect);
  btnUi := TButtonUI.FromXmlName('btn_main_sysTools', BB_NONE, 'Resource\tools.svg', 16, 16);
  btnUi.RegEvent(XE_BNCLICK, @MainWindowTools_OnButtonClick);
  XEle_RegEvent(btnUi.Handle, XE_MENU_SELECT, @MainWindowTools_OnMenuSelect);
  TButtonUI.FromXmlName('btn_main_notify', BB_NONE, 'Resource\bell.svg', 16, 16).RegEvent(XE_BNCLICK, @TMainFormUI.OnSafeLogButtonClick);
  btnUi := TButtonUI.FromXmlName('btn_main_list_sort', BB_NONE, 'Resource\list_view_sort.svg', 16, 16);
  btnUi.RegEvent(XE_BNCLICK, @TMainFormUI.OnListSortButtonClick);
  XEle_RegEvent(btnUi.Handle, XE_MENU_SELECT, @TMainFormUI.OnListSortMenuSelect);
  btnStatWeather := TButtonUI.FromXmlName('btn_main_stat_weather', BB_NONE, PWideChar(WeatherIconSvgPath(999)), 16, 16).Handle;
  CSearchBox := TSearchBoxUI.FromXml('edit_main_search');
  CSearchBox.RegOnSearchClick(@TMainFormUI.OnMainSearchButtonClick);
  CListBoxUI := TListBoxUI.FromXmlName('list_main_category');
  CListViewUI := TListViewUI.FromXmlName('list_main_content');
  cachePaths := GetShellIconCachePaths;
  CListViewUI.SetIconCachePaths(cachePaths.IconCacheDirectory, cachePaths.FileTypeIconDirectory);
  pGrip := TSidebarGripUI.FromXmlName('layout_main_sidebar_grip');
  pGrip.Attach(XWidget_GetParent(CListBoxUI.Parent), pGrip.HWINDOW);
  CListBoxUI.RegEvent(XE_LISTBOX_SELECT, @TMainFormUI.OnCategorySelect);
  CListBoxUI.RegEvent(XE_MENU_SELECT, @TMainFormUI.OnCategoryMenuSelect);
  CListViewUI.RegEvent(XE_MENU_SELECT, @TMainFormUI.OnContentMenuSelect);
  LoadListBoxFromStore;
  CListBoxUI.SendEvent(XE_LISTBOX_SELECT, 0, 0);
  EnableDragFiles(True);
  RegEvent(WM_DROPFILES, @TMainFormUI.OnWndDropFiles);
  RegEvent(XWM_WINDPROC, @TMainFormUI.OnWinProc);
  ApplyDefaultStyles(Handle);
  TMainWindowStat.Init(Handle, GetCurrentThreadId, btnStatWeather);
end;

destructor TMainFormUI.Destroy;
var
  activeGroupIndex: Integer;
  sel: Integer;
begin
  SaveMainWindowBounds(Handle);
  activeGroupIndex := CListViewUI.GetActiveGroupIndex;
  if activeGroupIndex < 0 then
  begin
    sel := CListBoxUI.GetSelectItem;
    if (sel >= 0) and (sel < Length(CGroupMap)) then
      activeGroupIndex := CGroupMap[sel];
  end;
  if activeGroupIndex >= 0 then
    CStore.UpdateGroupItemWidth(activeGroupIndex, CListViewUI.GetItemWidth);
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

end.

