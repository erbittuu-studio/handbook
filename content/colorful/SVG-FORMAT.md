# The SVG format Colorful reads

Two audiences: whoever draws a new page, and whoever changes the parser. Every
number here was measured across all 88 pages in `Hosting/Artwork/`, not assumed.

All 88 are CorelDRAW X7 exports of the same drawing style. The app owns a small
parser rather than a library **because** the format is this narrow — so keeping
new pages inside it is what keeps colouring working.

`scripts/validate.py svg_subset` enforces the rules below on every PR. If a
page fails it, the page is wrong, not the check.

**Adding a page? Run `python3 Hosting/build.py canonicalize` first.** A raw Corel
export does not follow rules 1 and 2 — it names classes arbitrarily and writes
stroke widths as float noise. The script rewrites a page into the vocabulary
below without touching the drawing, and is safe to re-run. It was verified by
rendering all 88 pages before and after: 87 came out pixel-identical and the
88th differed by a single anti-aliased pixel.

---

## Authoring rules

### 1. One stylesheet vocabulary, shared by every page.

```css
.fil0 {fill:white}                     a region a child can colour
.fil1 {fill:none}                      line art
.strN {stroke:black;stroke-width:N}    an outline N units wide
```

That is the whole vocabulary. A class name means the same thing in every file,
and `.str6` says what it is — no lookup needed.

Corel does not do this. It emits per-file names, so `.fil1` used to mean
`fill:white` in 54 pages and `fill:none` in 27 — the same name, opposite
meanings — and wrote stroke widths as `5.99882`, `15.9992`, `3.99922`: twenty
values for what were really ten weights. Nothing was wrong with any one file,
but the app had to absorb all of it.

Stroke weights are **not** flattened to a single number. 87% of strokes already
render at 6, and the other 13% are the artist's choice — a heavy outer contour,
a fine whisker. Weights are rounded to integers (a shift of at most 0.0012
units) and otherwise left alone.

No hex colours, no inline `fill=` / `stroke=` / `style=` on a shape, and no
`fill-rule` in a class — the app always uses even-odd and ignores it, so a page
declaring otherwise renders differently than it reads.

### 2. Every page opens with one full-page backdrop.

```xml
<rect class="fil0" width="1024" height="1024"/>
```

Exactly one, covering the page, as the **first** shape in the file. It is the
boundary a child colours inside — the region behind the drawing, and what a tap
on empty paper fills. Drawn anywhere but first, it paints over the shapes before
it; drawn twice, only the last one is visible.

Measured before this rule existed: 5 pages had no backdrop at all, 4 were inset
1018x1018 leaving a hairline of bare page, and 3 carried a stroke — a black
border round the page nobody asked for.

### 3. Every colourable region needs a fill. Line art must have `fill:none`.

This is the single rule the whole feature rests on.

The app decides what a child can colour by asking "does this shape have a fill?"
A shape with `fill:white` is a region. A shape with `fill:none` is line art —
untouchable, so a tap on a line passes through to the region beneath it.

Get this wrong and the failure is quiet: line art with a fill becomes a tappable
"region" that paints over the drawing, and a region with `fill:none` becomes a
white area a child can see but never colour.

### 4. Make every colourable region thick enough for a fingertip.

The app has no tap tolerance, deliberately. A tap colours a region only when it
lands **inside** that region — nothing snaps, nothing reaches for a nearby shape,
nothing guesses what was meant. Tolerance was implemented and then removed: it
redirected 14% of taps onto a shape the finger was not on, which is worse than a
tap that does nothing, because it silently colours the wrong thing.

So reachability is the drawing's job.

The measure that matters is **thickness** — the widest circle that fits inside the
region — not bounding-box size. A long thin crescent has a large box and is
impossible to hit.

| Thickness | On screen | Verdict |
|---|---|---|
| **< 24 units** | under 8 pt | too thin — a fingertip cannot land in it |
| **24–40 units** | 8–13 pt | hittable, but fiddly for small hands |
| **>= 40 units** | 13 pt and up | comfortable — aim here |

Units are page units on the 1024 x 1024 canvas. The page renders about 340 pt
square on the smallest supported device, so **1 pt is roughly 3 page units**.

Measured over the current 88 pages: median thickness is 80 units, but 123 regions
across 37 pages fall under 24. Those pages predate this rule and still ship — they
are the reason it is written down. Detail below about 24 units should be drawn as
line art (`fill:none`) instead of as a region a child will try and fail to colour.

### 5. Draw order is paint order. Later shapes cover earlier ones.

Shapes render in document order, each drawing its own fill and then its own
stroke. A later white shape hides the strokes of earlier ones, and artists rely
on that to tidy joins.

Nothing reorders shapes. If a page looks wrong, the order in the file is the
order on screen.

### 6. Do not rely on `id`. Use it for notes only.

**54 of 88 pages repeat an id**, 602 duplicates in total — `id="crop0"` appears
many times in one file. The app identifies a shape by its position in the
document, never by id.

The old app keyed its fill logic on ids (`line_a` / `a_line` pairs) and could
fill the wrong shape as a result. Name things however helps you; the app will
not read it.

### 7. Keep the canvas square, 1024 x 1024.

Every page is `viewBox="0 0 1024 1024"`. The canvas is square, so a page with
different proportions renders letterboxed and smaller than its neighbours.

### 8. `fill-rule` is even-odd, always.

The root carries `fill-rule:evenodd`, and both rendering and tap-testing use it.
A shape with a hole has a hole — tapping the hole colours whatever is underneath,
not the ring.

The parser does not read `fill-rule` at all; even-odd is hardcoded. That is safe
because only 5 fillable shapes in the whole corpus (on `baby_6`, `baby_7` and
`climate_weather_5`) have more than one subpath, which is the only place the two
rules can differ. A class declaring `fill-rule:nonzero` is rejected rather than
silently ignored.

---

## The supported subset

Stay inside this and the app renders the page exactly.

| | Allowed |
|---|---|
| Elements | `path` `circle` `ellipse` `rect` `line` `polyline` `polygon` |
| Path commands | `M` `m` `L` `l` `C` `c` `Z` `z` (`H` `V` also parse) |
| Transform | `matrix(a b c d e f)` only |
| Style | `fill` `stroke` `stroke-width` `fill-rule` |

**Not supported, and rejected rather than silently dropped:**
`g` groups · `use` · `linearGradient` / `radialGradient` · `text` · `image` ·
`clipPath` · `mask` · `symbol` · arc commands (`A` / `a`).

None of these appear in the current 88 pages. Arcs matter most: converting them
to béziers is the fiddliest part of any SVG parser, and avoiding them is a large
part of why this parser is short enough to trust.

### Flatten groups before exporting

Corel's SVG export produces no `<g>` elements for these drawings. If a future
export starts emitting them, flatten the artwork first — a group's transform
would otherwise be lost, moving every shape inside it.

---

## What the corpus actually contains

```
files              88, average 3.2 KB, largest 6.6 KB
viewBox            0 0 1024 1024   (identical in all 88)
elements           path 923 · circle 238 · ellipse 177 · polygon 141
                   rect 134 · line 133 · polyline 27
path commands      M 923 · c 1429 · l 951 · m 6 · z 802
transforms         matrix 167   (nothing else)
css properties     fill 219 · stroke 155 · stroke-width 155 · fill-rule 1
fill values        white 151 · none 64 · #FEFEFE 4
shapes             1773 total, 1348 of them fillable
```

1773 `class` attributes against 363 `id`s: presentation is classes, ids are
incidental.

---

## Two traps, both found the hard way

### `stroke-width` scales with `transform`

A stroke is measured in the shape's own coordinates, so a `matrix()` that scales
the shape scales its outline too.

One page draws its caterpillar's spots as `r="45"` circles shrunk by a matrix,
with `stroke-width:15.9992`. Applying the matrix to the geometry but not the
stroke left a 16-unit outline on a circle scaled down to a ~13-unit radius: the
outline swallowed the circle and every spot rendered as a solid black blob.

The parser multiplies `stroke-width` by `sqrt(|determinant|)` of the matrix —
the geometric mean of the two axis scales, which stays correct when a matrix also
rotates or shears.

### Numbers run together in path data

`150,204-14,6` is four numbers: a minus sign is its own separator. And a command
repeats implicitly — `c` followed by twelve numbers is two curves, not one curve
and six strays. Splitting on whitespace and commas alone bends the drawing subtly
enough to look like a drawing mistake.

---

## Adding a page

1. Export from Corel as SVG 1.1, 1024 x 1024, no groups.
2. Drop it into `Hosting/Artwork/<category>/`.
3. Run `python3 Hosting/build.py canonicalize`. This is not optional — a raw export
   uses its own class names and float-noise stroke widths, and the script
   rewrites it into the shared vocabulary without touching the drawing.
4. Check by eye that regions have a fill and line art has `fill:none`, and that
   nothing colourable is thinner than 24 units (rule 4). Neither can be derived
   from the file; both are drawing decisions.
5. Open a PR. `scripts/validate.py svg_subset` and `data-ci` check it, and merging
   publishes it — installed apps pick it up from the manifest with no app update.
