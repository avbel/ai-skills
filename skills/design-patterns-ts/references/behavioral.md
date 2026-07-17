# Behavioral Patterns

## Strategy

**Intent:** Define interchangeable algorithms, swap at runtime.

```typescript
// Idiomatic TS: function types as strategies (no class needed)
type SortStrategy<T> = (data: T[]) => T[];

const bubbleSort: SortStrategy<number> = (data) => { /* ... */ return data; };
const quickSort: SortStrategy<number> = (data) => { /* ... */ return data; };

class Sorter<T> {
  constructor(private strategy: SortStrategy<T>) {}
  setStrategy(s: SortStrategy<T>) { this.strategy = s; }
  sort(data: T[]): T[] { return this.strategy(data); }
}

// Interface-based (when strategy has multiple methods or state)
interface Compressor {
  compress(data: Buffer): Buffer;
  decompress(data: Buffer): Buffer;
}
```

**Prefer:** Function types for single-method strategies; interfaces when strategies have multiple methods or internal state.

## Observer

**Intent:** Notify dependents of state changes (pub/sub).

```typescript
// Idiomatic TS: typed EventEmitter
type EventMap = {
  priceUpdate: [price: number];
  trade: [symbol: string, qty: number];
};

class TypedEmitter<T extends Record<string, any[]>> {
  private listeners = new Map<keyof T, Set<Function>>();

  on<K extends keyof T>(event: K, fn: (...args: T[K]) => void) {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event)!.add(fn);
    return () => this.listeners.get(event)!.delete(fn); // unsubscribe
  }

  emit<K extends keyof T>(event: K, ...args: T[K]) {
    this.listeners.get(event)?.forEach(fn => fn(...args));
  }
}

const emitter = new TypedEmitter<EventMap>();
const unsub = emitter.on('priceUpdate', (price) => { /* handle price */ });
emitter.emit('priceUpdate', 42.5); // listener receives 42.5
unsub(); // cleanup
```

**Also:** Node.js `EventEmitter`, RxJS `Subject`, DOM `EventTarget`.

## Command

**Intent:** Encapsulate request as object for undo/redo, queueing, logging.

```typescript
// Simple: closures as commands
type Command = { execute(): void; undo(): void };

function makeInsertCommand(doc: string[], pos: number, text: string): Command {
  return {
    execute() { doc.splice(pos, 0, text); },
    undo() { doc.splice(pos, 1); },
  };
}

class CommandHistory {
  private stack: Command[] = [];
  execute(cmd: Command) { cmd.execute(); this.stack.push(cmd); }
  undo() { this.stack.pop()?.undo(); }
}
```

**Use when:** Undo/redo, transaction queues, macro recording, CQRS.

## State

**Intent:** Object alters behavior when internal state changes.

```typescript
interface State {
  handle(context: Player): void;
}

class Player {
  constructor(public state: State) {}
  changeState(s: State) { this.state = s; }
  play() { this.state.handle(this); }
}

class StoppedState implements State {
  handle(ctx: Player) {
    // starts playback
    ctx.changeState(new PlayingState());
  }
}

class PlayingState implements State {
  handle(ctx: Player) {
    // pauses playback
    ctx.changeState(new PausedState());
  }
}

class PausedState implements State {
  handle(ctx: Player) {
    // resumes playback
    ctx.changeState(new PlayingState());
  }
}
```

**Use when:** Order workflows (Pending→Paid→Shipped), protocol handlers, UI states.

## Chain of Responsibility

**Intent:** Pass request through handler chain; each processes or forwards.

```typescript
// Idiomatic TS: middleware-style functions
type Middleware<T> = (req: T, next: () => void) => void;

function runChain<T>(middlewares: Middleware<T>[], req: T) {
  let i = 0;
  const next = () => { if (i < middlewares.length) middlewares[i++](req, next); };
  next();
}

// Usage
const auth: Middleware<Request> = (req, next) => {
  if (!req.token) throw new Error('401');
  next();
};
const log: Middleware<Request> = (req, next) => {
  // record req.path, e.g. logger.info(req.path)
  next();
};

runChain([auth, log], request);
```

**Use when:** Express/Koa middleware, validation pipelines, event bubbling.

## Iterator

**Intent:** Sequential access without exposing internals.

```typescript
// Idiomatic TS: Symbol.iterator for for...of support
class Range {
  constructor(private start: number, private end: number) {}

  *[Symbol.iterator]() {
    for (let i = this.start; i <= this.end; i++) yield i;
  }
}

const numbers = [...new Range(1, 5)]; // => [1, 2, 3, 4, 5]

// Async iterator
class PaginatedAPI {
  async *[Symbol.asyncIterator]() {
    let page = 1;
    while (true) {
      const data = await fetch(`/api?page=${page++}`).then(r => r.json());
      if (!data.items.length) break;
      yield* data.items;
    }
  }
}

for await (const item of new PaginatedAPI()) { /* ... */ }
```

## Template Method

**Intent:** Define algorithm skeleton; subclasses fill specific steps.

```typescript
abstract class DataMiner {
  // Template method — fixed skeleton
  mine(source: string) {
    const raw = this.extract(source);
    const data = this.parse(raw);
    this.analyze(data); // hook — optional override
    return data;
  }

  protected abstract extract(source: string): string;
  protected abstract parse(raw: string): string[];
  protected analyze(data: string[]) {} // default: no-op hook
}

class CSVMiner extends DataMiner {
  protected extract(source: string) { return readFileSync(source, 'utf8'); }
  protected parse(raw: string) { return raw.split('\n'); }
}
```

## Mediator

**Intent:** Centralize complex communications between components.

```typescript
interface Mediator { notify(sender: string, event: string): void }

class DialogMediator implements Mediator {
  constructor(private loginBtn: Button, private usernameInput: Input) {
    this.loginBtn.setMediator(this);
    this.usernameInput.setMediator(this);
  }

  notify(sender: string, event: string) {
    if (sender === 'username' && event === 'change') {
      this.loginBtn.setEnabled(this.usernameInput.value.length > 0);
    }
  }
}
```

**Use when:** Chat rooms, form validation coordination, air traffic control.

## Memento

**Intent:** Save and restore object state without violating encapsulation.

```typescript
class EditorMemento {
  constructor(readonly content: string, readonly cursor: number) {}
}

class Editor {
  constructor(public content = '', public cursor = 0) {}
  save(): EditorMemento { return new EditorMemento(this.content, this.cursor); }
  restore(m: EditorMemento) { this.content = m.content; this.cursor = m.cursor; }
}

class History {
  private snapshots: EditorMemento[] = [];
  push(m: EditorMemento) { this.snapshots.push(m); }
  pop(): EditorMemento | undefined { return this.snapshots.pop(); }
}
```

## Visitor

**Intent:** Add operations to objects without modifying them.

```typescript
interface Visitor {
  visitCircle(c: Circle): void;
  visitRect(r: Rect): void;
}

interface Shape { accept(v: Visitor): void }

class Circle implements Shape {
  constructor(public radius: number) {}
  accept(v: Visitor) { v.visitCircle(this); }
}

class Rect implements Shape {
  constructor(public w: number, public h: number) {}
  accept(v: Visitor) { v.visitRect(this); }
}

class AreaCalculator implements Visitor {
  total = 0;
  visitCircle(c: Circle) { this.total += Math.PI * c.radius ** 2; }
  visitRect(r: Rect) { this.total += r.w * r.h; }
}
```

**Use when:** AST processing, serialization to multiple formats, computing operations over heterogeneous hierarchies.
