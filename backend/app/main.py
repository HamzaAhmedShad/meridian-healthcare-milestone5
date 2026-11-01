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
    """
    Log every HTTP request as a structured JSON record.
    Cloud Logging will pick up the `httpRequest` field automatically.
    Errors (status >= 500) are logged at ERROR severity so the
    log-based metric can filter on severity="ERROR".
    """
    start = time.perf_counter()
    response = await call_next(request)
    latency_ms = (time.perf_counter() - start) * 1000

    http_request = {
        "requestMethod": request.method,
        "requestUrl": str(request.url),
        "requestPath": request.url.path,
        "status": response.status_code,
        "latencyMs": round(latency_ms, 2),
        "userAgent": request.headers.get("user-agent", ""),
        "remoteIp": request.client.host if request.client else "",
    }

    level = logging.ERROR if response.status_code >= 500 else logging.INFO
    logger.log(
        level,
        f"{request.method} {request.url.path} → {response.status_code} ({latency_ms:.1f}ms)",
        extra={"http_request": http_request},
    )
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

@app.get("/api/test-error")
def trigger_error():
    """
    Intentionally raises HTTP 500.
    Use this during the M6 demo to show a JSON log entry and the
    corresponding spike in the log-based metric.
    """
    logger.error(
        "Intentional 500 error triggered for demo",
        extra={
            "http_request": {
                "requestMethod": "GET",
                "requestPath": "/api/test-error",
                "status": 500,
            }
        },
    )
    raise HTTPException(status_code=500, detail="Intentional 5xx error for Milestone 6 demo")
