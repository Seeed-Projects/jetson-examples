#!/usr/bin/env python3
"""Download a shared OneDrive archive and keep a reusable local cache."""

from __future__ import annotations

import argparse
import html
import re
import shutil
import sys
import time
from pathlib import Path

import requests

DEFAULT_SHARE_URL = (
    "https://seeedstudio88-my.sharepoint.com/:u:/g/personal/"
    "youjiang_yu_seeedstudio88_onmicrosoft_com/"
    "IQCCDToomY6WSaRZdfsTs9vXAengb-SCEvNfSUgq0cipP6w?e=fXekAu"
)
DEFAULT_FILENAME = "nvblox_images.tar"
USER_AGENT = "Mozilla/5.0 (compatible; reComputer-nvblox-downloader/1.0)"
DOWNLOAD_TIMEOUT_SECONDS = 600
HTML_PROBE_BYTES = 4096
CHUNK_SIZE = 8 * 1024 * 1024
MIN_VALID_FILE_SIZE = 1024


class DownloadError(RuntimeError):
    """Raised when the share link cannot be resolved or downloaded."""


class OneDriveDownloader:
    def __init__(self, download_dir: str | Path = ".") -> None:
        self.download_dir = Path(download_dir)
        self.download_dir.mkdir(parents=True, exist_ok=True)
        self._progress_stream = self._open_progress_stream()
        self._progress_active = False

    @staticmethod
    def _open_progress_stream():
        try:
            stream = open("/dev/tty", "w", encoding="utf-8", buffering=1)
        except OSError:
            stream = None

        if stream is not None:
            return stream

        if sys.stdout.isatty():
            return sys.stdout

        return None

    @staticmethod
    def _looks_like_html(content_type: str, first_chunk: bytes) -> bool:
        lowered = (content_type or "").lower()
        if "text/html" in lowered:
            return True

        stripped = first_chunk.lstrip().lower()
        return stripped.startswith(b"<!doctype html") or stripped.startswith(b"<html")

    @staticmethod
    def _decode_embedded_url(raw_value: str) -> str:
        return html.unescape(raw_value.encode("utf-8").decode("unicode_escape")).replace(
            "\\/",
            "/",
        )

    def _extract_download_url(self, html_text: str) -> str | None:
        patterns = (
            r'"\.downloadUrl"\s*:\s*"([^"]+)"',
            r'"downloadUrl"\s*:\s*"([^"]+)"',
            r'"@microsoft\.graph\.downloadUrl"\s*:\s*"([^"]+)"',
        )

        for pattern in patterns:
            match = re.search(pattern, html_text)
            if match:
                return self._decode_embedded_url(match.group(1))
        return None

    def resolve_download_url(self, share_url: str) -> str:
        try:
            with requests.get(
                share_url,
                headers={"User-Agent": USER_AGENT},
                timeout=(15, DOWNLOAD_TIMEOUT_SECONDS),
                allow_redirects=True,
            ) as response:
                response.raise_for_status()
                first_chunk = response.content[:HTML_PROBE_BYTES]
                content_type = response.headers.get("Content-Type", "")
                final_url = response.url

                if first_chunk and not self._looks_like_html(content_type, first_chunk):
                    return final_url

                html_text = response.text
        except requests.RequestException as exc:
            raise DownloadError(f"Failed to open OneDrive share link: {exc}") from exc

        direct_url = self._extract_download_url(html_text)
        if direct_url:
            return direct_url

        raise DownloadError(
            "Share link resolved to an HTML preview page, but no anonymous download URL "
            "could be extracted from the response."
        )

    def _existing_file_is_usable(self, filepath: Path) -> bool:
        if not filepath.is_file():
            return False

        if filepath.stat().st_size < MIN_VALID_FILE_SIZE:
            return False

        try:
            with filepath.open("rb") as existing_file:
                first_chunk = existing_file.read(HTML_PROBE_BYTES)
        except OSError:
            return False

        return not self._looks_like_html("", first_chunk)

    @staticmethod
    def _format_bytes(num_bytes: int) -> str:
        value = float(num_bytes)
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if value < 1024.0 or unit == "TB":
                return f"{value:.1f}{unit}"
            value /= 1024.0
        return f"{num_bytes}B"

    def _emit_progress(
        self,
        filename: str,
        written: int,
        total: int | None,
        started_at: float,
        *,
        force: bool = False,
    ) -> None:
        now = time.monotonic()
        if not force and (now - started_at) < 2:
            return

        if self._progress_stream is None:
            return

        elapsed = max(now - started_at, 0.001)
        speed = written / elapsed
        terminal_width = shutil.get_terminal_size((100, 20)).columns
        bar_width = min(36, max(12, terminal_width - 70))

        if total and total > 0:
            percent = min(max(written / total, 0.0), 1.0)
            filled = int(bar_width * percent)
            bar = "#" * filled + "-" * (bar_width - filled)
            message = (
                f"\rDownloading {filename} [{bar}] {percent * 100:5.1f}% "
                f"{self._format_bytes(written)}/{self._format_bytes(total)} "
                f"{self._format_bytes(int(speed))}/s"
            )
        else:
            message = (
                f"\rDownloading {filename} "
                f"{self._format_bytes(written)} {self._format_bytes(int(speed))}/s"
            )

        if len(message) > terminal_width:
            message = message[: terminal_width - 1]

        self._progress_stream.write(message.ljust(terminal_width - 1))
        self._progress_stream.flush()
        self._progress_active = True

    def _finish_progress(self) -> None:
        if self._progress_stream is None or not self._progress_active:
            return

        self._progress_stream.write("\n")
        self._progress_stream.flush()
        self._progress_active = False

    def _download_from_url(self, download_url: str, filepath: Path, filename: str) -> None:
        tmp_path = filepath.with_suffix(filepath.suffix + ".part")
        if tmp_path.exists():
            tmp_path.unlink()

        print(f"Resolved OneDrive direct download URL for {filename}.", flush=True)
        last_report_at = 0.0

        try:
            with requests.get(
                download_url,
                headers={"User-Agent": USER_AGENT},
                timeout=(15, DOWNLOAD_TIMEOUT_SECONDS),
                allow_redirects=True,
                stream=True,
            ) as response, tmp_path.open("wb") as output_file:
                response.raise_for_status()
                content_type = response.headers.get("Content-Type", "")
                total_size_header = response.headers.get("Content-Length")
                total_size = int(total_size_header) if total_size_header else None

                chunks = response.iter_content(chunk_size=CHUNK_SIZE)
                first_chunk = next(chunks, b"")
                if not first_chunk:
                    raise DownloadError("Downloaded content is empty.")
                if self._looks_like_html(content_type, first_chunk):
                    preview = first_chunk[:200].decode("utf-8", errors="ignore")
                    raise DownloadError(
                        "Download URL returned HTML content instead of the Docker archive. "
                        f"Preview: {preview}"
                    )

                started_at = time.monotonic()
                written = 0
                if total_size and total_size > 0:
                    print(
                        f"Downloading {filename} ({self._format_bytes(total_size)})...",
                        flush=True,
                    )
                else:
                    print(f"Downloading {filename}...", flush=True)

                output_file.write(first_chunk)
                written += len(first_chunk)
                self._emit_progress(filename, written, total_size, started_at, force=True)
                last_report_at = time.monotonic()

                for chunk in chunks:
                    if not chunk:
                        continue
                    output_file.write(chunk)
                    written += len(chunk)

                    if time.monotonic() - last_report_at >= 5:
                        self._emit_progress(filename, written, total_size, started_at)
                        last_report_at = time.monotonic()

            if written < MIN_VALID_FILE_SIZE:
                raise DownloadError(
                    f"Downloaded file is unexpectedly small: {written} bytes."
                )

            if filepath.exists():
                filepath.unlink()
            tmp_path.replace(filepath)
            self._emit_progress(filename, written, total_size, started_at, force=True)
            self._finish_progress()
            print(f"Download complete: {filepath}", flush=True)
        except Exception:
            self._finish_progress()
            if tmp_path.exists():
                tmp_path.unlink()
            raise

    def download_file(self, share_url: str, filename: str = DEFAULT_FILENAME) -> Path:
        filepath = self.download_dir / filename

        if self._existing_file_is_usable(filepath):
            print(f"Using cached archive: {filepath}", flush=True)
            return filepath

        if filepath.exists():
            filepath.unlink()

        download_url = self.resolve_download_url(share_url)
        self._download_from_url(download_url, filepath, filename)
        return filepath


def main() -> int:
    parser = argparse.ArgumentParser(description="OneDrive/SharePoint downloader")
    parser.add_argument(
        "url",
        nargs="?",
        default=DEFAULT_SHARE_URL,
        help="OneDrive share link",
    )
    parser.add_argument(
        "filename",
        nargs="?",
        default=DEFAULT_FILENAME,
        help="Output filename",
    )
    parser.add_argument(
        "--download-dir",
        default="downloads",
        help="Directory used to store the downloaded archive",
    )
    parser.add_argument(
        "--aria2c",
        action="store_true",
        help="Print an aria2c command for the resolved direct download URL",
    )
    args = parser.parse_args()

    downloader = OneDriveDownloader(download_dir=args.download_dir)

    try:
        if args.aria2c:
            direct_url = downloader.resolve_download_url(args.url)
            print(f"aria2c '{direct_url}' -d '{args.download_dir}' -o '{args.filename}'")
            return 0

        downloader.download_file(args.url, args.filename)
        return 0
    except DownloadError as exc:
        print(f"Download failed: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Download cancelled.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
