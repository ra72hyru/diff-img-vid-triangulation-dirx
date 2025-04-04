ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
Texture2D image : register(t2);
RWByteAddressBuffer coefficients : register(u0);

static float2 points[7] = { float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f), float2(-1.0f, -1.0f) };

float cross(float2 v, float2 w)
{
    return v.x * w.y - v.y * w.x;
}

int intersect_segments(float2 o1, float2 d1, float2 o2, float2 d2, out float2 i0, out float2 i1)
{
    float2 w = o1 - o2;
    float D = cross(d1, d2);
    
    if (abs(D) < 1E-8)
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

        t0 = t0 < 0 ? 0 : t0;
        t1 = t1 > 1 ? 1 : t1;

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
    float s = 1.0 / (2.0 * signed_triangle_area(A, B, C)) * (A.y * C.x - A.x * C.y + p.x * (C.y - A.y) + p.y * (A.x - C.x));
    float t = 1.0 / (2.0 * signed_triangle_area(A, B, C)) * (A.x * B.y - A.y * B.x + p.x * (A.y - B.y) + p.y * (B.x - A.x));

    if (s >= -1E-5 && t >= -1E-5 && 1 - s - t >= -1E-5)
        return true;
    return false;
}

bool point_inside_triangle_(float2 p, float2 A, float2 B, float2 C)
{
    float2 ab = B - A;
    float2 bc = C - B;
    float2 ca = A - C;
    
    float2 ap = p - A;
    float2 bp = p - B;
    float2 cp = p - C;
    
    float a = ab.x * ap.y - ab.y * ap.x;
    float b = bc.x * bp.y - bc.y * bp.x;
    float c = ca.x * cp.y - ca.y * cp.x;
    
    if (a < 0 && b < 0 && c < 0)
        return true;
    if (a > 0 && b > 0 && c > 0)
        return true;
    if (a == 0 && b * c >= 0)
        return true;
    if (b == 0 && a * c >= 0)
        return true;
    if (c == 0 && a * b >= 0)
        return true;
    return false;
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

void integrate_over_polygon(inout float3 r1, inout float3 r2, in int size)
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
    
    r1 = float3(0, 0, 0);
    r2 = float3(0, 0, 0);
    const float EPS = 1E-5;
    float2 A = ordered_plgn[0];
    for (int o = 0; o < ordered_size - 2; o++)
    {
        //float m1 = 0, t1 = 0, m2 = 0, t2 = 0, m12 = 0, m22 = 0, t12 = 0, t22 = 0, c = 0, d = 0, c2 = 0, d2 = 0, dc = 0, d2c2 = 0, d3c3 = 0, d4c4 = 0, m2m1 = 0, t2t1 = 0, t22t12 = 0, m22m12 = 0, m23m13 = 0, m2t2m1t1 = 0, m22t2m12t1 = 0, m2t22m1t12 = 0;
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
            
            float d3 = d * d * d;
            float c3 = c * c * c;

            r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
            r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
            r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
            r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
            r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
            r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
        }
        else if (abs(tri_bc.x) <= EPS)
        {
            float m1 = tri_ac.y / tri_ac.x;
            float t1 = C.y - m1 * C.x;
            float m2 = tri_ab.y / tri_ab.x;
            float t2 = B.y - m2 * B.x;

            float c = min(A.x, B.x);
            float d = max(A.x, B.x);
            
            float d3 = d * d * d;
            float c3 = c * c * c;
        
            r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
            r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
            r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
            r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
            r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
            r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
        }
        else if (abs(tri_ab.x) <= EPS)
        {
            float m1 = tri_ac.y / tri_ac.x;
            float t1 = C.y - m1 * C.x;
            float m2 = tri_bc.y / tri_bc.x;
            float t2 = B.y - m2 * B.x;

            float c = min(A.x, C.x);
            float d = max(A.x, C.x);
            
            float d3 = d * d * d;
            float c3 = c * c * c;
        
            r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
            r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
            r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
            r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
            r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
            r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
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
                
                float d3 = d * d * d;
                float c3 = c * c * c;
        
                r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
                r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
                r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
                r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
                r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
                r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
                
                m1 = tri_bc.y / tri_bc.x;
                t1 = C.y - m1 * C.x;
                c = min(B.x, C.x);
                d = max(B.x, C.x);
                
                d3 = d * d * d;
                c3 = c * c * c;
        
                r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
                r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
                r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
                r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
                r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
                r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
            }
            else if (A.x < B.x && B.x < C.x || C.x < B.x && B.x < A.x)
            {
                float m1 = tri_ab.y / tri_ab.x;
                float t1 = B.y - m1 * B.x;
                float m2 = tri_ac.y / tri_ac.x;
                float t2 = C.y - m2 * C.x;
				
                float c = min(A.x, B.x);
                float d = max(A.x, B.x);
                
                float d3 = d * d * d;
                float c3 = c * c * c;
        
                r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
                r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
                r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
                r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
                r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
                r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
                
                m1 = tri_bc.y / tri_bc.x;
                t1 = B.y - m1 * B.x;
                c = min(C.x, B.x);
                d = max(C.x, B.x);
                
                d3 = d * d * d;
                c3 = c * c * c;
        
                r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
                r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
                r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
                r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
                r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
                r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
            }
            else if (B.x < A.x && A.x < C.x || C.x < A.x && A.x < B.x)
            {
                float m1 = tri_ac.y / tri_ac.x;
                float t1 = C.y - m1 * C.x;
                float m2 = tri_bc.y / tri_bc.x;
                float t2 = B.y - m2 * B.x;

                float c = min(A.x, C.x);
                float d = max(A.x, C.x);
                
                float d3 = d * d * d;
                float c3 = c * c * c;
        
                r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
                r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
                r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
                r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
                r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
                r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
                
                m1 = tri_ab.y / tri_ab.x;
                t1 = C.y - m1 * C.x;
                c = min(A.x, B.x);
                d = max(A.x, B.x);
                
                d3 = d * d * d;
                c3 = c * c * c;
        
                r1.x += abs(0.25 * (m2 - m1) * (d * d3 - c * c3) + 1.0 / 3.0 * (t2 - t1) * (d3 - c3));
                r1.y += abs(1.0 / 3.0 * (0.25 * (m2 * m2 * m2 - m1 * m1 * m1) * (d * d3 - c * c3) + (m2 * m2 * t2 - m1 * m1 * t1) * (d3 - c3) + 1.5 * (m2 * t2 * t2 - m1 * t1 * t1) * (d * d - c * c) + (d - c) * (t2 * t2 * t2 - t1 * t1 * t1)));
                r1.z += abs(1.0 / 3.0 * (m2 - m1) * (d3 - c3) + 0.5 * (t2 - t1) * (d * d - c * c));
                r2.x += abs(0.5 * (1.0 / 3.0 * (m2 * m2 - m1 * m1) * (d3 - c3) + (m2 * t2 - m1 * t1) * (d * d - c * c) + (t2 * t2 - t1 * t1) * (d - c)));
                r2.y += abs(0.5 * (0.25 * (m2 * m2 - m1 * m1) * (d * d3 - c * c3) + 2.0 / 3.0 * (m2 * t2 - m1 * t1) * (d3 - c3) + 0.5 * (t2 * t2 - t1 * t1) * (d * d - c * c)));
                r2.z += abs(0.5 * (m2 - m1) * (d * d - c * c) + (t2 - t1) * (d - c));
            }
        }
    }
}

float3x3 cholesky(float3x3 A)
{
    float M[9] =
    {
        A._m00, A._m01, A._m02,
		A._m10, A._m11, A._m12,
		A._m20, A._m21, A._m22
    };

    float L[9] = { 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    for (int i = 0; i < 3; i++)
    {
        for (int j = 0; j < (i + 1); j++)
        {
            float s = 0;
            for (int k = 0; k < j; k++)
                s += L[i * 3 + k] * L[j * 3 + k];
            L[i * 3 + j] = (i == j) ?
				sqrt(M[i * 3 + i] - s) :
				(1.0 / L[j * 3 + j] * (M[i * 3 + j] - s));
        }
    }
    return float3x3(L[0], L[1], L[2],
		L[3], L[4], L[5],
		L[6], L[7], L[8]);
}

float3 cholesky_solve(float3x3 mL, float3 b)
{
    float3 y = float3(b.x / mL._m00,
		b.y / mL._m11 - (b.x * mL._m10) / (mL._m00 * mL._m11),
		(b.x * mL._m10 * mL._m21) / (mL._m00 * mL._m11 * mL._m22) - (b.y * mL._m21) / (mL._m11 * mL._m22) - (b.x * mL._m20) / (mL._m00 * mL._m22) + b.z / mL._m22);
    float3 x = float3(
		(mL._m10 * mL._m21 * y.z) / (mL._m00 * mL._m11 * mL._m22) - (mL._m20 * y.z) / (mL._m00 * mL._m22) - (mL._m10 * y.y) / (mL._m00 * mL._m11) + y.x / mL._m00,
		y.y / mL._m11 - (mL._m21 * y.z) / (mL._m11 * mL._m22),
		y.z / mL._m22);
    return x;
}

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

[numthreads(128, 1, 1)]
void main(uint DTid : SV_DispatchThreadID)
{
    if (DTid > 647)
        return;
    //float2 A = float2(0.0f, 0.0f), B = float2(0.0f, 0.0f), C = float2(0.0f, 0.0f);
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
    
    float3 color = float3(0, 0, 0);
    
    float x2 = 0.0, y2 = 0.0, x = 0.0, y = 0.0, xy = 0.0, n = 0.0;
    float3 xI = float3(0.0, 0.0, 0.0);
    float3 yI = float3(0.0, 0.0, 0.0);
    float3 I = float3(0.0, 0.0, 0.0);
    
    float3 r123 = float3(0, 0, 0), r456 = float3(0, 0, 0);
    
    for (int i = pixel_right_x; i < pixel_left_x; i++)
    {
        for (int j = pixel_bottom_y; j < pixel_top_y; j++)
        {
            float3 pixel_color = image.Load(int3(i, j, 0));
            //{float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f)}
            int size = 0;
            
            float area = 0;
            bool whole_pixel = true;
            
            float2 x1y1 = float2(i, j);
            float2 x2y1 = float2(i + 1, j);
            float2 x1y2 = float2(i, j + 1);
            float2 x2y2 = float2(i + 1, j + 1);

            if (point_inside_triangle(x1y1, A, B, C))
            {
                if (!point_in_polygon(x1y1, size))
                    append(x1y1, size); //polygon.push_back
            }
            else
                whole_pixel = false;
            if (point_inside_triangle(x2y1, A, B, C))
            {
                if (!point_in_polygon(x2y1, size))
                    append(x2y1, size); //polygon.push_back
            }
            else
                whole_pixel = false;
            if (point_inside_triangle(x1y2, A, B, C))
            {
                if (!point_in_polygon(x1y2, size))
                    append(x1y2, size); //polygon.push_back
            }
            else
                whole_pixel = false;
            if (point_inside_triangle(x2y2, A, B, C))
            {
                if (!point_in_polygon(x2y2, size))
                    append(x2y2, size); //polygon.push_back
            }
            else
                whole_pixel = false;
            
            if (whole_pixel)
            {
                x2 += (1.0 / 3.0) * abs(pow(i + 1, 3) - pow(i, 3));
                y2 += (1.0 / 3.0) * abs(pow(j + 1, 3) - pow(j, 3));
                float x_pl = 0.5 * abs(pow(i + 1, 2) - pow(i, 2));
                float y_pl = 0.5 * abs(pow(j + 1, 2) - pow(j, 2));
                x += x_pl;
                y += y_pl;
                xy += x_pl * y_pl; //1.0f / 4.0f * abs(pow(i + 1, 2) - pow(i, 2)) * (pow(j + 1, 2) - pow(j, 2));
                n += 1.0;
                
                xI += x_pl * pixel_color;
                yI += y_pl * pixel_color;
                I += pixel_color;
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
                
                intrsct = intersect_segments(float2(i, j), float2(1, 0), A, ab, i0, i1);
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

                intrsct = intersect_segments(float2(i, j), float2(0, 1), A, ab, i0, i1);
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
                
                intrsct = intersect_segments(float2(i + 1, j), float2(0, 1), A, ab, i0, i1);
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
                
                intrsct = intersect_segments(float2(i, j + 1), float2(1, 0), A, ab, i0, i1);
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
                
                //AC
                
                intrsct = intersect_segments(float2(i, j), float2(1, 0), A, ac, i0, i1);
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

                intrsct = intersect_segments(float2(i, j), float2(0, 1), A, ac, i0, i1);
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
                
                intrsct = intersect_segments(float2(i + 1, j), float2(0, 1), A, ac, i0, i1);
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
                
                intrsct = intersect_segments(float2(i, j + 1), float2(1, 0), A, ac, i0, i1);
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
                
                //BC
                
                intrsct = intersect_segments(float2(i, j), float2(1, 0), B, bc, i0, i1);
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

                intrsct = intersect_segments(float2(i, j), float2(0, 1), B, bc, i0, i1);
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
                
                intrsct = intersect_segments(float2(i + 1, j), float2(0, 1), B, bc, i0, i1);
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
                
                intrsct = intersect_segments(float2(i, j + 1), float2(1, 0), B, bc, i0, i1);
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
                
                
                if (size >= 3)
                {
                    r123 = float3(0.0, 0.0, 0.0);
                    r456 = float3(0.0, 0.0, 0.0);
                    integrate_over_polygon(r123, r456, size);
                    
                    x2 += r123.x;
                    y2 += r123.y;
                    x += r123.z;
                    y += r456.x;
                    xy += r456.y;
                    n += r456.z;
                    
                    xI += r123.z * pixel_color;
                    yI += r456.x * pixel_color;
                    I += r456.z * pixel_color;
                }
            }
        }
    }
    /*if (1 || x2 != x2 || y2 != y2 || x != x || y != y || xy != xy || n != n)
    {
        coefficients.Store3(DTid * 36, asuint(float3(0, 0, x2)));
        coefficients.Store3(DTid * 36 + 12, asuint(float3(0, 0, x2)));
        coefficients.Store3(DTid * 36 + 24, asuint(float3(0, 0, x2)));
        return;
    }*/
    float3x3 M = { x2, xy, x, xy, y2, y, x, y, n };
    float3x3 L = cholesky(M);
    
    const float EPS = 1E-5;
    float3 abcR, abcG, abcB;
    if (L._m00 > EPS && L._m11 > EPS && L._m22 > EPS)
    {
        float3 bR = float3(xI.x, yI.x, I.x);
        float3 bG = float3(xI.y, yI.y, I.y);
        float3 bB = float3(xI.z, yI.z, I.z);

        abcR = cholesky_solve(L, bR);
        abcG = cholesky_solve(L, bG);
        abcB = cholesky_solve(L, bB);
    }
    else
    {
        abcR = float3(0, 0, I.x / (float) n);
        abcG = float3(0, 0, I.y / (float) n);
        abcB = float3(0, 0, I.z / (float) n);
    }
    
    /*abcR = DTid == 51 ? float3(0, 0, x2) : abcR;
    abcG = DTid == 51 ? float3(0, 0, 1) : abcG;
    abcB = DTid == 51 ? float3(0, 0, 1) : abcB;*/
    
    /*if (1 && DTid == 51)
    {
        coefficients.Store3(DTid * 36, asuint(float3(0, 0, x2)));
        coefficients.Store3(DTid * 36 + 12, asuint(float3(0, 0, 1)));
        coefficients.Store3(DTid * 36 + 24, asuint(float3(0, 0, 1)));
        return;
    }*/
    coefficients.Store3(DTid * 36, asuint(abcR));
    coefficients.Store3(DTid * 36 + 12, asuint(abcG));
    coefficients.Store3(DTid * 36 + 24, asuint(abcB));
}