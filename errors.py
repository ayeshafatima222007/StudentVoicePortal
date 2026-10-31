import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger(__name__)

# Default error code for each HTTP status
STATUS_CODES = {
    400: "BAD_REQUEST",
    401: "UNAUTHORIZED",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    405: "METHOD_NOT_ALLOWED",
    409: "CONFLICT",
    422: "VALIDATION_ERROR",
    500: "INTERNAL_ERROR",
}


class AppError(Exception):
    """Raise this anywhere in the API, e.g.
    raise AppError(404, "NOT_FOUND", "Complaint not found")
    """

    def __init__(self, status_code: int, code: str, message: str, fields: dict | None = None):
        self.status_code = status_code
        self.code = code
        self.message = message
        self.fields = fields or {}


def error_response(status_code: int, code: str, message: str, fields: dict | None = None):
    # The ONE shape every error uses
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message, "fields": fields or {}}},
    )


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError):
        return error_response(exc.status_code, exc.code, exc.message, exc.fields)

    @app.exception_handler(StarletteHTTPException)
    async def handle_http_error(request: Request, exc: StarletteHTTPException):
        code = STATUS_CODES.get(exc.status_code, "HTTP_ERROR")
        return error_response(exc.status_code, code, str(exc.detail))

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, exc: RequestValidationError):
        fields = {}
        for err in exc.errors():
            if err["type"] == "json_invalid":
                name, msg = "request", "Request body is not valid JSON"
            else:
                # loc looks like ("body", "email") -> field name is the last part
                name = ".".join(str(p) for p in err["loc"] if p not in ("body", "query", "path"))
                name, msg = name or "request", err["msg"]
            fields.setdefault(name, []).append(msg)
        return error_response(422, "VALIDATION_ERROR", "Validation failed", fields)

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, exc: Exception):
        logger.error("Unhandled error on %s %s", request.method, request.url.path, exc_info=exc)
        # Never leak internal details to the client
        return error_response(500, "INTERNAL_ERROR", "Something went wrong on the server")