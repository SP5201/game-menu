unit UI_ListBox;

interface

uses
  Windows, SysUtils, XCGUI, XListbox, UI_PopupMenu, UI_Theme;

const
  ID_LISTBOX_CATEGORY_ADD = 101;
  ID_LISTBOX_CATEGORY_EDIT = 102;
  ID_LISTBOX_CATEGORY_DELETE = 103;
  ID_LISTBOX_CATEGORY_TOGGLE_COMMON_TOOLS = 201;
  ID_LISTBOX_CATEGORY_TOGGLE_TRAFFIC = 202;

type
  TListBoxCategoryItem = record
    Title: string;
    SvgHandle: HSVG;
  end;

  TListBoxUI = class(TXListBox)
  private
    FItems: array of TListBoxCategoryItem;
    FItemCount: Integer;
    class function OnListDrawItem(hList: XCGUI.HELE; hCanvas: HDRAW; var pItem: TlistBox_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListButtonDown(hList: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListRButtonUp(hList: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    function LoadCategorySvg(const AIconFile: string): HSVG;
  protected
    procedure Init; override;
  public
    procedure ClearItems;
    function AddItem(const ATitle, AIconFile: string): Integer;
    function GetItemTitle(const AIndex: Integer): string;
    function GetCount: Integer;
    destructor Destroy; override;
  end;

implementation

uses
  AppConfig;

procedure TListBoxUI.Init;
begin
  inherited;
  XEle_SetUserData(Handle, NativeInt(Self));
  EnableBkTransparent(True);
  EnableDrawBorder(False);
  EnableDrawFocus(False);
  EnableVirtualTable(True);
  RegEvent(XE_LISTBOX_DRAWITEM, @TListBoxUI.OnListDrawItem);
  RegEvent(XE_LBUTTONDOWN, @TListBoxUI.OnListButtonDown);
  RegEvent(XE_RBUTTONDOWN, @TListBoxUI.OnListButtonDown);
  RegEvent(XE_RBUTTONUP, @TListBoxUI.OnListRButtonUp);

  SetItemHeightDefault(34, 34);
  SetItemTemplateXML('Resource\Layout\ListBox_Item.xml');
  CreateAdapter;
  SetVirtualRowCount(0);
end;

class function TListBoxUI.OnListDrawItem(hList: XCGUI.HELE; hCanvas: HDRAW; var pItem: TlistBox_item_; pbHandled: PBOOL): Integer; stdcall;
var
  ListBox: TListBoxUI;
  hSvg: XCGUI.HSVG;
  iconSize: Integer;
  xDraw: Integer;
  yDraw: Integer;
  rcBg: TRect;
  rcText: TRect;
  titleText: string;
begin
  Result := 0;
  ListBox := TListBoxUI(XEle_GetUserData(hList));
  if ListBox = nil then
    Exit;
  if (pItem.index < 0) or (pItem.index >= ListBox.FItemCount) then
    Exit;

  XDraw_EnableSmoothingMode(hCanvas, True);
  rcBg := pItem.rcItem;
  rcBg.Left := rcBg.Left + 4;
  rcBg.Right := rcBg.Right - 4;

  if pItem.nState = list_item_state_select then
  begin
    XDraw_SetBrushColor(hCanvas, UITheme_SurfaceSelected);
    XDraw_FillRoundRect(hCanvas, rcBg, 6, 6);
  end
  else if pItem.nState = list_item_state_stay then
  begin
    XDraw_SetBrushColor(hCanvas, UITheme_SurfaceHover);
    XDraw_FillRoundRect(hCanvas, rcBg, 6, 6);
  end;

  hSvg := ListBox.FItems[pItem.index].SvgHandle;
  if XC_GetObjectType(hSvg) = XC_SVG then
  begin
    iconSize := 20;
    XSvg_SetUserFillColor(hSvg, UITheme_SvgColor, True);
    XSvg_SetUserStrokeColor(hSvg, UITheme_SvgColor, 1, True);
    xDraw := pItem.rcItem.Left + 20;
    yDraw := pItem.rcItem.Top + ((pItem.rcItem.Bottom - pItem.rcItem.Top) - iconSize) div 2;
    XDraw_DrawSvgEx(hCanvas, hSvg, xDraw, yDraw, iconSize, iconSize);
  end;

  rcText := pItem.rcItem;
  rcText.Left := pItem.rcItem.Left + 52;
  rcText.Right := pItem.rcItem.Right - 20;
  titleText := ListBox.FItems[pItem.index].Title;
  XDraw_SetBrushColor(hCanvas, UITheme_TextPrimary);
  XDraw_SetFont(hCanvas, XC_GetDefaultFont);
  XDraw_SetTextAlign(hCanvas, textAlignFlag_left or textAlignFlag_vcenter or textFormatFlag_NoWrap);
  XDraw_DrawText(hCanvas, PWideChar(titleText), -1, rcText);

  pbHandled^ := True;
end;
 
class function TListBoxUI.OnListButtonDown(hList: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if XListBox_HitTestOffset(hList, pPt) < 0 then
    pbHandled^ := True;
end;

class function TListBoxUI.OnListRButtonUp(hList: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  Menu: TPopupMenuUI;
begin
  Result := 0;
  Menu := TPopupMenuUI.Create(hList);
  try
    Menu.AddItem(ID_LISTBOX_CATEGORY_ADD, UI_Utf8Src(UTF8String('添加新分类')));
    if XListBox_HitTestOffset(hList, pPt) >= 0 then
    begin
      Menu.AddItemIcon(ID_LISTBOX_CATEGORY_EDIT, '修改分类', 0, 'Resource\menu_edit.svg', 0);
      Menu.AddItem(ID_LISTBOX_CATEGORY_DELETE, '删除分类', 0);
    end;
    Menu.AddItem(0, '', 0, menu_item_flag_separator);
    Menu.AddItem(ID_LISTBOX_CATEGORY_TOGGLE_COMMON_TOOLS, '显示常用工具');
    Menu.AddItem(ID_LISTBOX_CATEGORY_TOGGLE_TRAFFIC, '显示流量监控');
    Menu.SetItemCheck(ID_LISTBOX_CATEGORY_TOGGLE_COMMON_TOOLS, TAppConfig.IsShowCommonTools);
    Menu.SetItemCheck(ID_LISTBOX_CATEGORY_TOGGLE_TRAFFIC, TAppConfig.IsShowTrafficMonitor);
    Menu.Popup(hList, pPt);
  finally
    Menu.Free;
  end;
end;

function TListBoxUI.LoadCategorySvg(const AIconFile: string): HSVG;
var
  iconPath: string;
begin
  iconPath := TAppConfig.ResolveGroupIconFile(AIconFile);
  Result := XSvg_LoadFile(PWideChar(iconPath));
  if XC_GetObjectType(Result) <> XC_SVG then
    Result := 0;
end;

procedure TListBoxUI.ClearItems;
var
  i: Integer;
begin
  for i := 0 to FItemCount - 1 do
  begin
    if XC_GetObjectType(FItems[i].SvgHandle) = XC_SVG then
      XSvg_Release(FItems[i].SvgHandle);
    FItems[i].SvgHandle := 0;
    FItems[i].Title := '';
  end;
  SetLength(FItems, 0);
  FItemCount := 0;
  if IsHELE then
    SetVirtualRowCount(0);
end;

function TListBoxUI.AddItem(const ATitle, AIconFile: string): Integer;
var
  iconFileName: string;
begin
  Result := FItemCount;
  Inc(FItemCount);
  SetLength(FItems, FItemCount);
  FItems[Result].Title := ATitle;
  iconFileName := ExtractFileName(Trim(AIconFile));
  FItems[Result].SvgHandle := LoadCategorySvg(iconFileName);
  if IsHELE then
    SetVirtualRowCount(FItemCount);
end;

function TListBoxUI.GetItemTitle(const AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex < FItemCount) then
    Result := FItems[AIndex].Title;
end;

function TListBoxUI.GetCount: Integer;
begin
  Result := FItemCount;
end;


destructor TListBoxUI.Destroy;
begin
  if IsHELE then
  begin
    RemoveEvent(XE_LISTBOX_DRAWITEM, @TListBoxUI.OnListDrawItem);
    RemoveEvent(XE_LBUTTONDOWN, @TListBoxUI.OnListButtonDown);
    RemoveEvent(XE_RBUTTONDOWN, @TListBoxUI.OnListButtonDown);
    RemoveEvent(XE_RBUTTONUP, @TListBoxUI.OnListRButtonUp);
  end;
  ClearItems;
  inherited;
end;



end.

