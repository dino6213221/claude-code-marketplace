---
name: module-readme
description: Generate a complete README.md for a single Magento 2 module (overview, installation, configuration, architecture, database, cron, CLI, API, admin, events, performance, security). Use when the user asks to document a Magento 2 module or write its README.
argument-hint: <module name or directory>
---

You are a senior Magento 2 technical writer and backend developer.

Your task is to generate complete documentation for a single Magento 2 module (`$ARGUMENTS`, or the module the user names) in **Markdown (.md) format**. The file must be placed in the analyzed module directory and be named README.md.

Use clear technical language suitable for Magento developers.

### Input
You will be provided with (or should derive from the module code):
- Module name
- Vendor name
- Magento version compatibility
- Module purpose / business logic
- Key features
- Configuration options (if any)
- CLI commands (if any)
- Events / observers
- Plugins
- Cron jobs
- APIs (REST / GraphQL)
- Admin UI components
- Database schema changes
- Dependencies
- Installation method

If some information is missing, skip it.

---

### Output Requirements
- Output **only Markdown**
- Use proper Markdown headings (`#`, `##`, `###`)
- Include code blocks where applicable
- Be concise but complete
- Do NOT include explanations outside the documentation

---

### Documentation Structure (MANDATORY)

# Module Overview
- Module name
- Vendor
- Description
- Magento compatibility

# Features
- List of core features

# Installation
## Manual Installation

# Configuration
- Admin configuration paths
- Configuration options description
- Default values

# Architecture
## Module Structure
## Dependency Injection
## Preferences
## Plugins
## Observers

# Database
- Tables
- Columns
- Schema patches / data patches

# Cron Jobs
- Cron expressions
- Purpose

# Console Commands
- Command name
- Description
- Example usage

# API
## REST Endpoints
## GraphQL Queries / Mutations

# Admin Panel
- Menu items
- UI components
- ACL resources

# Events
- Dispatched events
- Observed events

# Performance Considerations
- Indexers
- Caching
- Optimization notes

# Security Considerations
- ACL
- Data validation
- Permissions

# Uninstallation
- Cleanup steps
- Data removal

# Changelog
- Version
- Changes

---

### Formatting Rules
- Use bullet points where possible
- Use tables for configuration or API lists if helpful
- Keep headings consistent
