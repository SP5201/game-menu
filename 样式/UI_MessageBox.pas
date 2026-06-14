unit UI_MessageBox;

interface

uses
  Windows, Messages, SysUtils, Math, XCGUI, UI_Form, UI_Button, UI_Theme;

type
  TMessageBoxUI = class(TFormUI)
  private
    class var
      CModalResult: Integer;
    class function OnBtnOK(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnCancel(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndKeyDown(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    procedure SetDialogText(const ATitle, AText: string);
  protected
    procedure Init; override;
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: XCGUI.HWINDOW = 0): TMessageBoxUI; reintroduce;
    class function Confirm(const ATitle, AText: string; const hParent: XCGUI.HWINDOW = 0; hAttachWnd: XCGUI.HWINDOW = 0): Boolean;
  end;

implementation

class function TMessageBoxUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: XCGUI.HWINDOW = 0): TMessageBoxUI;
var
  h: HXCGUI;
begin
  h := XC_LoadLayout(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := FromHandle(h);
end;

procedure TMessageBoxUI.Init;
var
  hIcon: HXCGUI;
  hSvg: XCGUI.HSVG;
  hImg: HIMAGE;
begin
  inherited;
  TFormUI.ApplyTitleLogo('pic_msgbox_dialog_logo');
  hIcon := XC_GetObjectByName('pic_msgbox_icon');
  if hIcon <> 0 then
  begin
    // 先加载 SVG → 用主色覆盖填充 → 转成图片 → 设置到 shapePicture
    hSvg := XSvg_LoadFile('Resource\msg_warning.svg');
    if XC_SVG = XC_GetObjectType(hSvg) then
    begin
      XSvg_SetSize(hSvg, 80, 80);
      XSvg_SetUserFillColor(hSvg, UITheme_PrimaryColor, True);
      hImg := XImage_LoadSvg(hSvg);
      if XC_IMAGE = XC_GetObjectType(hImg) then
        XShapePic_SetImage(hIcon, hImg);
    end;
  end;

  TButtonUI.FromXmlName('btn_msgbox_close', BB_NONE, 'Resource\close.svg').RegEvent(XE_BNCLICK, @TMessageBoxUI.OnBtnCancel);
  TButtonUI.FromXmlName('btn_msgbox_ok', BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TMessageBoxUI.OnBtnOK);
  TButtonUI.FromXmlName('btn_msgbox_cancel', BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TMessageBoxUI.OnBtnCancel);
  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TMessageBoxUI.OnWndKeyDown);
end;

procedure TMessageBoxUI.SetDialogText(const ATitle, AText: string);
begin
  XShapeText_SetTextColor(XC_GetObjectByName('txt_msgbox_title'), UITheme_TextPrimary);
  XShapeText_SetTextColor(XC_GetObjectByName('txt_msgbox_content'), UITheme_TextPrimary);
  XShapeText_SetText(XC_GetObjectByName('txt_msgbox_title'), PWideChar(ATitle));
  XShapeText_SetText(XC_GetObjectByName('txt_msgbox_content'), PWideChar(AText));
end;

class function TMessageBoxUI.OnBtnOK(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  CModalResult := IDOK;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), CModalResult);
end;

class function TMessageBoxUI.OnBtnCancel(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  CModalResult := IDCANCEL;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), CModalResult);
end;

class function TMessageBoxUI.OnWndKeyDown(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if wParam = VK_RETURN then
  begin
    pbHandled^ := True;
    if (lParam and $40000000) = 0 then
    begin
      CModalResult := IDOK;
      XModalWnd_EndModal(hWindow, CModalResult);
    end;
  end
  else if wParam = VK_ESCAPE then
  begin
    pbHandled^ := True;
    if (lParam and $40000000) = 0 then
    begin
      CModalResult := IDCANCEL;
      XModalWnd_EndModal(hWindow, CModalResult);
    end;
  end;
end;

class function TMessageBoxUI.Confirm(const ATitle, AText: string; const hParent: XCGUI.HWINDOW = 0; hAttachWnd: XCGUI.HWINDOW = 0): Boolean;
var
  dlg: TMessageBoxUI;
  szText: TSize;
  rcDlg: TRect;
begin
  dlg := TMessageBoxUI.LoadLayout('Resource\Layout\MessageBox.xml', hParent);
  dlg.SetDialogText(ATitle, AText);
  CModalResult := IDCANCEL;
  XC_GetTextShowSize(PWideChar(AText), -1, XC_GetDefaultFont, szText);
  dlg.GetRect(rcDlg);
  rcDlg.Width := Max(szText.Width + 170, 230);
  rcDlg.Height := Max(szText.Height + 190, 220);
  dlg.SetRect(rcDlg);
  Result := XModalWnd_DoModal(dlg.Handle) = IDOK;
end;

end.

