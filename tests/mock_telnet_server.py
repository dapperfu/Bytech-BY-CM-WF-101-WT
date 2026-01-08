"""Mock telnet server for unit testing."""

import socket
import threading
import time
from typing import Callable


class MockTelnetServer:
    """Mock telnet server for testing."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 0,  # 0 = random port
        prompt: str = "# ",
        login_prompt: str = "login:",
        password_prompt: str = "Password:",
        welcome_message: str = "",
    ) -> None:
        """Initialize mock telnet server.

        Parameters
        ----------
        host : str, optional
            Bind host, by default "127.0.0.1"
        port : int, optional
            Bind port (0 for random), by default 0
        prompt : str, optional
            Shell prompt, by default "# "
        login_prompt : str, optional
            Login prompt, by default "login:"
        password_prompt : str, optional
            Password prompt, by default "Password:"
        welcome_message : str, optional
            Welcome message, by default ""
        """
        self.host = host
        self.port = port
        self.prompt = prompt
        self.login_prompt = login_prompt
        self.password_prompt = password_prompt
        self.welcome_message = welcome_message

        self.socket: socket.socket | None = None
        self.server_thread: threading.Thread | None = None
        self.running = False
        self.actual_port: int | None = None
        self.command_handler: Callable[[str], str] | None = None

    def set_command_handler(self, handler: Callable[[str], str]) -> None:
        """Set command handler function.

        Parameters
        ----------
        handler : Callable[[str], str]
            Function that takes command and returns output
        """
        self.command_handler = handler

    def start(self) -> int:
        """Start the mock server.

        Returns
        -------
        int
            Actual port number
        """
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind((self.host, self.port))
        self.socket.listen(1)
        self.actual_port = self.socket.getsockname()[1]
        self.running = True

        self.server_thread = threading.Thread(target=self._server_loop, daemon=True)
        self.server_thread.start()

        return self.actual_port

    def stop(self) -> None:
        """Stop the mock server."""
        self.running = False
        if self.socket:
            try:
                self.socket.close()
            except Exception:
                pass

        if self.server_thread:
            self.server_thread.join(timeout=1.0)

    def _server_loop(self) -> None:
        """Server main loop."""
        while self.running:
            try:
                if not self.socket:
                    break

                conn, addr = self.socket.accept()
                self._handle_client(conn)
            except Exception:
                if self.running:
                    break

    def _handle_client(self, conn: socket.socket) -> None:
        """Handle client connection.

        Parameters
        ----------
        conn : socket.socket
            Client connection
        """
        try:
            # Send welcome message
            if self.welcome_message:
                conn.send(self.welcome_message.encode())

            # Send login prompt
            conn.send(f"{self.login_prompt} ".encode())
            conn.recv(1024)  # Receive username

            # Send password prompt
            conn.send(f"{self.password_prompt} ".encode())
            conn.recv(1024)  # Receive password

            # Send prompt
            conn.send(self.prompt.encode())

            # Command loop
            while self.running:
                data = conn.recv(1024).decode()
                if not data:
                    break

                # Extract command (remove \r\n)
                command = data.strip()

                if command.lower() == "exit":
                    break

                # Handle command
                if self.command_handler:
                    output = self.command_handler(command)
                else:
                    output = f"Command: {command}\n"

                # Send output and prompt
                conn.send(output.encode())
                conn.send(self.prompt.encode())

        except Exception:
            pass
        finally:
            conn.close()

    def __enter__(self) -> "MockTelnetServer":
        """Context manager entry."""
        self.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        """Context manager exit."""
        self.stop()

