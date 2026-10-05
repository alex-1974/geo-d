module geo.internal.fused_coordinate_subtraction_bench;

import std.datetime.stopwatch : StopWatch;
import std.stdio : writefln;

import geo.internal.dyadic :
    SignedDyadicCoordinate,
    SignedDyadicDifference,
    decodeDyadicCoordinate,
    subtractDyadicCoordinates;

import geo.internal.dyadic_fused_candidate :
    subtractDyadicCoordinatesFusedCandidate;

enum size_t iterations = 100_000;
__gshared ulong sink;

private struct Inputs
{
    SignedDyadicCoordinate ax, ay, bx, by, cx, cy;
}

private Inputs[2] determinantCases;

private ulong fingerprint(
    ref const SignedDyadicDifference value,
    size_t salt
)
{
    ulong result =
        cast(ulong)(value.sign + 1) ^
        cast(ulong) salt;

    foreach (limb; value.magnitude.limb)
        result =
            (result * 0x100000001b3UL) ^
            limb;

    return result;
}

private void assertIdentical(
    ref const SignedDyadicDifference lhs,
    ref const SignedDyadicDifference rhs
)
{
    assert(lhs.sign == rhs.sign);
    assert(lhs.magnitude.limb == rhs.magnitude.limb);
}

private void prepare()
{
    determinantCases[0] = Inputs(
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(10.0),
        decodeDyadicCoordinate(10.0),
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(0.0),
        decodeDyadicCoordinate(0.0)
    );

    determinantCases[1] = Inputs(
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(11.0),
        decodeDyadicCoordinate(11.0),
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(1.0),
        decodeDyadicCoordinate(1.0)
    );
}

private void oracle()
{
    /*
     * Independent finite-value corpus spanning zeros, signs, fractions,
     * very small values, and very large values. Every ordered pair is
     * checked against the established implementation.
     */
    immutable double[] values = [
        -1.7976931348623157e308,
        -1.0e300,
        -11.0,
        -1.0,
        -0.5,
        -1.0e-300,
        -5.0e-324,
        -0.0,
        0.0,
        5.0e-324,
        1.0e-300,
        0.5,
        1.0,
        11.0,
        1.0e300,
        1.7976931348623157e308
    ];

    foreach (lhsValue; values)
    {
        const lhs = decodeDyadicCoordinate(lhsValue);

        foreach (rhsValue; values)
        {
            const rhs = decodeDyadicCoordinate(rhsValue);

            const classic =
                subtractDyadicCoordinates(lhs, rhs);

            const fused =
                subtractDyadicCoordinatesFusedCandidate(
                    lhs,
                    rhs
                );

            assertIdentical(classic, fused);
        }
    }

    foreach (ref const v; determinantCases)
    {
        const classicBax =
            subtractDyadicCoordinates(v.bx, v.ax);
        const fusedBax =
            subtractDyadicCoordinatesFusedCandidate(
                v.bx,
                v.ax
            );
        assertIdentical(classicBax, fusedBax);

        const classicBay =
            subtractDyadicCoordinates(v.by, v.ay);
        const fusedBay =
            subtractDyadicCoordinatesFusedCandidate(
                v.by,
                v.ay
            );
        assertIdentical(classicBay, fusedBay);

        const classicCax =
            subtractDyadicCoordinates(v.cx, v.ax);
        const fusedCax =
            subtractDyadicCoordinatesFusedCandidate(
                v.cx,
                v.ax
            );
        assertIdentical(classicCax, fusedCax);

        const classicCay =
            subtractDyadicCoordinates(v.cy, v.ay);
        const fusedCay =
            subtractDyadicCoordinatesFusedCandidate(
                v.cy,
                v.ay
            );
        assertIdentical(classicCay, fusedCay);
    }
}

pragma(inline, false)
private ulong classicFour(size_t i)
{
    ref const v = determinantCases[i & 1];

    const auto bax =
        subtractDyadicCoordinates(v.bx, v.ax);
    const auto bay =
        subtractDyadicCoordinates(v.by, v.ay);
    const auto cax =
        subtractDyadicCoordinates(v.cx, v.ax);
    const auto cay =
        subtractDyadicCoordinates(v.cy, v.ay);

    return fingerprint(bax, i * 4)
        ^ fingerprint(bay, i * 4 + 1)
        ^ fingerprint(cax, i * 4 + 2)
        ^ fingerprint(cay, i * 4 + 3);
}

pragma(inline, false)
private ulong fusedFour(size_t i)
{
    ref const v = determinantCases[i & 1];

    const auto bax =
        subtractDyadicCoordinatesFusedCandidate(
            v.bx,
            v.ax
        );
    const auto bay =
        subtractDyadicCoordinatesFusedCandidate(
            v.by,
            v.ay
        );
    const auto cax =
        subtractDyadicCoordinatesFusedCandidate(
            v.cx,
            v.ax
        );
    const auto cay =
        subtractDyadicCoordinatesFusedCandidate(
            v.cy,
            v.ay
        );

    return fingerprint(bax, i * 4)
        ^ fingerprint(bay, i * 4 + 1)
        ^ fingerprint(cax, i * 4 + 2)
        ^ fingerprint(cay, i * 4 + 3);
}

pragma(inline, false)
private ulong classicSameSign(size_t i)
{
    ref const v = determinantCases[1];

    const auto first =
        (i & 1) == 0
            ? subtractDyadicCoordinates(v.bx, v.ax)
            : subtractDyadicCoordinates(v.by, v.ay);

    return fingerprint(first, i);
}

pragma(inline, false)
private ulong fusedSameSign(size_t i)
{
    ref const v = determinantCases[1];

    const auto first =
        (i & 1) == 0
            ? subtractDyadicCoordinatesFusedCandidate(
                v.bx,
                v.ax
            )
            : subtractDyadicCoordinatesFusedCandidate(
                v.by,
                v.ay
            );

    return fingerprint(first, i);
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

    writefln(
        "%-24s %12.2f ns/op",
        name,
        cast(double) sw.peek.total!"nsecs" /
            cast(double) iterations
    );
}

void main()
{
    prepare();
    oracle();

    bench!classicSameSign("classic same-sign");
    bench!fusedSameSign("fused same-sign");

    bench!classicFour("classic 4 subtracts");
    bench!fusedFour("fused 4 subtracts");

    writefln("oracle: bit-identical");
    writefln("candidate: fused-scan-direct-output");
    writefln("sink: %s", sink);
}
