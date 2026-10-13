#!/usr/bin/env bats
# ============================================================
#   test/gitssh.bats — tests for the passwordless GitHub SSH
#   module (lib/gitssh.sh)
#
#   HOME points into a temp sandbox, so ~/.ssh, the generated
#   keys and the global git config live entirely inside it.
#   ssh and ssh-keygen are PATH stubs (a stateful ssh fails until
#   call N, then succeeds — no real network is ever touched);
#   git itself is real, operating on the sandbox HOME.
# ============================================================

setup() {
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
    # Copy ONLY the entry script + lib/ modules: the repo carries ~700MB of
    # website build artifacts (website/node_modules, website/.next), which a
    # full-tree cp would drag into every setup. The CLI entry script sources
    # everything it needs from its own lib/ directory.
    mkdir -p "$TEST_HOME/uo-tree/lib"
    cp "$BATS_TEST_DIRNAME/../ubuntu-optimizer.sh" "$TEST_HOME/uo-tree/"
    cp "$BATS_TEST_DIRNAME"/../lib/*.sh "$TEST_HOME/uo-tree/lib/"
    chmod +x "$TEST_HOME/uo-tree/ubuntu-optimizer.sh"
    cd "$TEST_HOME/uo-tree" || fail "cannot cd into the copied tree"

    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
}

teardown() {
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

run_uo() {
    UO_AUTO_UPDATE=0 bash "$TEST_HOME/uo-tree/ubuntu-optimizer.sh" --no-log "$@"
}

load_gitssh() {
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/common.sh"
    # shellcheck source=/dev/null
    source "$TEST_HOME/uo-tree/lib/gitssh.sh"
    SCRIPT_DIR="$TEST_HOME/uo-tree"
}

write_ssh_stubs() {
    cat > "$STUB_BIN/ssh" << 'EOF'
#!/usr/bin/env bash
# Stateful probe stub: fails until call number UO_SSH_SUCCESS_FROM,
# then answers with GitHub's success greeting.
n=$(cat "$UO_SSH_STATE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$UO_SSH_STATE"
if [ "$n" -ge "${UO_SSH_SUCCESS_FROM:-999}" ]; then
    printf 'Hi octocat! You'"'"'ve successfully authenticated, but GitHub does not provide shell access.\n' >&2
    exit 0
fi
printf 'git@github.com: Permission denied (publickey).\n' >&2
exit 255
EOF
    chmod +x "$STUB_BIN/ssh"
    cat > "$STUB_BIN/ssh-keygen" << 'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -l*) printf '256 SHA256:uoTestFingerprintHashValue0000000000 uo-test (ED25519)\n'; exit 0 ;;
esac
key=""; prev=""
for a in "$@"; do
    [ "$prev" = "-f" ] && key="$a"
    prev="$a"
done
printf '-----BEGIN OPENSSH PRIVATE KEY-----\nfake\n-----END OPENSSH PRIVATE KEY-----\n' > "$key"
printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyPayloadForTestsOnly123456 uo-test\n' > "$key.pub"
EOF
    chmod +x "$STUB_BIN/ssh-keygen"
}

# ---------- function level: key discovery ----------

@test "ssh_key_file finds ed25519 first, falls back to id_rsa, fails when none" {
    load_gitssh
    run ssh_key_file
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
    mkdir -p "$HOME/.ssh"
    printf 'rsa-key' > "$HOME/.ssh/id_rsa"
    run ssh_key_file
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.ssh/id_rsa" ]
    printf 'ed-key' > "$HOME/.ssh/id_ed25519"
    run ssh_key_file
    [ "$output" = "$HOME/.ssh/id_ed25519" ]   # ed25519 wins once present
}

# ---------- function level: probe + user parsing ----------

@test "gitssh_probe authenticates via the stub and captures GITSSH_OUT" {
    load_gitssh
    write_ssh_stubs
    export PATH="$STUB_BIN:$PATH"
    # Success path — called directly so GITSSH_OUT stays observable
    # (a bats `run` would isolate the variable in its subshell)
    UO_SSH_STATE="$TEST_HOME/ssh-state-ok" UO_SSH_SUCCESS_FROM=1 gitssh_probe
    [ "$?" -eq 0 ]
    [[ "$GITSSH_OUT" == *"successfully authenticated"* ]]
    # Failure path — permission denied, non-zero status; called directly so
    # the captured GITSSH_OUT stays observable (see above)
    local rc=0
    UO_SSH_STATE="$TEST_HOME/ssh-state-bad" UO_SSH_SUCCESS_FROM=99 gitssh_probe || rc=$?
    [ "$rc" -eq 1 ]
    [[ "$GITSSH_OUT" == *"Permission denied"* ]]
}

@test "gitssh_github_user extracts the username from the Hi <user>! greeting" {
    load_gitssh
    GITSSH_OUT="Hi octo-cat! You've successfully authenticated, but GitHub does not provide shell access."
    run gitssh_github_user
    [ "$status" -eq 0 ]
    [ "$output" = "octo-cat" ]
    GITSSH_OUT="git@github.com: Permission denied (publickey)."
    run gitssh_github_user
    [ "$output" = "" ]
}

# ---------- function level: https → ssh URL rewrite ----------

@test "gitssh_rewrite_enabled tracks the global git config" {
    load_gitssh
    run gitssh_rewrite_enabled
    [ "$status" -eq 1 ]
    git config --global url."git@github.com:".insteadOf "https://github.com/"
    run gitssh_rewrite_enabled
    [ "$status" -eq 0 ]
}

@test "gitssh_enable_rewrite writes the config with -y, is idempotent and respects a decline" {
    load_gitssh
    ASSUME_YES=1 run gitssh_enable_rewrite
    [ "$status" -eq 0 ]
    gitssh_rewrite_enabled
    [[ "$output" == *"Enabled"* ]]
    ASSUME_YES=1 run gitssh_enable_rewrite       # second call → already on
    [ "$status" -eq 0 ]
    [[ "$output" == *"already enabled"* ]]
    [ "$(grep -c 'insteadOf' "$HOME/.gitconfig")" -eq 1 ]
    # Declined confirmation leaves the config untouched
    git config --global --unset url."git@github.com:".insteadOf
    decline_rewrite() { gitssh_enable_rewrite < /dev/null; }
    run decline_rewrite
    [ "$status" -eq 0 ]
    [[ "$output" == *"Declined"* ]]
    ! gitssh_rewrite_enabled
}

@test "gitssh_disable_rewrite unsets the entry and reports when already off" {
    load_gitssh
    git config --global url."git@github.com:".insteadOf "https://github.com/"
    run gitssh_disable_rewrite
    [ "$status" -eq 0 ]
    [[ "$output" == *"URL rewriting disabled."* ]]
    ! gitssh_rewrite_enabled
    run gitssh_disable_rewrite
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already disabled."* ]]
}

# ---------- function level: status + wizard ----------

@test "gitssh_status is read-only and reports key, auth and rewrite state" {
    load_gitssh
    write_ssh_stubs
    export PATH="$STUB_BIN:$PATH"
    UO_SSH_STATE="$TEST_HOME/ssh-state" run gitssh_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"No SSH key exists"* ]]
    [[ "$output" == *"GitHub authentication is not working"* ]]
    [[ "$output" == *"URL rewriting disabled"* ]]
    # With a key present the fingerprint is shown and the hint appears
    mkdir -p "$HOME/.ssh"
    printf 'fake-private' > "$HOME/.ssh/id_ed25519"
    UO_SSH_STATE="$TEST_HOME/ssh-state2" run gitssh_status
    [[ "$output" == *"Key: $HOME/.ssh/id_ed25519"* ]]
    [[ "$output" == *"SHA256:uoTestFingerprintHashValue0000000000"* ]]
    [[ "$output" == *"add the public key"* ]]
}

@test "gitssh_setup generates a key, waits for the probe and enables the rewrite" {
    load_gitssh
    write_ssh_stubs
    export PATH="$STUB_BIN:$PATH"
    git config --global user.email "test@example.com"
    UO_SSH_STATE="$TEST_HOME/ssh-state" UO_SSH_SUCCESS_FROM=2 ASSUME_YES=1 run gitssh_setup
    [ "$status" -eq 0 ]
    [[ "$output" == *"Generating an ed25519 key"* ]]
    [[ "$output" == *"Key generated: $HOME/.ssh/id_ed25519"* ]]
    [[ "$output" == *"GitHub authentication successful"*"octocat"* ]]
    [[ "$output" == *"Setup complete"* ]]
    [ -f "$HOME/.ssh/id_ed25519" ]
    [ -f "$HOME/.ssh/id_ed25519.pub" ]
    gitssh_rewrite_enabled
}

@test "gitssh_setup short-circuits when authentication already works" {
    load_gitssh
    write_ssh_stubs
    export PATH="$STUB_BIN:$PATH"
    UO_SSH_STATE="$TEST_HOME/ssh-state" UO_SSH_SUCCESS_FROM=1 ASSUME_YES=1 run gitssh_setup
    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH is already set up!"*"octocat"* ]]
    [ ! -e "$HOME/.ssh/id_ed25519" ]          # no key was generated
    gitssh_rewrite_enabled                    # only the missing rewrite was applied
}

# ---------- CLI level ----------

@test "cli: --git-ssh-status is read-only and reports the degraded state" {
    # The stub keeps the probe offline and fast on every host
    # (real ssh would dial github.com:22 with a 10s timeout).
    write_ssh_stubs
    UO_SSH_STATE="$TEST_HOME/ssh-state" PATH="$STUB_BIN:$PATH" run run_uo --git-ssh-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub SSH Status"* ]]
    [[ "$output" == *"No SSH key exists"* ]]
    [[ "$output" == *"GitHub authentication is not working"* ]]
}
