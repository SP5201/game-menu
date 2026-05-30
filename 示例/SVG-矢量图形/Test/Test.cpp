// Test.cpp : 定义应用程序的入口点。
//

#include "stdafx.h"
#include "Test.h"
#include <vector>

//包含炫彩界面库文件
#include "../../../DLL/xcgui.h"
#pragma comment(lib,"../../../DLL/XCGUI.lib")


class CWindow_Demo
{
public:
	HWINDOW m_hWindow;
	HIMAGE  m_hImage;
	HELE  m_hEle;
	std::vector<HSVG>  _list;
	CWindow_Demo()
	{
		m_hImage = NULL;
		Init();
	}
	void Exit()
	{
		for (auto hSvg : _list)
			XSvg_Release(hSvg);
		if (m_hImage && XC_IsHXCGUI(m_hImage, XC_IMAGE_FRAME))
			XImage_Release(m_hImage);
	}
	void Init()
	{
		//1450
		m_hWindow = XWnd_Create(0, 0, 550, 500, L"炫彩界面库窗口", NULL, window_style_default);
		XWnd_EnableDragWindow(m_hWindow, TRUE);
#if 0
		HELE hButton = XBtn_Create(200, 50, 120, 30, L"测试SVG图标", m_hWindow);
		m_hImage = XImage_LoadSvgFile(L"svg\\play.svg");
		XSvg_SetSize(XImage_GetSvg(m_hImage), 24, 24);
		XBtn_SetIcon(hButton, m_hImage);

		hButton = XBtn_Create(200, 100, 120, 30, L"测试SVG图标", m_hWindow);
		m_hImage = XImage_LoadSvgFile(L"svg\\时间戳.svg");
		XSvg_SetSize(XImage_GetSvg(m_hImage), 24, 24);
		XBtn_SetIcon(hButton, m_hImage);

		hButton = XBtn_Create(200, 150, 120, 30, L"测试SVG图标", m_hWindow);
		m_hImage = XImage_LoadSvgFile(L"svg\\量子统计.svg");
		XSvg_SetSize(XImage_GetSvg(m_hImage), 24, 24);
		XBtn_SetIcon(hButton, m_hImage);

		hButton = XBtn_Create(200, 200, 120, 30, L"测试SVG图标", m_hWindow);
		m_hImage = XImage_LoadSvgFile(L"svg\\图标-保存.svg");
		XSvg_SetSize(XImage_GetSvg(m_hImage), 24, 24);
		XBtn_SetIcon(hButton, m_hImage);

		hButton = XBtn_Create(200, 250, 120, 30, L"测试SVG图标", m_hWindow);
		m_hImage = XImage_LoadSvgFile(L"svg\\test-border.svg");
		XSvg_SetSize(XImage_GetSvg(m_hImage), 24, 24);
		XBtn_SetIcon(hButton, m_hImage);
		//--------------------------
		hButton = XBtn_Create(350, 50, 100, 100, L"测试SVG图标", m_hWindow);
		m_hImage = XImage_LoadSvgFile(L"svg\\时间戳.svg");
		XSvg_SetSize(XImage_GetSvg(m_hImage), 100, 100);
		//	XBtn_SetIcon(hButton, m_hImage);
		XEle_AddBkFill(hButton, element_state_flag_leave, COLORREF_MAKE(200, 200, 200, 255));
		XEle_AddBkImage(hButton, element_state_flag_leave, m_hImage);

		hButton = XBtn_Create(350, 160, 100, 100, L"测试SVG图标", m_hWindow);
		m_hImage = XImage_LoadSvgFile(L"svg\\图标-保存.svg");
		XSvg_SetSize(XImage_GetSvg(m_hImage), 100, 100);
		//	XBtn_SetIcon(hButton, m_hImage);
		XEle_AddBkFill(hButton, element_state_flag_leave, COLORREF_MAKE(200, 200, 200, 255));
		XEle_AddBkImage(hButton, element_state_flag_leave, m_hImage);

		HSVG hSvg = XSvg_LoadFile(L"svg\\时间戳.svg"); if (hSvg) _list.push_back(hSvg);
#else
		HSVG hSvg = XSvg_LoadFile(L"svg\\时间戳.svg"); if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\公益.svg"); if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\查验.svg"); if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\底层架构.svg");	if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\技术服务.svg"); if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\接口配置.svg"); if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\图标-保存.svg");	if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\customer-service.svg");	if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\navigation.svg");	if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\play.svg");	if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\收藏夹.svg");	if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\鞋子.svg"); if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\淘公仔文字.svg"); if (hSvg) _list.push_back(hSvg);
		hSvg = XSvg_LoadFile(L"svg\\量子统计.svg"); if (hSvg) _list.push_back(hSvg);
#endif
		XWnd_RegEventCPP(m_hWindow, WM_PAINT, &CWindow_Demo::OnWndDrawWindow);
		XWnd_ShowWindow(m_hWindow, SW_SHOW);
	}

	//输出信息
	struct arc_out_
	{
		double  x;
		double  y;
		double  width;  //宽度
		double  height; //高度

		double  startAngle; //开始角度, 钟表盘3点方向为0度开始
		double  sweepAngle; //从开始角度计算, 绘制角度
	};

	int  OnWndDrawWindow(HDRAW hDraw, BOOL* pbHandled)
	{
		*pbHandled = TRUE;
		XWnd_DrawWindow(m_hWindow, hDraw);

		//	XDraw_SetBrushColor(hDraw, COLORREF_MAKE(200, 0, 0, 255));
	//	XDraw_DrawArc(hDraw, 50, 50, 120, 100, 0, 300);

	//	XSvg_SetSize(XImage_GetSvg(m_hImage), 100, 100);
	//	XDraw_Image(hDraw, m_hImage, 200, 50);

		int left = 20;
		int top = 50;
		for (auto hSvg : _list)
		{
			XDraw_DrawSvgEx(hDraw, hSvg, left, top, 100, 100); left += 100;
		}
		left = 20; top += (100 + 20);
		for (auto hSvg : _list)
		{
			XDraw_DrawSvgEx(hDraw, hSvg, left + (100 - 72) / 2, top, 72, 72); left += 100;
		}
		left = 20; top += (72 + 20);
		for (auto hSvg : _list)
		{
			XDraw_DrawSvgEx(hDraw, hSvg, left + (100 - 48) / 2, top, 48, 48); left += 100;
		}
		left = 20; top += (48 + 20);
		for (auto hSvg : _list)
		{
			XDraw_DrawSvgEx(hDraw, hSvg, left + +(100 - 32) / 2, top, 32, 32); left += 100;
		}
		left = 20; top += (32 + 20);
		for (auto hSvg : _list)
		{
			XDraw_DrawSvgEx(hDraw, hSvg, left + (100 - 24) / 2, top, 24, 24); left += 100;
		}
		return 0;
	}
};

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
	XInitXCGUI(TRUE);
	XC_ShowSvgFrame(TRUE);
	CWindow_Demo  MyWindow;
	XRunXCGUI();
	MyWindow.Exit();
	XExitXCGUI();
	return TRUE;
}