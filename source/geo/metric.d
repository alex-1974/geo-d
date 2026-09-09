module geo.metric;

import geo.point : Point2;
import geo.scalar : isGeoScalar;
import geo.segment : Segment2;

import std.math.algebraic : hypot;
import std.math.exponential : ilogb, scalbn;
import std.math.traits : isFinite;


/**
 * Floating-point computation type used by elementary metric operations.
 *
 * Storage precision and metric computation precision are deliberately
 * separate:
 *
 *     int     -> double
 *     long    -> double
 *     float   -> double
 *     double  -> double
 *     real    -> real
 */
template MetricScalar(T)
if (isGeoScalar!T)
{
    static if (is(T == real))
        alias MetricScalar = real;
    else
        alias MetricScalar = double;
}


private enum bool isMetricIntegral(T) =
       is(T == int)
    || is(T == long);


private template UnsignedMetricIntegral(T)
if (isMetricIntegral!T)
{
    static if (is(T == int))
        alias UnsignedMetricIntegral = uint;
    else
        alias UnsignedMetricIntegral = ulong;
}


/*
 * Exact unsigned magnitude of a signed integral value.
 *
 * The -(value + 1) formulation avoids overflow for T.min.
 */
private UnsignedMetricIntegral!T unsignedMagnitude(T)(T value)
    pure nothrow @safe @nogc
if (isMetricIntegral!T)
{
    alias U = UnsignedMetricIntegral!T;

    if (value >= 0)
        return cast(U) value;

    return cast(U)(-(value + 1)) + U(1);
}


/*
 * Exact absolute difference between two supported signed integer values.
 *
 * The result can span the complete corresponding unsigned type:
 *
 *     int  -> uint
 *     long -> ulong
 *
 * No signed subtraction overflow occurs.
 */
private UnsignedMetricIntegral!T unsignedDifference(T)(T a, T b)
    pure nothrow @safe @nogc
if (isMetricIntegral!T)
{
    alias U = UnsignedMetricIntegral!T;

    if ((a < 0) != (b < 0))
        return unsignedMagnitude(a) + unsignedMagnitude(b);

    if (a >= b)
        return cast(U)(a - b);

    return cast(U)(b - a);
}


/*
 * Signed component difference in the metric computation type.
 *
 * Semantics:
 *
 *     a - b
 *
 * For integral geometry the magnitude is obtained exactly in the
 * corresponding unsigned type before conversion to MetricScalar.
 * The sign is applied only after that conversion.
 *
 * This avoids both signed integer overflow and the loss of small
 * differences that would occur if large integer coordinates were
 * converted to floating point before subtraction.
 */
private MetricScalar!T signedMetricDifference(T)(T a, T b)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    static if (isMetricIntegral!T)
    {
        if (a == b)
            return M(0);

        const M magnitude =
            cast(M) unsignedDifference(a, b);

        return a > b ? magnitude : -magnitude;
    }
    else
    {
        return cast(M) a - cast(M) b;
    }
}


/*
 * Projection parameter of r onto d.
 *
 * Computes
 *
 *     t = dot(r, d) / dot(d, d)
 *
 * without directly forming potentially overflowing dot products.
 *
 * d and r are scaled independently by powers of two. Because binary
 * scaling is exact, the projection ratio can then be reconstructed
 * with scalbn().
 *
 * Preconditions:
 *
 *     dx, dy, rx and ry are finite;
 *     d is non-zero.
 */
private MetricScalar!T projectionParameter(T)(
    MetricScalar!T dx,
    MetricScalar!T dy,
    MetricScalar!T rx,
    MetricScalar!T ry
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    const M absDx = dx < M(0) ? -dx : dx;
    const M absDy = dy < M(0) ? -dy : dy;
    const M absRx = rx < M(0) ? -rx : rx;
    const M absRy = ry < M(0) ? -ry : ry;

    const M maxD = absDx > absDy ? absDx : absDy;
    const M maxR = absRx > absRy ? absRx : absRy;

    assert(maxD > M(0));

    if (maxR == M(0))
        return M(0);

    const int expD = ilogb(maxD);
    const int expR = ilogb(maxR);

    /*
     * After this scaling, the largest absolute component in each
     * vector lies in [1, 2), so products and sums cannot overflow.
     */
    const M ndx = scalbn(dx, -expD);
    const M ndy = scalbn(dy, -expD);

    const M nrx = scalbn(rx, -expR);
    const M nry = scalbn(ry, -expR);

    const M numerator =
        nrx * ndx + nry * ndy;

    const M denominator =
        ndx * ndx + ndy * ndy;

    const M normalizedRatio =
        numerator / denominator;

    /*
     * Restore the relative scale:
     *
     *     r = nr * 2^expR
     *     d = nd * 2^expD
     *
     * therefore
     *
     *     t = normalizedRatio * 2^(expR-expD)
     */
    return scalbn(
        normalizedRatio,
        expR - expD
    );
}


/**
 * Squared Euclidean distance between two points.
 *
 * Returns:
 *     The squared distance in MetricScalar!T.
 *
 * Integer coordinate geometry is converted to floating-point metric
 * arithmetic after each component difference has been obtained without
 * signed overflow.
 *
 * This operation does not promise exact integral arithmetic. In
 * particular, long-coordinate results may lose precision after
 * conversion to double.
 *
 * Very large floating-point results may overflow to infinity according
 * to normal IEEE floating-point semantics.
 *
 * This function is a metric computation, not a robust exact distance
 * comparison predicate.
 */
MetricScalar!T squaredDistance(T)(
    Point2!T a,
    Point2!T b
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    const M dx = signedMetricDifference(a.x, b.x);
    const M dy = signedMetricDifference(a.y, b.y);

    return dx * dx + dy * dy;
}


/**
 * Euclidean distance between two points.
 *
 * The component differences use the same overflow-safe integer handling
 * as squaredDistance().
 *
 * Distance is calculated directly with hypot rather than as
 *
 *     sqrt(squaredDistance(a, b))
 *
 * so avoidable intermediate square overflow is not introduced.
 */
MetricScalar!T distance(T)(
    Point2!T a,
    Point2!T b
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    const M dx = signedMetricDifference(a.x, b.x);
    const M dy = signedMetricDifference(a.y, b.y);

    return hypot(dx, dy);
}


/**
 * Finds the nearest point on a segment to a point.
 *
 * The result uses MetricScalar!T because the nearest point of an
 * integral segment is not generally representable with integral
 * coordinates.
 *
 * Returns false when:
 *
 * - an input coordinate is NaN or infinite; or
 * - a required metric difference overflows the floating computation
 *   type.
 *
 * On failure, result remains Point2!(MetricScalar!T).init.
 *
 * A degenerate segment returns its single endpoint.
 */
bool tryNearestPoint(T, R)(
    Segment2!T segment,
    Point2!T point,
    out Point2!R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
)
{
    alias M = MetricScalar!T;

    if (!segment.isFinite || !point.isFinite)
        return false;

    const M ax = cast(M) segment.a.x;
    const M ay = cast(M) segment.a.y;

    const M bx = cast(M) segment.b.x;
    const M by = cast(M) segment.b.y;

    const M dx =
        signedMetricDifference(segment.b.x, segment.a.x);

    const M dy =
        signedMetricDifference(segment.b.y, segment.a.y);

    if (!isFinite(dx) || !isFinite(dy))
        return false;

    /*
     * Degenerate segment.
     */
    if (dx == M(0) && dy == M(0))
    {
        result = Point2!M(ax, ay);
        return true;
    }

    const M rx =
        signedMetricDifference(point.x, segment.a.x);

    const M ry =
        signedMetricDifference(point.y, segment.a.y);

    if (!isFinite(rx) || !isFinite(ry))
        return false;

    const M t =
        projectionParameter!T(dx, dy, rx, ry);

    /*
     * Positive overflow of t simply means the projection lies beyond b.
     * Negative overflow means it lies before a.
     */
    if (t <= M(0))
    {
        result = Point2!M(ax, ay);
        return true;
    }

    if (t >= M(1))
    {
        result = Point2!M(bx, by);
        return true;
    }

    if (!isFinite(t))
        return false;

    /*
     * Interpolate from the nearer endpoint. This reduces avoidable
     * cancellation when t is very close to 0 or 1.
     */
    if (t <= M(0.5))
    {
        result = Point2!M(
            ax + t * dx,
            ay + t * dy
        );
    }
    else
    {
        const M fromB = t - M(1);

        result = Point2!M(
            bx + fromB * dx,
            by + fromB * dy
        );
    }

    return result.isFinite;
}


/**
 * Euclidean length of a segment.
 *
 * Uses the same metric computation policy as point-to-point distance.
 *
 * In particular:
 *
 * - integer coordinate differences are obtained without signed overflow;
 * - int, long and float geometry compute in double;
 * - real geometry computes in real;
 * - hypot is used indirectly through distance().
 */
MetricScalar!T segmentLength(T)(Segment2!T segment)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    return distance(segment.a, segment.b);
}


@safe unittest
{
    /*
     * Metric result policy.
     */
    static assert(is(MetricScalar!int == double));
    static assert(is(MetricScalar!long == double));
    static assert(is(MetricScalar!float == double));
    static assert(is(MetricScalar!double == double));
    static assert(is(MetricScalar!real == real));


    /*
     * Signed metric differences preserve direction without signed
     * integer subtraction overflow.
     */
    assert(signedMetricDifference!int(5, 2) == 3.0);
    assert(signedMetricDifference!int(2, 5) == -3.0);
    assert(signedMetricDifference!int(5, 5) == 0.0);

    assert(
        signedMetricDifference!long(
            long.max,
            long.max - 1
        ) == 1.0
    );

    assert(
        signedMetricDifference!long(
            long.max - 1,
            long.max
        ) == -1.0
    );

    assert(
        signedMetricDifference!long(
            long.min + 1,
            long.min
        ) == 1.0
    );

    assert(
        signedMetricDifference!long(
            long.min,
            long.min + 1
        ) == -1.0
    );

    /*
     * Crossing zero also avoids signed overflow.
     */
    assert(
        signedMetricDifference!long(1, -1) == 2.0
    );

    assert(
        signedMetricDifference!long(-1, 1) == -2.0
    );

    assert(
        signedMetricDifference!long(
            long.max,
            long.min
        ) > 0.0
    );

    assert(
        signedMetricDifference!long(
            long.min,
            long.max
        ) < 0.0
    );


    /*
     * Basic metric behaviour.
     */
    alias P = Point2!double;

    auto a = P(0.0, 0.0);
    auto b = P(3.0, 4.0);

    assert(squaredDistance(a, b) == 25.0);
    assert(squaredDistance(b, a) == 25.0);

    assert(distance(a, b) == 5.0);
    assert(distance(b, a) == 5.0);

    assert(distance(a, a) == 0.0);


    /*
     * float storage deliberately computes in double.
     */
    static assert(
        is(typeof(distance(
            Point2!float.init,
            Point2!float.init
        )) == double)
    );

    static assert(
        is(typeof(squaredDistance(
            Point2!float.init,
            Point2!float.init
        )) == double)
    );


    /*
     * real storage retains real metric computation.
     */
    static assert(
        is(typeof(distance(
            Point2!real.init,
            Point2!real.init
        )) == real)
    );


    /*
     * Integer extremes must not overflow during component subtraction.
     */
    alias PI = Point2!int;

    auto intLo = PI(int.min, int.min);
    auto intHi = PI(int.max, int.max);

    assert(distance(intLo, intHi) > 0.0);
    assert(squaredDistance(intLo, intHi) > 0.0);


    /*
     * Most importantly, integer subtraction occurs before conversion
     * without destroying small differences between very large values.
     *
     * Casting both long coordinates to double before subtraction would
     * incorrectly turn this distance into zero.
     */
    alias PL = Point2!long;

    auto largeA = PL(long.max, 0);
    auto largeB = PL(long.max - 1, 0);

    assert(distance(largeA, largeB) == 1.0);
    assert(squaredDistance(largeA, largeB) == 1.0);


    /*
     * Complete signed-long span is handled without signed overflow.
     *
     * Precision after conversion to double is intentionally not claimed
     * to be exact.
     */
    auto longLo = PL(long.min, 0);
    auto longHi = PL(long.max, 0);

    auto extremeDistance = distance(longLo, longHi);

    assert(extremeDistance > 0.0);
    assert(extremeDistance != double.infinity);


    /*
     * Non-finite floating values follow IEEE/Phobos metric semantics.
     */
    auto infPoint = P(double.infinity, 0.0);

    assert(distance(a, infPoint) == double.infinity);
    assert(squaredDistance(a, infPoint) == double.infinity);

    auto nanPoint = P(double.nan, 0.0);

    assert(distance(a, nanPoint) != distance(a, nanPoint));
    assert(squaredDistance(a, nanPoint) !=
           squaredDistance(a, nanPoint));

    /*
     * Nearest point on a segment.
     */
    {
        alias S = Segment2!double;

        auto horizontal = S(
            Point2!double(0.0, 0.0),
            Point2!double(10.0, 0.0)
        );

        Point2!double nearest;

        assert(tryNearestPoint(
            horizontal,
            Point2!double(3.0, 4.0),
            nearest
        ));

        assert(nearest == Point2!double(3.0, 0.0));


        /*
         * Projection before and after the segment clamps to endpoints.
         */
        assert(tryNearestPoint(
            horizontal,
            Point2!double(-5.0, 2.0),
            nearest
        ));

        assert(nearest == Point2!double(0.0, 0.0));

        assert(tryNearestPoint(
            horizontal,
            Point2!double(15.0, 2.0),
            nearest
        ));

        assert(nearest == Point2!double(10.0, 0.0));


        /*
         * Degenerate segment.
         */
        auto degenerate = S(
            Point2!double(7.0, -3.0),
            Point2!double(7.0, -3.0)
        );

        assert(tryNearestPoint(
            degenerate,
            Point2!double(100.0, 100.0),
            nearest
        ));

        assert(nearest == Point2!double(7.0, -3.0));


        /*
         * Integral geometry returns floating metric geometry.
         */
        Point2!double integerNearest;

        assert(tryNearestPoint(
            Segment2!int(
                Point2!int(0, 0),
                Point2!int(10, 0)
            ),
            Point2!int(3, 4),
            integerNearest
        ));

        assert(integerNearest == Point2!double(3.0, 0.0));

        static assert(is(typeof(integerNearest) == Point2!double));


        /*
         * Large dot products that would overflow in the naive formula
         *
         *     dot(r, d) / dot(d, d)
         *
         * remain usable after exponent scaling.
         */
        auto huge = S(
            Point2!double(0.0, 0.0),
            Point2!double(1.0e300, 1.0e300)
        );

        assert(tryNearestPoint(
            huge,
            Point2!double(5.0e299, 6.0e299),
            nearest
        ));

        assert(nearest.x > 5.49e299);
        assert(nearest.x < 5.51e299);
        assert(nearest.y > 5.49e299);
        assert(nearest.y < 5.51e299);


        /*
         * Very different vector scales may make the unclamped
         * projection parameter overflow, but endpoint clamping remains
         * well-defined.
         */
        auto tiny = S(
            Point2!double(0.0, 0.0),
            Point2!double(1.0e-300, 0.0)
        );

        assert(tryNearestPoint(
            tiny,
            Point2!double(1.0e300, 0.0),
            nearest
        ));

        assert(nearest == Point2!double(1.0e-300, 0.0));


        /*
         * Large long coordinates retain exact component differences
         * before conversion to double.
         *
         * The spacing is chosen large enough to remain distinguishable
         * in the resulting double coordinates.
         */
        const long base = long.max - 8192;

        assert(tryNearestPoint(
            Segment2!long(
                Point2!long(base, 0),
                Point2!long(base + 8192, 0)
            ),
            Point2!long(base + 4096, 100),
            integerNearest
        ));

        assert(integerNearest.y == 0.0);


        /*
         * Non-finite input is outside the operation's domain.
         */
        assert(!tryNearestPoint(
            horizontal,
            Point2!double(double.nan, 0.0),
            nearest
        ));

        assert(nearest == Point2!double.init);

        assert(!tryNearestPoint(
            S(
                Point2!double(0.0, 0.0),
                Point2!double(double.infinity, 0.0)
            ),
            Point2!double(1.0, 1.0),
            nearest
        ));

        assert(nearest == Point2!double.init);


        /*
         * Finite endpoints whose component difference itself exceeds
         * the MetricScalar range are conservatively rejected.
         */
        assert(!tryNearestPoint(
            S(
                Point2!double(-double.max, 0.0),
                Point2!double(double.max, 0.0)
            ),
            Point2!double(0.0, 1.0),
            nearest
        ));

        assert(nearest == Point2!double.init);
    }


    /*
     * Segment length is point distance between the stored endpoints.
     */
    {
        import geo.segment : Segment2;

        auto segment = Segment2!double(
            Point2!double(0.0, 0.0),
            Point2!double(3.0, 4.0)
        );

        assert(segmentLength(segment) == 5.0);

        auto degenerate = Segment2!int(
            Point2!int(7, -3),
            Point2!int(7, -3)
        );

        assert(segmentLength(degenerate) == 0.0);

        /*
         * Integer differences retain the same protection as distance().
         */
        auto large = Segment2!long(
            Point2!long(long.max, 0),
            Point2!long(long.max - 1, 0)
        );

        assert(segmentLength(large) == 1.0);

        static assert(
            is(typeof(segmentLength(
                Segment2!float.init
            )) == double)
        );

        static assert(
            is(typeof(segmentLength(
                Segment2!real.init
            )) == real)
        );
    }

}
