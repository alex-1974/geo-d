/**
 * Euclidean distance, length, and nearest-point operations.
  *
 * Authors:
 *     Alexander Bernardi
 *
 * Copyright:
 *     Copyright © 2026 Alexander Bernardi
 *
 * License:
 *     MIT
 *
 * Date:
 *     September 25, 2026
 */
module geo.metric;

private import euclid_core.scalar :
    CoreMetricScalar = MetricScalar;

import geo.polyline_view : Polyline2View;

import geo.point : Point2;
import geo.scalar : isGeoScalar;
import geo.segment : Segment2;
import geo.vector : Vector2;

private import euclid_core.internal.metric :
    metricHypot,
    metricScalbn;
import std.math.trigonometry : atan2;
import std.math.exponential : ilogb;
import std.math.traits : isFinite;


version (D_Ddoc)
{
    /**
     * Floating-point computation type used by elementary metric operations.
     *
     * Storage precision and metric computation precision are deliberately
     * separate:
     *
     *     int     -> double
     *     long    -> double
     *     float   -> double
     *     double  -> double
     *     real    -> real
     */
    template MetricScalar(T)
    if (isGeoScalar!T)
    {
        static if (is(T == real))
            alias MetricScalar = real;
        else
            alias MetricScalar = double;
    }

    static assert(
        is(
            MetricScalar!int ==
            CoreMetricScalar!int
        )
    );

    static assert(
        is(
            MetricScalar!long ==
            CoreMetricScalar!long
        )
    );

    static assert(
        is(
            MetricScalar!float ==
            CoreMetricScalar!float
        )
    );

    static assert(
        is(
            MetricScalar!double ==
            CoreMetricScalar!double
        )
    );

    static assert(
        is(
            MetricScalar!real ==
            CoreMetricScalar!real
        )
    );
}
else
{
    alias MetricScalar =
        CoreMetricScalar;
}


/// Example inspecting the metric computation scalar policy.
@safe unittest
{
    import geo;

    static assert(is(MetricScalar!int == double));
    static assert(is(MetricScalar!long == double));
    static assert(is(MetricScalar!float == double));
    static assert(is(MetricScalar!double == double));
    static assert(is(MetricScalar!real == real));
}


/**
 * Computes the Euclidean dot product of two vectors.
 *
 * Both vectors use the same storage scalar type.
 *
 * Returns:
 *     The dot product in `MetricScalar!T`.
 *
 * Integral components are converted to `MetricScalar!T` before
 * multiplication. The operation therefore follows ordinary floating-point
 * metric arithmetic and does not promise exact integral accumulation.
 *
 * Floating-point NaN and infinity follow ordinary floating-point arithmetic.
 *
 * This is a numerical vector operation, not a robust exact predicate.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
MetricScalar!T dot(T)(
    Vector2!T a,
    Vector2!T b
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    return
        cast(M) a.x * cast(M) b.x +
        cast(M) a.y * cast(M) b.y;
}


/// Example computing a vector dot product through the public package API.
@safe unittest
{
    import geo;

    auto a = Vector2!int(1, 2);
    auto b = Vector2!int(3, 4);

    static assert(
        is(typeof(dot(a, b)) == double)
    );

    assert(dot(a, b) == 11.0);
}


/**
 * Computes the squared Euclidean norm of a vector.
 *
 * Returns:
 *     The squared norm in `MetricScalar!T`.
 *
 * The numerical construction is the same as `dot(vector, vector)`.
 * Integral input is therefore metric floating-point arithmetic rather than
 * exact integral accumulation.
 *
 * Very large finite input may produce infinity. NaN and infinity otherwise
 * follow ordinary floating-point arithmetic.
 *
 * This is a numerical vector operation, not a robust exact predicate.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
MetricScalar!T squaredNorm(T)(
    Vector2!T vector
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    return dot(vector, vector);
}


/// Example computing a squared vector norm through the public package API.
@safe unittest
{
    import geo;

    auto vector = Vector2!int(3, 4);

    static assert(
        is(typeof(squaredNorm(vector)) == double)
    );

    assert(squaredNorm(vector) == 25.0);
}


/**
 * Computes the Euclidean norm of a vector.
 *
 * Returns:
 *     The norm in `MetricScalar!T`.
 *
 * Components are converted to the metric computation type and evaluated
 * with the shared Core `hypot`-compatible metric helper. The operation
 * deliberately does not compute `sqrt(squaredNorm(vector))`, avoiding
 * unnecessary intermediate square overflow and underflow.
 *
 * Floating-point NaN and infinity follow the corresponding `hypot`
 * semantics.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
MetricScalar!T norm(T)(
    Vector2!T vector
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    return metricHypot(
        cast(M) vector.x,
        cast(M) vector.y
    );
}


/// Example computing a vector norm through the public package API.
@safe unittest
{
    import geo;

    auto vector = Vector2!int(3, 4);

    static assert(
        is(typeof(norm(vector)) == double)
    );

    assert(norm(vector) == 5.0);
}


/**
 * Constructs the unit direction of a finite non-zero vector.
 *
 * Params:
 *     vector = Source vector.
 *     result = Unit vector in `MetricScalar!T`.
 *
 * Returns:
 *     `true` when a finite unit direction is produced; otherwise `false`.
 *
 * Returns `false` when either component is non-finite or when the vector is
 * exactly zero. No epsilon is used.
 *
 * On failure, `result` is `Vector2!R.init`.
 *
 * Components are converted to the metric computation type before absolute
 * magnitude is formed. The converted vector is then scaled by its largest
 * absolute component before `hypot` is evaluated. This avoids signed
 * integral `T.min` negation and avoids unnecessary overflow or underflow
 * for extreme finite vectors.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
bool tryNormalize(T, R)(
    Vector2!T vector,
    out Vector2!R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
)
{
    alias M = MetricScalar!T;

    result = Vector2!R.init;

    const M x =
        cast(M) vector.x;

    const M y =
        cast(M) vector.y;

    if (
        !isFinite(x) ||
        !isFinite(y)
    )
    {
        return false;
    }

    const M absX =
        x < M(0)
            ? -x
            : x;

    const M absY =
        y < M(0)
            ? -y
            : y;

    const M scale =
        absX > absY
            ? absX
            : absY;

    if (scale == M(0))
        return false;

    const M scaledX =
        x / scale;

    const M scaledY =
        y / scale;

    const M length =
        metricHypot(
            scaledX,
            scaledY
        );

    if (
        !isFinite(length) ||
        length == M(0)
    )
    {
        return false;
    }

    const M normalizedX =
        scaledX / length;

    const M normalizedY =
        scaledY / length;

    if (
        !isFinite(normalizedX) ||
        !isFinite(normalizedY)
    )
    {
        return false;
    }

    result =
        Vector2!R(
            normalizedX,
            normalizedY
        );

    return true;
}


/// Example normalizing a vector through the public package API.
@safe unittest
{
    import geo;

    auto vector = Vector2!int(3, 4);
    Vector2!double unit;

    assert(
        tryNormalize(
            vector,
            unit
        )
    );

    assert(
        unit ==
        Vector2!double(
            0.6,
            0.8
        )
    );
}


/**
 * Computes the canonical signed angle from one vector to another.
 *
 * Params:
 *     from = Starting direction.
 *     to = Target direction.
 *     result = Signed angle in radians.
 *
 * Returns:
 *     `true` when both vectors are finite and exactly non-zero; otherwise
 *     `false`.
 *
 * On success the result lies in `$(LPAREN)-pi, pi]`.
 *
 * Positive angles correspond to a positive two-dimensional determinant and
 * therefore to counter-clockwise rotation in the conventional Cartesian
 * x-right/y-up orientation.
 *
 * Both vectors are converted to `MetricScalar!T` and independently
 * power-of-two scaled before determinant and dot terms are formed. This
 * avoids avoidable product overflow and underflow while preserving the
 * direction represented by each finite vector.
 *
 * If the computed determinant is exactly zero, the branch cut is
 * canonicalized from the computed dot value:
 *
 * - dot >= 0 produces positive zero;
 * - dot < 0 produces positive pi.
 *
 * This is a numerical directional measurement, not a robust orientation or
 * collinearity predicate. No epsilon is used.
 *
 * On failure, `result` is zero.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
bool trySignedAngle(T, R)(
    Vector2!T from,
    Vector2!T to,
    out R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
)
{
    alias M = MetricScalar!T;

    result = R(0);

    const M fromX =
        cast(M) from.x;

    const M fromY =
        cast(M) from.y;

    const M toX =
        cast(M) to.x;

    const M toY =
        cast(M) to.y;

    if (
        !isFinite(fromX) ||
        !isFinite(fromY) ||
        !isFinite(toX) ||
        !isFinite(toY)
    )
    {
        return false;
    }

    const M absFromX =
        fromX < M(0)
            ? -fromX
            : fromX;

    const M absFromY =
        fromY < M(0)
            ? -fromY
            : fromY;

    const M absToX =
        toX < M(0)
            ? -toX
            : toX;

    const M absToY =
        toY < M(0)
            ? -toY
            : toY;

    const M maxFrom =
        absFromX > absFromY
            ? absFromX
            : absFromY;

    const M maxTo =
        absToX > absToY
            ? absToX
            : absToY;

    if (
        maxFrom == M(0) ||
        maxTo == M(0)
    )
    {
        return false;
    }

    const int exponentFrom =
        ilogb(maxFrom);

    const int exponentTo =
        ilogb(maxTo);

    const M scaledFromX =
        metricScalbn(
            fromX,
            -exponentFrom
        );

    const M scaledFromY =
        metricScalbn(
            fromY,
            -exponentFrom
        );

    const M scaledToX =
        metricScalbn(
            toX,
            -exponentTo
        );

    const M scaledToY =
        metricScalbn(
            toY,
            -exponentTo
        );

    const M determinant =
        scaledFromX * scaledToY -
        scaledFromY * scaledToX;

    const M dotValue =
        scaledFromX * scaledToX +
        scaledFromY * scaledToY;

    M angle;

    if (determinant == M(0))
    {
        if (dotValue < M(0))
        {
            /*
             * atan2(+0, -1) provides the positive branch-cut value +pi.
             */
            angle =
                atan2(
                    M(0),
                    M(-1)
                );
        }
        else
        {
            /*
             * Construct positive zero explicitly rather than retaining
             * a possible negative-zero determinant.
             */
            angle =
                M(0);
        }
    }
    else
    {
        angle =
            atan2(
                determinant,
                dotValue
            );
    }

    if (!isFinite(angle))
        return false;

    result =
        cast(R) angle;

    return true;
}


/// Example computing a signed angle through the public package API.
@safe unittest
{
    import geo;

    auto from = Vector2!int(1, 0);
    auto to = Vector2!int(0, 1);

    double angle;

    assert(
        trySignedAngle(
            from,
            to,
            angle
        )
    );

    assert(angle > 1.57);
    assert(angle < 1.58);
}


private enum bool isMetricIntegral(T) =
       is(T == int)
    || is(T == long);


private template UnsignedMetricIntegral(T)
if (isMetricIntegral!T)
{
    static if (is(T == int))
        alias UnsignedMetricIntegral = uint;
    else
        alias UnsignedMetricIntegral = ulong;
}


/*
 * Exact unsigned magnitude of a signed integral value.
 *
 * The -(value + 1) formulation avoids overflow for T.min.
 */
private UnsignedMetricIntegral!T unsignedMagnitude(T)(T value)
    pure nothrow @safe @nogc
if (isMetricIntegral!T)
{
    alias U = UnsignedMetricIntegral!T;

    if (value >= 0)
        return cast(U) value;

    return cast(U)(-(value + 1)) + U(1);
}


/*
 * Exact absolute difference between two supported signed integer values.
 *
 * The result can span the complete corresponding unsigned type:
 *
 *     int  -> uint
 *     long -> ulong
 *
 * No signed subtraction overflow occurs.
 */
private UnsignedMetricIntegral!T unsignedDifference(T)(T a, T b)
    pure nothrow @safe @nogc
if (isMetricIntegral!T)
{
    alias U = UnsignedMetricIntegral!T;

    if ((a < 0) != (b < 0))
        return unsignedMagnitude(a) + unsignedMagnitude(b);

    if (a >= b)
        return cast(U)(a - b);

    return cast(U)(b - a);
}


/*
 * Signed component difference in the metric computation type.
 *
 * Semantics:
 *
 *     a - b
 *
 * For integral geometry the magnitude is obtained exactly in the
 * corresponding unsigned type before conversion to MetricScalar.
 * The sign is applied only after that conversion.
 *
 * This avoids both signed integer overflow and the loss of small
 * differences that would occur if large integer coordinates were
 * converted to floating point before subtraction.
 */
private MetricScalar!T signedMetricDifference(T)(T a, T b)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    static if (isMetricIntegral!T)
    {
        if (a == b)
            return M(0);

        const M magnitude =
            cast(M) unsignedDifference(a, b);

        return a > b ? magnitude : -magnitude;
    }
    else
    {
        return cast(M) a - cast(M) b;
    }
}


/*
 * Conservative domain for direct binary floating-point products used by the
 * ordinary-range metric fast path.
 *
 * Every non-zero component must lie in [2^-250, 2^250]. Therefore the
 * individual products needed by projection and perpendicular-distance
 * formulas lie in [2^-500, 2^500], comfortably inside the normal binary64
 * range.
 *
 * The bound is intentionally conservative. Values outside it use the scaled
 * full-range implementation.
 */
private bool isDirectMetricComponent(M)(M value)
    pure nothrow @safe @nogc
{
    const M magnitude =
        value < M(0)
            ? -value
            : value;

    return
        magnitude == M(0) ||
        (
            magnitude >= M(0x1p-250) &&
            magnitude <= M(0x1p250)
        );
}


private bool hasDirectMetricProductRange(M)(
    M dx,
    M dy,
    M rx,
    M ry
)
    pure nothrow @safe @nogc
{
    return
        isDirectMetricComponent(dx) &&
        isDirectMetricComponent(dy) &&
        isDirectMetricComponent(rx) &&
        isDirectMetricComponent(ry);
}


/*
 * Direct ordinary-range projection.
 *
 * Preconditions:
 *
 *     dx, dy, rx and ry are finite;
 *     d is non-zero;
 *     hasDirectMetricProductRange(dx, dy, rx, ry) is true.
 */
private M directProjectionParameter(M)(
    M dx,
    M dy,
    M rx,
    M ry
)
    pure nothrow @safe @nogc
{
    const M numerator =
        rx * dx +
        ry * dy;

    const M denominator =
        dx * dx +
        dy * dy;

    return
        numerator /
        denominator;
}


/*
 * Direct ordinary-range perpendicular distance.
 *
 * Preconditions are identical to directProjectionParameter().
 */
private M directPerpendicularDistance(M)(
    M dx,
    M dy,
    M rx,
    M ry
)
    pure nothrow @safe @nogc
{
    const M cross =
        dx * ry -
        dy * rx;

    const M absCross =
        cross < M(0)
            ? -cross
            : cross;

    if (absCross == M(0))
        return M(0);

    return
        absCross /
        metricHypot(
            dx,
            dy
        );
}


/*
 * Projection parameter of r onto d.
 *
 * Computes
 *
 *     t = dot(r, d) / dot(d, d)
 *
 * without directly forming potentially overflowing dot products.
 *
 * d and r are scaled independently by powers of two. Because binary
 * scaling is exact, the projection ratio can then be reconstructed
 * with the shared Core power-of-two scaling helper.
 *
 * Preconditions:
 *
 *     dx, dy, rx and ry are finite;
 *     d is non-zero.
 */
private MetricScalar!T projectionParameter(T)(
    MetricScalar!T dx,
    MetricScalar!T dy,
    MetricScalar!T rx,
    MetricScalar!T ry
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    /*
     * Ordinary finite-range fast path.
     *
     * Inside this conservative domain, all direct products and their sums
     * remain safely representable, so exponent normalization is unnecessary.
     */
    if (
        hasDirectMetricProductRange(
            dx,
            dy,
            rx,
            ry
        )
    )
    {
        return
            directProjectionParameter(
                dx,
                dy,
                rx,
                ry
            );
    }

    const M absDx = dx < M(0) ? -dx : dx;
    const M absDy = dy < M(0) ? -dy : dy;
    const M absRx = rx < M(0) ? -rx : rx;
    const M absRy = ry < M(0) ? -ry : ry;

    const M maxD = absDx > absDy ? absDx : absDy;
    const M maxR = absRx > absRy ? absRx : absRy;

    assert(maxD > M(0));

    if (maxR == M(0))
        return M(0);

    const int expD = ilogb(maxD);
    const int expR = ilogb(maxR);

    /*
     * After this scaling, the largest absolute component in each
     * vector lies in [1, 2), so products and sums cannot overflow.
     */
    const M ndx = metricScalbn(dx, -expD);
    const M ndy = metricScalbn(dy, -expD);

    const M nrx = metricScalbn(rx, -expR);
    const M nry = metricScalbn(ry, -expR);

    const M numerator =
        nrx * ndx + nry * ndy;

    const M denominator =
        ndx * ndx + ndy * ndy;

    const M normalizedRatio =
        numerator / denominator;

    /*
     * Restore the relative scale:
     *
     *     r = nr * 2^expR
     *     d = nd * 2^expD
     *
     * therefore
     *
     *     t = normalizedRatio * 2^(expR-expD)
     */
    return metricScalbn(
        normalizedRatio,
        expR - expD
    );
}


/**
 * Squared Euclidean distance between two points.
 *
 * Returns:
 *     The squared distance in MetricScalar!T.
 *
 * Integer coordinate geometry is converted to floating-point metric
 * arithmetic after each component difference has been obtained without
 * signed overflow.
 *
 * This operation does not promise exact integral arithmetic. In
 * particular, long-coordinate results may lose precision after conversion
 * to double.
 *
 * Floating-point NaN and infinity are not rejected. Results follow normal
 * floating-point arithmetic. Very large finite results may overflow to
 * infinity.
 *
 * This function is a metric computation, not a robust exact distance
 * comparison predicate.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
MetricScalar!T squaredDistance(T)(
    Point2!T a,
    Point2!T b
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    const M dx = signedMetricDifference(a.x, b.x);
    const M dy = signedMetricDifference(a.y, b.y);

    return dx * dx + dy * dy;
}


/// Example computing squared distance without taking a square root.
@safe unittest
{
    import geo;

    const a = Point2!int(0, 0);
    const b = Point2!int(3, 4);

    static assert(
        is(typeof(squaredDistance(a, b)) == double)
    );

    assert(
        squaredDistance(a, b) == 25.0
    );
}


/**
 * Euclidean distance between two points.
 *
 * Integer coordinate differences are obtained without signed overflow
 * before conversion to MetricScalar!T. This avoids losing small differences
 * merely because large integer coordinates were converted before
 * subtraction.
 *
 * The resulting metric value is floating-point. In particular,
 * long-coordinate results may lose precision after conversion to double.
 *
 * Distance is calculated directly with hypot rather than as
 *
 *     sqrt(squaredDistance(a, b))
 *
 * so avoidable intermediate square overflow is not introduced.
 *
 * Floating-point NaN and infinity are not rejected. Results follow normal
 * floating-point arithmetic.
 *
 * This function is a metric computation, not a robust exact distance
 * comparison predicate.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
MetricScalar!T distance(T)(
    Point2!T a,
    Point2!T b
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    const M dx = signedMetricDifference(a.x, b.x);
    const M dy = signedMetricDifference(a.y, b.y);

    return metricHypot(dx, dy);
}


/// Example using the public package API.
@safe unittest
{
    import geo;

    alias P = Point2!double;

    assert(
        distance(
            P(0.0, 0.0),
            P(3.0, 4.0)
        ) == 5.0
    );
}


/*
 * Perpendicular distance from an offset vector r to the infinite line
 * through the origin with direction d.
 *
 * Computes
 *
 *     |cross(d, r)| / |d|
 *
 * after scaling d and r independently by powers of two. This avoids
 * directly forming potentially overflowing products.
 *
 * Preconditions:
 *
 *     dx, dy, rx and ry are finite;
 *     d is non-zero.
 */
private MetricScalar!T perpendicularDistance(T)(
    MetricScalar!T dx,
    MetricScalar!T dy,
    MetricScalar!T rx,
    MetricScalar!T ry
)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    /*
     * Ordinary finite-range fast path.
     *
     * Power-of-two normalization is only needed outside the conservative
     * direct-product domain.
     */
    if (
        hasDirectMetricProductRange(
            dx,
            dy,
            rx,
            ry
        )
    )
    {
        return
            directPerpendicularDistance(
                dx,
                dy,
                rx,
                ry
            );
    }

    const M absDx = dx < M(0) ? -dx : dx;
    const M absDy = dy < M(0) ? -dy : dy;
    const M absRx = rx < M(0) ? -rx : rx;
    const M absRy = ry < M(0) ? -ry : ry;

    const M maxD = absDx > absDy ? absDx : absDy;
    const M maxR = absRx > absRy ? absRx : absRy;

    assert(maxD > M(0));

    if (maxR == M(0))
        return M(0);

    const int expD = ilogb(maxD);
    const int expR = ilogb(maxR);

    const M ndx = metricScalbn(dx, -expD);
    const M ndy = metricScalbn(dy, -expD);

    const M nrx = metricScalbn(rx, -expR);
    const M nry = metricScalbn(ry, -expR);

    const M cross =
        ndx * nry - ndy * nrx;

    const M absCross =
        cross < M(0) ? -cross : cross;

    /*
     * Preserve exact zero explicitly and avoid unnecessary norm/rescaling
     * work. Core metricScalbn also preserves zero for every scaling call
     * in this path.
     */
    if (absCross == M(0))
        return M(0);

    const M normalizedDistance =
        absCross / metricHypot(ndx, ndy);

    return metricScalbn(
        normalizedDistance,
        expR
    );
}


/**
 * Computes the Euclidean distance from a point to a segment.
 *
 * Returns false when:
 *
 * - an input coordinate is NaN or infinite; or
 * - a required metric difference cannot be represented finitely in
 *   MetricScalar!T.
 *
 * On failure, result is zero. A successful call produces a finite result.
 *
 * A degenerate segment is treated as its single endpoint.
 *
 * Integral coordinate differences are obtained before conversion to the
 * metric computation type, avoiding signed overflow and preserving small
 * differences between large integer coordinates.
 *
 * For an interior projection, the perpendicular distance is computed from
 * scaled direction and offset vectors. No rounded nearest-point coordinate
 * is constructed.
 *
 * This is a metric computation, not an exact topological predicate.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
bool tryPointSegmentDistance(T, R)(
    Segment2!T segment,
    Point2!T point,
    out R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
)
{
    alias M = MetricScalar!T;

    result = M(0);

    if (!point.isFinite || !segment.isFinite)
        return false;

    const M dx =
        signedMetricDifference(
            segment.b.x,
            segment.a.x
        );

    const M dy =
        signedMetricDifference(
            segment.b.y,
            segment.a.y
        );

    const M rx =
        signedMetricDifference(
            point.x,
            segment.a.x
        );

    const M ry =
        signedMetricDifference(
            point.y,
            segment.a.y
        );

    if (
        !isFinite(dx) ||
        !isFinite(dy) ||
        !isFinite(rx) ||
        !isFinite(ry)
    )
    {
        return false;
    }

    /*
     * Degenerate segment.
     */
    if (dx == M(0) && dy == M(0))
    {
        result = metricHypot(rx, ry);
        if (!isFinite(result))
        {
            result = M(0);
            return false;
        }

        return true;
    }

    const bool directMetricRange =
        hasDirectMetricProductRange(
            dx,
            dy,
            rx,
            ry
        );

    const M t =
        directMetricRange
            ? directProjectionParameter(
                dx,
                dy,
                rx,
                ry
            )
            : projectionParameter!T(
                dx,
                dy,
                rx,
                ry
            );

    /*
     * Infinite projection parameters still determine an endpoint.
     * NaN reaches the explicit finite check below.
     */
    if (t <= M(0))
    {
        result = metricHypot(rx, ry);
        if (!isFinite(result))
        {
            result = M(0);
            return false;
        }

        return true;
    }

    if (t >= M(1))
    {
        const M bx =
            signedMetricDifference(
                point.x,
                segment.b.x
            );

        const M by =
            signedMetricDifference(
                point.y,
                segment.b.y
            );

        if (!isFinite(bx) || !isFinite(by))
            return false;

        result = metricHypot(bx, by);
        if (!isFinite(result))
        {
            result = M(0);
            return false;
        }

        return true;
    }

    if (!isFinite(t))
        return false;

    result =
        directMetricRange
            ? directPerpendicularDistance(
                dx,
                dy,
                rx,
                ry
            )
            : perpendicularDistance!T(
                dx,
                dy,
                rx,
                ry
            );

    if (!isFinite(result))
    {
        result = M(0);
        return false;
    }

    return true;
}

/**
 * Deprecated v1 point-first overload.
 *
 * Use `tryPointSegmentDistance(segment, point, result)` so that the segment
 * is the UFCS receiver consistently with `tryNearestPoint`.
 */
deprecated(
    "Use tryPointSegmentDistance(segment, point, result)"
)
bool tryPointSegmentDistance(T, R)(
    Point2!T point,
    Segment2!T segment,
    out R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
)
{
    return tryPointSegmentDistance(
        segment,
        point,
        result
    );
}



/// Example computing point-to-segment distance and handling failure.
@safe unittest
{
    import geo;

    alias P = Point2!double;
    alias S = Segment2!double;

    const segment =
        S(
            P(0.0, 0.0),
            P(10.0, 0.0)
        );

    double result;

    assert(
        tryPointSegmentDistance(
            segment,
            P(5.0, 3.0),
            result
        )
    );

    assert(result == 3.0);

    result = 123.0;

    assert(
        !tryPointSegmentDistance(
            segment,
            P(double.nan, 0.0),
            result
        )
    );

    assert(result == 0.0);
}


/**
 * Finds the nearest point on a segment to a point.
 *
 * The result uses MetricScalar!T because the nearest point of an integral
 * segment is not generally representable with integral coordinates.
 *
 * Returns false when:
 *
 * - an input coordinate is NaN or infinite; or
 * - a required metric difference cannot be represented finitely in the
 *   metric computation type.
 *
 * On failure, result remains Point2!(MetricScalar!T).init. A successful
 * result contains only finite coordinates.
 *
 * A degenerate segment returns its single endpoint converted to
 * MetricScalar!T. Endpoint projections are represented in the same way.
 * Consequently, long coordinates may be rounded when represented as
 * double.
 *
 * Interior nearest points are constructed using floating-point metric
 * arithmetic. The constructed coordinates are not an exact topological
 * representation and must not be treated as an exact predicate result.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
bool tryNearestPoint(T, R)(
    Segment2!T segment,
    Point2!T point,
    out Point2!R result
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
)
{
    alias M = MetricScalar!T;

    if (!segment.isFinite || !point.isFinite)
        return false;

    const M ax = cast(M) segment.a.x;
    const M ay = cast(M) segment.a.y;

    const M bx = cast(M) segment.b.x;
    const M by = cast(M) segment.b.y;

    const M dx =
        signedMetricDifference(segment.b.x, segment.a.x);

    const M dy =
        signedMetricDifference(segment.b.y, segment.a.y);

    if (!isFinite(dx) || !isFinite(dy))
        return false;

    /*
     * Degenerate segment.
     */
    if (dx == M(0) && dy == M(0))
    {
        result = Point2!M(ax, ay);
        return true;
    }

    const M rx =
        signedMetricDifference(point.x, segment.a.x);

    const M ry =
        signedMetricDifference(point.y, segment.a.y);

    if (!isFinite(rx) || !isFinite(ry))
        return false;

    const bool directMetricRange =
        hasDirectMetricProductRange(
            dx,
            dy,
            rx,
            ry
        );

    const M t =
        directMetricRange
            ? directProjectionParameter(
                dx,
                dy,
                rx,
                ry
            )
            : projectionParameter!T(
                dx,
                dy,
                rx,
                ry
            );

    /*
     * Positive overflow of t simply means the projection lies beyond b.
     * Negative overflow means it lies before a.
     */
    if (t <= M(0))
    {
        result = Point2!M(ax, ay);
        return true;
    }

    if (t >= M(1))
    {
        result = Point2!M(bx, by);
        return true;
    }

    if (!isFinite(t))
        return false;

    /*
     * Interpolate from the nearer endpoint. This reduces avoidable
     * cancellation when t is very close to 0 or 1.
     */
    if (t <= M(0.5))
    {
        result = Point2!M(
            ax + t * dx,
            ay + t * dy
        );
    }
    else
    {
        const M fromB = t - M(1);

        result = Point2!M(
            bx + fromB * dx,
            by + fromB * dy
        );
    }

    if (!result.isFinite)
    {
        result = Point2!M.init;
        return false;
    }

    return true;
}


/// Example constructing the nearest point in the metric scalar type.
@safe unittest
{
    import geo;

    const segment =
        Segment2!int(
            Point2!int(0, 0),
            Point2!int(10, 0)
        );

    Point2!double nearest;

    assert(
        tryNearestPoint(
            segment,
            Point2!int(3, 4),
            nearest
        )
    );

    static assert(
        is(typeof(nearest) == Point2!double)
    );

    assert(
        nearest ==
        Point2!double(
            3.0,
            0.0
        )
    );
}


/**
 * Euclidean length of a segment.
 *
 * Uses the same metric computation policy as point-to-point distance.
 *
 * In particular:
 *
 * - integer coordinate differences are obtained without signed overflow;
 * - int, long and float geometry compute in double;
 * - real geometry computes in real;
 * - hypot is used indirectly through distance().
 *
 * Floating-point non-finite coordinates follow the same arithmetic
 * semantics as distance().
 *
 * This is a metric computation, not an exact topological predicate.
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
MetricScalar!T segmentLength(T)(Segment2!T segment)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    return distance(segment.a, segment.b);
}


/// Example computing the Euclidean length of a segment.
@safe unittest
{
    import geo;

    const segment =
        Segment2!double(
            Point2!double(0.0, 0.0),
            Point2!double(3.0, 4.0)
        );

    assert(segmentLength(segment) == 5.0);
}


/**
 * Euclidean length of a polyline.
 *
 * The result is the sum of the lengths of all consecutive segments in
 * stored point order.
 *
 * Empty and singleton polylines have length zero.
 *
 * Uses the same MetricScalar policy as segmentLength().
 *
 * Segment lengths are accumulated in stored order in MetricScalar!T using
 * Kahan-style compensated summation to reduce floating-point accumulation
 * error.
 *
 * Compensation improves mixed-scale sums but does not make the result exact,
 * correctly rounded, or independent of segment order. Each segment length
 * remains an ordinary floating-point metric computation.
 *
 * Non-finite segment lengths and accumulated overflow propagate according to
 * normal floating-point arithmetic. The accumulated result may therefore be
 * NaN or infinity.
 *
 * No allocation or point copying is performed.
 *
 * Complexity:
 *     O(n) time and O(1) auxiliary space for n stored points.
 */
MetricScalar!T polylineLength(T)(Polyline2View!T polyline)
    pure nothrow @safe @nogc
if (isGeoScalar!T)
{
    alias M = MetricScalar!T;

    M result = M(0);
    M correction = M(0);

    foreach (i; 0 .. polyline.segmentCount)
    {
        const M value =
            segmentLength(
                polyline.segment(i)
            );

        const M adjusted =
            value - correction;

        const M next =
            result + adjusted;

        /*
         * A non-finite next value covers:
         *
         * - a non-finite segment length;
         * - accumulated finite overflow;
         * - an already non-finite running result.
         *
         * Preserve that ordinary floating-point result and discard the
         * compensation state before continuing.
         */
        if (!isFinite(next))
        {
            result = next;
            correction = M(0);
            continue;
        }

        correction =
            (next - result) - adjusted;

        result = next;
    }

    return result;
}


/// Example summing the lengths of consecutive polyline segments.
@safe unittest
{
    import geo;

    alias P = Point2!double;

    P[3] points = [
        P(0.0, 0.0),
        P(3.0, 4.0),
        P(6.0, 8.0)
    ];

    const polyline =
        Polyline2View!double(points[]);

    assert(polylineLength(polyline) == 10.0);
}


// Existing exhaustive regression coverage.
@safe unittest
{
    /*
     * Metric result policy.
     */
    static assert(is(MetricScalar!int == double));
    static assert(is(MetricScalar!long == double));
    static assert(is(MetricScalar!float == double));
    static assert(is(MetricScalar!double == double));
    static assert(is(MetricScalar!real == real));


    /*
     * Signed metric differences preserve direction without signed
     * integer subtraction overflow.
     */
    assert(signedMetricDifference!int(5, 2) == 3.0);
    assert(signedMetricDifference!int(2, 5) == -3.0);
    assert(signedMetricDifference!int(5, 5) == 0.0);

    assert(
        signedMetricDifference!long(
            long.max,
            long.max - 1
        ) == 1.0
    );

    assert(
        signedMetricDifference!long(
            long.max - 1,
            long.max
        ) == -1.0
    );

    assert(
        signedMetricDifference!long(
            long.min + 1,
            long.min
        ) == 1.0
    );

    assert(
        signedMetricDifference!long(
            long.min,
            long.min + 1
        ) == -1.0
    );

    /*
     * Crossing zero also avoids signed overflow.
     */
    assert(
        signedMetricDifference!long(1, -1) == 2.0
    );

    assert(
        signedMetricDifference!long(-1, 1) == -2.0
    );

    assert(
        signedMetricDifference!long(
            long.max,
            long.min
        ) > 0.0
    );

    assert(
        signedMetricDifference!long(
            long.min,
            long.max
        ) < 0.0
    );


    /*
     * Point-to-segment distance.
     */
    {
        alias PD = Point2!double;
        alias SD = Segment2!double;

        MetricScalar!double d;

        assert(
            tryPointSegmentDistance(
                SD(
                    PD(0.0, 0.0),
                    PD(10.0, 0.0)
                ),
                PD(5.0, 3.0),
                d
            )
        );
        assert(d == 3.0);

        /*
         * Exact collinearity must produce exact zero, including when
         * internal power-of-two rescaling uses a positive exponent.
         *
         * This guards against a compiler/runtime-library difference in
         * zero-preserving power-of-two rescaling.
         */
        assert(
            tryPointSegmentDistance(
                SD(
                    PD(0.0, 0.0),
                    PD(4.0, 0.0)
                ),
                PD(2.0, 0.0),
                d
            )
        );
        assert(d == 0.0);

        assert(
            tryPointSegmentDistance(
                SD(
                    PD(0.0, 0.0),
                    PD(4.0, 0.0)
                ),
                PD(3.0, 0.0),
                d
            )
        );
        assert(d == 0.0);

        /*
         * Projection before the first endpoint.
         */
        assert(
            tryPointSegmentDistance(
                SD(
                    PD(0.0, 0.0),
                    PD(10.0, 0.0)
                ),
                PD(-3.0, 4.0),
                d
            )
        );
        assert(d == 5.0);

        /*
         * Projection beyond the second endpoint.
         */
        assert(
            tryPointSegmentDistance(
                SD(
                    PD(0.0, 0.0),
                    PD(10.0, 0.0)
                ),
                PD(13.0, 4.0),
                d
            )
        );
        assert(d == 5.0);

        /*
         * Degenerate segment behaves as a point.
         */
        assert(
            tryPointSegmentDistance(
                SD(
                    PD(1.0, 2.0),
                    PD(1.0, 2.0)
                ),
                PD(4.0, 6.0),
                d
            )
        );
        assert(d == 5.0);
    }


    /*
     * Large integral coordinates retain small geometric differences.
     */
    {
        alias PL = Point2!long;
        alias SL = Segment2!long;

        double d;

        assert(
            tryPointSegmentDistance(
                SL(
                    PL(long.max - 2, 0),
                    PL(long.max, 0)
                ),
                PL(long.max - 1, 1),
                d
            )
        );
        assert(d == 1.0);

        /*
         * The baseline spans almost the complete signed-long domain.
         */
        assert(
            tryPointSegmentDistance(
                SL(
                    PL(long.min, 0),
                    PL(long.max, 0)
                ),
                PL(0, 1),
                d
            )
        );
        assert(d == 1.0);
    }


    /*
     * Non-finite geometry is rejected.
     */
    {
        alias PD = Point2!double;
        alias SD = Segment2!double;

        double d = 123.0;

        assert(
            !tryPointSegmentDistance(
                SD(
                    PD(0.0, 0.0),
                    PD(1.0, 0.0)
                ),
                PD(double.nan, 0.0),
                d
            )
        );

        assert(d == 0.0);
    }


    /*
     * Finite geometry can still require a metric difference outside the
     * finite MetricScalar range.
     *
     * Failure must retain the documented zero result rather than expose
     * an infinite intermediate value.
     */
    {
        alias PD = Point2!double;
        alias SD = Segment2!double;

        double d = 123.0;

        assert(
            !tryPointSegmentDistance(
                SD(
                    PD(-double.max, 0.0),
                    PD( double.max, 0.0)
                ),
                PD(0.0, 1.0),
                d
            )
        );

        assert(d == 0.0);
    }


    /*
     * Point-to-segment distance follows MetricScalar.
     */
    static assert(
        is(
            typeof({
                double value;
                tryPointSegmentDistance(
                    Segment2!int.init,
                    Point2!int.init,
                    value
                );
                return value;
            }()) == double
        )
    );

    static assert(
        is(
            typeof({
                real value;
                tryPointSegmentDistance(
                    Segment2!real.init,
                    Point2!real.init,
                    value
                );
                return value;
            }()) == real
        )
    );



    /*
     * Basic metric behaviour.
     */
    alias P = Point2!double;

    auto a = P(0.0, 0.0);
    auto b = P(3.0, 4.0);

    assert(squaredDistance(a, b) == 25.0);
    assert(squaredDistance(b, a) == 25.0);

    assert(distance(a, b) == 5.0);
    assert(distance(b, a) == 5.0);

    assert(distance(a, a) == 0.0);


    /*
     * float storage deliberately computes in double.
     */
    static assert(
        is(typeof(distance(
            Point2!float.init,
            Point2!float.init
        )) == double)
    );

    static assert(
        is(typeof(squaredDistance(
            Point2!float.init,
            Point2!float.init
        )) == double)
    );


    /*
     * real storage retains real metric computation.
     */
    static assert(
        is(typeof(distance(
            Point2!real.init,
            Point2!real.init
        )) == real)
    );


    /*
     * Integer extremes must not overflow during component subtraction.
     */
    alias PI = Point2!int;

    auto intLo = PI(int.min, int.min);
    auto intHi = PI(int.max, int.max);

    assert(distance(intLo, intHi) > 0.0);
    assert(squaredDistance(intLo, intHi) > 0.0);


    /*
     * Most importantly, integer subtraction occurs before conversion
     * without destroying small differences between very large values.
     *
     * Casting both long coordinates to double before subtraction would
     * incorrectly turn this distance into zero.
     */
    alias PL = Point2!long;

    auto largeA = PL(long.max, 0);
    auto largeB = PL(long.max - 1, 0);

    assert(distance(largeA, largeB) == 1.0);
    assert(squaredDistance(largeA, largeB) == 1.0);


    /*
     * Complete signed-long span is handled without signed overflow.
     *
     * Precision after conversion to double is intentionally not claimed
     * to be exact.
     */
    auto longLo = PL(long.min, 0);
    auto longHi = PL(long.max, 0);

    auto extremeDistance = distance(longLo, longHi);

    assert(extremeDistance > 0.0);
    assert(extremeDistance != double.infinity);


    /*
     * Non-finite floating values follow IEEE/Phobos metric semantics.
     */
    auto infPoint = P(double.infinity, 0.0);

    assert(distance(a, infPoint) == double.infinity);
    assert(squaredDistance(a, infPoint) == double.infinity);

    auto nanPoint = P(double.nan, 0.0);

    assert(distance(a, nanPoint) != distance(a, nanPoint));
    assert(squaredDistance(a, nanPoint) !=
           squaredDistance(a, nanPoint));

    /*
     * Nearest point on a segment.
     */
    {
        alias S = Segment2!double;

        auto horizontal = S(
            Point2!double(0.0, 0.0),
            Point2!double(10.0, 0.0)
        );

        Point2!double nearest;

        assert(tryNearestPoint(
            horizontal,
            Point2!double(3.0, 4.0),
            nearest
        ));

        assert(nearest == Point2!double(3.0, 0.0));


        /*
         * Projection before and after the segment clamps to endpoints.
         */
        assert(tryNearestPoint(
            horizontal,
            Point2!double(-5.0, 2.0),
            nearest
        ));

        assert(nearest == Point2!double(0.0, 0.0));

        assert(tryNearestPoint(
            horizontal,
            Point2!double(15.0, 2.0),
            nearest
        ));

        assert(nearest == Point2!double(10.0, 0.0));


        /*
         * Degenerate segment.
         */
        auto degenerate = S(
            Point2!double(7.0, -3.0),
            Point2!double(7.0, -3.0)
        );

        assert(tryNearestPoint(
            degenerate,
            Point2!double(100.0, 100.0),
            nearest
        ));

        assert(nearest == Point2!double(7.0, -3.0));


        /*
         * Integral geometry returns floating metric geometry.
         */
        Point2!double integerNearest;

        assert(tryNearestPoint(
            Segment2!int(
                Point2!int(0, 0),
                Point2!int(10, 0)
            ),
            Point2!int(3, 4),
            integerNearest
        ));

        assert(integerNearest == Point2!double(3.0, 0.0));

        static assert(is(typeof(integerNearest) == Point2!double));


        /*
         * Large dot products that would overflow in the naive formula
         *
         *     dot(r, d) / dot(d, d)
         *
         * remain usable after exponent scaling.
         */
        auto huge = S(
            Point2!double(0.0, 0.0),
            Point2!double(1.0e300, 1.0e300)
        );

        assert(tryNearestPoint(
            huge,
            Point2!double(5.0e299, 6.0e299),
            nearest
        ));

        assert(nearest.x > 5.49e299);
        assert(nearest.x < 5.51e299);
        assert(nearest.y > 5.49e299);
        assert(nearest.y < 5.51e299);


        /*
         * Very different vector scales may make the unclamped
         * projection parameter overflow, but endpoint clamping remains
         * well-defined.
         */
        auto tiny = S(
            Point2!double(0.0, 0.0),
            Point2!double(1.0e-300, 0.0)
        );

        assert(tryNearestPoint(
            tiny,
            Point2!double(1.0e300, 0.0),
            nearest
        ));

        assert(nearest == Point2!double(1.0e-300, 0.0));


        /*
         * Large long coordinates retain exact component differences
         * before conversion to double.
         *
         * The spacing is chosen large enough to remain distinguishable
         * in the resulting double coordinates.
         */
        const long base = long.max - 8192;

        assert(tryNearestPoint(
            Segment2!long(
                Point2!long(base, 0),
                Point2!long(base + 8192, 0)
            ),
            Point2!long(base + 4096, 100),
            integerNearest
        ));

        assert(integerNearest.y == 0.0);


        /*
         * Non-finite input is outside the operation's domain.
         */
        assert(!tryNearestPoint(
            horizontal,
            Point2!double(double.nan, 0.0),
            nearest
        ));

        assert(nearest == Point2!double.init);

        assert(!tryNearestPoint(
            S(
                Point2!double(0.0, 0.0),
                Point2!double(double.infinity, 0.0)
            ),
            Point2!double(1.0, 1.0),
            nearest
        ));

        assert(nearest == Point2!double.init);


        /*
         * Finite endpoints whose component difference itself exceeds
         * the MetricScalar range are conservatively rejected.
         */
        assert(!tryNearestPoint(
            S(
                Point2!double(-double.max, 0.0),
                Point2!double(double.max, 0.0)
            ),
            Point2!double(0.0, 1.0),
            nearest
        ));

        assert(nearest == Point2!double.init);
    }


    /*
     * Segment length is point distance between the stored endpoints.
     */
    {
        import geo.segment : Segment2;

        auto segment = Segment2!double(
            Point2!double(0.0, 0.0),
            Point2!double(3.0, 4.0)
        );

        assert(segmentLength(segment) == 5.0);

        auto degenerate = Segment2!int(
            Point2!int(7, -3),
            Point2!int(7, -3)
        );

        assert(segmentLength(degenerate) == 0.0);

        /*
         * Integer differences retain the same protection as distance().
         */
        auto large = Segment2!long(
            Point2!long(long.max, 0),
            Point2!long(long.max - 1, 0)
        );

        assert(segmentLength(large) == 1.0);

        static assert(
            is(typeof(segmentLength(
                Segment2!float.init
            )) == double)
        );

        static assert(
            is(typeof(segmentLength(
                Segment2!real.init
            )) == real)
        );
    }


    /*
     * Polyline length is the sum of consecutive segment lengths.
     */
    {
        import geo.polyline_view : Polyline2View;

        alias PP = Point2!double;

        PP[3] points = [
            PP(0.0, 0.0),
            PP(3.0, 4.0),
            PP(6.0, 8.0)
        ];

        auto polyline =
            Polyline2View!double(points[]);

        assert(polyline.segmentCount == 2);
        assert(polylineLength(polyline) == 10.0);
    }


    /*
     * Compensated accumulation preserves small segment lengths that ordinary
     * sequential addition can lose after the running total becomes large.
     *
     * Each block contributes exactly:
     *
     *     2 * 2^52 + 2
     *
     * and the complete expected result is itself exactly representable as
     * binary64.
     */
    {
        alias PP = Point2!double;

        enum size_t blocks = 256;
        enum double large = 0x1p52;
        enum double expected = 0x1p61 + 512.0;

        PP[1 + blocks * 4] points;

        size_t index;

        points[index++] =
            PP(0.0, 0.0);

        foreach (_; 0 .. blocks)
        {
            points[index++] =
                PP(large, 0.0);

            points[index++] =
                PP(0.0, 0.0);

            points[index++] =
                PP(1.0, 0.0);

            points[index++] =
                PP(0.0, 0.0);
        }

        assert(index == points.length);

        const length =
            polylineLength(
                Polyline2View!double(points[])
            );

        assert(length == expected);
    }


    /*
     * Compensated accumulation retains the established floating-point
     * non-finite semantics.
     */
    {
        alias PP = Point2!double;

        PP[2] infinitePoints = [
            PP(0.0, 0.0),
            PP(double.infinity, 0.0)
        ];

        assert(
            polylineLength(
                Polyline2View!double(
                    infinitePoints[]
                )
            ) ==
            double.infinity
        );


        PP[2] nanPoints = [
            PP(0.0, 0.0),
            PP(double.nan, 0.0)
        ];

        const nanLength =
            polylineLength(
                Polyline2View!double(
                    nanPoints[]
                )
            );

        assert(nanLength != nanLength);


        /*
         * Every individual segment length is finite, but two double.max
         * segments overflow the accumulated result. A later finite segment
         * must leave that infinity intact.
         */
        PP[4] overflowPoints = [
            PP(0.0, 0.0),
            PP(double.max, 0.0),
            PP(0.0, 0.0),
            PP(1.0, 0.0)
        ];

        assert(
            polylineLength(
                Polyline2View!double(
                    overflowPoints[]
                )
            ) ==
            double.infinity
        );
    }


    /*
     * Empty and singleton polylines have zero length.
     */
    {
        import geo.polyline_view : Polyline2View;

        Point2!int[] emptyPoints;

        auto empty =
            Polyline2View!int(emptyPoints);

        assert(polylineLength(empty) == 0.0);

        Point2!int[1] singletonPoints = [
            Point2!int(7, -3)
        ];

        auto singleton =
            Polyline2View!int(
                singletonPoints[]
            );

        assert(polylineLength(singleton) == 0.0);
    }


    /*
     * Polyline metric result types follow the existing MetricScalar
     * policy.
     */
    static assert(
        is(typeof(polylineLength(
            Polyline2View!int.init
        )) == double)
    );

    static assert(
        is(typeof(polylineLength(
            Polyline2View!long.init
        )) == double)
    );

    static assert(
        is(typeof(polylineLength(
            Polyline2View!float.init
        )) == double)
    );

    static assert(
        is(typeof(polylineLength(
            Polyline2View!double.init
        )) == double)
    );

    static assert(
        is(typeof(polylineLength(
            Polyline2View!real.init
        )) == real)
    );

}

// A1 vector metric and directional contract regression coverage.
@safe unittest
{
    import geo.vector : Vector2;

    alias VI = Vector2!int;
    alias VL = Vector2!long;
    alias VF = Vector2!float;
    alias VD = Vector2!double;
    alias VR = Vector2!real;


    /*
     * Public result scalar policy.
     */
    static assert(
        is(typeof(dot(VI.init, VI.init)) == double)
    );

    static assert(
        is(typeof(dot(VL.init, VL.init)) == double)
    );

    static assert(
        is(typeof(dot(VF.init, VF.init)) == double)
    );

    static assert(
        is(typeof(dot(VD.init, VD.init)) == double)
    );

    static assert(
        is(typeof(dot(VR.init, VR.init)) == real)
    );

    static assert(
        is(typeof(squaredNorm(VI.init)) == double)
    );

    static assert(
        is(typeof(squaredNorm(VR.init)) == real)
    );

    static assert(
        is(typeof(norm(VI.init)) == double)
    );

    static assert(
        is(typeof(norm(VR.init)) == real)
    );


    /*
     * Mixed scalar vectors remain explicit conversions.
     */
    static assert(
        !__traits(
            compiles,
            dot(
                VI.init,
                VD.init
            )
        )
    );


    /*
     * try... output type follows MetricScalar.
     */
    Vector2!double normalizedInt;
    Vector2!real normalizedReal;

    static assert(
        __traits(
            compiles,
            tryNormalize(
                VI.init,
                normalizedInt
            )
        )
    );

    static assert(
        __traits(
            compiles,
            tryNormalize(
                VR.init,
                normalizedReal
            )
        )
    );

    Vector2!float wrongNormalized;

    static assert(
        !__traits(
            compiles,
            tryNormalize(
                VI.init,
                wrongNormalized
            )
        )
    );

    double angleInt;
    real angleReal;

    static assert(
        __traits(
            compiles,
            trySignedAngle(
                VI.init,
                VI.init,
                angleInt
            )
        )
    );

    static assert(
        __traits(
            compiles,
            trySignedAngle(
                VR.init,
                VR.init,
                angleReal
            )
        )
    );

    float wrongAngle;

    static assert(
        !__traits(
            compiles,
            trySignedAngle(
                VI.init,
                VI.init,
                wrongAngle
            )
        )
    );


    /*
     * Basic dot and squared-norm behaviour.
     */
    assert(
        dot(
            VI(3, 4),
            VI(-2, 5)
        ) == 14.0
    );

    assert(
        squaredNorm(
            VI(3, 4)
        ) == 25.0
    );

    assert(
        squaredNorm(
            VI(3, 4)
        ) ==
        dot(
            VI(3, 4),
            VI(3, 4)
        )
    );


    /*
     * Integral dot uses MetricScalar arithmetic rather than
     * exact-before-round integer accumulation.
     *
     * 2^53 + 1 and 2^53 map to the same binary64 value.
     */
    enum long twoTo53 =
        1L << 53;

    assert(
        dot(
            VL(
                twoTo53 + 1,
                twoTo53
            ),
            VL(
                1,
                -1
            )
        ) == 0.0
    );


    /*
     * Non-finite dot/squaredNorm behaviour follows ordinary
     * floating-point arithmetic.
     */
    assert(
        squaredNorm(
            VD(
                double.infinity,
                0.0
            )
        ) ==
        double.infinity
    );

    const nanSquaredNorm =
        squaredNorm(
            VD(
                double.nan,
                0.0
            )
        );

    assert(
        nanSquaredNorm !=
        nanSquaredNorm
    );


    /*
     * norm uses hypot directly instead of sqrt(squaredNorm).
     */
    const hugeAxis =
        VD(
            double.max,
            1.0
        );

    assert(
        squaredNorm(hugeAxis) ==
        double.infinity
    );

    assert(
        norm(hugeAxis) ==
        double.max
    );

    enum double smallestSubnormal =
        0x1p-1074;

    /*
     * Phobos 2.111 incorrectly returns the internally scaled value
     * for hypot(smallestSubnormal, 0). geo-d must preserve the
     * mathematical metric result at its supported compiler floor.
     */
    assert(
        norm(
            VD(
                smallestSubnormal,
                0.0
            )
        ) ==
        smallestSubnormal
    );

    assert(
        distance(
            Point2!double.init,
            Point2!double(
                smallestSubnormal,
                0.0
            )
        ) ==
        smallestSubnormal
    );


    /*
     * Ordinary normalization.
     */
    Vector2!double normalized;

    assert(
        tryNormalize(
            VD(3.0, 4.0),
            normalized
        )
    );

    assert(
        normalized.x > 0.599999999999999
        && normalized.x < 0.600000000000001
    );

    assert(
        normalized.y > 0.799999999999999
        && normalized.y < 0.800000000000001
    );


    /*
     * Scale-first normalization remains usable even when the
     * unscaled norm is not representable as a finite double.
     */
    assert(
        tryNormalize(
            VD(
                double.max,
                double.max
            ),
            normalized
        )
    );

    assert(normalized.isFinite);
    assert(normalized.x > 0.70);
    assert(normalized.x < 0.71);
    assert(normalized.y > 0.70);
    assert(normalized.y < 0.71);


    /*
     * Subnormal components are scaled before the direction is
     * constructed. A naive unscaled normalization can lose this.
     */
    assert(
        tryNormalize(
            VD(
                smallestSubnormal,
                smallestSubnormal
            ),
            normalized
        )
    );

    assert(normalized.isFinite);
    assert(normalized.x > 0.70);
    assert(normalized.x < 0.71);
    assert(normalized.y > 0.70);
    assert(normalized.y < 0.71);


    /*
     * Integral T.min is converted before absolute magnitude is formed.
     */
    assert(
        tryNormalize(
            VL(
                long.min,
                0
            ),
            normalized
        )
    );

    assert(
        normalized ==
        VD(-1.0, 0.0)
    );


    /*
     * Normalization failure resets the out result.
     */
    normalized =
        VD(9.0, 9.0);

    assert(
        !tryNormalize(
            VD.init,
            normalized
        )
    );

    assert(
        normalized ==
        VD.init
    );

    normalized =
        VD(9.0, 9.0);

    assert(
        !tryNormalize(
            VD(
                double.nan,
                1.0
            ),
            normalized
        )
    );

    assert(
        normalized ==
        VD.init
    );

    normalized =
        VD(9.0, 9.0);

    assert(
        !tryNormalize(
            VD(
                double.infinity,
                1.0
            ),
            normalized
        )
    );

    assert(
        normalized ==
        VD.init
    );


    /*
     * Signed-angle orientation and canonical branch cut.
     */
    enum double halfPi =
        1.57079632679489661923;

    enum double pi =
        3.14159265358979323846;

    const xAxis =
        VD(1.0, 0.0);

    const yAxis =
        VD(0.0, 1.0);

    const negativeXAxis =
        VD(-1.0, 0.0);

    double angle =
        123.0;

    assert(
        trySignedAngle(
            xAxis,
            yAxis,
            angle
        )
    );

    assert(
        angle > halfPi - 1.0e-15
        && angle < halfPi + 1.0e-15
    );

    assert(
        trySignedAngle(
            yAxis,
            xAxis,
            angle
        )
    );

    assert(
        angle > -halfPi - 1.0e-15
        && angle < -halfPi + 1.0e-15
    );

    assert(
        trySignedAngle(
            xAxis,
            negativeXAxis,
            angle
        )
    );

    assert(
        angle > pi - 1.0e-15
        && angle <= pi
    );

    assert(
        trySignedAngle(
            xAxis,
            xAxis,
            angle
        )
    );

    assert(angle == 0.0);

    /*
     * Canonical same-direction result is positive zero.
     */
    assert(
        1.0 / angle ==
        double.infinity
    );


    /*
     * Independent scaling avoids determinant/dot overflow for
     * large finite directions.
     */
    assert(
        trySignedAngle(
            VD(
                double.max,
                double.max
            ),
            VD(
                -double.max,
                double.max
            ),
            angle
        )
    );

    assert(
        angle > halfPi - 1.0e-15
        && angle < halfPi + 1.0e-15
    );


    /*
     * The same directional construction works for subnormal vectors.
     */
    assert(
        trySignedAngle(
            VD(
                smallestSubnormal,
                0.0
            ),
            VD(
                0.0,
                smallestSubnormal
            ),
            angle
        )
    );

    assert(
        angle > halfPi - 1.0e-15
        && angle < halfPi + 1.0e-15
    );


    /*
     * Zero and non-finite vectors fail and reset the out result.
     */
    angle =
        123.0;

    assert(
        !trySignedAngle(
            VD.init,
            xAxis,
            angle
        )
    );

    assert(angle == 0.0);

    angle =
        123.0;

    assert(
        !trySignedAngle(
            VD(
                double.nan,
                0.0
            ),
            xAxis,
            angle
        )
    );

    assert(angle == 0.0);

    angle =
        123.0;

    assert(
        !trySignedAngle(
            VD(
                double.infinity,
                0.0
            ),
            xAxis,
            angle
        )
    );

    assert(angle == 0.0);
}
