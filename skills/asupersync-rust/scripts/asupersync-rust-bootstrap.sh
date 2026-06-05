#!/bin/bash
set -e

scenario="${1:-runtime}"

case "$scenario" in
  runtime)
    cat <<'JSON'
{"scenario":"runtime","cargo":"asupersync = { git = \"https://github.com/Dicklesworthstone/asupersync\" }","snippet":"use asupersync::runtime::RuntimeBuilder;\n\nfn main() -> Result<(), asupersync::Error> {\n    let runtime = RuntimeBuilder::current_thread().build()?;\n    runtime.block_on(async {\n        println!(\"running on Asupersync\");\n    });\n    Ok(())\n}\n"}
JSON
    ;;
  channel)
    cat <<'JSON'
{"scenario":"channel","cargo":"asupersync = { git = \"https://github.com/Dicklesworthstone/asupersync\" }","snippet":"use asupersync::{Outcome, channel::mpsc};\n\nasync fn send_one(cx: &asupersync::Cx) -> Result<(), String> {\n    let (tx, mut rx) = mpsc::channel::<String>(16);\n    let permit = tx.reserve(cx).await.map_err(|err| err.to_string())?;\n    match permit.send(\"hello\".to_owned()) {\n        Outcome::Ok(()) => {}\n        Outcome::Err(err) => return Err(err.to_string()),\n        Outcome::Cancelled(reason) => return Err(reason.to_string()),\n        Outcome::Panicked(payload) => return Err(payload.to_string()),\n    }\n    let value = rx.recv(cx).await.map_err(|err| err.to_string())?;\n    assert_eq!(value, \"hello\");\n    Ok(())\n}\n"}
JSON
    ;;
  http)
    cat <<'JSON'
{"scenario":"http","cargo":"asupersync = { git = \"https://github.com/Dicklesworthstone/asupersync\" }\nserde_json = \"1\"","snippet":"use asupersync::http::h1::listener::{Http1Listener, Http1ListenerConfig};\nuse asupersync::http::h1::server::{HostPolicy, Http1Config};\nuse asupersync::http::h1::types::{Request as H1Request, Response as H1Response, default_reason};\nuse asupersync::runtime::RuntimeBuilder;\nuse asupersync::web::extract::Request as WebRequest;\nuse asupersync::web::handler::FnHandler;\nuse asupersync::web::router::{Router, get};\nuse std::sync::Arc;\n\nfn health() -> &'static str { \"ok\" }\n\nfn to_web_request(req: H1Request) -> WebRequest {\n    let mut web = WebRequest::new(req.method.as_str(), req.uri);\n    for (name, value) in req.headers { web = web.with_header(name, value); }\n    web.with_body(req.body)\n}\n\nfn to_h1_response(resp: asupersync::web::response::Response) -> H1Response {\n    let status = resp.status.as_u16();\n    let mut out = H1Response::new(status, default_reason(status), resp.body.as_ref().to_vec());\n    for (name, value) in resp.headers { out = out.with_header(name, value); }\n    out\n}\n\nfn main() -> Result<(), Box<dyn std::error::Error>> {\n    let runtime = RuntimeBuilder::high_throughput().build()?;\n    let handle = runtime.handle();\n    runtime.block_on(async move {\n        let router = Arc::new(Router::new().route(\"/health\", get(FnHandler::new(health))));\n        let http_config = Http1Config::default()\n            .host_policy(HostPolicy::allow_list(vec![\"127.0.0.1\".to_owned(), \"localhost\".to_owned()]));\n        let listener = Http1Listener::bind_with_config(\n            \"127.0.0.1:8080\",\n            move |req| {\n                let router = Arc::clone(&router);\n                async move { to_h1_response(router.handle(to_web_request(req))) }\n            },\n            Http1ListenerConfig::default().http_config(http_config),\n        ).await?;\n        listener.run(&handle).await?;\n        Ok::<_, std::io::Error>(())\n    })?;\n    Ok(())\n}\n"}
JSON
    ;;
  test)
    cat <<'JSON'
{"scenario":"test","cargo":"asupersync = { git = \"https://github.com/Dicklesworthstone/asupersync\" }","snippet":"use asupersync::{LabConfig, LabRuntime};\n\n#[test]\nfn lab_reaches_quiescence() {\n    let mut lab = LabRuntime::new(LabConfig::new(42));\n    let report = lab.run_until_quiescent_with_report();\n    assert!(report.oracle_report.all_passed());\n    assert!(report.invariant_violations.is_empty());\n}\n"}
JSON
    ;;
  *)
    echo "Unknown scenario: $scenario" >&2
    echo "Usage: $0 [runtime|channel|http|test]" >&2
    exit 2
    ;;
esac
