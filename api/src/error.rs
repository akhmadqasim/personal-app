//! API error type and its JSON representation.

use serde::Serialize;
use serde_json::{Value, json};
use worker::{Response, console_error};

/// One validation problem on one pushed row.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct FieldError {
    /// Table the row belongs to (empty when unknown).
    pub table: String,
    /// Row id (empty when unknown).
    pub id: String,
    /// Human-readable reason.
    pub message: String,
}

/// Every failure the API can report. Maps 1:1 to the status codes in the spec.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiError {
    /// 400
    BadRequest(String),
    /// 401
    Unauthorized,
    /// 404
    NotFound,
    /// 409
    Conflict(String),
    /// 413
    PayloadTooLarge(String),
    /// 415
    // Constructed by the image upload handler (Task 10).
    #[allow(dead_code)]
    UnsupportedMediaType(String),
    /// 422
    Validation(Vec<FieldError>),
    /// 500 — detail is logged, never returned.
    Internal(String),
}

/// Result alias used by handlers and helpers.
pub type ApiResult<T> = Result<T, ApiError>;

impl ApiError {
    /// HTTP status for this error.
    pub fn status(&self) -> u16 {
        match self {
            Self::BadRequest(_) => 400,
            Self::Unauthorized => 401,
            Self::NotFound => 404,
            Self::Conflict(_) => 409,
            Self::PayloadTooLarge(_) => 413,
            Self::UnsupportedMediaType(_) => 415,
            Self::Validation(_) => 422,
            Self::Internal(_) => 500,
        }
    }

    /// Stable machine-readable code.
    pub fn code(&self) -> &'static str {
        match self {
            Self::BadRequest(_) => "bad_request",
            Self::Unauthorized => "unauthorized",
            Self::NotFound => "not_found",
            Self::Conflict(_) => "conflict",
            Self::PayloadTooLarge(_) => "payload_too_large",
            Self::UnsupportedMediaType(_) => "unsupported_media_type",
            Self::Validation(_) => "validation_failed",
            Self::Internal(_) => "internal",
        }
    }

    /// Message shown to the client.
    pub fn message(&self) -> String {
        match self {
            Self::BadRequest(m)
            | Self::Conflict(m)
            | Self::PayloadTooLarge(m)
            | Self::UnsupportedMediaType(m) => m.clone(),
            Self::Unauthorized => "missing or invalid bearer token".into(),
            Self::NotFound => "resource not found".into(),
            Self::Validation(errors) => format!("{} validation error(s)", errors.len()),
            Self::Internal(_) => "internal error".into(),
        }
    }

    /// JSON body as defined in the spec.
    pub fn to_json(&self) -> Value {
        let mut body = json!({ "code": self.code(), "message": self.message() });
        if let Self::Validation(errors) = self {
            body["errors"] = json!(errors);
        }
        body
    }

    /// Builds the HTTP response; internal details go to the Worker log only.
    pub fn into_response(self) -> worker::Result<Response> {
        if let Self::Internal(detail) = &self {
            console_error!("internal error: {detail}");
        }
        Ok(Response::from_json(&self.to_json())?.with_status(self.status()))
    }
}

impl From<worker::Error> for ApiError {
    fn from(err: worker::Error) -> Self {
        Self::Internal(err.to_string())
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    #[test]
    fn unauthorized_maps_to_401_and_code() {
        let err = ApiError::Unauthorized;
        assert_eq!(err.status(), 401);
        assert_eq!(
            err.to_json(),
            json!({ "code": "unauthorized", "message": "missing or invalid bearer token" })
        );
    }

    #[test]
    fn validation_includes_field_errors() {
        let err = ApiError::Validation(vec![FieldError {
            table: "exercise".into(),
            id: "abc".into(),
            message: "name is required".into(),
        }]);
        assert_eq!(err.status(), 422);
        let json = err.to_json();
        assert_eq!(json["code"], "validation_failed");
        assert_eq!(json["errors"][0]["table"], "exercise");
        assert_eq!(json["errors"][0]["message"], "name is required");
    }

    #[test]
    fn internal_never_leaks_details() {
        let err = ApiError::Internal("secret db path".into());
        assert_eq!(err.status(), 500);
        assert_eq!(err.to_json()["message"], "internal error");
    }

    #[test]
    fn every_variant_has_expected_status() {
        let cases = [
            (ApiError::BadRequest("x".into()), 400, "bad_request"),
            (ApiError::NotFound, 404, "not_found"),
            (ApiError::Conflict("x".into()), 409, "conflict"),
            (
                ApiError::PayloadTooLarge("x".into()),
                413,
                "payload_too_large",
            ),
            (
                ApiError::UnsupportedMediaType("x".into()),
                415,
                "unsupported_media_type",
            ),
        ];
        for (err, status, code) in cases {
            assert_eq!(err.status(), status);
            assert_eq!(err.code(), code);
        }
    }
}
