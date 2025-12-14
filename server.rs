use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::collections::HashMap;
use std::sync::{mpsc, Arc, Mutex};
use std::thread;

// Thread pool for handling connections
struct ThreadPool {
    workers: Vec<thread::JoinHandle<()>>,
    sender: Option<mpsc::Sender<TcpStream>>,
}

impl ThreadPool {
    fn new(size: usize) -> ThreadPool {
        let (sender, receiver) = mpsc::channel();
        let receiver = Arc::new(Mutex::new(receiver));
        
        let mut workers = Vec::with_capacity(size);
        
        for _ in 0..size {
            let receiver = Arc::clone(&receiver);
            let worker = thread::spawn(move || loop {
                let stream = {
                    let receiver = receiver.lock().unwrap();
                    receiver.recv()
                };
                
                match stream {
                    Ok(stream) => handle_client(stream),
                    Err(_) => break,  // Channel closed, exit worker
                }
            });
            workers.push(worker);
        }
        
        ThreadPool {
            workers,
            sender: Some(sender),
        }
    }
    
    fn execute(&self, stream: TcpStream) {
        if let Some(ref sender) = self.sender {
            sender.send(stream).unwrap_or_else(|_| {
                eprintln!("Failed to send stream to worker");
            });
        }
    }
}

impl Drop for ThreadPool {
    fn drop(&mut self) {
        drop(self.sender.take());
        for worker in self.workers.drain(..) {
            let _ = worker.join();
        }
    }
}

fn main() {
    let listener = TcpListener::bind("0.0.0.0:3003").unwrap();
    listener.set_nonblocking(false).unwrap();
    println!("Rust server running on :3003");
    
    // Create thread pool with fixed number of worker threads
    // Using 8 threads as a good default (can handle many concurrent connections)
    let pool = ThreadPool::new(8);
    
    for stream in listener.incoming().flatten() {
        pool.execute(stream);
    }
}

fn handle_client(stream: TcpStream) {
    // Set TCP options for performance
    stream.set_nodelay(true).ok();
    
    let mut reader = BufReader::new(&stream);
    let mut request_line = String::new();
    
    if reader.read_line(&mut request_line).is_err() || request_line.is_empty() {
        return;
    }

    let parts: Vec<&str> = request_line.trim().split_whitespace().collect();
    if parts.len() < 2 {
        return;
    }
    
    let (method, full_path) = (parts[0], parts[1]);
    let (path, query_string) = full_path.split_once('?').unwrap_or((full_path, ""));

    // Read headers
    let mut content_length: usize = 0;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).is_err() || line.trim().is_empty() {
            break;
        }
        if let Some((k, v)) = line.trim().split_once(": ") {
            if k.eq_ignore_ascii_case("content-length") {
                content_length = v.parse().unwrap_or(0);
            }
        }
    }

    let response = match (method, path) {
        ("GET", "/") => make_response(200, "Hello from Rust!", "text/plain"),
        
        ("GET", "/something") => {
            let query: HashMap<_, _> = query_string
                .split('&')
                .filter(|s| !s.is_empty())
                .filter_map(|p| p.split_once('='))
                .collect();
            
            if query.get("json") == Some(&"true") {
                let pairs: Vec<String> = query.iter()
                    .map(|(k, v)| format!(r#""{}":"{}""#, k, v))
                    .collect();
                let json = format!(r#"{{"route":"{}","query":{{{}}}}}"#, path, pairs.join(","));
                make_response(200, &json, "application/json")
            } else {
                let text = format!("Route: {}, Query: {:?}", path, query);
                make_response(200, &text, "text/plain")
            }
        }
        
        ("POST", "/something") => {
            let mut body = vec![0u8; content_length];
            if content_length > 0 && reader.read_exact(&mut body).is_ok() {
                let body_str = String::from_utf8_lossy(&body);
                let json = format!(r#"{{"route":"{}","body":{}}}"#, path, body_str);
                make_response(200, &json, "application/json")
            } else {
                make_response(200, r#"{"route":"/something","body":{}}"#, "application/json")
            }
        }
        
        _ => make_response(404, "Not Found", "text/plain"),
    };

    let mut stream = stream;
    let _ = stream.write_all(response.as_bytes());
    let _ = stream.flush();
}

fn make_response(code: u16, body: &str, content_type: &str) -> String {
    let status = match code {
        200 => "OK",
        404 => "Not Found",
        _ => "Error",
    };
    format!(
        "HTTP/1.1 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        code, status, content_type, body.len(), body
    )
}
