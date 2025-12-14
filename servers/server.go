package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		fmt.Fprint(w, "Hello from Go!")
	})

	http.HandleFunc("/something", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "GET" {
			query := make(map[string]string)
			for k, v := range r.URL.Query() {
				query[k] = v[0]
			}
			result := map[string]any{"route": r.URL.Path, "query": query}
			if r.URL.Query().Get("json") == "true" {
				w.Header().Set("Content-Type", "application/json")
				json.NewEncoder(w).Encode(result)
			} else {
				fmt.Fprintf(w, "Route: %s, Query: %v", r.URL.Path, query)
			}
		} else if r.Method == "POST" {
			body, _ := io.ReadAll(r.Body)
			w.Header().Set("Content-Type", "application/json")
			var parsed any
			json.Unmarshal(body, &parsed)
			result := map[string]any{"route": r.URL.Path, "body": parsed}
			json.NewEncoder(w).Encode(result)
		}
	})

	fmt.Println("Go server running on :3002")
	http.ListenAndServe(":3002", nil)
}
