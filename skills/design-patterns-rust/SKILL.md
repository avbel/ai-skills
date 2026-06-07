---
name: design-patterns-rust
description: Design patterns and idioms adapted to idiomatic Rust — the "social norm" idioms (borrowed args, Default, mem::take/replace, on-stack dynamic dispatch, temporary mutability, non_exhaustive, return-consumed-arg, closure capture), GoF patterns (Builder, Factory, Singleton, Newtype, Adapter, Decorator, Composite, Strategy, Command, Observer, State, Typestate, RAII, Iterator, Fold), anti-patterns (clone-to-appease, Deref polymorphism), trait-vs-enum dispatch, and core design principles (SOLID, composition-over-inheritance, DRY, KISS, LoD, CQS, POLA). Use when implementing or refactoring code that involves design patterns or idioms in Rust.
---

Apply these patterns when designing or refactoring Rust code. Many GoF patterns translate differently in Rust due to ownership, enums, traits, and lack of inheritance. Distilled from the *Rust Design Patterns* book (rust-unofficial/patterns): **idioms** are the community's social norms — break them only with a good reason; **patterns** solve recurring problems; **anti-patterns** look helpful but cause more problems. Always favor *why* you reach for a pattern over *how* to spell it.

## IDIOMS (social norms)

Foundational habits that make Rust code idiomatic. Prefer these before reaching for a named pattern.

### Borrowed types for arguments

Take the most general borrow. Prefer `&str` over `&String`, `&[T]` over `&Vec<T>`, `&T` over `&Box<T>` — callers with either form can pass in, and you avoid a layer of indirection.

```rust
fn count_words(text: &str) -> usize { text.split_whitespace().count() } // not &String
```

### Concatenate with `format!`

For building a string from pieces, `format!` reads better than a chain of `push_str`/`+`. Use `push_str` only in a hot loop where the extra allocation matters.

```rust
let s = format!("{name} is {age} years old"); // not "..".to_string() + &name + ..
```

### The `Default` trait

Implement (or `#[derive(Default)]`) `Default` for types with a sensible zero value, then use struct-update syntax to override a few fields. Enables `T::default()` in generic code and `..Default::default()` initialization.

```rust
#[derive(Default)]
struct Config { retries: u32, verbose: bool, name: String }
let c = Config { retries: 3, ..Default::default() };
```

### `mem::take` / `mem::replace` to mutate owned values behind `&mut`

You can't move a field out of a `&mut` reference. `mem::take` (leaves `Default::default()`) and `mem::replace` (leaves a supplied value) let you take ownership without cloning — essential when transitioning enum variants in place.

```rust
fn a_to_b(e: &mut MyEnum) {
    if let MyEnum::A { name, x: 0 } = e {
        *e = MyEnum::B { name: std::mem::take(name) }; // moves name out, no clone
    }
}
```

### On-stack dynamic dispatch

Bind differently-typed values to one `&mut dyn Trait` to get dynamic dispatch without a heap allocation. Since Rust 1.79 temporaries in `&`/`&mut` live long enough, so no deferred `let` bindings needed.

```rust
let readable: &mut dyn std::io::Read =
    if arg == "-" { &mut std::io::stdin() } else { &mut std::fs::File::open(arg)? };
// read from `readable` — no Box, no monomorphization of the code that follows
```

### Temporary mutability

When data is mutated only during setup and read-only afterward, make that intent explicit by rebinding to an immutable binding (or use a nested block). The compiler then guarantees no later mutation.

```rust
let mut data = get_vec();
data.sort();
let data = data; // now immutable
```

### Iterating over `Option`

`Option<T>` is `IntoIterator` (0 or 1 element) — use it directly with `.iter()`/`.extend()`/`chain()` instead of `if let`.

```rust
let mut names = vec!["a"];
names.extend(maybe_name.as_ref()); // pushes 0 or 1 item
```

### Return the consumed argument on error

If a fallible function moves an argument, hand it back inside the error so the caller can retry without cloning up front. The std library does this (`String::from_utf8` → `FromUtf8Error::into_bytes`).

```rust
pub struct SendError(String);
pub fn send(value: String) -> Result<(), SendError> {
    if ready() { Ok(()) } else { Err(SendError(value)) } // caller recovers `value`
}
```

### Pass selected variables into a closure

Closures capture the whole environment by borrow, or everything by `move`. To move/clone/borrow *specific* variables, rebind them in an enclosing block before the `move` closure.

```rust
let closure = {
    let num2 = num2.clone();   // cloned
    let num3 = num3.as_ref();  // borrowed
    move || *num1 + *num2 + *num3 // num1 moved
};
```

### `#[non_exhaustive]` for future-proof public types

Mark public structs/enums/variants `#[non_exhaustive]` so downstream crates can't exhaustively match or struct-literal them — letting you add fields/variants later without a breaking change. Costs ergonomics (forces a wildcard arm), so reserve for genuinely evolving APIs.

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

A `static` requires its inner type to be `Sync`. For a *mutable* singleton you can't use bare `RefCell`/`Cell` (`!Sync`) — wrap state in `Mutex`/`RwLock` (as `REGISTRY` above) or use atomics. Use singletons sparingly — prefer dependency injection.

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

### Other Rust structural guidance

- **Prefer small crates.** Split functionality into focused crates: faster parallel compilation, clear semver boundaries, and reuse. A crate should do one thing well.
- **Contain `unsafe` in small modules.** Wrap unsafe code in a minimal, well-documented module/abstraction that exposes a safe API and upholds its invariants internally — so reviewers audit a small surface, not the whole crate. Every `unsafe` block carries a `// SAFETY:` note.
- **Custom traits to avoid complex type bounds.** When several generic bounds repeat across functions, fold them into one marker/blanket trait so signatures read `T: MyTrait` instead of a long `where` list.

```rust
trait Storable: Serialize + DeserializeOwned + Send + 'static {}
impl<T: Serialize + DeserializeOwned + Send + 'static> Storable for T {}
fn save<T: Storable>(value: &T) { /* ... */ } // not a 4-bound where clause everywhere
```

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

**Note on fan-out:** `std::sync::mpsc` is **multi-producer, single-consumer** — each event is delivered to exactly one receiver, so a plain `mpsc` channel models an event *queue* (one observer / worker pool), **not** broadcast-to-all-observers. For true Observer semantics (every observer sees every event) give each observer its own sender, or use a broadcast channel.

```rust
use std::sync::mpsc::{self, Sender};

#[derive(Clone, Debug)]
enum Event { PriceUpdate(f64), Trade { qty: u64 } }

// Subject keeps one Sender per registered observer → every observer gets every event.
struct Subject { observers: Vec<Sender<Event>> }
impl Subject {
    fn subscribe(&mut self) -> mpsc::Receiver<Event> {
        let (tx, rx) = mpsc::channel();
        self.observers.push(tx);
        rx
    }
    fn notify(&self, e: Event) {
        for o in &self.observers { let _ = o.send(e.clone()); } // dropped observers error → ignore
    }
}
```

For real broadcast pub/sub prefer `tokio::sync::broadcast` (async, every receiver sees every message) or the `crossbeam-channel` crate; `std::sync::mpsc` alone cannot fan out.

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

### Fold

**Intent:** Accumulate a result over a collection — the functional alternative to a mutable accumulator loop. For mapping an AST/recursive enum into a new structure, write per-variant folder functions instead of a Visitor.

```rust
let sum = (1..=100).fold(0, |acc, n| acc + n); // for a plain sum, `.sum()` is more idiomatic
// fold shines when transforming an AST/recursive enum into a new structure:
fn fold_expr(e: &Expr) -> Expr {
    match e {
        Expr::Num(n) => Expr::Num(*n),
        Expr::Add(a, b) => Expr::Add(Box::new(fold_expr(a)), Box::new(fold_expr(b))),
        Expr::Mul(a, b) => Expr::Mul(Box::new(fold_expr(a)), Box::new(fold_expr(b))),
    }
}
```

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
| Fold | `.fold()` / per-variant folders | Visitor-as-transform |

## DESIGN PRINCIPLES

Why-level guidance the patterns serve. In Rust these map onto traits, modules, and ownership.

- **SOLID** — *SRP*: one reason to change per type. *OCP*: extend via new trait impls, don't edit existing code. *LSP*: trait impls must honor the trait's contract. *ISP*: many small traits beat one fat trait (`Read`/`Write` not `ReadWrite`). *DIP*: depend on traits (abstractions), inject concretions.
- **Composition over inheritance (CRP)** — Rust has no inheritance; compose by embedding structs and delegating to traits. This is the default, not a workaround.
- **DRY** — every piece of knowledge has one authoritative representation; factor shared logic into functions/traits/generics.
- **KISS** — simplest design that works; avoid unnecessary generics, indirection, and premature abstraction. Pairs with **YAGNI** (don't build it until needed).
- **Law of Demeter** — talk to immediate collaborators, not their internals (`a.do_x()` not `a.b().c().do_x()`); supports encapsulation.
- **Encapsulation** — keep fields private, expose behavior through methods; modules gate visibility with `pub`.
- **Command-Query Separation (CQS)** — a method either returns data *or* mutates state, not both; mirrors `&self` (query) vs `&mut self` (command).
- **Design by Contract (DbC)** — state preconditions/postconditions/invariants; encode them in the type system (newtypes, typestate) where possible, `assert!`/`debug_assert!` otherwise.
- **Principle of Least Astonishment (POLA)** — behave the way users expect; follow std naming/trait conventions (`Default`, `From`, `Iterator`) so APIs feel familiar.
- **Single Choice** — exactly one module knows the exhaustive list of alternatives; centralize a closed set in one enum + `match` rather than scattering `if mode == ..` checks.
