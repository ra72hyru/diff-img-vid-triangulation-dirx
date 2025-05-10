ByteAddressBuffer coefficients : register(t0);

Texture2D image : register(t1);
RWByteAddressBuffer errors : register(u1);

float4 main(float4 pos : SV_POSITION, uint primitiveID : SV_PrimitiveID) : SV_TARGET
{
    float3 abcR = asfloat(coefficients.Load3(primitiveID * 36));
    float3 abcG = asfloat(coefficients.Load3(primitiveID * 36 + 12));
    float3 abcB = asfloat(coefficients.Load3(primitiveID * 36 + 24));
    
    float R = max(min(abcR.x * pos.x + abcR.y * pos.y + abcR.z, 1), 0);
    float G = max(min(abcG.x * pos.x + abcG.y * pos.y + abcG.z, 1), 0);
    float B = max(min(abcB.x * pos.x + abcB.y * pos.y + abcB.z, 1), 0);
    
    float3 rgb01 = float3(R, G, B);
    float3 rgb = float3(rgb01 * 255);
    
    float3 img01 = image.Load(int3(pos.x, pos.y, 0)).rgb;
    float3 img = float3(img01 * 255);
    
    uint blob;
    uint3 err = uint3((img.x - rgb.x) * (img.x - rgb.x), (img.y - rgb.y) * (img.y - rgb.y), (img.z - rgb.z) * (img.z - rgb.z));
    
    errors.InterlockedAdd(primitiveID * 16, err.x, blob);
    errors.InterlockedAdd(primitiveID * 16 + 4, err.y, blob);
    errors.InterlockedAdd(primitiveID * 16 + 8, err.z, blob);
    errors.InterlockedAdd(primitiveID * 16 + 12, 1, blob);

    //if (primitiveID == 254) 
      //  return float4(1, 1, 1, 1);
    
    return float4(rgb01, 1.0f);
}