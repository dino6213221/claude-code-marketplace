---
name: coding-rules
description: Apply Magento 2 / Adobe Commerce coding rules (SOLID, dependency injection, plugins, observers, service contracts, output escaping, FPC, performance). Use when generating, modifying or reviewing Magento 2 PHP classes, di.xml, db_schema.xml, layout XML or .phtml templates.
---

# Magento 2 Coding Rules

When generating, modifying, or reviewing code in a Magento 2 codebase, strictly adhere to the following architectural, design, and formatting rules, which align with the official Adobe Commerce Technical Guidelines.

## 1. Software Design Principles

* **SOLID Principles:**
    * **SRP:** Keep classes small and focused. Avoid "God classes" with excessive constructor dependencies.
    * **OCP:** Never modify core files. Extend via Plugins, Events/Observers, or `di.xml`.
    * **LSP:** Custom preferences must honor the parent class/interface contract (signatures, return types).
    * **ISP:** Design focused, granular Service Contracts in `Api/` and `Api/Data/`.
    * **DIP:** Type-hint interfaces in constructors (e.g., `ProductRepositoryInterface`), NEVER concrete implementations.

* **Composition over Inheritance:** Always favor object composition over class inheritance. Reduce deep class hierarchies and use injected dependencies to share functionality.

* **KISS, DRY & YAGNI:** Utilize native Magento features (UI Components, ViewModels) before writing custom logic. Do not duplicate code. Implement only what is explicitly requested.

## 2. Dependency Injection (DI) & Object Creation

* **ALWAYS use Constructor Injection:** Inject dependencies via `__construct()`.

* **NEVER use `ObjectManager` directly:** Do not use `\Magento\Framework\App\ObjectManager::getInstance()`.
    * *Exception:* Allowed ONLY in Factory classes, fallback constructors for backward compatibility, or test scripts.

* **Factories & Proxies:**
    * Use Factories (e.g., `OrderInterfaceFactory`) to instantiate new entities or non-injectable objects.
    * Use Proxies in `di.xml` for heavy, optional dependencies to prevent unnecessary object graph instantiation.

* **Virtual Types:** Prefer `<virtualType>` in `di.xml` to customize constructor arguments instead of creating empty PHP subclasses.

## 3. Extension Points (Plugins, Events, Preferences)

* **Statelessness:** Plugins (Interceptors) and Event Observers are instantiated as singletons by the ObjectManager. They **MUST** be entirely stateless. Do not store mutable data in class properties.

* **Plugin Execution Rules:**
    * Use `before` to change arguments.
    * Use `after` to change the result.
    * **AVOID `around` plugins** unless absolutely necessary (e.g., short-circuiting execution), as they degrade performance and break the plugin chain.
    * **NEVER** write plugins for Data Objects (DTOs located in `Api/Data/`).

* **Events vs. Plugins:**
    * Use **Events/Observers** for side effects (logging, sending emails, webhooks).
    * Use **Plugins** to alter data in-flight or change method outputs.

## 4. Module Boundaries & Service Contracts

* **Cross-Module Communication:** Modules must interact with other modules **strictly** through Service Contracts (`Api/` interfaces). Never directly instantiate or inject a class from another module's `Model/` or `ResourceModel/` directory.

* **Data Interfaces (DTOs):** Classes implementing `Api/Data/` interfaces must only contain getters and setters. They must contain zero business logic.

* **Separation of Concerns:**
    * Models (`Model/`) handle logic. No SQL here.
    * ResourceModels handle database operations (INSERT/UPDATE/DELETE).
    * Collections handle multi-record filtering.

* **Database Schema:** ALWAYS use `etc/db_schema.xml` (Declarative Schema) for database modifications. Do not use legacy Install/Upgrade scripts.

## 5. Code Demarcation Standard

* **Strict Separation of Languages:**
    * **No HTML in PHP:** Never echo or construct HTML strings inside PHP classes or controllers.
    * **No PHP in JavaScript:** Pass dynamic data from PHP to JS via UI Components, `json` encoded data attributes (`data-mage-init`), or global configuration objects.
    * **No SQL in Models:** Raw SQL must be kept entirely within ResourceModels or Adapters. Use standard Select objects and parameter binding.

## 6. View Layer & Frontend

* **ViewModels:** PREFER ViewModels (`Magento\Framework\View\Element\Block\ArgumentInterface`) injected via XML over creating custom Block classes.

* **Output Escaping:** ALWAYS escape data in `.phtml` templates:
    * `$escaper->escapeHtml($data)` for standard text.
    * `$escaper->escapeHtmlAttr($data)` for HTML attributes.
    * `$escaper->escapeUrl($data)` for URLs.

* **FPC Safety:** NEVER use `cacheable="false"` in layout XML unless the page is inherently uncacheable (like cart or checkout). Adding it globally disables Full Page Cache for that route.

## 7. Coding Standards & Performance

* **PSR Compliance:** Follow PSR-12 for formatting and PSR-4 for autoloading/namespaces.

* **Type Hinting:** Use strict typing (`declare(strict_types=1);`), scalar type hints, and return type declarations wherever possible.

* **N+1 Queries:** NEVER execute database queries, model loads, or API calls inside a loop. Use Collections or Repositories to fetch data in bulk.

* **Security:** Ensure all POST forms include CSRF form keys. Encrypt all sensitive data saved to the database.
