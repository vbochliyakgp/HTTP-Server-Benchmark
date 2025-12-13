use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::collections::HashMap;

fn main() {
    let listener = TcpListener::bind("0.0.0.0:3003").unwrap();
    println!("Rust server running on :3003");

    for stream in listener.incoming().flatten() {
        let mut reader = BufReader::new(&stream);
        let mut request_line = String::new();
        reader.read_line(&mut request_line).unwrap();

        let parts: Vec<&str> = request_line.trim().split_whitespace().collect();
        let (method, full_path) = (parts[0], parts[1]);
        let (path, query_string) = full_path.split_once('?').unwrap_or((full_path, ""));

        let mut headers = HashMap::new();
        loop {
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            if line.trim().is_empty() { break; }
            if let Some((k, v)) = line.trim().split_once(": ") {
                headers.insert(k.to_lowercase(), v.to_string());
            }
        }

        let response = match (method, path) {
            ("GET", "/") => response(200, "Hello from Rust!", "text/plain"),
            ("GET", "/something") => {
                let query: HashMap<_, _> = query_string.split('&')
                    .filter_map(|p| p.split_once('='))
                    .collect();
                let is_json = query.get("json") == Some(&"true");
                if is_json {
                    let json = format!(r#"{{"route":"{}","query":{:?}}}"#, path, query);
                    response(200, &json, "application/json")
                } else {
                    response(200, &format!("Route: {}, Query: {:?}", path, query), "text/plain")
                }
            }
            ("POST", "/something") => {
                let len: usize = headers.get("content-length").and_then(|v| v.parse().ok()).unwrap_or(0);
                let mut body = vec![0u8; len];
                reader.read_exact(&mut body).unwrap();
                let body_str = String::from_utf8_lossy(&body);
                let json = format!(r#"{{"route":"{}","body":{}}}"#, path, body_str);
                response(200, &json, "application/json")
            }
            _ => response(404, "Not Found", "text/plain"),
        };

        let mut stream = stream;
        stream.write_all(response.as_bytes()).unwrap();
    }
}

fn response(code: u16, body: &str, content_type: &str) -> String {
    let status = if code == 200 { "OK" } else { "Not Found" };
    format!("HTTP/1.1 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\n\r\n{}", 
            code, status, content_type, body.len(), body)
}

