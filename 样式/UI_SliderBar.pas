unit UI_SliderBar;

interface

uses
  Windows, XCGUI, UI_Theme;

type
  TSliderBarUI = class
  public
    class procedure ApplyDefault(const ASlider: HELE; AButtonSize: Integer = 14); static;
    class procedure Redraw(const ASlider: HELE); static;
    class procedure SetValueSuffix(const ASlider: HELE; const ASuffix: string); static;
  end;

implementation

uses
  SysUtils, Classes, UI_SliderValuePopup;

const
  cTrackHeight = 4;
  cDefaultButtonSize = 14;

var
  GValueSuffixMap: TStringList;
  GDraggingSlider: HELE;

function SliderBarFromButton(hBtn: HELE): HELE;
var
  hParent: HELE;
begin
  Result := 0;
  hParent := XWidget_GetParentEle(hBtn);
  if XC_GetObjectType(hParent) = XC_SLIDERBAR then
    Result := hParent;
end;

function LookupValueSuffix(const ASlider: HELE): string;
var
  suffixIndex: Integer;
begin
  Result := '';
  if GValueSuffixMap = nil then
    Exit;
  suffixIndex := GValueSuffixMap.IndexOfName(IntToStr(ASlider));
  if suffixIndex >= 0 then
    Result := GValueSuffixMap.ValueFromIndex[suffixIndex];
end;

function FormatSliderValueText(const ASlider: HELE): string;
var
  value: Integer;
begin
  value := XSliderBar_GetPos(ASlider);
  if XC_IsHELE(ASlider) then
    value := value + XEle_GetUserData(ASlider);
  Result := IntToStr(value) + LookupValueSuffix(ASlider);
end;

function OnSliderBtnLButtonDown(hEle: XCGUI.HELE; nFlags: UINT; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
var
  trackEle: Integer;
begin
  Result := 0;
  trackEle := SliderBarFromButton(hEle);
  if not XC_IsHELE(trackEle) then
    Exit;
  GDraggingSlider := trackEle;
  TSliderValuePopupUI.ShowForSlider(trackEle, FormatSliderValueText(trackEle));
end;

function OnSliderBtnMouseStay(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
var
  trackEle: Integer;
begin
  Result := 0;
  if GDraggingSlider <> 0 then
    Exit;
  trackEle := SliderBarFromButton(hEle);
  if not XC_IsHELE(trackEle) then
    Exit;
  TSliderValuePopupUI.ShowForSlider(trackEle, FormatSliderValueText(trackEle));
end;

function OnSliderBtnMouseLeave(hEle: XCGUI.HELE; hEleStay: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if GDraggingSlider <> 0 then
    Exit;
  TSliderValuePopupUI.Hide;
end;

function OnSliderBtnLButtonUp(hEle: XCGUI.HELE; nFlags: UINT; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  GDraggingSlider := 0;
  TSliderValuePopupUI.Hide;
end;

function OnSliderBtnMouseMove(hEle: XCGUI.HELE; nFlags: UINT; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
var
  trackEle: Integer;
begin
  Result := 0;
  trackEle := SliderBarFromButton(hEle);
  if not XC_IsHELE(trackEle) or (GDraggingSlider <> trackEle) then
    Exit;
  TSliderValuePopupUI.UpdateForSlider(trackEle, FormatSliderValueText(trackEle));
end;

function OnSliderBarLButtonDown(hEle: XCGUI.HELE; nFlags: UINT; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if not XC_IsHELE(hEle) then
    Exit;
  GDraggingSlider := hEle;
  TSliderValuePopupUI.ShowForSlider(hEle, FormatSliderValueText(hEle));
end;

function OnSliderBarChange(hEle: XCGUI.HELE; nPos: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if GDraggingSlider <> hEle then
    Exit;
  TSliderValuePopupUI.UpdateForSlider(hEle, FormatSliderValueText(hEle));
end;

function OnSliderBarMouseMove(hEle: XCGUI.HELE; nFlags: UINT; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if (GDraggingSlider <> hEle) or ((nFlags and MK_LBUTTON) = 0) then
    Exit;
  TSliderValuePopupUI.UpdateForSlider(hEle, FormatSliderValueText(hEle));
end;

function OnSliderBarLButtonUp(hEle: XCGUI.HELE; nFlags: UINT; pPt: PPoint; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  if GDraggingSlider = hEle then
  begin
    GDraggingSlider := 0;
    TSliderValuePopupUI.Hide;
  end;
end;

function ClampSliderPos(AValue, AMin, AMax: Integer): Integer;
begin
  if AValue < AMin then
    Result := AMin
  else if AValue > AMax then
    Result := AMax
  else
    Result := AValue;
end;

function CalcTrackRect(const ARc: TRect; ABtnW: Integer; out ARcTrack: TRect): Integer;
var
  trackH, capR, inset: Integer;
begin
  trackH := cTrackHeight;
  if trackH > (ARc.Bottom - ARc.Top) then
    trackH := ARc.Bottom - ARc.Top;
  if trackH <= 0 then
  begin
    FillChar(ARcTrack, SizeOf(ARcTrack), 0);
    Result := 0;
    Exit;
  end;

  ARcTrack := ARc;
  ARcTrack.Top := ARc.Top + ((ARc.Bottom - ARc.Top) - trackH) div 2;
  ARcTrack.Bottom := ARcTrack.Top + trackH;

  inset := ABtnW div 2;
  if inset > 0 then
  begin
    Inc(ARcTrack.Left, inset);
    Dec(ARcTrack.Right, inset);
  end;
  if ARcTrack.Right < ARcTrack.Left then
    ARcTrack.Right := ARcTrack.Left;

  capR := trackH div 2;
  if capR < 1 then
    capR := 1;
  Result := capR;
end;

function CalcFillRight(hSliderEle: HELE; const ARcTrack: TRect; ASliderRange, ASliderPos: Integer): Integer;
var
  btnEle: Integer;
  rcBtn: TRect;
  trackW, fillW: Integer;
begin
  btnEle := XSliderBar_GetButton(hSliderEle);
  if XC_IsHELE(btnEle) then
  begin
    XEle_GetRect(btnEle, rcBtn);
    Result := (rcBtn.Left + rcBtn.Right) div 2;
    if Result < ARcTrack.Left then
      Result := ARcTrack.Left;
    if Result > ARcTrack.Right then
      Result := ARcTrack.Right;
    Exit;
  end;

  if ASliderRange <= 0 then
    ASliderRange := 1;
  trackW := ARcTrack.Right - ARcTrack.Left;
  fillW := MulDiv(trackW, ClampSliderPos(ASliderPos, 0, ASliderRange), ASliderRange);
  Result := ARcTrack.Left + fillW;
end;

function OnSliderBarPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc, rcTrack, rcFill: TRect;
  sliderRange, sliderPos, fillRight, capR, btnW: Integer;
  btnEle: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);

  btnW := cDefaultButtonSize;
  btnEle := XSliderBar_GetButton(hEle);
  if XC_IsHELE(btnEle) then
  begin
    btnW := XEle_GetWidth(btnEle);
    if btnW <= 0 then
      btnW := cDefaultButtonSize;
  end;

  capR := CalcTrackRect(rc, btnW, rcTrack);
  if capR <= 0 then
    Exit;

  XDraw_SetBrushColor(hDraw, UITheme_ProgressBarTrack);
  XDraw_FillRoundRectEx(hDraw, rcTrack, capR, capR, capR, capR);

  sliderRange := XSliderBar_GetRange(hEle);
  sliderPos := XSliderBar_GetPos(hEle);
  fillRight := CalcFillRight(hEle, rcTrack, sliderRange, sliderPos);
  if fillRight > rcTrack.Left then
  begin
    rcFill := rcTrack;
    rcFill.Right := fillRight;
    XDraw_SetBrushColor(hDraw, UITheme_PrimaryColor);
    XDraw_FillRoundRectEx(hDraw, rcFill, capR, capR, capR, capR);
  end;
end;

function OnSliderBtnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  XDraw_SetBrushColor(hDraw, UITheme_PrimaryColor);
  XDraw_FillEllipse(hDraw, rc);
end;

class procedure TSliderBarUI.SetValueSuffix(const ASlider: HELE; const ASuffix: string);
var
  suffixIndex: Integer;
  suffixKey: string;
begin
  if not XC_IsHELE(ASlider) then
    Exit;
  if GValueSuffixMap = nil then
  begin
    GValueSuffixMap := TStringList.Create;
    GValueSuffixMap.NameValueSeparator := '=';
  end;
  suffixKey := IntToStr(ASlider);
  suffixIndex := GValueSuffixMap.IndexOfName(suffixKey);
  if ASuffix = '' then
  begin
    if suffixIndex >= 0 then
      GValueSuffixMap.Delete(suffixIndex);
    Exit;
  end;
  if suffixIndex >= 0 then
    GValueSuffixMap.ValueFromIndex[suffixIndex] := ASuffix
  else
    GValueSuffixMap.Add(suffixKey + '=' + ASuffix);
end;

class procedure TSliderBarUI.ApplyDefault(const ASlider: HELE; AButtonSize: Integer);
var
  btnEle: Integer;
begin
  if not XC_IsHELE(ASlider) then
    Exit;
  XEle_EnableBkTransparent(ASlider, True);
  XEle_EnableDrawFocus(ASlider, False);
  XSliderBar_EnableHorizon(ASlider, True);
  XEle_RegEvent(ASlider, XE_PAINT, @OnSliderBarPaint);
  XEle_RegEvent(ASlider, XE_LBUTTONDOWN, @OnSliderBarLButtonDown);
  XEle_RegEvent(ASlider, XE_LBUTTONUP, @OnSliderBarLButtonUp);
  XEle_RegEvent(ASlider, XE_MOUSEMOVE, @OnSliderBarMouseMove);
  XEle_RegEvent(ASlider, XE_SLIDERBAR_CHANGE, @OnSliderBarChange);
  btnEle := XSliderBar_GetButton(ASlider);
  if XC_IsHELE(btnEle) then
  begin
    XSliderBar_SetButtonWidth(ASlider, AButtonSize);
    XSliderBar_SetButtonHeight(ASlider, AButtonSize);
    XEle_EnableBkTransparent(btnEle, True);
    XEle_SetCursor(btnEle, LoadCursor(0, IDC_HAND));
    XEle_RegEvent(btnEle, XE_PAINT, @OnSliderBtnPaint);
    XEle_RegEvent(btnEle, XE_LBUTTONDOWN, @OnSliderBtnLButtonDown);
    XEle_RegEvent(btnEle, XE_LBUTTONUP, @OnSliderBtnLButtonUp);
    XEle_RegEvent(btnEle, XE_MOUSEMOVE, @OnSliderBtnMouseMove);
    XEle_RegEvent(btnEle, XE_MOUSESTAY, @OnSliderBtnMouseStay);
    XEle_RegEvent(btnEle, XE_MOUSELEAVE, @OnSliderBtnMouseLeave);
  end;
end;

class procedure TSliderBarUI.Redraw(const ASlider: HELE);
var
  btnEle, trackEle: Integer;
begin
  trackEle := ASlider;
  if XC_GetObjectType(trackEle) <> XC_SLIDERBAR then
  begin
    trackEle := XWidget_GetParentEle(ASlider);
    if XC_GetObjectType(trackEle) <> XC_SLIDERBAR then
      trackEle := 0;
  end;
  if not XC_IsHELE(trackEle) then
    Exit;
  XEle_Redraw(trackEle);
  btnEle := XSliderBar_GetButton(trackEle);
  if XC_IsHELE(btnEle) then
    XEle_Redraw(btnEle);
end;

initialization
  GValueSuffixMap := nil;
  GDraggingSlider := 0;

finalization
  FreeAndNil(GValueSuffixMap);

end.
