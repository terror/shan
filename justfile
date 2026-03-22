set dotenv-load

export EDITOR := 'nvim'

alias f := fmt
alias r := run

default:
  just --list

fmt:
  gleam format

fmt-check:
  gleam format --check

install:
  gleam export erlang-shipment
  printf '#!/bin/sh\nexec "{{justfile_directory()}}/build/erlang-shipment/entrypoint.sh" run "$@"\n' > ~/.local/bin/shan
  chmod +x ~/.local/bin/shan

run *args:
  gleam run {{ args }}
