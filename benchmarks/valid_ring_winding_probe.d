module geo.internal.valid_ring_winding_probe;

import geo.linear_ring_view : LinearRing2View;
import geo.orientation : Orientation2, orientation;
import geo.point : Point2;
import geo.internal.polygon_union_input : exactRingOrientationSign;

import std.algorithm.mutation : reverse;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import std.exception : enforce;
import std.meta : AliasSeq;
import std.stdio : writefln, writeln;

__gshared ulong windingSink;

private int extremumValidRingOrientationSign(T)(
    scope const(LinearRing2View!T) ring
)
    pure nothrow @safe @nogc
{
    assert(ring.length >= 3);

    size_t highest = 0;

    foreach (i; 1 .. ring.length)
    {
        if (ring[i].y > ring[highest].y)
            highest = i;
    }

    const size_t previousIndex =
        highest == 0
            ? ring.length - 1
            : highest - 1;

    const size_t nextIndex =
        highest + 1 == ring.length
            ? 0
            : highest + 1;

    const auto previous = ring[previousIndex];
    const auto high = ring[highest];
    const auto next = ring[nextIndex];

    assert(previous != high);
    assert(next != high);

    const Orientation2 turn =
        orientation(
            previous,
            high,
            next
        );

    if (turn == Orientation2.left)
        return 1;

    if (turn == Orientation2.right)
        return -1;

    /*
     * A valid simple ring can have a flat extremal chain. At the selected
     * highest vertex the traversal direction across that horizontal support
     * determines winding exactly.
     */
    assert(previous.y == high.y);
    assert(next.y == high.y);
    assert(previous.x != next.x);

    return previous.x > next.x ? 1 : -1;
}

private Point2!T[] subdividedRectangle(T)(size_t subdivisions)
{
    alias P = Point2!T;

    P[] ring;

    foreach (j; 0 .. subdivisions)
        ring ~= P(cast(T)(4 * j), 0);

    foreach (j; 0 .. subdivisions)
        ring ~= P(
            cast(T)(4 * subdivisions),
            cast(T)(4 * j)
        );

    foreach (j; 0 .. subdivisions)
        ring ~= P(
            cast(T)(4 * (subdivisions - j)),
            cast(T)(4 * subdivisions)
        );

    foreach (j; 0 .. subdivisions)
        ring ~= P(
            0,
            cast(T)(4 * (subdivisions - j))
        );

    return ring;
}

private void checkRing(T)(scope Point2!T[] points)
{
    auto ring =
        LinearRing2View!T(
            points
        );

    const int exact =
        exactRingOrientationSign(
            ring
        );

    const int extremum =
        extremumValidRingOrientationSign(
            ring
        );

    enforce(exact != 0);
    enforce(extremum == exact);

    auto reversed =
        points.dup;

    reverse(reversed);

    auto reverseRing =
        LinearRing2View!T(
            reversed
        );

    enforce(
        exactRingOrientationSign(
            reverseRing
        ) == -exact
    );

    enforce(
        extremumValidRingOrientationSign(
            reverseRing
        ) == -exact
    );
}

private void equivalenceMatrix(T)()
{
    alias P = Point2!T;

    foreach (subdivisions; [1, 2, 4, 16, 64, 256])
    {
        auto points =
            subdividedRectangle!T(
                subdivisions
            );

        checkRing(points);
    }

    P[] concaveU = [
        P(0, 0),
        P(12, 0),
        P(12, 12),
        P(9, 12),
        P(9, 4),
        P(3, 4),
        P(3, 12),
        P(0, 12),
    ];

    checkRing(concaveU);

    P[] flatTop = [
        P(0, 0),
        P(12, 0),
        P(12, 8),
        P(10, 12),
        P(8, 12),
        P(6, 12),
        P(4, 12),
        P(2, 12),
        P(0, 8),
    ];

    checkRing(flatTop);

    P[] skew = [
        P(-11, -7),
        P(17, -5),
        P(23, 9),
        P(8, 21),
        P(-4, 18),
        P(-19, 3),
    ];

    checkRing(skew);
}

private void floatingExtremes(T)()
if (is(T == float) || is(T == double))
{
    alias P = Point2!T;

    const T tiny =
        T.min_normal *
        cast(T) 0.5;

    P[] tinyTriangle = [
        P(0, 0),
        P(tiny, 0),
        P(0, tiny),
    ];

    checkRing(tinyTriangle);

    const T large =
        T.max / cast(T) 16;

    P[] largeDiamond = [
        P(-large, 0),
        P(0, -large),
        P(large, 0),
        P(0, large),
    ];

    checkRing(largeDiamond);
}

private ulong timeExact(T)(
    scope const(LinearRing2View!T) ring,
    size_t iterations
)
{
    StopWatch watch;
    watch.start();

    foreach (i; 0 .. iterations)
    {
        windingSink += cast(ulong)(
            exactRingOrientationSign(
                ring
            ) + 1
        );
    }

    watch.stop();

    return cast(ulong)
        watch.peek.total!"nsecs";
}

private ulong timeExtremum(T)(
    scope const(LinearRing2View!T) ring,
    size_t iterations
)
{
    StopWatch watch;
    watch.start();

    foreach (i; 0 .. iterations)
    {
        windingSink += cast(ulong)(
            extremumValidRingOrientationSign(
                ring
            ) + 1
        );
    }

    watch.stop();

    return cast(ulong)
        watch.peek.total!"nsecs";
}

private void benchmark(T)(
    size_t subdivisions,
    size_t rounds,
    size_t iterations
)
{
    auto points =
        subdividedRectangle!T(
            subdivisions
        );

    auto ring =
        LinearRing2View!T(
            points
        );

    enforce(
        exactRingOrientationSign(ring) ==
        extremumValidRingOrientationSign(ring)
    );

    foreach (round; 0 .. rounds)
    {
        const ulong exactNs =
            timeExact(
                ring,
                iterations
            );

        const ulong extremumNs =
            timeExtremum(
                ring,
                iterations
            );

        writefln(
            "sample,%s,%s,%s,%s,%s,%s",
            T.stringof,
            subdivisions,
            round,
            iterations,
            exactNs,
            extremumNs
        );
    }
}

void main(string[] args)
{
    static foreach (T; AliasSeq!(int, long, float, double))
    {
        equivalenceMatrix!T();

        static if (
            is(T == float) ||
            is(T == double)
        )
        {
            floatingExtremes!T();
        }
    }

    if (args.length == 1)
    {
        writeln("equivalence,pass");
        return;
    }

    enforce(args.length == 5);

    const string scalar = args[1];
    const size_t subdivisions = args[2].to!size_t;
    const size_t rounds = args[3].to!size_t;
    const size_t iterations = args[4].to!size_t;

    writeln(
        "sample_header,scalar,subdivisions,round,iterations,exact_ns,extremum_ns"
    );

    if (scalar == "int")
        benchmark!int(subdivisions, rounds, iterations);
    else if (scalar == "long")
        benchmark!long(subdivisions, rounds, iterations);
    else if (scalar == "float")
        benchmark!float(subdivisions, rounds, iterations);
    else if (scalar == "double")
        benchmark!double(subdivisions, rounds, iterations);
    else
        enforce(false, "unknown scalar");

    writefln("sink,%s", windingSink);
}
