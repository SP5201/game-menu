// Test.cpp : 定义应用程序的入口点。
//

#include "stdafx.h"
#include "Test.h"

//包含炫彩界面库文件
#include "../../../DLL/xcgui.h"
#pragma comment(lib,"../../../DLL/XCGUI.lib")

#include <vector>
using namespace std;


class CMyWindowDemo
{
public:
	HWINDOW m_hWindow;
	ease_type_  m_easeFlag;  //缓动方式
	int    m_easeType;     //缓动类型
	int    m_pos;         //当前位置
	int    m_time;        //缓动点数量
	int    m_time_pos;    //当前点
	RECT   m_rect;         //窗口客户区坐标
	int    m_windowType;   //窗口水平或垂直缓动
	CMyWindowDemo()
	{
		m_easeFlag = easeOut; //easeOut; 
		m_easeType = 11;
		m_pos = 0;
		m_time = 60;
		m_time_pos = 0;
		m_windowType = 2;
		Init();
	}
	void Init()
	{
		m_hWindow = XWnd_Create(0, 0, 700, 450, L"炫彩界面库(XCGUI) - 缓动测试");
		XWnd_EnableDragWindow(m_hWindow, TRUE);
		XWnd_EnableDragBorder(m_hWindow, FALSE);

		int left = 30;
		int top = 35;
		CreateButton(2, 11, left, top, 100, L"Linear"); left += 105;
		CreateButton(2, 12, left, top, 100, L"Quadratic"); left += 105;
		CreateButton(2, 13, left, top, 100, L"Cubic"); left += 105;
		CreateButton(2, 14, left, top, 100, L"Quartic"); left += 105;
		CreateButton(2, 15, left, top, 100, L"Quintic"); left += 105;

		left = 30;
		top += 30;
		CreateButton(2, 16, left, top, 100, L"Sinusoidal"); left += 105;
		CreateButton(2, 17, left, top, 100, L"Exponential"); left += 105;
		CreateButton(2, 18, left, top, 100, L"Circular"); left += 105;

		left = 30;
		top += 30;
		CreateButton(2, 19, left, top, 100, L"Elastic"); left += 105;
		CreateButton(2, 20, left, top, 100, L"Back"); left += 105;
		CreateButton(2, 21, left, top, 100, L"Bounce"); left += 105;

		left = 30;
		top += 40;
		CreateButton(1, 0, left, top, 100, L"easeIn"); left += 105;
		CreateButton(1, 1, left, top, 100, L"easeOut"); left += 105;
		CreateButton(1, 2, left, top, 100, L"easeInOut"); left += 105;

		HELE hButton = XBtn_Create(445, top, 100, 24, L"快速", m_hWindow);
		XBtn_SetTypeEx(hButton, button_type_check);
		XBtn_SetCheck(hButton, TRUE);
		XEle_RegEventCPP(hButton, XE_BUTTON_CHECK, &CMyWindowDemo::OnBtnCheckSlow);

		hButton = XBtn_Create(600, 35, 60, 25, L"Exit", m_hWindow);
		XObj_SetTypeEx(hButton, button_type_close);

		hButton = XBtn_Create(445, 65, 100, 24, L"从左向右", m_hWindow);
		XBtn_SetTypeEx(hButton, button_type_radio);	XBtn_SetGroupID(hButton, 3);
		XEle_RegEventCPP(hButton, XE_BUTTON_CHECK, &CMyWindowDemo::OnBtnCheck_LeftToRight);

		hButton = XBtn_Create(445, 92, 100, 24, L"从上向下", m_hWindow);
		XBtn_SetTypeEx(hButton, button_type_radio);	XBtn_SetGroupID(hButton, 3); XBtn_SetCheck(hButton, TRUE);
		XEle_RegEventCPP(hButton, XE_BUTTON_CHECK, &CMyWindowDemo::OnBtnCheck_TopToBottom);

		hButton = XBtn_Create(550, 65, 110, 50, L"Run - 窗口缓动", m_hWindow);
		XEle_RegEventCPP(hButton, XE_BNCLICK, &CMyWindowDemo::OnBtnStartWindow);

		hButton = XBtn_Create(550, 120, 110, 50, L"Run - 缓动曲线", m_hWindow);
		XEle_RegEventCPP(hButton, XE_BNCLICK, &CMyWindowDemo::OnBtnStart);

		XWnd_AdjustLayout(m_hWindow);
		XWnd_ShowWindow(m_hWindow, SW_SHOW);
		XWnd_RegEventCPP(m_hWindow, WM_PAINT, &CMyWindowDemo::OnDrawWindow);

		RECT rect;
		GetWindowRect(XWnd_GetHWND(m_hWindow), &rect);
		int y = 0;

		for (int t = 0; t <= 30; t++)
		{
			float v = XEase_Bounce((float)t / 30, easeOut);
			y = v * rect.top;
			XWnd_SetPosition(m_hWindow, rect.left, y);
			XWnd_Redraw(m_hWindow, TRUE);
			Sleep(10);
		}
	}
	void CreateButton(int nGroup, int id, int x, int y, int cx, const wchar_t* title)
	{
		HELE hButton = XBtn_Create(x, y, cx, 22, title, m_hWindow);
		XBtn_SetTypeEx(hButton, button_type_radio);
		XBtn_SetGroupID(hButton, nGroup); XWidget_SetID(hButton, id);
		if (1 == id || 21 == id) XBtn_SetCheck(hButton, TRUE);
		XEle_RegEventCPP1(hButton, XE_BUTTON_CHECK, &CMyWindowDemo::OnButtonCheck);
	}
	int OnButtonCheck(HELE hButton, BOOL bCheck, BOOL *pbHandled)
	{
		if (!bCheck) return 0;
		int id = XWidget_GetID(hButton);
		if (id <= 2)
			m_easeFlag = (ease_type_)id;
		else
			m_easeType = id - 10;
		XWnd_Redraw(m_hWindow, TRUE);
		return 0;
	}
	int OnBtnCheckSlow(BOOL bCheck, BOOL *pbHandled)
	{
		if (bCheck)
			m_time = 60;
		else
			m_time = 120;
		return 0;
	}
	int OnBtnStart(BOOL *pbHandled)
	{
		float  width = 400.0f;
		for (int t = 0; t <= m_time; t++)
		{
			float  v = 0;
			switch (m_easeType)
			{
			case 1: v = XEase_Linear((float)t / m_time); break;
			case 2: v = XEase_Quad((float)t / m_time, m_easeFlag); break;
			case 3: v = XEase_Cubic((float)t / m_time, m_easeFlag); break;
			case 4: v = XEase_Quart((float)t / m_time, m_easeFlag); break;
			case 5: v = XEase_Quint((float)t / m_time, m_easeFlag); break;
			case 6: v = XEase_Sine((float)t / m_time, m_easeFlag); break;
			case 7: v = XEase_Expo((float)t / m_time, m_easeFlag); break;
			case 8: v = XEase_Circ((float)t / m_time, m_easeFlag); break;
			case 9: v = XEase_Elastic((float)t / m_time, m_easeFlag); break;
			case 10:v = XEase_Back((float)t / m_time, m_easeFlag); break;
			case 11:v = XEase_Bounce((float)t / m_time, m_easeFlag); break;
			}
			m_pos = v * width;
			m_time_pos = t;
			Sleep(10);
			RECT rc = m_rect;
			rc.top = 170;
			XWnd_RedrawRect(m_hWindow, &rc, TRUE);
		}
		return 0;
	}
	int OnBtnStartWindow(BOOL *pbHandled)
	{
		RECT rect;
		GetWindowRect(XWnd_GetHWND(m_hWindow), &rect);
		int time = m_time / 2;
		for (int t = 0; t <= time; t++)
		{
			float  v = 0;
			switch (m_easeType)
			{
			case 1: v = XEase_Linear((float)t / time); break;
			case 2: v = XEase_Quad((float)t / time, m_easeFlag); break;
			case 3: v = XEase_Cubic((float)t / time, m_easeFlag); break;
			case 4: v = XEase_Quart((float)t / time, m_easeFlag); break;
			case 5: v = XEase_Quint((float)t / time, m_easeFlag); break;
			case 6: v = XEase_Sine((float)t / time, m_easeFlag); break;
			case 7: v = XEase_Expo((float)t / time, m_easeFlag); break;
			case 8: v = XEase_Circ((float)t / time, m_easeFlag); break;
			case 9: v = XEase_Elastic((float)t / time, m_easeFlag); break;
			case 10:v = XEase_Back((float)t / time, m_easeFlag); break;
			case 11:v = XEase_Bounce((float)t / time, m_easeFlag); break;
			}
			if (1 == m_windowType)
			{
				int x = v * rect.left;
				XWnd_SetPosition(m_hWindow, x, rect.top);
			} else
			{
				int y = v * rect.top;
				XWnd_SetPosition(m_hWindow, rect.left, y);
			}
			XWnd_Redraw(m_hWindow, TRUE);
			Sleep(10);
		}
		return 0;
	}
	int OnBtnCheck_LeftToRight(BOOL bCheck, BOOL *pbHandled)
	{
		if (bCheck)
			m_windowType = 1;
		return 0;
	}
	int OnBtnCheck_TopToBottom(BOOL bCheck, BOOL *pbHandled)
	{
		if (bCheck)
			m_windowType = 2;
		return 0;
	}
	int OnDrawWindow(HDRAW hDraw, BOOL* pbHandled)
	{
		*pbHandled = TRUE;
		RECT rect;
		XWnd_GetClientRect(m_hWindow, &rect);
		XDraw_SetBrushColor(hDraw, RGBA(230, 230, 230,255));
		XDraw_FillRect(hDraw, &rect);
		m_rect = rect;

		XDraw_SetBrushColor(hDraw, RGBA(200, 200, 200, 255));
		XDraw_DrawRect(hDraw, &rect);

		XDraw_SetBrushColor(hDraw, RGBA(0, 0, 200, 255));
		XDraw_TextOutEx(hDraw, 260, 10, L"炫彩界面库(XCGUI) - 缓动测试");

		RECT rc;
		rc.left = 150;
		rc.top = 190;
		rc.right = rc.left + 400 + 30;
		rc.bottom = rc.top + 50;
		{
			RECT rcBorder = rc;
			rcBorder.left -= 2;
			rcBorder.top -= 2;
			rcBorder.right += 2;
			rcBorder.bottom += 2;
			XDraw_SetBrushColor(hDraw, RGBA(0, 0, 200, 255));
			XDraw_DrawRect(hDraw, &rcBorder);
		}
		RECT rcFill = rc;
		rcFill.left = rcFill.left + m_pos;
		rcFill.right = rcFill.left + 30;
		XDraw_SetBrushColor(hDraw, RGBA(128, 0, 0, 255));
		XDraw_FillRect(hDraw, &rcFill);

		RECT  rcBorder_Line;
		rcBorder_Line.left = 150;
		rcBorder_Line.right = 150 + 400;
		rcBorder_Line.top = 255;
		rcBorder_Line.bottom = 255 + 180;
		{
			RECT rcBorder = rcBorder_Line;
			rcBorder.right++;
			rcBorder.bottom++;
			XDraw_SetBrushColor(hDraw, RGBA(180, 180, 180, 255));
			XDraw_DrawRect(hDraw, &rcBorder);
		}

		POINTF  pts[121];
		int x = rcBorder_Line.left;
		int y = rcBorder_Line.bottom;
		for (int t = 0; t <= m_time; t++)
		{
			float  v = 0;
			switch (m_easeType)
			{
			case 1: v = XEase_Linear((float)t / m_time); break;
			case 2: v = XEase_Quad((float)t / m_time, m_easeFlag); break;
			case 3: v = XEase_Cubic((float)t / m_time, m_easeFlag); break;
			case 4: v = XEase_Quart((float)t / m_time, m_easeFlag); break;
			case 5: v = XEase_Quint((float)t / m_time, m_easeFlag); break;
			case 6: v = XEase_Sine((float)t / m_time, m_easeFlag); break;
			case 7: v = XEase_Expo((float)t / m_time, m_easeFlag); break;
			case 8: v = XEase_Circ((float)t / m_time, m_easeFlag); break;
			case 9: v = XEase_Elastic((float)t / m_time, m_easeFlag); break;
			case 10:v = XEase_Back((float)t / m_time, m_easeFlag); break;
			case 11:v = XEase_Bounce((float)t / m_time, m_easeFlag); break;
			}

			pts[t].x = rc.left + t / (float)m_time * 400.0f;
			pts[t].y = rcBorder_Line.bottom - v * 180.0f;
		}

		XDraw_EnableSmoothingMode(hDraw, TRUE);
		XDraw_SetBrushColor(hDraw, RGBA(128, 0, 0,255));

		int left = rc.left + m_time_pos / (float)m_time *400.0f;
		XDraw_DrawLine(hDraw, left, rcBorder_Line.top, left, rcBorder_Line.bottom);
		XDraw_DrawCurveF(hDraw, pts, m_time + 1, 0.5);
		return 0;
	}
};

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
	XInitXCGUI(TRUE);
	CMyWindowDemo  MyWindow;
	XRunXCGUI();
	XExitXCGUI();
	return 0;
}
