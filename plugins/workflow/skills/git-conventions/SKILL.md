---
name: git-conventions
description: Apply branch naming, commit message and pull request description conventions tied to Jira ticket keys. Use when creating a branch, writing a commit message, or opening or describing a pull request.
---

# Git Conventions & Rules

Strict rules for branch naming, commit message and pull request description formatting. All AI assistants and developers must adhere to these standards without exception.

---

## 1. Branch Naming Convention

All branch names MUST strictly follow this structure and order:

`<type>/<JIRA_TICKET>-<short-description>`

### Components

1. **Type:** MUST be either `feature` or `bugfix`.
2. **Jira Ticket ID:** MUST be the exact issue key (e.g., `PROJ-1234`).
3. **Short Description:** MUST be written in kebab-case, lowercase, and contain **a maximum of 5 words** (e.g., `product-stock-status`).

### Valid Examples

- `feature/PROJ-1234-product-stock-status`
- `bugfix/PROJ-1092-fix-checkout-cart-loader`

### Invalid Examples

- `PROJ-1234-product-stock-status` *(Missing type prefix)*
- `feature/product-stock-status` *(Missing Jira ticket)*
- `feature/PROJ-1234-product-stock-status-for-all-store-views` *(Description exceeds 5 words)*

---

## 2. Commit Message Standard

Commit messages MUST contain **ONLY** the following two elements in exact order:

1. **Jira Task Number** (e.g., `PROJ-1234`)
2. **Description of Changes** (maximum **2 sentences**)

Nothing else is permitted in the commit message.

### Format

`<JIRA_TICKET> <Description sentence 1>. <Optional description sentence 2>.`

### Valid Examples

- `PROJ-1234 Updated stock calculation logic for configurable products.`
- `PROJ-1234 Fixed inventory balance check during checkout. Added unit test for multi-stock items.`

### Strict Rules & Prohibitions

- **NO Conventional Commit prefixes** (e.g., `feat:`, `fix:`, `refactor:`).
- **NO Emojis** (e.g., `:sparkles:`, `🐛`).
- **NO Extra lines, footers, or co-author signatures.**
- **NO Long descriptions exceeding 2 sentences.**

---

## 3. Pull Request Description Standard

Pull request descriptions MUST contain **ONLY** a short description of the changes (maximum **2 sentences**).

Nothing else is permitted in the PR description.

### Valid Examples

- `Updated stock calculation logic for configurable products.`
- `Fixed inventory balance check during checkout. Added unit test for multi-stock items.`

### Strict Rules & Prohibitions

- **NO Headings or sections** (e.g., `## Summary`, `## Test plan`).
- **NO Bullet lists, checklists, or test plans.**
- **NO Emojis, footers, or generated-by / co-author signatures.**
- **NO Long descriptions exceeding 2 sentences.**

### Exception

PRs touching auth, secrets, encryption, logging/audit, backups, or access control MUST additionally include a `Security impact` section.
