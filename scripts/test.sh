#!/usr/bin/env sh
set -eu

IMAGE="vdaemon/mock-mcp:local"
CONTAINER_NAME="vdaemon-mock-mcp-local"
DOCKERFILE_DIR="docker/mock-mcp"

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required to run tests with mock MCP" >&2
  exit 2
fi

echo "Building mock-mcp docker image..."
docker build -t "$IMAGE" -f "$DOCKERFILE_DIR/Dockerfile" .

# stop/remove any previous container
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "Starting mock-mcp container..."
docker run -d --name "$CONTAINER_NAME" -p 51823:51823 "$IMAGE"

# wait for /health
for i in $(seq 1 30); do
  if curl -sS http://localhost:51823/health >/dev/null 2>&1; then
    echo "mock-mcp healthy"
    break
  fi
  echo "waiting for mock to become healthy... ($i)"
  sleep 1
done

# run a simple query against the mock server
RESP=$(curl -sS -X POST -H "Content-Type: application/json" -d '{"type":"completion","model":"claude"}' http://localhost:51823/query || true)

if echo "$RESP" | grep -q "Hello from mock MCP"; then
  echo "Mock MCP responded as expected"
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 0
else
  echo "Mock MCP did not respond as expected. Response:" >&2
  echo "$RESP" >&2
  docker logs "$CONTAINER_NAME" || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 3
fi
