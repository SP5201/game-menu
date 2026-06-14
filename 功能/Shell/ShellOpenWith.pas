unit ShellOpenWith;

interface

uses
  Windows, SysUtils, ShellAPI, XCGUI, XMenu;

type
  TOpenWithStringArray = array of string;

const
  /// <summary>右键「打开方式」父项 ID（与 ListView 主菜单其它 ID 错开）。</summary>
  cShellOpenWithMenuParent = 2000;
  cShellOpenWithMenuFirstHandler = 2001;
  cShellOpenWithMenuLastHandler = 2015; // 稍微扩大容量以容纳默认程序
  cShellOpenWithMenuChooseApp = 2099;

procedure ShellOpenWithEnum(const FilePath: UnicodeString;
  var ExePaths, DisplayNames: TOpenWithStringArray);

/// <summary>在 xcgui 弹出菜单上追加「打开方式」子项，完美还原 Windows 原生效果（带图标、默认程序和分割线）</summary>
procedure ShellOpenWithAppendContextMenuItems(Menu: TXMenu; const FilePath: UnicodeString);

/// <summary>处理 ListView 右键菜单中与「打开方式」相关的命令 ID。</summary>
function ShellOpenWithHandleMenuCommand(nMenuId: Integer; hwndOwner: Windows.HWND): Boolean;

function ShellOpenWithShowDialog(hwndOwner: Windows.HWND; const FilePath: UnicodeString): Boolean;

function ShellOpenWithHandlerImageFromExe(const ExePath: UnicodeString): HIMAGE;

function ShellOpenWithInvokeExe(const ExePath, FilePath: UnicodeString): Boolean;

procedure ShellOpenWithResetMenuState;

implementation

uses
  ActiveX,
  Classes,
  Registry;

type
  PHICON = ^HICON;

const
  cRegFileExtsBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\';
  cRegClassRootApplications = 'Applications\';
  cRegOpenWithProgids = '\OpenWithProgids';
  cRegOpenWithList = '\OpenWithList';
  cRegShellOpenCommand = '\shell\open\command';
  cRegFriendlyAppName = 'FriendlyAppName';
  ASSOCF_OPEN_BYEXENAME = $00000002;
  ASSOCSTR_FRIENDLYAPPNAME = 4;
  ASSOCSTR_COMMAND = 1; // 用于获取默认打开命令行
  ASSOC_FILTER_NONE = 0;
  ASSOC_FILTER_RECOMMENDED = 1;

type
  IAssocHandler = interface(IUnknown)
    ['{973810AE-9599-4B88-9E4D-6EE98C9552DA}']
    function GetName(out ppsz: PWideChar): HRESULT; stdcall;
    function GetUIName(out ppsz: PWideChar): HRESULT; stdcall;
    function GetIconLocation(out ppszPath: PWideChar; out pIndex: Integer): HRESULT; stdcall;
    function IsRecommended: HRESULT; stdcall;
    function MakeDefault(pszDescription: PWideChar): HRESULT; stdcall;
    function Invoke(pdo: IDataObject): HRESULT; stdcall;
    function CreateInvoker(pdo: IDataObject; out ppInvoker: IUnknown): HRESULT; stdcall;
  end;

  IEnumAssocHandlers = interface(IUnknown)
    ['{31C3E7FC-7B5A-48E0-93B2-10ED2BFEF9B1}']
    function Next(celt: ULONG; out rgelt: IAssocHandler; out pceltFetched: ULONG): HRESULT; stdcall;
    function Reset: HRESULT; stdcall;
    function Clone(out ppEnum: IEnumAssocHandlers): HRESULT; stdcall;
  end;

function PathRemoveArgsW(pszPath: PWideChar): BOOL; stdcall; external 'Shlwapi.dll' name 'PathRemoveArgsW';
function AssocQueryStringW(flags: DWORD; str: DWORD; pszAssoc, pszExtra, pszOut: PWideChar;
  var pcchOut: DWORD): HRESULT; stdcall; external 'Shlwapi.dll' name 'AssocQueryStringW';
function SHLoadIndirectString(pszSource: PWideChar; pszOutBuf: PWideChar; cchOutBuf: UINT;
  ppvReserved: Pointer): HRESULT; stdcall; external 'shlwapi.dll' name 'SHLoadIndirectString';
function SHAssocEnumHandlers(pszExtra: PWideChar; afFilter: DWORD; out ppEnumHandler: IEnumAssocHandlers): HRESULT; stdcall;
  external 'shell32.dll' name 'SHAssocEnumHandlers';

function ExtractIconExW(lpszFile: PWideChar; nIconIndex: Integer; phiconLarge: PHICON;
  phiconSmall: PHICON; nIcons: UINT): UINT; stdcall; external 'shell32.dll' name 'ExtractIconExW';

type
  OPEN_AS_INFO_FLAGS = DWORD;

const
  OAIF_ALLOW_REGISTRATION = $00000001;
  OAIF_EXEC = $00000004;

type
  TOPENASINFO = record
    pcszFile: LPCWSTR;
    pcszClass: LPCWSTR;
    oaifInFlags: OPEN_AS_INFO_FLAGS;
  end;
  POPENASINFO = ^TOPENASINFO;

function SHOpenWithDialog(hwnd: Windows.HWND; poainfo: POPENASINFO): HRESULT; stdcall;
  external 'shell32.dll' name 'SHOpenWithDialog';

var
  GShellOpenWithMenuFile: UnicodeString;
  GShellOpenWithMenuExes: TOpenWithStringArray;

function ExpandEnvPathW(const s: UnicodeString): UnicodeString;
var
  buf: array[0..4095] of WideChar;
  n: DWORD;
begin
  if s = '' then
    Exit('');
  n := ExpandEnvironmentStringsW(PWideChar(s), buf, Length(buf));
  if (n = 0) or (n > DWORD(Length(buf))) then
    Result := s
  else
    Result := Trim(WideString(PWideChar(@buf[0])));
end;

function ExpandIndirectString(const s: UnicodeString): UnicodeString;
var
  buf: array[0..1023] of WideChar;
begin
  Result := Trim(s);
  if (Result = '') or (Result[1] <> '@') then
    Exit;
  if SHLoadIndirectString(PWideChar(Result), @buf[0], Length(buf), nil) <> S_OK then
    Exit;
  Result := Trim(WideString(PWideChar(@buf[0])));
end;

function CommandLineToExePath(const cmd: UnicodeString): UnicodeString;
var
  buf: array[0..8191] of WideChar;
  n: Integer;
begin
  Result := '';
  if cmd = '' then
    Exit;
  n := Length(cmd);
  if n > Length(buf) - 2 then
    n := Length(buf) - 2;
  CopyMemory(@buf[0], PWideChar(cmd), n * SizeOf(WideChar));
  buf[n] := #0;
  PathRemoveArgsW(@buf[0]);
  Result := Trim(WideString(PWideChar(@buf[0])));
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
  Result := Trim(ExpandEnvPathW(Result));
end;

function QueryFriendlyAppNameByExeName(const AppExeName: UnicodeString): UnicodeString;
var
  cch: DWORD;
  buf: array of WideChar;
begin
  Result := '';
  if Trim(AppExeName) = '' then
    Exit;
  cch := 0;
  AssocQueryStringW(ASSOCF_OPEN_BYEXENAME, ASSOCSTR_FRIENDLYAPPNAME,
    PWideChar(AppExeName), nil, nil, cch);
  if cch <= 1 then
    Exit;
  SetLength(buf, cch + 1);
  if AssocQueryStringW(ASSOCF_OPEN_BYEXENAME, ASSOCSTR_FRIENDLYAPPNAME,
    PWideChar(AppExeName), nil, PWideChar(@buf[0]), cch) = S_OK then
    Result := Trim(WideString(PWideChar(@buf[0])));
  Result := ExpandIndirectString(Result);
end;

function QueryFriendlyAppNameFromRegistry(const AppExeName: UnicodeString): UnicodeString;
var
  reg: TRegistry;
  keyPath: UnicodeString;
begin
  Result := '';
  reg := TRegistry.Create(KEY_READ);
  try
    reg.RootKey := HKEY_CLASSES_ROOT;
    keyPath := cRegClassRootApplications + AppExeName;
    if reg.OpenKeyReadOnly(keyPath) then
    begin
      if reg.ValueExists(cRegFriendlyAppName) then
        Result := Trim(reg.ReadString(cRegFriendlyAppName));
      reg.CloseKey;
    end;
    if Result = '' then
      if reg.OpenKeyReadOnly(keyPath + '\shell\open') then
      begin
        if reg.ValueExists(cRegFriendlyAppName) then
          Result := Trim(reg.ReadString(cRegFriendlyAppName));
        reg.CloseKey;
      end;
  finally
    reg.Free;
  end;
  Result := ExpandIndirectString(Result);
end;

function GetFileDescriptionFromExe(const ExePath: UnicodeString): UnicodeString;
var
  handle: DWORD;
  infoSize: DWORD;
  infoBuf: Pointer;
  transBuf: Pointer;
  transLen: UINT;
  trans: DWORD;
  query: UnicodeString;
  valueBuf: Pointer;
  valueLen: UINT;
begin
  Result := '';
  infoSize := GetFileVersionInfoSizeW(PWideChar(ExePath), handle);
  if infoSize = 0 then
    Exit;
  GetMem(infoBuf, infoSize);
  try
    if not GetFileVersionInfoW(PWideChar(ExePath), 0, infoSize, infoBuf) then
      Exit;
    if VerQueryValueW(infoBuf, '\VarFileInfo\Translation', transBuf, transLen) and
      (transLen >= SizeOf(DWORD)) then
      trans := PDWORD(transBuf)^
    else
      trans := $04B00409;
    query := Format('\StringFileInfo\%.4x%.4x\FileDescription',
      [LOWORD(trans), HIWORD(trans)]);
    if VerQueryValueW(infoBuf, PWideChar(query), valueBuf, valueLen) and (valueLen > 0) then
      Result := Trim(WideString(PWideChar(valueBuf)));
  finally
    FreeMem(infoBuf);
  end;
end;

function GetDisplayNameFromExePath(const ExePath: UnicodeString): UnicodeString;
var
  appExeName: UnicodeString;
begin
  appExeName := ExtractFileName(ExePath);
  Result := QueryFriendlyAppNameByExeName(appExeName);
  if Result = '' then
    Result := QueryFriendlyAppNameFromRegistry(appExeName);
  if Result = '' then
    Result := GetFileDescriptionFromExe(ExePath);
  if Result = '' then
    Result := ExtractFileName(ExePath);
end;

procedure AppendOpenWithEntry(slSeen: TStringList; var ExePaths, DisplayNames: TOpenWithStringArray;
  const exePath, displayName: UnicodeString);
var
  norm, expanded: UnicodeString;
  n: Integer;
begin
  expanded := Trim(ExpandEnvPathW(exePath));
  if (expanded = '') or not FileExists(expanded) then
    Exit;
  norm := LowerCase(expanded);
  if slSeen.IndexOf(norm) >= 0 then
    Exit;
  slSeen.Add(norm);
  n := Length(ExePaths);
  SetLength(ExePaths, n + 1);
  SetLength(DisplayNames, n + 1);
  ExePaths[n] := expanded;
  if Trim(displayName) <> '' then
    DisplayNames[n] := displayName
  else
    DisplayNames[n] := GetDisplayNameFromExePath(expanded);
end;

// 【新增/优化】获取该文件后缀在当前系统的默认打开程序
function GetDefaultAssocExe(const Extension: UnicodeString): UnicodeString;
var
  cch: DWORD;
  buf: array of WideChar;
begin
  Result := '';
  cch := 0;
  AssocQueryStringW(0, ASSOCSTR_COMMAND, PWideChar(Extension), nil, nil, cch);
  if cch <= 1 then Exit;
  SetLength(buf, cch + 1);
  if AssocQueryStringW(0, ASSOCSTR_COMMAND, PWideChar(Extension), nil, PWideChar(@buf[0]), cch) = S_OK then
    Result := CommandLineToExePath(WideString(PWideChar(@buf[0])));
end;

procedure EnumProgIdsFromKey(reg: TRegistry; const keyPath: UnicodeString; slSeen: TStringList;
  var ExePaths, DisplayNames: TOpenWithStringArray);
var
  regCR: TRegistry;
  sl: TStringList;
  i: Integer;
  progId, cmd, exeFull: UnicodeString;
begin
  regCR := TRegistry.Create(KEY_READ);
  sl := TStringList.Create;
  try
    if not reg.OpenKeyReadOnly(keyPath) then
      Exit;
    try
      reg.GetValueNames(sl);
      regCR.RootKey := HKEY_CLASSES_ROOT;
      for i := 0 to sl.Count - 1 do
      begin
        if sl[i] = '' then
          Continue;
        progId := sl[i];
        if not regCR.OpenKeyReadOnly(progId + cRegShellOpenCommand) then
          Continue;
        try
          cmd := regCR.ReadString('');
        finally
          regCR.CloseKey;
        end;
        cmd := Trim(ExpandEnvPathW(cmd));
        if cmd = '' then
          Continue;
        exeFull := CommandLineToExePath(cmd);
        if exeFull = '' then
          Continue;
        AppendOpenWithEntry(slSeen, ExePaths, DisplayNames, exeFull, '');
      end;
    finally
      reg.CloseKey;
    end;
  finally
    sl.Free;
    regCR.Free;
  end;
end;

function GetExePathFromAppName(const AppExeName: UnicodeString): UnicodeString;
var
  reg: TRegistry;
  pathList: TStringList;
  i: Integer;
  cmd: UnicodeString;
begin
  Result := '';
  if Trim(AppExeName) = '' then
    Exit;
  reg := TRegistry.Create(KEY_READ);
  pathList := TStringList.Create;
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;
    if reg.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\App Paths\' + AppExeName) then
    begin
      Result := Trim(reg.ReadString(''));
      reg.CloseKey;
    end;
    if Result = '' then
    begin
      reg.RootKey := HKEY_CLASSES_ROOT;
      if reg.OpenKeyReadOnly(cRegClassRootApplications + AppExeName + cRegShellOpenCommand) then
      begin
        cmd := Trim(reg.ReadString(''));
        reg.CloseKey;
        Result := CommandLineToExePath(cmd);
      end;
    end;
    if Result = '' then
    begin
      pathList.Delimiter := ';';
      pathList.StrictDelimiter := True;
      pathList.DelimitedText := GetEnvironmentVariable('PATH');
      for i := 0 to pathList.Count - 1 do
      begin
        Result := IncludeTrailingPathDelimiter(pathList[i]) + AppExeName;
        if FileExists(Result) then
          Break;
        Result := '';
      end;
    end;
  finally
    pathList.Free;
    reg.Free;
  end;
end;

procedure EnumExeNamesFromSubKeys(reg: TRegistry; const keyPath: UnicodeString; slSeen: TStringList;
  var ExePaths, DisplayNames: TOpenWithStringArray);
var
  sl: TStringList;
  i: Integer;
  appExeName, appPath: UnicodeString;
begin
  sl := TStringList.Create;
  try
    if not reg.OpenKeyReadOnly(keyPath) then
      Exit;
    try
      reg.GetKeyNames(sl);
      for i := 0 to sl.Count - 1 do
      begin
        appExeName := Trim(sl[i]);
        if appExeName = '' then
          Continue;
        if SameText(appExeName, 'MRUList') then
          Continue;
        appPath := Trim(GetExePathFromAppName(appExeName));
        AppendOpenWithEntry(slSeen, ExePaths, DisplayNames, appPath, '');
      end;
    finally
      reg.CloseKey;
    end;
  finally
    sl.Free;
  end;
end;

procedure EnumExeNamesFromValues(reg: TRegistry; const keyPath: UnicodeString; slSeen: TStringList;
  var ExePaths, DisplayNames: TOpenWithStringArray);
var
  sl: TStringList;
  i: Integer;
  appExeName, appPath: UnicodeString;
begin
  sl := TStringList.Create;
  try
    if not reg.OpenKeyReadOnly(keyPath) then
      Exit;
    try
      reg.GetValueNames(sl);
      for i := 0 to sl.Count - 1 do
      begin
        if SameText(sl[i], 'MRUList') or (sl[i] = '') then
          Continue;
        appExeName := Trim(reg.ReadString(sl[i]));
        if appExeName = '' then
          Continue;
        appPath := Trim(GetExePathFromAppName(appExeName));
        AppendOpenWithEntry(slSeen, ExePaths, DisplayNames, appPath, '');
      end;
    finally
      reg.CloseKey;
    end;
  finally
    sl.Free;
  end;
end;

procedure EnumByAssocHandlers(const ext: UnicodeString; slSeen: TStringList;
  var ExePaths, DisplayNames: TOpenWithStringArray);
var
  hr: HRESULT;
  enumH, enumAll: IEnumAssocHandlers;
  h: IAssocHandler;
  fetched: ULONG;
  pUI, pName: PWideChar;
  exeFull, uiName: UnicodeString;
begin
  if (ext = '') or (ext[1] <> '.') then
    Exit;

  hr := SHAssocEnumHandlers(PWideChar(ext), ASSOC_FILTER_RECOMMENDED, enumH);
  if hr <> S_OK then
    enumH := nil;
  if enumH = nil then
  begin
    hr := SHAssocEnumHandlers(PWideChar(ext), ASSOC_FILTER_NONE, enumAll);
    if hr = S_OK then
      enumH := enumAll;
  end;
  if enumH = nil then
    Exit;

  while True do
  begin
    fetched := 0;
    h := nil;
    if enumH.Next(1, h, fetched) <> S_OK then
      Break;
    if (fetched = 0) or (h = nil) then
      Break;

    pUI := nil;
    pName := nil;
    uiName := '';
    exeFull := '';
    if h.GetUIName(pUI) = S_OK then
    begin
      uiName := Trim(WideString(pUI));
      CoTaskMemFree(pUI);
    end;
    if h.GetName(pName) = S_OK then
    begin
      exeFull := Trim(WideString(pName));
      CoTaskMemFree(pName);
    end;

    if exeFull <> '' then
      AppendOpenWithEntry(slSeen, ExePaths, DisplayNames, exeFull, uiName);
  end;
end;

procedure ShellOpenWithEnum(const FilePath: UnicodeString;
  var ExePaths, DisplayNames: TOpenWithStringArray);
var
  ext, defaultExe: UnicodeString;
  seen: TStringList;
  reg: TRegistry;
  access: LongWord;
begin
  SetLength(ExePaths, 0);
  SetLength(DisplayNames, 0);
  if (FilePath = '') or not FileExists(FilePath) then
    Exit;
  ext := ExtractFileExt(FilePath);
  if (Length(ext) < 2) or (ext[1] <> '.') then
    Exit;

  seen := TStringList.Create;
  try
    seen.CaseSensitive := False;

    // 【核心改进】先获取当前系统的默认打开程序，确保它排在最前面
    defaultExe := GetDefaultAssocExe(ext);
    if (defaultExe <> '') and FileExists(defaultExe) then
    begin
      AppendOpenWithEntry(seen, ExePaths, DisplayNames, defaultExe, '');
    end;

    access := KEY_READ;
    {$IF Declared(KEY_WOW64_64KEY)}
    access := access or KEY_WOW64_64KEY;
    {$IFEND}
    reg := TRegistry.Create(access);
    try
      EnumByAssocHandlers(ext, seen, ExePaths, DisplayNames);
      reg.RootKey := HKEY_CLASSES_ROOT;
      EnumProgIdsFromKey(reg, ext + cRegOpenWithProgids, seen, ExePaths, DisplayNames);
      reg.RootKey := HKEY_CURRENT_USER;
      EnumProgIdsFromKey(reg, cRegFileExtsBase + ext + cRegOpenWithProgids, seen, ExePaths, DisplayNames);

      reg.RootKey := HKEY_CLASSES_ROOT;
      EnumExeNamesFromSubKeys(reg, 'SystemFileAssociations\' + ext + cRegOpenWithList,
        seen, ExePaths, DisplayNames);
      reg.RootKey := HKEY_CLASSES_ROOT;
      EnumExeNamesFromSubKeys(reg, ext + cRegOpenWithList, seen, ExePaths, DisplayNames);
      reg.RootKey := HKEY_CURRENT_USER;
      EnumExeNamesFromValues(reg, cRegFileExtsBase + ext + cRegOpenWithList,
        seen, ExePaths, DisplayNames);
    finally
      reg.Free;
    end;
  finally
    seen.Free;
  end;
end;

procedure ShellOpenWithResetMenuState;
begin
  GShellOpenWithMenuFile := '';
  SetLength(GShellOpenWithMenuExes, 0);
end;

{ 改造成接近 Windows 原生右键「打开方式」子菜单效果 }
procedure ShellOpenWithAppendContextMenuItems(Menu: TXMenu; const FilePath: UnicodeString);
var
  exes, names: TOpenWithStringArray;
  i, n, maxN: Integer;
  hImg: HIMAGE;
  ext, defaultExe: UnicodeString;
  hasDefault: Boolean;
begin
  ShellOpenWithResetMenuState;
  if (FilePath = '') or not FileExists(FilePath) or DirectoryExists(FilePath) then
    Exit;
  if SameText(ExtractFileExt(FilePath), '.exe') then
    Exit;

  GShellOpenWithMenuFile := FilePath;
  ext := ExtractFileExt(FilePath);
  
  // 1. 检测有没有默认关联程序
  defaultExe := LowerCase(GetDefaultAssocExe(ext));
  hasDefault := (defaultExe <> '') and FileExists(defaultExe);

  // 2. 枚举所有打开方式（逻辑中默认程序已排在 Index = 0 处）
  ShellOpenWithEnum(FilePath, exes, names);
  
  maxN := cShellOpenWithMenuLastHandler - cShellOpenWithMenuFirstHandler + 1;
  n := Length(exes);
  if n > maxN then n := maxN;

  SetLength(GShellOpenWithMenuExes, n);
  for i := 0 to n - 1 do
    GShellOpenWithMenuExes[i] := exes[i];

  // 创建「打开方式」父级主菜单
  Menu.AddItem(cShellOpenWithMenuParent, '打开方式', 0, menu_item_flag_Popup);

  for i := 0 to n - 1 do
  begin
    // 添加普通菜单项
    Menu.AddItem(cShellOpenWithMenuFirstHandler + i, names[i], cShellOpenWithMenuParent, 0);
    
    // 【新增效果】提取程序图标并绑定到 XCGUI 对应菜单项
    hImg := ShellOpenWithHandlerImageFromExe(exes[i]);
    if hImg <> 0 then
    begin
      Menu.SetItemIcon(cShellOpenWithMenuFirstHandler + i, hImg);
    end;

    // 【新增效果】如果这一项是默认程序，在其下方添加 Windows 原生的「分割线」
    if hasDefault and (LowerCase(exes[i]) = defaultExe) then
    begin
      // XCGUI 中通过传入 flag = menu_item_flag_Separator 来绘制分割线（此时 ID 无所谓，填 0 即可）
      Menu.AddItem(0, '', cShellOpenWithMenuParent, menu_item_flag_Separator);
    end;
  end;

  // 如果中间没有生成过分割线且列表不为空，在“选择其他应用”前加一条线，保持视觉美观
  if (n > 0) and (not hasDefault) then
  begin
    Menu.AddItem(0, '', cShellOpenWithMenuParent, menu_item_flag_Separator);
  end;

  // 最后的“选择其他应用...”
  Menu.AddItem(cShellOpenWithMenuChooseApp, '选择其他应用...', cShellOpenWithMenuParent, 0);
end;

function ShellOpenWithShowDialog(hwndOwner: Windows.HWND; const FilePath: UnicodeString): Boolean;
var
  oa: TOPENASINFO;
  hr: HRESULT;
  localPath: UnicodeString;
begin
  Result := False;
  localPath := FilePath;
  if (localPath = '') or not FileExists(localPath) then
    Exit;
  oa.pcszFile := PWideChar(localPath);
  oa.pcszClass := nil;
  oa.oaifInFlags := OAIF_ALLOW_REGISTRATION or OAIF_EXEC;
  hr := SHOpenWithDialog(hwndOwner, @oa);
  Result := hr = S_OK;
end;

function ShellOpenWithHandleMenuCommand(nMenuId: Integer; hwndOwner: Windows.HWND): Boolean;
var
  idx: Integer;
begin
  Result := False;
  if GShellOpenWithMenuFile = '' then
    Exit;
  if nMenuId = cShellOpenWithMenuChooseApp then
  begin
    ShellOpenWithShowDialog(hwndOwner, GShellOpenWithMenuFile);
    Result := True;
    Exit;
  end;
  if (nMenuId < cShellOpenWithMenuFirstHandler) or (nMenuId > cShellOpenWithMenuLastHandler) then
    Exit;
  idx := nMenuId - cShellOpenWithMenuFirstHandler;
  if (idx < 0) or (idx >= Length(GShellOpenWithMenuExes)) then
    Exit;
  ShellOpenWithInvokeExe(GShellOpenWithMenuExes[idx], GShellOpenWithMenuFile);
  Result := True;
end;

function ShellOpenWithHandlerImageFromExe(const ExePath: UnicodeString): HIMAGE;
var
  fi: TSHFileInfo;
  hIco: HICON;
  n: UINT;
begin
  Result := 0;
  if ExePath = '' then
    Exit;
  ZeroMemory(@fi, SizeOf(fi));
  if SHGetFileInfoW(PWideChar(ExePath), 0, fi, SizeOf(fi), SHGFI_ICON or SHGFI_SMALLICON) <> 0 then // 改用小图标适合菜单
  begin
    try
      if fi.hIcon <> 0 then
        Result := XImage_LoadFromHICON(fi.hIcon);
    finally
      if fi.hIcon <> 0 then
        DestroyIcon(fi.hIcon);
    end;
  end;
  if XC_GetObjectType(Result) = XC_IMAGE then
    Exit;
  n := ExtractIconExW(PWideChar(ExePath), 0, nil, @hIco, 1); // 提取小图标
  if (n = 0) or (hIco = 0) then
    Exit;
  try
    Result := XImage_LoadFromHICON(hIco);
  finally
    DestroyIcon(hIco);
  end;
  if XC_GetObjectType(Result) <> XC_IMAGE then
    Result := 0;
end;

function ShellOpenWithInvokeExe(const ExePath, FilePath: UnicodeString): Boolean;
var
  params: UnicodeString;
  dir: UnicodeString;
  pDir: PWideChar;
begin
  Result := False;
  if (ExePath = '') or (FilePath = '') or not FileExists(FilePath) then
    Exit;
  params := '"' + FilePath + '"';
  dir := ExtractFilePath(FilePath);
  if dir <> '' then
    pDir := PWideChar(dir)
  else
    pDir := nil;
  Result := ShellExecuteW(0, 'open', PWideChar(ExePath), PWideChar(params), pDir, SW_SHOWNORMAL) > 32;
end;

end.