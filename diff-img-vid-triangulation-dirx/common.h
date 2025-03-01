#pragma once
#include <vector>

#ifndef SAFE_RELEASE
	#define SAFE_RELEASE(p) { if(p) { (p)->Release(); (p) = NULL;} }
#endif 

#ifndef SAFE_DELETE
	#define SAFE_DELETE(p) { if(p) { delete(p); (p) = NULL;} }
#endif 

struct Vec2f {
	float x;
	float y;
};
struct Vec3f {
	float r;
	float g;
	float b;
};

struct Vec4f 
{
	float r;
	float g;
	float b;
	float a;
};

struct Mat4x4f 
{
	Vec4f row1;
	Vec4f row2;
	Vec4f row3;
	Vec4f row4;
};