#pragma once

#include "common.h"
#include "D3D.h"
#include "Image.h"
#include <Eigen/Dense>
#include <stack>

enum RenderMode
{
	en_constant,
	en_linear
};

struct CB_VSInput 
{
	Mat4x4f projMatrix;
};

struct CB_UpdatePosInput 
{
	float stepSize;
	int width;
	int height;
};

class Triangulator 
{
	public:
		Triangulator(ImageView* image, D3D* pD3D, int numTriangles);
		~Triangulator();

		bool create(ID3D11Device* device);
		void release();

		void draw(ID3D11DeviceContext* immediatContext, RenderMode mode);
	private:
		void render(ID3D11DeviceContext* immediateContext, RenderMode mode);
		void computeConstantColors(ID3D11DeviceContext* immediateContext);
		void computeLinearGradients(ID3D11DeviceContext* immediateContext);
		void updatePositions(ID3D11DeviceContext* immediateContext);

		void delaunay(ID3D11Device* device, ID3D11DeviceContext* immediateContext);

		void createRegularGrid();
		void buildNeighbors();
		void buildNeighborBuffers();
		void buildEdges();

		int get_edge_index(unsigned int v1, unsigned int v2);

		ImageView* image;

		int nTriangles;

		int delaunayEveryNthIteration;
		int delaunayUntilNthIteration;

		D3D* d3d;

		SharedByteAddressBuffer<Vec2f> positions;							//triangle vertices
		SharedByteAddressBuffer<unsigned int> indices;						//triangle list
		SharedByteAddressBuffer<bool> is_on_border;							//same size as vertex list; true if vertex is on the edge of the image
		SharedByteAddressBuffer<Vec3f> colors;								//constant triangle color (RGB-values)
		SharedByteAddressBuffer<Vec9f> gradientCoefficients;				//linear color gradient coefficients
		SharedByteAddressBuffer<unsigned int> neighbor_list;				//list of neighboring triangles for each vertex
		SharedByteAddressBuffer<unsigned int> indices_in_neighbor_list;		//index for each vertex, where in the list its neighbors start
		SharedByteAddressBuffer<unsigned int> neighbor_count;				//count of neighboring triangles for each vertex

		std::vector<std::list<unsigned int> > neighbors;														//neighbors on CPU-side for (hopefully) faster delaunay
		std::vector<std::tuple<unsigned int, unsigned int, unsigned int, unsigned int> > edges;					//edges that have two adjacent triangles

		ID3D11InputLayout* pInputLayout;

		ID3D11VertexShader* pVertexShader;
		ID3D11PixelShader* pPixelShader;
		ID3D11PixelShader* pPSLinearGradients;

		ID3D11ComputeShader* pComputeConstantColor;
		ID3D11ComputeShader* pComputeLinearGradients;
		ID3D11ComputeShader* pUpdatePositions_cc;

		ConstantBuffer<CB_VSInput> VSInput;
		ConstantBuffer<CB_UpdatePosInput> CSInput;

		//debug and testing
		void createTestVertices();
		void setRandomColors();
};
