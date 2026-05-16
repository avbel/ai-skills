---
name: design-patterns-ts
description: GoF design patterns with idiomatic TypeScript — creational (Factory, Builder, Singleton), structural (Adapter, Decorator, Proxy, Composite), behavioral (Strategy, Observer, Command, State, Chain of Responsibility, Iterator, Visitor). Use when implementing or refactoring code that involves design patterns in TypeScript.
---

Apply these patterns when designing or refactoring TypeScript code.

## CREATIONAL PATTERNS

### Factory Method

**Intent:** Defer instantiation to subclasses / factory functions.

```typescript
interface Transport { deliver(): void }
class Truck implements Transport { deliver() { console.log('By road') } }
class Ship implements Transport { deliver() { console.log('By sea') } }

// Factory function (idiomatic TS — often no need for abstract class)
function createTransport(mode: 'land' | 'sea'): Transport {
  return mode === 'land' ? new Truck() : new Ship()
}

// Generic factory
function create<T>(Ctor: new () => T): T { return new Ctor() }
```

**Use when:** Concrete type depends on runtime conditions; extending a library's internal components.

### Abstract Factory

**Intent:** Create families of related objects without specifying concrete classes.

```typescript
interface UIFactory {
  createButton(): Button
  createCheckbox(): Checkbox
}

class MaterialFactory implements UIFactory {
  createButton() { return new MaterialButton() }
  createCheckbox() { return new MaterialCheckbox() }
}

// Client depends only on UIFactory — swap families at runtime
function renderUI(factory: UIFactory) {
  const btn = factory.createButton()
  const cb = factory.createCheckbox()
}
```

**Use when:** Cross-platform UI kits, theming systems, database abstraction layers.

### Builder

**Intent:** Construct complex objects step-by-step with fluent API.

```typescript
class QueryBuilder {
  private table = ''
  private conditions: string[] = []
  private cols: string[] = ['*']

  from(table: string) { this.table = table; return this }
  select(...cols: string[]) { this.cols = cols; return this }
  where(cond: string) { this.conditions.push(cond); return this }

  build(): string {
    let q = `SELECT ${this.cols.join(', ')} FROM ${this.table}`
    if (this.conditions.length) q += ` WHERE ${this.conditions.join(' AND ')}`
    return q
  }
}

const query = new QueryBuilder().from('users').select('name', 'email').where('active = true').build()
```

**Use when:** Objects with many optional params; different representations of same construction process.

### Singleton

**Intent:** Ensure single instance with global access.

```typescript
// Idiomatic TS: module-scoped const IS a singleton
// file: config.ts
export const config = Object.freeze({ dbUrl: process.env.DB_URL, port: 3000 })

// Class-based (when lazy init or complex setup needed)
class Database {
  static #instance: Database
  private constructor() {}
  static get instance(): Database {
    return (Database.#instance ??= new Database())
  }
}
```

**Prefer:** Module-level `const`/`let` over class-based singletons. ES modules are evaluated once.

### Prototype

**Intent:** Clone existing objects without depending on their classes.

```typescript
interface Cloneable<T> { clone(): T }

class Settings implements Cloneable<Settings> {
  constructor(public theme: string, public fontSize: number, public plugins: string[]) {}
  clone(): Settings {
    return new Settings(this.theme, this.fontSize, [...this.plugins])
  }
}
```

**Use when:** Creating variations of configured objects; avoiding costly re-initialization.

## STRUCTURAL PATTERNS

### Adapter

**Intent:** Make incompatible interfaces work together by wrapping one.

```typescript
// Target interface
interface Logger { log(msg: string): void }

// Adaptee (third-party, different API)
class LegacyLogger { writeLog(text: string, level: number) { /* ... */ } }

// Adapter
class LegacyLoggerAdapter implements Logger {
  constructor(private legacy: LegacyLogger) {}
  log(msg: string) { this.legacy.writeLog(msg, 1) }
}

function app(logger: Logger) { logger.log('hello') }
app(new LegacyLoggerAdapter(new LegacyLogger()))
```

**Use when:** Integrating third-party libraries, wrapping legacy APIs, normalizing data sources.

### Decorator

**Intent:** Add behavior dynamically by wrapping objects (stackable).

```typescript
interface DataSource { read(): string; write(data: string): void }

class FileSource implements DataSource {
  read() { return 'raw data' }
  write(data: string) { /* write to file */ }
}

class EncryptionDecorator implements DataSource {
  constructor(private wrapped: DataSource) {}
  read() { return decrypt(this.wrapped.read()) }
  write(data: string) { this.wrapped.write(encrypt(data)) }
}

class CompressionDecorator implements DataSource {
  constructor(private wrapped: DataSource) {}
  read() { return decompress(this.wrapped.read()) }
  write(data: string) { this.wrapped.write(compress(data)) }
}

// Stack: compression → encryption → file
const source = new CompressionDecorator(new EncryptionDecorator(new FileSource()))
```

**Use when:** Express/Koa middleware, I/O layers (buffering/encryption/compression), logging wrappers.

### Facade

**Intent:** Simplified interface to a complex subsystem.

```typescript
class VideoConverter {
  constructor(
    private decoder = new VideoDecoder(),
    private encoder = new VideoEncoder(),
    private mixer = new AudioMixer()
  ) {}

  convert(filename: string, format: string): Buffer {
    const video = this.decoder.decode(filename)
    const audio = this.mixer.extract(filename)
    return this.encoder.encode(video, audio, format)
  }
}

// Client uses one method instead of three subsystems
new VideoConverter().convert('video.mp4', 'webm')
```

### Proxy

**Intent:** Placeholder controlling access to another object.

```typescript
interface Service { request(): string }

class RealService implements Service {
  request() { return 'Real response' }
}

class CachingProxy implements Service {
  private cache?: string
  constructor(private real: RealService) {}

  request(): string {
    if (!this.cache) {
      this.cache = this.real.request()
    }
    return this.cache
  }
}

// Also: JS native Proxy for meta-programming
const handler: ProxyHandler<Record<string, any>> = {
  get(target, prop) {
    console.log(`Accessing ${String(prop)}`)
    return Reflect.get(target, prop)
  }
}
const proxy = new Proxy({ name: 'Alice' }, handler)
```

**Variants:** Lazy loading (virtual proxy), access control (protection proxy), caching, logging.

### Composite

**Intent:** Treat individual objects and compositions uniformly as a tree.

```typescript
interface Component {
  operation(): string
  add?(child: Component): void
}

class Leaf implements Component {
  constructor(private name: string) {}
  operation() { return this.name }
}

class Composite implements Component {
  private children: Component[] = []
  add(child: Component) { this.children.push(child) }
  operation(): string {
    return `Branch(${this.children.map(c => c.operation()).join('+')})`
  }
}
```

**Use when:** File system trees, UI component hierarchies, AST nodes, menu systems.

### Bridge

**Intent:** Separate abstraction from implementation so both can vary independently.

```typescript
interface Renderer { renderCircle(x: number, y: number, r: number): void }

class SVGRenderer implements Renderer {
  renderCircle(x: number, y: number, r: number) { console.log(`<circle cx="${x}" cy="${y}" r="${r}"/>`) }
}
class CanvasRenderer implements Renderer {
  renderCircle(x: number, y: number, r: number) { console.log(`canvas.arc(${x}, ${y}, ${r})`) }
}

class Circle {
  constructor(private x: number, private y: number, private r: number, private renderer: Renderer) {}
  draw() { this.renderer.renderCircle(this.x, this.y, this.r) }
}
```

### Flyweight

**Intent:** Share common state between many objects to reduce memory.

```typescript
class TreeType {
  constructor(public name: string, public color: string, public texture: string) {}
}

class TreeFactory {
  private static types = new Map<string, TreeType>()

  static getType(name: string, color: string, texture: string): TreeType {
    const key = `${name}_${color}_${texture}`
    if (!this.types.has(key)) {
      this.types.set(key, new TreeType(name, color, texture))
    }
    return this.types.get(key)!
  }
}

// Thousands of trees share a few TreeType instances
class Tree {
  constructor(public x: number, public y: number, public type: TreeType) {}
}
```

## BEHAVIORAL PATTERNS

### Strategy

**Intent:** Define interchangeable algorithms, swap at runtime.

```typescript
// Idiomatic TS: function types as strategies (no class needed)
type SortStrategy<T> = (data: T[]) => T[]

const bubbleSort: SortStrategy<number> = (data) => { /* ... */ return data }
const quickSort: SortStrategy<number> = (data) => { /* ... */ return data }

class Sorter<T> {
  constructor(private strategy: SortStrategy<T>) {}
  setStrategy(s: SortStrategy<T>) { this.strategy = s }
  sort(data: T[]): T[] { return this.strategy(data) }
}

// Interface-based (when strategy has multiple methods or state)
interface Compressor {
  compress(data: Buffer): Buffer
  decompress(data: Buffer): Buffer
}
```

**Prefer:** Function types for single-method strategies; interfaces when strategies have multiple methods or internal state.

### Observer

**Intent:** Notify dependents of state changes (pub/sub).

```typescript
// Idiomatic TS: typed EventEmitter
type EventMap = {
  priceUpdate: [price: number]
  trade: [symbol: string, qty: number]
}

class TypedEmitter<T extends Record<string, any[]>> {
  private listeners = new Map<keyof T, Set<Function>>()

  on<K extends keyof T>(event: K, fn: (...args: T[K]) => void) {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set())
    this.listeners.get(event)!.add(fn)
    return () => this.listeners.get(event)!.delete(fn) // unsubscribe
  }

  emit<K extends keyof T>(event: K, ...args: T[K]) {
    this.listeners.get(event)?.forEach(fn => fn(...args))
  }
}

const emitter = new TypedEmitter<EventMap>()
const unsub = emitter.on('priceUpdate', (price) => console.log(price))
emitter.emit('priceUpdate', 42.5)
unsub() // cleanup
```

**Also:** Node.js `EventEmitter`, RxJS `Subject`, DOM `EventTarget`.

### Command

**Intent:** Encapsulate request as object for undo/redo, queueing, logging.

```typescript
// Simple: closures as commands
type Command = { execute(): void; undo(): void }

function makeInsertCommand(doc: string[], pos: number, text: string): Command {
  return {
    execute() { doc.splice(pos, 0, text) },
    undo() { doc.splice(pos, 1) },
  }
}

class CommandHistory {
  private stack: Command[] = []
  execute(cmd: Command) { cmd.execute(); this.stack.push(cmd) }
  undo() { this.stack.pop()?.undo() }
}
```

**Use when:** Undo/redo, transaction queues, macro recording, CQRS.

### State

**Intent:** Object alters behavior when internal state changes.

```typescript
interface State {
  handle(context: Player): void
}

class Player {
  constructor(public state: State) {}
  changeState(s: State) { this.state = s }
  play() { this.state.handle(this) }
}

class StoppedState implements State {
  handle(ctx: Player) {
    console.log('Starting playback')
    ctx.changeState(new PlayingState())
  }
}

class PlayingState implements State {
  handle(ctx: Player) {
    console.log('Pausing playback')
    ctx.changeState(new PausedState())
  }
}

class PausedState implements State {
  handle(ctx: Player) {
    console.log('Resuming playback')
    ctx.changeState(new PlayingState())
  }
}
```

**Use when:** Order workflows (Pending→Paid→Shipped), protocol handlers, UI states.

### Chain of Responsibility

**Intent:** Pass request through handler chain; each processes or forwards.

```typescript
// Idiomatic TS: middleware-style functions
type Middleware<T> = (req: T, next: () => void) => void

function runChain<T>(middlewares: Middleware<T>[], req: T) {
  let i = 0
  const next = () => { if (i < middlewares.length) middlewares[i++](req, next) }
  next()
}

// Usage
const auth: Middleware<Request> = (req, next) => {
  if (!req.token) throw new Error('401')
  next()
}
const log: Middleware<Request> = (req, next) => {
  console.log(req.path)
  next()
}

runChain([auth, log], request)
```

**Use when:** Express/Koa middleware, validation pipelines, event bubbling.

### Iterator

**Intent:** Sequential access without exposing internals.

```typescript
// Idiomatic TS: Symbol.iterator for for...of support
class Range {
  constructor(private start: number, private end: number) {}

  *[Symbol.iterator]() {
    for (let i = this.start; i <= this.end; i++) yield i
  }
}

for (const n of new Range(1, 5)) console.log(n) // 1, 2, 3, 4, 5

// Async iterator
class PaginatedAPI {
  async *[Symbol.asyncIterator]() {
    let page = 1
    while (true) {
      const data = await fetch(`/api?page=${page++}`).then(r => r.json())
      if (!data.items.length) break
      yield* data.items
    }
  }
}

for await (const item of new PaginatedAPI()) { /* ... */ }
```

### Template Method

**Intent:** Define algorithm skeleton; subclasses fill specific steps.

```typescript
abstract class DataMiner {
  // Template method — fixed skeleton
  mine(source: string) {
    const raw = this.extract(source)
    const data = this.parse(raw)
    this.analyze(data) // hook — optional override
    return data
  }

  protected abstract extract(source: string): string
  protected abstract parse(raw: string): string[]
  protected analyze(data: string[]) {} // default: no-op hook
}

class CSVMiner extends DataMiner {
  protected extract(source: string) { return readFileSync(source, 'utf8') }
  protected parse(raw: string) { return raw.split('\n') }
}
```

### Mediator

**Intent:** Centralize complex communications between components.

```typescript
interface Mediator { notify(sender: string, event: string): void }

class DialogMediator implements Mediator {
  constructor(private loginBtn: Button, private usernameInput: Input) {
    this.loginBtn.setMediator(this)
    this.usernameInput.setMediator(this)
  }

  notify(sender: string, event: string) {
    if (sender === 'username' && event === 'change') {
      this.loginBtn.setEnabled(this.usernameInput.value.length > 0)
    }
  }
}
```

**Use when:** Chat rooms, form validation coordination, air traffic control.

### Memento

**Intent:** Save and restore object state without violating encapsulation.

```typescript
class EditorMemento {
  constructor(readonly content: string, readonly cursor: number) {}
}

class Editor {
  constructor(public content = '', public cursor = 0) {}
  save(): EditorMemento { return new EditorMemento(this.content, this.cursor) }
  restore(m: EditorMemento) { this.content = m.content; this.cursor = m.cursor }
}

class History {
  private snapshots: EditorMemento[] = []
  push(m: EditorMemento) { this.snapshots.push(m) }
  pop(): EditorMemento | undefined { return this.snapshots.pop() }
}
```

### Visitor

**Intent:** Add operations to objects without modifying them.

```typescript
interface Visitor {
  visitCircle(c: Circle): void
  visitRect(r: Rect): void
}

interface Shape { accept(v: Visitor): void }

class Circle implements Shape {
  constructor(public radius: number) {}
  accept(v: Visitor) { v.visitCircle(this) }
}

class Rect implements Shape {
  constructor(public w: number, public h: number) {}
  accept(v: Visitor) { v.visitRect(this) }
}

class AreaCalculator implements Visitor {
  total = 0
  visitCircle(c: Circle) { this.total += Math.PI * c.radius ** 2 }
  visitRect(r: Rect) { this.total += r.w * r.h }
}
```

**Use when:** AST processing, serialization to multiple formats, computing operations over heterogeneous hierarchies.

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
