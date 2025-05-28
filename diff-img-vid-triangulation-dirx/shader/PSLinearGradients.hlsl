ByteAddressBuffer coefficients : register(t0);

//float4 main(uint primitiveID : SV_PrimitiveID, float4 pos : SV_POSITION) : SV_TARGET
float4 main(float4 pos : SV_POSITION, uint primitiveID : SV_PrimitiveID) : SV_TARGET
{
    //return float4(primitiveID % 2, (primitiveID + 1) % 2, (primitiveID + 3) % 3, 0);
    //if (primitiveID == 95)//51)
      //  return float4(1, 0, 0, 1);
    float3 abcR = asfloat(coefficients.Load3(primitiveID * 36));
    float3 abcG = asfloat(coefficients.Load3(primitiveID * 36 + 12));
    float3 abcB = asfloat(coefficients.Load3(primitiveID * 36 + 24));
    //float R = max(min(abcR.x * (pos.x - 0.5) + abcR.y * (pos.y - 0.5) + abcR.z, 1), 0);
    ////float R = max(min(abcR.x * pos.x + abcR.y * pos.y + abcR.z, 1), 0);
    float R = abcR.x * pos.x + abcR.y * pos.y + abcR.z;
    //float G = max(min(abcG.x * (pos.x - 0.5) + abcG.y * (pos.y - 0.5) + abcG.z, 1), 0);
    ////float G = max(min(abcG.x * pos.x + abcG.y * pos.y + abcG.z, 1), 0);
    float G = abcG.x * pos.x + abcG.y * pos.y + abcG.z;
    //float B = max(min(abcB.x * (pos.x - 0.5) + abcB.y * (pos.y - 0.5) + abcB.z, 1), 0);
    ////float B = max(min(abcB.x * pos.x + abcB.y * pos.y + abcB.z, 1), 0);
    float B = abcB.x * pos.x + abcB.y * pos.y + abcB.z;
	return float4(R, G, B, 1.0f);
}