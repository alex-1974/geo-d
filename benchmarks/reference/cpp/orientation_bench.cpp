/*
 * Diagnostic C++ reference for benchmarks/orientation_bench.d.
 *
 * Comparable cases:
 *
 *   int
 *       Same exact signed-difference/product algorithm.
 *
 *   long manual
 *       Portable 32-bit-limb 64 x 64 -> 128 implementation corresponding
 *       to geo-d's non-LDC fallback.
 *
 *   long native u128
 *       Native wide-integer analogue of geo-d's LDC core.int128 path.
 *
 *   double certified filter
 *       First-stage certified filter only. It is not a complete robust
 *       orientation predicate because expansion and dyadic fallbacks are
 *       intentionally absent.
 *
 *   double naive
 *       Non-robust arithmetic baseline only.
 *
 * The C++ algorithms are inline and may be folded into the NOINLINE
 * benchmark wrappers. Therefore these measurements are useful compiler
 * and code-generation references, but they do not guarantee identical
 * public-call overhead to geo-d.
 */
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <limits>


constexpr std::size_t repetitions = 7;
constexpr std::size_t warmup_iterations = 1'000'000;

constexpr std::size_t cheap_iterations = 20'000'000;


#if defined(__GNUC__) || defined(__clang__)
#define NOINLINE __attribute__((noinline))
#else
#define NOINLINE
#endif


enum class Orientation : std::int8_t
{
    right     = -1,
    collinear =  0,
    left      =  1
};


template <typename T>
struct Point2
{
    T x;
    T y;
};


template <typename T>
struct OrientationCase
{
    Point2<T> a;
    Point2<T> b;
    Point2<T> c;
};


static std::uint64_t benchmark_sink;


static std::array<OrientationCase<std::int32_t>, 2>
    int_ordinary_cases;

static std::array<OrientationCase<std::int32_t>, 2>
    int_extreme_cases;

static std::array<OrientationCase<std::int64_t>, 2>
    long_ordinary_cases;

static std::array<OrientationCase<std::int64_t>, 2>
    long_extreme_cases;

static std::array<OrientationCase<double>, 2>
    double_fast_cases;

static std::array<OrientationCase<float>, 2>
    float_fast_cases;


static inline std::uint64_t encode(Orientation value)
{
    return static_cast<std::uint64_t>(
        static_cast<int>(value) + 1
    );
}


struct SignedDiff32
{
    int sign;
    std::uint32_t magnitude;
};


struct SignedDiff64
{
    int sign;
    std::uint64_t magnitude;
};


struct SignedProduct64
{
    int sign;
    std::uint64_t magnitude;
};


struct Unsigned128
{
    std::uint64_t hi;
    std::uint64_t lo;
};


struct SignedProduct128
{
    int sign;
    Unsigned128 magnitude;
};


static inline std::uint32_t unsigned_magnitude(
    std::int32_t value
)
{
    if (value >= 0)
        return static_cast<std::uint32_t>(value);

    return
        static_cast<std::uint32_t>(-(value + 1)) +
        std::uint32_t{1};
}


static inline std::uint64_t unsigned_magnitude(
    std::int64_t value
)
{
    if (value >= 0)
        return static_cast<std::uint64_t>(value);

    return
        static_cast<std::uint64_t>(-(value + 1)) +
        std::uint64_t{1};
}


static inline SignedDiff32 signed_difference(
    std::int32_t a,
    std::int32_t b
)
{
    if (a == b)
        return {0, 0};

    const int sign =
        a > b ? 1 : -1;

    std::uint32_t magnitude;

    if ((a < 0) != (b < 0))
    {
        magnitude =
            unsigned_magnitude(a) +
            unsigned_magnitude(b);
    }
    else if (a > b)
    {
        magnitude =
            static_cast<std::uint32_t>(a - b);
    }
    else
    {
        magnitude =
            static_cast<std::uint32_t>(b - a);
    }

    return {sign, magnitude};
}


static inline SignedDiff64 signed_difference(
    std::int64_t a,
    std::int64_t b
)
{
    if (a == b)
        return {0, 0};

    const int sign =
        a > b ? 1 : -1;

    std::uint64_t magnitude;

    if ((a < 0) != (b < 0))
    {
        magnitude =
            unsigned_magnitude(a) +
            unsigned_magnitude(b);
    }
    else if (a > b)
    {
        magnitude =
            static_cast<std::uint64_t>(a - b);
    }
    else
    {
        magnitude =
            static_cast<std::uint64_t>(b - a);
    }

    return {sign, magnitude};
}


static inline SignedProduct64 multiply(
    SignedDiff32 lhs,
    SignedDiff32 rhs
)
{
    if (lhs.sign == 0 || rhs.sign == 0)
        return {0, 0};

    const int sign =
        lhs.sign == rhs.sign ? 1 : -1;

    return {
        sign,
        static_cast<std::uint64_t>(lhs.magnitude) *
            static_cast<std::uint64_t>(rhs.magnitude)
    };
}


static inline Unsigned128 multiply_unsigned_64(
    std::uint64_t lhs,
    std::uint64_t rhs
)
{
    constexpr std::uint64_t mask32 =
        0xffff'ffffULL;

    const std::uint64_t lhs_lo =
        lhs & mask32;

    const std::uint64_t lhs_hi =
        lhs >> 32;

    const std::uint64_t rhs_lo =
        rhs & mask32;

    const std::uint64_t rhs_hi =
        rhs >> 32;


    const std::uint64_t w0 =
        lhs_lo * rhs_lo;

    const std::uint64_t t =
        lhs_hi * rhs_lo +
        (w0 >> 32);

    const std::uint64_t w1_low =
        t & mask32;

    const std::uint64_t w2 =
        t >> 32;

    const std::uint64_t w1 =
        lhs_lo * rhs_hi +
        w1_low;

    const std::uint64_t hi =
        lhs_hi * rhs_hi +
        w2 +
        (w1 >> 32);

    const std::uint64_t lo =
        ((w1 & mask32) << 32) |
        (w0 & mask32);

    return {hi, lo};
}


static inline SignedProduct128 multiply_manual(
    SignedDiff64 lhs,
    SignedDiff64 rhs
)
{
    if (lhs.sign == 0 || rhs.sign == 0)
        return {0, {0, 0}};

    const int sign =
        lhs.sign == rhs.sign ? 1 : -1;

    return {
        sign,
        multiply_unsigned_64(
            lhs.magnitude,
            rhs.magnitude
        )
    };
}


static inline int compare_unsigned_128(
    Unsigned128 lhs,
    Unsigned128 rhs
)
{
    if (lhs.hi < rhs.hi)
        return -1;

    if (lhs.hi > rhs.hi)
        return 1;

    if (lhs.lo < rhs.lo)
        return -1;

    if (lhs.lo > rhs.lo)
        return 1;

    return 0;
}


static inline int difference_sign(
    SignedProduct64 p,
    SignedProduct64 q
)
{
    if (p.sign == 0)
        return -q.sign;

    if (q.sign == 0)
        return p.sign;

    if (p.sign != q.sign)
        return p.sign;

    if (p.magnitude == q.magnitude)
        return 0;

    if (p.sign > 0)
        return
            p.magnitude > q.magnitude
                ? 1
                : -1;

    return
        p.magnitude < q.magnitude
            ? 1
            : -1;
}


static inline int difference_sign(
    SignedProduct128 p,
    SignedProduct128 q
)
{
    if (p.sign == 0)
        return -q.sign;

    if (q.sign == 0)
        return p.sign;

    if (p.sign != q.sign)
        return p.sign;

    const int comparison =
        compare_unsigned_128(
            p.magnitude,
            q.magnitude
        );

    if (comparison == 0)
        return 0;

    return
        p.sign > 0
            ? comparison
            : -comparison;
}


static inline Orientation from_sign(int sign)
{
    if (sign > 0)
        return Orientation::left;

    if (sign < 0)
        return Orientation::right;

    return Orientation::collinear;
}


static inline Orientation orientation_int(
    Point2<std::int32_t> a,
    Point2<std::int32_t> b,
    Point2<std::int32_t> c
)
{
    const auto bax =
        signed_difference(b.x, a.x);

    const auto bay =
        signed_difference(b.y, a.y);

    const auto cax =
        signed_difference(c.x, a.x);

    const auto cay =
        signed_difference(c.y, a.y);

    const auto p =
        multiply(bax, cay);

    const auto q =
        multiply(bay, cax);

    return from_sign(
        difference_sign(p, q)
    );
}


static inline Orientation orientation_long_manual(
    Point2<std::int64_t> a,
    Point2<std::int64_t> b,
    Point2<std::int64_t> c
)
{
    const auto bax =
        signed_difference(b.x, a.x);

    const auto bay =
        signed_difference(b.y, a.y);

    const auto cax =
        signed_difference(c.x, a.x);

    const auto cay =
        signed_difference(c.y, a.y);

    const auto p =
        multiply_manual(bax, cay);

    const auto q =
        multiply_manual(bay, cax);

    return from_sign(
        difference_sign(p, q)
    );
}


struct SignedProductNative128
{
    int sign;
    unsigned __int128 magnitude;
};


static inline SignedProductNative128 multiply_native(
    SignedDiff64 lhs,
    SignedDiff64 rhs
)
{
    if (lhs.sign == 0 || rhs.sign == 0)
        return {0, 0};

    return {
        lhs.sign == rhs.sign ? 1 : -1,
        static_cast<unsigned __int128>(
            lhs.magnitude
        ) *
        static_cast<unsigned __int128>(
            rhs.magnitude
        )
    };
}


static inline int difference_sign(
    SignedProductNative128 p,
    SignedProductNative128 q
)
{
    if (p.sign == 0)
        return -q.sign;

    if (q.sign == 0)
        return p.sign;

    if (p.sign != q.sign)
        return p.sign;

    if (p.magnitude == q.magnitude)
        return 0;

    if (p.sign > 0)
        return
            p.magnitude > q.magnitude
                ? 1
                : -1;

    return
        p.magnitude < q.magnitude
            ? 1
            : -1;
}


static inline Orientation orientation_long_native(
    Point2<std::int64_t> a,
    Point2<std::int64_t> b,
    Point2<std::int64_t> c
)
{
    const auto bax =
        signed_difference(b.x, a.x);

    const auto bay =
        signed_difference(b.y, a.y);

    const auto cax =
        signed_difference(c.x, a.x);

    const auto cay =
        signed_difference(c.y, a.y);

    const auto p =
        multiply_native(bax, cay);

    const auto q =
        multiply_native(bay, cax);

    return from_sign(
        difference_sign(p, q)
    );
}


enum class FilterResult : std::int8_t
{
    right     = -1,
    collinear =  0,
    left      =  1,
    uncertain =  2
};


constexpr double ccw_errbound_a =
    0x1.8000000000004p-52;


static inline bool normal_or_zero(double value)
{
    return
        value == 0.0 ||
        (
            std::isfinite(value) &&
            std::fpclassify(value) != FP_SUBNORMAL
        );
}


static inline bool product_underflowed(
    double lhs,
    double rhs,
    double product
)
{
    return
        product == 0.0 &&
        lhs != 0.0 &&
        rhs != 0.0;
}


static inline FilterResult orientation_filter(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy
)
{
    if (!std::isfinite(ax) ||
        !std::isfinite(ay) ||
        !std::isfinite(bx) ||
        !std::isfinite(by) ||
        !std::isfinite(cx) ||
        !std::isfinite(cy))
    {
        return FilterResult::uncertain;
    }


    const double acx =
        ax - cx;

    const double bcx =
        bx - cx;

    const double acy =
        ay - cy;

    const double bcy =
        by - cy;


    if (!normal_or_zero(acx) ||
        !normal_or_zero(bcx) ||
        !normal_or_zero(acy) ||
        !normal_or_zero(bcy))
    {
        return FilterResult::uncertain;
    }


    const double detleft =
        acx * bcy;

    const double detright =
        acy * bcx;


    if (product_underflowed(
            acx,
            bcy,
            detleft
        ) ||
        product_underflowed(
            acy,
            bcx,
            detright
        ))
    {
        return FilterResult::uncertain;
    }


    if (!normal_or_zero(detleft) ||
        !normal_or_zero(detright))
    {
        return FilterResult::uncertain;
    }


    double detsum;


    if (detleft > 0.0)
    {
        if (detright <= 0.0)
            return FilterResult::left;

        detsum =
            detleft + detright;
    }
    else if (detleft < 0.0)
    {
        if (detright >= 0.0)
            return FilterResult::right;

        detsum =
            -detleft - detright;
    }
    else
    {
        if (detright > 0.0)
            return FilterResult::right;

        if (detright < 0.0)
            return FilterResult::left;

        return FilterResult::collinear;
    }


    if (!std::isfinite(detsum) ||
        std::fpclassify(detsum) == FP_SUBNORMAL)
    {
        return FilterResult::uncertain;
    }


    const double det =
        detleft - detright;


    if (!std::isfinite(det) ||
        (
            det != 0.0 &&
            std::fpclassify(det) == FP_SUBNORMAL
        ))
    {
        return FilterResult::uncertain;
    }


    const double errbound =
        ccw_errbound_a * detsum;


    if (!std::isfinite(errbound) ||
        errbound == 0.0 ||
        std::fpclassify(errbound) == FP_SUBNORMAL)
    {
        return FilterResult::uncertain;
    }


    if (det >= errbound)
        return FilterResult::left;

    if (-det >= errbound)
        return FilterResult::right;

    return FilterResult::uncertain;
}


static inline Orientation orientation_double_filter(
    Point2<double> a,
    Point2<double> b,
    Point2<double> c
)
{
    const auto result =
        orientation_filter(
            a.x, a.y,
            b.x, b.y,
            c.x, c.y
        );

    switch (result)
    {
        case FilterResult::right:
            return Orientation::right;

        case FilterResult::collinear:
            return Orientation::collinear;

        case FilterResult::left:
            return Orientation::left;

        case FilterResult::uncertain:
            /*
             * The benchmark datasets for this function are deliberately
             * certified by the first-stage filter.
             *
             * The robust C++ fallbacks will be added separately.
             */
            return Orientation::collinear;
    }

    return Orientation::collinear;
}


static inline Orientation orientation_double_naive(
    Point2<double> a,
    Point2<double> b,
    Point2<double> c
)
{
    const double bax =
        b.x - a.x;

    const double bay =
        b.y - a.y;

    const double cax =
        c.x - a.x;

    const double cay =
        c.y - a.y;

    const double determinant =
        bax * cay -
        bay * cax;

    if (determinant > 0.0)
        return Orientation::left;

    if (determinant < 0.0)
        return Orientation::right;

    return Orientation::collinear;
}


static void prepare_cases()
{
    int_ordinary_cases[0] = {
        {0, 0},
        {10, 0},
        {5, 1}
    };

    int_ordinary_cases[1] = {
        {1, 1},
        {11, 1},
        {6, 0}
    };


    int_extreme_cases[0] = {
        {
            std::numeric_limits<std::int32_t>::min(),
            std::numeric_limits<std::int32_t>::min()
        },
        {
            std::numeric_limits<std::int32_t>::max(),
            std::numeric_limits<std::int32_t>::min()
        },
        {
            std::numeric_limits<std::int32_t>::min(),
            std::numeric_limits<std::int32_t>::max()
        }
    };

    int_extreme_cases[1] = {
        {
            std::numeric_limits<std::int32_t>::max(),
            std::numeric_limits<std::int32_t>::max()
        },
        {
            std::numeric_limits<std::int32_t>::min(),
            std::numeric_limits<std::int32_t>::max()
        },
        {
            std::numeric_limits<std::int32_t>::max(),
            std::numeric_limits<std::int32_t>::min()
        }
    };


    long_ordinary_cases[0] = {
        {0, 0},
        {10, 0},
        {5, 1}
    };

    long_ordinary_cases[1] = {
        {1, 1},
        {11, 1},
        {6, 0}
    };


    long_extreme_cases[0] = {
        {
            std::numeric_limits<std::int64_t>::min(),
            std::numeric_limits<std::int64_t>::min()
        },
        {
            std::numeric_limits<std::int64_t>::max(),
            std::numeric_limits<std::int64_t>::min()
        },
        {
            std::numeric_limits<std::int64_t>::min(),
            std::numeric_limits<std::int64_t>::max()
        }
    };

    long_extreme_cases[1] = {
        {
            std::numeric_limits<std::int64_t>::max(),
            std::numeric_limits<std::int64_t>::max()
        },
        {
            std::numeric_limits<std::int64_t>::min(),
            std::numeric_limits<std::int64_t>::max()
        },
        {
            std::numeric_limits<std::int64_t>::max(),
            std::numeric_limits<std::int64_t>::min()
        }
    };


    double_fast_cases[0] = {
        {0.0, 0.0},
        {10.0, 0.0},
        {5.0, 1.0}
    };

    double_fast_cases[1] = {
        {0.0, 0.0},
        {10.0, 0.0},
        {5.0, -1.0}
    };


    float_fast_cases[0] = {
        {0.0f, 0.0f},
        {10.0f, 0.0f},
        {5.0f, 1.0f}
    };

    float_fast_cases[1] = {
        {0.0f, 0.0f},
        {10.0f, 0.0f},
        {5.0f, -1.0f}
    };
}


template <typename Operation>
static void run_benchmark(
    const char* name,
    Operation operation,
    std::size_t iterations
)
{
    std::uint64_t local_sink = 0;


    for (std::size_t i = 0; i < warmup_iterations; ++i)
        local_sink += operation(i);


    std::array<long long, repetitions> samples{};


    for (std::size_t sample = 0;
         sample < repetitions;
         ++sample)
    {
        const auto start =
            std::chrono::steady_clock::now();

        for (std::size_t i = 0; i < iterations; ++i)
            local_sink += operation(i);

        const auto stop =
            std::chrono::steady_clock::now();


        samples[sample] =
            std::chrono::duration_cast<
                std::chrono::nanoseconds
            >(stop - start).count();
    }


    benchmark_sink ^= local_sink;

    std::sort(
        samples.begin(),
        samples.end()
    );


    const double median =
        static_cast<double>(
            samples[repetitions / 2]
        ) /
        static_cast<double>(iterations);

    const double minimum =
        static_cast<double>(
            samples.front()
        ) /
        static_cast<double>(iterations);

    const double maximum =
        static_cast<double>(
            samples.back()
        ) /
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


NOINLINE static std::uint64_t bench_int_ordinary(
    std::size_t i
)
{
    const auto value =
        int_ordinary_cases[i & 1];

    return encode(
        orientation_int(
            value.a,
            value.b,
            value.c
        )
    );
}


NOINLINE static std::uint64_t bench_int_extreme(
    std::size_t i
)
{
    const auto value =
        int_extreme_cases[i & 1];

    return encode(
        orientation_int(
            value.a,
            value.b,
            value.c
        )
    );
}


NOINLINE static std::uint64_t bench_long_manual_ordinary(
    std::size_t i
)
{
    const auto value =
        long_ordinary_cases[i & 1];

    return encode(
        orientation_long_manual(
            value.a,
            value.b,
            value.c
        )
    );
}


NOINLINE static std::uint64_t bench_long_manual_extreme(
    std::size_t i
)
{
    const auto value =
        long_extreme_cases[i & 1];

    return encode(
        orientation_long_manual(
            value.a,
            value.b,
            value.c
        )
    );
}


NOINLINE static std::uint64_t bench_long_native_ordinary(
    std::size_t i
)
{
    const auto value =
        long_ordinary_cases[i & 1];

    return encode(
        orientation_long_native(
            value.a,
            value.b,
            value.c
        )
    );
}


NOINLINE static std::uint64_t bench_long_native_extreme(
    std::size_t i
)
{
    const auto value =
        long_extreme_cases[i & 1];

    return encode(
        orientation_long_native(
            value.a,
            value.b,
            value.c
        )
    );
}


NOINLINE static std::uint64_t bench_double_naive(
    std::size_t i
)
{
    const auto value =
        double_fast_cases[i & 1];

    return encode(
        orientation_double_naive(
            value.a,
            value.b,
            value.c
        )
    );
}


NOINLINE static std::uint64_t bench_double_filter(
    std::size_t i
)
{
    const auto value =
        double_fast_cases[i & 1];

    return encode(
        orientation_double_filter(
            value.a,
            value.b,
            value.c
        )
    );
}


int main()
{
    prepare_cases();

    std::printf("C++ orientation reference benchmark\n");
    std::printf(
        "median of %zu measured runs\n\n",
        repetitions
    );


    run_benchmark(
        "int same algorithm ordinary",
        bench_int_ordinary,
        cheap_iterations
    );

    run_benchmark(
        "int same algorithm full-range",
        bench_int_extreme,
        cheap_iterations
    );


    run_benchmark(
        "long manual ordinary",
        bench_long_manual_ordinary,
        cheap_iterations
    );

    run_benchmark(
        "long manual full-range",
        bench_long_manual_extreme,
        cheap_iterations
    );


    run_benchmark(
        "long native u128 ordinary",
        bench_long_native_ordinary,
        cheap_iterations
    );

    run_benchmark(
        "long native u128 full-range",
        bench_long_native_extreme,
        cheap_iterations
    );


    run_benchmark(
        "double naive baseline",
        bench_double_naive,
        cheap_iterations
    );

    run_benchmark(
        "double certified filter",
        bench_double_filter,
        cheap_iterations
    );


    std::printf(
        "\nsink: %llu\n",
        static_cast<unsigned long long>(
            benchmark_sink
        )
    );

    return 0;
}
