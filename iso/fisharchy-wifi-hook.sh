# FISHARCHY: live ISO only. On the first console login, if there is no network, run the Wi-Fi setup
# before the Omarchy installer starts. Sourced by /etc/profile, so it runs ahead of root's .zlogin/.zprofile.
if [ -t 0 ] && [ "$(tty 2>/dev/null)" = /dev/tty1 ] && [ ! -e /run/fisharchy-wifi-done ] &&
   [ -x /usr/local/bin/fisharchy-wifi ] && [ -d /run/archiso ]; then
  : >/run/fisharchy-wifi-done
  if ! ip route show default 2>/dev/null | grep -q .; then
    clear
    echo "FISHARCHY: no network yet. Connect to Wi-Fi now so the install can download packages."
    echo "(Press q at the network list to skip, for example if you are installing offline.)"
    echo
    /usr/local/bin/fisharchy-wifi || true
    echo
  fi
fi
