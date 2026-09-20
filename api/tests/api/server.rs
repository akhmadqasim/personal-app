//! Boots `wrangler dev` with local D1/R2 state for the duration of the test binary.

use std::fs::{self, File};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{Duration, Instant};

/// The `API_TOKEN` the dev server is started with.
pub const TOKEN: &str = "test-token";

/// Pid of the running `wrangler dev` launcher, `0` when none is running. The watchdog in
/// `main` tears the server down from another thread, so it cannot go through `DevServer`.
static SERVER_PID: AtomicU32 = AtomicU32::new(0);

/// A `wrangler dev` process plus the port it listens on.
pub struct DevServer {
    child: Child,
    port: u16,
}

impl DevServer {
    /// Wipes local state, applies migrations, starts the dev server and waits for /api/health.
    pub fn start() -> Self {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let state = state_dir();
        let _ = fs::remove_dir_all(&state);
        apply_migrations(root, &state);
        fs::create_dir_all(&state).expect("create test state dir");

        // `wrangler dev` must not inherit the test runner's stdout: it outlives the
        // request that spawned it, and on CI a surviving child holding the step's pipe
        // open makes the step unkillable even after the job is cancelled.
        let log = File::create(log_path()).expect("create wrangler dev log");
        let log_for_stderr = log.try_clone().expect("clone wrangler dev log handle");

        let port = free_port();
        let mut cmd = Command::new("bun");
        cmd.args([
            "x",
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
            // `info`, not `warn`: the output goes to a file now, and the startup banner
            // is what tells CI whether the server ever came up.
            "--log-level",
            "info",
        ])
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(log_for_stderr));
        configure_process_group(&mut cmd);
        let child = cmd.spawn().expect("failed to spawn wrangler dev");
        SERVER_PID.store(child.id(), Ordering::SeqCst);

        let mut server = Self { child, port };
        server.wait_until_healthy(Duration::from_secs(300));
        server
    }

    /// Base URL every test client talks to.
    pub fn base_url(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    fn wait_until_healthy(&mut self, timeout: Duration) {
        let url = format!("{}/api/health", self.base_url());
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if let Ok(resp) = reqwest::blocking::get(&url)
                && resp.status().is_success()
            {
                return;
            }
            // A crashed server never becomes healthy, so fail in seconds instead of
            // burning the whole timeout on a dead port.
            if let Ok(Some(status)) = self.child.try_wait() {
                print_log_tail(60);
                panic!("wrangler dev exited before becoming healthy: {status}");
            }
            std::thread::sleep(Duration::from_millis(500));
        }
        print_log_tail(60);
        panic!("wrangler dev did not become healthy within {timeout:?}");
    }
}

impl Drop for DevServer {
    fn drop(&mut self) {
        SERVER_PID.store(0, Ordering::SeqCst);
        kill_group(self.child.id());
        // Belt and braces: if the group kill missed the launcher, `wait` below would
        // block forever, which is exactly how this harness used to hang on Linux.
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Kills the dev server tree from any thread. The watchdog calls this before aborting.
pub fn kill_running_server() {
    let pid = SERVER_PID.swap(0, Ordering::SeqCst);
    if pid != 0 {
        kill_group(pid);
    }
}

/// Directory holding the local D1/R2 state and the dev server log.
fn state_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join(".wrangler")
        .join("test-state")
}

/// Where `wrangler dev` writes its own stdout and stderr.
pub fn log_path() -> PathBuf {
    state_dir().join("wrangler-dev.log")
}

/// Prints the tail of the dev server log to stderr; the only clue when CI has no server.
pub fn print_log_tail(lines: usize) {
    let path = log_path();
    let Ok(bytes) = fs::read(&path) else {
        eprintln!("--- no wrangler dev log at {} ---", path.display());
        return;
    };
    let text = String::from_utf8_lossy(&bytes);
    let all: Vec<&str> = text.lines().collect();
    let tail = &all[all.len().saturating_sub(lines)..];
    eprintln!("--- last {} lines of {} ---", tail.len(), path.display());
    for line in tail {
        eprintln!("{line}");
    }
    eprintln!("--- end of wrangler dev log ---");
}

fn apply_migrations(root: &Path, state: &Path) {
    let status = Command::new("bun")
        .args([
            "x",
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

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .expect("bind")
        .local_addr()
        .expect("addr")
        .port()
}

/// Gives the dev server its own process group so `kill_group` can take down the
/// `node`/`esbuild`/`workerd` children `bun x` spawns. Windows needs nothing here:
/// `taskkill /T` walks the tree by pid instead.
#[cfg(unix)]
fn configure_process_group(cmd: &mut Command) {
    use std::os::unix::process::CommandExt;

    cmd.process_group(0);
}

#[cfg(not(unix))]
fn configure_process_group(_cmd: &mut Command) {}

#[cfg(windows)]
fn kill_group(pid: u32) {
    let _ = Command::new("taskkill")
        .args(["/PID", &pid.to_string(), "/T", "/F"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// Kills the whole process group, not just `bun x`.
///
/// The `--` is load-bearing. procps-ng `kill` (Ubuntu, and therefore every GitHub
/// runner) parses a leading `-<pgid>` as an option, silently does nothing and still
/// exits 0, so `node`, `esbuild` and both `workerd` processes survived and the
/// following `wait` blocked forever.
#[cfg(not(windows))]
fn kill_group(pid: u32) {
    let _ = Command::new("kill")
        .args(["-9", "--", &format!("-{pid}")])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}
