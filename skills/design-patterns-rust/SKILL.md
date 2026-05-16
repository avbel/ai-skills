---
name: design-patterns-rust
description: Design patterns adapted to idiomatic Rust — Builder, Factory, Singleton (OnceLock), Newtype, Adapter, Decorator, Composite, Strategy (traits/enums/closures), Command, Observer (channels), State (enum state machines), Typestate, RAII/Drop, Iterator, and trait-vs-enum dispatch trade-offs. Use when implementing or refactoring code that involves design patterns in Rust.
---

Apply these patterns when designing or refactoring Rust code. Many GoF patterns translate differently in Rust due to ownership, enums, traits, and lack of inheritance.

## CREATIONAL PATTERNS

### Builder

**Intent:** Construct complex structs step-by-step.

```rust
// Consuming builder (idiomatic — builder is consumed on build)
struct RequestBuilder {
    url: String,
    method: String,
    headers: Vec<(String, String)>,
    body: Option<String>,
}

impl RequestBuilder {
    fn new(url: impl Into<String>) -> Self {
        Self { url: url.into(), method: "GET".into(), headers: vec![], body: None }
    }
    fn method(mut self, m: &str) -> Self { self.method = m.into(); self }
    fn header(mut self, k: &str, v: &str) -> Self {
        self.headers.push((k.into(), v.into())); self
    }
    fn body(mut self, b: impl Into<String>) -> Self { self.body = Some(b.into()); self }
    fn build(self) -> Request {
        Request { url: self.url, method: self.method,
                  headers: self.headers, body: self.body }
    }
}

// One-liner:
let req = RequestBuilder::new("https://api.example.com")
    .method("POST").header("Content-Type", "application/json")
    .body(r#"{"key": "value"}"#).build();
```

**Two variants:** Consuming (`self`) prevents reuse bugs via move semantics. Non-consuming (`&mut self`) allows reconfiguration; requires `.clone()` in `build()`.

### Factory (Functions + Traits)

**Intent:** Encapsulate creation logic behind an interface.

```rust
trait Transport { fn deliver(&self); }
struct Truck;
struct Ship;
impl Transport for Truck { fn deliver(&self) { println!("By road"); } }
impl Transport for Ship  { fn deliver(&self) { println!("By sea"); } }

// Factory function with trait object (dynamic dispatch)
fn create_transport(mode: &str) -> Box<dyn Transport> {
    match mode {
        "land" => Box::new(Truck),
        "sea"  => Box::new(Ship),
        _ => panic!("Unknown mode"),
    }
}

// Factory via generics (static dispatch, zero cost)
fn process<T: Transport>(t: &T) { t.deliver(); }
```

No abstract factory class hierarchy needed — a function + `match` replaces it.

### Singleton (OnceLock / LazyLock)

**Intent:** Single global instance with thread-safe lazy initialization.

```rust
use std::sync::{LazyLock, OnceLock, Mutex};

// LazyLock — initialized on first access (Rust >= 1.80)
static CONFIG: LazyLock<Config> = LazyLock::new(|| Config::load_from_env());

// OnceLock — set explicitly, get later
static DB: OnceLock<Pool> = OnceLock::new();
fn init_db() { DB.set(Pool::connect("postgres://...")).unwrap(); }
fn db() -> &'static Pool { DB.get().expect("DB not initialized") }

// Mutable singleton — wrap in Mutex
static REGISTRY: LazyLock<Mutex<Vec<String>>> = LazyLock::new(|| Mutex::new(vec![]));
```

Use sparingly — prefer dependency injection.

## STRUCTURAL PATTERNS

### Newtype

**Intent:** Wrap a type for distinct semantics, type safety, or trait orphan rule.

```rust
struct Miles(f64);
struct Kilometers(f64);

impl Miles {
    fn to_km(&self) -> Kilometers { Kilometers(self.0 * 1.60934) }
}

fn drive(distance: Kilometers) { /* ... */ }
// drive(Miles(10.0)); // COMPILE ERROR — type mismatch

// Orphan rule workaround: impl foreign trait on foreign type
struct Wrapper(Vec<String>);
impl std::fmt::Display for Wrapper {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "[{}]", self.0.join(", "))
    }
}
```

Zero-cost at runtime (`#[repr(transparent)]`).

### Adapter (Trait Impl on Wrapper)

**Intent:** Make incompatible interfaces work together.

```rust
trait Logger { fn log(&self, msg: &str); }

// Adaptee with different interface
struct LegacyLogger;
impl LegacyLogger { fn write_log(&self, text: String) { println!("[OLD] {text}"); } }

// Adapter
struct LegacyAdapter { inner: LegacyLogger }
impl Logger for LegacyAdapter {
    fn log(&self, msg: &str) { self.inner.write_log(format!("ADAPTED: {msg}")); }
}
```

### Decorator (Generic Wrapping)

**Intent:** Add behavior by wrapping (stackable).

```rust
trait DataSource { fn read(&self) -> String; }

struct FileSource { path: String }
impl DataSource for FileSource {
    fn read(&self) -> String { std::fs::read_to_string(&self.path).unwrap() }
}

struct Encrypted<T: DataSource> { inner: T }
impl<T: DataSource> DataSource for Encrypted<T> {
    fn read(&self) -> String { format!("DECRYPTED({})", self.inner.read()) }
}

struct Compressed<T: DataSource> { inner: T }
impl<T: DataSource> DataSource for Compressed<T> {
    fn read(&self) -> String { format!("DECOMPRESSED({})", self.inner.read()) }
}

// Stack: Compressed<Encrypted<FileSource>>
// let src = Compressed { inner: Encrypted { inner: FileSource { path: "f.txt".into() } } };
```

Generic `T` = static dispatch, zero-cost. Use `Box<dyn DataSource>` for dynamic stacking. Real-world: `BufReader<R: Read>`.

### Facade

```rust
struct MediaPlayer { video: VideoDecoder, audio: AudioDecoder }
impl MediaPlayer {
    fn new() -> Self { Self { video: VideoDecoder, audio: AudioDecoder } }
    fn play(&self, file: &str) {
        self.video.decode(file);
        self.audio.decode(file);
    }
}
```

Rust modules also serve as natural facades via `pub` visibility.

### Composite (Recursive Enum)

```rust
enum FileSystem {
    File { name: String, size: u64 },
    Dir { name: String, children: Vec<FileSystem> },
}

impl FileSystem {
    fn size(&self) -> u64 {
        match self {
            Self::File { size, .. } => *size,
            Self::Dir { children, .. } => children.iter().map(|c| c.size()).sum(),
        }
    }
}
```

Enum replaces Component/Leaf/Composite hierarchy. `match` is exhaustive.

### Compose Structs (Borrow Checker Pattern)

**Intent:** Split a struct so the borrow checker allows partial borrows.

```rust
// PROBLEM: can't borrow self.cache mutably while reading self.conn
// SOLUTION: separate into independent structs
struct Connection { /* ... */ }
struct Cache { data: HashMap<String, String> }

struct Database { conn: Connection, cache: Cache }

impl Database {
    fn update(&mut self) {
        let result = self.conn.query("...");
        self.cache.data.insert("key".into(), result); // both borrows are independent
    }
}
```

Rust-specific — exists to satisfy the borrow checker.

## BEHAVIORAL PATTERNS

### Strategy (Three Approaches)

```rust
// 1. Closures (simplest for single-method strategies)
fn process(data: &[u8], compress: impl Fn(&[u8]) -> Vec<u8>) {
    let _result = compress(data);
}
process(b"hello", |d| d.to_vec());

// 2. Trait objects (open set, multiple methods, state)
trait Compressor { fn compress(&self, data: &[u8]) -> Vec<u8>; }
fn store(data: &[u8], strategy: &dyn Compressor) { strategy.compress(data); }

// 3. Enum dispatch (closed set, ~10x faster than trait objects)
enum Algorithm { Gzip, Lz4 }
impl Algorithm {
    fn compress(&self, data: &[u8]) -> Vec<u8> {
        match self {
            Self::Gzip => { /* gzip */ data.to_vec() }
            Self::Lz4  => { /* lz4 */  data.to_vec() }
        }
    }
}
```

### Command

```rust
trait Command { fn execute(&mut self); fn undo(&mut self); }

struct History { stack: Vec<Box<dyn Command>> }
impl History {
    fn execute(&mut self, mut cmd: Box<dyn Command>) {
        cmd.execute();
        self.stack.push(cmd);
    }
    fn undo(&mut self) { if let Some(mut cmd) = self.stack.pop() { cmd.undo(); } }
}

// Simple: closures as commands
let cmds: Vec<Box<dyn Fn()>> = vec![Box::new(|| println!("save"))];
```

### Observer (Channels)

```rust
use std::sync::mpsc;

#[derive(Clone, Debug)]
enum Event { PriceUpdate(f64), Trade { qty: u64 } }

let (tx, rx) = mpsc::channel::<Event>();
let tx2 = tx.clone(); // multiple producers

// Observer thread
std::thread::spawn(move || {
    while let Ok(event) = rx.recv() {
        match event {
            Event::PriceUpdate(p) => println!("price={p}"),
            Event::Trade { qty } => println!("traded {qty}"),
        }
    }
});

tx.send(Event::PriceUpdate(42.0)).unwrap();
```

For async: `tokio::sync::broadcast` for multi-consumer pub/sub.

### State — Enum State Machine

```rust
enum ConnState {
    Disconnected,
    Connecting { attempt: u32 },
    Connected { session_id: u64 },
}

struct Connection { state: ConnState }

impl Connection {
    fn connect(&mut self) {
        self.state = match &self.state {
            ConnState::Disconnected => ConnState::Connecting { attempt: 1 },
            ConnState::Connecting { attempt } =>
                ConnState::Connecting { attempt: attempt + 1 },
            _ => return,
        };
    }
    fn on_connected(&mut self, session: u64) {
        if matches!(self.state, ConnState::Connecting { .. }) {
            self.state = ConnState::Connected { session_id: session };
        }
    }
}
```

Enum variants hold per-state data. `match` is exhaustive — compiler forces handling all states.

### Iterator (Built-in)

```rust
struct Fibonacci { a: u64, b: u64 }
impl Fibonacci { fn new() -> Self { Self { a: 0, b: 1 } } }

impl Iterator for Fibonacci {
    type Item = u64;
    fn next(&mut self) -> Option<Self::Item> {
        let val = self.a;
        (self.a, self.b) = (self.b, self.a + self.b);
        Some(val)
    }
}

// Fibonacci::new().take(10).filter(|n| n % 2 == 0).collect::<Vec<_>>();
```

Lazy adaptors (`.map()`, `.filter()`, `.take()`) are zero-cost.

### Template Method (Trait Default Methods)

```rust
trait DataMiner {
    fn extract(&self, source: &str) -> String;    // required
    fn parse(&self, raw: &str) -> Vec<String>;     // required

    fn mine(&self, source: &str) -> Vec<String> {  // template method
        let raw = self.extract(source);
        let data = self.parse(&raw);
        self.analyze(&data); // hook
        data
    }
    fn analyze(&self, _data: &[String]) {}         // hook — default no-op
}

struct CsvMiner;
impl DataMiner for CsvMiner {
    fn extract(&self, source: &str) -> String { std::fs::read_to_string(source).unwrap() }
    fn parse(&self, raw: &str) -> Vec<String> { raw.lines().map(String::from).collect() }
}
```

### Chain of Responsibility

```rust
type Handler = Box<dyn Fn(&mut Request) -> bool>; // true = handled

fn process(chain: &[Handler], req: &mut Request) {
    for handler in chain {
        if handler(req) { return; }
    }
}

let chain: Vec<Handler> = vec![
    Box::new(|req| { if !req.auth { println!("401"); return true; } false }),
    Box::new(|req| { println!("200 OK"); true }),
];
```

`Vec<Box<dyn Fn>>` replaces linked-list of handler objects.

### Visitor (Enum + Match)

```rust
enum Expr {
    Num(f64),
    Add(Box<Expr>, Box<Expr>),
    Mul(Box<Expr>, Box<Expr>),
}

// Each "visitor" is a function with match
fn evaluate(expr: &Expr) -> f64 {
    match expr {
        Expr::Num(n) => *n,
        Expr::Add(a, b) => evaluate(a) + evaluate(b),
        Expr::Mul(a, b) => evaluate(a) * evaluate(b),
    }
}

fn pretty(expr: &Expr) -> String {
    match expr {
        Expr::Num(n) => n.to_string(),
        Expr::Add(a, b) => format!("({} + {})", pretty(a), pretty(b)),
        Expr::Mul(a, b) => format!("({} * {})", pretty(a), pretty(b)),
    }
}
```

`match` on enums replaces the Visitor pattern for closed type sets.

## RUST-SPECIFIC PATTERNS

### Typestate Pattern

**Intent:** Encode valid state transitions in the type system — invalid transitions are compile errors.

```rust
use std::marker::PhantomData;

struct Draft;
struct Published;

struct Post<State> {
    title: String,
    content: String,
    _state: PhantomData<State>,
}

impl Post<Draft> {
    fn new(title: impl Into<String>) -> Self {
        Post { title: title.into(), content: String::new(), _state: PhantomData }
    }
    fn set_content(mut self, c: impl Into<String>) -> Self { self.content = c.into(); self }
    fn publish(self) -> Post<Published> {
        Post { title: self.title, content: self.content, _state: PhantomData }
    }
}

impl Post<Published> {
    fn content(&self) -> &str { &self.content }
}

// post.set_content("x") after publish() is a COMPILE ERROR
```

`PhantomData<State>` is zero-sized — entire state machine enforced at compile time with zero runtime cost.

### RAII / Drop

**Intent:** Tie resource lifetime to scope — cleanup is automatic.

```rust
struct TempFile { path: std::path::PathBuf }

impl TempFile {
    fn new(path: impl Into<std::path::PathBuf>) -> std::io::Result<Self> {
        let path = path.into();
        std::fs::File::create(&path)?;
        Ok(Self { path })
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

// Guard pattern (like MutexGuard)
struct Timer { label: String, start: std::time::Instant }
impl Timer {
    fn start(label: impl Into<String>) -> Self {
        Self { label: label.into(), start: std::time::Instant::now() }
    }
}
impl Drop for Timer {
    fn drop(&mut self) { println!("{}: {:?}", self.label, self.start.elapsed()); }
}

fn work() {
    let _timer = Timer::start("work"); // prints elapsed on scope exit
    let _tmp = TempFile::new("/tmp/scratch.dat").unwrap(); // deleted on scope exit
}
```

Replaces try/finally, IDisposable. Ownership makes RAII the default in Rust.

## TRAIT OBJECTS vs ENUM DISPATCH

| | Enum | `dyn Trait` |
|---|---|---|
| Performance | ~10x faster (inlining, no vtable) | Vtable lookup, no inlining |
| Memory | Stack, contiguous in Vec | Heap (Box), pointer indirection |
| Extensibility | Closed — adding variant modifies enum | Open — new types impl trait anywhere |
| Use when | You control all variants | Plugins, extensibility, downstream crates |

```rust
// Enum: fastest, closed set
enum Shape { Circle(f64), Rect(f64, f64) }
impl Shape {
    fn area(&self) -> f64 {
        match self {
            Shape::Circle(r) => std::f64::consts::PI * r * r,
            Shape::Rect(w, h) => w * h,
        }
    }
}

// Trait object: extensible, open set
trait ShapeTrait { fn area(&self) -> f64; }
fn total_area(shapes: &[Box<dyn ShapeTrait>]) -> f64 {
    shapes.iter().map(|s| s.area()).sum()
}
```

**Rule:** If all variants known at compile time, use enum. If third-party extensibility needed, use trait objects.

## ANTI-PATTERNS

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `clone()` to appease borrow checker | Hides ownership issues | Restructure borrows, decompose structs |
| `Deref` polymorphism | Faking inheritance via `Deref` | Use composition + traits |
| `#[deny(warnings)]` in code | Breaks on new Rust versions | Use `RUSTFLAGS=-Dwarnings` in CI only |

## QUICK REFERENCE

| Pattern | Rust Mechanism | OOP Equivalent |
|---|---|---|
| Builder | `self`/`&mut self` chaining | Builder class + Director |
| Factory | Functions + `match` + trait objects | Factory Method / Abstract Factory |
| Singleton | `LazyLock` / `OnceLock` | `getInstance()` + locks |
| Newtype | Tuple struct `struct X(T)` | Wrapper subclass |
| Adapter | Trait impl on wrapper struct | Adapter class |
| Decorator | Generic `W<T: Trait>` | Decorator hierarchy |
| Composite | Recursive enum | Component/Leaf/Composite |
| Strategy | Closures / trait objects / enums | Strategy interface |
| Command | `Box<dyn Command>` or `Box<dyn Fn()>` | Command interface |
| Observer | `mpsc` / `broadcast` channels | Observer/Subject |
| State | Enum variants + `match` | State interface + subclasses |
| Typestate | `PhantomData<S>` + impl blocks | N/A (Rust-specific) |
| Iterator | `impl Iterator` (built-in) | Iterator interface |
| Template Method | Trait default methods | Abstract base class |
| Chain of Resp. | `Vec<Box<dyn Fn>>` | Handler linked list |
| Visitor | `match` on enum | Visitor + accept() |
| RAII/Drop | `impl Drop` | Destructor / IDisposable |
