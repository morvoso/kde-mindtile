# Who owns Meta+Left before and after claiming, and after releasing.
owner() { gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel --method org.kde.KGlobalAccel.getGlobalShortcutsByKey $1 >&2; }
ML=$((0x10000000 | 0x01000012)); MT=$((0x10000000 | 0x54))
echo "== before" >&2; owner $ML; owner $MT
"$MT_ROOT/tools/claim-keys.sh" >&2; sleep 2
echo "== claimed" >&2; owner $ML; owner $MT
"$MT_ROOT/tools/claim-keys.sh" --release >&2; sleep 2
echo "== released" >&2; owner $ML; owner $MT
"$MT_ROOT/tools/claim-keys.sh" >&2; sleep 2
echo "== claimed again" >&2; owner $ML; owner $MT
