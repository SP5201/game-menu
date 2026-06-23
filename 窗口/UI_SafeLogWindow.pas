unit UI_SafeLogWindow;

interface

uses
  Windows, SysUtils, Classes, XCGUI, UI_Form, UI_Button, UI_Edit, UI_Theme,
  UI_List, SafeLog;

type
  TSafeLogWindow = class(TFormUI)
  private
    class var
      FInstance: TSafeLogWindow;
      CListEle: XCGUI.HELE;
      CEditDetail: XCGUI.HELE;
    class function OnListSelect(hEle: XCGUI.HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWinProc(hWindow: XCGUI.HWINDOW; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    class procedure ShowEntryDetail(AEntryId: Integer); static;
    class procedure AppendRowToList(const AEntry: TSafeLogEntry); static;
    class procedure DoAppend(AEntryId: Integer); static;
    class procedure DoRemoveOldest; static;
    class procedure SyncAllEntries; static;
    class procedure DoClearLog; static;
    class procedure DoExportLog; static;
    class procedure DoCopyMessage; static;
    class function OnExportClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnClearClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnCopyClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    destructor Destroy; override;
    class procedure ShowWindow; static;
    class procedure CloseIfOpen; static;
    class function LoadLayout(const LayoutFile: PWideChar): TSafeLogWindow; reintroduce;
  end;

implementation

uses
  AppConfig, ShellHelper;

class procedure TSafeLogWindow.ShowEntryDetail(AEntryId: Integer);
var
  entry: TSafeLogEntry;
  detail: string;
begin
  if (CEditDetail = 0) or (not SafeLogFindById(AEntryId, entry)) then
    Exit;
  detail := SafeLogBuildDetail(entry);
  if Trim(detail) <> '' then
    XEdit_SetDefaultTextColor(CEditDetail, UITheme_InputText)
  else
    XEdit_SetDefaultTextColor(CEditDetail, UITheme_TextPlaceholder);
  XEdit_SetText(CEditDetail, PWideChar(detail));
  XEle_Redraw(CEditDetail);
end;

class procedure TSafeLogWindow.AppendRowToList(const AEntry: TSafeLogEntry);
var
  iRow: Integer;
  statusText: string;
begin
  if CListEle = 0 then
    Exit;
  statusText := SafeLogFormatStatusText(AEntry.Success);
  iRow := XList_AddItemText(CListEle, PWideChar(''));
  if iRow < 0 then
    Exit;
  XList_SetItemText(CListEle, iRow, cListColIndexStatus, PWideChar(statusText));
  XList_SetItemText(CListEle, iRow, cListColIndexTime, PWideChar(AEntry.TimeText));
  XList_SetItemText(CListEle, iRow, cListColIndexType, PWideChar(AEntry.TypeText));
  XList_SetItemText(CListEle, iRow, cListColIndexFeature, PWideChar(AEntry.FeatureText));
  XList_SetItemText(CListEle, iRow, cListColIndexSummary, PWideChar(AEntry.SummaryText));
  XList_SetItemData(CListEle, iRow, 0, AEntry.Id);
  XList_SetSelectRow(CListEle, iRow);
  XList_VisibleRow(CListEle, iRow);
  XList_RefreshRow(CListEle, iRow);
  XEle_Redraw(CListEle);
  ShowEntryDetail(AEntry.Id);
end;

class procedure TSafeLogWindow.DoAppend(AEntryId: Integer);
var
  entry: TSafeLogEntry;
begin
  if not SafeLogFindById(AEntryId, entry) then
    Exit;
  AppendRowToList(entry);
end;

class procedure TSafeLogWindow.DoRemoveOldest;
begin
  if CListEle = 0 then
    Exit;
  if XList_GetCount_AD(CListEle) > 0 then
  begin
    XList_DeleteRow(CListEle, 0);
    XEle_Redraw(CListEle);
  end;
end;

class procedure TSafeLogWindow.SyncAllEntries;
var
  snap: TSafeLogEntryArray;
  i: Integer;
begin
  if CListEle = 0 then
    Exit;
  SafeLogCopyAll(snap);
  XList_DeleteRowAll(CListEle);
  for i := 0 to High(snap) do
    AppendRowToList(snap[i]);
  XEle_Redraw(CListEle);
end;

class procedure TSafeLogWindow.DoClearLog;
begin
  SafeLogClearAll;
  if CListEle <> 0 then
  begin
    XList_DeleteRowAll(CListEle);
    XEle_Redraw(CListEle);
  end;
  if CEditDetail <> 0 then
  begin
    XEdit_SetText(CEditDetail, PWideChar(''));
    XEle_Redraw(CEditDetail);
  end;
end;

class procedure TSafeLogWindow.DoExportLog;
var
  exportPath: string;
  hOwner: Windows.HWND;
begin
  hOwner := 0;
  if Assigned(FInstance) and FInstance.IsHWINDOW then
    hOwner := XWnd_GetHWND(FInstance.Handle);
  if not SaveFileDialog(hOwner, '导出日志', '文本文件 (*.txt)|*.txt',
    'QDesktop_SafeLog_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.txt',
    IncludeTrailingPathDelimiter(TAppConfig.DataDirectory), 'txt', exportPath) then
    Exit;
  if SafeLogSaveToFile(exportPath) then
  begin
    if CEditDetail <> 0 then
    begin
      XEdit_SetText(CEditDetail, PWideChar('日志已导出至：' + sLineBreak + exportPath));
      XEle_Redraw(CEditDetail);
    end;
  end
  else if CEditDetail <> 0 then
  begin
    XEdit_SetText(CEditDetail, PWideChar('导出失败：' + exportPath));
    XEle_Redraw(CEditDetail);
  end;
end;

class procedure TSafeLogWindow.DoCopyMessage;
begin
  if CEditDetail = 0 then
    Exit;
  if Trim(string(XEdit_GetText_Temp(CEditDetail))) = '' then
    Exit;
  XEdit_ClipboardCopyAll(CEditDetail);
end;

class function TSafeLogWindow.OnCopyClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  DoCopyMessage;
  pbHandled^ := True;
end;

class function TSafeLogWindow.OnExportClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  DoExportLog;
  pbHandled^ := True;
end;

class function TSafeLogWindow.OnClearClick(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  DoClearLog;
  pbHandled^ := True;
end;

class function TSafeLogWindow.OnWinProc(hWindow: XCGUI.HWINDOW; Msg: UINT; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  TFormUI.HandleWndSize(hWindow, Msg, wParam);
  case Msg of
    WM_SAFELOG_APPEND:
      begin
        DoAppend(Integer(wParam));
        pbHandled^ := True;
      end;
    WM_SAFELOG_REMOVE_OLDEST:
      begin
        DoRemoveOldest;
        pbHandled^ := True;
      end;
  end;
end;

class function TSafeLogWindow.OnListSelect(hEle: XCGUI.HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  entryId: Integer;
begin
  Result := 0;
  if (CListEle = 0) or (iItem < 0) then
    Exit;
  entryId := Integer(XList_GetItemData(CListEle, iItem, 0));
  ShowEntryDetail(entryId);
end;

procedure TSafeLogWindow.Init;
var
  hTitle: XCGUI.HXCGUI;
  editUI: TEditUI;
  btnUi: TButtonUI;
begin
  inherited;
  CListEle := XC_GetObjectByName('list_safelog');
  CEditDetail := XC_GetObjectByName('edit_safelog_detail');

  ApplyTitleLogo('pic_safelog_logo', 20);

  hTitle := XC_GetObjectByName('txt_safelog_title');
  if XC_GetObjectType(hTitle) = XC_SHAPE_TEXT then
    XShapeText_SetTextColor(hTitle, UITheme_TextPrimary);
  TButtonUI.FromXmlName('btn_safelog_min', BB_NONE, 'Resource\min.svg');
  btnUi := TButtonUI.FromXmlName('btn_safelog_max', BB_NONE, cBtnSvgMax);
  TButtonUI.BindMaxButton(Handle, btnUi.Handle);
  TButtonUI.SyncMaxButtonSvg(Handle);
  TButtonUI.FromXmlName('btn_safelog_close', BB_NONE, 'Resource\close.svg');
  TButtonUI.FromXmlName('btn_safelog_copy', BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TSafeLogWindow.OnCopyClick);
  TButtonUI.FromXmlName('btn_safelog_export', BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TSafeLogWindow.OnExportClick);
  TButtonUI.FromXmlName('btn_safelog_clear', BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TSafeLogWindow.OnClearClick);

  if CListEle <> 0 then
  begin
    XList_EnableMultiSel(CListEle, False);
    XList_CreateAdapter(CListEle);
    XList_CreateAdapterHeader(CListEle);
    XList_AddColumnText(CListEle, 32, cListColIndicator, cListHeaderTextIndicator);
    XList_AddColumnText(CListEle, 44, cListColStatus, cListHeaderTextStatus);
    XList_AddColumnText(CListEle, 152, cListColTime, cListHeaderTextTime);
    XList_AddColumnText(CListEle, 52, cListColType, cListHeaderTextType);
    XList_AddColumnText(CListEle, 88, cListColFeature, cListHeaderTextFeature);
    XList_AddColumnText(CListEle, 300, cListColSummary, cListHeaderTextSummary);
    TListUI.ApplyTheme(CListEle);
    XEle_RegEvent(CListEle, XE_LIST_SELECT, @TSafeLogWindow.OnListSelect);
  end;

  if CEditDetail <> 0 then
  begin
    editUI := TEditUI(TEditUI.FromHandle(CEditDetail));
    TEditUI.ApplyEditStyle(editUI);
    editUI.EnableBorder := False;
    editUI.EnableBkColor := False;
    editUI.EnableFocusBkColor := False;
    XEdit_EnableReadOnly(CEditDetail, True);
    XEdit_EnableMultiLine(CEditDetail, True);
    XEdit_EnableAutoWrap(CEditDetail, True);
    XEdit_SetCaretWidth(CEditDetail, 0);
    editUI.EnableFocus(False);
    XEdit_SetDefaultTextColor(CEditDetail, UITheme_InputText);
    XEdit_SetText(CEditDetail, PWideChar(''));
  end;

  if IsHWINDOW then
  begin
    SafeLogBindWindow(Handle);
    RegEvent(XWM_WINDPROC, @TSafeLogWindow.OnWinProc);
  end;
end;

destructor TSafeLogWindow.Destroy;
begin
  SafeLogReleaseWindow(Handle);
  if FInstance = Self then
  begin
    FInstance := nil;
    CListEle := 0;
    CEditDetail := 0;
  end;
  inherited;
end;

class procedure TSafeLogWindow.CloseIfOpen;
begin
  if Assigned(FInstance) then
    FInstance.CloseWindow;
end;

class procedure TSafeLogWindow.ShowWindow;
var
  hLogWnd: XCGUI.HWINDOW;
  hRealWnd: Windows.HWND;
begin
  if Assigned(FInstance) then
  begin
    if FInstance.IsHWINDOW then
    begin
      hLogWnd := FInstance.Handle;
      XC_SetActivateTopWindow;
      hRealWnd := XWnd_GetHWND(hLogWnd);
      if (hRealWnd <> 0) and IsIconic(hRealWnd) then
        XWnd_ShowWindow(hLogWnd, SW_RESTORE)
      else
        XWnd_ShowWindow(hLogWnd, SW_SHOW);
      FInstance.SetTop;
      if hRealWnd <> 0 then
        SetForegroundWindow(hRealWnd);
      Exit;
    end;
    FInstance.Free;
    FInstance := nil;
  end;
  FInstance := TSafeLogWindow.LoadLayout('Resource\Layout\SafeLogWindow.xml');
  if FInstance = nil then
    Exit;
  hRealWnd := XWnd_GetHWND(FInstance.Handle);
  if hRealWnd <> 0 then
    SetWindowTextW(hRealWnd, 'QDesktop - 安全日志');
  FInstance.Show;
  SyncAllEntries;
end;

class function TSafeLogWindow.LoadLayout(const LayoutFile: PWideChar): TSafeLogWindow;
var
  h: XCGUI.HXCGUI;
begin
  h := TFormUI.LoadLayoutFile(LayoutFile, 0, 0);
  if h = 0 then
    Exit(nil);
  Result := TSafeLogWindow.FromHandle(h);
end;

end.

