unit UI_ListView;

interface

uses
  Windows, SysUtils, Math, XCGUI, XListview, UI_PopupMenu, UI_Theme, ListItemTypes;

const
  ID_LISTVIEW_MENU_OPEN = 101;
  ID_LISTVIEW_MENU_EDIT = 102;
  ID_LISTVIEW_MENU_DELETE = 103;
  ID_LISTVIEW_MENU_OPEN_FOLDER = 104;
  ID_LISTVIEW_MENU_ADD_FILE = 105;
  ID_LISTVIEW_MENU_ADD_FOLDER = 106;
  ID_LISTVIEW_MENU_RUN_AS_ADMIN = 107;

type
  TListViewSortKind = (lvskTitle, lvskAddTime, lvskFileType);

  TListViewUI = class(TXListView)
  private
    FItems: array of TListViewFileItem;
    FItemCount: Integer;
    FActiveGroupIndex: Integer;
    FItemWidth: Integer;
    FIconCacheDirectory: string;
    FFileTypeIconDirectory: string;
    /// <summary>上次已对可见项批量重建 DisplayImage 的图标边长；边长未变时 Ctrl+滚轮不重复重采样。</summary>
    FLastVisibleDisplayIconSide: Integer;
    FWheelLayoutDirty: Boolean;
    FWheelLayoutLastRefreshTick: Cardinal;
    procedure ApplyItemSize;
    procedure ReleaseVisibleDisplayImages;
    procedure InvalidateVisibleDisplayIfIconSideChanged;
    procedure FlushWheelLayoutRefresh;
    procedure ApplyItemWidthFromWheel(const AWidth: Integer);
    procedure ReleaseListItemDisplay(var AItem: TListViewFileItem);
    function CalcIconSideForItemWidth(AItemW: Integer): Integer;
    procedure EnsureItemFileImage(AIndex: Integer);
    procedure EnsureItemDisplayImage(AIndex, AIconSide: Integer);
    class function OnPaint(hEle: HELE; hDraw: HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewDrawItem(hEle: HELE; hDraw: HDRAW; var pItem: TlistView_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewButtonDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewMouseWheel(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewKeyUp(hEle: HELE; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewRButtonUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    /// <summary>
    /// 设置当前视图项宽度（会自动限制到允许范围并立即刷新显示尺寸）。
    /// </summary>
    /// <param name="AWidth">目标项宽度。</param>
    /// <remarks>建议搭配分类保存逻辑一起使用，这样重启后可恢复用户上次大小。</remarks>
    procedure SetItemWidth(const AWidth: Integer);
    /// <summary>
    /// 获取当前视图项宽度。
    /// </summary>
    /// <returns>当前生效的项宽度。</returns>
    function GetItemWidth: Integer;
    procedure SetIconCachePaths(const AIconCacheDirectory, AFileTypeIconDirectory: string);
    procedure ClearItems;
    function AddItemFromData(const AItem: TListViewFileItem; ASelect: Boolean = True): Integer;
    /// <summary>批量追加条目：一次扩容并只调用一次 SetVirtualItemCount（分类切换/搜索加载用）。</summary>
    procedure AddItemsFromData(const AItems: array of TListViewFileItem);
    function DeleteItemAt(const AIndex: Integer): Boolean;
    function UpdateItemAt(const AIndex: Integer; const AItem: TListViewFileItem): Boolean;
    function TryGetSelectedItem(out AGroup, AIndex: Integer; out AItem: TListViewFileItem): Boolean;
    procedure SetActiveGroupIndex(const AGroupIndex: Integer);
    function GetActiveGroupIndex: Integer;
    /// <summary>按名称、添加顺序或扩展名重排当前内存中的条目（不修改数据库顺序）。</summary>
    procedure SortItems(const AKind: TListViewSortKind; const AAscending: Boolean);
    /// <summary>按 XListView_GetVisibleItemRange 仅为可见项预建 DisplayImage（切换分组后调用）。</summary>
    procedure RefreshVisibleItems;
    destructor Destroy; override;
  end;

implementation

uses
  ShellOpenWith, ShellHelper, D2D1;

const
  cItemWidthMin = 60;
  cItemWidthMax = 256;
  cItemWidthDefault = 130;
  cWheelResizeLayoutIntervalMs = 48;

function CalcItemHeightFromWidth(const AW: Integer): Integer;
var
  iconSide: Integer;
begin
  iconSide := Min(Max(AW - 8, 32), 240);
  Result := iconSide + 42;
end;

procedure TListViewUI.ReleaseListItemDisplay(var AItem: TListViewFileItem);
begin
  if XC_GetObjectType(AItem.DisplayImage) = XC_IMAGE then
    XImage_Release(AItem.DisplayImage);
  AItem.DisplayImage := 0;
  AItem.DisplayIconSide := -1;
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

procedure TListViewUI.EnsureItemFileImage(AIndex: Integer);
var
  cachePaths: TShellIconCachePaths;
  img: HIMAGE;
  iconCacheOut: string;
begin
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;
  if XC_GetObjectType(FItems[AIndex].FileImage) = XC_IMAGE then
    Exit;

  cachePaths.IconCacheDirectory := FIconCacheDirectory;
  cachePaths.FileTypeIconDirectory := FFileTypeIconDirectory;
  img := AcquireListItemFileImage(FItems[AIndex].IconCachePath, FItems[AIndex].FilePath,
    cachePaths, iconCacheOut);
  if img = 0 then
    Exit;
  FItems[AIndex].FileImage := img;
  if iconCacheOut <> '' then
    FItems[AIndex].IconCachePath := iconCacheOut;
end;

procedure TListViewUI.EnsureItemDisplayImage(AIndex, AIconSide: Integer);
var
  cachePaths: TShellIconCachePaths;
  pngPath, displayKey: string;
  img: HIMAGE;
  iconCacheOut: string;
begin
  if (AIndex < 0) or (AIndex >= FItemCount) or (AIconSide <= 0) then
    Exit;
  if (FItems[AIndex].DisplayIconSide = AIconSide) and
     (XC_GetObjectType(FItems[AIndex].DisplayImage) = XC_IMAGE) then
    Exit;

  ReleaseListItemDisplay(FItems[AIndex]);

  displayKey := GetListItemDisplayImageCacheKey(FItems[AIndex].IconCachePath,
    FItems[AIndex].FilePath);
  if (displayKey <> '') and TryAcquireSharedDisplayImage(displayKey, AIconSide, img) then
  begin
    FItems[AIndex].DisplayImage := img;
    FItems[AIndex].DisplayIconSide := AIconSide;
    Exit;
  end;

  cachePaths.IconCacheDirectory := FIconCacheDirectory;
  cachePaths.FileTypeIconDirectory := FFileTypeIconDirectory;
  pngPath := ResolveListItemIconFilePath(FItems[AIndex].IconCachePath,
    FItems[AIndex].FilePath, cachePaths);
  if (pngPath = '') or (not FileExists(pngPath)) then
  begin
    img := AcquireListItemFileImage(FItems[AIndex].IconCachePath, FItems[AIndex].FilePath,
      cachePaths, iconCacheOut);
    if img = 0 then
      Exit;
    if iconCacheOut <> '' then
      FItems[AIndex].IconCachePath := iconCacheOut;
    if XC_GetObjectType(FItems[AIndex].FileImage) <> XC_IMAGE then
      FItems[AIndex].FileImage := img
    else
      XImage_Release(img);
    displayKey := GetListItemDisplayImageCacheKey(FItems[AIndex].IconCachePath,
      FItems[AIndex].FilePath);
    if (displayKey <> '') and TryAcquireSharedDisplayImage(displayKey, AIconSide, img) then
    begin
      FItems[AIndex].DisplayImage := img;
      FItems[AIndex].DisplayIconSide := AIconSide;
      Exit;
    end;
    pngPath := ResolveListItemIconFilePath(FItems[AIndex].IconCachePath,
      FItems[AIndex].FilePath, cachePaths);
  end;
  if (pngPath = '') or (not FileExists(pngPath)) then
    Exit;

  img := ResampleIconFileToHImage(pngPath, AIconSide, AIconSide);
  if img = 0 then
    Exit;
  XImage_EnableAutoDestroy(img, False);
  if displayKey <> '' then
    PutSharedDisplayImage(displayKey, AIconSide, img);
  if (displayKey <> '') and TryAcquireSharedDisplayImage(displayKey, AIconSide, img) then
  begin
    FItems[AIndex].DisplayImage := img;
    FItems[AIndex].DisplayIconSide := AIconSide;
    Exit;
  end;
  FItems[AIndex].DisplayImage := img;
  FItems[AIndex].DisplayIconSide := AIconSide;
end;

procedure TListViewUI.ReleaseVisibleDisplayImages;
var
  g1, g2, startGrp, startItm, endGrp, endItm, i: Integer;
begin
  if not IsHELE then
    Exit;
  XListView_GetVisibleItemRange(Handle, g1, g2, startGrp, startItm, endGrp, endItm);
  if (startItm < 0) or (endItm < startItm) then
    Exit;
  for i := startItm to endItm do
    if i < FItemCount then
      ReleaseListItemDisplay(FItems[i]);
end;

procedure TListViewUI.InvalidateVisibleDisplayIfIconSideChanged;
var
  iconSide: Integer;
begin
  iconSide := CalcIconSideForItemWidth(FItemWidth);
  if iconSide = FLastVisibleDisplayIconSide then
    Exit;
  FLastVisibleDisplayIconSide := iconSide;
  ReleaseVisibleDisplayImages;
  ClearListDisplayImageCache;
end;

procedure TListViewUI.FlushWheelLayoutRefresh;
begin
  FWheelLayoutDirty := False;
  if not IsHELE then
    Exit;
  RefreshData;
  XEle_Redraw(Handle);
end;

procedure TListViewUI.ApplyItemWidthFromWheel(const AWidth: Integer);
var
  NewWidth: Integer;
  nowTick: Cardinal;
begin
  NewWidth := EnsureRange(AWidth, cItemWidthMin, cItemWidthMax);
  if NewWidth = FItemWidth then
    Exit;
  FItemWidth := NewWidth;
  ApplyItemSize;
  InvalidateVisibleDisplayIfIconSideChanged;
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
  g1, g2, startGrp, startItm, endGrp, endItm, i, iconSide: Integer;
begin
  if not IsHELE then
    Exit;
  iconSide := CalcIconSideForItemWidth(FItemWidth);
  XListView_GetVisibleItemRange(Handle, g1, g2, startGrp, startItm, endGrp, endItm);
  if (startItm < 0) or (endItm < startItm) then
    Exit;
  for i := startItm to endItm do
    if i < FItemCount then
      EnsureItemDisplayImage(i, iconSide);
end;

procedure TListViewUI.SetIconCachePaths(const AIconCacheDirectory, AFileTypeIconDirectory: string);
begin
  FIconCacheDirectory := AIconCacheDirectory;
  FFileTypeIconDirectory := AFileTypeIconDirectory;
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
  NewWidth := EnsureRange(AWidth, cItemWidthMin, cItemWidthMax);
  if NewWidth = FItemWidth then
    Exit;
  FItemWidth := NewWidth;
  ApplyItemSize;
  InvalidateVisibleDisplayIfIconSideChanged;
  RefreshData;
  XEle_Redraw(Handle);
end;

function TListViewUI.GetItemWidth: Integer;
begin
  Result := FItemWidth;
end;

procedure TListViewUI.ClearItems;
const
  cGroup = 0;
var
  i, n: Integer;
  hImg: HIMAGE;
begin
  // 释放每个条目持有的图片资源，避免内存/句柄泄漏
  n := Length(FItems);
  for i := 0 to n - 1 do
  begin
    ReleaseListItemDisplay(FItems[i]);
    hImg := FItems[i].FileImage;
    if XC_GetObjectType(hImg) = XC_IMAGE then
      XImage_Release(hImg);
    FItems[i].FileImage := 0;
  end;
  SetLength(FItems, 0);
  FItemCount := 0;
  FActiveGroupIndex := -1;
  FLastVisibleDisplayIconSide := -1;
  FWheelLayoutDirty := False;

  if IsHELE then
    SetVirtualItemCount(cGroup, 0);
end;

procedure TListViewUI.Init;
begin
  inherited;
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
  RegEvent(XE_KEYUP, @TListViewUI.OnListViewKeyUp);
  RegEvent(XE_RBUTTONUP, @TListViewUI.OnListViewRButtonUp);
  if FItemWidth <= 0 then
    FItemWidth := cItemWidthDefault;
  FLastVisibleDisplayIconSide := -1;
  SetColumnSpace(8);
  SetRowSpace(8);
  SetGroupHeight(0);
  EnableVirtualTable(True);
  SetItemTemplateXML('Resource\Layout\ListView_Item.xml');
  XListView_CreateAdapter(Handle);
  EnableTemplateReuse(True);
  Group_AddItemText('', -1);
  // Adapter/模板就绪后再应用一次尺寸，避免首次显示时尺寸未落地
  ApplyItemSize;
end;

function TListViewUI.AddItemFromData(const AItem: TListViewFileItem; ASelect: Boolean): Integer;
const
  cGroup = 0;
begin
  AddItemsFromData([AItem]);
  Result := FItemCount - 1;
  if ASelect then
    SetSelectItem(cGroup, Result);
end;

procedure TListViewUI.AddItemsFromData(const AItems: array of TListViewFileItem);
const
  cGroup = 0;
var
  n, i, j, maxOrd, startIdx: Integer;
  it: TListViewFileItem;
begin
  n := Length(AItems);
  if n = 0 then
    Exit;

  maxOrd := -1;
  for j := 0 to FItemCount - 1 do
    if FItems[j].InsertOrder > maxOrd then
      maxOrd := FItems[j].InsertOrder;

  startIdx := FItemCount;
  SetLength(FItems, FItemCount + n);
  for i := 0 to n - 1 do
  begin
    it := AItems[i];
    it.DisplayImage := 0;
    it.DisplayIconSide := -1;
    if it.InsertOrder < 0 then
    begin
      Inc(maxOrd);
      it.InsertOrder := maxOrd;
    end;
    FItems[startIdx + i] := it;
  end;
  FItemCount := startIdx + n;
  SetVirtualItemCount(cGroup, FItemCount);
end;

function TListViewUI.DeleteItemAt(const AIndex: Integer): Boolean;
const
  cGroup = 0;
var
  i: Integer;
  hImg: HIMAGE;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;

  ReleaseListItemDisplay(FItems[AIndex]);
  hImg := FItems[AIndex].FileImage;
  if XC_GetObjectType(hImg) = XC_IMAGE then
  begin
    XImage_Release(hImg);
    FItems[AIndex].FileImage := 0;
  end;

  for i := AIndex to FItemCount - 2 do
    FItems[i] := FItems[i + 1];
  Dec(FItemCount);
  SetLength(FItems, FItemCount);
  SetVirtualItemCount(cGroup, FItemCount);
  Result := True;
end;

function TListViewUI.UpdateItemAt(const AIndex: Integer; const AItem: TListViewFileItem): Boolean;
var
  oldImg, newImg: HIMAGE;
  keptOrder: Integer;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;

  keptOrder := FItems[AIndex].InsertOrder;

  ReleaseListItemDisplay(FItems[AIndex]);
  // 若替换了图片句柄，释放旧句柄，避免泄漏；不替换则沿用原句柄
  oldImg := FItems[AIndex].FileImage;
  newImg := AItem.FileImage;
  if (newImg <> oldImg) and (XC_GetObjectType(oldImg) = XC_IMAGE) then
    XImage_Release(oldImg);

  FItems[AIndex] := AItem;
  FItems[AIndex].InsertOrder := keptOrder;
  FItems[AIndex].DisplayImage := 0;
  FItems[AIndex].DisplayIconSide := -1;
  Result := True;
end;

function TListViewUI.TryGetSelectedItem(out AGroup, AIndex: Integer; out AItem: TListViewFileItem): Boolean;
begin
  Result := False;
  if not GetSelectItem(AGroup, AIndex) then
    Exit;
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;
  AItem := FItems[AIndex];
  Result := True;
end;

procedure TListViewUI.SetActiveGroupIndex(const AGroupIndex: Integer);
begin
  FActiveGroupIndex := AGroupIndex;
end;

function TListViewUI.GetActiveGroupIndex: Integer;
begin
  Result := FActiveGroupIndex;
end;

procedure TListViewUI.SortItems(const AKind: TListViewSortKind; const AAscending: Boolean);
const
  cGroup = 0;

  function ItemFileTypeSortKey(const R: TListViewFileItem): string;
  begin
    if R.FilePath = '' then
      Result := ''
    else if SysUtils.DirectoryExists(R.FilePath) then
      Result := #1
    else
      Result := LowerCase(ExtractFileExt(R.FilePath));
  end;

  function CompareRows(const A, B: TListViewFileItem): Integer;
  var
    c: Integer;
  begin
    case AKind of
      lvskTitle:
        c := CompareText(ListViewItemDisplayTitle(A), ListViewItemDisplayTitle(B));
      lvskAddTime:
        c := A.InsertOrder - B.InsertOrder;
      lvskFileType:
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
    i, j: Integer;
    pivot: TListViewFileItem;
    tmp: TListViewFileItem;
  begin
    i := L;
    j := R;
    pivot := FItems[(L + R) shr 1];
    repeat
      while CompareRows(FItems[i], pivot) < 0 do
        Inc(i);
      while CompareRows(pivot, FItems[j]) < 0 do
        Dec(j);
      if i <= j then
      begin
        tmp := FItems[i];
        FItems[i] := FItems[j];
        FItems[j] := tmp;
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
begin
  if FItemCount <= 1 then
    Exit;

  selPath := '';
  if GetSelectItem(grp, selIdx) and (selIdx >= 0) and (selIdx < FItemCount) then
    selPath := FItems[selIdx].FilePath;

  QuickSortRange(0, FItemCount - 1);

  if selPath <> '' then
  begin
    for i := 0 to FItemCount - 1 do
      if SameText(FItems[i].FilePath, selPath) then
      begin
        SetSelectItem(cGroup, i);
        Break;
      end;
  end;

  RefreshData;
  XEle_Redraw(Handle);
end;

class function TListViewUI.OnListViewDrawItem(hEle: hEle; hDraw: hDraw; var pItem: TlistView_item_; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
  Title: string;
  hImg: HIMAGE;
  rc, rcText, rcBg: TRect;
  nItemW, x, y: Integer;
  cIconSide, drawW, drawH: Integer;
  hItemFont: HFONTX;
  useDisplayImg: Boolean;
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
  useDisplayImg := False;
  cIconSide := ListView.CalcIconSideForItemWidth(ListView.FItemWidth);
  if pItem.iItem < ListView.FItemCount then
  begin
    Title := ListViewItemDisplayTitle(ListView.FItems[pItem.iItem]);
    ListView.EnsureItemDisplayImage(pItem.iItem, cIconSide);
    useDisplayImg := XC_GetObjectType(ListView.FItems[pItem.iItem].DisplayImage) = XC_IMAGE;
    if useDisplayImg then
      hImg := ListView.FItems[pItem.iItem].DisplayImage
    else
    begin
      ListView.EnsureItemFileImage(pItem.iItem);
      hImg := ListView.FItems[pItem.iItem].FileImage;
    end;
  end;

  rc := pItem.rcItem;
  nItemW := rc.Right - rc.Left;
  x := rc.Left + (nItemW - cIconSide) div 2;
  y := rc.Top + 4;

  rcText := rc;
  rcText.Top := y + cIconSide + 4;
  rcText.Bottom := rc.Bottom - 2;
  hItemFont := XRes_GetFont('YaHei_9');
  rcBg := rc;

  if pItem.nState = list_item_state_select then
  begin
    XDraw_SetBrushColor(hDraw, UITheme_SurfaceSelected);
    XDraw_FillRoundRect(hDraw, rcBg, 6, 6);
  end
  else if pItem.nState = list_item_state_stay then
  begin
    XDraw_SetBrushColor(hDraw, UITheme_SurfaceHover);
    XDraw_FillRoundRect(hDraw, rcBg, 6, 6);
  end;

  if XC_GetObjectType(hImg) = XC_IMAGE then
  begin
    drawW := XImage_GetWidth(hImg);
    drawH := XImage_GetHeight(hImg);
    if (drawW <= 0) or (drawH <= 0) then
    begin
      drawW := cIconSide;
      drawH := cIconSide;
    end
    else if not useDisplayImg then
    begin
      if (drawW > cIconSide) or (drawH > cIconSide) then
        if drawW >= drawH then
        begin
          drawH := MulDiv(drawH, cIconSide, drawW);
          drawW := cIconSide;
        end
        else                                                                                                                                                                                                                                                                                                                         
        begin
          drawW := MulDiv(drawW, cIconSide, drawH);
          drawH := cIconSide;
        end;
    end;
    if not useDisplayImg then
      XDraw_EnableSmoothingMode(hDraw, True);
    XDraw_ImageEx(hDraw, hImg, x + (cIconSide - drawW) div 2, y + (cIconSide - drawH) div 2, drawW, drawH);
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
  if not XListView_HitTestOffset(hEle, pPt, grp, itm) then
    pbHandled^ := True;
end;

class function TListViewUI.OnListViewKeyUp(hEle: HELE; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TListViewUI;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  if (ListView = nil) or (wParam <> VK_CONTROL) then
    Exit;
  if ListView.FWheelLayoutDirty then
    ListView.FlushWheelLayoutRefresh;
end;

class function TListViewUI.OnListViewMouseWheel(hEle: hEle; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
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

class function TListViewUI.OnListViewRButtonUp(hEle: hEle; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  Menu: TPopupMenuUI;
  ListView: TListViewUI;
  grp, itm: Integer;
  filePath: string;
begin
  Result := 0;
  ListView := TListViewUI(XEle_GetUserData(hEle));
  Menu := TPopupMenuUI.Create(hEle);
  try
    ShellOpenWithResetMenuState;
    if XListView_HitTestOffset(hEle, pPt, grp, itm) then
    begin
      Menu.AddItem(ID_LISTVIEW_MENU_OPEN, '打开', 0);
      filePath := '';
      if (ListView <> nil) and (itm >= 0) and (itm < ListView.FItemCount) then
        filePath := ListView.FItems[itm].FilePath;
      if SameText(ExtractFileExt(filePath), '.exe') then
        Menu.AddItemShieldIcon(ID_LISTVIEW_MENU_RUN_AS_ADMIN, '以管理员身份运行', 0, 0);
      Menu.AddItem(ID_LISTVIEW_MENU_OPEN_FOLDER, UI_Utf8Src(UTF8String('打开所在目录')));
        
      if (ListView <> nil) and (itm >= 0) and (itm < ListView.FItemCount) then
        ShellOpenWithAppendContextMenuItems(Menu, ListView.FItems[itm].FilePath);
      Menu.AddItem(0, '', 0, menu_item_flag_separator);
      Menu.AddItemIcon(ID_LISTVIEW_MENU_EDIT, '修改', 0, 'Resource\menu_edit.svg', 0);
      Menu.AddItem(ID_LISTVIEW_MENU_DELETE, '删除');
      Menu.AddItem(0, '', 0, menu_item_flag_separator);
    end;
    Menu.AddItem(ID_LISTVIEW_MENU_ADD_FILE, '添加文件');
    Menu.AddItem(ID_LISTVIEW_MENU_ADD_FOLDER, UI_Utf8Src(UTF8String('添加文件夹')));
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
    RemoveEvent(XE_PAINT, @TListViewUI.OnPaint);
  ClearItems;
  inherited;
end;

end.

