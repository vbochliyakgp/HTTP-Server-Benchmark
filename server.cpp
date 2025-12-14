#include <iostream>
#include <string>
#include <sstream>
#include <map>
#include <thread>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <cstring>
#include <algorithm>
#include <cerrno>
#include <stdexcept>

class HTTPServer {
private:
    int server_fd;
    struct sockaddr_in address;
    int port = 3004;

    std::string urlDecode(const std::string& str) {
        std::string result;
        for (size_t i = 0; i < str.length(); ++i) {
            if (str[i] == '%' && i + 2 < str.length()) {
                int value;
                std::istringstream is(str.substr(i + 1, 2));
                if (is >> std::hex >> value) {
                    result += static_cast<char>(value);
                    i += 2;
                } else {
                    result += str[i];
                }
            } else if (str[i] == '+') {
                result += ' ';
            } else {
                result += str[i];
            }
        }
        return result;
    }

    std::map<std::string, std::string> parseQuery(const std::string& query) {
        std::map<std::string, std::string> params;
        std::istringstream iss(query);
        std::string pair;
        
        while (std::getline(iss, pair, '&')) {
            size_t pos = pair.find('=');
            if (pos != std::string::npos) {
                std::string key = urlDecode(pair.substr(0, pos));
                std::string value = urlDecode(pair.substr(pos + 1));
                params[key] = value;
            }
        }
        return params;
    }

    std::string makeResponse(int code, const std::string& body, const std::string& contentType) {
        std::string status = (code == 200) ? "OK" : "Not Found";
        std::ostringstream response;
        response << "HTTP/1.1 " << code << " " << status << "\r\n"
                 << "Content-Type: " << contentType << "\r\n"
                 << "Content-Length: " << body.length() << "\r\n"
                 << "Connection: close\r\n"
                 << "\r\n"
                 << body;
        return response.str();
    }

    // Helper function to read exactly N bytes (handles partial reads)
    bool readExact(int socket, void* buffer, size_t count) {
        char* buf = static_cast<char*>(buffer);
        size_t totalRead = 0;
        while (totalRead < count) {
            ssize_t n = read(socket, buf + totalRead, count - totalRead);
            if (n <= 0) {
                return false;  // Error or EOF
            }
            totalRead += n;
        }
        return true;
    }

    // Helper function to send all data (handles partial sends)
    bool sendAll(int socket, const void* buffer, size_t count) {
        const char* buf = static_cast<const char*>(buffer);
        size_t totalSent = 0;
        while (totalSent < count) {
            ssize_t n = send(socket, buf + totalSent, count - totalSent, 0);
            if (n <= 0) {
                return false;  // Error
            }
            totalSent += n;
        }
        return true;
    }

    void handleClient(int client_socket) {
        // Set socket options for better performance and timeout
        int flag = 1;
        setsockopt(client_socket, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));
        
        struct timeval timeout;
        timeout.tv_sec = 5;  // 5 second timeout
        timeout.tv_usec = 0;
        setsockopt(client_socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client_socket, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

        char buffer[8192] = {0};
        ssize_t valread = read(client_socket, buffer, 8191);
        
        if (valread <= 0) {
            close(client_socket);
            return;
        }

        std::string request(buffer, valread);
        std::istringstream iss(request);
        std::string method, path, version;
        iss >> method >> path >> version;

        // Parse path and query
        size_t queryPos = path.find('?');
        std::string route = path.substr(0, queryPos);
        std::string queryString = (queryPos != std::string::npos) ? path.substr(queryPos + 1) : "";

        // Read headers
        std::map<std::string, std::string> headers;
        std::string line;
        int contentLength = 0;
        while (std::getline(iss, line) && line != "\r" && !line.empty()) {
            size_t colonPos = line.find(':');
            if (colonPos != std::string::npos) {
                std::string key = line.substr(0, colonPos);
                std::string value = line.substr(colonPos + 1);
                // Trim whitespace
                value.erase(0, value.find_first_not_of(" \t\r\n"));
                value.erase(value.find_last_not_of(" \t\r\n") + 1);
                std::transform(key.begin(), key.end(), key.begin(), ::tolower);
                headers[key] = value;
                if (key == "content-length") {
                    try {
                        contentLength = std::stoi(value);
                        if (contentLength < 0 || contentLength > 1048576) {  // Max 1MB
                            contentLength = 0;
                        }
                    } catch (const std::exception&) {
                        contentLength = 0;
                    }
                }
            }
        }

        std::string response;

        if (method == "GET" && route == "/") {
            response = makeResponse(200, "Hello from C++!", "text/plain");
        }
        else if (method == "GET" && route == "/something") {
            auto query = parseQuery(queryString);
            if (query.find("json") != query.end() && query["json"] == "true") {
                std::ostringstream json;
                json << "{\"route\":\"/something\",\"query\":{";
                bool first = true;
                for (const auto& [k, v] : query) {
                    if (!first) json << ",";
                    json << "\"" << k << "\":\"" << v << "\"";
                    first = false;
                }
                json << "}}";
                response = makeResponse(200, json.str(), "application/json");
            } else {
                std::ostringstream text;
                text << "Route: /something, Query: {";
                bool first = true;
                for (const auto& [k, v] : query) {
                    if (!first) text << ", ";
                    text << k << ": " << v;
                    first = false;
                }
                text << "}";
                response = makeResponse(200, text.str(), "text/plain");
            }
        }
        else if (method == "POST" && route == "/something") {
            std::string body;
            if (contentLength > 0) {
                body.resize(contentLength);
                if (!readExact(client_socket, &body[0], contentLength)) {
                    // Failed to read body, send error response
                    response = makeResponse(400, "Bad Request", "text/plain");
                } else {
                    std::ostringstream json;
                    json << "{\"route\":\"/something\",\"body\":" << (body.empty() ? "{}" : body) << "}";
                    response = makeResponse(200, json.str(), "application/json");
                }
            } else {
                std::ostringstream json;
                json << "{\"route\":\"/something\",\"body\":{}}";
                response = makeResponse(200, json.str(), "application/json");
            }
        }
        else {
            response = makeResponse(404, "Not Found", "text/plain");
        }

        // Send response with error handling
        if (!sendAll(client_socket, response.c_str(), response.length())) {
            // Send failed, but connection will be closed anyway
        }
        close(client_socket);
    }

public:
    HTTPServer() {
        server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd == 0) {
            std::cerr << "Socket creation failed\n";
            exit(1);
        }

        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        
        // Set TCP_NODELAY for lower latency
        setsockopt(server_fd, IPPROTO_TCP, TCP_NODELAY, &opt, sizeof(opt));

        address.sin_family = AF_INET;
        address.sin_addr.s_addr = INADDR_ANY;
        address.sin_port = htons(port);

        if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
            std::cerr << "Bind failed\n";
            exit(1);
        }

        if (listen(server_fd, 10) < 0) {
            std::cerr << "Listen failed\n";
            exit(1);
        }

        std::cout << "C++ server running on :" << port << std::endl;
    }

    void run() {
        while (true) {
            int addrlen = sizeof(address);
            int client_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
            
            if (client_socket < 0) {
                continue;
            }

            std::thread(&HTTPServer::handleClient, this, client_socket).detach();
        }
    }
};

int main() {
    HTTPServer server;
    server.run();
    return 0;
}

