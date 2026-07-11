#!/bin/sh

lg_open_repo() {
  gh repo view --web >/dev/null 2>&1
}
