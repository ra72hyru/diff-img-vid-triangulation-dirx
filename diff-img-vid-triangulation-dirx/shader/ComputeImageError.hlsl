//THIS FILE IS NOT USED
Texture2D image : register(t0);
Texture2D triangulated : register(t1);

RWByteAddressBuffer errors : register(u0);

[numthreads(16, 16, 1)]
void main( uint3 GRid : SV_GroupID, uint3 DTid : SV_DispatchThreadID )
{
    uint3 dims;
    triangulated.GetDimensions(0, dims.x, dims.y, dims.z);
    if (DTid.x >= dims.x || DTid.y >= dims.y)
        return;
    
    float3 rgb = triangulated.Load(uint3(DTid.x, DTid.y, 0)).rgb;
    float3 img01 = image.Load(uint3(DTid.x, DTid.y, 0)).rgb;
            
    //float3 rgb = float3(rgb01 * 255);
    float3 img = float3(img01 * 255);
    
    uint blob;
    uint3 err = uint3((img.x - rgb.x) * (img.x - rgb.x), (img.y - rgb.y) * (img.y - rgb.y), (img.z - rgb.z) * (img.z - rgb.z));
    
    uint groupsX = dims.x;
    groupsX = groupsX % 16 == 0 ? groupsX / 16 : groupsX / 16 + 1;
    errors.InterlockedAdd((groupsX * GRid.y + GRid.x) * 16, err.x, blob);
    errors.InterlockedAdd((groupsX * GRid.y + GRid.x) * 16 + 4, err.y, blob);
    errors.InterlockedAdd((groupsX * GRid.y + GRid.x) * 16 + 8, err.z, blob);
    errors.InterlockedAdd((groupsX * GRid.y + GRid.x) * 16 + 12, 1, blob);
}