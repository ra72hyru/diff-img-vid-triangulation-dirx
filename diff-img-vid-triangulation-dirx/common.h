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

struct Vec6f 
{
	float grABCx;
	float grABCy;
	float grACBx;
	float grACBy;
	float grBCAx;
	float grBCAy;
};

struct Vec9f 
{
	float r_a;
	float r_b;
	float r_c;
	float g_a;
	float g_b;
	float g_c;
	float b_a;
	float b_b;
	float b_c;
};

struct Vec144f 
{
	float colors[144];
};

struct Mat4x4f 
{
	Vec4f row1;
	Vec4f row2;
	Vec4f row3;
	Vec4f row4;
};