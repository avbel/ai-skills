---
name: design-patterns-ts
description: GoF design patterns with idiomatic TypeScript — creational (Factory, Builder, Singleton), structural (Adapter, Decorator, Proxy, Composite), behavioral (Strategy, Observer, Command, State, Chain of Responsibility, Iterator, Visitor). Use when implementing or refactoring code that involves design patterns in TypeScript.
---

# Design Patterns in TypeScript

Apply these patterns when designing or refactoring TypeScript code.

## PATTERN CATALOGS

Full per-pattern catalogs (intent, TypeScript code example, use-when notes) live in `references/`. Read the file for the category you need:

- **Creational** (Factory Method, Abstract Factory, Builder, Singleton, Prototype) — see [references/creational.md](references/creational.md)
- **Structural** (Adapter, Decorator, Facade, Proxy, Composite, Bridge, Flyweight) — see [references/structural.md](references/structural.md)
- **Behavioral** (Strategy, Observer, Command, State, Chain of Responsibility, Iterator, Template Method, Mediator, Memento, Visitor) — see [references/behavioral.md](references/behavioral.md)

## CHOOSING THE IDIOMATIC FORM

Before reaching for a class-heavy GoF implementation, prefer the simplest TypeScript construct that expresses the pattern:

- **Singleton:** Module-level `const`/`let` over class-based singletons. ES modules are evaluated once.
- **Strategy:** Function types for single-method strategies; interfaces when strategies have multiple methods or internal state.
- **Command:** Closures over command classes when there is no shared state to encapsulate.
- **Iterator:** `Symbol.iterator` / `Symbol.asyncIterator` with generators — get `for...of` / `for await...of` for free.
- **Chain of Responsibility:** Middleware-style functions (`(req, next) => void`) over linked handler classes.

## IDIOMATIC TS ALTERNATIVES

| Pattern | Simpler TS Idiom |
|---|---|
| Strategy | Function types: `type Strategy = (data: T[]) => T[]` |
| Command | Closures: `{ execute: () => void, undo: () => void }` |
| Observer | `EventEmitter`, RxJS `Subject`, `EventTarget` |
| Iterator | `Symbol.iterator` / `Symbol.asyncIterator` + generators |
| Singleton | Module-scoped `const` (modules evaluate once) |
| Factory Method | Generic factory: `<T>(Ctor: new () => T) => T` |
| Proxy | Native `Proxy` + `ProxyHandler<T>` |
| Decorator | TS experimental decorators (`@decorator`) or wrapping |
| Builder | Method chaining with `return this` |

## QUICK REFERENCE

| Pattern | Category | One-Line Intent |
|---|---|---|
| Factory Method | Creational | Defer instantiation to subclasses/functions |
| Abstract Factory | Creational | Create families of related objects |
| Builder | Creational | Construct complex objects step by step |
| Prototype | Creational | Clone existing objects |
| Singleton | Creational | Single instance with global access |
| Adapter | Structural | Make incompatible interfaces work together |
| Bridge | Structural | Separate abstraction from implementation |
| Composite | Structural | Compose objects into trees |
| Decorator | Structural | Add behavior via wrapping (stackable) |
| Facade | Structural | Simplified interface to complex subsystem |
| Flyweight | Structural | Share state to reduce memory |
| Proxy | Structural | Placeholder controlling access |
| Chain of Resp. | Behavioral | Pass request along handler chain |
| Command | Behavioral | Encapsulate request as object |
| Iterator | Behavioral | Sequential access without exposing internals |
| Mediator | Behavioral | Centralize complex communications |
| Memento | Behavioral | Save and restore object state |
| Observer | Behavioral | Notify dependents of state changes |
| State | Behavioral | Alter behavior when state changes |
| Strategy | Behavioral | Swap algorithms at runtime |
| Template Method | Behavioral | Algorithm skeleton with overridable steps |
| Visitor | Behavioral | Add operations without modifying objects |
