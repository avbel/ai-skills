---
name: dotenvy-rust
description: Use when loading environment variables from .env files in Rust with dotenvy — dotenv, from_path, from_filename, override modes, iteration, and error handling. The well-maintained fork of dotenv.
---

# Dotenvy Rust

Use these conventions for loading environment variables from `.env` files with [`dotenvy`](https://github.com/allan2/dotenvy). Dotenvy is a well-maintained fork of `dotenv` that loads `.env` files into the process environment.

## Source Baseline

- Prefer released docs from `docs.rs/dotenvy`, crates.io, and the matching GitHub release.
- Current stable: `dotenvy 0.15.7`.
- This is the successor to the abandoned `dotenv` crate. Use `dotenvy` instead.
- MSRV: 1.56.1.

## Cargo.toml

```toml
[dependencies]
dotenvy = "0.15"
```

No features to enable. The crate works as-is.

## Basic Usage

### `dotenv()` — Load from Current or Parent Directories

This is the most common usage. It searches for `.env` starting from the current directory and walking up parent directories.

```rust
use dotenvy::dotenv;

fn main() {
    dotenv().ok(); // .ok() — don't fail if .env doesn't exist
    // Now env::var("DATABASE_URL") will find values from .env
    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
}
```

- `dotenv()` returns `Result<()>` — use `.ok()` if `.env` is optional.
- Values from `.env` do **not** override existing environment variables by default.

### Import Behavior

```rust
use dotenvy::dotenv;     // The main loading function
```

## Loading Functions

| Function | Behavior |
|----------|----------|
| `dotenv()` | Load `.env` from cwd and parents. Does NOT override existing vars. |
| `dotenv_override()` | Load `.env` from cwd and parents. **Overrides** existing vars. |
| `from_path(path)` | Load from a specific file path. Does NOT override. |
| `from_path_override(path)` | Load from a specific path. **Overrides** existing vars. |
| `from_filename(name)` | Load a file by name (e.g., `.env.local`) from cwd and parents. Does NOT override. |
| `from_filename_override(name)` | Same, but **overrides** existing vars. |
| `from_read(reader)` | Load from any `Read` impl. Does NOT override. |
| `from_read_override(reader)` | Load from `Read`. **Overrides** existing vars. |

```rust
use dotenvy::{dotenv, dotenv_override, from_path, from_filename};

// Standard: load .env, existing env vars take priority
dotenv().ok();

// Override: .env values replace existing env vars
dotenv_override().ok();

// Load a specific file
from_path("/etc/myapp/config.env").ok();

// Load .env.production instead of .env
from_filename(".env.production").ok();

// Load .env.local and override existing vars
from_filename_override(".env.local").ok();

// Load from an in-memory reader
use std::io::Cursor;
let data = Cursor::new("KEY=value\n");
from_read(data).ok();
```

## Iteration — Iterate Over Variables

```rust
use dotenvy::{dotenv_iter, from_filename_iter};

// Iterate over all key-value pairs from .env
for item in dotenv_iter()? {
    let (key, value) = item?;
    println!("{key}={value}");
}

// Iterate from a specific file
for item in from_filename_iter(".env.production")? {
    let (key, value) = item?;
    println!("{key}={value}");
}
```

- These return `Iter` which yields `Result<(String, String), Error>`.
- Useful for loading .env data into a `HashMap` instead of the environment.

## Accessing Variables

After loading, use `std::env` to access values:

```rust
use std::env;

// Require a variable (panics if missing)
let db_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");

// Optional variable
let timeout: u64 = env::var("TIMEOUT")
    .ok()
    .and_then(|v| v.parse().ok())
    .unwrap_or(30);

// Variable with default
let port: u16 = env::var("PORT")
    .ok()
    .and_then(|v| v.parse().ok())
    .unwrap_or(3000);
```

## .env File Format

```env
# Comments
DATABASE_URL=postgres://user:pass@localhost:5432/mydb

# Quoted values (quotes are stripped)
MESSAGE="Hello World"

# Single quotes (also stripped)
GREETING='Hi there'

# Multi-line values (double-quoted only)
PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----"

# Unquoted values
PORT=3000

# Empty value
OPTIONAL=

# Variable substitution (NOT supported — use shell expansion instead)
# HOST=localhost   # This is just a literal string
# PREFIX=$HOST:8080  # NOT expanded, stored as-is

# Inline comments (NOT supported without whitespace)
# URL=http://example.com  # This is part of the value!
# Use this instead:
URL=http://example.com
```

Important format notes:
- **Variable substitution** (`$VAR`) is **not** supported. Values are stored literally.
- **Inline comments** require a space separator: `KEY=value # comment` → value is `value # comment`. Avoid inline comments.
- Both single and double quotes are stripped from values.
- Multi-line values require double quotes.
- Blank lines are ignored.
- Lines starting with `#` are comments.

## Typical Application Setup

```rust
use dotenvy::dotenv;
use std::env;

fn main() {
    // Load .env file (use .ok() for optional)
    dotenv().ok();

    // Or load environment-specific file
    let env_name = env::var("APP_ENV").unwrap_or_else(|_| "development".into());
    match env_name.as_str() {
        "production" => dotenvy::from_filename(".env.production").ok(),
        "test" => dotenvy::from_filename(".env.test").ok(),
        _ => dotenv().ok(),
    };

    let db_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(3000);

    // ... start application
}
```

## Error Handling

```rust
use dotenvy::{dotenv, from_path};

// Pattern 1: Don't fail if .env is missing (development only)
dotenv().ok();

// Pattern 2: Require .env (fail fast)
dotenv().expect("Failed to load .env file");

// Pattern 3: Handle specific errors
match from_path("/etc/app/config.env") {
    Ok(()) => println!("Config loaded"),
    Err(e) => eprintln!("Config error: {e}"),
}
```

`dotenvy::Error` variants:
- `.env` file not found
- `.env` file has invalid Unicode
- I/O errors reading the file
- Duplicate keys (informational, not an error)

## Testing with dotenvy

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use dotenvy::from_path;
    use std::path::Path;

    // Load a test-specific env file
    fn setup() {
        from_path(Path::new(".env.test")).ok();
    }

    #[test]
    fn test_database_url() {
        setup();
        let url = std::env::var("DATABASE_URL");
        assert!(url.is_ok());
    }
}
```

Note: Environment variables are process-global. In tests, loading `.env` in one test affects all others. Use `from_read` with isolated data if needed.

## Variable Substitution — Not Built-In

Dotenvy does **not** support variable substitution (`$VAR`). If you need it:

```rust
// Manual expansion after loading
fn expand_vars(value: &str) -> String {
    std::env::var(value.strip_prefix('$').unwrap_or(value))
        .unwrap_or_else(|_| value.to_string())
}
```

Consider using `shellexpand` or `envsubst` crates for complex substitution needs.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Using `dotenv` crate instead of `dotenvy` | Replace `dotenv` with `dotenvy` in `Cargo.toml` — old crate is unmaintained |
| Calling `dotenv()` after `env::var()` | Load `.env` **first**, before any `env::var()` calls |
| `.env` overriding production env vars | Use `dotenv()` (not `dotenv_override()`) in production |
| Inline comments in `.env` | Avoid inline comments; they become part of the value |
| Variable substitution not working | `dotenvy` doesn't support `$VAR`; use a substitution crate |
| Missing `.env` file causing panic | Use `.ok()` to make `.env` optional |
| Duplicate keys in `.env` | Last occurrence wins; consider enabling `.env` validation |
| `.env` in version control | Add `.env` to `.gitignore`; commit `.env.example` with defaults |

## Security

- **Never commit `.env` files** containing secrets. Add `.env` to `.gitignore`.
- Do commit `.env.example` or `.env.template` with placeholder values.
- In production, prefer real environment variables over `.env` files.
- `dotenv_override()` replaces existing env vars — use cautiously in production.
- For Docker, use `--env-file` or `docker-compose env_file` instead of copying `.env` into the image.

## Review Checklist

- [ ] `dotenvy` used instead of `dotenv` (the old crate is unmaintained).
- [ ] `.env` loaded before any `env::var()` calls (typically at the start of `main`).
- [ ] `.ok()` used for optional `.env` files; `.expect()` or `?` for required configs.
- [ ] No inline comments in `.env` files (they become part of the value).
- [ ] `.env` added to `.gitignore`; `.env.example` committed with safe defaults.
- [ ] `dotenv_override()` avoided in production (prefer env vars set by the orchestrator).
- [ ] Environment-specific config loaded with `from_filename()` (e.g., `.env.production`).