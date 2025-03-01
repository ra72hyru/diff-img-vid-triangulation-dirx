#include "D3D.h"

D3D::D3D(HWND hWnd) : phWnd(hWnd), pFactory(NULL),
									pDevice(NULL), 
									pImmediateContext(NULL),
									pSwapChain(NULL),
									pRenderTargetView_Texture(NULL),
									pRenderTargetView_Backbuffer(NULL),
									pDepthStencilView_Texture(NULL),
									pDepthStencilView_Backbuffer(NULL),
									pShaderResourceView_Backbuffer(NULL),
									mViewport(D3D11_VIEWPORT())
{
	/*DXGI_SWAP_CHAIN_DESC sd = { 0 };
	sd.BufferDesc.Width = 0;
	sd.BufferDesc.Height = 0;
	sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	sd.BufferDesc.RefreshRate.Numerator = 0;
	sd.BufferDesc.RefreshRate.Denominator = 0;
	sd.BufferDesc.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
	sd.BufferDesc.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;

	sd.SampleDesc.Count = 1;
	sd.SampleDesc.Quality = 0;
	sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT,
	sd.BufferCount = 1;

	sd.OutputWindow = phWnd;
	sd.Windowed = TRUE;
	sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

	HRESULT hr;
	hr = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_DEBUG, 
										nullptr, 0, D3D11_SDK_VERSION, &sd, &pSwapChain, &pDevice, nullptr, &pImmediateContext);
	if (!FAILED(hr))
	{
		ID3D11Resource* pBackBuffer = nullptr;
		pSwapChain->GetBuffer(0, __uuidof(ID3D11Resource), reinterpret_cast<void**>(&pBackBuffer));
		pDevice->CreateRenderTargetView(pBackBuffer, nullptr, &pRenderTargetView_Backbuffer);
		pBackBuffer->Release();
	}*/
	
}

D3D::~D3D()
{
	releaseSwapChain();
	releaseDevice();
}

bool D3D::initialize() 
{
	if (!createDevice()) return false;
	if (!createSwapChain()) return false;

	return true;
}

bool D3D::createDevice()
{
	if (FAILED(CreateDXGIFactory(__uuidof(IDXGIFactory), (void**)&pFactory))) pFactory = NULL;

	HRESULT hr;

	hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, D3D11_CREATE_DEVICE_DEBUG, NULL, 0, D3D11_SDK_VERSION, &pDevice, NULL, &pImmediateContext);
	if (FAILED(hr)) return false;

	return true;
}

bool D3D::createSwapChain()
{
	HRESULT hr;

	RECT rc;
	GetClientRect(phWnd, &rc);
	UINT width = rc.right - rc.left;
	UINT height = rc.bottom - rc.top;

	DXGI_SWAP_CHAIN_DESC sd;
	ZeroMemory(&sd, sizeof(DXGI_SWAP_CHAIN_DESC));
	sd.BufferDesc.Width = width;
	sd.BufferDesc.Height = height;
	sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
	sd.BufferDesc.RefreshRate.Numerator = 0;
	sd.BufferDesc.RefreshRate.Denominator = 0;
	sd.BufferDesc.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
	sd.BufferDesc.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;

	sd.SampleDesc.Count = 1;
	sd.SampleDesc.Quality = 0;
	sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT,
	sd.BufferCount = 1;

	sd.OutputWindow = phWnd;
	sd.Windowed = TRUE;
	sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

	hr = pFactory->CreateSwapChain(pDevice, &sd, &pSwapChain);
	if (FAILED(hr)) return false;

	hr = pSwapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (LPVOID*)&pRenderTargetView_Texture);
	if (FAILED(hr)) return false;

	hr = pDevice->CreateRenderTargetView(pRenderTargetView_Texture, NULL, &pRenderTargetView_Backbuffer);
	if (FAILED(hr)) return false;


	D3D11_TEXTURE2D_DESC ds_desc;
	ZeroMemory(&ds_desc, sizeof(D3D11_TEXTURE2D_DESC));
	ds_desc.Width = width;
	ds_desc.Height = height;
	ds_desc.MipLevels = 1;
	ds_desc.ArraySize = 1;
	ds_desc.Format = DXGI_FORMAT_R32_TYPELESS;
	ds_desc.SampleDesc.Count = 1;
	ds_desc.SampleDesc.Quality = 0;
	ds_desc.Usage = D3D11_USAGE_DEFAULT;
	ds_desc.BindFlags = D3D11_BIND_DEPTH_STENCIL | D3D11_BIND_SHADER_RESOURCE;
	ds_desc.CPUAccessFlags = 0;
	ds_desc.MiscFlags = 0;

	hr = pDevice->CreateTexture2D(&ds_desc, NULL, &pDepthStencilView_Texture);
	if (FAILED(hr)) return false;

	D3D11_DEPTH_STENCIL_VIEW_DESC dsv_desc;
	ZeroMemory(&dsv_desc, sizeof(D3D11_DEPTH_STENCIL_VIEW_DESC));
	dsv_desc.Format = DXGI_FORMAT_D32_FLOAT;
	dsv_desc.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
	dsv_desc.Flags = 0;
	dsv_desc.Texture2D.MipSlice = 0;
	
	hr = pDevice->CreateDepthStencilView(pDepthStencilView_Texture, &dsv_desc, &pDepthStencilView_Backbuffer);
	if (FAILED(hr)) return false;

	D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc;
	ZeroMemory(&srv_desc, sizeof(D3D11_SHADER_RESOURCE_VIEW_DESC));
	srv_desc.Format = DXGI_FORMAT_R32_FLOAT;
	srv_desc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D;
	srv_desc.Texture2D.MostDetailedMip = 0;
	srv_desc.Texture2D.MipLevels = 1;

	hr = pDevice->CreateShaderResourceView(pDepthStencilView_Texture, &srv_desc, &pShaderResourceView_Backbuffer);
	if (FAILED(hr)) return false;

	ID3D11RenderTargetView* rt_views[] = { pRenderTargetView_Backbuffer };
	pImmediateContext->OMSetRenderTargets(1, rt_views, pDepthStencilView_Backbuffer);


	mViewport.TopLeftX = 0;
	mViewport.TopLeftY = 0;
	mViewport.Width = (FLOAT)width;
	mViewport.Height = (FLOAT)height;
	mViewport.MinDepth = 0.0f;
	mViewport.MaxDepth = 1.0f;

	pImmediateContext->RSSetViewports(1, &mViewport);

	return true;
}

void D3D::releaseDevice()
{
	if (pImmediateContext) pImmediateContext->ClearState();
	SAFE_RELEASE(pImmediateContext);
	SAFE_RELEASE(pFactory);
	SAFE_RELEASE(pDevice);
}

void D3D::releaseSwapChain()
{
	SAFE_RELEASE(pRenderTargetView_Texture);
	SAFE_RELEASE(pRenderTargetView_Backbuffer);
	SAFE_RELEASE(pDepthStencilView_Texture);
	SAFE_RELEASE(pDepthStencilView_Backbuffer);
	SAFE_RELEASE(pShaderResourceView_Backbuffer);
	SAFE_RELEASE(pSwapChain);
}

void D3D::EndFrame()
{
	pSwapChain->Present(1u, 0u);
}


