/**
 * Signed and polygon area operations.
 */
module geo.area;

import geo.internal.area_exact :
    SignedAreaAccumulator,
    SignedPolygonAreaAccumulator,
    addAreaDeterminant,
    addPolygonAreaMagnitude;

import geo.internal.dyadic :
    SignedDyadicDifference,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import geo.internal.dyadic_round :
    roundSignedDyadicToBinary64;

import geo.linear_ring_view :
    LinearRingView;

import geo.polygon_view :
    PolygonView;


/**
 * Result scalar used by signed planar area.
 *
 * Signed area currently supports:
 *
 *     int
 *     long
 *     float
 *     double
 *
 * and returns binary64 for all supported input scalars.
 *
 * real is deliberately deferred until geo-d has a platform-aware exact
 * backend for that scalar.
 */
template AreaScalar(T)
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    alias AreaScalar = double;
}


/*
 * Exact 2D determinant of two already-decoded relative vectors.
 *
 * Both vector components are represented in units of 2^-1074, therefore
 * the returned determinant is represented in units of 2^-2148.
 */
private SignedDyadicProduct determinantFromDifferences(
    ref const SignedDyadicDifference firstX,
    ref const SignedDyadicDifference firstY,
    ref const SignedDyadicDifference secondX,
    ref const SignedDyadicDifference secondY
)
    pure nothrow @safe @nogc
{
    const auto p =
        multiplyDyadicDifferences(
            firstX,
            secondY
        );

    const auto q =
        multiplyDyadicDifferences(
            firstY,
            secondX
        );

    return subtractDyadicProducts(
        p,
        q
    );
}


/*
 * Computes the exact determinant sum of a linear ring.
 *
 * The returned accumulator represents twice the signed area in units of
 * 2^-2148.
 *
 * Returns false when any stored coordinate is non-finite. On false,
 * accumulator is reset to canonical zero.
 */
private bool tryExactRingTwiceArea(T)(
    scope const(LinearRingView!T) ring,
    out SignedAreaAccumulator accumulator
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    /*
     * out initializes accumulator to canonical zero on entry.
     *
     * Empty rings therefore already have the required exact result.
     */
    if (ring.length == 0)
        return true;


    /*
     * Check vertices as they enter the rolling fan rather than scanning
     * the complete ring in a separate pass.
     */
    const auto origin =
        ring[0];

    if (!origin.isFinite)
        return false;

    if (ring.length == 1)
        return true;


    const auto first =
        ring[1];

    if (!first.isFinite)
        return false;

    if (ring.length == 2)
        return true;


    /*
     * Decode the fan origin once.
     */
    const auto originX =
        decodeDyadicCoordinate(
            origin.x
        );

    const auto originY =
        decodeDyadicCoordinate(
            origin.y
        );


    /*
     * Build the first relative vector once:
     *
     *     p1 - p0
     */
    const auto firstXCoordinate =
        decodeDyadicCoordinate(
            first.x
        );

    const auto firstYCoordinate =
        decodeDyadicCoordinate(
            first.y
        );

    auto previousX =
        subtractDyadicCoordinates(
            firstXCoordinate,
            originX
        );

    auto previousY =
        subtractDyadicCoordinates(
            firstYCoordinate,
            originY
        );


    /*
     * Rolling exact triangle fan.
     *
     * For each new vertex only that vertex is decoded. Its relative
     * vector is then paired with the previous relative vector:
     *
     *     det(
     *         p_i     - p0,
     *         p_(i+1) - p0
     *     )
     *
     * This preserves the exact ADR-0008 semantics while avoiding repeated
     * decoding of p0 and the shared vertex between adjacent fan triangles.
     */
    foreach (i; 2 .. ring.length)
    {
        const auto current =
            ring[i];

        if (!current.isFinite)
        {
            /*
             * Do not expose a partial exact result to future internal
             * callers.
             */
            accumulator =
                SignedAreaAccumulator.init;

            return false;
        }


        const auto currentXCoordinate =
            decodeDyadicCoordinate(
                current.x
            );

        const auto currentYCoordinate =
            decodeDyadicCoordinate(
                current.y
            );


        const auto currentX =
            subtractDyadicCoordinates(
                currentXCoordinate,
                originX
            );

        const auto currentY =
            subtractDyadicCoordinates(
                currentYCoordinate,
                originY
            );


        const auto determinant =
            determinantFromDifferences(
                previousX,
                previousY,
                currentX,
                currentY
            );

        addAreaDeterminant(
            accumulator,
            determinant
        );


        previousX =
            currentX;

        previousY =
            currentY;
    }

    return true;
}


/**
 * Algebraic signed area of a linear ring.
 *
 * Supported scalar types are `int`, `long`, `float`, and `double`.
 * The result is binary64.
 *
 * Counter-clockwise traversal has positive area and clockwise traversal
 * has negative area in the usual Cartesian coordinate system.
 *
 * For finite supported coordinates, the exact determinant sum is
 * accumulated before one final correctly-rounded binary64 conversion.
 *
 * Empty, singleton, two-vertex and otherwise algebraically degenerate
 * rings have area zero.
 *
 * A ring containing any non-finite coordinate returns NaN.
 *
 * Self-intersecting rings produce their algebraic signed area; this
 * operation does not validate polygon topology.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(n) time and O(1) auxiliary space for n stored vertices.
 */
AreaScalar!T signedArea(T)(
    scope LinearRingView!T ring
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    SignedAreaAccumulator accumulator;

    if (
        !tryExactRingTwiceArea(
            ring,
            accumulator
        )
    )
    {
        return double.nan;
    }


    /*
     * The exact accumulator contains twice the signed area in units of
     * 2^-2148.
     *
     * Division by two is represented solely by changing the binary scale
     * to 2^-2149 before one final correctly-rounded conversion.
     */
    return roundSignedDyadicToBinary64(
        accumulator.sign,
        accumulator.magnitude,
        -2149
    );
}


/**
 * Role-based algebraic area of a polygon.
 *
 * Supported scalar types are `int`, `long`, `float`, and `double`.
 * The result is binary64.
 *
 * Ring zero is the exterior ring and contributes the magnitude of its exact
 * algebraic area positively. Subsequent rings are interior rings and
 * contribute their exact area magnitudes negatively.
 *
 * Ring orientation therefore does not affect the result.
 *
 * All ring contributions are combined exactly before one final
 * correctly-rounded binary64 conversion.
 *
 * The empty polygon has area positive zero.
 *
 * A polygon containing any non-finite coordinate returns NaN.
 *
 * This operation does not validate polygon topology. Invalid polygon
 * representations may therefore produce a negative role-based result.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(n) time and O(1) auxiliary space for n stored vertices across all
 *     rings.
 */
AreaScalar!T polygonArea(T)(
    scope PolygonView!T polygon
)
    pure nothrow @safe @nogc
if (
    is(T == int) ||
    is(T == long) ||
    is(T == float) ||
    is(T == double)
)
{
    if (polygon.empty)
        return 0.0;


    SignedPolygonAreaAccumulator polygonAccumulator;


    /*
     * The exterior ring contributes its exact magnitude positively.
     *
     * Its original orientation sign is deliberately discarded.
     */
    SignedAreaAccumulator ringAccumulator;

    if (
        !tryExactRingTwiceArea(
            polygon.exterior,
            ringAccumulator
        )
    )
    {
        return double.nan;
    }

    addPolygonAreaMagnitude(
        polygonAccumulator,
        1,
        ringAccumulator.magnitude
    );


    /*
     * Every interior ring contributes its exact magnitude negatively,
     * independently of ring orientation.
     */
    foreach (i; 0 .. polygon.holeCount)
    {
        if (
            !tryExactRingTwiceArea(
                polygon.hole(i),
                ringAccumulator
            )
        )
        {
            return double.nan;
        }

        addPolygonAreaMagnitude(
            polygonAccumulator,
            -1,
            ringAccumulator.magnitude
        );
    }


    /*
     * The polygon accumulator still represents twice the role-based area
     * in determinant units of 2^-2148.
     *
     * Change only the binary scale to 2^-2149 and round once.
     */
    return roundSignedDyadicToBinary64(
        polygonAccumulator.sign,
        polygonAccumulator.magnitude,
        -2149
    );
}


/// Example showing that polygon ring roles are defined by storage order.
@safe unittest
{
    import geo;

    alias P = Point2!double;
    alias R = LinearRingView!double;
    alias V = PolygonView!double;

    P[4] exteriorPoints = [
        P(0.0, 0.0),
        P(10.0, 0.0),
        P(10.0, 10.0),
        P(0.0, 10.0)
    ];

    P[4] holePoints = [
        P(3.0, 3.0),
        P(7.0, 3.0),
        P(7.0, 7.0),
        P(3.0, 7.0)
    ];

    R[2] rings = [
        R(exteriorPoints[]),
        R(holePoints[])
    ];

    auto polygon =
        V(rings[]);

    assert(
        polygonArea(polygon) ==
        84.0
    );
}


@safe unittest
{
    import geo.point :
        Point2;


    alias P = Point2!double;
    alias R = LinearRingView!double;
    alias V = PolygonView!double;


    /*
     * Empty polygon has canonical positive zero area.
     */
    {
        R[] rings;

        const polygon =
            V(rings);

        const result =
            polygonArea(polygon);

        assert(result == 0.0);

        import std.bitmanip :
            DoubleRep;

        const DoubleRep bits =
            DoubleRep(result);

        assert(!bits.sign);
    }


    /*
     * Exterior ring orientation does not affect polygon area.
     */
    {
        P[3] ccwPoints = [
            P(0.0, 0.0),
            P(4.0, 0.0),
            P(0.0, 3.0)
        ];

        P[3] cwPoints = [
            P(0.0, 0.0),
            P(0.0, 3.0),
            P(4.0, 0.0)
        ];

        R[1] ccwRings = [
            R(ccwPoints[])
        ];

        R[1] cwRings = [
            R(cwPoints[])
        ];

        auto ccwPolygon =
            V(ccwRings[]);

        auto cwPolygon =
            V(cwRings[]);

        assert(
            polygonArea(
                ccwPolygon
            ) == 6.0
        );

        assert(
            polygonArea(
                cwPolygon
            ) == 6.0
        );
    }


    /*
     * Hole role, not orientation, determines subtraction.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(10.0, 0.0),
            P(10.0, 10.0),
            P(0.0, 10.0)
        ];

        P[4] holeCcwPoints = [
            P(2.0, 2.0),
            P(4.0, 2.0),
            P(4.0, 4.0),
            P(2.0, 4.0)
        ];

        P[4] holeCwPoints = [
            P(2.0, 2.0),
            P(2.0, 4.0),
            P(4.0, 4.0),
            P(4.0, 2.0)
        ];

        R[2] ccwHoleRings = [
            R(exteriorPoints[]),
            R(holeCcwPoints[])
        ];

        R[2] cwHoleRings = [
            R(exteriorPoints[]),
            R(holeCwPoints[])
        ];

        auto ccwHolePolygon =
            V(ccwHoleRings[]);

        auto cwHolePolygon =
            V(cwHoleRings[]);

        assert(
            polygonArea(
                ccwHolePolygon
            ) == 96.0
        );

        assert(
            polygonArea(
                cwHolePolygon
            ) == 96.0
        );
    }


    /*
     * Invalid representations are not clamped to zero.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(2.0, 0.0),
            P(2.0, 2.0),
            P(0.0, 2.0)
        ];

        P[4] oversizedHolePoints = [
            P(0.0, 0.0),
            P(3.0, 0.0),
            P(3.0, 3.0),
            P(0.0, 3.0)
        ];

        R[2] rings = [
            R(exteriorPoints[]),
            R(oversizedHolePoints[])
        ];

        auto polygon =
            V(rings[]);

        assert(
            polygonArea(
                polygon
            ) == -5.0
        );
    }


    /*
     * Polygon ring contributions are combined exactly before the one
     * final binary64 rounding.
     *
     * At 2^53, binary64 spacing is 2. The exact exterior area 2^53 + 1
     * therefore rounds to 2^53 (ties to even), exactly like the hole area
     * 2^53. Subtracting separately rounded ring areas would incorrectly
     * produce zero, while the exact polygon result is one.
     */
    {
        alias LP = Point2!long;
        alias LR = LinearRingView!long;
        alias LV = PolygonView!long;

        enum long large =
            1L << 53;

        LP[3] exteriorPoints = [
            LP(0, 0),
            LP(large + 1, 0),
            LP(0, 2)
        ];

        LP[3] holePoints = [
            LP(0, 0),
            LP(large, 0),
            LP(0, 2)
        ];

        LR exterior =
            LR(exteriorPoints[]);

        LR hole =
            LR(holePoints[]);

        assert(
            signedArea(exterior) ==
            9_007_199_254_740_992.0
        );

        assert(
            signedArea(hole) ==
            9_007_199_254_740_992.0
        );

        assert(
            signedArea(exterior) -
            signedArea(hole) ==
            0.0
        );

        LR[2] rings = [
            exterior,
            hole
        ];

        auto polygon =
            LV(rings[]);

        assert(
            polygonArea(polygon) ==
            1.0
        );
    }


    /*
     * Non-finite coordinates in any ring make the polygon result NaN.
     */
    {
        P[4] exteriorPoints = [
            P(0.0, 0.0),
            P(5.0, 0.0),
            P(5.0, 5.0),
            P(0.0, 5.0)
        ];

        P[3] holePoints = [
            P(1.0, 1.0),
            P(double.nan, 1.0),
            P(1.0, 2.0)
        ];

        R[2] rings = [
            R(exteriorPoints[]),
            R(holePoints[])
        ];

        auto polygon =
            V(rings[]);

        const result =
            polygonArea(
                polygon
            );

        assert(result != result);
    }
}


@safe unittest
{
    import geo.point :
        Point2;


    /*
     * The internal helper retains the exact twice-area determinant sum.
     */
    {
        Point2!long[3] points = [
            Point2!long(0, 0),
            Point2!long(4, 0),
            Point2!long(0, 3)
        ];

        const ring =
            LinearRingView!long(
                points[]
            );

        SignedAreaAccumulator accumulator;

        assert(
            tryExactRingTwiceArea(
                ring,
                accumulator
            )
        );

        assert(accumulator.sign == 1);
        assert(!accumulator.magnitude.isZero);

        assert(
            roundSignedDyadicToBinary64(
                accumulator.sign,
                accumulator.magnitude,
                -2149
            ) == 6.0
        );
    }


    /*
     * Non-finite input is reported separately and never leaves a partial
     * accumulator behind.
     */
    {
        Point2!double[4] points = [
            Point2!double(0.0, 0.0),
            Point2!double(4.0, 0.0),
            Point2!double(4.0, 3.0),
            Point2!double(double.nan, 3.0)
        ];

        const ring =
            LinearRingView!double(
                points[]
            );

        SignedAreaAccumulator accumulator;

        assert(
            !tryExactRingTwiceArea(
                ring,
                accumulator
            )
        );

        assert(accumulator.sign == 0);
        assert(accumulator.magnitude.isZero);
    }
}


@safe unittest
{
    import geo.point :
        Point2;

    import std.bigint :
        BigInt;

    import std.bitmanip :
        DoubleRep;


    /*
     * Independent exact oracle for integral rings.
     *
     * This deliberately uses the closed shoelace formula and Phobos
     * BigInt rather than geo-d's dyadic determinant implementation.
     *
     * The returned value is twice the exact algebraic area.
     */
    BigInt oracleTwiceArea(
        const(Point2!long)[] points
    )
    {
        BigInt result = 0;

        if (points.length == 0)
            return result;

        foreach (i; 0 .. points.length)
        {
            const size_t next =
                i + 1 == points.length
                    ? 0
                    : i + 1;

            const BigInt ax =
                BigInt(points[i].x);

            const BigInt ay =
                BigInt(points[i].y);

            const BigInt bx =
                BigInt(points[next].x);

            const BigInt by =
                BigInt(points[next].y);

            result +=
                ax * by -
                ay * bx;
        }

        return result;
    }


    static assert(is(AreaScalar!int == double));
    static assert(is(AreaScalar!long == double));
    static assert(is(AreaScalar!float == double));
    static assert(is(AreaScalar!double == double));

    static assert(
        !__traits(
            compiles,
            AreaScalar!real
        )
    );


    /*
     * Empty and degenerate rings.
     */
    {
        Point2!int[] none;

        auto empty =
            LinearRingView!int(none);

        assert(signedArea(empty) == 0.0);

        Point2!int[1] singletonPoints = [
            Point2!int(7, -3)
        ];

        auto singleton =
            LinearRingView!int(
                singletonPoints[]
            );

        assert(signedArea(singleton) == 0.0);

        Point2!int[2] twoPoints = [
            Point2!int(0, 0),
            Point2!int(4, 5)
        ];

        auto two =
            LinearRingView!int(
                twoPoints[]
            );

        assert(signedArea(two) == 0.0);
    }


    /*
     * Counter-clockwise and clockwise traversal.
     */
    {
        Point2!int[3] ccwPoints = [
            Point2!int(0, 0),
            Point2!int(4, 0),
            Point2!int(0, 3)
        ];

        auto ccw =
            LinearRingView!int(
                ccwPoints[]
            );

        assert(signedArea(ccw) == 6.0);


        Point2!int[3] cwPoints = [
            Point2!int(0, 0),
            Point2!int(0, 3),
            Point2!int(4, 0)
        ];

        auto cw =
            LinearRingView!int(
                cwPoints[]
            );

        assert(signedArea(cw) == -6.0);
    }


    /*
     * Translation does not change area, including near the signed-long
     * boundaries where direct integer products would be unsafe.
     */
    {
        Point2!long[3] low = [
            Point2!long(long.min, long.min),
            Point2!long(long.min + 4, long.min),
            Point2!long(long.min, long.min + 3)
        ];

        Point2!long[3] high = [
            Point2!long(long.max - 4, long.max - 3),
            Point2!long(long.max,     long.max - 3),
            Point2!long(long.max - 4, long.max)
        ];

        assert(
            signedArea(
                LinearRingView!long(low[])
            ) == 6.0
        );

        assert(
            signedArea(
                LinearRingView!long(high[])
            ) == 6.0
        );
    }


    /*
     * Explicitly repeated final vertices are ordinary stored vertices
     * and do not change the algebraic result.
     */
    {
        Point2!double[4] points = [
            Point2!double(0.0, 0.0),
            Point2!double(4.0, 0.0),
            Point2!double(0.0, 3.0),
            Point2!double(0.0, 0.0)
        ];

        assert(
            signedArea(
                LinearRingView!double(
                    points[]
                )
            ) == 6.0
        );
    }


    /*
     * Collinear traversal has exact zero area.
     */
    {
        Point2!long[4] points = [
            Point2!long(long.min, 0),
            Point2!long(-1, 0),
            Point2!long(1, 0),
            Point2!long(long.max, 0)
        ];

        const double result =
            signedArea(
                LinearRingView!long(
                    points[]
                )
            );

        DoubleRep representation;
        representation.value = result;

        assert(!representation.sign);
        assert(representation.exponent == 0);
        assert(representation.fraction == 0);
    }


    /*
     * A self-intersecting bow-tie may cancel algebraically to zero.
     */
    {
        Point2!int[4] points = [
            Point2!int(0, 0),
            Point2!int(2, 2),
            Point2!int(0, 2),
            Point2!int(2, 0)
        ];

        assert(
            signedArea(
                LinearRingView!int(
                    points[]
                )
            ) == 0.0
        );
    }


    /*
     * float geometry still returns double.
     */
    {
        Point2!float[3] points = [
            Point2!float(0.0f, 0.0f),
            Point2!float(1.0f, 0.0f),
            Point2!float(0.0f, 1.0f)
        ];

        static assert(
            is(typeof(signedArea(
                LinearRingView!float(
                    points[]
                )
            )) == double)
        );

        assert(
            signedArea(
                LinearRingView!float(
                    points[]
                )
            ) == 0.5
        );
    }


    /*
     * Non-finite input returns NaN, even for geometrically degenerate
     * rings.
     */
    {
        Point2!double[1] nanPoint = [
            Point2!double(
                double.nan,
                0.0
            )
        ];

        const double nanResult =
            signedArea(
                LinearRingView!double(
                    nanPoint[]
                )
            );

        assert(nanResult != nanResult);


        Point2!double[3] infinite = [
            Point2!double(0.0, 0.0),
            Point2!double(
                double.infinity,
                0.0
            ),
            Point2!double(0.0, 1.0)
        ];

        const double infiniteResult =
            signedArea(
                LinearRingView!double(
                    infinite[]
                )
            );

        assert(
            infiniteResult !=
            infiniteResult
        );
    }


    /*
     * Exactly half of the smallest positive subnormal area rounds to
     * positive zero under ties-to-even.
     *
     * The triangle has:
     *
     *     base   = 2^-1074
     *     height = 1
     *     area   = 2^-1075
     */
    {
        DoubleRep smallestRep =
            DoubleRep.init;

        smallestRep.sign = false;
        smallestRep.exponent = 0;
        smallestRep.fraction = 1;

        const double smallestSubnormal =
            smallestRep.value;

        Point2!double[3] positivePoints = [
            Point2!double(0.0, 0.0),
            Point2!double(
                smallestSubnormal,
                0.0
            ),
            Point2!double(0.0, 1.0)
        ];

        const double positive =
            signedArea(
                LinearRingView!double(
                    positivePoints[]
                )
            );

        DoubleRep positiveRep;
        positiveRep.value = positive;

        assert(!positiveRep.sign);
        assert(positiveRep.exponent == 0);
        assert(positiveRep.fraction == 0);


        /*
         * Reversing traversal preserves the exact magnitude and produces
         * negative zero after underflow.
         */
        Point2!double[3] negativePoints = [
            Point2!double(0.0, 0.0),
            Point2!double(0.0, 1.0),
            Point2!double(
                smallestSubnormal,
                0.0
            )
        ];

        const double negative =
            signedArea(
                LinearRingView!double(
                    negativePoints[]
                )
            );

        DoubleRep negativeRep;
        negativeRep.value = negative;

        assert(negativeRep.sign);
        assert(negativeRep.exponent == 0);
        assert(negativeRep.fraction == 0);
    }


    /*
     * Finite binary64 coordinates may have an exact area outside the
     * finite binary64 result range.
     */
    {
        Point2!double[3] positivePoints = [
            Point2!double(0.0, 0.0),
            Point2!double(
                double.max,
                0.0
            ),
            Point2!double(
                0.0,
                double.max
            )
        ];

        const double positive =
            signedArea(
                LinearRingView!double(
                    positivePoints[]
                )
            );

        DoubleRep positiveRep;
        positiveRep.value = positive;

        assert(!positiveRep.sign);
        assert(positiveRep.exponent == 0x7ff);
        assert(positiveRep.fraction == 0);


        Point2!double[3] negativePoints = [
            Point2!double(0.0, 0.0),
            Point2!double(
                0.0,
                double.max
            ),
            Point2!double(
                double.max,
                0.0
            )
        ];

        const double negative =
            signedArea(
                LinearRingView!double(
                    negativePoints[]
                )
            );

        DoubleRep negativeRep;
        negativeRep.value = negative;

        assert(negativeRep.sign);
        assert(negativeRep.exponent == 0x7ff);
        assert(negativeRep.fraction == 0);
    }


    /*
     * Compare the triangle-fan implementation with an independent
     * arbitrary-precision closed-shoelace oracle.
     */
    {
        Point2!long[3] fullRange = [
            Point2!long(
                long.min,
                long.min
            ),
            Point2!long(
                long.max,
                long.min
            ),
            Point2!long(
                long.min,
                long.max
            )
        ];

        auto oracle =
            oracleTwiceArea(
                fullRange[]
            );

        /*
         * Scaling by one half is exact in binary floating point once the
         * integer has been rounded to binary64 at this magnitude.
         */
        const double expected =
            cast(double) oracle *
            0.5;

        const double actual =
            signedArea(
                LinearRingView!long(
                    fullRange[]
                )
            );

        assert(actual == expected);
    }


    /*
     * Independent oracle comparison for a non-trivial multi-vertex ring.
     */
    {
        Point2!long[5] points = [
            Point2!long(-7, 3),
            Point2!long(5, -11),
            Point2!long(13, 2),
            Point2!long(4, 19),
            Point2!long(-9, 12)
        ];

        auto oracle =
            oracleTwiceArea(
                points[]
            );

        const double expected =
            cast(double) oracle *
            0.5;

        const double actual =
            signedArea(
                LinearRingView!long(
                    points[]
                )
            );

        assert(actual == expected);
    }


    /*
     * Large translated self-intersecting linework verifies exact
     * cancellation independently of the triangle-fan formulation.
     */
    {
        Point2!long[4] points = [
            Point2!long(
                long.max - 4,
                long.max - 4
            ),
            Point2!long(
                long.max,
                long.max
            ),
            Point2!long(
                long.max - 4,
                long.max
            ),
            Point2!long(
                long.max,
                long.max - 4
            )
        ];

        auto oracle =
            oracleTwiceArea(
                points[]
            );

        assert(oracle == 0);

        assert(
            signedArea(
                LinearRingView!long(
                    points[]
                )
            ) == 0.0
        );
    }


    /*
     * real remains deliberately unsupported by signedArea.
     */
    static assert(
        !__traits(
            compiles,
            signedArea(
                LinearRingView!real.init
            )
        )
    );
}


/*
 * The exact area construction must not depend on the process
 * floating-point rounding mode.
 */
unittest
{
    import core.stdc.fenv :
        FE_DOWNWARD,
        FE_UPWARD,
        fegetround,
        fesetround;

    import geo.linear_ring_view :
        LinearRingView;

    import geo.point :
        Point2;

    import std.bitmanip :
        DoubleRep;


    /*
     * Construct the next binary64 value above 1.0 directly from its
     * representation so the test input itself does not depend on
     * floating-point arithmetic.
     */
    DoubleRep coordinateRep =
        DoubleRep.init;

    coordinateRep.sign = false;
    coordinateRep.exponent = 1023;
    coordinateRep.fraction = 1;

    const double coordinate =
        coordinateRep.value;

    Point2!double[3] points = [
        Point2!double(0.0, 0.0),
        Point2!double(
            coordinate,
            0.0
        ),
        Point2!double(
            0.0,
            coordinate
        )
    ];

    auto ring =
        LinearRingView!double(
            points[]
        );


    const int originalMode =
        fegetround();

    assert(originalMode != -1);

    scope (exit)
    {
        assert(
            fesetround(
                originalMode
            ) == 0
        );
    }


    assert(
        fesetround(
            FE_DOWNWARD
        ) == 0
    );

    const double downward =
        signedArea(ring);


    assert(
        fesetround(
            FE_UPWARD
        ) == 0
    );

    const double upward =
        signedArea(ring);


    DoubleRep downwardRep;
    downwardRep.value = downward;

    DoubleRep upwardRep;
    upwardRep.value = upward;

    assert(
        downwardRep.sign ==
        upwardRep.sign
    );

    assert(
        downwardRep.exponent ==
        upwardRep.exponent
    );

    assert(
        downwardRep.fraction ==
        upwardRep.fraction
    );
}
