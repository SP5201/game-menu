unit UI_HintPopup;

interface

uses
  Windows, Messages, Classes, SysUtils, Types, Math, XCGUI, UI_Form,
  UI_Theme, UI_TooltipShape;

type
  THintPopupStyle = (hpsNormal, hpsBubble);

  /// 轻量提示窗：可控时长/位置，不依赖系统 Tooltip
  THintPopupUI = class(TFormUI)
  private
    class var
      FInstance: THintPopupUI;
    class var
      FOwnerWindow: XCGUI.HWINDOW;
      FTextShape: HXCGUI;
      FHoverHintMap: TStringList;
      FHoverStyleMap: TStringList;
      FIsVisible: Boolean;
      FLastTargetHandle: HXCGUI;
      FLastText: string;
      FLastStyle: THintPopupStyle;
      FCurrentStyle: THintPopupStyle;
      FArrowEdge: TTooltipArrowEdge;
      FTriangleCenterX: Integer;
      FBubbleLayout: TTooltipBubbleLayout;
    class function OnWndPaint(hWindow: XCGUI.HWINDOW; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnTargetMouseMove(hEle: XCGUI.HELE; nFlags: Cardinal; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnTargetMouseLeave(hEle: XCGUI.HELE; hEleStay: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function EnsureInstance(const ATargetComponentHandle: HXCGUI): THintPopupUI; static;
    class function GetHoverStyle(const ATargetComponentHandle: HXCGUI): THintPopupStyle; static;
    procedure SetTextAndResize(const AText: string);
  protected
    procedure Init; override;
  public
    class procedure ShowTextNearCursor(const AText: string; const AAutoCloseMs: Integer;
      const AStyle: THintPopupStyle = hpsNormal); static;
    class procedure ShowTextForTarget(const ATargetComponentHandle: HXCGUI; const AText: string;
      const AAutoCloseMs: Integer; const APopupAbove: Boolean = False; const AOffsetY: Integer = 0;
      const AStyle: THintPopupStyle = hpsNormal); static;
    class procedure BindHoverHint(const ATargetComponentHandle: HXCGUI; const AText: string;
      const AStyle: THintPopupStyle = hpsNormal); static;
    class procedure Hide; static;
  end;

implementation

const
  HintContentPad = 4;
  HintMaxWidth = 520;
  HintMaxHeight = 420;
  HintShadowExtendX = 20;
  HintShadowExtendY = 20;
  HintTargetGap = 4;

procedure THintPopupUI.Init;
begin
  inherited;
  { TFormUI.ApplyDefault 会设为 shadow 窗口；提示框须用 shaped，阴影由绘制区自行留白 }
  SetTransparentType(window_transparent_shaped);
  SetTransparentAlpha(255);
  SetShadowInfo(0, 0, 0, False, 0);
  RegEvent(WM_PAINT, @THintPopupUI.OnWndPaint);
end;

class function THintPopupUI.OnWndPaint(hWindow: XCGUI.HWINDOW; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  XDraw_EnableSmoothingMode(hDraw, True);
  XWnd_GetClientRect(hWindow, rc);

  if FCurrentStyle = hpsBubble then
  begin
    TooltipDrawBubble(hDraw, rc, FBubbleLayout, FArrowEdge, FTriangleCenterX);
    pbHandled^ := True;
    Exit;
  end;

  TooltipPrepareDraw(hDraw);
  TooltipDrawRoundRectPopup(hDraw, rc, HintShadowExtendX, TooltipCornerRadius);
  pbHandled^ := True;
end;

class function THintPopupUI.GetHoverStyle(const ATargetComponentHandle: HXCGUI): THintPopupStyle;
var
  styleIndex: Integer;
  styleKey: string;
begin
  Result := hpsNormal;
  if not Assigned(FHoverStyleMap) then
    Exit;
  styleKey := IntToStr(ATargetComponentHandle);
  styleIndex := FHoverStyleMap.IndexOfName(styleKey);
  if styleIndex >= 0 then
    Result := THintPopupStyle(StrToIntDef(FHoverStyleMap.ValueFromIndex[styleIndex], Ord(hpsNormal)));
end;

class function THintPopupUI.OnTargetMouseMove(hEle: XCGUI.HELE; nFlags: Cardinal; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
var
  tipText: string;
  hintIndex: Integer;
  hintStyle: THintPopupStyle;
begin
  Result := 0;
  tipText := '';
  if Assigned(FHoverHintMap) then
  begin
    hintIndex := FHoverHintMap.IndexOfName(IntToStr(hEle));
    if hintIndex >= 0 then
      tipText := FHoverHintMap.ValueFromIndex[hintIndex];
  end;
  if tipText <> '' then
  begin
    hintStyle := GetHoverStyle(hEle);
    if FIsVisible and (FLastTargetHandle = hEle) and (FLastText = tipText) and (FLastStyle = hintStyle) then
      Exit;
    ShowTextForTarget(hEle, tipText, 0, False, 0, hintStyle);
  end;
end;

class function THintPopupUI.OnTargetMouseLeave(hEle: XCGUI.HELE; hEleStay: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  Hide;
end;

class function THintPopupUI.EnsureInstance(const ATargetComponentHandle: HXCGUI): THintPopupUI;
const
  WS_EX_NOACTIVATE = $08000000;
var
  exStyle: DWORD;
  style: DWORD;
  hOwnerWindow: XCGUI.HWINDOW;
begin
  hOwnerWindow := 0;
  if ATargetComponentHandle <> 0 then
    hOwnerWindow := XWidget_GetHWINDOW(ATargetComponentHandle);

  if Assigned(FInstance) and FInstance.IsHWINDOW and (FOwnerWindow = hOwnerWindow) then
    Exit(FInstance);

  if Assigned(FInstance) and FInstance.IsHWINDOW then
    XWnd_DestroyWindow(FInstance.Handle);
  FInstance := nil;
  FOwnerWindow := hOwnerWindow;

  exStyle := WS_EX_TOPMOST or WS_EX_TRANSPARENT or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE;
  style := WS_POPUP;

  FInstance := THintPopupUI.CreateEx(exStyle, style, nil, 0, 0, 0, 0, '', hOwnerWindow, window_style_nothing);

  XWnd_SetTransparentType(FInstance.Handle, Ord(window_transparent_shaped));
  XWnd_SetTransparentAlpha(FInstance.Handle, 255);

  FInstance.FTextShape := XShapeText_Create(HintContentPad, HintContentPad, 200, 80, '', FInstance.Handle);
  XShapeText_SetTextAlign(FInstance.FTextShape, DT_LEFT or DT_TOP or DT_WORDBREAK);
  XShapeText_SetTextColor(FInstance.FTextShape, UITheme_TextPrimary);
  XWnd_ShowWindow(FInstance.Handle, SW_HIDE);

  Result := FInstance;
  Result.Init;
end;

procedure THintPopupUI.SetTextAndResize(const AText: string);
var
  sz: TSize;
  nFont: HFONTX;
  rc: TRect;
  w, h: Integer;
  rcText: TRect;
  maxTextW: Integer;
begin
  XShapeText_SetText(FTextShape, PWideChar(AText));

  nFont := XC_GetDefaultFont();
  XC_GetTextShowSize(PWideChar(AText), -1, nFont, sz);

  if FCurrentStyle = hpsBubble then
  begin
    maxTextW := HintMaxWidth - FBubbleLayout.TextPadX * 2 - FBubbleLayout.ShadowPad * 2;
    if sz.cx > maxTextW then
      sz.cx := maxTextW;
    if sz.cy > HintMaxHeight - FBubbleLayout.TextPadY * 2 - FBubbleLayout.ShadowPad * 2 - FBubbleLayout.TriangleSize then
      sz.cy := HintMaxHeight - FBubbleLayout.TextPadY * 2 - FBubbleLayout.ShadowPad * 2 - FBubbleLayout.TriangleSize;
    TooltipCalcBubbleSize(sz, FBubbleLayout, FArrowEdge, w, h);
    rc := Rect(0, 0, w, h);
    XWnd_SetRect(Handle, rc);
    TooltipCalcTextRect(rc, FBubbleLayout, FArrowEdge, rcText);
    XShape_SetRect(FTextShape, rcText);
    Exit;
  end;

  w := sz.cx + HintContentPad * 2 + HintShadowExtendX * 2;
  h := sz.cy + HintContentPad * 2 + HintShadowExtendY * 2;
  if w > HintMaxWidth + HintShadowExtendX * 2 then
    w := HintMaxWidth + HintShadowExtendX * 2;
  if h > HintMaxHeight + HintShadowExtendY * 2 then
    h := HintMaxHeight + HintShadowExtendY * 2;

  rc := Rect(0, 0, w, h);
  XWnd_SetRect(Handle, rc);
  rcText := Rect(HintShadowExtendX + HintContentPad, HintShadowExtendY + HintContentPad,
    w - HintShadowExtendX - HintContentPad, h - HintShadowExtendY - HintContentPad);
  XShape_SetRect(FTextShape, rcText);
end;

class procedure THintPopupUI.ShowTextNearCursor(const AText: string; const AAutoCloseMs: Integer;
  const AStyle: THintPopupStyle);
var
  dlg: THintPopupUI;
  pt: TPoint;
  rcPopup: TRect;
  x, y, popupW: Integer;
begin
  FCurrentStyle := AStyle;
  if AStyle = hpsBubble then
  begin
    FBubbleLayout := TooltipLayoutLikePopupMenu;
    FArrowEdge := TooltipArrowEdge_Top;
  end;

  dlg := EnsureInstance(0);
  dlg.SetTextAndResize(AText);

  Windows.GetCursorPos(pt);
  x := pt.X + 14;
  y := pt.Y + 18;

  if AStyle = hpsBubble then
  begin
    XWnd_GetRect(dlg.Handle, rcPopup);
    popupW := rcPopup.Right - rcPopup.Left;
    FTriangleCenterX := popupW div 2;
  end;

  XWnd_SetPosition(dlg.Handle, x, y);
  XWnd_ShowWindow(dlg.Handle, SW_SHOWNOACTIVATE);
  FIsVisible := True;
  FLastTargetHandle := 0;
  FLastText := AText;
  FLastStyle := AStyle;
end;

class procedure THintPopupUI.ShowTextForTarget(const ATargetComponentHandle: HXCGUI; const AText: string;
  const AAutoCloseMs: Integer; const APopupAbove: Boolean; const AOffsetY: Integer;
  const AStyle: THintPopupStyle);
var
  dlg: THintPopupUI;
  pt: TPoint;
  ptAnchor: TPoint;
  hTargetWindow: XCGUI.HWINDOW;
  rcTarget: TRect;
  rcPopup: TRect;
  popupW, popupH, targetW: Integer;
  x, y: Integer;
begin
  FCurrentStyle := AStyle;
  if AStyle = hpsBubble then
  begin
    FBubbleLayout := TooltipLayoutLikePopupMenu;
    if APopupAbove then
      FArrowEdge := TooltipArrowEdge_Bottom
    else
      FArrowEdge := TooltipArrowEdge_Top;
  end;

  dlg := EnsureInstance(ATargetComponentHandle);
  dlg.SetTextAndResize(AText);

  if ATargetComponentHandle <> 0 then
  begin
    hTargetWindow := XWidget_GetHWINDOW(ATargetComponentHandle);
    XEle_GetWndClientRectDPI(ATargetComponentHandle, rcTarget);

    XWnd_GetRect(dlg.Handle, rcPopup);
    popupW := rcPopup.Right - rcPopup.Left;
    popupH := rcPopup.Bottom - rcPopup.Top;
    targetW := rcTarget.Right - rcTarget.Left;

    if APopupAbove then
    begin
      ptAnchor := TPoint.Create(rcTarget.Left, rcTarget.Top);
      XWnd_ClientToScreen(hTargetWindow, ptAnchor);
      x := ptAnchor.X + (targetW - popupW) div 2;
      y := ptAnchor.Y - popupH - HintTargetGap;
    end
    else
    begin
      ptAnchor := TPoint.Create(rcTarget.Left, rcTarget.Bottom);
      XWnd_ClientToScreen(hTargetWindow, ptAnchor);
      x := ptAnchor.X + (targetW - popupW) div 2;
      y := ptAnchor.Y + HintTargetGap;
    end;
    Inc(y, AOffsetY);

    if AStyle = hpsBubble then
    begin
      ptAnchor.X := (rcTarget.Left + rcTarget.Right) div 2;
      ptAnchor.Y := rcTarget.Top;
      XWnd_ClientToScreen(hTargetWindow, ptAnchor);
      FTriangleCenterX := ptAnchor.X - x;
    end;
  end
  else
  begin
    Windows.GetCursorPos(pt);
    x := pt.X + 14;
    y := pt.Y + 18;
    if AStyle = hpsBubble then
    begin
      XWnd_GetRect(dlg.Handle, rcPopup);
      popupW := rcPopup.Right - rcPopup.Left;
      FTriangleCenterX := popupW div 2;
    end;
  end;

  XWnd_SetPosition(dlg.Handle, x, y);
  XWnd_ShowWindow(dlg.Handle, SW_SHOWNOACTIVATE);
  FIsVisible := True;
  FLastTargetHandle := ATargetComponentHandle;
  FLastText := AText;
  FLastStyle := AStyle;
end;

class procedure THintPopupUI.BindHoverHint(const ATargetComponentHandle: HXCGUI; const AText: string;
  const AStyle: THintPopupStyle);
var
  hintIndex: Integer;
  hintKey: string;
begin
  if ATargetComponentHandle = 0 then
    Exit;
  if FHoverHintMap = nil then
  begin
    FHoverHintMap := TStringList.Create;
    FHoverHintMap.NameValueSeparator := '=';
  end;
  if FHoverStyleMap = nil then
  begin
    FHoverStyleMap := TStringList.Create;
    FHoverStyleMap.NameValueSeparator := '=';
  end;
  hintKey := IntToStr(ATargetComponentHandle);
  hintIndex := FHoverHintMap.IndexOfName(hintKey);
  if hintIndex >= 0 then
  begin
    FHoverHintMap.ValueFromIndex[hintIndex] := AText;
    FHoverStyleMap.Values[hintKey] := IntToStr(Ord(AStyle));
  end
  else
  begin
    FHoverHintMap.Add(hintKey + '=' + AText);
    FHoverStyleMap.Add(hintKey + '=' + IntToStr(Ord(AStyle)));
    XEle_RegEvent(ATargetComponentHandle, XE_MOUSEMOVE, @THintPopupUI.OnTargetMouseMove);
    XEle_RegEvent(ATargetComponentHandle, XE_MOUSELEAVE, @THintPopupUI.OnTargetMouseLeave);
  end;
end;

class procedure THintPopupUI.Hide;
begin
  if Assigned(FInstance) and FInstance.IsHWINDOW then
    XWnd_ShowWindow(FInstance.Handle, SW_HIDE);
  FIsVisible := False;
  FLastTargetHandle := 0;
  FLastText := '';
  FLastStyle := hpsNormal;
end;

initialization
  THintPopupUI.FHoverHintMap := nil;
  THintPopupUI.FHoverStyleMap := nil;
  THintPopupUI.FIsVisible := False;
  THintPopupUI.FLastTargetHandle := 0;
  THintPopupUI.FLastText := '';
  THintPopupUI.FLastStyle := hpsNormal;
  THintPopupUI.FCurrentStyle := hpsNormal;
  THintPopupUI.FBubbleLayout := TooltipLayoutLikePopupMenu;
  THintPopupUI.FTriangleCenterX := 0;

finalization
  FreeAndNil(THintPopupUI.FHoverStyleMap);
  FreeAndNil(THintPopupUI.FHoverHintMap);

end.
