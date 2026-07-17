# Creational Patterns

## Factory Method

**Intent:** Defer instantiation to subclasses / factory functions.

```typescript
interface Transport { deliver(): void }
class Truck implements Transport { deliver() { /* deliver by road */ } }
class Ship implements Transport { deliver() { /* deliver by sea */ } }

// Factory function (idiomatic TS — often no need for abstract class)
function createTransport(mode: 'land' | 'sea'): Transport {
  return mode === 'land' ? new Truck() : new Ship();
}

// Generic factory
function create<T>(Ctor: new () => T): T { return new Ctor(); }
```

**Use when:** Concrete type depends on runtime conditions; extending a library's internal components.

## Abstract Factory

**Intent:** Create families of related objects without specifying concrete classes.

```typescript
interface UIFactory {
  createButton(): Button;
  createCheckbox(): Checkbox;
}

class MaterialFactory implements UIFactory {
  createButton() { return new MaterialButton(); }
  createCheckbox() { return new MaterialCheckbox(); }
}

// Client depends only on UIFactory — swap families at runtime
function renderUI(factory: UIFactory) {
  const btn = factory.createButton();
  const cb = factory.createCheckbox();
}
```

**Use when:** Cross-platform UI kits, theming systems, database abstraction layers.

## Builder

**Intent:** Construct complex objects step-by-step with fluent API.

```typescript
class QueryBuilder {
  private table = '';
  private conditions: string[] = [];
  private cols: string[] = ['*'];

  from(table: string) { this.table = table; return this; }
  select(...cols: string[]) { this.cols = cols; return this; }
  where(cond: string) { this.conditions.push(cond); return this; }

  build(): string {
    let q = `SELECT ${this.cols.join(', ')} FROM ${this.table}`;
    if (this.conditions.length) q += ` WHERE ${this.conditions.join(' AND ')}`;
    return q;
  }
}

const query = new QueryBuilder().from('users').select('name', 'email').where('active = true').build();
```

**Use when:** Objects with many optional params; different representations of same construction process.

## Singleton

**Intent:** Ensure single instance with global access.

```typescript
// Idiomatic TS: module-scoped const IS a singleton
// file: config.ts
export const config = Object.freeze({ dbUrl: process.env.DB_URL, port: 3000 });

// Class-based (when lazy init or complex setup needed)
class Database {
  static #instance: Database;
  private constructor() {}
  static get instance(): Database {
    return (Database.#instance ??= new Database());
  }
}
```

**Prefer:** Module-level `const`/`let` over class-based singletons. ES modules are evaluated once.

## Prototype

**Intent:** Clone existing objects without depending on their classes.

```typescript
interface Cloneable<T> { clone(): T }

class Settings implements Cloneable<Settings> {
  constructor(public theme: string, public fontSize: number, public plugins: string[]) {}
  clone(): Settings {
    return new Settings(this.theme, this.fontSize, [...this.plugins]);
  }
}
```

**Use when:** Creating variations of configured objects; avoiding costly re-initialization.
