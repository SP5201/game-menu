unit UI_SliderValuePopup;

interface

uses
  Windows, Messages, Classes, SysUtils, Types, Math, XCGUI, UI_Form, UI_Theme, UI_TooltipShape;

type
  /// 滑动条拖动时在滑块上方显示当前值的气泡窗（圆角矩形 + 三角箭头）
  TSliderValuePopupUI = class(TFormUI)
  private
    class var
      FInstance: TSliderValuePopupUI;
      FOwnerHwnd: HWND;
      FTextShape: HXCGUI;
      FBoundSlider: HELE;
      FIsVisible: Boolean;
      FLastText: string;
      FLayout: TTooltipBubbleLayout;
      FTriangleCenterX: Integer;
    class function OnWndPaint(hWindow: hWindow; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall; static;
    class function EnsureInstance(const ASlider: HELE): TSliderValuePopupUI; static;
    procedure SetTextAndResize(const AText: string);
    class procedure PositionAboveThumb(const ASlider: HELE); static;
  protected
    procedure Init; override;
  public
    class procedure ShowForSlider(const ASlider: HELE; const AText: string); static;
    class procedure UpdateForSlider(const ASlider: HELE; const AText: string); static;
    class procedure Hide; static;
  end;

implementation

const
  ValueMaxWidth = 200;
  ValueThumbGap = 8;

procedure TSliderValuePopupUI.Init;
begin
  inherited;
  SetTransparentType(window_transparent_shaped);
  SetTransparentAlpha(255);
  SetShadowInfo(0, 0, 0, False, 0);
  RegEvent(WM_PAINT, @TSliderValuePopupUI.OnWndPaint);
end;

class function TSliderValuePopupUI.OnWndPaint(hWindow: hWindow; hDraw: hDraw; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  XWnd_GetClientRect(hWindow, rc);
  TooltipDrawBubble(hDraw, rc, FLayout, TooltipArrowEdge_Bottom, FTriangleCenterX);
  pbHandled^ := True;
end;

class function TSliderValuePopupUI.EnsureInstance(const ASlider: HELE): TSliderValuePopupUI;
const
  WS_EX_NOACTIVATE = $08000000;
var
  exStyle: DWORD;
  style: DWORD;
  ownerHwnd: Integer;
  rcText: TRect;
begin
  ownerHwnd := 0;
  if ASlider <> 0 then
    ownerHwnd := XWidget_GetHWND(ASlider);

  if Assigned(FInstance) and FInstance.IsHWINDOW and (NativeUInt(FOwnerHwnd) = NativeUInt(ownerHwnd)) then
    Exit(FInstance);

  if Assigned(FInstance) and FInstance.IsHWINDOW then
    XWnd_DestroyWindow(FInstance.Handle);
  FInstance := nil;
  FOwnerHwnd := ownerHwnd;
  FLayout := TooltipLayoutLikePopupMenu;

  exStyle := WS_EX_TOPMOST or WS_EX_TRANSPARENT or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE;
  style := WS_POPUP;

  FInstance := TSliderValuePopupUI.CreateEx(exStyle, style, nil, 0, 0, 0, 0, '', ownerHwnd, window_style_nothing);
  XWnd_SetTransparentType(FInstance.Handle, Ord(window_transparent_shaped));
  XWnd_SetTransparentAlpha(FInstance.Handle, 255);

  FInstance.FTextShape := XShapeText_Create(0, 0, 80, 24, '', FInstance.Handle);
  XShapeText_SetTextAlign(FInstance.FTextShape, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
  XShapeText_SetTextColor(FInstance.FTextShape, UITheme_TextPrimary);
  rcText := Rect(0, 0, 80, 24);
  XShape_SetRect(FInstance.FTextShape, rcText);
  XWnd_ShowWindow(FInstance.Handle, SW_HIDE);

  Result := FInstance;
  Result.Init;
end;

procedure TSliderValuePopupUI.SetTextAndResize(const AText: string);
var
  sz: TSize;
  nFont: HFONTX;
  rc: TRect;
  w, h: Integer;
  rcText: TRect;
begin
  XShapeText_SetText(FTextShape, PWideChar(AText));

  nFont := XC_GetDefaultFont();
  XC_GetTextShowSize(PWideChar(AText), -1, nFont, sz);

  if sz.cx > ValueMaxWidth - FLayout.TextPadX * 2 - FLayout.ShadowPad * 2 then
    sz.cx := ValueMaxWidth - FLayout.TextPadX * 2 - FLayout.ShadowPad * 2;
  TooltipCalcBubbleSize(sz, FLayout, TooltipArrowEdge_Bottom, w, h);

  rc := Rect(0, 0, w, h);
  XWnd_SetRect(Handle, rc);
  TooltipCalcTextRect(rc, FLayout, TooltipArrowEdge_Bottom, rcText);
  XShape_SetRect(FTextShape, rcText);
end;

class procedure TSliderValuePopupUI.PositionAboveThumb(const ASlider: HELE);
var
  btnEle: HELE;
  hWnd: Integer;
  rcBtn, rcClient: TRect;
  pt: TPoint;
  popupW, popupH: Integer;
  x, y: Integer;
begin
  if not Assigned(FInstance) or not FInstance.IsHWINDOW then
    Exit;

  btnEle := XSliderBar_GetButton(ASlider);
  if not XC_IsHELE(btnEle) then
    Exit;

  hWnd := XWidget_GetHWINDOW(ASlider);
  XEle_GetWndClientRectDPI(btnEle, rcBtn);
  pt.X := (rcBtn.Left + rcBtn.Right) div 2;
  pt.Y := rcBtn.Top;
  XWnd_ClientToScreen(hWnd, pt);

  XWnd_GetClientRect(FInstance.Handle, rcClient);
  popupW := rcClient.Right - rcClient.Left;
  popupH := rcClient.Bottom - rcClient.Top;

  x := pt.X - popupW div 2;
  y := pt.Y - popupH - ValueThumbGap;
  XWnd_SetPosition(FInstance.Handle, x, y);
  { 三角在气泡底部水平居中，与滑块按钮中心对齐 }
  FTriangleCenterX := popupW div 2;
  XWnd_Redraw(FInstance.Handle, False);
end;

class procedure TSliderValuePopupUI.ShowForSlider(const ASlider: HELE; const AText: string);
var
  dlg: TSliderValuePopupUI;
begin
  if not XC_IsHELE(ASlider) then
    Exit;
  dlg := EnsureInstance(ASlider);
  dlg.SetTextAndResize(AText);
  PositionAboveThumb(ASlider);
  XWnd_ShowWindow(dlg.Handle, SW_SHOWNOACTIVATE);
  FBoundSlider := ASlider;
  FIsVisible := True;
  FLastText := AText;
end;

class procedure TSliderValuePopupUI.UpdateForSlider(const ASlider: HELE; const AText: string);
var
  dlg: TSliderValuePopupUI;
begin
  if not FIsVisible or (FBoundSlider <> ASlider) then
    Exit;
  if FLastText = AText then
  begin
    PositionAboveThumb(ASlider);
    Exit;
  end;
  dlg := EnsureInstance(ASlider);
  dlg.SetTextAndResize(AText);
  PositionAboveThumb(ASlider);
  FLastText := AText;
end;

class procedure TSliderValuePopupUI.Hide;
begin
  if Assigned(FInstance) and FInstance.IsHWINDOW then
    XWnd_ShowWindow(FInstance.Handle, SW_HIDE);
  FIsVisible := False;
  FBoundSlider := 0;
  FLastText := '';
end;

initialization
  TSliderValuePopupUI.FBoundSlider := 0;
  TSliderValuePopupUI.FIsVisible := False;
  TSliderValuePopupUI.FLastText := '';
  TSliderValuePopupUI.FLayout := TooltipLayoutLikePopupMenu;
  TSliderValuePopupUI.FTriangleCenterX := 0;

end.
