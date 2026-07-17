# CREATIONAL PATTERNS

## Builder

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

## Factory (Functions + Traits)

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

## Singleton (OnceLock / LazyLock)

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
