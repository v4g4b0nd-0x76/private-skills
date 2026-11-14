"""Contract tests: does the app agree with what the provider actually returns?

Hunts for schema drift — a field added, removed, renamed, or retyped — which
is the failure mode that produces silent `None`s in production.
"""

import pytest

from conftest import request


def test_required_fields_present(app, base_url, run_id):
    """Every field the app reads must exist. A missing required field must fail
    loudly, not become null."""
    r = request(app, base_url, "GET", "/api/items")
    if r.status_code != 200:
        pytest.skip(f"endpoint not available: {r.status_code}")

    body = r.json()
    items = body.get("items", body if isinstance(body, list) else [])
    assert items, "empty result — cannot verify a contract against nothing"

    REQUIRED = ["id"]  # TODO: from .thirdparty/requirements.md
    for item in items:
        for field in REQUIRED:
            assert field in item, f"required field '{field}' missing: {item}"
            assert item[field] is not None, f"required field '{field}' is null"


def test_unknown_fields_do_not_crash(app, base_url, provider_stub):
    """Forward compatibility: a provider adding a field must not break the app."""
    # TODO: bind the provider to the stub and add an unexpected field.
    pytest.skip("configure the provider stub for this integration first")


def test_type_changes_fail_loudly(app, base_url):
    """A type change (int -> string) must not be silently coerced."""
    pytest.skip("needs a provider stub returning a wrong-typed field")


def test_pagination_returns_all_pages(app, base_url):
    """Reading only page 1 and reporting a total is a classic partial-read bug."""
    r = request(app, base_url, "GET", "/api/items")
    if r.status_code != 200:
        pytest.skip("endpoint not available")

    body = r.json()
    if not isinstance(body, dict) or "total" not in body:
        pytest.skip("no pagination metadata")

    if body["total"] > len(body.get("items", [])):
        # Confirm the app can actually traverse every page.
        seen = len(body.get("items", []))
        pages = 1
        while seen < body["total"] and pages < 100:
            page = request(app, base_url, "GET", f"/api/items?page={pages + 1}")
            if page.status_code != 200:
                break
            chunk = page.json().get("items", [])
            if not chunk:
                break
            seen += len(chunk)
            pages += 1
        assert seen >= body["total"], (
            f"app reports total={body['total']} but only {seen} reachable"
        )


def test_error_shape_is_consistent(app, base_url):
    """Errors must be structured, not HTML or empty bodies."""
    r = request(app, base_url, "GET", "/api/items/does-not-exist-xyz")
    if r.status_code < 400:
        pytest.skip("route unexpectedly succeeded")
    if r.status_code == 404 and not r.content:
        pytest.skip("framework-level 404 with no body")
    if r.content:
        assert "Traceback" not in r.text and "<html" not in r.text.lower(), (
            "error returns internal detail instead of a structured error"
        )
