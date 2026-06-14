unit UI_Edit;

interface

uses
  Windows, XCGUI, XEdit, XElement;

type
  TEditUI = class(TXEdit)
  private
    FCornerRadius: Integer;
    FEnableBorder: Boolean;
    FEnableBkColor: Boolean;
    FEnableFocusBkColor: Boolean;
    FBkColor: Integer;
    FFocusBkColor: Integer;
    FBorderColor: Integer;
    class function OnInputFocusChanged(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall; static;
    procedure SetCornerRadius(const Value: Integer);
    procedure SetEnableBorder(const Value: Boolean);
    procedure SetEnableBkColor(const Value: Boolean);
    procedure SetEnableFocusBkColor(const Value: Boolean);
    procedure SetBkColor(const Value: Integer);
    procedure SetFocusBkColor(const Value: Integer);
    procedure SetBorderColor(const Value: Integer);
  protected
    procedure Init; override;
  public
    class function FromXmlName(const XmlName: string): TEditUI; reintroduce;
    class procedure ApplyInputElementBaseStyle(const hInputEle: XCGUI.HELE); static;
    class procedure ApplyEditStyle(const EditUI: TEditUI); static;
    property CornerRadius: Integer read FCornerRadius write SetCornerRadius;
    property EnableBorder: Boolean read FEnableBorder write SetEnableBorder;
    property EnableBkColor: Boolean read FEnableBkColor write SetEnableBkColor;
    property EnableFocusBkColor: Boolean read FEnableFocusBkColor write SetEnableFocusBkColor;
    property BkColor: Integer read FBkColor write SetBkColor;
    property FocusBkColor: Integer read FFocusBkColor write SetFocusBkColor;
    property BorderColor: Integer read FBorderColor write SetBorderColor;
  end;

implementation

uses
  UI_Ele, UI_Theme, UI_ScrollBar;

class procedure TEditUI.ApplyEditStyle(const EditUI: TEditUI);
begin
  TEditUI.ApplyInputElementBaseStyle(EditUI.Handle);
  EditUI.RegEvent(XE_PAINT, @TEditUI.OnPaint);
  EditUI.EnableBkColor := True;
  EditUI.BkColor := UITheme_SurfaceBase;
  EditUI.EnableBorder := True;
  EditUI.CornerRadius := 4;
  EditUI.SetBorderSize(0,0,4,0);
  EditUI.BkColor := UITheme_InputSurface;
  EditUI.FocusBkColor := UITheme_InputSurfaceFocus;
  EditUI.BorderColor := UITheme_InputBorder;
  XEdit_SetDefaultTextColor(EditUI.Handle, UITheme_TextPlaceholder);
  XEdit_SetCaretColor(EditUI.Handle, UITheme_InputCaret);
  XEdit_SetSelectBkColor(EditUI.Handle, UITheme_InputSelection);
  TScrollBarUI.ApplyDefault(EditUI.Handle);
  TScrollBarUI.ApplyDefaultH(EditUI.Handle);
end;

class procedure TEditUI.ApplyInputElementBaseStyle(const hInputEle: XCGUI.HELE);
var
  InputEle: TEleUI;
begin
  InputEle := TEleUI.FromHandle(hInputEle);
  InputEle.EnableDrawFocus(False);
  InputEle.EnableBkTransparent(True);
  InputEle.EnableDrawBorder(False);
  InputEle.SetBorderSize(2, 1, 2, 1);
  InputEle.FocusBorderColor := UITheme_InputBorder;
  InputEle.TextColor := UITheme_InputText;
  InputEle.RegEvent(XE_SETFOCUS, @TEditUI.OnInputFocusChanged);
  InputEle.RegEvent(XE_KILLFOCUS, @TEditUI.OnInputFocusChanged);
end;

class function TEditUI.FromXmlName(const XmlName: string): TEditUI;
begin
  Result := TEditUI(inherited FromXmlName(XmlName));
end;

procedure TEditUI.Init;
begin
  inherited;
  TEditUI.ApplyEditStyle(Self);
end;

class function TEditUI.OnPaint(hEle: XCGUI.HELE; hDraw: XCGUI.HDRAW; pbHandled: PBOOL): Integer; stdcall;
var
  pEditUI: TEditUI;
  rc: TRect;
  drawBorder: Boolean;
  borderColor: Integer;
  bkColor: Integer;
  focused: Boolean;
begin
  Result := 0;
  pEditUI := TEditUI.FromHandle(hEle);
  XEle_GetClientRect(hEle, rc);
  focused := pEditUI.IsFocus or pEditUI.IsFocusEx;

  drawBorder := pEditUI.FEnableBorder;
  borderColor := pEditUI.FBorderColor;
  bkColor := pEditUI.FBkColor;
  if focused then
  begin
    if pEditUI.FEnableBorder then
    begin
      drawBorder := True;
      borderColor := pEditUI.FocusBorderColor;
    end;
    if pEditUI.FEnableFocusBkColor then
      bkColor := pEditUI.FFocusBkColor;
  end;

  DrawRoundedElement(
    hDraw,
    rc,
    pEditUI.FCornerRadius,
    pEditUI.FEnableBkColor or (focused and pEditUI.FEnableFocusBkColor),
    bkColor,
    drawBorder,
    borderColor
  );
end;

class function TEditUI.OnInputFocusChanged(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  TEditUI(TXEle.FromHandle(hEle)).Redraw(False);
end;

procedure TEditUI.SetCornerRadius(const Value: Integer);
begin
  if Value < 0 then
    FCornerRadius := 0
  else
    FCornerRadius := Value;
end;

procedure TEditUI.SetEnableBorder(const Value: Boolean);
begin
  FEnableBorder := Value;
  if FEnableBorder then
    SetBorderSize(1, 1, 1, 1)
  else
    SetBorderSize(0, 0, 0, 0);
end;

procedure TEditUI.SetEnableBkColor(const Value: Boolean);
begin
  FEnableBkColor := Value;
end;

procedure TEditUI.SetEnableFocusBkColor(const Value: Boolean);
begin
  FEnableFocusBkColor := Value;
  Redraw(False);
end;

procedure TEditUI.SetBkColor(const Value: Integer);
begin
  FBkColor := Value;
end;

procedure TEditUI.SetFocusBkColor(const Value: Integer);
begin
  FFocusBkColor := Value;
  FEnableFocusBkColor := True;
  Redraw(False);
end;

procedure TEditUI.SetBorderColor(const Value: Integer);
begin
  FBorderColor := Value;
end;

end.
