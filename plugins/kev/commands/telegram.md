---
allowed-tools: Bash(bash ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/telegram-notify/scripts/send_telegram.sh:*), Bash(bash ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/telegram-notify/scripts/setup_telegram.sh:*), Bash(test -f ~/.claude/.telegram:*), Bash(source ~/.claude/.telegram:*)
description: Send a Telegram notification via your configured bot
---

Send a Telegram message using the configured bot credentials.

**If `$ARGUMENTS` is empty**, show this help text (do not run any bash commands):

```
Telegram Notify — Usage:

  /telegram <message>      Send a message to your Telegram
  /telegram                Show this help

Setup (first time):
  bash ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/telegram-notify/scripts/setup_telegram.sh

Natural language triggers:
  "notify me on Telegram when done"
  "ping me when you're finished"
  "send me a Telegram update"

Credentials stored in: ~/.claude/.telegram
```

**If `$ARGUMENTS` is provided**, do the following:

1. Check credentials exist:
```bash
test -f ~/.claude/.telegram && source ~/.claude/.telegram && [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && echo "ok"
```

2. If credentials are missing, tell the user to run the setup script. Do not proceed.

3. If credentials exist, send the message:
```bash
bash ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/telegram-notify/scripts/send_telegram.sh "$ARGUMENTS"
```

4. Confirm "Telegram notification sent!" on success, or show the error on failure.
