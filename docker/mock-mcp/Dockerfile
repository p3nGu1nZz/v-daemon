# Build a static Go binary and produce a small runtime image
FROM golang:1.21-alpine AS builder
WORKDIR /src/cmd/mock-mcp
COPY cmd/mock-mcp ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/mock-mcp .

FROM alpine:3.18
RUN addgroup -S mock && adduser -S mock -G mock || true
COPY --from=builder /out/mock-mcp /usr/local/bin/mock-mcp
COPY cmd/mock-mcp/fixtures /app/fixtures
COPY cmd/mock-mcp/scenarios /app/scenarios
WORKDIR /app
EXPOSE 51823
USER mock
ENTRYPOINT ["/usr/local/bin/mock-mcp"]
