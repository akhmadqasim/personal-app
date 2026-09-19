//! Static bearer token check. The token is the `API_TOKEN` Worker secret.

use subtle::ConstantTimeEq;
use worker::{Env, Request};

use crate::error::{ApiError, ApiResult};

const SECRET_NAME: &str = "API_TOKEN";

/// Pure check: `Authorization: Bearer <token>` must equal `expected` byte for byte.
pub fn is_authorized(header: Option<&str>, expected: &str) -> bool {
    if expected.is_empty() {
        return false;
    }
    let Some(token) = header.and_then(|h| h.strip_prefix("Bearer ")) else {
        return false;
    };
    bool::from(token.as_bytes().ct_eq(expected.as_bytes()))
}

/// Rejects the request unless it carries the configured token.
pub fn require(req: &Request, env: &Env) -> ApiResult<()> {
    let expected = env
        .secret(SECRET_NAME)
        .map_err(|_| ApiError::Internal(format!("{SECRET_NAME} secret is not configured")))?
        .to_string();
    let header = req.headers().get("authorization")?;
    if is_authorized(header.as_deref(), &expected) {
        Ok(())
    } else {
        Err(ApiError::Unauthorized)
    }
}

#[cfg(test)]
mod tests {
    use super::is_authorized;

    #[test]
    fn accepts_exact_bearer_token() {
        assert!(is_authorized(Some("Bearer s3cret"), "s3cret"));
    }

    #[test]
    fn rejects_missing_wrong_or_malformed() {
        assert!(!is_authorized(None, "s3cret"));
        assert!(!is_authorized(Some("Bearer nope"), "s3cret"));
        assert!(!is_authorized(Some("s3cret"), "s3cret"));
        assert!(!is_authorized(Some("bearer s3cret"), "s3cret"));
        assert!(!is_authorized(Some("Bearer s3cret "), "s3cret"));
    }

    #[test]
    fn rejects_when_expected_is_empty() {
        assert!(!is_authorized(Some("Bearer "), ""));
    }
}
