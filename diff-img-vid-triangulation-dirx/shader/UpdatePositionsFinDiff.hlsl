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
}

[numthreads(512, 1, 1)]
void main( uint DTid : SV_DispatchThreadID )
{
    float2 gradient = float2(0.0f, 0.0f);
    float2 gr = float2(0.0f, 0.0f);
    uint offset = index_in_neighbor_list.Load(DTid.x * 4) * 4;
    uint count = neighbor_count.Load(DTid.x * 4);
    
    [unroll(15)]
    for (uint i = 0; i < count; i++)
    {
        uint tri_index = neighbor_list.Load(offset + i * 4);
        uint3 ind = indices.Load3(tri_index * 12);
        float2 neighbor_gradient;
        float3 neighbor_color_pl_x;
        float3 neighbor_color_mi_x;
        float3 neighbor_color_pl_y;
        float3 neighbor_color_mi_y;
        float3 grad3;
        if (ind.x == DTid)
        {
            //neighbor_gradient = asfloat(fin_diffs.Load2(tri_index * 24 + 16));
            neighbor_color_pl_x = asfloat(fin_diffs.Load3(tri_index * 144));
            neighbor_color_mi_x = asfloat(fin_diffs.Load3(tri_index * 144 + 12));
            neighbor_color_pl_y = asfloat(fin_diffs.Load3(tri_index * 144 + 24));
            neighbor_color_mi_y = asfloat(fin_diffs.Load3(tri_index * 144 + 36));
        }
        else if (ind.y == DTid)
        {
            //neighbor_gradient = asfloat(fin_diffs.Load2(tri_index * 24 + 8));
            neighbor_color_pl_x = asfloat(fin_diffs.Load3(tri_index * 144 + 48));
            neighbor_color_mi_x = asfloat(fin_diffs.Load3(tri_index * 144 + 60));
            neighbor_color_pl_y = asfloat(fin_diffs.Load3(tri_index * 144 + 72));
            neighbor_color_mi_y = asfloat(fin_diffs.Load3(tri_index * 144 + 84));
        }
        else
        {
            //neighbor_gradient = asfloat(fin_diffs.Load2(tri_index * 24));
            neighbor_color_pl_x = asfloat(fin_diffs.Load3(tri_index * 144 + 96));
            neighbor_color_mi_x = asfloat(fin_diffs.Load3(tri_index * 144 + 108));
            neighbor_color_pl_y = asfloat(fin_diffs.Load3(tri_index * 144 + 120));
            neighbor_color_mi_y = asfloat(fin_diffs.Load3(tri_index * 144 + 132));
        }
        
        grad3 = (neighbor_color_pl_x - neighbor_color_mi_x) * 0.5;
        gradient.x += grad3.x + grad3.y + grad3.z;
        grad3 = (neighbor_color_pl_y - neighbor_color_mi_y) * 0.5;
        gradient.y += grad3.x + grad3.y + grad3.z;
        //gradient += neighbor_gradient;
    }
    
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
    
    positions.Store2(DTid.x * 8, asuint(position));
    return;
}