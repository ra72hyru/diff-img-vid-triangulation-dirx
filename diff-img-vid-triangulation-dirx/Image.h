#pragma once
#include "common.h"
#include <opencv2/opencv.hpp>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>
#include <D3D11.h>
#include <DXGI.h>

class Image 
{
	public:
		Image(std::string file);

		int getWidth() { return width; };
		int getHeight() { return height; };

		Vec3f at(int x, int y) { return { imageColors[y * width + x]}; };
	private:
		//cv::Mat img_opencv;
		void importOpenCV(const cv::Mat& img);

		int width;
		int height;

		std::vector<Vec3f> imageColors;
};

class ImageView 
{
	public:
		ImageView(int width, int height);
		~ImageView();

		ID3D11Texture2D* getTexture() { return pImage_Texture; };
		ID3D11ShaderResourceView* getShaderResourceView() { return pImage_View; };	

		void setImage(Image* image);

		int getWidth() { return width; };
		int getHeight() { return height; };
		Mat4x4f getProjectionMatrix() { return projMatrix; };

		bool create(ID3D11Device* device);
		void release();
	private:
		void createProjectionMatrix();

		int width;
		int height;

		std::vector<Vec4f> imageData;
		Mat4x4f projMatrix;

		ID3D11Texture2D* pImage_Texture;
		ID3D11ShaderResourceView* pImage_View;
};
