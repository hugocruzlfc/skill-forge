---
name: nextjs-feature-architecture
description: "Architecture guide for Next.js App Router projects organized by features: thin routes in src/app, code grouped by domain in src/features/<name>, plus shared and lib layers. Use whenever the user adds or changes a page, route, feature, server action, query, form, hook, store or validation schema in a Next.js project, asks where some code should live, or wants to scaffold or refactor toward a feature-based structure, even if they never say 'architecture' or 'features'. Backend-agnostic: Supabase, Prisma, Drizzle or any other data layer lives in lib."
---

# Next.js feature architecture

In a feature-based project, code is grouped by what it is *for* (products, cart, auth)
and not by what it *is* (components, hooks, utils). Routes only connect URLs to
features. Knowing this tells you where every new file goes and what it may import,
which is most of what you need before touching the codebase.

This skill is about **where code lives**. It does not teach Next.js APIs.

## Before you change anything

1. **Read the project first.** Check whether `src/features/` exists, list the existing
   features, and read one feature similar to your task from route to data access.
   The project's existing conventions win over this guide. If the project is not
   feature-based, do not restructure it unprompted: follow what is there, and mention
   the option once if it would clearly help.
2. **Do not rely on memory for Next.js APIs.** Caching, `params`, and cache
   invalidation change between versions. Check the installed version in
   `package.json` and read the matching docs (usually `node_modules/next/dist/docs/`;
   `AGENTS.md` often points to it).
3. **Defer to specialist skills** when they are installed (cache components, React
   performance, database practices). Use this one only for placement and structure.

## The layers

| Layer | Path | Holds | May import from |
|---|---|---|---|
| Routes | `src/app` | `page`, `layout`, `loading`, `error`, `route` files. Parse params, call a query, render a feature component. | features, shared |
| Features | `src/features/<name>` | Everything about one domain. | shared, lib |
| Shared | `src/shared` | UI, hooks and types used by two or more features (app shell, navbar, footer). | lib |
| Lib | `src/lib` | Infrastructure: database or ORM client, auth client, env validation, third-party SDKs, generic utilities. | nothing from the app |
| Assets | `src/assets` | Images, icons, fonts. | n/a |

Imports only go downward: `app → features → shared → lib`. Never upward, because an
upward import makes the lower layer depend on something that can change faster than it.

Whatever the backend is (Supabase, Prisma, Drizzle, Firebase, a REST API), it sits in
`lib`. Features reach it only through their own `queries/` and `actions/`, so swapping
backends touches `lib` and those two folders, not the components.

## Anatomy of a feature

```
src/features/<name>/
├── queries/        server-only reads
├── actions/        "use server" mutations
├── hooks/          client hooks (forms, flows)
├── schema.ts       validation schemas (zod) for this feature
├── types.ts        domain types for this feature
├── store.ts        client state owned by this feature
└── *.tsx           components, flat at the root
```

Create only what the feature needs. Never add empty folders "for later". When a
feature has more than about 8 component files, move them into `components/`.
Details and examples: `references/feature-anatomy.md`.

## Where does it go?

| You are adding | Put it in |
|---|---|
| A URL / page | `src/app/.../page.tsx`, thin. The UI lives in `features/<name>/` |
| A read from the database or an API | `features/<name>/queries/` |
| A write (create, update, delete) | `features/<name>/actions/` |
| Input validation | `features/<name>/schema.ts` |
| A form or multi-step client flow | `features/<name>/hooks/` |
| Client state used by one feature | `features/<name>/store.ts` |
| Client state used app-wide (session, theme) | `src/shared/` (provider) or `src/store/` |
| A component used by one feature | `features/<name>/` |
| A component used by two or more features | `src/shared/components/` |
| A domain type | `features/<name>/types.ts` |
| DB client, ORM, auth client, env, SDK | `src/lib/` |
| Generated database types | `src/lib/<provider>/` |
| Webhook or third-party callback | `src/app/api/.../route.ts`, calling feature code |

## Reads and writes

Keep them apart. Reads go in `queries/` with `import "server-only"`. Writes go in
`actions/` with `"use server"`. The reason: every exported function in a `"use server"`
file becomes a public endpoint that anyone can call, so a read placed there is exposed
for no benefit, and every action must validate its own input and check authorization.
Templates and the checklist: `references/queries-and-actions.md`.

## Workflow: adding a feature or extending one

1. Find the closest existing feature and mirror its shape.
2. Create the feature folder with only the parts you need.
3. Write `schema.ts` and `types.ts` first. They define what moves through the feature.
4. Write `queries/` and `actions/`. They are the only code that talks to `lib` data clients.
5. Write the components. Server components by default; add `"use client"` only for
   state, effects, event handlers or browser APIs, and keep that boundary on the
   smallest component that needs it.
6. Add the route in `src/app`: await params, call a query, handle not-found, render
   the feature component.
7. Run the project's lint, type check and build. Fix what you touched.

## Guardrails

- **No logic in `page.tsx`.** Routes are wiring. Logic buried in a route cannot be
  reused or tested.
- **No data client in components or pages.** Import it only in `queries/` and `actions/`.
- **No feature importing another feature's internals.** If two features need the same
  piece, move it to `shared`. The one exception is a composing feature (profile,
  dashboard) that aggregates other features' public components.
- **Do not promote to `shared` early.** Start inside the feature, and move it when a
  second feature needs it.
- **No type-based folders at the `src` root** (`components/`, `hooks/`, `utils/`).
  They turn into dumping grounds. Those belong inside a feature or in `shared`.
- **No barrel files (`index.ts`) inside features.** Import from the file directly. Barrels
  hurt bundling and create circular imports.
- **Match existing naming.** Files in kebab-case, the `@/` alias for `src`, and the
  export style the project already uses.

## Reference files

- `references/feature-anatomy.md`: read when creating a feature or deciding whether to
  split one. Covers each part, scaling rules, naming, composing features.
- `references/queries-and-actions.md`: read when writing any data read or mutation.
  Templates, the action checklist, route handlers, cache invalidation.
- `references/lib-and-shared.md`: read when touching `src/lib` or `src/shared`, adding a
  data provider, or moving code between layers.
