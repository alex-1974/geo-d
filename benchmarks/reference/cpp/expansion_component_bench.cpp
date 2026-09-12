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
static_assert(FLT_EVAL_METHOD == 0);

constexpr std::size_t repetitions = 7;
constexpr std::size_t warmup_iterations = 500'000;
constexpr std::size_t eft_iterations = 20'000'000;
constexpr std::size_t expansion_iterations = 5'000'000;
constexpr std::size_t orientation_iterations = 1'000'000;

static std::uint64_t benchmark_sink;

ALWAYS_INLINE std::uint64_t bits_of(double value) noexcept {
    return std::bit_cast<std::uint64_t>(value);
}

ALWAYS_INLINE bool is_finite(double value) noexcept {
    return (bits_of(value) & 0x7ff0'0000'0000'0000ULL)
        != 0x7ff0'0000'0000'0000ULL;
}

ALWAYS_INLINE double rounded_add(double lhs, double rhs) noexcept {
    return lhs + rhs;
}

ALWAYS_INLINE double rounded_sub(double lhs, double rhs) noexcept {
    return lhs - rhs;
}

ALWAYS_INLINE double rounded_mul(double lhs, double rhs) noexcept {
    return lhs * rhs;
}

struct TwoComponent {
    double high;
    double low;
};

struct SplitComponent {
    double high;
    double low;
};

constexpr double splitter = 134'217'729.0;

NOINLINE TwoComponent two_sum(double a, double b) noexcept {
    const double x = rounded_add(a, b);
    const double b_virtual = rounded_sub(x, a);
    const double a_virtual = rounded_sub(x, b_virtual);
    const double b_roundoff = rounded_sub(b, b_virtual);
    const double a_roundoff = rounded_sub(a, a_virtual);
    const double y = rounded_add(a_roundoff, b_roundoff);
    return {x, y};
}

NOINLINE TwoComponent two_diff(double a, double b) noexcept {
    const double x = rounded_sub(a, b);
    const double b_virtual = rounded_sub(a, x);
    const double a_virtual = rounded_add(x, b_virtual);
    const double b_roundoff = rounded_sub(b_virtual, b);
    const double a_roundoff = rounded_sub(a, a_virtual);
    const double y = rounded_add(a_roundoff, b_roundoff);
    return {x, y};
}

NOINLINE TwoComponent fast_two_sum(double a, double b) noexcept {
    const double x = rounded_add(a, b);
    const double b_virtual = rounded_sub(x, a);
    const double y = rounded_sub(b, b_virtual);
    return {x, y};
}

ALWAYS_INLINE SplitComponent split_inline(double value) noexcept {
    const double c = rounded_mul(splitter, value);
    const double a_big = rounded_sub(c, value);
    const double high = rounded_sub(c, a_big);
    const double low = rounded_sub(value, high);
    return {high, low};
}

NOINLINE TwoComponent two_product(double a, double b) noexcept {
    const double x = rounded_mul(a, b);

    const auto a_split = split_inline(a);
    const auto b_split = split_inline(b);

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

ALWAYS_INLINE double finite_magnitude(double value) noexcept {
    return value < 0.0 ? -value : value;
}

template <std::size_t SourceCapacity, std::size_t ResultCapacity>
ALWAYS_INLINE void copy_expansion_zero_elim(
    const ExpansionBuffer<SourceCapacity>& source,
    ExpansionBuffer<ResultCapacity>& result
) noexcept {
    result.clear();

    for (std::size_t i = 0; i < source.length; ++i) {
        const double component = source[i];

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

        const auto initial =
            fast_two_sum(next, q);

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

            const auto sum =
                two_sum(q, next);

            if (sum.low != 0.0)
                h.append(sum.low);

            q = sum.high;
        }
    }

    while (e_index < e.length) {
        const auto sum =
            two_sum(q, e[e_index++]);

        if (sum.low != 0.0)
            h.append(sum.low);

        q = sum.high;
    }

    while (f_index < f.length) {
        const auto sum =
            two_sum(q, f[f_index++]);

        if (sum.low != 0.0)
            h.append(sum.low);

        q = sum.high;
    }

    if (q != 0.0 || h.empty())
        h.append(q);
}

ALWAYS_INLINE TwoComponent two_product_presplit_inline(
    double a,
    double b,
    SplitComponent b_split
) noexcept {
    const double x = rounded_mul(a, b);
    const auto a_split = split_inline(a);

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

    const auto scalar_split =
        split_inline(scalar);

    auto product =
        two_product_presplit_inline(
            expansion[0],
            scalar,
            scalar_split
        );

    double q =
        product.high;

    if (product.low != 0.0)
        result.append(product.low);

    for (std::size_t index = 1;
         index < expansion.length;
         ++index)
    {
        product =
            two_product_presplit_inline(
                expansion[index],
                scalar,
                scalar_split
            );

        const auto sum =
            two_sum(q, product.low);

        if (sum.low != 0.0)
            result.append(sum.low);

        const auto accumulated =
            fast_two_sum(
                product.high,
                sum.high
            );

        if (accumulated.low != 0.0)
            result.append(accumulated.low);

        q = accumulated.high;
    }

    if (q != 0.0 || result.empty())
        result.append(q);
}

constexpr double min_working_magnitude = 0x1p-450;
constexpr double max_working_magnitude = 0x1p+450;

ALWAYS_INLINE bool supported_component(double value) noexcept {
    if (!is_finite(value))
        return false;

    if (value == 0.0)
        return true;

    const double magnitude =
        finite_magnitude(value);

    return magnitude >= min_working_magnitude &&
           magnitude <= max_working_magnitude;
}

NOINLINE bool build_difference(
    double lhs,
    double rhs,
    ExpansionBuffer<2>& result
) noexcept {
    const double rounded =
        rounded_sub(lhs, rhs);

    if (!is_finite(rounded))
        return false;

    const auto difference =
        two_diff(lhs, rhs);

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

    scale_expansion_zero_elim(
        lhs,
        rhs[0],
        first
    );

    if (rhs.length == 2) {
        scale_expansion_zero_elim(
            lhs,
            rhs[1],
            second
        );
    }

    fast_expansion_sum_zero_elim(
        first,
        second,
        result
    );
}

ALWAYS_INLINE int expansion_sign(
    const ExpansionBuffer<16>& expansion
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

ALWAYS_INLINE void negate_expansion(
    const ExpansionBuffer<8>& source,
    ExpansionBuffer<8>& result
) noexcept {
    result.clear();

    for (std::size_t i = 0; i < source.length; ++i)
        result.append(-source[i]);
}

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

struct Pair {
    double a;
    double b;
};

struct OrientationCase {
    double ax, ay, bx, by, cx, cy;
};

static std::array<Pair, 2> sum_cases;
static std::array<Pair, 2> diff_cases;
static std::array<Pair, 2> product_cases;
static std::array<Pair, 2> fast_sum_cases;

static std::array<ExpansionBuffer<2>, 2> scale_inputs;
static std::array<double, 2> scale_scalars;

static std::array<ExpansionBuffer<4>, 2> sum_left;
static std::array<ExpansionBuffer<4>, 2> sum_right;

static std::array<OrientationCase, 2> orientation_collinear_cases;
static std::array<OrientationCase, 2> orientation_near_cases;

ALWAYS_INLINE std::uint64_t encode(TwoComponent value) noexcept {
    return
        static_cast<std::uint64_t>(value.high != 0.0) +
        3ULL * static_cast<std::uint64_t>(value.low != 0.0) +
        static_cast<std::uint64_t>(value.high < 0.0);
}

static void prepare_cases() {
    sum_cases[0] = {1.0, 0x1p-53};
    sum_cases[1] = {-2.0, 0x1p-52};

    diff_cases[0] = {1.0, 0x1p-53};
    diff_cases[1] = {-2.0, -0x1p-52};

    product_cases[0] =
        {1.0 + 0x1p-27, 1.0 - 0x1p-27};

    product_cases[1] =
        {-3.0 + 0x1p-25, 0.5 + 0x1p-28};

    fast_sum_cases[0] =
        {1.0, 0x1p-53};

    fast_sum_cases[1] =
        {-2.0, 0x1p-52};

    scale_inputs[0].append(0x1p-104);
    scale_inputs[0].append(1.0);
    scale_scalars[0] =
        1.0 + 0x1p-27;

    scale_inputs[1].append(-0x1p-103);
    scale_inputs[1].append(2.0);
    scale_scalars[1] =
        -0.5 + 0x1p-28;

    sum_left[0].append(0x1p-156);
    sum_left[0].append(-0x1p-104);
    sum_left[0].append(0x1p-52);
    sum_left[0].append(1.0);

    sum_right[0].append(-0x1p-155);
    sum_right[0].append(0x1p-103);
    sum_right[0].append(-0x1p-51);
    sum_right[0].append(2.0);

    sum_left[1].append(-0x1p-158);
    sum_left[1].append(0x1p-106);
    sum_left[1].append(-0x1p-54);
    sum_left[1].append(-1.5);

    sum_right[1].append(0x1p-157);
    sum_right[1].append(-0x1p-105);
    sum_right[1].append(0x1p-53);
    sum_right[1].append(-2.5);

    orientation_collinear_cases[0] =
        {0.0, 0.0, 10.0, 10.0, 5.0, 5.0};

    orientation_collinear_cases[1] =
        {1.0, 1.0, 11.0, 11.0, 6.0, 6.0};

    orientation_near_cases[0] =
        {0.0, 0.0, 10.0, 10.0, 5.0,
         0x1.4000000000001p+2};

    orientation_near_cases[1] =
        {0.0, 0.0, 10.0, 10.0, 5.0,
         0x1.3ffffffffffffp+2};
}

NOINLINE std::uint64_t bench_two_sum(std::size_t i) noexcept {
    const auto value = sum_cases[i & 1];
    return encode(two_sum(value.a, value.b));
}

NOINLINE std::uint64_t bench_two_diff(std::size_t i) noexcept {
    const auto value = diff_cases[i & 1];
    return encode(two_diff(value.a, value.b));
}

NOINLINE std::uint64_t bench_fast_two_sum(std::size_t i) noexcept {
    const auto value = fast_sum_cases[i & 1];
    return encode(fast_two_sum(value.a, value.b));
}

NOINLINE std::uint64_t bench_two_product(std::size_t i) noexcept {
    const auto value = product_cases[i & 1];
    return encode(two_product(value.a, value.b));
}

NOINLINE std::uint64_t bench_scale_2(std::size_t i) noexcept {
    const auto index = i & 1;

    ExpansionBuffer<4> result;

    scale_expansion_zero_elim(
        scale_inputs[index],
        scale_scalars[index],
        result
    );

    return
        static_cast<std::uint64_t>(result.length) +
        7ULL * static_cast<std::uint64_t>(
            result[result.length - 1] != 0.0
        );
}

NOINLINE std::uint64_t bench_sum_4x4(std::size_t i) noexcept {
    const auto index = i & 1;

    ExpansionBuffer<8> result;

    fast_expansion_sum_zero_elim(
        sum_left[index],
        sum_right[index],
        result
    );

    return
        static_cast<std::uint64_t>(result.length) +
        7ULL * static_cast<std::uint64_t>(
            result[result.length - 1] != 0.0
        );
}

NOINLINE std::uint64_t bench_orientation_collinear(
    std::size_t i
) noexcept {
    const auto value =
        orientation_collinear_cases[i & 1];

    int sign = 0;

    const bool success =
        try_orientation_exact_expansion(
            value.ax, value.ay,
            value.bx, value.by,
            value.cx, value.cy,
            sign
        );

    return
        static_cast<std::uint64_t>(success) +
        static_cast<std::uint64_t>(sign + 1) * 3ULL;
}

NOINLINE std::uint64_t bench_orientation_near(
    std::size_t i
) noexcept {
    const auto value =
        orientation_near_cases[i & 1];

    int sign = 0;

    const bool success =
        try_orientation_exact_expansion(
            value.ax, value.ay,
            value.bx, value.by,
            value.cx, value.cy,
            sign
        );

    return
        static_cast<std::uint64_t>(success) +
        static_cast<std::uint64_t>(sign + 1) * 3ULL;
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
            std::chrono::duration_cast<
                std::chrono::nanoseconds
            >(stop - start).count();
    }

    benchmark_sink ^= local_sink;

    std::sort(samples.begin(), samples.end());

    const double median =
        static_cast<double>(
            samples[repetitions / 2]
        ) / static_cast<double>(iterations);

    const double minimum =
        static_cast<double>(
            samples.front()
        ) / static_cast<double>(iterations);

    const double maximum =
        static_cast<double>(
            samples.back()
        ) / static_cast<double>(iterations);

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

    std::puts(
        "C++ expansion component benchmark\n"
        "median of 7 measured runs"
    );

    run_benchmark("twoSum", eft_iterations, bench_two_sum);
    run_benchmark("twoDiff", eft_iterations, bench_two_diff);
    run_benchmark("fastTwoSum", eft_iterations, bench_fast_two_sum);
    run_benchmark("twoProduct", eft_iterations, bench_two_product);

    run_benchmark(
        "scaleExpansion 2->4",
        expansion_iterations,
        bench_scale_2
    );

    run_benchmark(
        "fastExpansionSum 4+4",
        expansion_iterations,
        bench_sum_4x4
    );

    run_benchmark(
        "orientation exact collinear",
        orientation_iterations,
        bench_orientation_collinear
    );

    run_benchmark(
        "orientation exact near",
        orientation_iterations,
        bench_orientation_near
    );

    std::printf(
        "\nsink: %llu\n",
        static_cast<unsigned long long>(
            benchmark_sink
        )
    );

    return 0;
}
