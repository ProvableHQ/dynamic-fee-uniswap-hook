#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p lib
install_dep() {
  local name="$1" url="$2" revision="$3"
  if [ -d "lib/$name/.git" ] && git -C "lib/$name" rev-parse HEAD >/dev/null 2>&1; then
    test "$(git -C "lib/$name" rev-parse HEAD)" = "$revision" || {
      echo "Unexpected dependency revision: $name" >&2; exit 1;
    }
    test -z "$(git -C "lib/$name" status --porcelain)" || {
      echo "Modified dependency: $name" >&2; exit 1;
    }
    return
  fi
  git init -q "lib/$name"
  git -C "lib/$name" fetch -q --depth 1 "$url" "$revision"
  git -C "lib/$name" checkout -q --detach FETCH_HEAD
}
install_dep uniswap-hooks https://github.com/OpenZeppelin/uniswap-hooks.git b5f10574f943911635754dd76ed6ce95858b7d93
install_dep openzeppelin-contracts https://github.com/OpenZeppelin/openzeppelin-contracts.git fcbae5394ae8ad52d8e580a3477db99814b9d565
install_dep v4-core https://github.com/Uniswap/v4-core.git d153b048868a60c2403a3ef5b2301bb247884d46
install_dep forge-std https://github.com/foundry-rs/forge-std.git a6d71da563bbb8d6eef8fbec3a16c61c603d2764
install_dep solmate https://github.com/transmissions11/solmate.git 4b47a19038b798b4a33d9749d25e570443520647
