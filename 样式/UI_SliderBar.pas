unit UI_SliderBar;

interface

uses
  Windows, Math, XCGUI, UI_Theme;

type
  TSliderBarUI = class
  public
    class procedure ApplyDefault(hSlider: HELE; AButtonSize: Integer = 14); static;
  end;

implementation

const
  cTrackHeight = 4;

function OnSliderBarPaint(hEle: HELE; hDraw: HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc, rcTrack, rcFill: TRect;
  range, pos, fillW, trackH, capR: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  trackH := cTrackHeight;
  if trackH > (rc.Bottom - rc.Top) then
    trackH := rc.Bottom - rc.Top;
  if trackH <= 0 then
    Exit;

  rcTrack := rc;
  rcTrack.Top := rc.Top + ((rc.Bottom - rc.Top) - trackH) div 2;
  rcTrack.Bottom := rcTrack.Top + trackH;
  capR := trackH div 2;
  if capR < 1 then
    capR := 1;

  XDraw_SetBrushColor(hDraw, UITheme_ProgressBarTrack);
  XDraw_FillRoundRectEx(hDraw, rcTrack, capR, capR, capR, capR);

  range := XSliderBar_GetRange(hEle);
  if range <= 0 then
    range := 1;
  pos := XSliderBar_GetPos(hEle);
  fillW := MulDiv(rcTrack.Right - rcTrack.Left, EnsureRange(pos, 0, range), range);
  if fillW > 0 then
  begin
    rcFill := rcTrack;
    rcFill.Right := rcFill.Left + fillW;
    XDraw_SetBrushColor(hDraw, UITheme_PrimaryColor);
    XDraw_FillRoundRectEx(hDraw, rcFill, capR, capR, capR, capR);
  end;
end;

function OnSliderBtnPaint(hEle: HELE; hDraw: HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  XDraw_SetBrushColor(hDraw, UITheme_PrimaryColor);
  XDraw_FillEllipse(hDraw, rc);
end;

class procedure TSliderBarUI.ApplyDefault(hSlider: HELE; AButtonSize: Integer);
var
  hBtn: HELE;
begin
  if not XC_IsHELE(hSlider) then
    Exit;
  XEle_EnableBkTransparent(hSlider, True);
  XEle_EnableDrawFocus(hSlider, False);
  XSliderBar_EnableHorizon(hSlider, True);
  XEle_RegEvent(hSlider, XE_PAINT, @OnSliderBarPaint);
  hBtn := XSliderBar_GetButton(hSlider);
  if XC_IsHELE(hBtn) then
  begin
    XSliderBar_SetButtonWidth(hSlider, AButtonSize);
    XSliderBar_SetButtonHeight(hSlider, AButtonSize);
    XEle_EnableBkTransparent(hBtn, True);
    XEle_SetCursor(hBtn, LoadCursor(0, IDC_HAND));
    XEle_RegEvent(hBtn, XE_PAINT, @OnSliderBtnPaint);
  end;
end;

end.
