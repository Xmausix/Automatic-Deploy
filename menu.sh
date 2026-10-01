#!/usr/bin/env bash
set -euo pipefail


readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v dialog &> /dev/null; then
    TUI=dialog
elif command -v whiptail &> /dev/null; then
    TUI=whiptail
else
    TUI=bash
fi

show_menu() {
    if [[ "$TUI" == "dialog" ]]; then
        dialog --clear --backtitle "Deployment Manager" \
            --title "Main Menu" \
            --menu "Choose operation:" 15 50 4 \
            1 "Deploy to Environment" \
            2 "Rollback" \
            3 "View Logs" \
            4 "Status" \
            2>&1 >/dev/tty
    elif [[ "$TUI" == "whiptail" ]]; then
        whiptail --clear --backtitle "Deployment Manager" \
            --title "Main Menu" \
            --menu "Choose operation:" 15 50 4 \
            "1" "Deploy to Environment" \
            "2" "Rollback" \
            "3" "View Logs" \
            "4" "Status" \
            2>&1 >/dev/tty
    else
        echo "======================================"
        echo " Deployment Manager"
        echo "======================================"
        echo "1. Deploy to Environment"
        echo "2. Rollback"
        echo "3. View Logs"
        echo "4. Status"
        echo "5. Exit"
        read -r -p "Select: " choice
        echo "$choice"
    fi
}

deploy_menu() {
    if [[ "$TUI" == "dialog" ]]; then
        dialog --menu "Select environment:" 12 40 3 \
            1 "development" \
            2 "staging" \
            3 "production" \
            2>&1 >/dev/tty
    elif [[ "$TUI" == "whiptail" ]]; then
        whiptail --menu "Select environment:" 12 40 3 \
            "1" "development" \
            "2" "staging" \
            "3" "production" \
            2>&1 >/dev/tty
    else
        read -r -p "Environment (development/staging/production): " env
        echo "$env"
    fi
}

run_choice() {
    local choice
    choice=$(show_menu)

    case "$choice" in
        1|"Deploy to Environment")
            local env
            env=$(deploy_menu)
            case "$env" in
                1) env="development" ;;
                2) env="staging" ;;
                3) env="production" ;;
            esac
            clear
            "${SCRIPT_DIR}/deploy.sh" "$env"
            read -r -p "Press Enter to continue..."
            ;;
        2|"Rollback")
            read -r -p "Environment: " env
            read -r -p "Backup name: " backup
            clear
            "${SCRIPT_DIR}/rollback.sh" "$env" "$backup"
            read -r -p "Press Enter to continue..."
            ;;
        3|"View Logs")
            clear
            if [[ -f "${SCRIPT_DIR}/logs/deploy.log" ]]; then
                tail -n 50 "${SCRIPT_DIR}/logs/deploy.log"
            else
                echo "No logs found."
            fi
            read -r -p "Press Enter to continue..."
            ;;
        4|"Status")
            clear
            echo "Status check:"
            for conf in "${SCRIPT_DIR}/config/"*.conf; do
                local env_name
                env_name=$(basename "$conf" .conf)
                echo "  - Environment: ${env_name}"
                grep -E '^SERVICE_NAME=' "$conf" || true
                grep -E '^APP_DIR=' "$conf" || true
            done
            read -r -p "Press Enter to continue..."
            ;;
        5|"Exit"|*)
            clear
            echo "Exiting."
            exit 0
            ;;
    esac
}

clear
while true; do
    run_choice
    clear
done
