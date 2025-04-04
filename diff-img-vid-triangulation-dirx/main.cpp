#include "common.h"
#include "Image.h"
#include "D3D.h"
#include "Triangulator.h"
#include <Windows.h>
#include <Eigen/Dense>


D3D* d3d;
ImageView* imageView = NULL;
Triangulator* triangulator = NULL;
const float clear_color[] = { 1.0f, 1.0f, 1.0f, 1.0f };

LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) 
{
	switch (msg)
	{
	case WM_DESTROY:
		PostQuitMessage(0);
		break;
	default:
		return DefWindowProc(hWnd, msg, wParam, lParam);
	}
	return 0;
}

HRESULT initializeWindow(HINSTANCE hInstance, HWND& hWnd, int nCmdShow, int width, int height) 
{
	const auto className = L"imgvid_triangulation";
	//register window class
	WNDCLASSEX wcex = { 0 };
	wcex.cbSize = sizeof(wcex);
	wcex.style = CS_HREDRAW | CS_VREDRAW;
	wcex.lpfnWndProc = WndProc;
	wcex.cbClsExtra = 0;
	wcex.cbWndExtra = 0;
	wcex.hInstance = hInstance;
	wcex.hIcon = nullptr;
	wcex.hCursor = nullptr;
	wcex.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
	wcex.lpszMenuName = nullptr;
	wcex.lpszClassName = className;
	wcex.hIconSm = nullptr;
	RegisterClassEx(&wcex);

	//create window instance
	RECT rct = { 0, 0, width, height };
	AdjustWindowRect(&rct, WS_OVERLAPPEDWINDOW, FALSE);
	hWnd = CreateWindowEx(0, className, L"Triangulation", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
		rct.right - rct.left, rct.bottom - rct.top, nullptr, nullptr, hInstance, nullptr);

	if (!hWnd) return E_FAIL;

	ShowWindow(hWnd, nCmdShow);

	return S_OK;
}

int CALLBACK WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
	//cv::Mat img = cv::imread(__argv[1], cv::IMREAD_COLOR);
	AllocConsole();
	FILE* pCout;
	freopen_s(&pCout, "CONOUT$", "w", stdout);
	std::cout << "Hi" << std::endl;

	Image image(__argv[1]);
	int width = image.getWidth();
	int height = image.getHeight();

	imageView = new ImageView(width, height);
	imageView->setImage(&image);

	HWND hWnd;
	if (FAILED(initializeWindow(hInstance, hWnd, nCmdShow, width, height))) return -1;


	d3d = new D3D(hWnd);
	if (!d3d->initialize()) return -1;

	triangulator = new Triangulator(imageView, d3d, 650);
	if (!triangulator->create(d3d->getDevice())) return -1;
	imageView->create(d3d->getDevice());

	MSG msg = { 0 };
	while (WM_QUIT != msg.message) 
	{
		if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) 
		{
			TranslateMessage(&msg);
			DispatchMessage(&msg);
		}
		//d3d->ClearBuffer((float)img.at<cv::Vec3b>(cv::Point(10, 10))[0]/255, (float)img.at<cv::Vec3b>(cv::Point(100, 100))[1]/255, (float)img.at<cv::Vec3b>(cv::Point(10, 10))[2]/255);
		
		ID3D11DeviceContext* immediateContext = d3d->getImmediateContext();
		ID3D11RenderTargetView* renderTargetView = d3d->getRenderTargetView_Backbuffer();
		ID3D11DepthStencilView* depthStencilView = d3d->getDepthStencilView_Backbuffer();

		immediateContext->ClearRenderTargetView(renderTargetView, clear_color);
		immediateContext->ClearDepthStencilView(depthStencilView, D3D11_CLEAR_DEPTH, 1, 0);
		
		triangulator->draw(immediateContext, en_constant);
		d3d->EndFrame();
		double a = 10;
	}

	SAFE_DELETE(imageView);
	SAFE_DELETE(triangulator);
	SAFE_DELETE(d3d);
	return 0;
}