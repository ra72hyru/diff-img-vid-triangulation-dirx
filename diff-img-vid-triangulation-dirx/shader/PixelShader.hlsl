ByteAddressBuffer color : register(t0);

float4 main(uint primitiveID : SV_PrimitiveID) : SV_TARGET
{
    //if (primitiveID == 10)//546)
      //  return float4(0, 0, 0, 0);
    //return float4(primitiveID % 2, (primitiveID + 1) % 2, 0, 0);
    float3 rgb = asfloat(color.Load3(primitiveID * 12));
    return float4(rgb, 1.0f);
}