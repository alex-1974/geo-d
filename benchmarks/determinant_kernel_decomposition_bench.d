module geo.internal.determinant_kernel_decomposition_bench;

import geo.internal.dyadic :
    SignedDyadicCoordinate,
    SignedDyadicDifference,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;
import geo.internal.orientation_dyadic :
    orientationDeterminantDyadicDecoded;

import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

enum size_t iterations = 100_000;
__gshared ulong sink;

private struct Inputs
{
    SignedDyadicCoordinate ax, ay, bx, by, cx, cy;
}

private Inputs[2] cases;

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
}

private ulong fingerprint(ref const SignedDyadicProduct value)
{
    ulong result = cast(ulong)(value.sign + 1);
    foreach (i; 0 .. value.magnitude.limb.length)
        result = (result * 0x100000001b3UL) ^ value.magnitude.limb[i];
    return result;
}

pragma(inline, false)
private ulong full(size_t i)
{
    ref const v = cases[i & 1];
    const auto d = orientationDeterminantDyadicDecoded(
        v.ax, v.ay, v.bx, v.by, v.cx, v.cy);
    return fingerprint(d);
}

pragma(inline, false)
private ulong differences(size_t i)
{
    ref const v = cases[i & 1];
    const auto bax = subtractDyadicCoordinates(v.bx, v.ax);
    const auto bay = subtractDyadicCoordinates(v.by, v.ay);
    const auto cax = subtractDyadicCoordinates(v.cx, v.ax);
    const auto cay = subtractDyadicCoordinates(v.cy, v.ay);
    return cast(ulong)(bax.sign + bay.sign + cax.sign + cay.sign + 4)
        ^ bax.magnitude.limb[33] ^ bay.magnitude.limb[33]
        ^ cax.magnitude.limb[33] ^ cay.magnitude.limb[33];
}

pragma(inline, false)
private ulong products(size_t i)
{
    ref const v = cases[i & 1];
    const auto bax = subtractDyadicCoordinates(v.bx, v.ax);
    const auto bay = subtractDyadicCoordinates(v.by, v.ay);
    const auto cax = subtractDyadicCoordinates(v.cx, v.ax);
    const auto cay = subtractDyadicCoordinates(v.cy, v.ay);
    const auto p = multiplyDyadicDifferences(bax, cay);
    const auto q = multiplyDyadicDifferences(bay, cax);
    return cast(ulong)(p.sign + q.sign + 2)
        ^ p.magnitude.limb[67] ^ q.magnitude.limb[67];
}

pragma(inline, false)
private ulong finalSubtract(size_t i)
{
    ref const v = cases[i & 1];
    const auto bax = subtractDyadicCoordinates(v.bx, v.ax);
    const auto bay = subtractDyadicCoordinates(v.by, v.ay);
    const auto cax = subtractDyadicCoordinates(v.cx, v.ax);
    const auto cay = subtractDyadicCoordinates(v.cy, v.ay);
    const auto p = multiplyDyadicDifferences(bax, cay);
    const auto q = multiplyDyadicDifferences(bay, cax);
    const auto result = subtractDyadicProducts(p, q);
    return fingerprint(result);
}

private void oracle()
{
    foreach (ref const v; cases)
    {
        const auto authoritative = orientationDeterminantDyadicDecoded(
            v.ax, v.ay, v.bx, v.by, v.cx, v.cy);

        const auto bax = subtractDyadicCoordinates(v.bx, v.ax);
        const auto bay = subtractDyadicCoordinates(v.by, v.ay);
        const auto cax = subtractDyadicCoordinates(v.cx, v.ax);
        const auto cay = subtractDyadicCoordinates(v.cy, v.ay);
        const auto p = multiplyDyadicDifferences(bax, cay);
        const auto q = multiplyDyadicDifferences(bay, cax);
        const auto decomposed = subtractDyadicProducts(p, q);

        assert(authoritative.sign == decomposed.sign);
        assert(authoritative.magnitude.limb == decomposed.magnitude.limb);
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
    writefln("%-24s %12.2f ns/op", name,
        cast(double) sw.peek.total!"nsecs" / cast(double) iterations);
}

void main()
{
    prepare();
    oracle();
    bench!differences("4 coordinate subtracts");
    bench!products("subtracts + 2 products");
    bench!finalSubtract("complete decomposed");
    bench!full("authoritative decoded");
    writefln("oracle: bit-identical");
    writefln("sink: %s", sink);
}
