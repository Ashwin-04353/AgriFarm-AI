from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from loguru import logger
import time, os
from .config import get_settings
from .auth.router import router as auth_router
from .routers.fields import router as fields_router
from .routers.analytics import router as analytics_router
from .routers.upload import router as upload_router
from .routers.alerts import router as alerts_router
from .routers.query import router as query_router

settings = get_settings()
os.makedirs(settings.upload_dir, exist_ok=True)

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[f"{settings.rate_limit_per_minute}/minute"]
)

app = FastAPI(
    title="AgriAI",
    version="1.0.0",
    docs_url="/docs" 
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins.split(","),
    allow_credentials=True,
    allow_methods=["GET","POST","PUT","DELETE"],
    allow_headers=["Authorization","Content-Type"]
)

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    ms = round((time.time()-start)*1000, 2)
    logger.info(f"{request.method} {request.url.path} "
                f"{response.status_code} {ms}ms")
    return response

@app.exception_handler(Exception)
async def global_error(request: Request, exc: Exception):
    logger.error(f"Unhandled: {exc}")
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "Internal server error"}
    )

app.include_router(auth_router)
app.include_router(fields_router)
app.include_router(analytics_router)
app.include_router(upload_router)
app.include_router(alerts_router)
app.include_router(query_router)

@app.get("/health")
def health():
    return {"status": "ok", "app": "AgriAI"}