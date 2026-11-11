# Feature Anatomy

Detailed conventions for organizing, scaling and composing features in a
feature-based Next.js application.

Contents:

- [Principles](#principles)
- [Feature Structure](#feature-structure)
- [Responsibilities](#responsibilities)
- [Scaling Rules](#scaling-rules)
- [Naming Conventions](#naming-conventions)
- [Feature Composition](#feature-composition)
- [Worked Example](#worked-example)

## Principles

- A feature owns one business domain or capability: `products`, `cart`,
  `orders`, `auth`.
- Everything required to implement that capability should live together.
- Structure grows only when necessary.
- A feature starts with a small number of files, not a predefined directory tree.
- Routes connect URLs to features and should not contain domain logic.
- Features should remain independent from unrelated features.
- Shared code should emerge from real reuse rather than anticipated reuse.

## Feature Structure

A feature can grow into the following structure:

```text
src/features/<name>/
├── queries/
│   └── <entity>.ts
├── actions/
│   └── <entity>.ts
├── hooks/
│   └── use-<thing>.ts
├── components/
├── context/
├── schema.ts
├── types.ts
├── store.ts
└── <component>.tsx
```

This represents the available organizational options, not a required template.

A simple feature might contain only:

```text
src/features/products/
├── queries.ts
├── product-list.tsx
└── types.ts
```

Introduce subfolders when the number of files or responsibilities makes
the feature easier to navigate.

## Responsibilities

### queries/

Server-side data retrieval.

- Keep reads separate from mutations.
- Use `import "server-only"` when appropriate.
- Return typed and serializable data.
- Keep database and external data access out of components.
- Group queries by entity when a feature has multiple unrelated data sources.

Example:

```ts
import "server-only";

export async function getProducts() {
  // Retrieve products from the configured data provider.
}
```

### actions/

Server-side mutations.

- Use `"use server"`.
- Validate all input on the server.
- Verify authentication and authorization.
- Handle errors explicitly.
- Invalidate affected caches when necessary.
- Keep each action focused on one operation.

Example:

```ts
"use server";

export async function createProduct(input: unknown) {
  // Validate input.
  // Verify authorization.
  // Perform the mutation.
  // Invalidate affected caches.
}
```

### hooks/

Client-side behavior owned by the feature.

Examples:

- Form state and submission.
- Multi-step flows.
- Feature-specific interactions.
- Client-side synchronization with server actions.

Avoid creating hooks that simply wrap one line of code without adding
meaningful behavior or reuse.

### components/

Feature-specific UI.

- Components belong to the feature that owns their business meaning.
- Prefer Server Components.
- Add `"use client"` only when browser APIs, state, effects or event handlers
  are required.
- Keep client boundaries small.
- Move components into this folder when the feature root becomes difficult
  to navigate.

### context/

Providers and context scoped to a feature subtree.

Use this for state or dependencies that need to be shared across a specific
part of a feature.

Application-wide providers, such as session or theme providers, belong in
`shared`.

### schema.ts

Validation schemas owned by the feature.

Use schemas when validation is required, especially when the same definition
must be shared between forms and server actions.

Keep server-side validation authoritative, even when client-side validation
uses the same schema.

### types.ts

Domain types owned by the feature.

- Use clear domain-oriented names.
- Avoid unnecessary duplication of generated database types.
- Derive feature types from infrastructure types when appropriate.
- Keep generated database types inside `lib`.

### store.ts

Client-side state owned by the feature.

Examples:

- Shopping cart state.
- Feature filters.
- Temporary UI state shared across feature components.

Do not introduce a store when local component state, URL state or server
state already solves the problem.

Application-wide state belongs in the existing shared state/provider
conventions of the project.

## Scaling Rules

| Signal                                            | Recommended action                   |
| ------------------------------------------------- | ------------------------------------ |
| A feature has only a few files                    | Keep them flat at the root           |
| The feature root becomes difficult to navigate    | Introduce `components/`              |
| Queries cover unrelated entities                  | Split them into focused query files  |
| Actions cover unrelated operations                | Split them into focused action files |
| Two unrelated business domains share one feature  | Consider splitting the feature       |
| Multiple features need the same UI building block | Move it to `shared/components/`      |
| A component is used only by one other component   | Keep it close to its consumer        |
| A provider is only needed in one feature subtree  | Keep it in `context/`                |

Do not split a feature simply because it has many files.

Split when its responsibilities, domain boundaries or change patterns
justify the separation.

## Naming Conventions

Follow the existing project conventions first.

| Element           | Convention                  | Example                     |
| ----------------- | --------------------------- | --------------------------- |
| Files and folders | kebab-case                  | `product-details.tsx`       |
| Components        | PascalCase                  | `ProductDetails`            |
| Queries           | Verb-first named exports    | `getProducts`               |
| Actions           | Verb-first named exports    | `createOrder`               |
| Hooks             | `use` prefix                | `use-review-form.ts`        |
| Schemas           | Descriptive name + `Schema` | `reviewSchema`              |
| Types             | PascalCase, no `I` prefix   | `Product`, `OrderStatus`    |
| Imports           | Configured project alias    | `@/features/products/types` |

Avoid introducing naming inconsistencies within an existing feature.

## Feature Composition

Some pages aggregate multiple business domains.

For example, a profile page might display addresses, orders and reviews.

There are two reasonable approaches.

### 1. Compose at the Route Level

The route imports public components from the required features.

```tsx
import { AddressList } from "@/features/addresses/address-list";
import { OrderList } from "@/features/orders/order-list";
import { ReviewList } from "@/features/reviews/review-list";

export default function ProfilePage() {
  return (
    <>
      <AddressList />
      <OrderList />
      <ReviewList />
    </>
  );
}
```

This is appropriate when the composition is specific to one route.

### 2. Create a Composing Feature

A dedicated feature can aggregate other feature components when the
composition represents a reusable business capability.

For example:

```text
src/features/profile/
├── profile-overview.tsx
└── profile-summary.tsx
```

The composing feature may import public components from other features.

It must not access their internal:

- `queries/`
- `actions/`
- `hooks/`
- `store.ts`
- Private implementation details.

If multiple features need the same building block, consider whether it belongs
in `shared` instead.

## Worked Example

A products feature with listing and detail pages:

```text
src/features/products/
├── queries/
│   └── products.ts
├── schema.ts
├── types.ts
├── product-card.tsx
├── product-details.tsx
└── home-products.tsx

src/app/
├── page.tsx
└── (pages)/
    └── product/
        └── [id]/
            └── page.tsx
```

The query module owns data retrieval:

```ts
// src/features/products/queries/products.ts

import "server-only";

export async function getProducts() {
  // Retrieve products.
}

export async function getProductById(id: string) {
  // Retrieve one product.
}
```

The listing route connects the page to the feature:

```tsx
// src/app/page.tsx

import { getProducts } from "@/features/products/queries/products";
import { HomeProducts } from "@/features/products/home-products";

export default async function HomePage() {
  const products = await getProducts();

  return <HomeProducts products={products} />;
}
```

The detail route handles the URL and retrieves the corresponding product:

```tsx
// src/app/(pages)/product/[id]/page.tsx

import { notFound } from "next/navigation";
import { getProductById } from "@/features/products/queries/products";
import { ProductDetails } from "@/features/products/product-details";

type PageProps = {
  params: Promise<{ id: string }>;
};

export default async function ProductPage({ params }: PageProps) {
  const { id } = await params;
  const product = await getProductById(id);

  if (!product) {
    notFound();
  }

  return <ProductDetails product={product} />;
}
```

The example illustrates separation of responsibilities. Adapt parameter
types, data fetching, error handling and component boundaries to the installed
Next.js version and the project's existing conventions.
