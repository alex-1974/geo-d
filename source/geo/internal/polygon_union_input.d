module geo.internal.polygon_union_input;

import geo.internal.area_exact :
    SignedAreaAccumulator,
    addAreaDeterminant;

import geo.internal.orientation_dyadic :
    orientationDeterminantDyadic;

import geo.linear_ring_view :
    LinearRing2View;

import geo.polygon_view :
    Polygon2View;

import geo.segment :
    Segment2;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact input-boundary provenance for the P1 polygon-union overlay.
 *
 * Polygon ring roles are structural. Ring traversal direction is preserved
 * from the caller. The exact signed ring determinant establishes whether the
 * polygon interior lies on the stored segment's left or right side.
 */


private enum bool isPolygonUnionInputScalar(T) =
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double);


/*
 * One represented polygon boundary source edge.
 *
 * operandMask contains exactly one operand bit.
 *
 * interiorOnSourceLeft is true exactly when the polygon interior adjacent to
 * this ring boundary lies on the left of segment.a -> segment.b.
 */
struct ExactPolygonBoundaryEdge(T)
if (isPolygonUnionInputScalar!T)
{
    Segment2!T segment;

    ubyte operandMask;

    bool interiorOnSourceLeft;
}


/*
 * Computes the exact sign of twice the algebraic area of one finite ring.
 *
 * Returns:
 *     -1 clockwise
 *      0 algebraically degenerate
 *      1 counter-clockwise
 *
 * No binary64 area is constructed.
 */
int exactRingOrientationSign(T)(
    scope const(LinearRing2View!T) ring
)
    pure nothrow @safe @nogc
if (isPolygonUnionInputScalar!T)
{
    SignedAreaAccumulator accumulator;

    if (ring.length == 0)
        return 0;

    foreach (i; 0 .. ring.segmentCount)
    {
        const auto edge =
            ring.segment(i);

        static if (
            is(T == float) ||
            is(T == double)
        )
        {
            assert(edge.isFinite);
        }

        const auto determinant =
            orientationDeterminantDyadic(
                cast(T) 0,
                cast(T) 0,
                edge.a.x,
                edge.a.y,
                edge.b.x,
                edge.b.y
            );

        addAreaDeterminant(
            accumulator,
            determinant
        );
    }

    return accumulator.sign;
}


/*
 * Counts represented source edges in one polygon.
 *
 * Returns false only on size_t overflow.
 */
bool tryPolygonBoundaryEdgeCount(T)(
    scope const(Polygon2View!T) polygon,
    out size_t count
)
    pure nothrow @safe @nogc
if (isPolygonUnionInputScalar!T)
{
    count = 0;

    foreach (ringIndex; 0 .. polygon.length)
    {
        const size_t ringEdges =
            polygon[ringIndex].segmentCount;

        if (
            count >
            size_t.max -
            ringEdges
        )
        {
            count = 0;
            return false;
        }

        count += ringEdges;
    }

    return true;
}


/*
 * Extracts exact source-boundary provenance from one already valid polygon.
 *
 * The caller supplies one exact operand bit.
 *
 * Preconditions:
 * - non-empty rings satisfy the existing polygon validation contract;
 * - every non-empty valid ring has non-zero exact algebraic area;
 * - floating coordinates are finite.
 *
 * Ring-role / orientation rule:
 *
 * exterior CCW -> polygon interior is left
 * exterior CW  -> polygon interior is right
 * hole CCW     -> polygon interior is right
 * hole CW      -> polygon interior is left
 *
 * Equivalently:
 *
 *     interiorOnSourceLeft = counterClockwise != isHole
 *
 * Empty polygon input produces zero source edges.
 */
bool buildExactPolygonBoundaryEdges(T)(
    scope const(Polygon2View!T) polygon,
    ubyte operandMask,
    scope ExactPolygonBoundaryEdge!T[] destination,
    out size_t count
)
    pure nothrow @safe @nogc
if (isPolygonUnionInputScalar!T)
{
    count = 0;

    if (
        operandMask == 0 ||
        (
            operandMask &
            (operandMask - 1)
        ) != 0
    )
    {
        return false;
    }

    size_t required;

    if (
        !tryPolygonBoundaryEdgeCount(
            polygon,
            required
        ) ||
        destination.length < required
    )
    {
        return false;
    }

    foreach (ringIndex; 0 .. polygon.length)
    {
        const auto ring =
            polygon[ringIndex];

        const int orientationSign =
            exactRingOrientationSign(
                ring
            );

        /*
         * The production caller validates polygons before extraction.
         * A non-empty zero-area ring therefore indicates a violated internal
         * precondition rather than a geometry-repair opportunity.
         */
        if (
            ring.length != 0 &&
            orientationSign == 0
        )
        {
            count = 0;
            return false;
        }

        const bool counterClockwise =
            orientationSign > 0;

        const bool isHole =
            ringIndex != 0;

        const bool interiorOnSourceLeft =
            counterClockwise !=
            isHole;

        foreach (edgeIndex; 0 .. ring.segmentCount)
        {
            const auto edge =
                ring.segment(
                    edgeIndex
                );

            if (edge.a == edge.b)
            {
                count = 0;
                return false;
            }

            destination[count++] =
                ExactPolygonBoundaryEdge!T(
                    edge,
                    operandMask,
                    interiorOnSourceLeft
                );
        }
    }

    assert(count == required);

    return true;
}


@safe unittest
{
    import geo.point :
        Point2;

    alias P = Point2!int;
    alias R = LinearRing2View!int;

    P[4] ccwPoints = [
        P(0, 0),
        P(4, 0),
        P(4, 3),
        P(0, 3),
    ];

    P[4] cwPoints = [
        P(0, 0),
        P(0, 3),
        P(4, 3),
        P(4, 0),
    ];

    assert(
        exactRingOrientationSign(
            R(ccwPoints[])
        ) == 1
    );

    assert(
        exactRingOrientationSign(
            R(cwPoints[])
        ) == -1
    );
}


@safe unittest
{
    import geo.point :
        Point2;

    /*
     * Ring orientation sign remains exact when the correctly-rounded
     * binary64 signed area would underflow to signed zero.
     */
    alias P = Point2!double;
    alias R = LinearRing2View!double;

    import std.math :
        nextUp;

    const double tiny =
        double.min_normal *
        0x1p-52;

    const double next =
        nextUp(tiny);

    P[3] positive = [
        P(0.0, 0.0),
        P(tiny, 0.0),
        P(0.0, tiny),
    ];

    P[3] negative = [
        positive[0],
        positive[2],
        positive[1],
    ];

    /*
     * Keep an additional representable finite value live in this fixture so
     * the test also exercises non-normal dyadic decoding independently of
     * any area rounding.
     */
    assert(next > tiny);

    assert(
        exactRingOrientationSign(
            R(positive[])
        ) == 1
    );

    assert(
        exactRingOrientationSign(
            R(negative[])
        ) == -1
    );
}


@safe unittest
{
    import geo.point :
        Point2;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;
    alias E = ExactPolygonBoundaryEdge!int;

    enum ubyte operandA = 1;


    /*
     * Exterior and hole may use the same CCW storage winding. Their polygon
     * interior sides are opposite because ring role is structural.
     */
    P[4] exteriorPoints = [
        P(0, 0),
        P(10, 0),
        P(10, 10),
        P(0, 10),
    ];

    P[4] holePoints = [
        P(2, 2),
        P(4, 2),
        P(4, 4),
        P(2, 4),
    ];

    R[2] rings = [
        R(exteriorPoints[]),
        R(holePoints[]),
    ];

    const G polygon =
        G(rings[]);

    E[8] edges;
    size_t count;

    assert(
        buildExactPolygonBoundaryEdges(
            polygon,
            operandA,
            edges[],
            count
        )
    );

    assert(count == 8);

    foreach (edge; edges[0 .. 4])
    {
        assert(edge.operandMask == operandA);
        assert(edge.interiorOnSourceLeft);
    }

    foreach (edge; edges[4 .. 8])
    {
        assert(edge.operandMask == operandA);
        assert(!edge.interiorOnSourceLeft);
    }
}


@safe unittest
{
    import geo.point :
        Point2;

    alias P = Point2!int;
    alias R = LinearRing2View!int;
    alias G = Polygon2View!int;
    alias E = ExactPolygonBoundaryEdge!int;

    enum ubyte operandB = 2;


    /*
     * Clockwise exterior stores polygon interior on the right; clockwise hole
     * stores polygon interior on the left.
     */
    P[4] exteriorPoints = [
        P(0, 0),
        P(0, 10),
        P(10, 10),
        P(10, 0),
    ];

    P[4] holePoints = [
        P(2, 2),
        P(2, 4),
        P(4, 4),
        P(4, 2),
    ];

    R[2] rings = [
        R(exteriorPoints[]),
        R(holePoints[]),
    ];

    const G polygon =
        G(rings[]);

    E[8] edges;
    size_t count;

    assert(
        buildExactPolygonBoundaryEdges(
            polygon,
            operandB,
            edges[],
            count
        )
    );

    assert(count == 8);

    foreach (edge; edges[0 .. 4])
        assert(!edge.interiorOnSourceLeft);

    foreach (edge; edges[4 .. 8])
        assert(edge.interiorOnSourceLeft);
}
