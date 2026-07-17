# STRUCTURAL PATTERNS

## Newtype

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

## Adapter (Trait Impl on Wrapper)

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

## Decorator (Generic Wrapping)

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

## Facade

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

## Composite (Recursive Enum)

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

## Compose Structs (Borrow Checker Pattern)

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

## Other Rust structural guidance

- **Prefer small crates.** Split functionality into focused crates: faster parallel compilation, clear semver boundaries, and reuse. A crate should do one thing well.
- **Contain `unsafe` in small modules.** Wrap unsafe code in a minimal, well-documented module/abstraction that exposes a safe API and upholds its invariants internally — so reviewers audit a small surface, not the whole crate. Every `unsafe` block carries a `// SAFETY:` note.
- **Custom traits to avoid complex type bounds.** When several generic bounds repeat across functions, fold them into one marker/blanket trait so signatures read `T: MyTrait` instead of a long `where` list.

```rust
trait Storable: Serialize + DeserializeOwned + Send + 'static {}
impl<T: Serialize + DeserializeOwned + Send + 'static> Storable for T {}
fn save<T: Storable>(value: &T) { /* ... */ } // not a 4-bound where clause everywhere
```
