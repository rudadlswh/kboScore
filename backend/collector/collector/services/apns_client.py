from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Protocol

from collector.config import CollectorConfig


@dataclass(frozen=True, slots=True)
class APNSNotificationRequest:
    device_token: str
    title: str | None
    body: str | None
    payload_json: dict


class APNSConfigurationError(RuntimeError):
    """Raised when APNs delivery is requested without the required credentials/config."""


class APNSDeliveryError(RuntimeError):
    def __init__(
        self,
        reason: str,
        *,
        status_code: int | None = None,
        retryable: bool = False,
        disable_device: bool = False,
    ) -> None:
        super().__init__(reason)
        self.reason = reason
        self.status_code = status_code
        self.retryable = retryable
        self.disable_device = disable_device


class APNSClient(Protocol):
    def send_notification(self, request: APNSNotificationRequest) -> None:
        """Send one prepared notification to APNs or raise APNSDeliveryError."""


@dataclass(slots=True)
class TokenBasedAPNSClient:
    team_id: str
    key_id: str
    bundle_id: str
    private_key_path: str
    use_sandbox: bool = True
    timeout_seconds: int = 10

    @classmethod
    def from_config(cls, config: CollectorConfig) -> "TokenBasedAPNSClient":
        missing = [
            name
            for name, value in (
                ("APNS_TEAM_ID", config.apns_team_id),
                ("APNS_KEY_ID", config.apns_key_id),
                ("APNS_BUNDLE_ID", config.apns_bundle_id),
                ("APNS_PRIVATE_KEY_PATH", config.apns_private_key_path),
            )
            if not value
        ]
        if missing:
            raise APNSConfigurationError(
                "APNs delivery configuration is incomplete: missing " + ", ".join(missing)
            )

        return cls(
            team_id=config.apns_team_id or "",
            key_id=config.apns_key_id or "",
            bundle_id=config.apns_bundle_id or "",
            private_key_path=config.apns_private_key_path or "",
            use_sandbox=config.apns_use_sandbox,
            timeout_seconds=config.http_timeout_seconds,
        )

    def send_notification(self, request: APNSNotificationRequest) -> None:
        if not request.device_token.strip():
            raise APNSDeliveryError("blank_device_token", retryable=False, disable_device=False)

        try:
            import httpx
            import jwt
        except ImportError as error:  # pragma: no cover - environment/configuration failure
            raise APNSConfigurationError(
                "APNs delivery dependencies are missing; install collector requirements"
            ) from error

        host = "https://api.sandbox.push.apple.com" if self.use_sandbox else "https://api.push.apple.com"
        url = f"{host}/3/device/{request.device_token}"
        auth_token = self._build_auth_token(jwt)
        payload = {
            "aps": {
                "alert": {
                    "title": request.title or "",
                    "body": request.body or "",
                },
                "sound": "default",
            },
            "data": request.payload_json,
        }

        try:
            with httpx.Client(http2=True, timeout=self.timeout_seconds) as client:
                response = client.post(
                    url,
                    headers={
                        "authorization": f"bearer {auth_token}",
                        "apns-topic": self.bundle_id,
                        "apns-push-type": "alert",
                        "content-type": "application/json",
                    },
                    json=payload,
                )
        except httpx.TimeoutException as error:
            raise APNSDeliveryError("apns_timeout", retryable=True) from error
        except httpx.TransportError as error:
            raise APNSDeliveryError("apns_transport_error", retryable=True) from error

        if response.status_code == 200:
            return

        reason = f"apns_http_{response.status_code}"
        try:
            body = response.json()
        except ValueError:
            body = None
        if isinstance(body, dict) and body.get("reason"):
            reason = str(body["reason"])
        raise self._classify_http_error(reason=reason, status_code=response.status_code)

    @staticmethod
    def _classify_http_error(*, reason: str, status_code: int) -> APNSDeliveryError:
        invalid_token_reasons = {"BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"}
        if reason in invalid_token_reasons:
            return APNSDeliveryError(reason, status_code=status_code, retryable=False, disable_device=True)
        if status_code >= 500:
            return APNSDeliveryError(reason, status_code=status_code, retryable=True, disable_device=False)
        if status_code == 429:
            return APNSDeliveryError(reason, status_code=status_code, retryable=True, disable_device=False)
        return APNSDeliveryError(reason, status_code=status_code, retryable=False, disable_device=False)

    def _build_auth_token(self, jwt_module) -> str:
        with open(self.private_key_path, "r", encoding="utf-8") as fp:
            private_key = fp.read()

        token = jwt_module.encode(
            {"iss": self.team_id, "iat": int(time.time())},
            private_key,
            algorithm="ES256",
            headers={"kid": self.key_id},
        )
        return str(token)
