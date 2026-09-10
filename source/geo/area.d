module geo.area;

import geo.internal.area_exact :
    SignedAreaAccumulator,
    addAreaDeterminant;

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


/**
 * Algebraic signed area of a linear ring.
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
 */
AreaScalar!T signedArea(T)(
    LinearRingView!T ring
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
     * Empty rings contain no non-finite coordinates and have exact
     * positive-zero area.
     */
    if (ring.length == 0)
        return 0.0;


    /*
     * Check vertices as they enter the rolling fan rather than scanning
     * the complete ring in a separate pass.
     */
    const auto origin =
        ring[0];

    if (!origin.isFinite)
        return double.nan;

    if (ring.length == 1)
        return 0.0;


    const auto first =
        ring[1];

    if (!first.isFinite)
        return double.nan;

    if (ring.length == 2)
        return 0.0;


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


    SignedAreaAccumulator accumulator;


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
            return double.nan;


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


    /*
     * The accumulated determinant sum represents twice the signed area
     * in units of 2^-2148.
     *
     * Division by two is represented by changing the exact binary scale
     * to 2^-2149 before one final correctly-rounded binary64 conversion.
     */
    return roundSignedDyadicToBinary64(
        accumulator.sign,
        accumulator.magnitude,
        -2149
    );

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
