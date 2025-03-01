#pragma once

#include "common.h"
#include "D3D.h"
#include "Image.h"
#include <Eigen/Dense>

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

		void draw(ID3D11DeviceContext* immediatContext);
	private:
		void render(ID3D11DeviceContext* immediateContext);
		void computeColors(ID3D11DeviceContext* immediateContext);
		void updatePositions(ID3D11DeviceContext* immediateContext);

		void createRegularGrid();
		void buildNeighbors();

		ImageView* image;

		int nTriangles;

		D3D* d3d;

		SharedByteAddressBuffer<Vec2f> positions;							//triangle vertices
		SharedByteAddressBuffer<unsigned int> indices;						//triangle list
		SharedByteAddressBuffer<bool> is_on_border;							//same size as vertex list; true if vertex is on the edge of the image
		SharedByteAddressBuffer<Vec3f> colors;								//constant triangle color: RGB-values; linear color gradient: coefficients
		SharedByteAddressBuffer<unsigned int> neighbor_list;				//list of neighboring triangles for each vertex
		SharedByteAddressBuffer<unsigned int> indices_in_neighbor_list;		//index for each vertex, where in the list its neighbors start
		SharedByteAddressBuffer<unsigned int> neighbor_count;				//count of neighboring triangles for each vertex
		ID3D11Buffer* edges;					//edges that have two adjacent triangles

		ID3D11InputLayout* pInputLayout;

		ID3D11VertexShader* pVertexShader;
		ID3D11PixelShader* pPixelShader;

		ID3D11ComputeShader* pComputeConstantColor;
		ID3D11ComputeShader* pUpdatePositions_cc;

		ConstantBuffer<CB_VSInput> VSInput;
		ConstantBuffer<CB_UpdatePosInput> CSInput;

		//debug and testing
		void createTestVertices();
		void setRandomColors();
};
