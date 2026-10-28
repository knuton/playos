#!/usr/bin/env python3
import argparse
import base64
import json
import time
import urllib.request
from pathlib import Path
from websockets.sync.client import connect


TIMEOUT = 30


def http_json(url, method="GET"):
    request = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


class CDP:
    def __init__(self, ws):
        self.ws = ws
        self.next_id = 0
        self.events = []

    def command(self, method, params=None):
        self.next_id += 1
        command_id = self.next_id

        self.ws.send(json.dumps({
            "id": command_id,
            "method": method,
            "params": params or {},
        }))

        while True:
            message = json.loads(self.ws.recv())

            if message.get("id") == command_id:
                if "error" in message:
                    raise RuntimeError(
                        f"{method}: {message['error']}"
                    )
                return message.get("result", {})

            if "method" in message:
                self.events.append(message)

    def wait_event(self, method):
        while True:
            for i, event in enumerate(self.events):
                if event.get("method") == method:
                    return self.events.pop(i)

            message = json.loads(self.ws.recv())

            if message.get("method") == method:
                return message

            if "method" in message:
                self.events.append(message)


def capture_batch(port, jobs):
    base_url = f"http://127.0.0.1:{port}"

    targets = http_json(f"{base_url}/json/list")
    page = next(
        (target for target in targets if target.get("type") == "page"),
        None,
    )
    if not page:
        raise RuntimeError("No existing Chromium page/tab found")

    with connect(
        page["webSocketDebuggerUrl"],
        open_timeout=TIMEOUT,
        close_timeout=5,
    ) as ws:
        cdp = CDP(ws)

        cdp.command("Page.enable")
        cdp.command("Runtime.enable")
        for index, job in enumerate(jobs, start=1):
            url = job["url"]
            output = Path(job["output"])
            output.parent.mkdir(parents=True, exist_ok=True)

            print(f"[{index}/{len(jobs)}] {url}")

            width, height = job.get("resolution")
            cdp.command("Emulation.setDeviceMetricsOverride", {
                "width": width,
                "height": height,
                "deviceScaleFactor": 1,
                "mobile": False,
            })

            # Navigate to URL and wait for page load, then sleep briefly to let page settle
            cdp.command("Page.navigate", {"url": url})
            cdp.wait_event("Page.loadEventFired")
            time.sleep(2)

            cdp.command("Runtime.evaluate", {
                "expression": """
                    Promise.all([
                        document.fonts.ready,
                        ...Array.from(document.images, img => {
                            if (img.complete) return Promise.resolve();
                            return new Promise(resolve => {
                                img.addEventListener(
                                    "load", resolve, { once: true }
                                );
                                img.addEventListener(
                                    "error", resolve, { once: true }
                                );
                            });
                        })
                    ]).then(() => new Promise(resolve =>
                        requestAnimationFrame(() =>
                            requestAnimationFrame(resolve)
                        )
                    ))
                """,
                "awaitPromise": True,
            })

            result = cdp.command("Page.captureScreenshot", {
                "format": "png",
                "fromSurface": True,
                "captureBeyondViewport": False,
            })

            output.write_bytes(base64.b64decode(result["data"]))
            print(f"  Saved {output}")


def parse_resolution(value):
    """Parse a resolution definition like 1280x720 into a tuple of width and height."""
    try:
        width, height = value.lower().split("x", 1)
        width, height = int(width), int(height)
        if width <= 0 or height <= 0:
            raise ValueError
        return width, height
    except ValueError:
        raise argparse.ArgumentTypeError(
            "Resolution must be WIDTHxHEIGHT, e.g. 1200x700"
        )


def parse_args():
    parser = argparse.ArgumentParser(
        description="Capture fixed-size viewport screenshots via Chromium CDP."
    )
    parser.add_argument(
        "--port", type=int, default=3355,
        help="Chromium remote debugging port (default: 3355)",
    )

    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--url", help="URL to capture")
    mode.add_argument("--json", help="JSON file containing a list of jobs")

    parser.add_argument(
        "--resolution",
        type=parse_resolution,
        default=(1280, 720),
        help="Viewport resolution WIDTHxHEIGHT (default: 1280x720)",
    )

    parser.add_argument(
        "--output",
        help="Output PNG path; required with --url",
    )

    args = parser.parse_args()

    if args.url:
        if not args.output:
            parser.error("--output is required with --url")
        jobs = [{"url": args.url, "output": args.output, "resolution": args.resolution}]
    else:
        if args.output:
            parser.error("--output cannot be used with --json")
        with open(args.json, encoding="utf-8") as f:
            jobs = json.load(f)

        if not isinstance(jobs, list):
            parser.error("JSON must contain a list of jobs")

        for job in jobs:
            if (
                not isinstance(job, dict)
                or not isinstance(job.get("url"), str)
                or not job["url"]
                or not isinstance(job.get("output"), str)
                or not job["output"]
            ):
                parser.error(
                    'Each job must contain non-empty string fields "url" and "output"'
                )

            if "resolution" in job:
                job["resolution"] = parse_resolution(job["resolution"])
            else:
                job["resolution"] = args.resolution

    return args.port, jobs


if __name__ == "__main__":
    port, jobs = parse_args()
    capture_batch(port, jobs)

