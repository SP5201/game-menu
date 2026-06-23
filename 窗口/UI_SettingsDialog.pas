unit UI_SettingsDialog;

interface

uses
  Windows, Messages, SysUtils, Classes, XCGUI, UI_Form, UI_Button, UI_Theme,
  UI_ComboBox, UI_ScrollBar, UI_SliderBar, UI_Edit, UI_HintPopup, AppConfig,
  UI_MainWindowStat;

type
  TSettingsDialogUI = class(TFormUI)
  private
    class var
      FNavListBox: HELE;
      FPaneHost: HELE;
      FNavPageIndex: Integer;
      FSaved: TAppGeneralSettings;
      FWorking: TAppGeneralSettings;
      FChkRunWithWindows: HELE;
      FChkMinimizeToTray: HELE;
      FComboRenderMode: TComboBoxUI;
      FSliderPaintFreq: HELE;
      FLabelPaintFreqValue: HELE;
      FChkCityCoordsUpdate: HELE;
      FComboProxyMode: TComboBoxUI;
      FEdtProxyHost: TEditUI;
      FEdtProxyPort: TEditUI;
      FEdtHostsResolve: TEditUI;
      FEdtUserAgent: TEditUI;
      FEdtFilterExts: array[0..cSearchFilterExtKindCount - 1] of TEditUI;
    class procedure UpdatePaintFrequencyValue(const APosMs: Integer);
    class procedure ApplySearchFilterToUi; static;
    class procedure ReadWorkingFromUi; static;
    class procedure ApplyWorkingToUi; static;
    class procedure ApplyCityCoordsUpdateToUi; static;
    class procedure ApplyProxyToUi; static;
    class procedure UpdateProxyInputState; static;
    class procedure SplitProxyUrl(const AUrl: string; out AHost, APort: string); static;
    class function JoinProxyUrl(const AHost, APort: string): string; static;
    class function TrySaveWorking: Boolean; static;
    class procedure UpdateNavPageVisible; static;
    class procedure SwitchNavPage(const APageIndex: Integer); static;
    class procedure ApplyShapeTextTheme(const AName: string); static;
    class function OnNavDrawItem(hList: XCGUI.HELE; hDraw: XCGUI.HDRAW; var pItem: TlistBox_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnNavSelect(hList: XCGUI.HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnNavButtonDown(hList: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnChkChanged(hEle: XCGUI.HELE; bCheck: BOOL; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnProxyModeChanged(hEle: XCGUI.HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnPaintFreqSliderChange(hEle: XCGUI.HELE; nPos: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnReset(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnApply(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnOk(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndKeyDown(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: XCGUI.HWINDOW = 0): TSettingsDialogUI; reintroduce;
    class function ShowDialog(const hParent: XCGUI.HWINDOW = 0; hAttachWnd: XCGUI.HWINDOW = 0): Boolean;
  end;

implementation

uses
  UI_MainWindow;

const
  ID_BTN_CLOSE                = 'btn_settings_close';
  ID_BTN_RESET                = 'btn_settings_reset';
  ID_BTN_APPLY                = 'btn_settings_apply';
  ID_BTN_OK                   = 'btn_settings_ok';
  ID_TXT_TITLE                = 'txt_settings_title';
  ID_TXT_GROUP_STARTUP        = 'txt_settings_group_startup';
  ID_LIST_NAV                 = 'list_settings_nav';
  ID_PANE_GENERAL             = 'pane_settings_general';
  ID_PANE_DATA_UPDATE         = 'pane_settings_data_update';
  ID_PANE_PROXY               = 'pane_settings_proxy';
  ID_CHK_RUN_WITH_WINDOWS     = 'chk_settings_run_with_windows';
  ID_CHK_MINIMIZE_TO_TRAY     = 'chk_settings_minimize_to_tray';
  ID_TXT_GROUP_DISPLAY        = 'txt_settings_group_display';
  ID_TXT_LABEL_RENDER_MODE    = 'txt_settings_label_render_mode';
  ID_TXT_RENDER_MODE_HINT     = 'txt_settings_render_mode_hint';
  ID_COMBO_RENDER_MODE        = 'combo_settings_render_mode';
  ID_SLIDER_PAINT_FREQUENCY   = 'slider_settings_paint_frequency';
  ID_TXT_PAINT_FREQ_VALUE     = 'txt_settings_paint_frequency_value';
  ID_TXT_LABEL_PAINT_FREQ     = 'txt_settings_label_paint_frequency';
  ID_TXT_GROUP_CITY_COORDS    = 'txt_settings_group_city_coords';
  ID_CHK_CITY_COORDS_UPDATE   = 'chk_settings_city_coords_update';
  ID_TXT_GROUP_PROXY          = 'txt_settings_group_proxy';
  ID_TXT_LABEL_PROXY_MODE     = 'txt_settings_label_proxy_mode';
  ID_TXT_LABEL_PROXY_HOST     = 'txt_settings_label_proxy_host';
  ID_TXT_LABEL_PROXY_PORT     = 'txt_settings_label_proxy_port';
  ID_COMBO_PROXY_MODE         = 'combo_settings_proxy_mode';
  ID_EDIT_PROXY_HOST          = 'edit_settings_proxy_host';
  ID_EDIT_PROXY_PORT          = 'edit_settings_proxy_port';
  ID_TXT_GROUP_HOSTS          = 'txt_settings_group_hosts';
  ID_BTN_HOSTS_HINT           = 'btn_settings_hosts_hint';
  ID_EDIT_HOSTS_RESOLVE       = 'edit_settings_hosts_resolve';
  cHostsResolveHintText       = '无需修改本地 hosts 就生效';
  ID_TXT_GROUP_USERAGENT      = 'txt_settings_group_useragent';
  ID_EDIT_USERAGENT           = 'edit_settings_useragent';
  cNavIndexGeneral            = 0;
  cNavIndexDataUpdate         = 1;
  cNavIndexProxy              = 2;
  cNavIndexSearchFilter       = 3;
  cNavItemCount               = 4;
  cNavTitles: array[0..3] of UnicodeString = ('常规', '数据更新', '网络设置', '搜索分类');
  ID_PANE_SEARCH_FILTER       = 'pane_settings_search_filter';
  ID_TXT_GROUP_SEARCH_FILTER  = 'txt_settings_group_search_filter';
  cFilterEditNames: array[0..cSearchFilterExtKindCount - 1] of string = (
    'edit_settings_filter_app', 'edit_settings_filter_doc', 'edit_settings_filter_image',
    'edit_settings_filter_video', 'edit_settings_filter_audio', 'edit_settings_filter_archive');
  cFilterGroupLabels: array[0..cSearchFilterExtKindCount - 1] of string = (
    'txt_settings_filter_label_app', 'txt_settings_filter_label_doc', 'txt_settings_filter_label_image',
    'txt_settings_filter_label_video', 'txt_settings_filter_label_audio', 'txt_settings_filter_label_archive');
  cRenderModeIndexGDI         = 0;
  cRenderModeIndexD2D         = 1;

class procedure TSettingsDialogUI.ApplyShapeTextTheme(const AName: string);
var
  hText: HELE;
begin
  hText := XC_GetObjectByName(PWideChar(AName));
  if XC_GetObjectType(hText) = XC_SHAPE_TEXT then
    XShapeText_SetTextColor(hText, UITheme_TextPrimary);
end;

class procedure TSettingsDialogUI.UpdatePaintFrequencyValue(const APosMs: Integer);
var
  paintFreqText: UnicodeString;
begin
  if not XC_IsHELE(FLabelPaintFreqValue) then
    Exit;
  paintFreqText := IntToStr(APosMs) + ' ms';
  XShapeText_SetText(FLabelPaintFreqValue, PWideChar(paintFreqText));
  XShape_Redraw(FLabelPaintFreqValue);
end;

class function TSettingsDialogUI.OnPaintFreqSliderChange(hEle: XCGUI.HELE; nPos: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  UpdatePaintFrequencyValue(nPos);
  if XC_IsHELE(hEle) then
    TSliderBarUI.Redraw(hEle);
end;

class function TSettingsDialogUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI; hAttachWnd: XCGUI.HWINDOW): TSettingsDialogUI;
var
  h: HXCGUI;
begin
  h := TFormUI.LoadLayoutFile(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := TSettingsDialogUI.FromHandle(h);
end;

class procedure TSettingsDialogUI.ReadWorkingFromUi;
var
  proxyHostText, proxyPortText: string;
  i: Integer;
begin
  if XC_GetObjectType(FChkRunWithWindows) = XC_BUTTON then
    FWorking.RunWithWindows := XBtn_IsCheck(FChkRunWithWindows);
  if XC_GetObjectType(FChkMinimizeToTray) = XC_BUTTON then
    FWorking.MinimizeToTray := XBtn_IsCheck(FChkMinimizeToTray);
  if FComboRenderMode <> nil then
    FWorking.RenderModeD2D := XComboBox_GetSelItem(FComboRenderMode.Handle) = cRenderModeIndexD2D;
  if XC_IsHELE(FSliderPaintFreq) then
    FWorking.PaintFrequencyMs := XSliderBar_GetPos(FSliderPaintFreq);
  if XC_GetObjectType(FChkCityCoordsUpdate) = XC_BUTTON then
    TAppConfig.SetCityCoordsUpdateEnabled(XBtn_IsCheck(FChkCityCoordsUpdate));
  if FComboProxyMode <> nil then
    TAppConfig.SetProxyMode(XComboBox_GetSelItem(FComboProxyMode.Handle));
  if (FEdtProxyHost <> nil) or (FEdtProxyPort <> nil) then
  begin
    proxyHostText := '';
    proxyPortText := '';
    if FEdtProxyHost <> nil then
      proxyHostText := FEdtProxyHost.Text;
    if FEdtProxyPort <> nil then
      proxyPortText := FEdtProxyPort.Text;
    TAppConfig.SetProxyUrl(JoinProxyUrl(proxyHostText, proxyPortText));
  end;
  if FEdtHostsResolve <> nil then
    TAppConfig.SetHostsResolve(FEdtHostsResolve.Text);
  if FEdtUserAgent <> nil then
    TAppConfig.SetUserAgent(FEdtUserAgent.Text);
  for i := 0 to cSearchFilterExtKindCount - 1 do
    if FEdtFilterExts[i] <> nil then
      TAppConfig.SetSearchFilterExtSet(i, FEdtFilterExts[i].Text);
end;

class procedure TSettingsDialogUI.ApplySearchFilterToUi;
var
  i: Integer;
begin
  for i := 0 to cSearchFilterExtKindCount - 1 do
    if FEdtFilterExts[i] <> nil then
      FEdtFilterExts[i].Text := TAppConfig.FormatSearchFilterExtSetForEdit(
        TAppConfig.GetSearchFilterExtSet(i));
end;

class procedure TSettingsDialogUI.ApplyCityCoordsUpdateToUi;
begin
  if XC_GetObjectType(FChkCityCoordsUpdate) = XC_BUTTON then
    XBtn_SetCheck(FChkCityCoordsUpdate, TAppConfig.IsCityCoordsUpdateEnabled);
end;

class procedure TSettingsDialogUI.SplitProxyUrl(const AUrl: string; out AHost, APort: string);
var
  s: string;
  colonPos: Integer;
begin
  AHost := '';
  APort := '';
  s := Trim(AUrl);
  if s = '' then
    Exit;
  colonPos := LastDelimiter(':', s);
  if colonPos > 0 then
  begin
    AHost := Copy(s, 1, colonPos - 1);
    APort := Copy(s, colonPos + 1, MaxInt);
  end
  else
    AHost := s;
end;

class function TSettingsDialogUI.JoinProxyUrl(const AHost, APort: string): string;
var
  host, port: string;
begin
  host := Trim(AHost);
  port := Trim(APort);
  if host = '' then
    Exit('');
  if port = '' then
    Exit(host);
  Result := host + ':' + port;
end;

class procedure TSettingsDialogUI.ApplyProxyToUi;
var
  proxyHost, proxyPort: string;
begin
  if FComboProxyMode <> nil then
    FComboProxyMode.SetSelItem(TAppConfig.GetProxyMode);
  SplitProxyUrl(TAppConfig.GetProxyUrl, proxyHost, proxyPort);
  if FEdtProxyHost <> nil then
    FEdtProxyHost.Text := proxyHost;
  if FEdtProxyPort <> nil then
    FEdtProxyPort.Text := proxyPort;
  if FEdtHostsResolve <> nil then
    FEdtHostsResolve.Text := TAppConfig.GetHostsResolve;
  if FEdtUserAgent <> nil then
    FEdtUserAgent.Text := TAppConfig.GetUserAgent;
  UpdateProxyInputState;
end;

class procedure TSettingsDialogUI.UpdateProxyInputState;
var
  proxyEnabled: Boolean;
begin
  if (FEdtProxyHost = nil) and (FEdtProxyPort = nil) then
    Exit;
  proxyEnabled := (FComboProxyMode <> nil) and
    (XComboBox_GetSelItem(FComboProxyMode.Handle) <> cProxyModeOff);
  if FEdtProxyHost <> nil then
  begin
    FEdtProxyHost.EnableReadOnly(not proxyEnabled);
    FEdtProxyHost.Redraw(False);
  end;
  if FEdtProxyPort <> nil then
  begin
    FEdtProxyPort.EnableReadOnly(not proxyEnabled);
    FEdtProxyPort.Redraw(False);
  end;
end;

class procedure TSettingsDialogUI.ApplyWorkingToUi;
begin
  if XC_GetObjectType(FChkRunWithWindows) = XC_BUTTON then
    XBtn_SetCheck(FChkRunWithWindows, FWorking.RunWithWindows);
  if XC_GetObjectType(FChkMinimizeToTray) = XC_BUTTON then
    XBtn_SetCheck(FChkMinimizeToTray, FWorking.MinimizeToTray);
  if FComboRenderMode <> nil then
  begin
    if FWorking.RenderModeD2D then
      FComboRenderMode.SetSelItem(cRenderModeIndexD2D)
    else
      FComboRenderMode.SetSelItem(cRenderModeIndexGDI);
  end;
  if XC_IsHELE(FSliderPaintFreq) then
  begin
    if FWorking.PaintFrequencyMs < 0 then
      FWorking.PaintFrequencyMs := 0
    else if FWorking.PaintFrequencyMs > cMaxPaintFrequencyMs then
      FWorking.PaintFrequencyMs := cMaxPaintFrequencyMs;
    XSliderBar_SetPos(FSliderPaintFreq, FWorking.PaintFrequencyMs);
    UpdatePaintFrequencyValue(FWorking.PaintFrequencyMs);
  end;
  ApplyCityCoordsUpdateToUi;
  ApplyProxyToUi;
  ApplySearchFilterToUi;
end;

class function TSettingsDialogUI.TrySaveWorking: Boolean;
begin
  ReadWorkingFromUi;
  TAppSettings.Save(FWorking);
  FSaved := FWorking;
  TMainFormUI.ReloadSearchFilterConfig;
  TMainWindowStat.RequestNetworkRefresh;
  Result := True;
end;

class procedure TSettingsDialogUI.UpdateNavPageVisible;
var
  hPaneGeneral, hPaneDataUpdate, hPaneProxy, hPaneSearchFilter: HELE;
  hModalWnd: XCGUI.HWINDOW;
  showGeneral, showData, showProxy, showSearchFilter: BOOL;
begin
  hPaneGeneral := XC_GetObjectByName(ID_PANE_GENERAL);
  hPaneDataUpdate := XC_GetObjectByName(ID_PANE_DATA_UPDATE);
  hPaneProxy := XC_GetObjectByName(ID_PANE_PROXY);
  hPaneSearchFilter := XC_GetObjectByName(ID_PANE_SEARCH_FILTER);
  showGeneral := FNavPageIndex = cNavIndexGeneral;
  showData := FNavPageIndex = cNavIndexDataUpdate;
  showProxy := FNavPageIndex = cNavIndexProxy;
  showSearchFilter := FNavPageIndex = cNavIndexSearchFilter;
  if XC_GetObjectType(hPaneGeneral) <> XC_ERROR then
    XWidget_Show(hPaneGeneral, showGeneral);
  if XC_GetObjectType(hPaneDataUpdate) <> XC_ERROR then
    XWidget_Show(hPaneDataUpdate, showData);
  if XC_GetObjectType(hPaneProxy) <> XC_ERROR then
    XWidget_Show(hPaneProxy, showProxy);
  if XC_GetObjectType(hPaneSearchFilter) <> XC_ERROR then
    XWidget_Show(hPaneSearchFilter, showSearchFilter);
  if XC_GetObjectType(FPaneHost) <> XC_ERROR then
  begin
    XEle_AdjustLayoutEx(FPaneHost, adjustLayout_all);
    XEle_Redraw(FPaneHost);
  end;
  if XC_GetObjectType(hPaneGeneral) <> XC_ERROR then
    hModalWnd := XWidget_GetHWINDOW(hPaneGeneral)
  else if XC_GetObjectType(FNavListBox) <> XC_ERROR then
    hModalWnd := XWidget_GetHWINDOW(FNavListBox)
  else
    hModalWnd := 0;
  if XC_GetObjectType(hModalWnd) = XC_MODALWINDOW then
    XWnd_Redraw(hModalWnd, True);
end;

class procedure TSettingsDialogUI.SwitchNavPage(const APageIndex: Integer);
begin
  if (APageIndex < 0) or (APageIndex >= cNavItemCount) then
    Exit;
  if FNavPageIndex = APageIndex then
    Exit;
  FNavPageIndex := APageIndex;
  if XC_GetObjectType(FNavListBox) = XC_LISTBOX then
    XListBox_SetSelectItem(FNavListBox, APageIndex);
  UpdateNavPageVisible;
end;

class function TSettingsDialogUI.OnNavDrawItem(hList: XCGUI.HELE; hDraw: XCGUI.HDRAW; var pItem: TlistBox_item_; pbHandled: PBOOL): Integer; stdcall;
var
  rcBg, rcText: TRect;
begin
  Result := 0;
  if (pItem.index < 0) or (pItem.index >= cNavItemCount) then
    Exit;

  rcBg := pItem.rcItem;
  rcBg.Left := rcBg.Left + 4;
  rcBg.Right := rcBg.Right - 4;

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

  rcText := pItem.rcItem;
  Inc(rcText.Left, 12);
  XDraw_SetBrushColor(hDraw, UITheme_TextPrimary);
  XDraw_SetTextAlign(hDraw, textAlignFlag_left or textAlignFlag_vcenter or textFormatFlag_NoWrap);
  XDraw_DrawText(hDraw, PWideChar(cNavTitles[pItem.index]), -1, rcText);
  pbHandled^ := True;
end;

class function TSettingsDialogUI.OnNavSelect(hList: XCGUI.HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  SwitchNavPage(iItem);
end;

class function TSettingsDialogUI.OnNavButtonDown(hList: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  itemIndex: Integer;
begin
  Result := 0;
  itemIndex := XListBox_HitTestOffset(hList, pPt);
  if itemIndex < 0 then
  begin
    pbHandled^ := True;
    Exit;
  end;
  SwitchNavPage(itemIndex);
  if XC_GetObjectType(hList) = XC_LISTBOX then
    XEle_Redraw(hList);
end;

class function TSettingsDialogUI.OnChkChanged(hEle: XCGUI.HELE; bCheck: BOOL; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
end;

class function TSettingsDialogUI.OnProxyModeChanged(hEle: XCGUI.HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  UpdateProxyInputState;
end;

class function TSettingsDialogUI.OnBtnReset(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  TAppSettings.ApplyDefaults(FWorking);
  TAppConfig.SetCityCoordsUpdateEnabled(True);
  TAppConfig.SetCityCoordsUrl(cDefaultCityCoordsUrl);
  TAppConfig.SetProxyMode(cProxyModeOff);
  TAppConfig.SetProxyUrl('');
  TAppConfig.SetHostsResolve('');
  TAppConfig.SetUserAgent('');
  TAppConfig.ApplySearchFilterDefaults;
  ApplyWorkingToUi;
end;

class function TSettingsDialogUI.OnBtnApply(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  TrySaveWorking;
end;

class function TSettingsDialogUI.OnBtnOk(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  if TrySaveWorking then
    TFormUI.EndModalOk(hEle);
end;

class function TSettingsDialogUI.OnWndKeyDown(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if (lParam and $40000000) <> 0 then
    Exit;
  case wParam of
    VK_ESCAPE:
      begin
        pbHandled^ := True;
        TFormUI.EndModalCancelWnd(hWindow);
      end;
    VK_RETURN:
      begin
        pbHandled^ := True;
        if TrySaveWorking then
          TFormUI.EndModalOkWnd(hWindow);
      end;
  end;
end;

procedure TSettingsDialogUI.Init;
var
  i: Integer;
begin
  inherited;
  SetupDialogChrome('pic_settings_dialog_logo', ID_BTN_CLOSE);

  TAppSettings.Load(FSaved);
  FWorking := FSaved;
  FNavPageIndex := cNavIndexGeneral;

  TButtonUI.FromXmlName(ID_BTN_RESET, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TSettingsDialogUI.OnBtnReset);
  TButtonUI.FromXmlName(ID_BTN_APPLY, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TSettingsDialogUI.OnBtnApply);
  TButtonUI.FromXmlName(ID_BTN_OK, BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TSettingsDialogUI.OnBtnOk);

  ApplyShapeTextTheme(ID_TXT_TITLE);
  ApplyShapeTextTheme(ID_TXT_GROUP_STARTUP);
  ApplyShapeTextTheme(ID_TXT_GROUP_DISPLAY);
  ApplyShapeTextTheme(ID_TXT_LABEL_RENDER_MODE);
  ApplyShapeTextTheme(ID_TXT_RENDER_MODE_HINT);
  ApplyShapeTextTheme(ID_TXT_LABEL_PAINT_FREQ);
  ApplyShapeTextTheme(ID_TXT_GROUP_CITY_COORDS);
  ApplyShapeTextTheme(ID_TXT_GROUP_PROXY);
  ApplyShapeTextTheme(ID_TXT_LABEL_PROXY_MODE);
  ApplyShapeTextTheme(ID_TXT_LABEL_PROXY_HOST);
  ApplyShapeTextTheme(ID_TXT_LABEL_PROXY_PORT);
  ApplyShapeTextTheme(ID_TXT_GROUP_HOSTS);
  ApplyShapeTextTheme(ID_TXT_GROUP_USERAGENT);
  ApplyShapeTextTheme(ID_TXT_GROUP_SEARCH_FILTER);
  for i := 0 to cSearchFilterExtKindCount - 1 do
    ApplyShapeTextTheme(cFilterGroupLabels[i]);

  FNavListBox := XC_GetObjectByName(ID_LIST_NAV);
  FPaneHost := 0;
  if XC_GetObjectType(FNavListBox) = XC_LISTBOX then
  begin
    XEle_EnableBkTransparent(FNavListBox, True);
    XEle_EnableDrawBorder(FNavListBox, False);
    XEle_EnableDrawFocus(FNavListBox, False);
    XListBox_SetItemHeightDefault(FNavListBox, 36, 36);
    XListBox_SetRowSpace(FNavListBox, 4);
    XListBox_EnableMultiSel(FNavListBox, False);
    XListBox_EnableVirtualTable(FNavListBox, True);
    XListBox_CreateAdapter(FNavListBox);
    XListBox_SetVirtualRowCount(FNavListBox, cNavItemCount);
    XSView_SetScrollBarSize(FNavListBox, 0);
    XSView_EnableAutoShowScrollBar(FNavListBox, False);
    XListBox_SetSelectItem(FNavListBox, cNavIndexGeneral);
    XEle_RegEvent(FNavListBox, XE_LISTBOX_DRAWITEM, @TSettingsDialogUI.OnNavDrawItem);
    XEle_RegEvent(FNavListBox, XE_LISTBOX_SELECT, @TSettingsDialogUI.OnNavSelect);
    XEle_RegEvent(FNavListBox, XE_LBUTTONDOWN, @TSettingsDialogUI.OnNavButtonDown);
    XEle_RegEvent(FNavListBox, XE_RBUTTONDOWN, @TSettingsDialogUI.OnNavButtonDown);
  end;
  FPaneHost := XWidget_GetParentEle(XC_GetObjectByName(ID_PANE_GENERAL));
  UpdateNavPageVisible;

  FChkRunWithWindows := XC_GetObjectByName(ID_CHK_RUN_WITH_WINDOWS);
  FChkMinimizeToTray := XC_GetObjectByName(ID_CHK_MINIMIZE_TO_TRAY);

  TButtonUI.FormHandle(FChkRunWithWindows, BB_EnableCheckStyle, '').RegEvent(XE_BUTTON_CHECK, @TSettingsDialogUI.OnChkChanged);
  TButtonUI.FormHandle(FChkMinimizeToTray, BB_EnableCheckStyle, '').RegEvent(XE_BUTTON_CHECK, @TSettingsDialogUI.OnChkChanged);

  FComboRenderMode := TComboBoxUI.FromXmlName(ID_COMBO_RENDER_MODE);
  FComboRenderMode.InitTextItems(['GDI', 'D2D'], 0);

  FSliderPaintFreq := XC_GetObjectByName(ID_SLIDER_PAINT_FREQUENCY);
  FLabelPaintFreqValue := XC_GetObjectByName(ID_TXT_PAINT_FREQ_VALUE);
  if XC_GetObjectType(FLabelPaintFreqValue) = XC_SHAPE_TEXT then
    XShapeText_SetTextColor(FLabelPaintFreqValue, UITheme_TextPrimary);
  if XC_IsHELE(FSliderPaintFreq) then
  begin
    XSliderBar_SetRange(FSliderPaintFreq, cMaxPaintFrequencyMs);
    TSliderBarUI.ApplyDefault(FSliderPaintFreq);
    TSliderBarUI.SetValueSuffix(FSliderPaintFreq, ' ms');
    XEle_RegEvent(FSliderPaintFreq, XE_SLIDERBAR_CHANGE, @TSettingsDialogUI.OnPaintFreqSliderChange);
  end;

  FChkCityCoordsUpdate := XC_GetObjectByName(ID_CHK_CITY_COORDS_UPDATE);
  TButtonUI.FormHandle(FChkCityCoordsUpdate, BB_EnableCheckStyle, '').RegEvent(XE_BUTTON_CHECK, @TSettingsDialogUI.OnChkChanged);

  FComboProxyMode := TComboBoxUI.FromXmlName(ID_COMBO_PROXY_MODE);
  FComboProxyMode.InitTextItems(['不使用代理', 'HTTP 代理', 'HTTPS 代理', 'SOCKS5 代理'], cProxyModeOff);
  FComboProxyMode.RegEvent(XE_COMBOBOX_SELECT_END, @TSettingsDialogUI.OnProxyModeChanged);
  FEdtProxyHost := TEditUI.FromXmlName(ID_EDIT_PROXY_HOST);
  FEdtProxyPort := TEditUI.FromXmlName(ID_EDIT_PROXY_PORT);
  FEdtHostsResolve := TEditUI.FromXmlName(ID_EDIT_HOSTS_RESOLVE);
  TButtonUI.FromXmlName(ID_BTN_HOSTS_HINT, BB_NONE, 'Resource\hint.svg');
  if XC_GetObjectType(XC_GetObjectByName(ID_BTN_HOSTS_HINT)) = XC_BUTTON then
    THintPopupUI.BindHoverHint(XC_GetObjectByName(ID_BTN_HOSTS_HINT), cHostsResolveHintText);
  FEdtUserAgent := TEditUI.FromXmlName(ID_EDIT_USERAGENT);
  for i := 0 to cSearchFilterExtKindCount - 1 do
    FEdtFilterExts[i] := TEditUI.FromXmlName(PWideChar(cFilterEditNames[i]));

  ApplyWorkingToUi;

  TScrollBarUI.ApplyDefaultRecursive(Handle);

  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TSettingsDialogUI.OnWndKeyDown);
end;

class function TSettingsDialogUI.ShowDialog(const hParent: XCGUI.HWINDOW; hAttachWnd: XCGUI.HWINDOW): Boolean;
var
  dlg: TSettingsDialogUI;
  modalResult: Integer;
begin
  dlg := TSettingsDialogUI.LoadLayout('Resource\Layout\SettingsDialog.xml', hParent, hAttachWnd);
  if dlg = nil then
    Exit(False);
  modalResult := XModalWnd_DoModal(dlg.Handle);
  Result := modalResult = IDOK;
end;

end.
