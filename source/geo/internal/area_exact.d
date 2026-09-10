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
