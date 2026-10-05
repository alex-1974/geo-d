module geo.internal.dyadic_product_subtraction_decomposition_bench;

import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

import geo.internal.dyadic :
    SignedDyadicCoordinate,
    SignedDyadicDifference,
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

private struct PreparedCase
{
    Inputs input;
    SignedDyadicDifference bax, bay, cax, cay;
    SignedDyadicProduct p, q;
    SignedDyadicProduct determinant;
}

private PreparedCase[2] cases;

pragma(inline, false)
private ulong fingerprintDifference(
    ref const SignedDyadicDifference value,
    size_t salt
)
{
    ulong result = cast(ulong)(value.sign + 1) ^ cast(ulong) salt;
    foreach (limb; value.magnitude.limb)
        result = (result * 0x100000001b3UL) ^ limb;
    return result;
}

private ulong fingerprintProduct(ref const SignedDyadicProduct value)
{
    ulong result = cast(ulong)(value.sign + 1);
    foreach (limb; value.magnitude.limb)
        result = (result * 0x100000001b3UL) ^ limb;
    return result;
}

private void prepare()
{
    cases[0].input = Inputs(
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(10.0),
        decodeDyadicCoordinate(10.0),
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(0.0)
    );
    cases[1].input = Inputs(
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(11.0),
        decodeDyadicCoordinate(11.0),
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(1.0)
    );

    foreach (ref c; cases)
    {
        ref const v = c.input;
        c.bax = subtractDyadicCoordinates(v.bx, v.ax);
        c.bay = subtractDyadicCoordinates(v.by, v.ay);
        c.cax = subtractDyadicCoordinates(v.cx, v.ax);
        c.cay = subtractDyadicCoordinates(v.cy, v.ay);
        c.p = multiplyDyadicDifferences(c.bax, c.cay);
        c.q = multiplyDyadicDifferences(c.bay, c.cax);
        c.determinant = subtractDyadicProducts(c.p, c.q);
    }
}

pragma(inline, false)
private ulong coordinateBaseline(size_t i)
{
    ref const c = cases[i & 1];
    return fingerprintDifference(c.bax, i * 4)
        ^ fingerprintDifference(c.bay, i * 4 + 1)
        ^ fingerprintDifference(c.cax, i * 4 + 2)
        ^ fingerprintDifference(c.cay, i * 4 + 3);
}

pragma(inline, false)
private ulong coordinateOperations(size_t i)
{
    ref const c = cases[i & 1];
    ref const v = c.input;

    const auto bax = subtractDyadicCoordinates(v.bx, v.ax);
    const auto bay = subtractDyadicCoordinates(v.by, v.ay);
    const auto cax = subtractDyadicCoordinates(v.cx, v.ax);
    const auto cay = subtractDyadicCoordinates(v.cy, v.ay);

    return fingerprintDifference(bax, i * 4)
        ^ fingerprintDifference(bay, i * 4 + 1)
        ^ fingerprintDifference(cax, i * 4 + 2)
        ^ fingerprintDifference(cay, i * 4 + 3);
}

pragma(inline, false)
private ulong productBaseline(size_t i)
{
    ref const c = cases[i & 1];
    return fingerprintProduct(c.p)
        ^ fingerprintProduct(c.q);
}

pragma(inline, false)
private ulong productOperations(size_t i)
{
    ref const c = cases[i & 1];

    const auto p = multiplyDyadicDifferences(c.bax, c.cay);
    const auto q = multiplyDyadicDifferences(c.bay, c.cax);

    return fingerprintProduct(p)
        ^ fingerprintProduct(q);
}

pragma(inline, false)
private ulong subtractionBaseline(size_t i)
{
    ref const c = cases[i & 1];
    return fingerprintProduct(c.determinant);
}

pragma(inline, false)
private ulong subtractionOperation(size_t i)
{
    ref const c = cases[i & 1];
    const auto result = subtractDyadicProducts(c.p, c.q);
    return fingerprintProduct(result);
}


pragma(inline, false)
private ulong rhsZeroBaseline(size_t i)
{
    return fingerprintDifference(cases[0].bax, i);
}

pragma(inline, false)
private ulong rhsZeroOperation(size_t i)
{
    ref const v = cases[0].input;
    const auto result = subtractDyadicCoordinates(v.bx, v.ax);
    return fingerprintDifference(result, i);
}

pragma(inline, false)
private ulong lhsZeroBaseline(size_t i)
{
    return fingerprintDifference(cases[0].bay, i);
}

pragma(inline, false)
private ulong lhsZeroOperation(size_t i)
{
    ref const v = cases[0].input;
    const auto result = subtractDyadicCoordinates(v.by, v.ay);
    return fingerprintDifference(result, i);
}

pragma(inline, false)
private ulong zeroZeroBaseline(size_t i)
{
    return fingerprintDifference(cases[0].cax, i);
}

pragma(inline, false)
private ulong zeroZeroOperation(size_t i)
{
    ref const v = cases[0].input;
    const auto result = subtractDyadicCoordinates(v.cx, v.ax);
    return fingerprintDifference(result, i);
}

pragma(inline, false)
private ulong sameSignGreaterBaseline(size_t i)
{
    return fingerprintDifference(cases[1].bax, i);
}

pragma(inline, false)
private ulong sameSignGreaterOperation(size_t i)
{
    ref const v = cases[1].input;
    const auto result = subtractDyadicCoordinates(v.bx, v.ax);
    return fingerprintDifference(result, i);
}

pragma(inline, false)
private ulong sameSignLessBaseline(size_t i)
{
    return fingerprintDifference(cases[1].bay, i);
}

pragma(inline, false)
private ulong sameSignLessOperation(size_t i)
{
    ref const v = cases[1].input;
    const auto result = subtractDyadicCoordinates(v.by, v.ay);
    return fingerprintDifference(result, i);
}

pragma(inline, false)
private ulong sameSignEqualBaseline(size_t i)
{
    return fingerprintDifference(cases[1].cax, i);
}

pragma(inline, false)
private ulong sameSignEqualOperation(size_t i)
{
    ref const v = cases[1].input;
    const auto result = subtractDyadicCoordinates(v.cx, v.ax);
    return fingerprintDifference(result, i);
}

private void oracle()
{
    foreach (ref const c; cases)
    {
        ref const v = c.input;

        const auto bax = subtractDyadicCoordinates(v.bx, v.ax);
        const auto bay = subtractDyadicCoordinates(v.by, v.ay);
        const auto cax = subtractDyadicCoordinates(v.cx, v.ax);
        const auto cay = subtractDyadicCoordinates(v.cy, v.ay);

        assert(bax.sign == c.bax.sign);
        assert(bax.magnitude.limb == c.bax.magnitude.limb);
        assert(bay.sign == c.bay.sign);
        assert(bay.magnitude.limb == c.bay.magnitude.limb);
        assert(cax.sign == c.cax.sign);
        assert(cax.magnitude.limb == c.cax.magnitude.limb);
        assert(cay.sign == c.cay.sign);
        assert(cay.magnitude.limb == c.cay.magnitude.limb);

        const auto p = multiplyDyadicDifferences(bax, cay);
        const auto q = multiplyDyadicDifferences(bay, cax);

        assert(p.sign == c.p.sign);
        assert(p.magnitude.limb == c.p.magnitude.limb);
        assert(q.sign == c.q.sign);
        assert(q.magnitude.limb == c.q.magnitude.limb);

        const auto determinant = subtractDyadicProducts(p, q);
        assert(determinant.sign == c.determinant.sign);
        assert(determinant.magnitude.limb == c.determinant.magnitude.limb);

        // These exact determinant cases use the rhs-zero product path.
        assert(c.p.sign != 0);
        assert(c.q.sign == 0);
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
    writefln("%-30s %12.2f ns/op", name,
        cast(double) sw.peek.total!"nsecs" /
        cast(double) iterations);
}

void main()
{
    prepare();
    oracle();

    bench!coordinateBaseline("coordinate baseline");
    bench!coordinateOperations("4 coordinate operations");

    bench!rhsZeroBaseline("coord rhs-zero baseline");
    bench!rhsZeroOperation("coord rhs-zero operation");
    bench!lhsZeroBaseline("coord lhs-zero baseline");
    bench!lhsZeroOperation("coord lhs-zero operation");
    bench!zeroZeroBaseline("coord zero-zero baseline");
    bench!zeroZeroOperation("coord zero-zero operation");
    bench!sameSignGreaterBaseline("coord same-sign > baseline");
    bench!sameSignGreaterOperation("coord same-sign > operation");
    bench!sameSignLessBaseline("coord same-sign < baseline");
    bench!sameSignLessOperation("coord same-sign < operation");
    bench!sameSignEqualBaseline("coord same-sign = baseline");
    bench!sameSignEqualOperation("coord same-sign = operation");

    bench!productBaseline("product baseline");
    bench!productOperations("2 product operations");
    bench!subtractionBaseline("subtraction baseline");
    bench!subtractionOperation("rhs-zero subtraction");

    writefln("coordinate paths: rhs-zero,lhs-zero,zero-zero,same-sign>,same-sign<,same-sign=");
    writefln("path: rhs-sign-zero");
    writefln("observation: matched-full-output");
    writefln("oracle: bit-identical");
    writefln("sink: %s", sink);
}
