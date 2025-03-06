ByteAddressBuffer coefficients : register(t0);

float4 main(uint primitiveID : SV_PrimitiveID, float4 pos : SV_POSITION) : SV_TARGET
{
    float3 abcR = asfloat(coefficients.Load3(primitiveID * 36));
    float3 abcG = asfloat(coefficients.Load3(primitiveID * 36 + 12));
    float3 abcB = asfloat(coefficients.Load3(primitiveID * 36 + 24));
    float R = max(min(abcR.x * pos.x + abcR.y * pos.y + abcR.z, 1), 0);
    float G = max(min(abcG.x * pos.x + abcG.y * pos.y + abcG.z, 1), 0);
    float B = max(min(abcB.x * pos.x + abcB.y * pos.y + abcB.z, 1), 0);
	return float4(R, G, B, 1.0f);
}