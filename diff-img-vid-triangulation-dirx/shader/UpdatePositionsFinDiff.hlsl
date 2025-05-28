ByteAddressBuffer indices : register(t0);
ByteAddressBuffer fin_diffs : register(t1);
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

[numthreads(256, 1, 1)]
void main( uint DTid : SV_DispatchThreadID )
{
    float2 gradient = float2(0.0f, 0.0f);
    float2 gr = float2(0.0f, 0.0f);
    uint offset = index_in_neighbor_list.Load(DTid.x * 4);
    uint count = neighbor_count.Load(DTid.x * 4);
    
    float3 neighbor_error_pl_x = float3(0, 0, 0);
    float3 neighbor_error_mi_x = float3(0, 0, 0);
    float3 neighbor_error_pl_y = float3(0, 0, 0);
    float3 neighbor_error_mi_y = float3(0, 0, 0);
    
    [unroll(15)]
    for (uint i = 0; i < count; i++)
    {
        uint tri_index = neighbor_list.Load((offset + i) * 4);
        uint3 ind = indices.Load3(tri_index * 12);
        /*float2 neighbor_gradient;
        float3 neighbor_error_pl_x;
        float3 neighbor_error_mi_x;
        float3 neighbor_error_pl_y;
        float3 neighbor_error_mi_y;*/
        float3 grad3;
        uint j = (ind.x == DTid) ? 0 : (ind.y == DTid ? 1 : 2);
        
        //neighbor_gradient = asfloat(fin_diffs.Load2(tri_index * 24 + 16));
        /*neighbor_error_pl_x = asfloat(fin_diffs.Load3(tri_index * 144 + j * 48));
        neighbor_error_mi_x = asfloat(fin_diffs.Load3(tri_index * 144 + j * 48 + 12));
        neighbor_error_pl_y = asfloat(fin_diffs.Load3(tri_index * 144 + j * 48 + 24));
        neighbor_error_mi_y = asfloat(fin_diffs.Load3(tri_index * 144 + j * 48 + 36));*/
        neighbor_error_pl_x += asfloat(fin_diffs.Load3(tri_index * 144 + j * 48));
        neighbor_error_mi_x += asfloat(fin_diffs.Load3(tri_index * 144 + j * 48 + 12));
        neighbor_error_pl_y += asfloat(fin_diffs.Load3(tri_index * 144 + j * 48 + 24));
        neighbor_error_mi_y += asfloat(fin_diffs.Load3(tri_index * 144 + j * 48 + 36));
    
        
        
        /*float pl3x = (neighbor_error_pl_x.r + neighbor_error_pl_x.g + neighbor_error_pl_x.b) / 3.0;
        float mi3x = (neighbor_error_mi_x.r + neighbor_error_mi_x.g + neighbor_error_mi_x.b) / 3.0;
        float pl3y = (neighbor_error_pl_y.r + neighbor_error_pl_y.g + neighbor_error_pl_y.b) / 3.0;
        float mi3y = (neighbor_error_mi_y.r + neighbor_error_mi_y.g + neighbor_error_mi_y.b) / 3.0;
        gradient.x += (pl3x - mi3x) * 0.5;
        gradient.y += (pl3y - mi3y) * 0.5;*/
        /*grad3 = (neighbor_error_pl_x - neighbor_error_mi_x) * 0.5;
        gradient.x += grad3.x + grad3.y + grad3.z;
        grad3 = (neighbor_error_pl_y - neighbor_error_mi_y) * 0.5;
        gradient.y += grad3.x + grad3.y + grad3.z;*/
        //gradient += neighbor_gradient;
    }
    
    float neplx_s = (neighbor_error_pl_x.x + neighbor_error_pl_x.y + neighbor_error_pl_x.z) / 3.0;
    float nemix_s = (neighbor_error_mi_x.x + neighbor_error_mi_x.y + neighbor_error_mi_x.z) / 3.0;
    float neply_s = (neighbor_error_pl_y.x + neighbor_error_pl_y.y + neighbor_error_pl_y.z) / 3.0;
    float nemiy_s = (neighbor_error_mi_y.x + neighbor_error_mi_y.y + neighbor_error_mi_y.z) / 3.0;
    
    gradient.x = (neplx_s - nemix_s) * 0.5;
    gradient.y = (neply_s - nemiy_s) * 0.5;
    
    bool on_boundary = false;
    float2 position = asfloat(positions.Load2(DTid.x * 8));
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

    float2 dir = -stepSize * gradient; //* 10000;
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