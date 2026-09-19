//! Boots `wrangler dev` with local D1/R2 state for the duration of the test binary.

use std::fs;
use std::net::TcpListener;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

/// The `API_TOKEN` the dev server is started with.
pub const TOKEN: &str = "test-token";

/// A `wrangler dev` process plus the port it listens on.
pub struct DevServer {
    child: Child,
    port: u16,
}

impl DevServer {
    /// Wipes local state, applies migrations, starts the dev server and waits for /api/health.
    pub fn start() -> Self {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let state = root.join(".wrangler").join("test-state");
        let _ = fs::remove_dir_all(&state);
        apply_migrations(root, &state);

        let port = free_port();
        let mut cmd = Command::new(npx());
        cmd.args([
            "wrangler",
            "dev",
            "--port",
            &port.to_string(),
            "--ip",
            "127.0.0.1",
            "--var",
            &format!("API_TOKEN:{TOKEN}"),
            "--persist-to",
            &state.to_string_lossy(),
            "--log-level",
            "warn",
        ])
        .current_dir(root)
        .stdin(Stdio::null());
        configure_process_group(&mut cmd);
        let child = cmd.spawn().expect("failed to spawn wrangler dev");

        let server = Self { child, port };
        server.wait_until_healthy(Duration::from_secs(300));
        server
    }

    /// Base URL every test client talks to.
    pub fn base_url(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    fn wait_until_healthy(&self, timeout: Duration) {
        let url = format!("{}/api/health", self.base_url());
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if let Ok(resp) = reqwest::blocking::get(&url)
                && resp.status().is_success()
            {
                return;
            }
            std::thread::sleep(Duration::from_millis(500));
        }
        panic!("wrangler dev did not become healthy within {timeout:?}");
    }
}

impl Drop for DevServer {
    fn drop(&mut self) {
        kill_tree(&mut self.child);
    }
}

fn apply_migrations(root: &Path, state: &Path) {
    let status = Command::new(npx())
        .args([
            "wrangler",
            "d1",
            "migrations",
            "apply",
            "DB",
            "--local",
            "--persist-to",
            &state.to_string_lossy(),
        ])
        .current_dir(root)
        .stdin(Stdio::null())
        .status()
        .expect("failed to run wrangler d1 migrations apply");
    assert!(status.success(), "migrations failed");
}

fn npx() -> &'static str {
    if cfg!(windows) { "npx.cmd" } else { "npx" }
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .expect("bind")
        .local_addr()
        .expect("addr")
        .port()
}

/// Gives the dev server its own process group so `kill_tree` can take down the
/// `node`/`workerd` children `npx` spawns. Windows needs nothing here: `taskkill /T`
/// walks the tree by pid instead.
#[cfg(unix)]
fn configure_process_group(cmd: &mut Command) {
    use std::os::unix::process::CommandExt;

    cmd.process_group(0);
}

#[cfg(not(unix))]
fn configure_process_group(_cmd: &mut Command) {}

#[cfg(windows)]
fn kill_tree(child: &mut Child) {
    let _ = Command::new("taskkill")
        .args(["/PID", &child.id().to_string(), "/T", "/F"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = child.wait();
}

/// Kills the whole process group (negative pid), not just `npx`: killing `npx` alone
/// leaves `wrangler` and `workerd` running.
#[cfg(not(windows))]
fn kill_tree(child: &mut Child) {
    let _ = Command::new("kill")
        .args(["-9", &format!("-{}", child.id())])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = child.wait();
}
