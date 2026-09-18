#!/usr/bin/env bash
# =============================================================================
#  smoke_test.sh — быстрые проверки install.sh без побочных эффектов на CI
#
#  Не претендует на полное покрытие: проверяет, что базовые режимы работы
#  (help/version/dry-run для каждого профиля и стека, реальная установка,
#  идемпотентность, --check до и после установки) не ломаются с кодом возврата.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT_DIR/install.sh"
PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" >/tmp/smoke_test_out.log 2>&1; then
    echo "ok    $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $desc (exit $?)"
    sed 's/^/        /' /tmp/smoke_test_out.log
    FAIL=$((FAIL + 1))
  fi
}

check_fail() {
  local desc="$1"; shift
  if "$@" >/tmp/smoke_test_out.log 2>&1; then
    echo "FAIL  $desc (ожидался ненулевой код возврата, получен 0)"
    FAIL=$((FAIL + 1))
  else
    echo "ok    $desc"
    PASS=$((PASS + 1))
  fi
}

echo "== install.sh: базовые флаги =="
check "--help завершается успешно"    bash "$INSTALL" --help
check "--version завершается успешно" bash "$INSTALL" --version

echo
echo "== install.sh: --dry-run по профилям и стекам =="
for profile in minimal standard full; do
  for stack in python node go rust generic; do
    tmp="$(mktemp -d)"
    check "--dry-run profile=$profile stack=$stack" \
      bash "$INSTALL" --dir "$tmp" --profile "$profile" --stack "$stack" --dry-run --no-git
    rm -rf "$tmp"
  done
done

echo
echo "== install.sh: неверные аргументы должны падать =="
check_fail "неизвестный профиль" bash "$INSTALL" --profile bogus --dry-run
check_fail "неизвестный стек"    bash "$INSTALL" --stack bogus --dry-run

echo
echo "== install.sh: --check на каталоге без harness должен вернуть ошибку =="
tmp="$(mktemp -d)"
check_fail "--check до установки" bash "$INSTALL" --dir "$tmp" --check
rm -rf "$tmp"

echo
echo "== install.sh: реальная установка + --check + идемпотентность =="
tmp="$(mktemp -d)"
check "установка profile=standard stack=generic" \
  bash "$INSTALL" --dir "$tmp" --profile standard --stack generic --no-ci
check "--check после установки"     bash "$INSTALL" --dir "$tmp" --check
check "повторный запуск идемпотентен (без --force)" \
  bash "$INSTALL" --dir "$tmp" --profile standard --stack generic --no-ci
for f in AGENTS.md PROGRESS.md DECISIONS.md BACKLOG.md .agent/feature_list.json Makefile scripts/verify.sh; do
  check "файл создан: $f" test -e "$tmp/$f"
done
rm -rf "$tmp"

echo
echo "=================================================="
echo "Пройдено: $PASS   Провалено: $FAIL"
[ "$FAIL" -eq 0 ]
