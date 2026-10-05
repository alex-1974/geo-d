module geo.internal.dyadic_product_subtraction_decomposition_bench;

import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

import geo.internal.dyadic :
    SignedDyadicCoordinate,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

enum size_t iterations = 100_000;
__gshared ulong sink;

private struct Inputs
{
    SignedDyadicCoordinate ax, ay, bx, by, cx, cy;
}

private struct ProductPair
{
    SignedDyadicProduct lhs;
    SignedDyadicProduct rhs;
}

private Inputs[2] cases;
private ProductPair[2] pairs;

private void prepare()
{
    cases[0] = Inputs(
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(10.0),
        decodeDyadicCoordinate(10.0),
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(0.0)
    );
    cases[1] = Inputs(
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(11.0),
        decodeDyadicCoordinate(11.0),
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(1.0)
    );

    foreach (i, ref const v; cases)
    {
        const auto bax = subtractDyadicCoordinates(v.bx, v.ax);
        const auto bay = subtractDyadicCoordinates(v.by, v.ay);
        const auto cax = subtractDyadicCoordinates(v.cx, v.ax);
        const auto cay = subtractDyadicCoordinates(v.cy, v.ay);

        pairs[i].lhs = multiplyDyadicDifferences(bax, cay);
        pairs[i].rhs = multiplyDyadicDifferences(bay, cax);
    }
}

private ulong fingerprint(ref const SignedDyadicProduct value)
{
    ulong result = cast(ulong)(value.sign + 1);
    foreach (i; 0 .. value.magnitude.limb.length)
        result = (result * 0x100000001b3UL) ^ value.magnitude.limb[i];
    return result;
}

pragma(inline, false)
private ulong observationBaseline(size_t i)
{
    ref const pair = pairs[i & 1];
    return fingerprint(pair.lhs);
}

pragma(inline, false)
private ulong reconstructedZeroRhs(size_t i)
{
    ref const pair = pairs[i & 1];

    SignedDyadicProduct result;
    if (pair.rhs.sign == 0)
    {
        result.sign = pair.lhs.sign;
        result.magnitude = pair.lhs.magnitude;
    }
    else
    {
        result.sign = pair.rhs.sign;
        result.magnitude = pair.rhs.magnitude;
    }

    return fingerprint(result);
}

pragma(inline, false)
private ulong authoritativeSubtract(size_t i)
{
    ref const pair = pairs[i & 1];
    const auto result = subtractDyadicProducts(pair.lhs, pair.rhs);
    return fingerprint(result);
}

private void oracle()
{
    foreach (ref const pair; pairs)
    {
        // These are exactly the two determinant cases used by
        // determinant_kernel_decomposition_bench.d. Both exercise the
        // rhs-sign-zero fast path in subtractDyadicProducts.
        assert(pair.lhs.sign != 0);
        assert(pair.rhs.sign == 0);

        SignedDyadicProduct reconstructed;
        reconstructed.sign = pair.lhs.sign;
        reconstructed.magnitude = pair.lhs.magnitude;

        const auto authoritative =
            subtractDyadicProducts(pair.lhs, pair.rhs);

        assert(authoritative.sign == reconstructed.sign);
        assert(authoritative.magnitude.limb ==
            reconstructed.magnitude.limb);
    }
}

private void bench(alias operation)(string name)
{
    ulong local;
    foreach (i; 0 .. 1000)
        local ^= operation(i);

    StopWatch sw;
    sw.start();
    foreach (i; 0 .. iterations)
        local ^= operation(i);
    sw.stop();

    sink ^= local;
    writefln("%-28s %12.2f ns/op", name,
        cast(double) sw.peek.total!"nsecs" /
        cast(double) iterations);
}

void main()
{
    prepare();
    oracle();

    bench!observationBaseline("observation baseline");
    bench!reconstructedZeroRhs("reconstructed rhs-zero");
    bench!authoritativeSubtract("authoritative subtraction");

    writefln("path: rhs-sign-zero");
    writefln("oracle: bit-identical");
    writefln("sink: %s", sink);
}
