#!/bin/sh

# Simple bash script for updating your status and DND state in a Slack workspace.
# Uses gpg key pair for securely storing an API token to be called in the script.

# Define the secure token storage location
CONFIG_DIR="$HOME/.config/slack-status"
TOKEN_FILE="$CONFIG_DIR/slack_token.gpg"

# Ensure the configuration directory exists
mkdir -p "$CONFIG_DIR"

# Check if a valid GPG key exists for the current user
if ! gpg --list-keys "$USER" >/dev/null 2>&1; then
  echo "No valid GPG key found for user: $USER"
  echo "To create a new GPG key, run the following command:"
  echo "  gpg --full-generate-key"
  echo "Then, rerun this script after successfully creating a key."
  exit 1
fi

if [ ! -f "$TOKEN_FILE" ]; then
  echo "Slack token file not found. Let's create one now."
  echo "Enter your Slack API token:"
  read -r SLACK_TOKEN
  echo "$SLACK_TOKEN" | gpg --batch --yes --encrypt --recipient "$USER" -o "$TOKEN_FILE"
  echo "Encrypted token stored at $TOKEN_FILE"
  exit 1
fi

# Decrypt the token securely
SLACK_TOKEN=$(gpg --quiet --batch --decrypt "$TOKEN_FILE") || { echo "Failed to decrypt token"; exit 1; }

# Parse arguments for Slack status
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 \"<emoji> <status_text>\""
  exit 1
fi

STATUS_INPUT="$1"
STATUS_EMOJI=$(echo "$STATUS_INPUT" | awk '{print $1}')
STATUS_TEXT=$(echo "$STATUS_INPUT" | cut -d ' ' -f2-)
STATUS_EXPIRATION=0  # Default to no expiration

# Update Slack status
STATUS_PAYLOAD="{\"profile\":{\"status_text\":\"$STATUS_TEXT\",\"status_emoji\":\"$STATUS_EMOJI\",\"status_expiration\":$STATUS_EXPIRATION}}"

if ! curl -s -X POST "https://slack.com/api/users.profile.set" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  --data "$STATUS_PAYLOAD" | grep -q '"ok":true'; then
  echo "Failed to update status"
  exit 1
else
  echo "Status updated successfully"
fi

# Ask if the user wants to enable Do Not Disturb mode
echo "Enable Do Not Disturb mode? (y/n)"
read -r ENABLE_DND
if [ "$ENABLE_DND" = "y" ]; then
  echo "Enter DND duration in minutes:"
  read -r DND_MINUTES
  if ! curl -s -X POST "https://slack.com/api/dnd.setSnooze" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    --data "num_minutes=$DND_MINUTES" | grep -q '"ok":true'; then
    echo "Failed to set DND"
    exit 1
  else
    echo "DND enabled for $DND_MINUTES minutes"
  fi
elif [ "$ENABLE_DND" = "n" ]; then
  echo "Disable Do Not Disturb mode? (y/n)"
  read -r DISABLE_DND
  if [ "$DISABLE_DND" = "y" ]; then
    if ! curl -s -X POST "https://slack.com/api/dnd.endSnooze" \
      -H "Authorization: Bearer $SLACK_TOKEN" | grep -q '"ok":true'; then
      echo "Failed to disable DND"
      exit 1
    else
      echo "DND disabled"
    fi
  fi
fi

