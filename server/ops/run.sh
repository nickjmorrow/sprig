#!/bin/zsh
# Launched by launchd on Edgar (com.nicholai.bouquet). Loads ANTHROPIC_API_KEY from ~/.zshrc.local
# at runtime so it never lives in the plist or this repo.
source ~/.zshrc.local
cd "${0:A:h}/.."
exec /opt/homebrew/bin/uv run --frozen bouquet serve
