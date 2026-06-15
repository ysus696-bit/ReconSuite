#!/usr/bin/env bash
# ============================================================
#  ReconSuite - Automated Pentesting Framework
#  Andres Rojas - 2026
#  Nmap → Gobuster/ffuf → Nikto → Nuclei → HTML Report
# ============================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Config ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_BASE="$SCRIPT_DIR/reports"
WORDLIST_DIR="/usr/share/wordlists"
DEFAULT_WORDLIST="$WORDLIST_DIR/dirb/common.txt"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE=""
SESSION_ID=""

# ── Tool Availability ────────────────────────────────────────
declare -A TOOLS_STATUS
REQUIRED_TOOLS=("nmap" "gobuster" "nikto" "nuclei" "python3")
OPTIONAL_TOOLS=("ffuf" "whatweb" "curl")

# ── Banner ───────────────────────────────────────────────────
print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
 ██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗
 ██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║
 ██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║
 ██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║
 ██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║
 ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝
  ███████╗██╗   ██╗██╗████████╗███████╗
  ██╔════╝██║   ██║██║╚══██╔══╝██╔════╝
  ███████╗██║   ██║██║   ██║   █████╗
  ╚════██║██║   ██║██║   ██║   ██╔══╝
  ███████║╚██████╔╝██║   ██║   ███████╗
  ╚══════╝ ╚═════╝ ╚═╝   ╚═╝   ╚══════╝
EOF
    echo -e "${RESET}"
    echo -e "${DIM}  Automated Pentesting Framework v1.0 │ by Andres Rojas${RESET}"
    echo -e "${DIM}  Nmap → Gobuster → Nikto → Nuclei → HTML Report${RESET}"
    echo ""
}

# ── Logging ──────────────────────────────────────────────────
log() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date +"%H:%M:%S")
    case "$level" in
        INFO)  echo -e "${CYAN}[${timestamp}] ${GREEN}[INFO]${RESET}  $msg" ;;
        WARN)  echo -e "${CYAN}[${timestamp}] ${YELLOW}[WARN]${RESET}  $msg" ;;
        ERROR) echo -e "${CYAN}[${timestamp}] ${RED}[ERROR]${RESET} $msg" ;;
        STEP)  echo -e "\n${BOLD}${BLUE}━━━ $msg ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" ;;
        OK)    echo -e "${CYAN}[${timestamp}] ${GREEN}[✓]${RESET}    $msg" ;;
        SKIP)  echo -e "${CYAN}[${timestamp}] ${DIM}[SKIP]${RESET}  $msg" ;;
    esac
    # Also write to log file if set
    if [[ -n "$LOG_FILE" ]]; then
        echo "[${timestamp}] [${level}] $msg" >> "$LOG_FILE"
    fi
}

# ── Dependency Check ─────────────────────────────────────────
check_dependencies() {
    log STEP "Checking Dependencies"
    local missing=()

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            TOOLS_STATUS[$tool]="ok"
            log OK "$tool found ($(command -v "$tool"))"
        else
            TOOLS_STATUS[$tool]="missing"
            log ERROR "$tool NOT FOUND"
            missing+=("$tool")
        fi
    done

    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            TOOLS_STATUS[$tool]="ok"
            log OK "$tool found (optional)"
        else
            TOOLS_STATUS[$tool]="missing"
            log WARN "$tool not found (optional)"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Missing required tools: ${missing[*]}${RESET}"
        echo -e "${YELLOW}Install with:${RESET}"
        echo "  sudo apt update && sudo apt install -y nmap gobuster nikto python3"
        echo "  go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
        echo ""
        read -r -p "Continue anyway? Some modules will be skipped. [y/N] " cont
        [[ "$cont" =~ ^[Yy]$ ]] || exit 1
    fi
}

# ── Target Input ─────────────────────────────────────────────
select_targets() {
    echo ""
    echo -e "${BOLD}Target Selection${RESET}"
    echo -e "${DIM}────────────────────────────────────────${RESET}"
    echo "  1) Single IP or hostname"
    echo "  2) Load from file (one target per line)"
    echo "  3) CIDR range (e.g. 192.168.1.0/24)"
    echo ""
    read -r -p "  Choose [1-3]: " choice

    case "$choice" in
        1)
            read -r -p "  Enter IP / hostname: " TARGET_INPUT
            TARGETS=("$TARGET_INPUT")
            ;;
        2)
            read -r -p "  Path to targets file: " TARGET_FILE
            if [[ ! -f "$TARGET_FILE" ]]; then
                log ERROR "File not found: $TARGET_FILE"
                exit 1
            fi
            mapfile -t TARGETS < "$TARGET_FILE"
            log INFO "Loaded ${#TARGETS[@]} targets from file"
            ;;
        3)
            read -r -p "  Enter CIDR range: " CIDR
            TARGETS=("$CIDR")
            ;;
        *)
            log ERROR "Invalid option"
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}Targets queued:${RESET}"
    for t in "${TARGETS[@]}"; do
        echo -e "  ${CYAN}→${RESET} $t"
    done
    echo ""
}

# ── Scan Profile Selection ───────────────────────────────────
select_scan_profile() {
    echo -e "${BOLD}Scan Profile${RESET}"
    echo -e "${DIM}────────────────────────────────────────${RESET}"
    echo "  1) Quick   - Top 1000 ports, fast discovery"
    echo "  2) Standard - Top 5000 ports, service versions"
    echo "  3) Full    - All 65535 ports + scripts (slow)"
    echo "  4) Stealth - SYN scan, low profile (requires root)"
    echo "  5) Custom  - I'll set my own Nmap flags"
    echo ""
    read -r -p "  Choose [1-5]: " profile

    case "$profile" in
        1) NMAP_FLAGS="-T4 --top-ports 1000 -sV"
           PROFILE_NAME="Quick" ;;
        2) NMAP_FLAGS="-T4 --top-ports 5000 -sV -sC"
           PROFILE_NAME="Standard" ;;
        3) NMAP_FLAGS="-T4 -p- -sV -sC --min-rate 5000"
           PROFILE_NAME="Full" ;;
        4) NMAP_FLAGS="-sS -T2 --top-ports 1000 -sV"
           PROFILE_NAME="Stealth"
           [[ $EUID -ne 0 ]] && log WARN "Stealth scan requires root. May fallback to TCP connect."
           ;;
        5) read -r -p "  Enter custom Nmap flags: " NMAP_FLAGS
           PROFILE_NAME="Custom" ;;
        *) NMAP_FLAGS="-T4 --top-ports 1000 -sV"
           PROFILE_NAME="Quick" ;;
    esac
    log INFO "Profile: $PROFILE_NAME | Flags: $NMAP_FLAGS"
}

# ── Module Selection ─────────────────────────────────────────
select_modules() {
    echo ""
    echo -e "${BOLD}Modules to run${RESET}"
    echo -e "${DIM}────────────────────────────────────────${RESET}"
    echo "  [A] All modules (recommended)"
    echo "  [C] Custom selection"
    echo ""
    read -r -p "  Choose [A/C]: " mod_choice

    if [[ "$mod_choice" =~ ^[Aa]$ ]]; then
        RUN_NMAP=true
        RUN_GOBUSTER=true
        RUN_NIKTO=true
        RUN_NUCLEI=true
        RUN_WHATWEB=true
    else
        echo ""
        echo "Toggle modules (y/n):"
        read -r -p "  Nmap port scan?      [Y/n] " r; [[ "$r" =~ ^[Nn]$ ]] && RUN_NMAP=false || RUN_NMAP=true
        read -r -p "  Gobuster dir enum?   [Y/n] " r; [[ "$r" =~ ^[Nn]$ ]] && RUN_GOBUSTER=false || RUN_GOBUSTER=true
        read -r -p "  Nikto web scan?      [Y/n] " r; [[ "$r" =~ ^[Nn]$ ]] && RUN_NIKTO=false || RUN_NIKTO=true
        read -r -p "  Nuclei CVE scan?     [Y/n] " r; [[ "$r" =~ ^[Nn]$ ]] && RUN_NUCLEI=false || RUN_NUCLEI=true
        read -r -p "  WhatWeb fingerprint? [Y/n] " r; [[ "$r" =~ ^[Nn]$ ]] && RUN_WHATWEB=false || RUN_WHATWEB=true
    fi
}

# ── Wordlist Selection ───────────────────────────────────────
select_wordlist() {
    if [[ "$RUN_GOBUSTER" == true ]]; then
        echo ""
        echo -e "${BOLD}Wordlist for Gobuster${RESET}"
        echo -e "${DIM}────────────────────────────────────────${RESET}"
        echo "  1) common.txt       (~4.6k entries, fast)"
        echo "  2) medium.txt       (~20k entries, balanced)"
        echo "  3) big.txt          (~20k entries, thorough)"
        echo "  4) directory-list-2.3-medium (~220k, slow)"
        echo "  5) Custom path"
        echo ""
        read -r -p "  Choose [1-5]: " wl_choice
        case "$wl_choice" in
            1) WORDLIST="$WORDLIST_DIR/dirb/common.txt" ;;
            2) WORDLIST="$WORDLIST_DIR/dirb/big.txt" ;;
            3) WORDLIST="$WORDLIST_DIR/dirbuster/directory-list-2.3-medium.txt" ;;
            4) WORDLIST="$WORDLIST_DIR/dirbuster/directory-list-2.3-medium.txt" ;;
            5) read -r -p "  Custom path: " WORDLIST ;;
            *) WORDLIST="$DEFAULT_WORDLIST" ;;
        esac

        if [[ ! -f "$WORDLIST" ]]; then
            log WARN "Wordlist not found: $WORDLIST"
            log WARN "Falling back to common.txt — install wordlists: sudo apt install wordlists"
            WORDLIST="/usr/share/wordlists/dirb/common.txt"
        fi
        log INFO "Wordlist: $WORDLIST"
    fi
}

# ── Setup Output Dir ─────────────────────────────────────────
setup_output() {
    local target_safe
    target_safe=$(echo "$1" | tr '/:.' '_' | tr -d ' ')
    SESSION_ID="${target_safe}_${TIMESTAMP}"
    local outdir="$OUTPUT_BASE/$SESSION_ID"
    mkdir -p "$outdir"/{nmap,gobuster,nikto,nuclei,whatweb}
    LOG_FILE="$outdir/session.log"
    echo "$outdir"
}

# ── Detect Web Ports ─────────────────────────────────────────
detect_web_ports() {
    local nmap_xml="$1"
    local web_ports=()

    if [[ -f "$nmap_xml" ]]; then
        # Parse open ports that are likely web services
        while IFS= read -r line; do
            web_ports+=("$line")
        done < <(python3 -c "
import xml.etree.ElementTree as ET
import sys
try:
    tree = ET.parse('$nmap_xml')
    root = tree.getroot()
    for host in root.findall('host'):
        ports = host.find('ports')
        if ports:
            for port in ports.findall('port'):
                state = port.find('state')
                service = port.find('service')
                if state is not None and state.get('state') == 'open':
                    portid = port.get('portid')
                    svc = service.get('name', '') if service is not None else ''
                    if svc in ['http','https','http-alt','http-proxy','ssl/http'] or portid in ['80','443','8080','8443','8000','8888','3000','5000']:
                        print(portid)
except Exception as e:
    pass
" 2>/dev/null)
    fi

    # Default fallback
    if [[ ${#web_ports[@]} -eq 0 ]]; then
        web_ports=("80" "443")
    fi

    echo "${web_ports[@]}"
}

# ════════════════════════════════════════════════════════════
# MODULE 1 — Nmap
# ════════════════════════════════════════════════════════════
run_nmap() {
    local target="$1"
    local outdir="$2"
    log STEP "Nmap Scan → $target"

    local nmap_out="$outdir/nmap/scan"

    nmap $NMAP_FLAGS \
        -oA "$nmap_out" \
        "$target" 2>&1 | tee -a "$LOG_FILE" | grep -E "^(Nmap|PORT|[0-9]+/|Host|Service)" || true

    log OK "Nmap complete → $nmap_out.xml"
    echo "$nmap_out.xml"
}

# ════════════════════════════════════════════════════════════
# MODULE 2 — Gobuster
# ════════════════════════════════════════════════════════════
run_gobuster() {
    local target="$1"
    local outdir="$2"
    local web_ports=($3)

    log STEP "Gobuster Directory Enumeration → $target"

    for port in "${web_ports[@]}"; do
        local scheme="http"
        [[ "$port" == "443" || "$port" == "8443" ]] && scheme="https"
        local url="${scheme}://${target}:${port}"
        local out="$outdir/gobuster/port_${port}.txt"

        log INFO "Scanning $url"
        gobuster dir \
            -u "$url" \
            -w "$WORDLIST" \
            -o "$out" \
            -t 30 \
            -q \
            --no-error \
            -x php,html,txt,asp,aspx,js,json \
            2>/dev/null | tee -a "$LOG_FILE" | grep "^/" | head -50 || true

        log OK "Gobuster port $port → $out"
    done
}

# ════════════════════════════════════════════════════════════
# MODULE 3 — Nikto
# ════════════════════════════════════════════════════════════
run_nikto() {
    local target="$1"
    local outdir="$2"
    local web_ports=($3)

    log STEP "Nikto Web Scanner → $target"

    for port in "${web_ports[@]}"; do
        local scheme="http"
        [[ "$port" == "443" || "$port" == "8443" ]] && scheme="https"
        local out="$outdir/nikto/port_${port}"

        log INFO "Nikto on port $port"
        nikto -h "$target" \
              -p "$port" \
              -Format txt \
              -output "${out}.txt" \
              -nointeractive \
              2>/dev/null | tee -a "$LOG_FILE" | grep -E "^\+" | head -40 || true

        log OK "Nikto port $port → ${out}.txt"
    done
}

# ════════════════════════════════════════════════════════════
# MODULE 4 — Nuclei
# ════════════════════════════════════════════════════════════
run_nuclei() {
    local target="$1"
    local outdir="$2"
    local web_ports=($3)

    log STEP "Nuclei CVE/Template Scanner → $target"

    local urls_file="$outdir/nuclei/urls.txt"
    > "$urls_file"

    for port in "${web_ports[@]}"; do
        local scheme="http"
        [[ "$port" == "443" || "$port" == "8443" ]] && scheme="https"
        echo "${scheme}://${target}:${port}" >> "$urls_file"
    done

    # Also add plain target for network-level templates
    echo "$target" >> "$urls_file"

    local out="$outdir/nuclei/results.txt"
    local out_json="$outdir/nuclei/results.json"

    nuclei \
        -list "$urls_file" \
        -severity low,medium,high,critical \
        -tags cve,exposure,misconfig,default-login,takeover \
        -o "$out" \
        -json-export "$out_json" \
        -silent \
        -timeout 10 \
        2>/dev/null | tee -a "$LOG_FILE" | head -50 || true

    log OK "Nuclei complete → $out"
}

# ════════════════════════════════════════════════════════════
# MODULE 5 — WhatWeb
# ════════════════════════════════════════════════════════════
run_whatweb() {
    local target="$1"
    local outdir="$2"
    local web_ports=($3)

    if [[ "${TOOLS_STATUS[whatweb]:-missing}" == "missing" ]]; then
        log SKIP "WhatWeb not installed"
        return
    fi

    log STEP "WhatWeb Fingerprinting → $target"

    for port in "${web_ports[@]}"; do
        local scheme="http"
        [[ "$port" == "443" || "$port" == "8443" ]] && scheme="https"
        local url="${scheme}://${target}:${port}"
        local out="$outdir/whatweb/port_${port}.txt"

        whatweb -a 3 "$url" --log-brief="$out" 2>/dev/null | tee -a "$LOG_FILE" || true
        log OK "WhatWeb port $port → $out"
    done
}

# ════════════════════════════════════════════════════════════
# REPORT GENERATOR
# ════════════════════════════════════════════════════════════
generate_report() {
    local target="$1"
    local outdir="$2"
    local report_file="$outdir/report.html"

    log STEP "Generating HTML Report"

    # Collect data
    local nmap_data=""
    local gobuster_data=""
    local nikto_data=""
    local nuclei_data=""
    local whatweb_data=""

    [[ -f "$outdir/nmap/scan.nmap" ]] && nmap_data=$(cat "$outdir/nmap/scan.nmap")
    for f in "$outdir"/gobuster/*.txt; do
        [[ -f "$f" ]] && gobuster_data+="=== $(basename "$f") ===\n$(cat "$f")\n\n"
    done
    for f in "$outdir"/nikto/*.txt; do
        [[ -f "$f" ]] && nikto_data+="=== $(basename "$f") ===\n$(cat "$f")\n\n"
    done
    [[ -f "$outdir/nuclei/results.txt" ]] && nuclei_data=$(cat "$outdir/nuclei/results.txt")
    for f in "$outdir"/whatweb/*.txt; do
        [[ -f "$f" ]] && whatweb_data+="=== $(basename "$f") ===\n$(cat "$f")\n\n"
    done

    # Count findings
    local nf="$outdir/nuclei/results.txt"
    if [[ -f "$nf" && -s "$nf" ]]; then
        nuclei_critical=$(grep -c '\[critical\]' "$nf" 2>/dev/null || true); nuclei_critical=${nuclei_critical//[^0-9]/}; nuclei_critical=${nuclei_critical:-0}
        nuclei_high=$(grep -c '\[high\]'     "$nf" 2>/dev/null || true); nuclei_high=${nuclei_high//[^0-9]/};         nuclei_high=${nuclei_high:-0}
        nuclei_medium=$(grep -c '\[medium\]' "$nf" 2>/dev/null || true); nuclei_medium=${nuclei_medium//[^0-9]/};     nuclei_medium=${nuclei_medium:-0}
        nuclei_low=$(grep -c '\[low\]'       "$nf" 2>/dev/null || true); nuclei_low=${nuclei_low//[^0-9]/};           nuclei_low=${nuclei_low:-0}
    else
        nuclei_critical=0; nuclei_high=0; nuclei_medium=0; nuclei_low=0
    fi
    local open_ports
    open_ports=$(grep -c "open" "$outdir/nmap/scan.nmap" 2>/dev/null || true)
    open_ports=${open_ports//[^0-9]/}; open_ports=${open_ports:-0}
    # Escape data for HTML embedding
    local escape_nmap escape_gobuster escape_nikto escape_nuclei escape_whatweb
    escape_nmap=$(echo "$nmap_data" | python3 -c "import sys,html; print(html.escape(sys.stdin.read()))")
    escape_gobuster=$(printf "%b" "$gobuster_data" | python3 -c "import sys,html; print(html.escape(sys.stdin.read()))")
    escape_nikto=$(printf "%b" "$nikto_data" | python3 -c "import sys,html; print(html.escape(sys.stdin.read()))")
    escape_nuclei=$(echo "$nuclei_data" | python3 -c "import sys,html; print(html.escape(sys.stdin.read()))")
    escape_whatweb=$(printf "%b" "$whatweb_data" | python3 -c "import sys,html; print(html.escape(sys.stdin.read()))")

    python3 - "$report_file" "$target" "$TIMESTAMP" "$PROFILE_NAME" \
              "$open_ports" "$nuclei_critical" "$nuclei_high" "$nuclei_medium" "$nuclei_low" \
              "$escape_nmap" "$escape_gobuster" "$escape_nikto" "$escape_nuclei" "$escape_whatweb" << 'PYEOF'
import sys

out_file   = sys.argv[1]
target     = sys.argv[2]
ts         = sys.argv[3]
profile    = sys.argv[4]
open_ports = sys.argv[5]
n_crit     = sys.argv[6]
n_high     = sys.argv[7]
n_med      = sys.argv[8]
n_low      = sys.argv[9]
nmap_d     = sys.argv[10]
gob_d      = sys.argv[11]
nikto_d    = sys.argv[12]
nuc_d      = sys.argv[13]
wweb_d     = sys.argv[14]

date_str   = f"{ts[:4]}-{ts[4:6]}-{ts[6:8]} {ts[9:11]}:{ts[11:13]}:{ts[13:15]}"

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ReconSuite Report — {target}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Rajdhani:wght@400;600;700&display=swap" rel="stylesheet">
<style>
  :root {{
    --bg:        #080b0f;
    --surface:   #0d1117;
    --border:    #1a2332;
    --accent:    #00ff9d;
    --accent2:   #0af;
    --critical:  #ff3b5c;
    --high:      #ff7c2a;
    --medium:    #f5c400;
    --low:       #4fc3f7;
    --text:      #c9d1d9;
    --dim:       #4a5568;
    --mono:      'Share Tech Mono', monospace;
    --sans:      'Rajdhani', sans-serif;
  }}

  * {{ box-sizing: border-box; margin: 0; padding: 0; }}

  body {{
    background: var(--bg);
    color: var(--text);
    font-family: var(--sans);
    font-size: 15px;
    line-height: 1.6;
    min-height: 100vh;
  }}

  /* Grid background */
  body::before {{
    content: '';
    position: fixed;
    inset: 0;
    background-image:
      linear-gradient(rgba(0,255,157,0.03) 1px, transparent 1px),
      linear-gradient(90deg, rgba(0,255,157,0.03) 1px, transparent 1px);
    background-size: 40px 40px;
    pointer-events: none;
    z-index: 0;
  }}

  .wrapper {{ position: relative; z-index: 1; max-width: 1280px; margin: 0 auto; padding: 40px 24px; }}

  /* ── Header ── */
  .header {{
    border: 1px solid var(--border);
    background: linear-gradient(135deg, #0d1117 0%, #0a1628 100%);
    padding: 40px;
    margin-bottom: 32px;
    position: relative;
    overflow: hidden;
  }}
  .header::before {{
    content: 'RECON SUITE';
    position: absolute;
    right: -10px;
    top: -10px;
    font-family: var(--mono);
    font-size: 120px;
    font-weight: bold;
    color: rgba(0,255,157,0.03);
    pointer-events: none;
    line-height: 1;
  }}
  .header-label {{
    font-family: var(--mono);
    font-size: 11px;
    color: var(--accent);
    letter-spacing: 4px;
    text-transform: uppercase;
    margin-bottom: 12px;
  }}
  .header-target {{
    font-family: var(--mono);
    font-size: 36px;
    color: #fff;
    font-weight: bold;
    word-break: break-all;
  }}
  .header-meta {{
    margin-top: 16px;
    display: flex;
    gap: 32px;
    flex-wrap: wrap;
  }}
  .meta-item {{
    font-family: var(--mono);
    font-size: 12px;
    color: var(--dim);
  }}
  .meta-item span {{ color: var(--accent2); }}

  /* ── Stat cards ── */
  .stats-grid {{
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 16px;
    margin-bottom: 32px;
  }}
  .stat-card {{
    border: 1px solid var(--border);
    background: var(--surface);
    padding: 20px;
    text-align: center;
    position: relative;
    overflow: hidden;
    transition: border-color 0.2s;
  }}
  .stat-card:hover {{ border-color: var(--accent); }}
  .stat-card::after {{
    content: '';
    position: absolute;
    bottom: 0; left: 0; right: 0;
    height: 2px;
  }}
  .stat-card.ports::after   {{ background: var(--accent2); }}
  .stat-card.crit::after    {{ background: var(--critical); }}
  .stat-card.high::after    {{ background: var(--high); }}
  .stat-card.med::after     {{ background: var(--medium); }}
  .stat-card.low::after     {{ background: var(--low); }}

  .stat-num {{
    font-family: var(--mono);
    font-size: 42px;
    font-weight: bold;
    line-height: 1;
    margin-bottom: 6px;
  }}
  .stat-card.ports .stat-num {{ color: var(--accent2); }}
  .stat-card.crit  .stat-num {{ color: var(--critical); }}
  .stat-card.high  .stat-num {{ color: var(--high); }}
  .stat-card.med   .stat-num {{ color: var(--medium); }}
  .stat-card.low   .stat-num {{ color: var(--low); }}

  .stat-label {{
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 2px;
    color: var(--dim);
  }}

  /* ── Sections ── */
  .section {{
    margin-bottom: 24px;
    border: 1px solid var(--border);
    background: var(--surface);
    overflow: hidden;
  }}

  .section-header {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 20px;
    background: #0a0e15;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    user-select: none;
  }}
  .section-header:hover {{ background: #0d1420; }}

  .section-title {{
    font-family: var(--sans);
    font-size: 14px;
    font-weight: 700;
    letter-spacing: 2px;
    text-transform: uppercase;
    display: flex;
    align-items: center;
    gap: 10px;
  }}

  .badge {{
    font-family: var(--mono);
    font-size: 10px;
    padding: 2px 8px;
    background: rgba(0,255,157,0.1);
    border: 1px solid rgba(0,255,157,0.3);
    color: var(--accent);
  }}

  .chevron {{
    font-size: 12px;
    color: var(--dim);
    transition: transform 0.2s;
  }}
  .section.collapsed .chevron {{ transform: rotate(-90deg); }}
  .section.collapsed .section-body {{ display: none; }}

  .section-body {{
    padding: 0;
  }}

  pre {{
    font-family: var(--mono);
    font-size: 12px;
    color: #8b949e;
    padding: 20px;
    overflow-x: auto;
    white-space: pre-wrap;
    word-break: break-word;
    line-height: 1.7;
    max-height: 500px;
    overflow-y: auto;
  }}
  pre::-webkit-scrollbar {{ width: 4px; height: 4px; }}
  pre::-webkit-scrollbar-thumb {{ background: var(--border); }}

  /* Highlight severity in nuclei output */
  .nuclei-line {{ display: block; }}
  .nuclei-line:hover {{ background: rgba(255,255,255,0.02); }}

  /* ── Empty state ── */
  .empty {{
    padding: 32px;
    text-align: center;
    color: var(--dim);
    font-family: var(--mono);
    font-size: 12px;
  }}

  /* ── Footer ── */
  .footer {{
    margin-top: 40px;
    padding: 20px;
    border: 1px solid var(--border);
    text-align: center;
    font-family: var(--mono);
    font-size: 11px;
    color: var(--dim);
  }}
  .footer span {{ color: var(--accent); }}

  /* ── Nuclei severity coloring ── */
  .sev-critical {{ color: var(--critical); }}
  .sev-high     {{ color: var(--high); }}
  .sev-medium   {{ color: var(--medium); }}
  .sev-low      {{ color: var(--low); }}
  .sev-info     {{ color: var(--accent2); }}
</style>
</head>
<body>
<div class="wrapper">

  <div class="header">
    <div class="header-label">// Reconnaissance Report</div>
    <div class="header-target">{target}</div>
    <div class="header-meta">
      <div class="meta-item">DATE <span>{date_str}</span></div>
      <div class="meta-item">PROFILE <span>{profile}</span></div>
      <div class="meta-item">SESSION <span>{ts}</span></div>
      <div class="meta-item">TOOL <span>ReconSuite v1.0</span></div>
    </div>
  </div>

  <div class="stats-grid">
    <div class="stat-card ports">
      <div class="stat-num">{open_ports}</div>
      <div class="stat-label">Open Ports</div>
    </div>
    <div class="stat-card crit">
      <div class="stat-num">{n_crit}</div>
      <div class="stat-label">Critical</div>
    </div>
    <div class="stat-card high">
      <div class="stat-num">{n_high}</div>
      <div class="stat-label">High</div>
    </div>
    <div class="stat-card med">
      <div class="stat-num">{n_med}</div>
      <div class="stat-label">Medium</div>
    </div>
    <div class="stat-card low">
      <div class="stat-num">{n_low}</div>
      <div class="stat-label">Low</div>
    </div>
  </div>

  <!-- NMAP -->
  <div class="section" id="sec-nmap">
    <div class="section-header" onclick="toggle('sec-nmap')">
      <div class="section-title">
        <span>01</span>
        <span>Nmap — Port Scan</span>
        <span class="badge">{open_ports} open</span>
      </div>
      <span class="chevron">▾</span>
    </div>
    <div class="section-body">
      {'<pre>' + nmap_d + '</pre>' if nmap_d.strip() else '<div class="empty">No output captured</div>'}
    </div>
  </div>

  <!-- GOBUSTER -->
  <div class="section" id="sec-gob">
    <div class="section-header" onclick="toggle('sec-gob')">
      <div class="section-title">
        <span>02</span>
        <span>Gobuster — Directory Enum</span>
      </div>
      <span class="chevron">▾</span>
    </div>
    <div class="section-body">
      {'<pre>' + gob_d + '</pre>' if gob_d.strip() else '<div class="empty">No output captured</div>'}
    </div>
  </div>

  <!-- NIKTO -->
  <div class="section" id="sec-nikto">
    <div class="section-header" onclick="toggle('sec-nikto')">
      <div class="section-title">
        <span>03</span>
        <span>Nikto — Web Vulnerability Scan</span>
      </div>
      <span class="chevron">▾</span>
    </div>
    <div class="section-body">
      {'<pre>' + nikto_d + '</pre>' if nikto_d.strip() else '<div class="empty">No output captured</div>'}
    </div>
  </div>

  <!-- NUCLEI -->
  <div class="section" id="sec-nuc">
    <div class="section-header" onclick="toggle('sec-nuc')">
      <div class="section-title">
        <span>04</span>
        <span>Nuclei — CVE / Template Scan</span>
        <span class="badge">{int(n_crit)+int(n_high)+int(n_med)+int(n_low)} findings</span>
      </div>
      <span class="chevron">▾</span>
    </div>
    <div class="section-body">
      {'<pre id="nuclei-pre">' + nuc_d + '</pre>' if nuc_d.strip() else '<div class="empty">No findings — target may be hardened or unreachable</div>'}
    </div>
  </div>

  <!-- WHATWEB -->
  <div class="section collapsed" id="sec-www">
    <div class="section-header" onclick="toggle('sec-www')">
      <div class="section-title">
        <span>05</span>
        <span>WhatWeb — Tech Fingerprint</span>
      </div>
      <span class="chevron">▾</span>
    </div>
    <div class="section-body">
      {'<pre>' + wweb_d + '</pre>' if wweb_d.strip() else '<div class="empty">WhatWeb not installed or no web services detected</div>'}
    </div>
  </div>

  <!-- SESSION LOG -->
  <div class="section collapsed" id="sec-log">
    <div class="section-header" onclick="toggle('sec-log')">
      <div class="section-title">
        <span>06</span>
        <span>Session Log</span>
      </div>
      <span class="chevron">▾</span>
    </div>
    <div class="section-body">
      <div class="empty">See session.log in report directory</div>
    </div>
  </div>

  <div class="footer">
    Generated by <span>ReconSuite v1.0</span> — For authorized testing only —
    <span>{target}</span> — {date_str}
  </div>

</div>
<script>
function toggle(id) {{
  const el = document.getElementById(id);
  el.classList.toggle('collapsed');
}}

// Colorize nuclei output by severity
(function() {{
  const pre = document.getElementById('nuclei-pre');
  if (!pre) return;
  const lines = pre.textContent.split('\\n');
  pre.innerHTML = lines.map(line => {{
    let cls = '';
    if (line.includes('[critical]')) cls = 'sev-critical';
    else if (line.includes('[high]'))     cls = 'sev-high';
    else if (line.includes('[medium]'))   cls = 'sev-medium';
    else if (line.includes('[low]'))      cls = 'sev-low';
    else if (line.includes('[info]'))     cls = 'sev-info';
    return `<span class="nuclei-line ${{cls}}">${{line}}</span>`;
  }}).join('\\n');
}})();
</script>
</body>
</html>"""

with open(out_file, 'w') as f:
    f.write(html)

print(out_file)
PYEOF

    log OK "Report generated → $report_file"
    echo "$report_file"
}

# ════════════════════════════════════════════════════════════
# MAIN LOOP — per target
# ════════════════════════════════════════════════════════════
run_target() {
    local target="$1"
    local outdir
    outdir=$(setup_output "$target")

    echo ""
    echo -e "${BOLD}${MAGENTA}┌─────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${MAGENTA}│  TARGET: ${CYAN}$target${RESET}"
    echo -e "${BOLD}${MAGENTA}│  OUTPUT: ${DIM}$outdir${RESET}"
    echo -e "${BOLD}${MAGENTA}└─────────────────────────────────────────┘${RESET}"

    local nmap_xml=""
    local web_ports="80 443"

    # Module 1 — Nmap
    if [[ "$RUN_NMAP" == true && "${TOOLS_STATUS[nmap]:-missing}" == "ok" ]]; then
        nmap_xml=$(run_nmap "$target" "$outdir")
        web_ports=$(detect_web_ports "$nmap_xml")
        [[ -z "$web_ports" ]] && web_ports="80 443"
    else
        log SKIP "Nmap skipped"
    fi

    # Module 2 — Gobuster
    if [[ "$RUN_GOBUSTER" == true && "${TOOLS_STATUS[gobuster]:-missing}" == "ok" ]]; then
        run_gobuster "$target" "$outdir" "$web_ports"
    else
        log SKIP "Gobuster skipped"
    fi

    # Module 3 — Nikto
    if [[ "$RUN_NIKTO" == true && "${TOOLS_STATUS[nikto]:-missing}" == "ok" ]]; then
        run_nikto "$target" "$outdir" "$web_ports"
    else
        log SKIP "Nikto skipped"
    fi

    # Module 4 — Nuclei
    if [[ "$RUN_NUCLEI" == true && "${TOOLS_STATUS[nuclei]:-missing}" == "ok" ]]; then
        run_nuclei "$target" "$outdir" "$web_ports"
    else
        log SKIP "Nuclei skipped"
    fi

    # Module 5 — WhatWeb
    if [[ "$RUN_WHATWEB" == true ]]; then
        run_whatweb "$target" "$outdir" "$web_ports"
    fi

    # Generate report
    local report
    report=$(generate_report "$target" "$outdir")

    echo ""
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN}${BOLD}  SCAN COMPLETE — $target${RESET}"
    echo -e "${GREEN}  Report: ${CYAN}$report${RESET}"
    echo -e "${GREEN}  Raw data: ${DIM}$outdir${RESET}"
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# ════════════════════════════════════════════════════════════
# ENTRY POINT
# ════════════════════════════════════════════════════════════
declare -a TARGETS
RUN_NMAP=true
RUN_GOBUSTER=true
RUN_NIKTO=true
RUN_NUCLEI=true
RUN_WHATWEB=true
NMAP_FLAGS="-T4 --top-ports 1000 -sV"
PROFILE_NAME="Quick"
WORDLIST="$DEFAULT_WORDLIST"

print_banner
check_dependencies

echo ""
select_targets
select_scan_profile
select_modules
select_wordlist

echo ""
echo -e "${YELLOW}${BOLD}Starting recon on ${#TARGETS[@]} target(s)...${RESET}"
read -r -p "Press [Enter] to begin or Ctrl+C to abort..."

START_TIME=$(date +%s)

for target in "${TARGETS[@]}"; do
    [[ -z "$target" || "$target" =~ ^# ]] && continue
    run_target "$target"
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo -e "${CYAN}${BOLD}Total time: ${ELAPSED}s for ${#TARGETS[@]} target(s)${RESET}"
echo -e "${DIM}Reports saved to: $OUTPUT_BASE${RESET}"
