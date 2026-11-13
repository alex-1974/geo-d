# Spezialisierte Vierecke

Diese Dokumentation beschreibt die v4-Shape-Familie oberhalb von
Quadrilateral2.

## Gemeinsame Regeln

Alle Shapes verwenden die mathematische Vertex-Reihenfolge:

~~~text
A = vertex(1)
B = vertex(2)
C = vertex(3)
D = vertex(4)
~~~

Die Kanten werden über ihre Endpunkte bezeichnet: AB, BC, CD, DA.

Alle Shapes sind intrinsisch. Sie besitzen keine Weltkoordinaten und keine
Weltorientierung. Die Koordinaten entstehen erst durch Placement2,
AnchorBinding2 oder toPolygon.

## Shape-Übersicht

| Shape | Primäre Parameter | Invariante |
| --- | --- | --- |
| Quadrilateral2 | AB, BC, CD, DA, AC | allgemeines konvexes Viereck |
| Trapezoid2 | AB, BC, CD, DA, Höhe | AB parallel CD |
| Parallelogram2 | AB, BC, Winkel B | AB parallel CD und BC parallel DA |
| Rhombus2 | Seitenlänge, Winkel | alle vier Seiten gleich |
| Kite2 | AB, BC, Winkel A | AB = AD und BC = CD |
| Rect2 | AB, BC | vier rechte Winkel |
| Square2 | Seitenlänge | Rechteck und alle Seiten gleich |

## Öffentliche Konstruktoren

~~~d
Quadrilateral2!T.tryFromSidesAndDiagonal(ab, bc, cd, da, ac, result);
Trapezoid2!T.tryFromBasesLegsAndHeight(ab, bc, cd, da, height, result);
Parallelogram2!T.tryFromSidesAndAngle(ab, bc, angleB, result);
Rhombus2!T.tryFromSideAndAngle(side, angle, result);
Kite2!T.tryFromSidesAndAngle(ab, bc, angleA, result);
Rect2!T.tryFromLengths(ab, bc, result);
Square2!T.tryFromSide(side, result);
~~~

Alle Konstruktoren setzen das Ergebnis bei Fehlschlag auf init zurück und
weisen nicht-positive oder geometrisch unmögliche Parameter zurück.

## Materialisierung

Alle spezialisierten Shapes verwenden dieselbe API:

~~~d
shape.toPolygon(placement);
shape.toPolygon(binding);
~~~

Die resultierende Geometrie ist immer ein owning Polygon2. Nach der
Materialisierung besteht kein API-Unterschied mehr zwischen einem Polygon aus
einem Shape und einem Polygon aus einer Punktfolge.

## Namensabgrenzung

Rect2 ist das intrinsische mathematische Rechteck-Shape. Es bleibt aus
Kompatibilitätsgründen auch aus Minimum-/Maximum-Koordinaten konstruierbar.
Die normative Shape-API verwendet jedoch die seitenbezogenen Parameter:

~~~d
rect.length.ab
rect.length.bc
~~~

Rectangle2 ist vorläufig nur noch ein Kompatibilitätsalias für Rect2.
Bounds2 bleibt der eigenständige koordinatengebundene Envelope-Typ.

## Validierungsprinzip

Die Formvalidierung erfolgt beim Konstruktor:

- endliche Werte;
- positive Längen;
- gültige Winkel;
- Dreiecksungleichungen bei diagonalen Konstruktionen;
- parallele beziehungsweise gleiche Kanten gemäß Shape-Invariante;
- nicht-degenerierte, konvexe kanonische Geometrie.

Die daraus erzeugten Polygone werden zusätzlich durch die bestehenden
Polygon- und Ring-Validierungen geprüft.

