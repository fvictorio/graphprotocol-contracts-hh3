#!/bin/bash
set -e

cd "$(dirname "$0")/.."

# Dynamically determine the home directory of the current user
USER_HOME=$(eval echo ~"$USER")

# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
# source "$USER_HOME/.bashrc"
"$USER_HOME/.foundry/bin/foundryup"

# Install yarn, dependencies, and build the project
corepack enable

# Avoid yarn generating a prompt for corepack to install yarn
corepack prepare yarn@4.0.2 --activate

yarn
