# Decision Guide: Modularization & Repository Topology

## When to keep everything in one repository (the default)

**Use when:** one product, even with multiple facets — app + marketing site
+ functions + data. This is the default for every new project.
**Avoid when:** a component has a genuinely different lifecycle or audience
(see splitting, below).
**Pros:** one clone, one CI setup, one issue tracker, atomic cross-component
changes (app + rules + functions in one commit), no version coordination
with yourself.
**Cons:** mixed-language tooling in one repo; CI needs path filters to avoid
rebuilding the app when only the site changed.
**Alternatives:** polyrepo per component — for a solo developer this
multiplies every piece of repo overhead by N for near-zero benefit.

## When to split a repository

Split only when at least one is true:

1. **Public/private boundary** — open-sourcing a package out of a private
   app.
2. **Independent consumers** — a Swift package used by 2+ apps must live in
   its own repo so SwiftPM can consume tagged versions.
3. **Different lifecycle** — a data repo updated daily vs an app released
   monthly, where the churn pollutes history and CI.

**Pros (when criteria met):** clean versioned dependency, independent
access control, focused CI.
**Cons:** cross-repo changes become two PRs + a version bump dance; more
repos to keep compliant with these standards.
**Alternatives:** local SwiftPM package inside the monorepo (gets you the
module boundary without the repo split — prefer this until criterion 2
actually happens).

## When to modularize Swift code (local packages)

Stay a single app target until one of these appears:

1. **Second target** shares code (widget, watch app, macOS version, App
   Intents extension) → extract the shared code to a local package.
2. **A reusable library emerges** that a future project will want →
   local package first; own repo when the second project arrives.
3. **Build times or tangled dependencies** measurably hurt — modularize
   along feature seams, guided by actual pain, not architecture blogs.

**Use:** local packages in `Packages/`, imported by the app project.
**Avoid:** pre-emptive 10-module skeletons on day one; module-per-screen;
splitting models from the only feature using them.
**Pros:** enforced API boundaries, faster incremental builds, testable in
isolation, trivial later promotion to its own repo.
**Cons:** each module adds `Package.swift` upkeep and mental routing
("where does this type live?"); over-modularized codebases are the solo
developer's most common self-inflicted wound.
**Alternatives:** folders + discipline (perfectly fine below ~10k lines);
Xcode targets/frameworks (more project-file complexity than SwiftPM, avoid).

## Rule of thumb

> Extract when the second consumer is real, split when the second repo
> criterion is met, and never before. Duplication is cheaper than the wrong
> abstraction, and both are cheaper than a repo you have to maintain.
