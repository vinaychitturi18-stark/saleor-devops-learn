#!/usr/bin/env bash
# Usage:
#   ./k8s/forward.sh start   — start port-forward in background
#   ./k8s/forward.sh stop    — kill port-forward
#   ./k8s/forward.sh status  — show status

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/saleor-k8s.conf}"
PID_FILE="/tmp/saleor-forwards.pid"

export KUBECONFIG

start() {
  if [ -f "$PID_FILE" ]; then
    read -r PID < "$PID_FILE"
    if ps -p "$PID" > /dev/null 2>&1; then
      echo "Already running (PID $PID). Run './k8s/forward.sh stop' first."
      exit 1
    fi
    rm -f "$PID_FILE"
  fi

  echo "==> Starting port-forward..."

  kubectl --kubeconfig "$KUBECONFIG" port-forward \
    -n ingress-nginx svc/ingress-nginx-controller 8080:80 \
    > /tmp/saleor-fwd-8080.log 2>&1 &
  echo $! > "$PID_FILE"

  sleep 2

  if ! ps -p "$(cat $PID_FILE)" > /dev/null 2>&1; then
    echo "ERROR: Port-forward failed to start. Check /tmp/saleor-fwd-8080.log"
    cat /tmp/saleor-fwd-8080.log
    exit 1
  fi

  echo ""
  echo "==> All services available at:"
  echo "    Storefront : http://saleor.local:8080/"
  echo "    Dashboard  : http://saleor.local:8080/dashboard/"
  echo "    GraphQL    : http://saleor.local:8080/graphql/"
  echo ""
  echo "==> Stop with: ./k8s/forward.sh stop"
}

stop() {
  pkill -f "port-forward.*ingress-nginx-controller" 2>/dev/null && echo "Stopped." || echo "Nothing running."
  rm -f "$PID_FILE"
}

status() {
  if [ ! -f "$PID_FILE" ]; then
    echo "Not running."
    return
  fi
  read -r PID < "$PID_FILE"
  ps -p "$PID" -o pid,comm= 2>/dev/null && echo "(port 8080 → ingress)" || echo "NOT RUNNING (stale PID file)"
}

case "${1:-}" in
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  *)      echo "Usage: $0 {start|stop|status}" ; exit 1 ;;
esac
