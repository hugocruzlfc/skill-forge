---
name: nextjs-feature-architecture
description: "Architecture guide for Next.js App Router projects organized by features: thin routes in src/app, code grouped by domain in src/features/<name>, plus shared and lib layers. Use whenever the user adds or changes a page, route, feature, server action, query, form, hook, store or validation schema in a Next.js project, asks where some code should live, or wants to scaffold or refactor toward a feature-based structure, even if they never say 'architecture' or 'features'. Backend-agnostic: Supabase, Prisma, Drizzle or any other data layer lives in lib."
---

# Next.js Feature Architecture

Organize code around business domains and capabilities rather than technical
file types. A feature such as products, cart or authentication owns the code
required to implement that capability.

Routes connect URLs to features. Shared code contains reusable application
building blocks, while lib contains infrastructure and external integrations.

This skill focuses on **architecture, code organization and file placement**.
It does not replace official Next.js or React documentation.

## Before You Change Anything

1. **Inspect the existing project first.** Check whether `src/features/` exists,
   identify existing features and inspect a similar implementation from route
   to data access.
2. **Respect existing conventions.** The project's established architecture,
   naming and implementation patterns take precedence over this guide.
3. **Do not restructure automatically.** If the project does not use feature-based
   architecture, follow its existing organization. Only propose migration when
   it provides a clear benefit or the user requests it.
4. **Check the installed Next.js version.** APIs involving caching, `params`,
   route handlers and cache invalidation change between versions. Inspect
   `package.json` and consult documentation matching the installed version.
5. **Use specialist skills when available.** Defer to dedicated skills for
   Next.js APIs, caching, React performance, database practices and other
   specialized topics.

## Architecture Layers

| Layer    | Path                   | Responsibility                                                                       |
| -------- | ---------------------- | ------------------------------------------------------------------------------------ |
| Routes   | `src/app/`             | URL structure, layouts, loading, error boundaries and route handlers                 |
| Features | `src/features/<name>/` | Domain-specific components, queries, actions, hooks, schemas and state               |
| Shared   | `src/shared/`          | Reusable UI, hooks, providers, types and application-wide building blocks            |
| Lib      | `src/lib/`             | Infrastructure, database clients, authentication clients, SDKs and generic utilities |
| Assets   | `src/assets/`          | Application images, icons, fonts and static resources                                |

### Dependency Direction

Prefer the following dependency direction:

`app → features → shared → lib`

- Routes can compose feature components and shared UI.
- Features can use shared building blocks and infrastructure from lib.
- Shared code can depend on lib but must not depend on individual features.
- Lib must remain independent of application-specific features and UI.

Avoid upward dependencies and circular imports.

A composing feature may use the public components of other features when
aggregating multiple domains. It must not access their internal queries,
actions, hooks or stores.

### Backend Independence

The architecture must not depend on a specific backend or ORM.

Supabase, Prisma, Drizzle, Firebase, REST clients and other infrastructure
integrations belong in `src/lib/`.

Features access these integrations through their own queries and actions
rather than importing database clients directly into components or routes.

## Feature Anatomy

A feature starts small and grows only when necessary.

```text
src/features/<name>/
├── queries/        Server-side reads
├── actions/        Server-side mutations
├── hooks/          Feature-specific client hooks
├── components/     Feature components (when needed)
├── context/        Feature-scoped providers (when needed)
├── schema.ts       Validation schemas (when needed)
├── types.ts        Domain types (when needed)
├── store.ts        Feature-specific client state (when needed)
└── *.tsx           Components, initially flat at the root
```

Create only the files and folders required by the feature.

Do not create empty folders or placeholder files for hypothetical future needs.

For detailed conventions, scaling rules and examples, read
[feature-anatomy.md](./feature-anatomy.md).

## Where Does It Go?

| Requirement                   | Location                                |
| ----------------------------- | --------------------------------------- |
| Page or URL                   | `src/app/.../page.tsx`                  |
| Layout or loading boundary    | `src/app/.../layout.tsx`, `loading.tsx` |
| Route handler or webhook      | `src/app/api/.../route.ts`              |
| Server-side data read         | `src/features/<name>/queries/`          |
| Data mutation                 | `src/features/<name>/actions/`          |
| Input validation              | `src/features/<name>/schema.ts`         |
| Feature-specific form or flow | `src/features/<name>/hooks/`            |
| Feature-specific client state | `src/features/<name>/store.ts`          |
| Feature-specific provider     | `src/features/<name>/context/`          |
| Feature-specific component    | `src/features/<name>/`                  |
| Reusable component            | `src/shared/components/`                |
| Reusable hook                 | `src/shared/hooks/`                     |
| Application-wide provider     | `src/shared/`                           |
| Application-wide state        | `src/shared/`                           |
| Database or ORM client        | `src/lib/`                              |
| Authentication integration    | `src/lib/`                              |
| Third-party SDK               | `src/lib/`                              |
| Environment validation        | `src/lib/`                              |
| Generated database types      | `src/lib/<provider>/`                   |

The table is a placement guide, not a reason to introduce folders that do not
already exist or are not needed.

## Reads and Writes

Keep data reads and mutations separate.

### Queries

- Live in `features/<name>/queries/`.
- Use `import "server-only"` when appropriate to prevent accidental client imports.
- Handle server-side data retrieval.
- Return typed, serializable data suitable for consumption by components.
- Do not mutate application state or perform writes.

### Server Actions

- Live in `features/<name>/actions/`.
- Use the `"use server"` directive.
- Validate input on the server.
- Check authentication and authorization on every operation.
- Handle expected errors explicitly.
- Invalidate affected caches when necessary.

Remember that exported functions from a `"use server"` module can be invoked
as server actions by clients. Treat them as externally callable entry points.

Never assume that client-side validation or hidden UI controls provide security.

## Workflow: Adding or Extending a Feature

1. Inspect the existing architecture and find the closest feature to follow.
2. Determine whether the change belongs to an existing feature or a new one.
3. Create only the necessary files and folders.
4. Define or update domain types and validation schemas when the feature requires them.
5. Implement server-side queries and actions when data access or mutations are needed.
6. Implement components and hooks following the existing client/server boundaries.
7. Connect the feature through the appropriate route in `src/app/`.
8. Verify the implementation using the project's existing lint, type-check and build commands.

### Server and Client Components

- Prefer Server Components by default.
- Introduce `"use client"` only when client-side interactivity is required.
- Keep client boundaries as close as possible to the components that need them.
- Avoid moving entire component trees to the client unnecessarily.
- Do not introduce client state when server rendering or URL state is sufficient.

## Guardrails

- **Keep routes thin.** Pages should connect route parameters, data and feature components rather than contain domain logic.
- **Keep data clients out of components.** Components and pages should not import database or infrastructure clients directly.
- **Respect feature boundaries.** A feature must not import another feature's internal implementation.
- **Expose reusable building blocks deliberately.** Move code into shared only when multiple consumers genuinely need it.
- **Avoid premature abstraction.** Start inside the feature and extract shared code when reuse becomes real.
- **Avoid type-based root folders.** Do not introduce global `components/`, `hooks/` or `utils/` folders that become dumping grounds.
- **Avoid unnecessary barrel files.** Prefer direct imports and follow the project's established conventions.
- **Follow existing naming conventions.** Use kebab-case for files and folders unless the project already follows another style.
- **Respect the existing import alias.** Use `@/` for `src` only when configured in the project.
- **Do not introduce dependencies without a reason.** Reuse the existing stack and conventions whenever possible.

## Reference

- [feature-anatomy.md](./feature-anatomy.md): detailed feature structure,
  responsibilities, scaling rules, naming and composition examples.
