module geo.internal.dyadic_product_subtraction_decomposition_bench;

import core.stdc.stdio : printf;
import core.time : MonoTime;

import geo.internal.dyadic;
import geo.internal.fixed_uint;

private enum iterations = 1_000_000;

private ulong fingerprint(ref const SignedDyadicProduct value) @safe pure nothrow @nogc
{
    ulong hash = cast(ulong)(value.sign + 2);
    foreach (limb; value.magnitude.limb)
        hash = (hash * 0x100000001b3UL) ^ limb;
    return hash;
}

private ulong fingerprintMagnitude(ref const DyadicProductMagnitude value) @safe pure nothrow @nogc
{
    ulong hash = 0xcbf29ce484222325UL;
    foreach (limb; value.limb)
        hash = (hash * 0x100000001b3UL) ^ limb;
    return hash;
}

private SignedDyadicProduct[2] makeProducts()
{
    const a = decodeDyadicCoordinate(123456789.125);
    const b = decodeDyadicCoordinate(-98765.5);
    const c = decodeDyadicCoordinate(0.03125);

    const ab = subtractDyadicCoordinates(a, b);
    const ac = subtractDyadicCoordinates(a, c);
    const bc = subtractDyadicCoordinates(b, c);

    return [
        multiplyDyadicDifferences(ab, ac),
        multiplyDyadicDifferences(ac, bc)
    ];
}

private double measure(scope ulong delegate() @safe action)
{
    const start = MonoTime.currTime;
    immutable sink = action();
    const stop = MonoTime.currTime;
    printf("sink=%llu\n", cast(ulong) sink);
    return cast(double)(stop - start).total!"nsecs" / iterations;
}

void main() @safe
{
    auto products = makeProducts();
    auto lhs = products[0];
    auto rhs = products[1];

    // Force same-sign subtraction, the determinant path that exercises
    // comparison followed by magnitude subtraction.
    if (lhs.sign != rhs.sign)
        rhs.sign = lhs.sign;

    const auto authoritative = subtractDyadicProducts(lhs, rhs);
    const int comparison = compareUnsigned(lhs.magnitude, rhs.magnitude);

    SignedDyadicProduct reconstructed;
    if (comparison == 0)
    {
        reconstructed.sign = 0;
    }
    else if (comparison > 0)
    {
        reconstructed.sign = lhs.sign;
        reconstructed.magnitude = subtractUnsigned(lhs.magnitude, rhs.magnitude);
    }
    else
    {
        reconstructed.sign = -lhs.sign;
        reconstructed.magnitude = subtractUnsigned(rhs.magnitude, lhs.magnitude);
    }

    assert(authoritative.sign == reconstructed.sign);
    assert(authoritative.magnitude.limb == reconstructed.magnitude.limb);
    printf("oracle: bit-identical\n");

    double ns;

    ns = measure(() @safe {
        ulong sink;
        foreach (_; 0 .. iterations)
            sink += cast(ulong)(compareUnsigned(lhs.magnitude, rhs.magnitude) + 1);
        return sink;
    });
    printf("compare unsigned: %.2f ns\n", ns);

    ns = measure(() @safe {
        ulong sink;
        foreach (_; 0 .. iterations)
        {
            auto copy = lhs.magnitude;
            sink ^= fingerprintMagnitude(copy);
        }
        return sink;
    });
    printf("carrier copy + fingerprint: %.2f ns\n", ns);

    ns = measure(() @safe {
        ulong sink;
        foreach (_; 0 .. iterations)
        {
            auto magnitude = comparison > 0
                ? subtractUnsigned(lhs.magnitude, rhs.magnitude)
                : subtractUnsigned(rhs.magnitude, lhs.magnitude);
            sink ^= fingerprintMagnitude(magnitude);
        }
        return sink;
    });
    printf("magnitude subtraction + fingerprint: %.2f ns\n", ns);

    ns = measure(() @safe {
        ulong sink;
        foreach (_; 0 .. iterations)
        {
            auto result = subtractDyadicProducts(lhs, rhs);
            sink ^= fingerprint(result);
        }
        return sink;
    });
    printf("complete product subtraction: %.2f ns\n", ns);
}
