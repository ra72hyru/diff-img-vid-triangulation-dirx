ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
ByteAddressBuffer colors : register(t2);
Texture2D image : register(t3);
RWByteAddressBuffer errors : register(u0);

cbuffer params : register(b0)
{
    float stepSize;
    float dxA;
    float dxB;
    float dxC;
    float dyA;
    float dyB;
    float dyC;
}

static float2 points[7] = { float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f) };

float cross(float2 v, float2 w)
{
    return v.x * w.y - v.y * w.x;
}

int intersect_segments(float2 o1, float2 d1, float2 o2, float2 d2, out float2 i0, out float2 i1)
{
    float2 w = o1 - o2;
    float D = cross(d1, d2);

    if (abs(D) < 1E-5)
    {
        float para1 = cross(d1, w);
        float para2 = cross(d2, w);
        if (para1 != 0 || para2 != 0)
        {
            return 0;
        }

        float t0;
        float t1;

        float2 w2 = o1 + d1 - o2;
        if (d2.x != 0)
        {
            t0 = w.x / d2.x;
            t1 = w2.x / d2.x;
        }
        else
        {
            t0 = w.y / d2.y;
            t1 = w2.y / d2.y;
        }

        if (t0 > t1)
        {
            float tmp = t1;
            t1 = t0;
            t0 = tmp;
        }

        if (t0 > 1 || t1 > 1)
        {
            return 0;
        }

        t0 < 0 ? 0 : t0;
        t1 > 1 ? 1 : t1;

        if (t0 == t1)
        {
            i0 = o2 + t0 * d2;
            return 1;
        }

        i0 = o2 + t0 * d2;
        i1 = o2 + t1 * d2;
        return 2;
    }

    float sI = cross(w, d2) / -D;
    if (sI < 0 || sI > 1)
    {
        return 0;
    }

    float tI = cross(d1, w) / D;
    if (tI < 0 || tI > 1)
    {
        return 0;
    }

    i0 = o1 + sI * d1;
    return 1;
}

float triangle_area(float2 A, float2 B, float2 C)
{
    return 0.5 * abs(A.x * (B.y - C.y) + B.x * (C.y - A.y) + C.x * (A.y - B.y));
}

float2 normal_in(float2 v, float2 w)
{
    float2 n = float2(v.y, -v.x);
    n = dot(n, w) <= 0 ? -n : n;
    return n;
}

bool point_inside_triangle(float2 p, float2 A, float2 B, float2 C)
{
    float2 ab = B - A;
    float2 ac = C - A;
    float2 bc = C - B;
    
    if (dot(normal_in(ab, ac), p - A) <= 1E-5 || dot(normal_in(ac, ab), p - A) <= 1E-5 || dot(normal_in(bc, -ab), p - B) <= 1E-5)
        return false;
    return true;
}

void append(float2 p, inout int size)
{
    points[size] = p;
    size += 1;
}

bool point_in_polygon(float2 p, in int size)
{
    const float eps = 1E-5;
    for (int i = 0; i < size; i++)
    {
        float2 ppi = p - points[i];
        if (abs(ppi.x) < eps && abs(ppi.y) < eps)
            return true;
    }
    return false;
}

bool isLeft(float2 n, float2 a, float2 q)
{
    float2 aq = q - a;
    if (dot(aq, n) > 0)
    {
        return true;
    }
    return false;
}

// computes the intersection of two line segments. t contains the relative positions on the two segments.
bool intersect_segment_segment(float2 _a, float2 _b, float2 _c, float2 _d, inout float2 _t)
{
    float2 ba = _b - _a, dc = _d - _c;
    float disc = _a.x * (_d.y - _c.y) + _b.x * (_c.y - _d.y) + (_b.y - _a.y) * _d.x + (_a.y - _b.y) * _c.x;
    if (abs(disc) < 1E-10)
        return false;
    
    _t.x = (_a.x * (_d.y - _c.y) + _c.x * (_a.y - _d.y) + (_c.y - _a.y) * _d.x) / (disc != 0 ? disc : 1);
    if (_t.x < 0 || 1 < _t.x)
        return false;
    
    _t.y = -(_a.x * (_c.y - _b.y) + _b.x * (_a.y - _c.y) + (_b.y - _a.y) * _c.x) / (disc != 0 ? disc : 1);
    if (_t.y < 0 || 1 < _t.y)
        return false;
    
    _t = _a + _t.x * ba;
    return true;
}

float polygon_area(in int size)
{
    float2 ordered_plgn[7] = { float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f) };
    int ordered_size = 0;
    int local_size = size;
    float2 local_plgn[7] = { points[0], points[1], points[2], points[3], points[4], points[5], points[6] };
    
    float2 start_p = points[0];

    for (int i = 0; i < size; i++)
    {
        if (points[i].x < start_p.x)
        {
            start_p = points[i];
        }
        else if (points[i].x == start_p.x)
        {
            start_p = float2(points[i].x, min(points[i].y, start_p.y));
        }
    }
    ordered_plgn[0] = start_p;
    ordered_size += 1;
    bool leftmost_point = true;
    int index;

    while (local_size > 1)
    {
        index = 0;
        for (int j = 0; j < local_size; j++)
        {
            if (start_p.x == local_plgn[j].x && start_p.y == local_plgn[j].y)
            {
                index += 1;
                continue;
            }
            float2 ab = local_plgn[j] - start_p;
            leftmost_point = true;
            for (int k = 0; k < local_size; k++)
            {
                if (local_plgn[k].x == start_p.x && local_plgn[k].y == start_p.y)
                {
                    continue;
                }
                else if (local_size == 2)
                {
                    ordered_plgn[ordered_size] = local_plgn[j];
                    ordered_size += 1;
                    local_plgn[index] = local_plgn[local_size - 1];
                    local_size -= 1;
                    leftmost_point = false;
                    break;
                }
                else if (local_plgn[k].x == local_plgn[j].x && local_plgn[k].y == local_plgn[j].y)
                {
                    continue;
                }
                else
                {
                    if (isLeft(float2(-ab.y, ab.x), start_p, local_plgn[k]))
                    {
                        leftmost_point = false;
                        break;
                    }
                }
            }
            if (leftmost_point)
            {
                ordered_plgn[ordered_size] = local_plgn[j];
                ordered_size += 1;
                local_plgn[index] = local_plgn[local_size - 1];
                local_size -= 1;
                break;
            }
            index += 1;
        }
    }
    
    float area = 0.0f;
    for (int l = 0; l < ordered_size - 2; l++)
    {
        area += triangle_area(ordered_plgn[0], ordered_plgn[l + 1], ordered_plgn[l + 2]);
    }
    return area;
}

float3 overlap(float2 A, float2 B, float2 C, float3 tri_color)//, float2 A2, float2 B2, float2 C2, out float3 color2)
{
    float2 ab = B - A;
    float2 ac = C - A;
    float2 bc = C - B;
    //float2 ab2 = B2 - A2;
    //float2 ac2 = C2 - A2;
    //float2 bc2 = C2 - B2;
    
    float tri_area = triangle_area(A, B, C);
    //float tri_area2 = triangle_area(A2, B2, C2);
    
    float min_x = min(A.x, min(B.x, C.x));
    float max_x = max(A.x, max(B.x, C.x));
    
    float min_y = min(A.y, min(B.y, C.y));
    float max_y = max(A.y, max(B.y, C.y));
    
    /*float min_x = min(min(A.x, min(B.x, C.x)), min(A2.x, min(B2.x, C2.x)));
    float max_x = max(max(A.x, max(B.x, C.x)), max(A2.x, max(B2.x, C2.x)));
    
    float min_y = min(min(A.y, min(B.y, C.y)), min(A2.y, min(B2.y, C2.y)));
    float max_y = max(max(A.y, max(B.y, C.y)), max(A2.y, max(B2.y, C2.y)));*/
    
    int pixel_right_x = floor(min_x);
    int pixel_bottom_y = floor(min_y);
    int pixel_left_x = ceil(max_x);
    int pixel_top_y = ceil(max_y);
    
    float3 error = float3(0.0f, 0.0f, 0.0f);

    for (int i = pixel_right_x; i < pixel_left_x; i++)
    {
        for (int j = pixel_bottom_y; j < pixel_top_y; j++)
        {
            //{float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f)}
            int size = 0;
            //int size2 = 0;
            
            float area = 0.0f;
            //float area2 = 0.0f;
            bool whole_pixel = true;
            //bool whole_pixel2 = true;
            
            float2 x1y1 = float2(i, j);
            float2 x2y1 = float2(i + 1, j);
            float2 x1y2 = float2(i, j + 1);
            float2 x2y2 = float2(i + 1, j + 1);

            if (point_inside_triangle(x1y1, A, B, C))
            {
                append(x1y1, size); //polygon.push_back
            }
            else
                whole_pixel = false;
            if (point_inside_triangle(x2y1, A, B, C))
            {
                append(x2y1, size); //polygon.push_back
            }
            else
                whole_pixel = false;
            if (point_inside_triangle(x1y2, A, B, C))
            {
                append(x1y2, size); //polygon.push_back
            }
            else
                whole_pixel = false;
            if (point_inside_triangle(x2y2, A, B, C))
            {
                append(x2y2, size); //polygon.push_back
            }
            else
                whole_pixel = false;
            
            if (whole_pixel)
            {
                area = 1.0f;
            }
            else
            {
                if (A.x >= i && A.x <= i + 1 && A.y >= j && A.y <= j + 1)
                {
                    if (!point_in_polygon(A, size))
                        append(A, size);
                }
                if (B.x >= i && B.x <= i + 1 && B.y >= j && B.y <= j + 1)
                {
                    if (!point_in_polygon(B, size))
                        append(B, size);
                }
                if (C.x >= i && C.x <= i + 1 && C.y >= j && C.y <= j + 1)
                {
                    if (!point_in_polygon(C, size))
                        append(C, size);
                }
                
                float2 i0;
                float2 i1;
                int intrsct;
                //AB
                //{
                    //intrsct = intersect_segments(float2(i, j), float2(1, 0), A, ab, i0, i1);
                intrsct = intersect_segment_segment(float2(i, j), float2(i + 1, j), A, B, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i, j), float2(i, j + 1), A, B, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i + 1, j), float2(i + 1, j + 1), A, B, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i, j + 1), float2(i + 1, j + 1), A, B, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                    
                intrsct = intersect_segment_segment(float2(i, j), float2(i + 1, j), A, C, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i, j), float2(i, j + 1), A, C, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i + 1, j), float2(i + 1, j + 1), A, C, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i, j + 1), float2(i + 1, j + 1), A, C, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                    
                intrsct = intersect_segment_segment(float2(i, j), float2(i + 1, j), B, C, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i, j), float2(i, j + 1), B, C, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i + 1, j), float2(i + 1, j + 1), B, C, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }
                    
                intrsct = intersect_segment_segment(float2(i, j + 1), float2(i + 1, j + 1), B, C, i0);
                if (intrsct)
                {
                    if (!point_in_polygon(i0, size))
                        append(i0, size);
                }

                if (size == 3)
                {
                    area = triangle_area(points[0], points[1], points[2]);
                }
                else if (size >= 4)
                {
                    area = polygon_area(size);
                }
            }
            float fraction = area / tri_area;
            //float fraction2 = area2 / tri_area2;
           
            float3 pixel_color = image.Load(int3(i, j, 0));
            //error += fraction * pow(abs(pixel_color - tri_color), 2);
            //float3 e = (pixel_color - tri_color) * 255;
            float3 e = float3(pixel_color.x * 255 - tri_color.x * 255, pixel_color.y * 255 - tri_color.y * 255, pixel_color.z * 255 - tri_color.z * 255);
            //error += dot(e, e) * area;
            error += float3(e.x * e.x, e.y * e.y, e.z * e.z) * area;
            //color2 += fraction2 * pixel_color;
        }
    }
    return error;
}

[numthreads(64, 1, 1)]
void main(uint DTid : SV_DispatchThreadID)
{
    uint3 inds = indices.Load3(DTid * 12);
    
    float2 A = asfloat(positions.Load2(inds.x * 8));
    float2 B = asfloat(positions.Load2(inds.y * 8));
    float2 C = asfloat(positions.Load2(inds.z * 8));

    //only one of dxA, dyA, dxB, dyB, dxC and dyC is 1, the rest is 0
    //0-11 dxA pl, 12-23 dxA mi, 24-35 dyA pl, 36-47 dyA mi, etc.
    uint address = 24 * dyA + 48 * dxB + 72 * dyB + 96 * dxC + 120 * dyC;
    address = stepSize < 0 ? address + 12 : address;
    
    float3 tri_color = asfloat(colors.Load3(DTid * 144 + address));
    float3 error = overlap(A + stepSize * float2(dxA, dyA), B + stepSize * float2(dxB, dyB), C + stepSize * float2(dxC, dyC), tri_color);
    
    errors.Store3(DTid * 144 + address, asuint(error));
}