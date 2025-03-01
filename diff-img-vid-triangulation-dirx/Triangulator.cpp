#include "Triangulator.h"

Triangulator::Triangulator(ImageView* image, D3D* pD3D, int numTriangles) : image(image), d3d(pD3D),
								positions(),
								indices(),
								is_on_border(), 
								colors(),
								neighbor_list(),
								indices_in_neighbor_list(),
								neighbor_count(),
								pInputLayout(NULL),
								pVertexShader(NULL),
								pPixelShader(NULL),
								pComputeConstantColor(NULL),
								VSInput(),
								nTriangles(numTriangles)
{
	VSInput.buffer_content.projMatrix = image->getProjectionMatrix();

	CSInput.buffer_content.stepSize = 0.4;
	CSInput.buffer_content.width = image->getWidth();
	CSInput.buffer_content.height = image->getHeight();
	
	createRegularGrid();
	setRandomColors();
	//createTestVertices();
	//build_neighbors();
	//build_edges();
}

Triangulator::~Triangulator()
{
	release();
}

bool Triangulator::create(ID3D11Device* device)
{
	if (!VSInput.createBuffer(device)) return false;

	if (!CSInput.createBuffer(device)) return false;

	D3D11_INPUT_ELEMENT_DESC inputLayout_desc[] =
	{
		{ "POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0 },
	};


	ID3DBlob* pBlob_vs;
	ID3DBlob* pBlob_ps;
	ID3DBlob* pBlob_cs;
	HRESULT hr;

	//read and create vertex shader
	hr = D3DReadFileToBlob(L".\\shader\\VertexShader.cso", &pBlob_vs);
	if (FAILED(hr)) return false;
	
	hr = device->CreateVertexShader(pBlob_vs->GetBufferPointer(), pBlob_vs->GetBufferSize(), NULL, &pVertexShader);
	if (FAILED(hr)) return false;
	
	//read and create pixel shader
	hr = D3DReadFileToBlob(L".\\shader\\PixelShader.cso", &pBlob_ps);
	if (FAILED(hr)) return false;

	hr = device->CreatePixelShader(pBlob_ps->GetBufferPointer(), pBlob_ps->GetBufferSize(), NULL, &pPixelShader);
	if (FAILED(hr)) return false;
	
	//read and create ComputeConstantColor compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeConstantColor.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputeConstantColor);
	if (FAILED(hr)) return false;

	//read and create UpdatePositionsRTT compute shader
	hr = D3DReadFileToBlob(L".\\shader\\UpdatePositionsRTT.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pUpdatePositions_cc);
	if (FAILED(hr)) return false;

	//create input layout
	hr = device->CreateInputLayout(inputLayout_desc, 1, pBlob_vs->GetBufferPointer(), pBlob_vs->GetBufferSize(), &pInputLayout);
	if (FAILED(hr)) return false;
	

	//create buffers
	if (!positions.createBuffer(device, D3D11_BIND_VERTEX_BUFFER | D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!indices.createBuffer(device, D3D11_BIND_INDEX_BUFFER | D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!colors.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, 0)) return false;

	if (!neighbor_list.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!neighbor_count.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!indices_in_neighbor_list.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;


	//release blobs
	SAFE_RELEASE(pBlob_vs);
	SAFE_RELEASE(pBlob_ps);
	SAFE_RELEASE(pBlob_cs);
	return true;
}

void Triangulator::release()
{
	positions.releaseBuffer();
	indices.releaseBuffer();
	colors.releaseBuffer();
	neighbor_count.releaseBuffer();
	neighbor_list.releaseBuffer();
	indices_in_neighbor_list.releaseBuffer();
	VSInput.releaseBuffer();
	CSInput.releaseBuffer();

	SAFE_RELEASE(pVertexShader);
	SAFE_RELEASE(pPixelShader);
	SAFE_RELEASE(pComputeConstantColor);
	SAFE_RELEASE(pUpdatePositions_cc);
	SAFE_RELEASE(pInputLayout);
}

void Triangulator::draw(ID3D11DeviceContext* immediateContext)
{
	computeColors(immediateContext);
	updatePositions(immediateContext);
	computeColors(immediateContext);
	render(immediateContext);
}


void Triangulator::render(ID3D11DeviceContext* immediateContext)
{
	ID3D11Buffer* vertexBuffers[] = { positions.getBuffer() };
	UINT strides[] = { sizeof(Vec2f) };
	UINT offsets[] = { 0 };

	//set input assembler 
	immediateContext->IASetInputLayout(pInputLayout);
	immediateContext->IASetVertexBuffers(0, 1, vertexBuffers, strides, offsets);
	immediateContext->IASetIndexBuffer(indices.getBuffer(), DXGI_FORMAT_R32_UINT, 0);
	immediateContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

	//set shaders
	immediateContext->VSSetShader(pVertexShader, NULL, 0);
	immediateContext->PSSetShader(pPixelShader, NULL, 0);

	ID3D11Buffer* CB_VS[] = { VSInput.getBuffer() };
	immediateContext->VSSetConstantBuffers(0, 1, CB_VS);

	//set render target
	ID3D11RenderTargetView* rtviews[] = { d3d->getRenderTargetView_Backbuffer() };
	immediateContext->OMSetRenderTargets(1, rtviews, d3d->getDepthStencilView_Backbuffer());

	ID3D11ShaderResourceView* srvs[] = { colors.getShaderResourceView() };
	immediateContext->PSSetShaderResources(0, 1, srvs);


	//draw
	//immediatContext->Draw((UINT)sizeof(positions.buffer_content), 0);
	immediateContext->DrawIndexed((UINT)indices.buffer_content.size(), 0, 0);


	//cleanup
	ID3D11Buffer* clean_vb[] = { NULL };
	UINT clean_strides[] = { 0 };
	immediateContext->IASetVertexBuffers(0, 1, clean_vb, clean_strides, offsets);

	ID3D11ShaderResourceView* clean_srv[] = { NULL };
	immediateContext->PSSetShaderResources(0, 1, clean_srv);
}

void Triangulator::computeColors(ID3D11DeviceContext* immediateContext) 
{
	immediateContext->CSSetShader(pComputeConstantColor, NULL, 0);
	
	ID3D11ShaderResourceView* ccc_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, ccc_srv);

	ID3D11UnorderedAccessView* ccc_uav[] = { colors.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, ccc_uav, NULL);

	UINT groupsX = (UINT)colors.buffer_content.size();
	if (groupsX % 256 == 0)
		groupsX /= 256;
	else
		groupsX = groupsX / 256 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::updatePositions(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pUpdatePositions_cc, NULL, 0);

	ID3D11ShaderResourceView* up_srv[] = { indices.getShaderResourceView(), colors.getShaderResourceView(), 
											neighbor_list.getShaderResourceView(), indices_in_neighbor_list.getShaderResourceView(),
											neighbor_count.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 6, up_srv);

	ID3D11UnorderedAccessView* up_uav[] = { positions.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, up_uav, NULL);

	ID3D11Buffer* CB_CS[] = { CSInput.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	UINT groupsX = (UINT)positions.buffer_content.size();
	if (groupsX % 512 == 0)
		groupsX /= 512;
	else
		groupsX = groupsX / 512 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL, NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 6, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);

	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);
}

void Triangulator::createRegularGrid()
{
	const int GRID_SPACING_CONSTANT = (int)round(sqrt(nTriangles / 2));

	float x_spacing = (float)(image->getWidth()) / GRID_SPACING_CONSTANT;
	float y_spacing = (float)(image->getHeight()) / GRID_SPACING_CONSTANT;

	bool border = false;

	for (int j = 0; j <= GRID_SPACING_CONSTANT; j++)
	{
		for (int i = 0; i <= GRID_SPACING_CONSTANT; i++)
		{
			if (i == 0 || i == GRID_SPACING_CONSTANT || j == 0 || j == GRID_SPACING_CONSTANT) border = true;
			//Vec2f p = { 2.0f * (float)i * x_spacing / (float)img.getWidth() - 1.0f, 1.0f - 2.0f * (float)j * y_spacing / (float)img.getHeight() };
			//Vec2f p = { 2.0f * (float)i * x_spacing / (float)image->getWidth() - 1.0f, 1.0f - 2.0f * (float)j * y_spacing / (float)image->getHeight() };
			Vec2f p = { (float)i * x_spacing, (float)j * y_spacing };
			positions.buffer_content.push_back(p);
			is_on_border.buffer_content.push_back(border);

			if (i != GRID_SPACING_CONSTANT && j != GRID_SPACING_CONSTANT)
			{
				//first triangle in quad
				indices.buffer_content.push_back(j * GRID_SPACING_CONSTANT + j + i);
				indices.buffer_content.push_back(j * GRID_SPACING_CONSTANT + j + i + 1);
				indices.buffer_content.push_back((j + 1) * GRID_SPACING_CONSTANT + j + i + 2);

				//second triangle in quad
				indices.buffer_content.push_back(j * GRID_SPACING_CONSTANT + j + i);
				indices.buffer_content.push_back((j + 1) * GRID_SPACING_CONSTANT + j + i + 2);
				indices.buffer_content.push_back((j + 1) * GRID_SPACING_CONSTANT + j + i + 1);
			}

			border = false;
		}
	}

	nTriangles = 2 * GRID_SPACING_CONSTANT * GRID_SPACING_CONSTANT;
	buildNeighbors();
}

void Triangulator::buildNeighbors()
{
	size_t pos_size = positions.buffer_content.size();
	indices_in_neighbor_list.buffer_content.resize(pos_size);
	neighbor_count.buffer_content.resize(pos_size);

	for (int i = 0; i < pos_size; i++)
		neighbor_count.buffer_content[i] = 0;

	std::vector<std::list<unsigned int>> neighbors;
	neighbors.resize(positions.buffer_content.size());

	for (int i = 0; i < indices.buffer_content.size() / 3; i++) 
	{
		neighbors[indices.buffer_content[i * 3]].push_back(i);
		neighbor_count.buffer_content[indices.buffer_content[i * 3]] += 1;

		neighbors[indices.buffer_content[i * 3 + 1]].push_back(i);
		neighbor_count.buffer_content[indices.buffer_content[i * 3 + 1]] += 1;

		neighbors[indices.buffer_content[i * 3 + 2]].push_back(i);
		neighbor_count.buffer_content[indices.buffer_content[i * 3 + 2]] += 1;
	}
	for (int i = 0; i < pos_size; i++) 
	{
		for (unsigned int n : neighbors[i])
		{
			neighbor_list.buffer_content.push_back(n);
		}
	}

	indices_in_neighbor_list.buffer_content[0] = 0;
	for (unsigned int i = 1; i < pos_size; i++) 
	{
		indices_in_neighbor_list.buffer_content[i] = indices_in_neighbor_list.buffer_content[i - 1] + neighbor_count.buffer_content[i - 1];//<-----------------
	}
}

void Triangulator::createTestVertices()
{
	positions.buffer_content.push_back({0.0f, 0.5f});
	positions.buffer_content.push_back({0.5f, -0.5f});
	positions.buffer_content.push_back({-0.5f, -0.5f});
	indices.buffer_content.push_back(0);
	indices.buffer_content.push_back(1);
	indices.buffer_content.push_back(2);
}

void Triangulator::setRandomColors()
{
	srand(time(NULL));
	for (int i = 0; i < nTriangles; i++)
	{
		colors.buffer_content.push_back({ ((float)(rand() % 255)) / 255.0f, ((float)(rand() % 255)) / 255.0f , ((float)(rand() % 255)) / 255.0f });
	}
}
