module geo.internal.polygon_union_exact;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    decodeDyadicCoordinate;

import geo.internal.exact_coordinate :
    SignedExactCoordinateNumerator,
    compareExactCoordinates;

import geo.internal.intersection_exact :
    ExactProperIntersection,
    tryProperIntersectionExact;

import geo.point :
    Point2;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact point representation used by the polygon-union overlay core.
 *
 * Input vertices and constructed proper-intersection events are lifted into
 * the same rational coordinate model:
 *
 *     numerator
 *     ----------- * 2^-1074
 *     denominator
 *
 * with one positive denominator shared by x and y.
 *
 * Rounded construction coordinates are deliberately absent here. Arrangement
 * identity and edge-event ordering are exact.
 */


private enum bool isPolygonUnionExactScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/*
 * Exact internal arrangement point.
 *
 * This type is implementation-only. It is not a public exact-geometry scalar
 * or consumer-visible polygon coordinate.
 */
struct ExactOverlayPoint
{
    SignedExactCoordinateNumerator xNumerator;
    SignedExactCoordinateNumerator yNumerator;

    DyadicProductMagnitude denominator;
}


/*
 * Lifts one represented finite coordinate into the established exact rational
 * construction domain with denominator 1.
 *
 * decodeDyadicCoordinate represents every supported input exactly in the
 * common 2^-1074 scale. Its 66-limb magnitude is embedded without arithmetic
 * into the established 198-limb exact-coordinate numerator.
 */
private SignedExactCoordinateNumerator liftRepresentedCoordinate(T)(
    T value
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    const auto coordinate =
        decodeDyadicCoordinate(value);

    SignedExactCoordinateNumerator result;
    result.sign = coordinate.sign;

    foreach (i, limb; coordinate.magnitude.limb)
    {
        result.magnitude.limb[i] =
            limb;
    }

    return result;
}


/*
 * Lifts one represented input point exactly into overlay space.
 */
ExactOverlayPoint exactOverlayPoint(T)(
    Point2!T point
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    ExactOverlayPoint result;

    result.xNumerator =
        liftRepresentedCoordinate(
            point.x
        );

    result.yNumerator =
        liftRepresentedCoordinate(
            point.y
        );

    result.denominator.limb[0] = 1;

    return result;
}


/*
 * Re-expresses an already exact proper-intersection event as an overlay point.
 *
 * No arithmetic or normalization is needed because ExactProperIntersection
 * already uses the same numerator/denominator model.
 */
ExactOverlayPoint exactOverlayPoint(
    ref const ExactProperIntersection intersection
)
    pure nothrow @safe @nogc
{
    return
        ExactOverlayPoint(
            intersection.xNumerator,
            intersection.yNumerator,
            intersection.denominator
        );
}


/*
 * Exact lexicographic ordering of arrangement points.
 *
 * Raw unreduced numerator/denominator storage is not used as identity.
 */
int compareExactOverlayPoints(
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
{
    const int xComparison =
        compareExactCoordinates(
            lhs.xNumerator,
            lhs.denominator,
            rhs.xNumerator,
            rhs.denominator
        );

    if (xComparison != 0)
        return xComparison;

    return
        compareExactCoordinates(
            lhs.yNumerator,
            lhs.denominator,
            rhs.yNumerator,
            rhs.denominator
        );
}


/*
 * Exact arrangement-point equality.
 */
bool exactOverlayPointsEqual(
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
{
    return
        compareExactOverlayPoints(
            lhs,
            rhs
        ) == 0;
}


/*
 * Orders exact overlay events along one represented non-degenerate source
 * segment from source.a toward source.b.
 *
 * A non-vertical segment is strictly monotone in x. A vertical segment is
 * strictly monotone in y. Therefore exact coordinate comparison orders all
 * points known to lie on the segment without constructing a floating-point
 * segment parameter.
 *
 * Returns -1, 0, or 1 according to source.a -> source.b order.
 */
int compareExactOverlayPointsAlongSegment(T)(
    Segment2!T source,
    ref const ExactOverlayPoint lhs,
    ref const ExactOverlayPoint rhs
)
    pure nothrow @safe @nogc
if (isPolygonUnionExactScalar!T)
{
    assert(source.a != source.b);

    int comparison;

    if (source.a.x != source.b.x)
    {
        comparison =
            compareExactCoordinates(
                lhs.xNumerator,
                lhs.denominator,
                rhs.xNumerator,
                rhs.denominator
            );

        return
            source.a.x < source.b.x
                ? comparison
                : -comparison;
    }

    comparison =
        compareExactCoordinates(
            lhs.yNumerator,
            lhs.denominator,
            rhs.yNumerator,
            rhs.denominator
        );

    return
        source.a.y < source.b.y
            ? comparison
            : -comparison;
}


@safe unittest
{
    /*
     * Represented integral and binary64 points with the same mathematical
     * value receive the same exact overlay identity.
     */
    const integerPoint =
        exactOverlayPoint(
            Point2!int(
                1,
                -2
            )
        );

    const floatingPoint =
        exactOverlayPoint(
            Point2!double(
                1.0,
                -2.0
            )
        );

    assert(
        exactOverlayPointsEqual(
            integerPoint,
            floatingPoint
        )
    );
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;

    const source =
        S(
            P(0, 0),
            P(10, 0)
        );

    const crossing =
        S(
            P(5, -3),
            P(5, 7)
        );

    ExactProperIntersection exact;

    assert(
        tryProperIntersectionExact(
            source,
            crossing,
            exact
        )
    );

    const auto sourceA =
        exactOverlayPoint(
            source.a
        );

    const auto sourceB =
        exactOverlayPoint(
            source.b
        );

    const auto event =
        exactOverlayPoint(
            exact
        );

    const auto representedCrossing =
        exactOverlayPoint(
            P(5, 0)
        );

    assert(
        exactOverlayPointsEqual(
            event,
            representedCrossing
        )
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            source,
            sourceA,
            event
        ) < 0
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            source,
            event,
            sourceB
        ) < 0
    );

    const auto reversed =
        S(
            source.b,
            source.a
        );

    assert(
        compareExactOverlayPointsAlongSegment(
            reversed,
            sourceA,
            event
        ) > 0
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            reversed,
            event,
            sourceB
        ) > 0
    );
}


@safe unittest
{
    alias P = Point2!int;
    alias S = Segment2!int;

    const vertical =
        S(
            P(3, -5),
            P(3, 8)
        );

    const lower =
        exactOverlayPoint(
            P(3, -2)
        );

    const upper =
        exactOverlayPoint(
            P(3, 7)
        );

    assert(
        compareExactOverlayPointsAlongSegment(
            vertical,
            lower,
            upper
        ) < 0
    );

    const reversed =
        S(
            vertical.b,
            vertical.a
        );

    assert(
        compareExactOverlayPointsAlongSegment(
            reversed,
            lower,
            upper
        ) > 0
    );
}


@safe unittest
{
    /*
     * Proper intersections with different raw denominators but the same
     * mathematical point compare equal after promotion to overlay points.
     */
    alias P = Point2!int;
    alias S = Segment2!int;

    const source =
        S(
            P(0, 0),
            P(10, 0)
        );

    const shortCrossing =
        S(
            P(5, -1),
            P(5, 1)
        );

    const longCrossing =
        S(
            P(5, -3),
            P(5, 7)
        );

    ExactProperIntersection first;
    ExactProperIntersection second;

    assert(
        tryProperIntersectionExact(
            source,
            shortCrossing,
            first
        )
    );

    assert(
        tryProperIntersectionExact(
            source,
            longCrossing,
            second
        )
    );

    assert(
        first.denominator.limb !=
        second.denominator.limb
    );

    const auto firstPoint =
        exactOverlayPoint(
            first
        );

    const auto secondPoint =
        exactOverlayPoint(
            second
        );

    assert(
        exactOverlayPointsEqual(
            firstPoint,
            secondPoint
        )
    );

    assert(
        compareExactOverlayPointsAlongSegment(
            source,
            firstPoint,
            secondPoint
        ) == 0
    );
}
