module geo.scalar;

/**
 * True exactly for the scalar types supported by the geo-d v0.1 core.
 *
 * Qualified scalar template arguments are deliberately excluded.
 */
enum bool isGeoScalar(T) =
       is(T == int)
    || is(T == long)
    || is(T == float)
    || is(T == double)
    || is(T == real);

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
