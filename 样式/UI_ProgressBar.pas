unit UI_ProgressBar;

interface

uses
  Windows, Math, XCGUI, UI_Theme;

type
  TProgressBarUI = class
  public
    { 应用默认圆角进度条样式；AFillColor=0 时使用 UITheme_ProgressBarFill }
    class procedure ApplyDefault(hProg: HELE; AFillColor: Integer = 0); static;
  end;

implementation

function OnProgressBarPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  rc, rcFill: TRect;
  range, pos, fillW, barW, barH, r, capR, minFillW: Integer;
begin
  Result := 0;
  pbHandled^ := True;
  XEle_GetClientRect(hEle, rc);
  r := UITheme_ProgressBarCornerRadius;
  barH := rc.Bottom - rc.Top;
  capR := r;
  if barH > 0 then
    capR := Min(capR, barH div 2);
  minFillW := capR * 2;

  XDraw_SetBrushColor(hDraw, UITheme_ProgressBarTrack);
  XDraw_FillRoundRectEx(hDraw, rc, r, r, r, r);

  range := XProgBar_GetRange(hEle);
  pos := XProgBar_GetPos(hEle);
  if range <= 0 then
    range := 100;
  barW := rc.Right - rc.Left;
  fillW := MulDiv(barW, EnsureRange(pos, 0, range), range);
  if (minFillW > 0) and (fillW < minFillW) then
    fillW := minFillW;
  if fillW > 0 then
  begin
    rcFill := rc;
    rcFill.Right := rcFill.Left + fillW;
    if XEle_GetUserData(hEle) <> 0 then
      XDraw_SetBrushColor(hDraw, XEle_GetUserData(hEle))
    else
      XDraw_SetBrushColor(hDraw, UITheme_ProgressBarFill);
    XDraw_FillRoundRectEx(hDraw, rcFill, capR, capR, capR, capR);
  end;
end;

class procedure TProgressBarUI.ApplyDefault(hProg: HELE; AFillColor: Integer);
var
  fillColor: Integer;
begin
  if hProg = 0 then
    Exit;
  fillColor := AFillColor;
  if fillColor = 0 then
    fillColor := UITheme_ProgressBarFill;
  XEle_SetUserData(hProg, fillColor);
  XProgBar_SetRange(hProg, 100);
  XProgBar_EnableHorizon(hProg, True);
  XProgBar_EnableShowText(hProg, False);
  XEle_EnableBkTransparent(hProg, True);
  XEle_EnableDrawBorder(hProg, False);
  XEle_EnableDrawFocus(hProg, False);
  XEle_SetSize(hProg, UITheme_ProgressBarWidth, UITheme_ProgressBarHeight, False, adjustLayout_no);
  XEle_RegEvent(hProg, XE_PAINT, @OnProgressBarPaint);
end;

end.
