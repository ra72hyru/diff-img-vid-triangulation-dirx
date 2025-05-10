#pragma once

#include <fstream>
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
	float trustRegion;
	float damping;
};

struct CB_FiniteDiffInput 
{
	float eps;
	float dxA;
	float dxB;
	float dxC;
	float dyA;
	float dyB;
	float dyC;
};

struct CB_Num
{
	int num;
};

struct sort_pred 
{
	bool operator()(const std::pair<int, float>& left, const std::pair<int, float>& right) 
	{
		return right.second < left.second;
	}
};

class Triangulator 
{
	public:
		Triangulator(ImageView* image, D3D* pD3D, int numTriangles, std::string file);
		~Triangulator();

		bool create(ID3D11Device* device);
		void release();

		void draw(ID3D11DeviceContext* immediateContext, RenderMode mode);
		void draw_fin_diff(ID3D11DeviceContext* immediateContext, RenderMode mode);
		void drawV2(ID3D11DeviceContext* immediateContext, RenderMode mode);
	private:
		void render(ID3D11DeviceContext* immediateContext, RenderMode mode);
		void computeConstantColors(ID3D11DeviceContext* immediateContext);
		void computeLinearGradients(ID3D11DeviceContext* immediateContext);
		void ccc_bi_interp(ID3D11DeviceContext* immediateContext);
		void clg_bi_interp(ID3D11DeviceContext* immediateContext);
		void computeGradients_rtt(ID3D11DeviceContext* immediateContext);
		void computeGradients_cplg(ID3D11DeviceContext* immediateContext);
		void finite_differences(float plmi, ID3D11DeviceContext* immediateContext);
		void computeErrors_fin_diff(float plmi, ID3D11DeviceContext* immediateContext);
		void updatePositions(ID3D11DeviceContext* immediateContext);
		void updatePositions_fin_diff(ID3D11DeviceContext* immediateContext);
		void computeErrors(ID3D11DeviceContext* immediateContext);
		void computePixelVariance(ID3D11DeviceContext* immediateContext);
		void computeImageErrorCS(ID3D11DeviceContext* immediateContext);

		void delaunay(ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		void delaunay_error_conscious(ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		bool eliminate_degenerate_triangles(ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		int insertion(ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		int insertion2(ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		int insertionV3(ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		float computeImageErrorPS(ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		float getTotalError(ID3D11Device* device, ID3D11DeviceContext* immediateContext);

		void print_areas(ID3D11DeviceContext* immediateContext);
		float compute_standard_deviation(ID3D11DeviceContext* immediateContext);
		float compute_standard_deviation2(ID3D11DeviceContext* immediateContext);

		void insert_vertex_center(unsigned int tri_index, ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		void insert_triangle_into_triangle(unsigned int tri_index, std::vector<bool>& marked, ID3D11Device* device, ID3D11DeviceContext* immediateContext);

		void updateDataOnGPU(ID3D11Device* device, ID3D11DeviceContext* immediateContext);
		void createRegularGrid();
		void buildNeighbors(bool buildBuffers);
		void buildNeighborBuffers();
		void buildEdges();
		void initializeTriangleGradients();

		int get_edge_index(unsigned int v1, unsigned int v2);
		int get_edge_index_by_tris(unsigned int t, unsigned int n);
		std::vector<int> get_edges_with_triangle(unsigned int t);
		std::vector<int> get_edges_with_vertex(unsigned int v);

		void writeErrorToFile(std::string file, int iteration, float error);

		float dot(const Vec2f& v, const Vec2f& w);
		Vec2f normal_in(const Vec2f& v, const Vec2f& w);
		bool point_inside_triangle(const Vec2f& p, const Vec2f& A, const Vec2f& B, const Vec2f& C);
		Vec3f tri_overlap_color(const Vec2f& A, const Vec2f& B, const Vec2f& C);
		float computeErrorCPU(const Vec2f& A, const Vec2f& B, const Vec2f& C, const Vec3f& color);

		ImageView* image;

		std::string filename;

		int nTriangles;
		int triangleGoal;

		int delaunayEveryNthIteration;
		int delaunayUntilNthIteration;

		bool computeErrorInPS;

		D3D* d3d;

		SharedByteAddressBuffer<Vec2f> positions;							//triangle vertices
		SharedByteAddressBuffer<unsigned int> indices;						//triangle list
		std::vector<bool> is_on_border;										//same size as vertex list; true if vertex is on the edge of the image
		SharedByteAddressBuffer<Vec3f> colors;								//constant triangle color (RGB-values)
		SharedByteAddressBuffer<Vec9f> gradientCoefficients;				//linear color gradient coefficients
		SharedByteAddressBuffer<unsigned int> neighbor_list;				//list of neighboring triangles for each vertex
		SharedByteAddressBuffer<unsigned int> indices_in_neighbor_list;		//index for each vertex, where in the list its neighbors start
		SharedByteAddressBuffer<unsigned int> neighbor_count;				//count of neighboring triangles for each vertex
		SharedByteAddressBuffer<Vec6f> gradients_rtt;						//gradients for each triangle, computed using Reynolds transport theorem
		SharedByteAddressBuffer<Vec36f> colors_fin_diff;
		SharedByteAddressBuffer<Vec36f> errors_fin_diff;
		SharedByteAddressBuffer<float> errors;								//error between image and triangle for each triangle 
		SharedByteAddressBuffer<Vec4u> errorsPS;								//error between image and triangle for each triangle, computed pixel-wise in the pixelshader
		SharedByteAddressBuffer<Vec4u> errorCS;								//error between original image and triangulated image
		
		SharedByteAddressBuffer<Vec3f> pixel_variance;						//pixel variance of pixels in a triangle 

		std::vector<std::list<unsigned int> > neighbors;														//neighbors on CPU-side for (hopefully) faster delaunay
		std::vector<std::tuple<unsigned int, unsigned int, unsigned int, unsigned int> > edges;					//edges that have two adjacent triangles

		ID3D11InputLayout* pInputLayout;

		ID3D11RasterizerState* pRSState;

		ID3D11VertexShader* pVertexShader;
		ID3D11PixelShader* pPixelShader;
		ID3D11PixelShader* pPSWithError;
		ID3D11PixelShader* pPSLinearGradients;
		ID3D11PixelShader* pPSLinGradWithError;

		ID3D11ComputeShader* pComputeConstantColor;
		ID3D11ComputeShader* pComputeLinearGradients;
		ID3D11ComputeShader* pCCC_bi_interp;
		ID3D11ComputeShader* pCLG_bi_interp;
		ID3D11ComputeShader* pComputeGradients_rtt;
		ID3D11ComputeShader* pComputeGradients_cplg;
		ID3D11ComputeShader* pFiniteDifferences;
		ID3D11ComputeShader* pComputeErrors_fin_diff;
		ID3D11ComputeShader* pUpdatePositions_cc;
		ID3D11ComputeShader* pUpdatePositions_fin_diff;
		ID3D11ComputeShader* pComputeErrors;
		ID3D11ComputeShader* pComputePixelVariance;
		ID3D11ComputeShader* pComputeImageError;

		ConstantBuffer<CB_VSInput> VSInput;
		ConstantBuffer<CB_UpdatePosInput> CSInput;
		ConstantBuffer<CB_FiniteDiffInput> CSfin_diff_Input;
		ConstantBuffer<CB_Num> CSNum;

		//debug and testing
		void createTestVertices();
		void setRandomColors();
		void testing(ID3D11DeviceContext* immediateContext);

		Vec2f m_normalized(const Vec2f& v)
		{
			float length = sqrt(v.x * v.x + v.y * v.y);
			return { v.x / length, v.y / length };
		};

		float m_dot(const Vec2f& v, const Vec2f& w)
		{
			return v.x * w.x + v.y * w.y;
		};

		float tri_area(const Vec2f& A, const Vec2f& B, const Vec2f& C)
		{
			return 0.5f * abs(A.x * (B.y - C.y) + B.x * (C.y - A.y) + C.x * (A.y - B.y));
		};

		float length(const Vec2f& a, const Vec2f& b) 
		{
			return sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2));
		};
};
