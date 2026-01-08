"""Health check API routes."""

from fastapi import APIRouter, HTTPException

from lib.telnet.api.models import ServiceStatusResponse

router = APIRouter(prefix="/health", tags=["health"])

# Store service instance (set by app)
_service = None


def set_service(service) -> None:
    """Set the telnet service instance.

    Parameters
    ----------
    service
        TelnetService instance
    """
    global _service
    _service = service


@router.get("", response_model=dict)
async def health_check() -> dict:
    """Health check endpoint.

    Returns
    -------
    dict
        Health status
    """
    return {"status": "healthy", "service": "telnet"}


@router.get("/status", response_model=ServiceStatusResponse)
async def get_status() -> ServiceStatusResponse:
    """Get service status.

    Returns
    -------
    ServiceStatusResponse
        Service status
    """
    if not _service:
        raise HTTPException(status_code=503, detail="Service not available")

    try:
        status = await _service.get_status()
        return ServiceStatusResponse(**status)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e

