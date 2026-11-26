"""aws-mcp MCP gateway (instance 00).

Single MCP endpoint for Copilot Studio: https://clade.dev.lilly.cn/mcp
  - The ALB (tg-00, jwt-validation) has already verified the Entra ID access token
    (signature, iss, exp, aud, scp=mcp.access) before a request reaches this container.
  - This gateway merges the tools of the two internal MCP servers and forwards calls
    through ECS Service Connect:
        aws_api_*  ->  MCP_BACKEND_AWS_API_URL  (aws-api MCP, read-only)
        aws_doc_*  ->  MCP_BACKEND_AWS_DOC_URL  (aws-documentation MCP)
  - The token is decoded (not verified) only to write the caller into the audit log.
    The gateway must stay reachable only through the ALB (security group gw-d-sg-01).
"""
import base64
import json
import logging
import os

from fastmcp.server import create_proxy
from fastmcp.server.dependencies import get_http_headers
from fastmcp.server.middleware import Middleware, MiddlewareContext
from starlette.requests import Request
from starlette.responses import PlainTextResponse

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(message)s")
log = logging.getLogger("mcp-gateway")

BACKENDS = {
    "aws_api": os.environ["MCP_BACKEND_AWS_API_URL"],
    "aws_doc": os.environ["MCP_BACKEND_AWS_DOC_URL"],
}


def _caller() -> str:
    """Return the signed-in user from the (already validated) bearer token."""
    try:
        auth = get_http_headers(include_all=True).get("authorization", "")
        if not auth.lower().startswith("bearer "):
            return "unknown"
        payload = auth.split(" ", 1)[1].split(".")[1]
        payload += "=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
        return claims.get("preferred_username") or claims.get("upn") or claims.get("oid", "unknown")
    except Exception:  # never fail a call because of audit logging
        return "unknown"


class AuditMiddleware(Middleware):
    async def on_call_tool(self, context: MiddlewareContext, call_next):
        log.info(json.dumps({"event": "tool_call", "user": _caller(), "tool": context.message.name}))
        return await call_next(context)


gateway = create_proxy(
    {"mcpServers": {name: {"url": url, "transport": "http"} for name, url in BACKENDS.items()}},
    name="AWS Cloud Resource Search",
)
gateway.add_middleware(AuditMiddleware())


@gateway.custom_route("/healthz", methods=["GET"])
async def healthz(_: Request) -> PlainTextResponse:
    return PlainTextResponse("ok")


if __name__ == "__main__":
    gateway.run(
        transport="http",
        host="0.0.0.0",
        port=int(os.getenv("MCP_PORT", "8000")),
        path="/mcp",
        stateless_http=True,
    )
