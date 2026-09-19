//! Custom exercise photos in R2. Built-in images (`builtin/…`) never touch the API.

use serde_json::{Value, json};
use worker::{Date, Headers, HttpMetadata, Request, Response, RouteContext};

use crate::db;
use crate::error::{ApiError, ApiResult};

const MAX_BYTES: usize = 5 * 1024 * 1024;
const BUCKET: &str = "IMAGES";
const CACHE_CONTROL: &str = "private, max-age=31536000, immutable";
const KEY_PREFIX: &str = "exercises/";
const TYPES: [(&str, &str); 3] = [
    ("image/jpeg", "jpg"),
    ("image/png", "png"),
    ("image/webp", "webp"),
];

/// `PUT /api/gym/exercises/:id/image` — stores the body and returns its key.
pub async fn upload(mut req: Request, ctx: RouteContext<()>) -> ApiResult<Response> {
    let id = ctx.param("id").cloned().ok_or(ApiError::NotFound)?;
    let content_type = req.headers().get("content-type")?.unwrap_or_default();
    let ext = extension_for(&content_type).ok_or_else(|| {
        ApiError::UnsupportedMediaType(format!(
            "unsupported content-type '{content_type}'; use image/jpeg, image/png or image/webp"
        ))
    })?;
    let declared = req
        .headers()
        .get("content-length")?
        .and_then(|v| v.parse::<usize>().ok());
    if declared.is_some_and(|len| len > MAX_BYTES) {
        return Err(too_large());
    }

    let db = ctx.env.d1("DB")?;
    let exists = db::query_i64(
        &db,
        "SELECT 1 AS one FROM exercise WHERE id = ?1 AND deleted_at IS NULL",
        &[Value::from(id.as_str())],
        "one",
    )
    .await?
    .is_some();
    if !exists {
        return Err(ApiError::NotFound);
    }

    let bytes = req.bytes().await?;
    if bytes.len() > MAX_BYTES {
        return Err(too_large());
    }
    if bytes.is_empty() {
        return Err(ApiError::BadRequest("empty body".into()));
    }

    let key = image_key(&id, ext, Date::now().as_millis(), nonce());
    let mime = mime_of(&content_type);
    ctx.env
        .bucket(BUCKET)?
        .put(&key, bytes)
        .http_metadata(HttpMetadata {
            content_type: Some(mime),
            cache_control: Some(CACHE_CONTROL.to_owned()),
            ..HttpMetadata::default()
        })
        .execute()
        .await?;
    Ok(Response::from_json(&json!({ "image_key": key }))?)
}

/// `GET /api/gym/images/*key` — streams the object back with its content type.
pub async fn serve(_req: Request, ctx: RouteContext<()>) -> ApiResult<Response> {
    let key = ctx.param("key").cloned().unwrap_or_default();
    if !is_valid_key(&key) {
        return Err(ApiError::NotFound);
    }
    let Some(object) = ctx.env.bucket(BUCKET)?.get(&key).execute().await? else {
        return Err(ApiError::NotFound);
    };
    let content_type = object
        .http_metadata()
        .content_type
        .unwrap_or_else(|| "application/octet-stream".to_owned());
    let Some(body) = object.body() else {
        return Err(ApiError::NotFound);
    };
    let bytes = body.bytes().await?;
    let headers = Headers::new();
    headers.set("Content-Type", &content_type)?;
    headers.set("Cache-Control", CACHE_CONTROL)?;
    Ok(Response::from_bytes(bytes)?.with_headers(headers))
}

/// File extension for an accepted image content type (parameters and case ignored).
pub fn extension_for(content_type: &str) -> Option<&'static str> {
    let mime = mime_of(content_type);
    TYPES.iter().find(|(m, _)| *m == mime).map(|(_, ext)| *ext)
}

/// Object key: namespaced per exercise, unique per upload.
pub fn image_key(exercise_id: &str, ext: &str, millis: u64, nonce: u32) -> String {
    format!("{KEY_PREFIX}{exercise_id}/{millis}-{nonce:08x}.{ext}")
}

/// Only keys this module created are served; blocks traversal-looking input.
pub fn is_valid_key(key: &str) -> bool {
    key.starts_with(KEY_PREFIX) && !key.contains("..") && !key.contains("//")
}

/// The bare mime type: parameters stripped, lowercased.
fn mime_of(content_type: &str) -> String {
    content_type
        .split(';')
        .next()
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase()
}

/// The error returned for any image above the size limit.
fn too_large() -> ApiError {
    ApiError::PayloadTooLarge(format!("image exceeds {MAX_BYTES} bytes"))
}

/// Random suffix that keeps two uploads in the same millisecond apart.
#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
fn nonce() -> u32 {
    (js_sys::Math::random() * f64::from(u32::MAX)) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_content_types_to_extensions() {
        assert_eq!(extension_for("image/jpeg"), Some("jpg"));
        assert_eq!(extension_for("image/png; charset=binary"), Some("png"));
        assert_eq!(extension_for("IMAGE/WEBP"), Some("webp"));
        assert_eq!(extension_for("image/gif"), None);
        assert_eq!(extension_for(""), None);
    }

    #[test]
    fn builds_namespaced_keys() {
        assert_eq!(
            image_key("abc", "jpg", 1_758_000_000_000, 0xdead_beef),
            "exercises/abc/1758000000000-deadbeef.jpg"
        );
    }

    #[test]
    fn validates_keys() {
        assert!(is_valid_key("exercises/abc/1-00000001.jpg"));
        assert!(!is_valid_key("exercises/../secret"));
        assert!(!is_valid_key("other/abc.jpg"));
        assert!(!is_valid_key("exercises//abc.jpg"));
        assert!(!is_valid_key(""));
    }
}
