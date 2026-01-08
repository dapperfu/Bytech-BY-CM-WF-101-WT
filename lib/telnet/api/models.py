"""Pydantic models for API requests/responses."""

from pydantic import BaseModel, Field


class DeviceConnectRequest(BaseModel):
    """Request to connect a device."""

    port: int = Field(default=23, description="Telnet port")
    username: str = Field(default="root", description="Username")
    password: str = Field(default="", description="Password")
    timeout: float = Field(default=30.0, description="Connection timeout")
    profile: str | None = Field(default=None, description="Device profile name")


class CommandExecuteRequest(BaseModel):
    """Request to execute a command."""

    command: str = Field(..., description="Command to execute")
    timeout: float | None = Field(default=None, description="Command timeout")


class CommandExecuteResponse(BaseModel):
    """Response from command execution."""

    host: str = Field(..., description="Device host IP")
    command: str = Field(..., description="Executed command")
    output: str = Field(..., description="Command output")
    success: bool = Field(..., description="Whether command succeeded")


class DeviceStatusResponse(BaseModel):
    """Device connection status."""

    host: str = Field(..., description="Device host IP")
    connected: bool = Field(..., description="Whether device is connected")
    info: dict = Field(default_factory=dict, description="Connection metadata")


class ServiceStatusResponse(BaseModel):
    """Service status response."""

    running: bool = Field(..., description="Whether service is running")
    pool: dict = Field(..., description="Connection pool status")

