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
    class function OnBtnSend(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: XCGUI.HWINDOW = 0): TFeedbackDialogUI; reintroduce;
    class procedure ShowDialog(const hParent: XCGUI.HWINDOW = 0; hAttachWnd: XCGUI.HWINDOW = 0);
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

class function TFeedbackDialogUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI; hAttachWnd: XCGUI.HWINDOW): TFeedbackDialogUI;
var
  h: HXCGUI;
begin
  h := TFormUI.LoadLayoutFile(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := TFeedbackDialogUI.FromHandle(h);
end;

procedure TFeedbackDialogUI.Init;
begin
  inherited;
  SetupDialogChrome('pic_feedback_dialog_logo', ID_BTN_DIALOG_CLOSE);
  TButtonUI.FromXmlName(ID_BTN_SEND, BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TFeedbackDialogUI.OnBtnSend);
  TButtonUI.FromXmlName(ID_BTN_CANCEL, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TFormUI.OnBtnModalCancel);
  XShapeText_SetTextColor(XC_GetObjectByName(ID_TXT_DIALOG_TITLE), UITheme_TextPrimary);
  FEdtContent := TEditUI.FromXmlName(ID_EDIT_CONTENT);
  RegModalEscape;
end;

class function TFeedbackDialogUI.OnBtnSend(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
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
    TMessageBoxUI.Confirm('提示', '请输入反馈内容。', XWidget_GetHWINDOW(hEle));
    Exit;
  end;
  ownerWnd := XWidget_GetHWND(hEle);
  if not SendFeedbackMessage(feedbackText, ownerWnd, errMsg) then
  begin
    TMessageBoxUI.Confirm('打开失败', '无法在浏览器中打开 GitHub 反馈页面。' + sLineBreak + sLineBreak + errMsg, XWidget_GetHWINDOW(hEle));
    Exit;
  end;
  TFormUI.EndModalOk(hEle);
end;

class procedure TFeedbackDialogUI.ShowDialog(const hParent: XCGUI.HWINDOW; hAttachWnd: XCGUI.HWINDOW);
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
