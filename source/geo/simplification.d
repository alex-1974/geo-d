module geo.simplification;


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
 */
size_t douglasPeuckerWorkspaceSize(size_t pointCount)
    pure nothrow @safe @nogc
{
    return pointCount > 2
        ? pointCount - 2
        : 0;
}


@safe unittest
{
    static assert(douglasPeuckerWorkspaceSize(0) == 0);
    static assert(douglasPeuckerWorkspaceSize(1) == 0);
    static assert(douglasPeuckerWorkspaceSize(2) == 0);

    static assert(douglasPeuckerWorkspaceSize(3) == 1);
    static assert(douglasPeuckerWorkspaceSize(4) == 2);
    static assert(douglasPeuckerWorkspaceSize(10) == 8);

    /*
     * The formulation must not underflow or overflow at the size_t
     * domain boundary.
     */
    static assert(
        douglasPeuckerWorkspaceSize(size_t.max) ==
        size_t.max - 2
    );
}
