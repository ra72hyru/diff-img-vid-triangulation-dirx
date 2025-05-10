ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
RWByteAddressBuffer colors : register(u0);
Texture2D image : register(t2);

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

float signed_triangle_area(float2 A, float2 B, float2 C)
{
    return 0.5 * (A.x * (B.y - C.y) + B.x * (C.y - A.y) + C.x * (A.y - B.y));
}

bool point_inside_triangle_(float2 p, float2 A, float2 B, float2 C)
{
    float s = 1 / (2 * signed_triangle_area(A, B, C)) * (A.y * C.x - A.x * C.y + p.x * (C.y - A.y) + p.y * (A.x - C.x));
    float t = 1 / (2 * signed_triangle_area(A, B, C)) * (A.x * B.y - A.y * B.x + p.x * (A.y - B.y) + p.y * (B.x - A.x));

    if (s >= -1E-5 && t >= -1E-5 && 1 - s - t >= -1E-5)
        return true;
    return false;
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
    const float eps = 1E-3;
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

float3 bilinear_interpolation(float3 K, float3 Kx, float3 Ky, float3 Kxy, float2 m, float2 t, float2 cd)
{
    float3 interp_1 = K * (0.5 * (m.y - m.x) * (cd.y * cd.y - cd.x * cd.x) + (t.y - t.x) * (cd.y - cd.x));
    float3 interp_2 = Kx * ((1.0 / 3.0) * (m.y - m.x) * (cd.y * cd.y * cd.y - cd.x * cd.x * cd.x) + 0.5 * (t.y - t.x) * (cd.y * cd.y - cd.x * cd.x));
    float3 interp_3 = 0.5 * Ky * ((1.0 / 3.0) * (m.y * m.y - m.x * m.x) * (cd.y * cd.y * cd.y - cd.x * cd.x * cd.x) + (m.y * t.y - m.x * t.x) * (cd.y * cd.y - cd.x * cd.x) + (t.y * t.y - t.x * t.x) * (cd.y - cd.x));
    float3 interp_4 = 0.5 * Kxy * (0.25 * (m.y * m.y - m.x * m.x) * (cd.y * cd.y * cd.y * cd.y - cd.x * cd.x * cd.x * cd.x) + (2.0 / 3.0) * (m.y * t.y - m.x * t.x) * (cd.y * cd.y * cd.y - cd.x * cd.x * cd.x) + 0.5 * (t.y * t.y - t.x * t.x) * (cd.y * cd.y - cd.x * cd.x));

    float3 interp = abs(interp_1 + interp_2 + interp_3 + interp_4);
    return interp;
}

float3 integrate(float3 K, float3 Kx, float3 Ky, float3 Kxy, in int size)
{
    //sorting
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
                    //ls.erase(ls.begin() + index);
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
                //ls.erase(ls.begin() + index);
                local_plgn[index] = local_plgn[local_size - 1];
                local_size -= 1;
                break;
            }
            index += 1;
        }
    }
    //end of sorting
    
    float3 result = float3(0, 0, 0);
    
    const float EPS = 1E-5;
    float2 A = ordered_plgn[0];
    for (int o = 0; o < ordered_size - 2; o++)
    {
        if (triangle_area(ordered_plgn[0], ordered_plgn[o + 1], ordered_plgn[o + 2]) < 0.2)
            continue;
        
        float2 C = ordered_plgn[o + 1];
        float2 B = ordered_plgn[o + 2];
        
        float2 tri_ac = C - A;
        float2 tri_ab = B - A;
        float2 tri_bc = C - B;
        
        if (abs(tri_ac.x) <= 1E-5 && abs(tri_ac.y) <= 1E-5 || abs(tri_ab.x) <= 1E-5 && abs(tri_ab.y) <= 1E-5 || abs(tri_bc.x) <= 1E-5 && abs(tri_bc.y) <= 1E-5)
            continue;
        if (abs(tri_ac.x) <= 1E-5 && abs(tri_ab.x) <= 1E-5 || abs(tri_ac.x) <= 1E-5 && abs(tri_bc.x) <= 1E-5 || abs(tri_ab.x) <= 1E-5 && abs(tri_bc.x) <= 1E-5)
            continue;
        
        if (abs(tri_ac.x) <= EPS)
        {
            float m1 = tri_bc.y / tri_bc.x;
            float t1 = B.y - m1 * B.x;
            float m2 = tri_ab.y / tri_ab.x;
            float t2 = B.y - m2 * B.x;

            float c = min(A.x, B.x);
            float d = max(A.x, B.x);
            
            result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));

        }
        else if (abs(tri_bc.x) <= EPS)
        {
            float m1 = tri_ac.y / tri_ac.x;
            float t1 = C.y - m1 * C.x;
            float m2 = tri_ab.y / tri_ab.x;
            float t2 = B.y - m2 * B.x;

            float c = min(A.x, B.x);
            float d = max(A.x, B.x);
            
            result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));
        }
        else if (abs(tri_ab.x) <= EPS)
        {
            float m1 = tri_ac.y / tri_ac.x;
            float t1 = C.y - m1 * C.x;
            float m2 = tri_bc.y / tri_bc.x;
            float t2 = B.y - m2 * B.x;

            float c = min(A.x, C.x);
            float d = max(A.x, C.x);
            
            result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));
        }
        else
        {
            if (A.x < C.x && C.x < B.x || B.x < C.x && C.x < A.x)
            {
                float m1 = tri_ac.y / tri_ac.x;
                float t1 = C.y - m1 * C.x;
                float m2 = tri_ab.y / tri_ab.x;
                float t2 = B.y - m2 * B.x;

                float c = min(A.x, C.x);
                float d = max(A.x, C.x);
                
                result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));
                
                m1 = tri_bc.y / tri_bc.x;
                t1 = C.y - m1 * C.x;
                c = min(B.x, C.x);
                d = max(B.x, C.x);
                
                result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));
            }
            else if (A.x < B.x && B.x < C.x || C.x < B.x && B.x < A.x)
            {
                float m1 = tri_ab.y / tri_ab.x;
                float t1 = B.y - m1 * B.x;
                float m2 = tri_ac.y / tri_ac.x;
                float t2 = C.y - m2 * C.x;
				
                float c = min(A.x, B.x);
                float d = max(A.x, B.x);
                
                result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));
                
                m1 = tri_bc.y / tri_bc.x;
                t1 = B.y - m1 * B.x;
                c = min(C.x, B.x);
                d = max(C.x, B.x);
                
                result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));
            }
            else if (B.x < A.x && A.x < C.x || C.x < A.x && A.x < B.x)
            {
                float m1 = tri_ac.y / tri_ac.x;
                float t1 = C.y - m1 * C.x;
                float m2 = tri_bc.y / tri_bc.x;
                float t2 = B.y - m2 * B.x;

                float c = min(A.x, C.x);
                float d = max(A.x, C.x);
                
                result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));
                
                m1 = tri_ab.y / tri_ab.x;
                t1 = C.y - m1 * C.x;
                c = min(A.x, B.x);
                d = max(A.x, B.x);
                
                result += bilinear_interpolation(K, Kx, Ky, Kxy, float2(m1, m2), float2(t1, t2), float2(c, d));
            }
        }
    }
    return result;
}
//TODO: mit anderem intersect testen, CLG_bi_interp.hlsl
[numthreads(128, 1, 1)]
void main(uint DTid : SV_DispatchThreadID)
{
    int3 dimensions;
    image.GetDimensions(0, dimensions.x, dimensions.y, dimensions.z);
    dimensions.x -= 1;
    dimensions.y -= 1;
    //float2 A = float2(0.0f, 0.0f), B = float2(0.0f, 0.0f), C = float2(0.0f, 0.0f);
    uint ind_A = indices.Load(DTid * 12);
    uint ind_B = indices.Load(DTid * 12 + 4);
    uint ind_C = indices.Load(DTid * 12 + 8);
    
    float2 A = asfloat(positions.Load2(ind_A * 8));
    float2 B = asfloat(positions.Load2(ind_B * 8));
    float2 C = asfloat(positions.Load2(ind_C * 8));

    float2 ab = B - A;
    float2 ac = C - A;
    float2 bc = B - C;
    
    float tri_area = triangle_area(A, B, C);
    
    float min_x = min(A.x, min(B.x, C.x));
    float max_x = max(A.x, max(B.x, C.x));
    
    float min_y = min(A.y, min(B.y, C.y));
    float max_y = max(A.y, max(B.y, C.y));
    
    int pixel_right_x = floor(min_x);
    int pixel_bottom_y = floor(min_y);
    int pixel_left_x = ceil(max_x);
    int pixel_top_y = ceil(max_y);
    
    float3 color = float3(0, 0, 0);
    float3 K, Kx, Ky, Kxy;
    float x1, x2, y1, y2;
    for (int i = pixel_right_x; i < pixel_left_x; i++)
    {
        for (int j = pixel_bottom_y; j < pixel_top_y; j++)
        {
            float4 col_bl = image.Load(int3(max(0, i - 1),                       max(0, j - 1), 0));
            float4 col_bm = image.Load(int3(i,                                   max(0, j - 1), 0));
            float4 col_br = image.Load(int3(min(dimensions.x, i + 1),            max(0, j - 1), 0));
            float4 col_ml = image.Load(int3(max(0, i - 1),                                   j, 0));
            float4 col_mm = image.Load(int3(i,                                               j, 0));
            float4 col_mr = image.Load(int3(min(dimensions.x, i + 1),                        j, 0));
            float4 col_tl = image.Load(int3(max(0, i - 1), min(dimensions.y,            j + 1), 0));
            float4 col_tm = image.Load(int3(i, min(dimensions.y, j + 1), 0));
            float4 col_tr = image.Load(int3(min(dimensions.x, i + 1), min(dimensions.y, j + 1), 0));
            float4 cols[9] =
            {
                col_bl, col_bm, col_br,
                col_ml, col_mm, col_mr,
                col_tl, col_tm, col_tr
            };
            for (int lr = 0; lr < 2; lr++)
            {
                for (int bu = 0; bu < 2; bu++)
                {
                    int size = 0;
            
                    K = cols[0 + bu * 3 + lr * 1].xyz * x2 * y2
                            - cols[1 + bu * 3 + lr * 1].xyz * x1 * y2
                            - cols[3 + bu * 3 + lr * 1].xyz * x2 * y1
                            + cols[4 + bu * 3 + lr * 1].xyz * x1 * y1;
                        
                    Kx = -cols[0 + bu * 3 + lr * 1].xyz * y2
                            + cols[1 + bu * 3 + lr * 1].xyz * y2
                            + cols[3 + bu * 3 + lr * 1].xyz * y1
                            - cols[4 + bu * 3 + lr * 1].xyz * y1;
                        
                    Ky = -cols[0 + bu * 3 + lr * 1].xyz * x2
                            + cols[1 + bu * 3 + lr * 1].xyz * x1
                            + cols[3 + bu * 3 + lr * 1].xyz * x2
                            - cols[4 + bu * 3 + lr * 1].xyz * x1;
                        
                    Kxy = cols[0 + bu * 3 + lr * 1].xyz
                            - cols[1 + bu * 3 + lr * 1].xyz
                            - cols[3 + bu * 3 + lr * 1].xyz
                            + cols[4 + bu * 3 + lr * 1].xyz;
                    
                    bool whole_pixel = true;
                    
                    //maybe take care at the boundary?
                    x1 = i - 1 + lr + 0.5f;
                    x2 = i + lr + 0.5f;
                    y1 = j - 1 + bu + 0.5f;
                    y2 = j + bu + 0.5f;
                    
                    float2 x1y1 = float2(i + (float) lr / 2.0f, j + (float) bu / 2.0f);
                    float2 x2y1 = float2(i + ((float) lr + 1) / 2.0f, j + (float) bu / 2.0f);
                    float2 x1y2 = float2(i + (float) lr / 2.0f, j + ((float) bu + 1) / 2.0f);
                    float2 x2y2 = float2(i + ((float) lr + 1) / 2.0f, j + ((float) bu + 1) / 2.0f);

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
                        //f(Q_11) = bl, ml, bm, mm --> 0, 3, 1, 4 --> cols[bu * 3 + lr * 1]
                        //f(Q_21) = bm, mm, br, mr --> 1, 4, 2, 5 --> cols[1 + bu * 3 + lr * 1]
                        //f(Q_12) = ml, tl, mm, tm --> 3, 6, 4, 7 --> cols[3 + bu * 3 + lr * 1]
                        //f(Q_22) = mm, tm, mr, tr --> 4, 7, 5, 8 --> cols[4 + bu * 3 + lr * 1]
                        float d1c1 = x2y1.x - x1y1.x;
                        float b1a1 = x1y2.y - x1y1.y;
                        float d2c2 = x2y1.x * x2y1.x - x1y1.x * x1y1.x;
                        float b2a2 = x1y2.y * x1y2.y - x1y1.y * x1y1.y;
                        color += K * b1a1 * d1c1 + Kx * 0.5f * d2c2 * b1a1 + Ky * 0.5f * d1c1 * b2a2 + Kxy * 0.25f * d2c2 * b2a2;
                        //color += 0.25f * float3((float) i / (float) dimensions.x, (float) j / (float) dimensions.y, (float) i * j / ((float) dimensions.x * (float) dimensions.y));
                        //tri_area += 0.25f;
                    }
                    else 
                    {
                        if (A.x >= i + (lr / 2.0) && A.x <= i + (lr + 1) / 2.0 && A.y >= j + bu / 2.0 && A.y <= j + (bu + 1) / 2.0)
                        {
                            if (!point_in_polygon(A, size))
                                append(A, size);
                        }
                        if (B.x >= i + (lr / 2.0) && B.x <= i + (lr + 1) / 2.0 && B.y >= j + bu / 2.0 && B.y <= j + (bu + 1) / 2.0)
                        {
                            if (!point_in_polygon(B, size))
                                append(B, size);
                        }
                        if (C.x >= i + (lr / 2.0) && C.x <= i + (lr + 1) / 2.0 && C.y >= j + bu / 2.0 && C.y <= j + (bu + 1) / 2.0)
                        {
                            if (!point_in_polygon(C, size))
                                append(C, size);
                        }
                
                        float2 i0;
                        float2 i1;
                        int intrsct;
                        float2 ij = float2(i + lr / 2.0, j + bu / 2.0);
                        //AB
                        {
                            intrsct = intersect_segments(ij, float2(0.5, 0), A, ab, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }

                            intrsct = intersect_segments(ij, float2(0, 0.5), A, ab, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                
                            intrsct = intersect_segments(float2(ij.x + 0.5, ij.y), float2(0, 0.5), A, ab, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                
                            intrsct = intersect_segments(float2(ij.x, ij.y + 0.5), float2(0.5, 0), A, ab, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                        }
                        //AC
                        {
                            intrsct = intersect_segments(ij, float2(0.5, 0), A, ac, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }

                            intrsct = intersect_segments(ij, float2(0, 0.5), A, ac, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                
                            intrsct = intersect_segments(float2(ij.x + 0.5, ij.y), float2(0, 0.5), A, ac, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                
                            intrsct = intersect_segments(float2(ij.x, ij.y + 0.5), float2(0.5, 0), A, ac, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                        }
                        //BC
                        {
                            intrsct = intersect_segments(ij, float2(0.5, 0), B, bc, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }

                            intrsct = intersect_segments(ij, float2(0, 0.5), B, bc, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                
                            intrsct = intersect_segments(float2(ij.x + 0.5, ij.y), float2(0, 0.5), B, bc, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                
                            intrsct = intersect_segments(float2(ij.x, ij.y + 0.5), float2(0.5, 0), B, bc, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                                if (!point_in_polygon(i1, size))
                                    append(i1, size);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0, size))
                                    append(i0, size);
                            }
                        }
                
                        if (size >= 3)
                        {
                            color += integrate(K, Kx, Ky, Kxy, size);
                        }
                    }
                }
            }
        }
    }

    color /= tri_area;
    colors.Store3(DTid * 12, asuint(color));
}