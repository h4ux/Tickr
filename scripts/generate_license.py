#!/usr/bin/env python3
"""
Tickr License Generator

Generates license keys tied to email addresses.
Keys are HMAC-SHA256 based, verifiable offline in the app.

Usage:
    python3 scripts/generate_license.py user@example.com
    python3 scripts/generate_license.py --list
    python3 scripts/generate_license.py --verify user@example.com XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
"""

import sys
import hmac
import hashlib
import json
import os
from datetime import datetime

# Secret key loaded from .license_secret file (git-ignored)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SECRET_FILE = os.path.join(SCRIPT_DIR, ".license_secret")
LICENSES_FILE = os.path.join(SCRIPT_DIR, "..", "licenses.json")

if not os.path.exists(SECRET_FILE):
    print(f"Error: Secret file not found at {SECRET_FILE}")
    print("Create it with: echo 'your-secret-here' > scripts/.license_secret")
    sys.exit(1)

with open(SECRET_FILE, "r") as f:
    LICENSE_SECRET = f.read().strip()

if not LICENSE_SECRET:
    print("Error: Secret file is empty")
    sys.exit(1)


def generate_key(email: str) -> str:
    """Generate a license key from an email address."""
    email = email.strip().lower()
    raw = hmac.new(
        LICENSE_SECRET.encode(),
        email.encode(),
        hashlib.sha256
    ).hexdigest()

    # Format as 5 groups of 5 uppercase chars
    key = raw[:25].upper()
    return "-".join(key[i:i+5] for i in range(0, 25, 5))


def verify_key(email: str, key: str) -> bool:
    """Verify a license key against an email."""
    expected = generate_key(email)
    return hmac.compare_digest(expected, key)


def load_licenses() -> dict:
    """Load existing licenses from file."""
    if os.path.exists(LICENSES_FILE):
        with open(LICENSES_FILE, "r") as f:
            return json.load(f)
    return {"licenses": []}


def save_license(email: str, key: str):
    """Save a license to the licenses file."""
    data = load_licenses()
    # Check if email already has a license
    for lic in data["licenses"]:
        if lic["email"].lower() == email.lower():
            print(f"License already exists for {email}: {lic['key']}")
            return

    data["licenses"].append({
        "email": email,
        "key": key,
        "created": datetime.utcnow().isoformat() + "Z"
    })

    with open(LICENSES_FILE, "w") as f:
        json.dump(data, f, indent=2)


def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 scripts/generate_license.py user@example.com")
        print("  python3 scripts/generate_license.py --list")
        print("  python3 scripts/generate_license.py --verify email key")
        sys.exit(1)

    if sys.argv[1] == "--list":
        data = load_licenses()
        if not data["licenses"]:
            print("No licenses generated yet.")
        else:
            print(f"{'Email':<35} {'Key':<32} {'Created'}")
            print("-" * 90)
            for lic in data["licenses"]:
                print(f"{lic['email']:<35} {lic['key']:<32} {lic.get('created', 'N/A')}")
            print(f"\nTotal: {len(data['licenses'])} licenses")
        return

    if sys.argv[1] == "--verify":
        if len(sys.argv) < 4:
            print("Usage: python3 scripts/generate_license.py --verify email key")
            sys.exit(1)
        email = sys.argv[2]
        key = sys.argv[3]
        if verify_key(email, key):
            print(f"✅ Valid license for {email}")
        else:
            print(f"❌ Invalid license for {email}")
        return

    # Generate license
    email = sys.argv[1]
    if "@" not in email:
        print(f"Error: '{email}' doesn't look like an email address")
        sys.exit(1)

    key = generate_key(email)
    save_license(email, key)

    print(f"License generated!")
    print(f"  Email: {email}")
    print(f"  Key:   {key}")
    print(f"\nSaved to: {LICENSES_FILE}")


if __name__ == "__main__":
    main()
