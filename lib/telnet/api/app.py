"""FastAPI application setup."""

import sys
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from lib.telnet.api.routes import devices, health
from lib.telnet.config import load_config
from lib.telnet.logging import setup_logging
from lib.telnet.service import TelnetService

# Add lib to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))


def create_app() -> FastAPI:
    """Create FastAPI application.

    Returns
    -------
    FastAPI
        Configured FastAPI app
    """
    config = load_config()
    setup_logging(
        level=getattr(__import__("logging"), config.log_level),
        json_output=config.log_json,
        log_file=config.log_file,
    )

    app = FastAPI(
        title="Telnet Device Management API",
        description="REST API for managing telnet device connections",
        version="0.1.0",
    )

    # CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Include routers
    app.include_router(devices.router)
    app.include_router(health.router)

    # Create and set service instance
    service = TelnetService(config=config)
    devices.set_service(service)
    health.set_service(service)

    @app.on_event("startup")
    async def startup() -> None:
        """Startup event handler."""
        await service.start()

    @app.on_event("shutdown")
    async def shutdown() -> None:
        """Shutdown event handler."""
        await service.stop()

    return app


def main() -> None:
    """Main entry point for running the API server."""
    import uvicorn

    app = create_app()
    uvicorn.run(app, host="0.0.0.0", port=8000)


if __name__ == "__main__":
    main()

