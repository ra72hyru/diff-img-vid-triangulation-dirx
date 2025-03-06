ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
RWByteAddressBuffer colors : register(u0);
Texture2D image : register(t2);

static float2 points[7] = { float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f) };
static uint size;

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

bool point_inside_triangle(float2 p, float2 A, float2 B, float2 C)
{
    float s = 1 / (2 * signed_triangle_area(A, B, C)) * (A.y * C.x - A.x * C.y + p.x * (C.y - A.y) + p.y * (A.x - C.x));
    float t = 1 / (2 * signed_triangle_area(A, B, C)) * (A.x * B.y - A.y * B.x + p.x * (A.y - B.y) + p.y * (B.x - A.x));

    if (s >= 0 && t >= 0 && 1 - s - t >= 0)
        return true;
    return false;
}

void append(float2 p)
{
    points[size] = p;
    size += 1;
}

bool point_in_polygon(float2 p)
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

float polygon_area()
{
    float2 mean = float2(0.0f, 0.0f);
    
    for (int i = 0; i < size; i++)
    {
        mean += points[i];
    }
    mean /= size;
    
    for (int j = 0; j < size; j++)
    {
        for (int k = 0; k < size - j; k++)
        {
            float2 pk_m = points[k] - mean;
            float2 pk1_m = points[k + 1] - mean;
            if (pk_m.x < pk1_m.x)
            {
                float2 temp = points[k];
                points[k] = points[k + 1];
                points[k + 1] = temp;
            }
            else if (abs(pk_m.x - pk1_m.x) < 1E-5)
            {
                if (sqrt(pk_m.x * pk_m.x + pk_m.y * pk_m.y) < sqrt(pk1_m.x * pk1_m.x + pk1_m.y * pk1_m.y))
                {
                    float2 temp = points[k];
                    points[k] = points[k + 1];
                    points[k + 1] = temp;
                }

            }
        }
    }
    
    float area = 0.0f;
    for (int l = 0; l < size - 2; l++)
    {
        area += triangle_area(points[0], points[l + 1], points[l + 2]);
    }
    
    return area;
}

[numthreads(256, 1, 1)]
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
    
    float3 color = float3(0.f, 0.0f, 0.0f);
    float K, Kx, Ky, Kxy, x1, x2, y1, y2;
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
                    size = 0;
            
                    
                    float area = 0;
                    bool whole_pixel = true;
                    
                    //maybe take care at the boundary?
                    x1 = i - 1 + lr + 0.5f;
                    
                    float2 x1y1 = float2(i + (float) lr / 2.0f, j + (float) bu / 2.0f);
                    float2 x2y1 = float2(i + ((float) lr + 1) / 2.0f, j + (float) bu / 2.0f);
                    float2 x1y2 = float2(i + (float) lr / 2.0f, j + ((float) bu + 1) / 2.0f);
                    float2 x2y2 = float2(i + ((float) lr + 1) / 2.0f, j + ((float) bu + 1) / 2.0f);

                    if (point_inside_triangle(x1y1, A, B, C))
                    {
                        if (!point_in_polygon(x1y1))
                            append(x1y1); //polygon.push_back
                    }
                    else
                        whole_pixel = false;
                    if (point_inside_triangle(x2y1, A, B, C))
                    {
                        if (!point_in_polygon(x2y1))
                            append(x2y1); //polygon.push_back
                    }
                    else
                        whole_pixel = false;
                    if (point_inside_triangle(x1y2, A, B, C))
                    {
                        if (!point_in_polygon(x1y2))
                            append(x1y2); //polygon.push_back
                    }
                    else
                        whole_pixel = false;
                    if (point_inside_triangle(x2y2, A, B, C))
                    {
                        if (!point_in_polygon(x2y2))
                            append(x2y2); //polygon.push_back
                    }
                    else
                        whole_pixel = false;
            
                    if (whole_pixel)
                    {
                        area = 1.0f;
                        
                        //f(Q_11) = bl, ml, bm, mm --> 0, 3, 1, 4 --> cols[bu * 3 + lr * 1]
                        //f(Q_21) = bm, mm, br, mr --> 1, 4, 2, 5 --> cols[1 + bu * 3 + lr * 1]
                        //f(Q_12) = ml, tl, mm, tm --> 3, 6, 4, 7 --> cols[3 + bu * 3 + lr * 1]
                        //f(Q_22) = mm, tm, mr, tr --> 4, 7, 5, 8 --> cols[4 + bu * 3 + lr * 1]
                        K = cols[0 + bu * 3 + lr * 1] * (x2y2.x + 0.5f) * (x2y2.y + 0.5f) 
                            - cols[1 + bu * 3 + lr * 1] * (x1y2.x + 0.5f) * (x1y2.y + 0.5f)
                            - cols[3 + bu * 3 + lr * 1] * (x2y1.x + 0.5f) * (x2y1.y + 0.5f)
                            + cols[4 + bu * 3 + lr * 1] * (x1y1.x + 0.5f) * (x1y1.y + 0.5f);
                        
                        Kx = cols[0 + bu * 3 + lr * 1] * (x2y2.x + 0.5f) * (x2y2.y + 0.5f)
                            - cols[1 + bu * 3 + lr * 1] * (x1y2.x + 0.5f) * (x1y2.y + 0.5f)
                            - cols[3 + bu * 3 + lr * 1] * (x2y1.x + 0.5f) * (x2y1.y + 0.5f)
                            + cols[4 + bu * 3 + lr * 1] * (x1y1.x + 0.5f) * (x1y1.y + 0.5f);
                        
                        Ky = cols[0 + bu * 3 + lr * 1] * (x2y2.x + 0.5f) * (x2y2.y + 0.5f)
                            - cols[1 + bu * 3 + lr * 1] * (x1y2.x + 0.5f) * (x1y2.y + 0.5f)
                            - cols[3 + bu * 3 + lr * 1] * (x2y1.x + 0.5f) * (x2y1.y + 0.5f)
                            + cols[4 + bu * 3 + lr * 1] * (x1y1.x + 0.5f) * (x1y1.y + 0.5f);
                        
                        Kxy = cols[0 + bu * 3 + lr * 1] * (x2y2.x + 0.5f) * (x2y2.y + 0.5f)
                            - cols[1 + bu * 3 + lr * 1] * (x1y2.x + 0.5f) * (x1y2.y + 0.5f)
                            - cols[3 + bu * 3 + lr * 1] * (x2y1.x + 0.5f) * (x2y1.y + 0.5f)
                            + cols[4 + bu * 3 + lr * 1] * (x1y1.x + 0.5f) * (x1y1.y + 0.5f);

                    }
                    else
                    {
                        if (A.x >= i && A.x <= i + 1 && A.y >= j && A.y <= j + 1)
                        {
                            if (!point_in_polygon(A))
                                append(A);
                        }
                        if (B.x >= i && B.x <= i + 1 && B.y >= j && B.y <= j + 1)
                        {
                            if (!point_in_polygon(B))
                                append(B);
                        }
                        if (C.x >= i && C.x <= i + 1 && C.y >= j && C.y <= j + 1)
                        {
                            if (!point_in_polygon(C))
                                append(C);
                        }
                
                        float2 i0;
                        float2 i1;
                        int intrsct;
                        //AB
                        {
                            intrsct = intersect_segments(float2(i, j), float2(1, 0), A, ab, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }

                            intrsct = intersect_segments(float2(i, j), float2(0, 1), A, ab, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                
                            intrsct = intersect_segments(float2(i + 1, j), float2(0, 1), A, ab, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                
                            intrsct = intersect_segments(float2(i, j + 1), float2(1, 0), A, ab, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                        }
                        //AC
                        {
                            intrsct = intersect_segments(float2(i, j), float2(1, 0), A, ac, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }

                            intrsct = intersect_segments(float2(i, j), float2(0, 1), A, ac, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                
                            intrsct = intersect_segments(float2(i + 1, j), float2(0, 1), A, ac, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                
                            intrsct = intersect_segments(float2(i, j + 1), float2(1, 0), A, ac, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                        }
                        //BC
                        {
                            intrsct = intersect_segments(float2(i, j), float2(1, 0), B, bc, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }

                            intrsct = intersect_segments(float2(i, j), float2(0, 1), B, bc, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                
                            intrsct = intersect_segments(float2(i + 1, j), float2(0, 1), B, bc, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                
                            intrsct = intersect_segments(float2(i, j + 1), float2(1, 0), B, bc, i0, i1);
                            if (intrsct == 2)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                                if (!point_in_polygon(i1))
                                    append(i1);
                            }
                            else if (intrsct == 1)
                            {
                                if (!point_in_polygon(i0))
                                    append(i0);
                            }
                        }
                
                        if (size >= 4)
                        {
                            area = polygon_area();
                        }
                        else if (size == 3)
                        {
                            area = triangle_area(points[0], points[1], points[2]);
                        }
                    }
                    
                    float fraction = area / tri_area;
                    float3 pixel_color = image.Load(int3(i, j, 0));
                    color += fraction * pixel_color;
                }
            }
        }
    }

    colors.Store3(DTid * 12, asuint(color));
}