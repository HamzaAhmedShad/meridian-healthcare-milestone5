import hmac
import uuid
import json
import logging
import os
import sys
import time

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from .database import init_db, engine
from .ml.predictor import get_predictor
from .routers import dashboard, jobs, predict, upload

# ============================================================
# STRUCTURED JSON LOGGING
# ============================================================

class JSONFormatter(logging.Formatter):
    """Emit one JSON object per log line — Cloud Logging parses these natively."""

    def format(self, record: logging.LogRecord) -> str:
        log: dict = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "time": self.formatTime(record, self.datefmt),
        }
        # Attach httpRequest field so Cloud Logging auto-populates the
        # httpRequest structured field and the log-based metric can filter on it.
        log["event"] = getattr(record, "event", "application")
        log["version"] = os.getenv("APP_VERSION", "development")
        if hasattr(record, "request_id"):
            log["request_id"] = record.request_id
        if hasattr(record, "request_path"):
            log["path"] = record.request_path
        if hasattr(record, "http_request"):
            log["httpRequest"] = record.http_request
        if record.exc_info:
            log["exception"] = self.formatException(record.exc_info)
        return json.dumps(log)


def _configure_logging() -> logging.Logger:
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    # Remove any default handlers (uvicorn adds its own)
    root.handlers.clear()
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    root.addHandler(handler)
    return logging.getLogger("healthcare_api")


logger = _configure_logging()

# ============================================================
# FASTAPI APP
# ============================================================

app = FastAPI(
    title="Healthcare Cost Prediction & Resource Planning API",
    description=(
        "Predicts per-patient healthcare cost from Medicare-claims-style "
        "features, supports single and bulk (async) scoring, and powers "
        "the resource-planning dashboard."
    ),
    version="1.0.0",
)

cors_origins = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ORIGINS",
        "http://127.0.0.1:5500,http://localhost:5500",
    ).split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================
# HTTP REQUEST LOGGING MIDDLEWARE
# ============================================================

@app.middleware("http")
async def log_requests(request: Request, call_next):
    started = time.perf_counter()
    request_id = uuid.uuid4().hex

    try:
        response = await call_next(request)
    except Exception:
        response = JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"},
        )

    elapsed = time.perf_counter() - started
    route = request.scope.get("route")
    route_path = getattr(route, "path", "<unmatched>")
    status = response.status_code

    logger.log(
        logging.ERROR if status >= 500 else
        logging.WARNING if status >= 400 else logging.INFO,
        f"{request.method} {route_path} -> {status}",
        extra={
            "event": "http_request",
            "request_id": request_id,
            "request_path": route_path,
            "http_request": {
                "requestMethod": request.method,
                "status": status,
                "latency": f"{elapsed:.6f}s",
            },
        },
    )

    response.headers["X-Request-ID"] = request_id
    return response


# ============================================================
# ROUTERS
# ============================================================

app.include_router(predict.router)
app.include_router(upload.router)
app.include_router(jobs.router)
app.include_router(dashboard.router)

# ============================================================
# STARTUP
# ============================================================

@app.on_event("startup")
def on_startup():
    init_db()
    get_predictor()  # trains/loads the model once at boot so first request isn't slow
    logger.info("Healthcare API started", extra={"http_request": {}})

# ============================================================
# HEALTH ENDPOINTS
# ============================================================

@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/health/live")
def liveness():
    return {"status": "alive"}


@app.get("/api/health/ready", include_in_schema=False)
@app.get("/health/ready")
def readiness():
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return {"status": "ready", "database": "connected"}
    except Exception:
        raise HTTPException(
            status_code=503,
            detail="Database connection unavailable",
        )

# ============================================================
# ROOT
# ============================================================

@app.get("/")
def root():
    return {
        "message": "Healthcare Cost Prediction API is running.",
        "docs": "/docs",
    }

# ============================================================
# TEST ERROR ENDPOINT (used in Milestone 6 demo to trigger 5xx)
# ============================================================

@app.get("/api/test-error", include_in_schema=False)
def trigger_error(request: Request):
    expected = os.getenv("DEMO_ERROR_TOKEN", "")
    supplied = request.headers.get("X-Demo-Token", "")

    if not expected or not supplied or not hmac.compare_digest(
        supplied.encode("utf-8"), expected.encode("utf-8")
    ):
        raise HTTPException(status_code=404, detail="Not found")

    # Request middleware writes the single counted error log.
    raise HTTPException(
        status_code=500,
        detail="Controlled Milestone 6 demonstration error",
    )



@app.get("/api/version")
def release_version():
    return {
        "service": "healthcare-api",
        "commit": os.getenv("APP_VERSION", "development"),
    }
