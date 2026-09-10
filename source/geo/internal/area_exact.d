module geo.internal.area_exact;

import geo.internal.dyadic :
    DyadicProductMagnitude,
    SignedDyadicProduct,
    dyadicProductLimbs;

import geo.internal.fixed_uint :
    UIntFixed,
    addUnsigned,
    compareUnsigned,
    subtractUnsigned;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Exact fixed-width accumulation for signed-area determinant terms.
 *
 * Every input term is an exact SignedDyadicProduct in units of 2^-2148.
 *
 * The accumulator width includes enough additional limbs to sum the
 * maximum number of terms addressable by size_t without overflow.
 */


enum size_t areaAccumulatorExtraLimbs =
    (size_t.sizeof * 8 + 31) / 32;

enum size_t areaAccumulatorLimbs =
    dyadicProductLimbs +
    areaAccumulatorExtraLimbs;


alias AreaAccumulatorMagnitude =
    UIntFixed!areaAccumulatorLimbs;


/**
 * Exact signed sum of area determinant terms.
 *
 * sign:
 *
 *     -1 negative
 *      0 zero
 *      1 positive
 *
 * magnitude is represented in units of 2^-2148.
 */
struct SignedAreaAccumulator
{
    int sign;
    AreaAccumulatorMagnitude magnitude;
}


/*
 * A polygon may contain up to size_t.max rings, while each ring may
 * itself contain up to size_t.max determinant terms.
 *
 * The polygon accumulator therefore needs one additional size_t-sized
 * headroom beyond the ring accumulator.
 */
enum size_t polygonAreaAccumulatorExtraLimbs =
    2 * areaAccumulatorExtraLimbs;

enum size_t polygonAreaAccumulatorLimbs =
    dyadicProductLimbs +
    polygonAreaAccumulatorExtraLimbs;


alias PolygonAreaAccumulatorMagnitude =
    UIntFixed!polygonAreaAccumulatorLimbs;


/**
 * Exact signed role-based sum of ring area magnitudes.
 *
 * sign:
 *
 *     -1 negative
 *      0 zero
 *      1 positive
 *
 * magnitude remains in determinant units of 2^-2148.
 *
 * Exterior and interior ring roles determine the sign supplied when a
 * ring magnitude is added; the original ring orientation is deliberately
 * not retained here.
 */
struct SignedPolygonAreaAccumulator
{
    int sign;
    PolygonAreaAccumulatorMagnitude magnitude;
}


/*
 * Widens one determinant magnitude into accumulator storage.
 */
private AreaAccumulatorMagnitude widenProductMagnitude(
    ref const DyadicProductMagnitude source
)
    pure nothrow @safe @nogc
{
    AreaAccumulatorMagnitude result;

    foreach (i; 0 .. dyadicProductLimbs)
    {
        result.limb[i] =
            source.limb[i];
    }

    return result;
}


/*
 * Widens one exact ring determinant-sum magnitude into polygon
 * accumulator storage.
 */
private PolygonAreaAccumulatorMagnitude widenAreaMagnitude(
    ref const AreaAccumulatorMagnitude source
)
    pure nothrow @safe @nogc
{
    PolygonAreaAccumulatorMagnitude result;

    foreach (i; 0 .. areaAccumulatorLimbs)
    {
        result.limb[i] =
            source.limb[i];
    }

    return result;
}


/**
 * Adds one exact ring-area magnitude with an explicit polygon role sign.
 *
 * contributionSign is:
 *
 *     +1 exterior contribution
 *     -1 interior contribution
 *
 * The ring magnitude itself is unsigned here. Ring orientation has
 * already been intentionally discarded by the caller.
 */
void addPolygonAreaMagnitude(
    ref SignedPolygonAreaAccumulator accumulator,
    int contributionSign,
    ref const AreaAccumulatorMagnitude magnitude
)
    pure nothrow @safe @nogc
{
    assert(
        contributionSign == -1 ||
        contributionSign == 1
    );

    assert(
        accumulator.sign >= -1 &&
        accumulator.sign <= 1
    );

    if (magnitude.isZero)
        return;

    const PolygonAreaAccumulatorMagnitude widened =
        widenAreaMagnitude(
            magnitude
        );

    if (accumulator.sign == 0)
    {
        accumulator.sign =
            contributionSign;

        accumulator.magnitude =
            widened;

        return;
    }

    if (accumulator.sign == contributionSign)
    {
        accumulator.magnitude =
            addUnsigned(
                accumulator.magnitude,
                widened
            );

        return;
    }

    const int comparison =
        compareUnsigned(
            accumulator.magnitude,
            widened
        );

    if (comparison == 0)
    {
        accumulator =
            SignedPolygonAreaAccumulator.init;

        return;
    }

    if (comparison > 0)
    {
        accumulator.magnitude =
            subtractUnsigned(
                accumulator.magnitude,
                widened
            );

        return;
    }

    accumulator.magnitude =
        subtractUnsigned(
            widened,
            accumulator.magnitude
        );

    accumulator.sign =
        contributionSign;
}


/**
 * Adds one exact signed determinant term to the accumulator.
 *
 * The compile-time accumulator-width proof guarantees that accumulation
 * over any representable ring view cannot overflow this fixed storage.
 */
void addAreaDeterminant(
    ref SignedAreaAccumulator accumulator,
    ref const SignedDyadicProduct term
)
    pure nothrow @safe @nogc
{
    assert(
        term.sign >= -1 &&
        term.sign <= 1
    );

    assert(
        accumulator.sign >= -1 &&
        accumulator.sign <= 1
    );

    if (term.sign == 0)
    {
        assert(term.magnitude.isZero);
        return;
    }

    const AreaAccumulatorMagnitude termMagnitude =
        widenProductMagnitude(
            term.magnitude
        );

    if (accumulator.sign == 0)
    {
        accumulator.sign =
            term.sign;

        accumulator.magnitude =
            termMagnitude;

        return;
    }

    if (accumulator.sign == term.sign)
    {
        accumulator.magnitude =
            addUnsigned(
                accumulator.magnitude,
                termMagnitude
            );

        return;
    }

    const int comparison =
        compareUnsigned(
            accumulator.magnitude,
            termMagnitude
        );

    if (comparison == 0)
    {
        accumulator =
            SignedAreaAccumulator.init;

        return;
    }

    if (comparison > 0)
    {
        accumulator.magnitude =
            subtractUnsigned(
                accumulator.magnitude,
                termMagnitude
            );

        return;
    }

    accumulator.magnitude =
        subtractUnsigned(
            termMagnitude,
            accumulator.magnitude
        );

    accumulator.sign =
        term.sign;
}


@safe unittest
{
    import geo.internal.orientation_dyadic :
        orientationDeterminantDyadic;


    /*
     * The accumulator has enough compile-time headroom for the maximum
     * number of determinant terms representable by size_t.
     */
    static assert(
        areaAccumulatorLimbs >=
        dyadicProductLimbs + 1
    );

    static assert(
        areaAccumulatorLimbs * 32 >=
        dyadicProductLimbs * 32 +
        size_t.sizeof * 8
    );


    /*
     * Exact zero is canonical.
     */
    SignedAreaAccumulator sum;

    assert(sum.sign == 0);
    assert(sum.magnitude.isZero);


    /*
     * Add one positive determinant.
     */
    const auto positive =
        orientationDeterminantDyadic(
            0L, 0L,
            1L, 0L,
            0L, 1L
        );

    addAreaDeterminant(
        sum,
        positive
    );

    assert(sum.sign == 1);
    assert(!sum.magnitude.isZero);


    /*
     * Adding the exact opposite determinant cancels to canonical zero.
     */
    const auto negative =
        orientationDeterminantDyadic(
            0L, 0L,
            0L, 1L,
            1L, 0L
        );

    addAreaDeterminant(
        sum,
        negative
    );

    assert(sum.sign == 0);
    assert(sum.magnitude.isZero);


    /*
     * Multiple equal-sign terms accumulate exactly.
     */
    addAreaDeterminant(
        sum,
        positive
    );

    const auto once =
        sum.magnitude;

    addAreaDeterminant(
        sum,
        positive
    );

    assert(sum.sign == 1);

    const auto expectedTwice =
        addUnsigned(
            once,
            once
        );

    assert(
        sum.magnitude.limb ==
        expectedTwice.limb
    );


    /*
     * A larger opposite-sign magnitude changes the resulting sign.
     */
    addAreaDeterminant(
        sum,
        negative
    );

    addAreaDeterminant(
        sum,
        negative
    );

    addAreaDeterminant(
        sum,
        negative
    );

    assert(sum.sign == -1);

    assert(
        sum.magnitude.limb ==
        widenProductMagnitude(
            negative.magnitude
        ).limb
    );
}



@safe unittest
{
    /*
     * Polygon accumulation has enough compile-time headroom for a
     * size_t-sized number of rings, each containing a size_t-sized
     * number of exact determinant terms.
     */
    static assert(
        polygonAreaAccumulatorLimbs >
        areaAccumulatorLimbs
    );

    static assert(
        polygonAreaAccumulatorLimbs * 32 >=
        dyadicProductLimbs * 32 +
        2 * size_t.sizeof * 8
    );


    /*
     * Exact zero is canonical and zero ring magnitudes have no effect.
     */
    {
        SignedPolygonAreaAccumulator sum;
        AreaAccumulatorMagnitude zero;

        addPolygonAreaMagnitude(
            sum,
            1,
            zero
        );

        assert(sum.sign == 0);
        assert(sum.magnitude.isZero);
    }


    /*
     * Exterior magnitudes contribute positively.
     */
    {
        SignedPolygonAreaAccumulator sum;

        AreaAccumulatorMagnitude exterior;
        exterior.limb[0] = 12;

        addPolygonAreaMagnitude(
            sum,
            1,
            exterior
        );

        assert(sum.sign == 1);
        assert(sum.magnitude.limb[0] == 12);
    }


    /*
     * Interior magnitudes subtract independently of original ring
     * orientation.
     */
    {
        SignedPolygonAreaAccumulator sum;

        AreaAccumulatorMagnitude exterior;
        exterior.limb[0] = 12;

        AreaAccumulatorMagnitude hole;
        hole.limb[0] = 5;

        addPolygonAreaMagnitude(
            sum,
            1,
            exterior
        );

        addPolygonAreaMagnitude(
            sum,
            -1,
            hole
        );

        assert(sum.sign == 1);
        assert(sum.magnitude.limb[0] == 7);
    }


    /*
     * Exact cancellation returns canonical positive zero state.
     */
    {
        SignedPolygonAreaAccumulator sum;

        AreaAccumulatorMagnitude value;
        value.limb[0] = 9;

        addPolygonAreaMagnitude(
            sum,
            1,
            value
        );

        addPolygonAreaMagnitude(
            sum,
            -1,
            value
        );

        assert(sum.sign == 0);
        assert(sum.magnitude.isZero);
    }


    /*
     * Interior magnitudes may exceed the exterior magnitude for invalid
     * polygon representations. The exact result then remains negative
     * rather than being clamped.
     */
    {
        SignedPolygonAreaAccumulator sum;

        AreaAccumulatorMagnitude exterior;
        exterior.limb[0] = 3;

        AreaAccumulatorMagnitude hole;
        hole.limb[0] = 11;

        addPolygonAreaMagnitude(
            sum,
            1,
            exterior
        );

        addPolygonAreaMagnitude(
            sum,
            -1,
            hole
        );

        assert(sum.sign == -1);
        assert(sum.magnitude.limb[0] == 8);
    }


    /*
     * Repeated maximum-width ring magnitudes may carry into the
     * polygon-only headroom.
     */
    {
        SignedPolygonAreaAccumulator sum;

        AreaAccumulatorMagnitude large;
        large.limb[areaAccumulatorLimbs - 1] =
            uint.max;

        addPolygonAreaMagnitude(
            sum,
            1,
            large
        );

        addPolygonAreaMagnitude(
            sum,
            1,
            large
        );

        assert(sum.sign == 1);

        assert(
            sum.magnitude
                .limb[areaAccumulatorLimbs - 1] ==
            uint.max - 1
        );

        assert(
            sum.magnitude
                .limb[areaAccumulatorLimbs] ==
            1
        );
    }
}
