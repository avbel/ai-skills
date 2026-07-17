# Structural Patterns

## Adapter

**Intent:** Make incompatible interfaces work together by wrapping one.

```typescript
// Target interface
interface Logger { log(msg: string): void }

// Adaptee (third-party, different API)
class LegacyLogger { writeLog(text: string, level: number) { /* ... */ } }

// Adapter
class LegacyLoggerAdapter implements Logger {
  constructor(private legacy: LegacyLogger) {}
  log(msg: string) { this.legacy.writeLog(msg, 1); }
}

function app(logger: Logger) { logger.log('hello'); }
app(new LegacyLoggerAdapter(new LegacyLogger()));
```

**Use when:** Integrating third-party libraries, wrapping legacy APIs, normalizing data sources.

## Decorator

**Intent:** Add behavior dynamically by wrapping objects (stackable).

```typescript
interface DataSource { read(): string; write(data: string): void }

class FileSource implements DataSource {
  read() { return 'raw data'; }
  write(data: string) { /* write to file */ }
}

class EncryptionDecorator implements DataSource {
  constructor(private wrapped: DataSource) {}
  read() { return decrypt(this.wrapped.read()); }
  write(data: string) { this.wrapped.write(encrypt(data)); }
}

class CompressionDecorator implements DataSource {
  constructor(private wrapped: DataSource) {}
  read() { return decompress(this.wrapped.read()); }
  write(data: string) { this.wrapped.write(compress(data)); }
}

// Stack: compression → encryption → file
const source = new CompressionDecorator(new EncryptionDecorator(new FileSource()));
```

**Use when:** Express/Koa middleware, I/O layers (buffering/encryption/compression), logging wrappers.

## Facade

**Intent:** Simplified interface to a complex subsystem.

```typescript
class VideoConverter {
  constructor(
    private decoder = new VideoDecoder(),
    private encoder = new VideoEncoder(),
    private mixer = new AudioMixer()
  ) {}

  convert(filename: string, format: string): Buffer {
    const video = this.decoder.decode(filename);
    const audio = this.mixer.extract(filename);
    return this.encoder.encode(video, audio, format);
  }
}

// Client uses one method instead of three subsystems
new VideoConverter().convert('video.mp4', 'webm');
```

## Proxy

**Intent:** Placeholder controlling access to another object.

```typescript
interface Service { request(): string }

class RealService implements Service {
  request() { return 'Real response'; }
}

class CachingProxy implements Service {
  private cache?: string;
  constructor(private real: RealService) {}

  request(): string {
    if (!this.cache) {
      this.cache = this.real.request();
    }
    return this.cache;
  }
}

// Also: JS native Proxy for meta-programming
const handler: ProxyHandler<Record<string, unknown>> = {
  get(target, prop) {
    // record the access, e.g. audit(`Accessing ${String(prop)}`)
    return Reflect.get(target, prop);
  },
};
const proxy = new Proxy({ name: 'Alice' }, handler);
```

**Variants:** Lazy loading (virtual proxy), access control (protection proxy), caching, logging.

## Composite

**Intent:** Treat individual objects and compositions uniformly as a tree.

```typescript
interface Component {
  operation(): string;
  add?(child: Component): void;
}

class Leaf implements Component {
  constructor(private name: string) {}
  operation() { return this.name; }
}

class Composite implements Component {
  private children: Component[] = [];
  add(child: Component) { this.children.push(child); }
  operation(): string {
    return `Branch(${this.children.map(c => c.operation()).join('+')})`;
  }
}
```

**Use when:** File system trees, UI component hierarchies, AST nodes, menu systems.

## Bridge

**Intent:** Separate abstraction from implementation so both can vary independently.

```typescript
interface Renderer { renderCircle(x: number, y: number, r: number): void }

class SVGRenderer implements Renderer {
  renderCircle(x: number, y: number, r: number) {
    // emits `<circle cx="${x}" cy="${y}" r="${r}"/>`
  }
}
class CanvasRenderer implements Renderer {
  renderCircle(x: number, y: number, r: number) {
    // emits `canvas.arc(${x}, ${y}, ${r})`
  }
}

class Circle {
  constructor(private x: number, private y: number, private r: number, private renderer: Renderer) {}
  draw() { this.renderer.renderCircle(this.x, this.y, this.r); }
}
```

## Flyweight

**Intent:** Share common state between many objects to reduce memory.

```typescript
class TreeType {
  constructor(public name: string, public color: string, public texture: string) {}
}

class TreeFactory {
  private static types = new Map<string, TreeType>();

  static getType(name: string, color: string, texture: string): TreeType {
    const key = `${name}_${color}_${texture}`;
    if (!this.types.has(key)) {
      this.types.set(key, new TreeType(name, color, texture));
    }
    return this.types.get(key)!;
  }
}

// Thousands of trees share a few TreeType instances
class Tree {
  constructor(public x: number, public y: number, public type: TreeType) {}
}
```
