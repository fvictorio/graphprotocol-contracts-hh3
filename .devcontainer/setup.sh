#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "Installing packages..."
corepack enable

curl -L https://foundry.paradigm.xyz | bash

# Dynamically determine the home directory of the current user
USER_HOME=$(eval echo ~"$USER")

# Source the user's .bashrc and run foundryup
# source "$USER_HOME/.bashrc"
"$USER_HOME/.foundry/bin/foundryup"
