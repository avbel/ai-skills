# BEHAVIORAL PATTERNS

## Strategy (Three Approaches)

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

## Command

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

## Observer (Channels)

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

## State — Enum State Machine

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

## Iterator (Built-in)

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

## Fold

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

## Template Method (Trait Default Methods)

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

## Chain of Responsibility

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

## Visitor (Enum + Match)

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
