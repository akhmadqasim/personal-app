//! HTTP client and trial builder shared by all integration tests.

use std::future::Future;
use std::sync::Arc;

use libtest_mimic::Trial;
use reqwest::StatusCode;
use serde_json::{Value, json};
use tokio::runtime::Runtime;

pub use crate::server::TOKEN;

/// A thin JSON client bound to one running dev server.
#[derive(Clone)]
pub struct Client {
    http: reqwest::Client,
    base: String,
}

impl Client {
    /// Builds a client for `base`, e.g. `http://127.0.0.1:8787`.
    pub fn new(base: &str) -> Self {
        Self {
            http: reqwest::Client::new(),
            base: base.to_owned(),
        }
    }

    /// `GET path`, decoded as JSON.
    pub async fn get(&self, path: &str, token: Option<&str>) -> (StatusCode, Value) {
        let mut req = self.http.get(format!("{}{path}", self.base));
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        split(req.send().await.expect("request failed")).await
    }

    /// `GET path`, left undecoded so tests can inspect headers and raw bytes.
    pub async fn get_raw(&self, path: &str, token: Option<&str>) -> reqwest::Response {
        let mut req = self.http.get(format!("{}{path}", self.base));
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        req.send().await.expect("request failed")
    }

    /// `POST path` with a JSON body.
    pub async fn post_json(
        &self,
        path: &str,
        body: &Value,
        token: Option<&str>,
    ) -> (StatusCode, Value) {
        let mut req = self.http.post(format!("{}{path}", self.base)).json(body);
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        split(req.send().await.expect("request failed")).await
    }

    /// `POST path` with a raw body typed as JSON, for malformed-payload tests.
    pub async fn post_text(
        &self,
        path: &str,
        body: &str,
        token: Option<&str>,
    ) -> (StatusCode, Value) {
        let mut req = self
            .http
            .post(format!("{}{path}", self.base))
            .header("content-type", "application/json")
            .body(body.to_owned());
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        split(req.send().await.expect("request failed")).await
    }

    /// `PUT path` with a binary body, for image uploads.
    pub async fn put_bytes(
        &self,
        path: &str,
        bytes: Vec<u8>,
        content_type: &str,
        token: Option<&str>,
    ) -> (StatusCode, Value) {
        let mut req = self
            .http
            .put(format!("{}{path}", self.base))
            .header("content-type", content_type)
            .body(bytes);
        if let Some(t) = token {
            req = req.bearer_auth(t);
        }
        split(req.send().await.expect("request failed")).await
    }

    /// Authenticated `POST /api/sync`.
    pub async fn sync(&self, since_seq: i64, push: Value) -> (StatusCode, Value) {
        self.post_json(
            "/api/sync",
            &json!({ "since_seq": since_seq, "push": push }),
            Some(TOKEN),
        )
        .await
    }

    /// One `sync`, then follows `has_more` until caught up, merging every page's
    /// `pull` into the first response. Echo assertions need this because a single
    /// pull is capped at 500 rows across all tables.
    ///
    /// Any non-200 response is returned as-is and ends the walk, whether it is the
    /// first page or a continuation.
    pub async fn sync_all(&self, since_seq: i64, push: Value) -> (StatusCode, Value) {
        let (status, mut body) = self.sync(since_seq, push).await;
        if status != StatusCode::OK {
            return (status, body);
        }
        while body["has_more"].as_bool().unwrap_or(false) {
            let cursor = body["seq"].as_i64().expect("seq");
            let (page_status, page) = self.sync(cursor, json!({})).await;
            if page_status != StatusCode::OK {
                return (page_status, page);
            }
            merge_page(&mut body, &page);
        }
        (status, body)
    }

    /// Pulls everything after `since_seq`, following `has_more`, and returns all rows per table.
    pub async fn pull_all(&self, since_seq: i64) -> Value {
        let mut cursor = since_seq;
        let mut merged = serde_json::Map::new();
        loop {
            let (status, body) = self.sync(cursor, json!({})).await;
            assert_eq!(status, StatusCode::OK, "pull failed: {body}");
            for (table, rows) in body["pull"].as_object().expect("pull object") {
                let entry = merged.entry(table.clone()).or_insert_with(|| json!([]));
                entry
                    .as_array_mut()
                    .expect("array")
                    .extend(rows.as_array().expect("rows").iter().cloned());
            }
            cursor = body["seq"].as_i64().expect("seq");
            if !body["has_more"].as_bool().unwrap_or(false) {
                return Value::Object(merged);
            }
        }
    }
}

/// Appends `page`'s pulled rows to `acc` per table and adopts its cursor.
fn merge_page(acc: &mut Value, page: &Value) {
    for (table, rows) in page["pull"].as_object().expect("pull object") {
        let entry = acc["pull"]
            .as_object_mut()
            .expect("pull object")
            .entry(table.clone())
            .or_insert_with(|| json!([]));
        entry
            .as_array_mut()
            .expect("array")
            .extend(rows.as_array().expect("rows").iter().cloned());
    }
    acc["seq"] = page["seq"].clone();
    acc["has_more"] = page["has_more"].clone();
}

async fn split(resp: reqwest::Response) -> (StatusCode, Value) {
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    (status, serde_json::from_str(&text).unwrap_or(Value::Null))
}

/// Owns the tokio runtime every trial blocks on.
pub struct Ctx {
    rt: Arc<Runtime>,
    client: Client,
}

impl Ctx {
    /// Builds a context talking to the dev server at `base`.
    pub fn new(base: &str) -> Self {
        let rt = Runtime::new().expect("tokio runtime");
        Self {
            rt: Arc::new(rt),
            client: Client::new(base),
        }
    }

    /// Wraps an async test as a libtest-mimic trial.
    pub fn trial<F, Fut>(&self, name: &str, f: F) -> Trial
    where
        F: Fn(Client) -> Fut + Send + 'static,
        Fut: Future<Output = ()>,
    {
        let rt = Arc::clone(&self.rt);
        let client = self.client.clone();
        Trial::test(name, move || {
            rt.block_on(f(client.clone()));
            Ok(())
        })
    }
}

/// Finds a row by id inside a pulled table.
pub fn find_row<'a>(pull: &'a Value, table: &str, id: &str) -> Option<&'a Value> {
    pull[table].as_array()?.iter().find(|r| r["id"] == id)
}
