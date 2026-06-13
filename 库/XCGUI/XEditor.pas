unit XEditor;

interface

uses
  Windows, Classes, SysUtils, XCGUI, XEdit, XScrollView, XWidget;

type
  TXEditor = class(TXEdit)
  protected
    procedure CreateHandle(x, y, cx, cy: Integer; hParent: TXWidget); override;
  public
    procedure EnableConvertChar(bEnable: BOOL);

    function IsBreakpoint(iRow: Integer): BOOL;
    function SetBreakpoint(iRow: Integer; bActivate: BOOL = True): BOOL;
    function GetBreakpointCount: Integer;
    function GetBreakpoints(out out_buffer: Integer; nCount: Integer): Integer;
    function RemoveBreakpoint(iRow: Integer): BOOL;
    procedure ClearBreakpoint;
    function SetRunRow(iRow: Integer): BOOL;

    procedure SetTipsDelay(nDelay: Integer);
    procedure SetAutoMatchSelectModel(model: Integer);
    procedure SetAutoMatchMode(mode: Integer);

    procedure GetColor(out pInfo: Integer);
    procedure SetColor(pInfo: Integer);

    procedure SetCurRow(iRow: Integer);
    function GetDepth(iRow: Integer): Integer;
    function GetDepthEx(iRow: Integer): Integer;
    function ToExpandRow(iRow: Integer): Integer;

    procedure ExpandAll(bExpand: BOOL);
    procedure Expand(iRow: Integer; bExpand: BOOL);
    procedure ExpandSwitch(iRow: Integer);
    procedure ExpandEx(iRow: Integer);

    function GetExpandState: string;
    function SetExpandState(const AState: string): BOOL;

    procedure AddKeyword(const AKey: string; iStyle: Integer);
    procedure AddConst(const AKey: string);
    procedure AddFunction(const AKey: string);
    procedure AddExcludeDefVarKeyword(const AKeyword: string);

    procedure FunArgsExpand_AddArg(const ATypeName, AArgName, AText: string);
    procedure FunArgsExpand_Expand(const AFunName: string; iRow, iCol, iCol2,
      nDepth: Integer);

    function IsEmptyRow(iRow: Integer): BOOL;
  end;

implementation

procedure TXEditor.CreateHandle(x, y, cx, cy: Integer; hParent: TXWidget);
begin
  Handle := XEditor_Create(x, y, cx, cy, hParent.Handle);
end;

procedure TXEditor.EnableConvertChar(bEnable: BOOL);
begin
  XEditor_EnableConvertChar(Handle, bEnable);
end;

function TXEditor.IsBreakpoint(iRow: Integer): BOOL;
begin
  Result := XEditor_IsBreakpoint(Handle, iRow);
end;

function TXEditor.SetBreakpoint(iRow: Integer; bActivate: BOOL): BOOL;
begin
  Result := XEditor_SetBreakpoint(Handle, iRow, bActivate);
end;

function TXEditor.GetBreakpointCount: Integer;
begin
  Result := XEditor_GetBreakpointCount(Handle);
end;

function TXEditor.GetBreakpoints(out out_buffer: Integer;
  nCount: Integer): Integer;
begin
  Result := XEditor_GetBreakpoints(Handle, out_buffer, nCount);
end;

function TXEditor.RemoveBreakpoint(iRow: Integer): BOOL;
begin
  Result := XEditor_RemoveBreakpoint(Handle, iRow);
end;

procedure TXEditor.ClearBreakpoint;
begin
  XEditor_ClearBreakpoint(Handle);
end;

function TXEditor.SetRunRow(iRow: Integer): BOOL;
begin
  Result := XEditor_SetRunRow(Handle, iRow);
end;

procedure TXEditor.SetTipsDelay(nDelay: Integer);
begin
  XEditor_SetTipsDelay(Handle, nDelay);
end;

procedure TXEditor.SetAutoMatchSelectModel(model: Integer);
begin
  XEditor_SetAutoMatchSelectModel(Handle, model);
end;

procedure TXEditor.SetAutoMatchMode(mode: Integer);
begin
  XEditor_SetAutoMatchMode(Handle, mode);
end;

procedure TXEditor.GetColor(out pInfo: Integer);
begin
  XEditor_GetColor(Handle, pInfo);
end;

procedure TXEditor.SetColor(pInfo: Integer);
begin
  XEditor_SetColor(Handle, pInfo);
end;

procedure TXEditor.SetCurRow(iRow: Integer);
begin
  XEditor_SetCurRow(Handle, iRow);
end;

function TXEditor.GetDepth(iRow: Integer): Integer;
begin
  Result := XEditor_GetDepth(Handle, iRow);
end;

function TXEditor.GetDepthEx(iRow: Integer): Integer;
begin
  Result := XEditor_GetDepthEx(Handle, iRow);
end;

function TXEditor.ToExpandRow(iRow: Integer): Integer;
begin
  Result := XEditor_ToExpandRow(Handle, iRow);
end;

procedure TXEditor.ExpandAll(bExpand: BOOL);
begin
  XEditor_ExpandAll(Handle, bExpand);
end;

procedure TXEditor.Expand(iRow: Integer; bExpand: BOOL);
begin
  XEditor_Expand(Handle, iRow, bExpand);
end;

procedure TXEditor.ExpandSwitch(iRow: Integer);
begin
  XEditor_ExpandSwitch(Handle, iRow);
end;

procedure TXEditor.ExpandEx(iRow: Integer);
begin
  XEditor_ExpandEx(Handle, iRow);
end;

function TXEditor.GetExpandState: string;
begin
  Result := string(AnsiString(XEditor_GetExpandState(Handle)));
end;

function TXEditor.SetExpandState(const AState: string): BOOL;
begin
  Result := XEditor_SetExpandState(Handle, PAnsiChar(AnsiString(AState)));
end;

procedure TXEditor.AddKeyword(const AKey: string; iStyle: Integer);
begin
  XEditor_AddKeyword(Handle, PWideChar(AKey), iStyle);
end;

procedure TXEditor.AddConst(const AKey: string);
begin
  XEditor_AddConst(Handle, PWideChar(AKey));
end;

procedure TXEditor.AddFunction(const AKey: string);
begin
  XEditor_AddFunction(Handle, PWideChar(AKey));
end;

procedure TXEditor.AddExcludeDefVarKeyword(const AKeyword: string);
begin
  XEditor_AddExcludeDefVarKeyword(Handle, PWideChar(AKeyword));
end;

procedure TXEditor.FunArgsExpand_AddArg(const ATypeName, AArgName,
  AText: string);
begin
  XEditor_FunArgsExpand_AddArg(Handle, PWideChar(ATypeName), PWideChar(AArgName),
    PWideChar(AText));
end;

procedure TXEditor.FunArgsExpand_Expand(const AFunName: string; iRow, iCol,
  iCol2, nDepth: Integer);
begin
  XEditor_FunArgsExpand_Expand(Handle, PWideChar(AFunName), iRow, iCol, iCol2,
    nDepth);
end;

function TXEditor.IsEmptyRow(iRow: Integer): BOOL;
begin
  Result := XEditor_IsEmptyRow(Handle, iRow);
end;

end.

