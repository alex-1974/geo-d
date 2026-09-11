#include <algorithm>
#include <array>
#include <bit>
#include <cfloat>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <limits>

#if defined(__GNUC__) || defined(__clang__)
#  define NOINLINE __attribute__((noinline))
#  define ALWAYS_INLINE inline __attribute__((always_inline))
#else
#  define NOINLINE
#  define ALWAYS_INLINE inline
#endif

static_assert(std::numeric_limits<double>::is_iec559);
static_assert(std::numeric_limits<double>::radix == 2);
static_assert(std::numeric_limits<double>::digits == 53);
static_assert(std::numeric_limits<double>::max_exponent == 1024);
static_assert(std::numeric_limits<double>::min_exponent == -1021);
static_assert(FLT_EVAL_METHOD == 0,
              "benchmark requires double expressions evaluated as binary64");

constexpr std::size_t repetitions = 7;
constexpr std::size_t warmup_iterations = 1'000'000;
constexpr std::size_t cheap_iterations = 20'000'000;
constexpr std::size_t expansion_iterations = 1'000'000;
constexpr std::size_t dyadic_iterations = 500'000;

enum class Orientation : std::int8_t {
    right = -1,
    collinear = 0,
    left = 1,
};

enum class OrientationFilterResult : std::int8_t {
    right = -1,
    collinear = 0,
    left = 1,
    uncertain = 2,
};

template <typename T>
struct Point2 {
    T x;
    T y;
};

template <typename T>
struct OrientationCase {
    Point2<T> a;
    Point2<T> b;
    Point2<T> c;
};

static std::array<OrientationCase<double>, 2> double_fast_cases;
static std::array<OrientationCase<double>, 2> double_expansion_collinear_cases;
static std::array<OrientationCase<double>, 2> double_expansion_near_cases;
static std::array<OrientationCase<double>, 2> double_dyadic_collinear_cases;
static std::array<OrientationCase<double>, 2> double_dyadic_near_cases;
static std::array<OrientationCase<double>, 2> double_subnormal_cases;

static std::uint64_t benchmark_sink;

ALWAYS_INLINE std::uint64_t bits_of(double x) noexcept {
    return std::bit_cast<std::uint64_t>(x);
}

ALWAYS_INLINE bool is_finite(double x) noexcept {
    return (bits_of(x) & 0x7ff0'0000'0000'0000ULL)
        != 0x7ff0'0000'0000'0000ULL;
}

ALWAYS_INLINE bool is_subnormal(double x) noexcept {
    const auto bits = bits_of(x) & 0x7fff'ffff'ffff'ffffULL;
    return (bits & 0x7ff0'0000'0000'0000ULL) == 0
        && (bits & 0x000f'ffff'ffff'ffffULL) != 0;
}

/*
 * C++ target contract for this benchmark:
 *
 * - IEEE binary64 double
 * - FLT_EVAL_METHOD == 0
 * - build with -ffp-contract=off and without -ffast-math
 *
 * Under that contract each elementary operator has the same binary64
 * rounding point that geo-d explicitly requests via toPrec!double.
 */
ALWAYS_INLINE double rounded_add(double lhs, double rhs) noexcept {
    return lhs + rhs;
}

ALWAYS_INLINE double rounded_sub(double lhs, double rhs) noexcept {
    return lhs - rhs;
}

ALWAYS_INLINE double rounded_mul(double lhs, double rhs) noexcept {
    return lhs * rhs;
}

ALWAYS_INLINE double finite_magnitude(double value) noexcept {
    return value < 0.0 ? -value : value;
}

ALWAYS_INLINE bool normal_or_zero(double value) noexcept {
    return value == 0.0 || (is_finite(value) && !is_subnormal(value));
}

ALWAYS_INLINE bool product_underflowed(
    double lhs,
    double rhs,
    double product
) noexcept {
    return product == 0.0 && lhs != 0.0 && rhs != 0.0;
}

constexpr double ccw_errbound_a = 0x1.8000000000004p-52;

/*
 * Match geo-d's observed LDC call boundary: the public orientation wrapper
 * calls the certified filter out-of-line.
 */
NOINLINE OrientationFilterResult orientation_filter(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy
) noexcept {
    if (!is_finite(ax) ||
        !is_finite(ay) ||
        !is_finite(bx) ||
        !is_finite(by) ||
        !is_finite(cx) ||
        !is_finite(cy))
    {
        return OrientationFilterResult::uncertain;
    }

    const double acx = rounded_sub(ax, cx);
    const double bcx = rounded_sub(bx, cx);
    const double acy = rounded_sub(ay, cy);
    const double bcy = rounded_sub(by, cy);

    if (!normal_or_zero(acx) ||
        !normal_or_zero(bcx) ||
        !normal_or_zero(acy) ||
        !normal_or_zero(bcy))
    {
        return OrientationFilterResult::uncertain;
    }

    const double detleft = rounded_mul(acx, bcy);
    const double detright = rounded_mul(acy, bcx);

    if (product_underflowed(acx, bcy, detleft) ||
        product_underflowed(acy, bcx, detright))
    {
        return OrientationFilterResult::uncertain;
    }

    if (!normal_or_zero(detleft) ||
        !normal_or_zero(detright))
    {
        return OrientationFilterResult::uncertain;
    }

    double detsum;

    if (detleft > 0.0) {
        if (detright <= 0.0)
            return OrientationFilterResult::left;

        detsum = rounded_add(detleft, detright);
    } else if (detleft < 0.0) {
        if (detright >= 0.0)
            return OrientationFilterResult::right;

        detsum = rounded_add(-detleft, -detright);
    } else {
        if (detright > 0.0)
            return OrientationFilterResult::right;

        if (detright < 0.0)
            return OrientationFilterResult::left;

        return OrientationFilterResult::collinear;
    }

    if (!is_finite(detsum) || is_subnormal(detsum))
        return OrientationFilterResult::uncertain;

    const double det = rounded_sub(detleft, detright);

    if (!is_finite(det) ||
        (det != 0.0 && is_subnormal(det)))
    {
        return OrientationFilterResult::uncertain;
    }

    const double errbound =
        rounded_mul(ccw_errbound_a, detsum);

    if (!is_finite(errbound) ||
        errbound == 0.0 ||
        is_subnormal(errbound))
    {
        return OrientationFilterResult::uncertain;
    }

    if (det >= errbound)
        return OrientationFilterResult::left;

    if (-det >= errbound)
        return OrientationFilterResult::right;

    return OrientationFilterResult::uncertain;
}

/* ------------------------------------------------------------------------- */
/* Expansion backend: direct port of geo.internal.expansion + orientation_exact */
/* ------------------------------------------------------------------------- */

struct TwoComponent {
    double high;
    double low;
};

struct SplitComponent {
    double high;
    double low;
};

constexpr double splitter = 134'217'729.0;

ALWAYS_INLINE TwoComponent two_sum(double a, double b) noexcept {
    const double x = rounded_add(a, b);
    const double b_virtual = rounded_sub(x, a);
    const double a_virtual = rounded_sub(x, b_virtual);
    const double b_roundoff = rounded_sub(b, b_virtual);
    const double a_roundoff = rounded_sub(a, a_virtual);
    const double y = rounded_add(a_roundoff, b_roundoff);
    return {x, y};
}

ALWAYS_INLINE TwoComponent two_diff(double a, double b) noexcept {
    const double x = rounded_sub(a, b);
    const double b_virtual = rounded_sub(a, x);
    const double a_virtual = rounded_add(x, b_virtual);
    const double b_roundoff = rounded_sub(b_virtual, b);
    const double a_roundoff = rounded_sub(a, a_virtual);
    const double y = rounded_add(a_roundoff, b_roundoff);
    return {x, y};
}

ALWAYS_INLINE SplitComponent split(double value) noexcept {
    const double c = rounded_mul(splitter, value);
    const double a_big = rounded_sub(c, value);
    const double high = rounded_sub(c, a_big);
    const double low = rounded_sub(value, high);
    return {high, low};
}

ALWAYS_INLINE TwoComponent two_product_presplit(
    double a,
    double b,
    SplitComponent b_split
) noexcept {
    const double x = rounded_mul(a, b);
    const auto a_split = split(a);

    const double high_product =
        rounded_mul(a_split.high, b_split.high);

    const double err1 =
        rounded_sub(x, high_product);

    const double low_high_product =
        rounded_mul(a_split.low, b_split.high);

    const double err2 =
        rounded_sub(err1, low_high_product);

    const double high_low_product =
        rounded_mul(a_split.high, b_split.low);

    const double err3 =
        rounded_sub(err2, high_low_product);

    const double low_product =
        rounded_mul(a_split.low, b_split.low);

    const double y =
        rounded_sub(low_product, err3);

    return {x, y};
}

template <std::size_t Capacity>
struct ExpansionBuffer {
    std::array<double, Capacity> data{};
    std::size_t length = 0;

    ALWAYS_INLINE bool empty() const noexcept {
        return length == 0;
    }

    ALWAYS_INLINE void clear() noexcept {
        length = 0;
    }

    ALWAYS_INLINE void append(double value) noexcept {
        data[length++] = value;
    }

    ALWAYS_INLINE double operator[](std::size_t index) const noexcept {
        return data[index];
    }
};

ALWAYS_INLINE TwoComponent fast_two_sum(double a, double b) noexcept {
    const double x = rounded_add(a, b);
    const double b_virtual = rounded_sub(x, a);
    const double y = rounded_sub(b, b_virtual);
    return {x, y};
}

template <std::size_t SourceCapacity, std::size_t ResultCapacity>
ALWAYS_INLINE void copy_expansion_zero_elim(
    const ExpansionBuffer<SourceCapacity>& source,
    ExpansionBuffer<ResultCapacity>& result
) noexcept {
    result.clear();

    for (std::size_t index = 0; index < source.length; ++index) {
        const double component = source[index];
        if (component != 0.0)
            result.append(component);
    }

    if (result.empty())
        result.append(0.0);
}

template <
    std::size_t ECapacity,
    std::size_t FCapacity,
    std::size_t HCapacity
>
NOINLINE void fast_expansion_sum_zero_elim(
    const ExpansionBuffer<ECapacity>& e,
    const ExpansionBuffer<FCapacity>& f,
    ExpansionBuffer<HCapacity>& h
) noexcept {
    static_assert(HCapacity >= ECapacity + FCapacity);

    if (e.empty()) {
        copy_expansion_zero_elim(f, h);
        return;
    }

    if (f.empty()) {
        copy_expansion_zero_elim(e, h);
        return;
    }

    h.clear();

    std::size_t e_index = 0;
    std::size_t f_index = 0;

    double e_now = e[e_index];
    double f_now = f[f_index];

    double q;

    if (finite_magnitude(e_now) <= finite_magnitude(f_now)) {
        q = e_now;
        ++e_index;
    } else {
        q = f_now;
        ++f_index;
    }

    if (e_index < e.length && f_index < f.length) {
        double next;

        if (finite_magnitude(e[e_index]) <=
            finite_magnitude(f[f_index]))
        {
            next = e[e_index++];
        } else {
            next = f[f_index++];
        }

        const auto initial = fast_two_sum(next, q);

        if (initial.low != 0.0)
            h.append(initial.low);

        q = initial.high;

        while (e_index < e.length && f_index < f.length) {
            if (finite_magnitude(e[e_index]) <=
                finite_magnitude(f[f_index]))
            {
                next = e[e_index++];
            } else {
                next = f[f_index++];
            }

            const auto sum = two_sum(q, next);

            if (sum.low != 0.0)
                h.append(sum.low);

            q = sum.high;
        }
    }

    while (e_index < e.length) {
        const auto sum = two_sum(q, e[e_index++]);

        if (sum.low != 0.0)
            h.append(sum.low);

        q = sum.high;
    }

    while (f_index < f.length) {
        const auto sum = two_sum(q, f[f_index++]);

        if (sum.low != 0.0)
            h.append(sum.low);

        q = sum.high;
    }

    if (q != 0.0 || h.empty())
        h.append(q);
}

template <std::size_t ECapacity, std::size_t HCapacity>
NOINLINE void scale_expansion_zero_elim(
    const ExpansionBuffer<ECapacity>& expansion,
    double scalar,
    ExpansionBuffer<HCapacity>& result
) noexcept {
    static_assert(HCapacity >= 2 * ECapacity);

    if (expansion.empty()) {
        result.clear();
        result.append(0.0);
        return;
    }

    result.clear();

    const auto scalar_split = split(scalar);

    auto product =
        two_product_presplit(
            expansion[0],
            scalar,
            scalar_split
        );

    double q = product.high;

    if (product.low != 0.0)
        result.append(product.low);

    for (std::size_t index = 1; index < expansion.length; ++index) {
        product =
            two_product_presplit(
                expansion[index],
                scalar,
                scalar_split
            );

        const auto sum =
            two_sum(q, product.low);

        if (sum.low != 0.0)
            result.append(sum.low);

        const auto accumulated =
            fast_two_sum(product.high, sum.high);

        if (accumulated.low != 0.0)
            result.append(accumulated.low);

        q = accumulated.high;
    }

    if (q != 0.0 || result.empty())
        result.append(q);
}

template <std::size_t Capacity>
ALWAYS_INLINE int expansion_sign(
    const ExpansionBuffer<Capacity>& expansion
) noexcept {
    std::size_t index = expansion.length;

    while (index > 0) {
        --index;
        const double component = expansion[index];

        if (component > 0.0)
            return 1;

        if (component < 0.0)
            return -1;
    }

    return 0;
}

template <std::size_t SourceCapacity, std::size_t ResultCapacity>
ALWAYS_INLINE void negate_expansion(
    const ExpansionBuffer<SourceCapacity>& source,
    ExpansionBuffer<ResultCapacity>& result
) noexcept {
    static_assert(ResultCapacity >= SourceCapacity);

    result.clear();

    for (std::size_t index = 0; index < source.length; ++index)
        result.append(-source[index]);
}

constexpr double min_working_magnitude = 0x1p-450;
constexpr double max_working_magnitude = 0x1p+450;

ALWAYS_INLINE bool supported_component(double value) noexcept {
    if (!is_finite(value))
        return false;

    if (value == 0.0)
        return true;

    const double abs_value = finite_magnitude(value);

    return abs_value >= min_working_magnitude &&
           abs_value <= max_working_magnitude;
}

NOINLINE bool build_difference(
    double lhs,
    double rhs,
    ExpansionBuffer<2>& result
) noexcept {
    const double rounded = rounded_sub(lhs, rhs);

    if (!is_finite(rounded))
        return false;

    const TwoComponent difference = two_diff(lhs, rhs);

    if (!supported_component(difference.low) ||
        !supported_component(difference.high))
    {
        return false;
    }

    result.clear();

    if (difference.low != 0.0)
        result.append(difference.low);

    if (difference.high != 0.0)
        result.append(difference.high);

    if (result.empty())
        result.append(0.0);

    return true;
}

NOINLINE void multiply_difference_expansions(
    const ExpansionBuffer<2>& lhs,
    const ExpansionBuffer<2>& rhs,
    ExpansionBuffer<8>& result
) noexcept {
    ExpansionBuffer<4> first;
    ExpansionBuffer<4> second;

    scale_expansion_zero_elim(lhs, rhs[0], first);

    if (rhs.length == 2)
        scale_expansion_zero_elim(lhs, rhs[1], second);

    fast_expansion_sum_zero_elim(first, second, result);
}

/*
 * Match geo-d's cold backend call structure.
 */
NOINLINE bool try_orientation_exact_expansion(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
    int& sign
) noexcept {
    sign = 0;

    if (!is_finite(ax) ||
        !is_finite(ay) ||
        !is_finite(bx) ||
        !is_finite(by) ||
        !is_finite(cx) ||
        !is_finite(cy))
    {
        return false;
    }

    ExpansionBuffer<2> acx;
    ExpansionBuffer<2> acy;
    ExpansionBuffer<2> bcx;
    ExpansionBuffer<2> bcy;

    if (!build_difference(ax, cx, acx) ||
        !build_difference(ay, cy, acy) ||
        !build_difference(bx, cx, bcx) ||
        !build_difference(by, cy, bcy))
    {
        return false;
    }

    ExpansionBuffer<8> left_product;
    ExpansionBuffer<8> right_product;

    multiply_difference_expansions(
        acx,
        bcy,
        left_product
    );

    multiply_difference_expansions(
        acy,
        bcx,
        right_product
    );

    ExpansionBuffer<8> negative_right;
    negate_expansion(right_product, negative_right);

    ExpansionBuffer<16> determinant;

    fast_expansion_sum_zero_elim(
        left_product,
        negative_right,
        determinant
    );

    sign = expansion_sign(determinant);
    return true;
}

/* ------------------------------------------------------------------------- */
/* Full-range exact dyadic backend: direct port of fixed_uint + dyadic        */
/* ------------------------------------------------------------------------- */

template <std::size_t Limbs>
struct UIntFixed {
    std::array<std::uint32_t, Limbs> limb{};
};

template <std::size_t Limbs>
ALWAYS_INLINE std::size_t first_non_zero_limb(
    const UIntFixed<Limbs>& value
) noexcept {
    for (std::size_t i = 0; i < Limbs; ++i) {
        if (value.limb[i] != 0)
            return i;
    }

    return Limbs;
}

template <std::size_t Limbs>
ALWAYS_INLINE std::size_t past_last_non_zero_limb(
    const UIntFixed<Limbs>& value
) noexcept {
    for (std::size_t i = Limbs; i != 0; --i) {
        if (value.limb[i - 1] != 0)
            return i;
    }

    return 0;
}

template <std::size_t Limbs>
ALWAYS_INLINE int compare_unsigned(
    const UIntFixed<Limbs>& lhs,
    const UIntFixed<Limbs>& rhs
) noexcept {
    std::size_t index = Limbs;

    while (index > 0) {
        --index;

        if (lhs.limb[index] < rhs.limb[index])
            return -1;

        if (lhs.limb[index] > rhs.limb[index])
            return 1;
    }

    return 0;
}

template <std::size_t Limbs>
ALWAYS_INLINE UIntFixed<Limbs> add_unsigned(
    const UIntFixed<Limbs>& lhs,
    const UIntFixed<Limbs>& rhs
) noexcept {
    UIntFixed<Limbs> result = lhs;

    const std::size_t rhs_first =
        first_non_zero_limb(rhs);

    if (rhs_first == Limbs)
        return result;

    const std::size_t rhs_end =
        past_last_non_zero_limb(rhs);

    std::uint64_t carry = 0;

    for (std::size_t index = rhs_first; index < rhs_end; ++index) {
        const std::uint64_t sum =
            static_cast<std::uint64_t>(result.limb[index]) +
            static_cast<std::uint64_t>(rhs.limb[index]) +
            carry;

        result.limb[index] =
            static_cast<std::uint32_t>(sum);

        carry = sum >> 32;
    }

    std::size_t index = rhs_end;

    while (carry != 0) {
        const std::uint64_t sum =
            static_cast<std::uint64_t>(result.limb[index]) +
            carry;

        result.limb[index] =
            static_cast<std::uint32_t>(sum);

        carry = sum >> 32;
        ++index;
    }

    return result;
}

template <std::size_t Limbs>
ALWAYS_INLINE UIntFixed<Limbs> subtract_unsigned(
    const UIntFixed<Limbs>& lhs,
    const UIntFixed<Limbs>& rhs
) noexcept {
    UIntFixed<Limbs> result = lhs;

    const std::size_t rhs_first =
        first_non_zero_limb(rhs);

    if (rhs_first == Limbs)
        return result;

    const std::size_t rhs_end =
        past_last_non_zero_limb(rhs);

    std::uint64_t borrow = 0;

    for (std::size_t index = rhs_first; index < rhs_end; ++index) {
        const std::uint64_t lhs_value =
            static_cast<std::uint64_t>(result.limb[index]);

        const std::uint64_t rhs_value =
            static_cast<std::uint64_t>(rhs.limb[index]) +
            borrow;

        if (lhs_value >= rhs_value) {
            result.limb[index] =
                static_cast<std::uint32_t>(
                    lhs_value - rhs_value
                );

            borrow = 0;
        } else {
            result.limb[index] =
                static_cast<std::uint32_t>(
                    0x1'0000'0000ULL +
                    lhs_value -
                    rhs_value
                );

            borrow = 1;
        }
    }

    std::size_t index = rhs_end;

    while (borrow != 0) {
        if (result.limb[index] != 0) {
            --result.limb[index];
            borrow = 0;
        } else {
            result.limb[index] =
                std::numeric_limits<std::uint32_t>::max();

            ++index;
        }
    }

    return result;
}

template <std::size_t LhsLimbs, std::size_t RhsLimbs>
NOINLINE UIntFixed<LhsLimbs + RhsLimbs> multiply_unsigned(
    const UIntFixed<LhsLimbs>& lhs,
    const UIntFixed<RhsLimbs>& rhs
) noexcept {
    UIntFixed<LhsLimbs + RhsLimbs> result;

    const std::size_t lhs_first =
        first_non_zero_limb(lhs);

    if (lhs_first == LhsLimbs)
        return result;

    const std::size_t rhs_first =
        first_non_zero_limb(rhs);

    if (rhs_first == RhsLimbs)
        return result;

    const std::size_t lhs_end =
        past_last_non_zero_limb(lhs);

    const std::size_t rhs_end =
        past_last_non_zero_limb(rhs);

    for (std::size_t i = lhs_first; i < lhs_end; ++i) {
        const std::uint32_t lhs_word =
            lhs.limb[i];

        if (lhs_word == 0)
            continue;

        std::uint64_t carry = 0;

        for (std::size_t j = rhs_first; j < rhs_end; ++j) {
            const std::size_t index = i + j;

            const std::uint64_t accumulated =
                static_cast<std::uint64_t>(lhs_word) *
                    static_cast<std::uint64_t>(rhs.limb[j])
                + static_cast<std::uint64_t>(
                    result.limb[index]
                )
                + carry;

            result.limb[index] =
                static_cast<std::uint32_t>(accumulated);

            carry = accumulated >> 32;
        }

        const std::size_t carry_index =
            i + rhs_end;

        result.limb[carry_index] =
            static_cast<std::uint32_t>(carry);
    }

    return result;
}

constexpr std::size_t dyadic_coordinate_limbs = 66;
constexpr std::size_t dyadic_product_limbs =
    2 * dyadic_coordinate_limbs;

using DyadicCoordinateMagnitude =
    UIntFixed<dyadic_coordinate_limbs>;

using DyadicProductMagnitude =
    UIntFixed<dyadic_product_limbs>;

struct SignedDyadicCoordinate {
    int sign = 0;
    DyadicCoordinateMagnitude magnitude;
};

struct SignedDyadicDifference {
    int sign = 0;
    DyadicCoordinateMagnitude magnitude;
};

struct SignedDyadicProduct {
    int sign = 0;
    DyadicProductMagnitude magnitude;
};

ALWAYS_INLINE void set_shifted_unsigned64(
    DyadicCoordinateMagnitude& result,
    std::uint64_t mantissa,
    std::uint32_t shift
) noexcept {
    const std::size_t base = shift / 32;
    const std::uint32_t offset = shift % 32;

    const std::uint32_t lower =
        static_cast<std::uint32_t>(mantissa);

    const std::uint32_t upper =
        static_cast<std::uint32_t>(mantissa >> 32);

    const std::uint64_t shifted_lower =
        static_cast<std::uint64_t>(lower) << offset;

    result.limb[base] |=
        static_cast<std::uint32_t>(shifted_lower);

    if (base + 1 < dyadic_coordinate_limbs) {
        result.limb[base + 1] |=
            static_cast<std::uint32_t>(shifted_lower >> 32);
    }

    if (upper != 0) {
        const std::uint64_t shifted_upper =
            static_cast<std::uint64_t>(upper) << offset;

        result.limb[base + 1] |=
            static_cast<std::uint32_t>(shifted_upper);

        if (base + 2 < dyadic_coordinate_limbs) {
            result.limb[base + 2] |=
                static_cast<std::uint32_t>(
                    shifted_upper >> 32
                );
        }
    }
}

NOINLINE SignedDyadicCoordinate decode_binary64_coordinate(
    double value
) noexcept {
    const std::uint64_t representation =
        bits_of(value);

    const std::uint64_t fraction =
        representation &
        0x000f'ffff'ffff'ffffULL;

    const std::uint32_t raw_exponent =
        static_cast<std::uint32_t>(
            (representation >> 52) & 0x7ffULL
        );

    std::uint64_t mantissa;
    std::uint32_t shift;

    if (raw_exponent == 0) {
        mantissa = fraction;
        shift = 0;
    } else {
        mantissa =
            (1ULL << 52) |
            fraction;

        shift =
            raw_exponent - 1;
    }

    SignedDyadicCoordinate result;

    if (mantissa == 0)
        return result;

    result.sign =
        (representation >> 63) != 0
            ? -1
            : 1;

    set_shifted_unsigned64(
        result.magnitude,
        mantissa,
        shift
    );

    return result;
}

NOINLINE SignedDyadicDifference subtract_dyadic_coordinates(
    const SignedDyadicCoordinate& lhs,
    const SignedDyadicCoordinate& rhs
) noexcept {
    SignedDyadicDifference result;

    if (lhs.sign == 0) {
        result.sign = -rhs.sign;
        result.magnitude = rhs.magnitude;
        return result;
    }

    if (rhs.sign == 0) {
        result.sign = lhs.sign;
        result.magnitude = lhs.magnitude;
        return result;
    }

    if (lhs.sign != rhs.sign) {
        result.sign = lhs.sign;
        result.magnitude =
            add_unsigned(lhs.magnitude, rhs.magnitude);
        return result;
    }

    const int comparison =
        compare_unsigned(lhs.magnitude, rhs.magnitude);

    if (comparison == 0)
        return result;

    if (comparison > 0) {
        result.sign = lhs.sign;
        result.magnitude =
            subtract_unsigned(lhs.magnitude, rhs.magnitude);
    } else {
        result.sign = -lhs.sign;
        result.magnitude =
            subtract_unsigned(rhs.magnitude, lhs.magnitude);
    }

    return result;
}

ALWAYS_INLINE SignedDyadicProduct multiply_dyadic_differences(
    const SignedDyadicDifference& lhs,
    const SignedDyadicDifference& rhs
) noexcept {
    SignedDyadicProduct result;

    if (lhs.sign == 0 || rhs.sign == 0)
        return result;

    result.sign =
        lhs.sign == rhs.sign
            ? 1
            : -1;

    result.magnitude =
        multiply_unsigned(lhs.magnitude, rhs.magnitude);

    return result;
}

NOINLINE SignedDyadicProduct subtract_dyadic_products(
    const SignedDyadicProduct& lhs,
    const SignedDyadicProduct& rhs
) noexcept {
    SignedDyadicProduct result;

    if (lhs.sign == 0) {
        result.sign = -rhs.sign;
        result.magnitude = rhs.magnitude;
        return result;
    }

    if (rhs.sign == 0) {
        result.sign = lhs.sign;
        result.magnitude = lhs.magnitude;
        return result;
    }

    if (lhs.sign != rhs.sign) {
        result.sign = lhs.sign;
        result.magnitude =
            add_unsigned(lhs.magnitude, rhs.magnitude);
        return result;
    }

    const int comparison =
        compare_unsigned(lhs.magnitude, rhs.magnitude);

    if (comparison == 0)
        return result;

    if (comparison > 0) {
        result.sign = lhs.sign;
        result.magnitude =
            subtract_unsigned(lhs.magnitude, rhs.magnitude);
    } else {
        result.sign = -lhs.sign;
        result.magnitude =
            subtract_unsigned(rhs.magnitude, lhs.magnitude);
    }

    return result;
}

/*
 * Match the observed D cold path: this large exact determinant remains
 * out-of-line.
 */
NOINLINE SignedDyadicProduct orientation_determinant_dyadic(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy
) noexcept {
    const auto a_x = decode_binary64_coordinate(ax);
    const auto a_y = decode_binary64_coordinate(ay);
    const auto b_x = decode_binary64_coordinate(bx);
    const auto b_y = decode_binary64_coordinate(by);
    const auto c_x = decode_binary64_coordinate(cx);
    const auto c_y = decode_binary64_coordinate(cy);

    const auto b_ax =
        subtract_dyadic_coordinates(b_x, a_x);

    const auto b_ay =
        subtract_dyadic_coordinates(b_y, a_y);

    const auto c_ax =
        subtract_dyadic_coordinates(c_x, a_x);

    const auto c_ay =
        subtract_dyadic_coordinates(c_y, a_y);

    const auto p =
        multiply_dyadic_differences(b_ax, c_ay);

    const auto q =
        multiply_dyadic_differences(b_ay, c_ax);

    return subtract_dyadic_products(p, q);
}

ALWAYS_INLINE bool all_finite(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy
) noexcept {
    return is_finite(ax) &&
           is_finite(ay) &&
           is_finite(bx) &&
           is_finite(by) &&
           is_finite(cx) &&
           is_finite(cy);
}

/*
 * Explicit hot/cold split matching the current geo-d experiment.
 */
NOINLINE bool robust_double_fallback(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
    int& sign
) noexcept {
    sign = 0;

    if (try_orientation_exact_expansion(
            ax, ay,
            bx, by,
            cx, cy,
            sign))
    {
        return true;
    }

    if (!all_finite(
            ax, ay,
            bx, by,
            cx, cy))
    {
        return false;
    }

    const auto determinant =
        orientation_determinant_dyadic(
            ax, ay,
            bx, by,
            cx, cy
        );

    sign = determinant.sign;
    return true;
}

ALWAYS_INLINE Orientation from_sign(int sign) noexcept {
    if (sign > 0)
        return Orientation::left;

    if (sign < 0)
        return Orientation::right;

    return Orientation::collinear;
}

ALWAYS_INLINE Orientation orientation_double(
    Point2<double> a,
    Point2<double> b,
    Point2<double> c
) noexcept {
    const auto filtered =
        orientation_filter(
            a.x, a.y,
            b.x, b.y,
            c.x, c.y
        );

    switch (filtered) {
        case OrientationFilterResult::right:
            return Orientation::right;

        case OrientationFilterResult::collinear:
            return Orientation::collinear;

        case OrientationFilterResult::left:
            return Orientation::left;

        case OrientationFilterResult::uncertain:
            break;
    }

    int sign = 0;

    const bool success =
        robust_double_fallback(
            a.x, a.y,
            b.x, b.y,
            c.x, c.y,
            sign
        );

    if (!success)
        std::abort();

    return from_sign(sign);
}

ALWAYS_INLINE std::uint64_t encode(Orientation value) noexcept {
    return static_cast<std::uint64_t>(
        static_cast<int>(value) + 1
    );
}

static void prepare_cases() {
    using PD = Point2<double>;

    double_fast_cases[0] = {
        PD{0.0, 0.0},
        PD{10.0, 0.0},
        PD{5.0, 1.0}
    };

    double_fast_cases[1] = {
        PD{0.0, 0.0},
        PD{10.0, 0.0},
        PD{5.0, -1.0}
    };

    double_expansion_collinear_cases[0] = {
        PD{0.0, 0.0},
        PD{10.0, 10.0},
        PD{5.0, 5.0}
    };

    double_expansion_collinear_cases[1] = {
        PD{1.0, 1.0},
        PD{11.0, 11.0},
        PD{6.0, 6.0}
    };

    double_expansion_near_cases[0] = {
        PD{0.0, 0.0},
        PD{10.0, 10.0},
        PD{5.0, 0x1.4000000000001p+2}
    };

    double_expansion_near_cases[1] = {
        PD{0.0, 0.0},
        PD{10.0, 10.0},
        PD{5.0, 0x1.3ffffffffffffp+2}
    };

    constexpr double large = 0x1p+500;
    constexpr double half = 0x1p+499;
    constexpr double half_next = 0x1.0000000000001p+499;
    constexpr double half_previous = 0x1.fffffffffffffp+498;

    double_dyadic_collinear_cases[0] = {
        PD{0.0, 0.0},
        PD{large, large},
        PD{half, half}
    };

    double_dyadic_collinear_cases[1] = {
        PD{0.0, 0.0},
        PD{-large, -large},
        PD{-half, -half}
    };

    double_dyadic_near_cases[0] = {
        PD{0.0, 0.0},
        PD{large, large},
        PD{half, half_next}
    };

    double_dyadic_near_cases[1] = {
        PD{0.0, 0.0},
        PD{large, large},
        PD{half, half_previous}
    };

    constexpr double min_subnormal = 0x0.0000000000001p-1022;

    double_subnormal_cases[0] = {
        PD{0.0, 0.0},
        PD{min_subnormal, 0.0},
        PD{0.0, min_subnormal}
    };

    double_subnormal_cases[1] = {
        PD{0.0, 0.0},
        PD{0.0, min_subnormal},
        PD{min_subnormal, 0.0}
    };
}

static void require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "SELF-TEST FAILED: %s\n", message);
        std::exit(2);
    }
}

static void self_test() {
    using R = OrientationFilterResult;

    require(
        orientation_filter(0.0, 0.0, 10.0, 0.0, 5.0, 1.0)
            == R::left,
        "filter left"
    );

    require(
        orientation_filter(0.0, 0.0, 10.0, 0.0, 5.0, -1.0)
            == R::right,
        "filter right"
    );

    require(
        orientation_filter(0.0, 0.0, 10.0, 10.0, 5.0, 5.0)
            == R::uncertain,
        "filter diagonal collinear -> uncertain"
    );

    int sign = 0;

    require(
        try_orientation_exact_expansion(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 5.0,
            sign
        ) && sign == 0,
        "expansion diagonal collinear"
    );

    require(
        try_orientation_exact_expansion(
            0.0, 0.0,
            10.0, 10.0,
            5.0, 0x1.4000000000001p+2,
            sign
        ) && sign > 0,
        "expansion one ulp above"
    );

    constexpr double large = 0x1p+500;
    constexpr double half = 0x1p+499;
    constexpr double half_next = 0x1.0000000000001p+499;

    require(
        !try_orientation_exact_expansion(
            0.0, 0.0,
            large, large,
            half, half,
            sign
        ),
        "expansion rejects dyadic collinear case"
    );

    require(
        orientation_determinant_dyadic(
            0.0, 0.0,
            large, large,
            half, half
        ).sign == 0,
        "dyadic collinear"
    );

    require(
        orientation_determinant_dyadic(
            0.0, 0.0,
            large, large,
            half, half_next
        ).sign > 0,
        "dyadic near"
    );

    constexpr double min_subnormal = 0x0.0000000000001p-1022;

    require(
        orientation_determinant_dyadic(
            0.0, 0.0,
            min_subnormal, 0.0,
            0.0, min_subnormal
        ).sign > 0,
        "dyadic minimum subnormal"
    );

    require(
        orientation_determinant_dyadic(
            -std::numeric_limits<double>::max(), 0.0,
             std::numeric_limits<double>::max(), 0.0,
             0.0, 1.0
        ).sign > 0,
        "dyadic subtraction overflow range"
    );

    require(
        orientation_determinant_dyadic(
            -std::numeric_limits<double>::max(),
            -std::numeric_limits<double>::max(),
             std::numeric_limits<double>::max(),
             std::numeric_limits<double>::max(),
             0.0,
             0.0
        ).sign == 0,
        "dyadic full finite range collinear"
    );

    require(
        orientation_double(
            {0.0, 0.0},
            {10.0, 0.0},
            {5.0, 1.0}
        ) == Orientation::left,
        "public fast left"
    );

    require(
        orientation_double(
            {0.0, 0.0},
            {10.0, 10.0},
            {5.0, 5.0}
        ) == Orientation::collinear,
        "public expansion collinear"
    );

    require(
        orientation_double(
            {0.0, 0.0},
            {large, large},
            {half, half_next}
        ) == Orientation::left,
        "public dyadic near"
    );
}

NOINLINE std::uint64_t bench_double_fast(std::size_t i) noexcept {
    const auto value = double_fast_cases[i & 1];
    return encode(
        orientation_double(value.a, value.b, value.c)
    );
}

NOINLINE std::uint64_t bench_double_expansion_collinear(
    std::size_t i
) noexcept {
    const auto value =
        double_expansion_collinear_cases[i & 1];

    return encode(
        orientation_double(value.a, value.b, value.c)
    );
}

NOINLINE std::uint64_t bench_double_expansion_near(
    std::size_t i
) noexcept {
    const auto value =
        double_expansion_near_cases[i & 1];

    return encode(
        orientation_double(value.a, value.b, value.c)
    );
}

NOINLINE std::uint64_t bench_double_dyadic_collinear(
    std::size_t i
) noexcept {
    const auto value =
        double_dyadic_collinear_cases[i & 1];

    return encode(
        orientation_double(value.a, value.b, value.c)
    );
}

NOINLINE std::uint64_t bench_double_dyadic_near(
    std::size_t i
) noexcept {
    const auto value =
        double_dyadic_near_cases[i & 1];

    return encode(
        orientation_double(value.a, value.b, value.c)
    );
}

NOINLINE std::uint64_t bench_double_dyadic_subnormal(
    std::size_t i
) noexcept {
    const auto value =
        double_subnormal_cases[i & 1];

    return encode(
        orientation_double(value.a, value.b, value.c)
    );
}

template <typename Operation>
static void run_benchmark(
    const char* name,
    std::size_t iterations,
    Operation operation
) {
    std::uint64_t local_sink = 0;

    for (std::size_t i = 0; i < warmup_iterations; ++i)
        local_sink += operation(i);

    std::array<std::int64_t, repetitions> samples{};

    for (std::size_t sample = 0; sample < repetitions; ++sample) {
        const auto start =
            std::chrono::steady_clock::now();

        for (std::size_t i = 0; i < iterations; ++i)
            local_sink += operation(i);

        const auto stop =
            std::chrono::steady_clock::now();

        samples[sample] =
            std::chrono::duration_cast<std::chrono::nanoseconds>(
                stop - start
            ).count();
    }

    benchmark_sink ^= local_sink;

    std::sort(samples.begin(), samples.end());

    const double median =
        static_cast<double>(samples[repetitions / 2]) /
        static_cast<double>(iterations);

    const double minimum =
        static_cast<double>(samples.front()) /
        static_cast<double>(iterations);

    const double maximum =
        static_cast<double>(samples.back()) /
        static_cast<double>(iterations);

    std::printf(
        "%-31s %10.2f ns/op   min=%8.2f   max=%8.2f   n=%zu\n",
        name,
        median,
        minimum,
        maximum,
        iterations
    );
}

int main() {
    prepare_cases();
    self_test();

    std::puts("C++ algorithm-equivalent robust orientation(double) benchmark");
    std::puts("median of 7 measured runs");

    run_benchmark(
        "double filter fast",
        cheap_iterations,
        bench_double_fast
    );

    run_benchmark(
        "double expansion collinear",
        expansion_iterations,
        bench_double_expansion_collinear
    );

    run_benchmark(
        "double expansion near",
        expansion_iterations,
        bench_double_expansion_near
    );

    run_benchmark(
        "double dyadic collinear",
        dyadic_iterations,
        bench_double_dyadic_collinear
    );

    run_benchmark(
        "double dyadic near",
        dyadic_iterations,
        bench_double_dyadic_near
    );

    run_benchmark(
        "double dyadic subnormal",
        dyadic_iterations,
        bench_double_dyadic_subnormal
    );

    std::printf("\nsink: %llu\n",
        static_cast<unsigned long long>(benchmark_sink));

    return 0;
}
