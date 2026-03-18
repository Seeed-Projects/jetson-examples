#!/usr/bin/env python3
"""Download public OneDrive/SharePoint share links with resume support."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlencode, urlparse, urlunparse

import requests
from tqdm import tqdm


CHUNK_SIZE = 65536
MIN_VALID_SIZE = 1024 * 1024
PROBE_CHUNK_SIZE = 4096
REQUEST_TIMEOUT = (15, 600)
DEFAULT_SHARE_URL = (
    "https://seeedstudio88-my.sharepoint.com/:u:/g/personal/"
    "youjiang_yu_seeedstudio88_onmicrosoft_com/"
    "IQCCDToomY6WSaRZdfsTs9vXAengb-SCEvNfSUgq0cipP6w?e=z9axor"
)
DEFAULT_FILENAME = "nvblox_images.tar"
DEFAULT_OUTPUT_DIR = Path.home() / ".cache" / "jetson-examples" / "nvblox"
SUPPORTED_DOMAINS = ("sharepoint.com", "sharepoint.cn")
SHARE_LINK_RE = re.compile(r"^/:[a-z]:/", re.IGNORECASE)
TEXT_ERROR_MARKERS = (
    "forbidden",
    "access denied",
    "sign in",
    "login",
    "not found",
    "permission",
)


class DownloadError(Exception):
    """Raised when the download cannot proceed safely."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download a public Microsoft 365 OneDrive/SharePoint share link."
    )
    parser.add_argument(
        "share_url",
        nargs="?",
        default=DEFAULT_SHARE_URL,
        help="Public sharepoint.com/sharepoint.cn share link",
    )
    parser.add_argument(
        "legacy_filename",
        nargs="?",
        help="Legacy positional filename override",
    )
    parser.add_argument(
        "--output-dir",
        "--download-dir",
        dest="output_dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Directory to save the file (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--filename",
        help="Override the detected filename. Only the final path component is used.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Redownload even if the target file already exists.",
    )
    parser.add_argument(
        "--aria2c",
        action="store_true",
        help="Print an aria2c command for the resolved direct download URL",
    )
    return parser.parse_args()


def is_supported_host(hostname: str) -> bool:
    hostname = hostname.lower()
    return any(
        hostname == domain or hostname.endswith(f".{domain}")
        for domain in SUPPORTED_DOMAINS
    )


def sanitize_filename(value: str | None) -> str | None:
    if not value:
        return None
    candidate = value.strip().strip("\"'")
    if not candidate:
        return None
    candidate = candidate.replace("\\", "/")
    candidate = Path(candidate).name
    if candidate in {"", ".", ".."}:
        return None
    return candidate


def validate_source_url(raw_url: str) -> str:
    url = raw_url.strip()
    if not url:
        raise DownloadError("share_url is required.")

    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise DownloadError("URL must start with http:// or https://.")

    hostname = parsed.hostname or ""
    if not is_supported_host(hostname):
        raise DownloadError(
            "Only public sharepoint.com/sharepoint.cn links are supported in v1."
        )

    lower_path = (parsed.path or "").lower()
    if "/_layouts/15/onedrive.aspx" in lower_path:
        raise DownloadError(
            "Unsupported page-style OneDrive URL. Use a public share link instead of "
            "a /_layouts/15/onedrive.aspx page or a login-protected page."
        )

    if not parsed.path:
        raise DownloadError("URL path is empty.")

    return url


def needs_download_flag(parsed_url) -> bool:
    return bool(SHARE_LINK_RE.match(parsed_url.path or ""))


def with_download_flag(url: str) -> str:
    parsed = urlparse(url)
    if not needs_download_flag(parsed):
        return url

    query_items = [
        (key, value)
        for key, value in parse_qsl(parsed.query, keep_blank_values=True)
        if key.lower() != "download"
    ]
    query_items.append(("download", "1"))
    return urlunparse(parsed._replace(query=urlencode(query_items, doseq=True)))


def looks_like_landing_page(content_type: str, first_chunk: bytes) -> bool:
    content_type = (content_type or "").lower()
    first = (first_chunk or b"").lstrip()
    first_lower = first.lower()

    if "text/html" in content_type or "application/xhtml" in content_type:
        return True

    if first_lower.startswith(b"<!doctype html") or first_lower.startswith(b"<html"):
        return True

    if content_type.startswith("text/plain"):
        snippet = first[:512].decode("utf-8", errors="ignore").lower()
        if any(marker in snippet for marker in TEXT_ERROR_MARKERS):
            return True

    return False


def filename_from_content_disposition(header_value: str | None) -> str | None:
    if not header_value:
        return None

    match = re.search(
        r"filename\*\s*=\s*(?:[A-Za-z0-9!#$&+\-.^_`|~]+'[^']*')?([^;]+)",
        header_value,
        flags=re.IGNORECASE,
    )
    if match:
        return sanitize_filename(unquote(match.group(1).strip().strip("\"'")))

    match = re.search(r'filename\s*=\s*"([^"]+)"', header_value, flags=re.IGNORECASE)
    if match:
        return sanitize_filename(match.group(1))

    match = re.search(r"filename\s*=\s*([^;]+)", header_value, flags=re.IGNORECASE)
    if match:
        return sanitize_filename(match.group(1))

    return None


def filename_from_url(url: str) -> str | None:
    parsed = urlparse(url)
    return sanitize_filename(unquote(Path(parsed.path or "").name))


def probe_remote_target(url: str, filename_override: str | None) -> tuple[str, str]:
    headers = {"Range": "bytes=0-0"}
    try:
        response = requests.get(
            url,
            stream=True,
            timeout=REQUEST_TIMEOUT,
            allow_redirects=True,
            headers=headers,
        )
    except requests.RequestException as exc:
        raise DownloadError(f"Failed to resolve the download target: {exc}") from exc

    try:
        response.raise_for_status()
        first_chunk = next(response.iter_content(chunk_size=PROBE_CHUNK_SIZE), b"")
        if looks_like_landing_page(response.headers.get("content-type", ""), first_chunk):
            raise DownloadError(
                "The link resolved to an HTML/text page instead of a downloadable file."
            )

        filename = (
            sanitize_filename(filename_override)
            or filename_from_content_disposition(
                response.headers.get("content-disposition")
            )
            or filename_from_url(response.url)
        )
        if not filename:
            raise DownloadError(
                "Could not infer a filename from the response. Pass --filename."
            )

        return response.url, filename
    except requests.RequestException as exc:
        raise DownloadError(f"Failed to resolve the download target: {exc}") from exc
    finally:
        response.close()


def prepare_target_paths(
    output_dir: Path, filename: str, force: bool
) -> tuple[Path, Path, bool]:
    output_dir.mkdir(parents=True, exist_ok=True)

    filepath = output_dir / filename
    tmp_path = filepath.with_suffix(filepath.suffix + ".part")

    if force:
        if filepath.exists():
            print(f"Removing cached file: {filepath}")
            filepath.unlink()
        if tmp_path.exists():
            print(f"Removing partial download: {tmp_path}")
            tmp_path.unlink()
        return filepath, tmp_path, False

    if filepath.exists():
        size = filepath.stat().st_size
        if size > MIN_VALID_SIZE:
            print(f"File already exists: {filepath}")
            return filepath, tmp_path, True
        print(
            f"Existing file is too small ({size} bytes), redownloading: {filepath}"
        )
        filepath.unlink()
        if tmp_path.exists():
            tmp_path.unlink()

    return filepath, tmp_path, False


def progress_stream():
    try:
        return open("/dev/tty", "w", encoding="utf-8", buffering=1)
    except OSError:
        return sys.stdout


def download_file(url: str, filepath: Path, filename: str) -> None:
    tmp_path = filepath.with_suffix(filepath.suffix + ".part")

    while True:
        resume_pos = tmp_path.stat().st_size if tmp_path.exists() else 0
        headers = {}
        if resume_pos > 0:
            headers["Range"] = f"bytes={resume_pos}-"
            print(f"Resuming download from byte {resume_pos}")

        try:
            response = requests.get(
                url,
                stream=True,
                timeout=REQUEST_TIMEOUT,
                allow_redirects=True,
                headers=headers,
            )
        except requests.RequestException as exc:
            raise DownloadError(f"Failed to start download: {exc}") from exc

        try:
            if resume_pos > 0 and response.status_code == 200:
                print("Server ignored the resume request, restarting from byte 0.")
                response.close()
                tmp_path.unlink(missing_ok=True)
                continue

            response.raise_for_status()

            total_size = int(response.headers.get("content-length", 0) or 0)
            if total_size and resume_pos:
                total_size += resume_pos

            chunks = response.iter_content(chunk_size=CHUNK_SIZE)
            first_chunk = next((chunk for chunk in chunks if chunk), b"")
            if not first_chunk:
                raise DownloadError("Downloaded content is empty.")

            if resume_pos == 0 and looks_like_landing_page(
                response.headers.get("content-type", ""), first_chunk
            ):
                raise DownloadError(
                    "The link resolved to an HTML/text page instead of a downloadable file."
                )

            written = resume_pos + len(first_chunk)
            mode = "ab" if resume_pos > 0 else "wb"

            progress_file = progress_stream()
            progress_bar = tqdm(
                desc=filename,
                initial=resume_pos,
                total=total_size if total_size > 0 else None,
                unit="B",
                unit_scale=True,
                unit_divisor=1024,
                file=progress_file,
                dynamic_ncols=True,
                ascii=True,
                leave=False,
                mininterval=0.2,
                smoothing=0.1,
            )
            try:
                with open(tmp_path, mode) as handle:
                    handle.write(first_chunk)
                    progress_bar.update(len(first_chunk))

                    for chunk in chunks:
                        if not chunk:
                            continue
                        handle.write(chunk)
                        written += len(chunk)
                        progress_bar.update(len(chunk))
            finally:
                progress_bar.close()
                if progress_file not in (sys.stdout, sys.stderr):
                    progress_file.write("\n")
                    progress_file.close()

            if written < MIN_VALID_SIZE:
                tmp_path.unlink(missing_ok=True)
                raise DownloadError(
                    f"Downloaded file is unexpectedly small: {written} bytes."
                )

            tmp_path.replace(filepath)
            return
        except requests.RequestException as exc:
            raise DownloadError(
                f"Download interrupted by a network/protocol error: {exc}"
            ) from exc
        finally:
            response.close()


def main() -> int:
    args = parse_args()

    try:
        validated_url = validate_source_url(args.share_url)
        normalized_url = with_download_flag(validated_url)
        output_dir = args.output_dir.expanduser()

        filename_override = sanitize_filename(args.filename or args.legacy_filename)
        if (args.filename or args.legacy_filename) and not filename_override:
            raise DownloadError("Invalid filename value.")

        print(f"Resolving download target: {normalized_url}")
        resolved_url, detected_filename = probe_remote_target(normalized_url, filename_override)
        filename = filename_override or detected_filename or DEFAULT_FILENAME

        filepath, _tmp_path, already_exists = prepare_target_paths(
            output_dir, filename, args.force
        )
        if already_exists:
            return 0

        if resolved_url != normalized_url:
            print(f"Resolved file URL: {resolved_url}")

        print(f"Download URL: {normalized_url}")
        print(f"Saving to: {filepath}")

        if args.aria2c:
            print(f"aria2c '{resolved_url}' -d '{output_dir}' -o '{filename}'")
            return 0

        download_file(resolved_url, filepath, filename)
        print(f"Download complete: {filepath}")
        return 0
    except DownloadError as exc:
        print(f"Error: {exc}")
        return 1
    except OSError as exc:
        print(f"Error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
