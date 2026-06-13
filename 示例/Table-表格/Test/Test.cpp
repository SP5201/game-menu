// Test.cpp : 定义应用程序的入口点。
//

#include "stdafx.h"
#include "Test.h"

//包含炫彩界面库文件
#include "../../../DLL/xcgui.h"
#pragma comment(lib,"../../../DLL/XCGUI.lib")

class CWindow
{
public:
	HWINDOW m_hWindow;
	CWindow()
	{
		Init();
	}
	void Init()
	{
		m_hWindow = XWnd_Create(0, 0, 700, 350, L"炫彩界面库窗口", NULL, window_style_default);

		HXCGUI hTable = XTable_Create(20, 50, 600, 250, m_hWindow);
		XTable_Reset(hTable, 8, 6);

		XTable_SetRowHeight(hTable, 7, 50);
		XTable_SetColWidth(hTable, 0, 100);
		XTable_SetColWidth(hTable, 4, 60);
		XTable_SetColWidth(hTable, 5, 60);
		XTable_ComboCol(hTable, 0, 0, 6);
		XTable_ComboCol(hTable, 0, 2, 2);
		XTable_ComboRow(hTable, 0, 2, 2);
		XTable_ComboCol(hTable, 1, 0, 2);
		XTable_ComboRow(hTable, 1, 0, 2);
		XTable_ComboCol(hTable, 2, 1, 5);
		XTable_ComboRow(hTable, 3, 4, 5);
		XTable_ComboRow(hTable, 3, 5, 5);

		XTable_SetItemText(hTable, 0, 0, L"v2.6.0");
		XTable_SetItemFlag(hTable, 0, 0, table_flag_none);
		XTable_SetItemTextColor(hTable, 0, 0, RGBA(0, 0, 255,255), TRUE);
		XTable_SetItemBkColor(hTable, 0, 0, RGBA(255, 150, 150,255), TRUE);

		XTable_SetItemText(hTable, 0, 2, L"炫彩界面库");
		HFONTX hFont = XFont_Create(16);
		XTable_SetItemFont(hTable, 0, 2, hFont);
		XTable_SetItemTextColor(hTable, 0, 2, RGBA(200, 0, 0,255), TRUE);
		XTable_SetItemTextAlign(hTable, 0, 2, textAlignFlag_center | textAlignFlag_vcenter);
		XTable_SetItemBkColor(hTable, 0, 2, RGBA(255, 255, 128,255), TRUE);

		XTable_SetItemBkColor(hTable, 1, 0, RGBA(128, 255, 128,255), TRUE);
		XTable_SetItemText(hTable, 1, 1, L"窗口");
		XTable_SetItemTextAlign(hTable, 1, 1, textAlignFlag_center | textAlignFlag_vcenter);

		XTable_SetItemText(hTable, 2, 0, L"元素");
		XTable_SetItemTextAlign(hTable, 2, 0, textAlignFlag_center | textAlignFlag_vcenter);

		XTable_SetItemText(hTable, 3, 0, L"基础元素"); XTable_SetItemBkColor(hTable, 3, 0, RGBA(0, 128, 64,255), TRUE);
		XTable_SetItemText(hTable, 4, 0, L"列表");  XTable_SetItemBkColor(hTable, 4, 0, RGBA(0, 128, 64,255), TRUE);
		XTable_SetItemText(hTable, 5, 0, L"树"); XTable_SetItemBkColor(hTable, 5, 0, RGBA(0, 128, 64,255), TRUE);
		XTable_SetItemText(hTable, 6, 0, L"组合框"); XTable_SetItemBkColor(hTable, 6, 0, RGBA(0, 128, 64,255), TRUE);
		XTable_SetItemText(hTable, 7, 0, L"按钮"); XTable_SetItemBkColor(hTable, 7, 0, RGBA(0, 128, 64,255), TRUE);

		XTable_SetItemText(hTable, 1, 2, L"API");
		XTable_SetItemText(hTable, 2, 1, L"API: 02");
		XTable_SetItemText(hTable, 2, 2, L"API: 03");
		XTable_SetItemText(hTable, 2, 3, L"API: 04");
		XTable_SetItemText(hTable, 3, 1, L"API: 05");
		XTable_SetItemText(hTable, 3, 2, L"API: 06");
		XTable_SetItemText(hTable, 3, 3, L"API: 07");
		XTable_SetItemText(hTable, 4, 1, L"API: 08");
		XTable_SetItemText(hTable, 5, 1, L"API: 09");
		XTable_SetItemText(hTable, 6, 1, L"API: 10");
		XTable_SetItemText(hTable, 2, 5, L"API: 11");
		XTable_SetItemText(hTable, 3, 5, L"API: 12");

		XTable_SetItemLine(hTable, 0, 0, 0, 1, table_line_flag_left | table_line_flag_bottom | table_line_flag_right2 | table_line_flag_top2, RGB(0, 0, 200) | 0xFF000000);
		XTable_SetItemLine(hTable, 1, 0, 2, 0, table_line_flag_left | table_line_flag_top | table_line_flag_right2 | table_line_flag_bottom2, RGB(200, 0, 0) | 0xFF000000);
		XTable_SetItemLine(hTable, 2, 1, 7, 5, table_line_flag_left | table_line_flag_top | table_line_flag_right2 | table_line_flag_bottom2, RGB(0, 128, 255) | 0xFF000000);

		XWnd_AdjustLayout(m_hWindow);
		XWnd_ShowWindow(m_hWindow, SW_SHOW);
	}
};

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
	XInitXCGUI(TRUE);
	CWindow  MyWindow;
	XRunXCGUI();
	XExitXCGUI();
	return TRUE;
}
