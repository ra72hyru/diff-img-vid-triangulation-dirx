ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
RWByteAddressBuffer coefficients : register(u0);
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

void integrate_over_polygon(inout float3 r1, inout float3 r2)
{
    //sorting
    float2 mean = float2(0.0f, 0.0f);
    
    for (int ii = 0; ii < size; ii++)
    {
        mean += points[ii];
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
    //end of sorting
    
    
    const float EPS = 1E-5;
    float m1, t1, m2, t2, m12, m22, t12, t22, c, d, c2, d2, dc, d2c2, d3c3, d4c4, m2m1, t2t1, t22t12, m22m12, m23m13, m2t2m1t1, m22t2m12t1, m2t22m1t12;
    float2 A = points[0];
    for (int i = 0; i < size - 2; i++)
    {
        float2 C = points[i + 1];
        float2 B = points[i + 2];
        
        float2 tri_ac = C - A;
        float2 tri_ab = B - A;
        float2 tri_bc = C - B;
        
        if (abs(tri_ac.x) <= EPS)
        {
            m1 = tri_bc.y / tri_bc.x;
            t1 = B.y - m1 * B.x;
            m2 = tri_ab.y / tri_ab.x;
            t2 = B.y - m2 * B.x;

            c = min(A.x, B.x);
            d = max(A.x, B.x);
            
            c2 = c * c;
            d2 = d * d;
            dc = d - c;
            d2c2 = d2 - c2;
            d3c3 = d * d2 - c * c2;
            d4c4 = d2 * d2 - c2 * c2;
        
            m12 = m1 * m1;
            m22 = m2 * m2;
            t12 = t1 * t1;
            t22 = t2 * t2;
        
            m2m1 = m2 - m1;
            t2t1 = t2 - t1;
            m22m12 = m22 - m12;
            t22t12 = t22 - t12;
        
            m23m13 = m2 * m22 - m1 * m12;
            m2t2m1t1 = m2 * t2 - m1 * t1;
            m22t2m12t1 = m22 * t2 - m12 * t1;
            m2t22m1t12 = m2 * t22 - m1 * t12;
        
            r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
            r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
            r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
            r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
            r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
            r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
        }
        else if (abs(tri_bc.x) <= EPS)
        {
            m1 = tri_ac.y / tri_ac.x;
            t1 = C.y - m1 * C.x;
            m2 = tri_ab.y / tri_ab.x;
            t2 = B.y - m2 * B.x;

            c = min(A.x, B.x);
            d = max(A.x, B.x);
            
            c2 = c * c;
            d2 = d * d;
            dc = d - c;
            d2c2 = d2 - c2;
            d3c3 = d * d2 - c * c2;
            d4c4 = d2 * d2 - c2 * c2;
        
            m12 = m1 * m1;
            m22 = m2 * m2;
            t12 = t1 * t1;
            t22 = t2 * t2;
        
            m2m1 = m2 - m1;
            t2t1 = t2 - t1;
            m22m12 = m22 - m12;
            t22t12 = t22 - t12;
        
            m23m13 = m2 * m22 - m1 * m12;
            m2t2m1t1 = m2 * t2 - m1 * t1;
            m22t2m12t1 = m22 * t2 - m12 * t1;
            m2t22m1t12 = m2 * t22 - m1 * t12;
        
            r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
            r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
            r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
            r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
            r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
            r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
        }
        else if (abs(tri_ab.x) <= EPS)
        {
            m1 = tri_ac.y / tri_ac.x;
            t1 = C.y - m1 * C.x;
            m2 = tri_bc.y / tri_bc.x;
            t2 = B.y - m2 * B.x;

            c = min(A.x, C.x);
            d = max(A.x, C.x);
            
            c2 = c * c;
            d2 = d * d;
            dc = d - c;
            d2c2 = d2 - c2;
            d3c3 = d * d2 - c * c2;
            d4c4 = d2 * d2 - c2 * c2;
        
            m12 = m1 * m1;
            m22 = m2 * m2;
            t12 = t1 * t1;
            t22 = t2 * t2;
        
            m2m1 = m2 - m1;
            t2t1 = t2 - t1;
            m22m12 = m22 - m12;
            t22t12 = t22 - t12;
        
            m23m13 = m2 * m22 - m1 * m12;
            m2t2m1t1 = m2 * t2 - m1 * t1;
            m22t2m12t1 = m22 * t2 - m12 * t1;
            m2t22m1t12 = m2 * t22 - m1 * t12;
        
            r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
            r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
            r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
            r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
            r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
            r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
        }
        else
        {
            if (A.x < C.x && C.x < B.x || B.x < C.x && C.x < A.x)
            {
                m1 = tri_ac.y / tri_ac.x;
                t1 = C.y - m1 * C.x;
                m2 = tri_ab.y / tri_ab.x;
                t2 = B.y - m2 * B.x;

                c = min(A.x, C.x);
                d = max(A.x, C.x);
                
                c2 = c * c;
                d2 = d * d;
                dc = d - c;
                d2c2 = d2 - c2;
                d3c3 = d * d2 - c * c2;
                d4c4 = d2 * d2 - c2 * c2;
        
                m12 = m1 * m1;
                m22 = m2 * m2;
                t12 = t1 * t1;
                t22 = t2 * t2;
        
                m2m1 = m2 - m1;
                t2t1 = t2 - t1;
                m22m12 = m22 - m12;
                t22t12 = t22 - t12;
        
                m23m13 = m2 * m22 - m1 * m12;
                m2t2m1t1 = m2 * t2 - m1 * t1;
                m22t2m12t1 = m22 * t2 - m12 * t1;
                m2t22m1t12 = m2 * t22 - m1 * t12;
        
                r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
                r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
                r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
                r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
                r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
                r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
                
                m1 = tri_bc.y / tri_bc.x;
                t1 = C.y - m1 * C.x;
                c = min(B.x, C.x);
                d = max(B.x, C.x);
                
                c2 = c * c;
                d2 = d * d;
                dc = d - c;
                d2c2 = d2 - c2;
                d3c3 = d * d2 - c * c2;
                d4c4 = d2 * d2 - c2 * c2;
        
                m12 = m1 * m1;
                m22 = m2 * m2;
                t12 = t1 * t1;
                t22 = t2 * t2;
        
                m2m1 = m2 - m1;
                t2t1 = t2 - t1;
                m22m12 = m22 - m12;
                t22t12 = t22 - t12;
        
                m23m13 = m2 * m22 - m1 * m12;
                m2t2m1t1 = m2 * t2 - m1 * t1;
                m22t2m12t1 = m22 * t2 - m12 * t1;
                m2t22m1t12 = m2 * t22 - m1 * t12;
        
                r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
                r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
                r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
                r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
                r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
                r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
            }
            else if (A.x < B.x && B.x < C.x || C.x < B.x && B.x < A.x)
            {
                m1 = tri_ab.y / tri_ab.x;
                t1 = B.y - m1 * B.x;
                m2 = tri_ac.y / tri_ac.x;
                t2 = C.y - m2 * C.x;
				
                c = min(A.x, B.x);
                d = max(A.x, B.x);
                
                c2 = c * c;
                d2 = d * d;
                dc = d - c;
                d2c2 = d2 - c2;
                d3c3 = d * d2 - c * c2;
                d4c4 = d2 * d2 - c2 * c2;
        
                m12 = m1 * m1;
                m22 = m2 * m2;
                t12 = t1 * t1;
                t22 = t2 * t2;
        
                m2m1 = m2 - m1;
                t2t1 = t2 - t1;
                m22m12 = m22 - m12;
                t22t12 = t22 - t12;
        
                m23m13 = m2 * m22 - m1 * m12;
                m2t2m1t1 = m2 * t2 - m1 * t1;
                m22t2m12t1 = m22 * t2 - m12 * t1;
                m2t22m1t12 = m2 * t22 - m1 * t12;
        
                r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
                r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
                r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
                r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
                r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
                r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
                
                m1 = tri_bc.y / tri_bc.x;
                t1 = B.y - m1 * B.x;
                c = min(C.x, B.x);
                d = max(C.x, B.x);
                
                c2 = c * c;
                d2 = d * d;
                dc = d - c;
                d2c2 = d2 - c2;
                d3c3 = d * d2 - c * c2;
                d4c4 = d2 * d2 - c2 * c2;
        
                m12 = m1 * m1;
                m22 = m2 * m2;
                t12 = t1 * t1;
                t22 = t2 * t2;
        
                m2m1 = m2 - m1;
                t2t1 = t2 - t1;
                m22m12 = m22 - m12;
                t22t12 = t22 - t12;
        
                m23m13 = m2 * m22 - m1 * m12;
                m2t2m1t1 = m2 * t2 - m1 * t1;
                m22t2m12t1 = m22 * t2 - m12 * t1;
                m2t22m1t12 = m2 * t22 - m1 * t12;
        
                r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
                r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
                r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
                r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
                r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
                r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
            }
            else
            {
                m1 = tri_ac.y / tri_ac.x;
                t1 = C.y - m1 * C.x;
                m2 = tri_bc.y / tri_bc.x;
                t2 = B.y - m2 * B.x;

                c = min(A.x, C.x);
                d = max(A.x, C.x);
                
                c2 = c * c;
                d2 = d * d;
                dc = d - c;
                d2c2 = d2 - c2;
                d3c3 = d * d2 - c * c2;
                d4c4 = d2 * d2 - c2 * c2;
        
                m12 = m1 * m1;
                m22 = m2 * m2;
                t12 = t1 * t1;
                t22 = t2 * t2;
        
                m2m1 = m2 - m1;
                t2t1 = t2 - t1;
                m22m12 = m22 - m12;
                t22t12 = t22 - t12;
        
                m23m13 = m2 * m22 - m1 * m12;
                m2t2m1t1 = m2 * t2 - m1 * t1;
                m22t2m12t1 = m22 * t2 - m12 * t1;
                m2t22m1t12 = m2 * t22 - m1 * t12;
        
                r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
                r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
                r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
                r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
                r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
                r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
                
                m1 = tri_ab.y / tri_ab.x;
                t1 = C.y - m1 * C.x;
                c = min(A.x, B.x);
                d = max(A.x, B.x);
                
                c2 = c * c;
                d2 = d * d;
                dc = d - c;
                d2c2 = d2 - c2;
                d3c3 = d * d2 - c * c2;
                d4c4 = d2 * d2 - c2 * c2;
        
                m12 = m1 * m1;
                m22 = m2 * m2;
                t12 = t1 * t1;
                t22 = t2 * t2;
        
                m2m1 = m2 - m1;
                t2t1 = t2 - t1;
                m22m12 = m22 - m12;
                t22t12 = t22 - t12;
        
                m23m13 = m2 * m22 - m1 * m12;
                m2t2m1t1 = m2 * t2 - m1 * t1;
                m22t2m12t1 = m22 * t2 - m12 * t1;
                m2t22m1t12 = m2 * t22 - m1 * t12;
        
                r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
                r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
                r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
                r2.x += abs(0.5f * (1.0f / 3.0f * m22m12 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
                r2.y += abs(0.5f * (0.25f * m22m12 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
                r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);
            }
        }
        /*c2 = c * c;
        d2 = d * d;
        dc = d - c;
        d2c2 = d2 - c2;
        d3c3 = d * d2 - c * c2;
        d4c4 = d2 * d2 - c2 * c2;
        
        m12 = m1 * m1;
        m22 = m2 * m2;
        t12 = t1 * t1;
        t22 = t2 * t2;
        
        m2m1 = m2 - m1;
        t2t1 = t2 - t1;
        m22m12 = m22 - m12;
        t22t12 = t22 - t12;
        
        m23m13 = m2 * m22 - m1 * m12;
        m2t2m1t1 = m2 * t2 - m1 * t1;
        m22t2m12t1 = m22 * t2 - m12 * t1;
        m2t22m1t12 = m2 * t22 - m1 * t12;
        
        r1.x += abs(0.25 * m2m1 * d4c4 + 1.0f / 3.0f * t2t1 * d3c3);
        r1.y += abs(1.0f / 3.0f * (0.25f * m23m13 * d4c4 + m22t2m12t1 * d3c3 + 1.5f * m2t22m1t12 * d2c2 + (t2 * t2 * t2 - t1 * t1 * t1) * dc));
        r1.z += abs(1.0f / 3.0f * m2m1 * d3c3 + 0.5f * t2t1 * d2c2);
        r2.x += abs(0.5f * (1.0f / 3.0f * m22t2m12t1 * d3c3 + m2t2m1t1 * d2c2 + t22t12 * dc));
        r2.y += abs(0.5f * (0.25f * m22t2m12t1 * d4c4 + 2.0f / 3.0f * m2t2m1t1 * d3c3 + 0.5f * t22t12 * d2c2));
        r2.z += abs(0.5f * m2m1 * d2c2 + t2t1 * dc);*/

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

[numthreads(256, 1, 1)]
void main(uint DTid : SV_DispatchThreadID)
{
    
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
    
    float x2 = 0.0f, y2 = 0.0f, x = 0.0f, y = 0.0f, xy = 0.0f, n = 0.0f;
    float3 xI = float3(0.0f, 0.0f, 0.0f);
    float3 yI = float3(0.0f, 0.0f, 0.0f);
    float3 I = float3(0.0f, 0.0f, 0.0f);
    
    float3 r123, r456;
    
    for (int i = pixel_right_x; i < pixel_left_x; i++)
    {
        for (int j = pixel_bottom_y; j < pixel_top_y; j++)
        {
            float3 pixel_color = image.Load(int3(i, j, 0));
            //{float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f), float2(0.0f, 0.0f)}
            size = 0;
            
            float area = 0;
            bool whole_pixel = true;
            
            float2 x1y1 = float2(i, j);
            float2 x2y1 = float2(i + 1, j);
            float2 x1y2 = float2(i, j + 1);
            float2 x2y2 = float2(i + 1, j + 1);

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
                x2 += 1.0f / 3.0f * abs(pow(i + 1, 3) - pow(i, 3));
                y2 += 1.0f / 3.0f * abs(pow(j + 1, 3) - pow(j, 3));
                float x_pl = 0.5f * abs(pow(i + 1, 2) - pow(i, 2));
                float y_pl = 0.5f * abs(pow(j + 1, 2) - pow(j, 2));
                x += x_pl;
                y += y_pl;
                xy += x_pl * y_pl; //1.0f / 4.0f * abs(pow(i + 1, 2) - pow(i, 2)) * (pow(j + 1, 2) - pow(j, 2));
                n += 1.0f;
                
                xI += x_pl * pixel_color;
                yI += y_pl * pixel_color;
                I += pixel_color;
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
                
                if (size >= 3)
                {
                    r123 = float3(0.0f, 0.0f, 0.0f);
                    r456 = float3(0.0f, 0.0f, 0.0f);
                    integrate_over_polygon(r123, r456);
                    
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
    
    coefficients.Store3(DTid * 36, asuint(abcR));
    coefficients.Store3(DTid * 36 + 12, asuint(abcG));
    coefficients.Store3(DTid * 36 + 24, asuint(abcB));
}