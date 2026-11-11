# Feature anatomy

Contents: [Principles](#principles) · [Full layout](#full-layout) · [What each part is for](#what-each-part-is-for) · [Scaling rules](#scaling-rules) · [Naming](#naming) · [Composing features](#composing-features) · [Worked example](#worked-example)

## Principles

- A feature owns one domain noun or capability: `products`, `cart`, `orders`, `auth`.
- Everything a developer needs to change that capability sits in one folder.
- Structure grows only when needed. A new feature starts as two or three files.
- Routes never contain feature logic. They call into the feature.

## Full layout

This is the maximum. Most features use a small part of it.

```
src/features/<name>/
├── queries/
│   └── <entity>.ts        server-only reads
├── actions/
│   └── <entity>.ts        "use server" mutations
├── hooks/
│   └── use-<thing>.ts     client hooks
├── components/            only once the root gets crowded
├── context/               only for state scoped to this feature's subtree
├── schema.ts              zod schemas
├── types.ts               domain types
├── store.ts               client store (zustand or similar)
└── <component>.tsx        components, flat at the root while few
```

## What each part is for

**`queries/`** reads data on the server and returns plain, serializable objects typed
with this feature's `types.ts`. They use `import "server-only"` and never mutate.

**`actions/`** mutations. Each exported function validates its input, checks who is
calling, writes, and invalidates affected caches. See `queries-and-actions.md`.

**`hooks/`** client-side behavior that belongs to the feature, such as a form hook that
wires `react-hook-form` to a schema and an action, or a multi-step flow.

**`schema.ts`** the validation schemas for forms and action input. Keeping them in the
feature lets the form and the server action share one definition.

**`types.ts`** domain types the feature owns. Types generated from the database belong
in `lib`, and the feature's types can derive from them.

**`store.ts`** client state the feature owns (cart items, filters). State that many
features read, such as the session, belongs in `shared` or a root-level store.

**Components** server components by default. Add `"use client"` only to the components
that need it, and keep them small so most of the tree stays on the server.

**`context/`** use only for a provider scoped to the feature. An app-wide provider
(session, theme) belongs in `shared`, even when one feature produces its data.

## Scaling rules

| Signal | Action |
|---|---|
| More than about 8 component files at the root | Move them into `components/` |
| One file holds queries for several unrelated entities | Split into `queries/<entity>.ts` |
| Two unrelated nouns live in one feature | Split into two features |
| A second feature needs one of your components | Move it to `shared/components/` |
| A component is only used inside one other component | Keep it next to that component |

Split a feature when its parts change for different reasons, not because the folder
looks big.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Files and folders | kebab-case | `product-details.tsx`, `use-review-form.ts` |
| Component | PascalCase, one main component per file | `ProductDetails` |
| Query / action | verb first, named export | `getProducts`, `createOrder` |
| Hook | `use` prefix, file `use-*.ts` | `useReviewForm` |
| Schema | `<thing>Schema` | `reviewSchema` |
| Types | PascalCase, no `I` prefix | `Product`, `OrderStatus` |
| Imports | `@/` alias for `src`, no long relative paths | `@/features/products/types` |

If the project already has a naming style (for example `fetch*` for reads or default
exports for components), keep it. Consistency within a project beats this table.

## Composing features

Some pages aggregate several domains, like a profile page showing addresses, orders and
reviews. Two options:

1. **Compose in the route.** The page imports components from each feature. This keeps
   features independent.
2. **A composing feature** (`profile`) whose components import only the *public
   components* of other features. This is the only allowed cross-feature import.

Never import another feature's `queries/`, `actions/`, `hooks/` or `store.ts` directly.
If that seems necessary, the shared piece probably belongs in `shared` or `lib`.

## Worked example

A `products` feature with a list and a detail page:

```
src/features/products/
├── queries/products.ts       getProducts(), getProductById(id)
├── schema.ts                 productFilterSchema
├── types.ts                  Product, ProductCategory
├── product-card.tsx
├── product-details.tsx       "use client" (add-to-cart button)
└── home-products.tsx

src/app/(pages)/product/[id]/page.tsx   await params → getProductById → <ProductDetails />
src/app/page.tsx                         getProducts → <HomeProducts />
```

Notice that nothing here imports the database client directly. `queries/products.ts` is
the single place that does.
