ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
ByteAddressBuffer colors : register(t2);
Texture2D image : register(t3);
RWByteAddressBuffer errors : register(u0);

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
    
    if (dot(normal_in(ab, ac), p - A) <= 0 || dot(normal_in(ac, ab), p - A) <= 0 || dot(normal_in(bc, -ab), p - B) <= 0)
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

[numthreads(64, 1, 1)]
void main(uint DTid : SV_DispatchThreadID)
{
    uint ind_A = indices.Load(DTid * 12);
    uint ind_B = indices.Load(DTid * 12 + 4);
    uint ind_C = indices.Load(DTid * 12 + 8);
    
    float2 A = asfloat(positions.Load2(ind_A * 8));
    float2 B = asfloat(positions.Load2(ind_B * 8));
    float2 C = asfloat(positions.Load2(ind_C * 8));

    float2 ab = B - A;
    float2 ac = C - A;
    float2 bc = C - B;
    
    float tri_area = triangle_area(A, B, C);
    
    float min_x = min(A.x, min(B.x, C.x));
    float max_x = max(A.x, max(B.x, C.x));
    
    float min_y = min(A.y, min(B.y, C.y));
    float max_y = max(A.y, max(B.y, C.y));
    
    int pixel_right_x = floor(min_x);
    int pixel_bottom_y = floor(min_y);
    int pixel_left_x = ceil(max_x);
    int pixel_top_y = ceil(max_y);
    
    //float3 color = float3(0.0f, 0.0f, 0.0f);
    float error = 0;
    for (int i = pixel_right_x; i < pixel_left_x; i++)
    {
        for (int j = pixel_bottom_y; j < pixel_top_y; j++)
        {
            int size = 0;
            
            float area = 0.0f;
            bool whole_pixel = true;
            
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
                int intrsct;
                
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
           
            float3 pixel_color = image.Load(int3(i, j, 0));
            float3 tri_color = asfloat(colors.Load3(DTid * 12));
            float3 error3 = fraction * pow(abs(pixel_color - tri_color), 2);
            error += (error3.x + error3.y + error3.z) / 3.0;
        }
    }

    errors.Store(DTid * 4, asuint(error));
}