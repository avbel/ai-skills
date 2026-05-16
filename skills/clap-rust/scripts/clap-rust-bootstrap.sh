#!/bin/bash
set -e

scenario="${1:-derive}"
cargo='clap = { version = "4.6", features = ["derive", "env", "wrap_help"] }'

case "$scenario" in
  derive)
    snippet='use std::path::PathBuf;
use clap::{Args, Parser};

#[derive(Debug, Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    #[command(flatten)]
    global: GlobalArgs,

    /// Optional name to operate on
    name: Option<String>,
}

#[derive(Debug, Args)]
struct GlobalArgs {
    /// Increase logging verbosity
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,

    /// Optional config file
    #[arg(short, long, value_name = "FILE")]
    config: Option<PathBuf>,
}

fn main() {
    let cli = Cli::parse();
    println!("{cli:#?}");
}'
    ;;
  builder)
    snippet='use clap::{Arg, ArgAction, Command, value_parser};

fn command() -> Command {
    Command::new("demo")
        .version(env!("CARGO_PKG_VERSION"))
        .about("Demo CLI")
        .arg(
            Arg::new("port")
                .long("port")
                .value_parser(value_parser!(u16).range(1..=65535))
                .default_value("8080"),
        )
        .arg(
            Arg::new("verbose")
                .short('\''v'\'')
                .long("verbose")
                .action(ArgAction::Count),
        )
}'
    ;;
  subcommand)
    snippet='use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(version, about, subcommand_required = true, arg_required_else_help = true)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Run the service
    Serve {
        #[arg(long, default_value_t = 8080)]
        port: u16,
    },
    /// Check configuration and exit
    Check,
}'
    ;;
  value-enum)
    snippet='use clap::{Parser, ValueEnum};

#[derive(Debug, Parser)]
struct Cli {
    #[arg(long, value_enum, default_value_t = Mode::Fast)]
    mode: Mode,
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, Ord, PartialOrd, ValueEnum)]
enum Mode {
    Fast,
    Slow,
}

impl std::fmt::Display for Mode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'"'"'_>) -> std::fmt::Result {
        let value = match self {
            Self::Fast => "fast",
            Self::Slow => "slow",
        };
        f.write_str(value)
    }
}'
    ;;
  test)
    snippet='use clap::{CommandFactory, Parser};

#[derive(Debug, Parser)]
struct Cli {
    #[arg(long, default_value_t = 8080)]
    port: u16,
}

#[test]
fn cli_shape_is_valid() {
    Cli::command().debug_assert();
}

#[test]
fn parses_port() {
    let cli = Cli::try_parse_from(["app", "--port", "9000"]).unwrap();
    assert_eq!(cli.port, 9000);
}'
    ;;
  *)
    echo "Usage: $0 [derive|builder|subcommand|value-enum|test]" >&2
    exit 2
    ;;
esac

SCENARIO="$scenario" CARGO="$cargo" SNIPPET="$snippet" python3 <<'PY'
import json
import os

print(json.dumps({
    "scenario": os.environ["SCENARIO"],
    "cargo": os.environ["CARGO"],
    "snippet": os.environ["SNIPPET"],
}, indent=2))
PY
