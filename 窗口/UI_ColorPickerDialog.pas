unit UI_ColorPickerDialog;

interface

uses
  Windows, Messages, SysUtils, Classes, Math, XCGUI, UI_Form, UI_Button, UI_Edit,
  UI_Ele, UI_Theme;
                                                                                                              
type
  TColorPickerDialogUI = class(TFormUI)
  private
    FEdtR: TEditUI;
    FEdtG: TEditUI;                                                                                     
    FEdtB: TEditUI;
    FEdtA: TEditUI;
    FEdtHex: TEditUI;
    class var
      FPreviewEle: HELE;
      FEdtRHandle: HELE;
      FEdtGHandle: HELE;
      FEdtBHandle: HELE;
      FEdtAHandle: HELE;
      FEdtHexHandle: HELE;
      FHue: Double;
      FSat: Double;
      FVal: Double;
      FAlpha: Double;
      FDragging: Boolean;
      FUpdating: Boolean;
      FHueBarImage: HIMAGE;
      FAlphaBarImage: HIMAGE;
      FAlphaBarColor: Integer;
      FCurrentR: Integer;
      FCurrentG: Integer;
      FCurrentB: Integer;
    class function OnBtnCancel(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnOK(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnColorPanelPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnHueBarPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnPreviewPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnColorPanelLButtonDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnHueBarLButtonDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnColorPanelMouseMove(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnHueBarMouseMove(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnColorPanelLButtonUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnHueBarLButtonUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnAlphaBarPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnAlphaBarLButtonDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnAlphaBarMouseMove(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnAlphaBarLButtonUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnEditChanged(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnScreenColorPicker(hEle: HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class procedure UpdateEdits;
    class procedure CreateHueBarImage(w, h: Integer);
    class procedure CreateAlphaBarImage(w, h: Integer);
    class procedure DestroyCachedImages;
  protected
    procedure Init; override;                                                                      
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: Integer = 0): TColorPickerDialogUI; reintroduce;
    class function PickColor(const hParent: HWND; hAttachWnd: Integer; var ARed, AGreen, ABlue: Integer; var AAlpha: Byte): Boolean;
  end;

implementation

function HueToRGBA(const Hue: Double): Integer; forward;
function HSVtoRGB(const H, S, V: Double): Integer; forward;
procedure RGBtoHSV(const R, G, B: Integer; out H, S, V: Double); forward;

type
  TBGRA = packed record
    B, G, R, A: Byte;
  end;
  PBGRA = ^TBGRA;

const
  ID_BTN_DIALOG_CLOSE = 'btn_colorpicker_close';
  ID_BTN_CANCEL       = 'btn_colorpicker_cancel';
  ID_BTN_OK           = 'btn_colorpicker_ok';
  ID_EDIT_R           = 'edit_colorpicker_r';
  ID_EDIT_G           = 'edit_colorpicker_g';
  ID_EDIT_B           = 'edit_colorpicker_b';
  ID_ELE_PREVIEW      = 'ele_colorpicker_preview';
  ID_TXT_TITLE        = 'txt_colorpicker_title';
  ID_ELE_COLOR_PANEL  = 'ele_color_panel';
  ID_ELE_HUE_BAR      = 'ele_hue_bar';
  ID_ELE_ALPHA_BAR    = 'ele_alpha_bar';
  ID_EDIT_A           = 'edit_colorpicker_a';
  ID_EDIT_HEX         = 'edit_colorpicker_hex';
  ID_BTN_SCREEN       = 'btn_colorpicker_screen';

class function TColorPickerDialogUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI; hAttachWnd: Integer): TColorPickerDialogUI;
var
  h: HXCGUI;
begin
  h := XC_LoadLayout(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := FromHandle(h);
end;

procedure TColorPickerDialogUI.Init;
begin
  inherited;

  // 关闭按钮
  TButtonUI.FromXmlName(ID_BTN_DIALOG_CLOSE, BB_NONE, 'Resource\close.svg').RegEvent(XE_BNCLICK, @TColorPickerDialogUI.OnBtnCancel);

  // 取消按钮
  TButtonUI.FromXmlName(ID_BTN_CANCEL, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TColorPickerDialogUI.OnBtnCancel);

  // 确定按钮
  TButtonUI.FromXmlName(ID_BTN_OK, BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TColorPickerDialogUI.OnBtnOK);

  // RGBA编辑框
  FEdtR := TEditUI.FromXmlName(ID_EDIT_R);
  FEdtG := TEditUI.FromXmlName(ID_EDIT_G);
  FEdtB := TEditUI.FromXmlName(ID_EDIT_B);
  FEdtA := TEditUI.FromXmlName(ID_EDIT_A);
  FEdtHex := TEditUI.FromXmlName(ID_EDIT_HEX);

  // 缓存编辑框句柄（供 static 回调使用）
  FEdtRHandle := FEdtR.Handle;
  FEdtGHandle := FEdtG.Handle;
  FEdtBHandle := FEdtB.Handle;
  FEdtAHandle := FEdtA.Handle;
  FEdtHexHandle := FEdtHex.Handle;

  // 预览颜色区域
  FPreviewEle := XC_GetObjectByName(ID_ELE_PREVIEW);

  // 标题文本颜色
  XShapeText_SetTextColor(XC_GetObjectByName(ID_TXT_TITLE), UITheme_TextPrimary);

  // 颜色面板
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_COLOR_PANEL), XE_PAINT, @TColorPickerDialogUI.OnColorPanelPaint);

  // 色相条
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_HUE_BAR), XE_PAINT, @TColorPickerDialogUI.OnHueBarPaint);

  // 预览区域
  XEle_RegEvent(FPreviewEle, XE_PAINT, @TColorPickerDialogUI.OnPreviewPaint);

  // 颜色面板点击/移动/弹起
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_COLOR_PANEL), XE_LBUTTONDOWN, @TColorPickerDialogUI.OnColorPanelLButtonDown);
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_COLOR_PANEL), XE_MOUSEMOVE, @TColorPickerDialogUI.OnColorPanelMouseMove);
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_COLOR_PANEL), XE_LBUTTONUP, @TColorPickerDialogUI.OnColorPanelLButtonUp);

  // 色相条点击/移动/弹起
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_HUE_BAR), XE_LBUTTONDOWN, @TColorPickerDialogUI.OnHueBarLButtonDown);
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_HUE_BAR), XE_MOUSEMOVE, @TColorPickerDialogUI.OnHueBarMouseMove);
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_HUE_BAR), XE_LBUTTONUP, @TColorPickerDialogUI.OnHueBarLButtonUp);

  // Alpha条绘制和交互
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_ALPHA_BAR), XE_PAINT, @TColorPickerDialogUI.OnAlphaBarPaint);
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_ALPHA_BAR), XE_LBUTTONDOWN, @TColorPickerDialogUI.OnAlphaBarLButtonDown);
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_ALPHA_BAR), XE_MOUSEMOVE, @TColorPickerDialogUI.OnAlphaBarMouseMove);
  XEle_RegEvent(XC_GetObjectByName(ID_ELE_ALPHA_BAR), XE_LBUTTONUP, @TColorPickerDialogUI.OnAlphaBarLButtonUp);

  // 注册编辑框内容改变事件
  XEle_RegEvent(FEdtRHandle, XE_EDIT_CHANGED, @TColorPickerDialogUI.OnEditChanged);
  XEle_RegEvent(FEdtGHandle, XE_EDIT_CHANGED, @TColorPickerDialogUI.OnEditChanged);
  XEle_RegEvent(FEdtBHandle, XE_EDIT_CHANGED, @TColorPickerDialogUI.OnEditChanged);
  XEle_RegEvent(FEdtAHandle, XE_EDIT_CHANGED, @TColorPickerDialogUI.OnEditChanged);
  XEle_RegEvent(FEdtHexHandle, XE_EDIT_CHANGED, @TColorPickerDialogUI.OnEditChanged);

  // 屏幕取色器按钮
  TButtonUI.FromXmlName(ID_BTN_SCREEN, BB_EnableNormalBk, 'Resource\colorPicker.svg', 18, 18).RegEvent(XE_BNCLICK, @TColorPickerDialogUI.OnBtnScreenColorPicker);

  // FHue/FSat/FVal 由 PickColor 在 LoadLayout 前设置
  FAlpha := 1;
  FUpdating := False;
  FHueBarImage := 0;
  FAlphaBarImage := 0;
  FAlphaBarColor := 0;
  FCurrentR := 255;
  FCurrentG := 255;
  FCurrentB := 255;
  UpdateEdits;

  // 注册窗口按键事件
  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TColorPickerDialogUI.OnWndKeyDown);
end;

class function TColorPickerDialogUI.OnBtnCancel(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDCANCEL);
end;

class function TColorPickerDialogUI.OnBtnOK(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  XModalWnd_EndModal(XWidget_GetHWINDOW(hEle), IDOK);
end;

class function TColorPickerDialogUI.OnWndKeyDown(hWindow: HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
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

class function TColorPickerDialogUI.OnColorPanelPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  y, h, leftColor, rightColor: Integer;
  v: Double;
  rowRect: TRect;
  baseHue: Integer;
  dotRectF: TRectF;
  fx, fy: Single;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  h := rc.Bottom - rc.Top;
  if h <= 0 then Exit;

  baseHue := HueToRGBA(FHue);

  for y := 0 to h - 1 do
  begin
    v := 1.0 - (y / h); // 明度: 顶部=1, 底部=0
    rowRect := Rect(rc.Left, rc.Top + y, rc.Right, rc.Top + y + 1);

    // 左侧: 白色按明度缩放 (S=0)
    leftColor := RGBA(Round(v * 255), Round(v * 255), Round(v * 255), 255);
    // 右侧: 当前色相按明度缩放 (S=1)
    rightColor := RGBA(Round(v * Byte(baseHue)), Round(v * Byte(baseHue shr 8)), Round(v * Byte(baseHue shr 16)), 255);

    XDraw_GradientFill2(hDraw, rowRect, leftColor, rightColor, 0);
  end;

  // 绘制取色指示器: 空心圆环 (黑-白-黑)
  fx := rc.Left + FSat * (rc.Right - rc.Left);
  fy := rc.Top + (1 - FVal) * h;
  // 外圈黑色描边
  dotRectF.Left := fx - 8; dotRectF.Top := fy - 8;
  dotRectF.Right := fx + 8; dotRectF.Bottom := fy + 8;
  XDraw_SetLineWidthF(hDraw, 1.0);
  XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, 100));
  XDraw_DrawEllipseF(hDraw, dotRectF);
  // 白色圆环
  dotRectF.Left := fx - 6.5; dotRectF.Top := fy - 6.5;
  dotRectF.Right := fx + 6.5; dotRectF.Bottom := fy + 6.5;
  XDraw_SetLineWidthF(hDraw, 2.0);
  XDraw_SetBrushColor(hDraw, RGBA(255, 255, 255, 255));
  XDraw_DrawEllipseF(hDraw, dotRectF);
  // 内圈黑色描边
  dotRectF.Left := fx - 5; dotRectF.Top := fy - 5;
  dotRectF.Right := fx + 5; dotRectF.Bottom := fy + 5;
  XDraw_SetLineWidthF(hDraw, 1.0);
  XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, 100));
  XDraw_DrawEllipseF(hDraw, dotRectF);
end;

function HSVtoRGB(const H, S, V: Double): Integer;
var
  C, X, m, r, g, b: Double;
  hh: Integer;
begin
  C := V * S;
  hh := Trunc(H / 60) mod 6;
  X := C * (1.0 - Abs(Frac(H / 120) * 2 - 1));
  m := V - C;

  case hh of
    0: begin r := C; g := X; b := 0; end;
    1: begin r := X; g := C; b := 0; end;
    2: begin r := 0; g := C; b := X; end;
    3: begin r := 0; g := X; b := C; end;
    4: begin r := X; g := 0; b := C; end;
    else begin r := C; g := 0; b := X; end;
  end;

  Result := RGBA(Round((r + m) * 255), Round((g + m) * 255), Round((b + m) * 255), 255);
end;

function HueToRGBA(const Hue: Double): Integer;
var
  hp, X: Double;
  hh: Integer;
  r, g, b: Double;
begin
  hp := Hue / 60.0;
  hh := Trunc(hp) mod 6;
  X := 1.0 - Abs(Frac(Hue / 120) * 2 - 1);

  case hh of
    0: begin r := 1; g := X; b := 0; end;
    1: begin r := X; g := 1; b := 0; end;
    2: begin r := 0; g := 1; b := X; end;
    3: begin r := 0; g := X; b := 1; end;
    4: begin r := X; g := 0; b := 1; end;
    else begin r := 1; g := 0; b := X; end;
  end;

  Result := RGBA(Round(r * 255), Round(g * 255), Round(b * 255), 255);
end;

procedure RGBtoHSV(const R, G, B: Integer; out H, S, V: Double);
var
  rr, gg, bb, cmax, cmin, delta: Double;
begin
  rr := R / 255.0;
  gg := G / 255.0;
  bb := B / 255.0;
  cmax := Max(rr, Max(gg, bb));
  cmin := Min(rr, Min(gg, bb));
  delta := cmax - cmin;

  V := cmax;

  if cmax = 0 then
    S := 0
  else
    S := delta / cmax;

  if delta = 0 then
    H := 0
  else if cmax = rr then
  begin
    H := (gg - bb) / delta;
    if H < 0 then H := H + 6;
    H := 60 * H;
  end
  else if cmax = gg then
    H := 60 * (((bb - rr) / delta) + 2)
  else
    H := 60 * (((rr - gg) / delta) + 4);
end;

class procedure TColorPickerDialogUI.UpdateEdits;
var
  rgb: Integer;
  r, g, b: Integer;
  hexStr: string;
begin
  if FUpdating then Exit;
  FUpdating := True;       
  try
    rgb := HSVtoRGB(FHue, FSat, FVal);
    r := Byte(rgb);
    g := Byte(rgb shr 8);                                                             
    b := Byte(rgb shr 16);
    
    // 同步存储的RGB值
    FCurrentR := r;
    FCurrentG := g;
    FCurrentB := b;

    XEdit_SetTextInt(FEdtRHandle, r);                                            
    XEle_Redraw(FEdtRHandle);
    XEdit_SetTextInt(FEdtGHandle, g);
    XEle_Redraw(FEdtGHandle);
    XEdit_SetTextInt(FEdtBHandle, b);
    XEle_Redraw(FEdtBHandle);
    XEdit_SetTextInt(FEdtAHandle, Round(FAlpha * 255));
    XEle_Redraw(FEdtAHandle);
    hexStr := Format('%.2x%.2x%.2x%.2x', [Round(FAlpha * 255), r, g, b]);
    XEdit_SetText(FEdtHexHandle, PWideChar(hexStr));
    XEle_Redraw(FEdtHexHandle);
  finally
    FUpdating := False;
  end;                                                                           
end;

class procedure TColorPickerDialogUI.CreateHueBarImage(w, h: Integer);
var
  data: PBGRA;
  x, y: Integer;
  hue: Double;
  rgba: Integer;
  pb: PBGRA;
  radius: Integer;
  cx, cy: Double;
  dist, aa: Double;
  a: Byte;
begin
  if XC_GetObjectType(FHueBarImage) = XC_IMAGE then
    XImage_Destroy(FHueBarImage);

  GetMem(data, w * h * SizeOf(TBGRA));
  try
    pb := data;
    for y := 0 to h - 1 do
    begin
      hue := y / Max(h - 1, 1) * 360;
      rgba := HueToRGBA(hue);
      for x := 0 to w - 1 do
      begin
        pb^.B := Byte(rgba shr 16);
        pb^.G := Byte(rgba shr 8);
        pb^.R := Byte(rgba);
        pb^.A := 255;
        Inc(pb);
      end;
    end;

    // 圆角抗锯齿裁切 (半宽半径，两侧呈圆弧)
    radius := Min((w + 1) div 2, h div 2);
    if radius > 0 then
    begin
      for y := 0 to h - 1 do
        for x := 0 to w - 1 do
        begin
          dist := -1;
          if (x < radius) and (y < radius) then
          begin
            cx := radius - 0.5; cy := radius - 0.5;
            dist := Sqrt(Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy));
          end
          else if (x >= w - radius) and (y < radius) then
          begin
            cx := w - radius + 0.5; cy := radius - 0.5;
            dist := Sqrt(Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy));
          end
          else if (x < radius) and (y >= h - radius) then
          begin
            cx := radius - 0.5; cy := h - radius + 0.5;
            dist := Sqrt(Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy));
          end
          else if (x >= w - radius) and (y >= h - radius) then
          begin
            cx := w - radius + 0.5; cy := h - radius + 0.5;
            dist := Sqrt(Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy));
          end;
          if dist >= 0 then
          begin
            aa := radius - dist + 0.5;
            if aa <= 0 then
              a := 0
            else if aa >= 1 then
              a := 255
            else
              a := Round(aa * 255);
            pb := data;
            Inc(pb, y * w + x);
            pb^.R := Round(pb^.R * a / 255);
            pb^.G := Round(pb^.G * a / 255);
            pb^.B := Round(pb^.B * a / 255);
            pb^.A := a;
          end;
        end;
    end;

    FHueBarImage := XImage_LoadFromData(Integer(data), w, h);
  finally
    FreeMem(data);
  end;
end;

class procedure TColorPickerDialogUI.CreateAlphaBarImage(w, h: Integer);
var
  data: PBGRA;
  x, y: Integer;
  pb: PBGRA;
  alpha: Double;
  rgb: Integer;
  r, g, b: Integer;
  checkerR, checkerG, checkerB: Integer;
  outR, outG, outB: Integer;
  radius: Integer;
  cx, cy: Double;
  dist, aa: Double;
  a: Byte;
begin
  if XC_GetObjectType(FAlphaBarImage) = XC_IMAGE then
    XImage_Destroy(FAlphaBarImage);

  rgb := HSVtoRGB(FHue, FSat, FVal);
  r := Byte(rgb);
  g := Byte(rgb shr 8);
  b := Byte(rgb shr 16);
  FAlphaBarColor := rgb;

  GetMem(data, w * h * SizeOf(TBGRA));
  try
    for y := 0 to h - 1 do
    begin
      alpha := y / Max(h - 1, 1);
      for x := 0 to w - 1 do
      begin
        // 棋盘格背景
        if ((x div 4) + (y div 4)) mod 2 = 0 then
        begin
          checkerR := 255; checkerG := 255; checkerB := 255;
        end
        else
        begin
          checkerR := 204; checkerG := 204; checkerB := 204;
        end;

        // 当前颜色与棋盘格混合
        outB := Round(b * alpha + checkerB * (1 - alpha));
        outG := Round(g * alpha + checkerG * (1 - alpha));
        outR := Round(r * alpha + checkerR * (1 - alpha));

        pb := data;
        Inc(pb, y * w + x);
        pb^.B := outB;
        pb^.G := outG;
        pb^.R := outR;
        pb^.A := 255;
      end;
    end;

    // 圆角抗锯齿裁切 (半宽半径，两侧呈圆弧)
    radius := Min((w + 1) div 2, h div 2);
    if radius > 0 then
    begin
      for y := 0 to h - 1 do
        for x := 0 to w - 1 do
        begin
          dist := -1;
          if (x < radius) and (y < radius) then
          begin
            cx := radius - 0.5; cy := radius - 0.5;
            dist := Sqrt(Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy));
          end
          else if (x >= w - radius) and (y < radius) then
          begin
            cx := w - radius + 0.5; cy := radius - 0.5;
            dist := Sqrt(Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy));
          end
          else if (x < radius) and (y >= h - radius) then
          begin
            cx := radius - 0.5; cy := h - radius + 0.5;
            dist := Sqrt(Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy));
          end
          else if (x >= w - radius) and (y >= h - radius) then
          begin
            cx := w - radius + 0.5; cy := h - radius + 0.5;
            dist := Sqrt(Sqr(x + 0.5 - cx) + Sqr(y + 0.5 - cy));
          end;
          if dist >= 0 then
          begin
            aa := radius - dist + 0.5;
            if aa <= 0 then
              a := 0
            else if aa >= 1 then
              a := 255
            else
              a := Round(aa * 255);
            pb := data;
            Inc(pb, y * w + x);
            pb^.R := Round(pb^.R * a / 255);
            pb^.G := Round(pb^.G * a / 255);
            pb^.B := Round(pb^.B * a / 255);
            pb^.A := a;
          end;
        end;
    end;

    FAlphaBarImage := XImage_LoadFromData(Integer(data), w, h);
  finally
    FreeMem(data);
  end;
end;

class procedure TColorPickerDialogUI.DestroyCachedImages;
begin
  if XC_GetObjectType(FHueBarImage) = XC_IMAGE then
  begin
    XImage_Destroy(FHueBarImage);
    FHueBarImage := 0;
  end;
  if XC_GetObjectType(FAlphaBarImage) = XC_IMAGE then
  begin
    XImage_Destroy(FAlphaBarImage);
    FAlphaBarImage := 0;
  end;
end;

class function TColorPickerDialogUI.OnHueBarPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  w, h: Integer;
  dotRect: TRectF;
  cx, cy, r: Single;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  w := rc.Right - rc.Left;
  h := rc.Bottom - rc.Top;
  if w <= 0 then w := 15;
  if h <= 0 then Exit;

  if XC_GetObjectType(FHueBarImage) <> XC_IMAGE then
    CreateHueBarImage(w, h);

  XDraw_ImageExF(hDraw, FHueBarImage, rc.Left, rc.Top, w, h);

  // 色相指示器: 空心圆环 (黑-白-黑)
  cx := rc.Left + w / 2.0;
  cy := rc.Top + FHue / 360 * h;
  // 外圈黑色描边
  r := (w / 2.0) +0.5;
  if cy < rc.Top + r then cy := rc.Top + r;
  if cy > rc.Top + h - r then cy := rc.Top + h - r;
  dotRect.Left := cx - r; dotRect.Top := cy - r;
  dotRect.Right := cx + r; dotRect.Bottom := cy + r;
  XDraw_SetLineWidthF(hDraw, 1.0);
  XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, 100));
  XDraw_DrawEllipseF(hDraw, dotRect);
  // 白色圆环
  r := r - 1.5;
  dotRect.Left := cx - r; dotRect.Top := cy - r;
  dotRect.Right := cx + r; dotRect.Bottom := cy + r;
  XDraw_SetLineWidthF(hDraw, 2.0);
  XDraw_SetBrushColor(hDraw, RGBA(255, 255, 255, 255));
  XDraw_DrawEllipseF(hDraw, dotRect);
  // 内圈黑色描边
  r := r - 1.5;
  dotRect.Left := cx - r; dotRect.Top := cy - r;
  dotRect.Right := cx + r; dotRect.Bottom := cy + r;
  XDraw_SetLineWidthF(hDraw, 1.0);
  XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, 100));
  XDraw_DrawEllipseF(hDraw, dotRect);
end;

class function TColorPickerDialogUI.OnAlphaBarPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  w, h: Integer;
  curRGB: Integer;
  dotRect: TRectF;
  cx, cy, r: Single;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  w := rc.Right - rc.Left;
  h := rc.Bottom - rc.Top;
  if w <= 0 then w := 15;
  if h <= 0 then Exit;

  curRGB := HSVtoRGB(FHue, FSat, FVal);
  if (XC_GetObjectType(FAlphaBarImage) <> XC_IMAGE) or (FAlphaBarColor <> curRGB) then
    CreateAlphaBarImage(w, h);

  XDraw_ImageExF(hDraw, FAlphaBarImage, rc.Left, rc.Top, w, h);

  // Alpha 指示器: 空心圆环 (黑-白-黑)
  cx := rc.Left + w / 2.0;
  cy := rc.Top + FAlpha * h;
  // 外圈黑色描边
  r := w / 2.0;
  if cy < rc.Top + r then cy := rc.Top + r;
  if cy > rc.Top + h - r then cy := rc.Top + h - r;
  dotRect.Left := cx - r; dotRect.Top := cy - r;
  dotRect.Right := cx + r; dotRect.Bottom := cy + r;
  XDraw_SetLineWidthF(hDraw, 1.0);
  XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, 100));
  XDraw_DrawEllipseF(hDraw, dotRect);
  // 白色圆环
  r := r - 1.5;
  dotRect.Left := cx - r; dotRect.Top := cy - r;
  dotRect.Right := cx + r; dotRect.Bottom := cy + r;
  XDraw_SetLineWidthF(hDraw, 2.0);
  XDraw_SetBrushColor(hDraw, RGBA(255, 255, 255, 255));
  XDraw_DrawEllipseF(hDraw, dotRect);
  // 内圈黑色描边
  r := r - 1.5;
  dotRect.Left := cx - r; dotRect.Top := cy - r;
  dotRect.Right := cx + r; dotRect.Bottom := cy + r;
  XDraw_SetLineWidthF(hDraw, 1.0);
  XDraw_SetBrushColor(hDraw, RGBA(0, 0, 0, 100));
  XDraw_DrawEllipseF(hDraw, dotRect);
end;

class function TColorPickerDialogUI.OnPreviewPaint(hEle: HELE; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  rr: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  rr := 4;
  XDraw_SetBrushColor(hDraw, HSVtoRGB(FHue, FSat, FVal));
  XDraw_FillRoundRect(hDraw, rc, rr, rr);
end;

class function TColorPickerDialogUI.OnColorPanelLButtonDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;
  FDragging := True;
  XEle_SetCapture(hEle, True);
  XEle_GetClientRect(hEle, rc);
  if rc.Right - rc.Left > 0 then
    FSat := (pPt.X - rc.Left) / (rc.Right - rc.Left);
  if rc.Bottom - rc.Top > 0 then
    FVal := 1.0 - (pPt.Y - rc.Top) / (rc.Bottom - rc.Top);
  if FSat < 0 then FSat := 0 else if FSat > 1 then FSat := 1;
  if FVal < 0 then FVal := 0 else if FVal > 1 then FVal := 1;
  XEle_Redraw(hEle);
  XEle_Redraw(XC_GetObjectByName(ID_ELE_ALPHA_BAR));
  XEle_Redraw(FPreviewEle);
  UpdateEdits;
end;

class function TColorPickerDialogUI.OnColorPanelLButtonUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  FDragging := False;
  XEle_SetCapture(hEle, False);
end;

class function TColorPickerDialogUI.OnColorPanelMouseMove(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  if not FDragging then
    Exit;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  if rc.Right - rc.Left > 0 then
    FSat := (pPt.X - rc.Left) / (rc.Right - rc.Left);
  if rc.Bottom - rc.Top > 0 then
    FVal := 1.0 - (pPt.Y - rc.Top) / (rc.Bottom - rc.Top);
  if FSat < 0 then FSat := 0 else if FSat > 1 then FSat := 1;
  if FVal < 0 then FVal := 0 else if FVal > 1 then FVal := 1;
  XEle_Redraw(hEle);
  XEle_Redraw(XC_GetObjectByName(ID_ELE_ALPHA_BAR));
  XEle_Redraw(FPreviewEle);
  UpdateEdits;
end;

class function TColorPickerDialogUI.OnHueBarLButtonUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  FDragging := False;
  XEle_SetCapture(hEle, False);
end;

class function TColorPickerDialogUI.OnHueBarMouseMove(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  if not FDragging then
    Exit;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  if rc.Bottom - rc.Top > 0 then
    FHue := (pPt.Y - rc.Top) / (rc.Bottom - rc.Top) * 360;
  if FHue < 0 then FHue := 0 else if FHue > 360 then FHue := 360;
  XEle_Redraw(hEle);
  XEle_Redraw(XC_GetObjectByName(ID_ELE_COLOR_PANEL));
  XEle_Redraw(XC_GetObjectByName(ID_ELE_ALPHA_BAR));
  XEle_Redraw(FPreviewEle);
  UpdateEdits;
end;

class function TColorPickerDialogUI.OnHueBarLButtonDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;
  FDragging := True;
  XEle_SetCapture(hEle, True);
  XEle_GetClientRect(hEle, rc);
  if rc.Bottom - rc.Top > 0 then
    FHue := (pPt.Y - rc.Top) / (rc.Bottom - rc.Top) * 360;
  if FHue < 0 then FHue := 0 else if FHue > 360 then FHue := 360;
  XEle_Redraw(hEle);
  XEle_Redraw(XC_GetObjectByName(ID_ELE_COLOR_PANEL));
  XEle_Redraw(XC_GetObjectByName(ID_ELE_ALPHA_BAR));
  XEle_Redraw(FPreviewEle);
  UpdateEdits;
end;

class function TColorPickerDialogUI.OnAlphaBarLButtonDown(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;
  FDragging := True;
  XEle_SetCapture(hEle, True);
  XEle_GetClientRect(hEle, rc);
  if rc.Bottom - rc.Top > 0 then
    FAlpha := (pPt.Y - rc.Top) / (rc.Bottom - rc.Top);
  if FAlpha < 0 then FAlpha := 0 else if FAlpha > 1 then FAlpha := 1;
  XEle_Redraw(hEle);
  XEle_Redraw(FPreviewEle);
  UpdateEdits;
end;

class function TColorPickerDialogUI.OnAlphaBarMouseMove(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  if not FDragging then
    Exit;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);                                            
  if rc.Bottom - rc.Top > 0 then                                                                
    FAlpha := (pPt.Y - rc.Top) / (rc.Bottom - rc.Top);
  if FAlpha < 0 then FAlpha := 0 else if FAlpha > 1 then FAlpha := 1;
  XEle_Redraw(hEle);
  XEle_Redraw(FPreviewEle);
  UpdateEdits;
end;

class function TColorPickerDialogUI.OnAlphaBarLButtonUp(hEle: HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  FDragging := False;
  XEle_SetCapture(hEle, False);
end;

class function TColorPickerDialogUI.OnEditChanged(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
var
  txt: string;
  r, g, b, a: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  if FUpdating then Exit;
  if XC_GetObjectType(hEle) <> XC_EDIT then Exit;
  if (XC_GetObjectType(FEdtRHandle) <> XC_EDIT) or (XC_GetObjectType(FEdtGHandle) <> XC_EDIT) or
     (XC_GetObjectType(FEdtBHandle) <> XC_EDIT) or (XC_GetObjectType(FEdtAHandle) <> XC_EDIT) or
     (XC_GetObjectType(FEdtHexHandle) <> XC_EDIT) then Exit;

  if hEle = FEdtRHandle then
  begin
    r := StrToIntDef(string(XEdit_GetText_Temp(hEle)), 0);
    if r < 0 then r := 0 else if r > 255 then r := 255;
    g := StrToIntDef(string(XEdit_GetText_Temp(FEdtGHandle)), 0);
    b := StrToIntDef(string(XEdit_GetText_Temp(FEdtBHandle)), 0);
    RGBtoHSV(r, g, b, FHue, FSat, FVal);
  end
  else if hEle = FEdtGHandle then
  begin
    r := StrToIntDef(string(XEdit_GetText_Temp(FEdtRHandle)), 0);
    g := StrToIntDef(string(XEdit_GetText_Temp(hEle)), 0);
    if g < 0 then g := 0 else if g > 255 then g := 255;
    b := StrToIntDef(string(XEdit_GetText_Temp(FEdtBHandle)), 0);
    RGBtoHSV(r, g, b, FHue, FSat, FVal);
  end
  else if hEle = FEdtBHandle then
  begin
    r := StrToIntDef(string(XEdit_GetText_Temp(FEdtRHandle)), 0);
    g := StrToIntDef(string(XEdit_GetText_Temp(FEdtGHandle)), 0);
    b := StrToIntDef(string(XEdit_GetText_Temp(hEle)), 0);
    if b < 0 then b := 0 else if b > 255 then b := 255;
    RGBtoHSV(r, g, b, FHue, FSat, FVal);
  end
  else if hEle = FEdtAHandle then
  begin
    a := StrToIntDef(string(XEdit_GetText_Temp(hEle)), 255);
    if a < 0 then a := 0 else if a > 255 then a := 255;
    FAlpha := a / 255;
  end
  else if hEle = FEdtHexHandle then
  begin
    txt := Trim(string(XEdit_GetText_Temp(hEle)));
    if txt <> '' then
    begin
      if txt[1] = '#' then Delete(txt, 1, 1);
      a := StrToIntDef('$' + Copy(txt, 1, 2), 255);
      r := StrToIntDef('$' + Copy(txt, 3, 2), 0);
      g := StrToIntDef('$' + Copy(txt, 5, 2), 0);
      b := StrToIntDef('$' + Copy(txt, 7, 2), 0);
      if a < 0 then a := 0 else if a > 255 then a := 255;
      FAlpha := a / 255;
      RGBtoHSV(r, g, b, FHue, FSat, FVal);
    end;
  end;

  // 更新当前RGB值
  FCurrentR := StrToIntDef(string(XEdit_GetText_Temp(FEdtRHandle)), 255);
  FCurrentG := StrToIntDef(string(XEdit_GetText_Temp(FEdtGHandle)), 255);
  FCurrentB := StrToIntDef(string(XEdit_GetText_Temp(FEdtBHandle)), 255);
  if FCurrentR < 0 then FCurrentR := 0 else if FCurrentR > 255 then FCurrentR := 255;
  if FCurrentG < 0 then FCurrentG := 0 else if FCurrentG > 255 then FCurrentG := 255;
  if FCurrentB < 0 then FCurrentB := 0 else if FCurrentB > 255 then FCurrentB := 255;

  XEle_Redraw(XC_GetObjectByName(ID_ELE_COLOR_PANEL));
  XEle_Redraw(XC_GetObjectByName(ID_ELE_HUE_BAR));
  XEle_Redraw(XC_GetObjectByName(ID_ELE_ALPHA_BAR));
  XEle_Redraw(FPreviewEle);
end;

class function TColorPickerDialogUI.PickColor(const hParent: HWND; hAttachWnd: Integer; var ARed, AGreen, ABlue: Integer; var AAlpha: Byte): Boolean;
var
  dlg: TColorPickerDialogUI;
begin
  // 用传入的颜色初始化 HSV 和当前RGB值
  RGBtoHSV(ARed, AGreen, ABlue, FHue, FSat, FVal);
  FCurrentR := ARed;
  FCurrentG := AGreen;
  FCurrentB := ABlue;
  FAlpha := AAlpha / 255;

  dlg := TColorPickerDialogUI.LoadLayout('Resource\Layout\ColorPickerDialog.xml', hParent, hAttachWnd);
  if dlg = nil then
    Exit(False);

  Result := XModalWnd_DoModal(dlg.Handle) = IDOK;
  if Result then
  begin
    ARed := FCurrentR;
    AGreen := FCurrentG;
    ABlue := FCurrentB;
    AAlpha := Round(FAlpha * 255);
  end;
  DestroyCachedImages;
end;

class function TColorPickerDialogUI.OnBtnScreenColorPicker(hEle: HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
end;

end.
