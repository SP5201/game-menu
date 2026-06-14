unit UI_FeedbackDialog;

interface

uses
  Windows, Messages, SysUtils, XCGUI, UI_Form, UI_Button, UI_Edit,
  UI_Theme, UI_MessageBox;

type
  TFeedbackDialogUI = class(TFormUI)
  private
    class var
      FEdtContent: TEditUI;
    class function OnBtnSend(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnCancel(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: Integer = 0): TFeedbackDialogUI; reintroduce;
    class procedure ShowDialog(const hParent: Windows.HWND = 0; hAttachWnd: Integer = 0);
  end;

implementation

uses
  FeedbackMailer;

const
  ID_BTN_DIALOG_CLOSE = 'btn_feedback_close';
  ID_BTN_SEND         = 'btn_feedback_send';
  ID_BTN_CANCEL       = 'btn_feedback_cancel';
  ID_EDIT_CONTENT     = 'edit_feedback_content';
  ID_TXT_DIALOG_TITLE = 'txt_feedback_title';

class function TFeedbackDialogUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI; hAttachWnd: Integer): TFeedbackDialogUI;
var
  h: HXCGUI;
begin
  h := XC_LoadLayout(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := FromHandle(h);
end;

procedure TFeedbackDialogUI.Init;
begin
  inherited;
  TFormUI.ApplyTitleLogo('pic_feedback_dialog_logo');
  TButtonUI.FromXmlName(ID_BTN_DIALOG_CLOSE, BB_NONE, 'Resource\close.svg');
  TButtonUI.FromXmlName(ID_BTN_SEND, BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TFeedbackDialogUI.OnBtnSend);
  TButtonUI.FromXmlName(ID_BTN_CANCEL, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TFeedbackDialogUI.OnBtnCancel);
  XShapeText_SetTextColor(XC_GetObjectByName(ID_TXT_DIALOG_TITLE), UITheme_TextPrimary);
  FEdtContent := TEditUI.FromXmlName(ID_EDIT_CONTENT);
  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TFeedbackDialogUI.OnWndKeyDown);
end;

class function TFeedbackDialogUI.OnBtnSend(hEle: HELE; pbHandled: PBOOL): Integer;
var
  ownerWnd: Windows.HWND;
  feedbackText, errMsg: string;
begin
  Result := 0;
  pbHandled^ := True;
  if FEdtContent = nil then
    Exit;
  feedbackText := Trim(FEdtContent.Text);
  if feedbackText = '' then
  begin
    TMessageBoxUI.Confirm('提示', '请输入反馈内容。', XWidget_GetHWND(hEle));
    Exit;
  end;
  ownerWnd := XWidget_GetHWND(hEle);
  if not SendFeedbackMessage(feedbackText, ownerWnd, errMsg) then
  begin
    TMessageBoxUI.Confirm('打开失败', '无法在浏览器中打开 GitHub 反馈页面。' + sLineBreak + sLineBreak + errMsg, ownerWnd);
    Exit;
  end;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDOK);
end;

class function TFeedbackDialogUI.OnBtnCancel(hEle: HELE; pbHandled: PBOOL): Integer;
begin
  Result := 0;
  pbHandled^ := True;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDCANCEL);
end;

class function TFeedbackDialogUI.OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer;
begin
  Result := 0;
  if wParam = VK_ESCAPE then
  begin
    pbHandled^ := True;
    XModalWnd_EndModal(hWindow, IDCANCEL);
  end;
end;

class procedure TFeedbackDialogUI.ShowDialog(const hParent: Windows.HWND; hAttachWnd: Integer);
var
  dlg: TFeedbackDialogUI;
begin
  dlg := TFeedbackDialogUI.LoadLayout('Resource\Layout\FeedbackDialog.xml', hParent, hAttachWnd);
  if dlg = nil then
    Exit;
  if FEdtContent <> nil then
    FEdtContent.SetText('');
  XModalWnd_DoModal(dlg.Handle);
end;

end.
