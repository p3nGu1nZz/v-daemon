Mock MCP server for Copilot CLI testing.

Start: (from repo root)
  npm --prefix scripts/mock-mcp install
  npm --prefix scripts/mock-mcp start

Default port: 51823 (MOCK_MCP_PORT to override)

Admin endpoints:
  POST /_admin/load-scenario  {"name":"default"}
  POST /_admin/reset
  GET  /_admin/requests

Fixtures live in scripts/mock-mcp/fixtures and scenarios in scripts/mock-mcp/scenarios.
