unit ShellDialogs;

interface

uses
  Classes,
  SysUtils,
  Windows,
  CommDlg;

function OpenFileDialogSingle(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; out AFilePath: string): Boolean;

function OpenFileDialogMulti(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; AFiles: TStrings): Boolean;

function SaveFileDialog(const AOwnerWnd: Windows.HWND; const ATitle, AFilter, ADefaultFileName,
  AInitialDir, ADefaultExt: string; out AFilePath: string): Boolean;

implementation

function OpenFileDialogSingle(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; out AFilePath: string): Boolean;
var
  ofn: TOpenFilenameW;
  fileBuf: array[0..MAX_PATH * 4] of WideChar;
begin
  Result := False;
  AFilePath := '';
  FillChar(ofn, SizeOf(ofn), 0);
  FillChar(fileBuf, SizeOf(fileBuf), 0);
  ofn.lStructSize := SizeOf(ofn);
  ofn.hwndOwner := AOwnerWnd;
  ofn.lpstrTitle := PWideChar(ATitle);
  ofn.lpstrFilter := PWideChar(StringReplace(AFilter, '|', #0, [rfReplaceAll]) + #0#0);
  ofn.lpstrFile := @fileBuf[0];
  ofn.nMaxFile := Length(fileBuf);
  ofn.Flags := OFN_EXPLORER or OFN_FILEMUSTEXIST or OFN_PATHMUSTEXIST or OFN_HIDEREADONLY or OFN_ENABLESIZING;
  if not GetOpenFileNameW(ofn) then
    Exit;
  AFilePath := fileBuf;
  Result := AFilePath <> '';
end;

function OpenFileDialogMulti(const AOwnerWnd: Windows.HWND; const ATitle, AFilter: string; AFiles: TStrings): Boolean;
var
  ofn: TOpenFilenameW;
  fileBuf: array[0..65535] of WideChar;
  baseDir: string;
  p: PWideChar;
  item: string;
begin
  Result := False;
  if AFiles = nil then
    Exit;
  AFiles.Clear;
  FillChar(ofn, SizeOf(ofn), 0);
  FillChar(fileBuf, SizeOf(fileBuf), 0);
  ofn.lStructSize := SizeOf(ofn);
  ofn.hwndOwner := AOwnerWnd;
  ofn.lpstrTitle := PWideChar(ATitle);
  ofn.lpstrFilter := PWideChar(StringReplace(AFilter, '|', #0, [rfReplaceAll]) + #0#0);
  ofn.lpstrFile := @fileBuf[0];
  ofn.nMaxFile := Length(fileBuf);
  ofn.Flags := OFN_EXPLORER or OFN_ALLOWMULTISELECT or OFN_FILEMUSTEXIST or OFN_PATHMUSTEXIST or OFN_HIDEREADONLY or OFN_ENABLESIZING;
  if not GetOpenFileNameW(ofn) then
    Exit;

  baseDir := fileBuf;
  p := @fileBuf[Length(baseDir) + 1];
  if p^ = #0 then
    AFiles.Add(baseDir)
  else
  begin
    while p^ <> #0 do
    begin
      item := p;
      AFiles.Add(IncludeTrailingPathDelimiter(baseDir) + item);
      Inc(p, Length(item) + 1);
    end;
  end;
  Result := AFiles.Count > 0;
end;

function SaveFileDialog(const AOwnerWnd: Windows.HWND; const ATitle, AFilter, ADefaultFileName,
  AInitialDir, ADefaultExt: string; out AFilePath: string): Boolean;
var
  ofn: TOpenFilenameW;
  fileBuf: array[0..MAX_PATH * 4] of WideChar;
begin
  Result := False;
  AFilePath := '';
  FillChar(ofn, SizeOf(ofn), 0);
  FillChar(fileBuf, SizeOf(fileBuf), 0);
  if ADefaultFileName <> '' then
    StrPLCopy(fileBuf, ADefaultFileName, Length(fileBuf) - 1);
  ofn.lStructSize := SizeOf(ofn);
  ofn.hwndOwner := AOwnerWnd;
  ofn.lpstrTitle := PWideChar(ATitle);
  ofn.lpstrFilter := PWideChar(StringReplace(AFilter, '|', #0, [rfReplaceAll]) + #0#0);
  ofn.lpstrFile := @fileBuf[0];
  ofn.nMaxFile := Length(fileBuf);
  if AInitialDir <> '' then
    ofn.lpstrInitialDir := PWideChar(AInitialDir);
  if ADefaultExt <> '' then
    ofn.lpstrDefExt := PWideChar(ADefaultExt);
  ofn.Flags := OFN_EXPLORER or OFN_OVERWRITEPROMPT or OFN_PATHMUSTEXIST or
    OFN_HIDEREADONLY or OFN_ENABLESIZING;
  if not GetSaveFileNameW(ofn) then
    Exit;
  AFilePath := fileBuf;
  Result := AFilePath <> '';
end;

end.
