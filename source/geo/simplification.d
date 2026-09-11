/**
 * Polyline simplification algorithms.
 */
module geo.simplification;

import geo.metric :
    MetricScalar,
    tryPointSegmentDistance;
import geo.point : Point2;
import geo.polyline_view : PolylineView;
import geo.scalar : isGeoScalar;
import geo.segment : Segment2;

import std.math.traits : isFinite;


/**
 * Returns the maximum workspace length required by
 * trySimplifyDouglasPeuckerInto() for a polyline containing pointCount
 * stored points.
 *
 * Empty, singleton, and two-point polylines require no auxiliary
 * workspace.
 *
 * For larger inputs, the iterative Douglas-Peucker implementation may
 * defer at most one right-hand section for each intermediate input
 * vertex.
 *
 * Returns:
 *
 *     max(pointCount - 2, 0)
 *
 * No allocation is performed.
 *
 * Complexity:
 *     O(1) time and O(1) auxiliary space.
 */
size_t douglasPeuckerWorkspaceSize(size_t pointCount)
    pure nothrow @safe @nogc
{
    return pointCount > 2
        ? pointCount - 2
        : 0;
}


/**
 * Simplifies a polyline using the Douglas-Peucker algorithm.
 *
 * Geometry scalars follow the geo-d scalar domain: `int`, `long`, `float`,
 * `double`, and `real`. The tolerance type must be MetricScalar!T.
 *
 * The output consists only of vertices selected from the input, in their
 * original order.
 *
 * For inputs containing at least two points, the first and last points are
 * always retained.
 *
 * A section is replaced by its baseline when every intermediate point has
 * computed Euclidean point-to-segment distance less than or equal to
 * tolerance.
 *
 * Distance decisions use the floating-point metric computation provided by
 * tryPointSegmentDistance(). They are not exact distance predicates. Values
 * near the tolerance threshold are therefore classified according to the
 * computed MetricScalar!T result.
 *
 * When several intermediate vertices have the same maximum computed
 * distance, the first one in stored order is selected as the split point.
 *
 * Parameters:
 *
 *     polyline     = input polyline view
 *     tolerance    = finite non-negative metric tolerance
 *     destination  = caller-owned output buffer
 *     workspace    = caller-owned iterative traversal workspace
 *     written      = number of output points on success
 *
 * destination must contain at least polyline.length elements.
 *
 * workspace must contain at least:
 *
 *     douglasPeuckerWorkspaceSize(polyline.length)
 *
 * elements.
 *
 * Input backing storage and destination storage must not overlap.
 * Overlap is not detected.
 *
 * Returns false when:
 *
 * - tolerance is negative or non-finite;
 * - an input coordinate is non-finite;
 * - destination is too small;
 * - workspace is too small; or
 * - a required metric computation cannot be represented finitely.
 *
 * On failure, written is zero. Destination contents after a failure are
 * unspecified.
 *
 * No topology-preservation guarantee is provided.
 *
 * No allocation is performed. The caller-provided workspace requires O(n)
 * elements in the worst case; beyond destination and workspace, the
 * algorithm uses O(1) auxiliary storage.
 *
 * Complexity:
 *     O(n^2) time in the worst case for n stored input points.
 */
bool trySimplifyDouglasPeuckerInto(T, R)(
    scope PolylineView!T polyline,
    R tolerance,
    scope Point2!T[] destination,
    scope size_t[] workspace,
    out size_t written
)
    pure nothrow @safe @nogc
if (
    isGeoScalar!T &&
    is(R == MetricScalar!T)
)
{
    alias M = MetricScalar!T;

    written = 0;

    const size_t pointCount =
        polyline.length;

    if (!isFinite(tolerance) || tolerance < M(0))
        return false;

    /*
     * Validate all coordinates before producing any output.
     */
    foreach (i; 0 .. pointCount)
    {
        if (!polyline[i].isFinite)
            return false;
    }

    if (destination.length < pointCount)
        return false;

    const size_t requiredWorkspace =
        douglasPeuckerWorkspaceSize(pointCount);

    if (workspace.length < requiredWorkspace)
        return false;

    /*
     * Degenerate input sizes need no Douglas-Peucker traversal.
     */
    if (pointCount == 0)
        return true;

    if (pointCount == 1)
    {
        destination[0] = polyline[0];
        written = 1;
        return true;
    }

    if (pointCount == 2)
    {
        destination[0] = polyline[0];
        destination[1] = polyline[1];
        written = 2;
        return true;
    }

    /*
     * Iterative depth-first traversal of the recursive
     * Douglas-Peucker subdivision tree.
     *
     * The workspace stores the end indices of deferred right-hand
     * sections. Only one size_t is needed for each pending section.
     */
    destination[0] = polyline[0];
    written = 1;

    size_t sectionStart = 0;
    size_t sectionEnd = pointCount - 1;
    size_t stackLength = 0;

    for (;;)
    {
        const Segment2!T baseline =
            Segment2!T(
                polyline[sectionStart],
                polyline[sectionEnd]
            );

        M maximumDistance = M(-1);
        size_t splitIndex = sectionStart + 1;

        foreach (
            index;
            sectionStart + 1 .. sectionEnd
        )
        {
            M pointDistance;

            if (
                !tryPointSegmentDistance(
                    polyline[index],
                    baseline,
                    pointDistance
                )
            )
            {
                written = 0;
                return false;
            }

            /*
             * Strict comparison deliberately retains the first point
             * when equal maximum distances occur.
             */
            if (pointDistance > maximumDistance)
            {
                maximumDistance = pointDistance;
                splitIndex = index;
            }
        }

        if (maximumDistance > tolerance)
        {
            /*
             * Process the left section immediately and defer the right
             * section.
             *
             * requiredWorkspace guarantees this write is in bounds.
             */
            workspace[stackLength] = sectionEnd;
            ++stackLength;

            sectionEnd = splitIndex;
            continue;
        }

        /*
         * This section can be represented by its baseline.
         * Its end point is therefore the next retained output point.
         */
        destination[written] =
            polyline[sectionEnd];
        ++written;

        if (stackLength == 0)
            break;

        sectionStart = sectionEnd;

        --stackLength;
        sectionEnd = workspace[stackLength];
    }

    return true;
}


@safe unittest
{
    /*
     * Workspace contract.
     */
    static assert(douglasPeuckerWorkspaceSize(0) == 0);
    static assert(douglasPeuckerWorkspaceSize(1) == 0);
    static assert(douglasPeuckerWorkspaceSize(2) == 0);

    static assert(douglasPeuckerWorkspaceSize(3) == 1);
    static assert(douglasPeuckerWorkspaceSize(4) == 2);
    static assert(douglasPeuckerWorkspaceSize(10) == 8);

    static assert(
        douglasPeuckerWorkspaceSize(size_t.max) ==
        size_t.max - 2
    );


    alias P = Point2!double;
    alias V = PolylineView!double;


    /*
     * Empty polyline.
     */
    {
        P[] input;
        P[] output;
        size_t[] workspace;

        auto polyline = V(input[]);

        size_t written = size_t.max;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 0);
    }


    /*
     * Singleton is copied unchanged.
     */
    {
        P[1] input = [
            P(3.0, 4.0)
        ];

        P[1] output;
        size_t[] workspace;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 1);
        assert(output[0] == input[0]);
    }


    /*
     * Two-point polyline is copied unchanged.
     */
    {
        P[2] input = [
            P(1.0, 2.0),
            P(5.0, 6.0)
        ];

        P[2] output;
        size_t[] workspace;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                1000.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 2);
        assert(output[0] == input[0]);
        assert(output[1] == input[1]);
    }


    /*
     * Collinear intermediate vertices may be removed even at zero
     * tolerance.
     */
    {
        P[5] input = [
            P(0.0, 0.0),
            P(1.0, 0.0),
            P(2.0, 0.0),
            P(3.0, 0.0),
            P(4.0, 0.0)
        ];

        P[5] output;
        size_t[3] workspace;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 2);
        assert(output[0] == P(0.0, 0.0));
        assert(output[1] == P(4.0, 0.0));
    }


    /*
     * Equality with tolerance permits removal.
     */
    {
        P[3] input = [
            P(0.0, 0.0),
            P(1.0, 1.0),
            P(2.0, 0.0)
        ];

        P[3] output;
        size_t[1] workspace;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                1.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 2);
        assert(output[0] == input[0]);
        assert(output[1] == input[2]);
    }


    /*
     * A point beyond tolerance is retained.
     */
    {
        P[3] input = [
            P(0.0, 0.0),
            P(1.0, 1.0),
            P(2.0, 0.0)
        ];

        P[3] output;
        size_t[1] workspace;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.5,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 3);

        foreach (i; 0 .. input.length)
            assert(output[i] == input[i]);
    }


    /*
     * Recursive subdivision is reproduced by the iterative traversal,
     * preserving stored point order.
     */
    {
        P[5] input = [
            P(0.0, 0.0),
            P(1.0, 2.0),
            P(2.0, 0.0),
            P(3.0, 2.0),
            P(4.0, 0.0)
        ];

        P[5] output;
        size_t[3] workspace;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.5,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 5);

        foreach (i; 0 .. input.length)
            assert(output[i] == input[i]);
    }


    /*
     * The documented n - 2 workspace bound is sufficient even when the
     * traversal reaches its maximum number of simultaneously deferred
     * right-hand sections.
     *
     * This reversed power-of-two zigzag causes every successive left
     * section to split at sectionEnd - 1. The traversal therefore pushes
     * all six deferred section ends before the first pop.
     */
    {
        P[8] input = [
            P(7.0,    0.0),
            P(6.0,    4.0),
            P(5.0,   -8.0),
            P(4.0,   16.0),
            P(3.0,  -32.0),
            P(2.0,   64.0),
            P(1.0, -128.0),
            P(0.0,  256.0)
        ];

        P[8] output;
        size_t[6] workspace;
        workspace[] = size_t.max;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == input.length);

        foreach (i; 0 .. input.length)
            assert(output[i] == input[i]);

        /*
         * Every workspace slot was reached:
         *
         *     7, 6, 5, 4, 3, 2
         */
        assert(workspace[0] == 7);
        assert(workspace[1] == 6);
        assert(workspace[2] == 5);
        assert(workspace[3] == 4);
        assert(workspace[4] == 3);
        assert(workspace[5] == 2);
    }


    /*
     * Equal maximum distances select the first vertex in stored order.
     *
     * Vertices 1 and 3 are both distance 1 from the initial baseline.
     * Selecting vertex 1 first allows the remaining right-hand section
     * to collapse at this tolerance.
     */
    {
        P[5] input = [
            P(0.0, 0.0),
            P(1.0, 1.0),
            P(2.0, 0.0),
            P(3.0, 1.0),
            P(4.0, 0.0)
        ];

        P[5] output;
        size_t[3] workspace;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.75,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 3);
        assert(output[0] == input[0]);
        assert(output[1] == input[1]);
        assert(output[2] == input[4]);
    }


    /*
     * Finite coordinates can still require a metric difference outside
     * the finite binary64 range. This is reported as failure rather than
     * silently simplifying with an infinite intermediate value.
     */
    {
        P[3] input = [
            P(-double.max, 0.0),
            P(0.0, 1.0),
            P(double.max, 0.0)
        ];

        P[3] output;
        size_t[1] workspace;

        auto polyline = V(input[]);

        size_t written = 99;

        assert(
            !trySimplifyDouglasPeuckerInto(
                polyline,
                1.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 0);
    }


    /*
     * Duplicate coordinates are permitted by the representation and do
     * not require implicit validation.
     */
    {
        P[4] input = [
            P(0.0, 0.0),
            P(0.0, 0.0),
            P(1.0, 0.0),
            P(2.0, 0.0)
        ];

        P[4] output;
        size_t[2] workspace;

        auto polyline = V(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 2);
        assert(output[0] == input[0]);
        assert(output[1] == input[$ - 1]);
    }


    /*
     * Invalid tolerance is rejected before output is produced.
     */
    {
        P[3] input = [
            P(0.0, 0.0),
            P(1.0, 1.0),
            P(2.0, 0.0)
        ];

        P[3] output;
        size_t[1] workspace;

        auto polyline = V(input[]);

        size_t written = 99;

        assert(
            !trySimplifyDouglasPeuckerInto(
                polyline,
                -1.0,
                output[],
                workspace[],
                written
            )
        );
        assert(written == 0);

        assert(
            !trySimplifyDouglasPeuckerInto(
                polyline,
                double.nan,
                output[],
                workspace[],
                written
            )
        );
        assert(written == 0);

        assert(
            !trySimplifyDouglasPeuckerInto(
                polyline,
                double.infinity,
                output[],
                workspace[],
                written
            )
        );
        assert(written == 0);
    }


    /*
     * Non-finite input is rejected.
     */
    {
        P[3] input = [
            P(0.0, 0.0),
            P(double.nan, 1.0),
            P(2.0, 0.0)
        ];

        P[3] output;
        size_t[1] workspace;

        auto polyline = V(input[]);

        size_t written = 99;

        assert(
            !trySimplifyDouglasPeuckerInto(
                polyline,
                1.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 0);
    }


    /*
     * Destination capacity is checked.
     */
    {
        P[3] input = [
            P(0.0, 0.0),
            P(1.0, 1.0),
            P(2.0, 0.0)
        ];

        P[2] output;
        size_t[1] workspace;

        auto polyline = V(input[]);

        size_t written = 99;

        assert(
            !trySimplifyDouglasPeuckerInto(
                polyline,
                1.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 0);
    }


    /*
     * Workspace capacity is checked.
     */
    {
        P[4] input = [
            P(0.0, 0.0),
            P(1.0, 1.0),
            P(2.0, -1.0),
            P(3.0, 0.0)
        ];

        P[4] output;
        size_t[1] workspace;

        auto polyline = V(input[]);

        size_t written = 99;

        assert(
            !trySimplifyDouglasPeuckerInto(
                polyline,
                0.0,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 0);
    }


    /*
     * Integral geometry uses the same public operation.
     */
    {
        alias PI = Point2!long;
        alias VI = PolylineView!long;

        PI[3] input = [
            PI(long.max - 2, 0),
            PI(long.max - 1, 1),
            PI(long.max, 0)
        ];

        PI[3] output;
        size_t[1] workspace;

        auto polyline = VI(input[]);

        size_t written;

        assert(
            trySimplifyDouglasPeuckerInto(
                polyline,
                0.5,
                output[],
                workspace[],
                written
            )
        );

        assert(written == 3);
    }


    /*
     * real remains supported through MetricScalar.
     */
    static assert(
        __traits(
            compiles,
            {
                Point2!real[3] input;
                Point2!real[3] output;
                size_t[1] workspace;

                auto polyline =
                    PolylineView!real(input[]);

                size_t written;

                trySimplifyDouglasPeuckerInto(
                    polyline,
                    real(0),
                    output[],
                    workspace[],
                    written
                );
            }
        )
    );
}
