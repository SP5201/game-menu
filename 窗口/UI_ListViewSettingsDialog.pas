unit UI_ListViewSettingsDialog;

interface

uses
  Windows, Messages, SysUtils, Classes, XCGUI, UI_Form, UI_Button, UI_Theme, UI_SliderBar,
  AppConfig;

type
  TListViewLayoutSettings = record
    ColumnSpace: Integer;
    RowSpace: Integer;
    ItemCornerRadius: Integer;
  end;

  TListViewSettingsDialogUI = class(TFormUI)
  private
    FTargetListView: NativeInt;
    class var
      FActiveDialog: TListViewSettingsDialogUI;
      FSaved: TListViewLayoutSettings;
      FWorking: TListViewLayoutSettings;
      FSliderColSpace: HELE;
      FSliderRowSpace: HELE;
      FSliderCorner: HELE;
      FLabelColSpace: HELE;
      FLabelRowSpace: HELE;
      FLabelCorner: HELE;
    class procedure ApplyShapeTextTheme(const AName: string); static;
    class procedure UpdateValueLabel(ALabel: HELE; const AValue: Integer); static;
    class procedure UpdateWorkingValueLabels; static;
    class procedure ReadWorkingFromUi; static;
    class procedure ApplyWorkingToUi; static;
    class procedure ApplyWorkingToListView; static;
    class procedure RedrawDialog; static;
    class procedure LoadSavedFromConfig; static;
    class procedure SaveWorkingToConfig; static;
    class function SliderPosToValue(hSlider: HELE; APos: Integer): Integer; static;
    class procedure InitSlider(hSlider: HELE; AMin, AMax, APos: Integer); static;
    class function OnSliderChange(hEle: XCGUI.HELE; nPos: Integer; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnClose(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnReset(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnBtnOk(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall; static;
    class function OnWndKeyDown(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall; static;
  protected
    procedure Init; override;
  public
    class function LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI = 0; hAttachWnd: XCGUI.HWINDOW = 0): TListViewSettingsDialogUI; reintroduce;
    class function ShowDialog(const hParent: XCGUI.HWINDOW; AListView: NativeInt; hAttachWnd: XCGUI.HWINDOW = 0): Boolean;
  end;

implementation

uses
  UI_ListView;

const
  ID_BTN_CLOSE              = 'btn_listview_settings_close';
  ID_BTN_RESET              = 'btn_listview_settings_reset';
  ID_BTN_OK                 = 'btn_listview_settings_ok';
  ID_TXT_TITLE              = 'txt_listview_settings_title';
  ID_TXT_LABEL_COL_SPACE    = 'txt_listview_settings_label_col_space';
  ID_TXT_LABEL_ROW_SPACE    = 'txt_listview_settings_label_row_space';
  ID_TXT_LABEL_CORNER       = 'txt_listview_settings_label_corner';
  ID_SLIDER_COL_SPACE       = 'slider_listview_settings_col_space';
  ID_SLIDER_ROW_SPACE       = 'slider_listview_settings_row_space';
  ID_SLIDER_CORNER          = 'slider_listview_settings_corner';
  ID_TXT_COL_SPACE_VALUE    = 'txt_listview_settings_col_space_value';
  ID_TXT_ROW_SPACE_VALUE    = 'txt_listview_settings_row_space_value';
  ID_TXT_CORNER_VALUE       = 'txt_listview_settings_corner_value';

class procedure TListViewSettingsDialogUI.ApplyShapeTextTheme(const AName: string);
var
  hText: HELE;
begin
  hText := XC_GetObjectByName(PWideChar(AName));
  if XC_GetObjectType(hText) = XC_SHAPE_TEXT then
    XShapeText_SetTextColor(hText, UITheme_TextPrimary);
end;

class procedure TListViewSettingsDialogUI.UpdateValueLabel(ALabel: HELE; const AValue: Integer);
begin
  if XC_GetObjectType(ALabel) <> XC_SHAPE_TEXT then
    Exit;
  XShapeText_SetText(ALabel, PWideChar(IntToStr(AValue)));
  XShape_AdjustLayout(ALabel);
end;

class procedure TListViewSettingsDialogUI.LoadSavedFromConfig;
begin
  FSaved.ColumnSpace := TAppConfig.GetListColumnSpace;
  FSaved.RowSpace := TAppConfig.GetListRowSpace;
  FSaved.ItemCornerRadius := TAppConfig.GetListItemCornerRadius;
end;

class procedure TListViewSettingsDialogUI.SaveWorkingToConfig;
begin
  TAppConfig.SetListColumnSpace(FWorking.ColumnSpace);
  TAppConfig.SetListRowSpace(FWorking.RowSpace);
  TAppConfig.SetListItemCornerRadius(FWorking.ItemCornerRadius);
  TAppConfig.Save;
end;

class function TListViewSettingsDialogUI.SliderPosToValue(hSlider: HELE; APos: Integer): Integer;
begin
  Result := APos;
  if XC_IsHELE(hSlider) then
    Result := APos + XEle_GetUserData(hSlider);
end;

class procedure TListViewSettingsDialogUI.UpdateWorkingValueLabels;
begin
  UpdateValueLabel(FLabelColSpace, FWorking.ColumnSpace);
  UpdateValueLabel(FLabelRowSpace, FWorking.RowSpace);
  UpdateValueLabel(FLabelCorner, FWorking.ItemCornerRadius);
end;

class procedure TListViewSettingsDialogUI.ReadWorkingFromUi;
begin
  if XC_IsHELE(FSliderColSpace) then
    FWorking.ColumnSpace := SliderPosToValue(FSliderColSpace, XSliderBar_GetPos(FSliderColSpace));
  if XC_IsHELE(FSliderRowSpace) then
    FWorking.RowSpace := SliderPosToValue(FSliderRowSpace, XSliderBar_GetPos(FSliderRowSpace));
  if XC_IsHELE(FSliderCorner) then
    FWorking.ItemCornerRadius := SliderPosToValue(FSliderCorner, XSliderBar_GetPos(FSliderCorner));
end;

class procedure TListViewSettingsDialogUI.ApplyWorkingToListView;
var
  listViewUi: TListViewUI;
  layout: TListViewLayoutSettings;
begin
  if (FActiveDialog = nil) or (FActiveDialog.FTargetListView = 0) then
    Exit;
  listViewUi := TListViewUI(FActiveDialog.FTargetListView);
  layout := FWorking;
  listViewUi.ApplyLayoutSettings(layout.ColumnSpace, layout.RowSpace, layout.ItemCornerRadius,
    TAppConfig.GetListScrollBarSize, TAppConfig.GetListScrollSliderMinLen, TAppConfig.GetListScrollThumbRadius);
end;

class procedure TListViewSettingsDialogUI.ApplyWorkingToUi;
begin
  if XC_IsHELE(FSliderColSpace) then
    XSliderBar_SetPos(FSliderColSpace, FWorking.ColumnSpace - XEle_GetUserData(FSliderColSpace));
  if XC_IsHELE(FSliderRowSpace) then
    XSliderBar_SetPos(FSliderRowSpace, FWorking.RowSpace - XEle_GetUserData(FSliderRowSpace));
  if XC_IsHELE(FSliderCorner) then
    XSliderBar_SetPos(FSliderCorner, FWorking.ItemCornerRadius - XEle_GetUserData(FSliderCorner));

  UpdateWorkingValueLabels;
  RedrawDialog;
end;

class procedure TListViewSettingsDialogUI.RedrawDialog;
begin
  if (FActiveDialog <> nil) and FActiveDialog.IsHWINDOW then
    XWnd_Redraw(FActiveDialog.Handle);
end;

class procedure TListViewSettingsDialogUI.InitSlider(hSlider: HELE; AMin, AMax, APos: Integer);
begin
  if not XC_IsHELE(hSlider) then
    Exit;
  XEle_SetUserData(hSlider, AMin);
  XSliderBar_SetRange(hSlider, AMax - AMin);
  XSliderBar_SetPos(hSlider, APos - AMin);
  TSliderBarUI.ApplyDefault(hSlider);
  XEle_RegEvent(hSlider, XE_SLIDERBAR_CHANGE, @TListViewSettingsDialogUI.OnSliderChange);
end;

class function TListViewSettingsDialogUI.OnSliderChange(hEle: XCGUI.HELE; nPos: Integer; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  ReadWorkingFromUi;
  UpdateWorkingValueLabels;
  ApplyWorkingToListView;
  RedrawDialog;
end;

class function TListViewSettingsDialogUI.OnBtnClose(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  FWorking := FSaved;
  ApplyWorkingToListView;
  TFormUI.EndModalCancel(hEle);
end;

class function TListViewSettingsDialogUI.OnBtnReset(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  FWorking.ColumnSpace := cDefaultListColumnSpace;
  FWorking.RowSpace := cDefaultListRowSpace;
  FWorking.ItemCornerRadius := cDefaultListItemCornerRadius;
  ApplyWorkingToUi;
  ApplyWorkingToListView;
end;

class function TListViewSettingsDialogUI.OnBtnOk(hEle: XCGUI.HELE; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  pbHandled^ := True;
  ReadWorkingFromUi;
  SaveWorkingToConfig;
  FSaved := FWorking;
  TFormUI.EndModalOk(hEle);
end;

class function TListViewSettingsDialogUI.OnWndKeyDown(hWindow: XCGUI.HWINDOW; wParam: WPARAM; lParam: LPARAM; pbHandled: PBOOL): Integer; stdcall;
begin
  Result := 0;
  case wParam of
    VK_ESCAPE:
      begin
        pbHandled^ := True;
        FWorking := FSaved;
        ApplyWorkingToListView;
        TFormUI.EndModalCancelWnd(hWindow);
      end;
    VK_RETURN:
      begin
        pbHandled^ := True;
        ReadWorkingFromUi;
        SaveWorkingToConfig;
        FSaved := FWorking;
        TFormUI.EndModalOkWnd(hWindow);
      end;
  end;
end;

class function TListViewSettingsDialogUI.LoadLayout(const LayoutFile: PWideChar; hParent: HXCGUI; hAttachWnd: XCGUI.HWINDOW): TListViewSettingsDialogUI;
var
  h: HXCGUI;
begin
  h := TFormUI.LoadLayoutFile(LayoutFile, hParent, hAttachWnd);
  if h = 0 then
    Exit(nil);
  Result := TListViewSettingsDialogUI.FromHandle(h);
end;

procedure TListViewSettingsDialogUI.Init;
begin
  inherited;
  ApplyTitleLogo('pic_listview_settings_dialog_logo', 20);
  FActiveDialog := Self;

  LoadSavedFromConfig;
  FWorking := FSaved;

  TButtonUI.FromXmlName(ID_BTN_CLOSE, BB_NONE, 'Resource\UI\close.svg').RegEvent(XE_BNCLICK, @TListViewSettingsDialogUI.OnBtnClose);
  TButtonUI.FromXmlName(ID_BTN_RESET, BB_EnableNormalBk, '').RegEvent(XE_BNCLICK, @TListViewSettingsDialogUI.OnBtnReset);
  TButtonUI.FromXmlName(ID_BTN_OK, BB_EnableHighlightBk, '').RegEvent(XE_BNCLICK, @TListViewSettingsDialogUI.OnBtnOk);

  ApplyShapeTextTheme(ID_TXT_TITLE);
  ApplyShapeTextTheme(ID_TXT_LABEL_COL_SPACE);
  ApplyShapeTextTheme(ID_TXT_LABEL_ROW_SPACE);
  ApplyShapeTextTheme(ID_TXT_LABEL_CORNER);

  FLabelColSpace := XC_GetObjectByName(ID_TXT_COL_SPACE_VALUE);
  FLabelRowSpace := XC_GetObjectByName(ID_TXT_ROW_SPACE_VALUE);
  FLabelCorner := XC_GetObjectByName(ID_TXT_CORNER_VALUE);
  ApplyShapeTextTheme(ID_TXT_COL_SPACE_VALUE);
  ApplyShapeTextTheme(ID_TXT_ROW_SPACE_VALUE);
  ApplyShapeTextTheme(ID_TXT_CORNER_VALUE);

  FSliderColSpace := XC_GetObjectByName(ID_SLIDER_COL_SPACE);
  FSliderRowSpace := XC_GetObjectByName(ID_SLIDER_ROW_SPACE);
  FSliderCorner := XC_GetObjectByName(ID_SLIDER_CORNER);

  InitSlider(FSliderColSpace, cListColumnSpaceMin, cListColumnSpaceMax, FWorking.ColumnSpace);
  InitSlider(FSliderRowSpace, cListRowSpaceMin, cListRowSpaceMax, FWorking.RowSpace);
  InitSlider(FSliderCorner, cListItemCornerRadiusMin, cListItemCornerRadiusMax, FWorking.ItemCornerRadius);

  ApplyWorkingToUi;
  ApplyWorkingToListView;

  if IsHWINDOW then
    RegEvent(WM_KEYDOWN, @TListViewSettingsDialogUI.OnWndKeyDown);
end;

class function TListViewSettingsDialogUI.ShowDialog(const hParent: XCGUI.HWINDOW; AListView: NativeInt; hAttachWnd: XCGUI.HWINDOW): Boolean;
var
  dlg: TListViewSettingsDialogUI;
  modalResult: Integer;
begin
  dlg := TListViewSettingsDialogUI.LoadLayout('Resource\Layout\ListViewSettingsDialog.xml', hParent, hAttachWnd);
  if dlg = nil then
    Exit(False);
  dlg.FTargetListView := AListView;
  try
    modalResult := XModalWnd_DoModal(dlg.Handle);
    Result := modalResult = IDOK;
  finally
    dlg.FTargetListView := 0;
    if FActiveDialog = dlg then
      FActiveDialog := nil;
  end;
end;

end.
