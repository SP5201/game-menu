unit UI_ListView;

interface

uses
  Windows, SysUtils, Math, XCGUI, XListview, UI_PopupMenu, UI_Theme, ListItemTypes, LibraryStore, SearchVM;

type
  TListViewUI = class;

  { XListView_GetVisibleItemRange 完整出参：Group1/2=可视组标题范围，Start/End=可视项起止组与项索引。 }
  TListViewVisibleItemRange = record
    Group1: Integer;
    Group2: Integer;
    StartGroup: Integer;
    StartItem: Integer;
    EndGroup: Integer;
    EndItem: Integer;
  end;

  TListViewUI = class(TXListView)
  public type
    TPrepareContextMenuEvent = procedure(ASender: TListViewUI; AMenu: TPopupMenuUI; AItemIndex: Integer;
      const AFilePath: string);
    TItemWidthChangedEvent = procedure(ASender: TListViewUI; AWidth: Integer);
    TListViewItemActivateEvent = procedure(ASender: TListViewUI; AItemIndex: Integer);
  private
    { 元数据与 MainWindow.CListFilterSourceItems 共享；图标在 FFileImages。 }
    FSourceItems: TListViewFileItemArray;  // 常与 MainWindow.CListFilterSourceItems 共享引用
    FRowMap: array of Integer;
    FFileImages: array of HIMAGE;
    FItemCount: Integer;
    FItemWidth: Integer;
    FItemCornerRadius: Integer;
    FListGeneration: Cardinal;
    FScrollGeneration: Cardinal;
    FIconPending: array of Boolean;
    FOnPrepareContextMenu: TPrepareContextMenuEvent;
    FOnItemWidthChanged: TItemWidthChangedEvent;
    FOnItemActivate: TListViewItemActivateEvent;
    FWheelLayoutDirty: Boolean;
    FWheelLayoutLastRefreshTick: Cardinal;
    FCachedIconSide: Integer;   // 缓存的图标边长（与 FItemWidth 关联，无效时=-1）
    FCachedItemFont: HFONTX;    // 缓存的绘制字体句柄
    FColumnSpace: Integer;      // 列间距缓存（用于键盘行导航计算）
    FRowSpace: Integer;         // 行间距缓存（用于项矩形估算与可见范围）
    FPlhFolder: HIMAGE;         // Init 预热的三类占位图（绘制只读，不写入 FileImage）
    FPlhApp: HIMAGE;
    FPlhFile: HIMAGE;
    FSearchMode: Boolean;
    FSearchHitIndices: TSearchHitIndexArray;
    function SourceIndex(ADisplayIndex: Integer): Integer;
    function SearchHitAt(ADisplayIndex: Integer): Integer;
    procedure BuildSearchListItem(AHitIndex, ADisplayOrder: Integer; out AItem: TListViewFileItem);
    function ResolveItemFilePath(ADisplayIndex: Integer; const AItem: TListViewFileItem): string;
    procedure GetItemAt(ADisplayIndex: Integer; out AItem: TListViewFileItem);
    function ItemFileImage(ADisplayIndex: Integer): HIMAGE;
    procedure SetItemFileImage(ADisplayIndex: Integer; AImage: HIMAGE);
    function ItemRecord(ADisplayIndex: Integer): PListViewFileItem;
    procedure ReleaseAllFileImages;
    procedure ApplyDisplayMap(const ARowMap: array of Integer; ASourceCount: Integer);
    function ClampItemWidth(AWidth: Integer): Integer;
    procedure NotifyItemWidthChanged;
    procedure ApplyItemSize;
    procedure EnsureIconPendingLength;
    procedure FetchVisibleItemRange(out ARange: TListViewVisibleItemRange);
    function TryEstimateVisibleItemRange(out AStartIdx, AEndIdx: Integer): Boolean;
    function ResolveVisibleItemRange(out AStartIdx, AEndIdx: Integer): Boolean;
    function IsItemIndexVisible(AIndex: Integer): Boolean;
    function TryGetItemClientRect(AIndex: Integer; out ARect: TRect): Boolean;
    function TryApplyCachedIcon(AIndex: Integer): Boolean;
    function PrimeVisibleIconsAfterBind: Boolean;
    procedure RequestVisibleRealIcon(AIndex: Integer);
    procedure ReleaseOffScreenItemImages;
    procedure ClearAllIconPendingFlags;
    procedure PropagateIconForSamePath(const AFilePath, AIconCachePathOut: string; ASourceImg: HIMAGE);
    procedure OnScrollMoving(const ARefreshIconsImmediately: Boolean);
    procedure ScheduleScrollIdleIconRefresh;
    procedure OnScrollIdleIconRefresh;
    procedure BindScrollRefreshEvents;
    procedure FlushWheelLayoutRefresh;
    procedure ApplyItemWidthFromWheel(const AWidth: Integer);
    function CalcIconSideForItemWidth(AItemW: Integer): Integer;
    class function OnPaint(hEle: HELE; hDraw: HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewDrawItem(hEle: HELE; hDraw: HDRAW; var pItem: TlistView_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewButtonDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewMouseWheel(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnScrollViewScrollV(hEle: HELE; AScrollPos: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnScrollViewScrollH(hEle: HELE; AScrollPos: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnScrollBarScroll(hEle: HELE; AScrollPos: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnEleXCTimer(hEle: HELE; nTimerID: UINT; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewKeyDown(hEle: HELE; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewRButtonUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewLButtonDBClick(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    /// <summary>
    /// 设置当前视图项宽度（会自动限制到允许范围并立即刷新显示尺寸）。
    /// </summary>
    /// <param name="AWidth">目标项宽度。</param>
    /// <remarks>宽度全部分组共用；持久化由 OnItemWidthChanged 交给窗口层（如 AppConfig）。</remarks>
    procedure SetItemWidth(const AWidth: Integer);
    /// <summary>
    /// 获取当前视图项宽度。
    /// </summary>
    /// <returns>当前生效的项宽度。</returns>
    function GetItemWidth: Integer;
    function GetItemCount: Integer;
    function TryGetItem(AIndex: Integer; out AItem: TListViewFileItem): Boolean;
    property OnPrepareContextMenu: TPrepareContextMenuEvent read FOnPrepareContextMenu write FOnPrepareContextMenu;
    property OnItemWidthChanged: TItemWidthChangedEvent read FOnItemWidthChanged write FOnItemWidthChanged;
    property OnItemActivate: TListViewItemActivateEvent read FOnItemActivate write FOnItemActivate;
    procedure ApplyIconLoadResult(AListGeneration, AScrollGeneration: Cardinal; AIndex: Integer;
      const AFilePath, AIconCachePathOut, APixelKey: string; AFromCache: Boolean; ACachedImage: HIMAGE);
    procedure ClearItems;
    /// <summary>绑定外部条目数组并刷新虚表（零拷贝共享元数据；ARowMap 为空表示 0..N-1 顺序显示）。</summary>
    procedure BindItems(var ASource: TListViewFileItemArray; const ARowMap: array of Integer;
      ABulkPlaceholdersOnly: Boolean = True);
    /// <summary>绑定搜索命中下标数组（O(1)，不拼路径；ARowMap 为空表示顺序显示全部命中）。</summary>
    procedure BindSearchHits(var AHitIndices: TSearchHitIndexArray; const ARowMap: array of Integer;
      ABulkPlaceholdersOnly: Boolean = True);
    /// <summary>增量刷新搜索命中（保留滚动位置，不重新触发搜索/排序）。</summary>
    procedure RefreshSearchHits(var AHitIndices: TSearchHitIndexArray; const ARowMap: array of Integer);
    function IsSearchMode: Boolean;
    function GetSearchHitIndex(ADisplayIndex: Integer): Integer;
    function ResolveSearchItemPath(ADisplayIndex: Integer): string;
    /// <summary>源数组物理顺序已与当前显示一致后，将行映射重置为恒等（排序写回源后调用）。</summary>
    procedure ResetRowMapIdentity;
    function UpdateItemAt(const AIndex: Integer; const AItem: TListViewFileItem): Boolean;
    function TryGetSelectedItem(out AGroup, AIndex: Integer; out AItem: TListViewFileItem): Boolean;
    /// <summary>按名称、添加顺序或扩展名重排当前内存中的条目（不修改数据库顺序）。</summary>
    procedure SortItems(const AKind: TLibraryListSortKind; const AAscending: Boolean);
    /// <summary>应用列表网格间距、项圆角与滚动条样式。</summary>
    procedure ApplyLayoutSettings(const AColumnSpace, ARowSpace, AItemCornerRadius, AScrollBarSize,
      AScrollSliderMinLen, AScrollThumbRadius: Integer);
    /// <summary>仅为可见项：绘制占位 → 内存缓存 → 异步真实图标（FileImage=0 时绘制占位，加载后写入 FileImage）。</summary>
    procedure RefreshVisibleItems;
    destructor Destroy; override;
  end;

implementation

uses
  D2D1, AppConfig, UI_ScrollBar, ShellIconHelper, ShellIconLoader, EverythingIndex;

const
  cWheelResizeLayoutIntervalMs = 64;
  cListViewScrollIdleTimerId = 902;
  cListViewScrollIdleMs = 80;
  cListDataGroup = 0;

function TListViewUI.SourceIndex(ADisplayIndex: Integer): Integer;
begin
  if (ADisplayIndex < 0) or (ADisplayIndex >= FItemCount) then
    Exit(-1);
  if Length(FRowMap) > 0 then
    Result := FRowMap[ADisplayIndex]
  else
    Result := ADisplayIndex;
end;

function TListViewUI.SearchHitAt(ADisplayIndex: Integer): Integer;
var
  srcIdx: Integer;
begin
  srcIdx := SourceIndex(ADisplayIndex);
  if (srcIdx < 0) or (srcIdx >= Length(FSearchHitIndices)) then
    Exit(0);
  Result := FSearchHitIndices[srcIdx];
end;

procedure TListViewUI.BuildSearchListItem(AHitIndex, ADisplayOrder: Integer; out AItem: TListViewFileItem);
var
  fileName: string;
begin
  FillChar(AItem, SizeOf(AItem), 0);
  fileName := EverythingIndexGetHitFileName(AHitIndex);
  AItem.FileName := fileName;
  AItem.DisplayTitle := fileName;
  AItem.InsertOrder := ADisplayOrder;
  AItem.ItemGroupIndex := -1;
  AItem.ShowCmd := SW_SHOWNORMAL;
end;

function TListViewUI.ResolveItemFilePath(ADisplayIndex: Integer; const AItem: TListViewFileItem): string;
begin
  Result := Trim(AItem.FilePath);
  if Result <> '' then
    Exit;
  if not FSearchMode then
    Exit;
  Result := EverythingIndexGetHitPath(SearchHitAt(ADisplayIndex));
end;

function TListViewUI.IsSearchMode: Boolean;
begin
  Result := FSearchMode;
end;

function TListViewUI.GetSearchHitIndex(ADisplayIndex: Integer): Integer;
begin
  if not FSearchMode then
    Exit(0);
  Result := SearchHitAt(ADisplayIndex);
end;

function TListViewUI.ResolveSearchItemPath(ADisplayIndex: Integer): string;
var
  item: TListViewFileItem;
begin
  Result := '';
  if not FSearchMode then
    Exit;
  if (ADisplayIndex < 0) or (ADisplayIndex >= FItemCount) then
    Exit;
  GetItemAt(ADisplayIndex, item);
  Result := ResolveItemFilePath(ADisplayIndex, item);
end;

function TListViewUI.ItemRecord(ADisplayIndex: Integer): PListViewFileItem;
var
  srcIdx: Integer;
begin
  srcIdx := SourceIndex(ADisplayIndex);
  if srcIdx < 0 then
    Result := nil
  else
    Result := @FSourceItems[srcIdx];
end;

procedure TListViewUI.GetItemAt(ADisplayIndex: Integer; out AItem: TListViewFileItem);
var
  srcIdx: Integer;
begin
  FillChar(AItem, SizeOf(AItem), 0);
  if FSearchMode then
  begin
    if (ADisplayIndex < 0) or (ADisplayIndex >= FItemCount) then
      Exit;
    BuildSearchListItem(SearchHitAt(ADisplayIndex), ADisplayIndex, AItem);
    if (ADisplayIndex >= 0) and (ADisplayIndex < Length(FFileImages)) then
      AItem.FileImage := FFileImages[ADisplayIndex];
    Exit;
  end;
  srcIdx := SourceIndex(ADisplayIndex);
  if srcIdx < 0 then
    Exit;
  AItem := FSourceItems[srcIdx];
  if (ADisplayIndex >= 0) and (ADisplayIndex < Length(FFileImages)) then
    AItem.FileImage := FFileImages[ADisplayIndex];
end;

function TListViewUI.ItemFileImage(ADisplayIndex: Integer): HIMAGE;
begin
  if (ADisplayIndex >= 0) and (ADisplayIndex < Length(FFileImages)) then
    Result := FFileImages[ADisplayIndex]
  else
    Result := 0;
end;

procedure TListViewUI.SetItemFileImage(ADisplayIndex: Integer; AImage: HIMAGE);
begin
  if (ADisplayIndex >= 0) and (ADisplayIndex < Length(FFileImages)) then
    FFileImages[ADisplayIndex] := AImage;
end;

procedure TListViewUI.ReleaseAllFileImages;
var
  i: Integer;
begin
  for i := 0 to Length(FFileImages) - 1 do
  begin
    if XC_GetObjectType(FFileImages[i]) = XC_IMAGE then
      XImage_Release(FFileImages[i]);
    FFileImages[i] := 0;
  end;
  SetLength(FFileImages, 0);
end;

procedure TListViewUI.ApplyDisplayMap(const ARowMap: array of Integer; ASourceCount: Integer);
var
  i, n: Integer;
begin
  n := Length(ARowMap);
  if n > 0 then
  begin
    SetLength(FRowMap, n);
    for i := 0 to n - 1 do
      FRowMap[i] := ARowMap[i];
    FItemCount := n;
  end
  else
  begin
    { 空映射由 SourceIndex 按显示下标直通源数组，避免大批量搜索时构建恒等映射。 }
    SetLength(FRowMap, 0);
    FItemCount := ASourceCount;
  end;
end;

procedure CalcListItemIconDrawSize(AImgW, AImgH, ASlotSide: Integer; out ADrawW, ADrawH: Integer);
begin
  if (AImgW <= 0) or (AImgH <= 0) then
  begin
    ADrawW := ASlotSide;
    ADrawH := ASlotSide;
    Exit;
  end;
  if (AImgW <= ASlotSide) and (AImgH <= ASlotSide) then
  begin
    ADrawW := AImgW;
    ADrawH := AImgH;
    Exit;
  end;
  if AImgW >= AImgH then
  begin
    ADrawW := ASlotSide;
    ADrawH := Max(1, AImgH * ASlotSide div AImgW);
  end
  else
  begin
    ADrawH := ASlotSide;
    ADrawW := Max(1, AImgW * ASlotSide div AImgH);
  end;
end;

function TListViewUI.ClampItemWidth(AWidth: Integer): Integer;
begin
  Result := TAppConfig.ClampListItemWidth(AWidth);
end;

procedure TListViewUI.NotifyItemWidthChanged;
begin
  if Assigned(FOnItemWidthChanged) then
    FOnItemWidthChanged(Self, FItemWidth);
end;

procedure TListViewUI.EnsureIconPendingLength;
begin
  if Length(FIconPending) < FItemCount then
    SetLength(FIconPending, FItemCount);
end;

procedure TListViewUI.FetchVisibleItemRange(out ARange: TListViewVisibleItemRange);
begin
  FillChar(ARange, SizeOf(ARange), 0);
  ARange.StartItem := -1;
  ARange.EndItem := -1;
  if not IsHELE then
    Exit;
  inherited GetVisibleItemRange(ARange.Group1, ARange.Group2, ARange.StartGroup, ARange.StartItem,
    ARange.EndGroup, ARange.EndItem);
end;

function CalcItemHeightFromWidth(const AW: Integer): Integer;
var
  iconSide: Integer;
begin
  iconSide := Min(Max(AW - 8, 32), 240);
  Result := iconSide + 42;
end;

function TListViewUI.TryEstimateVisibleItemRange(out AStartIdx, AEndIdx: Integer): Boolean;
var
  clientRc: TRect;
  itemSz: TSize;
  scrollX, scrollY, clientW, clientH, cols, cellW, cellH: Integer;
  firstRow, lastRow: Integer;
begin
  Result := False;
  AStartIdx := -1;
  AEndIdx := -1;
  if (FItemCount <= 0) or (not IsHELE) then
    Exit;
  XEle_GetClientRect(Handle, clientRc);
  itemSz := GetItemSize;
  if itemSz.cx <= 0 then
    itemSz.cx := FItemWidth;
  if itemSz.cy <= 0 then
    itemSz.cy := CalcItemHeightFromWidth(itemSz.cx);
  if (itemSz.cx <= 0) or (itemSz.cy <= 0) then
    Exit;
  scrollX := XSView_GetViewPosH(Handle);
  scrollY := XSView_GetViewPosV(Handle);
  clientW := clientRc.Right - clientRc.Left;
  clientH := clientRc.Bottom - clientRc.Top;
  if (clientW <= 0) or (clientH <= 0) then
    Exit;
  cellW := itemSz.cx + FColumnSpace;
  cellH := itemSz.cy + FRowSpace;
  if (cellW <= 0) or (cellH <= 0) then
    Exit;
  cols := Max(1, clientW div cellW);
  if scrollY < 0 then
    firstRow := 0
  else
    firstRow := scrollY div cellH;
  lastRow := (scrollY + clientH + cellH - 1) div cellH;
  AStartIdx := firstRow * cols;
  AEndIdx := ((lastRow + 1) * cols) - 1;
  if scrollX > 0 then
  begin
    Inc(AStartIdx, scrollX div cellW);
    Inc(AEndIdx, scrollX div cellW);
  end;
  if AStartIdx < 0 then
    AStartIdx := 0;
  if AEndIdx >= FItemCount then
    AEndIdx := FItemCount - 1;
  Result := AEndIdx >= AStartIdx;
end;

function TListViewUI.ResolveVisibleItemRange(out AStartIdx, AEndIdx: Integer): Boolean;
var
  vis: TListViewVisibleItemRange;
begin
  Result := False;
  AStartIdx := -1;
  AEndIdx := -1;
  if (FItemCount <= 0) or (not IsHELE) then
    Exit;
  FetchVisibleItemRange(vis);
  if (vis.StartItem >= 0) and (vis.EndItem >= vis.StartItem) and
    (vis.StartGroup = cListDataGroup) and (vis.EndGroup = cListDataGroup) then
  begin
    if (vis.Group1 < 0) or (vis.Group2 < 0) or
      ((vis.Group1 <= cListDataGroup) and (vis.Group2 >= cListDataGroup)) then
    begin
      AStartIdx := vis.StartItem;
      AEndIdx := vis.EndItem;
      if AStartIdx < FItemCount then
      begin
        if AEndIdx >= FItemCount then
          AEndIdx := FItemCount - 1;
        Exit(AEndIdx >= AStartIdx);
      end;
    end;
  end;
  Result := TryEstimateVisibleItemRange(AStartIdx, AEndIdx);
end;

function TListViewUI.IsItemIndexVisible(AIndex: Integer): Boolean;
var
  startIdx, endIdx: Integer;
begin
  Result := False;
  if not ResolveVisibleItemRange(startIdx, endIdx) then
    Exit;
  Result := (AIndex >= startIdx) and (AIndex <= endIdx);
end;

function TListViewUI.GetItemWidth: Integer;
begin
  Result := FItemWidth;
end;

function TListViewUI.GetItemCount: Integer;
begin
  Result := FItemCount;
end;

function TListViewUI.TryGetItem(AIndex: Integer; out AItem: TListViewFileItem): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < FItemCount);
  if not Result then
    Exit;
  GetItemAt(AIndex, AItem);
end;

function TListViewUI.TryApplyCachedIcon(AIndex: Integer): Boolean;
var
  itemRec: PListViewFileItem;
  img, oldImg: HIMAGE;
  resolvedCachePath, filePath: string;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;
  if FSearchMode then
  begin
    filePath := ResolveSearchItemPath(AIndex);
    if filePath = '' then
      Exit;
    if IsListFileImageLoadFailed('', filePath) then
      Exit(True);
    if XC_GetObjectType(ItemFileImage(AIndex)) = XC_IMAGE then
      Exit(True);
    img := 0;
    resolvedCachePath := '';
    if not TryAcquireMemoryCachedListFileImage('', filePath, img, resolvedCachePath) then
      Exit;
    if XC_GetObjectType(img) <> XC_IMAGE then
      Exit;
    oldImg := ItemFileImage(AIndex);
    if oldImg = img then
    begin
      XImage_Release(img);
      Exit(True);
    end;
    if XC_GetObjectType(oldImg) = XC_IMAGE then
      XImage_Release(oldImg);
    SetItemFileImage(AIndex, img);
    EnsureIconPendingLength;
    FIconPending[AIndex] := False;
    Exit(True);
  end;
  itemRec := ItemRecord(AIndex);
  if itemRec = nil then
    Exit;
  if IsListFileImageLoadFailed(itemRec^.IconCachePath, itemRec^.FilePath) then
    Exit(True);
  if XC_GetObjectType(ItemFileImage(AIndex)) = XC_IMAGE then
    Exit(True);
  img := 0;
  resolvedCachePath := '';
  if not TryAcquireMemoryCachedListFileImage(itemRec^.IconCachePath, itemRec^.FilePath, img,
    resolvedCachePath) then
    Exit;
  if XC_GetObjectType(img) <> XC_IMAGE then
    Exit;
  oldImg := ItemFileImage(AIndex);
  if oldImg = img then
  begin
    XImage_Release(img);
    Exit(True);
  end;
  if XC_GetObjectType(oldImg) = XC_IMAGE then
    XImage_Release(oldImg);
  if (resolvedCachePath <> '') and (Trim(itemRec^.IconCachePath) = '') then
    itemRec^.IconCachePath := resolvedCachePath;
  SetItemFileImage(AIndex, img);
  EnsureIconPendingLength;
  FIconPending[AIndex] := False;
  Result := True;
end;

function TListViewUI.PrimeVisibleIconsAfterBind: Boolean;
var
  startIdx, endIdx, i: Integer;
begin
  Result := ResolveVisibleItemRange(startIdx, endIdx);
  if not Result then
    Exit;
  for i := startIdx to endIdx do
    TryApplyCachedIcon(i);
  for i := startIdx to endIdx do
    if XC_GetObjectType(ItemFileImage(i)) <> XC_IMAGE then
      RequestVisibleRealIcon(i);
end;

procedure TListViewUI.RequestVisibleRealIcon(AIndex: Integer);
var
  itemRec: PListViewFileItem;
  filePath: string;
begin
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;
  if not IsItemIndexVisible(AIndex) then
    Exit;
  if FSearchMode then
  begin
    filePath := ResolveSearchItemPath(AIndex);
    if filePath = '' then
      Exit;
    if IsListFileImageLoadFailed('', filePath) then
      Exit;
    if XC_GetObjectType(ItemFileImage(AIndex)) = XC_IMAGE then
      Exit;
    EnsureIconPendingLength;
    if FIconPending[AIndex] then
      Exit;
    if not ShellIconLoaderRequestItem(FListGeneration, FScrollGeneration, Handle, AIndex,
      filePath, '', False) then
      Exit;
    FIconPending[AIndex] := True;
    Exit;
  end;
  itemRec := ItemRecord(AIndex);
  if itemRec = nil then
    Exit;
  if IsListFileImageLoadFailed(itemRec^.IconCachePath, itemRec^.FilePath) then
    Exit;
  if XC_GetObjectType(ItemFileImage(AIndex)) = XC_IMAGE then
    Exit;
  EnsureIconPendingLength;
  if FIconPending[AIndex] then
    Exit;
  if not ShellIconLoaderRequestItem(FListGeneration, FScrollGeneration, Handle, AIndex,
    itemRec^.FilePath, itemRec^.IconCachePath, False) then
    Exit;
  FIconPending[AIndex] := True;
end;

function TListViewUI.TryGetItemClientRect(AIndex: Integer; out ARect: TRect): Boolean;
var
  clientRc: TRect;
  itemSz: TSize;
  scrollX, scrollY, clientW, cols, col, row, cellW, cellH: Integer;
begin
  Result := False;
  FillChar(ARect, SizeOf(ARect), 0);
  if not IsHELE or (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;
  XEle_GetClientRect(Handle, clientRc);
  itemSz := GetItemSize;
  if itemSz.cx <= 0 then
    itemSz.cx := FItemWidth;
  if itemSz.cy <= 0 then
    itemSz.cy := CalcItemHeightFromWidth(itemSz.cx);
  if (itemSz.cx <= 0) or (itemSz.cy <= 0) then
    Exit;
  scrollX := XSView_GetViewPosH(Handle);
  scrollY := XSView_GetViewPosV(Handle);
  clientW := clientRc.Right - clientRc.Left;
  cellW := itemSz.cx + FColumnSpace;
  cellH := itemSz.cy + FRowSpace;
  if cellW <= 0 then
    Exit;
  cols := Max(1, clientW div cellW);
  col := AIndex mod cols;
  row := AIndex div cols;
  ARect.Left := clientRc.Left + col * cellW - scrollX;
  ARect.Top := clientRc.Top + row * cellH - scrollY;
  ARect.Right := ARect.Left + itemSz.cx;
  ARect.Bottom := ARect.Top + itemSz.cy;
  Result := (ARect.Right > clientRc.Left) and (ARect.Bottom > clientRc.Top) and
    (ARect.Left < clientRc.Right) and (ARect.Top < clientRc.Bottom);
end;

procedure TListViewUI.ReleaseOffScreenItemImages;
var
  startIdx, endIdx, i: Integer;
  oldImg: HIMAGE;
begin
  if not ResolveVisibleItemRange(startIdx, endIdx) then
    Exit;
  for i := 0 to FItemCount - 1 do
  begin
    if (i >= startIdx) and (i <= endIdx) then
      Continue;
    oldImg := ItemFileImage(i);
    if XC_GetObjectType(oldImg) = XC_IMAGE then
    begin
      XImage_Release(oldImg);
      SetItemFileImage(i, 0);
    end;
  end;
end;

procedure TListViewUI.ClearAllIconPendingFlags;
var
  i: Integer;
begin
  EnsureIconPendingLength;
  for i := 0 to FItemCount - 1 do
    FIconPending[i] := False;
end;

procedure TListViewUI.PropagateIconForSamePath(const AFilePath, AIconCachePathOut: string; ASourceImg: HIMAGE);
var
  i: Integer;
  itemRec: PListViewFileItem;
  imgCopy: HIMAGE;
  rc: TRect;
begin
  if (AFilePath = '') or (XC_GetObjectType(ASourceImg) <> XC_IMAGE) then
    Exit;
  for i := 0 to FItemCount - 1 do
  begin
    itemRec := ItemRecord(i);
    if (itemRec = nil) or (not SameText(itemRec^.FilePath, AFilePath)) then
      Continue;
    if XC_GetObjectType(ItemFileImage(i)) = XC_IMAGE then
      Continue;
    imgCopy := ASourceImg;
    XImage_AddRef(imgCopy);
    if AIconCachePathOut <> '' then
      itemRec^.IconCachePath := AIconCachePathOut;
    SetItemFileImage(i, imgCopy);
    EnsureIconPendingLength;
    FIconPending[i] := False;
    if IsHELE and IsItemIndexVisible(i) and TryGetItemClientRect(i, rc) then
      XEle_RedrawRect(Handle, rc, False);
  end;
end;

procedure TListViewUI.ScheduleScrollIdleIconRefresh;
begin
  if not IsHELE then
    Exit;
  KillXCTimer(cListViewScrollIdleTimerId);
  SetXCTimer(cListViewScrollIdleTimerId, cListViewScrollIdleMs);
end;

procedure TListViewUI.OnScrollIdleIconRefresh;
begin
  if not IsHELE then
    Exit;
  KillXCTimer(cListViewScrollIdleTimerId);
  FScrollGeneration := ShellIconLoaderBumpScrollGeneration;
  ClearAllIconPendingFlags;
  RefreshVisibleItems;
end;

procedure TListViewUI.OnScrollMoving(const ARefreshIconsImmediately: Boolean);
begin
  ReleaseOffScreenItemImages;
  if ARefreshIconsImmediately then
  begin
    FScrollGeneration := ShellIconLoaderBumpScrollGeneration;
    ClearAllIconPendingFlags;
    RefreshVisibleItems;
  end
  else
    ScheduleScrollIdleIconRefresh;
end;

procedure TListViewUI.ApplyIconLoadResult(AListGeneration, AScrollGeneration: Cardinal; AIndex: Integer;
  const AFilePath, AIconCachePathOut, APixelKey: string; AFromCache: Boolean; ACachedImage: HIMAGE);

  procedure FailIconLoad(const ACachePath, AResolvedPath: string);
  begin
    MarkListFileImageLoadFailed(ACachePath, AResolvedPath);
    FIconPending[AIndex] := False;
  end;

var
  itemRec: PListViewFileItem;
  fileImg, oldImg: HIMAGE;
  pixel: TShellIconPixelData;
  rc: TRect;
  resolvedPath, cachePath: string;
begin
  itemRec := nil;
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;
  EnsureIconPendingLength;
  if (AListGeneration <> FListGeneration) or (AScrollGeneration <> FScrollGeneration) then
  begin
    FIconPending[AIndex] := False;
    Exit;
  end;
  if FSearchMode then
  begin
    resolvedPath := ResolveSearchItemPath(AIndex);
    cachePath := '';
  end
  else
  begin
    itemRec := ItemRecord(AIndex);
    if itemRec = nil then
      Exit;
    resolvedPath := itemRec^.FilePath;
    cachePath := itemRec^.IconCachePath;
  end;
  if (AFilePath <> '') and (not SameText(resolvedPath, AFilePath)) then
  begin
    FIconPending[AIndex] := False;
    Exit;
  end;

  if AFromCache then
  begin
    if XC_GetObjectType(ACachedImage) <> XC_IMAGE then
    begin
      FailIconLoad(cachePath, resolvedPath);
      Exit;
    end;
    fileImg := ACachedImage;
    XImage_AddRef(fileImg);
  end
  else
  begin
    if APixelKey = '' then
    begin
      FailIconLoad(cachePath, resolvedPath);
      Exit;
    end;
    if not TakePendingIconPixels(APixelKey, pixel) then
    begin
      FailIconLoad(cachePath, resolvedPath);
      Exit;
    end;
    try
      fileImg := CreateHImageFromPixelData(pixel);
      if fileImg = 0 then
      begin
        FailIconLoad(cachePath, resolvedPath);
        Exit;
      end;
      StoreListFileImageToMemoryCache(cachePath, resolvedPath, pixel, fileImg);
      if XC_GetObjectType(fileImg) <> XC_IMAGE then
      begin
        FailIconLoad(cachePath, resolvedPath);
        Exit;
      end;
    finally
      SetLength(pixel.Bits, 0);
    end;
  end;

  if (not FSearchMode) and (itemRec <> nil) and (AIconCachePathOut <> '') then
    itemRec^.IconCachePath := AIconCachePathOut;

  oldImg := ItemFileImage(AIndex);
  if XC_GetObjectType(oldImg) = XC_IMAGE then
    XImage_Release(oldImg);
  SetItemFileImage(AIndex, fileImg);
  ClearListFileImageLoadFailure(cachePath, resolvedPath);
  FIconPending[AIndex] := False;
  if not FSearchMode then
    PropagateIconForSamePath(resolvedPath, cachePath, fileImg);
  if IsHELE and IsItemIndexVisible(AIndex) then
  begin
    if TryGetItemClientRect(AIndex, rc) then
      XEle_RedrawRect(Handle, rc, False)
    else
      XEle_Redraw(Handle, False);
  end;
end;

function TListViewUI.CalcIconSideForItemWidth(AItemW: Integer): Integer;
var
  itemH: Integer;
begin
  itemH := CalcItemHeightFromWidth(AItemW);
  Result := Min(AItemW - 8, itemH - 32);
  if Result < 24 then
    Result := Min(24, Max(0, AItemW - 8));
end;

procedure TListViewUI.FlushWheelLayoutRefresh;
begin
  FWheelLayoutDirty := False;
  if not IsHELE then
    Exit;
  RefreshVisibleItems;
end;

procedure TListViewUI.ApplyItemWidthFromWheel(const AWidth: Integer);
var
  NewWidth: Integer;
  nowTick: Cardinal;
begin
  NewWidth := ClampItemWidth(AWidth);
  if NewWidth = FItemWidth then
    Exit;
  FItemWidth := NewWidth;
  FCachedIconSide := -1; // 图标边长缓存失效，下次绘制重新计算
  NotifyItemWidthChanged;
  ApplyItemSize;
  FWheelLayoutDirty := True;
  nowTick := GetTickCount;
  if (nowTick - FWheelLayoutLastRefreshTick) >= cWheelResizeLayoutIntervalMs then
  begin
    FWheelLayoutLastRefreshTick := nowTick;
    FlushWheelLayoutRefresh;
  end
  else
    XEle_Redraw(Handle);
end;

procedure TListViewUI.RefreshVisibleItems;
var
  startItm, endItm, i: Integer;
  hadIcon, needsFullRedraw: Boolean;
  rc: TRect;
begin
  if not ResolveVisibleItemRange(startItm, endItm) then
    Exit;
  needsFullRedraw := False;
  for i := startItm to endItm do
  begin
    if i >= FItemCount then
      Continue;
    hadIcon := XC_GetObjectType(ItemFileImage(i)) = XC_IMAGE;
    TryApplyCachedIcon(i);
    if (not hadIcon) and (XC_GetObjectType(ItemFileImage(i)) = XC_IMAGE) then
    begin
      if IsHELE and TryGetItemClientRect(i, rc) then
        XEle_RedrawRect(Handle, rc, False)
      else
        needsFullRedraw := True;
    end;
    if XC_GetObjectType(ItemFileImage(i)) <> XC_IMAGE then
      RequestVisibleRealIcon(i);
  end;
  if IsHELE and needsFullRedraw then
    XEle_Redraw(Handle, False);
end;

procedure TListViewUI.ApplyItemSize;
var
  Sz: TSize;
begin
  Sz.cx := FItemWidth;
  Sz.cy := CalcItemHeightFromWidth(FItemWidth);
  SetItemSize(Sz);
end;

procedure TListViewUI.SetItemWidth(const AWidth: Integer);
var
  NewWidth: Integer;
begin
  if FWheelLayoutDirty then
    FlushWheelLayoutRefresh;
  NewWidth := ClampItemWidth(AWidth);
  if NewWidth = FItemWidth then
    Exit;
  FItemWidth := NewWidth;
  FCachedIconSide := -1; // 图标边长缓存失效
  NotifyItemWidthChanged;
  ApplyItemSize;
  RefreshVisibleItems;
end;

procedure TListViewUI.ClearItems;
begin
  FListGeneration := ShellIconLoaderBumpListGeneration;
  FScrollGeneration := 0;
  ReleaseAllFileImages;
  FSearchMode := False;
  SetLength(FSearchHitIndices, 0);
  SetLength(FSourceItems, 0);
  SetLength(FRowMap, 0);
  SetLength(FIconPending, 0);
  FItemCount := 0;
  FWheelLayoutDirty := False;

  if IsHELE then
  begin
    KillXCTimer(cListViewScrollIdleTimerId);
    SetVirtualItemCount(cListDataGroup, 0);
    XEle_Redraw(Handle);
  end;
end;

procedure TListViewUI.Init;
begin
  inherited;
  FPlhFolder := 0;
  FPlhApp := 0;
  FPlhFile := 0;
  // 启动时一次性预热三类占位图；绘制路径只读 FPlh*，不再触发 Shell IO
  RefListPlaceholderImage(lpkFolder, FPlhFolder);
  RefListPlaceholderImage(lpkApp, FPlhApp);
  RefListPlaceholderImage(lpkFile, FPlhFile);
  XEle_SetUserData(Handle, NativeInt(Self));
  EnableBkTransparent(True);
  EnableDrawBorder(False);
  EnableDrawFocus(False);
  RegEvent(XE_PAINT, @TListViewUI.OnPaint);
  RegEvent(XE_LISTVIEW_DRAWITEM, @TListViewUI.OnListViewDrawItem);
  RegEvent(XE_LBUTTONDOWN, @TListViewUI.OnListViewButtonDown);
  RegEvent(XE_RBUTTONDOWN, @TListViewUI.OnListViewButtonDown);
  RegEvent(XE_MOUSEWHEEL, @TListViewUI.OnListViewMouseWheel);
  EnableEvent_XE_MOUSEWHEEL(True);
  RegEvent(XE_XC_TIMER, @TListViewUI.OnEleXCTimer);
  RegEvent(XE_KEYDOWN, @TListViewUI.OnListViewKeyDown);
  RegEvent(XE_RBUTTONUP, @TListViewUI.OnListViewRButtonUp);
  RegEvent(XE_LBUTTONDBCLICK, @TListViewUI.OnListViewLButtonDBClick);
  if FItemWidth <= 0 then
    FItemWidth := cDefaultListItemWidth;
  FItemCornerRadius := cDefaultListItemCornerRadius;
  FListGeneration := 1;
  FScrollGeneration := 0;
  FCachedIconSide := -1;
  FCachedItemFont := 0;
  FColumnSpace := cDefaultListColumnSpace;
  FRowSpace := cDefaultListRowSpace;
  SetColumnSpace(cDefaultListColumnSpace);
  SetRowSpace(FRowSpace);
  SetGroupHeight(0);
  EnableVirtualTable(True);
  SetItemTemplateXML('Resource\Layout\ListView_Item.xml');
  XListView_CreateAdapter(Handle);
  EnableTemplateReuse(True);
  Group_AddItemText('', -1);
  // Adapter/模板就绪后再应用一次尺寸，避免首次显示时尺寸未落地
  ApplyItemSize;
  TScrollBarUI.ApplyDefault(Handle, cDefaultListScrollSliderMinLen, cDefaultListScrollBarSize,
    cDefaultListScrollThumbRadius);
  BindScrollRefreshEvents;
end;

procedure TListViewUI.BindScrollRefreshEvents;
var
  hSBarV, hSBarH: HELE;
begin
  if not IsHELE then
    Exit;
  RegEvent(XE_SCROLLVIEW_SCROLL_V, @TListViewUI.OnScrollViewScrollV);
  RegEvent(XE_SCROLLVIEW_SCROLL_H, @TListViewUI.OnScrollViewScrollH);
  hSBarV := XSView_GetScrollBarV(Handle);
  if hSBarV > 0 then
  begin
    XEle_SetUserData(hSBarV, NativeInt(Self));
    XEle_RegEvent(hSBarV, XE_SBAR_SCROLL, @TListViewUI.OnScrollBarScroll);
  end;
  hSBarH := XSView_GetScrollBarH(Handle);
  if hSBarH > 0 then
  begin
    XEle_SetUserData(hSBarH, NativeInt(Self));
    XEle_RegEvent(hSBarH, XE_SBAR_SCROLL, @TListViewUI.OnScrollBarScroll);
  end;
end;

procedure TListViewUI.ApplyLayoutSettings(const AColumnSpace, ARowSpace, AItemCornerRadius, AScrollBarSize,
  AScrollSliderMinLen, AScrollThumbRadius: Integer);
begin
  FColumnSpace := TAppConfig.ClampListColumnSpace(AColumnSpace);
  FRowSpace := TAppConfig.ClampListRowSpace(ARowSpace);
  SetColumnSpace(FColumnSpace);
  SetRowSpace(FRowSpace);
  FItemCornerRadius := TAppConfig.ClampListItemCornerRadius(AItemCornerRadius);
  if IsHELE then
  begin
    TScrollBarUI.ApplyDefault(Handle, TAppConfig.ClampListScrollSliderMinLen(AScrollSliderMinLen),
      TAppConfig.ClampListScrollBarSize(AScrollBarSize),
      TAppConfig.ClampListScrollThumbRadius(AScrollThumbRadius));
    XEle_Redraw(Handle);
  end;
end;

procedure TListViewUI.RefreshSearchHits(var AHitIndices: TSearchHitIndexArray; const ARowMap: array of Integer);
var
  i, oldCount: Integer;
begin
  if not FSearchMode then
    Exit;
  FSearchHitIndices := AHitIndices;
  oldCount := FItemCount;
  ApplyDisplayMap(ARowMap, Length(FSearchHitIndices));
  if FItemCount > Length(FFileImages) then
  begin
    SetLength(FFileImages, FItemCount);
    for i := oldCount to FItemCount - 1 do
      FFileImages[i] := 0;
    EnsureIconPendingLength;
  end
  else if FItemCount < Length(FFileImages) then
  begin
    for i := FItemCount to Length(FFileImages) - 1 do
      if XC_GetObjectType(FFileImages[i]) = XC_IMAGE then
        XImage_Release(FFileImages[i]);
    SetLength(FFileImages, FItemCount);
    SetLength(FIconPending, FItemCount);
  end;
  if IsHELE then
  begin
    SetVirtualItemCount(cListDataGroup, FItemCount);
    RefreshVisibleItems;
    XEle_Redraw(Handle);
  end;
end;

procedure TListViewUI.BindSearchHits(var AHitIndices: TSearchHitIndexArray; const ARowMap: array of Integer;
  ABulkPlaceholdersOnly: Boolean);
var
  i: Integer;
  iconsPrimed: Boolean;
begin
  FListGeneration := ShellIconLoaderBumpListGeneration;
  FScrollGeneration := 0;
  FWheelLayoutDirty := False;
  ReleaseAllFileImages;
  FSearchMode := True;
  FSearchHitIndices := AHitIndices;
  SetLength(FSourceItems, 0);
  ApplyDisplayMap(ARowMap, Length(FSearchHitIndices));
  SetLength(FFileImages, FItemCount);
  if FItemCount > 0 then
    FillChar(FFileImages[0], FItemCount * SizeOf(HIMAGE), 0);
  SetLength(FIconPending, FItemCount);
  if FItemCount > 0 then
    FillChar(FIconPending[0], FItemCount * SizeOf(Boolean), 0);
  if IsHELE then
  begin
    SetVirtualItemCount(cListDataGroup, FItemCount);
    if FItemCount > 0 then
      VisibleItem(cListDataGroup, 0)
    else
    begin
      XSView_ScrollPosV(Handle, 0);
      XSView_ScrollPosH(Handle, 0);
    end;
    iconsPrimed := False;
    if ABulkPlaceholdersOnly then
      iconsPrimed := PrimeVisibleIconsAfterBind
    else
      for i := 0 to FItemCount - 1 do
        TryApplyCachedIcon(i);
    XEle_Redraw(Handle);
    if not iconsPrimed then
      ShellIconLoaderScheduleDeferredListRefresh;
  end;
end;

procedure TListViewUI.BindItems(var ASource: TListViewFileItemArray; const ARowMap: array of Integer;
  ABulkPlaceholdersOnly: Boolean);
var
  i: Integer;
  iconsPrimed: Boolean;
begin
  FListGeneration := ShellIconLoaderBumpListGeneration;
  FScrollGeneration := 0;
  FWheelLayoutDirty := False;
  ReleaseAllFileImages;
  FSearchMode := False;
  SetLength(FSearchHitIndices, 0);
  FSourceItems := ASource;
  ApplyDisplayMap(ARowMap, Length(ASource));
  SetLength(FFileImages, FItemCount);
  if FItemCount > 0 then
    FillChar(FFileImages[0], FItemCount * SizeOf(HIMAGE), 0);
  SetLength(FIconPending, FItemCount);
  if FItemCount > 0 then
    FillChar(FIconPending[0], FItemCount * SizeOf(Boolean), 0);

  if IsHELE then
  begin
    SetVirtualItemCount(cListDataGroup, FItemCount);
    if FItemCount > 0 then
      VisibleItem(cListDataGroup, 0)
    else
    begin
      XSView_ScrollPosV(Handle, 0);
      XSView_ScrollPosH(Handle, 0);
    end;
    iconsPrimed := False;
    if ABulkPlaceholdersOnly then
      iconsPrimed := PrimeVisibleIconsAfterBind
    else
      for i := 0 to FItemCount - 1 do
        TryApplyCachedIcon(i);
    XEle_Redraw(Handle);
    if not iconsPrimed then
      ShellIconLoaderScheduleDeferredListRefresh;
  end;
end;

procedure TListViewUI.ResetRowMapIdentity;
var
  i: Integer;
begin
  if FItemCount <= 0 then
  begin
    SetLength(FRowMap, 0);
    Exit;
  end;
  SetLength(FRowMap, FItemCount);
  for i := 0 to FItemCount - 1 do
    FRowMap[i] := i;
end;

function TListViewUI.UpdateItemAt(const AIndex: Integer; const AItem: TListViewFileItem): Boolean;
var
  itemRec: PListViewFileItem;
  oldImg: HIMAGE;
  keptOrder: Integer;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;
  itemRec := ItemRecord(AIndex);
  if itemRec = nil then
    Exit;

  keptOrder := itemRec^.InsertOrder;
  oldImg := ItemFileImage(AIndex);
  itemRec^ := AItem;
  itemRec^.InsertOrder := keptOrder;
  SetItemFileImage(AIndex, 0);
  if XC_GetObjectType(oldImg) = XC_IMAGE then
    XImage_Release(oldImg);
  EnsureIconPendingLength;
  FIconPending[AIndex] := False;
  TryApplyCachedIcon(AIndex);
  Result := True;
end;

function TListViewUI.TryGetSelectedItem(out AGroup, AIndex: Integer; out AItem: TListViewFileItem): Boolean;
begin
  Result := False;
  if not GetSelectItem(AGroup, AIndex) then
    Exit;
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;
  GetItemAt(AIndex, AItem);
  Result := True;
end;

procedure TListViewUI.SortItems(const AKind: TLibraryListSortKind; const AAscending: Boolean);

  function ItemFileTypeSortKey(const R: TListViewFileItem): string;
  var
    ext: string;
  begin
    ext := LowerCase(ExtractFileExt(R.FilePath));
    if R.FilePath = '' then
      Result := ''
    else if ext = '' then
      Result := #1
    else
      Result := ext;
  end;

  function CompareRows(const A, B: TListViewFileItem): Integer;
  var
    c: Integer;
  begin
    case AKind of
      llskName:
        c := CompareText(A.DisplayTitle, B.DisplayTitle);
      llskAddTime:
        c := A.InsertOrder - B.InsertOrder;
      llskFileType:
        c := CompareText(ItemFileTypeSortKey(A), ItemFileTypeSortKey(B));
    else
      c := 0;
    end;
    if c = 0 then
      c := CompareText(A.FilePath, B.FilePath);
    if not AAscending then
      c := -c;
    Result := c;
  end;

  procedure QuickSortRange(L, R: Integer);
  var
    i, j, pivotSrc: Integer;
    pivot: TListViewFileItem;
    tmpMap: Integer;
    tmpImg: HIMAGE;
    tmpPending: Boolean;
  begin
    i := L;
    j := R;
    pivotSrc := FRowMap[(L + R) shr 1];
    pivot := FSourceItems[pivotSrc];
    repeat
      while CompareRows(FSourceItems[FRowMap[i]], pivot) < 0 do
        Inc(i);
      while CompareRows(pivot, FSourceItems[FRowMap[j]]) < 0 do
        Dec(j);
      if i <= j then
      begin
        tmpMap := FRowMap[i];
        FRowMap[i] := FRowMap[j];
        FRowMap[j] := tmpMap;
        tmpImg := FFileImages[i];
        FFileImages[i] := FFileImages[j];
        FFileImages[j] := tmpImg;
        tmpPending := FIconPending[i];
        FIconPending[i] := FIconPending[j];
        FIconPending[j] := tmpPending;
        Inc(i);
        Dec(j);
      end;
    until i > j;
    if L < j then
      QuickSortRange(L, j);
    if i < R then
      QuickSortRange(i, R);
  end;

var
  grp, selIdx, i: Integer;
  selPath: string;
  itemRec: PListViewFileItem;
begin
  if FItemCount <= 1 then
    Exit;
  if FSearchMode then
  begin
    EverythingIndexSortHitIndices(FSearchHitIndices, AKind, AAscending);
    SetLength(FRowMap, 0);
    if IsHELE then
      XEle_Redraw(Handle, False);
    Exit;
  end;
  if (FItemCount > 0) and (Length(FRowMap) < FItemCount) then
    ResetRowMapIdentity;

  EnsureIconPendingLength;

  selPath := '';
  if GetSelectItem(grp, selIdx) and (selIdx >= 0) and (selIdx < FItemCount) then
  begin
    itemRec := ItemRecord(selIdx);
    if itemRec <> nil then
      selPath := itemRec^.FilePath;
  end;

  QuickSortRange(0, FItemCount - 1);

  if selPath <> '' then
  begin
    for i := 0 to FItemCount - 1 do
    begin
      itemRec := ItemRecord(i);
      if (itemRec <> nil) and SameText(itemRec^.FilePath, selPath) then
      begin
        SetSelectItem(cListDataGroup, i);
        Break;
      end;
    end;
  end;

  if IsHELE then
    XEle_Redraw(Handle, False);
end;

class function TListViewUI.OnListViewDrawItem(hEle: hEle; hDraw: hDraw; var pItem: TlistView_item_; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
  itemRec: TListViewFileItem;
  Title: string;
  hImg: HIMAGE;
  rc, rcText, rcBg: TRect;
  nItemW, x, y, slotX, slotY, imgW, imgH, drawW, drawH: Integer;
  cIconSide: Integer;
  hItemFont: HFONTX;
  ext: string;
begin
  Result := 0;
  if pItem.iItem < 0 then
  begin
    pbHandled^ := True;
    Exit;
  end;

  ListView := TListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
  begin
    pbHandled^ := True;
    Exit;
  end;

  Title := '';
  hImg := 0;
  // 使用缓存的图标边长，当 FItemWidth 变化时 FCachedIconSide 被置 -1
  if ListView.FCachedIconSide < 0 then
    ListView.FCachedIconSide := ListView.CalcIconSideForItemWidth(ListView.FItemWidth);
  cIconSide := ListView.FCachedIconSide;
  if pItem.iItem < ListView.FItemCount then
  begin
    ListView.TryGetItem(pItem.iItem, itemRec);
    Title := itemRec.DisplayTitle;
    if XC_GetObjectType(itemRec.FileImage) = XC_IMAGE then
      hImg := itemRec.FileImage
    else if ListView.FSearchMode and EverythingIndexHitIsFolder(ListView.SearchHitAt(pItem.iItem)) then
      hImg := ListView.FPlhFolder
    else
    begin
      ext := LowerCase(Trim(ExtractFileExt(itemRec.FilePath)));
      if (ext = '') and ListView.FSearchMode then
        ext := LowerCase(Trim(EverythingIndexGetHitExtension(ListView.SearchHitAt(pItem.iItem))));
      if ListPathLeafName(itemRec.FilePath) = '' then
      begin
        if ListView.FSearchMode and EverythingIndexHitIsFolder(ListView.SearchHitAt(pItem.iItem)) then
          hImg := ListView.FPlhFolder
        else
          hImg := ListView.FPlhFile;
      end
      else if (ext = '') or (ext = '.') then
        hImg := ListView.FPlhFile
      else if ext = '.exe' then
        hImg := ListView.FPlhApp
      else
        hImg := ListView.FPlhFile;
    end;
  end;

  rc := pItem.rcItem;
  nItemW := rc.Right - rc.Left;
  slotX := rc.Left + (nItemW - cIconSide) div 2;
  slotY := rc.Top + 4;

  rcText := rc;
  rcText.Top := slotY + cIconSide + 4;
  rcText.Bottom := rc.Bottom - 2;
  if ListView.FCachedItemFont = 0 then
    ListView.FCachedItemFont := XRes_GetFont('YaHei_9');
  hItemFont := ListView.FCachedItemFont;
  rcBg := rc;

  if pItem.nState = list_item_state_select then
  begin
    XDraw_SetBrushColor(hDraw, UITheme_SurfaceSelected);
    if ListView.FItemCornerRadius > 0 then
      XDraw_FillRoundRect(hDraw, rcBg, ListView.FItemCornerRadius, ListView.FItemCornerRadius);
  end
  else if pItem.nState = list_item_state_stay then
  begin
    XDraw_SetBrushColor(hDraw, UITheme_SurfaceHover);
    if ListView.FItemCornerRadius > 0 then
      XDraw_FillRoundRect(hDraw, rcBg, ListView.FItemCornerRadius, ListView.FItemCornerRadius);
  end;

  if XC_GetObjectType(hImg) = XC_IMAGE then
  begin
    imgW := XImage_GetWidth(hImg);
    imgH := XImage_GetHeight(hImg);
    CalcListItemIconDrawSize(imgW, imgH, cIconSide, drawW, drawH);
    x := slotX + (cIconSide - drawW) div 2;
    y := slotY + (cIconSide - drawH) div 2;
    XDraw_EnableSmoothingMode(hDraw, True);
    XDraw_ImageEx(hDraw, hImg, x, y, drawW, drawH);
  end;

  XDraw_SetFont(hDraw, hItemFont);
  XDraw_SetBrushColor(hDraw, UITheme_TextPrimary);
  XDraw_SetTextAlign(hDraw, textAlignFlag_center or textAlignFlag_top);
  XDraw_DrawText(hDraw, PWideChar(Title), -1, rcText);

  pbHandled^ := True;
end;

class function TListViewUI.OnListViewButtonDown(hEle: hEle; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  grp, itm: Integer;
begin
  Result := 0;
  // 点空白区域时吞掉按下，避免误触底层或穿透到父容器
  if not XListView_HitTestOffset(hEle, pPt, grp, itm) then
    pbHandled^ := True;
end;

class function TListViewUI.OnListViewKeyDown(hEle: HELE; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
  rc: TRect;
  itemSz: TSize;
  colSpace, clientW, itemsPerRow, grp, cur, target: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
    Exit;

  // Ctrl 键释放时刷布局
  if wParam = VK_CONTROL then
  begin
    if ListView.FWheelLayoutDirty then
      ListView.FlushWheelLayoutRefresh;
    Exit;
  end;

  // 仅处理方向键
  if (wParam <> VK_UP) and (wParam <> VK_DOWN) and (wParam <> VK_LEFT) and (wParam <> VK_RIGHT) then
  begin
    pbHandled^ := False;
    Exit;
  end;

  if not ListView.GetSelectItem(grp, cur) then
    Exit;

  // 计算每行项数
  XEle_GetClientRect(hEle, rc);
  itemSz := ListView.GetItemSize;
  colSpace := ListView.FColumnSpace;
  clientW := rc.Right - rc.Left;
  if (itemSz.cx + colSpace) > 0 then
    itemsPerRow := Max(1, clientW div (itemSz.cx + colSpace))
  else
    itemsPerRow := 1;

  target := cur;
  case wParam of
    VK_LEFT:
      if cur > 0 then
        target := cur - 1;
    VK_RIGHT:
      if cur < ListView.FItemCount - 1 then
        target := cur + 1;
    VK_UP:
      if cur >= itemsPerRow then
        target := cur - itemsPerRow;
    VK_DOWN:
      if cur + itemsPerRow < ListView.FItemCount then
        target := cur + itemsPerRow;
  end;

  if target <> cur then
  begin
    ListView.SetSelectItem(grp, target);
    XListView_VisibleItem(hEle, grp, target);
    ListView.OnScrollMoving(True);
  end;
end;

class function TListViewUI.OnScrollViewScrollV(hEle: HELE; AScrollPos: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
    Exit;
  ListView.OnScrollMoving(False);
end;

class function TListViewUI.OnScrollViewScrollH(hEle: HELE; AScrollPos: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
    Exit;
  ListView.OnScrollMoving(False);
end;

class function TListViewUI.OnScrollBarScroll(hEle: HELE; AScrollPos: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
    Exit;
  ListView.OnScrollMoving(False);
end;

class function TListViewUI.OnEleXCTimer(hEle: HELE; nTimerID: UINT; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
begin
  Result := 0;
  if nTimerID <> cListViewScrollIdleTimerId then
    Exit;
  pbHandled^ := True;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if ListView <> nil then
    ListView.OnScrollIdleIconRefresh;
end;

class function TListViewUI.OnListViewMouseWheel(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
  delta: SmallInt;
  w: Integer;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
    Exit;

  // Ctrl 以 GetKeyState 为准，避免 MK_CONTROL 粘连导致滚轮一直被当成缩放
  if (GetKeyState(VK_CONTROL) and $8000) = 0 then
  begin
    if ListView.FWheelLayoutDirty then
      ListView.FlushWheelLayoutRefresh;
    ListView.OnScrollMoving(True);
    Exit;
  end;

  delta := SmallInt(HiWord(nFlags));
  if delta = 0 then
    Exit;
  w := ListView.FItemWidth;
  if delta > 0 then
    Inc(w, 8)
  else
    Dec(w, 8);
  if w = ListView.FItemWidth then
    Exit;
  ListView.ApplyItemWidthFromWheel(w);
  pbHandled^ := True;
end;

class function TListViewUI.OnListViewLButtonDBClick(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
  grp, itm: Integer;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
    Exit;
  if not XListView_HitTestOffset(hEle, pPt, grp, itm) then
    Exit;
  if (itm < 0) or (itm >= ListView.FItemCount) then
    Exit;
  ListView.SetSelectItem(grp, itm);
  if Assigned(ListView.FOnItemActivate) then
    ListView.FOnItemActivate(ListView, itm);
  pbHandled^ := True;
end;

class function TListViewUI.OnListViewRButtonUp(hEle: hEle; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  Menu: TPopupMenuUI;
  ListView: TListViewUI;
  grp, itm: Integer;
  filePath: string;
  itemData: TListViewFileItem;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  itm := -1;
  filePath := '';
  if (ListView <> nil) and XListView_HitTestOffset(hEle, pPt, grp, itm) then
  begin
    if (itm < 0) or (itm >= ListView.FItemCount) then
      itm := -1
    else if ListView.TryGetItem(itm, itemData) then
    begin
      filePath := itemData.FilePath;
      if (filePath = '') and ListView.IsSearchMode then
        filePath := ListView.ResolveSearchItemPath(itm);
    end;
  end;
  Menu := TPopupMenuUI.Create(hEle);
  try
    if (ListView <> nil) and Assigned(ListView.FOnPrepareContextMenu) then
      ListView.FOnPrepareContextMenu(ListView, Menu, itm, filePath);
    Menu.Popup(hEle, pPt);
  finally
    Menu.Free;
  end;
end;

class function TListViewUI.OnPaint(hEle: HELE; hDraw: HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
  rc: TRect;
  cx, cy: Integer;
  iconRc: TRect;
  titleRc, descRc: TRect;
  d2dRT: ID2D1RenderTarget;
  d2dFactory: ID2D1Factory;
  d2dBrush: ID2D1SolidColorBrush;
  d2dStrokeStyle: ID2D1StrokeStyle;
  roundedRect: TD2D1RoundedRect;
  ssProp: TD2D1StrokeStyleProperties;
  hr: HResult;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if (ListView = nil) or (ListView.FItemCount > 0) then
    Exit;

  XEle_GetClientRect(hEle, rc);
  XDraw_EnableSmoothingMode(hDraw, True);

  cx := (rc.Left + rc.Right) div 2;
  cy := (rc.Top + rc.Bottom) div 2 - 40;

  // ---- 虚线圆角边框（包裹图标与文字） ----
  if XC_IsEnableD2D then
  begin
    d2dRT := ID2D1RenderTarget(XDraw_GetD2dRenderTarget(hDraw));
    d2dFactory := ID2D1Factory(XC_GetD2dFactory());
    iconRc.Left := cx - 130;
    iconRc.Top := cy - 65;
    iconRc.Right := cx + 130;
    iconRc.Bottom := cy + 110;
    XEle_RectClientToWndClientDPI(hEle, iconRc);

    FillChar(ssProp, SizeOf(ssProp), 0);
    ssProp.startCap := D2D1_CAP_STYLE_FLAT;
    ssProp.endCap := D2D1_CAP_STYLE_FLAT;
    ssProp.dashCap := D2D1_CAP_STYLE_FLAT;
    ssProp.lineJoin := D2D1_LINE_JOIN_MITER;
    ssProp.miterLimit := 10;
    ssProp.dashStyle := D2D1_DASH_STYLE_DASH;
    ssProp.dashOffset := 0;

    hr := d2dFactory.CreateStrokeStyle(ssProp, nil, 0, d2dStrokeStyle);
    if hr >= 0 then
    begin
      hr := d2dRT.CreateSolidColorBrush(
        RGBAToD2D1ColorF(RGBA(255, 255, 255, 80)), nil, d2dBrush);
      if hr >= 0 then
      begin
        roundedRect.rect.left   := iconRc.Left;
        roundedRect.rect.top    := iconRc.Top;
        roundedRect.rect.right  := iconRc.Right;
        roundedRect.rect.bottom := iconRc.Bottom;
        roundedRect.radiusX := 12;
        roundedRect.radiusY := 12;
        d2dRT.DrawRoundedRectangle(roundedRect, d2dBrush, 2, d2dStrokeStyle);
      end;
    end;
  end;

  // ---- 绘制文件夹图标 ----
  // 后层纸张
  iconRc.Left := cx - 14; iconRc.Top := cy - 32;
  iconRc.Right := cx + 10; iconRc.Bottom := cy - 10;
  XDraw_SetBrushColor(hDraw, RGBA(255, 255, 255, 20));
  XDraw_FillRoundRect(hDraw, iconRc, 2, 2);

  // 文件夹主体
  iconRc.Left := cx - 22; iconRc.Top := cy - 18;
  iconRc.Right := cx + 22; iconRc.Bottom := cy + 18;
  XDraw_SetBrushColor(hDraw, RGBA(255, 255, 255, 32));
  XDraw_FillRoundRect(hDraw, iconRc, 5, 5);

  // 文件夹盖
  iconRc.Left := cx - 22; iconRc.Top := cy - 26;
  iconRc.Right := cx + 2; iconRc.Bottom := cy - 12;
  XDraw_SetBrushColor(hDraw, RGBA(255, 255, 255, 38));
  XDraw_FillRoundRect(hDraw, iconRc, 3, 3);

  // 闪电
  XDraw_SetLineWidth(hDraw, 2);
  XDraw_SetBrushColor(hDraw, RGBA(255, 255, 255, 255));
  XDraw_DrawLine(hDraw, cx - 2, cy - 6, cx + 6, cy - 6);
  XDraw_DrawLine(hDraw, cx + 6, cy - 6, cx - 4, cy + 6);
  XDraw_DrawLine(hDraw, cx - 4, cy + 6, cx + 6, cy + 6);
  XDraw_DrawLine(hDraw, cx + 6, cy + 6, cx - 4, cy + 18);

  // ---- 绘制文字 ----
  cy := cy + 40;

  titleRc.Left := rc.Left; titleRc.Top := cy;
  titleRc.Right := rc.Right; titleRc.Bottom := cy + 28;
  XDraw_SetFont(hDraw, XRes_GetFont('YaHei_15_Bold'));
  XDraw_SetBrushColor(hDraw, UITheme_TextPrimary);
  XDraw_SetTextAlign(hDraw, textAlignFlag_center or textAlignFlag_top);
  XDraw_DrawText(hDraw, '您可以将文件拖动到这', -1, titleRc);

  Inc(cy, 28);
  descRc.Left := rc.Left; descRc.Top := cy;
  descRc.Right := rc.Right; descRc.Bottom := cy + 22;
  XDraw_SetFont(hDraw, XRes_GetFont('YaHei_11'));
  XDraw_SetBrushColor(hDraw, RGBA(200, 200, 200, 200));
  XDraw_SetTextAlign(hDraw, textAlignFlag_center or textAlignFlag_top);
  XDraw_DrawText(hDraw, '支持 .exe、快捷方式和文件夹', -1, descRc);

  pbHandled^ := True;
end;

destructor TListViewUI.Destroy;
begin
  if IsHELE then
  begin
    KillXCTimer(cListViewScrollIdleTimerId);
    RemoveEvent(XE_PAINT, @TListViewUI.OnPaint);
    RemoveEvent(XE_XC_TIMER, @TListViewUI.OnEleXCTimer);
  end;
  ClearItems;
  if XC_GetObjectType(FPlhFolder) = XC_IMAGE then
    XImage_Release(FPlhFolder);
  if XC_GetObjectType(FPlhApp) = XC_IMAGE then
    XImage_Release(FPlhApp);
  if XC_GetObjectType(FPlhFile) = XC_IMAGE then
    XImage_Release(FPlhFile);
  inherited;
end;

end.

