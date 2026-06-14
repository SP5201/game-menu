unit UI_Ele;

interface

uses
  Windows, XCGUI, XElement;

procedure DrawRoundedElement(hDraw: XCGUI.HDRAW; rc: TRect; const CornerRadius: Integer;
  const EnableBkColor: Boolean; const BkColor: Integer; const EnableBorder: Boolean;
  const BorderColor: Integer);

type
  TEleUI = class(TXEle)
  private
    FCornerRadius: Integer;
    FEnableBorder: Boolean;
    FEnableBkColor: Boolean;
    FBkColor: Integer;
    FBorderColor: Integer;
    procedure SetCornerRadius(const Value: Integer);
    procedure SetEnableBorder(const Value: Boolean);
    procedure SetEnableBkColor(const Value: Boolean);
    procedure SetBkColor(const Value: Integer);
    procedure SetBorderColor(const Value: Integer);
  protected
    procedure Init; override;
  public
    class function OnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    property CornerRadius: Integer read FCornerRadius write SetCornerRadius;
    property EnableBorder: Boolean read FEnableBorder write SetEnableBorder;
    property EnableBkColor: Boolean read FEnableBkColor write SetEnableBkColor;
    property BkColor: Integer read FBkColor write SetBkColor;
    property BorderColor: Integer read FBorderColor write SetBorderColor;
  end;

implementation

uses
  UI_Theme;

procedure DrawRoundedElement(hDraw: XCGUI.HDRAW; rc: TRect; const CornerRadius: Integer;
  const EnableBkColor: Boolean; const BkColor: Integer; const EnableBorder: Boolean;
  const BorderColor: Integer);
begin
  if EnableBkColor then
  begin
    XDraw_SetBrushColor(hDraw, BkColor);
    XDraw_FillRoundRect(hDraw, rc, CornerRadius, CornerRadius);
  end;

  if EnableBorder then
  begin
    XDraw_SetLineWidth(hDraw, 1);
    XDraw_SetBrushColor(hDraw, BorderColor);
    XDraw_DrawRoundRect(hDraw, rc, CornerRadius, CornerRadius);
  end;
end;

procedure TEleUI.Init;
begin
  inherited;
  FEnableBorder := False;
  FEnableBkColor := False;
  FBkColor := UITheme_SurfaceBase;
  FBorderColor := UITheme_SurfaceOutline;
  FCornerRadius := UITheme_WindowCornerRadius;
  FocusBorderColor := UITheme_SurfaceOutline;
  RegEvent(XE_PAINT, @TEleUI.OnPaint);
end;

procedure TEleUI.SetCornerRadius(const Value: Integer);
begin
  if Value < 0 then
    FCornerRadius := 0
  else
    FCornerRadius := Value;
end;

procedure TEleUI.SetEnableBorder(const Value: Boolean);
begin
  FEnableBorder := Value;
end;

procedure TEleUI.SetEnableBkColor(const Value: Boolean);
begin
  FEnableBkColor := Value;
end;

procedure TEleUI.SetBkColor(const Value: Integer);
begin
  FBkColor := Value;
end;

procedure TEleUI.SetBorderColor(const Value: Integer);
begin
  FBorderColor := Value;
end;

class function TEleUI.OnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  pEleUI: TEleUI;
  rc: TRect;
begin
  Result := 0;
  pbHandled^ := True;

  pEleUI := TEleUI.FromHandle(hEle);
  XEle_GetClientRect(hEle, rc);

  DrawRoundedElement(
    hDraw,
    rc,
    pEleUI.CornerRadius,
    pEleUI.FEnableBkColor,
    pEleUI.FBkColor,
    pEleUI.FEnableBorder,
    pEleUI.FBorderColor
  );
end;

end.

