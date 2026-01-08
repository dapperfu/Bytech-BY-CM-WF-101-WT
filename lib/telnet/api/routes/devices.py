"""Device management API routes."""

from fastapi import APIRouter, HTTPException

from lib.telnet.api.models import (
    CommandExecuteRequest,
    CommandExecuteResponse,
    DeviceConnectRequest,
    DeviceStatusResponse,
)
from lib.telnet.exceptions import ConnectionError, TelnetError

router = APIRouter(prefix="/devices", tags=["devices"])


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


@router.post("/{ip}/connect", response_model=dict)
async def connect_device(ip: str, request: DeviceConnectRequest) -> dict:
    """Connect to a device.

    Parameters
    ----------
    ip : str
        Device IP address
    request : DeviceConnectRequest
        Connection parameters

    Returns
    -------
    dict
        Connection result
    """
    if not _service:
        raise HTTPException(status_code=503, detail="Service not available")

    try:
        await _service.connect_device(
            host=ip,
            port=request.port,
            username=request.username,
            password=request.password,
            timeout=request.timeout,
            profile=request.profile,
        )
        return {"host": ip, "status": "connected", "success": True}
    except TelnetError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.post("/{ip}/execute", response_model=CommandExecuteResponse)
async def execute_command(ip: str, request: CommandExecuteRequest) -> CommandExecuteResponse:
    """Execute a command on a device.

    Parameters
    ----------
    ip : str
        Device IP address
    request : CommandExecuteRequest
        Command to execute

    Returns
    -------
    CommandExecuteResponse
        Command execution result
    """
    if not _service:
        raise HTTPException(status_code=503, detail="Service not available")

    try:
        output = await _service.execute_command(ip, request.command, request.timeout)
        return CommandExecuteResponse(
            host=ip,
            command=request.command,
            output=output,
            success=True,
        )
    except ConnectionError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
    except TelnetError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("/{ip}/status", response_model=DeviceStatusResponse)
async def get_device_status(ip: str) -> DeviceStatusResponse:
    """Get device connection status.

    Parameters
    ----------
    ip : str
        Device IP address

    Returns
    -------
    DeviceStatusResponse
        Device status
    """
    if not _service:
        raise HTTPException(status_code=503, detail="Service not available")

    try:
        status = await _service.get_status()
        pool_status = status.get("pool", {})
        connections = pool_status.get("connections", {})

        if ip in connections:
            conn_info = connections[ip]
            return DeviceStatusResponse(
                host=ip,
                connected=conn_info.get("connected", False),
                info=conn_info.get("info", {}),
            )
        else:
            return DeviceStatusResponse(host=ip, connected=False, info={})

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.delete("/{ip}/disconnect")
async def disconnect_device(ip: str) -> dict:
    """Disconnect a device.

    Parameters
    ----------
    ip : str
        Device IP address

    Returns
    -------
    dict
        Disconnection result
    """
    if not _service:
        raise HTTPException(status_code=503, detail="Service not available")

    try:
        await _service.pool.disconnect(ip)
        return {"host": ip, "status": "disconnected", "success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.get("", response_model=dict)
async def list_devices() -> dict:
    """List all managed devices.

    Returns
    -------
    dict
        List of devices
    """
    if not _service:
        raise HTTPException(status_code=503, detail="Service not available")

    try:
        status = await _service.get_status()
        pool_status = status.get("pool", {})
        connections = pool_status.get("connections", {})

        devices = []
        for host, conn_info in connections.items():
            devices.append(
                {
                    "host": host,
                    "connected": conn_info.get("connected", False),
                    "info": conn_info.get("info", {}),
                }
            )

        return {"devices": devices, "total": len(devices)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e)) from e

