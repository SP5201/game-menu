unit UI_QrCodeDialog;

interface

uses
  Windows, Messages, SysUtils, Classes, Math, ShlObj, XCGUI, UI_Form, UI_Button,
  UI_Edit, UI_Theme, UI_Ele, UI_ComboBox, DelphiZXingQRCode, UI_ColorPickerDialog, UI_HintPopup;

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
    class function OnBtnGenerate(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnEditTextChanged(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnComboLevelChanged(hEle: HELE; iItem: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class procedure DoGenerateQRCode(ForceECIndex: Integer = -1); static;
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
    class function ShowDialog(const hParent: HWND = 0; hAttachWnd: Integer = 0): Boolean;
  end;

implementation

const
  ID_BTN_DIALOG_CLOSE = 'btn_qrcode_close';
  ID_BTN_CANCEL       = 'btn_qrcode_cancel';
  ID_BTN_GENERATE     = 'btn_qrcode_generate';
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
  desktopPath: array[0..MAX_PATH] of WideChar;
begin
  inherited;

  // 关闭按钮
  TButtonUI.FromXmlName(ID_BTN_DIALOG_CLOSE, BB_NONE, 'Resource\close.svg').RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnCancel);

  // 取消按钮
  TButtonUI.FromXmlName(ID_BTN_CANCEL, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnCancel);

  // 浏览按钮（样式同取消按钮）
  TButtonUI.FromXmlName(ID_BTN_BROWSE, BB_EnableBorder , '');

  // 生成按钮
  TButtonUI.FromXmlName(ID_BTN_GENERATE, BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnGenerate);

  // 背景颜色设置按钮
  TButtonUI.FromXmlName(ID_BTN_BG_COLOR, BB_EnableBorder, '').RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnBgColor);
  XEle_RegEvent(XC_GetObjectByName(ID_BTN_BG_COLOR), XE_PAINT, @TQrCodeDialogUI.OnBtnBgColorPaint);

  // 前景颜色设置按钮
  TButtonUI.FromXmlName(ID_BTN_FG_COLOR, BB_EnableBorder, '').RegEvent(XE_BNCLICK, @TQrCodeDialogUI.OnBtnFgColor);
  XEle_RegEvent(XC_GetObjectByName(ID_BTN_FG_COLOR), XE_PAINT, @TQrCodeDialogUI.OnBtnFgColorPaint);

  // 编辑框
  FEdtText := TEditUI.FromXmlName(ID_EDIT_TEXT);
  FEdtText.RegEvent(XE_EDIT_CHANGED, @TQrCodeDialogUI.OnEditTextChanged);

  // 保存路径编辑框，默认桌面\二维码
  FEdtPath := TEditUI.FromXmlName(ID_EDIT_PATH);
  if Succeeded(SHGetFolderPathW(0, CSIDL_DESKTOP, 0, 0, desktopPath)) then
    FEdtPath.Text := desktopPath + '\二维码';

  // 滑动条
  InitSliderBar;

  // 圆角数值标签
  FLabelRadiusValue := XC_GetObjectByName(ID_TXT_RADIUS_VALUE);
  UpdateRadiusLabel;

  // 二维码预览区域
  InitPreviewArea;

  // 纠错率
  FComboLevel := TComboBoxUI.FromXmlName(ID_COMBO_LEVEL);
  FComboLevel.InitTextItems(['L 低(7%)', 'M 中(15%)', 'Q 较高(25%)', 'H 高(30%)'], 1);
  FComboLevel.RegEvent(XE_COMBOBOX_SELECT, @TQrCodeDialogUI.OnComboLevelChanged);

  // 保存格式
  FComboFormat := TComboBoxUI.FromXmlName(ID_COMBO_FORMAT);
  FComboFormat.InitTextItems(['PNG', 'JPG', 'BMP'], 0);

  // 设置文本颜色
  hTitle := XC_GetObjectByName(ID_TXT_DIALOG_TITLE);
  XShapeText_SetTextColor(hTitle, UITheme_TextPrimary);

  hLabelText := XC_GetObjectByName(ID_TXT_LABEL_TEXT);
  XShapeText_SetTextColor(hLabelText, UITheme_TextPrimary);

  hLabelRadius := XC_GetObjectByName(ID_TXT_LABEL_RADIUS);
  XShapeText_SetTextColor(hLabelRadius, UITheme_TextPrimary);

  XShapeText_SetTextColor(FLabelRadiusValue, UITheme_TextPrimary);

  hLabelPath := XC_GetObjectByName(ID_TXT_LABEL_PATH);
  XShapeText_SetTextColor(hLabelPath, UITheme_TextPrimary);

  hLabelLevel := XC_GetObjectByName(ID_TXT_LABEL_LEVEL);
  XShapeText_SetTextColor(hLabelLevel, UITheme_TextPrimary);

  XShapeText_SetTextColor(XC_GetObjectByName(ID_TXT_LABEL_FORMAT), UITheme_TextPrimary);
  THintPopupUI.BindHoverHint(TButtonUI.FromXmlName(ID_BTN_HINT, BB_NONE, 'Resource\hint.svg').Handle, '把透明度(A)设置为0 可以不显示背景');
  TButtonUI.FromXmlName(ID_BTN_LIQUIFY, BB_EnableCheckStyle, '').RegEvent(XE_BUTTON_CHECK, @TQrCodeDialogUI.OnBtnLiquify);

  hLabelBgColor := XC_GetObjectByName(ID_TXT_LABEL_BG_COLOR);
  XShapeText_SetTextColor(hLabelBgColor, UITheme_TextPrimary);

  hLabelFgColor := XC_GetObjectByName(ID_TXT_LABEL_FG_COLOR);
  XShapeText_SetTextColor(hLabelFgColor, UITheme_TextPrimary);

  // 注册窗口按键事件
  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TQrCodeDialogUI.OnWndKeyDown);

  // 默认生成一个二维码
  DoGenerateQRCode;
end;

class function TQrCodeDialogUI.OnBtnCancel(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDCANCEL);
end;

class procedure TQrCodeDialogUI.DoGenerateQRCode(ForceECIndex: Integer = -1);
var
  pText: PWideChar;
  qrText: WideString;
  ecIndex: Integer;
const
  ECBits: array[0..3] of Integer = (1, 0, 3, 2); // L=1, M=0, Q=3, H=2
begin
  if FEdtText = nil then
    Exit;

  pText := XEdit_GetText_Temp(FEdtText.Handle);
  if pText = nil then
    Exit;

  qrText := pText;

  if FQRCode <> nil then
  begin
    FQRCode.Free;
    FQRCode := nil;
  end;

  if qrText <> '' then
  begin
    FQRCode := TDelphiZXingQRCode.Create;
    FQRCode.Data := qrText;
    FQRCode.QuietZone := 0;
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

  XEle_Redraw(FPreviewEle);
end;

class function TQrCodeDialogUI.OnBtnGenerate(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  DoGenerateQRCode;
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
  if FPreviewEle <> 0 then
    XEle_Redraw(FPreviewEle);
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
  qrSize, moduleSize, offsetX, offsetY: Integer;
  r, c, qz, innerSize, startC: Integer;
  qr: TDelphiZXingQRCode;
  qrRect: TRect;

  function IsInFinderPattern(row, col: Integer): Boolean;
  begin
    Result := ((row >= qz) and (row < qz + 7) and (col >= qz) and (col < qz + 7)) or
              ((row >= qz) and (row < qz + 7) and (col >= qz + innerSize - 7) and (col < qz + innerSize)) or
              ((row >= qz + innerSize - 7) and (row < qz + innerSize) and (col >= qz) and (col < qz + 7));
  end;

  procedure DrawFinderPattern(px, py, ms, radius: Integer);
  var
    rcOuter, rcInner: TRect;
    rrOuter, rrInner: Integer;
    halfMs: Integer;
  begin
    halfMs := ms div 2;

    // 外层 7x7 圆角边框（黑色圆环，1模块厚）
    // 内缩 halfMs 使描边外缘对齐 7x7 边界
    rcOuter := Rect(px + halfMs, py + halfMs, px + ms * 7 - halfMs, py + ms * 7 - halfMs);
    rrOuter := Min(radius, (ms * 7 - ms) div 2);
    XDraw_SetBrushColor(hDraw, RGBA(FFgR, FFgG, FFgB, FFgA));
    XDraw_SetLineWidth(hDraw, ms);
    XDraw_DrawRoundRect(hDraw, rcOuter, rrOuter, rrOuter);

    // 内层 3x3 圆角填充（实心黑色）
    rcInner := Rect(px + ms * 2, py + ms * 2, px + ms * 5, py + ms * 5);
    rrInner := Min(radius, ms * 3 div 2);
    XDraw_SetBrushColor(hDraw, RGBA(FFgR, FFgG, FFgB, FFgA));
    XDraw_FillRoundRect(hDraw, rcInner, rrInner, rrInner);
  end;

begin
  Result := 0;
  pbHandled^ := True;

  XEle_GetClientRect(hEle, rc);

  // 绘制圆角背景和边框
  DrawRoundedElement(hDraw, rc, 4, True, RGBA(FBgR, FBgG, FBgB, FBgA), True, UITheme_BorderDefault);

  qr := FQRCode;
  if qr = nil then
    Exit;

  qrSize := qr.Rows;
  if qrSize <= 0 then
    Exit;

  qz := qr.QuietZone;
  innerSize := qrSize - qz * 2;

  moduleSize := (rc.Right - rc.Left) div qrSize;
  if (rc.Bottom - rc.Top) div qrSize < moduleSize then
    moduleSize := (rc.Bottom - rc.Top) div qrSize;
  if moduleSize <= 0 then
    Exit;

  offsetX := rc.Left + ((rc.Right - rc.Left) - moduleSize * qrSize) div 2;
  offsetY := rc.Top + ((rc.Bottom - rc.Top) - moduleSize * qrSize) div 2;

  // 绘制普通模块（跳过定位图案区域）
  XDraw_SetBrushColor(hDraw, RGBA(FFgR, FFgG, FFgB, FFgA));
  if FLiquify then
  begin
    for r := 0 to qrSize - 1 do
      for c := 0 to qrSize - 1 do
        if qr.IsBlack[r, c] and (not IsInFinderPattern(r, c)) then
        begin
          // 绘制圆形模块
          qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize,
                         offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize);
          XDraw_FillEllipse(hDraw, qrRect);
          // 水平连接：与右邻模块之间填充矩形
          if (c + 1 < qrSize) and qr.IsBlack[r, c + 1] and (not IsInFinderPattern(r, c + 1)) then
          begin
            qrRect := Rect(offsetX + c * moduleSize + moduleSize div 2, offsetY + r * moduleSize,
                           offsetX + (c + 1) * moduleSize + moduleSize div 2, offsetY + (r + 1) * moduleSize);
            XDraw_FillRect(hDraw, qrRect);
          end;
          // 垂直连接：与下邻模块之间填充矩形
          if (r + 1 < qrSize) and qr.IsBlack[r + 1, c] and (not IsInFinderPattern(r + 1, c)) then
          begin
            qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize + moduleSize div 2,
                           offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize + moduleSize div 2);
            XDraw_FillRect(hDraw, qrRect);
          end;
        end;
  end
  else
  begin
    for r := 0 to qrSize - 1 do
    begin
      c := 0;
      while c < qrSize do
      begin
        if qr.IsBlack[r, c] and (not IsInFinderPattern(r, c)) then
        begin
          startC := c;
          while (c < qrSize) and qr.IsBlack[r, c] and (not IsInFinderPattern(r, c)) do
            Inc(c);
          qrRect := Rect(offsetX + startC * moduleSize, offsetY + r * moduleSize,
                         offsetX + c * moduleSize, offsetY + (r + 1) * moduleSize);
          XDraw_FillRect(hDraw, qrRect);
        end
        else
          Inc(c);
      end;
    end;
  end;

  // 绘制3个定位图案（圆角）
  if FQRModuleRadius > 0 then
  begin
    DrawFinderPattern(offsetX + qz * moduleSize, offsetY + qz * moduleSize, moduleSize, FQRModuleRadius);
    DrawFinderPattern(offsetX + (qz + innerSize - 7) * moduleSize, offsetY + qz * moduleSize, moduleSize, FQRModuleRadius);
    DrawFinderPattern(offsetX + qz * moduleSize, offsetY + (qz + innerSize - 7) * moduleSize, moduleSize, FQRModuleRadius);
  end
  else
  begin
    XDraw_SetBrushColor(hDraw, RGBA(FFgR, FFgG, FFgB, FFgA));
    for r := 0 to qrSize - 1 do
      for c := 0 to qrSize - 1 do
        if qr.IsBlack[r, c] and IsInFinderPattern(r, c) then
        begin
          qrRect := Rect(offsetX + c * moduleSize, offsetY + r * moduleSize,
                         offsetX + (c + 1) * moduleSize, offsetY + (r + 1) * moduleSize);
          XDraw_FillRect(hDraw, qrRect);
        end;
  end;
end;

class function TQrCodeDialogUI.OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if wParam = VK_RETURN then
  begin
    pbHandled^ := True;
    if (lParam and $40000000) = 0 then
      XModalWnd_EndModal(hWindow, IDOK);
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
  if FPreviewEle <> 0 then
    XEle_Redraw(FPreviewEle);
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
    XEle_Redraw(FPreviewEle);
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
    XEle_Redraw(FPreviewEle);
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

class function TQrCodeDialogUI.ShowDialog(const hParent: HWND = 0; hAttachWnd: Integer = 0): Boolean;
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
    Exit(False);

  Result := XModalWnd_DoModal(dlg.Handle) = IDOK;

  if FQRCode <> nil then
  begin
    FQRCode.Free;
    FQRCode := nil;
  end;
end;

end.
