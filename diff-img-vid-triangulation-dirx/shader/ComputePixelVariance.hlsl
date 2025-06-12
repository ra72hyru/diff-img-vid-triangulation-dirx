//THIS FILE IS EXPERIMENTAL AND NOT REALLY USED
ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
Texture2D image : register(t2);
RWByteAddressBuffer variances : register(u0);

cbuffer params : register(b0)
{
    int num;
}

[numthreads(64, 1, 1)]
void main(uint DTid : SV_DispatchThreadID)
{
    if (DTid >= num)
        return;

    uint3 inds = indices.Load3(DTid * 12);
    
    float2 A = asfloat(positions.Load2(inds.x * 8));
    float2 B = asfloat(positions.Load2(inds.y * 8));
    float2 C = asfloat(positions.Load2(inds.z * 8));
    
    float min_x = min(A.x, min(B.x, C.x));
    float max_x = max(A.x, max(B.x, C.x));
    
    float min_y = min(A.y, min(B.y, C.y));
    float max_y = max(A.y, max(B.y, C.y));
    
    int pixel_right_x = floor(min_x);
    int pixel_bottom_y = floor(min_y);
    int pixel_left_x = ceil(max_x);
    int pixel_top_y = ceil(max_y);
    
    float3 variance = float3(0.0f, 0.0f, 0.0f);
    float3 mean = float3(0.0f, 0.0f, 0.0f);
    int pixel_count = 0;
    for (int i = pixel_right_x; i < pixel_left_x; i++)
    {
        for (int j = pixel_bottom_y; j < pixel_top_y; j++)
        {          
            float3 pixel_color = image.Load(int3(i, j, 0));
            
            pixel_count += 1;
            mean += pixel_color;
        }
    }
    mean /= (float) pixel_count;

    for (int k = pixel_right_x; k < pixel_left_x; k++)
    {
        for (int j = pixel_bottom_y; j < pixel_top_y; j++)
        {
            float3 pixel_color = image.Load(int3(i, j, 0));
            
            variance += (pixel_color - mean) * (pixel_color - mean);
        }
    }
    variance /= (float) pixel_count;
    variances.Store3(DTid * 12, asuint(variance));
}