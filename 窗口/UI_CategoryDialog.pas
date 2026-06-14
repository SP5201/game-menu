unit UI_CategoryDialog;

interface

uses
  Windows, Messages, SysUtils, ShellAPI, XCGUI, UI_Form, UI_Button, UI_Edit, UI_Theme,
  UI_Icon_ListView, UI_HintPopup, AppConfig;

type
  TCategoryDialogUI = class(TFormUI)
  private
    class var
      FCategoryDialogIcon: HXCGUI;
      FResultName: PString;
      FResultIconFile: PString;
      FSelectedIconFile: string;
      FEdtCategoryName: TEditUI;
      FListCategoryIcons: TIconListViewUI;
    class function ResolveCategoryIconDir(const AEnsureExists: Boolean): string; static;
    class function ApplyPreviewSvg(const ASvgPath: string): Boolean; static;
    procedure InitCategoryIconList;
    class function OnCategoryIconSelect(hEle: XCGUI.HELE; iGroup, iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnOK(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnCancel(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnOpenIconDir(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndKeyDown(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    procedure SetDialogText(const AName, AIconFile, ATitle, AConfirmText: string);
  protected
    procedure Init; override;
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: XCGUI.HWINDOW = 0): TCategoryDialogUI; reintroduce;
    class function EditCategory(var AName, AIconFile: string; const ATitle, AConfirmText: string; const hParent: XCGUI.HWINDOW = 0; hAttachWnd: XCGUI.HWINDOW = 0): Boolean;
  end;

implementation

uses
  AppPaths;

const
  ID_BTN_DIALOG_CLOSE = 'btn_category_dialog_close';
  ID_BTN_ICON_HINT = 'btn_category_icon_hint';
  ID_BTN_CONFIRM = 'btn_category_confirm';
  ID_BTN_CANCEL = 'btn_category_cancel';
  ID_EDIT_CATEGORY_NAME = 'edit_category_name';
  ID_LIST_CATEGORY_ICONS = 'list_category_icons';
  ID_TXT_DIALOG_TITLE = 'txt_category_dialog_title';
  ID_TXT_LABEL_NAME = 'txt_category_label_name';
  ID_LINK_OPEN_ICON_DIR = 'link_category_open_icon_dir';
  ID_PIC_CATEGORY_ICON = 'pic_category_icon';

class function TCategoryDialogUI.ResolveCategoryIconDir(const AEnsureExists: Boolean): string;
begin
  Result := IncludeTrailingPathDelimiter(AppExeDirectory) + 'Resource\CategoryIcons';
  if DirectoryExists(Result) then
    Exit;
  if AEnsureExists then
    ForceDirectories(Result);
end;

class function TCategoryDialogUI.ApplyPreviewSvg(const ASvgPath: string): Boolean;
var
  hSvg: XCGUI.HSVG;
  hImg: HIMAGE;
begin
  Result := False;
  if FCategoryDialogIcon = 0 then
    Exit;

  hSvg := XSvg_LoadFile(PWideChar(ASvgPath));
  if XC_SVG <> XC_GetObjectType(hSvg) then
    Exit;

  XSvg_SetSize(hSvg, 18, 18);
  XSvg_SetUserFillColor(hSvg, UITheme_InputText, True);
  XSvg_SetUserStrokeColor(hSvg, UITheme_InputText, 1, True);
  hImg := XImage_LoadSvg(hSvg);
  if XC_IMAGE <> XC_GetObjectType(hImg) then
    Exit;

  XShapePic_SetImage(FCategoryDialogIcon, hImg);
  XShape_Redraw(FCategoryDialogIcon);
  Result := True;
end;

procedure TCategoryDialogUI.InitCategoryIconList;
var
  iconDir: string;
begin
  FListCategoryIcons := TIconListViewUI.FromXmlName(ID_LIST_CATEGORY_ICONS);
  if FListCategoryIcons = nil then
    Exit;

  iconDir := ResolveCategoryIconDir(False);

  FListCategoryIcons.AddSvgIconsFromDir(iconDir, UITheme_InputText);
  if FListCategoryIcons.Item_GetCount(0) <= 0 then
    FListCategoryIcons.AddSvgIconItem('Resource\category\default.svg', UITheme_InputText);
end;

class function TCategoryDialogUI.OnCategoryIconSelect(hEle: XCGUI.HELE; iGroup, iItem: Integer; pbHandled: PBOOL): Integer; stdcall;
var
  ListView: TIconListViewUI;
  iconPath: string;
begin
  Result := 0;
  if FCategoryDialogIcon = 0 then
    Exit;

  ListView := TIconListViewUI(XEle_GetUserData(hEle));
  if ListView = nil then
    Exit;

  iconPath := ListView.GetItemSvgPath(iGroup, iItem);
  if iconPath = '' then
    Exit;
  if ApplyPreviewSvg(iconPath) then
    FSelectedIconFile := iconPath;
end;

class function TCategoryDialogUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: XCGUI.HWINDOW = 0): TCategoryDialogUI;
var
  h: HXCGUI;
begin
  h := XC_LoadLayout(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := FromHandle(h);
end;

class function TCategoryDialogUI.OnOpenIconDir(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
var
  iconDir: string;
begin
  Result := 0;
  pbHandled^ := True;

  iconDir := ResolveCategoryIconDir(True);

  ShellExecuteW(XWidget_GetHWND(hEle), 'open', PWideChar(iconDir), nil, nil, SW_SHOWNORMAL);
end;

procedure TCategoryDialogUI.Init;
var
  hOpenIconDirLink: hEle;
  hIconHintBtn: HELE;
begin
  inherited;
  TFormUI.ApplyTitleLogo('pic_category_dialog_logo', 20, Handle);
  TButtonUI.FromXmlName(ID_BTN_DIALOG_CLOSE, BB_NONE, 'Resource\close.svg');
  TButtonUI.FromXmlName(ID_BTN_ICON_HINT, BB_NONE, 'Resource\hint.svg');
  hIconHintBtn := XC_GetObjectByName(ID_BTN_ICON_HINT);
  THintPopupUI.BindHoverHint(hIconHintBtn, '请把SVG放到图标文件夹内' + sLineBreak + '重启软件后生效');
  TButtonUI.FromXmlName(ID_BTN_CONFIRM, BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TCategoryDialogUI.OnBtnOK);
  TButtonUI.FromXmlName(ID_BTN_CANCEL, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TCategoryDialogUI.OnBtnCancel);
  FEdtCategoryName := TEditUI.FromXmlName(ID_EDIT_CATEGORY_NAME);
  InitCategoryIconList;
  if FListCategoryIcons <> nil then
    FListCategoryIcons.RegEvent(XE_LISTVIEW_SELECT, @TCategoryDialogUI.OnCategoryIconSelect);
  XShapeText_SetTextColor(XC_GetObjectByName(ID_TXT_DIALOG_TITLE), UITheme_TextPrimary);
  XShapeText_SetTextColor(XC_GetObjectByName(ID_TXT_LABEL_NAME), UITheme_TextPrimary);

  hOpenIconDirLink := XC_GetObjectByName(ID_LINK_OPEN_ICON_DIR);
  if hOpenIconDirLink <> 0 then
  begin
    XEle_SetTextColor(hOpenIconDirLink, RGBA(255, 255, 255, 60));
    XTextLink_SetTextColorStay(hOpenIconDirLink, UITheme_PrimaryColor);
    XTextLink_SetUnderlineColorLeave(hOpenIconDirLink, 0);
    XTextLink_SetUnderlineColorStay(hOpenIconDirLink, UITheme_PrimaryColor);
    XEle_RegEvent(hOpenIconDirLink, XE_BNCLICK, @TCategoryDialogUI.OnOpenIconDir);
  end;

  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TCategoryDialogUI.OnWndKeyDown);

  FCategoryDialogIcon := XC_GetObjectByName(ID_PIC_CATEGORY_ICON);
  ApplyPreviewSvg('Resource\category\default.svg');
end;

procedure TCategoryDialogUI.SetDialogText(const AName, AIconFile, ATitle, AConfirmText: string);
var
  hTitle: HXCGUI;
  hBtnOk: HELE;
  groupIndex, itemIndex: Integer;
  iconPath: string;
  hasIconItems: Boolean;
begin
  if FEdtCategoryName <> nil then
    FEdtCategoryName.SetText(AName);

  hTitle := XC_GetObjectByName(ID_TXT_DIALOG_TITLE);
  if hTitle <> 0 then
    XShapeText_SetText(hTitle, PWideChar(ATitle));

  hBtnOk := XC_GetObjectByName(ID_BTN_CONFIRM);
  if hBtnOk <> 0 then
    XBtn_SetText(hBtnOk, PWideChar(AConfirmText));

  FSelectedIconFile := '';
  iconPath := ExpandFileName(Trim(AIconFile));
  if (iconPath = '') or not FileExists(iconPath) then
    iconPath := TAppConfig.ResolveGroupIconFile(AIconFile);
  if (iconPath <> '') and (FListCategoryIcons <> nil) and
    FListCategoryIcons.FindItemBySvgPath(iconPath, groupIndex, itemIndex) and
    FListCategoryIcons.SetSelectItem(groupIndex, itemIndex) then
    OnCategoryIconSelect(FListCategoryIcons.Handle, groupIndex, itemIndex, nil);

  hasIconItems := Assigned(FListCategoryIcons) and (FListCategoryIcons.Item_GetCount(0) > 0);
  if FSelectedIconFile = '' then
  begin
    if hasIconItems then
    begin
      FListCategoryIcons.SetSelectItem(0, 0);
      OnCategoryIconSelect(FListCategoryIcons.Handle, 0, 0, nil);
    end
    else
    begin
      FSelectedIconFile := TAppConfig.ResolveGroupIconFile('');
      ApplyPreviewSvg(FSelectedIconFile);
    end;
  end;
end;

class function TCategoryDialogUI.OnBtnOK(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
var
  newName: string;
begin
  Result := 0;
  pbHandled^ := True;
  if (FEdtCategoryName = nil) or (FResultName = nil) or (FResultIconFile = nil) then
    Exit;
  newName := Trim(FEdtCategoryName.Text);
  if newName = '' then
    Exit;
  FResultName^ := newName;
  if not Assigned(FListCategoryIcons) or
    (not FListCategoryIcons.GetSelectedSvgPath(FResultIconFile^)) then
    FResultIconFile^ := FSelectedIconFile;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDOK);
end;

class function TCategoryDialogUI.OnBtnCancel(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDCANCEL);
end;

class function TCategoryDialogUI.OnWndKeyDown(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
var
  newName: string;
begin
  Result := 0;
  if wParam = VK_RETURN then
  begin
    pbHandled^ := True;
    if (lParam and $40000000) = 0 then
    begin
      if (FEdtCategoryName = nil) or (FResultName = nil) or (FResultIconFile = nil) then
        Exit;
      newName := Trim(FEdtCategoryName.Text);
      if newName = '' then
        Exit;
      FResultName^ := newName;
      if not Assigned(FListCategoryIcons) or
        (not FListCategoryIcons.GetSelectedSvgPath(FResultIconFile^)) then
        FResultIconFile^ := FSelectedIconFile;
      XModalWnd_EndModal(hWindow, IDOK);
    end;
  end
  else if wParam = VK_ESCAPE then
  begin
    pbHandled^ := True;
    XModalWnd_EndModal(hWindow, IDCANCEL);
  end;
end;

class function TCategoryDialogUI.EditCategory(var AName, AIconFile: string; const ATitle,
  AConfirmText: string; const hParent: XCGUI.HWINDOW = 0; hAttachWnd: XCGUI.HWINDOW = 0): Boolean;
var
  dlg: TCategoryDialogUI;
  titleText, confirmText: string;
begin
  dlg := TCategoryDialogUI.LoadLayout('Resource\Layout\CategoryDialog.xml', hParent, hAttachWnd);
  if dlg = nil then
    Exit(False);
  titleText := Trim(ATitle);
  confirmText := Trim(AConfirmText);
  if titleText = '' then
    titleText := '分类';
  if confirmText = '' then
    confirmText := '保存';
  dlg.SetDialogText(AName, AIconFile, titleText, confirmText);
  dlg.FResultName := @AName;
  dlg.FResultIconFile := @AIconFile;
  Result := XModalWnd_DoModal(dlg.Handle) = IDOK;
end;

end.

