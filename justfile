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

run *args:
  gleam run {{ args }}
