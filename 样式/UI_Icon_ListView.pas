unit UI_Icon_ListView;

interface

uses
  Windows, SysUtils, XCGUI, XListview, UI_Theme, UI_ScrollBar;

type
  TIconListItemData = record
    SvgHandle: HSVG;
    SvgPath: string;
  end;

  TIconListViewUI = class(TXListView)
  private
    FItems: array of TIconListItemData;
    FItemCount: Integer;
    class function OnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListViewDrawItem(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; var pItem: TlistView_item_; pbHandled: PBOOL): Integer; stdcall; static;
    procedure ReleaseItemData(const AIndex: Integer);
  protected
    procedure Init; override;
  public
    class function FromXmlName(const XmlName: string): TIconListViewUI; reintroduce;
    procedure ClearItems;
    function DeleteItemAt(const AIndex: Integer): Boolean;
    function AddSvgIconItem(const ASvgPath: string; const AColor: Integer = -1): Integer;
    procedure AddSvgIconsFromDir(const ADir: string; const AColor: Integer = -1);
    function FindItemBySvgPath(const ASvgPath: string; out AGroup, AItem: Integer): Boolean;
    function GetSelectedSvgPath(out APath: string): Boolean; overload;
    function GetItemSvgHandle(iGroup, iItem: Integer): HSVG;
    function GetItemSvgPath(iGroup, iItem: Integer): string;
    destructor Destroy; override;
  end;

implementation

const
  ICON_ITEM_SIZE = 30;
  ICON_SIDE_BASE = 20;
  ICON_ITEM_HOVER_ALPHA = 120;
  ICON_ITEM_SELECT_ALPHA = 240;
  ICON_ITEM_HIGHLIGHT_R = 210;
  ICON_ITEM_HIGHLIGHT_G = 27;
  ICON_ITEM_HIGHLIGHT_B = 70;

class function TIconListViewUI.FromXmlName(const XmlName: string): TIconListViewUI;
begin
  Result := TIconListViewUI(inherited FromXmlName(XmlName));
end;

procedure TIconListViewUI.Init;
var
  itemSize: TSize;
begin
  inherited;
  XEle_SetUserData(Handle, NativeInt(Self));
  EnableBkTransparent(True);
  EnableDrawBorder(False);
  EnableDrawFocus(False);
  RegEvent(XE_PAINT, @TIconListViewUI.OnPaint);
  RegEvent(XE_LISTVIEW_DRAWITEM, @TIconListViewUI.OnListViewDrawItem);
  SetColumnSpace(6);
  SetRowSpace(6);
  SetGroupHeight(0);
  EnableVirtualTable(True);
  SetItemTemplateXML('Resource\Layout\IconListView_Item.xml');
  XListView_CreateAdapter(Handle);
  Group_AddItemText('', -1);

  TScrollBarUI.ApplyDefault(Handle);

  itemSize.cx := ICON_ITEM_SIZE;
  itemSize.cy := ICON_ITEM_SIZE;
  SetItemSize(itemSize);
end;

function TIconListViewUI.AddSvgIconItem(const ASvgPath: string; const AColor: Integer = -1): Integer;
const
  cGroup = 0;
var
  hSvg: XCGUI.HSVG;
  colorValue: Integer;
begin
  Result := -1;
  hSvg := XSvg_LoadFile(PWideChar(ASvgPath));
  if XC_SVG <> XC_GetObjectType(hSvg) then
    Exit;

  if AColor = -1 then
    colorValue := UITheme_InputText
  else
    colorValue := AColor;

  XSvg_SetSize(hSvg, ICON_SIDE_BASE, ICON_SIDE_BASE);
  XSvg_SetUserFillColor(hSvg, colorValue, True);
  XSvg_SetUserStrokeColor(hSvg, colorValue, 1, True);

  Result := FItemCount;
  Inc(FItemCount);
  SetLength(FItems, FItemCount);
  FItems[Result].SvgHandle := hSvg;
  FItems[Result].SvgPath :=  ExpandFileName(ASvgPath);

  if IsHELE then
    SetVirtualItemCount(cGroup, FItemCount);
end;

procedure TIconListViewUI.ReleaseItemData(const AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;

  if XC_GetObjectType(FItems[AIndex].SvgHandle) = XC_SVG then
    XSvg_Release(FItems[AIndex].SvgHandle);
  FItems[AIndex].SvgHandle := 0;
  FItems[AIndex].SvgPath := '';
end;

procedure TIconListViewUI.ClearItems;
const
  cGroup = 0;
var
  i: Integer;
begin
  for i := 0 to FItemCount - 1 do
    ReleaseItemData(i);

  SetLength(FItems, 0);
  FItemCount := 0;

  if IsHELE then
    SetVirtualItemCount(cGroup, 0);
end;

function TIconListViewUI.DeleteItemAt(const AIndex: Integer): Boolean;
const
  cGroup = 0;
var
  i: Integer;
begin
  Result := False;
  if (AIndex < 0) or (AIndex >= FItemCount) then
    Exit;

  ReleaseItemData(AIndex);
  for i := AIndex to FItemCount - 2 do
    FItems[i] := FItems[i + 1];

  Dec(FItemCount);
  SetLength(FItems, FItemCount);
  if IsHELE then
    SetVirtualItemCount(cGroup, FItemCount);
  Result := True;
end;

class function TIconListViewUI.OnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  XEle_GetClientRect(hEle, rc);
  XDraw_EnableSmoothingMode(hDraw, True);

  XDraw_SetBrushColor(hDraw, RGBA(255, 255, 255, 0));
  XDraw_FillRect(hDraw, rc);
end;

class function TIconListViewUI.OnListViewDrawItem(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; var pItem: TlistView_item_; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TIconListViewUI;
  rc: TRect;
  hSvg: XCGUI.HSVG;
  svgColor: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  if pItem.iItem < 0 then
    Exit;

  ListView := TIconListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
    Exit;
  if pItem.iItem >= ListView.FItemCount then
    Exit;

  rc := pItem.rcItem;
  XDraw_EnableSmoothingMode(hDraw, True);
  hSvg := ListView.GetItemSvgHandle(pItem.iGroup, pItem.iItem);
  if XC_SVG <> XC_GetObjectType(hSvg) then
    Exit;

  if pItem.nState = list_item_state_select then
  begin
    XDraw_SetBrushColor(hDraw, RGBA(ICON_ITEM_HIGHLIGHT_R, ICON_ITEM_HIGHLIGHT_G, ICON_ITEM_HIGHLIGHT_B, ICON_ITEM_SELECT_ALPHA));
    XDraw_FillRoundRect(hDraw, rc, 4, 4);
  end
  else if pItem.nState <> list_item_state_stay then
  begin
    XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, 38));
    XDraw_FillRoundRect(hDraw, rc, 4, 4);
  end;

  if pItem.nState = list_item_state_stay then
    svgColor := UITheme_PrimaryColor
  else
    svgColor := UITheme_InputText;
    
  XSvg_SetUserFillColor(hSvg, svgColor, True);
  XSvg_SetUserStrokeColor(hSvg, svgColor, 1, True);

  XDraw_DrawSvgEx(hDraw, hSvg, rc.Left + (rc.Width - ICON_SIDE_BASE) div 2, rc.Top + (rc.Height - ICON_SIDE_BASE) div 2, ICON_SIDE_BASE, ICON_SIDE_BASE);
end;

procedure TIconListViewUI.AddSvgIconsFromDir(const ADir: string; const AColor: Integer = -1);
var
  sr: TSearchRec;
  dirPath: string;
  fullPath: string;
begin
  dirPath := ExcludeTrailingPathDelimiter(ADir);
  if (dirPath = '') or (not DirectoryExists(dirPath)) then
    Exit;

  if FindFirst(IncludeTrailingPathDelimiter(dirPath) + '*.svg', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Attr and faDirectory) <> 0 then
        Continue;
      fullPath := ExpandFileName(IncludeTrailingPathDelimiter(dirPath) + sr.Name);
      AddSvgIconItem(fullPath, AColor);
    until FindNext(sr) <> 0;
  finally
    Redraw();
    FindClose(sr);
  end;
end;

function TIconListViewUI.FindItemBySvgPath(const ASvgPath: string; out AGroup, AItem: Integer): Boolean;
var
  i: Integer;
  targetPath: string;
begin
  Result := False;
  AGroup := 0;
  AItem := -1;

  targetPath := ExpandFileName(ASvgPath);
  for i := 0 to FItemCount - 1 do
  begin
    if SameText(FItems[i].SvgPath, targetPath) then
    begin
      AItem := i;
      Result := True;
      Break;
    end;
  end;
end;

function TIconListViewUI.GetSelectedSvgPath(out APath: string): Boolean;
var
  g, i: Integer;
begin
  APath := '';
  if not IsHELE then
    Exit(False);
  Result := GetSelectItem(g, i);
  if Result and (i >= 0) and (i < FItemCount) then
    APath := GetItemSvgPath(g, i);
end;

function TIconListViewUI.GetItemSvgHandle(iGroup, iItem: Integer): HSVG;
begin
  Result := 0;
  if (iItem >= 0) and (iItem < FItemCount) then
    Result := FItems[iItem].SvgHandle;
end;

function TIconListViewUI.GetItemSvgPath(iGroup, iItem: Integer): string;
begin
  Result := '';
  if (iItem >= 0) and (iItem < FItemCount) then
    Result := FItems[iItem].SvgPath;
end;

destructor TIconListViewUI.Destroy;
begin
  if IsHELE then
  begin
    RemoveEvent(XE_PAINT, @TIconListViewUI.OnPaint);
    RemoveEvent(XE_LISTVIEW_DRAWITEM, @TIconListViewUI.OnListViewDrawItem);
  end;
  ClearItems;
  inherited;
end;

end.
