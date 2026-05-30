unit UI_List;

{
  报表列表（listUI）主题：XML 项模板、透明底、行态/滚动条。
  列配置见 SetupSafeLogColumns；模板 SafeLogList_Item.xml。
}

interface

uses
  Windows, SysUtils, XCGUI, UI_Theme, UI_ScrollBar;

const
  cListColStatus = 'col_status';
  cListColTime = 'col_time';
  cListColType = 'col_type';
  cListColFeature = 'col_feature';
  cListColSummary = 'col_summary';
  cListColIndexStatus = 0;
  cListColIndexTime = 1;
  cListColIndexType = 2;
  cListColIndexFeature = 3;
  cListColIndexSummary = 4;
  cSafeLogListTemplateXml = 'Resource\Layout\SafeLogList_Item.xml';
  cListHeaderSplitLineInset = 8;
  cListHeaderTextStatus = '状态';
  cListHeaderTextTime = '时间';
  cListHeaderTextType = '类型';
  cListHeaderTextFeature = '功能';
  cListHeaderTextSummary = '概要';

type
  TListUI = class
  private
    class function OnDrawItem(hEle: HELE; hDraw: HDRAW; var pItem: Tlist_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnHeaderDrawItem(hEle: HELE; hDraw: HDRAW; var pItem: Tlist_header_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnHeaderTempCreateEnd(hEle: HELE; var pItem: Tlist_header_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListSelect(hEle: HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnSize(hEle: HELE; nFlags: Integer; nAdjustNo: UINT; pbHandled: PBOOL): Integer; stdcall; static;
  public
    class procedure ApplyTheme(const AListEle: HELE); static;
  end;

implementation

function ListRowDrawState(const AListEle: HELE; ARow: Integer; ACellState: Integer): Integer;
begin
  if XList_GetSelectRow(AListEle) = ARow then
    Result := list_item_state_select
  else if ACellState = list_item_state_stay then
    Result := list_item_state_stay
  else
    Result := list_item_state_leave;
end;

procedure DrawListRowBk(const AHDraw: HDRAW; const ARc: TRect; AState: Integer);
var
  rc: TRect;
begin
  if AState = list_item_state_select then
    XDraw_SetBrushColor(AHDraw, UITheme_SurfaceSelected)
  else if AState = list_item_state_stay then
    XDraw_SetBrushColor(AHDraw, UITheme_SurfaceHover)
  else
    Exit;
  rc := ARc;
  XDraw_FillRect(AHDraw, rc);
end;

class function TListUI.OnDrawItem(hEle: hEle; hDraw: hDraw; var pItem: Tlist_item_; pbHandled: PBOOL): Integer; stdcall;
var
  pText: PWideChar;
  rcText: TRect;
begin
  Result := 0;
  DrawListRowBk(hDraw, pItem.rcItem, ListRowDrawState(hEle, pItem.index, pItem.nState));

  pText := XList_GetItemText(hEle, pItem.index, pItem.iSubItem);
  if (pText <> nil) and (pText^ <> #0) then
  begin
    rcText := pItem.rcItem;
    rcText.Left := rcText.Left + 4;
    rcText.Right := rcText.Right - 4;
    XDraw_SetBrushColor(hDraw, UITheme_TextPrimary);
    XDraw_SetTextAlign(hDraw, textAlignFlag_left or textAlignFlag_vcenter or DT_SINGLELINE);
    XDraw_DrawText(hDraw, pText, -1, rcText);
  end;

  pbHandled^ := True;
end;

class function TListUI.OnHeaderDrawItem(hEle: hEle; hDraw: hDraw; var pItem: Tlist_header_item_; pbHandled: PBOOL): Integer; stdcall;
var
  RC: TRect;
begin
  pbHandled^ := True;
  Result := 0;
  XDraw_SetBrushColor(hDraw, UITheme_ListHeaderSurface);
  XEle_GetClientRect(hEle, RC);
  XDraw_FillRect(hDraw, RC);
end;

class function TListUI.OnHeaderTempCreateEnd(hEle: hEle; var pItem: Tlist_header_item_; pbHandled: PBOOL): Integer; stdcall;
var
  hShapeText: HXCGUI;
  I: Integer;
begin
  Result := 0;
  for I := 0 to XList_GetColumnCount(hEle) - 1 do
  begin
    hShapeText := XList_GetHeaderTemplateObject(hEle, I, 1);
    if XC_GetObjectType(hShapeText) = XC_SHAPE_TEXT then
      XShapeText_SetTextColor(hShapeText, UITheme_ListHeaderText);
  end;
end;

class function TListUI.OnListSelect(hEle: hEle; iItem: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
end;

class function TListUI.OnSize(hEle: hEle; nFlags: Integer; nAdjustNo: UINT; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
end;

class procedure TListUI.ApplyTheme(const AListEle: hEle);
begin
  if not XC_IsHELE(AListEle) then
    Exit;
  XEle_EnableBkTransparent(AListEle, True);
  XEle_EnableDrawBorder(AListEle, False);
  XEle_EnableDrawFocus(AListEle, False);
  XList_SetSplitLineColor(AListEle, RGBA(0, 0, 0, 0));
  XList_SetDrawRowBkFlags(AListEle, 0);
  XList_EnableRowBkFull(AListEle, True);
  XList_EnableTemplateReuse(AListEle, False);
  TScrollBarUI.ApplyDefault(AListEle);
  XList_SetItemTemplateXML(AListEle, PWideChar(cSafeLogListTemplateXml));
  XEle_EnableBkTransparent(XList_GetHeaderHELE(AListEle), True);
  XEle_RegEvent(AListEle, XE_LIST_DRAWITEM, @TListUI.OnDrawItem);
  XEle_RegEvent(AListEle, XE_LIST_SELECT, @TListUI.OnListSelect);
  XEle_RegEvent(AListEle, XE_LIST_HEADER_DRAWITEM, @TListUI.OnHeaderDrawItem);
  XEle_RegEvent(AListEle, XE_LIST_HEADER_TEMP_CREATE_END, @TListUI.OnHeaderTempCreateEnd);
  XEle_RegEvent(AListEle, XE_SIZE, @TListUI.OnSize);
end;

end.

