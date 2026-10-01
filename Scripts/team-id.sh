# Single source of truth for the Developer ID team this app is signed with,
# and for the one correct way to check that a bundle really carries it.
#
# `codesign -d`/`-dv` is a *display* command: it prints whatever is in the
# signature's own free-form fields and does not check that the signature is
# valid, and both its exit status and its output are attacker-controlled.
# Matching a `TeamIdentifier=…` substring in that output was reproduced
# bypassable two ways (see Sources/NativeVoice/Update/Updater.swift for the
# detail) — by an ad-hoc bundle whose `--identifier` echoes our team ID back
# on a different line, and by a signed bundle that was damaged after the
# fact. `codesign --verify` is the actual verification command; constraining
# it with `-R` to a requirement means only its exit status needs checking,
# nothing printed by it is parsed.
#
# Source this file; it is not meant to be run.
TEAM_ID="5XJALC3SPQ"

# Usage: verify_signed_by_us <path-to-app-or-dmg>
# Exit status only — see the comment above for why nothing here is parsed.
verify_signed_by_us() {
    codesign --verify --deep --strict \
        -R "=anchor apple generic and certificate leaf[subject.OU] = \"$TEAM_ID\"" \
        "$1"
}
