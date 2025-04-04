#include "Triangulator.h"

Triangulator::Triangulator(ImageView* image, D3D* pD3D, int numTriangles) : image(image), d3d(pD3D),
								positions(),
								indices(),
								is_on_border(), 
								gradientCoefficients(),
								colors(),
								neighbor_list(),
								indices_in_neighbor_list(),
								neighbor_count(),
								gradients_rtt(),
								gradients_fin_diff(),
								pInputLayout(NULL),
								pVertexShader(NULL),
								pPixelShader(NULL),
								pPSLinearGradients(NULL),
								pComputeConstantColor(NULL),
								pComputeLinearGradients(NULL),
								pCCC_bi_interp(NULL),
								pCLG_bi_interp(NULL),
								pComputeGradients_rtt(NULL),
								pComputeGradients_cplg(NULL),
								pUpdatePositions_cc(NULL),
								pFiniteDifferences(NULL),
								pUpdatePositions_fin_diff(NULL),
								VSInput(),
								nTriangles(numTriangles),
								delaunayEveryNthIteration(10),
								delaunayUntilNthIteration(100)
{
	VSInput.buffer_content.projMatrix = image->getProjectionMatrix();

	CSInput.buffer_content.stepSize = 0.4f;
	CSInput.buffer_content.width = image->getWidth();
	CSInput.buffer_content.height = image->getHeight();

	CSfin_diff_Input.buffer_content.eps = 1;
	CSfin_diff_Input.buffer_content.dxA = 1;
	CSfin_diff_Input.buffer_content.dxB = 0;
	CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyA = 0;
	CSfin_diff_Input.buffer_content.dyB = 0;
	CSfin_diff_Input.buffer_content.dyC = 0;
	
#if 0 
	testing(d3d->getImmediateContext());
#else
	createRegularGrid();
	setRandomColors();
	initializeTriangleGradients();
	//546, 51
	std::cout << positions.buffer_content[indices.buffer_content[51 * 3]].x << " " << positions.buffer_content[indices.buffer_content[51 * 3]].y << std::endl;
	std::cout << positions.buffer_content[indices.buffer_content[51 * 3 + 1]].x << " " << positions.buffer_content[indices.buffer_content[51 * 3 + 1]].y << std::endl;
	std::cout << positions.buffer_content[indices.buffer_content[51 * 3 + 2]].x << " " << positions.buffer_content[indices.buffer_content[51 * 3 + 2]].y << std::endl;
	std::cout << positions.buffer_content[indices.buffer_content[51 * 3 + 2]].x - positions.buffer_content[indices.buffer_content[51 * 3 ]].x << std::endl;
	std::cout << positions.buffer_content[indices.buffer_content[51 * 3 + 2]].y - positions.buffer_content[indices.buffer_content[51 * 3 ]].y << std::endl;
	
	//createTestVertices();
	//build_neighbors();
	//build_edges();
#endif
}

Triangulator::~Triangulator()
{
	release();
}

bool Triangulator::create(ID3D11Device* device)
{
	if (!VSInput.createBuffer(device)) return false;

	if (!CSInput.createBuffer(device)) return false;

	if (!CSfin_diff_Input.createBuffer(device)) return false;

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
	

	//read and create pixel shaders
	hr = D3DReadFileToBlob(L".\\shader\\PixelShader.cso", &pBlob_ps);
	if (FAILED(hr)) return false;

	hr = device->CreatePixelShader(pBlob_ps->GetBufferPointer(), pBlob_ps->GetBufferSize(), NULL, &pPixelShader);
	if (FAILED(hr)) return false;
	
	hr = D3DReadFileToBlob(L".\\shader\\PSLinearGradients.cso", &pBlob_ps);
	if (FAILED(hr)) return false;

	hr = device->CreatePixelShader(pBlob_ps->GetBufferPointer(), pBlob_ps->GetBufferSize(), NULL, &pPSLinearGradients);
	if (FAILED(hr)) return false;

	//read and create ComputeConstantColor compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeConstantColor.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputeConstantColor);
	if (FAILED(hr)) return false;

	//read and create ComputeLinearGradients compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeLinearGradients.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputeLinearGradients);
	if (FAILED(hr)) return false;

	//read and create ComputeConstantColors_bilinearly_interpolated compute shader
	hr = D3DReadFileToBlob(L".\\shader\\CCC_bi_interp.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pCCC_bi_interp);
	if (FAILED(hr)) return false;

	//read and create ComputeLinearGradients_bilinearly_interpolated compute shader
	hr = D3DReadFileToBlob(L".\\shader\\CLG_bi_interp.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pCLG_bi_interp);
	if (FAILED(hr)) return false;

	//read and create ComputeGradient_cpct compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeGradient_cpct.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputeGradients_rtt);
	if (FAILED(hr)) return false;

	//read and create ComputeGradient_cplg compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeGradient_cplg.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputeGradients_cplg);
	if (FAILED(hr)) return false;

	//read and create UpdatePositionsRTT compute shader
	hr = D3DReadFileToBlob(L".\\shader\\UpdatePositionsRTT.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pUpdatePositions_cc);
	if (FAILED(hr)) return false;

	//read and create FiniteDifferences compute shader
	hr = D3DReadFileToBlob(L".\\shader\\FiniteDifferences.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pFiniteDifferences);
	if (FAILED(hr)) return false;

	//read and create UpdatePositionsFinDiff compute shader
	hr = D3DReadFileToBlob(L".\\shader\\UpdatePositionsFinDiff.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pUpdatePositions_fin_diff);
	if (FAILED(hr)) return false;


	//create input layout
	hr = device->CreateInputLayout(inputLayout_desc, 1, pBlob_vs->GetBufferPointer(), pBlob_vs->GetBufferSize(), &pInputLayout);
	if (FAILED(hr)) return false;
	

	//create buffers
	if (!positions.createBuffer(device, D3D11_BIND_VERTEX_BUFFER | D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!indices.createBuffer(device, D3D11_BIND_INDEX_BUFFER | D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!colors.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, 0)) return false;

	if (!gradientCoefficients.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ)) return false; //TODO: remove cpu access

	if (!neighbor_list.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!neighbor_count.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!indices_in_neighbor_list.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!gradients_rtt.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ)) return false;

	if (!gradients_fin_diff.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ)) return false;


	//compute colors once before positions get updated
	computeConstantColors(d3d->getImmediateContext());
	computeLinearGradients(d3d->getImmediateContext());


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
	gradientCoefficients.releaseBuffer();
	neighbor_count.releaseBuffer();
	neighbor_list.releaseBuffer();
	indices_in_neighbor_list.releaseBuffer();
	gradients_rtt.releaseBuffer();
	gradients_fin_diff.releaseBuffer();
	VSInput.releaseBuffer();
	CSInput.releaseBuffer();
	CSfin_diff_Input.releaseBuffer();

	SAFE_RELEASE(pVertexShader);
	SAFE_RELEASE(pPixelShader);
	SAFE_RELEASE(pPSLinearGradients);
	SAFE_RELEASE(pComputeConstantColor);
	SAFE_RELEASE(pComputeLinearGradients);
	SAFE_RELEASE(pCCC_bi_interp);
	SAFE_RELEASE(pCLG_bi_interp);
	SAFE_RELEASE(pComputeGradients_rtt);
	SAFE_RELEASE(pComputeGradients_cplg);
	SAFE_RELEASE(pUpdatePositions_cc);
	SAFE_RELEASE(pUpdatePositions_fin_diff);
	SAFE_RELEASE(pFiniteDifferences);
	SAFE_RELEASE(pInputLayout);
}

void Triangulator::print_areas(ID3D11DeviceContext* immediateContext) 
{
	positions.gpuToCpu(immediateContext);
	for (int i = 0; i < indices.buffer_content.size() / 3; i++) 
	{
		float area = tri_area(positions.buffer_content[indices.buffer_content[i * 3]], positions.buffer_content[indices.buffer_content[i * 3 + 1]], positions.buffer_content[indices.buffer_content[i * 3 + 2]]);
		if (area < 10)
			std::cout << "triangle " << i << " area: " << area << std::endl;
		std::flush(std::cout);
	}
}

void Triangulator::draw(ID3D11DeviceContext* immediateContext, RenderMode mode)
{
	//computeColors(immediateContext);
	static int iteration = 0;
	iteration++;
	if ((iteration % delaunayEveryNthIteration) == 0 && delaunayUntilNthIteration > iteration)
	{
		delaunay(d3d->getDevice(), immediateContext);
		std::cout << "delaunay done" << std::endl;
		std::flush(std::cout);
	}

	if (mode == en_constant) 
	{
#if 1	
		if (iteration < 1210) 
		{
			//computeGradients_rtt(immediateContext);
			finite_differences(immediateContext);
			std::cout << "gradients computed" << std::endl;
			//updatePositions(immediateContext);
			updatePositions_fin_diff(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		//if (iteration > 50)
		/*{
			gradients_rtt.gpuToCpu(immediateContext);
			for (int i = 0; i < gradients_rtt.buffer_content.size(); i++)
			{
				std::cout << "Triangle " << i << " gradient_x when moving C : " << gradients_rtt.buffer_content[i].grABCx << std::endl;
			}
		}*/
		//print_areas(immediateContext);
		if (eliminate_degenerate_triangles(d3d->getDevice(), immediateContext))
		{
			std::cout << "eliminated at least one triangle" << std::endl;
			//Sleep(1000);
			std::cout << "sleeping end" << std::endl;
		}
#endif
		computeConstantColors(immediateContext);
		//ccc_bi_interp(immediateContext);
		render(immediateContext, mode);
		//if (iteration > 10)
			//Sleep(500);
	}
	else if (mode == en_linear) 
	{
		//updatePositions_linGrad(immediateContext);
		//computeLinearGradients(immediateContext);
		clg_bi_interp(immediateContext);

		if (iteration < -121)
		{
			computeGradients_cplg(immediateContext);
			std::cout << "gradients computed" << std::endl;
			updatePositions(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		//computeLinearGradients(immediateContext);
		//clg_bi_interp(immediateContext);

		gradientCoefficients.gpuToCpu(immediateContext);
		//std::cout << gradientCoefficients.buffer_content[51].r_b << std::endl;
		std::cout << "Triangle 51 - R_a " << gradientCoefficients.buffer_content[51].r_a << std::endl;
		std::cout << "Triangle 51 - R_b " << gradientCoefficients.buffer_content[51].r_b << std::endl;
		std::cout << "Triangle 51 - R_c " << gradientCoefficients.buffer_content[51].r_c << std::endl;
		std::cout << "Triangle 51 - G_a " << gradientCoefficients.buffer_content[51].g_a << std::endl;
		std::cout << "Triangle 51 - G_b " << gradientCoefficients.buffer_content[51].g_b << std::endl;
		std::cout << "Triangle 51 - G_c " << gradientCoefficients.buffer_content[51].g_c << std::endl;
		std::cout << "Triangle 51 - B_a " << gradientCoefficients.buffer_content[51].b_a << std::endl;
		std::cout << "Triangle 51 - B_b " << gradientCoefficients.buffer_content[51].b_b << std::endl;
		std::cout << "Triangle 51 - B_c " << gradientCoefficients.buffer_content[51].b_c << std::endl;
		render(immediateContext, mode);
	}
	
	std::cout << iteration << " cycle(s) done" << std::endl;
}


void Triangulator::render(ID3D11DeviceContext* immediateContext, RenderMode mode)
{
	ID3D11Buffer* vertexBuffers[] = { positions.getBuffer() };
	UINT strides[] = { sizeof(Vec2f) };
	UINT offsets[] = { 0 };

	//set input assembler 
	immediateContext->IASetInputLayout(pInputLayout);
	immediateContext->IASetVertexBuffers(0, 1, vertexBuffers, strides, offsets);
	immediateContext->IASetIndexBuffer(indices.getBuffer(), DXGI_FORMAT_R32_UINT, 0);
	immediateContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

	//set shaders and shader resources
	immediateContext->VSSetShader(pVertexShader, NULL, 0);
	if (mode == en_constant) 
	{
		immediateContext->PSSetShader(pPixelShader, NULL, 0);
		ID3D11ShaderResourceView* srvs[] = { colors.getShaderResourceView() };
		immediateContext->PSSetShaderResources(0, 1, srvs);
	}
	else if (mode == en_linear) 
	{
		immediateContext->PSSetShader(pPSLinearGradients, NULL, 0);
		ID3D11ShaderResourceView* srvs[] = { gradientCoefficients.getShaderResourceView() };
		immediateContext->PSSetShaderResources(0, 1, srvs);
	}

	ID3D11Buffer* CB_VS[] = { VSInput.getBuffer() };
	immediateContext->VSSetConstantBuffers(0, 1, CB_VS);

	//set render target
	ID3D11RenderTargetView* rtviews[] = { d3d->getRenderTargetView_Backbuffer() };
	immediateContext->OMSetRenderTargets(1, rtviews, d3d->getDepthStencilView_Backbuffer());
	//immediateContext->RSSetState();

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

void Triangulator::computeConstantColors(ID3D11DeviceContext* immediateContext) 
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

void Triangulator::computeLinearGradients(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputeLinearGradients, NULL, 0);

	ID3D11ShaderResourceView* ccc_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, ccc_srv);

	ID3D11UnorderedAccessView* ccc_uav[] = { gradientCoefficients.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, ccc_uav, NULL);

	//UINT groupsX = (UINT)colors.buffer_content.size();
	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 128 == 0)
		groupsX /= 128;
	else
		groupsX = groupsX / 128 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::ccc_bi_interp(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pCCC_bi_interp, NULL, 0);

	ID3D11ShaderResourceView* ccc_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, ccc_srv);

	ID3D11UnorderedAccessView* ccc_uav[] = { colors.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, ccc_uav, NULL);

	UINT groupsX = (UINT)colors.buffer_content.size();
	if (groupsX % 128 == 0)
		groupsX /= 128;
	else
		groupsX = groupsX / 128 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::clg_bi_interp(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pCLG_bi_interp, NULL, 0);

	ID3D11ShaderResourceView* ccc_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, ccc_srv);

	ID3D11UnorderedAccessView* ccc_uav[] = { gradientCoefficients.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, ccc_uav, NULL);

	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 128 == 0)
		groupsX /= 128;
	else
		groupsX = groupsX / 128 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::computeGradients_rtt(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputeGradients_rtt, NULL, 0);

	ID3D11ShaderResourceView* cg_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), colors.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 4, cg_srv);

	ID3D11UnorderedAccessView* cg_uav[] = { gradients_rtt.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, cg_uav, NULL);


	UINT groupsX = (UINT)indices.buffer_content.size() / 3;//(UINT)gradients_rtt.buffer_content.size();
	if (groupsX % 512 == 0)
		groupsX /= 512;
	else
		groupsX = groupsX / 512 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 4, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::computeGradients_cplg(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputeGradients_cplg, NULL, 0);

	ID3D11ShaderResourceView* cg_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), gradientCoefficients.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 4, cg_srv);

	ID3D11UnorderedAccessView* cg_uav[] = { gradients_rtt.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, cg_uav, NULL);


	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 512 == 0)
		groupsX /= 512;
	else
		groupsX = groupsX / 512 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 4, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::finite_differences(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pFiniteDifferences, NULL, 0);//TODO: beide funktionen, updatePositions_fin_diff.hlsl, srvs und uavs, buffer f¸r Farben von verschobenen Dreiecken

	ID3D11ShaderResourceView* up_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, up_srv);

	ID3D11UnorderedAccessView* up_uav[] = { gradients_fin_diff.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, up_uav, NULL);

	CSfin_diff_Input.buffer_content.dxA = 1; CSfin_diff_Input.buffer_content.dxB = 0; CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyA = 0; CSfin_diff_Input.buffer_content.dyB = 0; CSfin_diff_Input.buffer_content.dyC = 0;
	CSfin_diff_Input.buffer_content.eps = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 256 == 0)
		groupsX /= 256;
	else
		groupsX = groupsX / 256 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);											//dxA
	//TODO: UpdateBuffer

	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxA = 0;
	CSfin_diff_Input.buffer_content.dyA = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyA

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyA = 0;
	CSfin_diff_Input.buffer_content.dxB = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxB

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxB = 0;
	CSfin_diff_Input.buffer_content.dyB = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyB

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyB = 0;
	CSfin_diff_Input.buffer_content.dxC = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxC

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyC = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyC

	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyC = 0;
	CSfin_diff_Input.buffer_content.dxA = 1;
	CSfin_diff_Input.buffer_content.eps = -1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxA

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxA = 0;
	CSfin_diff_Input.buffer_content.dyA = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyA

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyA = 0;
	CSfin_diff_Input.buffer_content.dxB = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxB

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxB = 0;
	CSfin_diff_Input.buffer_content.dyB = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyB

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyB = 0;
	CSfin_diff_Input.buffer_content.dxC = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxC

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyC = 1;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyC

	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);
}

void Triangulator::updatePositions(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pUpdatePositions_cc, NULL, 0);

	ID3D11ShaderResourceView* up_srv[] = { indices.getShaderResourceView(), gradients_rtt.getShaderResourceView(), 
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

void Triangulator::updatePositions_fin_diff(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pUpdatePositions_fin_diff, NULL, 0);

	ID3D11ShaderResourceView* up_srv[] = { indices.getShaderResourceView(), gradients_fin_diff.getShaderResourceView(),
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

void Triangulator::delaunay(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	positions.gpuToCpu(immediateContext);

	bool changes = false;

	std::stack<unsigned int> edges_stack;
	std::vector<bool> on_stack;

	on_stack.resize(edges.size());
	for (unsigned int i = 0; i < edges.size(); i++) 
	{
		edges_stack.push(i);
		on_stack[i] = true;
	}
	//TODO: Rest von delaunay, --> copying GPU-CPU und CPU-GPU <--, edges mit neighbors statt mit neighbor_list
	while (!edges_stack.empty()) 
	{
		unsigned int current_edge_index = edges_stack.top();
		std::tuple<unsigned int, unsigned int, unsigned int, unsigned int> edge = edges[current_edge_index];
		on_stack[current_edge_index] = false;
		edges_stack.pop();

		unsigned int tri_index = std::get<0>(edge);
		unsigned int neighbor_index = std::get<1>(edge);

		unsigned int tI = tri_index * 3;
		unsigned int nI = neighbor_index * 3;

		unsigned int tri_indexA = indices.buffer_content[tI], tri_indexB = indices.buffer_content[tI + 1], tri_indexC = indices.buffer_content[tI + 2];
		unsigned int n_indexA = indices.buffer_content[nI], n_indexB = indices.buffer_content[nI + 1], n_indexC = indices.buffer_content[nI + 2];

		unsigned int indexA = std::get<2>(edge), indexB = std::get<3>(edge), indexC, indexD;

		if (tri_indexA != indexA && tri_indexA != indexB) 
		{
			indexC = tri_indexA;
		}
		else if (tri_indexB != indexA && tri_indexB != indexB)
		{
			indexC = tri_indexB;
		}
		else 
		{
			indexC = tri_indexC;
		}

		if (n_indexA != indexA && n_indexA != indexB)
		{
			indexD = n_indexA;
		}
		else if (n_indexB != indexA && n_indexB != indexB)
		{
			indexD = n_indexB;
		}
		else
		{
			indexD = n_indexC;
		}

		Vec2f A = positions.buffer_content[indexA];
		Vec2f B = positions.buffer_content[indexB];
		Vec2f C = positions.buffer_content[indexC];
		Vec2f D = positions.buffer_content[indexD];

		float mat_elements[9] = { A.x - D.x, A.y - D.y, (A.x - D.x) * (A.x - D.x) + (A.y - D.y) * (A.y - D.y),
									B.x - D.x, B.y - D.y, (B.x - D.x) * (B.x - D.x) + (B.y - D.y) * (B.y - D.y),
									C.x - D.x, C.y - D.y, (C.x - D.x) * (C.x - D.x) + (C.y - D.y) * (C.y - D.y) };
		cv::Mat matrix = cv::Mat(3, 3, CV_32F, mat_elements);
		float det = cv::determinant(matrix);
		bool clock = false;
		if (((B.x - A.x) * (C.y - A.y) - (B.y - A.y) * (C.x - A.x)) > 0)
			clock = true;

		if (clock && det > 0 || !clock && det < 0) 
		{
			changes = true;

			edges[current_edge_index] = std::make_tuple(tri_index, neighbor_index, indexD, indexC);		//flip edge

			int cb = get_edge_index(indexC, indexB);
			int ca = get_edge_index(indexC, indexA);
			int db = get_edge_index(indexD, indexB);
			int da = get_edge_index(indexD, indexA);

			if (da != -1) 
			{
				//edge DA has the same vertices and the outer neighbor stays the same, but the inner neighbor (previously neighbor_index) is now the other triangle
				if (std::get<0>(edges[da]) == neighbor_index)
					edges[da] = std::make_tuple(tri_index, std::get<1>(edges[da]), indexA, indexD);
				else
					edges[da] = std::make_tuple(std::get<0>(edges[da]), tri_index, std::get<2>(edges[da]), std::get<3>(edges[da]));
			}
			if (cb != -1) 
			{
				//edge CB has the same vertices and the outer neighbor stays the same, but the inner neighbor (previously tri_index) is now the other triangle
				if (std::get<0>(edges[cb]) == tri_index)
					edges[cb] = std::make_tuple(neighbor_index, std::get<1>(edges[cb]), indexB, indexC);
				else
					edges[cb] = std::make_tuple(std::get<0>(edges[cb]), neighbor_index, std::get<2>(edges[cb]), std::get<3>(edges[cb]));
			}
			
			//adjust triangle at tri_index
			indices.buffer_content[tI] = indexA;
			indices.buffer_content[tI + 1] = indexD;
			indices.buffer_content[tI + 2] = indexC;

			//adjust triangle at neighbor_index
			indices.buffer_content[nI] = indexB;
			indices.buffer_content[nI + 1] = indexC;
			indices.buffer_content[nI + 2] = indexD;

			neighbors[indexC].push_back(neighbor_index);
			neighbors[indexD].push_back(tri_index);

			std::list<unsigned int> neighborsA, neighborsB;
			for (auto i : neighbors[indexA]) 
			{
				//A lost the triangle at neighbor_index
				if (i != neighbor_index)
					neighborsA.push_back(i);
			}
			neighbors[indexA] = neighborsA;
			for (auto i : neighbors[indexB])
			{
				//B lost the triangle at tri_index
				if (i != tri_index)
					neighborsB.push_back(i);
			}
			neighbors[indexB] = neighborsB;
			
			//push edges that exist and are not on the stack
			if (cb != -1 && !on_stack[cb]) 
			{
				edges_stack.push(cb);
				on_stack[cb] = true;
			}
			if (ca != -1 && !on_stack[ca])
			{
				edges_stack.push(ca);
				on_stack[ca] = true;
			}
			if (db != -1 && !on_stack[db])
			{
				edges_stack.push(db);
				on_stack[db] = true;
			}
			if (da != -1 && !on_stack[da])
			{
				edges_stack.push(da);
				on_stack[da] = true;
			}
		}
	}

	if (changes)
	{
		buildNeighborBuffers();
		indices.cpuToGpu(device, immediateContext);
		indices_in_neighbor_list.cpuToGpu(device, immediateContext);
		neighbor_count.cpuToGpu(device, immediateContext);
		neighbor_list.cpuToGpu(device, immediateContext);
	}
}

bool Triangulator::eliminate_degenerate_triangles(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{//TODO: da(?) bei delaunay war viel zu groﬂ (evtl. (unsigned int) -1); deswegen alle edges ausgeben und schauen, ob irgendwo -1 geschrieben wird
	positions.gpuToCpu(immediateContext);

	bool changes = true;
	bool changes_made = false;

	while (changes) 
	{
		changes = false;
		for (int i = 0; i < edges.size(); i++) 
		{
			unsigned int indexA = std::get<2>(edges[i]);
			unsigned int indexB = std::get<3>(edges[i]);
			float edge_length = length(positions.buffer_content[indexA], positions.buffer_content[indexB]);

			if (edge_length < 5)
			{
				changes = true;
				changes_made = true;
				//default: indexA on the border, merge indexB into indexA; if indexB is on the border, swap them
				if (is_on_border[indexB])
				{
					unsigned int temp = indexA;
					indexA = indexB;
					indexB = temp;
				}

				unsigned int tri_index = std::get<0>(edges[i]);
				unsigned int neighbor_index = std::get<1>(edges[i]);
				std::cout << indices.buffer_content.size() << " " << tri_index * 3 << " " << neighbor_index * 3 << " " << std::endl;
				//get the third index (indexC) for the triangle at tri_index
				unsigned int indexC, indexD;
				if (indices.buffer_content[tri_index * 3] != indexA && indices.buffer_content[tri_index * 3] != indexB)
					indexC = indices.buffer_content[tri_index * 3];
				else if (indices.buffer_content[tri_index * 3 + 1] != indexA && indices.buffer_content[tri_index * 3 + 1] != indexB)
					indexC = indices.buffer_content[tri_index * 3 + 1];
				else
					indexC = indices.buffer_content[tri_index * 3 + 2];

				//get the third index (indexD) for the triangle at neighbor_index
				if (indices.buffer_content[neighbor_index * 3] != indexA && indices.buffer_content[neighbor_index * 3] != indexB)
					indexD = indices.buffer_content[neighbor_index * 3];
				else if (indices.buffer_content[neighbor_index * 3 + 1] != indexA && indices.buffer_content[neighbor_index * 3 + 1] != indexB)
					indexD = indices.buffer_content[neighbor_index * 3 + 1];
				else
					indexD = indices.buffer_content[neighbor_index * 3 + 2];

				//for all neighbors of indexB swap the respective index
				for (unsigned int n : neighbors[indexB])
				{
					if (indices.buffer_content[n * 3] == indexB)
					{
						indices.buffer_content[n * 3] = indexA;
					}
					else if (indices.buffer_content[n * 3 + 1] == indexB)
					{
						indices.buffer_content[n * 3 + 1] = indexA;
					}
					else if (indices.buffer_content[n * 3 + 2] == indexB)
					{
						indices.buffer_content[n * 3 + 2] = indexA;
					}
				}

				//remove the two collapsing triangles
				nTriangles -= 1;
				indices.buffer_content[tri_index * 3] = indices.buffer_content[nTriangles * 3];
				indices.buffer_content[tri_index * 3 + 1] = indices.buffer_content[nTriangles * 3 + 1];
				indices.buffer_content[tri_index * 3 + 2] = indices.buffer_content[nTriangles * 3 + 2];

				nTriangles -= 1;
				indices.buffer_content[neighbor_index * 3] = indices.buffer_content[nTriangles * 3];
				indices.buffer_content[neighbor_index * 3 + 1] = indices.buffer_content[nTriangles * 3 + 1];
				indices.buffer_content[neighbor_index * 3 + 2] = indices.buffer_content[nTriangles * 3 + 2];

				//remove the vertex
				for (int j = indexB; j < positions.buffer_content.size() - 1; j++) 
				{
					positions.buffer_content[j] = positions.buffer_content[j + 1];
				}
				
				positions.buffer_content.resize(positions.buffer_content.size() - 1);
				
				//adjust the indices
				for (int j = 0; j < indices.buffer_content.size(); j++) 
				{
					if (indices.buffer_content[j] > indexB)
						indices.buffer_content[j]--;
				}

				buildNeighbors(false);
				buildEdges();
				break;
			}
		}
	}

	if (changes_made) 
	{	
		buildNeighborBuffers();
		positions.cpuToGpu(device, immediateContext);
		indices.cpuToGpu(device, immediateContext);
		indices_in_neighbor_list.cpuToGpu(device, immediateContext);
		neighbor_count.cpuToGpu(device, immediateContext);
		neighbor_list.cpuToGpu(device, immediateContext);
		return true;
	}
	return false;
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
			is_on_border.push_back(border);

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
	buildNeighbors(true);
	buildEdges();
}

void Triangulator::buildNeighbors(bool buildBuffers)
{
	size_t pos_size = positions.buffer_content.size();
	
	//for (int i = 0; i < pos_size; i++)
		//neighbor_count.buffer_content[i] = 0;

	//std::vector<std::list<unsigned int>> neighbors;
	neighbors.clear();
	neighbors.resize(positions.buffer_content.size());

	for (int i = 0; i < indices.buffer_content.size() / 3; i++) 
	{
		neighbors[indices.buffer_content[i * 3]].push_back(i);
		//neighbor_count.buffer_content[indices.buffer_content[i * 3]] += 1;

		neighbors[indices.buffer_content[i * 3 + 1]].push_back(i);
		//neighbor_count.buffer_content[indices.buffer_content[i * 3 + 1]] += 1;

		neighbors[indices.buffer_content[i * 3 + 2]].push_back(i);
		//neighbor_count.buffer_content[indices.buffer_content[i * 3 + 2]] += 1;
	}
	if (buildBuffers)
		buildNeighborBuffers();
}

void Triangulator::buildNeighborBuffers()
{
	size_t pos_size = positions.buffer_content.size();

	neighbor_list.buffer_content.clear();
	indices_in_neighbor_list.buffer_content.clear();
	neighbor_count.buffer_content.clear();
	indices_in_neighbor_list.buffer_content.resize(pos_size);
	neighbor_count.buffer_content.resize(pos_size);

	for (int i = 0; i < pos_size; i++)
	{
		neighbor_count.buffer_content[i] = (unsigned int)neighbors[i].size();
		for (unsigned int n : neighbors[i])
		{
			neighbor_list.buffer_content.push_back(n);
		}
	}

	indices_in_neighbor_list.buffer_content[0] = 0;
	for (unsigned int i = 1; i < pos_size; i++)
	{
		indices_in_neighbor_list.buffer_content[i] = indices_in_neighbor_list.buffer_content[i - 1] + neighbor_count.buffer_content[i - 1];
	}
}

void Triangulator::buildEdges()
{
	edges.clear();

	for (unsigned int tri_index = 0; tri_index < indices.buffer_content.size() / 3; tri_index++) 
	{
		unsigned int tI = tri_index * 3;

		unsigned int indA = indices.buffer_content[tI];
		unsigned int indB = indices.buffer_content[tI + 1];
		unsigned int indC = indices.buffer_content[tI + 2];

#if 0
		if (get_edge_index(indA, indB) == -1)
		{
			int indA_offset = indices_in_neighbor_list.buffer_content[indA];
			for (int i = indA_offset; i < neighbor_count.buffer_content[indA]; i++) 
			{
				unsigned int neighborA = neighbor_list.buffer_content[i] * 3;
				if (neighborA == tI)
					continue;

				unsigned int nA_indA = indices.buffer_content[neighborA];
				unsigned int nA_indB = indices.buffer_content[neighborA + 1];
				unsigned int nA_indC = indices.buffer_content[neighborA + 2];

				if (nA_indA == indB || nA_indB == indB || nA_indC == indB)
					edges.push_back(std::make_tuple(tri_index, neighborA / 3, indA, indB));
			} 
		}
		if (get_edge_index(indA, indC) == -1)
		{
			int indA_offset = indices_in_neighbor_list.buffer_content[indA];
			for (int i = indA_offset; i < neighbor_count.buffer_content[indA]; i++)
			{
				unsigned int neighborA = neighbor_list.buffer_content[i] * 3;
				if (neighborA == tI)
					continue;

				unsigned int nA_indA = indices.buffer_content[neighborA];
				unsigned int nA_indB = indices.buffer_content[neighborA + 1];
				unsigned int nA_indC = indices.buffer_content[neighborA + 2];

				if (nA_indA == indC || nA_indB == indC || nA_indC == indC)
					edges.push_back(std::make_tuple(tri_index, neighborA / 3, indA, indC));
			}
		}
		if (get_edge_index(indB, indC) == -1)
		{
			int indB_offset = indices_in_neighbor_list.buffer_content[indB];
			for (int i = indB_offset; i < neighbor_count.buffer_content[indB]; i++)
			{
				unsigned int neighborB = neighbor_list.buffer_content[i] * 3;
				if (neighborB == tI)
					continue;

				unsigned int nB_indA = indices.buffer_content[neighborB];
				unsigned int nB_indB = indices.buffer_content[neighborB + 1];
				unsigned int nB_indC = indices.buffer_content[neighborB + 2];

				if (nB_indA == indC || nB_indB == indC || nB_indC == indC)
					edges.push_back(std::make_tuple(tri_index, neighborB / 3, indB, indC));
			}
		}
#else
		if (get_edge_index(indA, indB) == -1) 
		{
			for (auto neighborA : neighbors[indA]) 
			{
				if (neighborA == tri_index)
					continue;

				unsigned int nI = neighborA * 3;

				unsigned int nA_indA = indices.buffer_content[nI];
				unsigned int nA_indB = indices.buffer_content[nI + 1];
				unsigned int nA_indC = indices.buffer_content[nI + 2];

				if (nA_indA == indB || nA_indB == indB || nA_indC == indB)
					edges.push_back(std::make_tuple(tri_index, neighborA, indA, indB));
			}
		}
		if (get_edge_index(indA, indC) == -1)
		{
			for (auto neighborA : neighbors[indA])
			{
				if (neighborA == tri_index)
					continue;

				unsigned int nI = neighborA * 3;

				unsigned int nA_indA = indices.buffer_content[nI];
				unsigned int nA_indB = indices.buffer_content[nI + 1];
				unsigned int nA_indC = indices.buffer_content[nI + 2];

				if (nA_indA == indC || nA_indB == indC || nA_indC == indC)
					edges.push_back(std::make_tuple(tri_index, neighborA, indC, indA));
			}
		}
		if (get_edge_index(indB, indC) == -1)
		{
			for (auto neighborB : neighbors[indB])
			{
				if (neighborB == tri_index)
					continue;

				unsigned int nI = neighborB * 3;

				unsigned int nB_indA = indices.buffer_content[nI];
				unsigned int nB_indB = indices.buffer_content[nI + 1];
				unsigned int nB_indC = indices.buffer_content[nI + 2];

				if (nB_indA == indC || nB_indB == indC || nB_indC == indC)
					edges.push_back(std::make_tuple(tri_index, neighborB, indB, indC));
			}
		}
#endif
	}
}

void Triangulator::initializeTriangleGradients()
{
	for (int i = 0; i < nTriangles; i++)
	{
		gradients_rtt.buffer_content.push_back({ 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f });
		//gradients_fin_diff.buffer_content.push_back({ 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f });
		Vec144f c = { {0} };
		gradients_fin_diff.buffer_content.push_back(c);
	}
}

int Triangulator::get_edge_index(unsigned int v1, unsigned int v2)
{
	unsigned int index = 0;
	for (auto& edge : edges) 
	{
		unsigned int e_v1 = std::get<2>(edge);
		unsigned int e_v2 = std::get<3>(edge);
		if (e_v1 == v1 && e_v2 == v2 || e_v1 == v2 && e_v2 == v1)
			return index;
		index++;
	}
	return -1;
}

int Triangulator::get_edge_index_by_tris(unsigned int t, unsigned int n)
{
	unsigned int index = 0;
	for (auto& edge : edges)
	{
		unsigned int e_t = std::get<0>(edge);
		unsigned int e_n = std::get<1>(edge);
		if (e_t == t && e_n == n || e_t == n && e_n == t)
			return index;
		index++;
	}
	return -1;
}

std::vector<int> Triangulator::get_edges_with_triangle(unsigned int t)
{
	std::vector<int> _edges;
	for (int i = 0; i < edges.size(); i++) 
	{
		if (std::get<0>(edges[i]) == t || std::get<1>(edges[i]) == t)
			_edges.push_back(i);
	}
	return _edges;
}

std::vector<int> Triangulator::get_edges_with_vertex(unsigned int v)
{
	std::vector<int> _edges;
	for (int i = 0; i < edges.size(); i++)
	{
		if (std::get<2>(edges[i]) == v || std::get<3>(edges[i]) == v)
			_edges.push_back(i);
	}
	return _edges;
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
		gradientCoefficients.buffer_content.push_back({ 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f });
	}
}

void Triangulator::testing(ID3D11DeviceContext* immediateContext)
{
	/*for (int i = 0; i < 3; i++)
	{
		for (int j = 0; j < 3; j++) 
		{
			positions.buffer_content.push_back({ 0.0f + i, 0.0f + j });
			positions.buffer_content.push_back({ 1.0f + i, 0.0f + j });
			positions.buffer_content.push_back({ 1.0f + i, 1.0f + j });
			positions.buffer_content.push_back({ 0.0f + i, 1.0f + j });
		}
	}*/
	/*positions.buffer_content.push_back({0.0f, 0.0f});
	positions.buffer_content.push_back({ (float)image->getWidth() / 2.0f , 0.0f});
	positions.buffer_content.push_back({ (float)image->getWidth(), 0.0f});
	positions.buffer_content.push_back({ 0.0f, (float)image->getHeight() / 2.0f });
	positions.buffer_content.push_back({ (float)image->getWidth() / 2.0f, (float)image->getHeight() / 2.0f });
	positions.buffer_content.push_back({ (float)image->getWidth(), (float)image->getHeight() / 2.0f });
	positions.buffer_content.push_back({ 0.0f, (float)image->getHeight() });
	positions.buffer_content.push_back({ (float)image->getWidth() / 2.0f, (float)image->getHeight() });
	positions.buffer_content.push_back({ (float)image->getWidth(), (float)image->getHeight() });

	indices.buffer_content.push_back(0); //A
	indices.buffer_content.push_back(1); //B
	indices.buffer_content.push_back(4); //C

	indices.buffer_content.push_back(0); //A
	indices.buffer_content.push_back(4); //B
	indices.buffer_content.push_back(3); //C

	indices.buffer_content.push_back(1); //A
	indices.buffer_content.push_back(2); //B
	indices.buffer_content.push_back(5); //C

	indices.buffer_content.push_back(1); //A
	indices.buffer_content.push_back(5); //B
	indices.buffer_content.push_back(4); //C

	indices.buffer_content.push_back(3); //A
	indices.buffer_content.push_back(4); //B
	indices.buffer_content.push_back(7); //C

	indices.buffer_content.push_back(3); //A
	indices.buffer_content.push_back(7); //B
	indices.buffer_content.push_back(6); //C

	indices.buffer_content.push_back(4); //A
	indices.buffer_content.push_back(5); //B
	indices.buffer_content.push_back(8); //C

	indices.buffer_content.push_back(4); //A
	indices.buffer_content.push_back(8); //B
	indices.buffer_content.push_back(7); //C

	nTriangles = 8;*/
	nTriangles = 1;
	positions.buffer_content.push_back({800.0f/18.0f * 11.0f, 600.0f / 18.0f * 2.0f});
	positions.buffer_content.push_back({800.0f/18.0f * 12.0f, 600.0f / 18.0f * 3.0f});
	positions.buffer_content.push_back({800.0f/18.0f * 11.0f, 600.0f / 18.0f * 3.0f});
	
	//positions.buffer_content.push_back({600.0f, 200.0f});
	//positions.buffer_content.push_back({575.0f, 280.0f});
	//positions.buffer_content.push_back({540.0f, 315.0f});
	
	indices.buffer_content.push_back(0);
	indices.buffer_content.push_back(1);
	indices.buffer_content.push_back(2);
	setRandomColors();
	buildNeighbors(true);
	buildEdges();
	initializeTriangleGradients();
	//computeConstantColors(immediateContext);
	//render(immediateContext, en_constant);
}
