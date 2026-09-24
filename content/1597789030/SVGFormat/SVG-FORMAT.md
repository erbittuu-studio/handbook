# The SVG format Colorful reads

For whoever draws a new page, and whoever changes the parser. The app owns a
small parser rather than a library — that only works if every page stays
inside this subset.

`scripts/validate.py svg_subset` enforces the rules below on every PR.

**Adding a page? Run `python3 Hosting/SVGFormat/canonicalize.py` first.** A raw
Corel export doesn't follow rules 1–2 — arbitrary class names, float-noise
stroke widths. The script rewrites a page into the vocabulary below without
touching the drawing, and is safe to re-run.

---

## Authoring rules

**1. One stylesheet vocabulary, shared by every page.**

```css
.fil0 {fill:white}                     a region a child can colour
.fil1 {fill:none}                      line art
.strN {stroke:black;stroke-width:N}    an outline N units wide
```

No hex colours, no inline `fill=`/`stroke=`/`style=` on a shape, no
`fill-rule` in a class. Stroke weights round to integers but aren't
flattened to one value — an artist's heavier outline stays heavier.

**2. Every page opens with one full-page backdrop, first shape in the file:**

```xml
<rect class="fil0" width="1024" height="1024"/>
```

That's the region behind the drawing, and what a tap on empty paper fills.
Drawn anywhere but first, it paints over everything before it.

**3. Every colourable region needs a fill. Line art must have `fill:none`.**

The app decides what's tappable by asking "does this shape have a fill?" Get
this backwards and a line becomes a paintable region, or a region becomes
untouchable — both fail silently.

**4. Every colourable region must be thick enough for a fingertip.**

The app has no tap tolerance — a tap only colours the region it's actually
inside. What matters is **thickness** (the widest circle that fits inside the
shape), not bounding-box size — a thin crescent has a large box and is still
unhittable.

| Thickness | On screen | Verdict |
|---|---|---|
| < 24 units | under 8 pt | too thin |
| 24–40 units | 8–13 pt | hittable, but fiddly |
| ≥ 40 units | 13 pt+ | aim here |

Canvas is 1024×1024; roughly 3 page units per point on the smallest
supported device. Anything under 24 units should be line art instead.

**5. Draw order is paint order.** Shapes render in document order; nothing
reorders them. A later shape covers an earlier one.

**6. Don't rely on `id`.** Many pages repeat ids — the app identifies a shape
by its position in the document, never by id. Name things however helps you;
the app won't read it.

**7. Canvas is square, 1024×1024**, `viewBox="0 0 1024 1024"` on every page.

**8. `fill-rule` is always even-odd**, hardcoded in the parser — a class
declaring `fill-rule:nonzero` is rejected, not silently ignored.

---

## The supported subset

| | Allowed |
|---|---|
| Elements | `path` `circle` `ellipse` `rect` `line` `polyline` `polygon` |
| Path commands | `M` `m` `L` `l` `C` `c` `Z` `z` (`H` `V` also parse) |
| Transform | `matrix(a b c d e f)` only |
| Style | `fill` `stroke` `stroke-width` `fill-rule` |

**Rejected, not silently dropped:** `g` groups · `use` · gradients · `text` ·
`image` · `clipPath` · `mask` · `symbol` · arc commands (`A`/`a`).

Corel's export produces no `<g>` groups for this drawing style. If a future
export starts emitting them, flatten the artwork first — a group's transform
would otherwise be lost.

---

## Two traps

**`stroke-width` scales with `transform`.** A stroke is measured in the
shape's own coordinates, so a `matrix()` that scales the shape scales its
outline too — apply the matrix to geometry but not the stroke and a thin
circle's outline can swallow the whole shape. The parser multiplies
`stroke-width` by `sqrt(|determinant|)` of the matrix.

**Numbers run together in path data.** `150,204-14,6` is four numbers — a
minus sign is its own separator. And a command repeats implicitly: `c`
followed by twelve numbers is two curves, not one. Splitting on whitespace
and commas alone bends the drawing subtly.

---

## Adding a page

1. Export from Corel as SVG 1.1, 1024×1024, no groups.
2. Drop it into `Hosting/RawPacks/<world>/`.
3. Run `python3 Hosting/SVGFormat/canonicalize.py` — not optional, a raw
   export needs its class names and stroke widths rewritten first.
4. Check by eye: regions have a fill, line art has `fill:none`, nothing
   colourable is thinner than 24 units. Neither can be derived from the file.
5. Open a PR. `scripts/validate.py svg_subset` checks it; merging publishes
   it — installed apps pick it up with no app update.
