module intersection_exact_bench;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    tryProperIntersectionExact;

import geo.internal.intersection_round :
    roundIntersectionCoordinate;

import geo.internal.orientation_dyadic :
    orientationDeterminantDyadic;

import geo.point : Point2;
import geo.segment : Segment2;

import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;


enum size_t determinantIterations = 200_000;
enum size_t exactIterations = 100_000;
enum size_t roundingIterations = 200_000;

__gshared ulong sink;

__gshared ExactProperIntersection[2] roundingCases;


private ulong bits(double value)
{
    import std.bitmanip : DoubleRep;

    DoubleRep rep;
    rep.value = value;

    return
        rep.fraction ^
        (cast(ulong) rep.exponent << 52) ^
        (cast(ulong) rep.sign << 63);
}


private void bench(alias operation)(
    string name,
    size_t iterations
)
{
    ulong local;

    foreach (i; 0 .. 1000)
        local += operation(i);

    StopWatch sw;
    sw.start();

    foreach (i; 0 .. iterations)
        local += operation(i);

    sw.stop();

    sink ^= local;

    writefln(
        "%-32s %12.2f ns/op",
        name,
        cast(double) sw.peek.total!"nsecs" /
            cast(double) iterations
    );
}


pragma(inline, false)
private ulong determinant(size_t i)
{
    const double offset =
        cast(double)(i & 1);

    const auto value =
        orientationDeterminantDyadic(
            0.0 + offset,
            10.0,
            10.0 + offset,
            0.0,
            0.0 + offset,
            0.0
        );

    return
        cast(ulong)(value.sign + 1) +
        value.magnitude.limb[0];
}


pragma(inline, false)
private ulong exactConstruction(size_t i)
{
    alias P = Point2!double;
    alias S = Segment2!double;

    const double offset =
        cast(double)(i & 1);

    const S first =
        S(
            P(offset, 0.0),
            P(offset + 10.0, 10.0)
        );

    const S second =
        S(
            P(offset, 10.0),
            P(offset + 10.0, 0.0)
        );

    ExactProperIntersection exact;

    const bool success =
        tryProperIntersectionExact(
            first,
            second,
            exact
        );

    return
        cast(ulong) success +
        exact.denominator.limb[0] +
        exact.xNumerator.magnitude.limb[0] +
        exact.yNumerator.magnitude.limb[0];
}


private void prepareRoundingCases()
{
    alias P = Point2!double;
    alias S = Segment2!double;

    foreach (index; 0 .. roundingCases.length)
    {
        const double offset =
            cast(double) index;

        const S first =
            S(
                P(offset, 0.0),
                P(offset + 1.0, 0.0)
            );

        const S second =
            S(
                P(offset, 1.0),
                P(offset + 1.0, -2.0)
            );

        const bool success =
            tryProperIntersectionExact(
                first,
                second,
                roundingCases[index]
            );

        assert(success);
    }
}


pragma(inline, false)
private ulong roundOnly(size_t i)
{
    const size_t index =
        i & 1;

    return bits(
        roundIntersectionCoordinate(
            roundingCases[index].xNumerator,
            roundingCases[index].denominator
        )
    );
}


void main()
{
    prepareRoundingCases();

    bench!determinant(
        "one exact determinant",
        determinantIterations
    );

    bench!exactConstruction(
        "proper exact construction",
        exactIterations
    );

    bench!roundOnly(
        "one exact round",
        roundingIterations
    );

    writefln("sink: %s", sink);
}
