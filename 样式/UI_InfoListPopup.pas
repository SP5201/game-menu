unit UI_InfoListPopup;

{
  信息行列表悬停弹层：独立弹出窗口 + ListBox，可复用于状态栏 IP/天气等多行说明。
}

interface

uses
  Windows, Messages, Classes, SysUtils, Types, Math, Generics.Collections, XCGUI,
  UI_Form, UI_Theme;

type
  /// <summary>悬停弹层拉取正文（IP/天气等），弹层可见时由 NotifyContentChanged 就地刷新。</summary>
  TInfoListGetTextFunc = function: string;

  TInfoListHoverBind = class
  public
    Target: HELE;
    GetText: TInfoListGetTextFunc;
    PopupAbove: Boolean;
    OffsetY: Integer;
  end;

  TInfoListPopupUI = class(TFormUI)
  private
    class var
      FInstance: TInfoListPopupUI;
      FInstanceHwnd: XCGUI.HWINDOW;
      FOwnerWindow: XCGUI.HWINDOW;
      FListBoxHele: HELE;
      FHoverBinds: TObjectList<TInfoListHoverBind>;
      FIsVisible: Boolean;
      FLastBodyText: string;
      FDisplayLines: TStringList;
      FLabelColWidth: Integer;
      FPopupAbove: Boolean;
      FPopupOffsetY: Integer;
      FBoundTargetHandle: HELE;
      FPopupUpdateLock: Boolean;
      FRefreshPending: Boolean;
      FDeferFirstShow: Boolean;
      FDeferSwitchingTarget: Boolean;
      FInfoSvgCache: TStringList;
    class procedure EnsureHoverBinds; static;
    class function FindBindIndex(const ATarget: HELE): Integer; static;
    class function FindBindIndexForEle(const AEle: HELE): Integer; static;
    class function IsEleUnderBindTarget(const AEle, ABindTarget: HELE): Boolean; static;
    class function IsStayWithinBoundHover(const AStayEle: HELE): Boolean; static;
    class function GetBoundText: string; static;
    class procedure SplitInfoLine(const ALine: string; out ALabel, AValue: string; out AHasValueCol: Boolean); static;
    class function TryParseSvgValue(const AValue: string; out ASvgPath: string;
      out ADrawW, ADrawH: Integer): Boolean; static;
    class function ResolveInfoSvgFile(const ASvgRelPath: string): string; static;
    class function InfoSvgFallbackText(const ASvgPath: string): string; static;
    class function ResolveInfoSvgColor(const ASvgPath: string): Integer; static;
    class procedure ApplyInfoSvgStyle(const hSvg: XCGUI.HSVG; const ASvgPath: string); static;
    class function GetCachedSvg(const ASvgPath: string): XCGUI.HSVG; static;
    class function MeasureSvgDisplayWidth(const ASvgPath: string; ADrawW, ADrawH: Integer): Integer; static;
    class procedure DrawSvgValue(const AHDraw: XCGUI.HDRAW; const ARcValue: TRect; const ASvgPath: string;
      ADrawW, ADrawH: Integer); static;
    class procedure EnsureSvgCache; static;
    class procedure FreeSvgCache; static;
    class procedure DrawInfoListItem(const AHDraw: XCGUI.HDRAW; const ARcItem: TRect; const ALineText: string; const ALabelColWidth: Integer); static;
    class function MeasureTextWidth(const AText: string; const AFont: HFONTX): Integer; static;
    class procedure CalcInfoListPopupMetrics(const ALines: TStringList; const AFont: HFONTX;
      out ALineCount, ALabelColWidth, APopupW, APopupH: Integer); static;
    class procedure CalcInfoListPopupScreenRect(const APopupW, APopupH: Integer; out ARect: TRect); static;
    class function OnWndPaint(hWindow: XCGUI.HWINDOW; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListDrawItem(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; var pItem: TlistBox_item_; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnListButtonDown(hEle: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnTargetMouseMove(hEle: XCGUI.HELE; nFlags: Cardinal; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnTargetMouseLeave(hEle: XCGUI.HELE; hEleStay: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndTimer(hWindow: XCGUI.HWINDOW; nIDEvent: UINT; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndDestroy(hWindow: XCGUI.HWINDOW; pbHandled: PBOOL): Integer; stdcall; static;
    class function EnsureInstance(const ATargetHandle: HELE): TInfoListPopupUI; static;
    class procedure ClearInstanceRefs; static;
    class procedure RedrawPopup; static;
    class procedure ClearDisplayList(const ARedraw: Boolean); static;
    class procedure RebuildDisplayList(const ABodyText: string); static;
    class procedure ApplyPopupLayout(const AFirstShow, ASwitchingTarget: Boolean); static;
    class procedure RefreshPopup(const AFirstShow, ASwitchingTarget: Boolean); static;
    class procedure SetRefreshTimer(const AEnable: Boolean); static;
  protected
    procedure Init; override;
  public
    class procedure BindHover(const ATargetHandle: HELE; const AGetText: TInfoListGetTextFunc; const APopupAbove: Boolean = False; const AOffsetY: Integer = 0); static;
    class procedure NotifyContentChanged; static;
    class function IsHoverBoundTo(const ATarget: HELE): Boolean; static;
    class procedure Hide; static;
  end;

implementation

uses
  AppPaths;

const
  CInfoPadX = 12;
  CInfoPadY = 8;
  CInfoItemHeight = 22;
  CInfoRowSpace = 0;
  CInfoMinWidth = 160;
  CInfoMaxWidth = 1024;
  CInfoTextMeasureWrapWidth = 8192;
  CInfoTextMeasureAlign = textAlignFlag_left or textAlignFlag_vcenter or textFormatFlag_NoWrap;
  CInfoTextDrawAlignRight = textAlignFlag_right or textAlignFlag_vcenter or textFormatFlag_NoWrap;
  CInfoShadowExt = 8;
  CInfoTargetGap = 4;
  CInfoWndEdgeMargin = 4;
  CInfoLabelColMin = 72;
  CInfoSvgValuePrefix = '#svg:';
  CInfoRefreshTimerId = 1;
  CInfoRefreshTimerMs = 1000;
  CInfoDeferHoverTimerId = 2;
  CInfoDeferHoverTimerMs = 1;

class procedure TInfoListPopupUI.EnsureHoverBinds;
begin
  if FHoverBinds = nil then
    FHoverBinds := TObjectList<TInfoListHoverBind>.Create(True);
end;

class function TInfoListPopupUI.FindBindIndex(const ATarget: HELE): Integer;
var
  i: Integer;
begin
  Result := -1;
  if (FHoverBinds = nil) or not XC_IsHELE(ATarget) then
    Exit;
  for i := 0 to FHoverBinds.Count - 1 do
    if FHoverBinds[i].Target = ATarget then
      Exit(i);
end;

class function TInfoListPopupUI.FindBindIndexForEle(const AEle: HELE): Integer;
var
  i: Integer;
begin
  Result := -1;
  if FHoverBinds = nil then
    Exit;
  for i := 0 to FHoverBinds.Count - 1 do
    if IsEleUnderBindTarget(AEle, FHoverBinds[i].Target) then
      Exit(i);
end;

class function TInfoListPopupUI.IsEleUnderBindTarget(const AEle, ABindTarget: HELE): Boolean;
var
  hCurEle: HELE;
begin
  Result := False;
  if not XC_IsHELE(ABindTarget) or not XC_IsHELE(AEle) then
    Exit;
  hCurEle := AEle;
  while XC_IsHELE(hCurEle) do
  begin
    if hCurEle = ABindTarget then
      Exit(True);
    hCurEle := XWidget_GetParentEle(hCurEle);
  end;
end;

class function TInfoListPopupUI.IsStayWithinBoundHover(const AStayEle: HELE): Boolean;
var
  i: Integer;
begin
  Result := False;
  if FHoverBinds = nil then
    Exit;
  if not XC_IsHELE(AStayEle) then
    Exit;
  for i := 0 to FHoverBinds.Count - 1 do
  begin
    if IsEleUnderBindTarget(AStayEle, FHoverBinds[i].Target) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

class procedure TInfoListPopupUI.SplitInfoLine(const ALine: string; out ALabel, AValue: string; out AHasValueCol: Boolean);
var
  sepPos: Integer;
begin
  ALabel := ALine;
  AValue := '';
  AHasValueCol := False;
  sepPos := Pos(UI_Utf8Src(UTF8String('：')), ALine);
  if sepPos <= 0 then
    sepPos := Pos(':', ALine);
  if sepPos <= 0 then
    Exit;
  ALabel := Copy(ALine, 1, sepPos);
  AValue := Copy(ALine, sepPos + 1, MaxInt);
  AHasValueCol := True;
end;

class procedure TInfoListPopupUI.EnsureSvgCache;
begin
  if FInfoSvgCache = nil then
  begin
    FInfoSvgCache := TStringList.Create;
    FInfoSvgCache.Sorted := True;
    FInfoSvgCache.Duplicates := dupError;
  end;
end;

class function TInfoListPopupUI.TryParseSvgValue(const AValue: string; out ASvgPath: string;
  out ADrawW, ADrawH: Integer): Boolean;
var
  payload, sizePart: string;
  atPos, xPos: Integer;
begin
  ADrawW := 0;
  ADrawH := 0;
  Result := (Length(AValue) > Length(CInfoSvgValuePrefix)) and
    (Copy(AValue, 1, Length(CInfoSvgValuePrefix)) = CInfoSvgValuePrefix);
  if not Result then
  begin
    ASvgPath := '';
    Exit;
  end;
  payload := Copy(AValue, Length(CInfoSvgValuePrefix) + 1, MaxInt);
  atPos := Pos('@', payload);
  if atPos > 0 then
  begin
    ASvgPath := Copy(payload, 1, atPos - 1);
    sizePart := Copy(payload, atPos + 1, MaxInt);
    xPos := Pos('x', sizePart);
    if xPos <= 0 then
      xPos := Pos('X', sizePart);
    if xPos > 0 then
    begin
      ADrawW := StrToIntDef(Copy(sizePart, 1, xPos - 1), 0);
      ADrawH := StrToIntDef(Copy(sizePart, xPos + 1, MaxInt), 0);
    end;
  end
  else
    ASvgPath := payload;
end;

class function TInfoListPopupUI.ResolveInfoSvgFile(const ASvgRelPath: string): string;
begin
  Result := ASvgRelPath;
  if Result = '' then
    Exit;
  if FileExists(Result) then
    Exit;
  Result := AppExeDirectory + Result;
end;

class function TInfoListPopupUI.InfoSvgFallbackText(const ASvgPath: string): string;
var
  baseName: string;
begin
  baseName := LowerCase(ChangeFileExt(ExtractFileName(ASvgPath), ''));
  if baseName = 'amd' then
    Result := 'AMD'
  else if baseName = 'intel' then
    Result := 'Intel'
  else if baseName = 'apple' then
    Result := 'Apple'
  else if baseName = 'qualcomm' then
    Result := 'Qualcomm'
  else if baseName <> '' then
    Result := baseName
  else
    Result := '--';
end;

class function TInfoListPopupUI.ResolveInfoSvgColor(const ASvgPath: string): Integer;
var
  fileName: string;
begin
  fileName := LowerCase(ExtractFileName(ASvgPath));
  if fileName = 'intel.svg' then
    Result := RGBA(0, 113, 197, 255)
  else if fileName = 'amd.svg' then
    Result := RGBA(237, 28, 36, 255)
  else if fileName = 'apple.svg' then
    Result := RGBA(220, 220, 220, 255)
  else if fileName = 'qualcomm.svg' then
    Result := RGBA(50, 83, 220, 255)
  else
    Result := UITheme_TextPrimary;
end;

class procedure TInfoListPopupUI.ApplyInfoSvgStyle(const hSvg: XCGUI.HSVG; const ASvgPath: string);
var
  color: Integer;
begin
  if hSvg <= 0 then
    Exit;
  color := ResolveInfoSvgColor(ASvgPath);
  XSvg_SetUserFillColor(hSvg, color, True);
  XSvg_SetUserStrokeColor(hSvg, color, 1, True);
end;

class function TInfoListPopupUI.GetCachedSvg(const ASvgPath: string): XCGUI.HSVG;
var
  idx: Integer;
  svgHandle: XCGUI.HSVG;
  filePath: string;
begin
  Result := 0;
  if ASvgPath = '' then
    Exit;
  EnsureSvgCache;
  idx := FInfoSvgCache.IndexOf(ASvgPath);
  if idx >= 0 then
    Exit(XCGUI.HSVG(NativeInt(FInfoSvgCache.Objects[idx])));
  filePath := ResolveInfoSvgFile(ASvgPath);
  if not FileExists(filePath) then
    Exit;
  svgHandle := XSvg_LoadFile(PWideChar(filePath));
  if XC_GetObjectType(svgHandle) <> XC_SVG then
    Exit;
  ApplyInfoSvgStyle(svgHandle, ASvgPath);
  FInfoSvgCache.AddObject(ASvgPath, TObject(NativeInt(svgHandle)));
  Result := svgHandle;
end;

class function TInfoListPopupUI.MeasureSvgDisplayWidth(const ASvgPath: string; ADrawW, ADrawH: Integer): Integer;
var
  svgHandle: XCGUI.HSVG;
  svgW, svgH: Integer;
begin
  if ADrawW > 0 then
    Exit(ADrawW);
  Result := 0;
  svgHandle := GetCachedSvg(ASvgPath);
  if svgHandle <= 0 then
    Exit;
  XSvg_GetSize(svgHandle, svgW, svgH);
  if svgH <= 0 then
    Exit;
  if ADrawH > 0 then
    Result := (svgW * ADrawH) div svgH
  else
    Result := svgW;
end;

class procedure TInfoListPopupUI.DrawSvgValue(const AHDraw: XCGUI.HDRAW; const ARcValue: TRect;
  const ASvgPath: string; ADrawW, ADrawH: Integer);
var
  svgHandle: XCGUI.HSVG;
  svgW, svgH, drawW, drawH, x, y: Integer;
begin
  svgHandle := GetCachedSvg(ASvgPath);
  if svgHandle <= 0 then
    Exit;
  XSvg_GetSize(svgHandle, svgW, svgH);
  if ADrawH > 0 then
    drawH := ADrawH
  else if svgH > 0 then
    drawH := svgH
  else
    Exit;
  if ADrawW > 0 then
    drawW := ADrawW
  else if svgH > 0 then
    drawW := (svgW * drawH) div svgH
  else
    drawW := svgW;
  x := ARcValue.Right - drawW;
  y := ARcValue.Top + (ARcValue.Bottom - ARcValue.Top - drawH) div 2;
  XDraw_DrawSvgEx(AHDraw, svgHandle, x, y, drawW, drawH);
end;

class procedure TInfoListPopupUI.FreeSvgCache;
var
  i: Integer;
begin
  if FInfoSvgCache = nil then
    Exit;
  for i := 0 to FInfoSvgCache.Count - 1 do
    XSvg_Release(XCGUI.HSVG(NativeInt(FInfoSvgCache.Objects[i])));
  FreeAndNil(FInfoSvgCache);
end;

class procedure TInfoListPopupUI.DrawInfoListItem(const AHDraw: XCGUI.HDRAW; const ARcItem: TRect; const ALineText: string; const ALabelColWidth: Integer);
var
  rc, rcLabel, rcValue: TRect;
  labelText, valueText, svgPath: string;
  svgW, svgH: Integer;
  hasValueCol: Boolean;
begin
  if ALineText = '' then
    Exit;
  SplitInfoLine(ALineText, labelText, valueText, hasValueCol);
  rc := ARcItem;
  Inc(rc.Left, CInfoPadX);
  Dec(rc.Right, CInfoPadX);
  if not hasValueCol then
  begin
    rcValue := rc;
    rcValue.Left := rcValue.Left + ALabelColWidth;
    XDraw_SetBrushColor(AHDraw, UITheme_TextPrimary);
    XDraw_SetTextAlign(AHDraw, CInfoTextDrawAlignRight);
    XDraw_DrawText(AHDraw, PWideChar(ALineText), -1, rcValue);
  end
  else
  begin
    rcLabel := rc;
    rcLabel.Right := rcLabel.Left + ALabelColWidth;
    rcValue := rc;
    rcValue.Left := rcLabel.Right;

    XDraw_SetBrushColor(AHDraw, UITheme_StatLabel);
    XDraw_SetTextAlign(AHDraw, CInfoTextMeasureAlign);
    XDraw_DrawText(AHDraw, PWideChar(labelText), -1, rcLabel);

    if TryParseSvgValue(valueText, svgPath, svgW, svgH) then
    begin
      if GetCachedSvg(svgPath) > 0 then
        DrawSvgValue(AHDraw, rcValue, svgPath, svgW, svgH)
      else
      begin
        XDraw_SetBrushColor(AHDraw, UITheme_TextPrimary);
        XDraw_SetTextAlign(AHDraw, CInfoTextDrawAlignRight);
        XDraw_DrawText(AHDraw, PWideChar(InfoSvgFallbackText(svgPath)), -1, rcValue);
      end;
    end
    else
    begin
      XDraw_SetBrushColor(AHDraw, UITheme_TextPrimary);
      XDraw_SetTextAlign(AHDraw, CInfoTextDrawAlignRight);
      XDraw_DrawText(AHDraw, PWideChar(valueText), -1, rcValue);
    end;
  end;
end;

class function TInfoListPopupUI.MeasureTextWidth(const AText: string; const AFont: HFONTX): Integer;
var
  sz: TSize;
begin
  Result := 0;
  if AText = '' then
    Exit;
  XC_GetTextShowRect(PWideChar(AText), -1, AFont, CInfoTextMeasureAlign, CInfoTextMeasureWrapWidth, sz);
  Result := sz.cx;
end;

class procedure TInfoListPopupUI.CalcInfoListPopupMetrics(const ALines: TStringList; const AFont: HFONTX;
  out ALineCount, ALabelColWidth, APopupW, APopupH: Integer);
var
  i, labelW, valueW, maxTextW: Integer;
  labelText, valueText, svgPath: string;
  svgW, svgH: Integer;
  hasValueCol: Boolean;
  listH, listTop: Integer;
begin
  ALineCount := 0;
  ALabelColWidth := CInfoLabelColMin;
  maxTextW := 0;
  APopupW := CInfoMinWidth;
  APopupH := 0;
  if (ALines = nil) or (ALines.Count = 0) then
    Exit;
  ALineCount := ALines.Count;
  for i := 0 to ALines.Count - 1 do
  begin
    SplitInfoLine(ALines[i], labelText, valueText, hasValueCol);
    if hasValueCol then
    begin
      labelW := MeasureTextWidth(labelText, AFont);
      if labelW > ALabelColWidth then
        ALabelColWidth := labelW;
      if TryParseSvgValue(valueText, svgPath, svgW, svgH) then
      begin
        if GetCachedSvg(svgPath) > 0 then
          valueW := MeasureSvgDisplayWidth(svgPath, svgW, svgH)
        else
          valueW := MeasureTextWidth(InfoSvgFallbackText(svgPath), AFont);
      end
      else
        valueW := MeasureTextWidth(valueText, AFont);
      Inc(valueW, 2);
      if ALabelColWidth + valueW > maxTextW then
        maxTextW := ALabelColWidth + valueW + (CInfoShadowExt * 2 + CInfoPadX * 2);
    end
    else
    begin
      valueW := MeasureTextWidth(ALines[i], AFont);
      Inc(valueW, 2);
      if ALabelColWidth + valueW > maxTextW then
        maxTextW := ALabelColWidth + valueW + (CInfoShadowExt * 2 + CInfoPadX * 2);
    end;
  end;
  listH := ALineCount * CInfoItemHeight + CInfoPadY;
  listTop := CInfoShadowExt + CInfoPadY;
  APopupW := EnsureRange(maxTextW + CInfoPadX * 2 + CInfoShadowExt * 2, CInfoMinWidth, CInfoMaxWidth);
  APopupH := listTop + listH + CInfoShadowExt;
end;

class procedure TInfoListPopupUI.CalcInfoListPopupScreenRect(const APopupW, APopupH: Integer; out ARect: TRect);
var
  rcTarget, rcMainClient: TRect;
  ptAnchor, ptMainLT, ptMainRB: TPoint;
  hTargetWindow: XCGUI.HWINDOW;
  targetW, x, y, mainL, mainR, minX, maxX: Integer;
begin
  ARect := Rect(0, 0, 0, 0);
  if XC_IsHELE(FBoundTargetHandle) then
  begin
    hTargetWindow := XWidget_GetHWINDOW(FBoundTargetHandle);
    XEle_GetWndClientRectDPI(FBoundTargetHandle, rcTarget);
    targetW := rcTarget.Right - rcTarget.Left;
    if FPopupAbove then
      ptAnchor := TPoint.Create(rcTarget.Left, rcTarget.Top)
    else
      ptAnchor := TPoint.Create(rcTarget.Left, rcTarget.Bottom);
    XWnd_ClientToScreen(hTargetWindow, ptAnchor);
    x := ptAnchor.X + (targetW - APopupW) div 2;
    if FPopupAbove then
      y := ptAnchor.Y - APopupH - CInfoTargetGap
    else
      y := ptAnchor.Y + CInfoTargetGap;
    Inc(y, FPopupOffsetY);

    if XWnd_GetClientRect(hTargetWindow, rcMainClient) then
    begin
      ptMainLT.X := rcMainClient.Left;
      ptMainLT.Y := rcMainClient.Top;
      ptMainRB.X := rcMainClient.Right;
      ptMainRB.Y := rcMainClient.Bottom;
      XWnd_ClientToScreen(hTargetWindow, ptMainLT);
      XWnd_ClientToScreen(hTargetWindow, ptMainRB);
      mainL := ptMainLT.X + CInfoWndEdgeMargin;
      mainR := ptMainRB.X - CInfoWndEdgeMargin;
      if mainR > mainL then
      begin
        minX := mainL;
        maxX := mainR - APopupW;
        if maxX < minX then
          x := minX
        else if x < minX then
          x := minX
        else if x > maxX then
          x := maxX;
      end;
    end;
  end
  else
  begin
    Windows.GetCursorPos(ptAnchor);
    x := ptAnchor.X + 14;
    y := ptAnchor.Y + 18;
  end;
  ARect := Rect(x, y, x + APopupW, y + APopupH);
end;

class function TInfoListPopupUI.GetBoundText: string;
var
  bindIdx: Integer;
begin
  Result := '';
  bindIdx := FindBindIndex(FBoundTargetHandle);
  if (bindIdx >= 0) and Assigned(FHoverBinds[bindIdx].GetText) then
    Result := FHoverBinds[bindIdx].GetText();
end;

procedure TInfoListPopupUI.Init;
begin
  inherited;
  SetTransparentType(window_transparent_shaped);
  SetTransparentAlpha(240);
  SetShadowInfo(0, 0, 0, False, 0);
  RegEvent(WM_PAINT, @TInfoListPopupUI.OnWndPaint);
  RegEvent(WM_TIMER, @TInfoListPopupUI.OnWndTimer);
  RegEvent(WM_DESTROY, @TInfoListPopupUI.OnWndDestroy);
end;

class function TInfoListPopupUI.OnWndDestroy(hWindow: XCGUI.HWINDOW; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if (FInstanceHwnd <> 0) and (FInstanceHwnd = hWindow) then
  begin
    FInstance := nil;
    FInstanceHwnd := 0;
    FListBoxHele := 0;
  end;
end;

class procedure TInfoListPopupUI.ClearInstanceRefs;
begin
  FInstance := nil;
  FInstanceHwnd := 0;
  FListBoxHele := 0;
end;

class procedure TInfoListPopupUI.RedrawPopup;
begin
  if XC_IsHELE(FListBoxHele) then
    XEle_Redraw(FListBoxHele);
  if Assigned(FInstance) and FInstance.IsHWINDOW then
    FInstance.Redraw;
end;

class procedure TInfoListPopupUI.ClearDisplayList(const ARedraw: Boolean);
begin
  XListBox_DeleteItemAll(FListBoxHele);
  if FDisplayLines <> nil then
    FDisplayLines.Clear;
  if XC_IsHELE(FListBoxHele) then
    XListBox_SetVirtualRowCount(FListBoxHele, 0);
  if ARedraw then
    RedrawPopup;
end;

class procedure TInfoListPopupUI.SetRefreshTimer(const AEnable: Boolean);
begin
  if not Assigned(FInstance) or not FInstance.IsHWINDOW then
    Exit;
  FInstance.KillTimer(CInfoRefreshTimerId);
  if AEnable then
    FInstance.SetTimer(CInfoRefreshTimerId, CInfoRefreshTimerMs);
end;

class function TInfoListPopupUI.OnWndTimer(hWindow: XCGUI.HWINDOW; nIDEvent: UINT; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if nIDEvent = CInfoDeferHoverTimerId then
  begin
    if Assigned(FInstance) and FInstance.IsHWINDOW then
      FInstance.KillTimer(CInfoDeferHoverTimerId);
    RefreshPopup(FDeferFirstShow, FDeferSwitchingTarget);
    Exit;
  end;
  if (nIDEvent = CInfoRefreshTimerId) and FIsVisible then
    NotifyContentChanged;
end;

class procedure TInfoListPopupUI.NotifyContentChanged;
begin
  if FIsVisible then
    RefreshPopup(False, False);
end;

class function TInfoListPopupUI.IsHoverBoundTo(const ATarget: HELE): Boolean;
begin
  Result := FIsVisible and XC_IsHELE(FBoundTargetHandle) and XC_IsHELE(ATarget) and
    (FBoundTargetHandle = ATarget);
end;

class function TInfoListPopupUI.OnWndPaint(hWindow: XCGUI.HWINDOW; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
  nRadius: Integer;
begin
  Result := 0;
  XDraw_EnableSmoothingMode(hDraw, True);
  XWnd_GetClientRect(hWindow, rc);
  nRadius := UITheme_WindowCornerRadius;
  XDraw_SetBrushColor(hDraw, UITheme_SurfaceBase);
  XDraw_FillRoundRect(hDraw, rc, nRadius, nRadius);
  XDraw_SetLineWidth(hDraw, 1);
  XDraw_SetBrushColor(hDraw, UITheme_SurfaceOutline);
  XDraw_DrawRoundRect(hDraw, rc, nRadius, nRadius);
  pbHandled^ := True;
end;

class function TInfoListPopupUI.OnListDrawItem(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; var pItem: TlistBox_item_; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if FDisplayLines = nil then
    Exit;
  if (pItem.index < 0) or (pItem.index >= FDisplayLines.Count) then
    Exit;
  DrawInfoListItem(hDraw, pItem.rcItem, FDisplayLines[pItem.index], FLabelColWidth);
  pbHandled^ := True;
end;

class function TInfoListPopupUI.OnListButtonDown(hEle: XCGUI.HELE; nFlags: UINT; var pPt: TPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
end;

class function TInfoListPopupUI.EnsureInstance(const ATargetHandle: hEle): TInfoListPopupUI;
const
  WS_EX_NOACTIVATE = $08000000;
var
  exStyle: DWORD;
  style: DWORD;
  hOwnerWindow: XCGUI.HWINDOW;
  oldPopup: TInfoListPopupUI;
begin
  hOwnerWindow := 0;
  if ATargetHandle <> 0 then
    hOwnerWindow := XWidget_GetHWINDOW(ATargetHandle);

  if (FInstanceHwnd <> 0) and not XC_IsHWINDOW(FInstanceHwnd) then
    ClearInstanceRefs;

  if Assigned(FInstance) and (FInstanceHwnd <> 0) and FInstance.IsHWINDOW and (FOwnerWindow = hOwnerWindow) then
    Exit(FInstance);

  if Assigned(FInstance) then
  begin
    if FInstance.IsHWINDOW then
    begin
      FInstance.KillTimer(CInfoRefreshTimerId);
      FInstance.KillTimer(CInfoDeferHoverTimerId);
      oldPopup := FInstance;
      ClearInstanceRefs;
      XWnd_DestroyWindow(oldPopup.Handle);
    end
    else
    begin
      FreeAndNil(FInstance);
      ClearInstanceRefs;
    end;
  end;
  FOwnerWindow := hOwnerWindow;

  exStyle := WS_EX_TOPMOST or WS_EX_TRANSPARENT or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE;
  style := WS_POPUP;

  FInstance := TInfoListPopupUI.CreateEx(exStyle, style, nil, 0, 0, 0, 0, '', hOwnerWindow, window_style_nothing);
  if not Assigned(FInstance) or not FInstance.IsHWINDOW then
  begin
    FreeAndNil(FInstance);
    ClearInstanceRefs;
    Exit(nil);
  end;
  FInstanceHwnd := FInstance.Handle;
  FInstance.Init;

  FListBoxHele := XListBox_Create(CInfoShadowExt, CInfoShadowExt, 200, 80, FInstance.Handle);
  XEle_EnableDrawBorder(FListBoxHele, False);
  XEle_EnableBkTransparent(FListBoxHele, True);
  XEle_EnableDrawFocus(FListBoxHele, False);
  XListBox_SetItemHeightDefault(FListBoxHele, CInfoItemHeight, CInfoItemHeight);
  XListBox_SetRowSpace(FListBoxHele, CInfoRowSpace);
  XListBox_EnableMultiSel(FListBoxHele, False);
  XListBox_EnableVirtualTable(FListBoxHele, True);
  XListBox_CreateAdapter(FListBoxHele);
  XListBox_SetVirtualRowCount(FListBoxHele, 0);
  XSView_SetScrollBarSize(FListBoxHele, 0);
  XSView_EnableAutoShowScrollBar(FListBoxHele, False);
  XEle_RegEvent(FListBoxHele, XE_LISTBOX_DRAWITEM, @TInfoListPopupUI.OnListDrawItem);
  XEle_RegEvent(FListBoxHele, XE_LBUTTONDOWN, @TInfoListPopupUI.OnListButtonDown);
  XEle_RegEvent(FListBoxHele, XE_RBUTTONDOWN, @TInfoListPopupUI.OnListButtonDown);

  XWnd_ShowWindow(FInstance.Handle, SW_HIDE);
  Result := FInstance;
end;

class procedure TInfoListPopupUI.RebuildDisplayList(const ABodyText: string);
var
  sl: TStringList;
  i: Integer;
begin
  if FDisplayLines = nil then
    FDisplayLines := TStringList.Create;
  FDisplayLines.Clear;
  if ABodyText <> '' then
  begin
    sl := TStringList.Create;
    try
      sl.Text := ABodyText;
      for i := 0 to sl.Count - 1 do
        if Trim(sl[i]) <> '' then
          FDisplayLines.Add(sl[i]);
    finally
      sl.Free;
    end;
  end;
  if XC_IsHELE(FListBoxHele) then
    XListBox_SetVirtualRowCount(FListBoxHele, FDisplayLines.Count);
end;

class procedure TInfoListPopupUI.ApplyPopupLayout(const AFirstShow, ASwitchingTarget: Boolean);
var
  lineCount, popupW, popupH: Integer;
  listH, listTop: Integer;
  rcWnd: TRect;
begin
  if not Assigned(FInstance) or not FInstance.IsHWINDOW or not XC_IsHELE(FListBoxHele) then
    Exit;

  CalcInfoListPopupMetrics(FDisplayLines, XC_GetDefaultFont(), lineCount, FLabelColWidth, popupW, popupH);
  if lineCount <= 0 then
  begin
    Hide;
    Exit;
  end;

  listTop := CInfoShadowExt + CInfoPadY;
  listH := lineCount * CInfoItemHeight + CInfoPadY;
  CalcInfoListPopupScreenRect(popupW, popupH, rcWnd);
  XWnd_SetRect(FInstance.Handle, rcWnd);
  XEle_SetRectEx(FListBoxHele, CInfoShadowExt, listTop, popupW - CInfoShadowExt * 2, listH, True);
  RedrawPopup;
  if AFirstShow or ASwitchingTarget then
    XWnd_ShowWindow(FInstance.Handle, SW_SHOWNOACTIVATE);
end;

class procedure TInfoListPopupUI.RefreshPopup(const AFirstShow, ASwitchingTarget: Boolean);
var
  bodyText: string;
begin
  if not AFirstShow and not FIsVisible then
    Exit;
  if not XC_IsHELE(FBoundTargetHandle) then
  begin
    Hide;
    Exit;
  end;

  if AFirstShow then
    EnsureInstance(FBoundTargetHandle);

  if FPopupUpdateLock then
  begin
    FRefreshPending := True;
    Exit;
  end;

  FPopupUpdateLock := True;
  try
    if ASwitchingTarget and FIsVisible and Assigned(FInstance) and FInstance.IsHWINDOW then
    begin
      XWnd_ShowWindow(FInstance.Handle, SW_HIDE);
      ClearDisplayList(False);
    end;

    bodyText := GetBoundText;
    if bodyText = '' then
    begin
      if AFirstShow then
        Exit;
      Hide;
      Exit;
    end;

    if (not AFirstShow) and (not ASwitchingTarget) and (bodyText = FLastBodyText) then
      Exit;

    FLastBodyText := bodyText;
    RebuildDisplayList(bodyText);
    ApplyPopupLayout(AFirstShow, ASwitchingTarget);
  finally
    FPopupUpdateLock := False;
    if FRefreshPending then
    begin
      FRefreshPending := False;
      RefreshPopup(False, False);
    end;
  end;
  if AFirstShow then
  begin
    FIsVisible := True;
    SetRefreshTimer(True);
  end;
end;

class function TInfoListPopupUI.OnTargetMouseMove(hEle: XCGUI.HELE; nFlags: Cardinal; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
var
  bindIdx: Integer;
  bindEntry: TInfoListHoverBind;
  firstShow: Boolean;
  switchingTarget: Boolean;
begin
  Result := 0;
  bindIdx := FindBindIndexForEle(hEle);
  if bindIdx < 0 then
    Exit;
  bindEntry := FHoverBinds[bindIdx];
  if not Assigned(bindEntry.GetText) then
    Exit;
  if FPopupUpdateLock then
    Exit;
  if FIsVisible and (FBoundTargetHandle = bindEntry.Target) then
    Exit;
  switchingTarget := FIsVisible;
  FBoundTargetHandle := bindEntry.Target;
  FPopupAbove := bindEntry.PopupAbove;
  FPopupOffsetY := bindEntry.OffsetY;
  firstShow := not FIsVisible;
  if switchingTarget then
    FLastBodyText := '';
  FDeferFirstShow := firstShow;
  FDeferSwitchingTarget := switchingTarget;
  EnsureInstance(bindEntry.Target);
  if Assigned(FInstance) and FInstance.IsHWINDOW then
  begin
    FInstance.KillTimer(CInfoDeferHoverTimerId);
    FInstance.SetTimer(CInfoDeferHoverTimerId, CInfoDeferHoverTimerMs);
  end
  else
    RefreshPopup(firstShow, switchingTarget);
end;

class function TInfoListPopupUI.OnTargetMouseLeave(hEle: XCGUI.HELE; hEleStay: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if IsStayWithinBoundHover(hEleStay) then
    Exit;
  Hide;
end;

class procedure TInfoListPopupUI.BindHover(const ATargetHandle: hEle; const AGetText: TInfoListGetTextFunc; const APopupAbove: Boolean; const AOffsetY: Integer);
var
  bindIdx: Integer;
  entry: TInfoListHoverBind;
begin
  if not XC_IsHELE(ATargetHandle) then
    Exit;
  EnsureHoverBinds;
  bindIdx := FindBindIndex(ATargetHandle);
  if bindIdx < 0 then
  begin
    entry := TInfoListHoverBind.Create;
    FHoverBinds.Add(entry);
  end
  else
    entry := FHoverBinds[bindIdx];
  entry.Target := ATargetHandle;
  entry.GetText := AGetText;
  entry.PopupAbove := APopupAbove;
  entry.OffsetY := AOffsetY;
  if bindIdx < 0 then
  begin
    XEle_RegEvent(ATargetHandle, XE_MOUSEMOVE, @TInfoListPopupUI.OnTargetMouseMove);
    XEle_RegEvent(ATargetHandle, XE_MOUSELEAVE, @TInfoListPopupUI.OnTargetMouseLeave);
  end;
end;

class procedure TInfoListPopupUI.Hide;
begin
  if Assigned(FInstance) and FInstance.IsHWINDOW then
    FInstance.KillTimer(CInfoDeferHoverTimerId);
  SetRefreshTimer(False);
  ClearDisplayList(False);
  if Assigned(FInstance) and FInstance.IsHWINDOW then
    XWnd_ShowWindow(FInstance.Handle, SW_HIDE);
  FIsVisible := False;
  FLastBodyText := '';
end;

initialization
  TInfoListPopupUI.FHoverBinds := nil;
  TInfoListPopupUI.FInstanceHwnd := 0;
  TInfoListPopupUI.FBoundTargetHandle := 0;
  TInfoListPopupUI.FIsVisible := False;
  TInfoListPopupUI.FLastBodyText := '';
  TInfoListPopupUI.FPopupUpdateLock := False;
  TInfoListPopupUI.FRefreshPending := False;
  TInfoListPopupUI.FDeferFirstShow := False;
  TInfoListPopupUI.FDeferSwitchingTarget := False;
  TInfoListPopupUI.FInfoSvgCache := nil;

finalization
  TInfoListPopupUI.FreeSvgCache;
  FreeAndNil(TInfoListPopupUI.FHoverBinds);
  FreeAndNil(TInfoListPopupUI.FDisplayLines);

end.

