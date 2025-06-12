#include "Triangulator.h"

Triangulator::Triangulator(ImageView* image, D3D* pD3D, int numTriangles, std::string file) : image(image), d3d(pD3D),
								positions(),
								indices(),
								is_on_border(), 
								gradientCoefficients(),
								colors(),
								neighbor_list(),
								indices_in_neighbor_list(),
								neighbor_count(),
								gradients_rtt(),
								colors_fin_diff(),
								errors_fin_diff(),
								errors(),
								errorsPS(),
								errorCS(),
								pixel_variance(),
								pInputLayout(NULL),
								pVertexShader(NULL),
								pPixelShader(NULL),
								pPSWithError(NULL),
								pPSLinearGradients(NULL),
								pPSLinGradWithError(NULL),
								pComputeConstantColor(NULL),
								pComputeLinearGradients(NULL),
								pCCC_bi_interp(NULL),
								pCLG_bi_interp(NULL),
								pComputeGradients_rtt(NULL),
								pComputeGradients_cplg(NULL),
								pUpdatePositions_cc(NULL),
								pFiniteDifferences(NULL),
								pComputeErrors_fin_diff(NULL),
								pUpdatePositions_fin_diff(NULL),
								pComputeErrors(NULL),
								pComputeImageError(NULL),
								VSInput(),
								CSInput(),
								CSfin_diff_Input(),
								CSNum(),
								nTriangles(numTriangles),
								triangleGoal(numTriangles),
								delaunayEveryNthIteration(10),
								delaunayUntilNthIteration(100),
								computeErrorInPS(true),
								filename(file)
{
	VSInput.buffer_content.projMatrix = image->getProjectionMatrix();

	CSInput.buffer_content.stepSize = 1;//0.4f;
	CSInput.buffer_content.width = image->getWidth();
	CSInput.buffer_content.height = image->getHeight();
	CSInput.buffer_content.trustRegion = 0.2f;//1.0f;
	CSInput.buffer_content.damping = 0.001f;

	CSfin_diff_Input.buffer_content.eps = 1;
	CSfin_diff_Input.buffer_content.dxA = 1;
	CSfin_diff_Input.buffer_content.dxB = 0;
	CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyA = 0;
	CSfin_diff_Input.buffer_content.dyB = 0;
	CSfin_diff_Input.buffer_content.dyC = 0;
	
#if	0 
	testing(d3d->getImmediateContext());
#else
	createRegularGrid();
	setRandomColors();
	initializeTriangleGradients();

	int ecsX = image->getWidth();
	int ecsY = image->getHeight();
	ecsX = ecsX % 16 == 0 ? ecsX / 16 : ecsX / 16 + 1;
	ecsY = ecsY % 16 == 0 ? ecsY / 16 : ecsY / 16 + 1;
	errorCS.buffer_content.resize(ecsX * ecsY, {0, 0, 0, 0});

	//546, 51
	std::cout << positions.buffer_content[indices.buffer_content[11 * 3]].x << " " << positions.buffer_content[indices.buffer_content[11 * 3]].y << std::endl;
	std::cout << positions.buffer_content[indices.buffer_content[11 * 3 + 1]].x << " " << positions.buffer_content[indices.buffer_content[11 * 3 + 1]].y << std::endl;
	std::cout << positions.buffer_content[indices.buffer_content[11 * 3 + 2]].x << " " << positions.buffer_content[indices.buffer_content[11 * 3 + 2]].y << std::endl;
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

	if (!CSNum.createBuffer(device)) return false;

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
	
	hr = D3DReadFileToBlob(L".\\shader\\PSWithError.cso", &pBlob_ps);
	if (FAILED(hr)) return false;

	hr = device->CreatePixelShader(pBlob_ps->GetBufferPointer(), pBlob_ps->GetBufferSize(), NULL, &pPSWithError);
	if (FAILED(hr)) return false;

	hr = D3DReadFileToBlob(L".\\shader\\PSLinearGradients.cso", &pBlob_ps);
	if (FAILED(hr)) return false;

	hr = device->CreatePixelShader(pBlob_ps->GetBufferPointer(), pBlob_ps->GetBufferSize(), NULL, &pPSLinearGradients);
	if (FAILED(hr)) return false;

	hr = D3DReadFileToBlob(L".\\shader\\PSLinGradWithError.cso", &pBlob_ps);
	if (FAILED(hr)) return false;

	hr = device->CreatePixelShader(pBlob_ps->GetBufferPointer(), pBlob_ps->GetBufferSize(), NULL, &pPSLinGradWithError);
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

	//read and create ComputeErrors_fin_diff compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeErrorFinDiff.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputeErrors_fin_diff);
	if (FAILED(hr)) return false;

	//read and create UpdatePositionsFinDiff compute shader
	hr = D3DReadFileToBlob(L".\\shader\\UpdatePositionsFinDiff.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pUpdatePositions_fin_diff);
	if (FAILED(hr)) return false;

	//read and create ComputeError compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeError.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputeErrors);
	if (FAILED(hr)) return false;

	//read and create ComputePixelVariance compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputePixelVariance.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputePixelVariance);
	if (FAILED(hr)) return false;

	//read and create ComputeImageError compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeImageError.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pComputeImageError);
	if (FAILED(hr)) return false;

	//read and create ComputeGradient_bipct compute shader
	hr = D3DReadFileToBlob(L".\\shader\\ComputeGradient_bipct.cso", &pBlob_cs);
	if (FAILED(hr)) return false;

	hr = device->CreateComputeShader(pBlob_cs->GetBufferPointer(), pBlob_cs->GetBufferSize(), NULL, &pCG_bipct);
	if (FAILED(hr)) return false;


	//create input layout
	hr = device->CreateInputLayout(inputLayout_desc, 1, pBlob_vs->GetBufferPointer(), pBlob_vs->GetBufferSize(), &pInputLayout);
	if (FAILED(hr)) return false;
	

	//create buffers
	if (!positions.createBuffer(device, D3D11_BIND_VERTEX_BUFFER | D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!indices.createBuffer(device, D3D11_BIND_INDEX_BUFFER | D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!colors.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!gradientCoefficients.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!neighbor_list.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!neighbor_count.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!indices_in_neighbor_list.createBuffer(device, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!gradients_rtt.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;

	if (!colors_fin_diff.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;
	
	if (!errors_fin_diff.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;
	
	if (!errors.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;
	
	if (!errorsPS.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;
	
	if (!errorCS.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;
	
	if (!pixel_variance.createBuffer(device, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_CPU_ACCESS_READ | D3D11_CPU_ACCESS_WRITE)) return false;


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
	colors_fin_diff.releaseBuffer();
	errors_fin_diff.releaseBuffer();
	VSInput.releaseBuffer();
	CSInput.releaseBuffer();
	CSfin_diff_Input.releaseBuffer();
	CSNum.releaseBuffer();
	errors.releaseBuffer();
	errorsPS.releaseBuffer();
	errorCS.releaseBuffer();
	pixel_variance.releaseBuffer();

	SAFE_RELEASE(pVertexShader);
	SAFE_RELEASE(pPixelShader);
	SAFE_RELEASE(pPSWithError);
	SAFE_RELEASE(pPSLinearGradients);
	SAFE_RELEASE(pPSLinGradWithError);
	SAFE_RELEASE(pComputeConstantColor);
	SAFE_RELEASE(pComputeLinearGradients);
	SAFE_RELEASE(pCCC_bi_interp);
	SAFE_RELEASE(pCLG_bi_interp);
	SAFE_RELEASE(pComputeGradients_rtt);
	SAFE_RELEASE(pComputeGradients_cplg);
	SAFE_RELEASE(pUpdatePositions_cc);
	SAFE_RELEASE(pUpdatePositions_fin_diff);
	SAFE_RELEASE(pFiniteDifferences);
	SAFE_RELEASE(pComputeErrors_fin_diff);
	SAFE_RELEASE(pComputeErrors);
	SAFE_RELEASE(pComputeImageError);
	SAFE_RELEASE(pCG_bipct);
	SAFE_RELEASE(pInputLayout);
}

void Triangulator::insert_vertex_center(unsigned int tri_index, ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	//positions.gpuToCpu(immediateContext);
	unsigned int indexA = indices.buffer_content[tri_index * 3];
	unsigned int indexB = indices.buffer_content[tri_index * 3 + 1];
	unsigned int indexC = indices.buffer_content[tri_index * 3 + 2];
	
	float center_x = (positions.buffer_content[indexA].x + positions.buffer_content[indexB].x + positions.buffer_content[indexC].x) / 3.0f;
	float center_y = (positions.buffer_content[indexA].y + positions.buffer_content[indexB].y + positions.buffer_content[indexC].y) / 3.0f;

	unsigned int newIndex = positions.buffer_content.size();
	positions.buffer_content.push_back({ center_x, center_y });
	is_on_border.push_back(false);

	//triangle 1
	indices.buffer_content[tri_index * 3 + 2] = newIndex;

	//adjust neighbors of indexC, which will no longer have tri_index as neighbor
	std::list<unsigned int> neighborsC;
	for (unsigned int i : neighbors[indexC]) 
	{
		if (i != tri_index)
			neighborsC.push_back(i);
	}
	neighbors[indexC] = neighborsC;

	//triangle 2
	indices.buffer_content.push_back(indexC);
	indices.buffer_content.push_back(indexA);
	indices.buffer_content.push_back(newIndex);

	neighbors[indexA].push_back(nTriangles);
	nTriangles += 1;
	
	//edge AC
	int edge_ac = get_edge_index(indexA, indexC);
	if (edge_ac != -1) 
	{
		std::tuple<unsigned int, unsigned int, unsigned int, unsigned int> edge = edges[edge_ac];
		if (std::get<0>(edge) == tri_index)
			edges[edge_ac] = std::make_tuple((unsigned int)nTriangles - 1, std::get<1>(edge), std::get<2>(edge), std::get<3>(edge));
		else
			edges[edge_ac] = std::make_tuple(std::get<0>(edge), (unsigned int)nTriangles - 1, std::get<2>(edge), std::get<3>(edge));

	}

	//triangle 3
	indices.buffer_content.push_back(indexB);
	indices.buffer_content.push_back(indexC);
	indices.buffer_content.push_back(newIndex);

	neighbors[indexB].push_back(nTriangles);
	nTriangles += 1;

	//edge BC
	int edge_bc = get_edge_index(indexB, indexC);
	if (edge_bc != -1)
	{
		std::tuple<unsigned int, unsigned int, unsigned int, unsigned int> edge = edges[edge_bc];
		if (std::get<0>(edge) == tri_index)
			edges[edge_bc] = std::make_tuple((unsigned int)nTriangles - 1, std::get<1>(edge), std::get<2>(edge), std::get<3>(edge));
		else
			edges[edge_bc] = std::make_tuple(std::get<0>(edge), (unsigned int)nTriangles - 1, std::get<2>(edge), std::get<3>(edge));

	}

	neighbors[indexC].push_back(nTriangles - 2);
	neighbors[indexC].push_back(nTriangles - 1);

	edges.push_back(std::make_tuple(tri_index, (unsigned int)nTriangles - 2, newIndex, indexA));
	edges.push_back(std::make_tuple(tri_index, (unsigned int)nTriangles - 1, indexB, newIndex));
	edges.push_back(std::make_tuple((unsigned int)nTriangles - 2, (unsigned int)nTriangles - 1, newIndex, indexC));

	std::list<unsigned int> new_vertex_neighbors = { tri_index, (unsigned int)nTriangles - 2, (unsigned int)nTriangles - 1 };
	neighbors.push_back(new_vertex_neighbors);

	//updateDataOnGPU(device, immediateContext);
	//buildNeighborBuffers();
	//positions.cpuToGpu(device, immediateContext);
	//indices.cpuToGpu(device, immediateContext);
	//indices_in_neighbor_list.cpuToGpu(device, immediateContext);
	//neighbor_count.cpuToGpu(device, immediateContext);
	//neighbor_list.cpuToGpu(device, immediateContext);
}

void Triangulator::insert_triangle_into_triangle(unsigned int tri_index, std::vector<bool>& marked, ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	//positions.gpuToCpu(immediateContext);

	unsigned int indexA = indices.buffer_content[tri_index * 3];
	unsigned int indexB = indices.buffer_content[tri_index * 3 + 1];
	unsigned int indexC = indices.buffer_content[tri_index * 3 + 2];

	Vec2f A = positions.buffer_content[indexA];
	Vec2f B = positions.buffer_content[indexB];
	Vec2f C = positions.buffer_content[indexC];

	Vec2f m_ab = { (A.x + B.x) / 2.0f, (A.y + B.y) / 2.0f };
	Vec2f m_bc = { (B.x + C.x) / 2.0f, (B.y + C.y) / 2.0f };
	Vec2f m_ca = { (C.x + A.x) / 2.0f, (C.y + A.y) / 2.0f };

	//if (tri_area(m_ab, m_bc, m_ca) <= 2)
		//return;

	unsigned int index_mAB = positions.buffer_content.size();
	positions.buffer_content.push_back(m_ab);
	neighbors.push_back({ });
	is_on_border.push_back(true);

	unsigned int index_mBC = positions.buffer_content.size();
	positions.buffer_content.push_back(m_bc);
	neighbors.push_back({ });
	is_on_border.push_back(true);

	unsigned int index_mCA = positions.buffer_content.size();
	positions.buffer_content.push_back(m_ca);
	neighbors.push_back({ });
	is_on_border.push_back(true);

	//triangle inside
	unsigned int index_middle_tri = nTriangles;
	indices.buffer_content.push_back(index_mAB);
	indices.buffer_content.push_back(index_mBC);
	indices.buffer_content.push_back(index_mCA);
	nTriangles += 1;

	//change tri_index (becomes second new triangle inside)
	indices.buffer_content[tri_index * 3 + 1] = index_mAB;
	indices.buffer_content[tri_index * 3 + 2] = index_mCA;

	//create third triangle inside
	unsigned int index_mBm = nTriangles;
	indices.buffer_content.push_back(index_mAB);
	indices.buffer_content.push_back(indexB);
	indices.buffer_content.push_back(index_mBC);
	nTriangles += 1;

	//create fourth triangle inside
	unsigned int index_mCm = nTriangles;
	indices.buffer_content.push_back(index_mBC);
	indices.buffer_content.push_back(indexC);
	indices.buffer_content.push_back(index_mCA);
	nTriangles += 1;

	std::list<unsigned int> neighbors_mAB = { tri_index, index_middle_tri, index_mBm };
	neighbors[index_mAB] = neighbors_mAB;

	std::list<unsigned int> neighbors_mBC = { index_mBm, index_middle_tri, index_mCm };
	neighbors[index_mBC] = neighbors_mBC;

	std::list<unsigned int> neighbors_mCA = { tri_index, index_middle_tri, index_mCm };
	neighbors[index_mCA] = neighbors_mCA;

	//check if there is a triangle next to edge AB
	int edgeAB = get_edge_index(indexA, indexB);
	unsigned int neighborAB = -1;

	if (edgeAB != -1) 
	{
		is_on_border[index_mAB] = false;
		neighborAB = std::get<0>(edges[edgeAB]) == tri_index ? std::get<1>(edges[edgeAB]) : std::get<0>(edges[edgeAB]);

		//get its third vertex not on the edge
		unsigned int nIC;
		for (unsigned int i = 0; i < 3; i++)
		{
			nIC = indices.buffer_content[neighborAB * 3 + i];
			if (std::get<2>(edges[edgeAB]) != nIC && std::get<3>(edges[edgeAB]) != nIC)
				break;
		}

		indices.buffer_content[neighborAB * 3] = indexA;
		indices.buffer_content[neighborAB * 3 + 1] = nIC;							//t1
		indices.buffer_content[neighborAB * 3 + 2] = index_mAB;

		if (neighborAB < marked.size())
			marked[neighborAB] = true;

		indices.buffer_content.push_back(index_mAB);
		indices.buffer_content.push_back(nIC);										//t2
		indices.buffer_content.push_back(indexB);
		nTriangles += 1;

		neighbors[indexB].push_back(nTriangles - 1);
		neighbors[nIC].push_back(nTriangles - 1);
		neighbors[index_mAB].push_back(nTriangles - 1);
		neighbors[index_mAB].push_back(neighborAB);

		std::list<unsigned int> nB;
		for (auto n : neighbors[indexB])
		{
			if (n != neighborAB)
				nB.push_back(n);
		}
		neighbors[indexB] = nB;
	}
	
	//check if there is a triangle next to edge BC
	int edgeBC = get_edge_index(indexB, indexC);
	unsigned int neighborBC = -1;

	if (edgeBC != -1)
	{
		is_on_border[index_mBC] = false;
		neighborBC = std::get<0>(edges[edgeBC]) == tri_index ? std::get<1>(edges[edgeBC]) : std::get<0>(edges[edgeBC]);

		//get its third vertex not on the edge
		unsigned int nIC;
		for (unsigned int i = 0; i < 3; i++)
		{
			nIC = indices.buffer_content[neighborBC * 3 + i];
			if (std::get<2>(edges[edgeBC]) != nIC && std::get<3>(edges[edgeBC]) != nIC)
				break;
		}

		indices.buffer_content[neighborBC * 3] = indexB;
		indices.buffer_content[neighborBC * 3 + 1] = nIC;							//t1
		indices.buffer_content[neighborBC * 3 + 2] = index_mBC;

		if (neighborBC < marked.size())
			marked[neighborBC] = true;

		indices.buffer_content.push_back(index_mBC);
		indices.buffer_content.push_back(nIC);										//t2
		indices.buffer_content.push_back(indexC);
		nTriangles += 1;

		//neighbors[indexB].push_back(index_mBm);
		neighbors[indexC].push_back(nTriangles - 1);
		neighbors[nIC].push_back(nTriangles - 1);
		neighbors[index_mBC].push_back(nTriangles - 1);
		neighbors[index_mBC].push_back(neighborBC);

		std::list<unsigned int> nC;
		for (auto n : neighbors[indexC])
		{
			if (n != neighborBC)
				nC.push_back(n);
		}
		neighbors[indexC] = nC;
	}

	//check if there is a triangle next to edge CA
	int edgeCA = get_edge_index(indexC, indexA);
	unsigned int neighborCA = -1;

	if (edgeCA != -1)
	{
		is_on_border[index_mCA] = false;
		neighborCA = std::get<0>(edges[edgeCA]) == tri_index ? std::get<1>(edges[edgeCA]) : std::get<0>(edges[edgeCA]);

		//get its third vertex not on the edge
		unsigned int nIC;
		for (unsigned int i = 0; i < 3; i++)
		{
			nIC = indices.buffer_content[neighborCA * 3 + i];
			if (std::get<2>(edges[edgeCA]) != nIC && std::get<3>(edges[edgeCA]) != nIC)
				break;
		}

		indices.buffer_content[neighborCA * 3] = indexC;
		indices.buffer_content[neighborCA * 3 + 1] = nIC;							//t1
		indices.buffer_content[neighborCA * 3 + 2] = index_mCA;

		if (neighborCA < marked.size())
			marked[neighborCA] = true;

		indices.buffer_content.push_back(index_mCA);
		indices.buffer_content.push_back(nIC);										//t2
		indices.buffer_content.push_back(indexA);
		nTriangles += 1;

		//neighbors[indexC].push_back(index_mCm);
		neighbors[indexA].push_back(nTriangles - 1);
		neighbors[nIC].push_back(nTriangles - 1);
		neighbors[index_mCA].push_back(nTriangles - 1);
		neighbors[index_mCA].push_back(neighborCA);

		std::list<unsigned int> nA;
		for (auto n : neighbors[indexA])
		{
			if (n != neighborCA)
				nA.push_back(n);
		}
		neighbors[indexA] = nA;
	}

	std::list<unsigned int> nB, nC;
	for (auto n : neighbors[indexB])
	{
		if (n != tri_index)
			nB.push_back(n);
	}
	neighbors[indexB] = nB;
	neighbors[indexB].push_back(index_mBm);

	for (auto n : neighbors[indexC])
	{
		if (n != tri_index)
			nC.push_back(n);
	}
	neighbors[indexC] = nC;
	neighbors[indexC].push_back(index_mCm);

	nTriangles = indices.buffer_content.size() / 3;

	//buildNeighbors(false);
	buildEdges();
	//updateDataOnGPU(device, immediateContext);
}

void Triangulator::draw(ID3D11DeviceContext* immediateContext, RenderMode mode)
{
	//computeColors(immediateContext);
	static int iteration = 0;
	iteration++;
	if ((iteration % delaunayEveryNthIteration) == 0 && delaunayUntilNthIteration > iteration)
	{
		delaunay(d3d->getDevice(), immediateContext);
		//delaunay_error_conscious(d3d->getDevice(), immediateContext);
		std::cout << "delaunay done" << std::endl;
		std::flush(std::cout);
	}

	if (mode == en_constant)
	{
#if 1	
		if (iteration < 1210)
		{
			computeGradients_rtt(immediateContext);
			std::cout << "gradients computed" << std::endl;
			updatePositions(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		if (iteration == -20 && iteration < 120)
		{
			//insertion(d3d->getDevice(), immediateContext);
			insertion2(d3d->getDevice(), immediateContext);
			std::cout << "size:                                                                        " << indices.buffer_content.size() / 3 << std::endl;
			//computeErrors(immediateContext);
			//float dev = compute_standard_deviation(immediateContext);

			/*errors.gpuToCpu(immediateContext);
			for (int i = 0; i < errors.buffer_content.size(); i++)
			{
				if (errors.buffer_content[i] > 0.25)
				{
					insert_vertex_center(i, d3d->getDevice(), immediateContext);
					//insert_triangle_into_triangle(i, d3d->getDevice(), immediateContext);
					std::cout << "vertex inserted" << std::endl;
				}
			}*/
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
		if (iteration == 50 && eliminate_degenerate_triangles(d3d->getDevice(), immediateContext))
		{
			std::cout << "eliminated at least one triangle" << std::endl;
			//Sleep(1000);
			std::cout << "sleeping end" << std::endl;
		}
#endif
		if (iteration == -10)//1256.296296, 253.33
			insert_vertex_center(100, d3d->getDevice(), immediateContext);
		//insert_triangle_into_triangle(647, d3d->getDevice(), immediateContext);
		computeConstantColors(immediateContext);

		if (iteration == -20)
		{
			colors.gpuToCpu(immediateContext);
			std::cout << colors.buffer_content[720].r << " " << colors.buffer_content[720].g << " " << colors.buffer_content[720].b << std::endl;
			std::cout << indices.buffer_content[720 * 3] << " " << indices.buffer_content[720 * 3 + 1] << " " << indices.buffer_content[720 * 3 + 2] << std::endl;
			std::cout << positions.buffer_content[210].x << " " << " " << positions.buffer_content[210].y << std::endl;
			std::cout << positions.buffer_content[190].x << " " << " " << positions.buffer_content[190].y << std::endl;
			std::cout << positions.buffer_content[397].x << " " << " " << positions.buffer_content[397].y << std::endl;
		}
		//ccc_bi_interp(immediateContext);

		//computePixelVariance(immediateContext);
		//pixel_variance.gpuToCpu(immediateContext);
		//for (int o = 0; o < pixel_variance.buffer_content.size(); o++)
			//std::cout << "pixel_variance: " << pixel_variance.buffer_content[o].r << " " << pixel_variance.buffer_content[o].g << " " << pixel_variance.buffer_content[o].b << std::endl;

		render(immediateContext, mode);
		//if (iteration > 10)
			//Sleep(500);
	}
	else if (mode == en_linear)
	{
		//updatePositions_linGrad(immediateContext);
		//computeLinearGradients(immediateContext);
		//clg_bi_interp(immediateContext);

		if (iteration < 1210)
		{
			computeGradients_cplg(immediateContext);
			std::cout << "gradients computed" << std::endl;
			updatePositions(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		computeLinearGradients(immediateContext);
		//clg_bi_interp(immediateContext);

		gradients_rtt.gpuToCpu(immediateContext);
		std::cout << gradients_rtt.buffer_content[0].grABCx << std::endl;

		//gradientCoefficients.gpuToCpu(immediateContext);
		//std::cout << gradientCoefficients.buffer_content[0].r_a << " " << gradientCoefficients.buffer_content[0].r_b << " " << gradientCoefficients.buffer_content[0].r_c << std::endl;
		//std::cout << gradientCoefficients.buffer_content[0].g_a << " " << gradientCoefficients.buffer_content[0].g_b << " " << gradientCoefficients.buffer_content[0].g_c << std::endl;
		//std::cout << gradientCoefficients.buffer_content[0].b_a << " " << gradientCoefficients.buffer_content[0].b_b << " " << gradientCoefficients.buffer_content[0].b_c << std::endl;

		/*gradientCoefficients.gpuToCpu(immediateContext);
		//std::cout << gradientCoefficients.buffer_content[51].r_b << std::endl;
		std::cout << "Triangle 51 - R_a " << gradientCoefficients.buffer_content[51].r_a << std::endl;
		std::cout << "Triangle 51 - R_b " << gradientCoefficients.buffer_content[51].r_b << std::endl;
		std::cout << "Triangle 51 - R_c " << gradientCoefficients.buffer_content[51].r_c << std::endl;
		std::cout << "Triangle 51 - G_a " << gradientCoefficients.buffer_content[51].g_a << std::endl;
		std::cout << "Triangle 51 - G_b " << gradientCoefficients.buffer_content[51].g_b << std::endl;
		std::cout << "Triangle 51 - G_c " << gradientCoefficients.buffer_content[51].g_c << std::endl;
		std::cout << "Triangle 51 - B_a " << gradientCoefficients.buffer_content[51].b_a << std::endl;
		std::cout << "Triangle 51 - B_b " << gradientCoefficients.buffer_content[51].b_b << std::endl;
		std::cout << "Triangle 51 - B_c " << gradientCoefficients.buffer_content[51].b_c << std::endl;*/
		render(immediateContext, mode);
	}
	//errorsPS.gpuToCpu(immediateContext);
	//computeErrors(immediateContext);
	//errors.gpuToCpu(immediateContext);
	//float errR = (float)errorsPS.buffer_content[254].r;// / (255.0f * 255.0f);
	//float errG = (float)errorsPS.buffer_content[254].g;// / (255.0f * 255.0f);
	//float errB = (float)errorsPS.buffer_content[254].b;// / (255.0f * 255.0f);
	//std::cout << "The error for the 154th triangle is: " << errR << ", " << errG << ", " << errB << std::endl;
	//std::cout << "The error for the 154th triangle is: " << (errR + errG + errB) / 3.0f << std::endl;
	//std::cout << "Without pixel shader: " << (errors.buffer_content[254]) / 3.0f << std::endl;
	if (computeErrorInPS) 
	{
		float err = computeImageErrorPS(d3d->getDevice(), immediateContext);
		std::cout << "The image error is: " << err << std::endl;
	}
	std::cout << iteration << " cycle(s) done" << std::endl;
}

void Triangulator::draw_fin_diff(ID3D11DeviceContext* immediateContext, RenderMode mode)
{
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
			float plmi = (iteration % 2 == 0) ? -1.0f : 1.0f;
			if (iteration % 5 == 1 || iteration % 5 == 2) 
			{
				finite_differences(plmi, immediateContext);
				std::cout << "colors " << plmi << " computed" << std::endl;
			}
			else if (iteration % 5 == 3 || iteration % 5 == 4)
			{
				computeErrors_fin_diff(plmi, immediateContext);
				std::cout << "errors " << plmi << " computed" << std::endl;
			}
			if (iteration % 5 == 0) 
			{
				updatePositions_fin_diff(immediateContext);
				//positions.gpuToCpu(immediateContext);
				//for (int o = 0; o < positions.buffer_content.size(); o++)
					//std::cout << "gradient of vertex " << o << ": " << positions.buffer_content[o].x << " " << positions.buffer_content[o].y << std::endl;
				std::cout << "positions updated" << std::endl;
				colors_fin_diff.gpuToCpu(immediateContext);
				errors_fin_diff.gpuToCpu(immediateContext);
				/*std::cout << "Ax, color_pl: " << colors_fin_diff.buffer_content[10].colors[0] << " " << colors_fin_diff.buffer_content[10].colors[1] << " " << colors_fin_diff.buffer_content[10].colors[2] << std::endl;
				std::cout << "Ax, color_mi: " << colors_fin_diff.buffer_content[10].colors[3] << " " << colors_fin_diff.buffer_content[10].colors[4] << " " << colors_fin_diff.buffer_content[10].colors[5] << std::endl;
				std::cout << "Bx, color_pl: " << colors_fin_diff.buffer_content[10].colors[12] << " " << colors_fin_diff.buffer_content[10].colors[13] << " " << colors_fin_diff.buffer_content[10].colors[14] << std::endl;
				std::cout << "Bx, color_mi: " << colors_fin_diff.buffer_content[10].colors[15] << " " << colors_fin_diff.buffer_content[10].colors[16] << " " << colors_fin_diff.buffer_content[10].colors[17] << std::endl;
				std::cout << "Ax, error_pl: " << errors_fin_diff.buffer_content[10].colors[0] << " " << errors_fin_diff.buffer_content[10].colors[1] << " " << errors_fin_diff.buffer_content[10].colors[2] << std::endl;
				std::cout << "Ax, error_mi: " << errors_fin_diff.buffer_content[10].colors[3] << " " << errors_fin_diff.buffer_content[10].colors[4] << " " << errors_fin_diff.buffer_content[10].colors[5] << std::endl;
				std::cout << "Bx, error_pl: " << errors_fin_diff.buffer_content[10].colors[12] << " " << errors_fin_diff.buffer_content[10].colors[13] << " " << errors_fin_diff.buffer_content[10].colors[14] << std::endl;
				std::cout << "Bx, error_mi: " << errors_fin_diff.buffer_content[10].colors[15] << " " << errors_fin_diff.buffer_content[10].colors[16] << " " << errors_fin_diff.buffer_content[10].colors[17] << std::endl;
				*/
			}
		}
		//if (iteration > 50)
		/*{
			gradients_rtt.gpuToCpu(immediateContext);
			for (int i = 0; i < gradients_rtt.buffer_content.size(); i++)
			{
				std::cout << "Triangle " << i << " gradient_x when moving C : " << gradients_rtt.buffer_content[i].grABCx << std::endl;
			}
		}*/
		/*if (iteration < 50 && eliminate_degenerate_triangles(d3d->getDevice(), immediateContext))
		{
			std::cout << "eliminated at least one triangle" << std::endl;
			//Sleep(1000);
			std::cout << "sleeping end" << std::endl;
		}*/
#endif
		computeConstantColors(immediateContext);
		render(immediateContext, mode);
	}

	std::cout << iteration << " cycle(s) done" << std::endl;
}

void Triangulator::drawV2(ID3D11DeviceContext* immediateContext, RenderMode mode)
{
	static int iteration = 1;
	
	/*if (iteration > 1) 
	{
		computeImageErrorCS(immediateContext);
		float err = getTotalError(d3d->getDevice(), immediateContext);
		std::cout << "The error computed by the compute shader is: " << err << std::endl;
	}*/

	//if (triangleGoal > nTriangles && delaunayUntilNthIteration > iteration)
	if (iteration == -120)// && (iteration % delaunayEveryNthIteration) == 0 && delaunayUntilNthIteration > iteration)
	{
		delaunay(d3d->getDevice(), immediateContext);
		std::cout << "delaunay done" << std::endl;
		std::flush(std::cout);
	}

	if (mode == en_constant)
	{
		if (iteration > 1)
		{
			errorsPS.gpuToCpu(immediateContext); //changed here (added)
		}
		if (iteration < 1210)
		{
			std::ofstream fs;
			//fs.open(filename + "_rtt_200.txt", std::ios::out | std::ios::app);
			//auto start = std::chrono::high_resolution_clock::now();
			computeGradients_rtt(immediateContext);
			//auto end = std::chrono::high_resolution_clock::now();
			//fs << indices.buffer_content.size() / 3 << ";" << (std::chrono::duration_cast<std::chrono::microseconds>(end - start)).count() << "\n";
			//fs.close();
			//computeGradients_bipct(immediateContext);
			std::cout << "gradients computed" << std::endl;
			updatePositions(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		if (iteration > 2 && triangleGoal > nTriangles) 
		{
			//std::cout << triangleGoal << " " << nTriangles << std::endl;
			insertionV3(d3d->getDevice(), immediateContext);
			//insertionV3_tri_in_tri(d3d->getDevice(), immediateContext);

			if (delaunayUntilNthIteration > iteration)
			{
				delaunay(d3d->getDevice(), immediateContext);
				std::cout << "delaunay done" << std::endl;
				std::flush(std::cout);
			}
		}

		if (triangleGoal > nTriangles && eliminate_degenerate_triangles(d3d->getDevice(), immediateContext))
		{
			std::cout << "eliminated at least one triangle" << std::endl;
			//Sleep(1000);
			std::cout << "sleeping end" << std::endl;
			//delaunay(d3d->getDevice(), immediateContext);
		}

		computeConstantColors(immediateContext);

		errorsPS.clearUAV(immediateContext, { 0, 0, 0, 0 }); 

		render(immediateContext, mode);
		//d3d->saveImageFromBackBuffer(filename);
	}
	else if (mode == en_linear)
	{
		if (iteration > 1)
		{
			errorsPS.gpuToCpu(immediateContext); 
		}
		if (iteration < 1210)
		{
			std::ofstream fs;
			fs.open(filename + "_rtt_speed_test.txt", std::ios::out | std::ios::app);
			auto start = std::chrono::high_resolution_clock::now();
			computeGradients_cplg(immediateContext);
			auto end = std::chrono::high_resolution_clock::now();
			fs << (std::chrono::duration_cast<std::chrono::microseconds>(end - start)).count() << "\n";
			fs.close();
			std::cout << "gradients computed" << std::endl;
			updatePositions(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		if (iteration > 2 && triangleGoal > nTriangles)
		{
			//std::cout << triangleGoal << " " << nTriangles << std::endl;
			insertionV3(d3d->getDevice(), immediateContext);
			//insertionV3_tri_in_tri(d3d->getDevice(), immediateContext);

			if (delaunayUntilNthIteration > iteration)
			{
				delaunay(d3d->getDevice(), immediateContext);
				std::cout << "delaunay done" << std::endl;
				std::flush(std::cout);
			}
		}

		if (triangleGoal > nTriangles && eliminate_degenerate_triangles(d3d->getDevice(), immediateContext))
		{
			std::cout << "eliminated at least one triangle" << std::endl;
			//Sleep(1000);
			std::cout << "sleeping end" << std::endl;
			//delaunay(d3d->getDevice(), immediateContext);
		}
		computeLinearGradients(immediateContext);
		errorsPS.clearUAV(immediateContext, { 0, 0, 0, 0 }); //changed here (added)
		render(immediateContext, mode);
		//d3d->saveImageFromBackBuffer(filename);
	}
	
	std::cout << iteration << " cycle(s) done" << std::endl;
	std::cout << nTriangles << " triangles are drawn" << std::endl;
	iteration++;
}

void Triangulator::drawV2_fin_diff(ID3D11DeviceContext* immediateContext, RenderMode mode)
{
	static int iteration = 1;

	/*if (iteration > 1)
	{
		computeImageErrorCS(immediateContext);
		float err = getTotalError(d3d->getDevice(), immediateContext);
		std::cout << "The error computed by the compute shader is: " << err << std::endl;
	}*/

	//if (triangleGoal > nTriangles && delaunayUntilNthIteration > iteration)
	if (0 && (iteration % (delaunayEveryNthIteration * 5)) == 0 && delaunayUntilNthIteration * 5 > iteration)
	{
		delaunay(d3d->getDevice(), immediateContext);
		//delaunay_error_conscious(d3d->getDevice(), immediateContext);
		std::cout << "delaunay done" << std::endl;
		std::flush(std::cout);
	}

	if (mode == en_constant)
	{
		if (iteration % 5 == 0 && iteration > 1)
		{
			errorsPS.gpuToCpu(immediateContext); //changed here (added)
		}
		if (iteration < 12100)
		{
			float plmi = (iteration % 2 == 0) ? -1.0f : 1.0f;
			if (iteration % 5 == 1 || iteration % 5 == 2)
			{
				//finite_differences(plmi, immediateContext);
				//std::cout << "colors " << plmi << " computed" << std::endl;
				color_fd(plmi, {plmi, 1, 0, 0, 0, 0, 0}, immediateContext);
				color_fd(plmi, {plmi, 0, 1, 0, 0, 0, 0}, immediateContext);
				color_fd(plmi, {plmi, 0, 0, 1, 0, 0, 0}, immediateContext);
				color_fd(plmi, {plmi, 0, 0, 0, 1, 0, 0}, immediateContext);
				color_fd(plmi, {plmi, 0, 0, 0, 0, 1, 0}, immediateContext);
				color_fd(plmi, {plmi, 0, 0, 0, 0, 0, 1}, immediateContext);
			}
			else if (iteration % 5 == 3 || iteration % 5 == 4)
			{
				//computeErrors_fin_diff(plmi, immediateContext);
				//std::cout << "errors " << plmi << " computed" << std::endl;
				errors_fd(plmi, { plmi, 1, 0, 0, 0, 0, 0 }, immediateContext);
				errors_fd(plmi, { plmi, 0, 1, 0, 0, 0, 0 }, immediateContext);
				errors_fd(plmi, { plmi, 0, 0, 1, 0, 0, 0 }, immediateContext);
				errors_fd(plmi, { plmi, 0, 0, 0, 1, 0, 0 }, immediateContext);
				errors_fd(plmi, { plmi, 0, 0, 0, 0, 1, 0 }, immediateContext);
				errors_fd(plmi, { plmi, 0, 0, 0, 0, 0, 1 }, immediateContext);
			}
			if (iteration % 5 == 0)
			{
				updatePositions_fin_diff(immediateContext);
				std::cout << "positions updated" << std::endl;
				//colors_fin_diff.gpuToCpu(immediateContext);
				//errors_fin_diff.gpuToCpu(immediateContext);
			}
		}
		if (iteration == 0)
		{
			CSInput.buffer_content.trustRegion = 1;
			CSInput.updateBuffer(immediateContext);
		}
		if (iteration % 5 == 0 && iteration > 2 && triangleGoal > nTriangles)
		{
			//std::cout << triangleGoal << " " << nTriangles << std::endl;
			insertionV3(d3d->getDevice(), immediateContext);
			//insertionV3_tri_in_tri(d3d->getDevice(), immediateContext);

			if (1 || delaunayUntilNthIteration > iteration)
			{
				delaunay(d3d->getDevice(), immediateContext);
				std::cout << "delaunay done" << std::endl;
				std::flush(std::cout);
			}
		}

		if (iteration % 5 == 0 && triangleGoal > nTriangles && eliminate_degenerate_triangles(d3d->getDevice(), immediateContext))
		{
			std::cout << "eliminated at least one triangle" << std::endl;
			//Sleep(1000);
			std::cout << "sleeping end" << std::endl;
		}

		if (iteration % 5 == 0)
			computeConstantColors(immediateContext);

		errorsPS.clearUAV(immediateContext, { 0, 0, 0, 0 }); //changed here (added)

		render(immediateContext, mode);
		if (iteration % 5 == 6) 
		{
			//d3d->saveImageFromBackBuffer(filename);
		}
	}
	else if (mode == en_linear)
	{
		if (iteration < 1210)
		{
			computeGradients_cplg(immediateContext);
			std::cout << "gradients computed" << std::endl;
			updatePositions(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		computeLinearGradients(immediateContext);

		render(immediateContext, mode);
	}

	if (computeErrorInPS)
	{
		//float err = computeImageErrorPS(d3d->getDevice(), immediateContext);
		//std::cout << "The image error is: " << err << std::endl;
	}
	if (iteration % 5 == 0) 
	{
		std::cout << iteration / 5 << " cycle(s) done" << std::endl;
		std::cout << nTriangles << " triangles are drawn" << std::endl;
	}
	iteration++;
}

void Triangulator::drawV3(ID3D11DeviceContext* immediateContext, RenderMode mode)
{
	static int iteration = 1;

	if (mode == en_constant)
	{
		computeErrors(immediateContext);
		errors.gpuToCpu(immediateContext);

		if (iteration < 1210)
		{
			computeGradients_rtt(immediateContext);
			std::cout << "gradients computed" << std::endl;
			updatePositions(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		if (iteration > 1 && triangleGoal > nTriangles) //was iteration > 2 before
		{
			insertionV4(d3d->getDevice(), immediateContext);

			if (delaunayUntilNthIteration > iteration)
			{
				delaunay(d3d->getDevice(), immediateContext);
				std::cout << "delaunay done" << std::endl;
				std::flush(std::cout);
			}
		}

		if (triangleGoal > nTriangles && eliminate_degenerate_triangles(d3d->getDevice(), immediateContext))
		{
			std::cout << "eliminated at least one triangle" << std::endl;
			//Sleep(1000);
			std::cout << "sleeping end" << std::endl;
		}

		computeConstantColors(immediateContext);

		render(immediateContext, mode);
		//d3d->saveImageFromBackBuffer(filename);
	}
	else if (mode == en_linear)
	{
		if (iteration < -1210)
		{
			computeGradients_cplg(immediateContext);
			std::cout << "gradients computed" << std::endl;
			updatePositions(immediateContext);
			std::cout << "positions updated" << std::endl;
		}
		computeLinearGradients(immediateContext);

		render(immediateContext, mode);
	}

	std::cout << iteration << " cycle(s) done" << std::endl;
	std::cout << nTriangles << " triangles are drawn" << std::endl;
	iteration++;
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
	
	ID3D11Buffer* CB_VS[] = { VSInput.getBuffer() };
	immediateContext->VSSetConstantBuffers(0, 1, CB_VS);
	
	if (!computeErrorInPS) 
	{
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


		//set render target
		ID3D11RenderTargetView* rtviews[] = { d3d->getRenderTargetView_Backbuffer() };
		immediateContext->OMSetRenderTargets(1, rtviews, d3d->getDepthStencilView_Backbuffer());
		//immediateContext->RSSetState();
	}
	else 
	{
		if (mode == en_constant)
		{
			immediateContext->PSSetShader(pPSWithError, NULL, 0);
			ID3D11ShaderResourceView* srvs[] = { colors.getShaderResourceView(), image->getShaderResourceView() };
			immediateContext->PSSetShaderResources(0, 2, srvs);
		}
		else if (mode == en_linear)
		{
			immediateContext->PSSetShader(pPSLinGradWithError, NULL, 0);
			ID3D11ShaderResourceView* srvs[] = { gradientCoefficients.getShaderResourceView(), image->getShaderResourceView() };
			immediateContext->PSSetShaderResources(0, 1, srvs);
		}

		ID3D11UnorderedAccessView* uavs[] = { errorsPS.getUnorderedAccessView() };


		//set render target
		ID3D11RenderTargetView* rtviews[] = { d3d->getRenderTargetView_Backbuffer() };
		UINT initialCounts[] = { 0, 0, 0, 0 };
		immediateContext->OMSetRenderTargetsAndUnorderedAccessViews(1, rtviews, d3d->getDepthStencilView_Backbuffer(), 1, 1, uavs, initialCounts);
	}
	//draw
	//immediatContext->Draw((UINT)sizeof(positions.buffer_content), 0);
	immediateContext->DrawIndexed((UINT)indices.buffer_content.size(), 0, 0);


	//cleanup
	if (!computeErrorInPS) 
	{
		ID3D11Buffer* clean_vb[] = { NULL };
		UINT clean_strides[] = { 0 };
		immediateContext->IASetVertexBuffers(0, 1, clean_vb, clean_strides, offsets);

		ID3D11ShaderResourceView* clean_srv[] = { NULL };
		immediateContext->PSSetShaderResources(0, 1, clean_srv);
	}
	else 
	{
		ID3D11Buffer* clean_vb[] = { NULL };
		UINT clean_strides[] = { 0 };
		immediateContext->IASetVertexBuffers(0, 1, clean_vb, clean_strides, offsets);

		ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL };
		immediateContext->PSSetShaderResources(0, 2, clean_srv);

		ID3D11UnorderedAccessView* clear_uavs[] = { NULL };
		UINT initialCounts[] = { 0, 0, 0, 0 };
		ID3D11RenderTargetView* clear_rtvs[] = { NULL };
		immediateContext->OMSetRenderTargetsAndUnorderedAccessViews(1, clear_rtvs, d3d->getDepthStencilView_Backbuffer(), 1, 1, clear_uavs, initialCounts);
	}
}

void Triangulator::computeConstantColors(ID3D11DeviceContext* immediateContext) 
{
	immediateContext->CSSetShader(pComputeConstantColor, NULL, 0);
	
	ID3D11ShaderResourceView* ccc_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, ccc_srv);

	ID3D11UnorderedAccessView* ccc_uav[] = { colors.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, ccc_uav, NULL);

	CSNum.buffer_content.num = indices.buffer_content.size() / 3;
	CSNum.updateBuffer(immediateContext);

	ID3D11Buffer* CB_CS[] = { CSNum.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	UINT groupsX = (UINT)colors.buffer_content.size();
	if (groupsX % 64 == 0)
		groupsX /= 64;
	else
		groupsX = groupsX / 64 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);

	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);
}

void Triangulator::computeLinearGradients(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputeLinearGradients, NULL, 0);

	ID3D11ShaderResourceView* ccc_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, ccc_srv);

	ID3D11UnorderedAccessView* ccc_uav[] = { gradientCoefficients.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, ccc_uav, NULL);

	CSNum.buffer_content.num = indices.buffer_content.size() / 3;
	CSNum.updateBuffer(immediateContext);

	ID3D11Buffer* CB_CS[] = { CSNum.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	//UINT groupsX = (UINT)colors.buffer_content.size();
	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 64 == 0)
		groupsX /= 64;
	else
		groupsX = groupsX / 64 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);

	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);
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
	if (groupsX % 64 == 0)
		groupsX /= 64;
	else
		groupsX = groupsX / 64 + 1;
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

void Triangulator::finite_differences(float plmi, ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pFiniteDifferences, NULL, 0);

	ID3D11ShaderResourceView* up_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, up_srv);

	ID3D11UnorderedAccessView* up_uav[] = { colors_fin_diff.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, up_uav, NULL);

	CSfin_diff_Input.buffer_content.dxA = 1.0f; CSfin_diff_Input.buffer_content.dxB = 0; CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyA = 0; CSfin_diff_Input.buffer_content.dyB = 0; CSfin_diff_Input.buffer_content.dyC = 0;
	CSfin_diff_Input.buffer_content.eps = plmi;
	CSfin_diff_Input.updateBuffer(immediateContext);

	ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 32 == 0)
		groupsX /= 32;
	else
		groupsX = groupsX / 32 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);											//dxA

	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxA = 0;
	CSfin_diff_Input.buffer_content.dyA = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyA

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyA = 0;
	CSfin_diff_Input.buffer_content.dxB = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxB

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxB = 0;
	CSfin_diff_Input.buffer_content.dyB = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyB

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyB = 0;
	CSfin_diff_Input.buffer_content.dxC = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxC

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyC = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyC

	/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	/*immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

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
	*/

	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);
}

void Triangulator::computeErrors_fin_diff(float plmi, ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputeErrors_fin_diff, NULL, 0);

	ID3D11ShaderResourceView* up_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), colors_fin_diff.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 4, up_srv);

	ID3D11UnorderedAccessView* up_uav[] = { errors_fin_diff.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, up_uav, NULL);

	CSfin_diff_Input.buffer_content.dxA = 1.0f; CSfin_diff_Input.buffer_content.dxB = 0; CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyA = 0; CSfin_diff_Input.buffer_content.dyB = 0; CSfin_diff_Input.buffer_content.dyC = 0;
	CSfin_diff_Input.buffer_content.eps = plmi;
	CSfin_diff_Input.updateBuffer(immediateContext);

	ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 32 == 0)
		groupsX /= 32;
	else
		groupsX = groupsX / 32 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);											//dxA

	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxA = 0;
	CSfin_diff_Input.buffer_content.dyA = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyA

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyA = 0;
	CSfin_diff_Input.buffer_content.dxB = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxB

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxB = 0;
	CSfin_diff_Input.buffer_content.dyB = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyB

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dyB = 0;
	CSfin_diff_Input.buffer_content.dxC = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dxC

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	CSfin_diff_Input.buffer_content.dxC = 0;
	CSfin_diff_Input.buffer_content.dyC = 1.0f;
	CSfin_diff_Input.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	immediateContext->Dispatch(groupsX, 1, 1);											//dyC


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 4, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);

	//ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);
}

void Triangulator::color_fd(float plmi, CB_FiniteDiffInput cb, ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pFiniteDifferences, NULL, 0);

	ID3D11ShaderResourceView* up_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, up_srv);

	ID3D11UnorderedAccessView* up_uav[] = { colors_fin_diff.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, up_uav, NULL);

	CSfin_diff_Input.buffer_content.dxA = cb.dxA; CSfin_diff_Input.buffer_content.dxB = cb.dxB; CSfin_diff_Input.buffer_content.dxC = cb.dxC;
	CSfin_diff_Input.buffer_content.dyA = cb.dyA; CSfin_diff_Input.buffer_content.dyB = cb.dyB; CSfin_diff_Input.buffer_content.dyC = cb.dyC;
	CSfin_diff_Input.buffer_content.eps = plmi;

	ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);
	CSfin_diff_Input.updateBuffer(immediateContext);

	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 64 == 0)
		groupsX /= 64;
	else
		groupsX = groupsX / 64 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);											
										

	//cleanup
	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::errors_fd(float plmi, CB_FiniteDiffInput cb, ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputeErrors_fin_diff, NULL, 0);

	ID3D11ShaderResourceView* up_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), colors_fin_diff.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 4, up_srv);

	ID3D11UnorderedAccessView* up_uav[] = { errors_fin_diff.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, up_uav, NULL);

	CSfin_diff_Input.buffer_content.dxA = cb.dxA; CSfin_diff_Input.buffer_content.dxB = cb.dxB; CSfin_diff_Input.buffer_content.dxC = cb.dxC;
	CSfin_diff_Input.buffer_content.dyA = cb.dyA; CSfin_diff_Input.buffer_content.dyB = cb.dyB; CSfin_diff_Input.buffer_content.dyC = cb.dyC;
	CSfin_diff_Input.buffer_content.eps = plmi;

	ID3D11Buffer* CB_CS[] = { CSfin_diff_Input.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);
	CSfin_diff_Input.updateBuffer(immediateContext);

	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 64 == 0)
		groupsX /= 64;
	else
		groupsX = groupsX / 64 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);

	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 4, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
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
	if (groupsX % 256 == 0)
		groupsX /= 256;
	else
		groupsX = groupsX / 256 + 1;
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

	ID3D11ShaderResourceView* up_srv[] = { indices.getShaderResourceView(), errors_fin_diff.getShaderResourceView(),
											neighbor_list.getShaderResourceView(), indices_in_neighbor_list.getShaderResourceView(),
											neighbor_count.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 6, up_srv);

	ID3D11UnorderedAccessView* up_uav[] = { positions.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, up_uav, NULL);

	ID3D11Buffer* CB_CS[] = { CSInput.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	UINT groupsX = (UINT)positions.buffer_content.size();
	if (groupsX % 256 == 0)
		groupsX /= 256;
	else
		groupsX = groupsX / 256 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL, NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 6, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);

	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);
}

void Triangulator::computeErrors(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputeErrors, NULL, 0);

	ID3D11ShaderResourceView* ccc_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), colors.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 4, ccc_srv);

	ID3D11UnorderedAccessView* ccc_uav[] = { errors.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, ccc_uav, NULL);

	UINT groupsX = (UINT)errors.buffer_content.size();
	if (groupsX % 64 == 0)
		groupsX /= 64;
	else
		groupsX = groupsX / 64 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 4, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::computePixelVariance(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputePixelVariance, NULL, 0);

	ID3D11ShaderResourceView* ccc_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 3, ccc_srv);

	ID3D11UnorderedAccessView* ccc_uav[] = { pixel_variance.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, ccc_uav, NULL);

	CSNum.buffer_content.num = indices.buffer_content.size() / 3;
	CSNum.updateBuffer(immediateContext);

	ID3D11Buffer* CB_CS[] = { CSNum.getBuffer() };
	immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	UINT groupsX = (UINT)pixel_variance.buffer_content.size();
	if (groupsX % 64 == 0)
		groupsX /= 64;
	else
		groupsX = groupsX / 64 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 3, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);

	ID3D11Buffer* clean_cb[] = { NULL };
	immediateContext->CSSetConstantBuffers(0, 1, clean_cb);
}

void Triangulator::computeImageErrorCS(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pComputeImageError, NULL, 0);

	ID3D11ShaderResourceView* srv[] = { image->getShaderResourceView(), d3d->getShaderResourceView_RT() };
	immediateContext->CSSetShaderResources(0, 2, srv);

	ID3D11UnorderedAccessView* uav[] = { errorCS.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, uav, NULL);

	//CSNum.buffer_content.num = indices.buffer_content.size() / 3;
	//CSNum.updateBuffer(immediateContext);

	//ID3D11Buffer* CB_CS[] = { CSNum.getBuffer() };
	//immediateContext->CSSetConstantBuffers(0, 1, CB_CS);

	UINT groupsX = (UINT)image->getWidth();
	if (groupsX % 16 == 0)
		groupsX /= 16;
	else
		groupsX = groupsX / 16 + 1;

	UINT groupsY = (UINT)image->getHeight();
	if (groupsY % 16 == 0)
		groupsY /= 16;
	else
		groupsY = groupsY / 16 + 1;
	immediateContext->Dispatch(groupsX, groupsY, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL };
	immediateContext->CSSetShaderResources(0, 2, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
}

void Triangulator::computeGradients_bipct(ID3D11DeviceContext* immediateContext)
{
	immediateContext->CSSetShader(pCG_bipct, NULL, 0);

	ID3D11ShaderResourceView* cg_srv[] = { positions.getShaderResourceView(), indices.getShaderResourceView(), colors.getShaderResourceView(), image->getShaderResourceView() };
	immediateContext->CSSetShaderResources(0, 4, cg_srv);

	ID3D11UnorderedAccessView* cg_uav[] = { gradients_rtt.getUnorderedAccessView() };
	immediateContext->CSSetUnorderedAccessViews(0, 1, cg_uav, NULL);


	UINT groupsX = (UINT)indices.buffer_content.size() / 3;
	if (groupsX % 32 == 0)
		groupsX /= 32;
	else
		groupsX = groupsX / 32 + 1;
	immediateContext->Dispatch(groupsX, 1, 1);


	//cleanup
	ID3D11ShaderResourceView* clean_srv[] = { NULL, NULL, NULL, NULL };
	immediateContext->CSSetShaderResources(0, 4, clean_srv);

	ID3D11UnorderedAccessView* clean_uav[] = { NULL };
	immediateContext->CSSetUnorderedAccessViews(0, 1, clean_uav, NULL);
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

float Triangulator::compute_standard_deviation(ID3D11DeviceContext* immediateContext) 
{
	//errors.gpuToCpu(immediateContext);

	float mean = 0;
	for (int i = 0; i < errors.buffer_content.size(); i++) 
	{
		mean += errors.buffer_content[i];
	}
	//std::cout << "mean before division: " << mean << std::endl;
	mean /= (float)errors.buffer_content.size();
	//std::cout << "mean: " << mean << std::endl;
	float dev = 0;
	for (int i = 0; i < errors.buffer_content.size(); i++)
	{
		dev += (errors.buffer_content[i] - mean) * (errors.buffer_content[i] - mean);
	}
	dev = sqrt(dev / (errors.buffer_content.size() - 1));

	return dev;
}

float Triangulator::compute_standard_deviation2(ID3D11DeviceContext* immediateContext)
{
	float mean = 0;
	for (int i = 0; i < pixel_variance.buffer_content.size(); i++) 
	{
		mean += (pixel_variance.buffer_content[i].r + pixel_variance.buffer_content[i].g + pixel_variance.buffer_content[i].b) / 3.0f;
	}
	mean /= (float)pixel_variance.buffer_content.size();

	float dev = 0;
	for (int i = 0; i < pixel_variance.buffer_content.size(); i++) 
	{
		float rgb = (pixel_variance.buffer_content[i].r + pixel_variance.buffer_content[i].g + pixel_variance.buffer_content[i].b) / 3.0f;
		dev += (rgb - mean) * (rgb - mean);
	}
	dev = sqrt(dev / (pixel_variance.buffer_content.size() - 1));

	return dev;
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

void Triangulator::delaunay_error_conscious(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
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
			//only flip if error does NOT get much worse
			Vec3f col1 = tri_overlap_color(A, B, C);
			Vec3f col2 = tri_overlap_color(A, B, D);

			float err1 = computeErrorCPU(A, B, C, col1);
			float err2 = computeErrorCPU(A, B, D, col2);

			col1 = tri_overlap_color(A, D, C);
			col2 = tri_overlap_color(B, D, C);

			float err3 = computeErrorCPU(A, D, C, col1);
			float err4 = computeErrorCPU(B, D, C, col2);

			if (err1 + err2 < err3 + err4) 
			{
				std::cout << "Would have flipped, but error would have gotten bigger!" << std::endl;
				continue;
			}

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
{
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
				
				//std::cout << indices.buffer_content.size() << " " << tri_index * 3 << " " << neighbor_index * 3 << " " << std::endl;
				
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

				unsigned int min = tri_index < neighbor_index ? tri_index : neighbor_index;
				unsigned int max = tri_index > neighbor_index ? tri_index : neighbor_index;
				for (int k = max; k < indices.buffer_content.size() / 3 - 1; k++) 
				{
					indices.buffer_content[k * 3] = indices.buffer_content[(k + 1) * 3];
					indices.buffer_content[k * 3 + 1] = indices.buffer_content[(k + 1) * 3 + 1];
					indices.buffer_content[k * 3 + 2] = indices.buffer_content[(k + 1) * 3 + 2];
				}
				indices.buffer_content.resize(indices.buffer_content.size() - 3);

				for (int k = min; k < indices.buffer_content.size() / 3 - 1; k++)
				{
					indices.buffer_content[k * 3] = indices.buffer_content[(k + 1) * 3];
					indices.buffer_content[k * 3 + 1] = indices.buffer_content[(k + 1) * 3 + 1];
					indices.buffer_content[k * 3 + 2] = indices.buffer_content[(k + 1) * 3 + 2];
				}
				indices.buffer_content.resize(indices.buffer_content.size() - 3);
				nTriangles -= 2;
				//remove the two collapsing triangles
				/*nTriangles -= 1;
				//std::cout << "tri_index: " << tri_index << std::endl;
				indices.buffer_content[tri_index * 3] = indices.buffer_content[nTriangles * 3];
				indices.buffer_content[tri_index * 3 + 1] = indices.buffer_content[nTriangles * 3 + 1];
				indices.buffer_content[tri_index * 3 + 2] = indices.buffer_content[nTriangles * 3 + 2];
				//std::cout << "tri_index: " << tri_index << " " << indices.buffer_content[tri_index * 3] << " " << indices.buffer_content[tri_index * 3 + 1] << " " << indices.buffer_content[tri_index * 3 + 2] << std::endl;
				nTriangles -= 1;
				std::cout << "neighbor_index: " << neighbor_index << " indices size: " << indices.buffer_content.size() << " nTriangles: " << nTriangles << std::endl;
				indices.buffer_content[neighbor_index * 3] = indices.buffer_content[nTriangles * 3];
				indices.buffer_content[neighbor_index * 3 + 1] = indices.buffer_content[nTriangles * 3 + 1];
				indices.buffer_content[neighbor_index * 3 + 2] = indices.buffer_content[nTriangles * 3 + 2];
				indices.buffer_content.resize(indices.buffer_content.size() - 3);
				indices.buffer_content.resize(indices.buffer_content.size() - 3);*/
				//std::cout << "neighbor_index: " << neighbor_index << " " << indices.buffer_content[neighbor_index * 3] << " " << indices.buffer_content[neighbor_index * 3 + 1] << " " << indices.buffer_content[neighbor_index * 3 + 2] << std::endl;

				//remove the vertex
				for (int j = indexB; j < positions.buffer_content.size() - 1; j++) 
				{
					positions.buffer_content[j] = positions.buffer_content[j + 1];
					is_on_border[j] = is_on_border[j + 1];
				}
				
				positions.buffer_content.resize(positions.buffer_content.size() - 1);
				is_on_border.resize(positions.buffer_content.size());
				
				//adjust the indices
				std::cout << indexA << " " << indexB << std::endl;
				for (int j = 0; j < indices.buffer_content.size(); j++) 
				{
					if (indices.buffer_content[j] > indexB)
						indices.buffer_content[j]--;
					if (indices.buffer_content[j] >= positions.buffer_content.size())
						std::cout << "j: " << j << " indices: " << indices.buffer_content[j] << " positions.size: " << positions.buffer_content.size() << std::endl;
				}
				std::cout << "check 1" << std::endl;
				buildNeighbors(false);
				std::cout << "check 2" << std::endl;
				buildEdges();
				break;
			}
		}
	}

	if (changes_made) 
	{	
		updateDataOnGPU(device, immediateContext);
		return true;
	}
	return false;
}

int Triangulator::insertion(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	int n_before = indices.buffer_content.size() / 3;

	computeErrors(immediateContext);
	errors.gpuToCpu(immediateContext);

	float dev = compute_standard_deviation(immediateContext);
	std::cout << "standard deviation: " << dev << std::endl;
	
	std::vector<bool> marked;
	marked.resize(indices.buffer_content.size() / 3, false);

	positions.gpuToCpu(immediateContext);
	for (int i = 0; i < n_before; i++)
	{
		//if (i % 10 == 0)
		if (errors.buffer_content[i] > dev && !marked[i])
		{
			std::cout << "error: " << errors.buffer_content[i] << std::endl;
			//insert_vertex_center(i, d3d->getDevice(), immediateContext);
			insert_triangle_into_triangle(i, marked, d3d->getDevice(), immediateContext);
			std::cout << "vertex inserted" << std::endl;
		}
	}

	int n_after = indices.buffer_content.size() / 3;
	updateDataOnGPU(device, immediateContext);
	std::cout << "now there are " << nTriangles << " triangles" << std::endl;
	return n_after - n_before;
}

int Triangulator::insertion2(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	int n_before = indices.buffer_content.size() / 3;

	computePixelVariance(immediateContext);
	pixel_variance.gpuToCpu(immediateContext);

	float dev = compute_standard_deviation2(immediateContext);
	std::cout << "standard deviation: " << dev << std::endl;

	std::vector<bool> marked;
	marked.resize(indices.buffer_content.size() / 3, false);

	positions.gpuToCpu(immediateContext);
	for (int i = 0; i < n_before; i++)
	{
		//if (i % 10 == 0)
		if ((pixel_variance.buffer_content[i].r + pixel_variance.buffer_content[i].g + pixel_variance.buffer_content[i].b) / 3.0f > dev && !marked[i])
		{
			std::cout << "error: " << errors.buffer_content[i] << std::endl;
			//insert_vertex_center(i, d3d->getDevice(), immediateContext);
			insert_triangle_into_triangle(i, marked, d3d->getDevice(), immediateContext);
			std::cout << "vertex inserted" << std::endl;
		}
	}

	int n_after = indices.buffer_content.size() / 3;
	updateDataOnGPU(device, immediateContext);
	std::cout << "now there are " << nTriangles << " triangles" << std::endl;
	return n_after - n_before;
}

int Triangulator::insertionV3(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	positions.gpuToCpu(immediateContext);
	int n_before = indices.buffer_content.size() / 3;
	static float threshold = 1.0f;
	//errorsPS.gpuToCpu(immediateContext); //changed here

	//std::vector<int> trianglesToInsertInto;
	std::vector<std::pair<int, float>> trianglesToInsertInto;
	
	for (unsigned int i = 0; i < errorsPS.buffer_content.size(); i++) 
	{
		Vec4u err = errorsPS.buffer_content[i];
		//std::cout << "errorPS: " << err.r << " " << err.g << " " << err.b << std::endl;
		Vec3f errf = { err.r / (255.0f * 255.0f), err.g / (255.0f * 255.0f), err.b / (255.0f * 255.0f) };
		float errS = (errf.r + errf.g + errf.b) / 3.0f;
		errS /= image->getWidth() * image->getHeight();
		errS = (float)(sqrt(errS) * 255.0f);
		//std::cout << "Triangle error from PS: " << errS << std::endl;
		if (errS > threshold)									//changed here (before: 3.0f), changed again (before: 1.0f)
			trianglesToInsertInto.push_back(std::make_pair(i, errS));
			//trianglesToInsertInto.push_back(i);
	}

	if (trianglesToInsertInto.size() == 0) 
	{
		//threshold = threshold - 0.1f < 0 ? 0.1f : threshold - 0.1f;
		triangleGoal = nTriangles;
	}

	std::sort(trianglesToInsertInto.begin(), trianglesToInsertInto.end(), sort_pred());

	//int size = 25 < trianglesToInsertInto.size() ? 25 : trianglesToInsertInto.size();

	for (int i = 0; i < trianglesToInsertInto.size(); i++)
	{
		//unsigned int tri = trianglesToInsertInto[i];
		unsigned int tri = trianglesToInsertInto[i].first;
		if (nTriangles < triangleGoal)
			insert_vertex_center(tri, device, immediateContext);
		//else
			//triangleGoal = nTriangles;
	}

	int n_after = indices.buffer_content.size() / 3;
	//errorsPS.clearUAV(immediateContext, { 0, 0, 0, 0 });	//changed here (commented out)
	updateDataOnGPU(device, immediateContext);			//changed here (commented out)

	return n_after - n_before;
}

int Triangulator::insertionV3_tri_in_tri(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	positions.gpuToCpu(immediateContext);
	int n_before = indices.buffer_content.size() / 3;
	static float threshold = 1.0f;

	std::vector<bool> marked;
	marked.resize(indices.buffer_content.size() / 3, false);

	std::vector<std::pair<int, float>> trianglesToInsertInto;

	for (unsigned int i = 0; i < errorsPS.buffer_content.size(); i++)
	{
		Vec4u err = errorsPS.buffer_content[i];
		Vec3f errf = { err.r / (255.0f * 255.0f), err.g / (255.0f * 255.0f), err.b / (255.0f * 255.0f) };
		float errS = (errf.r + errf.g + errf.b) / 3.0f;
		errS /= image->getWidth() * image->getHeight();
		errS = (float)(sqrt(errS) * 255.0f);
		if (errS > threshold)									
			trianglesToInsertInto.push_back(std::make_pair(i, errS));
	}

	if (trianglesToInsertInto.size() == 0)
	{
		//threshold = threshold - 0.3f < 0 ? 0.1f : threshold - 0.3f;
		triangleGoal = nTriangles;
	}

	std::sort(trianglesToInsertInto.begin(), trianglesToInsertInto.end(), sort_pred());

	for (int i = 0; i < trianglesToInsertInto.size(); i++)
	{
		//unsigned int tri = trianglesToInsertInto[i];
		unsigned int tri = trianglesToInsertInto[i].first;
		if (nTriangles < triangleGoal)
			insert_triangle_into_triangle(tri, marked, device, immediateContext);
	}

	int n_after = indices.buffer_content.size() / 3;
	//errorsPS.clearUAV(immediateContext, { 0, 0, 0, 0 });	//changed here (commented out)
	updateDataOnGPU(device, immediateContext);			//changed here (commented out)

	return n_after - n_before;
}

int Triangulator::insertionV4(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	int n_before = indices.buffer_content.size() / 3;
	static bool first_iter = true;
	float total = 0;
	if (first_iter) 
	{
		for (int i = 0; i < errors.buffer_content.size(); i++) 
		{
			float err = errors.buffer_content[i];
			err = err * 0.5f * 255 * 255;
			err = sqrt(err);
			total += err;
		}
		total /= errors.buffer_content.size();
		first_iter = false;
	}

	//static float threshold = first_iter ? total : threshold;//10.0f;
	static float threshold = 10.0f;
	float decrement = 3.0f;

	std::vector<std::pair<int, float>> trianglesToInsertInto;

	for (unsigned int i = 0; i < errors.buffer_content.size(); i++)
	{
		float errS = errors.buffer_content[i];
		errS = errS * 0.5f * 255 * 255;
		errS = sqrt(errS);
		std::cout << "error from CS is: " << errS << std::endl;
		if (errS > threshold)									
			trianglesToInsertInto.push_back(std::make_pair(i, errS));
	}

	if (trianglesToInsertInto.size() == 0)
		threshold = threshold - decrement < 0 ? 1.0f : threshold - decrement;

	std::sort(trianglesToInsertInto.begin(), trianglesToInsertInto.end(), sort_pred());

	for (int i = 0; i < trianglesToInsertInto.size(); i++)
	{
		unsigned int tri = trianglesToInsertInto[i].first;
		if (nTriangles < triangleGoal)
			insert_vertex_center(tri, device, immediateContext);
	}

	int n_after = indices.buffer_content.size() / 3;
	updateDataOnGPU(device, immediateContext);			

	return n_after - n_before;
}

float Triangulator::computeImageErrorPS(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	//errorsPS.gpuToCpu(immediateContext);

	int pixels = 0;
	float err = 0;
	float total = 0;
	for (int i = 0; i < errorsPS.buffer_content.size(); i++) 
	{
		float denom = 255.0f * 255.0f;
		float errR = errorsPS.buffer_content[i].r / denom;
		float errG = errorsPS.buffer_content[i].g / denom;
		float errB = errorsPS.buffer_content[i].b / denom;
		err = (errR + errG + errB) / 3.0f;
		//err *= errorsPS.buffer_content[i].a / ((float)image->getWidth() * (float)image->getHeight());
		err /= (float)image->getWidth() * (float)image->getHeight();
		err = (float)(sqrt(err) * 255.0f);

		total += err;
		pixels += errorsPS.buffer_content[i].a;
	}
	//std::cout << "pixel count: " << pixels << std::endl;
	//errorsPS.clearUAV(immediateContext, { 0, 0, 0, 0 });
	//errorsPS.buffer_content.clear();
	//errorsPS.buffer_content.resize(indices.buffer_content.size() / 3, { 0, 0, 0, 0 });
	//errorsPS.cpuToGpu(device, immediateContext);

	return total;
}

float Triangulator::getTotalError(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	errorCS.gpuToCpu(immediateContext);
	int pixels = 0;
	float err = 0;
	float total = 0;
	for (int i = 0; i < errorCS.buffer_content.size(); i++)
	{
		float denom = 255.0f * 255.0f;
		float errR = errorCS.buffer_content[i].r / denom;
		float errG = errorCS.buffer_content[i].g / denom;
		float errB = errorCS.buffer_content[i].b / denom;
		err = (errR + errG + errB) / 3.0f;
		//err *= errorsPS.buffer_content[i].a / ((float)image->getWidth() * (float)image->getHeight());
		err /= (float)image->getWidth() * (float)image->getHeight();
		err = (float)(sqrt(err) * 255.0f);

		total += err;
		pixels += errorCS.buffer_content[i].a;
	}
	//std::cout << "pixel count: " << pixels << std::endl;

	errorCS.clearUAV(immediateContext, { 0, 0, 0, 0 });

	return total;
}

void Triangulator::updateDataOnGPU(ID3D11Device* device, ID3D11DeviceContext* immediateContext)
{
	buildNeighborBuffers();
	
	positions.cpuToGpu(device, immediateContext);
	indices.cpuToGpu(device, immediateContext);
	indices_in_neighbor_list.cpuToGpu(device, immediateContext);
	neighbor_count.cpuToGpu(device, immediateContext);
	neighbor_list.cpuToGpu(device, immediateContext);

	colors.buffer_content.resize(indices.buffer_content.size() / 3);
	colors.cpuToGpu(device, immediateContext);

	gradientCoefficients.buffer_content.resize(indices.buffer_content.size() / 3);
	gradientCoefficients.cpuToGpu(device, immediateContext);

	gradients_rtt.buffer_content.resize(indices.buffer_content.size() / 3);
	gradients_rtt.cpuToGpu(device, immediateContext);

	colors_fin_diff.buffer_content.resize(indices.buffer_content.size() / 3);
	colors_fin_diff.cpuToGpu(device, immediateContext);

	errors_fin_diff.buffer_content.resize(indices.buffer_content.size() / 3);
	errors_fin_diff.cpuToGpu(device, immediateContext);

	errors.buffer_content.resize(indices.buffer_content.size() / 3);
	errors.cpuToGpu(device, immediateContext);

	errorsPS.buffer_content.resize(indices.buffer_content.size() / 3);
	errorsPS.cpuToGpu(device, immediateContext);

	pixel_variance.buffer_content.resize(indices.buffer_content.size() / 3);
	pixel_variance.cpuToGpu(device, immediateContext);
}

void Triangulator::createRegularGrid()
{
	triangleGoal = 10000;
	//triangleGoal = 800;
	int startingTriangleCount = 200;
	//int startingTriangleCount = 1000;
	if (nTriangles < startingTriangleCount)
		startingTriangleCount = nTriangles;

	const int GRID_SPACING_CONSTANT = (int)round(sqrt(startingTriangleCount / 2));

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

	//nTriangles = 2 * GRID_SPACING_CONSTANT * GRID_SPACING_CONSTANT;
	nTriangles = indices.buffer_content.size() / 3;
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
		if (indA == indB || indA == indC || indB == indC) 
		{
			std::cout << indA << " " << indB << " " << indC << " " << tri_index << std::endl;
		}
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
		//colors_fin_diff.buffer_content.push_back({ 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f });
		//colors_fin_diff.buffer_content.push_back(c);
		//errors_fin_diff.buffer_content.push_back(c);
	}
	Vec36f c = { {0} };
	colors_fin_diff.buffer_content.resize(nTriangles, c);
	errors_fin_diff.buffer_content.resize(nTriangles, c);
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

void Triangulator::writeErrorToFile(std::string file, int iteration, float error)
{
	std::ofstream fs;
	fs.open(file, std::ios::out | std::ios::app);

	//fs << "Iteration;Error;\n";
	//for (int i = 0; i < errorsPS.buffer_content.size(); i++) 
	//{
	fs << iteration << ";" << error << ";\n";
	//}

	fs.close();
}

float Triangulator::dot(const Vec2f& v, const Vec2f& w)
{
	return v.x * w.x + v.y * w.y;
}

Vec2f Triangulator::normal_in(const Vec2f& v, const Vec2f& w)
{
	Vec2f n = { v.y, -v.x };
	if (dot(n, w) <= 0)
		n = { -n.x, -n.y };
	return n;
}

bool Triangulator::point_inside_triangle(const Vec2f& p, const Vec2f& A, const Vec2f& B, const Vec2f& C)
{
	Vec2f ab = { B.x - A.x, B.y - A.y };
	Vec2f ac = { C.x - A.x, C.y - A.y };
	Vec2f bc = { C.x - B.x, C.y - B.y };

	if (dot(normal_in(ab, ac), { p.x - A.x, p.y - A.y }) <= 0 || dot(normal_in(ac, ab), { p.x - A.x, p.y - A.y }) <= 0 || dot(normal_in(bc, { -ab.x, -ab.y }), { p.x - B.x, p.y - B.y }) <= 0)
		return false;
	return true;
}

Vec3f Triangulator::tri_overlap_color(const Vec2f& A, const Vec2f& B, const Vec2f& C)
{
	float triangle_area = tri_area(A, B, C);

	float t = A.x < B.x ? A.x : B.x;
	float min_x = t < C.x ? t : C.x;
	t = A.x > B.x ? A.x : B.x;
	float max_x = t > C.x ? t : C.x;

	t = A.y < B.y ? A.y : B.y;
	float min_y = t < C.y ? t : C.y;
	t = A.y > B.y ? A.y : B.y;
	float max_y = t > C.y ? t : C.y;

	int pixel_right_x = floor(min_x);
	int pixel_bottom_y = floor(min_y);
	int pixel_left_x = ceil(max_x);
	int pixel_top_y = ceil(max_y);

	Vec3f color = { 0, 0, 0 };
	for (int i = pixel_right_x; i < pixel_left_x; i++)
	{
		for (int j = pixel_bottom_y; j < pixel_top_y; j++)
		{
			std::vector<Vec2f> polygon;

			float area = 0.0f;
			bool whole_pixel = true;

			Vec2f x1y1 = { i, j };
			Vec2f x2y1 = { i + 1, j };
			Vec2f x1y2 = { i, j + 1 };
			Vec2f x2y2 = { i + 1, j + 1 };

			if (point_inside_triangle(x1y1, A, B, C))
			{
				polygon.push_back(x1y1); 
			}
			else
				whole_pixel = false;
			if (point_inside_triangle(x2y1, A, B, C))
			{
				polygon.push_back(x2y1);
			}
			else
				whole_pixel = false;
			if (point_inside_triangle(x1y2, A, B, C))
			{
				polygon.push_back(x1y2);
			}
			else
				whole_pixel = false;
			if (point_inside_triangle(x2y2, A, B, C))
			{
				polygon.push_back(x2y2);
			}
			else
				whole_pixel = false;

			if (whole_pixel)
			{
				area = 1.0f;
			}
			else 
			{
				//TODO
			}
			float fraction = area / triangle_area;

			Vec3f pixel_color = image->at(i, j);
			color = { color.r + fraction * pixel_color.r, color.g + fraction * pixel_color.g , color.b + fraction * pixel_color.b };
		}
	}
	return color;
}

float Triangulator::computeErrorCPU(const Vec2f& A, const Vec2f& B, const Vec2f& C, const Vec3f& color)
{
	float triangle_area = tri_area(A, B, C);

	float t = A.x < B.x ? A.x : B.x;
	float min_x = t < C.x ? t : C.x;
	t = A.x > B.x ? A.x : B.x;
	float max_x = t > C.x ? t : C.x;

	t = A.y < B.y ? A.y : B.y;
	float min_y = t < C.y ? t : C.y;
	t = A.y > B.y ? A.y : B.y;
	float max_y = t > C.y ? t : C.y;

	int pixel_right_x = floor(min_x);
	int pixel_bottom_y = floor(min_y);
	int pixel_left_x = ceil(max_x);
	int pixel_top_y = ceil(max_y);

	float error = 0;
	for (int i = pixel_right_x; i < pixel_left_x; i++)
	{
		for (int j = pixel_bottom_y; j < pixel_top_y; j++)
		{
			std::vector<Vec2f> polygon;

			float area = 0.0f;
			bool whole_pixel = true;

			Vec2f x1y1 = { i, j };
			Vec2f x2y1 = { i + 1, j };
			Vec2f x1y2 = { i, j + 1 };
			Vec2f x2y2 = { i + 1, j + 1 };

			if (point_inside_triangle(x1y1, A, B, C))
			{
				polygon.push_back(x1y1);
			}
			else
				whole_pixel = false;
			if (point_inside_triangle(x2y1, A, B, C))
			{
				polygon.push_back(x2y1);
			}
			else
				whole_pixel = false;
			if (point_inside_triangle(x1y2, A, B, C))
			{
				polygon.push_back(x1y2);
			}
			else
				whole_pixel = false;
			if (point_inside_triangle(x2y2, A, B, C))
			{
				polygon.push_back(x2y2);
			}
			else
				whole_pixel = false;

			if (whole_pixel)
			{
				area = 1.0f;
			}
			else
			{
				//TODO
			}
			float fraction = area / triangle_area;

			Vec3f pixel_color = image->at(i, j);
			float errR = fraction * (pixel_color.r - color.r) * (pixel_color.r - color.r);
			float errG = fraction * (pixel_color.g - color.g) * (pixel_color.g - color.g);
			float errB = fraction * (pixel_color.b - color.b) * (pixel_color.b - color.b);
			error += errR + errG + errB;
		}
	}
	return error;
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
		errors.buffer_content.push_back(0.0f);
	}
	errorsPS.buffer_content.resize(nTriangles, { 0, 0, 0, 0 });
	pixel_variance.buffer_content.resize(nTriangles, {0, 0, 0});
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
	/*positions.buffer_content.push_back({800.0f / 18.0f * 11.0f, 600.0f / 18.0f * 2.0f});
	positions.buffer_content.push_back({800.0f/18.0f * 12.0f, 600.0f / 18.0f * 3.0f});
	positions.buffer_content.push_back({800.0f/18.0f * 11.0f, 600.0f / 18.0f * 3.0f});*/

	positions.buffer_content.push_back({1280.0f/18.0f, 720.0f / 18.0f * 11.0f});
	positions.buffer_content.push_back({0.0f, 720.0f / 18.0f * 10.0f});
	positions.buffer_content.push_back({(1280.0f/18.0f * 2.0f) / 3.0f, (720.0f / 18.0f * 10.0f * 2.0f + 720.0f / 18.0f * 11.0f) / 3.0f});
	
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
