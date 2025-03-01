ByteAddressBuffer indices : register(t0);
ByteAddressBuffer colors : register(t1);
ByteAddressBuffer neighbor_list : register(t2);
ByteAddressBuffer index_in_neighbor_list : register(t3);
ByteAddressBuffer neighbor_count : register(t4);
Texture2D image : register(t5);

RWByteAddressBuffer positions : register(u0);

cbuffer params : register(b0)
{
    float stepSize;
    int width;
    int height;
}

float cross(float2 v, float2 w)
{
    return v.x * w.y - v.y * w.x;
}

float2 normal_out(float2 v, float2 w)
{
    float2 n = float2(v.y, -v.x);
    if (dot(v, w) > 0)
        return -n;
    return n;
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

float gradient_rtt(float3 tri_color, float dx, float dy, float2 A, float2 B, float2 C)
{
    float2 ba = A - B;
    float2 ac = C - A;
    float2 bc = C - B;
    
    float length_bc = length(bc);
    float length_ac = length(ac);
    
    float2 n_bc = normalize(normal_out(bc, ba));
    float2 n_ac = normalize(normal_out(ac, -ba));
    
    int pixel_right_x = floor(min(A.x, min(B.x, C.x)));
    int pixel_bottom_y = floor(min(A.y, min(B.y, C.y)));
    int pixel_left_x = ceil(max(A.x, max(B.x, C.x)));
    int pixel_top_y = ceil(max(A.y, max(B.y, C.y)));
    
    int f_right = 1;
    float2 n = -normal_out(bc, ba);
    if (dot(n, float2(dx, dy)) > 0)
        f_right = -1;
    
    int f_left = 1;
    n = -normal_out(ac, -ba);
    if (dot(n, float2(dx, dy)) > 0)
        f_left = -1;

    float grad = 0.0f;
    
    for (int i = pixel_right_x; i < pixel_left_x; i++)
    {
        for (int j = pixel_bottom_y; j < pixel_top_y; j++)
        {
            float3 img_col = image.Load(int3(i, j, 0));
            float3 err3 = pow((img_col - tri_color), 2);
            float err = err3.x + err3.y + err3.z;
            
            float2 p = float2(-1.0f, -1.0f);
            float2 q = float2(-1.0f, -1.0f);

            if (all(float2(i, j) <= B) && all(B <= float2(i + 1, j + 1)))
                p = B;
            if (all(float2(i, j) <= C) && all(C <= float2(i + 1, j + 1)))
                p = C;
            /*
            if (i <= B.x && B.x <= i + 1 && j <= B.y && B.y <= j + 1) 
			{
				p = B;
			}
			if (i <= C.x && C.x <= i + 1 && j <= C.y && C.y <= j + 1)
			{
				p = C;
			}*/
            
            float2 i0, i1;
            int intrsct = intersect_segments(B, bc, float2(i, j), float2(1, 0), i0, i1);
            
            if (intrsct == 1)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                }
                else if (q.x == -1.0f && any(p != i0))
                {
                    q = i0;
                }
            }
            else if (intrsct == 2)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                    q = i1;
                }
            }
            
            intrsct = intersect_segments(B, bc, float2(i, j), float2(0, 1), i0, i1);
            
            if (intrsct == 1)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                }
                else if (q.x == -1.0f && any(p != i0))
                {
                    q = i0;
                }
            }
            else if (intrsct == 2)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                    q = i1;
                }
            }
            
            intrsct = intersect_segments(B, bc, float2(i + 1, j), float2(0, 1), i0, i1);
            
            if (intrsct == 1)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                }
                else if (q.x == -1.0f && any(p != i0))
                {
                    q = i0;
                }
            }
            else if (intrsct == 2)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                    q = i1;
                }
            }
            
            intrsct = intersect_segments(B, bc, float2(i, j + 1), float2(1, 0), i0, i1);
            
            if (intrsct == 1)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                }
                else if (q.x == -1.0f && any(p != i0))
                {
                    q = i0;
                }
            }
            else if (intrsct == 2)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                    q = i1;
                }
            }
            
            if (q.x != -1.0f)
            {
                float b = length(p - B) / length_bc;
                float a = length(q - B) / length_bc;
                
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            }
            
            /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            
            p = float2(-1.0f, -1.0f);
            q = float2(-1.0f, -1.0f);

            if (all(float2(i, j) <= A) && all(A <= float2(i + 1, j + 1)))
                p = A;
            if (all(float2(i, j) <= C) && all(C <= float2(i + 1, j + 1)))
                p = C;
            /*
            if (i <= B.x && B.x <= i + 1 && j <= B.y && B.y <= j + 1) 
			{
				p = B;
			}
			if (i <= C.x && C.x <= i + 1 && j <= C.y && C.y <= j + 1)
			{
				p = C;
			}*/
            
            intrsct = intersect_segments(A, ac, float2(i, j), float2(1, 0), i0, i1);
            
            if (intrsct == 1)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                }
                else if (q.x == -1.0f && any(p != i0))
                {
                    q = i0;
                }
            }
            else if (intrsct == 2)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                    q = i1;
                }
            }
            
            intrsct = intersect_segments(A, ac, float2(i, j), float2(0, 1), i0, i1);
            
            if (intrsct == 1)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                }
                else if (q.x == -1.0f && any(p != i0))
                {
                    q = i0;
                }
            }
            else if (intrsct == 2)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                    q = i1;
                }
            }
            
            intrsct = intersect_segments(A, ac, float2(i + 1, j), float2(0, 1), i0, i1);
            
            if (intrsct == 1)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                }
                else if (q.x == -1.0f && any(p != i0))
                {
                    q = i0;
                }
            }
            else if (intrsct == 2)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                    q = i1;
                }
            }
            
            intrsct = intersect_segments(A, ac, float2(i, j + 1), float2(1, 0), i0, i1);
            
            if (intrsct == 1)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                }
                else if (q.x == -1.0f && any(p != i0))
                {
                    q = i0;
                }
            }
            else if (intrsct == 2)
            {
                if (p.x == -1.0f)
                {
                    p = i0;
                    q = i1;
                }
            }
            
            if (q.x != -1.0f)
            {
                float b = length(p - A) / length_ac;
                float a = length(q - A) / length_ac;
                
                grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_left;
            }
        }
    }
    return grad;
}

[numthreads(512, 1, 1)]
void main( uint DTid : SV_DispatchThreadID )
{
    //return;
    //all this is executed for each vertex (DTid is the index of the vertex)
    /*float2 pos = asfloat(positions.Load2(DTid.x * 8));
    pos += float2(10.0f, 1.0f);
    //pos.x = min(max(0, pos.x), width);
    //pos.y = min(max(0, pos.y), height);
    positions.Store2(DTid.x * 8, asuint(pos));
    return;*/
    //TODO: 
    float2 gradient = float2(0.0f, 0.0f);
    
    uint offset = index_in_neighbor_list.Load(DTid.x * 4);
    uint count = neighbor_count.Load(DTid.x * 4);
    //TODO: kleineres intersect probieren; nicht alle Pixel durchgehen sondern nur nächsten, je nachdem, in welche Richtung die Kante geht
    float2 pos = asfloat(positions.Load2(DTid * 8));
    pos += float2(offset, 0.0f);
    positions.Store2(DTid.x * 8, asuint(pos));
    return;
    
    for (uint i = 0; i < count; i++)
    {
        uint tri_index = neighbor_list.Load(offset + i * 4);
        float3 tri_color = asfloat(colors.Load3(tri_index * 12));
        uint3 ind = indices.Load3(tri_index * 12);
        float2 A, B, C;
        if (ind.x == DTid.x)
        {
            C = asfloat(positions.Load2(ind.x * 8));
            A = asfloat(positions.Load2(ind.y * 8));
            B = asfloat(positions.Load2(ind.z * 8));
        }
        else if (ind.y == DTid.x)
        {
            C = asfloat(positions.Load2(ind.y * 8));
            A = asfloat(positions.Load2(ind.x * 8));
            B = asfloat(positions.Load2(ind.z * 8));
        }
        else
        {
            C = asfloat(positions.Load2(ind.z * 8));
            A = asfloat(positions.Load2(ind.x * 8));
            B = asfloat(positions.Load2(ind.y * 8));
        }
        
        gradient.x += 1.0f / 3.0f * gradient_rtt(tri_color, 1.0f, 0.0f, A, B, C);
        gradient.y += 1.0f / 3.0f * gradient_rtt(tri_color, 0.0f, 1.0f, A, B, C);

    }
        //update position, clamping, etc.
    float2 position = asfloat(positions.Load2(DTid.x * 8));
    if (position.x <= 0.0f || position.x >= width)
        gradient.x = 0;
    if (position.y <= 0.0f || position.y >= height)
        gradient.y = 0;
        
    float2 dir = -stepSize * gradient;
    float len = length(dir);
    if (len > 1)
        dir *= 1 / len;
    position += dir;
    
    position.x = min(max(0, position.x), width);
    position.y = min(max(0, position.y), height);
    //for all neighbors
    positions.Store2(DTid.x * 8, asuint(position));
}