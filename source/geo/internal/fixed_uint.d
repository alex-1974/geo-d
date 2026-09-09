module geo.internal.fixed_uint;


/*
 * INTERNAL IMPLEMENTATION MODULE.
 *
 * Small fixed-width unsigned integer primitives for robust geometric
 * predicates and constructions.
 *
 * This is deliberately not a general arbitrary-precision integer type.
 *
 * Storage is:
 *
 * - fixed at compile time;
 * - inline/value-owned;
 * - little-endian in base 2^32;
 * - allocation-free.
 */


/**
 * Fixed-width unsigned integer using little-endian 32-bit limbs.
 */
struct UIntFixed(size_t Limbs)
if (Limbs > 0)
{
    uint[Limbs] limb;


    @property bool isZero() const
        pure nothrow @safe @nogc
    {
        foreach (value; limb)
        {
            if (value != 0)
                return false;
        }

        return true;
    }
}


/**
 * Exact unsigned comparison.
 *
 * Returns:
 *
 *     -1 lhs < rhs
 *      0 lhs == rhs
 *      1 lhs > rhs
 */
int compareUnsigned(size_t Limbs)(
    ref const UIntFixed!Limbs lhs,
    ref const UIntFixed!Limbs rhs
)
    pure nothrow @safe @nogc
{
    size_t index = Limbs;

    while (index > 0)
    {
        --index;

        if (lhs.limb[index] < rhs.limb[index])
            return -1;

        if (lhs.limb[index] > rhs.limb[index])
            return 1;
    }

    return 0;
}


/**
 * Exact fixed-width unsigned addition.
 *
 * The caller guarantees that the mathematical result fits in the
 * selected width.
 */
UIntFixed!Limbs addUnsigned(size_t Limbs)(
    ref const UIntFixed!Limbs lhs,
    ref const UIntFixed!Limbs rhs
)
    pure nothrow @safe @nogc
{
    UIntFixed!Limbs result;

    ulong carry = 0;

    foreach (index; 0 .. Limbs)
    {
        const ulong sum =
            cast(ulong) lhs.limb[index] +
            cast(ulong) rhs.limb[index] +
            carry;

        result.limb[index] =
            cast(uint) sum;

        carry =
            sum >> 32;
    }

    assert(carry == 0);

    return result;
}


/**
 * Exact fixed-width unsigned subtraction.
 *
 * Precondition:
 *
 *     lhs >= rhs
 */
UIntFixed!Limbs subtractUnsigned(size_t Limbs)(
    ref const UIntFixed!Limbs lhs,
    ref const UIntFixed!Limbs rhs
)
    pure nothrow @safe @nogc
{
    assert(
        compareUnsigned(lhs, rhs) >= 0
    );

    UIntFixed!Limbs result;

    ulong borrow = 0;

    foreach (index; 0 .. Limbs)
    {
        const ulong lhsValue =
            cast(ulong) lhs.limb[index];

        const ulong rhsValue =
            cast(ulong) rhs.limb[index] +
            borrow;

        if (lhsValue >= rhsValue)
        {
            result.limb[index] =
                cast(uint)(
                    lhsValue - rhsValue
                );

            borrow = 0;
        }
        else
        {
            result.limb[index] =
                cast(uint)(
                    0x1_0000_0000UL +
                    lhsValue -
                    rhsValue
                );

            borrow = 1;
        }
    }

    assert(borrow == 0);

    return result;
}


/**
 * Exact fixed-width multiplication.
 *
 * Multiplying an M-limb value by an N-limb value yields an
 * (M + N)-limb result.
 *
 * The implementation uses ordinary base-2^32 schoolbook
 * multiplication.
 */
UIntFixed!(LhsLimbs + RhsLimbs) multiplyUnsigned(
    size_t LhsLimbs,
    size_t RhsLimbs
)(
    ref const UIntFixed!LhsLimbs lhs,
    ref const UIntFixed!RhsLimbs rhs
)
    pure nothrow @safe @nogc
{
    UIntFixed!(LhsLimbs + RhsLimbs) result;

    foreach (i; 0 .. LhsLimbs)
    {
        ulong carry = 0;

        foreach (j; 0 .. RhsLimbs)
        {
            const size_t index =
                i + j;

            /*
             * Maximum possible accumulator:
             *
             *     (2^32 - 1)^2
             *   + (2^32 - 1)
             *   + (2^32 - 1)
             *
             * = 2^64 - 1
             *
             * therefore ulong is exactly sufficient.
             */
            const ulong accumulated =
                cast(ulong) lhs.limb[i] *
                    cast(ulong) rhs.limb[j]
                + cast(ulong)
                    result.limb[index]
                + carry;

            result.limb[index] =
                cast(uint) accumulated;

            carry =
                accumulated >> 32;
        }

        const size_t carryIndex =
            i + RhsLimbs;

        assert(
            carryIndex <
            LhsLimbs + RhsLimbs
        );

        /*
         * This limb lies immediately beyond the inner product range
         * for this outer iteration and has not yet received a value
         * except through the propagated carry represented here.
         */
        result.limb[carryIndex] =
            cast(uint) carry;
    }

    return result;
}


@safe unittest
{
    /*
     * Initial value and zero detection.
     */
    {
        UIntFixed!2 value;

        assert(value.isZero);

        value.limb[0] = 1;

        assert(!value.isZero);
    }


    /*
     * Comparison proceeds from the most significant limb.
     */
    {
        UIntFixed!2 a;
        UIntFixed!2 b;

        a.limb[0] = uint.max;

        b.limb[1] = 1;

        assert(
            compareUnsigned(a, b) < 0
        );

        assert(
            compareUnsigned(b, a) > 0
        );

        assert(
            compareUnsigned(a, a) == 0
        );
    }


    /*
     * Addition propagates carry across limbs.
     */
    {
        UIntFixed!2 a;
        UIntFixed!2 b;

        a.limb[0] =
            uint.max;

        b.limb[0] = 1;

        const auto sum =
            addUnsigned(a, b);

        assert(sum.limb[0] == 0);
        assert(sum.limb[1] == 1);
    }


    /*
     * Subtraction propagates borrow across limbs.
     */
    {
        UIntFixed!2 a;
        UIntFixed!2 b;

        a.limb[1] = 1;
        b.limb[0] = 1;

        const auto difference =
            subtractUnsigned(a, b);

        assert(
            difference.limb[0] ==
            uint.max
        );

        assert(
            difference.limb[1] == 0
        );
    }


    /*
     * 1-limb multiplication.
     */
    {
        UIntFixed!1 a;
        UIntFixed!1 b;

        a.limb[0] =
            uint.max;

        b.limb[0] =
            uint.max;

        const auto product =
            multiplyUnsigned(a, b);

        static assert(
            is(
                typeof(
                    multiplyUnsigned(a, b)
                ) ==
                UIntFixed!2
            )
        );

        assert(
            product.limb[0] == 1
        );

        assert(
            product.limb[1] ==
            uint.max - 1
        );
    }


    /*
     * Multiplication works across unequal widths.
     *
     *     2^32 * 1
     *   = 2^32
     */
    {
        UIntFixed!2 a;
        UIntFixed!1 b;

        a.limb[1] = 1;
        b.limb[0] = 1;

        const auto product =
            multiplyUnsigned(a, b);

        static assert(
            is(
                typeof(
                    multiplyUnsigned(a, b)
                ) ==
                UIntFixed!3
            )
        );

        assert(product.limb[0] == 0);
        assert(product.limb[1] == 1);
        assert(product.limb[2] == 0);
    }


    /*
     * Multi-limb carry propagation.
     *
     *     (2^64 - 1) * (2^32 - 1)
     */
    {
        UIntFixed!2 a;
        UIntFixed!1 b;

        a.limb[0] =
            uint.max;

        a.limb[1] =
            uint.max;

        b.limb[0] =
            uint.max;

        const auto product =
            multiplyUnsigned(a, b);

        assert(
            product.limb[0] == 1
        );

        assert(
            product.limb[1] ==
            uint.max
        );

        assert(
            product.limb[2] ==
            uint.max - 1
        );
    }
}
