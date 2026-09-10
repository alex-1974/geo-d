module area_exact_bench;

import geo.internal.area_exact :
    SignedAreaAccumulator,
    addAreaDeterminant;

import geo.internal.dyadic :
    SignedDyadicDifference,
    SignedDyadicProduct,
    decodeDyadicCoordinate,
    multiplyDyadicDifferences,
    subtractDyadicCoordinates,
    subtractDyadicProducts;

import geo.internal.dyadic_round :
    roundSignedDyadicToBinary64;

import geo.internal.orientation_dyadic :
    orientationDeterminantDyadic;

import std.bitmanip :
    DoubleRep;

import std.datetime.stopwatch :
    StopWatch;

import std.stdio :
    writefln;


enum size_t determinantIterations = 200_000;
enum size_t addIterations         = 200_000;
enum size_t roundIterations       = 200_000;

__gshared ulong sink;

__gshared SignedDyadicProduct[2] terms;
__gshared SignedAreaAccumulator[2] roundCases;


struct RelativeDeterminantCase
{
    SignedDyadicDifference firstX;
    SignedDyadicDifference firstY;
    SignedDyadicDifference secondX;
    SignedDyadicDifference secondY;
}


__gshared RelativeDeterminantCase[2] relativeCases;
__gshared SignedDyadicProduct[2] preparedP;
__gshared SignedDyadicProduct[2] preparedQ;


private ulong bits(double value)
{
    DoubleRep representation;
    representation.value = value;

    return
        representation.fraction ^
        (cast(ulong) representation.exponent << 52) ^
        (cast(ulong) representation.sign << 63);
}


private void bench(alias operation)(
    string name,
    size_t iterations
)
{
    ulong local;

    foreach (i; 0 .. 1_000)
        local ^= operation(i);

    StopWatch sw;
    sw.start();

    foreach (i; 0 .. iterations)
        local ^= operation(i);

    sw.stop();

    sink ^= local;

    writefln(
        "%-36s %12.2f ns/op",
        name,
        cast(double) sw.peek.total!"nsecs" /
            cast(double) iterations
    );
}


private RelativeDeterminantCase makeRelativeCase(
    double originXValue,
    double originYValue,
    double firstXValue,
    double firstYValue,
    double secondXValue,
    double secondYValue
)
    pure nothrow @safe @nogc
{
    const auto originX =
        decodeDyadicCoordinate(originXValue);

    const auto originY =
        decodeDyadicCoordinate(originYValue);

    const auto firstX =
        decodeDyadicCoordinate(firstXValue);

    const auto firstY =
        decodeDyadicCoordinate(firstYValue);

    const auto secondX =
        decodeDyadicCoordinate(secondXValue);

    const auto secondY =
        decodeDyadicCoordinate(secondYValue);


    RelativeDeterminantCase result;

    result.firstX =
        subtractDyadicCoordinates(
            firstX,
            originX
        );

    result.firstY =
        subtractDyadicCoordinates(
            firstY,
            originY
        );

    result.secondX =
        subtractDyadicCoordinates(
            secondX,
            originX
        );

    result.secondY =
        subtractDyadicCoordinates(
            secondY,
            originY
        );

    return result;
}


private SignedDyadicProduct determinantFromPrepared(
    ref const RelativeDeterminantCase value
)
    pure nothrow @safe @nogc
{
    const auto p =
        multiplyDyadicDifferences(
            value.firstX,
            value.secondY
        );

    const auto q =
        multiplyDyadicDifferences(
            value.firstY,
            value.secondX
        );

    return subtractDyadicProducts(
        p,
        q
    );
}


private void prepareCases()
{
    terms[0] =
        orientationDeterminantDyadic(
            1000.125,
            2000.375,
            1987.625,
            2111.875,
            1212.375,
            2977.625
        );

    terms[1] =
        orientationDeterminantDyadic(
            -731.5,
            812.25,
            493.75,
            -119.5,
            1220.875,
            2213.125
        );

    assert(terms[0].sign != 0);
    assert(terms[1].sign != 0);


    relativeCases[0] =
        makeRelativeCase(
            1000.125,
            2000.375,
            1987.625,
            2111.875,
            1212.375,
            2977.625
        );

    relativeCases[1] =
        makeRelativeCase(
            -731.5,
            812.25,
            493.75,
            -119.5,
            1220.875,
            2213.125
        );


    foreach (i; 0 .. relativeCases.length)
    {
        preparedP[i] =
            multiplyDyadicDifferences(
                relativeCases[i].firstX,
                relativeCases[i].secondY
            );

        preparedQ[i] =
            multiplyDyadicDifferences(
                relativeCases[i].firstY,
                relativeCases[i].secondX
            );
    }


    foreach (i; 0 .. roundCases.length)
    {
        SignedAreaAccumulator accumulator;

        addAreaDeterminant(
            accumulator,
            terms[i]
        );

        addAreaDeterminant(
            accumulator,
            terms[i]
        );

        roundCases[i] =
            accumulator;
    }
}


pragma(inline, false)
private ulong oneDeterminant(size_t i)
{
    const double offset =
        cast(double)(i & 1) *
        0.25;

    const auto term =
        orientationDeterminantDyadic(
            1000.125 + offset,
            2000.375,
            1987.625 + offset,
            2111.875,
            1212.375 + offset,
            2977.625
        );

    return
        cast(ulong)(term.sign + 1) ^
        term.magnitude.limb[67] ^
        term.magnitude.limb[68];
}


pragma(inline, false)
private ulong firstAdd(size_t i)
{
    SignedAreaAccumulator accumulator;

    addAreaDeterminant(
        accumulator,
        terms[i & 1]
    );

    return
        cast(ulong)(accumulator.sign + 1) ^
        accumulator.magnitude.limb[67] ^
        accumulator.magnitude.limb[68];
}


pragma(inline, false)
private ulong twoAdds(size_t i)
{
    const size_t index =
        i & 1;

    SignedAreaAccumulator accumulator;

    addAreaDeterminant(
        accumulator,
        terms[index]
    );

    addAreaDeterminant(
        accumulator,
        terms[index]
    );

    return
        cast(ulong)(accumulator.sign + 1) ^
        accumulator.magnitude.limb[67] ^
        accumulator.magnitude.limb[68];
}


pragma(inline, false)
private ulong onePreparedMultiply(size_t i)
{
    const size_t index =
        i & 1;

    const auto product =
        multiplyDyadicDifferences(
            relativeCases[index].firstX,
            relativeCases[index].secondY
        );

    return
        cast(ulong)(product.sign + 1) ^
        product.magnitude.limb[67] ^
        (
            cast(ulong)
                product.magnitude.limb[68]
            << 32
        );
}


pragma(inline, false)
private ulong twoPreparedMultiplies(size_t i)
{
    const size_t index =
        i & 1;

    const auto p =
        multiplyDyadicDifferences(
            relativeCases[index].firstX,
            relativeCases[index].secondY
        );

    const auto q =
        multiplyDyadicDifferences(
            relativeCases[index].firstY,
            relativeCases[index].secondX
        );

    return
        cast(ulong)(p.sign + 1) ^
        cast(ulong)(q.sign + 1) ^
        p.magnitude.limb[67] ^
        (
            cast(ulong)
                q.magnitude.limb[68]
            << 32
        );
}


pragma(inline, false)
private ulong preparedProductDifference(size_t i)
{
    const size_t index =
        i & 1;

    const auto value =
        subtractDyadicProducts(
            preparedP[index],
            preparedQ[index]
        );

    return
        cast(ulong)(value.sign + 1) ^
        value.magnitude.limb[67] ^
        (
            cast(ulong)
                value.magnitude.limb[68]
            << 32
        );
}


pragma(inline, false)
private ulong preparedDeterminant(size_t i)
{
    const auto value =
        determinantFromPrepared(
            relativeCases[i & 1]
        );

    return
        cast(ulong)(value.sign + 1) ^
        value.magnitude.limb[67] ^
        (
            cast(ulong)
                value.magnitude.limb[68]
            << 32
        );
}


pragma(inline, false)
private ulong roundOnly(size_t i)
{
    const auto value =
        roundCases[i & 1];

    return bits(
        roundSignedDyadicToBinary64(
            value.sign,
            value.magnitude,
            -2149
        )
    );
}


void main()
{
    prepareCases();

    bench!oneDeterminant(
        "one ordinary exact determinant",
        determinantIterations
    );

    bench!onePreparedMultiply(
        "one prepared dyadic multiply",
        determinantIterations
    );

    bench!twoPreparedMultiplies(
        "two prepared dyadic multiplies",
        determinantIterations
    );

    bench!preparedProductDifference(
        "prepared product difference",
        determinantIterations
    );

    bench!preparedDeterminant(
        "prepared exact determinant",
        determinantIterations
    );

    bench!firstAdd(
        "first determinant accumulation",
        addIterations
    );

    bench!twoAdds(
        "two determinant accumulations",
        addIterations
    );

    bench!roundOnly(
        "one area dyadic round",
        roundIterations
    );

    writefln("sink: %s", sink);
}
