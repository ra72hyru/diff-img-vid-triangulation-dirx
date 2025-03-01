ByteAddressBuffer color : register(t0);

float4 main(uint primitiveID : SV_PrimitiveID) : SV_TARGET
{
    float3 rgb = asfloat(color.Load3(primitiveID * 12));
	return float4(rgb, 1.0f);
}