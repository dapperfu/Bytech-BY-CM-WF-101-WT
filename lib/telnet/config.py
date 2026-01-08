"""Configuration management for telnet framework."""

import os
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class TelnetDeviceConfig(BaseModel):
    """Configuration for a single device."""

    host: str
    port: int = 23
    username: str = "root"
    password: str = ""
    timeout: float = 30.0
    profile: str | None = None


class TelnetServiceConfig(BaseModel):
    """Configuration for telnet service."""

    max_connections: int = 10
    health_check_interval: float = 30.0
    reconnect_delay: float = 2.0
    health_check_timeout: float = 5.0


class TelnetConfig(BaseSettings):
    """Main configuration class."""

    model_config = SettingsConfigDict(
        env_prefix="TELNET_",
        case_sensitive=False,
        extra="ignore",
    )

    # Default device settings
    default_port: int = Field(default=23, description="Default telnet port")
    default_username: str = Field(default="root", description="Default username")
    default_password: str = Field(default="", description="Default password")
    default_timeout: float = Field(default=30.0, description="Default timeout in seconds")

    # Service settings
    service: TelnetServiceConfig = Field(default_factory=TelnetServiceConfig)

    # Devices
    devices: dict[str, TelnetDeviceConfig] = Field(default_factory=dict)

    # Logging
    log_level: str = Field(default="INFO", description="Logging level")
    log_json: bool = Field(default=False, description="Enable JSON logging")
    log_file: str | None = Field(default=None, description="Log file path")

    @classmethod
    def load_from_yaml(cls, path: str | Path) -> "TelnetConfig":
        """Load configuration from YAML file.

        Parameters
        ----------
        path : str | Path
            Path to YAML file

        Returns
        -------
        TelnetConfig
            Loaded configuration
        """
        yaml_path = Path(path)
        if not yaml_path.exists():
            # Return defaults if file doesn't exist
            return cls()

        with open(yaml_path, "r") as f:
            data = yaml.safe_load(f) or {}

        # Extract telnet section if present
        telnet_data = data.get("telnet", {})
        if not telnet_data:
            telnet_data = data

        return cls(**telnet_data)

    @classmethod
    def load_from_iot_config(cls, path: str | Path = "scripts/iot-config.yaml") -> "TelnetConfig":
        """Load configuration from existing iot-config.yaml.

        Parameters
        ----------
        path : str | Path, optional
            Path to iot-config.yaml, by default "scripts/iot-config.yaml"

        Returns
        -------
        TelnetConfig
            Loaded configuration
        """
        config_path = Path(path)
        if not config_path.exists():
            return cls()

        with open(config_path, "r") as f:
            data = yaml.safe_load(f) or {}

        # Extract telnet section
        telnet_data = data.get("telnet", {})
        if not telnet_data:
            # Create minimal config from existing data
            telnet_data = {}

        return cls(**telnet_data)

    def get_device_config(self, host: str) -> TelnetDeviceConfig:
        """Get device configuration.

        Parameters
        ----------
        host : str
            Device host IP

        Returns
        -------
        TelnetDeviceConfig
            Device configuration
        """
        if host in self.devices:
            return self.devices[host]

        # Return default config
        return TelnetDeviceConfig(
            host=host,
            port=self.default_port,
            username=self.default_username,
            password=self.default_password,
            timeout=self.default_timeout,
        )


def load_config(
    config_file: str | Path | None = None,
    use_iot_config: bool = True,
) -> TelnetConfig:
    """Load configuration from file or environment.

    Parameters
    ----------
    config_file : str | Path | None, optional
        Path to config file, by default None
    use_iot_config : bool, optional
        Try to load from iot-config.yaml if config_file not provided, by default True

    Returns
    -------
    TelnetConfig
        Loaded configuration
    """
    if config_file:
        return TelnetConfig.load_from_yaml(config_file)

    if use_iot_config:
        try:
            return TelnetConfig.load_from_iot_config()
        except Exception:
            pass

    # Load from environment variables
    return TelnetConfig()

