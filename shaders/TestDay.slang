module test;

[shader("compute")]
[numthreads(8, 1, 1)]
void TestDay(uint3 coord : SV_DispatchThreadID, uniform RWStructuredBuffer<float> output)
{
    if (coord.x >= 8)
        return;

    output[coord.x] = float(coord.x);
}
