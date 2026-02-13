package main

import (
"encoding/json"
"log"
"net/http"
"os"
"path/filepath"
"sync"
"time"
)

type Match struct {
Type  string `json:"type,omitempty"`
Model string `json:"model,omitempty"`
}

type Mapping struct {
Match    Match  `json:"match"`
Response string `json:"response"`
}

type Scenario struct {
Name     string    `json:"name"`
Mappings []Mapping `json:"mappings"`
}

var (
scenarioMu       sync.RWMutex
scenario         Scenario
recordedRequests []map[string]interface{}
recordedMu       sync.Mutex
fixturesDir      string
scenariosDir     string
)

func loadScenario(name string) Scenario {
p := filepath.Join(scenariosDir, name+".json")
var s Scenario
b, err := os.ReadFile(p)
if err != nil {
return s
}
_ = json.Unmarshal(b, &s)
return s
}

func readResponse(rel string) (interface{}, error) {
p := filepath.Join(fixturesDir, rel)
b, err := os.ReadFile(p)
if err != nil {
return nil, err
}
var v interface{}
if err := json.Unmarshal(b, &v); err != nil {
return nil, err
}
return v, nil
}

func matchMapping(body map[string]interface{}) *Mapping {
scenarioMu.RLock()
defer scenarioMu.RUnlock()
for _, m := range scenario.Mappings {
ok := true
if m.Match.Type != "" {
if t, _ := body["type"].(string); t != m.Match.Type {
ok = false
}
}
if m.Match.Model != "" {
if md, _ := body["model"].(string); md != m.Match.Model {
ok = false
}
}
if ok {
return &m
}
}
return nil
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
w.Header().Set("Content-Type", "application/json")
json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func handleModels(w http.ResponseWriter, r *http.Request) {
path := filepath.Join(fixturesDir, "models.json")
if _, err := os.Stat(path); err == nil {
http.ServeFile(w, r, path)
return
}
w.Header().Set("Content-Type", "application/json")
json.NewEncoder(w).Encode(map[string][]interface{}{"models": {}})
}

func handleQuery(w http.ResponseWriter, r *http.Request) {
var body map[string]interface{}
dec := json.NewDecoder(r.Body)
if err := dec.Decode(&body); err != nil {
http.Error(w, "invalid json body", http.StatusBadRequest)
return
}
recordedMu.Lock()
recordedRequests = append(recordedRequests, map[string]interface{}{
"time": time.Now().UTC().Format(time.RFC3339),
"body": body,
})
recordedMu.Unlock()

if m := matchMapping(body); m != nil {
if resp, err := readResponse(m.Response); err == nil {
w.Header().Set("Content-Type", "application/json")
json.NewEncoder(w).Encode(resp)
return
}
}
w.Header().Set("Content-Type", "application/json")
w.WriteHeader(http.StatusNotFound)
json.NewEncoder(w).Encode(map[string]string{"error": "no mapping found"})
}

func handleAdminLoadScenario(w http.ResponseWriter, r *http.Request) {
var body map[string]interface{}
dec := json.NewDecoder(r.Body)
if err := dec.Decode(&body); err != nil {
http.Error(w, "invalid json body", http.StatusBadRequest)
return
}
name, _ := body["name"].(string)
if name == "" {
http.Error(w, "missing name", http.StatusBadRequest)
return
}
s := loadScenario(name)
scenarioMu.Lock()
scenario = s
scenarioMu.Unlock()
recordedMu.Lock()
recordedRequests = nil
recordedMu.Unlock()
json.NewEncoder(w).Encode(map[string]string{"loaded": name})
}

func handleAdminReset(w http.ResponseWriter, r *http.Request) {
recordedMu.Lock()
recordedRequests = nil
recordedMu.Unlock()
json.NewEncoder(w).Encode(map[string]bool{"reset": true})
}

func handleAdminRequests(w http.ResponseWriter, r *http.Request) {
recordedMu.Lock()
reqs := recordedRequests
recordedMu.Unlock()
w.Header().Set("Content-Type", "application/json")
json.NewEncoder(w).Encode(map[string]interface{}{"requests": reqs})
}

func main() {
port := os.Getenv("MOCK_MCP_PORT")
if port == "" {
port = "51823"
}
fixturesDir = "fixtures"
scenariosDir = "scenarios"
// Preload default scenario if present
scenario = loadScenario("default")

http.HandleFunc("/health", handleHealth)
http.HandleFunc("/models", handleModels)
http.HandleFunc("/query", handleQuery)
http.HandleFunc("/_admin/load-scenario", handleAdminLoadScenario)
http.HandleFunc("/_admin/reset", handleAdminReset)
http.HandleFunc("/_admin/requests", handleAdminRequests)

addr := ":" + port
log.Printf("mock-mcp listening on %s", addr)
if err := http.ListenAndServe(addr, nil); err != nil {
log.Fatal(err)
}
}
