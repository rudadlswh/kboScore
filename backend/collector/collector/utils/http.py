from __future__ import annotations

from dataclasses import dataclass, field
from typing import Mapping
from urllib import error, parse, request


@dataclass(frozen=True, slots=True)
class HTTPResponse:
    status_code: int
    headers: Mapping[str, str]
    body: bytes

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")


@dataclass(slots=True)
class HTTPClient:
    timeout_seconds: int = 10
    default_headers: dict[str, str] = field(
        default_factory=lambda: {
            "User-Agent": "kboScoreCollector/1.0",
            "Accept": "*/*",
        }
    )

    def get(self, url: str, headers: Mapping[str, str] | None = None) -> HTTPResponse:
        req = request.Request(url=url, headers={**self.default_headers, **(headers or {})}, method="GET")
        try:
            with request.urlopen(req, timeout=self.timeout_seconds) as resp:  # pragma: no cover - network integration
                return HTTPResponse(status_code=resp.status, headers=dict(resp.headers.items()), body=resp.read())
        except error.HTTPError as http_error:  # pragma: no cover - network integration
            return HTTPResponse(
                status_code=http_error.code,
                headers=dict(http_error.headers.items()),
                body=http_error.read(),
            )

    def post(
        self,
        url: str,
        form_data: Mapping[str, str],
        headers: Mapping[str, str] | None = None,
    ) -> HTTPResponse:
        encoded = parse.urlencode(form_data).encode("utf-8")
        request_headers = {
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            **self.default_headers,
            **(headers or {}),
        }
        req = request.Request(url=url, headers=request_headers, data=encoded, method="POST")
        try:
            with request.urlopen(req, timeout=self.timeout_seconds) as resp:  # pragma: no cover - network integration
                return HTTPResponse(status_code=resp.status, headers=dict(resp.headers.items()), body=resp.read())
        except error.HTTPError as http_error:  # pragma: no cover - network integration
            return HTTPResponse(
                status_code=http_error.code,
                headers=dict(http_error.headers.items()),
                body=http_error.read(),
            )
