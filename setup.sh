#!/bin/bash

set -e

function getCurrentDir() {
    local current_dir="${BASH_SOURCE%/*}"
    if [[ ! -d "${current_dir}" ]]; then current_dir="$PWD"; fi
    echo "${current_dir}"
}

function includeDependencies() {
    # shellcheck source=./setupLibrary.sh
    source "${current_dir}/setupLibrary.sh"
}

current_dir=$(getCurrentDir)
includeDependencies
output_file="output.log"

function main() {
    read -rp "Enter the username of the new user account:" username

    echo "Please specify your Git Global Name & Email" 
    read -rp 'Your (git) Name: ' git_name 
    read -rp 'Your (git) Email Address: ' git_email 

    promptForPassword

    # Run setup functions
    trap cleanup EXIT SIGHUP SIGINT SIGTERM

    addUserAccount "${username}" "${password}"

    read -rp $'Paste in the public SSH key for the new user:\n' sshKey
    echo 'Running setup script...'
    logTimestamp "${output_file}"

    # Use exec and tee to redirect logs to stdout and a log file at the same time 
    # https://unix.stackexchange.com/a/145654
    exec > >(tee -a "${output_file}") 2>&1
    disableSudoPassword "${username}"
    addSSHKey "${username}" "${sshKey}"
    changeSSHConfig
    furtherHardening
    setupUfw

    if ! hasSwap; then
        setupSwap
    fi

    setupTimezone

    echo "Installing Network Time Protocol... " >&3
    configureNTP

    sudo service ssh restart

    cleanup

    echo "Setup Done! Log file is located at ${output_file}" >&3
}

function setupSwap() {
    createSwap
    mountSwap
    tweakSwapSettings "10" "50"
    saveSwapSettings "10" "50"
}

function hasSwap() {
    [[ "$(sudo swapon -s)" == *"/swapfile"* ]]
}

function cleanup() {
    if [[ -f "/etc/sudoers.bak" ]]; then
        revertSudoers
    fi
}

function logTimestamp() {
    local filename=${1}
    {
        echo "===================" 
        echo "Log generated on $(date)"
        echo "==================="
    } >>"${filename}" 2>&1
}

function setupTimezone() {
    echo -ne "Enter the timezone for the server (Default is 'America/Toronto'):\n" >&3
    read -r timezone
    if [ -z "${timezone}" ]; then
        timezone="America/Toronto"
    fi
    setTimezone "${timezone}"
    echo "Timezone is set to $(cat /etc/timezone)" >&3
}

# Keep prompting for the password and password confirmation
function promptForPassword() {
   PASSWORDS_MATCH=0
   while [ "${PASSWORDS_MATCH}" -eq "0" ]; do
       read -s -rp "Enter new UNIX password:" password
       printf "\n"
       read -s -rp "Retype new UNIX password:" password_confirmation
       printf "\n"

       if [[ "${password}" != "${password_confirmation}" ]]; then
           echo "Passwords do not match! Please try again."
       else
           PASSWORDS_MATCH=1
       fi
   done 
}

function setupGit() {
  # Configure git
  git config --global color.ui true

  git config --global user.name "${git_name}"
  git config --global user.email "${git_email}"
}

function furtherHardening() {
  # restrict access to the server
  echo "AllowUsers ${username}" | sudo tee -a /etc/ssh/sshd_config

  # Secure Shared Memory
  # tip 6 at https://hostadvice.com/how-to/how-to-harden-your-ubuntu-18-04-server/
  echo "none /run/shm tmpfs defaults,ro 0 0" | sudo tee -a /etc/fstab
}

main