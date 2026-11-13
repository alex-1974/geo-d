# Shape-Familie: einheitliche Spezifikation

Status: Research- und Planungsgrundlage für v4 und spätere geo/geo3-Versionen.

Dieses Dokument definiert die gemeinsame Sprache für Shapes. Es ist zunächst eine Spezifikation; die Implementierung erfolgt schrittweise und darf die bestehende v1/v2-Kompatibilität nicht ungeplant brechen.

## 1. Grundmodell

Ein Shape beschreibt ausschließlich eine intrinsische geometrische Form. Koordinaten, Orientierung und Platzierung gehören nicht zum Shape.

```
Shape      = intrinsische Maße und geometrische Beziehungen
Placement  = Zuordnung zu einem Koordinatenraum
Polygon    = materialisierte Koordinaten des platzierten Shapes
```

Die öffentliche API verwendet mathematische Bezeichnungen. Intern dürfen kompakte kanonische Repräsentationen und abgeleitete Werte verwendet werden, solange die intrinsischen Maße verlustfrei rekonstruierbar bleiben.

## 2. Nomenklatur

Vertices werden mathematisch mit Großbuchstaben bezeichnet und in der API zusätzlich mit einem 1-basierten Index angesprochen:

```
vertex(1) = A
vertex(2) = B
vertex(3) = C
```

Bei geschlossenen 2D- und 3D-Formen werden die Vertices in positivem Umlaufsinn beziehungsweise schichtweise und konsistent angeordnet.

Kanten werden über ihre Endvertices benannt:

```
AB, BC, CD, ...
length.ab, length.bc, length.cd, ...
```

Winkel werden über den Vertex benannt:

```
angle.a = Winkel BAC
angle.b = Winkel ABC
```

Shape-spezifische Aliase sind zulässig. Beim Rechteck sind `length.x` und `length.y` Aliase für `length.ab` und `length.bc`; die allgemeine Placement-API bleibt jedoch kantenbezogen.

## 3. 2D-Shape-Katalog

| Shape | Eindeutige intrinsische Parameter | Konstruktionsfamilien | Interne Zielrepräsentation |
| --- | --- | --- | --- |
| `Point2` | keine intrinsischen Maße | Koordinate | `x`, `y` |
| `Line2` | Punkt und Richtung | Punkt+Winkel, zwei Punkte | Ursprung + normierter Richtungsvektor |
| `Ray2` | Punkt und Richtung | Punkt+Winkel, zwei Punkte | Ursprung + Richtungsvektor |
| `Segment2` | Länge | Länge; zwei Endpunkte als abgeleitete Konstruktion | `length` |
| `Circle2` | Radius | Radius, Durchmesser, Umfang, Fläche | `radius` |
| `Ellipse2` | Halbachsen | Halbachsen, Achsenverhältnis+eine Halbachse, Fläche+eine Halbachse | `semiAxis.a`, `semiAxis.b` |
| `Triangle2` | `length.ab`, `length.bc`, `length.ca` | SSS, SAS, ASA, AAS; SSA mit expliziter Lösungswahl | drei Seitenlängen |
| `Quadrilateral2` | vier Kanten plus ausreichende Winkel-/Diagonal-Constraints | vier Punkte, Kanten+Winkel, Kanten+Diagonalen | vier Kanten + Constraints |
| `Trapezoid2` | parallele Basis `AB || CD` plus vier Kanten oder Basis/Höhe/Seiten | Basen+Höhe, Basen+Schenkel, Punkte | Basen, Schenkel, Höhe/Winkel |
| `Parallelogram2` | `AB`, `BC`, `angle.b` | SAS, Seite+Höhe, Diagonalen | zwei Seiten + eingeschlossener Winkel |
| `Rhombus2` | Seitenlänge + Winkel oder Diagonalen | Seite+Winkel, Diagonalen | Seite + Winkel |
| `Kite2` | zwei Paare gleicher Nachbarkanten plus Winkel/Diagonale | Seitenpaare+Winkel, Diagonalen | zwei Seitenlängen + Winkel/Diagonalrelation |
| `Rect2` | `length.ab`, `length.bc`, rechte Winkel | zwei Seiten, Diagonale+Seite, Fläche+Seite | zwei Seitenlängen |
| `Square2` | eine Seitenlänge | Seite, Diagonale, Fläche, Umfang | eine Seitenlänge |
| `RegularPolygon2` | Seitenanzahl `n` + eine Größe | Seitenlänge, Umkreisradius, Inkreisradius, Fläche | `sideCount` + kanonische Größe |
| `Polygon2` | geordnete Vertices | Punktfolge | Punktfolge/Ringstruktur |
| `CircularArc2` | Radius + Winkelintervall | Mittelpunkt+Winkel, Endpunkte+Radius, Sehne+Höhe | Radius + Start-/Endwinkel |
| `CircularSector2` | Radius + Zentralwinkel | Radius+Winkel, Bogen+Radius | Radius + Winkel |
| `CircularSegment2` | Radius + Sehne/Höhe oder Zentralwinkel | Radius+Sehne, Radius+Winkel, Sehne+Höhe | Radius + Sehne/Winkel |
| `Annulus2` | Außen- und Innenradius | zwei Radien, Fläche+Radius | `outerRadius`, `innerRadius` |
| `Capsule2` | Achsenlänge + Radius | Achse+Radius, Gesamtlänge+Radius | Achsenlänge + Radius |
| `RoundedRectangle2` | zwei Seitenlängen + Eckradius | Seiten+Radius, Seiten+Eckdurchmesser | Seiten + Radius |

`Polygon2` bleibt das allgemeine koordinatenbasierte Polygon. Die parametrischen Shapes sind mathematische Modelle und können über `toPolygon` materialisiert werden.

## 4. 3D-Shape-Katalog

| Shape | Eindeutige intrinsische Parameter | Konstruktionsfamilien | Interne Zielrepräsentation |
| --- | --- | --- | --- |
| `Point3` | keine intrinsischen Maße | Koordinate | `x`, `y`, `z` |
| `Line3` | Punkt + Richtung | Punkt+Richtung, zwei Punkte | Ursprung + Richtungsvektor |
| `Plane3` | Punkt + Normale | drei Punkte, Punkt+Normale | Ursprung + Normale |
| `Tetrahedron3` | sechs Kanten; regulär: eine Kante | sechs Kanten, vier Punkte | Kanten/Constraints |
| `Cuboid3` | `length.ab`, `length.bc`, `length.ae` | drei Kanten, Raumdiagonale+zwei Kanten | drei Kantenlängen |
| `Cube3` | eine Kantenlänge | Kante, Raumdiagonale, Volumen | eine Kantenlänge |
| `Prism3` | Grundpolygon + Extrusionslänge | Grundpolygon+Höhe, Grundpolygon+Seitenkante | Grundshape + Höhe |
| `Pyramid3` | Grundpolygon + Höhe oder Seitenkanten | Grundpolygon+Höhe, Grundpolygon+Seitenkante | Grundshape + Höhe |
| `Frustum3` | zwei ähnliche parallele Grundflächen + Höhe | zwei Grundgrößen+Höhe, Seitenkanten | Grundflächen + Höhe |
| `RegularPolyhedron3` | Typ + eine Größe | Kante, Umkugelradius, Inkugelradius | Typ + Kantenlänge |
| `Sphere3` | Radius | Radius, Durchmesser, Oberfläche, Volumen | `radius` |
| `Ellipsoid3` | drei Halbachsen | drei Halbachsen, Volumen+zwei Halbachsen | `semiAxis.x/y/z` |
| `Cylinder3` | Radius + Höhe | Radius+Höhe, Durchmesser+Höhe, Mantellinie+Radius | Radius + Höhe |
| `Cone3` | Grundradius + Höhe oder Mantellinie | Radius+Höhe, Radius+Mantellinie | Radius + Höhe/Mantellinie |
| `TruncatedCone3` | zwei Radien + Höhe | zwei Radien+Höhe, Radien+Mantellinie | zwei Radien + Höhe |
| `Torus3` | Hauptradius + Rohrradius | zwei Radien | `majorRadius`, `minorRadius` |
| `Capsule3` | Achsenlänge + Radius | Zylinderhöhe+Radius, Gesamtlänge+Radius | Achsenlänge + Radius |

Für geschichtete Körper gilt die Vertex-Konvention:

```
A, B, C, D = Grundfläche
E, F, G, H = Deckfläche
E liegt über A, F über B, ...
```

Beim Quader sind die Standardkanten daher `AB`, `BC` und `AE`.

## 5. Konstruktor- und API-Regeln

Neue öffentliche Konstruktoren liefern strukturierte Resultate:

~~~d
auto result = Triangle2!double.fromSSS(ab, bc, ca);
if (!result.valid)
    // result.status beschreibt den Konstruktionsfehler
~~~

Die Bool-/Out-Varianten bleiben zunächst als Kompatibilitäts- und
Low-Level-API erhalten.

Konstruktoren werden nach der geometrischen Fallgruppe benannt. Das vermeidet Mehrdeutigkeiten bei gleichen Parametertypen:

```d
Triangle2!T.fromSSS(ab, bc, ca)
Triangle2!T.fromSAS(ab, angle.b, bc)
Triangle2!T.fromASA(angle.a, ab, angle.b)
Triangle2!T.fromAAS(angle.a, angle.b, ab)
```

Die Parameter werden als benannte Measure-Typen geführt:

```d
Length!T
Angle!T
Radius!T
Area!T
Volume!T
Size2!T
Size3!T
```

Jeder Konstruktor muss:

1. endliche und positive Maße prüfen;
2. geometrische Existenzbedingungen prüfen;
3. Mehrdeutigkeiten explizit behandeln;
4. eine kanonische interne Repräsentation erzeugen;
5. abgeleitete Maße daraus berechnen oder deterministisch ableiten.

Bei mehrdeutigen Fällen wie SSA wird die Lösungswahl Teil der API und nicht implizit geraten.

## 6. Placement und Materialisierung

Placement verwendet zwei Deskriptoren:

```d
vertex(edge1, edge2, coordinate)
edge(length, angle)
```

Ein Vertex ist der Schnittpunkt seiner beiden angrenzenden Kanten. Die Kantenreferenz bleibt dabei erhalten; eine bloße numerische Länge genügt nicht, weil mehrere Kanten dieselbe Länge besitzen können.

Die einheitlichen Formen sind:

```d
shape.placement(vertex(...), vertex(...))
shape.placement(vertex(...), edge(...))
shape.toPolygon(placement)
```

`vertex/vertex` bestimmt Translation und Rotation aus zwei Korrespondenzen; eine Skalierung ist nur über eine explizite Policy erlaubt. `vertex/edge` verwendet die benannte intrinsische Kante und deren Weltwinkel.

## 7. Umsetzungsreihenfolge

1. Nomenklatur und Measure-Typen stabilisieren.
2. intrinsische Repräsentationen für Dreieck und Rechteck abschließen.
3. gemeinsame Placement-Deskriptoren implementieren.
4. `toPolygon` für Rechteck, Dreieck und regelmäßige Polygone.
5. allgemeine Vierecke und deren Spezialisierungen.
6. Ellipse und kreisbasierte Flächenformen.
7. 3D-Polyeder und Rotationskörper analog zu 2D.

Diese Reihenfolge erlaubt stückweise Umsetzung, ohne die gemeinsame API für spätere Shapes erneut zu erfinden.

