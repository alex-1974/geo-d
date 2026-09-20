/**
 * Scalar-domain definitions used by geo-d geometry primitives.
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
 *     September 12, 2026
 */
module geo.scalar;

static import euclid_core.scalar;

/**
 * True exactly for the scalar types supported by the geo-d core.
 *
 * The supported scalar domain is:
 *
 *     int
 *     long
 *     float
 *     double
 *     real
 *
 * This trait describes membership in the public scalar domain, not general
 * numeric convertibility. Qualified scalar types, enums, and user-defined
 * numeric-like types are deliberately excluded.
 */
alias isGeoScalar =
    euclid_core.scalar.isGeoScalar;


/// Example checking the exact public scalar domain.
@safe unittest
{
    import geo;

    static assert(isGeoScalar!int);
    static assert(isGeoScalar!long);
    static assert(isGeoScalar!float);
    static assert(isGeoScalar!double);
    static assert(isGeoScalar!real);

    static assert(!isGeoScalar!uint);
    static assert(!isGeoScalar!(const int));
}


@safe unittest
{
    static assert(isGeoScalar!int);
    static assert(isGeoScalar!long);
    static assert(isGeoScalar!float);
    static assert(isGeoScalar!double);
    static assert(isGeoScalar!real);

    static assert(!isGeoScalar!byte);
    static assert(!isGeoScalar!ubyte);
    static assert(!isGeoScalar!short);
    static assert(!isGeoScalar!ushort);
    static assert(!isGeoScalar!uint);
    static assert(!isGeoScalar!ulong);

    static assert(!isGeoScalar!bool);
    static assert(!isGeoScalar!char);
    static assert(!isGeoScalar!wchar);
    static assert(!isGeoScalar!dchar);

    static assert(!isGeoScalar!(const int));
    static assert(!isGeoScalar!(immutable double));

    enum E : int
    {
        value
    }

    static assert(!isGeoScalar!E);

    struct NumericLike
    {
        int value;
    }

    static assert(!isGeoScalar!NumericLike);
}
