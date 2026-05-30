unit ListItemTypes;

interface

uses
  SysUtils,
  XCGUI;

type
  /// <summary>列表/库条目绑定的文件元数据（路径、图标、显示名、启动参数等）。</summary>
  TListViewFileItem = record
    FilePath: string;
    FileImage: HIMAGE;
    /// <summary>按当前格宽预缩放的显示用图（共享池 AddRef）；0 表示绘制时仍用 FileImage。</summary>
    DisplayImage: HIMAGE;
    /// <summary>DisplayImage 对应的图标边长；-1 表示无。</summary>
    DisplayIconSide: Integer;
    IconCachePath: string;
    FileName: string;
    FileParams: string;
    WorkingDir: string;
    /// <summary>与数据库 id 顺序一致的插入序号；负数表示由列表在添加时自动分配。</summary>
    InsertOrder: Integer;
    /// <summary>数据库 group_index；全局搜索时每项独立；-1 表示使用列表当前活动分组。</summary>
    ItemGroupIndex: Integer;
  end;

/// <summary>列表项显示标题：FileName → 文件名 → 完整路径。</summary>
function ListViewItemDisplayTitle(const R: TListViewFileItem): string;

implementation

function ListViewItemDisplayTitle(const R: TListViewFileItem): string;
begin
  Result := R.FileName;
  if Result = '' then
    Result := ExtractFileName(R.FilePath);
  if Result = '' then
    Result := R.FilePath;
end;

end.
