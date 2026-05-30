unit XAdTable;

interface

uses
  Windows, XCGUI;

type
  TXAdTable = class
  private
    FHandle: HXCGUI;
  public
    constructor Create; overload;
    constructor CreateFromHandle(hAdapter: HXCGUI); overload;
    property Handle: HXCGUI read FHandle;

    procedure Sort(iColumn: Integer; bAscending: BOOL);

    function AddColumn(pName: PWideChar): Integer;
    function SetColumn(pColName: PWideChar): Integer;

    function AddItemText(pValue: PWideChar): Integer;
    function AddItemTextEx(pName, pValue: PWideChar): Integer;
    function AddItemImage(hImage: HIMAGE): Integer;
    function AddItemImageEx(pName: PWideChar; hImage: HIMAGE): Integer;

    function AddRowText(pValue: PWideChar): Integer;
    function AddRowTextEx(pName, pValue: PWideChar): Integer;
    function AddRowImage(hImage: HIMAGE): Integer;

    function InsertItemText(iItem: Integer; pValue: PWideChar): Integer;
    function InsertItemTextEx(iItem: Integer; pName, pValue: PWideChar): Integer;
    function InsertItemImage(iItem: Integer; hImage: HIMAGE): Integer;
    function InsertItemImageEx(iItem: Integer; pName: PWideChar; hImage: HIMAGE): Integer;

    function SetItemText(iItem, iColumn: Integer; pValue: PWideChar): BOOL;
    function SetItemTextEx(iItem: Integer; pName, pValue: PWideChar): BOOL;
    function SetItemInt(iItem, iColumn: Integer; nValue: Integer): BOOL;
    function SetItemIntEx(iItem: Integer; pName: PWideChar; nValue: Integer): BOOL;
    function SetItemFloat(iItem, iColumn: Integer; nValue: Single): BOOL;
    function SetItemFloatEx(iItem: Integer; pName: PWideChar; nValue: Single): BOOL;
    function SetItemImage(iItem, iColumn: Integer; hImage: HIMAGE): BOOL;
    function SetItemImageEx(iItem: Integer; pName: PWideChar; hImage: HIMAGE): BOOL;

    function GetItemText(iItem, iColumn: Integer): PWideChar;
    function GetItemTextEx(iItem: Integer; pName: PWideChar): PWideChar;
    function GetItemImage(iItem, iColumn: Integer): HIMAGE;
    function GetItemImageEx(iItem: Integer; pName: PWideChar): HIMAGE;

    function GetItemInt(iItem, iColumn: Integer; out pOutValue: Integer): BOOL;
    function GetItemIntEx(iItem: Integer; pName: PWideChar; out pOutValue: Integer): BOOL;
    function GetItemFloat(iItem, iColumn: Integer; out pOutValue: Single): BOOL;
    function GetItemFloatEx(iItem: Integer; pName: PWideChar; out pOutValue: Single): BOOL;

    function GetCount: Integer;
    function GetCountColumn: Integer;

    function DeleteItem(iItem: Integer): BOOL;
    function DeleteItemEx(iItem, nCount: Integer): BOOL;
    procedure DeleteItemAll;
    procedure DeleteColumnAll;
  end;

implementation

constructor TXAdTable.Create;
begin
  inherited Create;
  FHandle := XAdTable_Create();
end;

constructor TXAdTable.CreateFromHandle(hAdapter: HXCGUI);
begin
  inherited Create;
  FHandle := hAdapter;
end;

procedure TXAdTable.Sort(iColumn: Integer; bAscending: BOOL);
begin
  XAdTable_Sort(FHandle, iColumn, bAscending);
end;

function TXAdTable.AddColumn(pName: PWideChar): Integer;
begin
  Result := XAdTable_AddColumn(FHandle, pName);
end;

function TXAdTable.SetColumn(pColName: PWideChar): Integer;
begin
  Result := XAdTable_SetColumn(FHandle, pColName);
end;

function TXAdTable.AddItemText(pValue: PWideChar): Integer;
begin
  Result := XAdTable_AddItemText(FHandle, pValue);
end;

function TXAdTable.AddItemTextEx(pName, pValue: PWideChar): Integer;
begin
  Result := XAdTable_AddItemTextEx(FHandle, pName, pValue);
end;

function TXAdTable.AddItemImage(hImage: HIMAGE): Integer;
begin
  Result := XAdTable_AddItemImage(FHandle, hImage);
end;

function TXAdTable.AddItemImageEx(pName: PWideChar; hImage: HIMAGE): Integer;
begin
  Result := XAdTable_AddItemImageEx(FHandle, pName, hImage);
end;

function TXAdTable.AddRowText(pValue: PWideChar): Integer;
begin
  Result := XAdTable_AddRowText(FHandle, pValue);
end;

function TXAdTable.AddRowTextEx(pName, pValue: PWideChar): Integer;
begin
  Result := XAdTable_AddRowTextEx(FHandle, pName, pValue);
end;

function TXAdTable.AddRowImage(hImage: HIMAGE): Integer;
begin
  Result := XAdTable_AddRowImage(FHandle, hImage);
end;

function TXAdTable.InsertItemText(iItem: Integer; pValue: PWideChar): Integer;
begin
  Result := XAdTable_InsertItemText(FHandle, iItem, pValue);
end;

function TXAdTable.InsertItemTextEx(iItem: Integer; pName, pValue: PWideChar): Integer;
begin
  Result := XAdTable_InsertItemTextEx(FHandle, iItem, pName, pValue);
end;

function TXAdTable.InsertItemImage(iItem: Integer; hImage: HIMAGE): Integer;
begin
  Result := XAdTable_InsertItemImage(FHandle, iItem, hImage);
end;

function TXAdTable.InsertItemImageEx(iItem: Integer; pName: PWideChar; hImage: HIMAGE): Integer;
begin
  Result := XAdTable_InsertItemImageEx(FHandle, iItem, pName, hImage);
end;

function TXAdTable.SetItemText(iItem, iColumn: Integer; pValue: PWideChar): BOOL;
begin
  Result := XAdTable_SetItemText(FHandle, iItem, iColumn, pValue);
end;

function TXAdTable.SetItemTextEx(iItem: Integer; pName, pValue: PWideChar): BOOL;
begin
  Result := XAdTable_SetItemTextEx(FHandle, iItem, pName, pValue);
end;

function TXAdTable.SetItemInt(iItem, iColumn: Integer; nValue: Integer): BOOL;
begin
  Result := XAdTable_SetItemInt(FHandle, iItem, iColumn, nValue);
end;

function TXAdTable.SetItemIntEx(iItem: Integer; pName: PWideChar; nValue: Integer): BOOL;
begin
  Result := XAdTable_SetItemIntEx(FHandle, iItem, pName, nValue);
end;

function TXAdTable.SetItemFloat(iItem, iColumn: Integer; nValue: Single): BOOL;
begin
  Result := XAdTable_SetItemFloat(FHandle, iItem, iColumn, nValue);
end;

function TXAdTable.SetItemFloatEx(iItem: Integer; pName: PWideChar; nValue: Single): BOOL;
begin
  Result := XAdTable_SetItemFloatEx(FHandle, iItem, pName, nValue);
end;

function TXAdTable.SetItemImage(iItem, iColumn: Integer; hImage: HIMAGE): BOOL;
begin
  Result := XAdTable_SetItemImage(FHandle, iItem, iColumn, hImage);
end;

function TXAdTable.SetItemImageEx(iItem: Integer; pName: PWideChar; hImage: HIMAGE): BOOL;
begin
  Result := XAdTable_SetItemImageEx(FHandle, iItem, pName, hImage);
end;

function TXAdTable.GetItemText(iItem, iColumn: Integer): PWideChar;
begin
  Result := XAdTable_GetItemText(FHandle, iItem, iColumn);
end;

function TXAdTable.GetItemTextEx(iItem: Integer; pName: PWideChar): PWideChar;
begin
  Result := XAdTable_GetItemTextEx(FHandle, iItem, pName);
end;

function TXAdTable.GetItemImage(iItem, iColumn: Integer): HIMAGE;
begin
  Result := XAdTable_GetItemImage(FHandle, iItem, iColumn);
end;

function TXAdTable.GetItemImageEx(iItem: Integer; pName: PWideChar): HIMAGE;
begin
  Result := XAdTable_GetItemImageEx(FHandle, iItem, pName);
end;

function TXAdTable.GetItemInt(iItem, iColumn: Integer; out pOutValue: Integer): BOOL;
begin
  Result := XAdTable_GetItemInt(FHandle, iItem, iColumn, pOutValue);
end;

function TXAdTable.GetItemIntEx(iItem: Integer; pName: PWideChar; out pOutValue: Integer): BOOL;
begin
  Result := XAdTable_GetItemIntEx(FHandle, iItem, pName, pOutValue);
end;

function TXAdTable.GetItemFloat(iItem, iColumn: Integer; out pOutValue: Single): BOOL;
begin
  Result := XAdTable_GetItemFloat(FHandle, iItem, iColumn, pOutValue);
end;

function TXAdTable.GetItemFloatEx(iItem: Integer; pName: PWideChar; out pOutValue: Single): BOOL;
begin
  Result := XAdTable_GetItemFloatEx(FHandle, iItem, pName, pOutValue);
end;

function TXAdTable.GetCount: Integer;
begin
  Result := XAdTable_GetCount(FHandle);
end;

function TXAdTable.GetCountColumn: Integer;
begin
  Result := XAdTable_GetCountColumn(FHandle);
end;

function TXAdTable.DeleteItem(iItem: Integer): BOOL;
begin
  Result := XAdTable_DeleteItem(FHandle, iItem);
end;

function TXAdTable.DeleteItemEx(iItem, nCount: Integer): BOOL;
begin
  Result := XAdTable_DeleteItemEx(FHandle, iItem, nCount);
end;

procedure TXAdTable.DeleteItemAll;
begin
  XAdTable_DeleteItemAll(FHandle);
end;

procedure TXAdTable.DeleteColumnAll;
begin
  XAdTable_DeleteColumnAll(FHandle);
end;

end.

