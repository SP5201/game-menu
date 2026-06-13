unit UI_EditItemDialog;

interface

uses
  Windows, Messages, SysUtils, XCGUI, UI_Form, UI_Button, UI_Edit,
  UI_Ele, UI_Theme, UI_ComboBox;

type
  TEditItemDialogUI = class(TFormUI)
  private
    FResultTitle: PString;
    FResultParams: PString;
    FResultWorkingDir: PString;
    FResultShowCmd: PInteger;
    FResultIconPath: PString;
    FCurrentIconPath: string;
    FIconChanged: Boolean;
    FEdtPath: TEditUI;
    FEdtTitle: TEditUI;
    FEdtParams: TEditUI;
    FEdtWorkDir: TEditUI;
    FEdtHotkey: TEditUI;
    FComboShowCmd: TComboBoxUI;
    FPicIcon: HELE;
    class function OnBtnOK(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnCancel(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnChangeIcon(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    procedure SetItemImage(const AIcon: HIMAGE = 0);
    procedure SetFields(const AFilePath, ATitle, AParams, AWorkingDir, AIconPath: string; const AShowCmd: Integer; const AIcon: HIMAGE = 0);
    procedure GetFields(out ATitle, AParams, AWorkingDir: string; out AShowCmd: Integer);
  protected
    procedure Init; override;
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: Integer = 0): TEditItemDialogUI; reintroduce;
    class function EditItem(const AFilePath: string; const AIcon: HIMAGE; var ATitle, AParams, AWorkingDir: string;
      var AShowCmd: Integer; var AIconPath: string; out AIconChanged: Boolean; const hParent: HWND): Boolean;
  end;

implementation

uses
  AppConfig, ShellHelper, ListItemTypes, UI_ListView, UI_HintPopup;

function ResolveEditItemPreviewIcon(const AIcon: HIMAGE; const AIconPath, AFilePath: string): HIMAGE;
var
  iconPath, iconCacheOut: string;
begin
  Result := AIcon;
  if XC_GetObjectType(Result) = XC_IMAGE then
    Exit;

  iconPath := ResolveItemIconPath(AIconPath);
  if (iconPath <> '') and FileExists(iconPath) then
    Result := LoadXImageFromFileMemory(iconPath);

  if XC_GetObjectType(Result) = XC_IMAGE then
    Exit;

  Result := AcquireListItemFileImage(AIconPath, AFilePath, iconCacheOut);

  if XC_GetObjectType(Result) = XC_IMAGE then
    Exit;

  Result := 0;
end;

class function TEditItemDialogUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI; hAttachWnd: Integer): TEditItemDialogUI;
var
  h: HXCGUI;
begin
  h := XC_LoadLayout(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := FromHandle(h);
end;

procedure TEditItemDialogUI.Init;
const
  PathHintText = '支持系统变量写法和相对路径写法' + sLineBreak + '# 系统变量路径' + sLineBreak + '%APPDATA%/MyApp/icons/settings.svg' + sLineBreak + '$HOME/.myapp/icons/error.svg' + sLineBreak + sLineBreak + '# 相对路径' + sLineBreak + './icons/loading.svg' + sLineBreak + '../resources/check.svg' + sLineBreak + './ui/toolbar/print.svg';
var
  hIconBorderEle: TEleUI;
  btnPathHint: TButtonUI;
begin
  inherited;
  TFormUI.ApplyTitleLogo('pic_edititem_dialog_logo');
  TButtonUI.FromXmlName('btn_edititem_close', BB_NONE, 'Resource\close.svg');
  btnPathHint := TButtonUI.FromXmlName('btn_edititem_path_hint_icon', BB_NONE, 'Resource\hint.svg');
  if btnPathHint <> nil then
    THintPopupUI.BindHoverHint(btnPathHint.Handle, PathHintText);
  TButtonUI.FromXmlName('btn_edititem_ok', BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TEditItemDialogUI.OnBtnOK);
  TButtonUI.FromXmlName('btn_edititem_cancel', BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TEditItemDialogUI.OnBtnCancel);
  TButtonUI.FromXmlName('btn_edititem_change_icon', BB_EnableBorder, '').RegEvent(XE_BNCLICK, @TEditItemDialogUI.OnBtnChangeIcon);
  TButtonUI.FromXmlName('btn_edititem_run_as_admin', BB_EnableCheckStyle, '');
  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TEditItemDialogUI.OnWndKeyDown);

  XShapeText_SetTextColor(XC_GetObjectByName('txt_edititem_title'), UITheme_TextPrimary);
  XShapeText_SetTextColor(XC_GetObjectByName('txt_edititem_label_path'), UITheme_TextPrimary);
  XShapeText_SetTextColor(XC_GetObjectByName('txt_edititem_label_title'), UITheme_TextPrimary);
  XShapeText_SetTextColor(XC_GetObjectByName('txt_edititem_label_params'), UITheme_TextPrimary);
  XShapeText_SetTextColor(XC_GetObjectByName('txt_edititem_label_workdir'), UITheme_TextPrimary);
  XShapeText_SetTextColor(XC_GetObjectByName('txt_edititem_label_hotkey'), UITheme_TextPrimary);
  XShapeText_SetTextColor(XC_GetObjectByName('txt_edititem_label_show_cmd'), UITheme_TextPrimary);

  FEdtPath := TEditUI.FromXmlName('edit_item_path');
  FEdtTitle := TEditUI.FromXmlName('edit_item_title');
  FEdtParams := TEditUI.FromXmlName('edit_item_params');
  FEdtWorkDir := TEditUI.FromXmlName('edit_item_workdir');
  FEdtHotkey := TEditUI.FromXmlName('edit_item_hotkey');
  FComboShowCmd := TComboBoxUI.FromXmlName('combo_item_show_cmd');
  FPicIcon := XC_GetObjectByName('pic_edititem_icon');

  FComboShowCmd.InitTextItems(['常规窗口', '最大化', '最小化'], 0);

  hIconBorderEle := TEleUI.FromXmlName('rect_edititem_icon_border');
  hIconBorderEle.EnableBorder := True;
  hIconBorderEle.BorderColor := UITheme_BorderDefault;
end;

procedure TEditItemDialogUI.SetItemImage(const AIcon: HIMAGE = 0);
begin
  if XC_GetObjectType(AIcon) <> XC_IMAGE then
    Exit;
  XImage_SetDrawType(AIcon, image_draw_type_fixed_ratio);
  XShapePic_SetImage(FPicIcon, AIcon);
  if XC_IsShape(FPicIcon) then
    XShape_Redraw(FPicIcon);
end;

procedure TEditItemDialogUI.SetFields(const AFilePath, ATitle, AParams, AWorkingDir, AIconPath: string; const AShowCmd: Integer; const AIcon: HIMAGE = 0);
begin
  FEdtPath.SetText(AFilePath);
  FEdtTitle.SetText(ATitle);
  FEdtParams.SetText(AParams);
  FEdtWorkDir.SetText(AWorkingDir);
  FCurrentIconPath := AIconPath;
  FIconChanged := False;
  FComboShowCmd.SetSelItem(ComboIndexFromShowCmd(AShowCmd));
  SetItemImage(AIcon);
end;

procedure TEditItemDialogUI.GetFields(out ATitle, AParams, AWorkingDir: string; out AShowCmd: Integer);
begin
  ATitle := FEdtTitle.Text;
  AParams := FEdtParams.Text;
  AWorkingDir := FEdtWorkDir.Text;
  AShowCmd := ShowCmdFromComboIndex(XComboBox_GetSelItem(FComboShowCmd.Handle));
end;

class function TEditItemDialogUI.OnBtnOK(hEle: hEle; pbHandled: PBOOL): Integer; stdcall;
var
  dlg: TEditItemDialogUI;
  title, params, workDir: string;
  showCmd: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  dlg := TEditItemDialogUI.FromHandle(XWidget_GetHWINDOW(hEle));
  dlg.GetFields(title, params, workDir, showCmd);

  dlg.FResultTitle^ := title;
  dlg.FResultParams^ := params;
  dlg.FResultWorkingDir^ := workDir;
  dlg.FResultShowCmd^ := showCmd;
  if dlg.FIconChanged and (dlg.FResultIconPath <> nil) then
    dlg.FResultIconPath^ := dlg.FCurrentIconPath;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDOK);
end;

class function TEditItemDialogUI.OnBtnCancel(hEle: hEle; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDCANCEL);
end;

class function TEditItemDialogUI.OnBtnChangeIcon(hEle: hEle; pbHandled: PBOOL): Integer; stdcall;
var
  dlg: TEditItemDialogUI;
  iconPath: string;
  hIconImage: HIMAGE;
  fileItem: TListViewFileItem;
begin
  Result := 0;
  pbHandled^ := True;
  dlg := TEditItemDialogUI.FromHandle(XWidget_GetHWINDOW(hEle));
  if dlg = nil then
    Exit;
  if not OpenFileDialogSingle(dlg.HWND, '选择图标',
    '支持文件 (*.exe;*.jpg;*.jpeg;*.png;*.ico)|*.exe;*.jpg;*.jpeg;*.png;*.ico|可执行文件 (*.exe)|*.exe|图片文件 (*.jpg;*.jpeg;*.png;*.ico)|*.jpg;*.jpeg;*.png;*.ico|所有文件 (*.*)|*.*',
    iconPath) then
    Exit;

  if SameText(ExtractFileExt(iconPath), '.exe') then
  begin
    fileItem := GetListViewFileItemFromParsingPath(iconPath, True);
    hIconImage := fileItem.FileImage;
    if XC_GetObjectType(hIconImage) = XC_IMAGE then
    begin
      XImage_AddRef(hIconImage);
      dlg.FCurrentIconPath := Trim(fileItem.IconCachePath);
    end;
  end
  else
    hIconImage := LoadXImageFromFileMemory(iconPath);

  if XC_GetObjectType(hIconImage) <> XC_IMAGE then
    Exit;

  if dlg.FCurrentIconPath = '' then
  begin
    if SameText(ExtractFileExt(iconPath), '.exe') then
      dlg.FCurrentIconPath := Trim(fileItem.IconCachePath)
    else
      dlg.FCurrentIconPath := iconPath;
  end;
  dlg.FIconChanged := True;
  dlg.SetItemImage(hIconImage);
  if XC_GetObjectType(hIconImage) = XC_IMAGE then
    XImage_Release(hIconImage);
end;

class function TEditItemDialogUI.OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
var
  dlg: TEditItemDialogUI;
  title, params, workDir: string;
  showCmd: Integer;
begin
  Result := 0;
  if wParam = VK_RETURN then
  begin
    pbHandled^ := True;
    if (lParam and $40000000) = 0 then
    begin
      dlg := TEditItemDialogUI.FromHandle(hWindow);
      if dlg <> nil then
      begin
        dlg.GetFields(title, params, workDir, showCmd);
        dlg.FResultTitle^ := title;
        dlg.FResultParams^ := params;
        dlg.FResultWorkingDir^ := workDir;
        dlg.FResultShowCmd^ := showCmd;
        if dlg.FIconChanged and (dlg.FResultIconPath <> nil) then
          dlg.FResultIconPath^ := dlg.FCurrentIconPath;
      end;
      XModalWnd_EndModal(hWindow, IDOK);
    end;
  end
  else if wParam = VK_ESCAPE then
  begin
    pbHandled^ := True;
    XModalWnd_EndModal(hWindow, IDCANCEL);
  end;
end;

class function TEditItemDialogUI.EditItem(const AFilePath: string; const AIcon: HIMAGE; var ATitle, AParams, AWorkingDir: string;
  var AShowCmd: Integer; var AIconPath: string; out AIconChanged: Boolean; const hParent: HWND): Boolean;
var
  dlg: TEditItemDialogUI;
  hIcon: HIMAGE;
begin
  AIconChanged := False;
  hIcon := ResolveEditItemPreviewIcon(AIcon, AIconPath, AFilePath);
  dlg := TEditItemDialogUI.LoadLayout('Resource\Layout\EditItemDialog.xml', hParent);
  if XC_GetObjectType(hIcon) = XC_IMAGE then
  begin
    XImage_AddRef(hIcon);
    XImage_SetDrawType(hIcon, image_draw_type_fixed_ratio);
  end;
  dlg.SetFields(AFilePath, ATitle, AParams, AWorkingDir, AIconPath, AShowCmd, hIcon);
  dlg.FResultTitle := @ATitle;
  dlg.FResultParams := @AParams;
  dlg.FResultWorkingDir := @AWorkingDir;
  dlg.FResultShowCmd := @AShowCmd;
  dlg.FResultIconPath := @AIconPath;

  Result := XModalWnd_DoModal(dlg.Handle) = IDOK;
  if Result then
    AIconChanged := dlg.FIconChanged;
end;

end.

