import base64, hashlib, hmac, json, time

from .config import settings


def _sig(body: str) -> str:
    return hmac.new(settings.secret_key.encode(), body.encode(), hashlib.sha256).hexdigest()


def make_token(uid: str, role: str, ttl: int = 30 * 86400) -> str:
    body = base64.urlsafe_b64encode(json.dumps({"uid": uid, "role": role, "exp": int(time.time()) + ttl}).encode()).decode().rstrip("=")
    return f"{body}.{_sig(body)}"


def verify_token(token: str):
    try:
        body, sig = token.rsplit(".", 1)
        if not hmac.compare_digest(sig, _sig(body)):
            return None
        data = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
        return data if data["exp"] > time.time() else None
    except Exception:
        return None
