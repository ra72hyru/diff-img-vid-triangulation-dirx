ByteAddressBuffer indices : register(t0);
ByteAddressBuffer gradients : register(t1);
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
    float trustRegion;
    float damping;
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
    if (sI <= 1E-5 || sI >= 0.99999)
    {
        return 0;
    }

    float tI = cross(d1, w) / D;
    if (tI <= 1E-5 || tI >= 0.9999)
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
    
    int f_right = 1;
    float2 n = -normal_out(bc, ba);
    if (dot(n, float2(dx, dy)) > 0)
        f_right = -1;
    
    int f_left = 1;
    n = -normal_out(ac, -ba);
    if (dot(n, float2(dx, dy)) > 0)
        f_left = -1;

    float grad = 0.0f;
    
    int curX = floor(B.x);
    int curY = floor(B.y);
    int endX = floor(C.x);
    int endY = floor(C.y);
    
    float2 p = B;
    float2 q;
    
    float2 i0, i1;
    int intrsct;
    float a = 0, b = 0, err;
    float3 img_col, err3;
    bool4 last_pixel = bool4(false, false, false, false); //Bottom, Top, Left, Right
    
    [loop]
    while (curX != endX || curY != endY)
    {
        img_col = image.Load(int3(curX, curY, 0));
        err3 = pow((img_col - tri_color), 2);
        err = err3.x + err3.y + err3.z;
        
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(B, bc, float2(curX, curY), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - B) / length_bc;
                
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                p = q;
                a = b;
                curY += 1; //curY = (B.y < C.y) ? curY + 1 : curY - 1;
                last_pixel = bool4(false, true, false, false);
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - B) / length_bc;
                a = length(q - B) / length_bc;
            
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                curX = (B.x < C.x) ? curX + 1 : curX - 1;
                continue;
            }
        }
        
        if (!last_pixel.z)
        {
            intrsct = intersect_segments(B, bc, float2(curX, curY), float2(0, 1), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - B) / length_bc;
                
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                p = q;
                a = b;
                curX -= 1;
                last_pixel = bool4(false, false, false, true);
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - B) / length_bc;
                a = length(q - B) / length_bc;
            
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                curY = (B.y < C.y) ? curY + 1 : curY - 1;
                continue;
            }
        }
        
        if (!last_pixel.w)
        {
            intrsct = intersect_segments(B, bc, float2(curX + 1, curY), float2(0, 1), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - B) / length_bc;
                
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                p = q;
                a = b;
                curX += 1;
                last_pixel = bool4(false, false, true, false);
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - B) / length_bc;
                a = length(q - B) / length_bc;
            
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                curY = (B.y < C.y) ? curY + 1 : curY - 1;
                continue;
            }
        }
        
        if (!last_pixel.y)
        {
            intrsct = intersect_segments(B, bc, float2(curX, curY + 1), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - B) / length_bc;
                
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                p = q;
                a = b;
                curY -= 1;
                last_pixel = bool4(true, false, false, false);
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - B) / length_bc;
                a = length(q - B) / length_bc;
            
                grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                curX = (B.x < C.x) ? curX + 1 : curX - 1;
                continue;
            }
        }
    }
    
    //TODO: p - C nach den Schleifen
    img_col = image.Load(int3(curX, curY, 0));
    err3 = pow((img_col - tri_color), 2);
    err = err3.x + err3.y + err3.z;
    a = max(a, b);
    b = 1.0f;
    grad += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
    
    curX = floor(A.x);
    curY = floor(A.y);
    
    while (false && curX < endX && curY < endY)
    {
        img_col = image.Load(int3(curX, curY, 0));
        err3 = pow((img_col - tri_color), 2);
        err = err3.x + err3.y + err3.z;
        
        intrsct = intersect_segments(A, ac, float2(curX, curY), float2(1, 0), i0, i1);
        if (intrsct == 1)
        {
            q = i0;
            b = length(p - A) / length_ac;
                
            grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
            p = q;
            a = b;
            curY += 1;
            continue;
        }
        else if (intrsct == 2)
        {
            p = i0;
            q = i1;
            
            b = length(p - A) / length_ac;
            a = length(q - A) / length_ac;
            
            grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
            curX = A.x < C.x ? curX + 1 : curX - 1;
            continue;
        }
        
        intrsct = intersect_segments(A, ac, float2(curX, curY), float2(0, 1), i0, i1);
        if (intrsct == 1)
        {
            q = i0;
            b = length(p - A) / length_ac;
                
            grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
            p = q;
            a = b;
            curX -= 1;
            continue;
        }
        else if (intrsct == 2)
        {
            p = i0;
            q = i1;
            
            b = length(p - A) / length_ac;
            a = length(q - A) / length_ac;
            
            grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
            curY = A.y < C.y ? curY + 1 : curY - 1;
            continue;
        }
        
        intrsct = intersect_segments(A, ac, float2(curX + 1, curY), float2(0, 1), i0, i1);
        if (intrsct == 1)
        {
            q = i0;
            b = length(p - A) / length_ac;
                
            grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
            p = q;
            a = b;
            curX += 1;
            continue;
        }
        else if (intrsct == 2)
        {
            p = i0;
            q = i1;
            
            b = length(p - A) / length_ac;
            a = length(q - A) / length_ac;
            
            grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
            curY = A.y < C.y ? curY + 1 : curY - 1;
            continue;
        }
        
        intrsct = intersect_segments(A, ac, float2(curX, curY + 1), float2(1, 0), i0, i1);
        if (intrsct == 1)
        {
            q = i0;
            b = length(p - A) / length_ac;
                
            grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
            p = q;
            a = b;
            curY -= 1;
            continue;
        }
        else if (intrsct == 2)
        {
            p = i0;
            q = i1;
            
            b = length(p - A) / length_ac;
            a = length(q - A) / length_ac;
            
            grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
            curX = A.x < C.x ? curX + 1 : curX - 1;
            continue;
        }
    }
        
    img_col = image.Load(int3(curX, curY, 0));
    err3 = pow((img_col - tri_color), 2);
    err = err3.x + err3.y + err3.z;
    a = max(a, b);
    b = 1.0f;
    grad += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;

    return grad;
}

[numthreads(256, 1, 1)]
void main( uint DTid : SV_DispatchThreadID )
{
    float2 gradient = float2(0.0f, 0.0f);
    float2 gr = float2(0.0f, 0.0f);
    uint offset = index_in_neighbor_list.Load(DTid.x * 4);
    uint count = neighbor_count.Load(DTid.x * 4);
    
    [unroll(15)]
    for (uint i = 0; i < count; i++)
    {
        uint tri_index = neighbor_list.Load((offset + i) * 4);
        uint3 ind = indices.Load3(tri_index * 12);
        float2 neighbor_gradient;
        if (ind.x == DTid)
        {
            neighbor_gradient = asfloat(gradients.Load2(tri_index * 24 + 16));
        }
        else if (ind.y == DTid)
        {
            neighbor_gradient = asfloat(gradients.Load2(tri_index * 24 + 8));
        }
        else
        {
            neighbor_gradient = asfloat(gradients.Load2(tri_index * 24));
        }
        
        gradient += neighbor_gradient;
    }
    
    bool on_boundary = false;
    float2 position = asfloat(positions.Load2(DTid.x * 8));
    float2 position_old = position;
    if (position.x <= 0.0f || position.x >= width)
    {
        on_boundary = true;
        gradient.x = 0;
    }
    if (position.y <= 0.0f || position.y >= height)
    {
        on_boundary = true;
        gradient.y = 0;
    }

    float2 dir = -stepSize * gradient;
    float len = length(dir);
    if (len > trustRegion)
        dir *= trustRegion / len;
    position += dir;

    if (damping > 0)
    {
        [unroll(15)]
        for (uint i = 0; i < count; i++)
        {
            uint tri_index = neighbor_list.Load((offset + i) * 4);
            uint3 ind = indices.Load3(tri_index * 12);
            
            //A is the moving vertex, B and C are the two other vertices of the current neighbor triangle  
            uint indexB = 0;
            uint indexC = 0;
            
            if (ind.x == DTid)
            {
                indexB = ind.y;
                indexC = ind.z;
            }
            else if (ind.y == DTid)
            {
                indexB = ind.x;
                indexC = ind.z;
            }
            else
            {
                indexB = ind.x;
                indexC = ind.y;
            }
            
            float2 B = asfloat(positions.Load2(indexB * 8));
            float2 C = asfloat(positions.Load2(indexC * 8));
            
            float2 middle = float2(0, 0);
            middle += B + C;
            
            if (!on_boundary)
            {
                middle /= 2.0;
                position += (middle - position) * damping;
            }
        }
    }
    
    position.x = min(max(0, position.x), width);
    position.y = min(max(0, position.y), height);
    
    bool store_new = true;
    [unroll(15)]
    for (uint j = 0; j < count; j++)
    {
        uint tri_index = neighbor_list.Load((offset + j) * 4);
        uint3 ind = indices.Load3(tri_index * 12);
        
        float2 neighbor_gradient;
        if (1 || ind.x == DTid)
        {
            float2 posA = asfloat(positions.Load2(ind.x * 8));
            float2 posB = asfloat(positions.Load2(ind.y * 8));
            float2 posC = asfloat(positions.Load2(ind.z * 8));
            store_new = cross(posB - posA, posC - posA) < 0 ? false : true;
        }
        else if (ind.y == DTid)
        {
            float2 posA = asfloat(positions.Load2(ind.x * 8));
            float2 posB = asfloat(positions.Load2(ind.y * 8));
            float2 posC = asfloat(positions.Load2(ind.z * 8));
            store_new = cross(posA - posB, posC - posB) < 0 ? false : true;
        }
        else
        {
            float2 posA = asfloat(positions.Load2(ind.x * 8));
            float2 posB = asfloat(positions.Load2(ind.y * 8));
            float2 posC = asfloat(positions.Load2(ind.z * 8));
            store_new = cross(posA - posC, posB - posC) < 0 ? false : true;
        }
    }
    
    if (store_new)
        positions.Store2(DTid.x * 8, asuint(position));
    
    //positions.Store2(DTid.x * 8, asuint(gradient));
    return;
}