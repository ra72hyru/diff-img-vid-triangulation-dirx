#pragma once

#include <D3D11.h>
#include <DXGI.h>
#include <d3dcompiler.h>
#include "common.h"

class D3D 
{
	public:
		D3D(HWND hWnd);
		~D3D();

		bool initialize();

		bool createDevice();
		bool createSwapChain();

		void releaseDevice();
		void releaseSwapChain();

		ID3D11Device* getDevice() { return pDevice; };
		ID3D11DeviceContext* getImmediateContext() { return pImmediateContext; };
		IDXGISwapChain* getSwapChain() { return pSwapChain; };

		ID3D11RenderTargetView* getRenderTargetView_Backbuffer() { return pRenderTargetView_Backbuffer; };
		ID3D11DepthStencilView* getDepthStencilView_Backbuffer() { return pDepthStencilView_Backbuffer; };
		ID3D11ShaderResourceView* getShaderResourceView_Backbuffer() { return pShaderResourceView_Backbuffer; };

		void EndFrame();
		void ClearBuffer(float r, float g, float b) 
		{
			const float color[] = { r, g, b, 1.0f };
			pImmediateContext->ClearRenderTargetView(pRenderTargetView_Backbuffer, color);
		};
	private:
		HWND phWnd;

		IDXGIFactory* pFactory;

		ID3D11Device* pDevice;
		ID3D11DeviceContext* pImmediateContext;
		IDXGISwapChain* pSwapChain;

		ID3D11Texture2D* pRenderTargetView_Texture;
		ID3D11RenderTargetView* pRenderTargetView_Backbuffer;
		ID3D11Texture2D* pDepthStencilView_Texture;
		ID3D11DepthStencilView* pDepthStencilView_Backbuffer;
		ID3D11ShaderResourceView* pShaderResourceView_Backbuffer;

		D3D11_VIEWPORT mViewport;
};

template<typename T>
class SharedByteAddressBuffer 
{
	public:
		SharedByteAddressBuffer() : pBuffer(NULL), pStaging(NULL), pDynamic(NULL), pShaderResourceView(NULL), pUnorderedAccessView(NULL), byte_width(0), bind_flags(0), CPUaccess_flags(0)
		{
		}

		bool createBuffer(ID3D11Device* device, UINT bindFlags, UINT CPUaccessFlags) 
		{
			byte_width = calculateByteWidth();
			
			bind_flags = bindFlags;
			CPUaccess_flags = CPUaccessFlags;

			D3D11_BUFFER_DESC buf_desc;
			ZeroMemory(&buf_desc, sizeof(D3D11_BUFFER_DESC));
			buf_desc.ByteWidth = (UINT)(byte_width);
			buf_desc.Usage = D3D11_USAGE_DEFAULT;
			buf_desc.BindFlags = bindFlags;
			buf_desc.CPUAccessFlags = 0;
			buf_desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_ALLOW_RAW_VIEWS;

			D3D11_SUBRESOURCE_DATA initData;
			ZeroMemory(&initData, sizeof(D3D11_SUBRESOURCE_DATA));

			std::vector<char> data(byte_width);
			memcpy_s(data.data(), byte_width, buffer_content.data(), byte_width);
			initData.pSysMem = data.data();

			HRESULT hr;

			hr = device->CreateBuffer(&buf_desc, &initData, &pBuffer);
			if (FAILED(hr)) return false;


			if ((bindFlags & D3D11_BIND_SHADER_RESOURCE) != 0) 
			{
				D3D11_SHADER_RESOURCE_VIEW_DESC srv_desc;
				ZeroMemory(&srv_desc, sizeof(D3D11_SHADER_RESOURCE_VIEW_DESC));
				srv_desc.Format = DXGI_FORMAT_R32_TYPELESS;
				srv_desc.ViewDimension = D3D11_SRV_DIMENSION_BUFFEREX;
				srv_desc.BufferEx.FirstElement = 0;
				srv_desc.BufferEx.NumElements = (UINT)byte_width / 4;
				srv_desc.BufferEx.Flags = D3D11_BUFFEREX_SRV_FLAG_RAW;
				
				hr = device->CreateShaderResourceView(pBuffer, &srv_desc, &pShaderResourceView);
				if (FAILED(hr)) return false;
			}

			if ((bindFlags & D3D11_BIND_UNORDERED_ACCESS) != 0) 
			{
				D3D11_UNORDERED_ACCESS_VIEW_DESC uav_desc;
				ZeroMemory(&uav_desc, sizeof(D3D11_UNORDERED_ACCESS_VIEW_DESC));
				uav_desc.Format = DXGI_FORMAT_R32_TYPELESS;
				uav_desc.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
				uav_desc.Buffer.FirstElement = 0;
				uav_desc.Buffer.NumElements = (UINT)byte_width / 4;
				uav_desc.Buffer.Flags = D3D11_BUFFER_UAV_FLAG_RAW;

				hr = device->CreateUnorderedAccessView(pBuffer, &uav_desc, &pUnorderedAccessView);
				if (FAILED(hr)) return false;
			}

			if ((CPUaccessFlags & D3D11_CPU_ACCESS_READ) != 0) 
			{
				buf_desc.Usage = D3D11_USAGE_STAGING;
				buf_desc.BindFlags = 0;
				buf_desc.MiscFlags = 0;
				buf_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

				hr = device->CreateBuffer(&buf_desc, NULL, &pStaging);
				if (FAILED(hr)) return false;
			}

			if ((CPUaccessFlags & D3D11_CPU_ACCESS_WRITE) != 0)
			{
				buf_desc.Usage = D3D11_USAGE_DYNAMIC;
				buf_desc.BindFlags = D3D11_BIND_VERTEX_BUFFER; //does not work with 0??
				buf_desc.MiscFlags = 0;
				buf_desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

				hr = device->CreateBuffer(&buf_desc, NULL, &pDynamic);
				if (FAILED(hr)) return false;
			}
			return true;
		};

		void releaseBuffer() 
		{
			SAFE_RELEASE(pShaderResourceView);
			SAFE_RELEASE(pUnorderedAccessView);
			SAFE_RELEASE(pBuffer);
			SAFE_RELEASE(pStaging);
			SAFE_RELEASE(pDynamic);
		};

		void gpuToCpu(ID3D11DeviceContext* immediateContext) 
		{
			immediateContext->CopyResource(pStaging, pBuffer);

			int numElements = (int)buffer_content.size() * sizeof(T);
			D3D11_MAPPED_SUBRESOURCE mapped_subresource;

			HRESULT hr;
			hr = immediateContext->Map(pStaging, 0, D3D11_MAP_READ, 0, &mapped_subresource);

			if (SUCCEEDED(hr)) 
			{
				memcpy_s(buffer_content.data(), numElements, mapped_subresource.pData, numElements);
				immediateContext->Unmap(pStaging, 0);
			}
		};

		void cpuToGpu(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
		{
			if (buffer_content.size() * sizeof(T) < byte_width) 
			{
				int numElements = (int)buffer_content.size() * sizeof(T);
				D3D11_MAPPED_SUBRESOURCE mapped_subresource;

				HRESULT hr;
				hr = immediateContext->Map(pDynamic, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped_subresource);

				if (SUCCEEDED(hr)) 
				{
					memcpy_s(mapped_subresource.pData, numElements, buffer_content.data(), numElements);
					immediateContext->Unmap(pDynamic, 0);
				}
				immediateContext->CopyResource(pBuffer, pDynamic);
			}
			else 
			{
				releaseBuffer();
				createBuffer(device, bind_flags, CPUaccess_flags);
			}
		};

		ID3D11Buffer* getBuffer() { return pBuffer; };
		ID3D11Buffer* getStagingBuffer() { return pStaging; };
		ID3D11Buffer* getDynamic() { return pDynamic; };
		ID3D11ShaderResourceView* getShaderResourceView() { return pShaderResourceView; };
		ID3D11UnorderedAccessView* getUnorderedAccessView() { return pUnorderedAccessView; };

		std::vector<T> buffer_content;
	private:
		size_t calculateByteWidth() const 
		{
			size_t i = 1; 
			while (i < buffer_content.size() * sizeof(T)) { i *= 2; }
			return i;
		};

		size_t byte_width;

		UINT bind_flags;
		UINT CPUaccess_flags;

		ID3D11Buffer* pBuffer;
		ID3D11Buffer* pStaging;
		ID3D11Buffer* pDynamic;

		ID3D11ShaderResourceView* pShaderResourceView;
		ID3D11UnorderedAccessView* pUnorderedAccessView;
};

template <typename T>
class ConstantBuffer 
{
	public:
		ConstantBuffer() : buffer_content(), pBuffer(NULL) 
		{
		}

		bool createBuffer(ID3D11Device* device) 
		{
			size_t byte_width = sizeof(T);
			if ((byte_width & 15) != 0)
			{
				byte_width >>= 4;					//
				byte_width++;						//awesome way to do this :D +++https://github.com/tobguent/image-triangulation/blob/master/demo/D3D.h+++ 
				byte_width <<= 4;					//
			}

			D3D11_BUFFER_DESC buf_desc;
			ZeroMemory(&buf_desc, sizeof(D3D11_BUFFER_DESC));
			buf_desc.ByteWidth = (UINT)(byte_width);
			buf_desc.Usage = D3D11_USAGE_DYNAMIC;
			buf_desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
			buf_desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
			buf_desc.MiscFlags = 0;

			D3D11_SUBRESOURCE_DATA initData;
			ZeroMemory(&initData, sizeof(D3D11_SUBRESOURCE_DATA));

			initData.pSysMem = &buffer_content;

			HRESULT hr;

			hr = device->CreateBuffer(&buf_desc, &initData, &pBuffer);
			if (FAILED(hr)) return false;

			return true;
		};

		void releaseBuffer()
		{
			SAFE_RELEASE(pBuffer);
		};

		ID3D11Buffer* getBuffer() { return pBuffer; };

		T buffer_content;
	private:
		ID3D11Buffer* pBuffer;
};
