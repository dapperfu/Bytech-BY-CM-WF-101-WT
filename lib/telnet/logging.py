"""Structured logging for telnet framework."""

import json
import logging
import sys
from datetime import datetime
from typing import Any

# Default logger
_logger: logging.Logger | None = None
_json_mode = False


def setup_logging(
    level: int = logging.INFO,
    json_output: bool = False,
    log_file: str | None = None,
) -> None:
    """Set up logging configuration.

    Parameters
    ----------
    level : int, optional
        Logging level, by default logging.INFO
    json_output : bool, optional
        Enable JSON output format, by default False
    log_file : str | None, optional
        Log file path, by default None (stdout)
    """
    global _logger, _json_mode

    _json_mode = json_output
    _logger = logging.getLogger("lib.telnet")
    _logger.setLevel(level)
    _logger.handlers.clear()

    if json_output:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
    else:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(TextFormatter())

    if log_file:
        file_handler = logging.FileHandler(log_file)
        if json_output:
            file_handler.setFormatter(JsonFormatter())
        else:
            file_handler.setFormatter(TextFormatter())
        _logger.addHandler(file_handler)

    _logger.addHandler(handler)


def get_logger() -> logging.Logger:
    """Get the framework logger.

    Returns
    -------
    logging.Logger
        Logger instance
    """
    global _logger

    if _logger is None:
        setup_logging()

    return _logger


class JsonFormatter(logging.Formatter):
    """JSON formatter for structured logging."""

    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON.

        Parameters
        ----------
        record : logging.LogRecord
            Log record

        Returns
        -------
        str
            JSON-formatted log entry
        """
        log_data: dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # Add extra fields
        if hasattr(record, "device_ip"):
            log_data["device_ip"] = record.device_ip
        if hasattr(record, "command"):
            log_data["command"] = record.command
        if hasattr(record, "duration"):
            log_data["duration"] = record.duration

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_data)


class TextFormatter(logging.Formatter):
    """Text formatter compatible with existing bash script format."""

    def __init__(self) -> None:
        """Initialize text formatter."""
        super().__init__(
            fmt="[%(asctime)s] [%(levelname)s] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )

    def format(self, record: logging.LogRecord) -> str:
        """Format log record as text.

        Parameters
        ----------
        record : logging.LogRecord
            Log record

        Returns
        -------
        str
            Text-formatted log entry
        """
        # Add device IP prefix if available
        if hasattr(record, "device_ip"):
            record.msg = f"[{record.device_ip}] {record.msg}"

        return super().format(record)


def log_info(message: str, device_ip: str | None = None, **kwargs: Any) -> None:
    """Log info message.

    Parameters
    ----------
    message : str
        Log message
    device_ip : str | None, optional
        Device IP address, by default None
    **kwargs : Any
        Additional log fields
    """
    logger = get_logger()
    extra = kwargs.copy()
    if device_ip:
        extra["device_ip"] = device_ip
    logger.info(message, extra=extra)


def log_error(message: str, device_ip: str | None = None, **kwargs: Any) -> None:
    """Log error message.

    Parameters
    ----------
    message : str
        Log message
    device_ip : str | None, optional
        Device IP address, by default None
    **kwargs : Any
        Additional log fields
    """
    logger = get_logger()
    extra = kwargs.copy()
    if device_ip:
        extra["device_ip"] = device_ip
    logger.error(message, extra=extra)


def log_warn(message: str, device_ip: str | None = None, **kwargs: Any) -> None:
    """Log warning message.

    Parameters
    ----------
    message : str
        Log message
    device_ip : str | None, optional
        Device IP address, by default None
    **kwargs : Any
        Additional log fields
    """
    logger = get_logger()
    extra = kwargs.copy()
    if device_ip:
        extra["device_ip"] = device_ip
    logger.warning(message, extra=extra)


def log_success(message: str, device_ip: str | None = None, **kwargs: Any) -> None:
    """Log success message.

    Parameters
    ----------
    message : str
        Log message
    device_ip : str | None, optional
        Device IP address, by default None
    **kwargs : Any
        Additional log fields
    """
    logger = get_logger()
    extra = kwargs.copy()
    if device_ip:
        extra["device_ip"] = device_ip
    logger.info(f"SUCCESS: {message}", extra=extra)

