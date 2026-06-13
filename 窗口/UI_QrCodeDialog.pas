unit UI_QrCodeDialog;

interface

uses
  Windows, Messages, SysUtils, Classes, Math, ShlObj, XCGUI, UI_Form, UI_Button,
  UI_Edit, UI_Theme, UI_Ele, UI_ComboBox, DelphiZXingQRCode, UI_ColorPickerDialog, UI_HintPopup,
  UI_MessageBox, ShellHelper, UI_QrCodeRender;

type
  TQrCodeDialogUI = class(TFormUI)
  private
    class var
      FEdtText: TEditUI;
      FEdtPath: TEditUI;
      FSliderRadius: HELE;
      FLabelRadiusValue: HELE;
      FPreviewEle: HELE;
      FComboLevel: TComboBoxUI;
      FComboFormat: TComboBoxUI;
      FQRCode: TDelphiZXingQRCode;
      FQRModuleRadius: Integer;
      FBgR, FBgG, FBgB: Integer;
      FBgA: Byte;
      FFgR, FFgG, FFgB: Integer;
      FFgA: Byte;
      FLiquify: Boolean;
    class function OnBtnLiquify(hEle: HELE; bCheck: BOOL; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnCancel(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnSave(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnBrowse(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnEditTextChanged(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnComboLevelChanged(hEle: HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class procedure DoGenerateQRCode(ForceECIndex: Integer = -1); static;
    class procedure RedrawPreview; static;
    class function DoSaveQRCode(hOwnerWnd: Windows.HWND): Boolean; static;
    class function RenderQRCodeToFile(const AFilePath, AExt: string): Boolean; static;
    class function OnSliderChange(hEle: HELE; nPos: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnSliderPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnSliderBtnPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnPreviewPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnBgColor(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnBgColorPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnFgColor(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnFgColorPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    procedure InitPreviewArea;
    procedure InitSliderBar;
    procedure UpdateRadiusLabel;
  protected
    procedure Init; override;
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: Integer = 0): TQrCodeDialogUI; reintroduce;
    class procedure ShowDialog(const hParent: HWND = 0; hAttachWnd: Integer = 0);
  end;

implementation

const
  ID_BTN_DIALOG_CLOSE = 'btn_qrcode_close';
  ID_BTN_CANCEL       = 'btn_qrcode_cancel';
  ID_BTN_SAVE         = 'btn_qrcode_save';
  ID_EDIT_TEXT        = 'edit_qrcode_text';
  ID_SLIDER_RADIUS    = 'slider_qrcode_radius';
  ID_TXT_RADIUS_VALUE = 'txt_qrcode_radius_value';
  ID_TXT_DIALOG_TITLE = 'txt_qrcode_title';
  ID_TXT_LABEL_TEXT   = 'txt_qrcode_label_text';
  ID_TXT_LABEL_RADIUS = 'txt_qrcode_label_radius';
  ID_ELE_PREVIEW      = 'ele_qrcode_preview';
  ID_EDIT_PATH        = 'edit_qrcode_path';
  ID_BTN_BROWSE       = 'btn_qrcode_browse';
  ID_TXT_LABEL_PATH   = 'txt_qrcode_label_path';
  ID_COMBO_LEVEL      = 'combox_qrcode_level';
  ID_TXT_LABEL_LEVEL  = 'txt_qrcode_label_level';
  ID_COMBO_FORMAT     = 'combox_qrcode_format';
  ID_TXT_LABEL_FORMAT = 'txt_qrcode_label_format';
  ID_BTN_HINT         = 'btn_qrcode_hint';
  ID_BTN_LIQUIFY      = 'btn_qrcode_liquify';
  ID_BTN_BG_COLOR     = 'btn_qrcode_bgcolor';
  ID_TXT_LABEL_BG_COLOR = 'txt_qrcode_label_bgcolor';
  ID_BTN_FG_COLOR     = 'btn_qrcode_fgcolor';
  ID_TXT_LABEL_FG_COLOR = 'txt_qrcode_label_fgcolor';

class function TQrCodeDialogUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: Integer = 0): TQrCodeDialogUI;
var
  h: HXCGUI;
begin
  h := XC_LoadLayout(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := FromHandle(h);
end;

procedure TQrCodeDialogUI.InitPreviewArea;
begin
  FPreviewEle := XC_GetObjectByName(ID_ELE_PREVIEW);
  if FPreviewEle = 0 then
    Exit;

  XEle_EnableBkTransparent(FPreviewEle, True);
  XEle_RegEvent(FPreviewEle, XE_PAINT, @TQrCodeDialogUI.OnPreviewPaint);
end;

procedure TQrCodeDialogUI.UpdateRadiusLabel;
var
  posVal: Integer;
begin
  if (FSliderRadius = 0) or (FLabelRadiusValue = 0) then
    Exit;

  posVal := XSliderBar_GetPos(FSliderRadius);
  XShapeText_SetText(FLabelRadiusValue, PWideChar(IntToStr(posVal)));
  XShape_Redraw(FLabelRadiusValue);
end;

procedure TQrCodeDialogUI.InitSliderBar;
var
  hSliderBtn: HELE;
begin
  FSliderRadius := XC_GetObjectByName(ID_SLIDER_RADIUS);
  if FSliderRadius = 0 then
    Exit;

  // 设置滑动条为水平方向，范围 0-50，背景透明，不绘制焦点边框
  XSliderBar_EnableHorizon(FSliderRadius, True);
  XSliderBar_SetRange(FSliderRadius, 50);
  XSliderBar_SetPos(FSliderRadius, 0);
  XEle_EnableBkTransparent(FSliderRadius, True);
  XEle_EnableDrawFocus(FSliderRadius, False);
  XEle_RegEvent(FSliderRadius, XE_PAINT, @TQrCodeDialogUI.OnSliderPaint);

  // 滑块按钮改为圆形
  hSliderBtn := XSliderBar_GetButton(FSliderRadius);
  if hSliderBtn <> 0 then
  begin
    XSliderBar_SetButtonWidth(FSliderRadius, 14);
    XSliderBar_SetButtonHeight(FSliderRadius, 14);
    XEle_RegEvent(hSliderBtn, XE_PAINT, @TQrCodeDialogUI.OnSliderBtnPaint);
  end;

  // 注册滑动条变化事件
  XEle_RegEvent(FSliderRadius, XE_SLIDERBAR_CHANGE, @TQrCodeDialogUI.OnSliderChange);
end;

procedure TQrCodeDialogUI.Init;
var
  hTitle, hLabelText, hLabelRadius, hLabelPath, hLabelLevel, hLabelBgColor, hLabelFgColor: HELE;
  btnBrowse, btnSave, btnBgColor, btnFgColor, btnHint, btnLiquify: TButtonUI;
  desktopPath: array[0..MAX_PATH] of WideChar;
begin
  inherited;
  TFormUI.ApplyTitleLogo('pic_qrcode_dialog_logo');

  TButtonUI.FromXmlName(ID_BTN_DIALOG_CLOSE, BB_NONE, 'Resource\close.svg').RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnCancel);
  TButtonUI.FromXmlName(ID_BTN_CANCEL, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnCancel);

  btnBrowse := TButtonUI.FromXmlName(ID_BTN_BROWSE, BB_EnableBorder, '');
  if XC_BUTTON = XC_GetObjectType(btnBrowse.Handle) then
    btnBrowse.RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnBrowse);

  btnSave := TButtonUI.FromXmlName(ID_BTN_SAVE, BB_EnableHighlightBk, '');
  if XC_BUTTON = XC_GetObjectType(btnSave.Handle) then
    btnSave.RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnSave);

  btnBgColor := TButtonUI.FromXmlName(ID_BTN_BG_COLOR, BB_EnableBorder, '');
  if XC_BUTTON = XC_GetObjectType(btnBgColor.Handle) then
  begin
    btnBgColor.RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnBgColor);
    XEle_RegEvent(btnBgColor.Handle, XE_PAINT, @TQrCodeDialogUI.OnBtnBgColorPaint);
  end;

  btnFgColor := TButtonUI.FromXmlName(ID_BTN_FG_COLOR, BB_EnableBorder, '');
  if XC_BUTTON = XC_GetObjectType(btnFgColor.Handle) then
  begin
    btnFgColor.RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnFgColor);
    XEle_RegEvent(btnFgColor.Handle, XE_PAINT, @TQrCodeDialogUI.OnBtnFgColorPaint);
  end;

  FEdtText := TEditUI.FromXmlName(ID_EDIT_TEXT);
  if FEdtText.Handle <> 0 then
    FEdtText.RegEvent(XE_EDIT_CHANGED, @TQrCodeDialogUI.OnEditTextChanged);

  FEdtPath := TEditUI.FromXmlName(ID_EDIT_PATH);
  if Succeeded(SHGetFolderPathW(0, CSIDL_DESKTOP, 0, 0, desktopPath)) then
    FEdtPath.Text := desktopPath + '\二维码';

  InitSliderBar;

  FLabelRadiusValue := XC_GetObjectByName(ID_TXT_RADIUS_VALUE);
  UpdateRadiusLabel;

  InitPreviewArea;

  FComboLevel := TComboBoxUI.FromXmlName(ID_COMBO_LEVEL);
  FComboLevel.InitTextItems(['L 低(7%)', 'M 中(15%)', 'Q 较高(25%)', 'H 高(30%)'], 1);
  FComboLevel.RegEvent(XE_COMBOBOX_SELECT, @TQrCodeDialogUI.OnComboLevelChanged);

  FComboFormat := TComboBoxUI.FromXmlName(ID_COMBO_FORMAT);
  FComboFormat.InitTextItems(['PNG', 'JPG', 'BMP'], 0);

  hTitle := XC_GetObjectByName(ID_TXT_DIALOG_TITLE);
  XShapeText_SetTextColor(hTitle, UITheme_TextPrimary);

  hLabelText := XC_GetObjectByName(ID_TXT_LABEL_TEXT);
  XShapeText_SetTextColor(hLabelText, UITheme_TextPrimary);

  hLabelRadius := XC_GetObjectByName(ID_TXT_LABEL_RADIUS);
  XShapeText_SetTextColor(hLabelRadius, UITheme_TextPrimary);

  if FLabelRadiusValue <> 0 then
    XShapeText_SetTextColor(FLabelRadiusValue, UITheme_TextPrimary);

  hLabelPath := XC_GetObjectByName(ID_TXT_LABEL_PATH);
  XShapeText_SetTextColor(hLabelPath, UITheme_TextPrimary);

  hLabelLevel := XC_GetObjectByName(ID_TXT_LABEL_LEVEL);
  XShapeText_SetTextColor(hLabelLevel, UITheme_TextPrimary);

  hLabelBgColor := XC_GetObjectByName(ID_TXT_LABEL_BG_COLOR);
  XShapeText_SetTextColor(hLabelBgColor, UITheme_TextPrimary);

  hLabelFgColor := XC_GetObjectByName(ID_TXT_LABEL_FG_COLOR);
  XShapeText_SetTextColor(hLabelFgColor, UITheme_TextPrimary);

  if XC_SHAPE_TEXT = XC_GetObjectType(XC_GetObjectByName(ID_TXT_LABEL_FORMAT)) then
    XShapeText_SetTextColor(XC_GetObjectByName(ID_TXT_LABEL_FORMAT), UITheme_TextPrimary);

  btnHint := TButtonUI.FromXmlName(ID_BTN_HINT, BB_NONE, 'Resource\hint.svg');
  if XC_BUTTON = XC_GetObjectType(btnHint.Handle) then
    THintPopupUI.BindHoverHint(btnHint.Handle, '把透明度(A)设置为0 可以不显示背景');

  btnLiquify := TButtonUI.FromXmlName(ID_BTN_LIQUIFY, BB_EnableCheckStyle, '');
  if XC_BUTTON = XC_GetObjectType(btnLiquify.Handle) then
    btnLiquify.RegEvent(XE_BUTTON_CHECK, @TQrCodeDialogUI.OnBtnLiquify);

  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TQrCodeDialogUI.OnWndKeyDown);

  DoGenerateQRCode;
end;

class function TQrCodeDialogUI.OnBtnCancel(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDCANCEL);
end;

class function TQrCodeDialogUI.OnBtnBrowse(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
var
  folderPath: string;
begin
  Result := 0;
  pbHandled^ := True;
  if FEdtPath = nil then
    Exit;

  if BrowseForFolderPath('选择保存文件夹', XWidget_GetHWINDOW(hEle), folderPath) then
    FEdtPath.Text := folderPath;
end;

class function TQrCodeDialogUI.OnBtnSave(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  DoSaveQRCode(XWidget_GetHWINDOW(hEle));
end;

class procedure TQrCodeDialogUI.RedrawPreview;
begin
  if FPreviewEle <> 0 then
    XEle_Redraw(FPreviewEle);
end;

class procedure TQrCodeDialogUI.DoGenerateQRCode(ForceECIndex: Integer = -1);
var
  pText: PWideChar;
  qrText: WideString;
  ecIndex: Integer;
const
  ECBits: array[0..3] of Integer = (1, 0, 3, 2); // L=1, M=0, Q=3, H=2
begin
  try
    if FEdtText = nil then
      Exit;

    pText := XEdit_GetText_Temp(FEdtText.Handle);
    if pText = nil then
      Exit;

    qrText := pText;

    if qrText = '' then
    begin
      if FQRCode <> nil then
      begin
        FQRCode.Free;
        FQRCode := nil;
      end;
    end
    else
    begin
      if FQRCode = nil then
        FQRCode := TDelphiZXingQRCode.Create;
      FQRCode.QuietZone := 0;
      FQRCode.Data := qrText;
      if FComboLevel <> nil then
      begin
        if ForceECIndex >= 0 then
          ecIndex := ForceECIndex
        else
          ecIndex := XComboBox_GetSelItem(FComboLevel.Handle);
        if (ecIndex >= 0) and (ecIndex <= 3) then
          FQRCode.ErrorCorrectionLevel := ECBits[ecIndex];
      end;
    end;

    if FSliderRadius <> 0 then
      FQRModuleRadius := XSliderBar_GetPos(FSliderRadius)
    else
      FQRModuleRadius := 0;
  finally
    RedrawPreview;
  end;
end;

class function TQrCodeDialogUI.OnComboLevelChanged(hEle: HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  DoGenerateQRCode(iItem);
end;

class function TQrCodeDialogUI.OnEditTextChanged(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  DoGenerateQRCode;
end;

class function TQrCodeDialogUI.OnSliderChange(hEle: HELE; nPos: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;

  if FLabelRadiusValue = 0 then
    Exit;

  XShapeText_SetText(FLabelRadiusValue, PWideChar(IntToStr(nPos)));
  XShape_Redraw(FLabelRadiusValue);

  FQRModuleRadius := nPos;
  RedrawPreview;
end;

class function TQrCodeDialogUI.OnSliderPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;

  XEle_GetClientRect(hEle, rc);
  // 轨道：1px 高的水平线，居中
  rc.Top := rc.Top + (rc.Bottom - rc.Top) div 2;
  rc.Bottom := rc.Top + 1;
  XDraw_SetBrushColor(hDraw, UITheme_BorderDefault);
  XDraw_FillRect(hDraw, rc);
end;

class function TQrCodeDialogUI.OnSliderBtnPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;

  XEle_GetClientRect(hEle, rc);
  XDraw_SetBrushColor(hDraw, UITheme_PrimaryColor);
  XDraw_FillEllipse(hDraw, rc);
end;

class function TQrCodeDialogUI.OnPreviewPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  qr: TDelphiZXingQRCode;
  layout: TQrPaintLayout;
  fgColor: Integer;
begin
  Result := 0;
  pbHandled^ := True;

  XEle_GetClientRect(hEle, rc);
  qr := FQRCode;

  if QrShouldPaintBackground(qr, FBgA) then
    DrawRoundedElement(hDraw, rc, 4, True, RGBA(FBgR, FBgG, FBgB, FBgA), True, UITheme_BorderDefault)
  else
    DrawRoundedElement(hDraw, rc, 4, False, 0, True, UITheme_BorderDefault);

  if not QrHasMatrix(qr) then
    Exit;

  if not QrCalcPaintLayout(qr, rc, layout) then
    Exit;

  fgColor := RGBA(FFgR, FFgG, FFgB, FFgA);
  QrPaintMatrixXDraw(hDraw, qr, layout, fgColor, FLiquify, FQRModuleRadius);
end;

class function TQrCodeDialogUI.OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if wParam = VK_RETURN then
  begin
    pbHandled^ := True;
    if (lParam and $40000000) = 0 then
      DoSaveQRCode(hWindow);
  end
  else if wParam = VK_ESCAPE then
  begin
    pbHandled^ := True;
    XModalWnd_EndModal(hWindow, IDCANCEL);
  end;
end;

class function TQrCodeDialogUI.OnBtnLiquify(hEle: HELE; bCheck: BOOL; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  FLiquify := bCheck;
  RedrawPreview;
end;

class function TQrCodeDialogUI.OnBtnBgColor(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
var
  r, g, b: Integer;
  a: Byte;
begin
  Result := 0;
  pbHandled^ := True;
  r := FBgR; g := FBgG; b := FBgB; a := FBgA;
  if TColorPickerDialogUI.PickColor(XWidget_GetHWINDOW(hEle), 0, r, g, b, a) then
  begin
    FBgR := r; FBgG := g; FBgB := b; FBgA := a;
    RedrawPreview;
    XEle_Redraw(XC_GetObjectByName(ID_BTN_BG_COLOR));
  end;
end;

class function TQrCodeDialogUI.OnBtnFgColor(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
var
  r, g, b: Integer;
  a: Byte;
begin
  Result := 0;
  pbHandled^ := True;
  r := FFgR; g := FFgG; b := FFgB; a := FFgA;
  if TColorPickerDialogUI.PickColor(XWidget_GetHWINDOW(hEle), 0, r, g, b, a) then
  begin
    FFgR := r; FFgG := g; FFgB := b; FFgA := a;
    RedrawPreview;
    XEle_Redraw(XC_GetObjectByName(ID_BTN_FG_COLOR));
  end;
end;

class function TQrCodeDialogUI.OnBtnFgColorPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  rr: Integer;
begin
  Result := 0;
  pbHandled^ := True;

  XEle_GetClientRect(hEle, rc);
  rr := 4;

  // 填充当前前景色（圆角）
  XDraw_SetBrushColor(hDraw, RGBA(FFgR, FFgG, FFgB, FFgA));
  XDraw_FillRoundRect(hDraw, rc, rr, rr);

  // 绘制边框（与编辑框失去焦点时同色）
  XDraw_SetBrushColor(hDraw, UITheme_InputBorder);
  XDraw_SetLineWidth(hDraw, 1);
  XDraw_DrawRoundRect(hDraw, rc, rr, rr);
end;

class function TQrCodeDialogUI.OnBtnBgColorPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  rr: Integer;
begin
  Result := 0;
  pbHandled^ := True;

  XEle_GetClientRect(hEle, rc);
  rr := 4;

  // 填充当前背景色（圆角）
  XDraw_SetBrushColor(hDraw, RGBA(FBgR, FBgG, FBgB, FBgA));
  XDraw_FillRoundRect(hDraw, rc, rr, rr);

  // 绘制边框（与编辑框失去焦点时同色）
  XDraw_SetBrushColor(hDraw, UITheme_InputBorder);
  XDraw_SetLineWidth(hDraw, 1);
  XDraw_DrawRoundRect(hDraw, rc, rr, rr);
end;

function SanitizeQrFileName(const AText: string): string;
const
  InvalidChars = '\/:*?"<>|';
var
  i: Integer;
  ch: WideChar;
begin
  Result := '';
  for i := 1 to Length(AText) do
  begin
    ch := AText[i];
    if (Pos(ch, InvalidChars) > 0) or (Ord(ch) < 32) then
      Result := Result + '_'
    else
      Result := Result + ch;
    if Length(Result) >= 40 then
      Break;
  end;
  Result := Trim(Result);
  if Result = '' then
    Result := 'QRCode';
end;

function FormatExtByIndex(AFormatIndex: Integer): string;
begin
  case AFormatIndex of
    1: Result := 'jpg';
    2: Result := 'bmp';
  else
    Result := 'png';
  end;
end;

function UniqueFilePath(const AFolder, ABaseName, AExt: string): string;
var
  candidate: string;
  seq: Integer;
begin
  candidate := IncludeTrailingPathDelimiter(AFolder) + ABaseName + '.' + AExt;
  if not FileExists(candidate) then
    Exit(candidate);
  seq := 1;
  repeat
    candidate := IncludeTrailingPathDelimiter(AFolder) + ABaseName + Format('(%d)', [seq]) + '.' + AExt;
    Inc(seq);
  until (not FileExists(candidate)) or (seq > 9999);
  Result := candidate;
end;

class function TQrCodeDialogUI.RenderQRCodeToFile(const AFilePath, AExt: string): Boolean;
begin
  Result := QrRenderToFile(FQRCode, AFilePath, AExt,
    FBgR, FBgG, FBgB, FBgA, FFgR, FFgG, FFgB, FFgA, FLiquify, FQRModuleRadius);
end;

class function TQrCodeDialogUI.DoSaveQRCode(hOwnerWnd: Windows.HWND): Boolean;
var
  qrText, saveFolder, baseName, ext, savePath: string;
  pText: PWideChar;
  formatIndex: Integer;
begin
  Result := False;
  DoGenerateQRCode;

  if (FQRCode = nil) or (FQRCode.Rows <= 0) then
  begin
    TMessageBoxUI.Confirm('保存失败', '请先输入要生成二维码的文本内容。', hOwnerWnd);
    Exit;
  end;

  if FEdtPath = nil then
    Exit;

  saveFolder := Trim(FEdtPath.Text);
  if saveFolder = '' then
  begin
    TMessageBoxUI.Confirm('保存失败', '请先选择保存路径。', hOwnerWnd);
    Exit;
  end;

  qrText := '';
  if FEdtText <> nil then
  begin
    pText := XEdit_GetText_Temp(FEdtText.Handle);
    if pText <> nil then
      qrText := pText;
  end;

  formatIndex := 0;
  if FComboFormat <> nil then
    formatIndex := XComboBox_GetSelItem(FComboFormat.Handle);
  ext := FormatExtByIndex(formatIndex);
  if (FBgA = 0) and (SameText(ext, 'jpg') or SameText(ext, 'jpeg')) then
  begin
    TMessageBoxUI.Confirm('保存提示', '背景透明度为 0 时 JPG 会铺白底，建议使用 PNG 格式。', hOwnerWnd);
    ext := 'png';
  end;
  baseName := SanitizeQrFileName(qrText);

  if not ForceDirectories(saveFolder) then
  begin
    TMessageBoxUI.Confirm('保存失败', '无法创建保存目录：' + saveFolder, hOwnerWnd);
    Exit;
  end;

  savePath := UniqueFilePath(saveFolder, baseName, ext);
  if not RenderQRCodeToFile(savePath, ext) then
  begin
    TMessageBoxUI.Confirm('保存失败', '写入文件失败：' + savePath, hOwnerWnd);
    Exit;
  end;

  ShellOpenFolderAndSelectPath(hOwnerWnd, savePath);
  Result := True;
end;

class procedure TQrCodeDialogUI.ShowDialog(const hParent: HWND = 0; hAttachWnd: Integer = 0);
var
  dlg: TQrCodeDialogUI;
begin
  // 重置二维码数据，每次打开都是空白状态
  if FQRCode <> nil then
  begin
    FQRCode.Free;
    FQRCode := nil;
  end;
  FQRModuleRadius := 0;
  FBgR := 255; FBgG := 255; FBgB := 255; FBgA := 255;
  FFgR := 0;   FFgG := 0;   FFgB := 0;   FFgA := 255;
  FLiquify := False;

  dlg := TQrCodeDialogUI.LoadLayout('Resource\Layout\QrCodeDialog.xml', hParent, hAttachWnd);
  if dlg = nil then
    Exit;

  XModalWnd_DoModal(dlg.Handle);

  if FQRCode <> nil then
  begin
    FQRCode.Free;
    FQRCode := nil;
  end;
end;

end.
