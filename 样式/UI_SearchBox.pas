unit UI_SearchBox;

interface

uses
  Windows, SysUtils, XCGUI, UI_Edit, UI_Button;

const
  CDefaultSearchSvg = 'Resource\search.svg';

type
  TSearchBoxInputChangedProc = procedure;

  TSearchBoxUI = record
  private
    FEdit: TEditUI;
    FBtn: TButtonUI;
    class function OnEditKeyDown(hEle: XCGUI.HELE; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnEditChanged(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class procedure AttachSearchButton(var ABox: TSearchBoxUI; const ASvgFile: PWideChar;
      const AIconW, AIconH: Integer); static;
    class var
      FOnInputChanged: TSearchBoxInputChangedProc;
  public
    { 从 XML 绑定编辑框，动态创建内嵌搜索按钮并应用统一样式 }
    class function FromXml(const AEditName: string;
      const ASvgFile: PWideChar = nil;
      const AIconW: Integer = 16; const AIconH: Integer = 16;
      const ABtnRightInset: Integer = 36): TSearchBoxUI; static;
    function GetTrimmedText: string;
    procedure RegOnSearchClick(pfn: Pointer);
    procedure RegOnSearchInputChanged(pfn: Pointer);
    property Edit: TEditUI read FEdit;
    property Button: TButtonUI read FBtn;
  end;

implementation

class procedure TSearchBoxUI.AttachSearchButton(var ABox: TSearchBoxUI; const ASvgFile: PWideChar;
  const AIconW, AIconH: Integer);
var
  editW, editH, btnSize, btnX, btnY: Integer;
begin
  ABox.FEdit.GetSize(editW, editH);
  btnSize := AIconW + 10;
  if AIconH + 10 > btnSize then
    btnSize := AIconH + 10;
  btnX := editW - btnSize - 4;
  if btnX < 0 then
    btnX := 0;
  btnY := (editH - btnSize) div 2;
  if btnY < 0 then
    btnY := 0;
  ABox.FBtn := TButtonUI.FormHandle(
    XBtn_Create(btnX, btnY, btnSize, btnSize, nil, ABox.FEdit.Handle),
    BB_NONE, ASvgFile, AIconW, AIconH);
  ABox.FBtn.SetLockScroll(True, True);
end;

class function TSearchBoxUI.FromXml(const AEditName: string;
  const ASvgFile: PWideChar; const AIconW, AIconH, ABtnRightInset: Integer): TSearchBoxUI;
var
  svg: PWideChar;
begin
  svg := ASvgFile;
  if svg = nil then
    svg := CDefaultSearchSvg;
  Result.FEdit := TEditUI.FromXmlName(AEditName);
  Result.FEdit.SetBorderSize(1, 1, ABtnRightInset, 1);
  AttachSearchButton(Result, svg, AIconW, AIconH);
  XEle_SetUserData(Result.FEdit.Handle, NativeInt(Result.FBtn.Handle));
end;

class function TSearchBoxUI.OnEditChanged(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  if Assigned(FOnInputChanged) then
    FOnInputChanged();
end;

class function TSearchBoxUI.OnEditKeyDown(hEle: XCGUI.HELE; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
var
  hBtn: XCGUI.HELE;
begin
  Result := 0;
  case wParam of
    VK_RETURN, VK_SEPARATOR:
      if (lParam and $40000000) = 0 then
      begin
        pbHandled^ := True;
        hBtn := XCGUI.HELE(XEle_GetUserData(hEle));
        XEle_SendEvent(hBtn, XE_BNCLICK, 0, 0);
      end;
  end;
end;

function TSearchBoxUI.GetTrimmedText: string;
begin
  Result := Trim(FEdit.GetText_Temp);
end;

procedure TSearchBoxUI.RegOnSearchClick(pfn: Pointer);
begin
  FBtn.RegEvent(XE_BNCLICK, pfn);
  FEdit.RegEvent(XE_KEYDOWN, @TSearchBoxUI.OnEditKeyDown);
  FEdit.RegEvent(XE_EDIT_CHANGED, @TSearchBoxUI.OnEditChanged);
end;

procedure TSearchBoxUI.RegOnSearchInputChanged(pfn: Pointer);
begin
  FOnInputChanged := TSearchBoxInputChangedProc(pfn);
end;

end.
