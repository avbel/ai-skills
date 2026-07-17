# RUST-SPECIFIC PATTERNS

## Typestate Pattern

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

## RAII / Drop

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
