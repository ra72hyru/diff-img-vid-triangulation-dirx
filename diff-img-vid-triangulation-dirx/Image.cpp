#include "Image.h"

Image::Image(std::string file)
{
	cv::Mat img = cv::imread(file, cv::IMREAD_COLOR);
	width = img.cols;
	height = img.rows;

	imageColors.resize(width * height);
	importOpenCV(img);
}

void Image::importOpenCV(const cv::Mat& img)
{
	for (int j = 0; j < height; j++)
	{
		for (int i = 0; i < width; i++)
		{
			imageColors[j * width + i] = { (float)img.at<cv::Vec3b>(j, i)[2] / 255, (float)img.at<cv::Vec3b>(j, i)[1] / 255, (float)img.at<cv::Vec3b>(j, i)[0] / 255 };
		}
	}
}


////////////////////////////////////////
//ImageView
////////////////////////////////////////


ImageView::ImageView(int width, int height) : width(width), height(height), pImage_Texture(NULL), pImage_View(NULL)
{
	imageData.resize(width * height);
	createProjectionMatrix();
}

ImageView::~ImageView()
{
	release();
}

void ImageView::setImage(Image* image)
{
	if (width != image->getWidth() || height != image->getHeight()) return;

	for (int j = 0; j < height; j++) 
	{
		for (int i = 0; i < width; i++) 
		{
			Vec3f rgb = image->at(i, j);
			imageData[j * width + i] = { rgb.r, rgb.g, rgb.b, 1.0f };
		}
	}
}

bool ImageView::create(ID3D11Device* device)
{
	D3D11_TEXTURE2D_DESC tex_desc;
	ZeroMemory(&tex_desc, sizeof(D3D11_TEXTURE2D_DESC));
	tex_desc.Width = width;
	tex_desc.Height = height;
	tex_desc.MipLevels = 1;
	tex_desc.ArraySize = 1;
	tex_desc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
	tex_desc.SampleDesc.Count = 1;
	tex_desc.SampleDesc.Quality = 0;
	tex_desc.Usage = D3D11_USAGE_DYNAMIC;
	tex_desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	tex_desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
	tex_desc.MiscFlags = 0;
	//TODO: projection matrix, order_polygon, compute shader ausführen

	D3D11_SUBRESOURCE_DATA initData;
	ZeroMemory(&initData, sizeof(D3D11_SUBRESOURCE_DATA));
	initData.pSysMem = imageData.data();
	initData.SysMemPitch = sizeof(Vec4f) * width;

	HRESULT hr;
	hr = device->CreateTexture2D(&tex_desc, &initData, &pImage_Texture);
	if (FAILED(hr)) return false;

	hr = device->CreateShaderResourceView(pImage_Texture, NULL, &pImage_View);
	if (FAILED(hr)) return false;

	return true;
}

void ImageView::release()
{
	SAFE_RELEASE(pImage_View);
	SAFE_RELEASE(pImage_Texture);
}

void ImageView::createProjectionMatrix()
{
	Vec4f row1 = {2.0f / width, 0.0f, 0.0f, -1.0f};
	Vec4f row2 = { 0.0f, -2.0f/height, 0.0f, 1.0f };
	Vec4f row3 = { 0.0f, 0.0f, 0.0f, 0.0f };
	Vec4f row4 = { 0.0f, 0.0f, 0.0f, 1.0f };
	projMatrix = { row1, row2, row3, row4 };
}
