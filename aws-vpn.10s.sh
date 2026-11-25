#!/usr/bin/env bash
# <swiftbar.title>AWS VPN</swiftbar.title>
# <swiftbar.desc>AWS Client VPN status and profile switching through aws-vpn-client.</swiftbar.desc>
# <swiftbar.dependencies>AWS VPN Client 6.0+</swiftbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

set -u
PATH="/usr/local/bin:/usr/bin:/bin"
VPN=aws-vpn-client
PLUGIN_NAME=$(basename "$0")
PLUGIN_NAME=${PLUGIN_NAME%%.*}

# Profile names end up inside SwiftBar parameters, where quotes and pipes would
# break the line, so only names made of these characters get a click action.
SAFE_NAME='^[A-Za-z0-9._ -]+$'

json_value() {
  plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null
}

profile_names() {
  local json name i=0
  json=$("$VPN" list-profiles 2>/dev/null) || return 0
  while name=$(json_value "$json" "$i.profile-name"); do
    printf '%s\n' "$name"
    i=$((i + 1))
  done
}

profile_status() {
  json_value "$("$VPN" get-connection-status --profile-name "$1" 2>/dev/null)" connection-status
}

# list-connections leaves out a profile that is still connecting, so each
# profile's own status is the only view that includes one.
active_profiles() {
  local name status
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    status=$(profile_status "$name")
    [[ -n "$status" && "$status" != "NotConnected" ]] && printf '%s\n' "$name"
  done < <(profile_names)
}

connected_profile() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" && "$(profile_status "$name")" == "Connected" ]] && printf '%s\n' "$name" && return 0
  done < <(profile_names)
}

# The client takes one connection at a time, so whatever is up goes down first.
disconnect_all() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] && "$VPN" disconnect --profile-name "$name" >/dev/null 2>&1
  done < <(active_profiles)
  for _ in $(seq 20); do
    [[ -z "$(active_profiles)" ]] && return 0
    sleep 0.5
  done
}

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/swiftbar-$PLUGIN_NAME"
LAST_FILE="$STATE_DIR/last-connected"
BUSY_FILE="$STATE_DIR/action-running"
mkdir -p "$STATE_DIR"

refresh_menu_bar() {
  open -g "swiftbar://refreshplugin?name=$PLUGIN_NAME"
}

urlencode() {
  local LC_ALL=C text=$1 out="" char byte i
  for ((i = 0; i < ${#text}; i++)); do
    char=${text:i:1}
    case "$char" in
    [A-Za-z0-9._~-]) out+=$char ;;
    *)
      # macOS's bash 3.2 reads bytes above 0x7F as negative numbers.
      byte=$(printf '%d' "'$char")
      out+=$(printf '%%%02X' $((byte & 255)))
      ;;
    esac
  done
  printf '%s' "$out"
}

notify() {
  open -g "swiftbar://notify?plugin=$(urlencode "$PLUGIN_NAME")&title=$(urlencode "$1")&body=$(urlencode "$2")"
}

# While a menu action runs, its in-between states are not news. A marker older
# than the longest action is left over from one that was killed.
action_running() {
  local started
  started=$(cat "$BUSY_FILE" 2>/dev/null) || return 1
  (($(date +%s) - started < 240))
}

begin_action() { date +%s >"$BUSY_FILE"; }

end_action() {
  connected_profile >"$LAST_FILE"
  rm -f "$BUSY_FILE"
}

# connect returns as soon as the attempt starts, so watch for it to come up
# through the browser sign-in, which the client allows up to 3 minutes for.
wait_until_connected() {
  for _ in $(seq 180); do
    [[ "$(profile_status "$1")" == "Connected" ]] && return 0
    sleep 1
  done
  return 1
}

case "${1:-}" in
connect)
  target=${2:?profile name required}
  profile_names | grep -Fxq -- "$target" || exit 1
  begin_action
  disconnect_all
  if ! "$VPN" connect --profile-name "$target" >/dev/null 2>&1; then
    notify "VPN didn't connect" "aws-vpn-client couldn't start connecting to $target."
  else
    refresh_menu_bar
    wait_until_connected "$target" ||
      notify "VPN didn't connect" "$target isn't connected after 3 minutes. The sign-in may have been closed or failed."
  fi
  end_action
  refresh_menu_bar
  exit 0
  ;;
disconnect)
  begin_action
  disconnect_all
  end_action
  exit 0
  ;;
esac

if ! command -v "$VPN" >/dev/null 2>&1; then
  echo " | sfimage=exclamationmark.shield"
  echo "---"
  echo "aws-vpn-client not found. Install AWS VPN Client 6.0 or later. | disabled=true"
  exit 0
fi

profiles=$(profile_names)
current=""
status=""
while IFS= read -r profile; do
  [[ -z "$profile" ]] && continue
  profile_state=$(profile_status "$profile")
  if [[ -n "$profile_state" && "$profile_state" != "NotConnected" ]]; then
    current=$profile
    status=$profile_state
    [[ "$status" == "Connected" ]] && break
  fi
done <<<"$profiles"
shown_current=${current//|/¦}

# Announce changes made outside the menu: from a terminal, the AWS app, or a
# dropped session. A connect still in progress is not a settled state yet.
if [[ -z "$current" || "$status" == "Connected" ]] && ! action_running; then
  now=""
  [[ "$status" == "Connected" ]] && now=$current
  if [[ -f "$LAST_FILE" ]]; then
    last=$(cat "$LAST_FILE")
    if [[ "$now" != "$last" ]]; then
      if [[ -z "$now" ]]; then
        notify "VPN disconnected" "$last is no longer connected."
      elif [[ -z "$last" ]]; then
        notify "VPN connected" "$now connected outside the menu."
      else
        notify "VPN switched" "Now connected to $now, was $last."
      fi
    fi
  fi
  printf '%s\n' "$now" >"$LAST_FILE"
fi

# The menu bar draws SF Symbols as template images and ignores sfcolor, so the
# grey goes through a palette rendering config, which SwiftBar takes as base64.
DIM=#8E8E93
DIM_SYMBOL=$(printf '{"renderingMode":"Palette","colors":["%s"]}' "$DIM" | base64)

if [[ -z "$current" ]]; then
  echo " | sfimage=lock.shield sfconfig=$DIM_SYMBOL"
elif [[ "$status" == "Connected" ]]; then
  echo "$shown_current | sfimage=lock.shield.fill"
else
  echo "$shown_current | sfimage=lock.shield sfconfig=$DIM_SYMBOL color=$DIM"
fi

echo "---"
echo "AWS Client VPN | size=11 disabled=true"
while IFS= read -r profile; do
  [[ -z "$profile" ]] && continue
  shown=${profile//|/¦}
  if [[ "$profile" == "$current" && "$status" == "Connected" ]]; then
    echo "$shown | checked=true"
  elif [[ "$profile" == "$current" ]]; then
    echo "$shown (connecting) | checked=true"
  elif [[ "$profile" =~ $SAFE_NAME ]]; then
    echo "$shown | bash=\"$0\" param1=connect param2=\"$profile\" terminal=false refresh=true"
  else
    echo "$shown (connect from the AWS app) | disabled=true"
  fi
done <<<"$profiles"
echo "---"
if [[ -n "$current" ]]; then
  echo "Disconnect | bash=\"$0\" param1=disconnect terminal=false refresh=true"
else
  echo "Disconnect | disabled=true"
fi
echo "---"
echo "Open AWS VPN Client | bash=/usr/bin/open param1=-a param2=\"AWS VPN Client\" terminal=false"
echo "Checked $(date +%H:%M:%S) | size=11 disabled=true"
